--[[
	VisorHolo — the holographic visor HUD (v6, approved mock holo_hud_mock_v6e).

	Panels are SurfaceGuis on client-only parts floating 0.6 studs in front of the camera, sized so a
	design pixel (1920x1080 screen) maps 1:1 at that depth. Each panel is angled toward the eye (real
	perspective) and trails head turns by its layer's lag (parallax between layers). SurfaceGui
	Brightness > 1 + LightInfluence 0 lets the lines catch the game's bloom.
	(AlwaysOnTop SurfaceGuis do not render in this place; the near placement keeps walls / the
	viewmodel from cutting through.)

	Holo.new(ctx) -> holo        ctx = { Player, Feed, AbilityConfig, Ability(name) -> (state, left, cooldown),
	                                     RadarDots = { Frame }, Glass = ScreenGui, Group = Frame (2D HUD), LastKill() }
	holo:Step(dt)                every frame while the helmet is closed
	holo:SetShown(on, instant?)  boot / shutdown of the panels
	holo:AbilityUsed(name)       per-ability badge animation
	holo:SetEjected(on, reboot?) shield down: every panel except Holo.EJECT_KEEP glitches out and stays dark
	                             (one-frame ghosts now and then); off + reboot = staggered draw-back-in
]]
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KIT = require(script.Parent:WaitForChild("VisorKit"))

local C = Color3.fromRGB
local V2 = Vector2.new
local O = UDim2.fromOffset
local rad = math.rad
local TF = "rbxasset://fonts/families/TitilliumWeb.json"
local F_B = Font.new(TF, Enum.FontWeight.Bold)
local F_SB = Font.new(TF, Enum.FontWeight.SemiBold)

-- palette (user-specified)
local PRI = C(77, 205, 255) -- #4DCDFF primary holographic blue
local DEEP = C(40, 127, 191) -- #287FBF deep electric blue
local BG = C(7, 24, 43) -- #07182B dark blue background
local GREY = C(96, 132, 168) -- #6084A8 subtle blue-grey
local HI = C(160, 255, 255) -- #A0FFFF bright cyan-white highlight
local GREEN = C(110, 255, 200)
local AMBER = C(255, 180, 70)
local RED = C(255, 80, 64)
local MATE = C(110, 170, 255)

local DEPTH = 0.6
-- the glass opening (HoloFrame inner contour, 1920x1080 design px; the frame quads stretch with the screen)
local GLASS_HALF = { { 960, 160 }, { 700, 150 }, { 480, 128 }, { 370, 72 }, { 200, 66 }, { 108, 132 }, { 76, 262 }, { 74, 540 }, { 100, 580 }, { 78, 620 }, { 76, 880 }, { 156, 976 }, { 296, 1030 }, { 640, 1030 }, { 690, 990 }, { 960, 990 } }
local GLASS = {}
for _, q in GLASS_HALF do
	table.insert(GLASS, Vector2.new(q[1], q[2]))
end
for i = #GLASS_HALF - 1, 1, -1 do
	table.insert(GLASS, Vector2.new(1920 - GLASS_HALF[i][1], GLASS_HALF[i][2]))
end
local function insideGlass(p: Vector2): boolean
	-- 18 px clear of the lit edge: test the point pushed outward from the centre
	local c = Vector2.new(960, 560)
	local d = p - c
	p = c + d + (if d.Magnitude > 1 then d.Unit * 18 else Vector2.zero)
	local inside, j = false, #GLASS
	for i = 1, #GLASS do
		local a, b = GLASS[i], GLASS[j]
		if (a.Y > p.Y) ~= (b.Y > p.Y) and p.X < (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X then
			inside = not inside
		end
		j = i
	end
	return inside
end
local WIRE = {
	Vanguard = "Wire_VX01_Vanguard", Sentinel = "Wire_BR07_Sentinel", Longshot = "Wire_SR88_Longshot",
	Breacher = "Wire_SG12_Breacher", Spectre = "Wire_PX9_Spectre", Arc = "Wire_ER04_Arc", Knife = "Wire_Combat_Knife",
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
local function tween(inst, t, props, style, dir, delay)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end
-- holographic text: a soft deep-blue halo that fades with the text
local function txt(parent, props)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or F_SB
	props.TextColor3 = props.TextColor3 or PRI
	local l = new("TextLabel", props, parent)
	local st = new("UIStroke", { Color = DEEP, Thickness = props.TextSize and props.TextSize > 30 and 3 or 1.5, Transparency = 0.55 }, l)
	l:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		st.Transparency = 0.55 + 0.45 * l.TextTransparency
	end)
	return l
end
local function rect(parent, x, y, w, h, color, tr, z)
	return new("Frame", { Position = O(x, y), Size = O(w, h), BackgroundColor3 = color, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z or 1 }, parent)
end
-- a thin line between two points (rotated frame)
local function line(parent, x1, y1, x2, y2, color, thick, tr, z)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	return new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O((x1 + x2) / 2, (y1 + y2) / 2), Size = O(len, thick or 2), Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = color, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z or 2 }, parent)
end
-- holographic glass: navy fill, chamfered top-left / bottom-right, layered lit edge, fine scan lines
local function glass(parent, w, h, c, opts)
	opts = opts or {}
	local fillT = opts.Fill or 0.45
	rect(parent, c, 0, w - c, h - c, BG, fillT, 0)
	rect(parent, 0, c, c, h - c, BG, fillT, 0)
	rect(parent, c, h - c, w - 2 * c, c, BG, fillT, 0)
	local CUT = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.502, 1), NumberSequenceKeypoint.new(1, 1) })
	local tl = rect(parent, 0, 0, c, c, BG, fillT, 0)
	new("UIGradient", { Rotation = 225, Transparency = CUT }, tl)
	local br = rect(parent, w - c, h - c, c, c, BG, fillT, 0)
	new("UIGradient", { Rotation = 45, Transparency = CUT }, br)
	-- a faint deep-blue wash toward the edges (glass thickness)
	local wash = rect(parent, 0, 0, w, h, DEEP, 0.86, 0)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.2) }) }, wash)
	-- edge: straight runs + the two diagonals
	local ec, et = opts.Edge or PRI, opts.EdgeT or 0
	local edges = {
		line(parent, c, 1, w, 1, ec, 2, et, 3), line(parent, w - 1, 0, w - 1, h - c, ec, 2, et, 3),
		line(parent, w - c, h - 1, 0, h - 1, ec, 2, et, 3), line(parent, 1, h, 1, c, ec, 2, et, 3),
		line(parent, 0, c, c, 0, ec, 2, et, 3), line(parent, w - c, h, w, h - c, ec, 2, et, 3),
	}
	-- inner second edge (layered glass)
	local k = 7
	line(parent, c + k * 0.4, k, w - k, k, DEEP, 1, 0.3, 3)
	line(parent, w - k, k, w - k, h - c - k * 0.4, DEEP, 1, 0.3, 3)
	line(parent, k, h - k, w - c - k * 0.4, h - k, DEEP, 1, 0.3, 3)
	line(parent, k, h - k, k, c + k * 0.4, DEEP, 1, 0.3, 3)
	-- scan lines across the projected glass
	if opts.Scan ~= false then
		for y = 3, h - 3, 5 do
			rect(parent, 2, y, w - 4, 1, PRI, 0.94, 1)
		end
	end
	return edges
end
local function bar(parent, x, y, w, h, color, track)
	local tr = rect(parent, x, y, w, h, DEEP, track or 0.6, 2)
	local f = rect(tr, 0, 0, w, h, color, 0, 3)
	f.Size = UDim2.fromScale(1, 1)
	return f, tr
end

-- ─── panels ────────────────────────────────────────────────────────────────────────────
local Holo = {}
Holo.__index = Holo

