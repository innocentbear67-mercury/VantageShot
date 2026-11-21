-- VantageSkinRange (Studio only) — shot overhaul test bench, 2026-11-18
-- Press the "SKIN RANGE" button (top-left, Studio playtests only) to open a client-side range far
-- from the map: two stands (A / B) firing the real cosmetic pipeline (WeaponEffects + SkinFX) at a
-- wall of surface strips and two dummies. Nothing here touches the server, damage or hit
-- registration; it never runs in a live server (IsStudio guard).
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	script:Destroy()
	return
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Wpn = RS:WaitForChild("Vantage"):WaitForChild("Weapons")
local Skins = require(Wpn:WaitForChild("Skins"))
local SkinFX = require(Wpn:WaitForChild("SkinFX"))
local VFXKit = require(Wpn:WaitForChild("VFXKit"))
local WeaponConfig = require(Wpn:WaitForChild("WeaponConfig"))
local clientScripts = player:WaitForChild("PlayerScripts"):WaitForChild("VantageWeaponClient")
local WeaponEffects = require(clientScripts:WaitForChild("WeaponEffects"))

local V, C = Vector3.new, Color3.fromRGB
local ORIGIN = V(6000, 600, 6000)
local WEAPONS = { "Vanguard", "Sentinel", "Spectre", "Breacher", "Longshot", "Riptide", "Bulwark", "Verdict", "Quill", "Helix", "Havoc", "Arc" }
local AIMS = { "Concrete", "Metal", "Glass", "Wood", "Fabric", "Slate", "Dummy" }
local STRIPS = { Concrete = Enum.Material.Concrete, Metal = Enum.Material.DiamondPlate, Glass = Enum.Material.Glass,
	Wood = Enum.Material.WoodPlanks, Fabric = Enum.Material.Fabric, Slate = Enum.Material.Slate }

local fx -- WeaponEffects instance (made on first open)
local range: Folder? = nil
local targets: { [string]: Vector3 } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local rng = Random.new()
local iso = "All"
local soundOn = true
local aimIx = 1

-- ─── range geometry ───────────────────────────────────────────────────────
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do p[k] = v end
	p.Parent = parent
	return p
end

local function build()
	local f = Instance.new("Folder")
	f.Name = "_SkinRange"
	local tg = Instance.new("Folder"); tg.Name = "Targets"; tg.Parent = f
	local guns = Instance.new("Folder"); guns.Name = "Guns"; guns.Parent = f
	part({ Name = "Floor", Size = V(110, 1, 120), CFrame = CFrame.new(ORIGIN + V(0, -0.5, 36)), Color = C(26, 28, 34), Material = Enum.Material.SmoothPlastic }, tg)
	for _, x in { -3, 3 } do
		part({ Name = "Stand", Size = V(0.6, 3.4, 0.6), CFrame = CFrame.new(ORIGIN + V(x, 1.7, -0.4)), Color = C(60, 64, 74), Material = Enum.Material.Metal, CanQuery = false }, f)
	end
	local order = { "Concrete", "Metal", "Glass", "Wood", "Fabric", "Slate" }
	for i, name in order do
		local x = -15 + (i - 0.5) * 5
		local p = part({ Name = name, Size = V(5, 14, 2), CFrame = CFrame.new(ORIGIN + V(x, 7, 72)), Material = STRIPS[name],
			Color = if name == "Glass" then C(150, 190, 210) else C(120, 122, 128), Transparency = if name == "Glass" then 0.35 else 0 }, tg)
		targets[name] = p.Position + V(0, -2.5, -1)
	end
	for _, x in { -2.5, 2.5 } do
		local m = Instance.new("Model")
		m.Name = "Dummy"
		local torso = part({ Name = "Torso", Size = V(2, 2, 1), CFrame = CFrame.new(ORIGIN + V(x, 4, 60)), Color = C(90, 96, 110) }, m)
		part({ Name = "Head", Size = V(1.2, 1.2, 1.2), CFrame = CFrame.new(ORIGIN + V(x, 5.6, 60)), Color = C(90, 96, 110) }, m)
		part({ Name = "Legs", Size = V(2, 2, 1), CFrame = CFrame.new(ORIGIN + V(x, 2, 60)), Color = C(70, 74, 86) }, m)
		Instance.new("Humanoid").Parent = m
		m.PrimaryPart = torso
		m.Parent = tg
	end
	targets.Dummy = ORIGIN + V(-2.5, 4.4, 59.5)
	params.FilterDescendantsInstances = { tg }
	f.Parent = Workspace
	range = f
end

