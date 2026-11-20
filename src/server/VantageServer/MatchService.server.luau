--[[
	VANTAGE — MatchService (server)
	Server-authoritative matchmaking and match flow for this server (one match at a time).
	  Queue   DEPLOY on the menu calls MatchRequest("Queue", modeId). A full queue (TeamSize x 2)
	          starts a match; "Skip" (playtesting, MatchConfig.AllowSkip) starts one with whoever
	          is queued for that mode. Players queued while a match runs wait for the next one.
	  Teams   balanced Red / Blue, assigned at MATCH FOUND (TeamSelect is no longer used).
	  Phases  Found -> Deploy -> Intro -> Prep -> Countdown -> Live -> Ended -> Idle (see MatchConfig).
	          Every phase change is published on ReplicatedStorage.Vantage.Match:
	            Phase, PhaseEnds (server time), MatchId, Mode, MapName, Combat, TimeLeft,
	            BlueRoster / RedRoster (JSON names), Winner, EndReason, Queue_<mode>
	          and per player: MatchStatus ("Queued" | "Match" | nil), QueueMode, MatchId.
	  Combat  Match.Combat is true only while Live; DamageService and CombatBot refuse damage
	          otherwise. During Prep / Countdown players are held inside their spawn zone.
	  Leaving a queued player leaving updates the count; a match whose players all leave is
	          cancelled; a team emptied during Live forfeits (if it started with players).
	2026-11-18 complete match system:
	  * TDM 6v6, first to 150, 20 min; tied at time -> OVERTIME sudden death (Match.Overtime), still
	    tied after MatchConfig.Overtime.Length -> DRAW.
	  * The deciding elimination switches combat off on the same frame (no kills after the win).
	  * Backfill: queueing for the running mode while Live puts you on the smaller team (never past
	    TeamSize, never in overtime / the last MatchConfig.Backfill.MinTimeLeft s). A player who
	    left and comes back gets their match stats back.
	  * Results: Match.Results (JSON) is published just before Phase "Ended": final rows for every
	    participant (also those who left), server-picked MVP (winning team) and top performer, match
	    earnings. Players are frozen during the results and can leave early with
	    MatchRequest("Leave").
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("MatchConfig"))
local Remotes = require(Vantage:WaitForChild("RemotesLib"))
local request = Vantage.Remotes:WaitForChild("MatchRequest") :: RemoteFunction
local DamageService = require(script.Parent:WaitForChild("WeaponServer"):WaitForChild("DamageService"))
local exempt = script.Parent:WaitForChild("ExemptMovement", 10) :: BindableEvent?
local IntroService = require(script.Parent:WaitForChild("IntroService")) -- operative introductions (phase "Intro")
local Progression = require(script.Parent:WaitForChild("Progression")) -- XP / directives for match end
local MapService = require(script.Parent:WaitForChild("MapService")) -- 2026-11-18: map vote + rotation loader

local M = DamageService.MatchFolder()
MapService.Attach(M)

-- map vote of the match being found (MatchConfig.MapVote). Published on M:
--   VoteMaps (JSON ids), VoteStart / VoteEnds (server time), VoteCounts (JSON id -> n), VoteWinner
local votes = nil -- { Choices = { id }, ByPlayer = { [Player] = id }, Open = bool, Match = m }
local TEAM_NAMES = { "Blue", "Red" }

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- ─── published state ──────────────────────────────────────────────────────────────────────────────────
local function setPhase(name: string, duration: number?)
	-- PhaseEnds first: a client reacting to Phase reads the matching end time
	M:SetAttribute("PhaseEnds", if duration then now() + duration else 0)
	M:SetAttribute("Phase", name)
end

local function resetBoard()
	local tdm = Config.Modes.TDM
	M:SetAttribute("BlueScore", 0)
	M:SetAttribute("RedScore", 0)
	M:SetAttribute("ScoreLimit", tdm.ScoreLimit)
	M:SetAttribute("TimeLeft", tdm.Length)
	M:SetAttribute("Combat", false)
	M:SetAttribute("Mode", "")
	M:SetAttribute("MapName", MapService.CurrentName())
	votes = nil
	M:SetAttribute("VoteMaps", "")
	M:SetAttribute("VoteCounts", "")
	M:SetAttribute("VoteStart", 0)
	M:SetAttribute("VoteEnds", 0)
	M:SetAttribute("VoteWinner", "")
	M:SetAttribute("BlueRoster", "[]")
	M:SetAttribute("RedRoster", "[]")
	M:SetAttribute("Winner", "")
	M:SetAttribute("EndReason", "")
	M:SetAttribute("Overtime", false)
	M:SetAttribute("Results", "")
	M:SetAttribute("LiveStart", 0)
end
resetBoard()
M:SetAttribute("MatchId", 0)
M:SetAttribute("AllowSkip", Config.AllowSkip)
setPhase("Idle")

-- ─── queue ────────────────────────────────────────────────────────────────────────────────────────────────────────
local queue: { { Player: Player, Mode: string } } = {}
local match = nil -- { Id, Mode, Players = { [Player] = teamName }, Ready = {}, Started = { Blue, Red }, Zones }
local matchCounter = 0

local function queueIndex(p: Player): number?
	for i, q in queue do
		if q.Player == p then
			return i
		end
	end
	return nil
end

local function queueCount(modeId: string): number
	local n = 0
	for _, q in queue do
		if q.Mode == modeId and q.Player.Parent then
			n += 1
		end
	end
	return n
end

local function publishQueue()
	for id in Config.Modes do
		M:SetAttribute("Queue_" .. id, queueCount(id))
	end
end
publishQueue()

-- status: "Queued" | "Match" | nil. Queued players carry QueueMode, match players MatchId.
local function setStatus(p: Player, status: string?, queueMode: string?, matchId: number?)
	p:SetAttribute("QueueMode", queueMode)
	p:SetAttribute("MatchId", matchId)
	p:SetAttribute("MatchStatus", status)
end

-- ─── match helpers ──────────────────────────────────────────────────────────────────────────────────────────────────
local function teamCount(teamName: string): number
	local n = 0
	if match then
		for p, t in match.Players do
			if t == teamName and p.Parent then
				n += 1
			end
		end
	end
	return n
end

local function memberCount(): number
	return teamCount("Blue") + teamCount("Red")
end

local function publishRosters()
	for _, t in TEAM_NAMES do
		local names = {}
		if match then
			for p, team in match.Players do
				if team == t and p.Parent then
					table.insert(names, p.DisplayName)
				end
			end
		end
		table.sort(names)
		M:SetAttribute(t .. "Roster", HttpService:JSONEncode(names))
	end
end

-- spawn zone per team: the X/Z box around that team's SpawnLocations, padded
local function buildZones()
	local zones = {}
	local map = Workspace:FindFirstChild(Config.Map.Folder)
	if not map then
		return zones
	end
	for _, d in map:GetDescendants() do
		if d:IsA("SpawnLocation") and not d.Neutral then
			for _, t in TEAM_NAMES do
				local team = Teams:FindFirstChild(t) :: Team?
				if team and team.TeamColor == d.TeamColor then
					local z = zones[t] or { Min = Vector2.new(math.huge, math.huge), Max = Vector2.new(-math.huge, -math.huge) }
					local h = d.Size / 2
					z.Min = Vector2.new(math.min(z.Min.X, d.Position.X - h.X), math.min(z.Min.Y, d.Position.Z - h.Z))
					z.Max = Vector2.new(math.max(z.Max.X, d.Position.X + h.X), math.max(z.Max.Y, d.Position.Z + h.Z))
					zones[t] = z
				end
			end
		end
	end
	local pad = Config.SpawnZonePad
	for t, z in zones do
		z.Min -= Vector2.new(pad, pad)
		z.Max += Vector2.new(pad, pad)
		-- published so the client can draw the boundary
		M:SetAttribute("Zone_" .. t, Vector3.new(z.Min.X, z.Min.Y, 0))
		M:SetAttribute("ZoneMax_" .. t, Vector3.new(z.Max.X, z.Max.Y, 0))
	end
	return zones
end

local holdConn: RBXScriptConnection? = nil
local function holdInZones(on: boolean)
	if holdConn then
		holdConn:Disconnect()
		holdConn = nil
	end
	if not on or not match then
		return
	end
	local m = match
	local nextCheck = 0
	holdConn = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		if t < nextCheck then
			return
		end
		nextCheck = t + 0.1
		for p, teamName in m.Players do
			local z = m.Zones[teamName]
			local c = p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if z and root then
				local pos = root.Position
				if pos.X < z.Min.X or pos.X > z.Max.X or pos.Z < z.Min.Y or pos.Z > z.Max.Y then
					local inset = 2
					local x = math.clamp(pos.X, z.Min.X + inset, z.Max.X - inset)
					local zz = math.clamp(pos.Z, z.Min.Y + inset, z.Max.Y - inset)
					if exempt then
						exempt:Fire(p, 0.75)
					end
					local rot = root.CFrame - root.Position
					c:PivotTo(CFrame.new(x, pos.Y, zz) * rot)
					root.AssemblyLinearVelocity = Vector3.zero
					p:SetAttribute("ZoneBounce", (p:GetAttribute("ZoneBounce") or 0) + 1)
				end
			end
		end
	end)
