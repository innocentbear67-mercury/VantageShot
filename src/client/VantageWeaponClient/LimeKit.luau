--[[
	VANTAGE — LimeKit
	Visual language for the cinematic main menu (lime / obsidian / olive).
	  C, F       colour + font tokens
	  glass()    translucent obsidian panel, chamfered top-right corner, hairline edges,
	             olive light from the top, lime corner ticks (no images)
	  keyChip()  bordered key label (Q, E, ENTER ...)
	  spaced()   letter-spacing via hair spaces (Roblox text has no tracking)
	  scrim()    gradient darkening frame
	All sizes are 1920x1080 design pixels; clusters are scaled with UIScale by the menu.
]]

local TweenService = game:GetService("TweenService")

local Kit = {}
local C = Color3.fromRGB
local O = UDim2.fromOffset
local V2 = Vector2.new
local SQ2 = math.sqrt(2)

Kit.C = {
	Lime = C(182, 255, 0),
	Obs = C(8, 13, 8),
	Olive = C(38, 56, 0),
	White = C(236, 242, 230),
	Muted = C(150, 162, 146),
	Dim = C(104, 116, 100),
	Line = C(236, 242, 230),
	Blue = C(77, 166, 255),
	Red = C(255, 86, 72),
}
local function fam(n, w)
	return Font.new("rbxasset://fonts/families/" .. n .. ".json", w or Enum.FontWeight.Regular)
end
Kit.F = {
	Word = fam("Michroma"),
	Head = fam("Oswald", Enum.FontWeight.Bold),
	Head6 = fam("Oswald", Enum.FontWeight.SemiBold),
	Sub = fam("Oswald", Enum.FontWeight.Medium),
	Sub4 = fam("Oswald", Enum.FontWeight.Regular),
	Body = fam("TitilliumWeb"),
	Label = fam("TitilliumWeb", Enum.FontWeight.SemiBold),
	LabelB = fam("TitilliumWeb", Enum.FontWeight.Bold),
	Mono = fam("RobotoMono"),
	MonoM = fam("RobotoMono", Enum.FontWeight.Medium),
	MonoB = fam("RobotoMono", Enum.FontWeight.Bold),
}

function Kit.new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local new = Kit.new

function Kit.tween(i, t, props, style, dir)
	local tw = TweenService:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- letter-spacing: n hair spaces between characters
local HAIR = utf8.char(0x200A)
function Kit.spaced(s, n)
	n = n or 1
	local gap = string.rep(HAIR, n)
	local out = {}
	for _, cp in utf8.codes(s) do
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out, gap)
end

-- Roblox renders a given TextSize ~1.45x smaller than the design mocks; TextSize also caps
-- at 100, so larger text is drawn at 100 and scaled up with a UIScale (box kept the same)
Kit.TEXT_K = 1.45
local function isMono(l)
	return string.find(l.FontFace.Family, "RobotoMono", 1, true) ~= nil
end
function Kit.text(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Kit.C.White,
		FontFace = Kit.F.Label,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BorderSizePixel = 0,
	}, parent)
	for k, v in props do
		l[k] = v
	end
	-- monospace glyphs are already wide: drop hair-space tracking (now and on later updates)
	if isMono(l) then
		local function strip()
			if string.find(l.Text, HAIR, 1, true) then
				l.Text = string.gsub(l.Text, HAIR, "")
			end
		end
		strip()
		l:GetPropertyChangedSignal("Text"):Connect(strip)
	end
	local want = math.floor(l.TextSize * Kit.TEXT_K + 0.5)
	if want <= 100 then
		l.TextSize = want
	else
		l.TextSize = 100
		local k = want / 100
		new("UIScale", { Scale = k }, l)
		local sz = l.Size
		l.Size = UDim2.new(sz.X.Scale / k, sz.X.Offset / k, sz.Y.Scale / k, sz.Y.Offset / k)
	end
	return l
end

function Kit.rect(parent, x, y, w, h, color, t, z)
	return new("Frame", { Position = O(x, y), Size = O(w, h), BackgroundColor3 = color, BackgroundTransparency = t or 0, BorderSizePixel = 0, ZIndex = z or 1 }, parent)
end

