--[[
	VANTAGE — UltClient (2026-11-18): ULT key + ORBITAL LANCE visuals (UltConfig / UltServer).
	Key (UltConfig.Key, gamepad UltConfig.Gamepad) or the HUD's ACTIVATE ULT button sends the
	camera look direction; the server decides everything else.
	Mark   dashed spinning ground ring + charge disc + targeting laser + countdown tag; enemies
	       standing in it get "INCOMING STRIKE — MOVE!"
	Strike chromatic lance slams down, white core, shockwave, sparks, smoke, debris, light,
	       scorch; camera shake (Screen shake setting) and a flash when close
	Pulse  aftershock rings from the scorch
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local lp = Players.LocalPlayer
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remote = Vantage:WaitForChild("Remotes"):WaitForChild("Ult") :: RemoteEvent
local Cfg = require(Vantage:WaitForChild("Ult"):WaitForChild("UltConfig"))

local WHITE = Color3.new(1, 1, 1)
local FRIEND = Color3.fromRGB(70, 225, 255)
local FOE = Color3.fromRGB(255, 60, 84)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local fx = Instance.new("Folder")
fx.Name = "VantageUltFX"
fx.Parent = workspace

local function rainbow(t: number, spread: number, sat: number?): ColorSequence
	local kp = {}
	for k = 0, 6 do
		kp[#kp + 1] = ColorSequenceKeypoint.new(k / 6, Color3.fromHSV((t + k / 6 * spread) % 1, sat or 0.7, 1))
	end
	return ColorSequence.new(kp)
end

local function friendly(team: string?, owner: number?): boolean
	if owner == lp.UserId then
		return true
	end
	local mine = if lp.Team and not lp.Neutral then lp.Team.Name else nil
	return team ~= nil and mine ~= nil and team == mine
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = fx
	return p
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis (X) pointing up
local function flatCF(pos: Vector3, lift: number): CFrame
	return CFrame.new(pos + Vector3.new(0, lift, 0)) * UP
end
local function columnCF(pos: Vector3, bottom: number, h: number): CFrame
	return CFrame.new(pos + Vector3.new(0, bottom + h / 2, 0)) * UP
end

local function sound(def, pos: Vector3, maxDist: number?)
	if not def then
		return
	end
	local a = part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(pos), Material = Enum.Material.SmoothPlastic })
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume or 1
	s.PlaybackSpeed = def.Speed or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = maxDist or 700
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 8)
end

-- ── one frame loop for every effect ──
local anims = {}
local function animate(dur: number, fn: (number, number) -> (), done: (() -> ())?)
	table.insert(anims, { T0 = os.clock(), Dur = dur, Fn = fn, Done = done })
end

-- ── camera shake (undone at the start of the next frame, so it never accumulates) ──
local shakeAmp, shakeUntil, shakeDur, lastShake = 0, 0, 1, CFrame.identity
local function addShake(deg: number, dur: number)
	if lp:GetAttribute("VantageScreenShake") == false then
		return
	end
	local now = os.clock()
	if deg >= shakeAmp * math.clamp((shakeUntil - now) / shakeDur, 0, 1) then
		shakeAmp, shakeUntil, shakeDur = deg, now + dur, dur
	end
end
RunService:BindToRenderStep("VantageUltShakeUndo", Enum.RenderPriority.First.Value, function()
	if lastShake ~= CFrame.identity then
		workspace.CurrentCamera.CFrame *= lastShake:Inverse()
		lastShake = CFrame.identity
	end
end)
RunService:BindToRenderStep("VantageUltShake", Enum.RenderPriority.Camera.Value + 5, function()
	local now = os.clock()
	if now >= shakeUntil then
		return
	end
	local a = math.rad(shakeAmp) * ((shakeUntil - now) / shakeDur) ^ 1.5
	lastShake = CFrame.Angles((math.random() * 2 - 1) * a, (math.random() * 2 - 1) * a, (math.random() * 2 - 1) * a * 0.5)
	workspace.CurrentCamera.CFrame *= lastShake
end)

-- ── overlay: screen flash + banner ──
local gui = Instance.new("ScreenGui")
gui.Name = "VantageUltOverlay"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = lp:WaitForChild("PlayerGui")
local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = WHITE
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui
local flashGrad = Instance.new("UIGradient")
flashGrad.Rotation = 35
flashGrad.Parent = flash

