--[[
	VANTAGE — SkinInspects (2026-11-15)
	Per-skin first-person inspect (F) for the VX-01 skin ladder. Same clip format as WeaponClips
	(Gun / Left tracks, Weights, Events) plus:
	  • per-key easing  e = nil (smoothstep) | "o" ease-out snap | "i" ease-in slam | "l" linear | "c" flowing spline
	  • Drive: curves that push the skin's own moving pieces while inspecting (read by Viewmodel)
	      SpinRate / SwayRate / FlapRate  time-rate multipliers for Spin / Sway / Flap pieces
	      SwayAmp                          amplitude multiplier for Sway pieces
	      HoldW, HoldA                     Flap pieces (wings, jaws) blend to a held angle (× Amp)
	  • Events named FX_<Name> run SkinInspects.FX on the viewmodel; every effect sits ON the gun
	    (particles locked to the gun body, Highlight / light flares, rings around the barrel axis).
	Weights.LeftOff > 0.5 hides the support arm (the Dragon's one-handed twirl).
	Method: fwjelaa animation craft (anticipation -> hero hold -> overshoot settle, overlap on pieces).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local WeaponClips = require(script.Parent.WeaponClips)

local V = Vector3.new
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function k(t, p, r, e)
	return { t = t, p = p or Vector3.zero, r = r or Vector3.zero, e = e }
end
local function w(t, v)
	return { t = t, w = v }
end

local SkinInspects = {}

-- ─── sampling ─────────────────────────────────────────────────────────────
local EASE = {
	s = function(u) return u * u * (3 - 2 * u) end,
	o = function(u) return 1 - (1 - u) ^ 3 end,
	i = function(u) return u * u * u end,
	l = function(u) return u end,
}
local function cat(p0, p1, p2, p3, u)
	local u2, u3 = u * u, u * u * u
	return 0.5 * ((2 * p1) + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3)
end
local function sampleKeys(keys, t)
	if t <= keys[1].t then
		return keys[1].p, keys[1].r
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.t then
			local u = (t - a.t) / math.max(1e-6, b.t - a.t)
			if b.e == "c" then
				local a0, b1 = keys[i - 2] or a, keys[i + 1] or b
				return cat(a0.p, a.p, b.p, b1.p, u), cat(a0.r, a.r, b.r, b1.r, u)
			end
			u = (EASE[b.e or "s"] or EASE.s)(u)
			return a.p:Lerp(b.p, u), a.r:Lerp(b.r, u)
		end
	end
	local l = keys[#keys]
	return l.p, l.r
end

local function sample(clip, t)
	local pose = WeaponClips.Sample({ Weights = clip.Weights, Hidden = clip.Hidden }, t)
	pose.FlyPivot = clip.FlyPivot
	local B = clip.Boost
	for name, keys in clip.Tracks do
		local p, r = sampleKeys(keys, t)
		if B then -- exaggeration (2026-11-15: v1 read too subtle); keys are offsets from rest, so scaling is safe
			if name == "Gun" then
				p = V(p.X * B.P, p.Y * B.P, p.Z * (B.PZ or B.P))
				r = V(r.X * B.R, r.Y * B.R, if B.KeepRoll then r.Z else r.Z * (B.RZ or B.R))
			elseif name == "Left" then
				p *= B.L or 1
			end
		end
		local FB = clip.FlyBoost
		if FB and name == "Fly" then -- v4: higher tosses, more turns (per-axis, whole revolutions kept)
			p *= FB.P or 1
			r = V(r.X * (FB.RX or 1), r.Y * (FB.RY or 1), r.Z * (FB.RZ or 1))
		end
		if name == "Fly" and clip.Hover ~= false then -- v5: a slow breathing hover while airborne
			local w = math.clamp((p.Magnitude - 0.15) / 0.35, 0, 1)
			if w > 0 then
				p += V(math.sin(t * 5.3) * 0.02, math.sin(t * 8.1) * 0.03, math.sin(t * 4.4) * 0.02) * w
				r += V(math.sin(t * 6.7) * 2.5, math.sin(t * 5.1) * 2, math.sin(t * 7.3) * 3) * w
			end
		end
		pose.Tracks[name] = WeaponClips.ToCFrame(p, r)
		pose.Raw[name] = r
	end
	return pose
end

local function curve(c, t, def)
	if not c then
		return def
	end
	if t <= c[1][1] then
		return c[1][2]
	end
	for i = 2, #c do
		if t <= c[i][1] then
			local a, b = c[i - 1], c[i]
			return a[2] + (b[2] - a[2]) * (t - a[1]) / math.max(1e-6, b[1] - a[1])
		end
	end
	return c[#c][2]
end

function SkinInspects.DriveAt(clip, t: number)
	local d = clip.Drive or {}
	local m = clip.DriveMul or 1 -- scales each curve's deviation from rest
	local function x(c, def)
		return def + (curve(c, t, def) - def) * m
	end
	return {
		SpinRate = x(d.SpinRate, 1),
		SwayRate = x(d.SwayRate, 1),
		FlapRate = x(d.FlapRate, 1),
		SwayAmp = x(d.SwayAmp, 1),
		FlapAmp = x(d.FlapAmp, 1),
		HoldW = curve(d.HoldW, t, 0),
		HoldA = x(d.HoldA, 0),
	}
end

-- ─── clips (keyed by skin Id) ─────────────────────────────────────────────
local C = {}
-- v3 (2026-11-15): Call-of-Duty style - the gun LEAVES the hands. Gun = what the hands do (toss / wait /
-- catch), Fly = the gun's own flight relative to the hands, spinning about FlyPivot (kit Root space).
local PIV = V(0, 0.1, -0.6)

-- RARE: Glacier Ops 2.6 s - end-over-end backflip toss with a frost trail, frost-burst catch, side check
C.GlacierOps = {
	Length = 2.6,
	FlyPivot = PIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.15, V(0, -0.06, 0.02), V(-8, 0, 0)),
			k(0.28, V(0, 0.08, -0.02), V(12, 0, 0), "o"),
			k(0.5, V(0, 0.02, 0), V(4, 0, 0)),
			k(1.05, V(0, 0.03, 0), V(3, 0, 0)),
			k(1.12, V(0, -0.08, 0.03), V(-10, 2, -3), "o"),
			k(1.35, V(0, 0.01, 0), V(2, 0, 1)),
			k(1.7, V(-0.2, 0.25, 0.15), V(12, 40, -60)),
			k(2.05, V(-0.22, 0.26, 0.15), V(14, 42, -63)),
			k(2.3, V(0, -0.03, 0.01), V(-4, 2, -5), "o"),
			k(2.6),
		},
		Fly = {
			k(0), k(0.28),
			k(0.45, V(0, 0.55, 0.05), V(130, 0, 8), "c"),
			k(0.62, V(0, 0.8, 0.05), V(230, 0, 12), "c"),
			k(0.8, V(0, 0.55, 0.03), V(310, 0, 8), "c"),
			k(0.98, V(0, 0.14, 0.01), V(352, 0, 2), "c"),
			k(1.12, nil, V(360, 0, 0), "o"),
			k(2.6, nil, V(360, 0, 0)),
		},
		Left = { k(0), k(0.24, V(-0.1, -0.25, 0.2), nil, "o"), k(1.05, V(-0.08, -0.2, 0.15)), k(1.2), k(2.6) },
	},
	Events = {
		{ t = 0.28, name = "Equip" }, { t = 0.32, name = "FX_FrostTrail" }, { t = 0.52, name = "FX_FrostTrail" },
		{ t = 0.72, name = "FX_FrostTrail" }, { t = 0.92, name = "FX_FrostTrail" },
		{ t = 1.12, name = "FX_Frost" }, { t = 1.12, name = "MagIn" },
		{ t = 2.3, name = "FX_Shards" }, { t = 2.3, name = "Bolt" },
	},
}

-- EPIC: Archangel 3.6 s - released, it RISES: wings beat and hold it aloft while it turns a full 360
-- in front of you, halos blazing, then it floats back down into the hands
C.Archangel = {
	Length = 3.6,
	FlyPivot = PIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.2, V(0, -0.04, 0.02), V(-6, 0, 0)),
			k(0.4, V(0, 0.04, 0), V(5, 0, 0), "o"),
			k(0.9, V(0, -0.1, 0.06), V(-12, 0, 0)),
			k(2.7, V(0, -0.09, 0.06), V(-10, 0, 0)),
			k(2.95, V(0, 0, 0)),
			k(3.02, V(0, -0.06, 0.02), V(-7, 0, 0), "o"),
			k(3.3, V(0, 0.005, 0), V(1, 0, 0)),
			k(3.6),
		},
		Fly = {
			k(0), k(0.38),
			k(0.9, V(-0.3, 0.55, -0.5), V(10, 40, 0), "c"),
			k(1.4, V(-0.35, 0.7, -0.6), V(8, 120, 0), "c"),
			k(1.9, V(-0.35, 0.75, -0.6), V(6, 220, 0), "c"),
			k(2.4, V(-0.32, 0.7, -0.55), V(8, 320, 0), "c"),
			k(2.8, V(-0.05, 0.12, -0.05), V(4, 358, 0), "c"),
			k(2.97, nil, V(0, 360, 0), "o"),
			k(3.6, nil, V(0, 360, 0)),
		},
		Left = { k(0), k(0.38), k(0.6, V(-0.08, -0.2, 0.15)), k(2.75, V(-0.06, -0.18, 0.12)), k(3.0), k(3.6) },
	},
	Drive = {
		HoldW = { { 0, 0 }, { 0.15, 1 }, { 0.38, 1 }, { 0.48, 0 }, { 2.8, 0 }, { 2.9, 1 }, { 3.4, 1 }, { 3.6, 0 } },
		HoldA = { { 0, 0 }, { 0.15, -1 }, { 0.38, -1.1 }, { 0.48, 0 }, { 2.8, 0 }, { 2.9, -0.8 }, { 3.4, -0.6 }, { 3.6, 0 } },
		FlapRate = { { 0, 1 }, { 0.4, 1 }, { 0.5, 3.2 }, { 2.6, 3.2 }, { 2.9, 1 } },
		FlapAmp = { { 0, 1 }, { 0.4, 1 }, { 0.5, 2 }, { 2.6, 2 }, { 2.9, 1 } },
		SpinRate = { { 0, 1 }, { 0.4, 7 }, { 2.6, 7 }, { 3.2, 1.5 }, { 3.6, 1 } },
	},
	Events = {
		{ t = 0.42, name = "FX_HaloBurst" }, { t = 0.42, name = "Equip" },
		{ t = 1.0, name = "FX_Feathers" }, { t = 1.6, name = "FX_Feathers" }, { t = 2.2, name = "FX_Feathers" },
		{ t = 2.97, name = "FX_HaloLand" }, { t = 3.02, name = "MagIn" },
	},
}

-- MYTHIC: Molten Sovereign 3.4 s - TOO HOT: it bounces in the hands twice, the support hand flinches
-- off, then it's tossed up spinning through an ember trail; catch, maw to camera, JAW SNAP + lava pulse
C.MoltenSovereign = {
	Length = 3.4,
	FlyPivot = PIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.12, V(0, -0.05, 0.02), V(-8, 0, 4)),
			k(0.2, V(0, 0.05, 0), V(6, 0, -3), "o"),
			k(0.45, V(0.02, -0.05, 0.03), V(-7, 2, 4), "o"),
			k(0.55, V(-0.01, 0.05, 0), V(5, -2, -3), "o"),
			k(0.85, V(0, -0.06, 0.03), V(-8, 0, 5), "o"),
			k(0.95, V(0, 0.08, 0), V(9, 0, 0), "o"),
			k(1.9, V(0, -0.03, 0.03), V(-4, 0, 0)),
			k(1.97, V(0, -0.1, 0.04), V(-11, 0, 6), "o"),
			k(2.12, V(0, -0.02, 0.01), V(-2, 0, 1)),
			k(2.4, V(-0.18, 0.18, 0.12), V(15, 62, -20)),
			k(2.62, V(-0.18, 0.19, 0.12), V(16, 63, -19)),
			k(2.68, V(-0.18, 0.24, 0.17), V(24, 65, -16), "o"),
			k(2.85, V(-0.17, 0.18, 0.12), V(15, 60, -20)),
			k(3.15, V(0, 0.01, 0), V(1, -1, 1)),
			k(3.4),
		},
		Fly = {
			k(0), k(0.2),
			k(0.32, V(0.03, 0.24, 0), V(14, -10, 18), "o"),
			k(0.45),
			k(0.55),
			k(0.7, V(-0.04, 0.3, 0), V(-10, 12, -22), "o"),
			k(0.85),
			k(0.95),
			k(1.2, V(-0.12, 0.65, -0.25), V(20, 120, 10), "c"),
			k(1.45, V(-0.14, 0.8, -0.3), V(25, 220, 14), "c"),
			k(1.7, V(-0.07, 0.5, -0.2), V(15, 320, 8), "c"),
			k(1.97, nil, V(0, 360, 0), "o"),
			k(3.4, nil, V(0, 360, 0)),
		},
		Left = {
			k(0),
			k(0.15, V(-0.14, -0.14, 0.28), V(10, 0, 35), "o"),
			k(1.9, V(-0.12, -0.12, 0.24), V(8, 0, 30)),
			k(2.1, nil, nil, "o"),
			k(3.4),
		},
	},
	Drive = {
		HoldW = { { 0, 0 }, { 2.2, 0 }, { 2.35, 1 }, { 2.95, 1 }, { 3.2, 0 } },
		HoldA = { { 0, 0 }, { 2.3, 0 }, { 2.4, 1 }, { 2.62, 2.8 }, { 2.67, -0.3 }, { 2.8, 0.3 }, { 2.95, 0 } },
	},
	Events = {
		{ t = 0.2, name = "FX_Sizzle" }, { t = 0.55, name = "FX_Sizzle" }, { t = 0.95, name = "FX_Sizzle" },
		{ t = 1.1, name = "FX_EmberTrail" }, { t = 1.3, name = "FX_EmberTrail" }, { t = 1.5, name = "FX_EmberTrail" }, { t = 1.7, name = "FX_EmberTrail" },
		{ t = 1.97, name = "MagIn" },
		{ t = 2.45, name = "FX_MawFire" }, { t = 2.67, name = "FX_LavaPulse" }, { t = 2.67, name = "Bolt" },
	},
}

-- LEGENDARY: Event Horizon 3.8 s - gravity RIPS it out of the hands: it orbits a point in front of you,
-- barrel-rolling, trailing void; TIME STOP; then it's yanked back into the grip
local OC = V(-0.4, 0.55, -1.2)
local function orb(a, r)
	return OC + V(math.cos(math.rad(a)), math.sin(math.rad(a)), 0) * r
end
C.EventHorizon = {
	Length = 3.8,
	FlyPivot = PIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.2, V(0, 0.03, 0), V(4, 0, 0)),
			k(0.35, V(0, 0.06, -0.1), V(7, 0, 0), "o"),
			k(0.9, V(0, -0.06, 0.05), V(-7, 0, 0)),
			k(2.35, V(0, -0.05, 0.04), V(-6, 0, 0)),
			k(2.45, V(-0.03, 0.06, -0.06), V(8, 0, 0)),
			k(2.55, V(0, -0.1, 0.05), V(-13, -4, 6), "o"),
			k(2.8, V(0, 0.015, -0.005), V(2, 1, -1)),
			k(3.8),
		},
		Fly = {
			k(0), k(0.35),
			k(0.65, orb(-40, 0.3) + V(0, 0, 0.3), V(0, 25, 60), "c"),
			k(0.95, orb(200, 0.42), V(0, 25, 150), "c"),
			k(1.25, orb(90, 0.42), V(0, 25, 240), "c"),
			k(1.55, orb(-20, 0.42), V(0, 25, 330), "c"),
			k(1.85, orb(-110, 0.42), V(0, 25, 420), "c"),
			k(2.08, orb(-170, 0.42), V(0, 25, 480), "c"),
			k(2.12, orb(-176, 0.42), V(0, 25, 486), "o"),
			k(2.32, orb(-176, 0.42), V(0, 25, 486), "l"),
			k(2.55, nil, V(0, 0, 720), "i"),
			k(3.8, nil, V(0, 0, 720)),
		},
		Left = { k(0), k(0.3, V(-0.06, -0.16, 0.15)), k(2.35, V(-0.05, -0.14, 0.12)), k(2.55, nil, nil, "i"), k(3.8) },
	},
	Drive = {
		SpinRate = { { 0, 1 }, { 0.4, 8 }, { 2.05, 12 }, { 2.12, 0.02 }, { 2.32, 0.02 }, { 2.5, 4 }, { 3.2, 1 } },
		SwayAmp = { { 0, 1 }, { 0.4, 3 }, { 2.32, 3 }, { 2.6, 1.5 }, { 3.5, 1 } },
		SwayRate = { { 0, 1 }, { 0.4, 2 }, { 2.08, 2 }, { 2.12, 0.02 }, { 2.32, 0.02 }, { 2.4, 1 } },
	},
	Events = {
		{ t = 0.35, name = "FX_Release" }, { t = 0.35, name = "Equip" },
		{ t = 0.7, name = "FX_VoidTrail" }, { t = 1.0, name = "FX_VoidTrail" }, { t = 1.3, name = "FX_VoidTrail" },
		{ t = 1.6, name = "FX_VoidTrail" }, { t = 1.9, name = "FX_VoidTrail" },
		{ t = 2.12, name = "FX_Collapse" },
		{ t = 2.55, name = "FX_Release" }, { t = 2.55, name = "Bolt" },
	},
}

