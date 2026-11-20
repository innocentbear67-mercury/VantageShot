--[[
	ECLIPSE — Greybox builder (edit-time). Builds Workspace.Map_Eclipse:
	  A_OuterValley  B_GrandChamber  C_Installation (Blue)  D_GrandBridge  E_Undercroft
	  Sanctum (Red)  Landmarks  Gameplay {Spawns, KillVolumes, Lifts, Boundary, BotSpots, Callouts}
	  Systems (lift + kill-volume scripts)
	Greybox.Build(area) builds one area ("Root", "C", "Sanctum", "D", "B", "E", "A", "Landmarks").
	Coordinates: +X east, +Z north, studs. Terrain comes from Heightfield.
]]
local HF = require(script.Parent.Heightfield)
local K = require(script.Parent.Kit)
local PAL = K.PAL
local V, CF = Vector3.new, CFrame.new
local rad, cos, sin = math.rad, math.cos, math.sin
local box, P, ramp, tunnel, wall, carveBox = K.box, K.P, K.ramp, K.tunnel, K.wall, K.carveBox
local G = {}

local function root()
	local r = workspace:FindFirstChild("Map_Eclipse")
	if not r then
		r = Instance.new("Folder")
		r.Name = "Map_Eclipse"
		r:SetAttribute("Stage", "Greybox")
		r.Parent = workspace
	end
	return r
end
local function area(name)
	local r = root()
	local old = r:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = r
	return m
end
local function gp(name)
	return K.folder(K.folder(root(), "Gameplay"), name)
end

-- ════════ ROOT: gameplay scaffolding, systems, boundary ════════
function G.Root()
	local r = root()
	local g = K.folder(r, "Gameplay")
	for _, n in { "Spawns", "KillVolumes", "Lifts", "Boundary", "BotSpots", "Callouts" } do
		K.folder(g, n)
	end
	-- canyon kill plane (well above the gorge floor so falls end quickly)
	local kv = gp("KillVolumes")
	kv:ClearAllChildren()
	box(kv, "CanyonFall", -150, -170, 36, 170, -164, 900, PAL.Red, { Transparency = 1, CanCollide = false, CanQuery = false })
	-- invisible boundary (bullets pass: CanQuery off)
	local b = gp("Boundary")
	b:ClearAllChildren()
	local bp = { Transparency = 1, CanQuery = false, CanTouch = false }
	box(b, "West", -494, -260, -540, -488, 700, 445, PAL.Wall, bp)
	box(b, "East", 488, -260, -540, 494, 700, 445, PAL.Wall, bp)
	box(b, "North", -494, -260, 439, 494, 700, 445, PAL.Wall, bp)
	box(b, "South", -494, -260, -546, 494, 700, -540, PAL.Wall, bp)
	box(b, "Ceiling", -494, 700, -546, 494, 706, 445, PAL.Wall, bp)
	-- systems
	local sys = K.folder(r, "Systems")
	sys:ClearAllChildren()
	local server = Instance.new("Script")
	server.Name = "MapServer"
	server.Source = [[
-- ECLIPSE map server: kill volumes, and movement-validator exemptions for gravity lifts.
local Players = game:GetService("Players")
local map = script.Parent.Parent
local g = map:WaitForChild("Gameplay")
local vs = game:GetService("ServerScriptService"):FindFirstChild("VantageServer")
local exempt = vs and vs:WaitForChild("ExemptMovement", 10)
local function fromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return model, hum, model and Players:GetPlayerFromCharacter(model)
end
for _, kv in g:WaitForChild("KillVolumes"):GetChildren() do
	kv.Touched:Connect(function(hit)
		local _, hum = fromHit(hit)
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	end)
end
local recent = {}
for _, lift in g:WaitForChild("Lifts"):GetChildren() do
	lift.Touched:Connect(function(hit)
		local _, hum, plr = fromHit(hit)
		if plr and hum and hum.Health > 0 and (recent[plr] or 0) < os.clock() then
			recent[plr] = os.clock() + 1
			if exempt then
				exempt:Fire(plr, 3.5) -- the launch exceeds normal jump height
			end
		end
	end)
end
Players.PlayerRemoving:Connect(function(p) recent[p] = nil end)
]]
	server.Parent = sys
	local client = Instance.new("Script")
	client.Name = "MapClient"
	client.RunContext = Enum.RunContext.Client
	client.Source = [[
-- ECLIPSE map client: gravity lifts launch the local character (it owns its physics).
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local map = script.Parent.Parent
local lifts = map:WaitForChild("Gameplay"):WaitForChild("Lifts")
local cool = 0
local function hook(lift)
	lift.Touched:Connect(function(hit)
		local char = player.Character
		if not char or not hit:IsDescendantOf(char) or os.clock() < cool then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not (root and hum) or hum.Health <= 0 then
			return
		end
		cool = os.clock() + 1
		local h = lift:GetAttribute("LiftHeight") or 30
		local push = lift:GetAttribute("LiftPush") or Vector3.zero
		local vy = math.sqrt(2 * workspace.Gravity * (h + 4))
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		-- LiftClearY: hold the push until the player has risen out of a shaft
		local clearY = lift:GetAttribute("LiftClearY")
		root.AssemblyLinearVelocity = if clearY then Vector3.new(0, vy, 0) else Vector3.new(push.X, vy, push.Z)
		if push.Magnitude > 0 then
			-- carry the player along the push until they land, so the lift delivers them onto its landing
			local t0 = os.clock()
			local conn
			conn = game:GetService("RunService").Heartbeat:Connect(function()
				local st = hum:GetState()
				local landed = os.clock() - t0 > 0.25 and (st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed)
				if landed or os.clock() - t0 > 2.5 or hum.Health <= 0 or not root.Parent then
					conn:Disconnect()
					return
				end
				local v = root.AssemblyLinearVelocity
				if clearY and root.Position.Y < clearY then
					root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
					return
				end
				local flat = Vector3.new(v.X, 0, v.Z)
				local want = push + hum.MoveDirection * 8
				if flat:Dot(push.Unit) < push.Magnitude then
					root.AssemblyLinearVelocity = Vector3.new(want.X, v.Y, want.Z)
				end
			end)
		end
	end)
end
for _, l in lifts:GetChildren() do hook(l) end
lifts.ChildAdded:Connect(hook)
]]
	client.Parent = sys
