--[[
	VANTAGE — Progression service (server). Levels / XP, Daily Directives, weekly Operation.
	  • DataStore "VantageProgression_v1", key "u_<UserId>" ->
	      { V = 1, XP, Stats = { Elims, Headshots, Assists, Damage, Matches, Wins },
	        Daily = { Day, P = { [id] = progress }, Done = { [id] = true } },
	        Op = { Week, P = progress, Paid = tiersPaid } }
	    Studio playtests never write (same rule as Requisition).
	  • replicated player attributes (server-set): Level, XP, LevelXP, LevelNeed
	  • Remotes.ProgressionGet() -> snapshot; Remotes.ProgressionUpdate:FireClient(snapshot)
	  • Progression.Record(player, stat, amount) counts a stat (lifetime, daily, operation);
	    Progression.AddXP(player, amount). Directive / operation rewards are paid in REQ.
	Fed by EliminationService (elims, headshots, assists), DamageService (damage) and
	MatchService (matches, wins).
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(script.Parent:WaitForChild("ProgressionConfig"))
local Requisition = require(script.Parent:WaitForChild("Requisition"))
-- 2026-11-17: Ordnance (ORD, second currency for Arsenal Crates) is earned through these hooks too
local OrdCfg = require(game:GetService("ReplicatedStorage").Vantage:WaitForChild("Ordnance"):WaitForChild("OrdnanceConfig"))
local OrdMod = nil
local function ord()
	if OrdMod == nil then
		local ok, m = pcall(function() return require(script.Parent:WaitForChild("Ordnance", 5)) end)
		OrdMod = if ok and m then m else false
	end
	return OrdMod or nil
end
local Ledger = require(script.Parent:WaitForChild("MatchLedger")) -- per-match earnings (2026-11-18)
local getRemote = Vantage.Remotes:WaitForChild("ProgressionGet") :: RemoteFunction
local updRemote = Vantage.Remotes:WaitForChild("ProgressionUpdate") :: RemoteEvent

local Progression = {}
local STORE = "VantageProgression_v1"
local SAVE = not RunService:IsStudio()
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local STATS = { "Elims", "Headshots", "Assists", "Damage", "Matches", "Wins" }
local data: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local pending: { [Player]: boolean } = {}

local function fresh()
	local s = {}
	for _, k in STATS do
		s[k] = 0
	end
	return { V = 1, XP = 0, Stats = s, Daily = { Day = -1, P = {}, Done = {} }, Op = { Week = -1, P = 0, Paid = 0 } }
end

local function sanitize(d)
	local f = fresh()
	if type(d) ~= "table" then
		return f
	end
	f.XP = if type(d.XP) == "number" then math.max(0, math.floor(d.XP)) else 0
	if type(d.Stats) == "table" then
		for _, k in STATS do
			f.Stats[k] = if type(d.Stats[k]) == "number" then d.Stats[k] else 0
		end
	end
	if type(d.Daily) == "table" and type(d.Daily.Day) == "number" then
		f.Daily.Day = d.Daily.Day
		f.Daily.P = if type(d.Daily.P) == "table" then d.Daily.P else {}
		f.Daily.Done = if type(d.Daily.Done) == "table" then d.Daily.Done else {}
	end
	if type(d.Op) == "table" and type(d.Op.Week) == "number" then
		f.Op.Week = d.Op.Week
		f.Op.P = tonumber(d.Op.P) or 0
		f.Op.Paid = tonumber(d.Op.Paid) or 0
	end
	return f
end

-- day / week rollover
local function roll(d)
	local day, week = Config.Day(), Config.Week()
	if d.Daily.Day ~= day then
		d.Daily = { Day = day, P = {}, Done = {} }
	end
	if d.Op.Week ~= week then
		d.Op = { Week = week, P = 0, Paid = 0 }
	end
end

function Progression.Snapshot(p: Player)
	local d = data[p]
	if not d then
		return nil
	end
	roll(d)
	local level, into, need = Config.LevelOf(d.XP)
	local daily = {}
	for _, dir in Config.DailyFor(d.Daily.Day) do
		table.insert(daily, {
			Id = dir.Id, Text = dir.Text, Goal = dir.Goal, Reward = dir.Reward,
			Progress = math.min(dir.Goal, d.Daily.P[dir.Id] or 0), Done = d.Daily.Done[dir.Id] == true,
		})
	end
	local op = Config.OperationFor(d.Op.Week)
	local tiers = {}
	for i, t in op.Tiers do
		tiers[i] = { Goal = t[1], Reward = t[2], Paid = i <= d.Op.Paid }
	end
	return {
		Level = level, XP = d.XP, LevelXP = into, LevelNeed = need, MaxLevel = Config.MaxLevel,
		Stats = table.clone(d.Stats),
		Daily = daily, DailyEnds = Config.DayEnds(),
		Operation = { Name = op.Name, Text = op.Text, Progress = d.Op.P, Tiers = tiers, Ends = Config.WeekEnds(), Total = Config.OperationTotal(op) },
		ServerTime = os.time(),
	}
end

local function publish(p: Player)
	local d = data[p]
	if not d or not p.Parent then
		return
	end
	local level, into, need = Config.LevelOf(d.XP)
	p:SetAttribute("Level", level)
	p:SetAttribute("XP", d.XP)
	p:SetAttribute("LevelXP", into)
	p:SetAttribute("LevelNeed", need)
end

-- coalesce updates: one push per player per frame-ish
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
			updRemote:FireClient(p, Progression.Snapshot(p))
		end
	end)
end

-- weapon mastery boosts (MasteryConfig.Boosts): gameplay ORD and account XP; purchases never pass through here
local function mBoost(p: Player, key: string, n: number): number
	return math.floor(n * (1 + (tonumber(p:GetAttribute("MasteryBoost" .. key)) or 0) / 100) + 0.5)
end

function Progression.AddXP(p: Player, amount: number)
	local d = data[p]
	amount = math.floor(tonumber(amount) or 0)
	local raw = amount -- the Season Pass mirror gets the un-boosted amount
	amount = mBoost(p, "XP", amount)
	if not d or amount <= 0 then
		return 0
	end
	Ledger.Add(p, "XP", amount)
	local before = Config.LevelOf(d.XP)
	d.XP += amount
	local passXP = script.Parent:FindFirstChild("PassXP") -- Season Pass mirrors match XP (SeasonPassService)
	if passXP then passXP:Fire(p, raw) end
	local after = Config.LevelOf(d.XP)
	if after > before then
		p:SetAttribute("LevelUp", after) -- clients may celebrate
		local o = ord()
		if o then
			local lv = mBoost(p, "ORD", (after - before) * OrdCfg.Rewards.LevelUp)
			o.Award(p, lv, "LEVEL " .. after)
			Ledger.Add(p, "ORD", lv)
		end
	end
	push(p)
	return amount
end

function Progression.Record(p: Player, stat: string, amount: number?)
	local d = data[p]
	local n = tonumber(amount) or 1
	if not d or n <= 0 or d.Stats[stat] == nil then
		return
	end
	roll(d)
	d.Stats[stat] += n
	local pay = {}
	-- daily directives
	for _, dir in Config.DailyFor(d.Daily.Day) do
		if dir.Stat == stat and not d.Daily.Done[dir.Id] then
			local v = (d.Daily.P[dir.Id] or 0) + n
			d.Daily.P[dir.Id] = math.min(dir.Goal, v)
			if v >= dir.Goal then
				d.Daily.Done[dir.Id] = true
				table.insert(pay, { Label = "DIRECTIVE: " .. string.upper(dir.Text), Amount = dir.Reward, Kind = "Directive" })
			end
		end
	end
	-- weekly operation
	local op = Config.OperationFor(d.Op.Week)
	if op.Stat == stat then
		d.Op.P += n
		while d.Op.Paid < #op.Tiers and d.Op.P >= op.Tiers[d.Op.Paid + 1][1] do
			d.Op.Paid += 1
			table.insert(pay, { Label = op.Name .. " TIER " .. d.Op.Paid, Amount = op.Tiers[d.Op.Paid][2], Kind = "Operation" })
		end
	end
	if #pay > 0 then
		Requisition.Award(p, pay)
	end
	push(p)
end

-- convenience hooks used by the combat / match services
function Progression.OnElimination(p: Player, headshot: boolean)
	Progression.Record(p, "Elims", 1)
	if headshot then
		Progression.Record(p, "Headshots", 1)
	end
	-- 2026-11-18: returns what was granted (XP, ORD) so the kill feed can show all three rewards
	local xp = Progression.AddXP(p, Config.XP.Elimination + (if headshot then Config.XP.Headshot else 0)) or 0
	local o = ord()
	local od = 0
	if o then
		od = mBoost(p, "ORD", OrdCfg.Rewards.Elimination)
		o.Credit(p, od)
		Ledger.Add(p, "ORD", od)
	end
	return xp, od
end
function Progression.OnAssist(p: Player)
	Progression.Record(p, "Assists", 1)
	local xp = Progression.AddXP(p, Config.XP.Assist) or 0
	local o = ord()
	local od = 0
	if o then
		od = mBoost(p, "ORD", OrdCfg.Rewards.Assist)
		o.Credit(p, od)
		Ledger.Add(p, "ORD", od)
	end
	return xp, od
end
function Progression.OnDamage(p: Player, amount: number)
	if amount > 0 then
		Progression.Record(p, "Damage", math.floor(amount + 0.5))
		Ledger.Add(p, "Damage", amount)
	end
end
function Progression.OnMatchEnd(p: Player, won: boolean)
	Progression.Record(p, "Matches", 1)
	if won then
		Progression.Record(p, "Wins", 1)
	end
	Progression.AddXP(p, Config.XP.Match + (if won then Config.XP.Win else 0))
	local o = ord()
	if o then
		local od = mBoost(p, "ORD", OrdCfg.Rewards.Match + (if won then OrdCfg.Rewards.Win else 0))
		o.Award(p, od, if won then "VICTORY" else "MATCH COMPLETE")
		Ledger.Add(p, "ORD", od)
	end
end

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
			warn("[VANTAGE] Progression: load failed (progress this session only, not saved):", res)
			d.NoSave = true
		end
	end
	if p.Parent then
		roll(d)
		data[p] = d
		publish(p)
		updRemote:FireClient(p, Progression.Snapshot(p))
	end
end

local function save(p: Player)
	local d = data[p]
	if not SAVE or not store or not d or d.NoSave or not dirty[p] then
		return
	end
	dirty[p] = nil
	local copy = { V = 1, XP = d.XP, Stats = d.Stats, Daily = d.Daily, Op = d.Op }
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function()
			return copy
		end)
	end)
	if not ok then
		dirty[p] = true
		warn("[VANTAGE] Progression: save failed (kept for the next try):", err)
	end
end

getRemote.OnServerInvoke = function(p: Player)
	local t0 = os.clock()
	while not data[p] and p.Parent and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	return Progression.Snapshot(p)
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p], dirty[p], pending[p] = nil, nil, nil
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
	-- Studio test hook: set player attribute ProgTest = "<Stat>:<n>" or "XP:<n>"
	local function hook(p: Player)
		p:GetAttributeChangedSignal("ProgTest"):Connect(function()
			local v = tostring(p:GetAttribute("ProgTest") or "")
			local stat, n = v:match("^(%a+):(%d+)")
			if stat == "XP" then
				Progression.AddXP(p, tonumber(n))
			elseif stat then
				Progression.Record(p, stat, tonumber(n))
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Progression
