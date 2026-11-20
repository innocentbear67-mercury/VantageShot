--!strict
--[[
	VANTAGE — VehicleConfig (shared)
	Single source of truth for the combined-arms vehicles. Read by the server (VehicleService:
	spawning, seats, validation, weapons, damage) and every client (driving feel, camera, HUD,
	visuals). Change numbers here only.

	Units: studs, seconds, studs/s, degrees unless noted. Vehicle space (seat / exit positions):
	+Z forward, +X left, +Y up, origin on the ground under the model's centre — the space of the
	imported asset (see VehicleBuilder for how a playable model is assembled from it).
	Damage values were proposed against the infantry balance (100 health + 100 shield,
	Vanguard ~270 DPS) and approved 2026-11-11.
]]

local Config = {}

Config.Tag = "VantageVehicle"

-- ─── interaction ─────────────────────────────────────────────────────────
Config.Interact = {
	Key = Enum.KeyCode.X,             -- enter (prompt) and exit (user 2026-11-11: was F; R is reload, E the grapple)
	GamepadKey = Enum.KeyCode.ButtonY,
	Distance = 14,                    -- prompt reach from the vehicle's nearest side
	HoldTime = 0.2,
	ExitKey = Enum.KeyCode.X,
	SeatKeys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six },
	CameraBlendTime = 0.45,           -- seconds the camera takes to move into / out of the vehicle view
	ExitClearance = Vector3.new(4, 5.4, 4), -- free box an exiting player needs
	ExitInvulnerable = 0.6,           -- brief movement-validator grace after a seat change / exit
	EnemyCanTakeEmpty = true,         -- an empty vehicle can be taken by either team
	-- Halo-style driving: hold W and the vehicle steers itself toward where the camera looks
	-- (A / D still steer by hand and override it). Per vehicle: Drive.CameraSteerAngle = heading error
	-- (deg) that gives full lock.
	CameraSteer = true,
}

