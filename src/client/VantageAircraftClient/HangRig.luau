--[[
	VANTAGE — HangRig (client): the body on the dropship's cable, solved every frame
	Not a canned pose. Each frame, from where the character is, where the hook is and how the
	body is moving relative to it:
		- arms: aimed along the real cable (left arm up the line to the hook, right hand gripping
		  a little lower), relaxed elbows, wrists flexed round the grip
		- legs: hanging loose (slight knee bend, pointed feet) and TRAILING the swing through a
		  spring with a little overshoot, so banks, the catch and accelerations read in the body
		- torso: a slight hollow with breathing; head looks a touch down at the battlefield, or
		  (local player) where the camera looks, within neck limits
		- the pull ("Pull"): reaching up the cable, legs trailing, back arched
	Returns Motor6D.Transform values (R15). The caller blends them over the animation.

	local st = HangRig.NewState(seed)
	local tf = HangRig.Solve(motors, rootCF, hookPos, swingWorld, phase, lookWorld?, st, dt)
		motors = HangRig.Motors(character)   swingWorld = body velocity relative to the hook
]]

local HangRig = {}

HangRig.Joints = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
}

-- tuning (radians unless noted)
HangRig.Tune = {
	-- arms: both hands on the ONE cable, the left above the right, over the head
	LeftElbow = 0.05, RightElbow = 0.16,
	LeftTwist = 0, RightTwist = 0,
	Cross = 0.22, -- studs: each hand aims this far past the cable, so the two grips overlap on it
	GripBase = 0.9, -- studs above the upper torso's centre where the cable line starts (neck)
	GripReach = 1.25, -- studs up the cable from there to the left hand (the suit's arms are ~2.2 long)
	RightGripDrop = 0.4, -- studs: the right hand grips this far below the left
	Wrist = 0.35,
	-- legs
	HipL = 0.16, HipR = 0.05, KneeL = -0.42, KneeR = -0.22, Ankle = -0.38,
	HipSplay = 0.05,
	TrailPitch = 0.016, TrailRoll = 0.014, TrailMax = 0.42, -- per stud/s of swing
	SpringW = 6.5, SpringZeta = 0.45, -- leg follow-through
	-- torso / head
	Waist = -0.06, Breath = 0.018, BreathRate = 1.25,
	HeadDown = -0.2, NeckYawMax = 0.9, NeckPitchMin = -0.6, NeckPitchMax = 0.35,
	IdleLegs = 0.05, IdleRate = 0.75,
	-- pull
	PullHip = -0.22, PullKnee = -0.55, PullWaist = -0.12,
}

function HangRig.Motors(character: Model): { [string]: Motor6D }
	local m = {}
	for joint, partName in HangRig.Joints do
		local part = character:FindFirstChild(partName)
		local j = part and part:FindFirstChild(joint)
		if j and j:IsA("Motor6D") then
			m[joint] = j
		end
	end
	return m
end

function HangRig.NewState(seed: number?)
	return {
		T = (seed or 0) % 17, Sv = Vector3.zero,
		LegP = 0, LegPV = 0, LegR = 0, LegRV = 0,
		Neck = Vector2.zero,
	}
end

local function fromTo(a: Vector3, b: Vector3): CFrame
	local d = math.clamp(a:Dot(b), -1, 1)
	if d > 0.99999 then
		return CFrame.identity
	end
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then
		axis = a:Cross(Vector3.xAxis)
		if axis.Magnitude < 1e-5 then
			axis = a:Cross(Vector3.zAxis)
		end
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(d))
end

-- spring step (semi-implicit), returns new x, v
local function spring(x: number, v: number, target: number, w: number, zeta: number, dt: number)
	local a = w * w * (target - x) - 2 * zeta * w * v
	v += a * dt
	x += v * dt
	return x, v
end

-- world frame of a part given its parent's frame and the joint's transform
local function child(parentCF: CFrame, m: Motor6D, t: CFrame): CFrame
	return parentCF * m.C0 * t * m.C1:Inverse()
end

-- the shoulder transform that points the upper arm at `targetWorld`, with a twist about the arm
local function aimArm(upperTorsoCF: CFrame, m: Motor6D, targetWorld: Vector3, twist: number): CFrame
	local jointCF = upperTorsoCF * m.C0
	local w = jointCF:VectorToObjectSpace((targetWorld - jointCF.Position).Unit)
	local u = m.C1:VectorToObjectSpace(Vector3.new(0, -1, 0)) -- the arm's rest direction, joint frame
	local r = fromTo(u, w)
	return CFrame.fromAxisAngle(w, twist) * r
end

