--!nocheck
--[[
	VANTAGE — Gloss v2  ·  luminous Hypershot-style UI kit (2026-11-15)
	Built from the approved design canvas https://claude.ai/artifact/AJsffcY6yUbAkL3ZNUwUP9
	(project doc claude/lobby-gloss-ui.md). Black ink outlines, accent gradients (cyan, blue, violet,
	magenta, aurora, dusk, hot), dark glass panels with a thin cyan edge, soft tinted glows.
	Art (rendered from the canvas, uploaded 2026-11-15): tile faces per accent, trapezoid CTA
	buttons, glow, halftone dots, the user's icons + nine rank badges + REQ emblem.
	Roblox has no blur: every glow is G.A.Glow tinted with ImageColor3.
	API kept from v1 so Lobby + Pages still work: new tween corner stroke abbrev clock text sound
	press setDisabled tile badge wide square pill shell openModal closeModal header bar card artCard.
	New: glass(parent, p) · surface(frame, accent, p) · cta(parent, kind, p) · setCta(btn, kind)
	     glow(parent, p) · RankFor(level) -> image, name, index, glowColor, nextName, nextLevel
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local G = {}
local function id(n)
	return "rbxassetid://" .. n
end

G.A = {
	Glow = id(85510492667572),
	Dots = id(128661353023629),
	Face = {
		cyan = id(94425914075597), blue = id(85246814872977), magenta = id(134544823600868),
		violet = id(100476175585596), aurora = id(99146822427317), dusk = id(72576451738277),
	},
	Cta = {
		deploy = id(71242705339562), cancel = id(80649155562883), modes = id(108591427291180),
		pass = id(86843620390847), small = id(100876329507628),
	},
	Icon = {
		Rifle = id(135744056930553), Helmet = id(92362293232568), Case = id(109214386004462),
		Inventory = id(111960605063985), Challenge = id(85047453745111), Trade = id(138165878907579),
		Settings = id(71251472577854), Gift = id(120493391648901), Robux = id(128831873354021),
		Trophy = id(81544771645127), Req = id(115805213028426),
		-- v1 names still used by Pages
		Book = id(85047453745111), Gear = id(71251472577854), Shop = id(109214386004462), Money = id(111960605063985),
	},
	Rank = {
		id(86922899695300), id(99283456831770), id(135855890564742), id(137839602098948), id(115001036884075),
		id(107240198857894), id(79142276908428), id(109887267286961), id(105048808444395),
	},
	Pack = {},
}
-- v1 keys that Pages reads: tiles by colour name -> the new accent faces
G.A.Tile = {
	Purple = G.A.Face.violet, Blue = G.A.Face.blue, Orange = G.A.Face.magenta, Red = G.A.Face.dusk,
	Green = G.A.Face.cyan, Yellow = G.A.Face.aurora, Rainbow = G.A.Face.aurora,
}
G.A.Pack.Target = G.A.Icon.Challenge
G.A.Pack.Backpack = G.A.Icon.Inventory
G.A.Pack.Trophy = G.A.Icon.Trophy

G.F = {
	Fredoka = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	Black = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	Bold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
}

local function rgb(h)
	return Color3.fromHex(h)
end
G.C = {
	Ink = rgb("05060d"),
	Panel = rgb("0b0c1c"),
	Panel2 = rgb("14163a"),
	Panel3 = rgb("1d2050"),
	White = Color3.new(1, 1, 1),
	Muted = rgb("aab2dc"),
	Cyan = rgb("7cf3ff"),
	Blue = rgb("3a6dff"),
	Violet = rgb("8b5cff"),
	Lilac = rgb("c4a8ff"),
	Magenta = rgb("ff3fd2"),
	Pink = rgb("ff7ad9"),
	Gold = rgb("ffd36a"),
	Green = rgb("7cf3ff"),
	Red = rgb("ff3f7f"),
	Orange = rgb("ff8a3d"),
	Purple = rgb("8b5cff"),
	TeamBlue = rgb("4f8dff"),
	TeamRed = rgb("ff4f7f"),
}
local C = G.C

-- accent families: top, mid, deep, edge light, glow, angle
G.ACC = {
	cyan = { "9dfaff", "16c8ff", "1648e0", "c8fdff", "16c8ff", 180 },
	blue = { "a9c4ff", "3a6dff", "1b1aa8", "cfdcff", "3a6dff", 180 },
	violet = { "dcc8ff", "8b5cff", "3f17b5", "e6dbff", "8b5cff", 180 },
	magenta = { "ffb8ef", "ff3fd2", "7d1ccf", "ffd6f6", "ff3fd2", 180 },
	aurora = { "9dfaff", "4f7dff", "8b2cff", "d8f7ff", "6e78ff", 160 },
	dusk = { "a9c4ff", "6a4dff", "c42ac8", "e2d6ff", "aa50ff", 160 },
	hot = { "ffb0c8", "ff3f7f", "9a1a6b", "ffd0de", "ff3f7f", 180 },
	glass = { "1d2050", "14163a", "0b0c1c", "7cf3ff", "3a6dff", 180 },
}
-- v1 colour names (Pages) -> accents
local NAME = { Green = "cyan", Blue = "blue", Purple = "violet", Yellow = "violet", Red = "hot", Orange = "magenta", Rainbow = "aurora", White = "glass" }
local function acc(name)
	return G.ACC[name] and name or NAME[name] or "blue"
end
G.acc = acc
function G.accColor(name)
	return rgb(G.ACC[acc(name)][5])
end

local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale

-- ─── basics ────────────────────────────────────────────────────────────────────────────
function G.new(class, props, parent)
	local o = Instance.new(class)
	if props then
		for k, v in props do
			o[k] = v
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local new = G.new

function G.tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
local tween = G.tween

function G.corner(o, r)
	return new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r or 12) }, o)
