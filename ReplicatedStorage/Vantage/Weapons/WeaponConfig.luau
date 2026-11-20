--[[
	VANTAGE — WeaponConfig (loader)
	Single source of truth for every weapon value, shared by client (feel / prediction) and server
	(authority / validation). Each weapon lives in its own module under Weapons.Configs (the module
	name is the weapon id); this module gathers them, fills derived fields and holds the global
	rules, server validation and HUD settings.

	Per-weapon fire behaviour is described by two independent fields:
		Trigger  "Auto" | "Semi" | "Burst"     (Burst = { Count, Interval, Cooldown })
		Shot     "Hitscan" | "Pellet" | "Projectile"   (Pellet = { Count, Spread }, Projectile = {...})
	plus optional blocks: Heat (overheat / cooling), Rechamber (pump / bolt), Scope (sniper overlay).

	Units: studs, seconds, degrees. Damage in health points (shield absorbs first, see Shield).
]]

local Config = {}

-- ─── Global rules ─────────────────────────────────────────────────────────
Config.DefaultWeapon = "Vanguard"
-- slot order (keys 1-7). Weapons without a module in Configs are skipped.
-- knife on 1 (melee), guns on 2-7 (user, 2026-11-08). You still spawn holding DefaultWeapon.
Config.LoadoutOrder = { "Knife", "Vanguard", "Sentinel", "Spectre", "Breacher", "Longshot", "Arc", "Riptide", "Bulwark", "Verdict", "Quill", "Helix", "Havoc" } -- 2026-11-18 wave-1 crate guns
-- the weapon a life starts with (falls back to slot 1 if it is not in the loadout)
function Config.SpawnWeapon(): string
	if Config.Weapons[Config.DefaultWeapon] then
		return Config.DefaultWeapon
	end
	return Config.Loadout[1]
end
Config.FriendlyFire = false          -- true = teammates can damage each other (future modes)
Config.AutoReloadOnEmpty = true      -- pulling the trigger on an empty mag starts a reload
Config.AwardTeamScoreOnKill = true   -- placeholder TDM scoring (ReplicatedStorage.Vantage.Match attributes)
Config.SwitchLowerTime = 0.14        -- time to lower the current weapon before the next one rises

-- ─── Weapons (one module per weapon in Weapons.Configs) ──────────────────
Config.Weapons = {}
local folder = script.Parent:WaitForChild("Configs")
for _, m in folder:GetChildren() do
	if m:IsA("ModuleScript") then
		local w = require(m)
		w.Id = m.Name
		if w.Kind == "Gun" then
			w.Trigger = w.Trigger or "Semi"
			w.Shot = w.Shot or "Hitscan"
			w.Automatic = w.Trigger == "Auto"
			w.FalloffMinMultiplier = w.FalloffMinMultiplier or 1
		end
		Config.Weapons[m.Name] = w
	end
end
Config.Loadout = {}
for _, id in Config.LoadoutOrder do
	if Config.Weapons[id] then
		table.insert(Config.Loadout, id)
	end
end

-- ─── Server validation ──────────────────────────────────────────────────
Config.Server = {
	MaxOriginDistance = 7,          -- camera origin must be this close to the server head
	MaxRewind = 0.35,               -- lag compensation window (seconds)
	InterpolationDelay = 0.1,       -- typical Roblox replication interpolation
	HitboxScale = 1.25,             -- every body part's hit box is this much bigger (2026-11-13, HyperShot-style forgiving hits)
	HitboxPadding = 0.3,            -- studs added to body part boxes
	HeadPadding = 0.12,
	FireRateTolerance = 1.1,        -- token bucket refill = RPM * this
	FireBurstTokens = 3,            -- network jitter allowance
	RemoteRateLimit = 30,           -- max weapon messages / second / player
	ReloadLatencyAllowance = 0.12,  -- server finishes reload this much earlier to absorb latency
	MeleeRangeTolerance = 1.5,      -- studs of latency forgiveness on knife range
	MeleeCooldownTolerance = 0.06,
	AimSendRate = 12,               -- aim pitch / ADS updates per second (unreliable remote)
	DeathAnchorMaxDrop = 14,        -- airborne deaths are dropped to the ground below up to this far
	DropLifetime = 4,               -- dropped weapon lifetime (seconds)
}

-- ─── HUD ─────────────────────────────────────────────────────────────────
Config.Hud = {
	CrosshairColor = Color3.fromRGB(255, 255, 255),
	CrosshairOutline = Color3.fromRGB(10, 12, 16),
	CrosshairLength = 10.5,            -- px
	CrosshairThickness = 3,
	CrosshairGap = 6,               -- px at zero spread
	SpreadToPixels = 9,             -- px of gap per degree of spread
	FireKickPixels = 3,
	HitColor = Color3.fromRGB(255, 255, 255),
	HeadshotColor = Color3.fromRGB(255, 214, 80),
	KillColor = Color3.fromRGB(255, 70, 80),
	LowAmmoFraction = 0.25,
	LowHealth = 35,
	MatchLength = 600,              -- placeholder timer when no match system sets one
}

function Config.Get(id: string?)
	return Config.Weapons[id or Config.DefaultWeapon]
end

return Config
