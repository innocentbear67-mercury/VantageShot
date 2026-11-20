--[[
	RankedConfig - VantageShot Ranked + Profile (2026-11-17). RP numbers are STARTER values for the user to tune.
	9 ranks from the user's badges. Wood..Mythic have 3 tiers each (1 -> 3), 100 RP per tier (300 per rank).
	Legend = RP >= LegendRP AND in the global top 100 (OrderedDataStore, SeasonPass-style server cache).
	Match RP (Ranked queue only): win +25 / loss -18 / draw 0, plus performance -6..+8 from K, A, D.
	Daily shield: the first loss of a UTC day costs nothing (performance still counts if positive).
	Rank-up protection: for 3 matches after reaching a new rank you can't drop below that rank.
]]
local R = {}
local RGB = Color3.fromRGB
local function id(n) return "rbxassetid://" .. n end

R.TierRP = 100
R.TiersPerRank = 3
R.Ranks = {
	{ Id = "Wood", Badge = id(86922899695300), Color = RGB(214, 150, 90) },
	{ Id = "Bronze", Badge = id(99283456831770), Color = RGB(230, 140, 100) },
	{ Id = "Silver", Badge = id(135855890564742), Color = RGB(210, 225, 255) },
	{ Id = "Gold", Badge = id(137839602098948), Color = RGB(255, 205, 80) },
	{ Id = "Elite", Badge = id(115001036884075), Color = RGB(255, 220, 130) },
	-- the Platinum badge id (107240198857894) does not load: Silver art tinted ice-blue until it is re-uploaded
	{ Id = "Platinum", Badge = id(135855890564742), Tint = RGB(190, 220, 255), Color = RGB(200, 215, 240) },
	{ Id = "Diamond", Badge = id(79142276908428), Color = RGB(80, 220, 255) },
	{ Id = "Mythic", Badge = id(109887267286961), Color = RGB(255, 60, 140) },
	{ Id = "Legend", Badge = id(105048808444395), Color = RGB(255, 200, 60) },
}
R.LegendRP = 8 * R.TiersPerRank * R.TierRP -- 2400: top of Mythic 3
R.LegendTop = 100
R.Win, R.Loss, R.Draw = 25, -18, 0
R.PerfMin, R.PerfMax = -6, 8
R.ProtectMatches = 3
R.HistoryMax = 20

-- profile banners (user's Gemini art, 1024x559)
R.Banners = {
	{ Id = "dogtag", Name = "Dog Tag", Image = id(72216391852307), Color = RGB(170, 110, 255) },
	{ Id = "visor", Name = "Shattered Visor", Image = id(134828145264424), Color = RGB(70, 230, 255) },
	{ Id = "rifles", Name = "Crossed Rifles", Image = id(94581929956264), Color = RGB(255, 170, 70) },
	{ Id = "grapple", Name = "Grapple Rush", Image = id(72464020984674), Color = RGB(90, 240, 255) },
	{ Id = "plasma", Name = "Plasma Core", Image = id(95518096437362), Color = RGB(220, 110, 255) },
	{ Id = "dragon", Name = "Gold Dragon", Image = id(83336799560798), Color = RGB(255, 150, 50) },
}
R.BannerById = {}
for _, b in R.Banners do R.BannerById[b.Id] = b end
R.DefaultBanner = "dogtag"

function R.Perf(k, d, a)
	return math.clamp(math.floor(((k or 0) + (a or 0) * 0.5 - (d or 0)) * 0.6 + 0.5), R.PerfMin, R.PerfMax)
end

-- rp -> { Index (1..9), Rank, Tier (1..3 or nil), Name, Into, Need }
function R.RankOf(rp, legend)
	rp = math.max(0, math.floor(tonumber(rp) or 0))
	local per = R.TiersPerRank * R.TierRP
	if rp >= R.LegendRP then
		if legend then
			return { Index = 9, Rank = R.Ranks[9], Name = "LEGEND", Into = rp - R.LegendRP, Need = 0 }
		end
		return { Index = 8, Rank = R.Ranks[8], Tier = 3, Name = "MYTHIC 3", Into = R.TierRP, Need = R.TierRP }
	end
	local idx = math.floor(rp / per) + 1
	local within = rp % per
	local tier = math.floor(within / R.TierRP) + 1
	local rank = R.Ranks[idx]
	return { Index = idx, Rank = rank, Tier = tier, Name = string.upper(rank.Id) .. " " .. tier, Into = within % R.TierRP, Need = R.TierRP }
end

return R
