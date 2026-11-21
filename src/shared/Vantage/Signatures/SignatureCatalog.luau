--!strict
--[[
	VANTAGE — SignatureCatalog (shared) — 2026-11-19
	The 10 Norse Signatures: display data, Ichor prices and ownership helpers.
	Server truth lives in SignatureService (DataStore "VantageSignatures_v1"), replicated as player attributes:
	  Ichor            number   — Ichor balance
	  OwnedSignatures  string   — "Mjolnir,Fenrir,…" (free ones are always owned)
	  Signature        string   — the equipped Signature id (always owned; defaults to Mjolnir)
	Remotes: SignatureEquip(id) -> SignatureResult(ok, id, reason) · SignatureBuy(id) -> SignatureResult(ok, id, reason, "Buy")
]]
local Catalog = {}

export type Item = { Id: string, Num: string, Name: string, Title: string, Color: Color3, Deep: Color3, Price: number, Free: boolean?, Tier: string,
	Asset: string, Art: string?, Role: string, Blurb: string, Stats: { { string } } }

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
Catalog.List = {
	{ Id = "Mjolnir", Num = "01", Name = "MJÖLNIR", Title = "The Thunder Hammer", Color = rgb(170, 190, 255), Deep = rgb(60, 70, 190), Price = 0, Free = true, Tier = "STARTER",
		Asset = "SIG_Mjolnir", Art = "rbxassetid://115865684641860", Role = "Ranged · Chain lightning",
		Blurb = "Call the hammer down from the storm and hurl it. Lightning arcs to everyone it passes, then it flies back to your hand.",
		Stats = { { "Range", "90 st" }, { "Hits", "Pierce + arc" }, { "Cast", "0.8 s" } } },
	{ Id = "Fenrir", Num = "02", Name = "FENRIR", Title = "The Bound Wolf", Color = rgb(150, 210, 255), Deep = rgb(40, 110, 210), Price = 18000, Tier = "LEGENDARY",
		Asset = "SIG_Fenrir", Art = "rbxassetid://85429173992371", Role = "Charge · Lane sweep",
		Blurb = "A spectral wolf bursts from a rune circle, howls, and tears down the lane, raking everyone in its path with frost claws.",
		Stats = { { "Lane", "70 st" }, { "Hits", "Claw rake" }, { "Cast", "1.0 s" } } },
	{ Id = "Gungnir", Num = "03", Name = "GUNGNIR", Title = "The Spear That Never Misses", Color = rgb(255, 205, 96), Deep = rgb(200, 120, 20), Price = 15000, Tier = "LEGENDARY",
		Asset = "SIG_Gungnir", Art = "rbxassetid://129013282216382", Role = "Precision · Pierce",
		Blurb = "Odin's spear forms in your hand, runes lighting tip to butt, then flies dead straight through every enemy in line.",
		Stats = { { "Range", "110 st" }, { "Hits", "Pierce all" }, { "Cast", "0.95 s" } } },
	{ Id = "Midgard", Num = "04", Name = "MIDGARD", Title = "The World Serpent", Color = rgb(64, 236, 210), Deep = rgb(14, 120, 120), Price = 22000, Tier = "LEGENDARY",
		Asset = "SIG_Jormungandr_Head", Art = "rbxassetid://96271325525620", Role = "Area · Knock-up",
		Blurb = "Jörmungandr breaches out of the ground like a whale, dragging a wall of sea spray, and dives back in beyond.",
		Stats = { { "Radius", "9 st" }, { "Hits", "Breach + body" }, { "Cast", "1.3 s" } } },
	{ Id = "Valkyrie", Num = "05", Name = "VALKYRIE", Title = "Chooser of the Slain", Color = rgb(255, 214, 120), Deep = rgb(190, 130, 40), Price = 18000, Tier = "LEGENDARY",
		Asset = "SIG_ValkyrieWing_R", Art = "rbxassetid://98016076769529", Role = "Mobility · Dive",
		Blurb = "Wings of light carry you up into a hover trailing the northern lights, then you dive and slam down in a burst of gold.",
		Stats = { { "Hover", "1.6 s" }, { "Hits", "Landing slam" }, { "Radius", "11 st" } } },
	{ Id = "Ragnarok", Num = "06", Name = "RAGNARÖK", Title = "Brighter Than the Sun", Color = rgb(255, 120, 40), Deep = rgb(170, 30, 10), Price = 35000, Tier = "MYTHIC",
		Asset = "SIG_SurtrSword", Art = "rbxassetid://86488485887744", Role = "Line · Burn",
		Blurb = "Surtr's sword pushes through a rift in the sky and slams down, splitting the ground into a burning fissure.",
		Stats = { { "Line", "56 st" }, { "Hits", "Fissure + burn" }, { "Cast", "1.0 s" } } },
	{ Id = "Helheim", Num = "07", Name = "HELHEIM", Title = "Half Dead, Half Living", Color = rgb(159, 231, 255), Deep = rgb(30, 50, 130), Price = 35000, Tier = "MYTHIC",
		Asset = "SIG_HelGate", Art = "rbxassetid://78815456450254", Role = "Cone · Freeze",
		Blurb = "The gate of Hel rises and its ice sheet shatters, rolling a freezing wave that encases everyone in the cone.",
		Stats = { { "Cone", "36 st" }, { "Freeze", "1.25 s" }, { "Cast", "0.9 s" } } },
	{ Id = "Sleipnir", Num = "08", Name = "SLEIPNIR", Title = "Eight Legs for Speed", Color = rgb(230, 238, 247), Deep = rgb(90, 110, 150), Price = 15000, Tier = "LEGENDARY",
		Asset = "SIG_Sleipnir", Art = "rbxassetid://137938652957275", Role = "Mobility · Trample",
		Blurb = "Odin's eight-legged horse forms out of storm mist and charges you across the map, trampling anyone in the way.",
		Stats = { { "Charge", "85 st" }, { "Hits", "Trample" }, { "Cast", "0.7 s" } } },
	{ Id = "Bifrost", Num = "09", Name = "BIFRÖST", Title = "The Burning Bridge", Color = rgb(255, 74, 42), Deep = rgb(120, 40, 200), Price = 25000, Tier = "LEGENDARY",
		Asset = "SIG_BifrostRing", Art = "rbxassetid://112408650978306", Role = "Teleport · Anywhere",
		Blurb = "Open the rainbow bridge: pick any spot on the map and step through a burning three-band portal.",
		Stats = { { "Range", "Whole map" }, { "Pick", "6 s" }, { "Cast", "0.9 s" } } },
	{ Id = "Yggdrasil", Num = "10", Name = "YGGDRASIL", Title = "Dew and White Clay", Color = rgb(47, 224, 122), Deep = rgb(10, 110, 60), Price = 20000, Tier = "LEGENDARY",
		Asset = "SIG_YggRoot_B", Art = "rbxassetid://121243348483144", Role = "Cover · Shield allies",
		Blurb = "The World Tree's roots burst up around a spot, giving cover and an emerald shield shimmer to allies inside.",
		Stats = { { "Radius", "14 st" }, { "Lasts", "6 s" }, { "Cast", "0.9 s" } } },
} :: { Item }

