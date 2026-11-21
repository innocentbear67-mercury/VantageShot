--[[
	VANTAGE — ScreenKit (client): shared pieces for the full-screen Loadout and Operators screens.
	  K.screen(name)            ScreenGui + a 1920x1080 canvas that scales to fit; K.toScreen() maps canvas px
	                            to viewport fractions (so the 3D showcase lines up with the UI)
	  K.header(G, canvas, p)    back button, title, Loadout | Operators tabs, REQ pill
	  K.panel(G, parent, p)     navy glass panel with the cyan-violet-magenta neon frame
	  K.neon(G, frame, color)   neon rim + a winking light that runs around it (driven by K.stepNeon)
	  K.weapon(id, skin)        a skinned weapon clone turned side-on (muzzle +X), centred on the origin
	  K.view(vp, model, size)   frames a model in a ViewportFrame
	  K.toast(G, canvas)        top-centre confirmation toast
	  K.FX / K.fxFor(skin)      skin -> showcase theme + tint
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Weapons = Vantage:WaitForChild("Weapons")
local Skins = require(Weapons:WaitForChild("Skins"))

local K = {}
local C = Color3.fromRGB
local V2, V3 = Vector2.new, Vector3.new
local S, O = UDim2.fromScale, UDim2.fromOffset
local NS, NK, CS, CK = NumberSequence.new, NumberSequenceKeypoint.new, ColorSequence.new, ColorSequenceKeypoint.new

K.W, K.H = 1920, 1080
K.ORDER = { Godly = 1, Exclusive = 2, Legendary = 3, Mythic = 4, Epic = 5, Rare = 6, Prime = 7, Elite = 8, Standard = 9 }
K.TIER = { Standard = 0, Elite = 1, Prime = 1, Rare = 2, Epic = 2, Mythic = 3, Legendary = 3, Exclusive = 3, Godly = 4 }

function K.rar(r)
	return (Skins.RarityColor and Skins.RarityColor[r]) or C(150, 172, 196)
end
-- the board's rarity ramp: vivid glow colour, card top, card bottom (HSV, Godly forced gold)
function K.rv(r)
	local h, s = K.rar(r):ToHSV()
	if r == "Godly" then
		h, s = 0.11, 0.85
	end
	return Color3.fromHSV(h, math.min(1, s * 1.15 + 0.1), 1), Color3.fromHSV(h, math.min(1, s + 0.25), 0.42), Color3.fromHSV(h, math.min(1, s + 0.35), 0.14)
end
function K.shade(c, t, to)
	return c:Lerp(to or C(10, 4, 28), t)
end

-- skin -> { theme, tint }
K.FX = {
	Factory = { "metal", "4a6cff" }, Graphite = { "metal", "3b4a8a" }, Whiteout = { "frost", "9fd8ff" }, Carbon = { "metal", "2a3a7a" },
	Cobalt = { "metal", "2860ff" }, Gilded = { "gold", "ffb02e" }, GlacierOps = { "frost", "7fd4ff" }, Archangel = { "holy", "ffe7a8" },
	AmberCore = { "ember", "ff9a1e" }, CarbonOps = { "scan", "5a7cff" }, ViridianNebula = { "cosmic", "2ed18a" }, PulsarStorm = { "cosmic", "ff3fd2" },
	SignalCorrupt = { "glitch", "ff3fa8" }, CryoFracture = { "frost", "8fdcff" }, GhostCamo = { "scan", "2fd3c8" }, CircuitLattice = { "electric", "16c8ff" },
	PlasmaFlux = { "electric", "8b6bff" }, DarkMatter = { "void", "8b3dff" }, MoltenSovereign = { "fire", "ff4a14" }, EventHorizon = { "void", "b04aff" },
	Kitsune = { "spirit", "ff3d6e" }, DragonEmperor = { "dragon", "ffb02e" }, StormHerald = { "electric", "3a8cff" }, ObsidianMagma = { "fire", "ff5a14" },
	HexBulwark = { "scan", "2fb8ff" }, AuroraVeil = { "cosmic", "22e0c0" }, RidgelineTopo = { "scan", "2a7cff" }, CrimsonDamascus = { "metal", "ff2a4a" },
	ToxicBloom = { "toxic", "5aff3a" }, PrismShard = { "prism", "c87cff" }, Kintsugi = { "gold", "ffcf6a" }, SimGrid = { "electric", "b04aff" },
	LiquidCobalt = { "water", "2a6cff" }, AbyssalLeviathan = { "water", "1ee0d0" }, CelestialAstrolabe = { "holy", "ffd27a" },
	SakuraRonin = { "petal", "ff5a8c" }, PhoenixAscendant = { "dragon", "ffcf5a" }, Tidebreaker = { "water", "40deff" }, Emberline = { "ember", "ff7830" },	PlagueDoctor = { "toxic", "6eff2e" }, FrostFenrir = { "frost", "8fd0ff" }, AnubisEternal = { "gold", "ffc24a" }, Calavera = { "petal", "ff8a1e" }, WraithKing = { "spirit", "a87cff" }, IroncladSteamworks = { "ember", "ffa040" }, BrazenMinotaur = { "fire", "ff3a1e" }, GorgonsGaze = { "toxic", "2effa0" }, KrampusYule = { "frost", "ff3048" }, CerberusWarden = { "fire", "3aa0ff" }, StrixNightwatch = { "scan", "7aa8ff" }, SabretoothPrimeval = { "fire", "ff8a1e" }, JaguarSunWarrior = { "gold", "3ee8d8" }, WatcherBeyond = { "void", "2ee8d8" }, HeartbreakerValentine = { "petal", "ff4f9a" }, AbyssDiver = { "water", "ffb03c" }, HammerheadApex = { "fire", "ff2848" }, TidecallerAtlantis = { "gold", "2ee6c8" }, SunsetSurf = { "petal", "ff7850" }, KrakenLord = { "void", "28dcff" }, RiotWarden = { "scan", "8cb4ff" }, RhinoJuggernaut = { "toxic", "e6f03c" }, OniWarlord = { "void", "b45aff" }, JackOLantern = { "ember", "ff8a1e" }, BehemothWorldBreaker = { "gold", "ffd25a" }, StarMarshal = { "scan", "8ce0ff" }, DeathstalkerScorpion = { "ember", "ffa020" }, ScalesOfJudgement = { "gold", "6a9cff" }, MidnightCountdown = { "void", "ff5ad2" }, SovereignLion = { "dragon", "ffd27a" }, ContainmentBreach = { "toxic", "ff3cdc" }, IronhornRam = { "scan", "28dcff" }, GenesisHelix = { "gold", "ffd778" }, MasqueradeCarnival = { "void", "aa46ff" }, StormTitan = { "dragon", "ffd25a" }, ReconTracker = { "toxic", "5aff8c" }, RaptorRampage = { "toxic", "8cff3c" }, CelestialStag = { "spirit", "5af0e6" },
}
function K.fxFor(skin)
	local f = K.FX[skin.Id]
	if f then
		return f[1], Color3.fromHex(f[2])
	end
	return "metal", skin.Swatch or K.rar(skin.Rarity)
end

-- ─── screen + canvas ─────────────────────────────────────────────────────────────────────
function K.screen(name, order)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = order or 13
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.AnchorPoint = V2(0.5, 0.5)
	canvas.Position = S(0.5, 0.5)
	canvas.Size = O(K.W, K.H)
	canvas.BackgroundTransparency = 1
	canvas.Parent = gui
	local sc = Instance.new("UIScale")
	sc.Parent = canvas
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		local s = math.min(vp.X / K.W, vp.Y / K.H)
		sc.Scale = s
		-- wider than 16:9: stretch the canvas so edge-anchored panels reach the screen edges
		canvas.Size = O(math.max(K.W, vp.X / s), K.H)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	local function toScreen(px, py)
		local vp = Workspace.CurrentCamera.ViewportSize
		return (vp.X / 2 + (px - K.W / 2) * sc.Scale) / vp.X, (vp.Y / 2 + (py - K.H / 2) * sc.Scale) / vp.Y
	end
	return gui, canvas, toScreen, sc
end

-- ─── header ──────────────────────────────────────────────────────────────────────────────
local function chevron(G, b)
	local sym = b:FindFirstChild("Symbol")
	if sym then
		sym:ClearAllChildren()
		for _, v in { { 0.44, 0.36, -45 }, { 0.44, 0.64, 45 } } do
			local f = G.new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(v[1], v[2]), Size = UDim2.new(0.36, 0, 0.14, 0), Rotation = v[3], BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = sym.ZIndex }, sym)
			G.corner(f, UDim.new(1, 0))
			G.stroke(f, 3, G.C.Ink)
		end
	end