-- EXCLUSIVE: Kitsune // Lunar Festival 3.8 s - tossed up and spun flat like a blade (3 turns) through
-- foxfire, caught on the BELL, then laid flat and presented
C.Kitsune = {
	Length = 3.8,
	FlyPivot = PIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.18, V(0, -0.05, 0.02), V(-6, 0, 0)),
			k(0.3, V(0, 0.06, -0.02), V(8, 0, 0), "o"),
			k(0.55, V(0, -0.05, 0.03), V(-5, 0, 0)),
			k(1.55, V(0, -0.03, 0.03), V(-3, 0, 0)),
			k(1.62, V(0, -0.09, 0.04), V(-11, 0, 4), "o"),
			k(1.85, V(0, 0, 0), V(1, 0, 0)),
			k(2.3, V(-0.12, 0.25, 0.1), V(10, 22, -76)),
			k(2.9, V(-0.2, 0.25, 0.06), V(8, 36, -80), "c"),
			k(3.3, V(0, 0.02, 0), V(-2, 2, -3)),
			k(3.8),
		},
		Fly = {
			k(0), k(0.3),
			k(0.5, V(-0.15, 0.6, -0.35), V(0, 180, 0), "c"),
			k(0.75, V(-0.25, 0.9, -0.45), V(0, 400, 0), "c"),
			k(1.0, V(-0.25, 0.95, -0.45), V(0, 620, 0), "c"),
			k(1.25, V(-0.15, 0.65, -0.35), V(0, 840, 0), "c"),
			k(1.45, V(-0.05, 0.25, -0.1), V(0, 1010, 0), "c"),
			k(1.62, nil, V(0, 1080, 0), "o"),
			k(3.8, nil, V(0, 1080, 0)),
		},
		Left = { k(0), k(0.28, V(-0.1, -0.22, 0.18), nil, "o"), k(1.55, V(-0.08, -0.18, 0.14)), k(1.7), k(3.8) },
	},
	Drive = {
		SwayAmp = { { 0, 1 }, { 0.3, 3 }, { 1.6, 3.5 }, { 1.62, 5 }, { 2.2, 2.5 }, { 3.8, 1.3 } },
		SwayRate = { { 0, 1 }, { 0.3, 2.5 }, { 1.6, 2.5 }, { 1.62, 3 }, { 2.4, 1.2 }, { 3.8, 1 } },
	},
	Events = {
		{ t = 0.3, name = "FX_Foxfire" }, { t = 0.3, name = "Equip" },
		{ t = 0.5, name = "FX_FoxTrail" }, { t = 0.7, name = "FX_FoxTrail" }, { t = 0.9, name = "FX_FoxTrail" },
		{ t = 1.1, name = "FX_FoxTrail" }, { t = 1.3, name = "FX_FoxTrail" },
		{ t = 1.62, name = "FX_Bell" }, { t = 1.62, name = "MagOut" },
		{ t = 2.6, name = "FX_Foxfire" },
	},
}

-- GODLY: Golden Dragon Emperor 4.4 s - heaved straight up OUT OF FRAME, it comes crashing back down
-- rolling through fire; heavy catch + gold shockwave; then the jaw ROAR finisher
C.DragonEmperor = {
	Length = 4.4,
	FlyPivot = PIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.25, V(0, -0.09, 0.04), V(-13, 0, 0)),
			k(0.38, V(0, 0.13, -0.06), V(20, 0, 0), "o"),
			k(0.7, V(0, -0.03, 0.03), V(-4, 0, 0)),
			k(1.5, V(0, 0.03, 0), V(2, 0, 0)),
			k(1.62, V(0, -0.17, 0.06), V(-19, -4, 8), "o"),
			k(1.95, V(0, 0.01, -0.01), V(2, 0, -1)),
			k(2.4, V(-0.1, 0.3, -0.1), V(22, -9, 10)),
			k(2.85, V(-0.1, 0.32, -0.1), V(23, -9, 10)),
			k(2.95, V(-0.12, 0.37, -0.22), V(28, -10, 10), "o"),
			k(3.05, V(-0.08, 0.3, -0.02), V(18, -8, 8), "o"),
			k(3.5, V(-0.1, 0.32, -0.1), V(22, -9, 10)),
			k(3.95, V(0, -0.03, 0.02), V(-5, 3, -6)),
			k(4.15, V(0, 0.005, 0), V(1, -1, 1)),
			k(4.4),
		},
		Fly = {
			k(0), k(0.38),
			k(0.55, V(0, 1.2, -0.3), V(60, 0, 180), "c"),
			k(0.75, V(0, 2.7, -0.5), V(88, 0, 400), "c"),
			k(1.0, V(0, 3.3, -0.5), V(90, 0, 620), "c"),
			k(1.22, V(0, 2.4, -0.4), V(80, 0, 860), "c"),
			k(1.42, V(0, 0.7, -0.2), V(40, 0, 1010), "c"),
			k(1.62, nil, V(0, 0, 1080), "o"),
			k(4.4, nil, V(0, 0, 1080)),
		},
		Left = { k(0), k(0.32, V(-0.1, -0.3, 0.25), nil, "o"), k(1.5, V(-0.06, -0.12, 0.1)), k(1.66), k(4.4) },
	},
	Drive = {
		HoldW = { { 0, 0 }, { 1.6, 0 }, { 1.7, 1 }, { 4.2, 1 }, { 4.4, 0 } },
		HoldA = { { 0, 0 }, { 1.6, 0 }, { 1.7, 1.8 }, { 1.9, 0.8 }, { 2.3, 1.2 }, { 2.5, 2.6 }, { 2.9, 2.6 }, { 2.97, 3.6 },
			{ 3.1, 3.0 }, { 3.6, 2.8 }, { 3.95, 0.4 }, { 4.4, 0 } },
		SwayAmp = { { 0, 1 }, { 0.4, 3 }, { 1.6, 3.5 }, { 3.0, 4 }, { 3.6, 2.2 }, { 4.4, 1 } },
		SwayRate = { { 0, 1 }, { 0.4, 2.5 }, { 1.6, 2.5 }, { 2, 1.4 }, { 3, 2 }, { 4.4, 1 } },
	},
	Events = {
		{ t = 0.38, name = "FX_DragonLaunch" }, { t = 0.38, name = "Equip" },
		{ t = 0.5, name = "FX_FireTrail" }, { t = 0.65, name = "FX_FireTrail" },
		{ t = 1.28, name = "FX_FireTrail" }, { t = 1.45, name = "FX_FireTrail" },
		{ t = 1.62, name = "FX_Impact" }, { t = 1.62, name = "MagIn" },
		{ t = 2.3, name = "FX_MawGlow" }, { t = 2.6, name = "FX_MawFire" },
		{ t = 2.95, name = "FX_Roar" }, { t = 3.05, name = "Bolt" }, { t = 3.1, name = "FX_TailFire" },
	},
}

-- ─── v4 exaggeration (2026-11-15): bigger hand throws, higher tosses, more revolutions ──────────────────
C.GlacierOps.Boost = { P = 1.5, R = 1.3, L = 1.2 }
C.GlacierOps.FlyBoost = { P = 1.35, RX = 2 } -- DOUBLE backflip
C.Archangel.Boost = { P = 1.5, R = 1.3, L = 1.2 }
C.Archangel.FlyBoost = { P = 1.3, RY = 2 } -- two full turns aloft
C.MoltenSovereign.Boost = { P = 1.5, R = 1.3, L = 1.2 }
C.MoltenSovereign.FlyBoost = { P = 1.3, RY = 2 }
C.EventHorizon.Boost = { P = 1.5, R = 1.3, L = 1.2 }
C.EventHorizon.FlyBoost = { P = 1.25, RZ = 1.5 } -- 3 barrel rolls through the orbit + yank
C.Kitsune.Boost = { P = 1.5, R = 1.1, L = 1.2 }
C.Kitsune.FlyBoost = { P = 1.3, RY = 4 / 3 } -- 4 flat blade turns
C.DragonEmperor.Boost = { P = 1.5, R = 1.3, L = 1.2 }
C.DragonEmperor.FlyBoost = { P = 1.2, RZ = 4 / 3 } -- 4 rolls on the way down

-- ─── sound timeline: S(t, role, vol, pitch) plays a bank role; K(t, amount) kicks the viewmodel ───────
local function S(t, role, vol, pitch)
	return { t = t, name = string.format("FX_S_%s_%s_%s", role, tostring(vol or 1), tostring(pitch or 1)) }
end
local function K(t, amt)
	return { t = t, name = "FX_K_" .. tostring(amt) }
end
local SND = {
	GlacierOps = {
		S(0.28, "whoosh", 1, 0.9), S(0.45, "whoosh", 0.7, 1.15), S(0.62, "whoosh", 0.7, 1.25), S(0.8, "whoosh", 0.65, 1.15),
		S(1.12, "ice", 1), S(1.12, "boom", 0.35, 1.8), K(1.12, 1),
		S(1.6, "frostBurst", 0.6), S(2.3, "iceShards", 1), S(2.3, "ice", 0.5, 1.2), K(2.3, 0.5),
	},
	Archangel = {
		S(0.42, "holy", 1), S(0.42, "wings", 1), S(0.42, "whoosh", 0.8, 0.8), K(0.42, 0.5),
		S(1.0, "wings", 0.7), S(1.5, "whoosh", 0.6, 0.75), S(1.9, "holy", 0.7, 1.12), S(2.2, "wings", 0.6),
		S(2.6, "whoosh", 0.55, 0.85),
		S(2.97, "holy", 1, 0.9), S(2.97, "boom", 0.3, 1.6), K(2.97, 0.9),
	},
	MoltenSovereign = {
		S(0.2, "sizzle", 1), S(0.32, "whoosh", 0.45, 1.2), K(0.45, 0.4), S(0.55, "sizzle", 0.9, 1.1), S(0.7, "whoosh", 0.45, 1.25), K(0.85, 0.4),
		S(0.95, "fire", 1), S(0.95, "whoosh", 0.9), S(1.25, "fire", 0.7, 1.05), S(1.5, "fire", 0.7, 1.15), S(1.7, "whoosh", 0.6, 1.1),
		S(1.97, "boom", 0.4, 1.7), K(1.97, 1),
		S(2.45, "fire", 0.8, 0.8), S(2.45, "growl", 0.8),
		S(2.67, "snap", 1), S(2.67, "boom", 0.6), S(2.67, "fire", 1, 0.7), K(2.67, 1.2),
	},
	EventHorizon = {
		S(0.35, "void", 1), S(0.35, "whoosh", 0.9, 0.7), K(0.35, 0.6), S(0.43, "reverse", 1),
		S(0.75, "whoosh", 0.55, 0.75), S(1.05, "whoosh", 0.55, 0.8), S(1.35, "whoosh", 0.55, 0.85), S(1.65, "whoosh", 0.55, 0.9), S(1.95, "whoosh", 0.55, 0.95),
		S(2.12, "timestop", 1),
		S(2.55, "boom", 0.7), S(2.55, "void", 0.5, 1.4), K(2.55, 1.3),
	},
	Kitsune = {
		S(0.3, "whoosh", 1), S(0.3, "fire", 0.5, 1.35), K(0.3, 0.4),
		S(0.45, "whoosh", 0.5, 1.1), S(0.62, "whoosh", 0.5, 1.2), S(0.79, "whoosh", 0.5, 1.3), S(0.96, "whoosh", 0.5, 1.25),
		S(1.13, "whoosh", 0.5, 1.2), S(1.3, "whoosh", 0.5, 1.15), S(1.45, "whoosh", 0.5, 1.1),
		S(1.62, "bell", 1), S(1.62, "glock", 0.8), S(1.62, "holy", 0.6, 1.2), K(1.62, 0.8),
		S(2.6, "fire", 0.4, 1.4), S(2.6, "holy", 0.35, 1.3),
	},
	DragonEmperor = {
		S(0.38, "whooshBig", 1), S(0.38, "fire", 1), K(0.38, 0.7), S(0.6, "fire", 0.7, 1.1),
		S(1.2, "whoosh", 0.9, 0.7), S(1.28, "fire", 0.8), S(1.38, "whoosh", 0.8, 0.8), S(1.48, "whoosh", 0.8, 0.9),
		S(1.62, "boom", 1), S(1.62, "growl", 0.6), K(1.62, 1.7),
		S(2.3, "fire", 0.5, 0.8), S(2.6, "fire", 0.7, 0.75),
		S(2.95, "roar", 1), S(2.95, "boom", 0.7), S(2.95, "fire", 1, 0.7), K(2.95, 1.5),
		S(3.1, "fire", 0.5, 0.9),
	},
}
for id, list in SND do
	for _, ev in list do
		table.insert(C[id].Events, ev)
	end
end

-- ═══ BR-07 SENTINEL ladder (2026-11-15): precise marksman flourishes, each with a scope beat ═══════════
local SPIV = V(0, 0.1, -0.4)

-- EPIC: Storm Herald "Lightning Rod" 3.4 s - held high and charging (wings folded, arcs on the barrel) -> thrown
-- up, LIGHTNING strikes it mid-air, wings snap open -> falls back spinning twice like a rotor -> catch -> scope glint
C.StormHerald = {
	Weapon = "Sentinel", Length = 3.4, FlyPivot = SPIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.25, V(-0.05, 0.18, -0.05), V(18, -6, 6)),
			k(0.5, V(-0.052, 0.19, -0.05), V(19, -6, 7)),
			k(0.7, V(-0.048, 0.185, -0.052), V(17.5, -5, 5.5)),
			k(0.82, V(-0.02, 0.05, 0.02), V(4, 0, 0)),
			k(0.92, V(0, 0.12, -0.05), V(16, 0, 0), "o"),
			k(1.2, V(0, -0.04, 0.03), V(-5, 0, 0)),
			k(2.25, V(0, 0.03, 0), V(2, 0, 0)),
			k(2.32, V(0, -0.11, 0.05), V(-13, 2, -4), "o"),
			k(2.55, V(0, 0.01, 0), V(1, 0, 0)),
			k(2.85, V(-0.06, 0.08, 0.06), V(6, 24, -30)),
			k(3.1, V(0, 0.005, 0), V(0.5, 0, 0.5)),
			k(3.4),
		},
		Fly = {
			k(0), k(0.92),
			k(1.15, V(0, 0.9, -0.4), V(20, 0, 0), "c"),
			k(1.35, V(0, 1.15, -0.5), V(25, 0, 0), "c"),
			k(1.45, V(0, 1.12, -0.5), V(25, 10, 0), "o"),
			k(1.7, V(0, 0.85, -0.4), V(10, 240, 0), "c"),
			k(1.95, V(0, 0.5, -0.25), V(5, 480, 0), "c"),
			k(2.15, V(0, 0.15, -0.08), V(2, 660, 0), "c"),
			k(2.32, nil, V(0, 720, 0), "o"),
			k(3.4, nil, V(0, 720, 0)),
		},
		Left = { k(0), k(0.88), k(1.0, V(-0.1, -0.24, 0.2), nil, "o"), k(2.25, V(-0.08, -0.18, 0.14)), k(2.38), k(3.4) },
	},
	Drive = {
		HoldW = { { 0, 0 }, { 0.2, 1 }, { 0.85, 1 }, { 1.0, 0 }, { 1.3, 0 }, { 1.35, 1 }, { 1.6, 1 }, { 1.8, 0 }, { 3.4, 0 } },
		HoldA = { { 0, 0 }, { 0.2, -0.8 }, { 0.85, -1 }, { 1.0, 0 }, { 1.3, 0 }, { 1.35, 2.4 }, { 1.6, 2.0 }, { 1.8, 0 }, { 3.4, 0 } },
		FlapAmp = { { 0, 1 }, { 1.3, 1 }, { 1.36, 2.6 }, { 2.3, 2 }, { 2.6, 1 } },
		FlapRate = { { 0, 1 }, { 1.3, 1 }, { 1.36, 3 }, { 2.3, 2.5 }, { 2.6, 1 } },
	},
	Events = {
		{ t = 0.3, name = "FX_StormCharge" }, { t = 0.55, name = "FX_StormCharge" }, { t = 0.8, name = "FX_StormCharge" },
		{ t = 1.35, name = "FX_Lightning" },
		{ t = 1.6, name = "FX_StormSpark" }, { t = 1.85, name = "FX_StormSpark" }, { t = 2.1, name = "FX_StormSpark" },
		{ t = 2.32, name = "FX_StormCatch" }, { t = 2.85, name = "FX_Glint" },
	},
}

