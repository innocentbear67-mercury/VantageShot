-- RoadKit: road slabs, markings, barriers, bridge members and terrain cuts for the combined-arms expansion.
local R = {}
R.ROAD_TOP = 2.2
R.C = {
	Road = Color3.fromRGB(56, 60, 66), Line = Color3.fromRGB(214, 220, 226), Lime = Color3.fromRGB(182, 255, 0),
	Barrier = Color3.fromRGB(122, 128, 136), Steel = Color3.fromRGB(46, 50, 58), Hazard = Color3.fromRGB(226, 172, 40),
}
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true; p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do p[k] = v end
	p.Parent = parent
	return p
end
R.part = part
local function deco(p) p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false; return p end

-- axis-aligned road slab from (x0,z0) to (x1,z1); top at ROAD_TOP
function R.slab(parent, x0, x1, z0, z1, name, thick)
	thick = thick or 1.6
	local sx, sz = math.abs(x1 - x0), math.abs(z1 - z0)
	return part({ Name = name or "Road", Size = Vector3.new(sx, thick, sz), CFrame = CFrame.new((x0 + x1) / 2, R.ROAD_TOP - thick / 2, (z0 + z1) / 2),
		Material = Enum.Material.Concrete, MaterialVariant = "VS_SealedFloor", Color = R.C.Road }, parent)
end
-- painted line (non-colliding), along X if alongX else along Z
function R.line(parent, cx, cz, len, alongX, width, color, name)
	width = width or 0.8
	return deco(part({ Name = name or "Line", Size = alongX and Vector3.new(len, 0.1, width) or Vector3.new(width, 0.1, len),
		CFrame = CFrame.new(cx, R.ROAD_TOP + 0.05, cz), Material = Enum.Material.SmoothPlastic, Color = color or R.C.Line }, parent))
end
function R.dashes(parent, x0, x1, z0, z1, dash, gap)
	dash, gap = dash or 10, gap or 12
	local alongX = math.abs(x1 - x0) > math.abs(z1 - z0)
	local a0, a1 = alongX and math.min(x0, x1) or math.min(z0, z1), alongX and math.max(x0, x1) or math.max(z0, z1)
	local c = alongX and (z0 + z1) / 2 or (x0 + x1) / 2
	local t = a0 + gap / 2
	while t + dash <= a1 do
		if alongX then R.line(parent, t + dash / 2, c, dash, true, 0.8, nil, "Dash") else R.line(parent, c, t + dash / 2, dash, false, 0.8, nil, "Dash") end
		t += dash + gap
	end
end
-- vehicle crash barrier (colliding, jersey-style: base + cap) with an outward lime strip
function R.barrier(parent, x0, x1, z0, z1, h)
	h = h or 3.2
	local alongX = math.abs(x1 - x0) > math.abs(z1 - z0)
	local len = alongX and math.abs(x1 - x0) or math.abs(z1 - z0)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local base = part({ Name = "Barrier", Size = alongX and Vector3.new(len, h, 1.6) or Vector3.new(1.6, h, len), CFrame = CFrame.new(cx, R.ROAD_TOP + h / 2, cz),
		Material = Enum.Material.Concrete, Color = R.C.Barrier }, parent)
	local cap = part({ Name = "BarrierCap", Size = alongX and Vector3.new(len, 0.4, 1.9) or Vector3.new(1.9, 0.4, len), CFrame = CFrame.new(cx, R.ROAD_TOP + h + 0.2, cz),
		Material = Enum.Material.Metal, MaterialVariant = "VS_Gunmetal", Color = R.C.Steel }, parent)
	deco(cap); cap.CanCollide = true -- cap adds to the barrier height
	return base
end
function R.box(parent, name, size, cf, color, mat, variant)
	return part({ Name = name, Size = size, CFrame = cf, Material = mat or Enum.Material.Metal, MaterialVariant = variant or "VS_Gunmetal", Color = color or R.C.Steel }, parent)
end
R.deco = deco

-- terrain: clear a rectangle to floor y (air above), optionally fill a solid base below
function R.cut(x0, x1, z0, z1, floorY, topY)
	local T = workspace.Terrain
	topY = topY or 420
	T:FillBlock(CFrame.new((x0 + x1) / 2, (floorY + topY) / 2, (z0 + z1) / 2), Vector3.new(math.abs(x1 - x0), topY - floorY, math.abs(z1 - z0)), Enum.Material.Air)
end
function R.base(x0, x1, z0, z1, floorY, depth, mat)
	depth = depth or 18
	workspace.Terrain:FillBlock(CFrame.new((x0 + x1) / 2, floorY - depth / 2, (z0 + z1) / 2), Vector3.new(math.abs(x1 - x0), depth, math.abs(z1 - z0)), mat or Enum.Material.Ground)
end
-- terraced cut: rectangle widened by `step` per `rise` up to `levels`
function R.terraces(x0, x1, z0, z1, floorY, step, rise, levels)
	for i = 1, levels do
		R.cut(x0 - step * i, x1 + step * i, z0 - step * i, z1 + step * i, floorY + rise * i)
		if i % 4 == 0 then task.wait() end
	end
end
return R
