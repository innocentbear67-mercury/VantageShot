--[[
	VANTAGE — CrateOpening (client): the unboxing sequence (design canvas board "CrateOpen.dc.html", 2026-11-16).
	The server decides the drop (Remotes.CrateOpen) the moment Open is pressed; nothing here can change it,
	and nothing during the taps hints at the result.
	  1 Tap    a real 3D crate drops in. Each of 4 taps spins it one full turn (dip, lift, bounce)
	           with a flash, a dust puff, sparkles and a whoosh. The 4th tap bursts the lid off.
	  2 Reel   curved card reel of skins from every rarity, ticks pitched by rarity, rarity-coloured light,
	           near-miss tease, slower creep for Legendary+. Lands on the server's result.
	  3 Reveal the real 3D gun in the won skin: white paint-on, a full 360° turn, then float and sway
	           inside a rarity aura (glow, flames, light pillar, orbiting sparks). Godly shakes the screen.
	           Name, rarity, NEW! or duplicate refund; Equip now / Again / Done.
	Stage: a private 3D set far above the map (STAGE), a scriptable camera held at RenderPriority Camera+10,
	and a self-lit SurfaceGui backdrop showing the board's tinted burst art (CrateConfig.Images.Open).
	Audio: Roblox-licensed library SFX (Pro Sound Effects / APM).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local K = require(script.Parent:WaitForChild("ScreenKit"))
local UX = require(script.Parent:WaitForChild("CrateUX"))
local Remotes = Vantage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local C = Color3.fromRGB
local V2, V3 = Vector2.new, Vector3.new
local S, O = UDim2.fromScale, UDim2.fromOffset
local CS, CK, NS, NK = ColorSequence.new, ColorSequenceKeypoint.new, NumberSequence.new, NumberSequenceKeypoint.new
local INK = C(5, 6, 13)
local WHITE = Color3.new(1, 1, 1)
local RAINBOW = K.CHROMA or CS({ CK(0, C(255, 92, 92)), CK(0.5, C(90, 255, 160)), CK(1, C(255, 92, 200)) })

local STAGE = V3(1400, 9850, 0) -- far from the lobby Showcase (y 9600) and the map
local CAM_POS = STAGE + V3(0, 2.2, 23)
local CAM_LOOK = STAGE + V3(0, -0.5, 0)
local FOV = 40
local REEL_N, REEL_WIN = 64, 56
local CARD_W, CARD_GAP = 176, 14
local SPIN_MS = { Rare = 4600, Epic = 4800, Mythic = 5600, Legendary = 6800, Exclusive = 7400, Godly = 8200 }

-- { asset id, base volume }
local SFX = {
	Whoosh = { 9120718279, 0.7 },
	Whoosh2 = { 9126283592, 0.6 },
	Hit = { 9048764753, 0.8 },
	Riser = { 9045201066, 0.55 },
	Swell = { 9040281024, 0.6 },
	Tick = { 89658557478425, 0.42 },
	Lock = { 131042770615213, 0.8 },
	Shimmer = { 74567426909562, 0.55 },
	Open = { 136434924728183, 0.7 },
	Land = { 103406447926543, 0.8 },
	Break = { 98213885190101, 0.9 },
}

local CrateOpening = {}
CrateOpening.__index = CrateOpening

local function tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function chroma(r)
	local c = K.CHROMAS and K.CHROMAS[r]
	return (c and c.Grad) or RAINBOW
end

function CrateOpening.new(opts)
	local self = setmetatable({}, CrateOpening)
	self.Opts, self.G = opts, opts.G
	self.Active = false
	self.Gui, self.Canvas = K.screen("VantageCrateOpen", 30)
	self.Gui.Enabled = false
	self:_buildUi()
	return self
end

-- ─── sound ──────────────────────────────────────────────────────────────────────────────
function CrateOpening:_sfx(name, pitch, vol)
	local e = SFX[name]
	if not e then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. e[1]
	s.Volume = (vol or 1) * e[2]
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(12, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end

-- ─── UI ─────────────────────────────────────────────────────────────────────────────────
function CrateOpening:_buildUi()
	local G, cv, gui = self.G, self.Canvas, self.Gui
	self.Dim = G.new("Frame", { Name = "Dim", Size = S(1, 1), BackgroundColor3 = C(4, 5, 18), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
	self.Flash = G.new("Frame", { Name = "Flash", Size = S(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50 }, gui)
	local vig = G.new("Frame", { Name = "Vignette", Size = S(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, gui)
	for i, a in { { 0, V2(0, 0), 90 }, { 1, V2(0, 1), -90 } } do
		local f = G.new("Frame", { Name = "Bar" .. i, AnchorPoint = a[2], Position = S(0, a[1]), Size = S(1, 0.22), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, vig)
		G.new("UIGradient", { Rotation = a[3], Transparency = NS(0.15, 1) }, f)
	end
	-- tap prompt
	self.TapLayer = G.new("Frame", { Name = "Tap", BackgroundTransparency = 1, Size = S(1, 1), Visible = false, ZIndex = 10 }, cv)
	self.TapTitle = G.text(self.TapLayer, { Text = "TAP THE CRATE!", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = O(900, 90), TextSize = 78, Stroke = 6, ZIndex = 12 })
	self.TapSub = G.text(self.TapLayer, { Text = "", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 158), Size = O(900, 32), TextSize = 24, Stroke = 3, ZIndex = 12, Color = C(200, 253, 255) })
	local toks = G.new("Frame", { Name = "Tokens", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 190), Size = O(4 * 76 + 3 * 18, 90), ZIndex = 12 }, self.TapLayer)
	G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toks)
	self.Tokens = {}
	for i = 1, 4 do
		local t = G.new("Frame", { Name = "T" .. i, BackgroundColor3 = C(14, 18, 60), Size = O(76, 76), ZIndex = 12, LayoutOrder = i }, toks)
		G.corner(t, UDim.new(1, 0))
		G.stroke(t, 4, INK)
		local q = G.text(t, { Text = "?", TextSize = 40, Stroke = 4, ZIndex = 14, Color = C(124, 243, 255) })
		local ic = G.new("ImageLabel", { Name = "Req", BackgroundTransparency = 1, Image = G.A.Icon.Req, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.15, 1.15), ZIndex = 13 }, t)
		G.glow(t, { Color = C(124, 243, 255), Transparency = 0.7, Size = S(2, 2), ZIndex = 11 })
		self.Tokens[i] = { F = t, Q = q, Ic = ic }
	end
	self.TapBtn = G.new("TextButton", { Name = "Catcher", Text = "", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 40, Visible = false }, gui)
	self.TapBtn.Activated:Connect(function()
		self:_tap()
	end)
	-- burst ring
	self.Ring = G.new("Frame", { Name = "Ring", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.52), Size = O(10, 10), BackgroundTransparency = 1, ZIndex = 20 }, gui)
	G.corner(self.Ring, UDim.new(1, 0))
	self.RingSt = G.new("UIStroke", { Thickness = 18, Color = WHITE, Transparency = 1 }, self.Ring)
	-- reel
	self.ReelLayer = G.new("Frame", { Name = "Reel", BackgroundTransparency = 1, Size = S(1, 1), Visible = false, ZIndex = 10 }, gui)
	self.ReelLight = G.glow(self.ReelLayer, { Name = "Light", Color = C(149, 79, 255), Transparency = 0.45, Position = S(0.5, 0.5), Size = S(1.3, 1.1), ZIndex = 10 })
	self.ReelRig = G.new("Frame", { Name = "Rig", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), ZIndex = 11 }, self.ReelLayer)
	self.RigScale = G.new("UIScale", {}, self.ReelRig)
	local band = G.new("Frame", { Name = "Band", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, 0, 0, 330), BackgroundColor3 = C(6, 8, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 11 }, self.ReelRig)
	G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.12, 0.2), NK(0.88, 0.2), NK(1, 1) }) }, band)
	self.ReelBand = band
	self.ReelTag = G.text(self.ReelRig, { Text = "POSSIBLE DROPS", AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -172), Size = O(420, 34), TextSize = 24, Stroke = 3.5, Color = C(200, 253, 255), ZIndex = 31 })
	self.Strip = G.new("Frame", { Name = "Strip", BackgroundTransparency = 1, AnchorPoint = V2(0, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = O(REEL_N * (CARD_W + CARD_GAP), 280), ZIndex = 12 }, self.ReelRig)
	local lens = G.new("Frame", { Name = "Lens", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(CARD_W + 26, 300), BackgroundTransparency = 1, ZIndex = 30 }, self.ReelRig)
	G.corner(lens, 22)
	self.LensSt = G.new("UIStroke", { Thickness = 5, Color = WHITE }, lens)
	G.glow(lens, { Color = WHITE, Transparency = 0.6, Size = S(1.8, 1.4), ZIndex = 29 })
	self.Lens = lens
	for _, y in { 0, 1 } do
		local tri = G.new("Frame", { Name = "Pin", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, y), Size = O(26, 26), Rotation = 45, BackgroundColor3 = WHITE, ZIndex = 31 }, lens)
		G.stroke(tri, 3, INK)
	end
	-- reveal text + buttons
	self.Info = G.new("Frame", { Name = "Info", BackgroundTransparency = 1, Size = S(1, 1), Visible = false, ZIndex = 20 }, cv)
	self.RarityHolder = G.new("Frame", { Name = "Rarity", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = O(10, 52), ZIndex = 22 }, self.Info)
	self.NameLbl = G.text(self.Info, { Text = "", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 1, -330), Size = O(1400, 96), TextSize = 86, Stroke = 6, ZIndex = 22 })
	self.WpnLbl = G.text(self.Info, { Text = "", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 1, -236), Size = O(900, 34), TextSize = 28, Stroke = 3.5, ZIndex = 22, Color = C(200, 253, 255) })
	self.NewPill = G.new("Frame", { Name = "New", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 128), Size = O(0, 44), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, ZIndex = 22 }, self.Info)
	G.corner(self.NewPill, UDim.new(1, 0))
	G.stroke(self.NewPill, 4, INK)
	self.NewGrad = G.new("UIGradient", { Rotation = 90 }, self.NewPill)
	G.new("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) }, self.NewPill)
	self.NewLbl = G.text(self.NewPill, { Text = "", Size = O(0, 44), Auto = Enum.AutomaticSize.X, TextSize = 24, Stroke = 3.5, ZIndex = 23 })
	local row = G.new("Frame", { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -56), Size = O(980, 96), ZIndex = 22 }, self.Info)
	G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 24), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	self.Btns = {}
	-- reveal actions: cyan = equip, gold = buy again (primary), dark glass = done (secondary)
	local function btn(name, text, kind, order, onClick, sound)
		local art = if kind == "gold" then Config.Images.CtaGold elseif kind == "cyan" then Config.Images.CtaCyan else nil
		local w, h = if art then 300 else 220, 82
		local b
		if art then
			b = G.new("ImageButton", { Name = name, BackgroundTransparency = 1, Image = art, ScaleType = Enum.ScaleType.Stretch, AutoButtonColor = false, Size = O(w, h + 6), LayoutOrder = order, ZIndex = 23 }, row)
		else
			b = G.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = C(12, 16, 44), BackgroundTransparency = 0.12, Size = O(w, h - 6), LayoutOrder = order, ZIndex = 23 }, row)
			G.corner(b, 16)
			G.new("UIStroke", { Thickness = 2, Color = C(124, 243, 255), Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		local lab = G.text(b, { Text = text, Size = O(w, if art then h else h - 6), TextSize = if art then 30 else 26, Stroke = 4, ZIndex = 25, Rich = true })
		local ctl = UX.bind(b, if kind == "gold" then "primary" else "secondary", { OnClick = onClick, Art = if art then b else nil, Stroke = if art then nil else b:FindFirstChildOfClass("UIStroke"), Sound = sound, Cooldown = 0.4 })
		self.Btns[name] = { B = b, L = lab, Ctl = ctl }
		return b
	end
	btn("Equip", "Equip now", "cyan", 1, function() self:_equip() end, "Select")
	btn("Again", "Open again", "gold", 2, function() self:_again() end, "Purchase")
	btn("Done", "Done", "dark", 3, function() self:Close() end, "Click")
	self.Confetti = G.new("Frame", { Name = "Confetti", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 18 }, gui)
	self.Toast = K.toast(G, cv)
end

-- ─── 3D stage ───────────────────────────────────────────────────────────────────────────
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

function CrateOpening:_buildStage(crate)
	local G = self.G
	local f = Instance.new("Folder")
	f.Name = "VantageCrateStage"
	self.Stage = f
	local bd = part({ Name = "Backdrop", Size = V3(96, 55, 1), CFrame = CFrame.new(STAGE + V3(0, 0.6, -18)), Transparency = 1 }, f)
	local sg = Instance.new("SurfaceGui")
	sg.Face, sg.LightInfluence, sg.Brightness, sg.SizingMode = Enum.NormalId.Back, 0, 1.2, Enum.SurfaceGuiSizingMode.FixedSize -- Back faces +Z, toward the camera
	sg.CanvasSize = V2(1600, 920)
	sg.Parent = bd
	self.BgA = G.new("ImageLabel", { Name = "ArtA", BackgroundColor3 = INK, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.08, 1.08), ZIndex = 1 }, sg)
	self.BgB = G.new("ImageLabel", { Name = "ArtB", BackgroundTransparency = 1, ImageTransparency = 1, ScaleType = Enum.ScaleType.Crop, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.08, 1.08), ZIndex = 2 }, sg)
	self.BgShade = G.new("Frame", { Name = "Shade", BackgroundColor3 = C(4, 5, 18), BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 3 }, sg)
	self.BgRays = G.new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = Config.Images.Rays, ImageTransparency = 0.75, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.52), Size = O(1700, 1700), ZIndex = 4 }, sg)
	self.BgGlow = G.glow(sg, { Name = "Glow", Color = crate.Color, Transparency = 0.4, Position = S(0.5, 0.52), Size = O(1100, 1100), ZIndex = 5 })
	self.BgCore = G.glow(sg, { Name = "Core", Color = WHITE, Transparency = 0.75, Position = S(0.5, 0.52), Size = O(520, 520), ZIndex = 6 })
	self.Speed = {}
	for i = 1, 18 do
		local a = (i / 18) * math.pi * 2
		local l = G.new("Frame", { Name = "Speed", AnchorPoint = V2(0, 0.5), Position = S(0.5, 0.52), Size = O(420, 6), Rotation = math.deg(a), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, sg)
		G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.4, 0.3), NK(1, 1) }) }, l)
		table.insert(self.Speed, { F = l, A = a, Ph = math.random() })
	end
	part({ Name = "Podium", Shape = Enum.PartType.Cylinder, Size = V3(0.8, 9, 9), CFrame = CFrame.new(STAGE + V3(0, -3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.SmoothPlastic, Color = C(14, 18, 56) }, f)
	self.PodRim = part({ Name = "PodRim", Shape = Enum.PartType.Cylinder, Size = V3(0.3, 9.5, 9.5), CFrame = CFrame.new(STAGE + V3(0, -3.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = crate.Color }, f)
	local key = part({ Name = "Key", Size = V3(1, 1, 1), Transparency = 1, CFrame = CFrame.new(STAGE + V3(0, 6, 9)) }, f)
	local kl = Instance.new("PointLight")
	kl.Range, kl.Brightness, kl.Color = 30, 2.2, WHITE
	kl.Parent = key
	local rim = part({ Name = "Rim", Size = V3(1, 1, 1), Transparency = 1, CFrame = CFrame.new(STAGE + V3(0, 2, -6)) }, f)
	self.RimLight = Instance.new("PointLight")
	self.RimLight.Range, self.RimLight.Brightness, self.RimLight.Color = 24, 3, crate.Color
	self.RimLight.Parent = rim
	local fx = part({ Name = "Fx", Size = V3(1, 1, 1), Transparency = 1, CFrame = CFrame.new(STAGE) }, f)
	local att = Instance.new("Attachment")
	att.Parent = fx
	self.FxPart = fx
	local function emitter(props)
		local e = Instance.new("ParticleEmitter")
		e.Enabled, e.LightEmission, e.LockedToPart = false, 1, false
		for k, v in props do
			e[k] = v
		end
		e.Parent = att
		return e
	end
	self.Puff = emitter({ Texture = "rbxasset://textures/particles/smoke_main.dds", Color = CS(C(220, 230, 255)), LightEmission = 0.4, Size = NS({ NK(0, 2), NK(1, 6) }), Transparency = NS({ NK(0, 0.4), NK(1, 1) }), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(10, 18), SpreadAngle = V2(180, 30), Drag = 6, Acceleration = V3(0, 2, 0) })
	self.Sparks = emitter({ Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = CS(crate.Light, WHITE), Size = NS({ NK(0, 0.9), NK(1, 0) }), Lifetime = NumberRange.new(0.5, 1.1), Speed = NumberRange.new(14, 30), SpreadAngle = V2(180, 180), Drag = 3, Acceleration = V3(0, -14, 0) })
	self.Flames = emitter({ Texture = "rbxasset://textures/particles/fire_main.dds", Size = NS({ NK(0, 3.5), NK(0.6, 2.6), NK(1, 0) }), Transparency = NS({ NK(0, 0.5), NK(0.3, 0.2), NK(1, 1) }), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(4, 9), SpreadAngle = V2(70, 10), Rate = 70, Acceleration = V3(0, 10, 0), EmissionDirection = Enum.NormalId.Top, ZOffset = -2 })
	self.Motes = emitter({ Texture = "rbxasset://textures/particles/sparkles_main.dds", Size = NS({ NK(0, 0), NK(0.3, 0.6), NK(1, 0) }), Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(2, 5), SpreadAngle = V2(180, 180), Rate = 40, Acceleration = V3(0, 3, 0) })
	self.Pillar = part({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = V3(40, 3.2, 3.2), CFrame = CFrame.new(STAGE + V3(0, 6, -4)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = WHITE, Transparency = 1 }, f)
	self.Orbs = {}
	for i = 1, 8 do
		table.insert(self.Orbs, { P = part({ Name = "Orb", Shape = Enum.PartType.Ball, Size = V3(0.32, 0.32, 0.32), Material = Enum.Material.Neon, Color = WHITE, Transparency = 1, CFrame = CFrame.new(STAGE) }, f), A = i / 8 * math.pi * 2, H = (i % 3) * 0.9 - 0.9 })
	end
	self:_buildCrate(crate)
	f.Parent = workspace
end

-- the crate as a real model so each tap can spin it a full turn. Its front and back wear the board's own
-- crate art (CrateConfig crate.Art Body / Lid, self-lit), with a neon-railed box behind for depth when it turns.
function CrateOpening:_buildCrate(crate)
	local m = Instance.new("Model")
	m.Name = "Crate"
	local base = CFrame.new(STAGE + V3(0, -0.4, 0))
	local W = 7.2
	local H = W / (878 / 608)
	local core = part({ Name = "Core", Size = V3(W * 0.84, H * 0.6, 3.5), CFrame = base * CFrame.new(0, -H * 0.13, 0), Material = Enum.Material.SmoothPlastic, Color = crate.Dark }, m)
	m.PrimaryPart = core
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			part({ Name = "Rail", Size = V3(0.2, 0.2, 3.56), CFrame = base * CFrame.new(x * W * 0.42, -H * 0.13 + y * H * 0.3, 0), Material = Enum.Material.Neon, Color = crate.Color }, m)
		end
		part({ Name = "Side", Size = V3(0.16, H * 0.5, 3.0), CFrame = base * CFrame.new(x * W * 0.425, -H * 0.13, 0), Material = Enum.Material.Neon, Color = crate.Light, Transparency = 0.35 }, m)
	end
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	part({ Name = "LidCore", Size = V3(W * 0.9, H * 0.2, 3.7), CFrame = base * CFrame.new(0, H * 0.25, 0), Material = Enum.Material.SmoothPlastic, Color = crate.Color }, lid)
	part({ Name = "LidBand", Size = V3(W * 0.91, 0.14, 3.72), CFrame = base * CFrame.new(0, H * 0.16, 0), Material = Enum.Material.Neon, Color = crate.Light }, lid)
	local function card(parent, img, z, face)
		local c = part({ Name = "Art", Size = V3(W, H, 0.05), CFrame = base * CFrame.new(0, 0, z), Transparency = 1 }, parent)
		local sg = Instance.new("SurfaceGui")
		sg.Face, sg.LightInfluence, sg.Brightness = face, 0, 1.15
		sg.SizingMode, sg.CanvasSize = Enum.SurfaceGuiSizingMode.FixedSize, V2(878, 608)
		sg.Parent = c
		self.G.new("ImageLabel", { BackgroundTransparency = 1, Image = img, Size = S(1, 1) }, sg)
		if img == crate.Art.Body then
			-- the REQ coin on the hex plate (same spot as the shop cards)
			self.G.glow(sg, { Color = crate.Light, Transparency = 0.35, Position = S(0.5, 0.628), Size = O(300, 300), ZIndex = 2 })
			self.G.new("ImageLabel", { Name = "Coin", BackgroundTransparency = 1, Image = self.G.A.Icon.Req, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.628), Size = O(205, 205), ZIndex = 3 }, sg)
		end
		return c
	end
	-- Back faces +Z (toward the camera), Front faces -Z
	card(m, crate.Art.Body, 1.85, Enum.NormalId.Back)
	card(m, crate.Art.Body, -1.85, Enum.NormalId.Front)
	card(lid, crate.Art.Lid, 1.9, Enum.NormalId.Back)
	card(lid, crate.Art.Lid, -1.9, Enum.NormalId.Front)
	lid.WorldPivot = base
	lid.Parent = m
	local glowPart = part({ Name = "Inner", Size = V3(1, 1, 1), Transparency = 1, CFrame = base * CFrame.new(0, H * 0.18, 0) }, m)
	local inner = Instance.new("PointLight")
	inner.Range, inner.Brightness, inner.Color = 12, 0, crate.Light
	inner.Parent = glowPart
	self.CrateModel, self.CrateLid, self.CrateInner = m, lid, inner
	self.CrateBase = base
	m.WorldPivot = base
	m.Parent = self.Stage
end

function CrateOpening:_setBg(key)
	self.BgCycle = nil
	if key == "cycle" then
		self.BgCycle = { I = 1, T = os.clock() }
		self.BgA.Image = Config.Images.Open[Config.Cycle[1]]
		self.BgB.Image = Config.Images.Open[Config.Cycle[2]]
	else
		self.BgA.Image = Config.Images.Open[key] or Config.Images.Open.h0
		self.BgB.ImageTransparency = 1
	end
end

-- ─── camera ─────────────────────────────────────────────────────────────────────────────
function CrateOpening:_grabCamera()
	local cam = workspace.CurrentCamera
	self.SavedCam = { Type = cam.CameraType, CF = cam.CFrame, Fov = cam.FieldOfView, Subject = cam.CameraSubject }
	self.Shake = 0
	RunService:BindToRenderStep("VantageCrateCam", Enum.RenderPriority.Camera.Value + 10, function(dt)
		local c = workspace.CurrentCamera
		c.CameraType = Enum.CameraType.Scriptable
		c.FieldOfView = FOV
		local cf = CFrame.lookAt(CAM_POS, CAM_LOOK)
		if self.Shake > 0 then
			local s = self.Shake
			cf *= CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * s * 0.05)
			self.Shake = math.max(0, s - dt * 1.6)
		end
		c.CFrame = cf
		self:_step(dt)
	end)
end

function CrateOpening:_releaseCamera()
	pcall(RunService.UnbindFromRenderStep, RunService, "VantageCrateCam")
	local s = self.SavedCam
	if s then
		local cam = workspace.CurrentCamera
		cam.CameraType = s.Type
		cam.CFrame = s.CF
		cam.FieldOfView = s.Fov
		if s.Subject then
			cam.CameraSubject = s.Subject
		end
	end
end

-- ─── flow ───────────────────────────────────────────────────────────────────────────────
function CrateOpening:Play(crate, opts)
	if self.Active then
		return
	end
	opts = opts or {}
	self.Active = true
	self.Crate, self.PlayOpts = crate, opts
	self.Result, self.Phase, self.Taps, self.SpinAngle = nil, "Intro", 0, 0
	self.Token = (self.Token or 0) + 1
	local token = self.Token
	-- ask the server now; the drop is decided before anything animates
	task.spawn(function()
		local ok, res = pcall(function()
			return Remotes:WaitForChild("CrateOpen", 5):InvokeServer(crate.Id, opts.Count or 1)
		end)
		if token ~= self.Token then
			return
		end
		self.Result = if ok and type(res) == "table" then res else { Ok = false, Error = "No connection" }
		if self.Result.Ok then
			self:_placeWinner()
		end
		if not self.Result.Ok then
			self.G.sound("Deny")
			self.Toast(self.Result.Error or "Could not open")
			task.delay(1.2, function()
				if token == self.Token then
					self:Close()
				end
			end)
		end
	end)
	self:_buildStage(crate)
	self:_setBg("h0")
	self:_prepReel()
	self.Gui.Enabled = true
	self.Info.Visible, self.TapLayer.Visible = false, false
	self.ReelLayer.Visible = true -- the possible-drops strip shows under the crate from the start
	self.Dim.BackgroundTransparency = 0
	tween(self.Dim, 0.5, { BackgroundTransparency = 1 })
	self:_grabCamera()
	-- intro: the crate drops in from above and lands on the podium
	self.Intro = { T = os.clock(), D = 0.7 }
	self:_sfx("Open", 1, 1)
	task.delay(0.7, function()
		if token ~= self.Token then
			return
		end
		self:_sfx("Land", 1, 1)
		self.Shake = 0.35
		self.Sparks:Emit(20)
		self.Puff:Emit(14)
		if opts.Fast then
			self:_waitResult(token, function()
				self:_burst(token)
			end)
			return
		end
		self.Phase = "Tap"
		self.TapLayer.Visible, self.TapBtn.Visible = true, true
		self.TapSub.Text = crate.Name .. " · 4 taps to smash it open"
		for _, t in self.Tokens do
			t.Q.TextTransparency, t.Ic.ImageTransparency = 0, 1
			t.F.BackgroundColor3 = C(14, 18, 60)
		end
		self.TapTitle.TextTransparency = 1
		tween(self.TapTitle, 0.35, { TextTransparency = 0 })
	end)
end

function CrateOpening:_waitResult(token, fn)
	task.spawn(function()
		local t = os.clock()
		while not self.Result and os.clock() - t < 10 and token == self.Token do
			task.wait()
		end
		if token == self.Token and self.Result and self.Result.Ok then
			fn()
		end
	end)
end

function CrateOpening:_tap()
	if self.Phase ~= "Tap" or (self.Spin and os.clock() - self.Spin.T < 0.28) then
		return
	end
	self.Taps += 1
	local n = self.Taps
	local tok = self.Tokens[n]
	if tok then
		tok.Q.TextTransparency = 1
		tok.Ic.ImageTransparency = 0
		tok.F.BackgroundColor3 = self.Crate.Color
		tok.F.Size = O(100, 100)
		tween(tok.F, 0.3, { Size = O(76, 76) }, Enum.EasingStyle.Back)
	end
	-- every tap is the same full turn: nothing here depends on the drop
	self.Spin = { T = os.clock(), D = 0.5, From = self.SpinAngle }
	self.SpinAngle += math.pi * 2
	self.Flash.BackgroundTransparency = 0.55
	tween(self.Flash, 0.25, { BackgroundTransparency = 1 })
	self.Puff:Emit(10)
	self.Sparks:Emit(16 + n * 4)
	self.Shake = 0.25 + n * 0.08
	self.CrateInner.Brightness = 1.5 + n
	tween(self.CrateInner, 0.5, { Brightness = n * 0.6 })
	self:_sfx(if n % 2 == 1 then "Whoosh" else "Whoosh2", 0.95 + n * 0.06)
	self:_sfx("Hit", 1.1 + n * 0.08, 0.45)
	self.TapTitle.Size = O(990, 99)
	tween(self.TapTitle, 0.2, { Size = O(900, 90) }, Enum.EasingStyle.Back)
	if n >= 4 then
		self.Phase = "Burst"
		self.TapBtn.Visible = false
		local token = self.Token
		task.delay(0.5, function()
			self:_waitResult(token, function()
				self:_burst(token)
			end)
		end)
	end
end

function CrateOpening:_burst(token)
	if token ~= self.Token then
		return
	end
	self.Phase = "Burst"
	self.TapLayer.Visible = false
	self:_sfx("Break", 1, 1)
	self:_sfx("Riser", 1, 0.6)
	self.Flash.BackgroundTransparency = 0
	tween(self.Flash, 0.6, { BackgroundTransparency = 1 })
	self.Shake = 0.9
	self.Ring.Size = O(40, 40)
	self.RingSt.Transparency = 0
	self.RingSt.Thickness = 18
	self.RingSt.Color = self.Crate.Light
	tween(self.Ring, 0.6, { Size = O(1800, 1800) }, Enum.EasingStyle.Quart)
	tween(self.RingSt, 0.6, { Transparency = 1, Thickness = 2 })
	self.Sparks:Emit(80)
	self.Puff:Emit(30)
	self.Burst = { T = os.clock() }
	task.delay(0.55, function()
		if token == self.Token then
			self:_startReel(token)
		end
	end)
end

-- ─── reel ───────────────────────────────────────────────────────────────────────────────
function CrateOpening:_card(parent, e, i)
	local G = self.G
	local col = Config.TierColor[e.Rarity] or WHITE
	local f = G.new("Frame", { Name = "C" .. i, AnchorPoint = V2(0.5, 0.5), Position = O((i - 1) * (CARD_W + CARD_GAP) + CARD_W / 2, 140), Size = O(CARD_W, 248), BackgroundColor3 = WHITE, ZIndex = 13 }, parent)
	G.corner(f, 18)
	G.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, col:Lerp(WHITE, 0.25)), CK(0.6, col:Lerp(INK, 0.35)), CK(1, col:Lerp(INK, 0.7)) }) }, f)
	local st = G.new("UIStroke", { Thickness = 4, Color = col }, f)
	if e.Rarity == "Godly" or e.Rarity == "Exclusive" then
		st.Color = WHITE
		G.new("UIGradient", { Color = chroma(e.Rarity) }, st)
	end
	local pv = Config.Preview(e.Key)
	local img = G.new("ImageLabel", { Name = "Skin", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = O(148, 148), ZIndex = 14 }, f)
	if pv then
		img.Image, img.ImageRectOffset, img.ImageRectSize = pv.Image, pv.Offset, pv.Size
	end
	G.corner(img, 14)
	G.text(f, { Text = e.Name, Position = O(8, 168), Size = UDim2.new(1, -16, 0, 44), TextSize = 19, Stroke = 3, Wrapped = true, ZIndex = 15 })
	G.text(f, { Text = string.upper(e.Rarity), Position = O(8, 214), Size = UDim2.new(1, -16, 0, 22), TextSize = 14, Stroke = 2.4, ZIndex = 15, Color = col:Lerp(WHITE, 0.45), Font = G.F.Bold })
	local shade = G.new("Frame", { Name = "Shade", BackgroundColor3 = INK, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 17 }, f)
	G.corner(shade, 18)
	return f