end

-- ════════ C: MILITARY INSTALLATION (Blue spawn, west shelf, floor y=30) ════════
function G.C()
	local m = area("C_Installation")
	local Y = 30
	-- carve only the building footprints, so the structures sit embedded in the cliff
	carveBox(-441, Y, -56, -344, Y + 44, 46) -- hangar
	carveBox(-476, Y, -27, -440, Y + 18, 27) -- spawn room
	carveBox(-347, Y, 47, -315, Y + 32, 83) -- control tower
	carveBox(-433, Y, 46, -365, Y + 16, 91) -- armory
	carveBox(-441, Y, -141, -355, Y + 16, -56) -- labs
	carveBox(-345, Y, -150, -300, Y + 40, 92) -- apron in front of the buildings
	box(m, "Foundation", -478, Y - 10, -150, -312, Y, 92, PAL.Floor)
	-- HANGAR  x[-440,-345] z[-55,45] h 42
	local H = Y + 42
	local hg = K.model(m, "Hangar")
	wall(hg, "WallW", V(-440, Y, -55), V(-440, Y, 45), Y, H, 2, { { 47, 53 + 0, 0, 12 } }, PAL.Wall)
	wall(hg, "WallN", V(-440, Y, 45), V(-345, Y, 45), Y, H, 2, { { 34, 46, 0, 12 }, { 76, 88, 0, 12 } }, PAL.Wall)
	wall(hg, "WallS", V(-440, Y, -55), V(-345, Y, -55), Y, H, 2, { { 34, 46, 0, 12 } }, PAL.Wall)
	wall(hg, "WallE", V(-345, Y, -55), V(-345, Y, 45), Y, H, 2, { { 25, 85, 0, 28 } }, PAL.Wall)
	box(hg, "Roof", -441, H, -56, -344, H + 2, 46, PAL.Metal)
	-- mezzanine catwalks (y=44) on the west and north walls + stairs
	box(hg, "CatwalkN", -439, Y + 13, 33, -346, Y + 14, 44, PAL.Floor)
	box(hg, "CatwalkW", -439, Y + 13, -54, -428, Y + 14, 33, PAL.Floor)
	box(hg, "CatwalkRailN", -428, Y + 14, 33, -346, Y + 17, 34, PAL.Cover)
	ramp(hg, "StairsN", V(-372, Y, 8), V(-372, Y + 14, 33), 8)
	ramp(hg, "StairsW", V(-410, Y, -40), V(-430, Y + 14, -40), 7)
	-- dropship placeholder + floor cover
	box(hg, "Dropship_Body", -412, Y + 4, -26, -378, Y + 14, 18, PAL.Metal)
	box(hg, "Dropship_Wings", -420, Y + 9, -10, -370, Y + 11, 2, PAL.Metal)
	box(hg, "Dropship_Gear", -400, Y, -18, -390, Y + 4, 10, PAL.Cover)
	for _, c in { { -365, -40, 6, 4 }, { -360, 22, 8, 4 }, { -420, 30, 6, 7 }, { -432, -20, 5, 4 }, { -355, -8, 4, 7 } } do
		box(hg, "Crate", c[1] - c[3] / 2, Y, c[2] - c[3] / 2, c[1] + c[3] / 2, Y + c[4], c[2] + c[3] / 2, PAL.Cover)
	end
	-- BLUE SPAWN ROOM behind the hangar (inside the mountain)
	local sp = K.model(m, "SpawnRoom")
	box(sp, "Floor", -474, Y, -26, -441, Y + 0.2, 26, PAL.Blue)
	wall(sp, "WallW", V(-474, Y, -26), V(-474, Y, 26), Y, Y + 16, 2, nil, PAL.Wall)
	wall(sp, "WallN", V(-474, Y, 26), V(-441, Y, 26), Y, Y + 16, 2, nil, PAL.Wall)
	wall(sp, "WallS", V(-474, Y, -26), V(-441, Y, -26), Y, Y + 16, 2, { { 8, 20, 0, 12 } }, PAL.Wall)
	box(sp, "Roof", -475, Y + 16, -27, -440, Y + 18, 27, PAL.Metal)
	for _, x in { -466, -456 } do
		for _, z in { -14, 0, 14 } do
			K.spawnPad(gp("Spawns"), V(x, Y + 0.2, z), "Blue")
		end
	end
	-- CONTROL TOWER with observation deck over the valley  x[-346,-316] z[48,82]
	local tw = K.model(m, "ControlTower")
	wall(tw, "WallW", V(-346, Y, 48), V(-346, Y, 82), Y, Y + 30, 1.5, { { 4, 14, 0, 11 } }, PAL.Wall)
	wall(tw, "WallN", V(-346, Y, 82), V(-316, Y, 82), Y, Y + 30, 1.5, { { 10, 20, 0, 11 } }, PAL.Wall)
	wall(tw, "WallS", V(-346, Y, 48), V(-316, Y, 48), Y, Y + 30, 1.5, { { 10, 20, 0, 11 } }, PAL.Wall)
	wall(tw, "WallE", V(-316, Y, 48), V(-316, Y, 82), Y, Y + 30, 1.5, { { 3, 31, 19, 27 } }, PAL.Wall)
	box(tw, "ObservationGlass", -316.5, Y + 19, 51, -315.5, Y + 27, 79, PAL.Glass, { Transparency = 0.6, Material = Enum.Material.Glass })
	box(tw, "DeckFloor", -345, Y + 15, 49, -317, Y + 16, 81, PAL.Floor)
	box(tw, "Roof", -347, Y + 30, 47, -315, Y + 31.5, 83, PAL.Metal)
	ramp(tw, "DeckStairs", V(-322, Y, 52), V(-322, Y + 16, 76), 7)
	box(tw, "Consoles", -330, Y + 16, 54, -322, Y + 19.5, 76, PAL.Cover)
	ramp(tw, "SkyBridge", V(-352, Y + 14, 40), V(-346, Y + 16, 56), 6) -- hangar catwalk -> deck
	-- ARMORY north of the hangar  x[-432,-366] z[47,90]
	local ar = K.model(m, "Armory")
	wall(ar, "WallW", V(-432, Y, 47), V(-432, Y, 90), Y, Y + 14, 1.5, nil, PAL.Wall)
	wall(ar, "WallN", V(-432, Y, 90), V(-366, Y, 90), Y, Y + 14, 1.5, { { 26, 38, 0, 11 } }, PAL.Wall)
	wall(ar, "WallE", V(-366, Y, 47), V(-366, Y, 90), Y, Y + 14, 1.5, { { 14, 26, 0, 11 } }, PAL.Wall)
	box(ar, "Roof", -433, Y + 14, 46, -365, Y + 15.5, 91, PAL.Metal)
	for i = 0, 3 do
		box(ar, "WeaponRack", -424 + i * 14, Y, 60, -418 + i * 14, Y + 6, 78, PAL.Cover)
	end
	-- RESEARCH LABS south wing  x[-440,-356] z[-140,-57]
	local lb = K.model(m, "Labs")
	wall(lb, "WallW", V(-440, Y, -140), V(-440, Y, -57), Y, Y + 14, 1.5, nil, PAL.Wall)
	wall(lb, "WallS", V(-440, Y, -140), V(-356, Y, -140), Y, Y + 14, 1.5, nil, PAL.Wall)
	wall(lb, "WallE", V(-356, Y, -140), V(-356, Y, -57), Y, Y + 14, 1.5, { { 30, 44, 0, 11 } }, PAL.Wall)
	box(lb, "Roof", -441, Y + 14, -141, -355, Y + 15.5, -56, PAL.Metal)
	-- corridor walls with lab doorways
	wall(lb, "CorridorN", V(-440, Y, -92), V(-356, Y, -92), Y, Y + 14, 1, { { 10, 20, 0, 10 }, { 40, 50, 0, 10 }, { 70, 82, 0, 10 } }, PAL.Ancient)
	wall(lb, "CorridorS", V(-440, Y, -106), V(-356, Y, -106), Y, Y + 14, 1, { { 18, 28, 0, 10 }, { 50, 60, 0, 10 } }, PAL.Ancient)
	for _, b in { { -425, -80 }, { -395, -78 }, { -372, -122 }, { -415, -125 } } do
		box(lb, "LabBench", b[1] - 6, Y, b[2] - 2.5, b[1] + 6, Y + 3.5, b[2] + 2.5, PAL.Cover)
	end
	-- stairwell down to the Undercroft service tunnel (from the lab floor)
	tunnel(m, "UndercroftAccess", {
		V(-404, Y, -128), V(-372, Y - 12, -128), V(-330, 0, -112), V(-250, -24, -60), V(-160, -42, -12), V(-112, -46, 4),
	}, 14, 12, PAL.Floor)
	-- BACK CORRIDOR behind the spawn room: armory <-> labs flank inside the mountain
	tunnel(m, "BackCorridor", { V(-430, Y, 70), V(-484, Y, 60), V(-486, Y, -80), V(-430, Y, -96) }, 12, 12, PAL.Floor)
	K.callout(gp("Callouts"), V(-395, Y + 60, -5), "C · MILITARY INSTALLATION", "BLUE SPAWN · hangar · tower · armory · labs")
