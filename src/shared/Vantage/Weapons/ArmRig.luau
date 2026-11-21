--[[
	VANTAGE — ArmRig (shared)
	One arm model used by BOTH views so first and third person can never disagree:
	  • first person: anchored clones of the player's own R15 arm parts, positioned directly
	  • third person: the real character's arm joints, driven through joint Transforms
	Geometry comes from the rig's own attachments (Shoulder/Elbow/WristRigAttachment), so any
	avatar proportions work and the segments never stretch.

	Solve(arm, shoulderPos, handCF, pole) is an analytic two-bone IK:
	  wrist = handCF * wrist attachment; elbow placed on the circle of valid positions toward
	  `pole`; each segment is oriented so its local front (-Z) faces the side the joint folds to
	  (elbow hinge stays anatomical). Targets out of reach slide the hand toward the shoulder
	  instead of detaching it from the forearm.
]]

local ArmRig = {}

local function names(side: string)
	return {
		Upper = side .. "UpperArm",
		Lower = side .. "LowerArm",
		Hand = side .. "Hand",
		Shoulder = side .. "Shoulder",
		Elbow = side .. "Elbow",
		Wrist = side .. "Wrist",
		ShoulderAtt = side .. "ShoulderRigAttachment",
		ElbowAtt = side .. "ElbowRigAttachment",
		WristAtt = side .. "WristRigAttachment",
		GripAtt = side .. "GripAttachment",
	}
end
ArmRig.Names = names

local function attPos(part: Instance?, name: string): Vector3?
	local a = part and part:FindFirstChild(name)
	return a and a:IsA("Attachment") and a.Position or nil
end
local function attCF(part: Instance?, name: string): CFrame?
	local a = part and part:FindFirstChild(name)
	return a and a:IsA("Attachment") and a.CFrame or nil
end

-- Reads arm geometry from a container holding the three arm parts (character or clone model).
-- scale multiplies every length (first-person arms are scaled clones).
function ArmRig.Read(container: Instance, side: string, scale: number?)
	local s = scale or 1
	local n = names(side)
	local upper = container:FindFirstChild(n.Upper)
	local lower = container:FindFirstChild(n.Lower)
	local hand = container:FindFirstChild(n.Hand)
	if not (upper and lower and hand) then
		return nil
	end
	local us, ue = attPos(upper, n.ShoulderAtt), attPos(upper, n.ElbowAtt)
	local le, lw = attPos(lower, n.ElbowAtt), attPos(lower, n.WristAtt)
	local hw = attPos(hand, n.WristAtt)
	local grip = attCF(hand, n.GripAtt)
	if not (us and ue and le and lw and hw) then
		return nil
	end
	local arm = {
		Side = side,
		Names = n,
		Scale = s,
		UpperShoulder = us * s,
		UpperElbow = ue * s,
		LowerElbow = le * s,
		LowerWrist = lw * s,
		HandWrist = hw * s,
		-- where a held object's axis passes through the fist (Roblox tool convention)
		Grip = grip and (CFrame.new(grip.Position * s) * grip.Rotation) or CFrame.new(0, -0.1 * s, 0),
	}
	arm.L1 = (arm.UpperElbow - arm.UpperShoulder).Magnitude
	arm.L2 = (arm.LowerWrist - arm.LowerElbow).Magnitude
	arm.Reach = arm.L1 + arm.L2
	return arm
end

-- Hand CFrame that puts the fist's grip axis on `gripCF` (object frame: +Y = thumb side).
function ArmRig.HandFromGrip(arm, gripCF: CFrame): CFrame
	return gripCF * arm.Grip:Inverse()
end

local function perpendicular(v: Vector3, axis: Vector3): Vector3
	return v - axis * v:Dot(axis)
end

