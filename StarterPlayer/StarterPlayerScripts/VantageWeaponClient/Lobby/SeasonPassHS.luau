--!nocheck
--[[
	SeasonPassHS - VantageShot Season Pass modal (2026-11-17). Follows Hypershot's battlepass construction
	(user screenshot, measured in ref px and scaled x0.74):
	  title + emblem breaking the top-left, currency pill top-right, red X
	  tier strip     Tier N | XP bar (x / 1,000 XP, %) | Days Left
	  Free row       silver cards  (label card "Free" + tiers)
	  timeline       gold progress bar with numbered diamond nodes between the rows
	  Premium row    gold cards    (label card "Premium" + tiers)
	  arrows         chunky orange squares half outside the panel; wheel / drag also scroll
	  footer         Skip 1 / Skip 5 / Skip ALL (purple / orange / teal) + gift squares, struck-out "was" prices
	Card overlays: claimed check, CLAIM! pill, padlock, Odds chip (crates), eye preview (skins).
	Own 10%: violet neon panel, REQ, CLAIM ALL, GET premium on the Premium card, skin cards tinted by rarity.
	Data: PassConfig (ReplicatedStorage.Vantage.SeasonPass), server SeasonPassService, Remotes.PassClaim.
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

local GLOW = "rbxassetid://104786452938879"
local RAYS = "rbxassetid://113538852110620"
local BLOOM = "rbxassetid://103142630740394"
local REQ_ICON = "rbxassetid://115805213028426"
local BADGE = {
	Free = "rbxassetid://135855890564742", -- Silver
	Premium = "rbxassetid://105048808444395", -- Legend (crowned gold)
	Title = "rbxassetid://115001036884075", -- Elite (winged gold)
}

local function id(n) return "rbxassetid://" .. n end
-- rendered skins (sp_*.png in ~/roblox-game/vantage_vfx/hs, built by the season pass skin renderer)
local IMG = {
	SkipPurple = id(122806474423507), SkipOrange = id(78621689717496), SkipTeal = id(97938382155710), SkipGrey = id(70918593334893),
	Gift = id(77535673843531), Claim = id(76528258753692), ClaimAll = id(128794070186403), Get = id(94242394891722),
	Odds = id(120516280304960), ArrowL = id(131548320741217), ArrowR = id(127697174472703), Close = id(123378136837692),
	Eye = id(130872745481715), FaceSilver = id(111336833935915), FaceGold = id(97389271773016), FaceDark = id(108982291214344),
	FrameSilver = id(116415207313512), FrameGold = id(101526853169976), Check = id(116791301610552), Lock = id(80422637344824),
	NodeOn = id(112427494662580), NodeOff = id(83462642972170), Stripes = id(83980715940987),
}

-- geometry: Hypershot ref px, composition origin at ref (150, 95)
local SC = 0.74
local OX, OY = 150, 95
local CW, CH = 2170 * SC, 1355 * SC
local function R(x, y) return O((x - OX) * SC, (y - OY) * SC) end
local function Z(w, h) return O(w * SC, h * SC) end
local function P(v) return v * SC end
local function c(x, y) return O(x * SC, y * SC) end -- local (inside a card)

local CARD_W, CARD_H, PITCH = 333, 344, 357
local CLIP_X0, CLIP_X1, CLIP_Y0, CLIP_Y1 = 630, 2236, 300, 1236
local LINE_X0, LINE_X1, LINE_Y = 288, 2180, 763
local ROW_Y = { Free = 348, Premium = 828 }
local FIRST = 13 -- first card x inside the card clip
local NODE0 = (CLIP_X0 - LINE_X0) + FIRST + CARD_W / 2 -- tier 1 node x inside the line clip
local VISIBLE = (CLIP_X1 - CLIP_X0)
local OFF_MAX = math.max(0, FIRST + (Pass.MaxTier - 1) * PITCH + CARD_W + 14 - VISIBLE)

local C = {
	Panel = RGB(22, 9, 42), Dots = RGB(12, 4, 26), Neon = RGB(170, 100, 255), Ink = RGB(12, 6, 24), Muted = RGB(206, 192, 232),
}
local PAL = {
	Green = { Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(96, 206, 52), Ink = RGB(25, 45, 12) },
	Purple = { Rim = RGB(46, 16, 96), Top0 = RGB(196, 132, 255), Top1 = RGB(122, 56, 236), Ink = RGB(36, 10, 76) },
	Orange = { Rim = RGB(112, 44, 6), Top0 = RGB(255, 196, 84), Top1 = RGB(242, 110, 26), Ink = RGB(80, 30, 4) },
	Teal = { Rim = RGB(8, 74, 84), Top0 = RGB(130, 252, 240), Top1 = RGB(34, 196, 206), Ink = RGB(6, 56, 64) },
	Blue = { Rim = RGB(18, 40, 108), Top0 = RGB(112, 190, 255), Top1 = RGB(50, 112, 236), Ink = RGB(12, 28, 80) },
	Grey = { Rim = RGB(46, 44, 58), Top0 = RGB(160, 156, 176), Top1 = RGB(116, 112, 132), Ink = RGB(30, 28, 40) },
	Arrow = { Rim = RGB(104, 40, 6), Top0 = RGB(255, 200, 104), Top1 = RGB(240, 128, 36), Ink = RGB(90, 34, 4) },
}
local TRACK = {
	Free = {
		Face = CS({ CK(0, RGB(238, 240, 246)), CK(0.5, RGB(170, 174, 186)), CK(1, RGB(118, 122, 136)) }),
		Rim = RGB(248, 250, 255), Title = RGB(244, 244, 250), TitleInk = RGB(36, 38, 48),
		Amount = RGB(255, 182, 52), AmountInk = RGB(70, 34, 4),
	},
	Premium = {
		Face = CS({ CK(0, RGB(255, 234, 128)), CK(0.5, RGB(238, 176, 44)), CK(1, RGB(196, 122, 18)) }),
		Rim = RGB(255, 238, 150), Title = RGB(255, 232, 96), TitleInk = RGB(72, 38, 4),
		Amount = RGB(255, 150, 36), AmountInk = RGB(72, 30, 2),
	},
}

local skinInfo = {}
for _, list in Config.Pool().ByTier do
	for _, e in list do skinInfo[e.Key] = e end
end
local function tierColor(r) return Config.TierColor[r] or WHITE end
local function hsv(col, s, v)
	local h, s0 = col:ToHSV()
	return Color3.fromHSV(h, math.clamp(s0 * s, 0, 1), v)
end
local function num(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function spaced(s) return (s:gsub("(%l)(%u)", "%1 %2")) end

-- world AABB of a model (visible parts)
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
local function frameGun(vp, m, tilt, fill)
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
	vp.Ambient = RGB(215, 215, 228)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-0.35, -0.6, -1)
	m.Parent = vp
	return ctr
end

local SP = {}
SP.__index = SP

function SP.new(layer, env)
	local self = setmetatable({
		Env = env, HS = env.HS, Cards = {}, Nodes = {}, Off = 0, Cur = 0, Busy = false, Prev = {}, Glows = {},
		Drag = nil, Dragged = false, Spin = nil, Sweeps = {},
	}, SP)
	self:_build(layer)
	RunService.RenderStepped:Connect(function(dt)
		if self.Root.Visible then self:_step(dt) end
	end)
	player.AttributeChanged:Connect(function(a)
		if a:sub(1, 4) == "Pass" or a == "REQ" or a == "OwnedSkins" then
			self:_refresh()
		end
	end)
	task.defer(function() self:_refresh() end)
	return self
end

------------------------------------------------------------------ kit
function SP:_text(parent, p)
	p.Stroke = p.Stroke or 2.6
	p.StrokeColor = p.StrokeColor or C.Ink
	p.ZIndex = p.ZIndex or 34
	return self.HS.text(parent, p)
end

-- rendered button skin (rim, lip, gradient face, halftone, streaks, gloss) + live label + sweeping light streak
function SP:_pill(parent, p)
	local HS, z = self.HS, p.Z or 34
	local b = HS.new("ImageButton", { Name = p.Name or "Pill", Image = p.Skin or IMG.SkipGrey, BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	local sw = HS.new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = UDim2.new(0.035, 0, 0.07, 0), Size = UDim2.new(0.93, 0, 0.68, 0), ZIndex = z }, b)
	HS.corner(sw, UDim.new(0.2, 0))
	local g = HS.new("UIGradient", { Rotation = 20, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.4, 1), NK(0.48, 0.6), NK(0.5, 0.38), NK(0.52, 0.6), NK(0.6, 1), NK(1, 1) }) }, sw)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.4 })
	local t
	if p.Text then
		t = self:_text(b, { Name = "Label", Text = p.Text, Rich = p.Rich, TextSize = p.TextSize or 30, Stroke = p.TextStroke or 2.8, StrokeColor = p.Pal and p.Pal.Ink or RGB(20, 10, 30), Position = O(0, -0.075 * p.Size.Y.Offset), Size = S(1, 1), ZIndex = z + 1 })
	end
	self.HS.press(b, p.OnClick, { Hover = p.Hover or 1.06, Press = 0.94, Sound = p.Sound })
	return { B = b, T = t, G = g }
