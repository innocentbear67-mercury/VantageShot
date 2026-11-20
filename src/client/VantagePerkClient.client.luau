--[[
	VANTAGE — VantagePerkClient (2026-11-18, reworked 2026-11-19): the client side of the equipment traits that are not
	the grapple itself. Everything here is drawn by every client for every character, from server-set attributes.
	  Glide (Seraph Array)    hold jump while falling: fall held at Params.FallSpeed for Params.Time; refills on landing
	                          AND on letting go of a grapple. Tells the server (Remotes.PerkState "Glide") so the character
	                          attribute Gliding replicates and everyone sees the wings.
	  Marks / reveals         MarkedUntil / MarkedBy == your team (Harpoon, Starfall): red see-through outline
	  Overshield (Halo Ring)  Overshield > 0: a gold shimmer + light on the body (visible to enemies on purpose), a gold
	                          burst and crack when it pops
	  Perch (Mag-Anchor)      PerchAt / PerchN: pulsing red magnetic rings on the wall + a low hum (3D)
	  Event Horizon           PhaseUntil > now: the body shimmers half-transparent with an orange edge
	  Squad Pulse             PulsedAt on you (an ally's Pulsar): a pink edge flash
	  Slowed                  PerkSlowUntil on you (a gravity well): violet screen edge + label at the bottom edge
	  Low shield              your shield drops below 25 %: one double beep + a short crackling edge (no loop)
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Catalog = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local MovementController = require(script.Parent:WaitForChild("VantageMovementClient"):WaitForChild("MovementController"))
local EnergyFX = require(script.Parent:WaitForChild("VantageWeaponClient"):WaitForChild("EnergyFX"))
local PerkState = Vantage:WaitForChild("Remotes"):WaitForChild("PerkState", 15) :: RemoteEvent?
local player = Players.LocalPlayer

local function characters(includeMe: boolean): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character and (includeMe or p ~= player) then
			table.insert(list, p.Character)
		end
	end
	for _, tag in { "VantageBot", "VantageDummy" } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end
local function torsoOf(m: Model): BasePart?
	local t = m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso")
	return if t and t:IsA("BasePart") then t else nil
end
-- silent lead-ins of the library sounds used here (AudioAnalyzer onsets, as in AbilityConfig.Sounds)
local LEAD = { ["rbxassetid://9125981410"] = 0.42, ["rbxassetid://9114315137"] = 0.17, ["rbxassetid://9114592245"] = 0.42,
	["rbxassetid://9125648149"] = 0.05, ["rbxassetid://9125577419"] = 0.24, ["rbxassetid://9120769331"] = 0.05, ["rbxassetid://9125980435"] = 0.22 }
local function snd(id: string, vol: number, speed: number, at: Instance?)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = id, vol, speed
	s.TimePosition = LEAD[id] or 0
	s.RollOffMinDistance, s.RollOffMaxDistance = 8, 120
	s.Parent = at or game:GetService("SoundService")
	s:Play()
	Debris:AddItem(s, 4)
	return s
end

-- ── Glide ────────────────────────────────────────────────────────────────────────────────
local wingsOf: { [Model]: Model } = setmetatable({}, { __mode = "k" }) :: any
local function buildWings(character: Model, color: Color3)
	local torso = torsoOf(character)
	if not torso then
		return nil
	end
	local folder = Instance.new("Model")
	folder.Name = "VantageGlideWings"
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		w.Name = "Wing"
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow, w.Massless = false, false, false, false, false, true
		w.Material = Enum.Material.Neon
		w.Color = color
		w.Transparency = 1
		w.Size = Vector3.new(0.15, 1.2, 4.2)
		local weld = Instance.new("Weld")
		weld.Part0, weld.Part1 = torso, w
		weld.C0 = CFrame.new(side * 2.2, 0.4, 0.55) * CFrame.Angles(0, math.rad(side * 90), math.rad(side * -12))
		weld.Parent = w
		w.Parent = folder
	end
	local a = Instance.new("Attachment")
	a.Parent = torso
	local pe = Instance.new("ParticleEmitter") -- feathers of light trailing the wings
	pe.Name = "GlideFeathers"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.LightEmission, pe.LightInfluence = 1, 0
	pe.Size = NumberSequence.new(0.35, 0)
	pe.Lifetime = NumberRange.new(0.4, 0.7)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.Rate = 0
	pe.Parent = a
	folder:SetAttribute("Feathers", true)
	folder.Parent = character
	folder.Destroying:Connect(function()
		a:Destroy()
	end)
	return folder, pe
end
local featherOf: { [Model]: ParticleEmitter } = setmetatable({}, { __mode = "k" }) :: any
local function showWings(character: Model, on: boolean)
	local w = wingsOf[character]
	if on and not (w and w.Parent == character) then
		local _, _, it = Catalog.AbilityOf(character, "Pack")
		local pe
		w, pe = buildWings(character, it.Color)
		wingsOf[character] = w
		featherOf[character] = pe
		if w then
			snd("rbxassetid://9125648149", 0.35, 0.8, torsoOf(character))
		end
	end
	if w and w.Parent then
		for _, p in w:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = if on then 0.25 else 1
			end
		end
		local pe = featherOf[character]
		if pe then
			pe.Rate = if on then 40 else 0
		end
	end
end

local budget, gliding, wasGrappling = 0, false, false
local function setGliding(on: boolean)
	if gliding == on then
		return
	end
	gliding = on
	if player.Character then
		showWings(player.Character, on)
	end
	if PerkState then
		PerkState:FireServer("Glide", on)
	end
end
RunService.Heartbeat:Connect(function(dt)
	local character = player.Character
	local mv = MovementController.Current
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not mv or not root or not hum or hum.Health <= 0 then
		setGliding(false)
		return
	end
	local id, P = Catalog.AbilityOf(player, "Pack")
	if id ~= "Glide" then
		setGliding(false)
		return
	end
	local grappling = mv:IsGrappling()
	if mv.Grounded or (wasGrappling and not grappling) then
		budget = P.Time or 2 -- refills on landing and when you let go of a grapple
	end
	wasGrappling = grappling
	local v = root.AssemblyLinearVelocity
	local fall = P.FallSpeed or 8
	local busy = grappling or mv:IsHanging() or (mv.IsPerched and mv:IsPerched()) or character:GetAttribute("InVehicle")
	local want = not mv.Grounded and not busy and mv.Input and mv.Input.JumpHeld and v.Y < -fall and budget > 0
	if want then
		budget -= dt
		root.AssemblyLinearVelocity = Vector3.new(v.X, -fall, v.Z)
		setGliding(true)
	elseif gliding and (v.Y >= -fall - 0.5 or budget <= 0 or mv.Grounded or busy or not (mv.Input and mv.Input.JumpHeld)) then
		setGliding(false)
	end
end)

-- ── screen edges (all at the very edge: nothing near the crosshair) ─────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "VantagePerkScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2
local function edgeLabel(name: string, color: Color3): ImageLabel
	local e = Instance.new("ImageLabel")
	e.Name = name
	e.BackgroundTransparency = 1
	e.Image = "rbxassetid://104786452938879" -- soft glow frame (lobby kit)
	e.ImageColor3 = color
	e.ImageTransparency = 1
	e.ScaleType = Enum.ScaleType.Slice
	e.SliceCenter = Rect.new(130, 130, 410, 310)
	e.Size = UDim2.fromScale(1, 1)
	e.Parent = gui
	return e
end
local edge = edgeLabel("Slowed", Color3.fromRGB(160, 90, 255))
local pulseEdge = edgeLabel("Pulsed", Color3.fromRGB(255, 90, 200))
local lowEdge = edgeLabel("LowShield", Color3.fromRGB(120, 200, 255))
local tag = Instance.new("TextLabel")
tag.Name = "SlowTag"
tag.BackgroundTransparency = 1
tag.AnchorPoint = Vector2.new(0.5, 1)
tag.Position = UDim2.new(0.5, 0, 0.97, 0) -- 2026-11-19: bottom edge (was 62 % height, by the crosshair)
tag.Size = UDim2.fromOffset(300, 24)
tag.Font = Enum.Font.GothamBlack
tag.TextSize = 16
tag.TextColor3 = Color3.fromRGB(220, 190, 255)
tag.Text = "GRAVITY WELL  ·  SLOWED"
tag.TextTransparency = 1
tag.TextStrokeTransparency = 1
tag.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")
local function flashEdge(e: ImageLabel, peak: number, time: number)
	e.ImageTransparency = peak
	TweenService:Create(e, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 1 }):Play()
end

-- ── per character visuals: Overshield, Perch, Phase ───────────────────────────────────────────
type Vis = { Over: any?, OverWas: number, Perch: any?, Phased: boolean, Hl: Highlight?, Faded: { BasePart }? }
local vis: { [Model]: Vis } = setmetatable({}, { __mode = "k" }) :: any
local GOLD, GOLD2 = Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 244, 210)

local function overOn(m: Model, v: Vis)
	local t = torsoOf(m)
	if not t then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "VantageOverAura"
	a.Parent = t
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(GOLD2, GOLD)
	pe.LightEmission, pe.LightInfluence = 1, 0
	pe.Size = NumberSequence.new(0.28, 0)
	pe.Lifetime = NumberRange.new(0.5, 0.9)
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.Rate = 26
	pe.Parent = a
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = GOLD, 7, 1.2, false
	l.Parent = a
	v.Over = a
end
local function overOff(m: Model, v: Vis, popped: boolean)
	if v.Over then
		v.Over:Destroy()
		v.Over = nil
	end
	local t = torsoOf(m)
	if popped and t then
		local f = EnergyFX.Folder("VantagePerkFXLocal")
		EnergyFX.Flash(t.Position, { Color = GOLD2, From = 0.8, To = 5, Life = 0.22, Transparency = 0.35, Folder = f, Light = { Color = GOLD, Range = 14, Brightness = 4, Life = 0.35 } })
		EnergyFX.Sparks(CFrame.new(t.Position), 22, { Color0 = GOLD2, Color1 = GOLD, Spread = 180, Speed = NumberRange.new(14, 26), Life = NumberRange.new(0.25, 0.5), Size = 0.18, Gravity = 20, Drag = 3 })
		snd("rbxassetid://9114592245", 0.55, 0.85, if m == player.Character then nil else t)
	end
end

local function perchOn(m: Model, v: Vis, at: Vector3, n: Vector3)
	local f = EnergyFX.Folder("VantagePerkFXLocal")
	local _, _, it = Catalog.AbilityOf(m, "Hook")
	local col = it and it.Color or Color3.fromRGB(255, 60, 40)
	local cf = CFrame.lookAt(at + n * 0.08, at + n) * CFrame.Angles(0, math.rad(90), 0)
	local disc = EnergyFX.Part({ Name = "PerchDisc", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = col, Transparency = 0.35, Size = Vector3.new(0.06, 3.2, 3.2), CFrame = cf }, f)
	local ring = EnergyFX.Part({ Name = "PerchRing", Shape = Enum.PartType.Cylinder, Material = Enum.Material.ForceField, Color = col, Transparency = 0.2, Size = Vector3.new(0.06, 2, 2), CFrame = cf }, f)
	local hum = Instance.new("Sound")
	hum.SoundId = "rbxassetid://9125980435"
	hum.Looped, hum.Volume, hum.PlaybackSpeed = true, 0.45, 0.55
	hum.RollOffMinDistance, hum.RollOffMaxDistance = 8, 60
	hum.Parent = disc
	hum:Play()
	snd("rbxassetid://9114315137", 0.45, 1.6, disc) -- the clamp
	v.Perch = { Disc = disc, Ring = ring, At = os.clock(), Cf = cf }
end
local function perchOff(v: Vis)
	if v.Perch then
		v.Perch.Disc:Destroy()
		v.Perch.Ring:Destroy()
		v.Perch = nil
	end
end

local function setPhase(m: Model, v: Vis, on: boolean)
	if v.Phased == on then
		return
	end
	v.Phased = on
	if on then
		-- only parts that are shown now (a docked hook head hidden by GrappleFX stays hidden)
		v.Faded = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.LocalTransparencyModifier == 0 then
				d.LocalTransparencyModifier = 0.5
				table.insert(v.Faded :: any, d)
			end
		end
	else
		for _, d in v.Faded or {} do
			if d.Parent and d.LocalTransparencyModifier == 0.5 then
				d.LocalTransparencyModifier = 0
			end
		end
		v.Faded = nil
	end
	if on then
		local hl = Instance.new("Highlight")
		hl.Name = "VantagePhase"
		hl.FillTransparency = 1
		hl.OutlineColor = Color3.fromRGB(255, 150, 60)
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = m
		v.Hl = hl
		local t = torsoOf(m)
		if t then
			snd("rbxassetid://9125577419", 0.5, 0.55, if m == player.Character then nil else t)
		end
	elseif v.Hl then
		v.Hl:Destroy()
		v.Hl = nil
	end
end

-- ── marks, slowed, pulsed, low shield (10 Hz) ───────────────────────────────────────────────
local function myKey(): string
	return if player.Team and not player.Neutral then player.Team.Name else "U" .. player.UserId
end
local shown: { [Model]: Highlight } = {}
local lastPulsed, lastShieldFrac, lastChar = nil, 1, nil
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	-- perch rings breathe every frame
	local nowC = os.clock()
	for _, v in vis do
		local p = v.Perch
		if p then
			local k = ((nowC - p.At) * 1.6) % 1
			p.Ring.Size = Vector3.new(0.06, 2 + k * 3.2, 2 + k * 3.2)
			p.Ring.Transparency = 0.2 + 0.8 * k
		end
	end
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	local now = Workspace:GetServerTimeNow()
	local key = myKey()
	local live = {}
	local cam = Workspace.CurrentCamera.CFrame.Position
	for _, m in characters(true) do
		local h = m:FindFirstChildOfClass("Humanoid")
		local alive = h ~= nil and h.Health > 0
		local v = vis[m]
		if not v then
			v = { OverWas = 0, Phased = false }
			vis[m] = v
		end
		-- marks
		local u = m:GetAttribute("MarkedUntil")
		if m ~= player.Character and type(u) == "number" and u > now and m:GetAttribute("MarkedBy") == key and alive then
			live[m] = true
			if not shown[m] or shown[m].Parent ~= m then
				local hl = Instance.new("Highlight")
				hl.Name = "VantageMarked"
				hl.FillColor = Color3.fromRGB(255, 60, 70)
				hl.FillTransparency = 0.6
				hl.OutlineColor = Color3.fromRGB(255, 200, 200)
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = m
				shown[m] = hl
			end
		end
		-- overshield
		local o = m:GetAttribute("Overshield") or 0
		local t = torsoOf(m)
		local near = t ~= nil and (t.Position - cam).Magnitude < 160
		if o > 0.5 and alive and near and m ~= player.Character then
			if not v.Over then
				overOn(m, v)
			end
		elseif v.Over or (v.OverWas > 0.5 and o <= 0.5) then
			overOff(m, v, alive and v.OverWas > 0.5 and o <= 0.5 and near)
		end
		v.OverWas = o
		-- perch
		local pa, pn = m:GetAttribute("PerchAt"), m:GetAttribute("PerchN")
		if typeof(pa) == "Vector3" and typeof(pn) == "Vector3" and alive then
			if not v.Perch then
				perchOn(m, v, pa, pn)
			end
		else
			perchOff(v)
		end
		-- phase (Event Horizon) and glide wings (others; yours are drawn at once by setGliding)
		local ph = m:GetAttribute("PhaseUntil")
		setPhase(m, v, type(ph) == "number" and ph > now and alive and m ~= player.Character)
		if m ~= player.Character then
			showWings(m, m:GetAttribute("Gliding") == true and alive)
		end
	end
	for m, hl in shown do
		if not live[m] then
			hl:Destroy()
			shown[m] = nil
		end
	end
	for m, v in vis do
		if not m.Parent then
			perchOff(v)
			vis[m] = nil
		end
	end
	local me = player.Character
	-- slowed
	local su = me and me:GetAttribute("PerkSlowUntil")
	local slowed = type(su) == "number" and su > now
	edge.ImageTransparency = if slowed then 0.2 else 1
	tag.TextTransparency = if slowed then 0 else 1
	tag.TextStrokeTransparency = if slowed then 0.3 else 1
	if me ~= lastChar then
		lastChar, lastPulsed, lastShieldFrac = me, me and me:GetAttribute("PulsedAt"), 1
	end
	if me then
		-- an ally's Squad Pulse reached you
		local pu = me:GetAttribute("PulsedAt")
		if pu ~= lastPulsed then
			lastPulsed = pu
			if type(pu) == "number" then
				flashEdge(pulseEdge, 0.25, 0.7)
				snd("rbxassetid://9125981410", 0.35, 1.9)
			end
		end
		-- low shield: once, crossing below 25 %
		local s, mx = me:GetAttribute("Shield") or 0, me:GetAttribute("MaxShield") or 0
		local frac = if mx > 0 then s / mx else 1
		local hum = me:FindFirstChildOfClass("Humanoid")
		if frac < 0.25 and lastShieldFrac >= 0.25 and hum and hum.Health > 0 then
			lowEdge.ImageColor3 = (Catalog.ShieldColors(me))
			flashEdge(lowEdge, 0.15, 0.6)
			snd("rbxassetid://9125981410", 0.4, 2.6)
			task.delay(0.13, function()
				snd("rbxassetid://9125981410", 0.4, 2.6)
			end)
		end
		lastShieldFrac = frac
	end
end)
