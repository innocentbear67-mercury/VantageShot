--[[
	VANTAGE — GrenadeClient (VX-G1 frag), built 2026-11-11
	Client side of the grenade. The server (GrenadeServer) owns the cooldown, the flight and the
	damage; this only asks, and draws.
		- WeaponInput.ThrowPressedAt (Fire + Alt together) -> ("Throw", camera look) to the server
		- same gates as the guns: dead, visor blackout, hanging under the dropship, in a vehicle,
		  a menu blocking input; plus a local copy of the cooldown so a refused throw is rare
		- visor tile: sets VantageAbilityUsed = "Grenade@t" (same hook the grapple uses)
		- every grenade in flight gets a lime glow that blinks faster as the fuse runs down
		- the blast: flash, lime shockwave, sparks, smoke, light, sound, camera shake when close
	Started from the VantageWeaponClient bootstrap: GrenadeClient.Start({ Input, Effects }).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("Grenade"):WaitForChild("GrenadeConfig"))
local Feed = require(Vantage.Grenade:WaitForChild("GrenadeFeed")) -- drives the first-person left-hand throw (Viewmodel)
local Remote = Vantage:WaitForChild("Remotes"):WaitForChild("Grenade") :: RemoteEvent

local player = Players.LocalPlayer
local GrenadeClient = {}

local soundGroup: SoundGroup? = nil
local readyAt = 0
local shakeUntil, shakeStrength = 0, 0
-- HUD v4: the frag tile reads the cooldown from the shared feed
game:GetService("RunService").Heartbeat:Connect(function()
	Feed.ReadyAt = readyAt
end)

local function sound(cfg, parent: Instance)
	local s = Instance.new("Sound")
	s.SoundId = cfg.Id
	s.Volume = cfg.Volume or 1
	s.PlaybackSpeed = cfg.Speed or 1
	s.RollOffMaxDistance = 600
	s.RollOffMinDistance = 12
	s.SoundGroup = soundGroup
	s.Parent = parent
	s:Play()
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

local function fxPart(name: string, size: Vector3, pos: Vector3, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = CFrame.new(pos)
	return p
end

local function blast(pos: Vector3)
	local holder = Instance.new("Folder")
	holder.Name = "VantageGrenadeBlast"
	holder.Parent = Workspace

	-- the engine's fireball (visual only: no pressure, nothing breaks)
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = 14 -- visual only (x2 with the damage radius)
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.ExplosionType = Enum.ExplosionType.NoCraters
	ex.Parent = holder

	-- white-lime core flash
	local core = fxPart("Core", Vector3.one * 0.6, pos, Config.Colors.Core, 0, Enum.PartType.Ball)
	core.Parent = holder
	TweenService:Create(core, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 7, Transparency = 1 }):Play()

	-- lime shockwave out to the damage radius
	local wave = fxPart("Wave", Vector3.one * 1, pos, Config.Colors.Lime, 0.35, Enum.PartType.Ball)
	wave.Material = Enum.Material.ForceField
	wave.Parent = holder
	TweenService:Create(wave, TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * Config.Radius * 2, Transparency = 1 }):Play()

	-- flat ring along the ground
	local ring = fxPart("Ring", Vector3.new(0.2, 2, 2), pos, Config.Colors.Lime, 0.2, Enum.PartType.Cylinder)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = holder
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, Config.Radius * 2.2, Config.Radius * 2.2), Transparency = 1 }):Play()

	-- light
	local lp = fxPart("Light", Vector3.one * 0.1, pos, Config.Colors.Lime, 1)
	lp.Parent = holder
	local light = Instance.new("PointLight")
	light.Color = Config.Colors.Core
	light.Brightness = 8
	light.Range = 32
	light.Shadows = false
	light.Parent = lp
	TweenService:Create(light, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 0 }):Play()

	-- sparks and smoke
	local att = Instance.new("Attachment")
	att.Parent = lp
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Config.Colors.Core, Config.Colors.Lime)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Speed = NumberRange.new(40, 85)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Rate = 0
	sparks.Parent = att
	sparks:Emit(42)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 74, 66), Color3.fromRGB(40, 42, 40))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 9) })
	smoke.Lifetime = NumberRange.new(1.4, 2.4)
	smoke.Speed = NumberRange.new(4, 12)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Drag = 2.5
	smoke.Acceleration = Vector3.new(0, 4, 0)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Rate = 0
	smoke.Parent = att
	smoke:Emit(14)

	sound(Config.Sounds.Explode, lp)

	-- camera shake by distance
	local cam = Workspace.CurrentCamera
	if cam then
		local d = (cam.CFrame.Position - pos).Magnitude
		if d < Config.ShakeRadius then
			local s = (1 - d / Config.ShakeRadius) ^ 1.5
			shakeStrength = math.max(shakeStrength, s)
			shakeUntil = os.clock() + 0.45
		end
	end

	task.delay(3, function()
		holder:Destroy()
	end)
end

