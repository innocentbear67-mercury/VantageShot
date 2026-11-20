local I = {}
local K
local V = Vector3.new
function I.bind(k) K = k end
local rnd = Random.new(7)
function I.seed(n) rnd = Random.new(n) end
function I.faceBox(b, f, a0, a1, y0, y1, d0, d1, s, name)
	local i = b.inset or 0.5
	if f == "S" then return K.box(a0, a1, y0, y1, b.z0 + i - d1, b.z0 + i - d0, s, name)
	elseif f == "N" then return K.box(a0, a1, y0, y1, b.z1 - i + d0, b.z1 - i + d1, s, name)
	elseif f == "W" then return K.box(b.x0 + i - d1, b.x0 + i - d0, y0, y1, a0, a1, s, name)
	else return K.box(b.x1 - i + d0, b.x1 - i + d1, y0, y1, a0, a1, s, name) end
end
local NRM = { S = "-z", N = "+z", W = "-x", E = "+x" }
I.NRM = NRM
function I.facePoint(b, f, a, y, d)
	local i = b.inset or 0.5
	if f == "S" then return V(a, y, b.z0 + i - d)
	elseif f == "N" then return V(a, y, b.z1 - i + d)
	elseif f == "W" then return V(b.x0 + i - d, y, a)
	else return V(b.x1 - i + d, y, a) end
end
local function span(b, f)
	if f == "S" or f == "N" then return b.x0, b.x1 end
	return b.z0, b.z1
end
I.span = span
function I.pilasters(b, faces, bay, top, s)
	for _, f in ipairs(faces) do
		local a0, a1 = span(b, f)
		local n = math.max(1, math.floor((a1 - a0) / bay + 0.5))
		for k = 0, n do
			local a = a0 + (a1 - a0) * k / n
			local lo, hi = a - 0.7, a + 0.7
			if k == 0 then lo, hi = a0, a0 + 1.4 elseif k == n then lo, hi = a1 - 1.4, a1 end
			I.faceBox(b, f, lo, hi, 0, top, -0.1, 0.6, s or "steelDark", "Pilaster")
		end
	end
end
function I.window(b, f, a0, a1, y, h, m, glass)
	I.faceBox(b, f, a0, a1, y, y + h, -0.05, 0.12, glass or "glassDark", "Glass")
	I.faceBox(b, f, a0 - 0.3, a1 + 0.3, y + h, y + h + 0.45, 0, 0.35, "frame", "Head")
	I.faceBox(b, f, a0 - 0.5, a1 + 0.5, y - 0.55, y, 0, 0.6, "precast", "Sill")
	I.faceBox(b, f, a0 - 0.3, a0, y, y + h, 0, 0.35, "frame", "Jamb")
	I.faceBox(b, f, a1, a1 + 0.3, y, y + h, 0, 0.35, "frame", "Jamb")
	local n = math.max(1, math.floor((a1 - a0) / (m or 4) + 0.5))
	for k = 1, n - 1 do
		local a = a0 + (a1 - a0) * k / n
		I.faceBox(b, f, a - 0.14, a + 0.14, y, y + h, 0, 0.3, "frame", "Mullion")
	end
	if h > 5 then I.faceBox(b, f, a0, a1, y + h * 0.55, y + h * 0.55 + 0.25, 0, 0.3, "frame", "Transom") end
end
function I.windowBays(b, f, bay, y, h, inset, m, glass)
	local a0, a1 = span(b, f)
	local n = math.max(1, math.floor((a1 - a0) / bay + 0.5))
	for k = 0, n - 1 do
		local s0 = a0 + (a1 - a0) * k / n
		local s1 = a0 + (a1 - a0) * (k + 1) / n
		if not (b.skip and b.skip(f, s0, s1)) then I.window(b, f, s0 + inset, s1 - inset, y, h, m, glass) end
	end