end

-- ════════ SANCTUM (Red spawn, east plateau, ground y≈40) ════════
function G.Sanctum()
	local m = area("Sanctum")
	local Y = 41
	carveBox(296, Y, -140, 462, Y + 30, -20) -- level the plateau under the court
	-- courtyard floor (leaves the stairwell open)
	box(m, "Court_A", 300, Y - 4, -136, 340, Y, -24, PAL.Ancient)
	box(m, "Court_B", 374, Y - 4, -136, 452, Y, -24, PAL.Ancient)
	box(m, "Court_C", 340, Y - 4, -136, 374, Y, -64, PAL.Ancient)
	box(m, "Court_D", 340, Y - 4, -52, 374, Y, -24, PAL.Ancient)
	-- monolithic walls (ancient), broken into slabs with gaps
	for i, z in { -136, -24 } do
		for k = 0, 5 do
			if k ~= 2 then
				box(m, "Monolith", 304 + k * 24, Y, z - 3, 322 + k * 24, Y + 22 + (k % 2) * 8, z + 3, PAL.Ancient)
			end
		end
	end
	-- pylons around the court (landmark silhouette)
	for _, p in { { 322, -118 }, { 322, -42 }, { 410, -118 }, { 410, -42 } } do
		box(m, "Pylon", p[1] - 3, Y, p[2] - 3, p[1] + 3, Y + 46, p[2] + 3, PAL.Ancient)
		box(m, "PylonGlow", p[1] - 3.2, Y + 30, p[2] - 0.6, p[1] + 3.2, Y + 40, p[2] + 0.6, PAL.Energy, { Material = Enum.Material.Neon })
	end
	-- inner sanctum / RED SPAWN  x[420,456] z[-112,-48]
	local sp = K.model(m, "InnerSanctum")
	wall(sp, "WallE", V(456, Y, -112), V(456, Y, -48), Y, Y + 20, 3, nil, PAL.Ancient)
	wall(sp, "WallN", V(420, Y, -48), V(456, Y, -48), Y, Y + 20, 3, nil, PAL.Ancient)
	wall(sp, "WallS", V(420, Y, -112), V(456, Y, -112), Y, Y + 20, 3, nil, PAL.Ancient)
	wall(sp, "WallW", V(420, Y, -112), V(420, Y, -48), Y, Y + 20, 3, { { 22, 42, 0, 14 } }, PAL.Ancient)
	box(sp, "Roof", 418, Y + 20, -114, 458, Y + 23, -46, PAL.Ancient)
	box(sp, "Floor", 421, Y, -111, 455, Y + 0.2, -49, PAL.Red)
	for _, x in { 436, 446 } do
		for _, z in { -96, -80, -64 } do
			K.spawnPad(gp("Spawns"), V(x, Y + 0.2, z), "Red")
		end
	end
	-- overlook terrace facing the valley (high ground, exposed)
	box(m, "Overlook", 300, Y, -100, 326, Y + 10, -64, PAL.Ancient)
	ramp(m, "OverlookRamp", V(340, Y, -104), V(326, Y + 10, -104), 8, PAL.Ancient)
	box(m, "OverlookCover", 300, Y + 10, -100, 302, Y + 13.5, -64, PAL.Cover)
	-- twin obelisk gate at the escarpment top
	for _, z in { -78, -42 } do
		box(m, "GateObelisk", 286, Y - 2, z - 4, 294, Y + 52, z + 4, PAL.Ancient)
	end
	-- grand staircase down the escarpment to the valley
	local gx = 214
	local gy = K.ground(gx, -60) + 0.5
	-- cut the stair's path through the escarpment so it reads as a carved processional way
	for s = 0, 11 do
		local xa, xb = 298 + (gx - 298) * s / 12, 298 + (gx - 298) * (s + 1) / 12
		local yb = Y + (gy - Y) * (s + 1) / 12
		carveBox(math.min(xa, xb), yb + 0.3, -71, math.max(xa, xb), Y + 40, -49)
	end
	ramp(m, "GrandStair", V(298, Y, -60), V(gx, gy, -60), 18, PAL.Ancient, 2)
	for k = 1, 4 do
		local t = k / 5
		local px = 298 + (gx - 298) * t
		local top = Y + (gy - Y) * t
		local base = K.ground(px, -60) - 2
		if top - base > 3 then
			box(m, "StairPier", px - 2, base, -70, px + 2, top - 1, -50, PAL.Ancient)
		end
	end
	-- gravity lift up the escarpment (north end), landing deck at plateau height
	local lx, lz = 222, 38
	local lg = K.ground(lx, lz)
	K.lift(gp("Lifts"), m, "EscarpmentLift", V(lx, lg, lz), Y - lg + 6, V(26, 0, 0))
	box(m, "LiftColumn", lx - 13, lg, lz - 4, lx - 9, Y + 30, lz + 4, PAL.Ancient)
	box(m, "LiftLanding", 246, Y - 1, lz - 10, 276, Y, lz + 10, PAL.Ancient)
	-- vault below the court -> Undercroft
	carveBox(296, 16, -84, 378, 37, -34)
	box(m, "VaultFloor", 296, 14, -84, 378, 16, -34, PAL.Ancient)
	ramp(m, "VaultStair", V(372, Y, -58), V(342, 16, -58), 11, PAL.Ancient)
	carveBox(338, 16, -64, 376, Y, -52)
	for _, p in { { 312, -70 }, { 312, -48 }, { 330, -70 }, { 330, -48 } } do
		box(m, "VaultColumn", p[1] - 2, 16, p[2] - 2, p[1] + 2, 37, p[2] + 2, PAL.Ancient)
	end
	tunnel(m, "UndercroftAccess", { V(298, 16, -60), V(250, 0, -45), V(170, -30, -20), V(80, -44, 0), V(22, -46, 4) }, 14, 12, PAL.Ancient)
	-- south exit toward the chamber's east tunnel
	K.callout(gp("Callouts"), V(370, Y + 66, -80), "SANCTUM", "RED SPAWN · court · overlook · grand stair · lift")
