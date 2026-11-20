--[[
	VANTAGE — SkinFX (shared, cosmetic only)
	Per-skin firing effects + idle auras, escalating by rarity (Rare → Epic → Mythic → Legendary →
	Exclusive → Godly). A skin opts in with `FX = "<id>"` in its Skins entry.
	  • WeaponEffects (client) calls Flash / Tracer / Impact for shots from a skinned weapon.
	  • Skins.Apply calls AttachIdle / ClearIdle so the aura shows on viewmodels AND on the
	    server third-person model (replicates to everyone).
	Never touches firing, recoil, reload or ADS.
]]
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local C, V = Color3.fromRGB, Vector3.new
local NS, NK, CS, NR = NumberSequence.new, NumberSequenceKeypoint.new, ColorSequence.new, NumberRange.new
local VFXKit = require(script.Parent:WaitForChild("VFXKit"))
local KT = VFXKit.Tex
local TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	FireSpark = "rbxasset://textures/particles/fire_sparks_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Implode = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}

local SkinFX = {}
SkinFX.Version = 1

local function fade(a, b) return NS({ NK(0, a or 0), NK(1, b or 1) }) end
local function grow(a, b) return NS({ NK(0, a), NK(1, b) }) end
-- emitter preset: { tex, color(s), size0, size1, life0, life1, speed0, speed1, spread, count, extra }
local function E(t) return t end

