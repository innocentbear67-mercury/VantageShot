--[[
	VANTAGE — Footsteps (client, local player only) · 2026-11-17
	One footstep per footfall of the SAME gait the gun and the camera bob use (GaitFeed, written by
	the weapon Viewmodel), so what you hear lands exactly when the view dips. When no viewmodel is
	driving the gait (knife, dead, menus) a local gait with the same timing is used.
	  walk / run / sprint   louder and a touch brighter as speed rises
	  surface               Humanoid.FloorMaterial picks pitch / volume (metal rings, grass is soft)
	  jump / land           push-off step on take-off; landing = both feet + a body thud scaled by impact
	Roblox's looping "Running" sound is muted for the local character only (other players keep
	their 3D footsteps). Sounds play 2D through SoundService.VantageEffects (effects volume applies).
	Samples: the built-in action_footsteps_plastic loop, sliced into its four single steps
	(measured with an AudioAnalyzer: onsets 0.05 / 0.65 / 1.25 / 1.86 s); PSE Body Impact 2 for the thud.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local MoveConfig = require(Vantage:WaitForChild("Movement"):WaitForChild("MovementConfig"))
local GaitFeed = require(Vantage.Movement:WaitForChild("GaitFeed"))

local player = Players.LocalPlayer

local STEP_ID = "rbxasset://sounds/action_footsteps_plastic.mp3"
local STEPS = {
	NumberRange.new(0.03, 0.3),
	NumberRange.new(0.63, 0.9),
	NumberRange.new(1.23, 1.5),
	NumberRange.new(1.84, 2.1),
}
local THUD_ID = "rbxassetid://9113524237" -- PSE Body Impact 2

-- surface -> { speed, volume }
local SURFACE = {
	Metal = { 1.18, 1.0 },
	DiamondPlate = { 1.2, 1.0 },
	CorrodedMetal = { 1.12, 1.0 },
	Concrete = { 0.92, 1.0 },
	Slate = { 0.95, 1.0 },
	Brick = { 0.93, 1.0 },
	Cobblestone = { 0.9, 1.0 },
	Pavement = { 0.92, 1.0 },
	Asphalt = { 0.9, 0.95 },
	Wood = { 0.85, 1.05 },
	WoodPlanks = { 0.82, 1.05 },
	Grass = { 0.78, 0.6 },
	LeafyGrass = { 0.78, 0.6 },
	Sand = { 0.72, 0.55 },
	Ground = { 0.8, 0.65 },
	Mud = { 0.7, 0.6 },
	Snow = { 0.75, 0.55 },
	Glass = { 1.25, 0.9 },
	Plastic = { 1.0, 0.9 },
	SmoothPlastic = { 1.0, 0.9 },
	Neon = { 1.05, 0.9 },
}
local DEFAULT_SURFACE = { 0.95, 0.9 }

local VOL_WALK, VOL_RUN, VOL_SPRINT = 0.5, 0.7, 0.85 -- 2026-11-17: ~24 dB under own gunfire (Hypershot ratio)

local rng = Random.new()
local group: SoundGroup? = nil
local function bus(): Instance
	if group and group.Parent then
		return group
	end
	group = SoundService:FindFirstChild("VantageEffects") :: SoundGroup?
	return group or SoundService
end

local pools = {}
local function voice(id: string, n: number): Sound
	local p = pools[id]
	if not p then
		p = { i = 0 }
		for k = 1, n do
			local s = Instance.new("Sound")
			s.Name = "VantageFootstep"
			s.SoundId = id
			s.PlaybackRegionsEnabled = true
			local b = bus()
			if b:IsA("SoundGroup") then
				s.SoundGroup = b
			end
			s.Parent = b
			p[k] = s
		end
		pools[id] = p
	end
	p.i = p.i % #p + 1
	return p[p.i]
end

local lastStep = 0
local function step(speed: number, humanoid: Humanoid, gain: number?)
	local now = os.clock()
	if now - lastStep < 0.09 then
		return
	end
	lastStep = now
	local surf = SURFACE[humanoid.FloorMaterial.Name] or DEFAULT_SURFACE
	local run = MoveConfig.RunSpeed
	local vol = if speed > run * 0.95 then VOL_SPRINT elseif speed > run * 0.6 then VOL_RUN else VOL_WALK
	local s = voice(STEP_ID, 6)
	if s.IsPlaying then
		s:Stop()
	end
	s.PlaybackRegion = STEPS[rng:NextInteger(1, #STEPS)]
	s.PlaybackSpeed = surf[1] * rng:NextNumber(0.94, 1.06) * (if speed > run * 0.95 then 1.05 else 1)
	s.Volume = vol * surf[2] * (gain or 1)
	s.TimePosition = s.PlaybackRegion.Min
	s:Play()
end

local function thud(strength: number)
	local s = voice(THUD_ID, 2)
	if s.IsPlaying then
		s:Stop()
	end
	s.PlaybackRegionsEnabled = false
	s.PlaybackSpeed = 0.62 + rng:NextNumber(-0.03, 0.03)
	s.Volume = 0.05 + 0.13 * strength
	s.TimePosition = 0
	s:Play()
end

-- ── per character ────────────────────────────────────────────────────────────────────────
local conns = {}
local function clear()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
end

local function muteDefault(character: Model)
	local function mute(d: Instance)
		if d:IsA("Sound") and d.Name == "Running" then
			d.Volume = 0
			table.insert(conns, d:GetPropertyChangedSignal("Volume"):Connect(function()
				if d.Volume ~= 0 then
					d.Volume = 0
				end
			end))
		end
	end
	for _, d in character:GetDescendants() do
		mute(d)
	end
	table.insert(conns, character.DescendantAdded:Connect(mute))
end

local function onCharacter(character: Model)
	clear()
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	muteDefault(character)
	local seenStep = GaitFeed.StepCount or 0
	local phase, weight = 0, 0
	local lastHalf = 0
	local fallSpeed = 0
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if humanoid.Health <= 0 then
			return
		end
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if not grounded then
			fallSpeed = math.max(fallSpeed, -v.Y)
		end
		local fresh = GaitFeed.At ~= nil and os.clock() - GaitFeed.At < 0.15
		if fresh then
			-- the gun's gait drives the steps
			local c = GaitFeed.StepCount or 0
			if c ~= seenStep then
				seenStep = c
				step(GaitFeed.StepSpeed or flat, humanoid)
			end
			phase = GaitFeed.Phase or phase
			lastHalf = math.floor(phase / math.pi)
		else
			-- own gait (same timing as the Viewmodel's: BobFrequency 1.9 cycles / s at RunSpeed)
			local frac = math.clamp(flat / MoveConfig.RunSpeed, 0, 1.4)
			local target = if grounded and flat > 1 and character:GetAttribute("VantageStance") ~= "Slide" then math.min(frac, 1) else 0
			weight += (target - weight) * (1 - math.exp(-10 * dt))
			phase = (phase + dt * 1.9 * math.pi * 2 * math.max(frac, 0.35)) % (math.pi * 2)
			local half = math.floor(phase / math.pi)
			if half ~= lastHalf and weight > 0.35 and grounded then
				step(flat, humanoid)
			end
			lastHalf = half
		end
	end))
	table.insert(conns, humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			step(MoveConfig.RunSpeed, humanoid, 0.9) -- push-off
			fallSpeed = 0
		elseif new == Enum.HumanoidStateType.Landed then
			local s = math.clamp((fallSpeed - 12) / (MoveConfig.HardLandingVelocity - 12), 0, 1)
			if fallSpeed > 12 then
				lastStep = 0
				step(MoveConfig.RunSpeed * 1.2, humanoid, 1 + 0.5 * s)
				task.delay(0.045, function()
					lastStep = 0
					step(MoveConfig.RunSpeed * 1.2, humanoid, 0.8 + 0.4 * s)
				end)
				if s > 0.15 then
					thud(s)
				end
			end
			fallSpeed = 0
		end
	end))
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