end

-- one shape drawn as an outline layer under a fill layer, so overlapping parts share one outline
local function bar(parent, x0, y0, x1, y1, th, col, z, name)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	local f = Instance.new("Frame")
	f.Name = name or "Seg"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = col
	f.AnchorPoint = V2(0.5, 0.5)
	f.Position = O((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = O(len + th, th)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.ZIndex = z
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0.5, 0)
	cr.Parent = f
	f.Parent = parent
	return f
end

-- rendered glossy check / padlock / eye button
function SP:_check(parent, pos, w, z)
	local f = self.HS.new("ImageLabel", { Name = "Check", BackgroundTransparency = 1, Image = IMG.Check, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = pos, Size = O(w, w * 0.8), ZIndex = z }, parent)
	self.HS.new("UIScale", { Name = "Pop" }, f)
	return f
end

function SP:_lock(parent, pos, w, z)
	return self.HS.new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, Image = IMG.Lock, ScaleType = Enum.ScaleType.Fit, Position = pos, Size = O(w, w * 1.25), ZIndex = z }, parent)
end

function SP:_eye(parent, pos, w, z, onClick)
	local b = self.HS.new("ImageButton", { Name = "Eye", Image = IMG.Eye, BackgroundTransparency = 1, AutoButtonColor = false, Position = pos, Size = O(w, w), ZIndex = z }, parent)
	self.HS.press(b, onClick, { Hover = 1.12, Press = 0.9, Sound = "Click" })
	return b
end

