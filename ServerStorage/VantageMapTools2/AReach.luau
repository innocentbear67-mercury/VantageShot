-- AReach: 2.5D walk-reachability survey (2026-11-19). Cells of size c; each cell has up to 5 standable
-- levels (top faces with >=5.5 headroom). Neighbours connect when |dh| <= step. Jump pads link to targets.
local R = {}
local V = Vector3.new
function R.survey(map, O, b, opts)
	opts = opts or {}
	local c = opts.cell or 3
	local step = opts.step or 2.6
	local ceil = opts.ceil or 170
	local par = map.Parent
	if par ~= workspace then map.Parent = workspace end
	local excl = {}
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and (not d.CanCollide or d.Name:find("SpawnShield") or d.Name == "JumpPad") then table.insert(excl, d) end
	end
	local G = map:FindFirstChild("Gameplay") if G then table.insert(excl, G) end
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = excl
	local nx = math.floor((b[2] - b[1]) / c) local nz = math.floor((b[4] - b[3]) / c)
	local cells = {} -- [ix][iz] = { {y=}, ... }
	for ix = 0, nx - 1 do
		cells[ix] = {}
		for iz = 0, nz - 1 do
			local x, z = b[1] + (ix + 0.5) * c, b[3] + (iz + 0.5) * c
			local lv = {}
			local top = O.Y + ceil
			for k = 1, 6 do
				local h = workspace:Raycast(O + V(x, top - O.Y, z), V(0, -(top - (O.Y - 40)), 0), rp)
				if not h then break end
				local y = h.Position.Y
				if h.Normal.Y > 0.64 then
					local up = workspace:Raycast(h.Position + V(0, 0.2, 0), V(0, 5.5, 0), rp)
					if not up then table.insert(lv, { y = y - O.Y }) end
				end
				-- continue below this part
				local inst = h.Instance
				local bot = y - 0.3
				if inst:IsA("BasePart") then
					local cf, s = inst.CFrame, inst.Size
					local ey = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
					bot = math.min(bot, inst.Position.Y - ey / 2 - 0.1)
				end
				top = bot
				if top < O.Y - 30 then break end
			end
			cells[ix][iz] = lv
		end
		if ix % 8 == 0 then task.wait() end
	end
	-- flood from seeds
	local seen = {}
	local function key(ix, iz, l) return ix * 100000 + iz * 10 + l end
	local q = {}
	local function seed(p)
		local ix, iz = math.floor((p.X - O.X - b[1]) / c), math.floor((p.Z - O.Z - b[3]) / c)
		local col = cells[ix] and cells[ix][iz]
		if not col then return end
		local best, bd = nil, 1e9
		for l, v in ipairs(col) do local d = math.abs(v.y - (p.Y - O.Y)) if d < bd then best, bd = l, d end end
		if best and bd < 6 then local k = key(ix, iz, best) if not seen[k] then seen[k] = true table.insert(q, { ix, iz, best }) end end
	end
	for _, p in ipairs(opts.seeds or {}) do seed(p) end
	local pads = {}
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "JumpPad" and typeof(d:GetAttribute("PadTarget")) == "Vector3" then
			table.insert(pads, { d.Position, d:GetAttribute("PadTarget") })
		end
	end
	local head = 1
	while head <= #q do
		local cur = q[head] head += 1
		local ix, iz, l = cur[1], cur[2], cur[3]
		local y = cells[ix][iz][l].y
		for _, dd in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local jx, jz = ix + dd[1], iz + dd[2]
			local col = cells[jx] and cells[jx][jz]
			if col then
				for m, v in ipairs(col) do
					if math.abs(v.y - y) <= step then
						local k = key(jx, jz, m)
						if not seen[k] then seen[k] = true table.insert(q, { jx, jz, m }) end
					end
				end
			end
		end
		-- jump pad: standing cell near a pad -> its target
		local wx, wz = O.X + b[1] + (ix + 0.5) * c, O.Z + b[3] + (iz + 0.5) * c
		for _, pd in ipairs(pads) do
			if math.abs(pd[1].X - wx) < 4 and math.abs(pd[1].Z - wz) < 4 and math.abs(pd[1].Y - (O.Y + y)) < 4 then
				local before = #q seed(pd[2]) 
			end
		end
	end
	-- tally
	local bands = { { 0, 3 }, { 3, 8 }, { 8, 16 }, { 16, 999 } }
	local reach, total = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
	local unreachMid = {}
	for ix = 0, nx - 1 do for iz = 0, nz - 1 do
		for l, v in ipairs(cells[ix][iz]) do
			for bi, bd in ipairs(bands) do
				if v.y >= bd[1] - 0.5 and v.y < bd[2] then
					total[bi] += 1
					if seen[key(ix, iz, l)] then reach[bi] += 1 elseif bi >= 2 then table.insert(unreachMid, { b[1] + (ix + 0.5) * c, v.y, b[3] + (iz + 0.5) * c }) end
				end
			end
		end
	end end
	map.Parent = par
	local a = c * c
	local s = ("ground %d/%d  low3-8 %d/%d  mid8-16 %d/%d  high16+ %d/%d (reachable/total studs^2)"):format(reach[1] * a, total[1] * a, reach[2] * a, total[2] * a, reach[3] * a, total[3] * a, reach[4] * a, total[4] * a)
	return s, { cells = cells, seen = seen, key = key, c = c, unreach = unreachMid, reach = reach, total = total }
end
return R