end

function K.header(G, canvas, p)
	local h = {}
	local left = G.new("Frame", { Name = "TitleBlock", BackgroundTransparency = 1, Position = O(40, 26), Size = O(560, 70), ZIndex = 10 }, canvas)
	local back = G.square(left, "Back", 60, { Position = O(0, 4), ZIndex = 12, Sound = "Close", OnClick = p.OnBack })
	chevron(G, back)
	G.text(left, { Name = "Title", Text = p.Title, Position = O(84, -4), Size = O(480, 56), X = Enum.TextXAlignment.Left, TextSize = 52, Stroke = 4.5, ZIndex = 12 })
	G.text(left, { Name = "Sub", Text = p.Sub, Position = O(86, 48), Size = O(480, 24), X = Enum.TextXAlignment.Left, TextSize = 19, Color = G.C.Muted, Stroke = 0, Font = G.F.Bold, ZIndex = 12 })
	h.Left = left
	-- tabs
	local tabs = G.glass(canvas, { Name = "Tabs", Position = UDim2.new(0.5, 0, 0, 32), AnchorPoint = V2(0.5, 0), Size = O(372, 60), Radius = UDim.new(1, 0), TopLine = false, EdgeTransparency = 0.5, ZIndex = 10 })
	local x = 5
	for _, name in { "Loadout", "Operators" } do
		local w = if name == "Loadout" then 166 else 196
		local b = G.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = O(x, 5), Size = O(w, 50), ZIndex = 11 }, tabs)
		x += w
		if name == p.Active then
			local face = G.new("Frame", { Name = "Face", Size = S(1, 1), ZIndex = 11 }, b)
			G.surface(face, "cyan", { Radius = UDim.new(1, 0), Dots = false, Outline = 3 })
			G.text(b, { Text = name, TextSize = 25, Stroke = 3.2, ZIndex = 14 })
		else
			local t = G.text(b, { Text = name, TextSize = 25, Stroke = 0, Color = G.C.Muted, ZIndex = 14 })
			b.MouseEnter:Connect(function()
				G.tween(t, 0.15, { TextColor3 = Color3.new(1, 1, 1) })
				G.sound("Hover")
			end)
			b.MouseLeave:Connect(function()
				G.tween(t, 0.15, { TextColor3 = G.C.Muted })
			end)
			b.Activated:Connect(function()
				G.sound("Click")
				if p.OnTab then
					p.OnTab(name)
				end
			end)
		end
	end
	h.Tabs = tabs
	-- REQ
	local right = G.new("Frame", { Name = "Wallet", BackgroundTransparency = 1, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -40, 0, 30), Size = O(370, 66), ZIndex = 10 }, canvas)
	G.square(right, "Plus", 60, { Position = O(0, 0), ZIndex = 12, OnClick = p.OnStore })
	local pill, val = G.pill(right, { Name = "Req", Width = 290, Height = 60, Position = O(80, 0), Icon = G.A.Icon.Req, Text = "0", TextSize = 36 })
	pill.ZIndex = 11
	-- board styling: navy glass pill, oversized glowing REQ emblem breaking the left edge
	local pgr = pill:FindFirstChildOfClass("UIGradient")
	if pgr then
		pgr.Color = ColorSequence.new(C(26, 34, 96), C(10, 13, 44))
	end
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	local ps = pill:FindFirstChildOfClass("UIStroke")
	if ps then
		ps.Color = C(124, 243, 255)
		ps.Thickness = 2.5
		ps.Transparency = 0.45
	end
	local ic = pill:FindFirstChild("Icon")
	if ic then
		ic.AnchorPoint = V2(0.5, 0.5)
		ic.Size = O(86, 86)
		ic.Position = O(19, 27)
		G.glow(ic, { Color = C(58, 109, 255), Transparency = 0.35, Size = S(1.7, 1.7), ZIndex = 2 })
	end
	local pv = pill:FindFirstChild("Value")
	if pv then
		pv.Position = O(74, 0)
	end
	G.text(pill, { Name = "Unit", Text = "REQ", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -22, 0, 0), Size = O(60, 60), X = Enum.TextXAlignment.Right, TextSize = 20, Font = G.F.Bold, Stroke = 0, Color = G.C.Cyan, ZIndex = 3 })
	for _, d in pill:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = d.ZIndex + 10
		end
	end
	local function setReq()
		val.Text = G.abbrev(tonumber(Players.LocalPlayer:GetAttribute("REQ")) or 0)
	end
	setReq()
	Players.LocalPlayer:GetAttributeChangedSignal("REQ"):Connect(setReq)
	h.Right = right
	return h
