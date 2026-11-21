-- EpicFX: Epic-tier shot designs (shot overhaul stage 3, 2026-11-18)
-- Every Epic pattern + Epic hero gets its own signature: flash shape, beam mechanic (Laser.Sig), impact
-- archetype, rhythm (Every) and sustained-fire colour (Heat). Palettes come from the existing defs, so the
-- colours still match each pattern's texture. Shots stay straight laser beams (user decision 2026-11-14);
-- what changes is the beam's design and behaviour. Registered by SkinFX at load (overrides the generated
-- patternFX defs; heroes keep their Idle aura + light).
local W = script.Parent
local VFXKit = require(W:WaitForChild("VFXKit"))
local KT = VFXKit.Tex

local C, V, NR = Color3.fromRGB, Vector3.new, NumberRange.new
local WHITE = Color3.new(1, 1, 1)
local function NS(...)
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do
		table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(k)
end
local function CS(a, b)
	return if b then ColorSequence.new(a, b) else ColorSequence.new(a)
end
local function grow(a, b) return NS(0, a, 1, b) end
local function fade(a, b) return NS(0, a, 1, b) end
local TEX = {
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}

-- weapon class scale: flash size (f), beam width (w), fade (sniper lingers), light (fast-fire = lighter)
local K = {
	Vanguard = { f = 1, w = 0.09 },
	Sentinel = { f = 0.95, w = 0.09 },
	Spectre = { f = 0.7, w = 0.07 },
	Breacher = { f = 1.05, w = 0.06, light = true },
	Longshot = { f = 1.3, w = 0.12, fade = 0.32 },
	Riptide = { f = 0.75, w = 0.065, light = true },
	Bulwark = { f = 1.05, w = 0.1 },
	Verdict = { f = 1.2, w = 0.12 },
	Quill = { f = 0.6, w = 0.08 },
	Helix = { f = 0.8, w = 0.09 },
	Havoc = { f = 1.1, w = 0.1 },
	Knife = { f = 0.8, w = 0.08 },
}

-- ─── flash presets ──────────────────────────────────────────────────────
local function sparks(c, k, n, spread)
	return { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(c), Size = grow(0.18 * k, 0), Life = NR(0.06, 0.14), Speed = NR(10 * k, 22 * k), Spread = spread or 30, Count = n or 4, Drag = 4 }
end
local function core(a, k)
	return { Texture = KT.Glow, Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.45 * k, 0.1 * k), Transparency = fade(0.1, 1), Life = NR(0.04, 0.05), Speed = NR(0, 0), Count = 1, LockedToPart = true }
end
local function board(tex, a, b, k, size, flip, rot)
	return { Texture = tex, Flip = if flip then "Grid2x2" else nil, Color = CS(WHITE:Lerp(a, 0.25), b or a), Size = grow(size * k * 0.8, size * k * 1.15), Transparency = NS(0, 0.05, 0.6, 0.35, 1, 1), Life = NR(0.045, 0.06), Speed = NR(0, 0), Count = 1, Rotation = rot or NR(0, 360), LockedToPart = true }
end
local FLASH = {}
FLASH.Burst = function(a, b, k) return { { Texture = TEX.Fire, Color = CS(b:Lerp(WHITE, 0.6), a), Size = grow(0.42 * k, 0.1 * k), Life = NR(0.04, 0.06), Speed = NR(0.5, 1.5), Spread = 10, Count = 2 }, sparks(b, k, 5) } end
FLASH.Ring = function(a, b, k) return { core(a, k), { Texture = KT.Ring, Color = CS(a), Size = grow(0.15 * k, 0.9 * k), Transparency = fade(0.15, 1), Life = NR(0.08, 0.08), Speed = NR(0, 0), Count = 1, LockedToPart = true }, sparks(b, k, 3) } end
FLASH.Ripple = function(a, b, k) return { core(a, k), { Texture = KT.Ripple, Color = CS(b), Size = grow(0.2 * k, 1.1 * k), Transparency = fade(0.1, 1), Life = NR(0.09, 0.09), Speed = NR(0, 0), Count = 1, LockedToPart = true } } end
FLASH.Hex = function(a, b, k) return { board(KT.Hex, a, b, k, 0.55, true), sparks(b, k, 3) } end
FLASH.HexCell = function(a, b, k) return { core(a, k), board(KT.HexCell, a, b, k, 0.6, false, NR(0, 0)), sparks(b, k, 3) } end
FLASH.Star6 = function(a, b, k) return { board(KT.Star6, a, b, k, 0.6, true), sparks(b, k, 4) } end
FLASH.Slit = function(a, b, k) return { board(KT.Slit, a, b, k, 0.7, true, NR(0, 0)), { Texture = TEX.Smoke, Color = CS(C(70, 72, 80)), Size = grow(0.15 * k, 0.6 * k), Transparency = fade(0.5, 1), Life = NR(0.3, 0.45), Speed = NR(1, 2), Spread = 20, Count = 1 } } end
FLASH.Crown = function(a, b, k) return { board(KT.Crown, a, b, k, 0.65, true), board(KT.Glint, WHITE, a, k, 0.9, false, NR(-8, 8)) } end
FLASH.Cross = function(a, b, k) return { core(a, k), board(KT.Glint, a, b, k, 1.0, false, NR(0, 0)), board(KT.Glint, b, a, k, 0.7, false, NR(45, 45)) } end
FLASH.Glitch = function(a, b, k) return { board(KT.Glitch, a, a, k, 0.6, true, NR(0, 0)), board(KT.Glitch, b, b, k, 0.5, true, NR(180, 180)), board(KT.Pixel, WHITE, b, k, 0.4, true, NR(0, 0)) } end
FLASH.Static = function(a, b, k) return { board(KT.Static, WHITE, a, k, 0.5, true, NR(0, 0)), core(b, k) } end
FLASH.Pixel = function(a, b, k) return { board(KT.Pixel, a, b, k, 0.55, true, NR(0, 0)), core(a, k * 0.8) } end
FLASH.Puff = function(a, b, k) return { core(a, k), { Texture = TEX.Smoke, Color = CS(a:Lerp(WHITE, 0.35)), Size = grow(0.2 * k, 0.8 * k), Transparency = fade(0.45, 1), Life = NR(0.3, 0.5), Speed = NR(1, 2.5), Spread = 20, Count = 2 } } end
FLASH.Vent = function(a, b, k) return { core(WHITE, k), { Texture = TEX.Smoke, Color = CS(C(240, 245, 250)), Size = grow(0.3 * k, 1.3 * k), Transparency = fade(0.3, 1), Life = NR(0.25, 0.4), Speed = NR(4, 7), Spread = 25, Count = 3, Drag = 4 } } end
FLASH.Arc = function(a, b, k) return { board(KT.Plasma, a, b, k, 0.6, true), sparks(b, k, 4, 50) } end
FLASH.Shards = function(a, b, k) return { core(a, k), { Texture = KT.Shard, Flip = "Grid2x2", Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.3), b), Size = grow(0.2 * k, 0.03), Life = NR(0.08, 0.16), Speed = NR(10 * k, 18 * k), Spread = 35, Count = 6 } } end
FLASH.Bloom = function(a, b, k) return { { Texture = KT.Glow, Color = CS(WHITE:Lerp(a, 0.4), a), Size = grow(0.6 * k, 1.0 * k), Transparency = fade(0.2, 1), Life = NR(0.06, 0.08), Speed = NR(0, 0), Count = 1, LockedToPart = true }, sparks(b, k, 3) } end
FLASH.Splash = function(a, b, k) return { core(a, k), { Texture = KT.Drop, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.22 * k, 0.06), Life = NR(0.1, 0.2), Speed = NR(6 * k, 12 * k), Spread = 45, Count = 7, Accel = V(0, -25, 0) } } end
FLASH.Wire = function(a, b, k) return { board(KT.Wire, a, b, k, 0.55, true, NR(-10, 10)), core(a, k * 0.7) } end
FLASH.Bracket = function(a, b, k) return { board(KT.Bracket, a, b, k, 0.6, false, NR(0, 0)), core(a, k * 0.7) } end
FLASH.Glyph = function(a, b, k) return { board(KT.Glyph, a, b, k, 0.7, true, NR(0, 0)), core(a, k * 0.7) } end
FLASH.Chevron = function(a, b, k) return { board(KT.Chevron, a, b, k, 0.5, false, NR(0, 0)), sparks(b, k, 3) } end
FLASH.Implode = function(a, b, k) return { { Texture = KT.Ring, Color = CS(b, a), Size = grow(1.0 * k, 0.05), Transparency = fade(0.6, 0), Life = NR(0.07, 0.07), Speed = NR(0, 0), Count = 1, LockedToPart = true }, core(a, k * 0.6) } end
FLASH.Streak = function(a, b, k) return { core(a, k), { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE, a), Size = grow(0.3 * k, 0), Life = NR(0.05, 0.1), Speed = NR(30, 50), Spread = 8, Count = 8 } } end
FLASH.Moon = function(a, b, k) return { { Texture = KT.Glow, Color = CS(a), Size = grow(0.7 * k, 0.8 * k), Transparency = fade(0.25, 1), Life = NR(0.07, 0.09), Speed = NR(0, 0), Count = 1, LockedToPart = true }, { Texture = KT.Ring, Color = CS(b), Size = grow(0.5 * k, 0.75 * k), Transparency = fade(0.2, 1), Life = NR(0.07, 0.09), Speed = NR(0, 0), Count = 1, LockedToPart = true } } end
FLASH.Bubbles = function(a, b, k) return { core(a, k), { Texture = KT.Bubble, Color = CS(WHITE:Lerp(b, 0.4)), Size = grow(0.12 * k, 0.22 * k), Transparency = fade(0.1, 1), Life = NR(0.3, 0.6), Speed = NR(1.5, 4), Spread = 35, Count = 4, Accel = V(0, 4, 0) } } end
FLASH.Swarm = function(a, b, k) return { core(a, k * 0.6), { Texture = KT.Glow, Color = CS(WHITE, a), Size = grow(0.08 * k, 0), Life = NR(0.15, 0.35), Speed = NR(3, 8), Spread = 60, Count = 12, Drag = 3 } } end

-- stage 4 flash presets (heroes)
FLASH.Eye = function(a, b, k) return { board(KT.Eye, a, b, k, 0.8, false, NR(0, 0)), core(a, k * 0.7) } end
FLASH.Sun = function(a, b, k) return { core(a, k * 1.2), board(KT.Star6, a, b, k, 0.85, true), { Texture = KT.Ring, Color = CS(b), Size = grow(0.2 * k, 0.9 * k), Transparency = fade(0.2, 1), Life = NR(0.08, 0.08), Speed = NR(0, 0), Count = 1, LockedToPart = true } } end
FLASH.Horns = function(a, b, k) return { core(a, k), { Texture = TEX.Fire, Color = CS(b:Lerp(WHITE, 0.5), a), Size = grow(0.32 * k, 0.05), Life = NR(0.08, 0.12), Speed = NR(3, 6), Spread = 35, Count = 3, Dir = "Top", Accel = V(0, 6, 0) }, sparks(b, k, 4) } end
FLASH.Fangs = function(a, b, k) return { core(a, k), { Texture = TEX.Fire, Color = CS(b:Lerp(WHITE, 0.5), a), Size = grow(0.3 * k, 0.04), Life = NR(0.08, 0.12), Speed = NR(3, 5), Spread = 15, Count = 2, Dir = "Bottom" } } end
FLASH.TBar = function(a, b, k) return { board(KT.Slit, a, b, k, 1.0, true, NR(0, 0)), core(a, k * 0.8) } end
FLASH.Trident = function(a, b, k) return { core(a, k), sparks(WHITE:Lerp(a, 0.4), k, 3, 8), { Texture = KT.Drop, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.3), b), Size = grow(0.2 * k, 0.05), Life = NR(0.1, 0.2), Speed = NR(6 * k, 11 * k), Spread = 40, Count = 5, Accel = V(0, -20, 0) } } end
FLASH.Lava = function(a, b, k) return { { Texture = TEX.Fire, Color = CS(b:Lerp(WHITE, 0.6), a), Size = grow(0.45 * k, 0.1 * k), Life = NR(0.04, 0.06), Speed = NR(0.5, 1.5), Spread = 10, Count = 2 }, { Texture = KT.Glow, Color = CS(C(255, 220, 140), a), Size = grow(0.12 * k, 0.04), Life = NR(0.3, 0.5), Speed = NR(1, 3), Spread = 40, Count = 4, Accel = V(0, -30, 0) } } end

