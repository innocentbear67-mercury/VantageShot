-- AKit: Live Fire-style arena builders (body + cap blocks, ramps, frames, shell, spawn base). Bind to Kit.
local A = {}
local K
local M = Enum.Material
local V = Vector3.new
local P = {}
function A.bind(k) K = k end
function A.pal(p) P = p A.P = p end
local function soft(c) return K.st(M.SmoothPlastic, c, "VS_Soft") end
local function plain(c) return K.st(M.SmoothPlastic, c) end
local function neon(c) return K.st(M.Neon, c, nil, { ns = true }) end
A.soft, A.plain, A.neon = soft, plain, neon
local function capH(h) if h <= 6 then return 1 elseif h <= 22 then return 2 else return 3 end end
local function ng(p) if p then p:SetAttribute("NoGrapple", true) end return p end
A.ng = ng
function A.blk(x0, x1, z0, z1, y0, h, name, o)
	o = o or {}
	name = name or "Block"
	local c = o.cap or capH(h)
	if o.nocap then c = 0 end
	local b = K.box(x0, x1, y0, y0 + h - c, z0, z1, soft(o.col or P.body), name)
	local cp
	if c > 0 then cp = K.box(x0, x1, y0 + h - c, y0 + h, z0, z1, soft(o.capCol or P.cap), name .. "_Cap") end
	if o.ng then ng(b) ng(cp) end
	return b, cp
end
function A.plat(x0, x1, z0, z1, y0, h, name) return A.blk(x0, x1, z0, z1, y0, h, name or "Platform", { capCol = P.floor, cap = 1 }) end
function A.ramp(x0, x1, z0, z1, y0, y1, dir, name, col) return K.ramp(x0, x1, z0, z1, y0, y1, dir, soft(col or P.cap), name or "Ramp") end
function A.slab(x0, x1, z0, z1, y0, y1, name, col) return K.box(x0, x1, y0, y1, z0, z1, soft(col or P.cap), name or "Slab") end
-- gate frame: posts at both ends of the long horizontal axis + beam
function A.frame(x0, x1, z0, z1, y0, h, t, name)
	t = t or 4
	local s = soft(P.cap)
	name = name or "Frame"
	if (x1 - x0) >= (z1 - z0) then
		K.box(x0, x0 + t, y0, y0 + h, z0, z1, s, name) K.box(x1 - t, x1, y0, y0 + h, z0, z1, s, name)
	else
		K.box(x0, x1, y0, y0 + h, z0, z0 + t, s, name) K.box(x0, x1, y0, y0 + h, z1 - t, z1, s, name)
	end
	K.box(x0, x1, y0 + h - t, y0 + h, z0, z1, s, name)
end
function A.cyl(x, z, y0, h, d, name, o)
	o = o or {}
	name = name or "Column"
	local c = o.cap or 2
	local b = K.vcyl(x, z, y0, y0 + h - c, d, soft(o.col or P.body), name)
	local cp = K.vcyl(x, z, y0 + h - c, y0 + h, d + (o.lip or 0.6), soft(o.capCol or P.cap), name .. "_Cap")
	if o.ng then ng(b) ng(cp) end
	return b, cp
end
-- striped cylinder (lighthouses, chimneys)
function A.stripes(x, z, y0, h, d, step, c1, c2, name, ngf)
	local i = 0
	for y = y0, y0 + h - 0.01, step do
		local p = K.vcyl(x, z, y, math.min(y + step, y0 + h), d, soft(i % 2 == 0 and c1 or c2), name or "Stripe")
		if ngf then ng(p) end
		i += 1
	end
end
-- wall along X (z0..z1 thickness) with door gaps {a0,a1,doorH}
function A.wallX(x0, x1, z0, z1, y0, h, doors, name, o)
	o = o or {}
	name = name or "Wall"
	local cuts = { x0 }
	table.sort(doors or {}, function(p, q) return p[1] < q[1] end)
	local a = x0
	for _, d in ipairs(doors or {}) do
		if d[1] > a then A.blk(a, d[1], z0, z1, y0, h, name, o) end
		local dh = d[3] or 12
		if dh < h then A.blk(d[1], d[2], z0, z1, y0 + dh, h - dh, name .. "_Lintel", o) end
		a = d[2]
	end
	if x1 > a then A.blk(a, x1, z0, z1, y0, h, name, o) end
end
function A.wallZ(x0, x1, z0, z1, y0, h, doors, name, o)
	o = o or {}
	name = name or "Wall"
	table.sort(doors or {}, function(p, q) return p[1] < q[1] end)
	local a = z0
	for _, d in ipairs(doors or {}) do
		if d[1] > a then A.blk(x0, x1, a, d[1], y0, h, name, o) end
		local dh = d[3] or 12
		if dh < h then A.blk(x0, x1, d[1], d[2], y0 + dh, h - dh, name .. "_Lintel", o) end
		a = d[2]
	end
	if z1 > a then A.blk(x0, x1, a, z1, y0, h, name, o) end
end
-- hall: four walls (thickness t) with doors per face, optional roof slab
function A.hall(x0, x1, z0, z1, y0, h, t, doors, name, roof)
	doors = doors or {}
	A.wallX(x0, x1, z0, z0 + t, y0, h, doors.S, name)
	A.wallX(x0, x1, z1 - t, z1, y0, h, doors.N, name)
	A.wallZ(x0, x0 + t, z0 + t, z1 - t, y0, h, doors.W, name)
	A.wallZ(x1 - t, x1, z0 + t, z1 - t, y0, h, doors.E, name)
	if roof then A.slab(x0, x1, z0, z1, y0 + h, y0 + h + 2, (name or "Hall") .. "_Roof", P.body) end
