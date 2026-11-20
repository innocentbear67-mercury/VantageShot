--!nocheck
--[[
	MasteryHS - Weapon Mastery modal (2026-11-17). Built on the SeasonPassHS2 kit (same rendered atlas skins,
	panel, light sweeps, embers, twinkles) so it sits at the Season Pass / Shop quality bar.
	Board: design canvas "VantageShot UI v2", Mastery.dc.html.

	Layout (design px 1640 x 960):
	  title + mastery emblem break the top-left corner | Forge Parts / REQ pills + X break the top edge
	  left    scrolling weapon list (WeaponUnlocks order; locked guns say how to get them)
	  centre  spinning gun on rays, level medallion, XP strip, Standard / Variant I / Variant II cards
	  right   Prestige Gold card (prestige backdrop art, gold gun, stars, PRESTIGE) + version details
	          (trait text + stat bars against Standard)
	  bottom  1-50 reward track (drag / wheel / arrows) with a timeline of level nodes
	Data: player attributes Mastery_<weapon> = "level|into|need|prestige|kills", Level, OwnedWeapons,
	ForgeParts, REQ. Remotes: MasteryPrestige (fire), MasteryLevelUp (toast).
	Edit preview: Mount(layer, { HS = HS, Attr = { Level = 6, Mastery_Vanguard = "13|1240|4060|1|512" } }).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local MC = require(Vantage:WaitForChild("Mastery"):WaitForChild("MasteryConfig"))
local Variants = require(Vantage.Mastery:WaitForChild("Variants"))
local Unlocks = require(Vantage:WaitForChild("Weapons"):WaitForChild("WeaponUnlocks"))
local K = require(script.Parent:WaitForChild("ScreenKit"))

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local LEFT, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right

------------------------------------------------------------------ art
local function id(n) return "rbxassetid://" .. n end
local ATLAS = { [0] = id(104850711810300), id(84706372895889), id(136561818438659) }
local BANDS = id(132171274146535)
local A = { -- { atlas, x, y, w, h } (SeasonPassHS2 atlases)
	arrow_l = { 1, 166, 854, 155, 155 }, arrow_r = { 1, 324, 854, 155, 155 }, back = { 2, 3, 285, 300, 92 },
	check = { 1, 406, 451, 300, 240 }, claim = { 2, 306, 285, 290, 92 }, close = { 1, 861, 854, 124, 124 },
	face_dark = { 0, 3, 3, 425, 445 }, face_gold = { 0, 431, 3, 425, 445 }, fill = { 2, 3, 380, 160, 64 },
	frame_gold = { 0, 431, 451, 425, 445 }, frame_white = { 1, 431, 3, 425, 445 },
	line = { 2, 166, 380, 160, 64 }, linetrack = { 2, 329, 380, 160, 64 }, lock = { 0, 859, 451, 160, 196 },
	node_off = { 1, 709, 451, 160, 160 }, node_on = { 1, 3, 854, 160, 160 }, panel = { 1, 3, 451, 400, 400 },
	pill = { 0, 406, 899, 400, 104 }, skip_grey = { 2, 3, 3, 502, 138 }, skip_orange = { 2, 508, 3, 502, 138 },
	strip = { 1, 482, 854, 240, 140 }, track = { 2, 492, 380, 160, 64 },
}
local GLOW = id(104786452938879)
local RAYS = id(113538852110620)
local BLOOM = id(103142630740394)
local STAR = id(107113949398119)
local REQ_ICON = id(115805213028426)
local REQ_ART = { { 1000, id(126929361892136) }, { 2500, id(113707123684396) }, { 5000, id(101892365525049) }, { math.huge, id(96063758555679) } }
-- Mastery art (user's Gemini images, matted): tile emblem, Forge Parts, level medallion, prestige backdrop
local TILE = id(114502105680644)
local FORGE = id(90926834933579)
local MEDAL = id(100022048778683)
local PRESTIGE_BG = id(80080339744742)
local MMASKS = id(127080654076939) -- white silhouettes of tile / medal / forge (256 px each) for clipped sweeps
local MMASK = { Tile = 0, Medal = 256, Forge = 512 }
-- Prestige Gold renders (photo booth + gold grade) and their white masks; 512 x 256 cells
local GOLD_ATLAS, GOLD_MASKS = id(100199878854058), id(95186368975673)
local GOLD_CELL = { Vanguard = { 0, 0 }, Sentinel = { 512, 0 }, Spectre = { 0, 256 }, Breacher = { 512, 256 }, Longshot = { 0, 512 }, Arc = { 512, 512 }, Knife = { 0, 768 } }

------------------------------------------------------------------ geometry / palette
local CW, CH = 1640, 960
local PX, PY, PW, PH = 20, 60, 1600, 880
local LIST_X, LIST_Y, LIST_W, LIST_H, ROW_H, ROW_P = 46, 106, 414, 566, 74, 80
local CEN_X, CEN_W = 476, 656
local RIGHT_X, RIGHT_W = 1150, 444
local TR_X0, TR_X1, TR_Y = 52, 1588, 718
local CARD_W, CARD_H, PITCH = 140, 146, 150
local NODE_Y = 186
local NCARDS = MC.MaxLevel + 1 -- 50 levels + the prestige card
local OFF_MAX = math.max(0, NCARDS * PITCH + 10 - (TR_X1 - TR_X0))

local INK = RGB(10, 10, 30)
local GOLD_GRAD = CS({ CK(0, RGB(255, 250, 226)), CK(0.5, RGB(255, 206, 110)), CK(1, RGB(255, 140, 40)) })
local CYAN_GRAD = CS({ CK(0, RGB(236, 252, 255)), CK(1, RGB(110, 214, 255)) })
local VCOL = { [0] = RGB(120, 160, 255), RGB(60, 226, 255), RGB(236, 96, 255) }
local FINISH_COL = {
	Issue1 = RGB(120, 210, 255), Issue2 = RGB(130, 255, 170), Issue3 = RGB(255, 150, 90), Issue4 = RGB(255, 110, 190),
	Forged = RGB(255, 140, 50), Hardlight = RGB(90, 236, 255), Ascendant = RGB(190, 130, 255), Singularity = RGB(150, 80, 255),
	PrestigeGold = RGB(255, 206, 90),
}
local BOOST_COL = { REQ = RGB(80, 170, 255), ORD = RGB(255, 170, 50), XP = RGB(110, 230, 140) }

local function hsv(col, s, v)
	local h, s0 = col:ToHSV()
	return Color3.fromHSV(h, math.clamp(s0 * s, 0, 1), v)
end
local function num(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function skin(obj, key)
	local a = A[key]
	obj.Image = ATLAS[a[1]]
	obj.ImageRectOffset = V2(a[2], a[3])
	obj.ImageRectSize = V2(a[4], a[5])
	return obj
end
local function legendary(t)
	local d = K.CHROMAS and K.CHROMAS.Legendary
	return if d then K.chromaColor(d, t or 0, 0) else RGB(255, 206, 90)
end

------------------------------------------------------------------ 3D (same framing rules as SeasonPassHS2 / InventoryHS)
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
-- fill: gun length as a fraction of the viewport height (aspect-corrected by the caller)
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
local function fillFor(w, h, k) return (h / w) * (k or 1.12) end
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
-- Prestige Gold: polished gold ramp by the part's own brightness (darks stay deep amber, edges go pale)
local GOLD_RAMP = { RGB(70, 36, 4), RGB(176, 112, 22), RGB(255, 196, 64), RGB(255, 250, 222) }
local function goldify(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local l = math.clamp(0.12 + (0.3 * c.R + 0.59 * c.G + 0.11 * c.B) * 1.75, 0, 0.999) * 3
			local i = math.floor(l) + 1 -- segment 1..3 of the 4-stop ramp
			d.Color = GOLD_RAMP[i]:Lerp(GOLD_RAMP[i + 1], l - (i - 1))
			d.Material, d.Reflectance = Enum.Material.SmoothPlastic, 0
			pcall(function() d.TextureID = "" end)
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
end
local function gunModel(wid, gold)
	local ok, m = pcall(K.weapon, wid)
	if not (ok and m) then return nil end
	if gold then goldify(m) end
	return m
end

------------------------------------------------------------------ object
local M = {}
M.__index = M

function M:_attr(name)
	if self.Env.Attr then return self.Env.Attr[name] end
	return player and player:GetAttribute(name)
end

function M:_data(w)
	local s = self:_attr("Mastery_" .. w)
	local d = { Level = 1, Into = 0, Need = MC.Need(1), Prestige = 0, Kills = 0 }
	if type(s) == "string" then
		local a = string.split(s, "|")
		d.Level = tonumber(a[1]) or 1
		d.Into = tonumber(a[2]) or 0
		d.Need = tonumber(a[3]) or MC.Need(d.Level)
		d.Prestige = tonumber(a[4]) or 0
		d.Kills = tonumber(a[5]) or 0
	end
	return d
end

function M:_owns(w)
	return Unlocks.Owns(w, self:_attr("Level"), self:_attr("OwnedWeapons"))
end

function M:_variantOpen(w, i, d)
	d = d or self:_data(w)
	return i == 0 or d.Prestige > 0 or d.Level >= (MC.VariantLevels[i] or math.huge)
end

function M.new(layer, env)
	local self = setmetatable({
		Env = env, HS = env.HS, Sel = Unlocks.List[1].Id, Ver = 0, Rows = {}, VCards = {}, TrackCards = {},
		Off = 0, Cur = 0, Drag = nil, Sweeps = {}, Embers = {}, Twinkles = {}, Nebula = {}, Pulses = {}, Spin = nil,
	}, M)
	self:_build(layer)
	RunService.RenderStepped:Connect(function(dt)
		if self.Root.Visible then self:_step(dt) end
	end)
	if player and not env.Attr then
		player.AttributeChanged:Connect(function(a)
			if a:sub(1, 8) == "Mastery_" or a:sub(1, 12) == "MasteryBoost" or a == "REQ" or a == "ForgeParts" or a == "Level" or a == "OwnedWeapons" then
				if self.Root.Visible then self:_refresh() else self.Dirty = true end
			end
		end)
		local up = Remotes:FindFirstChild("MasteryLevelUp")
		if up then
			up.OnClientEvent:Connect(function(info) self:_onLevelUp(info) end)
		end
		-- Studio hook: PrestigeFXTest = "Vanguard:2" plays the prestige cinematic
		player:GetAttributeChangedSignal("PrestigeFXTest"):Connect(function()
			local v = player:GetAttribute("PrestigeFXTest")
			if type(v) == "string" and v ~= "" then
				local w, n = v:match("^(%w+):?(%d*)$")
				if w then self:_onLevelUp({ Weapon = w, Prestige = tonumber(n) or 1, Rewards = {} }) end
			end
		end)
	end
	task.defer(function()
		self:_select(self.Sel, true)
	end)
	return self
end

------------------------------------------------------------------ kit
function M:_label(parent, p)
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
	if p.Grad then self.HS.new("UIGradient", { Rotation = p.GradRot or 90, Color = p.Grad }, t) end
	if drop then
		t:GetPropertyChangedSignal("Text"):Connect(function() drop.Text = t.Text end)
		t:GetPropertyChangedSignal("Visible"):Connect(function() drop.Visible = t.Visible end)
	end
	return t, drop
end

-- small wrapped Montserrat copy (no drop)
function M:_body(parent, p)
	local HS = self.HS
	local t = HS.new("TextLabel", { Name = p.Name or "Body", BackgroundTransparency = 1, Text = p.Text or "", FontFace = HS.MontX, TextSize = p.TextSize or 16, TextColor3 = p.Color or RGB(206, 214, 240), TextWrapped = true, RichText = p.Rich or false, TextXAlignment = p.X or LEFT, TextYAlignment = p.Y or Enum.TextYAlignment.Top, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = p.ZIndex or 40 }, parent)
	HS.new("UIStroke", { Thickness = p.Stroke or 1.6, Color = p.StrokeColor or INK, Transparency = 0.15 }, t)
	return t
end

-- light sweep: white rounded frame, gradient band slides across (stays inside the rounded shape)
function M:_sweep(parent, pos, size, radius, z, strength, period)
	local sw = self.HS.new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = pos, Size = size, ZIndex = z }, parent)
	self.HS.corner(sw, radius)
	local s = strength or 0.35
	local g = self.HS.new("UIGradient", { Rotation = 22, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.38, 1), NK(0.47, 1 - s * 0.55), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.55), NK(0.62, 1), NK(1, 1) }) }, sw)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.6, Period = period })
	return sw