end

-- ════════ D: GRAND BRIDGE (crosses the canyon at z=170, deck y=40) ════════
function G.D()
	local m = area("D_GrandBridge")
	local Z, Y = 170, 40
	local cx = HF.CanyonCentre(Z)
	local x0, x1 = cx - 82, cx + 82
	box(m, "Deck", x0, Y - 3, Z - 8, x1, Y, Z + 8, PAL.Ancient)
	box(m, "DeckEnergy", x0 + 4, Y - 0.1, Z - 0.6, x1 - 4, Y + 0.05, Z + 0.6, PAL.Energy, { Material = Enum.Material.Neon, CanCollide = false })
	box(m, "Keel", x0 + 10, Y - 10, Z - 2, x1 - 10, Y - 3, Z + 2, PAL.Metal)
	for k = 0, 8 do
		local x = x0 + 18 + k * ((x1 - x0 - 36) / 8)
		box(m, "Rib", x - 1, Y - 8, Z - 8, x + 1, Y - 3, Z + 8, PAL.Metal)
	end
	-- low cover along the edges (gaps between) + two mid-span blocks
	for _, side in { -1, 1 } do
		for k = 0, 6 do
			local x = x0 + 16 + k * 22
			box(m, "Barrier", x, Y, Z + side * 8 - 0.6, x + 12, Y + 3.5, Z + side * 8 + 0.6, PAL.Cover)
		end
	end
	box(m, "MidCover", cx - 14, Y, Z - 3, cx - 8, Y + 4, Z + 3, PAL.Cover)
	box(m, "MidCover", cx + 8, Y, Z - 3, cx + 14, Y + 4, Z + 3, PAL.Cover)
	-- twin pylons at each end (structure + landmark)
	for _, x in { x0 - 6, x1 + 6 } do
		for _, dz in { -13, 13 } do
			box(m, "Pylon", x - 4, Y - 6, Z + dz - 4, x + 4, Y + 72, Z + dz + 4, PAL.Ancient)
			box(m, "PylonGlow", x - 4.2, Y + 40, Z + dz - 0.6, x + 4.2, Y + 64, Z + dz + 0.6, PAL.Energy, { Material = Enum.Material.Neon })
		end
	end
	-- cable stays from the pylon tops to the deck quarter points
	for _, end_ in { { x0 - 6, 1 }, { x1 + 6, -1 } } do
		for _, dz in { -8.5, 8.5 } do
			for _, t in { 0.22, 0.42 } do
				local top = V(end_[1], Y + 70, Z + dz * 1.5)
				local deckPt = V(end_[1] + end_[2] * (x1 - x0) * t, Y - 0.5, Z + dz)
				local mid = (top + deckPt) / 2
				P(m, "Stay", V(0.6, 0.6, (deckPt - top).Magnitude), CFrame.lookAt(mid, deckPt), PAL.Metal, { CanCollide = false })
			end
		end
	end
	-- lower maintenance catwalk (y=12) hung below the deck
	local cy = 12
	box(m, "Catwalk", cx - 70, cy - 1, Z - 3, cx + 70, cy, Z + 3, PAL.Metal)
	for k = 0, 6 do
		local x = cx - 60 + k * 20
		box(m, "Hanger", x - 0.3, cy, Z - 3.3, x + 0.3, Y - 3, Z - 2.7, PAL.Metal, { CanCollide = false })
		box(m, "Hanger", x - 0.3, cy, Z + 2.7, x + 0.3, Y - 3, Z + 3.3, PAL.Metal, { CanCollide = false })
	end
	box(m, "CatwalkCover", cx - 4, cy, Z - 3, cx + 4, cy + 3, Z - 2, PAL.Cover)
	-- wall portals and tunnels: west -> junction -> (west plateau bunker | Undercroft), east -> east plateau bunker
	tunnel(m, "WestPortal", { V(cx - 66, cy, Z), V(cx - 92, cy, Z), V(-104, 18, 146), V(-118, 30, 170), V(-132, 41, 198) }, 10, 11, PAL.Floor)
	tunnel(m, "WestToUndercroft", { V(-104, 18, 146), V(-92, 2, 110), V(-72, -28, 70), V(-56, -46, 44) }, 10, 11, PAL.Floor)
	tunnel(m, "EastPortal", { V(cx + 66, cy, Z), V(cx + 92, cy, Z), V(118, 26, 188), V(134, 41, 208) }, 10, 11, PAL.Floor)
	for _, p in { { -132, 198 }, { 134, 208 } } do
		box(m, "BunkerFrame", p[1] - 8, 40, p[2] - 2, p[1] + 8, 54, p[2] + 2, PAL.Wall)
	end
	-- waterfall sheet at the canyon lip
	local wx = HF.CanyonCentre(48)
	box(m, "Waterfall", wx - 11, -224, 46, wx + 11, 0, 49, PAL.Water, { Transparency = 0.35, CanCollide = false, CanQuery = false, Material = Enum.Material.Glass })
	K.callout(gp("Callouts"), V(cx, Y + 90, Z), "D · GRAND BRIDGE", "deck y40 · catwalk y12 · drop 270")