-- MYTHIC: Abyssal Leviathan "The Deep Bite" 3.6 s - sinks as if underwater, bubbles, the lure glows -> jaw gapes,
-- tail thrashes -> the gun LUNGES out of the hands and BITES -> yanked back like a fish on a line -> shows the tank
C.AbyssalLeviathan = {
	Weapon = "Sentinel", Length = 3.6, FlyPivot = SPIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.6, V(0, -0.08, 0.03), V(-6, 4, 4)),
			k(1.0, V(-0.12, 0.1, 0.05), V(10, 40, -10)),
			k(1.4, V(-0.13, 0.11, 0.06), V(11, 42, -11)),
			k(1.5, V(-0.1, 0.09, 0.12), V(8, 38, -10)),
			k(1.62, V(-0.1, 0.12, -0.12), V(12, 40, -10), "o"),
			k(1.95, V(-0.06, 0.06, 0.1), V(4, 20, -6)),
			k(2.05, V(0, -0.1, 0.05), V(-12, 0, 4), "o"),
			k(2.3, V(0, 0.01, 0), V(1, 0, 0)),
			k(2.7, V(-0.04, 0.1, 0.06), V(-30, 8, 20)),
			k(3.15, V(-0.042, 0.102, 0.062), V(-31, 9, 21)),
			k(3.6),
		},
		Fly = {
			k(0), k(1.62),
			k(1.78, V(0, 0.15, -1.1), V(-8, 0, 0), "o"),
			k(1.88, V(0, 0.12, -1.15), V(-6, 0, 0)),
			k(2.05, nil, V(0, 0, 360), "i"),
			k(3.6, nil, V(0, 0, 360)),
		},
		Left = { k(0), k(1.5), k(1.62, V(-0.1, -0.22, 0.2), nil, "o"), k(1.98, V(-0.08, -0.18, 0.14)), k(2.1), k(3.6) },
	},
	Drive = {
		HoldW = { { 0, 0 }, { 0.9, 0 }, { 1.0, 1 }, { 2.2, 1 }, { 2.4, 0 } },
		HoldA = { { 0, 0 }, { 0.9, 0 }, { 1.0, 0.4 }, { 1.5, 2.6 }, { 1.62, 3.2 }, { 1.86, 3.2 }, { 1.89, -0.3 }, { 2.0, 0.3 }, { 2.2, 0 } },
		SwayAmp = { { 0, 1 }, { 0.5, 1.5 }, { 1.5, 3.5 }, { 1.9, 4 }, { 2.4, 2 }, { 3.6, 1 } },
		SwayRate = { { 0, 1 }, { 1.0, 1.5 }, { 1.5, 3 }, { 2.0, 2 }, { 3.6, 1 } },
	},
	Events = {
		{ t = 0.2, name = "FX_Bubbles" }, { t = 0.6, name = "FX_Bubbles" }, { t = 1.0, name = "FX_Bubbles" }, { t = 1.3, name = "FX_Bubbles" },
		{ t = 0.9, name = "FX_Lure" },
		{ t = 1.7, name = "FX_BubbleTrail" }, { t = 1.8, name = "FX_BubbleTrail" }, { t = 1.89, name = "FX_Bite" }, { t = 1.95, name = "FX_BubbleTrail" },
		{ t = 2.05, name = "FX_Splash" }, { t = 2.8, name = "FX_TankGlow" },
	},
}

-- LEGENDARY: Celestial Astrolabe "Orrery" 3.8 s - lifted out of the hands, hangs in the air; the ring spins up and
-- THREE gyroscope rings orbit it while it turns on every axis among star motes -> rings LOCK (gong, sun flare) -> lowers
C.CelestialAstrolabe = {
	Weapon = "Sentinel", Length = 3.8, FlyPivot = SPIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.2, V(0, -0.03, 0.02), V(-4, 0, 0)),
			k(0.4, V(0, 0.04, 0), V(3, 0, 0)),
			k(0.8, V(0, -0.08, 0.06), V(-8, 0, 0)),
			k(2.85, V(0, -0.07, 0.06), V(-7, 0, 0)),
			k(3.05),
			k(3.12, V(0, -0.06, 0.03), V(-7, 0, 0), "o"),
			k(3.4, V(0, 0.005, 0), V(1, 0, 0)),
			k(3.8),
		},
		Fly = {
			k(0), k(0.4),
			k(0.9, V(-0.3, 0.5, -0.55), V(10, 30, 20), "c"),
			k(1.5, V(-0.32, 0.58, -0.6), V(90, 140, 100), "c"),
			k(2.1, V(-0.32, 0.6, -0.6), V(220, 250, 220), "c"),
			k(2.5, V(-0.32, 0.6, -0.6), V(320, 330, 320), "c"),
			k(2.65, V(-0.32, 0.6, -0.6), V(360, 360, 360), "o"),
			k(2.85, V(-0.12, 0.25, -0.25), V(360, 360, 360)),
			k(3.05, nil, V(360, 360, 360), "i"),
			k(3.8, nil, V(360, 360, 360)),
		},
		Left = { k(0), k(0.38), k(0.6, V(-0.08, -0.2, 0.15)), k(2.95, V(-0.06, -0.18, 0.12)), k(3.1), k(3.8) },
	},
	Drive = {
		SpinRate = { { 0, 1 }, { 0.4, 1 }, { 1.0, 6 }, { 2.5, 10 }, { 2.62, 10 }, { 2.65, 0 }, { 2.85, 0 }, { 3.2, 1 } },
	},
	Events = {
		{ t = 0.5, name = "FX_StarMotes" }, { t = 0.6, name = "FX_Orrery" }, { t = 1.2, name = "FX_StarMotes" },
		{ t = 1.6, name = "FX_Constellation" }, { t = 1.9, name = "FX_StarMotes" }, { t = 2.2, name = "FX_Constellation" },
		{ t = 2.65, name = "FX_SunFlare" }, { t = 3.3, name = "FX_Glint" },
	},
}

-- EXCLUSIVE: Sakura Ronin // Spring Festival "Iaijutsu" 3.6 s - drawn slowly along its length like a katana, tassel
-- trailing -> flicked into one fast spin -> caught in a SWORD-SLASH: pink arc + petal burst -> stillness -> sheathed
C.SakuraRonin = {
	Weapon = "Sentinel", Length = 3.6, FlyPivot = SPIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.15, V(0, -0.03, 0.02), V(-4, 0, 0)),
			k(0.4, V(0.05, 0, 0.12), V(4, -8, -80)),
			k(1.1, V(-0.05, 0.08, -0.15), V(6, 10, -82), "c"),
			k(1.3, V(-0.04, 0.06, -0.1), V(4, 8, -80)),
			k(1.4, V(0, 0.1, -0.05), V(14, 0, -40), "o"),
			k(1.7, V(0, -0.03, 0.03), V(-4, 0, 0)),
			k(1.78, V(0.15, 0.05, 0.05), V(0, -40, -20), "o"),
			k(1.95, V(-0.25, 0.02, -0.08), V(-4, 70, 30), "o"),
			k(2.0, V(-0.27, 0.02, -0.09), V(-5, 74, 32)),
			k(2.6, V(-0.26, 0.02, -0.085), V(-5, 73, 31)),
			k(2.95, V(0.02, -0.04, 0.02), V(-3, -6, -10)),
			k(3.25, V(0, 0.004, 0), V(0.5, 0, 0.5)),
			k(3.6),
		},
		Fly = {
			k(0), k(1.4),
			k(1.55, V(0, 0.45, -0.1), V(180, 0, 0), "c"),
			k(1.78, nil, V(360, 0, 0), "o"),
			k(3.6, nil, V(360, 0, 0)),
		},
		Left = { k(0), k(1.32), k(1.45, V(-0.12, -0.25, 0.2), nil, "o"), k(2.8, V(-0.12, -0.25, 0.2)), k(3.0), k(3.6) },
	},
	Drive = {
		SwayAmp = { { 0, 1 }, { 0.4, 2 }, { 1.1, 2.5 }, { 1.95, 5 }, { 2.6, 2.5 }, { 3.6, 1.2 } },
		SwayRate = { { 0, 1 }, { 1.9, 1 }, { 1.95, 3 }, { 2.6, 1 }, { 3.6, 1 } },
	},
	Events = {
		{ t = 0.4, name = "FX_Petals" }, { t = 0.5, name = "FX_Draw" }, { t = 1.0, name = "FX_Petals" },
		{ t = 1.95, name = "FX_Slash" }, { t = 2.1, name = "FX_Petals" }, { t = 2.4, name = "FX_Petals" }, { t = 2.95, name = "FX_Glint" },
	},
}

-- GODLY: Phoenix Ascendant "Rebirth" 4.6 s - white-hot in the hands -> heaved high, it BURSTS into a fireball (gone)
-- -> reborn: dives back down rolling through a fire spiral, the hidden wings UNFOLD for the dive -> heavy catch +
-- gold shockwave -> beak to camera: phoenix CRY + fire burst -> back to the hip
C.PhoenixAscendant = {
	Weapon = "Sentinel", Length = 4.6, FlyPivot = SPIV,
	Tracks = {
		Gun = {
			k(0),
			k(0.4, V(-0.03, 0.06, -0.02), V(8, -4, 4)),
			k(0.6, V(-0.031, 0.062, -0.02), V(8.5, -4, 4.5)),
			k(0.75, V(0, -0.08, 0.04), V(-12, 0, 0)),
			k(0.88, V(0, 0.14, -0.06), V(22, 0, 0), "o"),
			k(1.2, V(0, -0.03, 0.03), V(-4, 0, 0)),
			k(2.25, V(0, 0.03, 0), V(2, 0, 0)),
			k(2.38, V(0, -0.18, 0.07), V(-20, -4, 8), "o"),
			k(2.7, V(0, 0.01, -0.01), V(2, 0, -1)),
			k(3.1, V(-0.14, 0.18, 0.08), V(14, 58, -18)),
			k(3.45, V(-0.14, 0.19, 0.08), V(15, 59, -17)),
			k(3.52, V(-0.15, 0.24, 0.12), V(22, 62, -14), "o"),
			k(3.7, V(-0.14, 0.18, 0.08), V(14, 58, -18)),
			k(4.15, V(0, -0.02, 0.01), V(-3, 2, -3)),
			k(4.35, V(0, 0.004, 0), V(0.5, 0, 0.5)),
			k(4.6),
		},
		Fly = {
			k(0), k(0.88),
			k(1.05, V(0, 1.3, -0.4), V(50, 0, 0), "c"),
			k(1.3, V(0, 2.4, -0.6), V(75, 0, 0), "c"),
			k(1.55, V(0, 2.5, -0.6), V(-80, 0, 180), "l"),
			k(1.85, V(-0.1, 1.4, -0.5), V(-70, 0, 540), "c"),
			k(2.1, V(-0.05, 0.6, -0.3), V(-40, 0, 900), "c"),
			k(2.38, nil, V(0, 0, 1080), "o"),
			k(4.6, nil, V(0, 0, 1080)),
		},
		Left = { k(0), k(0.82), k(0.95, V(-0.1, -0.3, 0.25), nil, "o"), k(2.25, V(-0.06, -0.12, 0.1)), k(2.42), k(4.6) },
	},
	Drive = {
		SwayAmp = { { 0, 1 }, { 0.4, 2 }, { 2.4, 3.5 }, { 3.5, 4 }, { 4.6, 1 } },
		SwayRate = { { 0, 1 }, { 0.4, 1.5 }, { 2.4, 2.5 }, { 4.6, 1 } },
	},
	Events = {
		{ t = 0.2, name = "FX_WhiteHot" }, { t = 0.55, name = "FX_WhiteHot" },
		{ t = 0.88, name = "FX_PhoenixLaunch" }, { t = 1.0, name = "FX_FireTrailP" }, { t = 1.15, name = "FX_FireTrailP" },
		{ t = 1.3, name = "FX_Fireball" }, { t = 1.55, name = "FX_PhoenixWings" },
		{ t = 1.7, name = "FX_PhoenixTrail" }, { t = 1.9, name = "FX_PhoenixTrail" }, { t = 2.1, name = "FX_PhoenixTrail" }, { t = 2.25, name = "FX_PhoenixTrail" },
		{ t = 2.38, name = "FX_PhoenixImpact" }, { t = 3.52, name = "FX_PhoenixCry" }, { t = 3.6, name = "FX_TailFireP" },
	},
}

-- Sentinel: built big from the start (same exaggeration family as the Vanguard v4)
for _, id in { "StormHerald", "AbyssalLeviathan", "CelestialAstrolabe", "PhoenixAscendant" } do
	C[id].Boost = { P = 1.4, R = 1.25, L = 1.2 }
	C[id].FlyBoost = { P = 1.25 }
end
C.SakuraRonin.Boost = { P = 1.4, R = 1.1, L = 1.2 }
C.SakuraRonin.FlyBoost = { P = 1.25 }

local SND2 = {
	StormHerald = {
		S(0.3, "zap", 0.6, 0.8), S(0.55, "zap", 0.5, 0.9), S(0.8, "zap", 0.6, 1.0), S(0.92, "whoosh", 1, 0.85),
		S(1.35, "thunder", 1), S(1.35, "zap", 1), S(1.36, "wings", 0.9),
		S(1.6, "whoosh", 0.55, 1.2), S(1.85, "whoosh", 0.55, 1.3), S(2.1, "whoosh", 0.55, 1.25),
		S(2.32, "zap", 0.8, 1.2), S(2.32, "boom", 0.35, 1.8), K(2.32, 1), S(2.85, "holy", 0.35, 1.6),
	},
	AbyssalLeviathan = {
		S(0.2, "bubbles", 0.7), S(0.6, "bubbles", 0.6, 0.9), S(0.9, "whale", 0.8), S(1.3, "bubbles", 0.5, 0.8),
		S(1.62, "whoosh", 0.9, 0.8), S(1.62, "bubbles", 0.8, 1.1),
		S(1.89, "snap", 1, 0.8), S(1.89, "growl", 0.6, 0.8), K(1.89, 0.6),
		S(2.05, "bubbles", 1, 0.8), S(2.05, "boom", 0.4, 1.5), K(2.05, 1),
		S(2.8, "bubbles", 0.5, 1.2), S(2.8, "holy", 0.3, 0.8),
	},
	CelestialAstrolabe = {
		S(0.4, "holy", 0.8), S(0.53, "reverse", 0.6), S(0.6, "void", 0.4, 1.5),
		S(1.0, "holy", 0.5, 1.1), S(1.5, "holy", 0.5, 1.2), S(2.0, "holy", 0.5, 1.3),
		S(2.65, "gong", 1), S(2.65, "boom", 0.4, 1.4),
		S(3.12, "holy", 0.4, 0.9), K(3.12, 0.6),
	},
	SakuraRonin = {
		S(0.4, "wind", 0.5, 1.1), S(0.5, "bell", 0.6, 1.6),
		S(1.4, "whoosh", 0.8, 1.1), S(1.78, "boom", 0.3, 1.9), K(1.78, 0.5),
		S(1.95, "whoosh", 1, 0.85), S(1.95, "wind", 0.8, 1.2), S(1.95, "bell", 0.5, 1.9), K(1.95, 0.7),
		S(2.1, "holy", 0.4, 1.3), S(2.95, "boom", 0.2, 2.0), S(2.95, "bell", 0.3, 2.2),
	},
	PhoenixAscendant = {
		S(0.2, "fire", 0.5, 0.7), S(0.55, "fire", 0.5, 0.8),
		S(0.88, "whooshBig", 1), S(0.88, "fireBig", 1), K(0.88, 0.7),
		S(1.3, "fireBig", 1, 0.7), S(1.3, "boom", 0.6, 1.2),
		S(1.55, "bird", 0.7, 1.15), S(1.55, "wings", 0.8), S(1.7, "fire", 0.7),
		S(1.95, "whoosh", 0.8, 0.8), S(2.15, "whoosh", 0.8, 0.9),
		S(2.38, "boom", 1), S(2.38, "fireBig", 0.7, 0.8), K(2.38, 1.8),
		S(3.52, "bird", 1), S(3.52, "fireBig", 0.8), S(3.52, "boom", 0.5, 1.3), K(3.52, 1.2), S(3.7, "holy", 0.4, 0.9),
	},
}
for id, list in SND2 do
	for _, ev in list do
		table.insert(C[id].Events, ev)
	end
end

for id, clip in C do
	clip.SkinId = id
	clip.Sample = sample
	clip.Events = clip.Events or {}
	table.sort(clip.Events, function(a, b) return a.t < b.t end)
end
SkinInspects.Clips = C

function SkinInspects.For(skinId: string?, weaponId: string?)
	local c = skinId and C[skinId] or nil
	if c and weaponId and (c.Weapon or "Vanguard") ~= weaponId then
		return nil
	end
	return c
end

-- ─── FX (client, first-person viewmodel) ─────────────────────────────────
-- positions are kit Root-space (muzzle tip z -2.92, bore y 0.108), scaled by the viewmodel gun scale
local TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}
local RING
do
	local meshes = ReplicatedStorage.Vantage.Weapons:FindFirstChild("SkinKitMeshes")
	local arch = meshes and meshes:FindFirstChild("Archangel_Vanguard")
	RING = arch and arch:FindFirstChild("Halo0")
end

local function ctx(vm)
	local body, gun = vm.Body, vm.Gun
	if not body or not gun or not body.Parent or vm.Hidden or not vm.Visible then
		return nil, 1
	end
	return body, gun:GetScale()
end

