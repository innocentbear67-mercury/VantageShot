-- ArenaKit: Forge-style structures for the outer arena (same materials, colours and stairs as the core).
local A = {}
local S = workspace.Map_LiveFire.Structure
A.T1, A.T2 = 28, 44 -- walkway tiers (match the raised core)
A.C = {
	Wall = Color3.fromRGB(165, 173, 184), Dark = Color3.fromRGB(110, 117, 133), Panel = Color3.fromRGB(145, 154, 168),
	Rail = Color3.fromRGB(199, 207, 218), Deck = Color3.fromRGB(145, 152, 165), Lime = Color3.fromRGB(96, 235, 0),
	Hazard = Color3.fromRGB(226, 170, 30), Tank = Color3.fromRGB(150, 156, 164),
}
local M = Enum.Material
local function P(parent, name, size, cf, mat, var, col, props)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.Size = size; p.CFrame = cf
	p.Material = mat or M.Metal; p.MaterialVariant = var or ""; p.Color = col or A.C.Dark
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in props do p[k] = v end end
	p.Parent = parent
	return p
end
A.P = P
local function deco(p) p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false; return p end
A.deco = deco
local function model(parent, name) local mm = Instance.new("Model"); mm.Name = name; mm.Parent = parent; return mm end
A.model = model

-- terrain height (top surface) at x,z
local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include; rp.FilterDescendantsInstances = { workspace.Terrain }
function A.ground(x, z)
	local h = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -700, 0), rp)
	return h and h.Position.Y or 0
end
-- min / max ground under a rectangle
function A.groundRange(x0, x1, z0, z1)
	local lo, hi = math.huge, -math.huge
	for x = x0, x1, math.max(4, (x1 - x0) / 6) do for z = z0, z1, math.max(4, (z1 - z0) / 6) do
		local g = A.ground(x, z); lo = math.min(lo, g); hi = math.max(hi, g)
	end end
	return lo, hi
end

-- rails on one edge of a deck: from a to b (Vector3 at deck top), outward unit `out`
function A.rail(parent, a, b, out)
	local d = b - a
	local len = d.Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + d) -- length along Z
	local edge = cf + out * 0.25
	P(parent, "RailTop", Vector3.new(0.4, 0.4, len), edge + Vector3.new(0, 3.5, 0), M.Metal, "VS_PaintedSteel", A.C.Rail)
	deco(P(parent, "RailMid", Vector3.new(0.3, 0.3, len), edge + Vector3.new(0, 1.9, 0), M.Metal, "", A.C.Dark))
	P(parent, "RailKick", Vector3.new(0.3, 1.1, len), edge + Vector3.new(0, 0.55, 0), M.Metal, "", A.C.Dark)
	P(parent, "RailCollision", Vector3.new(0.5, 3.7, len), edge + Vector3.new(0, 1.85, 0), M.SmoothPlastic, "", Color3.new(1, 1, 1), { Transparency = 1, CanQuery = false })
	deco(P(parent, "RailEdge", Vector3.new(0.2, 0.2, len), edge + Vector3.new(0, 0.05, 0) + out * 0.2, M.Neon, "", A.C.Lime))
	local n = math.max(1, math.floor(len / 9))
	for i = 0, n do
		local pos = a + d * (i / n) + out * 0.25
		deco(P(parent, "RailPost", Vector3.new(0.4, 3.5, 0.4), CFrame.new(pos + Vector3.new(0, 1.75, 0)), M.Metal, "", A.C.Dark))
	end
end

-- support post from ground up to y (with hazard band + foot)
function A.post(parent, x, z, topY, w)
	w = w or 3.6
	local g = A.ground(x, z)
	local h = topY - g + 1
	P(parent, "Support", Vector3.new(w, h, w), CFrame.new(x, g - 1 + h / 2, z), M.Metal, "VS_Gunmetal", A.C.Dark)
	P(parent, "SupportFoot", Vector3.new(w + 1.2, 1.2, w + 1.2), CFrame.new(x, g + 0.3, z), M.Metal, "", A.C.Dark)
	deco(P(parent, "SupportBand", Vector3.new(w + 0.2, 1.4, w + 0.2), CFrame.new(x, g + 4, z), M.SmoothPlastic, "", A.C.Hazard))
end

