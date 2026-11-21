-- Hostile-value sanity scans over the shared configs.
--
-- Weapon configs load through their REAL code: ConfigBase is loaded via the
-- injected-globals environment and each Configs/<id>.luau runs with a fake
-- `script` + `require` that hands it the real ConfigBase table, so the
-- module's own deep-merge executes and the assertions see effective values
-- (template defaults included). Movement/Ability/Grenade/EffectCatalog load
-- the same way (Enum/Color3 globals injected; AbilityConfig's script-relative
-- GrenadeConfig require is satisfied with a fake script tree).

local fs = require("@lune/fs")
local RG = require("./roblox_globals")

local NaN = 0 / 0

local function assertFinite(value: any, path: string)
	if type(value) == "number" then
		assert(value ~= NaN, path .. " is NaN")
		assert(value ~= math.huge and value ~= -math.huge, path .. " is inf")
	elseif type(value) == "table" then
		for k, v in value do
			assertFinite(v, path .. "." .. tostring(k))
		end
	end
end

-- window-like fields (cooldown / timing) must be finite and non-negative
local function assertWindows(value: any, path: string)
	if type(value) == "table" then
		for k, v in value do
			local name = tostring(k)
			if type(v) == "number" and (name:match("Cooldown") or name:match("Delay") or name:match("Interval") or name:match("Tolerance") or name:match("Grace")) then
				assert(v == v and v ~= math.huge, path .. "." .. name .. " is NaN/inf")
				assert(v >= 0, string.format("%s.%s = %s is negative", path, name, tostring(v)))
			end
			assertWindows(v, path .. "." .. name)
		end
	end
end

local function fin(v: any, path: string): number
	assert(type(v) == "number", path .. " should be a number, got " .. type(v))
	assert(v == v and v ~= math.huge and v ~= -math.huge, path .. " is NaN/inf")
	return v
end

-- ─── weapon configs (real ConfigBase merge) ───────────────────────────────
local ConfigBase = RG.loadShared("src/shared/Vantage/Weapons/ConfigBase.luau")
local function loadWeapon(fileName: string): any
	local fakeRequire = function(name: string)
		if name == "ConfigBase" then
			return ConfigBase
		end
		error("sanity test require: unexpected module " .. tostring(name), 0)
	end
	local fakeScript = { Parent = { Parent = { ConfigBase = "ConfigBase" } } }
	return RG.loadShared("src/shared/Vantage/Weapons/Configs/" .. fileName, { script = fakeScript, require = fakeRequire })
end

local gunCount = 0
for _, name in fs.readDir("src/shared/Vantage/Weapons/Configs") do
	local stem = name:match("^(.-)%.luau$")
	if stem then
		local w = loadWeapon(name)
		local id = w.Id or stem
		assert(w.Kind == "Gun" or w.Kind == "Melee", id .. " has unexpected Kind " .. tostring(w.Kind))
		assertFinite(w, id)
		if w.Kind == "Gun" then
			gunCount += 1
			assert(fin(w.Damage, id .. ".Damage") >= 0, id .. ".Damage is negative")
			assert(fin(w.RPM, id .. ".RPM") > 0, id .. ".RPM must be positive")
			local mag = fin(w.MagazineSize, id .. ".MagazineSize")
			assert(mag >= 0, id .. ".MagazineSize is negative")
			assert(fin(w.ReserveAmmo, id .. ".ReserveAmmo") >= 0, id .. ".ReserveAmmo is negative")
			assert(fin(w.HeadshotMultiplier, id .. ".HeadshotMultiplier") >= 0, id .. ".HeadshotMultiplier is negative")
			assert(
				fin(w.FalloffStart, id .. ".FalloffStart") <= fin(w.FalloffEnd, id .. ".FalloffEnd"),
				id .. " falloff window is inverted"
			)
			local fm = fin(w.FalloffMinMultiplier, id .. ".FalloffMinMultiplier")
			assert(fm > 0 and fm <= 1, string.format("%s.FalloffMinMultiplier %s outside (0, 1]", id, tostring(fm)))
			if mag == 0 then
				-- energy weapons: heat instead of ammo (Arc, Helix)
				assert(w.Energy == true, id .. " has MagazineSize 0 but is not Energy")
				assert(type(w.Heat) == "table", id .. " has MagazineSize 0 but no Heat block")
				assert(fin(w.Heat.PerShot, id .. ".Heat.PerShot") > 0, id .. ".Heat.PerShot must be positive")
				assert(fin(w.Heat.CoolRate, id .. ".Heat.CoolRate") > 0, id .. ".Heat.CoolRate must be positive")
			else
				assert(fin(w.ReloadTime, id .. ".ReloadTime") > 0, id .. ".ReloadTime must be positive")
			end
		else -- Melee (Knife shape: Primary / Secondary strike blocks)
			local p, s = w.Primary, w.Secondary
			assert(p and s, id .. " melee config missing Primary/Secondary")
			assert(fin(p.Damage, id .. ".Primary.Damage") >= 0, id .. ".Primary.Damage negative")
			assert(fin(s.Damage, id .. ".Secondary.Damage") >= 0, id .. ".Secondary.Damage negative")
			assert(fin(s.BackstabDamage, id .. ".Secondary.BackstabDamage") >= 0, id .. ".BackstabDamage negative")
			assert(fin(p.Cooldown, id .. ".Primary.Cooldown") > 0, id .. ".Primary.Cooldown must be positive")
			assert(fin(s.Cooldown, id .. ".Secondary.Cooldown") > 0, id .. ".Secondary.Cooldown must be positive")
			assert(fin(p.Range, id .. ".Primary.Range") > 0, id .. ".Primary.Range must be positive")
			local cone = fin(p.ConeAngle, id .. ".Primary.ConeAngle")
			assert(cone > 0 and cone <= 90, id .. ".Primary.ConeAngle outside (0, 90]")
		end
	end
