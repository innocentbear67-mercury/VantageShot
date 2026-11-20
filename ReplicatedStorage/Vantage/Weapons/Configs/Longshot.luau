--[[
	SR-88 LONGSHOT — bolt-action sniper. High damage, small magazine, high-magnification scope,
	headshot multiplier that kills through a full shield, slow bolt and reload, big recoil.
]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "SR-88 LONGSHOT", ShortName = "LONGSHOT", Class = "SNIPER RIFLE", Asset = "Longshot",
	ClipSet = "Sniper",
	SpeedMultiplier = 0.9,
	MagazineSize = 7, ReserveAmmo = 24,
	RPM = 60, Trigger = "Semi",
	Rechamber = { Time = 0.69, Clip = "Rechamber", Event = "Bolt" },
	MaxRange = 1200,
	Damage = 95, HeadshotMultiplier = 2.4, LimbMultiplier = 0.85,   -- 228 head: one shot through shield
	FalloffStart = 1000, FalloffEnd = 1200, FalloffMinMultiplier = 1,
	ReloadTime = 3.0, EquipTime = 0.6, UnequipTime = 0.35,
	Spread = { PerShot = 0, MaxBloom = 0, Base = 2.5, Moving = 2.0, Air = 4, Slide = 3 },          -- no-scope is a gamble
	Recoil = { Pattern = { { 3.2, 0.25 } }, RecoveryDelay = 0.12, RecoverySpeed = 4, PatternResetTime = 1, PunchPitch = 2.4, MaxVertical = 12 },
	Viewmodel = { OffsetPosition = Vector3.new(0.46, -0.92, -0.92), KickBack = 0.22, KickPitch = 7 },
	Sounds = { -- 2026-11-17 handling identity: reload / equip pitched per weapon
		MagOut = { Speed = 0.8 }, MagIn = { Speed = 0.78, Volume = 0.95 }, Equip = { Speed = 0.82, Volume = 0.45 }, Bolt = { Speed = 0.85, Volume = 0.7 },
		 Fire = { -- 2026-11-17 layered fire (crack / body / mechanism), tails trimmed on fast guns
			Layers = { { Id = "rbxassetid://9116361236", Region = NumberRange.new(0, 0.085), Volume = 0.4, Speed = 0.7 }, { Ids = { "rbxassetid://9118173739", "rbxassetid://9118173988" }, Region = NumberRange.new(0, 1.2), Volume = 0.4, Speed = 0.42 } },  PitchMin = 0.55, PitchMax = 0.6, Volume = 0.95, MaxVoices = 1 }, FireThirdPerson = { Volume = 1.2, RollOff = 600 } },
	ADS = {
		-- SR-88 scope (2026-11-14, Blender model): eyepiece radius 0.06, eye 0.4 behind it at FOV 13
		-- -> the glass fills ~80% of the screen height, then the scope view takes over.
		FOV = 13, InTime = 0.3, OutTime = 0.15,
		SightDistance = 0.4, CompensateZoom = false,
		SpreadMultiplier = 0, RecoilMultiplier = 0.7,
		MoveSpeedMultiplier = 0.65, Sensitivity = 0.32,
		Scope = { Kind = "Sniper", Tint = Color3.fromRGB(255, 255, 255), Size = 0.86 },
		Transition = { Roll = -5, Pitch = -2, Yaw = 1.2, Dip = 0.012 },
		Settle = { Pitch = -0.5, Yaw = 0.15, Roll = 0.5 },
	},
})
