--!nocheck
--[[
	PrestigeFX - full-screen "end game" cinematic for prestiging a weapon (2026-11-17).
	Everything is a pure function of time t (FX:_at(t)), so frames can be frozen for previews and the
	sequence can be skipped cleanly.

	  0.00  blackout + cinematic letterbox
	  0.30  CHARGE  the weapon spins up in 3D, energy rings and light streams converge, shake builds
	  1.95  IGNITE  white flash, deep boom, double shockwave, the Prestige Gold render appears white-hot
	                and cools to gold, gold shards burst, the gold hex backdrop zooms in behind
	  2.60  "PRESTIGE II" slams in (cyan / magenta split collapsing)
	  3.10  the new star slams into its slot with its own shockwave
	  3.30  weapon line types out, reward chips rise, CONTINUE at 4.4; idle loop after that
	Click any time after 1.2 s to skip to the end.

	PrestigeFX.Play({ HS = HS, Weapon = "Vanguard", Prestige = 2, Parent = PlayerGui?, Hold = t?, OnDone = fn? })
	Hold freezes the frame at time t (Edit previews, no sound).
	Fired by MasteryHS when MasteryLevelUp carries Prestige; Studio hook: player attribute PrestigeFXTest = "Vanguard:2".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local MC = require(Vantage:WaitForChild("Mastery"):WaitForChild("MasteryConfig"))
local Unlocks = require(Vantage:WaitForChild("Weapons"):WaitForChild("WeaponUnlocks"))
local K = require(script.Parent:WaitForChild("ScreenKit"))

local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

local function id(n) return "rbxassetid://" .. n end
local ATLAS = { [0] = id(104850711810300), id(84706372895889), id(136561818438659) }
local A = { claim = { 2, 306, 285, 290, 92 }, pill = { 0, 406, 899, 400, 104 } }
local RAYS, BLOOM, STAR = id(113538852110620), id(103142630740394), id(107113949398119)
local PRESTIGE_BG = id(80080339744742)
local GOLD_ATLAS, GOLD_MASKS = id(100199878854058), id(95186368975673)
local GOLD_CELL = { Vanguard = { 0, 0 }, Sentinel = { 512, 0 }, Spectre = { 0, 256 }, Breacher = { 512, 256 }, Longshot = { 0, 512 }, Arc = { 512, 512 }, Knife = { 0, 768 } }
local SFX = { -- licensed sounds already used elsewhere in the game
	{ 0.02, 9045201066, 0.6 }, -- riser (crate opening)
	{ 0.30, 9125980435, 0.5 }, -- charge (effects)
	{ 1.70, 9039693350, 0.6 }, -- big dramatic whoosh (skin inspects)
	{ 1.95, 9125484526, 1.0 }, -- deep reverberant boom (match live)
	{ 1.95, 9048764753, 0.8 }, -- reveal hit (unbox)
	{ 2.00, 118649522317334, 0.55 }, -- legendary sting (eliminations)
	{ 2.60, 9125403425, 0.7 }, -- title slam boom
	{ 3.10, 9126073318, 0.6 }, -- star ring
	{ 3.25, 9040281024, 0.45 }, -- swell
}
local ROMAN = { "I", "II", "III", "IV", "V" }

local W, H = 1920, 1080
local C = V2(960, 355) -- gun centre (design px)
local GOLD = RGB(255, 200, 70)
local GOLD_GRAD = CS({ CK(0, RGB(255, 252, 232)), CK(0.45, RGB(255, 212, 110)), CK(0.75, RGB(255, 160, 40)), CK(1, RGB(200, 100, 20)) })

local function clamp01(x) return math.clamp(x, 0, 1) end
local function seg(t, a, b) return clamp01((t - a) / (b - a)) end
local function outCubic(x) return 1 - (1 - x) ^ 3 end
local function outExpo(x) return if x >= 1 then 1 else 1 - 2 ^ (-10 * x) end
local function outBack(x) local c1 = 1.9 return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2 end
local function lerp(a, b, x) return a + (b - a) * x end

local function skin(obj, key)
	local a = A[key]
	obj.Image = ATLAS[a[1]]
	obj.ImageRectOffset = V2(a[2], a[3])
	obj.ImageRectSize = V2(a[4], a[5])
end

-- 3D gun framed in a viewport (same rule as MasteryHS)
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
local function frame(vp, m, fill)
	local mn, mx = aabb(m)
	if mn.X == math.huge then return end
	local ctr, span = (mn + mx) / 2, mx - mn
	local L = math.max(span.X, span.Y * 1.7, span.Z, 0.1)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(ctr + Vector3.new(0, 0, L * fill / (2 * math.tan(math.rad(15))) + span.Z), ctr)
	cam.Parent = vp
	vp.CurrentCamera = cam
	m.Parent = vp
	return ctr
end
local GOLD_RAMP = { RGB(70, 36, 4), RGB(176, 112, 22), RGB(255, 196, 64), RGB(255, 250, 222) }
local function goldify(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local l = math.clamp(0.12 + (0.3 * c.R + 0.59 * c.G + 0.11 * c.B) * 1.75, 0, 0.999) * 3
			local i = math.floor(l) + 1
			d.Color = GOLD_RAMP[i]:Lerp(GOLD_RAMP[i + 1], l - (i - 1))
			d.Material, d.Reflectance = Enum.Material.SmoothPlastic, 0
			pcall(function() d.TextureID = "" end)
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
end

------------------------------------------------------------------ object
local FX = {}
FX.__index = FX

function FX:_ring(parent, z)
	local f = self.HS.new("Frame", { Name = "Ring", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(100, 100), ZIndex = z }, parent)
	self.HS.corner(f, UDim.new(0.5, 0))
	local st = self.HS.new("UIStroke", { Thickness = 6, Color = GOLD, Transparency = 1 }, f)
	return { F = f, S = st }
end

function FX:_text(parent, p)
	local t = self.HS.new("TextLabel", { Name = p.Name or "Text", BackgroundTransparency = 1, Text = p.Text, FontFace = p.Font or Font.fromEnum(Enum.Font.FredokaOne), TextSize = p.Size, TextColor3 = p.Color or WHITE, TextTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = p.Pos, Size = p.Box, ZIndex = p.Z, TextXAlignment = Enum.TextXAlignment.Center }, parent)
	local st = p.Stroke and self.HS.new("UIStroke", { Thickness = p.Stroke, Color = p.StrokeColor or RGB(40, 18, 2), Transparency = 1 }, t)
	return t, st
end

function FX.Play(opts)
	local self = setmetatable({ HS = opts.HS, Weapon = opts.Weapon or "Vanguard", N = math.max(1, opts.Prestige or 1), OnDone = opts.OnDone, T = 0, Done = false, Fired = {} }, FX)
	self:_build(opts.Parent)
	if opts.Hold then
		self:_at(opts.Hold)
		return self
	end
	self.Conn = RunService.RenderStepped:Connect(function(dt)
		if not self.Gui.Parent then self.Conn:Disconnect() return end -- GUI removed (reset, teleport, closed)
		self.T += dt
		self:_sounds(self.T)
		self:_at(self.T)
	end)
	return self
end

function FX:_build(parent)
	local HS = self.HS
	local new = HS.new
	local pg = parent or (Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
	local gui = new("ScreenGui", { Name = "PrestigeFX", DisplayOrder = 250, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	self.Gui = gui
	local click = new("TextButton", { Name = "Skip", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 1 }, gui)
	click.MouseButton1Click:Connect(function()
		if self.T > 1.2 and self.T < 4.4 then self.T = 4.4 end
	end)
	-- full-screen layers
	self.Black = new("Frame", { Name = "Black", BackgroundColor3 = BLACK, BorderSizePixel = 0, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 2 }, gui)
	self.BG = new("ImageLabel", { Name = "Backdrop", BackgroundTransparency = 1, Image = PRESTIGE_BG, ScaleType = Enum.ScaleType.Crop, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.3, 1.3), ZIndex = 3 }, gui)
	self.BGShade = new("Frame", { Name = "Shade", BackgroundColor3 = BLACK, BorderSizePixel = 0, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 4 }, gui)
	self.BGShadeG = new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.1), NK(0.35, 0.75), NK(0.6, 0.6), NK(1, 0.05) }) }, self.BGShade)
	-- stage (design px, scaled to fit)
	local shake = new("Frame", { Name = "Shake", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 5 }, gui)
	self.Shake = shake
	local stage = new("Frame", { Name = "Stage", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(W, H), ZIndex = 5 }, shake)
	self.Scale = new("UIScale", {}, stage)
	self.Stage = stage

	self.RaysA = new("ImageLabel", { Name = "RaysA", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = GOLD, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(1500, 1500), ZIndex = 6 }, stage)
	self.RaysB = new("ImageLabel", { Name = "RaysB", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(255, 236, 170), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(1100, 1100), ZIndex = 6 }, stage)
	self.Bloom = new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(120, 200, 255), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(1200, 800), ZIndex = 7 }, stage)
	self.Core = new("ImageLabel", { Name = "Core", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = WHITE, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(300, 300), ZIndex = 12 }, stage)

	-- converging rings + inward light streams (charge)
	self.Rings = {}
	for i = 1, 5 do self.Rings[i] = self:_ring(stage, 8) end
	self.Streams = {}
	local rng = Random.new(7)
	for i = 1, 48 do
		local a = rng:NextNumber(0, math.pi * 2)
		local f = new("Frame", { Name = "Stream", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(70, 4), Rotation = math.deg(a), BackgroundTransparency = 1, ZIndex = 9 }, stage)
		new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.6, 0.3), NK(1, 0) }) }, f)
		self.Streams[i] = { F = f, A = a, Sp = rng:NextNumber(0.9, 1.6), Off = rng:NextNumber(), R = rng:NextNumber(650, 1000) }
	end

	-- 3D gun (charge)
	self.GunHolder = new("Frame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(960, 420), ZIndex = 10 }, stage)
	self.GunScale = new("UIScale", {}, self.GunHolder)
	self.GunVP = new("ViewportFrame", { Name = "VP", BackgroundTransparency = 1, Size = S(1, 1), ImageTransparency = 1, Ambient = RGB(200, 210, 230), LightColor = WHITE, LightDirection = Vector3.new(-0.3, -0.6, -1), ZIndex = 10 }, self.GunHolder)
	local ok, m = pcall(K.weapon, self.Weapon)
	if ok and m then
		self.GunM, self.GunC = m, frame(self.GunVP, m, 0.48)
		self.GunBase = m:GetPivot()
	end

	-- gold reveal
	self.GoldHolder = new("Frame", { Name = "Gold", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(C.X, C.Y), Size = O(1000, 500), Visible = false, ZIndex = 11 }, stage)
	self.GoldScale = new("UIScale", {}, self.GoldHolder)
	local cell = GOLD_CELL[self.Weapon]
	local function img(name, image, color, tr, pos, size, z)
		return new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = image, ImageRectOffset = V2(cell[1], cell[2]), ImageRectSize = V2(512, 256), ImageColor3 = color, ImageTransparency = tr, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = pos, Size = size, ZIndex = z }, self.GoldHolder)
	end
	if cell then
		self.GoldGlow = img("Glow", GOLD_MASKS, RGB(255, 190, 60), 0.35, S(0.5, 0.5), S(1.08, 1.16), 11)
		img("Shadow", GOLD_MASKS, BLACK, 0.4, UDim2.new(0.5, 10, 0.5, 22), S(1, 1), 11)
		img("Art", GOLD_ATLAS, WHITE, 0, S(0.5, 0.5), S(1, 1), 12)
		self.Hot = img("Hot", GOLD_MASKS, WHITE, 0, S(0.5, 0.5), S(1, 1), 13)
		local sheen = img("Sheen", GOLD_MASKS, WHITE, 0, S(0.5, 0.5), S(1, 1), 14)
		self.Sheen = new("UIGradient", { Rotation = 25, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.48, 0.55), NK(0.5, 0.1), NK(0.52, 0.55), NK(0.58, 1), NK(1, 1) }) }, sheen)
	else -- weapon without a gold render yet: goldified 3D
		local gv = new("ViewportFrame", { Name = "VP", BackgroundTransparency = 1, Size = S(1, 1), Ambient = RGB(150, 110, 60), LightColor = RGB(255, 244, 210), LightDirection = Vector3.new(-0.3, -0.6, -0.8), ZIndex = 12 }, self.GoldHolder)
		local ok2, gm = pcall(K.weapon, self.Weapon)
		if ok2 and gm then goldify(gm); frame(gv, gm, 0.5) end
		self.GoldVP = gv
	end

	-- shockwaves
	self.Waves = { self:_ring(stage, 15), self:_ring(stage, 15), self:_ring(stage, 15) }
	-- shards (deterministic burst)
	self.Shards = {}
	for i = 1, 80 do
		local a = rng:NextNumber(0, math.pi * 2)
		local sp = rng:NextNumber(500, 1500)
		local sz = rng:NextNumber(8, 22)
		local f = new("Frame", { Name = "Shard", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz, sz * rng:NextNumber(1, 2.4)), BackgroundTransparency = 1, ZIndex = 16 }, stage)
		new("UIGradient", { Rotation = 45, Color = CS(RGB(255, 250, 220), RGB(230, 150, 30)) }, f)
		self.Shards[i] = { F = f, V = V2(math.cos(a), math.sin(a)) * sp, R0 = rng:NextNumber(0, 360), Spin = rng:NextNumber(-540, 540), Life = rng:NextNumber(1.0, 2.1), D = rng:NextNumber(0, 0.12) }
	end
	-- embers + twinkles (idle)
	self.Embers = {}
	for i = 1, 46 do
		local s = rng:NextNumber(3, 8)
		local f = new("Frame", { Name = "Ember", BackgroundColor3 = RGB(255, 200, 90):Lerp(RGB(255, 140, 40), rng:NextNumber()), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(s, s), BackgroundTransparency = 1, ZIndex = 9 }, stage)
		HS.corner(f, UDim.new(0.5, 0))
		self.Embers[i] = { F = f, X = rng:NextNumber(0, W), Sp = rng:NextNumber(0.06, 0.16), Off = rng:NextNumber(), Sw = rng:NextNumber(0, 6) }
	end
	self.Twinkles = {}
	for i = 1, 16 do
		local st = new("ImageLabel", { Name = "Twinkle", BackgroundTransparency = 1, Image = STAR, ImageColor3 = RGB(255, 240, 200), AnchorPoint = V2(0.5, 0.5), Size = O(0, 0), ZIndex = 17 }, stage)
		self.Twinkles[i] = { I = st, P = V2(C.X + rng:NextNumber(-560, 560), C.Y + rng:NextNumber(-230, 230)), Ph = rng:NextNumber(0, 10), Sz = rng:NextNumber(30, 70), Spd = rng:NextNumber(1.2, 2.4) }
	end

	-- caption
	self.Caption = self:_text(stage, { Text = "WEAPON MASTERY", Font = HS.MontX, Size = 26, Color = RGB(255, 226, 160), Pos = O(960, 120), Box = O(900, 40), Z = 20, Stroke = 2 })

	-- stars
	self.Stars = {}
	local n = MC.MaxPrestige
	for k = 1, n do
		local x = 960 + (k - (n + 1) / 2) * 104
		local h = new("Frame", { Name = "Star" .. k, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(x, 598), Size = O(96, 96), ZIndex = 20 }, stage)
		local sc = new("UIScale", { Scale = 0 }, h)
		local glow = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = GOLD, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(2.2, 2.2), ZIndex = 20 }, h)
		local t, st = self:_text(h, { Text = "★", Size = 92, Color = if k <= self.N then RGB(255, 214, 96) else RGB(60, 52, 40), Pos = S(0.5, 0.5), Box = S(1, 1), Z = 21, Stroke = 5 })
		if k <= self.N then new("UIGradient", { Rotation = 90, Color = GOLD_GRAD }, t) end
		self.Stars[k] = { H = h, Sc = sc, Glow = glow, T = t, St = st, X = x }
	end

	-- title: chroma copies + main + sheen
	local title = "PRESTIGE " .. (ROMAN[self.N] or tostring(self.N))
	local th = new("Frame", { Name = "Title", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(960, 705), Size = O(1400, 170), ZIndex = 22 }, stage)
	self.TitleScale = new("UIScale", {}, th)
	self.TitleGlow = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 170, 50), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.9, 1.9), ZIndex = 22 }, th)
	self.ChromaC = self:_text(th, { Text = title, Size = 150, Color = RGB(60, 230, 255), Pos = S(0.5, 0.5), Box = S(1, 1), Z = 23 })
	self.ChromaM = self:_text(th, { Text = title, Size = 150, Color = RGB(255, 60, 200), Pos = S(0.5, 0.5), Box = S(1, 1), Z = 23 })
	self.Title, self.TitleStroke = self:_text(th, { Text = title, Size = 150, Pos = S(0.5, 0.5), Box = S(1, 1), Z = 24, Stroke = 9, StrokeColor = RGB(44, 18, 0) })
	new("UIGradient", { Rotation = 90, Color = GOLD_GRAD }, self.Title)
	local shine = self:_text(th, { Text = title, Size = 150, Pos = S(0.5, 0.5), Box = S(1, 1), Z = 25 })
	self.TitleShine = shine
	self.TitleSheen = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.44, 1), NK(0.49, 0.45), NK(0.5, 0.1), NK(0.51, 0.45), NK(0.56, 1), NK(1, 1) }) }, shine)

	-- weapon line + chips + continue
	self.Sub = self:_text(stage, { Text = string.upper(Unlocks.Name(self.Weapon)) .. "   ·   PRESTIGE GOLD UNLOCKED", Font = HS.MontX, Size = 34, Color = RGB(255, 240, 210), Pos = O(960, 792), Box = O(1400, 50), Z = 22, Stroke = 3 })
	self.Chips = {}
	local chips = { { "PRESTIGE GOLD FINISH", RGB(255, 200, 80) }, { string.format("+%d%% REQ  +%d%% ORD  +%d%% XP", MC.PrestigeBoost.REQ, MC.PrestigeBoost.ORD, MC.PrestigeBoost.XP), RGB(130, 220, 255) }, { if self.N >= MC.MaxPrestige then "MAX PRESTIGE REACHED" else ("MASTERY RUN " .. (self.N + 1) .. " BEGINS"), RGB(200, 150, 255) } }
	for i, c in chips do
		local x = 960 + (i - 2) * 380
		local p = new("ImageLabel", { Name = "Chip" .. i, BackgroundTransparency = 1, ImageColor3 = c[2], ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(x, 858), Size = O(350, 60), ZIndex = 22 }, stage)
		skin(p, "pill")
		local t, st = self:_text(p, { Text = c[1], Font = HS.MontX, Size = 20, Pos = S(0.5, 0.45), Box = S(1, 1), Z = 23, Stroke = 2.2, StrokeColor = RGB(10, 10, 30) })
		self.Chips[i] = { P = p, T = t, St = st, X = x }
	end
	local cont = new("ImageButton", { Name = "Continue", BackgroundTransparency = 1, AutoButtonColor = false, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(960, 940), Size = O(300, 90), ZIndex = 24 }, stage)
	skin(cont, "claim")
	self.ContScale = new("UIScale", {}, cont)
	self.Cont = cont
	self.ContText, self.ContStroke = self:_text(cont, { Text = "CONTINUE", Size = 40, Pos = S(0.5, 0.44), Box = S(1, 1), Z = 25, Stroke = 3.5, StrokeColor = RGB(50, 26, 0) })
	cont.MouseButton1Click:Connect(function()
		if self.T >= 4.4 then self:Close() end
	end)

	-- white flash + letterbox on top of everything
	self.Flash = new("Frame", { Name = "Flash", BackgroundColor3 = RGB(255, 250, 235), BorderSizePixel = 0, BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 40 }, gui)
	self.BarT = new("Frame", { Name = "BarTop", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 0), ZIndex = 41 }, gui)
	self.BarB = new("Frame", { Name = "BarBottom", BackgroundColor3 = BLACK, BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = S(1, 0), ZIndex = 41 }, gui)
	self:_fit()
