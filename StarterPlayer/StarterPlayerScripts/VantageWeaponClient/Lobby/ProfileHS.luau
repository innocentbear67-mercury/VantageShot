--!nocheck
--[[
	ProfileHS - VantageShot Profile modal (2026-11-17). Follows Hypershot's profile (user capture 2576x1357, x0.78):
	  title "<Name>'s Profile" on the top border with the Roblox headshot breaking the top-left corner, red X
	  left     Exclusive Skins / Collection Worth, Most Valuable Skins 2x2, Favorite Weapons 2x2 (most eliminations)
	  centre   Casual / Ranked / Leaderboard tabs; rank badge, rank name, RP bar; match history rows (win teal / loss red)
	  right    VIEW INVENTORY; profile card (banner, LEVEL tab, name strip, rank badge + win-streak flame); edit popup
	Data: player attributes from ProfileService / Progression / CrateService / Mastery (they replicate to every client,
	so another player's profile reads the same attributes). Skins: SeasonPassHS2 atlases. Animated like the Shop.
	API: Mount(layer, env) -> { Root, OnShow, Object }; Object:SetTarget(player) before opening for someone else.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local R = require(Vantage:WaitForChild("Ranked"):WaitForChild("RankedConfig"))
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local MatchConfig = require(Vantage:WaitForChild("MatchConfig"))
local K = require(script.Parent:WaitForChild("ScreenKit"))

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right

local function id(n) return "rbxassetid://" .. n end
-- SeasonPassHS2 skin atlases (same rendered kit)
local ATLAS = { [0] = id(104850711810300), id(84706372895889), id(136561818438659) }
local A = {
	back = { 2, 3, 285, 300, 92 }, claimall = { 0, 3, 899, 400, 104 }, close = { 1, 861, 854, 124, 124 },
	face_dark = { 0, 3, 3, 425, 445 }, frame_white = { 1, 431, 3, 425, 445 }, fill = { 2, 3, 380, 160, 64 },
	panel = { 1, 3, 451, 400, 400 }, pill = { 0, 406, 899, 400, 104 }, track = { 2, 492, 380, 160, 64 },
	claim = { 2, 306, 285, 290, 92 }, check = { 1, 406, 451, 300, 240 }, strip = { 1, 482, 854, 240, 140 },
}
local BANDS = id(132171274146535)
local ROWS = id(124142702572098) -- win (2,2) / loss (2,72), 1010x66
local FLAME = id(87928671958534) -- win-streak flame (rendered)
local GLOW = id(104786452938879)
local RAYS = id(113538852110620)
local BLOOM = id(103142630740394)
local STAR = id(107113949398119)
local REQ_ICON = id(115805213028426)
local MAP_ART = {} -- [map name] = { Image, W, H } (Live Fire picture, once supplied)

-- geometry: capture px; composition origin (40, 45); x0.78
local SC = 0.78
local OX, OY = 40, 45
local CW, CH = 2420 * SC, 1250 * SC
local function R2(x, y) return O((x - OX) * SC, (y - OY) * SC) end
local function Z(w, h) return O(w * SC, h * SC) end
local function P(v) return v * SC end
local PX0, PY0, PX1, PY1 = 90, 120, 2385, 1280

local INK = RGB(14, 8, 24)
local GREEN = RGB(130, 255, 120)
local MUTED = RGB(170, 160, 196)

local skinInfo = {}
for _, list in Config.Pool().ByTier do
	for _, e in list do skinInfo[e.Key] = e end
end
local function chroma(r) return K.CHROMAS and K.CHROMAS[r] end
local function rarityColor(r, t)
	local d = chroma(r)
	if d then return K.chromaColor(d, t or 0, 0) end
	return Config.TierColor[r] or WHITE
end
local function hsv(col, s, v)
	local h, s0 = col:ToHSV()
	return Color3.fromHSV(h, math.clamp(s0 * s, 0, 1), v)
end
local function num(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function spaced(s) return (s:gsub("(%l)(%u)", "%1 %2")) end
local function skin(obj, key)
	local a = A[key]
	obj.Image = ATLAS[a[1]]
	obj.ImageRectOffset = V2(a[2], a[3])
	obj.ImageRectSize = V2(a[4], a[5])
	return obj
end

-- uniform gun framing (InventoryHS rule) + flat silhouettes
local function aabb(m)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = Vector3.new(
				math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
				math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
				math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
			)
			mn = mn:Min(cf.Position - ex)
			mx = mx:Max(cf.Position + ex)
		end
	end
	return mn, mx
end
local FOV = 30
local function frameUniform(vp, m, tilt, fill)
	vp:ClearAllChildren()
	local mn, mx = aabb(m)
	if mn.X == math.huge then return end
	local ctr = (mn + mx) / 2
	local span = mx - mn
	local L = math.max(span.X, span.Y * 1.7, 0.1)
	m:PivotTo(CFrame.new(ctr) * CFrame.Angles(0, 0, math.rad(tilt)) * CFrame.new(-ctr) * m:GetPivot())
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	local d = L * fill / (2 * math.tan(math.rad(FOV / 2)))
	cam.CFrame = CFrame.lookAt(ctr + Vector3.new(0, 0, d + span.Z), ctr)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Ambient = RGB(225, 225, 236)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-0.35, -0.6, -1)
	m.Parent = vp
end
local function silhouette(parent, vp, color, tr, scale, off, z)
	local cam, src = vp.CurrentCamera, vp:FindFirstChildWhichIsA("Model")
	if not (cam and src) then return end
	local v = Instance.new("ViewportFrame")
	v.Name = "Sil"
	v.BackgroundTransparency = 1
	v.ImageColor3, v.ImageTransparency = color, tr
	v.Ambient, v.LightColor = WHITE, BLACK
	v.AnchorPoint = vp.AnchorPoint
	v.Position = vp.Position + UDim2.fromOffset(off.X, off.Y)
	v.Size = UDim2.new(0, vp.Size.X.Offset * scale, 0, vp.Size.Y.Offset * scale)
	v.ZIndex = z
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color, d.Material, d.Reflectance = WHITE, Enum.Material.SmoothPlastic, 0
			pcall(function() d.TextureID = "" end)
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	local cc = Instance.new("Camera")
	cc.FieldOfView, cc.CFrame = cam.FieldOfView, cam.CFrame
	cc.Parent = v
	v.CurrentCamera = cc
	m.Parent = v
	v.Parent = parent
	return v
end

local PR = {}
PR.__index = PR

function PR.new(layer, env)
	local self = setmetatable({
		Env = env, HS = env.HS, Target = player, Tab = "Ranked",
		Sweeps = {}, Embers = {}, Twinkles = {}, Chromas = {}, Nebula = {}, Rows = {}, Cards = {}, Conns = {},
	}, PR)
	self:_build(layer)
	RunService.RenderStepped:Connect(function(dt)
		if self.Root.Visible then self:_step(dt) end
	end)
	return self
end

function PR:_attr(name)
	local t = self.Target
	if self.Env.Attr then return self.Env.Attr[name] end
	return t and t:GetAttribute(name)
end

------------------------------------------------------------------ kit (same construction as SeasonPassHS2)
function PR:_label(parent, p)
	local HS = self.HS
	local z = p.ZIndex or 40
	local drop
	if p.Drop ~= false then
		drop = HS.text(parent, { Name = (p.Name or "Label") .. "Drop", Text = p.Text, Font = p.Font, TextSize = p.TextSize, Color = BLACK, X = p.X, Y = p.Y, Rich = p.Rich, Fit = p.Fit, Stroke = p.Stroke or 3, StrokeColor = BLACK, AnchorPoint = p.AnchorPoint, Position = (p.Position or UDim2.new()) + UDim2.fromOffset(0, p.DropY or math.max(2, (p.TextSize or 24) * 0.07)), Size = p.Size, ZIndex = z - 1 })
		drop.TextTransparency = 0.35
		local st = drop:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = 0.35 end
	end
	local t = HS.text(parent, { Name = p.Name or "Label", Text = p.Text, Font = p.Font, TextSize = p.TextSize, Color = p.Color or WHITE, X = p.X, Y = p.Y, Rich = p.Rich, Fit = p.Fit, Stroke = p.Stroke or 3, StrokeColor = p.StrokeColor or INK, AnchorPoint = p.AnchorPoint, Position = p.Position, Size = p.Size, ZIndex = z })
	if p.Grad then HS.new("UIGradient", { Rotation = p.GradRot or 90, Color = p.Grad }, t) end
	if drop then
		t:GetPropertyChangedSignal("Text"):Connect(function() drop.Text = t.Text end)
		t:GetPropertyChangedSignal("Visible"):Connect(function() drop.Visible = t.Visible end)
	end
	return t, drop
end

function PR:_sweep(parent, pos, size, radius, z, strength, period)
	local sw = self.HS.new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = pos, Size = size, ZIndex = z }, parent)
	self.HS.corner(sw, radius)
	local s = strength or 0.35
	local g = self.HS.new("UIGradient", { Rotation = 22, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.38, 1), NK(0.47, 1 - s * 0.55), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.55), NK(0.62, 1), NK(1, 1) }) }, sw)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.6, Period = period })
	return sw
