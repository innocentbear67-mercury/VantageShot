--[[
	VANTAGE — BlenderIntegrate (Studio build tool, 2026-11-14)
	Turns a Blender-v2 weapon import (ServerStorage.WeaponImports_v2.<Gun>, meshes named
	<Comp>__<Role>[_n], imported at 100x and rotated 180 deg about Y) into a game weapon asset
	under ReplicatedStorage.Vantage.Weapons.Assets, keeping the asset contract:
	  Root (invisible PrimaryPart at the origin) + every old Root attachment (positions overridden
	  where the new model differs), Role-styled parts (SkinSchema "Roles"), a Real Magazine model
	  with MagGrip, MovingPart parts (several parts may share one MovingPart; MovingMain marks the
	  one whose rest drives hands / bolt pivot), welds.
	Usage: require(T.BlenderIntegrate:Clone()).Build("Vanguard")  -> backs up and replaces the asset
]]
local V = Vector3.new
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")

local GUNS = {
	-- ═══ 2026-11-18: wave-1 crate guns (Blender, from the user's concepts; new-guns-wave1.md) ═══
	Riptide = {
		Template = "Vanguard", Design = "SM-21 Riptide", Length = 3.3, MagBody = "Magazine__Frame", New = true,
		Moving = { Charge = "Charge__Armor" },
		Handle = V(0.000, -0.439, 0.380), MagGrip = V(0.000, -0.887, -0.358),
		Atts = { Muzzle = V(0.000, 0.000, -1.830), Support = V(0.000, -0.507, -1.079), SupportTP = V(0.000, -0.507, -1.079), Magazine = V(0.000, -1.462, -0.423), Shoulder = V(0.000, -0.046, 1.410), ADSPoint = V(0.000, 0.361, 0.217), EjectPoint = V(0.120, 0.089, 0.068) },
		Colors = { Dark = Color3.fromRGB(55, 58, 65), Frame = Color3.fromRGB(105, 106, 113), Armor = Color3.fromRGB(155, 155, 163), Accent = Color3.fromRGB(239, 237, 239), Glow = Color3.fromRGB(66, 156, 169) },
	},
	Bulwark = {
		Template = "Vanguard", Design = "LM-60 Bulwark", Length = 5.2, MagBody = "Magazine__Dark", New = true,
		Moving = { Barrels = "Barrels__Dark" },
		Handle = V(0.000, -0.535, 0.191), MagGrip = V(0.000, -0.954, -0.554),
		Atts = { Muzzle = V(0.000, -0.076, -3.596), Support = V(0.000, -0.458, -1.374), SupportTP = V(0.000, -0.458, -1.374), Magazine = V(0.000, -1.367, -0.554), Shoulder = V(0.000, -0.038, 1.489), ADSPoint = V(0.000, 0.916, -0.725), EjectPoint = V(0.200, -0.115, -0.229) },
		Colors = { Dark = Color3.fromRGB(54, 58, 66), Frame = Color3.fromRGB(106, 106, 114), Armor = Color3.fromRGB(134, 135, 145), Accent = Color3.fromRGB(223, 227, 236), Glow = Color3.fromRGB(96, 172, 195) },
	},
	Verdict = {
		Template = "Spectre", Design = "HC-50 Verdict", Length = 1.65, MagBody = "Magazine__Accent", New = true,
		Moving = { Cylinder = "Cylinder__Dark", Hammer = "Hammer__Dark" },
		Handle = V(0.000, -0.295, 0.325), MagGrip = V(0.000, -0.067, 0.181),
		Atts = { Muzzle = V(0.000, 0.000, -1.077), Support = V(0.000, -0.536, 0.325), SupportTP = V(0.000, -0.536, 0.325), Magazine = V(0.000, -0.067, 0.169), Shoulder = V(0.000, -0.343, 0.566), ADSPoint = V(0.000, 0.181, 0.205), EjectPoint = V(0.000, -0.067, 0.169) },
		Colors = { Dark = Color3.fromRGB(60, 62, 69), Frame = Color3.fromRGB(101, 103, 112), Armor = Color3.fromRGB(147, 149, 158), Accent = Color3.fromRGB(224, 226, 234), Glow = Color3.fromRGB(88, 174, 192) },
	},
	Quill = {
		Template = "Vanguard", Design = "XB-7 Quill", Length = 4.7, MagBody = "Magazine__Dark", New = true,
		Moving = { LimbT = "LimbT__Dark", LimbB = "LimbB__Dark" },
		Handle = V(0.000, -0.494, 0.494), MagGrip = V(0.000, 0.253, -1.111),
		Atts = { Muzzle = V(0.000, 0.253, -1.759), Support = V(0.000, -0.339, -0.926), SupportTP = V(0.000, -0.339, -0.926), Magazine = V(0.000, 0.253, -1.234), Shoulder = V(0.000, -0.154, 1.666), ADSPoint = V(0.000, 0.494, 0.339), EjectPoint = V(0.000, 0.185, -0.617) },
		Colors = { Dark = Color3.fromRGB(56, 58, 67), Frame = Color3.fromRGB(136, 133, 144), Armor = Color3.fromRGB(144, 144, 157), Accent = Color3.fromRGB(231, 232, 238), Glow = Color3.fromRGB(93, 173, 213) },
	},
	Helix = {
		Template = "Vanguard", Design = "BX-3 Helix", Length = 3.9, MagBody = "Magazine__Glass", New = true,
		Moving = { Coil = "Coil__Glow" },
		Handle = V(0.000, -0.514, 0.267), MagGrip = V(0.000, -0.128, 0.720),
		Atts = { Muzzle = V(0.000, 0.000, -2.421), Support = V(0.000, -0.435, -1.226), SupportTP = V(0.000, -0.435, -1.226), Magazine = V(0.000, -0.514, 0.720), Shoulder = V(0.000, -0.128, 1.440), ADSPoint = V(0.000, 0.472, -0.053), EjectPoint = V(0.000, 0.325, 0.720) },
		Colors = { Dark = Color3.fromRGB(53, 61, 73), Frame = Color3.fromRGB(131, 142, 161), Armor = Color3.fromRGB(144, 148, 160), Accent = Color3.fromRGB(227, 225, 225), Glow = Color3.fromRGB(88, 186, 226) },
	},
	Havoc = {
		Template = "Vanguard", Design = "GL-4 Havoc", Length = 4.0, MagBody = "Magazine__Dark", New = true,
		Moving = { Pump = "Pump__Dark" },
		Handle = V(0.000, -0.571, 0.372), MagGrip = V(0.000, -0.398, -0.744),
		Atts = { Muzzle = V(0.000, 0.000, -2.523), Support = V(0.000, -0.704, -1.766), SupportTP = V(0.000, -0.704, -1.766), Magazine = V(0.000, -0.438, -0.744), Shoulder = V(0.000, -0.146, 1.408), ADSPoint = V(0.000, 0.757, 0.120), EjectPoint = V(0.250, 0.252, -0.744) },
		Colors = { Dark = Color3.fromRGB(51, 53, 60), Frame = Color3.fromRGB(110, 114, 130), Armor = Color3.fromRGB(130, 132, 139), Accent = Color3.fromRGB(227, 228, 233), Glow = Color3.fromRGB(78, 177, 207) },
	},
	Vanguard = {
		Design = "VX-01 Vanguard", Length = 4.65, MagBody = "Magazine__Frame",
		Moving = { Charge = "Charge__Accent" },
		Handle = V(0, -0.49, 0.50), MagGrip = V(0, -0.646, -0.544),
		Atts = { ADSPoint = V(0, 0.4845, -0.30), WindowA = V(-0.085, 0.5495, -0.36), WindowB = V(0.085, 0.4195, -0.36),
			EjectPoint = V(0.12, 0.10, -0.065) },
	},
	Sentinel = {
		Design = "BR-07 Sentinel", Length = 4.25, MagBody = "Magazine__Metal",
		Moving = { Charge = "Charge__Accent" },
		Handle = V(0, -0.49, 0.50), MagGrip = V(0, -0.646, -0.544),
		-- look-through scope: the sight point sits inside the scope's bore, behind the front lens;
		-- the window is the front lens opening (ADS Sight.Kind = "Lens")
		-- open view: the eye sits just in front of the scope's front lens (scope body behind the
		-- camera); a wide window lets the chevron draw over the whole picture
		Atts = { ADSPoint = V(0, 0.465, -0.92), WindowA = V(-0.32, 0.785, -1.6), WindowB = V(0.32, 0.145, -1.6),
			Muzzle = V(0, 0.108, -2.508), EjectPoint = V(0.12, 0.10, -0.065) },
		Remove = { "LensEdge" },
	},
	Spectre = {
		Design = "PX-9 Spectre", Length = 1.25, MagBody = "Magazine__Frame",
		Moving = { Slide = "Slide__Frame" },
		MagGrip = V(0, -0.66, 0.29),
		Atts = { ADSPoint = V(0, 0.215, 0.24), EjectPoint = V(0.10, 0.12, -0.10) },
		Remove = { "WindowA", "WindowB", "LensEdge" },
	},
	Breacher = {
		Design = "SG-12 Breacher", Length = 4.25,
		Moving = { Pump = "Pump__Frame" },
		Handle = V(0, -0.269, 0.748),
		Atts = { ADSPoint = V(0, 0.456, -0.41), EjectPoint = V(0.11, 0.284, -0.12), Magazine = V(0, -0.09, -0.25),
			Support = V(0, -0.29, -1.143), SupportTP = V(0, -0.29, -0.933) },
		Remove = { "WindowA", "WindowB", "LensEdge" },
	},
	Longshot = {
		Design = "SR-88 Longshot", Length = 5.25, MagBody = "Magazine__Frame",
		Moving = { Bolt = "Bolt__Metal" },
		Atts = { ADSPoint = V(0, 0.43, 0.59), LensEdge = V(0, 0.49, 0.59), EjectPoint = V(0.10, 0.06, -0.08) },
	},
}

