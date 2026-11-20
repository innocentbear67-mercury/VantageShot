--!nocheck
--[[
	InventoryHS - VantageShot Inventory modal, v2 (2026-11-17). Follows Hypershot's inventory construction:
	  left panel   COLLECTION WORTH (REQ value of owned skins + REQ), best pull in 3D, ITEM INDEX, Skins Collected x / N + bar
	  main panel   title breaking the top border, red X; crate strip (owned crates xN) + GET MORE; owned skin cards;
	               "Many more to get!" scrolling row of skins not owned yet
	  bottom bar   search, weapon filter dropdown, Rarity sort, equipped-only toggle (no scrapping - user decision)
	  hover        tooltip card (name, rarity, weapon, worth, status); click: menu > Inspect / Equip / Unequip / Get Crates
	  Inspect      3D skin overlay, drag to rotate, EQUIP / BACK
	Own skin: violet neon panels, gold worth, REQ instead of cash.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local Skins = require(Vantage:WaitForChild("Weapons"):WaitForChild("Skins"))
local K = require(script.Parent:WaitForChild("ScreenKit"))
local EquipCatalog = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local EquipStatsUI = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentStatsUI"))
-- weapon crates then equipment crates
local ALL_CRATES = table.clone(Config.Crates)
for _, c in Config.EquipmentCrates or {} do
	table.insert(ALL_CRATES, c)
end
local TILE_W = if #ALL_CRATES > 4 then 132 else 185
local TILE_P = TILE_W + 12

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

local RAYS = "rbxassetid://113538852110620"
local BLOOM = "rbxassetid://103142630740394"
local GLOW = "rbxassetid://104786452938879"
local STAR = "rbxassetid://107113949398119"

local C = {
	Panel = RGB(22, 9, 42), Dots = RGB(12, 4, 26), Inner = RGB(8, 3, 17), InnerRim = RGB(58, 42, 92), Neon = RGB(170, 100, 255),
	Ink = RGB(12, 6, 24), Muted = RGB(206, 192, 232), Gold = RGB(255, 206, 84), Field = RGB(236, 232, 248), FieldInk = RGB(40, 34, 56),
	Green = RGB(117, 251, 134),
}
local PAL = {
	Green = { Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Ink = RGB(25, 45, 12) },
	Gold = { Rim = RGB(120, 70, 10), Top0 = RGB(255, 226, 120), Top1 = RGB(255, 160, 40), Ink = RGB(70, 36, 4) },
	Grey = { Rim = RGB(46, 44, 58), Top0 = RGB(160, 156, 176), Top1 = RGB(116, 112, 132), Ink = RGB(30, 28, 40) },
	Red = { Rim = RGB(110, 18, 22), Top0 = RGB(255, 100, 96), Top1 = RGB(212, 38, 46), Ink = RGB(60, 8, 12) },
}
local HOLO = CS({ CK(0, RGB(255, 90, 200)), CK(0.5, RGB(150, 90, 255)), CK(1, RGB(70, 220, 255)) })

-- geometry measured from the Hypershot capture (ref px x 0.7), composition origin at ref (60, 30)
local SC = 0.7
local CW, CH = 1432, 1034
local function R(x, y, ox, oy) return O((x - (ox or 60)) * SC, (y - (oy or 30)) * SC) end
local function Z(w, h) return O(w * SC, h * SC) end
local CARD, PITCH, GX0, GY0, COLS = 172, 190, 25, 22, 4
local TCARD, TPITCH = 105, 134

local function tierColor(r) return Config.TierColor[r] or WHITE end
local function tierIndex(r) return Config.TierIndex[r] or 1 end
-- animated rims / text: Godly rainbow, Exclusive holo, Legendary gold metal, Mythic platinum metal (ScreenKit.CHROMAS)
local function chromaSeq(r)
	local d = K.CHROMAS and K.CHROMAS[r]
	if d and d.Grad then return d.Grad end
	if r == "Exclusive" then return HOLO end
	return nil
end
local function hsv(c, s, v)
	local h, s0 = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(s0 * s, 0, 1), v)
end
local FACE = {
	Legendary = CS({ CK(0, RGB(255, 222, 110)), CK(0.45, RGB(196, 128, 18)), CK(1, RGB(60, 34, 6)) }),
	Mythic = CS({ CK(0, RGB(232, 240, 255)), CK(0.45, RGB(128, 142, 172)), CK(1, RGB(28, 34, 50)) }),
}
local FACEBASE = { Godly = RGB(110, 50, 230), Exclusive = RGB(230, 60, 190) }
local function faceSeq(r)
	if FACE[r] then return FACE[r] end
	local col = FACEBASE[r] or tierColor(r)
	return CS({ CK(0, hsv(col, 1.05, 0.86)), CK(0.45, hsv(col, 1.1, 0.52)), CK(1, hsv(col, 1.15, 0.2)) })
end
local function splitName(n)
	local a, b = n:match("^(.-)%s*//%s*(.+)$")
	return a or n, b
end
local function num(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function ownedSet()
	local s = player:GetAttribute("OwnedSkins")
	local set = {}
	if type(s) == "string" then
		for k in s:gmatch("[^,]+") do set[k] = true end
	end
	return set
end
local function crateCount(id)
	local n = player:GetAttribute("CrateOwned_" .. id)
	if type(n) == "number" then return n end
	local js = player:GetAttribute("OwnedCrates")
	if type(js) == "string" then
		local ok, t = pcall(HttpService.JSONDecode, HttpService, js)
		if ok and type(t) == "table" and type(t[id]) == "number" then return t[id] end
	end
	return 0
end

local Inv = {}
Inv.__index = Inv

function Inv.new(layer, env)
	local self = setmetatable({
		Env = env, HS = env.HS, Query = "", Weapon = "All", Desc = true, EquippedOnly = false, Index = false,
		Rims = {}, Stars = {}, Winks = {}, Spins = {}, CrateLbl = {}, Marq = nil,
	}, Inv)
	self:_build(layer)
	RunService.RenderStepped:Connect(function(dt)
		if self.Root.Visible then self:_step(dt) end
	end)
	player.AttributeChanged:Connect(function(a)
		if a == "OwnedSkins" or a == "OwnedWeapons" or a == "OwnedEquipment" or a:sub(1, 6) == "Equip_" or a:sub(1, 5) == "Skin_" or a == "REQ" or a == "OwnedCrates" or a == "EquipShards" or a:sub(1, 11) == "CrateOwned_" then
			if self.Root.Visible then self:_refresh() end
		end
	end)
	-- drag to rotate (inspect)
	local function isPress(io)
		return io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
	end
	self.InsVP.InputBegan:Connect(function(io)
		local sp = self.Spins.Inspect
		if sp and isPress(io) then sp.Drag, sp.X, sp.T, sp.V = true, io.Position.X, os.clock(), 0 end
	end)
	UserInputService.InputChanged:Connect(function(io)
		local sp = self.Spins.Inspect
		if not (sp and sp.Drag) then return end
		if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
			local dx, now = io.Position.X - sp.X, os.clock()
			sp.Yaw += dx * 0.013
			sp.V = math.clamp(dx * 0.013 / math.max(now - sp.T, 1 / 120), -14, 14)
			sp.X, sp.T = io.Position.X, now
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		local sp = self.Spins.Inspect
		if sp and isPress(io) then sp.Drag = false end
	end)
	return self
end

------------------------------------------------------------------ kit
function Inv:_text(parent, p)
	p.Stroke = p.Stroke or 2.6
	p.StrokeColor = p.StrokeColor or C.Ink
	p.ZIndex = p.ZIndex or 27
	return self.HS.text(parent, p)
end

function Inv:_pill(parent, p)
	local HS, z = self.HS, p.Z or 27
	local b = HS.new("TextButton", { Name = p.Name or "Pill", Text = "", AutoButtonColor = false, BackgroundColor3 = p.Pal.Rim, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	HS.corner(b, p.R or 10)
	local face = HS.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(3.4, 1.6), Size = UDim2.new(1, -6.8, 1, -7), ZIndex = z }, b)
	HS.corner(face, (p.R or 10) - 2)
	local grad = HS.new("UIGradient", { Rotation = 90, Color = CS(p.Pal.Top0, p.Pal.Top1) }, face)
	HS.new("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, BorderSizePixel = 0, Position = O(5, 2), Size = UDim2.new(1, -10, 0.42, 0), ZIndex = z }, face)
	-- two diagonal streaks on the right
	for i = 0, 1 do
		HS.new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.72, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -30 - i * 16, 0.5, 0), Size = UDim2.new(0, 6, 1.4, 0), Rotation = 24, ZIndex = z }, face)
	end
	face.ClipsDescendants = true
	local t = self:_text(b, { Name = "Label", Text = p.Text, TextSize = p.TextSize or 30, Stroke = 2.8, StrokeColor = p.Pal.Ink, Position = O(0, -2), Size = S(1, 1), ZIndex = z + 1 })
	HS.press(b, p.OnClick, { Hover = 1.06, Press = 0.94, Sound = p.Sound })
	return { B = b, T = t, G = grad }