end

function G.stroke(o, th, col, transparency)
	return new("UIStroke", {
		Thickness = th or 3, Color = col or C.Ink, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
end

function G.abbrev(n)
	n = tonumber(n) or 0
	if n >= 1e6 then
		return (string.format("%.1fM", n / 1e6):gsub("%.0M", "M"))
	elseif n >= 1e4 then
		return (string.format("%.1fK", n / 1e3):gsub("%.0K", "K"))
	end
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function G.clock(sec)
	sec = math.max(0, math.floor(sec))
	local d = sec // 86400
	if d > 0 then
		return string.format("%dd %dh", d, (sec % 86400) // 3600)
	end
	return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function gradSeq(a)
	local t = G.ACC[acc(a)]
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(t[1])),
		ColorSequenceKeypoint.new(0.5, rgb(t[2])),
		ColorSequenceKeypoint.new(1, rgb(t[3])),
	})
end
G.gradSeq = gradSeq

-- outlined text: white fill, ink stroke
function G.text(parent, p)
	local l = new("TextLabel", {
		Name = p.Name or "Text", BackgroundTransparency = 1,
		Position = p.Position or O(0, 0), Size = p.Size or S(1, 1), AnchorPoint = p.AnchorPoint or V2(0, 0),
		Text = p.Text or "", FontFace = p.Font or G.F.Fredoka, TextSize = p.TextSize or 28,
		TextColor3 = p.Color or C.White, TextXAlignment = p.X or Enum.TextXAlignment.Center,
		TextYAlignment = p.Y or Enum.TextYAlignment.Center, TextScaled = p.Scaled or false,
		TextWrapped = p.Wrapped or false, RichText = p.Rich or false, ZIndex = p.ZIndex or 1,
		LayoutOrder = p.LayoutOrder or 0, AutomaticSize = p.Auto or Enum.AutomaticSize.None,
		TextTransparency = p.Transparency or 0,
	}, parent)
	if p.Scaled and p.MaxSize then
		new("UITextSizeConstraint", { MaxTextSize = p.MaxSize }, l)
	end
	if (p.Stroke or 2.6) > 0 then
		new("UIStroke", { Thickness = p.Stroke or 2.6, Color = p.StrokeColor or C.Ink, LineJoinMode = Enum.LineJoinMode.Round, Transparency = p.StrokeTransparency or 0 }, l)
	end
	if p.Gradient then
		new("UIGradient", { Color = p.Gradient }, l)
	end
	return l
end

-- ─── sound ─────────────────────────────────────────────────────────────────────────────
local SOUNDS = {
	Hover = { "rbxasset://sounds/clickfast.wav", 0.12, 1.55 },
	Click = { "rbxasset://sounds/switch.wav", 0.3, 1.25 },
	Open = { "rbxasset://sounds/swoosh.wav", 0.22, 1.35 },
	Close = { "rbxasset://sounds/swoosh.wav", 0.18, 1.0 },
	Deny = { "rbxasset://sounds/switch.wav", 0.24, 0.6 },
	Play = { "rbxassetid://9126073318", 0.4, 0.9 },
	Found = { "rbxasset://sounds/electronicpingshort.wav", 0.5, 1.0 },
}
G.SoundGroup = nil
function G.sound(name)
	local spec = SOUNDS[name]
	if not spec then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = spec[1], spec[2], spec[3]
	s.SoundGroup = G.SoundGroup
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

