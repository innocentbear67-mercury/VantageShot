--!nocheck
--[[
	CasesHS — Cases modal (BUY / OPEN), reconstructed from the Hypershot Cases captures (2026-11-16).
	Geometry is design px (ref px x 0.6827). Panel 635.6 square, tabs 192.5 x 50.5, crate cards 116.1 x 114.7 (pitch 125.6),
	detail box 441 x 130.4, odds box 441 x 354.3. OPEN tab: two full-width boxes 594 x 255.5.
	VantageShot additions (our 10%): REQ pricing, OPEN detail box with x1 / x5, owned counts, guarantee line.
	Server: Remotes.CrateBuy(id, qty) adds owned crates; opening goes through CrateOpening (Remotes.CrateOpen consumes them).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Config = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))

local Cases = {}
Cases.__index = Cases

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB

local C = {
	-- dark neon purple (the user's Shop-bag look): deep violet fills, neon violet rims
	Panel = RGB(26, 10, 48),
	Stripe = RGB(17, 6, 33),
	Edge = RGB(150, 80, 255),
	Box = RGB(21, 8, 40),
	BoxEdge = RGB(104, 56, 186),
	Tab = RGB(30, 13, 54),
	TabEdge = RGB(80, 44, 146),
	Green = RGB(117, 251, 134),
	Card = RGB(33, 14, 60),
	Muted = RGB(184, 164, 222),
	White = RGB(255, 255, 255),
	Black = RGB(0, 0, 0),
}
local TIER = {
	Rare = RGB(88, 160, 255),
	Epic = RGB(190, 98, 255),
	Mythic = RGB(214, 224, 242),
	Legendary = RGB(255, 198, 50),
	Exclusive = RGB(255, 110, 220),
	Godly = RGB(255, 236, 140),
}

-- Arsenal crates (gun unlocks, ORD) first, then weapon-skin crates, then equipment crates (shield packs + grappling hooks)
local ALL_CRATES = {}
for _, c in Config.WeaponCrates or {} do
	table.insert(ALL_CRATES, c)
end
for _, c in Config.Crates do
	table.insert(ALL_CRATES, c)
end
for _, c in Config.EquipmentCrates or {} do
	table.insert(ALL_CRATES, c)
end
local OrdCfg = require(Vantage:WaitForChild("Ordnance"):WaitForChild("OrdnanceConfig"))
local function isGunCrate(c)
	return Config.IsWeaponCrate and Config.IsWeaponCrate(c)
end
local function currency(c)
	return if Config.Currency then Config.Currency(c) else "REQ"
end
local function ownedGuns()
	local set = {}
	for id in string.gmatch(player:GetAttribute("OwnedWeapons") or "", "[^,]+") do
		set[id] = true
	end
	return set
end
-- guns still locked for this player (Arsenal pool entries)
local function lockedGuns(crate)
	local set, out = ownedGuns(), {}
	for _, e in Config.Pool(crate).All do
		if not set[e.Id] then table.insert(out, e) end
	end
	return out
end

local EQUIP_CRATE = {}
for _, c in Config.EquipmentCrates or {} do
	EQUIP_CRATE[c.Id] = true
end
local SHARDS = 3 -- EquipmentCatalog.Shards

local function fmt(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function crateName(c)
	return string.upper((c.Name:gsub("%s*Crate$", "")))
end

function Cases.new(layer, env)
	local self = setmetatable({ Env = env, HS = env.HS, Tab = "Buy", Sel = 1, OpenSel = nil, Qty = 1 }, Cases)
	self:_build(layer)
	return self
end

-- slow float for animated crate art (Arsenal); on = false stops it and puts the image back
local TweenService = game:GetService("TweenService")
function Cases:_bob(img, on, base)
	self.Bobs = self.Bobs or {}
	local tw = self.Bobs[img]
	if on and not tw then
		img.Position = base
		tw = TweenService:Create(img, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = base + UDim2.fromOffset(0, -5) })
		tw:Play()
		self.Bobs[img] = tw
	elseif not on and tw then
		tw:Cancel()
		self.Bobs[img] = nil
		img.Position = base
	end
end

function Cases:_box(parent, name, pos, size, r, edge, fill)
	local HS = self.HS
	local f = HS.new("Frame", { Name = name, BackgroundColor3 = fill or C.Box, Position = pos, Size = size, ZIndex = 22 }, parent)
	HS.corner(f, r)
	HS.stroke(f, 2.7, edge or C.BoxEdge)
	return f
end

-- raised pill (BUY / Odds / OPEN): dark rim, gradient face, thicker bottom lip
function Cases:_pill(parent, p)
	local HS = self.HS
	local b = HS.new("TextButton", { Name = p.Name, Text = "", AutoButtonColor = false, BackgroundColor3 = p.Rim, Position = p.Position, Size = p.Size, ZIndex = 23 }, parent)
	HS.corner(b, p.R or 8)
	local face = HS.new("Frame", { Name = "Face", BackgroundColor3 = C.White, BorderSizePixel = 0, Position = O(p.Side or 3.4, p.Top or 1.4), Size = UDim2.new(1, -(p.Side or 3.4) * 2, 1, -((p.Top or 1.4) + (p.Lip or 4.4))), ZIndex = 23 }, b)
	HS.corner(face, (p.R or 8) - 2)
	HS.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(p.Top0, p.Top1) }, face)
	HS.new("Frame", { Name = "Gloss", BackgroundColor3 = C.White, BackgroundTransparency = 0.82, BorderSizePixel = 0, Position = O(3, 1), Size = UDim2.new(1, -6, 0.42, 0), ZIndex = 23 }, face).Visible = p.Gloss ~= false
	local t = HS.text(b, { Name = "Label", Text = p.Text, TextSize = p.TextSize or 26, Stroke = p.Stroke or 2.6, StrokeColor = p.Ink or RGB(20, 40, 10), Position = O(0, -1), Size = S(1, 1), ZIndex = 25 })
	HS.press(b, p.OnClick, { Hover = 1.06, Press = 0.94, Sound = p.Sound })
	return b, t
