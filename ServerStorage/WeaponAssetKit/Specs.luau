--[[
	Tripo weapon wrapper specs (edit + re-run WeaponAssetKit.Build to retune; meshes are never edited).
	Points are read from side renders of each FBX in normalised mesh units:
		x = along the length (-0.5 .. 0.5, as exported), z = height above the mesh bottom.
	Length     final model length in studs (the Root-space size the configs are tuned for)
	MuzzleDir  -1 = muzzle at mesh -X (most models), +1 = muzzle at +X (ER-04 Arc)
	Pitch      degrees to level the sight line (+ raises the muzzle)
	Anchor     Root-space position the Handle (right hand) lands on
	Rot        attachment rotations (degrees XYZ) — hand orientation for the IK rig
]]
local RIFLE_ANCHOR = Vector3.new(0, -0.49, 0.37) -- same as the old procedural VX-01, so tuned poses carry over
local HANDLE_ROT = Vector3.new(-18, 0, 0)
local SUPPORT_ROT = Vector3.new(-90, -90, 0)

return {
	Vanguard = {
		Length = 4.6, MuzzleDir = -1, Pitch = 0, Anchor = RIFLE_ANCHOR, SupportSpin = -75,
		-- reload prop, inside the mesh's canted box mag (from the side render grid)
		MagProp = { Top = { 0.058, 0.155, 0.003 }, Bottom = { 0.045, 0.02, 0.003 }, Depth = 0.058, Width = 0.028 },
		Points = {
			Handle = { 0.215, 0.115 }, Support = { -0.10, 0.205 }, SupportTP = { -0.09, 0.205 },
			-- holo window opening (raycast through the mesh, front + rear concentric): y -0.014..0.025,
			-- z 0.315..0.340. ADSPoint = its centre on the rear face; WindowA/B = opposite corners, which
			-- the HUD projects to draw a straight window frame while aimed.
			-- (calibrated against the in-game sight picture: visible opening centre z 0.3264, half-size
			-- 0.022 x 0.0166; the frame sits just inside it so its border hides the uneven rim)
			-- holo window measured as a see-through hole (Blender rays): opening sideways -0.0105..0.0205,
			-- height 0.316..0.338, glass plane x ~0.093. ADSPoint = its centre, WindowA/B = its corners.
			Muzzle = { -0.50, 0.245 }, ADSPoint = { 0.093, 0.327, 0.005 }, EjectPoint = { 0.05, 0.235 },
			-- frame corners on the window's FRONT lip (x 0.05), the inner edge the eye actually sees
			WindowA = { 0.05, 0.3374, -0.0100 }, WindowB = { 0.05, 0.3149, 0.0203 },
			Shoulder = { 0.50, 0.21 }, Magazine = { 0.01, 0.07 },
		},
	},
	Sentinel = {
		Length = 4.2, MuzzleDir = -1, Pitch = 0, Anchor = RIFLE_ANCHOR,
		-- reload prop, inside the mesh's forward-canted mag (from the side render grid)
		MagProp = { Top = { -0.005, 0.15, -0.0045 }, Bottom = { -0.03, 0.02, -0.0045 }, Depth = 0.07, Width = 0.028 },
		Points = {
			Handle = { 0.185, 0.115 }, Support = { -0.22, 0.205 }, SupportTP = { -0.10, 0.205 },
			-- optic axis measured from the eyepiece rings (Blender depth map); LensEdge = glass top
			Muzzle = { -0.50, 0.25 }, ADSPoint = { 0.177, 0.342, -0.003 }, LensEdge = { 0.177, 0.362, -0.003 }, EjectPoint = { 0.08, 0.255 },
			Shoulder = { 0.50, 0.22 }, Magazine = { 0.0, 0.08 },
		},
	},
	Spectre = {
		Length = 1.25, MuzzleDir = -1, Pitch = 4.0, Anchor = Vector3.new(0, -0.3, 0.18), SupportSpin = 0,
		-- reload prop: runs up inside the slanted grip, base plate just above the grip's own floorplate
		MagProp = { Top = { 0.26, 0.40, -0.015 }, Bottom = { 0.335, 0.06, -0.015 }, Depth = 0.085, Width = 0.055 },
		HandleRot = Vector3.new(-14, 0, 0),
		Points = {
			Handle = { 0.29, 0.40 }, Support = { 0.31, 0.30 }, SupportTP = { 0.31, 0.30 },
			Muzzle = { -0.50, 0.635 }, ADSPoint = { 0.36, 0.765 }, EjectPoint = { 0.02, 0.70 },
			Shoulder = { 0.40, 0.45 }, Magazine = { 0.30, 0.04 },
		},
	},
	Breacher = {
		Length = 4.2, MuzzleDir = -1, Pitch = 0, Anchor = RIFLE_ANCHOR,
		Points = {
			Handle = { 0.19, 0.085 }, Support = { -0.17, 0.12 }, SupportTP = { -0.12, 0.12 },
			Muzzle = { -0.50, 0.215 }, ADSPoint = { 0.05, 0.262 }, EjectPoint = { 0.0, 0.19 },
			Shoulder = { 0.50, 0.17 }, Magazine = { 0.03, 0.09 },
		},
	},
	Longshot = {
		Length = 5.2, MuzzleDir = -1, Pitch = 0, Anchor = RIFLE_ANCHOR,
		-- reload prop: the short detachable box ahead of the trigger guard
		MagProp = { Top = { 0.10, 0.155, 0.019 }, Bottom = { 0.10, 0.103, 0.019 }, Depth = 0.062, Width = 0.03 },
		Points = {
			Handle = { 0.23, 0.085 }, Support = { -0.12, 0.15 }, SupportTP = { -0.04, 0.15 },
			-- scope axis measured in Blender (eyepiece glass + tube cross-sections): the scope sits
			-- 0.0183 off the gun's centreline; LensEdge = top of the eyepiece glass (radius 0.022)
			Muzzle = { -0.50, 0.185 }, ADSPoint = { 0.265, 0.258, 0.0183 }, LensEdge = { 0.265, 0.280, 0.0183 }, EjectPoint = { 0.12, 0.17 },
			Shoulder = { 0.50, 0.12 }, Magazine = { 0.10, 0.11 }, Bolt = { 0.17, 0.15 },
		},
	},
	Arc = {
		Length = 4.0, MuzzleDir = 1, Pitch = 0, Anchor = RIFLE_ANCHOR,
		Points = {
			Handle = { -0.185, 0.11 }, Support = { 0.20, 0.135 }, SupportTP = { 0.12, 0.135 },
			Muzzle = { 0.50, 0.215 }, ADSPoint = { -0.10, 0.30 }, EjectPoint = { -0.05, 0.25 },
			Shoulder = { -0.50, 0.17 }, Magazine = { -0.38, 0.09 },
		},
	},
}
