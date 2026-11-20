--!nocheck
--[[
	SeasonPassHS2 - VantageShot Season Pass, v2 (2026-11-17). Rebuilt on the measured Hypershot battlepass
	(reference 3198x1886 true px, x0.58 -> design px). v1 (SeasonPassHS) is kept as the fallback.
	Layers, back to front:
	  panel glow -> panel interior (violet gradient + diagonal bands/hex web + vignette) -> 9-slice neon rim
	  title (drop + stroke) + emblem break the top-left corner; REQ pill / CLAIM ALL / X break the top edge
	  tier strip (9-slice bevel) with XP track + fill (9-slice, tinted) | Free row | timeline | Premium row | footer
	Cards: banded chrome face (silver / gold, or dark face tinted by the rarity colour) + frame (silver / gold
	hatch / white rim tinted by K.CHROMAS) + light sweep; items are 3D renders (K.weapon) or crate / REQ art with
	shadow + glow silhouettes. Overlays: check, CLAIM!, lock, Odds, eye. All skins are rendered PNG atlases
	(sp2_atlas0-2, built by /home/claude/sp/art/hs2.py).
	Edit preview: Mount(layer, { HS = HS, Attr = { PassXP = 3800, ... }, ToastParent = gui }).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Pass = require(Vantage:WaitForChild("SeasonPass"):WaitForChild("PassConfig"))
local Shop = require(Vantage:WaitForChild("Shop"):WaitForChild("ShopConfig"))
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local K = require(script.Parent:WaitForChild("ScreenKit"))

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local ROBUX = utf8.char(0xE002)

local function id(n) return "rbxassetid://" .. n end
local ATLAS = { [0] = id(104850711810300), id(84706372895889), id(136561818438659) }
local BANDS = id(132171274146535)
local A = { -- { atlas, x, y, w, h }
	arrow_l = { 1, 166, 854, 155, 155 }, arrow_r = { 1, 324, 854, 155, 155 }, back = { 2, 3, 285, 300, 92 },
	check = { 1, 406, 451, 300, 240 }, claim = { 2, 306, 285, 290, 92 }, claimall = { 0, 3, 899, 400, 104 },
	close = { 1, 861, 854, 124, 124 }, eye = { 0, 809, 899, 84, 84 }, face_dark = { 0, 3, 3, 425, 445 },
	face_gold = { 0, 431, 3, 425, 445 }, face_silver = { 0, 3, 451, 425, 445 }, fill = { 2, 3, 380, 160, 64 },
	frame_gold = { 0, 431, 451, 425, 445 }, frame_silver = { 1, 3, 3, 425, 445 }, frame_white = { 1, 431, 3, 425, 445 },
	get = { 2, 599, 285, 330, 92 }, gift = { 1, 725, 854, 133, 138 }, line = { 2, 166, 380, 160, 64 },
	linetrack = { 2, 329, 380, 160, 64 }, lock = { 0, 859, 451, 160, 196 }, node_off = { 1, 709, 451, 160, 160 },
	node_on = { 1, 3, 854, 160, 160 }, odds = { 2, 655, 380, 160, 52 }, panel = { 1, 3, 451, 400, 400 },
	pill = { 0, 406, 899, 400, 104 }, skip_grey = { 2, 3, 3, 502, 138 }, skip_orange = { 2, 508, 3, 502, 138 },
	skip_purple = { 2, 3, 144, 502, 138 }, skip_teal = { 2, 508, 144, 502, 138 }, strip = { 1, 482, 854, 240, 140 },
	track = { 2, 492, 380, 160, 64 },
}
local GLOW = id(104786452938879)
local RAYS = id(113538852110620)
local BLOOM = id(103142630740394)
local STAR = id(107113949398119)
local REQ_ICON = id(115805213028426)
local MASCOT = { Free = id(121045850954159), Premium = id(133658342101265), Title = id(135442727231351) } -- Season 1 art (user's Gemini images, rembg cut)
local CORNER, CORNER_W, CORNER_H = id(102272755804121), 670, 658 -- neon cable corner (top-left shape; mirrored per corner)
-- white silhouettes of the art (half size) so light sweeps are cut to each shape (sp_masks.png)
local MASKS = id(86884947126641)
local MASK = { Title = { 2, 2, 430, 382 }, Free = { 434, 2, 235, 315 }, Premium = { 671, 2, 235, 356 }, Corner = { 2, 386, 335, 329 } }
-- crystal highlights on the cable corner (fractions of the image), measured from the cut-out
local CRYSTALS = { { 0.343, 0.129 }, { 0.612, 0.101 }, { 0.091, 0.068 }, { 0.195, 0.127 }, { 0.754, 0.153 }, { 0.908, 0.105 }, { 0.105, 0.912 }, { 0.136, 0.285 }, { 0.185, 0.418 }, { 0.121, 0.541 } }
local REQ_ART = { -- REQ-pack chest cutouts (Shop), by amount
	{ 1000, id(126929361892136) }, { 2500, id(113707123684396) }, { 5000, id(101892365525049) }, { math.huge, id(96063758555679) },
}

-- geometry: Hypershot true px; composition origin (190, 110); x0.58 to design px
local SC = 0.58
local OX, OY = 190, 110
local CW, CH = 2750 * SC, 1745 * SC
local function R(x, y) return O((x - OX) * SC, (y - OY) * SC) end
local function Z(w, h) return O(w * SC, h * SC) end
local function P(v) return v * SC end
local function c(x, y) return O(x * SC, y * SC) end

local PX0, PY0, PX1, PY1 = 278, 210, 2861, 1730 -- panel
local CARD_W, CARD_H, PITCH = 425, 445, 455
local ROW_Y = { Free = 440, Premium = 1050 }
local LABEL_X, FIRST_X = 355, 815
local CLIP_X0, CLIP_X1, CLIP_Y0, CLIP_Y1 = 800, 2846, 400, 1580
local LINE_X0, LINE_X1, LINE_Y, LINE_TOP = 290, 2770, 973, 893
local FIRST = FIRST_X - CLIP_X0
local NODE0 = (CLIP_X0 - LINE_X0) + FIRST + CARD_W / 2
local OFF_MAX = math.max(0, FIRST + (Pass.MaxTier - 1) * PITCH + CARD_W + 16 - (CLIP_X1 - CLIP_X0))

local INK = RGB(14, 8, 24)
local TXT = {
	Free = { Title = CS(WHITE, RGB(196, 200, 212)), TitleInk = RGB(22, 22, 30), Amount = CS(RGB(255, 206, 96), RGB(214, 132, 24)), AmountInk = RGB(56, 28, 4) },
	Premium = { Title = CS(RGB(255, 248, 176), RGB(255, 198, 52)), TitleInk = RGB(66, 34, 4), Amount = CS(RGB(255, 180, 70), RGB(232, 104, 18)), AmountInk = RGB(60, 24, 2) },
}

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

-- world AABB / uniform framing (same rule as InventoryHS frameUniform)
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
	return ctr
end
-- flat-colour silhouette of a viewport's model (shadow / glow / edge)
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

local SP = {}
SP.__index = SP

function SP:_attr(name)
	if self.Env.Attr then return self.Env.Attr[name] end
	return player and player:GetAttribute(name)
end

function SP.new(layer, env)
	local self = setmetatable({
		Env = env, HS = env.HS, Cards = {}, Nodes = {}, Off = 0, Cur = 0, Busy = false, Prev = {}, Glows = {},
		Sweeps = {}, Chromas = {}, Motes = {}, Drag = nil, Dragged = false, Spin = nil,
		Embers = {}, Twinkles = {}, Mascots = {}, Corners = {}, Nebula = {},
	}, SP)
	self:_build(layer)
	RunService.RenderStepped:Connect(function(dt)
		if self.Root.Visible then self:_step(dt) end
	end)
	if player and not env.Attr then
		player.AttributeChanged:Connect(function(a)
			if a:sub(1, 4) == "Pass" or a == "REQ" or a == "OwnedSkins" then self:_refresh() end
		end)
	end
	task.defer(function() self:_refresh() end)
	return self
end

------------------------------------------------------------------ kit
-- Fredoka label with a thick dark stroke and a drop copy underneath
function SP:_label(parent, p)
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

-- light sweep: a white rounded frame whose gradient band slides across (stays inside the rounded shape)
function SP:_sweep(parent, pos, size, radius, z, strength)
	local sw = self.HS.new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = pos, Size = size, ZIndex = z }, parent)
	self.HS.corner(sw, radius)
	local s = strength or 0.35
	local g = self.HS.new("UIGradient", { Rotation = 22, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.38, 1), NK(0.47, 1 - s * 0.55), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.55), NK(0.62, 1), NK(1, 1) }) }, sw)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.6 })
	return sw