local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.25)
banner.Size = UDim2.new(0.8, 0, 0.06, 0)
banner.BackgroundTransparency = 1
banner.FontFace = FONT
banner.TextScaled = true
banner.TextColor3 = WHITE
banner.TextTransparency = 1
banner.Text = ""
banner.Parent = gui
local bannerStroke = Instance.new("UIStroke")
bannerStroke.Thickness = 3
bannerStroke.Color = Color3.fromRGB(12, 16, 34)
bannerStroke.Transparency = 1
bannerStroke.Parent = banner
local bannerGrad = Instance.new("UIGradient")
bannerGrad.Parent = banner
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner
local bannerSize = Instance.new("UITextSizeConstraint")
bannerSize.MaxTextSize = 46
bannerSize.Parent = banner

local bannerId = 0
local function showBanner(text: string, color: Color3?, dur: number)
	bannerId += 1
	local id = bannerId
	banner.Text = text
	banner.TextColor3 = color or WHITE
	bannerGrad.Enabled = color == nil -- nil = chromatic
	animate(dur, function(t, el)
		if id ~= bannerId then
			return
		end
		local a = if el < 0.12 then el / 0.12 elseif t > 0.75 then 1 - (t - 0.75) / 0.25 else 1
		banner.TextTransparency = 1 - a
		bannerStroke.Transparency = 1 - a
		bannerScale.Scale = if el < 0.18 then 1.35 - 0.35 * (el / 0.18) else 1
		if bannerGrad.Enabled then
			bannerGrad.Color = rainbow(el * 0.8, 1)
		end
	end, function()
		if id == bannerId then
			banner.TextTransparency, bannerStroke.Transparency = 1, 1
		end
	end)
end

local function myRoot(): BasePart?
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- ── emitters ──
local function emitter(att: Attachment, props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 1
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = att
	return e
end

local function groundAttachment(pos: Vector3, life: number): Attachment
	local host = part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(pos), Material = Enum.Material.SmoothPlastic })
	local att = Instance.new("Attachment")
	att.Parent = host
	Debris:AddItem(host, life)
	return att
end

-- ── MARK: the telegraph ──
local function onMark(d)
	local pos: Vector3, R: number, delay: number = d.Position, d.Radius or 18, d.Delay or 1.25
	local ally = friendly(d.Team, d.Owner)
	local col = if ally then FRIEND else FOE
	local parts = {}
	-- dashed ring (spins)
	local N = 36
	local dashes = {}
	for i = 1, N do
		local dash = part({ Size = Vector3.new(0.6, 0.25, (2 * math.pi * R / N) * 0.55), Color = col, Transparency = 0.1 })
		table.insert(dashes, dash)
		table.insert(parts, dash)
	end
	local fill = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.1, 0.1), CFrame = flatCF(pos, 0.05), Color = col, Transparency = 0.75 })
	local laser = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(400, 0.3, 0.3), CFrame = columnCF(pos, 0, 400), Color = col, Transparency = 0.15 })
	table.insert(parts, fill)
	table.insert(parts, laser)
	-- countdown tag
	local tagHost = part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(pos + Vector3.new(0, 7, 0)), Material = Enum.Material.SmoothPlastic })
	table.insert(parts, tagHost)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 56)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 900
	bb.Parent = tagHost
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundTransparency = 1
	tag.FontFace = FONT
	tag.TextScaled = true
	tag.TextColor3 = col
	tag.Text = ""
	tag.Parent = bb
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2.5
	ts.Color = Color3.fromRGB(12, 16, 34)
	ts.Parent = tag

	sound(Cfg.Sounds.Mark, pos, 500)
	if d.Owner == lp.UserId then
		showBanner("ORBITAL LANCE INBOUND", nil, 1.8)
	elseif not ally then
		local r = myRoot()
		if r and (Vector3.new(r.Position.X - pos.X, 0, r.Position.Z - pos.Z)).Magnitude < R + 10 then
			showBanner("⚠ INCOMING STRIKE — MOVE!", FOE, 1.6)
		end
	end

	animate(delay + 0.05, function(t, el)
		local spin = el * 1.4
		for i, dash in dashes do
			local a = spin + (i / N) * math.pi * 2
			local p = pos + Vector3.new(math.cos(a) * R, 0.15, math.sin(a) * R)
			dash.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
			dash.Transparency = 0.1 + 0.5 * (math.sin(el * 30 + i) * 0.5 + 0.5) * t
		end
		local rr = R * 2 * math.clamp(t, 0.02, 1)
		fill.Size = Vector3.new(0.1, rr, rr)
		fill.Transparency = 0.8 - 0.25 * t
		local w = 0.3 + 1.6 * t ^ 2
		laser.Size = Vector3.new(400, w, w)
		laser.Transparency = if math.random() < 0.15 then 0.6 else 0.1
		laser.Color = col:Lerp(WHITE, t * 0.6)
		tag.Text = string.format("%s  %.1f", if ally then "ORBITAL LANCE" else "⚠ STRIKE", math.max(0, delay - el))
	end, function()
		for _, p in parts do
			p:Destroy()
		end
	end)