end

function Cases:_tab(parent, name, x)
	local HS = self.HS
	local b = HS.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = C.Tab, Position = O(x, 18.5), Size = O(192.5, 50.5), ZIndex = 22 }, parent)
	HS.corner(b, 11)
	local st = HS.stroke(b, 3.4, C.TabEdge)
	local t = HS.text(b, { Name = "Label", Text = string.upper(name), TextSize = 34, Stroke = 2.7, StrokeColor = C.Black, ZIndex = 23 })
	HS.press(b, function()
		self:_setTab(name)
	end, { Hover = 1.04, Press = 0.95, Sound = "Tab" })
	return { Button = b, Stroke = st, Label = t }
end

function Cases:_crateCard(parent, crate, i, onPick)
	local HS = self.HS
	local b = HS.new("TextButton", { Name = crate.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = C.Card, Size = O(116.1, 114.7), LayoutOrder = i, ZIndex = 23 }, parent)
	HS.corner(b, 11)
	local st = HS.stroke(b, 2.7, C.TabEdge)
	HS.text(b, { Name = "Name", Text = crateName(crate), TextSize = 18, Color = crate.Light:Lerp(crate.Color, 0.35), Stroke = 0, AnchorPoint = V2(0.5, 0.5), Position = O(58, 20.5), Size = O(110, 20), ZIndex = 24 })
	local art = HS.new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = crate.Art.Full, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(58, 67), Size = O(108, 76), ZIndex = 24 }, b)
	if crate.Art.Mask then -- animated crate art (Arsenal): light sweep cut to the crate + a slow float
		HS.streak(art, crate.Art.Mask, 25).ScaleType = Enum.ScaleType.Fit
		self:_bob(art, true, art.Position)
	end
	HS.press(b, onPick, { Hover = 1.05, Press = 0.95, Sound = "Select" })
	return { Button = b, Stroke = st }