end

local function restyle(pill, pal, text)
	pill.B.BackgroundColor3 = pal.Rim
	pill.G.Color = CS(pal.Top0, pal.Top1)
	local st = pill.T:FindFirstChildOfClass("UIStroke")
	if st then st.Color = pal.Ink end
	if text then pill.T.Text = text end
end

-- neon panel: soft glow, violet body with a faint diagonal dot field, thick neon rim
function Inv:_panel(parent, name, pos, size)
	local HS = self.HS
	local new = HS.new
	local w, h = size.X.Offset, size.Y.Offset
	new("ImageLabel", { Name = name .. "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = C.Neon, ImageTransparency = 0.25, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.9, Position = O(pos.X.Offset - 64, pos.Y.Offset - 64), Size = O(w + 128, h + 128), ZIndex = 20 }, parent)
	local p = new("Frame", { Name = name, BackgroundColor3 = C.Panel, Position = pos, Size = size, ZIndex = 20 }, parent)
	HS.corner(p, 26)
	local outer = HS.stroke(p, 9, RGB(30, 8, 60))
	outer.Name = "Outer"
	local inner = new("Frame", { Name = "Rim", BackgroundTransparency = 1, Position = O(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 21 }, p)
	HS.corner(inner, 24)
	local st = HS.stroke(inner, 6, WHITE)
	local g = new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(222, 168, 255)), CK(0.5, RGB(150, 72, 255)), CK(1, RGB(222, 168, 255)) }) }, st)
	table.insert(self.Rims, { G = g, Spd = 18, P = math.random() * 360 })
	local dots = new("Frame", { Name = "Dots", BackgroundColor3 = C.Dots, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 20 }, p)
	HS.corner(dots, 26)
	local kp = {}
	for k = 0, 18 do table.insert(kp, NK(k / 18, if k % 2 == 0 then 1 else 0.55)) end
	new("UIGradient", { Rotation = 35, Transparency = NS(kp) }, dots)
	return p
end

function Inv:_inset(parent, name, pos, size)
	local HS = self.HS
	local f = HS.new("Frame", { Name = name, BackgroundColor3 = C.Inner, Position = pos, Size = size, ZIndex = 22 }, parent)
	HS.corner(f, 20)
	HS.stroke(f, 5, C.InnerRim)
	return f
end

