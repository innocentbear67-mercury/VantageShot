--[[
	VANTAGE — Hud (client)  ·  combat HUD v5 "HS Match" (2026-11-17)
	Reconstruction of Hypershot's in-match HUD (user rule: ~90% Hypershot, 10% VantageShot where
	the game needs it). Geometry measured from the user's reference capture, in 1920x1080 design px.

	  top-centre     glossy blue score box · dark timer box · red score box, "First to N" / mode
	                 labels at the sides, player avatar row (#rank, ring = team, kills) under it
	  top-right      kill feed (VantageKillFeed), FPS | ping tiny in the corner
	  right edge     key hints (Settings / Inventory / Inspect / Swap), weapon slot list (silhouette
	                 + key square, active one bright), Scoreboard [Tab] + Quick Melee [V] at the bottom
	  left edge      vertical killstreak meter + "Killstreak xN"
	  bottom-left    shield pill (cyan) over the long glossy health pill, numbers at the end
	  bottom-centre  glossy ability tiles (lobby tile skin) with the key on the bottom edge, dark
	                 cooldown shutter + seconds; ammo "MAG | RESERVE" to their right
	  centre         crosshair + hit marker only. Medals sit above (EliminationFX), REQ ticks right.

	Public API unchanged (Loadout, WeaponController, KnifeController, DeathPresenter, DeathReplay,
	EliminationFX, MatchHud, HudOptics, HitFeedback, VantageReqFeed). Fields others read: Gui, Root,
	Feedback, Kick, ScoreFrame, Dot (parent = crosshair), MagLabel, ReserveLabel, Prompt, Pips +
	_buildPips, Timer, Weapon, TimerStart, SuppressKillBanner. Root.Ammo / Vitals / Score by name.
	Ability cooldowns: GrappleFeed.ReadyAt / ChargeTimes, GrenadeFeed.ReadyAt (published per frame
	by VantageAbilityClient / GrenadeClient). Killstreak: own kills since the last death (KillFeed).
	Previous: ServerStorage._HudBackup_20261117.Hud (v3) and .HudV4
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Vantage.Weapons.WeaponConfig)
local H = Config.Hud
local HitFeedback = require(script.Parent:WaitForChild("HitFeedback"))

local AbilityConfig, GrappleFeed, GrenadeFeed, GrenadeConfig, EquipCatalog, KillFeedRemote, UltRemote, UltConfig
pcall(function()
	UltConfig = require(ReplicatedStorage.Vantage:WaitForChild("Ult", 10):WaitForChild("UltConfig", 10))
	UltRemote = ReplicatedStorage.Vantage.Remotes:WaitForChild("Ult", 10)
end)
pcall(function()
	AbilityConfig = require(ReplicatedStorage.Vantage.Abilities.AbilityConfig)
	GrappleFeed = require(ReplicatedStorage.Vantage.Abilities.GrappleFeed)
end)
pcall(function()
	GrenadeConfig = require(ReplicatedStorage.Vantage.Grenade.GrenadeConfig)
	GrenadeFeed = require(ReplicatedStorage.Vantage.Grenade.GrenadeFeed)
end)
pcall(function()
	EquipCatalog = require(ReplicatedStorage.Vantage.Equipment.EquipmentCatalog)
end)
local SignatureFeed, SignatureConfig, SignatureCatalog -- 2026-11-20: Signature tile (SignatureClient)
pcall(function()
	SignatureFeed = require(ReplicatedStorage.Vantage.Signatures.SignatureFeed)
	SignatureConfig = require(ReplicatedStorage.Vantage.Signatures.SignatureConfig)
	SignatureCatalog = require(ReplicatedStorage.Vantage.Signatures.SignatureCatalog)
end)
pcall(function()
	KillFeedRemote = ReplicatedStorage.Vantage.Remotes:WaitForChild("KillFeed", 10)
end)

local C = Color3.fromRGB
local V2 = Vector2.new
local O = UDim2.fromOffset

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local INK = C(12, 16, 34)
local WHITE = C(255, 255, 255)
local GREY = C(196, 204, 218)
local CYAN = C(70, 225, 255)
local CYAN_HI = C(190, 248, 255)
local BLUE_T, BLUE_B, BLUE_EDGE = C(108, 186, 255), C(34, 104, 238), C(10, 30, 92)
local RED_T, RED_B, RED_EDGE = C(255, 108, 128), C(222, 36, 70), C(88, 8, 26)
local GREEN_T, GREEN_B = C(140, 245, 96), C(56, 190, 44)
local RED = C(255, 66, 88)
local AMBER = C(255, 184, 52)
local GOLD = C(255, 204, 58)
local TILE_IMG = "rbxassetid://83303798085879" -- HS lobby tile (blue), measured from Hypershot
local TILE_INK = C(16, 40, 72)

-- killstreak meter v2 (2026-11-18): 10 reactor cells; overloads (chromatic, shaking, sparking) when a ULT is banked
local KS_TW, KS_TH, KS_TY, KS_CX = 56, 530, 54, 110
local KS_CELLS = 10
local NUMFONT = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Heavy)
local CELL_DIM, CELL_EDGE = C(26, 34, 56), C(64, 82, 120)
local GOLD_SEQ = ColorSequence.new(C(255, 244, 170), C(255, 158, 24))
local function rainbow(t: number, spread: number, sat: number?): ColorSequence
	local kp = {}
	for k = 0, 6 do
		kp[#kp + 1] = ColorSequenceKeypoint.new(k / 6, Color3.fromHSV((t + k / 6 * spread) % 1, sat or 0.7, 1))
	end
	return ColorSequence.new(kp)
end

local CROSS = { Len = 10, Thick = 2, Gap = 6, Dot = 2 } -- Hypershot proportions at 1080p (2026-11-17)
local MODE_NAMES = { TDM = "Team Deathmatch", RTDM = "Ranked Deathmatch", CTF = "Capture the Flag", DUEL = "Duel", TAC = "Tactical", FFA = "Free for All" }

local Hud = {}
Hud.__index = Hud

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

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- UIStroke thickness does not follow UIScale: every stroke is registered and rescaled in _fit
local STROKES = setmetatable({}, { __mode = "k" })
local function stroke(o: Instance, th: number, col: Color3?, tr: number?)
	local s = new("UIStroke", { Thickness = th, Color = col or INK, Transparency = tr or 0, LineJoinMode = Enum.LineJoinMode.Round }, o)
	if not o:IsA("TextLabel") then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	STROKES[s] = th
	return s
end

local function text(parent: Instance, p)
	local t = new("TextLabel", {
		Name = p.Name or "Label",
		BackgroundTransparency = 1,
		Text = p.Text or "",
		FontFace = FONT,
		TextSize = p.TextSize or 24,
		TextColor3 = p.Color or WHITE,
		TextTransparency = p.Transparency or 0,
		TextXAlignment = p.X or Enum.TextXAlignment.Center,
		TextYAlignment = p.Y or Enum.TextYAlignment.Center,
		AnchorPoint = p.AnchorPoint or V2(0, 0),
		Position = p.Position or O(0, 0),
		Size = p.Size or UDim2.fromScale(1, 1),
		AutomaticSize = p.AutoSize or Enum.AutomaticSize.None,
		ZIndex = p.ZIndex or 3,
		Visible = p.Visible ~= false,
		LayoutOrder = p.Order or 0,
		RichText = p.Rich or false,
	}, parent)
	if p.Stroke ~= 0 then
		stroke(t, p.Stroke or math.max(1.5, (p.TextSize or 24) * 0.11), p.StrokeColor or INK, p.StrokeT)
	end
	return t
end

-- slanted shape: body + 1px columns in a CanvasGroup (one gradient / transparency for all of it)
local function para(parent: Instance, p)
	local w, h, sk = p.W, p.H, p.Skew or 0
	local g = new("CanvasGroup", {
		Name = p.Name or "Para",
		AnchorPoint = p.AnchorPoint or V2(0, 0),
		Position = p.Position or O(0, 0),
		Size = O(w, h),
		BackgroundTransparency = 1,
		GroupTransparency = p.GroupTransparency or 0,
		ZIndex = p.ZIndex or 1,
	}, parent)
	local col = p.Color or WHITE
	local function piece(x, y, pw, ph)
		new("Frame", { Position = O(x, y), Size = O(pw, ph), BackgroundColor3 = col, BorderSizePixel = 0 }, g)
	end
	local ld, rd = p.LeftDir or 0, p.RightDir or 0
	local x0 = if ld ~= 0 then sk else 0
	local x1 = if rd ~= 0 then w - sk else w
	piece(x0, 0, x1 - x0, h)
	for i = 0, sk - 1 do
		local f = (i + 0.5) / sk
		if ld ~= 0 then
			local hh = math.max(1, math.floor(h * f + 0.5))
			if ld == 1 then piece(i, h - hh, 1, hh) else piece(i, 0, 1, hh) end
		end
		if rd ~= 0 then
			local hh = math.max(1, math.floor(h * (1 - f) + 0.5))
			if rd == 1 then piece(w - sk + i, 0, 1, hh) else piece(w - sk + i, h - hh, 1, hh) end
		end
	end
	return g
end

-- Hypershot score box: dark edge, glossy vertical gradient face, top gloss, bright bottom line
local function box(parent: Instance, p)
	local w, h, sk, b = p.W, p.H, p.Skew or 0, p.Border or 3
	local holder = new("Frame", { Name = p.Name or "Box", AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position or O(0, 0), Size = O(w, h), BackgroundTransparency = 1, ZIndex = p.ZIndex or 2 }, parent)
	local z = p.ZIndex or 2
	para(holder, { W = w, H = h, Skew = sk, LeftDir = p.LeftDir, RightDir = p.RightDir, Color = C(0, 0, 0), Position = O(0, 4), GroupTransparency = 0.55, ZIndex = z })
	para(holder, { W = w, H = h, Skew = sk, LeftDir = p.LeftDir, RightDir = p.RightDir, Color = p.Edge, ZIndex = z })
	local ih = h - 2 * b
	local isk = math.max(0, math.floor(sk * ih / h + 0.5))
	local face = para(holder, { W = w - 2 * b, H = ih, Skew = isk, LeftDir = p.LeftDir, RightDir = p.RightDir, Color = WHITE, Position = O(b, b), ZIndex = z + 1 })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(0.55, p.Mid or p.Bottom), ColorSequenceKeypoint.new(1, p.Bottom) }) }, face)
	local gloss = new("Frame", { Size = UDim2.new(1, 0, 0.42, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, BorderSizePixel = 0 }, face)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1) }, gloss)
	for k = 0, 1 do
		new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.22 + k * 0.1, 0, 0.5, 0), Size = O(6 - k * 3, h * 2), Rotation = 28, BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0 }, face)
	end
	new("Frame", { AnchorPoint = V2(0, 1), Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = p.Line or WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, face)
	return holder, face
end

-- rounded glossy pill bar (health / shield): edge + track + clipped fill + gloss + trail
local function pill(parent: Instance, p)
	local w, h = p.W, p.H
	local holder = new("Frame", { Name = p.Name or "Pill", Position = p.Position, Size = O(w, h), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, holder)
	stroke(holder, 2.5, INK)
	local trackIn = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = C(34, 40, 60), BorderSizePixel = 0, ZIndex = 2 }, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, trackIn)
	local function layer(z: number)
		local clip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z }, trackIn)
		local f = new("Frame", { Size = O(w - 4, h - 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = z }, clip)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		return clip, f
	end
	local trailClip, trail = layer(3)
	trail.BackgroundColor3 = p.Trail or C(255, 120, 120)
	local clip, fill = layer(4)
	local grad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(p.Top, p.Bottom) }, fill)
	local gloss = new("Frame", { Position = UDim2.new(0, 6, 0, 2), Size = UDim2.new(1, -12, 0.36, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 5 }, fill)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, gloss)
	return { Holder = holder, Clip = clip, Fill = fill, Grad = grad, Trail = trailClip, W = w - 4, H = h - 4 }
