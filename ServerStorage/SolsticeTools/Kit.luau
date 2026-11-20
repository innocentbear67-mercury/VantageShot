local K = {}
local CS = game:GetService("CollectionService")
local ROT = CFrame.Angles(0, math.pi, 0)
local C = Color3.fromRGB
K.Pal = {
	white = C(238, 234, 226), stone = C(220, 214, 203), cream = C(244, 236, 214),
	pave = C(200, 198, 192), paveDark = C(160, 162, 164), curb = C(176, 178, 180),
	slate = C(64, 76, 90), slateLight = C(96, 110, 124), steel = C(132, 140, 148),
	glass = C(130, 200, 232), water = C(52, 176, 210), waterDeep = C(30, 112, 150),
	wood = C(182, 134, 92), woodDark = C(140, 98, 66), sun = C(250, 198, 70), mint = C(120, 206, 170),
	green = C(108, 182, 84), greenDark = C(70, 140, 70), sand = C(232, 214, 176),
}
K.Team = {
	Blue = { team = C(40, 152, 204), teamDeep = C(28, 96, 146), teamSoft = C(150, 210, 236) },
	Red = { team = C(240, 108, 72), teamDeep = C(184, 64, 42), teamSoft = C(250, 190, 160) },
}
local M = Enum.Material
K.Look = {
	wall = { M.SmoothPlastic, "VS_White", "white" },
	wallStone = { M.SmoothPlastic, "VS_White", "stone" },
	wallCream = { M.SmoothPlastic, "VS_WhiteLarge", "cream" },
	wallTeam = { M.SmoothPlastic, "VS_White", "team" },
	wallTeamDeep = { M.SmoothPlastic, "VS_White", "teamDeep" },
	wallTeamSoft = { M.SmoothPlastic, "VS_White", "teamSoft" },
	wallSlate = { M.SmoothPlastic, "VS_WhiteLarge", "slate" },
	panel = { M.SmoothPlastic, "VS_WhiteLarge", "white" },
	floor = { M.Concrete, "VS_Floor", "pave" },
	floorDark = { M.Concrete, "VS_Floor", "paveDark" },
	floorStone = { M.Concrete, "VS_Floor", "stone" },
	roof = { M.Concrete, "VS_Floor", "curb" },
	trim = { M.SmoothPlastic, "", "slate" },
	trimLight = { M.SmoothPlastic, "", "white" },
	trimTeam = { M.SmoothPlastic, "", "team" },
	trimTeamDeep = { M.SmoothPlastic, "", "teamDeep" },
	trimSun = { M.SmoothPlastic, "", "sun" },
	steel = { M.Metal, "VS_CorrugatedSteel", "steel" },
	metal = { M.Metal, "", "slateLight" },
	glass = { M.Glass, "", "glass", tr = 0.35 },
	wood = { M.WoodPlanks, "", "wood" },
	water = { M.Glass, "", "water", tr = 0.2, cc = false },
	waterBed = { M.SmoothPlastic, "", "waterDeep" },
	leaf = { M.SmoothPlastic, "", "green" },
	leafDark = { M.SmoothPlastic, "", "greenDark" },
	sand = { M.Sand, "", "sand" },
	collider = { M.SmoothPlastic, "", "white", tr = 1 },
}
local cur
local function arena()
	local map = workspace.Map_LiveFire
	local a = map:FindFirstChild("Arena")
	if not a then a = Instance.new("Folder") a.Name = "Arena" a.Parent = map end
	return a
end
K.arena = arena
function K.begin(zone)
	local old = arena():FindFirstChild(zone)
	if old then old:Destroy() end
	local z = Instance.new("Folder") z.Name = zone
	local b, r, s = Instance.new("Folder"), Instance.new("Folder"), Instance.new("Folder")
	b.Name, r.Name, s.Name = "Blue", "Red", "Shared"
	b.Parent, r.Parent, s.Parent = z, z, z
	cur = { z = z, Blue = b, Red = r, Shared = s, n = 0 }
	return cur
end
function K.finish()
	local z = cur.z
	for _, f in ipairs(z:GetChildren()) do if #f:GetChildren() == 0 then f:Destroy() end end
	z.Parent = arena()
	local n = cur.n
	cur = nil
	return n
