--[[
	VANTAGE — CratesScreen (client): the Store › Crates tab (design canvas board "Crates.dc.html", 2026-11-16).
	Art is the board's own PNGs (CrateConfig.Images / crate Art), so the screen matches the canvas.
	  banner   tinted shard image (Apex cross-fades hues), crate (body + lid peeks), rays, rings, 3 top-drop guns (CardArt photos)
	  panel    drop odds per rarity, pity bar, Open button (price in REQ), Fast open toggle
	  cards    4 crates, cheapest → best, each with art, 3 skin previews + "+N", pity bar and price
	Opening is handed to CrateOpening (opts.Opening:Play(crate, { Fast })).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Skins = require(Vantage:WaitForChild("Weapons"):WaitForChild("Skins"))
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local K = require(script.Parent:WaitForChild("ScreenKit"))
local CardArt = require(script.Parent:WaitForChild("CardArt"))
local UX = require(script.Parent:WaitForChild("CrateUX"))

local player = Players.LocalPlayer
local C = Color3.fromRGB
local V2 = Vector2.new
local S, O = UDim2.fromScale, UDim2.fromOffset
local CS, CK, NS, NK = ColorSequence.new, ColorSequenceKeypoint.new, NumberSequence.new, NumberSequenceKeypoint.new
local INK = C(5, 6, 13)
local WHITE = Color3.new(1, 1, 1)
local RAINBOW = K.CHROMA or CS({ CK(0, C(255, 92, 92)), CK(0.5, C(90, 255, 160)), CK(1, C(255, 92, 200)) })
local function chromaOf(r)
	local c = K.CHROMAS and K.CHROMAS[r]
	return (c and c.Grad) or RAINBOW
end
local function shade(c, k)
	return c:Lerp(Color3.new(0, 0, 0), k)
end

-- crate PNG framing (art = the board's crate box)
local ART_W, ART_H, ART_DX, ART_DY = 439, 304, -9.5, 23
local HEX = V2(0.5, 0.628) -- REQ coin centre on the art
-- featured guns: board positions, enlarged; cells are 2:1 with the glow baked in
local GUNS = { { 500, -40, 760, 380, -9 }, { 600, 168, 660, 330, 6 }, { 540, 330, 700, 350, -5 } }

local CratesScreen = {}
CratesScreen.__index = CratesScreen

local function grad(colors, rot)
	local kps = {}
	for i, c in colors do
		table.insert(kps, CK((i - 1) / math.max(1, #colors - 1), c))
	end
	return { Color = CS(kps), Rotation = rot or 0 }
end

function CratesScreen.new(opts)
	local self = setmetatable({}, CratesScreen)
	self.Opts, self.G = opts, opts.G
	self.Sel = 4
	self.Fast = false
	self.Shown = false
	self.Gui, self.Canvas, self.ToScreen = K.screen("VantageCrates", 13)
	self:_build()
	player.AttributeChanged:Connect(function(n)
		if self.Shown and (string.sub(n, 1, 10) == "CratePity_" or n == "OwnedSkins") then
			self:_select(self.Sel, false)
		end
	end)
	return self
end

function CratesScreen:_chip(parent, rarity, pos, h)
	local G = self.G
	local col = Config.TierColor[rarity] or WHITE
	local f = G.new("Frame", { Name = "Chip", Position = pos, Size = O(0, h or 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, ZIndex = 12 }, parent)
	G.corner(f, 9)
	G.stroke(f, 3, INK)
	local g = G.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, col:Lerp(WHITE, 0.6)), CK(0.55, col), CK(1, shade(col, 0.5)) }) }, f)
	if rarity == "Godly" or rarity == "Exclusive" then
		g.Color = chromaOf(rarity)
		g.Rotation = 0
		self.Chroma[g] = true
	end
	G.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, f)
	G.text(f, { Text = string.upper(rarity), Size = O(0, h or 30), Auto = Enum.AutomaticSize.X, TextSize = 15, Stroke = 3, ZIndex = 13 })
	G.glow(f, { Color = col, Transparency = 0.86, Size = UDim2.new(1, 24, 1, 24), ZIndex = 11 })
	return f
end

-- a chunky gradient button with the black outline + gloss of the board's CTAs
function CratesScreen:_button(parent, p)
	local G = self.G
	local b = G.new("TextButton", { Name = p.Name or "Button", Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, Position = p.Position, Size = p.Size, AnchorPoint = p.AnchorPoint or V2(0, 0), ZIndex = p.ZIndex or 10 }, parent)
	G.corner(b, p.Radius or 16)
	G.stroke(b, 4, INK)
	G.new("UIGradient", grad(p.Colors, 90), b)
	local gloss = G.new("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, Position = S(0.03, 0.06), Size = S(0.94, 0.42), ZIndex = b.ZIndex }, b)
	G.corner(gloss, p.Radius or 14)
	G.new("UIGradient", { Rotation = 90, Transparency = NS(0.5, 1) }, gloss)
	local bloom = G.glow(b, { Color = p.Glow or p.Colors[2], Transparency = 0.85, Size = UDim2.new(1.3, 0, 2.2, 0), ZIndex = b.ZIndex - 1 })
	local lab = G.text(b, { Name = "Label", Text = p.Text or "", Size = S(1, 1), TextSize = p.TextSize or 30, Stroke = 4, ZIndex = b.ZIndex + 3, Rich = true })
	if p.Icon then
		lab.Size = UDim2.new(1, -40, 1, 0)
		lab.Position = O(40, 0)
		G.new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = p.Icon, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, p.IconX or 54, 0.5, 0), Size = O(p.IconSize or 54, p.IconSize or 54), ZIndex = b.ZIndex + 3 }, b)
	end
	local ctl = UX.bind(b, "secondary", { OnClick = p.OnClick, Bloom = bloom, Stroke = b:FindFirstChildOfClass("UIStroke") })
	return b, lab, ctl
end