end

-- sweep cut to one of the mastery art silhouettes
function M:_maskSweep(parent, key, z, strength, period)
	local m = self.HS.new("ImageLabel", { Name = "Sheen", BackgroundTransparency = 1, Image = MMASKS, ImageRectOffset = V2(MMASK[key], 0), ImageRectSize = V2(256, 256), ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = z }, parent)
	local s = strength or 0.6
	local g = self.HS.new("UIGradient", { Rotation = 25, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.4, 1), NK(0.47, 1 - s * 0.5), NK(0.5, 1 - s), NK(0.53, 1 - s * 0.5), NK(0.6, 1), NK(1, 1) }) }, m)
	table.insert(self.Sweeps, { G = g, P = math.random() * 3.6, Period = period })
	return m
end

function M:_btn(parent, p)
	local HS, z = self.HS, p.Z or 44
	local b = HS.new("ImageButton", { Name = p.Name or "Btn", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	skin(b, p.Skin)
	local w, h = p.Size.X.Offset, p.Size.Y.Offset
	local a = A[p.Skin]
	local hr = h / (a[5] * 0.95)
	local inset = math.max(3, a[5] * 0.115 * hr)
	self:_sweep(b, O(inset, inset * 0.9), O(w - inset * 2, (h * 0.95) - inset * 2), UDim.new(0, math.max(2, (p.Radius or a[5] * 0.17) * hr - inset * 0.6)), z, p.Sweep or 0.4)
	local t
	if p.Text then
		t = self:_label(b, { Name = "Label", Text = p.Text, Font = p.Font, TextSize = p.TextSize or 30, Stroke = p.Stroke or 3, StrokeColor = p.Ink or INK, Position = O(0, -h * 0.04), Size = S(1, 1), ZIndex = z + 2 })
	end
	HS.press(b, p.OnClick, { Hover = p.Hover or 1.05, Press = 0.95, Sound = p.Sound })
	return { B = b, T = t }
end

function M:_embers(holder, n, c1, c2, sz, z)
	for _ = 1, n do
		local k = 0.6 + math.random() * 0.8
		local f = self.HS.new("Frame", { Name = "Ember", BackgroundColor3 = c1:Lerp(c2, math.random()), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz * k, sz * k), ZIndex = z }, holder)
		self.HS.corner(f, UDim.new(0.5, 0))
		table.insert(self.Embers, { F = f, X = math.random(), Y = math.random(), V = 0.05 + math.random() * 0.1, Sway = math.random() * 6.28 })
	end
end

function M:_twinkles(holder, n, color, sz, z)
	for _ = 1, n do
		local st = self.HS.new("ImageLabel", { Name = "Twinkle", BackgroundTransparency = 1, Image = STAR, ImageColor3 = color, AnchorPoint = V2(0.5, 0.5), Position = S(math.random(), math.random()), Size = O(0, 0), ZIndex = z }, holder)
		table.insert(self.Twinkles, { I = st, Sz = sz * (0.7 + math.random() * 0.6), P = math.random() * 10, Spd = 1.1 + math.random() * 1.5 })
	end
end

-- 9-slice bevel strip (rows, boxes, details)
function M:_strip(parent, name, pos, size, z, tint, scale)
	local s = self.HS.new("ImageLabel", { Name = name, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(40, 40, 200, 100), SliceScale = scale or 0.5, Position = pos, Size = size, ZIndex = z, ImageColor3 = tint or WHITE }, parent)
	skin(s, "strip")
	return s
end

-- thin XP / progress bar from the track + fill skins
function M:_bar(parent, pos, size, z, grad)
	local HS = self.HS
	local tr = HS.new("ImageLabel", { Name = "Bar", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = size.Y.Offset / 70, Position = pos, Size = size, ZIndex = z }, parent)
	skin(tr, "track")
	local inset = math.max(2, size.Y.Offset * 0.09)
	local fill = HS.new("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = size.Y.Offset / 80, Position = O(inset, inset), Size = O(0, size.Y.Offset - inset * 2), ZIndex = z + 1 }, tr)
	skin(fill, "fill")
	HS.new("UIGradient", { Color = grad or CS(RGB(60, 150, 255), RGB(120, 240, 255)) }, fill)
	local sw = self:_sweep(fill, O(2, 1), UDim2.new(1, -4, 0.5, 0), UDim.new(0.5, 0), z + 1, 0.45)
	local function set(f)
		f = math.clamp(f, 0, 1)
		fill.Visible = f > 0.005
		fill.Size = O(math.max(size.Y.Offset, (size.X.Offset - inset * 2) * f), size.Y.Offset - inset * 2)
	end
	return tr, set, fill, sw
end

------------------------------------------------------------------ panel (SeasonPassHS2 construction, blue-violet)
function M:_panel(fit)
	local HS = self.HS
	local new = HS.new
	local pos, size = O(PX, PY), O(PW, PH)
	new("ImageLabel", { Name = "PanelGlow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(90, 110, 255), ImageTransparency = 0.15, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 1, Position = pos - O(70, 70), Size = size + O(140, 140), ZIndex = 20 }, fit)
	local p = new("Frame", { Name = "Panel", BackgroundTransparency = 1, Position = pos, Size = size, ZIndex = 21 }, fit)
	local inner = new("Frame", { Name = "Interior", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 21 }, p)
	HS.corner(inner, 26)
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(30, 30, 86)), CK(0.5, RGB(22, 18, 64)), CK(1, RGB(14, 10, 42)) }) }, inner)
	local bands = new("ImageLabel", { Name = "Bands", BackgroundTransparency = 1, Image = BANDS, ImageColor3 = RGB(176, 200, 255), Size = S(1, 1), ZIndex = 21 }, inner)
	HS.corner(bands, 26)
	table.insert(self.Nebula, { I = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(70, 90, 255), ImageTransparency = 0.7, AnchorPoint = V2(0.5, 0.5), Position = S(0.42, 0.4), Size = S(0.8, 0.9), ZIndex = 21 }, inner), Base = S(0.42, 0.4), Tr = 0.7 })
	table.insert(self.Nebula, { I = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(170, 70, 255), ImageTransparency = 0.8, AnchorPoint = V2(0.5, 0.5), Position = S(0.82, 0.5), Size = S(0.6, 0.8), ZIndex = 21 }, inner), Base = S(0.82, 0.5), Tr = 0.8 })
	local vig = new("Frame", { Name = "Vignette", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 21 }, inner)
	HS.corner(vig, 26)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.55), NK(0.12, 1), NK(0.72, 1), NK(1, 0.35) }) }, vig)
	self.Bands = bands
	local pm = new("Frame", { Name = "PanelMotes", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(14, 14), Size = UDim2.new(1, -28, 1, -28), ZIndex = 21 }, inner)
	self:_embers(pm, 30, RGB(150, 180, 255), RGB(200, 140, 255), 5, 21)
	self:_twinkles(pm, 12, RGB(206, 220, 255), 18, 21)
	local rim = new("ImageLabel", { Name = "Rim", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.3, Size = S(1, 1), ZIndex = 23 }, p)
	skin(rim, "panel")
	self.RimGrad = new("UIGradient", { Rotation = 35, Color = CS({ CK(0, RGB(110, 236, 255)), CK(0.35, RGB(110, 140, 255)), CK(0.7, RGB(200, 110, 255)), CK(1, RGB(110, 236, 255)) }) }, rim)
	return p