-- neon panel (same construction as InventoryHS)
function SP:_panel(parent, name, pos, size)
	local HS = self.HS
	local new = HS.new
	local w, h = size.X.Offset, size.Y.Offset
	new("ImageLabel", { Name = name .. "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = C.Neon, ImageTransparency = 0.25, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.9, Position = O(pos.X.Offset - 64, pos.Y.Offset - 64), Size = O(w + 128, h + 128), ZIndex = 20 }, parent)
	local p = new("Frame", { Name = name, BackgroundColor3 = C.Panel, Position = pos, Size = size, ZIndex = 20 }, parent)
	HS.corner(p, 30)
	HS.stroke(p, 9, RGB(30, 8, 60)).Name = "Outer"
	local inner = new("Frame", { Name = "Rim", BackgroundTransparency = 1, Position = O(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 21 }, p)
	HS.corner(inner, 28)
	local st = HS.stroke(inner, 6, WHITE)
	self.Rim = new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(222, 168, 255)), CK(0.5, RGB(150, 72, 255)), CK(1, RGB(222, 168, 255)) }) }, st)
	local dots = new("Frame", { Name = "Dots", BackgroundColor3 = C.Dots, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 20 }, p)
	HS.corner(dots, 30)
	local kp = {}
	for k = 0, 18 do table.insert(kp, NK(k / 18, if k % 2 == 0 then 1 else 0.55)) end
	new("UIGradient", { Rotation = 35, Transparency = NS(kp) }, dots)
	return p
end

------------------------------------------------------------------ cards
function SP:_icon(card, rw, z)
	local HS = self.HS
	local new = HS.new
	if rw.Kind == "REQ" then
		new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(90, 170, 255), ImageTransparency = 0.5, AnchorPoint = V2(0.5, 0.5), Position = c(166, 232), Size = Z(250, 200), ZIndex = z }, card)
		return new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = REQ_ICON, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(166, 228), Size = Z(178, 178), ZIndex = z + 1 }, card)
	elseif rw.Kind == "Crate" then
		local cr = Config.ById[rw.Id]
		new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = cr and cr.Color or WHITE, ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = c(166, 232), Size = Z(260, 210), ZIndex = z }, card)
		return new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = cr and cr.Art.Full or "", ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(166, 234), Size = Z(210, 190), ZIndex = z + 1 }, card)
	elseif rw.Kind == "Skin" then
		local e = skinInfo[rw.Key]
		local col = tierColor(e and e.Rarity)
		new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = col, ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = c(166, 236), Size = Z(300, 220), ZIndex = z }, card)
		local vp = new("ViewportFrame", { Name = "Icon", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = c(166, 232), Size = Z(300, 300), ZIndex = z + 1 }, card)
		if e then
			local ok, m = pcall(K.weapon, e.Weapon, e.Skin)
			if ok and m then frameGun(vp, m, 38, 1.02) end
		end
		return vp
	end
end

function SP:_card(parent, track, t, pos)
	local HS = self.HS
	local new = HS.new
	local rw = Pass.Tiers[t][track]
	local th = TRACK[track]
	local z = 30
	local b = new("TextButton", { Name = track .. t, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = pos, Size = Z(CARD_W, CARD_H), ZIndex = z }, parent)
	local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(255, 186, 64), ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.55, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, P(120), 1, P(120)), ZIndex = z - 1 }, b)
	local face = new("ImageLabel", { Name = "Face", BackgroundTransparency = 1, Image = if track == "Premium" then IMG.FaceGold else IMG.FaceSilver, Size = S(1, 1), ZIndex = z }, b)
	local skin = rw.Kind == "Skin" and skinInfo[rw.Key]
	if skin then
		face.Image = IMG.FaceDark
		face.ImageColor3 = hsv(tierColor(skin.Rarity), 1.05, 1)
	end
	new("ImageLabel", { Name = "Frame", BackgroundTransparency = 1, Image = if track == "Premium" then IMG.FrameGold else IMG.FrameSilver, Size = S(1, 1), ZIndex = z + 3 }, b)
	local flash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z + 9 }, b)
	HS.corner(flash, P(30))

	-- title + amount
	if skin then
		local nm = spaced(skin.Skin)
		self:_text(b, { Name = "Title", Text = nm, TextSize = P(46), Stroke = 3, StrokeColor = RGB(20, 12, 4), Color = th.Title, X = LEFT, Position = c(22, 14), Size = Z(232, 56), ZIndex = z + 4 })
		local sub = self:_text(b, { Name = "Amount", Text = string.upper(skin.Weapon .. " · " .. skin.Rarity), TextSize = P(30), Stroke = 2.4, StrokeColor = RGB(10, 6, 2), Color = WHITE, X = LEFT, Position = c(24, 66), Size = Z(232, 36), ZIndex = z + 4 })
		local ch = K.CHROMAS and K.CHROMAS[skin.Rarity]
		new("UIGradient", { Color = if ch and ch.Grad then ch.Grad else CS(tierColor(skin.Rarity), hsv(tierColor(skin.Rarity), 0.6, 1)) }, sub)
	else
		local title = if rw.Kind == "REQ" then "REQ" else (rw.Id .. " Crate")
		local amt = if rw.Kind == "REQ" then num(rw.Amount) else (rw.Count .. "x")
		self:_text(b, { Name = "Title", Text = title, TextSize = P(56), Stroke = 3.2, StrokeColor = th.TitleInk, Color = th.Title, X = LEFT, Position = c(22, 12), Size = Z(296, 66), ZIndex = z + 4 })
		self:_text(b, { Name = "Amount", Text = amt, TextSize = P(54), Stroke = 3.2, StrokeColor = th.AmountInk, Color = th.Amount, X = LEFT, Position = c(24, 70), Size = Z(250, 60), ZIndex = z + 4 })
	end
	local icon = self:_icon(b, rw, z + 1)

	local card = { B = b, Track = track, T = t, Rw = rw, Face = face, Glow = glow, Flash = flash, Icon = icon }
	card.Check = self:_check(b, c(166, 214), P(158), z + 6)
	card.Lock = self:_lock(b, c(26, 258), P(58), z + 6)
	if rw.Kind == "Crate" then
		local od = self:_pill(b, { Name = "Odds", Text = "Odds", TextSize = P(30), TextStroke = 2, Pal = PAL.Blue, Skin = IMG.Odds, R = 7, Outline = 1.6, Position = c(186, 284), Size = Z(126, 42), Z = z + 6, Hover = 1.1, OnClick = function()
			if self.Env.Open then self.Env.Open("Cases") end
		end })
		card.Odds = od.B
	end
	if skin then
		card.Eye = self:_eye(b, c(256, 16), P(62), z + 6, function() self:_preview(rw.Key) end)
	end
	card.Claim = self:_pill(b, { Name = "Claim", Text = "CLAIM!", TextSize = P(44), Pal = PAL.Green, Skin = IMG.Claim, R = 10, AnchorPoint = V2(0.5, 0.5), Position = c(166, 345), Size = Z(228, 72), Z = z + 7, Sound = false, OnClick = function()
		self:_claim(track, t)
	end }).B
	HS.press(b, function()
		if self.Dragged then return end
		if card.Can then
			self:_claim(track, t)
		elseif skin then
			self:_preview(rw.Key)
		end
	end, { Hover = 1.035, Press = 0.97, Sound = false })
	self.Cards[track .. t] = card
	return card
