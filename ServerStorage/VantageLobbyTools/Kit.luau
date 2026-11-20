local K = {}
K.O = CFrame.new(0, 3000, 0)
local RGB = Color3.fromRGB
K.C = {
	CH = RGB(46, 48, 56), CH2 = RGB(62, 65, 75), SL = RGB(98, 102, 114), LG = RGB(160, 162, 168), LG2 = RGB(186, 188, 192),
	WH = RGB(236, 234, 228), OR = RGB(240, 122, 32), RD = RGB(226, 52, 52), BL = RGB(46, 120, 238), WARM = RGB(255, 214, 160),
	GR = RGB(78, 146, 56), GR2 = RGB(62, 122, 46), GR3 = RGB(98, 168, 70), TR = RGB(112, 76, 48), GRASS = RGB(84, 150, 60),
}
K.M = Enum.Material
K.FONT = Font.fromName("BuilderSans", Enum.FontWeight.ExtraBold)
K.FONT_B = Font.fromName("BuilderSans", Enum.FontWeight.Bold)
function K.folder(parent, name)
	local f = parent:FindFirstChild(name)
	if f then f:Destroy() end
	f = Instance.new("Model") f.Name = name f.Parent = parent
	return f
end
function K.part(parent, name, size, cf, color, mat, opts)
	opts = opts or {}
	local p = Instance.new(opts.wedge and "WedgePart" or "Part")
	p.Name = name p.Size = size p.Anchored = true
	p.CFrame = opts.world and cf or (K.O * cf)
	p.Color = color or K.C.SL p.Material = mat or K.M.SmoothPlastic
	if opts.var then p.MaterialVariant = opts.var end
	p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.decor then p.CanCollide = false p.CanTouch = false p.CanQuery = false end
	if opts.neon then p.Material = K.M.Neon p.CastShadow = false end
	if opts.noshadow then p.CastShadow = false end
	if opts.tr then p.Transparency = opts.tr end
	if opts.shape then p.Shape = opts.shape end
	p.Parent = parent
	return p
end
function K.box(parent, name, x0, x1, y0, y1, z0, z1, color, mat, opts)
	return K.part(parent, name, Vector3.new(math.abs(x1 - x0), y1 - y0, math.abs(z1 - z0)),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat, opts)
end
function K.fbox(parent, F, name, x0, x1, y0, y1, z0, z1, color, mat, opts)
	return K.part(parent, name, Vector3.new(math.abs(x1 - x0), y1 - y0, math.abs(z1 - z0)),
		F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat, opts)
end
function K.stairs(parent, name, F, width, rise, steps, run, color, nose)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local h = rise / steps
	for i = 1, steps do
		local top = h * i
		K.part(m, "Step", Vector3.new(width, top, run), F * CFrame.new(0, top / 2, -(i - 0.5) * run), color or K.C.SL, K.M.Concrete, { var = "VS_WhitePrecast" })
		if nose then K.part(m, "Nose", Vector3.new(width, 0.12, 0.35), F * CFrame.new(0, top + 0.06, -(i - 1) * run - 0.18), nose, K.M.SmoothPlastic, { decor = true }) end
	end
	return m
end
function K.gui(part, face, pps, bright)
	local g = Instance.new("SurfaceGui") g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud g.PixelsPerStud = pps or 30
	g.LightInfluence = 0 g.Brightness = bright or 1.3 g.Parent = part
	return g
end
function K.text(parent, txt, pos, size, color, font, align)
	local t = Instance.new("TextLabel") t.BackgroundTransparency = 1 t.Text = txt
	t.FontFace = font or K.FONT t.TextColor3 = color or K.C.WH t.TextScaled = true
	t.Position = pos t.Size = size t.TextXAlignment = align or Enum.TextXAlignment.Center t.Parent = parent
	return t
end
function K.frame(parent, color, pos, size, tr, rot)
	local f = Instance.new("Frame") f.BorderSizePixel = 0 f.BackgroundColor3 = color
	f.Position = pos f.Size = size f.BackgroundTransparency = tr or 0 f.Rotation = rot or 0 f.Parent = parent
	return f
