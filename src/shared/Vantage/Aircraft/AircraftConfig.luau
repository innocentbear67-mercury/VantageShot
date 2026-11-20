--!strict
--[[
	VANTAGE — AircraftConfig (shared: server schedule + validation, client render + feel)
	The periodic dropship flyby that players can grapple onto, hang beneath and drop from.

	Everything gameplay-relevant is here: route, timing, speed, altitude, hooks, rider limits,
	grapple feel and audio. Units: studs, seconds, studs/second.

	Pieces:
		ReplicatedStorage.Vantage.Aircraft.AircraftConfig   this file
		ReplicatedStorage.Vantage.Aircraft.AircraftPath     deterministic flight path (shared math)
		ReplicatedStorage.Vantage.Aircraft.AircraftModel    the user's imported aircraft (template, never moved)
		ServerScriptService.VantageServer.AircraftService   schedule + attach / hang / release authority
		StarterPlayerScripts.VantageAircraftClient          renders the aircraft, audio, markers, riders
		  .AircraftRuntime                                  API used by VantageAbilityClient (targeting)
	The grapple itself is still VantageAbilityClient + MovementController + GrappleFX + AbilityServer.
]]

local Config = {}

Config.Enabled = true

-- ── the model ────────────────────────────────────────────────────────────────────────────
-- The imported mesh (asset 133814930114085, texture 123303217659833) is a 1 x 0.28 x 1 box with
-- its nose toward -Z (Roblox's forward) as imported. Everything below that says "mesh units"
-- uses those coordinates (y measured from the bottom); they are scaled by Length at runtime.
-- Note: the source FBX has the nose at +Z; the Roblox importer flipped Z.
Config.ModelName = "AircraftModel"
Config.Length = 72 -- studs nose to tail (and wingtip to wingtip)
Config.MeshCenter = Vector3.new(0, 0.14, 0) -- bounding-box centre of the mesh, mesh units
Config.ModelRotation = CFrame.identity -- mesh -> aircraft frame (nose already on -Z, the LookVector)

-- ── schedule (server-authoritative) ──────────────────────────────────────────────────────
Config.RequireLivePhase = true -- only during the match's Live phase
Config.FirstDelay = 30 -- seconds after Live starts until the first flyby begins
Config.Interval = 55 -- seconds from one aircraft leaving until the next one begins
Config.StartLead = 0.8 -- a flight is announced this far ahead so every client has it before t=0
-- Studio playtests without a running match: flybys anyway, on a short loop
Config.StudioAlwaysOn = true
Config.StudioFirstDelay = 6
Config.StudioInterval = 12

-- Direction 1 = Blue side -> Red side (the route below as written), -1 = the same track flown
-- backwards. The first flyby of every match is FirstDirection, then they alternate.
Config.FirstDirection = 1

-- ── route ────────────────────────────────────────────────────────────────────────────────
-- Waypoints from the BLUE side (-X) to the RED side (+X); the reverse flight uses the same
-- points in reverse order, so altitude, speed and reach are identical both ways. Pos is the
-- aircraft centre. A smooth centripetal Catmull-Rom spline runs through them; Speed is blended
-- along the path. The map is mirror-symmetric in X and so is this route.
--   * the MIDDLE of the map: straight down the east-west avenue (z ~0) from over the Blue
--     hangar, across the core, to over the Red hangar - where the fighting is.
--   * the spire (shaft + crown to 185, mast to 224) stands exactly on the centre line, and the
--     four pylons (116) flank it, so the aircraft banks gently round the SOUTH side of the spire
--     (z ~66 at x 0, wingtip well clear even when banked) and back onto the avenue.
--   * height: ~150 over the core (riders' feet clear the pylons), ~185 over the hangar roofs
--     (138). That is high, so the grapple reaches further on the aircraft (Grapple.Range).
--   * then a LOOP ROUND THE MAP before it leaves: past the Red hangar it banks north into a
--     circuit inside the compound walls (north edge -> down the west side over the Blue hangar ->
--     south edge) and flies off east from the south-east corner. Run backwards (Red -> Blue) the
--     same track gives the loop first and the middle pass last.
--   * the loop stays ~70 inside the compound walls (x +-497, z +-452) and above the edge blocks
--     (90-110) and hangar roofs (130).
--   * re-check after any map change: the clearance sweep in the build notes, and the hang HUD
--     warns NO GROUND BELOW when the predicted landing is a void.
Config.Route = {
	--  1-5   long approach over the scenery valley (terrain under this line < 140)
	{ Pos = Vector3.new(-2700, 380, -160), Speed = 100 },
	{ Pos = Vector3.new(-1900, 335, -110), Speed = 95 },
	{ Pos = Vector3.new(-1150, 298, -40), Speed = 90 },
	{ Pos = Vector3.new(-700, 245, 0), Speed = 82 },
	{ Pos = Vector3.new(-420, 192, 0), Speed = 62 },
	--  6-10  the middle: down the avenue, round the south side of the spire
	{ Pos = Vector3.new(-230, 182, 0), Speed = 50 }, -- 6: hooks open here (Blue->Red)
	{ Pos = Vector3.new(-110, 154, 34), Speed = 44 },
	{ Pos = Vector3.new(0, 150, 66), Speed = 42 },
	{ Pos = Vector3.new(110, 154, 34), Speed = 44 },
	{ Pos = Vector3.new(230, 182, 0), Speed = 50 },
	-- 11-23  the loop: over the Red hangar, along the north edge, down the west side over the
	--        Blue hangar, along the south edge
	{ Pos = Vector3.new(360, 192, -40), Speed = 54 },
	{ Pos = Vector3.new(420, 185, -190), Speed = 56 },
	{ Pos = Vector3.new(330, 172, -350), Speed = 56 },
	{ Pos = Vector3.new(120, 165, -395), Speed = 56 },
	{ Pos = Vector3.new(-120, 165, -395), Speed = 56 },
	{ Pos = Vector3.new(-330, 172, -350), Speed = 56 },
	{ Pos = Vector3.new(-420, 185, -190), Speed = 56 },
	{ Pos = Vector3.new(-430, 194, 0), Speed = 56 },
	{ Pos = Vector3.new(-420, 185, 190), Speed = 56 },
	{ Pos = Vector3.new(-330, 172, 345), Speed = 56 },
	{ Pos = Vector3.new(-120, 165, 375), Speed = 56 },
	{ Pos = Vector3.new(120, 165, 375), Speed = 56 },
	{ Pos = Vector3.new(330, 172, 345), Speed = 58 }, -- 23: riders dropped here (Blue->Red)
	-- 24-28  away to the east over the scenery
	{ Pos = Vector3.new(470, 195, 260), Speed = 64 },
	{ Pos = Vector3.new(700, 245, 150), Speed = 82 },
	{ Pos = Vector3.new(1150, 298, 60), Speed = 90 },
	{ Pos = Vector3.new(1900, 335, -60), Speed = 95 },
	{ Pos = Vector3.new(2700, 380, -160), Speed = 100 },
}
Config.SampleSpacing = 2 -- studs between precomputed path samples
Config.Bank = {
	Max = 30, -- degrees
	Gain = 1.0,
	VirtualG = 20, -- lower = more bank for the same turn (real gravity would barely bank at these speeds)
	Window = 60, -- studs either side used to measure the turn (smooths the roll)
}
Config.Bob = { Amplitude = 0.7, Period = 4.5 } -- gentle hover bob (studs, seconds)
Config.FadeTime = 1.6 -- fade in at the start of the route, out at the end (it starts far outside the map)

-- The grapple window, by distance along the route: hooks open at one of these waypoints and
-- riders are dropped at the other, in travel order, so it works both ways (Blue->Red opens at
-- 6 and drops at 23; Red->Blue opens at 23 and drops at 6). Both are inside the compound.
Config.Zone = {
	OpenAt = 6, -- waypoint index (Blue->Red numbering above)
	DropAt = 23,
	CloseBeforeDrop = 60, -- studs: no new grapples this close to the drop point
	WarnAhead = 140, -- studs: the hang HUD counts down this far before the drop point
}

-- ── grapple points (under the hull) ──────────────────────────────────────────────────────
-- Mesh units (see above), measured by raycasting the real hull (precise collision): lowest
-- surface under each point, then HookDrop studs further down so the hook sits just clear of it.
-- Bow and Stern on the keel, the two others under the wing roots (outboard of the engine pods).
Config.Hooks = {
	{ Name = "Bow", Mesh = Vector3.new(0, 0.032, -0.22) },
	{ Name = "WingL", Mesh = Vector3.new(-0.19, 0.139, -0.02) },
	{ Name = "WingR", Mesh = Vector3.new(0.19, 0.139, -0.02) },
	{ Name = "Stern", Mesh = Vector3.new(0, 0.067, 0.16) },
}
Config.HookDrop = 0.6
Config.MaxRiders = 4 -- can be lower than #Hooks

-- ── grapple onto the aircraft (layered on AbilityConfig.Abilities.Grapple) ──────────────
Config.Grapple = {
	Range = 300, -- eye to hook: anyone within 300 of the dropship can grab on (the normal
	-- map grapple stays AbilityConfig's 110)
	ServerSlack = 25, -- extra range the server allows for latency
	-- easy aim: point anywhere NEAR the dropship and it takes the free hook nearest your crosshair
	AimConeDeg = 12, -- the dropship counts as aimed at within this angle ...
	AimRadius = 40, -- ... or within this many studs of the aim line, whichever is larger
	MinBelowDot = -0.2, -- you must not be well above it (the hull is in the way from above)
	PullAccel = 340, -- along the cable, relative to the aircraft
	MaxSpeed = 125, -- top speed relative to the aircraft (a 300-stud pull in about 2.8 s)
	SteerAccel = 30,
	SideDamp = 2.2,
	MaxPullTime = 7,
	StuckTime = 0.5,
	StuckSpeed = 5,
	PullLeashSlack = 40, -- server: further than start distance + this = not a real pull
	ProjectileSpeed = 420, -- the hook's flight to the aircraft (200 studs in about half a second)
	ReleaseMaxSpeed = 48, -- horizontal speed kept when letting go during the pull
	ReleaseMaxUp = 30,
	ArriveHop = 0,
}

-- ── hanging ──────────────────────────────────────────────────────────────────────────────
Config.Hang = {
	Length = 8, -- hook to character root
	EnterTime = 0.35, -- rope shortens from arrival length to Length over this
	Damping = 2.4, -- per second, swing relative to the aircraft (gravity here is 196: the rope swings fast)
	EntrySwing = 0.4, -- share of the arrival speed (relative to the hook) kept as swing when the hang starts
	MaxAngle = 48, -- degrees from straight down
	Leash = 30, -- server: further than this from the hook while hanging = detached
	ServerConfirm = 16, -- server: must be this close to the hook to be marked hanging
	VoidY = -60, -- a predicted landing below this height = a void (the map's kill plane is at -80)
}

-- ── camera while on the dropship ────────────────────────────────────────────────────────────────────
-- Third person from the moment the cable bites ("Bite") or only once hanging ("Hang"); back to
-- first person the moment you let go. Mouse / right stick still look around. The HUD (visor,
-- screen panels) is off for the ride and comes back on release; only the dropship prompts show.
Config.Camera = {
	ThirdPerson = true,
	From = "Bite", -- "Bite" | "Hang"
	Distance = 15, -- behind the rider
	Shoulder = 1.8, -- over-the-shoulder offset to the right
	Height = 1.5, -- focus above the rider's root
	BlendIn = 0.4, -- seconds from first person to the orbit
	PitchMin = -30, -- degrees (looking down)
	PitchMax = 65, -- degrees (looking up at the hull)
	StartPitchMin = -12, -- the ride camera opens between these (degrees), whatever angle you shot from
	StartPitchMax = 15,
	HullGap = 2, -- the camera stays at least this far below the aircraft's belly
	StickSpeed = 3.2, -- gamepad, radians per second at full tilt
}

-- ── letting go ───────────────────────────────────────────────────────────────────────────
Config.Release = {
	Inherit = 0.6, -- share of the aircraft's velocity kept
	MaxHorizontal = 46,
	Up = 4, -- small hop so the drop starts clean of the hook
	Cooldown = 1.0, -- grapple ready again this soon after letting go (hook a building on the way down)
	ExemptTail = 4, -- movement-validator grace for the fall and the carried speed
}

-- ── look and sound ───────────────────────────────────────────────────────────────────────
Config.Colors = {
	Lime = Color3.fromRGB(186, 255, 84),
	LimeWhite = Color3.fromRGB(238, 255, 220),
	NavLeft = Color3.fromRGB(255, 60, 60),
	NavRight = Color3.fromRGB(70, 255, 120),
	Engine = Color3.fromRGB(150, 210, 255),
}
Config.ShowIdleMarkers = true -- faint dots on free hooks in reach; the targeted one gets the full ring
-- the screen pointer to the dropship while a flyby is on: a marker over it when it is on screen,
-- an arrow at the screen edge pointing to it when it is not
Config.Pointer = {
	Enabled = true,
	EdgeMargin = 70, -- px from the screen edge for the off-screen arrow
	Label = "DROPSHIP",
}
-- extra lights on the model, mesh units
Config.Lights = {
	Engines = { Vector3.new(0.078, 0.183, 0.5), Vector3.new(-0.078, 0.183, 0.5) },
	NavLeft = Vector3.new(-0.495, 0.097, -0.033),
	NavRight = Vector3.new(0.495, 0.097, -0.033),
}
-- Licensed library audio (ProSoundEffects), same source as the rest of VANTAGE's sound
Config.Sounds = {
	-- dropship turbine whine: carries the "close" sound
	Whine = { Id = "rbxassetid://9112812185", Volume = 0.5, Speed = 1.25, RollOffMin = 45, RollOffMax = 700 },
	-- low engine roar: heard from far away, swells as it approaches
	Roar = { Id = "rbxassetid://9119414082", Volume = 0.6, Speed = 0.8, RollOffMin = 90, RollOffMax = 1500 },
	-- the pass overhead (played once, when it is closest to you)
	Pass = { Id = "rbxassetid://9120742158", Volume = 0.55, Speed = 1.15, Length = 4.5, Within = 190 },
	Doppler = 0.12, -- max pitch shift from approach / recede speed
}

return Config
