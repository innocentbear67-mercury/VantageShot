--[[
	ECLIPSE — Hero (Phase 5): set pieces, original mesh kit placement, lights and effects per area.
	Everything goes into <Area>/Hero (rebuilt on each run). Animated models carry the
	"EclipseAnim" tag and are driven by Map_Eclipse/Systems/AmbientClient (client only).
]]
local H = {}
local D = require(script.Parent.Dress)
local HF = require(script.Parent.Heightfield)
local KIT = script.Parent.MeshKit
local S = D.S
local dp, sp = D.dp, D.sp
local V, CF = Vector3.new, CFrame.new
local rad, cos, sin, abs = math.rad, math.cos, math.sin, math.abs
local C3 = Color3.fromRGB
local CS = game:GetService("CollectionService")
local MAP = workspace.Map_Eclipse

local function hero(areaName)
	local area = MAP[areaName]
	local f = area:FindFirstChild("Hero")
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = "Hero"
	f.Parent = area
	return f, area
end
local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
local function inst(kind, parent, props)
	local i = Instance.new(kind)
	for k, v in props or {} do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function mesh(name, parent, cf, size, solid, props)
	local m = KIT[name]:Clone()
	m.Size = size
	m.CFrame = cf
	m.Anchored = true
	m.CanCollide = solid == true
	m.CanQuery = solid == true
	m.CanTouch = solid == true
	m.CastShadow = size.Magnitude > 12
	for k, v in props or {} do
		m[k] = v
	end
	m.Parent = parent
	return m
end
local function stand(x, y, z, size, rotY)
	return CF(x, y + size.Y / 2, z) * CFrame.Angles(0, rad(rotY or 0), 0)
end
local function anim(m, attrs)
	for k, v in attrs do
		m:SetAttribute(k, v)
	end
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CS:AddTag(m, "EclipseAnim")
end
local function hide(part)
	part.Transparency = 1
	part.CastShadow = false
	part:SetAttribute("HiddenCollider", true)
end
local function sign(parent, cf, size, text, color, face)
	local p = dp(parent, "Sign", size, cf, S.SteelDk)
	local g = inst("SurfaceGui", p, { Face = face or Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 24, LightInfluence = 0.4, Brightness = 1.6 })
	inst("TextLabel", g, {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text, TextColor3 = color, TextScaled = true,
		FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	})
	return p
end
local function beam(a0, a1, color, w0, w1)
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.85) })
	b.Width0, b.Width1 = w0 or 0.6, w1 or 0.25
	b.LightEmission = 1
	b.FaceCamera = true
	b.Segments = 1
	b.Parent = a0.Parent
	return b
end
local function anchorPart(parent, name, pos)
	return dp(parent, name, V(1, 1, 1), CF(pos), S.Black, { Transparency = 1 })
