--[[
	VANTAGE — ScoreboardConfig (ReplicatedStorage.Vantage.ScoreboardConfig)
	Settings for the hold-Tab scoreboard (ScoreboardClient) and per-match stats (MatchStatsServer).
	Part of the Scoreboard / MatchStats feature: every instance it adds is named Scoreboard* or MatchStats*.
]]

local Config = {}

-- ─── score ─────────────────────────────────────────────────────────────────────────────
Config.Score = {
	PerKill = 100,
	PerHeadshot = 25, -- bonus on top of the kill
}

-- ─── when the scoreboard may open ──────────────────────────────────────────────────────
Config.ScoreboardPhases = { Prep = true, Countdown = true, Live = true }
-- ScreenGuis that mean "a menu is open" (Tab does nothing while any of these is Enabled)
Config.MenuGuis = { "VantageMainMenu", "VantageArmory", "VantageSettings" }

-- ─── input ─────────────────────────────────────────────────────────────────────────────
Config.Key = Enum.KeyCode.Tab

-- ─── timings (seconds) ─────────────────────────────────────────────────────────────────
Config.ResultsDelay = 2.5      -- let MatchHud's VICTORY / DEFEAT / DRAW banner play first
Config.ResultsHideBefore = 0.6 -- slide out this long before Ended finishes (menu takes over)
Config.ResultsMaxHold = 6      -- safety cap if PhaseEnds is missing
Config.SlideTime = 0.35
Config.FadeTime = 0.12
Config.RefreshInterval = 0.25  -- scoreboard refresh rate while visible

-- ─── layout ────────────────────────────────────────────────────────────────────────────
Config.DisplayOrder = 11       -- above VantageMatchHud (9), below VantageMainMenu (12)
Config.SlotsPerTeam = 6        -- rows per team (empty slots greyed out)
Config.Board = { Width = 1120, Header = 92, ColumnHeader = 26, Row = 40, Gap = 12, Pad = 14 }
Config.Results = { Width = 760, Height = 190 }
Config.MinScale = 0.4
Config.MaxScale = 1.2

-- ─── style: obsidian / navy plates, lime highlights, no black ──────────────────────────
Config.Colors = {
	Plate = Color3.fromRGB(13, 21, 42),
	PlateRow = Color3.fromRGB(22, 33, 62),
	PlateEmpty = Color3.fromRGB(18, 26, 48),
	PlateTransparency = 0.15,
	RowTransparency = 0.25,
	Stroke = Color3.fromRGB(52, 64, 98),
	Lime = Color3.fromRGB(190, 242, 58),
	Text = Color3.fromRGB(232, 238, 248),
	TextDim = Color3.fromRGB(138, 150, 182),
	TextEmpty = Color3.fromRGB(70, 82, 114),
	OnLime = Color3.fromRGB(13, 21, 42), -- text on the lime self row
	Blue = Color3.fromRGB(78, 146, 255),
	Red = Color3.fromRGB(255, 88, 88),
	Draw = Color3.fromRGB(200, 206, 222),
}

Config.Fonts = {
	Header = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	Body = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium),
	Number = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.SemiBold),
}

return Config
