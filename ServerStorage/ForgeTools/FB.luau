-- ForgeTools.FB : walls with openings, truss roofs
local FK = require(script.Parent.FK)
local FB = {}
FB.FK = FK
local V, C = Vector3.new, Color3.fromRGB
local FY = FK.FY

-- axis "x": runs along X r0..r1, thickness spans Z c0..c1.  axis "z": runs along Z, thickness spans X.
-- ops: { {a, b, y0, y1, kind = "gate"|"door"|"window", barrier = bool}, ... }
-- o: name, style, rampart = {lo=bool, hi=bool}, noface = {lo=bool, hi=bool}, line = {lo=style, hi=style}, lit = {lo=bool, hi=bool}
function FB.wall(parent, axis, c0, c1, r0, r1, H, ops, o)
	o = o or {}
	ops = ops or {}
	local m = FK.folder(parent, o.name or "Wall")
	local det = FK.folder(m, "Detail")
	local function bx(par, name, u0, u1, y0, y1, d0, d1, style, opt)
		if axis == "x" then
			return FK.box(par, name, u0, u1, y0, y1, d0, d1, style, opt)
		else
			return FK.box(par, name, d0, d1, y0, y1, u0, u1, style, opt)
		end
	end
	table.sort(ops, function(a, b) return a[1] < b[1] end)
	local body = o.style or "Hull"
	local segs = {}
	local cur = r0
	for _, op in ipairs(ops) do
		if op[1] > cur + 0.01 then
			bx(m, "Body", cur, op[1], FY, H, c0, c1, body)
			table.insert(segs, {cur, op[1]})
		end
		if op[3] > FY + 0.01 then bx(m, "Sill", op[1], op[2], FY, op[3], c0, c1, body) end
		if op[4] < H - 0.01 then bx(m, "Header", op[1], op[2], op[4], H, c0, c1, body) end
		table.insert(segs, {op[1], op[2], op = op})
		cur = op[2]
	end
	if cur < r1 - 0.01 then
		bx(m, "Body", cur, r1, FY, H, c0, c1, body)
		table.insert(segs, {cur, r1})
	end
	bx(m, "Cap", r0, r1, H - 1.2, H, c0 - 1, c1 + 1, "Trim", {noshadow = true})
	if o.rampart then
		bx(det, "Walk", r0, r1, H, H + 0.08, c0, c1, "Deck", {deco = true})
		if o.rampart.lo then
			bx(m, "Parapet", r0, r1, H, H + 3.6, c0 - 1, c0, "ForgedDark")
			bx(det, "ParapetCap", r0, r1, H + 3.6, H + 4, c0 - 1.2, c0 + 0.2, "Trim", {deco = true})
		end
		if o.rampart.hi then
			bx(m, "Parapet", r0, r1, H, H + 3.6, c1, c1 + 1, "ForgedDark")
			bx(det, "ParapetCap", r0, r1, H + 3.6, H + 4, c1 - 0.2, c1 + 1.2, "Trim", {deco = true})
		end
	end
	local bands = {40}
	if H > 96 then table.insert(bands, 84) end
	local tiers = {}
	local lastY = 8
	for _, yb in ipairs(bands) do
		if yb < H - 8 then
			table.insert(tiers, {lastY + 1, yb - 2})
			lastY = yb + 4
		end
	end
	if H - 4 > lastY + 6 then table.insert(tiers, {lastY + 1, H - 4}) end
	local tierStyle = {"Rib", "Forged", "Corr"}
	for _, side in ipairs({"lo", "hi"}) do
		if not (o.noface and o.noface[side]) then
			local f0 = side == "lo" and c0 or c1
			local dir = side == "lo" and -1 or 1
			local function fb(par, name, u0, u1, y0, y1, dep0, dep1, style, opt)
				return bx(par, name, u0, u1, y0, y1, f0 + dir * dep0, f0 + dir * dep1, style, opt)
			end
			local lineStyle = o.line and o.line[side]
			for _, sg in ipairs(segs) do
				local u0, u1 = sg[1], sg[2]
				if not sg.op then
					fb(m, "Plinth", u0, u1, FY, 6, 0, 0.8, "ForgedDark", {noshadow = true})
					fb(det, "PlinthCap", u0, u1, 6, 6.5, 0, 1.1, "Trim", {deco = true})
				end
				for _, yb in ipairs(bands) do
					if yb < H - 8 and (not sg.op or yb >= sg.op[4] + 3.5 or yb + 3 <= sg.op[3] - 1) then
						fb(det, "Band", u0, u1, yb, yb + 3, 0, 1.1, "Trim", {deco = true})
						if lineStyle and yb == 40 then
							fb(det, "BandLine", u0, u1, yb - 0.45, yb - 0.1, 0, 1.2, lineStyle, {deco = true})
						end
					end
				end
				if not sg.op and u1 - u0 > 9 then
					local len = u1 - u0
					local n = math.max(1, math.floor(len / 26 + 0.5))
					local bl = (len - 6) / n
					for i = 0, n do
						local u = u0 + 3 + i * bl
						fb(m, "Fin", u - 1.5, u + 1.5, FY, H - 3, 0, 1.7, "Gun", {noshadow = true})
						if o.lit and o.lit[side] and i % 2 == 0 then
							local p = fb(det, "FinLight", u - 0.45, u + 0.45, 12, 22, 1.7, 1.95, "White", {deco = true})
							local face
							if axis == "x" then face = dir > 0 and Enum.NormalId.Back or Enum.NormalId.Front
							else face = dir > 0 and Enum.NormalId.Right or Enum.NormalId.Left end
							FK.light(p, "SurfaceLight", {Face = face, Range = 40, Brightness = 1.1, Angle = 150, Color = C(220, 230, 255), Shadows = false})
						end
						if i < n and bl > 6 then
							for ti, t in ipairs(tiers) do
								fb(det, "Panel", u + 2.5, u + bl - 2.5, t[1], t[2], 0, 0.6, tierStyle[(ti - 1) % 3 + 1], {deco = true})
							end
						end
					end
				end
			end
		end
	end
	local mid = (c0 + c1) / 2
	for _, op in ipairs(ops) do
		local a, b, y0, y1 = op[1], op[2], op[3], op[4]
		local kind = op.kind or "gate"
		bx(m, "Jamb", a - 3, a, y0, y1 + 3, c0 - 1.5, c1 + 1.5, "Gun")
		bx(m, "Jamb", b, b + 3, y0, y1 + 3, c0 - 1.5, c1 + 1.5, "Gun")
		if y1 < H - 0.01 then
			bx(m, "Lintel", a - 3, b + 3, y1, y1 + 3, c0 - 1.5, c1 + 1.5, "Gun")
		end
		if kind ~= "window" then
			bx(det, "HazardLo", a, b, y1 + 0.7, y1 + 2.3, c0 - 1.62, c0 - 1.5, "Hazard", {deco = true})
			bx(det, "HazardHi", a, b, y1 + 0.7, y1 + 2.3, c1 + 1.5, c1 + 1.62, "Hazard", {deco = true})
			local p = bx(det, "GateLight", a + 1, b - 1, y1 - 0.3, y1, mid - 1.2, mid + 1.2, "Amber", {deco = true})
			FK.light(p, "SurfaceLight", {Face = Enum.NormalId.Bottom, Range = 28, Brightness = 1.3, Angle = 150, Color = C(255, 196, 128), Shadows = false})
			bx(det, "Threshold", a, b, y0, y0 + 0.06, c0 - 1.5, c1 + 1.5, kind == "gate" and "HazardFloor" or "Deck", {deco = true})
			bx(det, "JambLine", a - 1.7, a - 1.3, y0, y1, c0 - 1.6, c0 - 1.5, "Amber", {deco = true})
			bx(det, "JambLine", a - 1.7, a - 1.3, y0, y1, c1 + 1.5, c1 + 1.6, "Amber", {deco = true})
			bx(det, "JambLine", b + 1.3, b + 1.7, y0, y1, c0 - 1.6, c0 - 1.5, "Amber", {deco = true})
			bx(det, "JambLine", b + 1.3, b + 1.7, y0, y1, c1 + 1.5, c1 + 1.6, "Amber", {deco = true})
		else
			bx(det, "SillCap", a - 3, b + 3, y0 - 0.2, y0 + 0.6, c0 - 1.8, c1 + 1.8, "Trim", {deco = true})
		end
		if op.barrier then
			bx(m, "Barrier", a, b, y0, y1, mid - 0.5, mid + 0.5, "Invis", {noquery = true})
		end
	end
	return m