-- hit accents (stage 4): hollow and brief, on the enemy where the shot landed (never a screen overlay)
local HIT = {}
HIT.Ring = function(c) return { { Texture = KT.Ring, Color = CS(c), Size = grow(0.15, 1.0), Transparency = fade(0.15, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Count = 1 } } end
HIT.Ripple = function(c) return { { Texture = KT.Ripple, Color = CS(c), Size = grow(0.2, 1.2), Transparency = fade(0.15, 1), Life = NR(0.14, 0.14), Speed = NR(0, 0), Count = 1 } } end
HIT.Implode = function(c) return { { Texture = KT.Ring, Color = CS(c), Size = grow(1.1, 0.1), Transparency = fade(0.5, 0.1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Count = 1 } } end
HIT.Claw = function(c) return { { Texture = KT.Claw, Color = CS(WHITE:Lerp(c, 0.4), c), Size = grow(0.7, 0.9), Transparency = fade(0.05, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Count = 1, Rotation = NR(-20, 20) } } end
HIT.Sparkle = function(c) return { { Texture = KT.Glint, Color = CS(WHITE, c), Size = grow(0.9, 0.2), Transparency = fade(0.05, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 45) } } end
HIT.Cross = function(c) return { { Texture = KT.Glint, Color = CS(WHITE, c), Size = grow(1.1, 0.3), Transparency = fade(0.05, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0), RotSpeed = NR(300, 300) } } end
HIT.Eye = function(c) return { { Texture = KT.Eye, Color = CS(WHITE:Lerp(c, 0.3), c), Size = grow(0.6, 0.9), Transparency = fade(0.05, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) } } end
HIT.Petrify = function(c) return { { Texture = KT.Flake, Flip = "Grid2x2", Color = CS(C(170, 170, 165), c), Size = grow(0.12, 0.05), Transparency = fade(0, 1), Life = NR(0.15, 0.22), Speed = NR(2, 4), Spread = 70, Count = 4 }, HIT.Ring(c)[1] } end

-- ─── impact presets: returns (emitters, decal?) ─────────────────────────
local function ring(c, s, life, tex)
	return { Texture = tex or KT.Ring, Color = CS(c), Size = grow(0.15, s), Transparency = fade(0.2, 1), Life = NR(life or 0.2, life or 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 }
end
local function isparks(c, n, spd, grav)
	return { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(c), Size = grow(0.22, 0), Life = NR(0.1, 0.28), Speed = NR(spd or 8, (spd or 8) * 2), Spread = 55, Count = n or 7, Drag = 2, Accel = V(0, -(grav or 20), 0) }
end
local IMPACT = {}
IMPACT.Shock = function(a, b) return { { Texture = TEX.Shock, Color = CS(a), Size = grow(0.15, 1.1), Transparency = fade(0.25, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Spread = 0, Count = 1 }, isparks(b, 7) } end
IMPACT.Core = function(a, b) return { { Texture = KT.Glow, Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.9, 0.2), Transparency = fade(0.1, 1), Life = NR(0.1, 0.12), Speed = NR(0, 0), Count = 1 }, ring(b, 1.6), isparks(b, 5) } end
IMPACT.Shards = function(a, b) return { { Texture = KT.Shard, Flip = "Grid2x2", Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.3), b), Size = grow(0.3, 0.05), Life = NR(0.2, 0.4), Speed = NR(8, 16), Spread = 55, Count = 8, Accel = V(0, -30, 0) }, ring(a, 1.2, 0.15) } end
IMPACT.Pixels = function(a, b) return { { Texture = KT.Pixel, Flip = "Grid2x2", Color = CS(a, b), Size = grow(0.3, 0.1), Life = NR(0.25, 0.45), Speed = NR(3, 8), Spread = 60, Count = 6, Accel = V(0, -12, 0), Rotation = NR(0, 0) }, ring(b, 1.2, 0.12) } end
IMPACT.Nodes = function(a, b) return { { Texture = KT.Pixel, Flip = "Grid2x2", Color = CS(b, a), Size = grow(0.45, 0.35), Transparency = fade(0, 1), Life = NR(0.25, 0.35), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, isparks(a, 4) } end
IMPACT.Cracks = function(a, b) return { isparks(b, 5), ring(a, 0.9, 0.12) }, { Texture = KT.Crack, Color = b, Size = 1.4, Grow = 1.05, Life = 1.3, Transp = 0.15 } end
IMPACT.Implode = function(a, b) return { { Texture = KT.Ring, Color = CS(b, a), Size = grow(2.2, 0.05), Transparency = fade(0.7, 0), Life = NR(0.16, 0.16), Speed = NR(0, 0), Count = 1 }, { Texture = KT.Glow, Color = CS(WHITE:Lerp(a, 0.4)), Size = grow(0.1, 1.0), Transparency = NS(0, 1, 0.6, 1, 0.7, 0.1, 1, 1), Life = NR(0.26, 0.26), Speed = NR(0, 0), Count = 1 } } end
IMPACT.Splash = function(a, b) return { { Texture = KT.Drop, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.22, 0.06), Life = NR(0.3, 0.55), Speed = NR(8, 14), Spread = 35, Count = 9, Accel = V(0, -35, 0) }, ring(b, 2.2, 0.3, KT.Ripple) } end
IMPACT.Arcs = function(a, b) return { { Texture = KT.Plasma, Flip = "Grid2x2", Color = CS(WHITE, a), Size = grow(0.6, 0.9), Transparency = fade(0.1, 1), Life = NR(0.08, 0.14), Speed = NR(1, 3), Spread = 70, Count = 3 }, isparks(b, 6, 10) } end
IMPACT.Ripple = function(a, b) return { ring(a, 2.4, 0.3, KT.Ripple), { Texture = KT.Glow, Color = CS(b), Size = grow(0.6, 0.1), Transparency = fade(0.2, 1), Life = NR(0.08, 0.1), Speed = NR(0, 0), Count = 1 } } end
IMPACT.Glyph = function(a, b) return { { Texture = KT.Glyph, Flip = "Grid2x2", Color = CS(WHITE:Lerp(a, 0.2), a), Size = grow(0.5, 1.4), Transparency = fade(0, 1), Life = NR(0.3, 0.3), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, isparks(b, 4) }, { Texture = KT.Glyph, Color = a, Size = 1.1, Grow = 1.1, Life = 0.9, Transp = 0.25 } end
IMPACT.HexStamp = function(a, b) return { { Texture = KT.HexCell, Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.3, 1.5), Transparency = fade(0, 1), Life = NR(0.22, 0.22), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, isparks(b, 4) }, { Texture = KT.HexCell, Color = a, Size = 1.0, Grow = 1.2, Life = 0.8, Transp = 0.3 } end
IMPACT.Puddle = function(a, b) return { { Texture = TEX.Smoke, Color = CS(a:Lerp(WHITE, 0.3)), Size = grow(0.3, 1.1), Transparency = fade(0.45, 1), Life = NR(0.4, 0.7), Speed = NR(1, 2.5), Spread = 35, Count = 2 }, isparks(b, 3, 5) }, { Texture = KT.Glow, Color = a, Size = 1.3, Grow = 1.3, Life = 1.1, Transp = 0.35 } end
IMPACT.Gas = function(a, b) return { { Texture = TEX.Smoke, Color = CS(a:Lerp(WHITE, 0.3)), Size = grow(0.3, 1.3), Transparency = fade(0.4, 1), Life = NR(0.5, 0.8), Speed = NR(1, 3), Spread = 40, Count = 3, Drag = 2 }, { Texture = KT.Glint, Color = CS(b), Size = grow(0.35, 0.05), Life = NR(0.2, 0.4), Speed = NR(2, 5), Spread = 60, Count = 3 } } end
IMPACT.SmokeRing = function(a, b) return { ring(a:Lerp(WHITE, 0.4), 2.0, 0.45), { Texture = TEX.Smoke, Color = CS(b), Size = grow(0.3, 1.0), Transparency = fade(0.5, 1), Life = NR(0.5, 0.8), Speed = NR(0.5, 1.5), Spread = 30, Count = 2 } } end
IMPACT.Pillar = function(a, b) return { { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE, a), Size = grow(1.2, 0.2), Life = NR(0.25, 0.35), Speed = NR(14, 18), Spread = 2, Count = 3 }, ring(b, 1.6, 0.2) } end
IMPACT.Eclipse = function(a, b) return { ring(a, 1.9, 0.3), isparks(b, 4, 6) }, { Texture = KT.Glow, Color = C(25, 0, 0), Size = 1.2, Grow = 1.1, Life = 1.0, Transp = 0.1 } end
IMPACT.Sparkle = function(a, b) return { { Texture = KT.Glint, Color = CS(WHITE:Lerp(a, 0.3), b), Size = grow(0.6, 0.05), Life = NR(0.2, 0.4), Speed = NR(2, 6), Spread = 70, Count = 4, Rotation = NR(0, 45) }, ring(a, 1.0, 0.15) } end
IMPACT.Bubbles = function(a, b) return { { Texture = KT.Bubble, Color = CS(WHITE:Lerp(a, 0.4)), Size = grow(0.15, 0.3), Transparency = fade(0.1, 1), Life = NR(0.5, 0.9), Speed = NR(1, 3), Spread = 50, Count = 6, Accel = V(0, 5, 0) }, ring(b, 1.4, 0.2) } end
IMPACT.Static = function(a, b) return { { Texture = KT.Static, Flip = "Grid2x2", Color = CS(WHITE, a), Size = grow(0.6, 0.9), Transparency = fade(0.1, 1), Life = NR(0.12, 0.2), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, isparks(b, 5) } end
IMPACT.Wire = function(a, b) return { { Texture = KT.Wire, Flip = "Grid2x2", Color = CS(a), Size = grow(0.4, 1.2), Transparency = fade(0, 1), Life = NR(0.2, 0.2), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, { Texture = KT.Pixel, Flip = "Grid2x2", Color = CS(b), Size = grow(0.2, 0.05), Life = NR(0.3, 0.5), Speed = NR(2, 5), Spread = 70, Count = 5, Rotation = NR(0, 0) } } end
IMPACT.Flakes = function(a, b) return { { Texture = KT.Flake, Flip = "Grid2x2", Color = CS(a, b), Size = grow(0.14, 0.05), Life = NR(0.35, 0.7), Speed = NR(4, 9), Spread = 55, Count = 7, Accel = V(0, -16, 0), RotSpeed = NR(-260, 260) }, isparks(b, 3) } end
IMPACT.Swarm = function(a, b) return { { Texture = KT.Glow, Color = CS(WHITE, a), Size = grow(0.12, 0), Life = NR(0.3, 0.6), Speed = NR(3, 9), Spread = 80, Count = 14, Drag = 3 }, ring(b, 1.0, 0.15) } end
IMPACT.Chevrons = function(a, b) return { { Texture = KT.Chevron, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.2), a), Size = grow(0.3, 0.1), Life = NR(0.15, 0.25), Speed = NR(8, 14), Spread = 50, Count = 5 }, ring(b, 1.0, 0.12) } end
IMPACT.Brackets = function(a, b) return { { Texture = KT.Bracket, Color = CS(a), Size = grow(1.6, 0.6), Transparency = fade(0, 1), Life = NR(0.22, 0.22), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, isparks(b, 3) } end
IMPACT.Molten = function(a, b) return { { Texture = KT.Glow, Color = CS(WHITE:Lerp(a, 0.2), a), Size = grow(0.18, 0.05), Life = NR(0.4, 0.8), Speed = NR(4, 9), Spread = 50, Count = 8, Accel = V(0, -30, 0) }, { Texture = KT.Glow, Color = CS(b), Size = grow(1.0, 0.3), Transparency = fade(0.2, 1), Life = NR(0.12, 0.14), Speed = NR(0, 0), Count = 1 } }, { Texture = KT.Glow, Color = a:Lerp(C(30, 10, 0), 0.5), Size = 1.0, Grow = 1.15, Life = 1.2, Transp = 0.2 } end
IMPACT.Steel = function(a, b) return { isparks(WHITE:Lerp(b, 0.3), 12, 12, 35), { Texture = KT.Glint, Color = CS(WHITE, a), Size = grow(0.8, 0.1), Life = NR(0.08, 0.1), Speed = NR(0, 0), Count = 1 } } end
IMPACT.Dust = function(a, b) return { { Texture = KT.Dust, Flip = "Grid2x2", Color = CS(a), Size = grow(0.3, 1.2), Transparency = fade(0.2, 1), Life = NR(0.4, 0.7), Speed = NR(2, 4), Spread = 35, Count = 3, Drag = 4, Accel = V(0, -2, 0) }, { Texture = KT.Flake, Flip = "Grid2x2", Color = CS(a, b), Size = grow(0.1, 0.04), Life = NR(0.3, 0.6), Speed = NR(4, 8), Spread = 50, Count = 5, Accel = V(0, -20, 0) } } end
IMPACT.Tear = function(a, b) return { { Texture = TEX.Smoke, Color = CS(C(235, 240, 250)), Size = grow(0.3, 1.2), Transparency = fade(0.4, 1), Life = NR(0.35, 0.6), Speed = NR(3, 6), Spread = 25, Count = 3, Drag = 4 }, isparks(a, 5) }, { Texture = KT.Crack, Color = WHITE:Lerp(b, 0.2), Size = 1.2, Grow = 1.0, Life = 1.0, Transp = 0.05 } end
IMPACT.Heat = function(a, b) return { { Texture = KT.Glow, Color = CS(WHITE, a), Size = grow(1.4, 0.4), Transparency = fade(0.15, 1), Life = NR(0.16, 0.2), Speed = NR(0, 0), Count = 1 }, isparks(b, 5) } end
IMPACT.Plasma = function(a, b) return { { Texture = KT.Plasma, Flip = "Grid2x2", Color = CS(WHITE, a), Size = grow(0.9, 1.4), Transparency = fade(0.1, 1), Life = NR(0.1, 0.15), Speed = NR(0, 0), Count = 2 }, isparks(b, 5) } end
IMPACT.Cross = function(a, b) return { { Texture = KT.Glint, Color = CS(WHITE, a), Size = grow(1.6, 0.4), Transparency = fade(0, 1), Life = NR(0.3, 0.3), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0), RotSpeed = NR(400, 400) }, ring(b, 1.2, 0.15) } end
IMPACT.Weld = function(a, b) return { isparks(WHITE:Lerp(a, 0.2), 14, 10, 45), { Texture = KT.Glow, Color = CS(WHITE, a), Size = grow(0.8, 0.2), Transparency = fade(0.1, 1), Life = NR(0.06, 0.08), Speed = NR(0, 0), Count = 1 } } end
IMPACT.Warp = function(a, b) return { ring(a, 2.6, 0.18), { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE, b), Size = grow(0.35, 0), Life = NR(0.08, 0.15), Speed = NR(18, 30), Spread = 70, Count = 8 } } end

-- ─── beam helpers ───────────────────────────────────────────────────────
local function marks(tex, c, c2, spacing, size, life, o)
	o = o or {}
	return { Kind = "Marks", Spacing = spacing, Seq = o.seq, Count = o.count, Off = o.off, Start = o.start, Stop = o.stop, Max = o.max,
		E = { Texture = tex, Flip = if o.flip then "Grid2x2" else nil, Color = CS(c, c2), Size = NS(0, size, 1, size * (o.endK or 0.3)), Transparency = fade(o.t0 or 0.05, 1),
			Life = NR(life, life * 1.3), Speed = NR(o.spd or 0, (o.spd or 0) * 1.6), Spread = 180, Count = 1, Accel = o.accel, Drag = o.drag,
			Rotation = o.rot or NR(0, 360), RotSpeed = o.spin } }
end
local function motes(c1, c2, o)
	o = o or {}
	return { c1, c2, Texture = o.tex, Flip = o.flip, Size = o.size or 0.14, Density = o.density or 0.5, Accel = o.accel, Life = o.life, Transp = o.transp, Emission = o.emission }
end

-- ─── builder ────────────────────────────────────────────────────────────
local function build(wid, a, b, s, old)
	local k = K[wid] or K.Vanguard
	local fk = k.f * (s.FlashK or 1)
	local w = s.Width or k.w
	local laser: any = { Color = a, Core = s.Core, Width = w, Inner = s.Inner, Fade = s.Fade or k.fade, ColorTo = s.ColorTo }
	local st = s.Strands or "twin"
	local tw = s.Twist or 2.2
	local r = 0.085 * (w / 0.09)
	local sc = s.StrandColor or b
	if st == "twin" then
		laser.Strands = { { Color = sc, Radius = r, Twist = tw, Width = 0.035 * (w / 0.09), Phase = 0 }, { Color = sc, Radius = r, Twist = tw, Width = 0.035 * (w / 0.09), Phase = math.pi } }
	elseif st == "triple" then
		laser.Strands = {}
		for i = 0, 2 do
			table.insert(laser.Strands, { Color = sc, Radius = r * 0.8, Twist = tw, Width = 0.028 * (w / 0.09), Phase = i * 2.094 })
		end
	elseif st == "single" then
		laser.Strands = { { Color = sc, Radius = r, Twist = tw, Width = 0.035 * (w / 0.09), Phase = 0 } }
	end
	laser.Motes = s.Motes
	laser.Mist = s.Mist
	laser.Fire = s.Fire
	laser.Sig = s.Sig
	if s.Keep and old then
		for _, key in s.Keep do laser[key] = old.Tracer.Laser[key] end
	end
	local imp, decal = (IMPACT[s.Impact or "Shock"] or IMPACT.Shock)(s.ImpactA or a, s.ImpactB or b)
	local def: any = {
		Light = a, LightBright = 3.6,
		Flash = (FLASH[s.Flash or "Burst"] or FLASH.Burst)(s.FlashA or a, s.FlashB or b, fk),
		Tracer = { Laser = laser, Core = a:Lerp(WHITE, 0.6), Width = 0.035 },
		Impact = imp,
		Decal = s.Decal or decal,
		Heat = s.Heat,
		Sustain = s.Sustain,
		Bolt = s.Bolt, -- arcing rounds: { Marks, Ghost, Blink }
		BeamTex = s.BeamTex, -- Helix glow texture
		BeamL = s.BeamL, -- Helix: extras re-drawn along the beam every 0.12 s
		BeamEvery = s.BeamEvery,
		Swing = s.Swing, -- knife swing trail
		MuzzleProps = s.MuzzleProps, -- mesh muzzle sequence (stage 4)
		ImpactProps = s.ImpactProps, -- mesh debris on impact (stage 4)
		Constellation = s.Constellation, -- lines between a burst's endpoints
		Rack = s.Rack, -- burst at the ejection port when the pump / bolt is worked (stage 6)
		Hit = if s.Hit then (HIT[s.Hit] or HIT.Ring)(s.HitColor or a) else nil, -- hit accent
	}
	if s.Explode then
		def.Explode, def.ExplodeDecal = (IMPACT[s.Explode] or IMPACT.Shock)(s.ImpactA or a, s.ImpactB or b)
	end
	if s.Every then
		local alt = table.clone(laser)
		for key, val in s.Every do
			if key ~= "N" then alt[key] = val end
		end
		def.Every = { N = s.Every.N, Laser = alt }
	end
	return def
end

-- ─── designs (shot overhaul §5.3 / §5.4) ─────────────────────────────────
local RED, BLK = C(255, 40, 40), C(14, 14, 18)
local S = {}

S.Vanguard = {
	P_Amber = { Flash = "Ring", Twist = 1.6, Sig = { { Kind = "Pulses", Color = C(255, 240, 200), Size = 0.2, Count = 1, Speed = 240 } }, Impact = "Core",
		Every = { N = 5, Width = 0.15, Sig = { { Kind = "Pulses", Color = WHITE, Size = 0.38, Count = 1, Speed = 200 } } } },
	P_Carbon = { Flash = "Slit", Strands = "none", Inner = BLK, Sig = { { Kind = "Dashes", Color = C(225, 236, 255), Len = 0.6, Gap = 0.45, Width = 0.05 } }, Impact = "Flakes", ImpactA = C(30, 30, 36) },
	P_Viridian = { Flash = "Puff", Twist = 1.2, Mist = motes(C(200, 255, 225), C(60, 230, 130), { tex = TEX.Smoke, size = 0.5, density = 0.3, life = { 0.5, 0.8 }, transp = 0.6, accel = V(0, 0.4, 0), emission = 0.5 }),
		Sig = { marks(KT.Glint, WHITE, C(60, 230, 130), 6, 0.3, 0.4, { off = 0.4 }) }, Impact = "Gas" },
	P_Pulsar = { Flash = "Cross", Strands = "none", Sig = { { Kind = "Pulses", Color = C(255, 200, 240), Size = 0.2, Count = 3, Gap = 0.035, Speed = 260 } }, Impact = "Cross", Heat = { Color = C(110, 150, 255), Max = 14 } },
	P_Signal = { Flash = "Glitch", Strands = "none", Sig = { { Kind = "Glitch", Colors = { C(255, 60, 170), C(40, 230, 255), WHITE }, Segs = 8, Jitter = 0.28, Width = 0.07 } }, Impact = "Pixels" },
	P_Cryo = { Flash = "Shards", Motes = motes(C(240, 250, 255), C(140, 215, 255), { tex = KT.Flake, flip = "Grid2x2", size = 0.1, density = 0.4, accel = V(0, -3, 0) }), Impact = "Cracks" },
	P_Camo = { Flash = "Bloom", FlashK = 0.7, Strands = "none", Inner = C(20, 40, 44), Sig = { { Kind = "Ribbon", c1 = C(60, 200, 200), c2 = C(160, 120, 235), Width = 0.35, Curve = 0.6, Transp = 0.72, Dur = 0.25 } }, Impact = "Ripple" },
	P_Circuit = { Flash = "HexCell", Strands = "none", Sig = { { Kind = "Trace", Color = C(255, 200, 80), Step = 1.3, Off = 0.17, Seq = 0.003 } }, Impact = "Nodes" },
	P_Plasma = { Flash = "Arc", Strands = "triple", Twist = 4, Motes = motes(C(230, 220, 255), C(120, 120, 255)), Impact = "Plasma", Heat = { Color = C(220, 200, 255), Max = 12 } },
	P_DarkMatter = { Flash = "Implode", Inner = C(8, 0, 16), Core = C(60, 20, 100), Motes = motes(C(250, 210, 255), C(130, 50, 230), { accel = V(0, -0.5, 0) }), Impact = "Implode" },
	Archangel = { Flash = "Crown", FlashA = C(255, 220, 140), FlashB = C(255, 240, 200), Keep = { "Rings" }, Strands = "none",
		Motes = motes(C(255, 245, 210), C(255, 200, 90), { tex = KT.Glint, size = 0.14, density = 0.35, accel = V(0, -1.2, 0), life = { 0.5, 0.8 } }),
		Impact = "Ripple", Decal = { Texture = KT.Ripple, Color = C(255, 215, 120), Size = 1.2, Grow = 1.2, Life = 0.9, Transp = 0.2 },
		Every = { N = 5, Width = 0.13 } },
}

S.Sentinel = {
	P_Magma = { Flash = "Burst", Width = 0.1, Motes = motes(C(255, 220, 140), C(255, 80, 10), { size = 0.12, density = 0.45, accel = V(0, -6, 0) }), Impact = "Molten", Every = { N = 3, Width = 0.17 } },
	P_Hex = { Flash = "HexCell", Strands = "none", Sig = { marks(KT.HexCell, WHITE, C(40, 200, 255), 3, 0.5, 0.25, { seq = 0.002, endK = 0.6 }) }, Impact = "HexStamp", Every = { N = 3, Width = 0.15 } },
	P_Aurora = { Flash = "Bloom", Strands = "none", Sig = { { Kind = "Ribbon", c1 = C(40, 230, 150), c2 = C(190, 90, 255), Width = 0.6, Curve = 2, Transp = 0.45, Dur = 0.4 } }, Impact = "Ripple",
		Every = { N = 3, Sig = { { Kind = "Ribbon", c1 = C(40, 230, 150), c2 = C(190, 90, 255), Width = 1.0, Curve = 2.6, Transp = 0.4, Dur = 0.5 } } } },
	P_Topo = { Flash = "Ripple", Strands = "single", Twist = 1.2, Sig = { marks(KT.Ripple, C(170, 255, 240), C(60, 220, 255), 5, 0.2, 0.35, { endK = 6, seq = 0.002 }) }, Impact = "Ripple",
		Decal = { Texture = KT.Ripple, Color = C(120, 240, 255), Size = 1.4, Grow = 1.25, Life = 1.0, Transp = 0.3 } },
	P_Damascus = { Flash = "Star6", Strands = "none", Core = C(255, 235, 235), Sig = { { Kind = "Wave", Color = C(255, 150, 130), Amp = 0.1, Wavelength = 1.6 }, { Kind = "Wave", Color = C(255, 220, 210), Amp = 0.1, Wavelength = 1.6, Phase = math.pi } }, Impact = "Steel" },
	P_Toxic = { Flash = "Puff", Motes = motes(C(230, 255, 160), C(100, 220, 30), { tex = KT.Bubble, size = 0.12, density = 0.35, accel = V(0, 2, 0) }), Impact = "Puddle" },
	P_Prism = { Flash = "Shards", Strands = "none", Sig = { { Kind = "Prism", Colors = { C(255, 120, 230), C(120, 230, 255), C(255, 240, 120) }, Radius = 0.26 } }, Impact = "Flakes" },
	P_Kintsugi = { Flash = "Star6", Strands = "none", Inner = BLK, Sig = { { Kind = "Zigzag", Color = C(255, 205, 90), Core = C(255, 250, 230), Amp = 0.07, Kink = 1.2, Width = 0.035, Max = 30 } }, Impact = "Cracks", ImpactB = C(255, 205, 90) },
	P_SimGrid = { Flash = "Wire", Strands = "none", Sig = { marks(KT.Wire, C(60, 230, 255), C(255, 60, 210), 4, 0.45, 0.3, { flip = true, seq = 0.002, endK = 0.8, rot = NR(0, 0) }) }, Impact = "Wire",
		Every = { N = 3, Width = 0.14 } },
	P_Cobalt = { Flash = "Splash", Twist = 2.6, Motes = motes(C(180, 215, 255), C(40, 100, 255), { tex = KT.Drop, size = 0.12, density = 0.4, accel = V(0, -8, 0) }), Impact = "Splash" },
	StormHerald = { Flash = "Arc", Keep = { "Strands" }, Impact = "Arcs", Decal = { Texture = KT.Crack, Color = C(150, 200, 255), Size = 1.2, Grow = 1.0, Life = 0.9, Transp = 0.2 },
		Every = { N = 3, Sig = { { Kind = "Zigzag", Color = C(120, 180, 255), Core = WHITE, Amp = 0.45, Kink = 2.4, Width = 0.08 }, { Kind = "Arcs", Color = C(170, 210, 255), Count = 3 } } } },
}

S.Spectre = {
	P_Venom = { Flash = "Puff", Twist = 3.4, Motes = motes(C(200, 255, 140), C(40, 230, 90), { tex = KT.Drop, size = 0.1, density = 0.35, accel = V(0, -9, 0) }), Impact = "Splash" },
	P_Ion = { Flash = "Arc", Strands = "none", Sig = { { Kind = "Zigzag", Color = C(90, 150, 255), Amp = 0.14, Kink = 1.6, Width = 0.05 }, { Kind = "Arcs", Color = C(230, 240, 255), Count = 4 } }, Impact = "Arcs" },
	P_BloodMoon = { Flash = "Moon", Mist = motes(C(160, 20, 20), C(60, 0, 0), { tex = TEX.Smoke, size = 0.4, density = 0.25, life = { 0.4, 0.6 }, transp = 0.6, emission = 0.2 }), Impact = "Eclipse" },
	P_Abyss = { Flash = "Bloom", Sig = { marks(KT.Glow, C(160, 255, 230), C(20, 200, 180), 2, 0.14, 0.7, { accel = V(0, 0.6, 0), off = 0.3 }) }, Impact = "Bubbles" },
	P_DeadChannel = { Flash = "Static", Strands = "none", Sig = { { Kind = "Glitch", Colors = { WHITE, C(255, 40, 70) }, Segs = 6, Jitter = 0.18, Width = 0.06 }, marks(KT.Static, WHITE, C(255, 40, 70), 3, 0.35, 0.15, { flip = true, rot = NR(0, 0) }) }, Impact = "Static" },
	P_Splinter = { Flash = "Shards", Strands = "none", Motes = motes(C(210, 216, 224), C(255, 122, 26), { tex = KT.Shard, flip = "Grid2x2", size = 0.16, density = 0.4, accel = V(0, -10, 0) }), Impact = "Shards" },
	P_Hyperspace = { Flash = "Streak", Strands = "none", Width = 0.06, Sig = { { Kind = "Streaks", Color = C(230, 215, 255), Count = 10, R0 = 0.1, R1 = 0.6, Min = 2, Max = 6 } }, Impact = "Warp" },
	P_Opal = { Flash = "Bloom", ColorTo = C(255, 170, 230), Twist = 2.8, Motes = motes(WHITE, C(200, 170, 255), { tex = KT.Glint, size = 0.12, density = 0.35 }), Impact = "Sparkle" },
	P_Rust = { Flash = "Burst", Strands = "single", Motes = motes(C(232, 120, 40), C(120, 60, 30), { tex = KT.Flake, flip = "Grid2x2", size = 0.09, density = 0.45, accel = V(0, -8, 0), emission = 0.3 }), Impact = "Dust", ImpactA = C(170, 90, 50) },
	P_Spectral = { Flash = "Puff", Strands = "none", Sig = { { Kind = "Ribbon", c1 = C(220, 215, 255), c2 = C(150, 140, 220), Width = 0.5, Curve = 1.4, Transp = 0.55, Dur = 0.45 } }, Impact = "SmokeRing" },
	PlagueDoctor = { Flash = "Puff", Strands = "none", Width = 0.06, Motes = motes(C(200, 255, 160), C(80, 220, 60), { tex = KT.Drop, size = 0.1, density = 0.4, accel = V(0, -10, 0) }),
		Sig = { marks(KT.Bubble, C(200, 255, 170), C(90, 230, 70), 4, 0.16, 0.6, { accel = V(0, 1.5, 0), off = 0.15 }) }, Impact = "Puddle" },
}

S.Breacher = {
	P_Plating = { Flash = "HexCell", Strands = "none", Sig = { marks(KT.Chevron, WHITE, C(255, 50, 40), 4, 0.22, 0.15, { rot = NR(0, 0) }) }, Impact = "Nodes" },
	P_Reactor = { Flash = "Ring", Strands = "none", Impact = "Core" },
	P_Conduit = { Flash = "Arc", Strands = "none", Sig = { { Kind = "Arcs", Color = C(240, 200, 255), Count = 1, Len = 0.6 } }, Impact = "Plasma" },
	P_Lattice = { Flash = "Wire", Strands = "none", Sig = { { Kind = "Dashes", Color = C(200, 255, 230), Len = 0.5, Gap = 0.9, Width = 0.06, Seq = 0.004 } }, Impact = "Nodes" },
	P_Cells = { Flash = "Pixel", Strands = "none", Impact = "Arcs" },
	P_Titanium = { Flash = "Star6", Strands = "none", Color = C(255, 200, 120), ColorTo = C(80, 120, 255), Impact = "Steel" },
	P_Mainframe = { Flash = "Pixel", Strands = "none", Sig = { marks(KT.Pixel, C(60, 255, 120), C(60, 140, 255), 3, 0.18, 0.15, { flip = true, rot = NR(0, 0) }) }, Impact = "Pixels" },
	P_Thermite = { Flash = "Burst", Strands = "none", Core = WHITE, Motes = motes(C(255, 240, 200), C(255, 140, 40), { size = 0.1, density = 0.2, accel = V(0, -8, 0) }), Impact = "Molten" },
	P_Tread = { Flash = "Burst", Strands = "none", Impact = "Steel", Decal = { Texture = KT.Crack, Color = C(60, 60, 66), Size = 0.6, Grow = 1, Life = 1.2, Transp = 0.2 } },
	P_Shockwave = { Flash = "Ring", FlashK = 1.3, Strands = "none", Impact = "Shock" },
	IroncladSteamworks = { Flash = "Vent", Strands = "none", Mist = motes(C(240, 240, 240), C(200, 200, 200), { tex = TEX.Smoke, size = 0.35, density = 0.15, life = { 0.4, 0.6 }, transp = 0.65, emission = 0 }),
		Impact = "Steel", ImpactB = C(255, 170, 80) },
}

S.Longshot = {
	P_Glyph = { Flash = "Glyph", Strands = "single", Twist = 1.2, Sig = { marks(KT.Glyph, WHITE, C(80, 230, 255), 6, 0.6, 0.45, { flip = true, seq = 0.004, rot = NR(0, 0), endK = 0.8 }) }, Impact = "Glyph" },
	P_Waveform = { Flash = "Ring", Strands = "none", Sig = { { Kind = "Wave", Color = C(255, 70, 170), Amp = 0.22, Wavelength = 3, Dur = 0.32 }, { Kind = "Wave", Color = C(60, 255, 220), Amp = 0.12, Wavelength = 1.5, Dur = 0.32, Axis = "v" } }, Impact = "Ripple" },
	P_Cascade = { Flash = "Pixel", Strands = "none", Sig = { marks(KT.Glyph, C(255, 240, 200), C(255, 140, 20), 2.5, 0.28, 0.6, { flip = true, accel = V(0, -6, 0), rot = NR(0, 0), endK = 0.6 }) }, Impact = "Pixels" },
	P_Targeting = { Flash = "Bracket", Strands = "single", Twist = 1, Sig = { marks(KT.Bracket, RED, C(255, 190, 180), 8, 0.35, 0.3, { rot = NR(0, 0), endK = 0.7 }) }, Impact = "Brackets" },
	P_Gravity = { Flash = "Implode", Sig = { { Kind = "Wave", Color = C(255, 230, 255), Amp = 0.35, Arc = true, Dur = 0.14 } }, Impact = "Implode" },
	P_Nanite = { Flash = "Swarm", Strands = "none", Width = 0.07, Sig = { marks(KT.Glow, WHITE, C(60, 200, 230), 0.9, 0.1, 0.5, { spd = 1.5, drag = 2, off = 0.12 }) }, Impact = "Swarm" },
	P_Breach = { Flash = "Vent", Sig = { marks(TEX.Smoke, C(230, 236, 250), C(200, 210, 230), 7, 0.4, 0.5, { spd = 2, endK = 3 }) }, Impact = "Tear" },
	P_StarChart = { Flash = "Cross", Sig = { marks(KT.Glint, WHITE, C(255, 210, 120), 5, 0.4, 0.5, { seq = 0.002, rot = NR(0, 0) }) }, Impact = "Sparkle" },
	P_Thermal = { Flash = "Bloom", Strands = "none", Color = C(255, 240, 200), Core = WHITE, ColorTo = C(60, 90, 255), Impact = "Heat" },
	P_Faceted = { Flash = "Shards", Strands = "none", Sig = { { Kind = "Glitch", Colors = { C(60, 200, 230), C(150, 240, 255) }, Segs = 9, Jitter = 0.02, Len = 2.4, Width = 0.1, Flicker = 0 } }, Impact = "Shards" },
	StrixNightwatch = { Flash = "Ripple", FlashA = C(150, 200, 255), Strands = "none", Width = 0.08, Fade = 0.4,
		Sig = { marks(KT.Glow, C(200, 230, 255), C(90, 150, 255), 3, 0.14, 0.7, { seq = 0.0015 }) }, Impact = "Sparkle" },
}

S.Riptide = {
	P_Overclock = { Flash = "Burst", Strands = "none", Heat = { Color = C(255, 40, 30), Max = 12 }, Impact = "Shock" },
	P_Vector = { Flash = "Chevron", Strands = "none", Sig = { marks(KT.Chevron, WHITE, C(255, 40, 160), 4, 0.3, 0.15, { rot = NR(0, 0) }) }, Impact = "Chevrons" },
	P_ArcWeld = { Flash = "Arc", Strands = "none", Sig = { { Kind = "Zigzag", Color = C(170, 210, 255), Amp = 0.1, Kink = 1.4, Width = 0.04, Max = 10 } }, Impact = "Weld" },
	P_KillSwitch = { Flash = "Bracket", Strands = "none", Sig = { { Kind = "Dashes", Color = BLK, Len = 0.4, Gap = 0.5, Width = 0.08 } }, Impact = "Brackets" },
	P_GridRun = { Flash = "Pixel", Strands = "none", Sig = { { Kind = "Trace", Color = C(40, 220, 255), Step = 2, Off = 0.1, Seq = 0.002, Width = 0.03 } }, Impact = "Nodes" },
	P_Static = { Flash = "Arc", Strands = "none", Sig = { { Kind = "Arcs", Color = C(255, 80, 120), Count = 3, Len = 0.6 } }, Impact = "Arcs" },
	P_Coolant = { Flash = "Puff", Strands = "none", Motes = motes(C(220, 255, 250), C(0, 180, 160), { tex = KT.Drop, size = 0.1, density = 0.3, accel = V(0, -9, 0) }), Impact = "Splash" },
	P_Nanoweave = { Flash = "Ring", Strands = "triple", Twist = 3, Impact = "Ripple" },
	P_Redline = { Flash = "Streak", Strands = "none", Sig = { { Kind = "Streaks", Color = C(255, 120, 90), Count = 4, R0 = 0.1, R1 = 0.35 } }, Heat = { Color = C(255, 230, 200), Max = 14 }, Impact = "Shock" },
	P_PulseDrive = { Flash = "Ring", Strands = "none", Sig = { { Kind = "Pulses", Color = C(220, 255, 230), Size = 0.16, Count = 2, Gap = 0.03, Speed = 280 } }, Impact = "Ripple" },
	AbyssDiver = { Flash = "Bubbles", Strands = "none", Motes = motes(C(255, 230, 190), C(255, 170, 80), { tex = KT.Bubble, size = 0.12, density = 0.3, accel = V(0, 3, 0) }), Impact = "Bubbles",
		Heat = { Color = C(255, 240, 210), Max = 14 } },
}

local HEAT = { From = 10, E = { Texture = KT.Glow, Color = CS(C(255, 130, 50), C(255, 50, 20)), Size = grow(0.35, 0.2), Transparency = fade(0.35, 1), Life = NR(0.25, 0.35), Speed = NR(0, 0), Count = 1, LockedToPart = true } }

S.Bulwark = { -- LMG: sustained fire is the point (barrel heat glow from 10 rounds on most)
	P_Siege = { Flash = "Burst", FlashK = 1.1, Width = 0.11, Strands = "none", Impact = "Steel", Sustain = HEAT, Decal = { Texture = KT.Crack, Color = C(70, 66, 60), Size = 0.6, Grow = 1, Life = 1.2, Transp = 0.2 } },
	P_Bastion = { Flash = "Bracket", Strands = "none", Sig = { marks(KT.Wire, C(220, 245, 255), C(60, 200, 255), 5, 0.4, 0.25, { flip = true, rot = NR(0, 0), endK = 0.8 }) }, Impact = "Brackets" },
	P_Forge = { Flash = "Burst", Strands = "single", Heat = { Color = C(255, 250, 230), Max = 16 }, Motes = motes(C(255, 230, 160), C(255, 120, 40), { size = 0.11, density = 0.35, accel = V(0, -6, 0) }), Impact = "Molten", Sustain = HEAT },
	P_Dreadnought = { Flash = "Ring", FlashK = 1.4, Width = 0.13, Strands = "none", Impact = "Dust", ImpactA = C(170, 170, 176) },
	P_UrbanDigi = { Flash = "Pixel", Strands = "none", Sig = { marks(KT.Pixel, C(230, 236, 245), C(120, 130, 150), 3, 0.22, 0.2, { flip = true, rot = NR(0, 0) }) }, Impact = "Pixels" },
	P_AmmoBelt = { Flash = "Burst", Strands = "none", Impact = "Steel", Sustain = HEAT,
		Every = { N = 5, Width = 0.2, Sig = { { Kind = "Pulses", Color = C(255, 230, 160), Size = 0.3, Count = 1, Speed = 240 } } } },
	P_ShieldHex = { Flash = "HexCell", Strands = "none", Sig = { marks(KT.HexCell, C(255, 230, 170), C(255, 140, 30), 6, 0.45, 0.25, { endK = 0.6 }) }, Impact = "Ripple" },
	P_BlackOps = { Flash = "Slit", FlashK = 0.6, Strands = "none", Color = C(110, 255, 120), Core = C(220, 255, 220), Width = 0.07, Impact = "Shock", ImpactA = C(110, 255, 120) },
	P_FusionCoils = { Flash = "Ring", Strands = "triple", Twist = 3.6, Impact = "Arcs", Sustain = HEAT },
	P_Tactical = { Flash = "Bracket", Strands = "single", Twist = 1.2, Sig = { marks(KT.Bracket, C(240, 255, 230), C(170, 255, 140), 6, 0.28, 0.2, { rot = NR(0, 0) }) }, Impact = "Ripple" },
}

S.Verdict = { -- hand cannon: punchy, thick
	P_Gavel = { Flash = "Ring", FlashK = 1.2, Strands = "none", Impact = "Shock", Decal = { Texture = KT.Ripple, Color = C(255, 210, 110), Size = 1.0, Grow = 1.15, Life = 0.9, Transp = 0.25 } },
	P_Noir = { Flash = "Burst", FlashA = C(235, 235, 235), FlashB = C(150, 150, 155), Color = C(238, 238, 238), StrandColor = C(140, 140, 146), Strands = "single", Impact = "Gas", ImpactA = C(180, 180, 186), ImpactB = C(230, 40, 40) },
	P_Sheriff = { Flash = "Star6", Strands = "none", Core = WHITE, Impact = "Steel" },
	P_Deco = { Flash = "Crown", Strands = "none", Sig = { { Kind = "Prism", Colors = { C(255, 210, 110), C(255, 240, 190), C(255, 190, 80) }, Radius = 0.14 } }, Impact = "Flakes" },
	P_Judgement = { Flash = "Cross", FlashA = C(255, 245, 220), Strands = "none", Color = C(255, 235, 200), Core = WHITE, Impact = "Pillar", ImpactA = C(255, 230, 180) },
	P_Desert = { Flash = "Burst", Strands = "none", Mist = motes(C(240, 220, 190), C(200, 170, 130), { tex = TEX.Smoke, size = 0.35, density = 0.2, life = { 0.4, 0.6 }, transp = 0.7, emission = 0 }), Impact = "Dust", ImpactA = C(220, 190, 140) },
	P_Executioner = { Flash = "Slit", FlashA = C(255, 60, 70), Strands = "none", Impact = "Cracks", ImpactB = C(255, 60, 70) },
	P_Vault = { Flash = "Cross", Twist = 2, Motes = motes(C(255, 235, 170), C(255, 200, 90), { tex = KT.Glint, size = 0.12, density = 0.4 }), Impact = "Sparkle" },
	P_Ledger = { Flash = "Glyph", Strands = "none", Sig = { marks(KT.Glyph, C(220, 255, 250), C(140, 255, 240), 5, 0.4, 0.4, { flip = true, rot = NR(0, 0), t0 = 0.3 }) }, Impact = "Glyph" },
	P_SilverBullet = { Flash = "Moon", FlashA = C(220, 235, 255), Strands = "none", Core = WHITE, Impact = "Ripple", ImpactA = C(220, 235, 255) },
}

S.Quill = { -- crossbow bolts: the path carries the design (Bolt), the hit uses the impact preset
	P_ShadowRail = { Flash = "Implode", Impact = "SmokeRing", Bolt = { Marks = marks(TEX.Smoke, C(110, 70, 200), C(40, 20, 80), 1.2, 0.35, 0.45, { endK = 2 }) } },
	P_Cloak = { Flash = "Bloom", FlashK = 0.6, Impact = "Ripple", Bolt = { Marks = marks(KT.Ripple, C(200, 255, 245), C(120, 255, 230), 3, 0.15, 0.3, { endK = 5 }) } },
	P_Fletch = { Flash = "Chevron", Impact = "Shards", Bolt = { Ghost = true, Marks = marks(KT.Chevron, WHITE, C(60, 220, 255), 2, 0.25, 0.2, { rot = NR(0, 0) }) } },
	P_Sonar = { Flash = "Ripple", Impact = "Ripple", Bolt = { Marks = marks(KT.Ripple, C(200, 255, 200), C(60, 255, 120), 6, 0.2, 0.4, { endK = 8 }) } },
	P_Ghost = { Flash = "Bloom", Impact = "SmokeRing", Bolt = { Ghost = true } },
	P_LaserMesh = { Flash = "Wire", Impact = "Wire", Bolt = { Marks = marks(KT.Wire, C(255, 220, 220), RED, 3, 0.3, 0.25, { flip = true, rot = NR(0, 0) }) } },
	P_Midnight = { Flash = "Cross", Impact = "Sparkle", Bolt = { Marks = marks(KT.Glint, WHITE, C(255, 200, 90), 2, 0.25, 0.45, { off = 0.2 }) } },
	P_Arctic = { Flash = "Hex", Impact = "Shards", Bolt = { Marks = marks(KT.Flake, WHITE, C(170, 230, 255), 1.5, 0.12, 0.6, { flip = true, accel = V(0, -4, 0), off = 0.15 }) } },
	P_ToxinCoil = { Flash = "Puff", Impact = "Puddle", Bolt = { Marks = marks(KT.Glow, C(240, 255, 200), C(150, 255, 40), 0.8, 0.14, 0.35, { off = 0.3 }) } },
	P_Moonlit = { Flash = "Moon", Impact = "Ripple", Bolt = { Ghost = true, Marks = marks(KT.Glint, WHITE, C(190, 210, 255), 3, 0.3, 0.35) } },
}

S.Helix = { -- continuous beam: glow texture + extras re-drawn along it every 0.12 s (BeamL)
	P_Torsion = { Flash = "Ring", Impact = "Ripple", BeamTex = KT.Dash, BeamL = { Sig = { { Kind = "Wave", Color = C(60, 255, 220), Amp = 0.15, Wavelength = 1.5, Dur = 0.14 } } } },
	P_Collider = { Flash = "Ring", Impact = "Warp", BeamL = { Sig = { { Kind = "Pulses", Color = C(255, 160, 230), Size = 0.18, Count = 2, Gap = 0.03, Speed = 320 } } } },
	P_Interference = { Flash = "Ripple", Impact = "Ripple", BeamL = { Sig = { { Kind = "Wave", Color = C(255, 140, 230), Amp = 0.12, Wavelength = 1.2, Dur = 0.14 }, { Kind = "Wave", Color = C(120, 230, 255), Amp = 0.12, Wavelength = 1.2, Phase = math.pi, Dur = 0.14 } } } },
	P_Tesla = { Flash = "Arc", Impact = "Arcs", BeamL = { Sig = { { Kind = "Arcs", Color = C(240, 225, 255), Count = 3, Len = 0.8 }, { Kind = "Zigzag", Color = C(170, 100, 255), Amp = 0.15, Kink = 1.6, Width = 0.04, Dur = 0.12 } } } },
	P_Supercon = { Flash = "Hex", Impact = "Shards", BeamTex = KT.Flake, BeamL = { Sig = { marks(KT.Flake, WHITE, C(120, 200, 255), 2, 0.12, 0.6, { flip = true, accel = V(0, 0.8, 0), off = 0.25 }) } } },
	P_FusionPlasma = { Flash = "Bloom", Impact = "Heat", BeamL = { Fire = { C(255, 200, 120), C(255, 80, 180), Size = 0.35, Density = 0.25 } } },
	P_Photon = { Flash = "Cross", Impact = "Sparkle", BeamL = { Strands = { { Color = C(255, 200, 120), Radius = 0.08, Twist = 3, Width = 0.025, Phase = 0 }, { Color = C(120, 220, 255), Radius = 0.08, Twist = 3, Width = 0.025, Phase = 2.09 }, { Color = WHITE, Radius = 0.08, Twist = 3, Width = 0.025, Phase = 4.19 } } } },
	P_Spectrum = { Flash = "Shards", Impact = "Flakes", BeamL = { Sig = { { Kind = "Prism", Colors = { C(255, 90, 90), C(90, 255, 120), C(90, 140, 255) }, Radius = 0.22, Dur = 0.14 } } } },
	P_CleanRoom = { Flash = "Bloom", Impact = "Ripple", BeamTex = "", BeamL = { Sig = { { Kind = "Pulses", Color = WHITE, Size = 0.22, Count = 1, Speed = 120 } } }, BeamEvery = 0.3 },
	P_Antimatter = { Flash = "Implode", Impact = "Implode", BeamL = { Inner = C(10, 0, 14), Width = 0.12 } },
}

S.Havoc = { -- launcher: the grenade's path + a skin blast where it lands (kept inside the real blast)
	P_Demolition = { Flash = "Burst", Impact = "Dust", Explode = "Dust", ImpactA = C(255, 170, 60), Bolt = { Marks = marks(TEX.Smoke, C(230, 200, 150), C(160, 140, 110), 1.6, 0.3, 0.5, { endK = 2.5 }) } },
	P_Detonator = { Flash = "Burst", Impact = "Core", Explode = "Core", Bolt = { Blink = true } },
	P_Scorched = { Flash = "Burst", Impact = "Molten", Explode = "Molten", Bolt = { Marks = marks(TEX.Fire, C(255, 220, 120), C(255, 80, 10), 1, 0.4, 0.3, { endK = 0.1 }) } },
	P_Payload = { Flash = "Burst", Impact = "Chevrons", Explode = "Chevrons", Bolt = { Marks = marks(TEX.Smoke, C(240, 230, 190), C(200, 190, 150), 1.6, 0.3, 0.5, { endK = 2.5 }) } },
	P_Shrapnel = { Flash = "Shards", Impact = "Shards", Explode = "Shards" },
	P_PopBlast = { Flash = "Cross", Impact = "Flakes", Explode = "Flakes", ImpactB = C(80, 220, 255), Bolt = { Marks = marks(KT.Glint, C(255, 230, 80), C(240, 40, 50), 1.5, 0.3, 0.35) } },
	P_Thermobaric = { Flash = "Bloom", Impact = "Heat", Explode = "Heat", Bolt = { Marks = marks(KT.Glow, C(255, 220, 160), C(255, 100, 20), 1, 0.25, 0.3, { off = 0.1 }) } },
	P_Minefield = { Flash = "Burst", Impact = "Dust", Explode = "Dust", ImpactA = C(110, 120, 90), Bolt = { Blink = true } },
	P_Bunker = { Flash = "Burst", Impact = "Cracks", Explode = "Dust", ImpactA = C(200, 200, 200), ImpactB = C(160, 160, 166) },
	P_NuclearWinter = { Flash = "Hex", Impact = "Shards", Explode = "Shards", Decal = { Texture = KT.Ripple, Color = C(220, 245, 255), Size = 3, Grow = 1.2, Life = 1.5, Transp = 0.2 },
		Bolt = { Marks = marks(KT.Flake, WHITE, C(90, 255, 220), 1, 0.14, 0.6, { flip = true, accel = V(0, -3, 0), off = 0.2 }) } },
}

local RAINBOW = ColorSequence.new({ ColorSequenceKeypoint.new(0, C(255, 80, 120)), ColorSequenceKeypoint.new(0.33, C(255, 230, 90)), ColorSequenceKeypoint.new(0.66, C(90, 255, 220)), ColorSequenceKeypoint.new(1, C(170, 110, 255)) })
S.Knife = { -- no shots: swing trail (Swing) + the hit (Impact)
	P_NeonFade = { Impact = "Sparkle", Swing = { c1 = C(255, 60, 150), c2 = C(255, 200, 90) } },
	P_Blueprint = { Impact = "Wire", Swing = { c1 = C(235, 245, 255), c2 = C(120, 170, 255), Tex = KT.Dash, Mode = Enum.TextureMode.Wrap, TexLen = 0.4 } },
	P_Chrome = { Impact = "Splash", ImpactA = C(235, 240, 255), Swing = { c1 = WHITE, c2 = C(170, 190, 220), Transp = 0.15 } },
	P_Fiber = { Impact = "Swarm", Swing = { c1 = C(40, 255, 140), c2 = C(255, 80, 200), Tex = KT.Dash, Mode = Enum.TextureMode.Wrap, TexLen = 0.15 } },
	P_Holofoil = { Impact = "Sparkle", Swing = { Seq = RAINBOW, Transp = 0.2 } },
	P_Magnetar = { Impact = "Ripple", Swing = { c1 = C(255, 60, 200), c2 = C(120, 240, 255), Tex = KT.Plasma } },
	P_Cipher = { Impact = "Glyph", Swing = { c1 = C(220, 230, 240), c2 = C(40, 230, 200), Tex = KT.Glyph, Mode = Enum.TextureMode.Wrap, TexLen = 0.5 } },
	P_DieShot = { Impact = "Pixels", Swing = { c1 = C(255, 210, 110), c2 = C(160, 120, 255), Tex = KT.Pixel, Mode = Enum.TextureMode.Wrap, TexLen = 0.4 } },
	P_Foil = { Impact = "Flakes", Swing = { c1 = C(255, 240, 200), c2 = C(255, 200, 80), Tex = KT.Flake, Mode = Enum.TextureMode.Wrap, TexLen = 0.4 } },
	P_Tesseract = { Impact = "Wire", Swing = { c1 = C(40, 220, 255), c2 = C(255, 60, 210), Tex = KT.Wire, Mode = Enum.TextureMode.Wrap, TexLen = 0.5 } },
}

-- ─── Mythic + Legendary heroes (shot overhaul §5.5 / §5.6, stage 4) ─────────────
local GLASS, SLATE, SMOOTH = Enum.Material.Glass, Enum.Material.Slate, Enum.Material.SmoothPlastic
local function embers(c1, c2) return marks(KT.Glow, c1, c2, 1.2, 0.14, 0.5, { accel = V(0, -6, 0), spd = 1 }) end

S.Vanguard.MoltenSovereign = { -- Mythic · volcanic forge: a crusted molten slug rides the beam, the splash cools on the wall
	Flash = "Lava", Keep = { "Strands", "Fire" },
	Sig = { { Kind = "Head", Mesh = "MS_MoltenSlug", Size = 0.55, Colors = { Core = C(255, 170, 60), Crust = C(45, 22, 14) }, Materials = { Crust = SLATE }, Speed = 300, Spin = 7, Trail = embers(C(255, 220, 140), C(255, 80, 10)) } },
	Impact = "Molten", Heat = { Color = C(255, 230, 150), Max = 20 },
	Sustain = { From = 12, E = { Texture = KT.Glow, Color = CS(C(255, 220, 140), C(255, 90, 20)), Size = grow(0.14, 0.05), Life = NR(0.3, 0.5), Speed = NR(0.5, 1.5), Spread = 20, Count = 1, Dir = "Bottom", Accel = V(0, -25, 0) } },
	Hit = "Ring", HitColor = C(255, 150, 50) }
S.Vanguard.EventHorizon = { -- Legendary · singularity: implosion at the muzzle, a black core inside a spinning accretion disc
	Flash = "Implode", Keep = { "Strands", "Inner", "Rings" },
	MuzzleProps = {
		{ Shape = "Ball", Color = C(4, 0, 8), Material = SMOOTH, Size = 0.45, Size1 = 0.04, Life = 0.12, Transp0 = 0, Transp1 = 0.4 },
		{ Mesh = "EH_AccretionDisc", Part = "Disc", Color = C(200, 110, 255), Size = 0.15, Size1 = 0.6, Grow = 0.6, Life = 0.16, Spin = 22, Align = true, Transp0 = 0.1 },
	},
	Sig = { { Kind = "Head", Mesh = "EH_AccretionDisc", Size = 0.55, Color = C(200, 110, 255), Tilt = 55, Spin = 14, Speed = 260, Ball = { Size = 0.2, Color = C(0, 0, 0), Material = SMOOTH } } },
	Impact = "Implode", Hit = "Implode", HitColor = C(200, 110, 255) }

S.Sentinel.AbyssalLeviathan = { -- Mythic · bioluminescent abyss: sonar ring, the 3rd round of each burst is the glowing lure
	Flash = "Ripple", Keep = { "Strands" },
	Motes = motes(C(160, 255, 240), C(40, 200, 200), { tex = KT.Bubble, size = 0.12, density = 0.35, accel = V(0, 2.5, 0) }),
	Every = { N = 3, Width = 0.15, Sig = { { Kind = "Pulses", Color = C(170, 255, 240), Size = 0.32, Count = 1, Speed = 220 } } },
	Impact = "Implode", Hit = "Ripple" }
S.Sentinel.CelestialAstrolabe = { -- Legendary · orrery: astrolabe rings unfold at the muzzle; each burst draws a constellation
	Flash = "Cross", Keep = { "Strands", "Inner", "Rings" },
	MuzzleProps = {
		{ Mesh = "CA_AstrolabeRings", Part = "RingOuter", Color = C(255, 215, 130), Size = 0.15, Size1 = 0.55, Grow = 0.5, Life = 0.2, Spin = 14, Axis = Vector3.xAxis, Align = true, Transp0 = 0 },
		{ Mesh = "CA_AstrolabeRings", Part = "RingMid", Color = C(150, 190, 255), Size = 0.15, Size1 = 0.55, Grow = 0.5, Life = 0.2, Spin = -18, Axis = Vector3.zAxis, Align = true, Transp0 = 0 },
		{ Mesh = "CA_AstrolabeRings", Part = "RingInner", Color = C(255, 245, 210), Size = 0.15, Size1 = 0.55, Grow = 0.5, Life = 0.2, Spin = 22, Axis = Vector3.yAxis, Align = true, Transp0 = 0 },
	},
	Constellation = { Color = C(255, 225, 150), Width = 0.03, Life = 0.7, Window = 0.45 },
	Sig = { marks(KT.Glint, WHITE, C(255, 215, 130), 6, 0.3, 0.4, { rot = NR(0, 0) }) },
	Impact = "Glyph", ImpactA = C(255, 215, 130), Hit = "Sparkle", HitColor = C(255, 215, 130) }

S.Spectre.FrostFenrir = { -- Mythic · ice wolf: an ice fang flies the beam; an ice cluster grows from the wall and shatters
	Flash = "Puff", FlashA = C(230, 245, 255), Keep = { "Strands" },
	Sig = { { Kind = "Head", Mesh = "FF_IceFang", Size = 0.45, Color = C(200, 235, 255), Material = GLASS, Transp = 0.1, Speed = 260, Spin = 10, Trail = marks(KT.Flake, WHITE, C(150, 210, 255), 1.2, 0.1, 0.5, { flip = true, accel = V(0, -4, 0) }) } },
	Motes = motes(WHITE, C(150, 210, 255), { tex = KT.Flake, flip = "Grid2x2", size = 0.08, density = 0.35, accel = V(0, -3, 0) }),
	Impact = "Shards", ImpactA = C(200, 235, 255),
	ImpactProps = { { Mesh = "FF_IceCluster", Part = "Cluster", Color = C(190, 230, 255), Material = GLASS, Size = 0.05, Size1 = 0.8, Grow = 0.2, Life = 0.9, Hold = 0.55, Transp0 = 0.15, Align = true, World = true } },
	Hit = "Claw", HitColor = C(170, 220, 255) }
S.Spectre.AnubisEternal = { -- Legendary · underworld judgement: eye flash, sand falls from the beam, every 6th shot an ankh pulse
	Flash = "Eye", Keep = { "Strands", "Inner", "Rings" },
	Motes = motes(C(255, 230, 170), C(200, 160, 90), { tex = KT.Flake, flip = "Grid2x2", size = 0.07, density = 0.5, accel = V(0, -6, 0), emission = 0.4 }),
	Every = { N = 6, Sig = { { Kind = "Pulses", Color = C(255, 230, 150), Size = 0.34, Count = 1, Speed = 200 } } },
	Impact = "Dust", ImpactA = C(230, 200, 120), Decal = { Texture = KT.Glyph, Color = C(255, 210, 110), Size = 1.1, Grow = 1.1, Life = 1.0, Transp = 0.2 },
	Hit = "Eye", HitColor = C(255, 210, 110) }

S.Breacher.BrazenMinotaur = { -- Mythic · bronze bull: flame horns at the muzzle, a ground stamp where the blast lands
	Flash = "Horns", Keep = { "Strands" }, Impact = "Dust", ImpactA = C(160, 110, 80),
	Decal = { Texture = KT.Crack, Color = C(255, 90, 40), Size = 0.9, Grow = 1, Life = 1.0, Transp = 0.15 }, Hit = "Ring", HitColor = C(255, 110, 50) }
S.Breacher.GorgonsGaze = { -- Legendary · petrification: emerald eye flash, stone shards burst off the surface
	Flash = "Eye", Keep = { "Strands" },
	Motes = motes(C(190, 190, 180), C(120, 130, 120), { tex = KT.Dust, flip = "Grid2x2", size = 0.12, density = 0.2, accel = V(0, -5, 0), emission = 0 }),
	Impact = "Shards", ImpactA = C(170, 175, 165),
	ImpactProps = {
		{ Mesh = "GG_StoneShards", Part = "S2", Color = C(150, 152, 145), Material = SLATE, Size = 2.4, Life = 0.7, Hold = 0.6, Vel = V(0, 0, -7), Rand = 4, Grav = 40, Spin = 9, RandSpin = true, Axis = Vector3.new(1, 1, 0).Unit, Transp0 = 0, World = true },
		{ Mesh = "GG_StoneShards", Part = "S4", Color = C(130, 135, 128), Material = SLATE, Size = 2.4, Life = 0.7, Hold = 0.6, Vel = V(0, 0, -6), Rand = 4, Grav = 40, Spin = 7, RandSpin = true, Axis = Vector3.new(0, 1, 1).Unit, Transp0 = 0, World = true },
	},
	Hit = "Petrify", HitColor = C(80, 255, 160) }

S.Longshot.SabretoothPrimeval = { -- Mythic · primal ember: twin fang flames, a sabre fang rides the beam, three claw scorches
	Flash = "Fangs", Keep = { "Strands", "Fire" },
	Sig = { { Kind = "Head", Mesh = "SK_SabreFang", Size = 0.8, Color = C(250, 236, 215), Speed = 340, Trail = embers(C(255, 210, 130), C(255, 90, 20)) } },
	Impact = "Molten", Decal = { Texture = KT.Claw, Color = C(255, 120, 40), Size = 1.4, Grow = 1, Life = 1.2, Transp = 0.1 },
	Hit = "Claw", HitColor = C(255, 150, 60) }
S.Longshot.JaguarSunWarrior = { -- Legendary · sun warrior: sun-disc flash, an obsidian sun-dart with a gold collar rides the beam
	Flash = "Sun", Keep = { "Strands", "Inner", "Rings" },
	Sig = { { Kind = "Head", Mesh = "JG_SunDart", Size = 0.8, Colors = { Blade = C(30, 22, 40), Collar = C(255, 210, 90) }, Materials = { Blade = GLASS }, Speed = 360, Spin = 9, Trail = marks(KT.Glint, WHITE, C(255, 210, 90), 2.5, 0.25, 0.35) } },
	Impact = "Glyph", ImpactA = C(255, 210, 90), ImpactB = C(60, 230, 210), Hit = "Cross", HitColor = C(255, 210, 90) }

S.Riptide.HammerheadApex = { -- Mythic · predator: hammerhead T-bar flash, every 3rd round leaves a fin wake; frenzy deepens the red
	Flash = "TBar", Strands = "none",
	Every = { N = 3, Sig = { { Kind = "Streaks", Color = C(255, 160, 170), Count = 2, R0 = 0.15, R1 = 0.3, Min = 3, Max = 5 } } },
	Heat = { Color = C(150, 0, 20), Max = 10 }, Impact = "Splash", Hit = "Ring", HitColor = C(255, 60, 80) }
S.Riptide.TidecallerAtlantis = { -- Legendary · sunken empire: trident flash, a water ribbon, every 4th round a trident tip
	Flash = "Trident", Keep = { "Strands", "Rings" },
	Sig = { { Kind = "Ribbon", c1 = C(120, 255, 230), c2 = C(40, 150, 220), Width = 0.35, Curve = 1.2, Transp = 0.55, Dur = 0.3 } },
	Every = { N = 4, Sig = { { Kind = "Head", Mesh = "AT_TridentTip", Size = 0.4, Color = C(140, 255, 235), Speed = 320 }, { Kind = "Ribbon", c1 = C(120, 255, 230), c2 = C(40, 150, 220), Width = 0.35, Curve = 1.2, Transp = 0.55, Dur = 0.3 } } },
	Impact = "Splash", Decal = { Texture = KT.Ripple, Color = C(255, 215, 120), Size = 1.2, Grow = 1.2, Life = 0.9, Transp = 0.25 }, Hit = "Ripple" }

-- ─── stage 5 presets (Exclusive + Godly heroes, Bulwark / Verdict hero batch) ─────────
FLASH.Heart = function(a, b, k) return { board(KT.Heart, a, b, k, 0.6, false, NR(0, 0)), sparks(b, k, 3) } end
FLASH.Petals = function(a, b, k) return { core(a, k * 0.8), { Texture = KT.Petal, Flip = "Grid2x2", Color = CS(a, b), Size = grow(0.14 * k, 0.08 * k), Life = NR(0.3, 0.55), Speed = NR(4 * k, 8 * k), Spread = 40, Count = 5, Drag = 3, Accel = V(0, -6, 0), RotSpeed = NR(-200, 200) } } end
FLASH.Clock = function(a, b, k) return { board(KT.Clock, a, b, k, 0.75, false, NR(0, 0)), sparks(b, k, 4, 50) } end
FLASH.Feathers = function(a, b, k) return { core(a, k), { Texture = KT.Feather, Color = CS(WHITE:Lerp(a, 0.3), b), Size = grow(0.25 * k, 0.1 * k), Life = NR(0.25, 0.45), Speed = NR(4 * k, 8 * k), Spread = 50, Count = 4, Drag = 3, RotSpeed = NR(-120, 120) } } end
FLASH.Bats = function(a, b, k) return { core(a, k * 0.9), { Texture = KT.Bat, Flip = "Grid2x2", Color = CS(b), Size = grow(0.22 * k, 0.16 * k), Life = NR(0.3, 0.5), Speed = NR(5 * k, 9 * k), Spread = 50, Count = 3, Drag = 2, Accel = V(0, 6, 0), Rotation = NR(-20, 20) } } end
FLASH.Ink = function(a, b, k) return { board(KT.Ink, a, a, k, 0.6, false), core(b, k * 0.7) } end
FLASH.Skull = function(a, b, k) return { board(KT.Skull, a, b, k, 0.55, false, NR(0, 0)), core(b, k * 0.7) } end
FLASH.Roar = function(a, b, k) return { core(a, k * 1.1), { Texture = KT.Ripple, Color = CS(a), Size = grow(0.3 * k, 1.6 * k), Transparency = fade(0.1, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Count = 1, LockedToPart = true }, sparks(b, k, 6, 40) } end
FLASH.Quake = function(a, b, k) return { core(a, k * 1.1), { Texture = TEX.Shock, Color = CS(a), Size = grow(0.2 * k, 1.2 * k), Transparency = fade(0.3, 1), Life = NR(0.1, 0.1), Speed = NR(0, 0), Count = 1, LockedToPart = true }, { Texture = KT.Dust, Flip = "Grid2x2", Color = CS(C(120, 100, 80)), Size = grow(0.2 * k, 0.7 * k), Transparency = fade(0.4, 1), Life = NR(0.3, 0.5), Speed = NR(2, 4), Spread = 40, Count = 2, Drag = 3 } } end
FLASH.Hellfire = function(a, b, k) return { core(a, k), { Texture = TEX.Fire, Color = CS(b:Lerp(WHITE, 0.5), a), Size = grow(0.3 * k, 0.05), Life = NR(0.08, 0.12), Speed = NR(4, 7), Spread = 28, Count = 3 } } end
FLASH.Pincers = function(a, b, k) return { board(KT.Slit, a, b, k, 0.7, false, NR(35, 35)), board(KT.Slit, a, b, k, 0.7, false, NR(-35, -35)), core(b, k * 0.7) } end

HIT.Heart = function(c) return { { Texture = KT.Heart, Color = CS(WHITE:Lerp(c, 0.3), c), Size = grow(0.4, 0.75), Transparency = fade(0.3, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) } } end
HIT.Crown = function(c) return { { Texture = KT.Crown, Color = CS(WHITE:Lerp(c, 0.3), c), Size = grow(0.55, 0.9), Transparency = fade(0.1, 1), Life = NR(0.13, 0.13), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) } } end
HIT.Skull = function(c) return { { Texture = KT.Skull, Color = CS(WHITE:Lerp(c, 0.3), c), Size = grow(0.45, 0.7), Transparency = fade(0.35, 1), Life = NR(0.12, 0.12), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) } } end