end

-- left label cards ("Free" / "Premium")
function SP:_label(parent, track, pos)
	local HS = self.HS
	local new = HS.new
	local th = TRACK[track]
	local z = 30
	local b = new("TextButton", { Name = track .. "Label", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = pos, Size = Z(CARD_W, CARD_H), ZIndex = z }, parent)
	new("ImageLabel", { Name = "Face", BackgroundTransparency = 1, Image = if track == "Premium" then IMG.FaceGold else IMG.FaceSilver, Size = S(1, 1), ZIndex = z }, b)
	new("ImageLabel", { Name = "Frame", BackgroundTransparency = 1, Image = if track == "Premium" then IMG.FrameGold else IMG.FrameSilver, Size = S(1, 1), ZIndex = z + 3 }, b)
	local t = self:_text(b, { Name = "Title", Text = track, TextSize = P(66), Stroke = 3.6, StrokeColor = th.TitleInk, Color = th.Title, Position = c(0, 18), Size = Z(CARD_W, 76), ZIndex = z + 4 })
	if track == "Free" then
		new("UIGradient", { Rotation = 90, Color = CS(WHITE, RGB(190, 194, 206)) }, t)
	else
		new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 246, 170), RGB(255, 196, 50)) }, t)
	end
	new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = if track == "Free" then WHITE else RGB(255, 220, 120), ImageTransparency = 0.7, AnchorPoint = V2(0.5, 0.5), Position = c(166, 222), Size = Z(330, 330), ZIndex = z + 1 }, b)
	new("ImageLabel", { Name = "Badge", BackgroundTransparency = 1, Image = BADGE[track], ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = c(166, 222), Size = Z(206, 206), ZIndex = z + 2 }, b)
	if track == "Premium" then
		local pr = Shop.ByKey[Pass.Products.Premium]
		self.GetPremium = self:_pill(b, { Name = "Get", Text = "GET  " .. ROBUX .. " " .. num(pr and pr.Robux or 0), TextSize = P(40), Pal = PAL.Purple, Skin = IMG.Get, R = 10, AnchorPoint = V2(0.5, 0.5), Position = c(166, 345), Size = Z(250, 72), Z = z + 7, OnClick = function()
			self:_buy(Pass.Products.Premium)
		end })
		self.PremiumOn = self:_text(b, { Name = "Active", Text = "ACTIVE", TextSize = P(34), Stroke = 2.6, StrokeColor = PAL.Green.Ink, Color = PAL.Green.Top0, Position = c(0, 290), Size = Z(CARD_W, 44), ZIndex = z + 5 })
		HS.press(b, function()
			if not player:GetAttribute("PassPremium") then self:_buy(Pass.Products.Premium) end
		end, { Hover = 1.03, Press = 0.97, Sound = false })
	end
	return b
end

-- timeline diamond node
function SP:_node(parent, t, x)
	local HS = self.HS
	local z = 33
	local s = P(98)
	local f = HS.new("ImageLabel", { Name = "Node" .. t, BackgroundTransparency = 1, Image = IMG.NodeOff, AnchorPoint = V2(0.5, 0.5), Position = O(x * SC, (LINE_Y - 715) * SC), Size = O(s, s), ZIndex = z }, parent)
	local lab = self:_text(f, { Name = "N", Text = tostring(t), Font = HS.Font, TextSize = P(40), Stroke = 2.6, StrokeColor = RGB(60, 36, 6), Color = WHITE, Position = O(0, -2), Size = S(1, 1), ZIndex = z + 2 })
	self.Nodes[t] = { F = f, L = lab }
