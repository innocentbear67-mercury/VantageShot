--[[ XB-7 QUILL — crossbow (wave 1 crate gun). One heavy bolt per draw: a body shot kills from full health. ]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "XB-7 QUILL", ShortName = "QUILL", Class = "CROSSBOW", Asset = "Quill",
	NoShells = true,
	MagazineSize = 1, ReserveAmmo = 12,
	RPM = 60, Trigger = "Semi", Shot = "Projectile",
	Projectile = { Speed = 260, Lifetime = 2.2, Gravity = 40, Color = Color3.fromRGB(120, 220, 255), Size = 0.22 }, -- ~3 studs of drop at 100 studs
	MaxRange = 572,
	Damage = 100, HeadshotMultiplier = 1.5,
	FalloffStart = 400, FalloffEnd = 572, FalloffMinMultiplier = 1,
	ReloadTime = 1.9, EquipTime = 0.5,
	Spread = { Base = 0, Moving = 0.6, Air = 2.0, Slide = 1.0 },
	Recoil = { Pattern = { { 0.9, 0 } }, PunchPitch = 0.6 },
	Viewmodel = { OffsetPosition = Vector3.new(0.44, -0.86, -0.92), KickBack = 0.09, KickPitch = 3 },
	Sounds = { Fire = { PitchMin = 1.5, PitchMax = 1.6, Volume = 0.45 }, MagIn = { Speed = 0.9 }, Bolt = { Speed = 0.8 } },
	ADS = { Mode = "Zoom", ZoomFOV = 55, FOV = 45, Sensitivity = 0.85 },
})