--[[
	VANTAGE — VehicleBuilder (server / edit-time)
	Assembles a playable vehicle template from an imported asset (ServerStorage.VehicleImports)
	without touching its meshes: invisible collision boxes, seats, joints for the moving parts,
	suspension points, exits and the muzzle. VehicleBuilder.BuildAll() rebuilds
	ServerStorage.Vehicles.Templates; VehicleService clones from there.

	Asset space: +Z forward, +X left, +Y up, ground at Y = 0 (the importer's orientation of the
	split .glb files). The template's Root part faces +Z, so Root.CFrame.LookVector is forward.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Vantage.Vehicles.VehicleConfig)

local B = {}

local FACE = CFrame.Angles(0, math.pi, 0) -- -Z look -> +Z look

-- geometry per vehicle, in asset space. Root/Extra = collision boxes { centre, size }.
-- Wheels: { name, hub position, radius, steers, driven, visual mesh name? }
B.Layout = {
	Tank = {
		Root = { Vector3.new(0, 4.3, -2.6), Vector3.new(14, 5.8, 26) },
		Extra = { { "Col_Turret", Vector3.new(0, 9.5, -5), Vector3.new(10.4, 4.6, 15.2) } },
		Static = { "Hull" },
		Yaw = { Part = "Turret", Pivot = Vector3.new(0, 7.0, -3.65) },
		Pitch = { Part = "Barrel", Pivot = Vector3.new(0, 8.5, 0.6) },
		Muzzle = Vector3.new(0, 8.5, 16.2),
		-- tracks: suspension points only (the road wheels are part of the hull mesh)
		Wheels = (function()
			local t = {}
			for i, z in { 8, 3, -2, -7, -12 } do
				table.insert(t, { "Track_L" .. i, Vector3.new(5.3, 1.5, z), 1.5, false, true })
				table.insert(t, { "Track_R" .. i, Vector3.new(-5.3, 1.5, z), 1.5, false, true })
			end
			return t
		end)(),
	},
	APC = {
		Root = { Vector3.new(0, 7.1, 0), Vector3.new(13.8, 8.6, 27.6) },
		Extra = {},
		Static = { "Hull" },
		Yaw = { Part = "GunYaw", Pivot = Vector3.new(-0.1, 11.4, -2.63) },
		Pitch = { Part = "GunPitch", Pivot = Vector3.new(-0.43, 13.95, -3.0) },
		Muzzle = Vector3.new(-0.43, 14.0, 3.6),
		Wheels = {
			{ "Wheel_FL", Vector3.new(5.85, 2.65, 8.57), 2.65, true, true, "Wheel_FL" },
			{ "Wheel_FR", Vector3.new(-5.85, 2.65, 8.57), 2.65, true, true, "Wheel_FR" },
			{ "Wheel_ML", Vector3.new(5.85, 2.65, -3.48), 2.65, false, true, "Wheel_ML" },
			{ "Wheel_MR", Vector3.new(-5.85, 2.65, -3.48), 2.65, false, true, "Wheel_MR" },
			{ "Wheel_RL", Vector3.new(5.85, 2.65, -9.42), 2.65, false, true, "Wheel_RL" },
			{ "Wheel_RR", Vector3.new(-5.85, 2.65, -9.42), 2.65, false, true, "Wheel_RR" },
		},
	},
	Buggy = {
		Root = { Vector3.new(0, 4.6, 0), Vector3.new(8.8, 4.0, 18.8) },
		Extra = {},
		Static = { "Hull" },
		Yaw = { Part = "GunYaw", Pivot = Vector3.new(-0.3, 9.3, -2.24) },
		Pitch = { Part = "GunPitch", Pivot = Vector3.new(0, 10.5, -2.4) },
		Muzzle = Vector3.new(0, 10.75, 2.4),
		Wheels = {
			{ "Wheel_FL", Vector3.new(5.53, 2.52, 7.51), 2.5, true, true, "Wheel_FL" },
			{ "Wheel_FR", Vector3.new(-5.64, 2.50, 7.47), 2.5, true, true, "Wheel_FR" },
			{ "Wheel_RL", Vector3.new(5.65, 2.59, -7.50), 2.5, false, true, "Wheel_RL" },
			{ "Wheel_RR", Vector3.new(-5.65, 2.56, -7.50), 2.5, false, true, "Wheel_RR" },
		},
	},
}

-- the drone: fixed twin guns in the nose (no moving gun parts), four rotors spinning on their own
-- tilted axes (disc normals measured from the mesh), a lift force instead of suspension
B.Layout.Drone = {
	Root = { Vector3.new(0, 3.0, -1.1), Vector3.new(6, 4.2, 11) },
	Extra = { { "Col_Fans", Vector3.new(0, 3.25, -1.6), Vector3.new(16, 3.5, 11.2) } },
	Static = { "Hull" },
	Gun = { Pivot = Vector3.new(0, 2.35, 4.0), Muzzles = { Vector3.new(0.64, 2.2, 7.1), Vector3.new(-0.64, 2.2, 7.1) } },
	Rotors = {
		{ "Rotor_FL", Vector3.new(0.002, 0.981, 0.194) },
		{ "Rotor_FR", Vector3.new(-0.004, 0.979, 0.203) },
		{ "Rotor_RL", Vector3.new(0.002, 0.98, 0.2) },
		{ "Rotor_RR", Vector3.new(0, 0.981, 0.196) },
	},
	Wheels = {},
}

local SUSP_TOP = 2.0 -- suspension rays start this far above the hub

local function part(parent, name, size, cf, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.Transparency = 1
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
	return w
end

local function motor(name: string, part0: BasePart, part1: BasePart, pivotWorld: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(pivotWorld)
	m.C1 = part1.CFrame:ToObjectSpace(pivotWorld)
	m.Parent = part0
	return m
end

function B.Build(kind: string): Model
	local L = B.Layout[kind]
	local cfg = Config.Vehicles[kind]
	local src = ServerStorage.VehicleImports:FindFirstChild(kind .. "_Asset")
	assert(src, "missing ServerStorage.VehicleImports." .. kind .. "_Asset")

	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("VehicleType", kind)

	-- Root: the hull collision box, carries all of the mass
	local rootCF = CFrame.new(L.Root[1]) * FACE
	local volume = L.Root[2].X * L.Root[2].Y * L.Root[2].Z
	local root = part(model, "Root", L.Root[2], rootCF, {
		CanCollide = true, CanQuery = true, CanTouch = true,
		CustomPhysicalProperties = PhysicalProperties.new(math.clamp(cfg.Mass / volume, 0.01, 100), 0.35, 0, 1, 1),
	})
	model.PrimaryPart = root
	for _, e in L.Extra do
		local c = part(model, e[1], e[3], CFrame.new(e[2]) * FACE, { CanCollide = true, CanQuery = true, CanTouch = false, Massless = true })
		weld(root, c)
	end

	-- visual meshes: copied as-is, made non-physical
	local meshes = {}
	for _, mp in src:GetDescendants() do
		if mp:IsA("MeshPart") then
			local c = mp:Clone()
			for _, ch in c:GetChildren() do
				if not (ch:IsA("SurfaceAppearance") or ch:IsA("Texture") or ch:IsA("Decal")) then
					ch:Destroy()
				end
			end
			c.Anchored = false
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.Massless = true
			c.Parent = model
			meshes[c.Name] = c
		end
	end
	for _, n in L.Static do
		weld(root, meshes[n])
	end
	-- shield shells: <Vehicle>_<Part>_Shield from the imported shell set, welded to their part
	local shellSet = ServerStorage.VehicleImports:FindFirstChild("Shields_Asset")
	if shellSet then
		for partName, mp in meshes do
			local sh = shellSet:FindFirstChild(kind .. "_" .. partName .. "_Shield", true)
			if sh and sh:IsA("MeshPart") then
				local c = sh:Clone()
				c:ClearAllChildren()
				c.Anchored = false
				c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = false, false, false, false
				c.Massless = true
				c.Transparency = 1
				c.Material = Enum.Material.ForceField
				c.Parent = model
				weld(mp, c)
			end
		end
	end

	if L.Yaw then
	-- weapon joints: yaw on the root, pitch on the yaw part. Pivots face +Z like the root.
	local yawPivot = CFrame.new(L.Yaw.Pivot) * FACE
	local pitchPivot = CFrame.new(L.Pitch.Pivot) * FACE
	motor("AimYaw", root, meshes[L.Yaw.Part], yawPivot)
	motor("AimPitch", meshes[L.Yaw.Part], meshes[L.Pitch.Part], pitchPivot)
	-- server-side math needs the same chain as plain offsets (root space)
	model:SetAttribute("YawPivot", rootCF:PointToObjectSpace(L.Yaw.Pivot))
	model:SetAttribute("PitchPivot", yawPivot:PointToObjectSpace(L.Pitch.Pivot))
	model:SetAttribute("MuzzleOffset", pitchPivot:PointToObjectSpace(L.Muzzle))
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = meshes[L.Pitch.Part].CFrame:ToObjectSpace(CFrame.new(L.Muzzle) * FACE)
	muzzle.Parent = meshes[L.Pitch.Part]
	else
		-- fixed gun mount (drone): the rounds still swing a little inside the weapon's limits
		local G = L.Gun
		local gp = CFrame.new(G.Pivot) * FACE
		local mid = (G.Muzzles[1] + G.Muzzles[2]) / 2
		model:SetAttribute("YawPivot", rootCF:PointToObjectSpace(G.Pivot))
		model:SetAttribute("PitchPivot", Vector3.zero)
		model:SetAttribute("MuzzleOffset", gp:PointToObjectSpace(mid))
		model:SetAttribute("BarrelSpread", (G.Muzzles[1] - G.Muzzles[2]).Magnitude / 2)
		for i, mp in G.Muzzles do
			local a = Instance.new("Attachment")
			a.Name = if i == 1 then "Muzzle" else "Muzzle" .. i
			a.CFrame = rootCF:ToObjectSpace(CFrame.new(mp) * FACE)
			a.Parent = root
		end
	end
	for _, r in L.Rotors or {} do
		local part = meshes[r[1]]
		local up = r[2].Unit
		local right = (Vector3.xAxis - up * up.X).Unit
		local pivot = CFrame.fromMatrix(part.Position, right, up)
		local j = motor("R_" .. r[1], root, part, pivot)
		j:SetAttribute("Rotor", true)
	end

	-- suspension points (+ a VectorForce each) and wheel joints
	local wheels = Instance.new("Folder")
	wheels.Name = "Wheels"
	wheels.Parent = model
	for i, w in L.Wheels do
		local name, hub, radius, steer, drive, mesh = w[1], w[2], w[3], w[4], w[5], w[6]
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = rootCF:PointToObjectSpace(hub + Vector3.new(0, SUSP_TOP, 0))
		a:SetAttribute("Radius", radius)
		a:SetAttribute("RideDistance", hub.Y + SUSP_TOP) -- ray length to the ground at design ride height
		a:SetAttribute("Steer", steer)
		a:SetAttribute("Drive", drive)
		a:SetAttribute("Side", if hub.X > 0 then 1 else -1) -- +1 left, -1 right
		a:SetAttribute("Order", i)
		a.Parent = root
		local f = Instance.new("VectorForce")
		f.Name = "F_" .. name
		f.Attachment0 = a
		f.RelativeTo = Enum.ActuatorRelativeTo.World
		f.ApplyAtCenterOfMass = false
		f.Force = Vector3.zero
		f.Parent = wheels
		if mesh and meshes[mesh] then
			local j = motor("J_" .. name, root, meshes[mesh], CFrame.new(meshes[mesh].Position) * FACE)
			j:SetAttribute("Wheel", name)
		end
	end
	local ca = Instance.new("Attachment")
	ca.Name = "Centre"
	ca.Parent = root
	local tq = Instance.new("Torque")
	tq.Name = "Stabilizer"
	tq.Attachment0 = ca
	tq.RelativeTo = Enum.ActuatorRelativeTo.World
	tq.Torque = Vector3.zero
	tq.Parent = wheels
	if cfg.Drive.Kind == "Flight" then
		local lift = Instance.new("VectorForce")
		lift.Name = "F_Lift"
		lift.Attachment0 = ca
		lift.RelativeTo = Enum.ActuatorRelativeTo.World
		lift.ApplyAtCenterOfMass = true
		lift.Force = Vector3.zero
		lift.Parent = wheels
	end

	-- seats (touch-sitting off: seats are only taken through the prompt)
	local seats = Instance.new("Folder")
	seats.Name = "Seats"
	seats.Parent = model
	for i, s in cfg.Seats do
		local seat = Instance.new("Seat")
		seat.Name = "Seat" .. i
		seat.Size = Vector3.new(2, 1, 2)
		seat.CFrame = CFrame.new(s.Pos) * FACE
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanTouch = false
		seat.CanQuery = false
		seat.Massless = true
		seat.Anchored = false
		seat:SetAttribute("SeatIndex", i)
		seat:SetAttribute("Role", s.Role)
		seat:SetAttribute("SeatName", s.Name)
		seat:SetAttribute("Hidden", s.Hidden)
		seat.Parent = seats
		weld(root, seat)
	end

	-- exits (ground level, vehicle space)
	for i, p in cfg.Exits do
		local a = Instance.new("Attachment")
		a.Name = "Exit" .. i
		a.Position = rootCF:PointToObjectSpace(p)
		a.Parent = root
	end

	-- the model pivots on the ground under its centre, facing +Z
	model.WorldPivot = FACE
	return model
end

-- shrink / grow a built model (Config.Scale) and keep every number that is not an instance in step:
-- turret offsets, suspension ride / radius, and the hull mass (density follows the new volume)
function B.ApplyScale(model: Model, kind: string)
	local sc = (Config.Scale and Config.Scale[kind]) or 1
	if sc == 1 then
		return
	end
	model:ScaleTo(sc)
	for _, n in { "YawPivot", "PitchPivot", "MuzzleOffset" } do
		model:SetAttribute(n, (model:GetAttribute(n) :: Vector3) * sc)
	end
	local root = model.PrimaryPart :: BasePart
	for _, a in root:GetChildren() do
		if a:IsA("Attachment") and a:GetAttribute("RideDistance") then
			a:SetAttribute("RideDistance", a:GetAttribute("RideDistance") * sc)
			a:SetAttribute("Radius", a:GetAttribute("Radius") * sc)
		end
	end
	local v = root.Size.X * root.Size.Y * root.Size.Z
	root.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(Config.Vehicles[kind].Mass / v, 0.01, 100), 0.35, 0, 1, 1)
	model:SetAttribute("Scale", sc)
end

function B.BuildAll()
	local folder = ServerStorage:FindFirstChild("Vehicles") or Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = ServerStorage
	local t = folder:FindFirstChild("Templates")
	if t then
		t:Destroy()
	end
	t = Instance.new("Folder")
	t.Name = "Templates"
	t.Parent = folder
	for kind in Config.Vehicles do
		local model = B.Build(kind)
		B.ApplyScale(model, kind)
		model.Parent = t
	end
	return t
end

return B
