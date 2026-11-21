--!nocheck
--[[
	ModesHS - VantageShot game-mode select (2026-11-18). Hypershot's mode screen construction (full-screen dark stage,
	"Casual" / "Ranked" section labels on the left, glowing dividers, square key-art cards with the title on top, locked
	cards dimmed with a lock), pushed further:
	  * every card is a 2.5D parallax scene: inpainted background drifting (Ken Burns), hero cut-out floating on its own
	    layer, per-mode live FX (tracers + explosion glow, smoke + door fire, rain + lightning, speed lines + pad glow,
	    god rays + gold sparks), light sweep, rotating neon rim with a white wink
	  * hover pops/tilts the card, zooms the art and slides the description up; selected = green rim + check
	  * the stage behind shows the hovered mode's art, drifting, plus our violet bands / nebulae / motes
	Art: user's key art (Gemini/Qwen, watermark cropped), cut-outs via rembg; ids below.
	API: Mount(layer, env{HS, Modes, State, SelectMode, Close, Attr?}) -> { Root, OnShow, Object }
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local R = require(Vantage:WaitForChild("Ranked"):WaitForChild("RankedConfig"))

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local LEFT = Enum.TextXAlignment.Left

local function id(n) return "rbxassetid://" .. n end
local ATLAS = { [0] = id(104850711810300), id(84706372895889), id(136561818438659) }
local A = {
	back = { 2, 3, 285, 300, 92 }, check = { 1, 406, 451, 300, 240 }, lock = { 0, 859, 451, 160, 196 },
	pill = { 0, 406, 899, 400, 104 },
}
local BANDS = id(132171274146535)
local GLOW = id(104786452938879)
local RAYS = id(113538852110620)
local BLOOM = id(103142630740394)
local STAR = id(107113949398119)

-- key art: Bg = inpainted plate, Cut = hero cut-out; Src = plate px; Box = cut-out rect in plate px
local ART = {
	TDM = { Bg = id(89865586611087), Cut = id(96518023937028), Src = V2(1024, 1024), Box = { 239, 148, 548, 636 } },
	TAC = { Bg = id(90290703412444), Cut = id(77414527378117), Src = V2(1024, 1024), Box = { 74, 314, 867, 695 } },
	DUEL = { Bg = id(88190095744386), Cut = id(111899167999905), Src = V2(1024, 683), Box = { 20, 180, 854, 503 }, Par = 0.1 },
	CTF = { Bg = id(102392322171189), Cut = id(92810817487959), Src = V2(1024, 1024), Box = { 177, 165, 683, 664 } },
	RTDM = { Bg = id(108164118988499), Cut = id(139860623968442), Src = V2(1024, 1024), Box = { 185, 131, 554, 749 } },
}
local COLORS = {
	Red = RGB(255, 84, 96), Purple = RGB(186, 110, 255), Blue = RGB(80, 170, 255), Orange = RGB(255, 150, 50),
	Green = RGB(110, 240, 110), Gold = RGB(255, 206, 80),
}
local TITLES = { TDM = "Deathmatch", TAC = "Tactical", DUEL = "Shootout", CTF = "Capture the Flag", RTDM = "Ranked Deathmatch" }

-- layout (design px 1920x1080)
local CARD, GAP, X0 = 318, 38, 418
local ROWS = { Casual = 186, Ranked = 612 }
local INK = RGB(14, 8, 24)
local GREEN = RGB(120, 255, 110)
local MUTED = RGB(178, 168, 204)

local function skin(obj, key)
	local a = A[key]
	obj.Image = ATLAS[a[1]]
	obj.ImageRectOffset = V2(a[2], a[3])
	obj.ImageRectSize = V2(a[4], a[5])
	return obj
end
local function rnd(a, b) return a + math.random() * (b - a) end

local M = {}
M.__index = M

function M.new(layer, env)
	local self = setmetatable({ Env = env, HS = env.HS, Cards = {}, Sweeps = {}, Embers = {}, Twinkles = {}, Nebula = {}, Lines = {}, Focus = nil }, M)
	self:_build(layer)
	RunService.RenderStepped:Connect(function(dt)
		if self.Root.Visible then self:_step(math.min(dt, 0.05)) end
	end)
	return self
end

function M:_attr(n)
	if self.Env.Attr then return self.Env.Attr[n] end
	return player and player:GetAttribute(n)
end

------------------------------------------------------------------ kit
function M:_label(parent, p)
	local HS = self.HS
	local z = p.ZIndex or 40
	local drop = HS.text(parent, { Name = (p.Name or "Label") .. "Drop", Text = p.Text, Font = p.Font, TextSize = p.TextSize, Color = BLACK, X = p.X, Y = p.Y, Fit = p.Fit, Stroke = p.Stroke or 3, StrokeColor = BLACK, AnchorPoint = p.AnchorPoint, Position = (p.Position or UDim2.new()) + UDim2.fromOffset(0, p.DropY or math.max(2, (p.TextSize or 24) * 0.08)), Size = p.Size, ZIndex = z - 1 })
	drop.TextTransparency = 0.35
	local ds = drop:FindFirstChildOfClass("UIStroke")
	if ds then ds.Transparency = 0.35 end
	local t = HS.text(parent, { Name = p.Name or "Label", Text = p.Text, Font = p.Font, TextSize = p.TextSize, Color = p.Color or WHITE, X = p.X, Y = p.Y, Fit = p.Fit, Stroke = p.Stroke or 3, StrokeColor = p.StrokeColor or INK, AnchorPoint = p.AnchorPoint, Position = p.Position, Size = p.Size, ZIndex = z })
	if p.Grad then HS.new("UIGradient", { Rotation = p.GradRot or 90, Color = p.Grad }, t) end
	t:GetPropertyChangedSignal("Text"):Connect(function() drop.Text = t.Text end)
	t:GetPropertyChangedSignal("Visible"):Connect(function() drop.Visible = t.Visible end)
	return t, drop
end

function M:_sweep(parent, pos, size, radius, z, strength, period)
	local sw = self.HS.new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = pos, Size = size, ZIndex = z }, parent)
	self.HS.corner(sw, radius)
	local s = strength or 0.35
	local g = self.HS.new("UIGradient", { Rotation = 22, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.38, 1), NK(0.47, 1 - s * 0.55), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.55), NK(0.62, 1), NK(1, 1) }) }, sw)
	table.insert(self.Sweeps, { G = g, P = math.random() * 4, Period = period })
	return sw