end

-- ─── panel ───────────────────────────────────────────────────────────────────────────────
function K.panel(G, parent, p)
	local f = G.new(p.Class or "Frame", {
		Name = p.Name or "Panel", Position = p.Position, Size = p.Size, AnchorPoint = p.AnchorPoint or V2(0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = p.ZIndex or 4, ClipsDescendants = false,
	}, parent)
	G.corner(f, p.Radius or 24)
	G.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, C(20, 28, 92)), CK(0.55, C(12, 16, 60)), CK(1, C(22, 12, 62)) }), Transparency = NS(p.Transparency or 0.06) }, f)
	local st = G.stroke(f, 3, Color3.new(1, 1, 1), 0)
	G.new("UIGradient", { Rotation = 45, Color = CS({ CK(0, C(157, 250, 255)), CK(0.5, C(139, 92, 255)), CK(1, C(255, 63, 210)) }) }, st)
	G.glow(f, { Name = "Aura", Color = C(139, 92, 255), Transparency = 0.82, Size = UDim2.new(1, 160, 1, 160), ZIndex = (p.ZIndex or 4) - 1 })
	return f
end

-- ─── neon rim + wink ─────────────────────────────────────────────────────────────────────
-- rim: a bright rarity-coloured border; wink: a white streak that circles the border now and then
local neonList = {}
function K.neon(G, frame, color, radius, delay)
	local z = frame.ZIndex + 6
	local rim = G.new("Frame", { Name = "Rim", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z }, frame)
	G.corner(rim, radius)
	local st = G.new("UIStroke", { Thickness = 5, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round }, rim)
	local rg = G.new("UIGradient", { Rotation = 35, Color = CS({ CK(0, color:Lerp(Color3.new(1, 1, 1), 0.6)), CK(0.3, color), CK(0.7, color), CK(1, K.shade(color, 0.35)) }) }, st)
	local wink = G.new("Frame", { Name = "Wink", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = z + 1 }, frame)
	G.corner(wink, radius)
	local wst = G.new("UIStroke", { Thickness = 5, Color = Color3.new(1, 1, 1), Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, wink)
	local wg = G.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.5, 0), NK(0.58, 1), NK(1, 1) }) }, wst)
	local rec = { Frame = frame, Rim = st, RimGrad = rg, Wink = wst, WinkGrad = wg, Delay = delay or 0, Fast = false }
	neonList[rec] = true
	return rec
