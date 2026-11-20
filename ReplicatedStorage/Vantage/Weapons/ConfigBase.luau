--[[
	VANTAGE — ConfigBase (shared)
	Shared template for gun configs: each module in Weapons.Configs calls ConfigBase.Gun{...} with
	only what makes that weapon distinct; everything else (feel, sounds, ADS defaults, third person)
	comes from here and is deep-merged. Tables merge recursively; arrays (Pattern, Ids) replace.
]]
local ConfigBase = {}

local function isArray(t)
	return type(t) == "table" and #t > 0
end

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = deepCopy(v)
	end
	return c
end

local function merge(into, from)
	for k, v in from do
		if type(v) == "table" and type(into[k]) == "table" and not isArray(v) and not isArray(into[k]) then
			merge(into[k], v)
		else
			into[k] = deepCopy(v)
		end
	end
	return into
end
ConfigBase.Merge = merge

local RIFLE_FIRE = { "rbxassetid://9118173739", "rbxassetid://9118173988", "rbxassetid://9118173992", "rbxassetid://9118174539" }

ConfigBase.Template = {
	Kind = "Gun",
	SpeedMultiplier = 1.0,
	MagazineSize = 36,
	ReserveAmmo = 90,
	RPM = 600,
	Trigger = "Semi",
	Shot = "Hitscan",
	MaxRange = 500,
	FireInputBuffer = 0.12,
	ReloadCancelByFire = true,
	Damage = 25,
	HeadshotMultiplier = 1.5,
	LimbMultiplier = 1.0,
	FalloffStart = 140,
	FalloffEnd = 320,
	FalloffMinMultiplier = 1.0,
	ReloadTime = 2.0,
	EquipTime = 0.45,
	UnequipTime = 0.3,
	Spread = { Base = 0, Moving = 0.25, Air = 1.1, Crouch = 0, Slide = 0.45 },
	Recoil = {
		Pattern = { { 0.4, 0 } },
		Scale = 1.0,
		MaxVertical = 9,
		MaxHorizontal = 3,
		Snap = 20,
		RecoveryDelay = 0.13,
		RecoverySpeed = 6.5,
		PatternResetTime = 0.28,
		PunchPitch = 0.3,
		PunchDecay = 30,
	},
	Viewmodel = {
		Scale = 0.6,
		-- grip position in camera space; the rotation is solved so the bore line meets the crosshair
		-- Converge studs out (Viewmodel.new), with this roll
		OffsetPosition = Vector3.new(0.44, -0.86, -0.9),
		Converge = 5,
		Roll = -6.8,
		CrouchOffset = CFrame.new(-0.04, -0.03, 0.04) * CFrame.Angles(0, 0, math.rad(-4)),
		SlideOffset = CFrame.new(-0.07, -0.04, 0.06) * CFrame.Angles(math.rad(2), 0, math.rad(-12)),
		FireStance = CFrame.new(-0.025, 0.018, 0.035) * CFrame.Angles(math.rad(0.8), math.rad(1.2), 0),
		FireStanceIn = 22,
		FireStanceOut = 6,
		KickBack = 0.075,
		KickRise = 0.018,
		KickPitch = 1.7,
		KickYaw = 2.2,
		KickRoll = 0.7,
		KickStiffness = 340,
		KickDamping = 27,
		KickRotStiffness = 280,
		KickRotDamping = 23,
		SwayAmount = 0.9,
		SwayMax = 6,
		FireSwayFactor = 0.45,
		StrafeTilt = 3.2,
		Inertia = 0.0018,
		BobAmount = 0.022,
		BobFrequency = 1.9,
		AirLift = 0.045,
		LandDip = 0.09,
		WallPushback = 0.3,
	},
	Sounds = {
		Fire = { Ids = RIFLE_FIRE, Volume = 0.62, PitchMin = 0.96, PitchMax = 1.04, MaxVoices = 2, CutFade = 0.07 },
		FireThirdPerson = { Ids = RIFLE_FIRE, Volume = 0.9, RollOff = 300, MaxVoices = 2, CutFade = 0.08 },
		MagOut = { Id = "rbxassetid://9113104337", Volume = 0.6 },
		MagIn = { Id = "rbxassetid://9113104208", Volume = 0.75 },
		Bolt = { Id = "rbxassetid://9116357355", Volume = 0.55 },
		Empty = { Id = "rbxassetid://72166668675269", Volume = 0.7 },
		Equip = { Id = "rbxassetid://9116357621", Volume = 0.35, StartAt = 0.03 },
	},
	ADS = {
		FOV = 55,
		InTime = 0.17,
		OutTime = 0.13,
		SightDistance = 0.6,
		Reticle = { Color = Color3.fromRGB(90, 230, 255), Size = 18, Thickness = 2, Dot = 4 },
		MoveSpeedMultiplier = 0.78,
		SpreadMultiplier = 0.35,
		RecoilMultiplier = 0.85,
		KickMultiplier = 0.45,
		SwayMultiplier = 0.25,
		BobMultiplier = 0.15,
		Sensitivity = 1.0,          -- extra mouse sensitivity multiplier while fully aimed (scopes < 1)
		CancelOnSlide = true,
	},
	Animations = {},
	ThirdPerson = {
		Scale = 0.8,
		Hold = CFrame.new(0.65, 0.45, -1.22),
		BladeAngle = 45,
		AimPivot = Vector3.new(0.65, 0.45, -0.1),
		WaistPitchShare = 0.35,
		ADSRaise = CFrame.new(-0.3, 0.38, 0.05),
	},
}

function ConfigBase.Gun(overrides)
	return merge(deepCopy(ConfigBase.Template), overrides)
end

return ConfigBase