end

-- ════════ B: GRAND CHAMBER (inside the south massif) ════════
function G.B()
	local m = area("B_GrandChamber")
	local CZ = -425 -- chamber centre
	local F = -20 -- floor
	carveBox(-136, F - 4, -522, 136, 152, -328)
	-- floor slabs around the reactor pit  pit x[-30,30] z[-455,-395]
	box(m, "Floor_N", -134, F - 4, -395, 134, F, -330, PAL.Floor)
	box(m, "Floor_S", -134, F - 4, -520, 134, F, -455, PAL.Floor)
	box(m, "Floor_W", -134, F - 4, -455, -30, F, -395, PAL.Floor)
	box(m, "Floor_E", 30, F - 4, -455, 134, F, -395, PAL.Floor)
	carveBox(-30, -50, -455, 30, F, -395)
	box(m, "PitFloor", -30, -50, -455, 30, -46, -395, PAL.Ancient)
	ramp(m, "PitRamp", V(-25, F, -455), V(-25, -46, -405), 8, PAL.Ancient)
	-- reactor core
	local core = V(0, 0, CZ)
	P(m, "ReactorCore", V(196, 16, 16), CF(0, 52, CZ) * CFrame.Angles(0, 0, rad(90)), PAL.Energy, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, CanCollide = true })
	for _, y in { -30, 0, 30, 60, 100 } do
		P(m, "ReactorRing", V(2, 34, 34), CF(0, y, CZ) * CFrame.Angles(0, 0, rad(90)), PAL.Metal, { Shape = Enum.PartType.Cylinder })
	end
	-- colossal pillars (ring of 8)
	for k = 0, 7 do
		local a = rad(22.5 + k * 45)
		local px, pz = cos(a) * 96, CZ + sin(a) * 76
		box(m, "Pillar", px - 8, F, pz - 8, px + 8, 152, pz + 8, PAL.Ancient)
	end
	-- wall buttresses
	for x = -120, 120, 30 do
		box(m, "Buttress", x - 3, F, -522, x + 3, 150, -516, PAL.Ancient)
		box(m, "Buttress", x - 3, F, -336, x + 3, 150, -330, PAL.Ancient)
	end
	-- ring walkway y=+12 (octagon of radius ~62)
	local RY = 12
	for k = 0, 7 do
		local a0, a1 = rad(k * 45), rad((k + 1) * 45)
		local p0 = V(cos(a0) * 64, RY, CZ + sin(a0) * 52)
		local p1 = V(cos(a1) * 64, RY, CZ + sin(a1) * 52)
		ramp(m, "RingWalk", p0, p1, 10, PAL.Floor, 1.5)
	end
	ramp(m, "RingRampW", V(-110, F, -395), V(-64, RY, -425 + 0), 10, PAL.Floor, 1.5)
	ramp(m, "RingRampE", V(110, F, -455), V(64, RY, -425), 10, PAL.Floor, 1.5)
	-- upper level y=+45: E-W span over the reactor with a ring platform around the core
	local UY = 45
	box(m, "UpperSpan", -128, UY - 2, CZ - 6, 128, UY, CZ + 6, PAL.Ancient)
	box(m, "CorePlatformN", -22, UY - 2, CZ + 6, 22, UY, CZ + 22, PAL.Ancient)
	box(m, "CorePlatformS", -22, UY - 2, CZ - 22, 22, UY, CZ - 6, PAL.Ancient)
	-- long wall ramps (16°) from the floor to the upper level, plus wall walkways to the span
	ramp(m, "UpperRampN", V(-110, F, -340), V(110, UY, -340), 9, PAL.Ancient, 1.5)
	box(m, "UpperLandingNE", 104, UY - 2, -345, 132, UY, -335, PAL.Ancient)
	box(m, "UpperWalkE", 122, UY - 2, -405, 132, UY, -345, PAL.Ancient)
	ramp(m, "UpperRampS", V(110, F, -510), V(-110, UY, -510), 9, PAL.Ancient, 1.5)
	box(m, "UpperLandingSW", -132, UY - 2, -515, -104, UY, -505, PAL.Ancient)
	box(m, "UpperWalkW", -134, UY - 2, -505, -124, UY, -419, PAL.Ancient)
	-- balconies where the side tunnels arrive
	box(m, "BalconyW", -134, RY - 2, -445, -100, RY, -405, PAL.Floor)
	ramp(m, "BalconyW_Link", V(-100, RY, -425), V(-64, RY, -425), 10, PAL.Floor, 1.5)
	box(m, "BalconyE", 100, UY - 2, -445, 134, UY, -405, PAL.Ancient)
	-- floor cover
	for _, c in { { -80, -360, 10, 5 }, { 70, -365, 8, 7 }, { -60, -490, 8, 7 }, { 85, -490, 10, 5 }, { -110, -500, 6, 4 }, { 115, -350, 6, 4 } } do
		box(m, "Cover", c[1] - c[3] / 2, F, c[2] - c[3] / 2, c[1] + c[3] / 2, F + c[4], c[2] + c[3] / 2, PAL.Cover)
	end
	-- valley gate + entry tunnel (40 x 40)
	local gz = -268
	local gg = K.ground(0, gz)
	tunnel(m, "GateTunnel", { V(0, gg, gz), V(0, gg - 2, -300), V(0, F, -334) }, 40, 40, PAL.Floor)
	for _, x in { -26, 26 } do
		box(m, "GatePylon", x - 6, gg - 2, gz - 10, x + 6, gg + 58, gz + 2, PAL.Ancient)
	end
	box(m, "GateLintel", -32, gg + 44, gz - 10, 32, gg + 54, gz + 2, PAL.Ancient)
	-- west tunnel (floor-ish level) -> valley SW ; east tunnel (upper level) -> east plateau
	local wx, wz = -258, -258
	tunnel(m, "WestTunnel", { V(-134, RY, -425), V(-190, RY, -380), V(-238, 10, -300), V(wx, K.ground(wx, wz) + 0.5, wz) }, 14, 14, PAL.Floor)
	local ex, ez = 268, -238
	tunnel(m, "EastTunnel", { V(134, UY, -425), V(190, UY - 1, -370), V(240, 42, -290), V(ex, K.ground(ex, ez) + 0.5, ez) }, 14, 14, PAL.Ancient)
	K.callout(gp("Callouts"), V(0, 90, CZ), "B · GRAND CHAMBER", "floor -20 · ring 12 · upper 45 · ceiling 150")
