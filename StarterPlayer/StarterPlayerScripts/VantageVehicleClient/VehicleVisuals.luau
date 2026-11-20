--[[
	VANTAGE — VehicleVisuals (client, every vehicle)
	Animates the moving parts of every vehicle from replicated state: turret yaw / pitch
	(server attributes AimYaw / AimPitch, or the local gunner's prediction), wheel spin, steering,
	suspension travel (each client casts its own short rays), engine / track audio by speed and
	throttle, dust behind moving vehicles, smoke and fire as the hull takes damage, and hides
	crew sitting in closed seats.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VF = ReplicatedStorage.Vantage.Vehicles
local Config = require(VF.VehicleConfig)
local VMath = require(VF.VehicleMath)

local V = {}
V.Local = nil -- set by the controller: { Model, Yaw, Pitch, Controls, Sim } for the local player's vehicle

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local FULL_DETAIL = 450 -- studs: beyond this only the turret and audio are animated

local tracked = {} -- [Model] = state
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local SV = Config.ShieldVisual

local shieldFolder: Folder
local function shieldHolder(): Folder
	if not shieldFolder or not shieldFolder.Parent then
		shieldFolder = Instance.new("Folder")
		shieldFolder.Name = "VehicleShieldFX"
		shieldFolder.Parent = Workspace
	end
	return shieldFolder
end

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0.6
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function shieldSound(spec, pos: Vector3)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local snd = Instance.new("Sound")
	snd.SoundId = spec.Id
	snd.Volume = spec.Volume or 0.5
	snd.PlaybackSpeed = (spec.Speed or 1) * (0.95 + math.random() * 0.1)
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 25
	snd.RollOffMaxDistance = 500
	snd.Parent = a
	snd.TimePosition = spec.StartAt or 0
	snd:Play()
	Debris:AddItem(a, 4)
end

-- the shield: dedicated shell meshes built into the vehicle (parts named "*_Shield": an offset skin
-- of each mesh with even hex UVs, welded to it so it follows turret, wheels and rotors). Here only
-- their look is driven, per client: transparency / colour from the shield state.
local function buildShell(model: Model, root: BasePart)
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	local shell = { Parts = {}, Flash = 0, Last = nil, LastHitSound = 0 }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name:match("_Shield$") then
			d.Material = Enum.Material.ForceField
			d.TextureID = SV.Image
			d.Color = SV.Color
			d.LocalTransparencyModifier = 0
			d.Transparency = 1
			table.insert(shell.Parts, { Part = d })
			local cfL = root.CFrame:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cfL:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						mn = mn:Min(p)
						mx = mx:Max(p)
					end
				end
			end
		end
	end
	if #shell.Parts == 0 then
		return nil -- shells not installed yet
	end
	shell.Centre = (mn + mx) / 2
	return shell
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	-- StreamingEnabled: a far vehicle arrives (or comes back) later — wait as long as it takes
	local root = model:WaitForChild("Root") :: BasePart?
	if not root or not model.Parent or tracked[model] then
		return
	end
	local kind = model:GetAttribute("VehicleType")
	local cfg = Config.Vehicles[kind]
	if not cfg then
		return
	end
	local st = {
		Model = model, Root = root, Kind = kind, Cfg = cfg,
		Yaw = 0, Pitch = 0, Steer = 0,
		YawJoint = root:FindFirstChild("AimYaw") :: Motor6D?,
		PitchJoint = nil :: Motor6D?,
		Wheels = {},
		Params = RaycastParams.new(),
		Hidden = {},
	}
	if st.YawJoint and st.YawJoint.Part1 then
		st.PitchJoint = st.YawJoint.Part1:FindFirstChild("AimPitch") :: Motor6D?
	end
	st.Params.FilterType = Enum.RaycastFilterType.Exclude
	for _, a in root:GetChildren() do
		if a:IsA("Attachment") and a:GetAttribute("RideDistance") then
			local joint = root:FindFirstChild("J_" .. a.Name) :: Motor6D?
			table.insert(st.Wheels, {
				Att = a, Joint = joint, Ride = a:GetAttribute("RideDistance"), Radius = a:GetAttribute("Radius"),
				Steer = a:GetAttribute("Steer") == true, Spin = 0, Offset = 0,
			})
		end
	end
	-- audio
	local snd = Config.Sounds[kind] or {}
	local function loop(spec)
		if not spec then
			return nil
		end
		local s = Instance.new("Sound")
		s.SoundId = spec.Id
		s.Looped = true
		s.Volume = 0
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 25
		s.RollOffMaxDistance = 600
		s.Parent = root
		s:Play()
		return s
	end
	st.Rotors = {}
	for _, j in root:GetChildren() do
		if j:IsA("Motor6D") and j:GetAttribute("Rotor") then
			table.insert(st.Rotors, { Joint = j, Spin = math.random() * 6 })
		end
	end
	st.RotorSpeed = 0
	st.Engine = loop(snd.Engine)
	st.Tracks = loop(snd.Tracks)
	-- dust at the back of the hull, smoke / fire for damage states
	local back = Instance.new("Attachment")
	back.Name = "DustFX"
	back.Position = Vector3.new(0, -root.Size.Y / 2, root.Size.Z / 2) -- local +Z = rear
	back.Parent = root
	st.Dust = emitter(back, {
		Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(150, 146, 136)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new(0.55, 1), Lifetime = NumberRange.new(0.8, 1.6), Rate = 0,
		Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(40, 40), Drag = 2,
		Acceleration = Vector3.new(0, 2, 0), EmissionDirection = Enum.NormalId.Top,
	})
	local top = Instance.new("Attachment")
	top.Name = "DamageFX"
	top.Position = Vector3.new(0, root.Size.Y / 2, root.Size.Z * 0.2)
	top.Parent = root
	st.Smoke = emitter(top, {
		Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(40, 38, 37)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new(0.3, 1), Lifetime = NumberRange.new(2, 3.5), Rate = 0,
		Speed = NumberRange.new(5, 9), SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Top,
	})
	st.Fire = emitter(top, {
		Texture = TEX_FIRE, Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 80, 20)),
		LightEmission = 0.8, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.5) }),
		Lifetime = NumberRange.new(0.4, 0.9), Rate = 0, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(20, 20),
		EmissionDirection = Enum.NormalId.Top,
	})
	st.Shell = buildShell(model, root)
	tracked[model] = st
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			V.Untrack(model)
		end
	end)
	-- streamed out (the Root goes away while the model stays): drop it and pick it up again
	root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(Workspace) and tracked[model] == st then
			V.Untrack(model)
			if model:IsDescendantOf(Workspace) then
				task.spawn(track, model)
			end
		end
	end)
