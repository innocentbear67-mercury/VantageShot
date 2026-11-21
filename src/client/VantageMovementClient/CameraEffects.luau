--[[
	VANTAGE — CameraEffects (client)
	Runs at RenderPriority.Camera + 1, after Roblox's first-person camera has positioned
	the camera for this frame, and layers SUBTLE feel effects on top:
		• FOV: base, small slide boost, small momentum boost
		• Roll tilt when strafing / sliding (roll only — never changes where you aim)
		• Landing dip (critically damped spring, scaled by impact)
		• Tiny head bob at running speed
	Crouch / slide camera height comes from the physical body lowering (MovementController).
	Nothing here rotates pitch or yaw, so mouse look stays 1:1 and responsive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
-- 2026-11-17: the head bob follows the gun's gait (same footfalls), landings pitch the view a touch,
-- jumps lift it. Pitch offsets are re-applied each frame on top of Roblox's camera (never accumulate).
local GaitFeed = require(ReplicatedStorage.Vantage.Movement:WaitForChild("GaitFeed"))
local LAND_PITCH = 3.2 -- degrees of look-down per stud of landing dip
local JUMP_LIFT = 1.1 -- spring velocity kick (studs/s) on take-off

-- [VANTAGE settings integration] player settings toggles (LocalPlayer attributes written by
-- the weapon client's Settings module; absent = enabled):
--   VantageCameraFX     strafe / slide tilt + speed / slide FOV boosts
--   VantageScreenShake  landing dip + head bob
local function settingOn(name: string): boolean
	return Players.LocalPlayer:GetAttribute(name) ~= false
end

local function smoothing(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local CameraEffects = {}
CameraEffects.__index = CameraEffects

function CameraEffects.new(movement)
	local self = setmetatable({}, CameraEffects)
	self.Movement = movement
	self.Fov = Config.BaseFOV
	self.Roll = 0
	self.DipOffset = 0
	self.DipVelocity = 0
	self.BobPhase = 0
	self.BobWeight = 0
	-- 2026-11-20 fix: the rotation written last frame. Roblox's camera builds each frame from the
	-- camera's current look, so a pitch left in place accumulated every frame of a landing dip and
	-- dragged the view to the floor. Undo() (bound at Camera - 1) takes it out before the camera runs.
	self.Applied = CFrame.identity
	self._landedConn = movement.Landed:Connect(function(impact: number)
		self:_onLanded(impact)
	end)
	if movement.Jumped then
		self._jumpedConn = movement.Jumped:Connect(function()
			if settingOn("VantageScreenShake") then
				self.DipVelocity += JUMP_LIFT
			end
		end)
	end
	return self
end

function CameraEffects:_onLanded(impact: number)
	if impact < 15 then
		return -- ignore tiny steps / micro drops
	end
	local strength = math.clamp((impact - 15) / (Config.HardLandingVelocity - 15), 0.15, 1)
	local depth = Config.LandingDipMax * strength
	-- critically damped spring: peak displacement = v0 / (omega * e)
	self.DipVelocity = -depth * Config.LandingDipRecover * math.exp(1)
end

function CameraEffects:Undo(camera: Camera)
	if self.Applied ~= CFrame.identity then
		camera.CFrame = camera.CFrame * self.Applied:Inverse()
		self.Applied = CFrame.identity
	end
end

function CameraEffects:Step(dt: number, camera: Camera)
	local m = self.Movement
	local vel = m.Velocity
	local speed = vel.Magnitude
	local sliding = m.Stance == "Slide"

	-- FOV
	local over = math.clamp((speed - Config.RunSpeed) / math.max(1, Config.SlideMaxSpeed - Config.RunSpeed), 0, 1)
	local cameraFx = settingOn("VantageCameraFX")
	local shake = settingOn("VantageScreenShake")
	local targetFov = Config.BaseFOV
	if cameraFx then
		targetFov += over * Config.SpeedFOVBonus + (if sliding then Config.SlideFOVBonus else 0)
		-- 2026-11-19: on the cable the view widens with real speed: +6 at 60 st/s up to +10 at top speed
		if m.IsGrappling and m:IsGrappling() and m.Root then
			local s3 = m.Root.AssemblyLinearVelocity.Magnitude
			targetFov += math.clamp((s3 - 30) / 75, 0, 1) * 10
		end
	end
	self.Fov += (targetFov - self.Fov) * smoothing(Config.FOVSmoothing, dt)
	camera.FieldOfView = self.Fov

	-- Roll tilt
	local camCF = camera.CFrame
	local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
	local side = 0
	if right.Magnitude > 1e-3 then
		side = math.clamp(vel:Dot(right.Unit) / Config.RunSpeed, -1, 1)
	end
	local targetRoll = -side * Config.StrafeTilt
	if sliding then
		targetRoll += Config.SlideTilt
	end
	if not cameraFx then
		targetRoll = 0
	end
	self.Roll += (targetRoll - self.Roll) * smoothing(Config.TiltSmoothing, dt)

	-- Landing dip spring (critically damped)
	local w = Config.LandingDipRecover
	local accel = -w * w * self.DipOffset - 2 * w * self.DipVelocity
	self.DipVelocity += accel * dt
	self.DipOffset += self.DipVelocity * dt
	if math.abs(self.DipOffset) < 1e-4 and math.abs(self.DipVelocity) < 1e-3 then
		self.DipOffset, self.DipVelocity = 0, 0
	end

	-- Head bob: the gun's gait when it is live (GaitFeed), else the old tiny bob
	local bob, bobX, bobRoll = 0, 0, 0
	local g = GaitFeed
	if Config.HeadBobEnabled and shake and g.At and os.clock() - g.At < 0.2 then
		local s1 = math.sin(g.Phase or 0)
		local w = (g.Weight or 0) * (g.Sprint or 1)
		bob = (math.abs(s1) - 0.6) * Config.HeadBobAmplitude * 1.7 * w
		bobX = s1 * Config.HeadBobAmplitude * 0.55 * w
		bobRoll = s1 * 0.28 * w
	elseif Config.HeadBobEnabled and shake then
		local moving = m.Grounded and not sliding and speed > 1
		local targetWeight = if moving then math.clamp(speed / Config.RunSpeed, 0, 1) else 0
		self.BobWeight += (targetWeight - self.BobWeight) * smoothing(10, dt)
		if self.BobWeight > 0.01 then
			self.BobPhase = (self.BobPhase + dt * Config.HeadBobFrequency * math.pi * 2 * math.max(self.BobWeight, 0.3)) % (math.pi * 2)
			bob = math.sin(self.BobPhase * 2) * Config.HeadBobAmplitude * self.BobWeight
		end
	end

	local dip = if shake then self.DipOffset else 0
	local offsetY = dip + bob
	local pitch = math.min(dip, 0) * LAND_PITCH
	self.Applied = CFrame.identity
	if offsetY ~= 0 or bobX ~= 0 or math.abs(self.Roll + bobRoll) > 1e-3 or pitch ~= 0 then
		local rot = CFrame.Angles(math.rad(pitch), 0, math.rad(self.Roll + bobRoll))
		camera.CFrame = CFrame.new(0, offsetY, 0) * camCF * CFrame.new(bobX, 0, 0) * rot
		self.Applied = rot
	end
end

function CameraEffects:Destroy(camera: Camera?)
	self._landedConn:Disconnect()
	if self._jumpedConn then
		self._jumpedConn:Disconnect()
	end
	if camera then
		self:Undo(camera)
		camera.FieldOfView = Config.BaseFOV
	end
end

return CameraEffects