function Holo.new(ctx)
	local self = setmetatable({}, Holo)
	self.ctx = ctx
	self.Player = ctx.Player
	self.Feed = ctx.Feed
	self.Shown = false
	self.Panels = {}
	self.History = table.create(48, 1)
	self.HistAt = 0
	self.WireFrame, self.WireT = 0, 0
	self.Weapon = nil
	self.T = 0
	local old = Workspace:FindFirstChild("VantageVisorHolo")
	if old then
		old:Destroy()
	end
	self.Folder = new("Folder", { Name = "VantageVisorHolo" }, Workspace)
	local pg = self.Player:WaitForChild("PlayerGui")
	for _, g in pg:GetChildren() do
		if g:IsA("SurfaceGui") and g.Name:match("^Holo_") then
			g:Destroy()
		end
	end
	self.PG = pg
	self.LagCF = Workspace.CurrentCamera.CFrame
	self:_build()
	self:SetShown(false, true)
	return self
end

-- side: "L" (x from the left edge), "R" (x from the right edge), "C" (from the centre); design 1920x1080
function Holo:_panel(name, side, cx, cy, w, h, yaw, pitch, lag)
	local part = new("Part", { Name = name, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.001), Locked = true }, self.Folder)
	local gui = new("SurfaceGui", { Name = "Holo_" .. name, Face = Enum.NormalId.Back, LightInfluence = 0, Brightness = 2.2, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 1000, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Adornee = part }, self.PG)
	local root = new("CanvasGroup", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 0 }, gui)
	local p = { Part = part, Gui = gui, Root = root, Side = side, CX = cx, CY = cy, W = w, H = h, Yaw = yaw, Pitch = pitch or 0, Lag = lag or 0.6, Pop = 1, Fit = 1, NX = 0, NY = 0, FitDone = false }
	self.Panels[name] = p
	return p, root
end

