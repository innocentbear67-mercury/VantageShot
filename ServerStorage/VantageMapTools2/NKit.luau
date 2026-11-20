-- NKit: modern downtown builders for Meridian (Hypershot style). Bind to Kit with I.bind(K).
local I = {}
local K
local V = Vector3.new
local M = Enum.Material
function I.bind(k) K = k end
local rnd = Random.new(11)
function I.seed(n) rnd = Random.new(n) end
local function c(r, g, b) return Color3.fromRGB(r, g, b) end
local function soft(col) return K.st(M.SmoothPlastic, col, "VS_Soft") end
local function plain(col) return K.st(M.SmoothPlastic, col) end
local function neon(col) return K.st(M.Neon, col, nil, { ns = true }) end
local function glass(col, t) return K.st(M.Glass, col, nil, { t = t or 0.35, r = 0.12 }) end
local function deco(col) return K.st(M.SmoothPlastic, col, nil, { nc = true }) end
I.soft, I.plain, I.neon, I.glass, I.deco = soft, plain, neon, glass, deco
I.C = {
	white = c(246, 246, 242), off = c(234, 232, 226), concrete = c(216, 216, 212), floor = c(204, 206, 208), grey = c(172, 176, 182),
	dark = c(98, 104, 114), asphalt = c(84, 88, 98), navy = c(46, 56, 78), glass = c(156, 210, 238), glassDeep = c(88, 150, 206),
	coral = c(242, 98, 86), lime = c(150, 214, 72), orange = c(250, 150, 48), yellow = c(252, 200, 40), teal = c(40, 182, 192),
	purple = c(160, 96, 240), pink = c(255, 86, 170), sky = c(120, 190, 255), wood = c(196, 146, 98), leaf = c(118, 206, 98),
	leaf2 = c(84, 174, 86), water = c(80, 196, 236), sand = c(236, 222, 190), black = c(32, 34, 40), red = c(226, 56, 56),
	warm = c(255, 222, 170), mint = c(150, 230, 200), cream = c(250, 238, 214),
}
local C = I.C
local function fbox(b, f, a0, a1, y0, y1, d0, d1, s, name)
	if f == "S" then return K.box(a0, a1, y0, y1, b.z0 - d1, b.z0 - d0, s, name)
	elseif f == "N" then return K.box(a0, a1, y0, y1, b.z1 + d0, b.z1 + d1, s, name)
	elseif f == "W" then return K.box(b.x0 - d1, b.x0 - d0, y0, y1, a0, a1, s, name)
	else return K.box(b.x1 + d0, b.x1 + d1, y0, y1, a0, a1, s, name) end
end
local function fpt(b, f, a, y, d)
	if f == "S" then return V(a, y, b.z0 - d) elseif f == "N" then return V(a, y, b.z1 + d)
	elseif f == "W" then return V(b.x0 - d, y, a) else return V(b.x1 + d, y, a) end
end
local NS = { S = "-z", N = "+z", W = "-x", E = "+x" }
local function span(b, f) if f == "S" or f == "N" then return b.x0, b.x1 end return b.z0, b.z1 end
I.fbox, I.fpt, I.NS, I.span = fbox, fpt, NS, span
function I.wall(b, f, y0, y1, t, s, holes, name)
	local a0, a1 = span(b, f)
	local cuts = { a0, a1 }
	for _, h in ipairs(holes or {}) do
		table.insert(cuts, math.clamp(h[1], a0, a1)); table.insert(cuts, math.clamp(h[2], a0, a1))
	end
	table.sort(cuts)
	for i = 1, #cuts - 1 do
		local u0, u1 = cuts[i], cuts[i + 1]
		if u1 - u0 > 0.05 then
			local ys = {}
			for _, h in ipairs(holes or {}) do
				if h[1] < u1 - 0.05 and h[2] > u0 + 0.05 then table.insert(ys, h) end
			end
			table.sort(ys, function(p, q) return p[3] < q[3] end)
			local y = y0
			for _, h in ipairs(ys) do
				if h[3] > y + 0.05 then fbox(b, f, u0, u1, y, h[3], -t, 0, s, name or "Wall") end
				if h[5] then fbox(b, f, u0, u1, h[3], h[4], -t * 0.65, -t * 0.35, h[5], "Pane") end
				y = math.max(y, h[4])
			end
			if y1 > y + 0.05 then fbox(b, f, u0, u1, y, y1, -t, 0, s, name or "Wall") end
		end
	end
