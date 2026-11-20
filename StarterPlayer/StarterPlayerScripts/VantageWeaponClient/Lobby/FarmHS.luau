--!nocheck
--[[
	FarmHS — ICHOR FARM screen (2026-11-19). Lobby tile "Farm" (next to Mastery) -> showScreen(ui.Farm).
	3D: FarmStage (sky island, cauldron, the player's avatar with Mjölnir; launch cutscene).
	Data: player attributes FarmLevel / FarmStored / FarmT / FarmCine, Ichor, REQ. Config: IchorConfig.Well.
	Remote: Remotes.IchorFarm:InvokeServer("Claim" | "Upgrade" | "Seen").
	The full launch cutscene plays on the first open of each day; later opens get the short slam.
	Screen API: Show / Hide (Lobby showScreen / hideScreen).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Cfg = require(Vantage:WaitForChild("Ichor"):WaitForChild("IchorConfig"))
local WELL = Cfg.Well
local Stage = require(script.Parent:WaitForChild("FarmStage"))
local player = Players.LocalPlayer

local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local GOLD = RGB(255, 196, 70)
local GOLD_GRAD = CS({ CK(0, RGB(255, 250, 226)), CK(0.5, RGB(255, 206, 110)), CK(1, RGB(255, 140, 40)) })
local BLOOM = "rbxassetid://103142630740394"
local RAYS = "rbxassetid://113538852110620"
local REQ_ICON = "rbxassetid://115805213028426"
local ICON, DROP = Cfg.Icon, Cfg.Drop

local function num(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function rate(L) return WELL.Rate[L] or WELL.Rate[#WELL.Rate] end
local function capH(L) return WELL.Cap[L] or WELL.Cap[#WELL.Cap] end
local function hm(sec)
	sec = math.max(0, math.floor(sec))
	local h, m = sec // 3600, (sec % 3600) // 60
	if h > 0 then return string.format("%dH %02dM", h, m) end
	return string.format("%dM %02dS", m, sec % 60)
end

local Farm = {}
Farm.__index = Farm

function Farm.new(env)
	local self = setmetatable({ Env = env, HS = env.HS, Shown = false }, Farm)
	self.Stage = Stage.new()
	self:_build()
	return self
end

------------------------------------------------------------------ art kit (MasteryHS / SeasonPassHS2 atlases)
local function id(n) return "rbxassetid://" .. n end
local ATLAS = { [0] = id(104850711810300), id(84706372895889), id(136561818438659) }
local BANDS = id(132171274146535)
local PGLOW = id(104786452938879)
local STAR = id(107113949398119)
local A = {
	back = { 2, 3, 285, 300, 92 }, claim = { 2, 306, 285, 290, 92 }, close = { 1, 861, 854, 124, 124 },
	face_dark = { 0, 3, 3, 425, 445 }, face_gold = { 0, 431, 3, 425, 445 }, fill = { 2, 3, 380, 160, 64 },
	frame_gold = { 0, 431, 451, 425, 445 }, frame_white = { 1, 431, 3, 425, 445 },
	node_off = { 1, 709, 451, 160, 160 }, node_on = { 1, 3, 854, 160, 160 }, panel = { 1, 3, 451, 400, 400 },
	pill = { 0, 406, 899, 400, 104 }, skip_grey = { 2, 3, 3, 502, 138 }, skip_orange = { 2, 508, 3, 502, 138 },
	strip = { 1, 482, 854, 240, 140 }, track = { 2, 492, 380, 160, 64 },
}
local INK = RGB(10, 10, 30)
local BROWN = RGB(60, 26, 2)
local function skin(obj, key)
	local a = A[key]
	obj.Image = ATLAS[a[1]]
	obj.ImageRectOffset = V2(a[2], a[3])
	obj.ImageRectSize = V2(a[4], a[5])
	return obj
end

function Farm:_label(parent, p)
	local HS = self.HS
	local z = p.ZIndex or 10
	local drop
	if p.Drop ~= false then
		drop = HS.text(parent, { Name = (p.Name or "Label") .. "Drop", Text = p.Text, Font = p.Font or HS.MontX, TextSize = p.TextSize, Color = BLACK, X = p.X, Rich = p.Rich, Fit = p.Fit, Stroke = p.Stroke or 3, StrokeColor = BLACK, AnchorPoint = p.AnchorPoint, Position = (p.Position or UDim2.new()) + O(0, p.DropY or math.max(2, (p.TextSize or 24) * 0.07)), Size = p.Size, ZIndex = z - 1 })
		drop.TextTransparency = 0.35
		local st = drop:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = 0.35 end
	end
	local t = HS.text(parent, { Name = p.Name or "Label", Text = p.Text, Font = p.Font or HS.MontX, TextSize = p.TextSize, Color = p.Color or WHITE, X = p.X, Rich = p.Rich, Fit = p.Fit, Stroke = p.Stroke or 3, StrokeColor = p.StrokeColor or INK, AnchorPoint = p.AnchorPoint, Position = p.Position, Size = p.Size, ZIndex = z })
	if p.Grad then HS.new("UIGradient", { Rotation = p.GradRot or 90, Color = p.Grad }, t) end
	if drop then
		t:GetPropertyChangedSignal("Text"):Connect(function() drop.Text = t.Text end)
		t:GetPropertyChangedSignal("Visible"):Connect(function() drop.Visible = t.Visible end)
	end
	return t, drop
end

function Farm:_body(parent, p)
	local HS = self.HS
	local t = HS.new("TextLabel", { Name = p.Name or "Body", BackgroundTransparency = 1, Text = p.Text or "", FontFace = HS.MontX, TextSize = p.TextSize or 16, TextColor3 = p.Color or RGB(226, 214, 240), TextWrapped = true, RichText = p.Rich or false, TextXAlignment = p.X or LEFT, TextYAlignment = p.Y or Enum.TextYAlignment.Center, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = p.ZIndex or 10 }, parent)
	HS.new("UIStroke", { Thickness = p.Stroke or 1.6, Color = p.StrokeColor or INK, Transparency = 0.15 }, t)
	return t
end

function Farm:_sweep(parent, pos, size, radius, z, strength, period)
	local sw = self.HS.new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = pos, Size = size, ZIndex = z }, parent)
	self.HS.corner(sw, radius)
	local s = strength or 0.35
	local g = self.HS.new("UIGradient", { Rotation = 22, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.38, 1), NK(0.47, 1 - s * 0.55), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.55), NK(0.62, 1), NK(1, 1) }) }, sw)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.6, Period = period })
	return sw
