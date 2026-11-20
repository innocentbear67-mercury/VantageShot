--[[
	WeaponAssetKit.Build(id) -> Model
	Wraps ServerStorage.WeaponImports.<id>.Mesh (the untouched Tripo MeshPart) into the weapon asset
	convention: Model <id>, PrimaryPart "Root" (invisible), the mesh welded to Root, and Root
	attachments Handle / Support / SupportTP / Muzzle / ADSPoint / EjectPoint / Shoulder / Magazine
	(+ any extra points, e.g. Bolt). Root space: forward = -Z, up = +Y, right = +X.
]]
local Specs = require(script.Parent.Specs)
local rad = math.rad

local Build = {}

-- Blender centre of each split Body (bounding box), from the Blender cut (2026-11-14)
local SPLIT_BODY_CENTER = {
	Vanguard = { 0.0, 0.00244, 0.1958 },
	Sentinel = { 0.0, 0.0, 0.21265 },
	Spectre = { 0.0, 0.00269, 0.36108 },
	Longshot = { 0.0, 0.0188, 0.15796 },
	Breacher = { 0.0, 0.0, 0.13306 },
	Arc = { 0.0, 0.0, 0.15308 },
}

-- XYZ Euler (CFrame.Angles), the same order the original VX-01 attachments were authored in
local function rot(v: Vector3?): CFrame
	v = v or Vector3.zero
	return CFrame.Angles(rad(v.X), rad(v.Y), rad(v.Z))
end

