--[[
	VANTAGE CONTROL — server (ServerScriptService.VantageControl)
	Decides WHEN each player hears a VANTAGE CONTROL line, from server-authoritative state only,
	and tells that one player (Remotes.VantageControl:FireClient(player, key, serverTime)).
	It only reads existing systems — nothing in matchmaking, damage, shields, scoring or respawn
	is changed:
	  #1 Deployment     Match.Phase -> "Deploy", once per MatchId per player (respawns never change Phase)
	  #2 Engage         Match.Phase -> "Live", once per MatchId per player
	  #3 Contact        server scan: nearest enemy within ContactRange + line of sight, cooldown
	  #4 Kill           client side: Remotes.Elimination "Confirm" (EliminationService sends it only to
	                    the player credited with the kill)
	  #5/#6/#7 Shield   the replicated character attributes Shield / MaxShield (set by ShieldService)
	  #8 Down           Humanoid.Died of a match player
	  #9 Losing         Match.BlueScore / RedScore during Live, with margin + re-arm hysteresis
	  #10 Victory       Match.Phase -> "Ended" with Winner == the player's team (never on "Draw")
	  #11 AircraftInbound  a dropship flyby is published (Vantage.Aircraft FlightId), every match player

	Install: static Rojo layout — the config ships in ReplicatedStorage.Vantage and the client
	in StarterPlayerScripts; this script only wires the remote and decides when lines play.

	Studio tests (Studio only): type "/vc 1" … "/vc 10", "/vc burst" or "/vc seq" in chat, or from the
	command bar while playing:  game.ServerScriptService.VantageControl.Test:Fire(player, "ShieldFail")
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- ─── install ─────────────────────────────────────────────────────────────────
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = require(Vantage:WaitForChild("RemotesLib"))
local Cfg = require(Vantage:WaitForChild("VantageControlConfig"))
local LINES = Cfg.Lines

local remote = Remotes.get("VantageControl") :: RemoteEvent

local M = Vantage:WaitForChild("Match") -- created by DamageService / MatchService

-- ─── helpers ─────────────────────────────────────────────────────────────────
local function now(): number
	return Workspace:GetServerTimeNow()
end

local function phase(): string
	return M:GetAttribute("Phase") or "Idle"
end

local function teamOf(p: Player): string?
	if p.Team and not p.Neutral then
		return p.Team.Name
	end
	return nil
end

-- in the match that is running right now
local function inMatch(p: Player): boolean
	return p.Parent ~= nil
		and p:GetAttribute("MatchStatus") == "Match"
		and p:GetAttribute("MatchId") == M:GetAttribute("MatchId")
		and teamOf(p) ~= nil
end

local function alive(model: Model?): (boolean, BasePart?)
	if not model then
		return false, nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hum ~= nil and hum.Health > 0 and root ~= nil, root
end

-- per-player state
type PState = {
	Sent: { [string]: number },
	DeployMatch: number,
	EngageMatch: number,
	VictoryMatch: number,
	ContactActive: boolean,
	LastSeen: number,
	LastContact: number,
}
local state: { [Player]: PState } = {}

local function st(p: Player): PState
	local s = state[p]
	if not s then
		s = { Sent = {}, DeployMatch = 0, EngageMatch = 0, VictoryMatch = 0, ContactActive = false, LastSeen = -math.huge, LastContact = -math.huge }
		state[p] = s
	end
	return s
end

-- the one place a line leaves the server (server-side duplicate guard on each line's Cooldown)
local function send(p: Player, key: string, force: boolean?)
	local line = LINES[key]
	if not line or not p.Parent then
		return
	end
	local s = st(p)
	local t = os.clock()
	if not force and s.Sent[key] and t - s.Sent[key] < (line.Cooldown or 0) then
		return
	end
	s.Sent[key] = t
	remote:FireClient(p, key, now(), force == true and RunService:IsStudio())
end

local function matchPlayers(team: string?): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if inMatch(p) and (team == nil or teamOf(p) == team) then
			table.insert(list, p)
		end
	end
	return list
end

-- ─── #9 losing ground ─────────────────────────────────────────────────────────
local teamState = {}
local function resetLosing()
	teamState = {
		Blue = { Armed = true, Last = -math.huge, Deficit = 0 },
		Red = { Armed = true, Last = -math.huge, Deficit = 0 },
	}
end
resetLosing()

local function checkScores()
	if phase() ~= "Live" then
		return
	end
	local scores = { Blue = M:GetAttribute("BlueScore") or 0, Red = M:GetAttribute("RedScore") or 0 }
	local limit = M:GetAttribute("ScoreLimit") or math.huge
	local cooldown = LINES.Losing.Cooldown
	for team, ts in teamState do
		local enemy = if team == "Blue" then "Red" else "Blue"
		local deficit = scores[enemy] - scores[team]
		local t = os.clock()
		if deficit <= Cfg.LosingRearmAt then
			ts.Armed = true
			ts.Deficit = 0
		elseif scores[enemy] < limit and t - ts.Last >= cooldown then
			local first = ts.Armed and deficit >= Cfg.LosingMargin
			local worse = not ts.Armed and deficit >= ts.Deficit + Cfg.LosingEscalate
			if first or worse then
				ts.Armed = false
				ts.Deficit = deficit
				ts.Last = t
				for _, p in matchPlayers(team) do
					send(p, "Losing")
				end
			end
		end
	end
end
M:GetAttributeChangedSignal("BlueScore"):Connect(checkScores)
M:GetAttributeChangedSignal("RedScore"):Connect(checkScores)

-- ─── #1 / #2 / #10 match phases ──────────────────────────────────────────────
local liveSince = -math.huge
M:GetAttributeChangedSignal("Phase"):Connect(function()
	local ph = phase()
	local id = M:GetAttribute("MatchId") or 0
	if ph == "Deploy" then
		for _, p in matchPlayers() do
			local s = st(p)
			if s.DeployMatch ~= id then
				s.DeployMatch = id
				send(p, "Deployment")
			end
		end
	elseif ph == "Live" then
		liveSince = os.clock()
		resetLosing()
		for _, p in matchPlayers() do
			local s = st(p)
			s.ContactActive, s.LastSeen, s.LastContact = false, -math.huge, -math.huge
			if s.EngageMatch ~= id then
				s.EngageMatch = id
				send(p, "Engage")
			end
		end
	elseif ph == "Ended" then
		local winner = M:GetAttribute("Winner")
		if winner == "Blue" or winner == "Red" then
			for _, p in matchPlayers(winner) do
				local s = st(p)
				if s.VictoryMatch ~= id then
					s.VictoryMatch = id
					send(p, "Victory")
				end
			end
		end
	end
end)

-- ─── #5 / #6 / #7 shield, #8 down (per character) ───────────────────────────
local DOWN_PHASES = { Prep = true, Countdown = true, Live = true }

local function watchCharacter(p: Player, character: Model)
	local conns: { RBXScriptConnection } = {}
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum or character.Parent == nil then
		return
	end

	-- #8: the moment the player dies, before RespawnTime / the death replay hold
	table.insert(conns, hum.Died:Connect(function()
		if inMatch(p) and DOWN_PHASES[phase()] then
			send(p, "Down")
		end
	end))

	-- shield cycle: damaged -> (critical once) -> (broken) -> full again = restored, flags reset
	local prev: number? = nil
	local lowest = 1
	local damaged, critWarned = false, false
	local function onShield()
		local s = character:GetAttribute("Shield")
		local max = character:GetAttribute("MaxShield")
		if type(s) ~= "number" or type(max) ~= "number" or max <= 0 then
			return
		end
		if prev == nil then
			prev = s
			return
		end
		local frac = s / max
		local live = phase() == "Live" and hum.Health > 0 and inMatch(p)
		if s < (prev :: number) - 1e-3 then
			damaged = true
			lowest = math.min(lowest, frac)
			if s <= 0 and (prev :: number) > 0 then
				critWarned = true -- broken this cycle: no late "critical" after the failure call
				if live then
					send(p, "ShieldFail")
				end
			elseif frac < Cfg.CriticalFraction and not critWarned then
				critWarned = true
				if live then
					send(p, "ShieldCritical")
				end
			end
		elseif s > (prev :: number) then
			if critWarned and frac >= Cfg.CriticalRearmFraction then
				critWarned = false -- recovered enough: a new hit cycle can warn again
			end
			if damaged and s >= max - 1e-3 then
				local wasLow = lowest < Cfg.RestoreAfterBelow
				damaged, critWarned, lowest = false, false, 1
				if live and wasLow then
					send(p, "ShieldRestored")
				end
			end
		end
		prev = s
	end
	table.insert(conns, character:GetAttributeChangedSignal("Shield"):Connect(onShield))
	table.insert(conns, character:GetAttributeChangedSignal("MaxShield"):Connect(function()
		prev = nil -- (re)setup: start a clean cycle
		damaged, critWarned, lowest = false, false, 1
		onShield()
	end))
	onShield()

	table.insert(conns, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			for _, c in conns do
				c:Disconnect()
			end
		end
	end))
end

local function onPlayer(p: Player)
	st(p)
	p.CharacterAdded:Connect(function(c)
		watchCharacter(p, c)
	end)
	if p.Character then
		task.spawn(watchCharacter, p, p.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

-- ─── #3 hostile contact ──────────────────────────────────────────────────────
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function hasSight(fromRoot: BasePart, fromChar: Model, target: Model, targetRoot: BasePart): boolean
	if not Cfg.ContactLineOfSight then
		return true
	end
	local origin = fromRoot.Position + Vector3.new(0, 1.5, 0)
	local goal = targetRoot.Position + Vector3.new(0, 1.5, 0)
	rayParams.FilterDescendantsInstances = { fromChar, target }
	return Workspace:Raycast(origin, goal - origin, rayParams) == nil
end

-- every hostile for a team: enemy match players, plus (Studio) training dummies of another team
local function hostiles(team: string): { { Model: Model, Root: BasePart } }
	local list = {}
	for _, p in Players:GetPlayers() do
		if inMatch(p) and teamOf(p) ~= team then
			local ok, root = alive(p.Character)
			if ok then
				table.insert(list, { Model = p.Character :: Model, Root = root :: BasePart })
			end
		end
	end
	if RunService:IsStudio() then
		for _, d in CollectionService:GetTagged("VantageDummy") do
			if d:IsA("Model") and d:IsDescendantOf(Workspace) and d:GetAttribute("Team") ~= team then
				local ok, root = alive(d)
				if ok then
					table.insert(list, { Model = d, Root = root :: BasePart })
				end
			end
		end
	end
	return list
end

task.spawn(function()
	while true do
		task.wait(Cfg.ContactScanRate)
		if phase() == "Live" and os.clock() - liveSince >= Cfg.ContactGrace then
			local cache = {}
			local t = os.clock()
			for _, p in Players:GetPlayers() do
				local team = teamOf(p)
				local ok, root = alive(p.Character)
				if team and ok and inMatch(p) then
					cache[team] = cache[team] or hostiles(team)
					local seen = false
					for _, h in cache[team] do
						if (h.Root.Position - (root :: BasePart).Position).Magnitude <= Cfg.ContactRange
							and hasSight(root :: BasePart, p.Character :: Model, h.Model, h.Root) then
							seen = true
							break
						end
					end
					local s = st(p)
					if seen then
						s.LastSeen = t
						if not s.ContactActive and t - s.LastContact >= Cfg.ContactCooldown then
							s.ContactActive = true
							s.LastContact = t
							send(p, "Contact")
						end
					elseif s.ContactActive and t - s.LastSeen >= Cfg.ContactClear then
						s.ContactActive = false
					end
				end
			end
		end
	end
end)

-- ─── #11 dropship inbound ──────────────────────────────────────────────────────
-- AircraftService publishes each flight as attributes on Vantage.Aircraft; a new FlightId with
-- FlightActive is a flyby starting (still outside the map, hooks open ~15 s later).
task.spawn(function()
	local aircraft = Vantage:WaitForChild("Aircraft", 30)
	if not aircraft then
		return
	end
	local lastId = aircraft:GetAttribute("FlightId") or 0
	aircraft:GetAttributeChangedSignal("FlightId"):Connect(function()
		local id = aircraft:GetAttribute("FlightId") or 0
		if id == 0 or id == lastId then
			return
		end
		lastId = id
		task.defer(function() -- FlightActive is set in the same publish
			if aircraft:GetAttribute("FlightActive") ~= true then
				return
			end
			local list = matchPlayers()
			if #list == 0 and RunService:IsStudio() and phase() ~= "Live" then
				-- Studio playtest without a match (flybys run anyway): everyone with a character
				for _, p in Players:GetPlayers() do
					if p.Character then
						table.insert(list, p)
					end
				end
			end
			for _, p in list do
				send(p, "AircraftInbound")
			end
		end)
	end)
end)

-- ─── Studio-only tests ───────────────────────────────────────────────────────
if RunService:IsStudio() then
	local ORDER = { "Deployment", "Engage", "Contact", "Kill", "ShieldCritical", "ShieldFail", "ShieldRestored", "Down", "Losing", "Victory", "AircraftInbound" }
	local function test(p: Player, what: any)
		if what == "burst" then
			-- priority check: Contact starts, Kill waits, ShieldFail cuts in, Contact-again is a duplicate
			send(p, "Contact", true)
			task.wait(0.15)
			send(p, "Kill", true)
			task.wait(0.15)
			send(p, "ShieldFail", true)
			send(p, "Contact", true)
		elseif what == "seq" then
			for _, k in ORDER do
				send(p, k, true)
				task.wait(4.5)
			end
		else
			local key = ORDER[tonumber(what) or 0] or (LINES[what] and what)
			if key then
				send(p, key, true)
			end
		end
	end
	local bindable = Instance.new("BindableEvent")
	bindable.Name = "Test"
	bindable.Parent = script
	bindable.Event:Connect(function(p, what)
		task.spawn(test, p, what)
	end)
	local function hookChat(p: Player)
		p.Chatted:Connect(function(msg)
			local arg = string.match(msg, "^/vc%s+(%S+)")
			if arg then
				task.spawn(test, p, arg)
			end
		end)
	end
	Players.PlayerAdded:Connect(hookChat)
	for _, p in Players:GetPlayers() do
		hookChat(p)
	end
end
