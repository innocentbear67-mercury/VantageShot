local D = {}
local V = Vector3.new
function D.measure(map, O, b, n, maxY)
	local wasParent = map.Parent
	if map.Parent ~= workspace then map.Parent = workspace end
	local excl = {}
	for _, d in ipairs(map:GetDescendants()) do if d:IsA("BasePart") and (d.Name:find("SpawnShield") or d.Transparency > 0.9) then table.insert(excl, d) end end
	local G = map:FindFirstChild("Gameplay") if G then table.insert(excl, G) end
	local los = RaycastParams.new() los.FilterType = Enum.RaycastFilterType.Exclude los.FilterDescendantsInstances = excl los.RespectCanCollide = true
	local rng = Random.new(7) local pts = {}
	local tries = 0
	while #pts < (n or 700) and tries < 20000 do
		tries += 1
		local x, z = rng:NextNumber(b[1] + 3, b[2] - 3), rng:NextNumber(b[3] + 3, b[4] - 3)
		local r = workspace:Raycast(O + V(x, 200, z), V(0, -260, 0), los)
		if r and r.Normal.Y > 0.7 and r.Position.Y - O.Y < (maxY or 40) then table.insert(pts, r.Position + V(0, 4.5, 0)) end
	end
	local d = {} local vis, tot = 0, 0
	for i = 1, #pts do for j = i + 1, #pts, 3 do tot += 1
		local a, c = pts[i], pts[j]
		if not workspace:Raycast(a, c - a, los) then vis += 1 table.insert(d, (c - a).Magnitude) end
	end if i % 50 == 0 then task.wait() end end
	table.sort(d)
	local function pct(p) return d[math.max(1, math.floor(#d * p))] or 0 end
	local o80, o120 = 0, 0 for _, x in ipairs(d) do if x > 80 then o80 += 1 end if x > 120 then o120 += 1 end end
	map.Parent = wasParent
	return ("visible=%.1f%% median=%.0f p75=%.0f p90=%.0f >80=%.0f%% >120=%.0f%%"):format(100 * vis / tot, pct(0.5), pct(0.75), pct(0.9), 100 * o80 / math.max(1,#d), 100 * o120 / math.max(1,#d))
end
return D
