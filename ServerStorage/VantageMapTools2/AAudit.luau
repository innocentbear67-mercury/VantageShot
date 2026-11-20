local Au = {}
local V = Vector3.new
function Au.run(map, O, box, sym, exits, minY)
	local out = {}
	local x0, x1, z0, z1 = box[1], box[2], box[3], box[4]
	local geo = {}
	for _, f in ipairs({ "Blue", "Red", "Shared" }) do table.insert(geo, map[f]) end
	local inc = RaycastParams.new() inc.FilterType = Enum.RaycastFilterType.Include inc.FilterDescendantsInstances = geo
	-- holes
	local holes = 0 local hs = {}
	for x = x0 + 0.5, x1 - 0.5, 1 do
		for z = z0 + 0.5, z1 - 0.5, 1 do
			local r = workspace:Raycast(O + V(x, 150, z), V(0, -230, 0), inc)
			if not r or r.Position.Y < (minY or -18) then holes += 1 if #hs < 8 then table.insert(hs, ("%d,%d"):format(x, z)) end end
		end
		if math.floor(x) % 25 == 0 then task.wait() end
	end
	table.insert(out, ("holes=%d %s"):format(holes, table.concat(hs, " ")))
	-- static grapple
	local inv = 0
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and d.Transparency >= 0.9 and not d:GetAttribute("NoGrapple") then inv += 1 end
	end
	-- grapple sim
	local rng = Random.new(3)
	local bad, n = {}, 0
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
	for i = 1, 2400 do
		local x, z = rng:NextNumber(x0 + 2, x1 - 2), rng:NextNumber(z0 + 2, z1 - 2)
		local fl = workspace:Raycast(O + V(x, 150, z), V(0, -230, 0), inc)
		if fl and fl.Position.Y < 140 then
			local from = fl.Position + V(0, 5, 0)
			for k = 1, 5 do
				local d = V(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit * 150
				local h = grapple(from, d) n += 1
				if h then local p = h.Position - O if p.X < x0 - 0.05 or p.X > x1 + 0.05 or math.abs(p.Z) > math.max(-z0, z1) + 0.05 or p.Y > 167 then table.insert(bad, h.Instance.Name .. ("@%d,%d,%d"):format(p.X, p.Y, p.Z)) end end
			end
		end
		if i % 300 == 0 then task.wait() end
	end
	table.insert(out, ("invisibleGrappleable=%d grappleRays=%d outside=%d %s"):format(inv, n, #bad, table.concat(bad, "; ", 1, math.min(#bad, 6))))
	-- sightlines
	local ex = { map.Gameplay }
	for _, d in ipairs(map:GetDescendants()) do if d.Name == "SpawnShield" then table.insert(ex, d) end end
	local los = RaycastParams.new() los.FilterType = Enum.RaycastFilterType.Exclude los.FilterDescendantsInstances = ex los.RespectCanCollide = true
	local function clear(a, b) return workspace:Raycast(O + a, b - a, los) == nil end
	local function red(p) if sym == "mirror" then return V(p.X, p.Y, -p.Z) end return V(-p.X, p.Y, -p.Z) end
	local targets = {}
	for x = x0 + 4, x1 - 4, 7 do for z = 3, z1 - 3, 7 do
		local f = workspace:Raycast(O + V(x, 150, z), V(0, -230, 0), inc)
		if f and not f.Instance:GetAttribute("NoGrapple") then table.insert(targets, f.Position - O + V(0, 5, 0)) end
	end task.wait() end
	local hits, tot, hs2 = 0, 0, {}
	for _, e in ipairs(exits) do for _, t in ipairs(targets) do tot += 1 if clear(e, t) then hits += 1 if #hs2 < 10 then table.insert(hs2, ("(%d,%d)->(%d,%d,%d)"):format(e.X, e.Z, t.X, t.Y, t.Z)) end end end task.wait() end
	local ee, et = 0, 0
	for _, a in ipairs(exits) do for _, b in ipairs(exits) do et += 1 if clear(a, red(b)) then ee += 1 end end end
	table.insert(out, ("exit->enemy %d/%d  exit<->exit %d/%d %s"):format(hits, tot, ee, et, table.concat(hs2, "  ")))
	-- paths
	local PFS = game:GetService("PathfindingService")
	local a = exits[1] + V(0, -3, 0)
	local p = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 8 })
	p:ComputeAsync(O + a, O + red(a))
	local len = 0 if p.Status == Enum.PathStatus.Success then local w = p:GetWaypoints() for i = 2, #w do len += (w[i].Position - w[i - 1].Position).Magnitude end end
	table.insert(out, ("gate->gate %s %d"):format(tostring(p.Status), len))
	return table.concat(out, "\n")
end
function Au.paths(O, from, goals)
	local PFS = game:GetService("PathfindingService")
	local out = {}
	for _, g in ipairs(goals) do
		local p = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 8 })
		p:ComputeAsync(O + from, O + g[2])
		table.insert(out, g[1] .. ":" .. tostring(p.Status):gsub("Enum.PathStatus.", ""))
		task.wait()
	end
	return table.concat(out, "  ")
end
return Au
