--!nocheck
--[[
	HS — VantageShot component kit, reconstructed from the Hypershot lobby captures (2026-11-16).
	All geometry is in 1920x1080 design px, measured from the 2940x1650 reference (x 0.6531).
	Bar and tile skins are layered PNGs rendered from the measured construction:
	  drop · border (per-edge colour/thickness) · lip · rim · measured face gradient · halftone · streaks.
	Text is live (FredokaOne + UIStroke) so labels can change; stroke thickness follows the HUD scale.
]]
local TweenService = game:GetService("TweenService")

local HS = {}

local function id(n)
	return "rbxassetid://" .. n
end

HS.Img = {
	BarOrange = id(99084093357726),
	BarGreen = id(121429764999053),
	BarPurple = id(80324743939505),
	BarRed = id(97111494385139),
	MaskSide = id(117618763063963),
	MaskSpawn = id(124880571842456),
	TileBlue = id(83303798085879),
	TileRed = id(101664708934291),
	TilePurple = id(118295492599643),
	TileGold = id(93088511839676),
	MaskTile = id(101038552267145),
	Req = id(115805213028426),
	Cases = id(81078832196281),
	Shop = id(140631027553026),
}
HS.CasesIcon = HS.Img.Cases

HS.Font = Font.new("rbxasset://fonts/families/FredokaOne.json")
HS.Mont = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
HS.MontX = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
HS.MontXI = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic)
HS.Ink = Color3.fromRGB(14, 14, 22)
HS.Black = Color3.fromRGB(0, 0, 0)

HS.Bars = {
	orange = { Image = HS.Img.BarOrange, Mask = HS.Img.MaskSide, W = 295.5, H = 69.5, TX = 147.7, TY = 35.5 },
	purple = { Image = HS.Img.BarPurple, Mask = HS.Img.MaskSide, W = 295.5, H = 69.5, TX = 148.2, TY = 34.8 },
	green = { Image = HS.Img.BarGreen, Mask = HS.Img.MaskSpawn, W = 356, H = 82.5, TX = 177.9, TY = 41.1 },
	red = { Image = HS.Img.BarRed, Mask = HS.Img.MaskSpawn, W = 356, H = 82.5, TX = 177.9, TY = 41.1 },
}
HS.Tiles = {
	blue = { Image = HS.Img.TileBlue, Ink = Color3.fromRGB(16, 40, 46) },
	red = { Image = HS.Img.TileRed, Ink = Color3.fromRGB(46, 16, 40) },
	purple = { Image = HS.Img.TilePurple, Ink = Color3.fromRGB(24, 18, 54) },
	gold = { Image = HS.Img.TileGold, Ink = Color3.fromRGB(48, 28, 14) },
}

local strokes = setmetatable({}, { __mode = "k" })
HS.Scale = 1