end

-- ─── per-player match lines (results, reconnect) ────────────────────────────────────────────────
local STAT_ATTR = {
	K = "MatchStats_Kills", D = "MatchStats_Deaths", A = "MatchStats_Assists", HS = "MatchStats_Headshots",
	Dmg = "MatchStats_Damage", REQ = "MatchStats_REQ", ORD = "MatchStats_ORD", XP = "MatchStats_XP",
	Score = "MatchStats_Score",
}
local function rating(r): number
	local W = Config.MVP
	return r.K * W.Kill + r.A * W.Assist + r.HS * W.Headshot + r.Dmg * W.Damage + r.D * W.Death
end
local function rowOf(p: Player, team: string)
	local r: any = { U = p.UserId, N = p.DisplayName, Name = p.Name, T = team }
	for k, attr in STAT_ATTR do
		r[k] = tonumber(p:GetAttribute(attr)) or 0
	end
	r.Dmg = math.floor(r.Dmg + 0.5)
	r.R = math.floor(rating(r) + 0.5)
	return r
end
-- deterministic order: rating, kills, fewer deaths, assists, damage, lower UserId
local function better(a, b): boolean
	if a.R ~= b.R then return a.R > b.R end
	if a.K ~= b.K then return a.K > b.K end
	if a.D ~= b.D then return a.D < b.D end
	if a.A ~= b.A then return a.A > b.A end
	if a.Dmg ~= b.Dmg then return a.Dmg > b.Dmg end
	return a.U < b.U