end

-- ════════ E: UNDERCROFT (beneath the valley) ════════
function G.E()
	local m = area("E_Undercroft")
	local F = -46
	carveBox(-112, F, -32, 22, F + 26, 42)
	box(m, "HallFloor", -112, F - 2, -32, 22, F, 42, PAL.Floor)
	for x = -92, 2, 24 do
		for _, z in { -14, 24 } do
			box(m, "Column", x - 2.5, F, z - 2.5, x + 2.5, F + 26, z + 2.5, PAL.Ancient)
		end
	end
	-- machinery: generators (cover) and an ancient energy conduit
	for _, g in { { -78, 5, 14, 9 }, { -30, 5, 16, 7 }, { 0, -20, 8, 5 }, { -100, 30, 8, 5 } } do
		box(m, "Generator", g[1] - g[3] / 2, F, g[2] - 5, g[1] + g[3] / 2, F + g[4], g[2] + 5, PAL.Metal)
	end
	box(m, "Conduit", -110, F + 22, 3, 20, F + 24, 7, PAL.Energy, { Material = Enum.Material.Neon, CanCollide = false })
	-- south tunnel to the chamber's reactor pit, via a pump station
	tunnel(m, "SouthTunnel", { V(-30, F, -32), V(-20, F, -100), V(-10, F, -185) }, 12, 12, PAL.Floor)
	carveBox(-28, F, -215, 8, F + 16, -185)
	box(m, "PumpStation", -28, F - 2, -215, 8, F, -185, PAL.Floor)
	box(m, "Pump", -20, F, -206, -8, F + 8, -194, PAL.Metal)
	tunnel(m, "SouthTunnel2", { V(-10, F, -215), V(0, F, -300), V(0, F, -395) }, 12, 12, PAL.Floor)
	-- valley vent shaft with a lift (drop in from the valley, lift back out)
	local vx, vz = -84, 34
	local top = K.ground(vx, vz)
	carveBox(vx - 6, F, vz - 6, vx + 6, top + 4, vz + 6)
	K.lift(gp("Lifts"), m, "VentLift", V(vx, F, vz), top - F + 8, V(0, 0, 30))
	gp("Lifts").VentLift:SetAttribute("LiftClearY", top + 3)
	box(m, "VentRim", vx - 8, top - 1, vz - 8, vx + 8, top + 1, vz - 6, PAL.Metal)
	box(m, "VentRim", vx - 8, top - 1, vz + 6, vx + 8, top + 1, vz + 8, PAL.Metal)
	box(m, "VentRim", vx - 8, top - 1, vz - 6, vx - 6, top + 1, vz + 6, PAL.Metal)
	box(m, "VentRim", vx + 6, top - 1, vz - 6, vx + 8, top + 1, vz + 6, PAL.Metal)
	-- gorge window: the hall's north end breaks into the canyon wall; glaze it as an observation window
	box(m, "GorgeWindow", -46, F - 2, 36, 26, F + 30, 37.5, PAL.Glass)
	for _, wx in { -46, -28, -10, 8, 24 } do
		box(m, "GorgeMullion", wx, F - 2, 35, wx + 2, F + 30, 38.5, PAL.Metal)
	end
	box(m, "GorgeSill", -46, F, 34, 26, F + 3, 38.5, PAL.Metal)
	box(m, "GorgeHeader", -46, F + 24, 34, 26, F + 30, 38.5, PAL.Metal)
	K.callout(gp("Callouts"), V(-45, 30, 5), "E · UNDERCROFT", "hall -46 · 4 tunnels + vent lift")
