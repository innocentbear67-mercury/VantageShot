--[[
	VANTAGE — ProgressionConfig (shared)
	Levels / XP, Daily Directives and the weekly Operation (event). Read by the server
	(Progression) and by the lobby UI. All times are UTC unix seconds.
]]
local Config = {}

-- XP awarded by the server
Config.XP = {
	Elimination = 100,
	Headshot = 25, -- on top of the elimination
	Assist = 50,
	Match = 250, -- finishing a match (any result)
	Win = 500, -- on top of Match
}

Config.MaxLevel = 100
-- XP needed to go from `level` to `level + 1`
function Config.Need(level: number): number
	return 1000 + 150 * (level - 1)
end
-- total XP -> level, XP into that level, XP needed for the next one
function Config.LevelOf(xp: number): (number, number, number)
	local level = 1
	local rest = math.max(0, math.floor(xp))
	while level < Config.MaxLevel and rest >= Config.Need(level) do
		rest -= Config.Need(level)
		level += 1
	end
	return level, rest, Config.Need(level)
end

-- stats the server counts: Elims, Headshots, Assists, Damage, Matches, Wins
Config.Directives = {
	{ Id = "E15", Text = "Get 15 Eliminations", Stat = "Elims", Goal = 15, Reward = 1000 },
	{ Id = "E30", Text = "Get 30 Eliminations", Stat = "Elims", Goal = 30, Reward = 2000 },
	{ Id = "W1", Text = "Win a Match", Stat = "Wins", Goal = 1, Reward = 1000 },
	{ Id = "W2", Text = "Win 2 Matches", Stat = "Wins", Goal = 2, Reward = 2000 },
	{ Id = "D5K", Text = "Deal 5,000 Damage", Stat = "Damage", Goal = 5000, Reward = 800 },
	{ Id = "D10K", Text = "Deal 10,000 Damage", Stat = "Damage", Goal = 10000, Reward = 1500 },
	{ Id = "H5", Text = "Get 5 Headshot Eliminations", Stat = "Headshots", Goal = 5, Reward = 1200 },
	{ Id = "M3", Text = "Play 3 Matches", Stat = "Matches", Goal = 3, Reward = 1200 },
	{ Id = "A5", Text = "Get 5 Assists", Stat = "Assists", Goal = 5, Reward = 800 },
}
Config.DailyCount = 3

function Config.Day(t: number?): number
	return math.floor((t or os.time()) / 86400)
end
function Config.DayEnds(t: number?): number
	return (Config.Day(t) + 1) * 86400
end
-- today's directives: the same three for everyone, one per stat, picked from the day number
function Config.DailyFor(day: number)
	local rng = Random.new(day * 7919 + 17)
	local pool = table.clone(Config.Directives)
	local picked, usedStat = {}, {}
	while #picked < Config.DailyCount and #pool > 0 do
		local i = rng:NextInteger(1, #pool)
		local d = table.remove(pool, i)
		if not usedStat[d.Stat] then
			usedStat[d.Stat] = true
			table.insert(picked, d)
		end
	end
	return picked
end

-- weekly Operation: rotates every Monday 00:00 UTC (1970-01-05 was a Monday)
local WEEK0 = 345600
Config.Operations = {
	{ Name = "OPERATION VERIDIAN", Text = "Eliminate 100 hostiles", Stat = "Elims", Tiers = { { 25, 1000 }, { 50, 2000 }, { 100, 5000 } } },
	{ Name = "OPERATION IRONGATE", Text = "Win 5 matches", Stat = "Wins", Tiers = { { 1, 1000 }, { 3, 2000 }, { 5, 5000 } } },
	{ Name = "OPERATION NIGHTFALL", Text = "Land 40 headshot eliminations", Stat = "Headshots", Tiers = { { 10, 1000 }, { 20, 2000 }, { 40, 5000 } } },
	{ Name = "OPERATION SHATTERPOINT", Text = "Deal 50,000 damage", Stat = "Damage", Tiers = { { 10000, 1000 }, { 25000, 2000 }, { 50000, 5000 } } },
}
function Config.Week(t: number?): number
	return math.floor(((t or os.time()) - WEEK0) / 604800)
end
function Config.WeekEnds(t: number?): number
	return WEEK0 + (Config.Week(t) + 1) * 604800
end
function Config.OperationFor(week: number)
	return Config.Operations[week % #Config.Operations + 1]
end
function Config.OperationTotal(op): number
	local n = 0
	for _, t in op.Tiers do
		n += t[2]
	end
	return n
end

return Config