-- ─── stands ───────────────────────────────────────────────────────────────
local function newStand(offset: Vector3, w: string, skinId: string?)
	local st = { offset = offset, w = w, on = true }
	local list = Skins.List(w)
	st.ix = 1
	for i, s in list do if s.Id == skinId then st.ix = i end end
	return st
end
local A = newStand(V(-3, 0, 0), "Vanguard", "EventHorizon")
local B = newStand(V(3, 0, 0), "Vanguard", "Factory")
local stress = {}

local function skinOf(st) return Skins.List(st.w)[st.ix] end

local function mount(st)
	if st.model then st.model:Destroy(); st.model = nil end
	if not range or not st.on then return end
	local cfg = WeaponConfig.Weapons[st.w]
	local asset = Wpn.Assets:FindFirstChild(cfg and cfg.Asset or st.w)
	if not asset then return end
	local m = asset:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false end
	end
	m.Parent = range.Guns
	local skin = skinOf(st)
	pcall(Skins.Apply, m, st.w, skin and skin.Id)
	local base = ORIGIN + st.offset + V(0, 4, 0)
	m:PivotTo(CFrame.lookAt(base, base + V(0, 0, 1)))
	st.model = m
	st.muzzle = (m.PrimaryPart and m.PrimaryPart:FindFirstChild("Muzzle")) or m:FindFirstChild("Muzzle", true)
end

-- ─── firing (the same calls the game makes for a remote player's shot) ───────
local function aimPoint(st)
	local name = AIMS[aimIx]
	local p = targets[name] or targets.Concrete
	if name == "Dummy" then p += V(if st == B then 5 else 0, 0, 0) else p += V(st.offset.X * 0.4, 0, 0) end
	return p
end

local function shoot(st, quiet: boolean?, spread: number?)
	local mz = st.muzzle
	if not (mz and mz.Parent and fx) then return end
	local cfg = WeaponConfig.Weapons[st.w]
	local from = mz.WorldPosition
	local s = spread or 0.4
	local aim = aimPoint(st) + V(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)
	local dir = (aim - from).Unit
	local res = Workspace:Raycast(from, dir * 300, params)
	local endPos = if res then res.Position else from + dir * 300
	local model = res and res.Instance:FindFirstAncestorOfClass("Model")
	local kind = if model and model:FindFirstChildOfClass("Humanoid") then "Character" else "World"
	local def = SkinFX.Get(SkinFX.ForAttachment(mz))
	if not quiet then
		if iso == "All" or iso == "Muzzle" then
			fx:MuzzleFlash(mz)
		else -- keep the skin lookup alive without drawing the flash
			table.insert(fx._flashes, { pos = mz.WorldPosition, def = def, t = os.clock(), P = VFXKit.ProfileForInstance(mz) })
		end
		if soundOn then fx:PlayFire3D(st.w, mz, st) end
	end
	if iso == "Muzzle" then return end
	if iso == "Impact" then
		if res then
			if def then SkinFX.Impact(res.Position, res.Normal, def) end
			fx:_ImpactDefault(res.Position, res.Normal, kind, res.Material, st.w, def)
		end
		return
	end
	local P = cfg.Projectile
	local withImpact = res and iso ~= "Round"
	if cfg.Beam then
		fx:BeamPulse(st, mz, endPos, cfg.Beam)
		if withImpact then fx:Impact(res.Position, res.Normal, kind, res.Material, st.w) end
	elseif P and P.Gravity then
		fx:BoltArc(from, dir, P, params, st.w)
	elseif P then
		fx:Bolt(from, endPos, P, if withImpact then { res.Normal, res.Material, st.w } else nil)
	else
		fx:Tracer(from, endPos, 1.4)
		if withImpact then fx:Impact(res.Position, res.Normal, kind, res.Material, st.w) end
	end
end

local function trigger(st, duration: number)
	local cfg = WeaponConfig.Weapons[st.w]
	if not cfg then return end
	local interval = 60 / (cfg.RPM or 600)
	local burst = 1
	if cfg.Trigger == "Burst" then
		local b = cfg.Burst or {}
		burst = b.Count or b.Shots or b.Rounds or 3
	end
	local pellets = 1
	if cfg.Shot == "Pellet" then
		local p = cfg.Pellet or {}
		pellets = p.Count or p.Pellets or 9
	end
	st.token = (st.token or 0) + 1
	local tok = st.token
	task.spawn(function()
		local stopAt = os.clock() + duration
		repeat
			for b = 1, burst do
				if st.token ~= tok then return end
				for p = 1, pellets do
					shoot(st, p > 1, if pellets > 1 then 3.2 else 0.4)
				end
				if b < burst then task.wait(interval / SkinFX.TimeScale) end
			end
			task.wait((if burst > 1 then 0.3 else interval) / SkinFX.TimeScale)
		until os.clock() >= stopAt or st.token ~= tok
	end)
end
local function stopAll()
	for _, st in { A, B } do st.token = (st.token or 0) + 1 end
	for _, st in stress do st.token = (st.token or 0) + 1 end
end

-- ─── slow motion: cosmetic clock + emitter TimeScale ─────────────────────
local slow = false
local function applyEmitterScale()
	local k = if slow then 0.25 else 1
	local roots = { Workspace.Terrain, Workspace:FindFirstChild("VantageWeaponFX"), range }
	for _, r in roots do
		if r then
			for _, d in r:GetDescendants() do
				if d:IsA("ParticleEmitter") then d.TimeScale = k end
			end
		end
	end
end

-- ─── camera ───────────────────────────────────────────────────────────────
local CAMS = {
	Side = { V(-26, 7, 30), V(0, 4, 32) },
	Shooter = { V(-1.5, 7.2, -9), V(0, 4.2, 60) },
	Target = { V(-9, 6, 56), V(0, 5, 70) },
	Spectator = { V(42, 22, -34), V(0, 4, 36) },
}
local camName = "Side"
local camCF = CFrame.new()
local function setCam(name)
	camName = name
	local c = CAMS[name]
	camCF = CFrame.lookAt(ORIGIN + c[1], ORIGIN + c[2])
end

-- ─── UI ───────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "VantageSkinRange"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local PURPLE, DARK, TXT = C(140, 90, 255), C(36, 40, 50), C(235, 238, 245)
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = o end
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(120, 30)
toggle.Position = UDim2.fromOffset(12, 60)
toggle.Text = "SKIN RANGE"
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 13
toggle.TextColor3 = TXT
toggle.BackgroundColor3 = PURPLE
corner(toggle)
toggle.Parent = gui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(380, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Position = UDim2.fromOffset(12, 98)
panel.BackgroundColor3 = C(18, 20, 26)
panel.BackgroundTransparency = 0.08
panel.Visible = false
panel.Active = true
corner(panel, 10)
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)
pad.Parent = panel
local vl = Instance.new("UIListLayout"); vl.Padding = UDim.new(0, 6); vl.SortOrder = Enum.SortOrder.LayoutOrder; vl.Parent = panel
panel.Parent = gui

local order = 0
local function row(h)
	order += 1
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, h or 26)
	f.LayoutOrder = order
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 4)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	f.Parent = panel
	return f
