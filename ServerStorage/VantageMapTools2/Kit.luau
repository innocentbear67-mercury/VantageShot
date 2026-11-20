local K = {}
K.O = Vector3.zero
K.count = 0
K.sym = "mirror"
local cur
local SM = Enum.SurfaceType.Smooth
local M = Enum.Material
K.BLUE = Color3.fromRGB(40, 130, 255)
K.RED = Color3.fromRGB(220, 30, 80)
local S = {}
K.S = S
local function st(m, c, v, extra)
	local t = { m = m, c = c, v = v }
	if extra then for k, x in pairs(extra) do t[k] = x end end
	return t
end
K.st = st
function K.init(model, origin, sym)
	K.model = model
	K.O = origin
	K.sym = sym or "mirror"
	K.count = 0
end
function K.into(folder) cur = folder end
function K.cur() return cur end
function K.folder(name, parent)
	local f = (parent or K.model):FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent or K.model
	end
	return f
end
local function apply(p, s)
	if type(s) == "string" then s = S[s] or error("style " .. s) end
	p.Material = s.m or M.SmoothPlastic
	if s.v then p.MaterialVariant = s.v end
	p.Color = s.c or Color3.new(1, 1, 1)
	if s.t then p.Transparency = s.t end
	if s.r then p.Reflectance = s.r end
	if s.ns then p.CastShadow = false end
	if s.nc then p.CanCollide = false; p.CanQuery = false; p.CanTouch = false end
	if s.team then p:SetAttribute("Team", s.team) end
end
K.apply = apply
local function mk(class, size, cf, s, name)
	local p = Instance.new(class)
	p.Anchored = true
	p.TopSurface = SM
	p.BottomSurface = SM
	p.Size = size
	p.CFrame = CFrame.new(K.O) * cf
	apply(p, s)
	p.Name = name or "P"
	p.Parent = cur
	K.count += 1
	return p
end
K.mk = mk
function K.box(x0, x1, y0, y1, z0, z1, s, name)
	if x1 < x0 then x0, x1 = x1, x0 end
	if y1 < y0 then y0, y1 = y1, y0 end
	if z1 < z0 then z0, z1 = z1, z0 end
	return mk("Part", Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), s, name)
