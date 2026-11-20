--[[ BX-3 HELIX — beam rifle (wave 1 crate gun). Very fast low-damage pulses, no magazine: heat like the Arc. ]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "BX-3 HELIX", ShortName = "HELIX", Class = "BEAM RIFLE", Asset = "Helix",
	ClipSet = "Energy", Energy = true, NoShells = true,
	MagazineSize = 0, ReserveAmmo = 0,
	RPM = 1200, Trigger = "Auto", Shot = "Hitscan", MaxRange = 180,
	Heat = { PerShot = 0.0125, CoolDelay = 0.4, CoolRate = 0.5, OverheatLock = 1.8, VentTime = 1.0 }, -- ~4 s of beam per cell
	Beam = { Color = Color3.fromRGB(90, 190, 255), Width = 0.5 }, -- one continuous beam (WeaponEffects:BeamPulse), no tracers
	Damage = 10, HeadshotMultiplier = 1.25,
	FalloffStart = 80, FalloffEnd = 180, FalloffMinMultiplier = 0.7,
	ReloadTime = 1.8, EquipTime = 0.5,
	Spread = { Base = 0.05, Moving = 0.15, Air = 0.6, Slide = 0.3 },
	Recoil = { Pattern = { { 0.06, 0.01 }, { 0.06, -0.01 } }, PunchPitch = 0.05 },
	Viewmodel = { OffsetPosition = Vector3.new(0.42, -0.86, -0.92), KickBack = 0.015, KickPitch = 0.3 },
	Sounds = { Fire = { PitchMin = 2.0, PitchMax = 2.1, Volume = 0.3, MaxVoices = 3 }, Vent = { Id = "rbxassetid://9116357621", Volume = 0.6, Speed = 0.6 }, Overheat = { Id = "rbxassetid://72166668675269", Volume = 0.8, Speed = 0.7 } },
	ADS = { Mode = "Zoom", ZoomFOV = 70, FOV = 60 },
})