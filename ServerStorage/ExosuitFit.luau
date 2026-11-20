--[[
	ExosuitFit (2026-11-14): mounts the imported VantageExosuit_v3 meshes on a blocky R15 rig.
	Each MeshPart is named <BodyPart>__<Slot>. META holds its centre and size in rest pose (relative to the
	root, Roblox axes) as exported from Blender, so placement doesn't depend on the importer's units.
	Fit.Mount(rig, source) clones the meshes from source (the imported model), sizes and places them on
	the rig's rest pose, welds each to its body part and hides the body. Returns the folder of pieces.
]]
local Fit = {}

Fit.Slots = {
	Graphite = { Color = Color3.fromRGB(58, 61, 68), Material = Enum.Material.SmoothPlastic, Reflectance = 0.04 },
	Gunmetal = { Color = Color3.fromRGB(118, 122, 130), Material = Enum.Material.Metal },
	Black = { Color = Color3.fromRGB(26, 27, 31), Material = Enum.Material.SmoothPlastic },
	Energy = { Color = Color3.fromRGB(205, 255, 130), Material = Enum.Material.Neon },
	Visor = { Color = Color3.fromRGB(95, 200, 20), Material = Enum.Material.Neon },
}

Fit.META = {
	["Head__Black"] = { Part = "Head", Slot = "Black", C = Vector3.new(0.0000, 1.6434, 0.0749), S = Vector3.new(1.5939, 1.3468, 1.1109) },
	["Head__Energy"] = { Part = "Head", Slot = "Energy", C = Vector3.new(0.0000, 1.7045, -0.2192), S = Vector3.new(1.6099, 0.1990, 0.6190) },
	["Head__Graphite"] = { Part = "Head", Slot = "Graphite", C = Vector3.new(0.0000, 1.6949, 0.1038), S = Vector3.new(1.3939, 1.4826, 1.4378) },
	["Head__Gunmetal"] = { Part = "Head", Slot = "Gunmetal", C = Vector3.new(0.0000, 1.7116, -0.0320), S = Vector3.new(1.5539, 1.1832, 1.2590) },
	["Head__Visor"] = { Part = "Head", Slot = "Visor", C = Vector3.new(0.0000, 1.7200, -0.0489), S = Vector3.new(1.3876, 0.4800, 0.9363) },
	["LeftFoot__Black"] = { Part = "LeftFoot", Slot = "Black", C = Vector3.new(-0.5000, -2.9500, -0.0400), S = Vector3.new(1.0400, 0.1000, 1.1800) },
	["LeftFoot__Graphite"] = { Part = "LeftFoot", Slot = "Graphite", C = Vector3.new(-0.5000, -2.7600, -0.0589), S = Vector3.new(0.9980, 0.2800, 1.1558) },
	["LeftFoot__Gunmetal"] = { Part = "LeftFoot", Slot = "Gunmetal", C = Vector3.new(-0.5000, -2.7900, -0.0386), S = Vector3.new(0.8780, 0.2161, 1.2372) },
	["LeftHand__Black"] = { Part = "LeftHand", Slot = "Black", C = Vector3.new(-1.5000, -0.8600, 0.0000), S = Vector3.new(0.9800, 0.3000, 0.9800) },
	["LeftHand__Gunmetal"] = { Part = "LeftHand", Slot = "Gunmetal", C = Vector3.new(-1.5000, -0.7900, -0.4800), S = Vector3.new(0.9200, 0.1400, 0.1200) },
	["LeftLowerArm__Black"] = { Part = "LeftLowerArm", Slot = "Black", C = Vector3.new(-1.5650, -0.1400, 0.0000), S = Vector3.new(1.0500, 1.2400, 0.9200) },
	["LeftLowerArm__Graphite"] = { Part = "LeftLowerArm", Slot = "Graphite", C = Vector3.new(-1.5228, -0.3300, 0.0000), S = Vector3.new(1.0656, 0.5400, 1.1600) },
	["LeftLowerArm__Gunmetal"] = { Part = "LeftLowerArm", Slot = "Gunmetal", C = Vector3.new(-1.5250, -0.2200, -0.0548), S = Vector3.new(1.0900, 0.9400, 1.1495) },
	["LeftLowerLeg__Black"] = { Part = "LeftLowerLeg", Slot = "Black", C = Vector3.new(-0.5414, -2.2000, 0.0000), S = Vector3.new(1.0028, 1.2800, 0.9000) },
	["LeftLowerLeg__Graphite"] = { Part = "LeftLowerLeg", Slot = "Graphite", C = Vector3.new(-0.5352, -2.0765, -0.1336), S = Vector3.new(0.9895, 1.0331, 1.3472) },
	["LeftLowerLeg__Gunmetal"] = { Part = "LeftLowerLeg", Slot = "Gunmetal", C = Vector3.new(-0.5810, -2.2221, -0.2673), S = Vector3.new(0.9181, 1.1959, 1.0595) },
	["LeftUpperArm__Black"] = { Part = "LeftUpperArm", Slot = "Black", C = Vector3.new(-1.5000, 0.3800, 0.0000), S = Vector3.new(0.9400, 1.2000, 0.9400) },
	["LeftUpperArm__Graphite"] = { Part = "LeftUpperArm", Slot = "Graphite", C = Vector3.new(-1.6249, 0.6446, 0.0000), S = Vector3.new(1.2476, 1.0092, 1.2395) },
	["LeftUpperArm__Gunmetal"] = { Part = "LeftUpperArm", Slot = "Gunmetal", C = Vector3.new(-1.6334, 0.7105, 0.0000), S = Vector3.new(1.2067, 0.9783, 1.2368) },
	["LeftUpperLeg__Black"] = { Part = "LeftUpperLeg", Slot = "Black", C = Vector3.new(-0.5000, -1.4200, 0.0000), S = Vector3.new(0.9400, 1.3400, 0.9200) },
	["LeftUpperLeg__Graphite"] = { Part = "LeftUpperLeg", Slot = "Graphite", C = Vector3.new(-0.5404, -1.1197, -0.0444), S = Vector3.new(0.9992, 0.7595, 1.1489) },
	["LeftUpperLeg__Gunmetal"] = { Part = "LeftUpperLeg", Slot = "Gunmetal", C = Vector3.new(-1.0000, -0.8600, 0.0000), S = Vector3.new(0.0800, 0.3400, 0.3315) },
	["LowerTorso__Black"] = { Part = "LowerTorso", Slot = "Black", C = Vector3.new(0.0000, -0.8000, 0.0000), S = Vector3.new(1.9000, 0.4200, 0.9400) },
	["LowerTorso__Graphite"] = { Part = "LowerTorso", Slot = "Graphite", C = Vector3.new(0.0000, -0.7850, -0.0337), S = Vector3.new(2.0600, 0.4300, 1.0675) },
	["LowerTorso__Gunmetal"] = { Part = "LowerTorso", Slot = "Gunmetal", C = Vector3.new(0.0000, -0.6700, -0.5300), S = Vector3.new(0.4365, 0.1800, 0.1000) },
	["RightFoot__Black"] = { Part = "RightFoot", Slot = "Black", C = Vector3.new(0.5000, -2.9500, -0.0400), S = Vector3.new(1.0400, 0.1000, 1.1800) },
	["RightFoot__Graphite"] = { Part = "RightFoot", Slot = "Graphite", C = Vector3.new(0.5000, -2.7600, -0.0589), S = Vector3.new(0.9980, 0.2800, 1.1558) },
	["RightFoot__Gunmetal"] = { Part = "RightFoot", Slot = "Gunmetal", C = Vector3.new(0.5000, -2.7900, -0.0386), S = Vector3.new(0.8780, 0.2161, 1.2372) },
	["RightHand__Black"] = { Part = "RightHand", Slot = "Black", C = Vector3.new(1.5000, -0.8600, 0.0000), S = Vector3.new(0.9800, 0.3000, 0.9800) },
	["RightHand__Gunmetal"] = { Part = "RightHand", Slot = "Gunmetal", C = Vector3.new(1.5000, -0.7900, -0.4800), S = Vector3.new(0.9200, 0.1400, 0.1200) },
	["RightLowerArm__Black"] = { Part = "RightLowerArm", Slot = "Black", C = Vector3.new(1.5650, -0.1400, 0.0000), S = Vector3.new(1.0500, 1.2400, 0.9200) },
	["RightLowerArm__Graphite"] = { Part = "RightLowerArm", Slot = "Graphite", C = Vector3.new(1.5228, -0.3300, 0.0000), S = Vector3.new(1.0656, 0.5400, 1.1600) },
	["RightLowerArm__Gunmetal"] = { Part = "RightLowerArm", Slot = "Gunmetal", C = Vector3.new(1.5250, -0.2200, -0.0548), S = Vector3.new(1.0900, 0.9400, 1.1495) },
	["RightLowerLeg__Black"] = { Part = "RightLowerLeg", Slot = "Black", C = Vector3.new(0.5414, -2.2000, 0.0000), S = Vector3.new(1.0028, 1.2800, 0.9000) },
	["RightLowerLeg__Graphite"] = { Part = "RightLowerLeg", Slot = "Graphite", C = Vector3.new(0.5352, -2.0765, -0.1336), S = Vector3.new(0.9895, 1.0331, 1.3472) },
	["RightLowerLeg__Gunmetal"] = { Part = "RightLowerLeg", Slot = "Gunmetal", C = Vector3.new(0.5810, -2.2221, -0.2673), S = Vector3.new(0.9181, 1.1959, 1.0595) },
	["RightUpperArm__Black"] = { Part = "RightUpperArm", Slot = "Black", C = Vector3.new(1.5000, 0.3800, 0.0000), S = Vector3.new(0.9400, 1.2000, 0.9400) },
	["RightUpperArm__Graphite"] = { Part = "RightUpperArm", Slot = "Graphite", C = Vector3.new(1.6249, 0.6446, 0.0000), S = Vector3.new(1.2476, 1.0092, 1.2395) },
	["RightUpperArm__Gunmetal"] = { Part = "RightUpperArm", Slot = "Gunmetal", C = Vector3.new(1.6334, 0.7105, 0.0000), S = Vector3.new(1.2067, 0.9783, 1.2368) },
	["RightUpperLeg__Black"] = { Part = "RightUpperLeg", Slot = "Black", C = Vector3.new(0.5000, -1.4200, 0.0000), S = Vector3.new(0.9400, 1.3400, 0.9200) },
	["RightUpperLeg__Graphite"] = { Part = "RightUpperLeg", Slot = "Graphite", C = Vector3.new(0.5404, -1.1197, -0.0444), S = Vector3.new(0.9992, 0.7595, 1.1489) },
	["RightUpperLeg__Gunmetal"] = { Part = "RightUpperLeg", Slot = "Gunmetal", C = Vector3.new(1.0000, -0.8600, 0.0000), S = Vector3.new(0.0800, 0.3400, 0.3315) },
	["UpperTorso__Black"] = { Part = "UpperTorso", Slot = "Black", C = Vector3.new(0.0000, 0.2650, 0.2344), S = Vector3.new(1.9000, 1.7500, 1.4089) },
	["UpperTorso__Energy"] = { Part = "UpperTorso", Slot = "Energy", C = Vector3.new(0.0000, 0.3200, 0.0180), S = Vector3.new(0.1732, 0.8400, 1.3660) },
	["UpperTorso__Graphite"] = { Part = "UpperTorso", Slot = "Graphite", C = Vector3.new(0.0000, 0.3827, -0.0837), S = Vector3.new(2.0800, 1.5515, 1.3275) },
	["UpperTorso__Gunmetal"] = { Part = "UpperTorso", Slot = "Gunmetal", C = Vector3.new(0.0000, 0.2398, 0.1220), S = Vector3.new(1.8000, 1.6197, 1.6747) },
}

