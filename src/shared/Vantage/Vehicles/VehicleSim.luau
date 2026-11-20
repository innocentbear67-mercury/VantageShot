--[[
	VANTAGE — VehicleSim (shared)
	Raycast-suspension vehicle physics. Exactly one machine steps a vehicle: the driver's client
	(it is the network owner while someone drives) or the server (empty vehicle). Both run this
	same code, so a vehicle behaves identically whoever simulates it.

	Every suspension point casts down, pushes the hull up with a damped spring, and adds grip
	(sideways) and drive / brake (lengthwise) forces at the contact, capped by a friction circle.
	Tracks (tank) steer with a yaw-rate controller instead of steered wheels.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Vehicles.VehicleConfig)

local Sim = {}
Sim.__index = Sim

export type Input = { Throttle: number, Steer: number, Brake: boolean }

local ZERO_INPUT: Input = { Throttle = 0, Steer = 0, Brake = false }
Sim.ZeroInput = ZERO_INPUT

-- characters never hold a vehicle up (run-overs are handled by the server); refreshed lazily
local charList: { Instance } = {}
local charListAt = 0
local function characters(): { Instance }
	local now = os.clock()
	if now - charListAt > 0.5 then
		charListAt = now
		charList = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(charList, p.Character)
			end
		end
	end
	return charList
end

function Sim.new(model: Model)
	local root = model.PrimaryPart :: BasePart
	local kind = model:GetAttribute("VehicleType") :: string
	local cfg = Config.Vehicles[kind]
	local self = setmetatable({}, Sim)
	self.Model = model
	self.Root = root
	self.Kind = kind
	self.Cfg = cfg
	self.D = cfg.Drive
	self.Wheels = {}
	local forces = model:WaitForChild("Wheels")
	for _, a in root:GetChildren() do
		if a:IsA("Attachment") and a:GetAttribute("RideDistance") then
			table.insert(self.Wheels, {
				Name = a.Name,
				Att = a,
				Force = forces:FindFirstChild("F_" .. a.Name) :: VectorForce,
				Ride = a:GetAttribute("RideDistance") :: number,
				Radius = a:GetAttribute("Radius") :: number,
				Steer = a:GetAttribute("Steer") == true,
				Drive = a:GetAttribute("Drive") == true,
				Side = a:GetAttribute("Side") :: number,
				Order = a:GetAttribute("Order") :: number,
				Dist = nil :: number?,
			})
		end
	end
	table.sort(self.Wheels, function(x, y)
		return x.Order < y.Order
	end)
	self.Torque = forces:WaitForChild("Stabilizer") :: Torque
	self.Lift = forces:FindFirstChild("F_Lift") :: VectorForce? -- flight only
	self.SteerAngle = 0
	self.YawCmd = 0
	self.Grounded = 0
	self.Speed = 0
	local s = root.Size
	self.InertiaYaw = cfg.Mass * (s.X * s.X + s.Z * s.Z) / 12
	self.InertiaTilt = cfg.Mass * (s.Y * s.Y + math.max(s.X, s.Z) ^ 2) / 12
	self.Params = RaycastParams.new()
	self.Params.FilterType = Enum.RaycastFilterType.Exclude
	self.Params.IgnoreWater = true
	return self
end

-- zero every force (ownership hand-over, destruction)
function Sim:Clear()
	for _, w in self.Wheels do
		w.Force.Force = Vector3.zero
		w.Dist = nil
	end
	self.Torque.Torque = Vector3.zero
	if self.Lift then
		self.Lift.Force = Vector3.zero
	end
end

local function approach(x: number, target: number, step: number): number
	if x < target then
		return math.min(target, x + step)
	end
	return math.max(target, x - step)
end

function Sim:Step(dt: number, input)
	local inp = input or ZERO_INPUT
	local root = self.Root
	if not root.Parent or root.Anchored then
		return
	end
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	if self.D.Kind == "Flight" then
		return self:StepFlight(dt, inp)
	end
	local D = self.D
	local cf = root.CFrame
	local up, fwd = cf.UpVector, cf.LookVector
	local v = root.AssemblyLinearVelocity
	local w = root.AssemblyAngularVelocity
	local com = root.AssemblyCenterOfMass
	local m = math.max(root.AssemblyMass, 1)
	local g = Workspace.Gravity
	local n = #self.Wheels
	local tracks = D.Kind == "Tracks"

	local filter = table.clone(characters())
	table.insert(filter, self.Model)
	self.Params.FilterDescendantsInstances = filter

	local vFwd = v:Dot(fwd)
	local speedFrac = math.clamp(math.abs(vFwd) / D.MaxForward, 0, 1)

	-- steering (wheels)
	if not tracks then
		local maxSteer = D.MaxSteer + (D.MaxSteerAtSpeed - D.MaxSteer) * speedFrac
		self.SteerAngle = approach(self.SteerAngle, -inp.Steer * maxSteer, D.SteerSpeed * dt)
	end

	-- longitudinal command (studs/s^2 along the hull)
	local accel = 0
	local throttle = math.clamp(inp.Throttle, -1, 1)
	if inp.Brake then
		accel = -math.sign(vFwd) * math.min(D.HandBrake, math.abs(vFwd) * 6)
	elseif throttle > 0.05 then
		if vFwd < -1.5 then
			accel = math.min(D.Brake, -vFwd * 6) -- moving backwards: brake first
		else
			local target = throttle * D.MaxForward
			accel = if vFwd < target then math.min(D.Accel, (target - vFwd) * 4) else -math.min(D.Coast, (vFwd - target) * 4)
		end
	elseif throttle < -0.05 then
		if vFwd > 1.5 then
			accel = -math.min(D.Brake, vFwd * 6)
		else
			local target = throttle * D.MaxReverse
			accel = if vFwd > target then -math.min(D.Accel * 0.7, (vFwd - target) * 4) else math.min(D.Coast, (target - vFwd) * 4)
		end
	else
		-- coasting; near a standstill the parking brake holds the vehicle on slopes
		accel = if math.abs(vFwd) < 3 then -vFwd * 8 else -math.sign(vFwd) * D.Coast
	end

	-- suspension + tyre forces
	local kSpring = m * g / (n * D.Sag)
	local cDamp = 2 * D.Damping * math.sqrt(kSpring * m / n)
	local steerCF = CFrame.fromAxisAngle(up, math.rad(self.SteerAngle))
	local grounded, drivenGrounded = 0, 0
	local boostSpeed, boostDir = nil, nil
	local liftTarget = nil
	local contacts = {}
	for i, wh in self.Wheels do
		local origin = cf:PointToWorldSpace(wh.Att.Position)
		local reach = wh.Ride + D.Sag + 1.5
		local hit = Workspace:Raycast(origin, -up * reach, self.Params)
		if hit then
			local dist = (hit.Position - origin):Dot(-up)
			wh.Dist = dist
			local x = (wh.Ride + D.Sag) - dist
			if x > 0 then
				local pv = v + w:Cross(origin - com)
				local fs = kSpring * x - cDamp * pv:Dot(up)
				-- bump stop: past 1.4 studs of extra compression the spring stiffens hard
				local over = (wh.Ride - 1.4) - dist
				if over > 0 then
					fs += kSpring * 6 * over
				end
				fs = math.max(0, fs)
				grounded += 1
				if wh.Drive then
					drivenGrounded += 1
				end
				-- the tyre pushes along the ground's normal (a wall edge's normal falls back to the hull's up)
				local nrm = if hit.Normal:Dot(up) > 0.5 then hit.Normal else up
				local lt = hit.Instance:GetAttribute("LiftTarget")
				if typeof(lt) == "Vector3" then
					liftTarget = lt
				end
				local rb = hit.Instance:GetAttribute("RampBoost")
				if rb then
					boostSpeed = rb
					boostDir = hit.Instance:GetAttribute("RampDir")
				end
				contacts[i] = { Origin = origin, Load = fs, PointVel = pv, Normal = nrm }
			end
		else
			wh.Dist = nil
		end
	end
	self.Grounded = grounded
	-- holding still (no throttle, slow): the tyres also cancel gravity along the ground — static grip
	local holding = math.abs(throttle) < 0.05 and math.abs(vFwd) < 3
	local gravity = Vector3.new(0, -g, 0)

	for i, wh in self.Wheels do
		local c = contacts[i]
		if not c then
			wh.Force.Force = Vector3.zero
			continue
		end
		-- steered wheels: the hull's forward turned about the hull's up by the steer angle, then laid
		-- onto the ground plane
		local nrm = c.Normal
		local wf0 = if wh.Steer then steerCF:VectorToWorldSpace(fwd) else fwd
		local wf = wf0 - nrm * wf0:Dot(nrm)
		wf = if wf.Magnitude > 1e-3 then wf.Unit else wf0
		local wr = wf:Cross(nrm)
		local weight = gravity * (m / grounded) -- this contact's share of the vehicle's weight
		-- sideways grip; tracks use the hull's sideways slip so they do not fight the yaw controller
		local vLat = if tracks then v:Dot(wr) else c.PointVel:Dot(wr)
		local grip = if not tracks and not wh.Steer then (D.RearGrip or D.Grip) else D.Grip
		if inp.Brake and not tracks and not wh.Steer then
			grip *= 0.35 -- handbrake: the rear steps out
		end
		-- sideways: velocity grip plus static resistance to sliding down a side slope
		local fLat = -vLat * (m / n) * grip - weight:Dot(wr)
		local fLong = 0
		if wh.Drive and drivenGrounded > 0 then
			fLong = m * accel / drivenGrounded
		end
		if holding then
			fLong -= weight:Dot(wf) -- parked on a slope: do not creep
		end
		-- friction circle
		local cap = D.Friction * c.Load
		local mag = math.sqrt(fLat * fLat + fLong * fLong)
		if mag > cap and mag > 0 then
			local s = cap / mag
			fLat *= s
			fLong *= s
		end
		wh.Force.Force = nrm * c.Load + wr * fLat + wf * fLong
	end

	-- vehicle lifts: a lime lift pad throws the vehicle in an arc onto its deck
	if liftTarget and os.clock() - (self.LastLift or 0) > 2 then
		self.LastLift = os.clock()
		local start = root.Position
		local rise = math.max(liftTarget.Y - start.Y, 0)
		local apex = rise + 14
		local vy = math.sqrt(2 * g * apex)
		local t = vy / g + math.sqrt(2 * (apex - rise + 2) / g)
		local flat = Vector3.new(liftTarget.X - start.X, 0, liftTarget.Z - start.Z)
		root.AssemblyLinearVelocity = flat / t + Vector3.new(0, vy, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end

	-- launch ramps: driving uphill on a boost ramp shoves the vehicle up the slope
	if boostSpeed and typeof(boostDir) == "Vector3" then
		local along = v:Dot(boostDir)
		if along > 2 and along < boostSpeed then
			local dv = math.min(boostSpeed - along, 160 * dt)
			root:ApplyImpulse(boostDir * dv * m)
		end
	end

	-- torques: tracks steer by yaw rate; everything gets an upright stabiliser
	local torque = Vector3.zero
	local yawRate = w:Dot(up)
	if tracks then
		local rate = math.rad(D.TurnRate + (D.TurnRateAtSpeed - D.TurnRate) * speedFrac)
		self.YawCmd += (-inp.Steer * rate - self.YawCmd) * math.min(1, D.TurnAccel * dt)
		if grounded > 0 then
			local tau = self.InertiaYaw * (self.YawCmd - yawRate) * 8
			local maxTau = self.InertiaYaw * 5
			torque += up * math.clamp(tau, -maxTau, maxTau) * (grounded / n)
		end
	end
	local tiltAxis = up:Cross(Vector3.yAxis)
	local tiltRate = w - up * yawRate
	local k = D.Stabilize * (if grounded >= n * 0.5 then 0.35 else 1)
	torque += tiltAxis * self.InertiaTilt * 14 * k - tiltRate * self.InertiaTilt * 3 * k
	self.Torque.Torque = torque
	self.Speed = vFwd
	self.Accel = accel
end

--[[ Flight (drone). input: Throttle (forward / back), Steer (strafe), Climb (-1..1), Yaw (world yaw
	the airframe should face — the pilot's camera), Piloted. One lift force at the centre of mass
	holds a target velocity; a PD torque turns the airframe to the wanted yaw and leans it into its
	acceleration. The altitude band is part of the controller: never below MinClearance over the
	ground, never above MaxAltitude (world Y). Nobody flying: it settles to the ground and idles. ]]
function Sim:StepFlight(dt: number, inp)
	local D = self.D
	local root = self.Root
	local lift = self.Lift
	if not lift then
		return
	end
	local cf = root.CFrame
	local v = root.AssemblyLinearVelocity
	local w = root.AssemblyAngularVelocity
	local m = math.max(root.AssemblyMass, 1)
	local g = Workspace.Gravity
	local filter = table.clone(characters())
	table.insert(filter, self.Model)
	self.Params.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -400, 0), self.Params)
	local height = if hit then root.Position.Y - hit.Position.Y else 400
	local bottom = root.Size.Y / 2 + 0.3
	local yaw = inp.Yaw
	if type(yaw) ~= "number" then
		local lv = cf.LookVector
		yaw = math.atan2(-lv.X, -lv.Z)
	end
	local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local targetH, targetV
	if inp.Piloted then
		-- mouse flight: thrust goes where the camera points (look up to climb, down to dive)
		local f = math.clamp(inp.Throttle or 0, -1, 1)
		local pitch = math.clamp(if type(inp.Pitch) == "number" then inp.Pitch else 0, -1.2, 1.2)
		local speed = if f >= 0 then f * D.MaxForward else f * D.MaxReverse
		targetH = fwd * (speed * math.cos(pitch)) + right * math.clamp(inp.Steer or 0, -1, 1) * D.MaxStrafe
		if targetH.Magnitude > D.MaxForward then
			targetH = targetH.Unit * D.MaxForward
		end
		targetV = math.clamp(speed * math.sin(pitch) + math.clamp(inp.Climb or 0, -1, 1) * D.MaxClimb, -D.MaxClimb, D.MaxClimb)
		-- altitude band
		local floor = D.MinClearance + bottom
		if height < floor then
			targetV = math.max(targetV, (floor - height) * 4)
		end
		targetV = math.min(targetV, (D.MaxAltitude - root.Position.Y) * 3)
	else
		-- nobody flying: settle to the ground, then switch off
		targetH = Vector3.zero
		targetV = -14
		if height <= bottom + 0.5 then
			lift.Force = Vector3.zero
			self.Torque.Torque = Vector3.zero
			self.Speed = 0
			self.Height = height
			return
		end
	end
	local vH = Vector3.new(v.X, 0, v.Z)
	local accelH = (targetH - vH) * 3
	local maxA = if targetH.Magnitude < vH.Magnitude - 1 then D.Brake else D.Accel
	if accelH.Magnitude > maxA then
		accelH = accelH.Unit * maxA
	end
	local accelV = math.clamp((targetV - v.Y) * 4, -D.ClimbAccel, D.ClimbAccel)
	lift.Force = Vector3.new(accelH.X, accelV + g, accelH.Z) * m
	-- attitude: face the yaw, lean into the acceleration
	local fa = math.clamp(accelH:Dot(fwd) / D.Accel, -1, 1)
	local ra = math.clamp(accelH:Dot(right) / D.Accel, -1, 1)
	local tilt = math.rad(D.Tilt)
	-- the nose follows the mouse a little (half the camera's pitch), plus the lean into acceleration
	local nose = if inp.Piloted and type(inp.Pitch) == "number" then math.clamp(inp.Pitch * 0.5, -0.45, 0.35) else 0
	local want = CFrame.fromOrientation(0, yaw, 0) * CFrame.Angles(nose - fa * tilt, 0, -ra * tilt)
	local axis, angle = (want.Rotation * cf.Rotation:Inverse()):ToAxisAngle()
	if angle > math.pi then
		angle -= 2 * math.pi
	end
	local k = D.TurnSpeed
	local I = self.InertiaYaw
	self.Torque.Torque = (axis * angle * k * k - w * 2 * k) * I
	self.Speed = vH:Dot(fwd)
	self.Height = height
end

return Sim