------------------------------------------------------------------ build
function Inv:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "InventoryHS", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(CW, CH), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit

	------------------------------------------------ left: worth + collection
	local lp = self:_panel(fit, "Worth", R(60, 85), Z(610, 1240))
	local function L(x, y) return R(x, y, 60, 85) end
	for _, x in { 112, 618 } do
		new("ImageLabel", { BackgroundTransparency = 1, Image = HS.Img.Req, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = L(x, 190), Size = Z(64, 64), ZIndex = 26 }, lp)
	end
	local hdr = self:_text(lp, { Name = "Header", Text = "COLLECTION WORTH", TextSize = 38, Stroke = 4, Color = WHITE, AnchorPoint = V2(0.5, 0.5), Position = L(365, 190), Size = Z(440, 70) })
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 240, 160), RGB(255, 170, 40)) }, hdr)
	self.WorthText = self:_text(lp, { Name = "Worth", Text = "0", TextSize = 62, Stroke = 5, AnchorPoint = V2(0.5, 0.5), Position = L(365, 287), Size = Z(540, 100) })
	self:_text(lp, { Text = "REQ value of your skins", TextSize = 23, Stroke = 2.4, Color = C.Muted, AnchorPoint = V2(0.5, 0.5), Position = L(365, 378), Size = Z(540, 40) })
	self:_text(lp, { Text = "+ your REQ balance.", TextSize = 23, Stroke = 2.4, Color = C.Muted, AnchorPoint = V2(0.5, 0.5), Position = L(365, 418), Size = Z(540, 40) })
	-- best pull showcase
	local show = new("Frame", { Name = "Showcase", BackgroundTransparency = 1, ClipsDescendants = true, Position = L(90, 470), Size = Z(550, 420), ZIndex = 22 }, lp)
	self.ShowRays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageTransparency = 0.8, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(520, 520), ZIndex = 22 }, show)
	self.ShowBloom = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(360, 240), ZIndex = 22 }, show)
	self.ShowVP = new("ViewportFrame", { Name = "View", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 23 }, show)
	self.ShowName = self:_text(lp, { Name = "ShowName", Text = "", TextSize = 22, Stroke = 2.4, AnchorPoint = V2(0.5, 0.5), Position = L(365, 905), Size = Z(540, 36) })
	self.IndexBtn = self:_pill(lp, { Name = "ItemIndex", Text = "ITEM INDEX", TextSize = 30, Pal = PAL.Gold, AnchorPoint = V2(0.5, 0), Position = L(365, 945), Size = Z(320, 82), Sound = "Tab", OnClick = function()
		self.Index = not self.Index
		self:_refresh(true)
	end })
	self:_text(lp, { Text = "Items Collected", TextSize = 33, Stroke = 3.4, AnchorPoint = V2(0.5, 0.5), Position = L(365, 1100), Size = Z(540, 60) })
	self.CountText = self:_text(lp, { Name = "Count", Text = "0 / 0", TextSize = 52, Stroke = 5, Color = C.Gold, AnchorPoint = V2(0.5, 0.5), Position = L(365, 1168), Size = Z(540, 84) })
	local bar = new("Frame", { Name = "Bar", BackgroundColor3 = RGB(26, 30, 62), Position = L(122, 1220), Size = Z(486, 34), ZIndex = 24 }, lp)
	HS.corner(bar, UDim.new(0.5, 0))
	HS.stroke(bar, 3, BLACK)
	self.Fill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(0, 1), ZIndex = 25 }, bar)
	HS.corner(self.Fill, UDim.new(0.5, 0))
	new("UIGradient", { Color = CS(RGB(255, 226, 120), RGB(255, 160, 40)) }, self.Fill)

	------------------------------------------------ main panel
	local mp = self:_panel(fit, "Main", R(815, 85), Z(1250, 1245))
	self.Main = mp
	local function M(x, y) return R(x, y, 815, 85) end
	new("Frame", { Name = "TitleGap", BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = O(20, -12), Size = O(366, 24), ZIndex = 22 }, mp)
	self.Title = self:_text(mp, { Name = "Title", Text = "INVENTORY", TextSize = 70, Stroke = 5.5, X = Enum.TextXAlignment.Left, Fit = false, Position = O(24, -50), Size = O(420, 86), ZIndex = 26 })
	local x = new("TextButton", { Name = "Close", Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(110, 18, 22), AnchorPoint = V2(0.5, 0.5), Position = M(2050, 90), Size = Z(110, 110), ZIndex = 27 }, mp)
	HS.corner(x, 12)
	HS.stroke(x, 3.5, RGB(40, 6, 10))
	local xf = new("Frame", { Name = "Face", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(4, 3), Size = UDim2.new(1, -8, 1, -10), ZIndex = 27 }, x)
	HS.corner(xf, 9)
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 100, 120), RGB(212, 38, 70)) }, xf)
	HS.text(x, { Text = "X", TextSize = 50, Stroke = 3.5, StrokeColor = RGB(60, 8, 12), Position = O(0, -3), Size = S(1, 1), ZIndex = 28 })
	HS.press(x, function()
		if self.Env.Close then self.Env.Close() end
	end, { Hover = 1.08, Press = 0.92, Sound = "Click" })

	-- crate strip
	local cb = self:_inset(mp, "Crates", M(855, 175), Z(1170, 260))
	for i, cr in ALL_CRATES do
		local t = new("TextButton", { Name = cr.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(14, 7, 28), Position = R(885 + (i - 1) * TILE_P, 193, 855, 175), Size = Z(TILE_W, 205), ZIndex = 24 }, cb)
		HS.corner(t, 14)
		local st = HS.stroke(t, 4, (cr.Light or WHITE):Lerp(cr.Color, 0.35))
		if cr.Rainbow then new("UIGradient", { Color = K.CHROMA }, st) end
		new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = cr.Color, ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.52), Size = S(1, 0.9), ZIndex = 24 }, t)
		self:_text(t, { Text = ((cr.Name or cr.Id):gsub(" Crate", ""):gsub("Equipment", "Equip")), TextSize = 21, Stroke = 2.4, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.new(1, -10, 0, 26), ZIndex = 26 })
		new("ImageLabel", { BackgroundTransparency = 1, Image = cr.Art.Full, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.52), Size = S(0.84, 0.5), ZIndex = 25 }, t)
		self.CrateLbl[cr.Id] = self:_text(t, { Text = "x0", TextSize = 24, Stroke = 2.6, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -10, 0, 28), ZIndex = 26 })
		HS.press(t, function()
			if self.Env.Open then self.Env.Open("Cases") end
		end, { Hover = 1.06, Press = 0.94, Sound = "Click" })
	end
	self:_pill(cb, { Name = "GetMore", Text = "GET MORE", TextSize = 28, Pal = PAL.Green, Position = R(1765, 275, 855, 175), Size = Z(235, 62), OnClick = function()
		if self.Env.Open then self.Env.Open("Shop") end
	end })

	-- card area
	local gb = self:_inset(mp, "Cards", M(855, 485), Z(1170, 800))
	local sc = new("ScrollingFrame", { Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Position = O(8, 8), Size = UDim2.new(1, -16, 1, -16), CanvasSize = O(0, 0), ScrollBarThickness = 8, ScrollBarImageColor3 = C.Neon, ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.Never, ZIndex = 23 }, gb)
	self.Scroll = sc
	self.BoxH = 800 * SC - 16

	------------------------------------------------ bottom bar
	local bb = new("Frame", { Name = "BottomBar", BackgroundColor3 = RGB(16, 10, 28), Position = R(970, 1380), Size = Z(945, 120), ZIndex = 22 }, fit)
	HS.corner(bb, 18)
	HS.stroke(bb, 5, BLACK)
	local function B(x, y) return R(x, y, 970, 1380) end
	local function field(name, pos, size, col)
		local f = new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = col or C.Field, Position = pos, Size = size, ZIndex = 24 }, bb)
		HS.corner(f, 6)
		local lip = new("Frame", { Name = "Lip", BackgroundColor3 = BLACK, BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = UDim2.new(1, 0, 0, 6), ZIndex = 24 }, f)
		HS.corner(lip, 6)
		return f
	end
	local sf = field("Search", B(1005, 1395), Z(470, 85))
	local tb = new("TextBox", { Name = "Box", BackgroundTransparency = 1, ClearTextOnFocus = false, PlaceholderText = "Search... (name or gun)", PlaceholderColor3 = RGB(130, 122, 150), Text = "", FontFace = HS.Font, TextSize = 25, TextColor3 = C.FieldInk, TextXAlignment = Enum.TextXAlignment.Left, Position = O(14, 0), Size = UDim2.new(1, -24, 1, -4), ZIndex = 25 }, sf)
	self.Search = tb
	tb:GetPropertyChangedSignal("Text"):Connect(function()
		self.Query = tb.Text:lower()
		self:_refresh(true)
	end)
	local chev = field("Weapon", B(1490, 1395), Z(90, 85))
	for side = -1, 1, 2 do
		new("Frame", { BackgroundColor3 = C.FieldInk, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, side * 8, 0.45, 0), Size = O(24, 7), Rotation = -side * 40, ZIndex = 25 }, chev)
	end
	HS.press(chev, function()
		self.Drop.Visible = not self.Drop.Visible
	end, { Hover = 1.06, Press = 0.94, Sound = "Click" })
	local rar = field("Rarity", B(1592, 1395), Z(180, 85))
	self.RarityText = self:_text(rar, { Text = "Rarity", TextSize = 27, Stroke = 0, Color = C.FieldInk, Position = O(0, -2), Size = S(1, 1), ZIndex = 25 })
	HS.press(rar, function()
		self.Desc = not self.Desc
		self:_refresh(true)
	end, { Hover = 1.06, Press = 0.94, Sound = "Toggle" })
	local eq = field("EquippedOnly", B(1787, 1395), Z(90, 85), RGB(60, 140, 255))
	self.EqBtn = eq
	local ck = new("Frame", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.46), Size = O(34, 34), ZIndex = 25 }, eq)
	self.EqMarks = {
		new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = O(10, 21), Size = O(16, 7), Rotation = 45, ZIndex = 25 }, ck),
		new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = O(21, 16), Size = O(28, 7), Rotation = -50, ZIndex = 25 }, ck),
	}
	HS.press(eq, function()
		self.EquippedOnly = not self.EquippedOnly
		self:_refresh(true)
	end, { Hover = 1.06, Press = 0.94, Sound = "Toggle" })

	-- weapon dropdown (opens upward from the chevron)
	local names = { "All" }
	for _, w in Skins.Weapons do table.insert(names, w) end
	table.insert(names, "Equipment")
	local drop = new("Frame", { Name = "Drop", BackgroundColor3 = RGB(14, 12, 18), AnchorPoint = V2(0, 1), Position = UDim2.new(0, chev.Position.X.Offset - 40, 0, -8), Size = O(190, #names * 42 + 12), Visible = false, ZIndex = 44 }, bb)
	HS.corner(drop, 14)
	HS.stroke(drop, 4, RGB(70, 70, 78))
	self.Drop = drop
	self.DropItems = {}
	for i, w in names do
		local it = new("TextButton", { Name = w, Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, BackgroundTransparency = 1, Position = O(6, 6 + (i - 1) * 42), Size = O(178, 40), ZIndex = 45 }, drop)
		HS.corner(it, 8)
		self.DropItems[w] = self:_text(it, { Text = w, TextSize = 24, Stroke = 2.4, X = Enum.TextXAlignment.Left, Position = O(14, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 46 })
		it.MouseEnter:Connect(function() it.BackgroundTransparency = 0.88 end)
		it.MouseLeave:Connect(function() it.BackgroundTransparency = 1 end)
		HS.press(it, function()
			self.Weapon = w
			drop.Visible = false
			self:_refresh(true)
		end, { Hover = 1.02, Press = 0.97, Sound = "Click" })
	end

	self:_buildTip(fit)
	self:_buildMenu(fit)
	self:_buildInspect(fit)
end

------------------------------------------------------------------ tooltip + menu
function Inv:_buildTip(fit)
	local HS = self.HS
	local new = HS.new
	local t = new("Frame", { Name = "Tip", BackgroundColor3 = WHITE, AnchorPoint = V2(0.5, 0), Size = O(280, 236), Visible = false, ZIndex = 40 }, fit)
	HS.corner(t, 18)
	HS.stroke(t, 5, RGB(244, 240, 255))
	new("UIGradient", { Rotation = 25, Color = CS({ CK(0, RGB(222, 214, 255)), CK(0.5, RGB(200, 236, 255)), CK(1, RGB(255, 214, 240)) }) }, t)
	local outer = new("Frame", { BackgroundTransparency = 1, Position = O(-4, -4), Size = UDim2.new(1, 8, 1, 8), ZIndex = 40 }, t)
	HS.corner(outer, 22)
	HS.stroke(outer, 2, RGB(60, 50, 90), 0.4)
	self.TipName = self:_text(t, { Text = "", TextSize = 27, Stroke = 3, StrokeColor = BLACK, AnchorPoint = V2(0.5, 0), Position = O(140, 8), Size = O(260, 34), ZIndex = 41 })
	self.TipRar = self:_text(t, { Text = "", TextSize = 26, Stroke = 2.6, StrokeColor = RGB(30, 20, 40), AnchorPoint = V2(0.5, 0), Position = O(140, 42), Size = O(250, 32), ZIndex = 41 })
	self.TipRarGrad = new("UIGradient", { Enabled = false, Color = K.CHROMA }, self.TipRar)
	local function div(y)
		local d = new("Frame", { BackgroundColor3 = RGB(110, 100, 130), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0), Position = O(140, y), Size = O(220, 3), ZIndex = 41 }, t)
		new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.2), NK(1, 1) }) }, d)
	end
	div(80)
	self.TipGun = self:_text(t, { Text = "", TextSize = 21, Stroke = 2.4, StrokeColor = BLACK, AnchorPoint = V2(0.5, 0), Position = O(140, 88), Size = O(260, 28), ZIndex = 41 })
	self.TipTag = self:_text(t, { Text = "", TextSize = 19, Stroke = 2.2, StrokeColor = BLACK, AnchorPoint = V2(0.5, 0), Position = O(140, 116), Size = O(260, 26), ZIndex = 41 })
	div(148)
	self.TipWorth = self:_text(t, { Text = "", TextSize = 23, Stroke = 2.6, StrokeColor = BLACK, Color = RGB(255, 214, 90), AnchorPoint = V2(0.5, 0), Position = O(140, 156), Size = O(260, 30), ZIndex = 41 })
	self.TipStatus = self:_text(t, { Text = "", TextSize = 21, Stroke = 2.4, StrokeColor = BLACK, AnchorPoint = V2(0.5, 0), Position = O(140, 190), Size = O(260, 30), ZIndex = 41 })
	-- 2026-11-18: equipment shows its stats (vs the starter) and its ability under the status line
	self.TipEquip = EquipStatsUI.new(HS, t, { Position = O(0, 228), Width = 280, ZIndex = 41, Light = true })
	self.TipEquip.Frame.Visible = false
	self.Tip = t