end

function Farm:_btn(parent, p)
	local HS, z = self.HS, p.Z or 14
	local b = HS.new("ImageButton", { Name = p.Name or "Btn", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	skin(b, p.Skin)
	local w, h = p.Size.X.Offset, p.Size.Y.Offset
	local a = A[p.Skin]
	local hr = h / (a[5] * 0.95)
	local inset = math.max(3, a[5] * 0.115 * hr)
	self:_sweep(b, O(inset, inset * 0.9), O(w - inset * 2, (h * 0.95) - inset * 2), UDim.new(0, math.max(2, (p.Radius or a[5] * 0.17) * hr - inset * 0.6)), z, p.Sweep or 0.4, p.Period)
	HS.press(b, p.OnClick, { Hover = p.Hover or 1.04, Press = 0.95, Sound = p.Sound })
	return b
end

function Farm:_strip(parent, name, pos, size, z, tint, scale)
	local s = self.HS.new("ImageLabel", { Name = name, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(40, 40, 200, 100), SliceScale = scale or 0.5, Position = pos, Size = size, ZIndex = z, ImageColor3 = tint or WHITE }, parent)
	skin(s, "strip")
	return s
end

function Farm:_bar(parent, pos, size, z, grad)
	local HS = self.HS
	local tr = HS.new("ImageLabel", { Name = "Bar", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = size.Y.Offset / 70, Position = pos, Size = size, ZIndex = z }, parent)
	skin(tr, "track")
	local inset = math.max(2, size.Y.Offset * 0.09)
	local fill = HS.new("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = size.Y.Offset / 80, Position = O(inset, inset), Size = O(0, size.Y.Offset - inset * 2), ZIndex = z + 1 }, tr)
	skin(fill, "fill")
	HS.new("UIGradient", { Color = grad }, fill)
	self:_sweep(fill, O(2, 1), UDim2.new(1, -4, 0.5, 0), UDim.new(0.5, 0), z + 1, 0.5, 2.4)
	local function set(f)
		f = math.clamp(f, 0, 1)
		fill.Visible = f > 0.005
		fill.Size = O(math.max(size.Y.Offset, (size.X.Offset - inset * 2) * f), size.Y.Offset - inset * 2)
	end
	return tr, set
end

function Farm:_embers(holder, n, c1, c2, sz, z)
	for _ = 1, n do
		local k = 0.6 + math.random() * 0.8
		local f = self.HS.new("Frame", { Name = "Ember", BackgroundColor3 = c1:Lerp(c2, math.random()), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz * k, sz * k), ZIndex = z }, holder)
		self.HS.corner(f, UDim.new(0.5, 0))
		table.insert(self.EmberList, { F = f, X = math.random(), Y = math.random(), V = 0.04 + math.random() * 0.08, Sway = math.random() * 6.28 })
	end
end

function Farm:_twinkles(holder, n, color, sz, z)
	for _ = 1, n do
		local st = self.HS.new("ImageLabel", { Name = "Twinkle", BackgroundTransparency = 1, Image = STAR, ImageColor3 = color, AnchorPoint = V2(0.5, 0.5), Position = S(math.random(), math.random()), Size = O(0, 0), ZIndex = z }, holder)
		table.insert(self.Twinkles, { I = st, Sz = sz * (0.7 + math.random() * 0.6), P = math.random() * 10, Spd = 1.1 + math.random() * 1.5 })
	end
end

------------------------------------------------------------------ build
function Farm:_build()
	local HS = self.HS
	local new = HS.new
	self.Sweeps, self.EmberList, self.Twinkles, self.Nebula = {}, {}, {}, {}
	local gui = new("ScreenGui", { Name = "VantageFarm", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 30, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Global }, player:WaitForChild("PlayerGui"))
	self.Gui = gui
	local canvas = new("CanvasGroup", { Name = "Canvas", BackgroundTransparency = 1, Size = S(1, 1), GroupTransparency = 1 }, gui)
	self.Canvas = canvas
	local wash = new("Frame", { Name = "WashR", BackgroundColor3 = RGB(8, 4, 14), BorderSizePixel = 0, AnchorPoint = V2(1, 0), Position = S(1, 0), Size = S(0.45, 1), ZIndex = 1 }, canvas)
	new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.55), NK(1, 0.25) }) }, wash)
	local washT = new("Frame", { Name = "WashT", BackgroundColor3 = RGB(8, 4, 14), BorderSizePixel = 0, Size = S(1, 0.22), ZIndex = 1 }, canvas)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.3), NK(1, 1) }) }, washT)
	local fit = new("Frame", { Name = "Fit", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1920, 1080), ZIndex = 2 }, canvas)
	self.Fit = new("UIScale", {}, fit)

	-- title: emblem breaking the corner, gold title with drop, subtitle pill
	self.TitleRays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageColor3 = GOLD, ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = O(112, 98), Size = O(300, 300), ZIndex = 3 }, fit)
	new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 170, 60), ImageTransparency = 0.25, AnchorPoint = V2(0.5, 0.5), Position = O(112, 98), Size = O(260, 230), ZIndex = 3 }, fit)
	local eh = new("Frame", { Name = "Emblem", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(112, 96), Size = O(156, 156), ZIndex = 4 }, fit)
	new("ImageLabel", { BackgroundTransparency = 1, Image = ICON, ImageColor3 = BLACK, ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Fit, Position = O(5, 9), Size = S(1, 1), ZIndex = 4 }, eh)
	new("ImageLabel", { BackgroundTransparency = 1, Image = ICON, ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = 5 }, eh)
	local sp = new("Frame", { BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.5, 1.4), ZIndex = 6 }, eh)
	self:_twinkles(sp, 7, RGB(255, 236, 170), 26, 6)
	self.Emblem = eh
	self:_label(fit, { Name = "Title", Text = "Ichor Farm", TextSize = 96, Stroke = 6, StrokeColor = RGB(40, 16, 2), Grad = GOLD_GRAD, X = LEFT, Fit = false, Position = O(214, 14), Size = O(700, 112), DropY = 7, ZIndex = 7 })
	local shine = HS.text(fit, { Name = "TitleShine", Text = "Ichor Farm", Font = HS.MontX, TextSize = 96, Color = WHITE, X = LEFT, Fit = false, Position = O(214, 14), Size = O(700, 112), ZIndex = 8 })
	table.insert(self.Sweeps, { G = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 0.55), NK(0.5, 0.25), NK(0.52, 0.55), NK(0.58, 1), NK(1, 1) }) }, shine), P = 1, Period = 5 })
	local chip = new("ImageLabel", { Name = "SubChip", BackgroundTransparency = 1, Position = O(206, 118), Size = O(430, 52), ZIndex = 6, ImageColor3 = RGB(255, 196, 110) }, fit)
	skin(chip, "pill")
	self:_sweep(chip, O(7, 6), O(416, 36), UDim.new(0.5, 0), 6, 0.3, 4.4)
	self:_label(chip, { Text = "THE CAULDRON OF YGGDRASIL", TextSize = 21, Stroke = 2.2, StrokeColor = BROWN, Position = O(0, -3), Size = S(1, 1), ZIndex = 8 })

	-- currency pills + close (Mastery construction)
	local function pill(name, x, icon, glowCol, iconSize)
		local cur = new("ImageLabel", { Name = name, BackgroundTransparency = 1, Position = O(x, 32), Size = O(232, 70), ZIndex = 6 }, fit)
		skin(cur, "pill")
		self:_sweep(cur, O(9, 8), O(214, 50), UDim.new(0.5, 0), 6, 0.35)
		new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = glowCol, ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = O(18, 32), Size = O(130, 110), ZIndex = 6 }, cur)
		new("ImageLabel", { BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(20, 31), Size = O(iconSize, iconSize), ZIndex = 8 }, cur)
		return (self:_label(cur, { Name = "Value", Text = "0", TextSize = 32, Stroke = 2.6, Position = O(64, -4), Size = O(154, 70), ZIndex = 8 }))
	end
	self.IchorText = pill("Ichor", 1344, ICON, RGB(255, 170, 60), 86)
	self.ReqText = pill("Req", 1596, REQ_ICON, RGB(90, 180, 255), 92)
	self:_btn(fit, { Name = "Close", Skin = "close", AnchorPoint = V2(0.5, 0.5), Position = O(1870, 66), Size = O(78, 78), Z = 8, Hover = 1.08, Sound = "Click", OnClick = function()
		if self.Env.Close then self.Env.Close() end
	end })

	-- skip (cutscene only; outside the canvas)
	local skip = new("ImageButton", { Name = "Skip", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = V2(1, 1), Position = UDim2.new(1, -36, 1, -36), Size = O(220, 62), ZIndex = 20, Visible = false }, gui)
	skin(skip, "skip_grey")
	self:_label(skip, { Text = "SKIP  >>", TextSize = 26, Stroke = 2.4, Position = O(0, -3), Size = S(1, 1), ZIndex = 22 })
	HS.press(skip, function() HS.sound("Click"); self.Stage:Skip() end)
	self.SkipB = skip

	self:_panel(fit)
	self:_toast(fit)