local function attach(body, s, pos: Vector3, dir: Vector3?)
	local a = Instance.new("Attachment")
	a.Name = "InspectFX"
	local p = pos * s
	a.CFrame = if dir then CFrame.lookAt(p, p + dir) else CFrame.new(p)
	a.Parent = body
	Debris:AddItem(a, 3)
	return a
end

-- global effect scale (v2: bigger, denser, brighter; still locked to the gun)
local FXS, FXN, FXR, FXL = 2.0, 2.0, 1.6, 2.0

local function burst(vm, o)
	local body, s = ctx(vm)
	if not body then
		return
	end
	o = table.clone(o)
	o.Size = (o.Size or 0.1) * FXS
	o.SizeEnd = (o.SizeEnd or 0) * FXS
	o.Speed = (o.Speed or 1) * 1.25
	o.N = math.ceil((o.N or 12) * FXN)
	local a = attach(body, s, o.Pos, o.Dir or V(0, 1, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX[o.Tex or "Spark"]
	e.Color = if typeof(o.Color) == "Color3" then ColorSequence.new(o.Color) else o.Color
	e.LightEmission = o.Emit or 1
	e.LightInfluence = 0
	e.Brightness = o.Bright or 2
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, (o.Size or 0.1) * s), NumberSequenceKeypoint.new(1, (o.SizeEnd or 0) * s) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, o.T0 or 0.05), NumberSequenceKeypoint.new(1, 1) })
	local life = o.Life or 0.5
	e.Lifetime = NumberRange.new(life * 0.65, life)
	local sp = (o.Speed or 1) * s
	e.Speed = NumberRange.new(sp * 0.45, sp)
	local spread = o.Spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = (o.Accel or Vector3.zero) * s
	e.Drag = o.Drag or 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.EmissionDirection = Enum.NormalId.Front
	e.LockedToPart = o.Locked ~= false
	e.Rate = 0
	e.ZOffset = o.Z or 0.3
	e.Parent = a
	e:Emit(o.N or 12)
end