-- ─── motion ─────────────────────────────────────────────────────────────────────────────
local shines = {}
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for band, spec in shines do
		if not band.Parent then
			shines[band] = nil
		elseif band.Visible then
			local p = ((t + spec.Delay) % spec.Period) / spec.Period
			local k = math.clamp((p - 0.6) / 0.22, 0, 1)
			k = k * k * (3 - 2 * k)
			band.Position = UDim2.fromScale(-0.45 + 1.8 * k, 0.5)
		end
	end
end)
function G.shine(parent, delay, period, width)
	local band = new("Frame", { Name = "Shine", AnchorPoint = V2(0, 0.5), Position = S(-0.45, 0.5), Size = UDim2.new(width or 0.24, 0, 1.6, 0), Rotation = 20, BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 3 }, parent)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.28), NumberSequenceKeypoint.new(1, 1) }) }, band)
	shines[band] = { Delay = delay or 0, Period = period or 4.4 }
	return band
end

function G.press(btn, onClick, opts)
	opts = opts or {}
	local sc = btn:FindFirstChildOfClass("UIScale") or new("UIScale", {}, btn)
	local hovering, down = false, false
	local function target()
		if btn:GetAttribute("Disabled") then
			return 1
		end
		return if down then 0.93 elseif hovering then (opts.Hover or 1.06) else 1
	end
	local function upd(t)
		tween(sc, t or 0.14, { Scale = target() }, Enum.EasingStyle.Back)
		if opts.OnHover then
			opts.OnHover(hovering and not btn:GetAttribute("Disabled"))
		end
	end
	btn.MouseEnter:Connect(function()
		hovering = true
		if not btn:GetAttribute("Disabled") then
			G.sound("Hover")
		end
		upd()
	end)
	btn.MouseLeave:Connect(function()
		hovering, down = false, false
		upd()
	end)
	btn.MouseButton1Down:Connect(function()
		down = true
		upd(0.06)
	end)
	btn.MouseButton1Up:Connect(function()
		down = false
		upd()
	end)
	btn.SelectionGained:Connect(function()
		hovering = true
		upd()
	end)
	btn.SelectionLost:Connect(function()
		hovering = false
		upd()
	end)
	btn.Activated:Connect(function()
		if btn:GetAttribute("Disabled") then
			G.sound("Deny")
			return
		end
		if opts.Sound ~= false then
			G.sound(opts.Sound or "Click")
		end
		sc.Scale = 0.9
		tween(sc, 0.25, { Scale = target() }, Enum.EasingStyle.Back)
		if onClick then
			task.spawn(onClick)
		end
	end)
	return sc
end