end

function PR:_btn(parent, p)
	local HS, z = self.HS, p.Z or 44
	local b = HS.new("ImageButton", { Name = p.Name or "Btn", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	skin(b, p.Skin)
	local w, h = p.Size.X.Offset, p.Size.Y.Offset
	local a = A[p.Skin]
	local hr = h / (a[5] * 0.95)
	local inset = math.max(3, a[5] * 0.115 * hr)
	self:_sweep(b, O(inset, inset * 0.9), O(w - inset * 2, (h * 0.95) - inset * 2), UDim.new(0, math.max(2, a[5] * 0.17 * hr - inset * 0.6)), z, 0.4)
	local t
	if p.Text then
		t = self:_label(b, { Name = "Label", Text = p.Text, Font = p.Font, TextSize = p.TextSize or 30, Stroke = p.Stroke or 3, StrokeColor = p.Ink or INK, Position = O(0, -h * 0.04), Size = S(1, 1), ZIndex = z + 2 })
	end
	HS.press(b, p.OnClick, { Hover = p.Hover or 1.05, Press = 0.95, Sound = p.Sound })
	return { B = b, T = t }
end

function PR:_embers(holder, n, c1, c2, sz, z)
	for _ = 1, n do
		local k = 0.6 + math.random() * 0.8
		local f = self.HS.new("Frame", { Name = "Ember", BackgroundColor3 = c1:Lerp(c2, math.random()), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz * k, sz * k), ZIndex = z }, holder)
		self.HS.corner(f, UDim.new(0.5, 0))
		table.insert(self.Embers, { F = f, X = math.random(), Y = math.random(), V = 0.05 + math.random() * 0.1, Sway = math.random() * 6.28 })
	end
end

function PR:_twinkles(holder, n, color, sz, z)
	for _ = 1, n do
		local st = self.HS.new("ImageLabel", { Name = "Twinkle", BackgroundTransparency = 1, Image = STAR, ImageColor3 = color, AnchorPoint = V2(0.5, 0.5), Position = S(math.random(), math.random()), Size = O(0, 0), ZIndex = z }, holder)
		table.insert(self.Twinkles, { I = st, Sz = sz * (0.7 + math.random() * 0.6), P = math.random() * 10, Spd = 1.1 + math.random() * 1.5 })
	end
end

-- rarity card (face_dark tinted + rim, 3D gun, glow/shadow/edge, sweep); returns refresh(key, sub)
function PR:_card(parent, pos, size)
	local HS = self.HS
	local new = HS.new
	local z = 30
	local b = new("Frame", { Name = "Card", BackgroundTransparency = 1, Position = pos, Size = O(size, size), ZIndex = z }, parent)
	local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = size / 520, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, size * 0.4, 1, size * 0.4), ZIndex = z - 1 }, b)
	local face = skin(new("ImageLabel", { Name = "Face", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z }, b), "face_dark")
	local frame = skin(new("ImageLabel", { Name = "Frame", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z + 5 }, b), "frame_white")
	local fg = new("UIGradient", { Rotation = 30, Enabled = false }, frame)
	local holder = new("Frame", { Name = "Item", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z + 1 }, b)
	self:_sweep(b, O(size * 0.04, size * 0.04), O(size * 0.92, size * 0.92), UDim.new(0, size * 0.07), z + 4, 0.25)
	local sub = self:_label(b, { Name = "Sub", Text = "", Font = HS.MontX, TextSize = math.max(12, size * 0.13), Stroke = 2.2, StrokeColor = BLACK, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -size * 0.04), Size = O(size * 0.9, size * 0.2), ZIndex = z + 7 })
	local rec = { B = b, Face = face, Frame = frame, FG = fg, Glow = glow, Holder = holder, Sub = sub }
	function rec.Set(e, text)
		holder:ClearAllChildren()
		sub.Text = text or ""
		if not e then
			face.ImageColor3 = RGB(60, 56, 76)
			frame.ImageColor3 = RGB(120, 116, 140)
			fg.Enabled = false
			glow.ImageTransparency = 1
			rec.Def = nil
			return
		end
		local col = rarityColor(e.Rarity)
		local d = chroma(e.Rarity)
		face.ImageColor3 = hsv(col, 1.05, 1)
		if d and d.Grad then
			fg.Color, fg.Enabled = d.Grad, true
			frame.ImageColor3 = WHITE
		else
			fg.Enabled = false
			frame.ImageColor3 = hsv(col, 0.55, 1)
		end
		rec.Def = d
		glow.ImageColor3, glow.ImageTransparency = col, 0.45
		local vp = new("ViewportFrame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.46), Size = O(size * 0.92, size * 0.92), ZIndex = z + 3 }, holder)
		local ok, m = pcall(K.weapon, e.Weapon, e.Skin)
		if ok and m then
			frameUniform(vp, m, 38, 1.0)
			silhouette(holder, vp, BLACK, 0.45, 1, V2(3, 5), z + 1)
			silhouette(holder, vp, hsv(col, 0.5, 1), 0.45, 1.08, V2(0, 0), z + 1)
			silhouette(holder, vp, WHITE, 0.15, 1.035, V2(0, 0), z + 2)
		end
	end
	table.insert(self.Cards, rec)
	return rec
end

------------------------------------------------------------------ build
function PR:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "ProfileHS", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(CW, CH), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit
	local function L(x, y) return O((x - PX0) * SC, (y - PY0) * SC) end

	-- panel (SeasonPassHS2 construction): glow, violet interior + drifting bands, nebulae, motes, 9-slice neon rim
	local pos, size = R2(PX0, PY0), Z(PX1 - PX0, PY1 - PY0)
	new("ImageLabel", { Name = "PanelGlow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(150, 70, 255), ImageTransparency = 0.15, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 1, Position = pos - O(80, 80), Size = size + O(160, 160), ZIndex = 20 }, fit)
	local panel = new("Frame", { Name = "Panel", BackgroundTransparency = 1, Position = pos, Size = size, ZIndex = 21 }, fit)
	local inner = new("Frame", { Name = "Interior", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 21 }, panel)
	HS.corner(inner, P(46))
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(40, 18, 70)), CK(0.5, RGB(26, 11, 48)), CK(1, RGB(16, 7, 32)) }) }, inner)
	self.Bands = new("ImageLabel", { Name = "Bands", BackgroundTransparency = 1, Image = BANDS, ImageColor3 = RGB(226, 190, 255), ScaleType = Enum.ScaleType.Stretch, Size = S(1, 1), ZIndex = 21 }, inner)
	HS.corner(self.Bands, P(46))
	for i, nb in { { RGB(140, 60, 255), S(0.25, 0.5), 0.74 }, { RGB(40, 170, 255), S(0.8, 0.45), 0.82 } } do
		local im = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = nb[1], ImageTransparency = nb[3], AnchorPoint = V2(0.5, 0.5), Position = nb[2], Size = S(0.7, 0.9), ZIndex = 21 }, inner)
		table.insert(self.Nebula, { I = im, Base = nb[2], Tr = nb[3] })
	end
	local pm = new("Frame", { Name = "PanelMotes", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(P(24), P(24)), Size = UDim2.new(1, -P(48), 1, -P(48)), ZIndex = 21 }, inner)
	self:_embers(pm, 26, RGB(196, 150, 255), RGB(110, 230, 255), P(9), 21)
	self:_twinkles(pm, 10, RGB(226, 206, 255), P(30), 21)
	local rim = skin(new("ImageLabel", { Name = "Rim", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.52, Size = S(1, 1), ZIndex = 23 }, panel), "panel")
	self.RimGrad = new("UIGradient", { Rotation = 35, Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.35, RGB(176, 110, 255)), CK(0.7, RGB(255, 110, 220)), CK(1, RGB(110, 236, 255)) }) }, rim)

	-- headshot breaking the top-left corner + title on the border + X
	local av = new("Frame", { Name = "Avatar", BackgroundColor3 = RGB(30, 14, 54), AnchorPoint = V2(0.5, 0.5), Position = R2(115, 112), Size = Z(150, 150), ZIndex = 46 }, fit)
	HS.corner(av, UDim.new(0.5, 0))
	local avs = HS.stroke(av, 5, WHITE)
	new("UIGradient", { Rotation = 45, Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.5, RGB(176, 110, 255)), CK(1, RGB(255, 110, 220)) }) }, avs)
	new("ImageLabel", { Name = "AvatarGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(176, 110, 255), ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.9, 1.9), ZIndex = 45 }, av)
	self.Head = new("ImageLabel", { Name = "Head", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 47 }, av)
	HS.corner(self.Head, UDim.new(0.5, 0))
	self.AvatarRing = avs
	local cut = new("Frame", { Name = "TitleCut", BackgroundColor3 = RGB(22, 9, 42), BorderSizePixel = 0, Position = R2(190, 96), Size = Z(700, 48), ZIndex = 46 }, fit)
	HS.corner(cut, P(20))
	new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.04, 0), NK(0.96, 0), NK(1, 1) }) }, cut)
	self.TitleCut = cut
	self.Title = self:_label(fit, { Name = "Title", Text = "Profile", TextSize = P(74), Stroke = 5, StrokeColor = RGB(20, 8, 36), Grad = CS(WHITE, RGB(220, 196, 255)), X = LEFT, Fit = false, Position = R2(205, 70), Size = Z(1400, 90), DropY = P(6), ZIndex = 47 })
	local shine = HS.text(fit, { Name = "TitleShine", Text = "Profile", TextSize = P(74), Color = WHITE, X = LEFT, Fit = false, Position = R2(205, 70), Size = Z(1400, 90), ZIndex = 48 })
	local sg = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 0.55), NK(0.5, 0.25), NK(0.52, 0.55), NK(0.58, 1), NK(1, 1) }) }, shine)
	table.insert(self.Sweeps, { G = sg, P = 1, Period = 5 })
	self.TitleShine = shine
	self:_btn(fit, { Name = "Close", Skin = "close", AnchorPoint = V2(0.5, 0.5), Position = R2(2380, 125), Size = Z(122, 122), Z = 48, Hover = 1.08, Sound = "Click", OnClick = function()
		if self.Env.Close then self.Env.Close() end
	end })

	-- left column
	self.StatA = self:_label(panel, { Name = "Exclusive", Text = "", Rich = true, TextSize = P(46), Stroke = 3.4, Position = L(150, 200), Size = Z(560, 66), ZIndex = 30 })
	self.StatB = self:_label(panel, { Name = "Worth", Text = "", Rich = true, TextSize = P(46), Stroke = 3.4, Position = L(150, 262), Size = Z(560, 66), ZIndex = 30 })
	local function divider(y)
		local d = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = L(195, y), Size = Z(445, 4), ZIndex = 30 }, panel)
		new("UIGradient", { Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.5, RGB(176, 110, 255)), CK(1, RGB(255, 110, 220)) }), Transparency = NS({ NK(0, 1), NK(0.15, 0.2), NK(0.85, 0.2), NK(1, 1) }) }, d)
	end
	divider(370)
	self:_label(panel, { Text = "Most Valuable Skins", TextSize = P(38), Stroke = 3, Position = L(150, 384), Size = Z(560, 52), ZIndex = 30 })
	self.MVS = {}
	for i = 0, 3 do
		table.insert(self.MVS, self:_card(panel, L(265 + (i % 2) * 165, 450 + math.floor(i / 2) * 155), P(140)))
	end
	divider(795)
	self:_label(panel, { Text = "Favorite Weapons", TextSize = P(44), Stroke = 3.4, Position = L(150, 806), Size = Z(560, 58), ZIndex = 30 })
	self.Favs = {}
	for i = 0, 3 do
		table.insert(self.Favs, self:_card(panel, L(265 + (i % 2) * 165, 875 + math.floor(i / 2) * 153), P(140)))
	end

	-- tabs
	self.TabBtns = {}
	for i, name in { "Casual", "Ranked", "Leaderboard" } do
		local x0 = 800 + (i - 1) * 296
		local b = new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(60, 52, 84), BackgroundTransparency = 1, Position = L(x0, 160), Size = Z(285, 52), ZIndex = 30 }, panel)
		local lab = self:_label(b, { Text = name, TextSize = P(44), Stroke = 3, Position = O(0, -P(2)), Size = S(1, 1), ZIndex = 32 })
		local line = new("Frame", { Name = "Line", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = UDim2.new(1, 0, 0, P(5)), ZIndex = 31 }, b)
		local lg = new("UIGradient", {}, line)
		HS.press(b, function()
			self.Tab = name
			self:_refresh()
		end, { Hover = 1.04, Press = 0.96, Sound = "Tab" })
		self.TabBtns[name] = { B = b, Line = line, LG = lg, L = lab }
	end

	-- rank header (badge with rays + bloom, name, RP bar)
	local head = new("Frame", { Name = "RankHeader", BackgroundTransparency = 1, Position = L(715, 220), Size = Z(1045, 330), ZIndex = 30 }, panel)
	self.Head2 = head
	local function H(x, y) return O((x - 715) * SC, (y - 220) * SC) end
	self.BadgeRays = new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = H(1238, 305), Size = Z(300, 300), ZIndex = 30 }, head)
	self.BadgeBloom = new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = H(1238, 305), Size = Z(260, 200), ZIndex = 30 }, head)
	self.Badge = new("ImageLabel", { Name = "Badge", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = H(1238, 305), Size = Z(150, 150), ZIndex = 32 }, head)
	self.BadgeBase = H(1238, 305)
	self.RankText = self:_label(head, { Name = "RankName", Text = "", TextSize = P(60), Stroke = 4, StrokeColor = RGB(16, 10, 26), AnchorPoint = V2(0.5, 0.5), Position = H(1238, 428), Size = Z(700, 74), ZIndex = 32 })
	self.RankGrad = new("UIGradient", { Rotation = 90 }, self.RankText)
	local xb = skin(new("ImageLabel", { Name = "RPTrack", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.32, Position = H(950, 466), Size = Z(580, 30), ZIndex = 31 }, head), "track")
	self.RPFill = skin(new("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.32, Position = O(P(3), P(3)), Size = Z(200, 24), ZIndex = 32 }, xb), "fill")
	new("UIGradient", { Color = CS(RGB(70, 210, 90), RGB(170, 255, 140)) }, self.RPFill)
	self:_sweep(self.RPFill, O(P(4), P(2)), UDim2.new(1, -P(8), 0, P(11)), UDim.new(0.5, 0), 32, 0.5)
	self:_label(head, { Text = "RANKED POINTS", Font = HS.MontX, TextSize = P(28), Stroke = 2, Color = MUTED, X = LEFT, Position = H(950, 500), Size = Z(400, 40), ZIndex = 32 })
	self.RPText = self:_label(head, { Text = "", TextSize = P(32), Stroke = 2.6, Color = GREEN, X = RIGHT, Position = H(1130, 498), Size = Z(400, 42), ZIndex = 32 })

	-- match history / leaderboard box
	local box = new("Frame", { Name = "History", BackgroundColor3 = RGB(10, 5, 20), BackgroundTransparency = 0.15, Position = L(715, 575), Size = Z(1045, 660), ZIndex = 30 }, panel)
	HS.corner(box, P(26))
	local bs = HS.stroke(box, 3, WHITE)
	new("UIGradient", { Rotation = 90, Color = CS(RGB(176, 110, 255), RGB(80, 40, 140)) }, bs)
	self.Box = box
	self.List = new("ScrollingFrame", { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = O(P(10), P(10)), Size = UDim2.new(1, -P(20), 1, -P(20)), CanvasSize = O(0, 0), ScrollBarThickness = 6, ScrollBarImageColor3 = RGB(176, 110, 255), ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 31 }, box)
	self.Empty = self:_label(box, { Text = "", TextSize = P(38), Stroke = 3, Color = MUTED, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = Z(900, 60), ZIndex = 33 })

	-- right column: VIEW INVENTORY + profile card
	self.InvBtn = self:_btn(panel, { Name = "ViewInventory", Skin = "claimall", Text = "VIEW INVENTORY", TextSize = P(40), Stroke = 3, Ink = RGB(10, 36, 4), Position = L(1915, 222), Size = Z(330, 86), Z = 34, OnClick = function()
		if self.Env.Open then self.Env.Open("Inventory") end
	end })
	local card = new("ImageButton", { Name = "ProfileCard", BackgroundTransparency = 1, AutoButtonColor = false, Position = L(1855, 375), Size = Z(455, 610), ZIndex = 32 }, panel)
	self.CardGlow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageTransparency = 0.25, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.8, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, P(170), 1, P(170)), ZIndex = 31 }, card)
	local art = new("ImageLabel", { Name = "Banner", BackgroundColor3 = BLACK, ScaleType = Enum.ScaleType.Stretch, Position = O(P(8), P(8)), Size = UDim2.new(1, -P(16), 1, -P(16)), ZIndex = 32 }, card)
	HS.corner(art, P(26))
	self.BannerArt = art
	local motes = new("Frame", { Name = "Motes", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(P(14), P(14)), Size = UDim2.new(1, -P(28), 1, -P(28)), ZIndex = 33 }, card)
	self:_embers(motes, 16, RGB(255, 236, 190), RGB(190, 150, 255), P(8), 33)
	self:_twinkles(motes, 5, WHITE, P(34), 34)
	local vig = new("Frame", { BackgroundColor3 = BLACK, BorderSizePixel = 0, Position = O(P(8), P(8)), Size = UDim2.new(1, -P(16), 1, -P(16)), ZIndex = 33 }, card)
	HS.corner(vig, P(26))
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.55), NK(0.2, 1), NK(0.62, 1), NK(1, 0.15) }) }, vig)
	self:_sweep(card, O(P(10), P(10)), UDim2.new(1, -P(20), 1, -P(20)), UDim.new(0, P(26)), 35, 0.25, 4.4)
	local fr = skin(new("ImageLabel", { Name = "Frame", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 36 }, card), "frame_white")
	self.CardRimGrad = new("UIGradient", { Rotation = 30, Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.5, RGB(176, 110, 255)), CK(1, RGB(255, 110, 220)) }) }, fr)
	local strip = new("Frame", { Name = "NameStrip", BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, BorderSizePixel = 0, AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, P(10), 0, P(495)), Size = UDim2.new(1, -P(20), 0, P(64)), ZIndex = 37 }, card)
	self.CardName = self:_label(strip, { Text = "", TextSize = P(44), Stroke = 3.4, Position = O(0, -P(2)), Size = S(1, 1), ZIndex = 38 })
	local tab = skin(new("ImageLabel", { Name = "LevelTab", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(40, 40, 200, 100), SliceScale = 0.35, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, P(4)), Size = Z(240, 56), ZIndex = 38 }, card), "strip")
	self.CardLevel = self:_label(tab, { Text = "", TextSize = P(38), Stroke = 2.6, Position = O(0, -P(2)), Size = S(1, 1), ZIndex = 39 })
	self.CardBadge = new("ImageLabel", { Name = "Badge", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, -P(45), 1, P(4)), Size = Z(104, 104), ZIndex = 40 }, card)
	local fl = new("ImageLabel", { Name = "Flame", BackgroundTransparency = 1, Image = FLAME, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, P(48), 1, P(6)), Size = Z(84, 84), ZIndex = 40 }, card)
	self.Flame = fl
	self.FlameBase = fl.Position
	self.StreakText = self:_label(fl, { Text = "0", TextSize = P(40), Stroke = 3, StrokeColor = RGB(60, 14, 2), Position = O(0, P(10)), Size = S(1, 1), ZIndex = 41 })
	self.EditHint = self:_label(panel, { Text = "Click to edit your profile!", TextSize = P(40), Stroke = 3, AnchorPoint = V2(0.5, 0.5), Position = L(2083, 1120), Size = Z(460, 110), ZIndex = 32 })
	self.EditHint.TextWrapped = true
	HS.press(card, function()
		if self.Target == player and not self.Env.Attr then self:_openEdit() end
	end, { Hover = 1.03, Press = 0.97, Sound = "Click" })
	self.Card = card

	self:_buildEdit(fit)
