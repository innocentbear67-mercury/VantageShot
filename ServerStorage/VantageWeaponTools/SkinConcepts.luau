-- VANTAGE — skin concept builders (preview only; run against Workspace._SkinShowcase)
local F = require(game.ServerStorage.VantageWeaponTools.SkinForge:Clone())
local rgb, MAT = F.rgb, Enum.Material
local B = F.Kit.Bevel
local C = {}

local function blade(g, comp, name, cf, L, h, t, tipBack, tipFront, style)
	-- tapered blade along local Z; tipBack/tipFront = length of the taper at each end (0 = square)
	local cuts = {}
	if tipBack and tipBack > 0 then table.insert(cuts, F.Kit.CutYZ(h/2, L/2 - tipBack, -h/2, L/2, h/2, L/2)) end
	if tipFront and tipFront > 0 then table.insert(cuts, F.Kit.CutYZ(-h/2, -L/2 + tipFront, h/2, -L/2, -h/2, -L/2)) end
	return F.Block(g, comp, {Name = name, Role = "Armor", Size = Vector3.new(t, h, L), CFrame = cf, Bevel = B.S, Axes = "z", Cuts = cuts}, style)
end
C.blade = blade

function C.Mythic_Seraph(st, slotCF)
	local PEARL = {Color = rgb(250,246,238), Material = MAT.SmoothPlastic, Reflectance = 0.02}
	local GOLD = {Color = rgb(255,196,84), Material = MAT.Metal, Reflectance = 0.2}
	local ROYAL = {Color = rgb(26,34,74), Material = MAT.Metal}
	local AZ = {Color = rgb(120,214,255), Material = MAT.Neon}
	local DARK = {Color = rgb(10,12,30), Material = MAT.SmoothPlastic}
	local g = F.CloneGun(st, "Vanguard", "Mythic_SeraphAscendant", slotCF)
	F.Paint(g, {Armor = PEARL, Frame = ROYAL, Metal = GOLD, Grip = ROYAL, Dark = DARK, Accent = GOLD, Glow = AZ,
		Glass = {Color = rgb(255,226,150), Material = MAT.Glass, Transparency = 0.7}})
	F.PaintParts(g, {{"Magazine","Base"},{"Optic","Brow"},{"Barrel","BrakeCap"},{"Stock","Cheek"},{"Grip","Backstrap"},{"Handguard","NoseRing"},
		{"Barrel","Band1"},{"Barrel","Band2"},{"Stock","Clamp"},{"Receiver","MagWellLip"},{"Grip","Cap"},{"Handguard","Jaw"}}, GOLD)
	-- gold edge trims
	for _, sx in {-1, 1} do
		F.Part(g,"Receiver","TrimHoodF",Vector3.new(0.014,0.018,0.58),CFrame.new(sx*0.149,0.335,-0.42),GOLD)
		F.Part(g,"Receiver","TrimHoodR",Vector3.new(0.014,0.018,0.60),CFrame.new(sx*0.149,0.31,0.18),GOLD)
		F.Part(g,"Receiver","TrimSideLo",Vector3.new(0.012,0.016,0.70),CFrame.new(sx*0.148,-0.2,-0.19),GOLD)
		F.Part(g,"Handguard","TrimTop",Vector3.new(0.012,0.016,1.08),CFrame.new(sx*0.139,0.21,-1.30),GOLD)
		F.Part(g,"Handguard","TrimSkirt",Vector3.new(0.012,0.014,0.98),CFrame.new(sx*0.148,-0.11,-1.29),GOLD)
		F.Part(g,"Stock","TrimSpine",Vector3.new(0.012,0.016,1.02),CFrame.new(sx*0.087,0.225,1.10),GOLD)
		F.Part(g,"Stock","TrimButt",Vector3.new(0.012,0.6,0.016),CFrame.new(sx*0.097,-0.15,1.53),GOLD)
	end
	-- raked gold sashes
	local rake = math.atan(0.5)
	for _, z in {-0.66, -0.14} do
		F.Block(g,"Receiver",{Name="Sash",Role="Metal",Size=Vector3.new(0.305,0.24,0.035),CFrame=CFrame.new(0,0.26,z)*CFrame.Angles(-rake,0,0),Bevel=B.S},GOLD)
	end
	-- winged gem emblem on each receiver flank
	for _, sx in {-1, 1} do
		local c = Vector3.new(sx*0.15, -0.1, -0.02)
		F.Part(g,"Receiver","GemBezel",Vector3.new(0.02,0.15,0.15),CFrame.new(c)*CFrame.Angles(math.rad(45),0,0),GOLD)
		F.Part(g,"Receiver","Gem",Vector3.new(0.03,0.095,0.095),CFrame.new(c+Vector3.new(sx*0.008,0,0))*CFrame.Angles(math.rad(45),0,0),AZ)
	end
	-- STOCK WING: fanned feather spread rising from the stock clamp
	local fe = {{50,0.40},{38,0.54},{26,0.66},{14,0.76},{2,0.84}}
	for _, sx in {-1, 1} do
		for i, f in fe do
			local e, L, h = math.rad(f[1]), f[2], 0.085
			local sty = (i % 2 == 1) and PEARL or GOLD
			local root = Vector3.new(sx*(0.105+0.011*i), 0.2 - 0.012*i, 0.56)
			local dir = Vector3.new(0, math.sin(e), math.cos(e))
			local cf = CFrame.new(root + dir*(L/2 + 0.02)) * CFrame.Angles(-e, 0, 0)
			blade(g,"Stock","Feather"..i,cf,L,h,0.016,0.13,0,sty)
			if sty == PEARL then
				F.Part(g,"Stock","FeatherEdge"..i,Vector3.new(0.02,0.012,L-0.16),cf*CFrame.new(sx*0.002,h/2-0.007,-0.07),GOLD)
				F.Part(g,"Stock","FeatherVein"..i,Vector3.new(0.02,0.006,L*0.45),cf*CFrame.new(sx*0.003,-0.012,-L*0.18),AZ)
			end
		end
		F.Block(g,"Stock",{Name="WingRoot",Role="Metal",Size=Vector3.new(0.03,0.12,0.12),CFrame=CFrame.new(sx*0.115,0.2,0.58)*CFrame.Angles(math.rad(45),0,0),Bevel=B.S},GOLD)
		F.Part(g,"Stock","WingRootGem",Vector3.new(0.02,0.05,0.05),CFrame.new(sx*0.132,0.2,0.58)*CFrame.Angles(math.rad(45),0,0),AZ)
	end
	-- UNDER-BARREL SERAPH BLADE
	F.Block(g,"Handguard",{Name="StrutA",Role="Metal",Size=Vector3.new(0.05,0.06,0.06),CFrame=CFrame.new(0,-0.13,-1.15),Bevel=B.S},GOLD)
	F.Block(g,"Handguard",{Name="StrutB",Role="Metal",Size=Vector3.new(0.05,0.06,0.06),CFrame=CFrame.new(0,-0.13,-1.62),Bevel=B.S},GOLD)
	blade(g,"Handguard","SeraphBlade",CFrame.new(0,-0.2,-1.48),1.02,0.13,0.05,0.16,0.42,PEARL)
	blade(g,"Handguard","SeraphKeel",CFrame.new(0,-0.262,-1.44),0.86,0.035,0.056,0.12,0.3,GOLD)
	for _, sx in {-1,1} do
		F.Part(g,"Handguard","BladeCore",Vector3.new(0.006,0.014,0.62),CFrame.new(sx*0.026,-0.185,-1.42),AZ)
	end
	-- HALO: floating rings around the barrel
	local ax = CFrame.Angles(0, math.rad(90), 0)
	F.Ring(g,"Barrel","HaloGold",0.5,0.43,0.03,CFrame.new(0,0.11,-2.3)*ax,GOLD)
	F.Ring(g,"Barrel","HaloAzure",0.4,0.36,0.024,CFrame.new(0,0.11,-2.3)*ax,AZ)
	F.Ring(g,"Barrel","HaloGoldS",0.3,0.25,0.025,CFrame.new(0,0.11,-2.12)*ax,GOLD)
	-- muzzle crown
	for k = 0, 3 do
		local r = math.rad(45 + 90*k)
		local cf = CFrame.new(0,0.11,-2.8)*CFrame.Angles(0,0,r)*CFrame.new(0,0.1,0)*CFrame.Angles(math.rad(-14),0,0)
		F.Block(g,"Barrel",{Name="Crown"..k,Role="Metal",Size=Vector3.new(0.022,0.05,0.3),CFrame=cf,Bevel=B.S,Axes="z",Cuts={F.Kit.CutYZ(0.025,-0.05,-0.025,-0.15,0.025,-0.15)}},GOLD)
	end
	-- magazine: gold edge, azure core window
	for _, sx in {-1,1} do
		F.Part(g,"Magazine","MagEdge",Vector3.new(0.012,0.44,0.014),CFrame.new(sx*0.086,-0.74,-0.2)*CFrame.Angles(math.rad(-6),0,0),GOLD)
		F.Part(g,"Magazine","MagGemBezel",Vector3.new(0.02,0.08,0.08),CFrame.new(sx*0.088,-0.6,-0.3)*CFrame.Angles(math.rad(45),0,0),GOLD)
		F.Part(g,"Magazine","MagGem",Vector3.new(0.03,0.05,0.05),CFrame.new(sx*0.094,-0.6,-0.3)*CFrame.Angles(math.rad(45),0,0),AZ)
	end
	-- celestial motes
	local box = F.Part(g,"Receiver","MoteField",Vector3.new(0.7,1.7,4.8),CFrame.new(0,-0.05,-0.5),{Transparency=1,Material=MAT.SmoothPlastic})
	F.Emitter(box,{Name="GoldMotes",Texture="rbxasset://textures/particles/sparkles_main.dds",Color=ColorSequence.new(rgb(255,220,140)),LightEmission=1,
		Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.3,0.09),NumberSequenceKeypoint.new(1,0)}),
		Lifetime=NumberRange.new(1.5,2.6),Rate=30,Speed=NumberRange.new(0.05,0.25),SpreadAngle=Vector2.new(180,180),Shape=Enum.ParticleEmitterShape.Box,
		ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume,Rotation=NumberRange.new(0,360),RotSpeed=NumberRange.new(-90,90),Acceleration=Vector3.new(0,0.15,0)})
	F.Emitter(box,{Name="StarMotes",Texture="rbxasset://textures/particles/sparkles_main.dds",Color=ColorSequence.new(rgb(140,215,255)),LightEmission=1,
		Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.4,0.06),NumberSequenceKeypoint.new(1,0)}),
		Lifetime=NumberRange.new(1,2),Rate=16,Speed=NumberRange.new(0.05,0.2),SpreadAngle=Vector2.new(180,180),Shape=Enum.ParticleEmitterShape.Box,
		ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume})
	g:SetAttribute("Rarity","Mythic") g:SetAttribute("Theme","Royal × Celestial")
	return g