-- base finish (brighter than the ForgeKit palette: these meshes read too dark in first person)
local BASE = {
	Frame = Color3.fromRGB(88, 94, 104),
	Grip = Color3.fromRGB(60, 63, 71),
	Dark = Color3.fromRGB(28, 30, 35),
	Metal = Color3.fromRGB(168, 174, 184),
}

local NEWMAT = {
	Dark = Enum.Material.SmoothPlastic, Frame = Enum.Material.Metal, Armor = Enum.Material.SmoothPlastic,
	Accent = Enum.Material.SmoothPlastic, Glow = Enum.Material.Neon, Glass = Enum.Material.Glass,
	Bore = Enum.Material.SmoothPlastic, Metal = Enum.Material.Metal,
}
local NEWCOL = { Glow = Color3.fromRGB(70, 225, 255), Glass = Color3.fromRGB(150, 225, 255), Metal = Color3.fromRGB(180, 186, 196), Bore = Color3.fromRGB(10, 11, 13) }

local M = {}
M.Guns = GUNS
M.Base = BASE

local function attach(root, name, cf)
	local a = root:FindFirstChild(name) or Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = root
	return a
end

function M.Build(name: string, opts)
	opts = opts or {}
	local G = assert(GUNS[name], "unknown gun " .. name)
	local Kit = require(SS.VantageWeaponTools.ForgeKit:Clone())
	local src = assert(SS.WeaponImports_v2:FindFirstChild(name), "import missing: " .. name):Clone()
	local assets = RS.Vantage.Weapons.Assets
	local old = assets:FindFirstChild(name)
	local tmpl = old or (G.Template and assets:FindFirstChild(G.Template))

	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide, root.CanQuery, root.CanTouch, root.Massless = false, false, false, true
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local comps = {}
	local function comp(c)
		if not comps[c] then
			local f = Instance.new("Model")
			f.Name = c
			f:SetAttribute("Component", c)
			f.Parent = model
			comps[c] = f
		end
		return comps[c]
	end
	local flip = CFrame.Angles(0, math.pi, 0)
	local count = 0
	for _, p in src:GetDescendants() do
		if p:IsA("MeshPart") then
			local c, role = p.Name:match("^(.-)__(%a+)")
			assert(c and role, "bad mesh name " .. p.Name)
			local pos = p.Position
			p.Size = p.Size / 100
			p.CFrame = CFrame.new(-pos.X / 100, pos.Y / 100, -pos.Z / 100) * flip
			if G.New then
				-- 2026-11-18 guns: role colours from the concept, no ForgeKit style
				p.Color = NEWCOL[role] or (G.Colors and G.Colors[role]) or Color3.fromRGB(128, 128, 128)
				p.Material = NEWMAT[role] or Enum.Material.SmoothPlastic
				p.MaterialVariant = ""
				p.Transparency = if role == "Glass" then 0.35 else 0
				p:SetAttribute("Role", role)
			else
			Kit.Style(p, role)
			if BASE[role] then
				p.Color = BASE[role]
				-- plain finish: the gunmetal / carbon variants render near-black on these meshes
				p.MaterialVariant = ""
				if role ~= "Metal" then
					p.Material = Enum.Material.SmoothPlastic
				end
			end
			end
			p.CollisionFidelity = Enum.CollisionFidelity.Box
			p.CastShadow = not (role == "Glow" or role == "Glass")
			p.DoubleSided = false
			if G.Moving[c] then
				p:SetAttribute("MovingPart", c)
				if G.Moving[c] == p.Name then
					p:SetAttribute("MovingMain", true)
				end
			end
			p.Parent = comp(c)
			count += 1
		end
	end
	src:Destroy()

	-- attachments: every old Root attachment, then the new model's own points
	if tmpl and tmpl.PrimaryPart then
		for _, a in tmpl.PrimaryPart:GetChildren() do
			if a:IsA("Attachment") then
				attach(root, a.Name, a.CFrame)
			end
		end
	end
	for _, n in G.Remove or {} do
		local a = root:FindFirstChild(n)
		if a then
			a:Destroy()
		end
	end
	local function setPos(n, p)
		local a = root:FindFirstChild(n)
		local rot = a and a.CFrame.Rotation or CFrame.identity
		attach(root, n, CFrame.new(p) * rot)
	end
	for n, p in G.Atts do
		setPos(n, p)
	end
	if G.Handle then
		setPos("Handle", G.Handle)
	end

	-- magazine
	local mag = comps.Magazine
	local body
	if mag then
		body = mag:FindFirstChild(G.MagBody)
		mag.PrimaryPart = body
		mag:SetAttribute("Real", true)
		local om = tmpl and tmpl:FindFirstChild("Magazine")
		local og = om and om.PrimaryPart and om.PrimaryPart:FindFirstChild("MagGrip")
		local rel = og and tmpl.PrimaryPart.CFrame:ToObjectSpace(og.WorldCFrame) or CFrame.new(0, -0.6, -0.4)
		local world = if G.MagGrip then CFrame.new(G.MagGrip) * rel.Rotation else rel
		local g = Instance.new("Attachment")
		g.Name = "MagGrip"
		g.CFrame = body.CFrame:ToObjectSpace(world)
		g.Parent = body
	end

	-- welds: magazine parts to the mag body, everything else to Root
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and d ~= body then
			local w = Instance.new("WeldConstraint")
			w.Part0 = if mag and body and d:IsDescendantOf(mag) then body else root
			w.Part1 = d
			w.Parent = d
		end
	end
	model:SetAttribute("Split", true)
	model:SetAttribute("Source", "Blender")
	model:SetAttribute("ArtStyle", "Forge2")
	model:SetAttribute("ArtVersion", 5)
	model:SetAttribute("SkinSchema", "Roles")
	model:SetAttribute("Design", G.Design)
	model:SetAttribute("Length", G.Length)

	if not opts.DryRun then
		local bk = SS:FindFirstChild("_WeaponBackup_Blender_20261114") or Instance.new("Folder")
		bk.Name = "_WeaponBackup_Blender_20261114"
		bk.Parent = SS
		if old and not bk:FindFirstChild(name) then
			old.Parent = bk
		elseif old then
			old:Destroy()
		end
		model.Parent = assets
	end
	return model, count
end

return M
