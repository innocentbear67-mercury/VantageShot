--[[
	VANTAGE — Exosuit visor (client)
	H closes / opens the helmet. Approved design 2026-11-09 (see project doc visor-redesign.md).

	Layers
	  VantageVisorGlass   (DisplayOrder -1, under the HUD)  faceted helmet frame (honeycomb shell, lit rim,
	                      chromatic fringe, perimeter falloff) as 4 image quadrants; rim pulses, threat
	                      flares, reflections, partial scans, Pulse Scan wave, Phase Dash streaks, chevrons.
	  VantageHUD.VisorHUD (inside the existing HUD gui)     the visor's own telemetry:
	                      top: shield arc + health arc + curved compass; centre: segmented reticle ring +
	                      rangefinder around the HUD crosshair, homing tracker (search / acquire / lock);
	                      bottom: ammo pips arc + count + weapon + mode; lower-left: clock + team tallies;
	                      lower-right: ability hex nodes with cooldown rings; upper-left: the HUD radar.
	  VantageVisorShutter (DisplayOrder 30, over the HUD)   startup / shutdown: the visor plate the hands
	                      pull down, blackout, core light, the eye slits that ignite, swoosh and burst open.
	The old HUD clusters (Vitals / Ammo / Score / ability slots) are parked in a hidden frame; the crosshair
	stays where it is and is the only thing on screen with the helmet open.

	Hooks: VisorFeed (HudOptics publishes weapon + clock; this script drives Hands for Viewmodel),
	attributes VisorClosed / VisorBlackout (WeaponController blocks fire / aim) / VantageAbilityUsed,
	WeaponEvent "Damaged" (threat direction). Studio test hook: bump attribute VisorToggle.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local KIT = require(Vantage:WaitForChild("UI"):WaitForChild("VisorKit"))
local Feed = require(Vantage.UI:WaitForChild("VisorFeed"))
local AbilityConfig = require(Vantage:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local Bus = require(Vantage.UI:WaitForChild("VisorBus"))
local HexGrid = require(Vantage.UI:WaitForChild("VisorHexGrid"))

local C = Color3.fromRGB
local V2 = Vector2.new
local O = UDim2.fromOffset
local rad = math.rad
local TF = "rbxasset://fonts/families/TitilliumWeb.json"
local F_SB = Font.new(TF, Enum.FontWeight.SemiBold)
local F_REG = Font.new(TF, Enum.FontWeight.Regular)
local F_TAG = Font.new(TF, Enum.FontWeight.Bold) -- one family across the visor

-- palette
local WHITE = C(236, 246, 255)
local CYAN = C(110, 220, 255)
local DEEP = C(52, 118, 210)
local MUTED = C(104, 132, 160)
local AMBER = C(255, 178, 70)
local RED = C(255, 72, 52)

local SND = {
	Servo = { "rbxassetid://9118383337", 0.5, 1.05 },
	ServoOpen = { "rbxassetid://9118370609", 0.5, 1.05 },
	Lock = { "rbxassetid://9117613062", 0.5, 1.25 },
	PowerOn = { "rbxassetid://9126027558", 0.35, 1.0 },
	Hum = { "rbxassetid://9114246115", 0.0, 1.0 },
	Whoosh = { "rbxassetid://9125648149", 0.45, 1.15 },
	Scan = { "rbxassetid://9119429580", 0.3, 1.1 },
	Beeps = { "rbxassetid://9125537079", 0.22, 1.15 },
	Chime = { "rbxassetid://81933188942245", 0.4, 1.0 },
	PowerOff = { "rbxassetid://9126027654", 0.35, 0.9 },
	VoiceOn = { "rbxassetid://128351112976944", 0.9, 1.0 }, -- "HUD activated"
	VoiceOff = { "rbxassetid://96907982289113", 0.9, 1.0 }, -- "HUD deactivated"
}

local function new(class: string, props, parent: Instance?)
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local function img(name: string, props, parent)
	props.Image = KIT[name]
	props.BackgroundTransparency = 1
	return new("ImageLabel", props, parent)
end
local function tween(inst: Instance, t: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end
local function play(name: string, volume: number?, speed: number?)
	local spec = SND[name]
	local s = new("Sound", { SoundId = spec[1], Volume = volume or spec[2], PlaybackSpeed = speed or spec[3] }, SoundService)
	if name:sub(1, 5) == "Voice" then
		-- suit comms: a light helmet-radio band (keeps the voice, trims the boom and the air)
		new("EqualizerSoundEffect", { LowGain = -5, MidGain = 1.5, HighGain = -2 }, s)
	end
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	return s
end
local function smooth(a: number, b: number, t: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end
local function label(props, parent)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or F_SB
	-- the small technical tags read a touch larger than designed
	if props.FontFace == F_TAG and props.TextSize then
		props.TextSize = math.floor(props.TextSize * 1.25 + 0.5)
	end
	return new("TextLabel", props, parent)
end

-- ─── state ─────────────────────────────────────────────────────────────────────────────────
local state = "Closed" -- Open | Closing | Closed | Opening
local token = 0
local deployedShown = false
local seq = nil -- { Kind = "Close" | "Open", T0 = os.clock() } drives hands + plate per frame
player:SetAttribute("VisorClosed", true)
player:SetAttribute("VisorBlackout", false)

-- ─── glass layer (under the HUD) ─────────────────────────────────────────────────────────
local glass = new("ScreenGui", { Name = "VantageVisorGlass", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = -1, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local function quads(prefix: string, z: number, props)
	local list = {}
	for i, q in { { "LTop", 0, 0 }, { "RTop", 0.5, 0 }, { "LBot", 0, 0.5 }, { "RBot", 0.5, 0.5 } } do
		local p = table.clone(props or {})
		p.Name = prefix .. q[1]
		p.Position = UDim2.fromScale(q[2], q[3])
		p.Size = UDim2.fromScale(0.5, 0.5)
		p.ZIndex = z
		p.ScaleType = Enum.ScaleType.Stretch
		local im = img(prefix .. q[1], p, glass)
		list[i] = { Image = im, Dir = V2(q[2] == 0 and -1 or 1, q[3] == 0 and -1 or 1).Unit }
	end
	return list
end
-- the shell without baked honeycomb once it is imported (the living honeycomb draws the cells)
local frameQ = quads("HoloFrame", 3) -- v6: the user's reference frame (HoloKit)
local rimQ = quads("HoloVeins", 4, { ImageColor3 = C(160, 255, 255), ImageTransparency = 1 }) -- rim pulses now travel through the veins
for _, q in rimQ do
	q.Grad = new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }) }, q.Image)
end
local threatQ = quads("HoloVeins", 5, { ImageColor3 = RED, ImageTransparency = 1 }) -- hits light the veins red on that side

-- v6: the honeycomb is retired; the frame's energy veins are the living layer. `hc` keeps the honeycomb's
-- API so every bus reaction (boot, damage, scan, dash, jump, lock...) now drives the veins per quadrant.
local PRI_V, HI_V = C(77, 205, 255), C(160, 255, 255)
local veinQ = quads("HoloVeins", 3, { ImageColor3 = PRI_V, ImageTransparency = 1 })
local hc = { Params = { Combat = 0, Intensity = 1 }, Level = 1, Flash = { 0, 0, 0, 0 }, FlashCol = { HI_V, HI_V, HI_V, HI_V } }
local QORDER = { 1, 2, 4, 3 } -- LTop, RTop, RBot, LBot (clockwise)
local function vflash(i: number, s: number, col: Color3?, delay: number?)
	task.delay(delay or 0, function()
		if s >= hc.Flash[i] * 0.8 then
			hc.Flash[i] = math.max(hc.Flash[i], s)
			hc.FlashCol[i] = col or HI_V
		end
	end)
end
function hc:Resize() end
function hc:SetOn(on: boolean)
	self.Level = if on then 1 else 0
	self.Booting, self.Shutting = nil, nil
end
function hc:Radial(o)
	local origin = o.Origin or V2(960, 540)
	for i, q in veinQ do
		local qc = V2(if q.Dir.X > 0 then 1440 else 480, if q.Dir.Y > 0 then 810 else 270)
		vflash(i, o.Strength or 0.8, o.Color, (qc - origin).Magnitude / (o.Speed or 900))
	end
end
function hc:Directional(o)
	local a = math.rad(o.Angle or 0)
	local dir = V2(math.cos(a), math.sin(a))
	for i, q in veinQ do
		local k = q.Dir:Dot(dir)
		if k > 0.1 then
			vflash(i, (o.Strength or 1) * k, o.Color)
		end
	end
end
function hc:Perimeter(o)
	local sp = math.max(60, math.abs(o.Speed or 300))
	for n, i in QORDER do
		vflash(i, o.Strength or 0.6, o.Color, (n - 1) * 90 / sp)
	end
end
function hc:Spark(col: Color3?, s: number?)
	vflash(math.random(1, 4), (s or 0.4) * 0.6, col)
end
function hc:Boot()
	self.Level, self.Booting, self.Shutting = 0, os.clock(), nil
end
function hc:Shutdown()
	self.Shutting, self.Booting = os.clock(), nil
end
local function stepVeins(now: number, dt: number)
	if hc.Booting and now - hc.Booting > 1 then
		hc.Booting, hc.Level = nil, 1
	elseif hc.Shutting then
		hc.Level = math.clamp(1 - (now - hc.Shutting) / 0.5, 0, 1)
		if hc.Level <= 0 then
			hc.Shutting = nil
		end
	end
	local combat = hc.Params.Combat
	for i, q in veinQ do
		-- boot: the top veins light first, then the lower ones
		local lvl = if hc.Booting then math.clamp((now - hc.Booting) / 0.6 - (if q.Dir.Y < 0 then 0 else 0.35), 0, 1) else hc.Level
		local base = (0.3 + 0.1 * math.sin(now * 1.3 + i * 1.7) + 0.05 * math.sin(now * 7.1 + i) + 0.18 * combat) * lvl
		hc.Flash[i] = math.max(0, hc.Flash[i] - dt * 2.2)
		local f = hc.Flash[i] * lvl
		q.Image.ImageTransparency = 1 - math.clamp(base + f, 0, 0.95)
		q.Image.ImageColor3 = PRI_V:Lerp(hc.FlashCol[i], math.clamp(f / (f + base + 0.05), 0, 1))
	end
end
local function edgePoint(angleDeg: number): Vector2
	-- design-px point on the screen edge in a direction from the centre (angles in the normalised frame)
	local a = rad(angleDeg)
	local dx, dy = math.cos(a), math.sin(a)
	local k = 1 / math.max(math.abs(dx), math.abs(dy))
	return V2(960 + dx * k * 960, 540 + dy * k * 540)
end

-- reflection: a wide, very soft diagonal sheen that drifts against camera turns + sweeps now and then
local reflection = new("Frame", { Name = "Reflection", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.35), Size = UDim2.fromScale(0.28, 1.7), Rotation = 28, BackgroundColor3 = C(235, 245, 255), BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 2 }, glass)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.6), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) }) }, reflection)
local refl = { X = 0.7, Base = 0.7, Sweep = 0 }

-- partial scan line (a region of the glass) + markings that light as it passes
local scanHolder = new("Frame", { Name = "Scan", BackgroundTransparency = 1, Size = UDim2.fromScale(0.26, 0.42), Visible = false, ZIndex = 6 }, glass)
local scanLine = img("GlowLine", { Size = UDim2.new(1, 0, 0, 10), AnchorPoint = V2(0, 0.5), ImageColor3 = CYAN, ImageTransparency = 0.25, ZIndex = 6 }, scanHolder)
local scanTicks = {}
for k = 1, 3 do
	scanTicks[k] = label({ Position = UDim2.new(0, 0, k * 0.25, 0), Size = O(110, 10), FontFace = F_TAG, Text = ({ "SECTOR " .. math.random(10, 99), "CAL  0" .. k, "DRIFT " .. math.random(100, 999) })[k], TextSize = 7, TextColor3 = CYAN, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }, scanHolder)
end

-- Pulse Scan rings, Phase Dash streaks
local waves = {}
for i = 1, 2 do
	waves[i] = img("Ring", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(10, 10), ImageColor3 = CYAN, Visible = false, ZIndex = 6 }, glass)
end
local streaks = {}
for i = 1, 16 do
	streaks[i] = { Image = img("GlowLine", { AnchorPoint = V2(0.5, 0.5), Size = O(160, 16), ImageColor3 = WHITE, ImageTransparency = 1, ZIndex = 6 }, glass), A = (i - 0.5) / 16 * math.pi * 2 }
end

local chevrons = {}
local decoScale = {}

-- optical tint (real colour correction)
local tint = Lighting:FindFirstChild("VantageVisorTint") or new("ColorCorrectionEffect", { Name = "VantageVisorTint" }, Lighting)
local TINT_ON = { TintColor = C(188, 212, 244), Saturation = -0.04, Contrast = 0.06, Brightness = 0.02 } -- v6: light blue wash
local TINT_OFF = { TintColor = C(255, 255, 255), Saturation = 0, Contrast = 0, Brightness = 0 }