function Holo:_build()
	local ctx = self.ctx

	-- brand tag ─────────────────────────────────────────────────────────────────────
	do
		local _, r = self:_panel("Brand", "L", 410, 150, 340, 76, 8, 0, 0.6)
		local logo = new("Frame", { Position = O(10, 10), Size = O(46, 50), BackgroundTransparency = 1 }, r)
		line(logo, 2, 4, 44, 4, HI, 3, 0, 3)
		line(logo, 44, 4, 23, 46, HI, 3, 0, 3)
		line(logo, 23, 46, 2, 4, HI, 3, 0, 3)
		line(logo, 12, 12, 34, 12, PRI, 4, 0.1, 3)
		line(logo, 34, 12, 23, 34, PRI, 4, 0.1, 3)
		txt(r, { Position = O(66, 6), Size = O(270, 34), FontFace = F_B, Text = "VANTAGESHOT", TextSize = 30, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Left })
		txt(r, { Position = O(68, 42), Size = O(270, 18), Text = "COMBAT SYSTEM  v6.0", TextSize = 15, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
	end

	-- left: suit panel (live avatar hologram + real vitals) ────────────────────────────
	do
		local p, r = self:_panel("Suit", "L", 337, 448, 470, 480, 14, 0, 0.62)
		p.Base = 0.85
		glass(r, 470, 480, 26)
		self.SuitName = txt(r, { Position = O(26, 16), Size = O(300, 22), FontFace = F_B, Text = "SUIT //", TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
		txt(r, { Position = O(26, 38), Size = O(300, 16), Text = "OPERATOR HOLOGRAM  ·  LIVE", TextSize = 13, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
		-- avatar (ViewportFrame lives outside the CanvasGroup so it renders; faded with the panel)
		local vpf = new("ViewportFrame", { Position = O(10, 64), Size = O(230, 404), BackgroundTransparency = 1, ImageColor3 = C(120, 215, 255), ImageTransparency = 0.3, Ambient = C(70, 140, 220), LightColor = C(230, 250, 255), LightDirection = Vector3.new(-0.3, -0.6, -0.7), ZIndex = 5 }, p.Gui)
		self.AvatarVPF = vpf
		self.AvatarCam = new("Camera", { FieldOfView = 22 }, vpf)
		vpf.CurrentCamera = self.AvatarCam
		-- body scan lines + a travelling sweep over the hologram
		local scanHolder = new("Frame", { Position = O(10, 64), Size = O(230, 404), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 6 }, p.Gui)
		for y = 0, 420, 4 do
			rect(scanHolder, 0, y, 230, 1, BG, 0.75, 6)
		end
		self.AvatarSweep = rect(scanHolder, 0, 0, 230, 18, HI, 0.55, 7)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, self.AvatarSweep)
		self.AvatarScan = scanHolder
		-- readouts
		local X = 258
		txt(r, { Position = O(X, 70), Size = O(190, 16), FontFace = F_B, Text = "SHIELD", TextSize = 15, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
		self.ShieldNum = txt(r, { Position = O(X, 84), Size = O(130, 58), FontFace = F_B, Text = "100", TextSize = 56, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Left })
		txt(r, { Position = O(X + 112, 112), Size = O(40, 26), Text = "%", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
		self.ShieldBar = bar(r, X, 148, 190, 7, PRI)
		txt(r, { Position = O(X, 168), Size = O(190, 16), FontFace = F_B, Text = "VITALS", TextSize = 15, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
		self.HealthNum = txt(r, { Position = O(X, 166), Size = O(190, 20), FontFace = F_B, Text = "100", TextSize = 18, TextColor3 = PRI, TextXAlignment = Enum.TextXAlignment.Right })
		self.HealthBar = bar(r, X, 192, 190, 4, PRI)
		txt(r, { Position = O(X, 210), Size = O(190, 14), Text = "INTEGRITY  ·  20 S", TextSize = 13, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
		-- integrity trace: 48 samples of (shield + health) / 2 over the last 20 s
		self.Trace = {}
		for i = 1, 48 do
			self.Trace[i] = new("Frame", { AnchorPoint = V2(0, 1), Position = O(X + (i - 1) * 4, 280), Size = O(3, 40), BackgroundColor3 = PRI, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, r)
		end
		rect(r, X, 281, 190, 1, GREY, 0.4, 3)
		self.Rows = {}
		for i, k in { "SPEED", "ALTITUDE", "STANCE", "SHIELD REGEN" } do
			local y = 298 + (i - 1) * 32
			txt(r, { Position = O(X, y), Size = O(110, 18), Text = k, TextSize = 15, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
			self.Rows[k] = txt(r, { Position = O(X, y), Size = O(190, 18), FontFace = F_B, Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right })
			rect(r, X, y + 24, 190, 1, DEEP, 0.5, 2)
		end
		-- frame meters on the left band: shield cells (top) and Pulse Scan charge (bottom) — 2D, on the glass
		self.ShieldCells, self.ScanCells = {}, {}
		local g = ctx.Glass
		for i = 1, 10 do
			self.ShieldCells[i] = new("Frame", { Name = "ShieldCell", Position = UDim2.fromScale(30 / 1920, (300 + (10 - i) * 22) / 1080), Size = UDim2.fromScale(14 / 1920, 16 / 1080), BackgroundColor3 = PRI, BorderSizePixel = 0, ZIndex = 8 }, g)
		end
		for i = 1, 12 do
			self.ScanCells[i] = new("Frame", { Name = "ScanCell", Position = UDim2.fromScale(30 / 1920, (700 + (12 - i) * 16) / 1080), Size = UDim2.fromScale(14 / 1920, 11 / 1080), BackgroundColor3 = PRI, BorderSizePixel = 0, ZIndex = 8 }, g)
		end
	end

	-- right: weapon panel (true wireframe of the equipped weapon + real config stats) ────
	do
		local pw, r = self:_panel("Weapon", "R", 1583, 448, 470, 480, -14, 0, 0.62)
		pw.Base = 0.85
		glass(r, 470, 480, 26)
		self.WName = txt(r, { Position = O(26, 16), Size = O(300, 22), FontFace = F_B, Text = "", TextSize = 20, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Left })
		self.WClass = txt(r, { Position = O(220, 20), Size = O(226, 16), Text = "", TextSize = 14, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Right })
		self.Wire = new("ImageLabel", { Position = O(-6, 40), Size = O(482, 241), BackgroundTransparency = 1, ImageColor3 = PRI, ImageRectSize = Vector2.new(512, 256), ZIndex = 4 }, r)
		self.WireGlow = new("ImageLabel", { Position = O(-6, 40), Size = O(482, 241), BackgroundTransparency = 1, ImageColor3 = DEEP, ImageTransparency = 0.4, ImageRectSize = Vector2.new(512, 256), ZIndex = 3 }, r)
		self.WireScan = rect(r, 0, 40, 470, 3, HI, 0.2, 5)
		self.WireScan.Visible = false
		self.Stats = {}
		for i = 1, 5 do
			local y = 296 + (i - 1) * 38
			local k = txt(r, { Position = O(28, y), Size = O(200, 18), Text = "", TextSize = 15, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
			local v = txt(r, { Position = O(232, y - 2), Size = O(210, 20), FontFace = F_B, Text = "", TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right })
			local b = bar(r, 28, y + 24, 414, 3, PRI, 0.55)
			self.Stats[i] = { K = k, V = v, B = b }
		end
	end

	-- top-right: match panel ─────────────────────────────────────────────────────────
	do
		local _, r = self:_panel("Match", "R", 1568, 158, 330, 160, -10, 0, 0.66)
		glass(r, 330, 160, 18)
		txt(r, { Position = O(20, 12), Size = O(200, 20), FontFace = F_B, Text = "TEAM DEATHMATCH", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
		self.MTime = txt(r, { Position = O(200, 10), Size = O(112, 22), FontFace = F_B, Text = "10:00", TextSize = 20, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Right })
		txt(r, { Position = O(20, 44), Size = O(60, 16), FontFace = F_B, Text = "BLUE", TextSize = 14, TextColor3 = MATE, TextXAlignment = Enum.TextXAlignment.Left })
		txt(r, { Position = O(252, 44), Size = O(60, 16), FontFace = F_B, Text = "RED", TextSize = 14, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Right })
		self.MBlue = txt(r, { Position = O(90, 36), Size = O(60, 32), FontFace = F_B, Text = "00", TextSize = 30, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Right })
		self.MRed = txt(r, { Position = O(180, 36), Size = O(60, 32), FontFace = F_B, Text = "00", TextSize = 30, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Left })
		txt(r, { Position = O(150, 40), Size = O(30, 24), FontFace = F_B, Text = "-", TextSize = 20, TextColor3 = GREY })
		self.MBlueBar = bar(r, 20, 82, 142, 5, MATE)
		local rt = rect(r, 170, 82, 142, 5, DEEP, 0.6, 2)
		self.MRedBar = new("Frame", { AnchorPoint = V2(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0, 1), BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 3 }, rt)
		self.MLimit = txt(r, { Position = O(0, 94), Size = O(330, 16), Text = "FIRST TO 50", TextSize = 13, TextColor3 = GREY })
		rect(r, 20, 117, 292, 1, DEEP, 0.4, 2)
		self.MFeed = txt(r, { Position = O(20, 124), Size = O(292, 20), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	end

	-- bottom-right: ammo panel ───────────────────────────────────────────────────────
	do
		local _, r = self:_panel("Ammo", "R", 1560, 856, 400, 172, -10, 0, 0.5)
		glass(r, 400, 172, 22)
		self.AName = txt(r, { Position = O(24, 14), Size = O(260, 22), FontFace = F_B, Text = "", TextSize = 20, TextColor3 = PRI, TextXAlignment = Enum.TextXAlignment.Left })
		self.AMode = txt(r, { Position = O(260, 16), Size = O(116, 18), FontFace = F_B, Text = "", TextSize = 16, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Right })
		self.ASub = txt(r, { Position = O(24, 38), Size = O(352, 16), Text = "", TextSize = 13, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
		self.AMag = txt(r, { AnchorPoint = V2(1, 0), Position = O(214, 46), Size = O(200, 92), FontFace = F_B, Text = "30", TextSize = 86, TextColor3 = HI, TextXAlignment = Enum.TextXAlignment.Right })
		self.AKick = new("UIScale", {}, self.AMag)
		self.ARes = txt(r, { Position = O(224, 98), Size = O(120, 34), Text = "/ 90", TextSize = 32, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left })
		self.ARng = txt(r, { Position = O(260, 112), Size = O(116, 18), Text = "RNG ---", TextSize = 14, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Right })
		self.ABar, self.ATrack = bar(r, 24, 146, 352, 6, PRI, 0.5)
		self.AState = txt(r, { Position = O(24, 120), Size = O(200, 18), FontFace = F_B, Text = "", TextSize = 15, TextColor3 = AMBER, TextXAlignment = Enum.TextXAlignment.Left })
	end

	-- abilities: badges with 12-segment charge rings ─────────────────────────────────
	do
		local _, r = self:_panel("Abilities", "C", 810, 850, 480, 230, 0, -8, 0.5)
		self.Badges = {}
		local ICON = { PhaseDash = KIT.IconDash2 or KIT.IconDash, HighJump = KIT.IconJump2 or KIT.IconJump, PulseScan = KIT.IconScan2 or KIT.IconPulse, Grapple = KIT.IconJump2 or KIT.IconJump }
		local NAME = { PhaseDash = "PHASE DASH", HighJump = "HIGH JUMP", PulseScan = "PULSE SCAN", Grapple = "GRAPPLE", Grenade = "FRAG" }
		for i, name in ctx.AbilityConfig.Order do
			local A = ctx.AbilityConfig.Abilities[name]
			local cx = if #ctx.AbilityConfig.Order == 1 then 240 else 90 + (i - 1) * 150 -- a single ability sits in the middle of the panel
			local holder = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(cx, 64), Size = O(124, 124), BackgroundTransparency = 1 }, r)
			local pop = new("UIScale", {}, holder)
			local disc = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(96, 96), BackgroundColor3 = BG, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 2 }, holder)
			new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, disc)
			local ds = new("UIStroke", { Color = DEEP, Thickness = 2, Transparency = 0.1 }, disc)
			local segs = {}
			for k = 1, 12 do
				local a = rad(-90 + (k - 0.5) * 30)
				segs[k] = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(62 + math.cos(a) * 56, 62 + math.sin(a) * 56), Size = O(24, 5), Rotation = math.deg(a) + 90, BackgroundColor3 = PRI, BorderSizePixel = 0, ZIndex = 3 }, holder)
			end
			local icon = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(50, 50), BackgroundTransparency = 1, Image = ICON[name] or "", ImageColor3 = HI, ZIndex = 4 }, holder)
			-- the grenade has no sprite in the kit: a small live view of the real model, lit in the HUD colour
			local gfolder = name == "Grenade" and game:GetService("ReplicatedStorage").Vantage:FindFirstChild("Grenade")
			local gmodel = gfolder and gfolder:FindFirstChild("FragModel")
			if gmodel then
				local vp = new("ViewportFrame", { Name = "GrenadeView", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(64, 64), BackgroundTransparency = 1, Ambient = HI, LightColor = HI, LightDirection = Vector3.new(-1, -1, -1), ZIndex = 4 }, holder)
				local m = gmodel:Clone()
				for _, p in m:GetDescendants() do
					if p:IsA("BasePart") then
						p.Anchored = true
					end
				end
				m:PivotTo(CFrame.new() * CFrame.Angles(0, math.rad(30), math.rad(-12)))
				m.Parent = vp
				local vcam = Instance.new("Camera")
				vcam.FieldOfView = 30
				local _, gsz = m:GetBoundingBox()
				vcam.CFrame = CFrame.lookAt(Vector3.new(0, 0.03, gsz.Y * 2.2), Vector3.new(0, 0.01, 0)) -- framed to the model's height
				vcam.Parent = vp
				vp.CurrentCamera = vcam
				icon.Image = ""
			end
			local sweep = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(-20, 62), Size = O(14, 96), BackgroundColor3 = HI, BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false, ZIndex = 5 }, holder)
			local ring = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(40, 40), BackgroundTransparency = 1, Image = KIT.Ring, ImageColor3 = HI, ImageTransparency = 1, ZIndex = 5 }, holder)
			txt(r, { AnchorPoint = V2(0.5, 0), Position = O(cx, 130), Size = O(140, 18), FontFace = F_B, Text = A and A.KeyLabel or "", TextSize = 16 })
			txt(r, { AnchorPoint = V2(0.5, 0), Position = O(cx, 150), Size = O(150, 20), FontFace = F_B, Text = NAME[name] or name, TextSize = 17 })
			local chip = new("Frame", { AnchorPoint = V2(0.5, 0), Position = O(cx, 174), Size = O(96, 26), BackgroundColor3 = GREEN, BackgroundTransparency = 0.78, BorderSizePixel = 0 }, r)
			new("UICorner", { CornerRadius = UDim.new(0, 4) }, chip)
			local state = txt(r, { AnchorPoint = V2(0.5, 0), Position = O(cx, 176), Size = O(140, 22), FontFace = F_B, Text = "READY", TextSize = 18, TextColor3 = GREEN })
			self.Badges[name] = { Holder = holder, Pop = pop, Disc = disc, Stroke = ds, Segs = segs, Icon = icon, Sweep = sweep, Ring = ring, Chip = chip, State = state }
		end
	end

	-- radar: a disc tilted back like a hologram table ─────────────────────────────────
	do
		local pr, r = self:_panel("Radar", "L", 372, 830, 400, 400, 3, -48, 0.5)
		pr.Base = 0.9
		local R = 190
		local disc = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(200, 200), Size = O(2 * R, 2 * R), BackgroundColor3 = BG, BackgroundTransparency = 0.4, BorderSizePixel = 0 }, r)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
		new("UIStroke", { Color = PRI, Thickness = 3 }, disc)
		for _, k in { 1.07, 0.66, 0.33 } do
			local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(200, 200), Size = O(2 * R * k, 2 * R * k), BackgroundTransparency = 1, ZIndex = 2 }, r)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
			new("UIStroke", { Color = if k > 1 then DEEP else PRI, Thickness = if k > 1 then 2 else 1.5, Transparency = if k > 1 then 0.2 else 0.55 }, ring)
		end
		for k = 0, 23 do
			local a = rad(k * 15)
			local long = k % 6 == 0
			line(r, 200 + math.sin(a) * (R - (long and 16 or 8)), 200 - math.cos(a) * (R - (long and 16 or 8)), 200 + math.sin(a) * R, 200 - math.cos(a) * R, if long then HI else PRI, long and 3 or 2, long and 0 or 0.4, 3)
		end
		for _, s in { -1, 1 } do
			local a = rad(s * 35)
			line(r, 200, 200, 200 + math.sin(a) * R * 0.9, 200 - math.cos(a) * R * 0.9, PRI, 1, 0.65, 2)
		end
		self.RSweep = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = O(200, 200), Size = O(2 * R, 2 * R), BackgroundTransparency = 1, Image = KIT.RadarSweep, ImageColor3 = PRI, ImageTransparency = 0.35, ZIndex = 3 }, r)
		self.RPulse = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(200, 200), Size = O(0, 0), BackgroundTransparency = 1, ZIndex = 4 }, r)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.RPulse)
		self.RPulseStroke = new("UIStroke", { Color = HI, Thickness = 4, Transparency = 1 }, self.RPulse)
		local me = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(200, 200), Size = O(30, 30), BackgroundTransparency = 1, ZIndex = 6 }, r)
		line(me, 15, 2, 4, 28, HI, 4, 0, 6)
		line(me, 15, 2, 26, 28, HI, 4, 0, 6)
		line(me, 4, 28, 15, 21, HI, 3, 0, 6)
		line(me, 26, 28, 15, 21, HI, 3, 0, 6)
		self.RContacts = {}
		for i = 1, 14 do
			local d = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(14, 14), Rotation = 45, BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false, ZIndex = 6 }, r)
			new("UIStroke", { Color = BG, Thickness = 1, Transparency = 0.3 }, d)
			self.RContacts[i] = d
		end
		self.RadarR = R
		-- the scan state reads off the disc, upright, beside it
		local _, s = self:_panel("ScanTag", "L", 606, 860, 130, 70, 4, 0, 0.5)
		self.ScanTag1 = txt(s, { Position = O(0, 4), Size = O(130, 30), FontFace = F_B, Text = if ctx.AbilityConfig.Abilities.PulseScan then "SCAN" else "HOOK", TextSize = 26, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Left })
		self.ScanTag2 = txt(s, { Position = O(0, 34), Size = O(130, 30), FontFace = F_B, Text = "READY", TextSize = 26, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Left })
	end

	-- compass: wide strip under the brow, tilted back so it follows the curve ────────
	do
		local _, r = self:_panel("Compass", "C", 960, 214, 700, 104, 0, 8, 0.72)
		self.CTicks = {}
		local CARD = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
		for k = 0, 71 do
			local deg = k * 5
			local card = CARD[deg]
			local t = new("Frame", { AnchorPoint = V2(0.5, 1), Size = O(if card then 3 else 2, if card then 18 elseif deg % 15 == 0 then 11 else 6), BackgroundColor3 = if card then HI else PRI, BorderSizePixel = 0, ZIndex = 2 }, r)
			local lab
			if card then
				lab = txt(r, { AnchorPoint = V2(0.5, 0), Size = O(50, 30), FontFace = F_B, Text = card, TextSize = if deg % 90 == 0 then 30 else 24, TextColor3 = HI, ZIndex = 2 })
			elseif deg % 15 == 0 then
				lab = txt(r, { AnchorPoint = V2(0.5, 0), Size = O(50, 18), Text = string.format("%03d", deg), TextSize = 15, TextColor3 = GREY, ZIndex = 2 })
			end
			self.CTicks[k + 1] = { F = t, L = lab, Deg = deg }
		end
		self.CBase = {}
		for i = 1, 60 do
			self.CBase[i] = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(16, 2), BackgroundColor3 = DEEP, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, r)
		end
		self.CMarkers = {}
		for i = 1, 10 do
			self.CMarkers[i] = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(13, 13), Rotation = 45, BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, r)
		end
		-- pointer + heading bracket
		local pt = new("Frame", { AnchorPoint = V2(0.5, 0), Position = O(350, 0), Size = O(22, 14), BackgroundTransparency = 1, ZIndex = 4 }, r)
		line(pt, 0, 1, 22, 1, HI, 3, 0, 4)
		line(pt, 0, 1, 11, 13, HI, 3, 0, 4)
		line(pt, 22, 1, 11, 13, HI, 3, 0, 4)
		local _, h = self:_panel("Heading", "C", 960, 258, 130, 40, 0, 5, 0.7)
		local bx = { { 16, 2 }, { 114, 2 }, { 128, 20 }, { 114, 38 }, { 16, 38 }, { 2, 20 } }
		rect(h, 16, 3, 98, 34, DEEP, 0.7, 0)
		for i = 1, 6 do
			local a, b = bx[i], bx[i % 6 + 1]
			line(h, a[1], a[2], b[1], b[2], PRI, 2, 0, 2)
		end
		self.CHeading = txt(h, { Position = O(0, 3), Size = O(130, 34), FontFace = F_B, Text = "000", TextSize = 28, TextColor3 = HI })
	end

	-- centre: reticle field (2D, exactly on the crosshair) ──────────────────────────
	do
		local g = ctx.Group
		local field = new("Frame", { Name = "HoloReticleField", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(600 / 1920, 600 / 1080), BackgroundTransparency = 1, ZIndex = 1 }, g)
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, field)
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = KIT.Ring, ImageColor3 = DEEP, ImageTransparency = 0.72 }, field)
		for _, s in { -1, 1 } do
			new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5 + s * 0.2, 0.5), Size = UDim2.fromScale(0.09, 0.2), BackgroundTransparency = 1, Image = KIT.RingHalf, ImageColor3 = PRI, ImageTransparency = 0.15, Rotation = if s > 0 then 0 else 180 }, field)
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5 + s * 0.37, 0.5), Size = UDim2.new(0.22, 0, 0, 1), BackgroundColor3 = PRI, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, field)
		end
		self.Field = field
	end