local function flash(vm, pos: Vector3, color: Color3, bright: number, range: number, dur: number)
	local body, s = ctx(vm)
	if not body then
		return
	end
	local a = attach(body, s, pos)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = bright * FXL
	l.Range = math.max(2, range * s * 1.3)
	l.Shadows = false
	l.Parent = a
	TweenService:Create(l, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
end

-- aura flare: lowers the kit Highlight fill and lifts its lights for a moment (SkinKits pulse loop)
local function boost(vm, amt: number, dur: number)
	vm._ib = vm._ib or {}
	table.insert(vm._ib, { t0 = os.clock(), a = amt * 1.6, d = dur * 1.2 })
	if vm._ibCon then
		return
	end
	vm._ibCon = RunService.RenderStepped:Connect(function()
		local now, v = os.clock(), 0
		for i = #vm._ib, 1, -1 do
			local b = vm._ib[i]
			local x = (now - b.t0) / b.d
			if x >= 1 then
				table.remove(vm._ib, i)
			else
				v += b.a * (if x < 0.1 then x / 0.1 else (1 - (x - 0.1) / 0.9) ^ 1.5)
			end
		end
		v = math.min(v, 1.6)
		local done = #vm._ib == 0
		for _, o in CollectionService:GetTagged("VantageSkinPulse") do
			if vm.Root and o:IsDescendantOf(vm.Root) then
				o:SetAttribute("InspectBoost", if done or v < 0.002 then nil else v)
			end
		end
		if done then
			vm._ibCon:Disconnect()
			vm._ibCon = nil
		end
	end)
end

-- a neon ring around the barrel axis at pos, growing r0 -> r1 (kit units, diameter) and fading
local ringN = 0
local function ring(vm, pos: Vector3, color: Color3, dur: number, r0: number, r1: number, plane: CFrame?)
	local body, s = ctx(vm)
	if not body or not RING then
		return
	end
	r0, r1 = r0 * FXR, r1 * FXR
	local p = RING:Clone()
	for _, c in p:GetChildren() do
		c:Destroy()
	end
	for name in p:GetAttributes() do
		p:SetAttribute(name, nil)
	end
	p.Name = "InspectRing"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	pcall(function()
		(p :: any).TextureID = ""
	end)
	local sz = RING.Size
	local thin = if sz.X <= sz.Y and sz.X <= sz.Z then "X" elseif sz.Y <= sz.Z then "Y" else "Z"
	local rot = if thin == "X" then CFrame.Angles(0, math.rad(90), 0) elseif thin == "Y" then CFrame.Angles(math.rad(90), 0, 0) else CFrame.identity
	local big = math.max(sz.X, sz.Y, sz.Z)
	local t0 = os.clock()
	ringN += 1
	local bind = "VantageInspectRing" .. ringN
	local function place(x)
		local d = (r0 + (r1 - r0) * (1 - (1 - x) ^ 2)) * s
		p.Size = sz * (d / big)
		p.Transparency = 0.15 + 0.85 * x * x
		p.CFrame = body.CFrame * CFrame.new(pos * s) * (plane or CFrame.identity) * rot
	end
	place(0)
	p.Parent = vm.Root
	Debris:AddItem(p, dur + 0.25) -- safety: never outlives the effect
	RunService:BindToRenderStep(bind, Enum.RenderPriority.Camera.Value + 20, function()
		local x = (os.clock() - t0) / dur
		if x >= 1 or not body.Parent or vm.Hidden then
			RunService:UnbindFromRenderStep(bind)
			p:Destroy()
			return
		end
		place(x)
	end)
end

local function later(dt: number, f)
	task.delay(dt, f)
end

local function seq(c0: Color3, c1: Color3)
	return ColorSequence.new(c0, c1)
end

local FX = {}

-- Glacier Ops
local ICE, FROST, ICEW = rgb(150, 210, 255), rgb(205, 238, 255), rgb(235, 250, 255)
FX.Frost = function(vm)
	burst(vm, { Pos = V(0.16, 0.12, -0.75), Dir = V(1, 0.3, 0), Spread = 40, Tex = "Smoke", Color = FROST, N = 12, Size = 0.1, SizeEnd = 0.32, Speed = 0.6, Life = 0.9, T0 = 0.55, Emit = 0.5, Bright = 1.4 })
	burst(vm, { Pos = V(0.14, 0.12, -0.75), Color = ICEW, N = 12, Size = 0.045, Speed = 0.9, Life = 0.55 })
	flash(vm, V(0.25, 0.15, -0.75), ICE, 3, 7, 0.6)
end
FX.FrostSlide = function(vm)
	for i = 0, 5 do
		later(i * 0.07, function()
			local z = -1.1 - i * 0.25
			burst(vm, { Pos = V(0, 0.2, z), Color = ICEW, N = 5, Size = 0.04, Speed = 0.4, Life = 0.55, Accel = V(0, -2, 0) })
			burst(vm, { Pos = V(0, 0.18, z), Tex = "Smoke", Color = FROST, N = 2, Size = 0.09, SizeEnd = 0.24, Speed = 0.25, Life = 0.75, T0 = 0.6, Emit = 0.5, Bright = 1.2 })
		end)
	end
	flash(vm, V(0, 0.25, -1.6), ICE, 2.2, 6, 0.7)
end
FX.Shards = function(vm)
	burst(vm, { Pos = V(0, 0.12, -1.4), Color = seq(ICEW, ICE), N = 20, Size = 0.07, SizeEnd = 0.02, Speed = 1.3, Life = 0.7, Accel = V(0, -7, 0), Drag = 1 })
	flash(vm, V(0, 0.2, -1.4), ICE, 3.5, 7, 0.4)
end

-- Archangel
local GOLD, GOLDW, GEM = rgb(255, 214, 120), rgb(255, 245, 210), rgb(120, 190, 255)
local function feathers(vm, n)
	for _, x in { -0.28, 0.28 } do
		burst(vm, { Pos = V(x, 0.36, 0.7), Dir = V(math.sign(x), 0.4, 0.3), Spread = 70, Color = seq(GOLDW, GOLD), N = n, Size = 0.08, SizeEnd = 0.03, Speed = 1.1, Life = 1.0, Accel = V(0, -0.8, 0), Drag = 3, Bright = 1.6 })
	end
end
FX.HaloBurst = function(vm)
	boost(vm, 1.2, 0.9)
	ring(vm, V(0, 0.108, -2.76), GOLD, 0.5, 0.35, 1.4)
	flash(vm, V(0.19, 0.064, -0.01), GEM, 5, 6, 0.6)
	flash(vm, V(0, 0.15, -2.6), GOLD, 4, 8, 0.7)
	burst(vm, { Pos = V(0.19, 0.064, -0.01), Color = seq(rgb(220, 240, 255), GEM), N = 14, Size = 0.06, Speed = 1.4, Life = 0.45 })
	burst(vm, { Pos = V(-0.19, 0.064, -0.01), Color = seq(rgb(220, 240, 255), GEM), N = 14, Size = 0.06, Speed = 1.4, Life = 0.45 })
	feathers(vm, 10)
end
FX.Feathers = function(vm)
	feathers(vm, 4)
	burst(vm, { Pos = V(0, 0.108, -2.76), Color = GOLDW, N = 8, Size = 0.04, Speed = 0.8, Life = 0.5 })
end

-- Molten Sovereign
local LAVA, EMBER, HOT = rgb(255, 120, 30), rgb(255, 70, 20), rgb(255, 210, 120)
FX.MawFire = function(vm)
	burst(vm, { Pos = V(0, 0.09, -2.7), Dir = V(0, 0.15, -1), Spread = 25, Tex = "Fire", Color = seq(HOT, EMBER), N = 9, Size = 0.14, SizeEnd = 0.02, Speed = 0.9, Life = 0.4, Bright = 2.5 })
	flash(vm, V(0, 0.09, -2.6), LAVA, 3, 7, 0.4)
end
FX.LavaPulse = function(vm)
	boost(vm, 1.4, 0.8)
	ring(vm, V(0, 0.09, -2.6), LAVA, 0.35, 0.2, 0.8)
	for i = 0, 4 do
		later(i * 0.04, function()
			burst(vm, { Pos = V(0, 0.08, -2.4 + i * 0.5), Color = seq(HOT, EMBER), N = 6, Size = 0.045, Speed = 1.1, Life = 0.45, Accel = V(0, -1.5, 0) })
			flash(vm, V(0, 0.08, -2.4 + i * 0.5), LAVA, 2.5, 5, 0.35)
		end)
	end
	burst(vm, { Pos = V(0, 0.09, -2.7), Dir = V(0, 0, -1), Spread = 35, Tex = "Fire", Color = seq(HOT, EMBER), N = 16, Size = 0.18, SizeEnd = 0.03, Speed = 1.4, Life = 0.45, Bright = 3 })
end
FX.Burn = function(vm)
	burst(vm, { Pos = V(0, -0.06, -1.3), Tex = "Smoke", Color = rgb(90, 80, 75), N = 6, Size = 0.08, SizeEnd = 0.25, Speed = 0.4, Life = 0.7, T0 = 0.5, Emit = 0, Bright = 1 })
	burst(vm, { Pos = V(0, -0.06, -1.3), Color = seq(HOT, EMBER), N = 8, Size = 0.03, Speed = 1.2, Life = 0.35 })
end

-- Event Horizon
local VIO, PINK, VIOW = rgb(170, 80, 255), rgb(255, 110, 220), rgb(225, 190, 255)
FX.Vortex = function(vm)
	for _, side in { -1, 1 } do
		local c = V(0.21 * side, 0.041, -0.345)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			local off = V(0, math.cos(a), math.sin(a)) * 0.32
			burst(vm, { Pos = c + off, Dir = -off, Spread = 8, Color = seq(VIOW, VIO), N = 2, Size = 0.045, SizeEnd = 0.01, Speed = 0.85, Life = 0.36 })
		end
	end
	boost(vm, 0.4, 0.5)
end
FX.Collapse = function(vm)
	boost(vm, 1.5, 0.35)
	ring(vm, V(0, 0.041, -0.345), VIO, 0.14, 1.2, 0.1)
	flash(vm, V(0, 0.1, -0.345), VIO, 5, 7, 0.25)
end
FX.Release = function(vm)
	ring(vm, V(0, 0.041, -0.345), PINK, 0.45, 0.2, 1.6)
	later(0.06, function()
		ring(vm, V(0, 0.041, -0.345), VIO, 0.45, 0.15, 1.2)
	end)
	for _, side in { -1, 1 } do
		burst(vm, { Pos = V(0.21 * side, 0.041, -0.345), Color = seq(VIOW, PINK), N = 16, Size = 0.05, Speed = 2.4, Life = 0.4, Drag = 4 })
	end
	flash(vm, V(0, 0.1, -0.345), PINK, 5, 8, 0.5)
	boost(vm, 1, 0.6)
end

-- Kitsune // Lunar Festival
local FOX, FOXW, FOXD = rgb(90, 200, 255), rgb(215, 245, 255), rgb(40, 110, 255)
FX.Foxfire = function(vm)
	for _, z in { -1.6, -2.0, -2.35 } do
		burst(vm, { Pos = V(0, 0.2, z), Dir = V(0, 1, 0), Spread = 20, Tex = "Fire", Color = seq(FOXW, FOXD), N = 4, Size = 0.1, SizeEnd = 0.01, Speed = 0.5, Life = 0.5, Bright = 2.2 })
	end
	flash(vm, V(0, 0.25, -2.0), FOX, 2.5, 6, 0.5)
end
FX.Bell = function(vm)
	boost(vm, 1.2, 0.8)
	ring(vm, V(-0.048, -0.2, 1.76), FOXW, 0.4, 0.1, 0.7)
	flash(vm, V(-0.048, -0.2, 1.76), FOXW, 5, 6, 0.5)
	burst(vm, { Pos = V(-0.048, -0.2, 1.76), Color = seq(FOXW, FOX), N = 12, Size = 0.04, Speed = 1.3, Life = 0.45 })
	burst(vm, { Pos = V(0, 0.2, -2.0), Dir = V(0, 1, 0), Spread = 60, Tex = "Fire", Color = seq(FOXW, FOXD), N = 14, Size = 0.13, SizeEnd = 0.01, Speed = 0.9, Life = 0.55, Bright = 2.6 })
	flash(vm, V(0, 0.25, -2.0), FOX, 4, 7, 0.6)
end

-- Golden Dragon Emperor
local DGOLD, DGOLDW, CRIM, DFIRE = rgb(255, 200, 80), rgb(255, 240, 190), rgb(220, 30, 40), rgb(255, 130, 40)
FX.TailFire = function(vm)
	burst(vm, { Pos = V(0, 0.34, 1.53), Dir = V(0, 1, 0.3), Spread = 30, Tex = "Fire", Color = seq(DGOLDW, DFIRE), N = 7, Size = 0.12, SizeEnd = 0.01, Speed = 0.6, Life = 0.45, Bright = 2.4 })
	flash(vm, V(0, 0.4, 1.5), DFIRE, 2.5, 5, 0.4)
end
FX.MawGlow = function(vm)
	burst(vm, { Pos = V(0, 0.09, -2.7), Dir = V(0, 0.1, -1), Spread = 20, Tex = "Fire", Color = seq(DGOLDW, DFIRE), N = 4, Size = 0.08, SizeEnd = 0.01, Speed = 0.4, Life = 0.35 })
	flash(vm, V(0, 0.09, -2.6), DFIRE, 2.5, 6, 0.35)
	boost(vm, 0.35, 0.4)
end
FX.MawFire = FX.MawFire -- shared with Molten (orange maw fire)
FX.RollSparks = function(vm)
	for _, z in { -2.2, -1.2, -0.2, 0.8 } do
		burst(vm, { Pos = V(0, 0.22, z), Color = seq(DGOLDW, DGOLD), N = 5, Size = 0.04, Speed = 1.4, Life = 0.4, Drag = 2 })
	end
	boost(vm, 0.5, 0.35)
end
FX.Roar = function(vm)
	boost(vm, 1.6, 1.0)
	ring(vm, V(0, 0.09, -2.75), DGOLD, 0.55, 0.3, 1.5)
	later(0.08, function()
		ring(vm, V(0, 0.09, -2.75), CRIM, 0.5, 0.25, 1.1)
	end)
	burst(vm, { Pos = V(0, 0.09, -2.75), Dir = V(0, 0, -1), Spread = 30, Tex = "Fire", Color = seq(DGOLDW, CRIM), N = 20, Size = 0.2, SizeEnd = 0.03, Speed = 1.6, Life = 0.5, Bright = 3 })
	burst(vm, { Pos = V(0, 0.15, -1.6), Color = seq(DGOLDW, DGOLD), N = 26, Size = 0.05, Speed = 2.4, Life = 0.45, Drag = 4 })
	flash(vm, V(0, 0.15, -2.5), DGOLD, 7, 10, 0.8)
end

-- ─── v3 flight FX: trails are world-space (unlocked) so they streak behind the flying gun ─────────
local function trail(vm, pts, o)
	for _, p in pts do
		local q = table.clone(o)
		q.Pos = p
		q.Locked = false
		burst(vm, q)
	end
end
local MUZ, STOCK = V(0, 0.1, -2.7), V(0, 0.1, 1.4)
FX.FrostTrail = function(vm)
	trail(vm, { MUZ, STOCK }, { Color = seq(ICEW, ICE), N = 6, Size = 0.07, SizeEnd = 0.01, Speed = 0.15, Life = 0.6, Accel = V(0, -1.5, 0) })
	trail(vm, { MUZ, STOCK }, { Tex = "Smoke", Color = FROST, N = 2, Size = 0.12, SizeEnd = 0.3, Speed = 0.1, Life = 0.7, T0 = 0.55, Emit = 0.5, Bright = 1.2 })
end
FX.HaloLand = function(vm)
	ring(vm, V(0, 0.108, -0.6), GOLD, 0.45, 0.4, 1.6)
	flash(vm, V(0, 0.2, -0.6), GOLD, 4, 8, 0.5)
	feathers(vm, 6)
	boost(vm, 0.9, 0.6)
end
FX.Sizzle = function(vm)
	burst(vm, { Pos = V(0, -0.08, 0.2), Tex = "Smoke", Color = rgb(110, 95, 85), N = 4, Size = 0.07, SizeEnd = 0.22, Speed = 0.4, Life = 0.6, T0 = 0.5, Emit = 0, Bright = 1 })
	burst(vm, { Pos = V(0, -0.06, -1.2), Color = seq(HOT, EMBER), N = 6, Size = 0.035, Speed = 1.3, Life = 0.35 })
	flash(vm, V(0, 0.05, -0.8), LAVA, 2.2, 5, 0.25)
	boost(vm, 0.5, 0.3)
end
FX.EmberTrail = function(vm)
	trail(vm, { MUZ, V(0, 0.08, -1.2), STOCK }, { Tex = "Fire", Color = seq(HOT, EMBER), N = 4, Size = 0.12, SizeEnd = 0.01, Speed = 0.2, Life = 0.45, Bright = 2.5 })
end
FX.VoidTrail = function(vm)
	trail(vm, { MUZ, V(0, 0.041, -0.345), STOCK }, { Color = seq(VIOW, VIO), N = 5, Size = 0.06, SizeEnd = 0.01, Speed = 0.12, Life = 0.55 })
	trail(vm, { V(0, 0.041, -0.345) }, { Tex = "Smoke", Color = rgb(40, 10, 70), N = 2, Size = 0.15, SizeEnd = 0.35, Speed = 0.05, Life = 0.6, T0 = 0.4, Emit = 0.2, Bright = 1 })
end
FX.FoxTrail = function(vm)
	trail(vm, { MUZ, STOCK }, { Tex = "Fire", Color = seq(FOXW, FOXD), N = 4, Size = 0.12, SizeEnd = 0.01, Speed = 0.2, Life = 0.45, Bright = 2.4 })
end
FX.DragonLaunch = function(vm)
	burst(vm, { Pos = V(0, 0.1, -0.6), Tex = "Fire", Color = seq(DGOLDW, DFIRE), N = 14, Size = 0.18, SizeEnd = 0.02, Speed = 1.2, Life = 0.4, Bright = 3 })
	ring(vm, V(0, 0.1, -0.6), DGOLD, 0.4, 0.4, 1.6)
	flash(vm, V(0, 0.2, -0.6), DFIRE, 5, 9, 0.5)
	boost(vm, 1, 0.5)
end
FX.FireTrail = function(vm)
	trail(vm, { MUZ, V(0, 0.15, -1.0), STOCK }, { Tex = "Fire", Color = seq(DGOLDW, DFIRE), N = 5, Size = 0.15, SizeEnd = 0.01, Speed = 0.2, Life = 0.5, Bright = 2.8 })
	trail(vm, { MUZ, STOCK }, { Color = seq(DGOLDW, DGOLD), N = 5, Size = 0.04, Speed = 0.5, Life = 0.5 })
end
FX.Impact = function(vm)
	boost(vm, 1.4, 0.7)
	ring(vm, V(0, 0.1, -0.6), DGOLD, 0.45, 0.5, 2.0)
	later(0.06, function()
		ring(vm, V(0, 0.1, -0.6), CRIM, 0.4, 0.4, 1.5)
	end)
	burst(vm, { Pos = V(0, 0.15, -0.8), Color = seq(DGOLDW, DGOLD), N = 22, Size = 0.05, Speed = 2.6, Life = 0.4, Drag = 4 })
	flash(vm, V(0, 0.2, -0.8), DGOLD, 6, 9, 0.6)
end

-- ─── Sentinel FX helpers ───────────────────────────────────────────────────────────────────────────
local tempLive: { Instance } = {}
local SMUZ, SSTOCK = V(0, 0.108, -2.45), V(0, 0.1, 1.4)

-- scope glint at the ADS point (marksman beat)
local function glint(vm, color: Color3)
	local body, s = ctx(vm)
	if not body or not vm.SightLocal then
		return
	end
	local kp = vm.SightLocal.Position / s
	burst(vm, { Pos = kp, Color = seq(rgb(255, 255, 255), color), N = 6, Size = 0.1, Speed = 0.25, Life = 0.35 })
	flash(vm, kp, color, 4, 4, 0.35)
end

-- jagged lightning bolt from above the view down onto pos (world space, brief)
local function bolt(vm, pos: Vector3, color: Color3)
	local body, s = ctx(vm)
	if not body then
		return
	end
	local target = body.CFrame:PointToWorldSpace(pos * s)
	local cf = workspace.CurrentCamera.CFrame
	local start = target + cf.UpVector * 6 + cf.RightVector * (math.random() - 0.5) * 2 + cf.LookVector * 1.5
	local pts = { start }
	local n = 9
	for i = 1, n - 1 do
		local a = i / n
		local j = (1 - a) * 0.55 + 0.08
		table.insert(pts, start:Lerp(target, a) + Vector3.new((math.random() - 0.5) * j, (math.random() - 0.5) * j * 0.3, (math.random() - 0.5) * j))
	end
	table.insert(pts, target)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local seg = Instance.new("Part")
		seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
		seg.Material = Enum.Material.Neon
		seg.Color = color
		local len = (b - a).Magnitude
		seg.Size = Vector3.new(0.05, 0.05, len)
		seg.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
		seg.Parent = vm.Root
		TweenService:Create(seg, TweenInfo.new(0.22), { Transparency = 1 }):Play()
		Debris:AddItem(seg, 0.25)
	end
end

-- gyroscope rings orbiting the gun for dur (specs: { color, diameter (kit), axis, rad/s })
local function orbit(vm, pos: Vector3, dur: number, specs)
	local body, s = ctx(vm)
	if not body or not RING then
		return
	end
	local sz = RING.Size
	local big = math.max(sz.X, sz.Y, sz.Z)
	local parts = {}
	for i, sp in specs do
		local p = RING:Clone()
		for _, c in p:GetChildren() do
			c:Destroy()
		end
		for nm in p:GetAttributes() do
			p:SetAttribute(nm, nil)
		end
		p.Name = "InspectRing"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = sp[1]
		pcall(function()
			(p :: any).TextureID = ""
		end)
		p.Size = sz * (sp[2] * s / big)
		p.Transparency = 1
		p.Parent = vm.Root
		Debris:AddItem(p, dur + 0.5)
		table.insert(tempLive, p)
		parts[i] = p
	end
	local t0 = os.clock()
	ringN += 1
	local bind = "VantageInspectOrbit" .. ringN
	RunService:BindToRenderStep(bind, Enum.RenderPriority.Camera.Value + 20, function()
		local t = os.clock() - t0
		local x = t / dur
		if x >= 1 or not body.Parent or vm.Hidden or not parts[1].Parent then
			RunService:UnbindFromRenderStep(bind)
			for _, p in parts do
				p:Destroy()
			end
			return
		end
		local fade = math.min(1, x / 0.12, (1 - x) / 0.08)
		local base = body.CFrame * CFrame.new(pos * s)
		for i, sp in specs do
			parts[i].Transparency = 1 - 0.85 * fade
			parts[i].CFrame = base * CFrame.fromAxisAngle(sp[3].Unit, t * sp[4]) * (sp[5] or CFrame.identity)
		end
	end)
end

-- a kit piece shown only during the inspect (Phoenix wings are destroyed in first person): grows in, beats, folds
local function tempPiece(vm, folder: string, name: string, dur: number, pivot: Vector3, beatDeg: number)
	local body, s = ctx(vm)
	if not body then
		return
	end
	local meshes = ReplicatedStorage.Vantage.Weapons:FindFirstChild("SkinKitMeshes")
	local fold = meshes and meshes:FindFirstChild(folder)
	local t = fold and fold:FindFirstChild(name)
	local rcf = t and t:GetAttribute("RootCF")
	if not t or typeof(rcf) ~= "CFrame" then
		return
	end
	local p = t:Clone()
	for nm in p:GetAttributes() do
		p:SetAttribute(nm, nil)
	end
	for _, c in p:GetChildren() do
		if not c:IsA("SurfaceAppearance") then
			c:Destroy()
		end
	end
	p.Name = "InspectPiece"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	local full = t.Size * s
	local off = rcf.Rotation + rcf.Position * s
	local piv = CFrame.new(pivot * s)
	p.Size = full * 0.05
	p.Parent = vm.Root
	table.insert(tempLive, p)
	Debris:AddItem(p, dur + 0.5)
	local t0 = os.clock()
	ringN += 1
	local bind = "VantageInspectPiece" .. ringN
	RunService:BindToRenderStep(bind, Enum.RenderPriority.Camera.Value + 20, function()
		local tt = os.clock() - t0
		if tt >= dur or not body.Parent or not p.Parent then
			RunService:UnbindFromRenderStep(bind)
			p:Destroy()
			return
		end
		local e = math.min(1, tt / 0.22, (dur - tt) / 0.22)
		e = e * e * (3 - 2 * e)
		p.Size = full * math.max(0.05, e)
		p.LocalTransparencyModifier = if vm.Hidden then 1 else 0
		local beat = math.rad(beatDeg) * math.sin(tt * math.pi * 2 * 2.4) * e
		p.CFrame = body.CFrame * piv * CFrame.Angles(beat, 0, 0) * piv:Inverse() * off
	end)
end

-- hide the gun for a moment (inside the Phoenix fireball)
local function hideGun(vm, dur: number)
	if vm.Hidden then
		return
	end
	local list = {}
	for _, p in vm.GunParts or {} do
		table.insert(list, p)
	end
	for _, p in vm.MagParts or {} do
		table.insert(list, p)
	end
	for _, p in list do
		p.LocalTransparencyModifier = 1
	end
	task.delay(dur, function()
		if not vm.Hidden then
			for _, p in list do
				if p.Parent then
					p.LocalTransparencyModifier = 0
				end
			end
		end
	end)
end

FX.Glint = function(vm)
	glint(vm, rgb(235, 245, 255))
end

-- Storm Herald
local STORM, STORMW = rgb(110, 180, 255), rgb(225, 240, 255)
FX.StormCharge = function(vm)
	for _, z in { -2.2, -1.4, -0.6, 0.2 } do
		burst(vm, { Pos = V((math.random() - 0.5) * 0.15, 0.16, z), Color = seq(STORMW, STORM), N = 4, Size = 0.04, Speed = 1.6, Life = 0.18, Drag = 6 })
	end
	flash(vm, V(0, 0.2, -1.2), STORM, 3, 5, 0.15)
	boost(vm, 0.4, 0.3)
end
FX.Lightning = function(vm)
	bolt(vm, V(0, 0.2, -0.6), STORMW)
	later(0.05, function()
		bolt(vm, V(0, 0.2, -1.4), STORM)
	end)
	flash(vm, V(0, 0.3, -0.6), STORMW, 8, 10, 0.4)
	ring(vm, V(0, 0.1, -0.6), STORM, 0.4, 0.4, 2.0)
	burst(vm, { Pos = V(0, 0.15, -0.6), Color = seq(STORMW, STORM), N = 26, Size = 0.05, Speed = 3, Life = 0.35, Drag = 5 })
	boost(vm, 1.6, 0.7)
end
FX.StormSpark = function(vm)
	trail(vm, { SMUZ, SSTOCK }, { Color = seq(STORMW, STORM), N = 4, Size = 0.04, Speed = 0.6, Life = 0.3 })
	flash(vm, V(0, 0.2, -0.6), STORM, 2, 4, 0.15)
end
FX.StormCatch = function(vm)
	burst(vm, { Pos = V(0, 0.1, -0.6), Color = seq(STORMW, STORM), N = 18, Size = 0.04, Speed = 2.4, Life = 0.3, Drag = 5 })
	flash(vm, V(0, 0.2, -0.6), STORM, 5, 6, 0.35)
	boost(vm, 0.8, 0.5)
end

-- Abyssal Leviathan
local TEAL, TEALW, DEEP = rgb(40, 230, 210), rgb(200, 255, 250), rgb(20, 110, 170)
local function bubbles(vm, pts, n)
	for _, p in pts do
		burst(vm, { Pos = p, Color = seq(TEALW, TEAL), N = n, Size = 0.05, SizeEnd = 0.08, Speed = 0.3, Life = 0.85, Accel = V(0, 1.2, 0), T0 = 0.3, Emit = 0.6, Bright = 1.5 })
	end
end
FX.Bubbles = function(vm)
	bubbles(vm, { V(0, 0.15, -2.0), V(0, 0.15, -1.0), V(0, 0.15, 0.2) }, 3)
end
FX.Lure = function(vm)
	flash(vm, V(0, 0.6, -1.55), TEALW, 4, 5, 0.6)
	burst(vm, { Pos = V(0, 0.6, -1.55), Color = seq(TEALW, TEAL), N = 8, Size = 0.04, Speed = 0.6, Life = 0.5 })
	boost(vm, 0.6, 0.6)
end
FX.Bite = function(vm)
	ring(vm, V(0, -0.1, -2.1), TEAL, 0.3, 0.2, 1.1)
	burst(vm, { Pos = V(0, -0.05, -2.2), Color = seq(TEALW, TEAL), N = 18, Size = 0.04, Speed = 2.4, Life = 0.3, Drag = 4 })
	flash(vm, V(0, 0, -2.1), TEAL, 5, 6, 0.35)
	boost(vm, 1, 0.4)
end
FX.BubbleTrail = function(vm)
	trail(vm, { SMUZ, V(0, 0.1, -0.6), SSTOCK }, { Color = seq(TEALW, TEAL), N = 4, Size = 0.05, SizeEnd = 0.09, Speed = 0.2, Life = 0.6, Accel = V(0, 1, 0), T0 = 0.3, Emit = 0.6 })
end
FX.Splash = function(vm)
	burst(vm, { Pos = V(0, 0.1, -0.8), Color = seq(TEALW, TEAL), N = 26, Size = 0.05, Speed = 2.2, Life = 0.5, Accel = V(0, -6, 0), Drag = 1 })
	ring(vm, V(0, 0.1, -0.8), DEEP, 0.4, 0.3, 1.6)
	flash(vm, V(0, 0.2, -0.8), TEAL, 4, 6, 0.4)
	boost(vm, 1, 0.5)
end
FX.TankGlow = function(vm)
	flash(vm, V(0, -0.445, -0.33), TEAL, 5, 5, 0.7)
	bubbles(vm, { V(0, -0.3, -0.33) }, 6)
	boost(vm, 0.8, 0.7)
end

-- Celestial Astrolabe
local CGOLD, CBLUE, CWHITE = rgb(255, 214, 120), rgb(140, 170, 255), rgb(255, 250, 235)
FX.StarMotes = function(vm)
	burst(vm, { Pos = V(0, 0.15, -0.4), Color = seq(CWHITE, CBLUE), N = 10, Size = 0.045, Speed = 0.9, Life = 0.7, Drag = 2 })
	burst(vm, { Pos = V(0, 0.15, -1.2), Color = seq(CWHITE, CGOLD), N = 6, Size = 0.04, Speed = 0.7, Life = 0.7, Drag = 2 })
end
FX.Orrery = function(vm)
	orbit(vm, V(0, 0.11, -0.6), 2.05, {
		{ CGOLD, 2.2, V(0, 0, 1), 3.2 },
		{ CBLUE, 2.7, V(1, 0, 0), -2.6 },
		{ CWHITE, 3.2, V(0.3, 1, 0), 2.0 },
	})
	boost(vm, 0.5, 0.6)
end
FX.Constellation = function(vm)
	for i = 1, 6 do
		local a = math.random() * math.pi * 2
		local p = V(math.cos(a) * 0.6, 0.15 + math.sin(a) * 0.5, -0.6 + (math.random() - 0.5) * 1.6)
		burst(vm, { Pos = p, Color = seq(CWHITE, CBLUE), N = 2, Size = 0.07, Speed = 0.05, Life = 0.6 })
	end
end
FX.SunFlare = function(vm)
	flash(vm, V(0, 0.15, -0.35), CGOLD, 8, 10, 0.7)
	ring(vm, V(0, 0.11, -0.6), CGOLD, 0.5, 0.4, 2.2)
	later(0.06, function()
		ring(vm, V(0, 0.11, -0.6), CBLUE, 0.45, 0.3, 1.6)
	end)
	burst(vm, { Pos = V(0, 0.15, -0.6), Color = seq(CWHITE, CGOLD), N = 24, Size = 0.05, Speed = 2.4, Life = 0.4, Drag = 4 })
	boost(vm, 1.6, 0.8)
end

-- Sakura Ronin
local PINK, PINKW, CRIMS = rgb(255, 120, 170), rgb(255, 215, 230), rgb(220, 40, 80)
FX.Petals = function(vm)
	burst(vm, { Pos = V(0, 0.25, -0.6), Color = seq(PINKW, PINK), N = 8, Size = 0.07, SizeEnd = 0.05, Speed = 0.5, Life = 1.4, Accel = V(0, -0.8, 0), Drag = 2, Locked = false, Emit = 0.4, Bright = 1.4 })
end
FX.Draw = function(vm)
	for i = 0, 5 do
		later(i * 0.08, function()
			burst(vm, { Pos = V(0, 0.15, 1.2 - i * 0.65), Color = seq(PINKW, PINK), N = 3, Size = 0.05, Speed = 0.4, Life = 0.35 })
		end)
	end
	flash(vm, V(0, 0.2, -0.6), PINK, 2.5, 6, 0.6)
end
FX.Slash = function(vm)
	local plane = CFrame.Angles(math.rad(90), 0, 0)
	ring(vm, V(0, 0.1, -0.6), PINK, 0.3, 0.6, 3.0, plane)
	later(0.04, function()
		ring(vm, V(0, 0.1, -0.6), CRIMS, 0.28, 0.5, 2.4, plane)
	end)
	burst(vm, { Pos = V(0, 0.2, -0.6), Color = seq(PINKW, PINK), N = 20, Size = 0.07, SizeEnd = 0.05, Speed = 2, Life = 1.2, Accel = V(0, -1, 0), Drag = 3, Locked = false, Emit = 0.4, Bright = 1.4 })
	flash(vm, V(0, 0.2, -0.6), PINK, 5, 7, 0.4)
	boost(vm, 1.2, 0.6)
end

-- Phoenix Ascendant
local PGOLD, PWHITE, PFIRE = rgb(255, 200, 90), rgb(255, 245, 220), rgb(255, 140, 40)
FX.WhiteHot = function(vm)
	boost(vm, 0.8, 0.5)
	flash(vm, V(0, 0.33, -0.1), PWHITE, 4, 6, 0.5)
	for _, z in { -1.6, -0.6, 0.4 } do
		burst(vm, { Pos = V(0, 0.15, z), Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 3, Size = 0.08, SizeEnd = 0.01, Speed = 0.3, Life = 0.35 })
	end
end
FX.PhoenixLaunch = function(vm)
	burst(vm, { Pos = V(0, 0.1, -0.4), Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 16, Size = 0.2, SizeEnd = 0.02, Speed = 1.2, Life = 0.4, Bright = 3 })
	ring(vm, V(0, 0.1, -0.4), PGOLD, 0.4, 0.4, 1.8)
	flash(vm, V(0, 0.2, -0.4), PFIRE, 5, 9, 0.5)
end
FX.FireTrailP = function(vm)
	trail(vm, { SMUZ, V(0, 0.15, -0.6), SSTOCK }, { Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 5, Size = 0.15, SizeEnd = 0.01, Speed = 0.2, Life = 0.5, Bright = 2.8 })
end
FX.Fireball = function(vm)
	hideGun(vm, 0.25)
	burst(vm, { Pos = V(0, 0.1, -0.4), Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 40, Size = 0.5, SizeEnd = 0.1, Speed = 1.2, Life = 0.5, Bright = 3, Locked = false })
	burst(vm, { Pos = V(0, 0.1, -0.4), Color = seq(PWHITE, PGOLD), N = 30, Size = 0.05, Speed = 3, Life = 0.45, Drag = 4, Locked = false })
	ring(vm, V(0, 0.1, -0.4), PFIRE, 0.35, 0.4, 2.4)
	flash(vm, V(0, 0.2, -0.4), PFIRE, 9, 12, 0.6)
	boost(vm, 1.6, 0.6)
end
FX.PhoenixWings = function(vm)
	tempPiece(vm, "Phoenix_Sentinel", "Wings", 0.8, V(0.015, 0.42, 0.9), 18)
	for _, x in { -0.4, 0.4 } do
		burst(vm, { Pos = V(x, 0.5, 0.9), Color = seq(PWHITE, PGOLD), N = 8, Size = 0.07, SizeEnd = 0.02, Speed = 1, Life = 0.6, Drag = 3 })
	end
end
FX.PhoenixTrail = function(vm)
	trail(vm, { SMUZ, V(0, 0.42, 0.9), SSTOCK }, { Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 5, Size = 0.16, SizeEnd = 0.01, Speed = 0.2, Life = 0.5, Bright = 2.8 })
	trail(vm, { SMUZ, SSTOCK }, { Color = seq(PWHITE, PGOLD), N = 4, Size = 0.04, Speed = 0.5, Life = 0.5 })
end
FX.PhoenixImpact = function(vm)
	ring(vm, V(0, 0.1, -0.6), PGOLD, 0.5, 0.5, 2.4)
	later(0.06, function()
		ring(vm, V(0, 0.1, -0.6), PWHITE, 0.45, 0.4, 1.8)
	end)
	burst(vm, { Pos = V(0, 0.15, -0.8), Color = seq(PWHITE, PGOLD), N = 26, Size = 0.05, Speed = 2.6, Life = 0.4, Drag = 4 })
	flash(vm, V(0, 0.2, -0.8), PGOLD, 7, 9, 0.6)
	boost(vm, 1.6, 0.8)
end
FX.PhoenixCry = function(vm)
	burst(vm, { Pos = V(0, 0.108, -2.55), Dir = V(0, 0, -1), Spread = 30, Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 22, Size = 0.22, SizeEnd = 0.03, Speed = 1.8, Life = 0.5, Bright = 3 })
	ring(vm, V(0, 0.108, -2.55), PGOLD, 0.45, 0.3, 1.6)
	flash(vm, V(0, 0.15, -2.4), PGOLD, 6, 8, 0.6)
	boost(vm, 1.4, 0.8)
end
FX.TailFireP = function(vm)
	burst(vm, { Pos = V(0.025, -0.3, 1.0), Dir = V(0, -0.3, 1), Spread = 30, Tex = "Fire", Color = seq(PWHITE, PFIRE), N = 7, Size = 0.12, SizeEnd = 0.01, Speed = 0.6, Life = 0.45, Bright = 2.4 })
end

-- ═══ PRESENTATION LAYER v5 (2026-11-15): AAA showcase benchmarks ══════════════════════════════════════
-- Camera that complements the gun (FOV push, look-follow, impulse shake; undone every frame), depth of field +
-- colour grade so the weapon is the centrepiece, ribbon light trails while airborne, layered particle impacts
-- with real textures, cinematic letterbox for Godly, activation and sealing sequences. Tier-scaled via clip.Pres.
local Players = game:GetService("Players")
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
-- Built-in client textures (proven to load 2026-11-15). The custom set in Downloads/fwjelaa/_vantage_vfx/
-- (vfx_glow, vfx_flare, vfx_streak, vfx_ring, vfx_arc, vfx_shard, vfx_ember, vfx_mist, vfx_sweep, vfx_trail) replaces
-- these one by one once imported: set SkinInspects.Tex.<key> = "rbxassetid://<id>".
-- (The older vfx_glow / vfx_ring / vfx_spark_streak / vfx_plasma uploads fail: "no asset content representation".)
local TEX2 = {
	glow = SPARK,
	ember = SPARK,
	flare = SPARK,
	shard = SPARK,
	streak = "rbxasset://textures/particles/fire_sparks_main.dds",
	ring = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	arc = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	plasma = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	mist = "rbxasset://textures/particles/smoke_main.dds",
	sweep = SPARK,
	fire = "rbxasset://textures/particles/fire_main.dds",
	trail = "",
}
local FLIP = {}
SkinInspects.Tex = TEX2
local live2: { ParticleEmitter } = {}

local function nseq(a: number, b: number?, c: number?)
	if c == nil then
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or 0) })
	end
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(0.25, b :: number), NumberSequenceKeypoint.new(1, c) })
end