end

local function keySquare(parent: Instance, label: string, p)
	local w = math.max(p.Size or 34, 18 + #label * 11)
	local k = new("Frame", { Name = "Key", AnchorPoint = p.AnchorPoint or V2(0, 0.5), Position = p.Position or O(0, 0), Size = O(w, p.Size or 34), BackgroundColor3 = C(24, 26, 36), BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = p.Order or 0, ZIndex = 3 }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 7) }, k)
	stroke(k, 1.5, C(70, 76, 96))
	local t = text(k, { Text = label, TextSize = p.TextSize or 18, Stroke = 0, ZIndex = 4 })
	return k, t
end

local function silhouette(vp: ViewportFrame, weapon, fill: number?)
	vp:ClearAllChildren()
	local asset = weapon and weapon.Asset and ReplicatedStorage.Vantage.Weapons.Assets:FindFirstChild(weapon.Asset)
	if not asset then
		return
	end
	local m = asset:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Transparency >= 0.95 then
				d:Destroy()
				continue
			end
			d.Color = WHITE
			d.Material = Enum.Material.SmoothPlastic
			d.Transparency = 0
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	if m:IsA("Model") then
		m:PivotTo(CFrame.new())
	end
	m.Parent = vp
	local cf, size
	if m:IsA("Model") then
		cf, size = m:GetBoundingBox()
	else
		cf, size = (m :: BasePart).CFrame, (m :: BasePart).Size
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 20
	local abs = vp.AbsoluteSize
	local aspect = if abs.Y > 1 then math.max(1, abs.X / abs.Y) else 3
	local t = math.tan(math.rad(10))
	local long = math.max(size.Z, size.X)
	local dist = math.max((long / 2) / (aspect * t), (size.Y / 2) / t) * (fill or 1.06) + math.min(size.X, size.Z) / 2
	cam.CFrame = CFrame.lookAt(cf.Position + cf.RightVector * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

local function bindLabel(name: string): string
	local map = { One = "1", Two = "2", Three = "3", MouseButton1 = "LMB", MouseButton2 = "RMB", LeftControl = "CTRL", LeftShift = "SHIFT" }
	return map[name] or name
end

function Hud.new()
	local self = setmetatable({}, Hud)
	local player = Players.LocalPlayer
	local gui = new("ScreenGui", { Name = "VantageHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	self.Gui = gui
	local root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	self.Root = root
	self.Scales = {}

	local vig = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 }, gui)
	self.VignetteEdges, self.BreakEdges = {}, {}
	for _, e in {
		{ UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.18, 0), 90 },
		{ UDim2.new(0, 0, 0.82, 0), UDim2.new(1, 0, 0.18, 0), -90 },
		{ UDim2.fromScale(0, 0), UDim2.new(0.14, 0, 1, 0), 0 },
		{ UDim2.new(0.86, 0, 0, 0), UDim2.new(0.14, 0, 1, 0), 180 },
	} do
		local f = new("Frame", { Position = e[1], Size = e[2], BackgroundColor3 = C(200, 16, 36), BackgroundTransparency = 1, BorderSizePixel = 0 }, vig)
		new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new(0, 1) }, f)
		table.insert(self.VignetteEdges, f)
		local b = new("Frame", { Position = e[1], Size = e[2], BackgroundColor3 = CYAN, BackgroundTransparency = 1, BorderSizePixel = 0 }, vig)
		new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, 0.7), NumberSequenceKeypoint.new(1, 1) }) }, b)
		table.insert(self.BreakEdges, b)
	end
	self.Glitch = {}
	for i = 1, 7 do
		local band = new("Frame", { Position = UDim2.fromScale(0, i / 8), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = CYAN_HI, BackgroundTransparency = 1, BorderSizePixel = 0 }, vig)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.18, 1), NumberSequenceKeypoint.new(0.82, 1), NumberSequenceKeypoint.new(1, 0.2) }) }, band)
		table.insert(self.Glitch, band)
	end
	self.Flash, self.BreakFx = 0, 0
	self.Impact = { 0, 0, 0, 0 }

	local cross = new("Frame", { Name = "Crosshair", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(0, 0), BackgroundTransparency = 1, ZIndex = 10 }, gui)
	self.Cross = cross
	self.Lines = {}
	for _, n in { "Up", "Down", "Left", "Right" } do
		local vert = n == "Up" or n == "Down"
		local l = new("Frame", {
			Name = n,
			AnchorPoint = ({ Up = V2(0.5, 1), Down = V2(0.5, 0), Left = V2(1, 0.5), Right = V2(0, 0.5) })[n],
			Size = if vert then O(CROSS.Thick, CROSS.Len) else O(CROSS.Len, CROSS.Thick),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, cross)
		new("UIStroke", { Color = C(0, 0, 0), Thickness = 1, Transparency = 0.5 }, l)
		self.Lines[n] = l
	end
	self.Dot = new("Frame", { Name = "Dot", AnchorPoint = V2(0.5, 0.5), Size = O(CROSS.Dot, CROSS.Dot), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 11 }, cross)
	new("UIStroke", { Color = C(0, 0, 0), Thickness = 1, Transparency = 0.55 }, self.Dot)
	self.KnifeRing = new("Frame", { Name = "KnifeRing", AnchorPoint = V2(0.5, 0.5), Size = O(16, 16), BackgroundTransparency = 1, Visible = false, ZIndex = 11 }, cross)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.KnifeRing)
	new("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.25 }, self.KnifeRing)

	self.Feedback = HitFeedback.new(self, gui)

	self.Arcs = {}
	for i = 1, 6 do
		local holder = new("Frame", { Name = "DamageArc" .. i, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(330, 330), BackgroundTransparency = 1, Visible = false, ZIndex = 3 }, gui)
		local segs = {}
		for k = -2, 2 do
			local ang = math.rad(k * 8)
			local s = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, math.sin(ang) * 165, 0.5, -math.cos(ang) * 165), Size = O(25, if k == 0 then 6 else 5 - math.abs(k) * 0.5), Rotation = math.deg(ang), BackgroundColor3 = RED, BorderSizePixel = 0 }, holder)
			table.insert(segs, s)
		end
		local glow = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -152), Size = O(120, 26), BackgroundColor3 = RED, BorderSizePixel = 0 }, holder)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.55) }) }, glow)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
		table.insert(self.Arcs, { Holder = holder, Segs = segs, Glow = glow, Scale = new("UIScale", {}, holder), Until = 0, Source = Vector3.zero })
	end

	local banner = new("Frame", { Name = "KillBanner", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.66, 0), Size = O(420, 60), BackgroundTransparency = 1, Visible = false }, root)
	self.Banner = banner
	self.BannerTag = text(banner, { Size = UDim2.new(1, 0, 0, 22), Text = "Eliminated!", Color = RED, TextSize = 22 })
	self.BannerName = text(banner, { Position = O(0, 24), Size = UDim2.new(1, 0, 0, 32), Text = "", TextSize = 30 })

	-- SCORE
	local top = new("Frame", { Name = "Score", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = O(1000, 210), BackgroundTransparency = 1 }, root)
	self.ScoreFrame = top
	local BH = 66
	box(top, { Name = "TimerBox", W = 236, H = BH, Skew = 6, LeftDir = -1, RightDir = 1, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Edge = C(46, 62, 108), Top = C(40, 50, 86), Mid = C(22, 28, 54), Bottom = C(14, 18, 38), Line = C(110, 140, 220), ZIndex = 4 })
	self.Timer = text(top, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(220, BH), Text = "10:00", TextSize = 40, Stroke = 3.5, ZIndex = 8 })
	self.TimerScale = new("UIScale", {}, self.Timer)
	local function side(sgn: number, team: string)
		local blue = team == "Blue"
		local w = 206
		local cx = sgn * (118 + w / 2 - 6)
		box(top, {
			Name = team .. "Box", W = w, H = BH, Skew = 8,
			LeftDir = if sgn < 0 then 1 else 0, RightDir = if sgn > 0 then -1 else 0,
			AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, cx, 0, 0),
			Edge = if blue then BLUE_EDGE else RED_EDGE, Top = if blue then BLUE_T else RED_T, Mid = if blue then C(60, 140, 255) else C(246, 70, 96), Bottom = if blue then BLUE_B else RED_B,
			ZIndex = 2,
		})
		local num = text(top, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, cx, 0, 0), Size = O(w, BH), Text = "0", TextSize = 40, Stroke = 3.5, ZIndex = 8 })
		local sc = new("UIScale", {}, num)
		-- 2026-11-18: glowing underline on the leading team's box
		local bar = new("Frame", { Name = team .. "Lead", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, cx, 0, BH + 4), Size = O(w - 44, 5), BackgroundColor3 = if blue then C(150, 215, 255) else C(255, 150, 165), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, top)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
		local barGlow = new("UIStroke", { Color = if blue then C(60, 150, 255) else C(255, 60, 90), Thickness = 3, Transparency = 1 }, bar)
		return { Num = num, Scale = sc, Last = -1, Bar = bar, BarGlow = barGlow, Lead = 0 }
	end
	self.SideBlue = side(-1, "Blue")
	self.SideRed = side(1, "Red")
	self.BlueScore, self.RedScore = self.SideBlue.Num, self.SideRed.Num
	self.TargetLabel = text(top, { AnchorPoint = V2(1, 0.5), Position = UDim2.new(0.5, -350, 0, BH / 2), Size = O(220, 34), Text = "First to 50!", TextSize = 28, X = Enum.TextXAlignment.Right, Transparency = 0.3, Stroke = 3, StrokeT = 0.35 })
	self.ModeLabel = text(top, { AnchorPoint = V2(0, 0.5), Position = UDim2.new(0.5, 350, 0, BH / 2), Size = O(260, 34), Text = "", TextSize = 28, X = Enum.TextXAlignment.Left, Transparency = 0.3, Stroke = 3, StrokeT = 0.35 })
	local prow = new("Frame", { Name = "Players", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, BH + 22), Size = O(870, 110), BackgroundTransparency = 1 }, top)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }, prow)
	self.PlayerRow = prow
	self.Avatars = {}
	for i = 1, 10 do
		local cell = new("Frame", { Name = "P" .. i, LayoutOrder = i, Size = O(64, 110), BackgroundTransparency = 1, Visible = false }, prow)
		local ring = new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = O(60, 60), BackgroundColor3 = C(235, 240, 250), BorderSizePixel = 0, ZIndex = 2 }, cell)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		local rs = stroke(ring, 3.5, BLUE_B)
		local img = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ZIndex = 3 }, ring)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
		local initial = text(ring, { Text = "", TextSize = 26, Color = C(60, 70, 100), Stroke = 0, ZIndex = 3 })
		local rank = text(cell, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(64, 22), Text = "#" .. i, TextSize = 21, Stroke = 2.8, ZIndex = 5 })
		local kills = text(cell, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = O(64, 24), Text = "0", TextSize = 22, Stroke = 2.8, ZIndex = 5 })
		self.Avatars[i] = { Cell = cell, Ring = ring, RingStroke = rs, Img = img, Initial = initial, Rank = rank, Kills = kills, UserId = nil }
	end
	self.ThumbCache = {}
	self.RowNext = 0

	local perf = new("Frame", { Name = "Perf", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -16, 0, 6), Size = O(220, 20), BackgroundTransparency = 1 }, root)
	self.PerfLabel = text(perf, { Text = "", TextSize = 15, X = Enum.TextXAlignment.Right, Transparency = 0.45, Stroke = 1.5, StrokeT = 0.5 })
	self.PerfFrames, self.PerfSince = 0, os.clock()

	self.RadarFrame = new("Frame", { Name = "Radar", Visible = false, Size = O(0, 0), BackgroundTransparency = 1 }, root)
	self.ZoneLabel = text(self.RadarFrame, { Text = "", Size = O(0, 0), Stroke = 0 })
	self.Feed = new("Frame", { Name = "LegacyFeed", Visible = false, Size = O(0, 0), BackgroundTransparency = 1 }, root)
	self.FeedItems, self.FeedOrder = {}, 0

	-- RIGHT EDGE
	local hints = new("Frame", { Name = "Hints", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -18, 0, 330), Size = O(320, 220), BackgroundTransparency = 1 }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, hints)
	self.HintsFrame = hints
	self.HintRows = {}
	local function hintRow(parent: Instance, order: number, title: string, bindKey: string?, fallback: string)
		local r = new("Frame", { Name = title, LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 40), BackgroundTransparency = 1 }, parent)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, r)
		text(r, { Order = 1, Text = title, TextSize = 28, Size = O(0, 40), AutoSize = Enum.AutomaticSize.X, Stroke = 3.2 })
		local _, kt = keySquare(r, fallback, { Order = 2, Size = 34, TextSize = 18 })
		table.insert(self.HintRows, { Bind = bindKey, Fallback = fallback, Label = kt })
		return r
	end
	hintRow(hints, 1, "Settings", "Bind_Settings", "P")
	hintRow(hints, 2, "Inventory", "Bind_Inventory", "B")
	hintRow(hints, 3, "Inspect", "Bind_Inspect", "F")
	hintRow(hints, 4, "Swap", "Bind_Swap", "Q")
	local bottomHints = new("Frame", { Name = "BottomHints", AnchorPoint = V2(1, 1), Position = UDim2.new(1, -18, 1, -12), Size = O(600, 40), BackgroundTransparency = 1 }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 34), SortOrder = Enum.SortOrder.LayoutOrder }, bottomHints)
	self.BottomHints = bottomHints
	hintRow(bottomHints, 1, "Scoreboard", nil, "Tab")
	hintRow(bottomHints, 2, "Quick Melee", "Bind_Knife", "V")

	local rail = new("Frame", { Name = "SlotRail", AnchorPoint = V2(1, 1), Position = UDim2.new(1, -18, 1, -66), Size = O(250, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, rail)
	self.Rail = rail
	self.Slots = {}
	local order = Config.LoadoutOrder or Config.Loadout
	for i, id in order do
		local w = Config.Weapons[id]
		if w then
			local r = new("Frame", { Name = id, LayoutOrder = i, Size = O(250, 50), BackgroundTransparency = 1 }, rail)
			local vp = new("ViewportFrame", { AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = O(170, 48), BackgroundTransparency = 1, Ambient = WHITE, LightColor = WHITE, LightDirection = Vector3.new(0, -1, -0.2), ImageColor3 = WHITE }, r)
			local k, kt = keySquare(r, tostring(i), { AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = 36, TextSize = 19 })
			table.insert(self.Slots, { Id = id, Row = r, View = vp, Key = k, KeyText = kt, Built = false })
		end
	end
	self.Highlight = new("Frame", { Visible = false, Size = O(0, 0) }, rail)
	self.Hotbar = rail
	self.RailShownAt = -10

	-- LEFT EDGE: killstreak v2 (2026-11-18) — segmented reactor meter (one cell per kill, 10 = ULT).
	-- Banked ULT (Player.UltReady): the meter overloads — chromatic cells, RGB-split ghosts, glow,
	-- shaking, electric arcs, sparks, building to a burst every ~1.4 s — and ACTIVATE ULT appears.
	local ks = new("Frame", { Name = "Killstreak", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0, 214, 0, 196), Size = O(220, 730), BackgroundTransparency = 1 }, root)
	self.StreakFrame = ks
	local core = new("Frame", { Name = "Core", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, ks)
	self.StreakCore = core
	self.StreakCoreScale = new("UIScale", {}, core)
	-- emblem: three chevrons
	local em = new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(40, 44), BackgroundTransparency = 1 }, core)
	self.StreakChevrons = {}
	for k = 0, 2 do
		local c = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 12 + k * 11), Size = O(22, 22), Rotation = 45, BackgroundTransparency = 1 }, em)
		local cs = stroke(c, 4, GOLD)
		cs.Transparency = k * 0.25
		new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.49, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }) }, c)
		table.insert(self.StreakChevrons, cs)
	end
	-- RGB-split ghosts of the frame (offset left / right while overloaded)
	self.StreakGhosts = {}
	for i, col in { C(255, 40, 96), C(40, 232, 255) } do
		local g = new("Frame", { Name = "Ghost", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0, KS_CX, 0, KS_TY), Size = O(KS_TW, KS_TH), BackgroundTransparency = 1, ZIndex = 1 }, core)
		new("UICorner", { CornerRadius = UDim.new(0, 10) }, g)
		table.insert(self.StreakGhosts, { F = g, S = stroke(g, 3, col, 1), Dir = if i == 1 then -1 else 1 })
	end
	-- outer glow ring
	local glow = new("Frame", { Name = "Glow", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, KS_CX, 0, KS_TY + KS_TH / 2), Size = O(KS_TW + 14, KS_TH + 14), BackgroundTransparency = 1, ZIndex = 1 }, core)
	new("UICorner", { CornerRadius = UDim.new(0, 16) }, glow)
	self.StreakGlowFrame = glow
	self.StreakGlow = stroke(glow, 7, WHITE, 1)
	self.StreakGlowGrad = new("UIGradient", { Rotation = 90 }, self.StreakGlow)
	-- glass track
	local track = new("Frame", { Name = "Track", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0, KS_CX, 0, KS_TY), Size = O(KS_TW, KS_TH), BackgroundColor3 = C(8, 12, 26), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 2 }, core)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, track)
	new("UIGradient", { Color = ColorSequence.new(C(150, 170, 210), C(60, 70, 100)) }, track)
	self.StreakTrack = track
	self.StreakTrackStroke = stroke(track, 2.5, CELL_EDGE, 0.05)
	self.StreakTrackGrad = new("UIGradient", { Rotation = 90, Enabled = false }, self.StreakTrackStroke)
	-- corner brackets
	self.StreakBrackets = {}
	local bx, by, arm, th = KS_TW / 2 + 8, KS_TH / 2 + 8, 16, 3
	for _, cnr in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local cx, cy = KS_CX + cnr[1] * bx, KS_TY + KS_TH / 2 + cnr[2] * by
		local h = new("Frame", { AnchorPoint = V2(if cnr[1] < 0 then 0 else 1, 0.5), Position = O(cx, cy), Size = O(arm, th), BackgroundColor3 = CYAN, BorderSizePixel = 0, ZIndex = 3 }, core)
		local v = new("Frame", { AnchorPoint = V2(0.5, if cnr[2] < 0 then 0 else 1), Position = O(cx, cy), Size = O(th, arm), BackgroundColor3 = CYAN, BorderSizePixel = 0, ZIndex = 3 }, core)
		table.insert(self.StreakBrackets, h)
		table.insert(self.StreakBrackets, v)
	end
	-- cells (1 = bottom) + side ticks
	local pad, gap = 7, 5
	local ch = (KS_TH - pad * 2 - gap * (KS_CELLS - 1)) / KS_CELLS
	self.StreakCells = {}
	for i = 1, KS_CELLS do
		local y = KS_TH - pad - i * ch - (i - 1) * gap
		local cell = new("Frame", { Name = "Cell" .. i, Position = O(pad, y), Size = O(KS_TW - pad * 2, ch), BackgroundColor3 = CELL_DIM, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, track)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, cell)
		local cst = stroke(cell, 1.5, CELL_EDGE, 0.3)
		local lit = new("Frame", { Name = "Lit", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, cell)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, lit)
		local lg = new("UIGradient", { Rotation = 90, Color = GOLD_SEQ }, lit)
		-- top bevel highlight
		new("Frame", { Name = "Bevel", Position = O(3, 2), Size = UDim2.new(1, -6, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 5 }, lit)
		local hot = new("Frame", { Name = "Hot", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6 }, cell)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, hot)
		local tick = new("Frame", { AnchorPoint = V2(1, 0.5), Position = O(KS_CX - KS_TW / 2 - 4, KS_TY + y + ch / 2), Size = O(if i % 5 == 0 then 12 else 6, 2), BackgroundColor3 = CELL_EDGE, BorderSizePixel = 0, ZIndex = 3 }, core)
		table.insert(self.StreakCells, { Cell = cell, Lit = lit, Grad = lg, Hot = hot, Stroke = cst, Tick = tick })
	end
	local ultTag = text(core, { AnchorPoint = V2(0, 0.5), Position = O(KS_CX + KS_TW / 2 + 6, KS_TY + pad + ch / 2), Size = O(40, 18), Text = "ULT", TextSize = 15, Color = CYAN, Stroke = 2, X = Enum.TextXAlignment.Left })
	ultTag.Visible = UltConfig ~= nil and UltConfig.Enabled == true -- 2026-11-20: ULT removed
	ultTag.FontFace = NUMFONT
	self.StreakUltTag = ultTag
	-- electric arcs (5 segments each) and spark pool
	self.StreakArcs = {}
	for _ = 1, 3 do
		local arc = {}
		for _ = 1, 5 do
			table.insert(arc, new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(4, 2), BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 7 }, core))
		end
		table.insert(self.StreakArcs, arc)
	end
	self.Sparks, self.SparkNext = {}, 1
	for _ = 1, 32 do
		table.insert(self.Sparks, { F = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(11, 2.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 8 }, core), X = 0, Y = 0, VX = 0, VY = 0, Age = 0, Life = 1 })
	end
	-- readout
	self.StreakCaption = text(core, { AnchorPoint = V2(0.5, 0), Position = O(KS_CX, KS_TY + KS_TH + 10), Size = O(220, 18), Text = "KILLSTREAK", TextSize = 16, Color = GREY, Stroke = 2 })
	self.StreakCaption.FontFace = NUMFONT
	self.StreakLabel = text(core, { AnchorPoint = V2(0.5, 0), Position = O(KS_CX, KS_TY + KS_TH + 26), Size = O(220, 40), Text = "x0", TextSize = 38, Color = GOLD, Stroke = 3, StrokeColor = C(60, 34, 0) })
	self.StreakLabel.FontFace = NUMFONT
	self.StreakLabelGrad = new("UIGradient", { Enabled = false }, self.StreakLabel)
	self.StreakScale = new("UIScale", {}, self.StreakLabel)
	-- ACTIVATE ULT button (key / gamepad in VantageUltClient; click or tap here)
	local btn = new("TextButton", { Name = "UltButton", AnchorPoint = V2(0.5, 0), Position = O(KS_CX, KS_TY + KS_TH + 76), Size = O(208, 54), BackgroundColor3 = C(10, 12, 24), BackgroundTransparency = 0.08, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 9, ClipsDescendants = true }, ks)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, btn)
	self.UltBtnStroke = stroke(btn, 3, WHITE)
	self.UltBtnGrad = new("UIGradient", {}, self.UltBtnStroke)
	self.UltBtnScale = new("UIScale", {}, btn)
	local shine = new("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 10 }, btn)
	self.UltShine = new("UIGradient", { Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }), Offset = V2(-1, 0) }, shine)
	local cap = new("Frame", { Name = "Key", AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = O(34, 34), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 11 }, btn)
	new("UICorner", { CornerRadius = UDim.new(0, 7) }, cap)
	self.UltKeyGrad = new("UIGradient", { Rotation = 45 }, cap)
	local keyLbl = text(cap, { Text = (UltConfig and UltConfig.KeyLabel) or "Z", TextSize = 22, Color = INK, Stroke = 0, ZIndex = 12 })
	keyLbl.FontFace = NUMFONT
	self.UltBtnLabel = text(btn, { AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 52, 0.5, 0), Size = UDim2.new(1, -58, 0, 30), Text = "ACTIVATE ULT", TextSize = 22, Color = WHITE, Stroke = 2.5, ZIndex = 11 })
	self.UltBtn = btn
	btn.Activated:Connect(function()
		if UltRemote and Players.LocalPlayer:GetAttribute("UltReady") == true then
			UltRemote:FireServer("Activate", Workspace.CurrentCamera.CFrame.LookVector)
		end
	end)
	self.Streak, self.StreakShown, self.StreakPopAt = 0, 0, -10
	self.UltReady, self.OverloadAt, self.UltUsedAt, self.BurstAt, self.OverPhase, self.ArcNext, self.SparkAcc = false, -10, -10, -10, 0, 0, 0

	-- VITALS
	local vit = new("Frame", { Name = "Vitals", AnchorPoint = V2(0, 1), Position = UDim2.new(0, 12, 1, -14), Size = O(480, 70), BackgroundTransparency = 1 }, root)
	self.HealthFrame = vit
	local shRow = new("Frame", { Name = "ShieldRow", Position = O(0, 0), Size = O(480, 26), BackgroundTransparency = 1 }, vit)
	self.ShieldRow = shRow
	self.ShieldBar = pill(shRow, { W = 300, H = 18, Position = O(0, 4), Top = C(200, 250, 255), Bottom = C(60, 200, 255), Trail = C(200, 245, 255) })
	self.ShieldNum = text(shRow, { AnchorPoint = V2(0, 0.5), Position = O(310, 13), Size = O(56, 26), Text = "100", TextSize = 24, Color = CYAN_HI, X = Enum.TextXAlignment.Left, Stroke = 2.8 })
	self.ShieldState = text(shRow, { AnchorPoint = V2(0, 0.5), Position = O(372, 13), Size = O(160, 26), Text = "", TextSize = 20, Color = AMBER, X = Enum.TextXAlignment.Left, Stroke = 2.5 })
	self.ShieldIcon = shRow
	local hpRow = new("Frame", { Name = "HealthRow", Position = O(0, 32), Size = O(480, 36), BackgroundTransparency = 1 }, vit)
	self.HealthBar = pill(hpRow, { W = 384, H = 26, Position = O(0, 5), Top = GREEN_T, Bottom = GREEN_B, Trail = C(255, 236, 190) })
	self.HealthLabel = text(hpRow, { Name = "HP", AnchorPoint = V2(0, 0.5), Position = O(394, 18), Size = O(90, 36), Text = "100", TextSize = 32, Color = GREY, X = Enum.TextXAlignment.Left, Stroke = 3 })
	self.HealthScale = new("UIScale", {}, self.HealthLabel)
	self.HealthIcon = hpRow

	-- ABILITIES + AMMO
	local ab = new("Frame", { Name = "Abilities", AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, -40, 1, -14), Size = O(384, 116), BackgroundTransparency = 1 }, root)
	self.AbilityFrame = ab
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 20), SortOrder = Enum.SortOrder.LayoutOrder }, ab)
	self.Tiles = {}
	local function tile(order: number, id: string, keyLabel: string, icon: string?)
		local holder = new("Frame", { Name = id, LayoutOrder = order, Size = O(112, 116), BackgroundTransparency = 1 }, ab)
		-- Hypershot ability tile: dark navy rim, bright diagonal blue face, halftone corner,
		-- two light streaks and a top gloss (CanvasGroup so the rounded corners clip everything)
		local face = new("Frame", { Name = "Face", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(110, 110), BackgroundColor3 = C(10, 26, 70), BorderSizePixel = 0, ZIndex = 2 }, holder)
		new("UICorner", { CornerRadius = UDim.new(0, 16) }, face)
		stroke(face, 3, C(6, 14, 40))
		local sc = new("UIScale", {}, face)
		local skin = new("CanvasGroup", { Name = "Skin", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, face)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, skin)
		new("UIGradient", { Rotation = 45, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C(150, 222, 255)), ColorSequenceKeypoint.new(0.45, C(74, 156, 255)), ColorSequenceKeypoint.new(1, C(34, 92, 228)) }) }, skin)
		for gx = 0, 5 do
			for gy = 0, 5 do
				if gx + gy >= 6 then
					local d = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(56 + gx * 9, 56 + gy * 9), Size = O(5, 5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55 + 0.05 * (10 - gx - gy), BorderSizePixel = 0 }, skin)
					new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
				end
			end
		end
		for k = 0, 1 do
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.34 + k * 0.16, 0, 0.5, 0), Size = O(10 - k * 5, 170), Rotation = 45, BackgroundColor3 = WHITE, BackgroundTransparency = 0.82 + k * 0.06, BorderSizePixel = 0 }, skin)
		end
		local gl = new("Frame", { Size = UDim2.new(1, 0, 0.42, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, skin)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.1, 1) }, gl)
		local rim = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, ZIndex = 3 }, face)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, rim)
		stroke(rim, 2, C(190, 236, 255), 0.35)
		local dim = new("Frame", { Name = "Dim", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = C(10, 18, 40), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, face)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, dim)
		local img = nil
		if icon and icon ~= "" then
			img = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = O(66, 66), BackgroundTransparency = 1, Image = icon, ImageColor3 = WHITE, ScaleType = Enum.ScaleType.Fit, ZIndex = 4 }, face)
		end
		local clip = new("Frame", { Name = "ShutClip", AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 5 }, face)
		local shut = new("Frame", { Name = "Shutter", AnchorPoint = V2(0, 0), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0), BackgroundColor3 = C(14, 22, 46), BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 5 }, clip)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, shut)
		local secs = text(face, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = O(110, 50), Text = "", TextSize = 40, Stroke = 3.5, StrokeColor = TILE_INK, ZIndex = 7 })
		local flash = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8 }, face)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, flash)
		local key = text(face, { Name = "Key", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -8), Size = O(110, 30), Text = keyLabel, TextSize = if #keyLabel > 2 then 20 else 30, Stroke = 3.5, StrokeColor = TILE_INK, ZIndex = 9 })
		local pips = new("Frame", { Name = "Charges", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = O(90, 6), BackgroundTransparency = 1, ZIndex = 9 }, face)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4) }, pips)
		local t = { Holder = holder, Face = face, Dim = dim, Scale = sc, Icon = img, Shutter = shut, Secs = secs, Flash = flash, Key = key, Pips = pips, PipList = {}, WasReady = true, FlashAt = -10 }
		self.Tiles[id] = t
		return t
	end
	local G = AbilityConfig and AbilityConfig.Abilities and AbilityConfig.Abilities.Grapple
	local GR = AbilityConfig and AbilityConfig.Abilities and AbilityConfig.Abilities.Grenade
	local grapple = tile(1, "Grapple", G and G.KeyLabel or "E", G and G.Icon)
	local frag = tile(2, "Grenade", GR and GR.KeyLabel or "G", nil)
	do
		local g = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0), Size = O(42, 52), BackgroundTransparency = 1, ZIndex = 4 }, frag.Face)
		local body = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = O(34, 38), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, g)
		new("UICorner", { CornerRadius = UDim.new(0.45, 0) }, body)
		stroke(body, 2.5, TILE_INK)
		for k = 0, 2 do
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 12 + k * 8), Size = O(34, 3), BackgroundColor3 = TILE_INK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 5 }, body)
		end
		local cap = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -37), Size = O(16, 8), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, g)
		stroke(cap, 2, TILE_INK)
		local lever = new("Frame", { AnchorPoint = V2(0, 0.5), Position = UDim2.new(0.5, 4, 0, 9), Size = O(18, 5), Rotation = 28, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, g)
		stroke(lever, 2, TILE_INK)
		local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, -10, 0, 7), Size = O(12, 12), BackgroundTransparency = 1, ZIndex = 4 }, g)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		new("UIStroke", { Color = WHITE, Thickness = 2.5 }, ring)
	end
	if SignatureFeed then
		-- 2026-11-20: Signature tile: the equipped Signature's card art fills the face; click / tap casts
		local st = tile(3, "Signature", SignatureConfig and SignatureConfig.KeyLabel or "SHIFT", nil)
		local skin = st.Face:FindFirstChild("Skin")
		st.Art = new("ImageLabel", { Name = "SigArt", BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, skin)
		local shade = new("Frame", { BackgroundColor3 = C(4, 6, 20), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, skin)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.72, 1), NumberSequenceKeypoint.new(1, 0.5) }) }, shade)
		local gloss = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.4, 0), ZIndex = 3 }, skin)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1) }, gloss)
		st.Shutter.BackgroundTransparency = 0.62 -- the art stays readable under the cooldown
		st.Rim = st.Face:FindFirstChildOfClass("UIStroke")
		-- chromatic charge-up (like the ULT meter): a spectrum fill rising from the bottom, a hot leading edge,
		-- a cycling rainbow rim and an outer glow that swells as it nears full and pulses when ready
		local clip = st.Face:FindFirstChild("ShutClip")
		st.Charge = new("Frame", { Name = "Charge", AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 5 }, clip)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, st.Charge)
		st.ChargeGrad = new("UIGradient", { Rotation = 90 }, st.Charge)
		st.ChargeEdge = new("Frame", { Name = "Edge", AnchorPoint = V2(0, 0.5), Position = UDim2.fromScale(0, 0), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6 }, st.Charge)
		st.EdgeGrad = new("UIGradient", {}, st.ChargeEdge)
		st.EdgeGlow = new("ImageLabel", { Name = "EdgeGlow", BackgroundTransparency = 1, Image = "rbxassetid://103142630740394", ImageColor3 = WHITE, ImageTransparency = 0.4, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1.3, 0, 0, 34), ZIndex = 6 }, st.Charge)
		if st.Rim then
			st.Rim.Color = WHITE
			st.RimGrad = new("UIGradient", {}, st.Rim)
		end
		st.Glow = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = "rbxassetid://103142630740394", ImageColor3 = WHITE, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 55), Size = O(190, 190), ZIndex = 1 }, st.Holder)
		st.Note = text(st.Holder, { Name = "Note", AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = O(220, 26), Text = "", TextSize = 20, Stroke = 3, StrokeColor = TILE_INK, ZIndex = 9 })
		st.Note.TextColor3 = C(255, 120, 110)
		local btn = new("TextButton", { Name = "Cast", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10 }, st.Face)
		btn.Activated:Connect(function()
			if SignatureFeed.Press then SignatureFeed.Press() end
		end)
	end
	if not grapple.Icon then
		local g = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = O(40, 40), BackgroundTransparency = 1, ZIndex = 4 }, grapple.Face)
		new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(5, 30), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, g)
		new("Frame", { AnchorPoint = V2(1, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = O(16, 5), Rotation = -40, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, g)
		new("Frame", { AnchorPoint = V2(0, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = O(16, 5), Rotation = 40, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, g)
	end

	local ammo = new("Frame", { Name = "Ammo", AnchorPoint = V2(0, 1), Position = UDim2.new(0.5, 104, 1, -40), Size = O(260, 60), BackgroundTransparency = 1 }, root)
	self.AmmoFrame = ammo
	local inner = new("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, ammo)
	self.AmmoInner = inner
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	self.MagLabel = text(inner, { Name = "Mag", Order = 1, Text = "30", TextSize = 40, Size = O(0, 50), AutoSize = Enum.AutomaticSize.X, Stroke = 3.5 })
	self.MagScale = new("UIScale", {}, self.MagLabel)
	self.Divider = text(inner, { Name = "Divider", Order = 2, Text = "|", TextSize = 38, Size = O(0, 50), AutoSize = Enum.AutomaticSize.X, Stroke = 3.5 })
	self.ReserveLabel = text(inner, { Name = "Reserve", Order = 3, Text = "90", TextSize = 40, Size = O(0, 50), AutoSize = Enum.AutomaticSize.X, Stroke = 3.5 })
	self.ReloadBar = new("Frame", { Name = "ReloadBar", Position = UDim2.new(0, 0, 1, 2), Size = O(150, 6), BackgroundColor3 = INK, BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false }, ammo)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.ReloadBar)
	self.ReloadFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, self.ReloadBar)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.ReloadFill)
	self.PipHolder = new("Frame", { Name = "Pips", Position = UDim2.new(0, 0, 1, 2), Size = O(150, 6), BackgroundTransparency = 1, Visible = false }, ammo)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }, self.PipHolder)
	self.Pips = {}
	self.SlotName = text(ammo, { Name = "WeaponName", Visible = false, Size = O(0, 0), Stroke = 0 })
	self.WeaponName = self.SlotName
	self.SkinLabel = text(ammo, { Name = "Skin", Visible = false, Size = O(0, 0), Stroke = 0 })
	self.WeaponClass = text(ammo, { Visible = false, Size = O(0, 0), Stroke = 0 })
	self.IconFrame = new("ViewportFrame", { Name = "WeaponIcon", Visible = false, Size = O(10, 10), BackgroundTransparency = 1 }, ammo)
	self.ReloadTag = text(ammo, { Visible = false, Size = O(0, 0), Stroke = 0 })

	self.Prompt = text(gui, { Name = "Prompt", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 120), Size = O(300, 30), Text = "", Color = AMBER, TextSize = 26, Stroke = 3 })

	local death = new("Frame", { Name = "Death", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 0), Size = O(520, 110), BackgroundTransparency = 1, Visible = false }, root)
	self.DeathCard = death
	self.DeathTitle = text(death, { Position = O(0, 0), Size = UDim2.new(1, 0, 0, 30), Text = "Eliminated by", Color = RED, TextSize = 28, Stroke = 3 })
	self.DeathName = text(death, { Position = O(0, 30), Size = UDim2.new(1, 0, 0, 46), Text = "", TextSize = 44, Stroke = 4 })
	self.DeathInfo = text(death, { Position = O(0, 78), Size = UDim2.new(1, 0, 0, 26), Text = "", Color = GREY, TextSize = 22, Stroke = 2.5 })
	self.Fader = new("Frame", { Name = "Fader", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(3, 5, 9), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50 }, gui)

	self.Numbers = {}
	self.NumberIndex = 0
	self.Spread, self.Kick, self.ADS = 0, 0, 0
	self.CrossVisible = true
	self.TimerStart = os.clock()
	self.HealthShown, self.TrailShown, self.LastHP, self.TrailHoldUntil = 100, 100, 100, 0
	self.ShieldShown, self.LastShield = 0, 0
	self.MagPunch, self.LastMag = 0, nil
	self.LastSecond = -1

	-- killstreak: server-owned now (Player.KillStreak / UltReady, set by EliminationService)

	self:_fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_fit()
	end)
	return self
