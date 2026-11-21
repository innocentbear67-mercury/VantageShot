--[[
	VANTAGE — LobbyKit: shared look for the Roblox-native lobby and menu screens (2026-11-15).
	BuilderSans (Roblox's own UI font), dark slabs, white for selected / call to action,
	lime only for small details (progress fills, tips). Icons are drawn from frames (no assets).
]]
local TweenService = game:GetService("TweenService")

local Kit = {}
local C = Color3.fromRGB
Kit.C = {
	White = C(244, 246, 248),
	Text = C(236, 239, 242),
	Muted = C(168, 175, 184),
	Dim = C(118, 125, 134),
	Slab = C(22, 24, 28),
	Slab2 = C(32, 35, 40),
	Ink = C(16, 18, 21),
	Lime = C(215, 240, 90),
	Blue = C(84, 156, 255),
	Red = C(255, 92, 84),
	Gold = C(242, 196, 92),
}
local function font(w)
	return Font.new("rbxasset://fonts/families/BuilderSans.json", w or Enum.FontWeight.Bold)
end
Kit.F = {
	Heavy = font(Enum.FontWeight.Heavy),
	Bold = font(Enum.FontWeight.Bold),
	Semi = font(Enum.FontWeight.SemiBold),
	Med = font(Enum.FontWeight.Medium),
	Reg = font(Enum.FontWeight.Regular),
}

function Kit.new(cls: string, props, parent: Instance?)
	local i = Instance.new(cls)
	if props then
		for k, v in props do
			(i :: any)[k] = v
		end
	end
	if i:IsA("GuiObject") and (props == nil or props.BorderSizePixel == nil) then
		(i :: any).BorderSizePixel = 0
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local new = Kit.new

function Kit.tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Kit.corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, p)
end
function Kit.stroke(p, color, transp, thick)
	return new("UIStroke", { Color = color or Kit.C.White, Transparency = transp or 0.85, Thickness = thick or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
function Kit.pad(p, l, r, t, b)
	return new("UIPadding", { PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or l or 0), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or t or 0) }, p)
end

function Kit.text(parent, props)
	local base = {
		BackgroundTransparency = 1, TextColor3 = Kit.C.Text, FontFace = Kit.F.Bold, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- dark slab panel
function Kit.panel(parent, props, transp)
	local base = { BackgroundColor3 = Kit.C.Slab, BackgroundTransparency = transp or 0.12 }
	for k, v in props do
		base[k] = v
	end
	local f = new("Frame", base, parent)
	Kit.corner(f, 6)
	Kit.stroke(f, Kit.C.White, 0.9)
	return f
end

-- progress bar: returns the fill frame
function Kit.bar(parent, props, fillColor)
	local base = { BackgroundColor3 = Kit.C.White, BackgroundTransparency = 0.86 }
	for k, v in props do
		base[k] = v
	end
	local b = new("Frame", base, parent)
	Kit.corner(b, 3)
	local f = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = fillColor or Kit.C.Lime }, b)
	Kit.corner(f, 3)
	return f
end

function Kit.keycap(parent, key: string, props)
	local base = { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundColor3 = Kit.C.Ink, BackgroundTransparency = 0.25,
		Text = key, FontFace = Kit.F.Bold, TextSize = 13, TextColor3 = Kit.C.Muted }
	for k, v in props or {} do
		base[k] = v
	end
	local l = new("TextLabel", base, parent)
	Kit.corner(l, 4)
	Kit.stroke(l, Kit.C.White, 0.8)
	Kit.pad(l, 7, 7, 0, 0)
	return l
end

function Kit.abbrev(n: number): string
	n = math.floor(n)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Kit.duration(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d, h, m = sec // 86400, (sec % 86400) // 3600, (sec % 3600) // 60
	if d > 0 then
		return string.format("%dD %dH", d, h)
	elseif h > 0 then
		return string.format("%dH %dM", h, m)
	end
	return string.format("%dM %dS", m, sec % 60)
end

-- ─── icons (drawn from frames; size = the box, color = stroke/fill) ──────────────────────────────────────────────────────────────────
local S, V2 = UDim2.fromScale, Vector2.new
local function fr(box, color, x, y, w, h, rot, round)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(x, y), Size = S(w, h), Rotation = rot or 0, BackgroundColor3 = color, Name = "Ink" }, box)
	if round then
		Kit.corner(f, round)
	end
	return f
end
local function ring(box, color, x, y, d, th)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(x, y), Size = S(d, d), BackgroundTransparency = 1 }, box)
	new("UIAspectRatioConstraint", {}, f)
	Kit.corner(f, 999)
	local s = new("UIStroke", { Color = color, Thickness = th, Name = "InkStroke" }, f)
	return f, s
end
local function dot(box, color, x, y, d)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(x, y), Size = S(d, d), BackgroundColor3 = color, Name = "Ink" }, box)
	new("UIAspectRatioConstraint", {}, f)
	Kit.corner(f, 999)
	return f
end

local DRAW = {}
DRAW.Deploy = function(b, c, px)
	ring(b, c, 0.5, 0.5, 0.66, math.max(2, px * 0.07))
	dot(b, c, 0.5, 0.5, 0.14)
	fr(b, c, 0.5, 0.08, 0.07, 0.24) fr(b, c, 0.5, 0.92, 0.07, 0.24)
	fr(b, c, 0.08, 0.5, 0.24, 0.07) fr(b, c, 0.92, 0.5, 0.24, 0.07)
