--[[ HC-50 VERDICT — hand cannon (wave 1 crate gun). Six rounds, two-shot headshot / three-shot body, punishing to miss. ]]
local Base = require(script.Parent.Parent.ConfigBase)
return Base.Gun({
	DisplayName = "HC-50 VERDICT", ShortName = "VERDICT", Class = "HAND CANNON", Asset = "Verdict",
	ClipSet = "Pistol", NoShells = true, -- the revolver dumps its empties in the reload
	SpeedMultiplier = 1.05,
	MagazineSize = 6, ReserveAmmo = 36,
	RPM = 140, Trigger = "Semi", Shot = "Hitscan", MaxRange = 500,
	Damage = 45, HeadshotMultiplier = 1.6,
	FalloffStart = 70, FalloffEnd = 200, FalloffMinMultiplier = 0.75,
	ReloadTime = 2.3, EquipTime = 0.35,
	Spread = { Base = 0, Moving = 0.35, Air = 1.4, Slide = 0.5 },
	Recoil = { Pattern = { { 1.6, 0.1 } }, MaxVertical = 6, RecoveryDelay = 0.12, RecoverySpeed = 7, PunchPitch = 1.2 },
	Viewmodel = { OffsetPosition = Vector3.new(0.27, -0.4, -1.02), Converge = 6, Roll = -3, KickBack = 0.1, KickRise = 0.09, KickPitch = 9, BobAmount = 0.026 },
	Sounds = { Fire = { PitchMin = 0.7, PitchMax = 0.76, Volume = 0.75, MaxVoices = 2 }, FireThirdPerson = { Volume = 1.1, RollOff = 420 }, Equip = { Speed = 1.2 } },
	ADS = { Mode = "Zoom", ZoomFOV = 70, FOV = 60 },
	ThirdPerson = { Hold = CFrame.new(0.5, 0.55, -1.55), BladeAngle = 20 },
})