function G.setDisabled(btn, off)
	btn:SetAttribute("Disabled", off and true or nil)
	local art = btn:FindFirstChild("Art")
	if art and art:IsA("ImageLabel") then
		art.ImageColor3 = if off then Color3.fromRGB(110, 112, 130) else Color3.new(1, 1, 1)
	elseif btn:IsA("ImageButton") or btn:IsA("ImageLabel") then
		btn.ImageColor3 = if off then Color3.fromRGB(110, 112, 130) else Color3.new(1, 1, 1)
	end
	local face = btn:FindFirstChild("Face")
	if face and face:IsA("Frame") then
		local g = face:FindFirstChild("Off")
		if off and not g then
			local cover = new("Frame", { Name = "Off", Size = S(1, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.45, ZIndex = 8 }, face)
			local uc = face:FindFirstChildOfClass("UICorner")
			G.corner(cover, uc and uc.CornerRadius or UDim.new(0, 12))
		elseif not off and g then
			g:Destroy()
		end
	elseif face and face:IsA("ImageLabel") then
		face.ImageColor3 = if off then Color3.fromRGB(110, 112, 130) else Color3.new(1, 1, 1)
	end
end

function G.glow(parent, p)
	return new("ImageLabel", {
		Name = p.Name or "Glow", BackgroundTransparency = 1, Image = G.A.Glow, ImageColor3 = p.Color or C.Cyan,
		ImageTransparency = p.Transparency or 0.4, AnchorPoint = p.AnchorPoint or V2(0.5, 0.5),
		Position = p.Position or S(0.5, 0.5), Size = p.Size or S(1.4, 1.4), ZIndex = p.ZIndex or 0,
	}, parent)
end

function G.surface(frame, accent, p)
	p = p or {}
	local t = G.ACC[acc(accent)]
	local r = p.Radius or UDim.new(0, 18)
	frame.BackgroundColor3 = C.White
	frame.BackgroundTransparency = p.Transparency or 0
	frame.BorderSizePixel = 0
	G.corner(frame, r)
	new("UIGradient", { Color = gradSeq(accent), Rotation = (p.Angle or t[6]) - 90 }, frame)
	G.stroke(frame, p.Outline or 4, C.Ink)
	local inner = new("Frame", { Name = "Surface", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = frame.ZIndex }, frame)
	local rim = new("Frame", { Name = "Rim", BackgroundTransparency = 1, Position = O(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = frame.ZIndex }, inner)
	G.corner(rim, UDim.new(r.Scale, math.max(0, r.Offset - 2)))
	G.stroke(rim, 2, rgb(t[4]), 0.15)
	if p.Split ~= false then
		local split = new("Frame", { Name = "Split", BackgroundColor3 = C.White, Size = S(1, 1), ZIndex = frame.ZIndex }, inner)
		G.corner(split, r)
		new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.84), NumberSequenceKeypoint.new(0.499, 0.84), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }) }, split)
	end
	if p.Dots ~= false then
		local dots = new("ImageLabel", { Name = "Dots", BackgroundTransparency = 1, Image = G.A.Dots, ScaleType = Enum.ScaleType.Tile, TileSize = O(8, 8), ImageTransparency = 0.7, Size = S(1, 1), ZIndex = frame.ZIndex }, inner)
		G.corner(dots, r)
		new("UIGradient", { Rotation = p.DotsRotation or 225, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }) }, dots)
	end
	if p.Gloss ~= false then
		local gloss = new("Frame", { Name = "Gloss", BackgroundColor3 = C.White, Position = S(0.04, 0.03), Size = S(0.92, 0.42), ZIndex = frame.ZIndex }, inner)
		G.corner(gloss, r)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.6, 1) }, gloss)
	end
	return inner
end

function G.glass(parent, p)
	p = p or {}
	local f = new(p.Class or "Frame", {
		Name = p.Name or "Glass", Position = p.Position or O(0, 0), Size = p.Size or O(300, 60), AnchorPoint = p.AnchorPoint or V2(0, 0),
		BackgroundColor3 = C.White, BackgroundTransparency = p.Transparency or 0.15, BorderSizePixel = 0, LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1, ClipsDescendants = p.Clip or false,
	}, parent)
	if f:IsA("TextButton") then
		f.Text = ""
		f.AutoButtonColor = false
	end
	G.corner(f, p.Radius or UDim.new(0, 22))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb("12142c"), rgb("07081a")) }, f)
	local st = G.stroke(f, p.EdgeWidth or 2, C.Cyan, p.EdgeTransparency or 0.75)
	if p.EdgeGradient ~= false then
		new("UIGradient", { Rotation = 0, Color = ColorSequence.new(C.Cyan, C.Lilac) }, st)
	end
	if p.TopLine ~= false then
		local line = new("Frame", { Name = "TopLine", BackgroundColor3 = C.White, BorderSizePixel = 0, Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(1, -36, 0, 2), ZIndex = f.ZIndex + 1 }, f)
		new("UIGradient", { Color = ColorSequence.new(C.Cyan, C.Lilac), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.1), NumberSequenceKeypoint.new(0.75, 0.1), NumberSequenceKeypoint.new(1, 1) }) }, line)
	end
	return f, st
end

