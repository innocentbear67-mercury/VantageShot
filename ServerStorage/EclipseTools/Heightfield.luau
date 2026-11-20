--[[
	ECLIPSE — Heightfield (edit-time tool, never runs in game)
	The landscape as a function: H(x, z) -> surface height in studs, plus surface material.
	World axes: +X east, +Z north. Playable area about X[-480, 480], Z[-440, 420].
	  valley floor        y  0..12   (centre / south)
	  north plateaus      y  40      (z > 105), split by the canyon
	  canyon floor        y -230     (x around 0, z > 50), waterfall lip at z ~ 50
	  west shelf          y  30      Blue: Military Installation (x < -305)
	  east plateau        y  40      Red: Sanctum (x > 290)
	  south massif        y  ~240    Grand Chamber carved inside (z < -300)
	  outer mountain ring rises beyond the playable edge
	Build(i0, i1) writes terrain chunks (64 x 64 studs) with WriteVoxels.
]]

local Heightfield = {}

local abs, max, min, sqrt, sin, floor, ceil = math.abs, math.max, math.min, math.sqrt, math.sin, math.floor, math.ceil
-- math.noise mostly stays within about +-0.3; scale it so amplitudes below mean what they say (~+-1)
local function noise(a, b, c)
	return math.noise(a, b, c) * 2.4
end
local function clamp(v, a, b)
	return if v < a then a elseif v > b then b else v
end
-- smoothstep from a to b (works with a > b for falling edges)
local function ss(a, b, t)
	local u = clamp((t - a) / (b - a), 0, 1)
	return u * u * (3 - 2 * u)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function fbm(x, z, s, oct)
	local v, amp, f = 0, 1, 1
	for _ = 1, oct do
		v += noise(x * f / s, z * f / s, 17.3 * f) * amp
		amp *= 0.5
		f *= 2.03
	end
	return v
end
local function ridged(x, z, s)
	return clamp(1 - abs(noise(x / s, z / s, 5.1)) * 1.3, -1, 1)
end

Heightfield.WATER = -2 -- lake / river surface
Heightfield.GORGE_WATER = -224
Heightfield.LAKE = Vector2.new(-40, -120)

function Heightfield.CanyonCentre(z)
	return 8 * sin((z - 55) / 70)
end
function Heightfield.CanyonHalfWidth(z)
	return 46 + max(z - 55, 0) * 0.12
end

local function segDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local t = clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
	local qx, qz = ax + dx * t, az + dz * t
	return sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
end

-- natural access slopes from the valley onto the high ground (designed routes)
Heightfield.RAMPS = {
	-- { x, z, radius }  where the plateau / shelf edge relaxes into a walkable slope
	{ -175, 78, 46 }, -- west plateau ramp (Blue side to the bridge)
	{ 165, 74, 40 }, -- east plateau ramp (Red side to the bridge)
	{ -282, -24, 38 }, -- road up to the Installation shelf
	{ -250, 118, 34 }, -- shelf -> west plateau
}

local function rampFactor(x, z)
	local f = 0
	for _, r in Heightfield.RAMPS do
		local d = sqrt((x - r[1]) ^ 2 + (z - r[2]) ^ 2)
		f = max(f, ss(r[3], r[3] * 0.35, d))
	end
	return f
end