-- light streak that sweeps across menu buttons, cut to the button's own shape (its mask image)
local streaks = {} -- strong on purpose: weak Instance keys get collected and the streak stops
local streakConn
local STREAK_EVERY, STREAK_DUR = 3.4, 0.85
function HS.streak(btn, mask, z)
	local s = Instance.new("ImageLabel")
	s.Name = "Streak"
	s.Image = mask
	s.BackgroundTransparency = 1
	s.ImageColor3 = Color3.new(1, 1, 1)
	s.Size = UDim2.fromScale(1, 1)
	s.ZIndex = z
	local g = Instance.new("UIGradient")
	g.Rotation = 20
	g.Offset = Vector2.new(-1, 0)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.36, 1),
		NumberSequenceKeypoint.new(0.47, 0.25),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.53, 0.25),
		NumberSequenceKeypoint.new(0.64, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = s
	s.Parent = btn
	HS._runStreak(g)
	return s
end

function HS._runStreak(g)
	streaks[g] = math.random() * STREAK_EVERY
	if not streakConn then
		streakConn = game:GetService("RunService").RenderStepped:Connect(function()
			local t = os.clock()
			for gr, ph in streaks do
				local host = gr.Parent
				if not host or not host.Parent then
					streaks[gr] = nil -- destroyed
				else
					local u = ((t + ph) % STREAK_EVERY) / STREAK_DUR
					gr.Offset = Vector2.new(if u < 1 then -1 + 2 * u else 1, 0)
				end
			end
		end)
	end
end

-- streak for rounded-rect buttons (Frames / TextButtons with a UICorner)
function HS.sheen(target, corner, z, strength)
	local s = Instance.new("Frame")
	s.Name = "Streak"
	s.BackgroundColor3 = Color3.new(1, 1, 1)
	s.BorderSizePixel = 0
	s.Size = UDim2.fromScale(1, 1)
	s.ZIndex = z or (target.ZIndex + 1)
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = corner
		c.Parent = s
	end
	local pk = strength or 0.3
	local g = Instance.new("UIGradient")
	g.Rotation = 20
	g.Offset = Vector2.new(-1, 0)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.38, 1),
		NumberSequenceKeypoint.new(0.5, pk),
		NumberSequenceKeypoint.new(0.62, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = s
	s.Parent = target
	HS._runStreak(g)
	return s
end

function HS.new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props or {} do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local new = HS.new

function HS.tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- UIStroke thickness does not follow UIScale, so kit strokes are registered and rescaled
function HS.stroke(o, th, col, tr)
	local s = new("UIStroke", { Thickness = th * HS.Scale, Color = col or HS.Black, Transparency = tr or 0, LineJoinMode = Enum.LineJoinMode.Round }, o)
	if o:IsA("GuiButton") or o:IsA("Frame") then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- TextButtons are containers here; only TextLabels get text outlines
	end
	strokes[s] = th
	return s
end
function HS.setScale(s)
	HS.Scale = s
	for st, th in strokes do
		if st.Parent then
			st.Thickness = th * s
		end
	end
end

function HS.corner(o, r)
	return new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r) }, o)
end

-- shrink-to-fit on ONE line: measure the text at its design size and scale down to the box width
local TextService = game:GetService("TextService")
function HS.fit(t, maxSize)
	maxSize = math.floor(maxSize)
	local w = t.Size.X.Offset
	if t.Size.X.Scale ~= 0 or w <= 0 then
		-- scale-sized box: let Roblox scale, but keep the box one line tall so it can't wrap
		t.TextScaled = true
		local c = t:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		c.MaxTextSize = maxSize c.MinTextSize = 6 c.Parent = t
		return
	end
	local busy = false
	local function refit()
		if busy then return end
		busy = true
		local pr = Instance.new("GetTextBoundsParams")
		pr.Text = t.Text pr.Font = t.FontFace pr.Size = maxSize pr.Width = 100000 pr.RichText = t.RichText
		local ok, bnd = pcall(TextService.GetTextBoundsAsync, TextService, pr)
		local room = (t.Size.X.Scale == 0 and t.Size.X.Offset or w) - 8
		if ok and bnd.X > room then
			t.TextSize = math.max(6, math.floor(maxSize * room / bnd.X))
		else
			t.TextSize = maxSize
		end
		busy = false
	end
	t.TextScaled = false
	t.TextSize = maxSize
	task.spawn(refit)
	t:GetPropertyChangedSignal("Text"):Connect(function() task.spawn(refit) end)
	t:GetPropertyChangedSignal("Size"):Connect(function() task.spawn(refit) end)
	t:GetPropertyChangedSignal("FontFace"):Connect(function() task.spawn(refit) end)
end