end

------------------------------------------------------------------ build
function M:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "MasteryHS", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(CW, CH), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit
	self:_panel(fit)

	-- emblem (mastery tile art) + title breaking the top-left corner
	new("ImageLabel", { Name = "TitleGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(120, 140, 255), ImageTransparency = 0.4, AnchorPoint = V2(0.5, 0.5), Position = O(84, 64), Size = O(240, 220), ZIndex = 45 }, fit)
	local eh = new("Frame", { Name = "TitleEmblem", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(80, 62), Size = O(146, 146), ZIndex = 47 }, fit)
	local core = new("ImageLabel", { Name = "CoreGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(150, 120, 255), ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.3, 1.3), ZIndex = 46 }, eh)
	new("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Image = TILE, ImageColor3 = BLACK, ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Fit, Position = O(5, 8), Size = S(1, 1), ZIndex = 46 }, eh)
	new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = TILE, ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = 47 }, eh)
	self:_maskSweep(eh, "Tile", 48, 0.75, 4.2)
	local sparks = new("Frame", { Name = "Sparks", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.4, 1.3), ZIndex = 48 }, eh)
	self:_twinkles(sparks, 6, RGB(190, 220, 255), 24, 48)
	self.Emblem = { H = eh, Core = core, Base = O(80, 62) }
	self:_label(fit, { Name = "Title", Text = "Mastery", TextSize = 92, Stroke = 6, StrokeColor = RGB(30, 16, 4), Grad = GOLD_GRAD, X = LEFT, Fit = false, Position = O(160, 0), Size = O(520, 104), DropY = 6, ZIndex = 47 })
	local shine = HS.text(fit, { Name = "TitleShine", Text = "Mastery", TextSize = 92, Color = WHITE, X = LEFT, Fit = false, Position = O(160, 0), Size = O(520, 104), ZIndex = 48 })
	table.insert(self.Sweeps, { G = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 0.55), NK(0.5, 0.25), NK(0.52, 0.55), NK(0.58, 1), NK(1, 1) }) }, shine), P = 1, Period = 5 })
	local chip = new("ImageLabel", { Name = "TotalChip", BackgroundTransparency = 1, Position = O(500, 36), Size = O(230, 50), ZIndex = 46 }, fit)
	skin(chip, "pill")
	chip.ImageColor3 = RGB(130, 200, 255)
	self:_sweep(chip, O(7, 6), O(216, 34), UDim.new(0.5, 0), 46, 0.3)
	self.TotalText = self:_label(chip, { Text = "TOTAL MASTERY 0", Font = HS.MontX, TextSize = 19, Stroke = 2.2, StrokeColor = RGB(6, 20, 50), Position = O(0, -3), Size = S(1, 1), ZIndex = 47 })
	-- account-wide earn boosts from mastery (MasteryBoostREQ / ORD / XP)
	self.BoostText = {}
	for i, key in { "REQ", "ORD", "XP" } do
		local bp = new("ImageLabel", { Name = "Boost" .. key, BackgroundTransparency = 1, Position = O(742 + (i - 1) * 118, 41), Size = O(112, 40), ZIndex = 46 }, fit)
		skin(bp, "pill")
		bp.ImageColor3 = BOOST_COL[key]
		self:_sweep(bp, O(5, 5), O(102, 26), UDim.new(0.5, 0), 46, 0.3)
		self.BoostText[key] = self:_label(bp, { Text = "+0% " .. key, Font = HS.MontX, TextSize = 16, Stroke = 2, StrokeColor = RGB(6, 10, 30), Position = O(0, -2), Size = S(1, 1), ZIndex = 47 })
	end

	-- Forge Parts + REQ pills, X
	local function pill(name, x, icon, glowCol, iconSize)
		local cur = new("ImageLabel", { Name = name, BackgroundTransparency = 1, Position = O(x, 30), Size = O(214, 66), ZIndex = 46 }, fit)
		skin(cur, "pill")
		self:_sweep(cur, O(9, 8), O(196, 46), UDim.new(0.5, 0), 46, 0.35)
		new("ImageLabel", { Name = "IconGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = glowCol, ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = O(16, 30), Size = O(120, 100), ZIndex = 46 }, cur)
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(18, 29), Size = O(iconSize, iconSize), ZIndex = 48 }, cur)
		return self:_label(cur, { Name = "Value", Text = "0", Font = HS.MontX, TextSize = 32, Stroke = 2.6, Position = O(62, -4), Size = O(140, 66), ZIndex = 48 })
	end
	self.ForgeText = pill("ForgeParts", 1104, FORGE, RGB(255, 140, 40), 74)
	self.ReqText = pill("Currency", 1336, REQ_ICON, RGB(90, 180, 255), 92)
	self:_btn(fit, { Name = "Close", Skin = "close", AnchorPoint = V2(0.5, 0.5), Position = O(1612, 66), Size = O(76, 76), Z = 48, Hover = 1.08, Sound = "Click", OnClick = function()
		if self.Env.Close then self.Env.Close() end
	end })

	self:_buildList(fit)
	self:_buildCentre(fit)
	self:_buildRight(fit)
	self:_buildTrack(fit)
	self:_buildConfirm(fit)
	self:_buildToast(fit)
end

------------------------------------------------------------------ left: weapon list
function M:_buildList(fit)
	local HS = self.HS
	local new = HS.new
	local sc = new("ScrollingFrame", { Name = "WeaponList", BackgroundTransparency = 1, BorderSizePixel = 0, Position = O(LIST_X, LIST_Y), Size = O(LIST_W + 10, LIST_H), CanvasSize = O(0, #Unlocks.List * ROW_P), ScrollBarThickness = 5, ScrollBarImageColor3 = RGB(120, 170, 255), ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 30 }, fit)
	self.List = sc
	for i, w in Unlocks.List do
		local y = (i - 1) * ROW_P
		local b = new("ImageButton", { Name = w.Id, BackgroundTransparency = 1, AutoButtonColor = false, Position = O(4, y + 2), Size = O(LIST_W - 8, ROW_H), ZIndex = 31 }, sc)
		local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(90, 220, 255), ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.22, Position = O(-14, -12), Size = UDim2.new(1, 28, 1, 24), ZIndex = 30 }, b)
		local st = self:_strip(b, "Face", O(0, 0), S(1, 1), 31, nil, 0.45)
		self:_sweep(b, O(6, 6), UDim2.new(1, -12, 1, -14), UDim.new(0, 12), 36, 0.18)
		local vp = new("ViewportFrame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(70, 36), Size = O(118, 58), ZIndex = 34 }, b)
		local m = gunModel(w.Id)
		if m then
			frameUniform(vp, m, 0, fillFor(118, 58))
			silhouette(b, vp, BLACK, 0.5, 1, V2(3, 4), 33)
		end
		local name = self:_label(b, { Name = "Name", Text = w.Name, TextSize = 25, Stroke = 2.6, X = LEFT, Position = O(136, 4), Size = O(170, 34), ZIndex = 36 })
		local sub = self:_body(b, { Name = "Sub", Text = "", TextSize = 13, Position = O(137, 34), Size = O(190, 16), ZIndex = 36 })
		local _, setBar = self:_bar(b, O(134, 50), O(196, 14), 35)
		local stars = {}
		for k = 1, MC.MaxPrestige do
			stars[k] = self:_star(b, O(258 + k * 22, 19), 22, 36)
		end
		local node = new("ImageLabel", { Name = "Level", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(LIST_W - 46, 37), Size = O(60, 60), ZIndex = 35 }, b)
		skin(node, "node_on")
		local lv = self:_label(node, { Name = "N", Text = "1", TextSize = 26, Stroke = 2.6, Position = O(0, -2), Size = S(1, 1), ZIndex = 37 })
		local lock = new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(LIST_W - 46, 36), Size = O(40, 49), Visible = false, ZIndex = 38 }, b)
		skin(lock, "lock")
		local shade = new("Frame", { Name = "Shade", BackgroundColor3 = RGB(6, 6, 18), BackgroundTransparency = 0.45, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -12), Visible = false, ZIndex = 37 }, b)
		HS.corner(shade, 12)
		HS.press(b, function() self:_select(w.Id) end, { Hover = 1.02, Press = 0.97, Sound = "Click" })
		self.Rows[w.Id] = { B = b, Glow = glow, Face = st, Name = name, Sub = sub, SetBar = setBar, Stars = stars, Node = node, Lv = lv, Lock = lock, Shade = shade, Gun = vp }
	end