end

-- rendered button skin + label + sweep (sweep clipped to the face)
function SP:_btn(parent, p)
	local HS, z = self.HS, p.Z or 44
	local b = HS.new("ImageButton", { Name = p.Name or "Btn", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	skin(b, p.Skin)
	local w, h = p.Size.X.Offset, p.Size.Y.Offset
	local a = A[p.Skin]
	local hr = h / (a[5] * 0.95) -- design px per skin px (vertical, minus shadow room)
	local inset = math.max(3, a[5] * 0.115 * hr)
	self:_sweep(b, O(inset, inset * 0.9), O(w - inset * 2, (h * 0.95) - inset * 2), UDim.new(0, math.max(2, (p.Radius or a[5] * 0.17) * hr - inset * 0.6)), z, p.Sweep or 0.4)
	local t
	if p.Text then
		t = self:_label(b, { Name = "Label", Text = p.Text, Font = p.Font, TextSize = p.TextSize or 30, Stroke = p.Stroke or 3, StrokeColor = p.Ink or INK, Rich = p.Rich, Position = O(0, -h * 0.04), Size = S(1, 1), ZIndex = z + 2 })
	end
	HS.press(b, p.OnClick, { Hover = p.Hover or 1.05, Press = 0.95, Sound = p.Sound })
	return { B = b, T = t, Skin = p.Skin }
end

------------------------------------------------------------------ living art (same tricks as the Shop cards)
-- light band cut to an image's exact silhouette (white mask), swept with a UIGradient offset
function SP:_maskSweep(parent, key, z, flipX, flipY, strength, period)
	local r = MASK[key]
	local m = self.HS.new("ImageLabel", { Name = "Sheen", BackgroundTransparency = 1, Image = MASKS, ImageRectOffset = V2(r[1] + (if flipX then r[3] else 0), r[2] + (if flipY then r[4] else 0)), ImageRectSize = V2(if flipX then -r[3] else r[3], if flipY then -r[4] else r[4]), ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = z }, parent)
	local s = strength or 0.55
	local g = self.HS.new("UIGradient", { Rotation = 25, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.4, 1), NK(0.47, 1 - s * 0.5), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.5), NK(0.6, 1), NK(1, 1) }) }, m)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.6, Period = period })
	return m, g
end

-- rising embers (Shop card embers): glowing dots drift up, sway and fade out near the top
function SP:_embers(holder, n, c1, c2, sz, z)
	for _ = 1, n do
		local k = 0.6 + math.random() * 0.8
		local f = self.HS.new("Frame", { Name = "Ember", BackgroundColor3 = c1:Lerp(c2, math.random()), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz * k, sz * k), ZIndex = z }, holder)
		self.HS.corner(f, UDim.new(0.5, 0))
		table.insert(self.Embers, { F = f, X = math.random(), Y = math.random(), V = 0.05 + math.random() * 0.1, Sway = math.random() * 6.28 })
	end
end

-- twinkling stars: grow, spin, vanish; free ones hop to a new spot each time (fixed ones sit on crystals)
function SP:_twinkles(holder, n, color, sz, z, spots)
	for i = 1, n do
		local sp = spots and spots[(i - 1) % #spots + 1]
		local st = self.HS.new("ImageLabel", { Name = "Twinkle", BackgroundTransparency = 1, Image = STAR, ImageColor3 = color, AnchorPoint = V2(0.5, 0.5), Position = if sp then S(sp[1], sp[2]) else S(math.random(), math.random()), Size = O(0, 0), ZIndex = z }, holder)
		table.insert(self.Twinkles, { I = st, Sz = sz * (0.7 + math.random() * 0.6), P = math.random() * 10, Spd = 1.1 + math.random() * 1.5, Fixed = sp ~= nil })
	end
end

------------------------------------------------------------------ panel
function SP:_panel(fit)
	local HS = self.HS
	local new = HS.new
	local pos, size = R(PX0, PY0), Z(PX1 - PX0, PY1 - PY0)
	-- outer glow
	new("ImageLabel", { Name = "PanelGlow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(150, 70, 255), ImageTransparency = 0.15, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 1, Position = pos - O(80, 80), Size = size + O(160, 160), ZIndex = 20 }, fit)
	local p = new("Frame", { Name = "Panel", BackgroundTransparency = 1, Position = pos, Size = size, ZIndex = 21 }, fit)
	-- interior
	local inner = new("Frame", { Name = "Interior", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 21 }, p)
	HS.corner(inner, P(46))
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(46, 22, 78)), CK(0.5, RGB(32, 14, 58)), CK(1, RGB(22, 9, 40)) }) }, inner)
	local bands = new("ImageLabel", { Name = "Bands", BackgroundTransparency = 1, Image = BANDS, ImageColor3 = RGB(226, 190, 255), ImageTransparency = 0, ScaleType = Enum.ScaleType.Stretch, Size = S(1, 1), ZIndex = 21 }, inner)
	HS.corner(bands, P(46))
	-- nebula blooms + vignette
	table.insert(self.Nebula, { I = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(140, 60, 255), ImageTransparency = 0.72, AnchorPoint = V2(0.5, 0.5), Position = S(0.3, 0.55), Size = S(0.8, 0.9), ZIndex = 21 }, inner), Base = S(0.3, 0.55), Tr = 0.72 })
	table.insert(self.Nebula, { I = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(40, 170, 255), ImageTransparency = 0.82, AnchorPoint = V2(0.5, 0.5), Position = S(0.78, 0.4), Size = S(0.7, 0.8), ZIndex = 21 }, inner), Base = S(0.78, 0.4), Tr = 0.82 })
	local vig = new("Frame", { Name = "Vignette", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 21 }, inner)
	HS.corner(vig, P(46))
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.55), NK(0.12, 1), NK(0.8, 1), NK(1, 0.4) }) }, vig)
	self.Bands = bands
	local pm = new("Frame", { Name = "PanelMotes", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(P(24), P(24)), Size = UDim2.new(1, -P(48), 1, -P(48)), ZIndex = 21 }, inner)
	self:_embers(pm, 30, RGB(196, 150, 255), RGB(110, 230, 255), P(9), 21)
	self:_twinkles(pm, 12, RGB(226, 206, 255), P(32), 21)
	-- 9-slice neon rim (white, tinted + slowly cycling)
	local rim = new("ImageLabel", { Name = "Rim", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.52, Size = S(1, 1), ZIndex = 23 }, p)
	skin(rim, "panel")
	self.RimGrad = new("UIGradient", { Rotation = 35, Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.35, RGB(176, 110, 255)), CK(0.7, RGB(255, 110, 220)), CK(1, RGB(110, 236, 255)) }) }, rim)
	return p