end

function C.Legendary_Molten(st, slotCF)
	local OBS = {Color = rgb(30,26,28), Material = MAT.SmoothPlastic, Reflectance = 0.06}
	local CHAR = {Color = rgb(44,38,38), Material = MAT.Metal}
	local BRONZE = {Color = rgb(120,74,42), Material = MAT.Metal, Reflectance = 0.1}
	local LAVA = {Color = rgb(255,118,24), Material = MAT.Neon}
	local HOT = {Color = rgb(255,196,70), Material = MAT.Neon}
	local g = F.CloneGun(st, "Vanguard", "Legendary_MoltenSovereign", slotCF)
	F.Paint(g, {Armor = OBS, Frame = CHAR, Metal = BRONZE, Grip = {Color = rgb(20,18,18), Material = MAT.Fabric}, Dark = {Color = rgb(8,6,6), Material = MAT.SmoothPlastic},
		Accent = LAVA, Glow = LAVA, Glass = {Color = rgb(255,140,60), Material = MAT.Glass, Transparency = 0.7}})
	-- furnace grill: vents glow behind the fins
	F.PaintParts(g, {{"Handguard","VentL"},{"Handguard","VentR"},{"Receiver","EjectPort"},{"Magazine","WindowL"},{"Magazine","WindowR"},{"Receiver","MagWellMouth"}}, LAVA)
	F.PaintParts(g, {{"Barrel","EmitterRing"},{"Magazine","CounterL"},{"Magazine","CounterR"},{"Magazine","Round"}}, HOT)
	-- magma veins: jagged raked cracks across the side armour
	local rnd = Random.new(7)
	local function vein(comp, x, y0, z0, n, len)
		local y, z = y0, z0
		for i = 1, n do
			local ang = math.rad(rnd:NextNumber(-55, 55))
			local L = len * rnd:NextNumber(0.6, 1.1)
			local dy, dz = math.sin(ang) * L, math.cos(ang) * L
			local mid = Vector3.new(x, y + dy/2, z + dz/2)
			F.Part(g, comp, "Vein", Vector3.new(0.008, 0.011, L + 0.01), CFrame.new(mid) * CFrame.Angles(-ang, 0, 0), LAVA)
			y, z = y + dy, z + dz
		end
	end
	for _, sx in {-1, 1} do
		local x = sx * 0.147
		vein("Receiver", x, 0.32, -0.7, 5, 0.12)
		vein("Receiver", x, 0.28, -0.05, 4, 0.11)
		vein("Receiver", sx*0.145, -0.04, -0.52, 5, 0.1)
		vein("Receiver", sx*0.145, -0.16, -0.25, 4, 0.09)
		vein("Handguard", sx*0.142, 0.22, -0.8, 6, 0.1)
		vein("Handguard", sx*0.15, -0.06, -0.9, 7, 0.1)
		vein("Stock", sx*0.087, 0.2, 0.62, 6, 0.1)
		vein("Stock", sx*0.097, 0.1, 1.53, 4, 0.09)
		vein("Magazine", sx*0.086, -0.5, -0.35, 4, 0.08)
	end
	-- dorsal obsidian spine: raked blades along the top
	local spines = {{-1.62,0.16},{-1.38,0.2},{-1.14,0.17},{-0.9,0.12}}
	for i, s in spines do
		local z, h = s[1], s[2]
		local cf = CFrame.new(0, 0.29 + h/2 - 0.03, z + 0.06)
		F.Block(g, "Handguard", {Name="Spine"..i, Role="Armor", Size=Vector3.new(0.04, h, 0.22), CFrame=cf, Bevel=B.S, Axes="y",
			Cuts={F.Kit.CutYZ(h/2, -0.11, -h/2+0.03, 0.11, h/2, 0.11), F.Kit.CutYZ(h/2, -0.11, -h/2, -0.11 + 0.02, -h/2, -0.11)}}, OBS)
		F.Part(g, "Handguard", "SpineCore"..i, Vector3.new(0.046, 0.01, 0.12), cf * CFrame.new(0, -h/2 + 0.04, 0.02), LAVA)
	end
	-- side heat blades flaring off the hood rear
	for _, sx in {-1,1} do
		for k, e in {22, 6} do
			local a = math.rad(e)
			local L = 0.42 - k*0.06
			local root = Vector3.new(sx*(0.152+0.01*k), 0.2 - 0.06*k, 0.12)
			local dir = Vector3.new(0, math.sin(a), math.cos(a))
			local cf = CFrame.new(root + dir*L/2) * CFrame.Angles(-a,0,0)
			C.blade(g, "Receiver", "HeatBlade"..k, cf, L, 0.06, 0.016, 0.16, 0, OBS)
			F.Part(g, "Receiver", "HeatEdge"..k, Vector3.new(0.02, 0.008, L*0.6), cf*CFrame.new(sx*0.002, -0.022, -L*0.1), LAVA)
		end
	end
	-- flame-tongue muzzle
	for k = 0, 2 do
		local r = math.rad(120*k)
		local cf = CFrame.new(0,0.11,-2.86)*CFrame.Angles(0,0,r)*CFrame.new(0,0.085,0)*CFrame.Angles(math.rad(-18),0,0)
		C.blade(g, "Barrel", "Tongue"..k, cf, 0.3, 0.06, 0.02, 0, 0.22, OBS)
		F.Part(g, "Barrel", "TongueCore"..k, Vector3.new(0.024, 0.012, 0.16), cf*CFrame.new(0,-0.012,0.04), LAVA)
	end
	local ax = CFrame.Angles(0, math.rad(90), 0)
	F.Ring(g, "Barrel", "HeatRing1", 0.2, 0.15, 0.02, CFrame.new(0,0.11,-2.16)*ax, LAVA)
	F.Ring(g, "Barrel", "HeatRing2", 0.2, 0.15, 0.02, CFrame.new(0,0.11,-2.28)*ax, LAVA)
	-- FX
	local box = F.Part(g,"Receiver","EmberField",Vector3.new(0.4,0.8,4.2),CFrame.new(0,0.05,-0.6),{Transparency=1,Material=MAT.SmoothPlastic})
	F.Emitter(box,{Name="Embers",Texture="rbxasset://textures/particles/sparkles_main.dds",Color=ColorSequence.new(rgb(255,170,60),rgb(255,70,20)),LightEmission=1,
		Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.05),NumberSequenceKeypoint.new(1,0)}),Lifetime=NumberRange.new(0.8,1.6),Rate=40,
		Speed=NumberRange.new(0.2,0.6),SpreadAngle=Vector2.new(25,25),EmissionDirection=Enum.NormalId.Top,Acceleration=Vector3.new(0,0.6,0),
		Shape=Enum.ParticleEmitterShape.Box,ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume})
	F.Emitter(box,{Name="Flames",Texture="rbxasset://textures/particles/fire_main.dds",Color=ColorSequence.new(rgb(255,150,40),rgb(255,60,10)),LightEmission=0.9,
		Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.12),NumberSequenceKeypoint.new(1,0)}),Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(1,1)}),
		Lifetime=NumberRange.new(0.4,0.8),Rate=22,Speed=NumberRange.new(0.2,0.5),EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(10,10),
		Shape=Enum.ParticleEmitterShape.Box,ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume,Rotation=NumberRange.new(-30,30)})
	g:SetAttribute("Rarity","Legendary") g:SetAttribute("Theme","Inferno")
	return g