SkinFX.Defs = {
	-- RARE · Glacier Ops: crisp ice flash, frost tracer, frost-puff impact. No idle aura (finish-only tier).
	-- RARE · Glacier Ops (shot overhaul stage 2, 2026-11-18): arctic ops. Hexagonal ice-crystal flash
	-- with a frost puff and crystal splinters; an ice-blue beam shedding fine frost flakes and a mist
	-- that hangs; impacts burst ice shards and leave a frost ring on the surface; the barrel frosts up
	-- (vapour) once the gun is sustained.
	Glacier = {
		Light = C(170, 225, 255), LightBright = 3.6,
		Flash = {
			E{ Texture = KT.Hex, Flip = "Grid2x2", Color = CS(C(245, 252, 255), C(140, 210, 255)), Size = grow(0.5, 0.18), Transparency = fade(0.05, 1), Life = NR(0.045, 0.06), Speed = NR(0, 0), Spread = 0, Count = 1, Rotation = NR(0, 60), LockedToPart = true },
			E{ Texture = TEX.Smoke, Color = CS(C(232, 247, 255)), Size = grow(0.12, 0.5), Transparency = fade(0.5, 1), Life = NR(0.3, 0.45), Speed = NR(1, 2.5), Spread = 18, Count = 1 },
			E{ Texture = KT.Shard, Flip = "Grid2x2", Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(C(235, 250, 255), C(150, 215, 255)), Size = grow(0.15, 0.02), Life = NR(0.1, 0.2), Speed = NR(8, 14), Spread = 30, Count = 4 },
		},
		Tracer = { Laser = { Color = C(150, 220, 255), Core = C(230, 250, 255), Width = 0.08,
			Motes = { C(240, 252, 255), C(140, 205, 255), Texture = KT.Flake, Flip = "Grid2x2", Size = 0.09, Density = 0.4, Accel = V(0, -3, 0) },
			Mist = { C(228, 245, 255), C(170, 215, 255), Texture = TEX.Smoke, Size = 0.45, Density = 0.28, Accel = V(0, -0.3, 0), Life = { 0.5, 0.8 }, Transp = 0.62, Emission = 0.3 } },
			Core = C(205, 240, 255), Width = 0.035 },
		Impact = {
			E{ Texture = KT.Shard, Flip = "Grid2x2", Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(C(240, 252, 255), C(140, 210, 255)), Size = grow(0.3, 0.05), Life = NR(0.2, 0.4), Speed = NR(8, 16), Spread = 55, Count = 8, Accel = V(0, -30, 0) },
			E{ Texture = TEX.Smoke, Color = CS(C(225, 242, 255)), Size = grow(0.25, 0.9), Transparency = fade(0.45, 1), Life = NR(0.35, 0.6), Speed = NR(1, 3), Spread = 30, Count = 2, Drag = 4 },
			E{ Texture = KT.Ripple, Color = CS(C(200, 240, 255)), Size = grow(0.3, 2.0), Transparency = fade(0.2, 1), Life = NR(0.25, 0.25), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Decal = { Texture = KT.Ripple, Color = C(185, 228, 255), Size = 1.2, Grow = 1.3, Life = 1.2, Transp = 0.2 },
		Sustain = { From = 4, E = E{ Texture = TEX.Smoke, Color = CS(C(236, 248, 255)), Size = grow(0.1, 0.45), Transparency = fade(0.55, 1), Life = NR(0.5, 0.8), Speed = NR(0.3, 0.8), Spread = 25, Count = 1, Accel = V(0, -0.6, 0), Dir = "Top" } },
	},
	-- EPIC · Archangel: gold starburst flash, gilded tracer with drifting motes, halo-ring impact, gold mote aura.
	Archangel = {
		Light = C(255, 214, 140), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 236, 170), C(255, 190, 90)), Size = grow(0.7, 0.15), Life = NR(0.05, 0.07), Speed = NR(0, 0), Spread = 0, Count = 1, Rotation = NR(0, 360) },
			E{ Texture = TEX.Fire, Color = CS(C(255, 250, 230), C(255, 200, 110)), Size = grow(0.36, 0.08), Life = NR(0.035, 0.05), Speed = NR(0.5, 1.5), Spread = 8, Count = 2 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 220, 140)), Size = grow(0.07, 0), Life = NR(0.2, 0.4), Speed = NR(3, 8), Spread = 60, Count = 5, Drag = 3 },
		},
		Tracer = { Laser = { Color = C(255, 205, 100), Width = 0.1, Rings = { Mesh = "Halo", Color = C(255, 220, 130), Spacing = 7, Size = 0.75 }, Motes = { C(255, 250, 225), C(255, 205, 100), Size = 0.18, Density = 0.6 } }, Projectile = { Kind = "Halo", Scale = 2.0, Speed = 230, Color = C(255, 214, 120), Light = C(255, 214, 140),
			Trail = E{ Texture = TEX.Spark, Color = CS(C(255, 236, 170), C(255, 196, 90)), Size = grow(0.12, 0), Life = NR(0.25, 0.45), Speed = NR(0, 0.4), Spread = 180, Rate = 140 } },
		Core = C(255, 246, 220), Glow = C(255, 196, 90), GlowWidth = 0.12, Width = 0.04,
			Trail = E{ Texture = TEX.Spark, Color = CS(C(255, 214, 140)), Size = grow(0.08, 0), Life = NR(0.25, 0.5), Speed = NR(0, 0.5), Spread = 180, Rate = 260 } },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 214, 140)), Size = grow(0.2, 1.4), Transparency = fade(0.2, 1), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 226, 160)), Size = grow(0.1, 0), Life = NR(0.2, 0.4), Speed = NR(4, 10), Spread = 60, Count = 8, Drag = 2 },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(255, 220, 150)), Size = NS({ NK(0, 0), NK(0.4, 0.07), NK(1, 0) }), Life = NR(1.2, 2.2), Speed = NR(0.1, 0.35), Spread = 180, Rate = 5, Accel = V(0, 0.25, 0) },
			{ At = "Muzzle", Texture = TEX.Spark, Color = CS(C(140, 210, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(0.8, 1.4), Speed = NR(0.05, 0.2), Spread = 180, Rate = 3 },
		},
	},
	-- MYTHIC · Molten Sovereign: three-claw fire burst, ember-streak tracer with smoke, lava-splash impact,
	-- burning horn-tip flames + rising embers.
	Molten = {
		Light = C(255, 120, 40), LightBright = 4.6,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 220, 120), C(255, 70, 10)), Size = grow(0.7, 0.15), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 14, Count = 3 },
			E{ Texture = TEX.Fire, Color = CS(C(255, 150, 40), C(160, 20, 0)), Size = grow(0.35, 0.05), Life = NR(0.08, 0.12), Speed = NR(6, 10), Spread = 34, Count = 3, Rotation = NR(-30, 30) },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 170, 60)), Size = grow(0.08, 0), Life = NR(0.3, 0.6), Speed = NR(4, 12), Spread = 45, Count = 8, Accel = V(0, 6, 0) },
			E{ Texture = TEX.Smoke, Color = CS(C(40, 30, 28)), Size = grow(0.3, 1.0), Transparency = fade(0.6, 1), Life = NR(0.4, 0.7), Speed = NR(1, 2), Spread = 20, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 120, 20), Core = C(255, 240, 180), Width = 0.13, Strands = { { Color = C(255, 70, 10), Radius = 0.09, Twist = 0.9, Width = 0.05 } }, Fire = { C(255, 140, 30), C(190, 30, 0), Emission = 0.5, Size = 0.45, Density = 1.1, Spread = 0.25 } }, Projectile = { Kind = "Fireball", Scale = 1.9, Speed = 210, Color = C(255, 100, 25), Light = C(255, 120, 40),
			Trail = E{ Texture = TEX.Fire, Color = CS(C(255, 220, 120), C(255, 70, 10)), Size = grow(0.38, 0.08), Life = NR(0.18, 0.3), Speed = NR(0, 0.6), Spread = 25, Rate = 160, Rotation = NR(0, 360) } },
		Core = C(255, 200, 110), Glow = C(255, 90, 20), GlowWidth = 0.14, Width = 0.05,
			Trail = E{ Texture = TEX.FireSpark, Color = CS(C(255, 140, 40)), Size = grow(0.09, 0), Life = NR(0.3, 0.6), Speed = NR(0, 1), Spread = 180, Rate = 320, Accel = V(0, 3, 0) } },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 180, 70), C(200, 30, 0)), Size = grow(0.5, 0.1), Life = NR(0.12, 0.2), Speed = NR(1, 3), Spread = 30, Count = 3 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 150, 40)), Size = grow(0.1, 0), Life = NR(0.3, 0.6), Speed = NR(6, 16), Spread = 55, Count = 12, Accel = V(0, -30, 0) },
		},
		Idle = {
			{ At = "Muzzle", Texture = TEX.Fire, Color = CS(C(255, 170, 60), C(255, 50, 0)), Size = grow(0.18, 0.02), Life = NR(0.25, 0.4), Speed = NR(0.4, 1), Spread = 15, Rate = 10, Dir = "Top" },
			{ At = "Root", Texture = TEX.FireSpark, Color = CS(C(255, 140, 40)), Size = grow(0.05, 0), Life = NR(0.8, 1.6), Speed = NR(0.4, 1.2), Spread = 50, Rate = 9, Dir = "Top", Accel = V(0, 1.5, 0) },
		},
	},
	-- LEGENDARY · Event Horizon: implosion flash, plasma beam tracer, mini-singularity impact,
	-- swirling vortex + plasma motes.
	Horizon = {
		Light = C(220, 80, 255), LightBright = 4.2,
		Flash = {
			E{ Texture = TEX.Implode, Color = CS(C(255, 120, 240), C(120, 40, 255)), Size = grow(0.9, 0), Life = NR(0.09, 0.09), Speed = NR(0, 0), Spread = 0, Count = 1, Rotation = NR(0, 360) },
			E{ Texture = TEX.Spark, Color = CS(C(255, 230, 255)), Size = grow(0.3, 0.05), Life = NR(0.04, 0.05), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Shock, Color = CS(C(190, 90, 255)), Size = grow(0.15, 0.9), Transparency = fade(0.1, 1), Life = NR(0.15, 0.15), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(185, 80, 255), Core = C(255, 225, 255), Width = 0.12, Inner = C(0, 0, 0), Strands = { { Color = C(255, 120, 235), Radius = 0.16, Twist = 0.75, Width = 0.045 }, { Color = C(130, 60, 255), Radius = 0.16, Twist = 0.75, Width = 0.045, Phase = math.pi } }, Rings = { Mesh = "Ring", Color = C(200, 100, 255), Spacing = 10, Size = 0.8 } }, Projectile = { Kind = "BlackHole", Scale = 1.9, Speed = 190, Color = C(190, 90, 255), Light = C(170, 80, 255),
			Trail = E{ Texture = TEX.Vortex, Color = CS(C(200, 110, 255), C(90, 30, 160)), Size = grow(0.45, 0.1), Life = NR(0.25, 0.4), Speed = NR(0, 0), Spread = 0, Rate = 60, Rotation = NR(0, 360) } },
		Core = C(255, 235, 255), Glow = C(200, 60, 255), GlowWidth = 0.16, Width = 0.03,
			Trail = E{ Texture = TEX.Spark, Color = CS(C(240, 90, 220), C(130, 60, 255)), Size = grow(0.08, 0), Life = NR(0.3, 0.6), Speed = NR(0, 0.3), Spread = 180, Rate = 300 } },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(200, 80, 255), C(20, 0, 40)), Size = grow(1.2, 0), Life = NR(0.25, 0.25), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Shock, Color = CS(C(255, 110, 230)), Size = grow(0.1, 1.2), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(220, 120, 255)), Size = grow(0.08, 0), Life = NR(0.2, 0.4), Speed = NR(-6, -2), Spread = 90, Count = 8 },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Vortex, Color = CS(C(200, 90, 255)), Size = grow(0.35, 0.05), Transparency = fade(0.5, 1), Life = NR(0.6, 0.9), Speed = NR(0, 0), Spread = 0, Rate = 3, Rotation = NR(0, 360), RotSpeed = NR(-240, -120) },
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(240, 90, 220), C(130, 60, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.3, 0.7), Spread = 180, Rate = 7 },
		},
	},
	-- EXCLUSIVE · Kitsune // Lunar Festival: foxfire petal flash, spirit-wisp tracer, foxfire + blossom
	-- impact, tail wisps + drifting petals.
	Kitsune = {
		Light = C(90, 190, 255), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(220, 245, 255), C(40, 140, 255)), Size = grow(0.6, 0.12), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 20, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Spark, Color = CS(C(255, 170, 200)), Size = grow(0.09, 0.02), Life = NR(0.4, 0.8), Speed = NR(2, 6), Spread = 70, Count = 6, Drag = 3, Accel = V(0, -2, 0) },
		},
		Tracer = { Laser = { Color = C(60, 200, 255), Core = C(225, 250, 255), Width = 0.12, Strands = { { Color = C(230, 250, 255), Radius = 0.2, Twist = 0.6, Width = 0.05 }, { Color = C(60, 170, 255), Radius = 0.2, Twist = 0.6, Width = 0.05, Phase = math.pi * 0.66 }, { Color = C(140, 230, 255), Radius = 0.2, Twist = 0.6, Width = 0.05, Phase = math.pi * 1.33 } }, Fire = { C(150, 230, 255), C(30, 110, 255), Emission = 0.7, Size = 0.4, Density = 0.9, Spread = 0.3 } }, Projectile = { Kind = "Head", Mesh = "FoxHead", Scale = 1.0, Speed = 220, Light = C(110, 210, 255), Start = 1.6,
			Trail = E{ Texture = TEX.Fire, Color = CS(C(170, 235, 255), C(60, 150, 255)), Size = grow(0.3, 0.05), Life = NR(0.2, 0.35), Speed = NR(0, 0.4), Spread = 20, Rate = 140, Rotation = NR(0, 360) } },
		Core = C(235, 250, 255), Glow = C(60, 170, 255), GlowWidth = 0.14, Width = 0.035,
			Trail = E{ Texture = TEX.Fire, Color = CS(C(150, 220, 255), C(30, 110, 255)), Size = grow(0.12, 0), Transparency = fade(0.3, 1), Life = NR(0.2, 0.4), Speed = NR(0, 0.5), Spread = 180, Rate = 260 } },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(200, 240, 255), C(30, 120, 255)), Size = grow(0.55, 0.05), Life = NR(0.15, 0.25), Speed = NR(1, 3), Spread = 30, Count = 3 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 175, 205)), Size = grow(0.1, 0.03), Life = NR(0.6, 1.1), Speed = NR(2, 6), Spread = 70, Count = 6, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = {
			{ At = "Shoulder", Texture = TEX.Fire, Color = CS(C(170, 230, 255), C(30, 110, 255)), Size = grow(0.22, 0.02), Transparency = fade(0.2, 1), Life = NR(0.4, 0.7), Speed = NR(0.5, 1.2), Spread = 25, Rate = 9, Dir = "Back" },
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(255, 180, 210)), Size = grow(0.06, 0.02), Life = NR(1.5, 2.5), Speed = NR(0.2, 0.5), Spread = 180, Rate = 3, Accel = V(0, -0.4, 0) },
		},
	},
	-- GODLY · Golden Dragon Emperor: dragon-breath flash, golden fire trail, gold-fire burst impact,
	-- permanent aura (fire from the jaws, rising embers, gold glints, warm glow).
	Dragon = {
		Light = C(255, 170, 70), LightBright = 5.2,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 236, 160), C(255, 90, 10)), Size = grow(1.0, 0.2), Life = NR(0.07, 0.11), Speed = NR(3, 7), Spread = 12, Count = 4 },
			E{ Texture = TEX.Shock, Color = CS(C(255, 200, 100)), Size = grow(0.2, 1.3), Transparency = fade(0.15, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 225, 140)), Size = grow(0.1, 0), Life = NR(0.3, 0.6), Speed = NR(4, 12), Spread = 50, Count = 10, Drag = 2 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 150, 50)), Size = grow(0.08, 0), Life = NR(0.4, 0.8), Speed = NR(3, 10), Spread = 60, Count = 8, Accel = V(0, 5, 0) },
		},
		Tracer = { Laser = { Color = C(255, 45, 35), Core = C(255, 225, 130), Width = 0.15, Strands = { { Color = C(255, 205, 80), Radius = 0.24, Twist = 0.55, Width = 0.07 }, { Color = C(255, 90, 30), Radius = 0.24, Twist = 0.55, Width = 0.06, Phase = math.pi } }, Fire = { C(255, 170, 50), C(200, 25, 10), Emission = 0.55, Size = 0.5, Density = 1.2, Spread = 0.35 }, Motes = { C(255, 240, 180), C(255, 170, 40), Size = 0.2, Density = 0.6 } }, Projectile = { Kind = "Head", Mesh = "DragonHead", Scale = 1.05, Speed = 220, Light = C(255, 160, 60), Start = 1.6,
			Trail = E{ Texture = TEX.Fire, Color = CS(C(255, 230, 140), C(255, 90, 20)), Size = grow(0.36, 0.06), Life = NR(0.22, 0.36), Speed = NR(0, 0.5), Spread = 20, Rate = 150, Rotation = NR(0, 360) } },
		Core = C(255, 240, 190), Glow = C(255, 140, 30), GlowWidth = 0.2, Width = 0.06,
			Trail = E{ Texture = TEX.Fire, Color = CS(C(255, 210, 110), C(255, 60, 0)), Size = grow(0.16, 0), Transparency = fade(0.2, 1), Life = NR(0.2, 0.35), Speed = NR(0, 1), Spread = 180, Rate = 360, Accel = V(0, 4, 0) } },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 230, 140), C(255, 60, 0)), Size = grow(0.8, 0.1), Life = NR(0.15, 0.25), Speed = NR(1, 4), Spread = 35, Count = 4 },
			E{ Texture = TEX.Shock, Color = CS(C(255, 200, 100)), Size = grow(0.2, 1.6), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 220, 140)), Size = grow(0.12, 0), Life = NR(0.3, 0.6), Speed = NR(5, 14), Spread = 60, Count = 12, Accel = V(0, -25, 0) },
		},
		Idle = {
			{ At = "Muzzle", Texture = TEX.Fire, Color = CS(C(255, 210, 110), C(255, 50, 0)), Size = grow(0.24, 0.03), Life = NR(0.3, 0.5), Speed = NR(0.6, 1.4), Spread = 20, Rate = 14, Dir = "Top" },
			{ At = "Root", Texture = TEX.FireSpark, Color = CS(C(255, 160, 50)), Size = grow(0.06, 0), Life = NR(1, 2), Speed = NR(0.4, 1.2), Spread = 70, Rate = 14, Dir = "Top", Accel = V(0, 1.6, 0) },
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(255, 225, 150)), Size = NS({ NK(0, 0), NK(0.4, 0.08), NK(1, 0) }), Life = NR(0.8, 1.6), Speed = NR(0.2, 0.5), Spread = 180, Rate = 6 },
			{ At = "Root", Light = { Color = C(255, 170, 80), Brightness = 1.4, Range = 6 } },
		},
	},
	-- BR-07 Sentinel ladder
	Storm = {
		Light = C(110, 180, 255), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(220, 240, 255), C(70, 160, 255)), Size = grow(0.5, 0.05), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 30, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(120, 190, 255)), Size = grow(0.15, 0.9), Transparency = fade(0.2, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(70, 170, 255), Core = C(235, 248, 255), Width = 0.1, Strands = { { Color = C(170, 225, 255), Radius = 0.11, Twist = 2.6, Width = 0.03 }, { Color = C(80, 150, 255), Radius = 0.09, Twist = 3.1, Width = 0.025, Phase = 2 } }, Motes = { C(230, 245, 255), C(90, 170, 255), Size = 0.14, Density = 0.5 } }, Core = C(235, 248, 255), Width = 0.035 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(140, 200, 255)), Size = grow(0.1, 1.1), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(200, 235, 255)), Size = grow(0.1, 0), Life = NR(0.2, 0.4), Speed = NR(4, 10), Spread = 70, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(170, 220, 255), C(70, 150, 255)), Size = NS({ NK(0, 0), NK(0.3, 0.07), NK(1, 0) }), Life = NR(0.2, 0.4), Speed = NR(0, 0.2), Spread = 180, Rate = 6 } },
	},
	Leviathan = {
		Light = C(60, 220, 210), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(210, 255, 250), C(30, 200, 200)), Size = grow(0.5, 0.08), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Spark, Color = CS(C(190, 255, 250)), Size = grow(0.07, 0.02), Life = NR(0.5, 0.9), Speed = NR(1, 4), Spread = 60, Count = 6, Accel = V(0, 2, 0) },
		},
		Tracer = { Laser = { Color = C(30, 220, 200), Core = C(215, 255, 250), Width = 0.13, Strands = { { Color = C(30, 120, 255), Radius = 0.11, Twist = 0.9, Width = 0.05 } }, Motes = { C(210, 255, 250), C(40, 200, 220), Size = 0.16, Density = 0.7, Accel = V(0, 1.5, 0) } }, Core = C(215, 255, 250), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(60, 230, 220), C(0, 40, 60)), Size = grow(0.9, 0), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(200, 255, 250)), Size = grow(0.1, 0.03), Life = NR(0.4, 0.8), Speed = NR(2, 6), Spread = 70, Count = 8, Accel = V(0, 3, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(190, 255, 250), C(40, 200, 220)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.2, 0.5), Spread = 40, Rate = 5, Dir = "Top" } },
	},
	Celestial = {
		Light = C(220, 210, 255), LightBright = 4.2,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 250, 230), C(255, 210, 120)), Size = grow(0.6, 0.06), Life = NR(0.06, 0.1), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(140, 170, 255)), Size = grow(0.15, 1.0), Transparency = fade(0.2, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 215, 120), Core = C(255, 255, 245), Width = 0.12, Inner = C(20, 30, 90), Strands = { { Color = C(100, 140, 255), Radius = 0.16, Twist = 0.7, Width = 0.045 }, { Color = C(255, 240, 200), Radius = 0.16, Twist = 0.7, Width = 0.04, Phase = math.pi } }, Rings = { Mesh = "Ring", Color = C(255, 215, 130), Spacing = 9, Size = 0.7 }, Motes = { C(255, 255, 255), C(130, 160, 255), Size = 0.18, Density = 0.6 } }, Core = C(255, 255, 245), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 220, 140)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 255, 255), C(130, 160, 255)), Size = grow(0.12, 0), Life = NR(0.4, 0.8), Speed = NR(3, 8), Spread = 80, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 255, 255), C(140, 170, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.07), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 6 } },
	},
	Sakura = {
		Light = C(255, 150, 190), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 245), C(255, 110, 160)), Size = grow(0.55, 0.06), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Spark, Color = CS(C(255, 180, 210)), Size = grow(0.1, 0.03), Life = NR(0.5, 1), Speed = NR(2, 6), Spread = 70, Count = 8, Drag = 3, Accel = V(0, -2, 0) },
		},
		Tracer = { Laser = { Color = C(255, 90, 150), Core = C(255, 238, 246), Width = 0.12, Strands = { { Color = C(255, 195, 220), Radius = 0.18, Twist = 0.6, Width = 0.045 }, { Color = C(200, 20, 50), Radius = 0.18, Twist = 0.6, Width = 0.045, Phase = math.pi } }, Motes = { C(255, 200, 225), C(255, 110, 160), Size = 0.26, Density = 0.9, Accel = V(0, -1.5, 0) } }, Core = C(255, 238, 246), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 150, 190)), Size = grow(0.1, 1.1), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 190, 215)), Size = grow(0.12, 0.04), Life = NR(0.7, 1.2), Speed = NR(2, 6), Spread = 80, Count = 10, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 190, 215)), Size = grow(0.07, 0.03), Life = NR(1.5, 2.5), Speed = NR(0.2, 0.5), Spread = 180, Rate = 4, Accel = V(0, -0.4, 0) } },
	},
	Phoenix = {
		Light = C(255, 210, 130), LightBright = 5.2,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 250, 220), C(255, 150, 40)), Size = grow(0.55, 0.1), Life = NR(0.05, 0.08), Speed = NR(2, 5), Spread = 12, Count = 3 },
			E{ Texture = TEX.Shock, Color = CS(C(255, 230, 160)), Size = grow(0.15, 0.9), Transparency = fade(0.3, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 210, 110)), Size = grow(0.08, 0), Life = NR(0.4, 0.8), Speed = NR(3, 10), Spread = 60, Count = 8, Accel = V(0, 5, 0) },
		},
		Tracer = { Laser = { Color = C(255, 190, 70), Core = C(255, 252, 230), Width = 0.16, Strands = { { Color = C(255, 250, 230), Radius = 0.26, Twist = 0.5, Width = 0.06 }, { Color = C(255, 200, 80), Radius = 0.26, Twist = 0.5, Width = 0.06, Phase = math.pi * 0.66 }, { Color = C(255, 130, 30), Radius = 0.26, Twist = 0.5, Width = 0.05, Phase = math.pi * 1.33 } }, Fire = { C(255, 225, 140), C(255, 120, 20), Emission = 0.5, Size = 0.38, Density = 0.6, Spread = 0.3 }, Motes = { C(255, 252, 225), C(255, 190, 80), Size = 0.22, Density = 0.7 } }, Core = C(255, 252, 230), Width = 0.06 },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 245, 200), C(255, 120, 20)), Size = grow(0.8, 0.1), Life = NR(0.15, 0.25), Speed = NR(1, 4), Spread = 35, Count = 4 },
			E{ Texture = TEX.Shock, Color = CS(C(255, 230, 160)), Size = grow(0.2, 1.7), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 240, 180)), Size = grow(0.12, 0), Life = NR(0.4, 0.8), Speed = NR(5, 14), Spread = 60, Count = 12, Accel = V(0, 6, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.FireSpark, Color = CS(C(255, 210, 110)), Size = grow(0.06, 0), Life = NR(1, 2), Speed = NR(0.4, 1.2), Spread = 70, Rate = 12, Dir = "Top", Accel = V(0, 1.6, 0) },
			{ At = "Root", Light = { Color = C(255, 210, 130), Brightness = 1.4, Range = 6 } },
		},
	},
	-- SMG-07 Spectre ladder (Tripo shells, 2026-11-16)
	Plague = {
		Light = C(140, 255, 80), LightBright = 3.6,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(225, 255, 190), C(90, 255, 40)), Size = grow(0.4, 0.05), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 25, Count = 3, Rotation = NR(0, 360) },
			E{ Texture = TEX.Smoke, Color = CS(C(130, 255, 80), C(40, 90, 30)), Size = grow(0.12, 0.45), Transparency = fade(0.55, 1), Life = NR(0.3, 0.5), Speed = NR(0.5, 1.5), Spread = 30, Count = 2 },
		},
		Tracer = { Laser = { Color = C(110, 255, 50), Core = C(235, 255, 215), Width = 0.09, Strands = { { Color = C(60, 190, 30), Radius = 0.08, Twist = 2.2, Width = 0.025 }, { Color = C(200, 255, 130), Radius = 0.08, Twist = 2.2, Width = 0.02, Phase = math.pi } }, Motes = { C(205, 255, 165), C(80, 220, 40), Size = 0.12, Density = 0.4, Accel = V(0, 1.2, 0) } }, Core = C(235, 255, 215), Width = 0.03 },
		Impact = {
			E{ Texture = TEX.Smoke, Color = CS(C(140, 255, 90), C(40, 80, 20)), Size = grow(0.3, 1.0), Transparency = fade(0.35, 1), Life = NR(0.4, 0.6), Speed = NR(0.5, 2), Spread = 60, Count = 3 },
			E{ Texture = TEX.Spark, Color = CS(C(205, 255, 150)), Size = grow(0.08, 0.02), Life = NR(0.4, 0.8), Speed = NR(1, 4), Spread = 70, Count = 6, Accel = V(0, 3, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(190, 255, 140), C(80, 220, 40)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(0.9, 1.6), Speed = NR(0.2, 0.5), Spread = 30, Rate = 5, Dir = "Top" } },
	},
	Fenrir = {
		Light = C(150, 215, 255), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(240, 250, 255), C(110, 190, 255)), Size = grow(0.45, 0.05), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(170, 225, 255)), Size = grow(0.12, 0.8), Transparency = fade(0.25, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(120, 200, 255), Core = C(242, 250, 255), Width = 0.1, Strands = { { Color = C(225, 245, 255), Radius = 0.1, Twist = 1.4, Width = 0.035 }, { Color = C(60, 130, 255), Radius = 0.1, Twist = 1.4, Width = 0.03, Phase = math.pi } }, Motes = { C(240, 250, 255), C(130, 200, 255), Size = 0.13, Density = 0.6, Accel = V(0, -2, 0) } }, Core = C(242, 250, 255), Width = 0.035 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(170, 225, 255)), Size = grow(0.12, 1.1), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(235, 248, 255), C(120, 190, 255)), Size = grow(0.1, 0.02), Life = NR(0.4, 0.8), Speed = NR(3, 9), Spread = 70, Count = 10, Accel = V(0, -12, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(240, 250, 255), C(140, 205, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5, Accel = V(0, -0.5, 0) } },
	},
	Anubis = {
		Light = C(255, 210, 120), LightBright = 4.2,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 245, 210), C(255, 190, 70)), Size = grow(0.5, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(90, 130, 255)), Size = grow(0.12, 0.9), Transparency = fade(0.25, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 200, 90), Core = C(255, 250, 228), Width = 0.11, Inner = C(20, 40, 140), Strands = { { Color = C(50, 100, 255), Radius = 0.13, Twist = 0.8, Width = 0.04 }, { Color = C(255, 232, 160), Radius = 0.13, Twist = 0.8, Width = 0.035, Phase = math.pi } }, Rings = { Mesh = "Ring", Color = C(255, 205, 110), Spacing = 9, Size = 0.5 }, Motes = { C(255, 238, 175), C(215, 165, 75), Size = 0.1, Density = 0.5 } }, Core = C(255, 250, 228), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 210, 120)), Size = grow(0.15, 1.2), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 170), C(80, 120, 255)), Size = grow(0.1, 0), Life = NR(0.4, 0.8), Speed = NR(3, 8), Spread = 80, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 232, 160), C(90, 130, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 6 } },
	},
	Calavera = {
		Light = C(255, 165, 70), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 230, 150), C(255, 110, 20)), Size = grow(0.4, 0.08), Life = NR(0.05, 0.08), Speed = NR(2, 4), Spread = 15, Count = 2 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 90, 190), C(40, 220, 230)), Size = grow(0.08, 0.03), Life = NR(0.4, 0.8), Speed = NR(2, 6), Spread = 70, Count = 6, Drag = 3, Accel = V(0, -2, 0) },
		},
		Tracer = { Laser = { Color = C(255, 140, 30), Core = C(255, 246, 222), Width = 0.11, Strands = { { Color = C(255, 60, 180), Radius = 0.15, Twist = 0.7, Width = 0.04 }, { Color = C(40, 220, 230), Radius = 0.15, Twist = 0.7, Width = 0.04, Phase = math.pi } }, Motes = { C(255, 185, 60), C(255, 110, 20), Size = 0.2, Density = 0.7, Accel = V(0, -1.5, 0) } }, Core = C(255, 246, 222), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 150, 50)), Size = grow(0.1, 1.1), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 90, 190), C(40, 220, 230)), Size = grow(0.12, 0.04), Life = NR(0.7, 1.2), Speed = NR(2, 6), Spread = 80, Count = 10, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.FireSpark, Color = CS(C(255, 200, 110)), Size = grow(0.05, 0), Life = NR(0.8, 1.5), Speed = NR(0.3, 0.8), Spread = 40, Rate = 6, Dir = "Top", Accel = V(0, 1, 0) } },
	},
	Wraith = {
		Light = C(190, 160, 255), LightBright = 4.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(250, 245, 255), C(160, 110, 255)), Size = grow(0.5, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Smoke, Color = CS(C(190, 160, 255), C(60, 30, 120)), Size = grow(0.12, 0.5), Transparency = fade(0.5, 1), Life = NR(0.35, 0.55), Speed = NR(0.5, 1.5), Spread = 30, Count = 2 },
		},
		Tracer = { Laser = { Color = C(170, 120, 255), Core = C(250, 246, 255), Width = 0.13, Inner = C(25, 12, 50), Strands = { { Color = C(242, 236, 255), Radius = 0.2, Twist = 0.6, Width = 0.05 }, { Color = C(150, 90, 255), Radius = 0.2, Twist = 0.6, Width = 0.05, Phase = math.pi * 0.66 }, { Color = C(100, 60, 210), Radius = 0.2, Twist = 0.6, Width = 0.04, Phase = math.pi * 1.33 } }, Fire = { C(225, 210, 255), C(120, 60, 255), Emission = 0.5, Size = 0.28, Density = 0.45, Spread = 0.25 }, Motes = { C(248, 244, 255), C(160, 110, 255), Size = 0.18, Density = 0.6, Accel = V(0, 1, 0) } }, Core = C(250, 246, 255), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(190, 150, 255), C(30, 10, 60)), Size = grow(0.9, 0), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(245, 240, 255), C(150, 100, 255)), Size = grow(0.12, 0), Life = NR(0.4, 0.8), Speed = NR(3, 9), Spread = 70, Count = 10, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(245, 240, 255), C(150, 100, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.07), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.4), Spread = 60, Rate = 6, Dir = "Top", Accel = V(0, 0.6, 0) },
			{ At = "Root", Light = { Color = C(190, 160, 255), Brightness = 1.2, Range = 5 } },
		},
	},
	-- SG Breacher ladder (Tripo shells, 2026-11-17). Nine pellets per shot, so each beam is slim
	-- and sheds little: the spread of nine reads as the effect.
	Ironclad = {
		Light = C(255, 170, 80), LightBright = 3.6,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 230, 160), C(255, 120, 30)), Size = grow(0.55, 0.1), Life = NR(0.05, 0.08), Speed = NR(2, 4), Spread = 20, Count = 2 },
			E{ Texture = TEX.Smoke, Color = CS(C(235, 230, 225), C(150, 140, 130)), Size = grow(0.2, 0.9), Transparency = fade(0.4, 1), Life = NR(0.4, 0.7), Speed = NR(1, 2.5), Spread = 25, Count = 3 },
		},
		Tracer = { Laser = { Color = C(255, 160, 50), Core = C(255, 245, 220), Width = 0.06, Strands = { { Color = C(255, 210, 120), Radius = 0.06, Twist = 1.6, Width = 0.018 }, { Color = C(200, 90, 30), Radius = 0.06, Twist = 1.6, Width = 0.018, Phase = math.pi } }, Motes = { C(240, 235, 230), C(170, 160, 150), Size = 0.14, Density = 0.15, Accel = V(0, 1, 0) } }, Core = C(255, 245, 220), Width = 0.02 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 180, 90)), Size = grow(0.1, 0.8), Transparency = fade(0.25, 1), Life = NR(0.15, 0.15), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 220, 150), C(255, 120, 30)), Size = grow(0.07, 0), Life = NR(0.3, 0.6), Speed = NR(3, 8), Spread = 70, Count = 5, Accel = V(0, -10, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Smoke, Color = CS(C(240, 235, 230)), Size = grow(0.05, 0.25), Transparency = fade(0.6, 1), Life = NR(1, 1.6), Speed = NR(0.2, 0.5), Spread = 20, Rate = 3, Dir = "Top", Accel = V(0, 0.8, 0) } },
	},
	Minotaur = {
		Light = C(255, 100, 40), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 220, 140), C(255, 50, 10)), Size = grow(0.6, 0.1), Life = NR(0.06, 0.09), Speed = NR(2, 4), Spread = 20, Count = 3 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 180, 90)), Size = grow(0.08, 0), Life = NR(0.3, 0.6), Speed = NR(4, 9), Spread = 40, Count = 6, Accel = V(0, -6, 0) },
		},
		Tracer = { Laser = { Color = C(255, 60, 25), Core = C(255, 235, 200), Width = 0.07, Strands = { { Color = C(205, 130, 60), Radius = 0.07, Twist = 1.2, Width = 0.022 } }, Motes = { C(255, 200, 110), C(255, 70, 20), Texture = TEX.FireSpark, Size = 0.1, Density = 0.2, Accel = V(0, 2, 0) } }, Core = C(255, 235, 200), Width = 0.025 },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 210, 130), C(255, 50, 10)), Size = grow(0.5, 0.1), Life = NR(0.12, 0.2), Speed = NR(1, 3), Spread = 35, Count = 2 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 190, 100)), Size = grow(0.08, 0), Life = NR(0.4, 0.7), Speed = NR(3, 9), Spread = 60, Count = 6, Accel = V(0, 4, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.FireSpark, Color = CS(C(255, 150, 70)), Size = grow(0.05, 0), Life = NR(0.8, 1.4), Speed = NR(0.3, 0.8), Spread = 50, Rate = 6, Dir = "Top", Accel = V(0, 1.2, 0) } },
	},
	Gorgon = {
		Light = C(80, 255, 160), LightBright = 4.2,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(230, 255, 230), C(40, 230, 120)), Size = grow(0.5, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(255, 215, 110)), Size = grow(0.12, 0.9), Transparency = fade(0.25, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(40, 230, 120), Core = C(240, 255, 235), Width = 0.07, Inner = C(255, 200, 80), Strands = { { Color = C(255, 210, 90), Radius = 0.09, Twist = 1.0, Width = 0.025 }, { Color = C(20, 160, 90), Radius = 0.09, Twist = 1.0, Width = 0.022, Phase = math.pi } }, Motes = { C(220, 225, 215), C(140, 150, 140), Size = 0.08, Density = 0.2, Accel = V(0, -3, 0) } }, Core = C(240, 255, 235), Width = 0.025 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(80, 255, 160)), Size = grow(0.12, 1.0), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Smoke, Color = CS(C(200, 205, 200), C(120, 125, 120)), Size = grow(0.2, 0.6), Transparency = fade(0.5, 1), Life = NR(0.4, 0.6), Speed = NR(0.5, 1.5), Spread = 60, Count = 2 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 230, 150), C(60, 240, 140)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 6 } },
	},
	Krampus = {
		Light = C(255, 110, 100), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 245, 240), C(255, 40, 50)), Size = grow(0.5, 0.06), Life = NR(0.05, 0.08), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Spark, Color = CS(C(240, 250, 255)), Size = grow(0.06, 0.03), Life = NR(0.6, 1.1), Speed = NR(2, 5), Spread = 70, Count = 8, Drag = 3, Accel = V(0, -2, 0) },
		},
		Tracer = { Laser = { Color = C(255, 40, 55), Core = C(255, 245, 240), Width = 0.07, Strands = { { Color = C(40, 200, 90), Radius = 0.09, Twist = 1.1, Width = 0.024 }, { Color = C(245, 250, 255), Radius = 0.09, Twist = 1.1, Width = 0.022, Phase = math.pi } }, Motes = { C(250, 252, 255), C(210, 230, 255), Size = 0.1, Density = 0.25, Accel = V(0, -1.5, 0) } }, Core = C(255, 245, 240), Width = 0.025 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 70, 80)), Size = grow(0.1, 1.0), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(250, 252, 255), C(60, 220, 110)), Size = grow(0.1, 0.03), Life = NR(0.6, 1.0), Speed = NR(2, 6), Spread = 80, Count = 8, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(250, 252, 255), C(200, 225, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5, Accel = V(0, -0.6, 0) } },
	},
	Cerberus = {
		Light = C(110, 190, 255), LightBright = 4.8,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(225, 245, 255), C(40, 120, 255)), Size = grow(0.6, 0.1), Life = NR(0.06, 0.09), Speed = NR(2, 4), Spread = 20, Count = 3 },
			E{ Texture = TEX.Shock, Color = CS(C(255, 210, 110)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(60, 150, 255), Core = C(245, 250, 255), Width = 0.08, Inner = C(255, 200, 90), Strands = { { Color = C(230, 245, 255), Radius = 0.11, Twist = 0.9, Width = 0.026 }, { Color = C(40, 110, 255), Radius = 0.11, Twist = 0.9, Width = 0.026, Phase = math.pi * 0.66 }, { Color = C(255, 205, 100), Radius = 0.11, Twist = 0.9, Width = 0.022, Phase = math.pi * 1.33 } }, Fire = { C(200, 230, 255), C(40, 110, 255), Emission = 0.5, Size = 0.18, Density = 0.2, Spread = 0.15 }, Motes = { C(235, 245, 255), C(90, 160, 255), Size = 0.1, Density = 0.2, Accel = V(0, 1.5, 0) } }, Core = C(245, 250, 255), Width = 0.03 },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(220, 240, 255), C(40, 110, 255)), Size = grow(0.6, 0.1), Life = NR(0.15, 0.22), Speed = NR(1, 3), Spread = 35, Count = 2 },
			E{ Texture = TEX.Spark, Color = CS(C(235, 245, 255), C(255, 200, 90)), Size = grow(0.1, 0), Life = NR(0.4, 0.8), Speed = NR(3, 9), Spread = 70, Count = 8, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.FireSpark, Color = CS(C(150, 210, 255), C(50, 120, 255)), Size = grow(0.06, 0), Life = NR(1, 1.8), Speed = NR(0.3, 0.8), Spread = 60, Rate = 8, Dir = "Top", Accel = V(0, 1.2, 0) },
			{ At = "Root", Light = { Color = C(110, 190, 255), Brightness = 1.2, Range = 5 } },
		},
	},
	-- LR Longshot ladder (Tripo shells, 2026-11-17): one slow shot, so full-weight beams
	Strix = {
		Light = C(150, 190, 255), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(240, 248, 255), C(110, 160, 255)), Size = grow(0.55, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(170, 205, 255)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(110, 165, 255), Core = C(242, 248, 255), Width = 0.12, Strands = { { Color = C(220, 230, 245), Radius = 0.14, Twist = 0.8, Width = 0.04 }, { Color = C(80, 140, 255), Radius = 0.14, Twist = 0.8, Width = 0.035, Phase = math.pi } }, Motes = { C(235, 242, 255), C(130, 170, 255), Size = 0.16, Density = 0.4, Accel = V(0, -1.5, 0) } }, Core = C(242, 248, 255), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(170, 205, 255)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(240, 248, 255), C(110, 160, 255)), Size = grow(0.1, 0.02), Life = NR(0.5, 0.9), Speed = NR(2, 7), Spread = 80, Count = 10, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(230, 240, 255), C(120, 170, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5, Accel = V(0, -0.4, 0) } },
	},
	Sabretooth = {
		Light = C(255, 150, 60), LightBright = 4.2,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 225, 150), C(255, 90, 20)), Size = grow(0.7, 0.12), Life = NR(0.06, 0.1), Speed = NR(2, 4), Spread = 20, Count = 3 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 190, 100)), Size = grow(0.09, 0), Life = NR(0.4, 0.8), Speed = NR(4, 10), Spread = 40, Count = 10, Accel = V(0, -5, 0) },
		},
		Tracer = { Laser = { Color = C(255, 130, 30), Core = C(255, 242, 214), Width = 0.14, Strands = { { Color = C(240, 230, 210), Radius = 0.16, Twist = 0.7, Width = 0.045 }, { Color = C(255, 80, 10), Radius = 0.16, Twist = 0.7, Width = 0.04, Phase = math.pi } }, Fire = { C(255, 205, 120), C(255, 80, 15), Emission = 0.5, Size = 0.3, Density = 0.45, Spread = 0.22 }, Motes = { C(255, 200, 110), C(255, 90, 20), Texture = TEX.FireSpark, Size = 0.12, Density = 0.5, Accel = V(0, 2.5, 0) } }, Core = C(255, 242, 214), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Fire, Color = CS(C(255, 215, 140), C(255, 70, 10)), Size = grow(0.8, 0.12), Life = NR(0.15, 0.22), Speed = NR(1, 3), Spread = 35, Count = 3 },
			E{ Texture = TEX.FireSpark, Color = CS(C(255, 190, 100)), Size = grow(0.1, 0), Life = NR(0.5, 0.9), Speed = NR(3, 10), Spread = 70, Count = 12, Accel = V(0, 4, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.FireSpark, Color = CS(C(255, 160, 70)), Size = grow(0.05, 0), Life = NR(0.8, 1.5), Speed = NR(0.3, 0.8), Spread = 50, Rate = 7, Dir = "Top", Accel = V(0, 1.2, 0) } },
	},
	Jaguar = {
		Light = C(255, 215, 130), LightBright = 4.4,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 248, 220), C(255, 190, 70)), Size = grow(0.6, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(60, 240, 220)), Size = grow(0.14, 1.1), Transparency = fade(0.25, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(40, 230, 210), Core = C(245, 255, 250), Width = 0.14, Inner = C(255, 200, 80), Strands = { { Color = C(255, 210, 100), Radius = 0.17, Twist = 0.8, Width = 0.045 }, { Color = C(20, 180, 170), Radius = 0.17, Twist = 0.8, Width = 0.04, Phase = math.pi } }, Rings = { Mesh = "Ring", Color = C(255, 205, 110), Spacing = 9, Size = 0.55 }, Motes = { C(255, 238, 175), C(255, 180, 60), Size = 0.11, Density = 0.5 } }, Core = C(245, 255, 250), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 210, 120)), Size = grow(0.15, 1.4), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 170), C(60, 240, 220)), Size = grow(0.11, 0), Life = NR(0.4, 0.8), Speed = NR(3, 9), Spread = 80, Count = 12 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 232, 160), C(60, 240, 220)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 6 } },
	},
	Watcher = {
		Light = C(90, 240, 225), LightBright = 5.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(225, 255, 250), C(40, 220, 210)), Size = grow(0.65, 0.06), Life = NR(0.05, 0.1), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Implode, Color = CS(C(255, 90, 220), C(20, 0, 40)), Size = grow(1.0, 0), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(40, 220, 210), Core = C(240, 255, 252), Width = 0.17, Inner = C(20, 0, 40), Strands = { { Color = C(80, 255, 235), Radius = 0.22, Twist = 0.6, Width = 0.05 }, { Color = C(255, 70, 210), Radius = 0.22, Twist = 0.6, Width = 0.05, Phase = math.pi * 0.66 }, { Color = C(220, 190, 110), Radius = 0.22, Twist = 0.6, Width = 0.04, Phase = math.pi * 1.33 } }, Rings = { Mesh = "Halo", Color = C(80, 255, 235), Spacing = 11, Size = 0.6 }, Fire = { C(160, 255, 245), C(255, 60, 200), Emission = 0.5, Size = 0.26, Density = 0.4, Spread = 0.22 }, Motes = { C(20, 10, 30), C(60, 240, 225), Size = 0.16, Density = 0.6, Accel = V(0, 0.8, 0) } }, Core = C(240, 255, 252), Width = 0.06 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(80, 255, 235), C(30, 0, 50)), Size = grow(1.1, 0), Life = NR(0.24, 0.24), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(220, 255, 250), C(255, 80, 210)), Size = grow(0.12, 0), Life = NR(0.5, 0.9), Speed = NR(3, 9), Spread = 70, Count = 12, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(200, 255, 250), C(255, 80, 210)), Size = NS({ NK(0, 0), NK(0.4, 0.07), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.4), Spread = 60, Rate = 7, Dir = "Top", Accel = V(0, 0.6, 0) },
			{ At = "Root", Light = { Color = C(90, 240, 225), Brightness = 1.3, Range = 6 } },
		},
	},
	Heartbreaker = {
		Light = C(255, 120, 180), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 240, 248), C(255, 60, 140)), Size = grow(0.55, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(255, 110, 180)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 70, 150), Core = C(255, 240, 248), Width = 0.13, Inner = C(170, 0, 40), Strands = { { Color = C(220, 20, 60), Radius = 0.16, Twist = 0.8, Width = 0.045 }, { Color = C(255, 230, 240), Radius = 0.16, Twist = 0.8, Width = 0.04, Phase = math.pi } }, Rings = { Mesh = "Halo", Color = C(255, 120, 190), Spacing = 10, Size = 0.45 }, Motes = { C(255, 150, 200), C(220, 30, 80), Size = 0.16, Density = 0.5, Accel = V(0, -1.2, 0) } }, Core = C(255, 240, 248), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 110, 180)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 200, 225), C(220, 30, 80)), Size = grow(0.12, 0.04), Life = NR(0.7, 1.2), Speed = NR(2, 6), Spread = 80, Count = 12, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 180, 215), C(255, 60, 140)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 6, Accel = V(0, -0.5, 0) } },
	},
	Diver = {
		Light = C(255, 180, 80), LightBright = 3.0,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 240, 200), C(255, 170, 60)), Size = grow(0.4, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(255, 175, 60), Core = C(255, 245, 220), Width = 0.07, Strands = { { Color = C(60, 200, 190), Radius = 0.1, Twist = 0.9, Width = 0.025 }, { Color = C(255, 210, 120), Radius = 0.1, Twist = 0.9, Width = 0.022, Phase = math.pi } }, Motes = { C(200, 240, 255), C(80, 200, 220), Size = 0.08, Density = 0.15, Accel = V(0, 1.2, 0) } }, Core = C(255, 245, 220), Width = 0.035 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 200, 120)), Size = grow(0.12, 0.9), Transparency = fade(0.25, 1), Life = NR(0.15, 0.15), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 230, 170), C(60, 200, 190)), Size = grow(0.09, 0), Life = NR(0.3, 0.6), Speed = NR(2, 6), Spread = 80, Count = 6, Accel = V(0, 2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(200, 240, 255), C(80, 200, 220)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 4, Accel = V(0, 0.6, 0) } },
	},
	Hammerhead = {
		Light = C(255, 70, 90), LightBright = 3.4,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 220, 225), C(255, 40, 70)), Size = grow(0.45, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(255, 40, 70), Core = C(255, 235, 238), Width = 0.08, Inner = C(120, 0, 20), Strands = { { Color = C(170, 175, 185), Radius = 0.11, Twist = 1.0, Width = 0.025 } }, Motes = { C(255, 90, 110), C(140, 0, 20), Size = 0.07, Density = 0.15 } }, Core = C(255, 235, 238), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 80, 100)), Size = grow(0.12, 1.0), Transparency = fade(0.2, 1), Life = NR(0.16, 0.16), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 200, 205), C(255, 30, 60)), Size = grow(0.1, 0), Life = NR(0.3, 0.6), Speed = NR(3, 8), Spread = 70, Count = 8 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 160, 170), C(255, 40, 70)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 4 } },
	},
	Atlantis = {
		Light = C(110, 255, 225), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(240, 255, 250), C(40, 230, 200)), Size = grow(0.5, 0.05), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(255, 215, 130)), Size = grow(0.1, 0.8), Transparency = fade(0.3, 1), Life = NR(0.1, 0.1), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(40, 230, 200), Core = C(240, 255, 250), Width = 0.09, Inner = C(255, 200, 90), Strands = { { Color = C(255, 210, 110), Radius = 0.12, Twist = 0.8, Width = 0.028 }, { Color = C(30, 170, 160), Radius = 0.12, Twist = 0.8, Width = 0.025, Phase = math.pi } }, Rings = { Mesh = "Ring", Color = C(255, 205, 110), Spacing = 13, Size = 0.35 }, Motes = { C(255, 238, 175), C(60, 230, 210), Size = 0.08, Density = 0.2 } }, Core = C(240, 255, 250), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(120, 255, 230)), Size = grow(0.13, 1.1), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 170), C(40, 230, 200)), Size = grow(0.1, 0), Life = NR(0.35, 0.7), Speed = NR(3, 8), Spread = 80, Count = 8 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 232, 160), C(60, 240, 220)), Size = NS({ NK(0, 0), NK(0.4, 0.055), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Sunset = {
		Light = C(255, 170, 110), LightBright = 3.6,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 240, 220), C(255, 120, 80)), Size = grow(0.48, 0.05), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(90, 230, 220)), Size = grow(0.1, 0.8), Transparency = fade(0.3, 1), Life = NR(0.1, 0.1), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 120, 80), Core = C(255, 240, 225), Width = 0.085, Inner = C(255, 60, 90), Strands = { { Color = C(60, 225, 215), Radius = 0.12, Twist = 0.8, Width = 0.026 }, { Color = C(255, 220, 160), Radius = 0.12, Twist = 0.8, Width = 0.022, Phase = math.pi } }, Rings = { Mesh = "Halo", Color = C(255, 170, 120), Spacing = 13, Size = 0.35 }, Motes = { C(255, 220, 180), C(255, 110, 80), Size = 0.09, Density = 0.18, Accel = V(0, -1, 0) } }, Core = C(255, 240, 225), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 160, 110)), Size = grow(0.13, 1.1), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 230, 200), C(60, 225, 215)), Size = grow(0.1, 0.03), Life = NR(0.5, 0.9), Speed = NR(2, 6), Spread = 80, Count = 8, Drag = 2, Accel = V(0, -2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 210, 170), C(255, 120, 80)), Size = NS({ NK(0, 0), NK(0.4, 0.055), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5, Accel = V(0, -0.4, 0) } },
	},
	Kraken = {
		Light = C(90, 220, 255), LightBright = 4.4,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(220, 250, 255), C(40, 220, 255)), Size = grow(0.55, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Implode, Color = CS(C(170, 110, 255), C(10, 0, 30)), Size = grow(0.8, 0), Life = NR(0.15, 0.15), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(40, 220, 255), Core = C(235, 252, 255), Width = 0.1, Inner = C(20, 0, 50), Strands = { { Color = C(90, 240, 255), Radius = 0.14, Twist = 0.7, Width = 0.028 }, { Color = C(170, 100, 255), Radius = 0.14, Twist = 0.7, Width = 0.028, Phase = math.pi * 0.66 }, { Color = C(220, 190, 110), Radius = 0.14, Twist = 0.7, Width = 0.022, Phase = math.pi * 1.33 } }, Fire = { C(150, 240, 255), C(140, 70, 255), Emission = 0.4, Size = 0.16, Density = 0.2, Spread = 0.15 }, Motes = { C(10, 20, 40), C(60, 220, 255), Size = 0.1, Density = 0.25, Accel = V(0, 0.8, 0) } }, Core = C(235, 252, 255), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(80, 230, 255), C(30, 0, 60)), Size = grow(0.9, 0), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(210, 250, 255), C(170, 100, 255)), Size = grow(0.11, 0), Life = NR(0.4, 0.8), Speed = NR(3, 8), Spread = 70, Count = 10, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(190, 245, 255), C(170, 100, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.4), Spread = 60, Rate = 6, Dir = "Top", Accel = V(0, 0.6, 0) },
			{ At = "Root", Light = { Color = C(90, 220, 255), Brightness = 1.2, Range = 5 } },
		},
	},
	Warden = {
		Light = C(170, 200, 255), LightBright = 3.2,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(240, 248, 255), C(120, 170, 255)), Size = grow(0.55, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(120, 170, 255), Core = C(245, 250, 255), Width = 0.09, Strands = { { Color = C(255, 60, 70), Radius = 0.13, Twist = 0.9, Width = 0.028 }, { Color = C(60, 120, 255), Radius = 0.13, Twist = 0.9, Width = 0.028, Phase = math.pi } }, Motes = { C(235, 245, 255), C(120, 170, 255), Size = 0.08, Density = 0.15 } }, Core = C(245, 250, 255), Width = 0.04 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(180, 210, 255)), Size = grow(0.14, 1.1), Transparency = fade(0.25, 1), Life = NR(0.16, 0.16), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(240, 248, 255), C(120, 170, 255)), Size = grow(0.1, 0), Life = NR(0.3, 0.6), Speed = NR(3, 8), Spread = 80, Count = 8 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(220, 235, 255), C(120, 170, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 4 } },
	},
	Rhino = {
		Light = C(240, 240, 90), LightBright = 3.6,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 255, 210), C(220, 230, 40)), Size = grow(0.6, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(220, 230, 40), Core = C(255, 255, 220), Width = 0.1, Inner = C(90, 100, 20), Strands = { { Color = C(150, 160, 140), Radius = 0.14, Twist = 1.0, Width = 0.03 } }, Motes = { C(255, 250, 150), C(200, 210, 30), Size = 0.09, Density = 0.2 } }, Core = C(255, 255, 220), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(240, 250, 90)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 255, 200), C(220, 230, 40)), Size = grow(0.11, 0), Life = NR(0.35, 0.7), Speed = NR(3, 9), Spread = 75, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(250, 250, 160), C(220, 230, 40)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Oni = {
		Light = C(190, 120, 255), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(245, 235, 255), C(170, 80, 255)), Size = grow(0.6, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(255, 215, 130)), Size = grow(0.12, 1.0), Transparency = fade(0.3, 1), Life = NR(0.11, 0.11), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(170, 80, 255), Core = C(248, 240, 255), Width = 0.11, Inner = C(255, 200, 90), Strands = { { Color = C(255, 210, 110), Radius = 0.15, Twist = 0.8, Width = 0.032 }, { Color = C(120, 40, 200), Radius = 0.15, Twist = 0.8, Width = 0.03, Phase = math.pi } }, Rings = { Mesh = "Ring", Color = C(255, 205, 110), Spacing = 12, Size = 0.45 }, Motes = { C(230, 200, 255), C(170, 80, 255), Size = 0.09, Density = 0.2 } }, Core = C(248, 240, 255), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(190, 120, 255)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 230, 170), C(170, 80, 255)), Size = grow(0.11, 0), Life = NR(0.4, 0.8), Speed = NR(3, 9), Spread = 80, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 225, 160), C(170, 80, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Lantern = {
		Light = C(255, 150, 60), LightBright = 3.8,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 200), C(255, 130, 30)), Size = grow(0.6, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(150, 255, 60)), Size = grow(0.1, 0.9), Transparency = fade(0.3, 1), Life = NR(0.1, 0.1), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 130, 30), Core = C(255, 240, 210), Width = 0.1, Inner = C(120, 30, 0), Strands = { { Color = C(150, 255, 60), Radius = 0.14, Twist = 0.8, Width = 0.03 }, { Color = C(120, 40, 160), Radius = 0.14, Twist = 0.8, Width = 0.026, Phase = math.pi } }, Rings = { Mesh = "Halo", Color = C(255, 150, 50), Spacing = 12, Size = 0.4 }, Fire = { C(255, 190, 80), C(255, 80, 0), Emission = 0.5, Size = 0.16, Density = 0.18, Spread = 0.15 }, Motes = { C(255, 170, 60), C(120, 255, 60), Size = 0.09, Density = 0.18, Accel = V(0, 1, 0) } }, Core = C(255, 240, 210), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 150, 50)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 220, 150), C(150, 255, 60)), Size = grow(0.11, 0.03), Life = NR(0.5, 0.9), Speed = NR(2, 7), Spread = 80, Count = 10, Accel = V(0, 2, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 180, 80), C(150, 255, 60)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5, Accel = V(0, 0.5, 0) } },
	},
	Behemoth = {
		Light = C(255, 215, 120), LightBright = 4.6,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 250, 230), C(255, 190, 60)), Size = grow(0.7, 0.07), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Implode, Color = CS(C(255, 230, 150), C(40, 20, 0)), Size = grow(0.9, 0), Life = NR(0.15, 0.15), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 190, 60), Core = C(255, 252, 240), Width = 0.12, Inner = C(40, 20, 0), Strands = { { Color = C(255, 230, 150), Radius = 0.17, Twist = 0.7, Width = 0.034 }, { Color = C(255, 140, 20), Radius = 0.17, Twist = 0.7, Width = 0.032, Phase = math.pi * 0.66 }, { Color = C(255, 255, 255), Radius = 0.17, Twist = 0.7, Width = 0.024, Phase = math.pi * 1.33 } }, Fire = { C(255, 240, 180), C(255, 130, 20), Emission = 0.5, Size = 0.2, Density = 0.22, Spread = 0.18 }, Motes = { C(30, 20, 10), C(255, 200, 80), Size = 0.11, Density = 0.25, Accel = V(0, 0.8, 0) } }, Core = C(255, 252, 240), Width = 0.055 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(255, 220, 130), C(50, 20, 0)), Size = grow(1.1, 0), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 250, 220), C(255, 160, 30)), Size = grow(0.12, 0), Life = NR(0.5, 0.9), Speed = NR(3, 9), Spread = 70, Count = 12, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(255, 240, 190), C(255, 170, 40)), Size = NS({ NK(0, 0), NK(0.4, 0.07), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.4), Spread = 60, Rate = 7, Dir = "Top", Accel = V(0, 0.6, 0) },
			{ At = "Root", Light = { Color = C(255, 215, 120), Brightness = 1.3, Range = 6 } },
		},
	},
	-- ─── HC-50 Verdict heroes (2026-11-18): 140 RPM hand cannon, every shot full weight ───
	Marshal = {
		Light = C(150, 215, 255), LightBright = 3.4,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(240, 250, 255), C(90, 200, 255)), Size = grow(0.6, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(90, 200, 255), Core = C(245, 252, 255), Width = 0.1, Strands = { { Color = C(235, 245, 255), Radius = 0.14, Twist = 0.9, Width = 0.03 }, { Color = C(40, 150, 255), Radius = 0.14, Twist = 0.9, Width = 0.03, Phase = math.pi } }, Motes = { C(235, 248, 255), C(90, 200, 255), Size = 0.09, Density = 0.2 } }, Core = C(245, 252, 255), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(150, 220, 255)), Size = grow(0.15, 1.2), Transparency = fade(0.25, 1), Life = NR(0.16, 0.16), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(240, 250, 255), C(90, 200, 255)), Size = grow(0.1, 0), Life = NR(0.3, 0.6), Speed = NR(3, 8), Spread = 80, Count = 8 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(220, 240, 255), C(90, 200, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 4 } },
	},
	Scorpion = {
		Light = C(255, 170, 60), LightBright = 3.8,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 240, 200), C(255, 150, 20)), Size = grow(0.65, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(255, 150, 20), Core = C(255, 245, 215), Width = 0.11, Inner = C(80, 30, 0), Strands = { { Color = C(255, 210, 110), Radius = 0.15, Twist = 1.0, Width = 0.032 } }, Fire = { C(255, 200, 90), C(255, 100, 0), Emission = 0.45, Size = 0.15, Density = 0.18, Spread = 0.14 }, Motes = { C(255, 200, 100), C(160, 90, 20), Size = 0.09, Density = 0.22, Accel = V(0, -0.8, 0) } }, Core = C(255, 245, 215), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 170, 50)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 180), C(255, 140, 20)), Size = grow(0.11, 0), Life = NR(0.35, 0.7), Speed = NR(3, 9), Spread = 75, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 220, 140), C(255, 140, 20)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Justice = {
		Light = C(255, 220, 140), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 250, 225), C(255, 200, 80)), Size = grow(0.65, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(110, 150, 255)), Size = grow(0.12, 1.0), Transparency = fade(0.3, 1), Life = NR(0.11, 0.11), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 205, 90), Core = C(255, 252, 235), Width = 0.11, Inner = C(40, 70, 220), Strands = { { Color = C(255, 230, 150), Radius = 0.15, Twist = 0.8, Width = 0.032 }, { Color = C(80, 120, 255), Radius = 0.15, Twist = 0.8, Width = 0.03, Phase = math.pi } }, Rings = { Mesh = "Halo", Color = C(255, 215, 110), Spacing = 9, Size = 0.42 }, Motes = { C(255, 235, 170), C(90, 130, 255), Size = 0.09, Density = 0.2 } }, Core = C(255, 252, 235), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 215, 110)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 245, 210), C(110, 150, 255)), Size = grow(0.11, 0), Life = NR(0.4, 0.8), Speed = NR(3, 9), Spread = 80, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 235, 170), C(110, 150, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Countdown = {
		Light = C(255, 210, 140), LightBright = 4.0,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 245, 210), C(255, 80, 200)), Size = grow(0.65, 0.06), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 6, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(255, 215, 120)), Size = grow(0.1, 0.9), Transparency = fade(0.3, 1), Life = NR(0.1, 0.1), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 80, 200), Core = C(255, 245, 225), Width = 0.1, Inner = C(255, 200, 90), Strands = { { Color = C(255, 215, 120), Radius = 0.15, Twist = 0.8, Width = 0.03 }, { Color = C(120, 90, 255), Radius = 0.15, Twist = 0.8, Width = 0.026, Phase = math.pi * 0.66 }, { Color = C(255, 255, 255), Radius = 0.15, Twist = 0.8, Width = 0.022, Phase = math.pi * 1.33 } }, Rings = { Mesh = "Ring", Color = C(255, 215, 120), Spacing = 10, Size = 0.42 }, Motes = { C(255, 215, 120), C(255, 70, 200), Size = 0.1, Density = 0.25, Accel = V(0, -1.2, 0) } }, Core = C(255, 245, 225), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 90, 200)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 225, 140), C(255, 70, 200)), Size = grow(0.12, 0.03), Life = NR(0.5, 0.9), Speed = NR(3, 9), Spread = 90, Count = 14, Accel = V(0, -3, 0) },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 220, 140), C(255, 80, 200)), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(1.2, 2), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5, Accel = V(0, -0.4, 0) } },
	},
	-- ─── XB-7 Quill heroes (2026-11-19): single bolt, every shot full weight ───
	Tracker = {
		Light = C(130, 255, 170), LightBright = 3.4,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(230, 255, 235), C(90, 255, 140)), Size = grow(0.6, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(90, 255, 140), Core = C(240, 255, 245), Width = 0.1, Strands = { { Color = C(200, 255, 210), Radius = 0.14, Twist = 0.9, Width = 0.03 }, { Color = C(40, 160, 80), Radius = 0.14, Twist = 0.9, Width = 0.03, Phase = math.pi } }, Motes = { C(220, 255, 230), C(90, 255, 140), Size = 0.09, Density = 0.2 } }, Core = C(240, 255, 245), Width = 0.045 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(140, 255, 170)), Size = grow(0.15, 1.2), Transparency = fade(0.25, 1), Life = NR(0.16, 0.16), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(230, 255, 235), C(90, 255, 140)), Size = grow(0.1, 0), Life = NR(0.3, 0.6), Speed = NR(3, 8), Spread = 80, Count = 8 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(210, 255, 220), C(90, 255, 140)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 4 } },
	},
	Raptor = {
		Light = C(150, 255, 110), LightBright = 3.8,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(235, 255, 210), C(110, 255, 70)), Size = grow(0.65, 0.06), Life = NR(0.04, 0.08), Speed = NR(1, 3), Spread = 25, Count = 5, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(110, 255, 70), Core = C(245, 255, 225), Width = 0.11, Inner = C(30, 70, 10), Strands = { { Color = C(220, 170, 110), Radius = 0.15, Twist = 1.0, Width = 0.032 } }, Motes = { C(200, 255, 150), C(70, 160, 30), Size = 0.1, Density = 0.22, Accel = V(0, -0.6, 0) } }, Core = C(245, 255, 225), Width = 0.05 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(140, 255, 90)), Size = grow(0.15, 1.3), Transparency = fade(0.2, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(230, 255, 200), C(110, 255, 70)), Size = grow(0.11, 0), Life = NR(0.35, 0.7), Speed = NR(3, 9), Spread = 75, Count = 10 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(210, 255, 170), C(110, 255, 70)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Stag = {
		Light = C(140, 255, 240), LightBright = 4.6,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(235, 255, 252), C(70, 235, 220)), Size = grow(0.75, 0.07), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 6, Rotation = NR(0, 360) },
			E{ Texture = TEX.Shock, Color = CS(C(255, 220, 130)), Size = grow(0.12, 1.1), Transparency = fade(0.3, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(70, 235, 220), Core = C(250, 255, 255), Width = 0.13, Inner = C(10, 40, 60), Strands = { { Color = C(255, 215, 120), Radius = 0.17, Twist = 0.7, Width = 0.034 }, { Color = C(120, 255, 245), Radius = 0.17, Twist = 0.7, Width = 0.032, Phase = math.pi * 0.66 }, { Color = C(255, 255, 255), Radius = 0.17, Twist = 0.7, Width = 0.024, Phase = math.pi * 1.33 } }, Rings = { Mesh = "Halo", Color = C(255, 220, 130), Spacing = 10, Size = 0.45 }, Motes = { C(255, 240, 190), C(70, 235, 220), Size = 0.11, Density = 0.25, Accel = V(0, 0.6, 0) } }, Core = C(250, 255, 255), Width = 0.055 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(120, 255, 240), C(10, 30, 50)), Size = grow(1.1, 0), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 245, 210), C(70, 235, 220)), Size = grow(0.12, 0), Life = NR(0.5, 0.9), Speed = NR(3, 9), Spread = 70, Count = 12, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(230, 255, 250), C(255, 215, 120)), Size = NS({ NK(0, 0), NK(0.4, 0.07), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.4), Spread = 60, Rate = 6, Dir = "Top", Accel = V(0, 0.6, 0) },
			{ At = "Root", Light = { Color = C(140, 255, 240), Brightness = 1.2, Range = 6 } },
		},
	},
	Lion = {
		Light = C(255, 215, 130), LightBright = 4.6,
		Flash = {
			E{ Texture = TEX.Spark, Color = CS(C(255, 250, 230), C(255, 190, 70)), Size = grow(0.75, 0.07), Life = NR(0.05, 0.09), Speed = NR(1, 3), Spread = 25, Count = 6, Rotation = NR(0, 360) },
			E{ Texture = TEX.Implode, Color = CS(C(255, 225, 150), C(90, 0, 10)), Size = grow(0.9, 0), Life = NR(0.15, 0.15), Speed = NR(0, 0), Spread = 0, Count = 1 },
		},
		Tracer = { Laser = { Color = C(255, 195, 80), Core = C(255, 252, 240), Width = 0.13, Inner = C(150, 0, 20), Strands = { { Color = C(255, 230, 150), Radius = 0.17, Twist = 0.7, Width = 0.034 }, { Color = C(230, 30, 50), Radius = 0.17, Twist = 0.7, Width = 0.032, Phase = math.pi * 0.66 }, { Color = C(255, 255, 255), Radius = 0.17, Twist = 0.7, Width = 0.024, Phase = math.pi * 1.33 } }, Fire = { C(255, 240, 180), C(255, 120, 30), Emission = 0.5, Size = 0.2, Density = 0.22, Spread = 0.18 }, Motes = { C(255, 210, 120), C(220, 30, 40), Size = 0.11, Density = 0.25, Accel = V(0, 0.8, 0) } }, Core = C(255, 252, 240), Width = 0.055 },
		Impact = {
			E{ Texture = TEX.Implode, Color = CS(C(255, 220, 130), C(80, 0, 10)), Size = grow(1.1, 0), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 250, 220), C(255, 60, 60)), Size = grow(0.12, 0), Life = NR(0.5, 0.9), Speed = NR(3, 9), Spread = 70, Count = 12, Accel = V(0, 3, 0) },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(C(255, 240, 190), C(255, 80, 60)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.8), Speed = NR(0.1, 0.4), Spread = 60, Rate = 6, Dir = "Top", Accel = V(0, 0.6, 0) },
			{ At = "Root", Light = { Color = C(255, 215, 130), Brightness = 1.2, Range = 5 } },
		},
	},
	-- ─── BX-3 Helix heroes (2026-11-20): 1200 RPM continuous beam; EpicFX S.Helix adds the beam extras ───
	Containment = {
		Light = C(255, 110, 230), LightBright = 3.6,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 235, 252), C(255, 60, 220)), Size = grow(0.55, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(255, 60, 220), Core = C(255, 235, 252), Width = 0.08, Inner = C(70, 0, 60), Strands = { { Color = C(255, 200, 60), Radius = 0.1, Twist = 2.2, Width = 0.026 }, { Color = C(255, 140, 240), Radius = 0.1, Twist = 2.2, Width = 0.026, Phase = math.pi } } } },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 60, 220)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 235, 252), C(255, 60, 220)), Size = grow(0.09, 0), Life = NR(0.25, 0.5), Speed = NR(3, 8), Spread = 80, Count = 5 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 190, 245), C(255, 60, 220)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Ram = {
		Light = C(110, 230, 255), LightBright = 3.6,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(235, 252, 255), C(40, 220, 255)), Size = grow(0.55, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(40, 220, 255), Core = C(235, 252, 255), Width = 0.08, Inner = C(0, 50, 80), Strands = { { Color = C(220, 250, 255), Radius = 0.1, Twist = 2.2, Width = 0.026 }, { Color = C(60, 150, 255), Radius = 0.1, Twist = 2.2, Width = 0.026, Phase = math.pi } } } },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(40, 220, 255)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(235, 252, 255), C(40, 220, 255)), Size = grow(0.09, 0), Life = NR(0.25, 0.5), Speed = NR(3, 8), Spread = 80, Count = 5 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(200, 245, 255), C(40, 220, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Genesis = {
		Light = C(255, 230, 160), LightBright = 3.6,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 252, 240), C(255, 205, 100)), Size = grow(0.55, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(255, 205, 100), Core = C(255, 252, 240), Width = 0.09, Inner = C(120, 80, 20), Strands = { { Color = C(255, 250, 230), Radius = 0.1, Twist = 2.2, Width = 0.026 }, { Color = C(255, 215, 120), Radius = 0.1, Twist = 2.2, Width = 0.026, Phase = math.pi } } } },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 205, 100)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 252, 240), C(255, 205, 100)), Size = grow(0.09, 0), Life = NR(0.25, 0.5), Speed = NR(3, 8), Spread = 80, Count = 5 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 245, 210), C(255, 205, 100)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Masquerade = {
		Light = C(190, 120, 255), LightBright = 3.6,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(250, 240, 255), C(170, 70, 255)), Size = grow(0.55, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(170, 70, 255), Core = C(250, 240, 255), Width = 0.08, Inner = C(40, 0, 70), Strands = { { Color = C(255, 215, 120), Radius = 0.1, Twist = 2.2, Width = 0.026 }, { Color = C(90, 255, 160), Radius = 0.1, Twist = 2.2, Width = 0.026, Phase = math.pi } } } },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(170, 70, 255)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(250, 240, 255), C(170, 70, 255)), Size = grow(0.09, 0), Life = NR(0.25, 0.5), Speed = NR(3, 8), Spread = 80, Count = 5 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 225, 150), C(170, 70, 255)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
	Titan = {
		Light = C(255, 230, 150), LightBright = 3.6,
		Flash = { E{ Texture = TEX.Spark, Color = CS(C(255, 252, 240), C(255, 210, 90)), Size = grow(0.55, 0.05), Life = NR(0.04, 0.07), Speed = NR(1, 3), Spread = 25, Count = 4, Rotation = NR(0, 360) } },
		Tracer = { Laser = { Color = C(255, 210, 90), Core = C(255, 252, 240), Width = 0.1, Inner = C(150, 10, 20), Strands = { { Color = C(255, 250, 230), Radius = 0.1, Twist = 2.2, Width = 0.026 }, { Color = C(255, 160, 40), Radius = 0.1, Twist = 2.2, Width = 0.026, Phase = math.pi } } } },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(C(255, 210, 90)), Size = grow(0.12, 1.0), Transparency = fade(0.25, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(C(255, 252, 240), C(255, 210, 90)), Size = grow(0.09, 0), Life = NR(0.25, 0.5), Speed = NR(3, 8), Spread = 80, Count = 5 },
		},
		Idle = { { At = "Root", Texture = TEX.Spark, Color = CS(C(255, 245, 210), C(255, 200, 70)), Size = NS({ NK(0, 0), NK(0.4, 0.06), NK(1, 0) }), Life = NR(1, 1.6), Speed = NR(0.1, 0.3), Spread = 180, Rate = 5 } },
	},
}