end

-- ─── weapon data ──────────────────────────────────────────────────────────────────────
local function weaponKey(w)
	local id = tostring(w.Asset or w.Id or "")
	if WIRE[id] then
		return id
	end
	local d = string.upper(tostring(w.DisplayName or ""))
	for key, prefix in { Vanguard = "VX%-01", Sentinel = "BR%-07", Longshot = "SR%-88", Breacher = "SG%-12", Spectre = "PX%-9", Arc = "ER%-04" } do
		if d:find(prefix) then
			return key
		end
	end
	if w.Kind == "Melee" then
		return "Knife"
	end
	return nil
end
function Holo:_setWeapon(w)
	local key = weaponKey(w)
	self.WName.Text = string.upper(tostring(w.DisplayName or key or ""))
	self.WClass.Text = tostring(w.Class or "")
	local img = key and KIT[WIRE[key]] or ""
	self.Wire.Image, self.WireGlow.Image = img, img
	local rows
	if w.Kind == "Melee" then
		local P, S = w.Primary or {}, w.Secondary or {}
		rows = {
			{ "SLASH", tostring(P.Damage or "-"), (P.Damage or 0) / 150 },
			{ "HEAVY", tostring(S.Damage or "-"), (S.Damage or 0) / 150 },
			{ "BACKSTAB", tostring(S.BackstabDamage or "-"), (S.BackstabDamage or 0) / 150 },
			{ "REACH", string.format("%.1f", P.Range or 0), (P.Range or 0) / 10 },
			{ "SWING", string.format("%.2f S", P.Cooldown or 0), 1 - math.clamp((P.Cooldown or 0.5) / 1.2, 0, 1) },
		}
	elseif type(w.Heat) == "table" then
		local H = w.Heat
		rows = {
			{ "DAMAGE", tostring(w.Damage or "-"), (w.Damage or 0) / 100 },
			{ "RATE", string.format("%d RPM", w.RPM or 0), (w.RPM or 0) / 900 },
			{ "HEAT / SHOT", string.format("%d %%", math.floor((H.PerShot or 0) * 100 + 0.5)), (H.PerShot or 0) * 8 },
			{ "COOL RATE", string.format("%d %%/S", math.floor((H.CoolRate or 0) * 100 + 0.5)), H.CoolRate or 0 },
			{ "OVERHEAT LOCK", string.format("%.1f S", H.OverheatLock or 0), (H.OverheatLock or 0) / 3 },
		}
	else
		rows = {
			{ "DAMAGE", tostring(w.Damage or "-"), (w.Damage or 0) / 100 },
			{ "RATE", string.format("%d RPM", w.RPM or 0), (w.RPM or 0) / 900 },
			{ "FALLOFF", string.format("%d - %d", w.FalloffStart or 0, w.FalloffEnd or 0), math.clamp((w.FalloffEnd or 0) / 1200, 0, 1) },
			{ "RELOAD", string.format("%.1f S", w.ReloadTime or 0), 1 - math.clamp((w.ReloadTime or 0) / 4, 0, 1) },
			{ "HEADSHOT", string.format("x%.2g", w.HeadshotMultiplier or 1), ((w.HeadshotMultiplier or 1) - 1) / 1.5 },
		}
	end
	for i, s in self.Stats do
		local row = rows[i]
		s.K.Text, s.V.Text = row[1], row[2]
		s.B.Size = UDim2.fromScale(0, 1)
		tween(s.B, 0.45, { Size = UDim2.fromScale(math.clamp(row[3], 0.03, 1), 1) }, Enum.EasingStyle.Quint, nil, 0.05 * i)
	end
	-- switch: the old hologram collapses, the new one draws in under a scan line
	self.Wire.ImageTransparency, self.WireGlow.ImageTransparency = 1, 1
	tween(self.Wire, 0.4, { ImageTransparency = 0.05 }, nil, nil, 0.1)
	tween(self.WireGlow, 0.4, { ImageTransparency = 0.45 }, nil, nil, 0.1)
	self.WireScan.Visible = true
	self.WireScan.Position = O(0, 40)
	tween(self.WireScan, 0.5, { Position = O(0, 280) }, Enum.EasingStyle.Sine)
	task.delay(0.52, function()
		self.WireScan.Visible = false
	end)
