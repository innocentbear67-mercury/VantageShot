-- Reload choreography data (see ReloadChoreo). Times are nominal; the animator stretches each
-- clip to the configured ReloadTime / Shell timings / vent lock, so beats keep their proportions.
-- Asset-space (Root) values are unscaled studs; "cam" values are camera-space studs.
local V = Vector3.new
local function k(t, p, r, e) return { t = t, p = p or Vector3.zero, r = r or Vector3.zero, e = e } end
local function pv(t, v, e) return { t = t, v = v, e = e } end

local C = {}

-- ═══ VX-01 Vanguard — "Flick & Slam" ═══════════════════════════════════════════════════════
C.Vanguard = {
	Reload = {
		Choreo = true,
		Length = 2.1,
		Geo = { Eject = V(0, -0.99, -0.16), Charge = { Axis = V(0, 0, 1), Travel = 0.345 } },
		Gun = {
			k(0.000, V(0.000, 0.000, 0.000), V(0, 0, 0)),
			k(0.200, V(-0.265, 0.271, 0.069), V(3.4, 13.7, -43.0), "back"),
			k(0.420, V(-0.249, 0.287, 0.067), V(6.6, 15.4, -49.2)),
			k(0.800, V(-0.232, 0.269, 0.055), V(2.4, 14.7, -40.9)),
			k(0.970, V(-0.217, 0.240, 0.077), V(-0.8, 13.9, -38.0), "in"),
			k(1.060, V(-0.217, 0.294, 0.068), V(6.4, 13.5, -33.7), "snap"),
			k(1.200, V(-0.051, 0.112, -0.217), V(7.0, 3.8, 34.9)),
			k(1.380, V(-0.035, 0.118, -0.217), V(6.0, 3.9, 39.0)),
			k(1.460, V(-0.021, 0.092, -0.179), V(3.0, 2.0, 29.6), "snap"),
			k(1.660, V(-0.034, 0.084, 0.017), V(-7.0, -2.0, -11.9), "back"),
			k(1.880, V(-0.018, 0.027, 0.027), V(-3.0, 0, -3.0)),
			k(2.100, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = {
			{ t = 1.03, p = V(0, 0, 0), r = V(-4, 0, 3), f = 40, d = 16 },
			{ t = 1.46, p = V(0, 0, 0.039), r = V(0, 0, 0), f = 50, d = 22 },
		},
		MagOut = {
			Vis = { 0, 1.6 },
			Keys = {
				{ t = 0, sp = "seat", off = 0 },
				{ t = 0.27, sp = "seat", off = 0 },
				{ t = 0.37, sp = "seat", off = 0.8, r = V(0, 0, -8), e = "in" },
				{ t = 0.45, sp = "seat", off = 1.3, p = V(-0.5, 0, 0.2), r = V(-20, 0, -40), e = "out" },
				{ t = 0.451, sp = "free", v = V(-1.8, 3.7, -1.1), w = V(3, 4, 16) },
			},
		},
		MagIn = {
			Vis = { 0.55, 99 },
			Keys = {
				{ t = 0, sp = "cam", p = V(-0.75, -1.55, -1.0), r = V(-35, 0, 25) },
				{ t = 0.62, sp = "cam", p = V(-0.7, -1.45, -1.0), r = V(-35, 0, 25) },
				{ t = 0.86, sp = "seat", off = 0.9, p = V(-0.1, 0, 0.05), r = V(0, 0, 10), e = "io" },
				{ t = 0.97, sp = "seat", off = 0.25, e = "io" },
				{ t = 1.03, sp = "seat", off = 0, e = "snap" },
			},
		},
		Left = {
			{ t = 0, hold = "Support" },
			{ t = 0.22, hold = "MagOut", e = "out" },
			{ t = 0.45, hold = "MagOut", e = "lin" },
			{ t = 0.47, hold = "Freeze", d = V(-0.08, 0.12, 0), e = "out" },
			{ t = 0.62, hold = "MagIn", e = "io" },
			{ t = 1.03, hold = "MagIn", e = "lin" },
			{ t = 1.16, hold = "Part", part = "Charge", p = V(-0.15, 0.15, 0.1), e = "io" },
			{ t = 1.26, hold = "Part", part = "Charge", p = V(-0.05, 0.08, 0.05), e = "out" },
			{ t = 1.38, hold = "Part", part = "Charge", p = V(-0.05, 0.08, 0.05), e = "lin" },
			{ t = 1.44, hold = "Part", part = "Charge", p = V(-0.3, 0.25, 0.3), e = "out" },
			{ t = 1.68, hold = "Support", e = "io" },
			{ t = 2.1, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.2, 1), pv(1.5, 1), pv(1.75, 0) },
		Parts = { Charge = { pv(0, 0), pv(1.26, 0), pv(1.38, 1, "out"), pv(1.42, 1), pv(1.46, 0, "snap") } },
		Events = {
			{ t = 0.3, name = "MagOut" },
			{ t = 1.03, name = "MagIn" },
			{ t = 1.46, name = "Rack" },
		},
	},
}

-- ═══ Sentinel — "Strip & Charge" ═══════════════════════════════════════════════════════════
C.Sentinel = {
	Reload = {
		Choreo = true,
		Length = 2.3,
		Geo = { Eject = V(0, -0.99, -0.14), Charge = { Axis = V(0, 0, 1), Travel = 0.336 } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)),
			k(0.22, V(-0.227, 0.214, 0.007), V(3.4, 13.7, -43), "back"),
			k(0.46, V(-0.222, 0.219, 0.006), V(4.4, 13.6, -45.2)),
			k(0.5, V(-0.227, 0.241, 0.003), V(7.6, 15.4, -52.5), "out"),
			k(0.7, V(-0.213, 0.2, 0.01), V(0.3, 13.8, -40.2)),
			k(0.77, V(-0.213, 0.247, 0.003), V(7.5, 13.4, -35.9), "snap"),
			k(0.98, V(-0.248, 0.082, -0.286), V(5.1, -7.8, -12.1)),
			k(1.12, V(-0.242, 0.082, -0.286), V(3.1, -7.8, -10.3)),
			k(1.17, V(-0.234, 0.069, -0.283), V(0, -5.9, -9.1), "snap"),
			k(1.45, V(-0.086, 0.128, 0.002), V(-3, 2, 57.8)),
			k(1.75, V(-0.014, 0.014, -0.003), V(0, 0, -6), "back"),
			k(2.3, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = {
			{ t = 0.48, r = V(-2, 0, 3) },
			{ t = 0.77, r = V(-4, 0, 3), f = 40, d = 16 },
			{ t = 1.17, p = V(0, 0, 0.034), f = 50, d = 22 },
		},
		MagOut = {
			Vis = { 0, 1.9 },
			Keys = {
				{ t = 0, sp = "seat", off = 0 },
				{ t = 0.38, sp = "seat", off = 0 },
				{ t = 0.5, sp = "seat", off = 0.7, p = V(-0.4, 0, 0.1), r = V(-15, 0, -30), e = "out" },
				{ t = 0.501, sp = "free", v = V(-1.5, 3, -0.8), w = V(3, 3, 12) },
			},
		},
		MagIn = {
			Vis = { 0.5, 99 },
			Keys = {
				{ t = 0, sp = "cam", p = V(-0.75, -1.55, -1.0), r = V(-35, 0, 25) },
				{ t = 0.55, sp = "cam", p = V(-0.7, -1.45, -1.0), r = V(-35, 0, 25) },
				{ t = 0.68, sp = "seat", off = 0.9, p = V(-0.1, 0, 0.05), r = V(0, 0, 10), e = "io" },
				{ t = 0.74, sp = "seat", off = 0.25, e = "io" },
				{ t = 0.77, sp = "seat", off = 0, e = "snap" },
			},
		},
		Left = {
			{ t = 0, hold = "Support" },
			{ t = 0.3, hold = "MagOut", e = "out" },
			{ t = 0.5, hold = "MagOut", e = "lin" },
			{ t = 0.52, hold = "Freeze", d = V(-0.06, 0.1, 0), e = "out" },
			{ t = 0.6, hold = "MagIn", e = "io" },
			{ t = 0.77, hold = "MagIn", e = "lin" },
			{ t = 0.98, hold = "Part", part = "Charge", p = V(-0.15, 0.15, 0.1), e = "io" },
			{ t = 1.08, hold = "Part", part = "Charge", p = V(-0.05, 0.08, 0.05), e = "out" },
			{ t = 1.14, hold = "Part", part = "Charge", p = V(-0.05, 0.08, 0.05), e = "lin" },
			{ t = 1.2, hold = "Part", part = "Charge", p = V(-0.3, 0.25, 0.3), e = "out" },
			{ t = 1.5, hold = "Support", e = "io" },
			{ t = 2.3, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.2, 1), pv(1.4, 1), pv(1.7, 0) },
		Parts = { Charge = { pv(0, 0), pv(1.08, 0), pv(1.14, 1, "out"), pv(1.15, 1), pv(1.17, 0, "snap") } },
		Events = {
			{ t = 0.48, name = "MagOut" },
			{ t = 0.77, name = "MagIn" },
			{ t = 1.17, name = "Rack" },
		},
	},
}

-- ═══ Spectre — "Drop, Toss & Slide" ═══════════════════════════════════════════════════════
C.Spectre = {
	Reload = {
		Choreo = true,
		Length = 1.45,
		Geo = { Eject = V(0, -0.969, 0.247), Slide = { Axis = V(0, 0, 1), Travel = 0.1625 } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)),
			k(0.1, V(-0.093, 0.133, -0.153), V(12.5, 13.4, -39.9), "back"),
			k(0.16, V(-0.093, 0.16, -0.155), V(22.7, 12.6, -48.2), "out"),
			k(0.4, V(-0.125, 0.114, -0.171), V(8.5, 15.6, -33.4)),
			k(0.52, V(-0.11, 0.082, -0.15), V(2.2, 13.9, -27.5), "in"),
			k(0.57, V(-0.11, 0.133, -0.154), V(10.4, 13.6, -25.5), "snap"),
			k(0.68, V(-0.073, 0.097, -0.183), V(4.6, 21.8, -5.2)),
			k(0.74, V(-0.066, 0.086, -0.182), V(1.4, 22.9, -3.1)),
			k(0.79, V(-0.055, 0.129, -0.205), V(15.1, 19, -3.4), "snap"),
			k(1.0, V(0.005, 0.002, -0.068), V(2, 2, 21.8)),
			k(1.18, V(0, -0.027, 0.002), V(0, 0, -4), "back"),
			k(1.45, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = {
			{ t = 0.52, r = V(-6, 0, 2), f = 40, d = 16 },
			{ t = 0.775, p = V(0, 0, 0.041), r = V(5, 0, 1), f = 50, d = 22 },
		},
		MagOut = {
			Vis = { 0, 1.2 },
			Keys = {
				{ t = 0, sp = "seat", off = 0 },
				{ t = 0.1, sp = "seat", off = 0 },
				{ t = 0.2, sp = "seat", off = 0.5, e = "in" },
				{ t = 0.201, sp = "free", v = V(0, -3, 0.4), w = V(2, 0, 1) },
			},
		},
		MagIn = {
			Vis = { 0.1, 99 },
			Keys = {
				{ t = 0, sp = "cam", p = V(-0.6, -1.3, -0.9), r = V(-30, 0, 20) },
				{ t = 0.2, sp = "cam", p = V(-0.45, -0.9, -1.0), r = V(-20, 0, 40), e = "out" },
				{ t = 0.2001, sp = "free", v = V(0.6, 4.5, 0), w = V(0, 0, -9) },
				{ t = 0.39, sp = "cam", p = V(-0.25, -0.55, -1.1), e = "in" },
				{ t = 0.46, sp = "seat", off = 0.8, e = "io" },
				{ t = 0.5, sp = "seat", off = 0.25, e = "io" },
				{ t = 0.52, sp = "seat", off = 0, e = "snap" },
			},
		},
		Left = {
			{ t = 0, hold = "Support" },
			{ t = 0.12, hold = "MagIn", e = "io" },
			{ t = 0.2, hold = "MagIn", e = "lin" },
			{ t = 0.25, hold = "Freeze", d = V(0.05, 0.12, 0), e = "out" },
			{ t = 0.39, hold = "MagIn", e = "out" },
			{ t = 0.52, hold = "MagIn", e = "lin" },
			{ t = 0.66, hold = "Part", part = "Slide", p = V(0, 0.06, 0.1), e = "io" },
			{ t = 0.745, hold = "Part", part = "Slide", p = V(0, 0.06, 0.1), e = "lin" },
			{ t = 0.8, hold = "Part", part = "Slide", p = V(-0.15, 0.25, 0.3), e = "out" },
			{ t = 1.0, hold = "Support", e = "io" },
			{ t = 1.45, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.1, 1), pv(0.95, 1), pv(1.15, 0) },
		Parts = { Slide = { pv(0, 0), pv(0.68, 0), pv(0.745, 1, "out"), pv(0.76, 1), pv(0.775, 0, "snap") } },
		Events = {
			{ t = 0.2, name = "MagOut" },
			{ t = 0.52, name = "MagIn" },
			{ t = 0.775, name = "Rack" },
		},
	},
}

-- ═══ Longshot — "Bolt Open, Swap, Bolt Home" (bolt on the LEFT: the left hand works it) ══════
C.Longshot = {
	Reload = {
		Choreo = true,
		Length = 2.9,
		Geo = {
			Eject = V(0, -1, 0),
			Bolt = { Axis = V(0, 0, 1), Travel = 0.546, Angle = -78, Pivot = V(0.17, 0.03, 0) },
		},
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)),
			k(0.22, V(0.037, 0.057, -0.095), V(4, -2.9, -21.4), "back"),
			k(0.6, V(0.029, 0.063, -0.095), V(5, -2.9, -23.3)),
			k(0.66, V(0.03, 0.076, -0.083), V(7, -2.9, -21.2), "snap"),
			k(0.92, V(-0.193, 0.202, -0.067), V(2.2, 10.8, -43.9)),
			k(1.55, V(-0.193, 0.188, -0.065), V(0.1, 10.9, -41.5)),
			k(1.68, V(-0.188, 0.169, -0.062), V(-1.9, 10.9, -39.2), "in"),
			k(1.75, V(-0.188, 0.215, -0.068), V(6.3, 10.7, -36.7), "snap"),
			k(1.98, V(0.037, 0.063, -0.095), V(2, -3, -19.5)),
			k(2.04, V(0.037, 0.05, -0.108), V(0, -3, -19.6), "snap"),
			k(2.14, V(0.033, 0.087, -0.084), V(5, -1.9, -15.5), "snap"),
			k(2.42, V(0.014, 0.027, -0.005), V(1, -1, 6.2)),
			k(2.9, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = {
			{ t = 1.72, r = V(-4, 0, 3), f = 40, d = 16 },
			{ t = 2.14, r = V(-5, -1, -2), f = 46, d = 20 },
		},
		MagOut = {
			Vis = { 0, 2.0 },
			Keys = {
				{ t = 0, sp = "seat", off = 0 },
				{ t = 0.9, sp = "seat", off = 0 },
				{ t = 0.98, sp = "seat", off = 0.5, e = "in" },
				{ t = 0.981, sp = "free", v = V(-0.4, -2.5, 0.2), w = V(1, 0, 3) },
			},
		},
		MagIn = {
			Vis = { 1.0, 99 },
			Keys = {
				{ t = 0, sp = "cam", p = V(-0.75, -1.55, -1.0), r = V(-35, 0, 25) },
				{ t = 1.25, sp = "cam", p = V(-0.7, -1.45, -1.0), r = V(-35, 0, 25) },
				{ t = 1.55, sp = "seat", off = 0.9, p = V(-0.1, 0, 0.05), r = V(0, 0, 10), e = "io" },
				{ t = 1.68, sp = "seat", off = 0.25, e = "io" },
				{ t = 1.72, sp = "seat", off = 0, e = "snap" },
			},
		},
		Left = {
			{ t = 0, hold = "Support" },
			{ t = 0.2, hold = "Part", part = "Bolt", p = V(-0.05, 0.02, 0), e = "io" },
			{ t = 0.66, hold = "Part", part = "Bolt", p = V(-0.05, 0.02, 0), e = "lin" },
			{ t = 0.85, hold = "MagOut", e = "io" },
			{ t = 0.95, hold = "MagOut", e = "lin" },
			{ t = 1.0, hold = "Freeze", d = V(-0.05, 0.1, 0), e = "out" },
			{ t = 1.25, hold = "MagIn", e = "io" },
			{ t = 1.72, hold = "MagIn", e = "lin" },
			{ t = 1.84, hold = "Part", part = "Bolt", p = V(-0.05, 0.02, 0), e = "io" },
			{ t = 2.16, hold = "Part", part = "Bolt", p = V(-0.05, 0.02, 0), e = "lin" },
			{ t = 2.42, hold = "Support", e = "io" },
			{ t = 2.9, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.2, 1), pv(2.2, 1), pv(2.45, 0) },
		Parts = {
			BoltR = { pv(0, 0), pv(0.22, 0), pv(0.3, 1, "out"), pv(2.06, 1), pv(2.14, 0, "snap") },
			BoltS = { pv(0, 0), pv(0.32, 0), pv(0.44, 1, "out"), pv(1.86, 1), pv(1.98, 0, "snap") },
		},
		Events = {
			{ t = 0.44, name = "Rack" },
			{ t = 0.98, name = "MagOut" },
			{ t = 1.72, name = "MagIn" },
			{ t = 2.14, name = "Rack" },
		},
	},
}

-- ═══ Arc — "Cell Flip" vent: the power cell pops, gets flipped in the hand and slammed home ══
C.Arc = {
	Vent = {
		Choreo = true,
		Length = 1.8,
		Geo = { Eject = V(0, 0.475, 0.88) },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)),
			k(0.12, V(-0.032, 0.035, 0.049), V(8, -1.9, -13.4), "out"),
			k(0.36, V(-0.169, 0.168, -0.007), V(2.8, -21.6, -34)),
			k(0.95, V(-0.183, 0.168, -0.008), V(0.5, -19.8, -33.1)),
			k(1.1, V(-0.183, 0.146, -0.005), V(-1.6, -19.9, -31.8), "in"),
			k(1.16, V(-0.183, 0.196, -0.012), V(6.9, -19.4, -25), "snap"),
			k(1.4, V(-0.028, 0.027, -0.006), V(0, 0, 10)),
			k(1.8, V(0, 0, 0), V(0, 0, 0), "back"),
		},
		Kicks = { { t = 1.12, r = V(-4, 0, 2), f = 40, d = 16 } },
		MagOut = {
			Keys = {
				{ t = 0, sp = "seat", off = 0 },
				{ t = 0.1, sp = "seat", off = 0 },
				{ t = 0.17, sp = "seat", off = 0.07, e = "out" },
				{ t = 0.36, sp = "seat", off = 0.07 },
				{ t = 0.55, sp = "seat", off = 0.55, e = "io" },
				{ t = 0.62, sp = "seat", off = 0.6, p = V(-0.15, 0.1, 0) },
				{ t = 0.66, sp = "seat", off = 0.6, p = V(-0.15, 0.1, 0), r = V(0, 0, 90), e = "lin" },
				{ t = 0.7, sp = "seat", off = 0.6, p = V(-0.15, 0.1, 0), r = V(0, 0, 180), e = "lin" },
				{ t = 0.74, sp = "seat", off = 0.6, p = V(-0.15, 0.1, 0), r = V(0, 0, 270), e = "lin" },
				{ t = 0.78, sp = "seat", off = 0.6, p = V(-0.15, 0.1, 0), r = V(0, 0, 360), e = "out" },
				{ t = 0.95, sp = "seat", off = 0.55, r = V(0, 0, 360), e = "io" },
				{ t = 1.1, sp = "seat", off = 0.15, r = V(0, 0, 360), e = "io" },
				{ t = 1.12, sp = "seat", off = 0, e = "snap" },
			},
		},
		Left = {
			{ t = 0, hold = "Support" },
			{ t = 0.3, hold = "MagOut", e = "io" },
			{ t = 1.12, hold = "MagOut", e = "lin" },
			{ t = 1.4, hold = "Support", e = "io" },
			{ t = 1.8, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.25, 1), pv(1.15, 1), pv(1.4, 0) },
		Events = {
			{ t = 0.17, name = "MagOut" },
			{ t = 1.12, name = "MagIn" },
		},
	},
}