-- returns surface height and a region tag
function Heightfield.H(x, z)
	-- domain warp so no region boundary is a straight line
	local wx = x + noise(x / 210, z / 210, 11.1) * 20 + noise(x / 60, z / 60, 12.2) * 5
	local wz = z + noise(x / 210, z / 210, 13.3) * 20 + noise(x / 60, z / 60, 14.4) * 5
	local ramp = rampFactor(x, z)
	-- valley floor: rolling hills, a rocky spine in the mid field, small gullies
	local h = 6 + fbm(wx, wz, 120, 4) * 4.5
	local spine = ss(70, 0, abs((wx - 60) * 0.55 + (wz + 30) * 0.84) + noise(wx / 40, wz / 40, 2.5) * 25)
	h += spine * (10 + ridged(wx, wz, 45) * 8) * ss(-260, -120, wz) * (1 - ss(-10, 40, wz))
	h -= ss(0.5, 0.1, abs(noise(wx / 70, wz / 70, 7.7))) * 3 -- dry gullies
	local tag = "valley"
	-- north plateaus: broken cliff edge, relaxed into ramps where the routes need them
	local edgeW = lerp(26, 120, ramp)
	local north = ss(60 - edgeW * 0.3, 60 + edgeW, wz)
	if north > 0 then
		local top = 40 + fbm(wx, wz, 70, 3) * 1.6
		-- terraced cliff face
		local terr = floor(north * 4) / 4
		local face = lerp(north, terr, 0.35 * (1 - ramp))
		h = lerp(h, top, face)
		if north > 0.5 then
			tag = "plateau"
		end
	end
	-- west shelf (Blue installation)
	local westEdge = lerp(22, 90, ramp)
	local west = ss(-262, -262 - westEdge, wx) * ss(-215, -175, wz) * (1 - ss(85, 125, wz))
	if west > 0 then
		h = lerp(h, 30 + noise(x / 40, z / 40, 1.1) * 0.8, west)
		if west > 0.5 then
			tag = "westshelf"
		end
	end
	-- east plateau (Red sanctum) behind a steep escarpment
	local east = ss(228, 268, wx) * ss(-268, -232, wz)
	if east > 0 then
		local terr = floor(east * 3) / 3
		h = lerp(h, 40 + fbm(wx, wz, 60, 2) * 1.5, lerp(east, terr, 0.4))
		if east > 0.5 then
			tag = "eastplateau"
		end
	end
	-- south massif housing the Grand Chamber: rugged peaks and buttresses
	local south = ss(-284, -332, wz)
	if south > 0 then
		local peak = 215 + fbm(wx, wz, 190, 3) * 38 + ridged(wx, wz, 120) * 42 + ridged(wx, wz, 48) * 7
		peak = lerp(peak, floor(peak / 16) * 16, 0.3) -- strata ledges
		h = max(h, lerp(h, peak, south))
		if south > 0.5 then
			tag = "massif"
		end
	end
	-- solid rock mass over the Grand Chamber (keeps a roof above the 152-stud ceiling)
	local cov = ss(180, 150, abs(x)) * ss(-296, -326, z) * (1 - ss(-540, -575, z))
	if cov > 0 then
		h = max(h, lerp(h, 218 + ridged(wx, wz, 110) * 16 + fbm(wx, wz, 140, 2) * 8, cov))
	end
	-- outer mountain ring
	local dx = max(abs(wx) - 465, 0)
	local dzn = max(wz - 410, 0)
	-- (noise only roughens the edge where we are already outside the playable rectangle)
	local base = sqrt(dx * dx + dzn * dzn)
	local d = if base > 0 then base + noise(x / 70, z / 70, 9.9) * 30 else -1
	if d > 0 then
		local mm = ss(0, 170, d)
		local peak = 310 + fbm(wx, wz, 280, 3) * 85 + ridged(wx, wz, 170) * 75 + ridged(wx, wz, 62) * 12
		peak = lerp(peak, floor(peak / 20) * 20, 0.3) -- strata ledges
		h = max(h, lerp(h, peak, mm))
		if mm > 0.4 then
			tag = "mountain"
		end
	end
	-- canyon (uses the unwarped z so the bridge position is exact)
	if z > 30 then
		local cx = Heightfield.CanyonCentre(z)
		local hw = Heightfield.CanyonHalfWidth(z) + noise(z / 30, 0, 1.7) * 7
		local dist = abs(x - cx)
		local inside = ss(hw + 4, hw - 18, dist) * ss(36, 56, z)
		if inside > 0 then
			local floorH = -230 + noise(x / 20, z / 20, 4.2) * 4
			-- broken, terraced walls
			local t = lerp(inside, floor(inside * 6) / 6, 0.45)
			h = lerp(h, floorH, t)
			if inside > 0.3 then
				tag = "canyon"
			end
		end
	end
	-- lake basin (bigger, irregular shoreline)
	local L = Heightfield.LAKE
	local ldx, ldz = (x - L.X) / 108, (z - L.Y) / 76
	local ld = sqrt(ldx * ldx + ldz * ldz) + noise(x / 45, z / 45, 3.9) * 0.22 + noise(x / 15, z / 15, 4.9) * 0.05
	if ld < 1.2 then
		local bed = lerp(-16, h, ss(0.4, 1.15, ld))
		h = min(h, bed)
		if ld < 1 then
			tag = "lake"
		end
	end
	-- river from the lake to the waterfall lip
	local rd = segDist(x, z, -28, -70, -10, 0)
	rd = min(rd, segDist(x, z, -10, 0, Heightfield.CanyonCentre(48), 48))
	rd += noise(x / 18, z / 18, 6.1) * 3
	if rd < 20 and z > -90 and z < 56 then
		h = min(h, lerp(-6, h, ss(8, 20, rd)))
		if rd < 10 then
			tag = "river"
		end
	end
	return h, tag
end