end

function Cases:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "Cases", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = O(635.6, 635.6), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit = new("UIScale", { Name = "Fit" }, fit)
	self.FitFrame = fit
	local outer = new("Frame", { Name = "Panel", BackgroundColor3 = C.Black, Size = S(1, 1), ZIndex = 20 }, fit)
	HS.corner(outer, 17.7)
	local panel = new("Frame", { Name = "Inner", BackgroundColor3 = C.White, Position = O(6.8, 6.8), Size = UDim2.new(1, -13.6, 1, -13.6), ZIndex = 21 }, outer)
	HS.corner(panel, 15)
	HS.stroke(panel, 3.4, C.Edge).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local glow = HS.stroke(outer, 2.2, RGB(190, 120, 255), 0.35)
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local bands = {}
	for i, x in { 0, 0.2, 0.2001, 0.5, 0.5001, 0.66, 0.6601, 0.95, 0.9501, 1 } do
		table.insert(bands, ColorSequenceKeypoint.new(x, if ((i + 1) // 2) % 2 == 1 then C.Panel else C.Stripe))
	end
	new("UIGradient", { Rotation = 45, Color = ColorSequence.new(bands) }, panel)
	self.Panel = panel

	HS.text(panel, { Name = "Title", Text = "CRATES", TextSize = 39, Stroke = 3.4, StrokeColor = C.Black, X = Enum.TextXAlignment.Left, AnchorPoint = V2(0, 0.5), Position = O(19.8, 44.4), Size = O(150, 40), ZIndex = 23 })
	self.Tabs = { Buy = self:_tab(panel, "Buy", 165.2), Open = self:_tab(panel, "Open", 382.3) }
	local badge = new("Frame", { Name = "Badge", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = O(32, 32), BackgroundColor3 = RGB(200, 52, 52), Visible = false, ZIndex = 26 }, self.Tabs.Open.Button)
	HS.corner(badge, 9)
	HS.stroke(badge, 2.7, RGB(70, 12, 12))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(255, 255, 255), RGB(205, 205, 205)) }, badge)
	self.BadgeText = HS.text(badge, { Text = "0", TextSize = 24, Stroke = 2.4, StrokeColor = RGB(70, 12, 12), ZIndex = 27 })
	self.Badge = badge
	local close = new("TextButton", { Name = "Close", Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(52, 11, 16), AnchorPoint = V2(0.5, 0.5), Position = O(629.4, 7.5), Size = O(61.4, 59.4), ZIndex = 30 }, fit)
	HS.corner(close, 10)
	local cf = new("Frame", { Name = "Face", BackgroundColor3 = C.White, BorderSizePixel = 0, Position = O(3, 3), Size = UDim2.new(1, -6, 1, -9), ZIndex = 30 }, close)
	HS.corner(cf, 8)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(221, 55, 71)), ColorSequenceKeypoint.new(0.42, RGB(224, 57, 79)), ColorSequenceKeypoint.new(0.62, RGB(232, 128, 112)), ColorSequenceKeypoint.new(1, RGB(241, 166, 112)) }) }, cf)
	new("Frame", { Name = "Lip", BackgroundColor3 = RGB(106, 46, 28), BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = UDim2.new(0, 3, 1, -2), Size = UDim2.new(1, -6, 0, 5), ZIndex = 30 }, close)
	HS.text(close, { Name = "X", Text = "X", TextSize = 44, Stroke = 2.4, StrokeColor = RGB(60, 20, 22), Position = O(0, -3), ZIndex = 31 })
	HS.press(close, function()
		self.Env.Close()
	end, { Hover = 1.08, Press = 0.92, Sound = "Click" })

	-- BUY page
	local buy = new("Frame", { Name = "BuyPage", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 22 }, panel)
	self.BuyPage = buy
	local list = new("ScrollingFrame", { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = O(16.2, 96.2), Size = O(146, 494), CanvasSize = O(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, ScrollBarImageColor3 = RGB(70, 74, 84), VerticalScrollBarInset = Enum.ScrollBarInset.None, ZIndex = 22 }, buy)
	new("UIListLayout", { Padding = UDim.new(0, 10.9), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, list)
	self.Cards = {}
	for i, crate in ALL_CRATES do
		self.Cards[i] = self:_crateCard(list, crate, i, function()
			self:_select(i)
		end)
	end
	local det = self:_box(buy, "Detail", O(165.2, 96.3), O(441, 130.4), 16.4)
	self.DName = HS.text(det, { Name = "Name", Text = "", TextSize = 21, Stroke = 0, AnchorPoint = V2(0.5, 0.5), Position = O(66.9, 25.3), Size = O(130, 22), ZIndex = 23 })
	self.DArt = new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Position = O(10, 34), Size = O(112, 80), ZIndex = 23 }, det)
	self.DArtSweep = HS.streak(self.DArt, "", 24)
	self.DArtSweep.ScaleType = Enum.ScaleType.Fit
	HS.text(det, { Name = "Qty", Text = "Amount", TextSize = 26, Stroke = 1.6, StrokeColor = C.Black, AnchorPoint = V2(0.5, 0.5), Position = O(215, 44), Size = O(140, 30), ZIndex = 23 })
	self.Price = HS.text(det, { Name = "Price", Text = "0", TextSize = 26, Stroke = 1.6, StrokeColor = C.Black, X = Enum.TextXAlignment.Right, AnchorPoint = V2(1, 0.5), Position = O(387.1, 44), Size = O(130, 30), ZIndex = 23 })
	self.Coin = new("ImageLabel", { Name = "Coin", BackgroundTransparency = 1, Image = HS.Img.Req, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0, 0.5), Position = O(391.2, 42.3), Size = O(34.1, 34.1), ZIndex = 23 }, det)
	self.OrdCoin = HS.ordCoin(det, { Name = "OrdCoin", AnchorPoint = V2(0, 0.5), Position = O(392, 42.3), Size = O(31, 31), ZIndex = 23 })
	self.OrdCoin.Visible = false
	local function stepBox(name, x, w, fill, txt, col, fn)
		local b = new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = fill, Position = O(x, 73), Size = O(w, 34.1), ZIndex = 23 }, det)
		HS.corner(b, 9)
		HS.stroke(b, 2.7, C.BoxEdge)
		local t = HS.text(b, { Name = "T", Text = txt, TextSize = 28, Color = col, Stroke = 1.4, StrokeColor = C.Black, ZIndex = 24 })
		if fn then
			HS.press(b, fn, { Hover = 1.08, Press = 0.9, Sound = "Click" })
		end
		return b, t
	end
	stepBox("Minus", 140, 37.5, C.Black, "-", C.White, function()
		self:_qty(-1)
	end)
	local _, qv = stepBox("Value", 187.7, 51.2, RGB(15, 15, 15), "1", C.Green)
	self.QtyText = qv
	stepBox("Plus", 250.5, 37.5, C.Black, "+", C.White, function()
		self:_qty(1)
	end)
	self.BuyBtn = self:_pill(det, { Name = "Buy", Text = "BUY", TextSize = 28, Position = O(335.9, 73), Size = O(92.2, 35.5), Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Lip = 4.6, Side = 3.4, Top = 1.4, Ink = RGB(25, 45, 12), Sound = false, OnClick = function()
		self:_buy()
	end })
	self.Msg = HS.text(det, { Name = "Msg", Text = "", TextSize = 17, Color = RGB(255, 110, 110), Stroke = 1.4, StrokeColor = C.Black, AnchorPoint = V2(1, 0), Position = O(428, 111), Size = O(260, 18), X = Enum.TextXAlignment.Right, ZIndex = 23 })
	local odds = self:_box(buy, "Odds", O(165.2, 245.8), O(441, 354.3), 16.4)
	self:_pill(odds, { Name = "OddsBtn", Text = "Rates", TextSize = 18, Position = O(348.2, 19.8), Size = O(73, 26.6), Rim = RGB(37, 89, 191), Top0 = RGB(95, 169, 245), Top1 = RGB(54, 122, 233), Lip = 2.8, Side = 1.4, Top = 1.4, R = 7, Ink = RGB(14, 30, 70), Gloss = false, OnClick = function()
		self.ShowContents = not self.ShowContents
		self:_render()
	end })
	self.OddsList = new("Frame", { Name = "Lines", BackgroundTransparency = 1, Position = O(25.3, 21.2), Size = O(400, 320), ZIndex = 23 }, odds)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, self.OddsList)

	-- OPEN page
	local op = new("Frame", { Name = "OpenPage", BackgroundTransparency = 1, Size = S(1, 1), Visible = false, ZIndex = 22 }, panel)
	self.OpenPage = op
	local owned = self:_box(op, "Owned", O(13.7, 81.9), O(594, 255.5), 27)
	local grid = new("ScrollingFrame", { Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0, Position = O(10, 8), Size = UDim2.new(1, -20, 1, -16), CanvasSize = O(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = RGB(70, 74, 84), ZIndex = 23 }, owned)
	new("UIGridLayout", { CellSize = O(92.8, 93.5), CellPadding = O(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	new("UIPadding", { PaddingTop = UDim.new(0, 8.4), PaddingLeft = UDim.new(0, 23.5) }, grid)
	self.Grid = grid
	self.Empty = HS.text(owned, { Name = "Empty", Text = "No crates yet. Buy some on the BUY tab!", TextSize = 22, Color = C.Muted, Stroke = 1.4, StrokeColor = C.Black, ZIndex = 24 })
	local sel = self:_box(op, "Selected", O(13.7, 349.6), O(594, 255.5), 27)
	self.SelBox = sel
	self.SArt = new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Position = O(26, 30), Size = O(230, 160), ZIndex = 24 }, sel)
	self.SArtSweep = HS.streak(self.SArt, "", 25)
	self.SArtSweep.ScaleType = Enum.ScaleType.Fit
	self.SName = HS.text(sel, { Name = "Name", Text = "", TextSize = 38, Stroke = 2.7, StrokeColor = C.Black, X = Enum.TextXAlignment.Left, Position = O(280, 34), Size = O(290, 42), ZIndex = 24 })
	self.SOwned = HS.text(sel, { Name = "Owned", Text = "", TextSize = 24, Color = C.Muted, Stroke = 1.4, StrokeColor = C.Black, X = Enum.TextXAlignment.Left, Position = O(282, 80), Size = O(290, 28), ZIndex = 24 })
	self.SPity = HS.text(sel, { Name = "Pity", Text = "", TextSize = 19, Color = RGB(255, 214, 120), Stroke = 1.4, StrokeColor = C.Black, X = Enum.TextXAlignment.Left, Position = O(282, 110), Size = O(290, 24), ZIndex = 24 })
	self.Open1 = self:_pill(sel, { Name = "Open1", Text = "OPEN", TextSize = 30, Position = O(282, 160), Size = O(132, 46), Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Lip = 5, Ink = RGB(25, 45, 12), Sound = false, OnClick = function()
		self:_open(1)
	end })
	self.Open5 = self:_pill(sel, { Name = "Open5", Text = "OPEN x5", TextSize = 28, Position = O(428, 160), Size = O(140, 46), Rim = RGB(37, 89, 191), Top0 = RGB(95, 169, 245), Top1 = RGB(54, 122, 233), Lip = 5, Ink = RGB(14, 30, 70), Sound = false, OnClick = function()
		self:_open(5)
	end })
	self.SEmpty = HS.text(sel, { Name = "Hint", Text = "", TextSize = 22, Color = C.Muted, Stroke = 1.4, StrokeColor = C.Black, ZIndex = 24 })

	player:GetAttributeChangedSignal("OwnedCrates"):Connect(function()
		self:_render()
	end)
	player:GetAttributeChangedSignal("REQ"):Connect(function()
		self:_render()
	end)
	for _, a in { "ORD", "OwnedWeapons" } do
		player:GetAttributeChangedSignal(a):Connect(function()
			self:_render()
		end)
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_fit()
	end)
	self:_select(1)
	self:_setTab("Buy", true)
end

function Cases:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.42, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
	self.FitFrame.Position = UDim2.new(0.5, 0, 0.5, 40 * self.Fit.Scale)
end

function Cases:_owned()
	local ok, t = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("OwnedCrates") or "{}")
	end)
	return ok and type(t) == "table" and t or {}