Catalog.ById = {} :: { [string]: Item }
for _, it in Catalog.List do Catalog.ById[it.Id] = it end
Catalog.Default = "Mjolnir"
Catalog.TierColor = { STARTER = rgb(150, 160, 190), LEGENDARY = rgb(255, 196, 70), MYTHIC = rgb(255, 80, 120) }

function Catalog.Valid(id: any): boolean
	return type(id) == "string" and Catalog.ById[id] ~= nil
end

function Catalog.OwnedSet(player: Player): { [string]: boolean }
	local set = {}
	for _, it in Catalog.List do if it.Free then set[it.Id] = true end end
	local s = player:GetAttribute("OwnedSignatures")
	if type(s) == "string" then
		for id in s:gmatch("[^,]+") do if Catalog.ById[id] then set[id] = true end end
	end
	return set
end

function Catalog.Owns(player: Player, id: string): boolean
	local it = Catalog.ById[id]
	if not it then return false end
	if it.Free then return true end
	return Catalog.OwnedSet(player)[id] == true
end

function Catalog.Equipped(player: Player): string
	local id = player:GetAttribute("Signature")
	if type(id) == "string" and Catalog.Owns(player, id) then return id end
	return Catalog.Default
end

-- 2026-11-20: ICHOR CRATE + DAILY SHOP.
-- Crate: a random Signature the player doesn't own (never a duplicate), weighted per Signature by tier.
Catalog.Crate = { Id = "IchorCrate", Name = "Ichor Crate", Price = 3500, Weights = { LEGENDARY = 3, MYTHIC = 1 } }
-- art (image asset ids; nil = placeholder art): Hero = 3/4 crate render, Lid/Body = the front view split at the seam
-- (same canvas, for the reveal's lid-pop), Reveal = burst backdrop, BannerBg/BannerFg = the Shop card's layered key art.
Catalog.Crate.Art = { Hero = 82228351122917, Lid = 101493685649932, Body = 91985831109011, Reveal = 82622061757140, BannerBg = 99935004045557, BannerFg = 77009708466490, BannerW = 1024, BannerH = 294 }
-- Daily Shop: DailyCount Signatures a day (UTC day), the same for everyone; they can be bought outright for their Price.
Catalog.DailyCount = 2
function Catalog.DailyToday(t: number?)
	local day = math.floor((t or os.time()) / 86400)
	local pool = {}
	for _, it in Catalog.List do if not it.Free then pool[#pool + 1] = it.Id end end
	local r = Random.new(day * 7919 + 17)
	for i = #pool, 2, -1 do
		local j = r:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(Catalog.DailyCount, #pool) do out[i] = pool[i] end
	return out, (day + 1) * 86400
end
-- crate odds for a set of owned ids -> byTier { LEGENDARY = 0..1, MYTHIC = 0..1 }, list of { Id, W, Tier, Chance }, count left
function Catalog.CrateOdds(ownedSet)
	local list, total, byTier = {}, 0, {}
	for _, it in Catalog.List do
		if not it.Free and not (ownedSet and ownedSet[it.Id]) then
			local w = Catalog.Crate.Weights[it.Tier] or 1
			list[#list + 1] = { Id = it.Id, W = w, Tier = it.Tier }
			total += w
		end
	end
	for _, e in list do
		e.Chance = e.W / total
		byTier[e.Tier] = (byTier[e.Tier] or 0) + e.Chance
	end
	return byTier, list, #list
end

return Catalog