end
function I.fins(b, f, a0, a1, y0, y1, bay, s, depth, w)
	local n = math.max(1, math.floor((a1 - a0) / bay + 0.5))
	w = w or 0.5
	for k = 0, n do
		local a = a0 + (a1 - a0) * k / n
		fbox(b, f, a - w / 2, a + w / 2, y0, y1, 0, depth or 0.6, s or plain(C.white), "Fin")
	end
end
function I.band(b, f, a0, a1, y0, y1, d0, d1, s, name)
	return fbox(b, f, a0, a1, y0, y1, d0 or 0, d1 or 0.4, s, name or "Band")
end
function I.windowStrip(b, f, a0, a1, y0, y1, bay)
	fbox(b, f, a0, a1, y0, y1, 0, 0.15, plain(C.glass), "Window")
	I.fins(b, f, a0, a1, y0, y1, bay or 6, plain(C.white), 0.45, 0.4)
	fbox(b, f, a0 - 0.3, a1 + 0.3, y0 - 0.5, y0, 0, 0.7, plain(C.white), "Sill")
	fbox(b, f, a0 - 0.3, a1 + 0.3, y1, y1 + 0.4, 0, 0.5, plain(C.white), "Head")
end
function I.doorFrame(b, f, a0, a1, y0, y1, s)
	s = s or plain(C.navy)
	fbox(b, f, a0 - 0.6, a0, y0, y1 + 0.6, -0.2, 0.4, s, "DoorFrame")
	fbox(b, f, a1, a1 + 0.6, y0, y1 + 0.6, -0.2, 0.4, s, "DoorFrame")
	fbox(b, f, a0 - 0.6, a1 + 0.6, y1, y1 + 0.6, -0.2, 0.4, s, "DoorFrame")