end

function Inv:_local(btn, fy)
	local f = self.FitFrame
	local sc = f.AbsoluteSize.X / CW
	local cx = (btn.AbsolutePosition.X + btn.AbsoluteSize.X / 2 - f.AbsolutePosition.X) / sc
	local y = (btn.AbsolutePosition.Y + btn.AbsoluteSize.Y * fy - f.AbsolutePosition.Y) / sc
	return cx, y
end

function Inv:_tip(e, btn)
	if self.Menu.Visible then return end
	local col = tierColor(e.Rarity)
	local seq = chromaSeq(e.Rarity)
	local short, tag = splitName(e.Name)
	self.TipName.Text = if e.Owned then short else short .. " (locked)"
	self.TipRar.Text = e.Rarity
	self.TipRar.TextColor3 = if seq then WHITE else col
	self.TipRarGrad.Enabled = seq ~= nil
	if seq then self.TipRarGrad.Color = seq end
	self.TipGun.Text = e.Weapon .. " | " .. tostring(Skins.Category[e.Weapon] or "")
	self.TipTag.Text = tag or "Crate drop"
	if e.Kind == "Equipment" then
		self.TipGun.Text = tostring(EquipCatalog.SlotNames[e.Slot] or e.Slot)
		self.TipTag.Text = if e.Ability and e.Ability.Name then "Ability: " .. e.Ability.Name else "Starter kit"
	end
	self.TipWorth.Text = "Worth: " .. num(Config.Refund[e.Rarity] or 0) .. " REQ"
	if e.Equipped then
		self.TipStatus.Text, self.TipStatus.TextColor3 = "Equipped", C.Green
	elseif e.Owned then
		self.TipStatus.Text, self.TipStatus.TextColor3 = "In your inventory", WHITE
	else
		self.TipStatus.Text, self.TipStatus.TextColor3 = if e.Kind == "Equipment" then string.format("Shards %d/%d to unlock", e.Shards or 0, EquipCatalog.Shards or 3) else "Not unlocked yet", RGB(255, 130, 140)
	end
	if e.Kind == "Equipment" then
		self.TipEquip:Set(e.Id)
		self.Tip.Size = O(280, 236 + self.TipEquip.Height)
	else
		self.TipEquip.Frame.Visible = false
		self.Tip.Size = O(280, 236)
	end
	local cx, y = self:_local(btn, 0.72)
	self.Tip.Position = O(math.clamp(cx, 150, CW - 150), math.max(10, math.min(y, CH - self.Tip.Size.Y.Offset - 10)))
	self.Tip.Visible = true
	self.TipFor = btn
