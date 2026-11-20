-- VantageMapTools.Kit
-- Reusable modular architecture pieces for the Vantage arena.
-- Every part carries a "Role" attribute; styles are resolved from K.Styles so the
-- whole map can be re-themed (or rendered as a plain greybox) from one table.

local K = {}
K.Stage = "final" -- "greybox" | "final"
K.count = 0

local V = Vector3.new
local C = Color3.fromRGB
local M = Enum.Material

K.Styles = {
	Floor         = {M.Concrete,      C(172, 176, 182)},
	FloorAlt      = {M.Concrete,      C(161, 165, 172)},
	FloorDark     = {M.Metal,         C(66, 71, 80)},
	Structure     = {M.Concrete,      C(128, 133, 142)},
	WallLight     = {M.SmoothPlastic, C(196, 201, 209)},
	WallDark      = {M.Metal,         C(48, 53, 62)},
	Trim          = {M.Metal,         C(92, 99, 110)},
	Deck          = {M.DiamondPlate,  C(104, 110, 120)},
	Cover         = {M.Metal,         C(56, 61, 71)},
	CoverLight    = {M.SmoothPlastic, C(178, 183, 191)},
	Container     = {M.Metal,         C(60, 68, 82)},
	Glass         = {M.Glass,         C(70, 110, 150), 0.25},
	Paint         = {M.SmoothPlastic, C(232, 234, 238)},
	PaintDark     = {M.SmoothPlastic, C(52, 56, 64)},
	Hazard        = {M.SmoothPlastic, C(236, 178, 36)},
	NeonBlue      = {M.Neon,          C(20, 96, 255)},
	NeonRed       = {M.Neon,          C(255, 36, 56)},
	NeonWhite     = {M.Neon,          C(225, 234, 248)},
	NeonAmber     = {M.Neon,          C(255, 170, 60)},
	TeamBlue      = {M.SmoothPlastic, C(26, 88, 205)},
	TeamRed       = {M.SmoothPlastic, C(198, 32, 46)},
	SpawnBlue     = {M.Metal,         C(30, 60, 120)},
	SpawnRed      = {M.Metal,         C(120, 30, 40)},
	Backdrop      = {M.Concrete,      C(74, 82, 96)},
	BackdropLight = {M.SmoothPlastic, C(150, 160, 176)},
	Invisible     = {M.SmoothPlastic, C(255, 255, 255), 1},
	Collision     = {M.SmoothPlastic, C(255, 255, 255), 1},
}

-- greybox overrides (plain SmoothPlastic, cover in orange so it reads at a glance)
local Grey = {
	Floor = C(190, 190, 190), FloorAlt = C(178, 178, 178), FloorDark = C(120, 120, 120),
	Structure = C(140, 140, 140), WallLight = C(165, 165, 165), WallDark = C(105, 105, 105),
	Trim = C(120, 120, 120), Deck = C(150, 160, 175), Cover = C(225, 150, 80),
	CoverLight = C(235, 175, 110), Container = C(210, 130, 70),
	SpawnBlue = C(40, 90, 200), SpawnRed = C(200, 50, 50),
}

function K.style(p: BasePart, role: string)
	local st = K.Styles[role] or K.Styles.Structure
	local mat, col, tr = st[1], st[2], st[3] or 0
	if K.Stage == "greybox" and Grey[role] then
		mat = M.SmoothPlastic
		col = Grey[role]
	end
	p.Material = mat
	p.Color = col
	p.Transparency = tr
	if mat == M.Neon or tr >= 1 then
		p.CastShadow = false
	end
end

function K.part(parent: Instance, name: string, size: Vector3, cf: CFrame, role: string, o: any?): BasePart
	local opt = o or {}
	local p: any = Instance.new(opt.class or "Part")
	if opt.shape then p.Shape = opt.shape end
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Role", role)
	K.style(p, role)
	if opt.deco then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	if opt.nocollide then p.CanCollide = false end
	p.Parent = parent
	K.count = K.count + 1
	return p
end

