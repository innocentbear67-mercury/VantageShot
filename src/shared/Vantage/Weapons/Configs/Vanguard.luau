--[[
	VX-01 VANGUARD — assault rifle (quality benchmark)
	Fully automatic, balanced damage / fire rate, 30-round magazine, moderate learnable recoil,
	close-to-medium range. Units: studs, seconds, degrees, damage in health points.
]]
return {
	Id = "Vanguard",
	Kind = "Gun",
	DisplayName = "VX-01 VANGUARD",
	ShortName = "VANGUARD",         -- HUD slot strip
	Class = "ASSAULT RIFLE",
	Asset = "Vanguard",                -- ReplicatedStorage.Vantage.Weapons.Assets.Vanguard
	SpeedMultiplier = 1.0,          -- movement speed while held (server validated)

	-- Ammo
	MagazineSize = 36, -- 43 -> 36 (balance pass 2026-11-17: the Vanguard had no real weakness)
	ReserveAmmo = 108,

	-- Fire
	RPM = 845,
	Trigger = "Auto",               -- Auto | Semi | Burst   (Automatic is derived from this by WeaponConfig)
	Shot = "Hitscan",               -- Hitscan | Pellet | Projectile
	MaxRange = 500,
	FireInputBuffer = 0.12,         -- a click this close before the next allowed shot still fires
	ReloadCancelByFire = true,      -- firing with ammo left cancels a reload before the new mag seats

	-- Damage
	Damage = 25,                    -- body
	HeadshotMultiplier = 1.5,
	LimbMultiplier = 1.0,           -- arms / legs (1 = same as body)
	FalloffStart = 140,             -- studs
	FalloffEnd = 320,
	FalloffMinMultiplier = 0.8,     -- 25 dmg up to 140 studs, easing to 20 dmg at 320+

	-- Timings
	ReloadTime = 2.0,               -- the reload clip (and its MagIn refill marker at 67.5%) scales to this
	EquipTime = 0.45,
	UnequipTime = 0.3,

	-- Movement inaccuracy only (degrees, cone half-angle). There is NO per-shot bloom:
	-- consecutive shots are governed purely by the deterministic recoil pattern below.
	Spread = {
		Base = 0,
		Moving = 0.25,              -- at full RunSpeed (run-and-gun stays viable)
		Air = 1.1,
		Crouch = 0,
		Slide = 0.45,
	},

	-- Camera recoil: a FIXED, learnable pattern (degrees per shot: {up, right}).
	-- Applied as a recovering offset on top of the camera; bullets follow it exactly.
	-- Shape: tight vertical start -> climb with slight right drift -> sway left -> sway right -> settle.
	Recoil = {
		Pattern = {
			{ 0.26, 0.00 }, { 0.38, 0.02 }, { 0.46, 0.04 }, { 0.50, 0.06 }, { 0.50, 0.08 },
			{ 0.48, 0.10 }, { 0.45, 0.10 }, { 0.42, 0.08 }, { 0.36, -0.06 }, { 0.32, -0.12 },
			{ 0.28, -0.16 }, { 0.26, -0.18 }, { 0.24, -0.16 }, { 0.22, -0.12 }, { 0.20, 0.04 },
			{ 0.19, 0.12 }, { 0.18, 0.16 }, { 0.17, 0.18 }, { 0.16, 0.14 }, { 0.15, 0.08 },
			{ 0.14, -0.08 }, { 0.13, -0.12 }, { 0.12, -0.12 }, { 0.12, -0.08 }, { 0.11, 0.04 },
			{ 0.11, 0.10 }, { 0.10, 0.12 }, { 0.10, 0.08 }, { 0.10, -0.04 }, { 0.10, -0.08 },
		},
		Scale = 1.0,                -- multiply the whole pattern
		MaxVertical = 9,            -- safety caps (degrees of accumulated offset)
		MaxHorizontal = 3,
		Snap = 20,                  -- how fast the camera reaches the kick target (per second)
		RecoveryDelay = 0.13,       -- recovery waits this long after a shot (> shot interval: no fighting mid-spray)
		RecoverySpeed = 6.5,        -- exponential return rate once recovering
		PatternResetTime = 0.28,    -- pause longer than this restarts the pattern at shot 1
		PunchPitch = 0.3,           -- per-shot camera punch (eases in, scaled down with zoom)
		PunchDecay = 30,
	},

	-- Viewmodel feel
	Viewmodel = {
		Scale = 0.6,                -- viewmodel render scale (keeps the gun to the lower-right third)
		-- grip pose in camera space: right of centre and low, muzzle canted in toward the crosshair and
		-- slightly up so the stock drops out of view bottom-right and the receiver side shows
		-- rotation solved so the bore line converges on the crosshair 5 studs out (stays pointed at it)
		Offset = CFrame.new(0.44, -0.86, -0.9) * CFrame.Angles(math.rad(6.97), math.rad(6.60), math.rad(-6.80)),
		CrouchOffset = CFrame.new(-0.04, -0.03, 0.04) * CFrame.Angles(0, 0, math.rad(-4)),
		SlideOffset = CFrame.new(-0.07, -0.04, 0.06) * CFrame.Angles(math.rad(2), 0, math.rad(-12)),
		FireStance = CFrame.new(-0.025, 0.018, 0.035) * CFrame.Angles(math.rad(0.8), math.rad(1.2), 0), -- shouldered while firing
		FireStanceIn = 22,          -- blend rates (per second)
		FireStanceOut = 6,
		-- per-shot kick (scaled by that shot's pattern step so weapon and camera agree)
		KickBack = 0.075,           -- studs
		KickRise = 0.018,
		KickPitch = 1.7,            -- degrees at a 0.45 deg pattern step
		KickYaw = 2.2,              -- degrees of gun yaw per degree of horizontal pattern step
		KickRoll = 0.7,             -- alternating ± degrees (deterministic)
		KickStiffness = 340,
		KickDamping = 27,
		KickRotStiffness = 280,
		KickRotDamping = 23,
		SwayAmount = 0.9,           -- rotation lag from mouse look
		SwayMax = 6,                -- degrees
		FireSwayFactor = 0.45,      -- sway multiplier while firing (steadier)
		StrafeTilt = 3.2,           -- degrees of roll at full strafe speed
		Inertia = 0.0018,           -- studs of lag per stud/s^2 of acceleration
		BobAmount = 0.022,
		BobFrequency = 1.9,         -- cycles per second at RunSpeed
		AirLift = 0.045,
		LandDip = 0.09,
		WallPushback = 0.3,         -- max studs pulled back near walls (gun also lowers)
	},

	-- Sounds. Every id was measured with the Audio API (onset / envelope); StartAt skips
	-- silent lead-ins so nothing plays late. ProSoundEffects = Roblox-licensed library.
	Sounds = { -- 2026-11-17 handling identity: reload / equip pitched per weapon
		MagOut = { Speed = 1.0 }, MagIn = { Speed = 1.0, Volume = 0.85 }, Equip = { Speed = 1.05 },
		
		Fire = { -- 2026-11-17 layered fire (crack / body / mechanism), tails trimmed on fast guns
			Region = NumberRange.new(0, 0.55), Layers = { { Id = "rbxassetid://9116361236", Region = NumberRange.new(0, 0.085), Volume = 0.32, Speed = 0.95 }, }, 
			Ids = { -- ProSoundEffects "Rifle Single Shots" 1/3/4/8: instant transient, natural tail
				"rbxassetid://9118173739", "rbxassetid://9118173988",
				"rbxassetid://9118173992", "rbxassetid://9118174539",
			},
			Volume = 0.62, PitchMin = 0.96, PitchMax = 1.04,
			MaxVoices = 2,          -- older shots fade out fast; the last shot rings out as the tail
			CutFade = 0.07,
		},
		FireThirdPerson = {
			Ids = { "rbxassetid://9118173739", "rbxassetid://9118173988", "rbxassetid://9118173992", "rbxassetid://9118174539" },
			Volume = 0.9, RollOff = 300, MaxVoices = 2, CutFade = 0.08,
		},
		MagOut = { Id = "rbxassetid://9113104337", Volume = 0.6 },   -- PSE Ammo Magazine 3
		MagIn = { Id = "rbxassetid://9113104208", Volume = 0.75 },   -- PSE Ammo Magazine 2
		Bolt = { Id = "rbxassetid://9116357355", Volume = 0.55 },    -- PSE Machine Gun Bolt 2
		Empty = { Id = "rbxassetid://72166668675269", Volume = 0.7 },
		Equip = { Id = "rbxassetid://9116357621", Volume = 0.35, StartAt = 0.03 }, -- PSE Machine Gun Bolt 4
		Impact = {
			Concrete = { Ids = { "rbxassetid://131554175554758", "rbxassetid://85805517776968" }, Volume = 0.25 },
			Metal = { Ids = { "rbxassetid://98609496290942", "rbxassetid://110295421669790" }, Volume = 0.25, StartAt = 0.03 },
			Glass = { Ids = { "rbxassetid://116374735080767", "rbxassetid://99255639682760" }, Volume = 0.22 },
			Body = { Ids = { "rbxassetid://9113524237" }, Volume = 0.3 },   -- PSE Body Impact 2
			Ricochet = { Ids = { "rbxassetid://9118168612", "rbxassetid://9118168610" }, Volume = 0.3, StartAt = 0.19, Chance = 0.18 },
			RollOff = 110,
		},
		-- confirmation cues are layered so each is clearly distinct
		Hit = { Layers = { { Id = "rbxassetid://138148057831879", Volume = 0.55 } } },
		Headshot = { Layers = {
			{ Id = "rbxassetid://138148057831879", Volume = 0.5, Speed = 1.22 },
			{ Id = "rbxassetid://137096881472307", Volume = 0.55, StartAt = 0.06 },
		} },
		Kill = { Layers = {
			{ Id = "rbxassetid://138148057831879", Volume = 0.6, Speed = 0.8 },
			{ Id = "rbxassetid://137096881472307", Volume = 0.45, Speed = 0.78, StartAt = 0.06 },
			{ Id = "rbxassetid://9126073318", Volume = 0.9, StartAt = 0.11 },  -- PSE synth sparkle tail
		} },
	},

	-- Aim down sights (per weapon so each future gun can zoom differently)
	ADS = { Mode = "Zoom", ZoomFOV = 70, -- 2026-11-14 hip-fire: right-click = small zoom, the gun stays at the hip (no sight)
		-- 2026-11-14 ADS rebuild: sight-anchored pose (see Viewmodel header)
		FOV = 60,                   -- fully aimed camera FOV at the 80 base: ~1.45x, a red-dot zoom (scales with the FOV setting)
		InTime = 0.2,               -- ease-out: ~80% aimed in half this time
		OutTime = 0.15,
		-- eye relief: camera-to-sight distance at the hip-equivalent FOV (the gun keeps this
		-- on-screen size at every zoom). The integrated visor window then fills ~1/5 of the screen.
		SightDistance = 0.25,
		-- collimated holo: the reticle is projected along the sight axis, clipped to the real window
		Sight = {
			Kind = "Holo",
			Reticle = { Style = "RingDot", Color = Color3.fromRGB(90, 230, 255), Size = 15, Thickness = 1.6, Dot = 2.6 },
		},
		-- swing into the shoulder: peaks mid-transition (degrees / studs), zero at hip and aimed
		Transition = { Roll = -7, Pitch = -2.5, Yaw = 1.8, Dip = 0.014 },
		Settle = { Pitch = -0.8, Yaw = 0.25, Roll = 0.8 },
		MoveSpeedMultiplier = 0.78, -- movement speed while aiming (client-side slow-down only)
		SpreadMultiplier = 0.35,    -- movement inaccuracy while aimed
		RecoilMultiplier = 0.85,    -- camera recoil pattern scale while aimed
		KickMultiplier = 0.45,      -- weapon model kick while aimed (keeps the sight on target)
		SwayMultiplier = 0.25,
		BobMultiplier = 0.15,
		CancelOnSlide = true,       -- sliding (the sprint action) drops ADS
	},

	-- Animation asset IDs for a RIGGED viewmodel (Assets.Vanguard_ViewmodelRig with an
	-- AnimationController). Empty = the built-in procedural animation is used.
	Animations = {
		Idle = "", Equip = "", Unequip = "", Fire = "", Reload = "", Run = "",
		Jump = "", Land = "", Crouch = "", ADS = "",
	},

	-- Third person (what other players see). The rifle is attached to the UpperTorso with a
	-- Motor6D; both arms reach its grips with two-bone IK; the upper body blades ~35 deg
	-- (real rifle stance) so the support hand reaches the handguard naturally.
	ThirdPerson = {
		-- Sized against R15 proportions: at this scale + hold the butt sits on the front of the
		-- (bladed) right shoulder, the right hand reaches the pistol grip and the left hand the
		-- rear of the handguard (SupportTP) — no stretching, no stock through the torso.
		Scale = 0.8,
		-- gun Body pose in the (un-bladed) UpperTorso aim frame
		Hold = CFrame.new(0.65, 0.45, -1.22),
		BladeAngle = 45,            -- upper-body yaw (deg) while holding the rifle (left shoulder forward)
		AimPivot = Vector3.new(0.65, 0.45, -0.1), -- torso-space pivot the gun pitches around (the stock)
		WaistPitchShare = 0.35,     -- fraction of aim pitch taken by the waist (rest by the arms/gun)
		ADSRaise = CFrame.new(-0.3, 0.38, 0.05), -- shouldered + cheek weld while aiming
	},
}