end

------------------------------------------------------------------ items
function SP:_item(card, rw, z)
	local HS = self.HS
	local new = HS.new
	local cx, cy = 212, 292
	if rw.Kind == "Skin" then
		local e = skinInfo[rw.Key]
		local col = rarityColor(e and e.Rarity)
		new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = col, ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = c(cx, cy), Size = Z(400, 300), ZIndex = z }, card)
		local vp = new("ViewportFrame", { Name = "Item", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = c(cx, cy - 6), Size = Z(360, 360), ZIndex = z + 3 }, card)
		if e then
			local ok, m = pcall(K.weapon, e.Weapon, e.Skin)
			if ok and m then
				frameUniform(vp, m, 38, 1.0)
				silhouette(card, vp, BLACK, 0.45, 1, V2(P(6), P(10)), z + 1)
				silhouette(card, vp, hsv(col, 0.5, 1), 0.45, 1.08, V2(0, 0), z + 1)
				silhouette(card, vp, WHITE, 0.1, 1.035, V2(0, 0), z + 2)
			end
		end
		return vp
	end
	local image, color, sz = "", WHITE, 270
	if rw.Kind == "Crate" then
		local cr = Config.ById[rw.Id]
		image, color, sz = cr and cr.Art.Full or "", cr and cr.Color or WHITE, 270
	elseif rw.Kind == "REQ" then
		for _, t in REQ_ART do
			if rw.Amount <= t[1] then image = t[2] break end
		end
		color, sz = RGB(90, 180, 255), 300
	end
	new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = color, ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = c(cx, cy), Size = Z(380, 290), ZIndex = z }, card)
	new("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Image = image, ImageColor3 = BLACK, ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(cx + 8, cy + 14), Size = Z(sz, sz), ZIndex = z + 1 }, card)
	return new("ImageLabel", { Name = "Item", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(cx, cy), Size = Z(sz, sz), ZIndex = z + 3 }, card)
end

------------------------------------------------------------------ cards
function SP:_cardShell(parent, track, pos, name, rarity)
	local HS = self.HS
	local new = HS.new
	local z = 30
	local b = new("ImageButton", { Name = name, BackgroundTransparency = 1, AutoButtonColor = false, Position = pos, Size = Z(CARD_W, CARD_H), ZIndex = z }, parent)
	local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(255, 190, 70), ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.55, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, P(150), 1, P(150)), ZIndex = z - 2 }, b)
	local face = new("ImageLabel", { Name = "Face", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z }, b)
	local frame = new("ImageLabel", { Name = "Frame", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z + 6 }, b)
	if rarity then
		skin(face, "face_dark")
		face.ImageColor3 = hsv(rarityColor(rarity), 1.05, 1)
		skin(frame, "frame_white")
		local d = chroma(rarity)
		if d and d.Grad then
			local g = new("UIGradient", { Rotation = 30, Color = d.Grad }, frame)
			table.insert(self.Chromas, { G = g, Face = face, Def = d })
		else
			frame.ImageColor3 = hsv(rarityColor(rarity), 0.55, 1)
		end
		glow.ImageColor3 = rarityColor(rarity)
	elseif track == "Premium" then
		skin(face, "face_gold")
		skin(frame, "frame_gold")
	else
		skin(face, "face_silver")
		skin(frame, "frame_silver")
	end
	local rr = UDim.new(0, P(30))
	self:_sweep(b, O(P(14), P(14)), Z(CARD_W - 28, CARD_H - 28), rr, z + 5, 0.22)
	local flash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, Position = O(P(10), P(10)), Size = Z(CARD_W - 20, CARD_H - 20), ZIndex = z + 12 }, b)
	HS.corner(flash, rr)
	-- motes (claimable cards): small stars drifting up inside the card
	local motes = new("Frame", { Name = "Motes", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(P(14), P(14)), Size = Z(CARD_W - 28, CARD_H - 28), Visible = false, ZIndex = z + 4 }, b)
	for i = 1, 6 do
		local st = new("ImageLabel", { BackgroundTransparency = 1, Image = STAR, ImageColor3 = RGB(255, 236, 170), AnchorPoint = V2(0.5, 0.5), Size = O(P(26), P(26)), ZIndex = z + 4 }, motes)
		table.insert(self.Motes, { I = st, X = math.random(), P = math.random(), Spd = 0.18 + math.random() * 0.2, Holder = motes })
	end
	return b, glow, flash, motes
end

function SP:_card(parent, track, t, pos)
	local HS = self.HS
	local new = HS.new
	local rw = Pass.Tiers[t][track]
	local th = TXT[track]
	local e = rw.Kind == "Skin" and skinInfo[rw.Key]
	local b, glow, flash, motes = self:_cardShell(parent, track, pos, track .. t, e and e.Rarity)
	local z = 30
	-- title + amount (top-left, Hypershot sizes)
	if e then
		self:_label(b, { Name = "Title", Text = spaced(e.Skin), TextSize = P(58), Stroke = 3.4, StrokeColor = BLACK, Grad = CS(WHITE, hsv(rarityColor(e.Rarity), 0.35, 1)), X = LEFT, Position = c(34, 24), Size = Z(300, 70), ZIndex = z + 9 })
		local sub = self:_label(b, { Name = "Amount", Text = string.upper(e.Weapon), Font = HS.MontX, TextSize = P(40), Stroke = 2.6, StrokeColor = BLACK, X = LEFT, Position = c(36, 92), Size = Z(300, 50), ZIndex = z + 9 })
		local d = chroma(e.Rarity)
		new("UIGradient", { Color = if d and d.Grad then d.Grad else CS(rarityColor(e.Rarity), hsv(rarityColor(e.Rarity), 0.55, 1)) }, sub)
		self:_label(b, { Name = "Rarity", Text = string.upper(e.Rarity), Font = HS.MontX, TextSize = P(34), Stroke = 2.2, StrokeColor = BLACK, X = LEFT, Color = rarityColor(e.Rarity), Position = c(36, 138), Size = Z(240, 40), ZIndex = z + 9 })
	else
		local title = if rw.Kind == "REQ" then "REQ" else (rw.Id .. " Crate")
		local amt = if rw.Kind == "REQ" then num(rw.Amount) else (rw.Count .. "x")
		self:_label(b, { Name = "Title", Text = title, TextSize = P(70), Stroke = 3.6, StrokeColor = th.TitleInk, Grad = th.Title, X = LEFT, Position = c(34, 18), Size = Z(370, 84), ZIndex = z + 9 })
		self:_label(b, { Name = "Amount", Text = amt, TextSize = P(64), Stroke = 3.4, StrokeColor = th.AmountInk, Grad = th.Amount, X = LEFT, Position = c(38, 96), Size = Z(320, 74), ZIndex = z + 9 })
	end
	local item = self:_item(b, rw, z + 1)
	local card = { B = b, Track = track, T = t, Rw = rw, Glow = glow, Flash = flash, Item = item, Motes = motes }
	local ck = new("ImageLabel", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = c(214, 282), Size = Z(250, 200), ZIndex = z + 10 }, b)
	skin(ck, "check")
	new("UIScale", { Name = "Pop" }, ck)
	card.Check = ck
	card.Lock = skin(new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, Position = c(30, 332), Size = Z(68, 83), ZIndex = z + 10 }, b), "lock")
	if rw.Kind == "Crate" then
		card.Odds = self:_btn(b, { Name = "Odds", Skin = "odds", Text = "Odds", Font = HS.MontX, TextSize = P(32), Stroke = 2.2, Ink = RGB(8, 20, 70), Position = c(240, 362), Size = Z(160, 52), Z = z + 10, Hover = 1.1, OnClick = function()
			if self.Env.Open then self.Env.Open("Cases") end
		end }).B
	end
	if e then
		local eye = new("ImageButton", { Name = "Eye", BackgroundTransparency = 1, AutoButtonColor = false, Position = c(322, 18), Size = Z(84, 84), ZIndex = z + 10 }, b)
		skin(eye, "eye")
		HS.press(eye, function() self:_preview(rw.Key) end, { Hover = 1.12, Press = 0.9, Sound = "Click" })
	end
	card.Claim = self:_btn(b, { Name = "Claim", Skin = "claim", Text = "CLAIM!", TextSize = P(56), Stroke = 3.4, Ink = RGB(10, 36, 4), AnchorPoint = V2(0.5, 0.5), Position = c(212, 445), Size = Z(290, 92), Z = z + 11, Sound = false, OnClick = function()
		self:_claim(track, t)
	end }).B
	HS.press(b, function()
		if self.Dragged then return end
		if card.Can then
			self:_claim(track, t)
		elseif e then
			self:_preview(rw.Key)
		end
	end, { Hover = 1.03, Press = 0.97, Sound = false })
	self.Cards[track .. t] = card
	return card