-- ─── small arms vs vehicles (multiplier on the gun's body-shot damage at that range) ───
-- (2026-11-11: raised with the vehicle shields so infantry can finish a vehicle — tanky, not immune)
Config.SmallArms = {
	Default = 0.35,
	Longshot = 0.6,
	Breacher = 0.3,
	Knife = 0,
}

-- Studio solo testing: an EMPTY vehicle can be damaged by its own team (so one tester can shoot
-- the parked vehicles). Never applies in a live server.
Config.Studio = { EmptyVehiclesNeutral = true }

-- model scale applied by VehicleBuilder (1 = the size of the imported asset)
Config.Scale = { Tank = 1, APC = 0.88, Buggy = 0.82 }

-- ─── vehicle energy shield (absorbs before the hull, recharges, honeycomb skin) ───
-- Per-vehicle Max / RegenDelay / RegenRate live under each vehicle's Shield.
Config.ShieldVisual = {
	Image = "rbxassetid://3423005094", -- the infantry shield's seamless hex grid (Shield.ShieldConfig)
	Color = Color3.fromRGB(64, 170, 255),
	White = Color3.fromRGB(214, 240, 255),
	Pad = 0.45,             -- studs the shield skin stands off each mesh (it follows the vehicle's shape)
	Tile = 4.5,             -- studs per hex tile
	IdleAlpha = 0.66,       -- hex transparency at full shield, untouched (was 0.93: too faint)
	HitAlpha = 0.0,         -- flash when struck
	FilmIdle = 0.35,        -- the shield shell (ForceField material, hex pattern) at rest
	FilmHit = 0.0,
	MaxDistance = 600,
	Sounds = {
		Hit = { Id = "rbxassetid://98609496290942", Volume = 0.35, StartAt = 0.03, Speed = 1.55 },
		Break = { Id = "rbxassetid://9114315137", Volume = 0.9, StartAt = 0.17 },
		Recharge = { Id = "rbxassetid://9125980435", Volume = 0.5, StartAt = 0.22, Speed = 1.1 },
	},
}

-- ─── hit confirmation (the game's own confirm cues from the Vanguard config, layered) ───
Config.HitMarker = {
	Hit = { Id = "rbxassetid://138148057831879", Volume = 0.55 },
	Shield = { Id = "rbxassetid://138148057831879", Volume = 0.5, Speed = 1.35 },
	Hull = { Id = "rbxassetid://98609496290942", Volume = 0.45, StartAt = 0.03, Speed = 0.9 },
	Kill = {
		{ Id = "rbxassetid://138148057831879", Volume = 0.6, Speed = 0.8 },
		{ Id = "rbxassetid://137096881472307", Volume = 0.5, Speed = 0.78, StartAt = 0.06 },
		{ Id = "rbxassetid://9126073318", Volume = 0.9, StartAt = 0.11 },
	},
	Destroyed = {
		{ Id = "rbxassetid://9125484367", Volume = 0.7, Speed = 1.05 }, -- deep hit + boom (MatchConfig)
		{ Id = "rbxassetid://138148057831879", Volume = 0.6, Speed = 0.7 },
		{ Id = "rbxassetid://9126073318", Volume = 0.9, StartAt = 0.11 },
	},
	MinGap = 0.045, -- seconds between confirm sounds (MG streams)
}

-- ─── destruction ─────────────────────────────────────────────────────────
Config.Destruction = {
	KillCrew = true,          -- a destroyed vehicle kills everyone inside (credited to whoever destroyed it)
	OccupantDamage = 60,      -- only used when KillCrew = false: each occupant thrown clear takes this
	WreckTime = 8,            -- burning wreck stays this long, then fades out
	FadeTime = 1.6,
	AbandonTime = 45,         -- empty and away from its spawn this long -> quietly recycled
	AbandonSpawnRadius = 60,  -- within this of its own spawn it never counts as abandoned
}

-- ─── per vehicle ─────────────────────────────────────────────────────────
-- RunOver: lethal at KillSpeed and above, else Damage scaled by speed (DamageAt = full damage speed); nothing below MinSpeed.
Config.Vehicles = {
	Tank = {
		DisplayName = "MBT // GOLIATH",
		Health = 3200, -- -20% (was 4000)
		Shield = { Max = 960, RegenDelay = 6, RegenRate = 150 },
		Mass = 1600,
		RespawnTime = 90,
		Camera = { Distance = 34, Height = 11, Fov = 70, ZoomFov = 30, PivotY = 6 },
		Drive = {
			Kind = "Tracks",
			MaxForward = 42, MaxReverse = 16,
			Accel = 13, Brake = 38, Coast = 7, HandBrake = 38,
			TurnRate = 70,          -- deg/s pivot turn at standstill (was 62)
			TurnRateAtSpeed = 48,   -- deg/s at full speed (was 34)
			TurnAccel = 8,          -- how fast the yaw rate follows the stick (1/s) (was 3.5: too sluggish)
			CameraSteerAngle = 20,
			Grip = 11,              -- lateral grip (1/s)
			Friction = 1.15,        -- friction coefficient cap
			Sag = 0.45, Damping = 0.6, -- suspension: static compression (studs), damping ratio
			Stabilize = 2.2,        -- anti-roll / anti-flip strength
		},
		Seats = {
			{ Name = "Driver", Role = "Driver", Pos = Vector3.new(0, 4.2, 6.5), Hidden = true },
			{ Name = "Gunner", Role = "Gunner", Pos = Vector3.new(-1.5, 7.2, -4), Hidden = true },
		},
		Exits = { Vector3.new(10, 0, -2), Vector3.new(-10, 0, -2), Vector3.new(0, 0, -18.5), Vector3.new(10, 0, -10), Vector3.new(-10, 0, -10), Vector3.new(10, 0, 6), Vector3.new(-10, 0, 6) },
		Weapon = {
			Kind = "Cannon", Id = "TankCannon", DisplayName = "120MM CANNON",
			Controller = "Gunner",   -- gunner seat; the driver aims and fires when it is empty
			YawSpeed = 38, PitchSpeed = 24, PitchMin = -8, PitchMax = 18, -- deg, deg/s
			Reload = 4,
			ShellSpeed = 450, ShellGravity = 0.12, MaxRange = 1400, -- gravity fraction of workspace.Gravity
			DirectVehicle = 1200, SplashVehicle = 420,
			SplashRadius = 24, SplashInfantry = 250, SplashMin = 0.2, -- (radius was 14) -- infantry damage at the edge = SplashMin x
			DirectInfantry = 250,
			Recoil = 0.6,            -- hull kick (studs/s back) for feel
			-- auto-aim: a locked target gets a full firing solution (lead + shell drop); vehicles first
			Homing = { Cone = 8, Range = 900, Prefer = "Vehicles" },
		},
		RunOver = { MinSpeed = 8, KillSpeed = 20, Damage = 300 },
		Visual = { Wheels = "Tracks", Dust = 1.2 },
	},
	APC = {
		DisplayName = "APC // MULE",
		Health = 1760, -- -20% (was 2200)
		Shield = { Max = 640, RegenDelay = 6, RegenRate = 110 },
		Mass = 1000,
		RespawnTime = 60,
		Camera = { Distance = 30, Height = 10, Fov = 72, ZoomFov = 40, PivotY = 6 },
		Drive = {
			Kind = "Wheels",
			MaxForward = 50, MaxReverse = 18, -- -20% (was 62 / 22)
			Accel = 19, Brake = 46, Coast = 6, HandBrake = 55,
			MaxSteer = 32, MaxSteerAtSpeed = 20, SteerSpeed = 180, -- deg, deg, deg/s (was 30 / 11 / 120)
			Grip = 10, RearGrip = 10, Friction = 1.15,
			CameraSteerAngle = 28,
			Sag = 0.9, Damping = 0.45,
			Stabilize = 1.8,
		},
		Seats = {
			{ Name = "Driver", Role = "Driver", Pos = Vector3.new(2.6, 4.4, 9), Hidden = true },
			{ Name = "Gunner", Role = "Gunner", Pos = Vector3.new(0, 5.6, -2.6), Hidden = true },
			{ Name = "Passenger 1", Role = "Passenger", Pos = Vector3.new(2.8, 4.2, -6), Hidden = true },
			{ Name = "Passenger 2", Role = "Passenger", Pos = Vector3.new(-2.8, 4.2, -6), Hidden = true },
			{ Name = "Passenger 3", Role = "Passenger", Pos = Vector3.new(2.8, 4.2, -10), Hidden = true },
			{ Name = "Passenger 4", Role = "Passenger", Pos = Vector3.new(-2.8, 4.2, -10), Hidden = true },
		},
		-- APC: the rear ramp first, then the sides, then the nose
		Exits = { Vector3.new(0, 0, -17), Vector3.new(4.5, 0, -17), Vector3.new(-4.5, 0, -17), Vector3.new(10.5, 0, -7), Vector3.new(-10.5, 0, -7), Vector3.new(10.5, 0, 4), Vector3.new(-10.5, 0, 4), Vector3.new(0, 0, 17) },
		Weapon = {
			Kind = "MG", Id = "APCGun", DisplayName = "RWS 30MM",
			Controller = "Gunner",
			YawSpeed = 120, PitchSpeed = 80, PitchMin = -10, PitchMax = 40,
			RPM = 600, Damage = 20, VehicleMultiplier = 0.5, Spread = 0.6, MaxRange = 650,
			Heat = { PerShot = 0.025, CoolRate = 0.35, CoolDelay = 0.4, Lock = 2.2 }, -- ~4 s to overheat
			TracerEvery = 2,
			Homing = { Cone = 9, Range = 550 }, -- rounds steer onto the locked enemy (infantry first)
		},
		RunOver = { MinSpeed = 10, KillSpeed = 25, Damage = 220 },
		Visual = { Wheels = "Wheels", Dust = 1.0 },
	},
	Buggy = {
		DisplayName = "RECON // VIPER",
		Health = 720, -- -20% (was 900)
		Shield = { Max = 280, RegenDelay = 5, RegenRate = 70 },
		Mass = 450,
		RespawnTime = 30,
		Camera = { Distance = 24, Height = 8, Fov = 74, ZoomFov = 45, PivotY = 4 },
		Drive = {
			Kind = "Wheels",
			MaxForward = 77, MaxReverse = 24, -- -20% (was 96 / 30)
			Accel = 40, Brake = 70, Coast = 7, HandBrake = 80,
			MaxSteer = 36, MaxSteerAtSpeed = 18, SteerSpeed = 260, -- (was 34 / 9 / 210)
			Grip = 9, RearGrip = 9.5, Friction = 1.15, -- front grips almost as hard as the rear: turns in, still stable
			-- no camera steering: the buggy's driver aims its turret with the camera and steers with A / D
			Sag = 1.3, Damping = 0.38,
			Stabilize = 1.6,
		},
		Seats = {
			{ Name = "Driver", Role = "Driver", Pos = Vector3.new(1.7, 3.9, -1.3), Hidden = false },
			{ Name = "Gunner", Role = "Gunner", Pos = Vector3.new(-2.4, 3.9, -1.3), Hidden = false },
		},
		Exits = { Vector3.new(7.8, 0, -1), Vector3.new(-7.8, 0, -1), Vector3.new(0, 0, -12.5), Vector3.new(7.8, 0, 5), Vector3.new(-7.8, 0, 5), Vector3.new(0, 0, 12.5) },
		Weapon = {
			Kind = "MG", Id = "BuggyGun", DisplayName = "M-12 HMG",
			Controller = "Gunner",
			YawSpeed = 200, PitchSpeed = 140, PitchMin = -12, PitchMax = 45,
			RPM = 750, Damage = 14, VehicleMultiplier = 0.5, Spread = 0.9, MaxRange = 500,
			Heat = { PerShot = 0.027, CoolRate = 0.4, CoolDelay = 0.35, Lock = 2 }, -- ~3 s to overheat
			TracerEvery = 2,
			Homing = { Cone = 10, Range = 450 }, -- rounds steer onto the locked enemy (infantry first)
		},
		RunOver = { MinSpeed = 12, KillSpeed = 1e9, Damage = 120, DamageAt = 35 }, -- 120 at >= 35 studs/s, scaled below
		Visual = { Wheels = "Wheels", Dust = 1.4 },
	},
}

-- the drone: one pilot (hidden in the airframe), flies inside an altitude band, twin fixed guns
-- 2026-11-20 BALANCE (big playtest: "p2w"): no homing, ~40% less DPS with range falloff, overheats in
-- ~2.5 s, fragile to small arms (x2.3 on top of SmallArms), slower, and a much longer respawn.
Config.Vehicles.Drone = {
	DisplayName = "DRONE // WASP",
	Health = 160, -- was 240 (480 originally)
	Shield = { Max = 60, RegenDelay = 6, RegenRate = 20 }, -- was 100 / 5 / 30
	SmallArmsTaken = 2.3, -- rifle hits do 0.35 x 2.3 = 0.8 of body damage to the drone (was 0.35)
	Mass = 260,
	RespawnTime = 90, -- was 35
	Camera = { Distance = 24, Height = 6, Fov = 76, ZoomFov = 45, PivotY = 2 },
	Drive = {
		Kind = "Flight",
		MaxForward = 72,        -- 2026-11-20: was 88
		MaxReverse = 45, MaxStrafe = 55, MaxClimb = 45, -- climb / dive comes from where the mouse points
		Accel = 70, Brake = 90, ClimbAccel = 60,
		MinClearance = 6,       -- piloted: never lower than this above the ground under it
		MaxAltitude = 85,       -- world Y ceiling (under the perimeter walls' tops and the dropship)
		TakeoffHeight = 12,     -- lifts to this when a pilot boards a grounded drone
		TurnSpeed = 7,          -- how hard the airframe swings to face the camera (1/s)
		Tilt = 16,              -- deg the airframe leans into acceleration
		Stabilize = 1,
	},
	Seats = {
		{ Name = "Pilot", Role = "Driver", Pos = Vector3.new(0, 2.6, -1.2), Hidden = true },
	},
	Exits = { Vector3.new(9.5, 0, -1), Vector3.new(-9.5, 0, -1), Vector3.new(0, 0, -10), Vector3.new(0, 0, 9) },
	Weapon = {
		Kind = "MG", Id = "DroneGun", DisplayName = "TWIN PULSE GUNS",
		Controller = "Driver",
		YawSpeed = 360, PitchSpeed = 260, PitchMin = -50, PitchMax = 25, YawLimit = 14,
		RPM = 540, Damage = 7, VehicleMultiplier = 0.5, Spread = 1.3, MaxRange = 300, -- 2026-11-20: was 10 dmg / 0.6 spread / 520 range
		Falloff = { Start = 60, End = 180, Min = 0.5 }, -- full damage to 60 studs, half by 180
		Barrels = 2,            -- both barrels fire every shot: two lines of rounds
		Heat = { PerShot = 0.045, CoolRate = 0.35, CoolDelay = 0.5, Lock = 2.5 }, -- was 0.024 / 0.42 / 0.35 / 1.8
		TracerEvery = 1,
		-- 2026-11-20: homing REMOVED (it was a flying aimbot). Re-add Homing = { Cone, Range } to restore.
		Homing = nil,
	},
	RunOver = { MinSpeed = 1e9, KillSpeed = 1e9, Damage = 0 }, -- no ramming
	Visual = { Wheels = "Rotors", Dust = 0 },
}

-- ─── sound (Creator Store library audio + the game's own rifle report; ids checked 2026-11-11) ───
Config.Sounds = {
	Tank = {
		Engine = { Id = "rbxassetid://8213083943", Volume = 0.9, Idle = 0.8, Max = 1.25 },
		Tracks = { Id = "rbxassetid://123123630309030", Volume = 0.7 },
		Fire = { Id = "rbxassetid://131068121289461", Volume = 1.6, Speed = 1 },
	},
	APC = {
		Engine = { Id = "rbxassetid://80317022777602", Volume = 0.8, Idle = 0.55, Max = 0.95 },
		Fire = { Id = "rbxassetid://9118173739", Volume = 0.9, Speed = 0.68 },
	},
	Buggy = {
		Engine = { Id = "rbxassetid://107090777647557", Volume = 0.65, Idle = 0.75, Max = 1.35 },
		Fire = { Id = "rbxassetid://9118173739", Volume = 0.75, Speed = 0.82 },
	},
	Drone = {
		Engine = { Id = "rbxassetid://129509260471892", Volume = 0.55, Idle = 0.9, Max = 1.45 },
		Fire = { Id = "rbxassetid://9118173739", Volume = 0.6, Speed = 1.05 },
	},
	ShellImpact = { Id = "rbxassetid://18245316227", Volume = 1.6 },
	Destroyed = { Id = "rbxassetid://139900006476219", Volume = 2 },
	MetalHit = { "rbxassetid://98609496290942", "rbxassetid://110295421669790", "rbxassetid://93157546246483" },
}

-- damage states for client effects (fraction of max health)
Config.DamageStates = { Smoke = 0.5, Fire = 0.25 }

return Config