end

function M:_btn(parent, p)
	local HS, z = self.HS, p.Z or 44
	local b = HS.new("ImageButton", { Name = p.Name or "Btn", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	skin(b, p.Skin)
	local w, h = p.Size.X.Offset, p.Size.Y.Offset
	local a = A[p.Skin]
	local hr = h / (a[5] * 0.95)
	local inset = math.max(3, a[5] * 0.115 * hr)
	self:_sweep(b, O(inset, inset * 0.9), O(w - inset * 2, (h * 0.95) - inset * 2), UDim.new(0, math.max(2, a[5] * 0.17 * hr - inset * 0.6)), z, 0.4)
	if p.Text then
		self:_label(b, { Name = "Label", Text = p.Text, TextSize = p.TextSize or 30, Stroke = p.Stroke or 3, StrokeColor = p.Ink or INK, Position = O(0, -h * 0.04), Size = S(1, 1), ZIndex = z + 2 })
	end
	HS.press(b, p.OnClick, { Hover = p.Hover or 1.05, Press = 0.95, Sound = p.Sound })
	return b
end

function M:_embers(holder, n, c1, c2, sz, z, list)
	for _ = 1, n do
		local k = 0.6 + math.random() * 0.8
		local f = self.HS.new("Frame", { Name = "Ember", BackgroundColor3 = c1:Lerp(c2, math.random()), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz * k, sz * k), ZIndex = z }, holder)
		self.HS.corner(f, UDim.new(0.5, 0))
		table.insert(list or self.Embers, { F = f, X = math.random(), Y = math.random(), V = 0.04 + math.random() * 0.08, Sway = math.random() * 6.28 })
	end
end

function M:_twinkles(holder, n, color, sz, z)
	for _ = 1, n do
		local st = self.HS.new("ImageLabel", { Name = "Twinkle", BackgroundTransparency = 1, Image = STAR, ImageColor3 = color, AnchorPoint = V2(0.5, 0.5), Position = S(math.random(), math.random()), Size = O(0, 0), ZIndex = z }, holder)
		table.insert(self.Twinkles, { I = st, Sz = sz * (0.7 + math.random() * 0.6), P = math.random() * 10, Spd = 1.1 + math.random() * 1.5 })
	end
end

------------------------------------------------------------------ per-card particles (scale coords inside the art)
local function particle(c, f, spawn)
	local p = { F = f, Spawn = spawn }
	spawn(p, true)
	table.insert(c.P, p)
	return p
end

function M:_fx(c, key, z)
	local HS = self.HS
	local new = HS.new
	local art = c.Art
	local function bloom(col, pos, size, tr, zz)
		return new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = col, ImageTransparency = tr, AnchorPoint = V2(0.5, 0.5), Position = pos, Size = size, ZIndex = zz }, art)
	end
	local function streak(col, w, h, zz, tr)
		local f = new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = S(w, h), ZIndex = zz }, art)
		new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.7, tr or 0.1), NK(1, 0) }) }, f)
		HS.corner(f, UDim.new(0.5, 0))
		return f
	end
	local function dot(col, sz, zz)
		local f = new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz, sz), ZIndex = zz }, art)
		HS.corner(f, UDim.new(0.5, 0))
		return f
	end
	local BG, FG = z + 1, z + 3 -- behind the hero / in front of it
	if key == "TDM" then
		c.Pulse = { bloom(RGB(255, 140, 40), S(0.74, 0.64), S(0.5, 0.5), 0.3, BG), 0.35, 2.2 }
		for i = 1, 7 do
			local col = if i % 2 == 0 then RGB(255, 90, 70) else RGB(110, 180, 255)
			particle(c, streak(col, 0.2, 0.008, BG), function(p, first)
				local dir = if col.R > 0.9 then -1 else 1
				p.x, p.y = if dir > 0 then -0.25 else 1.25, rnd(0.5, 0.95)
				p.vx, p.vy, p.wait = dir * rnd(1.6, 2.4), rnd(-0.05, 0.05), if first then rnd(0, 2) else rnd(0.2, 1.6)
				p.F.Rotation = if dir > 0 then 0 else 180
			end)
		end
		for _ = 1, 14 do
			particle(c, dot(RGB(255, 190, 90), rnd(2, 5), FG), function(p, first)
				p.x, p.y = rnd(0, 1), if first then rnd(0, 1) else 1.05
				p.vx, p.vy, p.fade = rnd(-0.03, 0.03), -rnd(0.06, 0.16), true
			end)
		end
	elseif key == "TAC" then
		c.Pulse = { bloom(RGB(255, 150, 60), S(0.42, 0.44), S(0.7, 0.7), 0.3, BG), 0.3, 9, true }
		for _ = 1, 5 do
			particle(c, bloom(RGB(200, 196, 220), S(0.5, 0.5), S(rnd(0.4, 0.6), rnd(0.35, 0.5)), 0.78, FG), function(p, first)
				p.x, p.y = if first then rnd(0, 1) else rnd(-0.2, 0.6), if first then rnd(0, 1) else 1.2
				p.vx, p.vy = rnd(0.01, 0.04), -rnd(0.03, 0.06)
			end)
		end
		for _ = 1, 12 do
			particle(c, dot(RGB(255, 200, 90), rnd(2, 4), FG), function(p, first)
				p.x, p.y = rnd(0.15, 0.6), if first then rnd(0, 1) else 1.05
				p.vx, p.vy, p.fade = rnd(-0.05, 0.08), -rnd(0.12, 0.3), true
			end)
		end
	elseif key == "DUEL" then
		c.Flash = new("Frame", { BackgroundColor3 = RGB(220, 210, 255), BackgroundTransparency = 1, BorderSizePixel = 0, Size = S(1, 1), ZIndex = BG }, art)
		c.FlashT = rnd(1, 3)
		for _ = 1, 20 do
			particle(c, streak(RGB(200, 210, 255), 0.004, 0.09, FG, 0.4), function(p, first)
				p.x, p.y = rnd(-0.1, 1.1), if first then rnd(0, 1) else -0.1
				p.vx, p.vy = -0.25, rnd(1.4, 1.9)
				p.F.Rotation = -8
				p.F.BackgroundTransparency = rnd(0.3, 0.6)
			end)
		end
		for _ = 1, 8 do
			particle(c, dot(RGB(255, 80, 80), rnd(2, 4), FG), function(p, first)
				p.x, p.y = rnd(0.55, 0.95), if first then rnd(0.2, 0.9) else 0.85
				p.vx, p.vy, p.fade = rnd(-0.06, 0.06), -rnd(0.08, 0.18), true
			end)
		end
	elseif key == "CTF" then
		c.Pulse = { bloom(RGB(80, 230, 255), S(0.5, 0.84), S(0.8, 0.3), 0.3, BG), 0.3, 3 }
		for _ = 1, 9 do
			particle(c, streak(WHITE, 0.24, 0.006, BG, 0.3), function(p, first)
				p.x, p.y = if first then rnd(0, 1.2) else 1.3, rnd(0.25, 0.85)
				p.vx, p.vy, p.wait = -rnd(1.8, 2.8), 0, if first then rnd(0, 1) else rnd(0, 0.8)
				p.F.Rotation = 180
			end)
		end
		for _ = 1, 14 do
			particle(c, dot(RGB(120, 240, 255), rnd(2, 5), FG), function(p, first)
				p.x, p.y = rnd(0.3, 0.7), if first then rnd(0.4, 1) else 0.95
				p.vx, p.vy, p.fade = rnd(-0.06, 0.06), -rnd(0.12, 0.26), true
			end)
		end
	elseif key == "RTDM" then
		c.Rays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(255, 210, 120), ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.42), Size = S(0.95, 0.95), ZIndex = BG }, art)
		c.Pulse = { bloom(RGB(190, 110, 255), S(0.5, 0.45), S(0.85, 0.85), 0.4, BG), 0.4, 1.6 }
		for _ = 1, 16 do
			particle(c, dot(RGB(255, 214, 110), rnd(2, 5), FG), function(p, first)
				p.x, p.y = rnd(0, 1), if first then rnd(0, 1) else -0.05
				p.vx, p.vy, p.fade = rnd(-0.02, 0.02), rnd(0.05, 0.12), "down"
			end)
		end
	end