end
function I.rollerDoor(b, f, a0, a1, hgt, shutter, open)
	I.faceBox(b, f, a0 - 1, a0, 0, hgt + 1, 0, 0.7, "steelDark", "Jamb")
	I.faceBox(b, f, a1, a1 + 1, 0, hgt + 1, 0, 0.7, "steelDark", "Jamb")
	I.faceBox(b, f, a0 - 1, a1 + 1, hgt, hgt + 2.2, 0, 1.4, "steel", "Drum")
	if not open then
		I.faceBox(b, f, a0, a1, 0, hgt, -0.2, 0.25, shutter or "cladGrey", "Shutter")
		I.faceBox(b, f, a0, a1, 0, 0.5, 0, 0.35, "steelDark", "BottomBar")
	end
	for k = 0, 3 do
		local s = (k % 2 == 0) and "yellow" or "hazard"
		I.faceBox(b, f, a0 - 1, a0, k * 0.9, (k + 1) * 0.9, 0.7, 0.75, s, "Hazard")
		I.faceBox(b, f, a1, a1 + 1, k * 0.9, (k + 1) * 0.9, 0.7, 0.75, s, "Hazard")
	end
	for _, a in ipairs({ a0 - 0.5, a1 + 0.5 }) do
		local p = I.facePoint(b, f, a, 0, 2.2)
		K.vcyl(p.X, p.Z, 0, 3.6, 1.1, "yellow", "Bollard")
		K.vcyl(p.X, p.Z, 2.6, 2.9, 1.15, "hazard", "BollardBand")
	end
	local lp = I.facePoint(b, f, (a0 + a1) / 2, hgt + 3.4, 0)
	K.wallLamp(lp, NRM[f])
end
function I.personDoor(b, f, a, w, col)
	w = w or 4
	I.faceBox(b, f, a - w / 2 - 0.5, a + w / 2 + 0.5, 0, 8.5, 0, 0.35, "frame", "DoorFrame")
	I.faceBox(b, f, a - w / 2, a + w / 2, 0, 8, 0.2, 0.45, col or "teal", "Door")
	I.faceBox(b, f, a - w / 2 + 0.6, a - w / 2 + 1.4, 3.6, 4.2, 0.45, 0.65, "steelBare", "Handle")
	I.faceBox(b, f, a - w / 2 - 1.5, a + w / 2 + 1.5, 9.2, 9.6, 0, 3, "steelDark", "Canopy")
	K.wallLamp(I.facePoint(b, f, a, 10.6, 0), NRM[f])
end
function I.downpipe(b, f, a, top)
	local p = I.facePoint(b, f, a, 0, 0.45)
	K.vcyl(p.X, p.Z, 0.3, top, 0.7, "steelDark", "Downpipe")
	local q = I.facePoint(b, f, a, top - 0.6, 0.45)
	K.box(q.X - 0.6, q.X + 0.6, top - 1.2, top, q.Z - 0.6, q.Z + 0.6, "steelDark", "Hopper")
end
function I.roofKit(x0, x1, z0, z1, y, n)
	for k = 1, n do
		local t = rnd:NextInteger(1, 4)
		local x = rnd:NextNumber(x0 + 4, x1 - 4)
		local z = rnd:NextNumber(z0 + 4, z1 - 4)
		if t == 1 or t == 2 then
			K.box(x - 2.5, x + 2.5, y, y + 3, z - 1.8, z + 1.8, "steel", "ACUnit")
			K.cyl(V(x - 1.2, y + 3, z), V(x - 1.2, y + 3.2, z), 2.6, "steelDark", "Fan")
			K.cyl(V(x + 1.3, y + 3, z), V(x + 1.3, y + 3.2, z), 2.6, "steelDark", "Fan")
			K.box(x - 2.7, x + 2.7, y, y + 0.4, z - 2, z + 2, "steelDark", "Base")
		elseif t == 3 then
			K.vcyl(x, z, y, y + 3.2, 1.6, "steelBare", "Vent")
			K.vcyl(x, z, y + 3.2, y + 3.8, 2.6, "steelBare", "VentCap")
		else
			K.box(x - 3, x + 3, y, y + 1.2, z - 2.5, z + 2.5, "frame", "SkylightBase")
			K.box(x - 2.6, x + 2.6, y + 1.2, y + 1.6, z - 2.1, z + 2.1, "frosted", "Skylight")
		end
	end
