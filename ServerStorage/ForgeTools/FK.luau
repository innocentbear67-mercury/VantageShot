-- ForgeTools.FK : build kit for the enclosed megastructure (Map_LiveFire, Nov 2026)
local FK = {}
local V, C, M = Vector3.new, Color3.fromRGB, Enum.Material
FK.FY, FK.T1, FK.T2, FK.T3, FK.ROOF = 2.1, 18, 34, 62, 180
FK.count = 0
FK.S = {
	Hull = {M.DiamondPlate, "Eclipse_MilitaryPlate", C(118, 124, 132)},
	HullDark = {M.DiamondPlate, "Eclipse_MilitaryPlate", C(90, 95, 104)},
	Forged = {M.Metal, "VS_ForgedPanel", C(104, 110, 120)},
	ForgedDark = {M.Metal, "VS_ForgedPanel", C(80, 85, 94)},
	Gun = {M.Metal, "VS_Gunmetal", C(84, 89, 98)},
	Steel = {M.Metal, "VS_PaintedSteel", C(142, 148, 156)},
	Titan = {M.Metal, "VS_PaintedSteel", C(128, 134, 142)},
	Rib = {M.Metal, "Eclipse_RibbedWall", C(84, 90, 100)},
	Corr = {M.Metal, "VS_CorrugatedSteel", C(86, 92, 102)},
	Floor = {M.Concrete, "VS_SealedFloor", C(96, 100, 106)},
	FloorDark = {M.Concrete, "VS_SealedFloor", C(70, 73, 79)},
	FloorPlate = {M.DiamondPlate, "VS_TreadPlate", C(78, 82, 90)},
	Deck = {M.DiamondPlate, "VS_TreadPlate", C(104, 109, 118)},
	HazardFloor = {M.DiamondPlate, "Eclipse_IndustrialFloor", C(170, 170, 170)},
	Trim = {M.Metal, "", C(72, 77, 86)},
	TrimLight = {M.Metal, "", C(120, 126, 134)},
	Hazard = {M.SmoothPlastic, "", C(226, 170, 30)},
	Paint = {M.SmoothPlastic, "", C(210, 214, 220)},
	Lime = {M.Neon, "", C(96, 235, 0)},
	Amber = {M.Neon, "", C(255, 96, 20)},
	White = {M.Neon, "", C(214, 230, 255)},
	Blue = {M.Neon, "", C(40, 120, 255)},
	Red = {M.Neon, "", C(255, 52, 60)},
	Glass = {M.Glass, "", C(110, 140, 160), 0.6},
	Invis = {M.SmoothPlastic, "", C(255, 255, 255), 1},
}
FK.Gain = 1.4
for k, st in pairs(FK.S) do
	if st[1] ~= M.Neon and k ~= "Hazard" and k ~= "Paint" and k ~= "Glass" and k ~= "Invis" then
		local c = st[3]
		st[3] = Color3.new(math.min(1, c.R * FK.Gain), math.min(1, c.G * FK.Gain), math.min(1, c.B * FK.Gain))
	end
end
function FK.style(p, s)
	local st = FK.S[s]
	if not st then error("unknown style " .. tostring(s)) end
	p.Material = st[1]
	p.MaterialVariant = st[2]
	p.Color = st[3]
	p.Transparency = st[4] or 0
	if st[1] == M.Neon or (st[4] or 0) >= 1 then p.CastShadow = false end
end
function FK.folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
function FK.part(parent, name, size, cf, style, o)
	o = o or {}
	local p = Instance.new(o.class or "Part")
	if o.shape then p.Shape = o.shape end
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	FK.style(p, style)
	if o.deco then p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false end
	if o.noshadow then p.CastShadow = false end
	if o.nocollide then p.CanCollide = false end
	if o.noquery then p.CanQuery = false end
	if o.color then p.Color = o.color end
	if o.tr then p.Transparency = o.tr end
	p.Parent = parent
	FK.count += 1
	return p
