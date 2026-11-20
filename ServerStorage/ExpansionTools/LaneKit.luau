-- LaneKit: helpers for cutting vehicle lanes through Map_LiveFire without destroying anything.
local SS = game:GetService("ServerStorage")
local K = {}
K.Map = workspace.Map_LiveFire
K.S = K.Map.Structure

function K.archive(inst, reason)
	local f = SS:FindFirstChild("_LaneArchive_20261111") or Instance.new("Folder")
	f.Name = "_LaneArchive_20261111"; f.Parent = SS
	inst:SetAttribute("ArchivedFrom", inst.Parent and inst.Parent:GetFullName() or "?")
	inst:SetAttribute("ArchiveReason", reason or "vehicle lane")
	inst.Parent = f
end

function K.parts(inst)
	if inst:IsA("BasePart") then return { inst } end
	local t = {}
	for _, d in inst:GetDescendants() do if d:IsA("BasePart") then table.insert(t, d) end end
	return t
end

function K.bounds(inst)
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in K.parts(inst) do
		local cf, h = d.CFrame, d.Size / 2
		local ax, ay, az = cf.RightVector * h.X, cf.UpVector * h.Y, cf.LookVector * h.Z
		local e = Vector3.new(math.abs(ax.X) + math.abs(ay.X) + math.abs(az.X), math.abs(ax.Y) + math.abs(ay.Y) + math.abs(az.Y), math.abs(ax.Z) + math.abs(ay.Z) + math.abs(az.Z))
		mn = mn:Min(cf.Position - e); mx = mx:Max(cf.Position + e)
	end
	return mn, mx
end

function K.translate(inst, off)
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + off)
	else
		for _, p in K.parts(inst) do p.CFrame = p.CFrame + off end
	end
end

-- is the box (world AABB) free of colliding structure parts, ignoring `ignore` and anything below y 2.6 (floors)
function K.free(mn, mx, ignore)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { workspace.Terrain }
	for _, i in ignore or {} do table.insert(ex, i) end
	params.FilterDescendantsInstances = ex
	params.RespectCanCollide = true
	local lo = Vector3.new(mn.X, math.max(mn.Y, 2.6), mn.Z)
	if mx.Y <= lo.Y then return true end
	local hits = workspace:GetPartBoundsInBox(CFrame.new((lo + mx) / 2), mx - lo, params)
	for _, h in hits do
		if h.CanCollide and h:IsDescendantOf(K.Map) and not h:IsDescendantOf(K.Map.Gameplay) then return false, h end
	end
	return true
end

-- slide an item along `dir` (unit, XZ) in 1-stud steps until it no longer touches lane box [lmn,lmx]
-- and lands in free space; tries `dir` first, then -dir. Returns moved distance or nil.
function K.slideOut(item, lmn, lmx, dir, maxd)
	local mn, mx = K.bounds(item)
	for _, d in { dir, -dir } do
		for s = 1, maxd or 40 do
			local off = d * s
			local a, b = mn + off, mx + off
			local outside = a.X >= lmx.X + 1 or b.X <= lmn.X - 1 or a.Z >= lmx.Z + 1 or b.Z <= lmn.Z - 1
			if outside then
				local ok = K.free(a, b, { item })
				if ok then K.translate(item, off); return s * (d == dir and 1 or -1) end
			end
		end
	end
	return nil
end

-- replace a single centred support (+ its foot) with two supports offset by `offsets` (list of Vector3)
function K.splitSupport(support, foot, offsets)
	local made = {}
	for _, o in offsets do
		local s = support:Clone(); s.CFrame = support.CFrame + o; s.Parent = support.Parent; table.insert(made, s)
		if foot then local f = foot:Clone(); f.CFrame = foot.CFrame + o; f.Parent = foot.Parent; table.insert(made, f) end
	end
	K.archive(support, "split for vehicle lane")
	if foot then K.archive(foot, "split for vehicle lane") end
	return made
end

-- nearest part named `name` inside `root` to position `pos` (XZ), within `tol`
function K.near(root, name, pos, tol)
	local best, bd = nil, tol or 3
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			local dd = (Vector2.new(d.Position.X, d.Position.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
			if dd < bd then best, bd = d, dd end
		end
	end
	return best
end

-- direct item (child of a Structure sub-folder or sub-model) owning part p
function K.itemOf(p)
	local cur = p
	while cur.Parent and cur.Parent.Parent ~= K.S and cur.Parent ~= K.S do
		if cur.Parent.Parent and cur.Parent.Parent.Parent == K.S and cur.Parent:IsA("Model") then break end
		cur = cur.Parent
	end
	return cur
end

-- colliding parts inside a lane box (ground band y 2.6..14)
function K.inLane(lmn, lmx)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { K.S }
	params.RespectCanCollide = true
	local lo, hi = Vector3.new(lmn.X, 2.6, lmn.Z), Vector3.new(lmx.X, 14, lmx.Z)
	local out = {}
	for _, h in workspace:GetPartBoundsInBox(CFrame.new((lo + hi) / 2), hi - lo, params) do
		if h.CanCollide then table.insert(out, h) end
	end
	return out
end

return K
