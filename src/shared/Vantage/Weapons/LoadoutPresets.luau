--!nocheck
--[[
	VANTAGE - LoadoutPresets (shared, 2026-11-17)
	Saved loadout presets: each preset = 3 different guns (the knife and grenade are always carried).
	The server (LoadoutService) owns the data and replicates player attributes:
	  LoadoutPresets  "g1,g2,g3;g1,g2,g3;..."  (Count presets)
	  LoadoutActive   index of the selected preset
	  ActiveLoadout   "g1,g2,g3"  the preset used when the player spawns (WeaponService + client Loadout)
	Remotes.LoadoutPreset("Select", index) / ("Set", index, slot 1-3, gunId)  (a gun already in the preset swaps places)
]]
local Config = require(script.Parent:WaitForChild("WeaponConfig"))
local Unlocks = require(script.Parent:WaitForChild("WeaponUnlocks")) -- 2026-11-17: gun ownership (Arsenal Crates)

local P = {}
P.Count = 8
P.PerPage = 4
P.Slots = 3
P.SlotNames = { "PRIMARY", "SECONDARY", "BACKUP" }

P.Guns = {}
P.Knife = nil
for _, id in Config.Loadout do
	local w = Config.Weapons[id]
	if w.Kind == "Gun" then
		table.insert(P.Guns, id)
	elseif w.Kind == "Melee" then
		P.Knife = id
	end
end

P.Default = {
	{ "Vanguard", "Spectre", "Sentinel" },
	{ "Breacher", "Arc", "Longshot" },
	{ "Longshot", "Spectre", "Vanguard" },
	{ "Arc", "Breacher", "Sentinel" },
	{ "Sentinel", "Spectre", "Breacher" },
	{ "Vanguard", "Breacher", "Longshot" },
	{ "Spectre", "Arc", "Sentinel" },
	{ "Longshot", "Vanguard", "Arc" },
}

function P.IsGun(id)
	return type(id) == "string" and Config.Weapons[id] ~= nil and Config.Weapons[id].Kind == "Gun"
end

-- 3 distinct valid guns; gaps filled from the fallback, then from the gun list
function P.Clean(list, fallback)
	local out, used = {}, {}
	for i = 1, P.Slots do
		local id = type(list) == "table" and list[i] or nil
		if P.IsGun(id) and not used[id] then
			out[i] = id
			used[id] = true
		end
	end
	for i = 1, P.Slots do
		if not out[i] then
			for _, src in { fallback or {}, P.Guns } do
				for _, id in src do
					if P.IsGun(id) and not used[id] then
						out[i] = id
						used[id] = true
						break
					end
				end
				if out[i] then break end
			end
		end
	end
	return out
end

function P.Encode(presets)
	local parts = {}
	for i = 1, P.Count do
		parts[i] = table.concat(P.Clean(presets[i], P.Default[i]), ",")
	end
	return table.concat(parts, ";")
end

function P.Decode(s)
	local presets = {}
	local i = 0
	if type(s) == "string" then
		for chunk in (s .. ";"):gmatch("([^;]*);") do
			i += 1
			if i > P.Count then break end
			local l = {}
			for g in chunk:gmatch("[^,]+") do table.insert(l, g) end
			presets[i] = P.Clean(l, P.Default[i])
		end
	end
	for k = 1, P.Count do
		presets[k] = presets[k] or P.Clean(P.Default[k])
	end
	return presets
end

-- does this player own the gun? (Vanguard + knife are starters; the rest come from Arsenal Crates)
function P.Owns(player, id)
	if not player then return true end
	return Unlocks.OwnsFor(player, id)
end

-- weapons a life carries, slot order: knife first (key 1), then the preset's OWNED guns (keys 2-4).
-- Presets may name locked guns (the defaults do); those slots are skipped, so a life can carry 1-3 guns.
-- If none of the preset's guns are owned the starter gun is carried.
function P.ActiveList(player)
	-- 2026-11-20 first-time training (TutorialService): everyone gets the starter gun only
	if player and player:GetAttribute("InTutorial") then
		local list = {}
		if P.Knife then table.insert(list, P.Knife) end
		for _, w in Unlocks.List do
			if w.Source == "Starter" and P.IsGun(w.Id) then
				table.insert(list, w.Id)
				break
			end
		end
		return list
	end
	local s = player and player:GetAttribute("ActiveLoadout")
	local l = {}
	if type(s) == "string" then
		for g in s:gmatch("[^,]+") do table.insert(l, g) end
	end
	local guns = P.Clean(l, P.Default[1])
	local list = {}
	if P.Knife then table.insert(list, P.Knife) end
	for _, g in guns do
		if P.Owns(player, g) then table.insert(list, g) end
	end
	if #list == (if P.Knife then 1 else 0) then
		for _, w in Unlocks.List do
			if w.Source == "Starter" and P.IsGun(w.Id) then
				table.insert(list, w.Id)
				break
			end
		end
	end
	return list
end

return P