IMPACT.Hearts = function(a, b) return { { Texture = KT.Heart, Color = CS(WHITE:Lerp(a, 0.2), a), Size = grow(0.25, 0.1), Life = NR(0.4, 0.7), Speed = NR(2, 5), Spread = 50, Count = 5, Accel = V(0, 4, 0), Drag = 2, Rotation = NR(-20, 20) }, ring(b, 1.2, 0.15) } end
IMPACT.Petals = function(a, b) return { { Texture = KT.Petal, Flip = "Grid2x2", Color = CS(a, b), Size = grow(0.16, 0.08), Life = NR(0.5, 0.9), Speed = NR(3, 7), Spread = 60, Count = 8, Drag = 2, Accel = V(0, -5, 0), RotSpeed = NR(-240, 240) }, ring(b, 1.0, 0.12) } end
IMPACT.Ink = function(a, b) return { { Texture = KT.Ink, Color = CS(b), Size = grow(0.4, 1.3), Transparency = fade(0.1, 1), Life = NR(0.18, 0.18), Speed = NR(0, 0), Count = 1 }, { Texture = KT.Drop, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(b), Size = grow(0.18, 0.05), Life = NR(0.25, 0.45), Speed = NR(7, 12), Spread = 50, Count = 6, Accel = V(0, -30, 0) } }, { Texture = KT.Ink, Color = a, Size = 1.3, Grow = 1.15, Life = 1.2, Transp = 0.15 } end
IMPACT.Firework = function(a, b) return { { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE, a), Size = grow(0.3, 0), Life = NR(0.25, 0.45), Speed = NR(14, 22), Spread = 180, Count = 12, Drag = 4, Accel = V(0, -8, 0) }, { Texture = KT.Glint, Color = CS(WHITE, b), Size = grow(0.25, 0.05), Life = NR(0.4, 0.7), Speed = NR(6, 12), Spread = 180, Count = 8, Drag = 3, Accel = V(0, -6, 0) }, ring(C(255, 230, 140), 1.4, 0.15) } end
IMPACT.Bats = function(a, b) return { { Texture = KT.Bat, Flip = "Grid2x2", Color = CS(a), Size = grow(0.3, 0.2), Life = NR(0.4, 0.7), Speed = NR(5, 9), Spread = 60, Count = 4, Drag = 2, Accel = V(0, 8, 0) }, { Texture = KT.Glow, Color = CS(WHITE:Lerp(b, 0.3), b), Size = grow(0.9, 0.2), Transparency = fade(0.1, 1), Life = NR(0.1, 0.12), Speed = NR(0, 0), Count = 1 } } end
IMPACT.Feathers = function(a, b) return { { Texture = KT.Feather, Color = CS(WHITE:Lerp(a, 0.3), b), Size = grow(0.3, 0.15), Life = NR(0.6, 1.0), Speed = NR(3, 6), Spread = 60, Count = 5, Drag = 4, Accel = V(0, -2, 0), RotSpeed = NR(-90, 90) }, { Texture = KT.Glow, Color = CS(WHITE:Lerp(a, 0.2), b), Size = grow(0.14, 0.04), Life = NR(0.4, 0.8), Speed = NR(2, 6), Spread = 50, Count = 6, Accel = V(0, 5, 0) } } end
IMPACT.Spirit = function(a, b) return { { Texture = KT.Skull, Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.5, 1.1), Transparency = fade(0.2, 1), Life = NR(0.25, 0.25), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, { Texture = TEX.Smoke, Color = CS(a:Lerp(WHITE, 0.2)), Size = grow(0.3, 1.0), Transparency = fade(0.5, 1), Life = NR(0.4, 0.7), Speed = NR(2, 4), Spread = 30, Count = 2, Accel = V(0, 4, 0) } } end
IMPACT.Quake = function(a, b) return { { Texture = TEX.Shock, Color = CS(a), Size = grow(0.2, 1.6), Transparency = fade(0.25, 1), Life = NR(0.22, 0.22), Speed = NR(0, 0), Spread = 0, Count = 1 }, { Texture = KT.Dust, Flip = "Grid2x2", Color = CS(b), Size = grow(0.3, 1.3), Transparency = fade(0.25, 1), Life = NR(0.4, 0.7), Speed = NR(2, 5), Spread = 40, Count = 3, Drag = 4 }, { Texture = KT.Flake, Flip = "Grid2x2", Color = CS(b, C(60, 50, 40)), Size = grow(0.12, 0.05), Life = NR(0.3, 0.6), Speed = NR(6, 11), Spread = 45, Count = 6, Accel = V(0, -30, 0) } }, { Texture = KT.Crack, Color = a, Size = 1.3, Grow = 1.1, Life = 1.2, Transp = 0.15 } end
IMPACT.Judgement = function(a, b) return { { Texture = KT.Spark, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE, a), Size = grow(1.5, 0.3), Life = NR(0.2, 0.3), Speed = NR(16, 20), Spread = 1, Count = 2 }, { Texture = KT.Glint, Color = CS(WHITE, a), Size = grow(1.4, 0.3), Transparency = fade(0, 1), Life = NR(0.25, 0.25), Speed = NR(0, 0), Count = 1, Rotation = NR(0, 0) }, ring(b, 1.8, 0.25) } end
IMPACT.Venom = function(a, b) return { { Texture = KT.Drop, Orient = "VelocityParallel", Rotation = NR(0, 0), Color = CS(WHITE:Lerp(a, 0.3), a), Size = grow(0.2, 0.05), Life = NR(0.3, 0.5), Speed = NR(7, 12), Spread = 45, Count = 7, Accel = V(0, -30, 0) }, { Texture = TEX.Smoke, Color = CS(a:Lerp(WHITE, 0.3)), Size = grow(0.3, 1.0), Transparency = fade(0.5, 1), Life = NR(0.4, 0.6), Speed = NR(1, 2), Spread = 30, Count = 2 }, ring(b, 1.0, 0.12) } end

