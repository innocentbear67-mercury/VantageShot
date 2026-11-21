-- Weapon-id canon + crate-pair + signature-catalog consistency tests.
--
-- What is requireable headlessly is required for real (WeaponUnlocks,
-- Variants, SignatureCatalog — the latter through the luau.load injected
-- environment from tests/roblox_globals.luau). What is DataModel-bound at
-- load (WeaponConfig's script.Parent loader, Skins' game:GetService,
-- CrateConfig, LoadoutPresets, EquipmentCatalog) is verified by reading its
-- source literals with @lune/fs — the same approach audit/boundaries.luau
-- takes. MasteryConfig.Weapons is derived at load from WeaponUnlocks.List
-- (MasteryConfig.luau line 13), so the LoadoutOrder ⊆ WeaponUnlocks
-- assertion below covers it by construction.

local fs = require("@lune/fs")
local RG = require("./roblox_globals")

local Unlocks = require("../src/shared/Vantage/Weapons/WeaponUnlocks")
local Variants = require("../src/shared/Vantage/Mastery/Variants")

local function readFile(path: string): string
	local ok, src = pcall(fs.readFile, path)
	assert(ok, "cannot read " .. path .. ": " .. tostring(src))
	return src
end

-- ─── weapon id canon ──────────────────────────────────────────────────────
-- LoadoutOrder is a literal in the (DataModel-bound) WeaponConfig loader.
local wcSrc = readFile("src/shared/Vantage/Weapons/WeaponConfig.luau")
local loBlock = wcSrc:match("Config%.LoadoutOrder = %{(.-)%}")
assert(loBlock ~= nil, "WeaponConfig LoadoutOrder literal not found — source shape changed?")
local loadoutOrder = {}
for id in (loBlock :: string):gmatch('"([%w]+)"') do
	table.insert(loadoutOrder, id)