function HS.text(parent, p)
	local t = new("TextLabel", {
		Name = p.Name or "Label",
		BackgroundTransparency = 1,
		Text = p.Text or "",
		FontFace = p.Font or HS.Font,
		TextSize = p.TextSize or 24,
		TextColor3 = p.Color or Color3.new(1, 1, 1),
		TextXAlignment = p.X or Enum.TextXAlignment.Center,
		TextYAlignment = p.Y or Enum.TextYAlignment.Center,
		AnchorPoint = p.AnchorPoint or Vector2.new(0, 0),
		Position = p.Position or UDim2.new(),
		Size = p.Size or UDim2.fromScale(1, 1),
		ZIndex = p.ZIndex or 3,
		RichText = p.Rich or false,
		TextWrapped = false,
	}, parent)
	if p.Stroke and p.Stroke > 0 then
		HS.stroke(t, p.Stroke, p.StrokeColor or HS.Ink)
	end
	if p.Fit ~= false then
		HS.fit(t, p.TextSize or 24)
	end
	return t
end

local SoundService = game:GetService("SoundService")
local SOUNDS = {
	Hover = { id(133432321810855), 0.35 },
	Click = { id(102705143114378), 0.5 },
	Tab = { id(101958858678403), 0.5 },
	Select = { id(122755406072761), 0.5 },
	Toggle = { id(104813282067857), 0.5 },
	Purchase = { id(102619312277180), 0.6 },
	Deny = { id(101979595621741), 0.5 },
}
HS.SoundGroup = nil
function HS.sound(name)
	local s = SOUNDS[name]
	if not s then
		return
	end
	local snd = new("Sound", { SoundId = s[1], Volume = s[2], SoundGroup = HS.SoundGroup }, SoundService)
	snd:Play()
	game:GetService("Debris"):AddItem(snd, 3)
end