end

------------------------------------------------------------------ card
function M:_card(parent, info, x, y)
	local HS = self.HS
	local new = HS.new
	local art = ART[info.Art]
	local col = COLORS[info.Color] or COLORS.Purple
	local c = { Info = info, Art = nil, P = {}, H = 0, Ph = math.random() * 10, Col = col, Data = art, Locked = info.Locked }
	local root = new("ImageButton", { Name = info.Key, BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = V2(0.5, 0.5), Position = O(x + CARD / 2, y + CARD / 2), Size = O(CARD, CARD), ZIndex = 30 }, parent)
	c.Root = root
	c.Scale = new("UIScale", {}, root)
	c.Glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = col, ImageTransparency = 0.5, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.55, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, 120, 1, 120), ZIndex = 29 }, root)
	local lip = new("Frame", { Name = "Lip", BackgroundColor3 = BLACK, BackgroundTransparency = 0.25, Position = O(0, 7), Size = S(1, 1), ZIndex = 30 }, root)
	HS.corner(lip, 26)
	-- the art stack, clipped to the rounded card
	local cv = new("CanvasGroup", { Name = "Art", BackgroundColor3 = RGB(16, 8, 30), ClipsDescendants = true, Size = S(1, 1), ZIndex = 31 }, root)
	HS.corner(cv, 26)
	c.Art = cv
	c.Bg = new("ImageLabel", { Name = "Plate", BackgroundTransparency = 1, Image = art.Bg, ScaleType = Enum.ScaleType.Stretch, Size = S(1, 1), ZIndex = 31 }, cv)
	HS.corner(c.Bg, 26)
	c.Hero = new("ImageLabel", { Name = "Hero", BackgroundTransparency = 1, Image = art.Cut, ScaleType = Enum.ScaleType.Stretch, ZIndex = 33 }, cv)
	self:_fx(c, info.Art, 31)
	-- top shade for the title, bottom shade for chips / description
	local top = new("Frame", { BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 0.36), ZIndex = 35 }, cv)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.25), NK(1, 1) }) }, top)
	local bot = new("Frame", { BackgroundColor3 = RGB(10, 4, 22), BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = S(1, 0.42), ZIndex = 35 }, cv)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 1), NK(0.55, 0.35), NK(1, 0.05) }) }, bot)
	-- description panel (slides up on hover)
	local desc = new("Frame", { Name = "Desc", BackgroundColor3 = RGB(18, 8, 36), BackgroundTransparency = 1, BorderSizePixel = 0, Position = S(0, 0.6), Size = S(1, 0.4), Visible = false, ZIndex = 38 }, cv)
	HS.corner(desc, 22)
	new("UIGradient", { Rotation = 90, Color = CS(col:Lerp(RGB(18, 8, 36), 0.55), RGB(14, 6, 28)) }, desc)
	c.DescLine = new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), ZIndex = 39 }, desc)
	c.DescText = HS.text(desc, { Text = info.Desc, Font = HS.MontX, TextSize = 19, Color = WHITE, Stroke = 1.6, StrokeColor = BLACK, Wrapped = true, Position = O(16, 10), Size = UDim2.new(1, -32, 1, -20), ZIndex = 40 })
	c.DescText.TextWrapped = true
	c.Desc = desc
	-- chips
	local chips = new("Frame", { Name = "Chips", BackgroundTransparency = 1, AnchorPoint = V2(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 40), ZIndex = 36 }, cv)
	c.Chips = chips
	local function chip(text, xa, dotCol)
		local f = new("Frame", { BackgroundColor3 = RGB(12, 6, 24), BackgroundTransparency = 0.15, AnchorPoint = V2(xa, 0), Position = S(xa, 0), Size = O(112, 38), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 36 }, chips)
		HS.corner(f, UDim.new(0.5, 0))
		local st = HS.stroke(f, 2.5, WHITE)
		new("UIGradient", { Rotation = 90, Color = CS(col:Lerp(WHITE, 0.4), col) }, st)
		new("UIPadding", { PaddingLeft = UDim.new(0, if dotCol then 30 else 14), PaddingRight = UDim.new(0, 14) }, f)
		local t = HS.text(f, { Text = text, Font = HS.MontX, TextSize = 19, Stroke = 1.6, StrokeColor = BLACK, Size = S(0, 1), ZIndex = 37 })
		t.AutomaticSize = Enum.AutomaticSize.X
		local d
		if dotCol then
			d = new("Frame", { BackgroundColor3 = dotCol, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, -15, 0.5, 0), Size = O(11, 11), ZIndex = 37 }, f)
			HS.corner(d, UDim.new(0.5, 0))
		end
		return t, d
	end
	if not c.Locked then
		chip(info.Size, 0)
		c.QueueText, c.Dot = chip("", 1, GREEN)
	end
	-- light sweep over the art
	self:_sweep(cv, O(0, 0), S(1, 1), UDim.new(0, 26), 37, 0.28, 4.6)
	-- locked overlay
	if c.Locked then
		local dim = new("Frame", { BackgroundColor3 = RGB(8, 4, 16), BackgroundTransparency = 0.48, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 41 }, cv)
		HS.corner(dim, 26)
		c.Bg.ImageColor3, c.Hero.ImageColor3 = RGB(150, 146, 170), RGB(160, 156, 180)
		local lk = skin(new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.56), Size = O(86, 105), ZIndex = 45 }, root), "lock")
		c.Lock = lk
		local pill = skin(new("ImageLabel", { Name = "Soon", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = O(230, 60), ZIndex = 45 }, root), "pill")
		self:_label(pill, { Text = info.LockText or "COMING SOON", TextSize = 24, Stroke = 2.6, Position = O(0, -3), Size = S(1, 1), ZIndex = 47 })
	end
	-- rim: dark border + neon stroke with a travelling white wink
	local rimF = new("Frame", { Name = "Rim", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 42 }, root)
	HS.corner(rimF, 26)
	local dk = HS.stroke(rimF, 9, RGB(10, 4, 20))
	dk.Transparency = 0.1
	local rimF2 = new("Frame", { Name = "Neon", BackgroundTransparency = 1, Position = O(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 43 }, root)
	HS.corner(rimF2, 23)
	c.RimStroke = HS.stroke(rimF2, 4.5, WHITE)
	c.RimGrad = new("UIGradient", {}, c.RimStroke)
	-- title on top (outside the canvas so the stroke stays crisp)
	local ts = math.min(48, math.floor(298 / (#info.Title * 0.56)))
	c.Title = self:_label(root, { Name = "Title", Text = info.Title, TextSize = ts, Stroke = 4, StrokeColor = RGB(12, 6, 22), AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(1, -16, 0, ts + 10), ZIndex = 46 })
	if c.Locked then c.Title.TextColor3 = RGB(200, 196, 214) end
	-- selected check
	c.Check = skin(new("ImageLabel", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), Size = O(66, 53), Visible = false, ZIndex = 48 }, root), "check")
	-- interaction
	root.MouseEnter:Connect(function()
		c.Hover = true
		self.Focus = c
		self:_backdrop(c)
		if HS.sound then pcall(HS.sound, "Hover") end
	end)
	root.MouseLeave:Connect(function() c.Hover = false end)
	HS.press(root, function()
		if c.Locked then
			if HS.sound then pcall(HS.sound, "Error") end
			c.Shake = 0.35
			return
		end
		if info.Index and self.Env.SelectMode then self.Env.SelectMode(info.Index, true) end
	end, { Hover = 1, Press = 0.96, Sound = if c.Locked then false else "Click" })
	table.insert(self.Cards, c)
	return c
end

------------------------------------------------------------------ build
function M:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "ModesHS", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	-- stage: oversized so it always covers the screen whatever the modal layer's scale
	local stage = new("Frame", { Name = "Stage", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, 4000, 1, 3000), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 20 }, root)
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(22, 10, 44)), CK(0.5, RGB(12, 6, 28)), CK(1, RGB(6, 3, 14)) }) }, stage)
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1920, 1080), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit
	-- backdrop art (hovered mode), bands, nebulae, motes, vignette
	local bd = new("Frame", { Name = "Backdrop", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(2600, 1500), ZIndex = 20 }, fit)
	self.BackA = new("ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Stretch, ImageTransparency = 1, Size = S(1, 1), ZIndex = 20 }, bd)
	self.BackB = new("ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Stretch, ImageTransparency = 1, Size = S(1, 1), ZIndex = 20 }, bd)
	self.BackFade = 1
	self.Bands = new("ImageLabel", { Name = "Bands", BackgroundTransparency = 1, Image = BANDS, ImageColor3 = RGB(200, 160, 255), ImageTransparency = 0.35, ScaleType = Enum.ScaleType.Stretch, Size = S(1, 1), ZIndex = 21 }, bd)
	for _, nb in { { RGB(140, 60, 255), S(0.22, 0.4), 0.7 }, { RGB(40, 170, 255), S(0.82, 0.6), 0.8 }, { RGB(255, 80, 200), S(0.55, 0.95), 0.86 } } do
		local im = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = nb[1], ImageTransparency = nb[3], AnchorPoint = V2(0.5, 0.5), Position = nb[2], Size = S(0.6, 0.9), ZIndex = 21 }, bd)
		table.insert(self.Nebula, { I = im, Base = nb[2], Tr = nb[3] })
	end
	local vig = new("Frame", { BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 22 }, bd)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.15), NK(0.3, 0.75), NK(0.7, 0.75), NK(1, 0.05) }) }, vig)
	local motes = new("Frame", { Name = "Motes", BackgroundTransparency = 1, Size = O(1920, 1080), ZIndex = 22 }, fit)
	self:_embers(motes, 34, RGB(196, 150, 255), RGB(110, 230, 255), 6, 22)
	self:_twinkles(motes, 12, RGB(226, 206, 255), 28, 22)

	-- title
	self:_label(fit, { Text = "Game Modes", TextSize = 72, Stroke = 5, StrokeColor = RGB(20, 8, 36), Grad = CS(WHITE, RGB(220, 196, 255)), X = LEFT, Position = O(100, 34), Size = O(900, 84), ZIndex = 47 })
	local shine = HS.text(fit, { Text = "Game Modes", TextSize = 72, Color = WHITE, X = LEFT, Position = O(100, 34), Size = O(900, 84), ZIndex = 48 })
	local sg = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 0.55), NK(0.5, 0.25), NK(0.52, 0.55), NK(0.58, 1), NK(1, 1) }) }, shine)
	table.insert(self.Sweeps, { G = sg, P = 1, Period = 5 })
	self:_label(fit, { Text = "Pick your fight. Hover a mode for the briefing.", Font = HS.MontX, TextSize = 22, Stroke = 2, Color = MUTED, X = LEFT, Position = O(104, 112), Size = O(900, 30), ZIndex = 47 })

	-- dividers (bright centre, a light pulse runs along them)
	local function divider(y)
		local d = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(100, y), Size = O(1720, 4), ZIndex = 24 }, fit)
		new("UIGradient", { Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.5, WHITE), CK(1, RGB(255, 110, 220)) }), Transparency = NS({ NK(0, 1), NK(0.12, 0.45), NK(0.5, 0.05), NK(0.88, 0.45), NK(1, 1) }) }, d)
		local run = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = S(0, 0.5), Size = O(220, 8), ZIndex = 25 }, d)
		new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0), NK(1, 1) }) }, run)
		HS.corner(run, UDim.new(0.5, 0))
		table.insert(self.Lines, { F = run, P = math.random() })
		new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(200, 160, 255), ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(900, 90), ZIndex = 23 }, d)
	end
	divider(160)
	divider(586)

	-- section labels
	local function section(name, y, sub)
		self:_label(fit, { Text = name, TextSize = 76, Stroke = 5, StrokeColor = RGB(16, 8, 30), X = LEFT, Position = O(100, y), Size = O(300, 90), ZIndex = 40 })
		self:_label(fit, { Text = sub, Font = HS.MontX, TextSize = 20, Stroke = 2, Color = MUTED, X = LEFT, Position = O(104, y + 88), Size = O(290, 52), ZIndex = 40 }).TextWrapped = true
	end
	section("Casual", ROWS.Casual + 100, "Jump in. No points on the line.")
	section("Ranked", ROWS.Ranked + 10, "Earn RP. Climb Wood to Legend.")
	-- player rank under "Ranked"
	self.RankBadge = new("ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(165, ROWS.Ranked + 210), Size = O(118, 118), ZIndex = 41 }, fit)
	self.RankBloom = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = O(165, ROWS.Ranked + 210), Size = O(220, 200), ZIndex = 40 }, fit)
	self.RankBase = O(165, ROWS.Ranked + 210)
	self.RankName = self:_label(fit, { Text = "", TextSize = 34, Stroke = 3, X = LEFT, Position = O(234, ROWS.Ranked + 172), Size = O(200, 40), ZIndex = 41 })
	self.RankGrad = new("UIGradient", { Rotation = 90 }, self.RankName)
	self.RankRP = self:_label(fit, { Text = "", TextSize = 26, Stroke = 2.6, Color = GREEN, X = LEFT, Position = O(234, ROWS.Ranked + 212), Size = O(200, 32), ZIndex = 41 })

	-- cards
	local byId = {}
	for i, m in self.Env.Modes or {} do byId[m.Id] = { M = m, I = i } end
	local function info(idk, extra)
		local e = byId[idk]
		local m = e and e.M or {}
		local t = {
			Key = idk, Art = idk, Index = e and e.I, Title = TITLES[idk] or m.Name or idk, Color = m.Color or "Purple",
			Desc = m.Desc or "", Size = if m.Sizes and #m.Sizes > 1 then (m.Sizes[1] .. "v" .. m.Sizes[1] .. "-" .. m.Sizes[#m.Sizes] .. "v" .. m.Sizes[#m.Sizes]) elseif (m.TeamSize or 0) > 0 then (m.TeamSize .. "v" .. m.TeamSize) else "Objective",
			Locked = not (m.Live == true), Id = idk,
		}
		for k, v in extra or {} do t[k] = v end
		return t
	end
	local casual = { "TDM", "TAC", "DUEL", "CTF" }
	for i, k in casual do
		self:_card(fit, info(k), X0 + (i - 1) * (CARD + GAP), ROWS.Casual)
	end
	self:_card(fit, info("RTDM"), X0, ROWS.Ranked)
	self:_card(fit, info("DUEL", { Key = "RDUEL", Title = "Ranked Shootout", Color = "Purple", Size = "1v1", Locked = true, Index = nil, Desc = "One opponent, Ranked Points on the line." }), X0 + CARD + GAP, ROWS.Ranked)

	-- BACK
	self:_btn(fit, { Name = "Back", Skin = "back", Text = "BACK", TextSize = 38, Stroke = 3, Position = O(60, 976), Size = O(250, 78), Z = 48, Sound = "Click", OnClick = function()
		if self.Env.Close then self.Env.Close() end
	end })
