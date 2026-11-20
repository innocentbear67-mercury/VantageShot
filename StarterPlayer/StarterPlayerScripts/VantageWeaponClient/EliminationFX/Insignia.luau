--[[
	VANTAGE — Insignia (default elimination effect)
	Every elimination effect module under EliminationFX implements:
		Build(parent, glow, tier, image?) -> icon { Root: CanvasGroup, Scale: UIScale, Glints: { UIGradient } }
			with `image` (the callout's Icon from EliminationConfig) the emblem is that artwork on a
			glow halo; without one it falls back to the built insignia described below
		Impact(icon, tier, ringParent?)   slam in, overshoot, settle, metal glint (+ shockwave ring)
		Screen(layer, tier)               the killer's golden screen burst (pooled, reused)
		World(position, glow, headshot, image?)   small in-world version above the eliminated player
	The insignia: a gunmetal diamond plate with a gold "V" chevron, swept gold blades either side,
	tip studs and a soft glow. Tier 2 (headshot / knife) adds a crown and a red core; tier 3
	(multikill / streak) adds outer blades. Gold parts share one metal gradient whose highlight
	band sweeps across as it lands. Built from GuiObjects: crisp at any size, no image assets.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ElimConfig = require(ReplicatedStorage.Vantage.Elimination.EliminationConfig)
local GOLD, METAL = ElimConfig.Gold, ElimConfig.Metal

local S = UDim2.fromScale
local V2 = Vector2.new
local CK = ColorSequenceKeypoint.new
local function NK(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

local GOLD_SEQ = ColorSequence.new({ CK(0, GOLD.Deep), CK(0.3, GOLD.Base), CK(0.46, GOLD.Glint), CK(0.54, GOLD.Light), CK(0.72, GOLD.Base), CK(1, GOLD.Deep) })
local METAL_SEQ = ColorSequence.new(METAL.Light, METAL.Dark)
local CORE = Color3.fromRGB(255, 72, 64)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FLAKES, FRAGS = 40, 8

local rng = Random.new()

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function tween(i, t, props, style, dir)
	local tw = TweenService:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- one shape; gold metal unless a flat colour is given
local function piece(root, size, pos, rot, glints, color: Color3?)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = size, Position = pos, Rotation = rot or 0, BackgroundColor3 = color or Color3.new(1, 1, 1), BorderSizePixel = 0 }, root)
	if not color then
		table.insert(glints, new("UIGradient", { Color = GOLD_SEQ, Rotation = 35 }, f))
		new("UIStroke", { Color = GOLD.Deep, Thickness = 1, Transparency = 0.35 }, f)
	end
	return f
end

local Insignia = {}

function Insignia.Build(parent: Instance, glow: Color3, tier: number, image: string?)
	local root = new("CanvasGroup", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1 }, parent)
	local scale = new("UIScale", {}, root)
	local glints = {}
	if image and image ~= "" then
		-- artwork emblem on a soft halo (brighter for bigger callouts)
		for _, g in { { 0.95, 0.94 }, { 0.78, 0.88 }, { 0.6, 0.82 } } do
			local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(g[1], g[1]), BackgroundColor3 = glow, BackgroundTransparency = g[2] - 0.04 * (tier - 1), BorderSizePixel = 0 }, root)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		end
		new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit }, root)
		return { Root = root, Scale = scale, Glints = glints }
	end
	-- soft glow: stacked rounded diamonds
	for _, g in { { 0.66, 0.93 }, { 0.55, 0.86 }, { 0.46, 0.78 } } do
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(g[1], g[1]), Rotation = 45, BackgroundColor3 = glow, BackgroundTransparency = g[2], BorderSizePixel = 0 }, root)
		new("UICorner", { CornerRadius = UDim.new(0.2, 0) }, f)
	end
	-- swept blades, mirrored (drawn first so the plate covers their roots)
	local function blades(x, y, w, h, rot)
		piece(root, S(w, h), S(x, y), rot, glints)
		piece(root, S(w, h), S(1 - x, y), -rot, glints)
	end
	if tier >= 3 then
		blades(0.1, 0.5, 0.17, 0.035, 0)
	end
	blades(0.2, 0.43, 0.3, 0.055, 16)
	blades(0.23, 0.57, 0.22, 0.045, -12)
	-- gunmetal plate with a gold rim and an inner hairline
	local plate = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.44, 0.44), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, root)
	new("UIGradient", { Color = METAL_SEQ, Rotation = 45 }, plate)
	new("UIStroke", { Color = GOLD.Base, Thickness = 2 }, plate)
	local inner = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.32, 0.32), Rotation = 45, BackgroundTransparency = 1 }, root)
	new("UIStroke", { Color = GOLD.Light, Thickness = 1, Transparency = 0.55 }, inner)
	-- the V
	piece(root, S(0.065, 0.27), S(0.448, 0.47), -22, glints)
	piece(root, S(0.065, 0.27), S(0.552, 0.47), 22, glints)
	piece(root, S(0.075, 0.075), S(0.5, 0.6), 45, glints)
	-- tip studs
	piece(root, S(0.05, 0.05), S(0.5, 0.205), 45, glints)
	piece(root, S(0.05, 0.05), S(0.5, 0.795), 45, glints)
	if tier >= 2 then
		-- crown + red core
		piece(root, S(0.04, 0.04), S(0.42, 0.165), 45, glints)
		piece(root, S(0.055, 0.055), S(0.5, 0.11), 45, glints)
		piece(root, S(0.04, 0.04), S(0.58, 0.165), 45, glints)
		local core = piece(root, S(0.06, 0.06), S(0.5, 0.42), 45, glints, CORE)
		new("UIStroke", { Color = GOLD.Light, Thickness = 1 }, core)
	end
	return { Root = root, Scale = scale, Glints = glints }