-- ═══ Breacher — "Tilt & Feed": rolled to show the port, one shell pushed per ShellIn ════════
-- (ammo +1 lands at the end of each ShellIn in WeaponController; the push completes just before)
local TILT_P, TILT_R = V(-0.18, 0.2, 0.04), V(4, 10, -55)
local PORT_READY = V(0, -0.6, 0.05)
local BREACHER_GEO = { Pump = { Axis = V(0, 0, 1), Travel = 0.315 } }
C.Breacher = {
	ReloadStart = {
		Choreo = true,
		Length = 0.35,
		Geo = BREACHER_GEO,
		Gun = { k(0, V(0, 0, 0), V(0, 0, 0)), k(0.25, TILT_P, TILT_R, "back"), k(0.35, TILT_P, TILT_R) },
		Left = {
			{ t = 0, hold = "Support" },
			{ t = 0.3, hold = "Gun", p = PORT_READY, e = "io" },
			{ t = 0.35, hold = "Gun", p = PORT_READY },
		},
		Reach = { pv(0, 0), pv(0.2, 1), pv(0.35, 1) },
		Events = {},
	},
	ShellIn = {
		Choreo = true,
		Length = 0.48,
		Geo = BREACHER_GEO,
		Gun = {
			k(0, TILT_P, TILT_R),
			k(0.38, TILT_P, TILT_R),
			k(0.42, TILT_P + V(0, 0.01, -0.02), TILT_R + V(2, 0, 2), "in"),
			k(0.48, TILT_P, TILT_R, "out"),
		},
		Kicks = { { t = 0.42, r = V(-2, 0, 1), f = 46, d = 22 } },
		Left = {
			{ t = 0, hold = "Gun", p = PORT_READY },
			{ t = 0.13, hold = "Cam", p = V(-0.5, -0.95, -0.85), e = "io" },
			{ t = 0.3, hold = "Gun", p = V(0, -0.75, 0.15), e = "io" },
			{ t = 0.42, hold = "Gun", p = V(0, -0.5, -0.2), e = "in" },
			{ t = 0.48, hold = "Gun", p = PORT_READY, e = "out" },
		},
		Reach = { pv(0, 1), pv(0.48, 1) },
		Events = {},
	},
	ReloadEnd = {
		Choreo = true,
		Length = 0.4,
		Geo = BREACHER_GEO,
		Gun = {
			k(0, TILT_P, TILT_R),
			k(0.12, V(-0.02, 0.05, 0.04), V(-3, 0, 4), "io"),
			k(0.2, V(0, 0, 0.05), V(2, 0, 0)),
			k(0.4, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.24, p = V(0, 0, 0.04), f = 50, d = 22 } },
		Left = {
			{ t = 0, hold = "Gun", p = PORT_READY },
			{ t = 0.1, hold = "Support", e = "io" },
			{ t = 0.4, hold = "Support" },
		},
		Reach = { pv(0, 1), pv(0.3, 0) },
		Parts = { Pump = { pv(0, 0), pv(0.1, 0), pv(0.17, 1, "out"), pv(0.19, 1), pv(0.24, 0, "snap") } },
		Events = { { t = 0.22, name = "Rack" } },
	},
}


