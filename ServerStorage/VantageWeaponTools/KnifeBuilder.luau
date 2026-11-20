--[[
	VANTAGE — KnifeBuilder (edit-time)
	Builds the VK-7 balisong (butterfly knife) into ReplicatedStorage.Vantage.Weapons.Assets.Knife.
		require(game.ServerStorage.VantageWeaponTools.KnifeBuilder:Clone()).Build()

	Knife space: pivot pin at the origin, pin axis = Z (the parts stack along Z).
	Open (held) state: handles point down -Y, blade points up +Y.
	Parts:
		Handle  (PrimaryPart) "safe" handle, held by the hand. Attachment "Grip" follows Roblox's
		        RightGripAttachment convention (+Y = toward the blade / thumb side).
		Blade   hinged to Handle by Motor6D "BladeHinge" (rotation about Z, degrees in clips)
		Bite    the second handle, Motor6D "BiteHinge" (rotation about Z)
	Each moving piece's details are welded to it, so animating three motors flips the whole knife.
]]

local V = Vector3.new
local C = Color3.fromRGB
local A = CFrame.Angles
local CF = CFrame.new
local rad = math.rad
local SM = Enum.Material.SmoothPlastic

local COL = {
	Graphite = { Enum.Material.Metal, C(56, 61, 72) },
	White = { SM, C(232, 235, 240) },
	Dark = { SM, C(30, 33, 40) },
	Steel = { Enum.Material.Metal, C(196, 202, 212) },
	Edge = { SM, C(236, 240, 246) },
	Neon = { Enum.Material.Neon, C(40, 140, 255) },
}

local B = {}

function B.Build()
	local assets = game:GetService("ReplicatedStorage").Vantage.Weapons.Assets
	local old = assets:FindFirstChild("Knife")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Knife"
	local count = 0
	local function P(parent, name, size, cf, s, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Material = s[1]
		p.Color = s[2]
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if s == COL.Neon then
			p.CastShadow = false
		end
		if shape then
			p.Shape = shape
		end
		p.Parent = parent
		count += 1
		return p
	end
	local function group(name)
		local f = Instance.new("Model")
		f.Name = name
		f.Parent = model
		return f
	end

	-- safe handle (+Z side) — held
	local safe = group("SafeHandle")
	local handle = P(safe, "Handle", V(0.13, 0.98, 0.065), CF(0, -0.5, 0.05), COL.Graphite)
	P(safe, "SafeInlay", V(0.09, 0.72, 0.02), CF(0, -0.52, 0.09), COL.White)
	P(safe, "SafeAccent", V(0.02, 0.6, 0.022), CF(0.045, -0.52, 0.1), COL.Neon)
	P(safe, "SafeTip", V(0.14, 0.06, 0.07), CF(0, -1.0, 0.05), COL.Dark)
	P(safe, "PinCapSafe", V(0.02, 0.13, 0.13), CF(0, 0, 0.09) * A(0, rad(90), 0), COL.Dark, Enum.PartType.Cylinder)
	P(safe, "Latch", V(0.05, 0.14, 0.03), CF(0, -0.99, 0.0), COL.Steel)

	-- bite handle (-Z side)
	local biteG = group("BiteHandle")
	local bite = P(biteG, "Bite", V(0.13, 0.98, 0.065), CF(0, -0.5, -0.05), COL.Graphite)
	P(biteG, "BiteInlay", V(0.09, 0.72, 0.02), CF(0, -0.52, -0.09), COL.White)
	P(biteG, "BiteAccent", V(0.02, 0.6, 0.022), CF(-0.045, -0.52, -0.1), COL.Neon)
	P(biteG, "BiteTip", V(0.14, 0.06, 0.07), CF(0, -1.0, -0.05), COL.Dark)
	P(biteG, "PinCapBite", V(0.02, 0.13, 0.13), CF(0, 0, -0.09) * A(0, rad(90), 0), COL.Dark, Enum.PartType.Cylinder)

	-- blade (centre, z = 0)
	local bladeG = group("BladeGroup")
	local blade = P(bladeG, "Blade", V(0.15, 0.74, 0.024), CF(0, 0.43, 0), COL.Steel)
	P(bladeG, "Tang", V(0.11, 0.16, 0.026), CF(0, 0.02, 0), COL.Steel)
	P(bladeG, "Tip", V(0.106, 0.106, 0.023), CF(0.02, 0.8, 0) * A(0, 0, rad(45)), COL.Steel)
	P(bladeG, "EdgeBevel", V(0.035, 0.68, 0.026), CF(-0.06, 0.44, 0), COL.Edge)
	P(bladeG, "Fuller", V(0.025, 0.42, 0.027), CF(0.025, 0.4, 0), COL.Graphite)
	P(bladeG, "BladeGlow", V(0.012, 0.36, 0.028), CF(0.052, 0.42, 0), COL.Neon)

	-- pin + attachments
	P(safe, "Pin", V(0.2, 0.05, 0.05), CF(0, 0, 0) * A(0, rad(90), 0), COL.Steel, Enum.PartType.Cylinder)
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.CFrame = handle.CFrame:ToObjectSpace(CF(0, -0.55, 0))
	grip.Parent = handle
	local tipAtt = Instance.new("Attachment")
	tipAtt.Name = "Tip"
	tipAtt.CFrame = blade.CFrame:ToObjectSpace(CF(0, 0.85, 0))
	tipAtt.Parent = blade

	-- welds: details to their moving piece; hinges to the safe handle
	local function weldGroup(g, root)
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	weldGroup(safe, handle)
	weldGroup(biteG, bite)
	weldGroup(bladeG, blade)
	local pivot = CF(0, 0, 0)
	local function hinge(name, part)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = handle
		m.Part1 = part
		m.C0 = handle.CFrame:ToObjectSpace(pivot)
		m.C1 = part.CFrame:ToObjectSpace(pivot)
		m.Parent = handle
	end
	hinge("BladeHinge", blade)
	hinge("BiteHinge", bite)

	model.PrimaryPart = handle
	model:SetAttribute("Weapon", "Knife")
	model.Parent = assets
	return "Knife built: " .. count .. " parts"
end

return B
