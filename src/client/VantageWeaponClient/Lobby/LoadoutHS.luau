--!nocheck
--[[
	LoadoutHS - VantageShot Loadout screen (2026-11-17). Follows Hypershot's loadout construction:
	  full-screen dark stage with diagonal bands; left column of 4 preset cards (3 gun tiles + 5 kit squares),
	  EDIT beside each (selected = blue rim + blue EDIT), Page x/2 arrows, red BACK; the shown gun huge in the
	  middle; currency top right. Our own 10%: violet/cyan skin, 3 guns per preset (knife + grenade always on),
	  Shield Pack / Grappling Hook squares, and a weapon stats panel where Hypershot has its emote wheel.
	Selecting a card makes it the deploy loadout (Remotes.LoadoutPreset "Select"); a gun tile or EDIT opens the
	gun picker for that slot ("Set"; a gun already in the preset swaps places). Data: LoadoutPresets module.
	Screen API used by the Lobby: Show / Hide / IsShown / HandleKey.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local WConfig = require(Vantage:WaitForChild("Weapons"):WaitForChild("WeaponConfig"))
local Skins = require(Vantage.Weapons:WaitForChild("Skins"))
local Presets = require(Vantage.Weapons:WaitForChild("LoadoutPresets"))
local Crate = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local EquipCatalog = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local EquipStatsUI = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentStatsUI"))
local HS = require(script.Parent:WaitForChild("HS"))
local K = require(script.Parent:WaitForChild("ScreenKit"))

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local new = HS.new

-- 2026-11-19: Signatures (kit square 4 + SIGNATURE picker tab)
local SigRoot = game:GetService("ReplicatedStorage"):WaitForChild("Vantage"):WaitForChild("Signatures")
local SigCat = require(SigRoot:WaitForChild("SignatureCatalog"))
local IchorIcon = "rbxassetid://108288759204937"
pcall(function() IchorIcon = require(game:GetService("ReplicatedStorage").Vantage:WaitForChild("Ichor"):WaitForChild("IchorConfig")).Icon or IchorIcon end)
local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
local ICON = { Grenade = "rbxassetid://79018507679348", Pack = "rbxassetid://89469379464247", Hook = "rbxassetid://96495682163172", Empty = "rbxassetid://90848964555404" }
local BLOOM = "rbxassetid://103142630740394"
local RAYS = "rbxassetid://113538852110620"
local GLOW = "rbxassetid://104786452938879"
-- background art (user's Gemini armory, left seam blended, split in two 688x768 halves) + aura textures (UnboxHS)
local ART_L, ART_R, ART_W, ART_H = "rbxassetid://79345497802882", "rbxassetid://101199786462963", 1376, 768
local AURA = { RaysA = "rbxassetid://113538852110620", RaysB = "rbxassetid://84656415162737", Ring = "rbxassetid://101633346517219", Bokeh = "rbxassetid://79247701955793" }
local GUN_X, GUN_Y = 960, 455

local C = {
	Bg0 = RGB(12, 9, 26), Bg1 = RGB(6, 5, 14), Band = RGB(40, 30, 80),
	Card = RGB(14, 10, 26), Tile = RGB(24, 17, 42), Rim = RGB(112, 104, 140), RimDark = RGB(4, 3, 10),
	Sel = RGB(70, 170, 255), Ink = RGB(10, 6, 22), Muted = RGB(200, 190, 230),
}
local PAL = {
	Green = { Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Ink = RGB(25, 45, 12) },
	Red = { Rim = RGB(110, 18, 22), Top0 = RGB(255, 100, 96), Top1 = RGB(212, 38, 46), Ink = RGB(60, 8, 12) },
	Blue = { Rim = RGB(14, 40, 110), Top0 = RGB(96, 176, 255), Top1 = RGB(36, 96, 220), Ink = RGB(8, 22, 64) },
	Steel = { Rim = RGB(150, 146, 170), Top0 = RGB(46, 40, 64), Top1 = RGB(16, 12, 26), Ink = RGB(6, 4, 12) },
}

-- geometry: Hypershot ref px x 0.745 (1920x1080 design)
local CARD_X, CARD_Y, CARD_W, CARD_H, CARD_P = 41, 56, 320, 164, 188.5
local TILE_Y, TILE_H, TILE_GAP = 14, 66, 8
local SQ_Y, SQ, SQ_P = 92, 52, 60

local function titleCase(s)
	return (tostring(s):lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
local function num(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function hsv(c, s, v)
	local h, s0 = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(s0 * s, 0, 1), v)
end

-- world box of the visible parts + one framing for every gun (same size on screen)
local function aabb(m)
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf, h = d.CFrame, d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
						mn, mx = mn:Min(p), mx:Max(p)
					end
				end
			end
		end
	end
	return mn, mx
end
local function frame(vp, m, tilt, fill, aspect, fov)
	vp:ClearAllChildren()
	local mn, mx = aabb(m)
	if mn.X == math.huge then return nil end
	local c = (mn + mx) / 2
	local span = mx - mn
	local L = math.max(span.X, span.Y * 1.7, 0.1)
	m:PivotTo(CFrame.new(c) * CFrame.Angles(0, 0, math.rad(tilt)) * CFrame.new(-c) * m:GetPivot())
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov or 20
	local tv = math.tan(math.rad(cam.FieldOfView / 2))
	local d = math.max(L * fill / 2 / (tv * (aspect or 1)), span.Y * 1.25 * fill / 2 / tv)
	cam.CFrame = CFrame.lookAt(c + Vector3.new(0, 0, d + span.Z), c)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Ambient = RGB(215, 215, 228)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-0.35, -0.6, -1)
	m.Parent = vp
	return m, c
end
local function silhouette(parent, vp, color, tr, scale, off, z)
	local cam, src = vp.CurrentCamera, vp:FindFirstChildWhichIsA("Model")
	if not (cam and src) then return end
	local v = new("ViewportFrame", { Name = "Sil", BackgroundTransparency = 1, ImageColor3 = color, ImageTransparency = tr, AnchorPoint = vp.AnchorPoint, Position = vp.Position + UDim2.fromOffset(off.X, off.Y), Size = UDim2.new(vp.Size.X.Scale * scale, vp.Size.X.Offset * scale, vp.Size.Y.Scale * scale, vp.Size.Y.Offset * scale), Ambient = WHITE, LightColor = BLACK, ZIndex = vp.ZIndex - 1 }, parent)
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color, d.Material, d.Reflectance = WHITE, Enum.Material.SmoothPlastic, 0
			pcall(function() d.TextureID = "" end)
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	local c = Instance.new("Camera")
	c.FieldOfView, c.CFrame = cam.FieldOfView, cam.CFrame
	c.Parent = v
	v.CurrentCamera = c
	m.Parent = v
	return v
end

local function skinOf(w)
	local id = player:GetAttribute("Skin_" .. w)
	return if type(id) == "string" then id else Skins.Default
end
local function skinDef(w)
	local ok, d = pcall(Skins.Get, w, skinOf(w))
	return ok and d or nil
end

-- a Signature's Tripo model framed in a viewport, turned to a three-quarter view
local function sigModel(vp, it, aspect, fill, fov)
	local src = it and SigRoot:FindFirstChild("Assets") and SigRoot.Assets:FindFirstChild(it.Asset)
	if not src then vp:ClearAllChildren() return end
	local m = src:Clone()
	for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.Anchored = true end end
	m:PivotTo(CFrame.Angles(0, math.rad(it.Yaw or 215), 0))
	frame(vp, m, 0, fill or 1, aspect or 1, fov or 22)
	vp.Ambient = Color3.fromRGB(120, 118, 135):Lerp(it.Color, 0.3)
	vp.LightColor = WHITE:Lerp(it.Color, 0.35)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.8)
end
local function sigSway(vp, t, amp)
	local m = vp:FindFirstChildOfClass("Model")
	if not m then return end
	local base = m:GetAttribute("BaseCF")
	if not base then base = m:GetPivot(); m:SetAttribute("BaseCF", base); m:SetAttribute("SwayC", (m:GetBoundingBox()).Position) end
	local c = m:GetAttribute("SwayC")
	local size = m:GetExtentsSize().Magnitude
	m:PivotTo(CFrame.new(c) * CFrame.new(0, math.sin(t * 1.1) * size * 0.025, 0) * CFrame.Angles(math.sin(t * 0.7) * 0.04, math.sin(t * 0.55) * (amp or 0.3), 0) * CFrame.new(-c) * base)
end
local function sigSpin(vp, rad)
	local m = vp:FindFirstChildOfClass("Model")
	if not m then return end
	local c = m:GetAttribute("SpinC")
	if not c then c = (m:GetBoundingBox()).Position; m:SetAttribute("SpinC", c) end
	m:PivotTo(CFrame.new(c) * CFrame.Angles(0, rad, 0) * CFrame.new(-c) * m:GetPivot())
end

-- 2026-11-19: "living" card art — Ken Burns drift + breathing zoom on the background image, a soft light
-- sweep and rising motes in the Signature's colour. Pure UI (no particles), driven from _sigStep.
local function makeLiving(face, it, nMotes, z)
	local L = { Phase = math.random() * 50 }
	L.Art = new("ImageLabel", { Name = "Art", BackgroundTransparency = 1, Image = it.Art or "", Visible = (it.Art or "") ~= "", ScaleType = Enum.ScaleType.Crop,
		AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.16, 1.16), ZIndex = z }, face)
	L.Sweep = new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5),
		Position = S(-0.3, 0.5), Size = S(0.16, 2), Rotation = 22, ZIndex = z }, face)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, L.Sweep)
	L.Motes = {}
	for k = 1, nMotes do
		local sz = math.random(3, 6)
		local m = new("Frame", { Name = "Mote", BackgroundColor3 = it.Color:Lerp(WHITE, 0.45), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz, sz), ZIndex = z }, face)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, m)
		L.Motes[k] = { F = m, X = math.random(), Off = math.random() * 1.2, Spd = 0.05 + math.random() * 0.06, Sway = math.random() * 6.28 }
	end
	return L