end
function K.part(size, cf, s, name) return mk("Part", size, cf, s, name) end
function K.cyl(a, b, d, s, name)
	local dir = b - a
	local len = dir.Magnitude
	local up = math.abs(dir.Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	local p = mk("Part", Vector3.new(len, d, d), cf, s, name)
	p.Shape = Enum.PartType.Cylinder
	return p
end
function K.vcyl(x, z, y0, y1, d, s, name) return K.cyl(Vector3.new(x, y0, z), Vector3.new(x, y1, z), d, s, name) end
function K.ball(pos, d, s, name)
	local p = mk("Part", Vector3.new(d, d, d), CFrame.new(pos), s, name)
	p.Shape = Enum.PartType.Ball
	return p
end
local DIR = { ["+z"] = 0, ["-z"] = math.pi, ["+x"] = math.pi / 2, ["-x"] = -math.pi / 2 }
K.DIR = DIR
function K.ramp(x0, x1, z0, z1, y0, y1, dir, s, name)
	local w, l
	if dir == "+z" or dir == "-z" then w, l = x1 - x0, z1 - z0 else w, l = z1 - z0, x1 - x0 end
	return mk("WedgePart", Vector3.new(w, y1 - y0, l), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(0, DIR[dir], 0), s, name)
end
function K.stairs(x0, x1, z0, z1, y0, y1, dir, s, o)
	o = o or {}
	local rise = y1 - y0
	local n = math.max(1, math.floor(math.abs(rise) / (o.step or 1) + 0.5))
	local along = (dir == "+z" or dir == "-z")
	local L = along and (z1 - z0) or (x1 - x0)
	local run = L / n
	local f = Instance.new("Model")
	f.Name = o.name or "Stairs"
	f.Parent = cur
	local prev = cur
	cur = f
	for i = 1, n do
		local top = y0 + rise * i / n
		local a = (i - 1) * run
		local b = i * run
		local bottom = o.open and (top - 0.8) or math.min(y0, top) - (o.sink or 0)
		if dir == "+z" then K.box(x0, x1, bottom, top, z0 + a, z0 + b, s, "Step")
		elseif dir == "-z" then K.box(x0, x1, bottom, top, z1 - b, z1 - a, s, "Step")
		elseif dir == "+x" then K.box(x0 + a, x0 + b, bottom, top, z0, z1, s, "Step")
		else K.box(x1 - b, x1 - a, bottom, top, z0, z1, s, "Step") end
	end
	if o.stringer then
		local ss = o.stringer
		if along then
			local za = dir == "+z" and z0 or z1
			local zb = dir == "+z" and z1 or z0
			for _, x in ipairs({ x0 - 0.3, x1 + 0.3 }) do
				K.cyl(Vector3.new(x, y0 - 0.2, za), Vector3.new(x, y1 - 0.6, zb), 1.0, ss, "Stringer").Shape = Enum.PartType.Block
			end
		else
			local xa = dir == "+x" and x0 or x1
			local xb = dir == "+x" and x1 or x0
			for _, z in ipairs({ z0 - 0.3, z1 + 0.3 }) do
				K.cyl(Vector3.new(xa, y0 - 0.2, z), Vector3.new(xb, y1 - 0.6, z), 1.0, ss, "Stringer").Shape = Enum.PartType.Block
			end
		end
	end
	if o.rail then
		local rs = o.railStyle or "railYellow"
		local function railAt(side)
			local pA, pB
			if along then
				local x = side < 0 and x0 + 0.2 or x1 - 0.2
				local za = dir == "+z" and z0 or z1
				local zb = dir == "+z" and z1 or z0
				pA = Vector3.new(x, y0 + 3.4, za)
				pB = Vector3.new(x, y1 + 3.4, zb)
			else
				local z = side < 0 and z0 + 0.2 or z1 - 0.2
				local xa = dir == "+x" and x0 or x1
				local xb = dir == "+x" and x1 or x0
				pA = Vector3.new(xa, y0 + 3.4, z)
				pB = Vector3.new(xb, y1 + 3.4, z)
			end
			K.cyl(pA, pB, 0.35, rs, "Handrail")
			local posts = math.max(2, math.floor((pB - pA).Magnitude / 6))
			for i = 0, posts do
				local p = pA:Lerp(pB, i / posts)
				K.box(p.X - 0.15, p.X + 0.15, p.Y - 3.4, p.Y, p.Z - 0.15, p.Z + 0.15, rs, "RailPost")
			end
		end
		if o.rail ~= "R" then railAt(-1) end
		if o.rail ~= "L" then railAt(1) end
	end
	cur = prev
	return f
end
function K.railing(a, b, s, h, gap)
	h = h or 3.5
	s = s or "railYellow"
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / (gap or 5)))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		K.box(p.X - 0.15, p.X + 0.15, p.Y, p.Y + h, p.Z - 0.15, p.Z + 0.15, s, "RailPost")
	end
	K.cyl(a + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0), 0.35, s, "Rail")
	K.cyl(a + Vector3.new(0, h * 0.5, 0), b + Vector3.new(0, h * 0.5, 0), 0.25, s, "Rail")
end
function K.light(part, kind, color, range, bright, face, angle)
	local l = Instance.new(kind or "SpotLight")
	l.Color = color or Color3.fromRGB(255, 196, 140)
	l.Range = range or 22
	l.Brightness = bright or 1.6
	if l:IsA("SpotLight") or l:IsA("SurfaceLight") then
		l.Face = face or Enum.NormalId.Bottom
		l.Angle = angle or 110
	end
	l.Shadows = false
	l.Parent = part
	return l
end
local NV = { ["+x"] = Vector3.xAxis, ["-x"] = -Vector3.xAxis, ["+z"] = Vector3.zAxis, ["-z"] = -Vector3.zAxis }
K.NV = NV
function K.wallLamp(pos, n, col)
	local nv = NV[n]
	local down = Vector3.new(0, 0.2, 0)
	K.part(Vector3.new(0.4, 0.4, 1.4), CFrame.lookAt(pos + nv * 0.5, pos + nv * 2), "steelDark", "LampArm")
	local hcf = CFrame.lookAt(pos + nv * 1.2 - down, pos + nv * 3 - down)
	K.part(Vector3.new(1.8, 0.7, 1.4), hcf, "steelDark", "LampHead")
	local lens = K.part(Vector3.new(1.5, 0.12, 1.1), hcf * CFrame.new(0, -0.38, 0), "lampWarm", "Lens")
	K.light(lens, "SpotLight", col, 26, 2.2, Enum.NormalId.Bottom, 120)
	return lens
