local I = {}
local K
local V = Vector3.new
local M = Enum.Material
function I.bind(k) K = k end
local rnd = Random.new(3)
function I.seed(n) rnd = Random.new(n) end
local function c(r, g, b) return Color3.fromRGB(r, g, b) end
local function soft(col, big) return K.st(M.SmoothPlastic, col, big and "VS_Soft" or nil) end
local function plain(col) return K.st(M.SmoothPlastic, col) end
I.soft, I.plain = soft, plain
I.C = {
	white = c(246, 242, 232), cream = c(250, 234, 206), ochre = c(250, 200, 120), peach = c(250, 178, 140), pink = c(244, 160, 170),
	mint = c(170, 226, 200), sky = c(150, 210, 240), stone = c(232, 218, 190), stoneDark = c(206, 188, 156), terra = c(232, 112, 72),
	terraDark = c(198, 86, 54), azure = c(36, 140, 230), teal = c(30, 170, 170), green = c(70, 160, 110), navy = c(46, 56, 78),
	wood = c(176, 118, 74), leaf = c(110, 200, 96), leaf2 = c(80, 170, 84), olive = c(150, 178, 110), sea = c(36, 186, 214),
	sand = c(246, 222, 166), glass = c(70, 110, 160), yellow = c(255, 206, 70), red = c(232, 70, 64),
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
local NRM = { S = -Vector3.zAxis, N = Vector3.zAxis, W = -Vector3.xAxis, E = Vector3.xAxis }
local NS = { S = "-z", N = "+z", W = "-x", E = "+x" }
I.fbox, I.fpt, I.NRM, I.NS = fbox, fpt, NRM, NS
local function span(b, f) if f == "S" or f == "N" then return b.x0, b.x1 end return b.z0, b.z1 end
function I.archDoor(b, f, a, y, w, h, col, frame)
	fbox(b, f, a - w / 2 - 0.6, a + w / 2 + 0.6, y, y + h, 0, 0.3, soft(frame or C.stone), "DoorSurround")
	local n = NRM[f]
	local top = fpt(b, f, a, y + h, 0.15)
	K.cyl(top - n * 0.15, top + n * 0.15, w + 1.2, soft(frame or C.stone), "ArchSurround")
	fbox(b, f, a - w / 2, a + w / 2, y, y + h, 0.3, 0.45, plain(col or C.wood), "Door")
	local t2 = fpt(b, f, a, y + h, 0.3)
	K.cyl(t2, t2 + n * 0.15, w, plain(col or C.wood), "DoorArch")
	fbox(b, f, a - 0.12, a + 0.12, y, y + h, 0.45, 0.55, plain(C.navy), "DoorSplit")
end
function I.window(b, f, a, y, w, h, shutter)
	fbox(b, f, a - w / 2, a + w / 2, y, y + h, 0, 0.12, plain(C.glass), "Glass")
	fbox(b, f, a - w / 2 - 0.35, a + w / 2 + 0.35, y + h, y + h + 0.5, 0, 0.35, plain(C.white), "Lintel")
	fbox(b, f, a - w / 2 - 0.5, a + w / 2 + 0.5, y - 0.5, y, 0, 0.6, plain(C.white), "Sill")
	fbox(b, f, a - 0.12, a + 0.12, y, y + h, 0.1, 0.25, plain(C.white), "Mullion")
	if shutter then
		fbox(b, f, a - w / 2 - w / 2, a - w / 2 - 0.1, y, y + h, 0, 0.3, plain(shutter), "Shutter")
		fbox(b, f, a + w / 2 + 0.1, a + w / 2 + w / 2, y, y + h, 0, 0.3, plain(shutter), "Shutter")
		for k = 1, math.floor(h / 1.2) do
			local yy = y + k * 1.2 - 0.3
			fbox(b, f, a - w + 0.1, a - w / 2 - 0.2, yy, yy + 0.15, 0.3, 0.38, plain(c(255, 255, 255)), "Louvre")
			fbox(b, f, a + w / 2 + 0.2, a + w - 0.1, yy, yy + 0.15, 0.3, 0.38, plain(c(255, 255, 255)), "Louvre")
		end
	end
end
function I.balcony(b, f, a0, a1, y, depth, pots)
	depth = depth or 2.6
	fbox(b, f, a0, a1, y - 0.6, y, 0, depth, soft(C.white), "BalconySlab")
	fbox(b, f, a0, a1, y - 1.1, y - 0.6, 0, depth - 0.4, plain(C.stoneDark), "Corbel")
	local p0, p1 = fpt(b, f, a0, y, depth - 0.15), fpt(b, f, a1, y, depth - 0.15)
	K.cyl(p0 + V(0, 3.2, 0), p1 + V(0, 3.2, 0), 0.3, plain(C.navy), "Rail")
	local len = (p1 - p0).Magnitude
	local nb = math.max(1, math.floor(len / 1.1))
	for k = 0, nb do
		local p = p0:Lerp(p1, k / nb)
		K.box(p.X - 0.08, p.X + 0.08, y, y + 3.2, p.Z - 0.08, p.Z + 0.08, plain(C.navy), "Baluster")
	end
	for _, s in ipairs({ a0, a1 }) do
		local q0, q1 = fpt(b, f, s, y, 0), fpt(b, f, s, y, depth - 0.15)
		K.cyl(q0 + V(0, 3.2, 0), q1 + V(0, 3.2, 0), 0.3, plain(C.navy), "Rail")
	end
	if pots then
		for k = 1, pots do
			local p = fpt(b, f, a0 + (a1 - a0) * k / (pots + 1), y, depth - 0.7)
			K.vcyl(p.X, p.Z, y, y + 1, 1.1, plain(C.terra), "Pot")
			K.ball(p + V(0, 1.5, 0), 1.5, plain((k % 2 == 0) and C.pink or C.leaf), "Flowers")
		end
	end
end
function I.awning(b, f, a0, a1, y, depth, c1, c2)
	local n = NRM[f]
	local stripes = math.max(2, math.floor((a1 - a0) / 1.6))
	local ang = math.rad(24)
	for k = 0, stripes - 1 do
		local s0 = a0 + (a1 - a0) * k / stripes
		local s1 = a0 + (a1 - a0) * (k + 1) / stripes
		local mid = fpt(b, f, (s0 + s1) / 2, y - math.sin(ang) * depth / 2, math.cos(ang) * depth / 2)
		local cf = CFrame.lookAt(mid, mid + n) * CFrame.Angles(-ang, 0, 0)
		K.part(V(s1 - s0, 0.25, depth), cf, plain((k % 2 == 0) and c1 or c2), "Awning")
	end
	local edge = fpt(b, f, (a0 + a1) / 2, y - math.sin(ang) * depth - 0.4, math.cos(ang) * depth)
	K.part(V(a1 - a0, 0.8, 0.2), CFrame.lookAt(edge, edge + n), plain(c1), "Valance")
end
function I.house(o)
	local b = { x0 = o.x0, x1 = o.x1, z0 = o.z0, z1 = o.z1 }
	local y0, h = o.y0 or 0, o.h
	local col = o.col or C.white
	K.box(o.x0, o.x1, y0 + 2, y0 + h, o.z0, o.z1, soft(col, true), "Walls")
	K.box(o.x0 - 0.3, o.x1 + 0.3, y0, y0 + 2, o.z0 - 0.3, o.z1 + 0.3, soft(C.stone, true), "BaseCourse")
	K.box(o.x0 - 0.5, o.x1 + 0.5, y0 + h - 0.6, y0 + h, o.z0 - 0.5, o.z1 + 0.5, plain(C.white), "Cornice")
	for _, x in ipairs({ o.x0, o.x1 }) do for _, z in ipairs({ o.z0, o.z1 }) do
		for y = y0 + 2, y0 + h - 2, 3 do K.box(x - 0.35, x + 0.35, y, y + 1.4, z - 0.35, z + 0.35, plain(C.stone), "Quoin") end
	end end
	if o.roof == "gable" then
		local ax = o.axis or ((o.x1 - o.x0) >= (o.z1 - o.z0) and "x" or "z")
		local rh = o.roofH or 7
		local tiles = K.st(M.SmoothPlastic, C.terra, "VS_Soft")
		if ax == "x" then
			local half = (o.z1 - o.z0) / 2 + 1
			local ang = math.atan(rh / half)
			local L = math.sqrt(half ^ 2 + rh ^ 2)
			local zc = (o.z0 + o.z1) / 2
			K.part(V(o.x1 - o.x0 + 2, 0.8, L), CFrame.new((o.x0 + o.x1) / 2, y0 + h + rh / 2, zc - half / 2) * CFrame.Angles(-ang, 0, 0), tiles, "Roof")
			K.part(V(o.x1 - o.x0 + 2, 0.8, L), CFrame.new((o.x0 + o.x1) / 2, y0 + h + rh / 2, zc + half / 2) * CFrame.Angles(ang, 0, 0), tiles, "Roof")
			K.box(o.x0 - 1, o.x1 + 1, y0 + h + rh - 0.2, y0 + h + rh + 0.6, zc - 0.6, zc + 0.6, plain(C.terraDark), "Ridge")
			for _, x in ipairs({ o.x0 + 0.3, o.x1 - 0.3 }) do
				K.ramp(x - 0.3, x + 0.3, o.z0, zc, y0 + h, y0 + h + rh, "+z", soft(col, true), "GableEnd")
				K.ramp(x - 0.3, x + 0.3, zc, o.z1, y0 + h, y0 + h + rh, "-z", soft(col, true), "GableEnd")
			end
		else
			local half = (o.x1 - o.x0) / 2 + 1
			local ang = math.atan(rh / half)
			local L = math.sqrt(half ^ 2 + rh ^ 2)
			local xc = (o.x0 + o.x1) / 2
			K.part(V(L, 0.8, o.z1 - o.z0 + 2), CFrame.new(xc - half / 2, y0 + h + rh / 2, (o.z0 + o.z1) / 2) * CFrame.Angles(0, 0, ang), tiles, "Roof")
			K.part(V(L, 0.8, o.z1 - o.z0 + 2), CFrame.new(xc + half / 2, y0 + h + rh / 2, (o.z0 + o.z1) / 2) * CFrame.Angles(0, 0, -ang), tiles, "Roof")
			K.box(xc - 0.6, xc + 0.6, y0 + h + rh - 0.2, y0 + h + rh + 0.6, o.z0 - 1, o.z1 + 1, plain(C.terraDark), "Ridge")
			for _, z in ipairs({ o.z0 + 0.3, o.z1 - 0.3 }) do
				K.ramp(o.x0, xc, z - 0.3, z + 0.3, y0 + h, y0 + h + rh, "+x", soft(col, true), "GableEnd")
				K.ramp(xc, o.x1, z - 0.3, z + 0.3, y0 + h, y0 + h + rh, "-x", soft(col, true), "GableEnd")
			end
		end
	else
		K.box(o.x0, o.x1, y0 + h, y0 + h + 2.4, o.z0, o.z0 + 0.8, soft(col, true), "Parapet")
		K.box(o.x0, o.x1, y0 + h, y0 + h + 2.4, o.z1 - 0.8, o.z1, soft(col, true), "Parapet")
		K.box(o.x0, o.x0 + 0.8, y0 + h, y0 + h + 2.4, o.z0, o.z1, soft(col, true), "Parapet")
		K.box(o.x1 - 0.8, o.x1, y0 + h, y0 + h + 2.4, o.z0, o.z1, soft(col, true), "Parapet")
		K.box(o.x0 - 0.2, o.x1 + 0.2, y0 + h + 2.4, y0 + h + 2.8, o.z0 - 0.2, o.z0 + 1, plain(C.terra), "Coping")
		K.box(o.x0 - 0.2, o.x1 + 0.2, y0 + h + 2.4, y0 + h + 2.8, o.z1 - 1, o.z1 + 0.2, plain(C.terra), "Coping")
		K.box(o.x0 - 0.2, o.x0 + 1, y0 + h + 2.4, y0 + h + 2.8, o.z0 + 1, o.z1 - 1, plain(C.terra), "Coping")
		K.box(o.x1 - 1, o.x1 + 0.2, y0 + h + 2.4, y0 + h + 2.8, o.z0 + 1, o.z1 - 1, plain(C.terra), "Coping")
		K.box(o.x0 + 0.8, o.x1 - 0.8, y0 + h, y0 + h + 0.15, o.z0 + 0.8, o.z1 - 0.8, soft(C.stone, true), "RoofTerrace")
		if o.roofProps ~= false then
			local x, z = rnd:NextNumber(o.x0 + 3, o.x1 - 3), rnd:NextNumber(o.z0 + 3, o.z1 - 3)
			K.vcyl(x, z, y0 + h, y0 + h + 3, 3, plain(C.white), "WaterTank")
			K.box(x - 1.6, x + 1.6, y0 + h + 3, y0 + h + 3.4, z - 1.6, z + 1.6, plain(C.navy), "TankLid")
		end
	end
	local storeys = math.max(1, math.floor((h - 2) / 10))
	for f, spec in pairs(o.faces or {}) do
		local a0, a1 = span(b, f)
		local doorAt = {}
		for _, d in ipairs(spec.doors or {}) do
			I.archDoor(b, f, d[1], y0, d[2] or 4, d[3] or 7, d[4] or (o.door or C.wood))
			doorAt[#doorAt + 1] = d[1]
		end
		local bay = spec.bay or 8
		local n = math.max(1, math.floor((a1 - a0 - 4) / bay))
		for s = 0, storeys - 1 do
			for k = 0, n - 1 do
				local a = a0 + 2 + (a1 - a0 - 4) * (k + 0.5) / n
				local wy = y0 + 4 + s * 10
				local blocked = false
				if s == 0 then for _, da in ipairs(doorAt) do if math.abs(da - a) < 5 then blocked = true end end end
				if spec.noGround and s == 0 then blocked = true end
				if not blocked then I.window(b, f, a, wy, spec.ww or 2.8, spec.wh or 5, o.shutter or C.azure) end
			end
		end
		if spec.balcony then local bl = spec.balcony; I.balcony(b, f, bl[1], bl[2], y0 + 2 + (bl[3] or 1) * 10, bl[4], bl[5] or 3) end
		if spec.awning then local aw = spec.awning; I.awning(b, f, aw[1], aw[2], y0 + 9.5, aw[5] or 4, aw[3] or C.azure, aw[4] or C.white) end
		if spec.sign then
			local sg = spec.sign
			K.facadeSign(fpt(b, f, sg.a, sg.y, 0.2), NS[f], sg.w, sg.h, sg.text, plain(sg.bg or C.navy), sg.fg or C.yellow)
		end
		if spec.lamp then for _, l in ipairs(spec.lamp) do I.wallLantern(fpt(b, f, l[1], l[2], 0), NS[f]) end end
	end
	return b
end
function I.wallLantern(pos, n)
	local nv = K.NV[n]
	K.part(V(0.3, 0.3, 1.4), CFrame.lookAt(pos + nv * 0.6, pos + nv * 2), plain(C.navy), "LanternArm")
	K.ball(pos + nv * 1.4 - V(0, 0.6, 0), 1.2, K.st(M.Neon, c(255, 226, 170), nil, { ns = true }), "LanternGlobe")
	K.box(pos.X + nv.X * 1.4 - 0.5, pos.X + nv.X * 1.4 + 0.5, pos.Y - 0.1, pos.Y + 0.2, pos.Z + nv.Z * 1.4 - 0.5, pos.Z + nv.Z * 1.4 + 0.5, plain(C.navy), "LanternCap")
end
function I.streetLamp(x, z, y0, h)
	h = h or 12
	K.vcyl(x, z, y0, y0 + 0.8, 1.4, plain(C.navy), "LampBase")
	K.vcyl(x, z, y0 + 0.8, y0 + h, 0.45, plain(C.navy), "LampPost")
	local g = K.ball(V(x, y0 + h + 0.8, z), 1.8, K.st(M.Neon, c(255, 232, 186), nil, { ns = true }), "LampGlobe")
	K.vcyl(x, z, y0 + h + 1.6, y0 + h + 2.1, 1.4, plain(C.navy), "LampCap")
	K.light(g, "PointLight", c(255, 214, 160), 18, 1.2)
end
function I.palm(x, z, y0, h, lean)
	h = h or 18; lean = lean or 0.12
	local segs = 6
	local prev = V(x, y0, z)
	local dir = V(math.cos(x + z), 0, math.sin(x + z)) * lean
	for k = 1, segs do
		local t = k / segs
		local p = V(x, y0, z) + V(0, h * t, 0) + dir * h * t * t
		K.cyl(prev, p, 1.3 - 0.35 * t, plain(c(176, 136, 96)), "PalmTrunk")
		K.cyl(p - V(0, 0.15, 0), p + V(0, 0.15, 0), 1.45 - 0.35 * t, plain(c(150, 112, 78)), "PalmRing")
		prev = p
	end
	for k = 0, 7 do
		local a = k * math.pi / 4 + 0.3
		local d = V(math.cos(a), 0, math.sin(a))
		local tip = prev + d * 7 + V(0, -2.4, 0)
		local mid = (prev + tip) / 2 + V(0, 0.9, 0)
		K.part(V(2.2, 0.25, (mid - prev).Magnitude + 0.6), CFrame.lookAt((prev + mid) / 2, mid), plain(C.leaf), "Frond")
		K.part(V(1.8, 0.25, (tip - mid).Magnitude + 0.6), CFrame.lookAt((mid + tip) / 2, tip), plain(C.leaf2), "Frond")
	end
	K.ball(prev - V(0, 0.6, 0), 1.6, plain(c(120, 90, 60)), "Coconuts")
end
function I.olive(x, z, y0, s)
	s = s or 1
	K.vcyl(x, z, y0, y0 + 4 * s, 1.1 * s, plain(c(140, 110, 84)), "OliveTrunk")
	K.ball(V(x, y0 + 6 * s, z), 7 * s, plain(C.olive), "OliveCanopy")
	K.ball(V(x + 2 * s, y0 + 7 * s, z - 1 * s), 4.6 * s, plain(c(170, 196, 128)), "OliveCanopy")
	K.ball(V(x - 2 * s, y0 + 6.6 * s, z + 1.4 * s), 4.2 * s, plain(c(132, 164, 100)), "OliveCanopy")
end
function I.cypress(x, z, y0, h)
	local p = K.part(V(4.2, h, 4.2), CFrame.new(x, y0 + h / 2 + 1, z), plain(c(52, 120, 72)), "Cypress")
	local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Parent = p
	K.vcyl(x, z, y0, y0 + 1.5, 0.7, plain(c(120, 90, 60)), "CypressTrunk")
end
function I.pot(x, z, y0, flower)
	K.vcyl(x, z, y0, y0 + 2.2, 2.4, plain(C.terra), "Pot")
	K.vcyl(x, z, y0 + 2.2, y0 + 2.5, 2.7, plain(C.terraDark), "PotRim")
	K.ball(V(x, y0 + 3.4, z), 2.6, plain(flower or C.leaf), "Shrub")
end
function I.umbrella(x, z, y0, c1)
	K.vcyl(x, z, y0, y0 + 7, 0.3, plain(C.white), "UmbrellaPole")
	K.cyl(V(x, y0 + 7, z), V(x, y0 + 7.6, z), 8, plain(c1 or C.azure), "Umbrella")
	K.cyl(V(x, y0 + 7.6, z), V(x, y0 + 8.4, z), 4, plain(c1 or C.azure), "UmbrellaTop")
	K.cyl(V(x, y0 + 6.7, z), V(x, y0 + 7.0, z), 8.3, plain(C.white), "UmbrellaFringe")
end
function I.cafeSet(x, z, y0)
	K.vcyl(x, z, y0, y0 + 2.6, 0.3, plain(C.navy), "TableLeg")
	K.vcyl(x, z, y0 + 2.6, y0 + 2.8, 2.6, plain(C.white), "TableTop")
	for _, d in ipairs({ { 1.9, 0 }, { -1.9, 0 } }) do
		K.box(x + d[1] - 0.6, x + d[1] + 0.6, y0 + 1.5, y0 + 1.7, z - 0.6, z + 0.6, plain(C.navy), "ChairSeat")
		local bx = x + d[1] + (d[1] > 0 and 0.5 or -0.5)
		K.box(bx - 0.1, bx + 0.1, y0 + 1.7, y0 + 3.4, z - 0.6, z + 0.6, plain(C.navy), "ChairBack")
	end
end
function I.stall(x0, x1, z0, z1, y0, c1, c2)
	K.box(x0, x1, y0, y0 + 3.4, z0, z1, soft(C.wood, true), "StallCounter")
	K.box(x0 - 0.2, x1 + 0.2, y0 + 3.4, y0 + 3.7, z0 - 0.2, z1 + 0.2, plain(C.white), "CounterTop")
	for _, x in ipairs({ x0 + 0.3, x1 - 0.3 }) do for _, z in ipairs({ z0 + 0.3, z1 - 0.3 }) do K.box(x - 0.2, x + 0.2, y0 + 3.4, y0 + 8.5, z - 0.2, z + 0.2, plain(C.navy), "StallPost") end end
	local n = math.max(2, math.floor((x1 - x0) / 1.6))
	for k = 0, n - 1 do
		local a = x0 - 0.6 + (x1 - x0 + 1.2) * k / n
		local b2 = x0 - 0.6 + (x1 - x0 + 1.2) * (k + 1) / n
		K.box(a, b2, y0 + 8.5, y0 + 9.1, z0 - 1.2, z1 + 1.2, plain((k % 2 == 0) and c1 or c2), "StallCanopy")
	end
	local fruit = { c(255, 140, 40), c(240, 70, 60), c(255, 220, 70), c(120, 200, 80) }
	for k = 0, 5 do
		local fx = x0 + 1 + (x1 - x0 - 2) * (k % 3) / 2
		local fz = z0 + 1.2 + (z1 - z0 - 2.4) * math.floor(k / 3)
		K.box(fx - 0.9, fx + 0.9, y0 + 3.7, y0 + 4.4, fz - 0.7, fz + 0.7, plain(C.wood), "Crate")
		K.ball(V(fx, y0 + 4.7, fz), 1.3, plain(fruit[k % 4 + 1]), "Fruit")
	end
end
function I.fountain(x, z, y0, r)
	K.vcyl(x, z, y0, y0 + 2.2, r * 2, soft(C.stone), "FountainRim")
	K.vcyl(x, z, y0 + 2.2, y0 + 2.5, r * 2 + 0.6, plain(C.white), "RimCap")
	K.vcyl(x, z, y0 + 1.2, y0 + 1.9, r * 2 - 1.6, K.st(M.Glass, C.sea, nil, { t = 0.25, r = 0.2 }), "Water")
	K.vcyl(x, z, y0, y0 + 7, 2.6, soft(C.stone), "FountainColumn")
	K.vcyl(x, z, y0 + 7, y0 + 7.8, 8, soft(C.stone), "UpperBowl")
	K.vcyl(x, z, y0 + 7.4, y0 + 7.9, 7, K.st(M.Glass, C.sea, nil, { t = 0.25, r = 0.2 }), "UpperWater")
	K.vcyl(x, z, y0 + 7.8, y0 + 10.5, 1.4, soft(C.stone), "Spout")
	K.ball(V(x, y0 + 11, z), 1.8, plain(C.white), "Finial")
end
function I.boat(x, z, y0, len, rotY, hull, stripe)
	local base = CFrame.new(x, y0, z) * CFrame.Angles(0, rotY or 0, 0)
	local w = len * 0.34
	K.part(V(w, 2.6, len * 0.62), base * CFrame.new(0, 1.3, 0), plain(hull or C.white), "Hull")
	local d = w / math.sqrt(2)
	K.part(V(d, 2.6, d), base * CFrame.new(0, 1.3, -len * 0.31) * CFrame.Angles(0, math.rad(45), 0), plain(hull or C.white), "Bow")
	K.part(V(d, 2.6, d), base * CFrame.new(0, 1.3, len * 0.31) * CFrame.Angles(0, math.rad(45), 0), plain(hull or C.white), "Stern")
	K.part(V(d + 0.1, 0.5, d + 0.1), base * CFrame.new(0, 2.2, -len * 0.31) * CFrame.Angles(0, math.rad(45), 0), plain(stripe or C.azure), "BoatStripe")
	K.part(V(w + 0.1, 0.5, len * 0.62), base * CFrame.new(0, 2.2, 0), plain(stripe or C.azure), "BoatStripe")
	K.part(V(w * 0.7, 2.2, len * 0.22), base * CFrame.new(0, 3.6, len * 0.12), plain(C.white), "Cabin")
	K.part(V(w * 0.72, 0.3, len * 0.24), base * CFrame.new(0, 4.8, len * 0.12), plain(stripe or C.azure), "CabinRoof")
end
function I.lighthouse(x, z, y0, h, d)
	d = d or 9
	K.vcyl(x, z, y0, y0 + 3, d + 6, soft(C.stone), "LighthouseBase")
	local bands = 6
	for k = 0, bands - 1 do
		local a, b2 = y0 + 3 + (h - 3) * k / bands, y0 + 3 + (h - 3) * (k + 1) / bands
		local dd = d - (d * 0.25) * (k / bands)
		K.vcyl(x, z, a, b2, dd, plain((k % 2 == 0) and C.white or C.red), "LighthouseBand")
	end
	local top = y0 + h
	K.vcyl(x, z, top, top + 0.8, d + 2.4, plain(C.navy), "Gallery")
	for k = 0, 11 do
		local a = k * math.pi / 6
		local p = V(x + math.cos(a) * (d / 2 + 0.9), top + 0.8, z + math.sin(a) * (d / 2 + 0.9))
		K.box(p.X - 0.1, p.X + 0.1, top + 0.8, top + 3.6, p.Z - 0.1, p.Z + 0.1, plain(C.navy), "GalleryPost")
	end
	for k = 0, 11 do
		local a0, a1 = k * math.pi / 6, (k + 1) * math.pi / 6
		local r = d / 2 + 0.9
		K.cyl(V(x + math.cos(a0) * r, top + 3.6, z + math.sin(a0) * r), V(x + math.cos(a1) * r, top + 3.6, z + math.sin(a1) * r), 0.3, plain(C.navy), "GalleryRail")
	end
	local lamp = K.vcyl(x, z, top + 0.8, top + 5, d * 0.55, K.st(M.Neon, c(255, 240, 200), nil, { ns = true }), "Lantern")
	K.light(lamp, "PointLight", c(255, 236, 190), 40, 1.6)
	K.vcyl(x, z, top + 5, top + 5.6, d * 0.75, plain(C.red), "LanternCap")
	K.ball(V(x, top + 6.4, z), d * 0.45, plain(C.red), "LanternDome")
end
return I