end

------------------------------------------------------------------ banner editor
function PR:_buildEdit(fit)
	local HS = self.HS
	local new = HS.new
	local ov = new("TextButton", { Name = "Edit", Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, Position = O(-600, -400), Size = UDim2.new(1, 1200, 1, 800), Visible = false, ZIndex = 70 }, fit)
	self.Edit = ov
	local box = skin(new("ImageLabel", { Name = "Box", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.52, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1060, 640), ZIndex = 71 }, ov), "panel")
	new("UIGradient", { Rotation = 35, Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.5, RGB(176, 110, 255)), CK(1, RGB(255, 110, 220)) }) }, box)
	local bin = new("Frame", { BackgroundColor3 = RGB(26, 12, 46), BorderSizePixel = 0, Position = O(10, 10), Size = UDim2.new(1, -20, 1, -20), ZIndex = 70 }, box)
	HS.corner(bin, 24)
	self:_label(box, { Text = "EDIT PROFILE", TextSize = 50, Stroke = 4, Grad = CS(WHITE, RGB(220, 196, 255)), AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = O(900, 60), ZIndex = 74 })
	self:_label(box, { Text = "Pick your banner", Font = HS.MontX, TextSize = 22, Stroke = 2, Color = MUTED, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = O(900, 30), ZIndex = 74 })
	self.EditTiles = {}
	for i, bn in R.Banners do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local t = new("ImageButton", { Name = bn.Id, BackgroundColor3 = BLACK, AutoButtonColor = false, Image = bn.Image, ScaleType = Enum.ScaleType.Crop, Position = O(60 + col * 320, 126 + row * 200), Size = O(300, 170), ZIndex = 74 }, box)
		HS.corner(t, 16)
		local st = HS.stroke(t, 4, RGB(90, 80, 120))
		new("Frame", { BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = UDim2.new(1, 0, 0, 34), ZIndex = 75 }, t)
		self:_label(t, { Text = bn.Name, TextSize = 22, Stroke = 2.2, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = UDim2.new(1, 0, 0, 34), ZIndex = 76 })
		local ck = skin(new("ImageLabel", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = O(60, 48), Visible = false, ZIndex = 77 }, t), "check")
		HS.press(t, function()
			self.EditPick = bn.Id
			self:_refreshEdit()
		end, { Hover = 1.05, Press = 0.95, Sound = "Select" })
		self.EditTiles[bn.Id] = { B = t, St = st, Ck = ck, Col = bn.Color }
	end
	self:_btn(box, { Name = "Save", Skin = "claim", Text = "SAVE", TextSize = 36, Stroke = 3, Ink = RGB(10, 36, 4), AnchorPoint = V2(1, 1), Position = UDim2.new(0.5, -14, 1, -22), Size = O(230, 72), Z = 76, OnClick = function()
		local rb = Remotes:FindFirstChild("ProfileBanner")
		if rb and self.EditPick then rb:FireServer(self.EditPick) end
		self.Edit.Visible = false
	end })
	self:_btn(box, { Name = "Back", Skin = "back", Text = "BACK", TextSize = 36, Stroke = 3, AnchorPoint = V2(0, 1), Position = UDim2.new(0.5, 14, 1, -22), Size = O(230, 72), Z = 76, OnClick = function()
		self.Edit.Visible = false
	end })
	HS.press(ov, function() self.Edit.Visible = false end, { Hover = 1, Press = 1, Sound = false })