-- ─── pieces ─────────────────────────────────────────────────────────────────────────────
local ICON_FIT = {
	normal = { S(0.06, -0.03), S(0.88, 0.88) },
	tall = { S(0.075, 0.005), S(0.85, 0.85) },
	low = { S(0.075, 0.045), S(0.85, 0.85) },
}
function G.tile(parent, p)
	local a = acc(p.Accent or p.Color or "blue")
	local t = G.ACC[a]
	local size = p.Size or 124
	local b = new("ImageButton", {
		Name = p.Name or "Tile", Size = O(size, size), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0),
		BackgroundTransparency = 1, Image = "", LayoutOrder = p.LayoutOrder or 0, AutoButtonColor = false,
	}, parent)
	local halo = G.glow(b, { Name = "Halo", Color = rgb(t[5]), Transparency = 0.3, Size = S(1.95, 1.95), ZIndex = 0 })
	local base = new("Frame", { Name = "Base", BackgroundColor3 = C.Ink, Position = O(0, 6), Size = S(1, 1), ZIndex = 1 }, b)
	G.corner(base, UDim.new(0.26, 0))
	new("ImageLabel", { Name = "Face", BackgroundTransparency = 1, Image = G.A.Face[a] or G.A.Face.blue, Size = S(1, 1), ZIndex = 2 }, b)
	local clip = new("CanvasGroup", { Name = "Clip", BackgroundTransparency = 1, Position = O(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 3 }, b)
	G.corner(clip, UDim.new(0.24, 0))
	new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = G.A.Glow, ImageTransparency = 0.25, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.42), Size = S(0.95, 0.95), ZIndex = 3 }, clip)
	G.shine(clip, p.Delay or 0, 4.4, 0.24)
	local fit = ICON_FIT[p.IconFit or "normal"]
	local holder = new("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Position = fit[1], Size = fit[2], ZIndex = 4 }, b)
	if p.Icon then
		new("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Image = p.Icon, ImageColor3 = C.Ink, ImageTransparency = 0.5, Position = O(0, 4), Size = S(1, 1), ScaleType = Enum.ScaleType.Fit, ZIndex = 4 }, holder)
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = p.Icon, Size = S(1, 1), ScaleType = Enum.ScaleType.Fit, ZIndex = 5 }, holder)
	end
	if p.Label then
		G.text(b, { Name = "Label", Text = p.Label, Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = V2(0.5, 0.62), Size = UDim2.new(1, 28, 0, 32), TextSize = p.TextSize or 24, Stroke = 3.4, ZIndex = 7 })
	end
	if p.Badge then
		G.badge(b, p.Badge)
	end
	local home = holder.Position
	G.press(b, p.OnClick, { Sound = p.Sound, Hover = 1.07, OnHover = function(on)
		tween(b, 0.2, { Rotation = if on then -1.5 else 0 })
		tween(halo, 0.25, { ImageTransparency = if on then 0 else 0.3, Size = if on then S(2.2, 2.2) else S(1.95, 1.95) })
		tween(holder, 0.28, { Position = if on then home - O(0, 7) else home, Rotation = if on then -6 else 0 }, Enum.EasingStyle.Back)
	end })
	return b, holder
end

