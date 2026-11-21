--[[ GL-4 HAVOC — grenade launcher (wave 1 crate gun). Four slow lobbed rounds per drum: 85 on a direct hit,
	line-of-sight blast damage around the impact (WeaponService splash), airburst at the end of the flight. ]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "GL-4 HAVOC", ShortName = "HAVOC", Class = "LAUNCHER", Asset = "Havoc",
	NoShells = true,
	SpeedMultiplier = 0.94,
	MagazineSize = 4, ReserveAmmo = 16,
	RPM = 90, Trigger = "Semi", Shot = "Projectile",
	Projectile = { Speed = 150, Lifetime = 2.0, Gravity = 70, Color = Color3.fromRGB(255, 150, 60), Size = 0.6,
		Splash = { Radius = 14, Inner = 3, Edge = 0.25, Scale = 0.9 } }, -- lobbed round; blast: 76 dmg within 3 studs, 19 at the 14-stud edge
	MaxRange = 300,
	Damage = 85, HeadshotMultiplier = 1.0,
	FalloffStart = 300, FalloffEnd = 300, FalloffMinMultiplier = 1,
	ReloadTime = 2.6, EquipTime = 0.6,
	Spread = { Base = 0, Moving = 0.5, Air = 1.5, Slide = 0.8 },
	Recoil = { Pattern = { { 1.8, 0.1 } }, PunchPitch = 1.0 },
	Viewmodel = { Scale = 0.52, OffsetPosition = Vector3.new(0.48, -0.92, -0.92), KickBack = 0.14, KickPitch = 5 },
	Sounds = { Fire = { PitchMin = 0.55, PitchMax = 0.6, Volume = 0.7 }, MagOut = { Speed = 0.9 }, MagIn = { Speed = 0.9 } },
	ADS = { Mode = "Zoom", ZoomFOV = 70, FOV = 62 },
})