-- ═══ New guns, 2026-11-18 (Blender models from the user's concepts; new-guns-reload-code.md) ═══
C.Riptide = {
	Reload = {
		Choreo = true, Length = 1.75,
		Geo = { Eject = V(0, -0.984, -0.18), Charge = { Axis = V(0, 0, 1), Travel = 0.16 } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)), k(0.16, V(-0.2, 0.24, 0.04), V(4, 14, -40), "back"), k(0.40, V(-0.21, 0.25, 0.04), V(5, 15, -44)),
			k(0.44, V(-0.21, 0.27, 0.04), V(8, 15, -46), "snap"), k(0.62, V(-0.2, 0.23, 0.05), V(1, 14, -38), "in"), k(0.68, V(-0.2, 0.28, 0.04), V(7, 13, -34), "snap"),
			k(0.84, V(-0.06, 0.12, -0.18), V(6, 4, 30)), k(0.96, V(-0.04, 0.12, -0.18), V(6, 4, 36)), k(1.02, V(-0.03, 0.09, -0.15), V(3, 2, 26), "snap"),
			k(1.22, V(-0.03, 0.07, 0.02), V(-6, -2, -10), "back"), k(1.45, V(-0.01, 0.02, 0.02), V(-2, 0, -2)), k(1.75, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.44, r = V(-3, 0, 4), f = 44, d = 18 }, { t = 0.68, r = V(-5, 0, 3), f = 40, d = 16 }, { t = 1.02, p = V(0, 0, 0.035), f = 50, d = 22 } },
		MagOut = { Vis = { 0, 1.4 }, Keys = { { t = 0, sp = "seat", off = 0 }, { t = 0.43, sp = "seat", off = 0 }, { t = 0.431, sp = "free", v = V(-1.4, -1.2, 0.4), w = V(3, 2, 12) } } },
		MagIn = { Vis = { 0.1, 99 }, Keys = {
			{ t = 0, sp = "cam", p = V(-0.7, -1.4, -1.0), r = V(-35, 0, 25) }, { t = 0.12, sp = "cam", p = V(-0.7, -1.4, -1.0), r = V(-35, 0, 25) },
			{ t = 0.30, sp = "seat", off = 0.75, p = V(-0.12, 0, 0.04), r = V(0, 0, 14), e = "io" }, { t = 0.43, sp = "seat", off = 0.42, e = "in" },
			{ t = 0.60, sp = "seat", off = 0.22, e = "io" }, { t = 0.68, sp = "seat", off = 0, e = "snap" } } },
		Left = {
			{ t = 0, hold = "Support" }, { t = 0.12, hold = "MagIn", e = "io" }, { t = 0.68, hold = "MagIn", e = "lin" },
			{ t = 0.84, hold = "Part", part = "Charge", p = V(-0.08, 0.06, 0.02), e = "io" }, { t = 0.96, hold = "Part", part = "Charge", p = V(-0.08, 0.06, 0.02), e = "lin" },
			{ t = 1.04, hold = "Part", part = "Charge", p = V(-0.25, 0.2, 0.25), e = "out" }, { t = 1.3, hold = "Support", e = "io" }, { t = 1.75, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.12, 1), pv(1.25, 1), pv(1.45, 0) },
		Parts = { Charge = { pv(0, 0), pv(0.86, 0), pv(0.96, 1, "out"), pv(0.99, 1), pv(1.02, 0, "snap") } },
		Events = { { t = 0.43, name = "MagOut" }, { t = 0.68, name = "MagIn" }, { t = 1.02, name = "Rack" } },
	},
}