-- axis aligned box from min/max extents (any order)
function K.box(parent, name, x0, x1, y0, y1, z0, z1, role, o)
	local ax, bx = math.min(x0, x1), math.max(x0, x1)
	local ay, by = math.min(y0, y1), math.max(y0, y1)
	local az, bz = math.min(z0, z1), math.max(z0, z1)
	return K.part(parent, name, V(bx - ax, by - ay, bz - az), CFrame.new((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), role, o)
end

-- part stretched between two points (non vertical), cross-section w x h
function K.beam(parent, name, a: Vector3, b: Vector3, w, h, role, o)
	local mid = (a + b) / 2
	return K.part(parent, name, V(w, h, (b - a).Magnitude), CFrame.lookAt(mid, b), role, o)
end

function K.neon(team: string?): string
	if team == "Blue" then return "NeonBlue" end
	if team == "Red" then return "NeonRed" end
	return "NeonWhite"
end

function K.teamOf(x: number): string?
	if x < -30 then return "Blue" end
	if x > 30 then return "Red" end
	return nil
end

local function model(parent, name, prefab)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Prefab", prefab)
	m.Parent = parent
	return m
end
K.model = model

local function basecf(pos: Vector3, rot: number?)
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(rot or 0), 0)
end

local function lp(m, name, size, base: CFrame, off: Vector3, role, o)
	return K.part(m, name, size, base * CFrame.new(off), role, o)
end

local function final()
	return K.Stage ~= "greybox"
end

---------------------------------------------------------------- prefabs

-- Crate: pos = bottom centre
function K.crate(parent, name, pos, size: Vector3, o)
	o = o or {}
	local m = model(parent, name, "Crate")
	local cf = basecf(pos, o.rot)
	lp(m, "Body", size, cf, V(0, size.Y / 2, 0), o.role or "Container")
	lp(m, "Lid", V(size.X + 0.3, 0.35, size.Z + 0.3), cf, V(0, size.Y - 0.175, 0), "Trim")
	lp(m, "Skirt", V(size.X + 0.3, 0.35, size.Z + 0.3), cf, V(0, 0.175, 0), "Trim")
	if final() then
		lp(m, "Panel", V(size.X * 0.72, size.Y * 0.42, size.Z + 0.12), cf, V(0, size.Y * 0.34, 0), "CoverLight", {deco = true})
		lp(m, "Accent", V(size.X + 0.08, 0.2, size.Z + 0.08), cf, V(0, size.Y * 0.66, 0), K.neon(o.team), {deco = true})
	end
	return m
end

-- Waist-high barrier (3.8 studs). Length along local X; rot = yaw degrees.
function K.waist(parent, name, pos, len, o)
	o = o or {}
	local m = model(parent, name, "WaistCover")
	local cf = basecf(pos, o.rot)
	lp(m, "Plinth", V(len + 0.4, 0.4, 2.8), cf, V(0, 0.2, 0), "Trim")
	lp(m, "Body", V(len, 3, 2.2), cf, V(0, 1.9, 0), "Cover")
	lp(m, "Cap", V(len + 0.2, 0.4, 2.6), cf, V(0, 3.6, 0), "CoverLight")
	if final() then
		lp(m, "Accent", V(len + 0.06, 0.18, 2.26), cf, V(0, 2.7, 0), K.neon(o.team), {deco = true})
	end
	return m
end

-- Full-height cover / solid block. len along local X, thick along local Z.
function K.full(parent, name, pos, len, h, thick, o)
	o = o or {}
	local m = model(parent, name, "FullCover")
	local cf = basecf(pos, o.rot)
	lp(m, "Base", V(len + 0.4, 0.6, thick + 0.4), cf, V(0, 0.3, 0), "WallDark")
	lp(m, "Body", V(len, h - 1, thick), cf, V(0, 0.6 + (h - 1) / 2, 0), o.role or "Cover")
	lp(m, "Cap", V(len + 0.3, 0.4, thick + 0.3), cf, V(0, h - 0.2, 0), "Trim")
	if final() then
		lp(m, "Inset", V(len * 0.8, h * 0.42, thick + 0.16), cf, V(0, h * 0.42, 0), o.inset or "CoverLight", {deco = true})
		lp(m, "Accent", V(len + 0.06, 0.2, thick + 0.06), cf, V(0, h - 1.1, 0), K.neon(o.team), {deco = true})
		lp(m, "AccentLow", V(len + 0.46, 0.14, thick + 0.46), cf, V(0, 0.65, 0), K.neon(o.team), {deco = true})
	end
	return m
end

-- Parapet / railing wall along a -> b (points at floor height of the deck)
function K.parapet(parent, name, a: Vector3, b: Vector3, h, o)
	o = o or {}
	local m = model(parent, name, "Parapet")
	local d = b - a
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + d.Unit)
	lp(m, "Panel", V(0.8, h - 0.35, d.Magnitude), cf, V(0, (h - 0.35) / 2, 0), "WallDark")
	lp(m, "Cap", V(1.1, 0.35, d.Magnitude + 0.1), cf, V(0, h - 0.175, 0), "Trim")
	if final() then
		lp(m, "Accent", V(0.9, 0.15, d.Magnitude), cf, V(0, h - 0.75, 0), K.neon(o.team), {deco = true})
	end
	return m
