local K = {}
K.O = CFrame.new(0, 3000, 0)
local RGB = Color3.fromRGB
local V = Vector3.new
local Mat = Enum.Material
K.C = {
	WALL = RGB(96, 84, 132), WALL2 = RGB(78, 68, 114), TRIM = RGB(112, 100, 150), TRIM2 = RGB(66, 58, 98),
	DARK = RGB(42, 36, 66), DARK2 = RGB(30, 26, 50), FLOOR = RGB(214, 212, 236), FLOOR2 = RGB(188, 186, 220), PLAZA = RGB(226, 224, 244),
	AMB = RGB(255, 132, 52), AMB2 = RGB(255, 176, 92), PEACH = RGB(255, 186, 140), SAL = RGB(255, 128, 112), SKY = RGB(150, 205, 255),
	YEL = RGB(255, 206, 40), BLK = RGB(34, 30, 44), WH = RGB(248, 246, 255), RED = RGB(255, 60, 60),
	DM = RGB(255, 70, 86), FFA = RGB(255, 140, 40), CTF = RGB(70, 160, 255), BP = RGB(255, 210, 50), SK = RGB(255, 90, 190), EX = RGB(50, 225, 235), JOIN = RGB(90, 200, 255),
	LEAF1 = RGB(70, 150, 78), LEAF2 = RGB(96, 176, 88), LEAF3 = RGB(56, 126, 70), LEAF4 = RGB(124, 194, 100),
}
K.M = {
	WALL = { Mat.Concrete, "LobbyWallPanel" }, PANEL = { Mat.Concrete, "LobbyWallPanel" }, TRIM = { Mat.SmoothPlastic },
	FLOOR = { Mat.Concrete, "VS_SealedFloor" }, TREAD = { Mat.DiamondPlate, "VS_TreadPlate" }, RIB = { Mat.Metal, "Eclipse_RibbedWall" },
	PLAIN = { Mat.SmoothPlastic }, METAL = { Mat.Metal }, NEON = { Mat.Neon }, GLASS = { Mat.Glass }, GRASS = { Mat.Grass },
}
local FONT = Font.fromName("LuckiestGuy")
K.FONT = FONT
function K.folder(parent, name)
	local f = parent:FindFirstChild(name) if f then f:Destroy() end
	f = Instance.new("Model") f.Name = name f.Parent = parent
	return f
end
function K.p(parent, name, size, cf, color, mat, opts)
	opts = opts or {}
	mat = mat or K.M.PLAIN
	local p = Instance.new(opts.wedge and "WedgePart" or (opts.corner and "CornerWedgePart" or "Part"))
	p.Name = name p.Anchored = true p.Size = size
	p.CFrame = opts.world and cf or (K.O * cf)
	p.Color = color p.Material = mat[1]
	if mat[2] then p.MaterialVariant = mat[2] end
	p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
	if mat[1] == Mat.Neon then p.CastShadow = false end
	if opts.decor then p.CanCollide = false p.CanTouch = false p.CanQuery = false end
	if opts.noshadow then p.CastShadow = false end
	if opts.tr then p.Transparency = opts.tr end
	if opts.shape then p.Shape = opts.shape end
	p.Parent = parent
	return p