end
local function animLiving(L, t, slow)
	if not L then return end
	t = t * (slow or 1) + L.Phase
	if L.Art.Visible then
		local zoom = 1.16 + 0.05 * math.sin(t * 0.17)
		L.Art.Size = S(zoom, zoom)
		L.Art.Position = S(0.5 + 0.035 * math.sin(t * 0.21), 0.5 + 0.03 * math.cos(t * 0.16))
	end
	local cyc = (t * 0.2) % 1.7
	L.Sweep.Position = S(-0.35 + cyc, 0.5)
	L.Sweep.Visible = cyc < 1.7
	for _, m in L.Motes do
		local y = 1.05 - ((t * m.Spd + m.Off) % 1.2)
		m.F.Position = S(m.X + 0.025 * math.sin(t * 1.3 + m.Sway), y)
		m.F.BackgroundTransparency = 0.15 + 0.85 * math.clamp(math.abs(y - 0.55) / 0.5, 0, 1)
	end
end
local function LoadoutHS_setArt(L, art)
	if not L then return end
	L.Art.Image = art or ""
	L.Art.Visible = (art or "") ~= ""
end

local LoadoutHS = {}
LoadoutHS.__index = LoadoutHS

function LoadoutHS.new(opts)
	local self = setmetatable({ Opts = opts or {}, Page = 1, Cards = {}, Shown = false, ShowGun = nil, PickSlot = nil, PickIndex = nil, Hover = nil }, LoadoutHS)
	self:_build()
	RunService.RenderStepped:Connect(function(dt)
		if self.Shown then self:_step(dt) end
	end)
	player.AttributeChanged:Connect(function(a)
		if not self.Shown then return end
		if a == "Signature" or a == "OwnedSignatures" or a == "Ichor" then
			self.SigPending = nil
			self:_renderCards()
			if self.Picker and self.Picker.Visible and self.PickSlot == "Sig" then self:_renderSig() end
		elseif a:sub(1, 6) == "Equip_" or a == "OwnedEquipment" then
			self.EquipPending = nil
			self:_refresh()
		elseif a == "LoadoutPresets" or a == "LoadoutActive" or a == "OwnedWeapons" or a:sub(1, 5) == "Skin_" then
			self:_refresh()
		elseif a == "REQ" then
			self:_req()
		end
	end)
	return self
end

------------------------------------------------------------------ kit
local function text(parent, p)
	p.Stroke = p.Stroke or 2.6
	p.StrokeColor = p.StrokeColor or C.Ink
	p.ZIndex = p.ZIndex or 6
	return HS.text(parent, p)
end

local function pill(parent, p)
	local z = p.Z or 6
	local b = new("TextButton", { Name = p.Name or "Pill", Text = "", AutoButtonColor = false, BackgroundColor3 = p.Pal.Rim, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	HS.corner(b, p.R or 8)
	local face = new("Frame", { Name = "Face", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(3, 3), Size = UDim2.new(1, -6, 1, -6), ClipsDescendants = true, ZIndex = z }, b)
	HS.corner(face, (p.R or 8) - 2)
	local grad = new("UIGradient", { Rotation = 90, Color = CS(p.Pal.Top0, p.Pal.Top1) }, face)
	new("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, BorderSizePixel = 0, Position = O(4, 2), Size = UDim2.new(1, -8, 0.42, 0), ZIndex = z }, face)
	for i = 0, 1 do
		new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.76, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -26 - i * 14, 0.5, 0), Size = UDim2.new(0, 6, 1.6, 0), Rotation = 24, ZIndex = z }, face)
	end
	local t = text(b, { Name = "Label", Text = p.Text, TextSize = p.TextSize or 30, Stroke = 3, StrokeColor = p.Pal.Ink, Position = O(0, -1), Size = S(1, 1), ZIndex = z + 1 })
	HS.press(b, p.OnClick, { Hover = p.Hover or 1.05, Press = 0.94, Sound = p.Sound })
	return { B = b, T = t, G = grad }
end
local function restyle(pl, pal, label)
	pl.B.BackgroundColor3 = pal.Rim
	pl.G.Color = CS(pal.Top0, pal.Top1)
	local st = pl.T:FindFirstChildOfClass("UIStroke")
	if st then st.Color = pal.Ink end
	if label then pl.T.Text = label end
end

------------------------------------------------------------------ build
function LoadoutHS:_build()
	local gui = new("ScreenGui", { Name = "VantageLoadoutHS", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	self.Gui = gui
	-- stage background (fills the screen at any aspect)
	local bg = new("Frame", { Name = "Stage", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 1 }, gui)
	new("UIGradient", { Rotation = 115, Color = CS({ CK(0, C.Bg0), CK(0.55, RGB(9, 8, 22)), CK(1, C.Bg1) }) }, bg)
	-- painted armory, scaled to cover the screen (see _fit) with a slow drift
	local art = new("Frame", { Name = "Art", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(ART_W, ART_H), ZIndex = 1 }, bg)
	new("ImageLabel", { Name = "L", BackgroundTransparency = 1, Image = ART_L, Size = S(0.5, 1), ZIndex = 1 }, art)
	new("ImageLabel", { Name = "R", BackgroundTransparency = 1, Image = ART_R, Position = S(0.5, 0), Size = S(0.5, 1), ZIndex = 1 }, art)
	self.Art = art
	-- spotlight pool pulse + motes drifting up the light beam
	self.Pool = new("ImageLabel", { Name = "Pool", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(190, 150, 255), ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.79), Size = S(0.36, 0.16), ZIndex = 1 }, art)
	self.Motes = {}
	for _ = 1, 36 do
		local m = new("Frame", { BackgroundColor3 = RGB(220, 200, 255), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(4, 4), ZIndex = 1 }, art)
		HS.corner(m, UDim.new(0.5, 0))
		table.insert(self.Motes, { F = m, X = 0.42 + math.random() * 0.16, P = math.random(), Spd = 0.03 + math.random() * 0.05, Sz = 2 + math.random() * 4 })
	end
	local vig = new("Frame", { Name = "Vignette", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 1 }, bg)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.55), NK(0.25, 1), NK(0.75, 1), NK(1, 0.4) }) }, vig)
	self.Sweep = new("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 1 }, bg)
	self.SweepG = new("UIGradient", { Rotation = 34, Offset = V2(-1, 0), Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.5, 0.94), NK(0.58, 1), NK(1, 1) }) }, self.Sweep)

	local root = new("Frame", { Name = "Root", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1920, 1080), BackgroundTransparency = 1, ZIndex = 2 }, gui)
	self.Root = root
	self.Scale = new("UIScale", {}, root)

	-- the gun on show
	-- rarity aura behind the gun (same textures as the crate reveal), stronger for higher tiers
	local aura = new("Frame", { Name = "Aura", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(GUN_X, GUN_Y), Size = O(10, 10), ZIndex = 2 }, root)
	local function layer(name, img, size, tr)
		return new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = img, ImageTransparency = tr, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(size[1], size[2]), ZIndex = 2 }, aura)
	end
	self.Aura = {
		Bloom = layer("Bloom", BLOOM, { 1150, 700 }, 0.5),
		RaysA = layer("RaysA", AURA.RaysA, { 1250, 1250 }, 0.78),
		RaysB = layer("RaysB", AURA.RaysB, { 1050, 1050 }, 0.82),
		Ring = layer("Ring", AURA.Ring, { 760, 760 }, 0.8),
		Bokeh = layer("Bokeh", AURA.Bokeh, { 1000, 640 }, 0.75),
		Core = layer("Core", BLOOM, { 620, 300 }, 0.45),
		Embers = {},
	}
	for _ = 1, 30 do
		local e = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(6, 6), ZIndex = 3 }, aura)
		HS.corner(e, UDim.new(0.5, 0))
		table.insert(self.Aura.Embers, { F = e, X = (math.random() - 0.5) * 860, P = math.random(), Spd = 0.18 + math.random() * 0.3, Sz = 3 + math.random() * 6, Sway = math.random() * 6.28 })
	end
	self.AuraLevel, self.AuraCol, self.AuraChroma = 0.5, RGB(150, 120, 255), nil
	self.GunHolder = new("Frame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(GUN_X, GUN_Y), Size = O(980, 560), ZIndex = 3 }, root)
	-- drag anywhere on the gun to spin it (full 360, with a throw)
	local hit = new("TextButton", { Name = "SpinHit", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(GUN_X, GUN_Y), Size = O(860, 500), ZIndex = 4 }, root)
	self.SpinHit = hit
	self.Spin = { Yaw = 0, Pitch = 0, V = 0, Drag = false, X = 0, Y = 0, T = 0 }
	hit.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			local sp = self.Spin
			sp.Drag, sp.X, sp.Y, sp.T, sp.V = true, io.Position.X, io.Position.Y, os.clock(), 0
		end
	end)
	local UIS = game:GetService("UserInputService")
	UIS.InputChanged:Connect(function(io)
		local sp = self.Spin
		if not sp.Drag then return end
		if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
			local dx, dy, now = io.Position.X - sp.X, io.Position.Y - sp.Y, os.clock()
			sp.Yaw += dx * 0.012
			sp.Pitch = math.clamp(sp.Pitch + dy * 0.006, -0.5, 0.5)
			sp.V = math.clamp(dx * 0.012 / math.max(now - sp.T, 1 / 120), -14, 14)
			sp.X, sp.Y, sp.T = io.Position.X, io.Position.Y, now
		end
	end)
	UIS.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			self.Spin.Drag = false
		end
	end)
	self.SpinHint = text(root, { Name = "SpinHint", Text = "Drag to spin", Font = HS.MontX, TextSize = 18, Stroke = 2, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(GUN_X, GUN_Y + 250), Size = O(240, 24), ZIndex = 6 })

	-- preset cards
	for i = 1, Presets.PerPage do
		self.Cards[i] = self:_card(root, i)
	end
	-- page arrows
	local function arrow(x, up)
		local b = new("TextButton", { Name = if up then "PageUp" else "PageDown", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(x, 849), Size = O(60, 60), ZIndex = 6 }, root)
		local shaft = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, if up then 8 else -8), Size = O(18, 26), ZIndex = 6 }, b)
		HS.stroke(shaft, 3, C.Ink)
		local head = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, if up then -8 else 8), Size = O(30, 30), Rotation = 45, ZIndex = 7 }, b)
		HS.stroke(head, 3, C.Ink)
		new("UIGradient", { Rotation = if up then 45 else 225, Transparency = NS({ NK(0, 0), NK(0.5, 0), NK(0.501, 1), NK(1, 1) }) }, head)
		HS.press(b, function()
			local n = math.ceil(Presets.Count / Presets.PerPage)
			self.Page = math.clamp(self.Page + (if up then -1 else 1), 1, n)
			self:_refresh()
		end, { Hover = 1.1, Press = 0.9, Sound = "Click" })
		return b
	end
	arrow(67, false)
	arrow(324, true)
	self.PageText = text(root, { Name = "Page", Text = "Page 1/2", TextSize = 34, Stroke = 3.2, AnchorPoint = V2(0.5, 0.5), Position = O(196, 849), Size = O(180, 44) })

	-- BACK
	local back = new("TextButton", { Name = "Back", Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(40, 4, 8), Position = O(43, 922), Size = O(184, 56), ZIndex = 6 }, root)
	HS.corner(back, 6)
	local bf = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(3, 3), Size = UDim2.new(1, -6, 1, -8), ClipsDescendants = true, ZIndex = 6 }, back)
	HS.corner(bf, 4)
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(255, 96, 100)), CK(0.5, RGB(226, 40, 52)), CK(1, RGB(176, 18, 30)) }) }, bf)
	for i = 0, 2 do
		new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, 120 + i * 18, 0.5, 0), Size = UDim2.new(0, 7, 1.6, 0), Rotation = 24, ZIndex = 6 }, bf)
	end
	text(back, { Text = "BACK", TextSize = 40, Stroke = 4, StrokeColor = RGB(50, 4, 8), Position = O(0, -2), Size = S(1, 1), ZIndex = 7 })
	HS.press(back, function() self:_back() end, { Hover = 1.05, Press = 0.94, Sound = "Click" })

	-- REQ top right
	local rq = new("Frame", { Name = "Req", BackgroundColor3 = RGB(10, 8, 20), BackgroundTransparency = 0.15, AnchorPoint = V2(1, 0), Position = O(1900, 14), Size = O(300, 48), ZIndex = 6 }, root)
	HS.corner(rq, UDim.new(0.5, 0))
	HS.stroke(rq, 3, RGB(30, 24, 50))
	new("ImageLabel", { BackgroundTransparency = 1, Image = HS.Img.Req, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(28, 24), Size = O(56, 56), ZIndex = 7 }, rq)
	self.ReqText = text(rq, { Text = "0", TextSize = 34, Stroke = 3.2, X = Enum.TextXAlignment.Left, Position = O(62, 0), Size = O(228, 48), ZIndex = 7 })

	self:_buildStats(root)
	self:_buildPicker(root)
