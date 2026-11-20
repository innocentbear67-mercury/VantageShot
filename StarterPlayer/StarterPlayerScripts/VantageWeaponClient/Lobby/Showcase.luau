--[[
	VANTAGE — Showcase (client): the 3D stage behind the Loadout and Operators screens.
	A far-off scene the camera locks onto while one of those screens is open.
	  backdrop  self-lit SurfaceGui plate: dark-blue gradient, drifting light blobs, diagonal bands,
	            dot field, a skin-tinted atmosphere, slow rings, vignette; layers parallax with the mouse
	  floor     glass podium with a neon rim, an orbiting light, a scrolling grid, a light shaft
	  lights    key / fill / rim PointLights and a SpotLight that sweeps across the subject
	  subject   a weapon (floats, turns, mirrored reflection) or an operator rig (idle, sways)
	  fx        per-skin themes built from ParticleEmitters, Beams and moving neon parts, scaled by tier
	API  Showcase.new{ Origin, Fov }  :Open()  :Close()  :SetFocus(fx, fy)
	     :SetSubject(model, { Kind = "weapon"|"rig" })  :SetTheme(fx, tint, rarity, tier)  :Burst()  :Spin(d)
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Showcase = {}
Showcase.__index = Showcase

local C = Color3.fromRGB
local V2, V3 = Vector2.new, Vector3.new
local S, O = UDim2.fromScale, UDim2.fromOffset
local NS, CS, NK, CK = NumberSequence.new, ColorSequence.new, NumberSequenceKeypoint.new, ColorSequenceKeypoint.new
local NR = NumberRange.new

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local EMBER = "rbxasset://textures/particles/fire_sparks_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local GLOW = "rbxassetid://85510492667572"
local DOTS = "rbxassetid://128661353023629"

local H = 4 -- subject height above the stage origin
local DIST = 9.2 -- camera distance (weapon); rigs use 10.5

local function new(cls, props, parent)
	local i = Instance.new(cls)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local function part(props, parent)
	props.Anchored = true
	props.CanCollide, props.CanQuery, props.CanTouch = false, false, false
	props.CastShadow = props.CastShadow or false
	return new("Part", props, parent)
end
local function corner(o, r)
	new("UICorner", { CornerRadius = r or UDim.new(0.5, 0) }, o)
end

function Showcase.new(opts)
	local self = setmetatable({}, Showcase)
	opts = opts or {}
	self.Origin = opts.Origin or V3(0, 9600, 0)
	self.Fov = opts.Fov or 42
	self.Focus = V2(0.44, 0.45)
	self.Look = V2(0, 0)
	self.UserYaw = 0
	self.Tint = C(255, 176, 46)
	self.Rarity = C(255, 196, 80)
	self.Tier = 2
	self.Fx = "metal"
	self.Kind = "weapon"
	self.SwapT = 1
	self.Arcs = {}
	return self
end

-- ─── backdrop ────────────────────────────────────────────────────────────────────────────
function Showcase:_buildBackdrop(folder)
	local plate = part({ Name = "Backdrop", Transparency = 1, Size = V3(40, 22, 0.05) }, folder)
	local sg = new("SurfaceGui", { Face = Enum.NormalId.Back, LightInfluence = 0, Brightness = 1, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 48, ClipsDescendants = true }, plate)
	local base = new("Frame", { Name = "Base", Size = S(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, sg)
	new("UIGradient", { Rotation = 70, Color = CS({ CK(0, C(14, 26, 92)), CK(0.4, C(10, 18, 64)), CK(0.72, C(8, 11, 44)), CK(1, C(18, 10, 54)) }) }, base)
	local L = {}
	local function glow(name, color, tr, pos, size, z)
		return new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = GLOW, ImageColor3 = color, ImageTransparency = tr, AnchorPoint = V2(0.5, 0.5), Position = pos, Size = size, ZIndex = z or 2 }, sg)
	end
	L.Blob1 = glow("Blob1", C(22, 200, 255), 0.72, S(0.08, 0.02), S(0.62, 0.9))
	L.Blob2 = glow("Blob2", C(139, 92, 255), 0.62, S(0.92, 1.02), S(0.7, 1))
	L.Blob3 = glow("Blob3", C(255, 63, 210), 0.86, S(0.45, 0.82), S(0.5, 0.5))
	L.Atmo = glow("Atmo", self.Tint, 0.3, S(0.44, 0.46), S(0.62, 0.95), 3)
	L.Core = glow("Core", Color3.new(1, 1, 1), 0.78, S(0.44, 0.46), S(0.3, 0.42), 3)
	-- diagonal bands (unrotated holder so the whole set can parallax)
	local bands = new("Frame", { Name = "Bands", BackgroundTransparency = 1, Size = S(1.2, 1.2), Position = S(-0.1, -0.1), ZIndex = 2 }, sg)
	for i = 0, 9 do
		new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(i * 0.13 - 0.05, 0.5), Size = S(0.07, 2.2), Rotation = 28, BackgroundColor3 = C(124, 160, 255), BackgroundTransparency = 0.955, BorderSizePixel = 0, ZIndex = 2 }, bands)
	end
	L.Bands = bands
	local dots = new("ImageLabel", { Name = "Dots", BackgroundTransparency = 1, Image = DOTS, ScaleType = Enum.ScaleType.Tile, TileSize = O(22, 22), ImageColor3 = C(124, 243, 255), ImageTransparency = 0.82, Size = S(1.1, 1.1), Position = S(-0.05, -0.05), ZIndex = 2 }, sg)
	new("UIGradient", { Rotation = 160, Transparency = NS({ NK(0, 0), NK(0.4, 1), NK(0.65, 1), NK(1, 0) }) }, dots)
	L.Dots = dots
	-- slow rings around the subject
	local function ring(name, size, tr, speed)
		local r = new("Frame", { Name = name, AnchorPoint = V2(0.5, 0.5), Position = S(0.44, 0.46), Size = O(size, size), BackgroundTransparency = 1, ZIndex = 3 }, sg)
		corner(r)
		local st = new("UIStroke", { Thickness = 2, Color = C(124, 243, 255), Transparency = tr }, r)
		new("UIGradient", { Transparency = NS({ NK(0, 0), NK(0.25, 0.85), NK(0.5, 0.4), NK(0.75, 0.9), NK(1, 0) }) }, st)
		return { Frame = r, Speed = speed }
	end
	L.Rings = { ring("Ring1", 620, 0.84, 4.5), ring("Ring2", 500, 0.78, -15) }
	-- periodic light sweep across the whole backdrop
	local sweep = new("Frame", { Name = "Sweep", AnchorPoint = V2(0.5, 0.5), Position = S(-0.3, 0.5), Size = S(0.16, 2), Rotation = 18, BackgroundColor3 = C(124, 243, 255), BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 4 }, sg)
	new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.2), NK(1, 1) }) }, sweep)
	L.Sweep = sweep
	-- vignette
	for _, v in { { S(0, 0), S(1, 0.3), 90, true }, { S(0, 0.7), S(1, 0.3), -90, true }, { S(0, 0), S(0.22, 1), 0, false }, { S(0.78, 0), S(0.22, 1), 180, false } } do
		local f = new("Frame", { Position = v[1], Size = v[2], BackgroundColor3 = C(5, 6, 20), BorderSizePixel = 0, ZIndex = 5 }, sg)
		new("UIGradient", { Rotation = v[3], Transparency = NS(0.35, 1) }, f)
	end
	self.Plate, self.Layers = plate, L
