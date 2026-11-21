--!nonstrict
--[[
	VANTAGE — Admin Panel (server, 2026-11-20)
	Owner-only panel. Client: StarterPlayerScripts.VantageAdminPanelClient (F2 or the ADMIN button, bottom-left).
	Every request is checked HERE: only ADMINS can do anything (plus anyone in a Studio playtest).
	Grants persist (REQ as Kind "Purchase", Ichor saves at once, skins/guns/crates save at once).

	Remotes (ReplicatedStorage): VantageAdminPanel (RemoteFunction), VantageAdminAnnounce (RemoteEvent).
	Target = "ALL" or a UserId. Actions: Catalog, REQ, ORD, ICHOR, XP, MASTERY, SKIN, ALLSKINS, GUN, ALLGUNS,
	SIG, CRATE, PASS_PREMIUM, PASS_TIERS, PASS_MAX, HEAL, KILL, KICK, BRING, GOTO, ANNOUNCE.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local ADMINS = { [11707170334] = true } -- add more UserIds here if needed

local function isAdmin(p: Player): boolean
	return p ~= nil and (ADMINS[p.UserId] == true or RunService:IsStudio())
end

local VS = script.Parent:WaitForChild("VantageServer")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Req = require(VS:WaitForChild("Requisition"))
local Ord = require(VS:WaitForChild("Ordnance"))
local Prog = require(VS:WaitForChild("Progression"))
local Mastery = require(VS:WaitForChild("Mastery"))
local CrateCfg = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local Unlocks = require(Vantage:WaitForChild("Weapons"):WaitForChild("WeaponUnlocks"))
local SigCat = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureCatalog"))
local MasteryCfg = require(Vantage:WaitForChild("Mastery"):WaitForChild("MasteryConfig"))

local function hook(name: string)
	return VS:FindFirstChild(name) or VS:WaitForChild(name, 10)
end

local Remotes = require(Vantage:WaitForChild("RemotesLib"))
local Fn = Remotes.get("VantageAdminPanel", "RemoteFunction", ReplicatedStorage) :: RemoteFunction
local Announce = Remotes.get("VantageAdminAnnounce", "RemoteEvent", ReplicatedStorage) :: RemoteEvent

-- static catalog for the client lists
local catalogCache
local function catalog()
	if catalogCache then return catalogCache end
	local byWeapon, weapons = {}, {}
	for _, list in CrateCfg.Pool().ByTier do
		for _, e in list do
			if e.Weapon and e.Key and not string.find(e.Key, "^Weapon/") and not string.find(e.Key, "^Equipment/") then
				if not byWeapon[e.Weapon] then
					byWeapon[e.Weapon] = {}
					table.insert(weapons, e.Weapon)
				end
				table.insert(byWeapon[e.Weapon], { Key = e.Key, Name = e.Name or e.Skin, Rarity = e.Rarity })
			end
		end
	end
	table.sort(weapons)
	for _, list in byWeapon do
		table.sort(list, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
	end
	local guns = {}
	for _, w in Unlocks.CrateWeapons() do table.insert(guns, w.Id) end
	local sigs = {}
	for _, s in SigCat.List do
		if not s.Free then table.insert(sigs, { Id = s.Id, Name = s.Name or s.Id }) end
	end
	local crates = {}
	for _, c in CrateCfg.Crates do table.insert(crates, c.Id) end
	for _, c in CrateCfg.WeaponCrates or {} do table.insert(crates, c.Id) end
	local mw = {}
	for _, w in MasteryCfg.Weapons do table.insert(mw, type(w) == "table" and (w.Id or w.Name) or w) end
	catalogCache = { Weapons = weapons, Skins = byWeapon, Guns = guns, Sigs = sigs, Crates = crates, MasteryWeapons = mw }
	return catalogCache
end

local function targets(caller: Player, who): { Player }
	if who == "ALL" then return Players:GetPlayers() end
	local p = Players:GetPlayerByUserId(tonumber(who) or 0)
	return if p then { p } else {}
end

local function root(p: Player)
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function exempt(p: Player, t: number)
	local ev = VS:FindFirstChild("ExemptMovement")
	if ev then ev:Fire(p, t) end
end

local function num(n, allowNeg)
	n = math.floor(tonumber(n) or 0)
	if not allowNeg and n < 0 then n = 0 end
	return math.clamp(n, -10000000, 10000000)
end

-- per-target actions: return true on success
local PER = {}

PER.REQ = function(_, p, n)
	n = num(n, true)
	if n > 0 then
		return (pcall(Req.Award, p, { { Label = "ADMIN GRANT", Amount = n, Kind = "Purchase" } }))
	elseif n < 0 then
		local take = math.min(-n, Req.Balance(p) or 0)
		return take > 0 and Req.Spend(p, take)
	end
	return false
end

PER.ORD = function(_, p, n)
	n = num(n, true)
	if n > 0 then
		return (pcall(Ord.Award, p, n, "ADMIN GRANT"))
	elseif n < 0 then
		local take = math.min(-n, Ord.Balance(p) or 0)
		return take > 0 and Ord.Spend(p, take)
	end
	return false
end

PER.ICHOR = function(_, p, n)
	n = num(n, true)
	local api = ServerStorage:FindFirstChild("SignatureAPI")
	return n ~= 0 and api ~= nil and api:Invoke("AddIchor", p, n, "Purchase") ~= nil
end

PER.XP = function(_, p, n)
	n = num(n)
	return n > 0 and (Prog.AddXP(p, n) or 0) > 0
end

PER.MASTERY = function(_, p, weapon, n)
	n = num(n)
	if n <= 0 or type(weapon) ~= "string" then return false end
	local ok = pcall(Mastery.AddXP, p, weapon, n)
	return ok
end

PER.SKIN = function(_, p, key)
	local h = hook("AdminGrantKeys")
	return type(key) == "string" and h ~= nil and (h:Invoke(p, { key }) or 0) >= 0
end

PER.GUN = function(_, p, id)
	local h = hook("AdminGrantKeys")
	return type(id) == "string" and h ~= nil and (h:Invoke(p, { "Weapon/" .. id }) or 0) >= 0
end

PER.ALLGUNS = function(_, p)
	local h = hook("AdminGrantKeys")
	if not h then return false end
	local keys = {}
	for _, w in Unlocks.CrateWeapons() do table.insert(keys, "Weapon/" .. w.Id) end
	return h:Invoke(p, keys) ~= false
end

PER.ALLSKINS = function(_, p)
	local h = hook("DevGrantAll")
	return h ~= nil and h:Invoke(p) ~= false
end

PER.SIG = function(_, p, id)
	local api = ServerStorage:FindFirstChild("SignatureAPI")
	return api ~= nil and type(id) == "string" and api:Invoke("Grant", p, id) == true
end

PER.CRATE = function(_, p, id, n)
	n = math.clamp(num(n), 1, 100)
	local h = hook("CrateGrant")
	return h ~= nil and type(id) == "string" and h:Invoke(p, { [id] = n }, {}) == true
end

local function pass(p, g)
	local h = hook("PassGrant")
	return h ~= nil and h:Invoke(p, g) == true
end
PER.PASS_PREMIUM = function(_, p) return pass(p, { Premium = true }) end
PER.PASS_TIERS = function(_, p, n) return pass(p, { Skips = math.clamp(num(n), 1, 200) }) end
PER.PASS_MAX = function(_, p) return pass(p, { SkipAll = true }) end

PER.HEAL = function(_, p)
	local _, hum = root(p)
	if not hum or hum.Health <= 0 then return false end
	hum.Health = hum.MaxHealth
	return true
end

PER.KILL = function(caller, p)
	if p == caller then return false end
	local _, hum = root(p)
	if not hum or hum.Health <= 0 then return false end
	hum.Health = 0
	return true
end

PER.KICK = function(caller, p)
	if p == caller then return false end
	p:Kick("You were removed from this server by an admin.")
	return true
end

PER.BRING = function(caller, p)
	if p == caller then return false end
	local a, b = root(caller), root(p)
	if not (a and b) then return false end
	exempt(p, 2)
	b.CFrame = a.CFrame * CFrame.new(math.random(-4, 4), 0, -5)
	return true
end

PER.GOTO = function(caller, p)
	if p == caller then return false end
	local a, b = root(caller), root(p)
	if not (a and b) then return false end
	exempt(caller, 2)
	a.CFrame = b.CFrame * CFrame.new(0, 0, 5)
	return true
end

local LABEL = {
	REQ = "REQ", ORD = "ORD", ICHOR = "Ichor", XP = "XP", MASTERY = "mastery XP", SKIN = "skin", GUN = "gun",
	ALLGUNS = "all guns", ALLSKINS = "all guns + skins", SIG = "Signature", CRATE = "crate(s)",
	PASS_PREMIUM = "Premium pass", PASS_TIERS = "pass tiers", PASS_MAX = "max pass",
	HEAL = "heal", KILL = "kill", KICK = "kick", BRING = "bring", GOTO = "go to",
}

local last: { [Player]: number } = {}

Fn.OnServerInvoke = function(caller: Player, action, who, a, b)
	if not isAdmin(caller) then
		warn("[VANTAGE] AdminPanel: refused", caller.Name, action)
		return false, "Not authorised."
	end
	if action == "Catalog" then
		return true, catalog()
	end
	local now = os.clock()
	if last[caller] and now - last[caller] < 0.15 then
		return false, "Too fast."
	end
	last[caller] = now

	if action == "ANNOUNCE" then
		if type(a) ~= "string" or #a == 0 then return false, "Type a message." end
		a = string.sub(a, 1, 160)
		local ok, res = pcall(function()
			return TextService:FilterStringAsync(a, caller.UserId):GetNonChatStringForBroadcastAsync()
		 end)
		if not ok then return false, "Text filter failed, try again." end
		Announce:FireAllClients(res, caller.DisplayName)
		return true, "Announcement sent."
	end

	local f = PER[action]
	if not f then return false, "Unknown action." end
	local list = targets(caller, who)
	if #list == 0 then return false, "No target." end
	local okN, names = 0, {}
	for _, p in list do
		local ok, res = pcall(f, caller, p, a, b)
		if ok and res then
			okN += 1
			if #names < 3 then table.insert(names, p.DisplayName) end
		elseif not ok then
			warn("[VANTAGE] AdminPanel:", action, p.Name, res)
		end
	end
	local what = LABEL[action] or action
	if type(a) == "number" then what = a .. " " .. what
	elseif type(a) == "string" and action ~= "KICK" then what = what .. " " .. a end
	if type(b) == "number" and action ~= "CRATE" then what = b .. " " .. what
	elseif action == "CRATE" then what = (b or 1) .. "x " .. tostring(a) .. " crate" end
	print(string.format("[VANTAGE] AdminPanel: %s -> %s %s (%d/%d)", caller.Name, action, tostring(who), okN, #list))
	if okN == 0 then
		return false, "Failed: " .. what .. " (player still loading, no character, or nothing to change)."
	end
	local who2 = #list > 1 and (okN .. " players") or table.concat(names, ", ")
	return true, "Done: " .. what .. " → " .. who2
end

Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