end

-- ── STRIKE: the lance hits ──
local function onStrike(d)
	local pos: Vector3, R: number = d.Position, d.Radius or 18
	local H = 460
	local beam = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, R * 1.15, R * 1.15), CFrame = columnCF(pos, H, 1), Color = WHITE, Transparency = 0.2 })
	local core = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, R * 0.45, R * 0.45), CFrame = columnCF(pos, H, 1), Color = WHITE, Transparency = 0 })
	local wave = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2), CFrame = flatCF(pos, 0.4), Color = WHITE, Transparency = 0.05 })
	local wave2 = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2), CFrame = flatCF(pos, 0.25), Color = WHITE, Transparency = 0.2 })
	local scorch = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, R * 1.5, R * 1.5), CFrame = flatCF(pos, 0.06), Color = Color3.fromRGB(255, 150, 60), Transparency = 0.15 })

	local att = groundAttachment(pos + Vector3.new(0, 0.5, 0), 6)
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 6
	light.Shadows = false
	light.Parent = att
	local sparks = emitter(att, {
		Texture = SPARK_TEX,
		Lifetime = NumberRange.new(0.5, 1.3),
		Speed = NumberRange.new(45, 120),
		SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, -90, 0),
		Drag = 1.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		Color = rainbow(math.random(), 1, 0.5),
	})
	sparks:Emit(110)
	local smoke = emitter(att, {
		Texture = SMOKE_TEX,
		LightEmission = 0,
		Lifetime = NumberRange.new(1.6, 2.8),
		Speed = NumberRange.new(10, 26),
		SpreadAngle = Vector2.new(80, 80),
		Drag = 2,
		RotSpeed = NumberRange.new(-40, 40),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 16) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(70, 66, 80)),
	})
	smoke:Emit(30)
	-- debris chunks (client physics only)
	for _ = 1, 12 do
		local s = 0.5 + math.random() * 1.1
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(s, s, s)
		chunk.Material = Enum.Material.Neon
		chunk.Color = Color3.fromHSV(math.random(), 0.45, 1)
		chunk.CanCollide = true
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.Massless = true
		chunk.CastShadow = false
		chunk.CFrame = CFrame.new(pos + Vector3.new((math.random() * 2 - 1) * 3, 1.5, (math.random() * 2 - 1) * 3))
		chunk.Parent = fx
		local a = math.random() * math.pi * 2
		chunk.AssemblyLinearVelocity = Vector3.new(math.cos(a) * (20 + math.random() * 40), 45 + math.random() * 50, math.sin(a) * (20 + math.random() * 40))
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() * 20, math.random() * 20, math.random() * 20)
		Debris:AddItem(chunk, 2.5 + math.random())
	end

	sound(Cfg.Sounds.Impact, pos, 900)
	sound(Cfg.Sounds.Impact2, pos, 900)
	local cam = workspace.CurrentCamera
	local dist = (cam.CFrame.Position - pos).Magnitude
	addShake(math.clamp(4.5 * (1 - dist / 260), 0.5, 4.5), 0.9)
	local flashK = math.clamp(1 - dist / 160, 0, 1)

	local hue0 = math.random()
	animate(1.1, function(t, el)
		-- the lance drops in 0.09 s, holds, then collapses
		local drop = math.clamp(el / 0.09, 0, 1)
		local h = math.max(1, H * drop)
		local shrink = if t < 0.35 then 1 else 1 - (t - 0.35) / 0.65
		local wd = R * 1.15 * shrink * (1 + 0.06 * math.sin(el * 60))
		beam.Size = Vector3.new(h, math.max(0.05, wd), math.max(0.05, wd))
		beam.CFrame = columnCF(pos, H - h, h)
		beam.Color = Color3.fromHSV((hue0 + el * 2.2) % 1, 0.65, 1)
		beam.Transparency = 0.15 + 0.6 * (1 - shrink)
		local cw = R * 0.45 * shrink
		core.Size = Vector3.new(h, math.max(0.05, cw), math.max(0.05, cw))
		core.CFrame = beam.CFrame
		core.Transparency = 0.6 * (1 - shrink)
		local wr = 2 + R * 2.6 * (1 - (1 - t) ^ 3)
		wave.Size = Vector3.new(0.4, wr, wr)
		wave.Transparency = 0.05 + 0.95 * t
		wave.Color = Color3.fromHSV((hue0 + 0.5 + el) % 1, 0.4, 1)
		local wr2 = 2 + R * 1.7 * (1 - (1 - math.clamp(t * 1.4, 0, 1)) ^ 2)
		wave2.Size = Vector3.new(0.3, wr2, wr2)
		wave2.Transparency = 0.2 + 0.8 * math.clamp(t * 1.4, 0, 1)
		light.Color = beam.Color
		light.Brightness = 6 * (1 - t)
		if flashK > 0 then
			flash.BackgroundTransparency = 1 - flashK * 0.32 * math.clamp(1 - el / 0.35, 0, 1)
			flashGrad.Color = rainbow(hue0 + el, 1, 0.35)
		end
	end, function()
		beam:Destroy()
		core:Destroy()
		wave:Destroy()
		wave2:Destroy()
		flash.BackgroundTransparency = 1
	end)
	-- scorched, glowing ground cools down
	animate(4.5, function(t)
		scorch.Color = Color3.fromRGB(255, 150, 60):Lerp(Color3.fromRGB(40, 30, 40), t)
		scorch.Transparency = 0.15 + 0.85 * t ^ 2
	end, function()
		scorch:Destroy()
	end)