end

------------------------------------------------------------------ centre: showcase, medallion, XP, versions
function M:_buildCentre(fit)
	local HS = self.HS
	local new = HS.new
	local cx = CEN_X + CEN_W / 2
	self.Rays = new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(120, 200, 255), ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = O(cx, 290), Size = O(560, 560), ZIndex = 24 }, fit)
	self.StageBloom = new("ImageLabel", { Name = "StageBloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(80, 160, 255), ImageTransparency = 0.25, AnchorPoint = V2(0.5, 0.5), Position = O(cx, 296), Size = O(600, 380), ZIndex = 24 }, fit)
	table.insert(self.Pulses, { I = self.StageBloom, Base = 0.25, Amp = 0.1, Spd = 1.6 })
	self.WName = self:_label(fit, { Name = "WeaponName", Text = "", TextSize = 58, Stroke = 4.5, Grad = CYAN_GRAD, Fit = false, Position = O(CEN_X, 96), Size = O(CEN_W, 64), ZIndex = 40 })
	self.WSub = self:_body(fit, { Name = "WeaponSub", Text = "", TextSize = 17, X = Enum.TextXAlignment.Center, Color = RGB(150, 220, 255), Position = O(CEN_X, 158), Size = O(CEN_W, 22), ZIndex = 40 })
	self.Show = new("Frame", { Name = "Showcase", BackgroundTransparency = 1, Size = O(CW, CH), ZIndex = 25 }, fit)
	-- locked overlay (weapon not owned yet)
	self.LockBox = new("Frame", { Name = "LockBox", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(cx, 300), Size = O(420, 120), Visible = false, ZIndex = 42 }, fit)
	local lb = self:_strip(self.LockBox, "Face", O(0, 0), S(1, 1), 42, RGB(200, 200, 230), 0.5)
	local li = new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(62, 56), Size = O(64, 78), ZIndex = 44 }, lb)
	skin(li, "lock")
	self.LockText = self:_label(lb, { Name = "Text", Text = "", TextSize = 30, Stroke = 3, X = LEFT, Position = O(112, 10), Size = O(290, 50), ZIndex = 44 })
	self.LockSub = self:_body(lb, { Name = "Sub", Text = "Mastery starts once you own it.", TextSize = 15, Position = O(113, 62), Size = O(290, 40), ZIndex = 44 })

	-- medallion + XP strip
	local md = new("Frame", { Name = "Medallion", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(CEN_X + 74, 470), Size = O(150, 150), ZIndex = 44 }, fit)
	local mg = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(80, 200, 255), ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.5, 1.4), ZIndex = 43 }, md)
	table.insert(self.Pulses, { I = mg, Base = 0.3, Amp = 0.15, Spd = 2.6 })
	new("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Image = MEDAL, ImageColor3 = BLACK, ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Fit, Position = O(4, 7), Size = S(1, 1), ZIndex = 44 }, md)
	new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = MEDAL, ScaleType = Enum.ScaleType.Fit, Size = S(1, 1), ZIndex = 45 }, md)
	self:_maskSweep(md, "Medal", 46, 0.6, 3.4)
	self:_body(md, { Name = "Cap", Text = "MASTERY", TextSize = 11, X = Enum.TextXAlignment.Center, Color = RGB(150, 230, 255), Position = O(0, 52), Size = O(150, 14), ZIndex = 47 })
	self.MedalN = self:_label(md, { Name = "N", Text = "1", TextSize = 40, Stroke = 3.4, Grad = CYAN_GRAD, Position = O(0, 58), Size = O(150, 44), ZIndex = 48 })
	self.MedalStars = {}
	for k = 1, MC.MaxPrestige do
		self.MedalStars[k] = self:_star(md, O(75 + (k - 2) * 28, 6), 28, 48)
	end
	self.Medal = md
	local strip = self:_strip(fit, "XPStrip", O(CEN_X + 140, 446), O(CEN_W - 146, 56), 40, nil, 0.42)
	local _, setXP = self:_bar(strip, O(14, 11), O(CEN_W - 174, 32), 41)
	self.SetXP = setXP
	self.XPText = self:_label(strip, { Name = "XP", Text = "", Font = HS.MontX, TextSize = 18, Stroke = 2.4, Position = O(14, 9), Size = O(CEN_W - 174, 34), ZIndex = 44 })
	self.NextText = self:_body(fit, { Name = "Next", Text = "", TextSize = 15, Rich = true, Color = RGB(200, 220, 255), Position = O(CEN_X + 150, 420), Size = O(CEN_W - 160, 20), ZIndex = 40 })

	-- version cards
	local vw = (CEN_W - 16) / 3
	for i = 0, 2 do
		local x = CEN_X + i * (vw + 8)
		local b = new("ImageButton", { Name = "Version" .. i, BackgroundTransparency = 1, AutoButtonColor = false, Position = O(x, 524), Size = O(vw, 150), ZIndex = 40 }, fit)
		local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = VCOL[i], ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.3, Position = O(-20, -18), Size = UDim2.new(1, 40, 1, 36), ZIndex = 39 }, b)
		local face = self:_strip(b, "Face", O(0, 0), S(1, 1), 40, hsv(VCOL[i], 0.55, 1), 0.5)
		local band = new("Frame", { Name = "Band", BackgroundColor3 = VCOL[i], BorderSizePixel = 0, Position = O(8, 8), Size = UDim2.new(1, -16, 0, 34), ZIndex = 41 }, b)
		HS.corner(band, 10)
		new("UIGradient", { Rotation = 90, Transparency = NS(0.2, 0.75) }, band)
		self:_sweep(b, O(7, 7), UDim2.new(1, -14, 1, -16), UDim.new(0, 12), 46, 0.22)
		local tag = self:_label(b, { Name = "Tag", Text = if i == 0 then "STANDARD" else ("VARIANT " .. string.rep("I", i)), Font = HS.MontX, TextSize = 15, Stroke = 2, X = LEFT, Position = O(18, 10), Size = O(vw - 36, 28), ZIndex = 44 })
		local name = self:_label(b, { Name = "Name", Text = "", TextSize = 30, Stroke = 3, X = LEFT, Position = O(16, 42), Size = O(vw - 30, 38), ZIndex = 44 })
		local short = self:_body(b, { Name = "Short", Text = "", TextSize = 14, Position = O(17, 84), Size = O(vw - 34, 40), ZIndex = 44 })
		local lock = new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = O(26, 32), Visible = false, ZIndex = 45 }, b)
		skin(lock, "lock")
		local req = self:_body(b, { Name = "Req", Text = "", TextSize = 13, X = RIGHT, Color = RGB(255, 210, 120), AnchorPoint = V2(1, 0), Position = UDim2.new(1, -14, 1, -28), Size = O(vw - 28, 18), ZIndex = 44 })
		local check = new("ImageLabel", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = O(40, 32), Visible = false, ZIndex = 45 }, b)
		skin(check, "check")
		HS.press(b, function() self.Ver = i; self:_refresh() end, { Hover = 1.03, Press = 0.97, Sound = "Click" })
		self.VCards[i] = { B = b, Glow = glow, Face = face, Band = band, Tag = tag, Name = name, Short = short, Lock = lock, Req = req, Check = check }
	end
end