end

------------------------------------------------------------------ build
function SP:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "SeasonPassHS", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(CW, CH), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit

	-- panel
	local panel = self:_panel(fit, "Panel", R(222, 165), Z(2023, 1200))
	local function PR(x, y) return O((x - 222) * SC, (y - 165) * SC) end

	-- title + emblem breaking the top-left
	new("ImageLabel", { Name = "TitleIcon", BackgroundTransparency = 1, Image = BADGE.Title, ScaleType = Enum.ScaleType.Fit, Position = R(160, 88), Size = Z(140, 140), ZIndex = 36 }, fit)
	local title = self:_text(fit, { Name = "Title", Text = "Season Pass", TextSize = P(94), Stroke = 5, StrokeColor = RGB(40, 18, 6), X = LEFT, Fit = false, Position = R(296, 96), Size = Z(640, 110), ZIndex = 36 })
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 252, 236), RGB(255, 206, 84)) }, title)
	local chip = new("Frame", { Name = "SeasonChip", BackgroundColor3 = RGB(16, 30, 60), Position = R(860, 124), Size = Z(220, 54), ZIndex = 36 }, fit)
	HS.corner(chip, UDim.new(0.5, 0))
	HS.stroke(chip, 2.6, RGB(90, 220, 255))
	self.SeasonChip = self:_text(chip, { Text = string.upper(Pass.Name), TextSize = P(32), Stroke = 2.2, StrokeColor = RGB(6, 20, 40), Color = RGB(150, 236, 255), ZIndex = 37 })

	-- CLAIM ALL (own) + REQ pill + X
	self.ClaimAll = self:_pill(fit, { Name = "ClaimAll", Text = "CLAIM ALL", TextSize = P(40), Pal = PAL.Green, Skin = IMG.ClaimAll, R = 12, Position = R(1452, 108), Size = Z(320, 80), Z = 36, Sound = false, OnClick = function()
		self:_claim("All")
	end })
	local cur = new("Frame", { Name = "Currency", BackgroundColor3 = WHITE, Position = R(1820, 114), Size = Z(250, 72), ZIndex = 36 }, fit)
	HS.corner(cur, UDim.new(0.5, 0))
	HS.stroke(cur, 3, BLACK)
	new("UIGradient", { Rotation = 90, Color = CS(RGB(170, 110, 255), RGB(96, 40, 214)) }, cur)
	local cin = new("Frame", { BackgroundTransparency = 1, Position = O(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 36 }, cur)
	HS.corner(cin, UDim.new(0.5, 0))
	HS.stroke(cin, 2, RGB(220, 196, 255), 0.3)
	new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = REQ_ICON, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(P(26), P(36)), Size = Z(104, 104), ZIndex = 37 }, cur)
	self.ReqText = self:_text(cur, { Name = "Value", Text = "0", Font = HS.MontX, TextSize = P(44), Stroke = 2.6, Color = WHITE, Position = O(P(70), 0), Size = O(P(170), P(72)), ZIndex = 37 })
	self:_pill(fit, { Name = "Close", Skin = IMG.Close, AnchorPoint = V2(0.5, 0.5), Position = R(2196, 152), Size = Z(100, 100), Z = 37, Hover = 1.08, Sound = "Click", OnClick = function()
		if self.Env.Close then self.Env.Close() end
	end })

	-- tier strip
	local strip = new("Frame", { Name = "TierStrip", BackgroundColor3 = RGB(12, 8, 22), Position = PR(280, 218), Size = Z(1905, 100), ZIndex = 24 }, panel)
	HS.corner(strip, P(24))
	HS.stroke(strip, 3, RGB(52, 40, 80))
	self.TierText = self:_text(strip, { Name = "Tier", Text = "Tier 0", TextSize = P(60), Stroke = 3.4, StrokeColor = RGB(40, 18, 4), X = LEFT, Position = O(P(36), 0), Size = O(P(290), P(100)), ZIndex = 26 })
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 226, 130), RGB(255, 150, 40)) }, self.TierText)
	local xb = new("Frame", { Name = "XPBar", BackgroundColor3 = RGB(36, 32, 48), Position = O(P(335), P(25)), Size = O(P(1252), P(52)), ZIndex = 25 }, strip)
	HS.corner(xb, UDim.new(0.5, 0))
	HS.stroke(xb, 2.6, BLACK)
	self.XPFill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(0, 1), ZIndex = 25 }, xb)
	HS.corner(self.XPFill, UDim.new(0.5, 0))
	new("UIGradient", { Color = CS(RGB(226, 90, 22), RGB(255, 206, 112)) }, self.XPFill)
	new("ImageLabel", { Name = "Stripes", BackgroundTransparency = 1, Image = IMG.Stripes, ScaleType = Enum.ScaleType.Tile, TileSize = O(P(52), P(52)), Size = S(1, 1), ZIndex = 25 }, self.XPFill)
	local gloss = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, Position = O(P(14), P(5)), Size = UDim2.new(1, -P(28), 0.34, 0), ZIndex = 25 }, self.XPFill)
	HS.corner(gloss, UDim.new(0.5, 0))
	self.XPText = self:_text(xb, { Name = "XP", Text = "", TextSize = P(40), Stroke = 2.8, Color = WHITE, X = LEFT, Position = O(P(26), 0), Size = O(P(700), P(52)), ZIndex = 27 })
	self.PctText = self:_text(xb, { Name = "Pct", Text = "", TextSize = P(40), Stroke = 2.8, Color = WHITE, X = RIGHT, Position = UDim2.new(1, -P(222), 0, 0), Size = O(P(200), P(52)), ZIndex = 27 })
	self.DaysText = self:_text(strip, { Name = "Days", Text = "", TextSize = P(44), Stroke = 2.8, Color = WHITE, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -P(30), 0, 0), Size = O(P(290), P(100)), ZIndex = 26 })

	-- label cards
	self:_label(panel, "Free", PR(280, ROW_Y.Free))
	self:_label(panel, "Premium", PR(280, ROW_Y.Premium))

	-- timeline (own clip, scrolls with the cards)
	local lclip = new("Frame", { Name = "LineClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = PR(LINE_X0, 715), Size = Z(LINE_X1 - LINE_X0, 96), ZIndex = 26 }, panel)
	local ltrack = new("Frame", { Name = "Track", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 26 }, lclip)
	self.LineTrack = ltrack
	local total = NODE0 + (Pass.MaxTier - 1) * PITCH + 260
	local rail = new("Frame", { Name = "Rail", BackgroundColor3 = RGB(48, 40, 70), BorderSizePixel = 0, AnchorPoint = V2(0, 0.5), Position = O(0, (LINE_Y - 715) * SC), Size = O(total * SC, P(22)), ZIndex = 27 }, ltrack)
	HS.corner(rail, UDim.new(0.5, 0))
	HS.stroke(rail, 2, BLACK, 0.3)
	self.LineFill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0, 0.5), Position = O(0, (LINE_Y - 715) * SC), Size = O(0, P(22)), ZIndex = 28 }, ltrack)
	HS.corner(self.LineFill, UDim.new(0.5, 0))
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 246, 150), RGB(255, 196, 44)) }, self.LineFill)
	new("ImageLabel", { Name = "Stripes", BackgroundTransparency = 1, Image = IMG.Stripes, ScaleType = Enum.ScaleType.Tile, TileSize = O(P(40), P(40)), Size = S(1, 1), ZIndex = 28 }, self.LineFill)
	for t = 1, Pass.MaxTier do
		self:_node(ltrack, t, NODE0 + (t - 1) * PITCH)
	end

	-- card rows (one clip, both rows)
	local cclip = new("Frame", { Name = "CardClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = PR(CLIP_X0, CLIP_Y0), Size = Z(CLIP_X1 - CLIP_X0, CLIP_Y1 - CLIP_Y0), ZIndex = 28 }, panel)
	local ctrack = new("Frame", { Name = "Track", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 28 }, cclip)
	self.CardTrack, self.CardClip = ctrack, cclip
	for t = 1, Pass.MaxTier do
		local xx = (FIRST + (t - 1) * PITCH) * SC
		self:_card(ctrack, "Free", t, O(xx, (ROW_Y.Free - CLIP_Y0) * SC))
		self:_card(ctrack, "Premium", t, O(xx, (ROW_Y.Premium - CLIP_Y0) * SC))
	end
	-- scroll input on the rows / timeline
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
			if self.Dragged then
				self.Off = math.clamp(d.Off - dx, 0, OFF_MAX)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if self.Drag and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
			self.Drag = nil
			task.delay(0.05, function() self.Dragged = false end)
		end
	end)

	-- arrows (chunky orange squares half outside the panel)
	local function arrow(xr, txt, dir)
		local a = self:_pill(fit, { Name = "Arrow" .. dir, Skin = if dir < 0 then IMG.ArrowL else IMG.ArrowR, Pal = PAL.Arrow, Position = R(xr, 700), Size = Z(126, 126), Z = 38, Hover = 1.08, Sound = "Tab", OnClick = function()
			self:_scrollTo(self.Off + dir * 4 * PITCH)
		end })
		return a
	end
	self.Left = arrow(160, "<", -1)
	self.Right = arrow(2180, ">", 1)

	-- footer: skips + gift squares
	local function skip(x0, x1, pal, label, key, gx)
		local pr = Shop.ByKey[key]
		local skin = if pal == PAL.Purple then IMG.SkipPurple elseif pal == PAL.Orange then IMG.SkipOrange else IMG.SkipTeal
		local p = self:_pill(fit, { Name = key, Text = label .. "  " .. ROBUX .. " " .. num(pr and pr.Robux or 0), TextSize = P(48), Pal = pal, Skin = skin, R = 14, Position = R(x0, 1305), Size = Z(x1 - x0, 106), Z = 38, OnClick = function()
			self:_buy(key)
		end })
		self:_pill(fit, { Name = "Gift" .. key, Skin = IMG.Gift, Pal = PAL.Blue, R = 14, Position = R(gx, 1305), Size = Z(108, 106), Z = 38, Hover = 1.08, OnClick = function()
			self:_toast("Gifting soon", "Gifting tier skips to friends is coming soon")
		end })
		if pr and pr.Was then
			local cx = (x0 + x1) / 2
			local w = self:_text(fit, { Name = "Was" .. key, Text = ROBUX .. " " .. num(pr.Was), TextSize = P(42), Stroke = 2.6, StrokeColor = RGB(50, 6, 6), Color = RGB(255, 70, 70), AnchorPoint = V2(0.5, 0.5), Position = R(cx, 1436), Size = Z(260, 54), ZIndex = 37 })
			new("Frame", { Name = "Strike", BackgroundColor3 = RGB(255, 60, 60), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.55), Size = O(P(150), 4), Rotation = -6, ZIndex = 38 }, w)
		end
		p.Skin = skin
		return p
	end
	self.Skips = {
		skip(405, 796, PAL.Purple, "Skip 1", Pass.Products.Skip1, 818),
		skip(970, 1361, PAL.Orange, "Skip 5", Pass.Products.Skip5, 1383),
		skip(1535, 1926, PAL.Teal, "Skip ALL", Pass.Products.SkipAll, 1948),
	}

	-- skin preview overlay
	local ov = new("TextButton", { Name = "Preview", Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 0.25, Position = O(-400, -300), Size = UDim2.new(1, 800, 1, 600), Visible = false, ZIndex = 60 }, fit)
	self.Preview = ov
	local box = new("Frame", { Name = "Box", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = O(900, 640), ZIndex = 61 }, ov)
	self.PrevRays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.45), Size = O(760, 760), ZIndex = 61 }, box)
	self.PrevBloom = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.45), Size = O(620, 380), ZIndex = 61 }, box)
	self.PrevVP = new("ViewportFrame", { BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.43), Size = O(760, 520), ZIndex = 62 }, box)
	self.PrevName = self:_text(box, { Text = "", TextSize = 54, Stroke = 4, Color = WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, -10), Size = O(860, 64), ZIndex = 63 })
	self.PrevSub = self:_text(box, { Text = "", TextSize = 30, Stroke = 2.6, Color = WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = O(860, 40), ZIndex = 63 })
	self.PrevGrad = new("UIGradient", {}, self.PrevSub)
	self.PrevNote = self:_text(box, { Text = "", TextSize = 26, Stroke = 2.4, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 1, -112), Size = O(860, 36), ZIndex = 63 })
	self:_pill(box, { Name = "Back", Text = "BACK", TextSize = 34, Pal = PAL.Grey, Skin = IMG.SkipGrey, R = 12, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = O(240, 66), Z = 63, OnClick = function()
		self:_closePreview()
	end })
	HS.press(ov, function() self:_closePreview() end, { Hover = 1, Press = 1, Sound = false })

	self:_buildToast()