end

-- avatar hologram: a clone of the character whose parts copy the live pose each frame
function Holo:_rebuildAvatar()
	local ch = self.Player.Character
	if self.AvatarModel then
		self.AvatarModel:Destroy()
		self.AvatarModel = nil
	end
	self.AvatarPairs = {}
	if not ch or not ch:FindFirstChild("HumanoidRootPart") then
		return
	end
	local was = ch.Archivable
	ch.Archivable = true
	local ok, clone = pcall(function()
		return ch:Clone()
	end)
	ch.Archivable = was
	if not ok or not clone then
		return
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Humanoid") or d:IsA("Tool") or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Attachment") or d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Material = Enum.Material.SmoothPlastic
			d.Color = C(90, 190, 255)
			d.Transparency = if d.Transparency >= 0.99 then 1 else 0.5
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
			local path, node = {}, d
			while node and node ~= clone do
				table.insert(path, 1, node.Name)
				node = node.Parent
			end
			local src = ch
			for _, nm in path do
				src = src and src:FindFirstChild(nm)
			end
			if src and src:IsA("BasePart") then
				table.insert(self.AvatarPairs, { d, src })
			end
		end
	end
	clone.Parent = self.AvatarVPF
	self.AvatarModel = clone
	self.AvatarRoot = ch:FindFirstChild("HumanoidRootPart")
end