end

function LoadoutHS:_card(root, i)
	local y = CARD_Y + (i - 1) * CARD_P
	local glow = new("ImageLabel", { Name = "CardGlow" .. i, BackgroundTransparency = 1, Image = GLOW, ImageColor3 = C.Sel, ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.5, Position = O(CARD_X - 40, y - 40), Size = O(CARD_W + 80, CARD_H + 80), ZIndex = 3 }, root)
	local card = new("TextButton", { Name = "Preset" .. i, Text = "", AutoButtonColor = false, BackgroundColor3 = C.RimDark, Position = O(CARD_X, y), Size = O(CARD_W, CARD_H), ZIndex = 4 }, root)
	HS.corner(card, 14)
	local inner = new("Frame", { Name = "Inner", BackgroundColor3 = C.Card, Position = O(6, 6), Size = UDim2.new(1, -12, 1, -12), ZIndex = 4 }, card)
	HS.corner(inner, 10)
	new("UIGradient", { Rotation = 90, Color = CS(RGB(26, 18, 46), RGB(10, 7, 20)) }, inner)
	local rim = HS.stroke(inner, 3.5, C.Rim)
	local rimGrad = new("UIGradient", { Enabled = false, Rotation = 0, Color = CS({ CK(0, RGB(130, 210, 255)), CK(0.5, RGB(40, 130, 255)), CK(1, RGB(130, 210, 255)) }) }, rim)
	local rec = { Card = card, Inner = inner, Rim = rim, RimGrad = rimGrad, Glow = glow, Tiles = {}, Index = nil }
	-- 3 gun tiles
	local tw = math.floor((CARD_W - 12 - 16 - TILE_GAP * 2) / 3)
	for s = 1, Presets.Slots do
		local t = new("TextButton", { Name = "Slot" .. s, Text = "", AutoButtonColor = false, BackgroundColor3 = C.Tile, Position = O(8 + (s - 1) * (tw + TILE_GAP), TILE_Y - 6), Size = O(tw, TILE_H), ZIndex = 5 }, inner)
		HS.corner(t, 8)
		HS.stroke(t, 2.5, RGB(70, 62, 96))
		new("UIGradient", { Rotation = 90, Color = CS(RGB(30, 22, 52), RGB(14, 10, 26)) }, t)
		local vp = new("ViewportFrame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(tw - 6, TILE_H - 6), ZIndex = 6 }, t)
		-- 2026-11-17: guns not unlocked yet (Arsenal Crates) show a lock; locked slots are skipped in a match
		local lock = new("Frame", { Name = "Lock", BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, Size = S(1, 1), Visible = false, ZIndex = 7 }, t)
		HS.corner(lock, 8)
		text(lock, { Text = "LOCKED", TextSize = 18, Stroke = 2, Color = RGB(255, 196, 90), Size = S(1, 1), ZIndex = 8 })
		local tile = { B = t, VP = vp, Id = nil, Lock = lock }
		t.MouseEnter:Connect(function()
			if rec.Index then self.Hover = rec.Index .. ":" .. s self:_show(tile.Id) end
		end)
		t.MouseLeave:Connect(function()
			if self.Hover == (rec.Index or 0) .. ":" .. s then self.Hover = nil self:_show(nil) end
		end)
		HS.press(t, function()
			if rec.Index then
				self:_select(rec.Index)
				self:_openPicker(rec.Index, s)
			end
		end, { Hover = 1.06, Press = 0.94, Sound = "Select" })
		rec.Tiles[s] = tile
	end
	-- 5 kit squares: grenade, shield pack, grappling hook, two empty
	rec.Squares = {}
	for k = 1, 5 do
		local sq = new("Frame", { Name = "Kit" .. k, BackgroundColor3 = C.Tile, Position = O(8 + (k - 1) * SQ_P, SQ_Y - 6), Size = O(SQ, SQ), ZIndex = 5 }, inner)
		HS.corner(sq, 8)
		HS.stroke(sq, 2.5, RGB(70, 62, 96))
		new("UIGradient", { Rotation = 90, Color = CS(RGB(30, 22, 52), RGB(14, 10, 26)) }, sq)
		local img = new("ImageLabel", { BackgroundTransparency = 1, Image = ({ ICON.Grenade, ICON.Pack, ICON.Hook, ICON.Empty, ICON.Empty })[k], ImageTransparency = if k >= 4 then 0.15 else 0, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.84, 0.84), ZIndex = 6 }, sq)
		rec.Squares[k] = { F = sq, I = img }
		if k == 4 then -- 2026-11-19: equipped Signature (live 3D), opens the SIGNATURE tab
			img.Visible = false
			rec.Squares[k].VP = new("ViewportFrame", { Name = "SigVP", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 6 }, sq)
			local artI = new("ImageLabel", { Name = "SigArt", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Size = S(1, 1), ZIndex = 5, Visible = false }, sq)
			local sqc = sq:FindFirstChildOfClass("UICorner")
			if sqc then new("UICorner", { CornerRadius = sqc.CornerRadius }, artI) end
			rec.Squares[k].Art = artI
			rec.Squares[k].Rim = sq:FindFirstChildOfClass("UIStroke")
			local hit = new("TextButton", { Name = "PickSig", Text = "", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 7 }, sq)
			HS.press(hit, function()
				if rec.Index then
					self:_select(rec.Index)
					self:_openPicker(rec.Index, "Sig")
				end
			end, { Hover = 1.08, Press = 0.94, Sound = "Select" })
		end
		if k == 2 or k == 3 then -- 2026-11-18: Shield Pack / Grappling Hook squares open the EQUIPMENT tab
			local hit = new("TextButton", { Name = "Pick", Text = "", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 7 }, sq)
			HS.press(hit, function()
				if rec.Index then
					self:_select(rec.Index)
					self:_openPicker(rec.Index, "Equip")
				end
			end, { Hover = 1.08, Press = 0.94, Sound = "Select" })
		end
	end
	-- EDIT
	rec.Edit = pill(root, { Name = "Edit" .. i, Text = "EDIT", TextSize = 32, Pal = PAL.Steel, Position = O(387, y + 50), Size = O(138, 54), Sound = "Click", OnClick = function()
		if rec.Index then
			self:_select(rec.Index)
			self:_openPicker(rec.Index, 1)
		end
	end })
	HS.press(card, function()
		if rec.Index then self:_select(rec.Index) end
	end, { Hover = 1.02, Press = 0.97, Sound = "Select" })
	return rec
end