end

function SP:_trackLabel(parent, track)
	local HS = self.HS
	local new = HS.new
	local th = TXT[track]
	local b = self:_cardShell(parent, track, O((LABEL_X - PX0) * SC, (ROW_Y[track] - PY0) * SC), track .. "Label")
	local z = 30
	self:_label(b, { Name = "Title", Text = track, TextSize = P(84), Stroke = 4, StrokeColor = th.TitleInk, Grad = th.Title, Position = c(0, 30), Size = Z(CARD_W, 96), ZIndex = z + 9 })
	local rays = new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = if track == "Free" then WHITE else RGB(255, 222, 120), ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = c(212, 285), Size = Z(440, 440), ZIndex = z + 1 }, b)
	local bloom = new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = if track == "Free" then RGB(220, 230, 255) else RGB(255, 200, 80), ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = c(212, 290), Size = Z(380, 300), ZIndex = z + 1 }, b)
	local shadow = new("ImageLabel", { Name = "MascotShadow", BackgroundTransparency = 1, Image = MASCOT[track], ImageColor3 = BLACK, ImageTransparency = 0.5, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(222, 304), Size = Z(300, 300), ZIndex = z + 2 }, b)
	local mh = new("Frame", { Name = "MascotHolder", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = c(212, 290), Size = Z(300, 300), ZIndex = z + 3 }, b)
	local pop = new("UIScale", { Name = "Pop" }, mh)
	new("ImageLabel", { Name = "Mascot", BackgroundTransparency = 1, Image = MASCOT[track], ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = z + 3 }, mh)
	self:_maskSweep(mh, track, z + 4, false, false, 0.6, 3.8)
	local fx = new("Frame", { Name = "MascotFx", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(P(14), P(14)), Size = Z(CARD_W - 28, CARD_H - 28), ZIndex = z + 4 }, b)
	if track == "Premium" then
		self:_embers(fx, 18, RGB(255, 240, 160), RGB(255, 168, 40), P(9), z + 4)
		self:_twinkles(fx, 7, RGB(255, 242, 190), P(38), z + 5)
	else
		self:_embers(fx, 12, RGB(240, 244, 255), RGB(150, 200, 255), P(7), z + 4)
		self:_twinkles(fx, 5, WHITE, P(32), z + 5)
	end
	local rec = { H = mh, Pop = pop, Base = c(212, 290), Shadow = shadow, Rays = rays, Bloom = bloom, Phase = if track == "Premium" then 1.7 else 0, Hover = 0, HoverT = 0 }
	table.insert(self.Mascots, rec)
	b.MouseEnter:Connect(function() rec.HoverT = 1 end)
	b.MouseLeave:Connect(function() rec.HoverT = 0 end)
	if track == "Premium" then
		local pr = Shop.ByKey[Pass.Products.Premium]
		self.GetPremium = self:_btn(b, { Name = "Get", Skin = "get", Text = "UNLOCK  " .. ROBUX .. " " .. num(pr and pr.Robux or 0), TextSize = P(48), Stroke = 3.2, Ink = RGB(36, 10, 76), AnchorPoint = V2(0.5, 0.5), Position = c(212, 445), Size = Z(330, 92), Z = 41, OnClick = function()
			self:_buy(Pass.Products.Premium)
		end })
		self.PremiumOn = self:_label(b, { Name = "Active", Text = "ACTIVE", Font = HS.MontX, TextSize = P(38), Stroke = 2.6, StrokeColor = RGB(10, 36, 4), Color = RGB(176, 255, 110), Position = c(0, 385), Size = Z(CARD_W, 48), ZIndex = 40 })
		HS.press(b, function()
			if not self:_attr("PassPremium") then self:_buy(Pass.Products.Premium) end
		end, { Hover = 1.03, Press = 0.97, Sound = false })
	end
	return b
end

function SP:_node(parent, t, x)
	local HS = self.HS
	local s = P(150)
	local f = HS.new("ImageLabel", { Name = "Node" .. t, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(x * SC, (LINE_Y - LINE_TOP) * SC), Size = O(s, s), ZIndex = 30 }, parent)
	skin(f, "node_off")
	local lab = HS.text(f, { Name = "N", Text = tostring(t), TextSize = P(54), Color = RGB(74, 46, 6), Stroke = 2, StrokeColor = RGB(255, 244, 190), Position = O(0, -P(4)), Size = S(1, 1), ZIndex = 31 })
	self.Nodes[t] = { F = f, L = lab }
end

