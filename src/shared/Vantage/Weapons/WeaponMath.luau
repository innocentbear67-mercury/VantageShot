--[[
	VANTAGE — WeaponMath (shared)
	Pure helpers used by the server hit validation and client prediction.
]]

local WeaponMath = {}

-- Ray vs oriented box (slab test). origin/dir world-space, dir need not be unit
-- (t is returned in units of dir). Returns t of entry (>= 0) or nil.
function WeaponMath.RayOBB(origin: Vector3, dir: Vector3, boxCF: CFrame, half: Vector3): number?
	local o = boxCF:PointToObjectSpace(origin)
	local d = boxCF:VectorToObjectSpace(dir)
	local tmin, tmax = -math.huge, math.huge
	for _, axis in ipairs({ "X", "Y", "Z" }) do
		local oa, da, h = o[axis], d[axis], half[axis]
		if math.abs(da) < 1e-9 then
			if oa < -h or oa > h then
				return nil
			end
		else
			local t1 = (-h - oa) / da
			local t2 = (h - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmax < 0 then
		return nil
	end
	return math.max(tmin, 0)
end

-- Random direction inside a cone of half-angle `deg` around `dir` (uniform over the disc).
function WeaponMath.ApplySpread(dir: Vector3, deg: number, rng: Random): Vector3
	if deg <= 1e-4 then
		return dir.Unit
	end
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local r = math.rad(deg) * math.sqrt(rng:NextNumber())
	local a = rng:NextNumber() * math.pi * 2
	local local_ = Vector3.new(math.cos(a) * math.tan(r), math.sin(a) * math.tan(r), -1)
	return cf:VectorToWorldSpace(local_).Unit
end

-- Deterministic shotgun pattern: the client sends only its aim direction + an integer seed; both
-- sides rebuild the identical pellet directions (first pellet always dead centre).
function WeaponMath.PelletDirs(dir: Vector3, count: number, spreadDeg: number, seed: number): { Vector3 }
	local rng = Random.new(seed)
	local list = { dir.Unit }
	for i = 2, count do
		-- even ring coverage: angle from the index, radius jittered by the seed
		local ring = if i <= 4 then 0.45 else 0.95
		local r = spreadDeg * (ring * (0.75 + rng:NextNumber() * 0.25))
		local a = (i / count) * math.pi * 2 + rng:NextNumber() * 0.6
		local cf = CFrame.lookAt(Vector3.zero, dir)
		local t = math.tan(math.rad(r))
		table.insert(list, cf:VectorToWorldSpace(Vector3.new(math.cos(a) * t, math.sin(a) * t, -1)).Unit)
	end
	return list
end

function WeaponMath.IsFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- Damage for a validated hit (server only uses this; exposed for UI previews).
function WeaponMath.Damage(weapon, isHead: boolean, isLimb: boolean, distance: number): number
	local dmg = weapon.Damage
	if isHead then
		dmg *= weapon.HeadshotMultiplier
	elseif isLimb then
		dmg *= weapon.LimbMultiplier
	end
	if weapon.FalloffMinMultiplier < 1 and distance > weapon.FalloffStart then
		local a = math.clamp((distance - weapon.FalloffStart) / math.max(1, weapon.FalloffEnd - weapon.FalloffStart), 0, 1)
		dmg *= 1 + (weapon.FalloffMinMultiplier - 1) * a
	end
	return dmg
end

local LIMBS = {
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}
WeaponMath.Limbs = LIMBS

local HITBOX_PARTS = {
	Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
}
for k in pairs(LIMBS) do
	HITBOX_PARTS[k] = true
end
WeaponMath.HitboxParts = HITBOX_PARTS

return WeaponMath
