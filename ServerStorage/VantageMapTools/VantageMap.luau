-- VantageMapTools.VantageMap
-- Builds the "Vantage" 5v5 TDM arena into Workspace.Map_Vantage.
--   require(game.ServerStorage.VantageMapTools.VantageMap:Clone()).Build("greybox")
--   require(game.ServerStorage.VantageMapTools.VantageMap:Clone()).Build("final")
-- Layout: X axis = spawn-to-spawn (Blue at -X, Red at +X), Z axis = lanes.
--   Catwalk flank  z -115..-75  (two-level: catwalk deck y=12 + lower floor)
--   Mid lane       z  -45.. 45  (overlooks, bunker, central courtyard/dais)
--   Hangar flank   z   75..115  (roofed ground-level hangars + open loading bay)
-- The map is mirror-symmetric across x = 0, so both teams get identical routes.

local SS = game:GetService("ServerStorage")
local K = require(SS.VantageMapTools.Kit:Clone())

local V = Vector3.new
local C = Color3.fromRGB
local B = {}

B.Layout = {
	SizeX = 350, SizeZ = 230, WallHeight = 30, WallThick = 4,
	DeckY = 12, DividerHeight = 26,
	-- quarter outline (x<0, z>0); mirrored into the full boundary
	Outline = {{-175, 0}, {-175, 40}, {-150, 40}, {-150, 95}, {-130, 115}, {0, 115}},
}