local function petals(c1, c2, o) o = o or {}; return motes(c1, c2, { tex = KT.Petal, flip = "Grid2x2", size = o.size or 0.12, density = o.density or 0.35, accel = o.accel or V(0, -3, 0), emission = 0 }) end
local function embersUp(c1, c2, from) return { From = from or 10, E = { Texture = KT.Glow, Color = CS(c1, c2), Size = grow(0.12, 0.03), Life = NR(0.35, 0.6), Speed = NR(0.5, 1.5), Spread = 25, Count = 1, Dir = "Top", Accel = V(0, 8, 0) } } end

-- ─── Exclusive + Godly heroes (shot overhaul §5.7 / §5.8, stage 5) ─────────────────
-- Vanguard
S.Vanguard.Kitsune = { -- Exclusive · lunar festival: foxfire twin wisps; every 9th round (nine tails) the fox spirit runs the beam
	Flash = "Moon", FlashB = C(255, 60, 90), Strands = "twin", Twist = 3.2, StrandColor = C(150, 230, 255),
	Motes = motes(C(150, 230, 255), C(60, 160, 255), { tex = KT.Glow, size = 0.1, density = 0.3, accel = V(0, 3, 0) }),
	Every = { N = 9, Sig = { { Kind = "Head", Mesh = "KT_Fox", Size = 0.9, Color = C(240, 250, 255), Speed = 240, Trail = marks(KT.Glow, C(150, 230, 255), C(60, 160, 255), 0.8, 0.22, 0.45, { accel = V(0, 2, 0) }) } } },
	Impact = "Swarm", ImpactA = C(150, 230, 255), ImpactB = C(255, 60, 90),
	Decal = { Texture = KT.Ring, Color = C(255, 70, 100), Size = 0.8, Grow = 1.25, Life = 0.7, Transp = 0.35 },
	Hit = "Ring", HitColor = C(120, 220, 255) }
