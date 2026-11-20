--[[
	VANTAGE — Requisition (REQ) config. REQ is the main earned currency: Command credits
	Legionaries for eliminations, headshots and assists (later: directives, bounties, caches).
	Server: ServerScriptService.VantageServer.Requisition (balance, DataStore, awards).
	Client: StarterPlayerScripts.VantageReqFeed (tick feed beside the crosshair + total readout).
	Approved design: Direction D (2026-11-14) — HyperShot pattern in our lore:
	"KESTREL-7  +100 [REQ emblem]", chunky Fredoka with a dark outline, red amount.
]]
return {
	-- REQ emblem image (user's hex "R" badge). Empty = a drawn stand-in until it is uploaded.
	Icon = "rbxassetid://115805213028426",

	Rewards = {
		Elimination = 100,
		Headshot = 50,
		Melee = 25,
		Assist = 40,
	},
	-- SUPPLY SURGE (2026-11-18): HyperShot's random "SUPER BONUS!!" kill, in lore. Every credited
	-- elimination rolls Chance; a hit sends a Command bonus cache: flash + burst of REQ / ORD emblems
	-- out of the body, a rain of small +REQ / +ORD ticks that fly into the REQ total, a small heal,
	-- and one "SUPPLY SURGE" feed line paid when the ticks land (PayDelay s after the kill).
	-- Server: EliminationService (rollSurge). Client: StarterPlayerScripts.VantageSupplySurge.
	-- Studio: player attribute ForceSurge = true -> every kill surges; set SurgeTest to any new value
	-- -> one surge right now (no kill needed).
	Surge = {
		Enabled = true,
		Chance = 0.2, -- 1 in 5 kills (user, 2026-11-18; was 0.1)
		REQ = { Min = 250, Max = 400 }, -- a normal kill pays 100
		ORD = { Min = 15, Max = 30 }, -- a normal kill pays 5
		Heal = 25, -- HP restored on the spot (capped at max health)
		PayDelay = 2.9,
		Title = "SUPPLY SURGE!!",
		Label = "SUPPLY SURGE",
	},

	-- assists: other players who dealt at least this much in the last Window seconds
	AssistMinDamage = 25,
	AssistWindow = 10,

	Feed = {
		AmountColor = Color3.fromRGB(255, 222, 60), -- HyperShot yellow (2026-11-18; was red 255,59,59)
		NameColor = Color3.fromRGB(232, 233, 226), -- muted military white
		LabelColor = Color3.fromRGB(207, 198, 178), -- warm off-white (headshot / assist lines)
		EventColor = Color3.fromRGB(227, 166, 69), -- amber: big events (bounty, directive)
		Outline = Color3.fromRGB(11, 13, 16),
		OutlineThickness = 2.5,
		-- top-left of the feed, in px at 1080p, from the screen centre (crosshair): up and to
		-- the right, clear of the gun barrel
		Offset = Vector2.new(92, -113), -- (old centre placement, unused since 2026-11-16)
		EdgeInset = 36, -- px from the right edge (at the 900 px reference height)
		EdgeY = 70, -- px below screen centre
		-- v4 kill line (2026-11-18), measured from HyperShot footage: one line, replaced by the next
		-- kill. Left-middle of the line, in px at the 900 px reference height, from the screen centre
		-- (+x right, -y up). HyperShot at 1080p: +190, -140.
		LineX = 158,
		LineY = -117,
		LineSize = 30, -- name and amount (same size, like HyperShot); emblem 1.22x
		LineFont = "rbxasset://fonts/families/FredokaOne.json", -- chunky rounded, like HyperShot's
		LineOutline = 2.5,
		LineGap = 7,
		LinePop = 2.2, -- slams in at this scale...
		LinePopTime = 0.45, -- ...and eases to 1 in this long
		MainSize = 34, -- (v3, unused)
		SubSize = 22, -- (v3, unused)
		Life = 2.75, -- seconds a line stays before fading (HyperShot: gone ~3 s after the kill)
		Fade = 0.25,
		Max = 3,
		TotalSize = 30, -- running total next to the ammo
	},
}
