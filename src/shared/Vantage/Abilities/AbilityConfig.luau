--!strict
--[[
	VANTAGE — AbilityConfig
	Single source of truth for the suit's ability: the GRAPPLE (Phase Dash / High Jump / Pulse Scan
	were removed 2026-11-10; their effect code is still in AbilityFX, unused). Shared by client
	(feel, HUD) and server (cooldown, validation), so the two never disagree.

	Units: studs, seconds, studs/second.
]]

local Config = {}

-- "Grenade" is display-only here (visor tile, menu card): its rules live in Vantage.Grenade.GrenadeConfig
Config.Order = { "Grapple", "Grenade" }

Config.Abilities = {
	Grapple = {
		Name = "GRAPPLE",
		Icon = "rbxassetid://139156493311912",
		Keys = { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 },
		KeyLabel = "E",
		Cooldown = 2.5,          -- 2026-11-19: counts from when you LET GO (was 3.5 from firing). Each hook scales it (EquipmentCatalog)
		ActiveTime = 1.2,        -- HUD "active" highlight
		MissCooldown = 0.7,      -- firing at nothing / an invalid surface
		Range = 220,             -- longest shot (110 -> 220, user 2026-11-11)
		MinRange = 7,            -- closer than this there is nothing to pull to
		ProjectileSpeed = 340,   -- the hook's flight (110 studs in about a third of a second)
		PullAccel = 235,         -- acceleration along the cable (stronger yank, 2026-11-12)
		MaxSpeed = 105,          -- top speed on the cable
		SteerAccel = 42,         -- how hard the move keys bend the path
		SideDamp = 1.7,          -- per second: sideways speed bleeds off so you home in, not orbit
		ArriveDistance = 6,      -- this close to the hook the cable lets go by itself
		ArriveHop = 26,          -- upward speed given on arrival (pops you onto the ledge)
		ArriveKeep = 0.75,       -- share of momentum kept when the cable lets go at the hook (was 0.55)
		BrakeBase = 42,          -- near the hook the pull caps at BrakeBase + dist*BrakePerStud (was 18 + 3.2/stud)
		BrakePerStud = 4,
		ReleaseBoost = 1.12,     -- letting go mid-pull flings you: momentum x this (2026-11-12)
		MaxTime = 5,             -- longest pull (3.2 -> 5 so a full 220-stud pull can arrive: ~3.1 s at top speed)
		StuckTime = 0.45,        -- blocked this long (speed below StuckSpeed) and the cable lets go
		StuckSpeed = 5,
		ReleaseMaxSpeed = 82,    -- horizontal momentum kept when you let go (was 44)
		ReleaseMaxUp = 88,       -- upward speed kept when you let go: pull up + release = launch
		FloatTime = 2.4,         -- after the cable lets go: low-gravity hang (Halo-style), fades out over this time
		FloatLift = 0.65,        -- share of gravity cancelled at the start of the hang (0.65 = 35 percent gravity)
		ExemptTail = 0.35,       -- 2026-11-19: short blanket grace at let-go; the flight after it is checked ballistically
		MomentumTime = 3.5,      -- MovementValidator.Momentum: release speed allowed for 1 s, then fades to normal by this time
		LeashSlack = 26,         -- server: further than start distance + this from the hook = not a grapple
	},
	-- VX-G1 frag (2026-11-11). HUD fields only; Cooldown is copied from GrenadeConfig below.
	Grenade = {
		Name = "FRAG GRENADE",
		KeyLabel = "LMB+RMB",
		Cooldown = 20,
		ActiveTime = 0.6,
	},
}
do
	local ok, G = pcall(function()
		return require(script.Parent.Parent:WaitForChild("Grenade"):WaitForChild("GrenadeConfig"))
	end)
	if ok and G then
		Config.Abilities.Grenade.Cooldown = G.Cooldown
	end
end

