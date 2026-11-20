--[[
	VANTAGE — EliminationConfig (shared)
	Elimination effects, announcer callouts, streak / multikill rules and death replay timings.
	Effects are ModuleScripts under VantageWeaponClient.EliminationFX, one per id. A player's
	chosen effect is the Player attribute "EliminationEffect" (falls back to DefaultEffect), so
	new cosmetics are a new module + an attribute, nothing else.
]]

local C = Color3.fromRGB

return {
	DefaultEffect = "Insignia",
	WorldMaxDistance = 320, -- other players' eliminations further than this show no world effect
	ConfirmTime = 1.6, -- seconds the kill confirmation stays up (+0.25 per intensity tier)
	-- multikill: kills each within this many seconds of the previous one (DOUBLE / TRIPLE / MULTI)
	MultiKillWindow = 4,
	-- streak: kills in one life without dying; each milestone is announced once, when reached
	StreakMilestones = { [5] = "Dominating", [8] = "Unstoppable", [12] = "Untouchable" },

	Gold = {
		Glint = C(255, 251, 232),
		Light = C(255, 228, 150),
		Base = C(226, 172, 62),
		Deep = C(120, 78, 22),
	},
	Metal = { Light = C(78, 86, 102), Dark = C(14, 18, 26) },

	Colors = {
		Self = C(70, 235, 215), -- your own eliminations
		Headshot = C(255, 214, 80),
		Accent = C(60, 170, 255), -- Vantage cyan
		Kill = C(255, 70, 80),
		Blue = C(60, 170, 255), -- other players' eliminations: the killer's team colour
		Red = C(255, 70, 80),
		Neutral = C(235, 240, 248),
		Panel = C(7, 11, 19),
		Ink = C(10, 14, 24),
	},

	--[[ Announcer: exactly one line per elimination — the highest Priority that applies wins.
		A line still speaking is only cut off by a higher-priority one; equal or lower lines are
		dropped while it speaks or within Cooldown of it starting.
		Tier = visual intensity (1 normal, 2 headshot / knife, 3 multikill / streak).
		Icon = the emblem shown for that callout; Glow = the halo behind it.
		Id = "" means NO VOICE ASSET YET: a short non-voice placeholder sting plays instead.
		To finish a line, upload an original recording and paste its "rbxassetid://..." here. ]]
	-- 2026-11-14 marker set: the confirmation emblem follows the killer's streak (kills this life),
	-- same tiers as the crosshair kill marker (HitFeedback): 1 Clean, 3 Stylized, 5 Legendary,
	-- 7 Premium, 10 Mythic. Below 3, a headshot shows HEADKILL and a knife kill KILL. Double /
	-- triple kills show their own badge.
	ShowEmblem = false, -- the crosshair kill marker (HitFeedback) is the one kill emblem on screen
	TierIcons = {
		Clean = "rbxassetid://83499799910835",
		Stylized = "rbxassetid://80342476641284",
		Legendary = "rbxassetid://118649522317334",
		Premium = "rbxassetid://76418573656901",
		Mythic = "rbxassetid://92422570161008",
		Kill = "rbxassetid://132408962358190",
		HeadKill = "rbxassetid://129406414639740",
		Double = "rbxassetid://79392575299585",
		Triple = "rbxassetid://130508795227922",
	},
	TierStreak = { Stylized = 3, Legendary = 5, Premium = 7, Mythic = 10 },

	Announcer = {
		Enabled = false, -- 2026-11-17: Hypershot has no announcer; a kill = kill cue + coin blip
		Cooldown = 0.3,
		Volume = 1,
		Placeholder = { Id = "rbxassetid://137096881472307", Volume = 0.5, BaseSpeed = 0.95, SpeedPerPriority = 0.06 },
		Lines = {
			Eliminated = { Text = "ELIMINATED", Priority = 1, Tier = 1, Id = "rbxassetid://137238972220422", Icon = "rbxassetid://83499799910835", Glow = C(200, 210, 225) },
			Fatality = { Text = "FATALITY", Priority = 2, Tier = 2, Id = "rbxassetid://130830440359218", Icon = "rbxassetid://132408962358190", Glow = C(200, 210, 225) }, -- knife elimination
			Headshot = { Text = "HEADSHOT", Priority = 3, Tier = 2, Id = "rbxassetid://70852964788758", Icon = "rbxassetid://129406414639740", Glow = C(226, 172, 62) },
			DoubleKill = { Text = "DOUBLE KILL", Priority = 4, Tier = 3, Id = "rbxassetid://101863793946922", Icon = "rbxassetid://79392575299585", Glow = C(200, 210, 225) },
			TripleKill = { Text = "TRIPLE KILL", Priority = 5, Tier = 3, Id = "rbxassetid://112232143661091", Icon = "rbxassetid://130508795227922", Glow = C(226, 172, 62) }, -- no own art yet: double-skull, gold halo
			MultiKill = { Text = "MULTI KILL", Priority = 6, Tier = 3, Id = "rbxassetid://98037241910196", Icon = "rbxassetid://80342476641284", Glow = C(226, 172, 62) }, -- no own art yet: Dominating crest
			Dominating = { Text = "DOMINATING", Priority = 7, Tier = 3, Id = "rbxassetid://102368428404179", Icon = "rbxassetid://118649522317334", Glow = C(226, 172, 62) },
			Unstoppable = { Text = "UNSTOPPABLE", Priority = 8, Tier = 3, Id = "rbxassetid://97464921074785", Icon = "rbxassetid://76418573656901", Glow = C(255, 214, 110) },
			Untouchable = { Text = "UNTOUCHABLE", Priority = 9, Tier = 3, Id = "rbxassetid://103807123139443", Icon = "rbxassetid://92422570161008", Glow = C(255, 236, 170) }, -- no own art yet: Unstoppable crest
		},
	},

	-- non-voice layers on top of the weapon's own Kill cue (WeaponConfig Sounds.Kill)
	Sounds = {
		Headshot = { Id = "rbxassetid://9126073318", Speed = 1.35, Volume = 0.6 }, -- extra bright ring
	},

	Replay = {
		Buffer = 3.6, -- seconds of rolling history kept (2026-11-20 perf: was 7; only Window is ever replayed)
		RecordRate = 20, -- samples per second (2026-11-20 perf: was 30; the replay interpolates between samples)
		Window = 2.6, -- seconds before the death that are replayed
		MinBuffer = 1, -- less history than this (just spawned) -> no replay
		SlowLast = 0.45, -- the last seconds before the death play in slow motion...
		SlowSpeed = 0.4, -- ...at this speed
		After = 0.2, -- keep playing this long past the death (the fatal shot's effects)
		Reveal = 0.9, -- camera turns to the attacker
		Delay = 2.2, -- normal death camera shown first (long enough to watch the Crimson Core Overload)
		MaxRespawnDelay = 8, -- server never holds a respawn longer than this after the death
	},
}
