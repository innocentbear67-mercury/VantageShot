-- Property tests for src/shared/Vantage/Weapons/WeaponMath.luau (RayOBB +
-- ApplySpread). Runs under Lune with engine datatypes injected through the
-- documented luau.load environment (see tests/roblox_globals.luau for why _G
-- injection is impossible in Lune 0.11.1). All randomness comes from an inline
-- seeded MINSTD LCG (exact in f64), so every run is reproducible.

local RG = require("./roblox_globals")
local V3 = RG.roblox.Vector3
local CF = RG.roblox.CFrame
local WeaponMath = RG.loadShared("src/shared/Vantage/Weapons/WeaponMath.luau")

local NaN = 0 / 0

-- ─── deterministic randomness (MINSTD: full period, exact in f64) ────────
local state = 20261121
local function rnd(): number
	state = (state * 48271) % 2147483647
	return state / 2147483647
end
local function range(lo: number, hi: number): number
	return lo + (hi - lo) * rnd()
end
local function rngStub(): any
	return { NextNumber = function(_self: any): number
		return rnd()
	end }
end

-- ─── reference slab test (independent of the module's transform calls) ──
-- Uses CFrame:GetComponents() raw matrix numbers instead of the module's
-- PointToObjectSpace/VectorToObjectSpace, and mirrors the module's published
-- semantics (parallel threshold 1e-9, entry t >= 0, nil on miss).
local function refRayOBB(origin: any, dir: any, boxCF: any, half: any): number?
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = boxCF:GetComponents()
	local wx, wy, wz = origin.X - px, origin.Y - py, origin.Z - pz
	local lo = {
		wx * r00 + wy * r10 + wz * r20,
		wx * r01 + wy * r11 + wz * r21,
		wx * r02 + wy * r12 + wz * r22,
	}
	local ld = {
		dir.X * r00 + dir.Y * r10 + dir.Z * r20,
		dir.X * r01 + dir.Y * r11 + dir.Z * r21,
		dir.X * r02 + dir.Y * r12 + dir.Z * r22,
	}
	local h = { half.X, half.Y, half.Z }
	local tmin, tmax = -math.huge, math.huge
	for i = 1, 3 do
		local oa, da, he = lo[i], ld[i], h[i]
		if math.abs(da) < 1e-9 then
			if oa < -he or oa > he then
				return nil
			end
		else
			local t1 = (-he - oa) / da
			local t2 = (he - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then
				tmin = t1
			end
			if t2 < tmax then
				tmax = t2
			end
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

-- ─── RayOBB: ~200 seeded random trials ───────────────────────────────────
local hits, misses = 0, 0
for i = 1, 200 do
	local half = V3.new(range(0.5, 8), range(0.5, 8), range(0.5, 8))
	local pos = V3.new(range(-20, 20), range(-20, 20), range(-20, 20))
	local rot = CF.Angles(range(-0.5, 0.5), range(-0.5, 0.5), range(-0.5, 0.5)) -- small rotations
	local boxCF = CF.new(pos.X, pos.Y, pos.Z) * rot
	-- origin: outside the bounding sphere, so guaranteed outside the box
	local ox, oy, oz = rnd() * 2 - 1, rnd() * 2 - 1, rnd() * 2 - 1
	local len = math.sqrt(ox * ox + oy * oy + oz * oz)
	if len < 1e-6 then
		ox, oy, oz, len = 0.3, 0.5, 0.8, math.sqrt(0.98)
	end
	local dist = math.sqrt(half.X ^ 2 + half.Y ^ 2 + half.Z ^ 2) + range(2, 30)
	local origin = V3.new(pos.X + ox / len * dist, pos.Y + oy / len * dist, pos.Z + oz / len * dist)
	-- aim: box centre plus an overshootable offset, so both hits and misses occur
	local aim = V3.new(pos.X + range(-2, 2) * half.X, pos.Y + range(-2, 2) * half.Y, pos.Z + range(-2, 2) * half.Z)
	local dir = aim - origin

	local t = WeaponMath.RayOBB(origin, dir, boxCF, half)
	local tref = refRayOBB(origin, dir, boxCF, half)
	local ctx = string.format(
		"trial %d: half=(%.4f, %.4f, %.4f) pos=(%.4f, %.4f, %.4f) origin=(%.4f, %.4f, %.4f) dir=(%.4f, %.4f, %.4f)",
		i, half.X, half.Y, half.Z, pos.X, pos.Y, pos.Z, origin.X, origin.Y, origin.Z, dir.X, dir.Y, dir.Z
	)
	assert((t == nil) == (tref == nil), "RayOBB vs reference disagreement on hit/miss — " .. ctx)
	if t == nil then
		misses += 1
	else
		hits += 1
		assert(type(t) == "number" and t == t, "RayOBB returned a non-number/NaN t — " .. ctx)
		assert(t >= 0, string.format("RayOBB returned t=%.6f < 0 — %s", t, ctx))
		assert(math.abs(t - (tref :: number)) <= 1e-6, string.format("RayOBB t=%.9f vs reference %.9f — %s", t, tref :: number, ctx))
		-- hit point lies inside the box (box-local, half-extents + 1e-3)
		local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = boxCF:GetComponents()
		local hx = origin.X + dir.X * t - px
		local hy = origin.Y + dir.Y * t - py
		local hz = origin.Z + dir.Z * t - pz
		local lx = hx * r00 + hy * r10 + hz * r20
		local ly = hx * r01 + hy * r11 + hz * r21
		local lz = hx * r02 + hy * r12 + hz * r22
		assert(
			math.abs(lx) <= half.X + 1e-3 and math.abs(ly) <= half.Y + 1e-3 and math.abs(lz) <= half.Z + 1e-3,
			string.format("RayOBB hit point outside box: local=(%.6f, %.6f, %.6f) t=%.6f — %s", lx, ly, lz, t, ctx)
		)
	end
end
assert(hits > 20, string.format("RayOBB trial set produced only %d hits — hit path under-tested", hits))
assert(misses > 20, string.format("RayOBB trial set produced only %d misses — miss path under-tested", misses))

-- ─── RayOBB hostile inputs (contract read from the module source) ────────
-- zero-length direction: every axis is "parallel"; origin inside the box
-- degenerates to t = 0, origin outside is a miss. Never errors.
do
	local boxCF = CF.new(0, 0, 0)
	local half = V3.new(1, 1, 1)
	local zero = V3.new(0, 0, 0)
	local tInside = WeaponMath.RayOBB(V3.new(0.5, 0.5, 0.5), zero, boxCF, half)
	assert(tInside == 0, "zero dir + origin inside box should return t=0, got " .. tostring(tInside))
	local tOutside = WeaponMath.RayOBB(V3.new(5, 0, 0), zero, boxCF, half)
	assert(tOutside == nil, "zero dir + origin outside box should miss, got " .. tostring(tOutside))
	for i = 1, 5 do
		local h = V3.new(range(0.5, 8), range(0.5, 8), range(0.5, 8))
		local cf = CF.new(range(-5, 5), range(-5, 5), range(-5, 5)) * CF.Angles(range(-0.5, 0.5), range(-0.5, 0.5), range(-0.5, 0.5))
		local inside = cf:PointToWorldSpace(V3.new(h.X * 0.4, h.Y * 0.4, h.Z * 0.4))
		local okIn, tIn = pcall(WeaponMath.RayOBB, inside, zero, cf, h)
		assert(okIn and tIn == 0, string.format("hostile trial %d: zero dir in-box should be t=0, got %s", i, tostring(tIn)))
		local outside = cf:PointToWorldSpace(V3.new(h.X * 4, 0, 0))
		local okOut, tOut = pcall(WeaponMath.RayOBB, outside, zero, cf, h)
		assert(okOut and tOut == nil, string.format("hostile trial %d: zero dir out-of-box should miss, got %s", i, tostring(tOut)))
	end
end

-- NaN origin: never errors; the result is nil or a finite number >= 0
-- (NaN slab bounds never win a comparison, so tmin/tmax stay finite or -inf,
-- and the module clamps with math.max(tmin, 0)). Pinned: an all-NaN origin
-- with a non-zero dir returns exactly 0.
do
	local boxCF = CF.new(1, 2, 3)
	local half = V3.new(1.5, 1.5, 1.5)
	local tNaN = WeaponMath.RayOBB(V3.new(NaN, NaN, NaN), V3.new(0, 0, -1), boxCF, half)
	assert(tNaN == 0, "all-NaN origin with non-zero dir should return t=0, got " .. tostring(tNaN))
	for i = 1, 30 do
		local h = V3.new(range(0.5, 8), range(0.5, 8), range(0.5, 8))
		local cf = CF.new(range(-5, 5), range(-5, 5), range(-5, 5)) * CF.Angles(range(-0.5, 0.5), range(-0.5, 0.5), range(-0.5, 0.5))
		local origin = V3.new(NaN, range(-20, 20), range(-20, 20))
		local dir = V3.new(range(-1, 1), range(-1, 1), range(-1, 1))
		local ok, res = pcall(WeaponMath.RayOBB, origin, dir, cf, h)
		assert(ok, string.format("NaN-origin trial %d errored: %s", i, tostring(res)))
		if res ~= nil then
			assert(type(res) == "number" and res == res and res >= 0, string.format(
				"NaN-origin trial %d returned non-finite/negative t: %s", i, tostring(res)
			))
		end
	end
end

-- ─── ApplySpread: seeded random trials ────────────────────────────────────
-- spread amounts in [0.05, 15] deg — generous over every configured weapon
-- spread (ConfigBase template + per-gun overrides stay well under 4 deg).
for i = 1, 150 do
	local x, y, z = rnd() * 2 - 1, rnd() * 2 - 1, rnd() * 2 - 1
	local l2 = x * x + y * y + z * z
	while l2 < 1e-4 do
		x, y, z = rnd() * 2 - 1, rnd() * 2 - 1, rnd() * 2 - 1
		l2 = x * x + y * y + z * z
	end
	local s = range(0.5, 3) / math.sqrt(l2)
	local dir = V3.new(x * s, y * s, z * s)
	local deg = range(0.05, 15)
	local out = WeaponMath.ApplySpread(dir, deg, rngStub())
	local ctx = string.format("trial %d: dir=(%.4f, %.4f, %.4f) deg=%.4f", i, dir.X, dir.Y, dir.Z, deg)
	assert(typeof(out) == "Vector3", "ApplySpread should return a Vector3 — " .. ctx)
	assert(
		math.abs(out.Magnitude - 1) <= 1e-6,
		string.format("ApplySpread output |v|=%.9f is not unit length — %s", out.Magnitude, ctx)
	)
	local cosA = (out.X * dir.X + out.Y * dir.Y + out.Z * dir.Z) / (out.Magnitude * dir.Magnitude)
	cosA = math.clamp(cosA, -1, 1)
	local angleDeg = math.deg(math.acos(cosA))
	assert(
		angleDeg <= deg + 1e-6,
		string.format("ApplySpread angle %.6f exceeds cone %.4f deg — %s", angleDeg, deg, ctx)
	)
end

-- deg <= 1e-4 short-circuits to dir.Unit (read from the source)
do
	local d = V3.new(0.3, 0.4, -0.5)
	for _, deg in { 0, 1e-4 } do
		local out = WeaponMath.ApplySpread(d, deg, rngStub())
		local u = d.Unit
		assert(
			math.abs(out.X - u.X) <= 1e-9 and math.abs(out.Y - u.Y) <= 1e-9 and math.abs(out.Z - u.Z) <= 1e-9,
			string.format("deg=%.6f should return dir.Unit exactly, got (%.9f, %.9f, %.9f)", deg, out.X, out.Y, out.Z)
		)
	end
end

-- NaN spread (hostile, contract pinned empirically today): no error; the
-- module has no validation, so the result is a non-finite Vector3.
do
	for i = 1, 10 do
		local ok, res = pcall(WeaponMath.ApplySpread, V3.new(0, 0, -1), NaN, rngStub())
		assert(ok, string.format("NaN spread trial %d errored: %s", i, tostring(res)))
		assert(typeof(res) == "Vector3", "NaN spread should still return a Vector3")
		assert(res.X ~= res.X and res.Y ~= res.Y and res.Z ~= res.Z, string.format(
			"NaN spread trial %d: expected the pinned non-finite result, got (%.6f, %.6f, %.6f)", i, res.X, res.Y, res.Z
		))
	end
end

print(string.format("weapon-math: %d RayOBB trials (%d hit / %d miss), 150 spread trials, hostile blocks OK", 200, hits, misses))