-- hover lifts and brightens, press sinks and darkens; the skin itself never changes
function HS.press(btn, onClick, o)
	o = o or {}
	local sc = btn:FindFirstChild("Pop") or new("UIScale", { Name = "Pop" }, btn)
	local ov = o.Overlay
	local hov, down = false, false
	local function upd(t)
		local off = btn:GetAttribute("Disabled")
		local s = if off then 1 elseif down then (o.Press or 0.94) elseif hov then (o.Hover or 1.05) else 1
		HS.tween(sc, t or 0.16, { Scale = s }, if down then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
		if ov then
			if off then
				HS.tween(ov, 0.1, { ImageTransparency = 1 })
			elseif down then
				ov.ImageColor3 = Color3.new(0, 0, 0)
				HS.tween(ov, 0.05, { ImageTransparency = 0.78 })
			elseif hov then
				ov.ImageColor3 = Color3.new(1, 1, 1)
				HS.tween(ov, 0.12, { ImageTransparency = 0.84 })
			else
				HS.tween(ov, 0.18, { ImageTransparency = 1 })
			end
		end
	end
	btn.MouseEnter:Connect(function()
		hov = true
		if not btn:GetAttribute("Disabled") then
			HS.sound("Hover")
		end
		upd()
	end)
	btn.MouseLeave:Connect(function()
		hov, down = false, false
		upd()
	end)
	btn.MouseButton1Down:Connect(function()
		down = true
		upd(0.05)
	end)
	btn.MouseButton1Up:Connect(function()
		down = false
		upd()
	end)
	btn.Activated:Connect(function()
		if btn:GetAttribute("Disabled") then
			HS.sound("Deny")
			return
		end
		if o.Sound ~= false then
			HS.sound(o.Sound or "Click")
		end
		if onClick then
			task.spawn(onClick)
		end
	end)
	btn:GetAttributeChangedSignal("Disabled"):Connect(function()
		upd()
	end)
	return sc
end

function HS.setDisabled(btn, off)
	btn:SetAttribute("Disabled", off and true or nil)
	if btn:IsA("ImageButton") then
		HS.tween(btn, 0.15, { ImageColor3 = if off then Color3.fromRGB(150, 150, 150) else Color3.new(1, 1, 1) })
	end
end

function HS.bar(parent, kind, p)
	local k = HS.Bars[kind]
	local z = p.ZIndex or 4
	local b = new("ImageButton", {
		Name = p.Name or "Bar",
		Image = k.Image,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(k.W, k.H),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.new(0, 0),
		ZIndex = z,
	}, parent)
	local ov = new("ImageLabel", { Name = "Overlay", Image = k.Mask, BackgroundTransparency = 1, ImageTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z + 1 }, b)
	HS.streak(b, k.Mask, z + 1)
	local lab = HS.text(b, {
		Name = "Label",
		Text = p.Text,
		TextSize = p.TextSize or 30,
		Stroke = p.Stroke or 4.6,
		StrokeColor = HS.Ink,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(k.TX, k.TY),
		Size = UDim2.fromOffset(k.W - 40, k.H),
		ZIndex = z + 2,
	})
	local cap
	if p.Caption then
		cap = HS.text(b, {
			Name = "Caption",
			Text = p.Caption,
			TextSize = p.CaptionSize or 22,
			Stroke = 2.8,
			StrokeColor = Color3.fromRGB(25, 25, 25),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(k.TX, p.CaptionTop or (k.H + 8)),
			Size = UDim2.fromOffset(k.W + 120, (p.CaptionSize or 22) + 4),
			ZIndex = z,
		})
	end
	b:SetAttribute("Kind", kind)
	HS.press(b, p.OnClick, { Overlay = ov, Sound = p.Sound, Hover = 1.04, Press = 0.95 })
	return b, lab, cap
end

function HS.setBar(b, kind)
	local k = HS.Bars[kind]
	if b:GetAttribute("Kind") == kind then
		return
	end
	b:SetAttribute("Kind", kind)
	b.Image = k.Image
	b.Overlay.Image = k.Mask
	if b:FindFirstChild("Streak") then
		b.Streak.Image = k.Mask
	end
end

function HS.tile(parent, kind, p)
	local k = HS.Tiles[kind]
	local b = new("ImageButton", {
		Name = p.Name or "Tile",
		Image = k.Image,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(91, 91),
		Position = p.Position or UDim2.new(),
		ZIndex = 3,
	}, parent)
	local ov = new("ImageLabel", { Name = "Overlay", Image = HS.Img.MaskTile, BackgroundTransparency = 1, ImageTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, b)
	HS.streak(b, HS.Img.MaskTile, 4)
	local icon = new("ImageLabel", {
		Name = "Icon",
		Image = p.Icon or "",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(45.5, 39.5),
		Size = UDim2.fromOffset(p.IconSize or 72, p.IconSize or 72),
		ZIndex = 5,
	}, b)
	local lab = HS.text(b, {
		Name = "Label",
		Text = p.Label or p.Name,
		TextSize = 24,
		Stroke = 6.6,
		StrokeColor = k.Ink,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(45.5, 69),
		Size = UDim2.fromOffset(150, 26),
		ZIndex = 6,
	})
	HS.press(b, p.OnClick, { Overlay = ov, Hover = 1.07, Press = 0.93 })
	return b, icon, lab
end

function HS.badge(btn, value)
	local bd = btn:FindFirstChild("Badge")
	if not value then
		if bd then
			bd.Visible = false
		end
		return
	end
	if not bd then
		bd = new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 8), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromRGB(235, 52, 52), ZIndex = 8, AutomaticSize = Enum.AutomaticSize.X }, btn)
		HS.corner(bd, 8)
		HS.stroke(bd, 2.6, Color3.fromRGB(40, 10, 10))
		new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, bd)
		local t = HS.text(bd, { Name = "T", TextSize = 16, Fit = false, Stroke = 2.4, StrokeColor = Color3.fromRGB(60, 10, 10), Size = UDim2.new(0, 0, 1, 0), ZIndex = 9 })
		t.AutomaticSize = Enum.AutomaticSize.X
	end
	bd.T.Text = tostring(value)
	bd.Visible = true
end