-- the crate art: body + lid layers, glowing REQ coin
function CratesScreen:_crate(parent, crate, pos, scale, z)
	local G = self.G
	local root = G.new("Frame", { Name = "Crate", BackgroundTransparency = 1, Position = pos, Size = O(ART_W * scale, ART_H * scale), ZIndex = z }, parent)
	G.glow(root, { Name = "Aura", Color = crate.Color, Transparency = 0.35, Size = S(1.7, 1.9), ZIndex = z - 1 })
	G.new("ImageLabel", { Name = "Body", BackgroundTransparency = 1, Image = crate.Art.Body, Size = S(1, 1), ZIndex = z }, root)
	local lid = G.new("ImageLabel", { Name = "Lid", BackgroundTransparency = 1, Image = crate.Art.Lid, Size = S(1, 1), ZIndex = z + 1 }, root)
	local coin = G.new("ImageLabel", { Name = "Coin", BackgroundTransparency = 1, Image = G.A.Icon.Req, AnchorPoint = V2(0.5, 0.5), Position = S(HEX.X, HEX.Y), Size = S(0.24, 0.35), ZIndex = z + 2 }, root)
	local leak = G.glow(root, { Name = "Leak", Color = crate.Light, Transparency = 1, Position = S(0.5, 0.33), Size = S(1.1, 0.5), ZIndex = z + 1 })
	return { Root = root, Lid = lid, Coin = coin, Leak = leak, Scale = scale }
end

-- ─── build ──────────────────────────────────────────────────────────────────────────────
function CratesScreen:_build()
	local G, cv, gui = self.G, self.Canvas, self.Gui
	self.Chroma = {}
	local bg = G.new("Frame", { Name = "Backdrop", Size = S(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0 }, gui)
	G.new("UIGradient", { Rotation = 70, Color = CS({ CK(0, C(14, 26, 92)), CK(0.4, C(10, 18, 64)), CK(0.72, C(8, 11, 44)), CK(1, C(18, 10, 54)) }) }, bg)
	G.new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = Config.Images.Backdrop, ScaleType = Enum.ScaleType.Crop, Size = S(1, 1), ZIndex = 0 }, bg)
	self.Blob1 = G.glow(bg, { Name = "Blob1", Color = C(22, 200, 255), Transparency = 0.86, Position = S(0.08, 0.02), Size = S(0.62, 0.9), ZIndex = 0 })
	self.Blob2 = G.glow(bg, { Name = "Blob2", Color = C(139, 92, 255), Transparency = 0.8, Position = S(0.92, 1.02), Size = S(0.7, 1), ZIndex = 0 })
	local dots = G.new("ImageLabel", { Name = "Dots", BackgroundTransparency = 1, Image = G.A.Dots, ScaleType = Enum.ScaleType.Tile, TileSize = O(22, 22), ImageColor3 = C(124, 243, 255), ImageTransparency = 0.84, Size = S(1, 1), ZIndex = 0 }, bg)
	G.new("UIGradient", { Rotation = 160, Transparency = NS({ NK(0, 0), NK(0.4, 1), NK(0.65, 1), NK(1, 0) }) }, dots)
	self.Sweep = G.new("Frame", { Name = "Sweep", AnchorPoint = V2(0.5, 0.5), Position = S(-0.3, 0.5), Size = S(0.16, 2), Rotation = 18, BackgroundColor3 = C(124, 243, 255), BackgroundTransparency = 0.92, BorderSizePixel = 0, ZIndex = 0 }, bg)
	G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.2), NK(1, 1) }) }, self.Sweep)
	self.Twinkles = {}
	for _ = 1, 26 do
		local s = G.new("Frame", { Name = "Twk", AnchorPoint = V2(0.5, 0.5), Position = S(math.random(), math.random()), Size = O(3, 3), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0 }, bg)
		G.corner(s, UDim.new(1, 0))
		table.insert(self.Twinkles, { F = s, Ph = math.random() * 6, Sp = 0.6 + math.random() })
	end

	local h = K.header(G, cv, {
		Title = "Store", Sub = "Supply crates · spend REQ, unbox skins", Active = "Crates",
		OnBack = function() self.Opts.OnBack() end,
		OnTab = function(n) if self.Opts.OnTab then self.Opts.OnTab(n) end end,
		OnStore = self.Opts.OnStore,
	})
	-- tabs: Crates (here) | Skins (Loadout)
	local oldTabs = (type(h) == "table" and h.Tabs) or cv:FindFirstChild("Tabs")
	if oldTabs then
		oldTabs:Destroy()
	end
	local tabs = G.glass(cv, { Name = "Tabs", Position = UDim2.new(0.5, 0, 0, 32), AnchorPoint = V2(0.5, 0), Size = O(460, 60), Radius = UDim.new(1, 0), TopLine = false, EdgeTransparency = 0.5, ZIndex = 10 })
	local x = 5
	for _, t in { { "Featured", 150 }, { "Crates", 150 }, { "Skins", 150 } } do
		local b = G.new("TextButton", { Name = t[1], Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = O(x, 5), Size = O(t[2], 50), ZIndex = 11 }, tabs)
		x += t[2]
		if t[1] == "Crates" then
			local face = G.new("Frame", { Name = "Face", Size = S(1, 1), ZIndex = 11 }, b)
			face.BackgroundColor3 = WHITE
			G.corner(face, UDim.new(1, 0))
			G.stroke(face, 3, INK)
			G.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, C(255, 243, 196)), CK(0.5, C(255, 176, 46)), CK(1, C(224, 86, 15)) }) }, face)
			G.glow(face, { Color = C(255, 176, 46), Transparency = 0.55, Size = S(1.4, 2), ZIndex = 10 })
			G.text(b, { Text = t[1], TextSize = 25, Stroke = 3.2, ZIndex = 14 })
		else
			local lab = G.text(b, { Text = t[1], TextSize = 25, Stroke = 0, Color = G.C.Muted, ZIndex = 14 })
			local fill = G.new("Frame", { Name = "Hover", BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 11 }, b)
			G.corner(fill, UDim.new(1, 0))
			UX.bind(b, "tab", { OnHover = function(on)
				UX.tween(lab, 0.12, { TextColor3 = if on then WHITE else G.C.Muted })
				UX.tween(fill, 0.12, { BackgroundTransparency = if on then 0.9 else 1 })
			end, OnClick = function()
				if t[1] == "Featured" then
					self:_select(4, true)
				elseif self.Opts.OnTab then
					self.Opts.OnTab("Loadout")
				end
			end })
		end
	end

	-- the 1920-wide board layout, centred on any aspect ratio
	self.Body = G.new("Frame", { Name = "Body", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(1920, 1080), ZIndex = 1 }, cv)
	self:_buildBanner()
	self:_buildPanel()
	self:_buildCards()
	self.Toast = K.toast(G, cv)