end
local function resolve(look, side)
	local l = type(look) == "table" and look or K.Look[look]
	assert(l, "bad look " .. tostring(look))
	local key = l[3]
	return l, (K.Team[side][key] or K.Pal[key]), key
end
local function style(p, look, side)
	local l, col, key = resolve(look, side)
	p.Material = l[1]
	p.MaterialVariant = l[2] or ""
	p.Color = col
	p.Transparency = l.tr or 0
	if K.Team.Blue[key] then p:SetAttribute("TeamKey", key) end
	if l.cc == false then p.CanCollide = false p.CanQuery = false end
end
local function mk(shape)
	local p
	if shape == "Wedge" then p = Instance.new("WedgePart")
	elseif shape == "Cyl" then p = Instance.new("Part") p.Shape = Enum.PartType.Cylinder
	elseif shape == "Corner" then p = Instance.new("CornerWedgePart")
	else p = Instance.new("Part") end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end
function K.emit(p, look, opts)
	opts = opts or {}
	style(p, look, "Blue")
	if opts.nocollide then p.CanCollide = false end
	if opts.noquery then p.CanQuery = false end
	if opts.noshadow then p.CastShadow = false end
	if opts.tag then CS:AddTag(p, opts.tag) end
	if opts.grapple == false then p:SetAttribute("NoGrapple", true) end
	p.Parent = opts.solo and cur.Shared or cur.Blue
	cur.n += 1
	if not opts.solo then
		local q = p:Clone()
		q.CFrame = ROT * p.CFrame
		local key = p:GetAttribute("TeamKey")
		if key then q.Color = K.Team.Red[key] end
		q.Parent = cur.Red
		cur.n += 1
	end
	return p
end
function K.part(name, size, cf, look, opts)
	local p = mk(opts and opts.shape)
	p.Name = name p.Size = size p.CFrame = cf
	return K.emit(p, look, opts)
end
function K.box(name, x0, x1, y0, y1, z0, z1, look, opts)
	if x0 > x1 then x0, x1 = x1, x0 end
	if z0 > z1 then z0, z1 = z1, z0 end
	return K.part(name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), look, opts)
end
local DIRS = { ["+x"] = Vector3.new(1, 0, 0), ["-x"] = Vector3.new(-1, 0, 0), ["+z"] = Vector3.new(0, 0, 1), ["-z"] = Vector3.new(0, 0, -1) }
function K.stairs(name, x0, x1, z0, z1, ya, yb, dir, opts)
	opts = opts or {}
	local d = DIRS[dir]
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local alongX = d.X ~= 0
	local run = alongX and math.abs(x1 - x0) or math.abs(z1 - z0)
	local width = alongX and math.abs(z1 - z0) or math.abs(x1 - x0)
	local rise = yb - ya
	local pos = Vector3.new(cx, ya + rise / 2, cz)
	local cf = CFrame.lookAt(pos, pos - d)
	local look = opts.look or "floor"
	local so = { solo = opts.solo }
	if opts.ramp then
		return K.part(name, Vector3.new(width, rise, run), cf, look, { shape = "Wedge", solo = opts.solo })
	end
	K.part(name .. "_Col", Vector3.new(width, rise, run), cf, "collider", { shape = "Wedge", solo = opts.solo })
	local n = math.max(2, math.floor(rise / 1.5 + 0.5))
	local tread = run / n
	for i = 1, n do
		local top = ya + rise * i / n
		local a = -run / 2 + (i - 1) * tread
		local h = top - ya
		local s = K.part(name .. "_S" .. i, Vector3.new(width, h, tread), cf * CFrame.new(0, -rise / 2 + h / 2, a + tread / 2), look, { solo = opts.solo, nocollide = true, noquery = true })
		s.CanTouch = false
	end
	if opts.rails ~= false then
		local rl = opts.railLook or "trimTeam"
		for _, sx in ipairs({ -1, 1 }) do
			local railCf = cf * CFrame.new(sx * (width / 2 - 0.3), 3, 0) * CFrame.Angles(-math.atan2(rise, run), 0, 0)
			K.part(name .. "_Rail", Vector3.new(0.6, 0.6, math.sqrt(run * run + rise * rise)), railCf, rl, { solo = opts.solo, nocollide = true })
			K.part(name .. "_Cheek", Vector3.new(0.8, rise + 1, run), cf * CFrame.new(sx * (width / 2 + 0.4), 0.5, 0), "trim", { shape = "Wedge", solo = opts.solo })
		end
	end