S.Vanguard.DragonEmperor = { -- Godly · golden dragon: gold scales shed off a red beam that gilds with the spray; every 8th the dragon chases its pearl
	Flash = "Crown", FlashA = C(255, 200, 90), FlashB = C(255, 70, 40), Keep = { "Fire" }, Strands = "twin", StrandColor = C(255, 205, 90), Twist = 3,
	MuzzleProps = { { Shape = "Ball", Color = C(255, 240, 200), Size = 0.16, Size1 = 0.28, Life = 0.12, Transp0 = 0.05 } },
	Sig = { marks(KT.Flake, C(255, 230, 150), C(255, 150, 40), 3, 0.16, 0.35, { flip = true, accel = V(0, -6, 0), spd = 1 }) },
	Every = { N = 8, Sig = {
		{ Kind = "Head", Mesh = "GD_Dragon", Only = {}, Ball = { Size = 0.3, Color = C(255, 245, 215) }, Speed = 230, Start = 4.5 },
		{ Kind = "Head", Mesh = "GD_Dragon", Size = 1.1, Color = C(255, 196, 80), Speed = 230, Trail = embers(C(255, 220, 140), C(255, 60, 20)) },
	} },
	Heat = { Color = C(255, 200, 90), Max = 24 },
	Impact = "Molten", ImpactA = C(255, 200, 90), ImpactB = C(255, 60, 30),
	Hit = "Crown", HitColor = C(255, 205, 90) }