end
-- floor slab, top at y
function A.floor(x0, x1, z0, z1, y, name, col)
	return K.box(x0, x1, y - 6, y, z0, z1, soft(col or P.floor), name or "Floor")
end
-- perimeter shell outside the box; heights per side {S,N,W,E}
function A.shell(x0, x1, z0, z1, h, o)
	o = o or {}
	local hs = o.h or {}
	local t = 4
	local wc, pc = P.wall or P.body, P.trim or P.cap
	local sides = {
		S = { x0 - t, x1 + t, z0 - t, z0, "x" }, N = { x0 - t, x1 + t, z1, z1 + t, "x" },
		W = { x0 - t, x0, z0, z1, "z" }, E = { x1, x1 + t, z0, z1, "z" },
	}
	for k, s in pairs(sides) do
		local hh = hs[k] or h
		if hh > 0 then
			ng(K.box(s[1], s[2], 0, hh - 2, s[3], s[4], soft(wc), "Shell" .. k))
			ng(K.box(s[1], s[2], hh - 2, hh, s[3], s[4], soft(pc), "ShellTrim" .. k))
			local L = s[5] == "x" and (s[2] - s[1]) or (s[4] - s[3])
			local n = math.max(1, math.floor(L / 96))
			for i = 1, n - 1 do
				local a = (s[5] == "x" and s[1] or s[3]) + L * i / n
				local out = (k == "S" or k == "W") and -1 or 1
				if s[5] == "x" then
					local zz = out < 0 and s[3] or s[4]
					ng(K.box(a - 4, a + 4, 0, hh + 2, math.min(zz, zz + out * 3), math.max(zz, zz + out * 3), soft(P.body), "Pilaster"))
				else
					local xx = out < 0 and s[1] or s[2]
					ng(K.box(math.min(xx, xx + out * 3), math.max(xx, xx + out * 3), 0, hh + 2, a - 4, a + 4, soft(P.body), "Pilaster"))
				end
			end
		end
	end
end
-- spawn base (Blue, back wall at zb, facing +z), centred on cx, floor y0. Returns gameplay points.
function A.base(cx, zb, y0, tpl, folder)
	local S = K.S
	y0 = y0 or 0
	-- side blocks (non-grapple) form the courtyard
	A.blk(cx - 72, cx - 40, zb, zb + 64, y0, 24, "BaseSide", { ng = true })
	A.blk(cx + 40, cx + 72, zb, zb + 64, y0, 24, "BaseSide", { ng = true })
	K.box(cx - 40, cx + 40, y0, y0 + 0.08, zb, zb + 64, soft(P.body), "CourtFloor")
	-- gate wall with two doors (12 tall), team-lit frames
	A.wallX(cx - 40, cx + 40, zb + 64, zb + 72, y0, 16, { { cx - 28, cx - 12, 12 }, { cx + 12, cx + 28, 12 } }, "GateWall", { ng = true })
	for _, d in ipairs({ { cx - 28, cx - 12 }, { cx + 12, cx + 28 } }) do
		K.box(d[1] - 0.5, d[1] + 0.5, y0, y0 + 12, zb + 72, zb + 72.6, "teamGlow", "DoorFrameL")
		K.box(d[2] - 0.5, d[2] + 0.5, y0, y0 + 12, zb + 72, zb + 72.6, "teamGlow", "DoorFrameR")
		K.box(d[1] - 0.5, d[2] + 0.5, y0 + 12, y0 + 12.8, zb + 72, zb + 72.6, "teamGlow", "DoorFrameT")
	end
	K.box(cx - 10, cx + 10, y0 + 4, y0 + 9, zb + 72, zb + 72.3, "teamPanel", "TeamStripe")
	-- canopy
	A.slab(cx - 14, cx + 14, zb, zb + 26, y0 + 12, y0 + 14, "Canopy")
	for _, x in ipairs({ cx - 12, cx + 12 }) do K.box(x - 2, x + 2, y0, y0 + 12, zb + 22, zb + 26, soft(P.body), "CanopyPost") end
	-- flag plinth + covers
	A.slab(cx - 4, cx + 4, zb + 92, zb + 100, y0, y0 + 1, "FlagPlinth")
	A.blk(cx - 24, cx - 16, zb + 102, zb + 118, y0, 6, "FlagCover")
	A.blk(cx + 16, cx + 24, zb + 102, zb + 118, y0, 6, "FlagCover")
	-- shields
	local function shield(x0, x1, ya, yb, z0, z1, tr)
		local p = tpl:Clone()
		p.Size = V(x1 - x0, yb - ya, z1 - z0)
		p.CFrame = CFrame.new(K.O + V((x0 + x1) / 2, (ya + yb) / 2, (z0 + z1) / 2))
		p.Transparency = tr p.Color = K.BLUE
		p:SetAttribute("Team", "Blue") p:SetAttribute("NoGrapple", true) p:SetAttribute("TeamKey", "gteam")
		game:GetService("CollectionService"):AddTag(p, "SpawnShield")
		p.Parent = K.cur()
		return p
	end
	shield(cx - 28, cx - 12, y0, y0 + 12, zb + 67, zb + 69, 0.6)
	shield(cx + 12, cx + 28, y0, y0 + 12, zb + 67, zb + 69, 0.6)
	shield(cx - 40, cx + 40, y0 + 16, y0 + 24, zb + 70, zb + 72, 0.85)
	shield(cx - 40, cx + 40, y0 + 24, y0 + 26, zb, zb + 72, 0.85)
	local spawns = {}
	for i = 0, 7 do table.insert(spawns, V(cx - 35 + i * 10, y0 + 0.3, zb + 30)) end
	return { spawns = spawns, bot = V(cx, y0 + 0.5, zb + 84), flag = V(cx, y0 + 1.5, zb + 96) }
end
return A