-- one designed particle layer, attached to the gun body (kit Root-space position)
local function emit(vm, o)
	local body, s = ctx(vm)
	if not body then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "InspectFX2"
	local p = o.Pos * s
	att.CFrame = if o.Dir then CFrame.lookAt(p, p + o.Dir) else CFrame.new(p)
	att.Parent = body
	local e = Instance.new("ParticleEmitter")
	local key = o.Tex or "glow"
	e.Texture = TEX2[key] or SPARK
	if FLIP[key] then
		e.FlipbookLayout = FLIP[key]
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	e.Color = if typeof(o.Color) == "Color3" then ColorSequence.new(o.Color) else o.Color
	e.LightEmission = o.Emit or 1
	e.LightInfluence = 0
	e.Brightness = o.Bright or 2
	local sz = o.Size or 0.2
	if type(sz) == "table" then
		e.Size = nseq(sz[1] * s, sz[2] * s, if sz[3] then sz[3] * s else nil)
	else
		e.Size = nseq(sz * s, 0)
	end
	local T = o.T or { 0, 1 }
	e.Transparency = if #T == 3
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, T[1]), NumberSequenceKeypoint.new(0.2, T[2]), NumberSequenceKeypoint.new(1, T[3]) })
		else NumberSequence.new(T[1], T[2])
	local life = o.Life or 0.5
	e.Lifetime = NumberRange.new(life * (o.LifeMin or 0.7), life)
	local sp = (o.Speed or 0) * s
	e.Speed = NumberRange.new(sp * (o.SpeedMin or 0.5), sp)
	local spread = o.Spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = (o.Accel or Vector3.zero) * s
	e.Drag = o.Drag or 0
	e.Rotation = NumberRange.new(o.Rot0 or 0, o.Rot1 or 360)
	e.RotSpeed = NumberRange.new(-(o.Spin or 0), o.Spin or 0)
	e.EmissionDirection = Enum.NormalId.Front
	e.LockedToPart = o.Locked ~= false
	if o.Orient == "streak" then
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
	end
	e.ZOffset = o.Z or 0.5
	e.Rate = 0
	e.Parent = att
	table.insert(live2, e)
	if o.N then
		e:Emit(o.N)
	end
	if o.Rate then
		e.Rate = o.Rate
		task.delay(o.Dur or 0.5, function()
			e.Enabled = false
		end)
	end
	Debris:AddItem(att, (o.Dur or 0) + life + 0.6)
	return e
end
SkinInspects.Emit = emit

-- palettes: hot = white-hot core, mid = identity colour, dark = falloff / embers
local PAL = {
	Ice = { hot = rgb(240, 252, 255), mid = rgb(140, 205, 255), dark = rgb(50, 110, 200) },
	Void = { hot = rgb(255, 225, 255), mid = rgb(185, 90, 255), dark = rgb(80, 20, 150), alt = rgb(255, 110, 220) },
	Gold = { hot = rgb(255, 246, 215), mid = rgb(255, 190, 70), dark = rgb(210, 45, 30), alt = rgb(230, 30, 40) },
}

-- layered impact: core bloom -> star flare -> shockwave(s) -> streak sparks -> embers -> lingering mist
local function impact(vm, pos: Vector3, P, k: number, opts)
	opts = opts or {}
	emit(vm, { Pos = pos, Tex = "glow", Color = P.hot, N = 1, Size = { 0.7 * k, 1.3 * k, 0.2 * k }, Life = 0.22, LifeMin = 1, T = { 0.05, 1 }, Bright = 3, Z = 1 })
	emit(vm, { Pos = pos, Tex = "flare", Color = ColorSequence.new(P.hot, P.mid), N = 1, Size = { 1.0 * k, 1.8 * k, 0 }, Life = 0.38, LifeMin = 1, T = { 0, 0.05, 1 }, Spin = 40, Bright = 3, Z = 1.2 })
	emit(vm, { Pos = pos, Tex = "ring", Color = P.mid, N = 1, Size = { 0.2 * k, 2.6 * k }, Life = 0.42, LifeMin = 1, T = { 0.05, 1 }, Bright = 2.5, Z = 0.8 })
	if opts.ring2 then
		later(0.06, function()
			emit(vm, { Pos = pos, Tex = "ring", Color = opts.ring2, N = 1, Size = { 0.15 * k, 1.9 * k }, Life = 0.48, LifeMin = 1, T = { 0.15, 1 }, Bright = 2, Z = 0.7 })
		end)
	end
	emit(vm, { Pos = pos, Tex = "streak", Orient = "streak", Color = ColorSequence.new(P.hot, P.mid), N = math.floor(18 * k), Size = { 0.22 * k, 0.14 * k, 0 }, Life = 0.32, Speed = 5.5 * k, Drag = 7, Bright = 3, Locked = false })
	emit(vm, { Pos = pos, Tex = "ember", Color = ColorSequence.new(P.hot, P.dark), N = math.floor(14 * k), Size = { 0.07 * k, 0.05 * k, 0 }, Life = 0.9, Speed = 2.4 * k, Drag = 2, Accel = V(0, -3, 0), Locked = false })
	if opts.mist then
		emit(vm, { Pos = pos, Tex = "mist", Color = opts.mist, N = 3, Size = { 0.5 * k, 1.2 * k }, Life = 1.0, Speed = 0.35, Emit = 0.15, Bright = 1, T = { 0.65, 0.6, 1 }, Spin = 20, Z = 0.2 })
	end
end

-- end-of-inspect light sweep: a glint travelling muzzle -> stock along the gun
local function seal(vm, color: Color3, zFrom: number, zTo: number, y: number)
	emit(vm, { Pos = V(0, y, zFrom), Dir = V(0, 0, 1), Spread = 0, Tex = "glow", Color = color, N = 1, Size = { 0.35, 0.35, 0.2 }, Life = 0.32, LifeMin = 1, Speed = (zTo - zFrom) / 0.32, SpeedMin = 1, Bright = 3, Emit = 1, T = { 0.1, 0.05, 1 }, Z = 1.5 })
	later(0.3, function()
		emit(vm, { Pos = V(0, y, zTo), Tex = "flare", Color = color, N = 1, Size = { 0.4, 0.7, 0 }, Life = 0.3, LifeMin = 1, Spin = 60, Bright = 3, Z = 1.5 })
	end)
end

-- ─── presentation state: driven by WeaponController each frame (SkinInspects.Present) ───────────────
local target = { fov = 0, look = 0, grade = 0, desat = 0, bars = 0, dof = 0 }
local cur = { fov = 0, look = 0, grade = 0, desat = 0, bars = 0, dof = 0, shake = 0, flash = 0 }
local presClip, presVm, presTint, presRest = nil, nil, Color3.new(1, 1, 1), nil
local presGradeAmt, presDofAmt = 1, 1
local trails: { any } = {}

local function clearTrails()
	for _, t in trails do
		for _, i in t do
			if typeof(i) == "Instance" and i.Parent then
				i:Destroy()
			end
		end
	end
	table.clear(trails)
end

local function makeTrail(vm, spec)
	local body, s = ctx(vm)
	if not body then
		return
	end
	local w = spec.Width or 0.1
	local a0 = Instance.new("Attachment")
	a0.Name = "InspectTrail"
	a0.Position = (spec.Pos + V(0, w / 2, 0)) * s
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Name = "InspectTrail"
	a1.Position = (spec.Pos - V(0, w / 2, 0)) * s
	a1.Parent = body
	local t = Instance.new("Trail")
	t.Name = "InspectTrail"
	t.Attachment0, t.Attachment1 = a0, a1
	t.Texture = TEX2.trail
	t.TextureMode = Enum.TextureMode.Stretch
	t.Color = spec.Color
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.T0 or 0.1), NumberSequenceKeypoint.new(0.6, spec.T1 or 0.55), NumberSequenceKeypoint.new(1, 1) })
	t.Lifetime = spec.Life or 0.3
	t.LightEmission = spec.Emit or 1
	t.LightInfluence = 0
	t.Brightness = spec.Bright or 2
	t.FaceCamera = true
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	t.MinLength = 0.01
	t.Enabled = false
	t.Parent = body
	table.insert(trails, { t, a0, a1 })
end

local function flyMag(clip, t: number): number
	local keys = clip.Tracks and clip.Tracks.Fly
	if not keys then
		return 0
	end
	local p = sampleKeys(keys, t)
	local FB = clip.FlyBoost
	return p.Magnitude * (if FB and FB.P then FB.P else 1)
end

-- called every frame by WeaponController: clip = playing skin clip (or nil), t = clip time
function SkinInspects.Present(vm, clip, t: number)
	local P = clip and clip.Pres
	if P then
		if presClip ~= clip or presVm ~= vm then
			clearTrails()
			presClip, presVm = clip, vm
			presTint = P.Tint or Color3.new(1, 1, 1)
			presGradeAmt, presDofAmt = P.GradeAmt or 1, P.DofAmt or 1
			presRest = nil
			for _, spec in P.Trails or {} do
				makeTrail(vm, spec)
			end
		end
		target.fov = curve(P.Fov, t, 0)
		target.look = curve(P.Look, t, 0)
		target.grade = curve(P.Grade, t, 0)
		target.dof = curve(P.Dof or P.Grade, t, 0)
		target.desat = curve(P.Desat, t, 0)
		target.bars = curve(P.Bars, t, 0)
		local flying = flyMag(clip, t) > 0.12
		for _, tr in trails do
			tr[1].Enabled = flying and not vm.Hidden
		end
	else
		if presClip then
			for _, tr in trails do
				tr[1].Enabled = false
			end
			local old = trails
			trails = {}
			task.delay(0.6, function()
				for _, tt in old do
					for _, i in tt do
						if i.Parent then
							i:Destroy()
						end
					end
				end
			end)
			presClip = nil
		end
		target.fov, target.look, target.grade, target.dof, target.desat, target.bars = 0, 0, 0, 0, 0, 0
	end
