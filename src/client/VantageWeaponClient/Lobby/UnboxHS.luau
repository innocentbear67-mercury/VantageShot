--!nocheck
--[[
	UnboxHS - VantageShot crate opening (2026-11-16).
	Hypershot's two-phase structure (reel modal -> full-screen reveal), in VantageShot's own skin:
	  Reel:   violet panel with a soft stripe field, crate tab on the top edge, card reel with a cyan diamond marker, SKIP.
	  Reveal: violet stage with rotating rarity light rays + halo, 3D skin in a ViewportFrame, name band with rarity rails,
	          NEW / duplicate-refund line, x5 results row, COLLECT + EQUIP.
	The server decides the drop (Remotes.CrateOpen) the moment Play runs; the reel only lands on it.
	API matches CrateOpening: .Active, :Play(crate, {Count, Fast, OnDone}), :Close(), :HandleKey(kc).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local K = require(script.Parent:WaitForChild("ScreenKit"))

local player = Players.LocalPlayer
local RGB = Color3.fromRGB
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local CS, CK, NS, NK = ColorSequence.new, ColorSequenceKeypoint.new, NumberSequence.new, NumberSequenceKeypoint.new
local WHITE = Color3.new(1, 1, 1)

local P = {
	Panel = RGB(24, 9, 46), Deep = RGB(10, 4, 22), Edge = RGB(150, 80, 255), Glow = RGB(190, 120, 255),
	Rim = RGB(70, 36, 130), Card = RGB(30, 13, 56), Muted = RGB(184, 164, 222), Ink = RGB(12, 4, 26),
	Cyan = RGB(64, 224, 255), Stage0 = RGB(30, 11, 60), Stage1 = RGB(5, 2, 12), Green = RGB(117, 251, 134), Gold = RGB(255, 206, 84),
}
local DW, DH = 1920, 1080
local PW, PH = 860, 372
local WW, WH = 780, 176
local CW, CH, GAP = 122, 152, 10
local PITCH = CW + GAP
local N, WIN = 48, 40
local BAND_Y, BAND_H = 805, 132
local SPIN = { Rare = 4.6, Epic = 4.9, Mythic = 5.6, Legendary = 6.3, Exclusive = 6.8, Godly = 7.4 }
local SFX = {
	Tick = { 89658557478425, 0.4 }, Lock = { 131042770615213, 0.8 }, Shimmer = { 74567426909562, 0.55 },
	Swell = { 9040281024, 0.6 }, Riser = { 9045201066, 0.5 }, Hit = { 9048764753, 0.8 }, Whoosh = { 9120718279, 0.6 },
	Break = { 98213885190101, 0.9 }, Land = { 103406447926543, 0.8 },
}
-- hype per tier (1 Rare .. 6 Godly): embers/s, stars/s, burst sparks, glow (outline transparency, 1 = off),
-- charge-up seconds before the reveal, shake px, giant rarity slam, rainbow
local FXT = {
	{ Embers = 4, Stars = 1, Burst = 40, Glow = 1, Charge = 0, Shake = 4, Slam = false, Rings = 1 },
	{ Embers = 10, Stars = 3, Burst = 80, Glow = 0.5, Charge = 0, Shake = 8, Slam = false, Rings = 1 },
	{ Embers = 22, Stars = 6, Burst = 150, Glow = 0.32, Charge = 1.1, Shake = 16, Slam = true, Rings = 2 },
	{ Embers = 32, Stars = 9, Burst = 210, Glow = 0.22, Charge = 1.4, Shake = 22, Slam = true, Rings = 2 },
	{ Embers = 40, Stars = 12, Burst = 260, Glow = 0.16, Charge = 1.7, Shake = 26, Slam = true, Rings = 3, Rainbow = true },
	{ Embers = 50, Stars = 16, Burst = 320, Glow = 0.1, Charge = 2.0, Shake = 30, Slam = true, Rings = 3, Rainbow = true },
}
local function silhouette(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color, d.Material, d.Reflectance = WHITE, Enum.Material.SmoothPlastic, 0
			if d:IsA("MeshPart") then pcall(function() d.TextureID = "" end) end
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") or d:IsA("Highlight") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		end
	end
end

-- aura textures (white, tinted per rarity): bloom, two fine god-ray layers, energy ring, bokeh
local AURA = { Bloom = 103142630740394, RaysA = 113538852110620, RaysB = 84656415162737, Ring = 101633346517219, Bokeh = 79247701955793 }

local STAGE3 = Vector3.new(-2400, 9850, 300) -- 3D reveal stage, far from the map
local CHROMA_T = K.CHROMAS or {}

local function tierColor(r) return Config.TierColor[r] or WHITE end
-- 2026-11-18: padlock icon built from frames (skins pulled for a gun the player hasn't unlocked yet)
local function lockIcon(HS, parent, s, col, z)
	local root = HS.new("Frame", { Name = "LockIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(s, s), ZIndex = z }, parent)
	local sh = HS.new("Frame", { Name = "Shackle", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, s * 0.06), Size = UDim2.fromOffset(s * 0.5, s * 0.6), ZIndex = z }, root)
	HS.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, sh)
	HS.new("UIStroke", { Thickness = math.max(2, s * 0.11), Color = col }, sh)
	local body = HS.new("Frame", { Name = "Body", BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -s * 0.04), Size = UDim2.fromOffset(s * 0.76, s * 0.5), ZIndex = z + 1 }, root)
	HS.new("UICorner", { CornerRadius = UDim.new(0, math.max(2, s * 0.1)) }, body)
	local hole = HS.new("Frame", { Name = "Keyhole", BackgroundColor3 = Color3.fromRGB(20, 16, 24), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = UDim2.fromOffset(s * 0.16, s * 0.16), ZIndex = z + 2 }, body)
	HS.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hole)
	local slot = HS.new("Frame", { Name = "Slot", BackgroundColor3 = Color3.fromRGB(20, 16, 24), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(math.max(2, s * 0.06), s * 0.18), ZIndex = z + 2 }, body)
	return root
end
local LOCK_COL = Color3.fromRGB(255, 196, 86)
local function tierIndex(r) return Config.TierIndex[r] or 1 end
local function chroma(r) return r == "Godly" or r == "Exclusive" end
local function hex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
local function num(n)
	local s = tostring(math.floor(n or 0))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (r:gsub("^,", ""))
end

local Unbox = {}
Unbox.__index = Unbox

function Unbox.new(env)
	local self = setmetatable({ HS = env.HS, Env = env, Active = false, Token = 0, Sc = 1, Cards = {} }, Unbox)
	self:_build()
	RunService.RenderStepped:Connect(function(dt)
		if self.Active then
			self:_step(dt)
		end
	end)
	local function isPress(io)
		return io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
	end
	UserInputService.InputBegan:Connect(function(io, gp)
		if not self.Active or gp then return end
		self:HandleKey(io.KeyCode)
		local R = self.Rot
		if R and self.Phase == "Reveal" and self.Gun3 and isPress(io) then
			R.Drag, R.P, R.T, R.V = true, io.Position, os.clock(), 0
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		local R = self.Rot
		if not (R and R.Drag) then return end
		if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
			local now = os.clock()
			local d = io.Position - R.P
			R.P = io.Position
			R.Yaw += d.X * 0.012
			R.Pitch = math.clamp(R.Pitch + d.Y * 0.008, -0.9, 0.9)
			R.V = math.clamp(d.X * 0.012 / math.max(now - R.T, 1 / 240), -10, 10)
			R.T, R.Last = now, now
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		local R = self.Rot
		if R and R.Drag and isPress(io) then
			R.Drag, R.Last = false, os.clock()
			if os.clock() - R.T > 0.08 then R.V = 0 end
		end
	end)
	return self
end

function Unbox:_sfx(name, pitch, vol)
	local d = SFX[name]
	if not d then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. d[1]
	s.Volume = d[2] * (vol or 1)
	s.PlaybackSpeed = pitch or 1
	if self.HS.SoundGroup then s.SoundGroup = self.HS.SoundGroup end
	s.Parent = SoundService
	s:Play()
	task.delay(8, function() s:Destroy() end)
end

-- raw stroke for per-opening instances (not registered with HS.stroke, so nothing accumulates)
function Unbox:_rs(o, th, col)
	local st = Instance.new("UIStroke")
	st.Thickness = th * self.Sc
	st.Color = col
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.ApplyStrokeMode = if o:IsA("TextLabel") then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	st.Parent = o
	return st
end

function Unbox:_pill(parent, p)
	local HS = self.HS
	local b = HS.new("TextButton", { Name = p.Name, Text = "", AutoButtonColor = false, BackgroundColor3 = p.Rim, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size }, parent)
	HS.corner(b, p.R or 14)
	local face = HS.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(3.4, 1.6), Size = UDim2.new(1, -6.8, 1, -7) }, b)
	HS.corner(face, (p.R or 14) - 2)
	HS.new("UIGradient", { Rotation = 90, Color = CS(p.Top0, p.Top1) }, face)
	HS.new("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, Position = O(5, 2), Size = UDim2.new(1, -10, 0.4, 0) }, face)
	local t = HS.text(b, { Name = "Label", Text = p.Text, TextSize = p.TextSize or 28, Stroke = 2.6, StrokeColor = p.Ink, Position = O(0, -2), Size = S(1, 1), ZIndex = 4 })
	HS.press(b, p.OnClick, { Hover = 1.06, Press = 0.94, Sound = p.Sound })
	return b, t
end

function Unbox:_build()
	local HS = self.HS
	local gui = HS.new("ScreenGui", { Name = "UnboxHS", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 40, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Dim = HS.new("Frame", { Name = "Dim", BackgroundColor3 = RGB(6, 2, 14), BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 1 }, gui)

	-- full-screen reveal stage: violet vignette, rotating rarity rays, soft halo
	local stage = HS.new("Frame", { Name = "Stage", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 2, Visible = false }, gui)
	HS.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, P.Stage1), CK(0.42, P.Stage0), CK(1, P.Stage1) }) }, stage)
	self.Stage = stage
	self.Rays = {}
	self.Halo = HS.new("Frame", { Name = "Halo", BackgroundTransparency = 1, Visible = false }, stage)
	local aura = HS.new("Frame", { Name = "Aura", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.435), Size = S(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeYY }, stage)
	self.Aura, self.AuraPop, self.AL = aura, HS.new("UIScale", {}, aura), {}
	for _, d in { { "Bloom", AURA.Bloom, 1.45 }, { "RaysB", AURA.RaysB, 1.8 }, { "RaysA", AURA.RaysA, 1.7 }, { "Ring", AURA.Ring, 0.95 }, { "Bokeh", AURA.Bokeh, 1.35 }, { "Core", AURA.Bloom, 0.5 } } do
		local name, img, size = d[1], d[2], d[3]
		self.AL[name] = HS.new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = "rbxassetid://" .. img, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(size, size) }, aura)
	end

	-- design canvas (1920x1080, scaled to fit)
	local root = HS.new("Frame", { Name = "Root", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(DW, DH), ZIndex = 5 }, gui)
	self.RootScale = HS.new("UIScale", {}, root)
	self.Root = root

	---------------------------------------------------------------- reel panel
	local glow = HS.new("Frame", { Name = "Glow", AnchorPoint = V2(0.5, 0.5), Position = O(DW / 2, DH / 2 + 10), Size = O(PW + 18, PH + 18), BackgroundTransparency = 1 }, root)
	HS.corner(glow, 30)
	HS.stroke(glow, 10, P.Glow, 0.72)
	local panel = HS.new("Frame", { Name = "Panel", AnchorPoint = V2(0.5, 0.5), Position = O(DW / 2, DH / 2 + 10), Size = O(PW, PH), BackgroundColor3 = P.Panel, BorderSizePixel = 0 }, root)
	HS.corner(panel, 22)
	HS.stroke(panel, 4, P.Edge)
	self.PanelPop = HS.new("UIScale", {}, panel)
	self.Panel, self.Glow = panel, glow
	local stripes = HS.new("Frame", { Name = "Stripes", BackgroundColor3 = P.Deep, BorderSizePixel = 0, Size = S(1, 1) }, panel)
	HS.corner(stripes, 22)
	local kp = {}
	for k = 0, 12 do
		table.insert(kp, NK(k / 12, if k % 2 == 0 then 1 else 0.55))
	end
	HS.new("UIGradient", { Rotation = 28, Transparency = NS(kp) }, stripes)

	-- crate tab straddling the top edge
	local tab = HS.new("Frame", { Name = "Tab", AnchorPoint = V2(0.5, 0.5), Position = O(PW / 2, 0), Size = O(430, 62), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	HS.corner(tab, 16)
	HS.stroke(tab, 4, P.Ink)
	HS.new("UIGradient", { Rotation = 90, Color = CS(RGB(176, 110, 255), RGB(112, 48, 214)) }, tab)
	self.TabArt = HS.new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0, 0.5), Position = O(8, 29), Size = O(84, 66) }, tab)
	self.Title = HS.text(tab, { Name = "Title", Text = "", TextSize = 34, Stroke = 3.2, StrokeColor = P.Ink, X = Enum.TextXAlignment.Left, Position = O(98, 4), Size = O(316, 54) })

	self.Status = HS.text(panel, { Name = "Status", Text = "", TextSize = 24, Font = HS.MontX, Color = P.Muted, Stroke = 2.4, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0), Position = O(PW / 2, 44), Size = O(PW - 60, 32) })

	local win = HS.new("Frame", { Name = "Window", AnchorPoint = V2(0.5, 0), Position = O(PW / 2, 84), Size = O(WW, WH), BackgroundColor3 = P.Ink, BorderSizePixel = 0, ClipsDescendants = true }, panel)
	HS.corner(win, 14)
	HS.stroke(win, 3, P.Rim)
	self.Strip = HS.new("Frame", { Name = "Strip", BackgroundTransparency = 1, Position = O(0, (WH - CH) / 2), Size = O(N * PITCH, CH), ZIndex = 1 }, win)
	for side = 0, 1 do
		local f = HS.new("Frame", { Name = "Fade" .. side, BackgroundColor3 = P.Ink, BorderSizePixel = 0, AnchorPoint = V2(side, 0), Position = S(side, 0), Size = UDim2.new(0, 170, 1, 0), ZIndex = 3 }, win)
		HS.new("UIGradient", { Transparency = if side == 0 then NS(0, 1) else NS(1, 0) }, f)
	end

	-- cyan marker: glow + line + two diamonds (sits outside the clipped window)
	local mk = HS.new("Frame", { Name = "Marker", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = O(PW / 2, 84 - 14), Size = O(30, WH + 28) }, panel)
	self.MarkGlow = HS.new("Frame", { Name = "LineGlow", AnchorPoint = V2(0.5, 0), Position = O(15, 10), Size = O(16, WH + 8), BackgroundColor3 = P.Cyan, BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 1 }, mk)
	self.MarkLine = HS.new("Frame", { Name = "Line", AnchorPoint = V2(0.5, 0), Position = O(15, 10), Size = O(4, WH + 8), BackgroundColor3 = P.Cyan, BorderSizePixel = 0, ZIndex = 2 }, mk)
	self.MarkTips = {}
	for k, y in { 0, 1 } do
		local d = HS.new("Frame", { Name = "Tip" .. k, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, 15, y, if y == 0 then 8 else -8), Size = O(20, 20), Rotation = 45, BackgroundColor3 = P.Cyan, BorderSizePixel = 0, ZIndex = 3 }, mk)
		HS.stroke(d, 3, P.Ink)
		self.MarkTips[k] = d
	end

	self.Hint = HS.text(panel, { Name = "Hint", Text = "", TextSize = 22, Font = HS.MontX, Color = P.Muted, Stroke = 2, StrokeColor = P.Ink, X = Enum.TextXAlignment.Left, Position = O(40, 292), Size = O(520, 48) })
	self.Skip = self:_pill(panel, { Name = "Skip", Text = "SKIP", TextSize = 28, AnchorPoint = V2(1, 0), Position = O(PW - 40, 288), Size = O(150, 56), Rim = RGB(14, 70, 104), Top0 = RGB(120, 236, 255), Top1 = RGB(40, 170, 236), Ink = RGB(8, 40, 64), OnClick = function()
		self:_skip()
	end })

	---------------------------------------------------------------- reveal
	local rv = HS.new("Frame", { Name = "Reveal", BackgroundTransparency = 1, Size = S(1, 1), Visible = false }, root)
	self.RevealUI = rv
	local band = HS.new("Frame", { Name = "Band", AnchorPoint = V2(0.5, 0.5), Position = O(DW / 2, BAND_Y), Size = O(9000, BAND_H), BackgroundColor3 = P.Ink, BackgroundTransparency = 0.1, BorderSizePixel = 0, ClipsDescendants = true }, rv)
	self.Band = band
	self.RailFrames = {}
	for k, y in { 0, 1 } do
		local rail = HS.new("Frame", { Name = "Rail" .. k, AnchorPoint = V2(0.5, y), Position = UDim2.new(0.5, 0, y, 0), Size = O(2600, 5), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, band)
		HS.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.18, 0.15), NK(0.5, 0), NK(0.82, 0.15), NK(1, 1) }) }, rail)
		self.RailFrames[k] = rail
	end
	self.NameLbl = HS.text(band, { Name = "Name", Text = "", TextSize = 62, Stroke = 4, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = O(1300, 70), ZIndex = 4 })
	self.NameGrad = HS.new("UIGradient", { Rotation = 90 }, self.NameLbl)
	local tierRow = HS.new("Frame", { Name = "TierRow", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80), Size = O(1300, 40), ZIndex = 4 }, band)
	HS.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, tierRow)
	local function seg(name, order)
		local t = HS.new("TextLabel", { Name = name, LayoutOrder = order, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 40), Text = "", FontFace = HS.MontX, TextSize = 32, TextColor3 = WHITE, ZIndex = 5 }, tierRow)
		HS.stroke(t, 3, P.Ink)
		return t
	end
	self.TierWord, self.TierSep, self.TierWpn = seg("Rarity", 1), seg("Sep", 2), seg("Weapon", 3)
	self.TierSep.Text = "·"
	self.TierGrad = HS.new("UIGradient", {}, self.TierWord)
	self.DragHint = HS.text(rv, { Name = "DragHint", Text = "Drag to rotate", TextSize = 20, Font = HS.MontX, Color = P.Muted, Stroke = 2, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0), Position = O(DW / 2, 700), Size = O(400, 26) })
	self.TierLbl = HS.text(band, { Name = "TierOld", Visible = false, Text = "", TextSize = 32, Rich = true, Font = HS.MontX, Stroke = 3, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80), Size = O(1300, 40), ZIndex = 4 })

	self.TopLbl = HS.text(rv, { Name = "Top", Text = "", TextSize = 30, Font = HS.MontX, Color = P.Muted, Stroke = 2.6, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0), Position = O(DW / 2, 36), Size = O(1000, 40) })
	self.Row = HS.new("Frame", { Name = "Row", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = O(DW / 2, 92), Size = O(5 * PITCH - GAP, CH) }, rv)
	self.Slam = HS.text(rv, { Name = "Slam", Text = "", TextSize = 100, Stroke = 7, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0.5), Position = O(DW / 2, 450), Size = O(800, 120), Fit = false, ZIndex = 1 })
	self.SlamStroke = self.Slam:FindFirstChildOfClass("UIStroke")
	self.SlamPop = HS.new("UIScale", {}, self.Slam)
	self.SlamGrad = HS.new("UIGradient", { Enabled = false }, self.Slam)
	local holder = HS.new("Frame", { Name = "GunHolder", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(DW / 2, 470), Size = O(1100, 560), ZIndex = 2 }, rv)
	self.VPPop = HS.new("UIScale", {}, holder)
	-- 2026-11-18: lock tag over the gun when the skin's gun isn't unlocked yet
	local lt = HS.new("Frame", { Name = "LockTag", Visible = false, AnchorPoint = V2(0.5, 0.5), Position = O(DW / 2, 240), Size = O(470, 64), BackgroundColor3 = Color3.fromRGB(26, 18, 10), BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 6 }, rv)
	HS.corner(lt, 32)
	HS.new("UIStroke", { Thickness = 3, Color = LOCK_COL }, lt)
	local ic = HS.new("Frame", { Name = "IconHolder", BackgroundTransparency = 1, AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = O(44, 44), ZIndex = 7 }, lt)
	lockIcon(HS, ic, 40, LOCK_COL, 7)
	self.LockTagText = HS.text(lt, { Name = "Label", Text = "GUN NOT UNLOCKED YET", TextSize = 28, Font = HS.MontX, Color = LOCK_COL, Stroke = 2.4, StrokeColor = P.Ink, AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 66, 0.5, 0), Size = UDim2.new(1, -80, 0, 34), ZIndex = 7 })
	self.LockTag = lt
	self.GlowVP = {}
	for i, sc in { 1.08, 1.035 } do
		local g = HS.new("ViewportFrame", { Name = "Glow" .. i, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(sc, sc), LightColor = Color3.new(0, 0, 0), ImageTransparency = 1, ZIndex = 1 }, holder)
		self.GlowVP[i] = { F = g, Base = sc }
	end
	self.VP = HS.new("ViewportFrame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), ZIndex = 2 }, holder)
	self.Info = HS.text(rv, { Name = "Info", Text = "", TextSize = 30, Font = HS.MontX, Stroke = 2.8, StrokeColor = P.Ink, AnchorPoint = V2(0.5, 0), Position = O(DW / 2, 884), Size = O(1100, 42) })
	self.CollectBtn = self:_pill(rv, { Name = "Collect", Text = "COLLECT", TextSize = 32, AnchorPoint = V2(1, 0), Position = O(DW / 2 - 14, 944), Size = O(250, 68), Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Ink = RGB(25, 45, 12), OnClick = function()
		self:Close()
	end })
	self.EquipBtn, self.EquipLbl = self:_pill(rv, { Name = "Equip", Text = "EQUIP", TextSize = 32, Position = O(DW / 2 + 14, 944), Size = O(250, 68), Rim = RGB(14, 70, 104), Top0 = RGB(120, 236, 255), Top1 = RGB(40, 170, 236), Ink = RGB(8, 40, 64), OnClick = function()
		self:_equip()
	end })

	self.FX = HS.new("Frame", { Name = "FX", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 8 }, gui)
	self.Parts = {}
	self.Flash = HS.new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 10 }, gui)