------------------------------------------------------------------ right: prestige gold + version details
function M:_buildRight(fit)
	local HS = self.HS
	local new = HS.new
	local w = RIGHT_W
	local card = new("Frame", { Name = "Prestige", BackgroundTransparency = 1, Position = O(RIGHT_X, 100), Size = O(w, 318), ZIndex = 30 }, fit)
	new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(255, 190, 70), ImageTransparency = 0.25, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.35, Position = O(-30, -30), Size = UDim2.new(1, 60, 1, 60), ZIndex = 29 }, card)
	local bg = new("ImageLabel", { Name = "Backdrop", BackgroundTransparency = 1, Image = PRESTIGE_BG, ScaleType = Enum.ScaleType.Crop, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 30 }, card)
	HS.corner(bg, 22)
	local shade = new("Frame", { Name = "Shade", BackgroundColor3 = BLACK, BorderSizePixel = 0, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 30 }, card)
	HS.corner(shade, 22)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.35), NK(0.3, 0.9), NK(0.62, 0.85), NK(1, 0.25) }) }, shade)
	local rim = new("ImageLabel", { Name = "Rim", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.22, Size = S(1, 1), ZIndex = 36 }, card)
	skin(rim, "panel")
	self.GoldRim = new("UIGradient", { Rotation = 30, Color = CS({ CK(0, RGB(255, 246, 200)), CK(0.3, RGB(255, 196, 70)), CK(0.55, RGB(180, 110, 20)), CK(0.8, RGB(255, 220, 120)), CK(1, RGB(255, 246, 200)) }) }, rim)
	self:_sweep(card, O(8, 8), UDim2.new(1, -16, 1, -16), UDim.new(0, 20), 35, 0.2, 4.4)
	local motes = new("Frame", { Name = "Motes", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(10, 10), Size = UDim2.new(1, -20, 1, -20), ZIndex = 31 }, card)
	self:_embers(motes, 14, RGB(255, 220, 140), RGB(255, 170, 60), 4, 31)
	self:_label(card, { Name = "Title", Text = "Prestige Gold", TextSize = 38, Stroke = 4, StrokeColor = RGB(46, 22, 2), Grad = GOLD_GRAD, X = LEFT, Position = O(22, 12), Size = O(300, 44), ZIndex = 40 })
	self.PStars = {}
	for k = 1, MC.MaxPrestige do
		self.PStars[k] = self:_star(card, O(w - 128 + k * 32, 34), 32, 40)
	end
	self.PGold = new("Frame", { Name = "Gun", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 32 }, card)
	self.PRays = new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(255, 210, 110), ImageTransparency = 0.55, AnchorPoint = V2(0.5, 0.5), Position = O(w / 2, 142), Size = O(300, 300), ZIndex = 31 }, card)
	self.PText = self:_body(card, { Name = "Text", Text = "", TextSize = 15, X = Enum.TextXAlignment.Center, Color = RGB(255, 236, 196), Position = O(20, 214), Size = O(w - 40, 20), ZIndex = 40 })
	self.PBtn = self:_btn(card, { Name = "PrestigeBtn", Skin = "skip_orange", Text = "PRESTIGE", TextSize = 30, Stroke = 3, Ink = RGB(60, 24, 2), AnchorPoint = V2(0.5, 0), Position = O(w / 2, 240), Size = O(250, 68), Z = 40, Sound = "Click", OnClick = function()
		if self.CanPrestige then self:_confirm(true) end
	end })

	-- version details
	local det = self:_strip(fit, "Details", O(RIGHT_X, 432), O(w, 242), 30, RGB(170, 190, 255), 0.45)
	self:_sweep(det, O(7, 7), UDim2.new(1, -14, 1, -16), UDim.new(0, 12), 38, 0.14, 5)
	self.DName = self:_label(det, { Name = "Name", Text = "", TextSize = 28, Stroke = 3, X = LEFT, Position = O(18, 8), Size = O(260, 34), ZIndex = 36 })
	self.DCode = self:_body(det, { Name = "Code", Text = "", TextSize = 14, X = RIGHT, Color = RGB(150, 220, 255), Position = O(w - 200, 18), Size = O(180, 18), ZIndex = 36 })
	self.DBlurb = self:_body(det, { Name = "Blurb", Text = "", TextSize = 15, Position = O(19, 44), Size = O(w - 38, 40), ZIndex = 36 })
	self.DStats = {}
	for k, key in Variants.StatKeys do
		local y = 88 + (k - 1) * 23
		self:_body(det, { Name = "K" .. k, Text = string.upper(key), TextSize = 12, Color = RGB(170, 186, 230), Position = O(19, y + 2), Size = O(100, 16), ZIndex = 36 })
		local trk = new("Frame", { Name = "Track" .. k, BackgroundColor3 = RGB(8, 10, 28), BorderSizePixel = 0, Position = O(120, y + 3), Size = O(w - 196, 12), ZIndex = 35 }, det)
		HS.corner(trk, UDim.new(0.5, 0))
		HS.new("UIStroke", { Color = RGB(70, 90, 160), Thickness = 1, Transparency = 0.3 }, trk)
		local f = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(0.5, 1), ZIndex = 36 }, trk)
		HS.corner(f, UDim.new(0.5, 0))
		new("UIGradient", { Color = CS(RGB(70, 150, 255), RGB(130, 240, 255)) }, f)
		local delta = new("Frame", { Name = "Delta", BackgroundColor3 = RGB(110, 255, 140), BorderSizePixel = 0, Size = S(0, 1), ZIndex = 37 }, trk)
		HS.corner(delta, UDim.new(0.5, 0))
		local val = self:_body(det, { Name = "V" .. k, Text = "", TextSize = 13, X = RIGHT, Position = O(w - 70, y + 1), Size = O(52, 16), ZIndex = 36 })
		self.DStats[k] = { Fill = f, Delta = delta, Val = val }
	end
end

