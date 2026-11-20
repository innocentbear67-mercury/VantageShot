--[[
	VANTAGE — EnergyFX (client)
	Shared building blocks for the exosuit energy effects (ShieldFX shields, CoreOverloadFX deaths):
	jagged electrical arcs, spark bursts, surface ripples, flashes, segmented shockwave rings and
	one-shot sounds. Everything is client-only, anchored, non-collidable, invisible to raycasts
	(CanQuery = false, so weapon prediction never hits it) and removed by Debris.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local EnergyFX = {}
local rng = Random.new()

function EnergyFX.Folder(name: string): Folder
	local f = Workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = Workspace
	end
	return f :: Folder
end

function EnergyFX.Part(props, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

function EnergyFX.Tween(inst: Instance, time: number, goal, style: Enum.EasingStyle?)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function worldAttachment(cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	a.WorldCFrame = cf
	return a
end

-- a frame looking along `dir` that never degenerates (straight up / down)
function EnergyFX.Facing(pos: Vector3, dir: Vector3): CFrame
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(pos, pos + dir, up)
end

-- a frame whose UpVector is `normal` (spark bursts emit along +Y)
function EnergyFX.UpFrame(pos: Vector3, normal: Vector3): CFrame
	return EnergyFX.Facing(pos, normal) * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function perpendicular(dir: Vector3): Vector3
	local u = dir.Unit
	local r = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	local p = r - u * r:Dot(u)
	if p.Magnitude < 1e-3 then
		p = u:Cross(if math.abs(u.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis)
	end
	return p.Unit
end

--[[ Arc(a, b, opts): a jagged electrical arc between two world points, re-struck once mid-life.
	opts: Color, Width (studs), Life (s), Segments, Jitter (fraction of the length), Brightness ]]
function EnergyFX.Arc(a: Vector3, b: Vector3, opts)
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then
		return
	end
	local n = opts.Segments or 5
	local life = opts.Life or 0.1
	local jitter = (opts.Jitter or 0.18) * len
	local atts = table.create(n + 1)
	for i = 1, n + 1 do
		local att = Instance.new("Attachment")
		att.Parent = Workspace.Terrain
		atts[i] = att
	end
	local function strike()
		for i = 0, n do
			local off = if i == 0 or i == n then Vector3.zero else perpendicular(d) * rng:NextNumber(0.3, 1) * jitter
			atts[i + 1].WorldPosition = a + d * (i / n) + off
		end
	end
	strike()
	local color = ColorSequence.new(opts.Color or Color3.new(1, 1, 1))
	local w = opts.Width or 0.06
	for i = 1, n do
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = atts[i], atts[i + 1]
		beam.Width0, beam.Width1 = w, w
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = opts.Brightness or 4
		beam.Color = color
		beam.Transparency = NumberSequence.new(0)
		beam.Segments = 1
		beam.Parent = atts[i]
	end
	task.delay(life * 0.5, strike)
	for _, att in atts do
		Debris:AddItem(att, life)
	end
end

--[[ Sparks(cf, count, opts): one burst of hot sparks along cf.UpVector.
	opts: Color0, Color1, Speed (NumberRange), Spread (deg, 180 = all round), Life (NumberRange),
	Size, Drag, Gravity, Brightness ]]
function EnergyFX.Sparks(cf: CFrame, count: number, opts)
	local att = worldAttachment(cf)
	local p = Instance.new("ParticleEmitter")
	p.Texture = SPARK
	p.LightEmission = 1
	p.LightInfluence = 0
	p.Brightness = opts.Brightness or 3
	local c0 = opts.Color0 or Color3.new(1, 1, 1)
	p.Color = ColorSequence.new(c0, opts.Color1 or c0)
	p.Size = NumberSequence.new(opts.Size or 0.18, 0)
	local life = opts.Life or NumberRange.new(0.15, 0.35)
	p.Lifetime = life
	p.Speed = opts.Speed or NumberRange.new(12, 26)
	p.Drag = opts.Drag or 5
	p.Acceleration = Vector3.new(0, -(opts.Gravity or 30), 0)
	local spread = opts.Spread or 55
	p.SpreadAngle = Vector2.new(spread, spread)
	p.EmissionDirection = Enum.NormalId.Top
	p.Orientation = Enum.ParticleOrientation.VelocityParallel
	p.Rate = 0
	p.Enabled = false
	p.Parent = att
	p:Emit(count)
	Debris:AddItem(att, life.Max + 0.2)
end

-- a ripple spreading over a surface: a ForceField disc facing `normal` that grows and fades
function EnergyFX.Ripple(pos: Vector3, normal: Vector3, opts)
	local life = opts.Life or 0.22
	local from, to = opts.From or 0.3, opts.To or 2
	local cf = EnergyFX.Facing(pos, normal) * CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (X) along the normal
	local disc = EnergyFX.Part({
		Shape = Enum.PartType.Cylinder, Material = opts.Material or Enum.Material.ForceField, Color = opts.Color,
		Size = Vector3.new(0.05, from, from), CFrame = cf, Transparency = opts.Transparency or 0,
	}, opts.Folder)
	EnergyFX.Tween(disc, life, { Size = Vector3.new(0.05, to, to), Transparency = 1 })
	Debris:AddItem(disc, life + 0.05)
end

--[[ Flash(pos, opts): a hot energy flash, a neon ball that blooms and fades.
	opts: Color, From, To (diameters), Life, Transparency, Material, Folder,
	Light = { Color, Range, Brightness, Life } (optional short point light) ]]
function EnergyFX.Flash(pos: Vector3, opts)
	local life = opts.Life or 0.12
	local ball = EnergyFX.Part({
		Shape = Enum.PartType.Ball, Material = opts.Material or Enum.Material.Neon, Color = opts.Color,
		Size = Vector3.one * (opts.From or 0.4), CFrame = CFrame.new(pos), Transparency = opts.Transparency or 0.1,
	}, opts.Folder)
	EnergyFX.Tween(ball, life, { Size = Vector3.one * (opts.To or 1.5), Transparency = 1 })
	Debris:AddItem(ball, life + 0.05)
	local L = opts.Light
	if L then
		local att = worldAttachment(CFrame.new(pos))
		local light = Instance.new("PointLight")
		light.Color = L.Color or opts.Color
		light.Range = L.Range or 8
		light.Brightness = L.Brightness or 3
		light.Shadows = false
		light.Parent = att
		EnergyFX.Tween(light, L.Life or life * 1.5, { Brightness = 0 })
		Debris:AddItem(att, (L.Life or life * 1.5) + 0.05)
	end
end

--[[ ShockRing(cf, opts): a hollow shockwave ring of glowing segments expanding in the plane of
	cf (cf.UpVector is the ring's axis). opts: From, To (radius), Life, Segments, Thickness, Color,
	Material, Transparency, Folder ]]
function EnergyFX.ShockRing(cf: CFrame, opts)
	local n = opts.Segments or 18
	local life = opts.Life or 0.5
	local thick = opts.Thickness or 0.3
	local r0, r1 = opts.From or 1, opts.To or 12
	local info = TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	for i = 1, n do
		local around = cf * CFrame.Angles(0, (i / n) * math.pi * 2, 0)
		local seg = EnergyFX.Part({
			Material = opts.Material or Enum.Material.Neon, Color = opts.Color, Transparency = opts.Transparency or 0.05,
			Size = Vector3.new(2 * math.pi * r0 / n * 1.08, thick, thick), CFrame = around * CFrame.new(0, 0, -r0),
		}, opts.Folder)
		TweenService:Create(seg, info, {
			CFrame = around * CFrame.new(0, 0, -r1),
			Size = Vector3.new(2 * math.pi * r1 / n * 1.08, thick * 0.4, thick * 0.4),
			Transparency = 1,
		}):Play()
		Debris:AddItem(seg, life + 0.05)
	end
end

--[[ Sound(list, at, opts): one-shot sounds. list = { { Id, Volume, StartAt?, Speed?, Duration? } };
	at = world position (3D) or nil (2D, e.g. for your own character). opts: Volume, Speed
	(multipliers), RollOffMin, RollOffMax, Life. Returns the Sound instances. ]]
function EnergyFX.Sound(list, at: Vector3?, opts): { Sound }
	opts = opts or {}
	local life = opts.Life or 6
	local holder: Attachment? = nil
	if at then
		holder = worldAttachment(CFrame.new(at))
		Debris:AddItem(holder :: Attachment, life)
	end
	local group = SoundService:FindFirstChild("VantageEffects") :: SoundGroup?
	local out = {}
	for _, spec in list do
		local s = Instance.new("Sound")
		s.SoundId = spec.Id
		s.Volume = spec.Volume * (opts.Volume or 1)
		s.PlaybackSpeed = (spec.Speed or 1) * (opts.Speed or 1) * (0.97 + rng:NextNumber() * 0.06)
		s.TimePosition = spec.StartAt or 0
		s.SoundGroup = group
		if holder then
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = opts.RollOffMin or 8
			s.RollOffMaxDistance = opts.RollOffMax or 160
			s.Parent = holder
		else
			s.Parent = SoundService
			Debris:AddItem(s, life)
		end
		s:Play()
		if spec.Duration then
			task.delay(spec.Duration, function()
				if s.Parent then
					s:Stop()
				end
			end)
		end
		table.insert(out, s)
	end
	return out
end

return EnergyFX