function HangRig.Solve(motors, rootCF: CFrame, hookPos: Vector3, swingWorld: Vector3, phase: string, lookWorld: Vector3?, st, dt: number)
	local T = HangRig.Tune
	dt = math.clamp(dt, 0, 1 / 15)
	st.T += dt
	local tf = {}
	local pull = phase == "Pull"

	-- swing in the body's frame (x right, y up, z back), smoothed a touch
	local sv = rootCF:VectorToObjectSpace(swingWorld)
	st.Sv = st.Sv:Lerp(sv, 1 - math.exp(-12 * dt))
	-- legs trail the motion: forward motion (-z) swings them back, sideways swings them out
	local tp = math.clamp(st.Sv.Z * T.TrailPitch, -T.TrailMax, T.TrailMax)
	local tr = math.clamp(-st.Sv.X * T.TrailRoll, -T.TrailMax, T.TrailMax)
	st.LegP, st.LegPV = spring(st.LegP, st.LegPV, tp, T.SpringW, T.SpringZeta, dt)
	st.LegR, st.LegRV = spring(st.LegR, st.LegRV, tr, T.SpringW, T.SpringZeta, dt)

	local breathe = math.sin(st.T * T.BreathRate * 2 * math.pi / 2)
	local idleL = math.sin(st.T * T.IdleRate * 2 * math.pi / 2) * T.IdleLegs
	local idleR = math.sin(st.T * T.IdleRate * 2 * math.pi / 2 + 2.3) * T.IdleLegs

	-- torso
	local waist = CFrame.Angles((if pull then T.PullWaist else T.Waist) + breathe * T.Breath, 0, -st.LegR * 0.25)
	tf.Root = CFrame.identity
	tf.Waist = waist

	-- legs
	local legP, legR = st.LegP, st.LegR
	if pull then
		tf.LeftHip = CFrame.Angles(T.PullHip + legP * 0.5 + idleL, 0, -T.HipSplay + legR)
		tf.RightHip = CFrame.Angles(T.PullHip + 0.08 + legP * 0.5 + idleR, 0, T.HipSplay + legR)
		tf.LeftKnee = CFrame.Angles(T.PullKnee, 0, 0)
		tf.RightKnee = CFrame.Angles(T.PullKnee + 0.2, 0, 0)
	else
		tf.LeftHip = CFrame.Angles(T.HipL + legP + idleL, 0, -T.HipSplay + legR)
		tf.RightHip = CFrame.Angles(T.HipR + legP + idleR, 0, T.HipSplay + legR)
		-- knees fold a little more when the legs are swung back (follow-through)
		tf.LeftKnee = CFrame.Angles(T.KneeL + math.min(0, legP) * 0.6, 0, 0)
		tf.RightKnee = CFrame.Angles(T.KneeR + math.min(0, legP) * 0.6, 0, 0)
	end
	tf.LeftAnkle = CFrame.Angles(T.Ankle, 0, 0)
	tf.RightAnkle = CFrame.Angles(T.Ankle + 0.06, 0, 0)

	-- arms along the cable: the torso's frame this frame, then aim each upper arm
	local root, waistM = motors.Root, motors.Waist
	if root and waistM then
		local lower = child(rootCF, root, tf.Root)
		local upper = child(lower, waistM, tf.Waist)
		local ls, rs = motors.LeftShoulder, motors.RightShoulder
		-- the cable runs from the hook down to just above the head; the hands meet on it
		local base = upper.Position + upper.UpVector * T.GripBase
		local ropeDir = (hookPos - base).Unit
		local gripL = base + ropeDir * T.GripReach
		local gripR = gripL - ropeDir * T.RightGripDrop
		if ls then
			tf.LeftShoulder = aimArm(upper, ls, gripL + upper.RightVector * T.Cross, T.LeftTwist)
		end
		if rs then
			tf.RightShoulder = aimArm(upper, rs, gripR - upper.RightVector * T.Cross, T.RightTwist)
		end
		tf.LeftElbow = CFrame.Angles(if pull then 0.08 else T.LeftElbow, 0, 0)
		tf.RightElbow = CFrame.Angles(if pull then 0.25 else T.RightElbow, 0, 0)
		tf.LeftWrist = CFrame.Angles(T.Wrist, 0, 0)
		tf.RightWrist = CFrame.Angles(T.Wrist, 0, 0)

		-- head: a little down at the battlefield, or toward where you look
		local neck = motors.Neck
		if neck then
			local want = Vector2.new(T.HeadDown, 0)
			if lookWorld then
				local l = upper:VectorToObjectSpace(lookWorld)
				local yaw = math.atan2(-l.X, -l.Z)
				local pitch = math.asin(math.clamp(l.Y, -1, 1))
				want = Vector2.new(math.clamp(pitch, T.NeckPitchMin, T.NeckPitchMax), math.clamp(yaw, -T.NeckYawMax, T.NeckYawMax))
			end
			st.Neck = st.Neck:Lerp(want, 1 - math.exp(-6 * dt))
			tf.Neck = CFrame.Angles(st.Neck.X, st.Neck.Y, 0)
		end
	end
	return tf
end

return HangRig