------------------------------------------------------------------ bottom: reward track
function M:_buildTrack(fit)
	local HS = self.HS
	local new = HS.new
	self.TrackTitle = self:_label(fit, { Name = "TrackTitle", Text = "Rewards", TextSize = 30, Stroke = 3, Grad = CYAN_GRAD, X = LEFT, Position = O(TR_X0 + 4, TR_Y - 38), Size = O(500, 36), ZIndex = 40 })
	self:_body(fit, { Name = "TrackHint", Text = "Every mastery level pays out. Rewards are granted automatically.", TextSize = 14, X = RIGHT, Color = RGB(160, 180, 230), Position = O(TR_X1 - 600, TR_Y - 26), Size = O(596, 18), ZIndex = 40 })
	local clip = new("Frame", { Name = "TrackClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = O(TR_X0, TR_Y), Size = O(TR_X1 - TR_X0, 220), ZIndex = 30 }, fit)
	local track = new("Frame", { Name = "Track", BackgroundTransparency = 1, Size = O(NCARDS * PITCH + 20, 220), ZIndex = 30 }, clip)
	self.Clip, self.Track = clip, track -- cards, rail and nodes are built per weapon in _select
	-- drag / wheel
	clip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.Drag = { X = input.Position.X, Off = self.Off }
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if self.Drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local k = clip.AbsoluteSize.X / (TR_X1 - TR_X0)
			self.Off = math.clamp(self.Drag.Off - (input.Position.X - self.Drag.X) / math.max(k, 0.01), 0, OFF_MAX)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then self.Drag = nil end
	end)
	clip.MouseWheelForward:Connect(function() self.Off = math.clamp(self.Off - PITCH * 2, 0, OFF_MAX) end)
	clip.MouseWheelBackward:Connect(function() self.Off = math.clamp(self.Off + PITCH * 2, 0, OFF_MAX) end)
	self:_btn(fit, { Name = "ArrowL", Skin = "arrow_l", AnchorPoint = V2(0.5, 0.5), Position = O(TR_X0 - 14, TR_Y + 76), Size = O(56, 56), Z = 46, Hover = 1.1, Sound = "Click", OnClick = function() self.Off = math.clamp(self.Off - PITCH * 6, 0, OFF_MAX) end })
	self:_btn(fit, { Name = "ArrowR", Skin = "arrow_r", AnchorPoint = V2(0.5, 0.5), Position = O(TR_X1 + 14, TR_Y + 76), Size = O(56, 56), Z = 46, Hover = 1.1, Sound = "Click", OnClick = function() self.Off = math.clamp(self.Off + PITCH * 6, 0, OFF_MAX) end })
end

local function rewardLook(rw)
	if not rw then return "Start", RGB(120, 160, 255) end
	local k = rw.Kind
	if k == "REQ" then return num(rw.Amount) .. " REQ", RGB(80, 170, 255) end
	if k == "ForgePart" or k == "Forge" or k == "ForgeParts" then return (rw.Amount or 1) .. " Forge Part" .. (if (rw.Amount or 1) > 1 then "s" else ""), RGB(255, 140, 40) end
	if k == "Variant" then return "Variant " .. string.rep("I", rw.Index or 1), VCOL[rw.Index or 1] end
	if k == "Finish" then return (rw.Name or rw.Id):gsub("^Mastery finish: ", ""), FINISH_COL[rw.Id] or RGB(255, 206, 90) end
	if k == "Title" or k == "Badge" then return rw.Name, RGB(255, 196, 70) end
	if k == "Boost" then return rw.Name, BOOST_COL[rw.Key] or RGB(255, 196, 70) end
	return rw.Name or k, RGB(180, 130, 255)
end

-- one reward card (rebuilt per weapon)
function M:_trackCard(i, level, rewards, w)
	local HS = self.HS
	local new = HS.new
	local prestige = level == nil
	local rw = if prestige then MC.PrestigeReward else rewards[1]
	local text, col = rewardLook(rw)
	if prestige then text, col = "Prestige Gold", legendary(0) end
	local x = (i - 1) * PITCH + 4
	local b = new("Frame", { Name = "Card" .. i, BackgroundTransparency = 1, Position = O(x, 6), Size = O(CARD_W, CARD_H), ZIndex = 32 }, self.Track)
	local glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = col, ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.22, Position = O(-22, -22), Size = UDim2.new(1, 44, 1, 44), ZIndex = 31 }, b)
	local face = new("ImageLabel", { Name = "Face", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 32 }, b)
	local frame = new("ImageLabel", { Name = "Frame", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 38 }, b)
	if prestige then
		skin(face, "face_gold")
		skin(frame, "frame_gold")
	else
		skin(face, "face_dark")
		face.ImageColor3 = hsv(col, 1.05, 1)
		skin(frame, "frame_white")
		frame.ImageColor3 = hsv(col, 0.55, 1)
	end
	self:_sweep(b, O(5, 5), O(CARD_W - 10, CARD_H - 10), UDim.new(0, 10), 37, 0.22)
	-- item
	local cx, cy = CARD_W / 2, 66
	new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = col, ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = O(cx, cy), Size = O(130, 100), ZIndex = 33 }, b)
	local k = rw and rw.Kind
	if prestige and GOLD_CELL[w] then
		self:_goldArt(b, w, O(cx, cy), O(132, 66), 34)
	elseif k == "Finish" or k == "Variant" or k == "Cosmetic" or k == "Inspect" or prestige then
		local vp = new("ViewportFrame", { Name = "Item", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(cx, cy), Size = O(118, 92), ZIndex = 36 }, b)
		local m = gunModel(w, prestige or (rw.Id == "PrestigeGold"))
		if m then
			frameUniform(vp, m, 30, fillFor(118, 92, 1.0))
			if (k == "Finish" or k == "Cosmetic") and not prestige then vp.ImageColor3 = hsv(col, 0.6, 1) end
			silhouette(b, vp, BLACK, 0.45, 1, V2(3, 5), 34)
			silhouette(b, vp, hsv(col, 0.6, 1), 0.4, 1.06, V2(0, 0), 35)
		end
	else
		local image, sz, tint = STAR, 60, col
		if k == "REQ" then
			for _, t in REQ_ART do
				if (rw.Amount or 0) <= t[1] then image = t[2] break end
			end
			sz, tint = 104, WHITE
		elseif k == "ForgePart" or k == "Forge" or k == "ForgeParts" then
			image, sz, tint = FORGE, 84, WHITE
		elseif k == "Boost" then
			image, sz, tint = (if rw.Key == "REQ" then REQ_ICON else TILE), (if rw.Key == "REQ" then 92 else 74), WHITE
		elseif not rw or k == "Title" or k == "Badge" then
			image, sz, tint = TILE, 90, WHITE
		elseif k == "Counter" then
			image, sz, tint = MEDAL, 96, WHITE
		end
		new("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Image = image, ImageColor3 = BLACK, ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(cx + 3, cy + 5), Size = O(sz, sz), ZIndex = 35 }, b)
		new("ImageLabel", { Name = "Item", BackgroundTransparency = 1, Image = image, ImageColor3 = tint, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(cx, cy), Size = O(sz, sz), ZIndex = 36 }, b)
		if k == "Boost" then -- permanent earn boost: currency art + big "+n%"
			if rw.Key == "ORD" and HS.ordCoin then
				b.Item.Visible, b.Shadow.Visible = false, false
				HS.ordCoin(b, { Position = O(cx, cy - 6), Size = O(70, 70), ZIndex = 36 })
			end
			self:_label(b, { Name = "Pct", Text = "+" .. rw.Pct .. "%", TextSize = 36, Stroke = 3.4, StrokeColor = RGB(30, 14, 2), Grad = GOLD_GRAD, Position = O(0, cy + 6), Size = O(CARD_W, 40), ZIndex = 41 })
		end
	end
	self:_label(b, { Name = "Text", Text = text, Font = HS.MontX, TextSize = 13, Stroke = 2, Position = O(8, CARD_H - 40), Size = O(CARD_W - 16, 30), ZIndex = 40 })
	if #rewards > 1 then
		local extra = new("ImageLabel", { Name = "More", BackgroundTransparency = 1, Position = O(8, 8), Size = O(40, 22), ZIndex = 40 }, b)
		skin(extra, "pill")
		self:_label(extra, { Text = "+" .. (#rewards - 1), Font = HS.MontX, TextSize = 13, Stroke = 1.8, Position = O(0, -2), Size = S(1, 1), ZIndex = 41 })
	end
	local check = new("ImageLabel", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = O(38, 30), Visible = false, ZIndex = 41 }, b)
	skin(check, "check")
	local lock = new("ImageLabel", { Name = "Lock", BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = O(22, 27), Visible = false, ZIndex = 41 }, b)
	skin(lock, "lock")
	local dim = new("Frame", { Name = "Dim", BackgroundColor3 = RGB(6, 6, 18), BackgroundTransparency = 0.55, Position = O(6, 6), Size = O(CARD_W - 12, CARD_H - 12), Visible = false, ZIndex = 39 }, b)
	HS.corner(dim, 10)
	-- timeline node
	local node = new("ImageLabel", { Name = "Node" .. i, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(x + CARD_W / 2, NODE_Y), Size = O(42, 42), ZIndex = 33 }, self.Track)
	skin(node, "node_off")
	local nl = self:_label(node, { Text = if prestige then "P" else tostring(level), TextSize = 17, Stroke = 2, Position = O(0, -1), Size = S(1, 1), ZIndex = 35 })
	self.TrackCards[i] = { Level = level, B = b, Glow = glow, Check = check, Lock = lock, Dim = dim, Node = node, NL = nl }
end

------------------------------------------------------------------ prestige confirm + toast
function M:_buildConfirm(fit)
	local HS = self.HS
	local new = HS.new
	local c = new("TextButton", { Name = "Confirm", Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, Position = O(PX + 6, PY + 6), Size = O(PW - 12, PH - 12), Visible = false, ZIndex = 80 }, fit)
	HS.corner(c, 26)
	local box = new("Frame", { Name = "Box", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.46), Size = O(640, 330), ZIndex = 81 }, c)
	new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = RGB(255, 190, 70), ImageTransparency = 0.2, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.4, Position = O(-40, -40), Size = UDim2.new(1, 80, 1, 80), ZIndex = 81 }, box)
	local bg = new("ImageLabel", { Name = "Backdrop", BackgroundTransparency = 1, Image = PRESTIGE_BG, ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.15, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 82 }, box)
	HS.corner(bg, 22)
	local sh = new("Frame", { BackgroundColor3 = BLACK, BackgroundTransparency = 0.4, BorderSizePixel = 0, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 82 }, box)
	HS.corner(sh, 22)
	local rim = new("ImageLabel", { Name = "Rim", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(80, 80, 320, 320), SliceScale = 0.24, Size = S(1, 1), ZIndex = 84 }, box)
	skin(rim, "panel")
	new("UIGradient", { Rotation = 30, Color = CS({ CK(0, RGB(255, 246, 200)), CK(0.4, RGB(255, 196, 70)), CK(0.7, RGB(180, 110, 20)), CK(1, RGB(255, 236, 160)) }) }, rim)
	self.CTitle = self:_label(box, { Name = "Title", Text = "Prestige?", TextSize = 50, Stroke = 4.5, StrokeColor = RGB(46, 22, 2), Grad = GOLD_GRAD, Position = O(0, 22), Size = O(640, 60), ZIndex = 86 })
	self.CText = self:_body(box, { Name = "Text", Text = "", TextSize = 18, X = Enum.TextXAlignment.Center, Color = RGB(255, 240, 210), Rich = true, Position = O(50, 96), Size = O(540, 110), ZIndex = 86 })
	self:_btn(box, { Name = "Cancel", Skin = "back", Text = "CANCEL", TextSize = 28, Position = O(70, 226), Size = O(230, 72), Z = 86, Sound = "Click", OnClick = function() self:_confirm(false) end })
	self:_btn(box, { Name = "Go", Skin = "skip_orange", Text = "PRESTIGE", TextSize = 30, Ink = RGB(60, 24, 2), Position = O(340, 222), Size = O(240, 78), Z = 86, Sound = "Click", OnClick = function()
		self:_confirm(false)
		local r = Remotes:FindFirstChild("MasteryPrestige")
		if r and not self.Env.Attr then r:FireServer(self.Sel) end
	end })
	self.ConfirmFrame = c
end

function M:_confirm(show)
	if show then
		local d = self:_data(self.Sel)
		self.CTitle.Text = "Prestige " .. Unlocks.Name(self.Sel) .. "?"
		self.CText.Text = string.format("Mastery goes back to <b>Level 1</b>. Your variants and finishes stay unlocked.\nYou earn <font color=\"#FFD36A\"><b>Prestige Gold</b></font> and star <b>%d of %d</b>.", d.Prestige + 1, MC.MaxPrestige)
	end
	self.ConfirmFrame.Visible = show
end

function M:_buildToast(fit)
	local t = self:_strip(fit, "Toast", O(CW / 2 - 260, -90), O(520, 74), 90, RGB(150, 220, 255), 0.5)
	t.Visible = false
	local ic = self.HS.new("ImageLabel", { BackgroundTransparency = 1, Image = TILE, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(46, 36), Size = O(64, 64), ZIndex = 92 }, t)
	self.ToastTitle = self:_label(t, { Text = "", TextSize = 26, Stroke = 2.8, Grad = GOLD_GRAD, X = LEFT, Position = O(88, 6), Size = O(410, 32), ZIndex = 92 })
	self.ToastText = self:_body(t, { Text = "", TextSize = 15, Position = O(89, 40), Size = O(410, 20), ZIndex = 92 })
	self.Toast = t
	return ic