end

-- cosmetic strip weighted like the crate (every rarity shows up); the winner slot is filled when the server answers
function CrateOpening:_pick()
	local pool, crate = Config.Pool(), self.Crate
	if not self.PickTiers then
		local tiers, total = {}, 0
		for _, t in Config.Tiers do
			local w = crate.Odds[t]
			if w and #pool.ByTier[t] > 0 then
				w = math.max(w, 2.5)
				table.insert(tiers, { t, w })
				total += w
			end
		end
		self.PickTiers, self.PickTotal = tiers, total
	end
	local x = math.random() * self.PickTotal
	for _, e in self.PickTiers do
		x -= e[2]
		if x <= 0 then
			local l = pool.ByTier[e[1]]
			return l[math.random(1, #l)]
		end
	end
	local l = pool.ByTier[self.PickTiers[#self.PickTiers][1]]
	return l[math.random(1, #l)]
end

-- the "possible drops" strip idles under the crate during the taps, then becomes the spin reel
function CrateOpening:_prepReel()
	for _, ch in self.Strip:GetChildren() do
		ch:Destroy()
	end
	self.PickTiers = nil
	self.Cards = {}
	for i = 1, REEL_N do
		local e = self:_pick()
		self.Cards[i] = { F = self:_card(self.Strip, e, i), E = e }
	end
	self.ReelLayer.Visible = true
	self.ReelRig.Position = S(0.5, 0.86)
	self.RigScale.Scale = 0.5
	self.Lens.Visible = false
	self.ReelTag.TextTransparency = 0
	self.ReelBand.BackgroundTransparency = 0.45
	self.ReelLight.ImageTransparency = 1
	self.Reel = { Idle = true, X = CARD_W * 2, Prev = CARD_W * 2, LastIdx = 0, Done = false }
end

function CrateOpening:_placeWinner()
	local res = self.Result
	if not (res and res.Ok and self.Cards and #self.Cards >= REEL_N) then
		return
	end
	local pool = Config.Pool()
	local function put(i, e)
		local old = self.Cards[i]
		if old then
			old.F:Destroy()
		end
		self.Cards[i] = { F = self:_card(self.Strip, e, i), E = e }
	end
	put(REEL_WIN, { Weapon = res.Weapon, Skin = res.Skin, Rarity = res.Rarity, Name = res.Name, Key = res.Weapon .. "/" .. res.Skin })
	-- near miss: a top-tier card right after the winner when the winner is lower
	if Config.TierIndex[res.Rarity] < 5 then
		local top = pool.ByTier[if #pool.ByTier.Godly > 0 then "Godly" else "Legendary"]
		if #top > 0 then
			put(REEL_WIN + 1, top[math.random(1, #top)])
		end
	end
end

function CrateOpening:_startReel(token)
	local res = self.Result
	self.Phase = "Reel"
	self.CrateModel.Parent = nil
	tween(self.BgShade, 0.4, { BackgroundTransparency = 0.15 })
	-- the same strip rises into the centre and takes over
	self.ReelLayer.Visible = true
	tween(self.ReelRig, 0.45, { Position = S(0.5, 0.5) }, Enum.EasingStyle.Quart)
	tween(self.RigScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Quart)
	tween(self.ReelTag, 0.2, { TextTransparency = 1 })
	tween(self.ReelBand, 0.45, { BackgroundTransparency = 0.25 })
	tween(self.ReelLight, 0.5, { ImageTransparency = 0.45 })
	self.Lens.Visible = true
	local step = CARD_W + CARD_GAP
	local jitter = (math.random() - 0.5) * CARD_W * 0.6
	local target = (REEL_WIN - 1) * step + CARD_W / 2 + jitter
	local ms = if self.PlayOpts.Fast then 1800 else (SPIN_MS[res.Rarity] or 5000)
	local from = if self.Reel and self.Reel.X then self.Reel.X else 0
	self.Reel = { T = os.clock(), D = ms / 1000, From = from, Target = target, LastIdx = 0, Creep = Config.TierIndex[res.Rarity] >= 4 and not self.PlayOpts.Fast, Done = false, Prev = from }
	self:_sfx("Swell", 1, 0.7)
end

function CrateOpening:_reelPos(k)
	local r = self.Reel
	local span = r.Target - r.From
	if r.Creep then
		if k < 0.78 then
			local q = k / 0.78
			return r.From + span * 0.985 * (1 - (1 - q) ^ 3)
		end
		local q = (k - 0.78) / 0.22
		return r.From + span * (0.985 + 0.015 * (1 - (1 - q) ^ 2))
	end
	return r.From + span * (1 - (1 - k) ^ 4)
end

function CrateOpening:_layoutReel(x, speed)
	local step = CARD_W + CARD_GAP
	self.Strip.Position = UDim2.new(0.5, -x, 0.5, 0)
	local blur = math.clamp(speed / 4000, 0, 1)
	for i, c in self.Cards do
		local cx = (i - 1) * step + CARD_W / 2 - x
		local d = math.abs(cx) / 900
		if d < 1.2 then
			c.F.Visible = true
			local s = 1 - 0.32 * d * d
			c.F.Size = O(CARD_W * s * (1 + blur * 0.25), 248 * s)
			c.F.Position = O((i - 1) * step + CARD_W / 2, 140 + d * d * 30)
			c.F.Rotation = math.clamp(cx / 900, -1, 1) * 6
		else
			c.F.Visible = false
		end
	end
	local idx = math.floor(x / step) + 1
	return idx, self.Cards[math.clamp(idx, 1, REEL_N)]
end

function CrateOpening:_stepReel(dt)
	local r = self.Reel
	if not r or r.Done then
		return
	end
	if r.Idle then
		r.X += dt * 26
		self:_layoutReel(r.X, 0)
		return
	end
	local k = math.clamp((os.clock() - r.T) / r.D, 0, 1)
	local x = self:_reelPos(k)
	local speed = (x - r.Prev) / math.max(dt, 1e-3)
	r.Prev = x
	local idx, cur = self:_layoutReel(x, speed)
	if idx ~= r.LastIdx then
		r.LastIdx = idx
		local ti = cur and Config.TierIndex[cur.E.Rarity] or 1
		self:_sfx("Tick", 0.94 + ti * 0.05, 0.55 + 0.45 * math.clamp(speed / 3000, 0, 1))
	end
	if cur then
		local col = Config.TierColor[cur.E.Rarity] or WHITE
		self.ReelLight.ImageColor3 = self.ReelLight.ImageColor3:Lerp(col, math.min(1, dt * 10))
		self.LensSt.Color = self.LensSt.Color:Lerp(col:Lerp(WHITE, 0.5), math.min(1, dt * 10))
		self.BgGlow.ImageColor3 = self.ReelLight.ImageColor3
	end
	if k >= 1 then
		r.Done = true
		self:_lock()
	end
end

function CrateOpening:_lock()
	local res = self.Result
	local token = self.Token
	local col = Config.TierColor[res.Rarity] or WHITE
	self:_sfx("Lock", 1, 1)
	self.Lens.Size = O(CARD_W + 64, 336)
	tween(self.Lens, 0.22, { Size = O(CARD_W + 26, 300) }, Enum.EasingStyle.Quart)
	self.LensSt.Color = col
	-- everything but the winner steps back
	for i, c in self.Cards do
		local sh = c.F:FindFirstChild("Shade")
		if sh and i ~= REEL_WIN then
			tween(sh, 0.25, { BackgroundTransparency = 0.4 })
		end
	end
	local win = self.Cards[REEL_WIN]
	if win then
		win.F.ZIndex = 20
		tween(win.F, 0.24, { Size = O(CARD_W * 1.18, 248 * 1.18) }, Enum.EasingStyle.Quart)
		local g = self.G.glow(win.F, { Color = col, Transparency = 1, Size = S(1.7, 1.5), ZIndex = 12 })
		tween(g, 0.3, { ImageTransparency = 0.35 })
	end
	self.Shake = 0.35
	task.delay(0.85, function()
		if token == self.Token then
			self:_reveal(token)
		end
	end)
end

-- ─── reveal ─────────────────────────────────────────────────────────────────────────────
function CrateOpening:_reveal(token)
	local res = self.Result
	local G = self.G
	local col = Config.TierColor[res.Rarity] or WHITE
	local ti = Config.TierIndex[res.Rarity] or 1
	self.Phase = "Reveal"
	self.Flash.BackgroundColor3 = col:Lerp(WHITE, 0.6)
	self.Flash.BackgroundTransparency = 0
	tween(self.Flash, 0.8, { BackgroundTransparency = 1 })
	self.ReelLayer.Visible = false
	self:_setBg(Config.OpenByTier[res.Rarity] or "h0")
	tween(self.BgShade, 0.6, { BackgroundTransparency = 0.45 })
	self.BgGlow.ImageColor3 = col
	self.RimLight.Color = col
	self.PodRim.Color = col
	self:_sfx("Hit", 0.55, 1)
	self:_sfx("Shimmer", 1, 1)
	self:_sfx("Swell", 1.15, 0.7)
	if ti >= 4 then
		self:_sfx("Riser", 1.2, 0.7)
	end
	-- the gun, in the won skin
	local ok, model = pcall(K.weapon, res.Weapon, res.Skin)
	if ok and model then
		-- a Highlight draws invisible parts too: drop every hidden part so no ghost outline shows
		model.PrimaryPart = nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency >= 0.99 and d.Parent then
				d:Destroy()
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
			end
		end
		model.WorldPivot = CFrame.new((model:GetBoundingBox()).Position)
		local bsz = model:GetExtentsSize()
		local scale = 11 / math.max(bsz.X, bsz.Y * 2.6, bsz.Z * 2.6, 0.1)
		pcall(function()
			model:ScaleTo(model:GetScale() * scale)
		end)
		model.WorldPivot = CFrame.new((model:GetBoundingBox()).Position)
		model.Parent = self.Stage
		local hl = Instance.new("Highlight")
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillColor, hl.FillTransparency = WHITE, 0
		hl.OutlineColor, hl.OutlineTransparency = col:Lerp(WHITE, 0.3), 0
		hl.Adornee, hl.Parent = model, model
		self.Gun, self.GunHl = model, hl
		-- paint-on: the white silhouette fades into the skin
		task.delay(0.25, function()
			if token == self.Token and hl.Parent then
				tween(hl, 0.9, { FillTransparency = 1 }, Enum.EasingStyle.Sine)
			end
		end)
		self.Turn = { T = os.clock() + 0.3, D = 1.6 }
	else
		warn("[VANTAGE] CrateOpening: weapon model failed:", model)
	end
	-- aura, scaled by rarity
	self.Aura = ti
	self.FxPart.CFrame = CFrame.new(STAGE + V3(0, -2.4, 0))
	self.Flames.Color = if ti >= 6 then RAINBOW else CS(col:Lerp(WHITE, 0.4), col)
	self.Flames.Rate = 20 + ti * 14
	self.Flames.Enabled = ti >= 2
	self.Motes.Color = CS(col:Lerp(WHITE, 0.6))
	self.Motes.Enabled = true
	self.Sparks.Color = CS(col:Lerp(WHITE, 0.5), WHITE)
	self.Sparks:Emit(40 + ti * 20)
	self.Pillar.Color = col:Lerp(WHITE, 0.35)
	tween(self.Pillar, 0.6, { Transparency = if ti >= 3 then 0.55 else 0.8 })
	for _, o in self.Orbs do
		o.P.Color = col:Lerp(WHITE, 0.4)
		o.P.Transparency = if ti >= 3 then 0 else 1
	end
	if ti >= 6 then
		self.Shake = 1.4
	elseif ti >= 4 then
		self.Shake = 0.7
	end
	self:_confetti(col, ti)
	task.delay(0.9, function()
		if token ~= self.Token then
			return
		end
		self.Info.Visible = true
		self.RarityHolder:ClearAllChildren()
		local chip = G.new("Frame", { Name = "Chip", AnchorPoint = V2(0.5, 0), Position = S(0.5, 0), Size = O(0, 52), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, ZIndex = 22 }, self.RarityHolder)
		G.corner(chip, 14)
		G.stroke(chip, 4, INK)
		local cg = G.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, col:Lerp(WHITE, 0.6)), CK(0.55, col), CK(1, col:Lerp(INK, 0.5)) }) }, chip)
		if ti >= 5 then
			cg.Color, cg.Rotation = chroma(res.Rarity), 0
			self.ChipGrad = cg
		end
		G.new("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 26) }, chip)
		G.text(chip, { Text = string.upper(res.Rarity), Size = O(0, 52), Auto = Enum.AutomaticSize.X, TextSize = 30, Stroke = 4, ZIndex = 23 })
		G.glow(chip, { Color = col, Transparency = 0.4, Size = UDim2.new(1, 80, 1, 80), ZIndex = 21 })
		self.NameLbl.Text = res.Name
		self.NameLbl.TextTransparency = 1
		tween(self.NameLbl, 0.4, { TextTransparency = 0 })
		self.WpnLbl.Text = string.upper(res.Weapon)
		local up = if res.Count == 5 then 110 else 0
		self.NameLbl.Position = UDim2.new(0.5, 0, 1, -330 - up)
		self.WpnLbl.Position = UDim2.new(0.5, 0, 1, -236 - up)
		if res.Count == 5 then
			local new, refund = 0, 0
			for _, r in res.Results do
				if r.Dup then refund += r.Refund else new += 1 end
			end
			self.NewLbl.Text = if refund > 0 then string.format("%d NEW · +%s REQ REFUND", new, G.abbrev(refund)) else string.format("%d NEW SKINS!", new)
			self.NewGrad.Color = CS({ CK(0, C(255, 243, 196)), CK(0.55, C(255, 176, 46)), CK(1, C(224, 86, 15)) })
		elseif res.Dup then
			self.NewLbl.Text = string.format("DUPLICATE · +%s REQ", G.abbrev(res.Refund or 0))
			self.NewGrad.Color = CS({ CK(0, C(190, 214, 255)), CK(1, C(52, 80, 200)) })
		else
			self.NewLbl.Text = "NEW!"
			self.NewGrad.Color = CS({ CK(0, C(255, 243, 196)), CK(0.55, C(255, 176, 46)), CK(1, C(224, 86, 15)) })
		end
		local cost = Config.Price(self.Crate, self.PlayOpts.Count or 1)
		local canAgain = (tonumber(player:GetAttribute("REQ")) or 0) >= cost
		self.Btns.Again.L.Text = (if (self.PlayOpts.Count or 1) == 5 then "Again ×5" else "Again") .. " · " .. G.abbrev(cost)
		self:_multi(res)
		self.Btns.Again.B.Visible = canAgain
		self.Btns.Equip.L.Text = "Equip now"
		self.Btns.Equip.Ctl:SetDisabled(false)
		for i, n in { "Equip", "Again", "Done" } do
			local sc = self.Btns[n].B:FindFirstChildOfClass("UIScale")
			if sc then
				sc.Scale = 0.86
				task.delay(0.06 * i, function()
					UX.tween(sc, 0.24, { Scale = 1 })
				end)
			end
		end
		self:_sfx("Hit", 1.3, 0.4)
	end)
end

-- x5: all five drops as neon preview tiles above the buttons (the best one is revealed)
function CrateOpening:_multi(res)
	local G = self.G
	if self.MultiRow then
		self.MultiRow:Destroy()
		self.MultiRow = nil
	end
	if not (res.Results and #res.Results > 1) then
		return
	end
	local row = G.new("Frame", { Name = "Multi", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 1, -196), Size = O(5 * 96 + 4 * 14, 96), ZIndex = 22 }, self.Info)
	G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, r in res.Results do
		local col = Config.TierColor[r.Rarity] or WHITE
		local pv = Config.Preview(r.Weapon .. "/" .. r.Skin)
		local t = G.new("ImageLabel", { Name = "R" .. i, BackgroundColor3 = col:Lerp(INK, 0.55), Size = O(96, 96), LayoutOrder = i, ZIndex = 23, Image = pv and pv.Image or "", ImageRectOffset = pv and pv.Offset or V2(0, 0), ImageRectSize = pv and pv.Size or V2(0, 0) }, row)
		G.corner(t, 16)
		local st = G.new("UIStroke", { Thickness = if i == res.Best then 5 else 3, Color = col }, t)
		if r.Rarity == "Godly" or r.Rarity == "Exclusive" then
			st.Color = WHITE
			G.new("UIGradient", { Color = chroma(r.Rarity) }, st)
		end
		G.glow(t, { Color = col, Transparency = 0.3, Size = S(1.9, 1.9), ZIndex = 22 })
		G.text(t, { Text = if r.Dup then "+" .. G.abbrev(r.Refund) else "NEW", AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = O(90, 22), TextSize = 16, Stroke = 3, ZIndex = 24, Color = if r.Dup then C(200, 253, 255) else C(255, 243, 196) })
		t.Size = O(40, 40)
		task.delay(0.08 * i, function()
			if t.Parent then
				G.tween(t, 0.35, { Size = O(96, 96) }, Enum.EasingStyle.Back)
				self:_sfx("Tick", 1 + i * 0.1, 0.6)
			end
		end)
	end
	self.MultiRow = row
end

function CrateOpening:_confetti(col, ti)
	local G = self.G
	local n = ({ 0, 10, 24, 40, 56, 80 })[ti] or 0
	local cols = { col, col:Lerp(WHITE, 0.5), WHITE }
	if ti >= 5 then
		cols = { C(255, 92, 92), C(255, 190, 60), C(90, 255, 160), C(80, 200, 255), C(170, 110, 255), C(255, 92, 200) }
	end
	self.Bits = {}
	for _ = 1, n do
		local f = G.new("Frame", { Name = "Bit", AnchorPoint = V2(0.5, 0.5), Size = O(math.random(8, 16), math.random(14, 26)), BackgroundColor3 = cols[math.random(1, #cols)], BorderSizePixel = 0, ZIndex = 18 }, self.Confetti)
		local a = math.random() * math.pi * 2
		local v = 500 + math.random() * 900
		table.insert(self.Bits, { F = f, X = 0.5, Y = 0.5, VX = math.cos(a) * v, VY = math.sin(a) * v - 600, R = math.random() * 360, VR = (math.random() - 0.5) * 900 })
	end
end

-- ─── per frame ──────────────────────────────────────────────────────────────────────────
function CrateOpening:_step(dt)
	local t = os.clock()
	if not self.Stage then
		return
	end
	local z = 1.08 + 0.04 * math.sin(t * 0.4)
	self.BgA.Size, self.BgB.Size = S(z, z), S(z, z)
	self.BgRays.Rotation = (t * (if self.Phase == "Reveal" then 14 else 6)) % 360
	self.BgCore.ImageTransparency = 0.7 + 0.12 * math.sin(t * 3)
	if self.BgCycle then
		local k = (t - self.BgCycle.T) / 1.2
		if k >= 1 then
			self.BgCycle.T, k = t, 0
			self.BgCycle.I = self.BgCycle.I % #Config.Cycle + 1
			self.BgA.Image = Config.Images.Open[Config.Cycle[self.BgCycle.I]]
			self.BgB.Image = Config.Images.Open[Config.Cycle[self.BgCycle.I % #Config.Cycle + 1]]
		end
		self.BgB.ImageTransparency = 1 - k
	end
	local speedOn = self.Phase == "Reveal" or self.Burst ~= nil
	for _, s in self.Speed do
		local ph = (t * 1.4 + s.Ph) % 1
		s.F.Position = UDim2.new(0.5, math.cos(s.A) * (140 + ph * 700), 0.52, math.sin(s.A) * (140 + ph * 700))
		s.F.BackgroundTransparency = if speedOn then 0.3 + ph * 0.7 else 1
	end
	-- crate: intro drop, idle bob, tap spins, burst
	local m = self.CrateModel
	if m and m.Parent then
		local cf
		if self.Intro then
			local k = math.clamp((t - self.Intro.T) / self.Intro.D, 0, 1)
			local e = 1 - (1 - k) ^ 3
			cf = self.CrateBase * CFrame.new(0, (1 - e) * 14, (1 - e) * -6) * CFrame.Angles((1 - e) * 0.5, (1 - e) * 2.2, (1 - e) * 0.3)
			if k >= 1 then
				self.Intro = nil
			end
		else
			local bob = math.sin(t * 2.2) * 0.18
			local ang, yOff = self.SpinAngle, bob
			if self.Spin then
				local k = math.clamp((t - self.Spin.T) / self.Spin.D, 0, 1)
				ang = self.Spin.From + (1 - (1 - k) ^ 3) * math.pi * 2
				yOff = bob + (if k < 0.15 then -k / 0.15 * 0.5 elseif k < 0.6 then -0.5 + (k - 0.15) / 0.45 * 2.3 else 1.8 * (1 - (k - 0.6) / 0.4) ^ 2)
				if k >= 1 then
					self.Spin = nil
				end
			end
			cf = self.CrateBase * CFrame.new(0, yOff, 0) * CFrame.Angles(0, ang + math.sin(t * 1.3) * 0.12, math.sin(t * 1.7) * 0.03)
		end
		m:PivotTo(cf)
		if self.Burst then
			local k = math.clamp((t - self.Burst.T) / 0.55, 0, 1)
			self.CrateLid:PivotTo(cf * CFrame.new(0, k * 10, k * 3) * CFrame.Angles(-k * 2.2, k * 0.9, k * 0.4))
			self.CrateInner.Brightness = 8 * (1 - k)
		end
	end
	-- gun: 360° turn, then float and sway
	local g = self.Gun
	if g and g.Parent then
		local base = CFrame.new(STAGE + V3(0, 0.4, 0))
		local ang, pop = 0, 1
		if self.Turn then
			local k = math.clamp((t - self.Turn.T) / self.Turn.D, 0, 1)
			ang = (1 - (1 - k) ^ 3) * math.pi * 2
			pop = 0.6 + 0.4 * math.clamp((t - self.Turn.T + 0.3) / 0.4, 0, 1)
			if k >= 1 then
				self.Turn = nil
				self.Settled = t
			end
		end
		local sway = if self.Settled then math.sin((t - self.Settled) * 0.9) * 0.32 else 0
		local float = math.sin(t * 1.8) * 0.25
		g:PivotTo(base * CFrame.new(0, float - (1 - pop) * 2, 0) * CFrame.Angles(0, ang + sway, math.sin(t * 1.1) * 0.05))
		if self.GunHl and self.GunHl.Parent and self.GunHl.FillTransparency > 0.99 then
			self.GunHl.OutlineTransparency = 0.15 + 0.25 * (0.5 + 0.5 * math.sin(t * 4))
			if self.Aura and self.Aura >= 6 then
				self.GunHl.OutlineColor = Color3.fromHSV((t * 0.25) % 1, 0.7, 1)
			end
		end
		self.BgGlow.ImageTransparency = 0.25 + 0.15 * math.sin(t * 2.4)
		self.RimLight.Brightness = 3 + 1.5 * math.sin(t * 2.4)
		for _, o in self.Orbs do
			local a = o.A + t * 1.4
			o.P.CFrame = CFrame.new(STAGE + V3(math.cos(a) * 6.2, 0.4 + o.H + math.sin(a * 2) * 0.4, math.sin(a) * 2.4))
		end
		if self.Aura and self.Aura >= 6 then
			self.Pillar.Color = Color3.fromHSV((t * 0.2) % 1, 0.45, 1)
		end
	end
	if self.ChipGrad and self.ChipGrad.Parent then
		self.ChipGrad.Offset = V2(math.sin(t * 1.2) * 0.4, 0)
	end
	if self.Bits then
		local vp = workspace.CurrentCamera.ViewportSize
		for i = #self.Bits, 1, -1 do
			local b = self.Bits[i]
			b.VY += 1400 * dt
			b.VX *= 1 - dt * 0.8
			b.X += b.VX * dt / vp.X
			b.Y += b.VY * dt / vp.Y
			b.R += b.VR * dt
			b.F.Position = S(b.X, b.Y)
			b.F.Rotation = b.R
			if b.Y > 1.2 then
				b.F:Destroy()
				table.remove(self.Bits, i)
			end
		end
	end
	self:_stepReel(dt)
end

-- ─── buttons / protocol ─────────────────────────────────────────────────────────────────
function CrateOpening:_equip()
	local r = self.Result
	if not (r and r.Ok) then
		return
	end
	local ev = Remotes:FindFirstChild("SkinEquip")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireServer(r.Weapon, r.Skin)
	end
	self.G.sound("Found")
	self.Btns.Equip.L.Text = "Equipped ✓"
	self.Btns.Equip.Ctl:SetDisabled(true, true)
end

function CrateOpening:_again()
	local crate, opts = self.Crate, self.PlayOpts
	self:Close(true)
	task.defer(function()
		self:Play(crate, opts)
	end)
end

function CrateOpening:Close(again)
	if not self.Active then
		return
	end
	self.Active = false
	self.Token = (self.Token or 0) + 1
	self.Phase = nil
	self.Reel, self.Spin, self.Burst, self.Turn, self.Settled, self.Intro, self.Bits = nil, nil, nil, nil, nil, nil, nil
	self.Aura, self.ChipGrad, self.BgCycle = nil, nil, nil
	self.TapBtn.Visible = false
	self.Info.Visible, self.ReelLayer.Visible, self.TapLayer.Visible = false, false, false
	self.Confetti:ClearAllChildren()
	for _, ch in self.Strip:GetChildren() do
		ch:Destroy()
	end
	self:_releaseCamera()
	if self.Stage then
		self.Stage:Destroy()
		self.Stage, self.Gun, self.GunHl, self.CrateModel = nil, nil, nil, nil
	end
	self.Gui.Enabled = false
	local done = self.PlayOpts and self.PlayOpts.OnDone
	if done and not again then
		done(self.Result)
	end
end

function CrateOpening:HandleKey(kc)
	if not self.Active then
		return false
	end
	if self.Phase == "Tap" and (kc == Enum.KeyCode.Space or kc == Enum.KeyCode.Return or kc == Enum.KeyCode.ButtonA) then
		self:_tap()
	elseif self.Phase == "Reveal" and (kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Backspace) then
		self:Close()
	end
	return true -- swallow everything else while the sequence runs
end

return CrateOpening