-- ─── helpers ───────────────────────────────────────────────────────────────
SkinFX.Tuning = {
	FlashSize = 1.25, FlashLife = 1.6, -- premium flashes hang a little longer than stock
	IdleSize = 2.4, IdleRate = 1.4, IdleBrightness = 3.5, FlashBrightness = 2.5, -- world-model aura
	ViewmodelRate = 0.5, -- your own first-person gun: half the aura so it never clutters the view
}
local function scaleNS(ns: NumberSequence, k: number): NumberSequence
	local kps = {}
	for i, kp in ns.Keypoints do kps[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k) end
	return NumberSequence.new(kps)
end
local function scaleNR(nr: NumberRange, k: number): NumberRange
	return NumberRange.new(nr.Min * k, nr.Max * k)
end

local function emitter(parent: Instance, p, sizeK: number?, lifeK: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Texture = p.Texture
	e.Color = p.Color
	e.Size = if sizeK then scaleNS(p.Size, sizeK) else p.Size
	e.Transparency = p.Transparency or fade(0, 1)
	e.Lifetime = if lifeK then scaleNR(p.Life, lifeK) else p.Life
	e.Speed = p.Speed
	e.SpreadAngle = Vector2.new(p.Spread or 0, p.Spread or 0)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rotation = p.Rotation or NR(0, 360)
	if p.RotSpeed then e.RotSpeed = p.RotSpeed end
	if p.Accel then e.Acceleration = p.Accel end
	if p.Drag then e.Drag = p.Drag end
	e.EmissionDirection = Enum.NormalId[p.Dir or "Front"]
	e.ZOffset = 0.5
	if p.Flip then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout[p.Flip]
		e.FlipbookMode = Enum.ParticleFlipbookMode[p.FlipMode or "Random"]
	end
	if p.Orient then e.Orientation = Enum.ParticleOrientation[p.Orient] end
	if p.LockedToPart then e.LockedToPart = true end
	e.Parent = parent
	return e
end

-- ─── EPIC · pattern skins (2026-11-15): one generated def per pattern, in its palette ───
-- laser = colour core + two twin strands; flash / impact / a few idle glints on the gun.
local function patternFX(a: Color3, b: Color3, o: any?)
	local opt = o or {}
	local white = Color3.new(1, 1, 1)
	local tw = opt.Twist or 2.2
	local laser: any = { Color = a, Width = 0.09, Strands = {
		{ Color = b, Radius = 0.085, Twist = tw, Width = 0.035, Phase = 0 },
		{ Color = b, Radius = 0.085, Twist = tw, Width = 0.035, Phase = math.pi },
	} }
	if opt.Motes then
		laser.Motes = { opt.Motes[1], opt.Motes[2], Size = 0.14, Density = 0.5, Accel = opt.MoteAccel }
	end
	return {
		Light = a, LightBright = 3.6,
		Flash = {
			E{ Texture = TEX.Fire, Color = CS(b:Lerp(white, 0.6), a), Size = grow(0.42, 0.1), Life = NR(0.04, 0.06), Speed = NR(0.5, 1.5), Spread = 10, Count = 2 },
			E{ Texture = TEX.Spark, Color = CS(b), Size = grow(0.08, 0), Life = NR(0.15, 0.3), Speed = NR(5, 11), Spread = 40, Count = 6, Drag = 2 },
		},
		Tracer = { Laser = laser, Core = a:Lerp(white, 0.6), Width = 0.035 },
		Impact = {
			E{ Texture = TEX.Shock, Color = CS(a), Size = grow(0.15, 1.1), Transparency = fade(0.25, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 },
			E{ Texture = TEX.Spark, Color = CS(b), Size = grow(0.09, 0), Life = NR(0.15, 0.35), Speed = NR(4, 10), Spread = 55, Count = 7, Drag = 2 },
		},
		Idle = {
			{ At = "Root", Texture = TEX.Spark, Color = CS(b), Size = NS({ NK(0, 0), NK(0.4, 0.05), NK(1, 0) }), Life = NR(0.9, 1.6), Speed = NR(0.05, 0.25), Spread = 180, Rate = 3 },
		},
	}
end
local D = SkinFX.Defs
D.P_Amber = patternFX(C(255, 150, 30), C(255, 222, 130), { Motes = { C(255, 240, 200), C(255, 160, 40) } })
D.P_Carbon = patternFX(C(120, 180, 255), C(225, 236, 255))
D.P_Viridian = patternFX(C(60, 230, 130), C(190, 255, 215), { Motes = { C(220, 255, 235), C(60, 230, 130) } })
D.P_Pulsar = patternFX(C(255, 70, 190), C(100, 150, 255), { Motes = { C(255, 220, 245), C(120, 160, 255) } })
D.P_Signal = patternFX(C(255, 60, 170), C(40, 230, 255), { Twist = 4.5 })
D.P_Cryo = patternFX(C(140, 215, 255), C(240, 250, 255), { Motes = { C(240, 250, 255), C(140, 215, 255) }, MoteAccel = V(0, -2, 0) })
D.P_Camo = patternFX(C(60, 200, 200), C(160, 120, 235))
D.P_Circuit = patternFX(C(40, 220, 255), C(255, 200, 80), { Twist = 1.4 })
D.P_Plasma = patternFX(C(90, 110, 255), C(195, 120, 255), { Twist = 3.2, Motes = { C(230, 220, 255), C(120, 120, 255) } })
D.P_DarkMatter = patternFX(C(160, 70, 255), C(240, 120, 255), { Motes = { C(250, 210, 255), C(130, 50, 230) } })
-- BR-07 Sentinel set
D.P_Magma = patternFX(C(255, 90, 10), C(255, 190, 60), { Motes = { C(255, 220, 140), C(255, 80, 10) }, MoteAccel = V(0, 2, 0) })
D.P_Hex = patternFX(C(40, 200, 255), C(200, 245, 255), { Twist = 1.6 })
D.P_Aurora = patternFX(C(40, 230, 150), C(190, 90, 255), { Motes = { C(200, 255, 230), C(170, 90, 255) } })
D.P_Topo = patternFX(C(60, 220, 255), C(170, 255, 240), { Twist = 1.2 })
D.P_Damascus = patternFX(C(230, 30, 40), C(255, 150, 130))
D.P_Toxic = patternFX(C(130, 255, 40), C(230, 255, 150), { Motes = { C(230, 255, 160), C(100, 220, 30) }, MoteAccel = V(0, 1.5, 0) })
D.P_Prism = patternFX(C(255, 120, 230), C(120, 230, 255), { Twist = 3 })
D.P_Kintsugi = patternFX(C(255, 200, 80), C(255, 250, 230), { Motes = { C(255, 245, 200), C(255, 190, 70) } })
D.P_SimGrid = patternFX(C(255, 60, 210), C(60, 230, 255), { Twist = 1.4 })
D.P_Cobalt = patternFX(C(40, 100, 255), C(180, 215, 255), { Twist = 2.6 })
-- SMG-07 Spectre set
D.P_Venom = patternFX(C(40, 230, 90), C(200, 255, 140), { Twist = 3.4 })
D.P_Ion = patternFX(C(90, 150, 255), C(230, 240, 255), { Twist = 5 })
D.P_BloodMoon = patternFX(C(220, 30, 30), C(255, 160, 120), { Motes = { C(255, 200, 170), C(200, 20, 20) } })
D.P_Abyss = patternFX(C(20, 240, 200), C(120, 160, 255), { Motes = { C(160, 255, 230), C(20, 200, 180) }, MoteAccel = V(0, 1, 0) })
D.P_DeadChannel = patternFX(C(235, 240, 255), C(255, 40, 70), { Twist = 4.5 })
D.P_Splinter = patternFX(C(255, 122, 26), C(210, 216, 224))
D.P_Hyperspace = patternFX(C(120, 150, 255), C(230, 215, 255), { Motes = { C(240, 240, 255), C(130, 150, 255) } })
D.P_Opal = patternFX(C(160, 220, 255), C(255, 170, 230), { Twist = 2.8, Motes = { C(255, 255, 255), C(200, 170, 255) } })
D.P_Rust = patternFX(C(232, 120, 40), C(90, 170, 170))
D.P_Spectral = patternFX(C(200, 195, 255), C(255, 255, 255), { Motes = { C(255, 255, 255), C(150, 140, 220) }, MoteAccel = V(0, 0.8, 0) })
-- SG Breacher set (sci-fi)
D.P_Plating = patternFX(C(255, 50, 40), C(255, 200, 170), { Twist = 1.6 })
D.P_Reactor = patternFX(C(255, 170, 40), C(255, 240, 200), { Twist = 2.2, Motes = { C(255, 240, 200), C(255, 150, 30) } })
D.P_Conduit = patternFX(C(170, 60, 255), C(240, 200, 255), { Twist = 3 })
D.P_Lattice = patternFX(C(40, 255, 160), C(200, 255, 230), { Twist = 1.4 })
D.P_Cells = patternFX(C(30, 220, 200), C(220, 255, 250), { Motes = { C(220, 255, 250), C(30, 220, 200) }, MoteAccel = V(0, 1.5, 0) })
D.P_Titanium = patternFX(C(80, 120, 255), C(230, 150, 200), { Twist = 2.4 })
D.P_Mainframe = patternFX(C(60, 140, 255), C(255, 60, 70), { Twist = 4 })
D.P_Thermite = patternFX(C(255, 170, 60), C(140, 80, 255), { Motes = { C(255, 240, 200), C(255, 140, 40) }, MoteAccel = V(0, 1.5, 0) })
D.P_Tread = patternFX(C(255, 130, 40), C(220, 228, 240), { Twist = 1.2 })
D.P_Shockwave = patternFX(C(60, 220, 255), C(230, 255, 255), { Twist = 3.6 })

-- LR Longshot set (sci-fi)
D.P_Glyph = patternFX(C(80, 230, 255), C(230, 255, 255), { Twist = 1.2, Motes = { C(230, 255, 255), C(80, 200, 255) } })
D.P_Waveform = patternFX(C(60, 255, 220), C(255, 70, 170), { Twist = 5 })
D.P_Cascade = patternFX(C(255, 170, 40), C(255, 240, 200), { Motes = { C(255, 230, 160), C(255, 140, 20) }, MoteAccel = V(0, -2, 0) })
D.P_Targeting = patternFX(C(255, 40, 40), C(255, 190, 180), { Twist = 1 })
D.P_Gravity = patternFX(C(150, 70, 255), C(255, 230, 255), { Twist = 3.5, Motes = { C(240, 220, 255), C(130, 60, 230) } })
D.P_Nanite = patternFX(C(60, 200, 230), C(230, 250, 255), { Motes = { C(230, 250, 255), C(60, 200, 230) } })
D.P_Breach = patternFX(C(90, 160, 255), C(255, 180, 90), { Motes = { C(220, 235, 255), C(255, 170, 80) } })
D.P_StarChart = patternFX(C(255, 210, 120), C(120, 150, 255), { Twist = 2, Motes = { C(255, 245, 210), C(150, 170, 255) } })
D.P_Thermal = patternFX(C(255, 120, 30), C(255, 240, 160), { Twist = 2.6, Motes = { C(255, 230, 140), C(200, 30, 120) } })
D.P_Faceted = patternFX(C(60, 200, 230), C(150, 240, 255), { Twist = 1.6 })
-- CK-3 Edge knife set (sci-fi; the knife has no beam, so Flash/Tracer go unused and Idle glints show)
D.P_NeonFade = patternFX(C(255, 60, 150), C(255, 200, 90))
D.P_Blueprint = patternFX(C(120, 170, 255), C(235, 245, 255))
D.P_Chrome = patternFX(C(200, 220, 255), C(255, 255, 255))
D.P_Fiber = patternFX(C(40, 255, 140), C(255, 80, 200))
D.P_Holofoil = patternFX(C(200, 140, 255), C(120, 255, 220))
D.P_Magnetar = patternFX(C(255, 60, 200), C(120, 240, 255))
D.P_Cipher = patternFX(C(40, 230, 200), C(220, 230, 240))
D.P_DieShot = patternFX(C(255, 210, 110), C(160, 120, 255))
D.P_Foil = patternFX(C(255, 210, 90), C(255, 250, 220))
D.P_Tesseract = patternFX(C(40, 220, 255), C(255, 60, 210))
-- ═══ 2026-11-18: wave-1 crate guns (Riptide / Bulwark / Verdict / Quill / Helix / Havoc) ═══
D.P_Overclock = patternFX(C(255, 190, 40), C(60, 255, 140), { Twist = 3 })
D.P_Vector = patternFX(C(255, 40, 160), C(60, 220, 255), { Twist = 4 })
D.P_ArcWeld = patternFX(C(110, 170, 255), C(240, 245, 255), { Motes = { C(255, 230, 160), C(110, 170, 255) } })
D.P_KillSwitch = patternFX(C(255, 50, 40), C(255, 220, 200), { Twist = 1.4 })
D.P_GridRun = patternFX(C(255, 40, 200), C(40, 220, 255), { Twist = 3 })
D.P_Static = patternFX(C(40, 230, 255), C(255, 40, 90), { Twist = 5 })
D.P_Coolant = patternFX(C(40, 230, 210), C(220, 255, 250), { Motes = { C(220, 255, 250), C(0, 180, 160) }, MoteAccel = V(0, -2, 0) })
D.P_Nanoweave = patternFX(C(40, 220, 210), C(200, 255, 250), { Twist = 2 })
D.P_Redline = patternFX(C(255, 40, 30), C(255, 220, 120), { Twist = 2.6 })
D.P_PulseDrive = patternFX(C(60, 255, 140), C(220, 255, 230), { Twist = 4.5 })
D.P_Siege = patternFX(C(255, 120, 30), C(255, 220, 170), { Twist = 1.4 })
D.P_Bastion = patternFX(C(60, 200, 255), C(220, 245, 255), { Twist = 1.6 })
D.P_Forge = patternFX(C(255, 160, 60), C(90, 120, 255), { Motes = { C(255, 230, 160), C(255, 120, 40) }, MoteAccel = V(0, 1.5, 0) })
D.P_Dreadnought = patternFX(C(255, 50, 60), C(220, 224, 230), { Twist = 1.2 })
D.P_UrbanDigi = patternFX(C(220, 226, 235), C(120, 130, 150), { Twist = 1 })
D.P_AmmoBelt = patternFX(C(255, 190, 80), C(255, 240, 200), { Twist = 2 })
D.P_ShieldHex = patternFX(C(255, 140, 30), C(255, 240, 200), { Motes = { C(255, 230, 170), C(255, 110, 20) } })
D.P_BlackOps = patternFX(C(230, 30, 40), C(120, 120, 130), { Twist = 1 })
D.P_FusionCoils = patternFX(C(120, 240, 255), C(255, 170, 80), { Twist = 3.6 })
D.P_Tactical = patternFX(C(170, 255, 140), C(240, 255, 230), { Twist = 1.2 })
D.P_Gavel = patternFX(C(255, 200, 80), C(255, 250, 220), { Motes = { C(255, 245, 200), C(255, 190, 60) } })
D.P_Noir = patternFX(C(255, 236, 190), C(200, 200, 210), { Twist = 1.4 })
D.P_Sheriff = patternFX(C(200, 225, 255), C(255, 255, 255), { Twist = 2 })
D.P_Deco = patternFX(C(255, 210, 110), C(255, 250, 230), { Twist = 1.6 })
D.P_Judgement = patternFX(C(255, 60, 20), C(255, 210, 120), { Motes = { C(255, 200, 120), C(255, 40, 10) }, MoteAccel = V(0, 1.5, 0) })
D.P_Desert = patternFX(C(255, 190, 110), C(240, 225, 200), { Twist = 1.2 })
D.P_Executioner = patternFX(C(255, 40, 50), C(255, 200, 190), { Twist = 2.4 })
D.P_Vault = patternFX(C(200, 150, 255), C(240, 240, 250), { Twist = 2 })
D.P_Ledger = patternFX(C(140, 255, 240), C(220, 255, 250), { Twist = 3 })
D.P_SilverBullet = patternFX(C(170, 210, 255), C(255, 255, 255), { Motes = { C(255, 255, 255), C(140, 200, 255) } })
D.P_ShadowRail = patternFX(C(150, 90, 255), C(230, 210, 255), { Twist = 2.4 })
D.P_Cloak = patternFX(C(120, 255, 230), C(200, 180, 255), { Twist = 3.2 })
D.P_Fletch = patternFX(C(60, 220, 255), C(230, 250, 255), { Twist = 1.6 })
D.P_Sonar = patternFX(C(60, 255, 120), C(200, 255, 200), { Twist = 2 })
D.P_Ghost = patternFX(C(200, 215, 235), C(120, 130, 150), { Twist = 4 })
D.P_LaserMesh = patternFX(C(255, 50, 50), C(255, 220, 220), { Twist = 1.2 })
D.P_Midnight = patternFX(C(255, 200, 90), C(120, 150, 255), { Twist = 1.6 })
D.P_Arctic = patternFX(C(170, 230, 255), C(255, 255, 255), { Motes = { C(255, 255, 255), C(170, 220, 255) }, MoteAccel = V(0, -1.5, 0) })
D.P_ToxinCoil = patternFX(C(150, 255, 40), C(240, 255, 200), { Twist = 4 })
D.P_Moonlit = patternFX(C(190, 210, 255), C(255, 255, 255), { Twist = 1.4 })
D.P_Torsion = patternFX(C(60, 170, 255), C(60, 255, 220), { Twist = 5 })
D.P_Collider = patternFX(C(120, 200, 255), C(255, 120, 220), { Motes = { C(230, 240, 255), C(255, 120, 220) } })
D.P_Interference = patternFX(C(120, 230, 255), C(255, 140, 230), { Twist = 3.4 })
D.P_Tesla = patternFX(C(170, 100, 255), C(240, 225, 255), { Twist = 5 })
D.P_Supercon = patternFX(C(60, 180, 255), C(255, 255, 255), { Motes = { C(255, 255, 255), C(120, 200, 255) }, MoteAccel = V(0, -1, 0) })
D.P_FusionPlasma = patternFX(C(255, 120, 60), C(255, 80, 180), { Twist = 3.6 })
D.P_Photon = patternFX(C(255, 200, 120), C(120, 220, 255), { Twist = 3 })
D.P_Spectrum = patternFX(C(255, 90, 90), C(90, 140, 255), { Twist = 4 })
D.P_CleanRoom = patternFX(C(40, 210, 255), C(255, 255, 255), { Twist = 1.4 })
D.P_Antimatter = patternFX(C(255, 120, 230), C(255, 255, 255), { Motes = { C(255, 230, 250), C(200, 60, 200) } })
D.P_Demolition = patternFX(C(255, 200, 40), C(255, 255, 220), { Twist = 1.2 })
D.P_Detonator = patternFX(C(255, 40, 30), C(255, 200, 180), { Twist = 1.4 })
D.P_Scorched = patternFX(C(255, 90, 10), C(255, 220, 120), { Motes = { C(255, 210, 120), C(255, 80, 10) }, MoteAccel = V(0, 2, 0) })
D.P_Payload = patternFX(C(230, 210, 130), C(255, 250, 220), { Twist = 1.2 })
D.P_Shrapnel = patternFX(C(255, 140, 40), C(220, 226, 236), { Motes = { C(255, 220, 160), C(160, 160, 170) } })
D.P_PopBlast = patternFX(C(255, 210, 30), C(240, 40, 50), { Twist = 3 })
D.P_Thermobaric = patternFX(C(255, 140, 40), C(255, 240, 200), { Motes = { C(255, 230, 170), C(255, 100, 20) }, MoteAccel = V(0, 2, 0) })
D.P_Minefield = patternFX(C(255, 40, 30), C(255, 200, 190), { Twist = 1 })
D.P_Bunker = patternFX(C(255, 140, 40), C(210, 210, 210), { Twist = 1.4 })
D.P_NuclearWinter = patternFX(C(90, 255, 220), C(240, 244, 248), { Motes = { C(240, 244, 248), C(90, 255, 220) }, MoteAccel = V(0, -1.5, 0) })

local function fxFolder(): Folder
	local f = Workspace:FindFirstChild("VantageWeaponFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "VantageWeaponFX"
		f.Parent = Workspace
	end
	return f :: Folder
end

-- ─── shot pools + one animator (shot overhaul stage 1, 2026-11-18) ───────────
-- Lasers, rings, shed strips, lights and impacts used to be built per shot and cleaned up with
-- Debris (a Godly laser was ~100 new Parts per shot). They now come from pools parked under
-- VantageWeaponFX._SkinPool and are faded by one RenderStepped loop (same Quad-Out curves as the
-- old tweens). Shed / impact emitters are shared per spec: emitted particles live in world space,
-- so moving an emitter and calling Emit again never disturbs particles already in flight.
local FAR = CFrame.new(0, -5000, 0)
local poolRoot: Folder? = nil
local function poolFolder(): Folder
	if poolRoot and poolRoot.Parent then return poolRoot :: Folder end
	local f = fxFolder()
	local p = f:FindFirstChild("_SkinPool")
	if not p then p = Instance.new("Folder"); p.Name = "_SkinPool"; p.Parent = f end
	poolRoot = p :: Folder
	return p :: Folder
end

local Pool = { InUse = 0, Made = 0, Lights = 0 }
SkinFX.Pool = Pool

local freeCyl: { Part } = {}
local function cyl(color: Color3, width: number, transp: number, mat): Part
	local p: Part? = nil
	while #freeCyl > 0 do
		p = table.remove(freeCyl)
		if p and p.Parent then break end
		p = nil
	end
	if not p then
		p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Locked = true
		p.CFrame = FAR
		p.Parent = poolFolder()
		Pool.Made += 1
	end
	local q = p :: Part
	Pool.InUse += 1
	q.Material = mat or Enum.Material.Neon
	q.Color = color
	q.Transparency = transp
	q.Size = V(1, width, width)
	return q
end
local function freeCylPart(p: Part)
	Pool.InUse -= 1
	p.Transparency = 1
	p.CFrame = FAR
	table.insert(freeCyl, p)
end

local freeRings: { [string]: { BasePart } } = {}
local function ringPart(key: string, src: BasePart): BasePart
	local list = freeRings[key]
	if not list then list = {}; freeRings[key] = list end
	local p: BasePart? = nil
	while #list > 0 do
		p = table.remove(list)
		if p and p.Parent then break end
		p = nil
	end
	if not p then
		p = src:Clone()
		local r = p :: BasePart
		r.Anchored, r.CanCollide, r.CanQuery, r.CanTouch, r.CastShadow = true, false, false, false, false
		r.Locked = true
		r.CFrame = FAR
		r:SetAttribute("PoolKey", key)
		r.Parent = poolFolder()
		Pool.Made += 1
	end
	Pool.InUse += 1
	return p :: BasePart
end
local function freeRingPart(p: BasePart)
	Pool.InUse -= 1
	p.Transparency = 1
	p.CFrame = FAR
	local list = freeRings[p:GetAttribute("PoolKey") or "Ring"]
	if list then table.insert(list, p) end
end

local freeLights: { PointLight } = {}
local function poolLight(pos: Vector3, color: Color3, bright: number, range: number): PointLight
	local l: PointLight? = nil
	while #freeLights > 0 do
		l = table.remove(freeLights)
		if l and l.Parent and l.Parent.Parent then break end
		l = nil
	end
	if not l then
		local a = Instance.new("Attachment")
		a.Name = "SkinPoolLight"
		l = Instance.new("PointLight")
		;(l :: PointLight).Shadows = false
		;(l :: PointLight).Parent = a
		a.Parent = Workspace.Terrain
		Pool.Made += 1
	end
	local pl = l :: PointLight
	Pool.Lights += 1
	;(pl.Parent :: Attachment).WorldPosition = pos
	pl.Color, pl.Range, pl.Brightness, pl.Enabled = color, range, bright, true
	return pl
end
local function freeLight(l: PointLight)
	Pool.Lights -= 1
	l.Brightness = 0
	l.Enabled = false
	table.insert(freeLights, l)
end

-- live fades: { inst, t0, dur, size0, size1, tr0, tr1, release }
local live = {}
local lightFades = {} -- { light, t0, dur, b0 }
local freePlates = {} -- pooled decal plates
local movers = {} -- { part, from, dir, len, speed, t0, release, transparency }
local emitQ = {} -- { t, emitter, attachment, position, count }
local ribbonFades = {} -- { slot, t0, dur, tr0 }
local freeRib = {}
local heads = {} -- mesh heads riding a beam (stage 4)
local props = {} -- mesh / ball props: muzzle sequences, impact debris (stage 4)
local constel = setmetatable({}, { __mode = "k" }) -- recent burst endpoints per def
local decalFades = {} -- { plate, decal, t0, life, tr0, size0, size1 }
local offAt: { [PointLight]: number } = {} -- flash lights to switch off
local emaDt = 1 / 60
-- cosmetic clock: the Skin Range slows it (TimeScale 0.25); in play it is 1, i.e. os.clock pace
SkinFX.TimeScale = 1
local vNow, vLast = 0, os.clock()
function SkinFX.Now(): number
	local r = os.clock()
	vNow += (r - vLast) * SkinFX.TimeScale
	vLast = r
	return vNow
end
local stepConn: RBXScriptConnection? = nil
local function step(dt: number)
	emaDt += ((dt or emaDt) - emaDt) * 0.05
	local now = SkinFX.Now()
	local i, n = 1, #live
	while i <= n do
		local it = live[i]
		local a = (now - it[2]) / it[3]
		if a >= 1 then
			it[8](it[1])
			live[i] = live[n]; live[n] = nil; n -= 1
		elseif a < 0 then
			i += 1 -- sequenced, not started yet
		else
			local e = 1 - (1 - a) * (1 - a) -- Quad Out, as the old tweens
			local p = it[1]
			p.Size = it[4]:Lerp(it[5], e)
			local tr = it[6] + (it[7] - it[6]) * e
			if it[11] then tr = math.min(1, tr + math.random() * it[11]) end
			p.Transparency = tr
			if it[10] then p.Color = it[9]:Lerp(it[10], e) end
			i += 1
		end
	end
	-- movers: parts travelling down the beam (pulses / beads)
	i, n = 1, #movers
	while i <= n do
		local m = movers[i]
		local d = (now - m[6]) * m[5]
		if d >= m[4] then
			m[7](m[1])
			movers[i] = movers[n]; movers[n] = nil; n -= 1
		elseif d < 0 then
			i += 1
		else
			local at = m[2] + m[3] * d
			m[1].CFrame = CFrame.lookAt(at, at + m[3])
			m[1].Transparency = m[8]
			i += 1
		end
	end
	-- emit queue: sequenced marks along a beam
	i, n = 1, #emitQ
	while i <= n do
		local q = emitQ[i]
		if now >= q[1] then
			if q[3].Parent then
				q[3].WorldPosition = q[4]
				q[2]:Emit(q[5])
			end
			emitQ[i] = emitQ[n]; emitQ[n] = nil; n -= 1
		else
			i += 1
		end
	end
	-- mesh heads (stage 4)
	i, n = 1, #heads
	while i <= n do
		local h = heads[i]
		local el = now - h.t0
		local d = el * h.speed
		if d >= h.len then
			for _, e in h.kit do
				if e[4] then SkinFX._freeBallPart(e[1]) else SkinFX._freeMeshPart(e[1]) end
			end
			heads[i] = heads[n]; heads[n] = nil; n -= 1
		elseif el < 0 then
			i += 1
		else
			local at = h.from + h.dir * d
			local base = CFrame.lookAt(at, at + h.dir) * h.align * CFrame.Angles(0, el * h.spin, 0)
			local ps, cs = {}, {}
			for _, e in h.kit do
				table.insert(ps, e[1])
				table.insert(cs, base * e[2])
				e[1].Transparency = e[3]
			end
			Workspace:BulkMoveTo(ps, cs, Enum.BulkMoveMode.FireCFrameChanged)
			if h.trail then
				local sp = h.trail.Spacing or 1.5
				while h.laid + sp <= d do
					h.laid += sp
					SkinFX.EmitMark(h.trail, h.from + h.dir * h.laid)
				end
			end
			i += 1
		end
	end
	-- props (stage 4)
	i, n = 1, #props
	while i <= n do
		local e = props[i]
		local a = (now - e.t0) / e.life
		if a >= 1 then
			if e.ball then SkinFX._freeBallPart(e.p) else SkinFX._freeMeshPart(e.p) end
			props[i] = props[n]; props[n] = nil; n -= 1
		else
			local el = now - e.t0
			local g = if e.grow then math.min(1, a / e.grow) else a
			local sc = e.s0 + (e.s1 - e.s0) * (1 - (1 - g) * (1 - g))
			e.p.Size = e.base * sc
			local pos = e.p0 + e.vel * el + V(0, -0.5 * e.grav * el * el, 0)
			local cf = CFrame.new(pos) * e.rot * CFrame.fromAxisAngle(e.axis, e.rate * el)
			e.p.CFrame = if e.offP then cf * CFrame.new(e.offP * sc) * e.offR else cf
			local ft = if e.hold then math.max(0, (a - e.hold) / (1 - e.hold)) else a
			e.p.Transparency = e.tr0 + (e.tr1 - e.tr0) * ft * ft
			i += 1
		end
	end
	-- ribbons (curved Beams)
	i, n = 1, #ribbonFades
	while i <= n do
		local r = ribbonFades[i]
		local a = (now - r[2]) / r[3]
		if a >= 1 then
			r[1].beam.Enabled = false
			table.insert(freeRib, r[1])
			Pool.InUse -= 1
			ribbonFades[i] = ribbonFades[n]; ribbonFades[n] = nil; n -= 1
		else
			r[1].beam.Transparency = NumberSequence.new(r[4] + (1 - r[4]) * a * a)
			i += 1
		end
	end
	i, n = 1, #lightFades
	while i <= n do
		local it = lightFades[i]
		local a = (now - it[2]) / it[3]
		if a >= 1 then
			freeLight(it[1])
			lightFades[i] = lightFades[n]; lightFades[n] = nil; n -= 1
		else
			local e = 1 - (1 - a) * (1 - a)
			it[1].Brightness = it[4] * (1 - e)
			i += 1
		end
	end
	i, n = 1, #decalFades
	while i <= n do
		local it = decalFades[i]
		local a = (now - it[3]) / it[4]
		if a >= 1 then
			it[2].Transparency = 1
			it[1].CFrame = FAR
			table.insert(freePlates, it[1])
			decalFades[i] = decalFades[n]; decalFades[n] = nil; n -= 1
		else
			local e = a * a -- holds, then fades
			it[2].Transparency = it[5] + (1 - it[5]) * e
			local sz = it[6] + (it[7] - it[6]) * (1 - (1 - a) * (1 - a))
			it[1].Size = V(sz, 0.02, sz)
			i += 1
		end
	end
	for l, t in offAt do
		if now >= t then
			if l.Parent then l.Brightness = 0 end
			offAt[l] = nil
		end
	end
end
local function ensureStep()
	if stepConn or not RunService:IsClient() then return end
	-- Heartbeat, not RenderStepped: pooled FX must fade + return to the pool even when the client
	-- is not drawing frames (minimised / background Studio), or the pool grows while shots continue
	stepConn = RunService.Heartbeat:Connect(step)
end
local function fadeTo(p: BasePart, dur: number, size1: Vector3, tr1: number, release, delay: number?, c1: Color3?, flicker: number?)
	local tr0 = p.Transparency
	if delay and delay > 0 then p.Transparency = 1 end -- sequenced: hidden until its turn
	table.insert(live, { p, SkinFX.Now() + (delay or 0), dur, p.Size, size1, tr0, tr1, release, if c1 then p.Color else nil, c1, flicker })
end
SkinFX._fadeTo, SkinFX._cyl, SkinFX._freeCyl, SkinFX._poolLight = fadeTo, cyl, freeCylPart, poolLight
SkinFX._freeLight = freeLight

-- surface decals (def.Decal = { Texture, Color, Size, Grow, Life, Transp }): pooled plates, faded by step()
local function plate(): (Part, Decal)
	local p = table.remove(freePlates)
	while p and not p.Parent do p = table.remove(freePlates) end
	if not p then
		p = Instance.new("Part")
		p.Name = "SkinPoolDecal"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Locked = true
		local d = Instance.new("Decal")
		d.Face = Enum.NormalId.Top
		d.Parent = p
		p.CFrame = FAR
		p.Parent = poolFolder()
		Pool.Made += 1
	end
	return p, p:FindFirstChildOfClass("Decal") :: Decal
end
function SkinFX._decal(pos: Vector3, normal: Vector3, D)
	ensureStep()
	local p, d = plate()
	d.Texture = D.Texture
	d.Color3 = D.Color
	d.Transparency = D.Transp or 0.2
	local s = D.Size or 1
	p.Size = V(s, 0.02, s)
	local p0 = pos + normal * 0.03
	p.CFrame = CFrame.lookAt(p0, p0 + normal) * CFrame.Angles(math.rad(-90), 0, math.random() * math.pi * 2)
	table.insert(decalFades, { p, d, SkinFX.Now(), D.Life or 1, D.Transp or 0.2, s, s * (D.Grow or 1) })
end

-- ─── detail level: graphics quality x distance x load (the identity core is always drawn) ───
-- 1 = everything (identical to the pre-pool look); < 1 trims residue, strand segments, rings, lights.
local UGS = nil
pcall(function() UGS = UserSettings():GetService("UserGameSettings") end)
SkinFX.QualityOverride = nil -- the Skin Range sets 0.35 / 0.65 / 1
function SkinFX.Quality(): number
	if SkinFX.QualityOverride then return SkinFX.QualityOverride end
	local lv = 0
	if UGS then pcall(function() lv = UGS.SavedQualityLevel.Value end) end
	if lv == 0 then -- Automatic: follow the frame rate
		return if emaDt < 1 / 40 then 1 elseif emaDt < 1 / 25 then 0.65 else 0.35
	end
	return if lv <= 3 then 0.35 elseif lv <= 7 then 0.65 else 1
end
function SkinFX.Detail(pos: Vector3): number
	local q = SkinFX.Quality()
	local cam = Workspace.CurrentCamera
	if cam then
		local d = (cam.CFrame.Position - pos).Magnitude
		if d > 150 then q *= 0.3 elseif d > 60 then q *= 0.6 end
	end
	if Pool.InUse > 1400 then q *= 0.4 end -- global cap: shed detail first
	return q
end

-- ─── Epic signature primitives (shot overhaul stage 3, 2026-11-18) ──────────
-- Laser.Sig = { { Kind = "...", ... }, ... } — drawn by _LaserExtras after the strands / rings. All pooled.
local freeBall: { Part } = {}
local function ball(color: Color3, size: number): Part
	local p: Part? = nil
	while #freeBall > 0 do
		p = table.remove(freeBall)
		if p and p.Parent then break end
		p = nil
	end
	if not p then
		p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Locked = true
		p.Material = Enum.Material.Neon
		p.CFrame = FAR
		p.Parent = poolFolder()
		Pool.Made += 1
	end
	local b = p :: Part
	Pool.InUse += 1
	b.Material = Enum.Material.Neon
	b.Color = color
	b.Size = V(size, size, size)
	b.Transparency = 1
	return b
end
local function freeBallPart(p: Part)
	Pool.InUse -= 1
	p.Transparency = 1
	p.CFrame = FAR
	table.insert(freeBall, p)
end
SkinFX._freeBallPart = freeBallPart -- step() runs above this definition: call through the table
local function ribbonSlot()
	local s = table.remove(freeRib)
	while s and not s.a0.Parent do s = table.remove(freeRib) end
	if not s then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = "SkinRibbonA", "SkinRibbonB"
		a0.Parent, a1.Parent = Workspace.Terrain, Workspace.Terrain
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.Segments = 16
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Enabled = false
		b.Parent = a0
		s = { a0 = a0, a1 = a1, beam = b }
		Pool.Made += 1
	end
	Pool.InUse += 1
	return s
end
local function segPart(a: Vector3, b: Vector3, color: Color3, w: number, tr: number?): (Part, CFrame)
	local p = cyl(color, w, tr or 0)
	p.Size = V((b - a).Magnitude + w * 0.5, w, w)
	return p, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end
local markRigs = setmetatable({}, { __mode = "k" })
local function markRig(S)
	local r = markRigs[S]
	if r and r[2].Parent then return r end
	local a = Instance.new("Attachment")
	a.Name = "SkinMarkRig"
	a.Parent = Workspace.Terrain
	r = { emitter(a, S.E), a }
	markRigs[S] = r
	Pool.Made += 1
	return r
end
local function rnd2(u: Vector3, v: Vector3): Vector3
	local th = math.random() * math.pi * 2
	return u * math.cos(th) + v * math.sin(th)
end

local SIG = {}
-- segments jumping sideways + flicker (Signal Corrupt, Dead Channel...)
SIG.Glitch = function(S, from, dir, len, u, v, q, parts, cfs)
	local n = math.max(2, math.floor((S.Segs or 7) * q))
	local J = S.Jitter or 0.22
	for i = 1, n do
		local t0 = math.random() * len * 0.92
		local l = math.min(len - t0, (S.Len or 1.6) * (0.5 + math.random()))
		local a = from + dir * t0 + rnd2(u, v) * J * math.random()
		local c = if S.Colors then S.Colors[1 + (i % #S.Colors)] else S.Color
		local p, cf = segPart(a, a + dir * l, c, S.Width or 0.07)
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, 0.06 + math.random() * 0.2, p.Size, 1, freeCylPart, math.random() * 0.05, nil, S.Flicker or 0.6)
	end
end
-- square-wave PCB trace lit in sequence (Circuit Lattice...)
SIG.Trace = function(S, from, dir, len, u, v, q, parts, cfs)
	local step = math.max(S.Step or 1.4, len / 22)
	local off, w, seq = S.Off or 0.16, S.Width or 0.035, S.Seq or 0.0025
	local side, t = 1, 0.6
	local prev = from + dir * t + u * off
	while t + step < len do
		local nt = t + step
		local a = from + dir * nt + u * off * side
		local p, cf = segPart(prev, a, S.Color, w)
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, S.Dur or 0.24, V(p.Size.X, w * 0.3, w * 0.3), 1, freeCylPart, t * seq)
		side = -side
		local b = from + dir * nt + u * off * side
		local p2, cf2 = segPart(a, b, S.Color, w)
		table.insert(parts, p2); table.insert(cfs, cf2)
		fadeTo(p2, S.Dur or 0.24, V(p2.Size.X, w * 0.3, w * 0.3), 1, freeCylPart, nt * seq)
		prev, t = b, nt
	end
end
-- beads travelling down the beam (Pulsar beats, Pulse Drive...)
SIG.Pulses = function(S, from, dir, len, u, v, q, parts, cfs)
	local now = SkinFX.Now()
	for i = 1, math.max(1, math.floor((S.Count or 3) * q + 0.5)) do
		local p = ball(S.Color, S.Size or 0.22)
		table.insert(movers, { p, from, dir, len, S.Speed or 220, now + (i - 1) * (S.Gap or 0.045), freeBallPart, S.Transp or 0 })
	end
end
-- planar sine / bowed strand (Waveform, Damascus, Gravity Well when Arc = true)
SIG.Wave = function(S, from, dir, len, u, v, q, parts, cfs)
	local amp, wl = S.Amp or 0.16, S.Wavelength or 2.5
	local n = math.clamp(math.floor(len / (wl / 6)), 10, 44)
	if q < 1 then n = math.max(8, math.floor(n * q)) end
	local ax = if S.Axis == "v" then v else u
	local w = S.Width or 0.035
	local prev
	for i = 0, n do
		local t = i / n * len
		local ramp = math.min(1, t / 1.2)
		local o = if S.Arc then math.sin(math.pi * t / len) else math.sin(2 * math.pi * t / wl + (S.Phase or 0))
		local pt = from + dir * t + ax * o * amp * ramp
		if prev then
			local p, cf = segPart(prev, pt, S.Color, w)
			table.insert(parts, p); table.insert(cfs, cf)
			fadeTo(p, S.Dur or 0.24, V(p.Size.X, w * 0.2, w * 0.2), 1, freeCylPart, nil, S.ColorTo)
		end
		prev = pt
	end
end
-- dashed overlay (Carbon Ops, Kill Switch...)
SIG.Dashes = function(S, from, dir, len, u, v, q, parts, cfs)
	local d, g = S.Len or 0.7, S.Gap or 0.45
	local stride = math.max(d + g, len / 28)
	local w = S.Width or 0.06
	local t = 0.5
	while t + d < len do
		local p, cf = segPart(from + dir * t, from + dir * (t + d * stride / (d + g)), S.Color, w)
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, S.Dur or 0.22, V(p.Size.X, w * 0.2, w * 0.2), 1, freeCylPart, t * (S.Seq or 0))
		t += stride
	end
end
-- billboard marks laid along the beam, optionally in sequence (glyphs, hex cells, stars, swarm...)
SIG.Marks = function(S, from, dir, len, u, v, q, parts, cfs)
	local rig = markRig(S)
	local sp = math.max(S.Spacing or 3, len / (S.Max or 20)) / math.max(q, 0.35)
	local now = SkinFX.Now()
	local t = sp * (S.Start or 0.5)
	local stop = len * (S.Stop or 0.97)
	while t < stop do
		local pos = from + dir * t
		if S.Off then pos += rnd2(u, v) * S.Off * math.random() end
		table.insert(emitQ, { now + t * (S.Seq or 0), rig[1], rig[2], pos, S.Count or 1 })
		t += sp
	end
end
-- jagged lightning polyline (Storm Herald round 3, Ion Storm, Arc Weld)
SIG.Zigzag = function(S, from, dir, len, u, v, q, parts, cfs)
	local k = math.clamp(math.floor(len / (S.Kink or 2.2)), 4, S.Max or 18)
	local amp = S.Amp or 0.3
	local w = S.Width or 0.06
	local prev = from
	for i = 1, k do
		local t = i / k * len
		local pt = if i == k then from + dir * len else from + dir * t + rnd2(u, v) * amp * math.sin(math.pi * i / k) * (0.5 + math.random() * 0.5)
		local p, cf = segPart(prev, pt, S.Color, w)
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, S.Dur or 0.2, V(p.Size.X, w * 0.3, w * 0.3), 1, freeCylPart, nil, nil, 0.35)
		local c, ccf = segPart(prev, pt, S.Core or C(255, 255, 255), w * 0.4)
		table.insert(parts, c); table.insert(cfs, ccf)
		fadeTo(c, (S.Dur or 0.2) * 0.8, V(c.Size.X, w * 0.1, w * 0.1), 1, freeCylPart)
		prev = pt
	end
end
-- little arcs jumping off the beam (Ion Storm, Tesla, Static Burst)
SIG.Arcs = function(S, from, dir, len, u, v, q, parts, cfs)
	local w = S.Width or 0.03
	for _ = 1, math.max(1, math.floor((S.Count or 4) * q + 0.5)) do
		local t = (0.1 + math.random() * 0.85) * len
		local base = from + dir * t
		local out = rnd2(u, v)
		local prev = base
		for k = 1, 3 do
			local pt = base + out * (S.Len or 0.9) * k / 3 + dir * (math.random() - 0.5) * 0.4 + rnd2(u, v) * 0.12
			local p, cf = segPart(prev, pt, S.Color, w)
			table.insert(parts, p); table.insert(cfs, cf)
			fadeTo(p, S.Dur or 0.12, V(p.Size.X, w * 0.3, w * 0.3), 1, freeCylPart, math.random() * 0.06, nil, 0.4)
			prev = pt
		end
	end
end
-- speed lines parallel to the beam (Hyperspace, Redline)
SIG.Streaks = function(S, from, dir, len, u, v, q, parts, cfs)
	local w = S.Width or 0.025
	local r0, r1 = S.R0 or 0.15, S.R1 or 0.5
	for _ = 1, math.max(1, math.floor((S.Count or 8) * q + 0.5)) do
		local t = math.random() * len * 0.85
		local l = math.min(len - t, (S.Min or 1.5) + math.random() * ((S.Max or 4) - (S.Min or 1.5)))
		local off = rnd2(u, v) * (r0 + (r1 - r0) * math.random())
		local a = from + dir * t + off
		local p, cf = segPart(a, a + dir * l, S.Color, w)
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, S.Dur or 0.14, V(p.Size.X * 1.6, w * 0.2, w * 0.2), 1, freeCylPart)
	end
