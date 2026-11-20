--[[
	ECLIPSE — Dress (Phase 5): turns the greybox into finished architecture.
	Skin: real materials/colours on every greybox part (gameplay geometry unchanged).
	Detail: non-colliding trim (plinths, caps, grooves, ribs, coping, fascia, roof kit, lights)
	parented to <Area>/Detail so it can be rebuilt any time:  require(Dress).Skin("B_GrandChamber")
]]
local D = {}
local V, CF = Vector3.new, CFrame.new
local C3 = Color3.fromRGB
local M = Enum.Material
local rng = Random.new(2026)

local S = {
	Ancient = { C3(128, 134, 150), M.Metal, "Eclipse_AncientTrim3" },
	AncientDk = { C3(84, 90, 104), M.Metal, "Eclipse_RibbedWall" },
	AncientFl = { C3(140, 144, 156), M.Slate, "Eclipse_AncientFloor" },
	Steel = { C3(150, 155, 166), M.DiamondPlate, "Eclipse_MilitaryPlate1" },
	SteelDk = { C3(96, 101, 112), M.Metal, "Eclipse_RibbedWall2" },
	Plate = { C3(150, 152, 158), M.DiamondPlate, "Eclipse_IndustrialFloor1" },
	Tile = { C3(140, 144, 152), M.DiamondPlate, "Eclipse_MilitaryPlate2" },
	RoofPlate = { C3(130, 134, 142), M.DiamondPlate, "Eclipse_MilitaryPlate3" },
	Concrete = { C3(92, 94, 98), M.Concrete },
	Rust = { C3(88, 78, 70), M.CorrodedMetal },
	Energy = { C3(64, 186, 255), M.Neon },
	EnergyDim = { C3(28, 112, 176), M.Neon },
	Lamp = { C3(236, 242, 255), M.Neon },
	Amber = { C3(255, 160, 64), M.Neon },
	Hazard = { C3(200, 160, 40), M.SmoothPlastic },
	Glass = { C3(130, 170, 200), M.Glass },
	Blue = { C3(50, 110, 235), M.Neon },
	Red = { C3(235, 58, 52), M.Neon },
	Black = { C3(20, 21, 25), M.Metal },
}
D.S = S

local SKIN = {
	C_Installation = {
		_ = "Steel", Floor = "Tile", Foundation = "Concrete", Roof = "RoofPlate", ["Catwalk*"] = "Plate", ["Stairs*"] = "Plate",
		DeckFloor = "Plate", DeckStairs = "Plate", SkyBridge = "Plate", Crate = "SteelDk", ["Dropship*"] = "SteelDk",
		Consoles = "SteelDk", LabBench = "Steel", WeaponRack = "SteelDk", ObservationGlass = "Glass", Light = "Lamp",
		CatwalkRailN = "SteelDk",
	},
	Sanctum = {
		_ = "Ancient", Floor = "AncientFl", ["Court*"] = "AncientFl", PylonGlow = "EnergyDim", Light = "Lamp",
		EscarpmentLift_Pad = "Energy", EscarpmentLift_Ring = "AncientDk", GrandStair = "AncientFl", LiftLanding = "AncientFl",
		VaultFloor = "AncientFl", VaultStair = "AncientFl", OverlookRamp = "AncientFl", LiftColumn = "AncientDk",
	},
	D_GrandBridge = {
		_ = "Ancient", Deck = "AncientFl", Catwalk = "Plate", DeckEnergy = "Energy", PylonGlow = "EnergyDim", Light = "Lamp",
		Floor = "Tile", Hanger = "AncientDk", Stay = "AncientDk", Barrier = "AncientDk", Rib = "AncientDk", Keel = "AncientDk",
		BunkerFrame = "Steel", CatwalkCover = "SteelDk", MidCover = "AncientDk",
	},
	B_GrandChamber = {
		_ = "Ancient", ["Floor*"] = "AncientFl", PitFloor = "AncientFl", ReactorCore = "Energy", ReactorRing = "AncientDk",
		Light = "Lamp", ["Ring*"] = "AncientFl", ["Upper*"] = "AncientFl", ["CorePlatform*"] = "AncientFl", ["Balcony*"] = "AncientFl",
		Cover = "AncientDk", Buttress = "AncientDk", PitRamp = "AncientFl",
	},
	E_Undercroft = {
		_ = "SteelDk", HallFloor = "Plate", Floor = "Plate", PumpStation = "Plate", Column = "Concrete", Generator = "Rust",
		Pump = "Rust", Conduit = "EnergyDim", Light = "Lamp", ["Gorge*"] = "SteelDk", GorgeWindow = "Glass",
		VentLift_Pad = "Energy", VentLift_Ring = "Hazard", VentRim = "Hazard",
	},
	A_OuterValley = {
		_ = "Ancient", NeedleGlow = "EnergyDim", Crossing = "AncientFl", NeedleLedge = "AncientFl", NeedleRamp = "AncientFl",
		NeedleBase = "AncientDk", RuinBlock = "AncientDk", Boulder = "AncientDk",
	},
}
local ANCIENT = { Sanctum = true, D_GrandBridge = true, B_GrandChamber = true, A_OuterValley = true }

