--[[
	VANTAGE — VX01Builder (edit-time)
	Builds the VX-01 rifle into ReplicatedStorage.Vantage.Weapons.Assets.VX01.
		require(game.ServerStorage.VantageWeaponTools.VX01Builder:Clone()).Build()
	Gun space: -Z = forward (muzzle), +Y = up, origin = receiver centre.

	Attachments on Body (the hand / IK contract — keep names when swapping in MeshParts):
		GripRight    pistol grip; frame matches Roblox's RightGripAttachment convention
		             (+Y up the grip = thumb side, +Z back toward the wrist)
		GripLeft     first-person support hand on the handguard (palm up, thumb forward)
		GripLeftTP   third-person support hand (rear of the handguard, within R15 reach)
		Muzzle, EjectPort
		Sight        centre of the holo reticle (aim-down-sights alignment point)
		Shoulder     butt pad (third-person shoulder pocket)
	Sub-model "Magazine" (PrimaryPart MagBody, attachment MagGrip) animates separately.
]]

local V = Vector3.new
local C = Color3.fromRGB
local A = CFrame.Angles
local CF = CFrame.new
local rad = math.rad

local SM = Enum.Material.SmoothPlastic
local COL = {
	White = { SM, C(232, 235, 240) },
	Shell = { SM, C(214, 219, 227) },
	Graphite = { Enum.Material.Metal, C(62, 67, 78) },
	Dark = { SM, C(36, 40, 48) },
	Black = { SM, C(20, 22, 26) },
	Grey = { SM, C(120, 127, 138) },
	Neon = { Enum.Material.Neon, C(40, 140, 255) },
	Glass = { Enum.Material.Glass, C(120, 190, 255) },
	Brass = { Enum.Material.Metal, C(196, 160, 82) },
}

local B = {}