end

function M:_backdrop(c)
	if self.BackCard == c then return end
	self.BackCard = c
	self.BackA, self.BackB = self.BackB, self.BackA
	self.BackA.Image = c.Data.Bg
	self.BackA.ImageColor3 = c.Col:Lerp(WHITE, 0.55)
	self.BackFade = 0
end

------------------------------------------------------------------ refresh / step
function M:_refresh()
	local legend = self:_attr("RankLegend") == true
	local rp = tonumber(self:_attr("RP")) or 0
	local r = R.RankOf(rp, legend)
	self.RankBadge.Image, self.RankBadge.ImageColor3 = r.Rank.Badge, r.Rank.Tint or WHITE
	self.RankBloom.ImageColor3 = r.Rank.Color
	self.RankName.Text = r.Name
	self.RankGrad.Color = CS(WHITE, r.Rank.Color:Lerp(WHITE, 0.2))
	self.RankRP.Text = tostring(rp) .. " RP"
	local mf = Vantage:FindFirstChild("Match")
	local sel = self.Env.State and self.Env.State.Selected
	for _, c in self.Cards do
		if c.QueueText then
			local n = (mf and mf:GetAttribute("Queue_" .. c.Info.Id)) or (self.Env.Attr and self.Env.Attr["Queue_" .. c.Info.Id]) or 0
			c.QueueText.Text = n .. " in queue"
		end
		c.Selected = c.Info.Index ~= nil and c.Info.Index == sel
		c.Check.Visible = c.Selected
	end
	if not self.BackCard and self.Cards[1] then self:_backdrop(self.Cards[1]) end
