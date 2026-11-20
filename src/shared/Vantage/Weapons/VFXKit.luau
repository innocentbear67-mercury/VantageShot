-- VantageShot VFX kit v1 (2026-11-15), v2 (shot overhaul stage 2, 2026-11-18)
-- Custom textures (procedural, original; uploaded via Open Cloud) + per-weapon muzzle / tracer chassis
-- profiles + finish identities (Standard / Elite / Prime skins restyle the chassis).
-- Textures are white with alpha so ParticleEmitter.Color / Beam.Color tint them.
local C = Color3.fromRGB
local V = Vector3.new
local function id(n) return "rbxassetid://" .. n end

local VFXKit = {}

VFXKit.Tex = {
	FlashFront = id(134570861453913), -- 2x2 flipbook, star bursts (front view)
	FlashSide = id(106950964275389), -- 2x2 flipbook, flame cone (side view)
	Spark = id(109869220296346), -- streak, for VelocityParallel
	Glow = id(118178516679033), -- soft dot
	Smoke = id(134822937490141), -- 4x4 flipbook, puff billows then breaks up
	Dust = id(102518481957603), -- 2x2 flipbook, gritty impact dust
	Ring = id(132840247841992), -- shock ring
	Plasma = id(85687099441772), -- 2x2 flipbook, electric filaments
	Tracer = id(117874388206525), -- beam strip, bright head at u=1
	-- kit v2 (2026-11-18)
	Star6 = id(113877306257716), -- 2x2 flipbook, sharp 6-point stars (Whiteout)
	Slit = id(98331584055835), -- 2x2 flipbook, horizontal brake slit + side jets (Carbon)
	Crown = id(107506967320229), -- 2x2 flipbook, 4-petal crown + lens streak (Gilded)
	Hex = id(114071327406591), -- 2x2 flipbook, hexagonal ice-crystal burst (Glacier Ops)
	Flake = id(94383645624590), -- 2x2 flipbook, irregular flakes (debris, gold leaf, snow)
	Shard = id(97441524200069), -- 2x2 flipbook, long shards drawn horizontally (VelocityParallel)
	Glint = id(82648003523594), -- lens-star glint
	Ripple = id(137386464279731), -- three concentric rings
	Drop = id(116874261403517), -- droplet, head at +u (VelocityParallel)
	Dash = id(79552289852265), -- beam strip with one dash per tile (TextureMode Wrap)
	-- kit v3 (2026-11-18, stage 3)
	Pixel = id(74625154191618), -- 2x2, square-block clusters
	Glitch = id(97266659563296), -- 2x2, displaced horizontal bars
	Static = id(83276570668819), -- 2x2, TV-static noise squares
	Glyph = id(119717101580188), -- 2x2, abstract HUD sigils (no letters)
	Wire = id(82903961012702), -- 2x2, wireframe cubes
	Bracket = id(96358558004676), -- reticle corner brackets
	Chevron = id(91923059030727), -- solid chevron arrow (points +u)
	HexCell = id(101952352497796), -- single glowing hex outline
	Crack = id(109338279378569), -- radial cracks (decal)
	Bubble = id(125456264888756), -- bubble ring with highlight
	-- kit v4 (stage 4)
	Claw = id(89601809900712), -- three parallel slashes
	Eye = id(119211185084991), -- stylised eye outline + slit iris
	-- v5 (stage 5 heroes)
	Heart = id(113369544610518), -- solid heart, bright rim
	Petal = id(118165303851749), -- sakura petal, 2x2 tumble flipbook
	Bat = id(97657199540516), -- bat silhouette, 2x2 wing-flap flipbook
	Clock = id(76769359664950), -- clock face at midnight
	Ink = id(112388074615406), -- ink splat with droplet streaks
	Feather = id(81774302926894), -- feather vane
	Skull = id(140274695499676), -- sugar-skull silhouette
}

-- Rotation offset so the streak textures (drawn horizontally) align with velocity.
VFXKit.StreakRotation = 0

local DEFAULT = {
	Hot = C(255, 228, 175), Warm = C(255, 128, 40),
	Size = 0.55, FlashCount = 1, Petal = 0.7, PetalCount = 2,
	Sparks = { 3, 5 }, SparkSpread = 14, SparkColor = C(255, 205, 130),
	SmokeChance = 0.45, SmokeCount = 1, SmokeScale = 1,
	Light = C(255, 190, 120), LightB = 3.2, LightRange = 11,
	Ring = false, Energy = false,
	TracerColor = C(255, 214, 150), TracerWidth = 0.09, TracerLen = 9,
}
VFXKit.Default = DEFAULT