-- orient a segment whose local points a -> b must map onto world P -> Q, local -Z toward `front`
local function placeSegment(a: Vector3, b: Vector3, P: Vector3, Q: Vector3, front: Vector3): CFrame
	local u = (b - a).Unit
	local fl = perpendicular(Vector3.new(0, 0, -1), u)
	if fl.Magnitude < 1e-4 then
		fl = perpendicular(Vector3.new(1, 0, 0), u)
	end
	fl = fl.Unit
	local U = (Q - P).Unit
	local F = perpendicular(front, U)
	if F.Magnitude < 1e-4 then
		F = perpendicular(Vector3.new(0, 1, 0), U)
		if F.Magnitude < 1e-4 then
			F = perpendicular(Vector3.new(1, 0, 0), U)
		end
	end
	F = F.Unit
	local Bl = CFrame.fromMatrix(Vector3.zero, u, fl, u:Cross(fl))
	local Bw = CFrame.fromMatrix(Vector3.zero, U, F, U:Cross(F))
	local R = Bw * Bl:Inverse()
	return CFrame.new(P - R:VectorToWorldSpace(a)) * R
end

--[[ returns upperCF, lowerCF, handCF, reached ]]
function ArmRig.Solve(arm, shoulder: Vector3, handCF: CFrame, pole: Vector3)
	local L1, L2 = arm.L1, arm.L2
	local wrist = (handCF * CFrame.new(arm.HandWrist)).Position
	local toW = wrist - shoulder
	local d = toW.Magnitude
	local reached = true
	local maxD = (L1 + L2) * 0.999
	if d > maxD then
		reached = false
		local newWrist = shoulder + toW.Unit * maxD
		handCF = handCF + (newWrist - wrist) -- keep hand attached to the forearm
		wrist = newWrist
		toW = wrist - shoulder
		d = maxD
	end
	local minD = math.abs(L1 - L2) + 1e-3
	if d < minD then
		d = minD
	end
	local n = toW.Unit
	local a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, L1 * L1 - a * a))
	local p = perpendicular(pole, n)
	if p.Magnitude < 1e-4 then
		p = perpendicular(Vector3.new(0, -1, 0), n)
	end
	p = p.Unit
	local elbow = shoulder + n * a + p * h
	local upperDir = elbow - shoulder
	local upperFront = perpendicular(wrist - elbow, upperDir.Unit)
	if upperFront.Magnitude < 1e-3 then
		upperFront = -p
	end
	local lowerDir = wrist - elbow
	local lowerFront = perpendicular(shoulder - elbow, lowerDir.Unit)
	if lowerFront.Magnitude < 1e-3 then
		lowerFront = -p
	end
	local upperCF = placeSegment(arm.UpperShoulder, arm.UpperElbow, shoulder, elbow, upperFront)
	local lowerCF = placeSegment(arm.LowerElbow, arm.LowerWrist, elbow, wrist, lowerFront)
	return upperCF, lowerCF, handCF, reached
end

-- Joint Transform that makes part1 land on `part1CF` given part0's (predicted) CFrame.
-- Works for AnimationConstraint (new avatar joints) and Motor6D.
function ArmRig.JointTransform(joint: Instance, part0CF: CFrame, part1CF: CFrame): CFrame?
	if joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if not (a0 and a1) then
			return nil
		end
		return (part0CF * a0.CFrame):Inverse() * part1CF * a1.CFrame
	elseif joint:IsA("Motor6D") then
		return (part0CF * joint.C0):Inverse() * part1CF * joint.C1
	end
	return nil
end

-- Forward kinematics: part1 CFrame for a joint given part0's CFrame and a Transform.
function ArmRig.JointChild(joint: Instance, part0CF: CFrame, transform: CFrame): CFrame?
	if joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if not (a0 and a1) then
			return nil
		end
		return part0CF * a0.CFrame * transform * a1.CFrame:Inverse()
	elseif joint:IsA("Motor6D") then
		return part0CF * joint.C0 * transform * joint.C1:Inverse()
	end
	return nil
end

return ArmRig