end

function Inv:_buildMenu(fit)
	local HS = self.HS
	local new = HS.new
	self.Catch = new("TextButton", { Name = "Catch", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = S(1, 1), Visible = false, ZIndex = 42 }, fit)
	self.Catch.Activated:Connect(function() self:_closeMenu() end)
	local m = new("Frame", { Name = "Menu", BackgroundColor3 = RGB(12, 11, 14), AnchorPoint = V2(0.5, 0), Size = O(250, 60), Visible = false, ZIndex = 43 }, fit)
	HS.corner(m, 18)
	HS.stroke(m, 5, RGB(74, 72, 80))
	local inner = new("Frame", { BackgroundTransparency = 1, Position = O(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 43 }, m)
	HS.corner(inner, 14)
	HS.stroke(inner, 2, RGB(40, 38, 46))
	self.Menu = m
	self.MenuItems = {}
	for i = 1, 4 do
		local b = new("TextButton", { Name = "Item" .. i, Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, BackgroundTransparency = 1, Position = O(10, 10 + (i - 1) * 54), Size = O(230, 50), Visible = false, ZIndex = 44 }, m)
		HS.corner(b, 10)
		local t = self:_text(b, { Text = "", Rich = true, TextSize = 30, Stroke = 3, StrokeColor = BLACK, X = Enum.TextXAlignment.Left, Position = O(12, 0), Size = UDim2.new(1, -16, 1, 0), ZIndex = 45 })
		local rec = { B = b, T = t, Fn = nil, Off = false }
		b.MouseEnter:Connect(function() if not rec.Off then b.BackgroundTransparency = 0.9 end end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
		HS.press(b, function()
			if rec.Off or not rec.Fn then return end
			local fn = rec.Fn
			self:_closeMenu()
			fn()
		end, { Hover = 1.03, Press = 0.96, Sound = "Click" })
		self.MenuItems[i] = rec
	end
end

function Inv:_closeMenu()
	self.Menu.Visible = false
	self.Catch.Visible = false
end

function Inv:_menu(e, btn)
	self.Tip.Visible = false
	self.Drop.Visible = false
	local items = { { "Inspect", function() self:_inspect(e) end } }
	if e.Owned then
		if e.Equipped then
			table.insert(items, { "Equipped", nil, true })
			if not (e.Kind == "Equipment" and EquipCatalog.Default[e.Slot] == e.Id) then
				table.insert(items, { "Unequip", function() self:_equip(e, Skins.Default) end })
			end
		else
			table.insert(items, { "Equip", function() self:_equip(e, e.Skin) end })
		end
	else
		table.insert(items, { "Get Crates", function() if self.Env.Open then self.Env.Open("Shop") end end })
		table.insert(items, { "View Odds", function() if self.Env.Open then self.Env.Open("Cases") end end })
	end
	for i, rec in self.MenuItems do
		local it = items[i]
		rec.B.Visible = it ~= nil
		if it then
			rec.Fn, rec.Off = it[2], it[3] == true
			local col = if rec.Off then "#9A9AA2" else "#FFFFFF"
			rec.T.Text = '<font color="#8C8C94">&gt;</font> <font color="' .. col .. '">' .. it[1] .. "</font>"
		end
	end
	self.Menu.Size = O(250, 20 + #items * 54)
	local cx, y = self:_local(btn, 0.62)
	self.Menu.Position = O(math.clamp(cx, 135, CW - 135), math.min(y, CH - (30 + #items * 54)))
	self.Menu.Visible = true
	self.Catch.Visible = true
end

function Inv:_equip(e, skin)
	if e.Kind == "Equipment" then
		local eqv = Remotes:FindFirstChild("EquipmentEquip")
		if eqv and eqv:IsA("RemoteEvent") then
			eqv:FireServer(e.Slot, if skin == Skins.Default then EquipCatalog.Default[e.Slot] else e.Id)
		end
		return
	end
	local ev = Remotes:FindFirstChild("SkinEquip")
	if ev and ev:IsA("RemoteEvent") then ev:FireServer(e.Weapon, skin) end
end

------------------------------------------------------------------ inspect
function Inv:_buildInspect(fit)
	local HS = self.HS
	local new = HS.new
	local ov = new("TextButton", { Name = "Inspect", Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, Size = S(1, 1), Visible = false, ZIndex = 50 }, fit)
	HS.corner(ov, 26)
	self.Ins = ov
	local p = new("Frame", { Name = "Card", BackgroundColor3 = WHITE, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(920, 660), ZIndex = 51 }, ov)
	HS.corner(p, 26)
	self.InsGrad = new("UIGradient", { Rotation = 90 }, p)
	self.InsStroke = HS.stroke(p, 6, WHITE)
	self.InsStrokeGrad = new("UIGradient", { Enabled = false, Color = K.CHROMA }, self.InsStroke)
	local clip = new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 51 }, p)
	self.InsRays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageTransparency = 0.7, AnchorPoint = V2(0.5, 0.5), Position = O(454, 280), Size = O(1300, 1300), ZIndex = 51 }, clip)
	self.InsBloom = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.4, AnchorPoint = V2(0.5, 0.5), Position = O(454, 280), Size = O(760, 460), ZIndex = 51 }, clip)
	self.InsVP = new("ViewportFrame", { Name = "View", BackgroundTransparency = 1, Position = O(30, 30), Size = O(860, 440), ZIndex = 52 }, p)
	self.InsName = self:_text(p, { Text = "", TextSize = 56, Stroke = 5, AnchorPoint = V2(0.5, 0), Position = O(460, 470), Size = O(800, 66), ZIndex = 53 })
	self.InsRar = self:_text(p, { Text = "", TextSize = 34, Stroke = 3.4, AnchorPoint = V2(0.5, 0), Position = O(460, 532), Size = O(600, 42), ZIndex = 53 })
	self.InsRarGrad = new("UIGradient", { Enabled = false, Color = K.CHROMA }, self.InsRar)
	self:_text(p, { Text = "Drag to rotate", TextSize = 20, Stroke = 2.2, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(460, 40), Size = O(300, 26), ZIndex = 53 })
	self.InsEquip = self:_pill(p, { Name = "Equip", Text = "EQUIP", TextSize = 32, Pal = PAL.Green, Z = 53, AnchorPoint = V2(0.5, 0), Position = O(320, 584), Size = O(260, 62), Sound = "Select", OnClick = function()
		local e = self.InsE
		if not e then return end
		if not e.Owned then
			self.Ins.Visible = false
			if self.Env.Open then self.Env.Open("Shop") end
		elseif not e.Equipped then
			self:_equip(e, e.Skin)
			restyle(self.InsEquip, PAL.Grey, "EQUIPPED")
		end
	end })
	self:_pill(p, { Name = "Back", Text = "BACK", TextSize = 32, Pal = PAL.Red, Z = 53, AnchorPoint = V2(0.5, 0), Position = O(600, 584), Size = O(260, 62), OnClick = function()
		self.Ins.Visible = false
		self.Spins.Inspect = nil
	end })
