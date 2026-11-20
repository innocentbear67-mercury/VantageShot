--[[
	VANTAGE — Mastery service (server), 2026-11-17
	Weapon mastery per player: XP, levels 1–50 and prestige for every weapon (MasteryConfig).
	  • DataStore "VantageMastery_v1", key "u_<UserId>" ->
	      { V = 1, W = { [weaponId] = { XP, P, Base, K, H } }, FP }
	    XP = lifetime weapon XP, P = prestige count, Base = XP at the last prestige
	    (level = LevelOf(XP - Base)), K / H = eliminations / headshot eliminations, FP = Forge Parts.
	    Studio playtests never write (same rule as Requisition / Progression).
	  • replicated player attributes (server-set):
	      "Mastery_<weaponId>" = "level|into|need|prestige|kills", "ForgeParts"
	  • Remotes.MasteryGet() -> snapshot; Remotes.MasteryUpdate:FireClient(snapshot);
	    Remotes.MasteryLevelUp:FireClient({ Weapon, Level?, Prestige?, Rewards });
	    Remotes.MasteryPrestige:FireServer(weaponId)
	  • Mastery.Get / HasLevel / VariantUnlocked for other services (variants, loadout).
	Fed by EliminationService (eliminations, headshots, assists) and DamageService (damage).
	Level-up rewards: REQ through Requisition.Award and Forge Parts here. Finishes, variants and other
	unlocks are read from level + prestige (prestige keeps every unlock), so nothing else is stored.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("Mastery"):WaitForChild("MasteryConfig"))
local Requisition = require(script.Parent:WaitForChild("Requisition"))
local Remotes = Vantage:WaitForChild("Remotes")
local getRemote = Remotes:WaitForChild("MasteryGet") :: RemoteFunction
local updRemote = Remotes:WaitForChild("MasteryUpdate") :: RemoteEvent
local upRemote = Remotes:WaitForChild("MasteryLevelUp") :: RemoteEvent
local prestigeRemote = Remotes:WaitForChild("MasteryPrestige") :: RemoteEvent

local Mastery = {}
local STORE = "VantageMastery_v1"
local SAVE = not RunService:IsStudio()
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local data: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local pending: { [Player]: boolean } = {}
local frac: { [Player]: { [string]: number } } = {} -- damage XP under one point, per weapon
local lastWeaponOn = setmetatable({}, { __mode = "k" }) -- victim character -> { [userId] = weaponId }

local function rec0()
	return { XP = 0, P = 0, Base = 0, K = 0, H = 0 }
end
local function fresh()
	local w = {}
	for _, id in Config.Weapons do
		w[id] = rec0()
	end
	return { V = 1, W = w, FP = 0 }
end
local function num(v: any): number
	return if type(v) == "number" and v == v then math.max(0, math.floor(v)) else 0
end
local function sanitize(d)
	local f = fresh()
	if type(d) ~= "table" then
		return f
	end
	if type(d.W) == "table" then
		for _, id in Config.Weapons do
			local r = d.W[id]
			if type(r) == "table" then
				local x = f.W[id]
				x.XP, x.P, x.Base, x.K, x.H = num(r.XP), math.min(Config.MaxPrestige, num(r.P)), num(r.Base), num(r.K), num(r.H)
				if x.Base > x.XP then
					x.Base = x.XP
				end
			end
		end
	end
	f.FP = num(d.FP)
	return f
end

local function levelOf(r): (number, number, number)
	return Config.LevelOf(r.XP - r.Base)
end

local function encode(r): string
	local level, into, need = levelOf(r)
	return string.format("%d|%d|%d|%d|%d", level, into, need, r.P, r.K)
end

-- level a weapon is at (1 when unknown) and its prestige count
function Mastery.Get(p: Player, weaponId: string): (number, number)
	local d = data[p]
	local r = d and d.W[weaponId]
	if not r then
		return 1, 0
	end
	return (levelOf(r)), r.P
end
-- has the player unlocked what this weapon gives at `level`? (prestige keeps every unlock)
function Mastery.HasLevel(p: Player, weaponId: string, level: number): boolean
	local lv, pr = Mastery.Get(p, weaponId)
	return pr > 0 or lv >= level
end
function Mastery.VariantUnlocked(p: Player, weaponId: string, index: number): boolean
	local need = Config.VariantLevels[index]
	return need ~= nil and Mastery.HasLevel(p, weaponId, need)
end

function Mastery.CanPrestige(p: Player, weaponId: string): boolean
	local d = data[p]
	local r = d and d.W[weaponId]
	if not r or r.P >= Config.MaxPrestige then
		return false
	end
	if (levelOf(r)) < Config.MaxLevel then
		return false
	end
	if Config.RequireSingularity then
		return false -- mastery challenges are not built yet; this flag stays false until they are
	end
	return true
end

function Mastery.Snapshot(p: Player)
	local d = data[p]
	if not d then
		return nil
	end
	local w = {}
	for _, id in Config.Weapons do
		local r = d.W[id]
		local level, into, need = levelOf(r)
		w[id] = {
			Level = level, Into = into, Need = need, Prestige = r.P, Kills = r.K, Headshots = r.H,
			TotalXP = r.XP, CanPrestige = Mastery.CanPrestige(p, id),
		}
	end
	return { Weapons = w, ForgeParts = d.FP, MaxLevel = Config.MaxLevel, MaxPrestige = Config.MaxPrestige }
end

local function publish(p: Player)
	local d = data[p]
	if not d or not p.Parent then
		return
	end
	for _, id in Config.Weapons do
		p:SetAttribute("Mastery_" .. id, encode(d.W[id]))
	end
	p:SetAttribute("ForgeParts", d.FP)
	-- account-wide earn boosts from every weapon's mastery (read by Requisition / Progression)
	local lv = {}
	for wid, r in d.W do lv[wid] = { Level = (levelOf(r)), Prestige = r.P or 0 } end
	local bt = Config.BoostTotals(lv)
	p:SetAttribute("MasteryBoostREQ", bt.REQ)
	p:SetAttribute("MasteryBoostORD", bt.ORD)
	p:SetAttribute("MasteryBoostXP", bt.XP)
end

-- coalesce updates: one push per player per quarter second
local function push(p: Player)
	dirty[p] = true
	if pending[p] then
		return
	end
	pending[p] = true
	task.delay(0.25, function()
		pending[p] = nil
		if p.Parent and data[p] then
			publish(p)
			updRemote:FireClient(p, Mastery.Snapshot(p))
		end
	end)
end

local function payLevel(p: Player, d, weaponId: string, level: number)
	local rewards = Config.RewardsFor(level)
	local req = {}
	for _, rw in rewards do
		if rw.Kind == "REQ" then
			table.insert(req, { Label = string.upper(weaponId) .. " MASTERY " .. level, Amount = rw.Amount, Kind = "Mastery" })
		elseif rw.Kind == "ForgeParts" then
			d.FP += rw.Amount
		end
	end
	if #req > 0 then
		Requisition.Award(p, req)
	end
	upRemote:FireClient(p, { Weapon = weaponId, Level = level, Rewards = rewards })
end

function Mastery.AddXP(p: Player, weaponId: string, amount: number)
	local d = data[p]
	amount = math.floor(tonumber(amount) or 0)
	if not d or amount <= 0 or not Config.IsWeapon[weaponId] then
		return
	end
	local r = d.W[weaponId]
	local before = levelOf(r)
	r.XP += amount
	local after = levelOf(r)
	for level = before + 1, after do
		payLevel(p, d, weaponId, level)
	end
	push(p)
end

local function isSelf(p: Player, character: Model?): boolean
	return character ~= nil and character == p.Character
end

-- DamageService: damage dealt by `p` with `weaponId` to `character`
function Mastery.OnDamage(p: Player, weaponId: string, character: Model?, amount: number)
	if not (p and data[p] and Config.IsWeapon[weaponId]) or not amount or amount <= 0 or isSelf(p, character) then
		return
	end
	if character then
		local t = lastWeaponOn[character]
		if not t then
			t = {}
			lastWeaponOn[character] = t
		end
		t[p.UserId] = weaponId
	end
	local f = frac[p]
	if not f then
		f = {}
		frac[p] = f
	end
	local x = (f[weaponId] or 0) + amount / Config.XP.DamagePerXP
	local whole = math.floor(x)
	f[weaponId] = x - whole
	if whole > 0 then
		Mastery.AddXP(p, weaponId, whole)
	end
end

-- EliminationService: `p` eliminated someone with `weaponId`
function Mastery.OnElimination(p: Player, weaponId: any, headshot: boolean)
	local d = data[p]
	if not d or type(weaponId) ~= "string" or not Config.IsWeapon[weaponId] then
		return
	end
	local r = d.W[weaponId]
	r.K += 1
	if headshot then
		r.H += 1
	end
	Mastery.AddXP(p, weaponId, Config.XP.Elimination + (if headshot then Config.XP.Headshot else 0))
end

-- EliminationService: `p` assisted on `character`; XP goes to the weapon `p` last hit it with
function Mastery.OnAssist(p: Player, character: Model?)
	local t = character and lastWeaponOn[character]
	local weaponId = t and t[p.UserId]
	if weaponId then
		Mastery.AddXP(p, weaponId, Config.XP.Assist)
	end
end

function Mastery.Prestige(p: Player, weaponId: string): boolean
	if not Mastery.CanPrestige(p, weaponId) then
		return false
	end
	local r = data[p].W[weaponId]
	r.P += 1
	r.Base = r.XP
	push(p)
	upRemote:FireClient(p, { Weapon = weaponId, Prestige = r.P, Rewards = { Config.PrestigeReward } })
	return true
end

local lastPrestige: { [Player]: number } = {}
prestigeRemote.OnServerEvent:Connect(function(p: Player, weaponId)
	local now = os.clock()
	if now - (lastPrestige[p] or 0) < 1 then
		return
	end
	lastPrestige[p] = now
	if type(weaponId) == "string" and Config.IsWeapon[weaponId] then
		Mastery.Prestige(p, weaponId)
	end
end)

-- ─── persistence ───────────────────────────────────────────────────────────────────────────────────────
local function key(p: Player): string
	return "u_" .. p.UserId
end

local function load(p: Player)
	local d = fresh()
	if store then
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync(key(p))
		end)
		if ok then
			d = sanitize(res)
		else
			warn("[VANTAGE] Mastery: load failed (progress this session only, not saved):", res)
			d.NoSave = true
		end
	end
	if p.Parent then
		data[p] = d
		publish(p)
		updRemote:FireClient(p, Mastery.Snapshot(p))
	end