function HS.pill(parent, p)
	local f = new("TextButton", { Name = p.Name or "Pill", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), Position = p.Position, Size = p.Size, ZIndex = 3 }, parent)
	HS.corner(f, UDim.new(0.5, 0))
	HS.stroke(f, 3.3, Color3.fromRGB(26, 14, 16))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 88)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(236, 66, 66)), ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 98, 98)) }) }, f)
	HS.sheen(f, UDim.new(0.5, 0), 3, 0.25)
	HS.text(f, { Text = p.Text, TextSize = p.TextSize or 28, ZIndex = 4 })
	HS.press(f, p.OnClick, { Hover = 1.05 })
	return f
end

function HS.topChip(parent, p)
	local w = p.Width or 44
	local b = new("TextButton", { Name = p.Name, Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, Size = UDim2.fromOffset(w, 44), LayoutOrder = p.Order or 0 }, parent)
	HS.corner(b, UDim.new(1, 0))
	HS.sheen(b, UDim.new(1, 0), b.ZIndex, 0.55)
	new("ImageLabel", { Name = "Icon", Image = p.Icon or "", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Position = UDim2.fromOffset(if p.Label then 8 else 7, 7), Size = UDim2.fromOffset(30, 30) }, b)
	if p.Label then
		new("TextLabel", { BackgroundTransparency = 1, Text = p.Label, FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold), TextSize = 21, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -52, 1, 0) }, b)
	end
	b.MouseEnter:Connect(function()
		HS.tween(b, 0.12, { BackgroundTransparency = 0.12 })
		HS.sound("Hover")
	end)
	b.MouseLeave:Connect(function()
		HS.tween(b, 0.15, { BackgroundTransparency = 0.3 })
	end)
	b.Activated:Connect(function()
		HS.sound("Click")
		if p.OnClick then
			task.spawn(p.OnClick)
		end
	end)
	return b
end

function HS.currency(parent, p)
	local f = new("Frame", { Name = p.Name or "Currency", BackgroundTransparency = 1, Position = p.Position, Size = UDim2.fromOffset(268, 42.5) }, parent)
	local plus = new("TextButton", { Name = "Plus", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(38, 58, 82), Position = UDim2.fromOffset(26.3, 0), Size = UDim2.fromOffset(42.5, 42.5), ZIndex = 3 }, f)
	HS.corner(plus, 10)
	local face = new("Frame", { Name = "Face", BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(3.3, 3.3), Size = UDim2.new(1, -6.6, 1, -6.6), ZIndex = 3 }, plus)
	HS.corner(face, 7.5)
	HS.sheen(face, UDim.new(0, 7.5), 3, 0.3)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(128, 228, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(64, 172, 244)) }) }, face)
	HS.text(face, { Text = "+", Font = HS.MontX, TextSize = 34, Stroke = 1.6, StrokeColor = Color3.fromRGB(110, 110, 120), ZIndex = 4, Position = UDim2.fromOffset(0, -1) })
	HS.press(plus, p.OnPlus, { Hover = 1.08 })
	local pill = new("Frame", { Name = "Pill", BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(73.2, 0), Size = UDim2.fromOffset(194.6, 42.5), ZIndex = 2 }, f)
	HS.corner(pill, UDim.new(0.5, 0))
	HS.stroke(pill, 3.3, Color3.new(0, 0, 0))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(48, 50, 56), Color3.fromRGB(22, 24, 28)) }, pill)
	new("ImageLabel", { Name = "Icon", Image = p.Icon or HS.Img.Req, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(102.5, 21.25), Size = UDim2.fromOffset(46, 46), ZIndex = 4 }, f)
	if p.Coin == "ORD" and not p.Icon then
		f.Icon.Visible = false
		HS.ordCoin(f, { Position = UDim2.fromOffset(102.5, 21.25), Size = UDim2.fromOffset(43, 43), ZIndex = 4 })
	end
	local val = HS.text(pill, { Name = "Value", Text = "0", Font = HS.MontX, TextSize = 30, X = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -66, 1, 0), ZIndex = 3 })
	return f, val, plus