function B.Build()
	local weapons = game:GetService("ReplicatedStorage").Vantage.Weapons
	local assets = weapons:FindFirstChild("Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = weapons
	end
	local old = assets:FindFirstChild("VX01")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "VX01"
	local count = 0

	local function style(p, s)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Material = s[1]
		p.Color = s[2]
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if s == COL.Glass then
			p.Transparency = 0.82
			p.CastShadow = false
		elseif s == COL.Neon then
			p.CastShadow = false
		end
	end
	local function P(parent, name, size, cf, s, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		style(p, s)
		if shape then
			p.Shape = shape
		end
		p.Parent = parent
		count += 1
		return p
	end
	-- WedgePart: full height at +Z, slope descending toward -Z
	local function W(parent, name, size, cf, s)
		local p = Instance.new("WedgePart")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		style(p, s)
		p.Parent = parent
		count += 1
		return p
	end
	local function cyl(parent, name, len, d, cf, s)
		-- Cylinder axis = local X; rotated so it runs along Z
		return P(parent, name, V(len, d, d), cf * A(0, rad(90), 0), s, Enum.PartType.Cylinder)
	end
	local function bevelledTop(name, width, height, len, cf, s)
		-- box with two 35-degree chamfers along the top edges
		P(model, name, V(width - 0.06, height, len), cf, s)
		P(model, name .. "BevelL", V(0.07, height * 0.8, len), cf * CF(-(width / 2 - 0.04), -0.01, 0) * A(0, 0, rad(-28)), s)
		P(model, name .. "BevelR", V(0.07, height * 0.8, len), cf * CF(width / 2 - 0.04, -0.01, 0) * A(0, 0, rad(28)), s)
	end

	-- ── receiver ───────────────────────────────────────────────
	local body = P(model, "Body", V(0.3, 0.34, 1.22), CF(0, 0, 0), COL.Graphite)
	bevelledTop("UpperShell", 0.34, 0.15, 1.18, CF(0, 0.235, 0), COL.White)
	W(model, "UpperShellRear", V(0.28, 0.13, 0.2), CF(0, 0.225, 0.69) * A(0, rad(180), 0), COL.White)
	P(model, "LowerReceiver", V(0.28, 0.17, 0.86), CF(0, -0.25, 0.12), COL.Dark)
	W(model, "LowerTaperFront", V(0.28, 0.17, 0.14), CF(0, -0.25, -0.38) * A(0, rad(180), rad(180)), COL.Dark)
	for _, sx in ipairs({ -1, 1 }) do
		P(model, "SideInset", V(0.02, 0.15, 0.72), CF(sx * 0.158, -0.01, 0.06), COL.Dark)
		P(model, "SideAccent", V(0.022, 0.026, 0.56), CF(sx * 0.168, 0.155, 0.02), COL.Neon)
		P(model, "SideRib", V(0.024, 0.02, 0.5), CF(sx * 0.165, -0.1, 0.12), COL.Graphite)
	end
	P(model, "EjectionPort", V(0.02, 0.09, 0.27), CF(0.168, 0.02, -0.14), COL.Black)
	P(model, "DustCover", V(0.012, 0.1, 0.29), CF(0.172, 0.02, -0.14), COL.Graphite).Transparency = 0.3
	P(model, "ChargingHandle", V(0.24, 0.045, 0.08), CF(0, 0.33, 0.58), COL.Dark)
	P(model, "ChargingTab", V(0.06, 0.05, 0.09), CF(0.14, 0.33, 0.58), COL.Grey)
	cyl(model, "Selector", 0.04, 0.08, CF(-0.165, -0.13, 0.33) * A(0, rad(90), 0), COL.Grey)
	-- magwell
	P(model, "MagWell", V(0.25, 0.15, 0.36), CF(0, -0.37, -0.24), COL.Graphite)
	P(model, "MagWellLip", V(0.27, 0.04, 0.38), CF(0, -0.45, -0.24), COL.Black)
	-- trigger group
	P(model, "TriggerGuard", V(0.05, 0.03, 0.27), CF(0, -0.44, 0.1), COL.Black)
	P(model, "TriggerGuardFront", V(0.05, 0.11, 0.03), CF(0, -0.39, -0.02), COL.Black)
	P(model, "Trigger", V(0.035, 0.11, 0.04), CF(0, -0.37, 0.1) * A(rad(-15), 0, 0), COL.Grey)
	-- pistol grip (angled)
	local gripCF = CF(0, -0.53, 0.38) * A(rad(-18), 0, 0)
	P(model, "Grip", V(0.19, 0.5, 0.23), gripCF, COL.Dark)
	P(model, "GripBack", V(0.195, 0.4, 0.06), gripCF * CF(0, 0.02, 0.105), COL.White)
	for i = 0, 2 do
		P(model, "GripRib", V(0.198, 0.025, 0.2), gripCF * CF(0, 0.1 - i * 0.11, -0.02), COL.Graphite)
	end
	P(model, "GripCap", V(0.21, 0.05, 0.26), gripCF * CF(0, -0.27, 0), COL.Black)

	-- ── handguard ──────────────────────────────────────────────
	P(model, "HandguardCore", V(0.28, 0.28, 1.25), CF(0, 0.03, -1.22), COL.Dark)
	bevelledTop("HandguardTop", 0.31, 0.12, 1.25, CF(0, 0.21, -1.22), COL.Shell)
	W(model, "HandguardNose", V(0.25, 0.1, 0.16), CF(0, 0.2, -1.92), COL.Shell)
	for _, sx in ipairs({ -1, 1 }) do
		P(model, "HandguardPlate", V(0.03, 0.19, 1.05), CF(sx * 0.152, 0.0, -1.2), COL.Graphite)
		for k = 0, 2 do
			P(model, "HandguardVent", V(0.034, 0.05, 0.2), CF(sx * 0.156, 0.02, -0.88 - k * 0.3), COL.Black)
		end
		P(model, "HandguardAccent", V(0.034, 0.022, 0.95), CF(sx * 0.158, -0.105, -1.2), COL.Neon)
	end
	P(model, "HandguardBottom", V(0.24, 0.06, 1.1), CF(0, -0.13, -1.2), COL.Graphite)
	P(model, "HandStop", V(0.11, 0.11, 0.08), CF(0, -0.2, -1.58), COL.Black)
	P(model, "HandguardCap", V(0.26, 0.24, 0.07), CF(0, 0.04, -1.88), COL.Black)

	-- ── barrel + muzzle ───────────────────────────────────────
	cyl(model, "Barrel", 0.42, 0.12, CF(0, 0.04, -2.1), COL.Graphite)
	cyl(model, "BarrelCollar", 0.05, 0.16, CF(0, 0.04, -1.93), COL.Black)
	P(model, "MuzzleBrake", V(0.17, 0.16, 0.32), CF(0, 0.04, -2.45), COL.Graphite)
	cyl(model, "MuzzleRing", 0.03, 0.19, CF(0, 0.04, -2.3), COL.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 1 do
			P(model, "MuzzlePort", V(0.02, 0.08, 0.06), CF(sx * 0.085, 0.04, -2.4 - k * 0.1), COL.Black)
		end
	end
	P(model, "MuzzleTopVent", V(0.07, 0.02, 0.14), CF(0, 0.125, -2.47), COL.Black)

	-- ── top rail + holo optic ────────────────────────────────
	P(model, "Rail", V(0.15, 0.05, 1.5), CF(0, 0.335, -0.55), COL.Black)
	for i = 0, 11 do
		P(model, "RailRib", V(0.165, 0.025, 0.05), CF(0, 0.37, 0.12 - i * 0.12), COL.Graphite)
	end
	P(model, "OpticBase", V(0.24, 0.07, 0.44), CF(0, 0.395, 0.08), COL.Dark)
	for _, sx in ipairs({ -1, 1 }) do
		P(model, "OpticPost", V(0.035, 0.22, 0.36), CF(sx * 0.115, 0.53, 0.06), COL.White)
		P(model, "OpticAccent", V(0.012, 0.13, 0.02), CF(sx * 0.134, 0.53, -0.1), COL.Neon)
	end
	P(model, "OpticHood", V(0.27, 0.045, 0.38), CF(0, 0.66, 0.06), COL.White)
	P(model, "OpticLip", V(0.27, 0.03, 0.04), CF(0, 0.645, -0.12), COL.Graphite)
	P(model, "OpticEmitter", V(0.08, 0.04, 0.06), CF(0, 0.44, 0.18), COL.Graphite)
	local glass = P(model, "OpticGlass", V(0.19, 0.2, 0.012), CF(0, 0.53, -0.06), COL.Glass)
	-- reticle (ring + dot) on the eye-facing side of the glass
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Reticle"
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(190, 200)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.AlwaysOnTop = false
	gui.ZOffset = 1
	gui.Parent = glass
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(9, 9)
	dot.BackgroundColor3 = C(70, 200, 255)
	dot.BorderSizePixel = 0
	dot.Parent = gui
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1, 0)
	dc.Parent = dot
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(78, 78)
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Color = C(70, 200, 255)
	rs.Thickness = 3
	rs.Transparency = 0.15
	rs.Parent = ring

	-- ── stock (slim) ─────────────────────────────────────────
	cyl(model, "BufferTube", 0.5, 0.15, CF(0, 0.08, 0.88), COL.Black)
	P(model, "Stock", V(0.2, 0.28, 0.46), CF(0, 0.04, 1.12), COL.White)
	W(model, "StockUnder", V(0.19, 0.17, 0.42), CF(0, -0.18, 1.14) * A(0, 0, rad(180)), COL.Dark)
	P(model, "CheekRest", V(0.21, 0.05, 0.34), CF(0, 0.2, 1.12), COL.Graphite)
	for _, sx in ipairs({ -1, 1 }) do
		P(model, "StockAccent", V(0.012, 0.022, 0.3), CF(sx * 0.103, 0.1, 1.12), COL.Neon)
	end
	P(model, "ButtPad", V(0.22, 0.44, 0.08), CF(0, -0.05, 1.39), COL.Dark)
	P(model, "ButtRubber", V(0.225, 0.45, 0.03), CF(0, -0.05, 1.445), COL.Black)

	-- ── magazine (curved, own sub-model) ─────────────────────
	local mag = Instance.new("Model")
	mag.Name = "Magazine"
	mag.Parent = model
	local magCF = CF(0, -0.62, -0.25) * A(rad(8), 0, 0)
	local magBody = P(mag, "MagBody", V(0.19, 0.48, 0.29), magCF, COL.Dark)
	local lowerCF = magCF * CF(0, -0.33, -0.05) * A(rad(10), 0, 0)
	P(mag, "MagLower", V(0.19, 0.24, 0.28), lowerCF, COL.Dark)
	for i = 0, 2 do
		P(mag, "MagRib", V(0.198, 0.022, 0.27), magCF * CF(0, 0.12 - i * 0.12, 0), COL.Graphite)
	end
	P(mag, "MagWindow", V(0.2, 0.17, 0.035), magCF * CF(0, 0.0, 0.11), COL.Neon)
	P(mag, "MagRound", V(0.06, 0.04, 0.2), magCF * CF(0, 0.255, -0.02), COL.Brass)
	P(mag, "MagBase", V(0.23, 0.055, 0.32), lowerCF * CF(0, -0.14, -0.01), COL.White)
	mag.PrimaryPart = magBody
	local mg = Instance.new("Attachment")
	mg.Name = "MagGrip"
	mg.CFrame = CF(-0.11, -0.2, 0.02) -- left side of the magazine; identity frame (thumb up, palm +X)
	mg.Parent = magBody

	-- ── attachments ──────────────────────────────────────────
	local function att(name, cf)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = body.CFrame:ToObjectSpace(cf)
		a.Parent = body
		return a
	end
	att("GripRight", gripCF * CF(0, 0.04, 0))
	-- support hand frames: X = gun up (palm up), Y = gun forward (thumb), Z = gun left (toward the wrist)
	local support = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, -Vector3.zAxis, -Vector3.xAxis)
	att("GripLeft", CF(0, -0.15, -1.28) * support)
	att("GripLeftTP", CF(0, -0.15, -0.75) * support)
	att("Muzzle", CF(0, 0.04, -2.62))
	att("EjectPort", CF(0.18, 0.02, -0.14))
	att("Sight", CF(0, 0.53, -0.06))
	att("Shoulder", CF(0, -0.05, 1.46))

	model.PrimaryPart = body
	model:SetAttribute("Weapon", "VX01")
	model.Parent = assets
	return "VX01 built: " .. count .. " parts"
end

return B