end

-- Stairs: invisible wedge collision + visual steps + stringers + handrails.
-- base = bottom-front centre on the floor, dir = horizontal climb direction.
function K.stairs(parent, name, base: Vector3, dir: Vector3, width, run, rise, o)
	o = o or {}
	local m = model(parent, name, o.ramp and "Ramp" or "Stairs")
	dir = V(dir.X, 0, dir.Z).Unit
	local right = dir:Cross(Vector3.yAxis)
	local up = V(0, 1, 0)
	local center = base + dir * (run / 2) + up * (rise / 2)
	local wedgeCf = CFrame.lookAt(center, center - dir)
	if o.ramp then
		lp(m, "Ramp", V(width, rise, run), wedgeCf, V(0, 0, 0), "Deck", {class = "WedgePart"})
		if final() then
			for _, sgn in ipairs({-1, 1}) do
				local a = base + right * (sgn * (width / 2 + 0.1)) + up * 0.05
				local b = a + dir * run + up * rise
				K.beam(m, "EdgeLight", a, b, 0.2, 0.2, K.neon(o.team), {deco = true})
			end
		end
		return m
	end
	lp(m, "Collision", V(width, rise, run), wedgeCf, V(0, 0, 0), "Collision", {class = "WedgePart"})
	local n = math.max(1, math.floor(rise + 0.5))
	local h = rise / n
	local d = run / n
	local look = CFrame.lookAt(V(0, 0, 0), dir)
	for i = 1, n do
		local top = i * h - h * 0.5
		local pos = base + dir * ((i - 0.5) * d) + up * (top - h / 2)
		K.part(m, "Step", V(width, h, d + 0.05), look + pos, o.stepRole or "Deck", {deco = true})
	end
	for _, sgn in ipairs({-1, 1}) do
		local side = right * (sgn * (width / 2 + 0.35))
		local a = base + side + up * 0.2
		local b = base + side + dir * run + up * (rise + 0.2)
		K.beam(m, "Stringer", a, b, 0.7, 1.8, "WallDark")
		if o.rails ~= false then
			K.beam(m, "Handrail", a + up * 3.2, b + up * 3.2, 0.35, 0.35, "Trim", {deco = true})
			if final() then
				K.beam(m, "RailLight", a + up * 2.95, b + up * 2.95, 0.2, 0.15, K.neon(o.team), {deco = true})
			end
			for _, t in ipairs({0.04, 0.5, 0.96}) do
				local p = a:Lerp(b, t)
				K.part(m, "Post", V(0.35, 3.2, 0.35), CFrame.new(p + up * 1.6), "Trim", {deco = true})
			end
		end
	end
	return m
end

-- Team emblem (stylised V) on a wall. cf: centre on the wall face, LookVector pointing out of the wall.
function K.emblem(parent, name, cf: CFrame, w, h, team)
	local m = model(parent, name, "Emblem")
	local field = team == "Blue" and "TeamBlue" or (team == "Red" and "TeamRed" or "WallDark")
	K.part(m, "Frame", V(w + 1.2, h + 1.2, 0.3), cf * CFrame.new(0, 0, -0.15), "WallDark", {deco = true})
	K.part(m, "Field", V(w, h, 0.3), cf * CFrame.new(0, 0, -0.35), field, {deco = true})
	K.part(m, "Edge", V(w + 0.4, 0.18, 0.2), cf * CFrame.new(0, -h / 2 - 0.3, -0.4), K.neon(team), {deco = true})
	K.part(m, "Edge", V(w + 0.4, 0.18, 0.2), cf * CFrame.new(0, h / 2 + 0.3, -0.4), K.neon(team), {deco = true})
	local L = h * 0.7
	local th = math.rad(24)
	local bw = math.max(0.5, w * 0.075)
	for _, sgn in ipairs({-1, 1}) do
		local off = CFrame.new(sgn * L * 0.5 * math.sin(th), 0, -0.6) * CFrame.Angles(0, 0, -sgn * th)
		K.part(m, "V", V(bw, L, 0.2), cf * off, "NeonWhite", {deco = true})
	end
	return m
end

-- Light fixture: a glowing deco part carrying a light instance.
function K.fixture(parent, name, size: Vector3, cf: CFrame, lightClass: string, props, role)
	local p = K.part(parent, name, size, cf, role or "NeonWhite", {deco = true})
	local l: any = Instance.new(lightClass)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = p
	return p
end

return K