------------------------------------------------------------------ build
function SP:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "SeasonPassHS2", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(CW, CH), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit
	local panel = self:_panel(fit)
	local function PR(x, y) return O((x - PX0) * SC, (y - PY0) * SC) end

	-- title + emblem breaking the top-left corner
	new("ImageLabel", { Name = "TitleGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 170, 60), ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = R(300, 215), Size = Z(320, 260), ZIndex = 45 }, fit)
	local eh = new("Frame", { Name = "TitleEmblem", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = R(275, 207), Size = Z(250, 222), ZIndex = 47 }, fit)
	local core = new("ImageLabel", { Name = "CoreGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(176, 120, 255), ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.47), Size = S(1.25, 1.15), ZIndex = 46 }, eh)
	new("ImageLabel", { Name = "TitleIcon", BackgroundTransparency = 1, Image = MASCOT.Title, ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = 47 }, eh)
	self:_maskSweep(eh, "Title", 48, false, false, 0.75, 4.2)
	local sparks = new("Frame", { Name = "Sparks", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.4, 1.3), ZIndex = 48 }, eh)
	self:_twinkles(sparks, 7, RGB(206, 176, 255), P(44), 48)
	self.Emblem = { H = eh, Core = core, Base = R(275, 207) }
	-- neon cable corners (top-right mirrored in X, bottom-left mirrored in Y), behind the buttons
	local cw, ch = 420, 412
	local function corner(name, pos, fx, fy)
		local h = new("Frame", { Name = name, BackgroundTransparency = 1, Position = pos, Size = Z(cw, ch), ZIndex = 45 }, fit)
		local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(170, 90, 255), ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = S(if fx then 0.78 else 0.22, if fy then 0.78 else 0.22), Size = S(0.95, 0.95), ZIndex = 44 }, h)
		new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = CORNER, ImageRectOffset = V2(if fx then CORNER_W else 0, if fy then CORNER_H else 0), ImageRectSize = V2(if fx then -CORNER_W else CORNER_W, if fy then -CORNER_H else CORNER_H), Size = S(1, 1), ZIndex = 45 }, h)
		local mk, g = self:_maskSweep(h, "Corner", 45, fx, fy, 0.8, 2.8)
		mk.ImageColor3 = RGB(160, 244, 255)
		g.Rotation = if fx == fy then 45 else 135
		local spots = {}
		for _, p in CRYSTALS do table.insert(spots, { if fx then 1 - p[1] else p[1], if fy then 1 - p[2] else p[2] }) end
		self:_twinkles(h, #spots, RGB(255, 226, 255), P(48), 46, spots)
		table.insert(self.Corners, { H = h, Glow = glow, Base = pos, P = math.random() * 6 })
	end
	corner("CornerTR", R(PX1 + 40 - cw, PY0 - 44), true, false)
	corner("CornerBL", R(PX0 - 42, PY1 + 44 - ch), false, true)
	local title = self:_label(fit, { Name = "Title", Text = "Season Pass", TextSize = P(172), Stroke = 7, StrokeColor = RGB(46, 18, 4), Grad = CS({ CK(0, RGB(255, 250, 226)), CK(0.5, RGB(255, 206, 110)), CK(1, RGB(255, 140, 40)) }), X = LEFT, Fit = false, Position = R(392, 92), Size = Z(1100, 190), DropY = P(9), ZIndex = 47 })
	local shine = HS.text(fit, { Name = "TitleShine", Text = "Season Pass", TextSize = P(172), Color = WHITE, X = LEFT, Fit = false, Position = R(392, 92), Size = Z(1100, 190), ZIndex = 48 })
	local sg = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 0.55), NK(0.5, 0.25), NK(0.52, 0.55), NK(0.58, 1), NK(1, 1) }) }, shine)
	table.insert(self.Sweeps, { G = sg, P = 1, Period = 5 })
	local chip = new("ImageLabel", { Name = "SeasonChip", BackgroundTransparency = 1, Position = R(1258, 152), Size = Z(300, 78), ZIndex = 46 }, fit)
	skin(chip, "pill")
	chip.ImageColor3 = RGB(130, 220, 255)
	self:_label(chip, { Text = string.upper(Pass.Name), Font = HS.MontX, TextSize = P(36), Stroke = 2.6, StrokeColor = RGB(6, 20, 50), Position = O(0, -P(4)), Size = S(1, 1), ZIndex = 47 })

	-- CLAIM ALL + REQ pill + X (top edge)
	self.ClaimAll = self:_btn(fit, { Name = "ClaimAll", Skin = "claimall", Text = "CLAIM ALL", TextSize = P(52), Stroke = 3.2, Ink = RGB(10, 36, 4), Position = R(1930, 138), Size = Z(400, 104), Z = 46, Sound = false, OnClick = function()
		self:_claim("All")
	end })
	local cur = new("ImageLabel", { Name = "Currency", BackgroundTransparency = 1, Position = R(2440, 138), Size = Z(330, 104), ZIndex = 46 }, fit)
	skin(cur, "pill")
	self:_sweep(cur, O(P(14), P(12)), Z(302, 72), UDim.new(0.5, 0), 46, 0.35)
	new("ImageLabel", { Name = "IconGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(90, 180, 255), ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = c(20, 48), Size = Z(200, 160), ZIndex = 46 }, cur)
	new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = REQ_ICON, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(24, 46), Size = Z(150, 150), ZIndex = 48 }, cur)
	self.ReqText = self:_label(cur, { Name = "Value", Text = "0", Font = HS.MontX, TextSize = P(54), Stroke = 3, Position = c(100, -6), Size = Z(220, 104), ZIndex = 48 })
	self:_btn(fit, { Name = "Close", Skin = "close", AnchorPoint = V2(0.5, 0.5), Position = R(2862, 196), Size = Z(124, 124), Z = 48, Hover = 1.08, Sound = "Click", OnClick = function()
		if self.Env.Close then self.Env.Close() end
	end })

	-- tier strip
	local strip = new("ImageLabel", { Name = "TierStrip", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(40, 40, 200, 100), SliceScale = 0.6, Position = PR(355, 280), Size = Z(2420, 130), ZIndex = 24 }, panel)
	skin(strip, "strip")
	self.TierText = self:_label(strip, { Name = "Tier", Text = "Tier 0", TextSize = P(76), Stroke = 4, StrokeColor = RGB(46, 18, 4), Grad = CS(RGB(255, 226, 140), RGB(255, 140, 40)), X = LEFT, Position = c(48, -6), Size = Z(380, 130), ZIndex = 27 })
	local xb = new("ImageLabel", { Name = "XPTrack", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.55, Position = c(425, 30), Size = Z(1595, 64), ZIndex = 25 }, strip)
	skin(xb, "track")
	self.XPFill = new("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.55, Position = O(P(5), P(5)), Size = Z(600, 54), ZIndex = 26 }, xb)
	skin(self.XPFill, "fill")
	new("UIGradient", { Color = CS(RGB(226, 92, 24), RGB(255, 200, 104)) }, self.XPFill)
	self.XPSweep = self:_sweep(self.XPFill, O(P(6), P(4)), UDim2.new(1, -P(12), 0, P(26)), UDim.new(0.5, 0), 26, 0.45)
	self.XPText = self:_label(xb, { Name = "XP", Text = "", TextSize = P(52), Stroke = 3.2, X = LEFT, Position = c(34, -2), Size = Z(900, 64), ZIndex = 28 })
	self.PctText = self:_label(xb, { Name = "Pct", Text = "", TextSize = P(52), Stroke = 3.2, X = RIGHT, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -P(30), 0, -P(2)), Size = Z(260, 64), ZIndex = 28 })
	self.DaysText = self:_label(strip, { Name = "Days", Text = "", TextSize = P(58), Stroke = 3.4, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -P(40), 0, -P(4)), Size = Z(360, 130), ZIndex = 27 })

	-- track labels
	self:_trackLabel(panel, "Free")
	self:_trackLabel(panel, "Premium")

	-- timeline (own clip, scrolls with the cards)
	local lclip = new("Frame", { Name = "LineClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = PR(LINE_X0, LINE_TOP), Size = Z(LINE_X1 - LINE_X0, 160), ZIndex = 29 }, panel)
	local ltrack = new("Frame", { Name = "Track", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 29 }, lclip)
	self.LineTrack = ltrack
	local total = NODE0 + (Pass.MaxTier - 1) * PITCH + 300
	local rail = new("ImageLabel", { Name = "Rail", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.3, AnchorPoint = V2(0, 0.5), Position = O(0, (LINE_Y - LINE_TOP) * SC), Size = O(total * SC, P(30)), ZIndex = 29 }, ltrack)
	skin(rail, "linetrack")
	self.LineFill = new("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.3, AnchorPoint = V2(0, 0.5), Position = O(0, (LINE_Y - LINE_TOP) * SC), Size = O(0, P(30)), ZIndex = 29 }, ltrack)
	skin(self.LineFill, "line")
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 246, 150), RGB(250, 206, 70)) }, self.LineFill)
	for t = 1, Pass.MaxTier do
		self:_node(ltrack, t, NODE0 + (t - 1) * PITCH)
	end

	-- card rows
	local cclip = new("Frame", { Name = "CardClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = PR(CLIP_X0, CLIP_Y0), Size = Z(CLIP_X1 - CLIP_X0, CLIP_Y1 - CLIP_Y0), ZIndex = 32 }, panel)
	local ctrack = new("Frame", { Name = "Track", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 30 }, cclip)
	self.CardTrack = ctrack
	for t = 1, Pass.MaxTier do
		local xx = (FIRST + (t - 1) * PITCH) * SC
		self:_card(ctrack, "Free", t, O(xx, (ROW_Y.Free - CLIP_Y0) * SC))
		self:_card(ctrack, "Premium", t, O(xx, (ROW_Y.Premium - CLIP_Y0) * SC))
	end
	for _, area in { cclip, lclip } do
		area.InputChanged:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseWheel then
				self:_scrollTo(self.Off - io.Position.Z * PITCH)
			end
		end)
		area.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
				self.Drag = { X = io.Position.X, Off = self.Off }
				self.Dragged = false
			end
		end)
	end
	UserInputService.InputChanged:Connect(function(io)
		local d = self.Drag
		if d and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			local dx = (io.Position.X - d.X) / math.max(self.Fit.Scale * SC, 0.05)
			if math.abs(dx) > 14 then self.Dragged = true end
			if self.Dragged then self.Off = math.clamp(d.Off - dx, 0, OFF_MAX) end
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if self.Drag and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
			self.Drag = nil
			task.delay(0.05, function() self.Dragged = false end)
		end
	end)

	-- arrows
	self.Left = self:_btn(fit, { Name = "ArrowL", Skin = "arrow_l", Position = R(200, 890), Size = Z(155, 155), Z = 48, Hover = 1.08, Sound = "Tab", OnClick = function()
		self:_scrollTo(self.Off - 4 * PITCH)
	end })
	self.Right = self:_btn(fit, { Name = "ArrowR", Skin = "arrow_r", Position = R(2770, 890), Size = Z(155, 155), Z = 48, Hover = 1.08, Sound = "Tab", OnClick = function()
		self:_scrollTo(self.Off + 4 * PITCH)
	end })

	-- footer: skips + gift squares (straddle the panel's bottom edge)
	local function skip(x0, key, label, sk, gx)
		local pr = Shop.ByKey[key]
		local b = self:_btn(fit, { Name = key, Skin = sk, Text = label .. "  " .. ROBUX .. " " .. num(pr and pr.Robux or 0), TextSize = P(60), Stroke = 3.6, Position = R(x0, 1655), Size = Z(502, 138), Z = 48, OnClick = function()
			self:_buy(key)
		end })
		self:_btn(fit, { Name = "Gift" .. key, Skin = "gift", Position = R(gx, 1655), Size = Z(133, 138), Z = 48, Hover = 1.08, OnClick = function()
			self:_toast("Gifting soon", "Gifting tier skips to friends is coming soon")
		end })
		if pr and pr.Was then
			local w = self:_label(fit, { Name = "Was" .. key, Text = ROBUX .. " " .. num(pr.Was), TextSize = P(54), Stroke = 3, StrokeColor = RGB(50, 4, 6), Grad = CS(RGB(255, 110, 110), RGB(220, 30, 40)), AnchorPoint = V2(0.5, 0.5), Position = R(x0 + 251, 1822), Size = Z(300, 66), ZIndex = 47 })
			new("Frame", { Name = "Strike", BackgroundColor3 = RGB(255, 50, 60), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.52), Size = O(P(220), P(7)), Rotation = -7, ZIndex = 49 }, w)
		end
		b.Default = sk
		return b
	end
	self.Skips = {
		skip(515, Pass.Products.Skip1, "Skip 1", "skip_purple", 1035),
		skip(1230, Pass.Products.Skip5, "Skip 5", "skip_orange", 1755),
		skip(1950, Pass.Products.SkipAll, "Skip ALL", "skip_teal", 2472),
	}

	-- skin preview overlay
	local ov = new("TextButton", { Name = "Preview", Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, Position = O(-600, -400), Size = UDim2.new(1, 1200, 1, 800), Visible = false, ZIndex = 70 }, fit)
	self.Preview = ov
	local box = new("ImageLabel", { Name = "Box", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.52, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(900, 640), ZIndex = 71 }, ov)
	skin(box, "panel")
	self.PrevRimGrad = new("UIGradient", { Rotation = 35 }, box)
	local bin = new("Frame", { BackgroundColor3 = RGB(26, 12, 46), BorderSizePixel = 0, Position = O(10, 10), Size = UDim2.new(1, -20, 1, -20), ZIndex = 70 }, box)
	HS.corner(bin, 24)
	self.PrevRays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(760, 760), ZIndex = 71 }, box)
	self.PrevBloom = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(640, 400), ZIndex = 71 }, box)
	self.PrevVP = new("ViewportFrame", { BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(760, 460), ZIndex = 72 }, box)
	self.PrevName = self:_label(box, { Text = "", TextSize = 56, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = O(840, 64), ZIndex = 74 })
	self.PrevSub = self:_label(box, { Text = "", Font = HS.MontX, TextSize = 30, Stroke = 2.6, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Size = O(840, 40), ZIndex = 74 })
	self.PrevGrad = new("UIGradient", {}, self.PrevSub)
	self.PrevNote = self:_label(box, { Text = "", Font = HS.MontX, TextSize = 24, Stroke = 2.2, Color = RGB(214, 200, 240), AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -104), Size = O(840, 32), ZIndex = 74 })
	self:_btn(box, { Name = "Back", Skin = "back", Text = "BACK", TextSize = 36, Stroke = 3, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = O(220, 68), Z = 75, OnClick = function()
		self:_closePreview()
	end })
	HS.press(ov, function() self:_closePreview() end, { Hover = 1, Press = 1, Sound = false })

	self:_buildToast()