end

function Cases:_setTab(name)
	self.Tab = name
	for n, t in self.Tabs do
		local on = n == name
		t.Stroke.Color = if on then C.Green else C.TabEdge
		t.Label.TextColor3 = if on then C.White else C.Muted
	end
	self.BuyPage.Visible = name == "Buy"
	self.OpenPage.Visible = name == "Open"
	self:_render()
end

function Cases:_select(i)
	self.Sel = i
	self.Qty = 1
	self.ShowContents = false
	self.Msg.Text = ""
	for k, c in self.Cards do
		c.Stroke.Color = if k == i then C.Green else C.TabEdge
	end
	self:_render()
end

function Cases:_qty(d)
	self.Qty = math.clamp(self.Qty + d, 1, 99)
	self:_render()
end

function Cases:_lines(crate)
	for _, c in self.OddsList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local HS = self.HS
	local n = 0
	local function line(rich, indent)
		n += 1
		local t = HS.text(self.OddsList, { Name = "L" .. n, Text = rich, Rich = true, TextSize = 24, Stroke = 1.6, StrokeColor = C.Black, X = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 25.3), ZIndex = 24 })
		t.LayoutOrder = n
		if indent then
			HS.new("UIPadding", { PaddingLeft = UDim.new(0, 17.8) }, t)
		end
	end
	local function hex(c)
		return "#" .. c:ToHex()
	end
	if self.ShowContents then
		line('<font color="#96BEDC">Contents</font>')
		local seen = {}
		for _, t in Config.Tiers do
			if crate.Odds[t] and crate.Odds[t] > 0 then
				local names = {}
				for _, e in Config.Pool(crate).ByTier[t] or {} do
					if not seen[e.Key] and #names < 4 then
						seen[e.Key] = true
						table.insert(names, e.Name)
					end
				end
				line(string.format('•  <font color="%s">%s</font>  %s', hex(TIER[t]), t, table.concat(names, ", ")), true)
			end
		end
		return
	end
	local total = 0
	for _, t in Config.Tiers do
		total += crate.Odds[t] or 0
	end
	if isGunCrate(crate) then
		-- Arsenal: one new gun per crate, equal chance among the guns still locked
		local locked = lockedGuns(crate)
		line('<font color="#FFB45A">New Gun</font> - 100%')
		if #locked == 0 then
			line('<font color="#75FB86">You own every gun!</font>', true)
		else
			local pct = 100 / #locked
			for _, e in locked do
				line(string.format('•  <font color="%s">%s</font>  <font color="#B8A4DE">%s</font> - %s', hex(TIER[e.Rarity] or C.White), e.Name, string.lower(e.Class or ""), if pct >= 1 then string.format("%d%%", math.floor(pct + 0.5)) else string.format("%.2g%%", pct)), true)
			end
		end
		n += 1
		HS.new("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 25.3), LayoutOrder = n }, self.OddsList)
		line('<font color="#7FE6FF">Never a duplicate</font> - only guns you don\'t own', false)
		line('<font color="#FFB45A">Unlocks instantly</font> for your loadout', false)
		return
	end
	local eq = EQUIP_CRATE[crate.Id]
	line(if eq then '<font color="#96BEDC">Equipment Shard</font> - 100%' else '<font color="#96BEDC">Weapon Skin</font> - 100%')
	for _, t in Config.Tiers do
		local w = crate.Odds[t]
		if w and w > 0 then
			local pct = w / total * 100
			local s = if pct >= 1 then string.format("%d%%", math.floor(pct + 0.5)) else string.format("%.2g%%", pct)
			line(string.format('•  <font color="%s">%s%s</font> - %s', hex(TIER[t]), t, if eq then " Shard" else "", s), true)
		end
	end
	n += 1
	HS.new("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 25.3), LayoutOrder = n }, self.OddsList)
	line(string.format('<font color="#FFB45A">Guaranteed</font> - <font color="%s">%s</font> within %d opens', hex(TIER[crate.PityTier]), crate.PityTier, crate.Pity))
	if eq then
		line(string.format('<font color="#7FE6FF">%d shards</font> of the same item unlock it', SHARDS))
	end
end

function Cases:_render()
	local crate = ALL_CRATES[self.Sel]
	local owned = self:_owned()
	local total = 0
	for _, n in owned do
		total += n
	end
	self.Badge.Visible = total > 0
	self.BadgeText.Text = tostring(total)
	if self.Tab == "Buy" and crate then
		self.DName.Text = crateName(crate)
		self.DName.TextColor3 = crate.Light:Lerp(crate.Color, 0.35)
		self.DArt.Image = crate.Art.Full
		self.DArtSweep.Image = crate.Art.Mask or ""
		self.DArtSweep.Visible = crate.Art.Mask ~= nil
		self:_bob(self.DArt, crate.Art.Mask ~= nil, O(10, 34))
		self.QtyText.Text = tostring(self.Qty)
		self.Price.Text = fmt(crate.Price * self.Qty)
		local cur = currency(crate)
		self.Coin.Visible = cur ~= "ORD"
		self.OrdCoin.Visible = cur == "ORD"
		local afford = (player:GetAttribute(cur) or 0) >= crate.Price * self.Qty
		self.Price.TextColor3 = if afford then C.White else RGB(255, 120, 120)
		self:_lines(crate)
	elseif self.Tab == "Open" then
		for _, c in self.Grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local first
		for _, c in ALL_CRATES do
			if (owned[c.Id] or 0) > 0 then
				first = first or c.Id
			end
		end
		if not self.OpenSel or (owned[self.OpenSel] or 0) <= 0 then
			self.OpenSel = first
		end
		local HS = self.HS
		for i, c in ALL_CRATES do
			local n = owned[c.Id] or 0
			if n > 0 then
				first = first or c.Id
				local b = HS.new("TextButton", { Name = c.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = C.Card, LayoutOrder = i, ZIndex = 24 }, self.Grid)
				HS.corner(b, 11)
				HS.stroke(b, 2.7, if self.OpenSel == c.Id then C.Green else C.TabEdge)
				local col = c.Light:Lerp(c.Color, 0.35)
				HS.text(b, { Name = "Name", Rich = true, Text = string.format('<font color="#%s">%s</font> x%d', col:ToHex(), crateName(c), n), TextSize = 16, Stroke = 1.2, StrokeColor = C.Black, AnchorPoint = V2(0.5, 0), Position = O(46.4, 5), Size = O(90, 18), ZIndex = 25 })
				local gart = HS.new("ImageLabel", { BackgroundTransparency = 1, Image = c.Art.Full, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(46.4, 57), Size = O(86, 62), ZIndex = 25 }, b)
				if c.Art.Mask then
					HS.streak(gart, c.Art.Mask, 26).ScaleType = Enum.ScaleType.Fit
				end
				HS.press(b, function()
					self.OpenSel = c.Id
					self:_render()
				end, { Hover = 1.06, Press = 0.94, Sound = "Select" })
			end
		end
		if not self.OpenSel or (owned[self.OpenSel] or 0) <= 0 then
			self.OpenSel = first
		end
		self.Empty.Visible = first == nil
		local sc = self.OpenSel and Config.ById[self.OpenSel]
		local n = sc and owned[sc.Id] or 0
		for _, o in { self.SArt, self.SName, self.SOwned, self.SPity, self.Open1, self.Open5 } do
			o.Visible = sc ~= nil
		end
		self.SEmpty.Visible = sc == nil
		self.SEmpty.Text = if sc then "" else "Select a crate to open"
		if sc then
			self.SArt.Image = sc.Art.Full
			self.SArtSweep.Image = sc.Art.Mask or ""
			self.SArtSweep.Visible = sc.Art.Mask ~= nil
			self:_bob(self.SArt, sc.Art.Mask ~= nil, O(26, 30))
			self.SName.Text = sc.Name
			self.SName.TextColor3 = sc.Light:Lerp(sc.Color, 0.35)
			self.SOwned.Text = string.format("You own %d", n)
			local pity = player:GetAttribute("CratePity_" .. sc.Id) or 0
			self.SPity.Text = if isGunCrate(sc) then string.format("New gun every open · %d still locked", #lockedGuns(sc)) else string.format("%s guaranteed in %d opens", sc.PityTier, math.max(1, sc.Pity - pity))
			self.Open5.Visible = n >= 5
		end
	end
end

function Cases:_buy()
	local HS = self.HS
	local crate = ALL_CRATES[self.Sel]
	if self.Busy or not crate then
		return
	end
	self.Busy = true
	local ok, res = pcall(function()
		return Remotes:WaitForChild("CrateBuy", 5):InvokeServer(crate.Id, self.Qty)
	end)
	self.Busy = false
	if ok and type(res) == "table" and res.Ok then
		HS.sound("Purchase")
		self.Msg.TextColor3 = C.Green
		self.Msg.Text = string.format("+%d %s added to OPEN", self.Qty, crateName(crate))
		self.Qty = 1
		local pop = self.Badge:FindFirstChildOfClass("UIScale") or HS.new("UIScale", {}, self.Badge)
		pop.Scale = 1.5
		HS.tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		HS.sound("Deny")
		self.Msg.TextColor3 = RGB(255, 110, 110)
		self.Msg.Text = if ok and type(res) == "table" then tostring(res.Error) else "Couldn't buy, try again"
	end
	self:_render()
end

function Cases:_open(count)
	local crate = self.OpenSel and Config.ById[self.OpenSel]
	local opening = self.Env.Opening
	if not crate or not opening or opening.Active then
		self.HS.sound("Deny")
		return
	end
	if (self:_owned()[crate.Id] or 0) < count then
		self.HS.sound("Deny")
		return
	end
	self.HS.sound("Click")
	self.Env.Close(true)
	if self.Env.Hud then
		self.Env.Hud(false)
		task.spawn(function() -- never leave the HUD hidden if the sequence ends without OnDone
			task.wait(1)
			while opening.Active do
				task.wait(0.25)
			end
			self.Env.Hud(true)
		end)
	end
	opening:Play(crate, { Count = count, OnDone = function()
		task.defer(function()
			if self.Env.Hud then
				self.Env.Hud(true)
			end
			self.Env.Reopen("Cases")
			self:_setTab("Open")
		end)
	end })
end

function Cases:OnShow()
	self:_fit()
	self:_render()
end

function Cases.Mount(layer, env)
	local c = Cases.new(layer, env)
	return {
		Root = c.Root,
		OnShow = function()
			c:OnShow()
		end,
		OnData = function()
			c:_render()
		end,
		Object = c,
	}
end

return Cases