end

function V.Untrack(model: Model)
	local st = tracked[model]
	if not st then
		return
	end
	for part in st.Hidden do
		if part.Parent then
			(part :: any).LocalTransparencyModifier = 0
		end
	end
	if st.Shell then
		for _, p in st.Shell.Parts do
			if p.Part.Parent then
				p.Part.Transparency = 1
			end
		end
	end
	tracked[model] = nil
end

function V.Get(model: Model)
	return tracked[model]
end

local function hideCrew(st)
	local seen = {}
	local seats = st.Model:FindFirstChild("Seats")
	if seats then
		for _, seat in seats:GetChildren() do
			if seat:IsA("Seat") and seat:GetAttribute("Hidden") and seat.Occupant then
				local ch = seat.Occupant.Parent
				if ch then
					for _, d in ch:GetDescendants() do
						if d:IsA("BasePart") or d:IsA("Decal") then
							seen[d] = true
							st.Hidden[d] = true;
							(d :: any).LocalTransparencyModifier = 1
						end
					end
				end
			end
		end
	end
	for d in st.Hidden do
		if not seen[d] then
			st.Hidden[d] = nil
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
	end
end

local function update(st, dt: number, camPos: Vector3)
	local model, root = st.Model, st.Root
	if not root.Parent then
		return
	end
	local destroyed = model:GetAttribute("Destroyed") == true
	local dist = (root.Position - camPos).Magnitude

	-- turret: the local gunner's prediction, else smoothed replicated angles
	local L = V.Local
	if L and L.Model == model and L.Controls then
		st.Yaw, st.Pitch = L.Yaw, L.Pitch
	elseif not destroyed then
		local ty, tp = model:GetAttribute("AimYaw") or 0, model:GetAttribute("AimPitch") or 0
		local k = math.min(1, dt * 14)
		st.Yaw = VMath.WrapAngle(st.Yaw + VMath.WrapAngle(ty - st.Yaw) * k)
		st.Pitch += (tp - st.Pitch) * k
	end
	if st.YawJoint then
		st.YawJoint.Transform = CFrame.Angles(0, st.Yaw, 0)
	end
	if st.PitchJoint then
		st.PitchJoint.Transform = CFrame.Angles(st.Pitch, 0, 0)
	end
	hideCrew(st)

	local v = root.AssemblyLinearVelocity
	local cf = root.CFrame
	local vFwd = v:Dot(cf.LookVector)
	local speed = math.abs(vFwd)
	local D = st.Cfg.Drive

	-- audio: engine pitch rides speed + throttle
	local throttle = math.abs(model:GetAttribute("Throttle") or 0)
	local crewed = (model:GetAttribute("Crew") or 0) > 0
	local snd = Config.Sounds[st.Kind] or {}
	if st.Engine and snd.Engine then
		local frac = math.clamp(speed / D.MaxForward, 0, 1)
		local want = if destroyed then 0 elseif crewed then snd.Engine.Volume * (0.55 + 0.45 * math.max(frac, throttle)) else snd.Engine.Volume * 0.18
		st.Engine.Volume += (want - st.Engine.Volume) * math.min(1, dt * 4)
		local pitch = snd.Engine.Idle + (snd.Engine.Max - snd.Engine.Idle) * (frac * 0.8 + throttle * 0.2)
		st.Engine.PlaybackSpeed += (pitch - st.Engine.PlaybackSpeed) * math.min(1, dt * 3)
	end
	if st.Tracks and snd.Tracks then
		local want = if destroyed then 0 else snd.Tracks.Volume * math.clamp(speed / 12, 0, 1)
		st.Tracks.Volume += (want - st.Tracks.Volume) * math.min(1, dt * 5)
		st.Tracks.PlaybackSpeed = 0.8 + math.clamp(speed / D.MaxForward, 0, 1) * 0.5
	end

	-- rotors: idle spin when crewed, faster with throttle / speed; wind down when empty or wrecked
	if #st.Rotors > 0 then
		local want = if destroyed then 0 elseif crewed then 38 + 24 * math.max(throttle, math.clamp(v.Magnitude / D.MaxForward, 0, 1)) else 0
		st.RotorSpeed += (want - st.RotorSpeed) * math.min(1, dt * (if want > st.RotorSpeed then 3 else 0.8))
		for i, r in st.Rotors do
			r.Spin = (r.Spin + st.RotorSpeed * dt * (if i % 2 == 0 then -1 else 1)) % (math.pi * 2)
			r.Joint.Transform = CFrame.Angles(0, r.Spin, 0)
		end
	end
	-- damage states
	local hp, maxHp = model:GetAttribute("Health") or 1, model:GetAttribute("MaxHealth") or 1
	local frac = hp / math.max(1, maxHp)
	st.Smoke.Rate = if destroyed then 0 elseif frac < Config.DamageStates.Smoke then 6 + (1 - frac) * 12 else 0
	st.Fire.Rate = if destroyed then 0 elseif frac < Config.DamageStates.Fire then 30 else 0

	-- energy shield shell (the shell parts can land after the Root on a client — keep looking until they do)
	if not st.Shell then
		local now = os.clock()
		if now >= (st.ShellRetry or 0) then
			st.ShellRetry = now + 0.5
			st.Shell = buildShell(model, root)
		end
	end
	local sh = st.Shell
	if sh then
		local shield, maxShield = model:GetAttribute("Shield") or 0, model:GetAttribute("MaxShield") or 1
		local sfrac = shield / math.max(1, maxShield)
		if sh.Last and sh.Last <= 0 and shield > 0 and not destroyed then
			sh.Flash = 0.7 -- coming back online: a shimmer + the recharge cue
			shieldSound(SV.Sounds.Recharge, root.Position)
		end
		sh.Last = shield
		sh.Flash = math.max(0, sh.Flash - dt * 2.8)
		local visible = not destroyed and dist < SV.MaxDistance and (shield > 0 or sh.Flash > 0.02)
		if visible then
			local col = SV.Color:Lerp(SV.White, math.min(1, sh.Flash) * 0.7)
			local film = if shield <= 0 then 1 else SV.FilmIdle + (SV.FilmHit - SV.FilmIdle) * math.min(1, sh.Flash)
			if shield > 0 and sfrac < 0.3 and math.random() < 0.25 then
				film = math.min(film, SV.FilmIdle * 0.4) -- failing: flicker
			end
			for _, p in sh.Parts do
				p.Part.Transparency = film
				p.Part.Color = col
			end
			sh.Shown = true
		elseif sh.Shown then
			sh.Shown = false
			for _, p in sh.Parts do
				p.Part.Transparency = 1
			end
		end
	end

	if dist > FULL_DETAIL or destroyed then
		st.Dust.Rate = 0
		return
	end

	-- wheels: suspension travel from local rays, spin from ground speed, steering from input
	local filter = { model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	st.Params.FilterDescendantsInstances = filter
	local steerIn = model:GetAttribute("Steer") or 0
	if L and L.Model == model and L.Sim then
		st.Steer = L.Sim.SteerAngle
	elseif D.Kind == "Wheels" then
		local maxSteer = D.MaxSteer + (D.MaxSteerAtSpeed - D.MaxSteer) * math.clamp(speed / D.MaxForward, 0, 1)
		local target = -steerIn * maxSteer
		st.Steer += math.clamp(target - st.Steer, -D.SteerSpeed * dt, D.SteerSpeed * dt)
	end
	local contacts = 0
	for _, w in st.Wheels do
		local origin = cf:PointToWorldSpace(w.Att.Position)
		local reach = w.Ride + D.Sag + 1.5
		local hit = Workspace:Raycast(origin, -cf.UpVector * reach, st.Params)
		local target
		if hit then
			local d = (hit.Position - origin):Dot(-cf.UpVector)
			target = math.clamp(w.Ride - d, -1.2, 1.4)
			contacts += 1
		else
			target = -1.2
		end
		w.Offset += (target - w.Offset) * math.min(1, dt * 18)
		if w.Joint then
			w.Spin = (w.Spin + vFwd * dt / math.max(0.5, w.Radius)) % (math.pi * 2)
			local steer = if w.Steer then math.rad(st.Steer) else 0
			w.Joint.Transform = CFrame.new(0, w.Offset, 0) * CFrame.Angles(0, steer, 0) * CFrame.Angles(-w.Spin, 0, 0)
		end
	end
	st.Dust.Rate = if contacts > 0 and speed > 8 then (speed / D.MaxForward) * 40 * (st.Cfg.Visual.Dust or 1) else 0
end

-- the server's shield took a hit: flash the shell, ripple a hex patch at the impact, cue the sound
function V.ShieldHit(model: Model, pos: Vector3, absorbed: number, broke: boolean)
	local st = tracked[model]
	if not st or not st.Shell then
		return
	end
	local sh = st.Shell
	sh.Flash = math.max(sh.Flash, math.clamp(0.45 + absorbed / 200, 0.45, 1))
	local centre = st.Root.CFrame:PointToWorldSpace(sh.Centre)
	local dir = pos - centre
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.yAxis
	-- ripple
	local r = Instance.new("Part")
	r.Name = "ShieldRipple"
	r.Anchored = true
	r.CanCollide, r.CanQuery, r.CanTouch, r.CastShadow = false, false, false, false
	r.Transparency = 1
	r.Size = Vector3.new(3, 3, 0.05)
	r.CFrame = CFrame.lookAt(pos, pos + dir)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local t = Instance.new("Texture")
		t.Texture = SV.Image
		t.Face = face
		t.StudsPerTileU = SV.Tile * 0.6
		t.StudsPerTileV = SV.Tile * 0.52
		t.Color3 = SV.White
		t.Transparency = 0.05
		t.Parent = r
		TweenService:Create(t, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
	end
	r.Parent = shieldHolder()
	local grow = if broke then 26 else math.clamp(8 + absorbed / 25, 8, 20)
	TweenService:Create(r, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(grow, grow, 0.05) }):Play()
	Debris:AddItem(r, 0.45)
	local now = os.clock()
	if broke then
		sh.Flash = 1
		shieldSound(SV.Sounds.Break, pos)
		-- shatter: blue shards off the shell
		local a = Instance.new("Attachment")
		a.WorldPosition = centre
		a.Parent = Workspace.Terrain
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(SV.White, SV.Color)
		e.LightEmission = 1
		e.Size = NumberSequence.new(1.2, 0)
		e.Lifetime = NumberRange.new(0.4, 0.9)
		e.Speed = NumberRange.new(30, 60)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 3
		e.Enabled = false
		e.Parent = a
		e:Emit(60)
		Debris:AddItem(a, 1.5)
	elseif now - sh.LastHitSound > 0.07 then
		sh.LastHitSound = now
		shieldSound(SV.Sounds.Hit, pos)
	end
end

function V.Step(dt: number)
	local cam = Workspace.CurrentCamera
	local camPos = cam.CFrame.Position
	for model, st in tracked do
		if model.Parent then
			update(st, dt, camPos)
		end
	end
end

function V.Start()
	for _, m in CollectionService:GetTagged(Config.Tag) do
		task.spawn(track, m)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(function(m)
		task.spawn(track, m)
	end)
	CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(m)
		V.Untrack(m)
	end)
end

return V
