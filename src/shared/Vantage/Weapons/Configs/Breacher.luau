--[[
	SG-12 BREACHER — pump shotgun. Pellet spread with individual pellet hit detection (damage
	summed per target on the server), steep falloff, slow pump cycle, shell-by-shell reload.
]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "SG-12 BREACHER", ShortName = "BREACHER", Class = "SHOTGUN", Asset = "Breacher",
	ClipSet = "Shotgun",
	SpeedMultiplier = 0.95,
	MagazineSize = 8, ReserveAmmo = 36,
	RPM = 94, Trigger = "Semi",
	Shot = "Pellet",
	Pellet = { Count = 9, Spread = 4.2 },        -- pellets per shell, cone half-angle (degrees)
	Rechamber = { Time = 0.42, Clip = "Rechamber", Event = "Pump" },
	MaxRange = 140,
	Damage = 14, HeadshotMultiplier = 1.3,      -- per pellet: 126 point-blank body
	FalloffStart = 14, FalloffEnd = 45, FalloffMinMultiplier = 0.15,
	ReloadMode = "Shell",
	Shell = { Start = 0.35, Each = 0.48, Finish = 0.4 },   -- open, per shell, close (seconds)
	ReloadTime = 3.0,                           -- (HUD estimate; shells are timed individually)
	EquipTime = 0.5,
	Spread = { PerShot = 0.7, MaxBloom = 1.4, BloomRecover = 3, Base = 0, Moving = 0.3, Air = 0.8, Slide = 0.4 },
	Recoil = { Pattern = { { 2.4, 0.3 } }, RecoveryDelay = 0.1, RecoverySpeed = 5, PatternResetTime = 0.5, PunchPitch = 1.4, MaxVertical = 12 },
	Viewmodel = { OffsetPosition = Vector3.new(0.44, -0.88, -0.9), KickBack = 0.18, KickRise = 0.04, KickPitch = 6 },
	Sounds = { -- 2026-11-17 handling identity: reload / equip pitched per weapon
		Equip = { Speed = 0.8, Volume = 0.45 },
		
		Fire = { -- 2026-11-17 layered fire (crack / body / mechanism), tails trimmed on fast guns
			Layers = { { Ids = { "rbxassetid://9118173739", "rbxassetid://9118173988" }, Region = NumberRange.new(0, 0.9), Volume = 0.45, Speed = 0.45 } },  PitchMin = 0.62, PitchMax = 0.68, Volume = 0.85, MaxVoices = 1 },
		FireThirdPerson = { Volume = 1.1 },
		Pump = { Id = "rbxassetid://9116357355", Volume = 0.6, Speed = 0.8 },
		ShellIn = { Id = "rbxassetid://9113104208", Volume = 0.5, Speed = 1.5 },
	},
	ADS = { Mode = "Zoom", ZoomFOV = 72, -- 2026-11-14 hip-fire: right-click = small zoom, the gun stays at the hip (no sight)
		-- SG-12 ghost ring (2026-11-14, Blender model): look through the rear aperture onto the
		-- glowing front bead on the sight fin. Close eye relief so the ring frames the target.
		FOV = 66, InTime = 0.18, OutTime = 0.13,
		SightDistance = 0.16,
		Sight = { Kind = "Iron" },
		Transition = { Roll = -6, Pitch = -2.5, Yaw = 1.6, Dip = 0.016 },
		Settle = { Pitch = -0.9, Yaw = 0.3, Roll = 0.9 },
		MoveSpeedMultiplier = 0.8, SpreadMultiplier = 0.85, KickMultiplier = 0.6, SwayMultiplier = 0.3,
		BobMultiplier = 0.2, CancelOnSlide = true,
	},
})