-- Sentinel (3-round burst)
S.Sentinel.SakuraRonin = { -- Exclusive · spring festival: katana-slit flash, petals fall off the beam; each burst's 3rd round is a crescent blade
	Flash = "Slit", FlashA = C(255, 180, 210), Strands = "single", StrandColor = C(255, 235, 245),
	Motes = petals(C(255, 190, 215), C(255, 110, 160)),
	Every = { N = 3, Sig = { { Kind = "Head", Mesh = "SR_Crescent", Size = 0.9, Colors = { Blade = C(255, 235, 245), Blossom = C(255, 110, 160) }, Speed = 280 } } },
	Impact = "Petals", ImpactA = C(255, 190, 215), ImpactB = C(255, 110, 160),
	Decal = { Texture = KT.Slit, Color = C(255, 150, 190), Size = 1.2, Grow = 1, Life = 0.8, Transp = 0.2 },
	Hit = "Cross", HitColor = C(255, 150, 190) }
S.Sentinel.PhoenixAscendant = { -- Godly · rebirth: feather flash, a flame dart per round; the burst's 3rd round is the full phoenix
	Flash = "Feathers", FlashB = C(255, 90, 30), Keep = { "Fire" }, Strands = "twin", StrandColor = C(255, 120, 40),
	Sig = { { Kind = "Head", Mesh = "PX_FlameDart", Size = 0.6, Colors = { Core = C(255, 250, 220), Flames = C(255, 140, 40) }, Speed = 320 } },
	Every = { N = 3, Width = 0.13, Sig = { { Kind = "Head", Mesh = "PX_FlameDart", Size = 1.15, Colors = { Core = C(255, 250, 220), Flames = C(255, 120, 30) }, Speed = 300,
		Trail = marks(KT.Feather, C(255, 230, 150), C(255, 90, 30), 2.2, 0.3, 0.5, { accel = V(0, 2, 0), spin = NR(-90, 90) }) } } },
	Sustain = embersUp(C(255, 230, 150), C(255, 90, 20), 9),
	Impact = "Feathers", ImpactA = C(255, 200, 90), ImpactB = C(255, 90, 30),
	Decal = { Texture = KT.Ring, Color = C(255, 140, 40), Size = 1.1, Grow = 1.35, Life = 0.9, Transp = 0.3 },
	Hit = "Sparkle", HitColor = C(255, 200, 90) }