end

function Farm:_panel(fit)
	local HS = self.HS
	local new = HS.new
	local PX, PY, PW, PH = 1356, 150, 520, 808
	local pos, size = O(PX, PY), O(PW, PH)
	new("ImageLabel", { Name = "PanelGlow", BackgroundTransparency = 1, Image = PGLOW, ImageColor3 = RGB(255, 150, 50), ImageTransparency = 0.25, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 1, Position = pos - O(70, 70), Size = size + O(140, 140), ZIndex = 3 }, fit)
	local p = new("Frame", { Name = "Panel", BackgroundTransparency = 1, Position = pos, Size = size, ZIndex = 4 }, fit)
	local inner = new("Frame", { Name = "Interior", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 4, ClipsDescendants = true }, p)
	HS.corner(inner, 26)
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(78, 36, 30)), CK(0.45, RGB(44, 20, 40)), CK(1, RGB(20, 10, 28)) }) }, inner)
	local bands = new("ImageLabel", { Name = "Bands", BackgroundTransparency = 1, Image = BANDS, ImageColor3 = RGB(255, 200, 140), ImageTransparency = 0.35, Size = S(1, 1), ZIndex = 4 }, inner)
	self.Bands = bands
	table.insert(self.Nebula, { I = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 140, 40), ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = S(0.3, 0.18), Size = S(1.1, 0.5), ZIndex = 4 }, inner), Base = S(0.3, 0.18) })
	table.insert(self.Nebula, { I = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(200, 70, 160), ImageTransparency = 0.75, AnchorPoint = V2(0.5, 0.5), Position = S(0.8, 0.7), Size = S(0.9, 0.6), ZIndex = 4 }, inner), Base = S(0.8, 0.7) })
	local vig = new("Frame", { Name = "Vignette", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 4 }, inner)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.6), NK(0.12, 1), NK(0.72, 1), NK(1, 0.3) }) }, vig)
	local pm = new("Frame", { Name = "Motes", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 5 }, inner)
	self:_embers(pm, 26, RGB(255, 200, 90), RGB(255, 120, 40), 5, 5)
	self:_twinkles(pm, 10, RGB(255, 236, 190), 18, 5)
	local rim = new("ImageLabel", { Name = "Rim", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.3, Size = S(1, 1), ZIndex = 30 }, p)
	skin(rim, "panel")
	self.RimG = new("UIGradient", { Rotation = 35, Color = CS({ CK(0, RGB(255, 240, 180)), CK(0.35, RGB(255, 170, 60)), CK(0.7, RGB(255, 110, 70)), CK(1, RGB(255, 240, 180)) }) }, rim)

	-- header: title + level medallion
	self:_label(p, { Text = "Ichor Well", TextSize = 50, Stroke = 4, StrokeColor = RGB(40, 16, 2), Grad = GOLD_GRAD, X = LEFT, Fit = false, Position = O(34, 22), Size = O(320, 60), ZIndex = 12 })
	self:_body(p, { Text = "Mjölnir's lightning brews Ichor in the cauldron, even while you're offline.", TextSize = 15, Color = RGB(236, 210, 190), Position = O(36, 82), Size = O(330, 40), ZIndex = 12 })
	local md = new("Frame", { Name = "Medal", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(436, 70), Size = O(104, 108), ZIndex = 12 }, p)
	new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 170, 60), ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(2, 1.8), ZIndex = 11 }, md)
	local face = new("ImageLabel", { BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 12 }, md)
	skin(face, "face_gold")
	local frame = new("ImageLabel", { BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 13 }, md)
	skin(frame, "frame_gold")
	self:_label(md, { Text = "LEVEL", TextSize = 14, Stroke = 1.8, StrokeColor = BROWN, Position = O(0, 18), Size = O(104, 18), ZIndex = 15, Drop = false })
	self.LevelText = self:_label(md, { Text = "1", TextSize = 50, Stroke = 3, StrokeColor = BROWN, Position = O(0, 32), Size = O(104, 60), ZIndex = 15 })
	self.Medal = md
	-- level nodes
	self.Pips = {}
	for i = 1, #WELL.Rate do
		local n = new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(48 + (i - 1) * 47, 146), Size = O(34, 34), ZIndex = 12 }, p)
		skin(n, "node_off")
		self.Pips[i] = n
	end

	-- storage strip
	local st = self:_strip(p, "Storage", O(24, 176), O(472, 186), 10, RGB(255, 214, 160), 0.45)
	new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 170, 60), ImageTransparency = 0.2, AnchorPoint = V2(0.5, 0.5), Position = O(76, 74), Size = O(170, 150), ZIndex = 11 }, st)
	self.Drop = new("ImageLabel", { BackgroundTransparency = 1, Image = DROP, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(76, 72), Size = O(100, 100), ZIndex = 12 }, st)
	self:_body(st, { Text = "STORED IN THE CAULDRON", TextSize = 14, Color = RGB(255, 226, 190), Position = O(138, 22), Size = O(320, 18), ZIndex = 12 })
	self.StoredText = self:_label(st, { Text = "0", TextSize = 66, Stroke = 4, StrokeColor = RGB(50, 20, 0), Grad = GOLD_GRAD, X = LEFT, Fit = false, Position = O(134, 36), Size = O(320, 72), ZIndex = 12 })
	self.CapText = self:_body(st, { Text = "/ 0", TextSize = 18, Color = RGB(236, 216, 200), Position = O(140, 104), Size = O(320, 22), ZIndex = 12 })
	local _, setBar = self:_bar(st, O(22, 138), O(428, 28), 12, CS({ CK(0, RGB(255, 140, 30)), CK(0.6, RGB(255, 206, 90)), CK(1, RGB(255, 246, 200)) }))
	self.SetBar = setBar
	self.PctText = self:_label(st, { Text = "0%", TextSize = 17, Stroke = 2, X = RIGHT, Fit = false, Position = O(22, 138), Size = O(416, 28), ZIndex = 15, Drop = false })

	-- stat strips
	local function stat(x, cap, col)
		local s = self:_strip(p, "Stat", O(x, 374), O(230, 94), 10, col, 0.45)
		local v = self:_label(s, { Text = "-", TextSize = 34, Stroke = 2.6, X = LEFT, Fit = false, Position = O(22, 12), Size = O(200, 42), ZIndex = 12 })
		self:_body(s, { Text = cap, TextSize = 14, Color = RGB(230, 220, 240), Position = O(23, 56), Size = O(200, 18), ZIndex = 12 })
		return v
	end
	self.RateText = stat(24, "ICHOR PER HOUR", RGB(255, 210, 150))
	self.FullText = stat(266, "UNTIL FULL", RGB(210, 190, 255))

	-- claim (big glossy orange)
	new("ImageLabel", { Name = "ClaimGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 160, 40), ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = O(260, 540), Size = O(620, 220), ZIndex = 9 }, p)
	local claim = self:_btn(p, { Name = "Claim", Skin = "skip_orange", Position = O(24, 482), Size = O(472, 128), Z = 12, Sweep = 0.55, Period = 2.6, OnClick = function() self:_claim() end })
	self.ClaimText = self:_label(claim, { Text = "CLAIM", TextSize = 52, Stroke = 4, StrokeColor = BROWN, Fit = false, Position = O(0, 6), Size = O(472, 64), ZIndex = 16 })
	self.ClaimSub = self:_label(claim, { Text = "", TextSize = 22, Stroke = 2.4, StrokeColor = BROWN, Fit = false, Position = O(0, 66), Size = O(472, 30), ZIndex = 16 })
	self.ClaimB = claim

	-- upgrade
	local up = self:_strip(p, "Upgrade", O(24, 626), O(472, 156), 10, RGB(160, 200, 255), 0.45)
	self:_label(up, { Text = "UPGRADE THE WELL", TextSize = 22, Stroke = 2.2, Color = RGB(200, 230, 255), X = LEFT, Fit = false, Position = O(22, 12), Size = O(300, 28), ZIndex = 12, Drop = false })
	self.UpRate = self:_body(up, { Text = "", TextSize = 18, Rich = true, Position = O(22, 42), Size = O(230, 24), ZIndex = 12 })
	self.UpCap = self:_body(up, { Text = "", TextSize = 18, Rich = true, Position = O(22, 66), Size = O(230, 24), ZIndex = 12 })
	local ub = self:_btn(up, { Name = "UpgradeBtn", Skin = "skip_grey", Position = O(16, 94), Size = O(440, 52), Z = 12, Sweep = 0.4, OnClick = function() self:_upgrade() end })
	ub.ImageColor3 = RGB(140, 196, 255)
	self.UpLabel = self:_label(ub, { Text = "UPGRADE", TextSize = 26, Stroke = 2.4, StrokeColor = RGB(8, 26, 70), X = LEFT, Fit = false, Position = O(30, -3), Size = O(220, 52), ZIndex = 16 })
	self.UpIcon = new("ImageLabel", { BackgroundTransparency = 1, Image = REQ_ICON, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(300, 24), Size = O(50, 50), ZIndex = 16 }, ub)
	self.UpCost = self:_label(ub, { Text = "0", TextSize = 28, Stroke = 2.4, StrokeColor = RGB(8, 26, 70), X = LEFT, Fit = false, Position = O(330, -3), Size = O(110, 52), ZIndex = 16 })
	self.UpB = ub
	-- next-level preview, right side of the upgrade strip
	self.UpNext = self:_label(up, { Text = "", TextSize = 18, Stroke = 2, Color = RGB(160, 230, 255), X = RIGHT, Fit = false, Position = O(250, 50), Size = O(200, 30), ZIndex = 12, Drop = false })
	self.Note = self:_body(p, { Text = "", TextSize = 15, Color = RGB(255, 150, 150), X = Enum.TextXAlignment.Center, Position = O(24, 776), Size = O(472, 22), ZIndex = 12 })
	self.Panel = p
end

function Farm:_toast(fit)
	local HS = self.HS
	local t = HS.new("Frame", { Name = "Toast", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(660, 330), Size = O(620, 160), Visible = false, ZIndex = 40 }, fit)
	HS.new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageColor3 = GOLD, ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = O(120, 80), Size = O(360, 360), ZIndex = 40 }, t)
	HS.new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 160, 40), ImageTransparency = 0.2, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(760, 300), ZIndex = 40 }, t)
	HS.new("ImageLabel", { BackgroundTransparency = 1, Image = DROP, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(120, 80), Size = O(130, 130), ZIndex = 41 }, t)
	self.ToastText = self:_label(t, { Text = "+0", TextSize = 104, Stroke = 6, StrokeColor = RGB(50, 20, 0), Grad = GOLD_GRAD, X = LEFT, Fit = false, Position = O(200, 4), Size = O(420, 120), ZIndex = 42 })
	self:_label(t, { Text = "ICHOR CLAIMED", TextSize = 26, Stroke = 2.4, StrokeColor = BROWN, X = LEFT, Fit = false, Position = O(206, 114), Size = O(400, 34), ZIndex = 42 })
	self.Toast = t
	self.ToastRays = t:FindFirstChildOfClass("ImageLabel")
	self.ToastScale = HS.new("UIScale", {}, t)