end

function Insignia.Impact(icon, tier: number, ringParent: Instance?)
	local s = icon.Scale
	icon.Root.GroupTransparency = 1
	s.Scale = if tier >= 3 then 2.6 elseif tier == 2 then 2.3 else 2
	tween(icon.Root, 0.07, { GroupTransparency = 0 })
	local peak = if tier >= 2 then 1.12 else 1.06
	tween(s, 0.11, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		tween(s, 0.08, { Scale = peak }).Completed:Once(function()
			tween(s, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end)
	-- metal glint: the highlight band sweeps in and comes to rest
	for _, g in icon.Glints do
		g.Offset = V2(-0.8, 0)
	end
	task.delay(0.1, function()
		for _, g in icon.Glints do
			if g.Parent then
				tween(g, 0.5, { Offset = V2(0, 0) })
			end
		end
	end)
	if ringParent then
		-- shockwave as it lands
		task.delay(0.11, function()
			if not ringParent.Parent then
				return
			end
			local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.6, 0.6), BackgroundTransparency = 1 }, ringParent)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
			local st = new("UIStroke", { Color = GOLD.Light, Thickness = if tier >= 2 then 3 else 2, Transparency = 0.1 }, ring)
			local r = if tier >= 3 then 2.6 else 2.1
			tween(ring, 0.42, { Size = S(r, r) }, Enum.EasingStyle.Quart)
			tween(st, 0.42, { Transparency = 1, Thickness = 0.5 })
			Debris:AddItem(ring, 0.5)
		end)
	end
end

-- ─── golden screen burst (one pool per layer, reused every kill) ─────────────────────────
local pools = {}

local function pool(layer: Frame)
	local p = pools[layer]
	if p then
		return p
	end
	p = { Edges = {}, Flakes = {}, Frags = {} }
	for i, e in { { S(1, 0.16), S(0, 0), 90 }, { S(1, 0.16), S(0, 0.84), -90 }, { S(0.11, 1), S(0, 0), 0 }, { S(0.11, 1), S(0.89, 0), 180 } } do
		local f = new("Frame", { Size = e[1], Position = e[2], BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, layer)
		new("UIGradient", { Rotation = e[3], Color = ColorSequence.new(GOLD.Light, GOLD.Base), Transparency = NumberSequence.new({ NK(0, 0), NK(1, 1) }) }, f)
		p.Edges[i] = f
	end
	p.Ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, layer)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, p.Ring)
	p.RingStroke = new("UIStroke", { Color = GOLD.Light, Thickness = 2, Transparency = 1 }, p.Ring)
	for i = 1, FLAKES do
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Visible = false }, layer)
		new("UIGradient", { Color = GOLD_SEQ, Rotation = rng:NextNumber(0, 180) }, f)
		p.Flakes[i] = f
	end
	for i = 1, FRAGS do
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Visible = false }, layer)
		new("UIGradient", { Color = GOLD_SEQ, Rotation = 35 }, f)
		local st = new("UIStroke", { Color = GOLD.Glint, Thickness = 1.5, Transparency = 1 }, f)
		p.Frags[i] = { Frame = f, Stroke = st }
	end
	pools[layer] = p
	layer.Destroying:Once(function()
		pools[layer] = nil
	end)
	return p
end