end
function K.building(name, x0, x1, z0, z1, h, o)
	o = o or {}
	local y0 = o.y0 or 0
	K.box(name, x0, x1, y0, y0 + h, z0, z1, o.look or "wall", o)
	local top = y0 + h
	if o.parapet ~= false then
		local ph, pt = o.parapetH or 3, 1.2
		local pl = o.cap or "trim"
		K.box(name .. "_PN", x0, x1, top, top + ph, z1 - pt, z1, pl, o)
		K.box(name .. "_PS", x0, x1, top, top + ph, z0, z0 + pt, pl, o)
		K.box(name .. "_PE", x1 - pt, x1, top, top + ph, z0 + pt, z1 - pt, pl, o)
		K.box(name .. "_PW", x0, x0 + pt, top, top + ph, z0 + pt, z1 - pt, pl, o)
	end
	K.box(name .. "_Roof", x0 + 0.05, x1 - 0.05, top, top + 0.2, z0 + 0.05, z1 - 0.05, o.roofLook or "roof", o)
	local storey = o.storey or 12
	local floors = math.floor(h / storey + 0.01)
	if o.band ~= false then
		local bl = o.band or "trimTeam"
		for k = 1, floors do
			local y = y0 + k * storey
			if y < top - 1 then K.box(name .. "_Band" .. k, x0 - 0.4, x1 + 0.4, y - 0.8, y + 0.4, z0 - 0.4, z1 + 0.4, bl, o) end
		end
		K.box(name .. "_Base", x0 - 0.3, x1 + 0.3, y0, y0 + 1.2, z0 - 0.3, z1 + 0.3, "trim", o)
	end
	if o.win ~= false then
		local faces = o.winFaces or { N = true, S = true, E = true, W = true }
		for k = (o.winFrom or 2), floors do
			local yb = y0 + (k - 1) * storey + 3.2
			local yt = yb + storey - 6.4
			if yt < top - 1 then
				local function strip(a, b, c, d) K.box(name .. "_Win", a, b, yb, yt, c, d, "glass", o) end
				local m = 4
				if faces.N and (x1 - x0) > 12 then strip(x0 + m, x1 - m, z1, z1 + 0.25) end
				if faces.S and (x1 - x0) > 12 then strip(x0 + m, x1 - m, z0 - 0.25, z0) end
				if faces.E and (z1 - z0) > 12 then strip(x1, x1 + 0.25, z0 + m, z1 - m) end
				if faces.W and (z1 - z0) > 12 then strip(x0 - 0.25, x0, z0 + m, z1 - m) end
			end
		end
	end
end
function K.hollow(name, x0, x1, z0, z1, h, o)
	o = o or {}
	local y0 = o.y0 or 0
	local t = o.t or 2
	local look = o.look or "wall"
	local doors = o.doors or {}
	local function wall(face, a0, a1)
		local gaps = {}
		for _, d in ipairs(doors) do if d.face == face then table.insert(gaps, { d.at - d.w / 2, d.at + d.w / 2, d.h or 12 }) end end
		table.sort(gaps, function(a, b) return a[1] < b[1] end)
		local segs, pos = {}, a0
		for _, g in ipairs(gaps) do
			if g[1] > pos then table.insert(segs, { pos, g[1], y0, y0 + h }) end
			table.insert(segs, { g[1], g[2], y0 + g[3], y0 + h })
			pos = g[2]
		end
		if pos < a1 then table.insert(segs, { pos, a1, y0, y0 + h }) end
		for _, s in ipairs(segs) do
			if s[4] - s[3] > 0.1 then
				if face == "N" then K.box(name .. "_WN", s[1], s[2], s[3], s[4], z1 - t, z1, look, o)
				elseif face == "S" then K.box(name .. "_WS", s[1], s[2], s[3], s[4], z0, z0 + t, look, o)
				elseif face == "E" then K.box(name .. "_WE", x1 - t, x1, s[3], s[4], s[1], s[2], look, o)
				else K.box(name .. "_WW", x0, x0 + t, s[3], s[4], s[1], s[2], look, o) end
			end
		end
	end
	wall("N", x0, x1) wall("S", x0, x1) wall("E", z0 + t, z1 - t) wall("W", z0 + t, z1 - t)
	if o.roof ~= false then
		K.box(name .. "_Ceil", x0, x1, y0 + h, y0 + h + 1.5, z0, z1, o.roofLook or "roof", o)
		if o.parapet ~= false then
			local top = y0 + h + 1.5
			local pl = o.cap or "trim"
			K.box(name .. "_PN", x0, x1, top, top + 3, z1 - 1.2, z1, pl, o)
			K.box(name .. "_PS", x0, x1, top, top + 3, z0, z0 + 1.2, pl, o)
			K.box(name .. "_PE", x1 - 1.2, x1, top, top + 3, z0 + 1.2, z1 - 1.2, pl, o)
			K.box(name .. "_PW", x0, x0 + 1.2, top, top + 3, z0 + 1.2, z1 - 1.2, pl, o)
		end
	end
	if o.floor ~= false then K.box(name .. "_Floor", x0 + t, x1 - t, y0, y0 + 0.2, z0 + t, z1 - t, o.floorLook or "floorStone", o) end