-- Spectre (SMG)
S.Spectre.Calavera = { -- Exclusive · Día de Muertos: marigold flash, petals drift off the beam, every 7th round a sugar-skull procession
	Flash = "Petals", FlashA = C(255, 160, 30), FlashB = C(255, 70, 160), Strands = "triple", StrandColor = C(255, 80, 170),
	Motes = petals(C(255, 170, 40), C(255, 110, 20), { density = 0.3, size = 0.1 }),
	Every = { N = 7, Sig = { marks(KT.Skull, C(255, 245, 230), C(255, 140, 30), 6, 0.35, 0.35, { rot = NR(0, 0), max = 3 }) } },
	Impact = "Petals", ImpactA = C(255, 170, 40), ImpactB = C(255, 70, 160),
	Decal = { Texture = KT.Skull, Color = C(255, 235, 215), Size = 0.8, Grow = 1.05, Life = 0.9, Transp = 0.3 },
	Hit = "Skull", HitColor = C(255, 170, 60) }
S.Spectre.WraithKing = { -- Godly · undead monarch: skull flash, ghost smoke rises off the beam, every 5th round the crowned skull flies
	Flash = "Skull", FlashA = C(200, 170, 255), FlashB = C(120, 255, 210), Strands = "twin", StrandColor = C(120, 255, 210),
	Motes = motes(C(210, 190, 255), C(120, 80, 255), { tex = KT.Smoke, size = 0.25, density = 0.25, accel = V(0, 2.5, 0) }),
	Every = { N = 5, Sig = { { Kind = "Head", Mesh = "WK_Skull", Size = 0.65, Colors = { Skull = C(225, 215, 255), Eyes = C(120, 255, 210), Crown = C(170, 120, 255) },
		Materials = { Skull = GLASS }, Transps = { Skull = 0.2 }, Speed = 220, Trail = marks(KT.Smoke, C(200, 170, 255), C(80, 40, 160), 1.0, 0.4, 0.5, { accel = V(0, 2, 0), t0 = 0.4 }) } } },
	Impact = "Spirit", ImpactA = C(190, 150, 255), ImpactB = C(120, 255, 210),
	Hit = "Implode", HitColor = C(170, 120, 255) }

-- Breacher (shotgun: Every counts pellets)
S.Breacher.KrampusYule = { -- Exclusive · yule night: red star flash, candy-cane spiral, snow off the pellets, claw scars
	Flash = "Star6", FlashA = C(255, 60, 70), FlashB = C(60, 220, 120), Strands = "single", StrandColor = C(255, 245, 245), Twist = 4,
	Motes = motes(WHITE, C(200, 230, 255), { tex = KT.Flake, flip = "Grid2x2", size = 0.08, density = 0.2, accel = V(0, -3, 0) }),
	Impact = "Flakes", ImpactA = WHITE, ImpactB = C(255, 50, 60),
	Decal = { Texture = KT.Claw, Color = C(255, 40, 55), Size = 0.8, Grow = 1, Life = 0.9, Transp = 0.2 },
	Hit = "Claw", HitColor = C(255, 60, 70) }
S.Breacher.CerberusWarden = { -- Godly · three-headed hound: triple hellfire jets, triple strands; every 3rd pellet a set of fangs
	Flash = "Hellfire", FlashA = C(80, 160, 255), FlashB = C(180, 230, 255), Strands = "single", Twist = 3, StrandColor = C(140, 220, 255), -- single: a shotgun draws strands per pellet
	Every = { N = 3, Sig = { { Kind = "Head", Mesh = "CB_Fangs", Size = 0.5, Colors = { Fangs = C(230, 245, 255), Collar = C(40, 110, 255) }, Speed = 300, Trail = embers(C(160, 220, 255), C(40, 90, 255)) } } },
	Impact = "Heat", ImpactA = C(120, 200, 255), ImpactB = C(40, 110, 255),
	Decal = { Texture = KT.Glow, Color = C(30, 60, 160), Size = 0.9, Grow = 1.1, Life = 1.0, Transp = 0.3 },
	Hit = "Ring", HitColor = C(90, 170, 255) }

-- Longshot (sniper)
S.Longshot.HeartbreakerValentine = { -- Exclusive · Valentine's: heart flash, a heart-tipped arrow flies the beam leaving little hearts
	Flash = "Heart", FlashB = C(255, 180, 210), Strands = "twin", StrandColor = C(255, 200, 225), Twist = 1.4,
	Sig = { { Kind = "Head", Mesh = "HB_Arrowhead", Size = 1.0, Colors = { Heart = C(255, 60, 140), Shaft = C(255, 235, 240), Fletch = C(255, 180, 210) }, Speed = 380,
		Trail = marks(KT.Heart, C(255, 170, 210), C(255, 60, 140), 3.5, 0.22, 0.5, { accel = V(0, 2.5, 0), rot = NR(-15, 15) }) } },
	Impact = "Hearts", ImpactA = C(255, 90, 160), ImpactB = C(255, 200, 225),
	Decal = { Texture = KT.Heart, Color = C(255, 70, 150), Size = 0.9, Grow = 1.15, Life = 1.0, Transp = 0.25 },
	Hit = "Heart", HitColor = C(255, 90, 160) }
S.Longshot.WatcherBeyond = { -- Godly · eldritch eye: an iris dilates at the muzzle, the eye flies the beam and opens on the wall
	Flash = "Ripple", FlashA = C(60, 255, 230), Strands = "triple", StrandColor = C(170, 255, 245),
	MuzzleProps = {
		{ Mesh = "WB_Iris", Part = "Lids", Color = C(170, 255, 245), Size = 0.2, Size1 = 0.75, Grow = 0.4, Life = 0.24, Align = true, Transp0 = 0 },
		{ Mesh = "WB_Iris", Part = "Iris", Color = C(40, 220, 210), Size = 0.2, Size1 = 0.75, Grow = 0.4, Life = 0.24, Spin = 6, Align = true, Transp0 = 0 },
		{ Mesh = "WB_Iris", Part = "Pupil", Color = C(0, 0, 0), Material = SMOOTH, Size = 0.75, Size1 = 0.2, Grow = 0.6, Life = 0.24, Align = true, Transp0 = 0, Transp1 = 0.2 },
	},
	Sig = { { Kind = "Head", Mesh = "WB_Iris", Size = 0.6, Colors = { Iris = C(40, 220, 210), Pupil = C(0, 0, 0), Lids = C(170, 255, 245) }, Materials = { Pupil = SMOOTH }, Speed = 300,
		Trail = marks(KT.Glyph, C(170, 255, 245), C(40, 220, 210), 4, 0.3, 0.45, { flip = true, rot = NR(0, 0) }) } },
	Impact = "Warp", ImpactA = C(60, 255, 230), ImpactB = C(170, 255, 245),
	Decal = { Texture = KT.Eye, Color = C(40, 220, 210), Size = 1.2, Grow = 1.1, Life = 1.2, Transp = 0.2 },
	Hit = "Eye", HitColor = C(60, 255, 230) }

-- Riptide (fast)
S.Riptide.SunsetSurf = { -- Exclusive · summer festival: sunset ribbon, sun glints, every 5th round a surf-spray wake
	Flash = "Splash", FlashA = C(255, 170, 90), FlashB = C(255, 90, 140), Strands = "none",
	Sig = { { Kind = "Ribbon", c1 = C(255, 200, 90), c2 = C(255, 80, 150), Width = 0.3, Curve = 0.9, Transp = 0.5, Dur = 0.28 } },
	Motes = motes(C(255, 230, 160), C(255, 120, 80), { tex = KT.Glint, size = 0.1, density = 0.25 }),
	Every = { N = 5, Sig = { { Kind = "Ribbon", c1 = C(255, 200, 90), c2 = C(255, 80, 150), Width = 0.3, Curve = 0.9, Transp = 0.5, Dur = 0.28 },
		{ Kind = "Streaks", Color = C(255, 235, 210), Count = 2, R0 = 0.15, R1 = 0.3, Min = 3, Max = 5 } } },
	Impact = "Splash", ImpactA = C(255, 200, 150), ImpactB = C(255, 120, 80),
	Decal = { Texture = KT.Star6, Color = C(255, 150, 80), Size = 0.9, Grow = 1.2, Life = 0.8, Transp = 0.35 },
	Hit = "Ripple", HitColor = C(255, 150, 90) }
S.Riptide.KrakenLord = { -- Godly · abyss lord: ink flash, two tentacle ribbons coil the beam; every 6th round a harpoon
	Flash = "Ink", FlashA = C(40, 220, 255), FlashB = C(20, 90, 140), Strands = "twin", StrandColor = C(20, 140, 180), Twist = 1.2,
	Sig = { { Kind = "Ribbon", c1 = C(40, 200, 230), c2 = C(10, 50, 80), Width = 0.22, Curve = 1.6, Transp = 0.45, Dur = 0.3 },
		{ Kind = "Ribbon", c1 = C(40, 200, 230), c2 = C(10, 50, 80), Width = 0.22, Curve = -1.6, Transp = 0.45, Dur = 0.3 } },
	Motes = motes(C(170, 240, 255), C(40, 160, 200), { tex = KT.Bubble, size = 0.1, density = 0.3, accel = V(0, 2.5, 0) }),
	Every = { N = 6, Sig = {
		{ Kind = "Ribbon", c1 = C(40, 200, 230), c2 = C(10, 50, 80), Width = 0.22, Curve = 1.6, Transp = 0.45, Dur = 0.3 },
		{ Kind = "Ribbon", c1 = C(40, 200, 230), c2 = C(10, 50, 80), Width = 0.22, Curve = -1.6, Transp = 0.45, Dur = 0.3 },
		{ Kind = "Head", Mesh = "KR_Harpoon", Size = 0.9, Colors = { Tip = C(200, 245, 255), Barbs = C(40, 220, 255), Shaft = C(30, 40, 50) }, Materials = { Shaft = SMOOTH }, Speed = 300 },
	} },
	Impact = "Ink", ImpactA = C(15, 20, 35), ImpactB = C(40, 220, 255),
	Hit = "Implode", HitColor = C(40, 220, 255) }

-- ─── new hero batch: Bulwark (LMG) + Verdict (heavy revolver) ─────────────────────
S.Bulwark.RiotWarden = { -- Epic · riot line: bracket flash, chevrons stamp down the beam, hex shield stamp
	Flash = "Bracket", Strands = "twin", StrandColor = WHITE,
	Sig = { marks(KT.Chevron, WHITE, C(120, 170, 255), 8, 0.2, 0.25, { rot = NR(0, 0) }) },
	Impact = "HexStamp", ImpactB = WHITE }
S.Bulwark.RhinoJuggernaut = { -- Mythic · charge: steam-snort flash, every 4th round a horn; the longer the spray the hotter the beam
	Flash = "Vent", FlashA = C(240, 250, 120), Strands = "twin", StrandColor = C(255, 255, 200),
	Every = { N = 4, Sig = { { Kind = "Head", Mesh = "RJ_Horn", Size = 0.6, Colors = { Horn = C(235, 240, 150), Plate = C(70, 76, 50) }, Materials = { Plate = SMOOTH }, Speed = 280,
		Trail = marks(KT.Dust, C(200, 200, 160), C(120, 120, 90), 1.5, 0.3, 0.4, { flip = true, t0 = 0.4 }) } } },
	Heat = { Color = C(255, 120, 20), Max = 30 },
	Impact = "Quake", ImpactA = C(230, 240, 60), ImpactB = C(180, 170, 130),
	Hit = "Ring", HitColor = C(230, 240, 60) }
S.Bulwark.OniWarlord = { -- Legendary · demon general: the oni mask flares at the muzzle, violet fire strands, embers on sustained fire
	Flash = "Burst", Keep = { "Fire" }, Strands = "twin", StrandColor = C(255, 60, 90),
	MuzzleProps = {
		{ Mesh = "ON_Mask", Part = "Mask", Rig = true, Color = C(200, 40, 70), Size = 0.3, Size1 = 0.5, Grow = 0.35, Life = 0.13, Align = true, Offset = CFrame.new(0, 0.25, 0), Transp0 = 0.05 },
		{ Mesh = "ON_Mask", Part = "Horns", Rig = true, Color = C(255, 205, 110), Size = 0.3, Size1 = 0.5, Grow = 0.35, Life = 0.13, Align = true, Offset = CFrame.new(0, 0.25, 0), Transp0 = 0.05 },
		{ Mesh = "ON_Mask", Part = "Tusks", Rig = true, Color = C(255, 250, 240), Size = 0.3, Size1 = 0.5, Grow = 0.35, Life = 0.13, Align = true, Offset = CFrame.new(0, 0.25, 0), Transp0 = 0.05 },
	},
	Sustain = embersUp(C(220, 160, 255), C(150, 60, 255), 10),
	Impact = "Plasma", ImpactA = C(190, 110, 255), ImpactB = C(255, 60, 90),
	Decal = { Texture = KT.Claw, Color = C(170, 80, 255), Size = 1.0, Grow = 1, Life = 0.9, Transp = 0.2 },
	Hit = "Claw", HitColor = C(200, 110, 255) }
S.Bulwark.JackOLantern = { -- Exclusive · Halloween night: bats burst from the muzzle, every 5th round a grinning jack-o'-lantern
	Flash = "Bats", FlashA = C(255, 150, 40), FlashB = C(150, 90, 255), Strands = "single", StrandColor = C(160, 90, 255),
	Motes = motes(C(255, 200, 80), C(255, 100, 20), { tex = KT.Glow, size = 0.1, density = 0.25, accel = V(0, 2, 0) }),
	Every = { N = 5, Sig = { { Kind = "Head", Mesh = "JL_Pumpkin", Size = 0.6, Colors = { Shell = C(210, 80, 10), Stem = C(60, 110, 30), Face = C(255, 240, 120) }, Materials = { Stem = SMOOTH }, Speed = 220, Spin = 6,
		Trail = marks(KT.Bat, C(150, 90, 255), C(60, 20, 120), 4, 0.35, 0.6, { flip = true, accel = V(0, 3, 0), spd = 2, rot = NR(-20, 20) }) } } },
	Impact = "Bats", ImpactA = C(150, 90, 255), ImpactB = C(255, 130, 30),
	Hit = "Sparkle", HitColor = C(255, 140, 40) }
S.Bulwark.BehemothWorldBreaker = { -- Godly · world breaker: quake flash, the beam heats gold→magma; every 6th round a meteor; rock spikes burst from the wall
	Flash = "Quake", FlashA = C(255, 200, 80), FlashB = C(255, 90, 20), Strands = "twin", StrandColor = C(255, 110, 30), Twist = 1.6,
	Heat = { Color = C(255, 80, 20), Max = 30 },
	Sustain = embersUp(C(255, 200, 110), C(255, 70, 10), 15),
	Every = { N = 6, Width = 0.16, Sig = { { Kind = "Head", Mesh = "BH_Meteor", Size = 0.7, Colors = { Rock = C(40, 32, 28), Core = C(255, 150, 40) }, Materials = { Rock = SLATE }, Speed = 220, Spin = 5,
		Trail = embers(C(255, 200, 100), C(255, 70, 10)) } } },
	Impact = "Quake", ImpactA = C(255, 190, 70), ImpactB = C(120, 100, 80),
	ImpactProps = { { Mesh = "BH_Spikes", Part = "Spikes", Color = C(60, 50, 44), Material = SLATE, Size = 0.05, Size1 = 0.8, Grow = 0.12, Life = 0.7, Hold = 0.5, Align = true, World = true, Transp0 = 0 } },
	Hit = "Cross", HitColor = C(255, 200, 80) }

