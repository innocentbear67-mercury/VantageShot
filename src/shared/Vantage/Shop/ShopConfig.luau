--[[
	ShopConfig - VantageShot Robux shop catalog (2026-11-16).
	ProductId / PassId are filled in once the products exist on the experience (0 = not live yet).
	Prices are starter values; change Robux here AND on the Creator Dashboard together.
]]
local Shop = {}

Shop.Sections = {
	{ Id = "Crates", Title = "Premium Crates" },
	{ Id = "Ichor", Title = "Signatures" }, -- 2026-11-20: Ichor Crate + Daily Shop (SignatureCatalog)
	{ Id = "Deals", Title = "Deals" },
	{ Id = "Passes", Title = "Gamepasses" },
	{ Id = "Req", Title = "REQ Packs" },
	{ Id = "Ord", Title = "Ordnance Packs" }, -- 2026-11-17: ORD buys Arsenal Crates (gun unlocks)
	{ Id = "IchorPack", Title = "Ichor Packs" }, -- 2026-11-20: Ichor for Robux (Ichor Crate / Daily Shop Signatures)
}

Shop.Products = {
	{ Key = "crate_apex_1", Section = "Crates", Name = "Apex Crate", Crate = "Apex", Count = 1, Robux = 99, ProductId = 0, Grant = { Crates = { Apex = 1 } } },
	{ Key = "crate_apex_3", Section = "Crates", Name = "Apex Crate", Crate = "Apex", Count = 3, Robux = 269, ProductId = 0, Grant = { Crates = { Apex = 3 } } },
	{ Key = "crate_prestige_1", Section = "Crates", Name = "Prestige Crate", Crate = "Prestige", Count = 1, Robux = 49, ProductId = 0, Grant = { Crates = { Prestige = 1 } } },
	{ Key = "crate_prestige_3", Section = "Crates", Name = "Prestige Crate", Crate = "Prestige", Count = 3, Robux = 129, ProductId = 0, Grant = { Crates = { Prestige = 3 } } },
	-- equipment crates (shield packs + grappling hooks), 2026-11-17
	{ Key = "crate_eliteequip_1", Section = "Crates", Name = "Elite Equipment", Crate = "EliteEquipment", Count = 1, Robux = 79, ProductId = 0, Grant = { Crates = { EliteEquipment = 1 } } },
	{ Key = "crate_eliteequip_3", Section = "Crates", Name = "Elite Equipment", Crate = "EliteEquipment", Count = 3, Robux = 215, ProductId = 0, Grant = { Crates = { EliteEquipment = 3 } } },
	{ Key = "crate_equip_1", Section = "Crates", Name = "Equipment Crate", Crate = "Equipment", Count = 1, Robux = 35, ProductId = 0, Grant = { Crates = { Equipment = 1 } } },
	{ Key = "crate_equip_3", Section = "Crates", Name = "Equipment Crate", Crate = "Equipment", Count = 3, Robux = 95, ProductId = 0, Grant = { Crates = { Equipment = 3 } } },
	-- Deals (researched lineup): starter pack, featured weapon (gun + crates), anchor bundle; skins are GUARANTEED (not random)
	{ Key = "deal_recruit", Section = "Deals", Name = "Recruit Pack", Robux = 79, Was = 299, OneTime = true, ProductId = 0, Art = "recruit", Skin = "Vanguard/PlasmaFlux", DupeReq = 5000, Lines = { "Plasma Flux skin (Epic)", "1 Strike Crate", "5,000 REQ" }, Grant = { Skins = { "Vanguard/PlasmaFlux" }, Crates = { Strike = 1 }, Req = 5000 } },
	{ Key = "deal_featured", Section = "Deals", Name = "Event Horizon Drop", Robux = 399, Was = 699, OneTime = true, ProductId = 0, Art = "featured", Skin = "Vanguard/EventHorizon", DupeReq = 25000, Lines = { "Event Horizon skin (Legendary)", "2 Apex Crates", "Guaranteed skin, no RNG" }, Grant = { Skins = { "Vanguard/EventHorizon" }, Crates = { Apex = 2 } } },
	{ Key = "deal_commander", Section = "Deals", Name = "Commander Bundle", Robux = 1499, Was = 2499, OneTime = true, ProductId = 0, Art = "commander", Skin = "Vanguard/DragonEmperor", DupeReq = 100000, Lines = { "Golden Dragon Emperor (Godly)", "5 Apex Crates", "50,000 REQ" }, Grant = { Skins = { "Vanguard/DragonEmperor" }, Crates = { Apex = 5 }, Req = 50000 } },
	{ Key = "deal_pass", Section = "Deals", Name = "Season Pass Bundle", Robux = 799, Was = 1349, ProductId = 0, Art = "seasonpass", Lines = { "Premium Season Pass", "10 tier skips", "1 Apex Crate" }, Grant = { Pass = { Premium = true, Skips = 10 }, Crates = { Apex = 1 } } },
	-- Season Pass (SeasonPassHS footer / Premium card), 2026-11-17. Section "Pass" is not listed in the Shop grid.
	{ Key = "pass_premium", Section = "Pass", Name = "Premium Season Pass", Robux = 499, ProductId = 0, Grant = { Pass = { Premium = true } } },
	{ Key = "pass_skip1", Section = "Pass", Name = "Tier Skip", Robux = 75, ProductId = 0, Grant = { Pass = { Skips = 1 } } },
	{ Key = "pass_skip5", Section = "Pass", Name = "5 Tier Skips", Robux = 299, Was = 375, ProductId = 0, Grant = { Pass = { Skips = 5 } } },
	{ Key = "pass_skipall", Section = "Pass", Name = "Skip ALL Tiers", Robux = 1999, Was = 3750, ProductId = 0, Grant = { Pass = { SkipAll = true } } },
	-- Daily Deal: one offer per UTC day, rotating
	{ Key = "daily_prestige5", Section = "Daily", Name = "5 Prestige Crates", Crate = "Prestige", Robux = 149, Was = 245, ProductId = 0, Grant = { Crates = { Prestige = 5 } } },
	{ Key = "daily_apex3", Section = "Daily", Name = "3 Apex Crates", Crate = "Apex", Robux = 199, Was = 297, ProductId = 0, Grant = { Crates = { Apex = 3 } } },
	{ Key = "daily_req25", Section = "Daily", Name = "25,000 REQ", Robux = 119, Was = 169, ProductId = 0, Grant = { Req = 25000 } },
	{ Key = "req_s", Section = "Req", Name = "REQ Pouch", Robux = 49, ProductId = 0, Coins = 1, Grant = { Req = 5000 } },
	{ Key = "req_m", Section = "Req", Name = "REQ Satchel", Robux = 99, Bonus = "+20%", ProductId = 0, Coins = 2, Grant = { Req = 12000 } },
	{ Key = "req_l", Section = "Req", Name = "REQ Cache", Robux = 199, Bonus = "+50%", ProductId = 0, Coins = 3, Grant = { Req = 30000 } },
	{ Key = "req_xl", Section = "Req", Name = "REQ Vault", Robux = 449, Bonus = "+75%", Best = true, ProductId = 0, Coins = 4, Grant = { Req = 80000 } },
	-- Ordnance packs (ORD; an Arsenal Crate is 200 ORD). Starter prices, ProductId 0 until created on the dashboard.
	{ Key = "ord_s", Section = "Ord", Name = "Ammo Crate", Robux = 49, ProductId = 0, Coins = 1, Grant = { Ord = 400 } },
	{ Key = "ord_m", Section = "Ord", Name = "Munitions Drop", Robux = 99, Bonus = "+25%", ProductId = 0, Coins = 2, Grant = { Ord = 1000 } },
	{ Key = "ord_l", Section = "Ord", Name = "Ordnance Pallet", Robux = 199, Bonus = "+50%", Best = true, ProductId = 0, Coins = 3, Grant = { Ord = 2400 } },
	-- 2026-11-20: Ichor packs (an Ichor Crate is 3,500 Ichor; Signatures are 15k-35k). Starter prices, ProductId 0 until created.
	{ Key = "ichor_s", Section = "IchorPack", Name = "Vial of Ichor", Robux = 99, ProductId = 0, Grant = { Ichor = 1200 } },
	{ Key = "ichor_m", Section = "IchorPack", Name = "Ichor Flask", Robux = 249, Bonus = "+16%", ProductId = 0, Grant = { Ichor = 3500 } },
	{ Key = "ichor_l", Section = "IchorPack", Name = "Cauldron of Ichor", Robux = 499, Bonus = "+32%", Best = true, ProductId = 0, Grant = { Ichor = 8000 } },
}