function Fit.Mount(rig: Model, source: Instance)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local rest = root.CFrame
	local folder = Instance.new("Folder")
	folder.Name = "Exosuit"
	local report = { placed = 0, missing = {} }
	for name, m in Fit.META do
		local src = source:FindFirstChild(name, true)
		local body = rig:FindFirstChild(m.Part) :: BasePart?
		if not (src and src:IsA("MeshPart") and body) then
			table.insert(report.missing, name)
			continue
		end
		local mp = src:Clone()
		for _, c in mp:GetChildren() do c:Destroy() end
		mp.Name = name
		mp.Size = m.S
		mp.CFrame = rest * CFrame.new(m.C)
		mp.Anchored, mp.Massless = false, true
		mp.CanCollide, mp.CanQuery, mp.CanTouch = false, false, false
		local look = Fit.Slots[m.Slot]
		if look then
			mp.Color, mp.Material = look.Color, look.Material
			mp.Reflectance = look.Reflectance or 0
		end
		mp.CastShadow = m.Slot ~= "Energy"
		mp.TextureID = ""
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = body, mp
		w.Parent = mp
		mp.Parent = folder
		report.placed += 1
	end
	for _, p in rig:GetChildren() do
		if p:IsA("BasePart") and p ~= root then p.Transparency = 1 end
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("Decal") then d.Transparency = 1 end
	end
	folder.Parent = rig
	return folder, report
end

return Fit