end
local WATER = { C3(196, 226, 240), Enum.Material.ForceField }
local function mist(parent, cf, size, rate, props)
	local p = dp(parent, "Mist", size, cf, S.Black, { Transparency = 1 })
	local e = inst("ParticleEmitter", p, {
		Rate = rate, Lifetime = NumberRange.new(3, 6), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(60, 60),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(C3(225, 238, 248)), LightInfluence = 0.8, Texture = "rbxasset://textures/particles/smoke_main.dds",
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	for k, v in props or {} do
		e[k] = v
	end
	return p
end

function H.B()
	local f, area = hero("B_GrandChamber")
	local CZ, F, TOP = -425, -20, 150
	for _, p in area:GetChildren() do
		if p.Name == "Buttress" then
			p:Destroy()
		end
	end
	for _, p in area:GetDescendants() do
		if p.Name == "GatePylon" or p.Name == "GateLintel" then
			hide(p)
		end
	end
	local T = workspace.Terrain
	for _, reg in { Region3.new(V(-144, -60, -528), V(144, 160, -320)), Region3.new(V(-28, -24, -336), V(28, 48, -262)) } do
		reg = reg:ExpandToGrid(4)
		for _, m in { Enum.Material.Grass, Enum.Material.Ground, Enum.Material.Rock, Enum.Material.Snow, Enum.Material.Sand, Enum.Material.Mud, Enum.Material.Slate } do
			T:ReplaceMaterial(reg, 4, m, Enum.Material.Basalt)
		end
	end
	local wall = model(f, "WallColonnade")
	local function pil(x, z, rotY, lower)
		if lower then
			mesh("Kit_Pillar", wall, stand(x, F, z, V(10, 80, 5), rotY), V(10, 80, 5))
		end
		mesh("Kit_Pillar", wall, stand(x, F + 84, z, V(8, 64, 4), rotY), V(8, 64, 4))
	end
	for x = -120, 120, 24 do
		pil(x, -330.5, 180, abs(x) > 30)
		pil(x, -519.5, 0, true)
	end
	for z = -508, -344, 24 do
		local nearTunnel = abs(z + 425) < 28
		pil(-133.5, z, 90, not nearTunnel and not (z > -508 and z < -416))
		pil(133.5, z, -90, not nearTunnel and not (z > -408 and z < -342))
	end
	for _, b in {
		{ V(272, 3, 3), CF(0, F + 82.5, -329.5) }, { V(272, 3, 3), CF(0, F + 82.5, -520.5) },
		{ V(3, 3, 194), CF(-134.5, F + 82.5, CZ) }, { V(3, 3, 194), CF(134.5, F + 82.5, CZ) },
	} do
		dp(wall, "Gallery", b[1], b[2], S.AncientDk)
		local glow = b[1] - V(if b[1].X > 10 then 2 else 0, 2.6, if b[1].Z > 10 then 2 else 0)
		dp(wall, "GalleryGlow", glow + V(if b[1].X < 10 then 0.6 else 0, 0, if b[1].Z < 10 then 0.6 else 0), b[2] * CF(0, -1.8, 0), S.EnergyDim)
	end
	local ceil = model(f, "Ceiling")
	for z = -512, -338, 24 do
		dp(ceil, "CeilingRib", V(272, 6, 5), CF(0, TOP - 2, z), S.AncientDk)
	end
	for _, x in { -64, 64 } do
		dp(ceil, "CeilingSpine", V(5, 5, 194), CF(x, TOP - 3, CZ), S.Ancient)
	end
	for k = 0, 7 do
		local a = rad(k * 45 + 22.5)
		local p = V(cos(a) * 30, TOP - 6, CZ + sin(a) * 30)
		dp(ceil, "Oculus", V(25, 4, 4), CF(p) * CFrame.Angles(0, -a + rad(90), 0), S.AncientDk)
		dp(ceil, "OculusGlow", V(24, 0.4, 0.6), CF(p - V(0, 2.2, 0)) * CFrame.Angles(0, -a + rad(90), 0), S.Energy)
	end
	local core = model(f, "Reactor")
	for k = 0, 5 do
		local a = rad(k * 60)
		dp(core, "Rail", V(2, 196, 2), CF(cos(a) * 11, 52, CZ + sin(a) * 11), S.AncientDk)
	end
	local glow = anchorPart(core, "CoreLight", V(0, 30, CZ))
	inst("PointLight", glow, { Color = C3(90, 190, 255), Brightness = 3, Range = 60, Shadows = false })
	local glow2 = anchorPart(core, "CoreLight", V(0, -30, CZ))
	inst("PointLight", glow2, { Color = C3(90, 190, 255), Brightness = 2.5, Range = 45, Shadows = false })
	for i, r in { { 22, 80, 18, 0.35 }, { 29, 92, -24, -0.22 }, { 36, 104, 10, 0.16 } } do
		local ring = model(core, "GyroRing" .. i)
		local radius, y, tilt, speed = r[1], r[2], r[3], r[4]
		local n = 20
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2
			local chord = 2 * radius * sin(math.pi / n) + 0.4
			local seg = dp(ring, "Seg", V(chord, 1.6, 2.2), CF(cos(a) * radius, 0, sin(a) * radius) * CFrame.Angles(0, -a + rad(90), 0), S.AncientDk)
			if k % 4 == 0 then
				dp(ring, "SegGlow", V(chord * 0.6, 0.3, 2.3), seg.CFrame * CF(0, 0.9, 0), S.Energy)
			end
		end
		ring.WorldPivot = CF(0, 0, 0)
		ring:PivotTo(CF(0, y, CZ) * CFrame.Angles(rad(tilt), 0, rad(tilt * 0.5)))
		anim(ring, { Spin = speed, AnimRange = 450 })
	end
	local hub = anchorPart(core, "TetherHub", V(0, 96, CZ))
	local a0 = inst("Attachment", hub)
	for k = 0, 5 do
		local a = rad(k * 60 + 30)
		local fm = model(core, "Floater" .. k)
		local m = mesh("Kit_Floater", fm, CF(cos(a) * 50, 92 + (k % 2) * 14, CZ + sin(a) * 40) * CFrame.Angles(0, -a, rad(8)), V(8, 28, 8))
		local a1 = inst("Attachment", m)
		beam(a0, a1, C3(90, 200, 255), 0.5, 0.2)
		anim(fm, { Bob = 2.2, BobSpeed = 0.5 + k * 0.07, Phase = k * 1.1, AnimRange = 450 })
	end
	for i = -2, 2 do
		dp(core, "PitGrid", V(0.3, 0.1, 58), CF(i * 11, -45.95, CZ), S.EnergyDim)
		dp(core, "PitGrid", V(58, 0.1, 0.3), CF(0, -45.95, CZ + i * 11), S.EnergyDim)
	end
	for _, p in { { -38, -38 }, { 38, -38 }, { -38, 38 }, { 38, 38 } } do
		sp(core, "Pedestal", V(5, 4.5, 5), CF(p[1], F + 2.25, CZ + p[2]), S.Ancient)
		dp(core, "PedestalGlow", V(3.6, 0.3, 3.6), CF(p[1], F + 4.6, CZ + p[2]), S.Energy)
	end
	for k = 0, 7 do
		local a = rad(k * 45)
		local p = V(cos(a) * 62, F + 0.04, CZ + sin(a) * 52)
		dp(f, "FloorInlay", V(0.5, 0.08, 40), CFrame.lookAt(p, V(0, F + 0.04, CZ)) * CF(0, 0, 10), S.EnergyDim)
	end
	for k = 0, 7 do
		local a = rad(22.5 + k * 45)
		local px, pz = cos(a) * 96, CZ + sin(a) * 76
		local inward = (V(0, 0, CZ) - V(px, 0, pz)).Unit
		local lamp = dp(f, "PillarLamp", V(4, 6, 0.4), CFrame.lookAt(V(px, 40, pz) + inward * 8.3, V(px, 40, pz) + inward * 20), S.Lamp)
		inst("SpotLight", lamp, { Face = Enum.NormalId.Front, Angle = 70, Range = 40, Brightness = 1.6, Color = C3(170, 205, 255), Shadows = false })
	end
	local dust = dp(f, "Dust", V(240, 120, 170), CF(0, 50, CZ), S.Black, { Transparency = 1 })
	inst("ParticleEmitter", dust, {
		Rate = 28, Lifetime = NumberRange.new(12, 18), Speed = NumberRange.new(0.2, 0.8), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.22), LightEmission = 0.7, LightInfluence = 0.3, Color = ColorSequence.new(C3(180, 220, 255)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Texture = "rbxasset://textures/particles/sparkles_main.dds",
	})
	local gg = HF.H(0, -268)
	mesh("Kit_Arch", f, stand(0, gg - 2, -272, V(92, 78, 18), 0), V(92, 78, 18), true)
	for _, x in { -40, 40 } do
		mesh("Kit_Pillar", f, stand(x, gg - 2, -262, V(10, 46, 10), 0), V(10, 46, 10), true)
	end
end

function H.C()
	local f, area = hero("C_Installation")
	local Y = 30
	local props = game.ReplicatedStorage.Vantage.UI.HangarProps
	local function prop(name, cf, scale, solid)
		local m = props[name]:Clone()
		m:ScaleTo(scale)
		m:PivotTo(cf)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = solid == true
				d.CanQuery = solid == true
			end
		end
		m.Parent = f
		local b, s = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + V(0, Y - (b.Position.Y - s.Y / 2), 0))
		return m
	end
	local hg = area:FindFirstChild("Hangar")
	if hg then
		for _, p in hg:GetChildren() do
			if p.Name:find("^Dropship") then
				hide(p)
			end
		end
	end
	prop("Jet", CF(-395, Y, -4) * CFrame.Angles(0, rad(90), 0), 1.9, false)
	prop("Tug", CF(-366, Y, 14) * CFrame.Angles(0, rad(200), 0), 1.6, true)
	for i, c in { { -362, -30 }, { -420, 22 }, { -352, 30 }, { -430, -44 } } do
		prop("Crates", CF(c[1], Y, c[2]) * CFrame.Angles(0, rad(i * 37), 0), 1.3, true)
	end
	for _, z in { -36, -24, 24, 36 } do
		prop("Cone", CF(-338, Y, z), 1, false)
	end
	for _, side in { -1, 1 } do
		local zc = side * 44
		dp(f, "BayDoor", V(2, 30, 28), CF(-342.6, Y + 15, zc), S.Steel, { CanCollide = true, CanQuery = true })
		for k = 0, 5 do
			dp(f, "DoorRib", V(0.6, 28, 1.2), CF(-341.4, Y + 15, zc - 12 + k * 4.8), S.SteelDk)
		end
		dp(f, "DoorHazard", V(0.3, 30, 1.6), CF(-341.4, Y + 15, side * 30.8), S.Hazard)
	end
	dp(f, "DoorTrack", V(3, 3, 120), CF(-342.5, Y + 31.5, -5), S.SteelDk)
	dp(f, "BayThreshold", V(4, 0.12, 60), CF(-344, Y + 0.06, 0), S.Hazard)
	sign(f, CF(-342.2, Y + 36.5, 0), V(0.4, 6, 44), "HANGAR 02", C3(225, 235, 250), Enum.NormalId.Right)
	sign(f, CF(-364.8, Y + 12.4, 67), V(0.3, 2.2, 14), "ARMORY", C3(255, 196, 90), Enum.NormalId.Right)
	sign(f, CF(-354.8, Y + 12.4, -103), V(0.3, 2.2, 16), "RESEARCH · LAB 3", C3(150, 220, 255), Enum.NormalId.Right)
	sign(f, CF(-331, Y + 33.5, 47.2), V(18, 2.2, 0.3), "CONTROL", C3(150, 220, 255), Enum.NormalId.Back)
	for _, x in { -466.5, -453.5 } do
		dp(f, "SpawnDoorGlow", V(0.6, 12, 0.6), CF(x, Y + 6, -26.4), S.Blue)
	end
	dp(f, "SpawnDoorGlow", V(13.6, 0.6, 0.6), CF(-460, Y + 12.3, -26.4), S.Blue)
	sign(f, CF(-460, Y + 14, -27.2), V(12, 1.6, 0.3), "VANTAGE · BLUE COMMAND", C3(120, 170, 255), Enum.NormalId.Back)
	for z = -134, -66, 15 do
		if z < -110 or z > -88 then
			mesh("Kit_WallPanel", f, stand(-436.5, Y, z, V(13, 12, 4), 90), V(13, 12, 4), true)
		end
	end
	for _, z in { -120, -40, 60 } do
		prop("Floodlight", CF(-306, Y, z) * CFrame.Angles(0, rad(-90), 0), 2.6, true)
		local lp = anchorPart(f, "ApronLight", V(-306, Y + 16, z))
		inst("SpotLight", lp, { Face = Enum.NormalId.Left, Angle = 75, Range = 60, Brightness = 2.2, Color = C3(255, 236, 205), Shadows = true })
	end
	dp(f, "Mast", V(0.8, 22, 0.8), CF(-322, Y + 42.5, 76), S.SteelDk)
	dp(f, "Mast", V(0.5, 14, 0.5), CF(-338, Y + 38.5, 54), S.SteelDk)
	local bcn = dp(f, "Beacon", V(1.2, 1.2, 1.2), CF(-322, Y + 54, 76), S.Red)
	inst("PointLight", bcn, { Color = C3(255, 60, 50), Brightness = 2, Range = 14 })
	for i, y in { Y + 8, Y + 10.5 } do
		dp(f, "WallPipe", V(92, 1.4 - i * 0.2, 1.4 - i * 0.2), CF(-392, y, 47.4), if i == 1 then S.Rust else S.SteelDk, { Shape = Enum.PartType.Cylinder })
	end
end

function H.Sanctum()
	local f = hero("Sanctum")
	local Y = 41
	mesh("Kit_Arch", f, stand(290, Y - 2, -60, V(50, 50, 12), 90), V(50, 50, 12), false)
	for x = 380, 450, 23 do
		for _, z in { -127, -33 } do
			mesh("Kit_Pillar", f, stand(x, Y, z, V(7, 26, 7), 0), V(7, 26, 7), true)
		end
	end
	for _, z in { -91.5, -68.5 } do
		dp(f, "SpawnDoorGlow", V(0.6, 14, 0.6), CF(419.6, Y + 7, z), S.Red)
	end
	dp(f, "SpawnDoorGlow", V(0.6, 0.6, 23.6), CF(419.6, Y + 14.3, -80), S.Red)
	for i, r in { 10, 18 } do
		for _, e in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local size = if e[1] ~= 0 then V(0.5, 0.08, r * 2) else V(r * 2, 0.08, 0.5)
			dp(f, "CourtInlay", size, CF(395 + e[1] * r, Y + 0.04, -80 + e[2] * r), if i == 1 then S.Red else S.EnergyDim)
		end
	end
	local hub = anchorPart(f, "TetherHub", V(438, Y + 24, -80))
	local a0 = inst("Attachment", hub)
	for k, z in { -100, -60 } do
		local fm = model(f, "Floater" .. k)
		local m = mesh("Kit_Floater", fm, CF(438, Y + 46, z) * CFrame.Angles(0, rad(k * 40), 0), V(7, 22, 7))
		beam(a0, inst("Attachment", m), C3(255, 110, 90), 0.4, 0.15)
		anim(fm, { Bob = 1.6, BobSpeed = 0.6, Phase = k * 2, AnimRange = 400 })
	end
	local gy = HF.H(214, -60) + 0.5
	for k = 0, 6 do
		local t = (k + 0.5) / 7
		local x = 298 + (214 - 298) * t
		local y = Y + (gy - Y) * t
		for _, z in { -69.6, -50.4 } do
			sp(f, "Balustrade", V(10, 3, 1.2), CF(x, y + 1.5, z), S.AncientDk)
		end
		if k % 2 == 0 then
			local l = dp(f, "StairLamp", V(1, 1, 1), CF(x, y + 3.6, -69.6), S.Energy)
			inst("PointLight", l, { Color = C3(120, 200, 255), Brightness = 1, Range = 12 })
		end
	end
end

function H.D()
	local f = hero("D_GrandBridge")
	local Z, Y = 170, 40
	local cx = HF.CanyonCentre(Z)
	local x0, x1 = cx - 82, cx + 82
	for _, x in { x0 - 6, x1 + 6 } do
		mesh("Kit_Arch", f, stand(x, Y - 6, Z, V(44, 64, 10), 90), V(44, 64, 10), false)
		for _, dz in { -13, 13 } do
			local b = dp(f, "AviationLight", V(1.4, 1.4, 1.4), CF(x, Y + 73, Z + dz), S.Red)
			inst("PointLight", b, { Color = C3(255, 50, 40), Brightness = 1.5, Range = 10 })
		end
	end
	for _, side in { -1, 1 } do
		dp(f, "DeckEdgeGlow", V(x1 - x0 - 4, 0.25, 0.35), CF(cx, Y - 0.6, Z + side * 8.2), S.Energy)
		dp(f, "DeckUnderGlow", V(x1 - x0 - 24, 0.35, 0.35), CF(cx, Y - 10.2, Z + side * 1.8), S.EnergyDim)
	end
	for k = 0, 7 do
		local xa = x0 + 18 + k * ((x1 - x0 - 36) / 8)
		local xb = x0 + 18 + (k + 1) * ((x1 - x0 - 36) / 8)
		for _, z in { Z - 7.5, Z + 7.5 } do
			local a, b = V(xa, Y - 8, z), V(xb, Y - 3.2, z)
			dp(f, "Truss", V(0.8, 0.8, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), S.AncientDk)
		end
	end
	local wf = workspace.Map_Eclipse.D_GrandBridge:FindFirstChild("Waterfall")
	if wf then
		wf.Color = WATER[1]
		wf.Material = WATER[2]
		wf.MaterialVariant = ""
		wf.Transparency = 0.05
		wf.Reflectance = 0
	end
	local wx = HF.CanyonCentre(48)
	mist(f, CF(wx, -214, 50), V(30, 6, 14), 18)
	mist(f, CF(wx, -2, 50), V(24, 2, 6), 6, { Speed = NumberRange.new(1, 3) })
	for _, w in { { 300, -1 }, { 380, 1 } } do
		local z = w[1]
		local c, hw = HF.CanyonCentre(z), HF.CanyonHalfWidth(z)
		local x = c + w[2] * (hw - 6)
		local top = HF.H(x + w[2] * 14, z)
		local sheet = dp(f, "CanyonFall", V(12, top + 224, 2), CF(x, (top - 224) / 2, z), WATER, { Transparency = 0.05 })
		sheet.CFrame = sheet.CFrame * CFrame.Angles(0, rad(90), 0)
		mist(f, CF(x, -214, z), V(20, 6, 20), 10)
	end
end

function H.E()
	local f = hero("E_Undercroft")
	local F = -46
	for x = -104, 14, 14 do
		if abs(x + 30) > 9 then
			mesh("Kit_WallPanel", f, stand(x, F, -30, V(13, 12, 4), 0), V(13, 12, 4), true)
		end
	end
	for i, z in { -18, 0, 18 } do
		dp(f, "CeilingPipe", V(132, 2.4, 2.4), CF(-45, -22.6, z), if i == 2 then S.Rust else S.SteelDk, { Shape = Enum.PartType.Cylinder })
		for x = -105, 15, 20 do
			dp(f, "PipeHanger", V(0.4, 2.6, 3), CF(x, -21.4, z), S.Black)
		end
	end
	for _, g in workspace.Map_Eclipse.E_Undercroft:GetChildren() do
		if g.Name == "Generator" then
			local top = g.Position + V(0, g.Size.Y / 2, 0)
			local core = dp(f, "GenCore", V(1.2, 4, 4), CF(top + V(0, 0.6, 0)) * CFrame.Angles(0, 0, rad(90)), S.Amber, { Shape = Enum.PartType.Cylinder })
			inst("PointLight", core, { Color = C3(255, 150, 60), Brightness = 1.8, Range = 20, Shadows = false })
		end
	end
	for _, p in { V(-92, -30, 26.6), V(-68, -30, 26.6) } do
		local l = dp(f, "Warning", V(1, 1, 0.4), CF(p), S.Red)
		inst("PointLight", l, { Color = C3(255, 50, 40), Brightness = 1.2, Range = 16 })
	end
	local fm = model(f, "Heart")
	mesh("Kit_Floater", fm, CF(-10, -30, 30), V(6, 18, 6))
	anim(fm, { Bob = 1, BobSpeed = 0.8, AnimRange = 250 })
	local l = anchorPart(f, "HeartLight", V(-10, -30, 30))
	inst("PointLight", l, { Color = C3(80, 180, 255), Brightness = 2, Range = 30, Shadows = false })
end

local ROUTES = {
	{ V(-345, 0, 0), V(-282, 0, -24), V(-200, 0, -40), V(-100, 0, -60), V(0, 0, -90), V(110, 0, -150), V(214, 0, -60) },
	{ V(-282, 0, -24), V(-250, 0, 118), V(-175, 0, 78), V(-90, 0, 170) },
	{ V(214, 0, -60), V(222, 0, 38), V(165, 0, 74), V(90, 0, 170) },
	{ V(-200, 0, -40), V(-150, 0, -180), V(0, 0, -268) },
	{ V(214, 0, -60), V(150, 0, -190), V(0, 0, -268) },
}
local function routeDist(x, z)
	local best = math.huge
	for _, r in ROUTES do
		for i = 1, #r - 1 do
			local a, b = r[i], r[i + 1]
			local dx, dz = b.X - a.X, b.Z - a.Z
			local t = math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / (dx * dx + dz * dz), 0, 1)
			best = math.min(best, math.sqrt((x - a.X - dx * t) ^ 2 + (z - a.Z - dz * t) ^ 2))
		end
	end
	return best