end

-- ── killstreak meter v2 ──
function Hud:_spark(x: number, y: number, vx: number, vy: number, col: Color3)
	local s = self.Sparks[self.SparkNext]
	self.SparkNext = self.SparkNext % #self.Sparks + 1
	s.X, s.Y, s.VX, s.VY, s.Age, s.Life = x, y, vx, vy, 0, 0.3 + math.random() * 0.35
	s.F.BackgroundColor3 = col
	s.F.Visible = true
end

function Hud:_sparkEdge(power: number)
	local side = if math.random() < 0.5 then -1 else 1
	local x = KS_CX + side * (KS_TW / 2 + 2)
	local y = KS_TY + math.random() * KS_TH
	local sp = (110 + math.random() * 220) * power
	local a = math.rad(math.random(-70, 50))
	self:_spark(x, y, side * math.cos(a) * sp, math.sin(a) * sp, Color3.fromHSV(math.random(), 0.45, 1))
end

function Hud:_sparkBurst(n: number, power: number?)
	for _ = 1, n do
		self:_sparkEdge(power or 1.4)
	end
end

function Hud:_stepStreak(dt: number, now: number, humanoid: Humanoid?)
	local lp = Players.LocalPlayer
	local ks = tonumber(lp:GetAttribute("KillStreak")) or 0
	local ready = lp:GetAttribute("UltReady") == true
	if ks > self.Streak then
		self.StreakPopAt = now
	end
	self.Streak = ks
	if ready ~= self.UltReady then
		self.UltReady = ready
		if ready then
			self.OverloadAt = now
			self:_sparkBurst(18, 1.8)
		else
			self.UltUsedAt = now
			self:_sparkBurst(26, 2.2)
		end
	end
	local per = (UltConfig and UltConfig.StreakPerCharge) or KS_CELLS
	local goal = if ready then 1 else (ks % per) / per
	self.StreakShown += (goal - self.StreakShown) * expAlpha(10, dt)
	local shown = self.StreakShown * KS_CELLS
	local sp = now - self.StreakPopAt
	local pop = if sp < 0.3 then (1 - sp / 0.3) ^ 2 else 0
	local used = math.clamp(1 - (now - self.UltUsedAt) / 0.5, 0, 1)

	-- overload: intensity builds over each ~1.4 s cycle, then bursts
	local over = if ready then math.clamp((now - self.OverloadAt) / 0.35, 0, 1) else 0
	local phase = (now * 0.72) % 1
	if ready and phase < self.OverPhase then
		self.BurstAt = now
		self:_sparkBurst(9, 1.5)
	end
	self.OverPhase = phase
	local build = over * (0.3 + 0.7 * phase ^ 2)
	local burst = over * math.clamp(1 - (now - self.BurstAt) / 0.22, 0, 1)
	local hue = now * 0.55

	for i, c in self.StreakCells do
		local b = math.clamp(shown - (i - 1), 0, 1)
		c.Lit.BackgroundTransparency = 1 - b
		local newest = not ready and i == ks % per and pop > 0
		if ready then
			local h = hue - i * 0.075
			c.Grad.Color = rainbow(h, 0.35, 0.75)
			c.Stroke.Color = Color3.fromHSV(h % 1, 0.55, 1)
			c.Stroke.Transparency = 0
			local flick = if math.random() < 0.02 + 0.08 * build then 0.85 else 0
			c.Hot.BackgroundTransparency = 1 - math.max(flick, burst * 0.75, used)
			c.Tick.BackgroundColor3 = Color3.fromHSV(h % 1, 0.5, 1)
		else
			c.Grad.Color = GOLD_SEQ
			c.Stroke.Color = if b > 0.5 then GOLD else CELL_EDGE
			c.Stroke.Transparency = if b > 0.5 then 0 else 0.3
			c.Hot.BackgroundTransparency = 1 - math.max(if newest then pop else 0, used * 0.8)
			c.Tick.BackgroundColor3 = if b > 0.5 then GOLD else CELL_EDGE
		end
	end

	-- frame, glow, ghosts
	self.StreakTrackGrad.Enabled = ready
	if ready then
		self.StreakTrackStroke.Color = WHITE
		self.StreakTrackGrad.Color = rainbow(hue, 1)
		self.StreakTrackGrad.Rotation = (now * 120) % 360
		self.StreakGlowGrad.Color = rainbow(hue + 0.3, 1)
		self.StreakGlowGrad.Rotation = (-now * 90) % 360
	else
		self.StreakTrackStroke.Color = CELL_EDGE
	end
	local gl = math.max(over * (0.3 + 0.45 * build + 0.25 * burst), used)
	self.StreakGlow.Transparency = 1 - gl
	self.StreakGlowFrame.Size = O(KS_TW + 14 + 12 * build + 16 * burst, KS_TH + 14 + 12 * build + 16 * burst)
	self.StreakTrack.BackgroundColor3 = C(8, 12, 26):Lerp(C(120, 120, 170), burst * 0.5 + used * 0.6)
	for _, g in self.StreakGhosts do
		g.S.Transparency = 1 - over * (0.35 + 0.4 * build)
		local off = g.Dir * (2 + 5 * build + 6 * burst) + (math.random() * 2 - 1) * 1.5 * over
		g.F.Position = UDim2.new(0, KS_CX + off, 0, KS_TY + (math.random() * 2 - 1) * 1.5 * over)
	end
	for k, br in self.StreakBrackets do
		br.BackgroundColor3 = if ready then Color3.fromHSV((hue + k * 0.12) % 1, 0.55, 1) else CYAN
	end
	for k, cs in self.StreakChevrons do
		cs.Color = if ready then Color3.fromHSV((hue + k * 0.2) % 1, 0.6, 1) else GOLD
	end
	self.StreakUltTag.TextColor3 = if ready then Color3.fromHSV((hue + 0.5) % 1, 0.4, 1) else CYAN

	-- shake + swell
	local amp = over * (0.8 + 3 * build + 4.5 * burst) + pop * 2.5 + used * 5
	self.StreakCore.Position = O((math.random() * 2 - 1) * amp, (math.random() * 2 - 1) * amp)
	self.StreakCoreScale.Scale = 1 + 0.022 * build + 0.045 * burst + 0.02 * pop

	-- electric arcs
	if ready then
		self.ArcsShown = true
		if now >= self.ArcNext then
			self.ArcNext = now + 0.045 + math.random() * 0.05
			for _, arc in self.StreakArcs do
				local on = math.random() < 0.25 + 0.6 * build
				local x0 = KS_CX + (math.random() * 2 - 1) * KS_TW * 0.75
				local y0 = KS_TY + math.random() * KS_TH
				local a = math.random() * math.pi * 2
				local len = 40 + math.random() * 80
				local x1, y1 = x0 + math.cos(a) * len, y0 + math.sin(a) * len
				local px, py = x0, y0
				local col = Color3.fromHSV(math.random(), 0.3, 1)
				for k, seg in arc do
					local t = k / #arc
					local j = if k < #arc then 11 else 0
					local nx = x0 + (x1 - x0) * t + (math.random() * 2 - 1) * j
					local ny = y0 + (y1 - y0) * t + (math.random() * 2 - 1) * j
					local dx, dy = nx - px, ny - py
					seg.Visible = on
					seg.Position = O((px + nx) / 2, (py + ny) / 2)
					seg.Size = O(math.sqrt(dx * dx + dy * dy) + 1, 2)
					seg.Rotation = math.deg(math.atan2(dy, dx))
					seg.BackgroundColor3 = col
					px, py = nx, ny
				end
			end
		end
		-- a steady crackle of sparks, faster as it builds
		self.SparkAcc += dt * (5 + 28 * build)
		while self.SparkAcc >= 1 do
			self.SparkAcc -= 1
			self:_sparkEdge(0.8 + build)
		end
	elseif self.ArcsShown then
		self.ArcsShown = false
		for _, arc in self.StreakArcs do
			for _, seg in arc do
				seg.Visible = false
			end
		end
	end
	for _, s in self.Sparks do
		if s.F.Visible then
			s.Age += dt
			if s.Age >= s.Life then
				s.F.Visible = false
			else
				s.VY += 520 * dt
				s.X += s.VX * dt
				s.Y += s.VY * dt
				s.F.Position = O(s.X, s.Y)
				s.F.Rotation = math.deg(math.atan2(s.VY, s.VX))
				s.F.BackgroundTransparency = (s.Age / s.Life) ^ 2
			end
		end
	end

	-- readout
	if ready then
		self.StreakCaption.Text = "OVERLOAD"
		self.StreakCaption.TextColor3 = if math.sin(now * 18) > 0 then RED else WHITE
		self.StreakLabel.Text = "ULT READY"
		self.StreakLabel.TextSize = 30
		self.StreakLabel.TextColor3 = WHITE
		self.StreakLabelGrad.Enabled = true
		self.StreakLabelGrad.Color = rainbow(hue, 0.8)
	else
		self.StreakCaption.Text = "KILLSTREAK"
		self.StreakCaption.TextColor3 = GREY
		self.StreakLabel.Text = "x" .. ks
		self.StreakLabel.TextSize = 38
		self.StreakLabel.TextColor3 = GOLD
		self.StreakLabelGrad.Enabled = false
	end
	self.StreakScale.Scale = 1 + 0.3 * pop + 0.06 * burst

	-- button
	local alive = humanoid ~= nil and humanoid.Health > 0
	local show = ready and alive
	self.UltBtn.Visible = show
	if show then
		local s = now - self.OverloadAt
		self.UltBtnScale.Scale = if s < 0.32 then 0.55 + 0.6 * math.sin(math.min(1, s / 0.32) * math.pi * 0.62) else 1 + 0.035 * build + 0.05 * burst
		self.UltBtnGrad.Color = rainbow(hue, 1)
		self.UltBtnGrad.Rotation = (now * 200) % 360
		self.UltKeyGrad.Color = rainbow(hue + 0.25, 0.6, 0.45)
		self.UltShine.Offset = V2(((now * 0.9) % 1.7) * 2 - 1.2, 0)
		self.UltBtn.BackgroundColor3 = C(10, 12, 24):Lerp(C(60, 50, 90), burst * 0.6)
	end