end
-- three colour strands that bulge apart mid-beam and converge on the target (Prism Shard, Spectrum)
SIG.Prism = function(S, from, dir, len, u, v, q, parts, cfs)
	local R, w = S.Radius or 0.24, S.Width or 0.04
	local n = math.max(8, math.floor(16 * q))
	for k, col in S.Colors do
		local th = (k - 1) * 2 * math.pi / #S.Colors + (S.Phase or 0)
		local ax = u * math.cos(th) + v * math.sin(th)
		local prev
		for i = 0, n do
			local t = i / n * len
			local pt = from + dir * t + ax * R * math.sin(math.pi * t / len)
			if prev then
				local p, cf = segPart(prev, pt, col, w)
				table.insert(parts, p); table.insert(cfs, cf)
				fadeTo(p, S.Dur or 0.26, V(p.Size.X, w * 0.2, w * 0.2), 1, freeCylPart)
			end
			prev = pt
		end
	end
end
-- curved soft ribbon (Aurora Veil, Spectral Smoke, Torsion)
SIG.Ribbon = function(S, from, dir, len, u, v, q, parts, cfs)
	local s = ribbonSlot()
	local c = S.Curve or 1.6
	s.a0.CFrame = CFrame.fromMatrix(from + dir * 0.8, u, v)
	s.a1.CFrame = CFrame.fromMatrix(from + dir * len, u, v)
	local b = s.beam
	b.Texture = S.Texture or ""
	b.TextureMode = Enum.TextureMode.Stretch
	b.Color = if S.c2 then ColorSequence.new(S.c1, S.c2) else ColorSequence.new(S.c1)
	b.Width0, b.Width1 = S.Width or 0.5, (S.Width or 0.5) * (S.Taper or 0.4)
	b.CurveSize0 = (math.random() * 2 - 1) * c
	b.CurveSize1 = (math.random() * 2 - 1) * c
	b.Transparency = NumberSequence.new(S.Transp or 0.35)
	b.Enabled = true
	table.insert(ribbonFades, { s, SkinFX.Now(), S.Dur or 0.35, S.Transp or 0.35 })
