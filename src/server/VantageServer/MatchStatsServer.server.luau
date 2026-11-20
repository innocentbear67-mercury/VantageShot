--[[
	VANTAGE — MatchStatsServer (ServerScriptService.VantageServer.MatchStatsServer)
	Per-match stats derived from the session counters EliminationService already keeps.
	Read-only toward everything else: it only reads Session* / Match attributes and writes its own
	MatchStats_* player attributes:
	  MatchStats_Kills, MatchStats_Deaths, MatchStats_Headshots, MatchStats_Score
	  MatchStats_MatchId  (the match these numbers belong to)
	Rules
	  New match (Match.MatchId changes) or Phase -> "Prep": reset the match's players to 0.
	  Session counters are tracked as deltas; a delta only counts while Phase == "Live".
	  Values stay through "Ended" and are only reset when the next match starts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("ScoreboardConfig"))
local Match = Vantage:WaitForChild("Match")

local STATS = {
	SessionEliminations = "MatchStats_Kills",
	SessionDeaths = "MatchStats_Deaths",
	SessionHeadshots = "MatchStats_Headshots",
}

local last: { [Player]: { [string]: number } } = {}
local conns: { [Player]: { RBXScriptConnection } } = {}

local function num(v: any): number
	return if type(v) == "number" then v else 0
end

local function updateScore(p: Player)
	local k = num(p:GetAttribute("MatchStats_Kills"))
	local hs = num(p:GetAttribute("MatchStats_Headshots"))
	p:SetAttribute("MatchStats_Score", k * Config.Score.PerKill + hs * Config.Score.PerHeadshot)
end

-- baseline = current session values (everything before this point is not this match's)
local function snapshot(p: Player)
	local b = last[p]
	if not b then
		return
	end
	for session in STATS do
		b[session] = num(p:GetAttribute(session))
	end
end

local function resetPlayer(p: Player, matchId: number?)
	snapshot(p)
	for _, attr in STATS do
		p:SetAttribute(attr, 0)
	end
	p:SetAttribute("MatchStats_Score", 0)
	-- match earnings (MatchLedger, 2026-11-18)
	for _, k in { "REQ", "ORD", "XP", "Damage" } do
		p:SetAttribute("MatchStats_" .. k, 0)
	end
	p:SetAttribute("MatchStats_MatchId", matchId)
end

local function inCurrentMatch(p: Player): boolean
	local id = Match:GetAttribute("MatchId")
	return p:GetAttribute("MatchStatus") == "Match" and id ~= nil and id ~= 0 and p:GetAttribute("MatchId") == id
end

local function resetMatchPlayers()
	local id = Match:GetAttribute("MatchId")
	for _, p in Players:GetPlayers() do
		if inCurrentMatch(p) then
			resetPlayer(p, id)
		end
	end
end

local function onSessionChanged(p: Player, session: string)
	local b = last[p]
	if not b then
		return
	end
	local now = num(p:GetAttribute(session))
	local delta = now - (b[session] or now)
	b[session] = now
	if delta <= 0 or Match:GetAttribute("Phase") ~= "Live" or not inCurrentMatch(p) then
		return
	end
	-- a player put into this match after the reset (late join) gets a fresh line first
	if p:GetAttribute("MatchStats_MatchId") ~= Match:GetAttribute("MatchId") then
		resetPlayer(p, Match:GetAttribute("MatchId"))
		b[session] = now
	end
	local attr = STATS[session]
	p:SetAttribute(attr, num(p:GetAttribute(attr)) + delta)
	updateScore(p)
end

local function track(p: Player)
	if last[p] then
		return
	end
	last[p] = {}
	snapshot(p) -- joining mid-match: start from whatever the session counters say now
	local list = {}
	for session in STATS do
		table.insert(list, p:GetAttributeChangedSignal(session):Connect(function()
			onSessionChanged(p, session)
		end))
	end
	-- put into the running match after the Prep reset: zero this player's line now
	table.insert(list, p:GetAttributeChangedSignal("MatchId"):Connect(function()
		if inCurrentMatch(p) and p:GetAttribute("MatchStats_MatchId") ~= Match:GetAttribute("MatchId") then
			resetPlayer(p, Match:GetAttribute("MatchId"))
		end
	end))
	conns[p] = list
end

local function untrack(p: Player)
	local list = conns[p]
	if list then
		for _, c in list do
			c:Disconnect()
		end
	end
	conns[p] = nil
	last[p] = nil
end

Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)
for _, p in Players:GetPlayers() do
	track(p)
end

Match:GetAttributeChangedSignal("MatchId"):Connect(function()
	local id = Match:GetAttribute("MatchId")
	if id and id ~= 0 then
		-- MatchService sets MatchStatus / MatchId on players just before MatchId on the folder
		task.defer(resetMatchPlayers)
	end
end)

Match:GetAttributeChangedSignal("Phase"):Connect(function()
	if Match:GetAttribute("Phase") == "Prep" then
		resetMatchPlayers()
	end
end)