end
function I.block(o)
	local b = { x0 = o.x0, x1 = o.x1, z0 = o.z0, z1 = o.z1 }
	local y0, h = o.y0 or 0, o.h
	local core = K.box(o.x0, o.x1, y0, y0 + h, o.z0, o.z1, soft(o.col or C.white), o.name or "Block")
	if o.ng then core:SetAttribute("NoGrapple", true) end
	if o.base then K.box(o.x0 - 0.4, o.x1 + 0.4, y0, y0 + 2, o.z0 - 0.4, o.z1 + 0.4, soft(o.base), "Plinth") end
	for f, sp in pairs(o.faces or {}) do
		local a0, a1 = span(b, f)
		local m = sp.margin or 2
		for _, st in ipairs(sp.strips or {}) do
			I.windowStrip(b, f, (st[3] or a0 + m), (st[4] or a1 - m), y0 + st[1], y0 + st[2], sp.bay)
		end
		if sp.curtain then
			local cu = sp.curtain
			fbox(b, f, a0 + m, a1 - m, y0 + cu[1], y0 + cu[2], 0, 0.2, plain(C.glass), "Curtain")
			I.fins(b, f, a0 + m, a1 - m, y0 + cu[1], y0 + cu[2], sp.bay or 6, plain(C.white), 0.7, 0.6)
			for y = y0 + cu[1] + (cu[3] or 8), y0 + cu[2] - 1, (cu[3] or 8) do
				fbox(b, f, a0 + m, a1 - m, y - 0.4, y + 0.4, 0, 0.5, plain(C.white), "Spandrel")
			end
		end
		for _, bd in ipairs(sp.bands or {}) do
			fbox(b, f, a0 - 0.2, a1 + 0.2, y0 + bd[1], y0 + bd[2], 0, 0.5, bd[3] and plain(bd[3]) or soft(C.navy), "Band")
		end
		if sp.sign then
			local sg = sp.sign
			K.facadeSign(fpt(b, f, sg.a, y0 + sg.y, 0.3), NS[f], sg.w, sg.h, sg.text, sg.glow and neon(sg.bg or C.navy) or plain(sg.bg or C.navy), sg.fg or C.white, nil, sg.glow)
		end
	end
	if o.roof ~= false then
		local r = o.roof or {}
		local ph = r.parapet or 2.4
		local top = y0 + h
		local pc = soft(r.col or o.col or C.white)
		K.box(o.x0, o.x1, top, top + ph, o.z0, o.z0 + 0.8, pc, "Parapet")
		K.box(o.x0, o.x1, top, top + ph, o.z1 - 0.8, o.z1, pc, "Parapet")
		K.box(o.x0, o.x0 + 0.8, top, top + ph, o.z0 + 0.8, o.z1 - 0.8, pc, "Parapet")
		K.box(o.x1 - 0.8, o.x1, top, top + ph, o.z0 + 0.8, o.z1 - 0.8, pc, "Parapet")
		local cs = plain(r.cap or C.navy)
		K.box(o.x0 - 0.3, o.x1 + 0.3, top + ph, top + ph + 0.4, o.z0 - 0.3, o.z0 + 0.8, cs, "Coping")
		K.box(o.x0 - 0.3, o.x1 + 0.3, top + ph, top + ph + 0.4, o.z1 - 0.8, o.z1 + 0.3, cs, "Coping")
		K.box(o.x0 - 0.3, o.x0 + 0.8, top + ph, top + ph + 0.4, o.z0 + 0.8, o.z1 - 0.8, cs, "Coping")
		K.box(o.x1 - 0.8, o.x1 + 0.3, top + ph, top + ph + 0.4, o.z0 + 0.8, o.z1 - 0.8, cs, "Coping")
		for i = 1, (r.hvac or 0) do
			local x = rnd:NextNumber(o.x0 + 5, math.max(o.x0 + 5.1, o.x1 - 5))
			local z = rnd:NextNumber(o.z0 + 5, math.max(o.z0 + 5.1, o.z1 - 5))
			I.hvac(x, z, top)
		end
	end
	return b, core
end
function I.hvac(x, z, y)
	K.box(x - 3, x + 3, y, y + 3.4, z - 2.2, z + 2.2, plain(C.grey), "HVAC")
	K.box(x - 3.2, x + 3.2, y + 3.4, y + 3.8, z - 2.4, z + 2.4, plain(C.dark), "HVACLid")
	local p = K.vcyl(x - 1.3, z, y + 3.8, y + 4.0, 2.6, plain(C.black), "Fan")
	K.vcyl(x + 1.5, z, y + 3.8, y + 4.0, 2.2, plain(C.black), "Fan")
	for k = -1, 1 do K.box(x - 3.05, x + 3.05, y + 1 + k * 0.8, y + 1.25 + k * 0.8, z - 2.3, z + 2.3, plain(C.dark), "Grille") end
	return p
end
function I.duct(a, b, d, s)
	K.cyl(a, b, d or 2.2, s or plain(C.white), "Duct")
end
local function lp(base, size, off, s, name) return K.part(size, base * CFrame.new(off), s, name) end
local function wheel(base, off, d)
	local p = K.part(V(1.3, d, d), base * CFrame.new(off), plain(C.black), "Wheel")
	p.Shape = Enum.PartType.Cylinder
	K.part(V(1.35, d * 0.5, d * 0.5), base * CFrame.new(off), plain(C.grey), "Hub").Shape = Enum.PartType.Cylinder