end

function CratesScreen:_buildBanner()
	local G, cv = self.G, self.Body
	local glow = G.new("Frame", { Name = "BannerGlow", BackgroundTransparency = 1, Position = O(40, 128), Size = O(1200, 620), ZIndex = 2 }, cv)
	self.BannerAura = G.glow(glow, { Color = C(236, 72, 255), Transparency = 0.72, Size = UDim2.new(1, 160, 1, 160), ZIndex = 1 })
	local b = G.new("Frame", { Name = "Banner", Position = O(40, 128), Size = O(1200, 620), BackgroundColor3 = C(10, 12, 48), ClipsDescendants = true, ZIndex = 3 }, cv)
	G.corner(b, 28)
	self.Banner = b
	self.BgA = G.new("ImageLabel", { Name = "ArtA", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.1, 1.1), ZIndex = 3 }, b)
	self.BgB = G.new("ImageLabel", { Name = "ArtB", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.1, 1.1), ZIndex = 3 }, b)
	local dark = G.new("Frame", { Name = "TitleShade", BackgroundColor3 = C(5, 6, 20), Size = S(1, 1), BorderSizePixel = 0, ZIndex = 4 }, b)
	G.new("UIGradient", { Rotation = 25, Transparency = NS({ NK(0, 0.45), NK(0.38, 1), NK(1, 1) }) }, dark)
	self.Streaks = {}
	for _ = 1, 7 do
		local s = G.new("Frame", { Name = "Streak", AnchorPoint = V2(0, 0.5), Size = O(260, 3), Rotation = -38, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5 }, b)
		G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.7, 0.2), NK(1, 0) }) }, s)
		table.insert(self.Streaks, { F = s, X = -200 + math.random() * 1100, Y = 320 + math.random() * 420, T = 2.4 + math.random() * 2.6, Ph = math.random() * 5 })
	end
	self.Rays = G.new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = Config.Images.Rays, ImageTransparency = 0.82, AnchorPoint = V2(0.5, 0.5), Position = O(460, 400), Size = O(1000, 1000), ZIndex = 5 }, b)
	local function ring(size, th, tr, speed)
		local r = G.new("Frame", { Name = "Ring", AnchorPoint = V2(0.5, 0.5), Position = O(460, 400), Size = O(size, size), BackgroundTransparency = 1, ZIndex = 5 }, b)
		G.corner(r, UDim.new(1, 0))
		local st = G.new("UIStroke", { Thickness = th, Color = WHITE, Transparency = tr }, r)
		G.new("UIGradient", { Transparency = NS({ NK(0, 0), NK(0.25, 0.85), NK(0.5, 0.2), NK(0.75, 0.9), NK(1, 0) }) }, st)
		return { F = r, St = st, Speed = speed }
	end
	self.Rings = { ring(520, 2, 0.4, 14), ring(420, 3, 0.1, -90) }
	local pod = G.new("Frame", { Name = "Podium", AnchorPoint = V2(0.5, 0.5), Position = O(460, 572), Size = O(540, 96), BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, ZIndex = 5 }, b)
	G.corner(pod, UDim.new(1, 0))
	self.PodStroke = G.new("UIStroke", { Thickness = 3, Color = WHITE, Transparency = 0.2 }, pod)
	self.PodGlow = G.glow(pod, { Color = WHITE, Transparency = 0.4, Size = S(1.3, 2.2), ZIndex = 4 })
	self.Guns = {}
	for i, g in GUNS do
		local holder = G.new("Frame", { Name = "Gun" .. i, BackgroundTransparency = 1, Position = O(g[1], g[2]), Size = O(g[3], g[4]), Rotation = g[5], ZIndex = 6 }, b)
		local glowI = G.glow(holder, { Color = WHITE, Transparency = 0.8, Size = S(0.9, 0.8), ZIndex = 6 })
		local img = G.new("ImageLabel", { Name = "Photo", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = 7 }, holder)
		local flash = G.new("ImageLabel", { Name = "Flash", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ImageColor3 = WHITE, ImageTransparency = 1, ZIndex = 8 }, holder)
		local chipHolder = G.new("Frame", { Name = "ChipHolder", BackgroundTransparency = 1, AnchorPoint = V2(1, 1), Position = S(0.84, 0.86), Size = O(1, 30), ZIndex = 12 }, holder)
		table.insert(self.Guns, { Holder = holder, Img = img, Flash = flash, Glow = glowI, ChipHolder = chipHolder, Home = holder.Position, Ph = i * 1.4, T0 = 0 })
	end
	self.CrateHolder = G.new("Frame", { Name = "CrateHolder", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 8 }, b)
	self.Featured = G.new("Frame", { Name = "Featured", BackgroundColor3 = C(10, 8, 40), BackgroundTransparency = 0.3, Position = O(44, 34), Size = O(210, 32), ZIndex = 12 }, b)
	G.corner(self.Featured, UDim.new(1, 0))
	G.stroke(self.Featured, 2, C(200, 253, 255), 0.25)
	G.text(self.Featured, { Text = "FEATURED CRATE", TextSize = 15, Stroke = 0, Color = C(200, 253, 255), Font = G.F.Bold, ZIndex = 13 })
	self.Title = G.text(b, { Name = "Title", Text = "", Position = O(44, 76), Size = O(700, 70), X = Enum.TextXAlignment.Left, TextSize = 66, Stroke = 5, ZIndex = 12 })
	self.Sub = G.text(b, { Name = "Sub", Text = "", Position = O(46, 146), Size = O(700, 30), X = Enum.TextXAlignment.Left, TextSize = 22, Stroke = 3.5, ZIndex = 12 })
	self:_button(b, { Name = "Contents", Text = "CONTENTS & ODDS", Position = O(44, 196), Size = O(250, 48), TextSize = 20, Radius = 13, ZIndex = 12,
		Colors = { C(255, 243, 196), C(255, 194, 58), C(255, 138, 26) },
		OnClick = function() self.Toast("Drop odds are listed on the right") end })
	local rim = G.new("Frame", { Name = "Rim", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 20 }, b)
	G.corner(rim, 28)
	self.RimStroke = G.new("UIStroke", { Thickness = 4, Color = WHITE }, rim)
	self.RimGrad = G.new("UIGradient", {}, self.RimStroke)