end

function Hud:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	if vp.X < 50 or vp.Y < 50 then
		return
	end
	if #self.Scales == 0 then
		for _, name in ipairs({ "Ammo", "Vitals", "Score", "Perf", "KillBanner", "Death", "Abilities", "SlotRail", "Hints", "BottomHints", "Killstreak" }) do
			local f = self.Root:FindFirstChild(name)
			if f then
				table.insert(self.Scales, new("UIScale", {}, f))
			end
		end
		table.insert(self.Scales, new("UIScale", {}, self.Prompt))
	end
	local scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.45, 2)
	self.UIScale = scale
	for _, sc in self.Scales do
		sc.Scale = scale
	end
	for _, a in self.Arcs do
		a.Scale.Scale = scale
	end
	self.StreakFrame.Position = UDim2.new(0, 214 * scale, 0, 196 * scale)
	-- right edge: key hints sit above the weapon rail; on short/wide screens they slide up to stay clear
	local railH = (#self.Slots * 58 - 8) * scale
	local railTop = vp.Y - 66 * scale - railH
	local hintsH = (4 * 40 + 3 * 12) * scale
	self.HintsFrame.Position = UDim2.new(1, -18 * scale, 0, math.max(150 * scale, math.min(330 * scale, railTop - hintsH - 22 * scale)))
	self.Rail.Position = UDim2.new(1, -18 * scale, 1, -66 * scale)
	self.BottomHints.Position = UDim2.new(1, -18 * scale, 1, -12 * scale)
	-- bottom-centre group: ammo sits right of the tiles at any scale
	self.AmmoFrame.Position = UDim2.new(0.5, 104 * scale, 1, -40 * scale)
	self.AbilityFrame.Position = UDim2.new(0.5, (if self.Tiles and self.Tiles.Signature then -114 else -40) * scale, 1, -14 * scale)
	for s, th in STROKES do
		if s.Parent then
			s.Thickness = math.max(1, th * scale)
		end
	end
end

function Hud:BindSettings(settings)
	self.Settings = settings
	self:_refreshHints()
	pcall(function()
		settings.Changed:Connect(function()
			self:_refreshHints()
		end)
	end)
end

function Hud:_refreshHints()
	for _, h in self.HintRows do
		local v = h.Bind and self:_setting(h.Bind, nil)
		h.Label.Text = if type(v) == "string" and v ~= "" then bindLabel(v) else h.Fallback
		local k = h.Label.Parent
		if k and k:IsA("Frame") then
			k.Size = O(math.max(34, 18 + #h.Label.Text * 11), k.Size.Y.Offset)
		end
	end
end

function Hud:_setting(key: string, default)
	local s = self.Settings
	if not s then
		return default
	end
	local ok, v = pcall(function()
		return s:Get(key)
	end)
	if not ok or v == nil then
		return default
	end
	return v
end

function Hud:_buildIcon(_weapon) end

function Hud:_buildPips(size: number)
	if self.PipCount == size then
		return
	end
	self.PipCount = size
	for _, p in self.Pips do
		p:Destroy()
	end
	self.Pips = {}
	if size <= 0 or size > 60 then
		return
	end
	self.PipHolder.Visible = true
	local w = math.max(2, math.floor((150 - (size - 1)) / size))
	for i = 1, size do
		table.insert(self.Pips, new("Frame", { LayoutOrder = i, Size = O(w, 6), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, self.PipHolder))
	end
end

function Hud:SetSkin(_skinName: string?) end

function Hud:_refreshSkin() end

-- loadout presets (2026-11-17): only the carried weapons show on the rail, numbered by their key
function Hud:SetLoadout(list)
	for _, s in self.Slots do
		local i = table.find(list, s.Id)
		s.Row.Visible = i ~= nil
		if i then
			s.Row.LayoutOrder = i
			s.KeyText.Text = tostring(i)
		end
	end
end

function Hud:_showRail()
	self.RailShownAt = os.clock()
	for _, s in self.Slots do
		if not s.Built and s.View.AbsoluteSize.X > 1 then
			s.Built = true
			silhouette(s.View, Config.Weapons[s.Id], 1.0)
		end
	end
end

function Hud:SetWeapon(weapon)
	self.Weapon = weapon
	self.SlotName.Text = string.upper(weapon.DisplayName or weapon.Id or "")
	self.WeaponClass.Text = weapon.Class or ""
	local melee = weapon.Kind == "Melee"
	local heat = weapon.Heat ~= nil
	self.ReserveLabel.Visible = not melee
	self.Divider.Visible = not melee
	self.PipHolder.Visible = heat
	if melee then
		self.MagLabel.Text = "Melee"
		self.MagLabel.TextColor3 = WHITE
		self.Prompt.Text = ""
		self.ReloadBar.Visible = false
	end
	self.LastMag = nil
	for _, s in self.Slots do
		local on = s.Id == weapon.Id
		s.Active = on
		s.View.ImageTransparency = if on then 0 else 0.2
		s.View.ImageColor3 = if on then WHITE else C(150, 156, 172)
		s.KeyText.TextTransparency = if on then 0 else 0.35
		s.Key.BackgroundTransparency = if on then 0.05 else 0.35
		if on then
			s.View.Position = UDim2.new(1, -40, 0.5, 0)
			TweenService:Create(s.View, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(1, -52, 0.5, 0) }):Play()
		end
	end
	self:_showRail()
end

function Hud:SetCrosshairStyle(style: string)
	self.CrossStyle = style
	local knife = style == "Knife"
	for _, l in self.Lines do
		l.Visible = not knife
	end
	self.KnifeRing.Visible = knife
	self.Dot.Size = if knife then O(3, 3) else O(CROSS.Dot, CROSS.Dot)
end

function Hud:SetAmmo(mag: number, reserve: number, size: number)
	if self.Weapon and (self.Weapon.Kind == "Melee" or self.Weapon.Heat ~= nil) then
		return
	end
	if self.LastMag and mag < self.LastMag then
		self.MagPunch = 1
	end
	self.LastMag = mag
	self.MagLabel.Text = tostring(mag)
	self.ReserveLabel.Text = if reserve > 0 then "∞" else tostring(reserve) -- infinite reserve for now
	local low = mag <= math.floor(size * H.LowAmmoFraction)
	self.MagLabel.TextColor3 = if mag == 0 then RED elseif low then AMBER else WHITE
	self.ReserveLabel.TextColor3 = if reserve == 0 then RED else WHITE
	if mag == 0 and reserve == 0 then
		self.Prompt.Text = "No Ammo!"
		self.Prompt.TextColor3 = RED
	elseif mag == 0 then
		self.Prompt.Text = "Reload [R]"
		self.Prompt.TextColor3 = AMBER
	elseif low and reserve > 0 then
		self.Prompt.Text = "Low Ammo"
		self.Prompt.TextColor3 = AMBER
	else
		self.Prompt.Text = ""
	end
end

function Hud:SetReload(progress: number?)
	if progress then
		self.ReloadBar.Visible = true
		self.ReloadFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		if self.Prompt.Text ~= "" then
			self.Prompt.Text = ""
		end
	else
		self.ReloadBar.Visible = false
	end
end

function Hud:FireKick()
	self.Kick = math.min(math.max(self.Kick, 0) + 1, 2)
end

function Hud:SetCrosshairVisible(on: boolean)
	self.CrossVisible = on
end

function Hud:SetADS(a: number)
	self.ADS = a
end

function Hud:ShowPredictedHit(p)
	if p then
		self.Feedback:Predicted(p)
	end
end

function Hud:ShowHit(headshot: boolean, killed: boolean, victimName: string?)
	local now = os.clock()
	if killed then
		self.BannerName.Text = victimName or "Enemy"
		self.BannerTag.Text = if headshot then "Headshot!" else "Eliminated!"
		self.BannerTag.TextColor3 = if headshot then GOLD else RED
		self.Banner.Visible = not self.SuppressKillBanner
		self.BannerUntil = now + 1.8
		self.BannerStart = now
	end
end

function Hud:ShowDamageNumber(position: Vector3, amount: number, headshot: boolean, killed: boolean)
	if not self:_setting("DamageIndicators", true) or not position then
		return
	end
	self.NumberIndex = self.NumberIndex % 8 + 1
	local rec = self.Numbers[self.NumberIndex]
	if not rec then
		local att = Instance.new("Attachment")
		att.Parent = Workspace.Terrain
		local bb = new("BillboardGui", { Size = O(80, 30), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 400, Adornee = att, ResetOnSpawn = false }, self.Gui)
		local t = text(bb, { TextSize = 22, Text = "", Stroke = 2 })
		rec = { Att = att, Gui = bb, Label = t, Start = 0 }
		self.Numbers[self.NumberIndex] = rec
	end
	rec.Att.WorldPosition = position + Vector3.new(0, 0.6, 0)
	rec.Base = rec.Att.WorldPosition
	rec.Label.Text = tostring(math.floor(amount + 0.5))
	rec.Label.TextColor3 = if killed then RED elseif headshot then GOLD else WHITE
	rec.Gui.Enabled = true
	rec.Start = os.clock()
end

function Hud:ShowIncoming(sourcePos: Vector3)
	if not self:_setting("DamageIndicators", true) then
		return
	end
	local char = Players.LocalPlayer.Character
	local shieldUp = char ~= nil and (char:GetAttribute("Shield") or 0) > 0.5
	local best, oldest = nil, math.huge
	for _, a in self.Arcs do
		if a.Until < oldest then
			best, oldest = a, a.Until
		end
	end
	local col = if shieldUp then CYAN else RED
	for _, s in best.Segs do
		s.BackgroundColor3 = col
	end
	best.Glow.BackgroundColor3 = col
	best.Source = sourcePos
	best.Until = os.clock() + 1.2
	best.Born = os.clock()
	best.Holder.Visible = true
	if not shieldUp then
		self.Flash = math.max(self.Flash, 0.45)
	end
end

function Hud:ShowDeath(killerName: string?, info: string?)
	self.DeathName.Text = killerName or "Unknown"
	self.DeathInfo.Text = info or ""
	self.DeathCard.Visible = true
	self.DeathCard.Position = UDim2.new(0.5, 0, 0.62, 14)
	TweenService:Create(self.DeathCard, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.62, 0) }):Play()
end

function Hud:HideDeath()
	self.DeathCard.Visible = false
end

function Hud:Fade(toBlack: boolean, time: number)
	TweenService:Create(self.Fader, TweenInfo.new(time, Enum.EasingStyle.Quad), { BackgroundTransparency = if toBlack then 0 else 1 }):Play()
end

function Hud:SetCombatVisible(on: boolean)
	self.HealthFrame.Visible = on
	self.AmmoFrame.Visible = on
	self.AbilityFrame.Visible = on
	self.Rail.Visible = on
	self.HintsFrame.Visible = on
	self.BottomHints.Visible = on
	self.StreakFrame.Visible = on
	self.CrossVisible = on
	if on then
		self:_showRail()
	end
end

function Hud:ShieldBreak()
	self.BreakFx = 1
end

function Hud:ShieldImpact(sourcePos: Vector3, shieldFrac: number, onShield: boolean): (number, number)
	local d = Workspace.CurrentCamera.CFrame:PointToObjectSpace(sourcePos)
	local a = math.atan2(d.X, -d.Z)
	local critical = if onShield then math.clamp(1 - shieldFrac / 0.33, 0, 1) else 1
	local strength = if onShield then 0.35 + 0.45 * critical else 0.75
	if self:_setting("DamageIndicators", true) then
		self.ImpactColor = if onShield then CYAN else RED
		local w = { math.max(0, math.cos(a)), math.max(0, -math.cos(a)), math.max(0, -math.sin(a)), math.max(0, math.sin(a)) }
		for i = 1, 4 do
			self.Impact[i] = math.max(self.Impact[i], strength * (0.2 + 0.8 * w[i]))
		end
	end
	return strength, math.sin(a)
end

local function setPill(p, frac: number, trailFrac: number?)
	p.Clip.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
	if trailFrac then
		p.Trail.Size = UDim2.new(math.clamp(trailFrac, 0, 1), 0, 1, 0)
	end
end

function Hud:_stepVitals(dt: number, now: number, humanoid: Humanoid?)
	local char = humanoid and humanoid.Parent
	local maxSh = char and char:GetAttribute("MaxShield") or 0
	self.ShieldRow.Visible = maxSh > 0
	if maxSh > 0 then
		local sh = math.max(0, char:GetAttribute("Shield") or 0)
		if sh <= 0 and self.LastShield > 0.5 then
			self:ShieldBreak()
		end
		if sh > self.LastShield + 0.01 and sh < maxSh then
			self.ChargeUntil = now + 0.25
		end
		if sh < self.LastShield - 0.5 then
			self.ShieldTrailHold = now + 0.4
			self.ShieldTrail = math.max(self.ShieldTrail or 0, self.LastShield)
		end
		self.LastShield = sh
		self.ShieldShown += (sh - self.ShieldShown) * expAlpha(20, dt)
		if (self.ShieldTrail or 0) > sh and now >= (self.ShieldTrailHold or 0) then
			self.ShieldTrail += (sh - self.ShieldTrail) * expAlpha(5, dt)
		elseif (self.ShieldTrail or 0) < sh then
			self.ShieldTrail = sh
		end
		setPill(self.ShieldBar, self.ShieldShown / maxSh, (self.ShieldTrail or sh) / maxSh)
		local down = sh <= 0 and humanoid ~= nil and humanoid.Health > 0
		local recharging = now < (self.ChargeUntil or 0)
		local pulse = if down then math.sin(now * 7) * 0.5 + 0.5 else 0
		self.ShieldNum.Text = tostring(math.ceil(sh))
		self.ShieldNum.TextColor3 = if down then AMBER else CYAN_HI
		self.ShieldState.Text = if down then "Shield Down!" elseif recharging then "Recharging" else ""
		self.ShieldState.TextColor3 = if down then AMBER else CYAN_HI
		self.ShieldState.TextTransparency = if down then 0.35 * (1 - pulse) else 0.1
	end
	local lowPulse = 0
	if humanoid then
		local hp = math.max(0, humanoid.Health)
		local maxHp = math.max(1, humanoid.MaxHealth)
		if hp < self.LastHP - 0.5 then
			self.TrailHoldUntil = now + 0.45
			self.Flash = math.max(self.Flash, 0.3 + math.min(0.35, (self.LastHP - hp) / 100))
			self.HealthPunch = 1
		end
		self.LastHP = hp
		self.HealthShown += (hp - self.HealthShown) * expAlpha(20, dt)
		if hp < self.TrailShown then
			if now >= self.TrailHoldUntil then
				self.TrailShown += (hp - self.TrailShown) * expAlpha(5, dt)
			end
		else
			self.TrailShown = hp
		end
		setPill(self.HealthBar, self.HealthShown / maxHp, self.TrailShown / maxHp)
		local frac = hp / maxHp
		local low = hp <= H.LowHealth
		local hi, lo = GREEN_T, GREEN_B
		if low then
			hi, lo = C(255, 130, 140), C(225, 40, 60)
		elseif frac <= 0.5 then
			hi, lo = C(255, 228, 120), C(240, 160, 30)
		end
		if self._hpTone ~= hi then
			self._hpTone = hi
			self.HealthBar.Grad.Color = ColorSequence.new(hi, lo)
		end
		self.HealthLabel.Text = tostring(math.ceil(hp))
		if low and hp > 0 then
			lowPulse = math.sin(now * 6) * 0.5 + 0.5
			self.HealthLabel.TextColor3 = GREY:Lerp(RED, 0.4 + 0.6 * lowPulse)
		else
			self.HealthLabel.TextColor3 = GREY
		end
		self.HealthPunch = math.max(0, (self.HealthPunch or 0) - dt * 6)
		self.HealthScale.Scale = 1 + 0.12 * (self.HealthPunch ^ 2)
	end
	self.Flash = math.max(0, self.Flash - dt * 1.6)
	local vig = math.max(self.Flash, lowPulse * 0.35)
	for _, e in self.VignetteEdges do
		e.BackgroundTransparency = 1 - vig
	end
	local impact = 0
	for i = 1, 4 do
		self.Impact[i] = math.max(0, self.Impact[i] - dt * 2.6)
		impact = math.max(impact, self.Impact[i])
	end
	if self.BreakFx > 0 then
		self.BreakFx = math.max(0, self.BreakFx - dt * 2.2)
		local a = self.BreakFx
		for _, e in self.BreakEdges do
			e.BackgroundColor3 = CYAN
			e.BackgroundTransparency = 1 - a * 0.5
		end
		for i, band in self.Glitch do
			local flick = math.noise(i * 3.1, now * 22) + 0.5
			band.BackgroundTransparency = 1 - math.clamp(a * flick * 0.65, 0, 0.65)
			band.Position = UDim2.new(0, math.noise(i, now * 30) * 40 * a, i / 8 + math.noise(i * 7, now * 9) * 0.04, 0)
		end
		self._breakDirty = true
	elseif impact > 0 then
		for i, e in self.BreakEdges do
			e.BackgroundColor3 = self.ImpactColor or CYAN
			e.BackgroundTransparency = 1 - self.Impact[i] * 0.6
		end
		self._breakDirty = true
	elseif self._breakDirty then
		self._breakDirty = false
		for _, e in self.BreakEdges do
			e.BackgroundTransparency = 1
		end
		for _, band in self.Glitch do
			band.BackgroundTransparency = 1
		end
	end
end

function Hud:_stepTile(t, now: number, readyAt: number, cooldown: number, active: boolean, charges: number?, maxCharges: number?)
	local left = math.max(0, readyAt - now)
	local ready = left <= 0
	local q = if ready then 0 else math.clamp(left / math.max(cooldown, 0.01), 0, 1)
	t.Shutter.Size = UDim2.fromScale(1, q)
	t.Secs.Text = if ready then "" elseif left >= 10 then tostring(math.ceil(left)) else string.format("%.1f", left)
	if t.Icon then
		t.Icon.ImageTransparency = if ready then 0 else 0.6
	end
	t.Dim.BackgroundTransparency = if ready or active then 1 else 0.5
	if ready and not t.WasReady then
		t.FlashAt = now
	end
	t.WasReady = ready
	local fa = now - t.FlashAt
	if fa < 0.35 then
		local e = fa / 0.35
		t.Flash.BackgroundTransparency = 0.3 + 0.7 * e
		t.Scale.Scale = 1 + 0.15 * (1 - e) ^ 2
	else
		t.Flash.BackgroundTransparency = 1
		t.Scale.Scale = if active then 1.06 else 1
	end
	maxCharges = maxCharges or 0
	if maxCharges > 1 then
		while #t.PipList < maxCharges do
			local p = new("Frame", { Size = O(18, 6), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 9 }, t.Pips)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
			table.insert(t.PipList, p)
		end
		for i, p in t.PipList do
			p.Visible = i <= maxCharges
			p.BackgroundTransparency = if i <= (charges or 0) then 0 else 0.7
		end
	else
		for _, p in t.PipList do
			p.Visible = false
		end
	end
end

function Hud:_stepAbilities(now: number)
	if not self.AbilityFrame.Visible then
		return
	end
	local gt = self.Tiles.Grapple
	if gt then
		local cd, maxCh, ch = 3.5, 1, nil
		local G = AbilityConfig and AbilityConfig.Abilities and AbilityConfig.Abilities.Grapple
		if G then
			cd = G.Cooldown or cd
		end
		if EquipCatalog and EquipCatalog.HookStats then
			local ok, hs = pcall(EquipCatalog.HookStats, Players.LocalPlayer)
			if ok and hs then
				cd = hs.Cooldown or cd
				maxCh = hs.Charges or 1
			end
		end
		local readyAt = GrappleFeed and GrappleFeed.ReadyAt or 0
		if GrappleFeed and GrappleFeed.ChargeTimes and maxCh > 1 then
			ch = 0
			for i = 1, maxCh do
				local ct = GrappleFeed.ChargeTimes[i]
				if not ct or ct <= now then
					ch += 1
				end
			end
		end
		local active = GrappleFeed ~= nil and (GrappleFeed.FiredAt or 0) > 0 and GrappleFeed.EndAt == nil
		self:_stepTile(gt, now, readyAt, cd, active, ch, maxCh)
	end
	local ft = self.Tiles.Grenade
	if ft then
		local cd = (GrenadeConfig and GrenadeConfig.Cooldown) or 20
		local readyAt = GrenadeFeed and GrenadeFeed.ReadyAt or 0
		self:_stepTile(ft, now, readyAt, cd, GrenadeFeed ~= nil and GrenadeFeed.Start ~= nil, nil, 0)
	end
	local st = self.Tiles.Signature
	if st and SignatureFeed then
		local id = SignatureFeed.Id
		if id ~= st.SigId then
			st.SigId = id
			local it = SignatureCatalog and SignatureCatalog.ById[id]
			st.Art.Image = it and it.Art or ""

		end
		local c = SignatureConfig and SignatureConfig.Sig[id]
		local t = os.clock()
		self:_stepTile(st, t, SignatureFeed.ReadyAt or 0, SignatureFeed.Cooldown or 40, SignatureFeed.Active == true, nil, 0)
		local left = math.max(0, (SignatureFeed.ReadyAt or 0) - t)
		local ready = left <= 0
		local q = if ready then 0 else math.clamp(left / math.max(SignatureFeed.Cooldown or 40, 0.01), 0, 1)
		local fill = 1 - q
		local hue = (t * 0.22) % 1
		st.Art.ImageTransparency = if ready then 0 else 0.12
		st.Dim.BackgroundTransparency = 1
		st.Charge.Visible = not ready
		if not ready then
			st.Charge.Size = UDim2.fromScale(1, fill)
			st.ChargeGrad.Color = rainbow(hue, 0.55, 0.85)
			st.Charge.BackgroundTransparency = 0.62 - 0.27 * fill + math.sin(t * 6) * 0.04
			st.EdgeGrad.Color = rainbow(hue + 0.4, 1, 0.35)
			st.EdgeGlow.ImageColor3 = Color3.fromHSV((hue + 0.15) % 1, 0.5, 1)
			st.EdgeGlow.ImageTransparency = 0.45 + math.sin(t * 9) * 0.12
			st.ChargeEdge.Visible = fill > 0.01
		end
		if st.RimGrad then
			st.RimGrad.Color = rainbow(hue, 1, if ready then 0.8 else 0.35 + 0.35 * fill)
			st.RimGrad.Rotation = (t * 120) % 360
		end
		st.Glow.ImageColor3 = Color3.fromHSV((hue + 0.1) % 1, 0.6, 1)
		if ready then
			st.Glow.ImageTransparency = 0.38 + 0.14 * math.sin(t * 4.2)
			st.Glow.Size = O(190 + 12 * math.sin(t * 4.2), 190 + 12 * math.sin(t * 4.2))
		else
			st.Glow.ImageTransparency = 1 - 0.55 * fill ^ 3
			st.Glow.Size = O(150 + 40 * fill, 150 + 40 * fill)
		end
		if c and not c.Implemented then st.Dim.BackgroundTransparency = 0.45 end
		local d = SignatureFeed.Denied
		local show = d and t - d.At < 1.3
		st.Note.Text = if show then d.Text else ""
		st.Note.TextTransparency = if show then math.clamp((t - d.At - 0.9) / 0.4, 0, 1) else 1
	end
end

function Hud:_stepPlayers(now: number)
	if now < self.RowNext then
		return
	end
	self.RowNext = now + 0.25
	local match = ReplicatedStorage.Vantage:FindFirstChild("Match")
	local id = match and match:GetAttribute("MatchId")
	local list = {}
	for _, p in Players:GetPlayers() do
		local t = p.Team and p.Team.Name
		if (t == "Blue" or t == "Red") and (id == nil or p:GetAttribute("MatchId") == nil or p:GetAttribute("MatchId") == id) then
			table.insert(list, { P = p, K = tonumber(p:GetAttribute("MatchStats_Kills")) or 0, T = t })
		end
	end
	table.sort(list, function(a, b)
		if a.K ~= b.K then
			return a.K > b.K
		end
		return a.P.Name < b.P.Name
	end)
	local me = Players.LocalPlayer
	for i, a in self.Avatars do
		local e = list[i]
		a.Cell.Visible = e ~= nil
		if e then
			a.Kills.Text = tostring(e.K)
			a.Kills.TextColor3 = if e.P == me then GOLD else WHITE
			a.RingStroke.Color = if e.T == "Blue" then BLUE_B else RED_B
			if a.UserId ~= e.P.UserId then
				a.UserId = e.P.UserId
				a.Img.Image = self.ThumbCache[e.P.UserId] or ""
				a.Initial.Text = string.upper(string.sub(e.P.Name, 1, 1))
				if not self.ThumbCache[e.P.UserId] and e.P.UserId > 0 then
					local uid = e.P.UserId
					task.spawn(function()
						local ok, url = pcall(function()
							return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
						end)
						if ok and url then
							self.ThumbCache[uid] = url
							if a.UserId == uid then
								a.Img.Image = url
							end
						end
					end)
				end
			end
			a.Initial.Visible = a.Img.Image == ""
		end
	end
end

function Hud:Step(dt: number, spreadDeg: number, humanoid: Humanoid?)
	local now = os.clock()
	local target = spreadDeg * H.SpreadToPixels
	self.Spread += (target - self.Spread) * expAlpha(18, dt)
	self.Kick += (0 - self.Kick) * expAlpha(14, dt)
	-- Hypershot: the cross barely breathes (a hint of movement spread, ~1 px per shot)
	local px = math.clamp(Workspace.CurrentCamera.ViewportSize.Y / 1080, 0.8, 1.6)
	local gap = math.round((CROSS.Gap + math.min(self.Spread * 0.4, 5) + math.max(self.Kick, 0)) * px)
	for n, l in self.Lines do
		local vert = n == "Up" or n == "Down"
		local L, T = math.round(CROSS.Len * px), math.max(2, math.round(CROSS.Thick * px))
		l.Size = if vert then O(T, L) else O(L, T)
	end
	self.Dot.Size = if self.CrossStyle == "Knife" then O(3, 3) else O(math.max(2, math.round(CROSS.Dot * px)), math.max(2, math.round(CROSS.Dot * px)))
	self.Lines.Up.Position = O(0, -gap)
	self.Lines.Down.Position = O(0, gap)
	self.Lines.Left.Position = O(-gap, 0)
	self.Lines.Right.Position = O(gap, 0)
	self.Cross.Visible = self.CrossVisible and self:_setting("Crosshair", true) and self.ADS < 0.6
	local ct = math.clamp(self.ADS / 0.6, 0, 1)
	for _, l in self.Lines do
		l.BackgroundTransparency = ct
	end
	self.Dot.BackgroundTransparency = ct

	self.Feedback:Step(dt, now)

	if self.Banner.Visible then
		local a = now - (self.BannerStart or now)
		local left = (self.BannerUntil or 0) - now
		if left <= 0 then
			self.Banner.Visible = false
		else
			local ap = math.clamp(a / 0.12, 0, 1)
			local fade = math.clamp(left / 0.35, 0, 1)
			self.BannerName.TextTransparency = 1 - fade * ap
			self.BannerTag.TextTransparency = 1 - fade * ap
		end
	end

	local cam = Workspace.CurrentCamera.CFrame
	for _, arc in self.Arcs do
		if arc.Holder.Visible then
			local left = arc.Until - now
			if left <= 0 then
				arc.Holder.Visible = false
			else
				local d = cam:PointToObjectSpace(arc.Source)
				arc.Holder.Rotation = math.deg(math.atan2(d.X, -d.Z))
				local t = 1 - math.clamp(left / 0.5, 0, 1)
				local born = now - (arc.Born or now)
				local pop = if born < 0.12 then (1 - born / 0.12) else 0
				for _, s in arc.Segs do
					s.BackgroundTransparency = t
				end
				arc.Glow.BackgroundTransparency = math.clamp(0.4 + 0.6 * t - pop * 0.3, 0, 1)
			end
		end
	end

	for _, rec in self.Numbers do
		if rec.Gui.Enabled then
			local a = (now - rec.Start) / 0.7
			if a >= 1 then
				rec.Gui.Enabled = false
			else
				rec.Att.WorldPosition = rec.Base + Vector3.new(0, a * 1.2, 0)
				rec.Label.TextTransparency = math.clamp((a - 0.5) * 2, 0, 1)
			end
		end
	end

	if self.Prompt.Text ~= "" then
		self.Prompt.TextTransparency = 0.05 + 0.3 * (math.sin(now * 5) * 0.5 + 0.5)
	end

	self.MagPunch = math.max(0, self.MagPunch - dt * 9)
	self.MagScale.Scale = 1 + 0.1 * self.MagPunch

	self:_stepVitals(dt, now, humanoid)
	self:_stepAbilities(now)
	self:_stepPlayers(now)

	self:_stepStreak(dt, now, humanoid)

	local match = ReplicatedStorage.Vantage:FindFirstChild("Match")
	if match then
		local bs, rs = match:GetAttribute("BlueScore") or 0, match:GetAttribute("RedScore") or 0
		local limit = math.max(1, match:GetAttribute("ScoreLimit") or H.ScoreLimit or 50)
		for _, pair in { { self.SideBlue, bs, rs }, { self.SideRed, rs, bs } } do
			local sd, v, other = pair[1], pair[2], pair[3]
			-- leader underline (fades in / out, breathes slowly)
			local goalLead = if v > other then 1 else 0
			sd.Lead += (goalLead - sd.Lead) * expAlpha(8, dt)
			local breathe = 0.85 + 0.15 * math.sin(now * 3)
			sd.Bar.BackgroundTransparency = 1 - sd.Lead * breathe
			sd.BarGlow.Transparency = 1 - sd.Lead * 0.55 * breathe
			if sd.Last ~= v then
				if sd.Last >= 0 and v > sd.Last then
					sd.PopAt = now
				end
				sd.Last = v
				sd.Num.Text = tostring(v)
			end
			local pa = now - (sd.PopAt or -10)
			sd.Scale.Scale = if pa < 0.3 then 1 + 0.22 * (1 - pa / 0.3) ^ 2 else 1
		end
		local ot = match:GetAttribute("Overtime") == true
		if self._limit ~= limit or self._ot ~= ot then
			self._limit, self._ot = limit, ot
			self.TargetLabel.Text = if ot then "SUDDEN DEATH!" else "First to " .. limit .. "!"
			self.TargetLabel.TextColor3 = if ot then C(255, 205, 70) else WHITE
		end
		local mode = match:GetAttribute("Mode")
		if mode ~= self._mode then
			self._mode = mode
			self.ModeLabel.Text = if type(mode) == "string" and mode ~= "" then (MODE_NAMES[mode] or ((MODE_NAMES[(mode:gsub("_%d+$", ""))] or mode:gsub("_%d+$", "")) .. " " .. (mode:match("_(%d+)$") or "") .. "V" .. (mode:match("_(%d+)$") or ""))) else ""
		end
	end

	self.PerfFrames += 1
	if now - self.PerfSince >= 0.5 then
		local fps = self.PerfFrames / (now - self.PerfSince)
		self.PerfFrames, self.PerfSince = 0, now
		local ok, ping = pcall(function()
			return Players.LocalPlayer:GetNetworkPing()
		end)
		self.PerfLabel.Text = string.format("%d FPS | %d ms", math.floor(fps + 0.5), if ok then math.floor(ping * 1000 + 0.5) else 0)
	end
	local left = match and match:GetAttribute("TimeLeft")
	if type(left) ~= "number" then
		left = math.max(0, H.MatchLength - (os.clock() - self.TimerStart))
	end
	self.Timer.Text = string.format("%02d:%02d", math.floor(left / 60), math.floor(left % 60))
	local sec = math.floor(left)
	if match and match:GetAttribute("Overtime") == true then
		self.Timer.TextColor3 = C(255, 205, 70) -- overtime clock in gold
		if sec ~= self.LastSecond then
			self.LastSecond = sec
			self.TimerPopAt = now
		end
	elseif left <= 30 and left > 0 then
		self.Timer.TextColor3 = C(255, 150, 160)
		if sec ~= self.LastSecond then
			self.LastSecond = sec
			self.TimerPopAt = now
		end
	else
		self.Timer.TextColor3 = WHITE
	end
	local tpa = now - (self.TimerPopAt or -10)
	self.TimerScale.Scale = if tpa < 0.25 then 1 + 0.12 * (1 - tpa / 0.25) else 1
end

function Hud:Destroy()
	self.Gui:Destroy()
end

return Hud