function Insignia.Screen(layer: Frame, tier: number)
	local p = pool(layer)
	local vp = layer.AbsoluteSize
	local cx, cy = vp.X / 2, vp.Y / 2
	-- edge flash (never a full-screen tint)
	local flash = ({ 0.55, 0.35, 0.25 })[tier] or 0.55
	for _, e in p.Edges do
		e.BackgroundTransparency = flash
		tween(e, 0.45 + 0.1 * tier, { BackgroundTransparency = 1 })
	end
	-- centre shockwave: a hollow ring, so the crosshair stays visible
	local R = math.min(vp.X, vp.Y) * (0.6 + 0.2 * tier)
	p.Ring.Size = UDim2.fromOffset(36, 36)
	p.RingStroke.Transparency = if tier >= 2 then 0.1 else 0.3
	p.RingStroke.Thickness = 1 + tier
	tween(p.Ring, 0.55, { Size = UDim2.fromOffset(R, R) }, Enum.EasingStyle.Quart)
	tween(p.RingStroke, 0.55, { Transparency = 1 })
	-- gold flakes burst from just outside the crosshair, spin, sag and fade
	local n = ({ 18, 28, 40 })[tier] or 18
	for i = 1, n do
		local f = p.Flakes[i]
		local a = rng:NextNumber(0, math.pi * 2)
		local r0 = rng:NextNumber(34, 50)
		local r1 = rng:NextNumber(140, 220 + 110 * tier)
		f.Position = UDim2.fromOffset(cx + math.cos(a) * r0, cy + math.sin(a) * r0)
		f.Size = UDim2.fromOffset(rng:NextInteger(4, 8) + tier, rng:NextInteger(2, 4))
		f.Rotation = rng:NextNumber(0, 360)
		f.BackgroundTransparency = 0
		f.Visible = true
		tween(f, rng:NextNumber(0.55, 0.95), {
			Position = UDim2.fromOffset(cx + math.cos(a) * r1, cy + math.sin(a) * r1 + rng:NextNumber(20, 60)),
			Rotation = f.Rotation + rng:NextNumber(-300, 300),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quart)
	end
	-- a few larger glowing fragments drift away more slowly
	local m = ({ 3, 5, 8 })[tier] or 3
	for i = 1, m do
		local g = p.Frags[i]
		local f = g.Frame
		local a = rng:NextNumber(0, math.pi * 2)
		local r0 = rng:NextNumber(40, 60)
		local r1 = rng:NextNumber(90, 210)
		local dur = rng:NextNumber(0.9, 1.2)
		f.Position = UDim2.fromOffset(cx + math.cos(a) * r0, cy + math.sin(a) * r0)
		f.Rotation = 45
		f.BackgroundTransparency = 0
		f.Visible = true
		g.Stroke.Transparency = 0.2
		tween(f, dur, { Position = UDim2.fromOffset(cx + math.cos(a) * r1, cy + math.sin(a) * r1 - 30), Rotation = 45 + rng:NextNumber(-120, 120), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		tween(g.Stroke, dur, { Transparency = 1 })
	end
end

-- ─── in-world version (other players nearby, and the killer's own view of the body) ────────
local function fxFolder(): Folder
	local f = Workspace:FindFirstChild("VantageEliminationFX")
	if not f then
		f = new("Folder", { Name = "VantageEliminationFX" }, Workspace)
	end
	return f
end

function Insignia.World(position: Vector3, glow: Color3, headshot: boolean, image: string?)
	local anchor = new("Part", { Name = "Elimination", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(position) }, fxFolder())
	Debris:AddItem(anchor, 1.8)
	local bb = new("BillboardGui", { Size = S(2.4, 2.4), StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = ElimConfig.WorldMaxDistance }, anchor)
	local icon = Insignia.Build(bb, glow, if headshot then 2 else 1, image)
	Insignia.Impact(icon, 1)
	task.delay(0.8, function()
		tween(icon.Root, 0.35, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(bb, 0.35, { StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0) })
	end)
	local att = new("Attachment", {}, anchor)
	local sparks = new("ParticleEmitter", { Enabled = false, Texture = SPARK, Color = ColorSequence.new(GOLD.Glint, GOLD.Base), LightEmission = 1, LightInfluence = 0, Size = NumberSequence.new({ NK(0, 0.4), NK(1, 0) }), Transparency = NumberSequence.new({ NK(0, 0), NK(1, 1) }), Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(9, 16), Drag = 8, SpreadAngle = V2(180, 180) }, att)
	sparks:Emit(if headshot then 22 else 14)
	local light = new("PointLight", { Color = GOLD.Base, Range = 10, Brightness = if headshot then 4.5 else 3, Shadows = false }, anchor)
	tween(light, 0.3, { Brightness = 0 })
end

return Insignia