end
function I.car(x, z, y0, rot, col, kind)
	local base = CFrame.new(x, y0, z) * CFrame.Angles(0, rot or 0, 0)
	local L, W = 14, 6.4
	lp(base, V(W, 2.6, L), V(0, 2.1, 0), plain(col), "CarBody")
	lp(base, V(W - 0.8, 2.2, L * 0.5), V(0, 4.5, -0.8), plain(c(64, 96, 140)), "CarGlass")
	lp(base, V(W - 0.5, 0.35, L * 0.48), V(0, 5.7, -0.8), plain(col), "CarRoof")
	for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do wheel(base, V(sx * (W / 2 - 0.5), 1.4, sz * (L / 2 - 2.8)), 2.8) end end
	lp(base, V(W - 1.2, 0.6, 0.2), V(-0, 2.9, L / 2 + 0.05), neon(c(255, 250, 230)), "Headlight")
	lp(base, V(W - 1.2, 0.5, 0.2), V(0, 2.9, -L / 2 - 0.05), neon(C.red), "Taillight")
	lp(base, V(W + 0.1, 0.5, L + 0.1), V(0, 1.0, 0), plain(C.dark), "Skirt")
	if kind == "taxi" then
		lp(base, V(2.6, 1.0, 1.4), V(0, 6.4, -0.8), neon(C.yellow), "TaxiSign")
		lp(base, V(W + 0.05, 0.6, L * 0.8), V(0, 2.6, 0), plain(C.black), "Checker")
	end
end
function I.bus(x, z, rot, col, route)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, rot or 0, 0)
	local L, W, H = 40, 9, 11
	lp(base, V(W, H - 2, L), V(0, 1.5 + (H - 2) / 2, 0), plain(col), "BusBody")
	lp(base, V(W + 0.1, 3.4, L - 4), V(0, 6.6, -1), plain(c(52, 78, 116)), "BusWindows")
	lp(base, V(W + 0.12, 0.6, L - 4), V(0, 8.6, -1), plain(C.white), "BusStripe")
	lp(base, V(W - 0.6, 3.6, 0.2), V(0, 7.0, L / 2 + 0.05), plain(c(52, 78, 116)), "Windscreen")
	lp(base, V(W - 1, 1.2, 0.3), V(0, 9.7, L / 2 + 0.05), plain(C.black), "DestBox")
	local s = K.sign(base * CFrame.new(0, 9.7, L / 2 + 0.25) * CFrame.lookAt(V(), V(0, 0, 1)), V(W - 1.4, 1.0, 0.1), route or "42 MERIDIAN", neon(C.black), C.orange, nil, true)
	s.Name = "BusSign"
	lp(base, V(W - 0.4, 0.6, L - 0.4), V(0, H - 0.3, 0), plain(C.white), "BusRoof")
	lp(base, V(4, 1.2, 8), V(0, H + 0.6, -6), plain(C.grey), "BusAC")
	for _, sz in ipairs({ -1, 1 }) do for _, sx in ipairs({ -1, 1 }) do wheel(base, V(sx * (W / 2 - 0.6), 1.7, sz * (L / 2 - 6)), 3.4) end end
	lp(base, V(W + 0.2, 0.6, L + 0.2), V(0, 1.6, 0), plain(C.dark), "Bumper")
	lp(base, V(W - 2, 0.5, 0.2), V(0, 3.0, L / 2 + 0.1), neon(c(255, 250, 230)), "Headlight")