function Build.Make(id: string): Model
	local spec = assert(Specs[id], "no spec for " .. id)
	local src = game.ServerStorage.WeaponImports[id]:FindFirstChild("Mesh")
	assert(src and src:IsA("MeshPart"), "import missing for " .. id)
	local k = spec.Length / src.Size.X
	local h = src.Size.Y -- normalised height (mesh length is 1)
	-- split import (2026-11-14): Body + real moving parts (Mag / Charge / Bolt / Slide / Pump / Cell)
	-- cut in Blender. Each part keeps its exact place relative to the original single mesh.
	local split = game.ServerStorage.WeaponImports[id]:FindFirstChild("Split")
	local splitOrigin, sk
	if split and SPLIT_BODY_CENTER[id] then
		local bc = SPLIT_BODY_CENTER[id]
		-- import space is centimetres, x mirrored like the single mesh; the original mesh's centre is
		-- Blender (0, 0, h/2); the Body's centre is Blender bc
		splitOrigin = split.Body.Position + Vector3.new(bc[1] * 100, (h / 2 - bc[3]) * 100, (0 - bc[2]) * 100)
		sk = k / 100
	end
	local mesh = if split then split.Body:Clone() else src:Clone()
	mesh.Size = if split then split.Body.Size * sk else src.Size * k
	-- mesh-local point for a normalised (x, z) pair. Roblox's FBX import mirrors the length axis
	-- relative to Blender (where the points were measured), so x is negated here.
	local function localPt(p)
		-- optional p[3] = sideways offset (Blender y) for parts that are off the centreline
		-- (NOT negated: verified by looking down the built sight line in Studio, 2026-11-08 — the
		-- negated version put the VX-01 window and the SR-88 eyepiece on the wrong side)
		return Vector3.new(-p[1] * k, (p[2] - h / 2) * k, (p[3] or 0) * k)
	end
	-- muzzle at Blender -X = Roblox mesh +X -> Root -Z (yaw +90); otherwise yaw -90. Then level the
	-- sight line by rolling about the mesh's thickness axis (+Pitch raises the muzzle).
	local yaw = if spec.MuzzleDir < 0 then 90 else -90
	local pitchSign = if spec.MuzzleDir < 0 then 1 else -1
	local R = CFrame.Angles(0, rad(yaw), 0) * CFrame.Angles(0, 0, rad((spec.Pitch or 0) * pitchSign))
	local offset = spec.Anchor - R:PointToWorldSpace(localPt(spec.Points.Handle))
	local meshCF = CFrame.new(offset) * R

	local model = Instance.new("Model")
	model.Name = id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
	root.Anchored = true
	root.Massless = true
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	mesh.Name = "Mesh"
	mesh.Anchored = true
	mesh.CanCollide, mesh.CanQuery, mesh.CanTouch = false, false, false
	mesh.Massless = true
	mesh.CFrame = if split then meshCF * CFrame.new((split.Body.Position - splitOrigin) * sk) else meshCF
	mesh.Parent = model
	local function placeSplit(p: BasePart): BasePart
		local c = p:Clone()
		c.Size = p.Size * sk
		c.CFrame = meshCF * CFrame.new((p.Position - splitOrigin) * sk)
		c.Anchored = true
		c.CanCollide, c.CanQuery, c.CanTouch = false, false, false
		c.Massless = true
		return c
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = mesh
	weld.Parent = mesh

	for name, p in spec.Points do
		local a = Instance.new("Attachment")
		a.Name = name
		local r = CFrame.identity
		if name == "Handle" then
			r = rot(spec.HandleRot or Vector3.new(-18, 0, 0))
		elseif name == "Support" then
			-- spun about the handguard axis so the first-person support hand cups it from below and
			-- its forearm drops down behind the gun
			r = rot(spec.SupportRot or Vector3.new(-90, -90, 0)) * CFrame.Angles(0, rad(spec.SupportSpin or -75), 0)
		elseif name == "SupportTP" or name == "Magazine" then
			r = rot(spec.SupportRot or Vector3.new(-90, -90, 0))
		end
		local pos = meshCF:PointToWorldSpace(localPt(p))
		if name == "EjectPoint" then
			pos += Vector3.new(src.Size.Z * k * 0.5, 0, 0) -- on the right-hand side of the receiver
		end
		a.CFrame = CFrame.new(pos) * r
		a.Parent = root
	end
	-- reload magazine prop (the Tripo mesh is untouched): a separate box sized to sit just inside the
	-- mesh's own magazine, so it is hidden at rest and is what the hand pulls out / seats on a reload
	-- split: the real magazine and the moving parts
	if split then
		local magPart = split:FindFirstChild("Mag") or split:FindFirstChild("Cell")
		if magPart then
			local mag = Instance.new("Model")
			mag.Name = "Magazine"
			local body = placeSplit(magPart)
			body.Name = "MagBody"
			body.Parent = mag
			mag.PrimaryPart = body
			local magAtt = root:FindFirstChild("Magazine")
			local g = Instance.new("Attachment")
			g.Name = "MagGrip"
			g.CFrame = body.CFrame:ToObjectSpace(magAtt and magAtt.WorldCFrame or body.CFrame)
			g.Parent = body
			mag:SetAttribute("Real", true)
			mag.Parent = model
		end
		for _, n in { "Charge", "Bolt", "Slide", "Pump" } do
			local p = split:FindFirstChild(n)
			if p then
				local c = placeSplit(p)
				c.Name = n
				c:SetAttribute("MovingPart", n)
				c.Parent = model
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = root, c
				w.Parent = c
			end
		end
	end
	if spec.MagProp and not split then
		local P = spec.MagProp
		local top = meshCF:PointToWorldSpace(localPt(P.Top))
		local bot = meshCF:PointToWorldSpace(localPt(P.Bottom))
		local up = (top - bot).Unit
		local back = Vector3.zAxis - up * up.Z
		back = back.Unit
		local right = up:Cross(back)
		local len = (top - bot).Magnitude
		local mag = Instance.new("Model")
		mag.Name = "Magazine"
		local body = Instance.new("Part")
		body.Name = "MagBody"
		body.Size = Vector3.new(P.Width * k, len, P.Depth * k)
		body.CFrame = CFrame.fromMatrix((top + bot) / 2, right, up, back)
		body.Color = P.Color or Color3.fromRGB(38, 41, 47)
		body.Material = Enum.Material.Metal
		body.Anchored = true
		body.CanCollide, body.CanQuery, body.CanTouch = false, false, false
		body.Massless = true
		body.Parent = mag
		-- base plate: slightly wider lip at the bottom so it reads as a magazine in flight
		local base = body:Clone()
		base.Name = "MagBase"
		base.Size = Vector3.new(P.Width * k * 1.15, math.max(0.04, len * 0.07), P.Depth * k * 1.08)
		base.CFrame = body.CFrame * CFrame.new(0, -len / 2 + base.Size.Y / 2, 0)
		base.Color = P.BaseColor or Color3.fromRGB(26, 28, 32)
		base.Parent = mag
		local bw = Instance.new("WeldConstraint")
		bw.Part0, bw.Part1 = body, base
		bw.Parent = base
		mag.PrimaryPart = body
		-- support-hand grip on the mag: the same pose the hand used on the old Magazine point
		local magAtt = root:FindFirstChild("Magazine")
		local g = Instance.new("Attachment")
		g.Name = "MagGrip"
		g.CFrame = body.CFrame:ToObjectSpace(magAtt and magAtt.WorldCFrame or (body.CFrame * CFrame.new(0, -len * 0.3, 0)))
		g.Parent = body
		mag.Parent = model
	end
	model:SetAttribute("Source", "Tripo")
	model:SetAttribute("Split", split ~= nil)
	model:SetAttribute("ModelAssetId", src:GetAttribute("ModelAssetId"))
	model:SetAttribute("Length", spec.Length)
	return model
end

-- Build and install into ReplicatedStorage.Vantage.Weapons.Assets (replacing any existing asset;
-- a replaced non-Tripo asset is kept in ServerStorage.WeaponAssetKit.Replaced).
function Build.Install(id: string, assetName: string?)
	local assets = game.ReplicatedStorage.Vantage.Weapons.Assets
	local name = assetName or id
	local m = Build.Make(id)
	m.Name = name
	local old = assets:FindFirstChild(name)
	if old then
		if old:GetAttribute("Source") ~= "Tripo" then
			local keep = script.Parent:FindFirstChild("Replaced") or Instance.new("Folder")
			keep.Name = "Replaced"
			keep.Parent = script.Parent
			old.Parent = keep
		else
			old:Destroy()
		end
	end
	m.Parent = assets
	return m
end

return Build