end

function FX:_fit()
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or V2(W, H)
	self.Scale.Scale = math.min(vp.X / W, vp.Y / H)
end

function FX:_sounds(t)
	for i, s in SFX do
		if not self.Fired[i] and t >= s[1] then
			self.Fired[i] = true
			if t - s[1] < 0.25 then -- skipped cues stay silent
				local snd = Instance.new("Sound")
				snd.SoundId, snd.Volume = id(s[2]), s[3]
				snd.Parent = self.Gui
				snd:Play()
				snd.Ended:Connect(function() snd:Destroy() end)
			end
		end
	end
end

------------------------------------------------------------------ the timeline
function FX:_at(t)
	local IG = 1.95 -- ignite
	-- blackout + letterbox
	self.Black.BackgroundTransparency = 1 - outCubic(seg(t, 0, 0.35))
	local bar = 0.045 * outCubic(seg(t, 0.1, 0.6))
	self.BarT.Size, self.BarB.Size = S(1, bar), S(1, bar)
	self.Caption.TextTransparency = 1 - seg(t, 0.4, 0.9)
	self.Caption:FindFirstChildOfClass("UIStroke").Transparency = self.Caption.TextTransparency

	-- charge
	local ch = seg(t, 0.3, IG)
	local charging = t < IG
	self.GunHolder.Visible = charging
	if charging then
		self.GunVP.ImageTransparency = 1 - outCubic(seg(t, 0.3, 0.8))
		self.GunScale.Scale = lerp(0.72, 1.02, outCubic(ch))
		self.GunVP.ImageColor3 = WHITE:Lerp(RGB(255, 214, 140), ch ^ 2)
		if self.GunM and self.GunC then
			local yaw = (t - 0.3) * 0.8 + 16 * 1.65 * ch ^ 3 / 3
			self.GunM:PivotTo(CFrame.new(self.GunC) * CFrame.Angles(0.12 * math.sin(t * 3), yaw, 0) * CFrame.new(-self.GunC) * self.GunBase)
		end
	end
	local cyan, gold = RGB(110, 220, 255), GOLD
	local chargeCol = cyan:Lerp(gold, ch)
	for i, r in self.Rings do
		local p = ((t - 0.3) * 1.15 + i / 5) % 1
		local s = 2400 * (1 - p) ^ 1.7 + 60
		r.F.Size = O(s, s)
		r.S.Color = chargeCol
		r.S.Thickness = 3 + 10 * p
		r.S.Transparency = if charging and t > 0.3 then 1 - math.sin(math.pi * p) * (0.25 + 0.6 * ch) else 1
	end
	for _, s in self.Streams do
		local p = ((t * s.Sp) + s.Off) % 1
		local r = s.R * (1 - p) + 40
		local d = V2(math.cos(s.A), math.sin(s.A))
		s.F.Position = O(C.X + d.X * r, C.Y + d.Y * r)
		s.F.Size = O(40 + 160 * ch, 3 + 3 * ch)
		s.F.BackgroundColor3 = chargeCol:Lerp(WHITE, 0.4)
		s.F.BackgroundTransparency = if charging and t > 0.45 then 1 - (0.2 + 0.7 * ch) * math.sin(math.pi * p) else 1
	end
	self.Bloom.ImageColor3 = if charging then chargeCol else GOLD
	self.Bloom.ImageTransparency = if charging then 1 - (0.25 + 0.5 * ch) * seg(t, 0.3, 0.8) else 0.35 + 0.08 * math.sin(t * 2)
	self.Bloom.Size = if charging then O(900 + 700 * ch, 600 + 400 * ch) else O(1200, 800)
	self.Core.ImageTransparency = if charging then 1 - ch ^ 2 else 1 - 0.8 * (1 - outCubic(seg(t, IG, IG + 0.6)))
	self.Core.Size = O(200 + 500 * ch ^ 3, 200 + 500 * ch ^ 3)

	-- flash
	local fl = if t < IG then seg(t, 1.78, IG) ^ 2 else 1 - outCubic(seg(t, IG, IG + 0.75))
	self.Flash.BackgroundTransparency = 1 - fl

	-- reveal
	local rv = t >= IG
	self.GoldHolder.Visible = rv
	self.BG.ImageTransparency = if rv then 1 - outCubic(seg(t, IG, IG + 0.5)) else 1
	self.BGShade.BackgroundTransparency = if rv then 0 else 1
	local z = 1.38 - 0.28 * outCubic(seg(t, IG, IG + 2.6)) + 0.015 * math.sin(t * 0.5)
	self.BG.Size = S(z, z)
	self.BG.Position = UDim2.new(0.5, math.sin(t * 0.21) * 14, 0.5, math.cos(t * 0.17) * 10)
	local rp = outBack(seg(t, IG, IG + 0.55))
	self.RaysA.ImageTransparency = if rv then 0.35 + 0.1 * math.sin(t * 1.7) else 1 - 0.25 * ch
	self.RaysA.ImageColor3 = if rv then GOLD else chargeCol
	self.RaysA.Size = O(1500 * (if rv then 0.45 + 0.6 * rp else 0.6), 1500 * (if rv then 0.45 + 0.6 * rp else 0.6))
	self.RaysA.Rotation = (t * 9) % 360
	self.RaysB.ImageTransparency = if rv then 0.45 else 1
	self.RaysB.Rotation = (-t * 14) % 360
	if rv then
		self.GoldScale.Scale = lerp(0.78, 1, outBack(seg(t, IG, IG + 0.5)))
		self.GoldHolder.Position = O(C.X, C.Y + math.sin((t - IG) * 1.3) * 9)
		self.GoldHolder.Rotation = math.sin((t - IG) * 0.8) * 1.8
		if self.Hot then
			local c = seg(t, IG, IG + 1.3)
			self.Hot.ImageTransparency = outCubic(c)
			self.Hot.ImageColor3 = WHITE:Lerp(RGB(255, 140, 30), c)
		end
		if self.GoldGlow then self.GoldGlow.ImageTransparency = 0.3 + 0.12 * math.sin(t * 2.4) end
		if self.Sheen then
			local u = ((t - (IG + 0.6)) % 2.4) / 0.8
			self.Sheen.Offset = V2(if t > IG + 0.6 and u < 1 then -1 + 2 * u else 1, 0)
		end
		if self.GoldVP then self.GoldVP.LightDirection = Vector3.new(math.sin(t * 0.9) * 0.9, -0.55, -0.75) end
	end
	-- shockwaves: two at ignite, one at the star slam
	local newStar = math.min(self.N, #self.Stars)
	local starX = self.Stars[newStar] and self.Stars[newStar].X or 960
	local waves = { { IG, 0.9, 2600, GOLD, C }, { IG + 0.1, 1.0, 1900, RGB(255, 250, 230), C }, { 3.1, 0.7, 700, RGB(255, 220, 120), V2(starX, 598) } }
	for i, wv in waves do
		local r = self.Waves[i]
		local p = seg(t, wv[1], wv[1] + wv[2])
		r.F.Position = O(wv[5].X, wv[5].Y)
		local s = 80 + wv[3] * outCubic(p)
		r.F.Size = O(s, s)
		r.S.Color = wv[4]
		r.S.Thickness = 2 + 36 * (1 - p)
		r.S.Transparency = if t >= wv[1] and p < 1 then 0.1 + 0.9 * p else 1
	end
	-- shards
	for _, sh in self.Shards do
		local dt = t - IG - sh.D
		if dt > 0 and dt < sh.Life then
			local pos = C + sh.V * dt * (1 - 0.35 * dt / sh.Life) + V2(0, 520 * dt * dt)
			sh.F.Position = O(pos.X, pos.Y)
			sh.F.Rotation = sh.R0 + sh.Spin * dt
			sh.F.BackgroundTransparency = seg(dt, sh.Life * 0.45, sh.Life)
		else
			sh.F.BackgroundTransparency = 1
		end
	end
	-- embers + twinkles
	for _, e in self.Embers do
		local p = ((t * e.Sp) + e.Off) % 1
		e.F.Position = O(e.X + math.sin(t * 1.2 + e.Sw) * 18, H * (1.02 - p * 1.1))
		e.F.BackgroundTransparency = if rv then 0.1 + 0.9 * math.max(seg(p, 0.6, 1), 1 - seg(t, IG, IG + 0.8)) else 1
	end
	for _, tw in self.Twinkles do
		local a = if t > IG + 0.3 then math.max(0, math.sin((t + tw.Ph) * tw.Spd)) else 0
		tw.I.Position = O(tw.P.X, tw.P.Y)
		tw.I.Size = O(tw.Sz * a, tw.Sz * a)
		tw.I.Rotation = (t * 50 + tw.Ph * 40) % 360
	end

	-- title slam
	local tp = seg(t, 2.6, 2.95)
	local tin = t >= 2.6
	self.TitleScale.Scale = if tin then lerp(2.7, 1, outExpo(tp)) - 0.05 * math.sin(math.pi * seg(t, 2.95, 3.2)) else 2.7
	local ta = if tin then 1 - seg(t, 2.6, 2.72) else 1
	self.Title.TextTransparency, self.TitleStroke.Transparency = ta, ta
	local split = 46 * (1 - outCubic(seg(t, 2.6, 3.35)))
	self.ChromaC.Position = UDim2.new(0.5, -split, 0.5, 0)
	self.ChromaM.Position = UDim2.new(0.5, split, 0.5, 0)
	local ca = if tin then 0.25 + 0.75 * seg(t, 3.0, 3.5) else 1
	self.ChromaC.TextTransparency, self.ChromaM.TextTransparency = ca, ca
	self.TitleGlow.ImageTransparency = if tin then 0.35 + 0.15 * math.sin(t * 2.2) else 1
	self.TitleShine.TextTransparency = if tin then 0 else 1
	local su = ((t - 3.3) % 3) / 0.9
	self.TitleSheen.Offset = V2(if t > 3.3 and su < 1 then -1 + 2 * su else 1, 0)

	-- stars: earlier stars pop in, the new one slams
	for k, st in self.Stars do
		local s, a
		if k < self.N then
			local p = seg(t, 2.8 + k * 0.08, 3.0 + k * 0.08)
			s, a = outBack(p), 1 - p
		elseif k == self.N then
			local p = seg(t, 3.1, 3.4)
			s, a = if t >= 3.1 then lerp(4, 1, outExpo(p)) else 0, 1 - seg(t, 3.1, 3.18)
			st.H.Rotation = if t >= 3.1 then lerp(160, 0, outExpo(p)) else 0
			st.Glow.ImageTransparency = if t >= 3.1 then 0.2 + 0.25 * math.sin(t * 3) else 1
		else
			local p = seg(t, 3.25 + k * 0.06, 3.45 + k * 0.06)
			s, a = outBack(p), 0.25 + 0.75 * (1 - p)
		end
		st.Sc.Scale = math.max(0, s)
		st.T.TextTransparency, st.St.Transparency = a, a
	end

	-- weapon line types out, chips rise, continue
	local sub = self.Sub
	sub.TextTransparency = if t >= 3.3 then 0 else 1
	sub:FindFirstChildOfClass("UIStroke").Transparency = sub.TextTransparency
	sub.MaxVisibleGraphemes = math.floor(utf8.len(sub.Text) * seg(t, 3.3, 3.95))
	for i, c in self.Chips do
		local p = seg(t, 3.8 + i * 0.12, 4.2 + i * 0.12)
		c.P.Position = O(c.X, 858 + 40 * (1 - outBack(p)))
		c.P.ImageTransparency = 1 - p
		c.T.TextTransparency, c.St.Transparency = 1 - p, 1 - p
	end
	local cp = seg(t, 4.4, 4.8)
	self.Cont.ImageTransparency = 1 - cp
	self.ContText.TextTransparency, self.ContStroke.Transparency = 1 - cp, 1 - cp
	self.ContScale.Scale = (0.8 + 0.2 * outBack(cp)) * (1 + 0.035 * math.sin(t * 4) * cp)

	-- camera shake: builds through the charge, kicks on each impact
	local amp = (if charging then 7 * ch ^ 2 else 0)
		+ (if t >= IG then 30 * math.exp(-(t - IG) * 5) else 0)
		+ (if t >= 2.6 then 16 * math.exp(-(t - 2.6) * 7) else 0)
		+ (if t >= 3.1 then 10 * math.exp(-(t - 3.1) * 8) else 0)
	self.Shake.Position = O(math.sin(t * 71) * amp, math.cos(t * 59) * amp * 0.8)
end

function FX:Close()
	if self.Done then return end
	self.Done = true
	if self.Conn then self.Conn:Disconnect() end
	local HS = self.HS
	for _, d in self.Gui:GetDescendants() do
		if d:IsA("GuiObject") then
			pcall(function() HS.tween(d, 0.35, { BackgroundTransparency = 1 }) end)
			if d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame") then pcall(function() HS.tween(d, 0.35, { ImageTransparency = 1 }) end) end
			if d:IsA("TextLabel") then pcall(function() HS.tween(d, 0.35, { TextTransparency = 1 }) end) end
		elseif d:IsA("UIStroke") then
			pcall(function() HS.tween(d, 0.35, { Transparency = 1 }) end)
		end
	end
	task.delay(0.4, function()
		self.Gui:Destroy()
		if self.OnDone then self.OnDone() end
	end)
end

return FX