local M = Enum.Material
function Heightfield.Surface(h, slope, tag)
	if tag == "lake" or tag == "river" then
		return if h < -9 then M.Mud else M.Sand
	end
	if tag == "canyon" then
		return if slope > 0.8 then M.Basalt else M.Rock
	end
	if h > 300 then
		return if slope > 1.2 then M.Rock else M.Snow
	end
	if slope > 1.1 then
		return if tag == "mountain" or tag == "massif" then M.Slate else M.Rock
	end
	if slope > 0.55 then
		return M.Ground
	end
	if tag == "westshelf" or tag == "eastplateau" then
		return M.Ground
	end
	return M.Grass
end

-- chunk grid covering the world (64-stud chunks)
Heightfield.X0, Heightfield.X1 = -896, 896
Heightfield.Z0, Heightfield.Z1 = -832, 896
Heightfield.CHUNK = 64
function Heightfield.ChunkCount()
	local nx = (Heightfield.X1 - Heightfield.X0) / Heightfield.CHUNK
	local nz = (Heightfield.Z1 - Heightfield.Z0) / Heightfield.CHUNK
	return nx * nz, nx, nz
end

-- the playable core keeps solid rock down to this depth (room for tunnels)
local DEEP = -96
local function inCore(x, z)
	return x > -480 and x < 480 and z > -640 and z < 300 -- covers the chamber, bridge tunnels and bunkers
end

function Heightfield.Build(i0, i1)
	local terrain = workspace.Terrain
	local total, nx = Heightfield.ChunkCount()
	local R, C = 4, Heightfield.CHUNK
	local n = C / R
	local written = 0
	for idx = i0, math.min(i1, total - 1) do
		local cx, cz = idx % nx, idx // nx
		local x0, z0 = Heightfield.X0 + cx * C, Heightfield.Z0 + cz * C
		-- heights on a (n+2)^2 grid (one-cell border for slopes / neighbour minima)
		local hs, tags = {}, {}
		for i = 0, n + 1 do
			hs[i], tags[i] = {}, {}
			for k = 0, n + 1 do
				local wx, wz = x0 + (i - 0.5) * R, z0 + (k - 0.5) * R
				hs[i][k], tags[i][k] = Heightfield.H(wx, wz)
			end
		end
		local ylo, yhi = math.huge, -math.huge
		local lows = {}
		for i = 1, n do
			lows[i] = {}
			for k = 1, n do
				local h = hs[i][k]
				local nmin = min(h, hs[i - 1][k], hs[i + 1][k], hs[i][k - 1], hs[i][k + 1])
				local wx, wz = x0 + (i - 0.5) * R, z0 + (k - 0.5) * R
				local low = nmin - 16
				if inCore(wx, wz) then
					low = min(low, DEEP)
				end
				lows[i][k] = low
				ylo = min(ylo, low)
				yhi = max(yhi, h, Heightfield.WATER)
			end
		end
		ylo = floor(ylo / R) * R
		yhi = ceil((yhi + R) / R) * R
		local ny = (yhi - ylo) / R
		local mats, occ = {}, {}
		for i = 1, n do
			mats[i], occ[i] = {}, {}
			local wx = x0 + (i - 0.5) * R
			for j = 1, ny do
				mats[i][j], occ[i][j] = {}, {}
			end
			for k = 1, n do
				local wz = z0 + (k - 0.5) * R
				local h, tag = hs[i][k], tags[i][k]
				local slope = max(abs(hs[i + 1][k] - hs[i - 1][k]), abs(hs[i][k + 1] - hs[i][k - 1])) / (2 * R)
				local surf = Heightfield.Surface(h, slope, tag)
				local low = lows[i][k]
				local water = if tag == "lake" or tag == "river" then Heightfield.WATER
					elseif tag == "canyon" then Heightfield.GORGE_WATER
					else nil
				for j = 1, ny do
					local yb = ylo + (j - 1) * R -- cell bottom
					local mat, o = M.Air, 0
					if yb + R <= h and yb >= low then
						mat, o = (if h - yb < 8 then surf else M.Rock), 1
					elseif yb < h and yb >= low then
						mat, o = surf, clamp((h - yb) / R, 0.05, 1)
					elseif water and yb < water and yb >= h - R then
						mat, o = M.Water, 1
					end
					mats[i][j][k] = mat
					occ[i][j][k] = o
				end
			end
		end
		local region = Region3.new(Vector3.new(x0, ylo, z0), Vector3.new(x0 + C, yhi, z0 + C))
		terrain:WriteVoxels(region, R, mats, occ)
		written += 1
		task.wait()
	end
	return written
end

return Heightfield