end
K.CHROMA = CS({ CK(0, C(255, 84, 104)), CK(0.17, C(255, 196, 64)), CK(0.33, C(110, 255, 130)), CK(0.5, C(64, 224, 255)), CK(0.67, C(120, 110, 255)), CK(0.83, C(255, 84, 224)), CK(1, C(255, 84, 104)) })
-- chromatic rarities: Godly = full rainbow, Exclusive = "holo" pink-violet-cyan (its own sweep, never the rainbow)
K.CHROMAS = {
	Godly = { Grad = K.CHROMA, Bg = CS({ CK(0, C(96, 24, 92)), CK(0.33, C(26, 40, 122)), CK(0.66, C(12, 84, 96)), CK(1, C(84, 30, 20)) }), H0 = 0, H1 = 1, Speed = 0.14 },
	Exclusive = { Grad = CS({ CK(0, C(255, 70, 170)), CK(0.25, C(170, 90, 255)), CK(0.5, C(70, 220, 255)), CK(0.75, C(170, 90, 255)), CK(1, C(255, 70, 170)) }),
		Bg = CS({ CK(0, C(92, 14, 70)), CK(0.5, C(44, 22, 120)), CK(1, C(10, 60, 104)) }), H0 = 0.52, H1 = 0.93, Speed = 0.35, Bounce = true },
	-- metallic rarities (2026-11-17, user): Legendary = shiny gold, Mythic = shiny platinum; banded sheen that slides like the rainbow
	Legendary = { Grad = CS({ CK(0, C(255, 246, 196)), CK(0.22, C(255, 196, 52)), CK(0.5, C(255, 250, 220)), CK(0.76, C(204, 128, 14)), CK(1, C(255, 246, 196)) }),
		Bg = CS({ CK(0, C(120, 78, 10)), CK(0.5, C(70, 42, 6)), CK(1, C(34, 20, 4)) }), H0 = 0.1, H1 = 0.15, S = 0.62, Speed = 0.45, Bounce = true, Metal = true },
	Mythic = { Grad = CS({ CK(0, C(255, 255, 255)), CK(0.22, C(168, 184, 214)), CK(0.5, C(246, 250, 255)), CK(0.76, C(124, 138, 168)), CK(1, C(255, 255, 255)) }),
		Bg = CS({ CK(0, C(84, 94, 116)), CK(0.5, C(44, 50, 66)), CK(1, C(18, 22, 32)) }), H0 = 0.55, H1 = 0.64, S = 0.14, Speed = 0.45, Bounce = true, Metal = true },
}
function K.chromaColor(def, t, phase)
	local k = if def.Bounce then 0.5 + 0.5 * math.sin((t * def.Speed + phase) * math.pi * 2) else (t * def.Speed + phase) % 1
	return Color3.fromHSV(def.H0 + (def.H1 - def.H0) * k, def.S or 0.7, 1)