-- ─── shutter layer (over the HUD): visor plate, blackout, eyes ───────────────────────────
local shutter = new("ScreenGui", { Name = "VantageVisorShutter", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local plate = img("VisorPlate", { Name = "Plate", Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, -1.05), ScaleType = Enum.ScaleType.Stretch, ZIndex = 2 }, shutter)
img("GlowLine", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1.1, 0, 0, 26), ImageColor3 = CYAN, ZIndex = 3 }, plate)
local black = new("Frame", { Name = "Black", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(1, 2, 4), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, shutter)
local coreGlow = img("Glow", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = O(90, 90), ImageColor3 = WHITE, ImageTransparency = 1, ZIndex = 9 }, shutter)
-- eyes: mask (black with two holes) + glow outlines, inside one wrapper that scales up to "burst open"
local EYE_Y = 520 / 1080
local eyes = new("Frame", { Name = "Eyes", AnchorPoint = V2(0.5, EYE_Y), Position = UDim2.fromScale(0.5, EYE_Y), BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, shutter)
local eyeScale = new("UIScale", {}, eyes)
local eyeMask = img("EyeMask", { Size = UDim2.fromScale(1, 1), ZIndex = 5 }, eyes)
for _, b in { { V2(1, 0.5), UDim2.fromScale(0, 0.5) }, { V2(0, 0.5), UDim2.fromScale(1, 0.5) }, { V2(0.5, 1), UDim2.fromScale(0.5, 0) }, { V2(0.5, 0), UDim2.fromScale(0.5, 1) } } do
	new("Frame", { AnchorPoint = b[1], Position = b[2], Size = UDim2.fromScale(4, 4), BackgroundColor3 = C(1, 2, 4), BorderSizePixel = 0, ZIndex = 5 }, eyeMask)
end
local eyeGlow = img("EyeGlow", { Size = UDim2.fromScale(1, 1), ImageColor3 = C(170, 235, 255), ImageTransparency = 1, ZIndex = 6 }, eyes)
local swoosh = {}
for i, sx in { -1, 1 } do
	swoosh[i] = img("GlowLine", { AnchorPoint = V2(0.5, 0.5), Size = UDim2.fromScale(0.11, 0.045), Rotation = sx * -4, ImageColor3 = WHITE, ImageTransparency = 1, ZIndex = 7 }, eyes)
end
local diag = label({ AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 0), Size = O(420, 14), FontFace = F_TAG, Text = "", TextSize = 10, TextColor3 = CYAN, TextTransparency = 1, ZIndex = 9 }, shutter)

-- ─── HUD (inside VantageHUD) ─────────────────────────────────────────────────────────────
local hudGui = playerGui:WaitForChild("VantageHUD")
local hudRoot = hudGui:WaitForChild("Root")
hudRoot:WaitForChild("Ammo", 10)
local abilityGui = playerGui:WaitForChild("VantageAbilities", 30)
local cross = hudGui:FindFirstChild("Crosshair")

local old = hudGui:FindFirstChild("VisorHUD")
if old then
	old:Destroy()
end
local group = new("Frame", { Name = "VisorHUD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, hudGui)
local stash = hudGui:FindFirstChild("VisorStash") or new("Frame", { Name = "VisorStash", Visible = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, hudGui)
-- the old clusters the visor replaces: parked (still updated by Hud, never shown)
for _, n in { "Vitals", "Ammo", "Score" } do
	local g = hudRoot:FindFirstChild(n)
	if g then
		g.Parent = stash
	end
end
if abilityGui and abilityGui:FindFirstChild("Slots") then
	abilityGui.Slots.Parent = stash
end
-- transient HUD pieces live with the visor (hidden with the helmet open)
for _, n in { "HitMarker", "Prompt" } do
	local g = hudGui:FindFirstChild(n)
	if g then
		g.Parent = group
	end
end
for _, d in hudGui:GetChildren() do
	if d.Name:match("^DamageArc") then
		d.Parent = group
	end
end
for _, n in { "KillBanner", "Perf", "SettingsHint" } do
	local g = hudRoot:FindFirstChild(n)
	if g then
		g.Parent = group
	end
end

local holders = {}
-- a cluster in 1920x1080 design pixels; layout() places + scales it by viewport height
local function holder(name: string, anchor: Vector2, ax: string, x: number, y: number, w: number, h: number)
	local f = new("Frame", { Name = name, AnchorPoint = anchor, Size = O(w, h), BackgroundTransparency = 1 }, group)
	holders[name] = { Frame = f, Scale = new("UIScale", {}, f), Ax = ax, X = x, Y = y }
	return f
end

-- HUD v4 (2026-11-09): one motif — slim bands with 45° chamfered ends that echo the faceted visor,
-- placed against the glass's inner contour. One font (Titillium), three sizes, glowing text, dim
-- empty tracks behind every meter, nothing decorative that doesn't carry information.
local F_LAB = Font.new(TF, Enum.FontWeight.Bold)
local CUT = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.502, 1), NumberSequenceKeypoint.new(1, 1) })
-- chamfer caps: the square's opaque half (UIGradient rotation)
local CAP = { BackL = 135, SlashL = 225, SlashR = 45, BackR = 315 }
local function glowText(l: TextLabel, col: Color3?, t: number?)
	local base = t or 0.8
	local st = new("UIStroke", { Color = col or CYAN, Thickness = 1, Transparency = base + (1 - base) * l.TextTransparency, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	-- the glow fades with its text (a hidden label leaves no ghost outline)
	l:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		st.Transparency = base + (1 - base) * l.TextTransparency
	end)
	return l
end
local function text(parent, props)
	props.FontFace = props.FontFace or F_SB
	props.BackgroundTransparency = 1
	local l = new("TextLabel", props, parent)
	return glowText(l)
end
-- a band: body + two chamfered end caps (h x h squares cut on the diagonal)
local function band(parent, x: number, y: number, w: number, h: number, color: Color3, tr: number, capL: number, capR: number, z: number?)
	local f = new("Frame", { Position = O(x, y), Size = O(w, h), BackgroundTransparency = 1, ZIndex = z or 1 }, parent)
	local parts = {}
	parts[1] = new("Frame", { Position = O(h, 0), Size = O(math.max(0, w - 2 * h), h), BackgroundColor3 = color, BackgroundTransparency = tr, BorderSizePixel = 0, ZIndex = z or 1 }, f)
	for i, spec in { { 0, capL }, { w - h, capR } } do
		local c = new("Frame", { Position = O(spec[1], 0), Size = O(h, h), BackgroundColor3 = color, BackgroundTransparency = tr, BorderSizePixel = 0, ZIndex = z or 1 }, f)
		new("UIGradient", { Rotation = spec[2], Transparency = CUT }, c)
		parts[i + 1] = c
	end
	local api = { Frame = f }
	function api.Color(col: Color3)
		for _, p in parts do
			p.BackgroundColor3 = col
		end
	end
	function api.Alpha(t: number)
		for _, p in parts do
			p.BackgroundTransparency = t
		end
	end
	return api
end
-- a rectangle with its top-right corner cut at 45°
local function chamferRect(parent, x: number, y: number, w: number, h: number, c: number, color: Color3, tr: number, z: number?)
	local f = new("Frame", { Position = O(x, y), Size = O(w, h), BackgroundTransparency = 1, ZIndex = z or 1 }, parent)
	local parts = {
		new("Frame", { Size = O(w - c, h), BackgroundColor3 = color, BackgroundTransparency = tr, BorderSizePixel = 0, ZIndex = z or 1 }, f),
		new("Frame", { Position = O(w - c, c), Size = O(c, h - c), BackgroundColor3 = color, BackgroundTransparency = tr, BorderSizePixel = 0, ZIndex = z or 1 }, f),
	}
	local corner = new("Frame", { Position = O(w - c, 0), Size = O(c, c), BackgroundColor3 = color, BackgroundTransparency = tr, BorderSizePixel = 0, ZIndex = z or 1 }, f)
	new("UIGradient", { Rotation = CAP.BackR, Transparency = CUT }, corner)
	table.insert(parts, corner)
	local api = { Frame = f }
	function api.Color(col: Color3)
		for _, p in parts do
			p.BackgroundColor3 = col
		end
	end
	function api.Alpha(t: number)
		for _, p in parts do
			p.BackgroundTransparency = t
		end
	end
	return api
end
-- a soft dark plate behind a cluster (separates the readout from the world, adds depth)
local function backPlate(parent, x: number, y: number, w: number, h: number, fadeRot: number)
	local p = new("Frame", { Position = O(x, y), Size = O(w, h), BackgroundColor3 = C(2, 6, 12), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 0 }, parent)
	new("UIGradient", { Rotation = fadeRot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.55), NumberSequenceKeypoint.new(1, 0.45) }) }, p)
	local line = new("Frame", { Position = O(0, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = DEEP, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 0 }, p)
	new("UIGradient", { Rotation = fadeRot, Transparency = NumberSequence.new(1, 0) }, line)
	return p
end

-- HUD v5 (2026-11-09) — colour hierarchy: cool white = primary readouts, blue-grey = secondary labels,
-- cyan-white = active / live state, dark blue = backing, amber = warnings, red = critical. Only live
-- state glows. Every element below is a real UI object animated by the per-frame step or the bus.
local function plain(props, parent)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or F_SB
	local l = new("TextLabel", props, parent)
	-- a thin dark edge keeps secondary text legible over bright scenery (fades with the text)
	local st = new("UIStroke", { Color = C(2, 6, 12), Thickness = 1, Transparency = 0.45 + 0.55 * l.TextTransparency }, l)
	l:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		st.Transparency = 0.45 + 0.55 * l.TextTransparency
	end)
	return l
end
local PRIMARY = C(232, 242, 250)
local SECOND = C(122, 142, 164)
local ACTIVE = C(165, 232, 255)
local BACK = C(6, 14, 28)

-- top: compass tape (the hero), suit gauges flanking the heading ──────────────────────────
-- the clusters read at 1.2x the old design size (more info on screen, nothing tiny); the lower-left
-- pieces are placed so the 1.2x radar / abilities stay aligned with the clock column
local HUD_S = 1.2
local top = holder("Top", V2(0.5, 0), "C", 960, 0, 760, 210)
holders.Top.Base = HUD_S
local TCX = 380
local TAPE_W, TAPE_Y, PX_DEG = 660, 70, 7
local tape = new("CanvasGroup", { Name = "Tape", AnchorPoint = V2(0.5, 0), Position = O(TCX, TAPE_Y), Size = O(TAPE_W, 46), BackgroundTransparency = 1 }, top)
new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BACK, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, tape)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.16, 0), NumberSequenceKeypoint.new(0.84, 0), NumberSequenceKeypoint.new(1, 1) }) }, tape)
new("Frame", { Position = O(0, 16), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = SECOND, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, tape)
local CARD = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
local ticks = {}
for k = 0, 71 do
	local deg = k * 5
	local card = CARD[deg]
	local major = deg % 90 == 0
	local h = if card then 12 elseif deg % 15 == 0 then 8 else 4
	local t = new("Frame", { AnchorPoint = V2(0.5, 1), Size = O(2, h), BackgroundColor3 = if card then PRIMARY else SECOND, BorderSizePixel = 0 }, tape)
	local lab
	if card then
		lab = plain({ AnchorPoint = V2(0.5, 0), Size = O(40, 22), FontFace = F_LAB, Text = card, TextSize = if major then 21 else 17, TextColor3 = if deg == 0 then ACTIVE elseif major then PRIMARY else SECOND }, tape)
	elseif deg % 15 == 0 then
		lab = plain({ AnchorPoint = V2(0.5, 0), Size = O(40, 16), FontFace = F_SB, Text = string.format("%03d", deg), TextSize = 14, TextColor3 = SECOND }, tape)
	end
	ticks[k + 1] = { Frame = t, Label = lab, Deg = deg }
end
-- markers: what the radar is showing, by bearing (mates blue, enemies red); nothing it doesn't show
local markers = {}
for i = 1, 10 do
	local m = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(7, 7), Rotation = 45, BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, tape)
	markers[i] = m