--[[ glass(parent, o)
	o.W, o.H        size
	o.Cut           chamfer on the top-right corner (default 14, 0 = square)
	o.FillT         fill transparency (default 0.38)
	o.EdgeT         hairline transparency (default 0.87)
	o.Lime          lime hairline instead of white
	o.Ticks         lime corner ticks (default true)
	o.Olive         olive light from the top (default true)
	o.Button        TextButton root
	o.Position, o.Anchor, o.Name, o.Order, o.Z
	returns { Root, Fill, Edges, SetEdge(color, t, time) }
]]
function Kit.glass(parent, o)
	local w, h, c = o.W, o.H, o.Cut or 14
	local root = new(if o.Button then "TextButton" else "Frame", {
		Name = o.Name or "Glass",
		Size = O(w, h),
		Position = o.Position or O(0, 0),
		AnchorPoint = o.Anchor or V2(0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = o.Order or 0,
		ZIndex = o.Z or 1,
	}, parent)
	if o.Button then
		root.Text = ""
		root.AutoButtonColor = false
	end
	local fill = new("CanvasGroup", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = o.FillT or 0.38 }, root)
	if c > 0 then
		local L = 2 * (w + h) + 40
		new("Frame", {
			Name = "Shape",
			AnchorPoint = V2(0.5, 0.5),
			Size = O(L, L),
			Rotation = 45,
			Position = O(w - c / 2 - L / (2 * SQ2), c / 2 + L / (2 * SQ2)),
			BackgroundColor3 = Kit.C.Obs,
			BorderSizePixel = 0,
		}, fill)
	else
		new("Frame", { Name = "Shape", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Kit.C.Obs, BorderSizePixel = 0 }, fill)
	end
	if o.Olive ~= false then
		local ol = new("Frame", { Name = "Olive", Size = UDim2.new(1, -c, 0.6, 0), BackgroundColor3 = Kit.C.Olive, BorderSizePixel = 0, ZIndex = 2 }, fill)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }) }, ol)
	end
	local ec = if o.Lime then Kit.C.Lime else Kit.C.Line
	local et = o.EdgeT or (if o.Lime then 0.55 else 0.87)
	local edges = {}
	local function edge(pos, size, rot, anchor)
		table.insert(edges, new("Frame", { Name = "Edge", Position = pos, Size = size, Rotation = rot or 0, AnchorPoint = anchor or V2(0, 0), BackgroundColor3 = ec, BackgroundTransparency = et, BorderSizePixel = 0, ZIndex = 3 }, root))
	end
	edge(O(0, 0), O(w - c, 1))
	edge(O(w - 1, c), O(1, h - c))
	edge(O(0, h - 1), O(w, 1))
	edge(O(0, 0), O(1, h))
	if c > 0 then
		edge(O(w - c / 2, c / 2), O(c * SQ2, 1), 45, V2(0.5, 0.5))
	end
	local ticks = {}
	if o.Ticks ~= false then
		local L = Kit.C.Lime
		table.insert(ticks, Kit.rect(root, 0, 0, 10, 2, L, 0.05, 4))
		table.insert(ticks, Kit.rect(root, 0, 0, 2, 10, L, 0.05, 4))
		table.insert(ticks, Kit.rect(root, w - 10, h - 1, 10, 1, L, 0.4, 4))
		table.insert(ticks, Kit.rect(root, w - 1, h - 10, 1, 10, L, 0.4, 4))
	end
	local panel = { Root = root, Fill = fill, Edges = edges, Ticks = ticks }
	function panel.SetEdge(color, t, time)
		for _, e in edges do
			if time and time > 0 then
				Kit.tween(e, time, { BackgroundColor3 = color, BackgroundTransparency = t })
			else
				e.BackgroundColor3 = color
				e.BackgroundTransparency = t
			end
		end
	end
	return panel
end

function Kit.keyChip(parent, key, props)
	local h = (props and props.H) or 24
	local w = math.max(h, 16 + #key * 10)
	local chip = new("Frame", { Name = "Key", Size = O(w, h), BackgroundColor3 = Kit.C.Obs, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, parent)
	new("UIStroke", { Color = Kit.C.Line, Transparency = 0.62, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
	Kit.text(chip, { Name = "Label", Size = UDim2.fromScale(1, 1), Text = key, FontFace = Kit.F.MonoB, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center })
	if props then
		for k, v in props do
			if k ~= "H" then
				chip[k] = v
			end
		end
	end
	return chip
end

-- horizontal gradient darkening (a0 at the left edge -> a1 at the right edge), or vertical
function Kit.scrim(parent, props, a0, a1, rot)
	local f = new("Frame", { BackgroundColor3 = Kit.C.Obs, BorderSizePixel = 0, BackgroundTransparency = 0 }, parent)
	for k, v in props do
		f[k] = v
	end
	new("UIGradient", {
		Rotation = rot or 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - a0),
			NumberSequenceKeypoint.new(0.5, 1 - (a0 + (a1 - a0) * 0.5) * 0.92),
			NumberSequenceKeypoint.new(1, 1 - a1),
		}),
	}, f)
	return f
end

function Kit.gear(parent, size, color)
	local g = new("Frame", { Name = "Gear", Size = O(size, size), BackgroundTransparency = 1 }, parent)
	for i = 0, 3 do
		new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(size, size * 0.22), Rotation = i * 45, BackgroundColor3 = color, BorderSizePixel = 0 }, g)
	end
	local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(size * 0.74, size * 0.74), BackgroundColor3 = color, BorderSizePixel = 0 }, g)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local hole = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(size * 0.34, size * 0.34), BackgroundColor3 = Kit.C.Obs, BorderSizePixel = 0 }, g)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, hole)
	return g
end

return Kit