end

------------------------------------------------------------------ toast (own ScreenGui so it shows over everything)
function SP:_buildToast()
	local HS = self.HS
	local gui = HS.new("ScreenGui", { Name = "PassToast", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70 }, player:WaitForChild("PlayerGui"))
	local f = HS.new("Frame", { Name = "Toast", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, -160), Size = O(600, 104), BackgroundColor3 = C.Panel, ZIndex = 2 }, gui)
	HS.corner(f, 18)
	HS.stroke(f, 4, RGB(150, 72, 255))
	HS.new("UIScale", { Name = "Fit" }, f)
	self.ToastBar = HS.new("Frame", { BackgroundColor3 = PAL.Green.Top0, BorderSizePixel = 0, Position = O(14, 16), Size = O(8, 72), ZIndex = 3 }, f)
	HS.corner(self.ToastBar, 4)
	self.ToastTitle = HS.text(f, { Text = "", TextSize = 32, Stroke = 2.8, StrokeColor = C.Ink, X = LEFT, Position = O(38, 10), Size = O(540, 42), ZIndex = 3 })
	self.ToastText = HS.text(f, { Text = "", TextSize = 22, Stroke = 2, StrokeColor = C.Ink, Color = C.Muted, X = LEFT, Position = O(38, 54), Size = O(540, 36), ZIndex = 3 })
	self.ToastFrame = f