end
function I.foodTruck(x, z, rot, col, text, accent)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, rot or 0, 0)
	local W = 8
	lp(base, V(W, 6, 6), V(0, 4.6, 8), plain(C.white), "Cab")
	lp(base, V(W - 0.6, 2.4, 0.2), V(0, 6.0, 11.05), plain(c(52, 78, 116)), "CabGlass")
	lp(base, V(W, 9, 14), V(0, 6.0, -2), plain(col), "Box")
	lp(base, V(W + 0.1, 1.2, 14), V(0, 2.4, -2), plain(accent or C.white), "BoxStripe")
	lp(base, V(0.3, 3.4, 9), V(W / 2 + 0.05, 7.2, -2), plain(C.black), "Hatch")
	lp(base, V(1.6, 0.4, 9.4), V(W / 2 + 0.8, 5.4, -2), plain(C.off), "Counter")
	local aw = lp(base, V(3.4, 0.3, 10), V(W / 2 + 1.6, 9.6, -2), plain(accent or C.orange), "Awning")
	aw.CFrame = aw.CFrame * CFrame.Angles(0, 0, math.rad(-14))
	local s = K.sign(base * CFrame.new(W / 2 + 0.25, 11.6, -2) * CFrame.Angles(0, -math.pi / 2, 0), V(11, 2.2, 0.3), text or "TACOS", neon(accent or C.orange), C.white, nil, true)
	s.Name = "TruckSign"
	for _, sz in ipairs({ -1, 1 }) do for _, sx in ipairs({ -1, 1 }) do wheel(base, V(sx * (W / 2 - 0.5), 1.5, sz == 1 and 8 or -6), 3) end end
	lp(base, V(W + 0.1, 0.8, 22), V(0, 1.6, 1), plain(C.dark), "Chassis")
end
function I.tree(x, z, y0, h, planter)
	h = h or 14
	if planter then
		K.box(x - 3, x + 3, y0, y0 + 2.2, z - 3, z + 3, soft(C.off), "TreePlanter")
		K.box(x - 2.6, x + 2.6, y0 + 2.2, y0 + 2.4, z - 2.6, z + 2.6, plain(c(120, 92, 66)), "Soil")
		y0 = y0 + 2.2
	end
	K.vcyl(x, z, y0, y0 + h * 0.62, 1.3, plain(C.wood), "Trunk")
	local r = h * 0.3
	K.ball(V(x, y0 + h * 0.72, z), r * 2.1, plain(C.leaf), "Leaves")
	K.ball(V(x + r * 0.55, y0 + h * 0.6, z + r * 0.3), r * 1.5, plain(C.leaf2), "Leaves")
	K.ball(V(x - r * 0.5, y0 + h * 0.62, z - r * 0.4), r * 1.4, plain(C.leaf2), "Leaves")
end
function I.shrubRow(x0, x1, z0, z1, y0, h, col)
	K.box(x0, x1, y0, y0 + (h or 2.4), z0, z1, soft(C.off), "Planter")
	local L = math.max(x1 - x0, z1 - z0)
	local n = math.max(1, math.floor(L / 4))
	for k = 0, n - 1 do
		local t = (k + 0.5) / n
		local px = (x1 - x0) >= (z1 - z0) and x0 + (x1 - x0) * t or (x0 + x1) / 2
		local pz = (x1 - x0) >= (z1 - z0) and (z0 + z1) / 2 or z0 + (z1 - z0) * t
		local d = math.min(x1 - x0, z1 - z0) * 0.95
		K.ball(V(px, y0 + (h or 2.4) + d * 0.25, pz), d, plain(col or (k % 2 == 0 and C.leaf or C.leaf2)), "Shrub")
	end
end
function I.bench(x, z, y0, axis)
	local lx, lz = 6, 1.8
	if axis == "z" then lx, lz = 1.8, 6 end
	K.box(x - lx / 2, x + lx / 2, y0 + 1.5, y0 + 2.0, z - lz / 2, z + lz / 2, plain(C.wood), "BenchSeat")
	for _, s in ipairs({ -1, 1 }) do
		if axis == "z" then K.box(x - 0.8, x + 0.8, y0, y0 + 1.5, z + s * 2.4 - 0.3, z + s * 2.4 + 0.3, plain(C.dark), "BenchLeg")
		else K.box(x + s * 2.4 - 0.3, x + s * 2.4 + 0.3, y0, y0 + 1.5, z - 0.8, z + 0.8, plain(C.dark), "BenchLeg") end
	end
