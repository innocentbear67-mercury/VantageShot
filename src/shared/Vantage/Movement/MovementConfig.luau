--!strict
--[[
	VANTAGE — MovementConfig
	Single source of truth for every movement / camera / anti-exploit parameter.
	Shared by client (feel) and server (validation), so the two never disagree.

	Units: studs, seconds, studs/second. Angles in degrees.
	Roblox default WalkSpeed is 16 for reference.
]]

local Config = {}

-- ─── Ground movement (automatic sprint — there is no walk) ────────────────
Config.RunSpeed = 24                -- default movement speed (always sprinting)
Config.GroundAcceleration = 130     -- studs/s² toward target speed (22 reached in ~0.17s)
Config.GroundDeceleration = 150     -- studs/s² when releasing input (stop in ~0.15s)
Config.TurnAcceleration = 220       -- studs/s² when reversing / changing direction (snappy strafes)
Config.OverspeedDeceleration = 38   -- studs/s² bleed when above target speed on ground (post-slide / post-hop momentum)

-- ─── Crouch ───────────────────────────────────────────────────────────────
Config.CrouchSpeed = 10
Config.CrouchToggle = false         -- false = hold to crouch, true = press to toggle
Config.CrouchHeightDrop = 1.1       -- how far the body / hitbox / camera lowers when crouched
Config.HeightTransitionSpeed = 16   -- exponential smoothing rate for crouch/slide height changes
Config.StandClearancePadding = 0.1  -- extra headroom required before standing up

-- ─── Jump ─────────────────────────────────────────────────────────────────
Config.JumpHeight = 6.6             -- apex height in studs (with workspace.Gravity)
Config.JumpBufferTime = 0.12        -- jump pressed this long before landing still fires
Config.CoyoteTime = 0.10            -- jump still allowed this long after walking off a ledge
Config.JumpCooldown = 0.18          -- minimum time between two jumps
Config.RequireJumpRepress = true    -- holding Space will NOT auto-bunnyhop
Config.LandingSpeedPenalty = 0.0    -- fraction of speed lost on hard landing (0 = none)
Config.HardLandingVelocity = 70     -- fall speed considered a hard landing (camera dip / penalty)

-- ─── Air movement ─────────────────────────────────────────────────────────
Config.AirAcceleration = 45         -- studs/s² of air steering
Config.AirMaxWishSpeed = 24         -- air control can never push you above this by itself (= RunSpeed)
Config.AirOverspeedDrag = 6         -- studs/s² bleed when carrying momentum above AirMaxWishSpeed

-- ─── Slide ────────────────────────────────────────────────────────────────
Config.SlideMinStartSpeed = 17      -- must be moving at least this fast to slide
Config.SlideStartBoost = 1.35       -- entry speed = current speed × boost
Config.SlideMaxSpeed = 31           -- hard cap on slide speed
Config.SlideFriction = 18           -- linear deceleration studs/s² during slide
Config.SlideFrictionRamp = 30       -- extra deceleration added per second of slide (gradual friction)
Config.SlideDuration = 0.85         -- maximum slide time
Config.SlideEndSpeed = 11           -- slide ends early below this speed
Config.SlideCooldown = 0.9          -- after a slide ends, time before another can start
Config.SlideSteerRate = 2.2         -- radians/s the slide direction can rotate toward input
Config.SlideHeightDrop = 1.6        -- body / camera drop while sliding
Config.SlideAirGraceTime = 0.15     -- leaving the ground longer than this ends the slide
Config.SlideRequiresRepress = true  -- must release & press crouch again to slide again

-- ─── First-person camera ──────────────────────────────────────────────────
Config.BaseFOV = 80
Config.SlideFOVBonus = 6            -- optional subtle FOV boost while sliding (0 to disable)
Config.SpeedFOVBonus = 2            -- FOV added when moving faster than RunSpeed (momentum)
Config.FOVSmoothing = 8
Config.StrafeTilt = 1.2             -- degrees of roll when strafing
Config.SlideTilt = 2.5              -- degrees of roll while sliding
Config.TiltSmoothing = 10
Config.LandingDipMax = 0.45         -- studs the camera dips on the hardest landing
Config.LandingDipRecover = 12       -- spring stiffness for the dip recovery
Config.HeadBobEnabled = true
Config.HeadBobAmplitude = 0.045     -- studs, deliberately tiny
Config.HeadBobFrequency = 1.9       -- cycles per second at RunSpeed

-- ─── Animation ────────────────────────────────────────────────────────────
Config.RunAnimReferenceSpeed = 16   -- speed at which the run animation plays at 1x
Config.AnimFadeTime = 0.15
Config.LandAnimTime = 0.22

-- ─── Input (keyboard/mouse first, gamepad ready) ──────────────────────────
Config.Keybinds = {
	Jump = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
	Crouch = { Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonR3 },
}
Config.CreateTouchCrouchButton = true -- mobile: adds a crouch button via ContextActionService

-- Writes Dbg* attributes on the local character every frame (testing only, keep false).
Config.DebugAttributes = false

-- ─── Server validation (anti-exploit) ─────────────────────────────────────
Config.Server = {
	SampleInterval = 0.25,          -- seconds between position samples
	SpeedTolerance = 1.25,          -- multiplier over the allowed speed (latency / physics jitter)
	SpeedFlatAllowance = 4,         -- extra studs/s always allowed
	MomentumGraceTime = 1.2,        -- after an approved slide, slide-level speed is allowed this long (slide-hops)
	MaxViolations = 3,              -- violations before the player is snapped back
	ViolationDecayTime = 4,         -- one violation is forgiven every N seconds
	JumpRiseAllowance = 3,          -- studs above JumpHeight allowed before flagging (step-ups, physics)
	SlideCooldownTolerance = 0.2,   -- latency forgiveness on slide cooldown
	TeleportDistance = 60,          -- a sample moving further than this counts as a teleport
	RemoteRateLimit = 20,           -- max state messages per second
}

return Config
