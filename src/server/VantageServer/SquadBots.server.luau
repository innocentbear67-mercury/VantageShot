--[[
	VANTAGE — SquadBots (Studio only, never runs in a live server)
	A full 5v5 for feel-testing: 4 AI teammates on your team and 5 AI enemies. They leave spawn, path
	through the map, call out contacts to each other, strafe, retreat on a broken shield, reload, and
	fight each other as well as you.
	Grapple: bots hook up to high ground they can't walk to, Rifleman / Breacher / Suppressor hook in to
	close a long gap, and a bot whose shield breaks may hook away to escape (server-driven pull; every
	client draws the cable through the normal Ability remote).
	Vehicles: Push / Flank bots may take a tank, APC or buggy from their own bay (max 2 per team), drive
	it on hull-sized paths that avoid the centre pits, work the turret, run people over, and bail out
	when it's nearly dead, stuck or trapped. Sit in the gunner seat of a teammate bot's vehicle and
	you get the turret while it drives (VehicleService.BotEnter / BotControl / BotRelease).
	Every shot uses the real WeaponConfig gun (rate, damage, falloff,
	headshot / limb multipliers, magazine, reload, pellets, Arc heat) and goes through ShieldService,
	the kill feed / elimination effects (EliminationService) and team outlines (Team attribute).
	Kills by or on bots add to the team score while the match is Live.

	Chat (Studio playtest):
	  /squad                 4 allies + 5 enemies, normal difficulty (replaces any squad)
	  /squad easy|normal|hard
	  /squad hard 4 5        difficulty, ally count, enemy count (any order of words, counts in order)
	  /squad clear           remove every squad bot
	Command bar while playing:  game.ServerScriptService.VantageServer.SquadBots.Command:Invoke(player, "hard")

	Bots hold in their spawn until Match.Combat is on (the Live phase). The squad clears itself
	when the match returns to Idle. The single CombatBot stands down while a squad exists.
]]

local ENABLED = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local TextChatService = game:GetService("TextChatService")
local StarterPlayer = game:GetService("StarterPlayer")
local Teams = game:GetService("Teams")

local STUDIO = RunService:IsStudio()
local MatchConfig = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("MatchConfig"))
local FILL = MatchConfig.BotFill or {}
-- 2026-11-19: live servers run the bots too (bot fill); the /squad chat commands stay Studio-only
local LIVE_BOTS = FILL.Enabled == true
Workspace:SetAttribute("LiveBots", LIVE_BOTS)
if not ENABLED or not (STUDIO or LIVE_BOTS) then
	return
end
local FILL_HERE = LIVE_BOTS and (not STUDIO or FILL.InStudio ~= false)
local BOT_SUFFIX = FILL.NameSuffix or " [BOT]"

local WeaponServer = script.Parent:WaitForChild("WeaponServer")
local hook = WeaponServer:WaitForChild("WeaponDebug") :: BindableFunction
local EliminationService = require(WeaponServer.EliminationService)
local ShieldService = require(WeaponServer.ShieldService)
local DamageService = require(WeaponServer.DamageService)
local Weapons = ReplicatedStorage.Vantage.Weapons
local Config = require(Weapons.WeaponConfig)
local WeaponMath = require(Weapons.WeaponMath)
local Remotes = ReplicatedStorage.Vantage.Remotes
local EventRemote = Remotes.WeaponEvent :: RemoteEvent
local Match = DamageService.MatchFolder()
local VehicleService = require(script.Parent:WaitForChild("VehicleService"))
local VehicleConfig = require(ReplicatedStorage.Vantage.Vehicles.VehicleConfig)
local AbilityConfig = require(ReplicatedStorage.Vantage.Abilities.AbilityConfig)
local G = AbilityConfig.Abilities.Grapple
local AbilityRemote = Remotes:FindFirstChild("Ability") :: RemoteEvent?

local MsgRemote = Remotes:FindFirstChild("SquadBotsMsg") :: RemoteEvent?
if not MsgRemote then
	local r = Instance.new("RemoteEvent")
	r.Name = "SquadBotsMsg"
	r.Parent = Remotes
	MsgRemote = r
end

-- ─── tuning ─────────────────────────────────────────────────────────────────
local TICK = 0.1
local VISION = 420 -- studs a bot can spot someone at
local FOV_COS = math.cos(math.rad(80)) -- half-angle of what it notices ahead
local HEAR = 35 -- always notices hostiles this close, even behind it
local MEMORY = 5 -- seconds a last-known position is still worth chasing
local CALLOUT_RANGE = 170 -- teammates within this distance react to a callout
local RESPAWN = 5
local BASE_SPEED = StarterPlayer.CharacterWalkSpeed
local TURN_RATE = math.rad(540) -- deg/s the body turns toward its target

-- grapple (same reach / pull feel as the player's, a little tamer)
local BOT_GRAPPLE_RANGE = math.min(G.Range or 110, 150)
local BOT_GRAPPLE_SPEED = (G.MaxSpeed or 90) * 0.8
local GRAPPLE_RUSH = { Rifleman = true, Breacher = true, Sidearm = true, Suppressor = true } -- hook in to close a long gap

-- vehicles: Push / Flank bots may take one of their team's tanks, APCs or buggies
local VEHICLE_CHANCE = 0.65
local MAX_BOT_VEHICLES = 2 -- per team, at once
local VEHICLE_SEARCH = 220 -- studs a bot will walk to reach one
local VEHICLE_STANDOFF = { Tank = 120, APC = 75, Buggy = 30 } -- closes to this, then circles
local PIT_Y = -8 -- vehicle paths never dip below this (the centre pits trap hulls)

local DIFFICULTY = {
	easy = { Spread = 1.7, Reaction = 1.6, Head = 0.5, Label = "EASY" },
	normal = { Spread = 1.0, Reaction = 1.0, Head = 1.0, Label = "NORMAL" },
	hard = { Spread = 0.6, Reaction = 0.6, Head = 1.5, Label = "HARD" },
}

-- Range = preferred fight distance {min, max}. Spread = aim error cone (deg). Head = share of shots at
-- the head. Reaction = seconds from first sight to first shot. Burst / Pause = trigger discipline.
local ROLES = {
	Rifleman = { Weapon = "Vanguard", Range = { 25, 110 }, Spread = 2.0, Head = 0.2, Reaction = 0.45, Burst = { 5, 10 }, Pause = { 0.25, 0.6 }, Strafe = true },
	Breacher = { Weapon = "Breacher", Range = { 5, 22 }, Spread = 1.2, Head = 0.15, Reaction = 0.3, Pause = { 0.05, 0.2 }, Strafe = true, Melee = true },
	Marksman = { Weapon = "Sentinel", Range = { 45, 190 }, Spread = 1.1, Head = 0.3, Reaction = 0.55, Pause = { 0.2, 0.5 }, Strafe = true, Ads = true },
	Sniper = { Weapon = "Longshot", Range = { 110, 420 }, Spread = 0.45, Head = 0.35, Reaction = 0.95, Pause = { 0.3, 0.9 }, Strafe = false, Ads = true },
	Suppressor = { Weapon = "Arc", Range = { 25, 140 }, Spread = 2.4, Head = 0.12, Reaction = 0.4, Burst = { 8, 16 }, Pause = { 0.3, 0.7 }, Strafe = true },
	Sidearm = { Weapon = "Spectre", Range = { 15, 70 }, Spread = 1.6, Head = 0.25, Reaction = 0.4, Pause = { 0.12, 0.3 }, Strafe = true, Melee = true },
}

-- Job = what it does when nobody is in sight:
--   Escort    stays on the nearest human teammate's shoulder
--   Push      advances down the centre to the enemy front, then hunts their half
--   Flank     takes a side lane and hunts their half from the edge
--   Overwatch holds a long sightline on its own side of the map
local ALLIES = {
	{ Name = "KESTREL", Role = "Rifleman", Job = "Escort" },
	{ Name = "HALCYON", Role = "Marksman", Job = "Escort" },
	{ Name = "BASTION", Role = "Breacher", Job = "Flank" },
	{ Name = "WRAITH", Role = "Sniper", Job = "Overwatch" },
}
local ENEMIES = {
	{ Name = "ROOK", Role = "Rifleman", Job = "Push" },
	{ Name = "VIPER", Role = "Breacher", Job = "Flank" },
	{ Name = "SPECTER", Role = "Marksman", Job = "Push" },
	{ Name = "ASH", Role = "Suppressor", Job = "Flank" },
	{ Name = "GRIM", Role = "Sniper", Job = "Overwatch" },
}

local TEAM_TINT = {
	Blue = { Body = Color3.fromRGB(64, 92, 140), Head = Color3.fromRGB(150, 165, 185) },
	Red = { Body = Color3.fromRGB(140, 52, 48), Head = Color3.fromRGB(185, 160, 150) },
}

local AGENT = { AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 6 }

local rng = Random.new()

-- ─── state ──────────────────────────────────────────────────────────────────
type Bot = { [string]: any }
local squad = { Gen = 0, Bots = {} :: { Bot }, Diff = DIFFICULTY.normal }
local fillOn = false -- 2026-11-19: this match is being topped up with bots
local botByModel: { [Model]: Bot } = {}
local intel: { [string]: { [Model]: { Pos: Vector3, At: number } } } = { Blue = {}, Red = {} }

local function say(player: Player?, text: string)
	print("[SquadBots] " .. text)
	if player then
		(MsgRemote :: RemoteEvent):FireClient(player, text)
	end
end

local function phase(): string?
	return Match:GetAttribute("Phase")
end

local function otherTeam(team: string): string
	return if team == "Red" then "Blue" else "Red"
end

local function rand(range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- a living character, or a vehicle that isn't wrecked
local function aliveModel(m: Model?): boolean
	if not m or not m.Parent then
		return false
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	if h then
		return h.Health > 0
	end
	return m:GetAttribute("VehicleId") ~= nil and not m:GetAttribute("Destroyed")
end

-- the character (player or dummy) a hit part belongs to
local function characterOf(inst: Instance): Model?
	local cur = inst.Parent
	while cur and cur ~= Workspace do
		if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function award(team: string?)
	if (team == "Blue" or team == "Red") and phase() == "Live" then
		local key = team .. "Score"
		Match:SetAttribute(key, (Match:GetAttribute(key) or 0) + 1)
	end
end

-- everyone alive on a team: { Model, Root, Head, Player? }
local function membersOf(team: string)
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and p.Team and not p.Neutral and p.Team.Name == team and aliveModel(c) then
			local root, head = c:FindFirstChild("HumanoidRootPart"), c:FindFirstChild("Head")
			if root and head then
				table.insert(list, { Model = c, Root = root, Head = head, Player = p })
			end
		end
	end
	for _, d in CollectionService:GetTagged("VantageDummy") do
		if d:IsA("Model") and d:GetAttribute("Team") == team and d:IsDescendantOf(Workspace) and aliveModel(d) then
			local root, head = d:FindFirstChild("HumanoidRootPart"), d:FindFirstChild("Head")
			if root and head then
				table.insert(list, { Model = d, Root = root, Head = head })
			end
		end
	end
	return list
end

-- per-tick caches: who is on each team, and ray params that see through a team's own members
local cache = { At = 0, Members = {}, Params = {} }
local function refreshCache()
	local now = os.clock()
	if now - cache.At < TICK * 0.9 then
		return
	end
	cache.At = now
	for _, team in { "Blue", "Red" } do
		local members = membersOf(team)
		cache.Members[team] = members
		local exclude = {}
		for _, m in members do
			table.insert(exclude, m.Model)
		end
		local drops = Workspace:FindFirstChild("VantageDrops")
		if drops then
			table.insert(exclude, drops)
		end
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = exclude
		p.IgnoreWater = true
		cache.Params[team] = p
	end
end

-- ─── map points ─────────────────────────────────────────────────────────────
local function spawnPoints(team: string): { BasePart }
	local t = Teams:FindFirstChild(team) :: Team?
	local list = {}
	for _, s in Workspace:GetDescendants() do
		if s:IsA("SpawnLocation") and t and s.TeamColor == t.TeamColor then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		return a.Position.Z < b.Position.Z
	end)
	return list
end

-- the open ground in front of a team's base (map BotSpots), else ±330 on X
local function frontOf(team: string): Vector3
	for _, m in Workspace:GetChildren() do
		local g = m:FindFirstChild("Gameplay")
		local spots = g and g:FindFirstChild("BotSpots")
		local mk = spots and spots:FindFirstChild(team)
		if mk and mk:IsA("BasePart") then
			return mk.Position
		end
	end
	return Vector3.new(if team == "Blue" then -330 else 330, 1, 0)
end

-- 2026-11-19 compact arenas: the loaded map's playable box (from Gameplay.Boundary), cached per MapId
local boxCache = { id = nil, box = nil }
local function mapBox(): { number }?
	local id = Workspace:FindFirstChild("Map_LiveFire") and Workspace.Map_LiveFire:GetAttribute("MapId") or "?"
	if boxCache.id == id and boxCache.box then
		return boxCache.box
	end
	for _, m in Workspace:GetChildren() do
		local g = m:FindFirstChild("Gameplay")
		local bd = g and g:FindFirstChild("Boundary")
		if bd and bd:FindFirstChild("West") and bd:FindFirstChild("East") and bd:FindFirstChild("North") and bd:FindFirstChild("South") then
			local xs = { bd.West.Position.X, bd.East.Position.X }
			local zs = { bd.North.Position.Z, bd.South.Position.Z }
			local x0, x1 = math.min(xs[1], xs[2]) + 4, math.max(xs[1], xs[2]) - 4
			local z0, z1 = math.min(zs[1], zs[2]) + 4, math.max(zs[1], zs[2]) - 4
			if x0 >= x1 or z0 >= z1 then
				return nil
			end
			boxCache.id, boxCache.box = id, { x0, x1, z0, z1 }
			return boxCache.box
		end
	end
	return nil
end
local freeParams = OverlapParams.new()
freeParams.FilterType = Enum.RaycastFilterType.Include
local function standable(p: Vector3): boolean
	local mp = Workspace:FindFirstChild("Map_LiveFire")
	if not mp then
		return true
	end
	freeParams.FilterDescendantsInstances = { mp }
	for _, part in Workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 3.2, 0)), Vector3.new(3, 4.6, 3), freeParams) do
		if part.CanCollide and not string.find(part.Name, "SpawnShield") then
			return false
		end
	end
	return true