end

function M:_onLevelUp(info)
	if type(info) ~= "table" then return end
	if info.Prestige then -- end-game cinematic (PrestigeFX), plays over everything
		local ok, FX = pcall(require, script.Parent:WaitForChild("PrestigeFX"))
		if ok then pcall(FX.Play, { HS = self.HS, Weapon = info.Weapon, Prestige = info.Prestige }) end
		return
	end
	if not self.Root.Visible then return end
	local name = Unlocks.Name(info.Weapon or "")
	local title = if info.Prestige then name .. " Prestige " .. info.Prestige else name .. " Mastery " .. tostring(info.Level or "")
	local parts = {}
	for _, rw in info.Rewards or {} do table.insert(parts, (rewardLook(rw))) end
	self.ToastTitle.Text = title
	self.ToastText.Text = table.concat(parts, "  ·  ")
	local t = self.Toast
	t.Visible = true
	t.Position = O(CW / 2 - 260, -90)
	self.HS.tween(t, 0.35, { Position = O(CW / 2 - 260, 8) })
	task.delay(2.6, function()
		self.HS.tween(t, 0.3, { Position = O(CW / 2 - 260, -90) })
	end)
end

-- Prestige Gold render: glow + drop shadow + art + light streak cut to the gun's silhouette
function M:_goldArt(parent, w, pos, size, z)
	local new, c = self.HS.new, GOLD_CELL[w]
	local function img(name, image, color, tr, off, sz, zz)
		return new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = image, ImageRectOffset = V2(c[1], c[2]), ImageRectSize = V2(512, 256), ImageColor3 = color, ImageTransparency = tr, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = pos + off, Size = sz, ZIndex = zz }, parent)
	end
	img("GoldGlow", GOLD_MASKS, RGB(255, 206, 90), 0.3, O(0, 0), size + O(size.X.Offset * 0.06, size.Y.Offset * 0.12), z)
	img("GoldShadow", GOLD_MASKS, BLACK, 0.45, O(size.X.Offset * 0.012, size.Y.Offset * 0.05), size, z)
	local art = img("GoldArt", GOLD_ATLAS, WHITE, 0, O(0, 0), size, z + 1)
	local sheen = img("GoldSheen", GOLD_MASKS, WHITE, 0, O(0, 0), size, z + 2)
	local s = 0.8
	table.insert(self.Sweeps, { G = new("UIGradient", { Rotation = 25, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 1 - s * 0.5), NK(0.5, 1 - s), NK(0.52, 1 - s * 0.5), NK(0.58, 1), NK(1, 1) }) }, sheen), P = math.random() * 2, Period = 2.8 })
	return art
end

-- solid star (Fredoka glyph, thick stroke); colour via TextColor3
function M:_star(parent, pos, size, z)
	local t = self.HS.new("TextLabel", { Name = "Star", BackgroundTransparency = 1, Text = "★", FontFace = Font.fromEnum(Enum.Font.FredokaOne), TextSize = size, TextColor3 = RGB(40, 44, 80), AnchorPoint = V2(0.5, 0.5), Position = pos, Size = O(size, size), ZIndex = z }, parent)
	self.HS.new("UIStroke", { Thickness = math.max(1.5, size * 0.09), Color = RGB(20, 12, 4) }, t)
	return t
end
local function setStar(st, on, onCol, offCol)
	st.TextColor3 = if on then onCol else offCol
	st.TextTransparency = if on then 0 else 0.15
end