S.Verdict.StarMarshal = { -- Epic · frontier lawman: six-point star flash, stars stamped along the beam
	Flash = "Star6", Strands = "twin", StrandColor = WHITE,
	Sig = { marks(KT.Star6, WHITE, C(90, 200, 255), 7, 0.22, 0.3, { flip = true }) },
	Impact = "Sparkle" }
S.Verdict.DeathstalkerScorpion = { -- Mythic · desert predator: pincer flash, a stinger flies each round dripping venom; venom splash on the wall
	Flash = "Pincers", FlashA = C(255, 170, 40), FlashB = C(140, 255, 60), Strands = "twin", StrandColor = C(120, 255, 60),
	Sig = { { Kind = "Head", Mesh = "DS_Stinger", Size = 0.7, Colors = { Segments = C(70, 45, 25), Barb = C(140, 255, 60) }, Materials = { Segments = SMOOTH }, Speed = 300,
		Trail = marks(KT.Drop, C(160, 255, 80), C(60, 160, 20), 2.2, 0.16, 0.4, { accel = V(0, -14, 0) }) } },
	Motes = motes(C(230, 200, 150), C(180, 140, 90), { tex = KT.Dust, flip = "Grid2x2", size = 0.12, density = 0.2, accel = V(0, -2, 0), emission = 0 }),
	Impact = "Venom", ImpactA = C(140, 255, 60), ImpactB = C(255, 160, 30),
	Decal = { Texture = KT.Ink, Color = C(100, 220, 40), Size = 0.9, Grow = 1.1, Life = 1.1, Transp = 0.25 },
	Hit = "Claw", HitColor = C(255, 160, 30) }
S.Verdict.ScalesOfJudgement = { -- Legendary · justice: the scales rise and tip at the muzzle; the 6th chamber is the verdict; a pillar of light marks the hit
	Flash = "Cross", FlashA = C(255, 215, 120), FlashB = C(90, 130, 255), Strands = "triple", StrandColor = C(110, 150, 255),
	MuzzleProps = {
		{ Mesh = "SJ_Scales", Part = "Frame", Rig = true, Color = C(255, 215, 120), Size = 0.2, Size1 = 0.55, Grow = 0.4, Life = 0.26, Align = true, Offset = CFrame.new(0, 0.3, 0.35), Transp0 = 0 },
		{ Mesh = "SJ_Scales", Part = "Pans", Rig = true, Color = C(120, 160, 255), Size = 0.2, Size1 = 0.55, Grow = 0.4, Life = 0.26, Spin = 1.6, Axis = Vector3.yAxis, Align = true, Offset = CFrame.new(0, 0.3, 0.35), Transp0 = 0 },
	},
	Every = { N = 6, Width = 0.17, Sig = { { Kind = "Pulses", Color = C(255, 235, 170), Size = 0.36, Count = 1, Speed = 200 } } },
	Impact = "Judgement", ImpactA = C(255, 220, 130), ImpactB = C(110, 150, 255),
	Decal = { Texture = KT.Glint, Color = C(255, 220, 130), Size = 1.2, Grow = 1, Life = 0.8, Transp = 0.3 },
	Hit = "Cross", HitColor = C(255, 220, 130) }
S.Verdict.MidnightCountdown = { -- Exclusive · New Year's Eve: clock strikes midnight at the muzzle, a firework rocket flies, bursts on the wall
	Flash = "Clock", FlashA = C(255, 230, 250), FlashB = C(255, 80, 200), Strands = "twin", StrandColor = C(90, 200, 255),
	Motes = motes(C(255, 120, 220), C(90, 200, 255), { tex = KT.Pixel, flip = "Grid2x2", size = 0.08, density = 0.3, accel = V(0, -4, 0) }),
	Sig = { { Kind = "Head", Mesh = "MC_Rocket", Size = 0.6, Colors = { Body = C(255, 80, 200), Nose = C(255, 230, 120), Fins = C(90, 200, 255) }, Speed = 260, Spin = 12,
		Trail = marks(KT.Glint, WHITE, C(255, 220, 120), 1.2, 0.18, 0.3, { spd = 3, accel = V(0, -10, 0) }) } },
	Impact = "Firework", ImpactA = C(255, 80, 200), ImpactB = C(90, 200, 255),
	Hit = "Sparkle", HitColor = C(255, 120, 220) }
S.Verdict.SovereignLion = { -- Godly · the king's verdict: a roar ring at the muzzle, a lion head per round; the 6th chamber is the king's roar
	Flash = "Roar", FlashA = C(255, 210, 110), FlashB = C(255, 90, 40), Strands = "twin", StrandColor = C(255, 120, 40),
	Sig = { { Kind = "Head", Mesh = "SL_LionHead", Size = 0.7, Colors = { Mane = C(255, 140, 40), Face = C(255, 215, 120) }, Speed = 280, Trail = embers(C(255, 220, 140), C(255, 90, 20)) } },
	Every = { N = 6, Width = 0.18, Sig = {
		{ Kind = "Head", Mesh = "SL_LionHead", Size = 1.2, Colors = { Mane = C(255, 120, 30), Face = C(255, 225, 140) }, Speed = 260, Trail = embers(C(255, 220, 140), C(255, 90, 20)) },
		{ Kind = "Pulses", Color = C(255, 225, 140), Size = 0.4, Count = 1, Speed = 200 },
	} },
	Impact = "Shock", ImpactA = C(255, 210, 110), ImpactB = C(255, 120, 40),
	Decal = { Texture = KT.Crown, Color = C(255, 205, 100), Size = 1.0, Grow = 1.1, Life = 1.0, Transp = 0.2 },
	Hit = "Crown", HitColor = C(255, 210, 110) }


-- ─── stage 6: pump / bolt rack bursts (first person; small, at the ejection port) ─────────
local function rk(tex, c1, c2, o)
	o = o or {}
	return { Texture = tex, Flip = o.flip, Color = CS(c1, c2), Size = grow(o.s0 or 0.08, o.s1 or 0.2), Transparency = fade(o.t0 or 0.3, 1),
		Life = NR(o.l0 or 0.3, o.l1 or 0.55), Speed = NR(o.v0 or 1.5, o.v1 or 3), Spread = o.spread or 25, Count = o.n or 3, Drag = o.drag or 3,
		Accel = o.accel or V(0, 3, 0), RotSpeed = o.spin, Orient = o.orient, Rotation = o.rot }
end
local function rsparks(c, n, grav) return rk(KT.Spark, WHITE:Lerp(c, 0.3), c, { s0 = 0.08, s1 = 0, l0 = 0.12, l1 = 0.25, v0 = 4, v1 = 7, spread = 35, n = n, drag = 2, accel = V(0, -(grav or 20), 0), orient = "VelocityParallel", rot = NR(0, 0), t0 = 0 }) end
S.Breacher.IroncladSteamworks.Rack = { rk(TEX.Smoke, C(245, 245, 250), C(220, 225, 230), { s0 = 0.15, s1 = 0.5, l0 = 0.4, l1 = 0.7, n = 3 }), rsparks(C(255, 200, 90), 3) }
S.Breacher.BrazenMinotaur.Rack = { rsparks(C(255, 120, 40), 6, 30), rk(KT.Glow, C(255, 200, 120), C(255, 80, 20), { s0 = 0.06, s1 = 0.02, n = 2 }) }
S.Breacher.GorgonsGaze.Rack = { rk(KT.Dust, C(170, 172, 165), C(130, 132, 125), { flip = "Grid2x2", s0 = 0.1, s1 = 0.3, n = 2, accel = V(0, -2, 0) }), rk(KT.Glint, WHITE, C(60, 255, 150), { s0 = 0.15, s1 = 0.02, l0 = 0.15, l1 = 0.2, v0 = 0, v1 = 0, n = 1, t0 = 0 }) }
S.Breacher.KrampusYule.Rack = { rk(KT.Flake, WHITE, C(210, 230, 255), { flip = "Grid2x2", s0 = 0.06, s1 = 0.03, n = 5, accel = V(0, -4, 0), spin = NR(-200, 200) }), rk(KT.Glint, WHITE, C(255, 60, 70), { s0 = 0.14, s1 = 0.02, l0 = 0.15, l1 = 0.2, v0 = 0, v1 = 0, n = 1, t0 = 0 }) }
S.Breacher.CerberusWarden.Rack = { rk(TEX.Fire, C(180, 230, 255), C(40, 110, 255), { s0 = 0.14, s1 = 0.03, l0 = 0.15, l1 = 0.25, n = 2, accel = V(0, 6, 0) }), rk(KT.Glow, C(170, 225, 255), C(40, 90, 255), { s0 = 0.05, s1 = 0.01, n = 3 }) }
S.Breacher.P_Reactor.Rack = { rk(KT.Glow, C(255, 200, 120), C(255, 110, 30), { s0 = 0.12, s1 = 0.02, l0 = 0.15, l1 = 0.25, n = 2, v0 = 0.5, v1 = 1 }) }
S.Breacher.P_Cells.Rack = { rk(KT.Pixel, C(160, 255, 120), C(40, 220, 90), { flip = "Grid2x2", s0 = 0.08, s1 = 0.02, n = 3, rot = NR(0, 0) }), rk(KT.Glow, C(170, 255, 150), C(40, 220, 90), { s0 = 0.12, s1 = 0.02, l0 = 0.12, l1 = 0.18, v0 = 0, v1 = 0, n = 1 }) }
S.Breacher.P_Thermite.Rack = { rsparks(C(255, 240, 200), 7, 35) }
S.Longshot.SabretoothPrimeval.Rack = { rk(KT.Glow, C(255, 210, 130), C(255, 90, 20), { s0 = 0.05, s1 = 0.01, n = 4, accel = V(0, 4, 0) }) }
S.Longshot.JaguarSunWarrior.Rack = { rk(KT.Glint, WHITE, C(255, 210, 90), { s0 = 0.12, s1 = 0.02, n = 2, v0 = 0.5, v1 = 1 }) }
S.Longshot.HeartbreakerValentine.Rack = { rk(KT.Heart, C(255, 170, 210), C(255, 60, 140), { s0 = 0.08, s1 = 0.04, n = 3, accel = V(0, 3, 0) }) }
S.Longshot.WatcherBeyond.Rack = { rk(KT.Glyph, C(170, 255, 245), C(40, 220, 210), { flip = "Grid2x2", s0 = 0.1, s1 = 0.02, n = 2, rot = NR(0, 0) }) }
S.Longshot.StrixNightwatch.Rack = { rk(KT.Feather, C(220, 235, 255), C(110, 160, 255), { s0 = 0.1, s1 = 0.06, n = 2, accel = V(0, -1, 0), spin = NR(-90, 90) }) }

-- ─── BX-3 Helix heroes (2026-11-20): continuous beam, extras re-drawn along it every 0.12 s ───
S.Helix.ContainmentBreach = { -- Epic · lab containment: plasma specimens pulse down a hazard-striped beam
	Flash = "Ring", Impact = "Plasma", Strands = "twin", StrandColor = C(255, 200, 60),
	BeamL = { Sig = { { Kind = "Pulses", Color = C(255, 90, 230), Size = 0.2, Count = 2, Gap = 0.03, Speed = 320 } } } }
S.Helix.IronhornRam = { -- Mythic · storm ram: cyan lightning crackles round the beam
	Flash = "Arc", Impact = "Arcs", Strands = "twin", StrandColor = C(220, 250, 255),
	BeamL = { Sig = { { Kind = "Zigzag", Color = C(120, 240, 255), Amp = 0.15, Kink = 1.6, Width = 0.04, Dur = 0.12 }, { Kind = "Arcs", Color = C(225, 250, 255), Count = 2, Len = 0.7 } } } }
S.Helix.GenesisHelix = { -- Legendary · origin code: a gold-and-white double helix winds down the beam
	Flash = "Cross", Impact = "Sparkle", Strands = "twin", StrandColor = C(255, 250, 230),
	BeamL = { Strands = { { Color = C(255, 215, 120), Radius = 0.1, Twist = 3, Width = 0.028, Phase = 0 }, { Color = C(255, 252, 240), Radius = 0.1, Twist = 3, Width = 0.028, Phase = math.pi } } } }
S.Helix.MasqueradeCarnival = { -- Exclusive · carnival night: the beam splits into purple, gold and green ribbons
	Flash = "Bloom", Impact = "Flakes", Strands = "triple", StrandColor = C(255, 215, 120),
	BeamL = { Sig = { { Kind = "Prism", Colors = { C(170, 70, 255), C(255, 215, 120), C(90, 255, 160) }, Radius = 0.2, Dur = 0.14 } } } }
S.Helix.StormTitan = { -- Godly · lord of lightning: white-gold bolts and arcs, dark crimson core
	Flash = "Arc", Impact = "Arcs", Strands = "triple", StrandColor = C(255, 250, 230), Width = 0.1, Inner = C(150, 10, 20),
	BeamL = { Inner = C(150, 10, 20), Sig = { { Kind = "Zigzag", Color = C(255, 230, 140), Amp = 0.18, Kink = 1.4, Width = 0.05, Dur = 0.12 }, { Kind = "Arcs", Color = C(255, 252, 240), Count = 3, Len = 0.9 } } } }

local EpicFX = { Specs = S, Flash = FLASH, Impact = IMPACT, Build = build, Marks = marks, Motes = motes, K = K }

local HERO_FX = { Archangel = "Archangel", StormHerald = "Storm", PlagueDoctor = "Plague", IroncladSteamworks = "Ironclad", StrixNightwatch = "Strix", AbyssDiver = "Diver",
	MoltenSovereign = "Molten", AbyssalLeviathan = "Leviathan", FrostFenrir = "Fenrir", BrazenMinotaur = "Minotaur", SabretoothPrimeval = "Sabretooth", HammerheadApex = "Hammerhead",
	EventHorizon = "Horizon", CelestialAstrolabe = "Celestial", AnubisEternal = "Anubis", GorgonsGaze = "Gorgon", JaguarSunWarrior = "Jaguar", TidecallerAtlantis = "Atlantis",
	Kitsune = "Kitsune", DragonEmperor = "Dragon", SakuraRonin = "Sakura", PhoenixAscendant = "Phoenix", Calavera = "Calavera", WraithKing = "Wraith",
	KrampusYule = "Krampus", CerberusWarden = "Cerberus", HeartbreakerValentine = "Heartbreaker", WatcherBeyond = "Watcher", SunsetSurf = "Sunset", KrakenLord = "Kraken",
	RiotWarden = "Warden", RhinoJuggernaut = "Rhino", OniWarlord = "Oni", JackOLantern = "Lantern", BehemothWorldBreaker = "Behemoth",
	StarMarshal = "Marshal", DeathstalkerScorpion = "Scorpion", ScalesOfJudgement = "Justice", MidnightCountdown = "Countdown", SovereignLion = "Lion",
	ContainmentBreach = "Containment", IronhornRam = "Ram", GenesisHelix = "Genesis", MasqueradeCarnival = "Masquerade", StormTitan = "Titan" }

function EpicFX.Register(SkinFX)
	local D = SkinFX.Defs
	local n = 0
	for wid, set in S do
		for id, s in set do
			local fx = HERO_FX[id] or id
			local old = D[fx]
			if old and old.Tracer and old.Tracer.Laser then
				local L = old.Tracer.Laser
				local a = s.Color or L.Color
				local b = s.B or (L.Strands and L.Strands[1] and L.Strands[1].Color) or (L.Core) or a
				local d = build(wid, a, b, s, old)
				d.Idle = old.Idle
				if HERO_FX[id] then
					d.Light, d.LightBright = old.Light or d.Light, old.LightBright or d.LightBright
				end
				D[fx] = d
				n += 1
			end
		end
	end
	EpicFX.Registered = n
end

return EpicFX