Shop.Passes = {
	{ Key = "vip", Name = "VIP", Robux = 349, PassId = 0, Boost = 0.25, Lines = { "+25% REQ from matches", "Gold [VIP] chat tag", "2 Apex Crates instantly" }, Gift = { Crates = { Apex = 2 } } },
	{ Key = "req2x", Name = "Double REQ", Robux = 199, PassId = 0, Boost = 1, Lines = { "2x REQ from every match", "Stacks with VIP" } },
}

Shop.ByKey, Shop.ByProductId, Shop.ByPassId = {}, {}, {}
for _, p in Shop.Products do
	Shop.ByKey[p.Key] = p
	if p.ProductId and p.ProductId > 0 then Shop.ByProductId[p.ProductId] = p end
end
for _, p in Shop.Passes do
	Shop.ByKey[p.Key] = p
	if p.PassId and p.PassId > 0 then Shop.ByPassId[p.PassId] = p end
end

function Shop.Summary(g)
	local parts = {}
	for _, k in g.Skins or {} do
		local nm = (k:match("/(.+)$") or k):gsub("(%l)(%u)", "%1 %2")
		table.insert(parts, nm .. " skin")
	end
	for id, n in g.Crates or {} do
		table.insert(parts, string.format("%d %s Crate%s", n, id, if n > 1 then "s" else ""))
	end
	if g.Pass then
		if g.Pass.Premium then table.insert(parts, 1, "Premium Season Pass") end
		if g.Pass.SkipAll then table.insert(parts, "every tier unlocked") elseif g.Pass.Skips then table.insert(parts, g.Pass.Skips .. " tier skip" .. (if g.Pass.Skips > 1 then "s" else "")) end
	end
	if g.Ord and g.Ord > 0 then
		local s = tostring(math.floor(g.Ord)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		table.insert(parts, s .. " ORD")
	end
	if g.Ichor and g.Ichor > 0 then
		local s = tostring(math.floor(g.Ichor)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		table.insert(parts, s .. " Ichor")
	end
	if g.Req and g.Req > 0 then
		local s = tostring(math.floor(g.Req)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		table.insert(parts, s .. " REQ")
	end
	return table.concat(parts, " + ")
end

Shop.Daily = { "daily_prestige5", "daily_apex3", "daily_req25" }
-- today's daily offer (UTC day) and when it ends (unix seconds)
function Shop.DailyToday(now)
	local day = math.floor(now / 86400)
	return Shop.ByKey[Shop.Daily[(day % #Shop.Daily) + 1]], (day + 1) * 86400
end

return Shop
