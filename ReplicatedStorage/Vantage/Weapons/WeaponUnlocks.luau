--[[
	VANTAGE — WeaponUnlocks (shared), 2026-11-17
	One list of every weapon and how a player gets it. Mastery, Loadout and the server all read this, so a new
	weapon only needs one line here (plus its WeaponConfig).

	Sources:
	  Starter  owned from the start
	  Level    owned once the account level (player attribute "Level") reaches Level (none use this since 2026-11-17)
	  Crate    unlocked from Arsenal Crates (CrateConfig.WeaponCrates, bought with Ordnance / ORD). The server lists
	           owned crate weapons in the player attribute "OwnedWeapons" (comma-separated ids).

	2026-11-17 (user): every gun except the Vanguard comes from Arsenal Crates. A crate only rolls guns the player
	doesn't own yet, so every open is a new gun. Each gun has an equal chance; Rarity is presentation only
	(reel / reveal colour). OldLevel = the level it used to unlock at (kept for reference).
	ORD is also sold for Robux, so a new gun must stay a sidegrade (different, never statistically stronger).

	Order = display order (Mastery list, Loadout grid). Class groups the Loadout grid.
]]
local U = {}

U.List = {
	{ Id = "Vanguard", Name = "Vanguard", Class = "Rifle", Source = "Starter" },
	{ Id = "Spectre", Name = "Spectre", Class = "Sidearm", Source = "Crate", Rarity = "Rare", OldLevel = 3 },
	{ Id = "Breacher", Name = "Breacher", Class = "Shotgun", Source = "Crate", Rarity = "Epic", OldLevel = 5 },
	{ Id = "Sentinel", Name = "Sentinel", Class = "Rifle", Source = "Crate", Rarity = "Epic", OldLevel = 7 },
	{ Id = "Arc", Name = "Arc", Class = "Energy", Source = "Crate", Rarity = "Mythic", OldLevel = 9 },
	{ Id = "Longshot", Name = "Longshot", Class = "Sniper", Source = "Crate", Rarity = "Legendary", OldLevel = 11 },
	{ Id = "Knife", Name = "CK-3 Edge", Class = "Melee", Source = "Starter" },
	-- 2026-11-18 wave 1 (Blender models, new-guns-wave1.md)
	{ Id = "Riptide", Name = "Riptide", Class = "SMG", Source = "Crate", Rarity = "Rare" },
	{ Id = "Verdict", Name = "Verdict", Class = "Sidearm", Source = "Crate", Rarity = "Epic" },
	{ Id = "Bulwark", Name = "Bulwark", Class = "LMG", Source = "Crate", Rarity = "Epic" },
	{ Id = "Quill", Name = "Quill", Class = "Crossbow", Source = "Crate", Rarity = "Mythic" },
	{ Id = "Helix", Name = "Helix", Class = "Energy", Source = "Crate", Rarity = "Legendary" },
	{ Id = "Havoc", Name = "Havoc", Class = "Launcher", Source = "Crate", Rarity = "Legendary" },
	-- new guns: add a line here (Source = "Crate", Rarity) plus their WeaponConfig
}

U.ById = {}
for i, w in U.List do
	w.Order = i
	U.ById[w.Id] = w
end

function U.Name(id: string): string
	local w = U.ById[id]
	return if w then w.Name else id
end

local function ownedSet(owned)
	if type(owned) == "table" then return owned end
	local set = {}
	if type(owned) == "string" then
		for _, s in string.split(owned, ",") do
			if s ~= "" then set[s] = true end
		end
	end
	return set
end

-- level: account level; owned: crate-weapon set or the "OwnedWeapons" attribute string
function U.Owns(id: string, level: number?, owned): boolean
	local w = U.ById[id]
	if not w then return false end
	if w.Source == "Starter" then return true end
	if w.Source == "Level" then return (level or 1) >= (w.Level or 1) end
	if w.Source == "Crate" then return ownedSet(owned)[id] == true end
	return false
end

function U.OwnsFor(p: Player, id: string): boolean
	return U.Owns(id, p:GetAttribute("Level"), p:GetAttribute("OwnedWeapons"))
end

function U.LockText(id: string): string
	local w = U.ById[id]
	if not w then return "Locked" end
	if w.Source == "Level" then return "Unlocks at Level " .. w.Level end
	if w.Source == "Crate" then return "From Arsenal Crates" end
	return ""
end

-- weapons that unlock exactly at this account level (for the level-up toast / account rewards)
function U.UnlockedAt(level: number)
	local out = {}
	for _, w in U.List do
		if w.Source == "Level" and w.Level == level then table.insert(out, w) end
	end
	return out
end

-- guns that can come out of an Arsenal Crate, in list order
function U.CrateWeapons()
	local out = {}
	for _, w in U.List do
		if w.Source == "Crate" then table.insert(out, w) end
	end
	return out
end

-- crate guns this player doesn't own yet (owned = "OwnedWeapons" string or set)
function U.Missing(owned)
	local set = ownedSet(owned)
	local out = {}
	for _, w in U.List do
		if w.Source == "Crate" and not set[w.Id] then table.insert(out, w) end
	end
	return out
end

return U
