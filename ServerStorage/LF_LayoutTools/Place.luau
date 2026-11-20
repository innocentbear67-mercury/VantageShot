-- Place a library model (all parts share one CFrame/size, see split_mat.py anchors) at ground height, scaled.
local P = {}
local lib = game:GetService("ServerStorage"):WaitForChild("LF_MeshBoard")
function P.place(name, x, z, targetH, yaw, parent, groundY, sink, tilt)
	local src = lib:FindFirstChild(name); assert(src, name)
	local m = src:Clone()
	local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	local k = targetH / pp.Size.Y
	local cf = CFrame.new(x, groundY + pp.Size.Y * k / 2 - (sink or 0), z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	if tilt then cf = cf * CFrame.Angles(math.rad(tilt[1]), 0, math.rad(tilt[2])) end
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then p.Size = p.Size * k; p.CFrame = cf end
	end
	m.Parent = parent
	return m
end
return P