end
SkinFX.Sig = SIG

-- ─── Stage 4: Blender meshes (ReplicatedStorage.Vantage.Weapons.ShotMeshes) ──
-- Each mesh model is normalised to a 1-stud longest side; parts carry an "Offset" (pose about the box
-- centre). Long axis / disc normal = +Y; ALIGN_Y turns +Y to the direction of travel.
local freeMesh: { [string]: { BasePart } } = {}
local function meshTemplate(mesh: string, part: string): BasePart?
	local folder = script.Parent:FindFirstChild("ShotMeshes")
	local m = folder and folder:FindFirstChild(mesh)
	return m and m:FindFirstChild(part) :: BasePart?
end
local function meshPart(mesh: string, part: string): BasePart?
	local key = mesh .. "/" .. part
	local list = freeMesh[key]
	if not list then list = {}; freeMesh[key] = list end
	local p = table.remove(list)
	while p and not p.Parent do p = table.remove(list) end
	if not p then
		local src = meshTemplate(mesh, part)
		if not src then return nil end
		p = src:Clone()
		local q = p :: BasePart
		q:SetAttribute("PoolKey", key)
		q:SetAttribute("BaseSize", src.Size)
		q.CFrame = FAR
		q.Parent = poolFolder()
		Pool.Made += 1
	end
	Pool.InUse += 1
	return p