end
local U = UDim2.fromScale
function K.icon(parent, kind, pos, size, color)
	color = color or K.C.WH
	local box = K.frame(parent, color, pos, size, 1)
	local function r(x, y, w, h, rot) return K.frame(box, color, U(x, y), U(w, h), 0, rot) end
	if kind == "rifle" then
		r(0.05, 0.42, 0.62, 0.16) r(0.62, 0.45, 0.33, 0.08) r(0.0, 0.40, 0.14, 0.32, -12) r(0.30, 0.55, 0.08, 0.3, 12)
		r(0.43, 0.56, 0.06, 0.24) r(0.25, 0.32, 0.18, 0.1)
	elseif kind == "cart" then
		r(0.18, 0.28, 0.7, 0.36) r(0.02, 0.2, 0.2, 0.08) r(0.24, 0.72, 0.14, 0.14) r(0.66, 0.72, 0.14, 0.14)
	elseif kind == "trophy" then
		r(0.25, 0.1, 0.5, 0.42) r(0.43, 0.5, 0.14, 0.22) r(0.28, 0.72, 0.44, 0.12) r(0.1, 0.14, 0.16, 0.22) r(0.74, 0.14, 0.16, 0.22)
	elseif kind == "gift" then
		r(0.12, 0.38, 0.76, 0.52) r(0.08, 0.26, 0.84, 0.14) r(0.46, 0.26, 0.08, 0.64) r(0.3, 0.1, 0.18, 0.16, 25) r(0.52, 0.1, 0.18, 0.16, -25)
	elseif kind == "swords" then
		r(0.46, 0.05, 0.08, 0.8, 40) r(0.46, 0.05, 0.08, 0.8, -40) r(0.25, 0.62, 0.5, 0.06, 40) r(0.25, 0.62, 0.5, 0.06, -40)
	elseif kind == "skull" then
		r(0.2, 0.08, 0.6, 0.5) r(0.3, 0.55, 0.4, 0.22)
		local e1 = r(0.3, 0.28, 0.14, 0.14) e1.BackgroundColor3 = K.C.CH local e2 = r(0.56, 0.28, 0.14, 0.14) e2.BackgroundColor3 = K.C.CH
	elseif kind == "flag" then
		r(0.28, 0.06, 0.06, 0.88) r(0.34, 0.08, 0.46, 0.3)
	elseif kind == "vlogo" then
		r(0.18, 0.08, 0.2, 0.84, -24) r(0.58, 0.08, 0.2, 0.84, 24)
		local o = r(0.62, 0.06, 0.32, 0.16, 0) o.BackgroundColor3 = K.C.OR
	end
	return box
end
function K.sign(parent, name, F, w, h, label, opts)
	opts = opts or {}
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local board = K.part(m, "Board", Vector3.new(w, h, 0.6), F, opts.bg or K.C.CH, K.M.SmoothPlastic)
	if opts.border ~= false then
		K.part(m, "Edge", Vector3.new(w + 0.6, h + 0.6, 0.3), F * CFrame.new(0, 0, 0.3), opts.border or K.C.SL, K.M.SmoothPlastic, { decor = true })
	end
	if opts.strip then K.part(m, "Strip", Vector3.new(w, 0.5, 0.7), F * CFrame.new(0, -h / 2 - 0.1, -0.05), opts.strip, nil, { neon = opts.neonStrip, decor = true }) end
	local g = K.gui(board, Enum.NormalId.Front, opts.pps or 24, opts.bright or 1.35)
	local ic = opts.icon
	if ic and opts.iconTop then
		K.icon(g, ic, U(0.36, 0.06), U(0.28, 0.46), opts.iconColor)
		K.text(g, label, U(0.05, 0.56), U(0.9, 0.36), opts.color, K.FONT)
	elseif ic then
		K.icon(g, ic, U(0.05, 0.14), U(h / w * 0.9, 0.72), opts.iconColor)
		K.text(g, label, U(0.07 + h / w * 0.9, 0.16), U(0.88 - h / w * 0.9, 0.68), opts.color, K.FONT, Enum.TextXAlignment.Left)
	else
		K.text(g, label, U(0.05, 0.12), U(0.9, 0.76), opts.color, K.FONT)
	end
	return m, board, g
