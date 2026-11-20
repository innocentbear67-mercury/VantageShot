--[[
	VANTAGE — Loadout screen (lobby, client). Approved canvas board "Loadout" (2026-11-15).
	  left    Arsenal: the seven weapons, each wearing its equipped skin
	  centre  3D showcase (Showcase stage): the previewed skin floats over the podium with its own FX
	          theme; drag to turn it. Title: class chip, weapon name, rarity chip + skin name
	  bottom  stats (WeaponConfig values) that count up and ease when the weapon changes
	  right   skin collection: rarity cards with neon rims that wink, filters, detail strip + EQUIP
	Equip -> Remotes.SkinEquip(weaponId, skinId); LoadoutService validates + saves and replies on
	SkinResult (toast + burst). Equipped skins come from Skins.ForPlayer (Skin_<Weapon> attribute).
	Screen protocol for Lobby: :Show() :Hide() :HandleKey(kc) .Gui
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Weapons = Vantage:WaitForChild("Weapons")
local Skins = require(Weapons:WaitForChild("Skins"))
local Config = require(Weapons:WaitForChild("WeaponConfig"))
local Remotes = Vantage:WaitForChild("Remotes")
local K = require(script.Parent:WaitForChild("ScreenKit"))
local Showcase = require(script.Parent:WaitForChild("Showcase"))
local CardArt = require(script.Parent:WaitForChild("CardArt"))

local player = Players.LocalPlayer
local C = Color3.fromRGB
local V2, V3 = Vector2.new, Vector3.new
local S, O = UDim2.fromScale, UDim2.fromOffset
local NS, NK, CS, CK = NumberSequence.new, NumberSequenceKeypoint.new, ColorSequence.new, ColorSequenceKeypoint.new

local ORDER = { "Vanguard", "Sentinel", "Arc", "Breacher", "Longshot", "Spectre", "Knife" }
local LENGTH = { Vanguard = 4.8, Sentinel = 4.7, Arc = 4.5, Breacher = 4.7, Longshot = 5.8, Spectre = 3.2, Knife = 3.2, Riptide = 3.8, Bulwark = 5.6, Verdict = 2.4, Quill = 5.2, Helix = 4.5, Havoc = 4.6 }
local STATS = {
	{ "dmg", "Damage", "ff3f7f", "ff9ac0" }, { "rpm", "Fire rate", "ff3fd2", "ffb8ef" }, { "rng", "Range", "16c8ff", "c8fdff" },
	{ "mag", "Magazine", "8b5cff", "dcc8ff" }, { "rel", "Reload", "3a6dff", "cfdcff" }, { "mob", "Mobility", "ffb02e", "fff3c4" },
}

local function nice(n)
	local code, rest = string.match(n or "", "^(%S+)%s+(.+)$")
	if not code then
		return n
	end
	return code .. " " .. (string.gsub(string.lower(rest), "(%a)([%w']*)", function(a, b)
		return string.upper(a) .. b
	end))
end
local function cfg(id)
	return (Config.Weapons and Config.Weapons[id]) or {}
end
local function raw(k, w)
	if k == "dmg" then
		return w.Damage
	elseif k == "rpm" then
		return w.RPM
	elseif k == "rng" then
		return w.MaxRange
	elseif k == "mag" then
		return if w.Energy then nil else w.MagazineSize
	elseif k == "rel" then
		return w.ReloadTime
	end
	return w.SpeedMultiplier
end
local function pct(k, w)
	local v = raw(k, w)
	if k == "mag" and w.Energy then
		return 1
	end
	if v == nil then
		return 0
	end
	if k == "dmg" then
		return v / 95
	elseif k == "rpm" then
		return v / 1170
	elseif k == "rng" then
		return v / 1200
	elseif k == "mag" then
		return v / 43
	elseif k == "rel" then
		return math.clamp((3.4 - v) / 2.5, 0, 1)
	end
	return math.clamp((v - 0.85) / 0.3, 0, 1)
end
local function fmt(k, v, w)
	if k == "mag" and w.Energy then
		return "Energy"
	end
	if v == nil then
		return "—"
	end
	if k == "rel" then
		local s = string.format("%.2f", v):gsub("0$", "")
		return s .. "s"
	elseif k == "mob" then
		return string.format("%.2f×", v)
	elseif k == "rng" then
		return string.format("%d st", math.floor(v + 0.5))
	end
	return tostring(math.floor(v + 0.5))
end

local LoadoutScreen = {}
LoadoutScreen.__index = LoadoutScreen

function LoadoutScreen.new(opts)
	local self = setmetatable({}, LoadoutScreen)
	self.Opts = opts
	self.G = opts.G
	self.Weapon = "Vanguard"
	self.Preview = {}
	self.Filter, self.Desc = "all", true
	self.Rows, self.Cards, self.Stats = {}, {}, {}
	self.Shown = false
	self.Stage = Showcase.new({ Origin = V3(0, 9600, 0), Fov = 42 })
	self.Gui, self.Canvas, self.ToScreen = K.screen("VantageLoadout", 13)
	self:_build()
	task.spawn(function()
		local res = Remotes:WaitForChild("SkinResult", 15)
		if res then
			res.OnClientEvent:Connect(function(ok, weaponId, skinId, reason)
				if not self.Shown then
					return
				end
				if ok then
					local s = Skins.Get(weaponId, skinId)
					self.Toast((s and s.Name or tostring(skinId)) .. " equipped")
					self.G.sound("Found")
					if weaponId == self.Weapon then
						self.Stage:Burst()
					end
				else
					self.Toast("Could not equip: " .. tostring(reason))
					self.G.sound("Deny")
				end
				self:_refresh()
			end)
		end
	end)
	if RunService:IsStudio() then
		-- Studio test hook: DevLoadoutSkin = "Weapon/SkinId"
		player:GetAttributeChangedSignal("DevLoadoutSkin"):Connect(function()
			local w, s = string.match(tostring(player:GetAttribute("DevLoadoutSkin")), "^(%w+)/(%w+)$")
			if self.Shown and w then
				self:SelectWeapon(w)
				self:SelectSkin(s)
			end
		end)
	end
	player.AttributeChanged:Connect(function(name)
		if self.Shown and string.sub(name, 1, 5) == "Skin_" then
			self:_refresh()
		end
	end)
	return self
end

-- ─── build ───────────────────────────────────────────────────────────────────────────────
function LoadoutScreen:_build()
	local G, cv = self.G, self.Canvas
	K.header(G, cv, {
		Title = "Loadout", Sub = "Weapons & skins", Active = "Loadout",
		OnBack = function() self.Opts.OnBack() end,
		OnTab = function(n) self.Opts.OnTab(n) end,
		OnStore = function() if self.Opts.OnStore then self.Opts.OnStore() end end,
	})
	self.Toast = K.toast(G, cv)

	-- arsenal
	local list = G.new("Frame", { Name = "Arsenal", BackgroundTransparency = 1, Position = O(90, 140), Size = O(400, 760), ZIndex = 5 }, cv)
	self.ArsenalFrame = list
	G.text(list, { Text = "ARSENAL · 7", Position = O(4, 0), Size = O(300, 22), X = Enum.TextXAlignment.Left, TextSize = 16, Font = G.F.Bold, Stroke = 0, ZIndex = 6 })
	for i, id in ORDER do
		self.Rows[id] = self:_row(list, id, i)
	end

	-- title
	local title = G.new("Frame", { Name = "Title", BackgroundTransparency = 1, Position = UDim2.new(0.5, -520, 0, 136), Size = O(800, 150), ZIndex = 5 }, cv)
	self.TitleFrame = title
	local chip = G.glass(title, { Name = "Class", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(200, 32), Radius = UDim.new(1, 0), TopLine = false, EdgeTransparency = 0.2, ZIndex = 6 })
	self.ClassText = G.text(chip, { Text = "", TextSize = 15, Font = G.F.Bold, Stroke = 0, Color = C(200, 253, 255), ZIndex = 7 })
	self.ClassChip = chip
	self.NameText = G.text(title, { Name = "Name", Text = "", Position = O(0, 36), Size = O(800, 74), TextSize = 66, Stroke = 5, ZIndex = 6 })
	local rrow = G.new("Frame", { Name = "SkinRow", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 114), Size = O(10, 34), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 6 }, title)
	G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12) }, rrow)
	local rchip = G.new("Frame", { Name = "Rarity", Size = O(10, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7, LayoutOrder = 1 }, rrow)
	G.corner(rchip, 9)
	G.stroke(rchip, 3, G.C.Ink)
	self.RarityGrad = G.new("UIGradient", { Rotation = 90 }, rchip)
	G.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, rchip)
	self.RarityText = G.text(rchip, { Text = "", Size = O(0, 32), Auto = Enum.AutomaticSize.X, TextSize = 17, Stroke = 3, ZIndex = 8 })
	self.SkinText = G.text(rrow, { Name = "SkinName", Text = "", Size = O(0, 34), Auto = Enum.AutomaticSize.X, TextSize = 30, Stroke = 3, ZIndex = 7, LayoutOrder = 2 })
	self.SkinGrad = G.new("UIGradient", {}, self.SkinText)
	self.PreviewTag = G.text(cv, { Name = "PreviewTag", Text = "PREVIEW", AnchorPoint = V2(1, 0), Position = UDim2.new(0.5, 240, 0, 300), Size = O(140, 30), TextSize = 16, Font = G.F.Bold, Stroke = 0, ZIndex = 6 })
	self.PreviewTag.Visible = false

	-- drag to turn the showcase
	local drag = G.new("TextButton", { Name = "Drag", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.new(0.5, -520, 0, 300), Size = O(800, 440), ZIndex = 2 }, cv)
	local dragging, lastX = false, 0
	drag.MouseButton1Down:Connect(function(x)
		dragging, lastX = true, x
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local x = input.Position.X
			self.Stage:Spin((x - lastX) * 0.012)
			lastX = x
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	local hint = G.text(cv, { Name = "Hint", Text = "DRAG TO ROTATE", Position = UDim2.new(0.5, -520, 0, 744), Size = O(800, 28), TextSize = 19, Font = G.F.Bold, Stroke = 0, Color = C(226, 232, 255), ZIndex = 3 })
	hint.TextTransparency = 0.25

	-- stats
	local sp = K.panel(G, cv, { Name = "Stats", Position = UDim2.new(0.5, -490, 0, 800), Size = O(740, 160), ZIndex = 4 })
	self.StatsPanel = sp
	for i, st in STATS do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local pri = row == 0
		local f = G.new("Frame", { Name = st[1], BackgroundTransparency = 1, Position = O(28 + col * 238, if pri then 18 else 92), Size = O(208, if pri then 60 else 48), ZIndex = 5 }, sp)
		G.text(f, { Text = string.upper(st[2]), Position = O(0, if pri then 8 else 4), Size = O(120, 20), X = Enum.TextXAlignment.Left, TextSize = 15, Font = G.F.Bold, Stroke = 0, Color = G.C.Muted, ZIndex = 6 })
		local val = G.text(f, { Text = "", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = O(110, if pri then 36 else 26), X = Enum.TextXAlignment.Right, TextSize = if pri then 34 else 24, Stroke = 3.6, Color = Color3.fromHex(st[4]), ZIndex = 6 })
		local bh = if pri then 16 else 10
		local track = G.new("Frame", { Name = "Track", Position = O(0, if pri then 42 else 34), Size = UDim2.new(1, 0, 0, bh), BackgroundColor3 = C(5, 6, 13), BackgroundTransparency = 0.35, ClipsDescendants = true, ZIndex = 6 }, f)
		G.corner(track, UDim.new(1, 0))
		local ghost = G.new("Frame", { Name = "Ghost", Size = S(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 7 }, track)
		G.corner(ghost, UDim.new(1, 0))
		local fill = G.new("Frame", { Name = "Fill", Size = S(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 8 }, track)
		G.corner(fill, UDim.new(1, 0))
		G.new("UIGradient", { Color = CS(Color3.fromHex(st[3]), Color3.fromHex(st[4])) }, fill)
		local hi = G.new("Frame", { Name = "Hi", Size = UDim2.new(1, 0, 0.45, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.45, ZIndex = 9 }, fill)
		G.corner(hi, UDim.new(1, 0))
		G.new("UIGradient", { Rotation = 90, Transparency = NS(0.2, 1) }, hi)
		local cap = G.new("Frame", { Name = "Cap", AnchorPoint = V2(1, 0.5), Position = S(1, 0.5), Size = UDim2.new(0, 5, 1, 6), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 10 }, fill)
		G.corner(cap, 3)
		G.glow(cap, { Color = Color3.fromHex(st[3]), Transparency = 0.2, Size = O(36, 36), ZIndex = 9 })
		local shim = G.new("Frame", { Name = "Shim", AnchorPoint = V2(0.5, 0), Position = S(-0.3, 0), Size = S(0.25, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 11 }, track)
		G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.3), NK(1, 1) }) }, shim)
		self.Stats[st[1]] = { Val = val, Color = Color3.fromHex(st[4]), Fill = fill, Ghost = ghost, Shim = shim, From = nil, To = nil, T0 = 0, Pct = 0 }
	end

	-- skins panel
	local rp = K.panel(G, cv, { Name = "Skins", Position = UDim2.new(1, -680, 0, 120), Size = O(640, 920), ZIndex = 4 })
	self.SkinsPanel = rp
	G.text(rp, { Text = "Skins", Position = O(22, 18), Size = O(140, 44), X = Enum.TextXAlignment.Left, TextSize = 36, Stroke = 3.6, ZIndex = 6 })
	self.CountText = G.text(rp, { Text = "", Position = O(130, 26), Size = O(120, 30), X = Enum.TextXAlignment.Left, TextSize = 21, Stroke = 0, Color = G.C.Cyan, ZIndex = 6 })
	local chips = G.new("Frame", { BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -20, 0, 20), Size = O(330, 40), ZIndex = 6 }, rp)
	G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8) }, chips)
	self.Chips = {}
	for i, c in { { "all", "All", 64 }, { "owned", "Owned", 96 }, { "sort", "Rarity ▾", 120 } } do
		local b = G.glass(chips, { Name = c[1], Class = "TextButton", Size = O(c[3], 40), Radius = UDim.new(1, 0), TopLine = false, EdgeTransparency = 0.5, LayoutOrder = i, ZIndex = 7 })
		local t = G.text(b, { Text = c[2], TextSize = 18, Stroke = 0, Color = G.C.Muted, ZIndex = 8 })
		self.Chips[c[1]] = { Btn = b, Text = t }
		G.press(b, function()
			if c[1] == "sort" then
				self.Desc = not self.Desc
				t.Text = if self.Desc then "Rarity ▾" else "Rarity ▴"
			else
				self.Filter = c[1]
			end
			self:_cards(true)
		end, { Hover = 1.06 })
	end
	local track = G.new("Frame", { Position = O(22, 74), Size = O(596, 8), BackgroundColor3 = C(5, 6, 13), BackgroundTransparency = 0.35, ZIndex = 6 }, rp)
	G.corner(track, UDim.new(1, 0))
	self.CollFill = G.new("Frame", { Size = S(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7 }, track)
	G.corner(self.CollFill, UDim.new(1, 0))
	G.new("UIGradient", { Color = CS({ CK(0, C(139, 92, 255)), CK(0.5, C(255, 63, 210)), CK(1, C(255, 196, 80)) }) }, self.CollFill)
	local scroll = G.new("ScrollingFrame", {
		Name = "Grid", Position = O(0, 88), Size = O(640, 640), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
		ScrollBarImageColor3 = G.C.Cyan, CanvasSize = O(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 5,
	}, rp)
	G.new("UIPadding", { PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 30), PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, scroll)
	G.new("UIGridLayout", { CellSize = O(138, 178), CellPadding = O(14, 26), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	self.Scroll = scroll
	-- detail strip
	local strip = G.new("Frame", { Name = "Detail", Position = O(20, 748), Size = O(600, 150), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 6 }, rp)
	G.corner(strip, 18)
	self.StripGrad = G.new("UIGradient", { Transparency = NS(0.55, 0.85) }, strip)
	self.StripStroke = G.stroke(strip, 2, Color3.new(1, 1, 1), 0.3)
	self.DetailName = G.text(strip, { Text = "", Position = O(22, 22), Size = O(330, 32), X = Enum.TextXAlignment.Left, TextSize = 26, Stroke = 3, Scaled = true, MaxSize = 26, ZIndex = 7 })
	self.DetailMeta = G.text(strip, { Text = "", Position = O(22, 58), Size = O(330, 22), X = Enum.TextXAlignment.Left, TextSize = 17, Font = G.F.Bold, Stroke = 0, Color = C(230, 236, 255), ZIndex = 7 })
	G.text(strip, { Text = "[E] Equip     [Esc] Back", Position = O(22, 100), Size = O(330, 22), X = Enum.TextXAlignment.Left, TextSize = 15, Font = G.F.Bold, Stroke = 0, Color = G.C.Muted, ZIndex = 7 })
	self.EquipBtn = G.cta(strip, "deploy", { Name = "Equip", Text = "EQUIP", Width = 230, Height = 82, TextSize = 40, Breathe = true, AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -14, 0.5, -2), ZIndex = 8, OnClick = function() self:Equip() end })
end

function LoadoutScreen:_row(parent, id, i)
	local G = self.G
	local w = cfg(id)
	local b = G.new("TextButton", { Name = id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = O(0, 32 + (i - 1) * 96), Size = O(360, 84), ZIndex = 6 }, parent)
	local plain = G.new("Frame", { Name = "Plain", Size = S(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 6 }, b)
	G.corner(plain, 18)
	local pg = G.new("UIGradient", {}, plain)
	G.stroke(plain, 3, G.C.Ink)
	local sel = G.new("Frame", { Name = "Sel", Size = S(1, 1), ZIndex = 6, Visible = false }, b)
	G.surface(sel, "cyan", { Radius = UDim.new(0, 18), Split = false })
	local ring = G.new("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = O(-5, -5), Size = UDim2.new(1, 10, 1, 10), ZIndex = 6, Visible = false }, b)
	G.corner(ring, 22)
	G.stroke(ring, 3, Color3.new(1, 1, 1))
	local glow = G.glow(b, { Color = G.C.Cyan, Transparency = 1, Size = UDim2.new(1, 120, 1, 90), ZIndex = 5 })
	local arrow = G.new("Frame", { Name = "Arrow", AnchorPoint = V2(0.5, 0.5), Position = O(-22, 42), Size = O(14, 14), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7, Visible = false }, b)
	local vp = G.new("ViewportFrame", { Name = "Thumb", BackgroundTransparency = 1, Size = O(148, 84), ZIndex = 8 }, b)
	G.text(b, { Name = "Name", Text = nice(w.DisplayName or id), Position = O(150, 10), Size = O(200, 26), X = Enum.TextXAlignment.Left, TextSize = 22, Stroke = 3, Scaled = true, MaxSize = 22, ZIndex = 9 })
	G.text(b, { Name = "Class", Text = string.upper(w.Class or ""), Position = O(150, 36), Size = O(200, 16), X = Enum.TextXAlignment.Left, TextSize = 13, Font = G.F.Bold, Stroke = 0, ZIndex = 9 })
	local dot = G.new("Frame", { Name = "Dot", Position = O(150, 60), Size = O(10, 10), ZIndex = 9 }, b)
	G.corner(dot, 3)
	local skin = G.text(b, { Name = "Skin", Text = "", Position = O(166, 55), Size = O(184, 20), X = Enum.TextXAlignment.Left, TextSize = 15, Font = G.F.Bold, Stroke = 0, ZIndex = 9 })
	G.press(b, function()
		self:SelectWeapon(id)
	end, { Hover = 1.03, OnHover = function(on)
		if b:GetAttribute("Sel") then
			return
		end
		G.tween(glow, 0.2, { ImageTransparency = if on then 0.55 else 1 })
	end })
	return { Btn = b, Plain = plain, Grad = pg, Sel = sel, Ring = ring, Glow = glow, Arrow = arrow, Thumb = vp, Dot = dot, Skin = skin, Shown = nil }
end

-- ─── cards ───────────────────────────────────────────────────────────────────────────────
function LoadoutScreen:_card(s, order)
	local G = self.G
	local rc, mid, deep = K.rv(s.Rarity)
	local owned = Skins.Owns(player, self.Weapon, s.Id)
	local b = G.new("TextButton", { Name = s.Id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = O(138, 178), LayoutOrder = order, ZIndex = 6 }, self.Scroll)
	local glow = G.glow(b, { Color = rc, Transparency = 0.45, Size = UDim2.new(1, 80, 1, 80), ZIndex = 5 })
	local face = G.new("CanvasGroup", { Name = "Face", Size = S(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, b)
	G.corner(face, 20)
	local bg = G.new("Frame", { Name = "Bg", Size = S(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 6 }, face)
	local bgGrad = G.new("UIGradient", { Rotation = 90, Color = CS(mid, deep) }, bg)
	local chroma = K.CHROMAS[s.Rarity]
	if chroma then
		-- chromatic rarities: dark iridescent body that slowly turns
		bgGrad.Color = chroma.Bg
		bgGrad.Rotation = 135
	end
	local core = G.new("ImageLabel", { Name = "Core", BackgroundTransparency = 1, Image = G.A.Glow, ImageColor3 = rc, ImageTransparency = if owned then 0.5 else 0.72, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.36), Size = S(1.3, 0.95), ZIndex = 6 }, face)
	local vp = G.new("ViewportFrame", { Name = "View", BackgroundTransparency = 1, Position = S(0, 0.06), Size = S(1, 0.6), ZIndex = 7 }, face)
	-- photographed cutout when the weapon's atlas is uploaded (cheaper + matches the board); else live 3D
	local art = CardArt.get(self.Weapon, s.Id)
	if art then
		vp.Visible = false
		art = G.new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = art.Image, ImageRectOffset = art.Offset, ImageRectSize = art.Size, ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.37), Size = S(1.22, 0.66), Rotation = -20, ImageColor3 = if owned then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), ZIndex = 7 }, face)
	end
	if not owned then
		vp.ImageColor3 = Color3.new(0, 0, 0)
		G.text(face, { Name = "Q", Text = "?", Position = S(0, 0.1), Size = S(1, 0.42), TextSize = 64, Stroke = 6, ZIndex = 9 })
	end
	G.text(face, { Name = "Name", Text = s.Name, Position = UDim2.new(0, 6, 1, -60), Size = UDim2.new(1, -12, 0, 36), TextSize = 15, Stroke = 3, Wrapped = true, Scaled = true, MaxSize = 15, Y = Enum.TextYAlignment.Bottom, ZIndex = 9 })
	local strip = G.new("Frame", { Name = "Strip", AnchorPoint = V2(0, 1), Position = S(0, 1), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = rc, BackgroundTransparency = 0.62, ZIndex = 8 }, face)
	local stripGrad
	if chroma then
		strip.BackgroundColor3 = Color3.new(1, 1, 1)
		strip.BackgroundTransparency = 0.45
		stripGrad = G.new("UIGradient", { Color = chroma.Grad }, strip)
	end
	G.text(strip, { Text = string.upper(s.Rarity), TextSize = 12, Font = G.F.Bold, Stroke = if chroma then 2 else 0, Color = if chroma then Color3.new(1, 1, 1) else rc:Lerp(Color3.new(1, 1, 1), 0.6), ZIndex = 9 })
	local sheen = G.new("Frame", { Name = "Sheen", AnchorPoint = V2(0.5, 0.5), Position = S(-0.6, 0.5), Size = S(0.45, 1.6), Rotation = 20, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 12 }, face)
	G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.45), NK(1, 1) }) }, sheen)
	local embers = {}
	if s.Rarity == "Mythic" then
		for k = 1, 3 do
			local e = G.new("Frame", { Name = "Ember", AnchorPoint = V2(0.5, 0.5), Position = S(0.3 + k * 0.15, 0.8), Size = O(5, 5), BackgroundColor3 = C(255, 170, 60), BackgroundTransparency = 1, ZIndex = 10 }, face)
			G.corner(e, UDim.new(1, 0))
			embers[k] = e
		end
	end
	local stars = {}
	if (K.TIER[s.Rarity] or 0) >= 3 and owned then
		for k, v in { { 0.84, 0.1, 18 }, { 0.12, 0.42, 12 } } do
			local st = G.new("Frame", { Name = "Star", AnchorPoint = V2(0.5, 0.5), Position = S(v[1], v[2]), Size = O(v[3], v[3]), BackgroundTransparency = 1, ZIndex = 11 }, face)
			for _, rot in { 0, 90 } do
				local bar = G.new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, 0, 0.16, 0), Rotation = rot, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 11 }, st)
				G.corner(bar, UDim.new(1, 0))
			end
			G.glow(st, { Color = Color3.new(1, 1, 1), Transparency = 0.3, Size = S(2.4, 2.4), ZIndex = 10 })
			stars[k] = { Frame = st, Base = v[3], Phase = k * 0.47 + order * 0.31 }
		end
	end
	-- selection ring, godly frame, neon rim + wink, equipped tick
	local ring = G.new("Frame", { Name = "SelRing", BackgroundTransparency = 1, Position = O(-7, -7), Size = UDim2.new(1, 14, 1, 14), ZIndex = 14, Visible = false }, b)
	G.corner(ring, 26)
	local rst = G.new("UIStroke", { Thickness = 3.5, Color = Color3.new(1, 1, 1) }, ring)
	local rgrad = G.new("UIGradient", { Color = CS({ CK(0, Color3.new(1, 1, 1)), CK(0.3, rc), CK(0.5, Color3.new(1, 1, 1)), CK(0.8, rc), CK(1, Color3.new(1, 1, 1)) }) }, rst)
	local gframe
	if s.Rarity == "Godly" then
		local gf = G.new("Frame", { Name = "Godly", BackgroundTransparency = 1, Position = O(-3, -3), Size = UDim2.new(1, 6, 1, 6), ZIndex = 13 }, b)
		G.corner(gf, 23)
		local gst = G.new("UIStroke", { Thickness = 4, Color = Color3.new(1, 1, 1) }, gf)
		gframe = G.new("UIGradient", { Color = K.CHROMA }, gst)
	end
	local neon = K.neon(G, b, rc, UDim.new(0, 20), (order * 1.37) % 6.6)
	if chroma then
		neon.RimGrad.Color = chroma.Grad
		rgrad.Color = chroma.Grad
	end
	local tick = G.square(b, "Check", 34, { Name = "Tick", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), ZIndex = 16 })
	tick.Visible = false
	local rec = { Btn = b, Skin = s, Glow = glow, View = vp, Sheen = sheen, Ring = ring, RingGrad = rgrad, Godly = gframe, Neon = neon, Tick = tick, Embers = embers, Stars = stars, Owned = owned, Chroma = if chroma then { Def = chroma, Bg = bgGrad, Core = core, Strip = stripGrad, Phase = order * 0.13 } else nil, Art = art }
	G.press(b, function()
		self:SelectSkin(s.Id)
	end, { Hover = 1.05, OnHover = function(on)
		neon.Fast = on
		G.tween(glow, 0.2, { ImageTransparency = if on then 0.05 else (if rec.Selected then 0.1 else 0.45) })
		if on then
			sheen.Position = S(-0.6, 0.5)
			G.tween(sheen, 0.6, { Position = S(1.6, 0.5) }, Enum.EasingStyle.Quad)
		end
	end })
	return rec
