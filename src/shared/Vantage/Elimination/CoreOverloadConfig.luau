--[[
	VANTAGE — CoreOverloadConfig (shared)
	"Crimson Core Overload" death sequence. On a death the server sets the character attribute
	VantageDeath = "Overload:<serverTime>" (WeaponService); every client then plays the pose
	(DeathPresenter) and the effects (CoreOverloadFX) on that same clock, so all players see the
	same sequence in sync. All times are seconds from the lethal hit: tune them after testing.
	Kill credit, scoring and respawn are untouched (the respawn still waits Players.RespawnTime).
]]

local C = Color3.fromRGB

return {
	Enabled = true, -- false: the directional collapse styles (Back / Front / Crumple / Spin) return

	Impact = 0.14, -- phase 1 ends: sharp stagger + crimson-white flash over the armour
	Charge = 1.0, -- phase 3 starts: the chest core builds, warning tones, rising charge whine
	Detonate = 1.75, -- phase 4: the blast; the body is gone from here
	Length = 2.0, -- the pose clock stops here; one-shot effects fade on their own after it

	MaxDistance = 450, -- further from the camera than this the effects are skipped (the body still vanishes)
	ChargePitch = { 0.7, 1.9 }, -- charge whine playback speed from Charge to Detonate

	Colors = {
		Crimson = C(200, 16, 40),
		Blood = C(110, 0, 14),
		Hot = C(255, 64, 78),
		White = C(255, 236, 238),
	},

	Sounds = { -- licensed library sounds already used in Vantage; StartAt skips silent lead-ins
		Impact = {
			{ Id = "rbxassetid://9113524237", Volume = 0.55, Speed = 0.85 },
			{ Id = "rbxassetid://9126073318", Volume = 0.3, StartAt = 0.11, Speed = 0.7 },
		},
		Charge = { { Id = "rbxassetid://9125980435", Volume = 0.5, StartAt = 0.22 } },
		Warn = { { Id = "rbxassetid://9120769331", Volume = 0.28, StartAt = 0.05, Speed = 1.6, Duration = 0.12 } },
		Detonate = {
			{ Id = "rbxassetid://9125484526", Volume = 0.85 },
			{ Id = "rbxassetid://9125484367", Volume = 0.55, Speed = 1.15 },
			{ Id = "rbxassetid://9114315137", Volume = 0.5, StartAt = 0.17, Speed = 0.8 },
		},
	},
}
