-- ═══ SP-02 SPECTRE — sidearm ════════════════════════════════════════════════════════════
-- Identity: a heavy, squared-off sidearm. A fixed ceramic top shroud carries real three-dot
-- iron sights (rear notch with two dots, front post with one) so aiming lines them up for
-- real; the serrated slide runs underneath (the moving part, ejection port cut through it);
-- a ported compensator with a cyan ring caps the muzzle; the magazine base and a glowing
-- frame strip finish the lower.
local V = Vector3.new
local R = math.rad

return function(Kit, Common, O: CFrame, oldAsset: Model?)
	local ctx = Common.Begin(Kit, "Spectre", O)
	local B, cyz, sides, BV = ctx.B, ctx.cyz, ctx.sides, ctx.BV
	local BORE = 0.062
	local SIGHT = 0.235 -- sight line height (rear notch floor = front dot centre)

	-- ── SLIDE (moving) ──────────────────────────────────────────────────────────────────
	local holes = { { Size = V(0.05, 0.06, 0.16), CFrame = CFrame.new(0.08, 0.05, 0.07) } }
	for i = 0, 3 do
		for _, s in { -1, 1 } do
			table.insert(holes, { Size = V(0.024, 0.11, 0.016), CFrame = CFrame.new(s * 0.08, -0.005, 0.30 + i * 0.038) })
		end
	end
	local slide = B("Receiver", "Slide", "Frame", V(0, 0.05, -0.20), V(0.16, 0.18, 0.94), { Bevel = BV.M, Cuts = {
		cyz(0.05, -0.20, 0.14, -0.58, 0.03, -0.67, 0.14, -0.67),
		cyz(0.05, -0.20, 0.14, 0.19, 0.06, 0.27, 0.14, 0.27),
	}, Holes = holes })
	slide:SetAttribute("MovingPart", "Slide")
	-- barrel hood seen through the ejection port (fixed: the slide runs back over it)
	B("Barrel", "Hood", "Metal", V(0.045, 0.10, -0.12), V(0.06, 0.05, 0.15), { Bevel = 0.006 })
	-- ceramic cheek plates over the front of the slide (fixed shroud sides)
	sides(function(s, k)
		B("Receiver", "Cheek" .. k, "Armor", V(s * 0.0855, 0.035, -0.45), V(0.014, 0.12, 0.40), { Bevel = BV.S, Cuts = {
			cyz(0.035, -0.45, 0.095, -0.30, -0.025, -0.25, -0.025, -0.20),
			cyz(0.035, -0.45, 0.095, -0.60, -0.025, -0.65, 0.095, -0.65),
		} })
		B("Receiver", "CheekGlow" .. k, "Glow", V(s * 0.093, 0.035, -0.47), V(0.004, 0.01, 0.20))
	end)

	-- ── SHROUD (fixed, carries the sights) ──────────────────────────────────────────────
	B("Receiver", "Shroud", "Armor", V(0, 0.17, -0.24), V(0.18, 0.06, 0.86), { Bevel = BV.L, Cuts = {
		cyz(0.17, -0.24, 0.20, -0.58, 0.14, -0.67, 0.20, -0.67),
		cyz(0.17, -0.24, 0.20, 0.14, 0.15, 0.19, 0.20, 0.19),
	} })
	sides(function(s, k)
		B("Receiver", "ShroudGlow" .. k, "Glow", V(s * 0.0915, 0.165, -0.30), V(0.006, 0.012, 0.46))
		B("Receiver", "ShroudSeam" .. k, "Dark", V(s * 0.0915, 0.165, 0.02), V(0.006, 0.012, 0.12))
		-- rear sight ears + dots
		B("Receiver", "RearEar" .. k, "Frame", V(s * 0.045, 0.2275, 0.15), V(0.04, 0.055, 0.045), { Bevel = 0.006 })
		B("Receiver", "RearDot" .. k, "Glow", V(s * 0.045, 0.245, 0.1735), V(0.012, 0.012, 0.004))
	end)
	B("Receiver", "RearBase", "Frame", V(0, 0.2175, 0.15), V(0.13, 0.035, 0.045), { Bevel = 0.004 })
	B("Receiver", "FrontPost", "Frame", V(0, 0.2225, -0.62), V(0.024, 0.045, 0.03), { Bevel = 0.004 })
	B("Receiver", "FrontDot", "Glow", V(0, SIGHT, -0.6035), V(0.012, 0.012, 0.004))

	-- ── COMPENSATOR ─────────────────────────────────────────────────────────────────────
	B("Barrel", "Comp", "Frame", V(0, 0.075, -0.72), V(0.15, 0.15, 0.10), { Bevel = BV.M, Cuts = {
		cyz(0.075, -0.72, 0.15, -0.70, 0.10, -0.77, 0.15, -0.77),
	}, Holes = {
		{ Size = V(0.08, 0.2, 0.02), CFrame = CFrame.new(0, 0.1, -0.01) },
		{ Size = V(0.2, 0.035, 0.03), CFrame = CFrame.new(0, -0.013, 0.0) },
	} })
	B("Barrel", "Ring", "Glow", V(0, BORE, -0.668), V(0.09, 0.09, 0.008), { Bevel = 0.02, Axes = "z" })
	B("Barrel", "Bore", "Dark", V(0, BORE, -0.7725), V(0.03, 0.03, 0.006))

	-- ── FRAME (lower) ───────────────────────────────────────────────────────────────────
	B("Receiver", "Frame", "Frame", V(0, -0.095, -0.22), V(0.15, 0.11, 0.80), { Bevel = BV.M, Cuts = {
		cyz(-0.095, -0.22, -0.15, -0.50, -0.04, -0.62, -0.15, -0.62),
	} })
	B("Receiver", "Dust", "Armor", V(0, -0.085, -0.50), V(0.158, 0.09, 0.28), { Bevel = BV.M, Cuts = {
		cyz(-0.085, -0.50, -0.04, -0.60, -0.13, -0.52, -0.13, -0.64),
	} })
	sides(function(s, k)
		B("Receiver", "FrameGlow" .. k, "Glow", V(s * 0.0795, -0.075, -0.28), V(0.006, 0.012, 0.30))
		B("Receiver", "Pin" .. k, "Metal", V(s * 0.0775, -0.09, 0.02), V(0.006, 0.022, 0.022), { Bevel = 0.004 })
	end)
	B("Receiver", "SlideStop", "Accent", V(-0.083, -0.02, -0.06), V(0.012, 0.025, 0.08), { Bevel = 0.004 })
	B("Receiver", "MagRelease", "Accent", V(-0.078, -0.15, 0.06), V(0.012, 0.035, 0.035), { Bevel = 0.004 })
	B("Receiver", "GuardFront", "Frame", V(0, -0.205, -0.22), V(0.05, 0.11, 0.035), { Bevel = 0.006, Rot = CFrame.Angles(R(10), 0, 0) })
	B("Receiver", "Guard", "Frame", V(0, -0.255, -0.10), V(0.05, 0.03, 0.26), { Bevel = 0.006 })
	B("Receiver", "Trigger", "Metal", V(0, -0.185, -0.07), V(0.024, 0.08, 0.024), { Bevel = 0.005, Rot = CFrame.Angles(R(-15), 0, 0) })
	B("Receiver", "Beavertail", "Frame", V(0, -0.06, 0.235), V(0.135, 0.045, 0.15), { Bevel = BV.S, Cuts = {
		cyz(-0.06, 0.235, -0.0375, 0.24, -0.0825, 0.31, -0.0375, 0.31),
	} })

	-- ── GRIP ────────────────────────────────────────────────────────────────────────────
	local gripCF = CFrame.new(0, -0.35, 0.215) * CFrame.Angles(R(-14.3), 0, 0)
	B("Grip", "Body", "Grip", nil, V(0.14, 0.44, 0.19), { CF = gripCF, Bevel = BV.L })
	B("Grip", "Backstrap", "Armor", nil, V(0.15, 0.34, 0.04), { CF = gripCF * CFrame.new(0, 0.02, 0.085), Bevel = BV.M })
	sides(function(s, k)
		B("Grip", "Panel" .. k, "Frame", nil, V(0.012, 0.26, 0.11), { CF = gripCF * CFrame.new(s * 0.071, -0.02, -0.01), Bevel = 0.004 })
	end)
	for i = 0, 2 do
		B("Grip", "Ridge" .. i, "Frame", nil, V(0.145, 0.018, 0.025), { CF = gripCF * CFrame.new(0, 0.06 - i * 0.09, -0.095), Bevel = 0.005 })
	end

	-- ── MAGAZINE (in the grip; base plate shows) ────────────────────────────────────────
	local magCF = CFrame.new(0, -0.37, 0.22) * CFrame.Angles(R(-14.3), 0, 0)
	local body = B("Magazine", "MagBody", "Frame", nil, V(0.10, 0.50, 0.15), { CF = magCF, Bevel = BV.S })
	B("Magazine", "Base", "Armor", nil, V(0.155, 0.05, 0.21), { CF = magCF * CFrame.new(0, -0.265, 0.005), Bevel = BV.M })
	B("Magazine", "BaseGlow", "Glow", nil, V(0.11, 0.01, 0.006), { CF = magCF * CFrame.new(0, -0.265, -0.1005) })
	B("Magazine", "Tab", "Accent", nil, V(0.06, 0.02, 0.03), { CF = magCF * CFrame.new(0, -0.295, 0.06), Bevel = 0.004 })
	B("Magazine", "FeedLips", "Metal", nil, V(0.07, 0.025, 0.11), { CF = magCF * CFrame.new(0, 0.255, 0), Bevel = 0.004 })

	return Common.Finish(ctx, oldAsset, body, {
		ADSPoint = CFrame.new(0, SIGHT, 0.15),
		EjectPoint = CFrame.new(0.10, 0.10, -0.13),
		Socket_Receiver = CFrame.new(),
		Socket_Barrel = CFrame.new(0, BORE, -0.67),
		Socket_Optic = CFrame.new(0, 0.20, -0.10),
		Socket_Grip = gripCF,
		Socket_Magazine = magCF,
	}, { Length = 1.25, ArtVersion = 1, Design = "SP-02 Spectre" })
end
