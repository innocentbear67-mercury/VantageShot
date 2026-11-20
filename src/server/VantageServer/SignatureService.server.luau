--[[
	VANTAGE — SignatureService (server) — 2026-11-19
	Ichor balance + owned Signatures + the equipped Signature.
	  • DataStore "VantageSignatures_v1", key "u_<UserId>" -> { V = 1, Ichor = n, Owned = { id, … }, Equipped = id }
	  • attributes: Ichor, OwnedSignatures ("a,b,c"), Signature (equipped id)
	  • Remotes.SignatureEquip(id) -> Remotes.SignatureResult(ok, id, reason, "Equip")
	  • Remotes.SignatureBuy(id)   -> Remotes.SignatureResult(ok, id, reason, "Buy")  (price from SignatureCatalog, paid in Ichor)
	  • ServerStorage.SignatureAPI (BindableFunction): ("AddIchor", player, n, reason) / ("Grant", player, id) / ("Get", player)
	Studio sessions (dev convenience, never saved): 2,500 Ichor shown (well short of any price), all Signatures owned except Midgard, Helheim
	and Yggdrasil so both owned and locked cards can be checked.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Catalog = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureCatalog"))
local Remotes = Vantage:WaitForChild("Remotes")
local function remote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = Remotes end
	return r
end
local EquipEv, BuyEv, Result = remote("SignatureEquip"), remote("SignatureBuy"), remote("SignatureResult")
-- 2026-11-19: ICHOR FARM (the Well). Remotes.IchorFarm:InvokeServer(action) with action "Claim" | "Upgrade" | "Seen".
local IchorCfg = require(Vantage:WaitForChild("Ichor"):WaitForChild("IchorConfig"))
local WELL = IchorCfg.Well
local Requisition = require(script.Parent:WaitForChild("Requisition"))
local FarmFn = Remotes:FindFirstChild("IchorFarm")
if not FarmFn then FarmFn = Instance.new("RemoteFunction"); FarmFn.Name = "IchorFarm"; FarmFn.Parent = Remotes end

local store
do
	local ok, s = pcall(function() return DataStoreService:GetDataStore("VantageSignatures_v1") end)
	if ok then store = s end
end
local STUDIO = RunService:IsStudio()
local DEV_LOCKED = {} -- Studio owns every Signature for testing; put ids back here (e.g. Midgard = true) to test the Ichor crate

local data, dirty, loaded, last = {}, {}, {}, {}

local function publish(p)
	local d = data[p]
	if not d then return end
	local owned = {}
	for _, it in Catalog.List do
		if it.Free or table.find(d.Owned, it.Id) or (STUDIO and not DEV_LOCKED[it.Id]) then owned[#owned + 1] = it.Id end
	end
	p:SetAttribute("OwnedSignatures", table.concat(owned, ","))
	p:SetAttribute("Ichor", d.Ichor + (STUDIO and 2500 or 0))
	local eq = d.Equipped
	if not (Catalog.Valid(eq) and table.find(owned, eq)) then eq = Catalog.Default end
	p:SetAttribute("Signature", eq)
	local w = d.Well
	p:SetAttribute("FarmLevel", w.L)
	p:SetAttribute("FarmStored", w.S) -- Ichor stored at time FarmT (os.time); the client extrapolates
	p:SetAttribute("FarmT", w.T)
	p:SetAttribute("FarmCine", d.Cine or 0) -- day number of the last full cutscene
end

-- the Well: stored Ichor right now (fractional), capped
local function wellRate(L) return WELL.Rate[L] or WELL.Rate[#WELL.Rate] end
local function wellCap(L) return wellRate(L) * (WELL.Cap[L] or WELL.Cap[#WELL.Cap]) end
local function wellNow(w, now)
	return math.min(wellCap(w.L), w.S + wellRate(w.L) * math.max(0, now - w.T) / 3600)
end
local function settle(w, now)
	w.S = wellNow(w, now)
	w.T = now
end

local function load(p)
	local d = { V = 1, Ichor = 0, Owned = {}, Equipped = Catalog.Default, Well = { L = 1, S = WELL.StartStored, T = os.time() }, Cine = 0 }
	if store then
		local ok, res = pcall(function() return store:GetAsync("u_" .. p.UserId) end)
		if ok and type(res) == "table" then
			if type(res.Ichor) == "number" and res.Ichor >= 0 then d.Ichor = math.floor(res.Ichor) end
			if type(res.Owned) == "table" then
				for _, id in res.Owned do if Catalog.Valid(id) and not table.find(d.Owned, id) then d.Owned[#d.Owned + 1] = id end end
			end
			if Catalog.Valid(res.Equipped) then d.Equipped = res.Equipped end
			local w = res.Well
			if type(w) == "table" and type(w.L) == "number" and type(w.S) == "number" and type(w.T) == "number" then
				d.Well = { L = math.clamp(math.floor(w.L), 1, #WELL.Rate), S = math.max(0, w.S), T = math.min(w.T, os.time()) }
			end
			if type(res.Cine) == "number" then d.Cine = res.Cine end
		elseif not ok then
			warn("[VANTAGE] SignatureService: load failed:", res)
		end
	end
	if p.Parent then
		data[p] = d
		loaded[p] = true
		publish(p)
	end
end

local function save(p)
	local d = data[p]
	if not (store and d and dirty[p] and loaded[p]) then return end
	dirty[p] = nil
	local rec = { V = 1, Ichor = math.max(0, d.Ichor), Owned = d.Owned, Equipped = d.Equipped, Well = d.Well, Cine = d.Cine }
	local ok, err = pcall(function() store:SetAsync("u_" .. p.UserId, rec, { p.UserId }) end)
	if not ok then dirty[p] = true; warn("[VANTAGE] SignatureService: save failed:", err) end
end

local function owns(p, id)
	local s = p:GetAttribute("OwnedSignatures")
	return Catalog.ById[id] and (Catalog.ById[id].Free or (type(s) == "string" and table.find(string.split(s, ","), id) ~= nil))
end

EquipEv.OnServerEvent:Connect(function(p, id)
	local now = os.clock()
	if now - (last[p] or 0) < 0.15 then return end
	last[p] = now
	if not Catalog.Valid(id) then return end
	local d = data[p]
	if not d then Result:FireClient(p, false, id, "Loading", "Equip") return end
	if not owns(p, id) then Result:FireClient(p, false, id, "Not owned", "Equip") return end
	d.Equipped = id
	dirty[p] = true
	p:SetAttribute("Signature", id)
	Result:FireClient(p, true, id, nil, "Equip")
end)

BuyEv.OnServerEvent:Connect(function(p, id)
	local now = os.clock()
	if now - (last[p] or 0) < 0.3 then return end
	last[p] = now
	if not Catalog.Valid(id) then return end
	local d = data[p]
	if not d then Result:FireClient(p, false, id, "Loading", "Buy") return end
	if owns(p, id) then Result:FireClient(p, false, id, "Already owned", "Buy") return end
	if not table.find((Catalog.DailyToday(os.time())), id) then Result:FireClient(p, false, id, "Not in today's Daily Shop", "Buy") return end
	local price = Catalog.ById[id].Price
	local bal = d.Ichor + (STUDIO and 2500 or 0)
	if bal < price then Result:FireClient(p, false, id, "Not enough Ichor", "Buy") return end
	d.Ichor -= price -- (Studio: may go negative against the dev bonus; publish clamps the shown value)
	if d.Ichor < 0 and not STUDIO then d.Ichor = 0 end
	table.insert(d.Owned, id)
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
	Result:FireClient(p, true, id, nil, "Buy")
end)

-- 2026-11-20: ICHOR CRATE. Remotes.IchorCrate:InvokeServer() -> { Ok, Id, Left, Ichor } | { Ok = false, Error }
-- Rolls only Signatures the player doesn't own (never a duplicate), weighted per Signature by tier (Catalog.Crate.Weights).
local CrateFn = Remotes:FindFirstChild("IchorCrate")
if not CrateFn then CrateFn = Instance.new("RemoteFunction"); CrateFn.Name = "IchorCrate"; CrateFn.Parent = Remotes end
local crateRng = Random.new()
CrateFn.OnServerInvoke = function(p)
	local now0 = os.clock()
	if now0 - (last[p] or 0) < 0.4 then return { Ok = false, Error = "Slow down" } end
	last[p] = now0
	local d = data[p]
	if not d then return { Ok = false, Error = "Loading" } end
	local ownedSet = {}
	for _, it in Catalog.List do if owns(p, it.Id) then ownedSet[it.Id] = true end end
	local _, list, left = Catalog.CrateOdds(ownedSet)
	if left == 0 then return { Ok = false, Error = "You own every Signature" } end
	local price = Catalog.Crate.Price
	if d.Ichor + (STUDIO and 2500 or 0) < price then return { Ok = false, Error = "Not enough Ichor" } end
	d.Ichor -= price
	if d.Ichor < 0 and not STUDIO then d.Ichor = 0 end
	local x, pick = crateRng:NextNumber(), list[#list].Id
	for _, e in list do
		x -= e.Chance
		if x <= 0 then pick = e.Id break end
	end
	table.insert(d.Owned, pick)
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
	return { Ok = true, Id = pick, Left = left - 1, Ichor = p:GetAttribute("Ichor") }
end

-- ICHOR FARM
FarmFn.OnServerInvoke = function(p, action)
	local now0 = os.clock()
	if now0 - (last[p] or 0) < 0.25 then return { Ok = false, Error = "Slow down" } end
	last[p] = now0
	local d = data[p]
	if not d then return { Ok = false, Error = "Loading" } end
	local w, now = d.Well, os.time()
	if action == "Claim" then
		local have = wellNow(w, now)
		local n = math.floor(have)
		if n < WELL.MinClaim then return { Ok = false, Error = "The cauldron is empty" } end
		w.S, w.T = have - n, now
		d.Ichor += n
		dirty[p] = true
		publish(p)
		return { Ok = true, Amount = n, Ichor = p:GetAttribute("Ichor") }
	elseif action == "Upgrade" then
		local cost = WELL.UpgradeCost[w.L]
		if not cost then return { Ok = false, Error = "The Well is at max level" } end
		if not Requisition.Spend(p, cost) then return { Ok = false, Error = "Not enough REQ" } end
		settle(w, now)
		w.L += 1
		dirty[p] = true
		publish(p)
		return { Ok = true, Level = w.L, Cost = cost }
	elseif action == "Seen" then -- the full launch cutscene played today
		d.Cine = now // 86400
		dirty[p] = true
		p:SetAttribute("FarmCine", d.Cine)
		return { Ok = true }
	end
	return { Ok = false, Error = "Unknown action" }
end

-- server API for other services (match rewards, shop, admin)
local api = ServerStorage:FindFirstChild("SignatureAPI") or Instance.new("BindableFunction")
api.Name = "SignatureAPI"; api.Parent = ServerStorage
api.OnInvoke = function(action, p, a, reason)
	local d = data[p]
	if not d then return nil end
	if action == "AddIchor" and type(a) == "number" then
		d.Ichor = math.max(0, d.Ichor + math.floor(a)); dirty[p] = true; publish(p)
		if reason == "Purchase" then task.spawn(save, p) end -- Robux purchases save at once
		return d.Ichor
	elseif action == "Grant" and Catalog.Valid(a) then
		if not table.find(d.Owned, a) then table.insert(d.Owned, a); dirty[p] = true; publish(p) end
		return true
	elseif action == "Get" then
		return { Ichor = d.Ichor, Owned = table.clone(d.Owned), Equipped = d.Equipped }
	end
	return nil
end

-- the player's avatar rig for the Farm cutscene (lobby players may have no character)
local AvatarFolder = IchorCfg and Vantage.Ichor:FindFirstChild("Avatars")
if not AvatarFolder then AvatarFolder = Instance.new("Folder"); AvatarFolder.Name = "Avatars"; AvatarFolder.Parent = Vantage.Ichor end
local function buildAvatar(p)
	local ok, rig = pcall(function() return Players:CreateHumanoidModelFromUserId(math.max(1, p.UserId)) end)
	if not ok or not rig then
		ok, rig = pcall(function() return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15) end)
	end
	if not (ok and rig) or not p.Parent then return end
	rig.Name = "u_" .. p.UserId
	for _, d in rig:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
	local old = AvatarFolder:FindFirstChild(rig.Name)
	if old then old:Destroy() end
	rig.Parent = AvatarFolder
end

local function onPlayer(p)
	p:SetAttribute("Signature", Catalog.Default)
	task.spawn(buildAvatar, p)
	load(p)
	if STUDIO then
		p:GetAttributeChangedSignal("DevFarmHours"):Connect(function()
			local h, d = tonumber(p:GetAttribute("DevFarmHours")), data[p]
			if h and d then
				settle(d.Well, os.time())
				d.Well.S = math.min(wellCap(d.Well.L), d.Well.S + wellRate(d.Well.L) * h)
				publish(p)
			end
		end)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end
Players.PlayerRemoving:Connect(function(p)
	local av = AvatarFolder:FindFirstChild("u_" .. p.UserId)
	if av then av:Destroy() end
	save(p)
	data[p], dirty[p], loaded[p], last[p] = nil, nil, nil, nil
end)
task.spawn(function()
	while true do
		task.wait(30)
		for p in dirty do task.spawn(save, p) end
	end
end)
game:BindToClose(function()
	local n = 0
	for p in dirty do n += 1; task.spawn(function() save(p); n -= 1 end) end
	local t = os.clock()
	while n > 0 and os.clock() - t < 15 do task.wait(0.1) end
end)