end

-- ─── floor, podium, lights ─────────────────────────────────────────────────────────────────
function Showcase:_buildFloor(folder)
	local b = self.Base
	local podTop = H - 1.6
	self.PodTop = podTop
	-- podium = a flat glowing ring decal (matches the approved board), not a solid disc
	local disc = part({ Name = "Podium", Size = V3(4, 0.02, 4), Transparency = 1 }, folder)
	disc.CFrame = b * CFrame.new(0, podTop + 0.1, 0)
	local pg = new("SurfaceGui", { Face = Enum.NormalId.Top, LightInfluence = 0, Brightness = 1.4, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 100, ClipsDescendants = false }, disc)
	local haze = new("ImageLabel", { Name = "Haze", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = self.Rarity, ImageTransparency = 0.7, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1) }, pg)
	local function podRing(name, size, th, color, tr)
		local f = new("Frame", { Name = name, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = size }, pg)
		corner(f)
		return new("UIStroke", { Thickness = th, Color = color, Transparency = tr }, f)
	end
	local glowRing = podRing("RimGlow", UDim2.new(1, -12, 1, -12), 14, self.Rarity, 0.84)
	local rim = podRing("Rim", UDim2.new(1, -12, 1, -12), 3, self.Rarity, 0.3)
	local wink = podRing("Wink", UDim2.new(1, -12, 1, -12), 3, Color3.new(1, 1, 1), 0)
	self.PodWink = new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.02, 0.05), NK(0.1, 1), NK(1, 1) }) }, wink)
	local inner = podRing("Inner", S(0.64, 0.64), 2.5, Color3.new(1, 1, 1), 0.7)
	self.PodHaze, self.PodGlow = haze, glowRing
	local orb = part({ Name = "Orbit", Shape = Enum.PartType.Ball, Size = V3(0.14, 0.14, 0.14), Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1) }, folder)
	new("PointLight", { Brightness = 2, Range = 5, Color = self.Rarity }, orb)
	-- light shaft from above
	local a0 = new("Attachment", { WorldPosition = (b * CFrame.new(0, H + 9, -1)).Position }, Workspace.Terrain)
	local a1 = new("Attachment", { WorldPosition = (b * CFrame.new(0, podTop, 0)).Position }, Workspace.Terrain)
	local shaft = new("Beam", { Attachment0 = a0, Attachment1 = a1, Width0 = 1.2, Width1 = 4.4, FaceCamera = true, LightEmission = 1, LightInfluence = 0, Color = CS(self.Rarity), Transparency = NS({ NK(0, 1), NK(0.6, 0.95), NK(1, 0.9) }), Segments = 1 }, folder)
	self.TerrainAtt = { a0, a1 }
	-- floor grid that scrolls toward the camera
	local floor = part({ Name = "Floor", Size = V3(60, 0.05, 36), Transparency = 1 }, folder)
	floor.CFrame = b * CFrame.new(0, podTop - 0.45, -6)
	local fg = new("SurfaceGui", { Face = Enum.NormalId.Top, LightInfluence = 0, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 16, ClipsDescendants = true }, floor)
	local grid = new("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 64) }, fg)
	for i = 0, 40 do
		new("Frame", { Position = UDim2.new(0, 0, 0, i * 32), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C(124, 243, 255), BackgroundTransparency = 0.9, BorderSizePixel = 0 }, grid)
	end
	for i = 0, 60 do
		new("Frame", { Position = UDim2.new(0, i * 32, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C(124, 243, 255), BackgroundTransparency = 0.9, BorderSizePixel = 0 }, grid)
	end
	-- no opaque fade (it read as a dark floor slab); far lines simply dissolve
	for _, ln in grid:GetChildren() do
		if ln.Size.Y.Scale == 1 then
			new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 1), NK(0.55, 0.985), NK(1, 0.94) }) }, ln)
		else
			ln.BackgroundTransparency = 1 - 0.06 * math.clamp(ln.Position.Y.Offset / 576, 0, 1) ^ 1.5
		end
	end
	-- lights
	local function light(name, pos, cls, props)
		local p = part({ Name = name, Size = V3(0.2, 0.2, 0.2), Transparency = 1 }, folder)
		p.CFrame = CFrame.lookAt((b * CFrame.new(pos)).Position, (b * CFrame.new(0, H, 0)).Position)
		new(cls, props, p)
		return p
	end
	light("Key", V3(-4, H + 4, 6), "PointLight", { Brightness = 2.4, Range = 16, Color = Color3.new(1, 1, 1) })
	self.Fill = light("Fill", V3(5, H + 1, 5), "PointLight", { Brightness = 1.4, Range = 14, Color = self.Tint }):FindFirstChildOfClass("PointLight")
	self.Rim = light("RimLight", V3(0, H + 3, -4), "PointLight", { Brightness = 3, Range = 12, Color = self.Tint }):FindFirstChildOfClass("PointLight")
	self.Under = light("Under", V3(0, podTop + 0.4, 0.5), "PointLight", { Brightness = 0, Range = 9, Color = C(255, 110, 30) }):FindFirstChildOfClass("PointLight")
	self.SweepPart = light("Sweep", V3(-5, H + 0.6, 3.4), "SpotLight", { Brightness = 9, Range = 9, Angle = 32, Face = Enum.NormalId.Front, Color = Color3.new(1, 1, 1) })
	self.Disc, self.RimRing, self.Inner, self.Orb, self.Shaft, self.Grid = disc, rim, inner, orb, shaft, grid