end

------------------------------------------------------------------ toast
function SP:_buildToast()
	local HS = self.HS
	local parent = self.Env.ToastParent or (player and player:WaitForChild("PlayerGui"))
	if not parent then return end
	local gui = HS.new("ScreenGui", { Name = "PassToast", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70 }, parent)
	local f = HS.new("ImageLabel", { Name = "Toast", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.35, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, -180), Size = O(620, 112), ZIndex = 2 }, gui)
	skin(f, "panel")
	f.ImageColor3 = RGB(176, 110, 255)
	local bg = HS.new("Frame", { BackgroundColor3 = RGB(26, 12, 46), BorderSizePixel = 0, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 1 }, f)
	HS.corner(bg, 16)
	HS.new("UIScale", { Name = "Fit" }, f)
	self.ToastTitle = HS.text(f, { Text = "", TextSize = 34, Stroke = 3, StrokeColor = INK, X = LEFT, Position = O(30, 12), Size = O(560, 44), ZIndex = 3 })
	self.ToastText = HS.text(f, { Text = "", Font = HS.MontX, TextSize = 21, Stroke = 2, StrokeColor = INK, Color = RGB(214, 200, 240), X = LEFT, Position = O(30, 60), Size = O(560, 36), ZIndex = 3 })
	self.ToastFrame = f