function G.badge(parent, n)
	-- fixed-size pill pinned to the tile's top-right corner (AutomaticSize grew it with its own glow)
	local f = parent:FindFirstChild("Badge")
	if not f then
		f = new("Frame", { Name = "Badge", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = O(36, 34), BackgroundColor3 = C.White, ZIndex = 9 }, parent)
		G.corner(f, 12)
		G.stroke(f, 4, C.Ink)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb("ffb8ef")), ColorSequenceKeypoint.new(0.55, rgb("ff3fd2")), ColorSequenceKeypoint.new(1, rgb("a01cd0")) }) }, f)
		G.glow(f, { Name = "BadgeGlow", Color = C.Magenta, Transparency = 0.35, Size = UDim2.new(1, 34, 1, 34), ZIndex = 8 })
		G.text(f, { Name = "N", TextSize = 20, Stroke = 2.4, ZIndex = 10, Size = S(1, 1) })
		local sc = new("UIScale", {}, f)
		task.spawn(function()
			while f.Parent do
				tween(sc, 0.8, { Scale = 1.13 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(0.8)
				tween(sc, 0.8, { Scale = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(0.8)
			end
		end)
	end
	local s = tostring(n or "")
	f.N.Text = s
	f.Size = O(math.max(34, 16 + 12 * #s), 34)
	f.Visible = n ~= nil and n ~= 0 and n ~= ""
	return f
end

local CTA = {
	deploy = { "deploy", "cyan" }, cancel = { "cancel", "hot" }, modes = { "modes", "violet" },
	pass = { "pass", "magenta" }, small = { "small", "blue" },
}
function G.cta(parent, kind, p)
	local spec = CTA[kind] or CTA.small
	local w, h = p.Width or 340, p.Height or 80
	local z = p.ZIndex or 2
	local b = new("ImageButton", {
		Name = p.Name or "Cta", Size = O(w, h + 6), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0),
		BackgroundTransparency = 1, Image = "", AutoButtonColor = false,
		ZIndex = z, LayoutOrder = p.LayoutOrder or 0,
	}, parent)
	local bloom = G.glow(b, { Name = "Bloom", Color = G.accColor(spec[2]), Transparency = p.BloomTransparency or 0.55, Size = UDim2.new(1.3, 0, 2.6, 0), Position = S(0.5, 0.45), ZIndex = z - 1 })
	new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = G.A.Cta[spec[1]], ScaleType = Enum.ScaleType.Stretch, Size = S(1, 1), ZIndex = z }, b)
	local clip = new("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.new(0.07, 0, 0, 7), Size = UDim2.new(0.86, 0, 0, h - 14), ZIndex = z + 1 }, b)
	G.shine(clip, p.Delay or 0, 3.6, 0.14)
	local lab = G.text(b, { Name = "Label", Text = p.Text or "", Position = O(0, 0), Size = UDim2.new(1, 0, 0, h), Scaled = true, MaxSize = p.TextSize or 40, TextSize = p.TextSize or 40, Stroke = p.Stroke or 3.6, ZIndex = z + 3 })
	new("UIPadding", { PaddingTop = UDim.new(0, h * 0.18), PaddingBottom = UDim.new(0, h * 0.16), PaddingLeft = UDim.new(0, w * 0.1), PaddingRight = UDim.new(0, w * 0.1) }, lab)
	if p.Caption then
		G.text(b, { Name = "Caption", Text = p.Caption, Position = UDim2.new(0.5, 0, 1, 10), AnchorPoint = V2(0.5, 0), Size = O(w * 1.3, 32), TextSize = p.CaptionSize or 26, Stroke = 3, ZIndex = z + 3 })
	end
	if p.Breathe then
		task.spawn(function()
			while b.Parent do
				tween(bloom, 1.1, { ImageTransparency = 0.15, Size = UDim2.new(1.32, 0, 2.4, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(1.1)
				tween(bloom, 1.1, { ImageTransparency = 0.5, Size = UDim2.new(1.2, 0, 2.1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(1.1)
			end
		end)
	end
	G.press(b, p.OnClick, { Sound = p.Sound, Hover = 1.04 })
	return b
end
function G.setCta(b, kind)
	local spec = CTA[kind]
	b.Art.Image = G.A.Cta[spec[1]]
	b.Bloom.ImageColor3 = G.accColor(spec[2])
end

function G.wide(parent, p)
	local w = p.Width or 260
	local h = p.Height or math.floor(w / 2.6)
	local b = new("TextButton", {
		Name = p.Name or "Wide", Size = O(w, h), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0),
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = p.LayoutOrder or 0, ZIndex = p.ZIndex or 1,
	}, parent)
	local face = new("Frame", { Name = "Face", Size = S(1, 1), ZIndex = p.ZIndex or 1 }, b)
	G.surface(face, p.Color or "blue", { Radius = UDim.new(0, 16), Split = false })
	G.text(b, { Name = "Label", Text = p.Text or "", Position = S(0.5, 0.5), AnchorPoint = V2(0.5, 0.5), Size = S(0.84, 0.56), Scaled = true, MaxSize = p.TextSize or 40, Stroke = p.Stroke or 3.2, ZIndex = (p.ZIndex or 1) + 4 })
	if p.Caption then
		G.text(b, { Name = "Caption", Text = p.Caption, Position = UDim2.new(0.5, 0, 1, 10), AnchorPoint = V2(0.5, 0), Size = O(w * 1.3, 32), TextSize = p.CaptionSize or 26, Stroke = 3, ZIndex = (p.ZIndex or 1) + 4 })
	end
	G.press(b, p.OnClick, { Sound = p.Sound, Hover = 1.05 })
	return b
end

local SQUARE = { Plus = { "cyan", "plus" }, Close = { "hot", "x" }, Check = { "cyan", "check" }, Minus = { "blue", "minus" } }
local function bar(parent, cx, cy, len, rot, z)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(cx, cy), Size = UDim2.new(len, 0, 0.14, 0), Rotation = rot, BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = z }, parent)
	G.corner(f, UDim.new(1, 0))
	G.stroke(f, 3, C.Ink)
	return f
end
function G.square(parent, name, size, p)
	p = p or {}
	local spec = SQUARE[name] or { "blue", "plus" }
	local z = p.ZIndex or 5
	local b = new("TextButton", {
		Name = p.Name or name, Size = O(size, size), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0),
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = z, LayoutOrder = p.LayoutOrder or 0,
	}, parent)
	G.glow(b, { Color = G.accColor(spec[1]), Transparency = 0.35, Size = S(2.1, 2.1), ZIndex = z - 1 })
	local base = new("Frame", { Name = "Base", BackgroundColor3 = C.Ink, Position = O(0, 5), Size = S(1, 1), ZIndex = z }, b)
	G.corner(base, UDim.new(0.3, 0))
	local face = new("Frame", { Name = "Face", Size = S(1, 1), ZIndex = z }, b)
	G.surface(face, spec[1], { Radius = UDim.new(0.3, 0), Dots = false })
	local sym = new("Frame", { Name = "Symbol", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z + 2 }, b)
	if spec[2] == "plus" then
		bar(sym, 0.5, 0.5, 0.5, 0, z + 2)
		bar(sym, 0.5, 0.5, 0.5, 90, z + 2)
	elseif spec[2] == "x" then
		bar(sym, 0.5, 0.5, 0.55, 45, z + 2)
		bar(sym, 0.5, 0.5, 0.55, -45, z + 2)
	elseif spec[2] == "check" then
		bar(sym, 0.38, 0.6, 0.28, 45, z + 2)
		bar(sym, 0.58, 0.5, 0.5, -55, z + 2)
	else
		bar(sym, 0.5, 0.5, 0.5, 0, z + 2)
	end
	G.press(b, p.OnClick, { Sound = p.Sound })
	return b
end

function G.pill(parent, p)
	local h = p.Height or 60
	local f = G.glass(parent, { Name = p.Name or "Pill", Size = O(p.Width or 300, h), Position = p.Position, AnchorPoint = p.AnchorPoint, Radius = UDim.new(1, 0), TopLine = false, LayoutOrder = p.LayoutOrder })
	if p.Icon then
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = p.Icon, Size = O(h * 1.35, h * 1.35), AnchorPoint = V2(0.5, 0.5), Position = O(h * 0.3, h / 2), ZIndex = 3, ScaleType = Enum.ScaleType.Fit }, f)
	end
	local t = G.text(f, { Name = "Value", Text = p.Text or "", Position = O(h * 1.05, 0), Size = UDim2.new(1, -h * 1.2, 1, 0), X = Enum.TextXAlignment.Left, TextSize = p.TextSize or 36, Stroke = 2.6, ZIndex = 3 })
	return f, t
end

function G.shell(parent, p)
	local root = new("Frame", { Name = p.Name or "Modal", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.52), Size = O(p.Width or 1500, p.Height or 860), BackgroundTransparency = 1, ZIndex = 20, Visible = false }, parent)
	new("UIScale", { Name = "Pop" }, root)
	G.glow(root, { Name = "Aura", Color = C.Violet, Transparency = 0.7, Size = UDim2.new(1, 220, 1, 220), ZIndex = 19 })
	local body = G.glass(root, { Name = "Body", Size = S(1, 1), Radius = UDim.new(0, 30), Transparency = 0.06, EdgeWidth = 4, EdgeTransparency = 0.25, ZIndex = 20 })
	local ink = new("Frame", { Name = "Ink", BackgroundTransparency = 1, Position = O(-4, -4), Size = UDim2.new(1, 8, 1, 8), ZIndex = 20 }, body)
	G.corner(ink, 34)
	G.stroke(ink, 4, C.Ink)
	local content = new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, -80, 1, -110), Position = O(40, 78), ZIndex = 21 }, body)
	G.text(root, { Name = "Title", Text = p.Title or "", Position = O(48, -54), Size = O(900, 100), X = Enum.TextXAlignment.Left, TextSize = 80, Stroke = 5, ZIndex = 30 })
	local close = G.square(root, "Close", 84, { Name = "CloseX", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), ZIndex = 31, Sound = "Close", OnClick = p.OnClose })
	return root, content, nil, close