end

local function save(p: Player)
	local d = data[p]
	if not SAVE or not store or not d or d.NoSave or not dirty[p] then
		return
	end
	dirty[p] = nil
	local copy = { V = 1, W = d.W, FP = d.FP }
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function()
			return copy
		end)
	end)
	if not ok then
		dirty[p] = true
		warn("[VANTAGE] Mastery: save failed (kept for the next try):", err)
	end
end

getRemote.OnServerInvoke = function(p: Player)
	local t0 = os.clock()
	while not data[p] and p.Parent and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	return Mastery.Snapshot(p)
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p], dirty[p], pending[p], frac[p], lastPrestige[p] = nil, nil, nil, nil, nil
end)
task.spawn(function()
	while true do
		task.wait(60)
		for p in data do
			task.spawn(save, p)
		end
	end
end)
game:BindToClose(function()
	if not SAVE or not store then
		return
	end
	local n = 0
	for p in data do
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
	-- Studio test hook: player attribute MasteryTest = "<Weapon>:XP:<n>" | "<Weapon>:Elim" | "<Weapon>:Prestige"
	local function hook(p: Player)
		p:GetAttributeChangedSignal("MasteryTest"):Connect(function()
			local v = tostring(p:GetAttribute("MasteryTest") or "")
			local w, cmd, n = v:match("^(%a+):(%a+):?(%d*)")
			if not w then
				return
			end
			if cmd == "XP" then
				Mastery.AddXP(p, w, tonumber(n) or 0)
			elseif cmd == "Elim" then
				Mastery.OnElimination(p, w, false)
			elseif cmd == "Prestige" then
				Mastery.Prestige(p, w)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Mastery
