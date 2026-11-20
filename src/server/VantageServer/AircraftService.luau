--[[
	VANTAGE — AircraftService (server authority for the dropship flyby)

	Schedule
		Only during the match's Live phase (or always, in a Studio playtest with no match). The first
		flyby of a match is Config.FirstDirection (Blue -> Red), then every flyby alternates. A flight
		is published ONCE as attributes on ReplicatedStorage.Vantage.Aircraft:
			FlightId, FlightDir (1 / -1), FlightStart (workspace:GetServerTimeNow() time), FlightActive,
			NextFlight (server time the next one starts, 0 if none), Hook1..HookN (UserId of the rider, 0 = free)
		Every client and this server evaluate AircraftPath from those values, so the aircraft's
		position is identical everywhere without per-frame replication.

	Riders
		TryAttach   the grapple shot: flight / hook / zone / range / below-the-hull / line of sight /
		            rider limit, all checked against the hook position at the shot's own time
		MarkHanging the client reached the hook: confirmed only if really near it; sets the
		            character attribute VantageHanging (weapons refuse to fire while it is set)
		Release     letting go, death, respawn, leaving, flight end, match end, drop point, leash
		While attached the movement validator is exempted 0.7 s at a time, only while the rider
		stays on a leash around the moving hook. Every exit clears VantageAircraftHook /
		VantageHanging and the hook slot, so nothing outlives the ride.

	Used by AbilityServer (it owns the Ability remote and the grapple cooldown).
	Studio / admin: AircraftService.StartNow(direction?), AircraftService.Terminate(reason?)
	Studio playtests only: set the attribute DevCommand on ReplicatedStorage.Vantage.Aircraft (server
	side) to "Start1" / "Start-1" / "Terminate" to drive THIS instance from the command bar.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Folder = ReplicatedStorage.Vantage.Aircraft
local Config = require(Folder.AircraftConfig)
local Path = require(Folder.AircraftPath)
local remote = ReplicatedStorage.Vantage:WaitForChild("Remotes"):WaitForChild("Ability") :: RemoteEvent

local AircraftService = {}

local started = false
local flight = nil :: { Id: number, Dir: number, StartAt: number, Duration: number }?
local flightCounter = 0
local nextDir = Config.FirstDirection
local nextAt: number? = nil
-- player -> { Hook, FlightId, Phase = "Pull" | "Hang", StartedAt, StartDist, Character, Strikes }
local riders: { [Player]: any } = {}
local hookOwner: { [number]: Player } = {}
local releaseHandler: ((Player, string) -> ())? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function exempt(player: Player, seconds: number)
	local ev = script.Parent:FindFirstChild("ExemptMovement")
	if ev and ev:IsA("BindableEvent") then
		ev:Fire(player, seconds)
	end
end

local function publish()
	Folder:SetAttribute("FlightId", if flight then flight.Id else 0)
	Folder:SetAttribute("FlightDir", if flight then flight.Dir else 0)
	Folder:SetAttribute("FlightStart", if flight then flight.StartAt else 0)
	Folder:SetAttribute("FlightActive", flight ~= nil)
	Folder:SetAttribute("NextFlight", if not flight and nextAt then nextAt else 0)
end

local function setHook(i: number, player: Player?)
	hookOwner[i] = player
	Folder:SetAttribute("Hook" .. i, if player then player.UserId else 0)
end

local function relay(except: Player?, ...)
	for _, p in Players:GetPlayers() do
		if p ~= except then
			remote:FireClient(p, ...)
		end
	end
end

-- every character model: never blocks the line-of-sight ray
local function characters(): { Instance }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, tag in { "VantageDummy", "VantageBot" } do
		for _, m in CollectionService:GetTagged(tag) do
			table.insert(list, m)
		end
	end
	local standIns = Workspace:FindFirstChild("VantageIntroStandIns")
	if standIns then
		table.insert(list, standIns)
	end
	return list
end

-- first solid (CanCollide) thing along a ray
local function solidHit(origin: Vector3, dir: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = characters()
	params.FilterDescendantsInstances = ignore
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

local function aliveParts(player: Player): (Model?, BasePart?, Vector3?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	return character, root, if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
end

-- ── queries ────────────────────────────────────────────────────────────────────────────────

-- aircraft CFrame and velocity at a server time (nil if no flight / outside it)
function AircraftService.AircraftAt(t: number): (CFrame?, Vector3)
	if not flight then
		return nil, Vector3.zero
	end
	return Path.At(flight.Dir, flight.StartAt, t)
end

-- hook i world position, the aircraft's velocity and CFrame at a server time
function AircraftService.HookAt(i: number, t: number): (Vector3?, Vector3, CFrame?)
	local cf, vel = AircraftService.AircraftAt(t)
	if not cf then
		return nil, Vector3.zero, nil
	end
	return (cf * Path.HookLocal(i)).Position, vel, cf
end

function AircraftService.IsRider(player: Player): boolean
	return riders[player] ~= nil
end

function AircraftService.SetReleaseHandler(fn: (Player, string) -> ())
	releaseHandler = fn
end

-- ── riders ────────────────────────────────────────────────────────────────────────────────

local function riderCount(): number
	local n = 0
	for _ in riders do
		n += 1
	end
	return n
end

-- reason: "Release" (the player let go) | "Death" | "Respawn" | "Left" | "Ended" | "Drop" | "Leash" | "Timeout" | "Refused"
function AircraftService.Release(player: Player, reason: string, tellClient: boolean?)
	local r = riders[player]
	if not r then
		return
	end
	riders[player] = nil
	if hookOwner[r.Hook] == player then
		setHook(r.Hook, nil)
	end
	local character = r.Character
	if character and character.Parent then
		character:SetAttribute("VantageAircraftHook", nil)
		character:SetAttribute("VantageHanging", nil)
	end
	if tellClient and player.Parent then
		remote:FireClient(player, "AircraftDetach", reason)
	end
	local alive = player.Parent ~= nil and player.Character == character and reason ~= "Death" and reason ~= "Respawn" and reason ~= "Left"
	if alive and reason ~= "Leash" then
		exempt(player, Config.Release.ExemptTail) -- the fall and the carried speed
	end
	if alive and releaseHandler then
		releaseHandler(player, reason)
	end
	if character then
		relay(player, "GrappleEnd", character)
	end
end

-- the grapple shot at hook `hookIndex` of flight `flightId`, fired at server time `shotTime`
function AircraftService.TryAttach(player: Player, flightId: any, hookIndex: any, shotTime: any): (boolean, string?)
	if not Config.Enabled or not flight then
		return false, "NoFlight"
	end
	if flightId ~= flight.Id or type(hookIndex) ~= "number" or hookIndex ~= hookIndex then
		return false, "BadArgs"
	end
	local i = math.floor(hookIndex)
	if i < 1 or i > Path.HookCount() then
		return false, "BadArgs"
	end
	if riders[player] then
		return false, "AlreadyRiding"
	end
	if hookOwner[i] or riderCount() >= Config.MaxRiders then
		return false, "Full"
	end
	local character, root, eye = aliveParts(player)
	if not character or not root or not eye then
		return false, "Dead"
	end
	local now = serverNow()
	local t = if type(shotTime) == "number" and shotTime == shotTime then math.clamp(shotTime, now - 0.6, now) else now
	local hook, _, acf = AircraftService.HookAt(i, t)
	if not hook or not acf then
		return false, "NoFlight"
	end
	if not Path.ArmedAt(flight.Dir, t - flight.StartAt) then
		return false, "Zone"
	end
	local G = Config.Grapple
	local to = hook - eye
	local dist = to.Magnitude
	if dist > G.Range + G.ServerSlack or dist < 3 then
		return false, "Range"
	end
	-- the hooks are under the hull: from above, the hull is in the way
	if (-to.Unit):Dot(-acf.UpVector) < G.MinBelowDot - 0.12 then
		return false, "Above"
	end
	-- nothing solid between the player and the hook (the aircraft has no parts on the server,
	-- so anything this ray meets is map geometry)
	local hit = solidHit(eye, to)
	if hit and (hit.Position - eye).Magnitude < dist - 3 then
		return false, "Blocked"
	end
	riders[player] = {
		Hook = i, FlightId = flight.Id, Phase = "Pull", StartedAt = os.clock(), StartDist = dist,
		Character = character, Strikes = 0,
	}
	setHook(i, player)
	character:SetAttribute("VantageAircraftHook", i)
	exempt(player, 0.7)
	relay(player, "FX", character, "GrappleAircraft", { Flight = flight.Id, Hook = i })
	return true, nil
end

-- the client reached its hook and is hanging
function AircraftService.MarkHanging(player: Player)
	local r = riders[player]
	if not r or r.Phase ~= "Pull" then
		return
	end
	local _, root = aliveParts(player)
	local hook, vel = AircraftService.HookAt(r.Hook, serverNow())
	if not root or not hook then
		return
	end
	-- the rider's replicated position trails by their latency; allow for that
	local slack = Config.Hang.ServerConfirm + vel.Magnitude * 0.35
	if (root.Position - hook).Magnitude > slack then
		return -- not there (yet): the leash check still applies, weapons stay usable server-side
	end
	r.Phase = "Hang"
	r.HangAt = os.clock()
	r.Character:SetAttribute("VantageHanging", true)
end

-- ── flights ───────────────────────────────────────────────────────────────────────────────

local function releaseAll(reason: string)
	for player in riders do
		AircraftService.Release(player, reason, true)
	end
end

function AircraftService.Terminate(reason: string?)
	releaseAll(reason or "Ended")
	flight = nil
	publish()
end

local function startFlight(dir: number)
	flightCounter += 1
	flight = {
		Id = flightCounter,
		Dir = dir,
		StartAt = serverNow() + Config.StartLead,
		Duration = Path.Duration(dir),
	}
	nextAt = nil
	publish()
end

-- Studio / admin: launch now (direction defaults to the next in the alternation)
function AircraftService.StartNow(direction: number?)
	if flight then
		AircraftService.Terminate("Ended")
	end
	local dir = if direction then (if direction < 0 then -1 else 1) else nextDir
	startFlight(dir)
	nextDir = -dir
end

function AircraftService.State()
	return {
		Flight = flight, NextDir = nextDir, NextAt = nextAt, Riders = riderCount(),
		Now = serverNow(),
	}
end

local function allowed(): (boolean, boolean)
	if not Config.Enabled then
		return false, false
	end
	local match = ReplicatedStorage.Vantage:FindFirstChild("Match")
	local phase = match and match:GetAttribute("Phase")
	-- 2026-11-20: no dropship on a shrunk play area (1v1-4v4): riders would drop outside the zone
	local sc = match and match:GetAttribute("SizeClass")
	if sc == "S" or sc == "M" then
		return false, false
	end
	if phase == "Live" or not Config.RequireLivePhase then
		return true, false
	end
	if RunService:IsStudio() and Config.StudioAlwaysOn and (phase == nil or phase == "Idle") then
		return true, true
	end
	return false, false
end

local wasAllowed = false
local function scheduleStep()
	local ok, studio = allowed()
	local now = serverNow()
	if not ok then
		if flight then
			AircraftService.Terminate("Ended")
		end
		if wasAllowed then
			nextAt = nil
			nextDir = Config.FirstDirection -- every match starts Blue -> Red again
			publish()
		end
		wasAllowed = false
		return
	end
	if not wasAllowed then
		wasAllowed = true
		nextDir = Config.FirstDirection
		nextAt = now + (if studio then Config.StudioFirstDelay else Config.FirstDelay)
		publish()
	end
	if flight then
		if now > flight.StartAt + flight.Duration then
			releaseAll("Ended")
			flight = nil
			nextAt = now + (if studio then Config.StudioInterval else Config.Interval)
			publish()
		end
	elseif nextAt and now >= nextAt - Config.StartLead then
		local dir = nextDir
		nextDir = -dir
		startFlight(dir)
	end
end

-- five times a second: riders still legitimately on their hook?
local function riderStep()
	local now = serverNow()
	local G, H = Config.Grapple, Config.Hang
	for player, r in riders do
		local character, root = aliveParts(player)
		if not character or character ~= r.Character or not root then
			AircraftService.Release(player, if character then "Respawn" else "Death", false)
			continue
		end
		if not flight or flight.Id ~= r.FlightId then
			AircraftService.Release(player, "Ended", true)
			continue
		end
		local hook, vel, acf = AircraftService.HookAt(r.Hook, now)
		if not hook or not acf then
			AircraftService.Release(player, "Ended", true)
			continue
		end
		if Path.PastDropAt(flight.Dir, now - flight.StartAt) then
			AircraftService.Release(player, "Drop", true)
			continue
		end
		local lag = vel.Magnitude * 0.4 -- the rider's replicated position trails the true hook
		local dist = (root.Position - hook).Magnitude
		local leash
		if r.Phase == "Pull" then
			if os.clock() - r.StartedAt > G.MaxPullTime + 1.5 then
				AircraftService.Release(player, "Timeout", true)
				continue
			end
			leash = r.StartDist + G.PullLeashSlack + lag
		else
			leash = H.Leash + lag
		end
		if dist > leash then
			r.Strikes += 1
			if r.Strikes >= 3 then
				AircraftService.Release(player, "Leash", true)
			end
			continue
		end
		r.Strikes = 0
		exempt(player, 0.7)
	end
end

function AircraftService.Start()
	if started then
		return
	end
	started = true
	for i = 1, Path.HookCount() do
		setHook(i, nil)
	end
	publish()
	Path.Get(1)
	Path.Get(-1) -- build both directions up front
	Players.PlayerRemoving:Connect(function(p)
		AircraftService.Release(p, "Left", false)
	end)
	local function onPlayer(p: Player)
		p.CharacterAdded:Connect(function()
			AircraftService.Release(p, "Respawn", false)
		end)
	end
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	if RunService:IsStudio() then
		Folder:GetAttributeChangedSignal("DevCommand"):Connect(function()
			local cmd = Folder:GetAttribute("DevCommand")
			if cmd == "Start1" then
				AircraftService.StartNow(1)
			elseif cmd == "Start-1" then
				AircraftService.StartNow(-1)
			elseif cmd == "Terminate" then
				AircraftService.Terminate("Ended")
			end
			if cmd then
				Folder:SetAttribute("DevCommand", nil)
			end
		end)
	end
	local acc, sacc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		sacc += dt
		if sacc >= 0.25 then
			sacc = 0
			scheduleStep()
		end
		if acc >= 0.2 then
			acc = 0
			riderStep()
		end
	end)
end

return AircraftService
