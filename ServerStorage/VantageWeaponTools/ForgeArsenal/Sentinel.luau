-- ═══ MR-04 SENTINEL — marksman rifle ══════════════════════════════════════════════════════
-- Identity: long and lean. A flat ceramic top deck runs the receiver; "fang" side plates point
-- forward and down; a tall slim handguard with a long glowing vent slot ends in an exposed
-- fluted barrel and a square ported compensator. Up top, a hollow prism optic (you look
-- THROUGH it: eyepiece housing, humped prism body, wide objective with a glow frame), and a
-- solid slab stock with a thumbhole cut.
local V = Vector3.new
local R = math.rad

return function(Kit, Common, O: CFrame, oldAsset: Model?)
	local ctx = Common.Begin(Kit, "Sentinel", O)
	local B, cyz, sides, BV = ctx.B, ctx.cyz, ctx.sides, ctx.BV
	local BORE = 0.077

	-- ── RECEIVER ────────────────────────────────────────────────────────────────────────
	B("Receiver", "Core", "Frame", V(0, 0.0, -0.10), V(0.22, 0.44, 1.20), { Bevel = BV.M, Cuts = {
		cyz(0, -0.10, -0.22, 0.30, 0.0, 0.50, -0.22, 0.50),
	} })
	B("Receiver", "Deck", "Armor", V(0, 0.24, -0.12), V(0.25, 0.12, 1.20), { Bevel = BV.L, Cuts = {
		cyz(0.24, -0.12, 0.30, -0.62, 0.18, -0.74, 0.30, -0.74),
		cyz(0.24, -0.12, 0.30, 0.38, 0.18, 0.50, 0.30, 0.50),
	} })
	sides(function(s, k)
		B("Receiver", "Fang" .. k, "Armor", V(s * 0.122, -0.03, -0.18), V(0.03, 0.26, 0.96), { Bevel = BV.M, Cuts = {
			cyz(-0.03, -0.18, 0.10, -0.46, -0.16, -0.66, 0.10, -0.66),
			cyz(-0.03, -0.18, -0.16, 0.16, 0.10, 0.30, -0.16, 0.30),
		} })
		B("Receiver", "FangGlow" .. k, "Glow", V(s * 0.1385, 0.055, -0.14), V(0.006, 0.012, 0.50))
		B("Receiver", "Pin" .. k, "Metal", V(s * 0.139, -0.08, 0.10), V(0.008, 0.026, 0.026), { Bevel = 0.005 })
		B("Receiver", "DeckSeam" .. k, "Dark", V(s * 0.1255, 0.215, -0.16), V(0.006, 0.012, 0.62))
	end)
	B("Receiver", "EjectPort", "Dark", V(0.1115, 0.14, -0.07), V(0.008, 0.06, 0.26))
	B("Receiver", "ChargeSlot", "Dark", V(-0.1115, 0.14, 0.30), V(0.008, 0.035, 0.24))
	local charge = B("Receiver", "Charge", "Accent", V(-0.132, 0.14, 0.35), V(0.05, 0.042, 0.08), { Bevel = BV.S })
	charge:SetAttribute("MovingPart", "Charge")
	B("Receiver", "BoltGlow", "Glow", V(-0.1125, 0.14, -0.16), V(0.004, 0.01, 0.30))
	B("Receiver", "Selector", "Accent", V(-0.118, -0.12, 0.24), V(0.02, 0.028, 0.07), { Bevel = 0.006, Rot = CFrame.Angles(R(-25), 0, 0) })
	B("Receiver", "MagWell", "Frame", V(0, -0.29, -0.37), V(0.23, 0.16, 0.56), { Bevel = BV.M, Cuts = {
		cyz(-0.29, -0.37, -0.21, -0.60, -0.37, -0.66, -0.21, -0.66),
	} })
	B("Receiver", "MagWellLip", "Armor", V(0, -0.355, -0.40), V(0.25, 0.035, 0.38), { Bevel = BV.S, Cuts = {
		cyz(-0.355, -0.40, -0.337, -0.56, -0.373, -0.59, -0.337, -0.59),
	} })
	B("Receiver", "MagRelease", "Accent", V(0.122, -0.24, -0.16), V(0.02, 0.04, 0.04), { Bevel = 0.006 })
	Common.Trigger(ctx)
	Common.RifleGrip(ctx)

	-- ── HANDGUARD (tall, slim, long glowing vent) ───────────────────────────────────────
	B("Handguard", "Core", "Frame", V(0, 0.045, -1.24), V(0.20, 0.33, 1.08), { Bevel = BV.M, Cuts = {
		cyz(0.045, -1.24, -0.125, -1.60, 0.0, -1.78, -0.125, -1.78),
	} })
	B("Handguard", "Top", "Armor", V(0, 0.235, -1.22), V(0.23, 0.06, 1.04), { Bevel = BV.L, Cuts = {
		cyz(0.235, -1.22, 0.265, -0.74, 0.205, -0.70, 0.265, -0.70),
		cyz(0.235, -1.22, 0.265, -1.66, 0.205, -1.74, 0.265, -1.74),
	} })
	sides(function(s, k)
		B("Handguard", "Vent" .. k, "Dark", V(s * 0.1015, 0.07, -1.22), V(0.006, 0.075, 0.80))
		B("Handguard", "VentGlow" .. k, "Glow", V(s * 0.1035, 0.07, -1.22), V(0.004, 0.012, 0.72))
		for i = 0, 3 do
			B("Handguard", "Bar" .. k .. i, "Frame", V(s * 0.104, 0.07, -0.93 - i * 0.19), V(0.01, 0.085, 0.022), { Bevel = 0.004 })
		end
		B("Handguard", "Plate" .. k, "Armor", V(s * 0.106, -0.07, -1.10), V(0.018, 0.09, 0.66), { Bevel = BV.S, Cuts = {
			cyz(-0.07, -1.10, -0.025, -1.43, -0.115, -1.36, -0.115, -1.43),
		} })
	end)
	B("Handguard", "Keel", "Armor", V(0, -0.135, -1.30), V(0.12, 0.05, 0.78), { Bevel = BV.M, Cuts = {
		cyz(-0.135, -1.30, -0.11, -1.69, -0.16, -1.60, -0.16, -1.69),
	} })
	B("Handguard", "Nose", "Frame", V(0, BORE, -1.80), V(0.15, 0.15, 0.06), { Bevel = BV.M })

	-- ── BARREL (exposed, fluted) + square ported compensator ─────────────────────────────
	B("Barrel", "Barrel", "Metal", V(0, BORE, -2.10), V(0.07, 0.07, 0.56), { Bevel = 0.018, Axes = "z" })
	B("Barrel", "GasBlock", "Frame", V(0, BORE + 0.01, -1.92), V(0.10, 0.12, 0.05), { Bevel = BV.S })
	B("Barrel", "Band", "Frame", V(0, BORE, -2.24), V(0.09, 0.09, 0.025), { Bevel = 0.02, Axes = "z" })
	B("Barrel", "EmitterRing", "Glow", V(0, BORE, -2.372), V(0.095, 0.095, 0.014), { Bevel = 0.02, Axes = "z" })
	B("Barrel", "Comp", "Frame", V(0, BORE, -2.445), V(0.13, 0.13, 0.13), { Bevel = BV.M, Holes = {
		{ Size = V(0.07, 0.2, 0.024), CFrame = CFrame.new(0, 0.1, -0.025) },
		{ Size = V(0.07, 0.2, 0.024), CFrame = CFrame.new(0, 0.1, 0.025) },
		{ Size = V(0.2, 0.05, 0.03), CFrame = CFrame.new(0, 0, 0) },
	} })
	B("Barrel", "Bore", "Dark", V(0, BORE, -2.5125), V(0.03, 0.03, 0.006))

	-- ── OPTIC (hollow prism: you look through it) ───────────────────────────────────────
	local OY = 0.47
	B("Optic", "Mount", "Frame", V(0, 0.335, -0.02), V(0.14, 0.09, 0.36), { Bevel = BV.S, Cuts = {
		cyz(0.335, -0.02, 0.38, -0.16, 0.29, -0.20, 0.38, -0.20),
		cyz(0.335, -0.02, 0.38, 0.12, 0.29, 0.16, 0.38, 0.16),
	} })
	B("Optic", "Eyepiece", "Frame", V(0, OY, 0.12), V(0.20, 0.18, 0.20), { Bevel = BV.M, Holes = {
		{ Size = V(0.15, 0.12, 1), CFrame = CFrame.new() },
	} })
	B("Optic", "Prism", "Armor", V(0, OY + 0.015, -0.035), V(0.22, 0.23, 0.17), { Bevel = BV.L, Cuts = {
		cyz(OY + 0.015, -0.035, OY + 0.13, -0.06, OY + 0.07, -0.12, OY + 0.13, -0.12),
		cyz(OY + 0.015, -0.035, OY + 0.13, 0.02, OY + 0.09, 0.05, OY + 0.13, 0.05),
	}, Holes = {
		{ Size = V(0.15, 0.12, 1), CFrame = CFrame.new(0, -0.015, 0) },
	} })
	B("Optic", "Objective", "Frame", V(0, OY, -0.165), V(0.23, 0.20, 0.09), { Bevel = BV.M, Holes = {
		{ Size = V(0.17, 0.14, 1), CFrame = CFrame.new() },
	} })
	B("Optic", "ObjectiveGlow", "Glow", V(0, OY, -0.2115), V(0.20, 0.17, 0.004), { Holes = {
		{ Size = V(0.17, 0.14, 1), CFrame = CFrame.new() },
	} })
	B("Optic", "Glass", "Glass", V(0, OY, -0.17), V(0.17, 0.14, 0.004))
	B("Optic", "Turret", "Accent", V(-0.124, OY + 0.01, -0.035), V(0.03, 0.06, 0.06), { Bevel = 0.006 })
	B("Optic", "TurretCap", "Frame", V(0, OY + 0.155, -0.035), V(0.06, 0.03, 0.06), { Bevel = 0.006 })
	sides(function(s, k)
		B("Optic", "SideGlow" .. k, "Glow", V(s * 0.1105, OY + 0.06, -0.035), V(0.004, 0.01, 0.10))
	end)

	-- ── STOCK (solid slab, thumbhole) ───────────────────────────────────────────────────
	B("Stock", "Neck", "Frame", V(0, 0.05, 0.53), V(0.20, 0.32, 0.08), { Bevel = BV.M })
	B("Stock", "Slab", "Armor", V(0, 0.035, 1.10), V(0.18, 0.42, 1.20), { Bevel = BV.L, Cuts = {
		cyz(0.035, 1.10, -0.175, 0.95, 0.02, 0.50, -0.175, 0.50),
		cyz(0.035, 1.10, 0.245, 1.62, 0.15, 1.70, 0.245, 1.70),
	}, Holes = {
		{ Size = V(1, 0.14, 0.40), CFrame = CFrame.new(0, -0.02, -0.04) },
	} })
	B("Stock", "Cheek", "Frame", V(0, 0.265, 0.98), V(0.13, 0.05, 0.46), { Bevel = BV.M, Cuts = {
		cyz(0.265, 0.98, 0.29, 0.80, 0.24, 0.75, 0.29, 0.75),
	} })
	B("Stock", "Pad", "Grip", V(0, 0.035, 1.715), V(0.16, 0.36, 0.035), { Bevel = BV.M })
	sides(function(s, k)
		B("Stock", "Glow" .. k, "Glow", V(s * 0.0915, 0.19, 1.12), V(0.006, 0.012, 0.50))
		B("Stock", "Seam" .. k, "Dark", V(s * 0.0915, -0.11, 1.36), V(0.006, 0.012, 0.36))
	end)

	-- ── MAGAZINE (slim DMR box, raked along the reload eject axis) ───────────────────────
	local magCF = CFrame.new(0, -0.63, -0.42) * CFrame.Angles(R(8), 0, 0)
	local body = B("Magazine", "MagBody", "Frame", nil, V(0.13, 0.56, 0.30), { CF = magCF, Bevel = BV.M })
	sides(function(s, k)
		B("Magazine", "Shell" .. k, "Armor", nil, V(0.012, 0.40, 0.22), { CF = magCF * CFrame.new(s * 0.069, -0.06, 0.03), Bevel = 0.005 })
		B("Magazine", "Counter" .. k, "Glow", nil, V(0.006, 0.30, 0.014), { CF = magCF * CFrame.new(s * 0.0705, -0.05, -0.11) })
	end)
	B("Magazine", "Base", "Armor", nil, V(0.155, 0.06, 0.33), { CF = magCF * CFrame.new(0, -0.30, 0), Bevel = BV.M, Cuts = {
		Kit.CutYZ(-0.03, -0.12, 0.03, -0.165, -0.03, -0.165),
	} })
	B("Magazine", "FeedLips", "Metal", nil, V(0.10, 0.03, 0.24), { CF = magCF * CFrame.new(0, 0.29, 0.0), Bevel = 0.006 })

	return Common.Finish(ctx, oldAsset, body, {
		ADSPoint = CFrame.new(0, OY, 0.22),
		WindowA = CFrame.new(-0.085, OY + 0.07, -0.17),
		WindowB = CFrame.new(0.085, OY - 0.07, -0.17),
		EjectPoint = CFrame.new(0.13, 0.155, -0.07),
		Socket_Receiver = CFrame.new(),
		Socket_Handguard = CFrame.new(0, 0.045, -0.70),
		Socket_Barrel = CFrame.new(0, BORE, -1.83),
		Socket_Optic = CFrame.new(0, 0.30, -0.02),
		Socket_Stock = CFrame.new(0, 0.05, 0.49),
		Socket_Grip = CFrame.new(0, -0.482, 0.387) * CFrame.Angles(R(-15), 0, 0),
		Socket_Magazine = magCF,
	}, { Length = 4.2, ArtVersion = 1, Design = "MR-04 Sentinel" })
end