end
local CONT = { "team", "teamDeep", "sun", "white", "slateLight", "mint" }
function K.container(name, x, z, level, alongZ, colKey, opts)
	opts = opts or {}
	local L, H, W = 24, 10.4, 10
	local y = (opts.y0 or 0) + (level - 1) * H
	local look = { M.Metal, "VS_CorrugatedSteel", colKey or CONT[(math.floor(math.abs(x + z * 3)) % #CONT) + 1] }
	local sx, sz = (alongZ and W or L), (alongZ and L or W)
	K.box(name, x - sx / 2, x + sx / 2, y, y + H, z - sz / 2, z + sz / 2, look, opts)
	if alongZ then
		K.box(name .. "_F1", x - sx / 2 - 0.2, x + sx / 2 + 0.2, y, y + H, z + sz / 2 - 0.6, z + sz / 2 + 0.2, "trim", opts)
		K.box(name .. "_F2", x - sx / 2 - 0.2, x + sx / 2 + 0.2, y, y + H, z - sz / 2 - 0.2, z - sz / 2 + 0.6, "trim", opts)
	else
		K.box(name .. "_F1", x + sx / 2 - 0.6, x + sx / 2 + 0.2, y, y + H, z - sz / 2 - 0.2, z + sz / 2 + 0.2, "trim", opts)
		K.box(name .. "_F2", x - sx / 2 - 0.2, x - sx / 2 + 0.6, y, y + H, z - sz / 2 - 0.2, z + sz / 2 + 0.2, "trim", opts)
	end
end
function K.rail(name, x0, x1, z0, z1, y, h, look, opts) return K.box(name, x0, x1, y, y + h, z0, z1, look or "trimTeam", opts) end
function K.tree(name, x, z, y0, s, opts)
	s = s or 1 y0 = y0 or 0
	K.box(name .. "_Trunk", x - 0.8 * s, x + 0.8 * s, y0, y0 + 9 * s, z - 0.8 * s, z + 0.8 * s, "wood", opts)
	K.part(name .. "_Leaf", Vector3.new(9 * s, 7 * s, 9 * s), CFrame.new(x, y0 + 11 * s, z) * CFrame.Angles(0, math.rad(20), 0), "leaf", opts)
	K.part(name .. "_Leaf2", Vector3.new(6 * s, 4 * s, 6 * s), CFrame.new(x + 1 * s, y0 + 15.5 * s, z - 0.5 * s) * CFrame.Angles(0, math.rad(55), 0), "leafDark", opts)
end
function K.planter(name, x0, x1, z0, z1, opts)
	K.box(name, x0, x1, 0, 3, z0, z1, "wallTeam", opts)
	K.box(name .. "_Soil", x0 + 0.6, x1 - 0.6, 3, 3.2, z0 + 0.6, z1 - 0.6, "leafDark", opts)
	K.box(name .. "_Bush", x0 + 1, x1 - 1, 3.2, 5.2, z0 + 1, z1 - 1, "leaf", opts)
end
return K