end

-- 2026-11-17: Ordnance (ORD) emblem, drawn in UI (no image uploaded yet): amber coin, dark rim, inner disc,
-- an ammo-round glyph and a gloss spot. p = { Position, Size (square), AnchorPoint, ZIndex, Name }
local OrdCfgHS = nil
function HS.ordCoin(parent, p)
	p = p or {}
	local z = p.ZIndex or 4
	if OrdCfgHS == nil then
		local ok, c = pcall(function() return require(game:GetService("ReplicatedStorage").Vantage:WaitForChild("Ordnance"):WaitForChild("OrdnanceConfig")) end)
		OrdCfgHS = if ok then c else false
	end
	if OrdCfgHS and OrdCfgHS.Icon then
		-- uploaded coin art + a light sweep cut to the coin's silhouette (shared HS streak loop)
		local img = new("ImageLabel", { Name = p.Name or "OrdCoin", BackgroundTransparency = 1, Image = OrdCfgHS.Icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = p.AnchorPoint or Vector2.new(0.5, 0.5), Position = p.Position or UDim2.fromScale(0.5, 0.5), Size = p.Size or UDim2.fromOffset(40, 40), ZIndex = z }, parent)
		if OrdCfgHS.IconMask then
			local st = HS.streak(img, OrdCfgHS.IconMask, z)
			st.ScaleType = Enum.ScaleType.Fit
		end
		return img
	end
	local RGB = Color3.fromRGB
	local f = new("Frame", { Name = p.Name or "OrdCoin", BackgroundTransparency = 1, AnchorPoint = p.AnchorPoint or Vector2.new(0.5, 0.5), Position = p.Position or UDim2.fromScale(0.5, 0.5), Size = p.Size or UDim2.fromOffset(40, 40), ZIndex = z }, parent)
	new("UIAspectRatioConstraint", {}, f)
	local function disc(name, scale, col, zz, par)
		local d = new("Frame", { Name = name, BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(scale, scale), ZIndex = zz }, par or f)
		HS.corner(d, UDim.new(0.5, 0))
		return d
	end
	disc("Rim", 1, RGB(58, 22, 4), z)
	local face = disc("Face", 0.84, Color3.new(1, 1, 1), z)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 240, 170)), ColorSequenceKeypoint.new(0.45, RGB(255, 176, 48)), ColorSequenceKeypoint.new(1, RGB(206, 92, 10)) }) }, face)
	local inner = disc("Inner", 0.64, Color3.new(1, 1, 1), z, f)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(150, 56, 6), RGB(98, 34, 4)) }, inner)
	-- ammo round: rounded tip + body + rim band
	local cream = RGB(255, 244, 214)
	local tip = new("Frame", { Name = "Tip", BackgroundColor3 = cream, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.39), Size = UDim2.fromScale(0.17, 0.3), ZIndex = z }, f)
	HS.corner(tip, UDim.new(0.5, 0))
	local body = new("Frame", { Name = "Body", BackgroundColor3 = cream, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.17, 0.2), ZIndex = z }, f)
	new("UIGradient", { Color = ColorSequence.new(RGB(255, 255, 255), RGB(255, 206, 120)) }, body)
	new("UIGradient", { Color = ColorSequence.new(RGB(255, 255, 255), RGB(255, 206, 120)) }, tip)
	new("Frame", { Name = "Band", BackgroundColor3 = RGB(255, 196, 64), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.23, 0.07), ZIndex = z }, f)
	local gloss = new("Frame", { Name = "Gloss", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.33, 0.27), Size = UDim2.fromScale(0.2, 0.12), Rotation = -35, ZIndex = z }, f)
	HS.corner(gloss, UDim.new(0.5, 0))
	return f
end

return HS