end

-- ── PULSE: aftershock ──
local function onPulse(d)
	local pos: Vector3, R: number = d.Position, d.Radius or 12
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2), CFrame = flatCF(pos, 0.3), Color = WHITE, Transparency = 0.2 })
	local att = groundAttachment(pos + Vector3.new(0, 0.5, 0), 3)
	emitter(att, {
		Texture = SPARK_TEX,
		Lifetime = NumberRange.new(0.3, 0.8),
		Speed = NumberRange.new(25, 60),
		SpreadAngle = Vector2.new(80, 80),
		Acceleration = Vector3.new(0, -80, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Color = rainbow(math.random(), 1, 0.5),
	}):Emit(30)
	sound(Cfg.Sounds.Pulse, pos, 400)
	local dist = (workspace.CurrentCamera.CFrame.Position - pos).Magnitude
	if dist < 90 then
		addShake(1.2 * (1 - dist / 90) + 0.3, 0.3)
	end
	local hue0 = math.random()
	animate(0.45, function(t)
		local r = 2 + R * 2 * (1 - (1 - t) ^ 2)
		ring.Size = Vector3.new(0.3, r, r)
		ring.Transparency = 0.2 + 0.8 * t
		ring.Color = Color3.fromHSV((hue0 + t) % 1, 0.5, 1)
	end, function()
		ring:Destroy()
	end)
end

Remote.OnClientEvent:Connect(function(kind: string, d: any)
	if kind == "Mark" and type(d) == "table" then
		onMark(d)
	elseif kind == "Strike" and type(d) == "table" then
		onStrike(d)
	elseif kind == "Pulse" and type(d) == "table" then
		onPulse(d)
	elseif kind == "Denied" then
		showBanner("ULT UNAVAILABLE — " .. tostring(d or ""), FOE, 1.4)
	end
end)

-- ── input ──
local function tryActivate()
	if lp:GetAttribute("UltReady") ~= true then
		return
	end
	Remote:FireServer("Activate", workspace.CurrentCamera.CFrame.LookVector)
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Cfg.Key or input.KeyCode == Cfg.Gamepad then
		tryActivate()
	end
end)

lp:GetAttributeChangedSignal("UltReady"):Connect(function()
	if lp:GetAttribute("UltReady") == true then
		showBanner("ULT READY — PRESS [" .. Cfg.KeyLabel .. "]", nil, 2.2)
	end
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #anims, 1, -1 do
		local a = anims[i]
		local el = now - a.T0
		local t = math.clamp(el / a.Dur, 0, 1)
		local ok, err = pcall(a.Fn, t, el)
		if not ok then
			warn("[VANTAGE] ult fx: " .. tostring(err))
		end
		if t >= 1 or not ok then
			table.remove(anims, i)
			if a.Done then
				pcall(a.Done)
			end
		end
	end
end)