end
function H.A()
	local f, area = hero("A_OuterValley")
	local T = workspace.Terrain
	for _, b in area:GetChildren() do
		if b.Name == "Boulder" then
			local r = math.max(b.Size.X, b.Size.Z) * 0.55
			T:FillBall(b.Position, r, Enum.Material.Rock)
			T:FillBall(b.Position + V(r * 0.6, -r * 0.2, r * 0.3), r * 0.65, Enum.Material.Slate)
			b:Destroy()
		end
	end
	for _, a in { { -138, -100, 35, 0 }, { 24, -236, 30, 0 }, { 188, -30, 70, 1 } } do
		local g = HF.H(a[1], a[2])
		local size = V(30, 34, 7)
		local cf = stand(a[1], g - 3, a[2], size, a[3])
		if a[4] == 1 then
			cf = cf * CFrame.Angles(0, 0, rad(9)) - V(0, 3, 0)
		end
		mesh("Kit_Arch", f, cf, size, true)
	end
	local nx, nz = 110, -150
	local ng = HF.H(nx, nz)
	local hub = anchorPart(f, "NeedleHub", V(nx + 6, ng + 78, nz + 6))
	local a0 = inst("Attachment", hub)
	for k = 0, 3 do
		local a = rad(k * 90 + 20)
		local fm = model(f, "NeedleShard" .. k)
		local m = mesh("Kit_Floater", fm, CF(nx + 6 + cos(a) * 16, ng + 76 + k * 3, nz + 6 + sin(a) * 16) * CFrame.Angles(rad(12), -a, 0), V(4, 13, 4))
		beam(a0, inst("Attachment", m), C3(90, 200, 255), 0.3, 0.12)
		anim(fm, { Bob = 1.4, BobSpeed = 0.7, Phase = k, AnimRange = 600 })
	end
	local sx, top = -150, 96
	local sz = -330
	while sz < -240 and HF.H(sx, sz) > top do
		sz += 2
	end
	dp(f, "Spillway", V(16, 6, 36), CF(sx, top, sz - 10), S.Ancient)
	dp(f, "SpillwayWall", V(2, 4, 36), CF(sx - 7, top + 5, sz - 10), S.AncientDk)
	dp(f, "SpillwayWall", V(2, 4, 36), CF(sx + 7, top + 5, sz - 10), S.AncientDk)
	dp(f, "SpillwayGlow", V(12, 0.3, 0.4), CF(sx, top - 3.2, sz + 8.2), S.EnergyDim)
	local fz = sz + 9
	local g = HF.H(sx, fz + 6)
	T:FillBlock(CF(sx, g - 1, fz + 6), V(26, 10, 26), Enum.Material.Air)
	T:FillBlock(CF(sx, g - 4, fz + 6), V(24, 4, 24), Enum.Material.Water)
	dp(f, "ValleyFall", V(11, top - g + 2, 1.6), CF(sx, (top + g) / 2 - 2, fz), WATER, { Transparency = 0.05 })
	mist(f, CF(sx, g - 1, fz + 5), V(18, 4, 14), 12)
	local rng = Random.new(41)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.Terrain, f }
	local placed = {}
	local trees = model(f, "Trees")
	local tries = 0
	while #placed < 90 and tries < 3000 do
		tries += 1
		local x, z = rng:NextNumber(-460, 460), rng:NextNumber(-280, 420)
		local h, tag = HF.H(x, z)
		local hx = HF.H(x + 6, z)
		local hz = HF.H(x, z + 6)
		local slope = math.max(abs(hx - h), abs(hz - h)) / 6
		local ok = (tag == "valley" or tag == "plateau" or tag == "westshelf") and slope < 0.45 and h > 1 and routeDist(x, z) > 18
		if ok then
			for _, p in placed do
				if (p - V(x, 0, z)).Magnitude < 16 then
					ok = false
					break
				end
			end
		end
		if ok and #workspace:GetPartBoundsInBox(CF(x, h + 15, z), V(22, 30, 22), params) > 0 then
			ok = false
		end
		if ok then
			table.insert(placed, V(x, 0, z))
			local s = rng:NextNumber(1.1, 1.7)
			local size = KIT.Kit_Tree.Size * s
			local t = mesh("Kit_Tree", trees, stand(x, h - 0.6, z, size, rng:NextNumber(0, 360)), size, false)
			t.CastShadow = true
			sp(trees, "Trunk", V(1.6 * s, size.Y * 0.55, 1.6 * s), CF(x, h + size.Y * 0.27, z), S.Black, { Transparency = 1, CastShadow = false })
		end
		if tries % 200 == 0 then
			task.wait()
		end
	end
	return #placed