end
function K.tree(parent, name, F, s)
	s = s or 1
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	K.part(m, "Trunk", Vector3.new(1.8, 7, 1.8) * s, F * CFrame.new(0, 3.5 * s, 0), K.C.TR, K.M.Wood)
	K.part(m, "Canopy", Vector3.new(10, 6, 10) * s, F * CFrame.new(0, 9.5 * s, 0), K.C.GR, K.M.Grass, { decor = true })
	K.part(m, "Canopy2", Vector3.new(7, 4.5, 7) * s, F * CFrame.new(0.8 * s, 14.2 * s, -0.6 * s), K.C.GR3, K.M.Grass, { decor = true })
	K.part(m, "Canopy3", Vector3.new(5, 3, 5) * s, F * CFrame.new(-3.2 * s, 8.2 * s, 2.6 * s), K.C.GR2, K.M.Grass, { decor = true })
	return m
end
function K.bush(parent, F, w, h, d)
	K.part(parent, "Bush", Vector3.new(w, h, d), F * CFrame.new(0, h / 2, 0), K.C.GR2, K.M.Grass, { decor = true })
	K.part(parent, "BushTop", Vector3.new(w * 0.7, h * 0.5, d * 0.7), F * CFrame.new(w * 0.08, h + h * 0.2, -d * 0.05), K.C.GR, K.M.Grass, { decor = true })
end
function K.planter(parent, name, F, w, d, h, bushes)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	K.part(m, "Rim", Vector3.new(w, h, d), F * CFrame.new(0, h / 2, 0), K.C.LG2, K.M.Concrete, { var = "VS_WhitePrecast" })
	K.part(m, "Soil", Vector3.new(w - 1, 0.2, d - 1), F * CFrame.new(0, h + 0.05, 0), K.C.GRASS, K.M.Grass, { decor = true })
	for i = 1, (bushes or 0) do
		local t = (i - 0.5) / bushes - 0.5
		K.bush(m, F * CFrame.new(t * (w - 3), h + 0.1, ((i % 2) - 0.5) * 0.6), 2.6 + (i % 3) * 0.5, 2.0 + (i % 2) * 0.6, 2.6)
	end
	return m
end
function K.bollard(parent, F)
	local m = Instance.new("Model") m.Name = "Bollard" m.Parent = parent
	K.part(m, "Post", Vector3.new(1, 2.2, 1), F * CFrame.new(0, 1.1, 0), K.C.CH, K.M.Metal, { var = "VS_Gunmetal" })
	local l = K.part(m, "Lens", Vector3.new(0.8, 0.5, 0.8), F * CFrame.new(0, 2.0, 0), K.C.WARM, nil, { neon = true, decor = true })
	return m, l
end
function K.lamp(parent, F, h, lit)
	h = h or 9
	local m = Instance.new("Model") m.Name = "LampPost" m.Parent = parent
	K.part(m, "Base", Vector3.new(1.8, 1, 1.8), F * CFrame.new(0, 0.5, 0), K.C.CH, K.M.Metal, { var = "VS_Gunmetal" })
	K.part(m, "Pole", Vector3.new(0.9, h, 0.9), F * CFrame.new(0, h / 2, 0), K.C.CH, K.M.Metal, { var = "VS_Gunmetal" })
	K.part(m, "Cage", Vector3.new(2, 2.6, 2), F * CFrame.new(0, h + 1.3, 0), K.C.CH, K.M.Metal, { decor = true })
	local lens = K.part(m, "Lantern", Vector3.new(1.6, 2.0, 1.6), F * CFrame.new(0, h + 1.3, 0), K.C.WARM, nil, { neon = true, decor = true })
	K.part(m, "Cap", Vector3.new(2.4, 0.4, 2.4), F * CFrame.new(0, h + 2.8, 0), K.C.CH, K.M.Metal, { decor = true })
	if lit then local pl = Instance.new("PointLight") pl.Color = K.C.WARM pl.Range = 16 pl.Brightness = 0.9 pl.Shadows = false pl.Parent = lens end
	return m