end

function SP:_toast(title, text, good)
	local f = self.ToastFrame
	if not f then return end
	local vp = Workspace.CurrentCamera.ViewportSize
	f.Fit.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.5, 1.4)
	self.ToastTitle.Text, self.ToastText.Text = title, text
	self.ToastTitle.TextColor3 = if good then RGB(176, 255, 110) else RGB(255, 200, 90)
	self.ToastN = (self.ToastN or 0) + 1
	local n = self.ToastN
	self.HS.tween(f, 0.35, { Position = UDim2.new(0.5, 0, 0, 90) }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		if self.ToastN == n then
			self.HS.tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, -180) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end

------------------------------------------------------------------ actions
function SP:_buy(key)
	local it = Shop.ByKey[key]
	if not it then return end
	if (key == Pass.Products.Premium and self:_attr("PassPremium")) or ((tonumber(self:_attr("PassTier")) or 0) >= Pass.MaxTier and key ~= Pass.Products.Premium) then
		self.HS.sound("Deny")
		return
	end
	if (it.ProductId or 0) <= 0 or not player then
		self.HS.sound("Deny")
		self:_toast("Coming soon", it.Name .. " isn't on sale yet")
		return
	end
	MarketplaceService:PromptProductPurchase(player, it.ProductId)
end