end

function LoadoutScreen:_cards(reanimate)
	for _, c in self.Cards do
		c.Btn:Destroy()
	end
	self.Cards = {}
	local list = {}
	for _, s in Skins.List(self.Weapon) do
		if self.Filter ~= "owned" or Skins.Owns(player, self.Weapon, s.Id) then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = K.ORDER[a.Rarity] or 9, K.ORDER[b.Rarity] or 9
		if ra == rb then
			return a.Name < b.Name
		end
		if self.Desc then
			return ra < rb
		end
		return ra > rb
	end)
	for i, s in list do
		self.Cards[s.Id] = self:_card(s, i)
	end
	for k, c in self.Chips do
		if k ~= "sort" then
			c.Text.TextColor3 = if self.Filter == k then Color3.new(1, 1, 1) else self.G.C.Muted
		end
	end
	-- render the models a few per frame so opening never hitches
	local token = {}
	self.CardToken = token
	task.spawn(function()
		for i, s in list do
			if self.CardToken ~= token then
				return
			end
			local c = self.Cards[s.Id]
			if c and c.Btn.Parent and not c.Art then
				local m, size = K.weapon(self.Weapon, s.Id)
				if m then
					K.view(c.View, m, size, { Tilt = 24, Aspect = 138 / (178 * 0.6), Pad = 1.05 })
				end
			end
			if i % 3 == 0 then
				task.wait()
			end
		end
	end)
	if reanimate then
		self.Scroll.CanvasPosition = V2(0, 0)
	end
	self:_refresh()
