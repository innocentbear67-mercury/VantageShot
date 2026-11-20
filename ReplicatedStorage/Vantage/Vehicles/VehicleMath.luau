--!strict
--[[
	VANTAGE — VehicleMath (shared)
	Turret kinematics, identical on server and clients. The weapon always fires along the real
	barrel: muzzle = Root * YawPivot * yaw * PitchPivot * pitch * MuzzleOffset (offsets written
	by VehicleBuilder as model attributes). The camera only chooses where the turret tries to go.
	Yaw > 0 turns left, pitch > 0 raises the barrel (radians).
]]

local M = {}

function M.Offsets(model: Model)
	return model:GetAttribute("YawPivot") :: Vector3, model:GetAttribute("PitchPivot") :: Vector3, model:GetAttribute("MuzzleOffset") :: Vector3
end

function M.YawFrame(rootCF: CFrame, model: Model, yaw: number): CFrame
	local yp = model:GetAttribute("YawPivot") :: Vector3
	return rootCF * CFrame.new(yp) * CFrame.Angles(0, yaw, 0)
end

function M.PitchFrame(rootCF: CFrame, model: Model, yaw: number, pitch: number): CFrame
	local pp = model:GetAttribute("PitchPivot") :: Vector3
	return M.YawFrame(rootCF, model, yaw) * CFrame.new(pp) * CFrame.Angles(pitch, 0, 0)
end

function M.Muzzle(rootCF: CFrame, model: Model, yaw: number, pitch: number): CFrame
	local mo = model:GetAttribute("MuzzleOffset") :: Vector3
	-- the barrel axis is the pitch frame's look; the muzzle sits at the barrel tip on that axis
	return M.PitchFrame(rootCF, model, yaw, pitch) * CFrame.new(mo)
end

-- yaw / pitch (radians, hull-relative) that point the barrel at a world point
function M.AnglesTo(rootCF: CFrame, model: Model, point: Vector3, currentYaw: number?): (number, number)
	local yp = model:GetAttribute("YawPivot") :: Vector3
	local pp = model:GetAttribute("PitchPivot") :: Vector3
	local mo = model:GetAttribute("MuzzleOffset") :: Vector3
	local d = (rootCF * CFrame.new(yp)):PointToObjectSpace(point)
	local yaw = math.atan2(-d.X, -d.Z)
	local frame = rootCF * CFrame.new(yp) * CFrame.Angles(0, yaw, 0) * CFrame.new(pp)
	local d2 = frame:PointToObjectSpace(point)
	-- the barrel sits mo.Y above the pitch pivot: aim so the bore line (not the pivot) meets the point
	local horiz = math.max(1, math.sqrt(d2.X * d2.X + d2.Z * d2.Z))
	local pitch = math.atan2(d2.Y, horiz) - math.asin(math.clamp(mo.Y / math.max(horiz, math.abs(mo.Y) + 0.01), -1, 1))
	return yaw, pitch
end

function M.WrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- move the current angles toward the wanted ones at the weapon's slew rates (deg/s)
function M.Slew(yaw: number, pitch: number, wantYaw: number, wantPitch: number, w, dt: number): (number, number)
	local dy = M.WrapAngle(wantYaw - yaw)
	local maxY = math.rad(w.YawSpeed) * dt
	yaw = M.WrapAngle(yaw + math.clamp(dy, -maxY, maxY))
	if w.YawLimit then
		local lim = math.rad(w.YawLimit)
		yaw = math.clamp(yaw, -lim, lim)
	end
	wantPitch = math.clamp(wantPitch, math.rad(w.PitchMin), math.rad(w.PitchMax))
	local maxP = math.rad(w.PitchSpeed) * dt
	pitch += math.clamp(wantPitch - pitch, -maxP, maxP)
	return yaw, pitch
end

-- deterministic cone spread for MG rounds (degrees)
function M.Spread(dir: Vector3, deg: number, rng: Random): Vector3
	if deg <= 0 then
		return dir
	end
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local a = rng:NextNumber(0, 2 * math.pi)
	local r = math.rad(deg) * math.sqrt(rng:NextNumber())
	return (cf * CFrame.Angles(math.sin(a) * r, math.cos(a) * r, 0)).LookVector
end

return M