end

function Inv:_inspect(e)
	self.InsE = e
	local col = tierColor(e.Rarity)
	local seq = chromaSeq(e.Rarity)
	self.InsGrad.Color = CS({ CK(0, col:Lerp(BLACK, 0.3)), CK(0.6, col:Lerp(BLACK, 0.72)), CK(1, RGB(10, 4, 20)) })
	self.InsStroke.Color = if seq then WHITE else col:Lerp(WHITE, 0.25)
	self.InsStrokeGrad.Enabled = seq ~= nil
	if seq then self.InsStrokeGrad.Color = seq end
	self.InsRays.ImageColor3, self.InsBloom.ImageColor3 = col:Lerp(WHITE, 0.4), col
	local short, tag = splitName(e.Name)
	self.InsName.Text = short
	self.InsRar.Text = e.Rarity .. "  |  " .. e.Weapon .. (if tag then "  |  " .. tag else "")
	self.InsRar.TextColor3 = if seq then WHITE else col:Lerp(WHITE, 0.2)
	self.InsRarGrad.Enabled = seq ~= nil
	if seq then self.InsRarGrad.Color = seq end
	if e.Equipped then
		restyle(self.InsEquip, PAL.Grey, "EQUIPPED")
	elseif e.Owned then
		restyle(self.InsEquip, PAL.Green, "EQUIP")
	else
		restyle(self.InsEquip, PAL.Gold, "GET CRATES")
	end
	self.Spins.Inspect = self:_spin(self.InsVP, e, 860 / 440, 22)
	self.InsVP.ImageColor3 = if e.Owned then WHITE else RGB(10, 6, 22)
	self.Ins.Visible = true
end

------------------------------------------------------------------ renders
function Inv:_spin(vp, e, aspect, fov)
	local ok, m, size = pcall(K.weapon, e.Weapon, e.Skin)
	if not (ok and m and size) then
		vp:ClearAllChildren()
		return nil
	end
	K.view(vp, m, size, { Aspect = aspect, Fov = fov, Pad = 1.12 })
	return { Model = m, Base = m:GetPivot(), Yaw = -0.5, V = 0.6, Drag = false, X = 0, T = 0 }
end

-- flat silhouette copy of a framed gun (same camera), tinted by ImageColor3
function Inv:_sil(parent, vp, color, tr, scale, off, z)
	local cam, src = vp.CurrentCamera, vp:FindFirstChildWhichIsA("Model")
	if not (cam and src) then return end
	local v = self.HS.new("ViewportFrame", { Name = "Sil", BackgroundTransparency = 1, ImageColor3 = color, ImageTransparency = tr, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, off.X, 0.5, off.Y), Size = UDim2.new(0, vp.Size.X.Offset * scale, 0, vp.Size.Y.Offset * scale), Ambient = WHITE, LightColor = BLACK, ZIndex = z }, parent)
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color, d.Material, d.Reflectance = WHITE, Enum.Material.SmoothPlastic, 0
			pcall(function() d.TextureID = "" end)
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	local c = Instance.new("Camera")
	c.FieldOfView, c.CFrame = cam.FieldOfView, cam.CFrame
	c.Parent = v
	v.CurrentCamera = c
	m.Parent = v
end

-- world-space box of the visible parts
local function aabb(m)
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf, h = d.CFrame, d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
						mn, mx = mn:Min(p), mx:Max(p)
					end
				end
			end
		end
	end
	return mn, mx
end

-- every gun framed by its own length (stubby guns by height x 1.7), so all cards show the gun at the same size
local CARD_FOV = 20
local function frameUniform(vp, m, tilt, fill)
	vp:ClearAllChildren()
	local mn, mx = aabb(m)
	if mn.X == math.huge then return end
	local c = (mn + mx) / 2
	local span = mx - mn
	local L = math.max(span.X, span.Y * 1.7, 0.1)
	m:PivotTo(CFrame.new(c) * CFrame.Angles(0, 0, math.rad(tilt)) * CFrame.new(-c) * m:GetPivot())
	local cam = Instance.new("Camera")
	cam.FieldOfView = CARD_FOV
	local d = L * fill / (2 * math.tan(math.rad(CARD_FOV / 2)))
	cam.CFrame = CFrame.lookAt(c + Vector3.new(0, 0, d + span.Z), c)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Ambient = RGB(215, 215, 228)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-0.35, -0.6, -1)
	m.Parent = vp
end

-- the gun, placed diagonally at one shared size (live 3D render; atlas only when the model is missing)
function Inv:_render(parent, e, s, locked, z)
	local g = Config.Gun(e.Key)
	local ok3 = pcall(function() assert(Vantage.Weapons:FindFirstChild("Assets"):FindFirstChild(e.Weapon)) end)
	if g and not ok3 then
		self.HS.new("ImageLabel", { Name = "Gun", BackgroundTransparency = 1, Image = g.Image, ImageRectOffset = g.Offset, ImageRectSize = g.Size, ScaleType = Enum.ScaleType.Fit, ImageColor3 = if locked then RGB(4, 2, 10) else WHITE, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(s * 0.86, s * 0.43), Rotation = -38, ZIndex = z }, parent)
		return
	end
	local ok, m, size = pcall(K.weapon, e.Weapon, e.Skin)
	if ok and m and size then
		local vp = self.HS.new("ViewportFrame", { Name = "Gun3D", BackgroundTransparency = 1, ImageColor3 = if locked then RGB(4, 2, 10) else WHITE, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(s, s), ZIndex = z }, parent)
		frameUniform(vp, m, 38, 1.0)
		if not locked and s > 120 then
			-- drop shadow, rarity glow and a crisp white edge behind the gun so it pops off the card
			local col = tierColor(e.Rarity)
			vp.ZIndex = z + 1
			self:_sil(parent, vp, BLACK, 0.45, 1, V2(4, 6), z)
			self:_sil(parent, vp, hsv(col, 0.45, 1), 0.5, 1.09, V2(0, 0), z)
			self:_sil(parent, vp, WHITE, 0.15, 1.035, V2(0, 0), z)
		end
	end
end