function LoadoutHS:_buildStats(root)
	local p = new("Frame", { Name = "Stats", BackgroundColor3 = RGB(12, 9, 24), BackgroundTransparency = 0.08, Position = O(1556, 508), Size = O(330, 362), ZIndex = 4 }, root)
	HS.corner(p, 22)
	HS.stroke(p, 4, RGB(90, 70, 150))
	new("UIGradient", { Rotation = 90, Color = CS(RGB(30, 20, 56), RGB(10, 7, 20)) }, p)
	self.StatsTitle = text(p, { Text = "", TextSize = 28, Stroke = 3, Position = O(16, 12), Size = O(298, 34), X = Enum.TextXAlignment.Left, ZIndex = 5 })
	self.StatsClass = text(p, { Text = "", Font = HS.MontX, TextSize = 17, Stroke = 1.8, Color = C.Muted, Position = O(16, 46), Size = O(298, 22), X = Enum.TextXAlignment.Left, ZIndex = 5 })
	self.GunSkin = text(p, { Name = "Skin", Text = "", TextSize = 22, Stroke = 2.4, Position = O(16, 70), Size = O(298, 28), X = Enum.TextXAlignment.Left, ZIndex = 5 })
	self.GunSkinGrad = new("UIGradient", { Enabled = false }, self.GunSkin)
	self.Bars = {}
	for i, n in { "DAMAGE", "FIRE RATE", "RANGE", "MOBILITY" } do
		local y = 112 + (i - 1) * 54
		text(p, { Text = n, Font = HS.MontX, TextSize = 17, Stroke = 1.8, Position = O(16, y), Size = O(200, 22), X = Enum.TextXAlignment.Left, ZIndex = 5 })
		local val = text(p, { Text = "", TextSize = 20, Stroke = 2, Position = O(214, y), Size = O(100, 22), X = Enum.TextXAlignment.Right, ZIndex = 5 })
		local track = new("Frame", { BackgroundColor3 = RGB(36, 28, 60), Position = O(16, y + 26), Size = O(298, 14), ZIndex = 5 }, p)
		HS.corner(track, UDim.new(0.5, 0))
		local fill = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(0, 1), ZIndex = 6 }, track)
		HS.corner(fill, UDim.new(0.5, 0))
		new("UIGradient", { Color = CS(RGB(90, 200, 255), RGB(170, 110, 255)) }, fill)
		self.Bars[i] = { Fill = fill, Val = val, Target = 0, Cur = 0 }
	end
	self.StatsMag = text(p, { Text = "", Font = HS.MontX, TextSize = 18, Stroke = 1.8, Color = C.Muted, Position = O(16, 328), Size = O(298, 24), X = Enum.TextXAlignment.Left, ZIndex = 5 })
	-- normalisers across every gun
	local mx = { Damage = 1, RPM = 1, Range = 1 }
	for _, id in Presets.Guns do
		local w = WConfig.Weapons[id]
		local dmg = (w.Damage or 0) * ((w.Pellet and w.Pellet.Count) or 1)
		mx.Damage = math.max(mx.Damage, dmg)
		mx.RPM = math.max(mx.RPM, w.RPM or 0)
		mx.Range = math.max(mx.Range, w.FalloffEnd or w.MaxRange or 0)
	end
	self.Max = mx
end

-- 2026-11-18: the picker lists scroll inside plain Frames (ViewportFrames don't draw / redraw inside a
-- ScrollingFrame): wheel or drag the bar, the content glides to the target, panel-coloured masks above and
-- below the window hide the overflow, and cards that would stick out of the panel are hidden.
local UIS = game:GetService("UserInputService")
local WIN_Y, WIN_H, PANEL_TOP, PANEL_BOTTOM = 128, 500, 6, 754
local function makeScroller(p, name, contentH)
	local win = new("Frame", { Name = name, BackgroundTransparency = 1, Position = O(26, WIN_Y), Size = O(1018, WIN_H), ZIndex = 22 }, p)
	local content = new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = O(1000, contentH), ZIndex = 22 }, win)
	local track = new("Frame", { Name = "Track", BackgroundColor3 = RGB(40, 28, 70), BorderSizePixel = 0, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -2, 0, 4), Size = UDim2.new(0, 8, 1, -8), ZIndex = 22 }, win)
	HS.corner(track, UDim.new(0.5, 0))
	local thumb = new("Frame", { Name = "Thumb", BackgroundColor3 = RGB(170, 120, 255), BorderSizePixel = 0, Size = S(1, 0.3), ZIndex = 22 }, track)
	HS.corner(thumb, UDim.new(0.5, 0))
	local st = { H = contentH, Target = 0, Cur = 0 }
	local function maxOff() return math.max(0, st.H - WIN_H) end
	local function layout()
		content.Position = O(0, -math.floor(st.Cur + 0.5))
		local m = maxOff()
		track.Visible = m > 0
		local frac = WIN_H / math.max(st.H, WIN_H)
		thumb.Size = S(1, frac)
		thumb.Position = S(0, if m > 0 then (st.Cur / m) * (1 - frac) else 0)
		for _, c in content:GetChildren() do
			if c:IsA("GuiObject") then
				local y = WIN_Y + c.Position.Y.Offset - st.Cur
				c.Visible = y >= PANEL_TOP and y + c.Size.Y.Offset <= PANEL_BOTTOM
			end
		end
	end
	local conn
	local function run()
		if conn then return end
		conn = RunService.RenderStepped:Connect(function(dt)
			st.Cur += (st.Target - st.Cur) * math.min(1, dt * 18)
			if math.abs(st.Target - st.Cur) < 0.5 then
				st.Cur = st.Target
				conn:Disconnect()
				conn = nil
			end
			layout()
		end)
	end
	local function scrollTo(y)
		st.Target = math.clamp(y, 0, maxOff())
		run()
	end
	local function shown()
		return win.Visible and p.Parent and p.Parent.Visible
	end
	local function over(pos)
		local a, s = win.AbsolutePosition, win.AbsoluteSize
		return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
	end
	local drag = nil
	thumb.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			drag = { Y = io.Position.Y, Start = st.Target }
		end
	end)
	UIS.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then drag = nil end
	end)
	UIS.InputChanged:Connect(function(io)
		if not shown() then return end
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			if over(UIS:GetMouseLocation()) then scrollTo(st.Target - io.Position.Z * 166) end
		elseif drag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			local trackPx = track.AbsoluteSize.Y * (1 - WIN_H / math.max(st.H, WIN_H))
			if trackPx > 1 then
				scrollTo(drag.Start + (io.Position.Y - drag.Y) / trackPx * maxOff())
			end
		end
	end)
	win:GetPropertyChangedSignal("Visible"):Connect(layout)
	local function setH(h)
		st.H = h
		content.Size = O(1000, h)
		st.Target = math.clamp(st.Target, 0, maxOff())
		st.Cur = st.Target
		layout()
	end
	layout()
	return win, content, setH, layout
end