-- ─── weapon chassis (shot overhaul §4): every skin restyles these, never replaces them ───
local ENERGY = { Energy = true, Hot = C(225, 255, 255), Warm = C(40, 190, 255), SparkColor = C(120, 235, 255), SmokeChance = 0, Light = C(80, 225, 255), TracerColor = C(110, 230, 255) }
local function with(base, t)
	local o = table.clone(base)
	for k, v in t do o[k] = v end
	return o
end
local P = {
	Vanguard = {}, -- AR: balanced warm 4-prong (the baseline)
	Sentinel = { Size = 0.5, Petal = 0.75, PetalCount = 2, Sparks = { 2, 3 }, SmokeChance = 0.75, SmokeScale = 1.15, LightB = 3.8, TracerWidth = 0.1, TracerLen = 11 }, -- burst: tight
	Spectre = { Size = 0.3, Petal = 0.36, PetalCount = 1, Sparks = { 1, 2 }, SmokeChance = 0.25, SmokeScale = 0.7, LightB = 2.4, LightRange = 9, TracerWidth = 0.07, TracerLen = 7 }, -- sidearm: compact
	Breacher = { Size = 0.66, FlashCount = 2, Petal = 0.7, PetalCount = 4, Sparks = { 7, 11 }, SparkSpread = 26, SmokeChance = 1, SmokeCount = 2, SmokeScale = 1.4, LightB = 4.6, LightRange = 15, Warm = C(255, 130, 45), TracerWidth = 0.06, TracerLen = 6 }, -- shotgun: wide cone
	Longshot = { Size = 0.8, Petal = 1.05, PetalCount = 3, Sparks = { 3, 5 }, SmokeChance = 1, SmokeCount = 3, SmokeScale = 1.6, LightB = 5.2, LightRange = 17, Ring = true, TracerColor = C(255, 232, 196), TracerWidth = 0.14, TracerLen = 16 }, -- sniper: blast ring
	Arc = with(ENERGY, { Size = 0.55, PetalCount = 0, Sparks = { 3, 5 }, SparkSpread = 22, LightB = 3.6, LightRange = 12, Ring = true }), -- energy bolts
	Riptide = { Size = 0.38, Petal = 0.45, PetalCount = 2, Sparks = { 1, 3 }, SparkSpread = 16, SmokeChance = 0.2, SmokeScale = 0.7, LightB = 2.6, LightRange = 9, TracerWidth = 0.06, TracerLen = 6 }, -- SMG 1000 rpm: lightest
	Bulwark = { Size = 0.62, Petal = 0.8, PetalCount = 3, Sparks = { 3, 6 }, SmokeChance = 0.6, SmokeScale = 1.2, LightB = 3.8, LightRange = 13, TracerWidth = 0.11, TracerLen = 10, HeatGlow = 10 }, -- LMG: barrel glows after 10 rounds
	Verdict = { Size = 0.75, FlashCount = 2, Petal = 0.95, PetalCount = 4, Sparks = { 5, 8 }, SparkSpread = 20, SmokeChance = 1, SmokeCount = 2, SmokeScale = 1.3, LightB = 5, LightRange = 15, Ring = true, RingK = 0.8, TracerWidth = 0.13, TracerLen = 8 }, -- hand cannon: punchy shockwave
	Quill = { Size = 0.22, FlashCount = 0, Petal = 0.3, PetalCount = 0, Sparks = { 0, 1 }, SparkSpread = 30, SmokeChance = 0, Hot = C(240, 248, 255), Warm = C(150, 205, 255), SparkColor = C(200, 230, 255), Light = C(170, 215, 255), LightB = 1.2, LightRange = 6, Glint = true }, -- crossbow: string-snap glint, no flash
	Helix = with(ENERGY, { Size = 0.4, PetalCount = 0, Sparks = { 1, 2 }, SparkSpread = 22, LightB = 2.8, LightRange = 10 }), -- beam rifle: emitter glow
	Havoc = { Size = 0.7, FlashCount = 1, Petal = 0.8, PetalCount = 3, Sparks = { 2, 4 }, SparkSpread = 24, SmokeChance = 1, SmokeCount = 3, SmokeScale = 1.8, LightB = 4, LightRange = 14, Warm = C(255, 120, 40) }, -- launcher: heavy smoke
}
for name, t in P do
	P[name] = setmetatable(t, { __index = DEFAULT })