Config.Colors = {
	Cyan = Color3.fromRGB(60, 170, 255),
	Hot = Color3.fromRGB(191, 230, 255),
	Enemy = Color3.fromRGB(255, 70, 80),
	Gold = Color3.fromRGB(226, 172, 62),
	GoldLight = Color3.fromRGB(255, 228, 150),
	Panel = Color3.fromRGB(10, 14, 24),
	-- the grapple uses the suit's electric lime-white
	Lime = Color3.fromRGB(186, 255, 84),
	LimeWhite = Color3.fromRGB(238, 255, 220),
}

-- Licensed Roblox library audio (ProSoundEffects). StartAt trims the measured silent lead-in
-- (AudioAnalyzer onset) so every cue lands on the key press.
Config.Sounds = {
	PhaseDash = {
		{ Id = "rbxassetid://9113865025", Volume = 0.7, StartAt = 0.2, Speed = 1.15 },   -- compressed air burst
		{ Id = "rbxassetid://9125648149", Volume = 0.45, StartAt = 0.05, Speed = 1.1 },  -- tubular whoosh
	},
	HighJump = {
		{ Id = "rbxassetid://9120769331", Volume = 0.55, StartAt = 0.05, Speed = 1.0, PitchRise = { 0.86, 1.18, 0.55 } }, -- low boom, pitch climbs with the launch
		{ Id = "rbxassetid://9125577419", Volume = 0.4, StartAt = 0.24, Speed = 1.25 },  -- thruster air blast
	},
	PulseScan = {
		{ Id = "rbxassetid://9125981410", Volume = 0.6, StartAt = 0.42, Speed = 1.0 },   -- sonar sweep
	},
	Reveal = { Id = "rbxassetid://9125981410", Volume = 0.35, StartAt = 0.42, Speed = 1.6 }, -- short high ping per contact
	-- grapple: the same licensed sounds, re-pitched
	GrappleFire = {
		{ Id = "rbxassetid://9113865025", Volume = 0.6, StartAt = 0.2, Speed = 1.5 },    -- launcher: compressed air
		{ Id = "rbxassetid://9125648149", Volume = 0.35, StartAt = 0.05, Speed = 1.6 },  -- cable paying out
	},
	GrappleAttach = {
		{ Id = "rbxassetid://98609496290942", Volume = 0.5, StartAt = 0.03, Speed = 0.9 }, -- energy bite
		{ Id = "rbxassetid://9125981410", Volume = 0.3, StartAt = 0.42, Speed = 2.1 },     -- lock ping
	},
	GrappleRelease = {
		{ Id = "rbxassetid://9125648149", Volume = 0.3, StartAt = 0.05, Speed = 2.0 },   -- cable snapping back
	},
	-- 2026-11-19 equipment traits
	Hooked = { -- Harpoon: you were speared (2D, victim only)
		{ Id = "rbxassetid://98609496290942", Volume = 0.9, StartAt = 0.03, Speed = 0.55 },
		{ Id = "rbxassetid://9114315137", Volume = 0.35, StartAt = 0.17, Speed = 1.5 },
	},
	Blink = { -- Starfall: the zip, heard by everyone
		{ Id = "rbxassetid://9125648149", Volume = 0.55, StartAt = 0.05, Speed = 2.6 },
		{ Id = "rbxassetid://9125981410", Volume = 0.3, StartAt = 0.42, Speed = 2.8 },
	},
	Magnet = { -- Mag-Anchor: a near miss bends onto a ledge
		{ Id = "rbxassetid://9125981410", Volume = 0.35, StartAt = 0.42, Speed = 3.2 },
	},
	RelayReady = { -- Kraken: the free second grapple is ready
		{ Id = "rbxassetid://9125981410", Volume = 0.4, StartAt = 0.42, Speed = 2.4 },
	},
}
Config.SoundRollOff = { Min = 8, Max = 160 }

Config.ServerCooldownTolerance = 0.35 -- latency forgiveness on cooldowns

return Config