end
function I.shed(o)
	local b = { x0 = o.x0, x1 = o.x1, z0 = o.z0, z1 = o.z1, h = o.h, inset = 0.5, skip = o.skip }
	local h, ph = o.h, o.parapet or 2.2
	local baseH = o.baseH or 3
	K.box(o.x0 + 0.5, o.x1 - 0.5, baseH - 0.1, h, o.z0 + 0.5, o.z1 - 0.5, o.wall or "cladGrey", "Wall")
	K.box(o.x0 + 0.2, o.x1 - 0.2, 0, baseH, o.z0 + 0.2, o.z1 - 0.2, o.base or "precast", "Plinth")
	K.box(o.x0 + 0.1, o.x1 - 0.1, baseH, baseH + 0.4, o.z0 + 0.1, o.z1 - 0.1, "frame", "BaseTrim")
	local t = 0.9
	K.box(o.x0 + 0.3, o.x1 - 0.3, h, h + ph, o.z0 + 0.3, o.z0 + 0.3 + t, o.wall or "cladGrey", "Parapet")
	K.box(o.x0 + 0.3, o.x1 - 0.3, h, h + ph, o.z1 - 0.3 - t, o.z1 - 0.3, o.wall or "cladGrey", "Parapet")
	K.box(o.x0 + 0.3, o.x0 + 0.3 + t, h, h + ph, o.z0 + 0.3, o.z1 - 0.3, o.wall or "cladGrey", "Parapet")
	K.box(o.x1 - 0.3 - t, o.x1 - 0.3, h, h + ph, o.z0 + 0.3, o.z1 - 0.3, o.wall or "cladGrey", "Parapet")
	K.box(o.x0 + 1.2, o.x1 - 1.2, h, h + 0.15, o.z0 + 1.2, o.z1 - 1.2, o.roofDeck or "sealed", "RoofDeck")
	K.box(o.x0, o.x1, h + ph, h + ph + 0.45, o.z0, o.z0 + 1.4, "steelDark", "Coping")
	K.box(o.x0, o.x1, h + ph, h + ph + 0.45, o.z1 - 1.4, o.z1, "steelDark", "Coping")
	K.box(o.x0, o.x0 + 1.4, h + ph, h + ph + 0.45, o.z0 + 1.4, o.z1 - 1.4, "steelDark", "Coping")
	K.box(o.x1 - 1.4, o.x1, h + ph, h + ph + 0.45, o.z0 + 1.4, o.z1 - 1.4, "steelDark", "Coping")
	local faces = o.faces or {}
	local pf = {}
	for f in pairs(faces) do table.insert(pf, f) end
	if o.bay then I.pilasters(b, pf, o.bay, h + ph, o.pilaster) end
	for f, spec in pairs(faces) do
		if spec.win then I.windowBays(b, f, o.bay or 16, spec.win[1], spec.win[2], spec.win[3] or 1.6, spec.win[4] or 4, spec.win[5]) end
		if spec.win2 then I.windowBays(b, f, o.bay or 16, spec.win2[1], spec.win2[2], spec.win2[3] or 1.6, spec.win2[4] or 4, spec.win2[5]) end
		for _, d in ipairs(spec.doors or {}) do
			if d.kind == "roller" then I.rollerDoor(b, f, d.a, d.b, d.h or 12, d.shutter, d.open)
			else I.personDoor(b, f, d.a, d.w, d.col) end
		end
		if spec.sign then
			local sgn = spec.sign
			local p = I.facePoint(b, f, sgn.a, sgn.y, 0.3)
			K.facadeSign(p, NRM[f], sgn.w, sgn.h, sgn.text, sgn.bg or "signDark", sgn.fg or K.rgb(242, 192, 46), sgn.font, sgn.glow)
		end
		for _, a in ipairs(spec.pipes or {}) do I.downpipe(b, f, a, h + 0.5) end
		for _, l in ipairs(spec.lamps or {}) do K.wallLamp(I.facePoint(b, f, l[1], l[2], 0), NRM[f]) end
	end
	if o.roofN and o.roofN > 0 then I.roofKit(o.x0 + 2, o.x1 - 2, o.z0 + 2, o.z1 - 2, h + 0.15, o.roofN) end
	return b