end
local function groundAt(pos: Vector3): Vector3?
	local box = mapBox()
	if box then
		pos = Vector3.new(math.clamp(pos.X, box[1], box[2]), pos.Y, math.clamp(pos.Z, box[3], box[4]))
	end
	local r = Workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -140, 0), cache.Params.Blue)
	if not r then
		return nil
	end
	local p = r.Position
	if box and (p.X < box[1] or p.X > box[2] or p.Z < box[3] or p.Z > box[4]) then
		return nil
	end
	if not standable(p) then
		-- look for open floor nearby before giving up
		for rad = 4, 16, 4 do
			for a = 0, 315, 45 do
				local q = pos + Vector3.new(math.cos(math.rad(a)) * rad, 0, math.sin(math.rad(a)) * rad)
				local r2 = Workspace:Raycast(q + Vector3.new(0, 40, 0), Vector3.new(0, -140, 0), cache.Params.Blue)
				if r2 and math.abs(r2.Position.Y - p.Y) < 6 and standable(r2.Position) and (not box or (r2.Position.X > box[1] and r2.Position.X < box[2] and r2.Position.Z > box[3] and r2.Position.Z < box[4])) then
					return r2.Position
				end
			end
		end
		return nil
	end
	return p
end

-- 2026-11-18 map vote: the tuned lane / deck logic below is Live Fire's (teams on the X axis
-- around the origin). On any other map the bots work in the frame of the two BotSpots instead.
local MatchAttrs = game:GetService("ReplicatedStorage"):WaitForChild("Vantage"):WaitForChild("Match", 30)
local function otherMap(): boolean
	local id = MatchAttrs and MatchAttrs:GetAttribute("MapId")
	return true -- 2026-11-19: Live Fire is now a compact N/S arena too; every map uses the BotSpot frame
end
-- point in a team's half: along 0 = the middle line, 1 = that team's front; across = sideways studs
local function inHalf(team: string, along: number, across: number): Vector3
	local mine = frontOf(team)
	local theirs = frontOf(if team == "Blue" then "Red" else "Blue")
	local d = Vector3.new(mine.X - theirs.X, 0, mine.Z - theirs.Z)
	if d.Magnitude < 1 then
		return mine
	end
	local mid = (mine + theirs) / 2
	local fwd = d.Unit
	local lat = Vector3.new(-fwd.Z, 0, fwd.X)
	local p = mid + fwd * (d.Magnitude / 2) * along + lat * across
	local box = mapBox()
	if box then
		p = Vector3.new(math.clamp(p.X, box[1], box[2]), p.Y, math.clamp(p.Z, box[3], box[4]))
	end
	return p
end

-- a random reachable-looking point in the enemy half (for hunting)
local function huntPoint(enemyTeam: string, laneZ: number?): Vector3
	local front = frontOf(enemyTeam)
	if otherMap() then
		for _ = 1, 8 do
			local p = inHalf(enemyTeam, rng:NextNumber(0.25, 0.95), rng:NextNumber(-150, 150))
			local g = groundAt(Vector3.new(p.X, front.Y, p.Z))
			if g and g.Y < front.Y + 12 and g.Y > front.Y - 10 then
				return g
			end
		end
		return front
	end
	local side = math.sign(front.X)
	for _ = 1, 8 do
		local x = side * rng:NextNumber(110, 330)
		local z = laneZ and (laneZ + rng:NextNumber(-40, 40)) or rng:NextNumber(-220, 220)
		local g = groundAt(Vector3.new(x, 0, z))
		if g and g.Y < 12 and g.Y > -10 then
			return g
		end
	end
	return front
end

-- ─── movement ───────────────────────────────────────────────────────────────
-- centre of a team's spawn pads (cached per team)
local spawnCentre: { [string]: Vector3 } = {}
local function spawnCentreOf(team: string): Vector3?
	if spawnCentre[team] then
		return spawnCentre[team]
	end
	local pts = spawnPoints(team)
	if #pts == 0 then
		return nil
	end
	local sum = Vector3.zero
	for _, s in pts do
		sum += s.Position
	end
	spawnCentre[team] = sum / #pts
	return spawnCentre[team]
end