end
function SkinFX._freeMeshPart(p: BasePart)
	Pool.InUse -= 1
	p.Transparency = 1
	p.CFrame = FAR
	local list = freeMesh[p:GetAttribute("PoolKey")]
	if list then table.insert(list, p) end
end
local partNamesCache = {}
local function partNames(mesh: string)
	local c = partNamesCache[mesh]
	if c then return c end
	local folder = script.Parent:FindFirstChild("ShotMeshes")
	local m = folder and folder:FindFirstChild(mesh)
	c = {}
	if m then
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then table.insert(c, p.Name) end
		end
	end
	table.sort(c)
	partNamesCache[mesh] = c
	return c
end
local ALIGN_Y = CFrame.Angles(-math.pi / 2, 0, 0)
-- mesh head riding the beam: { Kind = "Head", Mesh, Size, Color / Colors[part], Material / Materials[part],
--   Transp / Transps[part], Only = {parts}, Ball = { Size, Color, Material }, Speed, Spin, Tilt, Start, Delay, Trail = marks spec }
SIG.Head = function(S, from, dir, len, u, v, q, parts, cfs)
	if q < 0.3 then return end
	local kit = {}
	-- your own first-person shot (stage 6): the head launches clear of the crosshair and smaller
	local camNow = Workspace.CurrentCamera
	local own = camNow ~= nil and (from - camNow.CFrame.Position).Magnitude < 6
	local k = (S.Size or 0.5) * (if own then 0.6 else 1)
	for _, name in partNames(S.Mesh) do
		if not (S.Only and not table.find(S.Only, name)) then
			local p = meshPart(S.Mesh, name)
			if p then
				p.Size = (p:GetAttribute("BaseSize") :: Vector3) * k
				p.Material = (S.Materials and S.Materials[name]) or S.Material or Enum.Material.Neon
				p.Color = (S.Colors and S.Colors[name]) or S.Color or Color3.new(1, 1, 1)
				local tr = (S.Transps and S.Transps[name]) or S.Transp or 0
				p.Transparency = 1
				local off = p:GetAttribute("Offset") :: CFrame
				table.insert(kit, { p, CFrame.new(off.Position * k) * off.Rotation, tr, false })
			end
		end
	end
	if S.Ball then
		local b = ball(S.Ball.Color, S.Ball.Size * (if own then 0.6 else 1))
		b.Material = S.Ball.Material or Enum.Material.Neon
		table.insert(kit, { b, CFrame.identity, S.Ball.Transp or 0, true })
	end
	if #kit == 0 then return end
	local st = if own then math.min((S.Start or 1) + 15, len * 0.8) else math.min(S.Start or 1, len * 0.5)
	local tilt = if S.Tilt then CFrame.Angles(math.rad(S.Tilt), 0, 0) else CFrame.identity
	table.insert(heads, { kit = kit, from = from + dir * st, dir = dir, len = math.max(0, len - st), speed = S.Speed or 260,
		t0 = SkinFX.Now() + (S.Delay or 0), align = ALIGN_Y * tilt, spin = S.Spin or 0, trail = S.Trail, laid = 0 })
