--[[ LM-60 BULWARK — LMG (wave 1 crate gun). Rotary barrels: a 100-round belt, heavy and slow to handle, holds a lane. ]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "LM-60 BULWARK", ShortName = "BULWARK", Class = "LMG", Asset = "Bulwark",
	SpeedMultiplier = 0.88,
	MagazineSize = 100, ReserveAmmo = 200,
	RPM = 800, Trigger = "Auto", Shot = "Hitscan", MaxRange = 500,
	Damage = 27, HeadshotMultiplier = 1.4, -- buffed 2026-11-20 (was 22 dmg / 700 RPM / 3.2 s reload / moving spread 0.5)
	FalloffStart = 120, FalloffEnd = 300, FalloffMinMultiplier = 0.8,
	ReloadTime = 2.9, EquipTime = 0.7, UnequipTime = 0.4,
	Spread = { Base = 0.1, Moving = 0.35, Air = 1.6, Slide = 0.8 },
	Recoil = { Pattern = { { 0.3, 0.02 }, { 0.34, 0.06 }, { 0.3, -0.05 }, { 0.26, 0.04 }, { 0.22, -0.06 }, { 0.2, 0.05 } }, MaxVertical = 7, RecoveryDelay = 0.14, PunchPitch = 0.25 },
	Viewmodel = { Scale = 0.5, OffsetPosition = Vector3.new(0.5, -0.95, -0.92), KickBack = 0.06, KickPitch = 1.3, SwayAmount = 1.2, Inertia = 0.0026 },
	Sounds = { Fire = { PitchMin = 0.82, PitchMax = 0.88, Volume = 0.68 }, MagOut = { Speed = 0.85 }, MagIn = { Speed = 0.85, Volume = 0.9 }, Equip = { Speed = 0.85 } },
	ADS = { Mode = "Zoom", ZoomFOV = 70, FOV = 60, MoveSpeedMultiplier = 0.7 },
})