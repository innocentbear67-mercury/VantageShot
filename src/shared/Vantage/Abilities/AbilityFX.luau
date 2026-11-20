--[[
	VANTAGE — AbilityFX (client)
	World-space activation effects for Phase Dash, High Jump and Pulse Scan, plus the Pulse Scan
	reveal. The caster plays its own copy instantly; other clients play it when the server relays it.
	All parts are anchored, non-colliding and non-queryable (weapon raycasts ignore them) and
	clean themselves up. Design language: cyan = player tech, red = revealed enemies only.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Config = require(script.Parent.AbilityConfig)
local COL = Config.Colors
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local AbilityFX = {}

local folder: Folder? = nil
local function fxFolder(): Folder
	if not folder or not folder.Parent then
		folder = Workspace:FindFirstChild("VantageAbilityFX") :: Folder? or Instance.new("Folder")
		folder.Name = "VantageAbilityFX"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function fxPart(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = COL.Cyan
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent or fxFolder()
	return p
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function cleanup(inst: Instance, t: number)
	task.delay(t, function()
		inst:Destroy()
	end)
end

local function flashLight(pos: Vector3, range: number, brightness: number, t: number)
	local p = fxPart({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color = COL.Cyan
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	tween(l, t, { Brightness = 0 })
	cleanup(p, t + 0.05)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function groundBelow(character: Model, root: BasePart): Vector3
	groundParams.FilterDescendantsInstances = { character, fxFolder() }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
	return if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
end

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

-- one-shot particle burst at a world position or attachment
local function burst(parent: Instance, count: number, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEXTURE
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new(COL.Hot, COL.Cyan)
	e.Transparency = seq(0.1, 1)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	e:Emit(count)
	cleanup(e, 1.5)
	return e
end

-- Expanding ring of short neon segments. Height > ~0.3 turns it into a short holographic wall.
local function ring(center: Vector3, r0: number, r1: number, duration: number, opts: { [string]: any })
	local n = opts.Segments or 32
	local height = opts.Height or 0.15
	local width = opts.Width or 0.35
	local t0 = opts.Transparency or 0
	local fadePower = opts.FadePower or 1.6
	local model = Instance.new("Model")
	model.Name = "Ring"
	local segs = table.create(n)
	for i = 1, n do
		segs[i] = fxPart({ Color = opts.Color or COL.Cyan, Transparency = 1, Size = Vector3.new(0.1, height, width), CFrame = CFrame.new(center) }, model)
	end
	model.Parent = fxFolder()
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / duration, 0, 1)
		local e = 1 - (1 - a) ^ 3
		local r = r0 + (r1 - r0) * e
		local len = 2 * math.pi * r / n * 1.06
		local tr = t0 + (1 - t0) * (a ^ fadePower)
		for i, s in segs do
			local ang = (i / n) * 2 * math.pi
			s.Size = Vector3.new(len, height, width)
			s.CFrame = CFrame.new(center) * CFrame.Angles(0, ang, 0) * CFrame.new(0, height / 2, -r)
			s.Transparency = tr
		end
		if a >= 1 then
			conn:Disconnect()
			model:Destroy()
		end
	end)
end

-- Translucent cyan snapshot of a character (Phase Dash afterimage).
local function afterimage(character: Model, transparency: number, life: number)
	local model = Instance.new("Model")
	model.Name = "Afterimage"
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and not d.Parent:IsA("Accessory") then
			local ok, c = pcall(d.Clone, d)
			if ok and c then
				c:ClearAllChildren()
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.Material = Enum.Material.Neon
				c.Color = COL.Cyan
				c.Transparency = transparency
				if c:IsA("MeshPart") then
					c.TextureID = ""
				end
				c.Parent = model
				tween(c, life, { Transparency = 1 })
			end
		end
	end
	model.Parent = fxFolder()
	cleanup(model, life + 0.05)
end

local function attachTrail(root: BasePart, top: Vector3, bottom: Vector3, props: { [string]: any }, life: number)
	local a0 = Instance.new("Attachment")
	a0.Position = top
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = bottom
	a1.Parent = root
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.FaceCamera = true
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.Color = ColorSequence.new(COL.Hot, COL.Cyan)
	for k, v in props do
		(tr :: any)[k] = v
	end
	tr.Parent = root
	task.delay(life, function()
		tr.Enabled = false
	end)
	task.delay(life + tr.Lifetime + 0.05, function()
		tr:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

local function screenPulse(brightness: number, blur: number, t: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "VantageAbilityPulse"
	cc.TintColor = Color3.fromRGB(205, 232, 255)
	cc.Brightness = brightness
	cc.Contrast = 0.08
	cc.Parent = Lighting
	tween(cc, t, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0 })
	cleanup(cc, t + 0.05)
	if blur > 0 then
		local b = Instance.new("BlurEffect")
		b.Name = "VantageAbilityBlur"
		b.Size = blur
		b.Parent = Lighting
		tween(b, t * 0.8, { Size = 0 })
		cleanup(b, t + 0.05)
	end
end

-- ── Sound ────────────────────────────────────────────────────────────────────────────────────────
-- Caster hears it flat (2D, no distance falloff); everyone else hears it positioned at the caster.
local SoundService = game:GetService("SoundService")
local function playCue(spec, root: BasePart?, isLocal: boolean, speedScale: number?)
	if not spec then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume or 0.5
	s.PlaybackSpeed = (spec.Speed or 1) * (speedScale or 1) * (0.96 + math.random() * 0.08)
	s.TimePosition = spec.StartAt or 0
	s.SoundGroup = SoundService:FindFirstChild("VantageEffects") :: SoundGroup?
	if isLocal or not root then
		s.Parent = SoundService
	else
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = Config.SoundRollOff.Min
		s.RollOffMaxDistance = Config.SoundRollOff.Max
		s.Parent = root
	end
	s:Play()
	if spec.PitchRise then
		-- dynamic pitch: the cue climbs while the jump accelerates
		local r = spec.PitchRise
		s.PlaybackSpeed = r[1] * (speedScale or 1)
		TweenService:Create(s, TweenInfo.new(r[3], Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { PlaybackSpeed = r[2] * (speedScale or 1) }):Play()
	end
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end
local function playCues(list, root: BasePart?, isLocal: boolean, speedScale: number?)
	for _, spec in list or {} do
		playCue(spec, root, isLocal, speedScale)
	end
end
AbilityFX.PlayCue = playCue

-- ── Phase Dash ──────────────────────────────────────────────────────────────────────────────────

function AbilityFX.PhaseDash(character: Model, dir: Vector3, isLocal: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local A = Config.Abilities.PhaseDash
	local origin = root.Position
	local face = CFrame.lookAt(origin, origin + dir)

	-- phase rift where the dash began (flat ellipsoid facing the dash direction)
	for i, spec in { { COL.Cyan, Vector3.new(2.6, 7, 0.2), 0.25 }, { COL.Hot, Vector3.new(0.7, 5.6, 0.12), 0.05 } } do
		local rift = fxPart({ Color = spec[1], Size = spec[2], CFrame = face, Transparency = spec[3] })
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = rift
		tween(rift, 0.35 + i * 0.05, { Size = spec[2] * Vector3.new(1.7, 1.25, 0.4), Transparency = 1 })
		cleanup(rift, 0.5)
	end
	flashLight(origin, 14, 2.5, 0.3)

	-- energy trail: wide body blade + bright core
	attachTrail(root, Vector3.new(0, 1.3, 0), Vector3.new(0, -1.7, 0), {
		Lifetime = 0.3,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		WidthScale = seq(1, 0.3),
	}, A.Duration)
	attachTrail(root, Vector3.new(0, 0.35, 0), Vector3.new(0, -0.05, 0), {
		Lifetime = 0.22,
		Color = ColorSequence.new(Color3.new(1, 1, 1), COL.Hot),
		Transparency = seq(0, 1),
	}, A.Duration)

	-- spark shards shed along the path
	local att = Instance.new("Attachment")
	att.Parent = root
	cleanup(att, 1.6)
	local sparkProps = {
		Size = seq(0.16, 0),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(4, 12),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
	}
	burst(att, 18, sparkProps)
	task.delay(A.Duration, function()
		if att.Parent then
			burst(att, 14, sparkProps)
		end
	end)

	playCues(Config.Sounds.PhaseDash, root, isLocal)

	-- trailing energy ghosts: large faint silhouettes shed along the path (everyone)
	local ghostAtt = Instance.new("Attachment")
	ghostAtt.Parent = root
	cleanup(ghostAtt, 1.2)
	local ghost = Instance.new("ParticleEmitter")
	ghost.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ghost.Color = ColorSequence.new(COL.Hot, COL.Cyan)
	ghost.LightEmission = 0.9
	ghost.LightInfluence = 0
	ghost.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 1.4) })
	ghost.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	ghost.Lifetime = NumberRange.new(0.25, 0.4)
	ghost.Speed = NumberRange.new(0)
	ghost.Rate = 70
	ghost.LockedToPart = false
	ghost.Parent = ghostAtt
	task.delay(A.Duration + 0.04, function()
		ghost.Enabled = false
	end)

	if isLocal then
		-- sleek motion blur: a short blur + brightness pulse that releases as the burst ends
		screenPulse(0.06, 9, 0.28)
	else
		-- afterimages (others only: in first person they would sit on your own camera)
		for i, tr in { 0.45, 0.6, 0.75 } do
			task.delay((i - 1) * A.Duration * 0.5, function()
				if character.Parent then
					afterimage(character, tr, 0.35)
				end
			end)
		end
	end
end

-- ── High Jump ─────────────────────────────────────────────────────────────────────────────────────

function AbilityFX.HighJump(character: Model, isLocal: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local ground = groundBelow(character, root) + Vector3.new(0, 0.05, 0)

	-- launch flash disc + shockwave rings flat on the floor
	local disc = fxPart({ Shape = Enum.PartType.Cylinder, Color = COL.Hot, Transparency = 0.15, Size = Vector3.new(0.08, 3, 3), CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2) })
	tween(disc, 0.4, { Size = Vector3.new(0.08, 9, 9), Transparency = 1 })
	cleanup(disc, 0.45)
	ring(ground, 1.2, 15, 0.55, { Width = 0.45, Height = 0.1, Color = COL.Hot, Segments = 36 })
	task.delay(0.07, function()
		ring(ground, 0.8, 9, 0.7, { Width = 0.25, Height = 0.08, Transparency = 0.35, Segments = 32 })
	end)

	-- vertical light shaft from the launch point
	local shaft = fxPart({ Shape = Enum.PartType.Cylinder, Transparency = 0.55, Size = Vector3.new(10, 1.3, 1.3), CFrame = CFrame.new(ground + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2) })
	tween(shaft, 0.35, { Size = Vector3.new(12, 0.1, 0.1), Transparency = 1 })
	cleanup(shaft, 0.4)

	-- rising particles + thruster plume under the feet
	local groundAtt = Instance.new("Attachment")
	groundAtt.WorldPosition = ground
	groundAtt.Parent = Workspace.Terrain
	cleanup(groundAtt, 1.8)
	burst(groundAtt, 26, {
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(35, 35),
		Size = seq(0.14, 0),
		Speed = NumberRange.new(6, 18),
		Drag = 2.5,
		Lifetime = NumberRange.new(0.6, 1.2),
	})
	local feet = Instance.new("Attachment")
	feet.Position = Vector3.new(0, -2.7, 0)
	feet.Parent = root
	local plume = Instance.new("ParticleEmitter")
	plume.Texture = SPARK_TEXTURE
	plume.EmissionDirection = Enum.NormalId.Bottom
	plume.SpreadAngle = Vector2.new(8, 8)
	plume.Rate = 140
	plume.Speed = NumberRange.new(14, 22)
	plume.Lifetime = NumberRange.new(0.15, 0.28)
	plume.Size = seq(0.55, 0)
	plume.LightEmission = 1
	plume.LightInfluence = 0
	plume.Color = ColorSequence.new(Color3.new(1, 1, 1), COL.Cyan)
	plume.Transparency = seq(0.05, 1)
	plume.Parent = feet
	task.delay(0.32, function()
		plume.Enabled = false
	end)
	cleanup(feet, 0.8)

	-- upward motion streak (ribbon between the boots)
	attachTrail(root, Vector3.new(-0.45, -2.6, 0), Vector3.new(0.45, -2.6, 0), {
		FaceCamera = false,
		Lifetime = 0.45,
		Transparency = seq(0.2, 1),
	}, 0.4)
	flashLight(ground + Vector3.new(0, 1.5, 0), 18, 3, 0.4)
	playCues(Config.Sounds.HighJump, root, isLocal)

	if isLocal then
		screenPulse(0.05, 0, 0.3)
	end
end

-- ── Pulse Scan ───────────────────────────────────────────────────────────────────────────────────

function AbilityFX.PulseScan(character: Model, isLocal: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local A = Config.Abilities.PulseScan
	local ground = groundBelow(character, root) + Vector3.new(0, 0.05, 0)

	-- wavefront: bright floor ring + short holographic wall, then a fainter echo
	ring(ground, 0.5, A.Radius, A.WaveTime, { Width = 0.6, Height = 0.1, Color = COL.Hot, Segments = 72, FadePower = 2.4 })
	ring(ground, 0.5, A.Radius, A.WaveTime, { Width = 0.12, Height = 3.5, Transparency = 0.75, Segments = 72, FadePower = 2 })
	task.delay(0.14, function()
		ring(ground, 0.5, A.Radius * 0.6, A.WaveTime * 0.9, { Width = 0.3, Height = 0.08, Transparency = 0.45, Segments = 56 })
	end)

	-- source ping at the feet
	local disc = fxPart({ Shape = Enum.PartType.Cylinder, Color = COL.Hot, Transparency = 0.25, Size = Vector3.new(0.08, 2, 2), CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2) })
	tween(disc, 0.35, { Size = Vector3.new(0.08, 7, 7), Transparency = 1 })
	cleanup(disc, 0.4)
	flashLight(root.Position, 16, 2, 0.5)
	playCues(Config.Sounds.PulseScan, root, isLocal)

	-- expanding spherical sonar wave: an outer shell (seen from outside) and an inverted inner
	-- shell (negative mesh scale flips the faces, so it is also visible once it has passed you)
	local centre = root.Position
	for _, inverted in { false, true } do
		local shell = fxPart({ Shape = Enum.PartType.Block, Material = Enum.Material.ForceField, Color = COL.Cyan, Transparency = 0.1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(centre) })
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		local sign = if inverted then -1 else 1
		mesh.Scale = Vector3.new(sign, sign, sign) * 2
		mesh.Parent = shell
		local d = A.Radius * 2
		TweenService:Create(mesh, TweenInfo.new(A.WaveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = Vector3.new(sign, sign, sign) * d }):Play()
		TweenService:Create(shell, TweenInfo.new(A.WaveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		cleanup(shell, A.WaveTime + 0.05)
	end

	if isLocal then
		screenPulse(0.04, 0, 0.45)
	end
end

-- Highlights enemies the server reported, each lighting up as the wave reaches it.
-- targets = { { Model, distance } }
function AbilityFX.Reveal(targets: { any })
	local A = Config.Abilities.PulseScan
	for _, t in targets do
		local model, dist = t[1], t[2]
		if typeof(model) ~= "Instance" or not model:IsA("Model") or type(dist) ~= "number" then
			continue
		end
		task.delay(math.clamp(dist / A.Radius, 0, 1) * A.WaveTime, function()
			if not model.Parent then
				return
			end
			local hl = Instance.new("Highlight")
			hl.Name = "VantageScanReveal"
			hl.Adornee = model
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillColor = COL.Enemy
			hl.OutlineColor = Color3.fromRGB(255, 150, 150)
			hl.FillTransparency = 0.25
			hl.OutlineTransparency = 0
			hl.Parent = fxFolder()
			-- tactical look: a hot flash on contact settling into a crisp outline with a faint fill
			tween(hl, 0.35, { FillTransparency = 0.86 })
			playCue(Config.Sounds.Reveal, nil, true)

			local head = model:FindFirstChild("Head") or model.PrimaryPart
			local bb = Instance.new("BillboardGui")
			bb.Name = "VantageScanMarker"
			bb.Adornee = head
			bb.AlwaysOnTop = true
			bb.LightInfluence = 0
			bb.Size = UDim2.fromOffset(80, 40)
			bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
			local diamond = Instance.new("Frame")
			diamond.AnchorPoint = Vector2.new(0.5, 0.5)
			diamond.Position = UDim2.new(0.5, 0, 0, 10)
			diamond.Size = UDim2.fromOffset(11, 11)
			diamond.Rotation = 45
			diamond.BackgroundTransparency = 1
			diamond.Parent = bb
			local stroke = Instance.new("UIStroke")
			stroke.Color = COL.Enemy
			stroke.Thickness = 2
			stroke.Parent = diamond
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromOffset(0, 20)
			label.Size = UDim2.new(1, 0, 0, 14)
			label.Font = Enum.Font.GothamBold
			label.TextSize = 12
			label.TextColor3 = Color3.fromRGB(255, 154, 160)
			label.TextStrokeTransparency = 0.6
			label.Text = ("%d m"):format(math.floor(dist * 0.28 + 0.5))
			label.Parent = bb
			bb.Parent = fxFolder()

			task.delay(A.RevealTime, function()
				tween(hl, 0.3, { FillTransparency = 1, OutlineTransparency = 1 })
				tween(stroke, 0.3, { Transparency = 1 })
				tween(label, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
				cleanup(hl, 0.35)
				cleanup(bb, 0.35)
			end)
		end)
	end
end

return AbilityFX
