--[[ SM-21 RIPTIDE — SMG (wave 1 crate gun, 2026-11-18). Fastest fire rate, shreds up close, falls off hard past 25 studs. ]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "SM-21 RIPTIDE", ShortName = "RIPTIDE", Class = "SMG", Asset = "Riptide",
	SpeedMultiplier = 1.06,
	MagazineSize = 30, ReserveAmmo = 120,
	RPM = 1000, Trigger = "Auto", Shot = "Hitscan", MaxRange = 300,
	Damage = 23, HeadshotMultiplier = 1.4,
	FalloffStart = 45, FalloffEnd = 110, FalloffMinMultiplier = 0.7, -- buffed 2026-11-20 (was 21 dmg, 25-70 x0.6, base spread 0.15)
	ReloadTime = 1.75, EquipTime = 0.35,
	Spread = { Base = 0.08, Moving = 0.2, Air = 0.8, Slide = 0.3 },
	Recoil = { Pattern = { { 0.2, 0.03 }, { 0.24, -0.04 }, { 0.26, 0.05 }, { 0.22, -0.05 }, { 0.2, 0.04 } }, RecoveryDelay = 0.1, RecoverySpeed = 8, PunchPitch = 0.18 },
	Viewmodel = { OffsetPosition = Vector3.new(0.4, -0.78, -0.95), KickBack = 0.05, KickPitch = 1.2 },
	Sounds = { Fire = { PitchMin = 1.12, PitchMax = 1.2, Volume = 0.5, MaxVoices = 3 }, MagOut = { Speed = 1.2 }, MagIn = { Speed = 1.2 }, Equip = { Speed = 1.3 } },
	ADS = { Mode = "Zoom", ZoomFOV = 72, FOV = 62 },
})