function LoadoutHS:_buildPicker(root)
	local ov = new("TextButton", { Name = "Picker", Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, Size = O(1920, 1080), Visible = false, ZIndex = 20 }, root)
	self.Picker = ov
	local p = new("Frame", { Name = "Panel", BackgroundColor3 = RGB(18, 10, 36), AnchorPoint = V2(0.5, 0.5), Position = O(1010, 540), Size = O(1060, 760), ZIndex = 21 }, ov)
	HS.corner(p, 24)
	local st = HS.stroke(p, 5, WHITE)
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(214, 160, 255)), CK(0.5, RGB(140, 70, 255)), CK(1, RGB(214, 160, 255)) }) }, st)
	new("Frame", { BackgroundColor3 = RGB(18, 10, 36), BorderSizePixel = 0, Position = O(26, -10), Size = O(520, 20), ZIndex = 22 }, p)
	self.PickTitle = text(p, { Text = "EDIT LOADOUT", TextSize = 58, Stroke = 5, X = Enum.TextXAlignment.Left, Fit = false, Position = O(32, -44), Size = O(600, 74), ZIndex = 23 })
	-- slot tabs
	self.PickTabs = {}
	for s = 1, Presets.Slots do
		self.PickTabs[s] = pill(p, { Name = "Tab" .. s, Text = Presets.SlotNames[s], TextSize = 26, Pal = PAL.Steel, Position = O(36 + (s - 1) * 202, 56), Size = O(194, 56), Z = 22, Sound = "Tab", OnClick = function()
			self.PickSlot = s
			self:_renderPicker()
		end })
	end
	-- gun grid: 3 columns in a scrolling frame (2026-11-18: 12 guns no longer fit a 3 x 2 grid)
	local scroll, gunContent, _, gunLayout = makeScroller(p, "GunScroll", math.ceil(#Presets.Guns / 4) * 166 + 8)


	self.GunScroll = scroll
	self.PickCards = {}
	for i, id in Presets.Guns do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local b = new("TextButton", { Name = id, Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(8, 4, 16), Position = O(10 + col * 248, 4 + row * 166), Size = O(238, 156), ZIndex = 22 }, gunContent)
		HS.corner(b, 16)
		local rim = HS.stroke(b, 4, RGB(90, 80, 120))
		local face = new("Frame", { BackgroundColor3 = WHITE, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 22 }, b)
		HS.corner(face, 12)
		local fg = new("UIGradient", { Rotation = 90 }, face)
		local vp = new("ViewportFrame", { Name = "Gun", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 60), Size = O(222, 96), ZIndex = 24 }, b)
		local name = text(b, { Text = "", TextSize = 21, Stroke = 2.4, Position = O(12, 106), Size = O(214, 24), X = Enum.TextXAlignment.Left, ZIndex = 25 })
		local cls = text(b, { Text = titleCase(WConfig.Weapons[id].Class or ""), Font = HS.MontX, TextSize = 14, Stroke = 1.6, Color = C.Muted, Position = O(12, 130), Size = O(200, 18), X = Enum.TextXAlignment.Left, ZIndex = 25 })
		local tag = new("Frame", { Name = "Tag", BackgroundColor3 = RGB(60, 140, 255), AnchorPoint = V2(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = O(100, 24), Visible = false, ZIndex = 26 }, b)
		HS.corner(tag, 7)
		HS.stroke(tag, 2, RGB(8, 22, 64))
		local tagT = text(tag, { Text = "", TextSize = 14, Stroke = 1.6, StrokeColor = RGB(8, 22, 64), Size = S(1, 1), ZIndex = 27 })
		local lock = new("Frame", { Name = "Lock", BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, Size = S(1, 1), Visible = false, ZIndex = 28 }, b)
		HS.corner(lock, 16)
		local lockT = text(lock, { Text = "LOCKED", TextSize = 28, Stroke = 3, Color = RGB(255, 196, 90), Position = O(0, -14), Size = S(1, 1), ZIndex = 29 })
		text(lock, { Text = "Unlock from Arsenal Crates", Font = HS.MontX, TextSize = 14, Stroke = 1.6, Color = C.Muted, Position = O(0, 16), Size = S(1, 1), ZIndex = 29 })
		local rec = { B = b, Rim = rim, FaceG = fg, VP = vp, Name = name, Cls = cls, Tag = tag, TagT = tagT, Id = id, Skin = nil, Lock = lock, LockT = lockT }
		b.MouseEnter:Connect(function() self:_show(id) end)
		b.MouseLeave:Connect(function() self:_show(nil) end)
		HS.press(b, function()
			if not (self.PickIndex and self.PickSlot) then return end
			if not Presets.Owns(player, id) then
				HS.sound("Deny")
				local sc = lockT:FindFirstChild("Pop") or new("UIScale", { Name = "Pop" }, lockT)
				sc.Scale = 1.25
				HS.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				return
			end
			local ev = Remotes:FindFirstChild("LoadoutPreset")
			if ev then ev:FireServer("Set", self.PickIndex, self.PickSlot, id) end
			-- optimistic local swap so the picker answers instantly
			local list = self.Data[self.PickIndex]
			local at = table.find(list, id)
			if at then list[at] = list[self.PickSlot] end
			list[self.PickSlot] = id
			self:_renderCards()
			self:_renderPicker()
		end, { Hover = 1.04, Press = 0.96, Sound = "Select" })
		self.PickCards[id] = rec
	end
	-- 2026-11-18: EQUIPMENT tab (Shield Pack + Grappling Hook), also opened from the kit squares
	self.EquipTab = pill(p, { Name = "TabEquip", Text = "EQUIPMENT", TextSize = 23, Pal = PAL.Steel, Position = O(36 + 3 * 202, 56), Size = O(194, 56), Z = 22, Sound = "Tab", OnClick = function()
		self.PickSlot = "Equip"
		self:_renderPicker()
	end })
	local es, esContent, setEsH, esLayout = makeScroller(p, "EquipScroll", 0)
	es.Visible = false
	self.EquipScroll = es
	self.EquipCards = {}
	local ey = 4
	for _, sec in { { "Pack", "SHIELD PACK" }, { "Hook", "GRAPPLING HOOK" } } do
		local slot = sec[1]
		text(esContent, { Text = sec[2], TextSize = 26, Stroke = 2.6, X = Enum.TextXAlignment.Left, Position = O(12, ey), Size = O(600, 32), ZIndex = 23 })
		ey += 40
		local items = EquipCatalog.List(slot)
		for i, it in items do
			local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
			local b = new("TextButton", { Name = it.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(8, 4, 16), Position = O(10 + col * 248, ey + row * 166), Size = O(238, 156), ZIndex = 22 }, esContent)
			HS.corner(b, 16)
			local rim = HS.stroke(b, 4, RGB(90, 80, 120))
			local face = new("Frame", { BackgroundColor3 = WHITE, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 22 }, b)
			HS.corner(face, 12)
			local fg = new("UIGradient", { Rotation = 90 }, face)
			local vp = new("ViewportFrame", { Name = "Item", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 60), Size = O(222, 96), ZIndex = 24 }, b)
			text(b, { Text = it.Name or it.Id, TextSize = 20, Stroke = 2.4, Position = O(12, 106), Size = O(214, 24), X = Enum.TextXAlignment.Left, ZIndex = 25 })
			local rar = text(b, { Text = string.upper(it.Rarity or ""), Font = HS.MontX, TextSize = 14, Stroke = 1.6, Color = C.Muted, Position = O(12, 130), Size = O(214, 18), X = Enum.TextXAlignment.Left, ZIndex = 25 })
			local tag = new("Frame", { Name = "Tag", BackgroundColor3 = RGB(60, 140, 255), AnchorPoint = V2(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = O(100, 24), Visible = false, ZIndex = 26 }, b)
			HS.corner(tag, 7)
			HS.stroke(tag, 2, RGB(8, 22, 64))
			text(tag, { Text = "EQUIPPED", TextSize = 15, Stroke = 1.8, StrokeColor = RGB(8, 22, 64), Size = S(1, 1), ZIndex = 27 })
			local lock = new("Frame", { Name = "Lock", BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, Size = S(1, 1), Visible = false, ZIndex = 28 }, b)
			HS.corner(lock, 16)
			local lockT = text(lock, { Text = "LOCKED", TextSize = 30, Stroke = 3, Color = RGB(255, 196, 90), Position = O(0, -14), Size = S(1, 1), ZIndex = 29 })
			text(lock, { Text = "From Equipment Crates", Font = HS.MontX, TextSize = 15, Stroke = 1.6, Color = C.Muted, Position = O(0, 18), Size = S(1, 1), ZIndex = 29 })
			local rec = { B = b, Rim = rim, FaceG = fg, VP = vp, Tag = tag, Lock = lock, Rar = rar, Id = it.Id, Slot = slot, Item = it }
			HS.press(b, function()
				if not EquipCatalog.Owns(player, it.Id) then
					HS.sound("Deny")
					local sc = lockT:FindFirstChild("Pop") or new("UIScale", { Name = "Pop" }, lockT)
					sc.Scale = 1.25
					HS.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
					return
				end
				local ev = Remotes:FindFirstChild("EquipmentEquip")
				if ev then ev:FireServer(slot, it.Id) end
				self.EquipPending = { [slot] = it.Id }
				self:_renderPicker()
				self:_renderCards()
			end, { Hover = 1.04, Press = 0.96, Sound = "Select" })
			self.EquipCards[it.Id] = rec
			b.MouseEnter:Connect(function()
				self.EquipHover, self.EquipLastSlot = it.Id, slot
				self:_equipStats()
			end)
			b.MouseLeave:Connect(function()
				if self.EquipHover == it.Id then
					self.EquipHover = nil
					self:_equipStats()
				end
			end)
		end
		ey += math.ceil(#items / 4) * 166 + 10
	end
	setEsH(ey)
	-- 2026-11-19: SIGNATURE tab (one Signature for every preset; Shift / L1 in a match)
	self.SigTab = pill(p, { Name = "TabSig", Text = "SIGNATURE", TextSize = 23, Pal = PAL.Steel, Position = O(36 + 4 * 202, 56), Size = O(194, 56), Z = 22, Sound = "Tab", OnClick = function()
		self.PickSlot = "Sig"
		self:_renderPicker()
	end })
	local sg, sgContent, setSgH, sgLayout = makeScroller(p, "SigScroll", 0)
	sg.Visible = false
	self.SigScroll, self.ClipSig = sg, sgLayout
	self.SigCards = {}
	for i, it in SigCat.List do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local b = new("TextButton", { Name = it.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(8, 4, 16), Position = O(10 + col * 248, 6 + row * 248), Size = O(238, 238), ZIndex = 22 }, sgContent)
		HS.corner(b, 16)
		local rim = HS.stroke(b, 4, hsv(it.Color, 0.6, 0.9))
		local rimG = new("UIGradient", { Enabled = false, Color = CS({ CK(0, WHITE), CK(0.25, it.Color), CK(0.5, WHITE), CK(0.75, it.Color), CK(1, WHITE) }) }, rim)
		local face = new("Frame", { BackgroundColor3 = WHITE, Position = O(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 22, ClipsDescendants = true }, b)
		HS.corner(face, 12)
		new("UIGradient", { Rotation = 90, Color = CS({ CK(0, hsv(it.Deep, 1, 0.62)), CK(0.55, hsv(it.Deep, 1.1, 0.26)), CK(1, RGB(10, 6, 18)) }) }, face)
		local living = makeLiving(face, it, 7, 22)
		local hasArt = (it.Art or "") ~= ""
		new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = it.Color, ImageTransparency = if hasArt then 0.62 else 0.35, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 86), Size = O(250, 200), ZIndex = 22 }, face)
		-- keep the name readable over busy art
		local shade = new("Frame", { Name = "Shade", BackgroundColor3 = BLACK, BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = S(0, 1), Size = S(1, 0.42), ZIndex = 22 }, face)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }) }, shade)
		-- diagonal sheen bands
		for k = 0, 1 do
			local band = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.9 + k * 0.04, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.62 + k * 0.16, 0, 0.42, 0), Size = O(24 - k * 10, 420), Rotation = 28, ZIndex = 22 }, face)
		end
		text(face, { Text = it.Num, Font = HS.MontX, TextSize = 64, Stroke = 0, Color = WHITE, X = Enum.TextXAlignment.Left, Position = O(12, -2), Size = O(120, 70), ZIndex = 22 }).TextTransparency = 0.78
		local vp = new("ViewportFrame", { Name = "Item", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 92), Size = O(226, 150), ZIndex = 24 }, b)
		new("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = BLACK, ImageTransparency = 0.3, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 96), Size = O(200, 150), ZIndex = 23 }, b)
		text(b, { Text = it.Name, TextSize = 26, Stroke = 2.6, Position = O(14, 168), Size = O(210, 30), X = Enum.TextXAlignment.Left, ZIndex = 25 })
		text(b, { Text = it.Title, Font = HS.MontX, TextSize = 14, Stroke = 1.6, Color = hsv(it.Color, 0.45, 1), Position = O(14, 198), Size = O(210, 20), X = Enum.TextXAlignment.Left, ZIndex = 25 })
		local tierC = SigCat.TierColor[it.Tier] or WHITE
		local tier = new("Frame", { Name = "Tier", BackgroundColor3 = tierC, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = O(104, 24), ZIndex = 26 }, b)
		HS.corner(tier, 7); HS.stroke(tier, 2, hsv(tierC, 1, 0.3))
		text(tier, { Text = it.Tier, TextSize = 14, Stroke = 1.6, StrokeColor = hsv(tierC, 1, 0.25), Size = S(1, 1), ZIndex = 27 })
		local tag = new("Frame", { Name = "Tag", BackgroundColor3 = RGB(60, 140, 255), AnchorPoint = V2(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = O(104, 24), Visible = false, ZIndex = 28 }, b)
		HS.corner(tag, 7); HS.stroke(tag, 2, RGB(8, 22, 64))
		text(tag, { Text = "EQUIPPED", TextSize = 15, Stroke = 1.8, StrokeColor = RGB(8, 22, 64), Size = S(1, 1), ZIndex = 29 })
		local lock = new("Frame", { Name = "Lock", BackgroundColor3 = BLACK, BackgroundTransparency = 0.38, Size = S(1, 1), Visible = false, ZIndex = 30 }, b)
		HS.corner(lock, 16)
		new("ImageLabel", { BackgroundTransparency = 1, Image = IchorIcon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, -62, 0.5, -10), Size = O(46, 46), ZIndex = 31 }, lock)
		local priceT = text(lock, { Text = commas(it.Price), TextSize = 32, Stroke = 3, Color = RGB(255, 226, 150), X = Enum.TextXAlignment.Left, AnchorPoint = V2(0, 0.5), Position = UDim2.new(0.5, -34, 0.5, -10), Size = O(150, 40), ZIndex = 31 })
		text(lock, { Text = "DAILY SHOP", Font = HS.MontX, TextSize = 15, Stroke = 1.6, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 18), Size = O(200, 20), ZIndex = 31 })
		local rec = { B = b, Rim = rim, RimG = rimG, VP = vp, Tag = tag, Tier = tier, Lock = lock, Price = priceT, Id = it.Id, Item = it, Living = living }
		HS.press(b, function()
			if not SigCat.Owns(player, it.Id) then
				HS.sound("Deny")
				local sc = priceT:FindFirstChild("Pop") or new("UIScale", { Name = "Pop" }, priceT)
				sc.Scale = 1.25
				HS.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				self.SigHover = it.Id
				self:_renderSigDetail()
				return
			end
			local ev = Remotes:FindFirstChild("SignatureEquip")
			if ev then ev:FireServer(it.Id) end
			self.SigPending = it.Id
			self:_renderSig()
			self:_renderCards()
		end, { Hover = 1.04, Press = 0.96, Sound = "Select" })
		b.MouseEnter:Connect(function() self.SigHover = it.Id; self:_renderSigDetail() end)
		b.MouseLeave:Connect(function() if self.SigHover == it.Id then self.SigHover = nil; self:_renderSigDetail() end end)
		self.SigCards[it.Id] = rec
	end
	setSgH(math.ceil(#SigCat.List / 4) * 248 + 12)

	-- detail card, right of the panel (like the equipment stats card)
	local d = new("Frame", { Name = "SigDetail", BackgroundColor3 = RGB(14, 8, 28), Position = O(1556, 150), Size = O(344, 690), Visible = false, ZIndex = 30 }, ov)
	HS.corner(d, 20)
	local dRim = HS.stroke(d, 4, WHITE)
	local dRimG = new("UIGradient", { Rotation = 90 }, dRim)
	local top = new("Frame", { BackgroundColor3 = WHITE, Position = O(6, 6), Size = O(332, 250), ZIndex = 30, ClipsDescendants = true }, d)
	HS.corner(top, 15)
	local topG = new("UIGradient", { Rotation = 90 }, top)
	local dLiving = makeLiving(top, SigCat.List[1], 12, 30)
	local bloom = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageTransparency = 0.25, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(380, 300), ZIndex = 30 }, top)
	local rays = new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageTransparency = 0.7, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.55), Size = O(420, 420), ZIndex = 30 }, top)
	local dNum = text(top, { Text = "01", Font = HS.MontX, TextSize = 90, Stroke = 0, X = Enum.TextXAlignment.Left, Position = O(12, -6), Size = O(200, 96), ZIndex = 30 })
	dNum.TextTransparency = 0.8
	local dVP = new("ViewportFrame", { BackgroundTransparency = 1, Position = O(6, 6), Size = O(332, 250), ZIndex = 31 }, d)
	local dTier = new("Frame", { BackgroundColor3 = WHITE, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = O(112, 26), ZIndex = 33 }, d)
	HS.corner(dTier, 8)
	local dTierS = HS.stroke(dTier, 2, BLACK)
	local dTierT = text(dTier, { Text = "", TextSize = 15, Stroke = 1.6, Size = S(1, 1), ZIndex = 34 })
	local dName = text(d, { Text = "", TextSize = 40, Stroke = 3.4, X = Enum.TextXAlignment.Left, Position = O(20, 266), Size = O(304, 46), ZIndex = 32 })
	local dTitle = text(d, { Text = "", Font = HS.MontX, TextSize = 17, Stroke = 1.6, X = Enum.TextXAlignment.Left, Position = O(20, 310), Size = O(304, 22), ZIndex = 32 })
	local dRole = text(d, { Text = "", Font = HS.MontX, TextSize = 15, Stroke = 1.4, Color = C.Muted, X = Enum.TextXAlignment.Left, Position = O(20, 336), Size = O(304, 20), ZIndex = 32 })
	local dBlurb = text(d, { Text = "", Font = HS.Mont or HS.MontX, TextSize = 16, Stroke = 1.2, Color = RGB(214, 210, 230), X = Enum.TextXAlignment.Left, Position = O(20, 364), Size = O(304, 96), ZIndex = 32 })
	dBlurb.TextWrapped = true; dBlurb.TextYAlignment = Enum.TextYAlignment.Top; dBlurb.TextScaled = false
	local rows = {}
	for k = 1, 3 do
		local r = new("Frame", { BackgroundColor3 = RGB(30, 22, 52), Position = O(16, 466 + (k - 1) * 42), Size = O(312, 36), ZIndex = 31 }, d)
		HS.corner(r, 9)
		local l = text(r, { Text = "", Font = HS.MontX, TextSize = 15, Stroke = 1.4, Color = C.Muted, X = Enum.TextXAlignment.Left, Position = O(12, 0), Size = O(150, 36), ZIndex = 32 })
		local v = text(r, { Text = "", TextSize = 18, Stroke = 1.8, X = Enum.TextXAlignment.Right, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = O(160, 36), ZIndex = 32 })
		rows[k] = { L = l, V = v }
	end
	local foot = new("Frame", { BackgroundColor3 = WHITE, Position = O(16, 600), Size = O(312, 74), ZIndex = 31 }, d)
	HS.corner(foot, 14)
	local footG = new("UIGradient", { Rotation = 90 }, foot)
	local footStroke = HS.stroke(foot, 2.5, BLACK)
	local footIcon = new("ImageLabel", { BackgroundTransparency = 1, Image = IchorIcon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = O(44, 44), ZIndex = 32 }, foot)
	local footT = text(foot, { Text = "", TextSize = 26, Stroke = 2.4, X = Enum.TextXAlignment.Left, Position = O(66, 8), Size = O(236, 32), ZIndex = 32 })
	local footS = text(foot, { Text = "", Font = HS.MontX, TextSize = 14, Stroke = 1.4, X = Enum.TextXAlignment.Left, Position = O(66, 40), Size = O(236, 22), ZIndex = 32 })
	self.SigDetail = d
	self.SigD = { Living = dLiving, Rim = dRimG, TopG = topG, Bloom = bloom, Rays = rays, Num = dNum, VP = dVP, Tier = dTier, TierS = dTierS, TierT = dTierT, Name = dName, Title = dTitle,
		Role = dRole, Blurb = dBlurb, Rows = rows, Foot = foot, FootG = footG, FootStroke = footStroke, FootIcon = footIcon, FootT = footT, FootS = footS }
	pill(p, { Name = "Done", Text = "DONE", TextSize = 34, Pal = PAL.Green, Z = 22, AnchorPoint = V2(1, 1), Position = O(1030, 744), Size = O(220, 64), OnClick = function()
		self:_closePicker()
	end })
	text(p, { Text = "Knife and grenade are always carried.  Keys: 1 knife, 2-4 guns.", Font = HS.MontX, TextSize = 18, Stroke = 1.8, Color = C.Muted, X = Enum.TextXAlignment.Left, Position = O(38, 704), Size = O(720, 26), ZIndex = 22 })
	-- masks: panel-coloured covers above and below the list window (the lists can't clip, see windowClip);
	-- everything else in the panel draws above them
	for _, m in { { 6, 122 }, { 628, 126 } } do
		local mk = new("Frame", { Name = "Mask", BackgroundColor3 = RGB(18, 10, 36), BorderSizePixel = 0, Position = O(6, m[1]), Size = O(1048, m[2]), ZIndex = 23 }, p)
		HS.corner(mk, 18)
	end
	for _, c in p:GetChildren() do
		if c:IsA("GuiObject") and c ~= scroll and c ~= es and c ~= self.SigScroll and c.Name ~= "Mask" then
			c.ZIndex = math.max(c.ZIndex, 24)
		end
	end
	self.ClipGuns = gunLayout
	self.ClipEquip = esLayout
	-- 2026-11-18: stats + ability of the hovered equipment (else the equipped item), right of the list
	self.EquipStats = EquipStatsUI.new(HS, ov, { Position = O(1556, 196), Width = 344, ZIndex = 30 })
	self.EquipStats.Frame.Visible = false
end

function LoadoutHS:_renderSig()
	if not self.SigCards then return end
	local cur = self.SigPending or SigCat.Equipped(player)
	local bal = player:GetAttribute("Ichor") or 0
	for id, rec in self.SigCards do
		local it = rec.Item
		local here = cur == id
		local owned = SigCat.Owns(player, id)
		rec.Rim.Color = if here then WHITE else hsv(it.Color, 0.6, 0.9)
		rec.Rim.Thickness = (if here then 5 else 4) * HS.Scale
		rec.RimG.Enabled = here
		rec.Tag.Visible = here
		rec.Tier.Visible = not here
		rec.Lock.Visible = not owned
		rec.Price.TextColor3 = if bal >= it.Price then RGB(150, 255, 160) else RGB(255, 226, 150)
		if rec.VP:GetAttribute("Key") ~= id then
			rec.VP:SetAttribute("Key", id)
			sigModel(rec.VP, it, 226 / 150, 1.05, 22)
		end
		rec.VP.Visible = true
	end
	self:_renderSigDetail()
end

function LoadoutHS:_renderSigDetail()
	local D = self.SigD
	if not D then return end
	local id = self.SigHover or self.SigPending or SigCat.Equipped(player)
	local it = SigCat.ById[id]
	if not it then return end
	local owned = SigCat.Owns(player, id)
	local equipped = (self.SigPending or SigCat.Equipped(player)) == id
	D.Rim.Color = CS({ CK(0, it.Color), CK(0.5, WHITE), CK(1, it.Color) })
	D.TopG.Color = CS({ CK(0, hsv(it.Deep, 1, 0.7)), CK(0.6, hsv(it.Deep, 1.1, 0.3)), CK(1, RGB(14, 8, 28)) })
	D.Bloom.ImageColor3 = it.Color
	LoadoutHS_setArt(D.Living, it.Art)
	D.Bloom.ImageTransparency = if (it.Art or "") ~= "" then 0.6 else 0.25
	for _, m in D.Living.Motes do m.F.BackgroundColor3 = it.Color:Lerp(WHITE, 0.45) end
	D.Rays.ImageColor3 = it.Color
	D.Num.Text = it.Num
	if D.VP:GetAttribute("Key") ~= id then
		D.VP:SetAttribute("Key", id)
		sigModel(D.VP, it, 332 / 250, 0.95, 24)
	end
	D.VP.Visible = true
	local tc = SigCat.TierColor[it.Tier] or WHITE
	D.Tier.BackgroundColor3 = tc
	D.TierS.Color = hsv(tc, 1, 0.3)
	D.TierT.Text = it.Tier
	D.Name.Text = it.Name
	D.Title.Text = it.Title
	D.Title.TextColor3 = hsv(it.Color, 0.45, 1)
	D.Role.Text = string.upper(it.Role)
	D.Blurb.Text = it.Blurb
	D.Blurb.TextSize = 16 -- the text() helper fits single lines; the blurb wraps
	D.Title.TextSize = 17
	for k, r in D.Rows do
		local st = it.Stats[k]
		r.L.Text = st and string.upper(st[1]) or ""
		r.V.Text = st and st[2] or ""
	end
	if owned then
		D.FootIcon.Visible = false
		D.FootT.Position = O(16, 8); D.FootS.Position = O(16, 40)
		D.FootT.Text = if equipped then "EQUIPPED" else "OWNED · CLICK TO EQUIP"
		D.FootT.TextSize = if equipped then 26 else 19
		D.FootS.Text = "SHIFT  ·  L1  to cast in a match"
		D.FootS.TextColor3 = RGB(220, 230, 255)
		D.FootG.Color = if equipped then CS(RGB(96, 176, 255), RGB(36, 96, 220)) else CS(RGB(70, 62, 110), RGB(34, 26, 60))
		D.FootStroke.Color = if equipped then RGB(14, 40, 110) else RGB(20, 14, 40)
	else
		local bal = player:GetAttribute("Ichor") or 0
		D.FootIcon.Visible = true
		D.FootT.Position = O(66, 8); D.FootS.Position = O(66, 40)
		D.FootT.TextSize = 26
		D.FootT.Text = commas(it.Price)
		D.FootS.Text = if bal >= it.Price then "Buy it when it's in the daily Shop" else ("You have " .. commas(bal) .. " Ichor")
		D.FootS.TextColor3 = RGB(255, 236, 200)
		D.FootG.Color = CS(RGB(120, 70, 20), RGB(60, 30, 8))
		D.FootStroke.Color = RGB(30, 14, 4)
	end
end

function LoadoutHS:_sigStep(dt)
	-- the gun stats card sits under the Signature detail card: hide it while the SIGNATURE tab is open
	if self.Picker and not self._statsF then self._statsF = self.Picker.Parent:FindFirstChild("Stats") end
	if self._statsF then
		local want = not (self.Picker.Visible and self.PickSlot == "Sig")
		if self._statsF.Visible ~= want then self._statsF.Visible = want end
	end
	if not (self.Picker and self.Picker.Visible and self.PickSlot == "Sig") then
		-- spin the little preset-card signatures slowly
		for _, rec in self.Cards do
			local sq = rec.Squares and rec.Squares[4]
			if sq and sq.VP then sigSway(sq.VP, os.clock(), 0.25) end
		end
		return
	end
	self.SigT = (self.SigT or 0) + dt
	local cur = self.SigPending or SigCat.Equipped(player)
	for id, rec in self.SigCards do
		animLiving(rec.Living, self.SigT, if id == self.SigHover then 1.6 else 1)
		sigSway(rec.VP, os.clock() + (rec.Living and rec.Living.Phase or 0), if id == self.SigHover then 0.45 else 0.22)
		if rec.RimG.Enabled then rec.RimG.Rotation = (self.SigT * 90) % 360 end
	end
	if self.SigD then
		sigSway(self.SigD.VP, os.clock() * 0.8, 0.3)
		if self.SigD.Blurb.TextSize ~= 16 then self.SigD.Blurb.TextSize = 16 end -- text() refits it to one line
		animLiving(self.SigD.Living, self.SigT, 0.8)
		self.SigD.Rays.Rotation = (self.SigT * 8) % 360
	end
end

function LoadoutHS:_equipStats()
	local card = self.EquipStats
	if not card then return end
	if not (self.Picker.Visible and self.PickSlot == "Equip") then
		card.Frame.Visible = false
		return
	end
	local slot = self.EquipLastSlot or "Pack"
	local id = self.EquipHover or (self.EquipPending and self.EquipPending[slot]) or EquipCatalog.Equipped(player, slot)
	card:Set(id)
end

------------------------------------------------------------------ data + render
function LoadoutHS:_data()
	self.Data = Presets.Decode(player:GetAttribute("LoadoutPresets"))
	local a = player:GetAttribute("LoadoutActive")
	self.Active = if type(a) == "number" then math.clamp(math.floor(a), 1, Presets.Count) else 1
end

function LoadoutHS:_req()
	local r = player:GetAttribute("REQ")
	self.ReqText.Text = num(if type(r) == "number" then r else 0)
end

function LoadoutHS:_tileGun(vp, id, key)
	if vp:GetAttribute("Key") == key then return end
	vp:SetAttribute("Key", key)
	local ok, m = pcall(K.weapon, id, skinOf(id))
	if ok and m then
		frame(vp, m, 0, 1.0, vp.Size.X.Offset / vp.Size.Y.Offset, 20)
	else
		vp:ClearAllChildren()
	end
end

function LoadoutHS:_renderCards()
	for i, rec in self.Cards do
		local idx = (self.Page - 1) * Presets.PerPage + i
		rec.Index = idx
		local list = self.Data[idx]
		local sel = idx == self.Active
		rec.Rim.Color = if sel then WHITE else C.Rim
		rec.Rim.Thickness = (if sel then 4.5 else 3.5) * HS.Scale
		rec.RimGrad.Enabled = sel
		rec.Glow.ImageTransparency = if sel then 0.45 else 1
		restyle(rec.Edit, if sel then PAL.Blue else PAL.Steel)
		for s, tile in rec.Tiles do
			tile.Id = list[s]
			self:_tileGun(tile.VP, list[s], list[s] .. "/" .. skinOf(list[s]))
			tile.Lock.Visible = not Presets.Owns(player, list[s])
		end
		-- kit squares: equipment colours from the equipped Shield Pack / Grappling Hook
		for k, slot in { [2] = "Pack", [3] = "Hook" } do
			local id = player:GetAttribute("Equip_" .. slot)
			local it = type(id) == "string" and EquipCatalog.ById[id]
			rec.Squares[k].I.ImageColor3 = if it and it.Color then (it.Color :: Color3):Lerp(WHITE, 0.45) else WHITE
		end
		local sq4 = rec.Squares[4]
		if sq4 and sq4.VP then
			local sid = self.SigPending or SigCat.Equipped(player)
			local sit = SigCat.ById[sid]
			if sq4.VP:GetAttribute("Key") ~= sid then
				sq4.VP:SetAttribute("Key", sid)
				sigModel(sq4.VP, sit, 1, 1.15, 24)
			end
			local hasArt = sit and (sit.Art or "") ~= ""
			sq4.Art.Image = hasArt and sit.Art or ""
			sq4.Art.Visible = hasArt
			sq4.VP.Visible = true
			if sq4.Rim and sit then sq4.Rim.Color = sit.Color end
			local g = sq4.F:FindFirstChildOfClass("UIGradient")
			if g and sit then g.Color = CS(hsv(sit.Deep, 1, 0.42), RGB(12, 8, 22)) end
		end
	end
	self.PageText.Text = "Page " .. self.Page .. "/" .. math.ceil(Presets.Count / Presets.PerPage)
end

function LoadoutHS:_refresh()
	self:_data()
	self:_req()
	self:_renderCards()
	if self.Picker.Visible then self:_renderPicker() end
	self:_show(nil)
end

-- big gun in the middle: the hovered gun, or the selected preset's first gun
function LoadoutHS:_show(id)
	id = id or (self.Data and self.Data[self.Active] and self.Data[self.Active][1])
	if not id then return end
	local key = id .. "/" .. skinOf(id)
	local def = skinDef(id)
	local rarity = def and def.Rarity
	local col = (rarity and Crate.TierColor[rarity]) or (def and def.Swatch) or RGB(120, 160, 255)
	self.GunSkin.Text = (def and def.Name or "Factory Issue") .. (if rarity and Crate.TierIndex[rarity] then "  |  " .. rarity else "")
	local ch = rarity and K.CHROMAS and K.CHROMAS[rarity]
	self.GunSkin.TextColor3 = if ch then WHITE else hsv(col, 0.7, 1)
	self.GunSkinGrad.Enabled = ch ~= nil
	if ch then self.GunSkinGrad.Color = ch.Grad end
	local ti = rarity and Crate.TierIndex[rarity]
	self.AuraLevel = if ti then 0.45 + ti * 0.11 else 0.35
	self.AuraCol = hsv(col, 1, 1)
	self.AuraChroma = ch
	self:_stats(id)
	if self.ShowKey == key then return end
	self.ShowKey = key
	local h = self.GunHolder
	h:ClearAllChildren()
	local ok, m = pcall(K.weapon, id, skinOf(id))
	if not (ok and m) then return end
	local vp = new("ViewportFrame", { Name = "View", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(980, 560), ZIndex = 5 }, h)
	local model, centre = frame(vp, m, 6, 1.2, 980 / 560, 24)
	local sils = {}
	for _, sp in { { hsv(col, 0.5, 1), 0.5, 1.05 }, { WHITE, 0.35, 1.012 } } do
		local v = silhouette(h, vp, sp[1], sp[2], sp[3], V2(0, 0), 4)
		local sm = v and v:FindFirstChildWhichIsA("Model")
		if sm then table.insert(sils, { M = sm, Base = sm:GetPivot() }) end
	end
	self.Spin.Yaw, self.Spin.Pitch, self.Spin.V = 0, 0, 0
	self.Gun = { Model = model, Base = model and model:GetPivot(), Centre = centre, VP = vp, T0 = os.clock(), Sils = sils }
end

function LoadoutHS:_stats(id)
	local w = WConfig.Weapons[id]
	self.StatsTitle.Text = titleCase(w.DisplayName or id)
	self.StatsClass.Text = titleCase(w.Class or "")
	local dmg = (w.Damage or 0) * ((w.Pellet and w.Pellet.Count) or 1)
	local range = w.FalloffEnd or w.MaxRange or 0
	local mob = math.clamp(((w.SpeedMultiplier or 1) - 0.8) / 0.3, 0.05, 1)
	local vals = {
		{ dmg / self.Max.Damage, tostring(math.floor(dmg + 0.5)) },
		{ (w.RPM or 0) / self.Max.RPM, tostring(w.RPM or 0) .. " rpm" },
		{ range / self.Max.Range, tostring(math.floor(range)) .. " st" },
		{ mob, string.format("%d%%", math.floor((w.SpeedMultiplier or 1) * 100 + 0.5)) },
	}
	for i, b in self.Bars do
		b.Target = math.clamp(vals[i][1], 0.04, 1)
		b.Val.Text = vals[i][2]
	end
	self.StatsMag.Text = if w.Heat then "Overheats instead of reloading" else ("Magazine " .. tostring(w.MagazineSize or 0) .. "  |  Reload " .. tostring(w.ReloadTime or 0) .. "s")
end

function LoadoutHS:_select(idx)
	if idx == self.Active then return end
	self.Active = idx
	local ev = Remotes:FindFirstChild("LoadoutPreset")
	if ev then ev:FireServer("Select", idx) end
	self:_renderCards()
	self:_show(nil)
end

function LoadoutHS:_openPicker(idx, slot)
	self.PickIndex, self.PickSlot = idx, slot
	self.Picker.Visible = true
	self:_renderPicker()
	task.defer(function()
		if self.ClipGuns then self.ClipGuns() end
		if self.ClipEquip then self.ClipEquip() end
		if self.ClipSig then self.ClipSig() end
	end)
end

function LoadoutHS:_closePicker()
	self.Picker.Visible = false
	self.PickIndex, self.PickSlot = nil, nil
	self.EquipHover = nil
	self.SigHover = nil
	if self.SigDetail then self.SigDetail.Visible = false end
	self:_equipStats()
	self:_show(nil)
end

function LoadoutHS:_renderPicker()
	local idx, slot = self.PickIndex, self.PickSlot
	if not idx then return end
	local list = self.Data[idx]
	self.PickTitle.Text = "EDIT LOADOUT " .. idx
	for s, t in self.PickTabs do restyle(t, if s == slot then PAL.Blue else PAL.Steel) end
	local sigMode = slot == "Sig"
	if self.SigTab then restyle(self.SigTab, if sigMode then PAL.Blue else PAL.Steel) end
	if self.SigScroll then self.SigScroll.Visible = sigMode end
	if self.SigDetail then self.SigDetail.Visible = sigMode end
	if sigMode then
		restyle(self.EquipTab, PAL.Steel)
		self.GunScroll.Visible = false
		self.EquipScroll.Visible = false
		self:_renderSig()
		self:_equipStats()
		return
	end
	local eqMode = slot == "Equip"
	restyle(self.EquipTab, if eqMode then PAL.Blue else PAL.Steel)
	self.GunScroll.Visible = not eqMode
	self.EquipScroll.Visible = eqMode
	if eqMode then
		for id, rec in self.EquipCards do
			local it = rec.Item
			local col = (it.Rarity and Crate.TierColor[it.Rarity]) or it.Color or RGB(120, 110, 170)
			local cur = (self.EquipPending and self.EquipPending[rec.Slot]) or EquipCatalog.Equipped(player, rec.Slot)
			local here = cur == id
			rec.Rim.Color = if here then RGB(90, 190, 255) else hsv(col, 0.6, 0.9)
			rec.FaceG.Color = CS({ CK(0, hsv(col, 1, 0.5)), CK(0.6, hsv(col, 1.1, 0.24)), CK(1, hsv(col, 1.1, 0.1)) })
			rec.Rar.TextColor3 = hsv(col, 0.55, 1)
			rec.Tag.Visible = here
			rec.Lock.Visible = not EquipCatalog.Owns(player, id)
			if rec.VP:GetAttribute("Key") ~= id then
				rec.VP:SetAttribute("Key", id)
				local ok, m = pcall(K.weapon, "Equipment", id)
				if ok and m then frame(rec.VP, m, 0, 1.0, 222 / 96, 22) end
			end
		end
		self:_equipStats()
		return
	end
	self:_equipStats()
	for id, rec in self.PickCards do
		local def = skinDef(id)
		local rarity = def and def.Rarity
		local col = (rarity and Crate.TierColor[rarity]) or RGB(120, 110, 170)
		local at = table.find(list, id)
		local here = at == slot
		rec.Rim.Color = if here then RGB(90, 190, 255) else hsv(col, 0.6, 0.9)
		rec.FaceG.Color = CS({ CK(0, hsv(col, 1, 0.5)), CK(0.6, hsv(col, 1.1, 0.24)), CK(1, hsv(col, 1.1, 0.1)) })
		rec.Name.Text = titleCase(WConfig.Weapons[id].ShortName or id)
		rec.Tag.Visible = at ~= nil
		rec.Tag.BackgroundColor3 = if here then RGB(60, 140, 255) else RGB(90, 80, 120)
		rec.TagT.Text = if here then "SELECTED" elseif at then Presets.SlotNames[at] else ""
		self:_tileGun(rec.VP, id, id .. "/" .. skinOf(id))
		rec.Lock.Visible = not Presets.Owns(player, id)
	end
end

------------------------------------------------------------------ animation
function LoadoutHS:_step(dt)
	if self._sigStep then self:_sigStep(dt) end
	local t = os.clock()
	self.SweepG.Offset = V2(-1 + ((t % 7) / 7) * 2, 0)
	-- background drift
	if self.ArtBase then
		local k = math.sin(t * 0.12)
		self.Art.Size = UDim2.fromOffset(self.ArtBase.X * (1.04 + 0.015 * k), self.ArtBase.Y * (1.04 + 0.015 * k))
		self.Art.Position = UDim2.new(0.5, math.sin(t * 0.09) * 10, 0.5, math.cos(t * 0.07) * 6)
	end
	self.Pool.ImageTransparency = 0.6 + math.sin(t * 1.6) * 0.1
	for _, m in self.Motes do
		local u = (m.P + t * m.Spd) % 1
		m.F.Position = UDim2.fromScale(m.X + math.sin(t * 0.8 + m.P * 6) * 0.006, 0.8 - u * 0.62)
		local s = m.Sz * (0.5 + 0.5 * math.sin(u * math.pi))
		m.F.Size = UDim2.fromOffset(s, s)
		m.F.BackgroundTransparency = 0.25 + 0.75 * (1 - math.sin(u * math.pi))
	end
	-- aura
	local A, lv = self.Aura, self.AuraLevel
	local col = if self.AuraChroma then K.chromaColor(self.AuraChroma, t, 0) else self.AuraCol
	local pulse = 0.5 + 0.5 * math.sin(t * 2.2)
	A.Bloom.ImageColor3, A.RaysA.ImageColor3, A.RaysB.ImageColor3 = col, col:Lerp(WHITE, 0.35), col:Lerp(WHITE, 0.6)
	A.Ring.ImageColor3, A.Bokeh.ImageColor3, A.Core.ImageColor3 = col:Lerp(WHITE, 0.3), col:Lerp(WHITE, 0.5), col:Lerp(WHITE, 0.55)
	A.Bloom.ImageTransparency = 1 - lv * (0.62 + pulse * 0.12)
	A.Core.ImageTransparency = 1 - lv * (0.7 + pulse * 0.15)
	A.RaysA.ImageTransparency, A.RaysA.Rotation = 1 - lv * 0.42, (t * 9) % 360
	A.RaysB.ImageTransparency, A.RaysB.Rotation = 1 - lv * 0.36, (-t * 14) % 360
	local ring = (t * 0.45) % 1
	A.Ring.Size = UDim2.fromOffset(420 + ring * 620, 420 + ring * 620)
	A.Ring.ImageTransparency = 1 - lv * 0.5 * (1 - ring)
	A.Bokeh.ImageTransparency = 1 - lv * 0.32
	A.Bokeh.Rotation = math.sin(t * 0.3) * 6
	for _, e in A.Embers do
		local u = (e.P + t * e.Spd) % 1
		e.F.Position = UDim2.fromOffset(e.X + math.sin(t * 1.3 + e.Sway) * 22, 230 - u * 520)
		local s = e.Sz * (0.4 + 0.6 * math.sin(u * math.pi))
		e.F.Size = UDim2.fromOffset(s, s)
		e.F.BackgroundColor3 = col:Lerp(WHITE, 0.4)
		e.F.BackgroundTransparency = 1 - lv * 0.9 * math.sin(u * math.pi)
	end
	-- gun: drag to spin (with throw), otherwise a gentle float + sway on its stand
	local g, sp = self.Gun, self.Spin
	if g and g.Model and g.Model.Parent and g.Base then
		if not sp.Drag then
			sp.Yaw += sp.V * dt
			sp.V *= math.exp(-dt * 2.2)
			sp.Pitch += (0 - sp.Pitch) * math.min(1, dt * 2)
		end
		local k = t - g.T0
		local idle = if sp.Drag or math.abs(sp.V) > 0.2 then 0 else 1
		local rot = CFrame.new(g.Centre) * CFrame.Angles(sp.Pitch + math.sin(k * 0.9) * 0.03 * idle, sp.Yaw + math.sin(k * 0.6) * 0.12 * idle, 0) * CFrame.new(-g.Centre)
		local cf = CFrame.new(0, math.sin(k * 1.4) * 0.03, 0) * rot
		g.Model:PivotTo(cf * g.Base)
		for _, s in g.Sils do
			if s.M.Parent then s.M:PivotTo(cf * s.Base) end
		end
	end
	for _, b in self.Bars do
		b.Cur += (b.Target - b.Cur) * math.min(1, dt * 8)
		b.Fill.Size = S(b.Cur, 1)
	end
	for _, rec in self.Cards do
		if rec.RimGrad.Enabled then rec.RimGrad.Rotation = (t * 90) % 360 end
	end
end

------------------------------------------------------------------ screen API
function LoadoutHS:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	self.Scale.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.4, 2)
	local inset = self.Gui.AbsoluteSize
	local w, h = math.max(inset.X, vp.X), math.max(inset.Y, vp.Y)
	local k = math.max(w / ART_W, h / ART_H)
	self.ArtBase = Vector2.new(ART_W * k, ART_H * k)
end

function LoadoutHS:IsShown()
	return self.Shown
end

function LoadoutHS:Show()
	self.Shown = true
	self:_fit()
	self.Picker.Visible = false
	self.ShowKey = nil
	self.Gui.Enabled = true
	self:_refresh()
end

function LoadoutHS:Hide()
	self.Shown = false
	self.Gui.Enabled = false
	self.Picker.Visible = false
end

function LoadoutHS:_back()
	if self.Picker.Visible then
		self:_closePicker()
		return
	end
	if self.Opts.OnBack then self.Opts.OnBack() else self:Hide() end
end

function LoadoutHS:HandleKey(kc)
	if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.Backspace or kc == Enum.KeyCode.ButtonB then
		self:_back()
	end
end

return LoadoutHS