end
-- props: { Mesh, Part | Shape = "Ball", Size, Size1, Grow (fraction of life to reach Size1), Life, Hold (fade starts),
--   Vel (local to the spawn frame), Rand, Grav, Spin (rad/s), Axis, Color, Material, Transp0, Transp1, Align (+Y to frame -Z) }
function SkinFX.Prop(P, cf: CFrame, scale: number?)
	ensureStep()
	local sk = scale or 1
	local p, base
	if P.Shape == "Ball" then
		p = ball(P.Color or Color3.new(1, 1, 1), 1)
		base = Vector3.one
	else
		p = meshPart(P.Mesh, P.Part)
		if not p then return end
		p.Color = P.Color or Color3.new(1, 1, 1)
		base = p:GetAttribute("BaseSize")
	end
	p.Material = P.Material or Enum.Material.Neon
	local f = if P.Align then cf * ALIGN_Y else cf
	if P.Offset then f *= P.Offset end
	local vel = f:VectorToWorldSpace(P.Vel or Vector3.zero)
	if P.Rand then vel += V(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1) * P.Rand end
	local e = { p = p, base = base, ball = P.Shape == "Ball", p0 = f.Position, rot = f.Rotation, vel = vel, grav = P.Grav or 0,
		axis = P.Axis or Vector3.yAxis, rate = (P.Spin or 0) * (if P.RandSpin and math.random() < 0.5 then -1 else 1), t0 = SkinFX.Now(), life = P.Life or 0.3,
		s0 = (P.Size or 0.5) * sk, s1 = (P.Size1 or P.Size or 0.5) * sk, grow = P.Grow, hold = P.Hold, tr0 = P.Transp0 or 0, tr1 = P.Transp1 or 1 }
	-- Rig = true: a multi-part mesh assembled in place (each part keeps its pose about the model centre, scaled with the prop)
	local off = if P.Rig and not e.ball then p:GetAttribute("Offset") :: CFrame? else nil
	if off then e.offP, e.offR = off.Position, off.Rotation end
	p.Size = base * e.s0
	p.Transparency = e.tr0
	p.CFrame = if off then f * CFrame.new(off.Position * e.s0) * off.Rotation else f
	table.insert(props, e)
end

-- one shared emitter strip per spec (key = the spec table)
local shedRigs = setmetatable({}, { __mode = "k" })
local function shedRig(key, build): (Part, ParticleEmitter)
	local r = shedRigs[key]
	if r and r[1].Parent then return r[1], r[2] end
	local strip = Instance.new("Part")
	strip.Anchored, strip.CanCollide, strip.CanQuery, strip.CanTouch, strip.CastShadow = true, false, false, false, false
	strip.Transparency = 1
	strip.Locked = true
	strip.CFrame = FAR
	strip.Name = "SkinPoolStrip"
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	build(e)
	e.Parent = strip
	strip.Parent = poolFolder()
	Pool.Made += 1
	shedRigs[key] = { strip, e }
	return strip, e
end
local function emitAlong(strip: Part, e: ParticleEmitter, cf: CFrame, len: number, thick: number, count: number)
	strip.Size = V(math.min(len, 2048), thick, thick)
	strip.CFrame = cf
	e:Emit(count)
end
SkinFX._shedRig, SkinFX._emitAlong, SkinFX._ensureStep = shedRig, emitAlong, ensureStep
function SkinFX.Get(fxId: string?)
	return fxId and SkinFX.Defs[fxId] or nil
end