end
new("Frame", { AnchorPoint = V2(0.5, 0), Position = O(TCX, TAPE_Y - 4), Size = O(2, 24), BackgroundColor3 = ACTIVE, BorderSizePixel = 0, ZIndex = 3 }, top) -- lubber line
band(top, TCX - 10, TAPE_Y - 9, 20, 6, ACTIVE, 0, CAP.BackL, CAP.SlashR, 3)
-- heading box
local hdgBox = chamferRect(top, TCX - 46, 124, 92, 30, 8, BACK, 0.3)
new("Frame", { Position = O(TCX - 46, 153), Size = O(92, 1), BackgroundColor3 = ACTIVE, BackgroundTransparency = 0.4, BorderSizePixel = 0 }, top)
local heading = text(top, { AnchorPoint = V2(0.5, 0.5), Position = O(TCX - 8, 139), Size = O(56, 26), Text = "000", TextSize = 24, TextColor3 = PRIMARY })
local headingCard = plain({ AnchorPoint = V2(0, 0.5), Position = O(TCX + 18, 140), Size = O(28, 18), FontFace = F_LAB, Text = "N", TextSize = 16, TextColor3 = SECOND, TextXAlignment = Enum.TextXAlignment.Left }, top)
-- suit gauges: shield (left) and vitals (right), thin lines with a trailing damage chip
local G_W, G_Y = 210, 146
local suitL = plain({ Position = O(TCX - 66 - 210, G_Y + 9), Size = O(210, 16), FontFace = F_SB, Text = "", TextSize = 15, TextColor3 = SECOND, TextXAlignment = Enum.TextXAlignment.Left }, top)
local suitR = plain({ Position = O(TCX + 66, G_Y + 9), Size = O(210, 16), FontFace = F_SB, Text = "", TextSize = 15, TextColor3 = SECOND, TextXAlignment = Enum.TextXAlignment.Right }, top)
local function gauge(x: number, anchorRight: boolean, title: string, col: Color3)
	local track = new("Frame", { Position = O(x, G_Y), Size = O(G_W, 4), BackgroundColor3 = BACK, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, top)
	new("UIStroke", { Color = SECOND, Transparency = 0.7, Thickness = 1 }, track)
	local ax = if anchorRight then 1 else 0
	local chip = new("Frame", { AnchorPoint = V2(ax, 0), Position = UDim2.fromScale(ax, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = PRIMARY, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, track)
	local fill = new("Frame", { AnchorPoint = V2(ax, 0), Position = UDim2.fromScale(ax, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 2 }, track)
	local tl = plain({ AnchorPoint = V2(ax, 1), Position = O(if anchorRight then x + G_W else x, G_Y - 3), Size = O(90, 18), FontFace = F_LAB, Text = title, TextSize = 15, TextColor3 = SECOND, TextXAlignment = if anchorRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left }, top)
	local num = text(top, { AnchorPoint = V2(1 - ax, 1), Position = O(if anchorRight then x else x + G_W, G_Y - 1), Size = O(60, 24), Text = "100", TextSize = 22, TextColor3 = PRIMARY, TextXAlignment = if anchorRight then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right })
	return { Track = track, Fill = fill, Chip = chip, Title = tl, Num = num, Shown = 0, Chipped = 0, ChipAt = 0, Col = col }
end
local shieldG = gauge(TCX - 66 - G_W, false, "SHIELD", ACTIVE)
local healthG = gauge(TCX + 66, true, "VITALS", PRIMARY)
local shieldWarn = text(top, { AnchorPoint = V2(0.5, 0.5), Position = O(TCX, 170), Size = O(240, 18), FontFace = F_LAB, Text = "SHIELD DOWN", TextSize = 16, TextColor3 = AMBER, TextTransparency = 1 })
local status = text(top, { AnchorPoint = V2(0.5, 0.5), Position = O(TCX, 192), Size = O(340, 18), FontFace = F_LAB, Text = "", TextSize = 16, TextColor3 = ACTIVE, TextTransparency = 1 })

-- centre: one quiet ring around the HUD crosshair ─────────────────────────────────────
local ret = holder("Reticle", V2(0.5, 0.5), "X", 960, 540, 200, 200)
local RC = 100
local segs = {}
local adsHidReticle = false -- the visor ring is hidden while aiming (see the step)
for i, a in { 45, 135, 225, 315 } do
	segs[i] = img("ReticleSeg", { AnchorPoint = V2(0.5, 0.5), Position = O(RC, RC), Size = O(52, 52), Rotation = a, ImageColor3 = WHITE, ImageTransparency = 0.35 }, ret)
	segs[i]:SetAttribute("A", a)
end

-- homing tracker (shown only once an enemy is in range) ─────────────────────────────────
local trk = holder("Tracker", V2(0.5, 0.5), "X", 960, 540, 220, 260)
local TK = V2(110, 130)
local tSegs = {}
for i = 1, 3 do
	tSegs[i] = img("TrackSeg", { AnchorPoint = V2(0.5, 0.5), Position = O(TK.X, TK.Y), Size = O(87, 87), ImageColor3 = CYAN }, trk)
end
local tRing = img("Ring", { AnchorPoint = V2(0.5, 0.5), Position = O(TK.X, TK.Y), Size = O(107, 107), ImageColor3 = DEEP, ImageTransparency = 0.35 }, trk)
local tDot = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(TK.X, TK.Y), Size = O(5, 5), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, trk)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, tDot)
local tBr = {}
for i, c in { { -1, -1, 0 }, { 1, -1, 90 }, { 1, 1, 180 }, { -1, 1, 270 } } do
	tBr[i] = { Image = img(if KIT.Bracket4 then "Bracket4" else "Bracket", { AnchorPoint = V2(0.5, 0.5), Size = O(40, 40), Rotation = c[3], ImageColor3 = AMBER, ImageTransparency = 1 }, trk), SX = c[1], SY = c[2] }
end
local tDiamond = img("Diamond", { AnchorPoint = V2(0.5, 0.5), Position = O(TK.X, TK.Y), Size = O(56, 56), ImageColor3 = RED, ImageTransparency = 1 }, trk)
local tFlash = img("Ring", { AnchorPoint = V2(0.5, 0.5), Position = O(TK.X, TK.Y), Size = O(150, 150), ImageColor3 = RED, ImageTransparency = 1 }, trk)
local tTag = text(trk, { AnchorPoint = V2(0, 1), Size = O(160, 18), FontFace = F_LAB, Text = "SEARCH", TextSize = 15, TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Left })
local tRange = text(trk, { AnchorPoint = V2(0, 0), Size = O(160, 18), Text = "", TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left })
local tether = img("GlowLine", { AnchorPoint = V2(0.5, 0.5), Size = O(10, 8), ImageColor3 = RED, ImageTransparency = 1 }, group)

-- lower right: weapon panel — big count, reserve, name + mode, one thin magazine line ─────────
local ammo = holder("Ammo", V2(1, 1), "R", 1920, 1010, 560, 200)
holders.Ammo.Base = HUD_S
backPlate(ammo, 10, 50, 420, 145, 0)
local wpn = new("Frame", { Name = "Panel", Size = O(560, 200), BackgroundTransparency = 1 }, ammo) -- slides on weapon switch
local weaponName = text(wpn, { AnchorPoint = V2(1, 0.5), Position = O(392, 70), Size = O(300, 18), FontFace = F_LAB, Text = "", TextSize = 17, TextColor3 = PRIMARY, TextXAlignment = Enum.TextXAlignment.Right })
local fireMode = plain({ AnchorPoint = V2(0, 0.5), Position = O(400, 70), Size = O(120, 18), FontFace = F_LAB, Text = "", TextSize = 16, TextColor3 = SECOND, TextXAlignment = Enum.TextXAlignment.Left }, wpn)
local magNum = text(wpn, { AnchorPoint = V2(1, 1), Position = O(318, 154), Size = O(230, 70), Text = "30", TextSize = 64, TextColor3 = PRIMARY, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Bottom })
local magKick = new("UIScale", {}, magNum)
local reserveNum = plain({ AnchorPoint = V2(0, 1), Position = O(326, 145), Size = O(100, 24), FontFace = F_REG, Text = "/ 90", TextSize = 21, TextColor3 = SECOND, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom }, wpn)
local MAG_X, MAG_Y, MAG_W = 60, 166, 340
local magTrack = new("Frame", { Position = O(MAG_X, MAG_Y), Size = O(MAG_W, 3), BackgroundColor3 = SECOND, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, wpn)
local magFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = ACTIVE, BorderSizePixel = 0, ZIndex = 2 }, magTrack)
local magFlash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PRIMARY, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, magTrack)
local rangeTxt = plain({ AnchorPoint = V2(0, 0.5), Position = O(60, 70), Size = O(140, 18), FontFace = F_SB, Text = "", TextSize = 16, TextColor3 = SECOND, TextXAlignment = Enum.TextXAlignment.Left }, wpn)
local ammoState = plain({ AnchorPoint = V2(1, 0), Position = O(MAG_X + MAG_W, MAG_Y + 9), Size = O(240, 18), FontFace = F_LAB, Text = "", TextSize = 16, TextColor3 = AMBER, TextXAlignment = Enum.TextXAlignment.Right }, wpn)

-- lower left: clock + score tallies beside the radar ──────────────────────────────────
local ll = holder("LowerLeft", V2(0, 1), "L", 0, 1010, 600, 220)
holders.LowerLeft.Base = HUD_S
backPlate(ll, 120, 20, 500, 200, 180)
local clock = text(ll, { AnchorPoint = V2(0, 0.5), Position = O(380, 52), Size = O(120, 32), Text = "10:00", TextSize = 28, TextColor3 = PRIMARY, TextXAlignment = Enum.TextXAlignment.Left })
local blueTab = band(ll, 380, 74, 62, 20, DEEP, 0.15, CAP.SlashL, CAP.SlashR)
local redTab = band(ll, 448, 74, 62, 20, C(190, 70, 56), 0.15, CAP.SlashL, CAP.SlashR)
local blueNum = text(ll, { AnchorPoint = V2(0.5, 0.5), Position = O(411, 84), Size = O(40, 18), FontFace = F_LAB, Text = "00", TextSize = 15, TextColor3 = WHITE })
local redNum = text(ll, { AnchorPoint = V2(0.5, 0.5), Position = O(479, 84), Size = O(40, 18), FontFace = F_LAB, Text = "00", TextSize = 15, TextColor3 = WHITE })