local function F(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- mirrored box: d0/d1 are distances from the centre line along X, s = -1 (Blue) / 1 (Red)
local function boxM(parent, name, s, d0, d1, y0, y1, z0, z1, role, o)
	return K.box(parent, name, s * d0, s * d1, y0, y1, z0, z1, role, o)
end

local function teamName(s)
	return s < 0 and "Blue" or "Red"
end

function B.segments()
	local segs = {}
	local q = B.Layout.Outline
	for _, m in ipairs({{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}) do
		for i = 1, #q - 1 do
			local a, b = q[i], q[i + 1]
			table.insert(segs, {V(a[1] * m[1], 0, a[2] * m[2]), V(b[1] * m[1], 0, b[2] * m[2])})
		end
	end
	return segs
end

local function segFrame(a, b)
	local dir = (b - a).Unit
	local mid = (a + b) / 2
	local n = dir:Cross(Vector3.yAxis)
	if n:Dot(mid) < 0 then n = -n end
	return dir, mid, n -- n = outward normal
end

---------------------------------------------------------------- greybox / structure

function B.Floor(f)
	for ix = 0, 13 do
		for iz = 0, 9 do
			local x0 = -175 + ix * 25
			local z0 = -125 + iz * 25
			K.box(f, "FloorTile", x0, x0 + 25, -4, 0, z0, z0 + 25, ((ix + iz) % 2 == 0) and "Floor" or "FloorAlt")
		end
	end
end

function B.Boundary(f)
	local walls = F(f, "PerimeterWalls")
	local inv = F(f, "InvisibleBarriers")
	local T = B.Layout.WallThick
	for _, seg in ipairs(B.segments()) do
		local a, b = seg[1], seg[2]
		local dir, mid, n = segFrame(a, b)
		local len = (b - a).Magnitude + T * 1.2
		local c = mid + n * (T / 2)
		local cf = CFrame.lookAt(c, c + dir)
		K.part(walls, "Wall", V(T, B.Layout.WallHeight, len), cf + V(0, B.Layout.WallHeight / 2, 0), "WallLight")
		local barrier = K.part(inv, "Barrier", V(T, 70, len), cf + V(0, B.Layout.WallHeight + 35, 0), "Invisible")
		barrier.CanQuery = false
	end
	-- invisible lid far above the playable space (no part of the map is reachable near it)
	local lid = K.box(inv, "Ceiling", -180, 180, 100, 102, -125, 125, "Invisible")
	lid.CanQuery = false
end

function B.SpawnRoom(f, s)
	local team = teamName(s)
	local room = F(f, "SpawnRoom")
	-- facade / front wall with two offset doorways (|z| 18..30)
	for _, p in ipairs({{-40, -30, 0}, {-30, -18, 11}, {-18, 18, 0}, {18, 30, 11}, {30, 40, 0}}) do
		boxM(room, p[3] > 0 and "DoorHeader" or "FrontWall", s, 148.5, 151.5, p[3], 30, p[1], p[2], "WallLight")
	end
	boxM(room, "Ceiling", s, 150, 175, 16, 17.5, -40, 40, "WallDark")
	boxM(room, "Shield", s, 133, 139, 0, 12, -14, 14, "Structure") -- blocks the long view along the spawn axis
	boxM(room, "SpawnScreen", s, 155.5, 156.5, 0, 10, -19.5, 19.5, "WallLight") -- hides the pads from angled views through the doors
	local pads = F(f, "SpawnPoints")
	for _, d in ipairs({161, 168}) do
		for _, z in ipairs({-9, 0, 9}) do
			local sp = Instance.new("SpawnLocation")
			sp.Name = team .. "Spawn"
			sp.Anchored = true
			sp.Size = V(6, 0.4, 6)
			sp.CFrame = CFrame.lookAt(V(s * d, 0.2, z), V(0, 0.2, z))
			sp.TeamColor = BrickColor.new(team == "Blue" and "Really blue" or "Really red")
			sp.Neutral = false
			sp.AllowTeamChangeOnTouch = false
			sp.Duration = 3 -- short spawn ForceField
			sp.TopSurface = Enum.SurfaceType.Smooth
			sp:SetAttribute("Role", team == "Blue" and "SpawnBlue" or "SpawnRed")
			K.style(sp, team == "Blue" and "SpawnBlue" or "SpawnRed")
			sp.Parent = pads
		end
	end
end

function B.BaseYard(f, s)
	local team = teamName(s)
	local cov = F(f, "YardCover")
	K.crate(cov, "Crate", V(s * 128, 0, 60), V(6, 6, 6), {team = team})
	K.crate(cov, "Crate", V(s * 128, 6, 60), V(4, 4, 4), {team = team, rot = 20})
	K.crate(cov, "Crate", V(s * 124, 0, 80), V(5, 5, 5), {team = team, rot = 10})
	K.waist(cov, "Barrier", V(s * 128, 0, -62), 10, {team = team, rot = 90})
	K.waist(cov, "Barrier", V(s * 120, 0, 30), 8, {team = team, rot = 90})
	K.waist(cov, "Barrier", V(s * 122, 0, -8), 6, {team = team, rot = 90})
	K.full(cov, "YardPillar", V(s * 126, 0, 46), 8, 10, 3, {team = team})
	K.full(cov, "YardPillar", V(s * 126, 0, -46), 8, 10, 3, {team = team})
	-- door fins: stop enemies in the yard corners from watching the spawn exits along the facade
	K.full(cov, "DoorFin", V(s * 144.25, 0, 35), 8.5, 10, 2, {team = team})
	K.full(cov, "DoorFin", V(s * 144.25, 0, -35), 8.5, 10, 2, {team = team})
end

function B.Dividers(f, s)
	local team = teamName(s)
	local H = B.Layout.DividerHeight
	local cat = F(f, team .. "_CatwalkDivider")
	boxM(cat, "Block", s, 25, 43, 0, H, -75, -45, "Structure")
	boxM(cat, "TunnelHeader", s, 43, 55, 10, H, -75, -45, "Structure")
	boxM(cat, "Block", s, 55, 70, 0, H, -75, -45, "Structure")
	boxM(cat, "ConnectorBase", s, 70, 82, 0, 12, -75, -45, "Structure")
	boxM(cat, "ConnectorHeader", s, 70, 82, 22, H, -75, -45, "Structure")
	boxM(cat, "Block", s, 82, 105, 0, H, -75, -45, "Structure")
	local han = F(f, team .. "_HangarDivider")
	boxM(han, "Block", s, 25, 43, 0, H, 45, 75, "Structure")
	boxM(han, "TunnelHeader", s, 43, 55, 10, H, 45, 75, "Structure")
	boxM(han, "Block", s, 55, 105, 0, H, 45, 75, "Structure")
end

function B.Overlook(f, s)
	local team = teamName(s)
	local o = F(f, team .. "_Overlook")
	boxM(o, "Deck", s, 66, 98, 10.5, 12, -45, -29, "Deck")
	for _, p in ipairs({{67.2, -30.2}, {82, -30.2}}) do
		boxM(o, "Support", s, p[1] - 0.9, p[1] + 0.9, 0, 10.5, p[2] - 0.9, p[2] + 0.9, "WallDark")
	end
	K.parapet(o, "Parapet", V(s * 66, 12, -29.4), V(s * 98, 12, -29.4), 3, {team = team})
	K.parapet(o, "Parapet", V(s * 66.4, 12, -45), V(s * 66.4, 12, -29.8), 3, {team = team})
	K.parapet(o, "Parapet", V(s * 97.6, 12, -32.8), V(s * 97.6, 12, -29.8), 3, {team = team})
	K.full(o, "UnderWall", V(s * 90, 0, -29.6), 14, 10.5, 2, {team = team})
	K.stairs(o, "OverlookStairs", V(s * 122, 0, -38), V(-s, 0, 0), 10, 24, 12, {team = team})
end

function B.MidLane(f, s)
	local team = teamName(s)
	local m = F(f, team .. "_Approach")
	K.full(m, "Bunker", V(s * 78, 0, 34.5), 24, 10, 21, {team = team, role = "WallLight", inset = "WallDark"})
	K.full(m, "Barricade", V(s * 58.5, 0, 0), 26, 10, 3, {team = team, rot = 90})
	K.waist(m, "Barrier", V(s * 88, 0, 2), 10, {team = team, rot = 90})
	K.full(m, "TunnelBaffle", V(s * 49, 0, -35), 10, 9, 2, {team = team})
	K.waist(m, "Barrier", V(s * 42, 0, 30), 8, {team = team})
	K.crate(m, "Crate", V(s * 100, 0, 16), V(6, 6, 6), {team = team})
	K.crate(m, "Crate", V(s * 76, 0, -14), V(5, 6, 5), {team = team, rot = 12})
	K.crate(m, "Crate", V(s * 86, 0, -37), V(5, 5, 5), {team = team})
end

function B.Courtyard(f)
	local cy = F(f, "Structures")
	local cov = F(f, "Cover")
	K.box(cy, "Dais", -15, 15, 0, 3, -15, 15, "Structure")
	K.box(cy, "Core", -5, 5, 3, 16, -5, 5, "WallLight")
	for _, s in ipairs({-1, 1}) do
		K.stairs(cy, "DaisRamp", V(s * 24, 0, 0), V(-s, 0, 0), 14, 9, 3, {ramp = true, team = teamName(s)})
		K.stairs(cy, "DaisSteps", V(0, 0, s * 21), V(0, 0, -s), 14, 6, 3, {rails = false})
		for _, sz in ipairs({-1, 1}) do
			K.full(cov, "Pylon", V(s * 30, 0, sz * 21), 12, 12, 6, {rot = 90, team = teamName(s)})
			K.waist(cov, "Barrier", V(s * 15, 0, sz * 60), 6, {rot = 90})
		end
		K.full(cov, "CourtPillar", V(0, 0, s * 31.5), 7, 10, 5, {rot = 90})
		-- staggered screens: break the cross-courtyard sightline between the two flank gaps
		K.full(cov, "Screen", V(s * 10, 0, 37), 12, 9, 2, {team = teamName(s)})
		K.full(cov, "Screen", V(s * 19, 0, -37), 12, 9, 2, {team = teamName(s)})
	end
	K.full(cov, "GapPillar", V(0, 0, -42), 6, 10, 6, {})
	K.full(cy, "GateWall_Catwalk", V(0, 0, -60), 16, 9, 8, {rot = 90})
	K.full(cy, "GateWall_Hangar", V(0, 0, 60), 16, 12, 8, {rot = 90})
end

function B.Catwalk(f)
	local up = F(f, "UpperCatwalk")
	local low = F(f, "LowerFlank")
	K.box(up, "Deck", -90, 90, 10.5, 12, -91, -75, "Deck")
	K.box(up, "NestDeck", -12, 12, 10.5, 12, -99, -91, "Deck")
	for _, x in ipairs({-80, -60, -40, -20, 20, 40, 60, 80}) do
		K.box(up, "Support", x - 0.9, x + 0.9, 0, 10.5, -90.8, -89, "WallDark")
	end
	for _, x in ipairs({-11, 11}) do
		K.box(up, "Support", x - 0.9, x + 0.9, 0, 10.5, -98.8, -97, "WallDark")
	end
	K.parapet(up, "Parapet", V(-90, 12, -90.6), V(-12, 12, -90.6), 3, {team = "Blue"})
	K.parapet(up, "Parapet", V(12, 12, -90.6), V(90, 12, -90.6), 3, {team = "Red"})
	K.parapet(up, "Parapet", V(-12, 12, -98.6), V(12, 12, -98.6), 3, {})
	K.parapet(up, "Parapet", V(-11.6, 12, -98.2), V(-11.6, 12, -91), 3, {})
	K.parapet(up, "Parapet", V(11.6, 12, -98.2), V(11.6, 12, -91), 3, {})
	K.parapet(up, "Parapet", V(-25, 12, -75.4), V(25, 12, -75.4), 3, {})
	K.full(up, "DeckCover", V(0, 12, -86.5), 7, 7, 2, {rot = 90})
	K.full(up, "DeckCover", V(-50, 12, -80.25), 10.5, 7, 2, {rot = 90, team = "Blue"})
	K.full(up, "DeckCover", V(50, 12, -80.25), 10.5, 7, 2, {rot = 90, team = "Red"})
	K.full(up, "NestCover", V(0, 12, -95.5), 6, 5, 1.5, {})
	for _, s in ipairs({-1, 1}) do
		local team = teamName(s)
		K.stairs(up, "CatwalkStairs", V(s * 114, 0, -83), V(-s, 0, 0), 10, 24, 12, {team = team})
		K.full(low, "FlankBlock", V(s * 40, 0, -95), 10, 9, 3, {team = team, rot = 90})
		K.full(low, "Bulkhead", V(s * 70, 0, -104), 8, 9, 2, {team = team, rot = 90})
		K.crate(low, "Crate", V(s * 96, 0, -106), V(6, 6, 6), {team = team})
		K.crate(low, "Crate", V(s * 26, 0, -80), V(5, 5, 5), {team = team, rot = 15})
	end
	K.full(low, "Generator", V(0, 0, -109), 18, 9, 12, {role = "WallLight", inset = "WallDark"})
	K.full(low, "CenterPier", V(0, 0, -81.5), 8, 10.5, 13, {role = "Structure", inset = "WallDark"}) -- under the catwalk
end

function B.Hangar(f)
	for _, s in ipairs({-1, 1}) do
		local team = teamName(s)
		local h = F(f, team .. "_Hangar")
		boxM(h, "Roof", s, 35, 112, 18, 19.5, 75, 115, "WallDark")
		boxM(h, "Bulkhead", s, 33, 35, 0, 18, 75, 93, "WallLight")
		boxM(h, "BulkheadHeader", s, 33, 35, 12, 18, 93, 107, "WallLight")
		boxM(h, "Bulkhead", s, 33, 35, 0, 18, 107, 115, "WallLight")
		for _, p in ipairs({{62, 95}, {88, 95}, {110.5, 76.5}}) do
			boxM(h, "Column", s, p[1] - 1, p[1] + 1, 0, 18, p[2] - 1, p[2] + 1, "WallDark")
		end
		K.crate(h, "Crate", V(s * 50, 0, 108), V(6, 6, 6), {team = team})
		K.crate(h, "Crate", V(s * 50, 6, 108), V(4, 4, 4), {team = team, rot = 15})
		K.full(h, "Rack", V(s * 75, 0, 82), 10, 9, 2, {team = team})
		K.waist(h, "Barrier", V(s * 75, 0, 108), 8, {team = team})
		K.crate(h, "Crate", V(s * 100, 0, 90), V(6, 6, 6), {team = team, rot = 10})
		K.waist(h, "Barrier", V(s * 96, 0, 106), 8, {team = team, rot = 90})
	end
	local bay = F(f, "LoadingBay")
	K.crate(bay, "Container", V(0, 0, 100), V(18, 9, 8), {rot = 90, role = "Container"})
	for _, s in ipairs({-1, 1}) do
		K.waist(bay, "Barrier", V(s * 18, 0, 84), 6, {rot = 90})
		K.crate(bay, "Crate", V(s * 20, 0, 109), V(5, 9, 5), {rot = 15})
	end
end

function B.Callouts(f)
	local list = {
		{"Blue Spawn", -162, -40, 40}, {"Red Spawn", 162, -40, 40},
		{"Courtyard", 0, -45, 45},
	}
	local function add(name, cx, cz, sx, sz, y)
		local p = K.part(f, name, V(sx, 10, sz), CFrame.new(cx, (y or 0) + 5, cz), "Invisible", {deco = true})
		p:SetAttribute("Callout", name)
	end
	add("Blue Spawn", -162.5, 0, 25, 80)
	add("Red Spawn", 162.5, 0, 25, 80)
	add("Blue Yard", -132, 0, 34, 190)
	add("Red Yard", 132, 0, 34, 190)
	add("Courtyard", 0, 0, 80, 90)
	add("Core", 0, 0, 30, 30, 3)
	add("Blue Mid", -78, 0, 76, 90)
	add("Red Mid", 78, 0, 76, 90)
	add("Blue Overlook", -82, -37, 32, 16, 12)
	add("Red Overlook", 82, -37, 32, 16, 12)
	add("Blue Bunker", -78, 22, 24, 14)
	add("Red Bunker", 78, 22, 24, 14)
	add("Catwalk", 0, -83, 180, 16, 12)
	add("Nest", 0, -95, 24, 8, 12)
	add("Generator", 0, -105, 40, 20)
	add("Blue Lower Flank", -70, -103, 90, 24)
	add("Red Lower Flank", 70, -103, 90, 24)
	add("Blue Upper Connector", -76, -60, 12, 30, 12)
	add("Red Upper Connector", 76, -60, 12, 30, 12)
	add("Blue Catwalk Tunnel", -49, -60, 12, 30)
	add("Red Catwalk Tunnel", 49, -60, 12, 30)
	add("Blue Hangar Tunnel", -49, 60, 12, 30)
	add("Red Hangar Tunnel", 49, 60, 12, 30)
	add("Blue Hangar", -73, 95, 77, 40)
	add("Red Hangar", 73, 95, 77, 40)
	add("Loading Bay", 0, 95, 66, 40)
end

---------------------------------------------------------------- dressing (final stage)

local function faceCF(c: Vector3, outward: Vector3)
	return CFrame.lookAt(c, c + outward)
end

function B.PerimeterFacade(f)
	local walls = F(f, "WallFacade")
	local lights = F(f, "WallLights")
	for _, seg in ipairs(B.segments()) do
		local a, b = seg[1], seg[2]
		local dir, _, n = segFrame(a, b)
		local inward = -n
		local len = (b - a).Magnitude
		local bays = math.max(1, math.floor(len / 16 + 0.5))
		local bl = len / bays
		for i = 0, bays - 1 do
			local c = a + dir * ((i + 0.5) * bl)
			local cf = faceCF(c, inward)
			local team = K.teamOf(c.X)
			K.part(walls, "Kick", V(bl, 2.4, 0.8), cf * CFrame.new(0, 1.2, -0.4), "WallDark")
			K.part(walls, "KickLight", V(bl, 0.22, 0.3), cf * CFrame.new(0, 2.6, -0.62), K.neon(team), {deco = true})
			K.part(walls, "Band", V(bl, 1.4, 0.7), cf * CFrame.new(0, 21, -0.35), "Trim", {deco = true})
			K.part(walls, "BandLight", V(bl, 0.16, 0.2), cf * CFrame.new(0, 20.2, -0.75), K.neon(team), {deco = true})
			K.part(walls, "Coping", V(bl, 1, 1.4), cf * CFrame.new(0, 29.8, -0.3), "WallDark", {deco = true})
			if i % 2 == 0 and bl > 8 then
				K.part(walls, "Panel", V(bl - 4, 11, 0.3), cf * CFrame.new(0, 10.5, -0.15), "WallDark", {deco = true})
				K.part(walls, "PanelInset", V(bl - 6, 9, 0.2), cf * CFrame.new(0, 10.5, -0.35), "Trim", {deco = true})
			else
				K.fixture(lights, "WallLamp", V(3.5, 0.5, 1.2), cf * CFrame.new(0, 17, -0.6), "SpotLight",
					{Face = Enum.NormalId.Bottom, Angle = 110, Range = 26, Brightness = 1.6, Color = C(220, 235, 255), Shadows = false})
			end
			local pc = a + dir * (i * bl)
			K.part(walls, "Pilaster", V(1.8, 30, 1.2), faceCF(pc, inward) * CFrame.new(0, 15, -0.6), "WallDark")
		end
	end
end

function B.DividerFacade(f, s)
	local team = teamName(s)
	local df = F(f, team .. "_DividerFacade")
	local H = B.Layout.DividerHeight
	local function on(z0, z1)
		return function(d, y0, y1)
			return {d, y0, y1, z0, z1}
		end
	end
	local divs = {
		{z0 = -75, z1 = -45, openings = {{43, 55, 0, 10}, {70, 82, 12, 22}}},
		{z0 = 45, z1 = 75, openings = {{43, 55, 0, 10}}},
	}
	for _, dv in ipairs(divs) do
		-- top coping
		boxM(df, "Coping", s, 24.4, 105.6, H, H + 0.8, dv.z0 - 0.6, dv.z1 + 0.6, "WallDark", {deco = true})
		for _, face in ipairs({{dv.z0, -1}, {dv.z1, 1}}) do
			local zf, nz = face[1], face[2]
			local function slab(name, d0, d1, y0, y1, depth, role, o)
				local za, zb = zf, zf + nz * depth
				return boxM(df, name, s, d0, d1, y0, y1, za, zb, role, o)
			end
			local function blocked(d0, d1, y0, y1)
				for _, op in ipairs(dv.openings) do
					if d1 > op[1] - 0.5 and d0 < op[2] + 0.5 and y1 > op[3] and y0 < op[4] then
						return true
					end
				end
				return false
			end
			-- band + neon line
			slab("Band", 25, 105, 22.6, 24, 0.5, "Trim", {deco = true})
			slab("BandLight", 25, 105, 23.1, 23.35, 0.7, K.neon(team), {deco = true})
			-- kick strip + light (split around ground openings)
			local cuts = {25}
			for _, op in ipairs(dv.openings) do
				if op[3] == 0 then
					table.insert(cuts, op[1])
					table.insert(cuts, op[2])
				end
			end
			table.insert(cuts, 105)
			for i = 1, #cuts - 1, 2 do
				slab("Kick", cuts[i], cuts[i + 1], 0, 2.2, 0.6, "WallDark", {deco = true})
				slab("KickLight", cuts[i], cuts[i + 1], 2.3, 2.5, 0.4, K.neon(team), {deco = true})
			end
			-- vertical fins + windows
			for d = 25, 105, 10 do
				if not blocked(d - 0.8, d + 0.8, 0, H) then
					slab("Fin", d - 0.8, d + 0.8, 0, H, 1.1, "WallDark", {deco = true})
				end
				if d < 105 and not blocked(d + 2, d + 8, 14, 20) then
					slab("WindowFrame", d + 1.6, d + 8.4, 13.6, 19.4, 0.25, "Trim", {deco = true})
					slab("Window", d + 2, d + 8, 14, 19, 0.4, "Glass", {deco = true})
				end
			end
			-- opening frames
			for _, op in ipairs(dv.openings) do
				slab("FrameL", op[1] - 0.6, op[1], op[3], op[4] + 0.6, 0.8, "WallDark", {deco = true})
				slab("FrameR", op[2], op[2] + 0.6, op[3], op[4] + 0.6, 0.8, "WallDark", {deco = true})
				slab("FrameTop", op[1] - 0.6, op[2] + 0.6, op[4], op[4] + 0.6, 0.8, "WallDark", {deco = true})
				slab("FrameLight", op[1] - 0.2, op[2] + 0.2, op[4] + 0.15, op[4] + 0.35, 0.95, K.neon(team), {deco = true})
				slab("JambLight", op[1] - 0.35, op[1] - 0.15, op[3], op[4], 0.95, K.neon(team), {deco = true})
				slab("JambLight", op[2] + 0.15, op[2] + 0.35, op[3], op[4], 0.95, K.neon(team), {deco = true})
			end
		end
		-- tunnel / connector interior lights
		for _, op in ipairs(dv.openings) do
			local mid = (op[1] + op[2]) / 2
			local fx = K.box(df, "TunnelLight", s * (mid - 0.4), s * (mid + 0.4), op[4] - 0.2, op[4], dv.z0 + 3, dv.z1 - 3, "NeonWhite", {deco = true})
			local l = Instance.new("SurfaceLight")
			l.Face = Enum.NormalId.Bottom
			l.Range = 14
			l.Brightness = 1.4
			l.Angle = 120
			l.Color = C(215, 230, 255)
			l.Parent = fx
			if op[3] == 0 then
				boxM(df, "TunnelFloorStrip", s, op[1] + 0.6, op[2] - 0.6, op[3] - 0.01, op[3] + 0.05, dv.z0 + 0.5, dv.z1 - 0.5, "FloorDark", {deco = true})
			end
			-- inner wall trim: dark wainscot, neon line, ribs
			for _, wall in ipairs({{op[1], 1}, {op[2], -1}}) do
				local wd, inn = wall[1], wall[2] -- inn: +1 means the tunnel lies at larger distance
				boxM(df, "TunnelWainscot", s, wd, wd + inn * 0.4, op[3], op[3] + 2.6, dv.z0, dv.z1, "WallDark", {deco = true})
				boxM(df, "TunnelLine", s, wd, wd + inn * 0.5, op[3] + 2.7, op[3] + 2.9, dv.z0, dv.z1, K.neon(team), {deco = true})
				boxM(df, "TunnelPanel", s, wd, wd + inn * 0.2, op[3] + 3.6, op[4] - 1.2, dv.z0 + 2, dv.z1 - 2, "Trim", {deco = true})
				for z = dv.z0 + 1.5, dv.z1 - 1, 7 do
					boxM(df, "TunnelRib", s, wd, wd + inn * 0.6, op[3], op[4], z - 0.5, z + 0.5, "WallDark", {deco = true})
				end
			end
		end
		-- end faces: team banner toward the base, light strip toward the centre
		local zc = (dv.z0 + dv.z1) / 2
		K.emblem(df, "TeamBanner", faceCF(V(s * 105, 13, zc), V(s, 0, 0)), 14, 16, team)
		boxM(df, "EndLight", s, 24.3, 25, 0, H, zc - 0.4, zc + 0.4, K.neon(team), {deco = true})
		boxM(df, "EndFin", s, 24.0, 25, 0, H, dv.z0, dv.z0 + 1.2, "WallDark", {deco = true})
		boxM(df, "EndFin", s, 24.0, 25, 0, H, dv.z1 - 1.2, dv.z1, "WallDark", {deco = true})
		-- deck plate on the upper connector floor
		if #dv.openings > 1 then
			boxM(df, "ConnectorPlate", s, 70, 82, 11.99, 12.06, dv.z0, dv.z1, "Deck", {deco = true})
		end
	end
end

function B.SpawnDress(f, s)
	local team = teamName(s)
	local df = F(f, "SpawnDetail")
	local tint = team == "Blue" and C(170, 205, 255) or C(255, 190, 190)
	-- giant team banner on the yard facade above the doorways
	K.emblem(df, "SpawnBanner", faceCF(V(s * 148.5, 20.5, 0), V(-s, 0, 0)), 28, 13, team)
	K.emblem(df, "BackWallBanner", faceCF(V(s * 175, 8.5, 0), V(-s, 0, 0)), 18, 9, team)
	-- door frames + threshold hazard stripes
	for _, z0 in ipairs({-30, 18}) do
		local z1 = z0 + 12
		for _, side in ipairs({148.5 - 0.01, 151.5 + 0.01}) do
			local dx = side < 150 and -1 or 1
			local xa, xb = side, side + dx * 0.6
			boxM(df, "DoorFrame", s, xa, xb, 0, 11.6, z0 - 0.6, z0, "WallDark", {deco = true})
			boxM(df, "DoorFrame", s, xa, xb, 0, 11.6, z1, z1 + 0.6, "WallDark", {deco = true})
			boxM(df, "DoorFrame", s, xa, xb, 11, 11.6, z0 - 0.6, z1 + 0.6, "WallDark", {deco = true})
			boxM(df, "DoorLight", s, xa, xb + dx * 0.15, 11.6, 11.85, z0 - 0.6, z1 + 0.6, K.neon(team), {deco = true})
		end
		for k = 0, 5 do
			local za = z0 + k * 2
			boxM(df, "Hazard", s, 146.5, 153.5, 0, 0.05, za, za + 1, (k % 2 == 0) and "Hazard" or "PaintDark", {deco = true})
		end
	end
	-- interior: floor inlay, ceiling light panels
	boxM(df, "FloorInlay", s, 153.5, 171, 0, 0.04, -15, 15, "FloorDark", {deco = true})
	boxM(df, "FloorInlayEdge", s, 153.5, 171, 0, 0.06, 14.6, 15, K.neon(team), {deco = true})
	boxM(df, "FloorInlayEdge", s, 153.5, 171, 0, 0.06, -15, -14.6, K.neon(team), {deco = true})
	for _, d in ipairs({156, 168}) do
		for _, z in ipairs({-22, 0, 22}) do
			local p = boxM(df, "CeilingStrip", s, d - 0.5, d + 0.5, 15.8, 16, z - 5, z + 5, "NeonWhite", {deco = true})
			local l = Instance.new("SurfaceLight")
			l.Face = Enum.NormalId.Bottom
			l.Range = 18
			l.Brightness = 1.2
			l.Angle = 120
			l.Color = tint
			l.Parent = p
		end
	end
	-- facade vertical light strips + shield wall dress
	for _, z in ipairs({-36, -12, 12, 36}) do
		boxM(df, "FacadeStrip", s, 148.2, 148.5, 0, 30, z - 0.25, z + 0.25, K.neon(team), {deco = true})
	end
	boxM(df, "ShieldCap", s, 132.7, 139.3, 12, 12.5, -14.3, 14.3, "Trim", {deco = true})
	boxM(df, "ShieldLight", s, 132.6, 139.4, 9.5, 9.8, -14.1, 14.1, K.neon(team), {deco = true})
	K.emblem(df, "ShieldEmblem", faceCF(V(s * 133, 6, 0), V(-s, 0, 0)), 8, 6, team)
	-- team stripe across the yard edge
	boxM(df, "TeamLine", s, 114.6, 115.6, 0, 0.05, -95, -76, team == "Blue" and "TeamBlue" or "TeamRed", {deco = true})
	boxM(df, "TeamLine", s, 114.6, 115.6, 0, 0.05, -45, 45, team == "Blue" and "TeamBlue" or "TeamRed", {deco = true})
	boxM(df, "TeamLine", s, 114.6, 115.6, 0, 0.05, 75, 95, team == "Blue" and "TeamBlue" or "TeamRed", {deco = true})
end

function B.ElevatedDress(f)
	local df = F(f, "ElevatedDetail")
	for _, s in ipairs({-1, 1}) do
		local team = teamName(s)
		boxM(df, "DeckEdgeLight", s, 66, 98, 11.0, 11.25, -29.05, -28.9, K.neon(team), {deco = true})
		for _, d in ipairs({74, 90}) do
			local p = boxM(df, "UnderLight", s, d - 2, d + 2, 10.2, 10.5, -38, -36, "NeonWhite", {deco = true})
			local l = Instance.new("SurfaceLight")
			l.Face = Enum.NormalId.Bottom
			l.Range = 14
			l.Brightness = 1.2
			l.Parent = p
		end
		boxM(df, "CatwalkEdgeLight", s, 12, 90, 11.0, 11.25, -91.05, -90.9, K.neon(team), {deco = true})
		for _, d in ipairs({30, 50, 70}) do
			local p = boxM(df, "UnderLight", s, d - 2, d + 2, 10.2, 10.5, -84, -82, "NeonWhite", {deco = true})
			local l = Instance.new("SurfaceLight")
			l.Face = Enum.NormalId.Bottom
			l.Range = 14
			l.Brightness = 1.2
			l.Parent = p
		end
	end
	K.box(df, "NestEdgeLight", -12, 12, 11.0, 11.25, -99.05, -98.9, "NeonWhite", {deco = true})
end

function B.HangarDress(f)
	local df = F(f, "HangarDetail")
	for _, s in ipairs({-1, 1}) do
		local team = teamName(s)
		local i = 0
		for d = 40, 108, 11 do
			i = i + 1
			boxM(df, "Beam", s, d - 0.5, d + 0.5, 16.6, 18, 75, 115, "Trim", {deco = true})
			if i % 2 == 0 then
				local p = boxM(df, "CeilingLight", s, d - 6, d - 5, 17.6, 17.9, 80, 110, "NeonWhite", {deco = true})
				local l = Instance.new("SurfaceLight")
				l.Face = Enum.NormalId.Bottom
				l.Range = 20
				l.Brightness = 1.3
				l.Angle = 120
				l.Color = C(220, 232, 255)
				l.Parent = p
			end
		end
		for _, pz in ipairs({{113, 14}, {111.6, 15.6}}) do
			local len = 112 - 35
			K.part(df, "Pipe", V(len, 1, 1), CFrame.new(s * (35 + len / 2), pz[2], pz[1]), "Trim", {deco = true, shape = Enum.PartType.Cylinder})
		end
		-- roof edge trim toward the base and toward the bay
		boxM(df, "RoofEdgeLight", s, 111.9, 112.1, 18.3, 18.6, 75, 115, K.neon(team), {deco = true})
		boxM(df, "RoofEdgeLight", s, 34.8, 35, 18.3, 18.6, 75, 115, K.neon(team), {deco = true})
		-- bulkhead door frame
		for _, side in ipairs({32.9, 35.1}) do
			local dx = side < 34 and -1 or 1
			boxM(df, "DoorLight", s, side, side + dx * 0.2, 12.1, 12.35, 93, 107, K.neon(team), {deco = true})
			boxM(df, "DoorLight", s, side, side + dx * 0.2, 0, 12.1, 92.6, 92.85, K.neon(team), {deco = true})
			boxM(df, "DoorLight", s, side, side + dx * 0.2, 0, 12.1, 107.15, 107.4, K.neon(team), {deco = true})
		end
		for k = 0, 6 do
			local za = 93 + k * 2
			boxM(df, "Hazard", s, 31, 37, 0, 0.05, za, za + 1, (k % 2 == 0) and "Hazard" or "PaintDark", {deco = true})
		end
		-- painted walkway lines
		boxM(df, "WalkLine", s, 36, 112, 0, 0.04, 87.6, 88, "Hazard", {deco = true})
	end
end

function B.CourtyardDress(f)
	local df = F(f, "CourtyardDetail")
	K.box(df, "CoreCap", -5.5, 5.5, 16, 16.8, -5.5, 5.5, "Trim", {deco = true})
	K.box(df, "CoreBand", -5.15, 5.15, 13.2, 13.5, -5.15, 5.15, "NeonWhite", {deco = true})
	for _, s in ipairs({-1, 1}) do
		local team = teamName(s)
		K.emblem(df, "CoreEmblem", faceCF(V(s * 5, 8.5, 0), V(s, 0, 0)), 7, 7.5, team)
		for _, x in ipairs({-3.2, 3.2}) do
			K.box(df, "CoreStrip", x - 0.2, x + 0.2, 3, 13, s * 5, s * 5.15, "NeonWhite", {deco = true})
		end
		K.box(df, "CorePanel", -2.5, 2.5, 4.5, 12, s * 5, s * 5.12, "WallDark", {deco = true})
		-- dais edge lights
		K.box(df, "DaisEdge", -15.1, 15.1, 2.6, 2.85, s * 15, s * 15.12, "NeonWhite", {deco = true})
		K.box(df, "DaisEdge", s * 15, s * 15.12, 2.6, 2.85, -15.1, 15.1, K.neon(team), {deco = true})
		-- team-colour floor lines at the courtyard edge, white centre markings
		K.box(df, "CourtLine", s * 39.5, s * 40.5, 0, 0.05, -44, 44, team == "Blue" and "TeamBlue" or "TeamRed", {deco = true})
		K.box(df, "HazardRing", -17, 17, 0, 0.05, s * 16.4, s * 17, "Hazard", {deco = true})
		K.box(df, "HazardRing", s * 16.4, s * 17, 0, 0.05, -16.4, 16.4, "Hazard", {deco = true})
		for k = 0, 2 do
			local z0 = 24 + k * 7
			K.box(df, "CentreDash", -0.4, 0.4, 0, 0.05, s * z0, s * (z0 + 4), "Paint", {deco = true})
		end
		-- floodlights on the core corners
		for _, sz in ipairs({-1, 1}) do
			K.fixture(df, "CoreFlood", V(1.2, 0.6, 1.2), CFrame.new(s * 5.6, 15.2, sz * 5.6), "PointLight",
				{Range = 22, Brightness = 1.1, Color = C(225, 238, 255), Shadows = false})
		end
	end
end

function B.FloorDress(f)
	local df = F(f, "FloorMarkings")
	for x = -150, 150, 25 do
		K.box(df, "Seam", x - 0.15, x + 0.15, 0, 0.03, -115, 115, "PaintDark", {deco = true})
	end
	for z = -100, 100, 25 do
		K.box(df, "Seam", -175, 175, 0, 0.03, z - 0.15, z + 0.15, "PaintDark", {deco = true})
	end
	-- metal grate walkways in the flanks
	K.box(df, "Grate", -112, 112, 0, 0.035, -114, -110, "FloorDark", {deco = true})
	K.box(df, "Grate", -33, 33, 0, 0.035, 110.5, 114.5, "FloorDark", {deco = true})
end

function B.Backdrop(f)
	local bd = F(f, "Backdrop")
	K.box(bd, "OuterGround", -700, 700, -10, -4, -700, 700, "Backdrop")
	local rng = Random.new(1337)
	local spots = {}
	for x = 20, 290, 68 do
		table.insert(spots, {x + rng:NextNumber(-10, 10), 175 + rng:NextNumber(0, 50)})
		table.insert(spots, {x + rng:NextNumber(-10, 10), -(175 + rng:NextNumber(0, 50))})
	end
	for z = -110, 110, 73 do
		table.insert(spots, {240 + rng:NextNumber(0, 40), z + rng:NextNumber(-10, 10)})
	end
	for _, sp in ipairs(spots) do
		local w = rng:NextNumber(24, 40)
		local d = rng:NextNumber(24, 40)
		local h = rng:NextNumber(55, 110)
		local h2 = h + rng:NextNumber(18, 40)
		local glowWhite = rng:NextInteger(0, 1) == 0
		for _, s in ipairs({-1, 1}) do
			local x, z = sp[1] * s, sp[2]
			local t = F(bd, "Tower")
			-- podium, main block, setback crown
			K.box(t, "Podium", x - w / 2 - 4, x + w / 2 + 4, -4, 18, z - d / 2 - 4, z + d / 2 + 4, "Backdrop")
			K.box(t, "Body", x - w / 2, x + w / 2, 18, h, z - d / 2, z + d / 2, "Backdrop")
			K.box(t, "Setback", x - w / 3, x + w / 3, h, h2, z - d / 3, z + d / 3, "BackdropLight")
			K.box(t, "Cap", x - w / 3 - 0.8, x + w / 3 + 0.8, h2, h2 + 1.5, z - d / 3 - 0.8, z + d / 3 + 0.8, "WallDark")
			K.box(t, "Ledge", x - w / 2 - 1, x + w / 2 + 1, h, h + 1.2, z - d / 2 - 1, z + d / 2 + 1, "Trim", {deco = true})
			-- vertical window ribbons on the two faces that look at the arena
			local fz = z > 0 and (z - d / 2 - 0.15) or (z + d / 2 + 0.15)
			for i = -1, 1 do
				local wx = x + i * w * 0.28
				K.box(t, "Ribbon", wx - 1.2, wx + 1.2, 24, h - 4, fz - 0.15, fz + 0.15, "Glass", {deco = true})
			end
			local fx = (x > 0) and (x - w / 2 - 0.15) or (x + w / 2 + 0.15)
			K.box(t, "Ribbon", fx - 0.15, fx + 0.15, 24, h - 4, z - 1.5, z + 1.5, "Glass", {deco = true})
			local role = glowWhite and "NeonWhite" or (s < 0 and "NeonBlue" or "NeonRed")
			K.box(t, "Glow", x - w / 3 - 0.3, x + w / 3 + 0.3, h2 - 3, h2 - 2.6, z - d / 3 - 0.3, z + d / 3 + 0.3, role, {deco = true})
			K.box(t, "PodiumGlow", x - w / 2 - 4.2, x + w / 2 + 4.2, 15, 15.4, z - d / 2 - 4.2, z + d / 2 + 4.2, role, {deco = true})
		end
	end
	-- two central spires on the lane axis behind each long wall
	for _, sz in ipairs({-1, 1}) do
		local z = sz * 190
		local t = F(bd, "Spire")
		K.box(t, "Base", -22, 22, -4, 60, z - 16, z + 16, "Backdrop")
		K.box(t, "Shaft", -12, 12, 60, 130, z - 10, z + 10, "BackdropLight")
		K.box(t, "Crown", -15, 15, 130, 136, z - 13, z + 13, "WallDark")
		K.box(t, "CrownLight", -15.3, 15.3, 131.5, 132.2, z - 13.3, z + 13.3, "NeonWhite", {deco = true})
		K.part(t, "Antenna", V(40, 1.6, 1.6), CFrame.new(0, 156, z) * CFrame.Angles(0, 0, math.rad(90)), "Trim", {shape = Enum.PartType.Cylinder})
		K.emblem(t, "SpireEmblem", faceCF(V(0, 100, z - sz * 10), V(0, 0, -sz)), 16, 18, nil)
		for _, x in ipairs({-12, 12}) do
			K.box(t, "Strip", x - 0.4, x + 0.4, 60, 130, z - sz * 10.3, z - sz * 10, x < 0 and "NeonBlue" or "NeonRed", {deco = true})
		end
	end
end

---------------------------------------------------------------- environment

local function backup()
	local bk = SS:FindFirstChild("_VantageBackup")
	if bk then return bk end
	bk = F(SS, "_VantageBackup")
	local ws = F(bk, "Workspace_Original")
	for _, n in ipairs({"Baseplate", "SpawnLocation"}) do
		local o = workspace:FindFirstChild(n)
		if o then o.Parent = ws end
	end
	local L = game:GetService("Lighting")
	local lf = F(bk, "Lighting_Original")
	for _, c in ipairs(L:GetChildren()) do
		c:Clone().Parent = lf
	end
	for _, p in ipairs({"ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "GeographicLatitude", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ShadowSoftness", "ExposureCompensation"}) do
		lf:SetAttribute(p, (L :: any)[p])
	end
	return bk
end

function B.Environment()
	local L = game:GetService("Lighting")
	L.ClockTime = 14.8
	L.GeographicLatitude = 32
	L.Brightness = 2.6
	L.Ambient = C(62, 64, 70)
	L.OutdoorAmbient = C(118, 118, 124)
	L.EnvironmentDiffuseScale = 0.55
	L.EnvironmentSpecularScale = 0.8
	L.ShadowSoftness = 0.15
	L.ExposureCompensation = 0.05
	local atm = L:FindFirstChildOfClass("Atmosphere")
	if atm then
		atm.Density = 0.26
		atm.Offset = 0.12
		atm.Color = C(205, 210, 220)
		atm.Decay = C(110, 116, 130)
		atm.Glare = 0.15
		atm.Haze = 1
	end
	local bloom = L:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = 0.5
		bloom.Size = 22
		bloom.Threshold = 1
	end
	local rays = L:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = 0.04
		rays.Spread = 0.6
	end
	local cc = L:FindFirstChild("VantageGrade") or Instance.new("ColorCorrectionEffect")
	cc.Name = "VantageGrade"
	cc.Contrast = 0.08
	cc.Saturation = 0.06
	cc.Brightness = 0.01
	cc.TintColor = C(255, 251, 246)
	cc.Parent = L
	-- teams (needed so the team SpawnLocations work)
	local Teams = game:GetService("Teams")
	for _, t in ipairs({{"Blue", "Really blue"}, {"Red", "Really red"}}) do
		local team = Teams:FindFirstChild(t[1]) or Instance.new("Team")
		team.Name = t[1]
		team.TeamColor = BrickColor.new(t[2])
		team.AutoAssignable = true
		team.Parent = Teams
	end
end

---------------------------------------------------------------- entry

function B.Build(stage)
	K.Stage = stage or "final"
	K.count = 0
	backup()
	local old = workspace:FindFirstChild("Map_Vantage")
	if old then old:Destroy() end
	local root = Instance.new("Folder")
	root.Name = "Map_Vantage"
	root:SetAttribute("Stage", K.Stage)
	root:SetAttribute("Layout", "3-lane TDM, 350x230 playable, Blue -X / Red +X")

	B.Floor(F(root, "00_Floor"))
	B.Boundary(F(root, "01_Boundary"))
	local blue = F(root, "02_BlueBase")
	local red = F(root, "03_RedBase")
	local mid = F(root, "04_MidLane")
	local court = F(root, "05_Courtyard")
	local cat = F(root, "06_CatwalkFlank")
	local hang = F(root, "07_HangarFlank")
	local div = F(root, "08_LaneDividers")
	for _, s in ipairs({-1, 1}) do
		local base = s < 0 and blue or red
		B.SpawnRoom(base, s)
		B.BaseYard(base, s)
		B.Dividers(div, s)
		B.Overlook(mid, s)
		B.MidLane(mid, s)
	end
	B.Courtyard(court)
	B.Catwalk(cat)
	B.Hangar(hang)
	B.Callouts(F(root, "10_Callouts"))

	if K.Stage ~= "greybox" then
		local det = F(root, "09_Details")
		B.PerimeterFacade(det)
		for _, s in ipairs({-1, 1}) do
			B.DividerFacade(det, s)
			B.SpawnDress(s < 0 and blue or red, s)
		end
		B.ElevatedDress(det)
		B.HangarDress(hang)
		B.CourtyardDress(court)
		B.FloorDress(det)
		B.Backdrop(F(root, "11_Backdrop"))
		B.Environment()
	else
		B.Environment()
	end
	root.Parent = workspace
	return string.format("Built Map_Vantage (%s): %d parts", K.Stage, K.count)
end

return B