end
function I.bollards(a, b, n, y0)
	for k = 0, n - 1 do
		local p = a:Lerp(b, n == 1 and 0.5 or k / (n - 1))
		K.vcyl(p.X, p.Z, y0 or p.Y, (y0 or p.Y) + 2.6, 1.0, plain(C.dark), "Bollard")
		K.vcyl(p.X, p.Z, (y0 or p.Y) + 2.0, (y0 or p.Y) + 2.3, 1.05, neon(C.warm), "BollardLed")
	end
end
function I.lamp(x, z, y0, dir, h, col)
	h = h or 16
	local nv = K.NV[dir]
	K.vcyl(x, z, y0, y0 + 0.6, 1.6, plain(C.dark), "LampBase")
	K.vcyl(x, z, y0, y0 + h, 0.6, plain(C.navy), "LampPole")
	local tip = V(x, y0 + h, z) + nv * 5
	K.cyl(V(x, y0 + h - 0.2, z), tip, 0.5, plain(C.navy), "LampArm").Shape = Enum.PartType.Block
	local mid = V(x, y0 + h - 0.55, z) + nv * 3.2
	local sx, sz = 1.2, 1.2
	if nv.X ~= 0 then sx = 4.6 else sz = 4.6 end
	local lens = K.box(mid.X - sx / 2, mid.X + sx / 2, mid.Y - 0.2, mid.Y + 0.2, mid.Z - sz / 2, mid.Z + sz / 2, neon(col or C.warm), "LampLed")
	K.light(lens, "SpotLight", col or Color3.fromRGB(255, 214, 170), 42, 2.2, Enum.NormalId.Bottom, 130)
	return lens
end
function I.trafficLight(x, z, dir, y0)
	y0 = y0 or 0
	local nv = K.NV[dir]
	K.vcyl(x, z, y0, y0 + 14, 0.7, plain(C.navy), "TLPole")
	local tip = V(x, y0 + 14, z) + nv * 10
	K.cyl(V(x, y0 + 13.6, z), tip, 0.5, plain(C.navy), "TLArm").Shape = Enum.PartType.Block
	K.box(tip.X - 0.9, tip.X + 0.9, y0 + 9.4, y0 + 13.6, tip.Z - 0.9, tip.Z + 0.9, plain(C.black), "TLHead")
	local cols = { C.red, C.yellow, C.lime }
	for k = 1, 3 do
		local y = y0 + 13.6 - k * 1.3
		K.vcyl(tip.X, tip.Z, y - 0.5, y + 0.5, 1.0, k == 3 and neon(c(90, 255, 120)) or plain(cols[k]:Lerp(C.black, 0.45)), "TLLamp")
	end
end
function I.billboard(pos, n, w, h, text, bg, fg, legs)
	local nv = K.NV[n]
	local cf = CFrame.lookAt(pos, pos + nv)
	K.part(V(w + 1.2, h + 1.2, 1.2), cf * CFrame.new(0, 0, 0.7), plain(C.navy), "BillboardFrame")
	local s = K.sign(cf * CFrame.new(0, 0, -0.05), V(w, h, 0.3), text, neon(bg or C.purple), fg or C.white, nil, true)
	s.Name = "Billboard"
	if legs then
		for _, sx in ipairs({ -1, 1 }) do
			local p = (cf * CFrame.new(sx * w * 0.3, 0, 1.6)).Position
			K.box(p.X - 0.6, p.X + 0.6, legs, pos.Y - h / 2, p.Z - 0.6, p.Z + 0.6, plain(C.navy), "BillboardLeg")
		end
	end
	return s