end

function CratesScreen:_buildPanel()
	local G, cv = self.G, self.Body
	local p = K.panel(G, cv, { Name = "Odds", Position = UDim2.new(0, 1280, 0, 128), Size = O(600, 620), ZIndex = 4 })
	p.ClipsDescendants = false
	self.Panel = p
	local head = G.new("Frame", { Name = "Head", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 82), ZIndex = 5 }, p)
	G.corner(head, 24)
	self.HeadGrad = G.new("UIGradient", { Rotation = 35 }, head)
	local cover = G.new("Frame", { Name = "Square", BackgroundColor3 = WHITE, Position = O(0, 58), Size = UDim2.new(1, 0, 0, 24), BorderSizePixel = 0, ZIndex = 5 }, head)
	self.HeadGrad2 = G.new("UIGradient", { Rotation = 35 }, cover)
	local hd = G.new("ImageLabel", { Name = "Halftone", BackgroundTransparency = 1, Image = G.A.Dots, ScaleType = Enum.ScaleType.Tile, TileSize = O(11, 11), ImageTransparency = 0.6, Size = S(1, 1), ZIndex = 6 }, head)
	G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.45, 1), NK(1, 0) }) }, hd)
	G.text(p, { Text = "Drop odds", Position = O(26, 20), Size = O(300, 40), X = Enum.TextXAlignment.Left, TextSize = 32, Stroke = 4, ZIndex = 8 })
	G.text(p, { Text = "Server roll", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -26, 0, 24), Size = O(200, 32), X = Enum.TextXAlignment.Right, TextSize = 17, Stroke = 3, ZIndex = 8, Font = G.F.Bold })
	self.OddsList = G.new("Frame", { Name = "Rows", BackgroundTransparency = 1, Position = O(26, 100), Size = UDim2.new(1, -52, 0, 270), ZIndex = 6 }, p)
	G.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, self.OddsList)
	local pity = G.new("Frame", { Name = "Pity", BackgroundColor3 = C(255, 176, 46), BackgroundTransparency = 0.8, Size = UDim2.new(1, -52, 0, 76), Position = O(26, 372), ZIndex = 6 }, p)
	G.corner(pity, 16)
	G.stroke(pity, 2, C(255, 200, 90), 0.3)
	self.PityLabel = G.text(pity, { Text = "", Position = O(16, 8), Size = UDim2.new(1, -32, 0, 30), X = Enum.TextXAlignment.Left, TextSize = 20, Stroke = 3, ZIndex = 7, Rich = true })
	self.PityLeft = G.text(pity, { Text = "", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -16, 0, 8), Size = O(160, 30), X = Enum.TextXAlignment.Right, TextSize = 22, Stroke = 3, Color = C(255, 243, 196), ZIndex = 7 })
	local track = G.new("Frame", { Name = "Track", BackgroundColor3 = INK, BackgroundTransparency = 0.45, Position = O(16, 46), Size = UDim2.new(1, -32, 0, 16), ZIndex = 7 }, pity)
	G.corner(track, UDim.new(1, 0))
	self.PityFill = G.new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, Size = S(0, 1), ZIndex = 8 }, track)
	G.corner(self.PityFill, UDim.new(1, 0))
	G.new("UIGradient", grad({ C(224, 86, 15), C(255, 176, 46), C(255, 243, 196) }), self.PityFill)
	self.PityBox = pity
	local function cta(name, art, x, y, w, h, label, ts, onClick)
		local b = G.new("ImageButton", { Name = name, BackgroundTransparency = 1, Image = art, AutoButtonColor = false, ScaleType = Enum.ScaleType.Stretch, Position = O(x, y), Size = O(w, h + 6), ZIndex = 8 }, p)
		local bloom = G.glow(b, { Name = "Bloom", Color = if art == Config.Images.CtaGold then C(255, 176, 46) else C(22, 200, 255), Transparency = if name == "Open" then 0.62 else 0.82, Position = S(0.5, 0.45), Size = UDim2.new(1.3, 0, 2.1, 0), ZIndex = 7 })
		if name == "Open" then
			local clip = G.new("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.new(0.05, 0, 0, 6), Size = UDim2.new(0.9, 0, 0, h - 12), ZIndex = 9 }, b)
			G.shine(clip, 0, 4.6, 0.12)
		end
		local row = G.new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = O(w, h), ZIndex = 10 }, b)
		G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		G.text(row, { Name = "Label", Text = label, Size = O(0, h), Auto = Enum.AutomaticSize.X, TextSize = ts, Stroke = 4.5, ZIndex = 11, LayoutOrder = 1 })
		local pill = G.new("Frame", { Name = "Price", BackgroundTransparency = 1, Size = O(0, h), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 11 }, row)
		G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, pill)
		G.new("ImageLabel", { Name = "Req", BackgroundTransparency = 1, Image = G.A.Icon.Req, Size = O(ts * 1.4, ts * 1.4), ZIndex = 12, LayoutOrder = 1 }, pill)
		local price = G.text(pill, { Name = "Value", Text = "", Size = O(0, h), Auto = Enum.AutomaticSize.X, TextSize = ts, Stroke = 4.5, ZIndex = 12, LayoutOrder = 2 })
		local ctl = UX.bind(b, if name == "Open" then "primary" else "secondary", { OnClick = onClick, Art = b, Bloom = bloom, Sound = false, Cooldown = 0.4 })
		return b, price, ctl
	end
	self.OpenBtn, self.OpenPrice, self.OpenCtl = cta("Open", Config.Images.CtaGold, 26, 458, 300, 88, "Open", 32, function() self:_open(1) end)
	self.Open5Btn, self.Price5, self.Open5Ctl = cta("Open5", Config.Images.CtaCyan, 348, 470, 226, 76, "×5", 26, function() self:_open(5) end)
	local tg = G.new("TextButton", { Name = "Fast", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = O(28, 566), Size = O(200, 36), ZIndex = 8 }, p)
	local sw = G.new("Frame", { Name = "Switch", BackgroundColor3 = INK, BackgroundTransparency = 0.4, Position = O(0, 4), Size = O(52, 28), ZIndex = 9 }, tg)
	G.corner(sw, UDim.new(1, 0))
	G.stroke(sw, 2, C(124, 243, 255), 0.5)
	local knob = G.new("Frame", { Name = "Knob", BackgroundColor3 = C(170, 178, 220), Position = O(4, 4), Size = O(20, 20), ZIndex = 10 }, sw)
	G.corner(knob, UDim.new(1, 0))
	G.text(tg, { Text = "Fast open", Position = O(64, 0), Size = O(136, 36), X = Enum.TextXAlignment.Left, TextSize = 20, Stroke = 3, ZIndex = 9 })
	UX.bind(tg, "toggle", { Stroke = sw:FindFirstChildOfClass("UIStroke"), OnClick = function()
		self.Fast = not self.Fast
		UX.sound(if self.Fast then "ToggleOn" else "ToggleOff", if self.Fast then 1 else 0.86)
		UX.tween(knob, 0.14, { Position = if self.Fast then O(28, 4) else O(4, 4), BackgroundColor3 = if self.Fast then WHITE else C(170, 178, 220) })
		UX.tween(sw, 0.14, { BackgroundColor3 = if self.Fast then C(22, 140, 255) else INK, BackgroundTransparency = if self.Fast then 0 else 0.4 })
	end })
	self.Saves = G.text(p, { Name = "Saves", Text = "", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -28, 0, 566), Size = O(260, 36), X = Enum.TextXAlignment.Right, TextSize = 15, Stroke = 0, Color = C(170, 178, 220), Font = G.F.Bold, ZIndex = 8 })