C.Bulwark = {
	Reload = {
		Choreo = true, Length = 3.2,
		Geo = { Eject = V(0, -1, 0), Barrels = { Spin = true, SpinAxis = V(0, 0, 1), SpinPivot = V(0, -0.076, -2.52) } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)), k(0.25, V(-0.18, 0.2, 0.06), V(6, 12, -38), "back"), k(0.5, V(-0.19, 0.21, 0.06), V(7, 12, -40)),
			k(0.56, V(-0.19, 0.24, 0.06), V(10, 12, -42), "snap"), k(1.3, V(-0.18, 0.2, 0.06), V(4, 12, -37)), k(1.42, V(-0.18, 0.17, 0.06), V(1, 12, -35), "in"),
			k(1.5, V(-0.18, 0.25, 0.06), V(9, 11, -31), "snap"), k(1.75, V(-0.05, 0.18, -0.05), V(-4, 2, -6)), k(1.85, V(-0.05, 0.14, -0.05), V(-7, 2, -6), "snap"),
			k(2.2, V(0, 0.03, 0.02), V(2, 0, 0)), k(3.2, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.56, r = V(-3, 0, 3) }, { t = 1.5, r = V(-6, 0, 4), f = 36, d = 12 }, { t = 1.85, p = V(0, -0.03, 0), r = V(-5, 0, 1) }, { t = 2.0, p = V(0, 0, 0.02), f = 60, d = 8 } },
		MagOut = { Vis = { 0, 1.6 }, Keys = { { t = 0, sp = "seat", off = 0 }, { t = 0.5, sp = "seat", off = 0 }, { t = 0.6, sp = "seat", off = 0.25, e = "in" }, { t = 0.601, sp = "free", v = V(0.2, -2.6, 0.2), w = V(1.2, 0, 2.5) } } },
		MagIn = { Vis = { 0.6, 99 }, Keys = {
			{ t = 0, sp = "cam", p = V(-0.8, -1.7, -1.1), r = V(-25, 0, 20) }, { t = 0.75, sp = "cam", p = V(-0.8, -1.7, -1.1), r = V(-25, 0, 20) },
			{ t = 1.25, sp = "seat", off = 0.75, p = V(-0.15, 0, 0), r = V(0, 0, 10), e = "io" }, { t = 1.42, sp = "seat", off = 0.12, e = "io" }, { t = 1.5, sp = "seat", off = 0, e = "snap" } } },
		Left = {
			{ t = 0, hold = "Support" }, { t = 0.4, hold = "MagOut", e = "io" }, { t = 0.56, hold = "MagOut", e = "lin" }, { t = 0.62, hold = "Freeze", d = V(-0.05, 0.1, 0), e = "out" },
			{ t = 0.85, hold = "MagIn", e = "io" }, { t = 1.5, hold = "MagIn", e = "lin" }, { t = 1.72, hold = "Gun", p = V(0, 0.55, -0.3), e = "io" },
			{ t = 1.85, hold = "Gun", p = V(0, 0.46, -0.3), e = "in" }, { t = 2.15, hold = "Support", e = "io" }, { t = 3.2, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.35, 1), pv(2.0, 1), pv(2.25, 0) },
		Parts = { BarrelsSpin = { pv(0, 0), pv(1.9, 0), pv(3.0, 3, "io"), pv(3.2, 3) } },
		Events = { { t = 0.6, name = "MagOut" }, { t = 1.5, name = "MagIn" }, { t = 1.85, name = "Rack" } },
	},
}

