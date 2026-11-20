--[[
	VANTAGE — CrateService (server): supply crates + real skin ownership (2026-11-16).
	  • Remotes.CrateOpen (RemoteFunction) crateId -> result table. The roll happens HERE; clients only animate.
	  • Ownership: DataStore "VantageSkinOwnership_v1", key "u_<UserId>" -> { V = 1, Owned = { ["Weapon/Skin"] = true }, Pity = { [crateId] = n }, Migrated = true }
	    Replicated as player attributes OwnedSkins ("Weapon/Skin,...") and CratePity_<Id> (opens since the last pity-tier drop).
	    Standard / Elite / Prime finishes stay free; only Skins.Ladder rarities (Rare+) need ownership (Skins.Owns).
	  • Migration: premium skins a player already had equipped before ownership existed are granted once.
	  • Duplicates refund REQ (CrateConfig.Refund). Pity: after Pity - 1 opens without the crate's PityTier or better, the next roll is forced to it.
	  • Studio: never saves (like Requisition). Test hooks: player attributes DevReqGrant = <REQ to add>, DevCrateForce = "<Rarity>".
]]
-- 2026-11-16b: buy now, open later. Remotes.CrateBuy(crateId, qty) spends REQ and adds owned crates;
--   Remotes.CrateOpen(crateId, count) now consumes owned crates (no REQ). Owned counts replicate as player attribute
--   OwnedCrates (JSON {Id = n}) and per-crate CrateOwned_<Id>.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Skins = require(Vantage:WaitForChild("Weapons"):WaitForChild("Skins"))
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local Requisition = require(script.Parent:WaitForChild("Requisition"))
local EquipCatalog = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local SHARDS = EquipCatalog.Shards or 3 -- 2026-11-17: equipment drops as shards; this many of one item unlock it
-- 2026-11-17: Arsenal Crates (Config.WeaponCrates) cost Ordnance and unlock a gun the player doesn't own yet.
--   Owned guns live in the same Owned table as "Weapon/<id>" and replicate as the attribute OwnedWeapons.
--   Grandfathering: players who already had account data (Level >= 2) when this shipped keep every gun once
--   (WeaponsMigrated flag; skipped in Studio so the crate can be tested).
local Ordnance = require(script.Parent:WaitForChild("Ordnance"))
local Unlocks = require(Vantage:WaitForChild("Weapons"):WaitForChild("WeaponUnlocks"))

local remotes = Vantage:WaitForChild("Remotes")
local Open = remotes:FindFirstChild("CrateOpen")
if not Open then
	Open = Instance.new("RemoteFunction")
	Open.Name = "CrateOpen"
	Open.Parent = remotes
end

local Buy = remotes:FindFirstChild("CrateBuy")
if not Buy then
	Buy = Instance.new("RemoteFunction")
	Buy.Name = "CrateBuy"
	Buy.Parent = remotes
end
local HttpService = game:GetService("HttpService")
local MAX_BUY = 99

local STORE = "VantageSkinOwnership_v1"
local SAVE = not RunService:IsStudio()
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local data: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}
local rng = Random.new()

local function key(p: Player): string
	return "u_" .. p.UserId
end

local function publish(p: Player)
	local d = data[p]
	if not d then
		return
	end
	local list, equip = {}, {}
	local guns = {}
	for k in d.Owned do
		if string.sub(k, 1, 7) == "Weapon/" then
			table.insert(guns, string.sub(k, 8))
		elseif string.sub(k, 1, 10) == "Equipment/" then
			table.insert(equip, string.sub(k, 11)) -- 2026-11-17: equipment shares the Owned table
		else
			table.insert(list, k)
		end
	end
	table.sort(list)
	table.sort(equip)
	p:SetAttribute("OwnedSkins", table.concat(list, ","))
	p:SetAttribute("OwnedEquipment", table.concat(equip, ","))
	table.sort(guns)
	p:SetAttribute("OwnedWeapons", table.concat(guns, ","))
	for _, group in { Config.Crates, Config.EquipmentCrates or {}, Config.WeaponCrates or {} } do
		for _, c in group do
			p:SetAttribute("CratePity_" .. c.Id, d.Pity[c.Id] or 0)
			p:SetAttribute("CrateOwned_" .. c.Id, d.Crates[c.Id] or 0)
		end
	end
	p:SetAttribute("OwnedCrates", HttpService:JSONEncode(d.Crates))
	p:SetAttribute("EquipShards", HttpService:JSONEncode(d.Shards or {}))