end

function CratesScreen:_buildCards()
	local G, cv = self.G, self.Body
	self.Cards = {}
	for i, crate in Config.Crates do
		local x = 40 + (i - 1) * 466
		local b = G.new("TextButton", { Name = crate.Id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = O(x, 776), Size = O(440, 272), ZIndex = 6 }, cv)
		local glow = G.glow(b, { Color = crate.Color, Transparency = 0.9, Size = UDim2.new(1, 60, 1, 60), ZIndex = 5 })
		local face = G.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, Size = S(1, 1), ClipsDescendants = true, ZIndex = 6 }, b)
		G.corner(face, 24)
		G.new("UIGradient", grad(crate.Grad, 35), face)
		local rays = G.new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = Config.Images.Rays, ImageTransparency = 0.72, AnchorPoint = V2(0.5, 0.5), Position = O(108, 150), Size = O(620, 620), ZIndex = 6 }, face)
		G.new("Frame", { Name = "Band", BackgroundColor3 = WHITE, BackgroundTransparency = 0.74, AnchorPoint = V2(0.5, 0.5), Position = S(0.72, 0.5), Size = O(60, 600), Rotation = 30, BorderSizePixel = 0, ZIndex = 6 }, face)
		local ht = G.new("ImageLabel", { Name = "Halftone", BackgroundTransparency = 1, Image = G.A.Dots, ScaleType = Enum.ScaleType.Tile, TileSize = O(11, 11), ImageTransparency = 0.5, AnchorPoint = V2(1, 0), Position = S(1, 0), Size = O(300, 200), ZIndex = 6 }, face)
		G.new("UIGradient", { Rotation = 225, Transparency = NS({ NK(0, 0), NK(0.7, 1), NK(1, 1) }) }, ht)
		local inner = G.new("Frame", { Name = "Inner", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 9 }, face)
		G.corner(inner, 24)
		G.stroke(inner, 3, WHITE, 0.25)
		local outer = G.new("Frame", { Name = "Outer", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 9 }, b)
		G.corner(outer, 24)
		local ost = G.stroke(outer, 4, INK)
		local art = self:_crate(face, crate, O(-0.75, 67), 0.5, 7)
		local tag = G.new("Frame", { Name = "Tag", BackgroundColor3 = INK, BackgroundTransparency = 0.22, Position = O(18, 18), Size = O(0, 28), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 10 }, face)
		G.corner(tag, 9)
		G.stroke(tag, 2, WHITE, 0.1)
		G.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tag)
		G.text(tag, { Text = string.upper(crate.Tag), Size = O(0, 28), Auto = Enum.AutomaticSize.X, TextSize = 13, Stroke = 0, Font = G.F.Bold, ZIndex = 11 })
		G.text(face, { Name = "Name", Text = crate.Name, Position = O(220, 24), Size = O(210, 36), X = Enum.TextXAlignment.Left, TextSize = 30, Stroke = 4.5, ZIndex = 10 })
		local strip = G.new("Frame", { Name = "Strip", BackgroundTransparency = 1, Position = O(220, 80), Size = O(206, 46), ZIndex = 10 }, face)
		G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
		local total = 0
		for t in crate.Odds do
			total += Config.Count(t)
		end
		for k = 1, 3 do
			local key = crate.Top[k]
			local pv = key and Config.Preview(key)
			local w, sid = string.match(key or "", "^(%w+)/(%w+)$")
			local def = w and Skins.Get(w, sid)
			local col = def and Config.TierColor[def.Rarity] or WHITE
			local m = G.new("ImageLabel", { Name = "Mini" .. k, BackgroundColor3 = INK, Size = O(46, 46), Image = pv and pv.Image or "", ImageRectOffset = pv and pv.Offset or V2(0, 0), ImageRectSize = pv and pv.Size or V2(0, 0), ZIndex = 11, LayoutOrder = k }, strip)
			G.corner(m, 11)
			G.new("UIStroke", { Thickness = 3, Color = col }, m)
			G.glow(m, { Color = col, Transparency = 0.55, Size = S(1.6, 1.6), ZIndex = 10 })
		end
		local more = G.new("Frame", { Name = "More", BackgroundColor3 = C(10, 12, 40), BackgroundTransparency = 0.2, Size = O(46, 46), ZIndex = 11, LayoutOrder = 4 }, strip)
		G.corner(more, 11)
		G.stroke(more, 2, WHITE, 0.6)
		G.text(more, { Text = "+" .. math.max(0, total - 3), TextSize = 16, Stroke = 2.4, ZIndex = 12, Color = C(200, 253, 255) })
		local pl = G.text(face, { Name = "Pity", Text = "", Position = O(220, 140), Size = O(206, 20), X = Enum.TextXAlignment.Left, TextSize = 14, Stroke = 3, ZIndex = 10, Font = G.F.Bold })
		local ptrack = G.new("Frame", { Name = "PTrack", BackgroundColor3 = INK, BackgroundTransparency = 0.4, Position = O(220, 164), Size = O(200, 8), ZIndex = 10 }, face)
		G.corner(ptrack, UDim.new(1, 0))
		local pfill = G.new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, Size = S(0, 1), ZIndex = 11 }, ptrack)
		G.corner(pfill, UDim.new(1, 0))
		G.new("UIGradient", grad({ C(224, 86, 15), C(255, 176, 46), C(255, 243, 196) }), pfill)
		local price = G.new("Frame", { Name = "Price", BackgroundColor3 = WHITE, AnchorPoint = V2(1, 1), Position = UDim2.new(1, -16, 1, -18), Size = O(176, 54), ZIndex = 10 }, face)
		G.corner(price, UDim.new(1, 0))
		G.stroke(price, 4, INK)
		G.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, C(58, 76, 192)), CK(0.55, C(27, 36, 120)), CK(1, C(14, 20, 80)) }) }, price)
		G.new("ImageLabel", { Name = "Req", BackgroundTransparency = 1, Image = G.A.Icon.Req, Position = O(-8, -5), Size = O(64, 64), ZIndex = 12 }, price)
		G.text(price, { Text = G.abbrev(crate.Price), Position = O(58, 0), Size = UDim2.new(1, -66, 1, 0), X = Enum.TextXAlignment.Left, TextSize = 30, Stroke = 4, ZIndex = 12 })
		local pclip = G.new("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Size = S(1, 1), ZIndex = 11 }, price)
		G.shine(pclip, i * 0.4, 3.6, 0.3)
		local sel = G.new("Frame", { Name = "Sel", BackgroundTransparency = 1, Position = O(-9, -9), Size = UDim2.new(1, 18, 1, 18), ZIndex = 12, Visible = false }, b)
		G.corner(sel, 31)
		local sst = G.new("UIStroke", { Thickness = 3, Color = WHITE }, sel)
		local sg = G.new("UIGradient", { Enabled = false }, sst)
		local dim = G.new("Frame", { Name = "Dim", BackgroundColor3 = INK, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 30 }, b)
		G.corner(dim, 24)
		local rb = nil
		if crate.Rainbow then
			ost.Color = WHITE
			ost.Thickness = 5
			rb = G.new("UIGradient", { Color = RAINBOW }, ost)
		end
		local rec = { Btn = b, Crate = crate, Sel = sel, SelGrad = sg, Rays = rays, Art = art, Glow = glow, PityText = pl, PityFill = pfill, Rainbow = rb, Ph = i * 0.9, Dim = dim }
		rec.Ctl = UX.bind(b, "card", { Pitch = 0.92 + i * 0.05, OnClick = function()
			self:_select(i, true)
		end, OnHover = function(on, selected)
			UX.tween(glow, 0.14, { ImageTransparency = if selected then 0.5 elseif on then 0.7 else 0.9 })
			if selected or on then
				UX.tween(dim, 0.12, { BackgroundTransparency = 1 })
			else
				UX.tween(dim, 0.16, { BackgroundTransparency = 0.42 })
			end
		end })
		table.insert(self.Cards, rec)
	end
end

-- ─── state ──────────────────────────────────────────────────────────────────────────────
function CratesScreen:_pityOf(crate)
	return tonumber(player:GetAttribute("CratePity_" .. crate.Id)) or 0
end

function CratesScreen:_select(i, animate)
	local G = self.G
	self.Sel = i
	local crate = Config.Crates[i]
	self.Crate = crate
	for k, c in self.Cards do
		c.Sel.Visible = k == i
		if c.Ctl then
			c.Ctl:SetSelected(k == i)
		end
		local n = self:_pityOf(c.Crate)
		c.PityText.Text = string.format("%s+ in %d opens", c.Crate.PityTier, math.max(1, c.Crate.Pity - n))
		c.PityFill.Size = S(math.clamp(n / c.Crate.Pity, 0.02, 1), 1)
	end
	self.BannerImages = {}
	for _, k in crate.Banner do
		table.insert(self.BannerImages, Config.Images.Banner[k])
	end
	self.BgA.Image = self.BannerImages[1]
	self.BgB.Image = self.BannerImages[2] or self.BannerImages[1]
	self.BgB.ImageTransparency = 1
	self.HueIdx, self.HueT = 1, os.clock()
	self.BannerAura.ImageColor3 = crate.Color
	self.RimGrad.Color = if crate.Rainbow then RAINBOW else CS({ CK(0, crate.Light), CK(0.4, crate.Color), CK(1, crate.Dark) })
	self.PodStroke.Color = crate.Color
	self.PodGlow.ImageColor3 = crate.Color
	for _, r in self.Rings do
		r.St.Color = crate.Light
	end
	self.Title.Text = crate.Name
	local total = 0
	for t in crate.Odds do
		total += Config.Count(t)
	end
	self.Sub.Text = string.format("%s · %d skins", crate.Tag, total)
	if self.BannerCrate then
		self.BannerCrate.Root:Destroy()
	end
	self.BannerCrate = self:_crate(self.CrateHolder, crate, O(250 + ART_DX, 236 + ART_DY), 1, 9)
	for k, g in self.Guns do
		local key = crate.Top[k]
		local w, sid = string.match(key or "", "^(%w+)/(%w+)$")
		local art = (key and Config.Gun(key)) or (w and CardArt.get(w, sid))
		local def = w and Skins.Get(w, sid)
		g.Img.Image = art and art.Image or ""
		g.Img.ImageRectOffset = art and art.Offset or V2(0, 0)
		g.Img.ImageRectSize = art and art.Size or V2(0, 0)
		g.Flash.Image, g.Flash.ImageRectOffset, g.Flash.ImageRectSize = g.Img.Image, g.Img.ImageRectOffset, g.Img.ImageRectSize
		g.Glow.ImageColor3 = def and Config.TierColor[def.Rarity] or WHITE
		g.ChipHolder:ClearAllChildren()
		if def then
			local chip = self:_chip(g.ChipHolder, def.Rarity, O(0, 0), 28)
			chip.AnchorPoint = V2(1, 0)
		end
		if animate then
			g.T0 = os.clock() + (k - 1) * 0.14
		end
	end
	for _, ch in self.OddsList:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	local maxP, rows = 0, 0
	for _, t in Config.Tiers do
		maxP = math.max(maxP, crate.Odds[t] or 0)
	end
	for idx, t in Config.Tiers do
		local p = crate.Odds[t]
		if p then
			rows += 1
			local row = G.new("Frame", { Name = t, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = idx, ZIndex = 6 }, self.OddsList)
			local chip = self:_chip(row, t, O(0, 5), 30)
			chip.AutomaticSize = Enum.AutomaticSize.None
			chip.Size = O(150, 30)
			local col = Config.TierColor[t]
			local tr = G.new("Frame", { Name = "Track", BackgroundColor3 = INK, BackgroundTransparency = 0.45, Position = O(166, 13), Size = O(220, 14), ZIndex = 7 }, row)
			G.corner(tr, UDim.new(1, 0))
			local fill = G.new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, Size = S(0, 1), ZIndex = 8 }, tr)
			G.corner(fill, UDim.new(1, 0))
			local fg = G.new("UIGradient", { Color = CS(col, col:Lerp(WHITE, 0.55)) }, fill)
			if t == "Godly" or t == "Exclusive" then
				fg.Color = chromaOf(t)
			end
			G.tween(fill, 0.8, { Size = S(math.max(0.03, math.sqrt(p / maxP)), 1) }, Enum.EasingStyle.Quint)
			G.text(row, { Text = string.format("%g", p) .. "%", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 0, 0, -2), Size = O(110, 30), X = Enum.TextXAlignment.Right, TextSize = 26, Stroke = 3.5, ZIndex = 8 })
			G.text(row, { Text = Config.Count(t) .. " SKINS", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 0, 0, 25), Size = O(110, 14), X = Enum.TextXAlignment.Right, TextSize = 12, Stroke = 0, Color = G.C.Muted, ZIndex = 8, Font = G.F.Bold })
		end
	end
	local n = self:_pityOf(crate)
	self.PityLabel.Text = string.format("<b>%s+ guaranteed</b>  <font color=\"#ffe3a8\">within %d opens</font>", crate.PityTier, crate.Pity)
	self.PityLeft.Text = string.format("%d to go", math.max(1, crate.Pity - n))
	G.tween(self.PityFill, 0.6, { Size = S(math.clamp(n / crate.Pity, 0.02, 1), 1) }, Enum.EasingStyle.Quint)
	self.PityBox.Position = O(26, 100 + 44 * rows + 8)
	local p5 = Config.Price(crate, 5)
	self.Price5.Text = G.abbrev(p5)
	self.Saves.Text = "×5 saves " .. G.abbrev(crate.Price * 5 - p5) .. " REQ"
	self.OpenPrice.Text = G.abbrev(crate.Price)
	self.HeadGrad.Color = grad(crate.Grad).Color
	self.HeadGrad2.Color = self.HeadGrad.Color