end
function K.streetLamp(x, z, dir, h, col)
	h = h or 18
	local nv = NV[dir]
	K.vcyl(x, z, 0, 0.8, 1.6, "concrete", "LampBase")
	K.vcyl(x, z, 0.8, h, 0.7, "steelDark", "LampPole")
	local tip = Vector3.new(x, h, z) + nv * 4
	K.cyl(Vector3.new(x, h - 0.3, z), tip, 0.4, "steelDark", "LampArm")
	K.box(tip.X - 1.1, tip.X + 1.1, h - 0.9, h - 0.1, tip.Z - 1.1, tip.Z + 1.1, "steelDark", "LampHead")
	local lens = K.box(tip.X - 0.9, tip.X + 0.9, h - 1.0, h - 0.85, tip.Z - 0.9, tip.Z + 0.9, "lampWarm", "Lens")
	K.light(lens, "SpotLight", col, 40, 2.4, Enum.NormalId.Bottom, 130)
end
function K.sign(cf, size, text, bg, fg, font, glow)
	local p = K.part(size, cf, bg or "signDark", "Sign")
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = math.clamp(130 / size.Y, 6, 40)
	g.LightInfluence = glow and 0 or 1
	g.Brightness = glow and 1.4 or 1
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.TextScaled = true
	t.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	local sk = Instance.new("UIStroke"); sk.Thickness = 2; sk.Color = Color3.fromRGB(20, 24, 34); sk.Transparency = 0.15; sk.Parent = t
	t.TextColor3 = fg or Color3.fromRGB(240, 240, 236)
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0); pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.12, 0); pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = t
	return p
end
function K.facadeSign(pos, n, w, h, text, bg, fg, font, glow)
	local nv = NV[n]
	return K.sign(CFrame.lookAt(pos + nv * 0.25, pos + nv * 2), Vector3.new(w, h, 0.4), text, bg, fg, font, glow)