-- elevated deck x0..x1, z0..z1 at top y; rails on edges listed in `rails` ("N","S","E","W"); posts every `span`
-- (no posts inside any rectangle listed in opts.keepClear, e.g. a road it spans)
function A.deck(parent, x0, x1, z0, z1, y, rails, opts)
	opts = opts or {}
	local mm = model(parent, opts.name or "Deck")
	local w, d = x1 - x0, z1 - z0
	P(mm, "Slab", Vector3.new(w, 1, d), CFrame.new((x0 + x1) / 2, y - 0.5, (z0 + z1) / 2), M.DiamondPlate, "VS_TreadPlate", A.C.Deck)
	P(mm, "Frame", Vector3.new(w - 0.8, 1.4, d - 0.8), CFrame.new((x0 + x1) / 2, y - 1.7, (z0 + z1) / 2), M.Metal, "", A.C.Dark)
	for _, e in rails or {} do
		if e == "N" then A.rail(mm, Vector3.new(x0, y, z0), Vector3.new(x1, y, z0), Vector3.new(0, 0, -1))
		elseif e == "S" then A.rail(mm, Vector3.new(x0, y, z1), Vector3.new(x1, y, z1), Vector3.new(0, 0, 1))
		elseif e == "W" then A.rail(mm, Vector3.new(x0, y, z0), Vector3.new(x0, y, z1), Vector3.new(-1, 0, 0))
		elseif e == "E" then A.rail(mm, Vector3.new(x1, y, z0), Vector3.new(x1, y, z1), Vector3.new(1, 0, 0)) end
	end
	if not opts.noPosts then
		local span = opts.span or 28
		local function clear(x, z)
			for _, r in opts.keepClear or {} do if x > r[1] - 4 and x < r[2] + 4 and z > r[3] - 4 and z < r[4] + 4 then return false end end
			return true
		end
		local nx, nz = math.max(1, math.ceil(w / span)), math.max(1, math.ceil(d / span))
		for i = 0, nx do for j = 0, nz do
			if i == 0 or i == nx or j == 0 or j == nz then
				local x, z = x0 + 2.5 + (w - 5) * i / nx, z0 + 2.5 + (d - 5) * j / nz
				if clear(x, z) then A.post(mm, x, z, y - 2.4) end
			end
		end end
	end
	return mm
end

-- solid building block with a walkable roof at `top`; base sits into the ground (foundation)
function A.block(parent, x0, x1, z0, z1, top, opts)
	opts = opts or {}
	local mm = model(parent, opts.name or "Block")
	local lo = A.groundRange(x0, x1, z0, z1) - 4
	local w, d, h = x1 - x0, z1 - z0, top - lo
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	P(mm, "Body", Vector3.new(w, h - 1, d), CFrame.new(cx, lo + (h - 1) / 2, cz), M.DiamondPlate, "Eclipse_MilitaryPlate", A.C.Wall)
	P(mm, "Roof", Vector3.new(w + 0.6, 1, d + 0.6), CFrame.new(cx, top - 0.5, cz), M.DiamondPlate, "VS_TreadPlate", A.C.Deck)
	-- gunmetal fins every ~12 studs on each face + a dark band near the top
	for _, f in { { "x", z0 - 0.4 }, { "x", z1 + 0.4 }, { "z", x0 - 0.4 }, { "z", x1 + 0.4 } } do
		local len = f[1] == "x" and w or d
		local n = math.max(1, math.floor(len / 12))
		for i = 1, n - 1 do
			local t = (f[1] == "x" and x0 or z0) + len * i / n
			local pos = f[1] == "x" and Vector3.new(t, lo + h / 2, f[2]) or Vector3.new(f[2], lo + h / 2, t)
			P(mm, "Fin", f[1] == "x" and Vector3.new(1.8, h - 2, 0.8) or Vector3.new(0.8, h - 2, 1.8), CFrame.new(pos), M.Metal, "VS_Gunmetal", A.C.Dark)
		end
		local bandPos = f[1] == "x" and Vector3.new(cx, top - 4, f[2]) or Vector3.new(f[2], top - 4, cz)
		P(mm, "Band", f[1] == "x" and Vector3.new(w + 0.8, 3, 0.8) or Vector3.new(0.8, 3, d + 0.8), CFrame.new(bandPos), M.Metal, "VS_Gunmetal", A.C.Dark)
		deco(P(mm, "LimeStrip", f[1] == "x" and Vector3.new(w * 0.6, 0.35, 0.3) or Vector3.new(0.3, 0.35, d * 0.6), CFrame.new(bandPos + (f[1] == "x" and Vector3.new(0, -2.2, (f[2] < cz and -0.5 or 0.5)) or Vector3.new((f[2] < cx and -0.5 or 0.5), -2.2, 0))), M.Neon, "", A.C.Lime))
	end
	if opts.rails ~= false then
		A.rail(mm, Vector3.new(x0, top, z0), Vector3.new(x1, top, z0), Vector3.new(0, 0, -1))
		A.rail(mm, Vector3.new(x0, top, z1), Vector3.new(x1, top, z1), Vector3.new(0, 0, 1))
		A.rail(mm, Vector3.new(x0, top, z0), Vector3.new(x0, top, z1), Vector3.new(-1, 0, 0))
		A.rail(mm, Vector3.new(x1, top, z0), Vector3.new(x1, top, z1), Vector3.new(1, 0, 0))
	end
	return mm