end
function K.b(parent, name, x0, x1, y0, y1, z0, z1, color, mat, opts)
	local ax, bx = math.min(x0, x1), math.max(x0, x1)
	local ay, by = math.min(y0, y1), math.max(y0, y1)
	local az, bz = math.min(z0, z1), math.max(z0, z1)
	return K.p(parent, name, V(bx - ax, by - ay, bz - az), CFrame.new((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), color, mat, opts)
end
function K.beam(parent, name, a, b, w, h, color, mat, opts)
	local d = b - a
	local up = math.abs(d.Unit.Y) > 0.95 and V(0, 0, 1) or V(0, 1, 0)
	return K.p(parent, name, V(w, h, d.Magnitude), CFrame.lookAt((a + b) / 2, b, up), color, mat, opts)
end
function K.cyl(parent, name, cf, r, h, color, mat, opts)
	local p = K.p(parent, name, V(h, r * 2, r * 2), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, mat, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end
function K.hex(parent, name, cf, r, h, color, mat, opts)
	local first
	for i = 0, 2 do
		local p = K.p(parent, name, V(r, h, r * math.sqrt(3)), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(i * 60), 0), color, mat, opts)
		first = first or p
	end
	return first
end
function K.oct(parent, name, F, r, t, depth, color, mat, opts, skip)
	local s = 2 * r * math.tan(math.rad(22.5))
	for i = 0, 7 do
		if not (skip and skip[i]) then
			local th = math.rad(i * 45)
			K.p(parent, name, V(t, s + t * 0.83, depth), F * CFrame.new(r * math.cos(th), r * math.sin(th), 0) * CFrame.Angles(0, 0, th), color, mat, opts)
		end
	end
end
function K.sign(parent, name, F, w, h, text, col, opts)
	opts = opts or {}
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local layers = opts.layers or 7
	local depth = opts.depth or math.max(h * 0.16, 0.5)
	local dark = opts.side or col:Lerp(Color3.new(0, 0, 0), 0.55)
	local pps = math.clamp(100 / h, 4, 60)
	for i = layers, 0, -1 do
		local p = K.p(m, i == 0 and "Face" or "Layer", V(w, h, 0.05), F * CFrame.new(0, 0, depth * i / layers), col, K.M.PLAIN, { decor = true, tr = 1 })
		local g = Instance.new("SurfaceGui") g.Face = Enum.NormalId.Front g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud g.PixelsPerStud = pps
		g.LightInfluence = 0 g.Brightness = i == 0 and 1.5 or 1 g.Parent = p
		local t = Instance.new("TextLabel") t.BackgroundTransparency = 1 t.Size = UDim2.fromScale(1, 1) t.Text = text t.FontFace = FONT t.TextScaled = true
		t.Rotation = opts.rot or 0
		local s = Instance.new("UIStroke") s.LineJoinMode = Enum.LineJoinMode.Round s.Parent = t
		if i == 0 then
			t.TextColor3 = Color3.new(1, 1, 1)
			local gr = Instance.new("UIGradient") gr.Rotation = 90
			gr.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, col:Lerp(Color3.new(1, 1, 1), 0.45)), ColorSequenceKeypoint.new(0.55, col), ColorSequenceKeypoint.new(1, col:Lerp(Color3.new(0, 0, 0), 0.15)) })
			gr.Parent = t
			s.Color = opts.stroke or RGB(24, 18, 40) s.Thickness = 3
		else
			local k = i / layers
			t.TextColor3 = dark:Lerp(Color3.new(0, 0, 0), k * 0.35)
			s.Color = (opts.stroke or RGB(24, 18, 40)) s.Thickness = 3
		end
		t.Parent = g
	end
	return m
end
function K.stairs(parent, name, F, width, rise, steps, run, color, mat, noseCol)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local h = rise / steps
	for i = 1, steps do
		local top = h * i
		K.p(m, "Step", V(width, top, run), F * CFrame.new(0, top / 2, -(i - 0.5) * run), color, mat or K.M.FLOOR)
		if noseCol then K.p(m, "Nose", V(width - 0.6, 0.1, 0.3), F * CFrame.new(0, top + 0.05, -(i - 1) * run - 0.2), noseCol, K.M.NEON, { decor = true }) end
	end
	return m
end
function K.rail(parent, a, b, h)
	h = h or 3.5
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	K.p(parent, "RailTop", V(0.7, 0.45, len + 0.4), cf * CFrame.new(0, h, 0), K.C.DARK, K.M.TRIM)
	K.p(parent, "RailGlass", V(0.24, h - 0.5, len), cf * CFrame.new(0, (h - 0.5) / 2 + 0.05, 0), RGB(200, 220, 255), K.M.GLASS, { tr = 0.55 })
	K.p(parent, "RailBase", V(0.6, 0.35, len), cf * CFrame.new(0, 0.175, 0), K.C.DARK, K.M.TRIM)
	local n = math.max(1, math.floor(len / 6))
	for i = 0, n do K.p(parent, "RailPost", V(0.45, h, 0.45), cf * CFrame.new(0, h / 2, -len / 2 + len * i / n), K.C.DARK, K.M.TRIM) end
end
function K.prompt(part, action, object, station)
	local pp = Instance.new("ProximityPrompt") pp.ActionText = action pp.ObjectText = object
	pp.MaxActivationDistance = 12 pp.RequiresLineOfSight = false pp.Parent = part
	part:SetAttribute("Station", station)
end
function K.queuePad(part, mode)
	part:SetAttribute("Mode", mode) game:GetService("CollectionService"):AddTag(part, "LobbyQueuePad")
end
function K.anim(inst, spin, bob, period, phase)
	game:GetService("CollectionService"):AddTag(inst, "HL_Anim")
	inst:SetAttribute("Spin", spin or 0) inst:SetAttribute("Bob", bob or 0) inst:SetAttribute("BobPeriod", period or 3) inst:SetAttribute("Phase", phase or 0)
end
function K.pulse(part, amp, period, phase)
	game:GetService("CollectionService"):AddTag(part, "HL_Pulse")
	part:SetAttribute("PulseAmp", amp or 0.5) part:SetAttribute("PulsePeriod", period or 2) part:SetAttribute("Phase", phase or 0)