end
local contCols = {
	{ 198, 94, 68 }, { 90, 144, 138 }, { 234, 226, 206 }, { 112, 140, 174 }, { 222, 132, 72 }, { 172, 176, 182 }, { 120, 156, 100 },
}
I.contCols = contCols
function I.container(x0, x1, z0, z1, y0, col, doorEnd)
	col = col or contCols[rnd:NextInteger(1, #contCols)]
	local s = K.st(Enum.Material.Metal, K.rgb(col[1], col[2], col[3]), "FR_Corrugated")
	local h = 8.5
	local alongZ = (z1 - z0) > (x1 - x0)
	K.box(x0 + 0.25, x1 - 0.25, y0 + 0.4, y0 + h - 0.4, z0 + 0.25, z1 - 0.25, s, "Container")
	for _, x in ipairs({ x0, x1 - 0.6 }) do
		for _, z in ipairs({ z0, z1 - 0.6 }) do
			K.box(x, x + 0.6, y0, y0 + h, z, z + 0.6, "steelDark", "Post")
		end
	end
	K.box(x0, x1, y0, y0 + 0.5, z0, z0 + 0.6, "steelDark", "Rail"); K.box(x0, x1, y0, y0 + 0.5, z1 - 0.6, z1, "steelDark", "Rail")
	K.box(x0, x1, y0 + h - 0.5, y0 + h, z0, z0 + 0.6, "steelDark", "Rail"); K.box(x0, x1, y0 + h - 0.5, y0 + h, z1 - 0.6, z1, "steelDark", "Rail")
	K.box(x0, x0 + 0.6, y0, y0 + 0.5, z0, z1, "steelDark", "Rail"); K.box(x1 - 0.6, x1, y0, y0 + 0.5, z0, z1, "steelDark", "Rail")
	K.box(x0, x0 + 0.6, y0 + h - 0.5, y0 + h, z0, z1, "steelDark", "Rail"); K.box(x1 - 0.6, x1, y0 + h - 0.5, y0 + h, z0, z1, "steelDark", "Rail")
	if doorEnd ~= false then
		local dark = K.st(Enum.Material.Metal, K.rgb(col[1] * 0.85, col[2] * 0.85, col[3] * 0.85), "FR_Corrugated")
		if alongZ then
			local z = (doorEnd == "+") and z1 or z0
			local sgn = (doorEnd == "+") and 1 or -1
			K.box(x0 + 0.6, x1 - 0.6, y0 + 0.5, y0 + h - 0.5, z - sgn * 0.3, z + sgn * 0.05, dark, "Doors")
			for k = 1, 4 do
				local x = x0 + (x1 - x0) * k / 5
				K.cyl(V(x, y0 + 0.7, z + sgn * 0.15), V(x, y0 + h - 0.7, z + sgn * 0.15), 0.22, "steelBare", "LockBar")
			end
		else
			local x = (doorEnd == "+") and x1 or x0
			local sgn = (doorEnd == "+") and 1 or -1
			K.box(x - sgn * 0.3, x + sgn * 0.05, y0 + 0.5, y0 + h - 0.5, z0 + 0.6, z1 - 0.6, dark, "Doors")
			for k = 1, 4 do
				local z = z0 + (z1 - z0) * k / 5
				K.cyl(V(x + sgn * 0.15, y0 + 0.7, z), V(x + sgn * 0.15, y0 + h - 0.7, z), 0.22, "steelBare", "LockBar")
			end
		end
	end
	return y0 + h
end
function I.track(xc, z0, z1)
	K.box(xc - 6, xc + 6, 0, 0.35, z0, z1, "gravel", "Ballast")
	for _, dx in ipairs({ -2.6, 2.6 }) do
		K.box(xc + dx - 0.3, xc + dx + 0.3, 0.75, 1.25, z0, z1, "steelBare", "Rail")
		K.box(xc + dx - 0.45, xc + dx + 0.45, 0.6, 0.75, z0, z1, "steelDark", "RailFoot")
	end
	local n = math.floor((z1 - z0) / 3)
	for k = 0, n - 1 do
		local z = z0 + 1.5 + k * 3
		K.box(xc - 4.4, xc + 4.4, 0.2, 0.6, z - 0.55, z + 0.55, "concreteStain", "Sleeper")
	end
end
function I.bogie(xc, z)
	K.box(xc - 3.6, xc + 3.6, 1.2, 2.2, z - 3.5, z + 3.5, "steelDark", "BogieFrame")
	for _, dz in ipairs({ -2, 2 }) do
		for _, dx in ipairs({ -2.6, 2.6 }) do
			K.cyl(V(xc + dx - 0.3, 1.9, z + dz), V(xc + dx + 0.3, 1.9, z + dz), 2.4, "steelDark", "Wheel")
		end
		K.cyl(V(xc - 3.4, 1.9, z + dz), V(xc + 3.4, 1.9, z + dz), 0.6, "steelBare", "Axle")
	end
end
function I.boxcar(xc, z0, z1, s)
	s = s or "cladRed"
	K.box(xc - 4.3, xc + 4.3, 2.4, 3.0, z0 + 0.4, z1 - 0.4, "steelDark", "Underframe")
	K.box(xc - 4.5, xc + 4.5, 3.0, 11.2, z0 + 0.5, z1 - 0.5, s, "Body")
	K.box(xc - 4.7, xc + 4.7, 11.2, 11.7, z0 + 0.3, z1 - 0.3, "steelDark", "Roof")
	K.box(xc - 0.8, xc + 0.8, 11.7, 11.9, z0 + 0.6, z1 - 0.6, "tread", "Walkway")
	local n = math.floor((z1 - z0) / 4)
	for k = 1, n - 1 do
		local z = z0 + (z1 - z0) * k / n
		K.box(xc - 4.75, xc - 4.45, 3.0, 11.2, z - 0.2, z + 0.2, "steelDark", "Rib")
		K.box(xc + 4.45, xc + 4.75, 3.0, 11.2, z - 0.2, z + 0.2, "steelDark", "Rib")
	end
	local zc = (z0 + z1) / 2
	for _, sx in ipairs({ -1, 1 }) do
		K.box(xc + sx * 4.5, xc + sx * 4.95, 3.2, 10.6, zc - 3.5, zc + 3.5, "steel", "SlideDoor")
		K.box(xc + sx * 4.5, xc + sx * 5.05, 10.6, 11.0, zc - 6, zc + 6, "steelDark", "DoorTrack")
		K.box(xc + sx * 4.95, xc + sx * 5.15, 5.5, 8, zc + 2.8, zc + 3.1, "steelBare", "Handle")
	end
	I.bogie(xc, z0 + 5)
	I.bogie(xc, z1 - 5)
	K.box(xc - 0.7, xc + 0.7, 2.6, 3.6, z0 - 0.8, z0 + 0.6, "steelDark", "Coupler")
	K.box(xc - 0.7, xc + 0.7, 2.6, 3.6, z1 - 0.6, z1 + 0.8, "steelDark", "Coupler")
	for _, z in ipairs({ z0 + 0.4, z1 - 0.4 }) do
		for k = 0, 6 do K.box(xc + 2.4, xc + 4.3, 4 + k * 1.1, 4.2 + k * 1.1, z - 0.12, z + 0.12, "yellow", "Rung") end
	end
end
function I.trailer(xc, z0, z1, body, stripe, text)
	K.box(xc - 4.4, xc + 4.4, 4.4, 13.6, z0, z1, body or "cladCream", "Body")
	K.box(xc - 4.6, xc + 4.6, 13.6, 14.0, z0 - 0.1, z1 + 0.1, "steelDark", "RoofRail")
	K.box(xc - 4.6, xc + 4.6, 4.0, 4.4, z0 - 0.1, z1 + 0.1, "steelDark", "FloorRail")
	K.box(xc - 3, xc + 3, 3.0, 4.0, z0 + 1, z1 - 1, "steelDark", "Chassis")
	K.box(xc - 4.5, xc - 4.2, 1.6, 4.0, z0 + 11, z1 - 10, "steelDark", "Skirt")
	K.box(xc + 4.2, xc + 4.5, 1.6, 4.0, z0 + 11, z1 - 10, "steelDark", "Skirt")
	if stripe then
		K.box(xc - 4.55, xc - 4.4, 5.2, 6.4, z0 + 0.5, z1 - 0.5, stripe, "Stripe")
		K.box(xc + 4.4, xc + 4.55, 5.2, 6.4, z0 + 0.5, z1 - 0.5, stripe, "Stripe")
	end
	for _, z in ipairs({ z0 + 3.2, z0 + 7.2 }) do
		for _, sx in ipairs({ -1, 1 }) do
			K.cyl(V(xc + sx * 2.4, 1.8, z), V(xc + sx * 4.2, 1.8, z), 3.6, "tyre", "Tyre")
			K.cyl(V(xc + sx * 4.15, 1.8, z), V(xc + sx * 4.3, 1.8, z), 2, "steelBare", "Hub")
		end
		K.box(xc - 4.4, xc + 4.4, 3.4, 4.0, z - 2.2, z + 2.2, "steelDark", "Mudflap")
	end
	K.box(xc - 4.3, xc + 4.3, 4.6, 13.4, z0 - 0.2, z0, "steel", "RearDoors")
	K.box(xc - 0.1, xc + 0.1, 4.6, 13.4, z0 - 0.35, z0 - 0.2, "steelDark", "DoorSplit")
	for _, x in ipairs({ xc - 2.6, xc - 1.2, xc + 1.2, xc + 2.6 }) do K.cyl(V(x, 4.9, z0 - 0.4), V(x, 13.1, z0 - 0.4), 0.2, "steelBare", "LockBar") end
	K.box(xc - 4, xc + 4, 2.2, 2.8, z0 - 0.8, z0 + 0.2, "steelDark", "Bumper")
	K.box(xc - 3.8, xc - 2.8, 4.8, 5.4, z0 - 0.3, z0 - 0.15, "redPaint", "TailLight")
	K.box(xc + 2.8, xc + 3.8, 4.8, 5.4, z0 - 0.3, z0 - 0.15, "redPaint", "TailLight")
	for _, sx in ipairs({ -1, 1 }) do
		K.box(xc + sx * 3 - 0.35, xc + sx * 3 + 0.35, 0.4, 3.0, z1 - 9, z1 - 8.3, "steelDark", "Leg")
		K.box(xc + sx * 3 - 0.8, xc + sx * 3 + 0.8, 0, 0.4, z1 - 9.4, z1 - 7.9, "steelDark", "Foot")
	end
	if text then
		for _, sx in ipairs({ -1, 1 }) do
			local p = V(xc + sx * 4.4, 9.6, (z0 + z1) / 2)
			K.facadeSign(p, sx < 0 and "-x" or "+x", (z1 - z0) * 0.7, 4, text, K.st(Enum.Material.SmoothPlastic, K.rgb(234, 226, 206)), K.rgb(60, 64, 72))
		end
	end
end
function I.pallet(x, z, y)
	K.box(x - 2, x + 2, y, y + 0.6, z - 2, z + 2, "woodPallet", "Pallet")
	return y + 0.6
end
function I.palletStack(x, z, layers, kind)
	local y = 0
	for l = 1, layers do
		y = I.pallet(x, z, y)
		if kind == "wrap" then
			K.box(x - 1.9, x + 1.9, y, y + 3, z - 1.9, z + 1.9, "wrap", "Goods"); y += 3
		elseif kind == "sacks" then
			K.box(x - 1.9, x + 1.9, y, y + 2.2, z - 1.9, z + 1.9, K.st(Enum.Material.Fabric, K.rgb(206, 194, 166)), "Sacks"); y += 2.2
		else
			K.box(x - 1.8, x + 1.8, y, y + 2.6, z - 1.8, z + 1.8, "wood", "Crate"); y += 2.6
		end
	end
	return y
end
function I.drum(x, z, y, col)
	local s = K.st(Enum.Material.Metal, col or K.rgb(62, 100, 150), "FR_PaintedSteel")
	K.vcyl(x, z, y, y + 3, 2, s, "Drum")
	K.vcyl(x, z, y + 1, y + 1.15, 2.08, "steelDark", "Hoop")
	K.vcyl(x, z, y + 2, y + 2.15, 2.08, "steelDark", "Hoop")
end
function I.drumCluster(x, z, n)
	local cols = { K.rgb(62, 100, 150), K.rgb(196, 70, 52), K.rgb(232, 182, 50), K.rgb(80, 128, 96) }
	for k = 1, n do
		local a = k * 2.4
		I.drum(x + math.cos(a) * (k > 1 and 1.9 or 0), z + math.sin(a) * (k > 1 and 1.9 or 0), 0, cols[(k % 4) + 1])
	end
end
function I.jersey(x0, x1, z0, z1)
	local alongX = (x1 - x0) > (z1 - z0)
	local len = alongX and (x1 - x0) or (z1 - z0)
	local n = math.max(1, math.floor(len / 6))
	for k = 0, n - 1 do
		local a = (alongX and x0 or z0) + len * k / n
		local b = (alongX and x0 or z0) + len * (k + 1) / n - 0.25
		if alongX then
			local zc = (z0 + z1) / 2
			K.box(a, b, 0, 1, zc - 1.3, zc + 1.3, "concrete", "Barrier")
			K.box(a, b, 1, 3.4, zc - 0.6, zc + 0.6, "concrete", "Barrier")
			K.ramp(a, b, zc - 1.3, zc - 0.6, 1, 2.0, "+z", "concrete", "Barrier")
			K.ramp(a, b, zc + 0.6, zc + 1.3, 1, 2.0, "-z", "concrete", "Barrier")
			K.box(a + 0.5, a + 1.3, 2.6, 3.0, zc - 0.65, zc + 0.65, "redPaint", "Reflector")
		else
			local xc = (x0 + x1) / 2
			K.box(xc - 1.3, xc + 1.3, 0, 1, a, b, "concrete", "Barrier")
			K.box(xc - 0.6, xc + 0.6, 1, 3.4, a, b, "concrete", "Barrier")
			K.ramp(xc - 1.3, xc - 0.6, a, b, 1, 2.0, "+x", "concrete", "Barrier")
			K.ramp(xc + 0.6, xc + 1.3, a, b, 1, 2.0, "-x", "concrete", "Barrier")
		end
	end
end
function I.floodMast(x, z, h, aimX, aimZ)
	K.box(x - 1.4, x + 1.4, 0, 1, z - 1.4, z + 1.4, "concrete", "MastBase")
	K.vcyl(x, z, 1, h, 1.1, "steel", "Mast")
	K.box(x - 3, x + 3, h - 0.4, h, z - 0.6, z + 0.6, "steelDark", "MastBar")
	for _, dx in ipairs({ -2.2, 0, 2.2 }) do
		local p = V(x + dx, h + 0.8, z)
		local tgt = V(aimX + dx * 4, 0, aimZ)
		local cf = CFrame.lookAt(p, tgt)
		K.part(V(1.8, 1.4, 0.8), cf, "steelDark", "Flood")
		local lens = K.part(V(1.5, 1.1, 0.12), cf * CFrame.new(0, 0, -0.45), "lampCool", "FloodLens")
		K.light(lens, "SpotLight", K.rgb(255, 236, 214), 60, 1.6, Enum.NormalId.Front, 70)
	end
end
function I.forklift(x, z, rotY)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, rotY or 0, 0)
	local function b(sx, sy, sz, ox, oy, oz, s, n) K.part(V(sx, sy, sz), base * CFrame.new(ox, oy, oz), s, n) end
	b(4.2, 2.6, 6, 0, 2.2, 0, "yellow", "Body")
	b(4.4, 2.4, 1.6, 0, 3.0, 2.6, "steelDark", "Counterweight")
	b(3.4, 0.4, 3, 0, 3.7, 0.4, "black", "Seat")
	for _, sx in ipairs({ -1.9, 1.9 }) do
		b(0.25, 4.6, 0.25, sx, 5.9, -1.2, "steelDark", "GuardPost")
		b(0.25, 4.6, 0.25, sx, 5.9, 2.0, "steelDark", "GuardPost")
	end
	b(4.2, 0.3, 3.6, 0, 8.3, 0.4, "steelDark", "Guard")
	b(0.4, 7.6, 0.4, -1.2, 4.6, -3.3, "steelDark", "Mast")
	b(0.4, 7.6, 0.4, 1.2, 4.6, -3.3, "steelDark", "Mast")
	b(0.5, 0.3, 4, -1, 0.5, -5.4, "steelBare", "Fork")
	b(0.5, 0.3, 4, 1, 0.5, -5.4, "steelBare", "Fork")
	for _, w in ipairs({ { -2.2, -2.0, 2.4 }, { 2.2, -2.0, 2.4 }, { -2.2, 2.2, 2.0 }, { 2.2, 2.2, 2.0 } }) do
		local p = base * CFrame.new(w[1], w[3] / 2, w[2])
		local q = p * CFrame.new(w[1] > 0 and 0.5 or -0.5, 0, 0)
		K.cyl(p.Position, q.Position, w[3], "tyre", "Wheel")
	end
	local pc = base * CFrame.new(0, 1.0, -5.6)
	K.part(V(4, 0.6, 4), pc, "woodPallet", "Pallet")
	K.part(V(3.6, 2.4, 3.6), pc * CFrame.new(0, 1.5, 0), "wood", "Crate")
end
function I.skip(x0, x1, z0, z1, s)
	s = s or "yellow"
	K.box(x0 + 1.5, x1 - 1.5, 0.3, 5.5, z0, z1, s, "Skip")
	K.ramp(x0, x0 + 1.5, z0, z1, 0.3, 5.5, "+x", s, "SkipEnd")
	K.ramp(x1 - 1.5, x1, z0, z1, 0.3, 5.5, "-x", s, "SkipEnd")
	K.box(x0 + 1, x1 - 1, 5.5, 6, z0 - 0.2, z1 + 0.2, "steelDark", "Lip")
end
function I.tank(x, z, d, h, s)
	s = s or "cladCream"
	K.vcyl(x, z, 0, 1, d + 3, "concrete", "TankBase")
	K.vcyl(x, z, 1, h, d, s, "Tank")
	for y = 4, h - 2, 5 do K.vcyl(x, z, y, y + 0.35, d + 0.25, "steelDark", "Band") end
	local top = K.ball(V(x, h, z), d, s, "Dome")
	top.Size = V(d, d * 0.28, d)
	local lx = x - d / 2 - 0.6
	K.box(lx - 0.15, lx + 0.15, 1, h + 3, z - 1.1, z - 0.9, "railYellow", "LadderRail")
	K.box(lx - 0.15, lx + 0.15, 1, h + 3, z + 0.9, z + 1.1, "railYellow", "LadderRail")
	for y = 2, h + 2, 1.5 do K.box(lx - 0.1, lx + 0.1, y, y + 0.15, z - 1, z + 1, "railYellow", "Rung") end
	local r = d / 2 - 0.6
	for k = 0, 7 do
		local a0, a1 = k * math.pi / 4, (k + 1) * math.pi / 4
		local p0 = V(x + math.cos(a0) * r, h + 0.8, z + math.sin(a0) * r)
		local p1 = V(x + math.cos(a1) * r, h + 0.8, z + math.sin(a1) * r)
		K.cyl(p0 + V(0, 3, 0), p1 + V(0, 3, 0), 0.3, "railYellow", "TankRail")
		K.box(p0.X - 0.15, p0.X + 0.15, h + 0.8, h + 3.8, p0.Z - 0.15, p0.Z + 0.15, "railYellow", "TankPost")
	end
end
function I.pipeRun(a, b, d, s, flangeEvery)
	K.cyl(a, b, d, s or "steel", "Pipe")
	local len = (b - a).Magnitude
	local n = math.floor(len / (flangeEvery or 16))
	for k = 1, n - 1 do
		local p = a:Lerp(b, k / n)
		local dir = (b - a).Unit
		K.cyl(p - dir * 0.25, p + dir * 0.25, d + 0.5, "steelDark", "Flange")
	end
end
function I.acWall(b, f, a, y)
	I.faceBox(b, f, a - 1.6, a + 1.6, y, y + 2.4, 0, 1.6, "steel", "WallAC")
	local p = I.facePoint(b, f, a, y + 1.2, 1.65)
	K.part(V(2.2, 2.0, 0.1), CFrame.lookAt(p, p + K.NV[NRM[f]]), "steelDark", "Grille")
end
return I
