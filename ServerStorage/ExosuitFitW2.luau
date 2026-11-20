--[[
	ExosuitFitW2 (2026-11-14): installs the five reference-sheet suits (Onyx, Ranger, Nightowl, Crimson,
	Paladin) from the import of VantageSuits_W2.fbx (MeshParts named <Suit>__<BodyPart>__<Slot>).
	The import keeps the pieces' layout, only scaled (Roblox's importer: 100x) and moved, so one reference
	piece with a known rest centre/size gives the scale and origin for all of them.
	Fit.Build(import, rig, fpArms) -> { [suit] = count }  fills ReplicatedStorage.Vantage.Armour.Pieces.<Suit>:
	  piece names "<Base>__<Slot>" (Chest__Graphite, UpperArm_R__Base, ...), the visor "Visor";
	  attributes Bone, Offset (from the rig's rest pose), Slot; arm pieces FPOffset / FPSize (first person).
	Camo slots keep the imported TextureID; every other piece gets its colour / material from Fit.Suits.
]]
local Fit = {}

local SP, MT, NE = Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Neon
local function L(r, g, b, mat, refl)
	return { Color = Color3.fromRGB(r, g, b), Material = mat or SP, Reflectance = refl or 0 }
end

Fit.Suits = {
	Onyx = { Name = "ONYX", Tag = "MK II  //  NIGHT OPS", Swatch = Color3.fromRGB(34, 36, 42),
		Description = "Blacked-out plating, a lit octagonal core and a lime visor.",
		Slots = { Base = L(34, 36, 42), Graphite = L(46, 48, 54), Gunmetal = L(26, 27, 31), Black = L(14, 14, 16),
			Accent = L(80, 84, 92), Energy = L(215, 240, 255, NE), Visor = L(120, 225, 40, NE) } },
	Ranger = { Name = "RANGER", Tag = "WOODLAND  //  FIELD ISSUE", Swatch = Color3.fromRGB(70, 104, 58),
		Description = "Olive plating over a woodland-camo undersuit and a gold-mirrored visor.",
		Slots = { Base = L(255, 255, 255), Graphite = L(50, 76, 42), Gunmetal = L(58, 46, 34), Black = L(22, 20, 16),
			Accent = L(100, 108, 78), Energy = L(255, 200, 90, NE), Visor = L(214, 160, 50, MT, 0.35) } },
	Nightowl = { Name = "NIGHTOWL", Tag = "URBAN  //  RECON", Swatch = Color3.fromRGB(118, 122, 128),
		Description = "Digital urban camo, a sealed rebreather and quad night-vision optics.",
		Slots = { Base = L(255, 255, 255), Graphite = L(255, 255, 255), Gunmetal = L(62, 64, 70), Black = L(16, 16, 18),
			Accent = L(110, 114, 120), Energy = L(90, 255, 120, NE), Visor = L(16, 16, 18) } },
	Crimson = { Name = "CRIMSON", Tag = "VANGUARD  //  ASSAULT", Swatch = Color3.fromRGB(170, 18, 26),
		Description = "Gunmetal plating with gold inlays and a red combat visor.",
		Slots = { Base = L(48, 50, 54), Graphite = L(64, 66, 70), Gunmetal = L(36, 37, 40), Black = L(14, 14, 16),
			Accent = L(200, 155, 80, MT), Energy = L(255, 80, 60, NE), Visor = L(140, 8, 16, SP, 0.08) } },
	Paladin = { Name = "PALADIN", Tag = "HONOUR GUARD  //  COMMAND", Swatch = Color3.fromRGB(30, 42, 82),
		Description = "Navy undersuit, polished silver plate, gold trim and an ice-blue visor.",
		Slots = { Base = L(22, 32, 62), Graphite = L(140, 146, 158, MT), Gunmetal = L(44, 50, 64), Black = L(14, 15, 20),
			Accent = L(210, 168, 96, MT), Energy = L(190, 235, 255, NE), Visor = L(150, 215, 255, NE) } },
}
Fit.Order = { "Onyx", "Ranger", "Nightowl", "Crimson", "Paladin" }

-- uploaded replacement textures (the embedded camo read too light in Roblox lighting).
-- Nightowl plates: own image 84893325895317 failed to load on 2026-11-14 (moderation?), so plates use the
-- base camo until it loads; then set Graphite back to "rbxassetid://84893325895317".
Fit.Textures = {
	Nightowl = { Base = "rbxassetid://90835195890453", Graphite = "rbxassetid://90835195890453" },
}

-- reference pieces: rest centre / size relative to the root, from the Blender export
Fit.Ref = {
	{ Name = "Onyx__Head__Black", C = Vector3.new(0, 1.505, -0.08), S = Vector3.new(1.79, 1.13, 1.0) },
	{ Name = "Onyx__RightFoot__Black", C = Vector3.new(0.5, -2.97, -0.04), S = Vector3.new(1.08, 0.06, 1.16) },
}

