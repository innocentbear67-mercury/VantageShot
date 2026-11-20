--[[
	VANTAGE — VehicleFX (client)
	Everything a vehicle weapon looks and sounds like, for every client: muzzle flashes at the
	visual barrel, cannon shells flying the server's ballistic path, MG tracers + impacts,
	explosions, and the destruction blast. Purely cosmetic — the server already decided every hit.
	Particle textures are Roblox's built-in rbxasset:// particles.
]]

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Vehicles.VehicleConfig)

local FX = {}
FX.Shake = 0 -- read by the vehicle camera

local HOT = Color3.fromRGB(255, 196, 110)
local TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

local holder: Folder
local function fxFolder(): Folder
	if not holder or not holder.Parent then
		holder = Instance.new("Folder")
		holder.Name = "VehicleFX"
		holder.Parent = Workspace
	end
	return holder
end

local function anchorAt(pos: Vector3, life: number): Attachment
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	Debris:AddItem(a, life)
	return a
end

function FX.Sound(spec, parent: Instance, override: { [string]: any }?)
	if not spec or not spec.Id then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume or 1
	s.PlaybackSpeed = spec.Speed or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 900
	for k, v in override or {} do
		(s :: any)[k] = v
	end
	s.Parent = parent
	return s
end

local function oneShot(spec, pos: Vector3, override)
	local a = anchorAt(pos, 6)
	local s = FX.Sound(spec, a, override)
	if s then
		s:Play()
	end
end
FX.OneShot = oneShot

local function burst(a: Attachment, props, count: number)
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Enabled = false
	e.Parent = a
	e:Emit(count)
	return e
end

local function flashLight(pos: Vector3, color: Color3, range: number, life: number)
	local a = anchorAt(pos, life + 0.1)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 6
	l.Parent = a
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < life and l.Parent do
			l.Brightness = 6 * (1 - (os.clock() - t0) / life)
			RunService.RenderStepped:Wait()
		end
	end)
end

local function camShake(pos: Vector3, strength: number, radius: number)
	local cam = Workspace.CurrentCamera
	local d = (cam.CFrame.Position - pos).Magnitude
	if d < radius then
		FX.Shake = math.max(FX.Shake, strength * (1 - d / radius))
	end
end

local function muzzleOf(model: Model, index: number?): Attachment?
	local want = if index and index > 1 then "Muzzle" .. index else "Muzzle"
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == want then
			return d
		end
	end
	return nil
end

