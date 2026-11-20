--[[
	VANTAGE — ForgeBuilds (Studio build tool)
	One builder per weapon in the Forge art direction (see ForgeKit for the shared language).

	Usage (command bar / MCP):
	  local Kit = require(game.ServerStorage.VantageWeaponTools.ForgeKit:Clone())
	  local Builds = require(game.ServerStorage.VantageWeaponTools.ForgeBuilds:Clone())
	  local model = Builds.Vanguard(Kit, CFrame.new(...), oldAssetForMagGrip)

	ASSET CONTRACT (unchanged from the Tripo guns, so every consumer keeps working)
	  Root (invisible PrimaryPart) with Handle / Support / SupportTP / Muzzle / ADSPoint /
	  EjectPoint / Shoulder / Magazine (+ WindowA/B, LensEdge, Bolt where the gun has them)
	  Magazine model (Real = true, PrimaryPart MagBody + MagGrip attachment)
	  moving parts carry MovingPart = "Charge" | "Bolt" | "Slide" | "Pump" (one part each)
	FORGE ADDITIONS
	  every visible part sits in a component Model (Receiver, Handguard, Barrel, Optic, Stock,
	  Grip, Magazine — attribute Component) and carries a Role attribute (see ForgeKit).
	  Root has Socket_<Component> attachments: the origin each component is authored around, so
	  a legendary barrel / optic / stock can be swapped in without touching the rest.
	  Model attributes: SkinSchema = "Roles", ArtStyle = "Forge", ArtVersion.
	Root space: -Z = muzzle, +Y = up, +X = the gun's right (ejection) side. Studs at asset scale.
]]
local V = Vector3.new
local R = math.rad

local Builds = {}

local function newModel(name: string, O: CFrame)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide, root.CanQuery, root.CanTouch, root.Massless = false, false, false, true
	root.CFrame = O
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

local function attach(root: BasePart, name: string, cf: CFrame)
	local a = root:FindFirstChild(name) or Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = root
	return a
end

-- welds: magazine parts to MagBody, everything else to Root (WeaponService re-welds its clone)
local function weldAll(model: Model, root: BasePart)
	local mag = model:FindFirstChild("Magazine")
	local magBody = mag and mag.PrimaryPart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and d ~= magBody then
			local w = Instance.new("WeldConstraint")
			w.Part0 = if mag and d:IsDescendantOf(mag) then magBody else root
			w.Part1 = d
			w.Parent = d
		end
	end
end