end

-- ════════ A: OUTER VALLEY (cover, ruins, crossings, landmark) ════════
function G.A()
	local m = area("A_OuterValley")
	local function onGround(name, x, z, sx, sy, sz, color, rot)
		local g = K.ground(x, z)
		return P(m, name, V(sx, sy, sz), CF(x, g + sy / 2 - 1, z) * CFrame.Angles(0, rad(rot or 0), 0), color or PAL.Cover)
	end
	-- river crossings
	local function slab(x, z, len, rot)
		P(m, "Crossing", V(7, 1, len), CF(x, 1.2, z) * CFrame.Angles(0, rad(rot), 0), PAL.Ancient)
	end
	slab(-21, -40, 30, 18)
	slab(-6, 22, 26, 75)
	-- THE NEEDLE: ruined ancient tower on the mid-field spine (long sightlines, exposed)
	local nx, nz = 110, -150
	local ng = K.ground(nx, nz)
	P(m, "NeedleBase", V(30, 8, 30), CF(nx, ng + 3, nz), PAL.Ancient)
	P(m, "NeedleTower", V(10, 74, 10), CF(nx + 6, ng + 44, nz + 6), PAL.Ancient)
	P(m, "NeedleLedge", V(14, 2, 18), CF(nx - 4, ng + 24, nz + 4), PAL.Ancient) -- High Jump only
	ramp(m, "NeedleRamp", V(nx - 28, K.ground(nx - 28, nz - 10) + 0.5, nz - 10), V(nx - 15, ng + 7, nz - 10), 7, PAL.Ancient)
	P(m, "NeedleGlow", V(10.4, 18, 1.2), CF(nx + 6, ng + 60, nz + 0.8), PAL.Energy, { Material = Enum.Material.Neon })
	-- ancient wall ruins: broken cover lines across the mid field
	for _, w in { { -130, -110, 34, 35 }, { 60, -60, 30, -20 }, { -90, -230, 40, 10 }, { 180, -20, 26, 70 }, { -200, -170, 24, -50 }, { 30, -230, 28, 30 } } do
		onGround("RuinWall", w[1], w[2], w[3], 7, 3, PAL.Ancient, w[4])
		onGround("RuinBlock", w[1] + 8, w[2] + 6, 6, 4, 6, PAL.Ancient, w[4] + 20)
	end
	-- boulder clusters (rock cover)
	for _, r in {
		{ -60, -40, 9 }, { 40, -110, 11 }, { -160, -40, 8 }, { 150, -230, 12 }, { -220, -90, 10 }, { 200, -120, 9 },
		{ -40, -250, 10 }, { 80, 10, 8 }, { -150, 40, 9 }, { 140, 60, 10 },
	} do
		onGround("Boulder", r[1], r[2], r[3], r[3] * 0.75, r[3] * 0.9, PAL.Cover, r[1] % 90)
		onGround("Boulder", r[1] + r[3] * 0.7, r[2] - r[3] * 0.4, r[3] * 0.6, r[3] * 0.5, r[3] * 0.6, PAL.Cover, r[2] % 70)
	end
	-- ruined structures embedded in the valley walls (scale / backdrop)
	P(m, "CliffFacade", V(4, 60, 80), CF(-472, 40, -250) * CFrame.Angles(0, 0, rad(-8)), PAL.Ancient)
	P(m, "CliffFacade", V(80, 50, 4), CF(-60, 30, -300), PAL.Ancient)
	K.callout(gp("Callouts"), V(-40, 70, -120), "A · OUTER VALLEY", "lake · river · Needle ruin · mid-field cover")
	K.callout(gp("Callouts"), V(nx, ng + 90, nz), "THE NEEDLE", "ruin tower · high ground")