end

local function isPremium(w: string, s: string): boolean
	local def = Skins.Valid(w, s) and Skins.Get(w, s)
	return def ~= nil and def ~= false and Config.TierIndex[def.Rarity] ~= nil
end

-- one-time: premium skins equipped before ownership existed become owned
local function migrate(p: Player)
	local d = data[p]
	if not d or d.Migrated then
		return
	end
	local function grantEquipped()
		for _, w in Skins.Weapons do
			local s = p:GetAttribute("Skin_" .. w)
			if type(s) == "string" and isPremium(w, s) and not d.Owned[w .. "/" .. s] then
				d.Owned[w .. "/" .. s] = true
				dirty[p] = true
			end
		end
	end
	grantEquipped()
	-- LoadoutService may publish the saved selections a moment later
	local conn
	conn = p.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Skin_" then
			grantEquipped()
			publish(p)
		end
	end)
	task.delay(20, function()
		conn:Disconnect()
		d.Migrated = true
		dirty[p] = true
	end)
end

local function load(p: Player)
	local d = { V = 1, Owned = {}, Pity = {}, Crates = {}, Shards = {}, Migrated = false, WeaponsMigrated = false }
	if store then
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync(key(p))
		end)
		if ok and type(res) == "table" then
			d.Owned = type(res.Owned) == "table" and res.Owned or {}
			d.Pity = type(res.Pity) == "table" and res.Pity or {}
			d.Crates = type(res.Crates) == "table" and res.Crates or {}
			d.Shards = type(res.Shards) == "table" and res.Shards or {}
			d.Migrated = res.Migrated == true
			d.WeaponsMigrated = res.WeaponsMigrated == true
		elseif not ok then
			warn("[VANTAGE] Crates: ownership load failed:", res)
			d.LoadFailed = true -- never overwrite a store we couldn't read
		end
	end
	if not p.Parent then
		return
	end
	data[p] = d
	publish(p)
	migrate(p)
	task.spawn(function() -- grandfather existing players: everyone had every gun before Arsenal Crates
		if d.WeaponsMigrated or d.LoadFailed or RunService:IsStudio() then
			return
		end
		local t = os.clock()
		while p.Parent and p:GetAttribute("Level") == nil and os.clock() - t < 30 do
			task.wait(0.5)
		end
		if not p.Parent or data[p] ~= d or p:GetAttribute("Level") == nil then
			return -- try again next session
		end
		if (tonumber(p:GetAttribute("Level")) or 1) >= 2 then
			for _, w in Unlocks.CrateWeapons() do
				d.Owned["Weapon/" .. w.Id] = true
			end
		end
		d.WeaponsMigrated = true
		dirty[p] = true
		publish(p)
	end)
end

local function save(p: Player)
	local d = data[p]
	if not SAVE or not store or not d or not dirty[p] or d.LoadFailed then
		return
	end
	local owned, pity, mig, crates = table.clone(d.Owned), table.clone(d.Pity), d.Migrated, table.clone(d.Crates)
	local wmig = d.WeaponsMigrated
	local shards = table.clone(d.Shards or {})
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			local merged = type(old) == "table" and type(old.Owned) == "table" and old.Owned or {}
			for k in owned do
				merged[k] = true
			end
			return { V = 1, Owned = merged, Pity = pity, Crates = crates, Shards = shards, Migrated = mig or (type(old) == "table" and old.Migrated == true), WeaponsMigrated = wmig or (type(old) == "table" and old.WeaponsMigrated == true) }
		end)
	end)
	if ok then
		dirty[p] = nil
	else
		warn("[VANTAGE] Crates: ownership save failed (kept for the next try):", err)
	end