end

function M:_step(dt)
	local t = os.clock()
	for _, sw in self.Sweeps do
		local u = ((t + sw.P) % (sw.Period or 3.6)) / 0.9
		sw.G.Offset = V2(if u < 1 then -1 + 2 * u else 1, 0)
	end
	for _, ln in self.Lines do
		ln.F.Position = S(((t * 0.22 + ln.P) % 1.2) - 0.1, 0.5)
	end
	-- stage
	local zz = 1.06 + 0.05 * (0.5 + 0.5 * math.sin(t * 0.27))
	local rw, rh = 1024 / zz, 640 / zz
	self.Bands.ImageRectSize = V2(rw, rh)
	self.Bands.ImageRectOffset = V2((1024 - rw) * (0.5 + math.sin(t * 0.17) * 0.45), (640 - rh) * (0.5 + math.cos(t * 0.13) * 0.45))
	for i, nb in self.Nebula do
		nb.I.Position = nb.Base + UDim2.fromScale(math.sin(t * 0.13 + i * 2) * 0.06, math.cos(t * 0.11 + i) * 0.05)
		nb.I.ImageTransparency = nb.Tr + math.sin(t * 0.7 + i) * 0.06
	end
	self.BackFade = math.min(1, self.BackFade + dt * 2.2)
	self.BackA.ImageTransparency = 1 - 0.3 * self.BackFade
	self.BackB.ImageTransparency = 1 - 0.3 * (1 - self.BackFade)
	for _, b in { self.BackA, self.BackB } do
		local src = b == self.BackA and self.BackCard and self.BackCard.Data.Src or V2(1024, 1024)
		local bz = 1.1 + 0.06 * math.sin(t * 0.09)
		local w, h = src.X / bz, math.min(src.Y, src.X * (1500 / 2600)) / bz
		b.ImageRectSize = V2(w, h)
		b.ImageRectOffset = V2((src.X - w) * (0.5 + 0.45 * math.sin(t * 0.07)), (src.Y - h) * (0.5 + 0.4 * math.cos(t * 0.06)))
	end
	self.RankBadge.Position = self.RankBase + O(0, math.sin(t * 1.5) * 5)
	self.RankBloom.ImageTransparency = 0.4 + 0.15 * math.sin(t * 2.2)
	-- cards
	for _, c in self.Cards do
		local target = if c.Hover then 1 else 0
		c.H += (target - c.H) * math.min(1, dt * 11)
		local h = c.H
		local shake = 0
		if c.Shake then
			c.Shake -= dt
			shake = if c.Shake > 0 then math.sin(t * 60) * 6 * c.Shake else 0
			if c.Shake <= 0 then c.Shake = nil end
		end
		c.Scale.Scale = 1 + 0.05 * h
		c.Root.Rotation = -1.4 * h + shake * 0.3
		local ph = c.Ph
		-- Ken Burns plate + parallax hero
		local d = c.Data
		local W, H = d.Src.X, d.Src.Y
		local zb = 1.1 + 0.05 * math.sin(t * 0.23 + ph) + 0.07 * h
		local wv = math.min(W, H) / zb
		local px = if W > H then math.sin(t * 0.11 + ph) * 0.48 else math.sin(t * 0.17 + ph) * 0.42
		local py = math.cos(t * 0.13 + ph) * 0.42
		local ox, oy = (W - wv) * (0.5 + px), (H - wv) * (0.5 + py)
		c.Bg.ImageRectOffset, c.Bg.ImageRectSize = V2(ox, oy), V2(wv, wv)
		local sc = CARD / wv
		local par = d.Par or 0.25
		local hx = ox + ((W - wv) * 0.5 - ox) * par
		local hy = oy + ((H - wv) * 0.5 - oy) * par
		local b = d.Box
		local hz = 1 + 0.025 * h
		local bob = math.sin(t * 1.3 + ph) * 3.5
		local cw, ch = b[3] * sc * hz, b[4] * sc * hz
		local cx, cy = (b[1] - hx) * sc - (cw - b[3] * sc) * 0.5, (b[2] - hy) * sc - (ch - b[4] * sc) + bob
		local x0, y0 = math.max(cx, 4), math.max(cy, 4)
		local x1, y1 = math.min(cx + cw, CARD - 4), math.min(cy + ch, CARD - 4)
		if x1 <= x0 or y1 <= y0 then
			c.Hero.Visible = false
		else
			local kx, ky = b[3] / cw, b[4] / ch
			c.Hero.Visible = true
			c.Hero.ImageRectOffset = V2((x0 - cx) * kx, (y0 - cy) * ky)
			c.Hero.ImageRectSize = V2((x1 - x0) * kx, (y1 - y0) * ky)
			c.Hero.Position, c.Hero.Size = O(x0, y0), O(x1 - x0, y1 - y0)
		end
		-- rim / glow / selection
		local col = if c.Selected then GREEN else c.Col
		c.RimGrad.Rotation = (t * 70 + ph * 30) % 360
		c.RimGrad.Color = CS({ CK(0, col), CK(0.42, col), CK(0.5, WHITE), CK(0.58, col), CK(1, col) })
		c.RimStroke.Thickness = 4.5 + 1.5 * h + (if c.Selected then 1 else 0)
		c.Glow.ImageColor3 = col
		c.Glow.ImageTransparency = (if c.Locked then 0.82 else 0.55) - 0.35 * h - (if c.Selected then 0.15 else 0) + 0.06 * math.sin(t * 2 + ph)
		c.Desc.Visible = h > 0.02
		c.Desc.BackgroundTransparency = 1 - 0.9 * h
		c.DescText.TextTransparency = 1 - h
		c.DescLine.BackgroundTransparency = 1 - h
		local dst = c.DescText:FindFirstChildOfClass("UIStroke")
		if dst then dst.Transparency = 1 - h end
		c.Chips.Visible = h < 0.3
		if c.Dot then c.Dot.BackgroundTransparency = 0.5 - 0.5 * math.sin(t * 4) end
		if c.Lock then c.Lock.Rotation = math.sin(t * 1.7 + ph) * 4 end
		c.Check.Size = O(66 + math.sin(t * 3) * 3, 53 + math.sin(t * 3) * 2.4)
		-- per-mode FX
		if c.Pulse then
			local pu = c.Pulse
			local v = if pu[4] then (math.sin(t * pu[3]) * 0.5 + math.sin(t * pu[3] * 2.7) * 0.5) else math.sin(t * pu[3] + ph)
			pu[1].ImageTransparency = math.clamp(pu[2] + 0.18 * v, 0, 1)
		end
		if c.Rays then c.Rays.Rotation = (t * 9) % 360 end
		if c.Flash then
			c.FlashT -= dt
			if c.FlashT <= 0 then
				c.FlashT, c.FlashA = rnd(2.5, 5.5), 0
			end
			if c.FlashA then
				c.FlashA += dt
				local a = c.FlashA
				local v = if a < 0.08 then 0.45 elseif a < 0.16 then 0.9 elseif a < 0.24 then 0.55 elseif a < 0.6 then 0.55 + (a - 0.24) / 0.36 * 0.45 else 1
				c.Flash.BackgroundTransparency = v
				if a >= 0.6 then c.FlashA = nil end
			end
		end
		for _, p in c.P do
			if p.wait and p.wait > 0 then
				p.wait -= dt
				p.F.Visible = false
			else
				p.F.Visible = true
				p.x += p.vx * dt
				p.y += p.vy * dt
				if p.x < -0.3 or p.x > 1.35 or p.y < -0.25 or p.y > 1.25 then p.Spawn(p, false) end
				p.F.Position = S(p.x, p.y)
				local hw, hh = p.F.Size.X.Scale * 0.5, p.F.Size.Y.Scale * 0.5
				if p.F:IsA("ImageLabel") then
					local e = math.clamp(math.min(p.x, 1 - p.x, p.y, 1 - p.y) / 0.3, 0, 1)
					p.F.ImageTransparency = 1 - (1 - (p.Tr or 0.78)) * e
				else
					local ox = p.F.Size.X.Offset / CARD * 0.5
					p.F.Visible = p.x - hw - ox >= 0.02 and p.x + hw + ox <= 0.98 and p.y - hh - ox >= 0.02 and p.y + hh + ox <= 0.98
				end
				if p.fade then
					local life = if p.fade == "down" then p.y else 1 - p.y
					p.F.BackgroundTransparency = 0.1 + 0.9 * math.clamp(life, 0, 1) ^ 2
				end
			end
		end
	end
	for _, e in self.Embers do
		e.Y -= e.V * dt
		if e.Y < -0.05 then e.Y, e.X = 1.05, math.random() end
		e.F.Position = UDim2.new(e.X, math.sin(t * 1.3 + e.Sway) * 6, e.Y, 0)
		e.F.BackgroundTransparency = 0.2 + 0.8 * math.clamp(1 - e.Y, 0, 1) ^ 2
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
function M:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.4, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
end

function M:OnShow()
	self:_fit()
	for _, c in self.Cards do c.Hover, c.H = false, 0 end
	self:_refresh()
end

function M.Mount(layer, env)
	local s = M.new(layer, env)
	if player then
		for _, a in { "RP", "RankLegend" } do
			player:GetAttributeChangedSignal(a):Connect(function()
				if s.Root.Visible then s:_refresh() end
			end)
		end
	end
	return { Root = s.Root, OnShow = function() s:OnShow() end, Object = s }
end

return M