end

function Unbox:_card(parent, i, e, x)
	local HS = self.HS
	local col = tierColor(e.Rarity)
	local f = HS.new("Frame", { Name = "C" .. i, Position = O(x, 0), Size = O(CW, CH), BackgroundColor3 = P.Card, BorderSizePixel = 0 }, parent)
	HS.corner(f, 12)
	local tint = HS.new("Frame", { Name = "Tint", BackgroundColor3 = col, BorderSizePixel = 0, Size = S(1, 1) }, f)
	HS.corner(tint, 12)
	HS.new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.92), NK(0.55, 0.8), NK(1, 0.3) }) }, tint)
	local st = self:_rs(f, 3, col)
	local cdef = CHROMA_T[e.Rarity]
	if cdef and cdef.Grad then
		st.Color = WHITE
		HS.new("UIGradient", { Color = cdef.Grad }, st)
	end
	local img = HS.new("ImageLabel", { Name = "Skin", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = O(CW - 16, CW - 22) }, f)
	local ok, pv = pcall(Config.Preview, e.Key)
	if ok and pv and pv.Image then
		img.Image = pv.Image
		if pv.Offset then img.ImageRectOffset = pv.Offset end
		if pv.Size then img.ImageRectSize = pv.Size end
	elseif e.Kind == "Equipment" or e.Weapon == "Equipment" or e.Kind == "Weapon" then
		-- equipment and Arsenal guns have no card render: a small 3D view of the item / gun (factory finish)
		local okm, m, size
		if e.Kind == "Weapon" then
			okm, m, size = pcall(K.weapon, e.Weapon, e.Skin)
		else
			okm, m, size = pcall(K.weapon, "Equipment", e.Id or e.Skin)
		end
		if okm and m and size then
			local vp = HS.new("ViewportFrame", { Name = "Equip3D", BackgroundTransparency = 1, AnchorPoint = img.AnchorPoint, Position = img.Position, Size = img.Size, ZIndex = img.ZIndex }, f)
			K.view(vp, m, size, { Fov = 22, Pad = 1.15 })
		end
	end
	local nm = HS.text(f, { Name = "Name", Text = e.Name or "", TextSize = 16, Position = O(5, CH - 42), Size = O(CW - 10, 22) })
	self:_rs(nm, 2, P.Ink)
	local bar = HS.new("Frame", { Name = "Bar", BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 6) }, f)
	HS.corner(bar, 3)
	local shade = HS.new("Frame", { Name = "Shade", BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 5 }, f)
	HS.corner(shade, 12)
	return f
