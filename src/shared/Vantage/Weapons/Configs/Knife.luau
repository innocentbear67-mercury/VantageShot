--[[
	Knife — melee: Combat Knife (Tripo mesh, fixed blade; the old VK-7 balisong asset is kept in
	ServerStorage.WeaponAssetKit.Replaced.Knife_Balisong and its clips as WeaponClips.Balisong)
]]
return {
	Id = "Knife",
	Kind = "Melee",
	DisplayName = "CK-3 Edge",
	ShortName = "KNIFE",
	Class = "COMBAT KNIFE",
	Asset = "Knife",
	SpeedMultiplier = 1.14,         -- 22 -> 25.1 studs/s; server validated

	EquipTime = 0.32,
	UnequipTime = 0.14,

	Primary = {                     -- left click: quick slash (alternates direction)
		Damage = 45,
		Range = 6.2,                -- studs from attacker root to victim body
		ConeAngle = 55,             -- half-angle around the aim direction
		WindUp = 0.07,              -- strike happens this long after the click
		Cooldown = 0.42,            -- between strikes (server enforced)
		Recovery = 0.3,
	},
	Secondary = {                   -- right click: heavy stab
		Damage = 80,
		BackstabDamage = 150,       -- from behind = elimination
		BackstabDot = 0.35,         -- victim facing away threshold
		Range = 5.2,
		ConeAngle = 40,
		WindUp = 0.2,
		Cooldown = 1.0,
		Recovery = 0.45,
	},
	InspectTime = 2.4,

	Viewmodel = {
		Scale = 0.5,
		-- right hand pose in camera space
		-- combat knife: blade raised ~34 deg toward the centre so it reads past the fist, flat to camera
		Offset = CFrame.new(0.4, -0.5, -1.15) * CFrame.Angles(math.rad(34.5), math.rad(11.6), math.rad(-7.4)),
		LeftOffset = CFrame.new(-0.72, -1.02, -0.98) * CFrame.Angles(math.rad(20), math.rad(18), math.rad(30)),
		SwayAmount = 1.1,
		SwayMax = 7,
		BobAmount = 0.04,           -- knife running is more energetic
		BobFrequency = 2.1,
		AirLift = 0.06,
		LandDip = 0.1,
		StrafeTilt = 4,
		Inertia = 0.0022,
		KickStiffness = 300,
		KickDamping = 24,
		KickRotStiffness = 260,
		KickRotDamping = 22,
	},

	Sounds = {
		Equip = { Id = "rbxassetid://9116357621", Volume = 0.3, StartAt = 0.03, Speed = 1.4 },
		-- PSE "Wood Whoosh Slicing Air Quick Swings 4" + a fast cloth whoosh (onsets measured: 67 / 50 ms)
		Swing = { Ids = { "rbxassetid://9120972321", "rbxassetid://111254855668531" }, Volume = 0.5, StartAt = 0.05, PitchMin = 0.95, PitchMax = 1.1 },
		HitBody = { Id = "rbxassetid://9116197520", Volume = 0.65 },   -- PSE Knife Stab 1 (instant onset)
		HitWorld = { Id = "rbxassetid://98609496290942", Volume = 0.35, StartAt = 0.03 },
		Flip = { Id = "rbxassetid://9116357355", Volume = 0.18, Speed = 2.2 },
	},

	ThirdPerson = {
		Scale = 0.9,                -- handle must be longer than an avatar fist is wide
		Hold = CFrame.new(0.55, -0.45, -0.85) * CFrame.Angles(math.rad(-10), math.rad(10), 0), -- right hand target in UpperTorso space
	},
}