end

function PR:_openEdit()
	self.EditPick = self:_attr("Banner") or R.DefaultBanner
	self:_refreshEdit()
	self.Edit.Visible = true
end

function PR:_refreshEdit()
	for bid, t in self.EditTiles do
		local on = bid == self.EditPick
		t.St.Color = if on then t.Col else RGB(90, 80, 120)
		t.St.Thickness = if on then 6 else 4
		t.Ck.Visible = on
	end
end

------------------------------------------------------------------ rows
function PR:_clearRows()
	for _, r in self.Rows do r:Destroy() end
	table.clear(self.Rows)
end

function PR:_historyRow(i, e, badge)
	local HS = self.HS
	local new = HS.new
	local w, h = P(1010), P(66)
	local y = (i - 1) * P(81)
	local row = new("ImageLabel", { Name = "Row" .. i, BackgroundTransparency = 1, Image = ROWS, ImageRectOffset = V2(2, if e.R == "W" then 2 else 72), ImageRectSize = V2(1010, 66), Position = O(0, y), Size = O(w, h), ZIndex = 32 }, self.List)
	if e.R == "D" then row.ImageColor3 = RGB(170, 170, 190) end
	-- map picture fading in on the right
	local mapArt = MAP_ART[e.Map or ""]
	if mapArt then
		local mp = new("ImageLabel", { Name = "Map", BackgroundTransparency = 1, Image = mapArt[1], ScaleType = Enum.ScaleType.Crop, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -P(4), 0, P(4)), Size = UDim2.new(0, P(260), 1, -P(9)), ZIndex = 33 }, row)
		HS.corner(mp, P(8))
		new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.45, 0.25), NK(1, 0) }) }, mp)
	end
	self:_sweep(row, O(P(4), P(4)), UDim2.new(1, -P(8), 1, -P(9)), UDim.new(0, P(8)), 34, 0.22)
	new("ImageLabel", { Name = "Badge", BackgroundTransparency = 1, Image = badge.Badge, ImageColor3 = badge.Tint or WHITE, ScaleType = Enum.ScaleType.Fit, Position = O(P(10), P(2)), Size = O(P(44), P(44)), ZIndex = 35 }, row)
	local rp = if e.RP then ((e.RP >= 0 and "+" or "") .. e.RP) else "—"
	self:_label(row, { Text = rp, Font = HS.MontX, TextSize = P(20), Stroke = 2, StrokeColor = BLACK, Color = if e.RP and e.RP < 0 then RGB(255, 150, 160) else WHITE, Position = O(P(6), P(40)), Size = O(P(54), P(24)), ZIndex = 36 })
	self:_label(row, { Text = string.format("KDA %d/%d/%d", e.K or 0, e.D or 0, e.A or 0), TextSize = P(34), Stroke = 3, StrokeColor = BLACK, X = LEFT, Position = O(P(76), 0), Size = O(P(260), h), ZIndex = 36 })
	local mode = MatchConfig.Modes[e.M or ""]
	local name = mode and (mode.Name or mode.Short) or tostring(e.M or "")
	name = name:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
	self:_label(row, { Text = string.format("%s (%s)", name, e.S or "0-0"), TextSize = P(40), Stroke = 3.2, StrokeColor = BLACK, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(P(520), h), ZIndex = 36 })
	table.insert(self.Rows, row)