Fit.BaseName = {
	Head = "Helmet", UpperTorso = "Chest", LowerTorso = "Belt",
	RightUpperArm = "UpperArm_R", LeftUpperArm = "UpperArm_L", RightLowerArm = "Gauntlet_R", LeftLowerArm = "Gauntlet_L",
	RightHand = "Glove_R", LeftHand = "Glove_L", RightUpperLeg = "Thigh_R", LeftUpperLeg = "Thigh_L",
	RightLowerLeg = "Shin_R", LeftLowerLeg = "Shin_L", RightFoot = "Boot_R", LeftFoot = "Boot_L",
}

local FP_XZ = 0.55

local function fpFit(p: BasePart, boneName: string, rig: Model, fp: Model)
	local side = if boneName:find("Right") then "Right" else "Left"
	local b, fb = rig:FindFirstChild(boneName), fp:FindFirstChild(boneName)
	if not (b and fb) then return end
	local eb = b[side .. "ElbowRigAttachment"].Position
	local ef = fb[side .. "ElbowRigAttachment"].Position
	local ky
	if boneName:find("Upper") then
		ky = fb.Size.Y / (b[side .. "ShoulderRigAttachment"].Position.Y - eb.Y)
	else
		ky = fb.Size.Y / (eb.Y - b[side .. "WristRigAttachment"].Position.Y)
	end
	local off = p:GetAttribute("Offset")
	local d = off.Position - eb
	p:SetAttribute("FPOffset", CFrame.new(ef + Vector3.new(d.X * FP_XZ, d.Y * ky, d.Z * FP_XZ)) * off.Rotation)
	p:SetAttribute("FPSize", Vector3.new(p.Size.X * FP_XZ, p.Size.Y * ky, p.Size.Z * FP_XZ))
end

function Fit.Build(import: Instance, rig: Model, fp: Model?)
	local r1 = import:FindFirstChild(Fit.Ref[1].Name, true) :: BasePart
	local r2 = import:FindFirstChild(Fit.Ref[2].Name, true) :: BasePart
	assert(r1 and r2, "reference pieces missing from the import")
	local scale = r1.Size.X / Fit.Ref[1].S.X
	local origin = r1.Position - Fit.Ref[1].C * scale
	-- check with the second reference. Roblox's FBX import comes in mirrored left-right (the whole scene,
	-- geometry included): a "Right" mesh then sits at -x with the left-hand shape, so it is the left piece.
	local c2 = (r2.Position - origin) / scale
	local mirrored = false
	if (c2 - Fit.Ref[2].C).Magnitude >= 0.02 then
		local m = Vector3.new(-Fit.Ref[2].C.X, Fit.Ref[2].C.Y, Fit.Ref[2].C.Z)
		assert((c2 - m).Magnitude < 0.02, "import layout check failed: " .. tostring(c2))
		mirrored = true
	end
	local rest = rig.HumanoidRootPart.CFrame
	local piecesRoot = game.ReplicatedStorage.Vantage.Armour.Pieces
	local counts = {}
	for _, suit in Fit.Order do
		local old = piecesRoot:FindFirstChild(suit)
		if old then old:Destroy() end
		local f = Instance.new("Folder")
		f.Name = suit
		counts[suit] = 0
		for _, mp in import:GetDescendants() do
			if mp:IsA("MeshPart") then
				local s, part, slot = string.match(mp.Name, "^(%w+)__(%w+)__(%w+)$")
				if s == suit and mirrored then
					if part:find("^Right") then
						part = "Left" .. part:sub(6)
					elseif part:find("^Left") then
						part = "Right" .. part:sub(5)
					end
				end
				if s == suit then
					local p = mp:Clone()
					p:ClearAllChildren()
					local c = (mp.Position - origin) / scale
					p.Size = mp.Size / scale
					p.Name = if slot == "Visor" then "Visor" else Fit.BaseName[part] .. "__" .. slot
					local look = Fit.Suits[suit].Slots[slot]
					if p.TextureID ~= "" then
						local ov = Fit.Textures[suit]
						if ov and ov[slot] then
							p.TextureID = ov[slot]
						end
						p.Color = Color3.new(1, 1, 1)
						p.Material = SP
					elseif look then
						p.Color, p.Material, p.Reflectance = look.Color, look.Material, look.Reflectance
					end
					p.CastShadow = slot ~= "Energy" and slot ~= "Visor"
					p.Anchored = true
					p.CFrame = rest * CFrame.new(c)
					local bone = rig:FindFirstChild(part) :: BasePart
					p:SetAttribute("Bone", part)
					p:SetAttribute("Offset", bone.CFrame:ToObjectSpace(p.CFrame))
					p:SetAttribute("Slot", slot)
					if fp and (part:find("UpperArm") or part:find("LowerArm")) then
						fpFit(p, part, rig, fp)
					end
					p.Parent = f
					counts[suit] += 1
				end
			end
		end
		f.Parent = piecesRoot
	end
	return counts
end

return Fit