function Inv:_card(parent, e, pos, s, locked)
	local HS = self.HS
	local new = HS.new
	local col = tierColor(e.Rarity)
	local ti = tierIndex(e.Rarity)
	local btn = new("TextButton", { Name = e.Key, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = pos, Size = O(s, s), ZIndex = 24 }, parent)
	new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = col, ImageTransparency = if locked then 0.88 else 0.42, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = s / 430, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, s * 0.32, 1, s * 0.32), ZIndex = 23 }, btn)
	local r = math.floor(s * 0.14)
	local face = new("Frame", { Name = "Face", BackgroundColor3 = WHITE, Size = S(1, 1), ZIndex = 24 }, btn)
	HS.corner(face, r)
	if locked then
		new("UIGradient", { Rotation = 90, Color = CS(RGB(34, 30, 46), RGB(12, 10, 18)) }, face)
	else
		new("UIGradient", { Rotation = 90, Color = faceSeq(e.Rarity) }, face)
	end
	local th = math.max(3, s * 0.045)
	local rim = HS.stroke(face, th, if locked then RGB(84, 78, 100) else hsv(col, 0.8, 1))
	local seq = (not locked) and chromaSeq(e.Rarity)
	if seq then
		table.insert(self.Rims, { G = new("UIGradient", { Color = seq }, rim), Spd = 140, P = math.random() * 360 })
	end
	-- darker outer rim
	local outer = new("Frame", { BackgroundTransparency = 1, Position = O(-th, -th), Size = UDim2.new(1, th * 2, 1, th * 2), ZIndex = 24 }, btn)
	HS.corner(outer, r + th)
	HS.stroke(outer, math.max(2, th * 0.6), if locked then RGB(20, 18, 26) else col:Lerp(BLACK, 0.45))
	local clip = new("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(th, th), Size = UDim2.new(1, -th * 2, 1, -th * 2), ZIndex = 24 }, btn)
	new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = hsv(col, 0.45, 1), ImageTransparency = if locked then 0.92 else 0.3, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.05, 0.95), ZIndex = 24 }, clip)
	self:_render(clip, e, s - th * 2, locked, 25)
	if locked then
		self:_text(clip, { Text = "?", TextSize = math.floor(s * 0.4), Fit = false, Stroke = 4, Color = col:Lerp(WHITE, 0.55), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.6, 0.6), ZIndex = 26 })
	end
	if locked and e.Kind == "Equipment" and s > 100 then
		-- shard progress: collect EquipCatalog.Shards of this item to unlock it
		local need = EquipCatalog.Shards or 3
		local have = math.clamp(e.Shards or 0, 0, need)
		local ph = math.max(22, math.floor(s * 0.16))
		local pill = new("Frame", { Name = "Shards", BackgroundColor3 = RGB(10, 26, 40), AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -th - 8), Size = O(math.floor(s * 0.64), ph), ZIndex = 27 }, btn)
		HS.corner(pill, UDim.new(0.5, 0))
		HS.stroke(pill, 2, RGB(90, 220, 255))
		if have > 0 then
			local fill = new("Frame", { Name = "Fill", BackgroundColor3 = RGB(64, 200, 255), BorderSizePixel = 0, Size = S(have / need, 1), ZIndex = 27 }, pill)
			HS.corner(fill, UDim.new(0.5, 0))
			new("UIGradient", { Rotation = 90, Color = CS(RGB(150, 240, 255), RGB(40, 150, 255)) }, fill)
		end
		self:_text(pill, { Text = have .. "/" .. need, TextSize = math.floor(ph * 0.78), Fit = false, Stroke = 2, Color = WHITE, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), ZIndex = 28 })
	end
	if not locked and ti >= 3 then
		for _ = 1, ti - 1 do
			local sz = math.floor(s * (0.12 + math.random() * 0.1))
			local st = new("ImageLabel", { Name = "Spark", BackgroundTransparency = 1, Image = STAR, ImageColor3 = WHITE, AnchorPoint = V2(0.5, 0.5), Position = S(0.15 + math.random() * 0.7, 0.12 + math.random() * 0.6), Size = O(sz, sz), ZIndex = 26 }, clip)
			table.insert(self.Stars, { I = st, Sz = sz, P = math.random() * 6, Spd = 1.6 + math.random() * 1.6 })
		end
	end
	-- light streak sweeping across every card (gradient sweep, so it stays inside the card)
	local sheen = new("Frame", { Name = "Wink", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 26 }, clip)
	HS.corner(sheen, math.max(0, r - th))
	local sg = new("UIGradient", { Rotation = 24, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.4, 1), NK(0.5, if locked then 0.8 else 0.42), NK(0.6, 1), NK(1, 1) }) }, sheen)
	table.insert(self.Winks, { G = sg, P = math.random() * 3.6 })
	if e.Equipped and s > 120 then
		-- green check badge, bottom-left (where Hypershot puts its star level)
		local b = new("Frame", { Name = "Equipped", BackgroundColor3 = RGB(70, 210, 100), AnchorPoint = V2(0.5, 0.5), Position = O(s * 0.2, s * 0.8), Size = O(36, 36), ZIndex = 27 }, btn)
		HS.corner(b, UDim.new(0.5, 0))
		HS.stroke(b, 3, RGB(14, 60, 24))
		new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = O(12, 20), Size = O(11, 5), Rotation = 45, ZIndex = 28 }, b)
		new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = O(20, 17), Size = O(19, 5), Rotation = -50, ZIndex = 28 }, b)
	end
	btn.MouseEnter:Connect(function() self:_tip(e, btn) end)
	btn.MouseLeave:Connect(function()
		if self.TipFor == btn then self.Tip.Visible = false end
	end)
	HS.press(btn, function() self:_menu(e, btn) end, { Hover = 1.05, Press = 0.95, Sound = "Select" })
	return btn
end

------------------------------------------------------------------ data
local Unlocks = require(game:GetService("ReplicatedStorage"):WaitForChild("Vantage"):WaitForChild("Weapons"):WaitForChild("WeaponUnlocks"))
-- 2026-11-18: skins pulled for a gun the player hasn't unlocked stay saved, but only show as owned once the gun is
local function gunOwned(w)
	return Unlocks.ById[w] == nil or Unlocks.Owns(w, player:GetAttribute("Level"), player:GetAttribute("OwnedWeapons"))
end
function Inv:_entries()
	local own = ownedSet()
	local list, nOwned, worth = {}, 0, 0
	for _, p in Config.Pool().All do
		local o = own[p.Key] == true and gunOwned(p.Weapon)
		if o then
			nOwned += 1
			worth += Config.Refund[p.Rarity] or 0
		end
		table.insert(list, {
			Key = p.Key, Weapon = p.Weapon, Skin = p.Skin, Name = p.Name, Rarity = p.Rarity, Ti = tierIndex(p.Rarity), Owned = o,
			Equipped = o and player:GetAttribute("Skin_" .. p.Weapon) == p.Skin,
		})
	end
	-- equipment (shield packs + grappling hooks); the starters are always owned
	for _, it in EquipCatalog.Items do
		local o = EquipCatalog.Owns(player, it.Id) == true
		if o then
			nOwned += 1
			worth += Config.Refund[it.Rarity] or 0
		end
		table.insert(list, {
			Key = "Equipment/" .. it.Id, Weapon = "Equipment", Skin = it.Id, Id = it.Id, Kind = "Equipment", Slot = it.Slot,
			Name = it.Name, Rarity = it.Rarity, Ti = tierIndex(it.Rarity), Owned = o, Ability = it.Ability,
			Shards = if o then nil else EquipCatalog.ShardCount(player, it.Id),
			Equipped = o and player:GetAttribute("Equip_" .. it.Slot) == it.Id,
		})
	end
	return list, nOwned, worth
end

