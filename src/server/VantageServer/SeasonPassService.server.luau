--[[
	SeasonPassService - VantageShot Season Pass (server), 2026-11-17.
	- Pass XP mirrors match XP: Progression.AddXP fires the PassXP BindableEvent. 1 tier = PassConfig.TierXP.
	- DataStore "VantageSeasonPass_v1", key "u_<UserId>" -> { Season, XP, Premium, F = {tier=true}, P = {tier=true} }.
	  A new PassConfig.Season starts everyone fresh. Studio playtests never write (same rule as REQ).
	- Replicated attributes: PassSeason, PassXP, PassTier, PassPremium, PassClaimed ("f1,f2|p1").
	- Remotes.PassClaim(track "Free"|"Premium", tier) or ("All") -> { Ok, Granted = {labels}, Error }.
	  Crates / skins go through CrateGrant (atomic), REQ through Requisition.Award (Kind "Purchase", no boosts).
	  Premium-track crates become REQ for players restricted from paid random items.
	- PassGrant BindableFunction (ShopService receipts): { Premium = true } / { Skips = n } / { SkipAll = true }.
	- Studio hooks (player attributes): DevPassXP = n (adds XP), DevPassPremium = true, DevPassReset = true.
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PolicyService = game:GetService("PolicyService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Pass = require(Vantage:WaitForChild("SeasonPass"):WaitForChild("PassConfig"))
local CrateConfig = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local Requisition = require(script.Parent:WaitForChild("Requisition"))
local CrateGrant = script.Parent:WaitForChild("CrateGrant", 60)
local remotes = require(Vantage:WaitForChild("RemotesLib"))

local SAVE = not RunService:IsStudio()
local store
pcall(function() store = DataStoreService:GetDataStore("VantageSeasonPass_v1") end)

local data, dirty, busy, restrictedCache = {}, {}, {}, {}
local function key(p) return "u_" .. p.UserId end
local function now() return os.time() end

local function restricted(p)
	if restrictedCache[p] == nil then
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, p)
		restrictedCache[p] = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == true or false
	end
	return restrictedCache[p]
end

local function fresh()
	return { Season = Pass.Season, XP = 0, Premium = false, F = {}, P = {} }
end

local function publish(p)
	local d = data[p]
	if not d then return end
	local tier = Pass.TierOf(d.XP)
	local f, q = {}, {}
	for t in d.F do table.insert(f, tostring(t)) end
	for t in d.P do table.insert(q, tostring(t)) end
	table.sort(f, function(a, b) return tonumber(a) < tonumber(b) end)
	table.sort(q, function(a, b) return tonumber(a) < tonumber(b) end)
	p:SetAttribute("PassSeason", Pass.Season)
	p:SetAttribute("PassXP", d.XP)
	p:SetAttribute("PassTier", tier)
	p:SetAttribute("PassPremium", d.Premium)
	p:SetAttribute("PassClaimed", table.concat(f, ",") .. "|" .. table.concat(q, ","))
end

local function save(p)
	local d = data[p]
	if not (SAVE and store and d and dirty[p]) then return end
	dirty[p] = nil
	local out = { Season = d.Season, XP = d.XP, Premium = d.Premium, F = {}, P = {} }
	for t in d.F do table.insert(out.F, t) end
	for t in d.P do table.insert(out.P, t) end
	local ok, err = pcall(function() store:SetAsync(key(p), out) end)
	if not ok then
		dirty[p] = true
		warn("[VANTAGE] SeasonPass save failed:", err)
	end
end

local function load(p)
	local d = fresh()
	if SAVE and store then
		local ok, res = pcall(function() return store:GetAsync(key(p)) end)
		if ok and type(res) == "table" and res.Season == Pass.Season then
			d.XP = math.max(0, math.floor(tonumber(res.XP) or 0))
			d.Premium = res.Premium == true
			for _, t in res.F or {} do d.F[t] = true end
			for _, t in res.P or {} do d.P[t] = true end
		elseif not ok then
			warn("[VANTAGE] SeasonPass load failed:", res)
		end
	end
	if not p.Parent then return end
	data[p] = d
	publish(p)
end

local function addXP(p, amount)
	local d = data[p]
	amount = math.floor(tonumber(amount) or 0)
	if not d or amount <= 0 or now() >= Pass.EndsAt then return end
	local cap = Pass.MaxTier * Pass.TierXP
	if d.XP >= cap then return end
	d.XP = math.min(cap, d.XP + amount)
	dirty[p] = true
	publish(p)
end

-- one reward -> crates / skins / REQ buckets
local function collect(p, rw, premium, acc)
	if rw.Kind == "REQ" then
		acc.Req += rw.Amount
	elseif rw.Kind == "Crate" then
		if premium and restricted(p) then
			acc.Req += (CrateConfig.ById[rw.Id] and CrateConfig.ById[rw.Id].Price or 0) * rw.Count
		else
			acc.Crates[rw.Id] = (acc.Crates[rw.Id] or 0) + rw.Count
		end
	elseif rw.Kind == "Skin" then
		table.insert(acc.Skins, rw.Key)
	end
	table.insert(acc.Labels, Pass.Label(rw))
end

local rarityOf = {}
for _, list in CrateConfig.Pool().ByTier do
	for _, e in list do rarityOf[e.Key] = e.Rarity end
end

local function claim(p, list)
	local d = data[p]
	if not d then return { Ok = false, Error = "Loading" } end
	local tier = Pass.TierOf(d.XP)
	local acc = { Req = 0, Crates = {}, Skins = {}, Labels = {} }
	local marks = {}
	for _, it in list do
		local t, track = it[2], it[1]
		local row = Pass.Tiers[t]
		if row and t <= tier then
			if track == "Free" and not d.F[t] then
				collect(p, row.Free, false, acc)
				table.insert(marks, { "F", t })
			elseif track == "Premium" and d.Premium and not d.P[t] then
				collect(p, row.Premium, true, acc)
				table.insert(marks, { "P", t })
			end
		end
	end
	if #marks == 0 then return { Ok = false, Error = "Nothing to claim" } end
	local note
	if next(acc.Crates) or #acc.Skins > 0 then
		if not CrateGrant then return { Ok = false, Error = "Server busy" } end
		local ok, res, dupes = pcall(function() return CrateGrant:Invoke(p, acc.Crates, acc.Skins) end)
		if not (ok and res) then return { Ok = false, Error = "Server busy" } end
		for _, k in (type(dupes) == "table" and dupes or {}) do
			local add = Pass.DupeReq[rarityOf[k] or "Epic"] or 2500
			acc.Req += add
			note = "Skin already owned: REQ instead"
		end
	end
	for _, m in marks do d[m[1]][m[2]] = true end
	if acc.Req > 0 then
		Requisition.Award(p, { { Label = "SEASON PASS", Amount = acc.Req, Kind = "Purchase" } })
		task.spawn(function() pcall(Requisition.Flush, p) end)
	end
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
	return { Ok = true, Granted = acc.Labels, Note = note, Count = #marks }
end

local Claim = remotes.get("PassClaim", "RemoteFunction") :: RemoteFunction
Claim.OnServerInvoke = function(p, track, tier)
	if busy[p] then return { Ok = false, Error = "Busy" } end
	busy[p] = true
	local ok, res = pcall(function()
		local d = data[p]
		if not d then return { Ok = false, Error = "Loading" } end
		local list = {}
		if track == "All" then
			local top = Pass.TierOf(d.XP)
			for t = 1, top do
				table.insert(list, { "Free", t })
				table.insert(list, { "Premium", t })
			end
		elseif (track == "Free" or track == "Premium") and type(tier) == "number" then
			table.insert(list, { track, math.floor(tier) })
		end
		return claim(p, list)
	end)
	busy[p] = nil
	if not ok then
		warn("[VANTAGE] SeasonPass claim failed:", res)
		return { Ok = false, Error = "Server error" }
	end
	return res
end

-- XP feed from Progression.AddXP
local XPEv = script.Parent:FindFirstChild("PassXP") or Instance.new("BindableEvent")
XPEv.Name = "PassXP"
XPEv.Parent = script.Parent
XPEv.Event:Connect(addXP)

-- ShopService receipts
local Grant = script.Parent:FindFirstChild("PassGrant") or Instance.new("BindableFunction")
Grant.Name = "PassGrant"
Grant.Parent = script.Parent
Grant.OnInvoke = function(p, g)
	local d = data[p]
	if not (d and type(g) == "table") then return false end
	local cap = Pass.MaxTier * Pass.TierXP
	if g.Premium then d.Premium = true end
	if g.SkipAll then
		d.XP = cap
	elseif tonumber(g.Skips) then
		-- a skip moves you to the start of a later tier (keeps nothing past the cap)
		local t = Pass.TierOf(d.XP)
		d.XP = math.min(cap, math.max(d.XP + g.Skips * Pass.TierXP, (t + g.Skips) * Pass.TierXP))
	end
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
	return true
end

Players.PlayerAdded:Connect(function(p)
	load(p)
	if RunService:IsStudio() then
		p:GetAttributeChangedSignal("DevPassXP"):Connect(function()
			local n = tonumber(p:GetAttribute("DevPassXP"))
			if n and n > 0 then
				p:SetAttribute("DevPassXP", nil)
				addXP(p, n)
			end
		end)
		p:GetAttributeChangedSignal("DevPassPremium"):Connect(function()
			if p:GetAttribute("DevPassPremium") and data[p] then
				data[p].Premium = true
				publish(p)
			end
		end)
		p:GetAttributeChangedSignal("DevPassReset"):Connect(function()
			if p:GetAttribute("DevPassReset") then
				p:SetAttribute("DevPassReset", nil)
				data[p] = fresh()
				publish(p)
			end
		end)
	end
end)
for _, p in Players:GetPlayers() do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p], dirty[p], busy[p], restrictedCache[p] = nil, nil, nil, nil
end)
task.spawn(function()
	while true do
		task.wait(60)
		for p in dirty do task.spawn(save, p) end
	end
end)
game:BindToClose(function()
	if not (SAVE and store) then return end
	for p in data do task.spawn(save, p) end
	task.wait(2)
end)