-- ═══ VX-01 VANGUARD — assault rifle (benchmark) ═══════════════════════════════════════════
-- Identity: a split ceramic hood that peaks at an integrated, forward-raked holo visor; panel
-- seams all raked at one angle (top back, bottom forward) so the gun leans into the target; a
-- segmented handguard over slanted vent fins ending in a hooked under-barrel "jaw"; a slotted
-- wedge brake behind a cyan emitter ring; a forward-raked energy-cell magazine; and a skeletal
-- triangle stock with a raked butt.
function Builds.Vanguard(Kit, origin: CFrame?, oldAsset: Model?)
	local O = origin or CFrame.new()
	local BV = Kit.Bevel
	local model, root = newModel("Vanguard", O)
	local comps = {}
	local function comp(name)
		local c = comps[name]
		if not c then
			c = Instance.new("Model")
			c.Name = name
			c:SetAttribute("Component", name)
			c.Parent = model
			comps[name] = c
		end
		return c
	end
	local function B(c, name, role, center, size, o)
		o = o or {}
		local cf = O * (o.CF or (CFrame.new(center) * (o.Rot or CFrame.identity)))
		return Kit.Block(comp(c), { Name = name, Role = role, Size = size, CFrame = cf, Bevel = o.Bevel, Axes = o.Axes, Cuts = o.Cuts, Holes = o.Holes, Smooth = o.Smooth })
	end
	-- cut through two root-space (y, z) points of an unrotated block centred at (cy, cz);
	-- (oy, oz) = the corner that is removed
	local function cyz(cy, cz, y1, z1, y2, z2, oy, oz)
		return Kit.CutYZ(y1 - cy, z1 - cz, y2 - cy, z2 - cz, oy - cy, oz - cz)
	end
	local function sides(fn)
		fn(-1, "L")
		fn(1, "R")
	end
	local RAKE = 0.5 -- seam rake: dz per dy (top toward the stock), shared by every panel end
	local yield = task.wait

	-- ── RECEIVER ────────────────────────────────────────────────────────────────────────
	B("Receiver", "Core", "Frame", V(0, 0.03, -0.06), V(0.24, 0.50, 1.18), { Bevel = BV.M, Cuts = {
		cyz(0.03, -0.06, -0.22, 0.36, 0.0, 0.53, -0.22, 0.53),
	} })
	-- split hood: the front half is the tallest block on the gun, the rear half steps down
	B("Receiver", "HoodFront", "Armor", V(0, 0.265, -0.42), V(0.29, 0.21, 0.64), { Bevel = BV.L, Cuts = {
		cyz(0.265, -0.42, 0.37, -0.56, 0.16, -0.76, 0.37, -0.76),
		cyz(0.265, -0.42, 0.37, -0.10, 0.16, -0.205, 0.16, -0.10),
	} })
	B("Receiver", "HoodRear", "Armor", V(0, 0.255, 0.18), V(0.29, 0.19, 0.64), { Bevel = BV.L, Cuts = {
		cyz(0.255, 0.18, 0.35, -0.065, 0.16, -0.16, 0.35, -0.16),
		cyz(0.255, 0.18, 0.35, 0.20, 0.21, 0.50, 0.35, 0.50),
	} })
	sides(function(s, k)
		B("Receiver", "HoodGlow" .. k, "Glow", V(s * 0.1435, 0.245, -0.41), V(0.008, 0.012, 0.42))
		B("Receiver", "HoodSeam" .. k, "Dark", V(s * 0.1435, 0.295, 0.11), V(0.008, 0.012, 0.30))
	end)
	B("Receiver", "ChargeSlot", "Dark", V(-0.1435, 0.215, 0.385), V(0.008, 0.032, 0.21))
	local charge = B("Receiver", "Charge", "Accent", V(-0.166, 0.215, 0.33), V(0.05, 0.042, 0.09), { Bevel = BV.S })
	charge:SetAttribute("MovingPart", "Charge")
	B("Receiver", "EjectPort", "Dark", V(0.1215, 0.10, -0.17), V(0.01, 0.07, 0.26))
	B("Receiver", "PortCover", "Metal", V(0.126, 0.145, -0.17), V(0.012, 0.014, 0.28), { Bevel = 0.004 })
	B("Receiver", "Deflector", "Frame", V(0.13, 0.10, 0.0), V(0.04, 0.08, 0.06), { Bevel = BV.S })
	yield()
	-- lower armour: trapezoid plates (front raked with the magazine, rear raked with the grip)
	sides(function(s, k)
		B("Receiver", "SidePlate" .. k, "Armor", V(s * 0.128, -0.10, -0.185), V(0.03, 0.22, 0.73), { Bevel = BV.M, Cuts = {
			cyz(-0.10, -0.185, 0.01, -0.46, -0.21, -0.55, 0.01, -0.55),
			cyz(-0.10, -0.185, 0.01, 0.09, -0.21, 0.18, 0.01, 0.18),
		} })
		B("Receiver", "PinF" .. k, "Metal", V(s * 0.144, -0.035, -0.40), V(0.008, 0.026, 0.026), { Bevel = 0.005 })
		B("Receiver", "PinR" .. k, "Metal", V(s * 0.144, -0.035, 0.06), V(0.008, 0.026, 0.026), { Bevel = 0.005 })
	end)
	B("Receiver", "BoltHousing", "Frame", V(-0.127, 0.09, -0.30), V(0.016, 0.09, 0.56), { Bevel = 0.006, Cuts = {
		cyz(0.09, -0.30, 0.135, -0.54, 0.045, -0.585, 0.135, -0.585),
		cyz(0.09, -0.30, 0.135, -0.03, 0.045, -0.015, 0.135, -0.015),
	} })
	B("Receiver", "BoltGlow", "Glow", V(-0.1355, 0.09, -0.32), V(0.004, 0.01, 0.36))
	B("Receiver", "StatusPanel", "Dark", V(-0.1445, -0.10, -0.17), V(0.006, 0.09, 0.15))
	for i, y in { -0.07, -0.10, -0.13 } do
		B("Receiver", "StatusPip" .. i, "Glow", V(-0.1465, y, -0.17 + (i - 2) * 0.012), V(0.004, 0.014, 0.10))
	end
	B("Receiver", "Selector", "Accent", V(-0.128, 0.05, 0.27), V(0.02, 0.028, 0.07), { Bevel = 0.006, Rot = CFrame.Angles(R(-25), 0, 0) })
	B("Receiver", "MagWell", "Frame", V(0, -0.30, -0.395), V(0.25, 0.16, 0.55), { Bevel = BV.M, Cuts = {
		cyz(-0.30, -0.395, -0.22, -0.60, -0.38, -0.67, -0.22, -0.67),
	} })
	B("Receiver", "MagWellLip", "Armor", V(0, -0.366, -0.375), V(0.27, 0.035, 0.47), { Bevel = BV.S, Cuts = {
		cyz(-0.366, -0.375, -0.348, -0.585, -0.384, -0.61, -0.348, -0.61),
	} })
	B("Receiver", "MagWellMouth", "Dark", V(0, -0.386, -0.36), V(0.155, 0.006, 0.34))
	B("Receiver", "MagRelease", "Accent", V(0.132, -0.25, -0.10), V(0.02, 0.04, 0.04), { Bevel = 0.006 })
	B("Receiver", "TriggerGuard", "Frame", V(0, -0.40, 0.075), V(0.06, 0.035, 0.37), { Bevel = BV.S })
	B("Receiver", "Trigger", "Metal", V(0, -0.325, 0.11), V(0.028, 0.09, 0.03), { Bevel = 0.006, Rot = CFrame.Angles(R(-18), 0, 0) })
	yield()

	-- ── GRIP ────────────────────────────────────────────────────────────────────────────
	local gripCF = CFrame.new(0, -0.482, 0.387) * CFrame.Angles(R(-15), 0, 0)
	B("Grip", "Body", "Grip", nil, V(0.15, 0.58, 0.19), { CF = gripCF, Bevel = BV.L, Cuts = { Kit.CutYZ(-0.29, -0.04, -0.22, -0.095, -0.29, -0.095) } })
	B("Grip", "Backstrap", "Armor", nil, V(0.16, 0.46, 0.05), { CF = gripCF * CFrame.new(0, 0.0, 0.085), Bevel = BV.M })
	B("Grip", "Ridge1", "Frame", nil, V(0.155, 0.022, 0.03), { CF = gripCF * CFrame.new(0, -0.02, -0.095), Bevel = 0.006 })
	B("Grip", "Ridge2", "Frame", nil, V(0.155, 0.022, 0.03), { CF = gripCF * CFrame.new(0, -0.14, -0.095), Bevel = 0.006 })
	B("Grip", "Cap", "Frame", nil, V(0.17, 0.045, 0.23), { CF = gripCF * CFrame.new(0, -0.29, 0.005), Bevel = BV.M })
	yield()

	-- ── HANDGUARD ───────────────────────────────────────────────────────────────────────
	B("Handguard", "Core", "Frame", V(0, 0.06, -1.32), V(0.24, 0.36, 1.20), { Bevel = BV.M, Cuts = {
		cyz(0.06, -1.32, 0.24, -1.80, -0.12, -1.92, 0.24, -1.92),
	} })
	B("Handguard", "TopPlateA", "Armor", V(0, 0.24, -1.03), V(0.27, 0.12, 0.60), { Bevel = BV.L, Cuts = {
		cyz(0.24, -1.03, 0.30, -0.73, 0.18, -0.73 - 0.12 * RAKE, 0.18, -0.73),
		cyz(0.24, -1.03, 0.30, -1.25, 0.18, -1.25 - 0.12 * RAKE, 0.30, -1.33),
	} })
	B("Handguard", "TopPlateB", "Armor", V(0, 0.235, -1.58), V(0.27, 0.11, 0.58), { Bevel = BV.L, Cuts = {
		cyz(0.235, -1.58, 0.29, -1.285, 0.18, -1.285 - 0.11 * RAKE, 0.18, -1.29),
		cyz(0.235, -1.58, 0.29, -1.66, 0.18, -1.87, 0.29, -1.87),
	} })
	B("Handguard", "SeamGlow", "Glow", V(0, 0.24, -1.296), V(0.19, 0.12, 0.012), { Rot = CFrame.Angles(R(26.6), 0, 0) })
	sides(function(s, k)
		B("Handguard", "Vent" .. k, "Dark", V(s * 0.1215, 0.07, -1.30), V(0.01, 0.13, 0.62))
		for i = 0, 4 do
			B("Handguard", "Fin" .. k .. i, "Frame", V(s * 0.126, 0.07, -1.06 - i * 0.12), V(0.016, 0.122, 0.026), { Rot = CFrame.Angles(R(26.6), 0, 0), Bevel = 0.005 })
		end
		B("Handguard", "Skirt" .. k, "Armor", V(s * 0.13, -0.065, -1.295), V(0.03, 0.10, 1.01), { Bevel = BV.M, Cuts = {
			cyz(-0.065, -1.295, -0.015, -1.75, -0.115, -1.80, -0.015, -1.80),
			cyz(-0.065, -1.295, -0.015, -0.79, -0.115, -0.84, -0.115, -0.79),
		} })
		B("Handguard", "SkirtGlow" .. k, "Glow", V(s * 0.1465, -0.065, -1.25), V(0.006, 0.012, 0.66))
	end)
	-- hooked under-barrel jaw: the Vanguard's signature profile
	B("Handguard", "Jaw", "Armor", V(0, -0.04, -1.96), V(0.20, 0.12, 0.52), { Bevel = BV.M, Cuts = {
		cyz(-0.04, -1.96, 0.02, -2.22, -0.10, -2.10, -0.10, -2.22),
		cyz(-0.04, -1.96, 0.02, -2.17, -0.01, -2.22, 0.02, -2.22),
	} })
	sides(function(s, k)
		B("Handguard", "JawGlow" .. k, "Glow", V(s * 0.1015, -0.035, -1.98), V(0.006, 0.012, 0.24))
	end)
	B("Handguard", "NoseRing", "Frame", V(0, 0.11, -1.97), V(0.15, 0.15, 0.10), { Bevel = BV.M })
	yield()

	-- ── BARREL ──────────────────────────────────────────────────────────────────────────
	B("Barrel", "Shroud", "Frame", V(0, 0.108, -2.235), V(0.10, 0.10, 0.43), { Bevel = 0.025, Axes = "z" })
	B("Barrel", "Band1", "Metal", V(0, 0.108, -2.10), V(0.112, 0.112, 0.022), { Bevel = 0.02, Axes = "z" })
	B("Barrel", "Band2", "Metal", V(0, 0.108, -2.33), V(0.112, 0.112, 0.022), { Bevel = 0.02, Axes = "z" })
	B("Barrel", "EmitterRing", "Glow", V(0, 0.108, -2.455), V(0.125, 0.125, 0.022), { Bevel = 0.025, Axes = "z" })
	B("Barrel", "Brake", "Frame", V(0, 0.108, -2.695), V(0.15, 0.15, 0.45), { Bevel = BV.M, Cuts = {
		cyz(0.108, -2.695, 0.183, -2.78, 0.13, -2.92, 0.183, -2.92),
		cyz(0.108, -2.695, 0.033, -2.78, 0.086, -2.92, 0.033, -2.92),
	}, Holes = {
		{ Size = V(0.3, 0.045, 0.08), CFrame = CFrame.new(0, 0.0, -0.04) },
		{ Size = V(0.3, 0.045, 0.08), CFrame = CFrame.new(0, 0.0, 0.08) },
	} })
	B("Barrel", "BrakeCap", "Armor", V(0, 0.19, -2.62), V(0.13, 0.03, 0.26), { Bevel = BV.S, Cuts = {
		cyz(0.19, -2.62, 0.205, -2.70, 0.175, -2.75, 0.205, -2.75),
	} })
	B("Barrel", "Bore", "Dark", V(0, 0.108, -2.9205), V(0.032, 0.032, 0.006))
	yield()

	-- ── OPTIC (integrated, forward-raked holo visor) ────────────────────────────────────
	-- ADS-first proportions: slim, shallow posts so the window (0.17 x 0.13) dominates the sight
	-- picture; the reticle is projected through it (HudOptics:SetHoloSight).
	B("Optic", "Mount", "Frame", V(0, 0.395, -0.33), V(0.20, 0.05, 0.38), { Bevel = BV.S, Cuts = {
		cyz(0.395, -0.33, 0.42, -0.48, 0.37, -0.52, 0.42, -0.52),
	} })
	sides(function(s, k)
		B("Optic", "Post" .. k, "Frame", V(s * 0.10, 0.485, -0.34), V(0.03, 0.17, 0.14), { Bevel = 0.008, Cuts = {
			cyz(0.485, -0.34, 0.57, -0.33, 0.47, -0.41, 0.57, -0.41),
		} })
		B("Optic", "SideGlow" .. k, "Glow", V(s * 0.1155, 0.45, -0.31), V(0.004, 0.01, 0.07))
	end)
	B("Optic", "Brow", "Armor", V(0, 0.567, -0.31), V(0.23, 0.035, 0.20), { Bevel = 0.012, Cuts = {
		cyz(0.567, -0.31, 0.5845, -0.35, 0.5495, -0.41, 0.5845, -0.41),
		cyz(0.567, -0.31, 0.5845, -0.24, 0.5495, -0.21, 0.5845, -0.21),
	} })
	B("Optic", "Glass", "Glass", V(0, 0.485, -0.36), V(0.17, 0.13, 0.005))
	B("Optic", "Emitter", "Glow", V(0, 0.426, -0.25), V(0.035, 0.01, 0.025))
	yield()

	-- ── STOCK (skeletal triangle, raked butt) ───────────────────────────────────────────
	B("Stock", "Tube", "Frame", V(0, 0.10, 0.78), V(0.13, 0.13, 0.56), { Bevel = 0.03, Axes = "z" })
	B("Stock", "Clamp", "Frame", V(0, 0.115, 0.60), V(0.20, 0.21, 0.17), { Bevel = BV.M, Cuts = {
		cyz(0.115, 0.60, 0.01, 0.62, 0.06, 0.685, 0.01, 0.685),
	} })
	B("Stock", "Spine", "Armor", V(0, 0.16, 1.10), V(0.17, 0.15, 1.08), { Bevel = BV.L, Cuts = {
		cyz(0.16, 1.10, 0.085, 0.70, 0.15, 1.64, 0.085, 1.64),
		cyz(0.16, 1.10, 0.235, 1.48, 0.18, 1.64, 0.235, 1.64),
	} })
	sides(function(s, k)
		B("Stock", "SpineSeam" .. k, "Dark", V(s * 0.0855, 0.175, 1.00), V(0.006, 0.012, 0.56))
	end)
	local sa, sb = V(0, -0.10, 0.45), V(0, -0.44, 1.55)
	local mid = (sa + sb) / 2
	B("Stock", "Strut", "Frame", nil, V(0.10, 0.07, (sb - sa).Magnitude), { CF = CFrame.lookAt(mid, sb), Bevel = BV.M })
	local buttCF = CFrame.new(0, -0.15, 1.60) * CFrame.Angles(R(-8), 0, 0)
	B("Stock", "Butt", "Armor", nil, V(0.19, 0.66, 0.12), { CF = buttCF, Bevel = BV.L, Cuts = {
		Kit.CutYZ(-0.33, -0.02, -0.25, 0.06, -0.33, 0.06),
		Kit.CutYZ(0.33, -0.04, 0.25, -0.06, 0.33, -0.06),
	} })
	B("Stock", "Pad", "Grip", nil, V(0.17, 0.60, 0.05), { CF = buttCF * CFrame.new(0, 0, 0.083), Bevel = BV.M })
	B("Stock", "Cheek", "Frame", V(0, 0.255, 1.12), V(0.13, 0.05, 0.40), { Bevel = BV.M, Cuts = {
		cyz(0.255, 1.12, 0.28, 0.99, 0.23, 0.92, 0.28, 0.92),
	} })
	sides(function(s, k)
		B("Stock", "ButtGlow" .. k, "Glow", nil, V(0.006, 0.30, 0.02), { CF = buttCF * CFrame.new(s * 0.0965, 0.06, 0) })
		B("Stock", "StrutGlow" .. k, "Glow", nil, V(0.006, 0.012, 0.50), { CF = CFrame.lookAt(mid, sb) * CFrame.new(s * 0.0515, 0, 0) })
	end)
	yield()

	-- ── MAGAZINE (forward-raked energy cell, raked along the reload eject axis) ───────────
	local magCF = CFrame.new(0, -0.665, -0.378) * CFrame.Angles(R(9.2), 0, 0)
	local body = B("Magazine", "MagBody", "Frame", nil, V(0.15, 0.62, 0.40), { CF = magCF, Bevel = BV.M, Cuts = {
		Kit.CutYZ(0.31, -0.165, -0.31, -0.20, 0.31, -0.20),
	} })
	sides(function(s, k)
		B("Magazine", "Shell" .. k, "Armor", nil, V(0.014, 0.42, 0.26), { CF = magCF * CFrame.new(s * 0.079, -0.07, 0.055), Bevel = 0.006, Cuts = {
			Kit.CutYZ(0.21, -0.13, -0.21, -0.11, 0.21, -0.13 - 0.01),
		} })
		B("Magazine", "Window" .. k, "Dark", nil, V(0.008, 0.40, 0.05), { CF = magCF * CFrame.new(s * 0.077, -0.05, -0.12) })
		B("Magazine", "Counter" .. k, "Glow", nil, V(0.006, 0.32, 0.016), { CF = magCF * CFrame.new(s * 0.0805, -0.06, -0.12) })
	end)
	for i, y in { 0.08, -0.04, -0.16 } do
		B("Magazine", "Rib" .. i, "Frame", nil, V(0.13, 0.022, 0.02), { CF = magCF * CFrame.new(0, y, -0.19 - (0.31 - y) * 0.035 / 0.62), Bevel = 0.005 })
	end
	B("Magazine", "Base", "Armor", nil, V(0.175, 0.07, 0.43), { CF = magCF * CFrame.new(0, -0.335, -0.01), Bevel = BV.M, Cuts = {
		Kit.CutYZ(-0.035, -0.15, 0.035, -0.215, -0.035, -0.215),
		Kit.CutYZ(-0.035, 0.18, 0.0, 0.215, -0.035, 0.215),
	} })
	B("Magazine", "FeedLips", "Metal", nil, V(0.11, 0.03, 0.30), { CF = magCF * CFrame.new(0, 0.32, 0.01), Bevel = 0.006 })
	B("Magazine", "Round", "Glow", nil, V(0.05, 0.028, 0.22), { CF = magCF * CFrame.new(0, 0.345, -0.02) })
	local mag = comps.Magazine
	mag.PrimaryPart = body
	mag:SetAttribute("Real", true)

	-- ── ATTACHMENTS ─────────────────────────────────────────────────────────────────────
	-- carry over every Root attachment of the old asset (grips, muzzle, shoulder, mag seat…)
	if oldAsset and oldAsset.PrimaryPart then
		for _, a in oldAsset.PrimaryPart:GetChildren() do
			if a:IsA("Attachment") then
				attach(root, a.Name, a.CFrame)
			end
		end
		local om = oldAsset:FindFirstChild("Magazine")
		local og = om and om.PrimaryPart and om.PrimaryPart:FindFirstChild("MagGrip")
		if og then
			local rel = oldAsset.PrimaryPart.CFrame:ToObjectSpace(og.WorldCFrame)
			local g = Instance.new("Attachment")
			g.Name = "MagGrip"
			g.CFrame = body.CFrame:ToObjectSpace(O * rel)
			g.Parent = body
		end
	end
	if not body:FindFirstChild("MagGrip") then
		local g = Instance.new("Attachment")
		g.Name = "MagGrip"
		g.CFrame = CFrame.new(0, -0.03, -0.195)
		g.Parent = body
	end
	attach(root, "ADSPoint", CFrame.new(0, 0.485, -0.191))
	attach(root, "WindowA", CFrame.new(-0.085, 0.5495, -0.36))
	attach(root, "WindowB", CFrame.new(0.085, 0.42, -0.36))
	attach(root, "EjectPoint", CFrame.new(0.14, 0.10, -0.17))
	attach(root, "Socket_Receiver", CFrame.new())
	attach(root, "Socket_Handguard", CFrame.new(0, 0.06, -0.72))
	attach(root, "Socket_Barrel", CFrame.new(0, 0.108, -2.02))
	attach(root, "Socket_Optic", CFrame.new(0, 0.37, -0.33))
	attach(root, "Socket_Stock", CFrame.new(0, 0.10, 0.50))
	attach(root, "Socket_Grip", gripCF)
	attach(root, "Socket_Magazine", magCF)

	weldAll(model, root)
	model:SetAttribute("Length", 4.6)
	model:SetAttribute("Split", true)
	model:SetAttribute("Source", "ForgeKit")
	model:SetAttribute("ArtStyle", "Forge")
	model:SetAttribute("ArtVersion", 4)
	model:SetAttribute("SkinSchema", "Roles")
	model:SetAttribute("Design", "VX-01 Vanguard")
	return model
end

return Builds