end
local function label(parent, text, w, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(0, w or 60, 1, 0)
	t.Text = text
	t.Font = Enum.Font.GothamMedium
	t.TextSize = 13
	t.TextColor3 = color or TXT
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end
local function btn(parent, text, w, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w or 64, 1, 0)
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.TextColor3 = TXT
	b.BackgroundColor3 = DARK
	b.AutoButtonColor = true
	corner(b)
	b.Parent = parent
	b.MouseButton1Click:Connect(cb)
	return b
end
local groups = {}
local function radio(group, b)
	groups[group] = groups[group] or {}
	table.insert(groups[group], b)
	b.MouseButton1Click:Connect(function()
		for _, o in groups[group] do o.BackgroundColor3 = DARK end
		b.BackgroundColor3 = PURPLE
	end)
end
local function pick(group, text)
	for _, o in groups[group] or {} do o.BackgroundColor3 = if o.Text == text then PURPLE else DARK end
end

local function header(text)
	local r = row(18)
	label(r, text, 360, C(150, 155, 170)).TextSize = 11
end

local standUI = {}
local function rarityColor(r)
	local rc = Skins.RarityColor and Skins.RarityColor[r]
	return if typeof(rc) == "Color3" then rc else TXT
end
local function refresh(st)
	local u = standUI[st]
	if not u then return end
	local cfg = WeaponConfig.Weapons[st.w]
	local s = skinOf(st)
	u.w.Text = (cfg and cfg.ShortName or st.w)
	u.s.Text = if s then string.format("%s  ·  %s", s.Name or s.Id, s.Rarity or "?") else "?"
	u.s.TextColor3 = if s then rarityColor(s.Rarity) else TXT
	if u.on then u.on.Text = if st.on then "ON" else "OFF" end
end
local function standRows(st, name, canToggle)
	header("STAND " .. name)
	local r1 = row()
	local u = {}
	btn(r1, "◀", 26, function()
		local i = table.find(WEAPONS, st.w) or 1
		st.w = WEAPONS[(i - 2) % #WEAPONS + 1]; st.ix = 1; mount(st); refresh(st)
	end)
	u.w = label(r1, "", 120)
	btn(r1, "▶", 26, function()
		local i = table.find(WEAPONS, st.w) or 1
		st.w = WEAPONS[i % #WEAPONS + 1]; st.ix = 1; mount(st); refresh(st)
	end)
	if canToggle then
		u.on = btn(r1, "ON", 48, function() st.on = not st.on; mount(st); refresh(st) end)
	end
	local r2 = row()
	btn(r2, "◀", 26, function()
		local n = #Skins.List(st.w); st.ix = (st.ix - 2) % n + 1; mount(st); refresh(st)
	end)
	u.s = label(r2, "", 270)
	btn(r2, "▶", 26, function()
		local n = #Skins.List(st.w); st.ix = st.ix % n + 1; mount(st); refresh(st)
	end)
	standUI[st] = u
	refresh(st)
end
standRows(A, "A", false)
standRows(B, "B", true)

header("FIRE")
local rf = row()
btn(rf, "Single", 70, function() trigger(A, 0); if B.on then trigger(B, 0) end end)
btn(rf, "Auto 3 s", 70, function() trigger(A, 3); if B.on then trigger(B, 3) end end)
btn(rf, "A only", 60, function() trigger(A, 3) end)
btn(rf, "B only", 60, function() if B.on then trigger(B, 3) end end)
btn(rf, "Stop", 50, stopAll)

header("AIM AT")
local ra = row()
local aimLbl
btn(ra, "◀", 26, function() aimIx = (aimIx - 2) % #AIMS + 1; aimLbl.Text = AIMS[aimIx] end)
aimLbl = label(ra, AIMS[aimIx], 90)
btn(ra, "▶", 26, function() aimIx = aimIx % #AIMS + 1; aimLbl.Text = AIMS[aimIx] end)

header("SHOW")
local ri = row()
for _, k in { "All", "Muzzle", "Round", "Impact" } do
	radio("iso", btn(ri, k, 64, function() iso = k end))
end
pick("iso", "All")

header("SPEED  ·  QUALITY  ·  SOUND")
local rs = row()
radio("spd", btn(rs, "1x", 40, function() slow = false; SkinFX.TimeScale = 1; applyEmitterScale() end))
radio("spd", btn(rs, "0.25x", 50, function() slow = true; SkinFX.TimeScale = 0.25; applyEmitterScale() end))
pick("spd", "1x")
for _, q in { { "Low", 0.35 }, { "Med", 0.65 }, { "High", 1 }, { "Auto", false } } do
	radio("q", btn(rs, q[1], 44, function() SkinFX.QualityOverride = q[2] or nil end))
end
pick("q", "Auto")
local sb
sb = btn(rs, "Snd ON", 60, function() soundOn = not soundOn; sb.Text = if soundOn then "Snd ON" else "Snd OFF" end)

header("CAMERA")
local rc = row()
for _, k in { "Side", "Shooter", "Target", "Spectator" } do
	radio("cam", btn(rc, k, 70, function() setCam(k) end))
end
pick("cam", "Side")

header("STRESS")
local rst = row()
local stressBtn = btn(rst, "16 shooters · 8 s", 140, function() end)

local stats = label(row(34), "", 360, C(160, 220, 170))
stats.TextWrapped = true
stats.TextYAlignment = Enum.TextYAlignment.Top
stats.Size = UDim2.new(1, 0, 1, 0)

-- ─── stress test: 16 premium shooters on full auto ──────────────────────────
local hidden = {}
local open = false
local fpsEma, dtNow = 60, 1 / 60
RunService.RenderStepped:Connect(function(dt)
	dtNow = dt
	fpsEma += (1 / math.max(dt, 1e-3) - fpsEma) * 0.1
end)
local stressResult = ""
local running = false
local function runStress()
	if running or not range then return end
	running = true
	stopAll()
	local picks = {}
	for _, w in WEAPONS do
		for _, s in Skins.List(w) do
			if s.Rarity == "Godly" or s.Rarity == "Exclusive" or s.Rarity == "Legendary" or s.Rarity == "Mythic" then
				table.insert(picks, { w, s.Id })
			end
		end
	end
	if #picks == 0 then running = false; return end
	stress = {}
	for i = 1, 16 do
		local p = picks[(i - 1) % #picks + 1]
		local st = newStand(V(-30 + (i - 1) * 4, 0, -6), p[1], p[2])
		mount(st)
		table.insert(stress, st)
	end
	setCam("Spectator"); pick("cam", "Spectator")
	task.wait(0.5)
	local made0 = SkinFX.Pool.Made
	local minFps, sum, n, peak = math.huge, 0, 0, 0
	for _, st in stress do trigger(st, 8) end
	local t0 = os.clock()
	while os.clock() - t0 < 8 do
		task.wait()
		local f = 1 / math.max(dtNow, 1e-3)
		minFps = math.min(minFps, f)
		sum += f; n += 1
		peak = math.max(peak, SkinFX.Pool.InUse)
	end
	for _, st in stress do st.token = (st.token or 0) + 1 end
	task.wait(1)
	for _, st in stress do if st.model then st.model:Destroy() end end
	stress = {}
	stressResult = string.format("stress (render fps): avg %.0f fps, min %.0f, peak pooled parts %d, new pool items %d", sum / math.max(n, 1), minFps, peak, SkinFX.Pool.Made - made0)
	print("[SkinRange] " .. stressResult)
	running = false
end
stressBtn.MouseButton1Click:Connect(runStress)

task.spawn(function()
	while true do
		task.wait(0.25)
		if panel.Visible then
			local P = SkinFX.Pool or { InUse = 0, Made = 0, Lights = 0 }
			stats.Text = string.format("render %.0f fps (Studio throttles this when unfocused) · pooled in use %d · pool size %d · lights %d · detail %.2f\n%s",
				fpsEma, P.InUse, P.Made, P.Lights or 0, SkinFX.Quality(), stressResult)
			if slow then applyEmitterScale() end
		end
	end
end)

-- ─── open / close ─────────────────────────────────────────────────────────
local function setOpen(v: boolean)
	if v == open then return end
	open = v
	panel.Visible = open
	if open then
		fx = fx or WeaponEffects.new()
		build()
		mount(A); mount(B)
		hidden = {}
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then g.Enabled = false; table.insert(hidden, g) end
		end
		setCam(camName)
		SkinFX.QualityOverride = 1
		pick("q", "High")
		local hiddenSet = {}
		for _, g in hidden do hiddenSet[g] = true end
		RunService:BindToRenderStep("VantageSkinRangeHold", Enum.RenderPriority.Last.Value, function()
			local cam = Workspace.CurrentCamera
			if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
			cam.CFrame = camCF
			cam.FieldOfView = 70
			-- the lobby re-enables its menu every Heartbeat; switch it off again just before each render
			for _, g in player.PlayerGui:GetChildren() do
				if g ~= gui and g:IsA("ScreenGui") and g.Enabled then
					g.Enabled = false
					if not hiddenSet[g] then hiddenSet[g] = true; table.insert(hidden, g) end
				end
			end
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep("VantageSkinRangeHold") end)
		stopAll()
		slow = false; SkinFX.TimeScale = 1; SkinFX.QualityOverride = nil
		pick("spd", "1x"); pick("q", "Auto")
		if range then range:Destroy(); range = nil end
		A.model, B.model = nil, nil
		for _, g in hidden do if g.Parent then g.Enabled = true end end
		hidden = {}
		local cam = Workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
	end
end
toggle.MouseButton1Click:Connect(function() setOpen(not open) end)

-- automation hook (Studio tests): gui.Cmd:Invoke(command, ...)
local cmd = Instance.new("BindableFunction")
cmd.Name = "Cmd"
cmd.Parent = gui
cmd.OnInvoke = function(c, x, y)
	if c == "open" then setOpen(true)
	elseif c == "close" then setOpen(false)
	elseif c == "set" then -- x = "A"|"B", y = { weapon, skinId }
		local st = if x == "B" then B else A
		st.w = y[1]; st.ix = 1
		for k, sk in Skins.List(st.w) do if sk.Id == y[2] then st.ix = k end end
		st.on = true
		mount(st); refresh(st)
	elseif c == "fire" then trigger(A, x or 0); if B.on then trigger(B, x or 0) end
	elseif c == "stress" then task.spawn(runStress)
	elseif c == "stop" then stopAll()
	elseif c == "cam" then setCam(x); pick("cam", x)
	elseif c == "iso" then iso = x; pick("iso", x)
	elseif c == "aim" then aimIx = table.find(AIMS, x) or aimIx
	elseif c == "slow" then slow = x and true or false; SkinFX.TimeScale = if slow then 0.25 else 1; applyEmitterScale()
	elseif c == "quality" then SkinFX.QualityOverride = x
	elseif c == "panel" then panel.Visible = x and true or false; toggle.Visible = panel.Visible
	elseif c == "stats" then
		local P = SkinFX.Pool
		return string.format("fps %.0f inUse %d made %d lights %d | %s", fpsEma, P.InUse, P.Made, P.Lights or 0, stressResult)
	end
	return "ok"
end