end
function K.railing(parent, a, b, h, panel)
	local m = Instance.new("Model") m.Name = "Railing" m.Parent = parent
	local d = b - a local len = d.Magnitude
	local cf = CFrame.lookAt(a + d / 2, a + d / 2 + d.Unit)
	local posts = math.max(2, math.floor(len / 6) + 1)
	for i = 0, posts - 1 do
		local t = (i / (posts - 1) - 0.5) * len
		K.part(m, "Post", Vector3.new(0.6, h, 0.6), cf * CFrame.new(0, h / 2, t), K.C.CH, K.M.Metal)
	end
	K.part(m, "TopRail", Vector3.new(0.5, 0.4, len), cf * CFrame.new(0, h, 0), K.C.CH, K.M.Metal)
	K.part(m, "Panel", Vector3.new(0.25, h * 0.62, len - 0.6), cf * CFrame.new(0, h * 0.45, 0), panel or K.C.OR, K.M.SmoothPlastic)
	return m
end
function K.crate(parent, F, s, style)
	local m = Instance.new("Model") m.Name = style == "dark" and "EquipCrate" or "VCrate" m.Parent = parent
	local body = K.part(m, "Body", Vector3.new(s, s, s), F * CFrame.new(0, s / 2, 0), style == "dark" and K.C.CH or K.C.OR, K.M.SmoothPlastic)
	for _, y in ipairs({ 0.06, s - 0.06 }) do
		K.part(m, "Band", Vector3.new(s + 0.1, 0.25, s + 0.1), F * CFrame.new(0, y, 0), style == "dark" and K.C.OR or K.C.CH, nil, { decor = true })
	end
	if style ~= "dark" then local g = K.gui(body, Enum.NormalId.Front, 30, 1) K.icon(g, "vlogo", U(0.2, 0.2), U(0.6, 0.6), K.C.CH) end
	return m
end
function K.banner(parent, name, F, w, h)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	K.part(m, "Rod", Vector3.new(w + 1.2, 0.5, 0.5), F * CFrame.new(0, 0.3, 0.3), K.C.CH, K.M.Metal)
	K.part(m, "Border", Vector3.new(w, h, 0.25), F * CFrame.new(0, -h / 2, 0.15), K.C.OR, nil)
	local cloth = K.part(m, "Cloth", Vector3.new(w - 1.2, h - 0.6, 0.3), F * CFrame.new(0, -h / 2 + 0.3, 0), K.C.CH, K.M.Fabric)
	local tail = w * 0.45
	for _, sx in ipairs({ -1, 1 }) do
		local rot = CFrame.Angles(0, math.rad(-sx * 90), 0) * CFrame.Angles(0, 0, math.pi)
		K.part(m, "TailBorder", Vector3.new(0.25, tail, w / 2), F * CFrame.new(sx * w / 4, -h - tail / 2, 0.15) * rot, K.C.OR, nil, { wedge = true })
		K.part(m, "TailFill", Vector3.new(0.3, tail - 0.9, w / 2 - 0.6), F * CFrame.new(sx * (w / 4 - 0.3), -h + 0.6 - (tail - 0.9) / 2, 0) * rot, K.C.CH, K.M.Fabric, { wedge = true })
	end
	local g = K.gui(cloth, Enum.NormalId.Front, 20, 1.2)
	K.icon(g, "vlogo", U(0.18, 0.12), U(0.64, 0.64 * (w - 1.2) / (h - 0.6)), K.C.WH)
	return m
end
return K