-- up on the raised spawn deck (pathfinding can't do the drop off its front edge)
if MatchAttrs then
	MatchAttrs:GetAttributeChangedSignal("MapId"):Connect(function()
		table.clear(spawnCentre) -- new map, new spawn pads
	end)
end

local function onDeck(b: Bot): boolean
	if otherMap() then
		return false -- the raised spawn deck is Live Fire's
	end
	local s = spawnCentreOf(b.Team)
	return s ~= nil and b.Root.Position.Y > s.Y - 15 and flat(b.Root.Position - s).Magnitude < 85
end

-- the way off the deck: line up on the centre gate, walk through it, step off the front edge
local DECK_GATE = 38 -- studs from the pad centre toward the map centre (gate posts at |z| > 15)
local DECK_DROP = 95 -- a point on the ground past the deck edge
local function deckExit(b: Bot): Vector3?
	if not onDeck(b) then
		return nil
	end
	local s = spawnCentreOf(b.Team) :: Vector3
	local sign = if s.X < 0 then 1 else -1
	local p = b.Root.Position
	local gateX = s.X + sign * DECK_GATE
	if (p.X - gateX) * sign < 2 then
		if math.abs(p.Z - s.Z) > 7 then
			return Vector3.new(gateX - sign * 6, p.Y, s.Z) -- line up behind the gate first
		end
		return Vector3.new(gateX + sign * 8, p.Y, s.Z)
	end
	return Vector3.new(s.X + sign * DECK_DROP, 0, s.Z + math.clamp(p.Z - s.Z, -8, 8))
end

-- a goal pathfinding just refused (somewhere up a structure, a player in an aircraft...)
local function unreachable(b: Bot, goal: Vector3): boolean
	return b.NoPathGoal ~= nil
		and (b.NoPathGoal - goal).Magnitude < 25
		and os.clock() - b.NoPathAt < 6
		and not onDeck(b)
end

local function stopMoving(b: Bot)
	b.Hum:MoveTo(b.Root.Position)
	b.Moving = false
end

-- what the bot is doing, readable on the model in Properties (AIState) while testing
local function setState(b: Bot, s: string)
	if b.State ~= s then
		b.State = s
		if b.Model and b.Model.Parent then
			b.Model:SetAttribute("AIState", s)
		end
	end
end

local function goTo(b: Bot, goal: Vector3, speedMul: number?)
	local now = os.clock()
	b.Moving = true
	b.Traveling = true -- only travel counts for the stuck check (strafing on the spot is not stuck)
	b.Hum.WalkSpeed = BASE_SPEED * (b.Weapon.SpeedMultiplier or 1) * (speedMul or 1)
	local needPath = not b.PathBusy
		and (b.PathGoal == nil or (b.PathGoal - goal).Magnitude > 12 or now - b.PathAt > 3 or (b.Wps and b.WpIndex > #b.Wps))
	if needPath then
		b.PathBusy = true
		local from, gen = b.Root.Position, b.Gen
		task.spawn(function()
			local path = PathfindingService:CreatePath(AGENT)
			local ok = pcall(function()
				path:ComputeAsync(from, goal)
			end)
			if gen ~= squad.Gen then
				return
			end
			if ok and path.Status == Enum.PathStatus.Success then
				b.Wps = path:GetWaypoints()
				b.WpIndex = math.min(2, #b.Wps)
				b.NoPathGoal = nil
			else
				b.Wps = nil -- no path: deck exit, or walk straight at it until think() drops the goal
				b.NoPathGoal, b.NoPathAt = goal, os.clock()
			end
			b.PathGoal, b.PathAt, b.PathBusy = goal, os.clock(), false
		end)
	end
	local target = deckExit(b) or goal
	local wps = b.Wps
	if wps and not onDeck(b) and b.PathGoal and (b.PathGoal - goal).Magnitude <= 12 then
		while b.WpIndex <= #wps do
			local wp = wps[b.WpIndex]
			if flat(wp.Position - b.Root.Position).Magnitude < 3.5 then
				b.WpIndex += 1
			else
				break
			end
		end
		local wp = wps[b.WpIndex]
		if wp then
			target = wp.Position
			if wp.Action == Enum.PathWaypointAction.Jump then
				b.Hum.Jump = true
			end
		end
	end
	b.Hum:MoveTo(target)
end

-- unstick: jump, then re-path, then a short random sidestep
local function checkStuck(b: Bot)
	local now = os.clock()
	if now - b.StuckCheckAt < 1 then
		return
	end
	local moved = flat(b.Root.Position - b.StuckPos).Magnitude
	b.StuckCheckAt, b.StuckPos = now, b.Root.Position
	if b.Traveling and moved < 1.5 then
		b.Stuck += 1
		b.Hum.Jump = true
		b.PathAt = 0
		if b.Stuck >= 3 then
			local a = rng:NextNumber(0, math.pi * 2)
			b.SidestepTo = b.Root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 10
			b.SidestepUntil = now + 1
			b.Stuck = 0
		end
	else
		b.Stuck = 0
	end
end

-- is a sidestep point open (no wall in the way, ground under it)?
local function openSpot(b: Bot, to: Vector3): boolean
	local from = b.Root.Position
	local params = cache.Params[b.Team]
	if Workspace:Raycast(from, to - from, params) then
		return false
	end
	local g = Workspace:Raycast(to, Vector3.new(0, -9, 0), params)
	return g ~= nil
end

-- ─── shooting ───────────────────────────────────────────────────────────────
local LIMB = { "Arm", "Hand", "Leg", "Foot" }
local function isLimb(part: Instance): boolean
	for _, s in LIMB do
		if string.find(part.Name, s) then
			return true
		end
	end
	return false
end

local function applyHit(b: Bot, victim: Model, dmg: number, isHead: boolean, dir: Vector3, pos: Vector3, weapon)
	local hum = victim:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not DamageService.CombatEnabled() then
		return
	end
	if DamageService.TeamOf(victim) == b.Team then
		return
	end
	local vb = botByModel[victim]
	if vb then
		vb.ThreatModel, vb.ThreatAt = b.Vehicle or b.Model, os.clock()
	end
	intel[otherTeam(b.Team)][b.Vehicle or b.Model] = { Pos = b.Root.Position, At = os.clock() }
	if victim:FindFirstChildOfClass("ForceField") then
		return
	end
	victim:SetAttribute("LastHitHead", isHead)
	victim:SetAttribute("LastHitDir", dir)
	victim:SetAttribute("LastHitWeapon", weapon.Id)
	victim:SetAttribute("LastHitKind", weapon.Kind)
	victim:SetAttribute("LastHitExplosive", weapon.Explosive == true)
	local before = hum.Health
	local toHealth, absorbed, broke = ShieldService.Absorb(victim, dmg)
	ShieldService.Report(victim, pos, dir, absorbed, broke)
	local lethal = toHealth >= before
	if lethal then
		victim:SetAttribute("VantageKiller", nil)
		EliminationService.SetDebugKiller(victim, b.Model)
	end
	if toHealth > 0 then
		hum:TakeDamage(toHealth)
	end
	local vp = Players:GetPlayerFromCharacter(victim)
	if vp then
		EventRemote:FireClient(vp, "Damaged", b.Head.Position, dmg)
	end
	if lethal and before > 0 and hum.Health <= 0 then
		if vb then
			vb.ScoredBy = b.Team -- so the bot's own death handler doesn't count it again
		end
		award(b.Team)
	end
end

local function currentSpread(b: Bot): number
	local d = squad.Diff
	local track = math.max(0, 1 - (os.clock() - b.TargetSince) / 1.4) * 4 -- loose first shots, then dialled in
	local moving = if b.Root.AssemblyLinearVelocity.Magnitude > 3 then 1.35 else 1
	return (b.Role.Spread * moving + track) * d.Spread
end

-- one trigger pull (one round, or one shell of pellets)
local function pull(b: Bot, t)
	local w = b.Weapon
	local head = b.Head
	if not head.Parent or not t.Head.Parent then
		return
	end
	local headChance = math.min(0.85, b.Role.Head * squad.Diff.Head)
	local aimPart = if rng:NextNumber() < headChance then t.Head else (t.Model:FindFirstChild("UpperTorso") or t.Root)
	local origin = head.Position
	local dir = WeaponMath.ApplySpread((aimPart.Position - origin).Unit, currentSpread(b), rng)
	hook:Invoke("DummyShoot", b.Model, origin + dir * 100) -- tracer, muzzle, sound for every client
	local pellets = if w.Pellet then w.Pellet.Count else 1
	local params = cache.Params[b.Team]
	local hits: { [Model]: { Dmg: number, Head: boolean, Pos: Vector3, Dist: number } } = {}
	for _ = 1, pellets do
		local d = if pellets > 1 then WeaponMath.ApplySpread(dir, w.Pellet.Spread, rng) else dir
		local res = Workspace:Raycast(origin, d * (w.MaxRange or 500), params)
		local victim = res and characterOf(res.Instance)
		-- small arms on an enemy vehicle: same multipliers a player's rounds get
		local vmodel = res and not victim and VehicleService.VehicleOf(res.Instance)
		if vmodel and vmodel:GetAttribute("Team") ~= b.Team then
			local mult = VehicleConfig.SmallArms[w.Id]
			if mult == nil then
				mult = VehicleConfig.SmallArms.Default
			end
			VehicleService.DamageVehicle(vmodel, WeaponMath.Damage(w, false, false, res.Distance) * (mult or 0), nil, w.Id, res.Position)
		end
		if res and victim and victim ~= b.Model then
			local isHead = res.Instance.Name == "Head" or (res.Instance.Parent ~= nil and res.Instance.Parent:IsA("Accessory"))
			local dmg = WeaponMath.Damage(w, isHead, isLimb(res.Instance), res.Distance)
			local e = hits[victim]
			if e then
				e.Dmg += dmg
				e.Head = e.Head or isHead
			else
				hits[victim] = { Dmg = dmg, Head = isHead, Pos = res.Position, Dist = res.Distance }
			end
		end
	end
	for victim, e in hits do
		if w.Shot == "Projectile" and w.Projectile then
			task.delay(e.Dist / w.Projectile.Speed, applyHit, b, victim, e.Dmg, e.Head, dir, e.Pos, w)
		else
			applyHit(b, victim, e.Dmg, e.Head, dir, e.Pos, w)
		end
	end
	if w.MagazineSize and w.MagazineSize > 0 then
		b.Mag -= 1
	end
	if w.Heat then
		b.Heat += w.Heat.PerShot
		b.HeatAt = os.clock()
		if b.Heat >= 1 then
			b.Heat = 0
			b.ReloadUntil = os.clock() + w.Heat.OverheatLock + w.Heat.VentTime
			hook:Invoke("DummyAction", b.Model, "Reload")
		end
	end
end

local function reload(b: Bot)
	local w = b.Weapon
	if not w.MagazineSize or w.MagazineSize <= 0 or b.Mag >= w.MagazineSize then
		return
	end
	local time = w.ReloadTime or 2
	if w.ReloadMode == "Shell" and w.Shell then
		time = w.Shell.Start + w.Shell.Each * (w.MagazineSize - b.Mag) + w.Shell.Finish
	end
	b.ReloadUntil = os.clock() + time
	b.Mag = w.MagazineSize
	hook:Invoke("DummyAction", b.Model, "Reload")
end

local function melee(b: Bot, t)
	local knife = Config.Weapons.Knife
	if not knife or not knife.Primary then
		return
	end
	hook:Invoke("DummyMelee", b.Model)
	local dir = (t.Root.Position - b.Root.Position).Unit
	applyHit(b, t.Model, knife.Primary.Damage, false, dir, t.Root.Position, knife)
end

-- the trigger finger: runs on its own thread so fire rates are exact
local function gunner(b: Bot, gen: number)
	local w = b.Weapon
	local interval = 60 / (w.RPM or 600)
	local function canFire(t)
		return b.Alive and gen == squad.Gen and b.FireReady and b.Target == t and aliveModel(t.Model) and os.clock() >= b.ReloadUntil
			and ((b.Root and b.Root.Parent and b.Root.Parent:GetAttribute("Status_FrozenUntil")) or 0) <= workspace:GetServerTimeNow() -- Helheim freeze
	end
	while b.Alive and gen == squad.Gen do
		local t = b.Target
		local now = os.clock()
		if w.Heat and now - b.HeatAt > w.Heat.CoolDelay then
			b.Heat = math.max(0, b.Heat - w.Heat.CoolRate * 0.05)
		end
		if now < b.ReloadUntil then
			task.wait(0.05)
		elseif t and canFire(t) and DamageService.CombatEnabled() then
			local dist = (t.Root.Position - b.Root.Position).Magnitude
			if b.Role.Melee and dist < 5.5 then
				melee(b, t)
				task.wait(0.75)
			elseif w.MagazineSize and w.MagazineSize > 0 and b.Mag <= 0 then
				reload(b)
			elseif w.Trigger == "Auto" then
				local n = rng:NextInteger(b.Role.Burst[1], b.Role.Burst[2])
				for _ = 1, n do
					if not canFire(t) or (w.MagazineSize > 0 and b.Mag <= 0) then
						break
					end
					pull(b, t)
					task.wait(interval)
				end
				task.wait(rand(b.Role.Pause))
			elseif w.Trigger == "Burst" and w.Burst then
				for _ = 1, w.Burst.Count do
					if not canFire(t) or b.Mag <= 0 then
						break
					end
					pull(b, t)
					task.wait(interval)
				end
				task.wait(w.Burst.Cooldown + rand(b.Role.Pause))
			else
				pull(b, t)
				task.wait(interval + (if w.Rechamber then w.Rechamber.Time else 0) + rand(b.Role.Pause))
			end
		else
			-- quiet moment with a part-empty magazine: top up, like a player would
			if not t and w.MagazineSize and w.MagazineSize > 0 and b.Mag < w.MagazineSize * 0.45 then
				reload(b)
			end
			task.wait(0.05)
		end
	end
end

-- ─── perception ─────────────────────────────────────────────────────────────
local function canSee(b: Bot, h): boolean
	local origin = b.Head.Position
	local res = Workspace:Raycast(origin, h.Head.Position - origin, b.SeeParams or cache.Params[b.Team])
	return res ~= nil and res.Instance:IsDescendantOf(h.Model)
end

local function perceive(b: Bot)
	local now = os.clock()
	local look = flat(b.Root.CFrame.LookVector).Unit
	local best, bestScore = nil, math.huge
	for _, h in cache.Members[otherTeam(b.Team)] or {} do
		if h.Model:GetAttribute("VehicleHidden") then
			continue -- buttoned up inside a hull: shoot the vehicle instead
		end
		local to = h.Head.Position - b.Head.Position
		local d = to.Magnitude
		if d <= VISION then
			local threat = b.ThreatModel == h.Model and now - b.ThreatAt < 3
			local current = b.Target ~= nil and b.Target.Model == h.Model
			local ahead = d < 1e-3 or flat(to).Unit:Dot(look) >= FOV_COS
			if (ahead or d <= HEAR or threat or current) and canSee(b, h) then
				intel[b.Team][h.Model] = { Pos = h.Root.Position, At = now }
				local score = d - (if current then 40 else 0) - (if threat then 70 else 0)
				if score < bestScore then
					best, bestScore = h, score
				end
			end
		end
	end
	-- crewed enemy vehicles (tanks prefer them; infantry prefer people)
	for vm, vst in VehicleService.Vehicles do
		if vm.Parent and vm ~= b.Vehicle and not vm:GetAttribute("Destroyed") and vm:GetAttribute("Team") ~= b.Team
			and (vm:GetAttribute("Crew") or 0) > 0 then
			local h = { Model = vm, Root = vst.Root, Head = vst.Root, Vehicle = true }
			local to = vst.Root.Position - b.Head.Position
			local d = to.Magnitude
			if d <= VISION then
				local current = b.Target ~= nil and b.Target.Model == vm
				local threat = b.ThreatModel == vm and now - b.ThreatAt < 3
				local ahead = flat(to).Magnitude < 1e-3 or flat(to).Unit:Dot(look) >= FOV_COS
				if (ahead or current or threat or d <= HEAR * 2) and canSee(b, h) then
					intel[b.Team][vm] = { Pos = vst.Root.Position, At = now }
					local score = d + (if b.Vehicle then -40 else 40) - (if current then 40 else 0) - (if threat then 70 else 0)
					if score < bestScore then
						best, bestScore = h, score
					end
				end
			end
		end
	end
	if best then
		if not b.Target or b.Target.Model ~= best.Model then
			b.TargetSince = now
		end
		b.Target = best
		b.LastKnown = { Model = best.Model, Pos = best.Root.Position, At = now }
	else
		b.Target = nil
	end
end

-- freshest teammate callout within reach
local function callout(b: Bot): Vector3?
	local now = os.clock()
	local best, bestD = nil, CALLOUT_RANGE
	for model, e in intel[b.Team] do
		if now - e.At > MEMORY or not aliveModel(model) then
			intel[b.Team][model] = nil
		else
			local d = (e.Pos - b.Root.Position).Magnitude
			if d < bestD then
				best, bestD = e.Pos, d
			end
		end
	end
	return best
end

-- ─── brain ──────────────────────────────────────────────────────────────────
-- ─── grapple ───
-- Server-driven: the bot's body is server-owned, so the pull is a LinearVelocity here. Every client
-- draws the hook and cable from the same Ability remote messages a player's grapple uses.
local function buildLauncher(character: Model)
	if character:FindFirstChild("VantageGrappleLauncher") then
		return
	end
	-- bots wear a random Shield Pack + Grappling Hook (EquipmentBuild), so a squad shows the range of looks
	local ok, err = pcall(function()
		local eq = game:GetService("ReplicatedStorage").Vantage.Equipment
		local Cat = require(eq.EquipmentCatalog)
		local packs, hooks = Cat.List("Pack"), Cat.List("Hook")
		require(eq.EquipmentBuild).Dress(character, packs[math.random(#packs)].Id, hooks[math.random(#hooks)].Id)
	end)
	if not ok then
		warn("[VANTAGE] SquadBots: equipment failed:", err)
	end
end

-- first solid thing along a ray (characters, vehicles and non-colliding parts are passed through)
local function solidHit(origin: Vector3, to: Vector3): RaycastResult?
	local ignore: { Instance } = {}
	for _, team in { "Blue", "Red" } do
		for _, m in cache.Members[team] or {} do
			table.insert(ignore, m.Model)
		end
	end
	for vm in VehicleService.Vehicles do
		table.insert(ignore, vm)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local dir = to - origin
	for _ = 1, 6 do
		local hit = Workspace:Raycast(origin, dir, params)
		if not hit then
			return nil
		end
		if hit.Instance.CanCollide then
			return hit
		end
		table.insert(ignore, hit.Instance)
		params.FilterDescendantsInstances = ignore
	end
	return nil
end

local function startGrapple(b: Bot, point: Vector3)
	local now = os.clock()
	local dist = (point - b.Head.Position).Magnitude
	b.Grapple = { Point = point, Started = now, Flight = dist / (G.ProjectileSpeed or 340), Speed = 0, LastPos = b.Root.Position, SlowFor = 0 }
	b.GrappleReady = now + (G.Cooldown or 3.5) + rng:NextNumber(0.5, 2.5)
	b.Face = point
	stopMoving(b)
	Workspace:SetAttribute("SquadGrapples", (Workspace:GetAttribute("SquadGrapples") or 0) + 1) -- test counter
	if AbilityRemote then
		AbilityRemote:FireAllClients("FX", b.Model, "Grapple", point)
	end
end

local function endGrapple(b: Bot, hop: boolean)
	local g = b.Grapple
	if not g then
		return
	end
	b.Grapple = nil
	if g.LV then
		g.LV:Destroy()
	end
	if g.Att then
		g.Att:Destroy()
	end
	local root = b.Root
	if root and root.Parent and b.Hum.Health > 0 then
		-- keep the momentum, capped like a player's release
		local v = root.AssemblyLinearVelocity
		local h = Vector3.new(v.X, 0, v.Z)
		if h.Magnitude > 44 then
			h = h.Unit * 44
		end
		local up = math.clamp(v.Y, -80, 34)
		if hop then
			up = math.max(up, (G.ArriveHop or 20) * 0.8)
		end
		root.AssemblyLinearVelocity = h + Vector3.new(0, up, 0)
	end
	if AbilityRemote then
		AbilityRemote:FireAllClients("GrappleEnd", b.Model)
	end
	b.PathAt = 0
	b.Face = nil
end

-- every frame while hooked
local function stepGrapple(b: Bot, dt: number)
	local g = b.Grapple
	local now = os.clock()
	local root = b.Root
	if b.Hum.Health <= 0 then
		endGrapple(b, false)
		return
	end
	if now - g.Started < g.Flight then
		return -- the hook is still flying
	end
	if not g.LV then
		local att = Instance.new("Attachment")
		att.Name = "SquadGrapple"
		att.Parent = root
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.MaxForce = 1e6
		lv.VectorVelocity = root.AssemblyLinearVelocity
		lv.Parent = root
		g.Att, g.LV, g.PullStart = att, lv, now
		b.Hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	local to = g.Point - root.Position
	local d = to.Magnitude
	if d <= (G.ArriveDistance or 6) + 1 then
		endGrapple(b, true)
		return
	end
	if now - g.PullStart > 3.2 then
		endGrapple(b, false)
		return
	end
	g.Speed = math.min(BOT_GRAPPLE_SPEED, g.Speed + (G.PullAccel or 215) * dt)
	g.LV.VectorVelocity = to.Unit * math.min(g.Speed, d * 6)
	-- blocked against geometry: let go
	local moved = (root.Position - g.LastPos).Magnitude
	g.LastPos = root.Position
	if now - g.PullStart > 0.3 and moved / math.max(dt, 1e-3) < (G.StuckSpeed or 5) then
		g.SlowFor += dt
	else
		g.SlowFor = 0
	end
	if g.SlowFor > (G.StuckTime or 0.45) then
		endGrapple(b, false)
	end
end

-- aim a hook at `want`; take it if it bites within `slack` studs of it
local function tryGrapple(b: Bot, want: Vector3, slack: number): boolean
	local now = os.clock()
	if b.Grapple or b.Vehicle or now < b.GrappleReady then
		return false
	end
	local eye = b.Head.Position
	local d = (want - eye).Magnitude
	if d < 15 or d > BOT_GRAPPLE_RANGE then
		return false
	end
	local hit = solidHit(eye, want + (want - eye).Unit * 3)
	if not hit or (hit.Position - want).Magnitude > slack or (hit.Position - eye).Magnitude < 12 then
		b.GrappleReady = now + 1 -- don't re-test every tick
		return false
	end
	startGrapple(b, hit.Position)
	return true
end

-- shield gone: hook something behind and get out
local function grappleEscape(b: Bot, t): boolean
	if b.Grapple or b.Vehicle or os.clock() < b.GrappleReady then
		return false
	end
	local from = (t and t.Root.Position) or (b.LastKnown and b.LastKnown.Pos)
	if not from then
		return false
	end
	local away = flat(b.Root.Position - from)
	if away.Magnitude < 1e-3 then
		return false
	end
	away = away.Unit
	local eye = b.Head.Position
	for _, ang in { 0, 30, -30, 60, -60 } do
		local dir = (CFrame.Angles(0, math.rad(ang), 0):VectorToWorldSpace(away) + Vector3.new(0, 0.3, 0)).Unit
		local hit = solidHit(eye, eye + dir * BOT_GRAPPLE_RANGE)
		if hit and (hit.Position - eye).Magnitude > 25 then
			startGrapple(b, hit.Position)
			return true
		end
	end
	b.GrappleReady = os.clock() + 1
	return false
end

-- ─── vehicles ───
local claimed: { [Model]: Bot } = {}

local function vehicleValid(model: Model?)
	local st = model and VehicleService.Vehicles[model]
	return st ~= nil and (model :: Model).Parent ~= nil and not (model :: Model):GetAttribute("Destroyed"), st
end

local function teamVehicleCount(team: string): number
	local n = 0
	for _, o in squad.Bots do
		if o.Team == team and o.Alive and (o.Vehicle or o.Mount or o.WantVehicle) then
			n += 1
		end
	end
	return n
end

-- nearest free ground vehicle of our side (or one a teammate is waiting in as gunner)
local function pickVehicle(b: Bot): Model?
	local best, bestD = nil, VEHICLE_SEARCH
	for model, st in VehicleService.Vehicles do
		local seat = st.SeatByRole.Driver
		if model.Parent and not model:GetAttribute("Destroyed") and not st.Bot and not claimed[model]
			and st.Cfg.Drive.Kind ~= "Flight" and seat and not seat.Occupant
			and (model:GetAttribute("Team") == nil or model:GetAttribute("Team") == b.Team) then
			local d = flat(st.Root.Position - b.Root.Position).Magnitude
			if d < bestD then
				best, bestD = model, d
			end
		end
	end
	return best
end

-- walk to the claimed vehicle and climb in; true while this is what the bot is doing
local function mountStep(b: Bot): boolean
	local model = b.Mount :: Model
	local ok, st = vehicleValid(model)
	if not ok or os.clock() > b.MountUntil or st.Bot or (st.SeatByRole.Driver and st.SeatByRole.Driver.Occupant) then
		claimed[model] = nil
		b.Mount = nil
		return false
	end
	local reach = if st.Prompt then st.Prompt.MaxActivationDistance else 12
	if (st.Root.Position - b.Root.Position).Magnitude <= reach then
		claimed[model] = nil
		b.Mount = nil
		if VehicleService.BotEnter(b.Model, model, b.Team) then
			Workspace:SetAttribute("SquadVehicleEntries", (Workspace:GetAttribute("SquadVehicleEntries") or 0) + 1) -- test counter
			claimed[model] = b
			b.Vehicle = model
			b.Face, b.Moving = nil, false
			b.VWps, b.VGoal, b.VPathAt, b.VPathBusy = nil, nil, 0, false
			b.VStuck, b.VStuckCount, b.VReverseUntil, b.VHunt, b.VNoPath = 0, 0, 0, nil, false
		b.VPitTime, b.VHoldTime = 0, 0
			return true
		end
		b.NoVehicleUntil = os.clock() + 20
		return false
	end
	local side = st.Root.Position + st.Root.CFrame.RightVector * (st.Root.Size.X / 2 + 3)
	goTo(b, side, 1.1)
	return true
end

-- throttle / steer toward a goal along a vehicle-sized path
local function driveTo(b: Bot, st, goal: Vector3): (number, number, boolean)
	local now = os.clock()
	local root = st.Root
	if not b.VPathBusy and (b.VGoal == nil or (b.VGoal - goal).Magnitude > 30 or now - b.VPathAt > 4 or (b.VWps and b.VWpIndex > #b.VWps)) then
		b.VPathBusy = true
		-- an agent as wide as the hull, so the route doesn't scrape buildings; routes start just
		-- off the nose (from inside our own hull pathfinding finds nothing) and avoid the pits
		local radius = math.clamp(math.min(root.Size.X, root.Size.Z) / 2 + 1.5, 4, 9)
		local agent = { AgentRadius = radius, AgentHeight = 8, AgentCanJump = false, WaypointSpacing = 10, Costs = { VehiclePit = math.huge } }
		local nose = flat(root.CFrame.LookVector)
		nose = if nose.Magnitude > 1e-3 then nose.Unit else Vector3.xAxis
		local from, gen = root.Position + nose * (math.max(root.Size.X, root.Size.Z) / 2 + radius + 1), b.Gen
		task.spawn(function()
			local path = PathfindingService:CreatePath(agent)
			local ok = pcall(function()
				path:ComputeAsync(from, goal)
			end)
			if gen ~= squad.Gen then
				return
			end
			local wps = if ok and path.Status == Enum.PathStatus.Success then path:GetWaypoints() else nil
			-- never route down into a pit (unless we're already in one and climbing out)
			if wps and from.Y > PIT_Y then
				for _, wp in wps do
					if wp.Position.Y < PIT_Y then
						wps = nil
						break
					end
				end
			end
			if wps then
				b.VWps = wps
				b.VWpIndex = math.min(2, #wps)
			else
				b.VWps = nil
			end
			b.VNoPath = wps == nil
			b.VGoal, b.VPathAt, b.VPathBusy = goal, os.clock(), false
		end)
	end
	local target = goal
	local wps = b.VWps
	local sameGoal = b.VGoal ~= nil and (b.VGoal - goal).Magnitude <= 30
	if sameGoal and b.VNoPath then
		-- no drivable route there: hold (the turret still works) and pick somewhere else to go
		if b.VHunt and (b.VHunt - goal).Magnitude < 1 then
			b.VHunt = nil
		end
		b.VStuck = 0
		return 0, 0, true
	end
	if wps then -- (a moving target: keep to the old route until the new one is ready)
		while b.VWpIndex <= #wps and flat(wps[b.VWpIndex].Position - root.Position).Magnitude < 10 do
			b.VWpIndex += 1
		end
		local wp = wps[b.VWpIndex]
		if wp then
			target = wp.Position
		end
	elseif not wps then
		return 0, 0, true -- route still being worked out
	end
	local lp = root.CFrame:VectorToObjectSpace(flat(target - root.Position))
	local ang = math.atan2(lp.X, -lp.Z) -- + : the point is to our right
	local steer = math.clamp(ang / math.rad(35), -1, 1)
	local thr, brake = 1, false
	if math.abs(ang) > math.rad(115) then
		thr, steer = -0.7, -steer -- behind us: back round
	else
		thr = math.clamp(1 - math.abs(ang) / math.rad(150), 0.35, 1)
	end
	if flat(goal - root.Position).Magnitude < 14 then
		thr, brake = 0, true
	end
	-- stuck on something: reverse out with the wheel turned, then re-path
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if thr ~= 0 and speed < 2.5 then
		b.VStuck += TICK
	else
		b.VStuck = math.max(0, b.VStuck - TICK * 2)
	end
	if b.VStuck > 1.8 then
		b.VStuck = 0
		b.VReverseUntil = now + 1.3
		b.VReverseSteer = if ang >= 0 then -1 else 1 -- back out swinging the nose toward the route
		b.VPathAt = 0
		b.VStuckCount += 1
	elseif speed > 8 then
		b.VStuckCount = math.max(0, b.VStuckCount - TICK * 0.2)
	end
	if now < b.VReverseUntil then
		thr, steer, brake = -1, b.VReverseSteer or -b.StrafeDir, false
	end
	return thr, steer, brake
end

-- the brain while driving; false when the bot is no longer in a vehicle
local function driveThink(b: Bot): boolean
	local model = b.Vehicle :: Model
	local ok, st = vehicleValid(model)
	if not ok or not st.Bot or st.Bot.Model ~= b.Model then
		claimed[model] = nil
		b.Vehicle, b.SeeParams = nil, nil
		return false
	end
	local now = os.clock()
	b.Face = nil
	-- sight lines from inside the hull see past our own vehicle and team
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { model }
	for _, m in cache.Members[b.Team] or {} do
		table.insert(ex, m.Model)
	end
	p.FilterDescendantsInstances = ex
	b.SeeParams = p
	perceive(b)
	local t = b.Target
	local root = st.Root
	local W = st.Cfg.Weapon
	local aim, trigger, goal = nil, false, nil
	if t then
		local tp = t.Root.Position + (if t.Vehicle then Vector3.new(0, 2, 0) else Vector3.new(0, 0.6, 0))
		aim = tp
		local d = (tp - root.Position).Magnitude
		local yawErr = math.abs(((st.Yaw - st.WantYaw + math.pi) % (2 * math.pi)) - math.pi)
		local aligned = yawErr < math.rad(5) and math.abs(st.Pitch - st.WantPitch) < math.rad(5)
		trigger = aligned and now - b.TargetSince >= b.Role.Reaction * squad.Diff.Reaction + 0.25 and d <= (W.MaxRange or 500) * 0.85
		local standoff = VEHICLE_STANDOFF[st.Kind] or 60
		if d > standoff then
			goal = t.Root.Position
		else
			-- in range: circle it rather than parking
			if now > b.StrafeFlipAt then
				b.StrafeDir = -b.StrafeDir
				b.StrafeFlipAt = now + rng:NextNumber(2.5, 4.5)
			end
			local dir = flat(tp - root.Position).Unit
			goal = root.Position + Vector3.new(-dir.Z, 0, dir.X) * 30 * b.StrafeDir - dir * (if d < standoff * 0.5 then 20 else 0)
		end
	else
		local lk = b.LastKnown
		if lk and now - lk.At < MEMORY * 2 and aliveModel(lk.Model) then
			goal, aim = lk.Pos, lk.Pos
		end
		goal = goal or callout(b)
		if not goal then
			if not b.VHunt or flat(b.VHunt - root.Position).Magnitude < 25 or now > b.VHuntUntil then
				b.VHunt = huntPoint(otherTeam(b.Team), nil)
				b.VHuntUntil = now + 35
			end
			goal = b.VHunt
		end
	end
	local thr, steer, brake = driveTo(b, st, goal :: Vector3)
	VehicleService.BotControl(model, thr, steer, brake, aim, trigger)
	-- bail out of a wreck-to-be, a vehicle that won't come unstuck, one trapped in a pit, or one
	-- with nowhere it can drive (the bot can walk or grapple out where the hull can't)
	b.VPitTime = if root.Position.Y < PIT_Y then (b.VPitTime or 0) + TICK else 0
	b.VHoldTime = if b.VNoPath and not t then (b.VHoldTime or 0) + TICK else 0
	local hp, maxHp = model:GetAttribute("Health"), model:GetAttribute("MaxHealth")
	if (hp and maxHp and hp < maxHp * 0.15 and rng:NextNumber() < 0.05) or b.VStuckCount > 6 or b.VPitTime > 3 or b.VHoldTime > 8 then
		VehicleService.BotRelease(model)
		claimed[model] = nil
		b.Vehicle, b.SeeParams = nil, nil
		b.NoVehicleUntil = now + 40
		return false
	end
	return true
end

local function nearestHuman(b: Bot)
	local best, bestD = nil, math.huge
	for _, m in cache.Members[b.Team] or {} do
		if m.Player then
			local d = (m.Root.Position - b.Root.Position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

local function jobMove(b: Bot)
	local now = os.clock()
	local enemy = otherTeam(b.Team)
	if b.Job == "Escort" then
		local lead = nearestHuman(b)
		if lead then
			-- a slot on the leader's shoulder: left / right, a little behind
			local side = if b.Slot % 2 == 0 then 1 else -1
			local lcf = lead.Root.CFrame
			local spot = lcf.Position + lcf.RightVector * (7 * side) - lcf.LookVector * 8
			if unreachable(b, spot) then
				lead = nil -- leader is somewhere we can't walk (aircraft, rooftop): go fight instead
			elseif flat(spot - b.Root.Position).Magnitude > 7 then
				goTo(b, spot, 1.05)
			else
				stopMoving(b)
				b.Face = b.Root.Position + lcf.LookVector * 50
			end
			if lead then
				return
			end
		end
	end
	if b.Job == "Overwatch" then
		if not b.Post or now > b.PostUntil then
			local own = frontOf(b.Team)
			if otherMap() then
				local p = inHalf(b.Team, rng:NextNumber(0.35, 0.7), rng:NextNumber(-120, 120))
				b.Post = groundAt(Vector3.new(p.X, own.Y, p.Z)) or own
			else
				local x = own.X - math.sign(own.X) * rng:NextNumber(60, 140)
				b.Post = groundAt(Vector3.new(x, 0, rng:NextNumber(-150, 150))) or own
			end
			b.PostUntil = now + rng:NextNumber(18, 30)
		end
		if unreachable(b, b.Post) then
			b.Post = nil
		elseif flat(b.Post - b.Root.Position).Magnitude > 5 then
			goTo(b, b.Post)
		else
			stopMoving(b)
			-- sweep the sightline across the middle of the map
			local sweep = math.sin(now * 0.35 + b.Slot) * 160
			b.Face = Vector3.new(0, b.Root.Position.Y, sweep)
		end
		return
	end
	-- Push / Flank (and an Escort with no human to follow): advance, then hunt the enemy half
	if not b.Hunt or flat(b.Hunt - b.Root.Position).Magnitude < 12 or now > b.HuntUntil or unreachable(b, b.Hunt) then
		local lane = nil
		if b.Job == "Flank" then
			lane = (if b.Slot % 2 == 0 then 1 else -1) * 200
		elseif not b.Hunted then
			lane = 0
		end
		b.Hunt = if b.Hunted then huntPoint(enemy, lane) else (huntPoint(enemy, lane or 0))
		b.Hunted = true
		b.HuntUntil = now + 25
	end
	goTo(b, b.Hunt, 1.1)
end

local function think(b: Bot)
	local now = os.clock()
	if not b.Alive or not b.Root.Parent then
		return
	end
	b.Traveling = false
	-- before Live: stand ready in the spawn
	if not DamageService.CombatEnabled() then
		setState(b, "Hold (pre-match)")
		b.Target, b.FireReady, b.Face = nil, false, nil
		if b.Vehicle then
			VehicleService.BotRelease(b.Vehicle)
			claimed[b.Vehicle] = nil
			b.Vehicle, b.SeeParams = nil, nil
		end
		if b.Moving then
			stopMoving(b)
		end
		return
	end

	-- driving: the vehicle brain takes over
	if b.Vehicle and driveThink(b) then
		setState(b, if b.Target then "Drive: engage" else "Drive: hunt")
		return
	end
	b.SeeParams = nil
	-- on the cable: the pull does the moving
	if b.Grapple then
		setState(b, "Grapple")
		b.FireReady = false
		return
	end

	perceive(b)
	local t = b.Target
	-- quiet moment: go and get a vehicle if this bot wants one
	if not t and not b.Vehicle then
		if b.WantVehicle and not b.Mount then
			b.WantVehicle = false
			local m = pickVehicle(b)
			if m then
				claimed[m] = b
				b.Mount, b.MountUntil = m, now + 35
			end
		end
		if b.Mount and mountStep(b) then
			setState(b, "Mount vehicle")
			return
		end
	end
	local shield = b.Model:GetAttribute("Shield") or 0
	local maxShield = b.Model:GetAttribute("MaxShield") or 100

	-- shield popped and hurt: break off and recharge (Breachers usually commit instead)
	if shield <= 0 and b.Hum.Health < 60 and now > b.RetreatCooldown and (b.RoleName ~= "Breacher" or rng:NextNumber() < 0.3) then
		b.RetreatUntil = now + rng:NextNumber(2.5, 4)
		b.RetreatCooldown = now + 9
		if rng:NextNumber() < 0.45 and grappleEscape(b, t) then
			return
		end
	end
	if now < b.RetreatUntil and shield < maxShield * 0.6 then
		b.FireReady = false
		local from = (t and t.Root.Position) or (b.LastKnown and b.LastKnown.Pos) or Vector3.zero
		local away = flat(b.Root.Position - from)
		away = if away.Magnitude > 1e-3 then away.Unit else flat(frontOf(b.Team) - b.Root.Position).Unit
		setState(b, "Retreat")
		goTo(b, b.Root.Position + away * 30, 1.15)
		b.Face = nil
		return
	end

	if t then
		local to = t.Root.Position - b.Root.Position
		local d = to.Magnitude
		local reaction = b.Role.Reaction * squad.Diff.Reaction
		local maxShoot = math.min((b.Weapon.MaxRange or 500) * 0.95, b.Role.Range[2] * 1.6)
		b.FireReady = now - b.TargetSince >= reaction and d <= maxShoot
		b.Face = t.Root.Position
		local pitch = math.deg(math.asin(math.clamp((t.Head.Position - b.Head.Position).Unit.Y, -1, 1)))
		hook:Invoke("DummyAim", b.Model, pitch, b.Role.Ads == true and b.FireReady)
		-- grapple: up to a target on high ground we can't walk to, or (aggressive roles) across a long gap
		local rise = t.Root.Position.Y - b.Root.Position.Y
		if rise > 10 and unreachable(b, t.Root.Position) and tryGrapple(b, t.Root.Position - Vector3.new(0, 2.5, 0), 18) then
			return
		end
		if GRAPPLE_RUSH[b.RoleName] and d > math.max(b.Role.Range[2], 35) and d < BOT_GRAPPLE_RANGE and rng:NextNumber() < 0.03
			and tryGrapple(b, t.Root.Position - Vector3.new(0, 2.5, 0), 22) then
			return
		end
		local dir = flat(to).Unit
		local right = Vector3.new(-dir.Z, 0, dir.X)
		if d > b.Role.Range[2] and not unreachable(b, t.Root.Position) then
			setState(b, "Fight: close in")
			goTo(b, t.Root.Position, 0.9) -- close the gap, shooting if in reach
		elseif d < b.Role.Range[1] then
			setState(b, "Fight: back off")
			local back = b.Root.Position - dir * 10 + right * b.StrafeDir * 4
			if openSpot(b, back) then
				b.Moving = true
				b.Hum.WalkSpeed = BASE_SPEED * 0.8
				b.Hum:MoveTo(back)
			else
				stopMoving(b)
			end
		elseif b.Role.Strafe then
			setState(b, "Fight: strafe")
			if now > b.StrafeFlipAt then
				b.StrafeDir = -b.StrafeDir
				b.StrafeFlipAt = now + rng:NextNumber(0.6, 1.5)
				if rng:NextNumber() < 0.12 then
					b.Hum.Jump = true
				end
			end
			local spot = b.Root.Position + right * b.StrafeDir * 8
			if not openSpot(b, spot) then
				b.StrafeDir = -b.StrafeDir
				spot = b.Root.Position + right * b.StrafeDir * 8
			end
			b.Moving = true
			b.Hum.WalkSpeed = BASE_SPEED * (b.Weapon.SpeedMultiplier or 1) * 0.7
			b.Hum:MoveTo(spot)
		else
			setState(b, "Fight: planted")
			stopMoving(b) -- sniper: plant and shoot
		end
		return
	end

	b.FireReady = false
	b.Face = nil
	if b.Weapon and b.Model:GetAttribute("VantageADS") then
		hook:Invoke("DummyAim", b.Model, 0, false)
	end

	-- the place we're heading is up something pathfinding can't climb: hook up there
	if b.NoPathGoal and now - b.NoPathAt < 6 and b.NoPathGoal.Y - b.Root.Position.Y > 8 and not onDeck(b) then
		if tryGrapple(b, b.NoPathGoal, 20) then
			return
		end
	end
	if b.SidestepUntil and now < b.SidestepUntil then
		setState(b, "Unstick")
		b.Moving = true
		b.Hum:MoveTo(b.SidestepTo)
		return
	end

	-- lost sight: push to where it was last seen
	local lk = b.LastKnown
	if lk and now - lk.At < MEMORY and aliveModel(lk.Model) and flat(lk.Pos - b.Root.Position).Magnitude > 6 and not unreachable(b, lk.Pos) then
		setState(b, "Chase last seen")
		goTo(b, lk.Pos, 1.05)
		return
	end
	-- shot by someone it can't see: turn to it
	if b.ThreatModel and now - b.ThreatAt < 2 and aliveModel(b.ThreatModel) then
		local r = b.ThreatModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			b.Face = r.Position
		end
	end
	-- a teammate called a contact nearby (snipers keep their post)
	local c = b.Job ~= "Overwatch" and callout(b)
	if c and flat(c - b.Root.Position).Magnitude > 10 and not unreachable(b, c) then
		setState(b, "Answer callout")
		goTo(b, c, 1.1)
		return
	end
	setState(b, "Job: " .. tostring(b.Job))
	jobMove(b)
end

-- ─── body turning (every frame, smooth) ─────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	for _, b in squad.Bots do
		if b.Alive and b.Root and b.Root.Parent and not b.Vehicle then
			if b.Grapple then
				local ok, err = pcall(stepGrapple, b, dt)
				if not ok then
					warn("[SquadBots] grapple: " .. tostring(err))
					b.Grapple = nil
				end
			end
			-- turn with a constraint, never by writing the root's CFrame: a CFrame write every frame
			-- cancels the Humanoid's walking, which froze bots in place (and the stuck check then
			-- made them hop)
			local face = b.Face
			local align = b.Align :: AlignOrientation?
			local want = face and flat(face - b.Root.Position)
			if align and want and want.Magnitude > 0.5 then
				b.Hum.AutoRotate = false
				align.CFrame = CFrame.lookAt(Vector3.zero, want.Unit)
				align.Enabled = true
			else
				if align then
					align.Enabled = false
				end
				b.Hum.AutoRotate = true
			end
		elseif b.Align then
			b.Align.Enabled = false -- seated in a vehicle: the seat weld owns the body
		end
	end
end)

-- ─── spawning ───────────────────────────────────────────────────────────────
local spawnBot

local function tint(model: Model, team: string)
	local c = TEAM_TINT[team]
	if not c then
		return
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Color = if p.Name == "Head" then c.Head else c.Body
		end
	end
end

local function onBotDied(b: Bot, model: Model)
	if b.Model ~= model or not b.Alive then
		return
	end
	b.Alive = false
	b.Target, b.FireReady, b.Face = nil, false, nil
	endGrapple(b, false)
	if b.Vehicle then
		VehicleService.BotRelease(b.Vehicle, true)
		claimed[b.Vehicle] = nil
	end
	if b.Mount then
		claimed[b.Mount] = nil
	end
	b.Vehicle, b.Mount, b.SeeParams = nil, nil, nil
	-- killed by a player (gun, knife, grenade, vehicle all stamp VantageKiller)
	if not b.ScoredBy then
		local id = model:GetAttribute("VantageKiller")
		local p = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
		if p and p.Team and p.Team.Name ~= b.Team then
			award(p.Team.Name)
		end
	end
	local gen = b.Gen
	task.delay(RESPAWN, function()
		if model.Parent then
			model:Destroy()
		end
		botByModel[model] = nil
		if gen == squad.Gen and not b.Removed then
			spawnBot(b)
		end
	end)
end

spawnBot = function(b: Bot)
	local points = spawnPoints(b.Team)
	local sp = points[((b.Slot - 1) % math.max(1, #points)) + 1]
	local pos = if sp then sp.Position + Vector3.new(rng:NextNumber(-3, 3), 3.5, rng:NextNumber(-3, 3)) else frontOf(b.Team) + Vector3.new(0, 4, b.Slot * 6)
	local model = hook:Invoke("SpawnDummy", pos, "SquadBot_" .. b.Name, true, b.Team) :: Model?
	if not model then
		warn("[SquadBots] SpawnDummy failed for " .. b.Name)
		return
	end
	model:PivotTo(CFrame.lookAt(pos, Vector3.new(0, pos.Y, pos.Z)))
	model:SetAttribute("DisplayName", b.Name .. BOT_SUFFIX)
	model:SetAttribute("SquadBot", true)
	model:SetAttribute("BotRole", b.RoleName)
	local hum = model:WaitForChild("Humanoid") :: Humanoid
	local root = model:WaitForChild("HumanoidRootPart") :: BasePart
	local head = model:WaitForChild("Head") :: BasePart
	hum.DisplayName = b.Name .. BOT_SUFFIX
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	tint(model, b.Team)
	buildLauncher(model)
	-- body turning toward its target (driven every frame by the Heartbeat loop)
	local faceAtt = Instance.new("Attachment")
	faceAtt.Name = "SquadFace"
	faceAtt.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "SquadFace"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = faceAtt
	align.MaxTorque = 1e6
	align.MaxAngularVelocity = TURN_RATE
	align.Responsiveness = 40
	align.Enabled = false
	align.Parent = root
	b.Align = align
	b.State = nil
	pcall(function()
		root:SetNetworkOwner(nil) -- server drives the body, never a nearby client
	end)

	b.Model, b.Hum, b.Root, b.Head = model, hum, root, head
	b.Alive, b.ScoredBy = true, nil
	b.Mag = b.Weapon.MagazineSize or 0
	b.Heat, b.HeatAt, b.ReloadUntil = 0, 0, 0
	b.Target, b.TargetSince, b.FireReady, b.LastKnown = nil, 0, false, nil
	b.ThreatModel, b.ThreatAt = nil, 0
	b.Wps, b.WpIndex, b.PathGoal, b.PathAt, b.PathBusy = nil, 1, nil, 0, false
	b.Moving, b.Stuck, b.StuckPos, b.StuckCheckAt = false, 0, root.Position, os.clock()
	b.SidestepUntil, b.SidestepTo = nil, nil
	b.StrafeDir, b.StrafeFlipAt = if rng:NextNumber() < 0.5 then 1 else -1, 0
	b.RetreatUntil, b.RetreatCooldown = 0, 0
	b.Hunt, b.Hunted, b.HuntUntil, b.Post, b.PostUntil = nil, false, 0, nil, 0
	b.NoPathGoal, b.NoPathAt = nil, 0
	b.Grapple, b.GrappleReady = nil, os.clock() + rng:NextNumber(2, 5)
	b.Vehicle, b.Mount, b.MountUntil, b.SeeParams = nil, nil, 0, nil
	b.WantVehicle = false
	b.WantVehicle = (b.Job == "Push" or b.Job == "Flank") and os.clock() >= (b.NoVehicleUntil or 0)
		and rng:NextNumber() < VEHICLE_CHANCE and teamVehicleCount(b.Team) < MAX_BOT_VEHICLES
	b.VHunt, b.VHuntUntil = nil, 0
	b.VWps, b.VGoal, b.VPathAt, b.VPathBusy = nil, nil, 0, false
	b.VStuck, b.VStuckCount, b.VReverseUntil = 0, 0, 0
	b.Face = nil
	botByModel[model] = b

	hum.Died:Connect(function()
		onBotDied(b, model)
	end)
	-- shot by a player: turn to them and tell the team
	local function onHurt()
		local id = model:GetAttribute("LastDamagedBy")
		local p = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
		local c = p and p.Character
		if c and aliveModel(c) then
			b.ThreatModel, b.ThreatAt = c, os.clock()
			local r = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				intel[b.Team][c] = { Pos = r.Position, At = os.clock() }
			end
		end
	end
	model:GetAttributeChangedSignal("LastDamagedBy"):Connect(onHurt)
	model:GetAttributeChangedSignal("Shield"):Connect(onHurt)
	hum.HealthChanged:Connect(onHurt)

	task.delay(0.4, function()
		if model.Parent and b.Model == model then
			hook:Invoke("DummyEquip", model, b.Weapon.Id)
		end
	end)
	task.spawn(gunner, b, b.Gen)
end

-- ─── squad control ──────────────────────────────────────────────────────────
local function clearSquad()
	squad.Gen += 1
	for _, b in squad.Bots do
		b.Alive = false
		if b.Grapple then
			endGrapple(b, false)
		end
		if b.Vehicle then
			VehicleService.BotRelease(b.Vehicle, true)
		end
		if b.Model and b.Model.Parent then
			b.Model:Destroy()
		end
	end
	table.clear(squad.Bots)
	table.clear(botByModel)
	table.clear(claimed)
	intel.Blue, intel.Red = {}, {}
	Workspace:SetAttribute("SquadBotsActive", false)
end

local function makeBot(def, team: string, slot: number, idx: number): Bot
	local role = ROLES[def.Role] or ROLES.Rifleman
	local name = def.Name .. (if idx > 1 then "-" .. idx else "")
	return {
		Name = name,
		Team = team,
		RoleName = def.Role,
		Role = role,
		Job = def.Job,
		Slot = slot,
		Weapon = Config.Weapons[role.Weapon] or Config.Weapons[Config.DefaultWeapon],
		Gen = squad.Gen,
	}
end

-- vehicle routes go round the centre pits (only vehicle paths carry the VehiclePit cost)
local function markPits()
	for _, p in Workspace:GetDescendants() do
		if p:IsA("BasePart") and string.find(p.Name, "Pit") and p.Position.Y < PIT_Y and not p:FindFirstChild("SquadPitMarker") then
			local mod = Instance.new("PathfindingModifier")
			mod.Name = "SquadPitMarker"
			mod.Label = "VehiclePit"
			mod.Parent = p
		end
	end
end

local function spawnSquad(player: Player?, diffName: string, allyCount: number, enemyCount: number)
	fillOn = false
	clearSquad()
	squad.Manual = true -- a hand-made squad: the bot fill leaves it alone until Idle
	markPits()
	squad.Diff = DIFFICULTY[diffName] or DIFFICULTY.normal
	Workspace:SetAttribute("SquadBotsActive", true)
	local myTeam = if player and player.Team and not player.Neutral then player.Team.Name else "Blue"
	local enemyTeam = otherTeam(myTeam)
	for i = 1, allyCount do
		local def = ALLIES[((i - 1) % #ALLIES) + 1]
		table.insert(squad.Bots, makeBot(def, myTeam, i, math.floor((i - 1) / #ALLIES) + 1))
	end
	for i = 1, enemyCount do
		local def = ENEMIES[((i - 1) % #ENEMIES) + 1]
		table.insert(squad.Bots, makeBot(def, enemyTeam, i, math.floor((i - 1) / #ENEMIES) + 1))
	end
	for _, b in squad.Bots do
		task.spawn(spawnBot, b)
	end
	local note = ""
	if not DamageService.CombatEnabled() then
		note = if phase() == "Idle" or phase() == nil
			then " Not in a match: DEPLOY → START NOW so they can fight."
			else " Holding in spawn until the match goes Live."
	end
	say(player, string.format("%d allies (%s) vs %d enemies (%s), %s.%s", allyCount, myTeam, enemyCount, enemyTeam, squad.Diff.Label, note))
end

local function command(player: Player?, text: string)
	local words = {}
	for w in string.gmatch(string.lower(text or ""), "%S+") do
		table.insert(words, w)
	end
	if words[1] == "clear" or words[1] == "off" or words[1] == "kill" then
		fillOn = false
		clearSquad()
		squad.Manual = true
		say(player, "Squad cleared.")
		return
	end
	local diff, nums = "normal", {}
	for _, w in words do
		if DIFFICULTY[w] then
			diff = w
		elseif tonumber(w) then
			table.insert(nums, math.clamp(math.floor(tonumber(w) :: number), 0, 8))
		end
	end
	spawnSquad(player, diff, nums[1] or 4, nums[2] or 5)
end

-- chat: /squad … (a TextChatCommand so it never shows in chat; Player.Chatted as a fallback)
local lastCmd: { [Player]: number } = {}
local function fromChat(player: Player, msg: string)
	local rest = string.match(msg, "^/squad%s*(.*)$")
	if not rest then
		return
	end
	if lastCmd[player] and os.clock() - lastCmd[player] < 0.5 then
		return
	end
	lastCmd[player] = os.clock()
	task.spawn(command, player, rest)
end

if STUDIO then -- 2026-11-19: chat commands are Studio-only
pcall(function()
	local parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	local old = parent:FindFirstChild("SquadCommand")
	if old then
		old:Destroy()
	end
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "SquadCommand"
	cmd.PrimaryAlias = "/squad"
	cmd.Parent = parent
	cmd.Triggered:Connect(function(source: TextSource, text: string)
		local p = Players:GetPlayerByUserId(source.UserId)
		if p then
			fromChat(p, text)
		end
	end)
end)
local function hookChat(p: Player)
	p.Chatted:Connect(function(msg)
		fromChat(p, msg)
	end)
end
Players.PlayerAdded:Connect(hookChat)
for _, p in Players:GetPlayers() do
	hookChat(p)
end
Players.PlayerRemoving:Connect(function(p)
	lastCmd[p] = nil
end)
end -- STUDIO chat commands

-- vehicle guns fired by a bot land here (VehicleService can't credit a non-Player)
VehicleService.BotHurt = function(bot: Model, victim: Model, amount: number, weaponId: string, pos: Vector3, dir: Vector3, explosive: boolean)
	local b = botByModel[bot]
	if b and b.Alive then
		applyHit(b, victim, amount, false, dir, pos, { Id = weaponId, Kind = "Vehicle", Explosive = explosive })
	end
end

-- command bar / other scripts
local bindable = Instance.new("BindableFunction")
bindable.Name = "Command"
bindable.OnInvoke = function(player: Player?, text: string?)
	command(player, text or "")
	return #squad.Bots
end
bindable.Parent = script

-- ─── bot fill (2026-11-19) ─────────────────────────────────────────────────
-- From Prep on, each team is topped up to MatchConfig.BotFill.PerTeam (default: the mode's TeamSize).
-- A player who joins takes a bot's place (a dead one first); one who leaves is replaced.
local CALLSIGNS = {
	Blue = { "KESTREL", "HALCYON", "BASTION", "WRAITH", "FALCON", "ORION", "TALON", "SABRE" },
	Red = { "ROOK", "VIPER", "SPECTER", "ASH", "GRIM", "HEX", "FANG", "DREAD" },
}
local FILL_ROLES = {
	{ Role = "Rifleman", Job = "Escort" },
	{ Role = "Breacher", Job = "Flank" },
	{ Role = "Marksman", Job = "Push" },
	{ Role = "Sniper", Job = "Overwatch" },
	{ Role = "Rifleman", Job = "Push" },
	{ Role = "Suppressor", Job = "Flank" },
	{ Role = "Marksman", Job = "Escort" },
	{ Role = "Breacher", Job = "Push" },
}
local FILL_PHASES = { Prep = true, Countdown = true, Live = true }

local function humansOn(team: string): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("MatchStatus") == "Match" and p.Team and not p.Neutral and p.Team.Name == team then
			n += 1
		end
	end
	return n
end

local function fillTarget(): number
	local mode = MatchConfig.Modes[Match:GetAttribute("Mode") or ""]
	return math.max(0, FILL.PerTeam or (mode and mode.TeamSize) or 5)
end

local function botsOn(team: string): { Bot }
	local list = {}
	for _, b in squad.Bots do
		if b.Team == team and not b.Removed then
			table.insert(list, b)
		end
	end
	return list
end

local function addFillBot(team: string)
	local used = {}
	for _, b in botsOn(team) do
		used[b.Slot] = true
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	local names = CALLSIGNS[team] or CALLSIGNS.Blue
	local def = FILL_ROLES[((slot - 1) % #FILL_ROLES) + 1]
	local b = makeBot({ Name = names[((slot - 1) % #names) + 1], Role = def.Role, Job = def.Job }, team, slot, math.floor((slot - 1) / #names) + 1)
	b.Fill = true
	table.insert(squad.Bots, b)
	task.spawn(spawnBot, b)
end

local function removeBot(b: Bot)
	b.Removed, b.Alive = true, false
	if b.Grapple then
		endGrapple(b, false)
	end
	if b.Vehicle then
		VehicleService.BotRelease(b.Vehicle, true)
		claimed[b.Vehicle] = nil
	end
	if b.Mount then
		claimed[b.Mount] = nil
	end
	if b.Model then
		botByModel[b.Model] = nil
		if b.Model.Parent then
			b.Model:Destroy()
		end
	end
	local i = table.find(squad.Bots, b)
	if i then
		table.remove(squad.Bots, i)
	end
end

local function rebalance()
	if not fillOn or not FILL_PHASES[phase() or ""] then
		return
	end
	local target = fillTarget()
	for _, team in { "Blue", "Red" } do
		local want = math.max(0, target - humansOn(team))
		local have = botsOn(team)
		while #have > want do
			local pick = have[#have]
			for _, b in have do
				if not b.Alive then
					pick = b
					break
				end
			end
			removeBot(pick)
			table.remove(have, table.find(have, pick) :: number)
		end
		for _ = #have + 1, want do
			addFillBot(team)
		end
	end
	Workspace:SetAttribute("SquadBotsActive", #squad.Bots > 0)
end

local function startFill()
	if fillOn or not FILL_HERE or (squad.Manual and STUDIO) then
		return
	end
	clearSquad()
	markPits()
	squad.Diff = DIFFICULTY[FILL.Difficulty or "normal"] or DIFFICULTY.normal
	fillOn = true
	rebalance()
	print(string.format("[SquadBots] bot fill: %d per team, %d bots, %s", fillTarget(), #squad.Bots, squad.Diff.Label))
end

-- phase changes: fill from Prep on, tidy up when the match is back at the menu
Match:GetAttributeChangedSignal("Phase"):Connect(function()
	local ph = phase()
	if ph == "Idle" then
		fillOn = false
		squad.Manual = nil
		if #squad.Bots > 0 then
			clearSquad()
			print("[SquadBots] match over, squad cleared")
		end
	elseif FILL_PHASES[ph or ""] then
		startFill()
	end
end)
task.spawn(function()
	while true do
		task.wait(2)
		if fillOn then
			local ok, err = pcall(rebalance)
			if not ok then
				warn("[SquadBots] fill: " .. tostring(err))
			end
		end
	end
end)

-- ─── main loop ──────────────────────────────────────────────────────────────
task.spawn(function()
	while true do
		task.wait(TICK)
		if #squad.Bots > 0 then
			refreshCache()
			for _, b in squad.Bots do
				if b.Alive and b.Root and b.Root.Parent then
					local ok, err = pcall(think, b)
					if not ok then
						warn("[SquadBots] " .. b.Name .. ": " .. tostring(err))
					end
					if DamageService.CombatEnabled() and not b.Vehicle and not b.Grapple then
						checkStuck(b)
					end
				end
			end
		end
	end
end)