end
function K.setNeon(rec, color)
	rec.RimGrad.Color = CS({ CK(0, color:Lerp(Color3.new(1, 1, 1), 0.55)), CK(0.35, color), CK(1, K.shade(color, 0.45)) })
end
function K.stepNeon(t)
	for rec in neonList do
		if not rec.Frame.Parent then
			neonList[rec] = nil
		elseif rec.Frame.Visible then
			if rec.Fast then
				rec.WinkGrad.Rotation = (t * 300) % 360
				rec.Wink.Transparency = 0
			else
				-- run around for ~1.6 s every 6.6 s, each card on its own clock
				local ph = ((t + rec.Delay) % 6.6) / 6.6
				local on = ph > 0.62 and ph < 0.94
				rec.WinkGrad.Rotation = (t * 220) % 360
				rec.Wink.Transparency = if on then math.abs((ph - 0.78) / 0.16) * 0.8 else 1
			end
		end
	end
end

-- ─── weapon models ───────────────────────────────────────────────────────────────────────
local PRE = { Knife = CFrame.Angles(0, math.rad(90), math.rad(-90)) }
function K.orient(model, pre)
	if pre then
		model:PivotTo(model:GetPivot() * pre)
	end
	local cf0 = model:GetBoundingBox()
	local rel = cf0:Inverse() * model:GetPivot()
	model:PivotTo(CFrame.Angles(0, math.rad(-90), 0) * (cf0 - cf0.Position) * rel)
	local cf1, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - cf1.Position)
	return size