-- ─── muzzle ──────────────────────────────────────────────────────────────
function FX.Muzzle(model: Model, big: boolean)
	local barrel = muzzleOf(model)
	if not barrel then
		return
	end
	local cf = barrel.WorldCFrame
	local a = anchorAt(cf.Position, 2)
	a.WorldCFrame = cf
	burst(a, {
		Texture = TEX.Spark, Color = ColorSequence.new(HOT, Color3.fromRGB(255, 120, 40)),
		LightEmission = 1, Size = NumberSequence.new(if big then 5 else 1.4, 0),
		Lifetime = NumberRange.new(0.05, if big then 0.14 else 0.07), Speed = NumberRange.new(if big then 40 else 18),
		SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Front,
	}, if big then 18 else 5)
	if big then
		burst(a, {
			Texture = TEX.Smoke, Color = ColorSequence.new(Color3.fromRGB(150, 150, 150)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
			Transparency = NumberSequence.new(0.35, 1), Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(8, 22), SpreadAngle = Vector2.new(35, 35), Drag = 3, EmissionDirection = Enum.NormalId.Front,
		}, 14)
		flashLight(cf.Position, HOT, 40, 0.18)
		camShake(cf.Position, 1.1, 120)
	else
		flashLight(cf.Position, HOT, 14, 0.05)
	end
end

-- ─── cannon shells ───────────────────────────────────────────────────────
local live = {} -- [id] = { Part, Pos, Vel, G, Born }

function FX.Shell(model: Model, id: number, origin: Vector3, vel: Vector3, gravityScale: number)
	local kind = model and model:GetAttribute("VehicleType")
	local snd = kind and Config.Sounds[kind]
	if model then
		FX.Muzzle(model, true)
		if snd and snd.Fire then
			oneShot(snd.Fire, origin)
		end
	end
	local p = Instance.new("Part")
	p.Name = "Shell"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = HOT
	p.Size = Vector3.new(0.5, 0.5, 6)
	p.CFrame = CFrame.lookAt(origin, origin + vel)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.25, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.25, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.35
	tr.Color = ColorSequence.new(HOT, Color3.fromRGB(255, 255, 255))
	tr.Transparency = NumberSequence.new(0.2, 1)
	tr.LightEmission = 1
	tr.Parent = p
	p.Parent = fxFolder()
	live[id] = { Part = p, Pos = origin, Vel = vel, G = gravityScale, Born = os.clock() }
end

function FX.StepShells(dt: number)
	local g = Workspace.Gravity
	for id, s in live do
		local nv = s.Vel - Vector3.new(0, g * s.G * dt, 0)
		s.Pos += (s.Vel + nv) * 0.5 * dt
		s.Vel = nv
		s.Part.CFrame = CFrame.lookAt(s.Pos, s.Pos + nv)
		if os.clock() - s.Born > 5 then
			s.Part:Destroy()
			live[id] = nil
		end
	end
end

local function explosion(pos: Vector3, radius: number, big: boolean)
	local a = anchorAt(pos, 6)
	burst(a, {
		Texture = TEX.Fire, Color = ColorSequence.new(HOT, Color3.fromRGB(255, 90, 20)), LightEmission = 0.9,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.5), NumberSequenceKeypoint.new(1, radius * 1.1) }),
		Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.25, 0.6),
		Speed = NumberRange.new(radius * 1.2, radius * 3), SpreadAngle = Vector2.new(180, 180), Drag = 4,
	}, if big then 40 else 22)
	burst(a, {
		Texture = TEX.Smoke, Color = ColorSequence.new(Color3.fromRGB(70, 66, 62), Color3.fromRGB(130, 128, 124)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.6), NumberSequenceKeypoint.new(1, radius * 2) }),
		Transparency = NumberSequence.new(0.25, 1), Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(radius * 0.6, radius * 1.8), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Acceleration = Vector3.new(0, 6, 0), RotSpeed = NumberRange.new(-30, 30),
	}, if big then 30 else 16)
	burst(a, {
		Texture = TEX.Spark, Color = ColorSequence.new(HOT), LightEmission = 1, Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.4, 1.1), Speed = NumberRange.new(radius * 3, radius * 6),
		SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -Workspace.Gravity * 0.4, 0),
	}, if big then 60 else 30)
	flashLight(pos, HOT, radius * 4, 0.35)
	camShake(pos, if big then 2.2 else 1.4, radius * 14)
end

function FX.Impact(id: number?, pos: Vector3, normal: Vector3, kind: string, radius: number?)
	if id and live[id] then
		live[id].Part:Destroy()
		live[id] = nil
	end
	if kind == "Explode" then
		explosion(pos, radius or 14, false)
		oneShot(Config.Sounds.ShellImpact, pos)
	end
end