end

function G.openModal(root)
	root.Visible = true
	root.Pop.Scale = 0.82
	tween(root.Pop, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
	G.sound("Open")
end

function G.closeModal(root, after)
	tween(root.Pop, 0.14, { Scale = 0.88 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		root.Visible = false
		if after then
			after()
		end
	end)
end

function G.header(parent, p)
	local f = new("Frame", { Name = p.Name or "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, p.Height or 64), Position = p.Position or O(0, 0), LayoutOrder = p.LayoutOrder or 0, ZIndex = 22 }, parent)
	local t = G.text(f, { Text = p.Text, Size = S(1, 1), TextSize = p.TextSize or 50, Stroke = 3.5, ZIndex = 23 })
	for _, side in { 0, 1 } do
		local l = new("Frame", { BackgroundColor3 = C.White, BorderSizePixel = 0, AnchorPoint = V2(side, 0.5), Position = S(side, 0.5), Size = UDim2.new(0.5, -(p.Gap or 170), 0, 3), ZIndex = 22 }, f)
		new("UIGradient", { Color = ColorSequence.new(C.Cyan, C.Lilac), Transparency = NumberSequence.new(if side == 0 then 1 else 0.1, if side == 0 then 0.1 else 1) }, l)
	end
	return f, t
end

function G.bar(parent, p)
	local track = new("Frame", { Name = p.Name or "Bar", Size = p.Size or UDim2.new(1, 0, 0, 22), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0), BackgroundColor3 = rgb("1a1d3e"), ZIndex = p.ZIndex or 22 }, parent)
	G.corner(track, UDim.new(1, 0))
	G.stroke(track, 3, C.Ink)
	local fill = new("Frame", { Name = "Fill", Size = S(0, 1), BackgroundColor3 = C.White, ZIndex = (p.ZIndex or 22) + 1, Visible = false }, track)
	G.corner(fill, UDim.new(1, 0))
	local col = p.Color
	new("UIGradient", { Color = if typeof(col) == "Color3" and col ~= C.Cyan then ColorSequence.new(col:Lerp(C.White, 0.35), col) else ColorSequence.new(C.Cyan, C.Violet) }, fill)
	local function set(frac)
		frac = math.clamp(frac or 0, 0, 1)
		fill.Visible = frac > 0.001
		tween(fill, 0.5, { Size = S(math.max(frac, 0.04), 1) })
	end
	return track, set
end

function G.card(parent, p)
	local f = new(p.Button and "TextButton" or "Frame", {
		Name = p.Name or "Card", Size = p.Size or O(300, 200), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0),
		LayoutOrder = p.LayoutOrder or 0, ZIndex = p.ZIndex or 22,
	}, parent)
	if p.Button then
		f.Text = ""
		f.AutoButtonColor = false
	end
	if p.Accent then
		G.surface(f, p.Accent, { Radius = UDim.new(0, p.Radius or 20) })
		return f, f:FindFirstChildOfClass("UIStroke")
	end
	f.BackgroundColor3 = C.White
	f.BackgroundTransparency = 0.05
	G.corner(f, p.Radius or 20)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb("1a1d44"), rgb("0d0e24")) }, f)
	local st = G.stroke(f, p.StrokeWidth or 2, C.Cyan, 0.8)
	return f, st