end

function C.Epic_Tideglass(st, slotCF)
	local TEAL = {Color = rgb(22,92,104), Material = MAT.SmoothPlastic, Reflectance = 0.03}
	local VIOLET = {Color = rgb(70,36,122), Material = MAT.Metal}
	local MINT = {Color = rgb(120,255,214), Material = MAT.Neon}
	local CRYS = {Color = rgb(170,255,240), Material = MAT.Glass, Transparency = 0.35}
	local PALE = {Color = rgb(196,244,236), Material = MAT.SmoothPlastic}
	local g = F.CloneGun(st, "Vanguard", "Epic_TideglassCircuit", slotCF)
	F.Paint(g, {Armor = TEAL, Frame = VIOLET, Metal = PALE, Grip = {Color = rgb(30,22,52), Material = MAT.Fabric}, Dark = {Color = rgb(8,16,22), Material = MAT.SmoothPlastic},
		Accent = MINT, Glow = MINT})
	F.PaintParts(g, {{"Optic","Brow"},{"Magazine","Base"},{"Barrel","BrakeCap"},{"Stock","Butt"},{"Handguard","Jaw"}}, PALE)
	-- circuit traces on the armour: L-shaped runs with node pads
	local function trace(comp, x, pts)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i+1]
			local mid = (a + b) / 2
			local d = b - a
			local sz = Vector3.new(0.006, math.max(math.abs(d.X), 0.009), math.max(math.abs(d.Y), 0.009))
			F.Part(g, comp, "Trace", Vector3.new(0.006, sz.Y, sz.Z), CFrame.new(x, mid.X, mid.Y), MINT)
		end
		local e = pts[#pts]
		F.Part(g, comp, "Node", Vector3.new(0.008, 0.024, 0.024), CFrame.new(x, e.X, e.Y), MINT)
	end
	local V2 = Vector2.new
	for _, sx in {-1,1} do
		trace("Receiver", sx*0.147, {V2(0.3,-0.72), V2(0.3,-0.5), V2(0.24,-0.5), V2(0.24,-0.3)})
		trace("Receiver", sx*0.147, {V2(0.32,0.0), V2(0.32,0.3), V2(0.27,0.3)})
		trace("Receiver", sx*0.146, {V2(-0.05,-0.5), V2(-0.05,-0.35), V2(-0.15,-0.35)})
		trace("Handguard", sx*0.149, {V2(-0.05,-1.75), V2(-0.05,-1.45), V2(-0.09,-1.45), V2(-0.09,-1.0)})
		trace("Stock", sx*0.087, {V2(0.19,0.7), V2(0.19,1.2), V2(0.13,1.2), V2(0.13,1.5)})
		-- add-on armour plate with chevron
		F.Block(g, "Handguard", {Name="AddPlate", Role="Armor", Size=Vector3.new(0.025,0.11,0.34), CFrame=CFrame.new(sx*0.155,0.11,-1.62), Bevel=B.S,
			Cuts={F.Kit.CutYZ(0.055,-0.17+0.08,-0.055,-0.17, 0.055,-0.17)}}, PALE)
		for k = 0, 2 do F.Part(g,"Handguard","Chevron",Vector3.new(0.008,0.012,0.05),CFrame.new(sx*0.168,0.11,-1.56+k*0.07)*CFrame.Angles(math.rad(35),0,0),VIOLET) end
	end
	-- crystal fin crest on the optic (Epic geometry add-on)
	C.blade(g, "Optic", "CrystalFin", CFrame.new(0,0.64,-0.2)*CFrame.Angles(math.rad(-12),0,0), 0.34, 0.09, 0.03, 0.16, 0.05, CRYS)
	F.Part(g, "Optic", "FinCore", Vector3.new(0.012,0.02,0.18), CFrame.new(0,0.63,-0.24)*CFrame.Angles(math.rad(-12),0,0), MINT)
	-- energy-cell magazine bands
	for k = 0, 2 do F.Part(g,"Magazine","CellBand",Vector3.new(0.17,0.014,0.38),CFrame.new(0,-0.56-k*0.12,-0.36-k*0.02),MINT) end
	g:SetAttribute("Rarity","Epic") g:SetAttribute("Theme","Neon Overdrive")
	return g
end

function C.Rare_Cobalt(st, slotCF)
	local COB = {Color = rgb(36,84,178), Material = MAT.Metal, Reflectance = 0.12}
	local GUN = {Color = rgb(34,36,44), Material = MAT.Metal}
	local GOLD = {Color = rgb(232,186,92), Material = MAT.Metal, Reflectance = 0.15}
	local WHITE = {Color = rgb(235,245,255), Material = MAT.Neon}
	local g = F.CloneGun(st, "Vanguard", "Rare_CobaltGilt", slotCF)
	F.Paint(g, {Armor = COB, Frame = GUN, Metal = GOLD, Accent = GOLD, Glow = WHITE})
	F.PaintParts(g, {{"Optic","Brow"},{"Barrel","BrakeCap"},{"Magazine","Base"}}, GOLD)
	-- engraved pinstripes
	for _, sx in {-1,1} do
		F.Part(g,"Receiver","Pin",Vector3.new(0.006,0.008,0.56),CFrame.new(sx*0.147,0.33,-0.42),GOLD)
		F.Part(g,"Receiver","Pin",Vector3.new(0.006,0.008,0.6),CFrame.new(sx*0.147,0.3,0.18),GOLD)
		F.Part(g,"Handguard","Pin",Vector3.new(0.006,0.008,1.0),CFrame.new(sx*0.139,0.215,-1.3),GOLD)
		F.Part(g,"Stock","Pin",Vector3.new(0.006,0.008,1.0),CFrame.new(sx*0.087,0.225,1.1),GOLD)
	end
	g:SetAttribute("Rarity","Rare") g:SetAttribute("Theme","Royal (lite)")
	return g
end

function C.Common_Sandstorm(st, slotCF)
	local g = F.CloneGun(st, "Vanguard", "Common_SandstormOps", slotCF)
	F.Paint(g, {Armor = {Color = rgb(196,170,128), Material = MAT.SmoothPlastic}, Frame = {Color = rgb(72,76,58), Material = MAT.Metal},
		Grip = {Color = rgb(58,54,44), Material = MAT.Fabric}, Glow = {Color = rgb(255,186,90), Material = MAT.Neon}, Accent = {Color = rgb(150,40,30), Material = MAT.SmoothPlastic}})
	g:SetAttribute("Rarity","Common") g:SetAttribute("Theme","Field")
	return g
end

return C