end
VFXKit.Profiles = P

-- ─── finish identities (Standard / Elite / Prime; shot overhaul §5.1) ────────
-- A finish restyles the chassis by shape and behaviour, not colour alone. Fields (all optional):
--   colours   Hot, Warm, SparkColor, Light, TracerColor, SmokeTint, Bolt / BoltCore (energy + arcing rounds, beams)
--   scale     SizeK, PetalK, LightK, FlashLifeK, RingK
--   shape     FlashTex (Tex key), PetalMode = "Side" (brake vents L/R), PetalCount, Ring, RingTex, Glint, SmokeChance
--   tracer    Tracer = { Tex = "Dash", Wrap = studs per dash, WidthK, LenK }
--   residue   Residue = particle spec, laid along the round's path in flight (first 75%: crosshair stays clean)
--   impact    Accent = { particle spec, ... } extra emitters on world hits
--   rhythm    Every = { N, WidthK, Color }  (every Nth round)
--             Heat  = { From = shots, Wisp = every n | SparkAdd | RingFrom | Alternate = true }
-- Particle spec: { Tex, c, c2?, Count, Size = {a, b}, Life = {a, b}, Speed = {a, b}?, Spread?, Accel?, Drag?,
--   Transp = {a, b}?, Emission?, Streak? (velocity-aligned), Rot? (spin), Flip = "Grid2x2"|"Grid4x4"?, Spacing? (residue studs) }
local F = {}
F.Factory = {}
F.Graphite = { -- matte suppressor look: dim, smoky, soft grey
	Hot = C(236, 234, 228), Warm = C(150, 150, 152), SparkColor = C(222, 222, 216), Light = C(230, 224, 214), LightK = 0.55,
	SizeK = 0.75, PetalK = 0.8, PetalCount = 3, SmokeChance = 1, SmokeTint = C(150, 152, 158),
	TracerColor = C(208, 210, 214), Tracer = { LenK = 0.9 }, Bolt = C(200, 205, 214), BoltCore = C(245, 245, 245),
	Residue = { Tex = "Smoke", Flip = "Grid4x4", c = C(185, 188, 194), c2 = C(140, 142, 148), Size = { 0.12, 0.5 }, Life = { 0.3, 0.45 }, Transp = { 0.55, 1 }, Accel = V(0, 0.6, 0), Drag = 2, Spread = 12, Speed = { 0.2, 0.6 }, Emission = 0, Spacing = 2.4 },
	Accent = { { Tex = "Smoke", Flip = "Grid4x4", c = C(165, 167, 172), Count = 2, Size = { 0.3, 1.3 }, Life = { 0.5, 0.8 }, Speed = { 1, 2.5 }, Spread = 35, Transp = { 0.4, 1 }, Emission = 0, Drag = 3 } },
	Heat = { From = 6, Wisp = 3 }, -- barrel smokes in long sprays
}
F.Whiteout = { -- clinical white: crisp 6-point star, thin needle, white flakes
	FlashTex = "Star6", Hot = C(255, 255, 255), Warm = C(200, 228, 255), SparkColor = C(235, 245, 255), Light = C(220, 235, 255),
	FlashLifeK = 0.7, PetalK = 0.7, SmokeChance = 0.2,
	TracerColor = C(246, 250, 255), Tracer = { WidthK = 0.7, LenK = 0.75 }, Bolt = C(235, 245, 255), BoltCore = C(255, 255, 255),
	Accent = {
		{ Tex = "Flake", Flip = "Grid2x2", c = C(250, 252, 255), Count = 5, Size = { 0.13, 0.03 }, Life = { 0.25, 0.5 }, Speed = { 4, 9 }, Spread = 55, Accel = V(0, -14, 0), Rot = true, Emission = 0.6 },
		{ Tex = "Ring", c = C(235, 245, 255), Count = 1, Size = { 0.15, 1.0 }, Life = { 0.14, 0.14 }, Transp = { 0.3, 1 } },
	},
}
F.Carbon = { -- stealth carbon: brake slit venting sideways, dark smoke, dashed amber tracer
	FlashTex = "Slit", PetalMode = "Side", PetalCount = 1, SizeK = 0.95, Hot = C(255, 214, 150), Warm = C(255, 140, 40),
	SmokeChance = 0.8, SmokeTint = C(78, 80, 86), Light = C(255, 170, 90), LightK = 0.8,
	TracerColor = C(255, 170, 70), Tracer = { Tex = "Dash", Wrap = 1.4, WidthK = 1.15, LenK = 1.4 }, Bolt = C(255, 160, 60), BoltCore = C(40, 40, 44),
	Accent = {
		{ Tex = "Flake", Flip = "Grid2x2", c = C(32, 32, 36), Count = 6, Size = { 0.1, 0.04 }, Life = { 0.3, 0.6 }, Speed = { 3, 8 }, Spread = 50, Accel = V(0, -20, 0), Rot = true, Emission = 0 },
		{ Tex = "Spark", Streak = true, c = C(255, 170, 60), Count = 2, Size = { 0.24, 0 }, Life = { 0.1, 0.2 }, Speed = { 10, 18 }, Spread = 40 },
	},
	Heat = { Alternate = true }, -- vents alternate left / right
}
F.Cobalt = { -- anodised blue: blue-rimmed star + ring, ion dots behind the round, blue spark spray
	Hot = C(220, 240, 255), Warm = C(60, 140, 255), SparkColor = C(120, 190, 255), Light = C(120, 170, 255), Ring = true, RingK = 0.6,
	TracerColor = C(150, 200, 255), Bolt = C(80, 150, 255), BoltCore = C(220, 240, 255),
	Residue = { Tex = "Glow", c = C(160, 210, 255), c2 = C(60, 120, 255), Size = { 0.09, 0 }, Life = { 0.2, 0.35 }, Spread = 180, Speed = { 0.2, 0.8 }, Spacing = 1.6 },
	Accent = {
		{ Tex = "Spark", Streak = true, c = C(120, 190, 255), Count = 7, Size = { 0.22, 0 }, Life = { 0.08, 0.2 }, Speed = { 10, 22 }, Spread = 50, Accel = V(0, -30, 0) },
		{ Tex = "Glow", c = C(110, 170, 255), Count = 1, Size = { 0.6, 0.1 }, Life = { 0.08, 0.1 }, Transp = { 0.1, 1 } },
	},
	Heat = { RingFrom = 4 }, -- the ring joins once the gun is sustained
}
F.Emberline = { -- ember forge: bigger flame cones + cinders, embers drifting off the round, ember splash
	Hot = C(255, 226, 160), Warm = C(255, 90, 20), SparkColor = C(255, 150, 60), Light = C(255, 140, 60), PetalK = 1.25, SparkAdd = 2,
	TracerColor = C(255, 140, 50), Bolt = C(255, 110, 30), BoltCore = C(255, 225, 160),
	Residue = { Tex = "Glow", c = C(255, 200, 90), c2 = C(255, 70, 10), Size = { 0.1, 0 }, Life = { 0.35, 0.6 }, Spread = 180, Speed = { 0.3, 1.2 }, Accel = V(0, 2.2, 0), Spacing = 2.2 },
	Accent = { { Tex = "Glow", c = C(255, 160, 60), c2 = C(255, 60, 10), Count = 7, Size = { 0.14, 0 }, Life = { 0.35, 0.7 }, Speed = { 5, 11 }, Spread = 55, Accel = V(0, -22, 0) } },
	Heat = { From = 5, SparkAdd = 3 }, -- cinders thicken
}
F.Gilded = { -- gold presentation: 4-petal crown + lens glint, every 4th round a bright glint, spinning gold leaf
	FlashTex = "Crown", Glint = true, Hot = C(255, 244, 200), Warm = C(255, 190, 60), SparkColor = C(255, 215, 110), Light = C(255, 210, 120),
	TracerColor = C(255, 214, 110), Bolt = C(255, 200, 80), BoltCore = C(255, 245, 210),
	Every = { N = 4, WidthK = 1.8, Color = C(255, 246, 215) },
	Accent = {
		{ Tex = "Flake", Flip = "Grid2x2", c = C(255, 222, 110), c2 = C(255, 170, 40), Count = 6, Size = { 0.12, 0.05 }, Life = { 0.4, 0.8 }, Speed = { 4, 9 }, Spread = 55, Accel = V(0, -16, 0), Rot = true, Emission = 0.8 },
		{ Tex = "Glint", c = C(255, 236, 170), Count = 1, Size = { 0.9, 0.2 }, Life = { 0.1, 0.12 }, Transp = { 0.1, 1 } },
	},
}
F.Tidebreaker = { -- tidal (Arc): ripple-ring flash, teal bolt shedding droplets, splash crown + ripple
	Hot = C(220, 255, 250), Warm = C(40, 210, 200), SparkColor = C(140, 255, 240), Light = C(80, 230, 220), Ring = true, RingTex = "Ripple", RingK = 1.1,
	TracerColor = C(80, 235, 220), Bolt = C(60, 230, 215), BoltCore = C(225, 255, 250),
	Residue = { Tex = "Drop", Streak = true, c = C(200, 255, 250), c2 = C(60, 220, 210), Size = { 0.16, 0.05 }, Life = { 0.3, 0.5 }, Speed = { 1, 3 }, Spread = 60, Accel = V(0, -26, 0), Spacing = 1.8 },
	Accent = {
		{ Tex = "Drop", Streak = true, c = C(210, 255, 250), c2 = C(60, 220, 210), Count = 9, Size = { 0.22, 0.06 }, Life = { 0.3, 0.55 }, Speed = { 8, 14 }, Spread = 35, Accel = V(0, -35, 0) },
		{ Tex = "Ripple", c = C(120, 245, 230), Count = 1, Size = { 0.25, 2.4 }, Life = { 0.3, 0.3 }, Transp = { 0.15, 1 } },
	},
}
VFXKit.Finishes = F

