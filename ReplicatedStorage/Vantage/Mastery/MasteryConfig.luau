--[[
	VANTAGE — MasteryConfig (shared), 2026-11-17
	Weapon mastery: every weapon levels 1–50 on its own, from XP earned with that weapon.
	Variant I unlocks at mastery 10, Variant II at 25; prestige opens at 50 (the level resets,
	every unlock is kept, and the weapon's Prestige Gold finish is granted).
	Read by the server (ServerScriptService.VantageServer.Mastery) and the lobby UI.
	Plan: project doc weapon-progression-proposal.md.
]]
local Config = {}

-- every weapon in WeaponUnlocks (level guns + future crate guns) gets mastery
Config.Weapons = {}
for _, w in require(script.Parent.Parent:WaitForChild("Weapons"):WaitForChild("WeaponUnlocks")).List do
	table.insert(Config.Weapons, w.Id)
end
Config.IsWeapon = {}
for _, id in Config.Weapons do
	Config.IsWeapon[id] = true
end

Config.MaxLevel = 50
Config.MaxPrestige = 3
-- true once mastery challenges exist: prestige then also needs that weapon's Singularity challenge
Config.RequireSingularity = false

-- weapon XP, earned only with that weapon
Config.XP = {
	Elimination = 100,
	Headshot = 25, -- on top of the elimination
	Assist = 50, -- goes to the weapon the assister last hit the victim with
	DamagePerXP = 4, -- 1 XP per 4 damage dealt (a full 200 HP kill is about 50 XP)
}

-- XP from `level` to `level + 1`. Level 10 ≈ 27k XP (about 2–3 h with one weapon),
-- level 50 ≈ 275k XP (about 25 h).
function Config.Need(level: number): number
	return 2500 + 130 * (level - 1)
end

-- XP since the last prestige -> level, XP into that level, XP needed for the next one
function Config.LevelOf(xp: number): (number, number, number)
	local level = 1
	local rest = math.max(0, math.floor(xp))
	while level < Config.MaxLevel and rest >= Config.Need(level) do
		rest -= Config.Need(level)
		level += 1
	end
	if level >= Config.MaxLevel then
		local n = Config.Need(Config.MaxLevel)
		return Config.MaxLevel, n, n -- full bar at max level
	end
	return level, rest, Config.Need(level)
end

Config.VariantLevels = { 10, 25 } -- Variant I, Variant II

-- milestone rewards (the same for every weapon). Finish / cosmetic ids name items built later.
Config.Milestones = {
	[2] = { { Kind = "Finish", Id = "Issue1", Name = "Issue colourway I" } },
	[3] = { { Kind = "REQ", Amount = 250 } },
	[4] = { { Kind = "Finish", Id = "Issue2", Name = "Issue colourway II" } },
	[5] = { { Kind = "REQ", Amount = 250 } },
	[6] = { { Kind = "Finish", Id = "Issue3", Name = "Issue colourway III" } },
	[7] = { { Kind = "REQ", Amount = 250 } },
	[8] = { { Kind = "Finish", Id = "Issue4", Name = "Issue colourway IV" } },
	[9] = { { Kind = "REQ", Amount = 250 } },
	[10] = { { Kind = "Variant", Index = 1, Name = "Variant I" }, { Kind = "Counter", Name = "Combat Log kill counter" } },
	[15] = { { Kind = "Title", Name = "Specialist title" } },
	[20] = { { Kind = "Finish", Id = "Forged", Name = "Mastery finish: Forged" } },
	[25] = { { Kind = "Variant", Index = 2, Name = "Variant II" }, { Kind = "Inspect", Name = "Mastery inspect" } },
	[30] = { { Kind = "Finish", Id = "Hardlight", Name = "Mastery finish: Hardlight" } },
	[40] = { { Kind = "Finish", Id = "Ascendant", Name = "Mastery finish: Ascendant" } },
	[50] = { { Kind = "Finish", Id = "Singularity", Name = "Mastery finish: Singularity" }, { Kind = "Badge", Name = "Mastery badge" } },
}
-- small cosmetics between the milestones
Config.Cosmetics = {
	[13] = "BeamTint", [18] = "CounterStyle", [23] = "Badge", [28] = "BeamTint",
	[33] = "CounterStyle", [38] = "Badge", [43] = "BeamTint", [48] = "CounterStyle",
}
Config.CosmeticNames = { BeamTint = "Variant beam tint", CounterStyle = "Combat Log style", Badge = "Banner badge" }

Config.PrestigeReward = { Kind = "Finish", Id = "PrestigeGold", Name = "Prestige Gold" }

-- account-wide earn boosts (user, 2026-11-17): these levels permanently raise REQ / ORD / account XP
-- earned in every match. Every weapon adds its own; the totals are capped. Never applies to purchases.
Config.Boosts = {
	[5] = { Key = "REQ", Pct = 2 }, [12] = { Key = "ORD", Pct = 2 }, [17] = { Key = "XP", Pct = 2 },
	[22] = { Key = "REQ", Pct = 3 }, [27] = { Key = "ORD", Pct = 3 }, [32] = { Key = "XP", Pct = 3 },
	[35] = { Key = "REQ", Pct = 3 }, [45] = { Key = "ORD", Pct = 3 },
}
Config.PrestigeBoost = { REQ = 2, ORD = 2, XP = 1 } -- per prestige, per weapon
Config.BoostCap = { REQ = 40, ORD = 40, XP = 25 }
Config.BoostNames = { REQ = "REQ earned", ORD = "ORD earned", XP = "account XP" }

function Config.BoostReward(b)
	return { Kind = "Boost", Key = b.Key, Pct = b.Pct, Name = "+" .. b.Pct .. "% " .. Config.BoostNames[b.Key] }
end

-- levels = { [weaponId] = { Level = n, Prestige = n } } -> { REQ = %, ORD = %, XP = % } (capped).
-- A prestiged weapon keeps every boost from its first run; replaying levels does not add them again.
function Config.BoostTotals(levels)
	local t = { REQ = 0, ORD = 0, XP = 0 }
	for _, r in levels do
		local lv, pr = r.Level or 1, r.Prestige or 0
		for L, b in Config.Boosts do
			if pr > 0 or lv >= L then t[b.Key] += b.Pct end
		end
		for k, v in Config.PrestigeBoost do t[k] += v * pr end
	end
	for k, cap in Config.BoostCap do t[k] = math.min(t[k], cap) end
	return t
end

-- what reaching `level` gives. Any level 11–49 without a milestone or cosmetic pays
-- 250 REQ (odd levels) or 1 Forge Part (even levels).
function Config.RewardsFor(level: number): { any }
	local b = Config.Boosts[level]
	if b then
		return { Config.BoostReward(b) }
	end
	local m = Config.Milestones[level]
	if m then
		return m
	end
	if level <= 10 or level >= Config.MaxLevel then
		return {}
	end
	local c = Config.Cosmetics[level]
	if c then
		return { { Kind = "Cosmetic", Id = c, Name = Config.CosmeticNames[c] } }
	end
	if level % 2 == 1 then
		return { { Kind = "REQ", Amount = 250 } }
	end
	return { { Kind = "ForgeParts", Amount = 1 } }
end

return Config