local CRANE_P, CRANE_R = V(-0.146, -0.134, 0), V(0, 0, 85)
C.Verdict = {
	Reload = {
		Choreo = true, Length = 2.3,
		Geo = {
			Eject = V(0, 0, 1),
			Cylinder = { Angle = 85, RotAxis = V(0, 0, 1), Pivot = V(0, -0.214, 0), Spin = true, SpinAxis = V(0, 0, 1), SpinPivot = V(0, -0.067, 0) },
			Hammer = { Angle = 35, RotAxis = V(1, 0, 0), Pivot = V(0, -0.018, 0.289) },
		},
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)), k(0.15, V(-0.05, 0.1, -0.05), V(5, 8, -30), "back"), k(0.3, V(-0.05, 0.12, -0.05), V(6, 8, -34)),
			k(0.42, V(-0.02, 0.2, 0), V(60, 6, -20), "out"), k(0.55, V(-0.02, 0.21, 0), V(64, 6, -20)), k(0.7, V(-0.08, 0.08, -0.06), V(-8, 10, -35), "io"),
			k(1.2, V(-0.08, 0.06, -0.06), V(-10, 10, -36)), k(1.28, V(-0.08, 0.04, -0.06), V(-12, 10, -36), "in"), k(1.36, V(0.02, 0.06, -0.03), V(2, -4, 12), "snap"),
			k(1.6, V(0, 0.02, 0), V(-2, 0, -4), "back"), k(1.72, V(0, 0.01, 0), V(4, 0, 0), "snap"), k(2.3, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.42, r = V(6, 0, 0) }, { t = 1.36, r = V(-4, 0, -3), f = 46, d = 18 }, { t = 1.72, p = V(0, 0, 0.015), r = V(-2, 0, 0) } },
		MagOut = { Vis = { 0, 1.5 }, Keys = {
			{ t = 0, sp = "seat", off = 0 }, { t = 0.15, sp = "seat", off = 0 }, { t = 0.3, sp = "seat", p = CRANE_P, r = CRANE_R, e = "back" },
			{ t = 0.48, sp = "seat", p = CRANE_P + V(0, 0, 0.08), r = CRANE_R, e = "out" }, { t = 0.481, sp = "free", v = V(0, -2.5, 0.6), w = V(4, 0, 1) } } },
		MagIn = { Vis = { 0.55, 99 }, Keys = {
			{ t = 0, sp = "cam", p = V(-0.6, -1.2, -0.9), r = V(-20, 0, 30) }, { t = 0.7, sp = "cam", p = V(-0.6, -1.2, -0.9), r = V(-20, 0, 30) },
			{ t = 1.15, sp = "seat", p = CRANE_P + V(0, 0, 0.12), r = CRANE_R, e = "io" }, { t = 1.28, sp = "seat", p = CRANE_P, r = CRANE_R, e = "in" }, { t = 1.36, sp = "seat", off = 0, e = "snap" } } },
		Left = {
			{ t = 0, hold = "Support" }, { t = 0.2, hold = "Part", part = "Cylinder", p = V(-0.08, 0, 0), e = "io" }, { t = 0.3, hold = "Part", part = "Cylinder", p = V(-0.08, 0, 0), e = "lin" },
			{ t = 0.42, hold = "Part", part = "Cylinder", p = V(-0.05, -0.05, 0.12), e = "io" }, { t = 0.5, hold = "Part", part = "Cylinder", p = V(-0.05, -0.05, 0.12), e = "lin" },
			{ t = 0.7, hold = "MagIn", e = "io" }, { t = 1.28, hold = "MagIn", e = "lin" }, { t = 1.5, hold = "Support", e = "io" }, { t = 2.3, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.15, 1), pv(1.45, 1), pv(1.6, 0) },
		Parts = {
			CylinderR = { pv(0, 0), pv(0.15, 0), pv(0.3, 1, "back"), pv(1.3, 1), pv(1.36, 0, "snap") },
			CylinderSpin = { pv(0, 0), pv(0.62, 0), pv(1.1, 1, "out"), pv(2.3, 1) },
			HammerR = { pv(0, 0), pv(1.6, 0), pv(1.68, 1, "out"), pv(1.72, 1), pv(1.76, 0, "snap") },
		},
		Events = { { t = 0.48, name = "MagOut" }, { t = 1.36, name = "MagIn" }, { t = 1.72, name = "Rack" } },
	},
}