end
assert(#loadoutOrder > 0, "LoadoutOrder parsed empty — parser broken?")

local configFiles = {}
for _, name in fs.readDir("src/shared/Vantage/Weapons/Configs") do
	local stem = name:match("^(.-)%.luau$")
	if stem then
		configFiles[stem] = true
	end
end

local seen = {}
for _, id in loadoutOrder do
	assert(not seen[id], "LoadoutOrder contains duplicate id " .. id)
	seen[id] = true
	assert(Unlocks.ById[id] ~= nil, "LoadoutOrder id " .. id .. " is missing from WeaponUnlocks.List (and thus MasteryConfig.Weapons)")
	assert(Variants.Standard[id] ~= nil, "LoadoutOrder id " .. id .. " has no Variants.Standard entry")
	assert(configFiles[id], "LoadoutOrder id " .. id .. " has no Weapons/Configs/" .. id .. ".luau module (the loader would silently skip it)")
end

-- every weapon the unlock list can grant must be an actual configurable gun
for _, w in Unlocks.List do
	assert(
		configFiles[w.Id],
		"WeaponUnlocks id " .. w.Id .. " (Source=" .. tostring(w.Source) .. ") has no Weapons/Configs module — a crate could roll an unusable gun"
	)
end

-- ─── per-weapon skin ids, parsed from the DataModel-bound Skins.luau ──────
local skinsSrc = readFile("src/shared/Vantage/Weapons/Skins.luau")

local weaponsBlock = skinsSrc:match("Skins%.Weapons = %{(.-)%}")
assert(weaponsBlock ~= nil, "Skins.Weapons literal not found — source shape changed?")
local skinsWeapons = {}
for id in (weaponsBlock :: string):gmatch('"([%w]+)"') do
	skinsWeapons[id] = true
end
for _, id in loadoutOrder do
	assert(skinsWeapons[id], "LoadoutOrder id " .. id .. " is missing from Skins.Weapons")
end

-- line-state machine over the skin definition blocks (GUN_FINISHES are
-- shared by every gun; PREMIUM/PATTERNS are per-weapon sections; KNIFE is
-- knife-only). GUN_TEXTURES are deliberately EXCLUDED from the valid set:
-- they are asset-gated at runtime and Prime/Elite — never crate-rolled.
local sharedFinishes = {}
local premiumByWeapon = {}
local patternsByWeapon = {}
local knifeOnly = {}
local mode = nil :: string?
local currentWeapon = nil :: string?
for line in skinsSrc:gmatch("[^\r\n]+") do
	if line:match("^local GUN_FINISHES") then
		mode, currentWeapon = "finishes", nil
	elseif line:match("^local PREMIUM") then
		mode, currentWeapon = "premium", nil
	elseif line:match("^local PATTERNS") then
		mode, currentWeapon = "patterns", nil
	elseif line:match("^local KNIFE") then
		mode, currentWeapon = "knife", nil
	elseif line:match("^local GUN_TEXTURES") then
		mode, currentWeapon = "textures", nil
	elseif mode ~= nil and (line:match("^local ") or line:match("^for ") or line:match("^Skins%.")) then
		mode, currentWeapon = nil, nil
	elseif mode == "finishes" then
		local id = line:match('Id = "([%w]+)"')
		if id then
			sharedFinishes[id] = true
		end
	elseif mode == "knife" then
		local id = line:match('Id = "([%w]+)"')
		if id then
			knifeOnly[id] = true
		end
	elseif mode == "premium" then
		local w = line:match("^%s*([%w]+) = {%s*$") or line:match("%},%s*([%w]+) = {%s*$")
		if w then
			currentWeapon = w
			premiumByWeapon[w] = premiumByWeapon[w] or {}
		else
			local id = line:match('Id = "([%w]+)"')
			if id and currentWeapon then
				premiumByWeapon[currentWeapon][id] = true
			end
		end
	elseif mode == "patterns" then
		local w = line:match("^%s*([%w]+) = {%s*$") or line:match("%},%s*([%w]+) = {%s*$")
		if w then
			currentWeapon = w
			patternsByWeapon[w] = patternsByWeapon[w] or {}
		else
			local id = line:match('pattern%("([%w]+)"')
			if id and currentWeapon then
				patternsByWeapon[currentWeapon][id] = true
			end
		end
	end
end
-- parser anchors: if the source formatting shifts, these fail loudly instead
-- of every pair check passing vacuously
assert(sharedFinishes.Factory, "GUN_FINISHES parse produced no 'Factory' — Skins.luau parser broken")
assert(premiumByWeapon.Vanguard and premiumByWeapon.Vanguard.GlacierOps, "PREMIUM parse lost Vanguard/GlacierOps — parser broken")
assert(patternsByWeapon.Vanguard and patternsByWeapon.Vanguard.AmberCore, "PATTERNS parse lost Vanguard/AmberCore — parser broken")
assert(patternsByWeapon.Knife and patternsByWeapon.Knife.Tesseract, "PATTERNS parse lost Knife/Tesseract — parser broken")
assert(knifeOnly.Graphite, "KNIFE parse lost Graphite — parser broken")

local function validSkin(weapon: string, skin: string): boolean
	if weapon == "Knife" then
		return knifeOnly[skin] == true
			or (premiumByWeapon.Knife and premiumByWeapon.Knife[skin]) == true
			or (patternsByWeapon.Knife and patternsByWeapon.Knife[skin]) == true
	end
	if not skinsWeapons[weapon] then
		return false
	end
	if sharedFinishes[skin] then
		return true
	end
	local p, q = premiumByWeapon[weapon], patternsByWeapon[weapon]
	return (p and p[skin]) == true or (q and q[skin]) == true
end

-- ─── CrateConfig Weapon/Skin pairs resolve in Skins ───────────────────────
local crateSrc = readFile("src/shared/Vantage/Crates/CrateConfig.luau")
local skinPairs = 0
local equipIds = {}
-- crate `Top = { "Weapon/Skin", ... }` showcase arrays
for block in crateSrc:gmatch("Top = %{(.-)%}") do
	for w, s in (block :: string):gmatch('"([%w]+)/([%w]+)"') do
		if w == "Equipment" then
			equipIds[s] = true
		else
			skinPairs += 1
			assert(
				validSkin(w, s),
				string.format("crate showcase pair %s/%s does not resolve in Skins.luau", w, s)
			)
		end
	end
end
-- ["Weapon/Skin"] atlas / swatch keys (GunCells, Cells, Swatches)
for w, s in crateSrc:gmatch('%[%"([%w]+)/([%w]+)%"%]') do
	if w == "Equipment" then
		equipIds[s] = true
	else
		skinPairs += 1
		assert(validSkin(w, s), string.format("crate atlas/swatch key [%s/%s] does not resolve in Skins.luau", w, s))
	end
end
assert(skinPairs > 0, "no crate weapon/skin pairs parsed — CrateConfig parser broken")

-- equipment pairs resolve in the non-starter EquipmentCatalog pool
local equipSrc = readFile("src/shared/Vantage/Equipment/EquipmentCatalog.luau")
local equipBlock = equipSrc:match("Catalog%.Items = %{(.-)Catalog%.ById")
assert(equipBlock ~= nil, "EquipmentCatalog Items block not found — source shape changed?")
local equipNonStarter = {}
local curId = nil :: string?
local curStarter = false
local function flush()
	if curId and not curStarter then
		equipNonStarter[curId] = true
	end
end
for line in (equipBlock :: string):gmatch("[^\r\n]+") do
	local id = line:match('{ Id = "([%w]+)"')
	if id then
		flush()
		curId, curStarter = id, line:match("Starter = true") ~= nil
	elseif curId and line:match("Starter = true") then
		curStarter = true
	end
end
flush()
assert(equipNonStarter.Singularity, "EquipmentCatalog parse lost non-starter Singularity — parser broken")
assert(not equipNonStarter.Aegis, "EquipmentCatalog parse marked starter Aegis as non-starter — parser broken")
for id in equipIds do
	assert(
		equipNonStarter[id],
		"equipment crate pair Equipment/" .. id .. " does not resolve in the non-starter EquipmentCatalog pool"
	)
end

-- ─── LoadoutPresets default presets stay inside the canon ─────────────────
local lpSrc = readFile("src/shared/Vantage/Weapons/LoadoutPresets.luau")
local defBlock = lpSrc:match("P%.Default = %{(.-)function P%.IsGun")
assert(defBlock ~= nil, "LoadoutPresets P.Default block not found — source shape changed?")
local presetCount = 0
for a, b, c in (defBlock :: string):gmatch('{%s*"([%w]+)",%s*"([%w]+)",%s*"([%w]+)"%s*}') do
	presetCount += 1
	for _, id in { a, b, c } do
		assert(seen[id], "LoadoutPresets default names gun " .. id .. " which is not in WeaponConfig.LoadoutOrder")
	end
end
assert(presetCount == 8, "expected 8 default presets, parsed " .. presetCount .. " — LoadoutPresets parser broken?")

-- ─── SignatureCatalog ids ↔ FX module files, both directions ──────────────
local SigCatalog = RG.loadShared("src/shared/Vantage/Signatures/SignatureCatalog.luau")
local nIds = 0
for _, it in SigCatalog.List do
	nIds += 1
	local ok, isFile = pcall(fs.isFile, "src/shared/Vantage/Signatures/FX/" .. it.Id .. ".luau")
	assert(ok and isFile, "signature " .. it.Id .. " has no FX module at src/shared/Vantage/Signatures/FX/" .. it.Id .. ".luau")
end
assert(nIds > 0, "SignatureCatalog.List parsed empty")
local fxFiles = {}
local nFx = 0
for _, name in fs.readDir("src/shared/Vantage/Signatures/FX") do
	local stem = name:match("^(.-)%.luau$")
	if stem then
		fxFiles[stem] = true
		nFx += 1
	end
end
for stem in fxFiles do
	assert(
		SigCatalog.ById[stem] ~= nil,
		"FX module " .. stem .. ".luau has no SignatureCatalog entry (orphan FX file)"
	)
end

local nEquip = 0
for _ in equipIds do
	nEquip += 1
end
print(string.format(
	"config-canon: %d loadout ids, %d crate pairs, %d equipment ids, %d signatures ↔ %d FX files OK",
	#loadoutOrder, skinPairs, nEquip, nIds, nFx
))
