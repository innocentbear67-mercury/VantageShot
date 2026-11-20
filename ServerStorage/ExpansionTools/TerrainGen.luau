-- TerrainGen: the VANTAGE battlefield landscape as one height function + chunked voxel writer.
-- Playable: |x| <= 625, |z| <= 500 (1250 x 1000, 6v6). Scenery world out to about +-2600 x +-2200.
-- The core basin rectangle is never written (core, ring road, underground keep their terrain).
local G = {}
G.PX, G.PZ = 495, 450
G.CORE = { -500, 500, -456, 456 } -- the whole arena (its floor is written by G.arenaFloor)
G.CHASM = { -470, 470, 418, 838 }
-- mesas inside the playable area: x, z, radius, height
G.MESAS = { { -560, -425, 40, 26 }, { 562, 415, 45, 28 }, { -565, 418, 36, 22 } }
local N = math.noise
local function sm(t) t = math.clamp(t, 0, 1) return t * t * (3 - 2 * t) end
function G.riverZ(x) return -404 + 12 * math.sin(x / 190) end
local function outsideRect(x, z, r)
	local dx = math.max(r[1] - x, 0, x - r[2]); local dz = math.max(r[3] - z, 0, z - r[4])
	return math.sqrt(dx * dx + dz * dz)
end

function G.height(x, z)
	local base = 3 + 4 * N(x / 380 + 11.3, z / 380 + 3.7) + 2 * N(x / 130 + 5.1, z / 130 + 9.9)
	local h, tag = base, "plain"
	local P = { -G.PX, G.PX, -G.PZ, G.PZ }
	local dOut = outsideRect(x, z, P)
	if dOut <= 0 then
		if x < -490 then
			-- WEST proving grounds: rolling swells for hull-down tank play
			local w = sm((-490 - x) / 50)
			h = base + w * (7 * N(x / 160 + 31.7, z / 160 + 17.2) + 2.5 * N(x / 55 + 2.2, z / 55 + 7.4))
			tag = "west"
		elseif x > 490 then
			-- EAST quarry terraces: 0 / 18 / 36 with ramp corridors, stepped pit
			local function level(x2, z2)
				local ramp = (z2 > -330 and z2 < -250) or (z2 > -40 and z2 < 40) or (z2 > 250 and z2 < 330)
				if ramp then return 18 * math.clamp((x2 - 515) / 100, 0, 1) end
				return 18 * sm((x2 - 560) / 10)
			end
			local w = sm((x - 490) / 40)
			h = base * (1 - 0.6 * w) + w * level(x, z)
			local dx, dz = x - 585, z + 160
			local r = math.sqrt(dx * dx + dz * dz)
			if r < 62 then
				local depth
				if math.abs(dz) < 16 and dx < 0 then depth = 20 * math.clamp((62 - r) / 50, 0, 1)
				else depth = 10 * math.ceil(math.clamp((62 - r) / 22, 0, 2)) end
				h -= depth
			end
			tag = "east"
		end
		if z < -335 then
			-- NORTH: river valley with banks, low hills to the north edge
			local zr = G.riverZ(x)
			local dr = math.abs(z - zr)
			h -= 11 * sm(1 - dr / 58)
			if dr < 18 then h = math.min(h, -9 + dr * 0.04) end
			h += 14 * sm((zr - 34 - z) / 40) * (0.7 + 0.3 * N(x / 150 + 4.4, z / 150 + 1.1))
			if tag == "plain" then tag = "north" end
		elseif z > 335 then
			h += 10 * sm((z - 335) / 90)
			if tag == "plain" then tag = "south" end
		end
		for _, ms in G.MESAS do
			local d = math.sqrt((x - ms[1]) ^ 2 + (z - ms[2]) ^ 2)
			if d < ms[3] + 40 then
				h = math.max(h, (ms[4] + 1.5 * N(x / 30, z / 30)) * sm((ms[3] + 40 - d) / 40))
				if d < ms[3] + 12 then tag = "mesa" end
			end
		end
	else
		-- SCENERY: a low rise just past the boundary, then mountains; an east-west valley
		-- (|z| small) keeps the aircraft approach low and open
		local corridor = sm((math.abs(z) - 260) / 420)
		h = base + 30 * sm(dOut / 160) + 8 * N(x / 90, z / 90) * sm(dOut / 120)
		local function ridged(f, ox, oz) local v = 1 - math.abs(N(x / f + ox, z / f + oz)); return v * v end
		local r = 0.55 * ridged(520, 2.2, 6.6) + 0.30 * ridged(230, 8.1, 3.3) + 0.15 * ridged(95, 5.5, 9.1)
		local reach = sm((dOut - 200) / 900)
		local mtn = reach * (90 + 470 * r * r) + 40 * reach * N(x / 60 + 1.7, z / 60 + 4.9)
		h += mtn * (0.18 + 0.82 * corridor)
		tag = "rim"
	end
	-- flat apron around the core basin
	local dc = outsideRect(x, z, G.CORE)
	if dc < 150 then h = 0.2 + (h - 0.2) * sm((dc - 30) / 120) end
	if x > G.CHASM[1] and x < G.CHASM[2] and z > G.CHASM[3] and z < G.CHASM[4] then h, tag = -142, "chasm" end
	return h, tag
