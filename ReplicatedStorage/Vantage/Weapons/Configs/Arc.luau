--[[
	ER-04 ARC — energy rifle. Automatic cyan energy bolts (server-simulated projectiles), no
	magazine: sustained fire builds heat; at 100% the rifle overheats and locks until it vents.
	Heat drains after a short pause. R vents manually.
]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "ER-04 ARC", ShortName = "ARC", Class = "ENERGY RIFLE", Asset = "Arc",
	ClipSet = "Energy",
	MagazineSize = 0, ReserveAmmo = 0,         -- energy weapon: heat instead of ammo
	Energy = true,
	RPM = 780, Trigger = "Auto",
	Shot = "Projectile",
	Projectile = { Speed = 360, Lifetime = 1.6, Color = Color3.fromRGB(80, 235, 255), Size = 0.35 },
	Heat = { PerShot = 0.0382, CoolDelay = 0.35, CoolRate = 0.6, OverheatLock = 1.6, VentTime = 1.0 }, -- PerShot was 0.055: 20% more shots per heat bar (2026-11-11)
	MaxRange = 576,                            -- Speed * Lifetime
	Damage = 19, HeadshotMultiplier = 1.4, -- 17 -> 19 (balance pass 2026-11-17: 11 body shots, ~770 ms)
	FalloffStart = 300, FalloffEnd = 500, FalloffMinMultiplier = 0.85,
	ReloadTime = 1.0, EquipTime = 0.45,
	NoShells = true,
	Spread = { PerShot = 0.1, MaxBloom = 1.2, Base = 0.1, Moving = 0.35, Air = 1.2, Slide = 0.5 },
	Recoil = {
		Pattern = { { 0.18, 0.02 }, { 0.2, -0.03 }, { 0.22, 0.03 }, { 0.2, -0.02 } },
		RecoveryDelay = 0.12, RecoverySpeed = 7, PunchPitch = 0.15,
	},
	Viewmodel = { OffsetPosition = Vector3.new(0.42, -0.86, -0.92), KickBack = 0.04, KickPitch = 0.9 },
	Sounds = { -- 2026-11-17 handling identity: reload / equip pitched per weapon
		Equip = { Speed = 1.25, Volume = 0.35 },
		
		Fire = { -- 2026-11-17 layered fire (crack / body / mechanism), tails trimmed on fast guns
			Region = NumberRange.new(0, 0.3), Layers = { { Id = "rbxassetid://9116361236", Region = NumberRange.new(0, 0.085), Volume = 0.25, Speed = 1.9 } },  PitchMin = 1.6, PitchMax = 1.75, Volume = 0.42, MaxVoices = 3 },
		FireThirdPerson = { Volume = 0.7 },
		Vent = { Id = "rbxassetid://9116357621", Volume = 0.6, Speed = 0.6 },
		Overheat = { Id = "rbxassetid://72166668675269", Volume = 0.8, Speed = 0.7 },
	},
	ADS = { Mode = "Zoom", ZoomFOV = 68, FOV = 50, SightDistance = 0.7, Reticle = { Size = 24, Thickness = 2, Dot = 4, Color = Color3.fromRGB(80, 235, 255) } },
})