-- abilities: tiles with ready / activating / active / cooldown states ──────────────────────
local ab = holder("Abilities", V2(0, 1), "L", 360 * HUD_S, 1010 - 6 * HUD_S, 300, 120)
holders.Abilities.Base = HUD_S
local nodes = {}
local ICONS = { PhaseDash = "IconDash", HighJump = "IconJump", PulseScan = "IconPulse", Grapple = "IconJump" }
local ICONS2 = { PhaseDash = "IconDash2", HighJump = "IconJump2", PulseScan = "IconScan2", Grapple = "IconJump2" }
local readyAt = {}
local TILE_W, TILE_H = 64, 46
for i, name in AbilityConfig.Order do
	local x = 20 + (i - 1) * 76
	local A = AbilityConfig.Abilities[name]
	local tab = chamferRect(ab, x, 36, TILE_W, TILE_H, 10, BACK, 0.3)
	local edge = new("Frame", { Position = O(x, 36 + TILE_H - 1), Size = O(TILE_W - 10, 1), BackgroundColor3 = SECOND, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 2 }, ab)
	-- effects live in a clipped window over the tile
	local fx = new("Frame", { Position = O(x, 36), Size = O(TILE_W, TILE_H), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 }, ab)
	local fill = new("Frame", { AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = ACTIVE, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 2 }, fx)
	local sweep = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(26, TILE_H * 2), Rotation = 18, Position = O(-30, TILE_H / 2), BackgroundColor3 = PRIMARY, BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, fx)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, sweep)
	local rise = new("Frame", { AnchorPoint = V2(0, 0.5), Size = O(TILE_W, 18), Position = O(0, TILE_H + 12), BackgroundColor3 = PRIMARY, BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, fx)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, rise)
	local accent = new("Frame", { Position = O(x, 36), Size = O(TILE_W - 10, 2), BackgroundColor3 = ACTIVE, BorderSizePixel = 0, ZIndex = 4 }, ab)
	local iconName = if KIT[ICONS2[name]] then ICONS2[name] else (ICONS[name] or "IconPulse")
	local icon = img(iconName, { AnchorPoint = V2(0.5, 0.5), Position = O(x + TILE_W / 2, 36 + TILE_H / 2), Size = O(28, 28), ImageColor3 = PRIMARY, ZIndex = 4 }, ab)
	local num = text(ab, { AnchorPoint = V2(0.5, 0.5), Position = O(x + TILE_W / 2, 36 + TILE_H / 2), Size = O(40, 20), Text = "", TextSize = 19, TextColor3 = PRIMARY, ZIndex = 5 })
	local prog = new("Frame", { Position = O(x, 36 + TILE_H + 3), Size = O(0, 2), BackgroundColor3 = ACTIVE, BorderSizePixel = 0, ZIndex = 4 }, ab)
	local key = plain({ AnchorPoint = V2(0.5, 0), Position = O(x + TILE_W / 2, 36 + TILE_H + 8), Size = O(70, 18), FontFace = F_LAB, Text = A and A.KeyLabel or "", TextSize = 16, TextColor3 = SECOND }, ab)
	local ring = img("Ring", { AnchorPoint = V2(0.5, 0.5), Position = O(x + TILE_W / 2, 36 + TILE_H / 2), Size = O(10, 10), ImageColor3 = ACTIVE, ImageTransparency = 1, ZIndex = 5 }, ab)
	local node = {
		Name = name, X = x, Tab = tab, Edge = edge, Fill = fill, Sweep = sweep, Rise = rise, Accent = accent, Icon = icon, Num = num, Prog = prog, Key = key, Ring = ring,
		Cooldown = A and A.Cooldown or 1, ActiveTime = A and A.ActiveTime or 0.2, State = "Ready", At = 0, Ready = true,
	}
	function node.Flash()
		accent.BackgroundColor3 = PRIMARY
		accent.BackgroundTransparency = 0
		tween(accent, 0.35, { BackgroundColor3 = ACTIVE })
	end
	function node.Activate()
		node.State, node.At = "Activating", os.clock()
		node.Flash()
		tab.Color(ACTIVE)
		tab.Alpha(0.55)
		tween(icon, 0.05, { ImageColor3 = WHITE })
		if name == "PhaseDash" then
			-- a fast horizontal sweep through the tile, the icon kicks forward
			sweep.Visible = true
			sweep.Position = O(-30, TILE_H / 2)
			tween(sweep, 0.24, { Position = O(TILE_W + 30, TILE_H / 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			icon.Position = O(x + TILE_W / 2 - 6, 36 + TILE_H / 2)
			tween(icon, 0.22, { Position = O(x + TILE_W / 2, 36 + TILE_H / 2) }, Enum.EasingStyle.Back)
		elseif name == "HighJump" then
			-- a vertical pulse rises through the tile, the icon lifts and settles
			rise.Visible = true
			rise.Position = O(0, TILE_H + 12)
			tween(rise, 0.32, { Position = O(0, -12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			icon.Position = O(x + TILE_W / 2, 36 + TILE_H / 2 - 7)
			tween(icon, 0.4, { Position = O(x + TILE_W / 2, 36 + TILE_H / 2) }, Enum.EasingStyle.Bounce)
		else
			-- an expanding ring out of the icon (the same ring that crosses the radar and the shell)
			ring.Size = O(12, 12)
			ring.ImageTransparency = 0.05
			tween(ring, 0.7, { Size = O(120, 120), ImageTransparency = 1 }, Enum.EasingStyle.Quad)
		end
	end
	nodes[name] = node
	readyAt[name] = 0
end

-- radar: the HUD's own dots (teammates, enemies only while firing) on the visor's instrument ────
-- The co-dev radar keeps detecting and placing its dots; its disc graphics are hidden and the visor
-- draws the instrument under them: rings, bezel ticks, a rotating sweep, the heading chevron.
local radarSrc = hudRoot:FindFirstChild("Radar")
local radarDisc, radarDots, rsweep, rpulse = nil, {}, nil, nil
local radarSweepRate = 70 -- deg/s
local radarBoost = 0 -- 0..1, Pulse Scan / boot spins the sweep up
if radarSrc then
	holder("Radar", V2(0.5, 0.5), "L", 250 * HUD_S, 1010 - 150 * HUD_S, 190, 190)
	local rh = holders.Radar.Frame
	local feed = radarSrc:FindFirstChild("KillFeed")
	if feed then
		holder("Feed", V2(0, 0), "L", 70, 84, 420, 140)
		feed.Position = O(0, 0)
		feed.Parent = holders.Feed.Frame
	end
	radarSrc.Size = O(190, 210)
	radarSrc.AnchorPoint = V2(0.5, 0)
	radarSrc.Position = UDim2.new(0.5, 0, 0, 7)
	radarSrc.Parent = rh
	local sc = radarSrc:FindFirstChildOfClass("UIScale")
	if sc then
		sc:Destroy()
	end
	local disc = radarSrc:FindFirstChild("Disc")
	radarDisc = disc
	if disc then
		disc.BackgroundTransparency = 1
		for _, d in disc:GetChildren() do
			if d:IsA("UIStroke") or d:IsA("UIGradient") then
				d.Enabled = false
			elseif d:IsA("TextLabel") then
				d.Visible = false -- the centre glyph; the visor draws its own chevron
			elseif d:IsA("GuiObject") and d.ZIndex < 3 then
				d.Visible = false -- the co-dev rings / spokes / bezel ticks (dots sit at ZIndex 3)
			elseif d:IsA("Frame") and d.ZIndex == 3 then
				table.insert(radarDots, d)
			end
		end
		local inst = new("Frame", { Name = "VisorRadar", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BACK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 1 }, disc)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, inst)
		new("UIStroke", { Color = SECOND, Thickness = 1.5, Transparency = 0.25 }, inst)
		for _, r in { 0.68, 0.36 } do
			local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(r, r), BackgroundTransparency = 1, ZIndex = 1 }, inst)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
			new("UIStroke", { Color = SECOND, Thickness = 1, Transparency = 0.6 }, ring)
		end
		for k = 0, 23 do -- bezel: a tick every 15°, longer at the quarters
			local a = rad(k * 15)
			local long = k % 6 == 0
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, math.sin(a) * 84, 0.5, -math.cos(a) * 84), Size = O(if long then 2 else 1, if long then 8 else 4), Rotation = k * 15, BackgroundColor3 = if long then PRIMARY else SECOND, BackgroundTransparency = if long then 0.1 else 0.4, BorderSizePixel = 0, ZIndex = 1 }, inst)
		end
		-- the sweep: a fading wedge (kit image) rotating about the centre
		rsweep = img("RadarSweep", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ImageColor3 = ACTIVE, ImageTransparency = 0.55, ZIndex = 2 }, inst)
		rpulse = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0, 0), BackgroundTransparency = 1, ZIndex = 2 }, inst)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, rpulse)
		new("UIStroke", { Color = ACTIVE, Thickness = 2, Transparency = 1 }, rpulse)
		-- you: a small chevron pointing where you face (the radar turns with you, so it always points up)
		local me = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(14, 14), BackgroundTransparency = 1, ZIndex = 4 }, disc)
		for _, s in { -1, 1 } do
			new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, s * 3, 0, 1), Size = O(2, 12), Rotation = -s * 24, BackgroundColor3 = PRIMARY, BorderSizePixel = 0, ZIndex = 4 }, me)
		end
		-- field of view wedge edges (±35° from up)
		for _, s in { -1, 1 } do
			local a = rad(s * 35)
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, math.sin(a) * 36, 0.5, -math.cos(a) * 36), Size = O(1, 72), Rotation = s * 35, BackgroundColor3 = PRIMARY, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 1 }, inst)
		end
	end
	for _, d in radarSrc:GetChildren() do
		if d:IsA("TextLabel") then
			d.FontFace = F_LAB
			d.TextSize = 15
			d.TextColor3 = SECOND
		end
	end
	holders.Radar.Base = 0.85 * HUD_S
end

-- ─── layout ───────────────────────────────────────────────────────────────────────────
-- ─── v6 holographic HUD (VisorHolo): 3D panels in front of the eye; the v5 2D clusters retire ─────
local Holo = require(Vantage.UI:WaitForChild("VisorHolo"))
local holo = Holo.new({
	Player = player,
	Feed = Feed,
	AbilityConfig = AbilityConfig,
	Glass = glass,
	Group = group,
	RadarDots = radarDots,
	Ability = function(name: string)
		local n = nodes[name]
		if not n then
			return "Ready", 0, 1
		end
		return n.State, math.max(0, (readyAt[name] or 0) - os.clock()), n.Cooldown
	end,
	LastKill = function(): string
		local fh = holders.Feed and holders.Feed.Frame
		local feed = fh and fh:FindFirstChild("KillFeed")
		if not feed then
			return ""
		end
		local best, order = nil, -math.huge
		for _, item in feed:GetChildren() do
			if item:IsA("GuiObject") and item.Visible and item.LayoutOrder > order then
				best, order = item, item.LayoutOrder
			end
		end
		if not best then
			return ""
		end
		local parts = {}
		for _, d in best:GetDescendants() do
			if d:IsA("TextLabel") and d.Text ~= "" then
				table.insert(parts, d.Text)
			end
		end
		return table.concat(parts, "  ")
	end,
})
for _, n in { "Top", "Ammo", "Abilities", "LowerLeft", "Radar", "Feed" } do
	if holders[n] then
		holders[n].Frame.Parent = stash -- still updated (the radar keeps detecting), never shown
	end
end

local K = 1
local function layout()
	local vp = Workspace.CurrentCamera.ViewportSize
	if vp.X < 50 then
		return
	end
	K = math.clamp(vp.Y / 1080, 0.5, 2)
	for name, h in holders do
		h.Scale.Scale = K * (h.Base or 1)
		local y = h.Y
		if h.Ax == "C" then
			h.Frame.Position = UDim2.new(0.5, (h.X - 960) * K, 0, y * K)
		elseif h.Ax == "L" then
			h.Frame.Position = UDim2.new(0, h.X * K, 0, y * K)
		elseif h.Ax == "R" then
			h.Frame.Position = UDim2.new(1, (h.X - 1920) * K, 0, y * K)
		end
	end
	for _, s in decoScale do
		s.Scale = K
	end
	-- eyes wrapper: 16:9 image covering the screen width (borders fill the rest)
	local w = math.max(vp.X, vp.Y * 16 / 9)
	eyes.Size = O(w, w * 9 / 16)
	hc:Resize(vp.Y)
end
layout()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)

-- ─── visibility helpers ────────────────────────────────────────────────────────────────
local CLUSTERS = { "Top", "Ammo", "Abilities", "LowerLeft", "Radar", "Reticle" }
local function setHudVisible(on: boolean)
	group.Visible = on
end
local function setClusters(on: boolean)
	for _, n in CLUSTERS do
		if holders[n] then
			holders[n].Frame.Visible = on
		end
	end
	for _, n in { "Perf", "SettingsHint" } do
		local g = group:FindFirstChild(n)
		if g then
			g.Visible = on
		end
	end
end
local function flickerOn(name: string, t0: number, tok: number)
	local h = holders[name]
	if not h then
		return
	end
	task.delay(t0, function()
		if tok ~= token then
			return
		end
		local f = h.Frame
		local base = f.Position
		f.Visible = true
		f.Position = base + O(0, if f.AnchorPoint.Y > 0.5 then 12 * K else -10 * K)
		tween(f, 0.3, { Position = base }, Enum.EasingStyle.Quint)
		task.wait(0.045)
		if tok ~= token then
			return
		end
		f.Visible = false
		task.wait(0.05)
		if tok ~= token then
			return
		end
		f.Visible = true
	end)
end
local function flickerOff(name: string, t0: number, tok: number)
	local h = holders[name]
	if not h then
		return
	end
	task.delay(t0, function()
		if tok ~= token then
			return
		end
		h.Frame.Visible = false
		task.wait(0.04)
		if tok ~= token then
			return
		end
		h.Frame.Visible = true
		task.wait(0.05)
		if tok ~= token then
			return
		end
		h.Frame.Visible = false
	end)
end
local function setBlackout(on: boolean)
	player:SetAttribute("VisorBlackout", on)
end
local function resetShutter()
	plate.Position = UDim2.fromScale(0, -1.05)
	plate.Visible = true
	black.BackgroundTransparency = 1
	coreGlow.ImageTransparency = 1
	eyes.Visible = false
	eyeScale.Scale = 1
	eyeMask.ImageTransparency = 0
	eyeGlow.ImageTransparency = 1
	for _, s in swoosh do
		s.ImageTransparency = 1
	end
	diag.TextTransparency = 1
end
local function setFrame(on: boolean)
	for _, q in frameQ do
		q.Image.ImageTransparency = if on then 0 else 1
	end
end
local function applyGlass(on: boolean, instant: boolean?)
	glass.Enabled = on
	setFrame(on)
	local props = if on then TINT_ON else TINT_OFF
	if instant then
		for k, v in props do
			(tint :: any)[k] = v
		end
	else
		tween(tint, 0.6, props, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end
local hum: Sound? = nil
local function stopHum()
	if hum then
		local h = hum
		hum = nil
		tween(h, 0.5, { Volume = 0 })
		task.delay(0.6, function()
			h:Destroy()
		end)
	end
end
local function setHands(w: number, h: number)
	Feed.Hands.W, Feed.Hands.H = w, h
end

local function snapClosed()
	token += 1
	seq = nil
	state = "Closed"
	shutter.Enabled = false
	resetShutter()
	setBlackout(false)
	setHands(0, 0)
	applyGlass(true, true)
	hc:SetOn(true)
	holo:SetShown(true, true)
	setHudVisible(true)
	setClusters(true)
	player:SetAttribute("VisorClosed", true)
end
local function snapOpen()
	token += 1
	seq = nil
	state = "Open"
	shutter.Enabled = false
	resetShutter()
	setBlackout(false)
	setHands(0, 0)
	applyGlass(false, true)
	holo:SetShown(false, true)
	setHudVisible(false)
	player:SetAttribute("VisorClosed", false)
end

-- rim pulse: a bright section travelling across one quadrant of the rim
local function rimPulse(quadIndex: number?, duration: number?, strength: number?)
	local q = rimQ[quadIndex or math.random(1, 4)]
	local d = duration or (1.0 + math.random() * 0.8)
	local s = strength or 0.55
	local rot = math.random(0, 359)
	q.Grad.Rotation = rot
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) / d
		if a >= 1 or not glass.Enabled then
			conn:Disconnect()
			q.Image.ImageTransparency = 1
			return
		end
		q.Grad.Offset = V2((a * 2 - 1) * math.cos(rad(rot)), (a * 2 - 1) * math.sin(rad(rot)))
		q.Image.ImageTransparency = 1 - s * math.sin(a * math.pi)
	end)
end