end
function K.sparkles(parent, col, rate, speed, size, up, box)
	local e = Instance.new("ParticleEmitter") e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(col) e.LightEmission = 1 e.LightInfluence = 0 e.Rate = rate or 6
	e.Lifetime = NumberRange.new(1.4, 2.6) e.Speed = NumberRange.new(speed or 1.5, (speed or 1.5) * 1.8)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.4), NumberSequenceKeypoint.new(0.5, (size or 0.4) * 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Acceleration = V(0, up or 1.5, 0) e.SpreadAngle = Vector2.new(25, 25) e.Rotation = NumberRange.new(0, 360) e.RotSpeed = NumberRange.new(-90, 90)
	if box then e.Shape = Enum.ParticleEmitterShape.Box e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume end
	e.Parent = parent
	return e
end
function K.gradient(part, face, keys, bright, pps)
	local g = Instance.new("SurfaceGui") g.Face = face g.LightInfluence = 0 g.Brightness = bright or 1.8
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud g.PixelsPerStud = pps or 3 g.Parent = part
	local f = Instance.new("Frame") f.Size = UDim2.fromScale(1, 1) f.BorderSizePixel = 0 f.BackgroundColor3 = Color3.new(1, 1, 1) f.Parent = g
	local kp = {} for i, c in ipairs(keys) do table.insert(kp, ColorSequenceKeypoint.new((i - 1) / (#keys - 1), c)) end
	local gr = Instance.new("UIGradient") gr.Rotation = 90 gr.Color = ColorSequence.new(kp) gr.Parent = f
	return g, gr
end
function K.hazard(part, face, tile)
	local g = Instance.new("SurfaceGui") g.Face = face g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud g.PixelsPerStud = 8 g.LightInfluence = 1 g.Parent = part
	local sz = part.Size
	local w, h
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then w, h = sz.X, sz.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then w, h = sz.Z, sz.Y else w, h = sz.X, sz.Z end
	tile = tile or h
	local kps, n = {}, 8
	for i = 0, n - 1 do
		local col = (i % 2 == 0) and K.C.YEL or K.C.BLK
		table.insert(kps, ColorSequenceKeypoint.new(i / n, col))
		table.insert(kps, ColorSequenceKeypoint.new(math.min((i + 1) / n - 0.0005, 1), col))
	end
	kps[#kps] = ColorSequenceKeypoint.new(1, kps[#kps].Value)
	for i = 0, math.ceil(w / tile) - 1 do
		local f = Instance.new("Frame") f.BorderSizePixel = 0 f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.Position = UDim2.fromScale(i * tile / w, 0) f.Size = UDim2.new(tile / w, 1, 1, 0) f.Parent = g
		local gr = Instance.new("UIGradient") gr.Color = ColorSequence.new(kps) gr.Rotation = 45 gr.Parent = f
	end
end
function K.plant(parent, pos, s, rng, potted)
	local m = Instance.new("Model") m.Name = "Plant" m.Parent = parent
	local LEAF = { K.C.LEAF1, K.C.LEAF2, K.C.LEAF3, K.C.LEAF4 }
	local base = pos
	if potted then
		K.cyl(m, "Pot", CFrame.new(pos), 1.8 * s, 2.8 * s, K.C.TRIM, K.M.TRIM)
		K.cyl(m, "PotRim", CFrame.new(pos + V(0, 2.8 * s, 0)), 1.95 * s, 0.35 * s, K.C.DARK, K.M.TRIM)
		K.cyl(m, "PotBand", CFrame.new(pos + V(0, 0.6 * s, 0)), 1.86 * s, 0.25 * s, K.C.AMB, K.M.NEON, { decor = true })
		K.cyl(m, "Soil", CFrame.new(pos + V(0, 2.8 * s + 0.36 * s, 0)), 1.7 * s, 0.05, RGB(60, 44, 40), { Mat.Ground }, { decor = true })
		base = pos + V(0, 3.1 * s, 0)
	end
	local n = 14
	for i = 1, n do
		local yaw = i / n * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local col = LEAF[rng:NextInteger(1, 4)]
		local tilt = rng:NextNumber(0.35, 0.95)
		local L1, L2, W = rng:NextNumber(1.6, 2.4) * s, rng:NextNumber(1.8, 2.8) * s, rng:NextNumber(0.9, 1.25) * s
		local c1 = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, -tilt)
		K.p(m, "Leaf", V(0.12, L1, W), c1 * CFrame.new(0, L1 / 2, 0), col, K.M.PLAIN, { decor = true, noshadow = true })
		local c2 = c1 * CFrame.new(0, L1, 0) * CFrame.Angles(0, 0, -rng:NextNumber(0.6, 1.1))
		for _, sd in ipairs({ -1, 1 }) do
			K.p(m, "LeafTip", V(0.12, L2, W / 2), c2 * CFrame.new(0, L2 / 2, sd * W / 4) * CFrame.Angles(0, sd > 0 and math.pi or 0, 0), col, K.M.PLAIN, { decor = true, noshadow = true, wedge = true })
		end
	end
	return m
end
return K