end

-- ─── open / close ─────────────────────────────────────────────────────────────────────────
function Showcase:Open()
	if self.Folder then
		return
	end
	self.Base = CFrame.new(self.Origin)
	local folder = new("Folder", { Name = "VantageShowcase" })
	self.Folder = folder
	self:_buildBackdrop(folder)
	self:_buildFloor(folder)
	self.FxFolder = new("Folder", { Name = "FX" }, folder)
	folder.Parent = Workspace
	local cam = Workspace.CurrentCamera
	self.SavedCamera = { Type = cam.CameraType, Subject = cam.CameraSubject, CFrame = cam.CFrame, Fov = cam.FieldOfView }
	local saved = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Env = Lighting.EnvironmentDiffuseScale, Spec = Lighting.EnvironmentSpecularScale, Effects = {} }
	self.SavedLighting = saved
	Lighting.Ambient, Lighting.OutdoorAmbient = C(96, 102, 130), C(110, 116, 140)
	Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = 0.5, 1
	for _, e in Lighting:GetChildren() do
		if e:IsA("DepthOfFieldEffect") or e:IsA("SunRaysEffect") then
			table.insert(saved.Effects, { e, "Enabled", e.Enabled })
			e.Enabled = false
		elseif e:IsA("BloomEffect") then
			table.insert(saved.Effects, { e, "Intensity", e.Intensity })
			table.insert(saved.Effects, { e, "Threshold", e.Threshold })
			table.insert(saved.Effects, { e, "Size", e.Size })
			e.Intensity, e.Threshold, e.Size = 0.9, 1.2, 28
		end
	end
	self.T0 = os.clock()
	self.Conn = RunService.RenderStepped:Connect(function(dt)
		self:_step(dt)
	end)
	self:_step(0)
	self:SetTheme(self.Fx, self.Tint, self.Rarity, self.Tier)
end

function Showcase:Close()
	if not self.Folder then
		return
	end
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	for _, a in self.TerrainAtt or {} do
		a:Destroy()
	end
	for _, a in self.Arcs do
		for _, x in a.Atts do
			x:Destroy()
		end
	end
	self.Arcs = {}
	self.Folder:Destroy()
	self.Folder, self.Subject, self.Reflection, self.Plate = nil, nil, nil, nil
	local s = self.SavedLighting
	if s then
		Lighting.Ambient, Lighting.OutdoorAmbient = s.Ambient, s.OutdoorAmbient
		Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = s.Env, s.Spec
		for _, e in s.Effects do
			if e[1].Parent then
				(e[1] :: any)[e[2]] = e[3]
			end
		end
		self.SavedLighting = nil
	end
	local cam = Workspace.CurrentCamera
	local c = self.SavedCamera
	if c then
		cam.CameraType = c.Type
		cam.CameraSubject = c.Subject
		cam.FieldOfView = c.Fov
		if c.Type == Enum.CameraType.Scriptable then
			cam.CFrame = c.CFrame
		end
		self.SavedCamera = nil
	end