C.Quill = {
	Reload = {
		Choreo = true, Length = 1.9,
		Geo = { Eject = V(0, 0.25, 0.97), LimbT = { Angle = 8, RotAxis = V(1, 0, 0), Pivot = V(0, 0.216, -2.376) }, LimbB = { Angle = -8, RotAxis = V(1, 0, 0), Pivot = V(0, -0.216, -2.376) } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)), k(0.18, V(-0.04, 0.06, 0), V(-14, 6, -18), "back"), k(0.5, V(-0.04, 0.03, 0.04), V(-16, 6, -18)),
			k(0.56, V(-0.04, 0.07, 0), V(-10, 6, -16), "snap"), k(1.15, V(-0.06, 0.08, -0.02), V(-6, 8, -22)), k(1.22, V(-0.06, 0.06, -0.02), V(-8, 8, -22), "in"),
			k(1.28, V(-0.03, 0.09, -0.02), V(-2, 6, -18), "snap"), k(1.6, V(0, 0.02, 0), V(2, 0, 2), "back"), k(1.9, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.56, p = V(0, 0, 0.03), r = V(-4, 0, 0) }, { t = 1.28, r = V(-3, 0, 2) } },
		MagOut = { Vis = { 0, 0 }, Keys = { { t = 0, sp = "seat", off = 0 } } },
		MagIn = { Vis = { 0.55, 99 }, Keys = {
			{ t = 0, sp = "cam", p = V(-0.55, -1.1, -0.9), r = V(-20, 0, 60) }, { t = 0.62, sp = "cam", p = V(-0.55, -1.1, -0.9), r = V(-20, 0, 60) },
			{ t = 1.0, sp = "seat", off = 0.5, e = "io" }, { t = 1.22, sp = "seat", off = 0.12, e = "in" }, { t = 1.28, sp = "seat", off = 0, e = "snap" } } },
		Left = {
			{ t = 0, hold = "Support" }, { t = 0.2, hold = "Gun", p = V(-0.03, 0.22, -0.62), e = "io" }, { t = 0.5, hold = "Gun", p = V(-0.03, 0.22, -0.32), e = "in" },
			{ t = 0.56, hold = "Gun", p = V(-0.03, 0.22, -0.32), e = "lin" }, { t = 0.68, hold = "MagIn", e = "io" }, { t = 1.28, hold = "MagIn", e = "lin" },
			{ t = 1.5, hold = "Support", e = "io" }, { t = 1.9, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.15, 1), pv(1.4, 1), pv(1.6, 0) },
		Parts = {
			LimbTR = { pv(0, 0), pv(0.2, 0), pv(0.5, 1, "in"), pv(0.56, 0, "snap") },
			LimbBR = { pv(0, 0), pv(0.2, 0), pv(0.5, 1, "in"), pv(0.56, 0, "snap") },
		},
		Events = { { t = 0.56, name = "Rack" }, { t = 1.28, name = "MagIn" } },
	},
}