end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
K.rgb = rgb
function K.palette(name)
	for k in pairs(S) do S[k] = nil end
	S.lampWarm = st(M.Neon, rgb(255, 214, 160), nil, { ns = true })
	S.lampCool = st(M.Neon, rgb(220, 236, 255), nil, { ns = true })
	S.glowOrange = st(M.Neon, rgb(255, 118, 32), nil, { ns = true })
	S.signDark = st(M.SmoothPlastic, rgb(34, 38, 44))
	S.black = st(M.SmoothPlastic, rgb(26, 27, 30))
	S.tyre = st(M.SmoothPlastic, rgb(30, 30, 32))
	S.paintWhite = st(M.SmoothPlastic, rgb(228, 228, 222), nil, { nc = true })
	S.paintYellow = st(M.SmoothPlastic, rgb(236, 186, 44), nil, { nc = true })
	S.teamPanel = st(M.SmoothPlastic, K.BLUE, nil, { team = "Blue" })
	S.teamGlow = st(M.Neon, K.BLUE, nil, { team = "Blue", ns = true })
	S.invisible = st(M.SmoothPlastic, rgb(255, 255, 255), nil, { t = 1, ns = true })
	S.glass = st(M.Glass, rgb(132, 160, 172), nil, { t = 0.3, r = 0.12 })
	S.glassDark = st(M.Glass, rgb(58, 76, 88), nil, { t = 0.15, r = 0.18 })
	if name == "foundry" then
		local C, V2 = "FR_Corrugated", "FR_PaintedSteel"
		S.slab = st(M.Concrete, rgb(176, 174, 168), "FR_YardConcrete")
		S.asphalt = st(M.Asphalt, rgb(92, 94, 98))
		S.gravel = st(M.Pebble, rgb(140, 130, 118))
		S.concrete = st(M.Concrete, rgb(192, 188, 180))
		S.concreteStain = st(M.Concrete, rgb(158, 154, 146))
		S.precast = st(M.Concrete, rgb(222, 218, 208), "FR_PrecastPanel")
		S.sealed = st(M.Concrete, rgb(150, 148, 144), "VS_SealedFloor")
		S.cladGrey = st(M.Metal, rgb(172, 176, 182), C)
		S.cladRed = st(M.Metal, rgb(198, 94, 68), C)
		S.cladTeal = st(M.Metal, rgb(90, 144, 138), C)
		S.cladCream = st(M.Metal, rgb(234, 226, 206), C)
		S.cladBlue = st(M.Metal, rgb(112, 140, 174), C)
		S.cladOrange = st(M.Metal, rgb(222, 132, 72), C)
		S.roof = st(M.Metal, rgb(140, 144, 150), C)
		S.steel = st(M.Metal, rgb(124, 130, 138), V2)
		S.steelDark = st(M.Metal, rgb(72, 76, 84), V2)
		S.steelBare = st(M.Metal, rgb(168, 170, 174))
		S.tread = st(M.DiamondPlate, rgb(150, 152, 156))
		S.railYellow = st(M.Metal, rgb(242, 192, 46), V2)
		S.yellow = st(M.Metal, rgb(242, 192, 46), V2)
		S.oxide = st(M.Metal, rgb(178, 82, 58), V2)
		S.teal = st(M.Metal, rgb(82, 136, 130), V2)
		S.rust = st(M.CorrodedMetal, rgb(150, 112, 92))
		S.brick = st(M.Brick, rgb(156, 90, 70))
		S.brickDark = st(M.Brick, rgb(112, 70, 58))
		S.refractory = st(M.Brick, rgb(124, 106, 98))
		S.wood = st(M.WoodPlanks, rgb(170, 132, 90))
		S.woodPallet = st(M.Wood, rgb(186, 148, 102))
		S.frame = st(M.Metal, rgb(78, 82, 90), V2)
		S.frosted = st(M.Glass, rgb(206, 216, 222), nil, { t = 0.2, r = 0.05 })
		S.wrap = st(M.SmoothPlastic, rgb(222, 226, 230), nil, { t = 0.1 })
		S.hazard = st(M.SmoothPlastic, rgb(32, 32, 34))
		S.green = st(M.Metal, rgb(86, 126, 98), V2)
		S.redPaint = st(M.SmoothPlastic, rgb(196, 44, 40))
		S.molten = st(M.Neon, rgb(255, 128, 36), nil, { ns = true })
		S.hill = st(M.Grass, rgb(104, 118, 86))
		S.far = st(M.Concrete, rgb(168, 172, 178), nil, { ns = true })
		S.farDark = st(M.Concrete, rgb(128, 134, 142), nil, { ns = true })
	end
end
local RY = CFrame.Angles(0, math.pi, 0)
local function mirrorCF(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local zc = K.O.Z
	return CFrame.new(x, y, 2 * zc - z, r00, r01, -r02, r10, r11, -r12, -r20, -r21, r22) * RY
end
local function rotCF(cf)
	return CFrame.new(K.O) * RY * CFrame.new(-K.O) * cf
end
K.mirrorCF = mirrorCF
K.rotCF = rotCF
local function swapTeam(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		local t = d:GetAttribute("Team")
		if t == "Blue" then
			d:SetAttribute("Team", "Red")
			if d:IsA("BasePart") then
				if d.Color == K.BLUE then d.Color = K.RED end
				if d:IsA("SpawnLocation") then d.TeamColor = BrickColor.new("Really red"); d.Name = "RedSpawn" end
			end
			if d:IsA("Light") then d.Color = K.RED end
		end
		if d:IsA("TextLabel") and d.Text == "BLUE" then d.Text = "RED" end
	end
end
function K.twin(srcFolder, dstName)
	local dst = srcFolder:Clone()
	dst.Name = dstName or "Red"
	local f = K.sym == "mirror" and mirrorCF or rotCF
	for _, d in ipairs(dst:GetDescendants()) do
		if d:IsA("BasePart") then d.CFrame = f(d.CFrame) end
	end
	swapTeam(dst)
	dst.Parent = srcFolder.Parent
	return dst
end
return K