-- the FX id of the weapon model an attachment belongs to (via Skins.Apply's "Skin" attribute)
local Skins
function SkinFX.ForAttachment(att: Instance?): string?
	local m = att and att:FindFirstAncestorWhichIsA("Model")
	while m and m:GetAttribute("Skin") == nil do
		m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model")
	end
	if not m then return nil end
	local fx = m:GetAttribute("SkinFX")
	return if type(fx) == "string" and fx ~= "" then fx else nil
end

-- ─── firing ──────────────────────────────────────────────────────────────
-- strong table: an Instance key in a weak table is dropped by the GC while the Instance still lives
-- (that rebuilt the rig and left the old emitters + light on the muzzle). Cleared when the attachment is destroyed.
local rigs = {}
local rigAdds = 0
local function pruneRigs()
	for a in rigs do
		if not a.Parent then rigs[a] = nil end
	end
end
function SkinFX.Flash(att: Attachment, def)
	local key = att
	local r = rigs[key]
	if not r or r.Def ~= def then
		if r then for _, e in r.E do e:Destroy() end if r.L then r.L:Destroy() end if r.S then r.S:Destroy() end end
		r = { Def = def, E = {}, n = 0, t = 0 }
		if def.Sustain then r.S = emitter(att, def.Sustain.E, SkinFX.Tuning.FlashSize) end
		for i, p in def.Flash do
			r.E[i] = emitter(att, p, SkinFX.Tuning.FlashSize, SkinFX.Tuning.FlashLife)
			r.E[i].Brightness = SkinFX.Tuning.FlashBrightness
		end
		local l = Instance.new("PointLight"); l.Color = def.Light; l.Range = 9; l.Brightness = 0; l.Shadows = false; l.Parent = att
		r.L = l
		rigs[key] = r
		att.Destroying:Once(function() rigs[att] = nil end)
		rigAdds += 1
		if rigAdds % 64 == 0 then pruneRigs() end
	end
	for i, p in def.Flash do r.E[i]:Emit(p.Count or 1) end
	if def.MuzzleProps and SkinFX.Detail(att.WorldPosition) >= 0.35 then -- mesh muzzle sequence (stage 4)
		local mcf = att.WorldCFrame
		-- your own first-person gun: half size, so the sequence never covers the view (crosshair-clean rule)
		local msc = if att:FindFirstAncestor("VantageViewmodel") then 0.5 else 1
		for _, P in def.MuzzleProps do SkinFX.Prop(P, mcf, msc) end
	end
	local now = os.clock()
	r.n = if now - r.t < 0.3 then r.n + 1 else 1
	r.t = now
	if r.S and r.n >= def.Sustain.From then -- sustained fire: e.g. Glacier's barrel frosts up
		r.S:Emit(math.min(3, 1 + (r.n - def.Sustain.From) // 4))
	end
	r.L.Brightness = def.LightBright or 3.5
	offAt[r.L] = SkinFX.Now() + 0.07
	ensureStep()
end

local function beamPart(color: Color3, w: number, transp: number): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transp
	p.Size = V(w, w, 0.1)
	p.Parent = fxFolder()
	return p
end

-- ─── themed projectiles (premium skins) ──────────────────────────────────
-- Tracer.Projectile = { Kind = "Halo" | "Fireball" | "BlackHole" | "Head", Mesh = "FoxHead" (Head kind), Speed, Scale,
--                       Color, Trail = emitter spec, Light = Color3 }
-- Cosmetic only: damage is already resolved; the visual shot flies at Speed and the skin's impact burst
-- plays when it arrives.
SkinFX._arrive = {}
local function akey(p: Vector3): string
	return string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
end

local function projBody(P): (BasePart?, { BasePart })
	local parts = {}
	local function part(shape, size, color, mat, transp)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = mat or Enum.Material.Neon
		p.Transparency = transp or 0
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		table.insert(parts, p)
		return p
	end
	local k = P.Scale or 1
	local meshes = script.Parent:FindFirstChild("SkinKitMeshes")
	if P.Kind == "Fireball" then
		local core = part(Enum.PartType.Ball, V(0.3, 0.3, 0.3) * k, C(255, 236, 160))
		part(Enum.PartType.Ball, V(0.46, 0.46, 0.46) * k, P.Color or C(255, 110, 30), nil, 0.25)
		return core, parts
	elseif P.Kind == "BlackHole" then
		-- a true black core, a faint violet event-horizon rim and a bright accretion disc around it
		local core = part(Enum.PartType.Ball, V(0.4, 0.4, 0.4) * k, C(0, 0, 0), Enum.Material.SmoothPlastic)
		core.Reflectance = 0
		part(Enum.PartType.Ball, V(0.47, 0.47, 0.47) * k, P.Color or C(190, 90, 255), nil, 0.86)
		-- accretion ring: Event Horizon's own ring mesh, tilted like Saturn's, spinning about its normal
		local hz = meshes and meshes:FindFirstChild("Horizon_Vanguard")
		local src = hz and hz:FindFirstChild("RingL")
		if src then
			local ring = src:Clone()
			ring.Size = src.Size * (0.95 * k / 0.49)
			ring.Material = Enum.Material.Neon
			ring.Color = P.Color or C(200, 110, 255)
			ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
			local rcf = src:GetAttribute("RootCF") :: CFrame
			ring:SetAttribute("Disc", true)
			ring:SetAttribute("Normal", if rcf then rcf:VectorToObjectSpace(V(1, -0.25, 0.15).Unit) else V(1, 0, 0))
			table.insert(parts, ring)
		end
		return core, parts
	elseif P.Kind == "Halo" or P.Kind == "Head" then
		local src = if P.Kind == "Halo" then meshes and meshes:FindFirstChild("Archangel_Vanguard") and meshes.Archangel_Vanguard:FindFirstChild("Halo0")
			else meshes and meshes:FindFirstChild("Projectiles") and meshes.Projectiles:FindFirstChild(P.Mesh)
		if not src then
			return nil, parts
		end
		local p = src:Clone()
		p.Size = src.Size * (P.Scale or 1)
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		if P.Kind == "Halo" then
			p.Material = Enum.Material.Neon
			p.Color = P.Color or C(255, 214, 120)
			-- the ring's own normal, so it flies face-on
			local rcf = src:GetAttribute("RootCF") :: CFrame
			p:SetAttribute("Normal", if rcf then rcf:VectorToObjectSpace(V(0.12, 0.35, 1).Unit) else V(0, 0, 1))
		end
		table.insert(parts, p)
		return p, parts
	end
	return nil, parts
end

function SkinFX.Projectile(from: Vector3, to: Vector3, skip: number?, def)
	local P = def.Tracer.Projectile
	local d = to - from
	local len = d.Magnitude
	local dir = d.Unit
	local main, parts = projBody(P)
	if not main then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "SkinProjectile"
	for _, p in parts do
		p.Parent = folder
	end
	local att = Instance.new("Attachment")
	att.Parent = main
	if P.Trail then
		local e = emitter(att, P.Trail, 2.2, 1.5) -- trails read at combat range: bigger, longer
		e.Rate = P.Trail.Rate or 120
		e.Brightness = 4
		e.ZOffset = -0.5 -- behind the shot's body
		e.Enabled = true
	end
	if P.Light then
		local l = Instance.new("PointLight")
		l.Color = P.Light; l.Brightness = 4; l.Range = 10; l.Shadows = false
		l.Parent = main
	end
	folder.Parent = Workspace
	local speed = P.Speed or 240
	local startAt = math.min(math.max(skip or 0, P.Start or 1.1), len)
	local travel = math.max(0, (len - startAt) / speed)
	SkinFX._arrive[akey(to)] = os.clock() + travel
	local t0 = os.clock()
	local spinAxis = main:GetAttribute("Normal")
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local el = os.clock() - t0
		local dist = startAt + el * speed
		if dist >= len or not folder.Parent then
			conn:Disconnect()
			for _, e in att:GetChildren() do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			for _, p in parts do
				p.Transparency = 1
				for _, l in p:GetChildren() do if l:IsA("PointLight") then l.Enabled = false end end
			end
			Debris:AddItem(folder, 1.2)
			return
		end
		local pos = from + dir * dist
		local look = CFrame.lookAt(pos, pos + dir)
		if P.Kind == "Halo" then
			-- ring face-on to the flight, spinning about it
			local n = spinAxis or V(0, 0, 1)
			local align = CFrame.fromRotationBetweenVectors(n, V(0, 0, -1))
			main.CFrame = look * CFrame.Angles(0, 0, el * 14) * align
		elseif P.Kind == "Head" then
			main.CFrame = look * CFrame.Angles(0, 0, math.sin(el * 18) * 0.12) * (main:GetAttribute("RotFix") or CFrame.identity)
		else
			for _, p in parts do
				if p:GetAttribute("Disc") then
					local n = p:GetAttribute("Normal") or V(1, 0, 0)
					-- ring plane tilted 65 deg off the flight line, spinning about its own axis
					p.CFrame = look * CFrame.Angles(math.rad(65), 0, 0) * CFrame.Angles(0, 0, el * 9) * CFrame.fromRotationBetweenVectors(n, V(0, 0, -1))
				else
					p.CFrame = look
				end
			end
		end
	end)
	Debris:AddItem(folder, travel + 2)
	return true
end

local TweenService = game:GetService("TweenService")
local LASER_FADE, EXTRA_FADE = 0.18, 0.24

-- ─── laser beams (all premium skins, 2026-11-14; pooled 2026-11-18) ───────────
-- Tracer.Laser = { Color = Color3, Core = Color3?, Width = number? }
-- An instant straight beam muzzle -> hit: white-hot core, coloured glow and a soft outer haze. It
-- pops thick on the shot, snaps thin and fades in ~0.18 s, with sparks shed along its length.
function SkinFX.Laser(from: Vector3, to: Vector3, def, info)
	local L = def.Tracer.Laser
	if info and info.Shot and def.Every and def.Every.Laser and info.Shot % def.Every.N == 0 then
		L = def.Every.Laser -- rhythm: e.g. every 3rd burst round, every 5th belt round
	end
	local col = L.Color
	if info and info.Heat and def.Heat then -- sustained fire shifts the beam colour
		col = col:Lerp(def.Heat.Color, math.clamp((info.Heat - 1) / (def.Heat.Max or 12), 0, 1))
	end
	local fd = L.Fade or LASER_FADE
	local d = to - from
	local len = d.Magnitude
	if len < 0.5 then
		return
	end
	ensureStep()
	local q = SkinFX.Detail(from)
	local w = L.Width or 0.09
	local cf = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0) -- cylinder axis = X
	local parts, cfs = {}, {}
	local layers = {
		{ L.Core or C(255, 255, 245), 0.45, 0 },
		{ col, 1, 0.15 },
		{ col, 2.6, 0.72 },
	}
	for _, l in layers do
		local p = cyl(l[1], w * l[2], l[3])
		p.Size = V(len, w * l[2] * 1.5, w * l[2] * 1.5) -- the shot pops thick...
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, fd, V(len, w * l[2] * 0.15, w * l[2] * 0.15), 1, freeCylPart, nil, if l[2] > 0.5 then L.ColorTo else nil) -- ...then snaps thin and fades
	end
	if q >= 0.5 then
		local l = poolLight(from + d.Unit * math.min(len, 3), col, 3, 8)
		table.insert(lightFades, { l, SkinFX.Now(), fd, 3 })
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- sparks shed along the beam
	local strip, e = shedRig(L, function(e)
		e.Texture = TEX.Spark
		e.Color = CS(L.Core or C(255, 255, 245), L.Color)
		e.LightEmission = 1
		e.Brightness = 4
		e.Size = NS({ NK(0, 0.14), NK(1, 0) })
		e.Lifetime = NR(0.15, 0.35)
		e.Speed = NR(0.5, 2.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 3
		e.Shape = Enum.ParticleEmitterShape.Box
	end)
	emitAlong(strip, e, cf, len, 0.05, math.max(1, math.floor(math.clamp(math.floor(len * 0.6), 6, 40) * q)))
	SkinFX._LaserExtras(from, to, len, d.Unit, cf, L, q)
	local K = def.Constellation -- thin lines joining a burst's impact points (Celestial Astrolabe)
	if K and q >= 0.5 then
		local list = constel[def]
		if not list then list = {}; constel[def] = list end
		local now = SkinFX.Now()
		while #list > 0 and now - list[1][2] > (K.Window or 0.5) do table.remove(list, 1) end
		table.insert(list, { to, now })
		while #list > 3 do table.remove(list, 1) end
		local function line(a: Vector3, b: Vector3)
			local p, lcf = segPart(a, b, K.Color, K.Width or 0.035)
			p.CFrame = lcf
			fadeTo(p, K.Life or 0.6, V(p.Size.X, 0.004, 0.004), 1, freeCylPart)
		end
		if #list >= 2 then line(list[#list - 1][1], list[#list][1]) end
		if #list == 3 then line(list[1][1], list[3][1]) end
	end
end

-- ─── tier extras: what makes each premium beam its own ───────────────────
--   Inner   = Color3          dark / coloured centre strand (Event Horizon's black core)
--   Strands = { {Color, Radius, Twist (rad/stud), Width, Phase} }  helix strands wrapped round the beam
--   Rings   = { Mesh = "Halo"|"Ring", Color, Spacing, Size }        rings strung along the beam, face-on
--   Fire    = { c1, c2, Size, Density }                             flames licking along its length
--   Motes   = { c1, c2, Size, Density, Texture }                    shed particles (ice shards, foxfire...)
-- qArg: detail level (number); older callers passed a Folder, which means full detail.
function SkinFX._LaserExtras(from: Vector3, to: Vector3, len: number, dir: Vector3, cf: CFrame, L, qArg)
	ensureStep()
	local q = if type(qArg) == "number" then qArg else 1
	local up = if math.abs(dir.Y) > 0.95 then V(1, 0, 0) else V(0, 1, 0)
	local u = dir:Cross(up).Unit
	local v = dir:Cross(u).Unit
	local parts, cfs = {}, {}
	if L.Inner then
		local iw = (L.Width or 0.1) * 0.6
		local p = cyl(L.Inner, iw, 0, Enum.Material.SmoothPlastic)
		p.Size = V(len, iw, iw)
		table.insert(parts, p); table.insert(cfs, cf)
		fadeTo(p, EXTRA_FADE, V(len, iw * 0.2, iw * 0.2), 1, freeCylPart)
	end
	if L.Strands and q >= 0.3 then
		for _, st in L.Strands do
			local turns = len * (st.Twist or 1.2) / (2 * math.pi)
			local n = math.clamp(math.floor(turns * 12), 12, 44)
			if q < 1 then n = math.max(8, math.floor(n * q)) end
			local sw = st.Width or 0.05
			local prev
			for i = 0, n do
				local t = i / n * len
				local th = (st.Phase or 0) + t * (st.Twist or 1.2)
				local r = st.Radius * math.min(1, t / 1.5) -- strands open out of the muzzle
				local pt = from + dir * t + (u * math.cos(th) + v * math.sin(th)) * r
				if prev then
					local p = cyl(st.Color, sw, 0.05)
					p.Size = V((pt - prev).Magnitude + sw * 0.5, sw, sw)
					table.insert(parts, p)
					table.insert(cfs, CFrame.lookAt((prev + pt) / 2, pt) * CFrame.Angles(0, math.rad(90), 0))
					fadeTo(p, EXTRA_FADE, V(p.Size.X, sw * 0.2, sw * 0.2), 1, freeCylPart)
				end
				prev = pt
			end
		end
	end
	if L.Rings and q >= 0.3 then
		local R = L.Rings
		local meshes = script.Parent:FindFirstChild("SkinKitMeshes")
		local src
		if meshes then
			if R.Mesh == "Halo" then
				local f = meshes:FindFirstChild("Archangel_Vanguard")
				src = f and f:FindFirstChild("Halo0")
			else
				local f = meshes:FindFirstChild("Horizon_Vanguard")
				src = f and f:FindFirstChild("RingL")
			end
		end
		if src then
			local key = if R.Mesh == "Halo" then "Halo" else "Ring"
			local rcf = src:GetAttribute("RootCF") :: CFrame
			local nAxis = if R.Mesh == "Halo" then V(0.12, 0.35, 1).Unit else V(1, -0.25, 0.15).Unit
			local nLocal = if rcf then rcf:VectorToObjectSpace(nAxis) else V(0, 0, 1)
			local align = CFrame.fromRotationBetweenVectors(nLocal, V(0, 0, -1))
			local count = math.clamp(math.floor(len / R.Spacing), 1, 8)
			if q < 1 then count = math.max(1, math.floor(count * q + 0.5)) end
			local k = (R.Size or 0.5) / math.max(src.Size.X, src.Size.Y)
			for i = 1, count do
				local pos = from + dir * (i * R.Spacing)
				local ring = ringPart(key, src)
				ring.Material = Enum.Material.Neon
				ring.Color = R.Color
				ring.Transparency = 0.05
				ring.Size = src.Size * k
				table.insert(parts, ring)
				table.insert(cfs, CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, i * 0.7) * align)
				fadeTo(ring, EXTRA_FADE, ring.Size * 1.9, 1, freeRingPart)
			end
		end
	end
	if L.Sig and q >= 0.3 then
		for _, S in L.Sig do
			local f = SIG[S.Kind]
			if f then f(S, from, dir, len, u, v, q, parts, cfs) end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local function shed(spec, tex)
		if q < 0.5 then return end -- residue: dropped at Low quality / far away
		local strip, e = shedRig(spec, function(e)
			e.Texture = spec.Texture or tex
			if spec.Flip then
				e.FlipbookLayout = Enum.ParticleFlipbookLayout[spec.Flip]
				e.FlipbookMode = Enum.ParticleFlipbookMode.Random
			end
			e.Color = CS(spec[1], spec[2])
			e.LightEmission = spec.Emission or 1
			e.Brightness = 3
			e.Size = NS({ NK(0, spec.Size or 0.3), NK(1, 0) })
			e.Transparency = NS({ NK(0, spec.Transp or 0.1), NK(1, 1) })
			e.Lifetime = if spec.Life then NR(spec.Life[1], spec.Life[2]) else NR(0.2, 0.4)
			e.Speed = NR(0.3, 1.2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Rotation = NR(0, 360)
			e.RotSpeed = NR(-120, 120)
			e.Acceleration = spec.Accel or V(0, 1.5, 0)
			e.Shape = Enum.ParticleEmitterShape.Box
		end)
		emitAlong(strip, e, cf, len, spec.Spread or 0.2,
			math.max(1, math.floor(math.clamp(math.floor(len * (spec.Density or 0.8)), 6, 60) * q)))
	end
	if L.Fire then
		shed(L.Fire, TEX.Fire)
	end
	if L.Motes then
		shed(L.Motes, L.Motes.Texture or TEX.Spark)
	end
	if L.Mist then
		shed(L.Mist, TEX.Smoke)
	end
end

function SkinFX.Tracer(from: Vector3, to: Vector3, skip: number?, def, info)
	local T = def.Tracer
	if T.Laser then
		SkinFX.Laser(from, to, def, info)
		return
	end
	if T.Projectile and (to - from).Magnitude >= 3 and SkinFX.Projectile(from, to, skip, def) then
		return
	end
	local d = to - from
	local len = d.Magnitude
	if len < 3 then return end
	local dir = d.Unit
	local startAt = math.min(skip or 0, len - 1)
	local core = beamPart(T.Core, T.Width or 0.04, 0.15)
	local glow = T.Glow and beamPart(T.Glow, T.GlowWidth or 0.12, 0.72) or nil
	local head
	if T.Trail then
		head = Instance.new("Attachment")
		head.Parent = Workspace.Terrain
		local e = emitter(head, T.Trail)
		e.Rate = T.Trail.Rate or 200
		e.Enabled = true
	end
	local streak = math.min(len, 9)
	local speed = 900
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local travelled = startAt + (os.clock() - t0) * speed
		local hd = math.min(travelled, len)
		local tl = math.max(startAt, travelled - streak) -- 2026-11-19: unclamped, so the loop ends (was a leaked RenderStepped per shot)
		if tl >= len - 0.1 then
			conn:Disconnect()
			core:Destroy()
			if glow then glow:Destroy() end
			if head then
				for _, e in head:GetChildren() do if e:IsA("ParticleEmitter") then e.Enabled = false end end
				Debris:AddItem(head, 1)
			end
			return
		end
		local a, b = from + dir * tl, from + dir * hd
		local l = math.max(0.05, (b - a).Magnitude)
		local cf = CFrame.lookAt((a + b) / 2, b)
		core.Size = V(core.Size.X, core.Size.Y, l); core.CFrame = cf
		if glow then glow.Size = V(glow.Size.X, glow.Size.Y, l); glow.CFrame = cf end
		if head then head.WorldPosition = b end
	end)
	Debris:AddItem(core, 1)
	if glow then Debris:AddItem(glow, 1) end
	if head then Debris:AddItem(head, 2) end
end

-- impacts: one shared attachment + emitter set per FX def, moved and re-emitted (pooled 2026-11-18)
local impactRigs = setmetatable({}, { __mode = "k" })
function SkinFX._ImpactNow(pos: Vector3, normal: Vector3, def, kind: string?)
	local r = impactRigs[def]
	if not r or not r.A.Parent then
		local a = Instance.new("Attachment")
		a.Name = "SkinPoolImpact"
		a.Parent = Workspace.Terrain
		local E = {}
		for i, p in def.Impact do E[i] = emitter(a, p) end
		r = { A = a, E = E }
		impactRigs[def] = r
		Pool.Made += 1
	end
	local p0 = pos + normal * 0.06
	r.A.CFrame = CFrame.lookAt(p0, p0 + normal)
	local q = SkinFX.Detail(pos)
	for i, p in def.Impact do
		local n = p.Count or 1
		if q < 1 then n = math.max(1, math.floor(n * q + 0.5)) end
		r.E[i]:Emit(n)
	end
	if def.Decal and kind ~= "Character" and q >= 0.35 then
		SkinFX._decal(pos, normal, def.Decal)
	end
	if def.ImpactProps and q >= 0.35 then -- mesh debris (stage 4)
		local icf = CFrame.lookAt(p0, p0 + normal)
		for _, P in def.ImpactProps do
			if not (P.World and kind == "Character") then SkinFX.Prop(P, icf) end
		end
	end
end

-- ─── idle aura (built on the weapon model; called by Skins.Apply) ─────────
local function anchorAttachment(model: Instance, name: string): Attachment?
	local root = model:FindFirstChild("Root", true)
	if root then
		local a = root:FindFirstChild(name)
		if a and a:IsA("Attachment") then return a end
		if name == "Root" then
			local x = root:FindFirstChild("SkinFXRoot")
			if not x then x = Instance.new("Attachment"); x.Name = "SkinFXRoot"; x.Parent = root end
			return x
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then return d end
	end
	return nil
end

function SkinFX.ClearIdle(model: Instance)
	for _, d in model:GetDescendants() do
		if d:GetAttribute("SkinFXIdle") then d:Destroy() end
	end
	model:SetAttribute("SkinFX", nil)
end

function SkinFX.AttachIdle(model: Instance, fxId: string?)
	SkinFX.ClearIdle(model)
	local def = SkinFX.Get(fxId)
	if not def then return end
	model:SetAttribute("SkinFX", fxId)
	for _, p in def.Idle or {} do
		local name = p.At == "Muzzle" and "Muzzle" or p.At == "Shoulder" and "Shoulder" or "Root"
		local a = anchorAttachment(model, name) or anchorAttachment(model, "Root")
		if a then
			if p.Light then
				local l = Instance.new("PointLight")
				l.Color, l.Brightness, l.Range, l.Shadows = p.Light.Color, p.Light.Brightness, p.Light.Range, false
				l:SetAttribute("SkinFXIdle", true)
				l.Parent = a
			else
				local e = emitter(a, p, SkinFX.Tuning.IdleSize)
				e.Rate = (p.Rate or 5) * SkinFX.Tuning.IdleRate
				e:SetAttribute("BaseRate", e.Rate)
				e.Brightness = SkinFX.Tuning.IdleBrightness
				e.Enabled = true
				e:SetAttribute("SkinFXIdle", true)
			end
		end
	end
end

-- first-person guns (under Camera.VantageViewmodel) get a lighter aura; checked a tick after
-- Apply because the viewmodel parents the gun right after skinning it
local _attach = SkinFX.AttachIdle
function SkinFX.AttachIdle(model: Instance, fxId: string?)
	_attach(model, fxId)
	if RunService:IsClient() then
		task.defer(function()
			if model:FindFirstAncestor("VantageViewmodel") then
				for _, d in model:GetDescendants() do
					if d:IsA("ParticleEmitter") and d:GetAttribute("SkinFXIdle") then
						d.Rate = (d:GetAttribute("BaseRate") or d.Rate) * SkinFX.Tuning.ViewmodelRate
					end
				end
			end
		end)
	end
end

function SkinFX.Impact(pos: Vector3, normal: Vector3, def, kind: string?)
	local k = akey(pos)
	local at = SkinFX._arrive[k]
	if at then
		SkinFX._arrive[k] = nil
		local wait = at - os.clock()
		if wait > 0.01 then
			task.delay(wait, SkinFX._ImpactNow, pos, normal, def, kind)
			return
		end
	end
	SkinFX._ImpactNow(pos, normal, def, kind)
end

-- ─── path helpers for bolts / beams / knife (stage 3) ───────────────────────
-- one mark (Marks spec) at a point: bolt trails (Quill), grenade trails (Havoc)
function SkinFX.EmitMark(S, pos: Vector3)
	local r = markRig(S)
	r[2].WorldPosition = pos
	r[1]:Emit(S.Count or 1)
end
-- a fading afterimage of a projectile head
function SkinFX.Ghost(pos: Vector3, color: Color3, size: number, life: number?)
	ensureStep()
	local p = ball(color, size)
	p.CFrame = CFrame.new(pos)
	p.Transparency = 0.45
	fadeTo(p, life or 0.18, p.Size * 0.4, 1, freeBallPart)
end
-- a laser's extras (Sig / strands / motes) between two points, without the core beam (Helix pulses)
function SkinFX.Extras(from: Vector3, to: Vector3, L, q: number?)
	local d = to - from
	local len = d.Magnitude
	if len < 0.5 then return end
	local cf = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	SkinFX._LaserExtras(from, to, len, d.Unit, cf, L, q or SkinFX.Detail(from))
end
-- a burst of emitters at a point (Havoc skin blast where the round lands); one shared rig per list
local burstRigs = setmetatable({}, { __mode = "k" })
function SkinFX.Burst(list, pos: Vector3, normal: Vector3, decal)
	local r = burstRigs[list]
	if not r or not r.A.Parent then
		local a = Instance.new("Attachment")
		a.Name = "SkinPoolBurst"
		a.Parent = Workspace.Terrain
		local E = {}
		for i, p in list do E[i] = emitter(a, p) end
		r = { A = a, E = E }
		burstRigs[list] = r
		Pool.Made += 1
	end
	local p0 = pos + normal * 0.15
	r.A.CFrame = CFrame.lookAt(p0, p0 + normal)
	local q = SkinFX.Detail(pos)
	for i, p in list do
		local n = p.Count or 1
		if q < 1 then n = math.max(1, math.floor(n * q + 0.5)) end
		r.E[i]:Emit(n)
	end
	if decal and q >= 0.35 then SkinFX._decal(pos, normal, decal) end
end

-- world-space hit accent for the local player's confirmed hits (stage 4): def.Hit = emitter list, hollow + brief
local hitAt, hitDef = -1, nil
local function localGunDef()
	if os.clock() - hitAt < 0.5 then return hitDef end
	hitAt, hitDef = os.clock(), nil
	local cam = Workspace.CurrentCamera
	if cam then
		for _, d in cam:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("SkinFX") and not string.find(d.Name, "Knife") and d:GetAttribute("WeaponId") ~= "Knife" then
				hitDef = SkinFX.Get(d:GetAttribute("SkinFX"))
				break
			end
		end
	end
	return hitDef
end
function SkinFX.HitAccent(pos: Vector3)
	local def = localGunDef()
	if not (def and def.Hit) then return end
	local cam = Workspace.CurrentCamera
	local nrm = if cam then (cam.CFrame.Position - pos).Unit else Vector3.yAxis
	SkinFX.Burst(def.Hit, pos, nrm)
end

-- Epic / hero shot designs (shot overhaul stage 3) live in EpicFX and override the generated defs
do
	local m = script.Parent:FindFirstChild("EpicFX")
	if m then
		local ok, E = pcall(require, m)
		if ok and E and E.Register then
			E.Register(SkinFX)
		elseif not ok then
			warn("[SkinFX] EpicFX failed: " .. tostring(E))
		end
	end
end

return SkinFX