end

function Showcase:SetFocus(fx, fy)
	self.Focus = V2(fx, fy)
end

function Showcase:Spin(d)
	self.UserYaw = math.clamp(self.UserYaw + d, -math.rad(70), math.rad(70))
end

-- ─── subject ──────────────────────────────────────────────────────────────────────────────
local function strip(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		elseif d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		end
	end
end

function Showcase:SetSubject(model, opts)
	opts = opts or {}
	if self.Subject then
		self.Subject:Destroy()
	end
	if self.Reflection then
		self.Reflection:Destroy()
		self.Reflection = nil
	end
	self.Subject, self.Kind = model, opts.Kind or "weapon"
	if not model then
		return
	end
	if self.Kind == "weapon" then
		strip(model)
		-- the caller hands over a model already turned side-on (muzzle +X); normalise its length
		local cf, size = model:GetBoundingBox()
		local long = math.max(size.X, size.Z)
		if long > 0 then
			pcall(function()
				model:ScaleTo(model:GetScale() * math.clamp((opts.Length or 4.8) / long, 0.4, 4))
			end)
		end
		cf = model:GetBoundingBox()
		self.Offset = CFrame.new(cf.Position):Inverse() * model:GetPivot()
		local refl = model:Clone()
		for _, d in refl:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 1 - (1 - d.Transparency) * 0.22
				d.CastShadow = false
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1 - (1 - d.Transparency) * 0.22
			elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") or d:IsA("Highlight") then
				d:Destroy()
			end
		end
		-- a mirrored copy spilled past the small podium; the glass disc's own reflectance reads better
		refl:Destroy()
	else
		self.Offset = nil
	end
	local hl = new("Highlight", { Name = "ShowcaseGlow", DepthMode = Enum.HighlightDepthMode.Occluded, FillColor = Color3.new(1, 1, 1), FillTransparency = 1, OutlineColor = self.Tint:Lerp(Color3.new(1, 1, 1), 0.25), OutlineTransparency = if self.Kind == "weapon" then 0.1 else 0.5 }, model)
	self.Glow = hl
	model.Parent = self.Folder
	self.SwapT = 0
	self.UserYaw = 0
	hl.FillTransparency = 0.15
	TweenService:Create(hl, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { FillTransparency = 1 }):Play()
end

-- ─── fx themes ───────────────────────────────────────────────────────────────────────────
local function emitter(parent, p)
	local e = new("ParticleEmitter", {
		Texture = p.Texture or GLOW, Rate = p.Rate or 5, Lifetime = p.Life or NR(2, 4), Speed = p.Speed or NR(0.1, 0.3),
		SpreadAngle = p.Spread or V2(180, 180), Size = p.Size or NS(0.08), Transparency = p.Trans or NS({ NK(0, 1), NK(0.2, 0.2), NK(0.8, 0.3), NK(1, 1) }),
		Color = p.Color or CS(Color3.new(1, 1, 1)), LightEmission = p.Light or 1, LightInfluence = 0, Acceleration = p.Accel or V3(0, 0, 0),
		Drag = p.Drag or 0, Rotation = p.Rot or NR(0, 360), RotSpeed = p.RotSpeed or NR(0, 0), Squash = p.Squash or NS(0),
		EmissionDirection = p.Dir or Enum.NormalId.Top, Shape = p.Shape or Enum.ParticleEmitterShape.Box,
		ShapeInOut = p.InOut or Enum.ParticleEmitterShapeInOut.Outward, ShapeStyle = p.Style or Enum.ParticleEmitterShapeStyle.Volume,
		ZOffset = p.Z or 0.5, LockedToPart = p.Locked or false, Brightness = p.Bright or 1.2,
	}, parent)
	return e
end

function Showcase:_box(name, size, offset)
	local b = part({ Name = name, Size = size, Transparency = 1 }, self.FxFolder)
	b.CFrame = self.Base * CFrame.new(offset or V3(0, H, 0))
	return b
end

local function seq(a, b)
	return CS(a, b or a)
end

function Showcase:SetTheme(fx, tint, rarity, tier)
	self.Fx, self.Tint, self.Rarity, self.Tier = fx or "metal", tint or self.Tint, rarity or self.Rarity, tier or 0
	if not self.Folder then
		return
	end
	local tint, rar = self.Tint, self.Rarity
	local m = ({ 0.7, 1, 1.6, 2.4, 3.4 })[math.clamp(self.Tier, 0, 4) + 1]
	self.FxFolder:ClearAllChildren()
	for _, a in self.Arcs do
		for _, x in a.Atts do
			x:Destroy()
		end
	end
	self.Arcs, self.ScanPart, self.Spark = {}, nil, nil
	local tw = TweenInfo.new(0.8, Enum.EasingStyle.Quad)
	TweenService:Create(self.Layers.Atmo, tw, { ImageColor3 = tint }):Play()
	TweenService:Create(self.RimRing, tw, { Color = rar }):Play()
	TweenService:Create(self.PodGlow, tw, { Color = rar }):Play()
	TweenService:Create(self.PodHaze, tw, { ImageColor3 = rar }):Play()
	TweenService:Create(self.Fill, tw, { Color = tint }):Play()
	TweenService:Create(self.Rim, tw, { Color = tint }):Play()
	self.Shaft.Color = seq(rar)
	self.Orb:FindFirstChildOfClass("PointLight").Color = rar
	if self.Glow then
		self.Glow.OutlineColor = tint:Lerp(Color3.new(1, 1, 1), 0.25)
	end
	local spot = self.SweepPart:FindFirstChildOfClass("SpotLight")
	spot.Color = if fx == "gold" or fx == "dragon" or fx == "holy" then C(255, 226, 160) elseif fx == "frost" then C(200, 240, 255) else Color3.new(1, 1, 1)
	self.Under.Brightness = if fx == "fire" or fx == "dragon" then 2.2 elseif fx == "ember" then 1.2 else 0
	self.Under.Color = if fx == "dragon" then C(255, 170, 50) else C(255, 100, 30)
	local white = Color3.new(1, 1, 1)
	local around = self:_box("Around", V3(7, 3, 2.4))
	local below = self:_box("Below", V3(5, 0.4, 1.6), V3(0, H - 1.2, 0))
	local above = self:_box("Above", V3(8, 0.4, 2.6), V3(0, H + 2.8, 0))
	local wide = self:_box("Wide", V3(16, 8, 3), V3(0, H + 0.6, -2.5))
	local function motes(col, n)
		emitter(around, { Rate = (n or 6) * m, Life = NR(3, 5), Size = NS({ NK(0, 0.04), NK(0.5, 0.09), NK(1, 0.02) }), Color = seq(col or tint), Speed = NR(0.05, 0.25) })
	end
	local function glints(col)
		emitter(around, { Texture = SPARK, Rate = 1.2 * m, Life = NR(0.45, 0.8), Speed = NR(0, 0), Size = NS({ NK(0, 0), NK(0.4, 0.55), NK(1, 0) }), Trans = NS(0), Color = seq(col or white), Bright = 2 })
	end
	local function embers(col1, col2, rate)
		emitter(below, { Texture = EMBER, Rate = (rate or 10) * m, Life = NR(1.4, 2.6), Speed = NR(0.5, 1.4), Spread = V2(25, 25), Accel = V3(0, 1.4, 0), Size = NS({ NK(0, 0.16), NK(1, 0.02) }), Color = CS(col1, col2), Bright = 2.5 })
	end
	if fx == "metal" then
		motes(tint, 4)
		glints()
	elseif fx == "gold" then
		motes(C(255, 210, 110), 7)
		glints(C(255, 236, 170))
		emitter(below, { Rate = 3 * m, Life = NR(2, 3), Speed = NR(0.3, 0.6), Accel = V3(0, 0.6, 0), Size = NS({ NK(0, 0.08), NK(1, 0.02) }), Color = seq(C(255, 200, 90)) })
	elseif fx == "fire" or fx == "ember" then
		embers(C(255, 220, 140), C(255, 70, 10), if fx == "fire" then 12 else 7)
		emitter(below, { Texture = SMOKE, Rate = 2 * m, Life = NR(2, 3), Speed = NR(0.4, 0.8), Accel = V3(0, 0.8, 0), Size = NS({ NK(0, 1.2), NK(1, 3) }), Trans = NS({ NK(0, 1), NK(0.3, 0.9), NK(1, 1) }), Color = seq(C(255, 120, 40)), Light = 0.4 })
		motes(C(255, 150, 60), 3)
	elseif fx == "dragon" then
		embers(C(255, 236, 160), C(255, 140, 20), 12)
		embers(C(255, 200, 120), C(255, 60, 10), 6)
		glints(C(255, 230, 150))
		emitter(below, { Texture = SMOKE, Rate = 1.5 * m, Life = NR(2, 3), Speed = NR(0.4, 0.8), Accel = V3(0, 0.8, 0), Size = NS({ NK(0, 1.2), NK(1, 3) }), Trans = NS({ NK(0, 1), NK(0.3, 0.9), NK(1, 1) }), Color = seq(C(255, 170, 60)), Light = 0.4 })
	elseif fx == "cosmic" or fx == "void" then
		emitter(wide, { Texture = SPARK, Rate = 9 * m, Life = NR(2, 4), Speed = NR(0, 0.08), Size = NS({ NK(0, 0), NK(0.5, 0.22), NK(1, 0) }), Trans = NS(0), Color = CS(white, tint) })
		emitter(wide, { Texture = SMOKE, Rate = 1.2, Life = NR(6, 9), Speed = NR(0.05, 0.15), Size = NS({ NK(0, 4), NK(1, 7) }), Trans = NS({ NK(0, 1), NK(0.4, 0.86), NK(1, 1) }), Color = CS(tint, C(139, 92, 255)), RotSpeed = NR(-12, 12), Z = -2 })
		if fx == "void" then
			local core = self:_box("Vortex", V3(3.2, 3.2, 3.2), V3(0, H, -1.2))
			core.Shape = Enum.PartType.Ball
			emitter(core, { Shape = Enum.ParticleEmitterShape.Sphere, Style = Enum.ParticleEmitterShapeStyle.Surface, InOut = Enum.ParticleEmitterShapeInOut.Inward, Rate = 26 * m, Life = NR(0.9, 1.3), Speed = NR(1.6, 2.4), Size = NS({ NK(0, 0.14), NK(1, 0.02) }), Color = CS(white, tint), Bright = 2 })
		end
	elseif fx == "frost" then
		emitter(above, { Rate = 9 * m, Life = NR(4, 6), Speed = NR(0.1, 0.3), Dir = Enum.NormalId.Bottom, Accel = V3(0.1, -0.35, 0), Size = NS({ NK(0, 0.1), NK(1, 0.06) }), Color = seq(C(230, 248, 255)) })
		emitter(below, { Texture = SMOKE, Rate = 1.5 * m, Life = NR(3, 5), Speed = NR(0.1, 0.3), Size = NS({ NK(0, 2), NK(1, 4) }), Trans = NS({ NK(0, 1), NK(0.4, 0.85), NK(1, 1) }), Color = seq(C(200, 240, 255)), Light = 0.5 })
		glints(C(220, 248, 255))
	elseif fx == "holy" then
		emitter(above, { Rate = 3 * m, Life = NR(5, 7), Speed = NR(0.1, 0.2), Dir = Enum.NormalId.Bottom, Accel = V3(0, -0.2, 0), Size = NS(0.16), Squash = NS(1.6), RotSpeed = NR(-40, 40), Color = seq(C(255, 246, 220)) })
		glints(C(255, 240, 200))
		motes(C(255, 230, 170), 5)
		for i = -1, 1 do
			local a0 = new("Attachment", { WorldPosition = (self.Base * CFrame.new(i * 2.2, H + 9, -2)).Position }, Workspace.Terrain)
			local a1 = new("Attachment", { WorldPosition = (self.Base * CFrame.new(i * 3.4, H - 2, 0)).Position }, Workspace.Terrain)
			local bm = new("Beam", { Attachment0 = a0, Attachment1 = a1, Width0 = 0.5, Width1 = 2.4, FaceCamera = true, LightEmission = 1, LightInfluence = 0, Color = seq(C(255, 240, 200)), Transparency = NS({ NK(0, 1), NK(0.5, 0.82), NK(1, 1) }) }, self.FxFolder)
			table.insert(self.Arcs, { Atts = { a0, a1 }, Beams = { bm }, Static = true })
		end
	elseif fx == "spirit" or fx == "petal" then
		emitter(above, { Rate = 6 * m, Life = NR(4, 6), Speed = NR(0.2, 0.4), Dir = Enum.NormalId.Bottom, Accel = V3(0.25, -0.3, 0), Size = NS(0.12), Squash = NS(-0.5), RotSpeed = NR(-160, 160), Color = CS(C(255, 214, 230), C(255, 111, 160)), Light = 0.6 })
		if fx == "spirit" then
			emitter(below, { Rate = 7 * m, Life = NR(1, 1.8), Speed = NR(0.6, 1.1), Spread = V2(15, 15), Accel = V3(0, 0.6, 0), Size = NS({ NK(0, 0.22), NK(1, 0.05) }), Squash = NS(1.3), Color = CS(C(232, 251, 255), C(60, 160, 255)), Bright = 2 })
		end
		motes(tint, 3)
	elseif fx == "water" then
		emitter(below, { Rate = 7 * m, Life = NR(2, 3.5), Speed = NR(0.3, 0.6), Spread = V2(20, 20), Accel = V3(0, 0.5, 0), Size = NS({ NK(0, 0.08), NK(1, 0.16) }), Trans = NS({ NK(0, 1), NK(0.2, 0.35), NK(0.9, 0.5), NK(1, 1) }), Color = seq(C(170, 240, 255)) })
		emitter(wide, { Texture = SMOKE, Rate = 1, Life = NR(5, 7), Speed = NR(0.05, 0.1), Size = NS({ NK(0, 4), NK(1, 6) }), Trans = NS({ NK(0, 1), NK(0.4, 0.88), NK(1, 1) }), Color = seq(tint), Z = -2 })
		motes(C(160, 230, 255), 3)
	elseif fx == "electric" or fx == "glitch" then
		self.Spark = emitter(around, { Texture = SPARK, Rate = 8 * m, Life = NR(0.15, 0.35), Speed = NR(1, 3), Size = NS({ NK(0, 0.25), NK(1, 0) }), Trans = NS(0), Color = CS(white, tint), Bright = 2.5 })
		motes(tint, 3)
		if fx == "electric" then
			for i = 1, 2 + self.Tier do
				local atts, beams = {}, {}
				for k = 1, 7 do
					atts[k] = new("Attachment", {}, Workspace.Terrain)
				end
				for k = 1, 6 do
					beams[k] = new("Beam", { Attachment0 = atts[k], Attachment1 = atts[k + 1], Width0 = 0.05, Width1 = 0.05, FaceCamera = true, LightEmission = 1, LightInfluence = 0, Color = CS(white, tint), Transparency = NS(0), Enabled = false, Segments = 1 }, self.FxFolder)
				end
				table.insert(self.Arcs, { Atts = atts, Beams = beams, Next = os.clock() + math.random() * 2, Off = 0 })
			end
		end
	elseif fx == "scan" then
		local plane = part({ Name = "Scan", Size = V3(6.4, 0.04, 2.2), Material = Enum.Material.Neon, Color = tint, Transparency = 0.45 }, self.FxFolder)
		self.ScanPart = plane
		motes(tint, 4)
		glints()
	elseif fx == "prism" then
		emitter(around, { Texture = SPARK, Rate = 6 * m, Life = NR(1, 1.8), Speed = NR(0.2, 0.6), Size = NS({ NK(0, 0), NK(0.4, 0.3), NK(1, 0) }), Trans = NS(0), Color = CS({ CK(0, C(255, 80, 160)), CK(0.25, C(255, 220, 90)), CK(0.5, C(90, 255, 180)), CK(0.75, C(80, 160, 255)), CK(1, C(180, 90, 255)) }), Bright = 2 })
		glints()
	elseif fx == "toxic" then
		emitter(below, { Rate = 8 * m, Life = NR(2, 3.5), Speed = NR(0.3, 0.7), Spread = V2(30, 30), Accel = V3(0, 0.6, 0), Size = NS({ NK(0, 0.1), NK(1, 0.04) }), Color = CS(C(234, 255, 216), C(90, 255, 58)) })
		motes(C(90, 255, 58), 3)
	end
	self.Burster = emitter(around, { Texture = SPARK, Rate = 0, Life = NR(0.5, 0.9), Speed = NR(3, 7), Size = NS({ NK(0, 0.35), NK(1, 0) }), Trans = NS(0), Color = CS(white, rar), Bright = 3, Drag = 3 })
end

function Showcase:Burst()
	if not self.Folder then
		return
	end
	local ring = part({ Name = "Burst", Shape = Enum.PartType.Cylinder, Size = V3(0.06, 1, 1), Material = Enum.Material.Neon, Color = self.Rarity, Transparency = 0 }, self.Folder)
	ring.CFrame = self.Base * CFrame.new(0, self.PodTop + 0.05, 0) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quart), { Size = V3(0.06, 16, 16), Transparency = 1 }):Play()
	task.delay(1, function()
		ring:Destroy()
	end)
	if self.Burster then
		self.Burster:Emit(36)
	end
	if self.Glow then
		self.Glow.FillTransparency = 0
		TweenService:Create(self.Glow, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { FillTransparency = 1 }):Play()
	end