-- ─── visibility (boot / shutdown) ────────────────────────────────────────────────────
local ORDER = { "Compass", "Heading", "Brand", "Suit", "Match", "Weapon", "Radar", "ScanTag", "Abilities", "Ammo" }
function Holo:SetShown(on: boolean, instant: boolean?)
	self.Shown = on
	-- boot / shutdown owns the panels: any shield-down eject ends here (the visor re-applies it)
	self.Ejected, self.Ghosting = false, false
	self.EjectTok = (self.EjectTok or 0) + 1
	for _, p in self.Panels do
		p.GX = 0
	end
	self.Token = (self.Token or 0) + 1
	local tok = self.Token
	for i, name in ORDER do
		local p = self.Panels[name]
		local delay = if instant then 0 else (if on then 0.06 * i else 0.03 * (#ORDER - i))
		task.delay(delay, function()
			if tok ~= self.Token then
				return
			end
			if on then
				-- draw in: the panel grows out of its centre and the glass fades up
				p.Gui.Enabled = true
				p.Pop = 0.82
				p.Root.GroupTransparency = 1
				tween(p.Root, if instant then 0 else 0.35, { GroupTransparency = 0 })
			else
				tween(p.Root, if instant then 0 else 0.18, { GroupTransparency = 1 })
				task.delay(if instant then 0 else 0.2, function()
					if tok == self.Token then
						p.Gui.Enabled = false
					end
				end)
			end
		end)
	end
	if self.AvatarVPF then
		if on then
			self:_rebuildAvatar()
			self.AvatarVPF.ImageTransparency = 1
			tween(self.AvatarVPF, if instant then 0 else 0.6, { ImageTransparency = 0.3 }, nil, nil, if instant then 0 else 0.35)
		else
			self.AvatarVPF.ImageTransparency = 1
		end
	end
	for _, c in self.ShieldCells or {} do
		c.Visible = on
	end
	for _, c in self.ScanCells or {} do
		c.Visible = on
	end
	if self.Field then
		self.Field.Visible = on
	end
end

-- ─── shield down: the visor sheds power ─────────────────────────────────────────────────────────────────
-- Panels that stay up while the shield is down (the suit panel carries shield / health / OFFLINE).
Holo.EJECT_KEEP = { Suit = true }
function Holo:SetEjected(on: boolean, reboot: boolean?)
	if (self.Ejected == true) == on then
		return
	end
	self.Ejected = on
	self.EjectTok = (self.EjectTok or 0) + 1
	local tok = self.EjectTok
	local i = 0
	for _, name in ORDER do
		local p = self.Panels[name]
		if not p or Holo.EJECT_KEEP[name] then
			continue
		end
		i += 1
		p.GX = 0
		if on then
			-- stutter, jump sideways, drop out (staggered across the visor)
			task.delay((i - 1) * 0.035, function()
				for k = 1, 4 do
					if tok ~= self.EjectTok then
						return
					end
					p.Root.GroupTransparency = if k % 2 == 0 then 0.15 else 0.85
					p.GX = math.random(-16, 16)
					task.wait(0.03 + math.random() * 0.03)
				end
				if tok ~= self.EjectTok then
					return
				end
				p.GX = 0
				p.Root.GroupTransparency = 1
			end)
		elseif self.Shown then
			if reboot then
				task.delay(0.04 + (i - 1) * 0.05, function()
					if tok ~= self.EjectTok then
						return
					end
					p.Pop = 0.86
					p.Root.GroupTransparency = 1
					tween(p.Root, 0.3, { GroupTransparency = 0 })
				end)
			else
				p.Root.GroupTransparency = 0
			end
		end
	end
	self.EjectDoneAt = os.clock() + i * 0.035 + 0.3
	self.NextGhost = self.EjectDoneAt + 0.6
end

function Holo:AbilityUsed(name: string)
	local b = self.Badges and self.Badges[name]
	if not b then
		return
	end
	b.Pop.Scale = 1.18
	tween(b.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	if name == "PhaseDash" then
		b.Sweep.Visible = true
		b.Sweep.Position = O(-10, 62)
		tween(b.Sweep, 0.24, { Position = O(134, 62) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.26, function()
			b.Sweep.Visible = false
		end)
	elseif name == "HighJump" then
		b.Icon.Position = UDim2.new(0.5, 0, 0.5, 14)
		tween(b.Icon, 0.45, { Position = UDim2.new(0.5, 0, 0.5, 0) }, Enum.EasingStyle.Bounce)
	else
		b.Ring.Size = O(30, 30)
		b.Ring.ImageTransparency = 0
		tween(b.Ring, 0.7, { Size = O(220, 220), ImageTransparency = 1 })
		self.RadarBoost = 1
		self.RPulse.Size = O(10, 10)
		self.RPulseStroke.Transparency = 0
		tween(self.RPulse, 1.0, { Size = O(2 * self.RadarR, 2 * self.RadarR) })
		tween(self.RPulseStroke, 1.0, { Transparency = 1 }, nil, Enum.EasingDirection.In)
	end
end

-- ─── per frame ───────────────────────────────────────────────────────────────────────
function Holo:_place(dt)
	local cam = Workspace.CurrentCamera
	local c = cam.CFrame
	self.LagCF = self.LagCF:Lerp(c, math.min(1, dt * 14))
	local vp = cam.ViewportSize
	if vp.Y < 10 then
		return
	end
	local unit = 2 * DEPTH * math.tan(rad(cam.FieldOfView) / 2) / 1080
	local aw = 1080 * vp.X / vp.Y
	if vp ~= self.LastVP then -- (FOV changes when aiming keep the same screen size: no refit)
		self.LastVP = vp
		for _, p in self.Panels do
			p.Fit, p.NX, p.NY, p.FitDone = 1, 0, 0, false
		end
	end
	-- narrower than 16:9: panels shrink and tuck toward their own edge so the centre stays clear
	local fit = math.clamp(aw / 1920, 0.6, 1)
	local M = 80 -- the frame band
	for _, p in self.Panels do
		if not p.Gui.Enabled then
			continue
		end
		local px = if p.Side == "L" then M + (p.CX - M) * fit elseif p.Side == "R" then aw - M - (1920 - M - p.CX) * fit else aw / 2 + (p.CX - 960) * fit
		px += p.NX + (p.GX or 0)
		local X, Y = (px - aw / 2) * unit, (540 - p.CY - p.NY) * unit
		p.Pop += (1 - p.Pop) * math.min(1, dt * 9)
		local s = unit * p.Pop * fit * p.Fit * (p.Base or 1)
		p.Part.Size = Vector3.new(p.W * s, p.H * s, 0.001)
		p.Gui.PixelsPerStud = 1 / s
		local rot = c.Rotation:Lerp(self.LagCF.Rotation, p.Lag)
		p.Part.CFrame = CFrame.new(c.Position) * rot * CFrame.new(X, Y, -DEPTH) * CFrame.Angles(rad(p.Pitch), rad(p.Yaw), 0)
		-- fit check (un-lagged pose, full size): any corner over the frame -> nudge toward the centre + shrink a touch
		if not p.FitDone and p.Pop > 0.995 then
			local pose = CFrame.new(c.Position) * c.Rotation * CFrame.new(X, Y, -DEPTH) * CFrame.Angles(rad(p.Pitch), rad(p.Yaw), 0)
			local hx, hy = p.W * s / 2, p.H * s / 2
			local out = false
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, k in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
				local v = cam:WorldToViewportPoint(pose * Vector3.new(k[1] * hx, k[2] * hy, 0))
				x0, y0, x1, y1 = math.min(x0, v.X), math.min(y0, v.Y), math.max(x1, v.X), math.max(y1, v.Y)
				if not insideGlass(Vector2.new(v.X * 1920 / vp.X, v.Y * 1080 / vp.Y)) then
					out = true
				end
			end
			p.Box = { x0, y0, x1, y1 }
			-- the big panels (suit, weapon, match, brand) own their space; everything else gives way to them:
			-- the compass / heading / radar / abilities / ammo shrink until clear, the scan tag slides off the radar
			local ANCHOR = { Suit = true, Weapon = true, Match = true, Brand = true }
			local clash, settled = false, true
			if not ANCHOR[p.Part.Name] then
				for name, o in self.Panels do
					local isAnchor = ANCHOR[name] or (p.Part.Name == "ScanTag" and name == "Radar")
						or (p.Part.Name == "Abilities" and (name == "Radar" or name == "ScanTag"))
					if isAnchor and o ~= p and o.Gui.Enabled then
						local b = o.Box
						if not (b and o.FitDone) then
							settled = false
						elseif x0 < b[3] + 12 and x1 > b[1] - 12 and y0 < b[4] + 10 and y1 > b[2] - 10 then
							clash = true
						end
					end
				end
			end
			if not settled and not out then
				-- wait for the anchors to finish fitting first
			elseif clash and not out and p.Fit > 0.45 then
				if p.Part.Name == "ScanTag" or (p.Part.Name == "Abilities" and p.NX < 260) then
					p.NX += 4 -- slide right, clear of the radar
				elseif p.Part.Name == "Radar" and p.NX < 200 then
					p.NX += 5 -- the radar slides along the chin before it shrinks
					p.NY += 1 -- (and down, away from the suit panel)
				else
					p.Fit *= 0.98
				end
			elseif out and p.Fit > 0.7 then
				local dirX = if p.Side == "L" then 1 elseif p.Side == "R" then -1 else 0
				local dirY = if p.CY < 540 then 1 else -1 -- NY > 0 moves down (Y = 540 - CY - NY)
				local low = p.CY > 700 and p.Side ~= "C"
				p.NX += dirX * (if low then 6 else 4)
				p.NY += dirY * (if low then 1 else 3)
				p.Fit *= 0.99
			else
				p.FitDone = true
			end
		end
	end
end
function Holo:Refit()
	for _, p in self.Panels do
		p.Fit, p.NX, p.NY, p.FitDone = 1, 0, 0, false
	end
end

function Holo:Step(dt: number)
	if not self.Shown then
		return
	end
	self.T += dt
	local now = os.clock()
	if self.Ejected and now >= (self.EjectDoneAt or 0) then
		-- held down: the panels stay dark, a one-frame ghost of a few of them flickers through now and then
		local ghost = now >= (self.NextGhost or 0)
		if ghost then
			self.NextGhost = now + 0.7 + math.random() * 1.1
		end
		if ghost or self.Ghosting then
			self.Ghosting = ghost
			for name, p in self.Panels do
				if not Holo.EJECT_KEEP[name] then
					local on = ghost and math.random() < 0.4
					p.Root.GroupTransparency = if on then 0.55 else 1
					p.GX = if on then math.random(-12, 12) else 0
				end
			end
		end
	end
	self:_place(dt)
	local plr = self.Player
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	local Feed = self.Feed
	-- ADS (2026-11-14): the centre reticle field steps aside while aiming (the weapon's sight takes over)
	if self.Field then
		self.Field.Visible = (Feed.ADS or 0) < 0.35
	end

	-- suit ─────────────────────────────────────────────────────────────────────────
	self.SuitName.Text = "SUIT // " .. string.upper(plr.Name)
	local sf, hf = 0, 0
	if hum and ch then
		local sh, msh = ch:GetAttribute("Shield") or 0, ch:GetAttribute("MaxShield") or 0
		sf = if msh > 0 then math.clamp(sh / msh, 0, 1) else 0
		hf = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		self.ShieldNum.Text = tostring(math.floor(sf * 100 + 0.5))
		self.ShieldNum.TextColor3 = if sf <= 0 then RED elseif sf < 0.3 then AMBER else HI
		self.ShieldBar.Size = UDim2.fromScale(sf, 1)
		self.ShieldBar.BackgroundColor3 = if sf < 0.3 then AMBER else PRI
		self.HealthNum.Text = tostring(math.floor(hf * 100 + 0.5))
		self.HealthBar.Size = UDim2.fromScale(hf, 1)
		self.HealthBar.BackgroundColor3 = if hf < 0.35 then RED else PRI
		local regen = if sh <= 0 then "OFFLINE" elseif sf < 1 and (self.LastShield or 0) < sh then "CHARGING" elseif sf < 1 then "DELAYED" else "ONLINE"
		self.LastShield = sh
		self.Rows["SHIELD REGEN"].Text = regen
		self.Rows["SHIELD REGEN"].TextColor3 = if regen == "OFFLINE" then RED elseif regen == "ONLINE" then PRI else AMBER
		local st = hum:GetState()
		local spd = if root then root.AssemblyLinearVelocity.Magnitude else 0
		self.Rows.STANCE.Text = if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then "AIRBORNE" elseif spd > 18 then "SPRINTING" elseif spd > 1 then "MOVING" else "STANDING"
		if root then
			local v = root.AssemblyLinearVelocity
			self.Rows.SPEED.Text = string.format("%04.1f M/S", Vector3.new(v.X, 0, v.Z).Magnitude * 0.28)
			self.Rows.ALTITUDE.Text = string.format("%03d M", math.floor(root.Position.Y * 0.28 + 0.5))
		end
		for i, cell in self.ShieldCells do
			cell.BackgroundColor3 = if sf < 0.3 then AMBER else PRI
			cell.BackgroundTransparency = if sf >= (i - 0.5) / 10 then 0.05 else 0.8
		end
	end
	-- integrity trace (sampled every 20/48 s)
	if now >= self.HistAt then
		self.HistAt = now + 20 / 48
		table.remove(self.History, 1)
		table.insert(self.History, (sf + hf) / 2)
		for i, b in self.Trace do
			local v = self.History[i]
			b.Size = O(3, math.max(2, 40 * v))
			b.BackgroundColor3 = if v < 0.35 then RED elseif v < 0.6 then AMBER else PRI
		end
	end
	-- avatar: copy the live pose relative to the root, slow turn, travelling scan sweep
	if self.AvatarModel and self.AvatarRoot and self.AvatarRoot.Parent then
		local inv = self.AvatarRoot.CFrame:Inverse()
		local turn = CFrame.Angles(0, rad(200 + math.sin(self.T * 0.4) * 25), 0)
		for _, pair in self.AvatarPairs do
			if pair[2].Parent then
				pair[1].CFrame = turn * (inv * pair[2].CFrame)
			end
		end
		self.AvatarCam.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, 15), Vector3.new(0, -0.4, 0))
	elseif root and now >= (self.AvatarRetry or 0) then
		self.AvatarRetry = now + 1
		self:_rebuildAvatar()
	end
	self.AvatarSweep.Position = O(0, (self.T * 90) % 460 - 20)

	-- weapon panel ─────────────────────────────────────────────────────────────────
	local w = Feed.Weapon
	if w and w ~= self.Weapon then
		self.Weapon = w
		self:_setWeapon(w)
	end
	self.WireT += dt
	if self.WireT > 0.16 then
		self.WireT = 0
		self.WireFrame = (self.WireFrame + 1) % 14 -- ping-pong over 8 frames
		local f = if self.WireFrame < 8 then self.WireFrame else 14 - self.WireFrame
		local off = Vector2.new((f % 2) * 512, math.floor(f / 2) * 256)
		self.Wire.ImageRectOffset, self.WireGlow.ImageRectOffset = off, off
	end

	-- ammo panel ───────────────────────────────────────────────────────────────────
	if w then
		self.AName.Text = string.upper(tostring(w.DisplayName or ""))
		if w.Kind == "Melee" then
			self.AMag.Text = "MELEE"
			self.AMag.TextSize = 50
			self.AMag.TextColor3 = HI
			self.ARes.Text = ""
			self.AMode.Text = "MELEE"
			self.ASub.Text = "SLASH  ·  HEAVY  ·  BACKSTAB"
			self.ATrack.Visible = false
			self.AState.Text = ""
		elseif Feed.Heat then
			local heat = Feed.Heat
			self.AMag.TextSize = 86
			self.AMag.Text = tostring(math.floor(heat * 100 + 0.5))
			self.AMag.TextColor3 = if Feed.Locked then RED elseif heat > 0.75 then AMBER else HI
			self.ARes.Text = "% HEAT"
			self.AMode.Text = "ENERGY"
			self.ASub.Text = string.format("%s  ·  %d RPM", tostring(w.Class or ""), w.RPM or 0)
			self.ATrack.Visible = true
			self.ABar.Size = UDim2.fromScale(heat, 1)
			self.ABar.BackgroundColor3 = if Feed.Locked then RED elseif heat > 0.75 then AMBER else PRI
			self.AState.Text = if Feed.Locked then "VENTING" elseif heat > 0.75 then "HEAT HIGH" else ""
			self.AState.TextColor3 = if Feed.Locked then RED else AMBER
		else
			local size, mag = Feed.Size or 0, Feed.Mag or 0
			local low = size > 0 and mag <= math.floor(size * 0.25)
			if self.LastMag and mag < self.LastMag and not Feed.Reload then
				self.AKick.Scale = 1.1
				tween(self.AKick, 0.14, { Scale = 1 })
			end
			if self.WasReload and not Feed.Reload then
				self.ReadyUntil = now + 0.7
				self.AKick.Scale = 1.15
				tween(self.AKick, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			self.LastMag, self.WasReload = mag, Feed.Reload
			self.AMag.TextSize = 86
			self.AMag.Text = tostring(mag)
			self.AMag.TextColor3 = if mag == 0 then RED elseif low then AMBER else HI
			self.ARes.Text = "/ " .. tostring(Feed.Reserve or 0)
			local trig = w.Trigger
			self.AMode.Text = if type(trig) == "string" then string.upper(trig) else ""
			self.ASub.Text = string.format("%d ROUND MAG  ·  %d RPM", size, w.RPM or 0)
			self.ATrack.Visible = true
			if Feed.Reload then
				self.ABar.Size = UDim2.fromScale(math.clamp(Feed.Reload, 0, 1), 1)
				self.ABar.BackgroundColor3 = HI
				self.AState.Text = "RELOADING"
				self.AState.TextColor3 = HI
				self.AState.TextTransparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(now * 10))
			else
				self.ABar.Size = UDim2.fromScale(if size > 0 then mag / size else 0, 1)
				self.ABar.BackgroundColor3 = if mag == 0 then RED elseif low then AMBER else PRI
				self.AState.TextTransparency = 0
				if now < (self.ReadyUntil or 0) then
					self.AState.Text, self.AState.TextColor3 = "READY", GREEN
				elseif mag == 0 then
					self.AState.Text, self.AState.TextColor3 = "EMPTY  //  RELOAD", RED
				elseif low then
					self.AState.Text, self.AState.TextColor3 = "LOW AMMO", AMBER
				else
					self.AState.Text = ""
				end
			end
		end
	end
	if now >= (self.RangeAt or 0) then
		self.RangeAt = now + 0.1
		local cam = Workspace.CurrentCamera
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local list = { cam, self.Folder }
		if ch then
			table.insert(list, ch)
		end
		local fx = Workspace:FindFirstChild("VantageWeaponFX")
		if fx then
			table.insert(list, fx)
		end
		rp.FilterDescendantsInstances = list
		local res = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 600, rp)
		self.ARng.Text = if res then string.format("RNG %03d M", math.floor(res.Distance * 0.28 + 0.5)) else "RNG ---"
	end

	-- match panel ──────────────────────────────────────────────────────────────────
	local V = ReplicatedStorage:FindFirstChild("Vantage")
	local match = V and V:FindFirstChild("Match")
	if match then
		local bs, rs, lim = match:GetAttribute("BlueScore") or 0, match:GetAttribute("RedScore") or 0, match:GetAttribute("ScoreLimit") or 50
		self.MBlue.Text, self.MRed.Text = string.format("%02d", bs), string.format("%02d", rs)
		self.MBlueBar.Size = UDim2.fromScale(math.clamp(bs / math.max(1, lim), 0, 1), 1)
		self.MRedBar.Size = UDim2.fromScale(math.clamp(rs / math.max(1, lim), 0, 1), 1)
		self.MLimit.Text = "FIRST TO " .. tostring(lim)
	end
	if Feed.Timer then
		self.MTime.Text = Feed.Timer
	end
	if self.ctx.LastKill then
		self.MFeed.Text = self.ctx.LastKill() or ""
	end

	-- abilities ────────────────────────────────────────────────────────────────────
	for name, b in self.Badges do
		local state, left, cd = self.ctx.Ability(name)
		local frac = if left > 0 then 1 - left / math.max(cd, 0.01) else 1
		local ready = state == "Ready"
		local live = state == "Active" or state == "Activating"
		local col = if ready then GREEN else PRI
		for k, seg in b.Segs do
			local lit = k / 12 <= frac + 1e-6
			seg.BackgroundColor3 = if lit then col else GREY
			seg.BackgroundTransparency = if lit then 0 else 0.75
		end
		b.Icon.ImageColor3 = if ready or live then HI else GREY
		b.Icon.ImageTransparency = if ready or live then 0 else 0.35
		b.Stroke.Color = if ready then GREEN else DEEP
		b.Disc.BackgroundTransparency = if live then 0.05 else 0.35
		b.Chip.Visible = ready
		if ready then
			b.State.Text, b.State.TextColor3 = "READY", GREEN
		elseif live then
			b.State.Text, b.State.TextColor3 = "ACTIVE", HI
		else
			b.State.Text = if left < 1 then string.format("%.1fs", left) else string.format("%ds", math.ceil(left))
			b.State.TextColor3 = PRI
		end
	end
	-- Pulse Scan charge cells + the radar's scan tag
	do
		local state, left, cd = self.ctx.Ability(if self.ctx.AbilityConfig.Abilities.PulseScan then "PulseScan" else self.ctx.AbilityConfig.Order[1]) -- the radar-side tag follows the grapple now
		local frac = if left > 0 then 1 - left / math.max(cd, 0.01) else 1
		for i, cell in self.ScanCells do
			cell.BackgroundColor3 = if frac >= 1 then GREEN else PRI
			cell.BackgroundTransparency = if frac >= i / 12 - 1e-6 then 0.05 else 0.8
		end
		local active = state == "Active" or state == "Activating" or (self.RadarBoost or 0) > 0.4
		self.ScanTag2.Text = if active then "ACTIVE" elseif frac >= 1 then "READY" else string.format("%ds", math.ceil(left))
		local c = if active or frac >= 1 then GREEN else GREY
		self.ScanTag1.TextColor3, self.ScanTag2.TextColor3 = c, c
	end

	-- radar ────────────────────────────────────────────────────────────────────────
	self.RadarBoost = math.max(0, (self.RadarBoost or 0) - dt / 1.6)
	self.RSweepA = ((self.RSweepA or 0) + dt * 75 * (1 + 4 * self.RadarBoost)) % 360
	self.RSweep.Rotation = self.RSweepA
	local used = 0
	local R = self.RadarR
	for _, dot in self.ctx.RadarDots do
		if dot.Visible and used < #self.RContacts then
			used += 1
			local c = self.RContacts[used]
			local x, y = dot.Position.X.Offset, dot.Position.Y.Offset
			c.Position = O(200 + x / 81 * (R - 10), 200 + y / 81 * (R - 10))
			c.BackgroundColor3 = dot.BackgroundColor3
			c.Visible = true
		end
	end
	for i = used + 1, #self.RContacts do
		self.RContacts[i].Visible = false
	end

	-- compass ──────────────────────────────────────────────────────────────────────
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local yaw = math.deg(math.atan2(look.X, -look.Z)) % 360
	self.CYaw = self.CYaw or yaw
	local d = (yaw - self.CYaw + 540) % 360 - 180
	self.CYaw = (self.CYaw + d * math.min(1, dt * 16)) % 360
	self.CHeading.Text = string.format("%03d", math.floor(yaw + 0.5) % 360)
	local PXD = 6.4
	local function curve(x)
		return 40 + 0.00036 * (x - 350) ^ 2
	end
	for _, t in self.CTicks do
		local dd = (t.Deg - self.CYaw + 540) % 360 - 180
		local vis = math.abs(dd) < 52
		t.F.Visible = vis
		if t.L then
			t.L.Visible = vis
		end
		if vis then
			local x = 350 + dd * PXD
			local y = curve(x)
			local a = (math.abs(dd) / 52) ^ 3
			t.F.Position = O(x, y)
			t.F.BackgroundTransparency = a
			if t.L then
				t.L.Position = O(x, y + 6)
				t.L.TextTransparency = a
			end
		end
	end
	for i, b in self.CBase do
		local x = 350 + (i - 30.5) * 11.2
		b.Position = O(x, curve(x) + 1)
		b.BackgroundTransparency = 0.2 + 0.8 * (math.abs(i - 30.5) / 30) ^ 2
		b.Rotation = math.deg(math.atan(0.00072 * (x - 350)))
	end
	used = 0
	for _, dot in self.ctx.RadarDots do
		if dot.Visible and used < #self.CMarkers then
			local x, y = dot.Position.X.Offset, dot.Position.Y.Offset
			if x * x + y * y > 4 then
				used += 1
				local rel = math.deg(math.atan2(x, -y))
				local m = self.CMarkers[used]
				local mx = 350 + math.clamp(rel, -50, 50) * PXD
				m.Position = O(mx, curve(mx) - 26)
				m.BackgroundColor3 = dot.BackgroundColor3
				m.BackgroundTransparency = if math.abs(rel) > 50 then 0.5 else 0
				m.Visible = true
			end
		end
	end
	for i = used + 1, #self.CMarkers do
		self.CMarkers[i].Visible = false
	end
end

function Holo:Destroy()
	for _, p in self.Panels do
		p.Gui:Destroy()
	end
	self.Folder:Destroy()
end

return Holo