end
-- equipment item (Shield Pack / Grappling Hook) from its template, turned to a 3/4 view, centred on the origin
function K.equipment(id)
	local eq = Vantage:FindFirstChild("Equipment")
	local models = eq and eq:FindFirstChild("Models")
	local t = models and models:FindFirstChild(id)
	if not t then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = id
	for _, src in t:GetChildren() do
		if src:IsA("BasePart") then
			local p = src:Clone()
			local rcf = src:GetAttribute("RootCF")
			p.CFrame = if typeof(rcf) == "CFrame" then rcf else CFrame.new()
			p:SetAttribute("RootCF", nil)
			p.Anchored = true
			p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
			p.Parent = m
		end
	end
	local rot = CFrame.Angles(math.rad(-12), math.rad(28), 0) * (if t:GetAttribute("Kind") == "hook" then CFrame.Angles(0, math.rad(90), 0) else CFrame.new())
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in m:GetChildren() do
		p.CFrame = rot * p.CFrame
		local cf, h = p.CFrame, p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local q = cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
					lo, hi = lo:Min(q), hi:Max(q)
				end
			end
		end
	end
	if lo.X == math.huge then
		return nil
	end
	local c = (lo + hi) / 2
	for _, p in m:GetChildren() do
		p.CFrame = p.CFrame - c
	end
	return m, hi - lo
end

function K.weapon(weaponId, skinId)
	if weaponId == "Equipment" then
		return K.equipment(skinId)
	end
	local src = Weapons:FindFirstChild("Assets") and Weapons.Assets:FindFirstChild(weaponId)
	if not src then
		return nil
	end
	local m = src:Clone()
	pcall(Skins.Apply, m, weaponId, skinId)
	-- drop base parts the skin hid: a Highlight still draws hidden parts (the floating "ghost box" under shell skins)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency >= 0.99 and d ~= m.PrimaryPart and d.Parent then
			for _, ch in d:GetChildren() do
				if not ch:IsA("JointInstance") and not ch:IsA("WeldConstraint") then
					ch.Parent = m
				end
			end
			d:Destroy()
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		end
	end
	local size = K.orient(m, PRE[weaponId])
	return m, size
end

-- frame a model (centred on the origin) in a ViewportFrame; tilt lifts the muzzle (degrees)
function K.view(vp, model, size, opts)
	opts = opts or {}
	vp:ClearAllChildren()
	local tilt = math.rad(opts.Tilt or 0)
	if tilt ~= 0 then
		model:PivotTo(CFrame.Angles(0, 0, tilt) * model:GetPivot())
	end
	local w = math.abs(size.X * math.cos(tilt)) + math.abs(size.Y * math.sin(tilt))
	local h = math.abs(size.X * math.sin(tilt)) + math.abs(size.Y * math.cos(tilt))
	local cam = Instance.new("Camera")
	cam.FieldOfView = opts.Fov or 20
	local aspect = opts.Aspect or 1
	local tv = math.tan(math.rad(cam.FieldOfView / 2))
	local dist = math.max(h / 2 / tv, w / 2 / (tv * aspect)) * (opts.Pad or 1.12) + size.Z / 2
	cam.CFrame = CFrame.lookAt(V3(opts.Dx or 0, opts.Dy or 0, dist), V3(opts.Dx or 0, opts.Dy or 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Ambient = opts.Ambient or C(150, 156, 180)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = V3(0.45, -0.55, -1)
	model.Parent = vp
	return cam
end

-- ─── toast ───────────────────────────────────────────────────────────────────────────────
function K.toast(G, canvas)
	local f = G.new("Frame", { Name = "Toast", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = O(10, 56), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 60, Visible = false }, canvas)
	G.corner(f, UDim.new(1, 0))
	G.new("UIGradient", { Color = CS(C(22, 200, 255), C(139, 92, 255)) }, f)
	G.stroke(f, 3, G.C.Ink)
	G.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 26) }, f)
	G.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12) }, f)
	local ok = G.square(f, "Check", 36, { ZIndex = 61, LayoutOrder = 1 })
	ok.Active = false
	local t = G.text(f, { Name = "Msg", Text = "", Size = O(0, 40), Auto = Enum.AutomaticSize.X, TextSize = 24, Stroke = 3.2, LayoutOrder = 2, ZIndex = 62 })
	local token = 0
	return function(msg)
		token += 1
		local my = token
		t.Text = msg
		f.Visible = true
		f.Position = UDim2.new(0.5, 0, 0, -90)
		G.tween(f, 0.45, { Position = UDim2.new(0.5, 0, 0, 112) }, Enum.EasingStyle.Back)
		task.delay(2.2, function()
			if my == token then
				G.tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, -90) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
	end
end

return K