end

function SP:_toast(title, text, good)
	local HS = self.HS
	local f = self.ToastFrame
	local vp = Workspace.CurrentCamera.ViewportSize
	f.Fit.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.5, 1.4)
	self.ToastTitle.Text, self.ToastText.Text = title, text
	self.ToastBar.BackgroundColor3 = if good then PAL.Green.Top0 else RGB(255, 170, 60)
	self.ToastN = (self.ToastN or 0) + 1
	local n = self.ToastN
	HS.tween(f, 0.35, { Position = UDim2.new(0.5, 0, 0, 90) }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		if self.ToastN == n then
			HS.tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, -160) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end

------------------------------------------------------------------ actions
function SP:_buy(key)
	local it = Shop.ByKey[key]
	if not it then return end
	if (key == Pass.Products.Premium and player:GetAttribute("PassPremium")) or ((tonumber(player:GetAttribute("PassTier")) or 0) >= Pass.MaxTier and key ~= Pass.Products.Premium) then
		self.HS.sound("Deny")
		return
	end
	if (it.ProductId or 0) <= 0 then
		self.HS.sound("Deny")
		self:_toast("Coming soon", it.Name .. " isn't on sale yet")
		return
	end
	MarketplaceService:PromptProductPurchase(player, it.ProductId)
end