end

function G.artCard(parent, p)
	local b = new(p.Button and "TextButton" or "Frame", {
		Name = p.Name or "ArtCard", Size = p.Size or O(270, 233), Position = p.Position or O(0, 0), AnchorPoint = p.AnchorPoint or V2(0, 0),
		LayoutOrder = p.LayoutOrder or 0, ZIndex = p.ZIndex or 22, BackgroundTransparency = 1,
	}, parent)
	if p.Button then
		b.Text = ""
		b.AutoButtonColor = false
	end
	local face = new("Frame", { Name = "Face", Size = S(1, 1), ZIndex = p.ZIndex or 22 }, b)
	if acc(p.Color or "Blue") == "glass" then
		face.BackgroundColor3 = C.White
		G.corner(face, 20)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb("1a1d44"), rgb("0d0e24")) }, face)
		G.stroke(face, 2, C.Cyan, 0.8)
	else
		G.surface(face, p.Color or "Blue", { Radius = UDim.new(0, 20) })
	end
	if p.Button then
		G.press(b, p.OnClick, { Hover = 1.03 })
	end
	return b
end

-- ─── ranks: the user's nine badges ──────────────────────────────────────────────────────
G.RANKS = {
	{ "Wood", 1, 9, "d6965a" }, { "Bronze", 10, 19, "e68c64" }, { "Silver", 20, 29, "d2e1ff" },
	{ "Gold", 30, 39, "ffcd50" }, { "Elite", 40, 49, "ffdc82" }, { "Platinum", 50, 64, "c8d7f0" },
	{ "Diamond", 65, 79, "50dcff" }, { "Mythic", 80, 99, "ff3c8c" }, { "Legend", 100, 100, "ffc83c" },
}
function G.RankFor(level)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, 100)
	local idx = 1
	for i, r in G.RANKS do
		if level >= r[2] and level <= r[3] then
			idx = i
			break
		end
	end
	local r, n = G.RANKS[idx], G.RANKS[idx + 1]
	return G.A.Rank[idx], r[1], idx, rgb(r[4]), n and n[1], n and n[2]
end

return G