end

local M = Enum.Material
function G.material(x, z, h, tag, slope)
	if h > 300 + 40 * N(x / 80, z / 80) then return M.Snow end
	if slope > 1.0 then return M.Rock end
	if slope > 0.55 then return tag == "east" and M.Slate or M.Rock end
	if tag == "east" then return N(x / 60, z / 60) > 0.1 and M.Limestone or M.Slate end
	if tag == "rim" then if h > 150 then return M.Rock end; return N(x / 260, z / 260) > -0.1 and M.Grass or M.Ground end
	if tag == "mesa" then return slope > 0.35 and M.Rock or M.Ground end
	if tag == "north" and h < -2 then return M.Mud end
	local n = 0.75 * N(x / 260 + 1.5, z / 260 + 7.5) + 0.25 * N(x / 45 + 3.1, z / 45 + 2.4)
	if n > -0.12 then return M.Grass elseif n < -0.42 then return M.Mud end
	return M.Ground
end

local T = workspace.Terrain
local CH = 256
local function inRect(x, z, r) return x > r[1] and x < r[2] and z > r[3] and z < r[4] end
function G.chunk(cx, cz)
	local n = CH / 4
	local H = table.create(n + 2)
	local hmin, hmax = math.huge, -math.huge
	for i = 0, n + 1 do
		H[i] = {}
		for j = 0, n + 1 do
			local h = G.height(cx + (i - 0.5) * 4, cz + (j - 0.5) * 4)
			H[i][j] = h
			if i >= 1 and i <= n and j >= 1 and j <= n then hmin = math.min(hmin, h); hmax = math.max(hmax, h) end
		end
	end
	local touchesCore = not (cx + CH <= G.CORE[1] or cx >= G.CORE[2] or cz + CH <= G.CORE[3] or cz >= G.CORE[4])
	local lo = math.floor((hmin - 8) / 4) * 4
	local hi = math.ceil((math.max(hmax, -3) + 4) / 4) * 4
	if touchesCore then lo = math.min(lo, -48); hi = math.max(hi, 420) end
	local region = Region3.new(Vector3.new(cx, lo, cz), Vector3.new(cx + CH, hi, cz + CH))
	local ny = (hi - lo) / 4
	local mats, occ
	if touchesCore then
		mats, occ = T:ReadVoxels(region, 4)
	else
		T:FillBlock(CFrame.new(cx + CH / 2, (hi + 640) / 2, cz + CH / 2), Vector3.new(CH, 640 - hi, CH), M.Air)
		T:FillBlock(CFrame.new(cx + CH / 2, (lo - 170) / 2, cz + CH / 2), Vector3.new(CH, lo + 170, CH), M.Rock)
		mats, occ = {}, {}
		for i = 1, n do mats[i], occ[i] = {}, {} for k = 1, ny do mats[i][k], occ[i][k] = {}, {} end end
	end
	for i = 1, n do
		for j = 1, n do
			local x, z = cx + (i - 0.5) * 4, cz + (j - 0.5) * 4
			if not (touchesCore and inRect(x, z, G.CORE)) then
				local h = H[i][j]
				local _, tag = G.height(x, z)
				local slope = math.max(math.abs(H[i + 1][j] - H[i - 1][j]), math.abs(H[i][j + 1] - H[i][j - 1])) / 8
				local mat = G.material(x, z, h, tag, slope)
				local wet = tag ~= "chasm" and z < -335 and z > -500 and h < -3
				for k = 1, ny do
					local y0 = lo + (k - 1) * 4
					local o = math.clamp((h - y0) / 4, 0, 1)
					if o > 0 then mats[i][k][j] = mat; occ[i][k][j] = o
					elseif wet and y0 < -3 then mats[i][k][j] = M.Water; occ[i][k][j] = math.clamp((-3 - y0) / 4, 0, 1)
					else mats[i][k][j] = M.Air; occ[i][k][j] = 0 end
				end
			end
		end
	end
	T:WriteVoxels(region, 4, mats, occ)
	return hmin, hmax