end

-- ════════ LANDMARKS (distant scenery, always streamed) ════════
function G.Landmarks()
	local m = area("Landmarks")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	-- the Spire: colossal ancient needle on the northern horizon
	P(m, "Spire", V(70, 1500, 70), CF(140, 700, 1450), PAL.Ancient, { CanCollide = false, CanQuery = false, CastShadow = false })
	P(m, "SpireCrown", V(130, 90, 130), CF(140, 1460, 1450), PAL.Ancient, { CanCollide = false, CanQuery = false, CastShadow = false })
	P(m, "SpireBeam", V(14, 1400, 14), CF(140, 720, 1412), PAL.Energy, { Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
	-- the Eclipse: a dark planetoid over the sun-side horizon with a glowing corona
	P(m, "EclipseBody", V(1100, 1100, 1100), CF(-1500, 1700, 3200), Color3.fromRGB(18, 22, 30), { Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false })
	P(m, "EclipseCorona", V(24, 1260, 1260), CF(-1500, 1700, 3260) * CFrame.Angles(0, rad(90), 0), PAL.Energy, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false, CastShadow = false })
end

-- ════════ HOOKUPS: markers read by existing systems (CombatBot) ════════
function G.Hookups()
	local folder = workspace.Map_Eclipse.Gameplay.BotSpots
	folder:ClearAllChildren()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	-- where the bot stands when a player spawns on that team: just outside their spawn room
	for name, at in { Blue = Vector3.new(-402, 30, 0), Red = Vector3.new(396, 41, -80) } do
		local hit = workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(2, 0.2, 2)
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Transparency = 1
		p.Position = Vector3.new(at.X, if hit then hit.Position.Y else at.Y, at.Z)
		p.Parent = folder
	end
end

function G.Build(which)
	K.count = 0
	G[which]()
	return K.count
end

return G
