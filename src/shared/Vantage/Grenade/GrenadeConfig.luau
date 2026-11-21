--!strict
--[[
	VANTAGE — GrenadeConfig (VX-G1 frag)
	Shared by GrenadeServer (authority: cooldown, flight, fuse, damage) and GrenadeClient
	(input, effects). Built 2026-11-11, see project doc claude/grenade-plan.md.

	Throw input: press FIRE and AIM together (mouse: both buttons at once; gamepad: R2 + L2).
	WeaponInput treats the two presses as one throw when they land within ChordWindow seconds
	of each other. Holding AIM first and then firing is still a normal aimed shot.

	Units: studs, seconds, studs/second.
]]

local Config = {}

Config.Id = "FragGrenade"           -- weapon id stamped on hits (kill feed shows a blast)
Config.DisplayName = "VX-G1 FRAG"
Config.ChordWindow = 0.08            -- both buttons within this = a throw (hip-fire waits this long)

Config.Cooldown = 20                 -- one grenade, regenerates this long after each throw
Config.ServerTolerance = 0.25        -- latency slack on the server's cooldown check
Config.RefillOnRespawn = true        -- a fresh life starts with the grenade ready

-- flight (server-owned physics part; Workspace.Gravity applies)
Config.ThrowSpeed = 104              -- along the look direction (88 -> 104, user 2026-11-11: more range)
Config.ThrowLift = 30                -- extra upward speed, so a level throw arcs (26 -> 30)
Config.InheritVelocity = 0.5         -- share of the thrower's own movement added
Config.SpawnAhead = 2.2              -- studs in front of the eyes (pulled back if a wall is closer)
Config.Spin = 14                     -- rad/s tumble
Config.GroundDrag = 4.5              -- per second: rolling friction once it is on the ground (settles in a few studs)
Config.MaxLookDeviation = 25         -- degrees: claimed look direction vs the server's view of the head

-- fuse and blast
Config.Fuse = 2.2                    -- seconds from the throw
-- user 2026-11-11: blast radius x2 (15 -> 30) and lethal to any enemy it reaches (full shield +
-- full health = 200), anywhere inside the radius. Cover still protects: the server's line-of-sight
-- check from the blast to the body / head is unchanged. Friendly fire / self damage unchanged.
Config.MaxDamage = 1000              -- one-shot: far above 100 shield + 100 health
Config.InnerRadius = 30              -- full damage all the way to the edge (no falloff)
Config.Radius = 30                   -- no damage past this
Config.EdgeFraction = 0.15           -- share of MaxDamage at the outer edge
Config.VehicleDamage = 120           -- to a vehicle at the centre (same falloff)
Config.SelfDamage = false            -- DamageService never damages the thrower

-- effects (client)
Config.Colors = {
	Lime = Color3.fromRGB(182, 255, 0),
	Core = Color3.fromRGB(230, 255, 170),
}
Config.Sounds = {
	Throw = { Id = "rbxassetid://9125484367", Volume = 0.25, Speed = 2.2 },
	Explode = { Id = "rbxassetid://18245316227", Volume = 0.75, Speed = 1.12 },
}
Config.ShakeRadius = 70              -- camera shake if the blast is this close

return Config
