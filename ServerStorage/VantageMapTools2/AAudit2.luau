local Au = {}
local V = Vector3.new
function Au.run(map, O, box, sym, opts)
	opts = opts or {}
	local out = {}
	local x0, x1, z0, z1 = box[1], box[2], box[3], box[4]
	local geoRoots = {}
	for _, c in ipairs(map:GetChildren()) do if c.Name ~= "Gameplay" and c.Name ~= "Systems" then table.insert(geoRoots, c) end end
	local inc = RaycastParams.new() inc.FilterType = Enum.RaycastFilterType.Include inc.FilterDescendantsInstances = geoRoots
	local ceilY = opts.ceil or 168
	-- holes
	local holes, hs = 0, {}
	for x = x0 + 0.5, x1 - 0.5, 1 do
		for z = z0 + 0.5, z1 - 0.5, 1 do
			local r = workspace:Raycast(O + V(x, ceilY - 2, z), V(0, -(ceilY + 30), 0), inc)
			if not r or r.Position.Y - O.Y < (opts.minY or -18) then holes += 1 if #hs < 6 then table.insert(hs, ("%.0f,%.0f"):format(x, z)) end end
		end
		if math.floor(x) % 20 == 0 then task.wait() end
	end
	table.insert(out, ("holes=%d %s"):format(holes, table.concat(hs, " ")))
	-- slits (gaps 0.5..3 studs wide at walkable level where a player could wedge)
	local slits, ss = 0, {}
	local hz = RaycastParams.new() hz.FilterType = Enum.RaycastFilterType.Include hz.FilterDescendantsInstances = geoRoots
	for x = x0 + 1, x1 - 1, 1 do
		for z = z0 + 1, z1 - 1, 1 do
			local f = workspace:Raycast(O + V(x, ceilY - 2, z), V(0, -(ceilY + 30), 0), inc)
			if f and f.Normal.Y > 0.7 then
				local p = f.Position + V(0, 2.5, 0)
				local function gap(dir)
					local a = workspace:Raycast(p, dir * 3, hz) local b = workspace:Raycast(p, -dir * 3, hz)
					if a and b then return (a.Position - b.Position).Magnitude end
				end
				local gx, gz = gap(V(1, 0, 0)), gap(V(0, 0, 1))
				local g = (gx and gz) and math.min(gx, gz) or gx or gz
				if g and g > 0.3 and g < 3.0 then
					-- is it enclosed below head height? check upward clearance and depth
					slits += 1 if #ss < 10 then table.insert(ss, ("%.0f,%.0f,%.0f(%s %.1f)"):format(x, f.Position.Y - O.Y, z, f.Instance.Name, g)) end
				end
			end
		end
		if math.floor(x) % 10 == 0 then task.wait() end
	end
	table.insert(out, ("slits=%d %s"):format(slits, table.concat(ss, " ")))
	-- grapple
	local rng = Random.new(3) local bad, n = {}, 0
	local function grapple(from, dir)
		local ex = {}
		for i = 1, 14 do
			local p = RaycastParams.new() p.FilterType = Enum.RaycastFilterType.Exclude p.FilterDescendantsInstances = ex
			local r = workspace:Raycast(from, dir, p)
			if not r then return nil end
			if r.Instance:IsDescendantOf(map) and r.Instance.CanCollide and not r.Instance:GetAttribute("NoGrapple") then return r end
			table.insert(ex, r.Instance)
		end
	end
	for i = 1, 1600 do
		local x, z = rng:NextNumber(x0 + 2, x1 - 2), rng:NextNumber(z0 + 2, z1 - 2)
		local fl = workspace:Raycast(O + V(x, ceilY - 2, z), V(0, -(ceilY + 30), 0), inc)
		if fl and fl.Position.Y - O.Y < 60 then
			local from = fl.Position + V(0, 5, 0)
			for k = 1, 5 do
				local d = V(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit * 150
				local h = grapple(from, d) n += 1
				if h then local p = h.Position - O if p.X < x0 - 0.1 or p.X > x1 + 0.1 or p.Z < z0 - 0.1 or p.Z > z1 + 0.1 or p.Y > ceilY then table.insert(bad, h.Instance.Name .. ("@%.0f,%.0f,%.0f"):format(p.X, p.Y, p.Z)) end end
			end
		end
		if i % 200 == 0 then task.wait() end
	end
	table.insert(out, ("grapple rays=%d outside=%d %s"):format(n, #bad, table.concat(bad, "; ", 1, math.min(#bad, 5))))
	-- spawn exits from door shields
	local exits = {}
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:find("SpawnShield") and d:GetAttribute("Team") == "Blue" and d.Size.Y >= 10 and d.Size.Y < 15 then
			local p = d.Position - O
			local dirz = p.Z < 0 and 1 or -1
			for _, ox in ipairs({ -3, 0, 3 }) do for _, dz in ipairs({ 4, 9 }) do
				local w = math.max(d.Size.X, d.Size.Z)
				local q = V(p.X + ox * (w / 10), p.Y - d.Size.Y / 2 + 5, p.Z + dirz * dz)
				table.insert(exits, q)
			end end
		end
	end
	local ex = { map:FindFirstChild("Gameplay") }
	for _, d in ipairs(map:GetDescendants()) do if d:IsA("BasePart") and d.Name:find("SpawnShield") then table.insert(ex, d) end end
	local los = RaycastParams.new() los.FilterType = Enum.RaycastFilterType.Exclude los.FilterDescendantsInstances = ex los.RespectCanCollide = true
	local function clear(a, b) return workspace:Raycast(O + a, b - a, los) == nil end
	local function red(p) if sym == "mirror" then return V(p.X, p.Y, -p.Z) end return V(-p.X, p.Y, -p.Z) end
	local targets = {}
	for x = x0 + 3, x1 - 3, 5 do for z = 3, z1 - 3, 5 do
		local f = workspace:Raycast(O + V(x, ceilY - 2, z), V(0, -(ceilY + 30), 0), inc)
		if f and not f.Instance:GetAttribute("NoGrapple") then table.insert(targets, f.Position - O + V(0, 5, 0)) end
	end task.wait() end
	local hits, tot = 0, 0
	for _, e in ipairs(exits) do for _, t in ipairs(targets) do tot += 1 if clear(e, t) then hits += 1 end end task.wait() end
	local ee, et = 0, 0
	for _, a in ipairs(exits) do for _, b in ipairs(exits) do et += 1 if clear(a, red(b)) then ee += 1 end end end
	table.insert(out, ("exits=%d exit->enemy %d/%d (%.2f%%) exit<->exit %d/%d"):format(#exits, hits, tot, 100 * hits / math.max(tot, 1), ee, et))
	-- reachability: gate->gate and sampled ground points -> centre
	local PFS = game:GetService("PathfindingService")
	local function path(a, b)
		local p = PFS:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
		local ok = pcall(function() p:ComputeAsync(a, b) end)
		if ok and p.Status == Enum.PathStatus.Success then local w = p:GetWaypoints() local L = 0 for i = 2, #w do L += (w[i].Position - w[i - 1].Position).Magnitude end return true, L end
		return false, 0
	end
	if #exits > 0 then
		local a = O + exits[2] - V(0, 3, 0)
		local ok, L = path(a, O + red(exits[2]) - V(0, 3, 0))
		table.insert(out, ("gate->gate %s %.0f"):format(tostring(ok), L))
		local trapped, tt, roofNo = 0, {}, 0
		local rs = Random.new(11)
		for i = 1, (opts.samples or 120) do
			local x, z = rs:NextNumber(x0 + 3, x1 - 3), rs:NextNumber(z0 + 3, z1 - 3)
			local f = workspace:Raycast(O + V(x, ceilY - 2, z), V(0, -(ceilY + 30), 0), inc)
			if f and f.Normal.Y > 0.7 and not f.Instance:GetAttribute("NoGrapple") then
				local ok2 = path(f.Position + V(0, 2.5, 0), a)
				if not ok2 then
					local y = f.Position.Y - O.Y
					if y <= (opts.groundMax or 1) then trapped += 1 if #tt < 8 then table.insert(tt, ("%.0f,%.0f,%.0f %s"):format(x, y, z, f.Instance.Name)) end else roofNo += 1 end
				end
			end
			if i % 10 == 0 then task.wait() end
		end
		table.insert(out, ("groundTrapped=%d %s | roofsNoWalk=%d"):format(trapped, table.concat(tt, "; "), roofNo))
	end
	return table.concat(out, "\n")
end
return Au