end

-- roof slab at y (underside) with trusses spanning `span` axis at positions `at` (coords on the other axis)
-- rect x0,x1,z0,z1; span = "z" (trusses run along z at given x's) or "x"
function FB.roof(parent, name, x0, x1, z0, z1, y, span, at, o)
	o = o or {}
	local m = FK.folder(parent, name)
	local slot = o.slot or 0
	local a0, a1 = (span == "z") and x0 or z0, (span == "z") and x1 or z1 -- axis the trusses are spaced on
	local s0, s1 = (span == "z") and z0 or x0, (span == "z") and z1 or x1 -- span extent
	local function bx(nm, p0, p1, y0, y1, q0, q1, style, opt)
		if span == "z" then return FK.box(m, nm, p0, p1, y0, y1, q0, q1, style, opt)
		else return FK.box(m, nm, q0, q1, y0, y1, p0, p1, style, opt) end
	end
	local function pt(p, yy, q)
		if span == "z" then return V(p, yy, q) else return V(q, yy, p) end
	end
	local depth = o.depth or 10
	for _, p in ipairs(at) do
		bx("TrussBottom", p - 1.6, p + 1.6, y - depth, y - depth + 2.4, s0, s1, "Gun")
		bx("TrussTop", p - 1.6, p + 1.6, y - 2.4, y, s0, s1, "Gun", {noshadow = true})
		local n = math.max(2, math.floor((s1 - s0) / 30 + 0.5))
		local dq = (s1 - s0) / n
		for k = 0, n - 1 do
			local q = s0 + k * dq
			local lo, hi = y - depth + 2.4, y - 2.4
			FK.beam(m, "TrussWeb", pt(p, (k % 2 == 0) and lo or hi, q), pt(p, (k % 2 == 0) and hi or lo, q + dq), 1.4, 1.4, "Trim", {noshadow = true})
		end
	end
	-- cover: opaque strips, optional glazed slots centred between trusses
	local edges = {a0}
	if slot > 0 then
		for i = 1, #at - 1 do
			local c = (at[i] + at[i + 1]) / 2
			table.insert(edges, c - slot / 2)
			table.insert(edges, c + slot / 2)
		end
	end
	table.insert(edges, a1)
	for i = 1, #edges - 1 do
		local glass = slot > 0 and i % 2 == 0
		if glass then
			local g = bx("Skylight", edges[i], edges[i + 1], y + 1, y + 1.5, s0 + 6, s1 - 6, "Glass", {noshadow = true, tr = 0.45, color = C(200, 214, 226)})
			bx("RoofEnd", edges[i], edges[i + 1], y, y + 3, s0, s0 + 6, "HullDark")
			bx("RoofEnd", edges[i], edges[i + 1], y, y + 3, s1 - 6, s1, "HullDark")
		else
			bx("RoofPanel", edges[i], edges[i + 1], y, y + 3, s0, s1, "HullDark")
		end
	end
	FK.box(m, "Fascia", x0 - 1, x1 + 1, y - 1.5, y + 4, z0 - 1, z0, "Trim", {noshadow = true})
	FK.box(m, "Fascia", x0 - 1, x1 + 1, y - 1.5, y + 4, z1, z1 + 1, "Trim", {noshadow = true})
	FK.box(m, "Fascia", x0 - 1, x0, y - 1.5, y + 4, z0, z1, "Trim", {noshadow = true})
	FK.box(m, "Fascia", x1, x1 + 1, y - 1.5, y + 4, z0, z1, "Trim", {noshadow = true})
	return m
end
return FB