-- ─── machine guns ────────────────────────────────────────────────────────
local lastShotSound = {}
function FX.Shots(model: Model, shots)
	if not model or not model.Parent then
		return
	end
	local kind = model:GetAttribute("VehicleType")
	local snd = Config.Sounds[kind]
	FX.Muzzle(model, false)
	local muzzle = muzzleOf(model)
	local muzzle2 = muzzleOf(model, 2)
	if muzzle2 then
		-- twin guns: flash the second barrel too
		local a = anchorAt(muzzle2.WorldPosition, 0.5)
		a.WorldCFrame = muzzle2.WorldCFrame
		burst(a, { Texture = TEX.Spark, Color = ColorSequence.new(HOT), LightEmission = 1, Size = NumberSequence.new(1.4, 0),
			Lifetime = NumberRange.new(0.05, 0.07), Speed = NumberRange.new(18), SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Front }, 5)
	end
	local now = os.clock()
	if snd and snd.Fire and muzzle and now - (lastShotSound[model] or 0) > 0.05 then
		lastShotSound[model] = now
		local s = FX.Sound(snd.Fire, muzzle)
		if s then
			s.PlaybackSpeed = (snd.Fire.Speed or 1) * (0.95 + math.random() * 0.1)
			s:Play()
			Debris:AddItem(s, 2)
		end
	end
	for _, sh in shots do
		local pos, normal, hitKind, tracer = sh[1], sh[2], sh[3], sh[5]
		local from_m = if sh[6] and sh[6] > 1 and muzzle2 then muzzle2 else muzzle
		if tracer and from_m then
			local from = from_m.WorldPosition
			local len = (pos - from).Magnitude
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Material = Enum.Material.Neon
			p.Color = HOT
			p.Size = Vector3.new(0.18, 0.18, math.min(len, 14))
			p.CFrame = CFrame.lookAt(from, pos) * CFrame.new(0, 0, -p.Size.Z / 2)
			p.Parent = fxFolder()
			local dir = (pos - from).Unit
			task.spawn(function()
				local t, speed = 0, 1400
				while p.Parent and t * speed < len do
					local dt = RunService.RenderStepped:Wait()
					t += dt
					local head = from + dir * math.min(len, t * speed)
					p.CFrame = CFrame.lookAt(head - dir * p.Size.Z / 2, head + dir)
				end
				p:Destroy()
			end)
		end
		if hitKind ~= "None" then
			local a = anchorAt(pos + normal * 0.1, 1.5)
			a.WorldCFrame = CFrame.lookAt(a.WorldPosition, a.WorldPosition + normal)
			burst(a, {
				Texture = TEX.Spark, Color = ColorSequence.new(HOT), LightEmission = 1, Size = NumberSequence.new(0.35, 0),
				Lifetime = NumberRange.new(0.1, 0.3), Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(50, 50),
				EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -Workspace.Gravity * 0.3, 0),
			}, 6)
			burst(a, {
				Texture = TEX.Smoke, Color = ColorSequence.new(Color3.fromRGB(150, 146, 140)), Size = NumberSequence.new(0.8, 2.6),
				Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 6),
				SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Front,
			}, 2)
		end
	end
end

-- a hit on a vehicle hull: clang at the impact (crew feedback)
function FX.HullHit(pos: Vector3)
	local ids = Config.Sounds.MetalHit
	if ids and #ids > 0 then
		oneShot({ Id = ids[math.random(1, #ids)], Volume = 0.8 }, pos)
	end
end

-- ─── destruction ─────────────────────────────────────────────────────────
function FX.Destroyed(model: Model, pos: Vector3)
	explosion(pos, 22, true)
	oneShot(Config.Sounds.Destroyed, pos)
	local root = model and model.PrimaryPart
	if not root then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "WreckFX"
	a.Position = Vector3.new(0, root.Size.Y / 2, 0)
	a.Parent = root
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = TEX.Fire
	fire.Color = ColorSequence.new(HOT, Color3.fromRGB(255, 80, 20))
	fire.LightEmission = 0.8
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.6, 1.2)
	fire.Rate = 40
	fire.Speed = NumberRange.new(6, 12)
	fire.SpreadAngle = Vector2.new(25, 25)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Parent = a
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = TEX.Smoke
	smoke.Color = ColorSequence.new(Color3.fromRGB(35, 33, 32))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) })
	smoke.Transparency = NumberSequence.new(0.2, 1)
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Rate = 10
	smoke.Speed = NumberRange.new(8, 14)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = a
	local l = Instance.new("PointLight")
	l.Color = HOT
	l.Range = 40
	l.Brightness = 3
	l.Parent = a
end

return FX