local count = 0
local function style(p, s)
	p.Color = s[1]
	p.Material = s[2]
	p.MaterialVariant = s[3] or ""
	if s[2] == M.Glass then
		p.Transparency = 0.55
		p.Reflectance = 0.12
	end
	if s[2] == M.Neon then
		p.CastShadow = false
	end
end
D.style = style

function D.dp(parent, name, size, cf, s, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	style(p, s)
	if size.X * size.Y * size.Z < 40 then
		p.CastShadow = false
	end
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.Parent = parent
	count += 1
	if count % 250 == 0 then
		task.wait()
	end
	return p
end
function D.sp(parent, name, size, cf, s, props)
	local p = D.dp(parent, name, size, cf, s, props)
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = true
	return p
end
local dp = D.dp

local function skinFor(area, name)
	local t = SKIN[area]
	if not t then
		return nil
	end
	if t[name] then
		return S[t[name]]
	end
	for k, v in t do
		if k:sub(-1) == "*" and name:sub(1, #k - 1) == k:sub(1, -2) then
			return S[v]
		end
	end
	return S[t._]
end

local function upright(cf)
	return cf.UpVector.Y > 0.999
end

local function column(p, out, ancient)
	local s = p.Size
	local hy = s.Y / 2
	local base, top = p.CFrame * CF(0, -hy, 0), p.CFrame * CF(0, hy, 0)
	local dk, md = (ancient and S.AncientDk or S.SteelDk), (ancient and S.Ancient or S.Steel)
	dp(out, "Plinth", V(s.X + 3, 3, s.Z + 3), base * CF(0, 1.5, 0), dk)
	dp(out, "Plinth", V(s.X + 1.6, 2, s.Z + 1.6), base * CF(0, 4, 0), md)
	dp(out, "Cap", V(s.X + 2.4, 2.4, s.Z + 2.4), top * CF(0, -1.2, 0), dk)
	dp(out, "Cap", V(s.X + 1.2, 1.2, s.Z + 1.2), top * CF(0, -3, 0), md)
	local gh = s.Y - 14
	if gh > 6 then
		for _, f in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local w = (if f[1] ~= 0 then s.Z else s.X) * 0.3
			local off = CF(f[1] * (s.X / 2 + 0.1), 0, f[2] * (s.Z / 2 + 0.1))
			local size = if f[1] ~= 0 then V(0.3, gh, w) else V(w, gh, 0.3)
			dp(out, "Groove", size, p.CFrame * off, S.Black)
			if ancient and f[1] ~= 0 then
				dp(out, "Seam", V(0.36, gh * 0.55, 0.32), p.CFrame * CF(f[1] * (s.X / 2 + 0.12), gh * 0.1, 0), S.EnergyDim)
			end
		end
		local nb = math.floor(s.Y / 32)
		for b = 1, nb - 1 do
			dp(out, "Band", V(s.X + 0.8, 1.4, s.Z + 0.8), base * CF(0, b * s.Y / nb, 0), dk)
		end
	end
end

local function wallRibs(p, out, ancient)
	local s = p.Size
	local thinX = s.X < s.Z
	local t, L = (if thinX then s.X else s.Z), (if thinX then s.Z else s.X)
	local hy = s.Y / 2
	local dk, md = (ancient and S.AncientDk or S.SteelDk), (ancient and S.Ancient or S.Steel)
	local function at(u, y, n)
		return p.CFrame * (if thinX then CF(n, y, u) else CF(u, y, n))
	end
	local function sz(across, h, along)
		return if thinX then V(across, h, along) else V(along, h, across)
	end
	dp(out, "Coping", sz(t + 1.2, 1.4, L + 0.6), at(0, hy - 0.5, 0), dk)
	if s.Y > 6 then
		dp(out, "Kick", sz(t + 0.8, 1.6, L), at(0, -hy + 0.8, 0), dk)
	end
	if s.Y >= 8 and L >= 10 then
		local spacing = if ancient then 14 else 11
		local n = math.max(1, math.floor(L / spacing))
		for i = 0, n do
			local u = -L / 2 + 1 + (L - 2) * i / n
			for _, side in { -1, 1 } do
				dp(out, "Rib", sz(1, s.Y - 3, 1.6), at(u, -0.2, side * (t / 2 + 0.5)), md)
			end
		end
		if not ancient then
			for _, side in { -1, 1 } do
				dp(out, "Seam", sz(0.3, 0.35, L), at(0, s.Y * 0.18, side * (t / 2 + 0.15)), S.Black)
				dp(out, "Seam", sz(0.3, 0.35, L), at(0, -s.Y * 0.18, side * (t / 2 + 0.15)), S.Black)
			end
		elseif s.Y > 14 then
			for _, side in { -1, 1 } do
				dp(out, "Inlay", sz(0.32, 0.3, L * 0.8), at(0, hy - 3, side * (t / 2 + 0.16)), S.EnergyDim)
			end
		end
	end
end

local function slabTrim(p, out, ancient, elevated)
	local s = p.Size
	local hy = s.Y / 2
	local longX = s.X >= s.Z
	local W, L = (if longX then s.Z else s.X), (if longX then s.X else s.Z)
	local function at(u, y, n)
		return p.CFrame * (if longX then CF(u, y, n) else CF(n, y, u))
	end
	local function sz(across, h, along)
		return if longX then V(along, h, across) else V(across, h, along)
	end
	local dk = ancient and S.AncientDk or S.SteelDk
	local fh = math.max(s.Y, 1.6)
	dp(out, "Fascia", sz(W + 0.5, fh, L + 0.5), at(0, hy - fh / 2 - 0.02, 0), dk)
	if elevated then
		for _, side in { -1, 1 } do
			dp(out, "Underglow", sz(0.35, 0.35, L - 1), at(0, hy - fh - 0.2, side * (W / 2 - 0.4)), ancient and S.EnergyDim or S.Lamp)
		end
		local n = math.max(1, math.floor(L / 16))
		for i = 0, n do
			local u = -L / 2 + 1 + (L - 2) * i / n
			dp(out, "Joist", sz(W - 1, 1.6, 1.4), at(u, hy - fh - 0.8, 0), dk)
		end
	end
end

local function roofKit(p, out)
	local s = p.Size
	local top = p.CFrame * CF(0, s.Y / 2, 0)
	for _, e in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local size = if e[1] ~= 0 then V(1.2, 2.6, s.Z + 1.2) else V(s.X + 1.2, 2.6, 1.2)
		dp(out, "Parapet", size, top * CF(e[1] * s.X / 2, 1.3, e[2] * s.Z / 2), S.SteelDk)
	end
	local units = math.clamp(math.floor(s.X * s.Z / 1400), 1, 6)
	for _ = 1, units do
		local ux, uz = rng:NextNumber(-0.38, 0.38) * s.X, rng:NextNumber(-0.38, 0.38) * s.Z
		local w, d, h = rng:NextNumber(6, 11), rng:NextNumber(5, 9), rng:NextNumber(3, 5)
		local u = dp(out, "RoofUnit", V(w, h, d), top * CF(ux, h / 2, uz), S.Steel)
		u.CanCollide = true
		dp(out, "RoofVent", V(w * 0.7, 0.4, d * 0.7), top * CF(ux, h + 0.2, uz), S.Black)
		dp(out, "FanHousing", V(0.6, 3.2, 3.2), top * CF(ux, h + 0.5, uz) * CFrame.Angles(0, 0, math.rad(90)), S.SteelDk, { Shape = Enum.PartType.Cylinder })
	end
	local alongX = s.X >= s.Z
	local L = (if alongX then s.X else s.Z) - 6
	local off = (if alongX then s.Z else s.X) / 2 - 3
	local cf = top * (if alongX then CF(0, 1.4, off) else CF(off, 1.4, 0)) * (if alongX then CFrame.identity else CFrame.Angles(0, math.rad(90), 0))
	dp(out, "Pipe", V(L, 1.4, 1.4), cf, S.Rust, { Shape = Enum.PartType.Cylinder })
	dp(out, "Pipe", V(L, 1, 1), cf * CF(0, 0, -2), S.SteelDk, { Shape = Enum.PartType.Cylinder })
end

local function lightUp(p, warm)
	if p:FindFirstChildOfClass("SurfaceLight") then
		return
	end
	local l = Instance.new("SurfaceLight")
	l.Face = Enum.NormalId.Bottom
	l.Range = 20
	l.Angle = 110
	l.Brightness = 1.6
	l.Color = if warm then C3(255, 226, 190) else C3(205, 225, 255)
	l.Shadows = false
	l.Parent = p
end

local function isElevated(p)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { p }
	local bottom = p.Position - V(0, p.Size.Y / 2 + 0.05, 0)
	return workspace:Raycast(bottom, V(0, -4, 0), params) == nil
end

function D.Skin(areaName)
	local area = workspace.Map_Eclipse:FindFirstChild(areaName)
	local out = area:FindFirstChild("Detail")
	if out then
		out:Destroy()
	end
	out = Instance.new("Folder")
	out.Name = "Detail"
	out.Parent = area
	local ancient = ANCIENT[areaName] == true
	local parts = {}
	for _, d in area:GetDescendants() do
		if d:IsA("BasePart") and not d:IsDescendantOf(out) and not (area:FindFirstChild("Hero") and d:IsDescendantOf(area.Hero)) then
			table.insert(parts, d)
		end
	end
	local stats = { column = 0, wall = 0, slab = 0, roof = 0, lights = 0 }
	for _, p in parts do
		local st = skinFor(areaName, p.Name)
		if st and not (p.Material == M.Neon and st[2] ~= M.Neon) then
			style(p, st)
		end
		if p.Name == "Light" then
			p.Material = M.Neon
			p.Color = S.Lamp[1]
			lightUp(p, not ancient)
			stats.lights += 1
			continue
		end
		if p.Material == M.Neon or p.Transparency > 0.5 or not upright(p.CFrame) then
			continue
		end
		local s = p.Size
		if not (p:IsA("Part") and p.Shape == Enum.PartType.Block) then
			continue
		end
		if s.Y >= 20 and s.Y >= 2.2 * math.max(s.X, s.Z) and math.max(s.X, s.Z) <= 20 and math.min(s.X, s.Z) >= 3 then
			column(p, out, ancient)
			stats.column += 1
		elseif math.min(s.X, s.Z) <= 6 and s.Y >= 3 and math.max(s.X, s.Z) >= 8 then
			wallRibs(p, out, ancient)
			stats.wall += 1
		elseif p.Name == "Roof" and not ancient then
			roofKit(p, out)
			stats.roof += 1
		elseif s.Y <= 4.5 and math.min(s.X, s.Z) >= 5 and math.max(s.X, s.Z) >= 10 then
			slabTrim(p, out, ancient, isElevated(p))
			stats.slab += 1
		end
	end
	return stats
end

return D