end

function H.Skyline()
	local old = MAP:FindFirstChild("Skyline")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "Skyline"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m.Parent = MAP
	local rng = Random.new(9)
	local function far(name, cf, size)
		local p = mesh(name, m, cf, size, false)
		p.CastShadow = false
		p.CanTouch = false
		return p
	end
	for k = 0, 27 do
		local a = k / 28 * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local r = rng:NextNumber(1350, 1900)
		local size = V(rng:NextNumber(500, 900), rng:NextNumber(380, 720), rng:NextNumber(450, 800))
		local mtn = far("Kit_Boulders", CF(cos(a) * r, -220 + size.Y / 2, -150 + sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), size)
		mtn.TextureID = ""
		mtn.Material = Enum.Material.Rock
		mtn.MaterialVariant = "Eclipse_LayeredRock2"
		mtn.Color = C3(92, 98, 110)
	end
	far("Kit_Arch", CF(0, -150 + 380, 2300), V(820, 760, 140))
	far("Kit_Pillar", CF(-1500, -150 + 450, 600), V(90, 900, 90))
	far("Kit_Pillar", CF(1550, -150 + 380, -500), V(80, 760, 80))
	far("Kit_Pillar", CF(1250, -150 + 300, 1500), V(70, 600, 70))
	for k = 0, 4 do
		far("Kit_Floater", CF(-1500 + (k - 2) * 70, 900 + k * 40, 600 + (k % 2) * 60) * CFrame.Angles(0, k, rad(10)), V(40, 140, 40))
	end