-- reticle segments: assemble (fly in + snap) / disperse
local function reticleIn(dur: number)
	for i, s in segs do
		local a = s:GetAttribute("A")
		local r = rad(a)
		s.Position = O(RC + math.cos(r) * 46, RC + math.sin(r) * 46)
		s.Rotation = a + (if i % 2 == 0 then 70 else -70)
		s.ImageTransparency = 1
		tween(s, dur, { Position = O(RC, RC), Rotation = a, ImageTransparency = 0.35 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, (i - 1) * 0.04)
	end
end
local function reticleOut(dur: number)
	for i, s in segs do
		local a = s:GetAttribute("A")
		local r = rad(a)
		tween(s, dur, { Position = O(RC + math.cos(r) * 40, RC + math.sin(r) * 40), Rotation = a + (if i % 2 == 0 then 50 else -50), ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
end

-- ─── close (activate) — 2.3 s, no hands: straight into the optics start-up ──────────────
-- 0.00 sealed: black, clunk · 0.10 core light flickers · 0.35 eyes ignite · 0.45 swoosh along the slits
-- 0.75 eyes burst open (world, tint, frame) · 0.95 rim lights in sections · 1.05 reticle snaps together
-- 1.20-1.80 telemetry online in stages · 2.0 chime
local function closeHelmet()
	if state ~= "Open" then
		return
	end
	token += 1
	local tok = token
	state = "Closing"
	resetShutter()
	shutter.Enabled = true
	plate.Visible = false
	setHudVisible(false)
	setBlackout(true)
	local function at(t: number, fn)
		task.delay(t, function()
			if tok == token then
				fn()
			end
		end)
	end
	hc:SetOn(false)
	play("Lock", 0.45, 1.3)
	black.BackgroundTransparency = 0.6
	tween(black, 0.08, { BackgroundTransparency = 0 })
	eyes.Visible = true
	eyeMask.ImageTransparency = 0
	eyeGlow.ImageTransparency = 1
	at(0.1, function()
		stopHum()
		hum = play("Hum", 0)
		hum.Looped = true
		tween(hum, 0.3, { Volume = 0.1 })
		coreGlow.ImageTransparency = 0.3
		tween(coreGlow, 0.08, { ImageTransparency = 1 })
	end)
	at(0.2, function()
		coreGlow.ImageTransparency = 0.15
		tween(coreGlow, 0.15, { ImageTransparency = 0.9 })
	end)
	at(0.35, function()
		play("PowerOn")
		eyeGlow.ImageTransparency = 0.15
		tween(coreGlow, 0.15, { ImageTransparency = 1 })
	end)
	at(0.39, function()
		eyeGlow.ImageTransparency = 0.8
	end)
	at(0.43, function()
		eyeGlow.ImageTransparency = 0
		tween(eyeGlow, 0.25, { ImageTransparency = 0.2 })
	end)
	at(0.45, function()
		play("Whoosh", 0.4, 1.35)
		for i, sx in { -1, 1 } do
			local sw = swoosh[i]
			sw.Position = UDim2.fromScale(0.5 + sx * 0.05, 0.474)
			sw.ImageTransparency = 0
			tween(sw, 0.24, { Position = UDim2.fromScale(0.5 + sx * 0.2, 0.48) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(sw, 0.1, { ImageTransparency = 1 }, nil, nil, 0.18)
		end
	end)
	at(0.75, function()
		play("Whoosh", 0.5, 0.85)
		play("Scan", 0.2, 1.25)
		applyGlass(true)
		Bus.Emit("Boot")
		black.BackgroundTransparency = 1
		tween(eyeScale, 0.38, { Scale = 9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(eyeGlow, 0.38, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
	at(0.95, function()
		setBlackout(false)
	end)
	at(1.15, function()
		eyes.Visible = false
	end)
	for i = 1, 4 do
		at(0.95 + i * 0.06, function()
			rimPulse(({ 1, 2, 4, 3 })[i], 0.6, 0.8)
		end)
	end
	at(1.05, function()
		setHudVisible(true)
		setClusters(false)
		holders.Reticle.Frame.Visible = true
		reticleIn(0.3)
		holo:SetShown(true) -- the holograms draw in, brow first, as the veins light down the frame
		play("Beeps")
	end)
	-- systems come online in the order the honeycomb wave reaches them (brow first, then down the sides)
	flickerOn("Top", 1.15, tok)
	at(1.15, function()
		-- the compass tape opens out from the lubber line; the suit gauges charge up from empty
		tape.Size = O(0, 46)
		tween(tape, 0.5, { Size = O(TAPE_W, 46) }, Enum.EasingStyle.Quint)
		shieldG.Shown, shieldG.Chipped, healthG.Shown, healthG.Chipped = 0, 0, 0, 0
	end)
	flickerOn("Radar", 1.32, tok)
	at(1.32, function()
		radarBoost = 0.6
	end)
	flickerOn("LowerLeft", 1.44, tok)
	flickerOn("Abilities", 1.52, tok)
	flickerOn("Ammo", 1.62, tok)
	at(1.55, function()
		play("Beeps", 0.16, 1.3)
	end)
	at(2.0, function()
		for _, n in { "Perf", "SettingsHint" } do
			local g = group:FindFirstChild(n)
			if g then
				g.Visible = true
			end
		end
		play("Chime")
		status.Text = "SYSTEMS ONLINE"
		status.TextTransparency = 0
		tween(status, 0.6, { TextTransparency = 1 }, nil, nil, 0.8)
	end)
	at(2.3, function()
		stopHum()
		shutter.Enabled = false
		resetShutter()
		state = "Closed"
		player:SetAttribute("VisorClosed", true)
	end)
end

-- ─── open (deactivate) — 1.0 s: telemetry off, eyes close back to slits, black, clear view ─
local function openHelmet()
	if state ~= "Closed" then
		return
	end
	token += 1
	local tok = token
	state = "Opening"
	resetShutter()
	local function at(t: number, fn)
		task.delay(t, function()
			if tok == token then
				fn()
			end
		end)
	end
	play("PowerOff")
	Bus.Emit("Shutdown")
	holo:SetShown(false)
	for i, n in { "LowerLeft", "Radar", "Abilities", "Ammo", "Top" } do
		flickerOff(n, (i - 1) * 0.035, tok)
	end
	for _, n in { "Perf", "SettingsHint" } do
		local g = group:FindFirstChild(n)
		if g then
			g.Visible = false
		end
	end
	reticleOut(0.18)
	at(0.2, function()
		setHudVisible(false)
		setBlackout(true)
		shutter.Enabled = true
		plate.Visible = false
		eyes.Visible = true
		eyeScale.Scale = 9
		eyeGlow.ImageTransparency = 1
		play("Whoosh", 0.4, 0.7)
		tween(eyeScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		tween(eyeGlow, 0.25, { ImageTransparency = 0.2 }, nil, nil, 0.08)
		tween(tint, 0.35, TINT_OFF, Enum.EasingStyle.Sine)
	end)
	at(0.55, function()
		glass.Enabled = false
		black.BackgroundTransparency = 0
		play("Lock", 0.35, 1.0)
		tween(eyeGlow, 0.15, { ImageTransparency = 1 })
	end)
	at(0.72, function()
		eyes.Visible = false
		tween(black, 0.25, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		setBlackout(false)
	end)
	at(1.0, function()
		shutter.Enabled = false
		resetShutter()
		state = "Open"
		player:SetAttribute("VisorClosed", false)
	end)
end

-- hands + plate curves (per frame while a sequence runs)
local function tipFrac(h: number): number
	-- screen height (0 top .. 1 bottom) of the knuckles: measured by Viewmodel this frame when the
	-- hands are up; otherwise estimated from the same hand targets (depth 1.25 studs)
	if Feed.TipY and Feed.Hands.W > 0.5 then
		return Feed.TipY
	end
	local cam = Workspace.CurrentCamera
	local y = -0.95 + 1.75 * h + 0.16
	local half = 1.7 * math.tan(rad(cam.FieldOfView / 2))
	return 0.5 - (y / half) * 0.5
end
local function stepSequence()
	-- Studio tuning hooks: VisorHandTune "x,z,rx,ry,rz" (hand pose), VisorDebugHands "w,h,plateTop" (freeze)
	local tune = player:GetAttribute("VisorHandTune")
	if type(tune) == "string" then
		local v = string.split(tune, ",")
		Feed.Tune = { X = tonumber(v[1]), Z = tonumber(v[2]), RX = tonumber(v[3]), RY = tonumber(v[4]), RZ = tonumber(v[5]) }
	else
		Feed.Tune = nil
	end
	local dbg = player:GetAttribute("VisorDebugHands")
	if type(dbg) == "string" then
		local v = string.split(dbg, ",")
		local w, h, pt = tonumber(v[1]) or 0, tonumber(v[2]) or 0, v[3]
		setHands(w, h)
		shutter.Enabled = true
		plate.Visible = true
		plate.Position = UDim2.fromScale(0, if pt == "tip" then math.min(tipFrac(h), 1) - 1 else (tonumber(pt) or -1.05))
		return
	end
	if not seq then
		return
	end
	local t = os.clock() - seq.T0
	if seq.Kind == "Close" then
		local w = smooth(0, 0.3, t) * (1 - smooth(0.98, 1.55, t))
		local h
		if t < 0.5 then
			h = smooth(0.04, 0.44, t)
		else
			h = 1 - 0.7 * smooth(0.5, 0.86, t)
		end
		setHands(w, h)
		if t < 0.28 then
			plate.Position = UDim2.fromScale(0, -1.05)
		elseif t < 0.45 then
			-- the visor's edge comes down out of the brow into the waiting fingers
			local a = smooth(0.28, 0.45, t)
			plate.Position = UDim2.fromScale(0, -1.05 + (math.min(tipFrac(h), 1) + 0.05) * a)
		elseif t < 0.86 then
			plate.Position = UDim2.fromScale(0, math.min(tipFrac(h), 1) - 1)
		elseif t < 0.92 then
			-- the hands let go and the plate's own weight slams it shut
			seq.SlamFrom = seq.SlamFrom or math.min(tipFrac(h), 1)
			local a = smooth(0.86, 0.92, t)
			plate.Position = UDim2.fromScale(0, seq.SlamFrom + (1 - seq.SlamFrom) * a - 1)
		else
			plate.Position = UDim2.fromScale(0, 0)
		end
	else
		local w = smooth(0.74, 0.95, t) * (1 - smooth(1.45, 1.9, t))
		local h = smooth(0.95, 1.45, t)
		setHands(w, h)
		if t >= 0.82 and t < 1.42 then
			plate.Position = UDim2.fromScale(0, math.min(tipFrac(h), 1) - 1)
		elseif t >= 1.42 then
			-- the last push flicks it up into the brow, then the hands drop back to the gun
			seq.FlickFrom = seq.FlickFrom or (plate.Position.Y.Scale + 1)
			local a = smooth(1.42, 1.58, t)
			plate.Position = UDim2.fromScale(0, seq.FlickFrom + (-0.05 - seq.FlickFrom) * a - 1)
		end
	end
end

-- ─── input ───────────────────────────────────────────────────────────────────────────
-- B3: cache the two menu ScreenGui lookups (deployed runs every frame from the render step);
-- reuse a cached ref while it is still parented to the PlayerGui, re-find only otherwise
local tsGui: Instance? = nil
local mmGui: Instance? = nil
local function deployed(): boolean
	local ch = player.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	if not (hudGui.Enabled and h and h.Health > 0) then
		return false
	end
	if not (tsGui and tsGui.Parent == playerGui) then
		tsGui = playerGui:FindFirstChild("TeamSelect")
	end
	if not (mmGui and mmGui.Parent == playerGui) then
		mmGui = playerGui:FindFirstChild("VantageMainMenu")
	end
	return not ((tsGui and tsGui:IsA("ScreenGui") and tsGui.Enabled) or (mmGui and mmGui:IsA("ScreenGui") and mmGui.Enabled))
end
local function toggle()
	if not deployed() then
		return
	end
	if state == "Closed" then
		play("VoiceOff")
		openHelmet()
	elseif state == "Open" then
		play("VoiceOn")
		closeHelmet()
	end
end
ContextActionService:BindAction("VantageHelmet", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.H)
player:GetAttributeChangedSignal("VisorToggle"):Connect(toggle)
-- Studio test hook: VisorTestEvent = "Damage,<angleDeg>" | "PulseScan" | "Dash" | "Jump" | "Lock" | "Fire" ...
player:GetAttributeChangedSignal("VisorTestEvent"):Connect(function()
	local v = string.split(tostring(player:GetAttribute("VisorTestEvent")), ",")
	if v[1] == "Damage" then
		local a = math.rad(tonumber(v[2]) or 0)
		Bus.Emit("Damage", V2(math.cos(a), math.sin(a)))
	elseif v[1] ~= "" then
		Bus.Emit(v[1], v[2])
	end
end)

-- ─── ambient behaviour (calm; one effect at a time, randomised) ───────────────────────────
local nextAt = {
	Pulse = os.clock() + 4 + math.random() * 4,
	Reflect = os.clock() + 9 + math.random() * 8,
	Scan = os.clock() + 14 + math.random() * 10,
	Calib = os.clock() + 18 + math.random() * 10,
	Blink = os.clock() + 3 + math.random() * 4,
}
local quietUntil = 0
local function runScan()
	local left = math.random() < 0.5
	scanHolder.Position = UDim2.fromScale(if left then 0.07 else 0.67, if math.random() < 0.5 then 0.14 else 0.42)
	scanHolder.Visible = true
	scanLine.Position = UDim2.fromScale(0, 0)
	for _, t in scanTicks do
		t.TextTransparency = 1
		t.Position = UDim2.new(if left then 0 else 0.55, 0, t.Position.Y.Scale, 0)
	end
	tween(scanLine, 1.1, { Position = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for i, t in scanTicks do
		task.delay(1.1 * (i * 0.25) - 0.05, function()
			t.TextTransparency = 0.15
			tween(t, 0.6, { TextTransparency = 1 })
		end)
	end
	task.delay(1.15, function()
		scanHolder.Visible = false
	end)
end
local function runCalib()
	-- reticle segments rotate a notch and settle (optics recalibrating)
	for i, s in segs do
		local a = s:GetAttribute("A")
		tween(s, 0.35, { Rotation = a + (if i % 2 == 0 then 22 else -22) }, Enum.EasingStyle.Quad)
		tween(s, 0.45, { Rotation = a }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.4)
	end
end
local function ambient(now: number)
	if state ~= "Closed" or now < quietUntil then
		return
	end
	if now >= nextAt.Pulse then
		nextAt.Pulse = now + 7 + math.random() * 9
		quietUntil = now + 1.4
		rimPulse()
	elseif now >= nextAt.Reflect then
		nextAt.Reflect = now + 12 + math.random() * 14
		quietUntil = now + 1.6
		refl.Sweep = 1
	elseif now >= nextAt.Scan then
		-- v6: the old floating scan labels are retired (the panels carry their own scan lines)
		nextAt.Scan = now + 16 + math.random() * 16
	elseif now >= nextAt.Calib then
		nextAt.Calib = now + 20 + math.random() * 16
		quietUntil = now + 1.1
		runCalib()
	end
	if now >= nextAt.Blink then
		nextAt.Blink = now + 3 + math.random() * 5
	end
end

-- ─── homing tracker: search -> acquire -> lock (line of sight only, enemies only) ───────────
local humanoids = {}
local function track(h: Instance)
	if h:IsA("Humanoid") then
		humanoids[h] = true
	end
end
for _, d in Workspace:GetDescendants() do
	track(d)
end
Workspace.DescendantAdded:Connect(track)
Workspace.DescendantRemoving:Connect(function(d)
	humanoids[d] = nil
end)
local function teamOf(model: Model): any
	local p = Players:GetPlayerFromCharacter(model)
	if p then
		return if p.Team and not p.Neutral then p.Team.Name else nil
	end
	return model:GetAttribute("Team")
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local function filterList()
	local f = { Workspace.CurrentCamera }
	if player.Character then
		table.insert(f, player.Character)
	end
	local fx = Workspace:FindFirstChild("VantageWeaponFX")
	if fx then
		table.insert(f, fx)
	end
	return f
end
local LOCK_RANGE = 180 -- studs
local TR = { Mode = "Search", Pos = nil :: Vector2?, Target = nil :: Model?, Seen = 0, Held = 0, NextScan = 0, LockedAt = 0 }
local function visibleEnemy(): Model?
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local center = vp / 2
	local mine = if player.Team and not player.Neutral then player.Team.Name else nil
	rayParams.FilterDescendantsInstances = filterList()
	local best, bestD = nil, math.huge
	for h in humanoids do
		if not h.Parent or h.Health <= 0 then
			continue
		end
		local model = h.Parent
		if not model:IsA("Model") or model == player.Character then
			continue
		end
		local theirs = teamOf(model)
		if mine and theirs and tostring(theirs) == mine then
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if not root then
			continue
		end
		local dist = (root.Position - cam.CFrame.Position).Magnitude
		if dist > LOCK_RANGE then
			continue
		end
		local sp, on = cam:WorldToViewportPoint(root.Position)
		if not on or sp.Z <= 0 then
			continue
		end
		-- inside the visor glass (not behind the frame)
		local nx, ny = (sp.X - center.X) / (vp.X * 0.47), (sp.Y - center.Y) / (vp.Y * 0.46)
		if nx * nx + ny * ny > 1 then
			continue
		end
		local d2 = (V2(sp.X, sp.Y) - center).Magnitude
		if d2 >= bestD then
			continue
		end
		-- line of sight to the head or torso
		local seen = false
		for _, pn in { "Head", "UpperTorso", "HumanoidRootPart" } do
			local p = model:FindFirstChild(pn)
			if p then
				local res = Workspace:Raycast(cam.CFrame.Position, p.Position - cam.CFrame.Position, rayParams)
				if res and res.Instance:IsDescendantOf(model) then
					seen = true
					break
				end
			end
		end
		if seen then
			best, bestD = model, d2
		end
	end
	return best
end
local function colorAll(col: Color3)
	for _, s in tSegs do
		s.ImageColor3 = col
	end
	for _, b in tBr do
		b.Image.ImageColor3 = col
	end
	tTag.TextColor3 = col
end
local function stepTracker(now: number, dt: number)
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local center = vp / 2
	if not TR.Pos then
		TR.Pos = center
	end
	if state ~= "Closed" then
		trk.Visible = false
		tether.ImageTransparency = 1
		return
	end
	-- re-evaluate the target at 10 Hz
	if now >= TR.NextScan then
		TR.NextScan = now + 0.1
		local found = visibleEnemy()
		if found then
			if found ~= TR.Target then
				TR.Target, TR.Held = found, 0
				TR.Mode = "Acquire"
				colorAll(AMBER)
				tTag.Text = "ACQUIRING"
				play("Beeps", 0.12, 1.5)
			end
			TR.Seen = now
		elseif TR.Target and now - TR.Seen > 0.3 then
			TR.Target, TR.Mode = nil, "Search"
			colorAll(CYAN)
			tTag.Text = "SEARCH"
			tRange.Text = ""
		end
	end
	local goal, boxW, boxH = nil, 52, 98
	local target = TR.Target
	local root = target and (target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart)
	if target and root then
		local topP = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 2.6, 0))
		local botP = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3.0, 0))
		goal = V2((topP.X + botP.X) / 2, (topP.Y + botP.Y) / 2)
		local hpx = math.max(30, botP.Y - topP.Y) / K
		boxH, boxW = hpx / 2 + 10, math.max(22, hpx * 0.26)
		local dist = (root.Position - cam.CFrame.Position).Magnitude
		tRange.Text = string.format("%03d M", math.floor(dist * 0.28 + 0.5))
		local close = (TR.Pos - goal).Magnitude < 10
		if TR.Mode == "Acquire" then
			TR.Held = if close then TR.Held + dt else 0
			if TR.Held > 0.3 then
				TR.Mode, TR.LockedAt = "Lock", now
				colorAll(RED)
				tTag.Text = "ENGAGE"
				Bus.Emit("Lock", true)
				play("Lock", 0.3, 1.6)
				play("Beeps", 0.2, 1.8)
				tFlash.ImageTransparency = 0.2
				tFlash.Size = O(70, 70)
				tween(tFlash, 0.35, { Size = O(170, 170), ImageTransparency = 1 })
			end
		end
	else
		-- search: drift slowly around the central glass
		local t = now * 0.23
		goal = center + V2(math.sin(t * 1.3) * vp.Y * 0.2, math.sin(t * 0.9 + 1.1) * vp.Y * 0.11)
	end
	local follow = if TR.Mode == "Search" then 1.6 elseif TR.Mode == "Acquire" then 9 else 22
	TR.Pos = TR.Pos:Lerp(goal, math.min(1, dt * follow))
	local insetY = if hudGui.IgnoreGuiInset then 0 else game:GetService("GuiService"):GetGuiInset().Y
	trk.Position = O(TR.Pos.X, TR.Pos.Y - insetY)
	-- visuals per mode
	local search = TR.Mode == "Search"
	local lock = TR.Mode == "Lock"
	trk.Visible = not search -- nothing in range: no tracker on the glass
	for i, s in tSegs do
		s.Visible = search
		s.Rotation = (now * 40 + i * 120) % 360
	end
	tRing.Visible = search
	tDot.Visible = not lock
	tDiamond.ImageTransparency = if lock then 0.05 else 1
	tDiamond.Position = O(TK.X, TK.Y - boxH * 0.28)
	local bw, bh = if search then 0 else boxW, if search then 0 else boxH
	for _, b in tBr do
		b.Image.ImageTransparency = if search then 1 else 0.05
		b.Image.Position = O(TK.X + b.SX * bw, TK.Y + b.SY * bh)
	end
	tTag.Position = if search then O(TK.X - 30, TK.Y + 64) else O(TK.X + bw + 12, TK.Y - bh + 4)
	tRange.Position = O(TK.X + bw + 12, TK.Y - bh + 8)
	tRange.Visible = not search
	-- tether from the crosshair to a lock
	if lock then
		local d = TR.Pos - center
		local len = d.Magnitude - 40 * K
		if len > 20 then
			tether.Position = O(center.X + d.X / 2, center.Y + d.Y / 2 - insetY)
			tether.Size = O(len, 8 * K)
			tether.Rotation = math.deg(math.atan2(d.Y, d.X))
			tether.ImageTransparency = 0.65
		else
			tether.ImageTransparency = 1
		end
	else
		tether.ImageTransparency = 1
	end
end

-- ─── threat direction: the rim nearest incoming fire flares red ────────────────────────
local function threat(source: Vector3)
	if state ~= "Closed" then
		return
	end
	local cam = Workspace.CurrentCamera
	local d = cam.CFrame:PointToObjectSpace(source)
	local dir = V2(d.X, -d.Z)
	if dir.Magnitude < 1e-3 then
		return
	end
	dir = V2(dir.Unit.X, -dir.Unit.Y) -- screen space: x right, y down (ahead = up)
	Bus.Emit("Damage", dir)
	for _, q in threatQ do
		local k = q.Dir:Dot(dir)
		if k > 0.2 then
			q.Image.ImageTransparency = 1 - math.clamp(k, 0, 1) * 0.95
			tween(q.Image, 0.9, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
end
-- ─── honeycomb reactions (one bus, every event lights the shell its own way) ───────────────────
local HC_WHITE = C(220, 248, 255)
local HC_GREEN = C(90, 255, 190)
Bus.On("Boot", function()
	-- light pours out of the brow and over the whole shell, then a lap round the frame
	hc:Boot(V2(960, 0))
	task.delay(0.55, function()
		hc:Perimeter({ From = -90, Speed = 330, Width = 18, Color = HC_GREEN, Strength = 0.6, Life = 1.1 })
		hc:Perimeter({ From = -90, Speed = -330, Width = 18, Color = HC_GREEN, Strength = 0.6, Life = 1.1 })
	end)
end)
Bus.On("Shutdown", function()
	hc:Shutdown(V2(960, 0))
end)
Bus.On("Damage", function(dir: Vector2)
	local a = math.deg(math.atan2(dir.Y, dir.X))
	hc:Directional({ Angle = a, Spread = 5, Color = RED, Strength = 1.25, Life = 0.9 })
	hc:Radial({ Origin = edgePoint(a), Speed = 900, Width = 70, Color = C(255, 120, 80), Strength = 0.8, Life = 0.7 })
end)
Bus.On("PulseScan", function()
	hc:Radial({ Origin = V2(960, 540), Speed = 1100, Width = 140, Color = HC_WHITE, Strength = 1.3, Life = 1.3 })
	task.delay(0.25, function()
		hc:Radial({ Origin = V2(960, 540), Speed = 1100, Width = 90, Color = CYAN, Strength = 0.8, Life = 1.3 })
	end)
	task.delay(0.6, function()
		hc:Perimeter({ From = 90, Speed = 520, Width = 16, Color = CYAN, Strength = 0.7, Life = 0.7 })
		hc:Perimeter({ From = 90, Speed = -520, Width = 16, Color = CYAN, Strength = 0.7, Life = 0.7 })
	end)
end)
Bus.On("Dash", function(shift: Vector2?)
	-- a fast lateral sweep: light streaks from one side of the shell to the other
	local side = if shift and shift.X > 0 then 0 else 180
	hc:Radial({ Origin = edgePoint(side), Speed = 4200, Width = 200, Color = HC_WHITE, Strength = 1.0, Life = 0.5 })
end)
Bus.On("Jump", function()
	-- a vertical pulse: rises from the chin up the cheeks to the brow
	hc:Radial({ Origin = V2(960, 1180), Speed = 1900, Width = 110, Color = HC_GREEN, Strength = 1.0, Life = 0.75 })
end)
Bus.On("Lock", function()
	hc:Radial({ Origin = V2(960, 540), Speed = 1600, Width = 60, Color = RED, Strength = 0.45, Life = 0.5 })
end)
Bus.On("AbilityReady", function()
	hc:Spark(HC_WHITE, 0.6)
end)
-- ambient life + combat state: the shell gets busier when you are fighting
local hcNext = { Spark = 0, Lap = os.clock() + 8 }
local function stepHoneycomb(now: number, dt: number)
	stepVeins(now, dt)
	local last = math.max(Bus.Last.Damage or -99, Bus.Last.Fire or -99, Bus.Last.Lock or -99)
	local goal = if now - last < 4 then 1 else 0
	hc.Params.Combat += (goal - hc.Params.Combat) * math.min(1, dt * (if goal > hc.Params.Combat then 4 else 0.6))
	if state ~= "Closed" then
		return
	end
	local combat = hc.Params.Combat
	if now >= hcNext.Spark then
		hcNext.Spark = now + (0.7 + math.random() * 1.6) * (1 - 0.6 * combat)
		hc:Spark(if math.random() < 0.5 then HC_GREEN else nil, 0.45 + 0.3 * combat)
	end
	if now >= hcNext.Lap then
		hcNext.Lap = now + 7 + math.random() * 8
		local from = math.random(0, 359)
		hc:Perimeter({ From = from, Speed = if math.random() < 0.5 then 180 else -180, Width = 16, Strength = 0.5, Life = 1.8 })
	end
end

local events = Vantage:WaitForChild("Remotes"):WaitForChild("WeaponEvent")
events.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Damaged" and typeof(a) == "Vector3" then
		threat(a)
	elseif kind == "ShieldHit" and a == player.Character and type(c) == "number" and c < 0.33 and state == "Closed" then
		-- critical shield: the visor frame stutters with every hit
		hc:Perimeter({ From = math.random(0, 359), Speed = 520, Width = 18, Color = AMBER, Strength = 0.75, Life = 0.5 })
	end
end)

-- ─── abilities ───────────────────────────────────────────────────────────────────────────
local function pulseWave()
	if state ~= "Closed" then
		return
	end
	local vp = Workspace.CurrentCamera.ViewportSize
	local big = math.max(vp.X, vp.Y) * 1.6
	for i, w in waves do
		task.delay((i - 1) * 0.14, function()
			w.Visible = true
			w.Size = O(20, 20)
			w.ImageTransparency = if i == 1 then 0.05 else 0.5
			tween(w, 0.95, { Size = O(big, big) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			tween(w, 0.95, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(1, function()
				w.Visible = false
			end)
		end)
	end
	Bus.Emit("PulseScan")
	status.Text = "PULSE SCAN  //  SWEEP"
	status.TextTransparency = 0
	tween(status, 0.5, { TextTransparency = 1 }, nil, nil, 1.0)
	rimPulse(1, 0.8, 0.7)
	rimPulse(2, 0.8, 0.7)
end
local dashUntil, dashShift = 0, Vector2.zero
local function phaseDash()
	if state ~= "Closed" then
		return
	end
	dashUntil = os.clock() + 0.42
	task.delay(0.03, function()
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local v = Workspace.CurrentCamera.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
			local hv = Vector2.new(v.X, -v.Z)
			if hv.Magnitude > 1 then
				dashShift = Vector2.new(-hv.Unit.X * 16, hv.Unit.Y * 10)
			end
		end
		Bus.Emit("Dash", dashShift)
	end)
	for q = 1, 4 do
		rimPulse(q, 0.45, 0.9)
	end
end
local function drawStreaks(now: number)
	local left = dashUntil - now
	if left <= 0 then
		if streaks[1].Image.ImageTransparency < 1 then
			for _, s in streaks do
				s.Image.ImageTransparency = 1
			end
		end
		return
	end
	local a = 1 - left / 0.42
	local vp = Workspace.CurrentCamera.ViewportSize
	for i, s in streaks do
		local jitter = ((i * 37) % 11) / 11
		local r = 0.36 + 0.2 * a + jitter * 0.05
		s.Image.Position = O(vp.X / 2 + math.cos(s.A) * vp.X * r, vp.Y / 2 + math.sin(s.A) * vp.Y * r)
		s.Image.Rotation = math.deg(s.A)
		s.Image.Size = O((90 + 160 * a) * K, 14 * K)
		s.Image.ImageTransparency = 0.1 + 0.9 * a
	end
end
player:GetAttributeChangedSignal("VantageAbilityUsed"):Connect(function()
	local v = tostring(player:GetAttribute("VantageAbilityUsed"))
	local name = v:match("^(%a+)@")
	if name and nodes[name] then
		readyAt[name] = os.clock() + nodes[name].Cooldown
		nodes[name].Ready = false
		if state == "Closed" then
			nodes[name].Activate()
			holo:AbilityUsed(name)
		end
	end
	if v:find("^PhaseDash") then
		phaseDash()
	elseif v:find("^PulseScan") then
		pulseWave()
	elseif v:find("^HighJump") and state == "Closed" then
		Bus.Emit("Jump")
	end
end)
-- ready -> activating (0.12 s, the per-ability animation) -> active (ActiveTime) -> cooldown -> ready
local function stepAbilities(now: number)
	for name, n in nodes do
		local left = readyAt[name] - now
		local since = now - n.At
		if n.State == "Activating" and since > 0.12 then
			n.State = "Active"
		end
		if n.State == "Active" then
			-- live: tile lit, accent breathing, until the effect ends
			n.Accent.BackgroundTransparency = 0.2 * (0.5 + 0.5 * math.sin(now * 30))
			if since > 0.12 + n.ActiveTime then
				n.State = "Cooldown"
				n.Sweep.Visible = false
				n.Rise.Visible = false
				n.Tab.Color(BACK)
				n.Tab.Alpha(0.3)
				tween(n.Icon, 0.25, { ImageColor3 = SECOND, ImageTransparency = 0.7 })
			end
		elseif left > 0 and n.State ~= "Activating" then
			if n.State == "Ready" then -- used while the visor was open: straight to cooldown
				n.State = "Cooldown"
				n.Tab.Color(BACK)
				n.Icon.ImageColor3 = SECOND
				n.Icon.ImageTransparency = 0.7
			end
			local q = 1 - left / n.Cooldown
			n.Fill.Size = UDim2.fromScale(1, q)
			n.Prog.Size = O((TILE_W - 10) * q, 2)
			n.Prog.BackgroundColor3 = SECOND
			n.Num.Text = if left < 1 then string.format("%.1f", left) else tostring(math.ceil(left))
			n.Accent.BackgroundTransparency = 1
			n.Key.TextColor3 = SECOND
		elseif left <= 0 and n.State == "Cooldown" then
			-- charged: the tile lights from the bottom edge up, the icon returns
			n.State = "Ready"
			n.Ready = true
			n.Fill.Size = UDim2.fromScale(1, 0)
			n.Prog.Size = O(0, 2)
			n.Num.Text = ""
			n.Tab.Color(BACK)
			n.Tab.Alpha(0.3)
			n.Icon.ImageTransparency = 0
			n.Icon.ImageColor3 = WHITE
			tween(n.Icon, 0.5, { ImageColor3 = PRIMARY })
			n.Key.TextColor3 = PRIMARY
			tween(n.Key, 0.8, { TextColor3 = SECOND })
			n.Rise.Visible = true
			n.Rise.Position = O(0, TILE_H + 12)
			tween(n.Rise, 0.3, { Position = O(0, -12) })
			task.delay(0.32, function()
				if n.State == "Ready" then
					n.Rise.Visible = false
				end
			end)
			n.Flash()
			if state == "Closed" then
				play("Beeps", 0.08, 2)
				Bus.Emit("AbilityReady", name)
			end
		end
	end
end
player.CharacterAdded:Connect(function()
	for name in readyAt do
		readyAt[name] = 0
	end
end)

-- ─── telemetry ─────────────────────────────────────────────────────────────────────────
local function stepGauge(g, frac: number, now: number, dt: number, col: Color3)
	-- the bar eases to the value; a lighter chip shows what was just lost, then drains after it
	g.Shown += (frac - g.Shown) * math.min(1, dt * 14)
	if frac < g.Chipped - 0.002 and now - g.ChipAt > 0.5 then
		g.ChipAt = now
	end
	if frac > g.Chipped or now - g.ChipAt > 0.45 then
		g.Chipped += (frac - g.Chipped) * math.min(1, dt * 5)
	end
	g.Fill.Size = UDim2.fromScale(math.clamp(g.Shown, 0, 1), 1)
	g.Chip.Size = UDim2.fromScale(math.clamp(g.Chipped, 0, 1), 1)
	g.Fill.BackgroundColor3 = col
	g.Num.Text = tostring(math.floor(frac * 100 + 0.5))
	g.Num.TextColor3 = if col == PRIMARY or col == ACTIVE then PRIMARY else col
end
-- ─── shield down: the visor HUD glitches out ────────────────────────────────────────────────
-- With the shield at 0 (and the server not yet recharging it) the suit sheds power from the visor:
-- every holo panel except the suit panel (shield / health / OFFLINE) stutters, jumps and drops out,
-- with the odd ghost frame flickering through while you stay exposed (VisorHolo:SetEjected). The
-- moment ShieldRecharging goes true the panels reboot, staggered, with a cyan sweep over the glass.
-- The reticle is not a holo panel and always stays.
local function stepEject(want: boolean, alive: boolean)
	if want == (holo.Ejected == true) then
		return
	end
	if want then
		holo:SetEjected(true)
		hc:Radial({ Origin = V2(960, 540), Speed = 1800, Width = 70, Color = AMBER, Strength = 0.5, Life = 0.5 })
		play("PowerOff", 0.16, 1.35)
	else
		local reboot = state == "Closed" and alive
		holo:SetEjected(false, reboot)
		if reboot then
			hc:Radial({ Origin = V2(960, 0), Speed = 1500, Width = 90, Color = ACTIVE, Strength = 0.6, Life = 0.7 })
			play("Beeps", 0.14, 1.25)
		end
	end
end

local lastShield, shieldWasDown, shieldLowSent = 1, false, false
local wpnState = { Id = nil, Mag = nil, Reload = nil, ReadyUntil = 0 }
local nextRange = 0
local function stepTelemetry(now: number, dt: number)
	local ch = player.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	if h then
		local sh, msh = ch:GetAttribute("Shield") or 0, ch:GetAttribute("MaxShield") or 0
		local sf = if msh > 0 then math.clamp(sh / msh, 0, 1) else 0
		local hf = math.clamp(h.Health / math.max(1, h.MaxHealth), 0, 1)
		local hit = sf < lastShield - 0.001
		lastShield = sf
		local scol = if hit then PRIMARY elseif sf < 0.3 then AMBER else ACTIVE
		stepGauge(shieldG, sf, now, dt, scol)
		stepGauge(healthG, hf, now, dt, if hf < 0.35 then RED else PRIMARY)
		local down = msh > 0 and sh <= 0
		if down and not shieldWasDown and state == "Closed" then
			Bus.Emit("ShieldBreak")
		end
		shieldWasDown = down
		local alive = h.Health > 0
		stepEject(down and alive and state == "Closed" and ch:GetAttribute("ShieldRecharging") ~= true, alive)
		if sf < 0.3 and not down and not shieldLowSent and state == "Closed" then
			shieldLowSent = true
			Bus.Emit("ShieldLow")
		elseif sf >= 0.3 then
			shieldLowSent = false
		end
		shieldWarn.TextTransparency = if down then 0.1 + 0.45 * (0.5 + 0.5 * math.sin(now * 7)) else 1
		-- suit telemetry: ground speed and altitude (studs -> metres at the game's 0.28 scale)
		local root = ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local v = root.AssemblyLinearVelocity
			suitL.Text = string.format("SPD  %04.1f M/S", Vector3.new(v.X, 0, v.Z).Magnitude * 0.28)
			suitR.Text = string.format("ALT  %03d M", math.floor(root.Position.Y * 0.28 + 0.5))
		end
	end
	-- rangefinder: distance to whatever the crosshair is on (10 Hz)
	if now >= nextRange then
		nextRange = now + 0.1
		local cam = Workspace.CurrentCamera
		rayParams.FilterDescendantsInstances = filterList()
		local res = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, rayParams)
		rangeTxt.Text = if res then string.format("RNG  %03d M", math.floor(res.Distance * 0.28 + 0.5)) else "RNG  ---"
	end
	-- weapon
	local w = Feed.Weapon
	if w then
		local id = w.Id or w.DisplayName
		if id ~= wpnState.Id then
			-- weapon switch: the panel drops out and slides back in with the new name typed on
			local first = wpnState.Id == nil
			wpnState.Id, wpnState.Mag = id, nil
			weaponName.Text = string.upper(w.DisplayName or w.Id or "")
			if not first and state == "Closed" then
				Bus.Emit("WeaponSwitch", id)
				wpn.Position = O(0, 18)
				tween(wpn, 0.28, { Position = O(0, 0) }, Enum.EasingStyle.Quint)
				weaponName.MaxVisibleGraphemes = 0
				local n = utf8.len(weaponName.Text) or 0
				for k = 1, n do
					task.delay(0.02 * k, function()
						weaponName.MaxVisibleGraphemes = k
					end)
				end
				task.delay(0.02 * n + 0.05, function()
					weaponName.MaxVisibleGraphemes = -1
				end)
				magFlash.BackgroundTransparency = 0.2
				tween(magFlash, 0.35, { BackgroundTransparency = 1 })
			end
		end
		if w.Kind == "Melee" then
			magNum.Text = "MELEE"
			magNum.TextSize = 40
			reserveNum.Text = ""
			fireMode.Text = ""
			magTrack.Visible = false
			ammoState.Text = ""
		elseif Feed.Heat then
			local heat = Feed.Heat
			local col = if Feed.Locked then RED elseif heat > 0.75 then AMBER else ACTIVE
			magTrack.Visible = true
			magFill.Size = UDim2.fromScale(heat, 1)
			magFill.BackgroundColor3 = col
			magNum.TextSize = 64
			magNum.Text = tostring(math.floor(heat * 100 + 0.5))
			magNum.TextColor3 = if Feed.Locked then RED elseif heat > 0.75 then AMBER else PRIMARY
			reserveNum.Text = "%"
			fireMode.Text = "ENERGY"
			ammoState.Text = if Feed.Locked then "VENTING" elseif heat > 0.75 then "HEAT HIGH" else ""
			ammoState.TextColor3 = if Feed.Locked then RED else AMBER
		else
			magTrack.Visible = true
			local size = Feed.Size or 0
			local mag = Feed.Mag or 0
			local low = size > 0 and mag <= math.floor(size * 0.25)
			if wpnState.Mag and mag < wpnState.Mag and not Feed.Reload then
				-- a shot: the count kicks, the line ticks down with a flash
				magKick.Scale = 1.1
				tween(magKick, 0.14, { Scale = 1 }, Enum.EasingStyle.Quad)
				magFlash.BackgroundTransparency = 0.5
				tween(magFlash, 0.12, { BackgroundTransparency = 1 })
				Bus.Emit("Fire")
			end
			-- reload: the line becomes a progress bar; done = a white confirm flash and READY
			if Feed.Reload and not wpnState.Reload then
				Bus.Emit("Reload", "Start")
			elseif not Feed.Reload and wpnState.Reload then
				Bus.Emit("Reload", "Done")
				wpnState.ReadyUntil = now + 0.7
				magFlash.BackgroundTransparency = 0
				tween(magFlash, 0.45, { BackgroundTransparency = 1 })
				magKick.Scale = 1.14
				tween(magKick, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			wpnState.Reload = Feed.Reload
			wpnState.Mag = mag
			local col = if mag == 0 then RED elseif low then AMBER else ACTIVE
			if Feed.Reload then
				magFill.Size = UDim2.fromScale(math.clamp(Feed.Reload, 0, 1), 1)
				magFill.BackgroundColor3 = PRIMARY
				ammoState.Text = "RELOADING"
				ammoState.TextColor3 = PRIMARY
				ammoState.TextTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(now * 10))
			else
				magFill.Size = UDim2.fromScale(if size > 0 then mag / size else 0, 1)
				magFill.BackgroundColor3 = col
				if now < wpnState.ReadyUntil then
					ammoState.Text = "READY"
					ammoState.TextColor3 = ACTIVE
					ammoState.TextTransparency = 0
				elseif mag == 0 then
					ammoState.Text = "EMPTY  //  RELOAD"
					ammoState.TextColor3 = RED
					ammoState.TextTransparency = 0.1 + 0.4 * (0.5 + 0.5 * math.sin(now * 8))
				elseif low then
					ammoState.Text = "LOW AMMO"
					ammoState.TextColor3 = AMBER
					ammoState.TextTransparency = 0.1 + 0.4 * (0.5 + 0.5 * math.sin(now * 6))
				else
					ammoState.Text = ""
				end
			end
			magNum.TextSize = 64
			magNum.Text = tostring(mag)
			magNum.TextColor3 = if mag == 0 then RED elseif low then AMBER else PRIMARY
			reserveNum.Text = "/ " .. tostring(Feed.Reserve or 0)
			local trig = w.Trigger
			fireMode.Text = if type(trig) == "string" then string.upper(trig) else (if w.Burst then "BURST" else "")
		end
	end
	-- match
	if Feed.Timer then
		clock.Text = Feed.Timer
	end
	local match = Vantage:FindFirstChild("Match")
	local bs, rs = 0, 0
	if match then
		bs, rs = match:GetAttribute("BlueScore") or 0, match:GetAttribute("RedScore") or 0
	end
	blueNum.Text = string.format("%02d", bs)
	redNum.Text = string.format("%02d", rs)
end

-- ─── compass + radar ──────────────────────────────────────────────────────────────────
local compassYaw = nil
local function stepCompass(look: Vector3, dt: number)
	local yaw = math.deg(math.atan2(look.X, -look.Z)) % 360
	compassYaw = compassYaw or yaw
	local d = (yaw - compassYaw + 540) % 360 - 180
	compassYaw = (compassYaw + d * math.min(1, dt * 16)) % 360
	local shown = compassYaw
	heading.Text = string.format("%03d", math.floor(yaw + 0.5) % 360)
	headingCard.Text = CARD[(math.floor((yaw + 22.5) / 45) % 8) * 45]
	local half = tape.Size.X.Offset / 2 -- (the tape opens out from the centre at boot)
	for _, t in ticks do
		local dd = (t.Deg - shown + 540) % 360 - 180
		local px = half + dd * PX_DEG
		local vis = px > -20 and px < half * 2 + 20
		t.Frame.Visible = vis
		if t.Label then
			t.Label.Visible = vis
		end
		if vis then
			t.Frame.Position = O(px, 16)
			if t.Label then
				t.Label.Position = O(px, 19)
			end
		end
	end
	-- markers from the radar's dots (a dot's offset from the disc centre is its bearing relative to you)
	local used = 0
	for _, dot in radarDots do
		if dot.Visible and used < #markers then
			local x, y = dot.Position.X.Offset, dot.Position.Y.Offset
			if x * x + y * y > 4 then
				used += 1
				local rel = math.deg(math.atan2(x, -y))
				local m = markers[used]
				local edge = math.abs(rel) * PX_DEG > half - 30
				local px = half + math.clamp(rel * PX_DEG, -(half - 30), half - 30)
				m.Position = O(px, 5)
				m.BackgroundColor3 = dot.BackgroundColor3
				m.BackgroundTransparency = if edge then 0.5 else 0
				m.Visible = true
			end
		end
	end
	for i = used + 1, #markers do
		markers[i].Visible = false
	end
end
local sweepAngle = 0
local function stepRadar(dt: number)
	if not rsweep then
		return
	end
	radarBoost = math.max(0, radarBoost - dt / 1.4)
	sweepAngle = (sweepAngle + dt * radarSweepRate * (1 + 5 * radarBoost)) % 360
	rsweep.Rotation = sweepAngle
	rsweep.ImageTransparency = 0.55 - 0.4 * radarBoost
end
Bus.On("PulseScan", function()
	radarBoost = 1
	if rpulse then
		local st = rpulse:FindFirstChildOfClass("UIStroke")
		for i = 0, 1 do
			task.delay(i * 0.25, function()
				rpulse.Size = UDim2.fromScale(0.05, 0.05)
				st.Transparency = 0
				tween(rpulse, 0.9, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Quad)
				tween(st, 0.9, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		end
	end
end)
Bus.On("ShieldBreak", function()
	hc:Radial({ Origin = V2(960, 0), Speed = 1600, Width = 120, Color = AMBER, Strength = 1.0, Life = 0.9 })
	status.Text = "SHIELD COLLAPSED"
	status.TextColor3 = AMBER
	status.TextTransparency = 0
	tween(status, 0.5, { TextTransparency = 1 }, nil, nil, 1.0)
	task.delay(1.6, function()
		status.TextColor3 = ACTIVE
	end)
end)
Bus.On("ShieldLow", function()
	hc:Perimeter({ From = -90, Speed = 400, Width = 16, Color = AMBER, Strength = 0.6, Life = 0.8 })
	hc:Perimeter({ From = -90, Speed = -400, Width = 16, Color = AMBER, Strength = 0.6, Life = 0.8 })
end)
Bus.On("Reload", function(phase)
	if phase == "Done" then
		hc:Radial({ Origin = V2(1920, 1080), Speed = 1400, Width = 80, Color = ACTIVE, Strength = 0.5, Life = 0.6 })
	end
end)
Bus.On("WeaponSwitch", function()
	hc:Radial({ Origin = V2(1920, 1080), Speed = 2200, Width = 100, Strength = 0.5, Life = 0.5 })
end)

-- ─── per frame ───────────────────────────────────────────────────────────────────────────
-- shield down: red alarm flash (see stepDownFlash below the eject code)
local DOWN_PERIOD = 0.71 -- seconds per flash (half the 1.42 s alarm clip)
local downGui = new("ScreenGui", { Name = "VantageShieldDownFlash", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, Enabled = false }, playerGui)
local downEdges = {}
for _, e in {
	{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.32), 90 }, -- top: opaque at the edge, clear inward
	{ UDim2.fromScale(0, 0.68), UDim2.fromScale(1, 0.32), -90 }, -- bottom
	{ UDim2.fromScale(0, 0), UDim2.fromScale(0.26, 1), 0 }, -- left
	{ UDim2.fromScale(0.74, 0), UDim2.fromScale(0.26, 1), 180 }, -- right
} do
	local f = new("Frame", { Position = e[1], Size = e[2], BackgroundColor3 = RED, BackgroundTransparency = 1, BorderSizePixel = 0 }, downGui)
	new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.75), NumberSequenceKeypoint.new(1, 1) }) }, f)
	table.insert(downEdges, f)
end
-- While Shield = 0, alive and not yet recharging (same condition as the looping shield-down alarm in
-- ShieldFX): the screen edges pulse red twice per alarm cycle and a red light chases round the visor
-- glass on every pulse. The centre stays clear. Fades out when the recharge starts or you die.
local downOn, downLevel, downStart, downLastPeak = false, 0, 0, -1
local function stepDownFlash(now: number, dt: number, live: boolean)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local want = live and hum ~= nil and hum.Health > 0 and (ch:GetAttribute("MaxShield") or 0) > 0
		and (ch:GetAttribute("Shield") or 0) <= 0 and ch:GetAttribute("ShieldRecharging") ~= true
	if want and not downOn then
		downStart, downLastPeak = now, -1
	end
	downOn = want
	if not want and downLevel <= 0 then
		if downGui.Enabled then
			downGui.Enabled = false
		end
		return
	end
	downLevel = if want then 1 else math.max(0, downLevel - dt * 6)
	local t = (now - downStart) / DOWN_PERIOD
	local pulse = (0.5 + 0.5 * math.cos(t * math.pi * 2)) ^ 2 -- sharp peak at the start of each cycle
	local tr = 1 - (0.12 + 0.6 * pulse) * downLevel
	downGui.Enabled = true
	for _, f in downEdges do
		f.BackgroundTransparency = tr
	end
	local peak = math.floor(t)
	if want and peak ~= downLastPeak then
		downLastPeak = peak
		if state == "Closed" then
			hc:Perimeter({ From = -90, Speed = 520, Width = 18, Color = RED, Strength = 0.75, Life = DOWN_PERIOD })
			hc:Perimeter({ From = -90, Speed = -520, Width = 18, Color = RED, Strength = 0.75, Life = DOWN_PERIOD })
		end
	end
end

local lastYaw = 0
RunService:BindToRenderStep("VantageVisor", Enum.RenderPriority.Camera.Value + 5, function(dt)
	local now = os.clock()
	local live = deployed()
	if live ~= deployedShown then
		deployedShown = live
		if live then
			if state == "Open" or state == "Opening" then
				snapOpen()
			else
				snapClosed()
			end
		else
			local wasClosed = state == "Closed" or state == "Closing"
			token += 1
			seq = nil
			state = if wasClosed then "Closed" else "Open"
			shutter.Enabled = false
			resetShutter()
			setBlackout(false)
			setHands(0, 0)
			applyGlass(false, true)
			setHudVisible(false)
			holo:SetShown(false, true)
			stopHum()
		end
	end
	stepSequence()
	stepDownFlash(now, dt, live)
	if not live then
		return
	end
	local cam = Workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	-- the visor reticle sits on the HUD crosshair
	if cross then
		-- AbsolutePosition is measured below the topbar inset; this gui ignores the inset
		local c = cross.AbsolutePosition + cross.AbsoluteSize / 2
		local inset = if hudGui.IgnoreGuiInset then game:GetService("GuiService"):GetGuiInset() else Vector2.zero
		holders.Reticle.Frame.Position = O(c.X + inset.X, c.Y + inset.Y)
	else
		holders.Reticle.Frame.Position = UDim2.fromScale(0.5, 0.5)
	end
	-- ADS (2026-11-14): the visor ring steps aside so the weapon's own sight is the only aiming
	-- reference (Feed.ADS is written every frame by WeaponController:PostCamera)
	local adsNow = Feed.ADS or 0
	if adsNow > 0.35 then
		if holders.Reticle.Frame.Visible then
			holders.Reticle.Frame.Visible = false
			adsHidReticle = true
		end
	elseif adsHidReticle then
		adsHidReticle = false
		holders.Reticle.Frame.Visible = true
	end
	if group.Visible then
		stepCompass(look, dt)
		stepTelemetry(now, dt)
		stepAbilities(now)
		stepRadar(dt)
	end
	-- reflection drifts against camera turns (+ an occasional slow sweep)
	local yawNow = math.atan2(look.X, -look.Z)
	local dyaw = (yawNow - lastYaw + math.pi) % (math.pi * 2) - math.pi
	lastYaw = yawNow
	if glass.Enabled then
		refl.X += -dyaw * 0.06
		refl.X += (refl.Base - refl.X) * math.min(1, dt * 1.5)
		local off = 0
		if refl.Sweep > 0 then
			refl.Sweep = math.max(0, refl.Sweep - dt / 1.6)
			off = (1 - refl.Sweep) * 1.1 - 0.75
		end
		reflection.Position = UDim2.fromScale(refl.X + off, 0.35)
		reflection.BackgroundTransparency = if refl.Sweep > 0 then 0.95 - 0.03 * math.sin(refl.Sweep * math.pi) else 0.955
	end
	-- the interface lags Phase Dash acceleration, then settles
	dashShift = dashShift:Lerp(Vector2.zero, math.min(1, dt * 6))
	group.Position = O(dashShift.X, dashShift.Y)
	drawStreaks(now)
	stepTracker(now, dt)
	stepHoneycomb(now, dt)
	holo:Step(dt)
	ambient(now)
end)

player.CharacterAdded:Connect(function()
	deployedShown = false
	TR.Target, TR.Mode = nil, "Search"
end)
