--[[
	VANTAGE — ForgeKit (Studio build tool)
	The shared design language of the 2026-11 "Forge" weapon art direction: premium, blocky,
	futuristic guns built from chamfered CSG blocks. Every weapon builder uses this kit, so the
	arsenal shares one palette, one bevel scale and one construction vocabulary, while each
	builder draws its own silhouette.

	ROLES (Part attribute "Role" — Skins, legendaries and FX target these, never part names)
	  Armor   ceramic shell panels (the colour skins repaint)
	  Frame   graphite structural body
	  Metal   machined steel (barrels, fasteners, feed lips)
	  Grip    carbon-weave polymer (grips, pads)
	  Dark    recesses / vents / ports (depth)
	  Accent  orange interactive bits (charging handle, selector, mag release)
	  Glow    cyan neon accents (readability + FX hooks)
	  Glass   holo / lens glass

	Kit.Block(parent, spec)
	  spec.Name, spec.Role, spec.Size, spec.CFrame (world)
	  spec.Bevel  chamfer leg in studs (0 = sharp box). spec.Axes "xyz" (default) | any subset:
	              "z" chamfers only the 4 edges running along Z (octagonal bar), etc.
	  spec.Cuts   { {N = Vector3 (local, outward), D = number} }   keep N·p <= D (planar cuts)
	  spec.Holes  { {Size = Vector3, CFrame = CFrame (local)} }   subtracted (ports, slots)
	Kit.CutYZ(y1,z1, y2,z2, oy,oz)  cut through two local points; o = the corner to remove
	Kit.CutXZ / Kit.CutXY likewise.
]]
local GeometryService = game:GetService("GeometryService")

local Kit = {}
Kit.Version = 1

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Kit.Palette = {
	Armor = { Color = rgb(212, 217, 224), Material = Enum.Material.SmoothPlastic, Variant = "" },
	Frame = { Color = rgb(46, 50, 58), Material = Enum.Material.Metal, Variant = "VS_Gunmetal" },
	Metal = { Color = rgb(128, 134, 144), Material = Enum.Material.Metal, Variant = "" },
	Grip = { Color = rgb(34, 36, 42), Material = Enum.Material.Fabric, Variant = "VantageCarbon" },
	Dark = { Color = rgb(13, 14, 17), Material = Enum.Material.SmoothPlastic, Variant = "" },
	Accent = { Color = rgb(255, 136, 40), Material = Enum.Material.SmoothPlastic, Variant = "" },
	Glow = { Color = rgb(64, 222, 255), Material = Enum.Material.Neon, Variant = "" },
	Glass = { Color = rgb(120, 205, 240), Material = Enum.Material.Glass, Variant = "", Transparency = 0.84 },
}
-- standard chamfer legs (studs, at asset scale) — keep the whole arsenal on these three
Kit.Bevel = { L = 0.035, M = 0.022, S = 0.011 }

function Kit.Style(p: BasePart, role: string)
	local s = Kit.Palette[role] or Kit.Palette.Frame
	p.Color = s.Color
	p.Material = s.Material
	p.MaterialVariant = s.Variant or ""
	p.Transparency = s.Transparency or 0
	p.Reflectance = 0
	p:SetAttribute("Role", role)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = not (role == "Glow" or role == "Glass")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function box(size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	return p
end

local function cut2(a1, b1, a2, b2, oa, ob)
	-- line through (a1,b1),(a2,b2); outward normal toward (oa,ob)
	local da, db = a2 - a1, b2 - b1
	local na, nb = -db, da
	local len = math.sqrt(na * na + nb * nb)
	na, nb = na / len, nb / len
	if na * (oa - a1) + nb * (ob - b1) < 0 then
		na, nb = -na, -nb
	end
	return na, nb, na * a1 + nb * b1
end
function Kit.CutYZ(y1, z1, y2, z2, oy, oz)
	local a, b, d = cut2(y1, z1, y2, z2, oy, oz)
	return { N = Vector3.new(0, a, b), D = d }
end
function Kit.CutXZ(x1, z1, x2, z2, ox, oz)
	local a, b, d = cut2(x1, z1, x2, z2, ox, oz)
	return { N = Vector3.new(a, 0, b), D = d }
end
function Kit.CutXY(x1, y1, x2, y2, ox, oy)
	local a, b, d = cut2(x1, y1, x2, y2, ox, oy)
	return { N = Vector3.new(a, b, 0), D = d }
end

local OPTS = { SplitApart = false, CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise }

-- removal cube covering the local half-space n·p > d (n unit): its inner face lies on the plane
local function halfspace(cf: CFrame, n: Vector3, d: number, H: number): Part
	local c = n * (d + H / 2)
	return box(Vector3.new(H, H, H), cf * CFrame.lookAt(c, c + n))
end

-- Every shape is ONE SubtractAsync of the box minus the union of removal regions (chamfer
-- half-spaces, cut half-spaces, holes). (IntersectAsync would intersect with the UNION of its
-- tools, which cancels bevels against cuts.)
function Kit.Block(parent: Instance, spec)
	local size: Vector3, cf: CFrame = spec.Size, spec.CFrame
	local bevel = spec.Bevel or 0
	local axes = spec.Axes or "xyz"
	local H = math.max(size.X, size.Y, size.Z) * 4 + 0.5
	local rem = {}
	if bevel > 0 then
		local r2 = math.sqrt(2)
		local function edges(axis: string)
			for _, sa in { -1, 1 } do
				for _, sb in { -1, 1 } do
					local n, k
					if axis == "x" then
						n = Vector3.new(0, sa, sb)
						k = (size.Y + size.Z) / 2 - bevel
					elseif axis == "y" then
						n = Vector3.new(sa, 0, sb)
						k = (size.X + size.Z) / 2 - bevel
					else
						n = Vector3.new(sa, sb, 0)
						k = (size.X + size.Y) / 2 - bevel
					end
					table.insert(rem, halfspace(cf, n / r2, k / r2, H))
				end
			end
		end
		for _, ax in { "x", "y", "z" } do
			if axes:find(ax) then
				edges(ax)
			end
		end
	end
	for _, c in spec.Cuts or {} do
		table.insert(rem, halfspace(cf, c.N.Unit, c.D, H))
	end
	for _, h in spec.Holes or {} do
		table.insert(rem, box(h.Size, cf * h.CFrame))
	end
	local base = box(size, cf)
	local part: BasePart = base
	if #rem > 0 then
		local ok, res = pcall(function()
			return GeometryService:SubtractAsync(base, rem, OPTS)
		end)
		if ok and res and res[1] then
			part = res[1]
			base:Destroy()
		else
			warn("[ForgeKit] subtract failed for", spec.Name, res)
		end
	end
	for _, r in rem do
		r:Destroy()
	end
	Kit.Style(part, spec.Role or "Frame")
	if part:IsA("PartOperation") then
		part.UsePartColor = true
		part.SmoothingAngle = spec.Smooth or 0
	end
	part.Name = spec.Name or spec.Role or "Block"
	part.Parent = parent
	return part
end

return Kit