end

function PR:_ladderRow(i, e)
	local HS = self.HS
	local new = HS.new
	local w, h = P(1010), P(66)
	local me = self.Target and e.U == self.Target.UserId
	local row = new("ImageLabel", { Name = "Row" .. i, BackgroundTransparency = 1, Image = ROWS, ImageRectOffset = V2(2, 2), ImageRectSize = V2(1010, 66), ImageColor3 = if me then WHITE elseif i <= 3 then RGB(255, 226, 150) else RGB(150, 140, 200), Position = O(0, (i - 1) * P(81)), Size = O(w, h), ZIndex = 32 }, self.List)
	self:_sweep(row, O(P(4), P(4)), UDim2.new(1, -P(8), 1, -P(9)), UDim.new(0, P(8)), 34, 0.18)
	self:_label(row, { Text = "#" .. i, TextSize = P(40), Stroke = 3, StrokeColor = BLACK, X = LEFT, Position = O(P(18), 0), Size = O(P(110), h), ZIndex = 36 })
	local r = R.RankOf(e.RP, i <= R.LegendTop and e.RP >= R.LegendRP)
	new("ImageLabel", { BackgroundTransparency = 1, Image = r.Rank.Badge, ImageColor3 = r.Rank.Tint or WHITE, ScaleType = Enum.ScaleType.Fit, Position = O(P(130), P(4)), Size = O(P(58), P(58)), ZIndex = 35 }, row)
	self:_label(row, { Text = tostring(e.N or "?"), TextSize = P(40), Stroke = 3, StrokeColor = BLACK, X = LEFT, Position = O(P(205), 0), Size = O(P(470), h), ZIndex = 36 })
	self:_label(row, { Text = r.Name, Font = HS.MontX, TextSize = P(26), Stroke = 2.4, StrokeColor = BLACK, Color = r.Rank.Color, X = RIGHT, Position = O(P(600), 0), Size = O(P(220), h), ZIndex = 36 })
	self:_label(row, { Text = num(e.RP) .. " RP", TextSize = P(36), Stroke = 3, StrokeColor = BLACK, Color = GREEN, X = RIGHT, Position = O(P(800), 0), Size = O(P(190), h), ZIndex = 36 })
	table.insert(self.Rows, row)