end

------------------------------------------------------------------ data
function Farm:_well()
	local L = tonumber(player:GetAttribute("FarmLevel")) or 1
	local S0 = tonumber(player:GetAttribute("FarmStored")) or 0
	local T0 = tonumber(player:GetAttribute("FarmT")) or Workspace:GetServerTimeNow()
	local r, cap = rate(L), rate(L) * capH(L)
	local now = Workspace:GetServerTimeNow()
	local stored = math.min(cap, S0 + r * math.max(0, now - T0) / 3600)
	return L, stored, cap, r
end

function Farm:_render()
	local L, stored, cap, r = self:_well()
	self.LevelText.Text = tostring(L)
	for i, pip in self.Pips do skin(pip, if i <= L then "node_on" else "node_off") end
	local shown = math.floor(stored)
	self.StoredText.Text = num(shown)
	self.CapText.Text = "/ " .. num(cap) .. " capacity"
	local f = stored / cap
	self.SetBar(f)
	self.PctText.Text = math.floor(f * 100) .. "%"
	self.RateText.Text = "+" .. r
	self.FullText.Text = if f >= 0.999 then "FULL" else hm((cap - stored) / r * 3600)
	self.FullText.TextColor3 = if f >= 0.999 then RGB(255, 210, 90) else WHITE
	self.Stage:SetFill(f)
	local can = shown >= WELL.MinClaim
	self.ClaimB:SetAttribute("Disabled", not can)
	skin(self.ClaimB, if can then "skip_orange" else "skip_grey")
	self.ClaimSub.Text = if can then ("+" .. num(shown) .. " ICHOR") else "BREWING..."
	local cost = WELL.UpgradeCost[L]
	if cost then
		self.UpRate.Text = string.format("RATE  <b>%d</b> <font color=\"#9BE8FF\">→ <b>%d</b></font> /hr", r, rate(L + 1))
		self.UpCap.Text = string.format("STORAGE  <b>%dh</b> <font color=\"#9BE8FF\">→ <b>%dh</b></font>", capH(L), capH(L + 1))
		self.UpNext.Text = "LEVEL " .. (L + 1)
		self.UpLabel.Text = "UPGRADE"
		self.UpCost.Text = num(cost)
		self.UpIcon.Visible, self.UpCost.Visible = true, true
		local req = tonumber(player:GetAttribute("REQ")) or 0
		self.UpCost.TextColor3 = if req >= cost then WHITE else RGB(255, 150, 150)
		self.UpB:SetAttribute("Disabled", false)
	else
		self.UpRate.Text = string.format("RATE  <b>%d</b> /hr", r)
		self.UpCap.Text = string.format("STORAGE  <b>%dh</b>", capH(L))
		self.UpNext.Text = "MAXED"
		self.UpLabel.Text = "MAX LEVEL"
		self.UpIcon.Visible, self.UpCost.Visible = false, false
		self.UpB:SetAttribute("Disabled", true)
	end
	self.IchorText.Text = num(self.ShownIchor or player:GetAttribute("Ichor") or 0)
	self.ReqText.Text = num(player:GetAttribute("REQ") or 0)