function Inv:_refresh(top)
	self:_closeMenu()
	self.Tip.Visible = false
	local all, nOwned, worth = self:_entries()
	local req = player:GetAttribute("REQ")
	self.WorthText.Text = num(worth + (if type(req) == "number" then req else 0))
	self.CountText.Text = nOwned .. " / " .. #all
	self.Fill.Size = S(if #all > 0 then math.max(nOwned / #all, 0.02) else 0, 1)
	for _, cr in ALL_CRATES do
		if self.CrateLbl[cr.Id] then self.CrateLbl[cr.Id].Text = "x" .. crateCount(cr.Id) end
	end
	self.Title.Text = if self.Index then "ITEM INDEX" else "INVENTORY"
	self.Main.TitleGap.Size = O(if self.Index then 380 else 366, 24)
	restyle(self.IndexBtn, PAL.Gold, if self.Index then "INVENTORY" else "ITEM INDEX")
	self.RarityText.Text = if self.Desc then "Rarity" else "Rarity (low)"
	self.EqBtn.BackgroundColor3 = if self.EquippedOnly then RGB(60, 140, 255) else C.Field
	for _, m in self.EqMarks do m.BackgroundColor3 = if self.EquippedOnly then WHITE else RGB(60, 140, 255) end
	for w, t in self.DropItems do t.TextColor3 = if w == self.Weapon then C.Gold else WHITE end

	-- best pull for the showcase: equipped first, then rarity
	local best
	for _, e in all do
		if e.Owned and (not best or e.Ti > best.Ti or (e.Ti == best.Ti and e.Equipped and not best.Equipped)) then best = e end
	end
	if best then
		if self.ShowKey ~= best.Key then
			self.ShowKey = best.Key
			self.Spins.Show = self:_spin(self.ShowVP, best, 550 / 420, 24)
		end
		local col = tierColor(best.Rarity)
		self.ShowRays.ImageColor3, self.ShowBloom.ImageColor3 = col:Lerp(WHITE, 0.4), col
		self.ShowName.Text = (splitName(best.Name))
		self.ShowName.TextColor3 = col:Lerp(WHITE, 0.35)
	else
		self.ShowKey = nil
		self.Spins.Show = nil
		self.ShowVP:ClearAllChildren()
		self.ShowName.Text = "Open a crate to start your collection"
		self.ShowName.TextColor3 = C.Muted
	end

	-- filter + sort
	local q = self.Query
	local function pass(e)
		if self.Weapon ~= "All" and e.Weapon ~= self.Weapon then return false end
		if self.EquippedOnly and not e.Equipped then return false end
		if q ~= "" then
			return string.find(e.Name:lower(), q, 1, true) ~= nil or string.find(e.Weapon:lower(), q, 1, true) ~= nil or string.find(e.Rarity:lower(), q, 1, true) ~= nil
		end
		return true
	end
	local list = {}
	for _, e in all do
		if (self.Index or e.Owned) and pass(e) then table.insert(list, e) end
	end
	table.sort(list, function(a, b)
		if self.Index and a.Owned ~= b.Owned then return a.Owned end
		if a.Ti ~= b.Ti then
			if self.Desc then return a.Ti > b.Ti else return a.Ti < b.Ti end
		end
		if a.Weapon ~= b.Weapon then return a.Weapon < b.Weapon end
		return a.Name < b.Name
	end)

	-- rebuild the card area
	local sc = self.Scroll
	for _, c in sc:GetChildren() do c:Destroy() end
	local keepRims = {}
	for _, r in self.Rims do
		if r.G.Parent and r.G:IsDescendantOf(self.Root) and not r.G:IsDescendantOf(sc) then table.insert(keepRims, r) end
	end
	self.Rims, self.Stars, self.Winks, self.Marq = keepRims, {}, {}, nil
	for i, e in list do
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		self:_card(sc, e, O(GX0 + col * PITCH, GY0 + row * PITCH), CARD, not e.Owned)
	end
	local y = GY0 + math.ceil(#list / COLS) * PITCH
	if #list == 0 then
		self:_text(sc, { Text = if self.Index then "No skins match" else "No skins here yet", TextSize = 30, Stroke = 3, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = O(600, 40), ZIndex = 25 })
		y = 100
	end
	if not self.Index then
		-- "Many more to get!" teaser row of skins not owned yet, drifting sideways
		local teaser = {}
		for _, e in all do
			if not e.Owned then table.insert(teaser, e) end
		end
		table.sort(teaser, function(a, b)
			if a.Ti ~= b.Ti then return a.Ti > b.Ti end
			return a.Key < b.Key
		end)
		if #teaser > 0 then
			local n = math.min(#teaser, 8)
			local ty = math.max(y + 10, self.BoxH - 190)
			self:_text(sc, { Text = "Many more to get!", TextSize = 38, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, ty), Size = O(600, 50), ZIndex = 25 })
			local row = self.HS.new("Frame", { Name = "Teaser", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(GX0, ty + 62), Size = O(COLS * PITCH - 18, TCARD + 24), ZIndex = 24 }, sc)
			local strip = self.HS.new("Frame", { Name = "Strip", BackgroundTransparency = 1, Size = O(n * TPITCH * 2, TCARD + 24), ZIndex = 24 }, row)
			for k = 1, n * 2 do
				local e = teaser[(k - 1) % n + 1]
				self:_card(strip, e, O((k - 1) * TPITCH + 10, 12), TCARD, false)
			end
			self.Marq = { F = strip, W = n * TPITCH }
			y = ty + 62 + TCARD + 40
		end
	end
	sc.CanvasSize = O(0, y + 10)
	if top then sc.CanvasPosition = V2(0, 0) end
end

------------------------------------------------------------------ animation
function Inv:_step(dt)
	local t = os.clock()
	for key, sp in self.Spins do
		if sp and sp.Model and sp.Model.Parent then
			if not sp.Drag then
				sp.V += (0.6 - sp.V) * math.min(1, dt * 1.6)
				sp.Yaw += sp.V * dt
			end
			sp.Model:PivotTo(CFrame.Angles(0.12, 0, 0) * CFrame.Angles(0, sp.Yaw, 0) * sp.Base)
		end
	end
	self.ShowRays.Rotation = (t * 8) % 360
	if self.Ins.Visible then self.InsRays.Rotation = (t * 6) % 360 end
	for _, r in self.Rims do r.G.Rotation = (r.P + t * r.Spd) % 360 end
	for _, s in self.Stars do
		local k = 0.5 + 0.5 * math.sin(t * s.Spd + s.P)
		s.I.Size = O(s.Sz * (0.35 + 0.75 * k), s.Sz * (0.35 + 0.75 * k))
		s.I.ImageTransparency = 1 - k * 0.95
		s.I.Rotation = (t * 40 + s.P * 30) % 360
	end
	for _, w in self.Winks do
		local u = ((t + w.P) % 3.6) / 0.9
		w.G.Offset = V2(-1 + math.clamp(u, 0, 1) * 2, 0)
	end
	if self.Marq then
		self.Marq.F.Position = O(-((t * 34) % self.Marq.W), 0)
	end
end

------------------------------------------------------------------ mount
function Inv:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.42, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
	self.FitFrame.Position = UDim2.new(0.5, 0, 0.5, 16 * self.Fit.Scale)
end

function Inv:OnShow()
	self:_fit()
	self.Index = false
	self.Ins.Visible = false
	self.Spins.Inspect = nil
	self.Drop.Visible = false
	self:_refresh(true)
end

function Inv.Mount(layer, env)
	local s = Inv.new(layer, env)
	return {
		Root = s.Root,
		OnShow = function() s:OnShow() end,
		OnData = function() if s.Root.Visible then s:_refresh() end end,
		Object = s,
	}
end

return Inv