end
function FK.box(parent, name, x0, x1, y0, y1, z0, z1, style, o)
	local ax, bx = math.min(x0, x1), math.max(x0, x1)
	local ay, by = math.min(y0, y1), math.max(y0, y1)
	local az, bz = math.min(z0, z1), math.max(z0, z1)
	return FK.part(parent, name, V(bx - ax, by - ay, bz - az), CFrame.new((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), style, o)
end
-- part stretched between two points; cross-section w (horizontal) x h
function FK.beam(parent, name, a, b, w, h, style, o)
	local mid = (a + b) / 2
	local d = b - a
	local cf
	if math.abs(d.Unit.Y) > 0.999 then
		cf = CFrame.lookAt(mid, b, Vector3.xAxis)
	else
		cf = CFrame.lookAt(mid, b)
	end
	return FK.part(parent, name, V(w, h, d.Magnitude), cf, style, o)
end
-- vertical cylinder, center = geometric centre
function FK.cyl(parent, name, x, z, y0, y1, dia, style, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return FK.part(parent, name, V(y1 - y0, dia, dia), CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), style, o)
end
-- cylinder (pipe) between two points
function FK.pipe(parent, name, a, b, dia, style, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	local mid = (a + b) / 2
	local d = b - a
	local cf
	if math.abs(d.Unit.Y) > 0.999 then
		cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.rad(90))
	else
		cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
	end
	return FK.part(parent, name, V(d.Magnitude, dia, dia), cf, style, o)
end
function FK.light(part, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do l[k] = v end
	l.Parent = part
	return l
end
-- glowing fixture with a light
function FK.fixture(parent, name, x0, x1, y0, y1, z0, z1, style, class, props)
	local p = FK.box(parent, name, x0, x1, y0, y1, z0, z1, style, {deco = true})
	FK.light(p, class, props)
	return p
end
-- railing between two deck-level points
function FK.rail(parent, a, b, o)
	o = o or {}
	local up = V(0, 1, 0)
	local len = (b - a).Magnitude
	if len < 0.5 then return end
	FK.beam(parent, "RailTop", a + up * 3.5, b + up * 3.5, 0.4, 0.4, o.style or "Steel", {deco = true})
	FK.beam(parent, "RailKick", a + up * 0.55, b + up * 0.55, 0.3, 1.1, "Trim", {noshadow = true})
	FK.beam(parent, "RailMid", a + up * 2, b + up * 2, 0.2, 0.2, "Trim", {deco = true})
	local c = FK.beam(parent, "RailCollision", a + up * 1.85, b + up * 1.85, 0.5, 3.7, "Invis", {noquery = true})
	local n = math.max(1, math.floor(len / 9 + 0.5))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		FK.part(parent, "RailPost", V(0.4, 3.5, 0.4), CFrame.new(p + up * 1.75), "Trim", {deco = true})
	end
end
-- structural column with foot and cap
function FK.column(parent, name, x, z, y0, y1, w, o)
	o = o or {}
	local st = o.style or "Gun"
	FK.box(parent, name, x - w / 2, x + w / 2, y0, y1, z - w / 2, z + w / 2, st)
	FK.box(parent, name .. "Foot", x - w / 2 - 0.6, x + w / 2 + 0.6, y0, y0 + 1.2, z - w / 2 - 0.6, z + w / 2 + 0.6, "Trim", {noshadow = true})
	if not o.nocap then
		FK.box(parent, name .. "Cap", x - w / 2 - 0.6, x + w / 2 + 0.6, y1 - 1, y1, z - w / 2 - 0.6, z + w / 2 + 0.6, "Trim", {noshadow = true})
	end
	if o.hazard then
		FK.box(parent, name .. "Band", x - w / 2 - 0.08, x + w / 2 + 0.08, y0 + 3, y0 + 4.4, z - w / 2 - 0.08, z + w / 2 + 0.08, "Hazard", {deco = true})
	end
end
-- deck slab with under-frame; cols = {{x,z},...}; y = walking surface
function FK.deck(parent, name, x0, x1, z0, z1, y, o)
	o = o or {}
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	FK.box(m, "Slab", x0, x1, y - 1, y, z0, z1, o.style or "Deck")
	FK.box(m, "Frame", x0 + 0.4, x1 - 0.4, y - 2.4, y - 1, z0 + 0.4, z1 - 0.4, "Trim", {noshadow = true})
	if o.edge then
		local e = o.edge
		FK.box(m, "EdgeLight", x0 - 0.06, x1 + 0.06, y - 0.75, y - 0.5, z0 - 0.06, z1 + 0.06, e, {deco = true})
	end
	for _, c in ipairs(o.cols or {}) do
		FK.column(m, "Support", c[1], c[2], o.colBase or FK.FY, y - 2.4, o.colW or 2.6, {hazard = o.hazard})
	end
	return m
end
-- stairs: invisible wedge collision + steps + stringers + rails. base = bottom-front centre.
function FK.stairs(parent, name, base, dir, width, run, rise, o)
	o = o or {}
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	dir = V(dir.X, 0, dir.Z).Unit
	local right = dir:Cross(Vector3.yAxis)
	local up = V(0, 1, 0)
	local center = base + dir * (run / 2) + up * (rise / 2)
	FK.part(m, "Collision", V(width, rise, run), CFrame.lookAt(center, center - dir), "Invis", {class = "WedgePart"})
	local n = math.max(1, math.floor(rise / 1.0 + 0.5))
	local h = rise / n
	local d = run / n
	local look = CFrame.lookAt(V(0, 0, 0), dir)
	for i = 1, n do
		local pos = base + dir * ((i - 0.5) * d) + up * (i * h - 0.25)
		FK.part(m, "Step", V(width, 0.5, d + 0.3), look + pos, o.stepStyle or "Deck", {deco = true})
	end
	for _, sgn in ipairs({-1, 1}) do
		local side = right * (sgn * (width / 2 + 0.3))
		local a = base + side - up * 0.4
		local b = base + side + dir * run + up * (rise - 0.4)
		FK.beam(m, "Stringer", a, b, 0.6, 1.6, "Trim")
		if o.rails ~= false then
			FK.beam(m, "Handrail", a + up * 3.9, b + up * 3.9, 0.4, 0.4, "Steel", {deco = true})
			local c = FK.beam(m, "RailCollision", a + up * 2.2, b + up * 2.2, 0.5, 3.6, "Invis", {noquery = true})
			for _, t in ipairs({0.03, 0.5, 0.97}) do
				local p = a:Lerp(b, t)
				FK.part(m, "Post", V(0.4, 3.9, 0.4), CFrame.new(p + up * 1.95), "Trim", {deco = true})
			end
		end
	end
	-- a solid dark skirt under the flight so it never reads as floating
	if o.skirt ~= false then
		local sk = base + dir * (run / 2) + up * (rise / 2 - 1.2)
		FK.part(m, "Soffit", V(width - 0.4, rise - 0.2, run - 0.4), CFrame.lookAt(sk, sk - dir), "Gun", {class = "WedgePart", deco = true})
	end
	return m
end
-- stencilled wall sign; cf faces outward (LookVector = normal)
function FK.sign(parent, cf, w, h, text, color, o)
	o = o or {}
	local p = FK.part(parent, "Sign", V(w, h, 0.1), cf, "Invis", {deco = true})
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.pps or 12
	g.LightInfluence = o.glow and 0 or 0.6
	g.Brightness = o.glow and 2 or 1
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.Michroma
	t.TextColor3 = color or C(210, 214, 220)
	t.TextTransparency = o.tt or 0.15
	t.Parent = g
	return p
end
-- place a library model by its bounding-box bottom centre
function FK.place(parent, lib, name, cf)
	local src = game:GetService("ServerStorage")[lib]:FindFirstChild(name)
	if not src then error("missing kit " .. name) end
	local c = src:Clone()
	local bcf, size = c:GetBoundingBox()
	local bottom = bcf * CFrame.new(0, -size.Y / 2, 0)
	c:PivotTo((cf * bottom:Inverse()) * c:GetPivot())
	c.Parent = parent
	FK.count += #c:GetDescendants()
	return c
end
-- move a staged (unparented) folder's children into the DataModel in small batches
function FK.commit(staging, parent)
	local dest = parent:FindFirstChild(staging.Name)
	if dest then dest:Destroy() end
	dest = Instance.new("Folder")
	dest.Name = staging.Name
	dest.Parent = parent
	local n = 0
	local function move(src, dst)
		for _, c in ipairs(src:GetChildren()) do
			if c:IsA("Folder") then
				local f = Instance.new("Folder")
				f.Name = c.Name
				f.Parent = dst
				move(c, f)
			else
				n += 1 + #c:GetDescendants()
				c.Parent = dst
				if n > 400 then n = 0 task.wait() end
			end
		end
	end
	move(staging, dest)
	return dest
end
return FK