end

function CratesScreen:_open(count)
	count = if count == 5 then 5 else 1
	local crate = self.Crate
	if not crate or (self.Opts.Opening and self.Opts.Opening.Active) then
		return
	end
	local bal = tonumber(player:GetAttribute("REQ")) or 0
	if bal < Config.Price(crate, count) then
		UX.sound("Deny")
		local c = if count == 5 then self.Open5Ctl else self.OpenCtl
		if c then
			c:Shake()
		end
		self.Toast(string.format("Not enough REQ: %s needed", self.G.abbrev(Config.Price(crate, count))))
		return
	end
	if self.Opts.Opening then
		-- the opening is a 3D stage; this screen's UI would sit on top of it
		if self.Pending then
			return
		end
		self.Pending = true
		UX.sound("Purchase")
		local c = if count == 5 then self.Open5Ctl else self.OpenCtl
		if c then
			c:Pulse()
		end
		task.wait(0.16)
		self.Pending = false
		if not self.Shown then
			return
		end
		self.Gui.Enabled = false
		self.Opts.Opening:Play(crate, { Fast = self.Fast, Count = count, OnDone = function()
			if self.Shown then
				self.Gui.Enabled = true
				self:_select(self.Sel, false)
			end
		end })
	end
end

-- ─── per frame ──────────────────────────────────────────────────────────────────────────
function CratesScreen:_step(dt)
	local t = os.clock()
	self.Blob1.Position = S(0.08 + math.sin(t * 0.21) * 0.06, 0.02 + math.cos(t * 0.17) * 0.05)
	self.Blob2.Position = S(0.92 + math.cos(t * 0.15) * 0.06, 1.02 + math.sin(t * 0.19) * 0.05)
	local sp = (t % 14) / 14
	self.Sweep.Position = S(-0.3 + math.max(0, sp - 0.7) / 0.3 * 1.6, 0.5)
	for _, s in self.Twinkles do
		s.F.BackgroundTransparency = 0.2 + 0.8 * (0.5 + 0.5 * math.sin(t * s.Sp * 2 + s.Ph))
	end
	local z = 1.1 + 0.05 * math.sin(t * 0.13)
	self.BgA.Size, self.BgB.Size = S(z, z), S(z, z)
	local pan = S(0.5 + 0.012 * math.sin(t * 0.11), 0.5 + 0.01 * math.cos(t * 0.09))
	self.BgA.Position, self.BgB.Position = pan, pan
	if self.BannerImages and #self.BannerImages > 1 then
		local k = (t - self.HueT) / 1.6
		if k >= 1 then
			self.HueT = t
			self.HueIdx = self.HueIdx % #self.BannerImages + 1
			self.BgA.Image = self.BannerImages[self.HueIdx]
			self.BgB.Image = self.BannerImages[self.HueIdx % #self.BannerImages + 1]
			k = 0
		end
		self.BgB.ImageTransparency = 1 - k
	end
	for _, s in self.Streaks do
		local ph = ((t + s.Ph) % s.T) / s.T
		s.F.Position = O(s.X + ph * 620, s.Y - ph * 485)
		s.F.BackgroundTransparency = if ph < 0.12 then 1 - ph / 0.12 elseif ph > 0.7 then (ph - 0.7) / 0.3 else 0
	end
	self.Rays.Rotation = (t * 7) % 360
	for _, r in self.Rings do
		r.F.Rotation = (t * r.Speed) % 360
	end
	self.RimGrad.Rotation = (t * 40) % 360
	if self.BannerCrate then
		self:_animCrate(self.BannerCrate, t, 236 + ART_DY, 250 + ART_DX)
	end
	for k, g in self.Guns do
		local e = math.clamp((t - g.T0) / 0.55, 0, 1)
		local ease = 1 - (1 - e) ^ 4
		local bob = math.sin(t * 2 + g.Ph) * 16
		g.Holder.Position = g.Home + O((1 - ease) * 620, bob - 4)
		g.Holder.Rotation = GUNS[k][5] + (1 - ease) * 30 + math.sin(t * 1.3 + g.Ph) * 1.5
		g.Img.ImageTransparency = 1 - ease
		local surge = ((t + g.Ph) % 4.2) / 4.2
		local s = if surge > 0.7 and surge < 0.82 then math.sin((surge - 0.7) / 0.12 * math.pi) else 0
		g.Glow.ImageTransparency = 0.8 - s * 0.4
		g.Glow.Size = S(0.9 + s * 0.2, 0.8 + s * 0.3)
		g.Flash.ImageTransparency = if e < 1 then 0.2 + 0.8 * e else 1 - s * 0.5
	end
	for _, c in self.Cards do
		c.Rays.Rotation = (t * 12 + c.Ph * 40) % 360
		self:_animCrate(c.Art, t + c.Ph)
		if c.Rainbow then
			c.Rainbow.Rotation = (t * 30) % 360
		end
	end
	for g in self.Chroma do
		if g.Parent then
			g.Offset = V2(math.sin(t * 0.8) * 0.5, 0)
		else
			self.Chroma[g] = nil
		end
	end
	if K.stepNeon then
		K.stepNeon(t)
	end
end

-- idle loop shared by every crate: lid lifts and peeks, light leaks out, the coin flips
function CratesScreen:_animCrate(c, t, top, left)
	local cyc = (t % 3.6) / 3.6
	local lift = 0
	if cyc > 0.52 and cyc < 0.9 then
		local k = (cyc - 0.52) / 0.38
		lift = math.sin(k * math.pi) * (1 - 0.35 * math.sin(k * math.pi * 3))
	end
	local sc = c.Scale
	c.Lid.Position = O(0, -lift * 22 * sc)
	c.Lid.Rotation = lift * -3
	c.Leak.ImageTransparency = 1 - lift * 0.85
	local turn = (t % 4.8) / 4.8
	local f = if turn > 0.4 and turn < 0.7 then math.abs(math.cos((turn - 0.4) / 0.3 * math.pi)) else 1
	c.Coin.Size = S(0.24 * f, 0.35)
	if top then
		c.Root.Position = O(left, top + math.sin(t * 1.36) * 7)
		c.Root.Rotation = math.sin(t * 1.36 + 1) * 1.2
	end
end

-- ─── screen protocol ────────────────────────────────────────────────────────────────────
function CratesScreen:Show()
	if self.Shown then
		return
	end
	self.Shown = true
	self.Gui.Enabled = true
	self:_select(self.Sel, true)
	self.Conn = RunService.RenderStepped:Connect(function(dt)
		if self.Opts.IsActive and not self.Opts.IsActive() then
			return
		end
		self:_step(dt)
	end)
end

function CratesScreen:Hide()
	if not self.Shown then
		return
	end
	self.Shown = false
	if self.Opts.Opening and self.Opts.Opening.Active then
		self.Opts.Opening:Close()
	end
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	self.Gui.Enabled = false
end

function CratesScreen:HandleKey(kc)
	if self.Opts.Opening and self.Opts.Opening.Active then
		return self.Opts.Opening:HandleKey(kc)
	end
	if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Backspace then
		self.Opts.OnBack()
		return true
	elseif kc == Enum.KeyCode.Return or kc == Enum.KeyCode.ButtonA then
		task.spawn(self._open, self, 1)
		return true
	end
	return false
end

return CratesScreen