end
function G.chunks()
	local list = {}
	for cz = -2304, 2048, CH do for cx = -2560, 2304, CH do table.insert(list, { cx, cz }) end end
	return list
end
-- flat arena floor (surface ~1.7, just under the floor tiles at 2), with the underground and chasm left open
G.UNDERGROUND = { -198, 170, 230, 390 }
function G.arenaFloor()
	local T = workspace.Terrain
	local M = Enum.Material
	for x0 = -500, 499, 200 do
		for z0 = -456, 455, 228 do
			local x1, z1 = math.min(x0 + 200, 500), math.min(z0 + 228, 456)
			local region = Region3.new(Vector3.new(x0, -40, z0), Vector3.new(x1, 8, z1))
			local nx, nz, ny = (x1 - x0) / 4, (z1 - z0) / 4, 12
			local mats, occ = {}, {}
			for i = 1, nx do
				mats[i], occ[i] = {}, {}
				for k = 1, ny do mats[i][k], occ[i][k] = {}, {} end
				for j = 1, nz do
					local x, z = x0 + (i - 0.5) * 4, z0 + (j - 0.5) * 4
					local open = (x > G.CHASM[1] and x < G.CHASM[2] and z > G.CHASM[3])
						or (x > G.UNDERGROUND[1] and x < G.UNDERGROUND[2] and z > G.UNDERGROUND[3] and z < G.UNDERGROUND[4])
					for k = 1, ny do
						local y0 = -40 + (k - 1) * 4
						local o = open and 0 or math.clamp((-0.3 - y0) / 4, 0, 1)
						mats[i][k][j] = o > 0 and M.Concrete or M.Air
						occ[i][k][j] = o
					end
				end
			end
			T:WriteVoxels(region, 4, mats, occ)
			-- clear anything left above the floor (old mesas, terraces, river banks)
			if true then
				local open = false
				T:FillBlock(CFrame.new((x0 + x1) / 2, 8 + 300, (z0 + z1) / 2), Vector3.new(x1 - x0, 600, z1 - z0), M.Air)
			end
			task.wait()
		end
	end
	-- the chasm and the underground cavity below the floor band
	T:FillBlock(CFrame.new(0, -95, (G.CHASM[3] + 456) / 2), Vector3.new(G.CHASM[2] - G.CHASM[1], 110, 456 - G.CHASM[3]), M.Air)
	T:FillBlock(CFrame.new((G.UNDERGROUND[1] + G.UNDERGROUND[2]) / 2, -36, (G.UNDERGROUND[3] + G.UNDERGROUND[4]) / 2), Vector3.new(G.UNDERGROUND[2] - G.UNDERGROUND[1], 12, G.UNDERGROUND[4] - G.UNDERGROUND[3]), M.Air)
end
return G
