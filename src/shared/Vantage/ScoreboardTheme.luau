--[[
	VANTAGE — ScoreboardTheme (ReplicatedStorage.Vantage.ScoreboardTheme)
	Visual tokens for the scoreboard + post-match debrief (ScoreboardClient).
	Typography, team colours and lime follow LimeKit (MainMenu / MatchHud) so the panels sit in
	the same family; the panel glass is a navy / obsidian variant of LimeKit's glass.
	Functional settings (keys, phases, timings of the flow, score weights) stay in ScoreboardConfig.
	All sizes are 1920x1080 design pixels, scaled with UIScale at runtime.
]]

local Theme = {}
local C = Color3.fromRGB

local function fam(name: string, weight: Enum.FontWeight?)
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight or Enum.FontWeight.Regular)
end

Theme.C = {
	-- glass
	Midnight = C(6, 10, 20),      -- deepest layer (shadows, recessed cells)
	Obsidian = C(10, 16, 30),     -- panel base
	Glass = C(16, 26, 46),        -- translucent navy glass
	GlassHi = C(30, 44, 72),      -- lit glass (rows, cards)
	-- metal / light
	Steel = C(132, 150, 180),     -- muted metallic blue-grey (labels, ticks)
	Line = C(160, 180, 214),      -- hairlines and edge light (always used translucent)
	-- text
	Text = C(232, 238, 248),
	TextDim = C(142, 158, 188),
	TextFaint = C(78, 92, 122),
	-- accents (LimeKit values)
	Lime = C(182, 255, 0),
	Blue = C(77, 166, 255),
	Red = C(255, 86, 72),
	Draw = C(206, 214, 230),
	OnLime = C(10, 16, 30),
}

Theme.F = {
	Head = fam("Oswald", Enum.FontWeight.Bold),
	Head6 = fam("Oswald", Enum.FontWeight.SemiBold),
	Name = fam("TitilliumWeb", Enum.FontWeight.SemiBold),
	NameB = fam("TitilliumWeb", Enum.FontWeight.Bold),
	Mono = fam("RobotoMono"),
	MonoM = fam("RobotoMono", Enum.FontWeight.Medium),
	MonoB = fam("RobotoMono", Enum.FontWeight.Bold),
}

-- scoreboard layout (design px)
Theme.Board = {
	W = 1240,
	Header = 116,
	Gap = 14,
	ColHeader = 32,
	Row = 46,
	RowGap = 4,
	Footer = 26,
	-- stat columns, right to left: key, title, width
	Stats = {
		{ "Score", "SCORE", 80 },
		{ "HS", "HS", 48 },
		{ "KD", "K/D", 60 },
		{ "D", "D", 48 },
		{ "K", "K", 48 },
	},
}

-- debrief layout (design px)
Theme.Results = {
	W = 1000,
	H = 244,
	GapBelowBanner = 18,
}

-- MatchHud's VICTORY / DEFEAT banner (read-only reference, design px): the "Result" group is
-- centred at 42 % of the screen height and 320 tall. The debrief is placed below its bottom edge.
Theme.Banner = { CenterY = 0.42, HalfHeight = 160 }

Theme.Anim = {
	OpenTime = 0.2,       -- scoreboard fade / rise in
	CloseTime = 0.14,     -- scoreboard fade out
	Rise = 14,            -- px the board rises while opening
	RowSlide = 12,        -- px rows slide in from the left
	RowStagger = 0.018,   -- s between rows
	HoverTime = 0.12,
	HighlightTime = 0.22, -- self-row tint / bar
	FlashTime = 0.6,      -- changed value flashes lime then settles
	PulseTime = 0.9,      -- live dot
	ResultsIn = 0.55,
	ResultsOut = 0.32,
	ResultsRise = 40,
	BlockStagger = 0.12,  -- outcome -> MVP -> your stats
	CountUp = 0.7,
	Shine = 0.9,
}

-- responsive scale (same rule MatchHud uses), clamped
Theme.MinScale = 0.45
Theme.MaxScale = 1.6
Theme.MobileMinScale = 0.6 -- small screens: never shrink the board below this (readability)

return Theme