end
function I.umbrella(x, z, y0, col)
	K.vcyl(x, z, y0, y0 + 8, 0.4, plain(C.white), "UmbPole")
	local p = K.vcyl(x, z, y0 + 7.4, y0 + 8.2, 8, plain(col), "UmbTop")
	K.vcyl(x, z, y0 + 8.2, y0 + 8.6, 3, plain(col), "UmbCap")
	return p
end
function I.picnic(x, z, y0, col)
	K.box(x - 3, x + 3, y0 + 2.6, y0 + 3.0, z - 1.6, z + 1.6, plain(C.wood), "Table")
	K.box(x - 0.3, x + 0.3, y0, y0 + 2.6, z - 1, z + 1, plain(C.dark), "TableLeg")
	for _, s in ipairs({ -1, 1 }) do K.box(x - 3, x + 3, y0 + 1.5, y0 + 1.9, z + s * 2.6 - 0.6, z + s * 2.6 + 0.6, plain(C.wood), "Seat") end
	if col then I.umbrella(x, z, y0 + 3, col) end
end
function I.kiosk(x0, x1, z0, z1, y0, h, col, text, face)
	local b = { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
	K.box(x0, x1, y0, y0 + h * 0.45, z0, z1, soft(col), "KioskBase")
	K.box(x0 + 0.4, x1 - 0.4, y0 + h * 0.45, y0 + h * 0.8, z0 + 0.4, z1 - 0.4, glass(C.glass, 0.4), "KioskGlass")
	K.box(x0 - 0.8, x1 + 0.8, y0 + h * 0.8, y0 + h, z0 - 0.8, z1 + 0.8, plain(C.white), "KioskRoof")
	K.box(x0 - 0.9, x1 + 0.9, y0 + h * 0.8 - 0.5, y0 + h * 0.8, z0 - 0.9, z1 + 0.9, neon(col), "KioskGlow")
	if text then
		local f = face or "S"
		local a0, a1 = span(b, f)
		K.facadeSign(fpt(b, f, (a0 + a1) / 2, y0 + h * 0.9, 0.9), NS[f], math.min(a1 - a0 - 1, 14), h * 0.16, text, plain(C.navy), C.white)
	end
	return b
end
function I.glassRail(a, b, y0, h, s)
	local d = b - a
	local len = d.Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(V(mid.X, y0 + h / 2, mid.Z), V(b.X, y0 + h / 2, b.Z))
	K.part(V(0.3, h, len), cf, s or glass(C.glass, 0.45), "GlassRail")
	K.part(V(0.6, 0.4, len), cf * CFrame.new(0, h / 2 + 0.2, 0), plain(C.white), "RailCap")
end
function I.crane(x, z, y0, h, dir, jib, counter)
	local s = plain(C.yellow)
	local w = 5
	for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		K.box(x + sx * w / 2 - 0.35, x + sx * w / 2 + 0.35, y0, y0 + h, z + sz * w / 2 - 0.35, z + sz * w / 2 + 0.35, s, "Mast")
	end end
	local seg = 8
	for y = y0 + seg, y0 + h - 1, seg do
		K.box(x - w / 2, x + w / 2, y - 0.25, y + 0.25, z - w / 2 - 0.2, z - w / 2 + 0.2, s, "Tie")
		K.box(x - w / 2, x + w / 2, y - 0.25, y + 0.25, z + w / 2 - 0.2, z + w / 2 + 0.2, s, "Tie")
		K.box(x - w / 2 - 0.2, x - w / 2 + 0.2, y - 0.25, y + 0.25, z - w / 2, z + w / 2, s, "Tie")
		K.box(x + w / 2 - 0.2, x + w / 2 + 0.2, y - 0.25, y + 0.25, z - w / 2, z + w / 2, s, "Tie")
		for _, sz in ipairs({ -1, 1 }) do
			K.cyl(V(x - w / 2, y - seg, z + sz * w / 2), V(x + w / 2, y, z + sz * w / 2), 0.35, s, "Brace").Shape = Enum.PartType.Block
		end
		for _, sx in ipairs({ -1, 1 }) do
			K.cyl(V(x + sx * w / 2, y - seg, z - w / 2), V(x + sx * w / 2, y, z + w / 2), 0.35, s, "Brace").Shape = Enum.PartType.Block
		end
	end
	local nv = K.NV[dir]
	local top = y0 + h
	K.box(x - 3.2, x + 3.2, top, top + 4, z - 3.2, z + 3.2, plain(C.white), "Slew")
	K.box(x - 1.5, x + 1.5, top + 4, top + 7, z - 2.8, z + 2.8, plain(C.white), "CabinBox")
	local tip = V(x, top + 5, z) + nv * jib
	local back = V(x, top + 5, z) - nv * (counter or 18)
	local side = V(-nv.Z, 0, nv.X)
	for _, s2 in ipairs({ -1, 1 }) do
		K.cyl(V(x, top + 4.4, z) + side * s2 * 1.4, tip + side * s2 * 1.4 - V(0, 0.6, 0), 0.6, s, "JibChord").Shape = Enum.PartType.Block
		K.cyl(V(x, top + 4.4, z) + side * s2 * 1.4, back + side * s2 * 1.4 - V(0, 0.6, 0), 0.6, s, "JibChord").Shape = Enum.PartType.Block
	end
	K.cyl(V(x, top + 7.5, z), tip, 0.5, s, "JibTop").Shape = Enum.PartType.Block
	local n = math.floor(jib / 6)
	for k = 1, n do
		local p = V(x, top + 4.4, z) + nv * (k * 6)
		K.cyl(p - side * 1.4, p + side * 1.4, 0.3, s, "JibRung").Shape = Enum.PartType.Block
	end
	K.box(back.X - 2.5, back.X + 2.5, top + 1, top + 4.6, back.Z - 2.5, back.Z + 2.5, plain(C.grey), "Counterweight")
	K.vcyl(x, z, top + 7, top + 13, 0.8, s, "Apex")
	K.cyl(V(x, top + 13, z), tip, 0.2, plain(C.dark), "Tie")
	K.cyl(V(x, top + 13, z), back, 0.2, plain(C.dark), "Tie")
	local hook = V(x, 0, z) + nv * (jib * 0.6)
	K.cyl(V(hook.X, top + 4, hook.Z), V(hook.X, top - 30, hook.Z), 0.15, plain(C.dark), "Cable")
	K.box(hook.X - 1, hook.X + 1, top - 32, top - 30, hook.Z - 1, hook.Z + 1, plain(C.yellow), "HookBlock")
	return K.ball(V(x, top + 13.6, z), 1, neon(C.red), "AviationLight")
end
function I.tower(x0, x1, z0, z1, y0, h, col, gl, crown)
	local core = K.box(x0, x1, y0, y0 + h, z0, z1, soft(col or C.white), "Tower")
	core.CastShadow = false
	local b = { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
	for _, f in ipairs({ "S", "N", "W", "E" }) do
		local a0, a1 = span(b, f)
		local w = a1 - a0
		local nStrip = math.max(1, math.floor(w / 12))
		for k = 0, nStrip - 1 do
			local s0 = a0 + 2 + (w - 4) * k / nStrip
			local s1 = a0 + 2 + (w - 4) * (k + 1) / nStrip - 1.6
			local p = fbox(b, f, s0, s1, y0 + 4, y0 + h - 4, 0, 0.2, plain(gl or C.glass), "TowerGlass")
			p.CastShadow = false
		end
	end
	if crown then
		K.box(x0 + 2, x1 - 2, y0 + h, y0 + h + 4, z0 + 2, z1 - 2, plain(crown), "Crown").CastShadow = false
	end
	return core
end
return I