end

-- cosmetic reel weighted like the crate (every rarity shows up); the winner slot is filled from the server result
function Unbox:_pick()
	local crate = self.Crate
	local pool = Config.Pool(crate)
	if not self.PickTiers then
		local tiers, total = {}, 0
		for _, t in Config.Tiers do
			local w = crate.Odds and crate.Odds[t]
			if w and pool.ByTier[t] and #pool.ByTier[t] > 0 then
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

function Unbox:_put(i, e)
	local old = self.Cards[i]
	if old then old.F:Destroy() end
	self.Cards[i] = { F = self:_card(self.Strip, i, e, (i - 1) * PITCH), E = e }
end

function Unbox:_placeWinner()
	local res = self.Result
	self:_put(WIN, { Weapon = res.Weapon, Skin = res.Skin, Rarity = res.Rarity, Name = res.Name, Key = res.Key or (res.Weapon .. "/" .. res.Skin), Kind = res.Kind, Id = res.Id })
	-- near miss: a top-tier card right after the winner when the winner is lower
	if tierIndex(res.Rarity) < 5 then
		local pool = Config.Pool(self.Crate)
		local top = pool.ByTier[if pool.ByTier.Godly and #pool.ByTier.Godly > 0 then "Godly" else "Legendary"]
		if top and #top > 0 then
			self:_put(WIN + 1, top[math.random(1, #top)])
		end
	end
end

function Unbox:Play(crate, opts)
	if self.Active or not crate then return end
	local HS = self.HS
	opts = opts or {}
	self.Active, self.Crate, self.Opts, self.Result = true, crate, opts, nil
	self.Phase, self.Spin, self.Gun, self.GunBase = "Reel", nil, nil, nil
	self.Token += 1
	local tok = self.Token
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(DW, DH)
	self.Sc = math.min(vp.X / DW, vp.Y / DH)
	self.RootScale.Scale = self.Sc

	task.spawn(function()
		local ok, res = pcall(function()
			return Remotes:WaitForChild("CrateOpen", 5):InvokeServer(crate.Id, opts.Count or 1)
		end)
		if tok ~= self.Token then return end
		self.Result = if ok and type(res) == "table" then res else { Ok = false, Error = "No connection" }
	end)

	-- reset
	self.Dim.Visible, self.Stage.Visible, self.RevealUI.Visible = true, false, false
	self.Panel.Visible, self.Glow.Visible, self.Skip.Visible = true, true, true
	self.Flash.BackgroundTransparency = 1
	self.Dim.BackgroundTransparency = 1
	HS.tween(self.Dim, 0.25, { BackgroundTransparency = 0.3 })
	for _, o in { self.MarkLine, self.MarkGlow, self.MarkTips[1], self.MarkTips[2] } do
		o.BackgroundColor3 = P.Cyan
	end
	self.Title.Text = string.upper(crate.Name or "Crate")
	self.TabArt.Image = (crate.Art and crate.Art.Full) or ""
	self.Status.TextColor3 = P.Muted
	self.Status.Text = "Decrypting drop..."
	local count = opts.Count or 1
	self.Hint.Text = if count > 1 then string.format("Opening %d crates · best drop is shown", count) else "Space to skip"

	self.Strip:ClearAllChildren()
	self.Cards, self.PickTiers = {}, nil
	for i = 1, N do
		self:_put(i, self:_pick())
	end
	self.Strip.Position = O(WW / 2 - CW / 2 - 2 * PITCH, (WH - CH) / 2)
	self.Gui.Enabled = true
	self.PanelPop.Scale = 0.86
	HS.tween(self.PanelPop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	self:_sfx("Whoosh", 1.1, 0.7)

	task.spawn(function()
		local t0 = os.clock()
		while not self.Result and os.clock() - t0 < 10 and tok == self.Token do
			task.wait()
		end
		if tok ~= self.Token then return end
		local res = self.Result
		if not (res and res.Ok) then
			HS.sound("Deny")
			self.Status.TextColor3 = RGB(255, 110, 110)
			self.Status.Text = (res and res.Error) or "Could not open"
			self.Skip.Visible = false
			task.delay(1.6, function()
				if tok == self.Token then self:Close() end
			end)
			return
		end
		self:_placeWinner()
		self:_spin(tok)
	end)
end

function Unbox:_spin(tok)
	local res = self.Result
	local dur = if self.Opts.Fast then 1.6 else (SPIN[res.Rarity] or 5)
	local jitter = (math.random() - 0.5) * CW * 0.7
	local x0 = WW / 2 - CW / 2 - 2 * PITCH
	local x1 = WW / 2 - ((WIN - 1) * PITCH + CW / 2) - jitter
	self.Spin = { T = os.clock(), D = dur, X0 = x0, X1 = x1, Tok = tok }
	self.Status.Text = "Rolling..."
	if tierIndex(res.Rarity) >= 4 and not self.Opts.Fast then
		self:_sfx("Riser", 1, 1)
	end
end

function Unbox:_skip()
	if self.Phase ~= "Reel" then return end
	if self.Spin then
		self.Spin.T = os.clock() - self.Spin.D
	else
		self.Opts.Fast = true
	end
end

function Unbox:_land(tok)
	local HS, res = self.HS, self.Result
	local col = tierColor(res.Rarity)
	local fx = FXT[tierIndex(res.Rarity)] or FXT[1]
	self.Phase = "Locked"
	self:_sfx("Lock", 1, 1)
	local cx = WW / 2 - ((WIN - 1) * PITCH + CW / 2)
	HS.tween(self.Strip, 0.35, { Position = O(cx, (WH - CH) / 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, c in self.Cards do
		if i ~= WIN then
			local sh = c.F:FindFirstChild("Shade")
			if sh then HS.tween(sh, 0.3, { BackgroundTransparency = 0.6 }) end
		end
	end
	local pop = HS.new("UIScale", {}, self.Cards[WIN].F)
	HS.tween(pop, 0.35, { Scale = 1.08 }, Enum.EasingStyle.Back)
	for _, o in { self.MarkLine, self.MarkGlow, self.MarkTips[1], self.MarkTips[2] } do
		HS.tween(o, 0.25, { BackgroundColor3 = col })
	end
	self.Status.Text = string.upper(res.Rarity) .. "!"
	self.Status.TextColor3 = col:Lerp(WHITE, 0.25)
	self.Skip.Visible = false
	local fast = self.Opts.Fast
	task.delay(if fast then 0.45 else 0.8, function()
		if tok ~= self.Token then return end
		if fx.Charge > 0 then
			local d = fx.Charge * (if fast then 0.6 else 1)
			self:_charge(col, d, fx)
			task.delay(d, function()
				if tok == self.Token then self:_reveal() end
			end)
		else
			self:_reveal()
		end
	end)
end

function Unbox:_row(res)
	local HS = self.HS
	self.Row:ClearAllChildren()
	for i, r in res.Results do
		local f = self:_card(self.Row, i, { Weapon = r.Weapon, Skin = r.Skin, Rarity = r.Rarity, Name = r.Name, Key = r.Key or (r.Weapon .. "/" .. r.Skin), Kind = r.Kind, Id = r.Id }, (i - 1) * PITCH)
		if r.GunLocked then -- 2026-11-18: this skin's gun isn't unlocked yet
			local b = HS.new("Frame", { Name = "Lock", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = O(34, 34), BackgroundColor3 = Color3.fromRGB(26, 18, 10), BorderSizePixel = 0, ZIndex = 8 }, f)
			HS.corner(b, 17)
			HS.new("UIStroke", { Thickness = 2, Color = LOCK_COL }, b)
			lockIcon(HS, b, 24, LOCK_COL, 9)
		end
		local sc = HS.new("UIScale", { Scale = 0 }, f)
		task.delay(0.15 + i * 0.08, function()
			HS.tween(sc, 0.3, { Scale = if i == res.Best then 1.08 else 0.94 }, Enum.EasingStyle.Back)
		end)
		if i == res.Best then
			local tag = HS.new("Frame", { Name = "Best", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Size = O(70, 24), BackgroundColor3 = P.Gold, BorderSizePixel = 0, ZIndex = 6 }, f)
			HS.corner(tag, 8)
			self:_rs(tag, 2, P.Ink)
			HS.text(tag, { Text = "BEST", TextSize = 16, Color = P.Ink, Size = S(1, 1), ZIndex = 7 })
		elseif r.Dup then
			f.Shade.BackgroundTransparency = 0.45
		end
	end
end

function Unbox:_reveal()
	local HS, res = self.HS, self.Result
	local col = tierColor(res.Rarity)
	local ti = tierIndex(res.Rarity)
	local fx = FXT[ti] or FXT[1]
	self.Phase = "Reveal"
	self.RevealT = os.clock()
	self.Charge = nil
	self.FXCur, self.Col, self.EmberAcc, self.StarAcc = fx, col, 0, 0
	self.RaySpeed = 8 + ti * 6

	-- impact: rarity flash, shockwaves, spark burst, shake
	self.Flash.BackgroundColor3 = if ti >= 3 then col:Lerp(WHITE, 0.55) else WHITE
	self.Flash.BackgroundTransparency = 0
	HS.tween(self.Flash, 0.45 + ti * 0.08, { BackgroundTransparency = 1 })
	self.ShakeAmt = fx.Shake * self.Sc
	self.Panel.Visible, self.Glow.Visible, self.Dim.Visible = false, false, false
	self.Stage.Visible, self.RevealUI.Visible = true, true
	for i, r in self.Rays do
		r.F.BackgroundColor3 = if fx.Rainbow then Color3.fromHSV((i - 1) / #self.Rays, 0.55, 1) else col:Lerp(WHITE, 0.15)
		r.F.BackgroundTransparency = math.max(0.05, 0.5 - ti * 0.08)
		r.F.Rotation = r.A
	end
	self.Halo.BackgroundColor3 = col
	self:_aura(col, ti, fx)
	for _, r in self.RailFrames do
		r.BackgroundColor3 = col
	end
	for k = 1, fx.Rings do
		self:_shock(if fx.Rainbow then Color3.fromHSV(k / 3, 0.6, 1) else col:Lerp(WHITE, 0.2 * (k - 1)), (k - 1) * 0.14, 1.3 + k * 0.25)
	end
	self:_burst(fx.Burst, col, fx.Rainbow)

	-- giant rarity slam behind the gun (Mythic+)
	if fx.Slam then
		self.Slam.Text = string.upper(res.Rarity) .. "!"
		self.Slam.TextColor3 = if fx.Rainbow then WHITE else col:Lerp(WHITE, 0.15)
		self.SlamGrad.Enabled = fx.Rainbow == true
		if fx.Rainbow then self.SlamGrad.Color = (CHROMA_T[res.Rarity] and CHROMA_T[res.Rarity].Grad) or K.CHROMA end
		self.Slam.TextTransparency = 0
		if self.SlamStroke then self.SlamStroke.Transparency = 0 end
		self.SlamPop.Scale = 6
		HS.tween(self.SlamPop, 0.3, { Scale = 2.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.9, function()
			if self.Phase ~= "Reveal" then return end
			HS.tween(self.Slam, 0.6, { TextTransparency = 0.8 })
			if self.SlamStroke then HS.tween(self.SlamStroke, 0.6, { Transparency = 0.92 }) end
		end)
	else
		self.Slam.Text = ""
	end

	-- 3D stage (sharp, lit, real particles); ViewportFrame only as a fallback
	self.VP:ClearAllChildren()
	for _, g in self.GlowVP do g.F:ClearAllChildren() g.F.ImageTransparency = 1 end
	self.Gun, self.GunBase, self.GlowModels = nil, nil, {}
	self.DragHint.Visible = false
	if self:_stage3D(res, col, ti, fx) then
		self.DragHint.Visible = true
	else
	self.VP:ClearAllChildren()
	for _, g in self.GlowVP do
		g.F:ClearAllChildren()
		g.F.ImageTransparency = 1
	end
	self.Gun, self.GunBase, self.GlowModels = nil, nil, {}
	local ok, m, size = pcall(K.weapon, res.Weapon, res.Skin)
	if ok and m and size then
		local cam = K.view(self.VP, m, size, { Tilt = 10, Aspect = 1100 / 560, Pad = 1.4, Fov = 22, Ambient = RGB(170, 160, 200) })
		self.Gun, self.GunBase = m, m:GetPivot()
		if fx.Glow < 1 and cam then
			for i, g in self.GlowVP do
				local c = m:Clone()
				silhouette(c)
				c.Parent = g.F
				local gc = cam:Clone()
				gc.Parent = g.F
				g.F.CurrentCamera = gc
				g.F.Ambient = col
				g.F.LightColor = Color3.new(0, 0, 0)
				g.F.ImageTransparency = fx.Glow + (if i == 1 then 0.45 else 0.22)
				self.GlowModels[i] = c
			end
		end
	end
	self.VPPop.Scale = 0.5
	HS.tween(self.VPPop, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- name band opens from its centre line, name pops
	self.NameLbl.Text = (res.Name or res.Skin or "") .. (if res.Kind == "Equipment" and not res.Unlocked and not res.Dup then " Shard" else "")
	self:_tierText(res, col)
	self.Band.Size = O(9000, 0)
	HS.tween(self.Band, 0.4, { Size = O(9000, BAND_H) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local np = self.NameLbl:FindFirstChild("Pop") or HS.new("UIScale", { Name = "Pop" }, self.NameLbl)
	np.Scale = 1.6
	HS.tween(np, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	if res.Results and #res.Results > 1 then
		local new, refund = 0, 0
		for _, r in res.Results do
			if r.Dup then refund += r.Refund or 0 else new += 1 end
		end
		if res.Results[1].Kind == "Weapon" then
			self.Info.Text = string.format("%d new guns unlocked for your loadout", new)
		elseif res.Results[1].Kind == "Equipment" then
			local un = 0
			for _, r in res.Results do
				if r.Unlocked then un += 1 end
			end
			self.Info.Text = string.format("%d shards · %d unlocked%s", #res.Results, un, if refund > 0 then " · +" .. num(refund) .. " REQ refunded" else "")
		else
			local lk = 0
			for _, r in res.Results do if r.GunLocked then lk += 1 end end
			self.Info.Text = string.format("%d drops · %d new%s%s", #res.Results, new, if refund > 0 then " · +" .. num(refund) .. " REQ refunded" else "",
				if lk > 0 then string.format(" · %d for a gun you haven't unlocked", lk) else "")
		end
		self.Info.TextColor3 = WHITE
		self.TopLbl.Text = "BEST OF " .. #res.Results
		self:_row(res)
	else
		self.Row:ClearAllChildren()
		if res.Kind == "Weapon" and res.Dup then
			self.Info.Text = "You already own every gun · +" .. num(res.RefundOrd or 0) .. " ORD refunded"
			self.Info.TextColor3 = P.Gold
		elseif res.Kind == "Weapon" then
			self.Info.Text = if (res.Left or 0) > 0 then string.format("NEW GUN! Unlocked for your loadout · %d still locked", res.Left) else "NEW GUN! You now own every gun"
			self.Info.TextColor3 = P.Green
		elseif res.GunLocked and not res.Dup then
			local gun = string.upper(tostring(res.Weapon or "gun"))
			self.Info.Text = "Saved to your inventory · unlock the " .. gun .. " (Arsenal Crate) to use it"
			self.Info.TextColor3 = LOCK_COL
		elseif res.Dup then
			self.Info.Text = "Already owned · +" .. num(res.Refund or 0) .. " REQ refunded"
			self.Info.TextColor3 = P.Gold
		elseif res.Kind == "Equipment" and not res.Unlocked then
			local need, have = res.Need or 3, res.Shards or 1
			self.Info.Text = string.format("+1 SHARD · %d/%d · %d more to unlock", have, need, need - have)
			self.Info.TextColor3 = P.Cyan
		elseif res.Kind == "Equipment" then
			self.Info.Text = string.format("%d/%d SHARDS · UNLOCKED! Added to your inventory", res.Need or 3, res.Need or 3)
			self.Info.TextColor3 = P.Green
		else
			self.Info.Text = "NEW! Added to your inventory"
			self.Info.TextColor3 = P.Green
		end
		self.TopLbl.Text = if res.Kind == "Weapon" then "NEW GUN UNLOCKED" else string.upper(self.Crate.Name or "Crate") .. (if res.Kind == "Equipment" then " SHARD" else " UNLOCKED")
	end
	local lockedShard = res.Kind == "Equipment" and not res.Unlocked and not res.Dup
	local lockedGun = res.GunLocked == true -- 2026-11-18: the skin's gun isn't unlocked yet
	self.EquipLbl.Text = if lockedShard or lockedGun then "LOCKED" else "EQUIP"
	self.EquipBtn:SetAttribute("Disabled", lockedShard or lockedGun)
	if self.LockTag then
		self.LockTag.Visible = lockedGun
		if lockedGun then
			self.LockTagText.Text = string.upper(tostring(res.Weapon or "GUN")) .. " NOT UNLOCKED YET"
			local sc = self.LockTag:FindFirstChild("Pop") or HS.new("UIScale", { Name = "Pop" }, self.LockTag)
			sc.Scale = 0.4
			HS.tween(sc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	-- sound scales with tier
	self:_sfx("Hit", if ti >= 3 then 0.8 else 1, 1)
	self:_sfx("Shimmer", 1, 1)
	if ti >= 2 then self:_sfx("Land", 0.9, 1) end
	if ti >= 3 then self:_sfx("Break", 0.9, 1) self:_sfx("Swell", 1, 1) end
	if ti >= 5 then
		task.delay(0.25, function() if self.Phase == "Reveal" then self:_sfx("Shimmer", 1.25, 1) end end)
	end
end

function Unbox:_pt(x, y)
	local a = self.Gui.AbsoluteSize
	return a.X / 2 + (x - DW / 2) * self.Sc, a.Y / 2 + (y - DH / 2) * self.Sc
end

function Unbox:_part(p)
	if #self.Parts > 600 then return end
	local f = Instance.new("Frame")
	f.AnchorPoint, f.BorderSizePixel, f.BackgroundColor3 = V2(0.5, 0.5), 0, p.Col
	f.Position = O(p.X, p.Y)
	if p.Star then
		f.Rotation = 45
		f.Size = O(0, 0)
	elseif p.Streak then
		f.Size = O(p.Size * 3, math.max(2, p.Size * 0.45))
	else
		f.Size = O(p.Size, p.Size)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	f.Parent = self.FX
	table.insert(self.Parts, { F = f, X = p.X, Y = p.Y, VX = p.VX or 0, VY = p.VY or 0, T = 0, L = p.Life, G = p.Grav or 0, D = p.Drag or 0, Streak = p.Streak, Star = p.Star, Sz = p.Size })
end

function Unbox:_pcol(col, rainbow)
	if rainbow then return Color3.fromHSV(math.random(), 0.6, 1) end
	return col:Lerp(WHITE, math.random() * 0.55)
end

function Unbox:_burst(n, col, rainbow)
	local cx, cy = self:_pt(DW / 2, 470)
	local sc = self.Sc
	for _ = 1, n do
		local a = math.random() * math.pi * 2
		local sp = (450 + math.random() * 1300) * sc
		local streak = math.random() < 0.7
		self:_part({ X = cx, Y = cy, VX = math.cos(a) * sp, VY = math.sin(a) * sp, Life = 0.55 + math.random() * 0.8, Size = (if streak then 7 else 5 + math.random() * 9) * sc, Col = self:_pcol(col, rainbow), Streak = streak, Drag = 2.6, Grav = 500 * sc })
	end
end

function Unbox:_ring(col, x, y, th)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.BackgroundTransparency, f.Size = V2(0.5, 0.5), 1, O(0, 0)
	f.Position = O(x, y)
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0.5, 0)
	cr.Parent = f
	local st = Instance.new("UIStroke")
	st.Color, st.Thickness = col, th
	st.Parent = f
	f.Parent = self.FX
	return f, st
end

function Unbox:_shock(col, delay, big)
	task.delay(delay or 0, function()
		if self.Phase ~= "Reveal" then return end
		local cx, cy = self:_pt(DW / 2, 470)
		local W = self.Gui.AbsoluteSize.X * (big or 1.5)
		local f, st = self:_ring(col, cx, cy, 26 * self.Sc)
		self.HS.tween(f, 0.75, { Size = O(W, W) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		self.HS.tween(st, 0.75, { Thickness = 2, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.8, function() f:Destroy() end)
	end)
end

-- Mythic+: the screen darkens, sparks are pulled into the panel, a rarity ring closes in, shake builds
function Unbox:_charge(col, d, fx)
	local HS = self.HS
	self.Charge = { T = os.clock(), D = d, Col = col, Shake = fx.Shake, Rainbow = fx.Rainbow, Acc = 0 }
	self:_sfx("Riser", 1.1, 1.2)
	HS.tween(self.Dim, d, { BackgroundTransparency = 0.04 })
	self.Status.Text = "..."
	local cx, cy = self:_pt(DW / 2, DH / 2 + 10)
	local W = self.Gui.AbsoluteSize.X * 1.3
	local f, st = self:_ring(col, cx, cy, 10 * self.Sc)
	f.Size, st.Transparency = O(W, W), 0.8
	HS.tween(f, d, { Size = O(PW * 0.5 * self.Sc, PW * 0.5 * self.Sc) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	HS.tween(st, d, { Transparency = 0, Thickness = 22 * self.Sc }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(d + 0.05, function() f:Destroy() end)
	local gs = self.Glow:FindFirstChildOfClass("UIStroke")
	if gs then HS.tween(gs, d, { Color = col, Transparency = 0.2 }) end
end

function Unbox:_aura(col, ti, fx)
	local L = self.AL
	local lite = col:Lerp(WHITE, 0.35)
	local dim = (1 - (ti - 1) / 5) * 0.35
	L.Bloom.ImageColor3, L.Bloom.ImageTransparency = col, 0.25 + dim
	L.RaysB.ImageColor3, L.RaysB.ImageTransparency = col, 0.45 + dim
	L.RaysA.ImageColor3, L.RaysA.ImageTransparency = lite, 0.2 + dim
	L.Ring.ImageColor3, L.Ring.ImageTransparency, L.Ring.Visible = lite, 0.1, ti >= 4
	L.Bokeh.ImageColor3, L.Bokeh.ImageTransparency = lite, 0.3 + dim
	L.Core.ImageColor3 = WHITE
	self.Aura.Position = UDim2.new(0.5, 0, 0.5, (470 - DH / 2) * self.Sc)
	self.AuraPop.Scale = 0.3
	self.HS.tween(self.AuraPop, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Unbox:_tierText(res, col)
	local ch = CHROMA_T[res.Rarity]
	self.TierWord.Text = string.upper(res.Rarity or "")
	self.TierWpn.Text = if res.Kind == "Weapon" then string.upper(tostring(res.Class or "GUN")) else string.upper(tostring(res.Weapon or ""))
	self.NameGrad.Offset, self.TierGrad.Offset = Vector2.zero, Vector2.zero
	if ch then
		self.NameGrad.Color, self.TierGrad.Color = ch.Grad, ch.Grad
		self.NameGrad.Rotation, self.TierGrad.Rotation = 0, 0
	else
		self.NameGrad.Color = CS(col:Lerp(WHITE, 0.6), col:Lerp(WHITE, 0.1))
		self.NameGrad.Rotation = 90
		self.TierGrad.Color = CS(col:Lerp(WHITE, 0.25), col:Lerp(WHITE, 0.25))
	end
	self.TextChroma = ch
end

local function stagePart(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do p[k] = v end
	p.Parent = parent
	return p
end

function Unbox:_stage3D(res, col, ti, fx)
	local cam = Workspace.CurrentCamera
	if not cam then return false end
	local ok, m, size = pcall(K.weapon, res.Weapon, res.Skin)
	if not (ok and m and size) then return false end
	self:_clear3D(true)
	local ch = CHROMA_T[res.Rarity]
	local vps = cam.ViewportSize
	local aspect = vps.X / math.max(vps.Y, 1)
	local fov = 30
	local tv = math.tan(math.rad(fov / 2))
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = math.max(maxDim / (tv * aspect), maxDim / (1.2 * tv))
	local hAt = 2 * dist * tv
	local focus = STAGE3 - Vector3.new(0, (0.5 - 470 / DH) * hAt, 0)
	self.Cam3 = { Focus = focus, Dist = dist, Fov = fov, Dolly = 0.55, K = hAt / math.max(vps.Y, 1) }

	local stage = Instance.new("Model")
	stage.Name = "UnboxStage"
	local bd = dist + 60
	local bh = 2 * bd * tv * 1.12
	local bw = bh * aspect * 1.04
	local bpos = focus - Vector3.new(0, 0, 60)
	local back = stagePart({ Name = "Backdrop", Size = Vector3.new(bw, bh, 0.2), CFrame = CFrame.lookAt(bpos, bpos + Vector3.new(0, 0, 1)), Color = P.Stage1, Material = Enum.Material.SmoothPlastic }, stage)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "UnboxBackdrop"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(1920, math.floor(1920 * bh / bw))
	sg.LightInfluence = 0
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Adornee = back
	sg.ResetOnSpawn = false
	local bg = Instance.new("Frame")
	bg.BackgroundColor3, bg.BorderSizePixel, bg.Size, bg.ZIndex = WHITE, 0, S(1, 1), 1
	local gr = Instance.new("UIGradient")
	gr.Rotation, gr.Color = 90, CS({ CK(0, P.Stage1), CK(0.44, P.Stage0), CK(1, P.Stage1) })
	gr.Parent = bg
	bg.Parent = sg
	local yc = 0.5 - (0.5 - 470 / DH) / 1.12
	self.Aura.Parent, self.Aura.Position, self.Aura.Size, self.Aura.ZIndex = sg, S(0.5, yc), S(1.12, 1.12), 2
	self.Slam.Parent, self.Slam.Position, self.Slam.ZIndex = sg, S(0.5, yc), 3
	sg.Parent = player:WaitForChild("PlayerGui")
	self.SG3 = sg

	m:PivotTo(m:GetPivot() + STAGE3)
	m.Parent = stage
	self.Gun3, self.Gun3Base = m, m:GetPivot()
	self.Rot = { Yaw = -2.6, Pitch = 0.18, V = 6, Drag = false, Last = os.clock(), T = os.clock() }
	if ti >= 2 then
		local h = Instance.new("Highlight")
		h.Adornee = m
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.OutlineColor = if ch then K.chromaColor(ch, 0, 0) else col:Lerp(WHITE, 0.2)
		h.OutlineTransparency = 0
		h.FillColor = col
		h.FillTransparency = if ti >= 3 then 0.84 else 1
		h.Parent = m
		self.Hl = h
	end

	local rig = stagePart({ Name = "Rig", Size = Vector3.new(size.X, size.Y, size.Z) * 1.25, CFrame = CFrame.new(STAGE3), Transparency = 1 }, stage)
	local function light(off, c, b, r)
		local a = Instance.new("Attachment")
		a.Position = off
		a.Parent = rig
		local L = Instance.new("PointLight")
		L.Color, L.Brightness, L.Range, L.Shadows = c, b, r, false
		L.Parent = a
	end
	light(Vector3.new(0, maxDim * 0.5, maxDim * 0.9), WHITE, 1.4, maxDim * 3)
	light(Vector3.new(-maxDim * 0.75, maxDim * 0.2, -maxDim * 0.4), col, 2 + ti * 0.6, maxDim * 2.2)
	light(Vector3.new(maxDim * 0.75, -maxDim * 0.1, -maxDim * 0.4), col:Lerp(WHITE, 0.3), 1.5 + ti * 0.5, maxDim * 2.2)
	local sz = maxDim / 7
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = if ch then ch.Grad else CS(col:Lerp(WHITE, 0.45), col)
	pe.LightEmission, pe.LightInfluence = 1, 0
	pe.Size = NS({ NK(0, sz), NK(0.6, sz * 0.6), NK(1, 0) })
	pe.Transparency = NS({ NK(0, 0.1), NK(0.7, 0.4), NK(1, 1) })
	pe.Lifetime = NumberRange.new(0.8, 1.8)
	pe.Speed = NumberRange.new(sz * 2, sz * 6)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Shape, pe.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
	pe.Rotation, pe.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-140, 140)
	pe.Drag = 1.5
	pe.Rate = fx.Stars * 3
	pe.Parent = rig
	stage.Parent = Workspace
	self.Stage3 = stage
	task.defer(function()
		if pe.Parent then pe:Emit(math.floor(fx.Burst / 3)) end
	end)
	if ti >= 3 then
		local bl = Instance.new("BloomEffect")
		bl.Intensity, bl.Size, bl.Threshold = 0.35 + ti * 0.05, 20, 0.9
		bl.Parent = cam
		self.Bloom3 = bl
	end

	self.SavedCam = self.SavedCam or { Type = cam.CameraType, CF = cam.CFrame, Fov = cam.FieldOfView, Subject = cam.CameraSubject }
	RunService:BindToRenderStep("UnboxCam", Enum.RenderPriority.Camera.Value + 10, function()
		local C3 = self.Cam3
		if not C3 then return end
		local c = Workspace.CurrentCamera
		c.CameraType = Enum.CameraType.Scriptable
		c.FieldOfView = C3.Fov
		local cf = CFrame.lookAt(C3.Focus + Vector3.new(0, 0, C3.Dist * (1 + C3.Dolly)), C3.Focus)
		local sh = self.ShakeAmt or 0
		if sh > 0.3 then
			cf *= CFrame.new((math.random() - 0.5) * 2 * sh * C3.K, (math.random() - 0.5) * 2 * sh * C3.K, 0)
		end
		c.CFrame = cf
	end)
	self.Stage.Visible = false
	return true
end

function Unbox:_clear3D(keepCam)
	pcall(RunService.UnbindFromRenderStep, RunService, "UnboxCam")
	self.Cam3 = nil
	if self.Stage3 then self.Stage3:Destroy() self.Stage3 = nil end
	if self.SG3 then
		self.Aura.Parent, self.Aura.Size, self.Aura.ZIndex = self.Stage, S(1, 1), 1
		self.Slam.Parent, self.Slam.Position, self.Slam.ZIndex = self.RevealUI, O(DW / 2, 450), 1
		self.SG3:Destroy()
		self.SG3 = nil
	end
	if self.Bloom3 then self.Bloom3:Destroy() self.Bloom3 = nil end
	self.Gun3, self.Gun3Base, self.Hl, self.Rot = nil, nil, nil, nil
	local sv = self.SavedCam
	if sv and not keepCam then
		local cam = Workspace.CurrentCamera
		cam.CameraType, cam.CFrame, cam.FieldOfView = sv.Type, sv.CF, sv.Fov
		if sv.Subject then cam.CameraSubject = sv.Subject end
		self.SavedCam = nil
	end
end

function Unbox:_equip()
	local r = self.Result
	if not (r and r.Ok) then return end
	if r.Kind == "Weapon" then
		-- put the new gun into the active preset: first slot holding a locked gun, else the BACKUP slot
		if not r.Unlocked then return end
		local Presets = require(Vantage:WaitForChild("Weapons"):WaitForChild("LoadoutPresets"))
		local lp = game:GetService("Players").LocalPlayer
		local idx = lp:GetAttribute("LoadoutActive")
		idx = if type(idx) == "number" then math.clamp(math.floor(idx), 1, Presets.Count) else 1
		local list = Presets.Decode(lp:GetAttribute("LoadoutPresets"))[idx] or {}
		local slot = table.find(list, r.Weapon)
		if not slot then
			for s2 = 1, Presets.Slots do
				if not Presets.Owns(lp, list[s2]) then slot = s2 break end
			end
		end
		slot = slot or Presets.Slots
		local ev = Remotes:FindFirstChild("LoadoutPreset")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireServer("Set", idx, slot, r.Weapon)
		end
	elseif r.Kind == "Equipment" then
		if not r.Unlocked and not r.Dup then
			return -- a shard alone doesn't unlock the item yet
		end
		local eqv = Remotes:FindFirstChild("EquipmentEquip")
		if eqv and eqv:IsA("RemoteEvent") then
			eqv:FireServer(r.Slot, r.Id)
		end
	else
		if r.GunLocked then return end -- the gun isn't unlocked yet
		local ev = Remotes:FindFirstChild("SkinEquip")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireServer(r.Weapon, r.Skin)
		end
	end
	self.EquipLbl.Text = "EQUIPPED"
	self.EquipBtn:SetAttribute("Disabled", true)
end

function Unbox:_step(dt)
	local now = os.clock()
	local sc = self.Sc
	local s = self.Spin
	if s then
		local u = math.clamp((now - s.T) / s.D, 0, 1)
		local e = 1 - (1 - u) ^ 4
		local x = s.X0 + (s.X1 - s.X0) * e
		self.Strip.Position = O(x, (WH - CH) / 2)
		local idx = math.floor((WW / 2 - x - CW / 2) / PITCH + 0.5)
		if idx ~= s.Last then
			if s.Last and now - (s.TickT or 0) > 0.035 then
				self:_sfx("Tick", 0.85 + 0.35 * e, 1)
				s.TickT = now
			end
			s.Last = idx
		end
		if u >= 1 then
			self.Spin = nil
			self:_land(s.Tok)
		end
	end

	local shake = self.ShakeAmt or 0
	local ch = self.Charge
	if ch then
		local k = math.clamp((now - ch.T) / ch.D, 0, 1)
		shake = math.max(shake, ch.Shake * 0.55 * k * sc)
		-- sparks pulled into the panel
		ch.Acc += dt * (40 + 160 * k)
		local cx, cy = self:_pt(DW / 2, DH / 2 + 10)
		while ch.Acc >= 1 do
			ch.Acc -= 1
			local a = math.random() * math.pi * 2
			local R = (520 + math.random() * 420) * sc
			local life = 0.42
			self:_part({ X = cx + math.cos(a) * R, Y = cy + math.sin(a) * R, VX = -math.cos(a) * R / life, VY = -math.sin(a) * R / life, Life = life, Size = 7 * sc, Col = self:_pcol(ch.Col, ch.Rainbow), Streak = true })
		end
		self.PanelPop.Scale = 1 + 0.03 * k + math.sin(now * 30) * 0.006 * k
	end
	if shake > 0.3 then
		self.Root.Position = UDim2.new(0.5, (math.random() - 0.5) * 2 * shake, 0.5, (math.random() - 0.5) * 2 * shake)
	else
		self.Root.Position = S(0.5, 0.5)
	end
	self.ShakeAmt = (self.ShakeAmt or 0) * math.exp(-5 * dt)

	if self.Phase == "Reveal" then
		local t = now - (self.RevealT or now)
		local fx, col = self.FXCur, self.Col
		local L = self.AL
		local boost = 1 + 4 * math.exp(-t * 2.5)
		L.RaysA.Rotation -= dt * 4 * boost
		L.RaysB.Rotation += dt * 3 * boost
		L.Ring.Rotation += dt * 10
		L.Bokeh.Rotation += dt * 2
		L.Core.ImageTransparency = 0.45 + math.sin(t * 2.6) * 0.12
		local rs = 0.95 + math.sin(t * 3) * 0.02
		L.Ring.Size = S(rs, rs)
		local hue = (t * 0.22) % 1
		if fx.Rainbow then
			local hc = Color3.fromHSV(hue, 0.6, 1)
			for _, g in self.GlowVP do g.F.Ambient = hc end
			self.SlamGrad.Rotation = (t * 60) % 360
			L.Bloom.ImageColor3 = Color3.fromHSV(hue, 0.75, 1)
			L.RaysB.ImageColor3 = Color3.fromHSV((hue + 0.33) % 1, 0.7, 1)
			L.RaysA.ImageColor3 = Color3.fromHSV((hue + 0.15) % 1, 0.45, 1)
			L.Ring.ImageColor3 = Color3.fromHSV((hue + 0.5) % 1, 0.4, 1)
		end
		for i, g in self.GlowVP do
			if fx.Glow < 1 then
				g.F.ImageTransparency = math.clamp(fx.Glow + (if i == 1 then 0.45 else 0.22) + math.sin(t * 3.2 + i) * 0.1, 0, 1)
			end
		end
		if self.Gun and self.GunBase and self.Gun.Parent then
			local cf = CFrame.Angles(0, math.sin(t * 0.9) * 0.5, 0) * self.GunBase
			self.Gun:PivotTo(cf)
			for _, c in self.GlowModels or {} do
				if c.Parent then c:PivotTo(cf) end
			end
		end
		if self.Gun3 and self.Gun3.Parent then
			local R = self.Rot
			if not R.Drag then
				local idle = now - R.Last > 1.6
				R.V += ((if idle then 0.35 else 0) - R.V) * math.min(1, dt * (if idle then 1 else 2.2))
				R.Yaw += R.V * dt
				if idle then R.Pitch += (0 - R.Pitch) * math.min(1, dt * 1.5) end
			end
			self.Gun3:PivotTo(CFrame.new(STAGE3) * CFrame.Angles(R.Pitch, 0, 0) * CFrame.Angles(0, R.Yaw, 0) * CFrame.new(-STAGE3) * self.Gun3Base)
			local C3 = self.Cam3
			C3.Dolly *= math.exp(-dt * 5)
		end
		local tc = self.TextChroma
		if tc then
			local o = Vector2.new(math.sin(t * 1.3) * 0.5, 0)
			self.NameGrad.Offset, self.TierGrad.Offset = o, o
			if self.Hl then self.Hl.OutlineColor = K.chromaColor(tc, t, 0) end
		end
		if self.Hl and fx.Charge > 0 then
			self.Hl.FillTransparency = 0.84 + math.sin(t * 3) * 0.06
		end
		-- embers rising around the gun, twinkling stars
		local cx, cy = self:_pt(DW / 2, 470)
		self.EmberAcc += dt * fx.Embers
		while self.EmberAcc >= 1 do
			self.EmberAcc -= 1
			self:_part({ X = cx + (math.random() - 0.5) * 1100 * sc, Y = cy + (60 + math.random() * 320) * sc, VX = (math.random() - 0.5) * 50 * sc, VY = -(70 + math.random() * 150) * sc, Life = 1.6 + math.random() * 1.6, Size = (4 + math.random() * 9) * sc, Col = self:_pcol(col, fx.Rainbow), Grav = -25 * sc })
		end
		self.StarAcc += dt * fx.Stars
		while self.StarAcc >= 1 do
			self.StarAcc -= 1
			self:_part({ X = cx + (math.random() - 0.5) * 900 * sc, Y = cy + (math.random() - 0.5) * 420 * sc, Life = 0.6 + math.random() * 0.6, Size = (12 + math.random() * 14) * sc, Col = WHITE:Lerp(col, math.random() * 0.4), Star = true })
		end
	end

	for i = #self.Parts, 1, -1 do
		local q = self.Parts[i]
		q.T += dt
		local k = q.T / q.L
		if k >= 1 then
			q.F:Destroy()
			table.remove(self.Parts, i)
		else
			if q.Star then
				local z = math.sin(k * math.pi) * q.Sz
				q.F.Size = O(z * 0.35, z * 0.35)
				q.F.Rotation = 45 + k * 90
				q.F.BackgroundTransparency = 0.1
			else
				q.VY += q.G * dt
				if q.D > 0 then
					local d = math.exp(-q.D * dt)
					q.VX *= d
					q.VY *= d
				end
				q.X += q.VX * dt
				q.Y += q.VY * dt
				q.F.Position = O(q.X, q.Y)
				q.F.BackgroundTransparency = k * k
				if q.Streak then
					local sp = math.sqrt(q.VX * q.VX + q.VY * q.VY)
					q.F.Rotation = math.deg(math.atan2(q.VY, q.VX))
					q.F.Size = O(math.clamp(sp * 0.035, 3, 80 * sc), math.max(2, q.Sz * 0.45))
				end
			end
		end
	end
end

function Unbox:Close()
	if not self.Active then return end
	self.Active = false
	self.Token += 1
	self.Phase, self.Spin, self.Charge, self.ShakeAmt = nil, nil, nil, 0
	self.Gui.Enabled = false
	self.Root.Position = S(0.5, 0.5)
	self.PanelPop.Scale = 1
	local gs = self.Glow:FindFirstChildOfClass("UIStroke")
	if gs then gs.Color, gs.Transparency = P.Glow, 0.72 end
	self.VP:ClearAllChildren()
	for _, g in self.GlowVP do g.F:ClearAllChildren() g.F.ImageTransparency = 1 end
	self.Gun, self.GunBase, self.GlowModels = nil, nil, {}
	self:_clear3D(false)
	self.TextChroma = nil
	self.FX:ClearAllChildren()
	self.Parts = {}
	self.Strip:ClearAllChildren()
	self.Row:ClearAllChildren()
	self.Cards = {}
	local done = self.Opts and self.Opts.OnDone
	if done then
		done(self.Result)
	end
end

function Unbox:HandleKey(kc)
	if not self.Active then return false end
	if kc == Enum.KeyCode.Space or kc == Enum.KeyCode.Return or kc == Enum.KeyCode.ButtonA then
		if self.Phase == "Reel" then
			self:_skip()
		elseif self.Phase == "Reveal" and os.clock() - (self.RevealT or 0) > 0.8 then
			self:Close()
		end
	elseif (kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB) and self.Phase == "Reveal" then
		self:Close()
	end
	return true
end

return Unbox
