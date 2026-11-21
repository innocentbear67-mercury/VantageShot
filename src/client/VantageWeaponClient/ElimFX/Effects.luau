--[[
	VANTAGE — ElimFX.Effects: the 19 elimination effects (prototype v2 port).
	Authored in prototype space (metres, feet at y = 0, +z = the Legionary's front) and prototype
	time (the rarity tier stretches it). X is the ElimFX session: body state X.B, primitives
	(Ring, Ball, Glow, Disc, Pillar, Plate, Ghost, Bolt / Lightning, Shard, Burst / BodyBurst, Light) and
	screen helpers (Flash, Desat, Contrast, Dim, Shake), timeline helpers At / Tick, Sound.
	Each effect: Init(X) -> state, Update(X, t, dt, S), Sound(X).
]]

local ElimFX = require(script.Parent)
local TEX = ElimFX.TEX
local seg, env, ease, lerp = ElimFX.seg, ElimFX.env, ElimFX.ease, ElimFX.lerp

local V3 = Vector3.new
local C = Color3.fromRGB
local W1 = Color3.new(1, 1, 1)

local SND = {
	Impact = "rbxassetid://9113524237", Ring = "rbxassetid://9126073318", Charge = "rbxassetid://9125980435",
	Warn = "rbxassetid://9120769331", Boom = "rbxassetid://9125484526", Boom2 = "rbxassetid://9125484367",
	Crack = "rbxassetid://9114315137",
}

local function R(X, a, b) return X.Rng:NextNumber(a, b) end
local function pick(X, t) return t[X.Rng:NextInteger(1, math.max(1, #t))] end
local function rdir(X)
	local u, th = X.Rng:NextNumber(-1, 1), X.Rng:NextNumber(0, math.pi * 2)
	local s = math.sqrt(1 - u * u)
	return V3(s * math.cos(th), u, s * math.sin(th))
end
local function hsv(h) return Color3.fromHSV(h % 1, 0.85, 1) end

-- shards flying out of the body
local function shardBurst(X, pts, o)
	if #pts == 0 then return end
	local n = math.floor(#pts * X.Tier.Amp ^ 0.7 + 0.5)
	local ka = X.Tier.Amp ^ 0.3
	for i = 1, n do
		local s = pts[(i - 1) % #pts + 1]
		local out = s.p - o.center
		out = if out.Magnitude > 1e-3 then out.Unit else V3(0, 1, 0)
		local v = out * R(X, o.speed[1], o.speed[2]) * ka + s.n * R(X, 0, o.normal or 1) + V3(0, R(X, if o.up then o.up[1] else 0, if o.up then o.up[2] else 1.5), 0)
		local color = if type(o.color) == "function" then o.color(s) else o.color
		if o.velFn then v = o.velFn(v, s) end
		X:Shard({
			kind = o.kind, p = s.p, v = v, life = R(X, o.life[1], o.life[2]), size = R(X, o.size[1], o.size[2]),
			e0 = if type(o.e0) == "function" then o.e0(s) else o.e0, e1 = o.e1, g = o.g, drag = o.drag, bounce = o.bounce,
			color = color, shrinkAt = o.shrinkAt, cool = o.cool, scale = o.scale and o.scale(),
		})
	end
end

-- radial burst helper (particles)
local function sparks(X, at, n, color, o)
	o = o or {}
	X:Burst(at, n, {
		tex = o.tex or TEX.Glow, color = color, size = o.size or { 0.035, 0.006 }, life = o.life or { 0.25, 0.5 },
		speed = o.speed or { 3, 10 }, drag = o.drag or 3, stretch = o.stretch or 2.2, bright = o.bright or 4, g = o.g,
		spread = o.spread, dir = o.dir, delay = o.delay,
	})
end

local E = {}

-- 01 ───────────────────────────────────────────────── COLLAPSE
E.collapse = {
	Init = function(X)
		local S = {}
		local ice = C(174, 224, 255)
		S.core = X:Glow({ Color = ice, Image = TEX.Core, Streak = 0.8, Brightness = 4 })
		S.shell = X:Ball({ Color = C(150, 205, 255) })
		S.ring = X:Ring({ Color = C(214, 239, 255), Thick = 0.025 })
		X:At(0.03, function()
			X:Burst(V3(0, 1.12, 0), 110, { shape = "inward", r = 0.95, tex = TEX.Glow, color = { C(190, 232, 255), C(74, 160, 255) }, size = { 0.035, 0.012 }, life = { 0.26, 0.3 }, speed = { 3.2, 3.6 }, stretch = 2, bright = 3 })
		end)
		X:At(0.3, function()
			shardBurst(X, X:Sample(46), { center = V3(0, 1.12, 0), kind = "metal", speed = { 2.5, 6.5 }, size = { 0.03, 0.07 }, e0 = C(159, 212, 255), e1 = C(20, 30, 45), life = { 0.55, 0.85 }, up = { 0.5, 2.5 }, cool = true })
			sparks(X, V3(0, 1.12, 0), 200, { C(230, 246, 255), C(58, 140, 255) }, { speed = { 3, 11 }, life = { 0.2, 0.45 } })
			X:Burst(V3(0, 1.12, 0), 30, { tex = TEX.Spark, color = C(159, 212, 255), size = { 0.05, 0.02 }, life = { 0.4, 0.7 }, speed = { 0.3, 1.2 }, drag = 1, bright = 3 })
			X:Burst(V3(0, 1.12, 0), 3, { noAmp = true, tex = TEX.Shock, color = C(190, 230, 255), size = { 0.4, 3.2 }, life = { 0.35, 0.35 }, speed = { 0, 0 }, bright = 3 })
			X:Shake(0.45)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local ign, imp = seg(t, 0, 0.05), seg(t, 0.05, 0.3)
		local Cc = V3(0, 1.12, 0)
		B.GlowColor, B.Glow = C(174, 224, 255), 0.75 * ign + 0.2 * imp
		B.OutlineColor, B.Outline = W1, ign
		B.Flicker, B.FlickerColor = 0.25 * imp + 0.6 * env(t, 0, 0.03, 0.1), C(200, 236, 255)
		B.Pinch, B.PinchC, B.Bias = ease.inQuad(imp), Cc, 0.9
		local cs = if t < 0.3 then 0.06 + 0.3 * ease.inQuad(imp) else 0.8 * (1 - seg(t, 0.3, 0.5)) ^ 2
		S.core:Set(Cc, cs * 2, if t < 0.3 then 0.5 + imp * 0.5 else 1 - seg(t, 0.3, 0.5))
		local k = seg(t, 0.3, 0.62)
		S.shell:Set(Cc, (0.15 + 1.7 * ease.outQuart(k)) * X.Tier.Amp ^ 0.75, if t > 0.3 then 0.7 * (1 - k) ^ 1.5 else 0)
		local kr = seg(t, 0.3, 0.6)
		S.ring:Set(Cc, (0.1 + 2.9 * ease.outCubic(kr)) * X.Tier.Amp ^ 0.75, if t > 0.3 then (1 - kr) ^ 1.5 else 0, 0.35)
		X:Light(1, Cc, C(168, 216, 255), 6 * env(t, 0, 0.03, 0.12) + 3 * imp + 14 * env(t, 0.3, 0.305, 0.6), 10)
		X:Flash(C(190, 224, 255), 0.25 * env(t, 0.3, 0.305, 0.42))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.35, speed = 1.6, len = 0.6 })
		X:Sound(SND.Boom, 0.3, { vol = 0.7, speed = 1.1 })
		X:Sound(SND.Ring, 0.3, { vol = 0.3, speed = 1.2 })
	end,
}

-- 02 ───────────────────────────────────────────────── OVERLOAD
E.overload = {
	Init = function(X)
		local S = { pts = X:Sample(260), cache = {}, big = {}, jit = V3() }
		X:At(0.38, function()
			X:BodyBurst(70, { tex = TEX.Glow, color = { C(255, 216, 192), C(255, 24, 0) }, size = { 0.03, 0.006 }, life = { 0.45, 0.9 }, speed = { 2, 7 }, spread = 40, g = V3(0, -9.8, 0), drag = 0.8, stretch = 2.2, bright = 4 })
			sparks(X, V3(0, 1.1, 0), 140, { C(255, 210, 190), C(255, 30, 0) }, { speed = { 2, 8 }, life = { 0.4, 0.9 }, g = V3(0, -9.8, 0), drag = 0.8 })
			X:Burst(V3(0, 1.1, 0), 12, { tex = TEX.Smoke, color = { C(30, 8, 8), C(10, 4, 4) }, size = { 0.35, 0.8 }, life = { 0.6, 0.95 }, speed = { 0.3, 1.1 }, light = 0, bright = 1, alpha = 0.55, drag = 1.5 })
			shardBurst(X, X:Sample(34), { center = V3(0, 1.1, 0), kind = "metal", speed = { 2, 5.5 }, size = { 0.03, 0.065 }, e0 = C(255, 70, 40), e1 = C(40, 10, 8), life = { 0.6, 0.9 }, cool = true })
			for _ = 1, 9 do
				local s = pick(X, S.pts)
				if s then
					local d = (s.n + rdir(X) * 0.6 + V3(0, 0.3, 0)).Unit
					table.insert(S.big, { a = s.p, b = s.p + d * R(X, 1.0, 2.0) })
				end
			end
			X:Shake(0.55)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local charge = seg(t, 0, 0.38)
		if X:Tick("arc", 30) then
			S.cache = {}
			if t < 0.4 and #S.pts > 0 then
				for _ = 1, 3 + math.floor(10 * charge) do
					local a = pick(X, S.pts)
					for _ = 1, 10 do
						local b = pick(X, S.pts)
						local d = (b.p - a.p).Magnitude
						if d > 0.12 and d < 0.42 then
							for _, l in X:Lightning(a.p + a.n * 0.02, b.p + b.n * 0.02, { depth = 3, jag = 0.35, branch = 0.15 }) do table.insert(S.cache, l) end
							break
						end
					end
				end
			end
			if t >= 0.38 and t < 0.56 then
				for _, b in S.big do
					for _, l in X:Lightning(b.a, b.b, { depth = 4, jag = 0.3, branch = 0.35, w = 2.4 }) do table.insert(S.cache, l) end
				end
			end
			S.flick = 0.55 + 0.45 * X.Rng:NextNumber()
			S.jit = V3(R(X, -1, 1), R(X, -0.3, 0.3), R(X, -1, 1)) * 0.018 * charge
		end
		local fade = if t < 0.38 then 1 else 1 - seg(t, 0.38, 0.56)
		X:DrawBolts(S.cache, 0.012, C(255, 60, 40), 1, fade)
		if t < 0.47 then B.Offset = S.jit end
		B.GlowColor, B.Glow = C(255, 36, 20), (0.1 + 0.45 * charge * charge) * (S.flick or 1)
		B.OutlineColor, B.Outline = C(255, 60, 40), charge
		B.Flicker, B.FlickerColor = 0.45 * charge, C(255, 48, 24)
		B.Glitch = 0.025 * charge
		B.Diss, B.DissMode, B.Edge = seg(t, 0.38, 0.47) * 1.05, 0, C(255, 112, 80)
		X:Light(1, V3(0, 1.12, 0), C(255, 42, 20), 6 * charge * (S.flick or 1) + 18 * env(t, 0.38, 0.385, 0.62), 10)
		X:Flash(C(255, 48, 32), 0.3 * env(t, 0.38, 0.385, 0.5))
	end,
	Sound = function(X)
		for i = 0, 5 do X:Sound(SND.Warn, i * 0.06, { vol = 0.15, speed = 2.4 + i * 0.15, len = 0.2 }) end
		X:Sound(SND.Boom2, 0.38, { vol = 0.75, speed = 1.0 })
		X:Sound(SND.Crack, 0.38, { vol = 0.5, speed = 1.3 })
	end,
}

-- 03 ───────────────────────────────────────────────── DISCHARGE
E.discharge = {
	Init = function(X)
		local L = X:Landmarks()
		local O = L.Chest
		local S = { O = O, targets = L.List, arcs = {}, sarcs = {}, strikes = {}, decals = {}, sky = {} }
		local lime = C(168, 255, 58)
		S.orb = X:Glow({ Color = lime, Image = TEX.Core, Streak = 0.4, Brightness = 4 })
		S.ring = X:Ring({ Color = C(200, 255, 112), Thick = 0.018 })
		for i = 1, 6 do S.decals[i] = X:Disc({ Color = lime }) end
		X:At(0.3, function()
			for i = 1, 6 do
				local a = i / 6 * math.pi * 2 + R(X, -0.35, 0.35)
				local r = R(X, 1.3, 2.4)
				local g = V3(math.cos(a) * r, 0.02, math.sin(a) * r * 0.8)
				S.strikes[i] = g
				sparks(X, g, 22, { C(224, 255, 176), C(106, 255, 0) }, { speed = { 1, 4 }, life = { 0.3, 0.6 }, g = V3(0, -9.8, 0), dir = V3(0, 1, 0), spread = 70, drag = 1 })
			end
			for i = 1, 5 do S.sky[i] = O + (rdir(X) + V3(0, 0.9, 0)).Unit * R(X, 1.8, 2.6) end
			sparks(X, O, 200, { C(232, 255, 192), C(90, 255, 0) }, { speed = { 3, 10 }, life = { 0.2, 0.45 } })
			X:Shake(0.45)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local grow = ease.outCubic(seg(t, 0.03, 0.26))
		local lime = C(168, 255, 58)
		if X:Tick("arc", 30) then
			S.arcs = {}
			if t < 0.42 then
				for _, T in S.targets do
					for _, l in X:Lightning(S.O, T, { depth = 4, jag = 0.16, branch = 0.5 }) do table.insert(S.arcs, l) end
				end
			end
			S.sarcs = {}
			if t >= 0.3 and t < 0.54 then
				for _, g in S.strikes do for _, l in X:Lightning(S.O, g, { depth = 5, jag = 0.22, branch = 0.35, w = 2.2 }) do table.insert(S.sarcs, l) end end
				for _, g in S.sky do for _, l in X:Lightning(S.O, g, { depth = 4, jag = 0.25, branch = 0.3, w = 1.5 }) do table.insert(S.sarcs, l) end end
			end
			if t >= 0.5 and t < 0.85 then
				for _, g in S.strikes do
					if X.Rng:NextNumber() < 0.6 then
						for _, l in X:Lightning(g + V3(0, 0.02, 0), g + V3(R(X, -0.3, 0.3), R(X, 0.1, 0.35), R(X, -0.3, 0.3)), { depth = 2, jag = 0.4, branch = 0 }) do table.insert(S.sarcs, l) end
					end
				end
			end
			S.fl = 0.6 + 0.4 * X.Rng:NextNumber()
		end
		X:DrawBolts(S.arcs, 0.011, lime, grow, 1 - seg(t, 0.36, 0.42))
		X:DrawBolts(S.sarcs, 0.011, C(190, 255, 90), 1, 1 - seg(t, 0.42, 0.85) * 0.7)
		B.GlowColor, B.Glow = lime, 0.2 * grow * (S.fl or 1)
		B.Flicker, B.FlickerColor = 0.3 * grow, lime
		B.Diss, B.DissMode, B.DissC, B.Edge = ease.inQuad(seg(t, 0.22, 0.41)) * 1.05, 3, S.O, C(200, 255, 96)
		local os_ = if t < 0.3 then 0.1 + 0.18 * grow * (S.fl or 1) else 0.7 * (1 - seg(t, 0.3, 0.45)) ^ 2
		S.orb:Set(S.O, os_ * 2, if t < 0.3 then 1 else 1 - seg(t, 0.3, 0.45))
		local kr = seg(t, 0.3, 0.58)
		S.ring:Set(S.O - V3(0, 0.2, 0), (0.2 + 2.6 * ease.outCubic(kr)) * X.Tier.Amp ^ 0.75, if t > 0.3 then 1 - kr else 0, 0.3)
		for i, d in S.decals do
			local g = S.strikes[i]
			if g then d:Set(g, 0.25, 0.8 * (1 - seg(t, 0.32, 0.95)) * (S.fl or 1)) else d:Set(V3(), 0, 0) end
		end
		X:Light(1, S.O, lime, 5 * grow * (S.fl or 1) + 14 * env(t, 0.3, 0.305, 0.5), 10)
		if S.strikes[1] then X:Light(2, S.strikes[1] + V3(0, 0.4, 0), lime, 8 * env(t, 0.3, 0.31, 0.6) * (S.fl or 1), 6) end
		if S.strikes[4] then X:Light(3, S.strikes[4] + V3(0, 0.4, 0), lime, 8 * env(t, 0.3, 0.31, 0.6) * (S.fl or 1), 6) end
		X:Flash(C(184, 255, 96), 0.2 * env(t, 0.3, 0.305, 0.4))
	end,
	Sound = function(X)
		for i = 0, 6 do X:Sound(SND.Warn, 0.02 + i * 0.04, { vol = 0.12, speed = 3 + i * 0.2, len = 0.2 }) end
		X:Sound(SND.Crack, 0.3, { vol = 0.65, speed = 1.5 })
		X:Sound(SND.Boom2, 0.3, { vol = 0.5, speed = 1.25 })
	end,
}

-- 04 ───────────────────────────────────────────────── AFTERSHOCK
E.aftershock = {
	Init = function(X)
		local Cc = V3(0, 1.0, 0)
		local S = { Cc = Cc, rings = {}, ground = {}, times = { 0.22, 0.29, 0.36, 0.43 }, radii = { 3.4, 2.9, 2.5, 2.1 } }
		S.core = X:Glow({ Color = C(85, 216, 255), Image = TEX.Core, Streak = 0.5, Brightness = 4 })
		S.inhale = X:Ring({ Color = C(64, 200, 255), Thick = 0.02 })
		for i = 1, 4 do
			S.rings[i] = X:Ring({ Color = if i % 2 == 0 then C(42, 123, 255) else C(106, 224, 255), Thick = 0.024 - i * 0.003 })
			S.ground[i] = X:Ring({ Color = C(72, 208, 255), Thick = 0.03 })
			X:At(S.times[i], function()
				sparks(X, Cc, 50, { C(191, 240, 255), C(42, 123, 255) }, { speed = { 5, 11 - i }, life = { 0.2, 0.35 }, spread = 12, dir = V3(1, 0, 0) })
				sparks(X, Cc, 50, { C(191, 240, 255), C(42, 123, 255) }, { speed = { 5, 11 - i }, life = { 0.2, 0.35 }, spread = 12, dir = V3(-1, 0, 0) })
				X:Burst(V3(0, 0.05, 0), 26, { shape = "ring", r = 0.4, tex = TEX.Smoke, color = { C(38, 48, 58), C(16, 21, 26) }, size = { 0.15, 0.45 }, life = { 0.4, 0.7 }, speed = { 3, 5 }, light = 0, bright = 1, alpha = 0.4, drag = 3 })
				X:Shake(0.3 - (i - 1) * 0.04)
			end)
		end
		X:At(0.0, function()
			X:Burst(Cc, 120, { shape = "inward", r = 1.8, tex = TEX.Glow, color = { C(122, 228, 255), C(42, 123, 255) }, size = { 0.04, 0.015 }, life = { 0.22, 0.25 }, speed = { 7, 8 }, stretch = 2.2, bright = 3, delay = 0.05 })
		end)
		X:At(0.22, function()
			shardBurst(X, X:Sample(24), { center = Cc, kind = "metal", speed = { 2, 5 }, size = { 0.025, 0.05 }, e0 = C(80, 208, 255), e1 = C(20, 26, 32), life = { 0.5, 0.8 }, cool = true })
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local comp = seg(t, 0, 0.22)
		B.Pinch, B.PinchC, B.PinchW, B.Bias = ease.inCubic(comp), S.Cc, V3(1, 1.15, 1), 0.3
		B.GlowColor, B.Glow = C(64, 208, 255), 0.7 * comp
		B.Flicker, B.FlickerColor = 0.5 * comp, C(130, 230, 255)
		local wob = if comp > 0.6 then 1 + 0.18 * math.sin(t * 140) else 1
		local after = seg(t, 0.22, 0.5)
		S.core:Set(S.Cc, ((if t < 0.22 then 0.1 + 0.45 * comp else 0.55 * (1 - after)) * wob) * 2, if t < 0.22 then 0.6 + comp * 0.4 else 1 - after)
		S.inhale:Set(V3(0, 0.03, 0), lerp(2.4, 0.3, ease.inQuad(comp)), if t < 0.22 then comp * 0.9 else 0, "h")
		local A = X.Tier.Amp ^ 0.75
		local pulses = 0
		for i = 1, 4 do
			local t0 = S.times[i]
			local k = seg(t, t0, t0 + 0.34)
			local r = (0.1 + S.radii[i] * ease.outCubic(k)) * A
			local a = if t > t0 then (1 - k) ^ 1.3 * (1 - (i - 1) * 0.12) else 0
			S.rings[i]:Set(S.Cc, r, a, 0.32)
			S.ground[i]:Set(V3(0, 0.03, 0), r * 1.05, a * 0.8, "h")
			pulses += env(t, t0, t0 + 0.008, t0 + 0.12)
		end
		X:Light(1, S.Cc, C(64, 200, 255), 4 * comp + 12 * pulses, 10)
		X:Flash(C(96, 208, 255), 0.12 * pulses)
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.35, speed = 2.0, len = 0.4 })
		for i, t in { 0.22, 0.29, 0.36, 0.43 } do X:Sound(SND.Boom, t, { vol = 0.6 - (i - 1) * 0.1, speed = 1.1 + i * 0.06 }) end
	end,
}

-- 05 ───────────────────────────────────────────────── PHASE SHIFT
E.phase = {
	Init = function(X)
		local S = { popped = {} }
		S.line = X:Glow({ Color = C(216, 168, 255), Image = TEX.Core, Brightness = 5 })
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local purple = C(176, 112, 255)
		local holo = seg(t, 0, 0.07)
		if holo > 0.2 then B.Skin, B.SkinColor, B.SkinT = "ff", purple, 0.1 end
		B.GlowColor, B.Glow = purple, 0.35 * holo
		B.OutlineColor, B.Outline = C(220, 180, 255), holo
		B.Jitter = 0.07 * seg(t, 0.05, 0.12)
		B.Glitch = 0.09 * env(t, 0.03, 0.18, 0.42)
		local q = math.floor(t * 30) / 30
		local cut = seg(q, 0.12, 0.4)
		B.Cut = cut
		for _, rec in X.Parts do
			if rec.Id < cut and not S.popped[rec] then
				S.popped[rec] = true
				X:Burst(rec.C, 8, { noAmp = true, tex = TEX.Square, color = { C(200, 144, 255), C(96, 32, 255) }, size = { 0.035, 0.015 }, life = { 0.25, 0.5 }, speed = { 0.2, 0.9 }, drag = 3, bright = 3 })
				X:Burst(rec.C, 1, { noAmp = true, tex = TEX.Glow, color = purple, size = { 0.25, 0.1 }, life = { 0.08, 0.08 }, speed = { 0, 0 }, bright = 3 })
			end
		end
		local Cc = V3(0, 1.12, 0)
		if t >= 0.38 then
			local a, b = seg(t, 0.38, 0.45), seg(t, 0.45, 0.52)
			local h = math.max(0.012, 0.6 * (1 - ease.outCubic(a)) + 0.012)
			local w = math.max(0.004, 0.95 * (1 - ease.inCubic(b)))
			S.line:Set(Cc, h, if t < 0.52 then 1 else 1 - seg(t, 0.52, 0.6), nil, w / h)
		else
			S.line:Set(Cc, 0, 0)
		end
		X:Light(1, Cc, C(160, 96, 255), 2.5 * (0.6 + 0.4 * math.sin(t * 90)) * (1 - seg(t, 0.4, 0.5)), 8)
	end,
	Sound = function(X)
		for i = 0, 8 do X:Sound(SND.Warn, 0.03 + i * 0.04, { vol = 0.12, speed = 1.6 + (i % 3) * 0.5, len = 0.15 }) end
		X:Sound(SND.Ring, 0.38, { vol = 0.3, speed = 2.2 })
	end,
}

-- 06 ───────────────────────────────────────────────── MELTDOWN
E.meltdown = {
	Init = function(X)
		local S = { pts = X:Sample(300) }
		S.pool = X:Disc({ Color = C(255, 106, 16) })
		X:At(0.3, function()
			shardBurst(X, X:Sample(70), { center = V3(0, 1.1, 0), kind = "metal", speed = { 2, 6 }, size = { 0.03, 0.075 }, e0 = C(255, 196, 120), e1 = C(60, 12, 4), life = { 0.7, 1.0 }, up = { 1, 3 }, cool = true })
			sparks(X, V3(0, 1.1, 0), 220, { C(255, 228, 170), C(255, 48, 0) }, { speed = { 2, 8 }, life = { 0.4, 0.8 }, g = V3(0, -9.8, 0), drag = 1 })
			X:Burst(V3(0, 1.1, 0), 30, { tex = TEX.Fire, color = { C(255, 170, 70), C(160, 20, 0) }, size = { 0.12, 0.04 }, life = { 0.5, 0.9 }, speed = { 1.5, 4 }, g = V3(0, -9.8, 0), drag = 0.5, bright = 3 })
			X:Burst(V3(0, 1.1, 0), 12, { tex = TEX.Smoke, color = { C(40, 22, 12), C(14, 8, 6) }, size = { 0.35, 0.8 }, life = { 0.7, 1.0 }, speed = { 0.2, 0.8 }, dir = V3(0, 1, 0), spread = 50, light = 0, bright = 1, alpha = 0.45, drag = 1 })
			X:Shake(0.4)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local h = seg(t, 0, 0.3)
		local c1, c2, c3 = C(138, 20, 0), C(255, 106, 16), C(255, 240, 216)
		local col = if h < 0.5 then c1:Lerp(c2, h * 2) else c2:Lerp(c3, (h - 0.5) * 2)
		B.GlowColor, B.Glow = col, 0.1 + 0.55 * h ^ 1.6
		B.OutlineColor, B.Outline = col, h
		B.Flicker, B.FlickerColor = 0.12 + 0.55 * seg(t, 0.04, 0.25), col
		B.Sag = 0.2 * ease.inQuad(seg(t, 0.08, 0.32))
		B.Diss, B.DissMode, B.Edge = seg(t, 0.29, 0.33) * 1.05, 0, C(255, 240, 192)
		if t < 0.3 and X:Tick("drip", 30) then
			for _ = 1, 3 do
				local s = pick(X, S.pts)
				if s then X:Burst(s.p, 1, { noAmp = true, tex = TEX.Glow, color = { C(255, 192, 96), C(255, 48, 0) }, size = { 0.03, 0.015 }, life = { 0.55, 0.55 }, speed = { 0.3, 0.4 }, dir = V3(0, -1, 0), spread = 5, g = V3(0, -9.8, 0), stretch = 2, bright = 3 }) end
			end
		end
		S.pool:Set(V3(0, 0.02, 0), 0.25 + 0.55 * h, 0.9 * h * (1 - seg(t, 0.35, 1.2)))
		X:Light(1, V3(0, 1.1, 0), C(255, 112, 32), 5 * h + 16 * env(t, 0.3, 0.305, 0.7), 10)
		X:Flash(C(255, 128, 64), 0.18 * env(t, 0.3, 0.305, 0.45))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.35, speed = 0.8, len = 0.6 })
		X:Sound(SND.Boom, 0.3, { vol = 0.75, speed = 0.9 })
		X:Sound(SND.Boom2, 0.32, { vol = 0.35, speed = 0.75 })
	end,
}

-- 07 ───────────────────────────────────────────────── SHATTER
E.shatter = {
	Init = function(X)
		local S = { pts = X:Sample(220) }
		X:At(0.17, function()
			shardBurst(X, X:Sample(150), {
				center = V3(0, 1.12, 0), kind = "crystal", speed = { 1.0, 4.2 }, size = { 0.035, 0.08 }, life = { 0.65, 1.0 }, up = { 0.4, 2.0 }, normal = 1.2,
				color = C(176, 220, 255), shrinkAt = 0.55, scale = function() return V3(R(X, 0.6, 1.1), R(X, 1.0, 2.3), R(X, 0.4, 0.8)) end,
			})
			sparks(X, V3(0, 1.1, 0), 140, { C(232, 246, 255), C(74, 144, 255) }, { speed = { 0.5, 4 }, life = { 0.2, 0.5 } })
			X:BodyBurst(30, { tex = TEX.Spark, color = C(208, 236, 255), size = { 0.05, 0.02 }, life = { 0.3, 0.7 }, speed = { 0.1, 0.6 }, drag = 2, bright = 3 })
			X:Shake(0.3)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local fr = ease.outCubic(seg(t, 0, 0.12))
		if fr > 0.35 then B.Skin, B.SkinColor = "glass", C(170, 214, 255) end
		B.GlowColor, B.Glow = C(159, 208, 255), 0.35 * fr + 0.3 * seg(t, 0.1, 0.17)
		B.OutlineColor, B.Outline = W1, fr
		B.Flicker, B.FlickerColor = 0.25 * seg(t, 0.1, 0.17), C(220, 240, 255)
		if t < 0.17 and X:Tick("sp", 40) then
			for _ = 1, 3 do
				local s = pick(X, S.pts)
				if s then X:Burst(s.p + s.n * 0.01, 1, { noAmp = true, tex = TEX.Spark, color = C(224, 242, 255), size = { 0.06, 0.02 }, life = { 0.14, 0.14 }, speed = { 0, 0 }, bright = 4 }) end
			end
		end
		if t < 0.17 then B.Offset = V3(env(t, 0.13, 0.15, 0.17) * 0.006 * math.sin(t * 400), 0, 0) end
		X:Light(1, V3(0, 1.12, 0), C(159, 208, 255), 3 * seg(t, 0, 0.12) + 10 * env(t, 0.17, 0.175, 0.45), 10)
		X:Flash(C(207, 232, 255), 0.22 * env(t, 0.17, 0.172, 0.27))
	end,
	Sound = function(X)
		X:Sound(SND.Ring, 0, { vol = 0.25, speed = 2.4 })
		X:Sound(SND.Crack, 0.17, { vol = 0.7, speed = 1.7 })
		X:Sound(SND.Ring, 0.18, { vol = 0.35, speed = 1.9 })
	end,
}

-- 08 ───────────────────────────────────────────────── DECONSTRUCT
E.deconstruct = {
	Init = function(X)
		local S = { ex = {} }
		local bc = V3(0, 1.1, 0)
		for _, rec in X.Parts do
			local d = rec.C - bc
			d = V3(d.X, d.Y * 0.6, d.Z)
			d = (if d.Magnitude > 1e-3 then d.Unit else V3(0, 1, 0)) + rdir(X) * 0.25
			S.ex[rec] = { Dir = d.Unit, Dist = R(X, 0.14, 0.38) * (if rec.C.Y > 1.55 then 1.4 else 1), K = 0, Axis = rdir(X), Ang = R(X, 0.25, 0.9), Delay = rec.Id * 0.1 }
		end
		S.scan = X:Ring({ Color = C(255, 198, 107), Thick = 0.012, Segments = 36 })
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local amber = C(255, 192, 112)
		local sy = if t < 0.14 then 2.05 - 2.15 * ease.inOutSine(seg(t, 0, 0.13)) else -1
		S.scan:Set(V3(0, sy, 0), 0.45, if t < 0.14 then 1 else 0, "h")
		B.GlowColor, B.Glow = amber, 0.25 * seg(t, 0, 0.12)
		B.OutlineColor, B.Outline = C(255, 220, 160), seg(t, 0, 0.1)
		for rec, e in S.ex do
			e.K = ease.outBack(seg(t, 0.1 + e.Delay, 0.3 + e.Delay))
			if t > 0.1 + e.Delay and t < 0.42 then
				X:Bolt({ V3(0, 1.1, 0), rec.C + e.Dir * e.Dist * e.K }, 0.004, C(255, 200, 120), 1, 0.8 * (1 - seg(t, 0.3, 0.42)))
			end
		end
		B.Explode = S.ex
		B.Diss, B.DissMode, B.Edge = seg(t, 0.26, 0.56) * 1.05, 4, C(255, 208, 138)
		if t > 0.26 and t < 0.56 and X:Tick("vox", 30) then
			for _, s in X:Sample(5) do
				local e = S.ex[s.part]
				local p = s.p + (if e then e.Dir * e.Dist * e.K else V3())
				X:Shard({ kind = "neon", p = p, v = s.n * R(X, 0.3, 1.0) + V3(0, R(X, 0.2, 0.8), 0), life = R(X, 0.35, 0.6), size = R(X, 0.018, 0.034), scale = V3(1, 1, 1), e0 = amber, e1 = C(80, 30, 0), g = 0.4, drag = 2, bounce = false, shrinkAt = 0.3 })
			end
		end
		X:Light(1, V3(0, 1.2, 0.6), amber, 2.5 * seg(t, 0, 0.1) * (1 - seg(t, 0.5, 0.7)), 8)
	end,
	Sound = function(X)
		X:Sound(SND.Warn, 0, { vol = 0.15, speed = 1.2, len = 0.3 })
		for i = 0, 5 do X:Sound(SND.Impact, 0.1 + i * 0.03, { vol = 0.12, speed = 1.8 + i * 0.1, len = 0.3 }) end
		X:Sound(SND.Ring, 0.3, { vol = 0.2, speed = 2.6 })
	end,
}

-- 09 ───────────────────────────────────────────────── SUPERNOVA
E.supernova = {
	Init = function(X)
		local Cc = V3(0, 1.12, 0)
		local S = { rays = {} }
		S.star = X:Glow({ Color = C(255, 210, 122), Image = TEX.Core, Streak = 1.4, Brightness = 5 })
		S.shell = X:Ball({ Color = C(255, 232, 170) })
		S.shell2 = X:Ball({ Color = C(255, 144, 48) })
		for i = 1, 26 do S.rays[i] = { d = rdir(X), L = R(X, 0.35, 1) } end
		X:At(0.0, function()
			X:Burst(Cc, 200, { shape = "inward", r = 2.2, tex = TEX.Glow, color = { C(255, 200, 96), C(255, 240, 192) }, size = { 0.04, 0.02 }, life = { 0.22, 0.24 }, speed = { 9, 10 }, stretch = 2.5, bright = 4, delay = 0.04 })
		end)
		X:At(0.26, function()
			sparks(X, Cc, 240, { C(255, 244, 208), C(255, 144, 32) }, { speed = { 5, 16 }, life = { 0.35, 0.65 }, drag = 4, stretch = 3 })
			X:Burst(Cc, 50, { tex = TEX.Spark, color = C(255, 224, 160), size = { 0.06, 0.02 }, life = { 0.5, 0.95 }, speed = { 0.2, 1 }, drag = 1, bright = 3 })
			X:Burst(Cc, 2, { noAmp = true, tex = TEX.Shock, color = C(255, 220, 150), size = { 0.5, 4.5 }, life = { 0.45, 0.45 }, speed = { 0, 0 }, bright = 3 })
			X:Shake(0.55)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local Cc = V3(0, 1.12, 0)
		local imp = seg(t, 0, 0.22)
		B.Pinch, B.PinchC, B.Bias, B.Swirl = ease.inQuart(imp), Cc, 0.4, 1.2
		B.GlowColor, B.Glow = C(255, 224, 160), 0.85 * imp
		if imp > 0.5 then B.Skin, B.SkinColor = "neon", C(255, 230, 170) end
		local peak = env(t, 0.2, 0.25, 0.27)
		local after = seg(t, 0.26, 0.6)
		local ss = if t < 0.26 then 0.06 + 0.32 * ease.inQuad(imp) + 0.15 * peak * (0.8 + 0.2 * math.sin(t * 300)) else 0.55 * (1 - after) ^ 2.4
		S.star:Set(Cc, ss * 2.4, if t < 0.26 then 0.7 + 0.3 * imp else 1 - after)
		local A = X.Tier.Amp ^ 0.75
		local k = seg(t, 0.26, 0.68)
		S.shell:Set(Cc, (0.2 + 2.1 * ease.outExpo(k)) * A, if t > 0.26 then 0.55 * (1 - k) ^ 1.8 else 0)
		local k2 = seg(t, 0.28, 0.95)
		S.shell2:Set(Cc, (0.2 + 1.9 * ease.outCubic(k2)) * A, if t > 0.28 then 0.4 * (1 - k2) ^ 1.8 else 0)
		-- god rays: Neon spikes thrown out from the star
		local kr = seg(t, 0.26, 0.62)
		if t > 0.26 and kr < 1 then
			local len, inner = (0.5 + 3.4 * ease.outCubic(kr)) * A, 0.6 * kr
			for _, r in S.rays do
				X:Bolt({ Cc + r.d * len * r.L * inner, Cc + r.d * len * r.L }, 0.02 * (1 - kr), C(255, 216, 144), 1, (1 - kr) ^ 1.2)
			end
		end
		X:Light(1, Cc, C(255, 200, 112), 6 * imp + 22 * env(t, 0.26, 0.265, 0.7), 12)
		X:Flash(C(255, 230, 176), 0.4 * env(t, 0.26, 0.262, 0.38))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.45, speed = 1.4, len = 0.5 })
		X:Sound(SND.Boom, 0.26, { vol = 0.9, speed = 0.85 })
		X:Sound(SND.Ring, 0.27, { vol = 0.3, speed = 1.0 })
	end,
}

-- 10 ───────────────────────────────────────────────── SINGULARITY
E.singularity = {
	Init = function(X)
		local P = V3(0, 1.18, 0.32)
		local S = { P = P, pts = X:Sample(300) }
		S.pt = X:Glow({ Color = C(232, 220, 255), Image = TEX.Core, Streak = 0.4, Brightness = 5 })
		S.warp = X:Ball({ Color = C(184, 160, 255) })
		S.pop = X:Ring({ Color = C(216, 200, 255), Thick = 0.03 })
		X:At(0.02, function()
			for _ = 1, 40 do
				local a, r = R(X, 0, 6.28), R(X, 0.8, 2.6)
				local p = V3(math.cos(a) * r, 0.04, math.sin(a) * r * 0.8)
				local tang = V3(-math.sin(a), 0, math.cos(a)) * R(X, 0.6, 1.4)
				X:Shard({ kind = "dark", p = p, v = tang + V3(0, R(X, 1.0, 2.2), 0), life = 0.6, size = R(X, 0.02, 0.045), g = 0, drag = 0.3, bounce = false, attract = R(X, 14, 24), swirl = 4, to = P, shrinkAt = 0.7, color = C(60, 56, 72), delay = R(X, 0, 0.1) })
			end
		end)
		X:At(0.47, function()
			sparks(X, P, 50, { C(224, 208, 255), C(96, 64, 255) }, { speed = { 0.3, 1.5 }, life = { 0.25, 0.5 }, drag = 2 })
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local form, pull = seg(t, 0, 0.08), seg(t, 0.05, 0.46)
		B.Pinch, B.PinchC, B.Bias, B.Swirl = ease.inQuad(pull), S.P, -0.95, 5.5 * pull
		B.GlowColor, B.Glow = C(154, 120, 255), 0.45 * pull
		B.OutlineColor, B.Outline = C(220, 210, 255), pull
		B.Diss, B.DissMode, B.DissC, B.Edge = seg(t, 0.32, 0.46) * 1.05, 3, S.P, C(224, 208, 255)
		S.warp:Set(S.P, if t < 0.46 then 0.08 + 0.12 * form + 0.1 * pull else 0.3 * (1 - ease.inCubic(seg(t, 0.46, 0.5))), if t < 0.5 then form else 0)
		S.pt:Set(S.P, if t < 0.46 then 0.1 + 0.12 * form + 0.15 * pull else 0.5 * (1 - seg(t, 0.46, 0.52)), if t < 0.46 then 1 else 1 - seg(t, 0.46, 0.55))
		local kp = seg(t, 0.47, 0.62)
		S.pop:Set(S.P, 0.05 + 0.7 * ease.outCubic(kp), if t > 0.47 then 1 - kp else 0, "cam")
		if t > 0.05 and t < 0.45 and X:Tick("st", 30) and #S.pts > 0 then
			for _ = 1, 12 do
				local s = pick(X, S.pts)
				local d = S.P - s.p
				local tang = V3(-d.Z, 0, d.X)
				local v = d.Unit * 1.4 + (if tang.Magnitude > 1e-3 then tang.Unit else V3()) * 0.8
				X:Burst(s.p, 1, { noAmp = true, tex = TEX.Glow, color = { pick(X, { C(176, 144, 255), C(106, 140, 255), C(240, 232, 255) }), C(64, 32, 255) }, size = { 0.03, 0.004 }, life = { 0.25, 0.32 }, speed = { d.Magnitude * 3, d.Magnitude * 3.4 }, dir = v, spread = 6, stretch = 2.5, bright = 3 })
			end
			X:Burst(S.P, 6, { noAmp = true, shape = "inward", r = 1.8, tex = TEX.Glow, color = { C(138, 122, 255), W1 }, size = { 0.025, 0.01 }, life = { 0.3, 0.32 }, speed = { 5.5, 6 }, stretch = 2.5, bright = 3 })
		end
		X:Light(1, S.P, C(160, 128, 255), 3 * pull + 8 * env(t, 0.46, 0.47, 0.6), 8)
		X:Flash(C(224, 216, 255), 0.15 * env(t, 0.46, 0.465, 0.55))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.4, speed = 0.6, len = 0.9 })
		X:Sound(SND.Ring, 0.46, { vol = 0.35, speed = 2.8 })
		X:Sound(SND.Impact, 0.46, { vol = 0.3, speed = 1.6 })
	end,
}

-- 11 ───────────────────────────────────────────────── RIFT
E.rift = {
	Init = function(X)
		local P = V3(0, 1.0, 0.34)
		local S = { P = P, n = 22, slices = {}, jag = {} }
		for i = 1, S.n do
			S.slices[i] = X:Plate({ Shape = Enum.PartType.Block, Material = Enum.Material.Neon, Color = C(14, 0, 28) })
			S.jag[i] = { L = R(X, 0.65, 1.35), R = R(X, 0.65, 1.35), X = R(X, -0.04, 0.04) }
		end
		S.seam = X:Glow({ Color = C(255, 112, 224), Image = TEX.Core, Brightness = 5 })
		S.haze = X:Glow({ Color = C(160, 40, 255), Image = TEX.Glow, Brightness = 2 })
		X:At(0.52, function()
			for _ = 1, 2 do
				X:Burst(P, 60, { box = V3(0.05, 1.8, 0.05), tex = TEX.Glow, color = { C(255, 208, 248), C(160, 32, 255) }, size = { 0.03, 0.005 }, life = { 0.25, 0.5 }, speed = { 1.5, 6 }, drag = 3, stretch = 2, bright = 4 })
			end
			X:Shake(0.3)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local K = ElimFX.K
		local close = ease.inCubic(seg(t, 0.42, 0.52))
		local len = ease.outCubic(seg(t, 0, 0.1)) * 0.86 * (1 - seg(t, 0.47, 0.53))
		local open = ease.outCubic(seg(t, 0.05, 0.2)) * 1.15 * (1 - close)
		local H = 1.4 * len -- half height (m)
		local cam = workspace.CurrentCamera
		local Pw = X:W(S.P)
		local face = CFrame.lookAt(Pw, Vector3.new(cam.CFrame.Position.X, Pw.Y, cam.CFrame.Position.Z))
		local left, right = {}, {}
		local mag = C(255, 64, 208)
		for i = 1, S.n do
			local y0 = -1 + (i - 1) / S.n * 2
			local y1 = -1 + i / S.n * 2
			local ym = (y0 + y1) / 2
			local shape = (1 - math.abs(ym)) ^ 0.7
			local j = S.jag[i]
			local hwL = open * shape * 0.22 * j.L
			local hwR = open * shape * 0.22 * j.R
			local p = S.slices[i]
			if H < 0.01 or open < 0.01 or t > 0.53 then
				p.Transparency = 1
			else
				local w = (hwL + hwR) * K
				local h = (y1 - y0) * H * K * 1.05
				p.Size = V3(math.max(0.02, w), h, 0.05)
				p.CFrame = face * CFrame.new((j.X + (hwR - hwL) / 2) * K, ym * H * K, 0)
				p.Transparency = 0
				p.Color = C(14, 0, 28):Lerp(C(60, 10, 110), 0.5 + 0.5 * math.sin(t * 40 + i))
			end
			-- edge polylines back in body space, drawn as Neon bolts
			local lp = face * CFrame.new((j.X - hwL) * K, ym * H * K, -0.05)
			local rp = face * CFrame.new((j.X + hwR) * K, ym * H * K, -0.05)
			local lo, ro = X.O:PointToObjectSpace(lp.Position) / K, X.O:PointToObjectSpace(rp.Position) / K
			table.insert(left, V3(lo.X, lo.Y, -lo.Z))
			table.insert(right, V3(ro.X, ro.Y, -ro.Z))
		end
		if H > 0.01 and t < 0.53 then
			local top, bot = S.P + V3(0, H, 0), S.P - V3(0, H, 0)
			table.insert(left, 1, bot)
			table.insert(right, 1, bot)
			table.insert(left, top)
			table.insert(right, top)
			X:Bolt(left, 0.014, mag, 1, 1)
			X:Bolt(right, 0.014, mag, 1, 1)
		end
		S.haze:Set(S.P, 1.2 * len + 0.6 * open, 0.6 * open)
		B.Pinch, B.PinchC, B.PinchW, B.Bias = ease.inCubic(seg(t, 0.1, 0.42)), S.P, V3(1, 0.06, 1), -0.2
		B.GlowColor, B.Glow = C(255, 64, 208), 0.35 * seg(t, 0.05, 0.3)
		B.OutlineColor, B.Outline = C(255, 160, 240), seg(t, 0.05, 0.2)
		B.Diss, B.DissMode, B.DissC, B.Edge = seg(t, 0.16, 0.42) * 1.05, 5, S.P, C(255, 128, 232)
		if t < 0.45 and X:Tick("in", 30) then
			for _ = 1, 8 do
				local side = if X.Rng:NextNumber() < 0.5 then -1 else 1
				local y = S.P.Y + R(X, -1.0, 1.1) * len
				local p = V3(side * R(X, 0.3, 1.3), y, S.P.Z + R(X, -0.3, 0.3))
				X:Burst(p, 1, { noAmp = true, tex = TEX.Glow, color = { pick(X, { C(255, 96, 224), C(154, 96, 255), C(255, 224, 255) }), C(96, 0, 255) }, size = { 0.03, 0.006 }, life = { 0.25, 0.3 }, speed = { math.abs(p.X) * 3.2, math.abs(p.X) * 3.6 }, dir = V3(-side, 0, 0), spread = 4, stretch = 2.5, bright = 3 })
			end
		end
		local kz = seg(t, 0.52, 0.66)
		S.seam:Set(S.P, 1.3 * (1 - ease.inQuad(kz)) * 2, if t > 0.52 then 1 - kz else 0, nil, 0.04)
		X:Light(1, S.P, C(255, 80, 216), 6 * open + 10 * env(t, 0.52, 0.525, 0.7), 9)
		X:Flash(C(255, 128, 224), 0.2 * env(t, 0.52, 0.522, 0.6))
	end,
	Sound = function(X)
		X:Sound(SND.Crack, 0, { vol = 0.5, speed = 1.8 })
		X:Sound(SND.Charge, 0.08, { vol = 0.3, speed = 0.7, len = 0.5 })
		X:Sound(SND.Impact, 0.45, { vol = 0.4, speed = 2.2 })
		X:Sound(SND.Boom2, 0.52, { vol = 0.45, speed = 1.3 })
	end,
}

-- 12 ───────────────────────────────────────────────── CATACLYSM
E.cataclysm = {
	Init = function(X)
		local Cc = V3(0, 0.75, 0)
		local S = { Cc = Cc, cracks = {} }
		S.shadow = X:Disc({ Material = Enum.Material.SmoothPlastic, Color = C(4, 0, 0) })
		S.ring = X:Ring({ Color = C(255, 32, 16), Thick = 0.06, Segments = 40 })
		S.ringD = X:Ring({ Color = C(10, 0, 0), Thick = 0.08, Segments = 40 })
		S.core = X:Glow({ Color = C(255, 26, 8), Image = TEX.Glow, Brightness = 3 })
		X:At(0.0, function()
			X:Burst(Cc, 120, { shape = "inward", r = 2.2, tex = TEX.Smoke, color = { C(2, 0, 0), C(40, 0, 0) }, size = { 0.2, 0.08 }, life = { 0.26, 0.3 }, speed = { 7, 8 }, light = 0, bright = 1, alpha = 0.85, delay = 0.06 })
			X:Burst(Cc, 110, { shape = "inward", r = 1.9, tex = TEX.Glow, color = { C(255, 32, 16), C(255, 96, 64) }, size = { 0.035, 0.015 }, life = { 0.24, 0.27 }, speed = { 7, 8 }, stretch = 2.5, bright = 3, delay = 0.08 })
		end)
		X:At(0.28, function()
			for i = 1, 9 do
				local a = i / 9 * math.pi * 2 + R(X, -0.25, 0.25)
				local L = R(X, 1.1, 2.3)
				for _, l in X:Lightning(V3(0, 0.02, 0), V3(math.cos(a) * L, 0.02, math.sin(a) * L), { depth = 4, jag = 0.12, branch = 0.3 }) do
					for k, p in l.pts do l.pts[k] = V3(p.X, 0.02, p.Z) end
					table.insert(S.cracks, l)
				end
			end
			sparks(X, Cc, 140, { C(255, 80, 48), C(96, 0, 0) }, { speed = { 7, 16 }, life = { 0.3, 0.55 }, dir = V3(0, 1, 0), spread = 15, drag = 2.5, stretch = 3 })
			local pts = {}
			for _ = 1, 40 do table.insert(pts, { p = Cc + V3(R(X, -0.3, 0.3), R(X, -0.2, 0.3), R(X, -0.3, 0.3)), n = rdir(X) }) end
			shardBurst(X, pts, { center = Cc - V3(0, 0.45, 0), kind = "metal", speed = { 2.5, 6 }, up = { 2, 6 }, size = { 0.05, 0.11 }, e0 = C(255, 32, 16), e1 = C(20, 4, 4), life = { 0.8, 1.1 }, g = -14, cool = true })
			X:Burst(Cc, 36, { tex = TEX.Smoke, color = { C(16, 4, 4), C(4, 2, 2) }, size = { 0.35, 1.2 }, life = { 0.7, 1.1 }, speed = { 1.5, 4.5 }, light = 0, bright = 1, alpha = 0.8, drag = 2.8 })
			sparks(X, Cc, 110, { C(255, 64, 32), C(64, 0, 0) }, { speed = { 2, 6 }, life = { 0.5, 1.0 }, g = V3(0, -9.8, 0), drag = 1, stretch = 1 })
			X:Shake(0.75)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local c = seg(t, 0, 0.27)
		if t > 0.05 then B.Skin, B.SkinColor = "dark", C(12, 8, 8) end
		B.Flicker, B.FlickerColor = 0.45 * c, C(255, 26, 8)
		B.GlowColor, B.Glow = C(255, 16, 0), 0.2 * c
		B.OutlineColor, B.Outline = C(255, 30, 10), c
		B.Pinch, B.PinchC, B.PinchW, B.Bias = ease.inCubic(seg(t, 0.08, 0.29)), V3(0, 0.35, 0), V3(0.75, 1, 0.75), 0.25
		B.Glitch = 0.015 * c
		S.shadow:Set(V3(0, 0.015, 0), 0.4 + 1.6 * c, 0.85 * c * (1 - seg(t, 0.3, 1.0)))
		S.core:Set(S.Cc, if t < 0.28 then (0.05 + 0.35 * c) * 3 else 1.4 * (1 - seg(t, 0.28, 0.45)) * 3, if t < 0.28 then c else 1 - seg(t, 0.28, 0.45))
		local A = X.Tier.Amp ^ 0.75
		local k = seg(t, 0.28, 0.82)
		local r = (0.2 + 3.6 * ease.outCubic(k)) * A
		S.ring:Set(V3(0, 0.04, 0), r, if t > 0.28 then (1 - k) ^ 1.2 else 0, "h")
		S.ringD:Set(V3(0, 0.035, 0), r * 0.88, if t > 0.28 then 0.8 * (1 - k) else 0, "h")
		X:DrawBolts(S.cracks, 0.014, C(255, 40, 16), 1, (1 - seg(t, 0.3, 1.3)) ^ 1.5)
		X:Dim(0.65 * c * (1 - seg(t, 0.3, 0.8)))
		X:Desat(0.4 * c * (1 - seg(t, 0.28, 0.4)))
		X:Light(1, S.Cc, C(255, 24, 8), 3 * c + 24 * env(t, 0.28, 0.285, 0.8), 12)
		X:Flash(C(255, 32, 16), 0.35 * env(t, 0.28, 0.282, 0.42))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.4, speed = 0.55, len = 0.6 })
		X:Sound(SND.Boom, 0.28, { vol = 1.0, speed = 0.7 })
		X:Sound(SND.Boom2, 0.28, { vol = 0.6, speed = 0.6 })
		X:Sound(SND.Crack, 0.3, { vol = 0.4, speed = 0.8 })
	end,
}

-- 13 ───────────────────────────────────────────────── VOIDBORN
E.voidborn = {
	Init = function(X)
		local S = { pts = X:Sample(300) }
		X:At(0.05, function()
			for _, col in { C(106, 44, 255), C(208, 64, 255), C(48, 72, 255), C(154, 60, 255) } do
				X:Burst(V3(0, 1.0, 0), 3, { noAmp = true, box = V3(0.9, 1.7, 0.5), tex = TEX.Vortex, color = col, size = { 0.8, 1.4 }, life = { 1.1, 1.3 }, speed = { 0.05, 0.3 }, dir = V3(0, 1, 0), spread = 40, bright = 1.4, alpha = 0.45 })
			end
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local d = seg(t, 0.06, 0.5)
		B.Diss, B.DissMode, B.Edge = ease.inOutSine(d) * 1.05, 0, C(192, 96, 255)
		B.GlowColor, B.Glow = C(90, 32, 255), 0.35 * seg(t, 0, 0.1)
		B.OutlineColor, B.Outline = C(200, 140, 255), seg(t, 0, 0.1)
		if t < 0.52 and X:Tick("em", 30) and #S.pts > 0 then
			local pal = { C(122, 60, 255), C(255, 92, 240), C(56, 88, 255), C(176, 112, 255) }
			for _ = 1, 16 do
				local s = pick(X, S.pts)
				local tang = V3(-s.p.Z, 0, s.p.X)
				local dir = s.n * 0.4 + (if tang.Magnitude > 1e-3 then tang.Unit else V3()) * 0.8 + V3(0, 0.6, 0)
				local c = pick(X, pal)
				X:Burst(s.p, 1, { noAmp = true, tex = TEX.Glow, color = { c, C(32, 0, 96) }, size = { 0.035, 0.004 }, life = { 0.5, 0.9 }, speed = { 0.4, 1.2 }, dir = dir, spread = 20, drag = 1.2, g = V3(0, 0.7, 0), bright = 3 })
			end
			for _ = 1, 2 do
				local s = pick(X, S.pts)
				X:Burst(s.p, 1, { noAmp = true, tex = TEX.Spark, color = C(240, 224, 255), size = { 0.06, 0.02 }, life = { 0.4, 0.8 }, speed = { 0.2, 0.4 }, drag = 1, bright = 3 })
			end
			local s = pick(X, S.pts)
			X:Burst(s.p, 2, { noAmp = true, tex = TEX.Smoke, color = { C(12, 0, 24), C(4, 0, 8) }, size = { 0.08, 0.25 }, life = { 0.5, 0.9 }, speed = { 0.2, 0.5 }, light = 0, bright = 1, alpha = 0.5, drag = 1 })
		end
		X:Light(1, V3(0, 1.1, 0), C(122, 60, 255), 4 * env(t, 0, 0.3, 0.9), 10)
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.3, speed = 0.5, len = 1.2 })
		X:Sound(SND.Ring, 0.1, { vol = 0.15, speed = 0.7 })
		X:Sound(SND.Ring, 0.3, { vol = 0.12, speed = 0.9 })
	end,
}

-- 14 ───────────────────────────────────────────────── EVENT HORIZON
E.horizon = {
	Init = function(X)
		local P = V3(0, 1.2, 0.5)
		local S = { P = P, pts = X:Sample(300), spin = 0 }
		S.hole = X:Ball({ Material = Enum.Material.Neon, Color = C(0, 0, 0) })
		S.disks = {
			X:Ring({ Color = C(255, 244, 224), Thick = 0.05, Segments = 40, Pattern = true }),
			X:Ring({ Color = C(255, 150, 40), Thick = 0.08, Segments = 44, Pattern = true }),
			X:Ring({ Color = C(190, 40, 10), Thick = 0.09, Segments = 48, Pattern = true }),
		}
		S.photon = X:Ring({ Color = C(255, 220, 160), Thick = 0.025, Segments = 36 })
		S.flash = X:Ring({ Color = C(255, 224, 176), Thick = 0.03 })
		S.halo = X:Glow({ Color = C(255, 138, 48), Image = TEX.Glow, Brightness = 1.5 })
		X:At(0.58, function()
			sparks(X, P, 110, { C(255, 224, 176), C(255, 80, 16) }, { speed = { 2, 7 }, life = { 0.25, 0.45 } })
			X:Shake(0.35)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local form = ease.outCubic(seg(t, 0, 0.12))
		local col = ease.inCubic(seg(t, 0.44, 0.58))
		local rbh = 0.17 * form * (1 - col)
		local dr = 0.62 * form * (1 - col * 0.92)
		local A = X.Tier.Amp ^ 0.45
		S.hole:Set(S.P, rbh * A, if t < 0.58 then 1 else 0)
		S.spin += dt * (6 + 30 * col)
		for i, r in S.disks do
			r.Spin = S.spin * (1.6 - i * 0.35)
			r:Set(S.P, (rbh * 1.6 + dr * (0.3 + 0.32 * i)) * A, if t < 0.58 then form * (1.05 - i * 0.18) else 0, 1.0)
		end
		S.photon:Set(S.P, rbh * 1.35 * A, if t < 0.58 then form else 0, "cam")
		S.halo:Set(S.P, dr * 3 * A, if t < 0.58 then 0.3 * form else 0)
		local kf = seg(t, 0.58, 0.75)
		S.flash:Set(S.P, (0.05 + 1.4 * ease.outCubic(kf)) * A, if t > 0.58 then 1 - kf else 0, "cam")
		B.Pinch, B.PinchC, B.Bias, B.Swirl = ease.inCubic(seg(t, 0.06, 0.45)), S.P, -0.6, 3.5
		B.GlowColor, B.Glow = C(255, 122, 32), 0.35 * seg(t, 0.05, 0.3)
		B.OutlineColor, B.Outline = C(255, 190, 110), seg(t, 0.05, 0.2)
		B.Diss, B.DissMode, B.DissC, B.Edge = seg(t, 0.14, 0.45) * 1.05, 3, S.P, C(255, 176, 96)
		if t < 0.5 and X:Tick("m", 30) and #S.pts > 0 then
			for _ = 1, 12 do
				local s = pick(X, S.pts)
				local d = S.P - s.p
				local tang = V3(-d.Z, 0, d.X)
				local v = d.Unit * 1.2 + (if tang.Magnitude > 1e-3 then tang.Unit else V3()) * 0.9
				X:Burst(s.p, 1, { noAmp = true, tex = TEX.Glow, color = { pick(X, { C(255, 224, 176), C(255, 138, 48) }), C(255, 48, 0) }, size = { 0.03, 0.005 }, life = { 0.3, 0.38 }, speed = { d.Magnitude * 2.6, d.Magnitude * 3 }, dir = v, spread = 6, stretch = 2.5, bright = 3 })
			end
		end
		X:Light(1, S.P, C(255, 138, 48), 5 * form * (1 - col) + 10 * env(t, 0.58, 0.585, 0.75), 9)
		X:Flash(C(255, 208, 160), 0.2 * env(t, 0.58, 0.582, 0.68))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.4, speed = 0.45, len = 1.0 })
		X:Sound(SND.Warn, 0.2, { vol = 0.1, speed = 0.6, len = 0.4 })
		X:Sound(SND.Ring, 0.58, { vol = 0.35, speed = 2.4 })
		X:Sound(SND.Boom2, 0.58, { vol = 0.5, speed = 1.1 })
	end,
}

-- 15 ───────────────────────────────────────────────── ASCENSION
E.ascension = {
	Init = function(X)
		local S = { pts = X:Sample(400) }
		S.beam = X:Pillar({ Color = C(255, 240, 200) })
		S.halo = X:Ring({ Color = C(255, 224, 160), Thick = 0.04 })
		X:At(0.45, function()
			X:Burst(V3(0, 1.8, 0), 120, { box = V3(0.3, 0.4, 0.3), tex = TEX.Glow, color = { C(255, 250, 240), C(255, 176, 64) }, size = { 0.035, 0.006 }, life = { 0.3, 0.5 }, speed = { 10, 20 }, dir = V3(0, 1, 0), spread = 4, drag = 0.5, stretch = 4, bright = 4 })
			X:Burst(V3(0, 1.1, 0), 40, { box = V3(1.2, 1.8, 0.8), tex = TEX.Spark, color = { C(255, 232, 176), C(255, 160, 48) }, size = { 0.06, 0.02 }, life = { 0.6, 1.0 }, speed = { 0.05, 0.3 }, g = V3(0, -0.35, 0), drag = 1, bright = 3 })
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local g = seg(t, 0, 0.08)
		B.GlowColor, B.Glow = C(255, 240, 200), 0.8 * g
		B.OutlineColor, B.Outline = W1, g
		B.Flicker, B.FlickerColor = 0.3 * g, C(255, 236, 190)
		B.Diss, B.DissMode, B.Edge = ease.inOutSine(seg(t, 0.07, 0.46)) * 1.05, 1, C(255, 230, 160)
		B.Lift = 0.1 * seg(t, 0.1, 0.46)
		local band = (B.Diss / 0.82) * 1.95 * 0.85
		if t > 0.07 and t < 0.47 and X:Tick("st", 40) then
			local n = 0
			for _, s in S.pts do
				if math.abs(s.p.Y - band) < 0.12 and X.Rng:NextNumber() < 0.4 then
					X:Burst(s.p, 1, { noAmp = true, tex = TEX.Glow, color = { C(255, 248, 232), C(255, 176, 64) }, size = { 0.03, 0.004 }, life = { 0.25, 0.4 }, speed = { 7, 15 }, dir = V3(-s.p.X * 0.5, 1, -s.p.Z * 0.5), spread = 3, drag = 0.4, stretch = 4, bright = 4 })
					n += 1
					if n > 18 then break end
				end
			end
		end
		local bw = 0.3 * (1 - 0.85 * seg(t, 0.35, 0.7))
		S.beam:Set(V3(0, 0, 0), bw, 12, 0.6 * env(t, 0.02, 0.12, 0.85))
		S.halo:Set(V3(0, 2.2, 0), 0.25 + 0.5 * ease.outCubic(seg(t, 0.05, 0.6)), env(t, 0.05, 0.2, 0.7), 0.3)
		X:Light(1, V3(0, 1.3, 0.3), C(255, 224, 160), 7 * env(t, 0, 0.1, 0.7), 10)
		X:Flash(C(255, 240, 208), 0.18 * env(t, 0.44, 0.45, 0.6))
	end,
	Sound = function(X)
		X:Sound(SND.Ring, 0, { vol = 0.25, speed = 0.8 })
		X:Sound(SND.Charge, 0.05, { vol = 0.35, speed = 1.8, len = 0.6 })
		X:Sound(SND.Ring, 0.45, { vol = 0.3, speed = 1.6 })
	end,
}

-- 16 ───────────────────────────────────────────────── FRACTURE
E.fracture = {
	Init = function(X)
		local P = V3(0, 1.0, 0.05)
		local S = { P = P, panes = {}, cracks = {} }
		local n = 46
		local ga = math.pi * (3 - math.sqrt(5))
		for i = 0, n - 1 do
			local y = 1 - (i / (n - 1)) * 2
			local r = math.sqrt(1 - y * y)
			local d = V3(math.cos(ga * i) * r, y, math.sin(ga * i) * r)
			if d.Y > -0.75 then
				local p = X:Plate({ Shape = Enum.PartType.Block, Material = Enum.Material.Glass, Color = C(24, 40, 90) })
				local sb = Instance.new("SelectionBox")
				sb.Adornee = p
				sb.Color3 = C(216, 236, 255)
				sb.LineThickness = 0.03
				sb.SurfaceTransparency = 1
				sb.Transparency = 1
				sb.Parent = p
				table.insert(S.panes, { P = p, SB = sb, D = d, Roll = R(X, 0, 6.28), Size = R(X, 0.42, 0.62), Delay = X.Rng:NextNumber() * 0.12 + (if d.Z < 0 then 0.04 else 0), Axis = rdir(X), Spin = R(X, 1.5, 4.5), Appear = X.Rng:NextNumber() * 0.06 })
			end
		end
		for _ = 1, 14 do
			local d = rdir(X)
			d = V3(d.X, d.Y, math.abs(d.Z) + 0.2).Unit
			for _, l in X:Lightning(P + rdir(X) * 0.2, P + d * 1.35, { depth = 3, jag = 0.12, branch = 0.3 }) do table.insert(S.cracks, l) end
		end
		S.core = X:Ball({ Material = Enum.Material.Neon, Color = C(0, 0, 0) })
		S.rim = X:Ball({ Color = C(216, 236, 255) })
		S.impact = X:Glow({ Color = C(216, 236, 255), Image = TEX.Core, Streak = 0.8, Brightness = 5 })
		X:At(0.53, function()
			local pts = {}
			for _ = 1, 36 do table.insert(pts, { p = P + rdir(X) * 0.1, n = rdir(X) }) end
			shardBurst(X, pts, { center = P, kind = "crystal", speed = { 1.5, 4 }, up = { 0, 0.8 }, size = { 0.02, 0.05 }, life = { 0.5, 0.8 }, g = -3, drag = 1.2, bounce = false, color = C(224, 240, 255) })
			sparks(X, P, 100, { C(240, 248, 255), C(80, 128, 255) }, { speed = { 1.5, 6 }, life = { 0.2, 0.45 } })
			X:Shake(0.4)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local K = ElimFX.K
		X:DrawBolts(S.cracks, 0.006, C(224, 240, 255), ease.outCubic(seg(t, 0, 0.07)), if t < 0.2 then 1 - seg(t, 0.1, 0.2) else 0)
		local A = X.Tier.Amp ^ 0.45
		local Pw = X:W(S.P)
		for _, p in S.panes do
			local ap = seg(t, p.Appear, p.Appear + 0.05)
			local k = ease.inCubic(seg(t, 0.1 + p.Delay, 0.42 + p.Delay * 0.15))
			if ap <= 0 or t > 0.5 or k >= 0.999 then
				p.P.Transparency = 1
				p.SB.Transparency = 1
			else
				local dW = X:WDir(p.D)
				local pos = Pw + dW * 1.35 * K * A * (1 - k)
				local sc = math.max(0.02, (1 - 0.9 * k)) * p.Size * K * A
				p.P.Size = V3(sc, sc, 0.04)
				p.P.CFrame = CFrame.lookAt(pos, pos + dW) * CFrame.Angles(0, 0, p.Roll) * CFrame.fromAxisAngle(p.Axis, p.Spin * k)
				p.P.Transparency = 1 - 0.7 * ap
				p.SB.Transparency = 1 - ap * (0.5 + 0.5 * (1 - seg(t, 0.06, 0.2)))
			end
		end
		B.Pinch, B.PinchC, B.Bias, B.Swirl = ease.inCubic(seg(t, 0.14, 0.44)), S.P, 0.3, 1.5
		B.Flicker, B.FlickerColor = 0.35 * seg(t, 0, 0.08), C(208, 232, 255)
		B.OutlineColor, B.Outline = C(208, 232, 255), seg(t, 0, 0.08)
		local cr = 0.28 * seg(t, 0.3, 0.44) * (1 - ease.inCubic(seg(t, 0.46, 0.53)))
		S.core:Set(S.P, cr, if t < 0.53 then 1 else 0)
		S.rim:Set(S.P, cr * 1.15, if t < 0.53 then 0.8 else 0)
		S.impact:Set(S.P, if t < 0.53 then 0.7 * (1 - seg(t, 0, 0.12)) + 0.01 else 1.4 * (1 - seg(t, 0.53, 0.68)), if t < 0.53 then 1 - seg(t, 0.1, 0.13) else 1 - seg(t, 0.53, 0.68))
		X:Light(1, S.P, C(208, 232, 255), 6 * env(t, 0, 0.02, 0.15) + 3 * seg(t, 0.1, 0.44) + 10 * env(t, 0.53, 0.535, 0.75), 10)
		X:Flash(C(224, 240, 255), 0.25 * env(t, 0, 0.01, 0.08) + 0.2 * env(t, 0.53, 0.532, 0.62))
	end,
	Sound = function(X)
		X:Sound(SND.Crack, 0, { vol = 0.7, speed = 1.9 })
		X:Sound(SND.Ring, 0.02, { vol = 0.25, speed = 2.2 })
		X:Sound(SND.Charge, 0.1, { vol = 0.3, speed = 0.9, len = 0.45 })
		X:Sound(SND.Boom2, 0.53, { vol = 0.55, speed = 1.2 })
		X:Sound(SND.Crack, 0.53, { vol = 0.4, speed = 2.4 })
	end,
}

-- 17 ───────────────────────────────────────────────── APOCALYPSE
E.apocalypse = {
	Init = function(X)
		local Cc = V3(0, 1.1, 0)
		local S = { Cc = Cc, src = {}, dl = {}, arcs = {}, domeArcs = {}, domeR = 0.2 }
		for i = 1, 11 do
			local a = i / 11 * 6.28 + R(X, -0.2, 0.2)
			S.src[i] = Cc + V3(math.cos(a) * R(X, 1.8, 2.5), R(X, -0.9, 1.4), math.sin(a) * R(X, 1.2, 2.0))
			S.dl[i] = R(X, 0, 0.07)
		end
		S.core = X:Glow({ Color = C(188, 216, 255), Image = TEX.Core, Streak = 1, Brightness = 5 })
		S.dome = X:Ball({ Color = C(150, 190, 255) })
		S.ring = X:Ring({ Color = C(200, 224, 255), Thick = 0.05, Segments = 44 })
		S.col = X:Pillar({ Color = C(208, 228, 255) })
		X:At(0.27, function()
			sparks(X, Cc, 300, { C(232, 242, 255), C(42, 88, 255) }, { speed = { 8, 19 }, life = { 0.35, 0.7 }, drag = 3.5, stretch = 3 })
			shardBurst(X, X:Sample(30), { center = Cc, kind = "metal", speed = { 4, 8 }, size = { 0.03, 0.06 }, e0 = C(128, 176, 255), e1 = C(20, 24, 32), life = { 0.6, 0.9 }, cool = true })
			X:Burst(Cc, 2, { noAmp = true, tex = TEX.Shock, color = C(200, 224, 255), size = { 0.6, 6 }, life = { 0.5, 0.5 }, speed = { 0, 0 }, bright = 3 })
			X:Shake(0.85)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local conv = seg(t, 0, 0.25)
		if X:Tick("b", 30) then
			S.arcs = {}
			if t < 0.27 then
				for i, p in S.src do
					for _, l in X:Lightning(p, S.Cc, { depth = 4, jag = 0.2, branch = 0.3, w = 1.5 }) do l.i = i; table.insert(S.arcs, l) end
				end
			end
			S.domeArcs = {}
			if t > 0.28 and t < 0.62 then
				for _ = 1, 6 do
					local a, e = R(X, 0, 6.28), R(X, 0.15, 1.2)
					local p1 = V3(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e)) * S.domeR
					local a2, e2 = a + R(X, -0.6, 0.6), math.max(0.05, e + R(X, -0.5, 0.5))
					local p2 = V3(math.cos(a2) * math.cos(e2), math.sin(e2), math.sin(a2) * math.cos(e2)) * S.domeR
					for _, l in X:Lightning(p1, p2, { depth = 3, jag = 0.25, branch = 0.2 }) do table.insert(S.domeArcs, l) end
				end
			end
			S.fl = 0.6 + 0.4 * X.Rng:NextNumber()
		end
		for _, b in S.arcs do
			local d0 = S.dl[b.i] or 0
			local f = ease.outCubic(seg(t, d0, d0 + 0.16))
			if f > 0 then X:Bolt(b.pts, 0.016 * b.w, C(168, 204, 255), f, 1) end
		end
		X:DrawBolts(S.domeArcs, 0.012, C(200, 224, 255), 1, 1 - seg(t, 0.4, 0.62))
		B.Pinch, B.PinchC, B.Bias = ease.inCubic(seg(t, 0.06, 0.26)), S.Cc, 0.5
		B.GlowColor, B.Glow = C(192, 220, 255), 0.8 * conv * (S.fl or 1)
		B.Flicker, B.FlickerColor = 0.5 * conv, C(224, 240, 255)
		if conv > 0.7 then B.Skin, B.SkinColor = "neon", C(214, 232, 255) end
		S.core:Set(S.Cc, (if t < 0.27 then 0.1 + 0.5 * conv * (S.fl or 1) else 2.5 * (1 - seg(t, 0.27, 0.45)) ^ 2) * 1.6, if t < 0.27 then 1 else 1 - seg(t, 0.27, 0.45))
		local A = X.Tier.Amp ^ 0.75
		local k = seg(t, 0.28, 0.82)
		S.domeR = (0.2 + 4.2 * ease.outExpo(k)) * A
		S.dome:Set(V3(0, 0, 0), S.domeR, if t > 0.28 then 0.75 * (1 - k) ^ 1.5 else 0)
		S.ring:Set(V3(0, 0.04, 0), S.domeR * 1.08, if t > 0.28 then (1 - k) ^ 1.1 else 0, "h")
		local kc = seg(t, 0.28, 0.55)
		S.col:Set(V3(0, 0, 0), 0.35 * (1 - kc) + 0.01, 6, env(t, 0.27, 0.29, 0.55))
		if t < 0.27 and (S.fl or 0) > 0.85 then X:Desat(0.6 * conv) else X:Desat(0.18 * conv) end
		X:Light(1, S.Cc, C(168, 204, 255), 5 * conv * (S.fl or 1) + 30 * env(t, 0.27, 0.28, 0.85), 14)
		X:Flash(C(232, 242, 255), 0.7 * env(t, 0.26, 0.272, 0.36))
	end,
	Sound = function(X)
		for i = 0, 6 do X:Sound(SND.Warn, i * 0.035, { vol = 0.15, speed = 2 + i * 0.25, len = 0.2 }) end
		X:Sound(SND.Charge, 0, { vol = 0.4, speed = 1.7, len = 0.5 })
		X:Sound(SND.Boom, 0.27, { vol = 1.0, speed = 0.75 })
		X:Sound(SND.Boom2, 0.29, { vol = 0.6, speed = 0.8 })
		X:Sound(SND.Crack, 0.3, { vol = 0.4, speed = 1.2 })
	end,
}

-- 18 ───────────────────────────────────────────────── PRISM
E.prism = {
	Init = function(X)
		local S = { pts = X:Sample(220), ghosts = {}, rays = {} }
		for i = 1, 30 do S.rays[i] = { d = rdir(X), L = R(X, 0.35, 1), h = (i - 1) / 30 } end
		X:At(0.1, function()
			for i, c in { C(255, 42, 42), C(42, 255, 90), C(58, 90, 255) } do S.ghosts[i] = X:Ghost(c) end
		end)
		X:At(0.26, function()
			shardBurst(X, X:Sample(140), {
				center = V3(0, 1.12, 0), kind = "crystal", speed = { 1.2, 4.6 }, size = { 0.03, 0.07 }, life = { 0.7, 1.05 }, up = { 0.5, 2 }, normal = 0.6, shrinkAt = 0.55,
				scale = function() return V3(R(X, 0.5, 1), R(X, 1, 2.2), R(X, 0.4, 0.8)) end,
				color = function(s) s.h = X.Rng:NextNumber(); return hsv(s.h * 0.85) end,
				velFn = function(v, s) local band = math.floor((s.h or 0) * 6); return CFrame.Angles(0, (band - 2.5) * 0.22, 0):VectorToWorldSpace(v) + V3(0, (2.5 - band) * 0.35, 0) end,
			})
			for i = 0, 6 do
				sparks(X, V3(0, 1.12, 0), 40, { hsv(i / 7), hsv(i / 7 + 0.05) }, { speed = { 3, 11 }, life = { 0.25, 0.55 }, drag = 3.5, stretch = 2.5 })
			end
			X:Shake(0.35)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local Cc = V3(0, 1.12, 0)
		local ir = seg(t, 0, 0.1)
		local hue = hsv(t * 2.2)
		if ir > 0.3 then B.Skin, B.SkinColor = "glass", hue:Lerp(W1, 0.45) end
		B.GlowColor, B.Glow = hue, 0.45 * ir + 0.3 * seg(t, 0.16, 0.26)
		B.OutlineColor, B.Outline = hsv(t * 2.2 + 0.5), ir
		if t < 0.26 and X:Tick("sp", 40) and #S.pts > 0 then
			for _ = 1, 3 do
				local s = pick(X, S.pts)
				X:Burst(s.p + s.n * 0.01, 1, { noAmp = true, tex = TEX.Spark, color = hsv(X.Rng:NextNumber()), size = { 0.06, 0.02 }, life = { 0.16, 0.16 }, speed = { 0, 0 }, bright = 4 })
			end
		end
		local split = ease.inQuad(seg(t, 0.1, 0.26))
		for i, g in S.ghosts do
			g:Set(V3((i - 2) * 0.22 * split, (if i == 2 then 0.06 else 0) * split, 0), if t < 0.26 then 0.55 * split else 0)
		end
		local A = X.Tier.Amp ^ 0.75
		if t > 0.12 and t < 0.6 then
			local scale = (0.4 + (if t < 0.26 then 0.9 * seg(t, 0.12, 0.26) else 0.9 + 2.6 * ease.outCubic(seg(t, 0.26, 0.6)))) * A
			local inner = if t < 0.26 then 0.2 else 0.2 + 0.6 * seg(t, 0.26, 0.6)
			local al = env(t, 0.12, 0.27, 0.6) * 0.9
			local rot = seg(t, 0.12, 0.6) * 0.6
			for _, r in S.rays do
				local d = CFrame.Angles(0, rot, 0):VectorToWorldSpace(r.d)
				X:Bolt({ Cc + d * scale * r.L * inner, Cc + d * scale * r.L }, 0.016, hsv(r.h), 1, al)
			end
		end
		X:Light(1, Cc, hue, 3 * seg(t, 0, 0.2) + 10 * env(t, 0.26, 0.265, 0.6), 10)
		X:Flash(W1, 0.22 * env(t, 0.26, 0.262, 0.36))
	end,
	Sound = function(X)
		X:Sound(SND.Ring, 0, { vol = 0.25, speed = 1.4 })
		X:Sound(SND.Ring, 0.1, { vol = 0.2, speed = 1.9 })
		X:Sound(SND.Crack, 0.26, { vol = 0.65, speed = 2.0 })
		X:Sound(SND.Ring, 0.27, { vol = 0.35, speed = 2.5 })
	end,
}

-- 19 ───────────────────────────────────────────────── ANTIMATTER
E.antimatter = {
	Init = function(X)
		local P = V3(0, 1.2, 0.48)
		local S = { P = P, cr = {}, j = V3(), js = 1, rays = {} }
		S.core = X:Ball({ Material = Enum.Material.Neon, Color = C(0, 0, 0) })
		S.rim = X:Ball({ Color = C(255, 255, 255) })
		S.haze = X:Glow({ Color = C(255, 16, 16), Image = TEX.Glow, Brightness = 2 })
		S.rW = X:Ring({ Color = W1, Thick = 0.025, Segments = 40 })
		S.rR = X:Ring({ Color = C(255, 24, 16), Thick = 0.045, Segments = 40 })
		S.rK = X:Ring({ Color = C(0, 0, 0), Thick = 0.08, Segments = 40 })
		S.shell = X:Ball({ Color = C(255, 64, 64) })
		for i = 1, 14 do S.rays[i] = rdir(X) end
		X:At(0.33, function()
			sparks(X, P, 220, { W1, C(255, 32, 32) }, { speed = { 6, 16 }, life = { 0.25, 0.5 }, drag = 3.5, stretch = 3 })
			sparks(X, P, 120, { C(255, 48, 32), C(64, 0, 0) }, { speed = { 2, 6 }, life = { 0.4, 0.75 }, drag = 2, g = V3(0, -4, 0), stretch = 1 })
			X:Burst(P, 36, { tex = TEX.Smoke, color = { C(0, 0, 0), C(0, 0, 0) }, size = { 0.15, 0.5 }, life = { 0.6, 0.95 }, speed = { 1, 3.5 }, light = 0, bright = 1, alpha = 0.85, drag = 2.5 })
			X:Shake(0.7)
		end)
		return S
	end,
	Update = function(X, t, dt, S)
		local B = X.B
		local form, un = ease.outCubic(seg(t, 0, 0.14)), seg(t, 0.12, 0.33)
		if X:Tick("j", 30) then
			S.j = V3(X.Rng:NextNumber(-1, 1), X.Rng:NextNumber(-1, 1), X.Rng:NextNumber(-1, 1)) * 0.03 * un
			S.js = 1 + (X.Rng:NextNumber() - 0.5) * 0.7 * un
			S.sp = X.Rng:NextNumber() < 0.55 * un
			S.inv = un > 0.35 and X.Rng:NextNumber() < 0.12
			S.rot = X.Rng:NextNumber() * 6.28
			S.cr = {}
			if t < 0.33 then
				for _ = 1, 2 + math.floor(5 * un) do
					local d = rdir(X)
					for _, l in X:Lightning(S.P + d * 0.15, S.P + (d + rdir(X) * 0.5).Unit * R(X, 0.3, 0.7), { depth = 3, jag = 0.35, branch = 0.2 }) do table.insert(S.cr, l) end
				end
			end
		end
		local cp = S.P + S.j
		local cr = if t < 0.33 then 0.2 * form * S.js else 0
		S.core:Set(cp, cr, if t < 0.33 then 1 else 0)
		S.rim:Set(cp, cr * 1.22, if t < 0.33 then 0.9 else 0)
		S.haze:Set(S.P, (0.4 + 0.6 * un) * 3, if t < 0.33 then form * (0.3 + 0.4 * un) else 0)
		if S.sp and t < 0.33 then
			local L = (0.3 + 0.9 * un)
			for _, d in S.rays do
				local dd = CFrame.Angles(0, S.rot or 0, 0):VectorToWorldSpace(d)
				X:Bolt({ cp + dd * cr, cp + dd * L }, 0.008, W1, 1, 1)
			end
		end
		X:DrawBolts(S.cr, 0.009, if X.Rng:NextNumber() < 0.5 then C(255, 32, 24) else W1, 1, 1)
		if form > 0.3 then B.Skin, B.SkinColor = "dark", C(6, 6, 8) end
		B.OutlineColor, B.Outline = W1, form
		B.GlowColor, B.Glow = W1, 0.12 * form
		B.Flicker, B.FlickerColor = 0.3 * un, W1
		B.Pinch, B.PinchC, B.Bias = ease.inCubic(seg(t, 0.12, 0.33)), S.P, -0.4
		B.Glitch = 0.04 * un
		B.Diss, B.DissMode, B.Edge = seg(t, 0.2, 0.33) * 1.05, 0, W1
		local inv = (t >= 0.33 and t < 0.37) or (S.inv and t < 0.33)
		if inv then X:Contrast(1.2); X:Desat(1) end
		local kW, kR, kK = seg(t, 0.33, 0.62), seg(t, 0.34, 0.75), seg(t, 0.35, 0.9)
		local A = X.Tier.Amp ^ 0.75
		S.rW:Set(S.P, (0.1 + 3.2 * ease.outExpo(kW)) * A, if t > 0.33 then 1 - kW else 0, "cam")
		S.rR:Set(S.P, (0.1 + 2.6 * ease.outCubic(kR)) * A, if t > 0.34 then 1 - kR else 0, "cam")
		S.rK:Set(S.P, (0.1 + 2.1 * ease.outCubic(kK)) * A, if t > 0.35 then 0.9 * (1 - kK) else 0, "cam")
		local ks = seg(t, 0.33, 0.7)
		S.shell:Set(S.P, (0.1 + 2.4 * ease.outQuart(ks)) * A, if t > 0.33 then 0.7 * (1 - ks) ^ 1.5 else 0)
		X:Light(1, S.P, C(255, 32, 32), 4 * un * S.js, 8)
		X:Light(2, S.P, W1, 26 * env(t, 0.37, 0.375, 0.7), 14)
		X:Flash(W1, 0.45 * env(t, 0.37, 0.372, 0.5))
	end,
	Sound = function(X)
		X:Sound(SND.Charge, 0, { vol = 0.35, speed = 0.5, len = 0.5 })
		for i = 0, 6 do X:Sound(SND.Warn, 0.12 + i * 0.028, { vol = 0.15, speed = 2.5 + (i % 2), len = 0.1 }) end
		X:Sound(SND.Ring, 0.33, { vol = 0.4, speed = 3.0 })
		X:Sound(SND.Boom, 0.36, { vol = 1.0, speed = 0.8 })
		X:Sound(SND.Boom2, 0.36, { vol = 0.5, speed = 1.4 })
	end,
}

return E
