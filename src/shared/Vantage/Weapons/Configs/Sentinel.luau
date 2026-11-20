--[[
	BR-07 SENTINEL — battle rifle. Three-round burst (each round its own server-validated shot),
	high damage per burst, controlled recoil, medium-to-long range, scoped precision ADS.
]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "BR-07 SENTINEL", ShortName = "SENTINEL", Class = "BATTLE RIFLE", Asset = "Sentinel",
	SpeedMultiplier = 0.97,
	MagazineSize = 35, ReserveAmmo = 115,
	RPM = 1170,                       -- cycle rate inside a burst
	Trigger = "Burst",
	Burst = { Count = 3, Cooldown = 0.26 },  -- seconds after the last round before the next burst
	MaxRange = 700,
	Damage = 24, HeadshotMultiplier = 1.75,  -- 72 per body burst; 3 bursts through a full shield
	FalloffStart = 220, FalloffEnd = 450, FalloffMinMultiplier = 0.85,
	ReloadTime = 2.3, EquipTime = 0.5,
	Spread = { PerShot = 0.14, MaxBloom = 0.8, Base = 0, Moving = 0.35, Air = 1.4, Slide = 0.6 },
	Recoil = {
		-- one learnable 3-step burst kick; the pattern restarts every burst (cooldown > reset time)
		Pattern = { { 0.42, 0.03 }, { 0.5, -0.04 }, { 0.58, 0.05 } },
		PatternResetTime = 0.26, RecoveryDelay = 0.08, RecoverySpeed = 8, PunchPitch = 0.35,
	},
	Viewmodel = { OffsetPosition = Vector3.new(0.44, -0.88, -0.92), KickBack = 0.085, KickPitch = 2.0 },
	Sounds = { -- 2026-11-17 handling identity: reload / equip pitched per weapon
		MagOut = { Speed = 0.92 }, MagIn = { Speed = 0.9, Volume = 0.9 }, Equip = { Speed = 0.95 },
		 Fire = { -- 2026-11-17 layered fire (crack / body / mechanism), tails trimmed on fast guns
			Region = NumberRange.new(0, 0.7), Layers = { { Id = "rbxassetid://9116361236", Region = NumberRange.new(0, 0.085), Volume = 0.28, Speed = 0.85 }, },  PitchMin = 0.86, PitchMax = 0.9, Volume = 0.7 }, FireThirdPerson = { Volume = 1.0 } },
	ADS = {
		-- BR-07 scope (2026-11-14): open view - the eye sits just in front of the front lens, so the
		-- scope body is behind the camera; ~1.6x zoom with the orange chevron projected along the bore
		FOV = 55, InTime = 0.22, OutTime = 0.15,
		SightDistance = 0.015, CompensateZoom = false,
		Sight = {
			Kind = "Lens",
			Reticle = { Style = "Chevron", Color = Color3.fromRGB(255, 150, 60), Size = 18, Thickness = 1.6, Dot = 2 },
			WindowInset = 2,
		},
		Transition = { Roll = -6, Pitch = -2.2, Yaw = 1.5, Dip = 0.012 },
		Settle = { Pitch = -0.6, Yaw = 0.2, Roll = 0.6 },
		MoveSpeedMultiplier = 0.74, SpreadMultiplier = 0.1, RecoilMultiplier = 0.75,
		KickMultiplier = 0.4, SwayMultiplier = 0.3, BobMultiplier = 0.15,
		Sensitivity = 0.65, CancelOnSlide = true,
	},
})