end

-- open vehicle shed: columns on the long sides only (drive-through on the short ends), walkable roof
function A.shed(parent, x0, x1, z0, z1, top, alongX)
	local mm = model(parent, "Shed")
	A.deck(mm, x0, x1, z0, z1, top, { "N", "S", "E", "W" }, { noPosts = true, name = "Roof" })
	local len = alongX and (x1 - x0) or (z1 - z0)
	local n = math.max(1, math.floor(len / 20))
	for i = 0, n do
		local t = (alongX and x0 or z0) + 3 + (len - 6) * i / n
		for _, side in { 1, 2 } do
			local x = alongX and t or (side == 1 and x0 + 2.5 or x1 - 2.5)
			local z = alongX and (side == 1 and z0 + 2.5 or z1 - 2.5) or t
			A.post(mm, x, z, top - 2.4, 4)
		end
	end
	-- lime strip lights under the roof
	for k = 1, 3 do
		local f = k / 4
		local pos = alongX and Vector3.new((x0 + x1) / 2, top - 2.7, z0 + (z1 - z0) * f) or Vector3.new(x0 + (x1 - x0) * f, top - 2.7, (z0 + z1) / 2)
		deco(P(mm, "ShedLight", alongX and Vector3.new(len - 12, 0.3, 0.6) or Vector3.new(0.6, 0.3, len - 12), CFrame.new(pos), M.Neon, "", A.C.Lime))
	end
	return mm
end

-- stair: clone of the core's ground-to-T1 stair (MezzStairDown), climbing toward `dir` ("+x","-x","+z","-z"),
-- with its top landing edge at (x, z). Returns the model.
local stairTemplate = nil
for _, d in S.Courtyard.ColonnadeW:GetChildren() do if d.Name == "MezzStairDown" then stairTemplate = d break end end
function A.stair(parent, x, z, dir)
	local st = stairTemplate:Clone()
	-- template: find its climb direction and top edge
	local top, low
	for _, p in st:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Step" then
			if not top or p.Position.Y > top.Position.Y then top = p end
			if not low or p.Position.Y < low.Position.Y then low = p end
		end
	end
	local climb = Vector3.new(top.Position.X - low.Position.X, 0, top.Position.Z - low.Position.Z).Unit
	local want = ({ ["+x"] = Vector3.xAxis, ["-x"] = -Vector3.xAxis, ["+z"] = Vector3.zAxis, ["-z"] = -Vector3.zAxis })[dir]
	local ang = math.atan2(climb.X, climb.Z) - math.atan2(want.X, want.Z)
	local piv = st:GetPivot()
	st:PivotTo(CFrame.new(piv.Position) * CFrame.Angles(0, -ang, 0) * (piv - piv.Position))
	-- recompute the top step after rotating and move so its far edge lands at x,z (ground follows)
	top = nil
	for _, p in st:GetDescendants() do if p:IsA("BasePart") and p.Name == "Step" and (not top or p.Position.Y > top.Position.Y) then top = p end end
	local edge = top.Position + want * (math.min(top.Size.X, top.Size.Z) / 2)
	local g = A.ground(x - want.X * 20, z - want.Z * 20)
	st:PivotTo(st:GetPivot() + Vector3.new(x - edge.X, (g - 2), z - edge.Z))
	st.Parent = parent
	return st
end