end

function SkinInspects.Shake(k: number)
	cur.shake = math.max(cur.shake, k)
end
function SkinInspects.Flash(k: number)
	cur.flash = math.max(cur.flash, k)
end

-- camera + post FX + letterbox (client): applied after the viewmodel is placed, undone before the next frame
if RunService:IsClient() and RunService:IsRunning() and not _G.__VantageInspectPresent then
	_G.__VantageInspectPresent = true
	local applied = nil
	local dof, cc, bars, barTop, barBot = nil, nil, nil, nil, nil
	local function post(c: Camera)
		if not dof or dof.Parent ~= c then
			for _, old in c:GetChildren() do
				if old.Name == "VantageInspectDOF" or old.Name == "VantageInspectCC" then
					old:Destroy()
				end
			end
			dof = Instance.new("DepthOfFieldEffect")
			dof.Name = "VantageInspectDOF"
			dof.Enabled = false
			dof.NearIntensity = 0
			dof.Parent = c
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "VantageInspectCC"
			cc.Enabled = false
			cc.Parent = c
		end
		local g, d = cur.grade * presGradeAmt, cur.dof * presDofAmt
		dof.Enabled = d > 0.01
		if dof.Enabled then
			local dist = 3
			if presVm and presVm.Body then
				dist = math.clamp((presVm.Body.Position - c.CFrame.Position).Magnitude, 1.5, 12)
			end
			dof.FocusDistance = dist
			dof.InFocusRadius = math.max(4, dist * 1.6)
			dof.FarIntensity = 0.6 * d
		end
		local fl = cur.flash
		cc.Enabled = g > 0.01 or cur.desat > 0.01 or fl > 0.01
		if cc.Enabled then
			cc.Brightness = -0.08 * g + 0.22 * fl
			cc.Contrast = 0.16 * g
			cc.Saturation = 0.12 * g - 0.85 * cur.desat
			cc.TintColor = Color3.new(1, 1, 1):Lerp(presTint, 0.35 * g)
		end
		-- letterbox (Godly)
		if cur.bars > 0.005 then
			if not bars or not bars.Parent then
				local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
				if pg then
					bars = Instance.new("ScreenGui")
					bars.Name = "VantageInspectBars"
					bars.IgnoreGuiInset = true
					bars.ResetOnSpawn = false
					bars.DisplayOrder = 150
					barTop = Instance.new("Frame")
					barTop.BackgroundColor3 = Color3.new(0, 0, 0)
					barTop.BorderSizePixel = 0
					barTop.Size = UDim2.fromScale(1, 0)
					barTop.Parent = bars
					barBot = barTop:Clone()
					barBot.AnchorPoint = Vector2.new(0, 1)
					barBot.Position = UDim2.fromScale(0, 1)
					barBot.Parent = bars
					bars.Parent = pg
				end
			end
			if barTop then
				local h = 0.095 * cur.bars
				barTop.Size = UDim2.fromScale(1, h)
				barBot.Size = UDim2.fromScale(1, h)
			end
		elseif bars and bars.Parent then
			bars:Destroy()
			bars = nil
		end
	end
	RunService:BindToRenderStep("VantageInspectCamUndo", Enum.RenderPriority.First.Value, function()
		local c = workspace.CurrentCamera
		if applied and c then
			c.CFrame = c.CFrame * applied.off:Inverse()
			if math.abs(c.FieldOfView - applied.fovSet) < 1e-3 then
				c.FieldOfView = applied.fovBase
			end
		end
		applied = nil
	end)
	RunService:BindToRenderStep("VantageInspectCam", Enum.RenderPriority.Camera.Value + 3, function(dt)
		local c = workspace.CurrentCamera
		if not c then
			return
		end
		local a = 1 - math.exp(-7 * dt)
		for _, k in { "fov", "look", "grade", "dof", "desat", "bars" } do
			cur[k] += (target[k] - cur[k]) * (if k == "desat" then 1 - math.exp(-20 * dt) else a)
		end
		cur.shake *= math.exp(-7 * dt)
		cur.flash *= math.exp(-12 * dt)
		post(c)
		local active = math.abs(cur.fov) > 0.02 or cur.look > 0.002 or cur.shake > 0.01
		if not active then
			presRest = nil
			return
		end
		local off = CFrame.identity
		-- look-follow: turn a little toward where the gun has moved since the inspect began
		if cur.look > 0.002 and presVm and presVm.Body and presVm.Body.Parent then
			local lp = c.CFrame:PointToObjectSpace(presVm.Body.Position)
			if lp.Z < -0.1 then
				local yaw, pitch = math.atan2(-lp.X, -lp.Z), math.atan2(lp.Y, -lp.Z)
				presRest = presRest or { yaw, pitch }
				local m = math.rad(6)
				local dy = math.clamp((yaw - presRest[1]) * 0.35, -m, m)
				local dp = math.clamp((pitch - presRest[2]) * 0.35, -m, m)
				off *= CFrame.Angles(dp * cur.look, dy * cur.look, 0)
			end
		end
		if cur.shake > 0.01 then
			local tt = os.clock() * 28
			local amp = math.rad(1.4) * cur.shake
			off *= CFrame.Angles(math.noise(tt, 1.7) * amp, math.noise(tt, 5.3) * amp, math.noise(tt, 9.1) * amp * 0.6)
		end
		c.CFrame = c.CFrame * off
		local base = c.FieldOfView
		local f = math.clamp(base + cur.fov, 20, 110)
		c.FieldOfView = f
		applied = { off = off, fovBase = base, fovSet = f }
	end)
end

local function clearPresent()
	clearTrails()
	for _, e in live2 do
		if e.Parent then
			e.Enabled = false
		end
	end
	table.clear(live2)
	presClip = nil
	target.fov, target.look, target.grade, target.dof, target.desat, target.bars = 0, 0, 0, 0, 0, 0
end
SkinInspects.ClearPresent = clearPresent

-- freeze / release every live inspect particle (Event Horizon time stop)
local function timeScale(v: number)
	for _, e in live2 do
		if e.Parent then
			e.TimeScale = v
		end
	end
end

-- ─── BENCHMARK 1 · RARE · Glacier Ops: clean, restrained, precise ───────────────────────────────────
local ICE = PAL.Ice
FX.GL_Charge = function(vm)
	emit(vm, { Pos = V(0.16, 0.12, -0.75), Dir = V(1, 0.25, 0), Spread = 35, Tex = "mist", Color = ICE.mid, N = 2, Size = { 0.15, 0.45 }, Life = 0.9, Speed = 0.5, Emit = 0.3, Bright = 1.2, T = { 0.6, 0.5, 1 } })
	emit(vm, { Pos = V(0, 0.14, -0.9), Tex = "glow", Color = ICE.mid, N = 1, Size = { 0.3, 0.55, 0 }, Life = 0.4, LifeMin = 1, T = { 0.35, 1 }, Bright = 2 })
end
FX.GL_Toss = function(vm)
	emit(vm, { Pos = V(0, 0.1, -0.6), Tex = "streak", Orient = "streak", Color = ColorSequence.new(ICE.hot, ICE.mid), N = 8, Size = { 0.12, 0.08, 0 }, Life = 0.25, Speed = 3.5, Drag = 8, Locked = false })
end
FX.GL_Catch = function(vm)
	impact(vm, V(0, 0.12, -1.0), ICE, 0.8, { mist = ICE.mid })
	emit(vm, { Pos = V(0, 0.15, -1.0), Tex = "shard", Color = ColorSequence.new(ICE.hot, ICE.mid), N = 10, Size = { 0.13, 0.11, 0.04 }, Life = 0.8, Speed = 2.6, Drag = 1.5, Accel = V(0, -9, 0), Spin = 320, Locked = false, Emit = 0.6, Bright = 2 })
	SkinInspects.Flash(0.3)
end
FX.GL_Crystal = function(vm)
	for i, z in { -2.2, -1.5, -0.8, -0.1 } do
		later(i * 0.06, function()
			emit(vm, { Pos = V(0.05, 0.22, z), Tex = "flare", Color = ICE.hot, N = 1, Size = { 0.15, 0.35, 0 }, Life = 0.3, LifeMin = 1, Spin = 80, Bright = 3, Z = 1 })
		end)
	end
end
FX.GL_Shatter = function(vm)
	emit(vm, { Pos = V(0, 0.12, -1.3), Tex = "shard", Color = ColorSequence.new(ICE.hot, ICE.mid), N = 14, Size = { 0.11, 0.09, 0.03 }, Life = 0.9, Speed = 1.6, Drag = 1, Accel = V(0, -10, 0), Spin = 360, Locked = false, Emit = 0.6 })
	emit(vm, { Pos = V(0, 0.12, -1.3), Tex = "ring", Color = ICE.mid, N = 1, Size = { 0.2, 1.4 }, Life = 0.35, LifeMin = 1, T = { 0.3, 1 }, Bright = 2 })
end
FX.GL_Seal = function(vm)
	seal(vm, ICE.hot, -2.6, 1.3, 0.2)
end

-- ─── BENCHMARK 2 · LEGENDARY · Event Horizon: a real singularity, gravity you can feel ────────────────
local VOID = PAL.Void
local HOLES = { V(0.21, 0.041, -0.345), V(-0.21, 0.041, -0.345) }
FX.EH_Charge = function(vm)
	for _, h in HOLES do
		emit(vm, { Pos = h, Tex = "glow", Color = rgb(20, 0, 40), Emit = 0, N = 1, Size = { 0.1, 0.5, 0.42 }, Life = 0.5, LifeMin = 1, T = { 0.15, 0.6 }, Bright = 1, Z = 0.9 })
		emit(vm, { Pos = h, Tex = "ring", Color = VOID.alt, N = 1, Size = { 1.2, 0.5 }, Life = 0.35, LifeMin = 1, T = { 0.2, 0.9 }, Bright = 2.5, Z = 1 })
	end
	SkinInspects.Flash(0.15)
end
FX.EH_Release = function(vm)
	impact(vm, V(0, 0.06, -0.35), VOID, 0.9, { ring2 = VOID.alt, mist = VOID.dark })
	SkinInspects.Flash(0.35)
end
FX.EH_Hole = function(vm) -- the singularity while airborne: dark core, lensing rim, spinning accretion, infall
	for _, h in HOLES do
		emit(vm, { Pos = h, Tex = "glow", Color = rgb(12, 0, 25), Emit = 0, Rate = 10, Dur = 1.7, Size = 0.42, Life = 0.3, LifeMin = 1, T = { 0.1, 0.6 }, Bright = 1, Z = 1 })
		emit(vm, { Pos = h, Tex = "ring", Color = ColorSequence.new(VOID.hot, VOID.alt), Rate = 6, Dur = 1.7, Size = { 0.62, 0.52 }, Life = 0.35, LifeMin = 1, T = { 0.35, 1 }, Bright = 2.5, Z = 1.1 })
		emit(vm, { Pos = h, Tex = "arc", Color = ColorSequence.new(VOID.alt, VOID.mid), Rate = 8, Dur = 1.7, Size = 0.85, Life = 0.4, LifeMin = 1, Spin = 520, T = { 0.2, 1 }, Bright = 3, Z = 1.2 })
		emit(vm, { Pos = h, Tex = "plasma", Color = ColorSequence.new(VOID.mid, VOID.dark), Rate = 5, Dur = 1.7, Size = { 0.9, 0.55 }, Life = 0.5, LifeMin = 1, Spin = 180, T = { 0.55, 1 }, Bright = 2, Z = 0.6 })
	end
end
FX.EH_Vortex = function(vm) -- streaking motes falling into both holes
	for _, h in HOLES do
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local off = V(0, math.cos(a), math.sin(a)) * 0.45
			emit(vm, { Pos = h + off, Dir = -off, Spread = 5, Tex = "streak", Orient = "streak", Color = ColorSequence.new(VOID.hot, VOID.mid), N = 1, Size = { 0.1, 0.08, 0 }, Life = 0.3, LifeMin = 1, Speed = 1.45, SpeedMin = 1, Bright = 3 })
		end
	end
end
FX.EH_Freeze = function(vm) -- TIME STOP: every particle hangs, the world drains of colour, the hole implodes
	timeScale(0.02)
	for _, h in HOLES do
		emit(vm, { Pos = h, Tex = "ring", Color = VOID.hot, N = 1, Size = { 2.2, 0.1 }, Life = 0.2, LifeMin = 1, T = { 0, 0.4 }, Bright = 3, Z = 1.3 })
	end
	emit(vm, { Pos = V(0, 0.06, -0.35), Tex = "flare", Color = VOID.hot, N = 1, Size = { 1.6, 1.2, 0.8 }, Life = 0.2, LifeMin = 1, Bright = 3, Z = 1.4 })
end
FX.EH_Snap = function(vm) -- time resumes with a violent release back into the hands
	timeScale(1)
	impact(vm, V(0, 0.06, -0.35), VOID, 1.3, { ring2 = VOID.alt, mist = VOID.dark })
	SkinInspects.Flash(0.55)
end
FX.EH_Seal = function(vm)
	seal(vm, VOID.hot, -2.6, 1.3, 0.25)
end

-- ─── BENCHMARK 3 · GODLY · Golden Dragon Emperor: the full cinematic treatment ───────────────────────
local GOLD = PAL.Gold
FX.DR_Ignite = function(vm)
	emit(vm, { Pos = V(0, 0.2, -0.8), Tex = "ember", Color = ColorSequence.new(GOLD.hot, GOLD.mid), Rate = 40, Dur = 0.35, Size = { 0.06, 0.05, 0 }, Life = 0.7, Speed = 0.8, Accel = V(0, 1.5, 0), Drag = 1, Spread = 60, Dir = V(0, 1, 0) })
	emit(vm, { Pos = V(0, 0.09, -2.6), Tex = "glow", Color = GOLD.mid, N = 1, Size = { 0.2, 0.7, 0.3 }, Life = 0.6, LifeMin = 1, T = { 0.3, 1 }, Bright = 3 })
	emit(vm, { Pos = V(0, 0.09, -2.6), Tex = "flare", Color = GOLD.hot, N = 1, Size = { 0.3, 0.8, 0 }, Life = 0.4, LifeMin = 1, Spin = 60, Bright = 3, Z = 1.2 })
end
FX.DR_Launch = function(vm)
	impact(vm, V(0, 0.1, -0.6), GOLD, 0.8, { ring2 = GOLD.alt })
	emit(vm, { Pos = V(0, 0.1, -0.6), Tex = "fire", Color = ColorSequence.new(GOLD.hot, GOLD.dark), N = 14, Size = { 0.35, 0.5, 0.05 }, Life = 0.45, Speed = 1.4, Bright = 3, Locked = false })
	-- ember storm shed by the flying gun (world space, so it streams behind it)
	for _, z in { -2.6, 1.4 } do
		emit(vm, { Pos = V(0, 0.15, z), Tex = "ember", Color = ColorSequence.new(GOLD.hot, GOLD.dark), Rate = 70, Dur = 1.25, Size = { 0.07, 0.05, 0 }, Life = 0.7, Speed = 0.6, Drag = 2, Accel = V(0, -1.5, 0), Locked = false })
	end
	SkinInspects.Flash(0.25)
end
FX.DR_Fall = function(vm)
	emit(vm, { Pos = V(0, 0.09, -2.7), Tex = "fire", Color = ColorSequence.new(GOLD.hot, GOLD.dark), Rate = 45, Dur = 0.42, Size = { 0.3, 0.45, 0.05 }, Life = 0.4, Speed = 0.4, Bright = 3, Locked = false })
end
FX.DR_Impact = function(vm)
	impact(vm, V(0, 0.15, -0.8), GOLD, 1.5, { ring2 = GOLD.alt, mist = rgb(90, 40, 20) })
	SkinInspects.Flash(0.6)
end
FX.DR_MawBuild = function(vm)
	emit(vm, { Pos = V(0, 0.09, -2.65), Tex = "glow", Color = ColorSequence.new(GOLD.hot, GOLD.mid), Rate = 14, Dur = 0.6, Size = { 0.2, 0.55, 0.3 }, Life = 0.3, LifeMin = 1, T = { 0.3, 1 }, Bright = 3 })
	emit(vm, { Pos = V(0, 0.09, -2.65), Dir = V(0, 0.1, -1), Spread = 15, Tex = "fire", Color = ColorSequence.new(GOLD.hot, GOLD.dark), Rate = 20, Dur = 0.6, Size = { 0.12, 0.2, 0 }, Life = 0.3, Speed = 0.6, Bright = 3 })