end

local function publishVotes()
	if not votes then
		return
	end
	local counts = {}
	for _, id in votes.Choices do
		counts[id] = 0
	end
	for p, id in votes.ByPlayer do
		if p.Parent and counts[id] then
			counts[id] += 1
		end
	end
	M:SetAttribute("VoteCounts", HttpService:JSONEncode(counts))
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- everyone in the match back to the menu: no team, no character
local function cleanup()
	holdInZones(false)
	local m = match
	match = nil
	if m then
		for p in m.Players do
			if p.Parent then
				setStatus(p, nil)
				p.Team = nil
				p.Neutral = true
				local c = p.Character
				p.Character = nil
				if c then
					c:Destroy()
				end
			end
		end
	end
	resetBoard()
	setPhase("Idle")
end

local tryStart -- forward

-- waits until the phase deadline; false if the match emptied (it is then cancelled)
local function waitUntil(deadline: number, m): boolean
	while now() < deadline do
		if match ~= m then
			return false
		end
		if memberCount() == 0 then
			cleanup()
			return false
		end
		task.wait(0.05)
	end
	return match == m
end

-- the final board: every participant (present + left), MVP of the winning team, top performer
local function publishResults(m, winner: string, reason: string)
	local rows = {}
	for p, teamName in m.Players do
		if p.Parent then
			table.insert(rows, rowOf(p, teamName))
		end
	end
	for _, d in m.Departed do
		local r = table.clone(d.Row)
		r.Left = true
		table.insert(rows, r)
	end
	table.sort(rows, better)
	local mvp, top = nil, nil
	for _, r in rows do
		if not r.Left then
			top = top or r
			if not mvp and (winner == "Draw" or r.T == winner) then
				mvp = r
			end
		end
	end
	local live0 = M:GetAttribute("LiveStart") or 0
	local res = {
		Id = m.Id, Mode = m.Mode, Winner = winner, Reason = reason,
		Blue = M:GetAttribute("BlueScore") or 0, Red = M:GetAttribute("RedScore") or 0,
		Limit = M:GetAttribute("ScoreLimit") or 0, Overtime = m.Overtime == true,
		Duration = if live0 > 0 then math.floor(now() - live0 + 0.5) else 0,
		MVP = if mvp then mvp.U else 0, Top = if top then top.U else 0,
		Rows = rows,
	}
	M:SetAttribute("Results", HttpService:JSONEncode(res))
	return res