function SP:_claim(track, t)
	if self.Busy or self.Env.Attr then return end
	local rf = Remotes:FindFirstChild("PassClaim")
	if not rf then return end
	self.Busy = true
	task.spawn(function()
		local ok, res = pcall(function() return rf:InvokeServer(track, t) end)
		self.Busy = false
		if ok and type(res) == "table" and res.Ok then
			local g = res.Granted or {}
			local text = if #g <= 3 then table.concat(g, " + ") else (#g .. " rewards claimed")
			if res.Note then text = text .. "  ·  " .. res.Note end
			self:_toast(if #g > 1 then "Rewards claimed!" else "Reward claimed!", text, true)
		else
			self.HS.sound("Deny")
			if ok and type(res) == "table" and res.Error and res.Error ~= "Nothing to claim" then
				self:_toast("Couldn't claim", tostring(res.Error))
			end
		end
	end)
end

function SP:_scrollTo(off)
	self.Off = math.clamp(off, 0, OFF_MAX)
end

function SP:_preview(key)
	local e = skinInfo[key]
	if not e then return end
	self.HS.sound("Select")
	local col = rarityColor(e.Rarity)
	self.PrevName.Text = spaced(e.Skin)
	self.PrevSub.Text = string.upper(e.Weapon .. " · " .. e.Rarity)
	local d = chroma(e.Rarity)
	self.PrevGrad.Color = if d and d.Grad then d.Grad else CS(col, hsv(col, 0.55, 1))
	self.PrevRimGrad.Color = if d and d.Grad then d.Grad else CS(col, hsv(col, 0.55, 1))
	self.PrevRays.ImageColor3, self.PrevBloom.ImageColor3 = col, col
	local owned = false
	for k in tostring(self:_attr("OwnedSkins") or ""):gmatch("[^,]+") do
		if k == key then owned = true end
	end
	self.PrevNote.Text = if owned then "Already owned: claiming it pays REQ instead" else "Season Pass reward"
	local ok, m = pcall(K.weapon, e.Weapon, e.Skin)
	self.Spin = nil
	if ok and m then
		local ctr = frameUniform(self.PrevVP, m, 0, 1.0)
		if ctr then self.Spin = { M = m, C = ctr, Base = m:GetPivot(), Yaw = 0 } end
	end
	self.Preview.Visible = true
end

function SP:_closePreview()
	self.Preview.Visible = false
	self.Spin = nil
	self.PrevVP:ClearAllChildren()
end

------------------------------------------------------------------ state
function SP:_claimed()
	local s = tostring(self:_attr("PassClaimed") or "")
	local a, b = s:match("^([^|]*)|?(.*)$")
	local F, Pm = {}, {}
	for n in (a or ""):gmatch("%d+") do F[tonumber(n)] = true end
	for n in (b or ""):gmatch("%d+") do Pm[tonumber(n)] = true end
	return F, Pm
end

function SP:_refresh()
	local tier, into = Pass.TierOf(tonumber(self:_attr("PassXP")) or 0)
	local prem = self:_attr("PassPremium") == true
	local F, Pm = self:_claimed()
	local count = 0
	local visible = self.Root.Visible
	local popped = false
	for key, cd in self.Cards do
		local done = if cd.Track == "Free" then F[cd.T] == true else Pm[cd.T] == true
		local can = cd.T <= tier and not done and (cd.Track == "Free" or prem)
		cd.Can = can
		if can then count += 1 end
		cd.Check.Visible = done
		cd.Lock.Visible = not done and not can
		cd.Claim.Visible = can
		cd.Motes.Visible = can
		if cd.Odds then cd.Odds.Visible = not can end
		if cd.Item and cd.Item:IsA("ImageLabel") then cd.Item.ImageTransparency = if done then 0.25 else 0 end
		self.Glows[key] = if can then cd.Glow else nil
		if not can then cd.Glow.ImageTransparency = 1 end
		if done and self.Prev[key] == false and visible then
			popped = true
			local pop = cd.Check:FindFirstChild("Pop")
			if pop then
				pop.Scale = 0.2
				self.HS.tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			cd.Flash.BackgroundTransparency = 0.1
			self.HS.tween(cd.Flash, 0.5, { BackgroundTransparency = 1 })
		end
		self.Prev[key] = done
	end
	if popped then self.HS.sound("Purchase") end
	for t, nd in self.Nodes do
		local on = t <= tier
		skin(nd.F, if on then "node_on" else "node_off")
		nd.L.TextColor3 = if on then RGB(74, 46, 6) else RGB(46, 40, 20)
		local st = nd.L:FindFirstChildOfClass("UIStroke")
		if st then st.Color = if on then RGB(255, 244, 190) else RGB(150, 140, 96) end
	end
	local frac = into / Pass.TierXP
	local fillX
	if tier >= Pass.MaxTier then
		fillX = NODE0 + (Pass.MaxTier - 1) * PITCH + 300
	elseif tier <= 0 then
		fillX = NODE0 * frac
	else
		fillX = NODE0 + (tier - 1) * PITCH + frac * PITCH
	end
	self.LineFill.Size = O(math.max(fillX, 40) * SC, P(30))
	self.TierText.Text = if tier >= Pass.MaxTier then "Tier " .. tier .. " MAX" else "Tier " .. tier
	local full = P(1585)
	if tier >= Pass.MaxTier then
		self.XPText.Text = "MAX TIER"
		self.PctText.Text = "100%"
		self.XPFill.Size = O(full, P(54))
	else
		self.XPText.Text = num(into) .. " / " .. num(Pass.TierXP) .. " XP"
		self.PctText.Text = math.floor(frac * 100) .. "%"
		self.XPFill.Size = O(math.max(full * frac, P(60)), P(54))
	end
	self.ReqText.Text = num(tonumber(self:_attr("REQ")) or 0)
	self.GetPremium.B.Visible = not prem
	self.PremiumOn.Visible = prem
	self.ClaimAll.B.Visible = count > 0
	self.ClaimAll.T.Text = "CLAIM ALL (" .. count .. ")"
	for _, sk in self.Skips do
		local off = tier >= Pass.MaxTier
		self.HS.setDisabled(sk.B, off)
		skin(sk.B, if off then "skip_grey" else sk.Default)
	end
	self.Tier, self.Count = tier, count
	if self.Env.Badge then pcall(self.Env.Badge, if count > 0 then count else nil) end
end

function SP:_days()
	local left = Pass.EndsAt - Workspace:GetServerTimeNow()
	if left <= 0 then
		self.DaysText.Text = "Season Ended"
	elseif left >= 86400 then
		local d = math.floor(left / 86400)
		self.DaysText.Text = d .. (if d == 1 then " Day Left!" else " Days Left!")
	else
		self.DaysText.Text = string.format("%dh %02dm Left!", left // 3600, (left % 3600) // 60)
	end
end

function SP:_place()
	self.CardTrack.Position = O(-self.Cur * SC, 0)
	self.LineTrack.Position = O(-self.Cur * SC, 0)
	-- both arrows always show (Hypershot); at an end they just dim
	self.Left.B.ImageColor3 = if self.Off > 1 then WHITE else RGB(150, 150, 150)
	self.Right.B.ImageColor3 = if self.Off < OFF_MAX - 1 then WHITE else RGB(150, 150, 150)
end

function SP:_step(dt)
	local t = os.clock()
	self.Cur += (self.Off - self.Cur) * math.min(1, dt * 12)
	if math.abs(self.Off - self.Cur) < 0.3 then self.Cur = self.Off end
	self:_place()
	for _, sw in self.Sweeps do
		local u = ((t + sw.P) % (sw.Period or 3.6)) / 0.9
		sw.G.Offset = V2(if u < 1 then -1 + 2 * u else 1, 0)
	end
	local a = 0.25 + 0.25 * math.sin(t * 4)
	for _, g in self.Glows do g.ImageTransparency = a end
	for _, m in self.Motes do
		if m.Holder.Visible then
			local u = (t * m.Spd + m.P) % 1
			m.I.Position = UDim2.new(m.X, math.sin((t + m.P * 6) * 2) * 6, 1 - u, 0)
			m.I.ImageTransparency = 0.2 + 0.8 * math.abs(u - 0.5) * 2
			m.I.Rotation = (t * 90 + m.P * 360) % 360
		end
	end
	for _, ch in self.Chromas do
		ch.G.Offset = V2(math.sin(t * 0.8) * 0.5, 0)
		ch.Face.ImageColor3 = hsv(K.chromaColor(ch.Def, t, 0), 1.05, 1)
	end
	if self.RimGrad then self.RimGrad.Rotation = 35 + (t * 14) % 360 end
	-- living art
	if self.Bands then -- Ken Burns drift through the band texture (1024x640), like the Shop key art
		local zz = 1.05 + 0.05 * (0.5 + 0.5 * math.sin(t * 0.31))
		local rw, rh = 1024 / zz, 640 / zz
		self.Bands.ImageRectSize = V2(rw, rh)
		self.Bands.ImageRectOffset = V2((1024 - rw) * (0.5 + math.sin(t * 0.19) * 0.45), (640 - rh) * (0.5 + math.cos(t * 0.15) * 0.45))
	end
	for i, nb in self.Nebula do
		nb.I.Position = nb.Base + UDim2.fromScale(math.sin(t * 0.13 + i * 2) * 0.06, math.cos(t * 0.11 + i) * 0.05)
		nb.I.ImageTransparency = nb.Tr + math.sin(t * 0.7 + i) * 0.07
	end
	if self.Emblem then
		local e = self.Emblem
		e.H.Position = e.Base + O(0, math.sin(t * 1.4) * P(8))
		e.H.Rotation = math.sin(t * 0.9) * 2.5
		e.Core.ImageTransparency = 0.28 + 0.22 * math.sin(t * 3.2)
	end
	for _, mc in self.Mascots do
		local tt = t + mc.Phase
		mc.Hover += (mc.HoverT - mc.Hover) * math.min(1, dt * 8)
		local up = 0.5 + 0.5 * math.sin(tt * 1.6)
		mc.H.Position = mc.Base + O(0, -P(12) * up)
		mc.H.Rotation = math.sin(tt * 1.1) * 3
		mc.Pop.Scale = 1 + 0.08 * mc.Hover
		mc.Shadow.ImageTransparency = 0.45 + 0.2 * up
		mc.Rays.Rotation = (tt * 8) % 360
		mc.Bloom.ImageTransparency = 0.28 + 0.14 * math.sin(tt * 2.2)
	end
	for _, cn in self.Corners do
		cn.Glow.ImageTransparency = 0.5 + 0.18 * math.sin(t * 1.8 + cn.P)
		cn.H.Position = cn.Base + O(math.sin(t * 0.7 + cn.P) * P(4), math.cos(t * 0.6 + cn.P) * P(4))
	end
	for _, e in self.Embers do
		e.Y -= e.V * dt
		if e.Y < -0.05 then
			e.Y, e.X = 1.05, math.random()
		end
		e.F.Position = UDim2.new(e.X, math.sin(t * 1.3 + e.Sway) * 6, e.Y, 0)
		e.F.BackgroundTransparency = 0.15 + 0.85 * math.clamp(1 - e.Y, 0, 1) ^ 2
	end
	for _, st in self.Twinkles do
		local a = math.max(0, math.sin((t + st.P) * st.Spd))
		st.I.Size = O(st.Sz * a, st.Sz * a)
		st.I.Rotation = (t * 40 + st.P * 60) % 360
		if not st.Fixed then
			if a <= 0.02 and not st.Moved then
				st.Moved = true
				st.I.Position = S(0.05 + math.random() * 0.9, 0.05 + math.random() * 0.9)
			elseif a > 0.1 then
				st.Moved = false
			end
		end
	end
	if self.Spin then
		local sp = self.Spin
		sp.Yaw += dt * 0.9
		sp.M:PivotTo(CFrame.new(sp.C) * CFrame.Angles(0, sp.Yaw, 0) * CFrame.new(-sp.C) * sp.Base)
		self.PrevRays.Rotation = (t * 10) % 360
	end
	if (self.NextDays or 0) < t then
		self.NextDays = t + 1
		self:_days()
	end
end

------------------------------------------------------------------ mount
function SP:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.42, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
	self.FitFrame.Position = UDim2.new(0.5, 0, 0.5, 6 * self.Fit.Scale)
end

function SP:OnShow()
	self:_fit()
	self:_closePreview()
	self:_refresh()
	local F, Pm = self:_claimed()
	local prem = self:_attr("PassPremium") == true
	local focus = math.min(Pass.MaxTier, (self.Tier or 0) + 1)
	for t = 1, self.Tier or 0 do
		if not F[t] or (prem and not Pm[t]) then
			focus = t
			break
		end
	end
	self.Off = math.clamp((focus - 1) * PITCH, 0, OFF_MAX)
	self.Cur = self.Off
	self:_place()
	self:_days()
end

function SP.Mount(layer, env)
	local s = SP.new(layer, env)
	return {
		Root = s.Root,
		OnShow = function() s:OnShow() end,
		Object = s,
	}
end

return SP
