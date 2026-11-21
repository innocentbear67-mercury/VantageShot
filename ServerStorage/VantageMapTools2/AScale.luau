-- AScale: compact a map horizontally (x,z) about its origin, keeping heights.
local S = {}
local V = Vector3.new
local function axisFactor(dir, s) return V(dir.X * s, dir.Y, dir.Z * s).Magnitude end
function S.scaleMap(root, O, s, skipNames, apply)
	skipNames = skipNames or {}
	if apply ~= true then
		local skipRoots = {}
		for _, d in ipairs(root:GetDescendants()) do
			if skipNames[d.Name] and (d:IsA("Folder") or d:IsA("Model")) then
				table.insert(skipRoots, d)
			end
		end
		local function drySkipped(d)
			for _, r in ipairs(skipRoots) do
				if d:IsDescendantOf(r) then
					return true
				end
			end
			return false
		end
		local counts = {}
		local total = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and not drySkipped(d) then
				local cn = d.ClassName
				counts[cn] = (counts[cn] or 0) + 1
				total += 1
			end
		end
		print(("AScale: dry run — %d parts in %s would be rescaled (x,z) by %s; skipped groups move rigidly"):format(total, root:GetFullName(), tostring(s)))
		local classes = {}
		for cls in pairs(counts) do
			table.insert(classes, cls)
		end
		table.sort(classes)
		for _, cls in ipairs(classes) do
			print(("AScale:   %s x%d"):format(cls, counts[cls]))
		end
		print("AScale: re-run with Apply=true to rescale in place — no backup is made")
		return
	end
	local n = 0
	local skipRoots = {}
	for _, d in ipairs(root:GetDescendants()) do
		if skipNames[d.Name] and (d:IsA("Folder") or d:IsA("Model")) then table.insert(skipRoots, d) end
	end
	local function skipped(d) for _, r in ipairs(skipRoots) do if d:IsDescendantOf(r) then return r end end end
	-- skipped groups: move rigidly by their centre only
	for _, r in ipairs(skipRoots) do
		local sum, k = V(), 0
		for _, d in ipairs(r:GetDescendants()) do if d:IsA("BasePart") then sum += d.Position k += 1 end end
		if k > 0 then
			local c = sum / k
			local rel = c - O
			local off = V(rel.X * (s - 1), 0, rel.Z * (s - 1))
			for _, d in ipairs(r:GetDescendants()) do if d:IsA("BasePart") then d.CFrame = d.CFrame + off end end
		end
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and not skipped(d) then
			local cf = d.CFrame
			local p = cf.Position - O
			local np = O + V(p.X * s, p.Y, p.Z * s)
			if d:IsA("SpawnLocation") then
				d.CFrame = cf - cf.Position + np
			else
				local sz = d.Size
				local fx = axisFactor(cf.RightVector, s)
				local fy = axisFactor(cf.UpVector, s)
				local fz = axisFactor(cf.LookVector, s)
				if d:IsA("Part") and d.Shape == Enum.PartType.Ball then
					local f = math.min(fx, fy, fz) d.Size = sz * f
				elseif d:IsA("Part") and d.Shape == Enum.PartType.Cylinder then
					local f = math.min(fy, fz) d.Size = V(sz.X * fx, sz.Y * f, sz.Z * f)
				else
					d.Size = V(sz.X * fx, sz.Y * fy, sz.Z * fz)
				end
				d.CFrame = cf - cf.Position + np
			end
			local t = d:GetAttribute("PadTarget")
			if typeof(t) == "Vector3" then local r = t - O d:SetAttribute("PadTarget", O + V(r.X * s, r.Y, r.Z * s)) end
			n += 1
		end
	end
	return n
end
return S