end
assert(gunCount >= 10, "expected at least 10 gun configs, found " .. gunCount)

-- ─── MovementConfig ────────────────────────────────────────────────────────
local Movement = RG.loadShared("src/shared/Vantage/Movement/MovementConfig.luau")
assertFinite(Movement, "MovementConfig")
assertWindows(Movement, "MovementConfig")
assert(fin(Movement.RunSpeed, "MovementConfig.RunSpeed") > 0, "RunSpeed must be positive")
assert(fin(Movement.JumpHeight, "MovementConfig.JumpHeight") > 0, "JumpHeight must be positive")

-- ─── AbilityConfig (GrenadeConfig wired through its script-relative require) ─
local Grenade = RG.loadShared("src/shared/Vantage/Grenade/GrenadeConfig.luau")
local leaf = { WaitForChild = function(_self: any, _name: string)
	return "GrenadeConfig"
end }
local fakeTree = { WaitForChild = function(_self: any, _name: string)
	return leaf
end }
local abilityRequire = function(name: string)
	if name == "GrenadeConfig" then
		return Grenade
	end
	error("sanity test require: unexpected module " .. tostring(name), 0)
end
local Ability = RG.loadShared("src/shared/Vantage/Abilities/AbilityConfig.luau", {
	script = { Parent = { Parent = fakeTree } },
	require = abilityRequire,
})
assert(
	Ability.Abilities.Grenade.Cooldown == Grenade.Cooldown,
	"AbilityConfig did not copy GrenadeConfig.Cooldown through its script-relative require"
)
local grapple = Ability.Abilities.Grapple
assert(fin(grapple.Cooldown, "AbilityConfig.Grapple.Cooldown") > 0, "grapple cooldown must be positive")
assert(fin(grapple.MissCooldown, "AbilityConfig.Grapple.MissCooldown") >= 0, "grapple miss cooldown negative")
assert(fin(grapple.Range, "AbilityConfig.Grapple.Range") > 0, "grapple range must be positive")
assertFinite(Ability, "AbilityConfig")
assertWindows(Ability, "AbilityConfig")

-- ─── GrenadeConfig ─────────────────────────────────────────────────────────
assert(fin(Grenade.Cooldown, "GrenadeConfig.Cooldown") > 0, "grenade cooldown must be positive")
assert(fin(Grenade.Fuse, "GrenadeConfig.Fuse") > 0, "grenade fuse must be positive")
assert(fin(Grenade.Radius, "GrenadeConfig.Radius") > 0, "grenade radius must be positive")
assert(fin(Grenade.MaxDamage, "GrenadeConfig.MaxDamage") > 0, "grenade MaxDamage must be positive")
assert(fin(Grenade.ServerTolerance, "GrenadeConfig.ServerTolerance") >= 0, "grenade server tolerance negative")
assertFinite(Grenade, "GrenadeConfig")

-- ─── EffectCatalog: picker removed, the default is what every kill plays ──
local Effects = RG.loadShared("src/shared/Vantage/Elimination/EffectCatalog.luau")
assert(Effects.PlayerChoice == false, "this test pins the picker-removed contract; PlayerChoice is no longer false")
assert(Effects.ById[Effects.Default] ~= nil, "Catalog.Default '" .. tostring(Effects.Default) .. "' is not a real effect id")
local syntheticPlayers = {
	nil,
	{},
	{ GetAttribute = function(_self: any, _k: string)
		return nil
	end },
	{ GetAttribute = function(_self: any, _k: string)
		return "overload"
	end }, -- a saved style is ignored while the picker is off
	{ GetAttribute = function(_self: any, _k: string)
		return NaN
	end },
	{ GetAttribute = function(_self: any, _k: string)
		return ""
	end, ActiveLoadout = "Vanguard,Spectre,Sentinel" },
}
for i, player in syntheticPlayers do
	local ok, res = pcall(Effects.ForPlayer, player)
	assert(ok, "ForPlayer errored on synthetic input " .. tostring(i) .. ": " .. tostring(res))
	assert(res == Effects.Default, string.format(
		"ForPlayer(synthetic %d) returned %s, expected the default %s",
		i, tostring(res), tostring(Effects.Default)
	))
end
assert(Effects.Owns(nil, Effects.Default), "the default effect must be owned even with no player")
assert(not Effects.Owns(nil, "overload"), "with the picker removed nothing but the default can be owned")
for _, e in Effects.Effects do
	local hide = fin(e.Hide, "Effects." .. e.Id .. ".Hide")
	local dur = fin(e.Dur, "Effects." .. e.Id .. ".Dur")
	assert(hide >= 0, e.Id .. ".Hide negative")
	assert(dur > hide, e.Id .. ": Dur must exceed Hide (Timing would end before it starts)")
	local tHide, tEnd = Effects.Timing(e.Id)
	assert(fin(tHide, "Timing." .. e.Id) > 0, e.Id .. " played hide time must be positive")
	assert(fin(tEnd, "Timing." .. e.Id .. ".end") > tHide, e.Id .. " played end must exceed played hide")
end

print(string.format(
	"config-sanity: %d gun configs + knife, Movement/Ability/Grenade windows finite, EffectCatalog default pinned (%d effects)",
	gunCount, #Effects.Effects
))