------------------------------------------------------------------ data -> view
function M:_select(w, force)
	if w == self.Sel and not force then return end
	self.Sel, self.Ver = w, 0
	-- showcase gun
	self.Show:ClearAllChildren()
	self.Spin = nil
	local cx = CEN_X + CEN_W / 2
	local vp = self.HS.new("ViewportFrame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(cx, 296), Size = O(600, 250), ZIndex = 28 }, self.Show)
	local m = gunModel(w)
	if m then
		local ctr = frameUniform(vp, m, 0, fillFor(600, 250, 1.08))
		local sh = silhouette(self.Show, vp, BLACK, 0.5, 1, V2(8, 12), 26)
		local gl = silhouette(self.Show, vp, RGB(110, 200, 255), 0.45, 1.05, V2(0, 0), 27)
		self.Spin = { M = m, C = ctr, Yaw = 0, Base = m:GetPivot(), Sils = { sh, gl } }
		self.ShowVP = vp
	end
	-- prestige gold gun
	self.PGold:ClearAllChildren()
	self.GoldVP = nil
	local gv = self.HS.new("ViewportFrame", { Name = "Gold", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(RIGHT_W / 2, 140), Size = O(380, 150), ZIndex = 34 }, self.PGold)
	local gm = (not GOLD_CELL[w]) and gunModel(w, true)
	if GOLD_CELL[w] then
		gv:Destroy()
		self.HS.new("ImageLabel", { Name = "Backing", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = BLACK, ImageTransparency = 0.15, AnchorPoint = V2(0.5, 0.5), Position = O(RIGHT_W / 2, 140), Size = O(440, 230), ZIndex = 31 }, self.PGold)
		self:_goldArt(self.PGold, w, O(RIGHT_W / 2, 140), O(400, 200), 32)
	elseif gm then
		frameUniform(gv, gm, 8, fillFor(380, 150, 1.05))
		gv.Ambient, gv.LightColor = RGB(150, 110, 60), RGB(255, 244, 210)
		self.GoldVP = gv
		silhouette(self.PGold, gv, BLACK, 0.4, 1, V2(5, 8), 32)
		silhouette(self.PGold, gv, RGB(255, 200, 80), 0.35, 1.07, V2(0, 0), 33)
		local sheen = silhouette(self.PGold, gv, WHITE, 0, 1, V2(0, 0), 35)
		if sheen then
			local s = 0.85
			table.insert(self.Sweeps, { G = self.HS.new("UIGradient", { Rotation = 25, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 1 - s * 0.5), NK(0.5, 1 - s), NK(0.52, 1 - s * 0.5), NK(0.58, 1), NK(1, 1) }) }, sheen), P = 0, Period = 2.6 })
		end
	end
	-- reward track
	self.Track:ClearAllChildren()
	self.TrackCards = {}
	do
		local rail = self.HS.new("ImageLabel", { Name = "Rail", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.25, AnchorPoint = V2(0, 0.5), Position = O(4 + CARD_W / 2, NODE_Y), Size = O((NCARDS - 1) * PITCH, 20), ZIndex = 30 }, self.Track)
		skin(rail, "linetrack")
		self.LineFill = self.HS.new("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(32, 31, 128, 33), SliceScale = 0.25, AnchorPoint = V2(0, 0.5), Position = O(4 + CARD_W / 2, NODE_Y), Size = O(0, 20), ZIndex = 31 }, self.Track)
		skin(self.LineFill, "line")
		self.HS.new("UIGradient", { Rotation = 90, Color = CS(RGB(200, 250, 255), RGB(80, 200, 255)) }, self.LineFill)
	end
	for L = 1, MC.MaxLevel do
		self:_trackCard(L, L, MC.RewardsFor(L) or {}, w)
	end
	self:_trackCard(NCARDS, nil, { MC.PrestigeReward }, w)
	self:_refresh()
	local d = self:_data(w)
	self.Off = math.clamp((d.Level - 3) * PITCH, 0, OFF_MAX)
	self.Cur = self.Off
	self.Track.Position = O(-self.Cur, 0)
end

function M:_refresh()
	self.Dirty = false
	local total = 0
	for _, w in Unlocks.List do
		local r = self.Rows[w.Id]
		local d = self:_data(w.Id)
		local owned = self:_owns(w.Id)
		if owned then total += d.Level + d.Prestige * MC.MaxLevel end
		local sel = w.Id == self.Sel
		r.Glow.ImageTransparency = if sel then 0.15 else 1
		r.Face.ImageColor3 = if sel then RGB(170, 236, 255) else WHITE
		r.Shade.Visible = not owned
		r.Lock.Visible = not owned
		r.Node.Visible = owned
		r.Lv.Text = tostring(d.Level)
		r.Gun.ImageTransparency = if owned then 0 else 0.35
		r.SetBar(if owned then (if d.Level >= MC.MaxLevel then 1 else d.Into / math.max(1, d.Need)) else 0)
		r.Sub.Text = if owned then (num(d.Kills) .. " eliminations") else Unlocks.LockText(w.Id)
		r.Sub.TextColor3 = if owned then RGB(170, 190, 235) else RGB(255, 206, 110)
		for k, st in r.Stars do setStar(st, k <= d.Prestige, RGB(255, 210, 90), RGB(44, 48, 86)) end
	end
	self.TotalText.Text = "TOTAL MASTERY " .. total
	for key, t in self.BoostText do t.Text = "+" .. (tonumber(self:_attr("MasteryBoost" .. key)) or 0) .. "% " .. key end
	self.ReqText.Text = num(self:_attr("REQ") or 0)
	self.ForgeText.Text = num(self:_attr("ForgeParts") or 0)

	local w = self.Sel
	local d = self:_data(w)
	local owned = self:_owns(w)
	local maxed = d.Level >= MC.MaxLevel
	self.WName.Text = string.upper(Unlocks.Name(w))
	local std = Variants.Standard[w]
	self.WSub.Text = if std then std.Blurb else ""
	self.LockBox.Visible = not owned
	self.LockText.Text = Unlocks.LockText(w)
	if self.ShowVP then self.ShowVP.ImageTransparency = if owned then 0 else 0.55 end
	self.MedalN.Text = tostring(d.Level)
	for k, st in self.MedalStars do setStar(st, k <= d.Prestige, RGB(255, 210, 90), RGB(44, 48, 86)) end
	self.SetXP(if maxed then 1 else d.Into / math.max(1, d.Need))
	self.XPText.Text = if maxed then "MAX MASTERY" else (num(d.Into) .. " / " .. num(d.Need) .. " XP")
	local nxt = math.min(MC.MaxLevel, d.Level + 1)
	local nr = MC.RewardsFor(nxt) or {}
	self.NextText.Text = if maxed then "Mastery 50 reached. Prestige for <font color=\"#FFD36A\">Prestige Gold</font>." else string.format("NEXT · LEVEL %d: <font color=\"#9BE8FF\">%s</font>", nxt, (rewardLook(nr[1])))

	-- version cards + details
	if not self:_variantOpen(w, self.Ver, d) or not (self.Ver == 0 or Variants.Get(w, self.Ver)) then self.Ver = 0 end
	for i = 0, 2 do
		local c = self.VCards[i]
		local v = Variants.Get(w, i)
		local exists = i == 0 or v ~= nil
		c.B.Visible = exists
		if exists then
			local open = self:_variantOpen(w, i, d)
			c.Name.Text = if i == 0 then "Standard" else v.Name
			c.Short.Text = if i == 0 then "The base weapon." else v.Short
			c.Lock.Visible = not open
			c.Req.Text = if open then "" else ("MASTERY " .. MC.VariantLevels[i])
			c.Check.Visible = open and i == self.Ver
			c.Glow.ImageTransparency = if i == self.Ver then 0.1 else 1
			c.Face.ImageColor3 = if open then hsv(VCOL[i], 0.55, 1) else RGB(120, 124, 150)
			c.Band.BackgroundTransparency = if open then 0 else 0.6
		end
	end
	local v = Variants.Get(w, self.Ver)
	local stats = if v then v.Stats elseif std then std.Stats else nil
	self.DName.Text = if v then v.Name else "Standard"
	self.DCode.Text = if v then (v.Code .. " · " .. v.Trait) else "BASE VERSION"
	self.DBlurb.Text = if v then v.Blurb elseif std then std.Blurb else ""
	for k, row in self.DStats do
		local val = stats and stats[k] or 0
		local base = std and std.Stats[k] or val
		local lo, hi = math.min(val, base), math.max(val, base)
		row.Fill.Size = S(lo / 100, 1)
		row.Delta.Position = S(lo / 100, 0)
		row.Delta.Size = S((hi - lo) / 100, 1)
		row.Delta.BackgroundColor3 = if val >= base then RGB(110, 255, 140) else RGB(255, 90, 110)
		row.Delta.BackgroundTransparency = if val >= base then 0 else 0.35
		row.Val.Text = if val == base then tostring(val) else ((if val > base then "+" else "−") .. math.abs(val - base))
		row.Val.TextColor3 = if val == base then RGB(206, 214, 240) elseif val > base then RGB(130, 255, 160) else RGB(255, 120, 140)
	end

	-- prestige card
	self.CanPrestige = owned and maxed and d.Prestige < MC.MaxPrestige
	for k, st in self.PStars do setStar(st, k <= d.Prestige, RGB(255, 214, 96), RGB(74, 56, 24)) end
	self.PText.Text = if d.Prestige >= MC.MaxPrestige then "Max prestige. Prestige Gold earned."
		elseif self.CanPrestige then "Mastery 50 reached. Prestige to earn the gold."
		else string.format("Reach Mastery %d to prestige (%d / %d)", MC.MaxLevel, d.Level, MC.MaxLevel)
	self.PBtn.B.ImageColor3 = if self.CanPrestige then WHITE else RGB(110, 100, 90)
	self.PBtn.T.TextTransparency = if self.CanPrestige then 0 else 0.4

	-- track states
	self.TrackTitle.Text = "Rewards · " .. Unlocks.Name(w)
	for _, c in self.TrackCards do
		local got = if c.Level then (owned and d.Level >= c.Level) else d.Prestige > 0
		local nextUp = c.Level ~= nil and owned and c.Level == d.Level + 1
		c.Check.Visible = got
		c.Lock.Visible = not got and not nextUp
		c.Dim.Visible = not got and not nextUp
		c.Glow.ImageTransparency = if nextUp then 0.2 elseif got then 0.75 else 1
		skin(c.Node, if got then "node_on" else "node_off")
		c.Next = nextUp
	end
	local reach = if owned then math.min(d.Level, MC.MaxLevel) else 1
	self.LineFill.Size = O((reach - 1) * PITCH + (if reach < NCARDS and owned and not maxed then PITCH * (d.Into / math.max(1, d.Need)) else 0), 20)
end

------------------------------------------------------------------ frame
function M:_step(dt)
	local t = os.clock()
	self.Cur += (self.Off - self.Cur) * math.min(1, dt * 12)
	if math.abs(self.Off - self.Cur) < 0.3 then self.Cur = self.Off end
	self.Track.Position = O(-self.Cur, 0)
	for _, sw in self.Sweeps do
		if sw.G.Parent then
			local u = ((t + sw.P) % (sw.Period or 3.6)) / 0.9
			sw.G.Offset = V2(if u < 1 then -1 + 2 * u else 1, 0)
		end
	end
	if self.RimGrad then self.RimGrad.Rotation = 35 + (t * 14) % 360 end
	if self.GoldRim then self.GoldRim.Rotation = 30 + (t * 40) % 360 end
	if self.Bands then
		local zz = 1.05 + 0.05 * (0.5 + 0.5 * math.sin(t * 0.31))
		local rw, rh = 1024 / zz, 640 / zz
		self.Bands.ImageRectSize = V2(rw, rh)
		self.Bands.ImageRectOffset = V2((1024 - rw) * (0.5 + math.sin(t * 0.19) * 0.45), (640 - rh) * (0.5 + math.cos(t * 0.15) * 0.45))
	end
	for i, nb in self.Nebula do
		nb.I.Position = nb.Base + UDim2.fromScale(math.sin(t * 0.13 + i * 2) * 0.06, math.cos(t * 0.11 + i) * 0.05)
		nb.I.ImageTransparency = nb.Tr + math.sin(t * 0.7 + i) * 0.07
	end
	for _, p in self.Pulses do
		p.I.ImageTransparency = p.Base + p.Amp * math.sin(t * p.Spd)
	end
	local e = self.Emblem
	e.H.Position = e.Base + O(0, math.sin(t * 1.4) * 5)
	e.H.Rotation = math.sin(t * 0.9) * 2.5
	e.Core.ImageTransparency = 0.28 + 0.22 * math.sin(t * 3.2)
	self.Medal.Rotation = math.sin(t * 0.8) * 1.5
	self.Rays.Rotation = (t * 8) % 360
	self.PRays.Rotation = (-t * 10) % 360
	if self.GoldVP then self.GoldVP.LightDirection = Vector3.new(math.sin(t * 0.9) * 0.9, -0.55, -0.75) end
	for _, c in self.TrackCards do
		if c.Next then c.Glow.ImageTransparency = 0.15 + 0.2 * math.sin(t * 4) end
	end
	for _, em in self.Embers do
		em.Y -= em.V * dt
		if em.Y < -0.05 then em.Y, em.X = 1.05, math.random() end
		em.F.Position = UDim2.new(em.X, math.sin(t * 1.3 + em.Sway) * 6, em.Y, 0)
		em.F.BackgroundTransparency = 0.15 + 0.85 * math.clamp(1 - em.Y, 0, 1) ^ 2
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
	if self.Spin and self.Spin.C then
		local sp = self.Spin
		sp.Yaw += dt * 0.6
		local cf = CFrame.new(sp.C) * CFrame.Angles(0, math.sin(sp.Yaw) * 0.55, 0) * CFrame.new(-sp.C) * sp.Base
		sp.M:PivotTo(cf)
		for _, s in sp.Sils do
			local sm = s and s:FindFirstChildWhichIsA("Model")
			if sm then sm:PivotTo(cf) end
		end
	end
end

------------------------------------------------------------------ mount
function M:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1780, vp.Y / 1040), 0.42, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
end

function M:OnShow()
	self:_fit()
	self:_confirm(false)
	if self.Dirty then self:_refresh() else self:_refresh() end
	local d = self:_data(self.Sel)
	self.Off = math.clamp((d.Level - 3) * PITCH, 0, OFF_MAX)
	self.Cur = self.Off
end

function M.Mount(layer, env)
	local s = M.new(layer, env)
	return {
		Root = s.Root,
		OnShow = function() s:OnShow() end,
		Object = s,
	}
end

return M