end

-- a player leaves the finished match early (results CONTINUE / PLAY AGAIN): back to the lobby
local function release(m, p: Player)
	m.Players[p] = nil
	m.Ready[p] = nil
	setStatus(p, nil)
	p.Team = nil
	p.Neutral = true
	local c = p.Character
	p.Character = nil
	if c then
		c:Destroy()
	end
end

local function endMatch(m, winner: string, reason: string)
	if match ~= m then
		return
	end
	M:SetAttribute("Combat", false)
	M:SetAttribute("Winner", winner)
	M:SetAttribute("EndReason", reason)
	for p, teamName in m.Players do
		if p.Parent then
			local ok, err = pcall(Progression.OnMatchEnd, p, teamName == winner)
			local pm = script.Parent:FindFirstChild("ProfileMatch") -- profile history + ranked RP (ProfileService)
			if pm then pm:Fire(p, teamName, winner, m.Mode, M:GetAttribute("BlueScore") or 0, M:GetAttribute("RedScore") or 0) end
			if not ok then
				warn("[VANTAGE] Progression match end: " .. tostring(err))
			end
		end
	end
	-- results after the match-end rewards, so the board carries the full match earnings
	local okRes, resErr = pcall(publishResults, m, winner, reason)
	if not okRes then
		warn("[VANTAGE] match results: " .. tostring(resErr))
	end
	-- freeze the field for the results sequence
	for p in m.Players do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
		end
	end
	setPhase("Ended", Config.EndTime)
	-- hold the results until the time is up or everyone has left them (CONTINUE / PLAY AGAIN)
	local deadline = now() + Config.EndTime
	while now() < deadline and match == m and memberCount() > 0 do
		task.wait(0.1)
	end
	if match == m then
		cleanup()
	end
	tryStart(false)
end

-- ─── backfill / reconnect ────────────────────────────────────────────────────────
local function canBackfill(m, modeId: string): boolean
	local B = Config.Backfill
	return B ~= nil and B.Enabled == true and match == m and m.Mode == modeId and m.LiveOn == true
		and M:GetAttribute("Phase") == "Live" and M:GetAttribute("Combat") == true and not m.Overtime
		and (M:GetAttribute("TimeLeft") or 0) >= B.MinTimeLeft
end

local function spawnBackfill(m, p: Player)
	if match == m and m.Players[p] and m.Pending[p] and p.Parent and M:GetAttribute("Phase") == "Live" then
		m.Pending[p] = nil
		if exempt then
			exempt:Fire(p, 2)
		end
		p:LoadCharacter()
	end
end

-- puts p on the smaller team (their old team on a tie); false if there is no fair slot
local function backfill(m, p: Player): boolean
	local mode = Config.Modes[m.Mode]
	local b, r = teamCount("Blue"), teamCount("Red")
	local prev = m.Departed[p.UserId]
	local team = if b < r then "Blue" elseif r < b then "Red" elseif prev then prev.Row.T elseif math.random() < 0.5 then "Blue" else "Red"
	if teamCount(team) >= mode.TeamSize then
		return false
	end
	if prev then
		-- same match again: restore the line first, then mark it as this match's so
		-- MatchStatsServer keeps it (it only zeroes lines that belong to another match)
		for k, attr in STAT_ATTR do
			p:SetAttribute(attr, prev.Row[k] or 0)
		end
		p:SetAttribute("MatchStats_MatchId", m.Id)
		m.Departed[p.UserId] = nil
	else
		p:SetAttribute("MatchStats_Assists", 0)
	end
	m.Players[p] = team
	m.Pending[p] = true
	p.Neutral = false
	p.Team = Teams:FindFirstChild(team) :: Team
	setStatus(p, "Match", nil, m.Id)
	publishRosters()
	-- the client plays the dropship clip and sends Ready; never wait longer than a deploy
	task.delay(Config.DeployTimeout, spawnBackfill, m, p)
	return true