function VFXKit.Profile(weaponId: string?)
	return (weaponId and P[weaponId]) or DEFAULT
end

-- chassis + finish, cached per (weapon, skin)
local resolved = {}
function VFXKit.Resolve(weaponId: string?, skinId: string?)
	local base = (weaponId and P[weaponId]) or DEFAULT
	local fin = skinId and F[skinId]
	if not fin or next(fin) == nil then
		return base
	end
	local key = (weaponId or "?") .. "|" .. skinId
	local r = resolved[key]
	if r then return r end
	r = setmetatable({}, { __index = base })
	for k, v in fin do r[k] = v end
	r.Finish, r.FinishId = fin, skinId
	if fin.SizeK then r.Size = base.Size * fin.SizeK end
	if fin.PetalK then r.Petal = base.Petal * fin.PetalK end
	if fin.LightK then r.LightB = base.LightB * fin.LightK end
	if fin.PetalCount and base.PetalCount == 0 then r.PetalCount = 0 end -- energy guns / crossbow keep no petals
	if fin.Ring and base.Energy == false and weaponId == "Quill" then r.Ring = false end
	local T = fin.Tracer
	if T then
		r.TracerWidth = base.TracerWidth * (T.WidthK or 1)
		r.TracerLen = base.TracerLen * (T.LenK or 1)
	end
	resolved[key] = r
	return r