end

-- ─── the roll ─────────────────────────────────────────────────────────────────────────────
local function rollTier(crate, minTier: number?): string
	local entries, total = {}, 0
	for _, t in Config.Tiers do
		local w = crate.Odds[t]
		if w and w > 0 and Config.Count(t, crate) > 0 and (not minTier or Config.TierIndex[t] >= minTier) then
			table.insert(entries, { t, w })
			total += w
		end
	end
	local x = rng:NextNumber() * total
	for _, e in entries do
		x -= e[2]
		if x <= 0 then
			return e[1]
		end
	end
	return entries[#entries][1]
end

local function rollOne(p: Player, d, crate)
	local pityIdx = Config.TierIndex[crate.PityTier]
	local count = d.Pity[crate.Id] or 0
	local tier
	local forced = RunService:IsStudio() and p:GetAttribute("DevCrateForce")
	if type(forced) == "string" and crate.Odds[forced] and Config.Count(forced, crate) > 0 then
		tier = forced
	elseif count >= crate.Pity - 1 then
		tier = rollTier(crate, pityIdx)
	else
		tier = rollTier(crate)
	end
	local list = Config.Pool(crate).ByTier[tier]
	local e = list[rng:NextInteger(1, #list)]
	local dup = d.Owned[e.Key] == true
	local refund = 0
	local shards, unlocked
	if dup then
		refund = Config.Refund[tier] or 0
	elseif e.Kind == "Equipment" then
		-- equipment drops as a shard; SHARDS of the same item unlock it
		d.Shards = d.Shards or {}
		local id = e.Id or e.Skin
		shards = math.min(SHARDS, (d.Shards[id] or 0) + 1)
		if shards >= SHARDS then
			d.Owned[e.Key] = true
			d.Shards[id] = nil
			unlocked = true
		else
			d.Shards[id] = shards
		end
	else
		d.Owned[e.Key] = true
	end
	d.Pity[crate.Id] = if Config.TierIndex[tier] >= pityIdx then 0 else count + 1
	-- 2026-11-18: a skin for a gun the player hasn't unlocked yet is still kept; the reveal shows a lock and
	-- the inventory lists it once the gun is unlocked (Arsenal Crates)
	local gunLocked = (e.Kind == nil or e.Kind == "Skin") and Unlocks.ById[e.Weapon] ~= nil
		and not Unlocks.Owns(e.Weapon, p:GetAttribute("Level"), p:GetAttribute("OwnedWeapons"))
	return { Weapon = e.Weapon, Skin = e.Skin, Rarity = tier, Name = e.Name, Dup = dup, Refund = refund, Kind = e.Kind or "Skin", Slot = e.Slot, Id = e.Id, Key = e.Key, Shards = shards, Need = if e.Kind == "Equipment" then SHARDS else nil, Unlocked = unlocked == true, GunLocked = gunLocked }
end

-- Arsenal Crate: a random gun the player doesn't own yet, unlocked now (equal chance per gun)
local function rollWeapon(p: Player, d, crate)
	local missing = {}
	for _, e in Config.Pool(crate).All do
		if not d.Owned[e.Key] then
			table.insert(missing, e)
		end
	end
	if #missing == 0 then
		-- nothing left to unlock (only possible with crates bought before every gun was owned): refund the ORD
		Ordnance.Credit(p, crate.Price)
		local e = Config.Pool(crate).All[1]
		return { Kind = "Weapon", Weapon = e.Weapon, Skin = e.Skin, Id = e.Id, Name = e.Name, Rarity = e.Rarity, Key = e.Key, Dup = true, Refund = 0, RefundOrd = crate.Price, Unlocked = false }
	end
	local e = missing[rng:NextInteger(1, #missing)]
	d.Owned[e.Key] = true
	return { Kind = "Weapon", Weapon = e.Weapon, Skin = e.Skin, Id = e.Id, Name = e.Name, Rarity = e.Rarity, Class = e.Class, Key = e.Key, Dup = false, Refund = 0, Unlocked = true, Left = #missing - 1 }
end

-- crateId, count (1 or 5) -> { Ok, Results = { ... }, <best result's fields>, Balance }
local function openCrate(p: Player, crateId, count)
	local crate = type(crateId) == "string" and Config.ById[crateId]
	if not crate then
		return { Ok = false, Error = "Unknown crate" }
	end
	count = if count == 5 then 5 else 1
	local d = data[p]
	if not d then
		return { Ok = false, Error = "Loading" }
	end
	if (d.Crates[crate.Id] or 0) < count then
		return { Ok = false, Error = "No crates to open" }
	end
	if busy[p] then
		return { Ok = false, Error = "Busy" }
	end
	busy[p] = true
	local ok, res = pcall(function()
		d.Crates[crate.Id] = (d.Crates[crate.Id] or 0) - count
		if d.Crates[crate.Id] <= 0 then
			d.Crates[crate.Id] = nil
		end
		local results, best, refund = {}, 1, 0
		for i = 1, count do
			local r = if Config.IsWeaponCrate(crate) then rollWeapon(p, d, crate) else rollOne(p, d, crate)
			results[i] = r
			refund += r.Refund
			if Config.TierIndex[r.Rarity] > Config.TierIndex[results[best].Rarity] then
				best = i
			end
		end
		if refund > 0 then
			Requisition.Credit(p, refund)
		end
		dirty[p] = true
		publish(p)
		local out = table.clone(results[best])
		out.Ok, out.Results, out.Best, out.Count, out.Pity, out.Balance = true, results, best, count, d.Pity[crate.Id], Requisition.Balance(p)
		out.Ord = Ordnance.Balance(p)
		return out
	end)
	busy[p] = nil
	if not ok then
		warn("[VANTAGE] Crates: open failed:", res)
		return { Ok = false, Error = "Server error" }
	end
	return res
end

Open.OnServerInvoke = openCrate

-- crateId, qty (1..99) -> { Ok, Owned, Balance }
Buy.OnServerInvoke = function(p: Player, crateId, qty)
	local crate = type(crateId) == "string" and Config.ById[crateId]
	if not crate then
		return { Ok = false, Error = "Unknown crate" }
	end
	qty = math.floor(tonumber(qty) or 0)
	if qty < 1 or qty > MAX_BUY then
		return { Ok = false, Error = "Bad quantity" }
	end
	local d = data[p]
	if not d then
		return { Ok = false, Error = "Loading" }
	end
	if busy[p] then
		return { Ok = false, Error = "Busy" }
	end
	busy[p] = true
	local ok, res = pcall(function()
		if Config.IsWeaponCrate(crate) then
			local left = 0
			for _, e in Config.Pool(crate).All do
				if not d.Owned[e.Key] then left += 1 end
			end
			left -= (d.Crates[crate.Id] or 0)
			if left <= 0 then
				return { Ok = false, Error = "You already have every gun" }
			end
			if qty > left then
				return { Ok = false, Error = string.format("Only %d gun%s left to unlock", left, if left == 1 then "" else "s") }
			end
			if not Ordnance.Spend(p, crate.Price * qty) then
				return { Ok = false, Error = "Not enough ORD" }
			end
		elseif not Requisition.Spend(p, crate.Price * qty) then
			return { Ok = false, Error = "Not enough REQ" }
		end
		d.Crates[crate.Id] = (d.Crates[crate.Id] or 0) + qty
		dirty[p] = true
		publish(p)
		return { Ok = true, Owned = d.Crates[crate.Id], Balance = Requisition.Balance(p), Ord = Ordnance.Balance(p) }
	end)
	busy[p] = nil
	if not ok then
		warn("[VANTAGE] Crates: buy failed:", res)
		return { Ok = false, Error = "Server error" }
	end
	return res
end

-- server-only grant hook for ShopService: CrateGrant:Invoke(player, { Apex = 1, ... }) -> true once applied
local Grant = script.Parent:FindFirstChild("CrateGrant") or Instance.new("BindableFunction")
Grant.Name = "CrateGrant"
Grant.Parent = script.Parent
Grant.OnInvoke = function(p: Player, crates, skins)
	local d = data[p]
	crates = crates or {}
	if not (d and type(crates) == "table") then
		return false
	end
	local valid = {}
	for _, list in Config.Pool().ByTier do
		for _, e in list do valid[e.Key] = true end
	end
	for _, list in (Config.EquipmentPool and Config.EquipmentPool().ByTier or {}) do
		for _, e in list do valid[e.Key] = true end -- "Equipment/<Id>"
	end
	for _, k in skins or {} do
		if not valid[k] then return false end
	end
	for id, n in crates do
		if not Config.ById[id] or (tonumber(n) or 0) <= 0 then
			return false
		end
	end
	for id, n in crates do
		d.Crates[id] = (d.Crates[id] or 0) + math.floor(n)
	end
	local dupes = {}
	for _, k in skins or {} do
		if d.Owned[k] then table.insert(dupes, k) else d.Owned[k] = true end
	end
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
	return true, dupes
end

-- 2026-11-18: server-only dev hook used by DevChatCommands /allskins. DevGrantAll:Invoke(player) -> gunCount, skinCount
local DevAll = script.Parent:FindFirstChild("DevGrantAll") or Instance.new("BindableFunction")
DevAll.Name = "DevGrantAll"
DevAll.Parent = script.Parent
DevAll.OnInvoke = function(p: Player)
	local d = data[p]
	if not d then
		return false
	end
	local guns, skins = 0, 0
	for _, w in Unlocks.CrateWeapons() do
		if not d.Owned["Weapon/" .. w.Id] then
			d.Owned["Weapon/" .. w.Id] = true
			guns += 1
		end
	end
	for _, w in Skins.Weapons do
		local ok, list = pcall(Skins.List, w)
		for _, s in (ok and list or {}) do
			local id = s.Id or s.id
			if id and isPremium(w, id) and not d.Owned[w .. "/" .. id] then
				d.Owned[w .. "/" .. id] = true
				skins += 1
			end
		end
	end
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
	return guns, skins
end

-- 2026-11-20: admin panel hook (ServerScriptService.VantageAdminPanel).
-- AdminGrantKeys:Invoke(player, { "Weapon/Helix", "Vanguard/EventHorizon", ... }) -> number added (false while loading)
local AdminKeys = script.Parent:FindFirstChild("AdminGrantKeys") or Instance.new("BindableFunction")
AdminKeys.Name = "AdminGrantKeys"
AdminKeys.Parent = script.Parent
AdminKeys.OnInvoke = function(p: Player, keys)
	local d = data[p]
	if not (d and type(keys) == "table") then
		return false
	end
	local valid = {}
	for _, list in Config.Pool().ByTier do
		for _, e in list do valid[e.Key] = true end
	end
	for _, w in Unlocks.CrateWeapons() do
		valid["Weapon/" .. w.Id] = true
	end
	local added = 0
	for _, k in keys do
		if valid[k] and not d.Owned[k] then
			d.Owned[k] = true
			added += 1
		end
	end
	if added > 0 then
		dirty[p] = true
		publish(p)
		task.spawn(save, p)
	end
	return added
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p], dirty[p], busy[p] = nil, nil, nil
end)
task.spawn(function()
	while true do
		task.wait(60)
		for p in dirty do
			task.spawn(save, p)
		end
	end
end)
game:BindToClose(function()
	if not SAVE or not store then
		return
	end
	local n = 0
	for p in dirty do
		n += 1
		task.spawn(function()
			save(p)
			n -= 1
		end)
	end
	local t = os.clock()
	while n > 0 and os.clock() - t < 20 do
		task.wait(0.1)
	end
end)

if RunService:IsStudio() then
	local function hook(p: Player)
		p:GetAttributeChangedSignal("DevReqGrant"):Connect(function()
			local n = tonumber(p:GetAttribute("DevReqGrant"))
			if n and n > 0 then
				Requisition.Award(p, { { Label = "DEV GRANT", Amount = n, Kind = "Dev" } })
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end