end

-- ─── state ───────────────────────────────────────────────────────────────────────────────
function LoadoutScreen:_selected()
	local id = self.Preview[self.Weapon] or Skins.ForPlayer(player, self.Weapon)
	return Skins.Get(self.Weapon, id)
end

function LoadoutScreen:_stage()
	local s = self:_selected()
	if not s then
		return
	end
	local m = K.weapon(self.Weapon, s.Id)
	if m then
		self.Stage:SetSubject(m, { Kind = "weapon", Length = LENGTH[self.Weapon] or 4.8 })
	end
	local fx, tint = K.fxFor(s)
	self.Stage:SetTheme(fx, tint, (K.rv(s.Rarity)), K.TIER[s.Rarity] or 0)
end

function LoadoutScreen:_title(animate)
	local G = self.G
	local w = cfg(self.Weapon)
	local s = self:_selected()
	local rc = (K.rv(s.Rarity))
	self.ClassText.Text = string.upper(w.Class or "")
	self.ClassChip.Size = O(math.max(150, #self.ClassText.Text * 12 + 40), 32)
	self.NameText.Text = nice(w.DisplayName or self.Weapon)
	self.RarityText.Text = string.upper(s.Rarity)
	self.RarityGrad.Color = if K.CHROMAS[s.Rarity] then K.CHROMAS[s.Rarity].Grad else CS({ CK(0, rc:Lerp(Color3.new(1, 1, 1), 0.55)), CK(0.55, rc), CK(1, K.shade(rc, 0.5)) })
	self.RarityGrad.Rotation = if K.CHROMAS[s.Rarity] then 0 else 90
	self.SkinText.Text = s.Name
	self.SkinGrad.Color = CS({ CK(0, rc:Lerp(Color3.new(1, 1, 1), 0.6)), CK(0.55, rc), CK(1, rc:Lerp(Color3.new(1, 1, 1), 0.25)) })
	self.PreviewTag.Visible = not Skins.Owns(player, self.Weapon, s.Id)
	if animate then
		self.TitleFrame.Position = UDim2.new(0.5, -520, 0, 122)
		G.tween(self.TitleFrame, 0.5, { Position = UDim2.new(0.5, -520, 0, 136) }, Enum.EasingStyle.Back)
	end
	-- detail strip + equip button
	local eq = Skins.ForPlayer(player, self.Weapon) == s.Id
	local owned = Skins.Owns(player, self.Weapon, s.Id)
	self.DetailName.Text = s.Name
	self.DetailMeta.Text = s.Rarity .. "  ·  " .. (if not owned then "Locked" elseif eq then "Equipped" else "Owned") .. "  ·  " .. nice(w.DisplayName or self.Weapon)
	self.StripGrad.Color = CS(rc, K.shade(rc, 0.6))
	self.StripStroke.Color = rc
	self.EquipBtn.Label.Text = if not owned then "LOCKED" elseif eq then "EQUIPPED" else "EQUIP"
	G.setDisabled(self.EquipBtn, (not owned) or eq)
end

function LoadoutScreen:_statsTo(animate)
	local w = cfg(self.Weapon)
	local now = os.clock()
	for _, st in STATS do
		local k = st[1]
		local r = self.Stats[k]
		local target = pct(k, w)
		if animate then
			r.Ghost.Size = S(r.Pct, 1)
			r.Ghost.BackgroundTransparency = 0.55
			self.G.tween(r.Ghost, 1.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			r.Shim.Position = S(-0.3, 0)
			task.delay(0.25, function()
				self.G.tween(r.Shim, 0.9, { Position = S(1.3, 0) }, Enum.EasingStyle.Quad)
			end)
		end
		self.G.tween(r.Fill, if animate then 0.9 else 0.01, { Size = S(math.max(target, 0.001), 1) })
		r.Fill.Visible = target > 0
		r.From = if animate then r.Cur else raw(k, w)
		r.To = raw(k, w)
		r.T0 = now
		r.Pct = target
		r.Val.TextColor3 = if r.To == nil and not (k == "mag" and w.Energy) then C(95, 103, 150) else r.Color
		r.W = w
		r.Key = k
	end
end

function LoadoutScreen:_refresh()
	local G = self.G
	-- arsenal rows
	for id, r in self.Rows do
		local s = Skins.Get(id, Skins.ForPlayer(player, id))
		local rc = (K.rv(s and s.Rarity or "Standard"))
		local on = id == self.Weapon
		r.Btn:SetAttribute("Sel", on or nil)
		r.Sel.Visible, r.Ring.Visible, r.Arrow.Visible = on, on, on
		r.Plain.Visible = not on
		r.Grad.Color = CS({ CK(0, rc:Lerp(C(20, 24, 70), 0.7)), CK(0.45, C(20, 24, 70)), CK(1, C(10, 12, 34)) })
		r.Glow.ImageTransparency = if on then 0.3 else 1
		r.Dot.BackgroundColor3 = if on then Color3.new(1, 1, 1) else rc
		r.Skin.Text = s and s.Name or ""
		if s and r.Shown ~= s.Id then
			r.Shown = s.Id
			local art = CardArt.get(id, s.Id)
			if art then
				r.Thumb.Visible = false
				r.ArtImg = r.ArtImg or G.new("ImageLabel", { Name = "ThumbArt", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = O(148, 84), ZIndex = 8 }, r.Thumb.Parent)
				r.ArtImg.Image, r.ArtImg.ImageRectOffset, r.ArtImg.ImageRectSize = art.Image, art.Offset, art.Size
			else
				local m, size = K.weapon(id, s.Id)
				if m then
					K.view(r.Thumb, m, size, { Aspect = 148 / 84, Pad = 1.12 })
				end
			end
		end
	end
	-- cards
	local sel = self:_selected()
	local eq = Skins.ForPlayer(player, self.Weapon)
	local owned, total = 0, 0
	for _, s in Skins.List(self.Weapon) do
		total += 1
		if Skins.Owns(player, self.Weapon, s.Id) then
			owned += 1
		end
	end
	self.CountText.Text = owned .. " / " .. total
	G.tween(self.CollFill, 0.8, { Size = S(owned / math.max(total, 1), 1) })
	for id, c in self.Cards do
		local on = sel and sel.Id == id
		c.Selected = on
		c.Ring.Visible = on
		c.Neon.Frame.Rim.Visible = true
		c.Glow.ImageTransparency = if on then 0.1 else 0.45
		local wasEq = c.Tick.Visible
		c.Tick.Visible = id == eq
		if c.Tick.Visible and not wasEq then
			local sc = c.Tick:FindFirstChildOfClass("UIScale")
			if sc then
				sc.Scale = 0.2
				G.tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	end
	self:_title(false)
end

function LoadoutScreen:SelectWeapon(id)
	if id == self.Weapon and self.Cards and next(self.Cards) then
		return
	end
	self.Weapon = id
	self:_cards(true)
	self:_stage()
	self:_title(true)
	self:_statsTo(true)
end

function LoadoutScreen:SelectSkin(id)
	local cur = self:_selected()
	if cur and cur.Id == id then
		return
	end
	self.Preview[self.Weapon] = id
	self:_stage()
	self:_refresh()
	self:_title(true)
end

function LoadoutScreen:Equip()
	local s = self:_selected()
	if not s then
		return
	end
	if not Skins.Owns(player, self.Weapon, s.Id) or Skins.ForPlayer(player, self.Weapon) == s.Id then
		self.G.sound("Deny")
		return
	end
	local ev = Remotes:FindFirstChild("SkinEquip")
	if ev then
		ev:FireServer(self.Weapon, s.Id)
	end
end

-- ─── per frame ───────────────────────────────────────────────────────────────────────────
function LoadoutScreen:_step(dt)
	if self.Opts.IsActive and not self.Opts.IsActive() then
		return
	end
	local t = os.clock()
	UserInputService.MouseIconEnabled = true
	local fx, fy = self.ToScreen(840, 470)
	self.Stage:SetFocus(fx, fy)
	K.stepNeon(t)
	for _, c in self.Cards do
		if c.Ring.Visible then
			c.RingGrad.Rotation = (t * 160) % 360
		end
		if c.Godly then
			c.Godly.Rotation = (t * 110) % 360
		end
		local ch = c.Chroma
		if ch then
			local col = K.chromaColor(ch.Def, t, ch.Phase)
			c.Glow.ImageColor3 = col
			ch.Core.ImageColor3 = col
			ch.Bg.Rotation = (135 + t * 24) % 360
			c.Neon.RimGrad.Rotation = (t * 90) % 360
		end
		for _, st in c.Stars do
			local ph = (t * 0.55 + st.Phase) % 1
			local s = math.max(0, math.sin(ph * math.pi * 2)) ^ 3
			st.Frame.Size = O(st.Base * (0.15 + s), st.Base * (0.15 + s))
			st.Frame.Rotation = ph * 90
		end
		for k, e in c.Embers do
			local ph = ((t * 0.38) + k * 0.33) % 1
			e.Position = S(0.25 + k * 0.17 + math.sin(ph * 6) * 0.03, 0.82 - ph * 0.6)
			e.BackgroundTransparency = 0.1 + ph * 0.9
		end
	end
	-- stat numbers count toward their targets
	for _, r in self.Stats do
		if r.W then
			local k = math.min(1, (t - r.T0) / 0.8)
			local e = 1 - (1 - k) ^ 3
			local v = r.To
			if r.From ~= nil and r.To ~= nil then
				v = r.From + (r.To - r.From) * e
			end
			r.Cur = v
			r.Val.Text = fmt(r.Key, v, r.W)
		end
	end
end

function LoadoutScreen:IsShown()
	return self.Shown
end

function LoadoutScreen:Show()
	if self.Shown then
		return
	end
	self.Shown = true
	self.Preview = {}
	self.Gui.Enabled = true
	self.Stage:Open()
	self.Weapon = self.Weapon or "Vanguard"
	self.Cards = {}
	self:_cards(true)
	self:_stage()
	self:_title(true)
	self:_statsTo(false)
	-- entrance
	local G = self.G
	local function slide(f, from, to, d)
		f.Position = from
		task.delay(d or 0, function()
			G.tween(f, 0.6, { Position = to }, Enum.EasingStyle.Quint)
		end)
	end
	slide(self.ArsenalFrame, O(20, 140), O(90, 140), 0.05)
	slide(self.SkinsPanel, UDim2.new(1, -600, 0, 120), UDim2.new(1, -680, 0, 120), 0.1)
	slide(self.StatsPanel, UDim2.new(0.5, -490, 0, 860), UDim2.new(0.5, -490, 0, 800), 0.18)
	self.Conn = RunService.RenderStepped:Connect(function(dt)
		self:_step(dt)
	end)
end

function LoadoutScreen:Hide()
	if not self.Shown then
		return
	end
	self.Shown = false
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
	self.CardToken = nil
	self.Gui.Enabled = false
	self.Stage:Close()
	for _, c in self.Cards do
		c.Btn:Destroy()
	end
	self.Cards = {}
end

function LoadoutScreen:HandleKey(kc)
	if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Backspace then
		self.Opts.OnBack()
		return true
	elseif kc == Enum.KeyCode.E or kc == Enum.KeyCode.ButtonX then
		self:Equip()
		return true
	end
	return false
end

return LoadoutScreen