end

-- Weapon id from a muzzle attachment: nearest ancestor Model named after a profile (or tagged WeaponId).
function VFXKit.ProfileForInstance(inst: Instance?)
	local cur = inst
	while cur and cur ~= game do
		local wid = cur:GetAttribute("WeaponId")
		if type(wid) == "string" and P[wid] then
			return P[wid], wid
		end
		if cur:IsA("Model") and P[cur.Name] then
			return P[cur.Name], cur.Name
		end
		cur = cur.Parent
	end
	return DEFAULT, nil
end

-- chassis + the finish on the weapon model (Skins.Apply's "Skin" attribute)
function VFXKit.ResolveForInstance(inst: Instance?)
	local base, wid = VFXKit.ProfileForInstance(inst)
	local cur, skin = inst, nil
	while cur and cur ~= game do
		local s = cur:GetAttribute("Skin")
		if type(s) == "string" then
			skin = s
			break
		end
		cur = cur.Parent
	end
	if not skin or not F[skin] then
		return base, wid, skin
	end
	return VFXKit.Resolve(wid, skin), wid, skin
end

function VFXKit.NS(...)
	local a = { ... }
	if #a == 1 then return NumberSequence.new(a[1]) end
	local k = {}
	for i = 1, #a, 2 do
		table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(k)
end

return VFXKit