function SP:_claim(track, t)
	if self.Busy then return end
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
	local col = tierColor(e.Rarity)
	self.PrevName.Text = spaced(e.Skin)
	self.PrevSub.Text = string.upper(e.Weapon .. " · " .. e.Rarity)
	local ch = K.CHROMAS and K.CHROMAS[e.Rarity]
	self.PrevGrad.Color = if ch and ch.Grad then ch.Grad else CS(col, hsv(col, 0.6, 1))
	self.PrevRays.ImageColor3, self.PrevBloom.ImageColor3 = col, col
	local owned = false
	for k in tostring(player:GetAttribute("OwnedSkins") or ""):gmatch("[^,]+") do
		if k == key then owned = true end
	end
	self.PrevNote.Text = if owned then "Already owned: claiming it pays REQ instead" else "Season Pass reward"
	local ok, m = pcall(K.weapon, e.Weapon, e.Skin)
	self.Spin = nil
	if ok and m then
		local ctr = frameGun(self.PrevVP, m, 0, 1.0)
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
local function claimedSets()
	local s = tostring(player:GetAttribute("PassClaimed") or "")
	local a, b = s:match("^([^|]*)|?(.*)$")
	local F, Pm = {}, {}
	for n in (a or ""):gmatch("%d+") do F[tonumber(n)] = true end
	for n in (b or ""):gmatch("%d+") do Pm[tonumber(n)] = true end
	return F, Pm
end

function SP:_refresh()
	local xp = tonumber(player:GetAttribute("PassXP")) or 0
	local tier, into = Pass.TierOf(xp)
	local prem = player:GetAttribute("PassPremium") == true
	local F, Pm = claimedSets()
	local count = 0
	local visible = self.Root.Visible
	local popped = false
	for key, cd in self.Cards do
		local done = if cd.Track == "Free" then F[cd.T] == true else Pm[cd.T] == true
		local reached = cd.T <= tier
		local can = reached and not done and (cd.Track == "Free" or prem)
		cd.Can = can
		if can then count += 1 end
		cd.Check.Visible = done
		cd.Lock.Visible = not done and not can
		cd.Claim.Visible = can
		if cd.Odds then cd.Odds.Visible = not can end
		if cd.Icon then cd.Icon.ImageTransparency = if done then 0.3 else 0 end
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
	-- timeline
	for t, nd in self.Nodes do
		local on = t <= tier
		nd.F.Image = if on then IMG.NodeOn else IMG.NodeOff
		nd.L.TextColor3 = if on then WHITE else RGB(170, 160, 130)
	end
	local frac = into / Pass.TierXP
	local fillX
	if tier >= Pass.MaxTier then
		fillX = NODE0 + (Pass.MaxTier - 1) * PITCH + 260
	elseif tier <= 0 then
		fillX = NODE0 * frac
	else
		fillX = NODE0 + (tier - 1) * PITCH + frac * PITCH
	end
	self.HS.tween(self.LineFill, 0.35, { Size = O(fillX * SC, P(22)) })
	-- strip
	self.TierText.Text = if tier >= Pass.MaxTier then "Tier " .. tier .. " MAX" else "Tier " .. tier
	if tier >= Pass.MaxTier then
		self.XPText.Text = "MAX TIER"
		self.PctText.Text = "100%"
		self.HS.tween(self.XPFill, 0.35, { Size = S(1, 1) })
	else
		self.XPText.Text = num(into) .. " / " .. num(Pass.TierXP) .. " XP"
		self.PctText.Text = math.floor(frac * 100) .. "%"
		self.HS.tween(self.XPFill, 0.35, { Size = S(math.max(frac, 0.04), 1) })
	end
	self.ReqText.Text = num(tonumber(player:GetAttribute("REQ")) or 0)
	self.GetPremium.B.Visible = not prem
	self.PremiumOn.Visible = prem
	self.ClaimAll.B.Visible = count > 0
	self.ClaimAll.T.Text = "CLAIM ALL (" .. count .. ")"
	for _, sk in self.Skips do
		local off = tier >= Pass.MaxTier
		self.HS.setDisabled(sk.B, off)
		sk.B.Image = if off then IMG.SkipGrey else sk.Skin
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

function SP:_step(dt)
	local t = os.clock()
	-- scroll easing
	self.Cur += (self.Off - self.Cur) * math.min(1, dt * 12)
	if math.abs(self.Off - self.Cur) < 0.3 then self.Cur = self.Off end
	self.CardTrack.Position = O(-self.Cur * SC, 0)
	self.LineTrack.Position = O(-self.Cur * SC, 0)
	self.Left.B.Visible = self.Off > 1
	self.Right.B.Visible = self.Off < OFF_MAX - 1
	for _, sw in self.Sweeps do
		local u = ((t + sw.P) % 3.4) / 0.85
		sw.G.Offset = V2(if u < 1 then -1 + 2 * u else 1, 0)
	end
	-- claimable glow pulse
	local a = 0.3 + 0.25 * math.sin(t * 4)
	for _, g in self.Glows do g.ImageTransparency = a end
	if self.Rim then self.Rim.Rotation = (t * 18) % 360 end
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
	self.FitFrame.Position = UDim2.new(0.5, 0, 0.5, 14 * self.Fit.Scale)
end

function SP:OnShow()
	self:_fit()
	self:_closePreview()
	self:_refresh()
	-- open on the first card to claim, else the current tier (shown as the 2nd card)
	local F, Pm = claimedSets()
	local prem = player:GetAttribute("PassPremium") == true
	local focus = math.min(Pass.MaxTier, (self.Tier or 0) + 1)
	for t = 1, self.Tier or 0 do
		if not F[t] or (prem and not Pm[t]) then
			focus = t
			break
		end
	end
	self.Off = math.clamp((focus - 2) * PITCH, 0, OFF_MAX)
	self.Cur = self.Off
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