C.Helix = {
	Reload = {
		Choreo = true, Length = 1.8,
		Geo = { Eject = V(0, 1, 0), Coil = { Spin = true, SpinAxis = V(0, 0, 1), SpinPivot = V(0, 0, -1.226) } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)), k(0.15, V(-0.15, 0.15, 0), V(4, -14, -30), "out"), k(0.5, V(-0.16, 0.16, 0), V(3, -16, -32)),
			k(0.95, V(-0.16, 0.15, 0), V(2, -16, -31)), k(1.02, V(-0.16, 0.12, 0), V(0, -16, -30), "in"), k(1.08, V(-0.15, 0.18, -0.01), V(8, -15, -26), "snap"),
			k(1.3, V(-0.02, 0.05, 0), V(-6, 0, 4)), k(1.5, V(0, 0.06, 0), V(-8, 0, 0)), k(1.8, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.22, r = V(4, 0, 0) }, { t = 1.08, r = V(-5, 0, 3), f = 40, d = 14 }, { t = 1.4, p = V(0, 0, 0.04), r = V(-3, 0, 0), f = 70, d = 10 } },
		MagOut = { Vis = { 0, 1.4 }, Keys = {
			{ t = 0, sp = "seat", off = 0 }, { t = 0.22, sp = "seat", off = 0.12, e = "out" }, { t = 0.38, sp = "seat", off = 0.12 },
			{ t = 0.5, sp = "seat", off = 0.5, p = V(-0.1, 0, 0), e = "io" }, { t = 0.501, sp = "free", v = V(-1.6, 1.8, 0.3), w = V(4, 2, 8) } } },
		MagIn = { Vis = { 0.5, 99 }, Keys = {
			{ t = 0, sp = "cam", p = V(-0.7, -1.3, -1.0), r = V(-30, 0, 20) }, { t = 0.6, sp = "cam", p = V(-0.7, -1.3, -1.0), r = V(-30, 0, 20) },
			{ t = 0.92, sp = "seat", off = 0.55, p = V(-0.08, 0, 0), r = V(0, 0, 8), e = "io" }, { t = 1.02, sp = "seat", off = 0.12, e = "io" }, { t = 1.08, sp = "seat", off = 0, e = "snap" } } },
		Left = {
			{ t = 0, hold = "Support" }, { t = 0.3, hold = "MagOut", e = "io" }, { t = 0.5, hold = "MagOut", e = "lin" }, { t = 0.54, hold = "Freeze", d = V(-0.06, 0.1, 0), e = "out" },
			{ t = 0.66, hold = "MagIn", e = "io" }, { t = 1.08, hold = "MagIn", e = "lin" }, { t = 1.3, hold = "Support", e = "io" }, { t = 1.8, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.25, 1), pv(1.15, 1), pv(1.35, 0) },
		Parts = { CoilSpin = { pv(0, 0), pv(1.08, 0), pv(1.75, 4, "io"), pv(1.8, 4) } },
		Events = { { t = 0.22, name = "MagOut" }, { t = 1.08, name = "MagIn" } },
	},
}
C.Helix.Vent = C.Helix.Reload