end

function H.AmbientClient()
	local sys = MAP.Systems
	local s = sys:FindFirstChild("AmbientClient") or Instance.new("Script")
	s.Name = "AmbientClient"
	s.RunContext = Enum.RunContext.Client
	s.Source = [[
-- ECLIPSE ambient motion (client only, ~30 Hz, skipped when far from the camera)
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local items = {}
local function add(m)
	if m:IsA("Model") then
		items[m] = m:GetPivot()
	end
end
for _, m in CS:GetTagged("EclipseAnim") do
	add(m)
end
CS:GetInstanceAddedSignal("EclipseAnim"):Connect(add)
CS:GetInstanceRemovedSignal("EclipseAnim"):Connect(function(m)
	items[m] = nil
end)
local acc = 0
RS.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < 1 / 30 then
		return
	end
	acc = 0
	local t = os.clock()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	for m, base in items do
		if not m.Parent then
			items[m] = nil
			continue
		end
		if (base.Position - cp).Magnitude > (m:GetAttribute("AnimRange") or 500) then
			continue
		end
		local cf = base
		local spin = m:GetAttribute("Spin")
		if spin then
			cf = cf * CFrame.Angles(0, t * spin, 0)
		end
		local bob = m:GetAttribute("Bob")
		if bob then
			cf = cf + Vector3.new(0, math.sin(t * (m:GetAttribute("BobSpeed") or 1) + (m:GetAttribute("Phase") or 0)) * bob, 0)
		end
		m:PivotTo(cf)
	end
end)
]]
	s.Parent = sys
end

return H
