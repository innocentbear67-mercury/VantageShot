--[[
	VANTAGE — KillFeedConfig (shared)
	The kill feed: who eliminated whom, with what. The server decides every entry
	(EliminationService.OnDeath -> Remotes.KillFeed); clients only draw it (VantageKillFeed).

	Entry types (Type) and how the server picks them, first match wins:
	  Suicide     the victim killed themselves (reset, own fire) — no killer
	  Environment no killer: the void / kill volumes, a fall, anything without a lethal hit
	  Explosion   the lethal hit was explosive (tank splash, caught in a destroyed vehicle's blast)
	              — with a killer: their weapon + a blast mark; without one: environmental blast
	  Drone       the lethal hit came from the drone's guns
	  Vehicle     tank cannon (direct), APC / buggy guns, run-overs
	  Aircraft    a weapon whose Kind is "Aircraft" (no aircraft weapon exists yet; ready for one)
	  Melee       a Melee-kind weapon (the knife)
	  Headshot    a gun kill on the head
	  Weapon      any other gun kill
]]

local C = Color3.fromRGB

return {
	MaxRows = 5,              -- visible at once; a 6th pushes the oldest out
	Lifetime = 5,             -- seconds an entry stays
	FadeTime = 0.45,          -- seconds the fade-out takes
	SlideTime = 0.32,         -- seconds the slide-in takes
	MaxNameChars = 16,        -- longer names are cut with an ellipsis
	MaxNameWidth = 190,       -- px (1080p): names never grow past this

	-- assists: display only (no score, no stats). A player who dealt at least MinDamage to the
	-- victim within Window seconds before the death, other than the killer, is listed after the killer.
	Assists = { Enabled = true, Window = 10, MinDamage = 25, Max = 1 },

	Colors = {
		Killer = C(255, 214, 64),  -- HUD v5 (Hypershot gold killer)
		Victim = C(255, 84, 104),  -- HUD v4 red
		Text = C(238, 244, 255),
		Dim = C(150, 166, 190),
		Icon = C(238, 244, 255),
		Back = C(16, 18, 30),
		BackAlpha = 0.22,          -- background transparency
		SelfBackAlpha = 0.1,      -- rows you are in: a touch more solid + a coloured edge
	},

	-- non-player names
	BotNames = { VantageBot = "COMBAT BOT", VantageDummy = "TRAINING DUMMY" },
	EnvironmentName = "ENVIRONMENT",
}