-- a grenade in flight: lime glow, blinking faster as the fuse runs out
local function dress(model: Model)
	local root = model.PrimaryPart or model:WaitForChild("Root", 2)
	if not root or not root:IsA("BasePart") then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = Config.Colors.Lime
	light.Range = 7
	light.Brightness = 2
	light.Shadows = false
	light.Parent = root
	local glow = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and (p.Name == "Core" or p.Name == "Lights") then
			table.insert(glow, p)
		end
	end
	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			conn:Disconnect()
			return
		end
		local t = math.clamp((os.clock() - born) / Config.Fuse, 0, 1)
		local hz = 2 + 14 * t * t
		local on = math.sin((os.clock() - born) * hz * math.pi * 2) > -0.2
		light.Brightness = if on then 2.5 + 3 * t else 0.4
		for _, p in glow do
			p.Transparency = if on then 0 else 0.55
		end
	end)
end

local function canThrow(input): boolean
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not ch or not hum or hum.Health <= 0 then
		return false
	end
	if input.Blocked then
		return false
	end
	if player:GetAttribute("VisorBlackout") or player:GetAttribute("VantageHangingLocal") or player:GetAttribute("VantageVehicleLocal") then
		return false
	end
	if ch:GetAttribute("InVehicle") then
		return false
	end
	local match = Vantage:FindFirstChild("Match")
	if match and match:GetAttribute("Combat") == false then
		return false
	end
	return os.clock() >= readyAt
end

function GrenadeClient.Start(ctx)
	local input = ctx.Input
	local effects = ctx.Effects
	soundGroup = effects and effects.EffectsGroup or nil

	local handled = input.ThrowPressedAt or -math.huge
	RunService.Heartbeat:Connect(function()
		-- Studio tuning hook: LocalPlayer attribute GrenadeHoldAt = seconds freezes the throw pose there
		if RunService:IsStudio() then
			local h = player:GetAttribute("GrenadeHoldAt")
			if type(h) == "number" then
				Feed.HoldAt = h
				Feed.Start = Feed.Start or os.clock()
			elseif Feed.HoldAt then
				Feed.HoldAt, Feed.Start = nil, nil
			end
			-- live pose tuning: attributes GrenadeTune_P1..P4 / R1..R4 (Vector3), GrenadeTune_Held (CFrame)
			local tune = nil
			for k, v in player:GetAttributes() do
				local key = string.match(k, "^GrenadeTune_(.+)$")
				if key then
					tune = tune or {}
					tune[key] = v
				end
			end
			Feed.Tune = tune
		end
		local at = input.ThrowPressedAt or -math.huge
		if at <= handled then
			return
		end
		handled = at
		if not canThrow(input) then
			return
		end
		if Feed.Start then
			return -- already mid-throw
		end
		local now = os.clock()
		readyAt = now + Config.Cooldown
		player:SetAttribute("VantageAbilityUsed", "Grenade@" .. string.format("%.3f", now)) -- visor tile + cooldown
		-- the left hand takes the grenade and winds up; it leaves the hand at Feed.Release
		Feed.Start = now
		local character = player.Character
		task.delay(Feed.Release, function()
			local cam = Workspace.CurrentCamera
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if not cam or player.Character ~= character or not hum or hum.Health <= 0 then
				readyAt = 0 -- died mid-wind-up: nothing was thrown
				return
			end
			Remote:FireServer("Throw", cam.CFrame.LookVector.Unit)
		end)
	end)

	Remote.OnClientEvent:Connect(function(kind: string, a, b)
		if kind == "Explode" and typeof(a) == "Vector3" then
			blast(a)
		elseif kind == "Thrown" and typeof(a) == "Instance" and a:IsA("Model") then
			task.spawn(dress, a)
			local r = a.PrimaryPart
			if r then
				sound(Config.Sounds.Throw, r)
			end
		elseif kind == "Reject" and type(a) == "number" then
			readyAt = os.clock() + math.max(a, 0)
		end
	end)

	player.CharacterAdded:Connect(function()
		if Config.RefillOnRespawn then
			readyAt = 0
		end
	end)

	-- camera shake after the camera scripts have placed the camera; undone before the camera runs
	-- next frame (2026-11-20: it used to stay in the aim and drift it)
	local shakeApplied = CFrame.identity
	RunService:BindToRenderStep("VantageGrenadeShakeUndo", Enum.RenderPriority.Camera.Value - 3, function()
		if shakeApplied ~= CFrame.identity then
			local cam = Workspace.CurrentCamera
			if cam then
				cam.CFrame = cam.CFrame * shakeApplied:Inverse()
			end
			shakeApplied = CFrame.identity
		end
	end)
	RunService:BindToRenderStep("VantageGrenadeShake", Enum.RenderPriority.Camera.Value + 3, function()
		local left = shakeUntil - os.clock()
		if left <= 0 then
			shakeStrength = 0
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local k = shakeStrength * (left / 0.45)
		local t = os.clock() * 55
		shakeApplied = CFrame.Angles(math.noise(t, 1) * 0.05 * k, math.noise(t, 2) * 0.05 * k, math.noise(t, 3) * 0.04 * k)
		cam.CFrame = cam.CFrame * shakeApplied
	end)
end

return GrenadeClient