end

------------------------------------------------------------------ data
function PR:_owned()
	local set = {}
	for k in tostring(self:_attr("OwnedSkins") or ""):gmatch("[^,]+") do set[k] = true end
	return set
end

function PR:_refresh()
	local t = self.Target
	local name = if self.Env.Attr then (self.Env.Attr.Name or "Player") elseif t then t.DisplayName else "Player"
	self.Title.Text = name .. "'s Profile"
	self.TitleShine.Text = self.Title.Text
	local mine = t == player and not self.Env.Attr
	self.InvBtn.B.Visible = mine
	self.EditHint.Visible = mine
	-- left stats + cards
	local owned = self:_owned()
	local list = {}
	local exclusive = 0
	local worth = tonumber(self:_attr("REQ")) or 0
	for k in owned do
		local e = skinInfo[k]
		if e then
			table.insert(list, e)
			if e.Rarity == "Exclusive" or e.Rarity == "Godly" then exclusive += 1 end
			worth += (Config.Refund and Config.Refund[e.Rarity] or 0)
		end
	end
	self.StatA.Text = string.format('<font color="#FFD25A">Exclusive Skins:</font> %d', exclusive)
	self.StatB.Text = string.format('<font color="#82FF78">Collection Worth:</font> %s', num(worth))
	table.sort(list, function(a, b)
		local ia, ib = Config.TierIndex[a.Rarity] or 0, Config.TierIndex[b.Rarity] or 0
		if ia ~= ib then return ia > ib end
		return a.Key < b.Key
	end)
	for i, c in self.MVS do c.Set(list[i], nil) end
	-- favourites: Mastery_<weapon> = "level|into|need|prestige|kills"
	local favs = {}
	local attrs = if self.Env.Attr then self.Env.Attr else (t and t:GetAttributes() or {})
	for k, v in attrs do
		if type(k) == "string" and k:sub(1, 8) == "Mastery_" and type(v) == "string" then
			local kills = tonumber((v:match("^[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)")))
			if kills and kills > 0 then table.insert(favs, { W = k:sub(9), K = kills }) end
		end
	end
	table.sort(favs, function(a, b) return a.K > b.K end)
	for i, c in self.Favs do
		local f = favs[i]
		if f then
			local sk = attrs["Skin_" .. f.W]
			local e = skinInfo[f.W .. "/" .. tostring(sk)] or { Weapon = f.W, Skin = sk or "Factory", Rarity = "Rare", Key = f.W }
			c.Set(e, num(f.K) .. " ELIMS")
		else
			c.Set(nil, "")
		end
	end
	-- rank header
	local legend = self:_attr("RankLegend") == true
	local rp = tonumber(self:_attr("RP")) or 0
	local r = R.RankOf(rp, legend)
	self.Badge.Image, self.Badge.ImageColor3 = r.Rank.Badge, r.Rank.Tint or WHITE
	self.BadgeBloom.ImageColor3, self.BadgeRays.ImageColor3 = r.Rank.Color, r.Rank.Color
	self.RankText.Text = r.Name
	self.RankGrad.Color = CS(WHITE, hsv(r.Rank.Color, 0.8, 1))
	local frac = if r.Need > 0 then r.Into / r.Need else 1
	self.RPFill.Size = O(math.max(P(574) * frac, P(24)), P(24))
	self.RPText.Text = num(rp) .. " RP"
	-- profile card
	local bn = R.BannerById[self:_attr("Banner") or R.DefaultBanner] or R.Banners[1]
	self.BannerArt.Image = bn.Image
	self.CardGlow.ImageColor3 = bn.Color
	self.CardName.Text = name
	self.CardLevel.Text = "LEVEL " .. tostring(self:_attr("Level") or 1)
	self.CardBadge.Image, self.CardBadge.ImageColor3 = r.Rank.Badge, r.Rank.Tint or WHITE
	self.StreakText.Text = tostring(self:_attr("Streak") or 0)
	if t and not self.Env.Attr and t.UserId > 0 then
		task.spawn(function()
			local ok, img = pcall(Players.GetUserThumbnailAsync, Players, t.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			if ok then self.Head.Image = img end
		end)
	end
	-- tabs
	for nm, tb in self.TabBtns do
		local on = nm == self.Tab
		tb.B.BackgroundTransparency = if on then 0.55 else 1
		tb.Line.Size = UDim2.new(1, 0, 0, if on then P(6) else P(3))
		tb.LG.Color = if on then CS({ CK(0, RGB(110, 236, 255)), CK(0.5, WHITE), CK(1, RGB(255, 110, 220)) }) else CS(RGB(90, 80, 120), RGB(90, 80, 120))
		tb.L.TextColor3 = if on then WHITE else RGB(190, 180, 214)
	end
	self.Head2.Visible = self.Tab ~= "Leaderboard"
	-- list
	self:_clearRows()
	local n = 0
	if self.Tab == "Leaderboard" then
		self.Box.Position = O((715 - PX0) * SC, (230 - PY0) * SC)
		self.Box.Size = Z(1045, 1005)
		local ok, top = pcall(HttpService.JSONDecode, HttpService, tostring(Vantage:GetAttribute("RankedTop") or "[]"))
		for i, e in (ok and type(top) == "table") and top or {} do
			if i > 50 then break end
			self:_ladderRow(i, e)
			n = i
		end
		self.Empty.Text = if n == 0 then "No ranked players yet" else ""
	else
		self.Box.Position = O((715 - PX0) * SC, (575 - PY0) * SC)
		self.Box.Size = Z(1045, 660)
		local ok, h = pcall(HttpService.JSONDecode, HttpService, tostring(self:_attr("ProfileHist") or "{}"))
		local hist = (ok and type(h) == "table" and h[self.Tab]) or {}
		for i, e in hist do
			local br = R.RankOf(rp, legend).Rank
			self:_historyRow(i, e, br)
			n = i
		end
		self.Empty.Text = if n == 0 then (if self.Tab == "Ranked" then "No ranked matches yet. Queue Ranked Deathmatch to earn RP!" else "No matches yet. Deploy to start your history!") else ""
	end
	self.List.CanvasSize = O(0, n * P(81))
end

function PR:SetTarget(p)
	for _, c in self.Conns do c:Disconnect() end
	table.clear(self.Conns)
	self.Target = p or player
	if self.Target then
		table.insert(self.Conns, self.Target.AttributeChanged:Connect(function(a)
			if self.Root.Visible and (a == "RP" or a == "Banner" or a == "ProfileHist" or a == "Streak" or a == "OwnedSkins" or a == "Level" or a:sub(1, 8) == "Mastery_") then
				self:_refresh()
			end
		end))
	end
end

------------------------------------------------------------------ animation (Shop tricks)
function PR:_step(dt)
	local t = os.clock()
	for _, sw in self.Sweeps do
		if sw.G.Parent then
			local u = ((t + sw.P) % (sw.Period or 3.6)) / 0.9
			sw.G.Offset = V2(if u < 1 then -1 + 2 * u else 1, 0)
		end
	end
	if self.RimGrad then self.RimGrad.Rotation = 35 + (t * 14) % 360 end
	if self.TitleCut then self.TitleCut.Size = O(self.Title.TextBounds.X + P(40), P(48)) end
	if self.CardRimGrad then self.CardRimGrad.Rotation = (t * 40) % 360 end
	if self.AvatarRing then
		local g = self.AvatarRing:FindFirstChildOfClass("UIGradient")
		if g then g.Rotation = (t * 60) % 360 end
	end
	-- panel bands Ken Burns + nebulae
	local zz = 1.05 + 0.05 * (0.5 + 0.5 * math.sin(t * 0.31))
	local rw, rh = 1024 / zz, 640 / zz
	self.Bands.ImageRectSize = V2(rw, rh)
	self.Bands.ImageRectOffset = V2((1024 - rw) * (0.5 + math.sin(t * 0.19) * 0.45), (640 - rh) * (0.5 + math.cos(t * 0.15) * 0.45))
	for i, nb in self.Nebula do
		nb.I.Position = nb.Base + UDim2.fromScale(math.sin(t * 0.13 + i * 2) * 0.06, math.cos(t * 0.11 + i) * 0.05)
		nb.I.ImageTransparency = nb.Tr + math.sin(t * 0.7 + i) * 0.07
	end
	-- banner Ken Burns (portrait window drifting across the 1024x559 art)
	local bz = 1.06 + 0.06 * (0.5 + 0.5 * math.sin(t * 0.27))
	local bh = 559 / bz
	local bw = math.min(1024, bh * (455 / 610))
	self.BannerArt.ImageRectSize = V2(bw, bh)
	self.BannerArt.ImageRectOffset = V2((1024 - bw) * (0.5 + math.sin(t * 0.16) * 0.42), (559 - bh) * (0.5 + math.cos(t * 0.21) * 0.4))
	self.CardGlow.ImageTransparency = 0.22 + 0.15 * math.sin(t * 1.8)
	-- rank badge: float, rays spin, bloom breathes
	self.Badge.Position = self.BadgeBase + O(0, math.sin(t * 1.5) * P(7))
	self.Badge.Rotation = math.sin(t * 0.9) * 3
	self.BadgeRays.Rotation = (t * 10) % 360
	self.BadgeBloom.ImageTransparency = 0.3 + 0.15 * math.sin(t * 2.4)
	-- streak flame flickers
	local f = 1 + 0.06 * math.sin(t * 9) + 0.03 * math.sin(t * 23)
	self.Flame.Size = Z(84 * f, 84 * (2 - f))
	self.Flame.Rotation = math.sin(t * 5) * 4
	-- edit hint pulses
	self.EditHint.TextTransparency = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(t * 2.6))
	-- card chroma rims
	for _, c in self.Cards do
		if c.Def and c.FG.Enabled then
			c.FG.Offset = V2(math.sin(t * 0.8) * 0.5, 0)
			c.Face.ImageColor3 = hsv(K.chromaColor(c.Def, t, 0), 1.05, 1)
		end
	end
	for _, e in self.Embers do
		e.Y -= e.V * dt
		if e.Y < -0.05 then e.Y, e.X = 1.05, math.random() end
		e.F.Position = UDim2.new(e.X, math.sin(t * 1.3 + e.Sway) * 6, e.Y, 0)
		e.F.BackgroundTransparency = 0.15 + 0.85 * math.clamp(1 - e.Y, 0, 1) ^ 2
	end
	for _, st in self.Twinkles do
		local a = math.max(0, math.sin((t + st.P) * st.Spd))
		st.I.Size = O(st.Sz * a, st.Sz * a)
		st.I.Rotation = (t * 40 + st.P * 60) % 360
		if a <= 0.02 and not st.Moved then
			st.Moved = true
			st.I.Position = S(0.05 + math.random() * 0.9, 0.05 + math.random() * 0.9)
		elseif a > 0.1 then
			st.Moved = false
		end
	end
end

------------------------------------------------------------------ mount
function PR:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.42, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
	self.FitFrame.Position = UDim2.new(0.5, 0, 0.5, 6 * self.Fit.Scale)
end

function PR:OnShow()
	self:_fit()
	self.Edit.Visible = false
	if not self.Target or not self.Target.Parent then self:SetTarget(player) end
	self:_refresh()
end

function PR.Mount(layer, env)
	local s = PR.new(layer, env)
	s:SetTarget(player)
	return {
		Root = s.Root,
		OnShow = function() s:OnShow() end,
		Object = s,
	}
end

return PR
