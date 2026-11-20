--[[
	PX-9 SPECTRE — sidearm. Semi-automatic, fast weapon switching, moderate-to-high damage, small
	magazine, quick reload, close-to-medium range. Iron sights.
]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "PX-9 SPECTRE", ShortName = "SPECTRE", Class = "SIDEARM", Asset = "Spectre",
	ClipSet = "Pistol",
	SpeedMultiplier = 1.08,
	MagazineSize = 17, ReserveAmmo = 72,
	RPM = 546, Trigger = "Semi",
	MaxRange = 400,
	Damage = 30, HeadshotMultiplier = 1.7,
	FalloffStart = 70, FalloffEnd = 200, FalloffMinMultiplier = 0.7,
	ReloadTime = 1.35, EquipTime = 0.22, UnequipTime = 0.15,
	Spread = { PerShot = 0.35, MaxBloom = 1.6, Base = 0.15, Moving = 0.3, Air = 1.0, Slide = 0.5 },
	Recoil = {
		Pattern = { { 0.85, 0.05 }, { 0.9, -0.07 }, { 0.95, 0.08 }, { 0.9, -0.05 } },
		RecoveryDelay = 0.05, RecoverySpeed = 11, PatternResetTime = 0.4, PunchPitch = 0.6,
	},
	Viewmodel = {
		-- closer and higher than the rifles: a short sidearm otherwise disappears behind the hands
		OffsetPosition = Vector3.new(0.27, -0.4, -1.02), Converge = 6, Roll = -3,
		KickBack = 0.06, KickRise = 0.05, KickPitch = 4.5, BobAmount = 0.026, SwayAmount = 1.0,
	},
	Sounds = { -- 2026-11-17 handling identity: reload / equip pitched per weapon
		MagOut = { Speed = 1.3 }, MagIn = { Speed = 1.35, Volume = 0.8 }, Equip = { Speed = 1.35, Volume = 0.3 },
		 Fire = { -- 2026-11-17 layered fire (crack / body / mechanism), tails trimmed on fast guns
			Region = NumberRange.new(0, 0.4), Layers = { { Id = "rbxassetid://9116361236", Region = NumberRange.new(0, 0.085), Volume = 0.45, Speed = 1.05 }, },  PitchMin = 1.14, PitchMax = 1.22, Volume = 0.55 } },
	ADS = { Mode = "Zoom", ZoomFOV = 70, -- 2026-11-14 hip-fire: right-click = small zoom, the gun stays at the hip (no sight)
		-- PX-9 three-dot iron sights (2026-11-14, Blender model): rear notch floor and front dot sit
		-- on the ADSPoint line, so aiming lines them up for real. Mild 1.3x zoom.
		FOV = 66, InTime = 0.13, OutTime = 0.1,
		SightDistance = 0.36,
		Sight = { Kind = "Iron" },
		Transition = { Roll = -4, Pitch = -1.5, Yaw = 1.0, Dip = 0.008 },
		Settle = { Pitch = -0.5, Yaw = 0.15, Roll = 0.5 },
		SpreadMultiplier = 0.4, KickMultiplier = 0.55, SwayMultiplier = 0.35, BobMultiplier = 0.2,
		CancelOnSlide = true,
	},
	ThirdPerson = { Hold = CFrame.new(0.5, 0.55, -1.55), BladeAngle = 20 },
})