end

function Showcase:Flash()
	if self.Glow then
		self.Glow.FillTransparency = 0.25
		TweenService:Create(self.Glow, TweenInfo.new(0.55, Enum.EasingStyle.Quad), { FillTransparency = 1 }):Play()
	end
end

-- ─── per frame ───────────────────────────────────────────────────────────────────────────
function Showcase:_camera()
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local aspect = vp.X / math.max(vp.Y, 1)
	local tanV = math.tan(math.rad(self.Fov / 2))
	local tanH = tanV * aspect
	local dist = if self.Kind == "rig" then 10.5 else DIST
	local lx, ly = self.Look.X, self.Look.Y
	local camPos = self.Base * V3(lx * 0.45, H + 0.3 - ly * 0.25, dist)
	local anchor = self.Base * V3(0, H, 0)
	local dl = V3((self.Focus.X * 2 - 1) * tanH, (1 - self.Focus.Y * 2) * tanV, -1).Unit
	local dw = (anchor - camPos).Unit
	local function yawOf(v)
		return math.atan2(-v.X, -v.Z)
	end
	local function pitchOf(v)
		return math.asin(math.clamp(v.Y, -1, 1))
	end
	local cf = CFrame.new(camPos) * CFrame.Angles(0, yawOf(dw) - yawOf(dl), 0) * CFrame.Angles(pitchOf(dw) - pitchOf(dl), 0, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = self.Fov
	cam.CFrame = cf
	-- backdrop covers the view 24 studs out
	local d = 24
	local fh, fw = 2 * d * tanV, 2 * d * tanH
	self.Plate.Size = V3(fw * 1.12, fh * 1.12, 0.05)
	self.Plate.CFrame = cf * CFrame.new(0, 0, -d)
	local sg = self.Plate:FindFirstChildOfClass("SurfaceGui")
	if sg then
		sg.PixelsPerStud = 1920 / (fw * 1.12)
	end
end

function Showcase:_step(dt)
	if not self.Folder then
		return
	end
	local t = os.clock() - (self.T0 or 0)
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local m = UserInputService:GetMouseLocation()
	local target = V2(math.clamp(m.X / math.max(vp.X, 1) * 2 - 1, -1, 1), math.clamp(m.Y / math.max(vp.Y, 1) * 2 - 1, -1, 1))
	self.Look = self.Look:Lerp(target, 1 - math.exp(-3 * dt))
	self:_camera()
	local L, lx, ly = self.Layers, self.Look.X, self.Look.Y
	-- backdrop motion: drifting blobs, parallax layers, rings, sweep
	L.Blob1.Position = S(0.08 + math.sin(t * 0.21) * 0.06 - lx * 0.02, 0.02 + math.cos(t * 0.17) * 0.05 - ly * 0.02)
	L.Blob2.Position = S(0.92 + math.cos(t * 0.15) * 0.06 + lx * 0.02, 1.02 + math.sin(t * 0.19) * 0.05 + ly * 0.02)
	L.Blob3.Position = S(0.45 + math.sin(t * 0.13) * 0.08, 0.82 + math.cos(t * 0.11) * 0.04)
	L.Atmo.ImageTransparency = 0.28 + math.sin(t * 0.9) * 0.06
	L.Atmo.Position = S(self.Focus.X + lx * 0.012, self.Focus.Y + ly * 0.01)
	L.Core.Position = L.Atmo.Position
	L.Bands.Position = S(-0.1 - lx * 0.008, -0.1 - ly * 0.006)
	L.Dots.Position = S(-0.05 - lx * 0.016, -0.05 - ly * 0.01)
	for _, r in L.Rings do
		r.Frame.Rotation += r.Speed * dt
		r.Frame.Position = S(self.Focus.X, self.Focus.Y)
	end
	local sp = (t % 14) / 14
	L.Sweep.Position = S(-0.3 + math.max(0, sp - 0.7) / 0.3 * 1.6, 0.5)
	self.Grid.Position = UDim2.new(0, 0, 0, -((t * 14) % 32))
	-- orbiting light on the podium rim
	local a = t * 1.1
	self.Orb.CFrame = self.Base * CFrame.new(math.cos(a) * 1.94, self.PodTop + 0.12, math.sin(a) * 1.94)
	self.Inner.Transparency = 0.7 + math.sin(t * 2) * 0.12
	self.PodWink.Rotation = (t * 70) % 360
	self.PodHaze.ImageTransparency = 0.7 + math.sin(t * 1.3) * 0.06
	-- sweep light glides across the subject, rests, glides back
	local ph = (t % 5) / 5
	local x = if ph < 0.55 then -5.5 + 11 * (ph / 0.55) else 5.5
	self.SweepPart.CFrame = CFrame.lookAt((self.Base * CFrame.new(x, H + 0.6, 3.4)).Position, (self.Base * CFrame.new(x * 0.4, H, 0)).Position)
	-- fire light flicker
	if self.Under.Brightness > 0 then
		local base = if self.Fx == "ember" then 1.2 else 2.2
		self.Under.Brightness = base + math.noise(t * 3, 0.5) * 1.2
	end
	-- subject
	if self.Subject and self.Subject.Parent then
		self.SwapT = math.min(1, self.SwapT + dt / 0.85)
		local e = 1 - (1 - self.SwapT) ^ 4
		if self.Kind == "weapon" and self.Offset then
			local bob = math.sin(t * 1.14) * 0.16
			local yaw = math.sin(t * 0.57) * math.rad(9) + lx * math.rad(10) + self.UserYaw - (1 - e) * math.rad(40)
			local pitch = math.sin(t * 0.8) * math.rad(2.5) - ly * math.rad(5)
			local roll = math.sin(t * 0.6) * math.rad(1)
			local center = self.Base * CFrame.new((1 - e) * 2.6, H + bob, 0) * CFrame.Angles(pitch, yaw, roll)
			self.Subject:PivotTo(center * self.Offset)
			if self.Reflection then
				local mirror = self.Base * CFrame.new((1 - e) * 2.6, 2 * self.PodTop - (H + bob) - 0.3, 0) * CFrame.Angles(-pitch, yaw, -roll)
				self.Reflection:PivotTo(mirror * CFrame.Angles(math.pi, 0, 0) * self.Offset)
			end
		elseif self.Kind == "rig" then
			local root = self.Subject.PrimaryPart
			if root then
				local yaw = math.rad(-18) + lx * math.rad(8) + self.UserYaw - (1 - e) * math.rad(30)
				self.Subject:PivotTo(self.Base * CFrame.new((1 - e) * 2, self.PodTop + 2.95, 0) * CFrame.Angles(0, math.pi + yaw, 0))
			end
		end
		if self.Fx == "glitch" and self.Glow then
			local j = math.floor(t * 7) % 9
			self.Glow.OutlineColor = if j == 0 then C(40, 230, 255) elseif j == 4 then C(255, 63, 210) else self.Tint
		end
	end
	-- scan plane
	if self.ScanPart then
		local p = (t % 2.6) / 2.6
		self.ScanPart.CFrame = self.Base * CFrame.new(0, H - 1.3 + 2.6 * p, 0)
		self.ScanPart.Transparency = 0.35 + math.abs(p - 0.5) * 0.9
	end
	-- electric arcs: re-shaped and flashed at random
	local now = os.clock()
	for _, arc in self.Arcs do
		if not arc.Static then
			if now >= arc.Next then
				arc.Next = now + 0.8 + math.random() * 2.2
				arc.Off = now + 0.12 + math.random() * 0.1
				local x0, y0 = -2.4 + math.random() * 3.6, H - 0.6 + math.random() * 1.4
				local len = 1.2 + math.random() * 1.8
				local ang = (math.random() - 0.5) * 0.9
				for k, att in arc.Atts do
					local u = (k - 1) / 6
					local jitter = if k == 1 or k == 7 then 0 else (math.random() - 0.5) * 0.45
					att.WorldPosition = (self.Base * CFrame.new(x0 + math.cos(ang) * len * u, y0 + math.sin(ang) * len * u + jitter, 0.9)).Position
				end
				for _, b in arc.Beams do
					b.Enabled = true
				end
			elseif arc.Off and now >= arc.Off then
				arc.Off = nil
				for _, b in arc.Beams do
					b.Enabled = false
				end
			end
		end
	end
end

return Showcase