end
FX.DR_Roar = function(vm)
	impact(vm, V(0, 0.09, -2.75), GOLD, 1.2, { ring2 = GOLD.alt })
	emit(vm, { Pos = V(0, 0.09, -2.8), Dir = V(0, 0.05, -1), Spread = 12, Tex = "fire", Color = ColorSequence.new(GOLD.hot, GOLD.dark), Rate = 70, Dur = 0.5, Size = { 0.25, 0.6, 0.1 }, Life = 0.4, Speed = 6, SpeedMin = 0.7, Drag = 3, Bright = 3, Locked = false })
	emit(vm, { Pos = V(0, 0.09, -2.8), Dir = V(0, 0, -1), Spread = 0, Tex = "ring", Color = ColorSequence.new(GOLD.hot, GOLD.alt), Rate = 9, Dur = 0.45, Size = { 0.3, 1.5 }, Life = 0.4, LifeMin = 1, Speed = 5, SpeedMin = 1, T = { 0.1, 1 }, Bright = 2.5, Locked = false })
	SkinInspects.Flash(0.5)
end
FX.DR_Tail = function(vm)
	emit(vm, { Pos = V(0, 0.34, 1.53), Dir = V(0, 1, 0.3), Spread = 30, Tex = "fire", Color = ColorSequence.new(GOLD.hot, GOLD.dark), N = 8, Size = { 0.15, 0.22, 0 }, Life = 0.4, Speed = 0.6, Bright = 3 })
end
FX.DR_Seal = function(vm)
	seal(vm, GOLD.hot, -2.7, 1.5, 0.25)
	emit(vm, { Pos = V(0, 0.2, -0.6), Tex = "ember", Color = ColorSequence.new(GOLD.hot, GOLD.dark), N = 16, Size = { 0.06, 0.04, 0 }, Life = 1.0, Speed = 0.5, Accel = V(0, -1, 0), Locked = false })
end

-- ─── wire the benchmarks: keep every sound / kick beat, replace the old visual beats ─────────────────
local function rebuild(clip, events, pres)
	local keep = {}
	for _, ev in clip.Events do
		local n = ev.name
		if string.sub(n, 1, 3) ~= "FX_" or string.sub(n, 1, 5) == "FX_S_" or string.sub(n, 1, 5) == "FX_K_" then
			table.insert(keep, ev)
		end
	end
	for _, ev in events do
		table.insert(keep, { t = ev[1], name = "FX_" .. ev[2] })
	end
	table.sort(keep, function(a, b)
		return a.t < b.t
	end)
	clip.Events = keep
	clip.Pres = pres
end

rebuild(C.GlacierOps, {
	{ 0.05, "GL_Charge" }, { 0.28, "GL_Toss" }, { 1.12, "GL_Catch" }, { 1.6, "GL_Crystal" }, { 2.3, "GL_Shatter" }, { 2.36, "GL_Seal" },
}, {
	Tier = "Rare",
	Fov = { { 0, 0 }, { 0.28, 0 }, { 0.62, -3 }, { 1.12, -4 }, { 1.3, -2 }, { 2.0, -3 }, { 2.6, 0 } },
	Look = { { 0, 0 }, { 0.3, 0.6 }, { 1.0, 0.6 }, { 1.25, 0 } },
	Grade = { { 0, 0 }, { 0.25, 1 }, { 2.3, 1 }, { 2.6, 0 } },
	GradeAmt = 0.35, DofAmt = 0.3, Tint = rgb(215, 238, 255),
	Trails = { { Pos = V(0, 0.1, -2.7), Width = 0.06, Color = ColorSequence.new(ICE.hot, ICE.mid), Life = 0.22, Bright = 2.5 } },
})

rebuild(C.EventHorizon, {
	{ 0.05, "EH_Charge" }, { 0.35, "EH_Release" }, { 0.4, "EH_Hole" }, { 0.9, "EH_Vortex" }, { 1.35, "EH_Vortex" }, { 1.75, "EH_Vortex" },
	{ 2.12, "EH_Freeze" }, { 2.55, "EH_Snap" }, { 3.4, "EH_Seal" },
}, {
	Tier = "Legendary",
	Fov = { { 0, 0 }, { 0.35, -2 }, { 1.9, -6 }, { 2.12, -9 }, { 2.32, -9 }, { 2.55, 1.5 }, { 2.85, -2 }, { 3.8, 0 } },
	Look = { { 0, 0 }, { 0.4, 0.8 }, { 2.45, 0.8 }, { 2.75, 0 } },
	Grade = { { 0, 0 }, { 0.35, 1 }, { 3.4, 1 }, { 3.8, 0 } },
	Desat = { { 0, 0 }, { 2.1, 0 }, { 2.13, 1 }, { 2.32, 1 }, { 2.45, 0 } },
	GradeAmt = 0.8, DofAmt = 0.7, Tint = rgb(222, 200, 255),
	Trails = {
		{ Pos = V(0, 0.108, -2.7), Width = 0.05, Color = ColorSequence.new(VOID.hot, VOID.alt), Life = 0.3, Bright = 3 },
		{ Pos = V(0, 0.108, -2.7), Width = 0.24, Color = ColorSequence.new(VOID.mid, VOID.dark), Life = 0.42, Bright = 1.5, Emit = 0.7, T0 = 0.45, T1 = 0.75 },
		{ Pos = V(0, 0.1, 1.4), Width = 0.05, Color = ColorSequence.new(VOID.hot, VOID.alt), Life = 0.3, Bright = 3 },
		{ Pos = V(0, 0.1, 1.4), Width = 0.24, Color = ColorSequence.new(VOID.mid, VOID.dark), Life = 0.42, Bright = 1.5, Emit = 0.7, T0 = 0.45, T1 = 0.75 },
	},
})

rebuild(C.DragonEmperor, {
	{ 0.05, "DR_Ignite" }, { 0.38, "DR_Launch" }, { 0.4, "DR_Tail" }, { 1.2, "DR_Fall" }, { 1.62, "DR_Impact" },
	{ 2.3, "DR_MawBuild" }, { 2.95, "DR_Roar" }, { 3.1, "DR_Tail" }, { 3.95, "DR_Seal" },
}, {
	Tier = "Godly",
	Fov = { { 0, 0 }, { 0.38, -2 }, { 0.75, 3 }, { 1.3, 2 }, { 1.62, -7 }, { 1.85, -4 }, { 2.6, -5 }, { 2.95, -11 }, { 3.3, -7 }, { 4.4, 0 } },
	Look = { { 0, 0 }, { 0.4, 1 }, { 1.5, 1 }, { 1.7, 0.3 }, { 2.9, 0.5 }, { 4.1, 0 } },
	Grade = { { 0, 0 }, { 0.3, 1 }, { 4.0, 1 }, { 4.4, 0 } },
	Bars = { { 0, 0 }, { 0.35, 1 }, { 3.95, 1 }, { 4.4, 0 } },
	GradeAmt = 1, DofAmt = 0.85, Tint = rgb(255, 222, 185),
	Trails = {
		{ Pos = V(0, 0.09, -2.75), Width = 0.06, Color = ColorSequence.new(GOLD.hot, GOLD.mid), Life = 0.32, Bright = 3 },
		{ Pos = V(0, 0.09, -2.75), Width = 0.3, Color = ColorSequence.new(GOLD.mid, GOLD.alt), Life = 0.45, Bright = 1.6, Emit = 0.8, T0 = 0.4, T1 = 0.75 },
		{ Pos = V(0, 0.15, 1.4), Width = 0.26, Color = ColorSequence.new(GOLD.mid, GOLD.dark), Life = 0.4, Bright = 1.6, Emit = 0.8, T0 = 0.45, T1 = 0.8 },
		{ Pos = V(0, 0.34, 1.53), Width = 0.05, Color = ColorSequence.new(GOLD.hot, GOLD.alt), Life = 0.28, Bright = 3 },
	},
})

SkinInspects.Effects = FX

-- ─── SFX (2026-11-15, fwjelaa-sfx + roblox-sfx skills) ───────────────────────────────────────────────
-- Every id below came back from a Creator Store search this session and was PROVEN in Studio (IsLoaded and a
-- measured TimeLength). licensed = Roblox's partner catalogue (ProSoundEffects / APM Music); community =
-- a free community upload (rights chain not checkable: swap for a licensed take before a big launch).
-- Own-viewmodel sounds are 2D on the VantageWeapon bus; round-robin takes, light pitch jitter, long files trimmed.
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local SFX_GAIN = 1
local BANK = {
	whoosh = { ids = { 9120972321, 9120972444, 9120972323 }, vol = 0.55, pitch = { 0.95, 1.08 }, src = "licensed: ProSoundEffects Wood Whoosh Slicing Air Quick Swings 1/3/4 (0.56-0.65 s)" },
	whooshBig = { ids = { 9039693350 }, vol = 0.55, pitch = { 1, 1 }, stop = 1.7, src = "licensed: APM Music Dramatic Whoosh (3.45 s, trimmed)" },
	ice = { ids = { 140692325552736, 1571353871 }, vol = 0.6, src = "community: WX_Ice_Crack_02 (1.44 s), Ice crack sound (1.74 s)" },
	iceShards = { ids = { 9114863539 }, vol = 0.45, stop = 1.4, src = "licensed: ProSoundEffects Ice Cubes Fall Dropping To Floor 5 (3.35 s, trimmed)" },
	frostBurst = { ids = { 137494680585626 }, vol = 0.5, stop = 1.6, src = "community: FrostSnowGlobeBurst (3.04 s, trimmed)" },
	holy = { ids = { 9116394545, 9116394876, 9116395089 }, vol = 0.55, pitch = { 1, 1 }, src = "licensed: ProSoundEffects Magic Glows Soft Clusters Of Chiming Hits 1/2/4" },
	wings = { ids = { 9125386815, 9125386730 }, vol = 0.5, stop = 1.8, src = "licensed: ProSoundEffects Bat Noises Bursts Of Wings Flapping (trimmed)" },
	fire = { ids = { 9114446852, 9114442751, 9114446802, 9114444052 }, vol = 0.5, pitch = { 0.92, 1.08 }, src = "licensed: ProSoundEffects Fire Whoosh 2/5/13/15 (0.83-1.29 s)" },
	sizzle = { ids = { 106226416967678 }, vol = 0.4, stop = 0.7, src = "community: meat-on-the-grill (3.17 s, trimmed)" },
	growl = { ids = { 9113980319 }, vol = 0.35, pitch = { 1.25, 1.35 }, stop = 1.0, src = "licensed: ProSoundEffects Creature Mix Giant Crab Monster Roar Growl 1 (pitched up, trimmed)" },
	snap = { ids = { 112534219704486 }, vol = 0.6, pitch = { 0.9, 1.0 }, src = "community: stronghit2 (0.81 s)" },
	roar = { ids = { 109312518223078, 122225901664901, 104011232223797 }, vol = 0.6, pitch = { 0.95, 1.02 }, src = "community: dragon-roar-5 (2.12 s), Dragon Roar (3.37 s), Dragon roar 1 (2.04 s)" },
	boom = { ids = { 9125403425, 9125403838, 9125404320 }, vol = 0.5, stop = 1.6, src = "licensed: ProSoundEffects Boom Impact Deep Distant Thumping Hits 17/25/36 (trimmed)" },
	void = { ids = { 9043340576 }, vol = 0.5, pitch = { 1, 1 }, stop = 2.2, src = "licensed: APM Music AMBIENT BOOM 01 (3.68 s, trimmed)" },
	reverse = { ids = { 9043343896 }, vol = 0.55, pitch = { 1, 1 }, src = "licensed: APM Music REVERSE NOISE HARD END 17 (2.12 s; the hard end lands on the yank)" },
	timestop = { ids = { 127329791266618 }, vol = 0.55, pitch = { 1, 1 }, src = "community: Time_Stop_Resume_Effect (1.67 s)" },
	bell = { ids = { 9117199599 }, vol = 0.55, pitch = { 1.35, 1.35 }, src = "licensed: ProSoundEffects Pan Hits With Knuckles Heads 6, resonant ring pitched up (1.63 s)" },
	glock = { ids = { 92005223886431 }, vol = 0.4, pitch = { 1, 1 }, src = "community: Glockenspiel C5 (2.71 s)" },
}
-- Sentinel ladder sounds (all proven in Studio 2026-11-15)
BANK.thunder = { ids = { 133858804746399, 6734393210, 108914009221156 }, vol = 0.6, pitch = { 0.95, 1.05 }, stop = 2.6, src = "community: Thunder (5.46 s), thunder strike (5.57 s), Thunder strike (5.57 s), trimmed" }
BANK.zap = { ids = { 9116275998, 9116276051, 9116279358 }, vol = 0.5, src = "licensed: ProSoundEffects Lightning Flashes Quick Electrical Bursts 11/13/53" }
BANK.bubbles = { ids = { 9125409840, 9120310416, 9120310477 }, vol = 0.5, src = "licensed: ProSoundEffects Bubbles Small Underwater 5 / Underwater Bubbles Deeper Med Short Bursts 6/7" }
BANK.whale = { ids = { 123987752396522 }, vol = 0.5, pitch = { 1, 1 }, stop = 2.4, src = "community: call of the whale (5.8 s, trimmed)" }
BANK.gong = { ids = { 9125585526, 9125585550 }, vol = 0.5, pitch = { 1, 1 }, stop = 2.8, src = "licensed: ProSoundEffects Gong Chinese Style Single Hits 2/5 (trimmed)" }
BANK.wind = { ids = { 224339308, 110536638811166 }, vol = 0.45, stop = 1.5, src = "community: Gust of Wind (3.17 s), wind_gust (1.73 s)" }
BANK.bird = { ids = { 9117889959 }, vol = 0.5, pitch = { 1, 1.05 }, stop = 1.8, src = "licensed: ProSoundEffects Prehistoric Bird 1 (screechy cries, trimmed)" }
BANK.fireBig = { ids = { 9114446277, 9114444052 }, vol = 0.6, src = "licensed: ProSoundEffects Fire Whoosh 5/6 (1.3-1.5 s)" }
SkinInspects.Bank = BANK
local bag: { [string]: number } = {}
local live: { Sound } = {}
local function snd(role: string, vol: number?, pitch: number?)
	local b = BANK[role]
	if not b or not RunService:IsClient() then
		return
	end
	local n = #b.ids
	local i = ((bag[role] or math.random(n)) % n) + 1 -- round robin: never the same take twice in a row
	bag[role] = i
	local s = Instance.new("Sound")
	s.Name = "InspectSFX_" .. role
	s.SoundId = "rbxassetid://" .. b.ids[i]
	s.Volume = (b.vol or 0.5) * (vol or 1) * SFX_GAIN
	local lo, hi = (b.pitch and b.pitch[1]) or 0.96, (b.pitch and b.pitch[2]) or 1.04
	s.PlaybackSpeed = (lo + (hi - lo) * math.random()) * (pitch or 1)
	s.SoundGroup = (SoundService:FindFirstChild("VantageWeapon") or SoundService:FindFirstChild("VantageEffects")) :: SoundGroup?
	s.Parent = SoundService -- 2D: it's your own gun
	s:Play()
	table.insert(live, s)
	local stop = b.stop
	if stop then
		task.delay(stop / s.PlaybackSpeed, function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.25), { Volume = 0 }):Play()
			end
		end)
	end
	Debris:AddItem(s, (stop or 4) / s.PlaybackSpeed + 0.6)
end
SkinInspects.Play = snd

-- fire / cancel / switch away: fade every inspect sound out fast
function SkinInspects.Cancel()
	for _, s in live do
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(0.12), { Volume = 0 }):Play()
			Debris:AddItem(s, 0.2)
		end
	end
	table.clear(live)
	for _, p in tempLive do
		if p.Parent then
			p:Destroy()
		end
	end
	table.clear(tempLive)
	if SkinInspects.ClearPresent then
		SkinInspects.ClearPresent()
	end
end

-- preload the bank on the client so the first inspect is not late
if RunService:IsClient() then
	task.spawn(function()
		local list = {}
		for _, b in BANK do
			for _, id in b.ids do
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. id
				table.insert(list, s)
			end
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
end

-- viewmodel punch on catches / impacts (recoil springs: drops the gun, rocks it)
local function kick(vm, k: number)
	if not vm or not vm.Kick or not vm.KickRot then
		return
	end
	local sc = vm.Scale or 1
	vm.Kick.Vel += V(0, -0.55 * k, 0.45 * k) * sc
	vm.KickRot.Vel += V(-42 * k, (math.random() - 0.5) * 20 * k, (if math.random() < 0.5 then -1 else 1) * 24 * k)
	if SkinInspects.Shake then
		SkinInspects.Shake(k * 0.8)
	end
end

-- name: "FX_<Name>" clip event ("FX_S_<role>_<vol>_<pitch>" sound, "FX_K_<amount>" kick)
function SkinInspects.FX(vm, name: string)
	if string.sub(name, 1, 5) == "FX_S_" then
		local parts = string.split(string.sub(name, 6), "_")
		snd(parts[1], tonumber(parts[2]), tonumber(parts[3]))
		return
	elseif string.sub(name, 1, 5) == "FX_K_" then
		kick(vm, tonumber(string.sub(name, 6)) or 1)
		return
	end
	local f = FX[string.sub(name, 4)]
	if f and vm then
		local ok, err = pcall(f, vm)
		if not ok then
			warn("[SkinInspects]", name, err)
		end
	end
end

return SkinInspects