-- clone a cover prop from the core (Kit_Container, Crate, Barricade, CoverSlab, Machine) to x,z with yaw
local kit = {}
for _, f in { S.CourtCover } do for _, c in f:GetChildren() do if not kit[c.Name] then kit[c.Name] = c end end end
function A.prop(parent, name, x, z, yaw, stackY)
	local src = kit[name]
	if not src then return nil end
	local c = src:Clone()
	local parts = c:IsA("BasePart") and { c } or c:GetDescendants()
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in parts do if p:IsA("BasePart") then mn = mn:Min(p.Position - p.Size / 2); mx = mx:Max(p.Position + p.Size / 2) end end
	local ctr = (mn + mx) / 2
	local g = stackY or A.ground(x, z)
	local rot = CFrame.new(ctr) * CFrame.Angles(0, math.rad(yaw or 0), 0) * CFrame.new(-ctr)
	for _, p in parts do if p:IsA("BasePart") then p.CFrame = rot * p.CFrame end end
	local off = Vector3.new(x - ctr.X, g - mn.Y, z - ctr.Z)
	for _, p in parts do if p:IsA("BasePart") then p.CFrame = p.CFrame + off end end
	c.Parent = parent
	return c
end

-- storage tank (cylinder) with bands
function A.tank(parent, x, z, r, h)
	local mm = model(parent, "StorageTank")
	local g = A.ground(x, z) - 2
	P(mm, "Shell", Vector3.new(h, r * 2, r * 2), CFrame.new(x, g + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, "VS_PaintedSteel", A.C.Tank, { Shape = Enum.PartType.Cylinder })
	P(mm, "Cap", Vector3.new(1.2, r * 2 - 1, r * 2 - 1), CFrame.new(x, g + h + 0.6, z) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, "VS_Gunmetal", A.C.Dark, { Shape = Enum.PartType.Cylinder })
	for _, f in { 0.3, 0.7 } do
		deco(P(mm, "Band", Vector3.new(1, r * 2 + 0.3, r * 2 + 0.3), CFrame.new(x, g + h * f, z) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, "", f < 0.5 and A.C.Hazard or A.C.Lime, { Shape = Enum.PartType.Cylinder }))
	end
	return mm
end
-- stair from a deck at baseY up 16 to the next tier (clone of the core's MezzStairUp), top edge at x,z
local upTemplate = nil
for _, d in S.Courtyard.ColonnadeW:GetChildren() do if d.Name == "MezzStairUp" then upTemplate = d break end end
function A.stairUp(parent, x, z, dir, baseY)
	local st = upTemplate:Clone()
	local top, low
	for _, p in st:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Step" then
			if not top or p.Position.Y > top.Position.Y then top = p end
			if not low or p.Position.Y < low.Position.Y then low = p end
		end
	end
	local climb = Vector3.new(top.Position.X - low.Position.X, 0, top.Position.Z - low.Position.Z).Unit
	local want = ({ ["+x"] = Vector3.xAxis, ["-x"] = -Vector3.xAxis, ["+z"] = Vector3.zAxis, ["-z"] = -Vector3.zAxis })[dir]
	local ang = math.atan2(climb.X, climb.Z) - math.atan2(want.X, want.Z)
	local piv = st:GetPivot()
	st:PivotTo(CFrame.new(piv.Position) * CFrame.Angles(0, -ang, 0) * (piv - piv.Position))
	top = nil
	for _, p in st:GetDescendants() do if p:IsA("BasePart") and p.Name == "Step" and (not top or p.Position.Y > top.Position.Y) then top = p end end
	local edge = top.Position + want * (math.min(top.Size.X, top.Size.Z) / 2)
	local topY = top.Position.Y + top.Size.Y / 2
	st:PivotTo(st:GetPivot() + Vector3.new(x - edge.X, (baseY + 16) - topY, z - edge.Z))
	st.Parent = parent
	return st
end

-- pave: turn natural ground materials into installation concrete inside a rectangle (keeps the shape)
function A.pave(x0, x1, z0, z1)
	local T = workspace.Terrain
	local reg = Region3.new(Vector3.new(x0, -40, z0), Vector3.new(x1, 80, z1)):ExpandToGrid(4)
	for _, mat in { M.Grass, M.Ground, M.Mud, M.Sandstone } do T:ReplaceMaterial(reg, 4, mat, M.Concrete) end
end
return A