end

function Farm:_note(msg)
	self.Note.Text = msg or ""
	local tok = {}
	self.NoteTok = tok
	task.delay(2.6, function() if self.NoteTok == tok then self.Note.Text = "" end end)
end

function Farm:_claim()
	local HS = self.HS
	if self.Busy or not self.Stage:IsSettled() then return end
	local _, stored = self:_well()
	if math.floor(stored) < WELL.MinClaim then HS.sound("Deny"); self:_note("The cauldron is empty. Come back soon.") return end
	self.Busy = true
	HS.sound("Purchase")
	local before = tonumber(player:GetAttribute("Ichor")) or 0
	self.ShownIchor = before
	local ok, res = pcall(function() return Remotes:WaitForChild("IchorFarm"):InvokeServer("Claim") end)
	if not (ok and type(res) == "table" and res.Ok) then
		self.Busy = false
		self.ShownIchor = nil
		HS.sound("Deny")
		self:_note(type(res) == "table" and res.Error or "Couldn't reach the Well. Try again.")
		return
	end
	local amount = res.Amount or 0
	local _, _, cap = self:_well()
	self.Stage:Claim(math.clamp((tonumber(player:GetAttribute("FarmStored")) or 0) / cap, 0, 1))
	-- toast + count-up once the stream reaches the hammer
	task.delay(1.2, function()
		self.Toast.Visible = true
		self.ToastText.Text = "+" .. num(amount)
		self.ToastScale.Scale = 0.4
		HS.tween(self.ToastScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		self.Toast.Position = O(660, 330)
		HS.tween(self.Toast, 2.2, { Position = O(660, 290) })
		local target = tonumber(player:GetAttribute("Ichor")) or (before + amount)
		local s0 = time()
		while time() - s0 < 1.2 do
			local u = (time() - s0) / 1.2
			self.ShownIchor = before + (target - before) * (1 - (1 - u) ^ 3)
			task.wait()
		end
		self.ShownIchor = nil
		task.wait(0.9)
		self.Toast.Visible = false
		self.Busy = false
	end)
end

function Farm:_upgrade()
	local HS = self.HS
	if self.Busy or not self.Stage:IsSettled() then return end
	local L = tonumber(player:GetAttribute("FarmLevel")) or 1
	local cost = WELL.UpgradeCost[L]
	if not cost then HS.sound("Deny") return end
	if (tonumber(player:GetAttribute("REQ")) or 0) < cost then HS.sound("Deny"); self:_note("Not enough REQ for the upgrade.") return end
	self.Busy = true
	local ok, res = pcall(function() return Remotes:WaitForChild("IchorFarm"):InvokeServer("Upgrade") end)
	self.Busy = false
	if not (ok and type(res) == "table" and res.Ok) then
		HS.sound("Deny")
		self:_note(type(res) == "table" and res.Error or "Couldn't reach the Well. Try again.")
		return
	end
	HS.sound("Purchase")
	self.Stage:Upgrade()
end

------------------------------------------------------------------ show / hide
function Farm:_step(dt)
	local t = time()
	local vp = Workspace.CurrentCamera.ViewportSize
	self.Fit.Scale = math.min(vp.X / 1920, vp.Y / 1080)
	self.RimG.Rotation = (35 + t * 30) % 360
	self.TitleRays.Rotation = (t * 10) % 360
	if self.ToastRays then self.ToastRays.Rotation = (t * 40) % 360 end
	self.Drop.Rotation = math.sin(t * 2) * 6
	self.Drop.Position = O(76, 72 + math.sin(t * 1.7) * 4)
	self.Emblem.Rotation = math.sin(t * 0.8) * 4
	self.Emblem.Position = O(112, 96 + math.sin(t * 1.1) * 5)
	self.Medal.Rotation = math.sin(t * 0.9) * 3
	self.Bands.Position = UDim2.new(0, -((t * 14) % 40), 0, 0)
	for _, n in self.Nebula do
		n.I.Position = n.Base + UDim2.fromScale(math.sin(t * 0.3 + n.Base.X.Scale * 5) * 0.04, math.cos(t * 0.25 + n.Base.Y.Scale * 5) * 0.03)
	end
	for _, sw in self.Sweeps do
		local per = sw.Period or 3.6
		local x = ((t + sw.P) % per) / 0.9
		sw.G.Offset = V2(math.clamp(x, 0, 1) * 2 - 1, 0)
	end
	for _, e in self.EmberList do
		local y = 1.05 - ((t * e.V + e.Y) % 1.1)
		e.F.Position = S(e.X + math.sin(t * 1.3 + e.Sway) * 0.02, y)
		e.F.BackgroundTransparency = 0.1 + 0.9 * math.clamp((0.3 - y) / 0.3, 0, 1)
	end
	for _, tw in self.Twinkles do
		local k = math.max(0, math.sin(t * tw.Spd + tw.P)) ^ 4
		tw.I.Size = O(tw.Sz * k, tw.Sz * k)
		tw.I.Rotation = (t * 60 + tw.P * 30) % 360
		if k < 0.02 and math.random() < 0.02 then tw.I.Position = S(math.random(), math.random()) end
	end
	local settled = self.Stage:IsSettled()
	self.SkipB.Visible = not settled
	if settled and self.Canvas.GroupTransparency > 0 and not self.Fading then
		self.Fading = true
		self.Canvas.Visible = true
		self.HS.tween(self.Canvas, 0.45, { GroupTransparency = 0 })
	end
	if t - (self.LastRender or 0) > 0.1 then
		self.LastRender = t
		self:_render()
		local gui = self.Stage.AmountGui
		if gui and not gui:FindFirstChild("V") then
			local v = Instance.new("TextLabel")
			v.Name = "V"; v.BackgroundTransparency = 1; v.Size = UDim2.new(1, 0, 0.7, 0); v.FontFace = self.HS.MontX; v.TextScaled = true
			v.TextColor3 = WHITE; v.Text = ""; v.Parent = gui
			Instance.new("UIGradient", v).Color = GOLD_GRAD
			local st = Instance.new("UIStroke"); st.Thickness = 3; st.Color = RGB(60, 26, 0); st.Parent = v
			local c = Instance.new("TextLabel")
			c.Name = "C"; c.BackgroundTransparency = 1; c.Position = UDim2.fromScale(0, 0.68); c.Size = UDim2.new(1, 0, 0.3, 0); c.FontFace = self.HS.MontX; c.TextScaled = true
			c.TextColor3 = RGB(255, 236, 200); c.Text = "ICHOR"; c.Parent = gui
			local st2 = Instance.new("UIStroke"); st2.Thickness = 2; st2.Color = RGB(60, 26, 0); st2.Parent = c
		end
		if gui and gui:FindFirstChild("V") then
			local _, stored, cap = self:_well()
			gui.V.Text = num(stored)
			gui.C.Text = if stored >= cap - 0.5 then "FULL" else "ICHOR"
			gui.Enabled = settled
		end
	end
end

function Farm:Show()
	if self.Shown then return end
	self.Shown = true
	self.Gui.Enabled = true
	self.Canvas.GroupTransparency = 1
	self.Canvas.Visible = false
	self.Fading = false
	self.Toast.Visible = false
	local today = math.floor(Workspace:GetServerTimeNow() / 86400)
	local full = true -- 2026-11-20: the full Mjölnir cutscene every visit (was: once per UTC day, then landing only); Skip still works
	local _ = today
	if RunService:IsStudio() and player:GetAttribute("FarmForceShort") then full = false end -- Studio test hook: landing only
	local _, stored, cap = self:_well()
	self.Stage:SetFill(stored / cap, true)
	self.Stage:Enter(full)
	if full then
		task.spawn(function() pcall(function() Remotes:WaitForChild("IchorFarm"):InvokeServer("Seen") end) end)
	end
	self.Conn = RunService.RenderStepped:Connect(function(dt) self:_step(dt) end)
end

function Farm:Hide()
	if not self.Shown then return end
	self.Shown = false
	if self.Conn then self.Conn:Disconnect() self.Conn = nil end
	self.Stage:Leave()
	self.Gui.Enabled = false
	self.Busy = false
end

return Farm
