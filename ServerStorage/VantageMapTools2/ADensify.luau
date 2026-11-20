-- ADensify: greedy placement of accent cover blocks on the cells crossed by the most long ground sightlines.
local A = {}
local V = Vector3.new
function A.run(o)
	local map, O, b, sym = o.map, o.O, o.box, o.sym
	local cell = o.cell or 4
	local folderB = o.folderB local folderR = o.folderR
	local excl = {}
	for _, d in ipairs(map:GetDescendants()) do if d:IsA("BasePart") and (d.Name:find("SpawnShield") or d.Transparency > 0.9) then table.insert(excl, d) end end
	table.insert(excl, map.Gameplay)
	local los = RaycastParams.new() los.FilterType = Enum.RaycastFilterType.Exclude los.FilterDescendantsInstances = excl los.RespectCanCollide = true
	local nx = math.floor((b[2] - b[1]) / cell) local nz = math.floor((b[4] - b[3]) / cell)
	-- floor height grid
	local H, flat = {}, {}
	for i = 0, nx - 1 do H[i] = {} flat[i] = {} for j = 0, nz - 1 do
		local x, z = b[1] + (i + 0.5) * cell, b[3] + (j + 0.5) * cell
		local r = workspace:Raycast(O + V(x, 200, z), V(0, -260, 0), los)
		H[i][j] = r and (r.Position.Y - O.Y) or -999
		flat[i][j] = r and r.Normal.Y > 0.99 and r.Instance.Size.X * r.Instance.Size.Z > 600 or false
	end task.wait() end
	-- ground sample points
	local rng = Random.new(o.seed or 5) local pts = {}
	local tries = 0
	while #pts < (o.points or 600) and tries < 30000 do
		tries += 1
		local i, j = rng:NextInteger(1, nx - 2), rng:NextInteger(1, nz - 2)
		if flat[i][j] and H[i][j] > -50 and H[i][j] < (o.maxFloor or 22) then
			table.insert(pts, V(b[1] + (i + 0.5) * cell, H[i][j] + 4.5, b[3] + (j + 0.5) * cell))
		end
	end
	-- long visible lines -> cell crossings below cover height
	local hb = o.h or 8
	local counts, lines = {}, {}
	local function key(i, j) return i * 10000 + j end
	for a = 1, #pts do for c = a + 1, #pts, 2 do
		local p, q = pts[a], pts[c]
		local d = (q - p).Magnitude
		if d > (o.minLen or 50) and not workspace:Raycast(O + p, q - p, los) then
			local cellsHit = {}
			local steps = math.ceil(d / (cell * 0.5))
			for k = 1, steps - 1 do
				local t = k / steps
				local pt = p:Lerp(q, t)
				local i, j = math.floor((pt.X - b[1]) / cell), math.floor((pt.Z - b[3]) / cell)
				if i >= 0 and i < nx and j >= 0 and j < nz and H[i][j] > -50 and pt.Y > H[i][j] and pt.Y < H[i][j] + hb then
					cellsHit[key(i, j)] = true
				end
			end
			local L = { cells = cellsHit, alive = true, w = d / 50 }
			table.insert(lines, L)
			for k in pairs(cellsHit) do counts[k] = (counts[k] or 0) + L.w end
		end
	end if a % 40 == 0 then task.wait() end end
	local nLines = #lines
	-- forbidden zones
	local function forbidden(x, z)
		for _, f in ipairs(o.forbid or {}) do
			if x > f[1] and x < f[2] and z > f[3] and z < f[4] then return true end
			if sym == "mirror" and x > f[1] and x < f[2] and -z > f[3] and -z < f[4] then return true end
			if sym == "rotate" and -x > f[1] and -x < f[2] and -z > f[3] and -z < f[4] then return true end
		end
		return false
	end
	local ov = OverlapParams.new() ov.FilterType = Enum.RaycastFilterType.Exclude ov.FilterDescendantsInstances = excl
	local sizes = o.sizes or { { 8, 8, 8 }, { 12, 6, 6 }, { 6, 12, 6 }, { 8, 8, 12 } }
	local placed = {}
	local function fits(x, z, w, d, h, y)
		if forbidden(x, z) then return false end
		local clr = o.clear or 7
		local cf = CFrame.new(O + V(x, y + 0.5 + (h + 6) / 2, z))
		local parts = workspace:GetPartBoundsInBox(cf, V(w + clr * 2, h + 6, d + clr * 2), ov)
		for _, p in ipairs(parts) do if p:IsDescendantOf(map) then return false end end
		-- footprint must be flat at one level
		for _, dx in ipairs({ -w / 2, 0, w / 2 }) do for _, dz in ipairs({ -d / 2, 0, d / 2 }) do
			local i, j = math.floor((x + dx - b[1]) / cell), math.floor((z + dz - b[3]) / cell)
			if i < 0 or i >= nx or j < 0 or j >= nz or math.abs(H[i][j] - y) > 0.3 or not flat[i][j] then return false end
		end end
		return true
	end
	local function twin(x, z) if sym == "mirror" then return x, -z end return -x, -z end
	for iter = 1, (o.attempts or 500) do
		if #placed >= (o.count or 12) then break end
		local best, bs = nil, 0
		for k, c in pairs(counts) do
			if c > bs then
				local i, j = k // 10000, k % 10000
				local z = b[3] + (j + 0.5) * cell
				if (z < -(o.midGap or 8)) then best, bs = k, c end
			end
		end
		if not best then break end
		local i, j = best // 10000, best % 10000
		local x, z = b[1] + (i + 0.5) * cell, b[3] + (j + 0.5) * cell
		local y = H[i][j]
		local done = false
		for _, sz in ipairs(sizes) do
			for _, off in ipairs({ { 0, 0 }, { cell, 0 }, { -cell, 0 }, { 0, cell }, { 0, -cell } }) do
				local cx, cz = x + off[1], z + off[2]
				local tx, tz = twin(cx, cz)
				if fits(cx, cz, sz[1], sz[3], sz[2], y) and fits(tx, tz, sz[1], sz[3], sz[2], y) then
					table.insert(placed, { cx, cz, sz, y })
					o.make(folderB, cx, cz, y, sz)
					o.make(folderR, tx, tz, y, sz, true)
					-- kill lines through this block
					local i0, i1 = math.floor((cx - sz[1] / 2 - b[1]) / cell), math.floor((cx + sz[1] / 2 - b[1]) / cell)
					local j0, j1 = math.floor((cz - sz[3] / 2 - b[3]) / cell), math.floor((cz + sz[3] / 2 - b[3]) / cell)
					local ti0, ti1 = math.floor((tx - sz[1] / 2 - b[1]) / cell), math.floor((tx + sz[1] / 2 - b[1]) / cell)
					local tj0, tj1 = math.floor((tz - sz[3] / 2 - b[3]) / cell), math.floor((tz + sz[3] / 2 - b[3]) / cell)
					for _, L in ipairs(lines) do
						if L.alive then
							local hit = false
							for ii = i0, i1 do for jj = j0, j1 do if L.cells[key(ii, jj)] then hit = true end end end
							for ii = ti0, ti1 do for jj = tj0, tj1 do if L.cells[key(ii, jj)] then hit = true end end end
							if hit then L.alive = false for k2 in pairs(L.cells) do counts[k2] = (counts[k2] or 0) - L.w end end
						end
					end
					done = true break
				end
			end
			if done then break end
		end
		if not done then counts[best] = 0 end
		if iter % 3 == 0 then task.wait() end
	end
	local alive = 0 for _, L in ipairs(lines) do if L.alive then alive += 1 end end
	return #placed, nLines, alive
end
return A