end

-- queued players for the running mode fill open slots
local function fillFromQueue(m)
	local i = 1
	while i <= #queue do
		local q = queue[i]
		if q.Player.Parent and canBackfill(m, q.Mode) and backfill(m, q.Player) then
			table.remove(queue, i)
			publishQueue()
		else
			i += 1
		end
	end
end

local function runMatch(modeId: string, picked: { Player })
	local mode = Config.Modes[modeId]
	matchCounter += 1
	local m = { Id = matchCounter, Mode = modeId, Players = {}, Ready = {}, Started = { Blue = 0, Red = 0 }, Zones = {}, Departed = {}, Pending = {} }
	match = m

	-- teams: shuffled, alternating, random first side (balanced to within one)
	shuffle(picked)
	local first = if math.random() < 0.5 then "Blue" else "Red"
	local second = if first == "Blue" then "Red" else "Blue"
	for i, p in picked do
		local teamName = if i % 2 == 1 then first else second
		m.Players[p] = teamName
		m.Started[teamName] += 1
		p.Neutral = false
		p.Team = Teams:FindFirstChild(teamName) :: Team
		setStatus(p, "Match", nil, m.Id)
	end
	resetBoard()
	M:SetAttribute("Mode", modeId)
	M:SetAttribute("ScoreLimit", mode.ScoreLimit)
	M:SetAttribute("TimeLeft", mode.Length)
	M:SetAttribute("MatchId", m.Id)
	publishRosters()

	-- MATCH FOUND + MAP VOTE (2026-11-18): the card shows the teams for MapVote.Intro, then the
	-- map vote for MapVote.Time, then the winner for MapVote.Reveal. The winning map is moved into
	-- Workspace as the vote closes; spawn zones are built from it afterwards.
	local V = Config.MapVote
	local choices = MapService.Candidates(modeId, V and V.Choices or 3)
	if V and V.Enabled and #choices > 1 then
		local t0 = now()
		votes = { Choices = choices, ByPlayer = {}, Open = false, Match = m }
		M:SetAttribute("VoteMaps", HttpService:JSONEncode(choices))
		M:SetAttribute("VoteStart", t0 + V.Intro)
		M:SetAttribute("VoteEnds", t0 + V.Intro + V.Time)
		M:SetAttribute("VoteWinner", "")
		publishVotes()
		setPhase("Found", V.Intro + V.Time + V.Reveal)
		if not waitUntil(t0 + V.Intro, m) then
			return
		end
		votes.Open = true
		if not waitUntil(t0 + V.Intro + V.Time, m) then
			return
		end
		votes.Open = false
		local winner = MapService.Tally(choices, votes.ByPlayer)
		MapService.Load(winner)
		M:SetAttribute("VoteWinner", winner)
		if not waitUntil(t0 + V.Intro + V.Time + V.Reveal, m) then
			return
		end
	else
		MapService.Load(choices[1])
		M:SetAttribute("MapName", MapService.CurrentName())
		setPhase("Found", Config.FoundTime)
		if not waitUntil(now() + Config.FoundTime, m) then
			return
		end
	end
	-- 2026-11-20: map size follows the team size (1v1/2v2 small, 3v3/4v4 medium, 5v5/6v6 full map)
	local okSize, errSize = pcall(MapService.ApplySize, Config.SizeClass and Config.SizeClass(mode.TeamSize) or "L")
	if not okSize then
		warn("[MatchService] ApplySize: " .. tostring(errSize))
	end
	m.Zones = buildZones()

	-- DEPLOY: clients play the dropship clip and report Ready; slow loaders get DeployTimeout
	local deployStart = now()
	setPhase("Deploy", Config.DeployTimeout)
	while now() - deployStart < Config.DeployTimeout do
		if match ~= m then
			return
		end
		if memberCount() == 0 then
			cleanup()
			return
		end
		local all = true
		for p in m.Players do
			if p.Parent and not m.Ready[p] then
				all = false
				break
			end
		end
		if all and now() - deployStart >= Config.DeployMinTime then
			break
		end
		task.wait(0.1)
	end

	-- spawn everyone at their team's SpawnLocations (TeamSpawnServer handles later respawns)
	for p in m.Players do
		if p.Parent then
			task.spawn(function()
				if exempt then
					exempt:Fire(p, 2)
				end
				p:LoadCharacter()
			end)
		end
	end

	-- OPERATIVE INTRODUCTION: everyone held in formation while the clients play the cinematic
	-- (skipped entirely when MatchConfig.Intro.Enabled is false)
	if not IntroService.Run(m, { M = M, now = now, setPhase = setPhase, waitUntil = waitUntil, exempt = exempt }) then
		return
	end

	-- PREPARATION: move / inspect / visor, no damage, held in the spawn zone
	setPhase("Prep", Config.PrepTime)
	holdInZones(true)
	if not waitUntil(now() + Config.PrepTime, m) then
		return
	end

	-- FINAL COUNTDOWN
	setPhase("Countdown", Config.CountdownTime)
	if not waitUntil(now() + Config.CountdownTime, m) then
		return
	end

	-- LIVE
	holdInZones(false)
	M:SetAttribute("Combat", true)
	local liveEnds = now() + mode.Length
	M:SetAttribute("LiveStart", now())
	m.LiveOn = true
	setPhase("Live", mode.Length)
	-- the deciding elimination switches combat off on the same frame, so nothing lands after it
	local function onScore()
		if match ~= m or M:GetAttribute("Phase") ~= "Live" then
			return
		end
		local bs, rs = M:GetAttribute("BlueScore") or 0, M:GetAttribute("RedScore") or 0
		if bs >= mode.ScoreLimit or rs >= mode.ScoreLimit or (m.Overtime and bs ~= rs) then
			M:SetAttribute("Combat", false)
		end
	end
	local scoreConns = { M:GetAttributeChangedSignal("BlueScore"):Connect(onScore), M:GetAttributeChangedSignal("RedScore"):Connect(onScore) }
	local function stopScore()
		for _, c in scoreConns do
			c:Disconnect()
		end
	end
	local nextFill = 0
	local lastLeftSec: number? = nil
	while match == m do
		local left = math.max(0, liveEnds - now())
		-- C2: every TimeLeft consumer renders whole seconds; replicate only when the second flips
		if math.floor(left) ~= lastLeftSec then
			lastLeftSec = math.floor(left)
			M:SetAttribute("TimeLeft", left)
		end
		local bs, rs = M:GetAttribute("BlueScore") or 0, M:GetAttribute("RedScore") or 0
		local lead = if bs > rs then "Blue" elseif rs > bs then "Red" else "Draw"
		if bs >= mode.ScoreLimit or rs >= mode.ScoreLimit then
			stopScore()
			endMatch(m, lead, "SCORE")
			return
		end
		if m.Overtime and bs ~= rs then
			stopScore()
			endMatch(m, lead, "OVERTIME")
			return
		end
		if left <= 0 then
			if lead == "Draw" and mode.Overtime and Config.Overtime and not m.Overtime then
				-- SUDDEN DEATH: the next elimination wins
				m.Overtime = true
				liveEnds = now() + Config.Overtime.Length
				M:SetAttribute("PhaseEnds", liveEnds)
				M:SetAttribute("TimeLeft", Config.Overtime.Length)
				M:SetAttribute("Overtime", true)
			else
				M:SetAttribute("TimeLeft", left) -- final tick: leave the ended board's clock at 0:00
				stopScore()
				endMatch(m, lead, if m.Overtime then "OVERTIME" else "TIME")
				return
			end
		end
		if os.clock() >= nextFill then
			nextFill = os.clock() + 1
			fillFromQueue(m)
		end
		if memberCount() == 0 then
			cleanup()
			tryStart(false)
			return
		end
		-- a side that started with players and now has none forfeits
		for _, t in TEAM_NAMES do
			if m.Started[t] > 0 and teamCount(t) == 0 and Workspace:GetAttribute("LiveBots") ~= true then -- bots take over an emptied side
				stopScore()
				endMatch(m, if t == "Blue" then "Red" else "Blue", "FORFEIT")
				return
			end
		end
		task.wait(0.05)
	end
	stopScore()
