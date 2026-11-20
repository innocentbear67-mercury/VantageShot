--[[
	PassConfig - VantageShot Season Pass (2026-11-17). Layout follows Hypershot's battlepass (free silver track,
	premium gold track, tier timeline, skip footer). Rewards, XP per tier, prices and the end date are STARTER
	values: change them here (Robux prices also live in ShopConfig "pass_*" products).
	Reward kinds:  { Kind = "REQ", Amount = n }  { Kind = "Crate", Id = "Field", Count = n }  { Kind = "Skin", Key = "Gun/Skin" }
]]
local Pass = {}

Pass.Season = "S1"
Pass.Name = "Season 1"
Pass.EndsAt = 1799971200 -- 2027-01-15 00:00 UTC
Pass.TierXP = 1000
Pass.MaxTier = 50
-- a skin you already own pays REQ instead (by rarity)
Pass.DupeReq = { Rare = 1000, Epic = 2500, Mythic = 7500, Legendary = 15000, Exclusive = 25000, Godly = 40000 }

local function R(n) return { Kind = "REQ", Amount = n } end
local function C(id, n) return { Kind = "Crate", Id = id, Count = n or 1 } end
local function K(key) return { Kind = "Skin", Key = key } end

local PREMIUM = {
	K("Vanguard/Archangel"), R(1500), C("Strike"), R(1500), C("Field", 2),
	C("Prestige"), R(2000), K("Breacher/ReactorCore"), R(2000), C("Strike", 2),
	R(2000), C("Field", 3), R(2500), C("Prestige"), K("Longshot/GravityWell"),
	R(2500), C("Strike", 2), R(3000), C("Field", 3), C("Apex"),
	R(3000), C("Prestige"), R(3000), C("Strike", 2), K("Vanguard/MoltenSovereign"),
	R(3500), C("Field", 3), C("Prestige"), R(3500), C("Apex"),
	R(4000), K("Knife/Magnetar"), C("Strike", 3), R(4000), C("Prestige", 2),
	R(4500), C("Field", 5), C("Strike", 3), R(5000), K("Sentinel/CelestialAstrolabe"),
	R(5000), C("Prestige", 2), R(5000), C("Apex"), C("Strike", 3),
	R(6000), C("Prestige", 2), C("Apex", 2), R(7500), K("Spectre/Calavera"),
}

Pass.Tiers = {}
for t = 1, Pass.MaxTier do
	local d = t % 10
	local req = ({ 500, 750, 1000, 1250, 1500 })[math.floor((t - 1) / 10) + 1] or 1500
	local free
	if t == 25 then
		free = K("Spectre/VenomScale")
	elseif t == 50 then
		free = C("Prestige")
	elseif d == 0 then
		free = C("Strike")
	elseif d == 3 or d == 7 then
		free = C("Field")
	else
		free = R(req)
	end
	Pass.Tiers[t] = { Free = free, Premium = PREMIUM[t] }
end

-- tier reached for a total XP (0 .. MaxTier) and progress inside the next tier
function Pass.TierOf(xp)
	xp = math.max(0, math.floor(tonumber(xp) or 0))
	local t = math.min(Pass.MaxTier, math.floor(xp / Pass.TierXP))
	local into = if t >= Pass.MaxTier then Pass.TierXP else xp - t * Pass.TierXP
	return t, into
end

function Pass.Label(rw)
	if not rw then return "" end
	if rw.Kind == "REQ" then
		local s = tostring(math.floor(rw.Amount)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		return s .. " REQ"
	elseif rw.Kind == "Crate" then
		return string.format("%s%s Crate%s", if rw.Count > 1 then rw.Count .. " " else "", rw.Id, if rw.Count > 1 then "s" else "")
	elseif rw.Kind == "Skin" then
		return ((rw.Key:match("/(.+)$") or rw.Key):gsub("(%l)(%u)", "%1 %2")) .. " skin"
	end
	return ""
end

-- Robux products (ShopConfig keys); the footer shows these
Pass.Products = { Premium = "pass_premium", Skip1 = "pass_skip1", Skip5 = "pass_skip5", SkipAll = "pass_skipall" }

return Pass