end
DRAW.Legionary = function(b, c)
	local shell = fr(b, c, 0.5, 0.46, 0.7, 0.72, 0, 999)
	local visor = fr(b, Kit.C.Ink, 0.56, 0.44, 0.58, 0.2, 0, 3)
	visor.Name = "Cut"
	fr(b, c, 0.5, 0.86, 0.56, 0.12, 0, 2)
end
DRAW.Arsenal = function(b, c)
	-- a round of ammunition, tilted
	local g = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Rotation = 35 }, b)
	fr(g, c, 0.5, 0.62, 0.3, 0.5, 0, 2)
	fr(g, c, 0.5, 0.28, 0.3, 0.3, 0, 999)
	fr(g, c, 0.5, 0.9, 0.36, 0.08, 0, 1)
end
DRAW.Squad = function(b, c)
	dot(b, c, 0.5, 0.3, 0.26)
	fr(b, c, 0.5, 0.74, 0.44, 0.32, 0, 6)
	dot(b, c, 0.2, 0.38, 0.2)
	fr(b, c, 0.18, 0.76, 0.3, 0.26, 0, 5)
	dot(b, c, 0.8, 0.38, 0.2)
	fr(b, c, 0.82, 0.76, 0.3, 0.26, 0, 5)
end
DRAW.Store = function(b, c, px)
	local th = math.max(2, px * 0.08)
	fr(b, c, 0.14, 0.22, 0.2, 0.08)
	local basket = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.55, 0.46), Size = S(0.62, 0.4), BackgroundTransparency = 1 }, b)
	Kit.corner(basket, 3)
	new("UIStroke", { Color = c, Thickness = th, Name = "InkStroke" }, basket)
	fr(b, c, 0.55, 0.46, 0.06, 0.4)
	dot(b, c, 0.36, 0.84, 0.16)
	dot(b, c, 0.74, 0.84, 0.16)
end
DRAW.Progression = function(b, c)
	-- rank chevrons
	for i, y in { 0.34, 0.58, 0.82 } do
		fr(b, c, 0.33, y - 0.04, 0.42, 0.12, 35, 2)
		fr(b, c, 0.67, y - 0.04, 0.42, 0.12, -35, 2)
	end
end
DRAW.Settings = function(b, c, px)
	for i = 0, 3 do
		fr(b, c, 0.5, 0.5, 0.18, 0.96, i * 45, 2)
	end
	dot(b, c, 0.5, 0.5, 0.7)
	dot(b, Kit.C.Ink, 0.5, 0.5, 0.3).Name = "Cut"
end
DRAW.Req = function(b, c)
	-- REQ: a cut hexagon chip
	fr(b, c, 0.5, 0.5, 0.62, 0.62, 45, 3)
	fr(b, Kit.C.Ink, 0.5, 0.5, 0.3, 0.3, 45, 1).Name = "Cut"
end
DRAW.Chevron = function(b, c)
	fr(b, c, 0.5, 0.33, 0.12, 0.5, -42, 2)
	fr(b, c, 0.5, 0.67, 0.12, 0.5, 42, 2)
end
DRAW.Back = function(b, c)
	fr(b, c, 0.5, 0.33, 0.12, 0.5, 42, 2)
	fr(b, c, 0.5, 0.67, 0.12, 0.5, -42, 2)
end
DRAW.Clock = function(b, c, px)
	ring(b, c, 0.5, 0.5, 0.86, math.max(2, px * 0.1))
	fr(b, c, 0.5, 0.38, 0.1, 0.32, 0, 1)
	fr(b, c, 0.6, 0.52, 0.28, 0.1, 0, 1)
end
DRAW.Check = function(b, c)
	fr(b, c, 0.34, 0.58, 0.14, 0.4, -45, 2)
	fr(b, c, 0.6, 0.46, 0.14, 0.7, 40, 2)
end
DRAW.Lock = function(b, c, px)
	ring(b, c, 0.5, 0.34, 0.46, math.max(2, px * 0.1))
	fr(b, c, 0.5, 0.66, 0.68, 0.5, 0, 3)
end
DRAW.Mark = function(b, c)
	-- the Vantage double chevron
	fr(b, c, 0.3, 0.42, 0.14, 0.76, -24, 1)
	fr(b, c, 0.7, 0.42, 0.14, 0.76, 24, 1)
	fr(b, c, 0.41, 0.56, 0.1, 0.42, -24, 1)
	fr(b, c, 0.59, 0.56, 0.1, 0.42, 24, 1)
end

-- an icon box; Kit.recolor(box, color) repaints it (hover / selected states)
function Kit.icon(parent, name: string, px: number, color: Color3?, props)
	local base = { Size = UDim2.fromOffset(px, px), BackgroundTransparency = 1, Name = "Icon" }
	for k, v in props or {} do
		base[k] = v
	end
	local b = new("Frame", base, parent)
	local draw = DRAW[name]
	if draw then
		draw(b, color or Kit.C.White, px)
	end
	return b
end

function Kit.recolor(box: Instance, color: Color3, cut: Color3?)
	for _, d in box:GetDescendants() do
		if d.Name == "Ink" and d:IsA("Frame") then
			d.BackgroundColor3 = color
		elseif d.Name == "InkStroke" and d:IsA("UIStroke") then
			d.Color = color
		elseif d.Name == "Cut" and d:IsA("Frame") and cut then
			d.BackgroundColor3 = cut
		end
	end
end

return Kit