end

function tryStart(force: boolean, modeId: string?)
	if match then
		return false
	end
	local chosen = modeId
	if not force then
		chosen = nil
		for id, mode in Config.Modes do
			if mode.Live and queueCount(id) >= Config.Needed(id) then
				chosen = id
				break
			end
		end
	end
	if not chosen then
		return false
	end
	local need = Config.Needed(chosen)
	local picked = {}
	local i = 1
	while i <= #queue and #picked < need do
		local q = queue[i]
		if q.Mode == chosen and q.Player.Parent then
			table.insert(picked, q.Player)
			table.remove(queue, i)
		else
			i += 1
		end
	end
	publishQueue()
	if #picked == 0 then
		return false
	end
	task.spawn(runMatch, chosen, picked)
	return true
end

-- ─── requests ──────────────────────────────────────────────────────────────────────────────────────────────────────────
request.OnServerInvoke = function(p: Player, action: any, arg: any)
	if not Remotes.rate(p, "MatchRequest", 0.15) then
		return false, "SLOW DOWN"
	end
	if action == "Queue" then
		local mode = type(arg) == "string" and Config.Modes[arg]
		if not mode then
			return false, "UNKNOWN MODE"
		end
		if not mode.Live then
			return false, "MODE NOT AVAILABLE YET"
		end
		if match and match.Players[p] then
			return false, "ALREADY IN A MATCH"
		end
		local i = queueIndex(p)
		if i then
			queue[i].Mode = arg -- re-queue is idempotent (never two entries)
		else
			table.insert(queue, { Player = p, Mode = arg })
		end
		setStatus(p, "Queued", arg)
		publishQueue()
		-- a match of this mode is running with a fair open slot: join it now
		if match and canBackfill(match, arg) then
			fillFromQueue(match)
			if match and match.Players[p] then
				return true, "JOINING"
			end
		end
		tryStart(false)
		return true, "QUEUED"
	elseif action == "Cancel" then
		local i = queueIndex(p)
		if not i then
			return false, "NOT QUEUED"
		end
		table.remove(queue, i)
		setStatus(p, nil)
		publishQueue()
		return true
	elseif action == "Skip" then
		if not Config.AllowSkip then
			return false, "SKIP DISABLED"
		end
		local i = queueIndex(p)
		if not i then
			return false, "NOT QUEUED"
		end
		if match then
			return false, "MATCH IN PROGRESS"
		end
		return tryStart(true, queue[i].Mode), "STARTING"
	elseif action == "Ready" then
		if match and match.Players[p] and M:GetAttribute("Phase") == "Deploy" then
			match.Ready[p] = true
		elseif match and match.Players[p] and match.Pending[p] then
			spawnBackfill(match, p) -- joined a running match: drop in now
		end
		return true
	elseif action == "Vote" then
		-- MATCH FOUND map vote: players of the match being found, while the vote is open; a new
		-- vote replaces the old one
		if not (votes and votes.Open and match and votes.Match == match and match.Players[p]) then
			return false, "VOTING CLOSED"
		end
		if type(arg) ~= "string" or not table.find(votes.Choices, arg) then
			return false, "UNKNOWN MAP"
		end
		votes.ByPlayer[p] = arg
		publishVotes()
		return true
	elseif action == "Leave" then
		-- results screen CONTINUE / PLAY AGAIN: only once the match is over
		if match and match.Players[p] and M:GetAttribute("Phase") == "Ended" then
			release(match, p)
			return true
		end
		return false, "NOT IN RESULTS"
	end
	return false, "BAD REQUEST"
end

Players.PlayerRemoving:Connect(function(p)
	local i = queueIndex(p)
	if i then
		table.remove(queue, i)
		publishQueue()
	end
	if match and match.Players[p] then
		-- keep their line for the results board and for a reconnect into this match
		local ph = M:GetAttribute("Phase")
		if ph == "Live" or ph == "Ended" then
			match.Departed[p.UserId] = { Row = rowOf(p, match.Players[p]) }
		end
		match.Players[p] = nil
		match.Ready[p] = nil
		match.Pending[p] = nil
		publishRosters()
	end
	if votes and votes.ByPlayer[p] then
		votes.ByPlayer[p] = nil
		publishVotes()
	end
end)