C.Havoc = {
	Reload = {
		Choreo = true, Length = 2.6,
		Geo = { Eject = V(-0.989, -0.148, 0), Pump = { Axis = V(0, 0, 1), Travel = 0.22 } },
		Gun = {
			k(0, V(0, 0, 0), V(0, 0, 0)), k(0.22, V(-0.12, 0.16, 0.02), V(4, 10, -25), "back"), k(0.5, V(-0.13, 0.17, 0.02), V(5, 10, -28)),
			k(0.56, V(-0.12, 0.19, 0.02), V(7, 10, -30), "out"), k(1.3, V(-0.12, 0.16, 0.02), V(3, 10, -24)), k(1.38, V(-0.12, 0.14, 0.02), V(1, 10, -23), "in"),
			k(1.44, V(-0.11, 0.2, 0.02), V(8, 9, -20), "snap"), k(1.65, V(-0.02, 0.06, -0.04), V(-3, 2, -4)), k(1.82, V(-0.02, 0.05, 0.02), V(-2, 1, -3)),
			k(1.92, V(-0.02, 0.07, -0.03), V(-5, 1, -3), "snap"), k(2.2, V(0, 0.02, 0), V(2, 0, 0), "back"), k(2.6, V(0, 0, 0), V(0, 0, 0)),
		},
		Kicks = { { t = 0.56, r = V(-2, 0, 3) }, { t = 1.44, r = V(-6, 0, 3), f = 36, d = 12 }, { t = 1.92, p = V(0, 0, 0.04), r = V(-4, 0, 0), f = 48, d = 18 } },
		MagOut = { Vis = { 0, 1.6 }, Keys = {
			{ t = 0, sp = "seat", off = 0 }, { t = 0.35, sp = "seat", off = 0 }, { t = 0.52, sp = "seat", off = 0.35, e = "io" },
			{ t = 0.56, sp = "seat", off = 0.45, p = V(0, 0.05, 0), r = V(0, 0, -20), e = "out" }, { t = 0.561, sp = "free", v = V(-2.4, 1.0, -0.3), w = V(0, 3, 7) } } },
		MagIn = { Vis = { 0.6, 99 }, Keys = {
			{ t = 0, sp = "cam", p = V(-0.9, -1.4, -1.0), r = V(-20, 0, 20) }, { t = 0.7, sp = "cam", p = V(-0.9, -1.4, -1.0), r = V(-20, 0, 20) },
			{ t = 1.2, sp = "seat", off = 0.7, p = V(0, 0.05, 0), r = V(0, 0, -15), e = "io" }, { t = 1.38, sp = "seat", off = 0.12, e = "io" }, { t = 1.44, sp = "seat", off = 0, e = "snap" } } },
		Left = {
			{ t = 0, hold = "Support" }, { t = 0.3, hold = "MagOut", e = "io" }, { t = 0.56, hold = "MagOut", e = "lin" }, { t = 0.6, hold = "Freeze", d = V(-0.06, 0.1, 0), e = "out" },
			{ t = 0.75, hold = "MagIn", e = "io" }, { t = 1.44, hold = "MagIn", e = "lin" }, { t = 1.66, hold = "Support", e = "io" }, { t = 2.6, hold = "Support" },
		},
		Reach = { pv(0, 0), pv(0.25, 1), pv(2.05, 1), pv(2.25, 0) },
		Parts = { Pump = { pv(0, 0), pv(1.72, 0), pv(1.82, 1, "out"), pv(1.86, 1), pv(1.92, 0, "snap") } },
		Events = { { t = 0.56, name = "MagOut" }, { t = 1.44, name = "MagIn" }, { t = 1.92, name = "Rack" } },
	},
}
return C
