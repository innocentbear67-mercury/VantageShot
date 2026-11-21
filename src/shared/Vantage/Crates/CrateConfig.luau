--[[
	VANTAGE — CrateConfig (shared): supply crates sold for REQ (2026-11-16).
	Every crate draws from the same pool: every Rare+ skin of every gun (Skins.List, rarity on Skins.Ladder).
	Crates differ by price and odds only. The roll happens on the server (CrateService); clients only animate.
	Art: PNGs from the design canvas, uploaded from ~/roblox-game/vantage_vfx/crates.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Skins = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Weapons"):WaitForChild("Skins"))

local C = {}
local rgb = Color3.fromRGB
local function id(n) return "rbxassetid://" .. n end

C.Tiers = { "Rare", "Epic", "Mythic", "Legendary", "Exclusive", "Godly" }
C.TierIndex = {}
for i, t in C.Tiers do C.TierIndex[t] = i end
C.Refund = { Rare = 75, Epic = 150, Mythic = 400, Legendary = 900, Exclusive = 1500, Godly = 3000 }
C.TierColor = { Rare = rgb(17, 107, 255), Epic = rgb(149, 79, 255), Mythic = rgb(206, 218, 238), Legendary = rgb(255, 190, 40), Exclusive = rgb(236, 72, 255), Godly = rgb(255, 190, 60) }

C.Images = {
	Skins = { id(105679128329972), id(101872127440174), id(83645321658699), id(133278671059055), id(128203937615194), id(122377652445031) },
	Banner = { h0 = id(85047520292396), h38 = id(88155407875761), gold = id(96760817383597), h120 = id(125393382810359), h200 = id(137108733838147), h280 = id(103098997597300) },
	Open = { h0 = id(73649845271213), red = id(75767972886160), gold = id(101751407252217), pink = id(104922563051909), h200 = id(99251068610893), h280 = id(115671491424224) },
	Rays = id(117813539668416),
	-- board-rendered featured guns (glow baked in, hidden parts cut): 2 atlases of 2x4 cells, 512x256
	Guns = { id(87012395787980), id(71898316224695) },
	Backdrop = id(118119181361296),
	CtaGold = id(96291702304413),
	CtaCyan = id(96473807856870),
}
C.GunCells = {
	["Sentinel/AbyssalLeviathan"] = { 0, 0 }, ["Sentinel/CelestialAstrolabe"] = { 0, 1 }, ["Sentinel/LiquidCobalt"] = { 0, 2 }, ["Sentinel/PhoenixAscendant"] = { 0, 3 },
	["Sentinel/StormHerald"] = { 0, 4 }, ["Vanguard/DragonEmperor"] = { 0, 5 }, ["Vanguard/EventHorizon"] = { 0, 6 }, ["Vanguard/GlacierOps"] = { 0, 7 },
	["Vanguard/Kitsune"] = { 1, 0 }, ["Vanguard/MoltenSovereign"] = { 1, 1 }, ["Vanguard/PlasmaFlux"] = { 1, 2 },
}
function C.Gun(key)
	local cell = C.GunCells[key]
	if not cell then return nil end
	local n = cell[2]
	return { Image = C.Images.Guns[cell[1] + 1], Offset = Vector2.new((n % 2) * 512, (n // 2) * 256), Size = Vector2.new(512, 256) }
end
-- x5 opens: 10% off, rounded to 50
function C.Price(crate, count)
	if count == 5 then
		return math.floor(crate.Price * 5 * 0.9 / 50 + 0.5) * 50
	end
	return crate.Price
end
-- open-screen background tint per rarity (Godly cycles all of them)
C.OpenByTier = { Rare = "h0", Epic = "h0", Mythic = "red", Legendary = "gold", Exclusive = "pink", Godly = "cycle" }
C.Cycle = { "h0", "red", "gold", "pink", "h200", "h280" }

C.Crates = {
	{ Id = "Field", Name = "Field Crate", Tag = "Starter", Price = 975, Pity = 80, PityTier = "Legendary",
		Odds = { Rare = 30, Epic = 66, Mythic = 3, Legendary = 0.8, Exclusive = 0.15, Godly = 0.05 },
		Color = rgb(22, 200, 255), Light = rgb(157, 250, 255), Dark = rgb(22, 72, 224), Banner = { "h0" },
		Grad = { rgb(138, 248, 255), rgb(31, 180, 255), rgb(47, 91, 255), rgb(58, 44, 200) },
		Art = { Full = id(104588601194703), Lid = id(86239856596837), Body = id(127359988362138) },
		Top = { "Vanguard/PlasmaFlux", "Sentinel/LiquidCobalt", "Vanguard/GlacierOps", "Vanguard/DarkMatter" } },
	{ Id = "Strike", Name = "Strike Crate", Tag = "Better odds", Price = 1950, Pity = 40, PityTier = "Legendary",
		Odds = { Rare = 15, Epic = 70, Mythic = 9, Legendary = 4, Exclusive = 1.5, Godly = 0.5 },
		Color = rgb(149, 79, 255), Light = rgb(227, 209, 255), Dark = rgb(74, 31, 176), Banner = { "h38" },
		Grad = { rgb(236, 220, 255), rgb(176, 122, 255), rgb(122, 60, 255), rgb(255, 63, 210) },
		Art = { Full = id(105753640822114), Lid = id(128238071794943), Body = id(100653160048210) },
		Top = { "Vanguard/MoltenSovereign", "Sentinel/AbyssalLeviathan", "Sentinel/StormHerald", "Vanguard/Archangel" } },
	{ Id = "Prestige", Name = "Prestige Crate", Tag = "Legendary+ boosted", Price = 4875, Pity = 15, PityTier = "Legendary",
		Odds = { Epic = 66, Mythic = 18, Legendary = 10, Exclusive = 4.5, Godly = 1.5 },
		Color = rgb(255, 176, 46), Light = rgb(255, 243, 196), Dark = rgb(196, 106, 0), Banner = { "gold" },
		Grad = { rgb(255, 246, 192), rgb(255, 200, 58), rgb(255, 138, 26), rgb(224, 69, 15) },
		Art = { Full = id(119048172520485), Lid = id(137857849802579), Body = id(137837463967412) },
		Top = { "Vanguard/EventHorizon", "Sentinel/CelestialAstrolabe", "Vanguard/MoltenSovereign", "Sentinel/AbyssalLeviathan" } },
	{ Id = "Apex", Name = "Apex Crate", Tag = "Mythic+ guaranteed", Price = 11250, Pity = 25, PityTier = "Godly",
		Odds = { Mythic = 55, Legendary = 28, Exclusive = 12, Godly = 5 },
		Color = rgb(236, 72, 255), Light = rgb(255, 209, 244), Dark = rgb(122, 28, 208), Banner = { "h0", "h120", "h200", "h280", "gold", "h38" }, Rainbow = true,
		Grad = { rgb(255, 243, 176), rgb(255, 122, 216), rgb(162, 75, 255), rgb(79, 168, 255) },
		Art = { Full = id(112249450372316), Lid = id(116912336036550), Body = id(102815312609705) },
		Top = { "Vanguard/DragonEmperor", "Sentinel/PhoenixAscendant", "Vanguard/Kitsune", "Sentinel/SakuraRonin" } },
}
C.ById = {}
for _, c in C.Crates do C.ById[c.Id] = c end

-- skin preview atlases: 1024x1024 sheets, 4x4 cells of 256
C.Cells = {
	["Breacher/AnodizedTitanium"] = { 2, 3 }, ["Breacher/HardlightPlating"] = { 1, 14 }, ["Breacher/Mainframe"] = { 2, 4 }, ["Breacher/PlasmaConduit"] = { 2, 0 }, ["Breacher/PowerCells"] = { 2, 2 }, ["Breacher/QuantumLattice"] = { 2, 1 }, ["Breacher/ReactorCore"] = { 1, 15 }, ["Breacher/Shockwave"] = { 2, 7 }, ["Breacher/ThermiteBurn"] = { 2, 5 }, ["Breacher/TreadPlate"] = { 2, 6 },
	["Knife/Blueprint"] = { 3, 3 }, ["Knife/CipherBlock"] = { 3, 8 }, ["Knife/DieShot"] = { 3, 9 }, ["Knife/FiberOptic"] = { 3, 5 }, ["Knife/Holofoil"] = { 3, 6 }, ["Knife/LiquidChrome"] = { 3, 4 }, ["Knife/Magnetar"] = { 3, 7 }, ["Knife/NeonFade"] = { 3, 2 }, ["Knife/SatelliteFoil"] = { 3, 10 }, ["Knife/Tesseract"] = { 3, 11 },
	["Longshot/DataCascade"] = { 2, 10 }, ["Longshot/Faceted"] = { 3, 1 }, ["Longshot/ForerunnerGlyph"] = { 2, 8 }, ["Longshot/GravityWell"] = { 2, 12 }, ["Longshot/HullBreach"] = { 2, 14 }, ["Longshot/NaniteSwarm"] = { 2, 13 }, ["Longshot/StarChart"] = { 2, 15 }, ["Longshot/TargetingArray"] = { 2, 11 }, ["Longshot/ThermalSight"] = { 3, 0 }, ["Longshot/Waveform"] = { 2, 9 },
	["Sentinel/AbyssalLeviathan"] = { 4, 3 }, ["Sentinel/AuroraVeil"] = { 0, 12 }, ["Sentinel/CelestialAstrolabe"] = { 4, 4 }, ["Sentinel/CrimsonDamascus"] = { 0, 14 }, ["Sentinel/HexBulwark"] = { 0, 11 }, ["Sentinel/Kintsugi"] = { 1, 1 }, ["Sentinel/LiquidCobalt"] = { 1, 3 }, ["Sentinel/ObsidianMagma"] = { 0, 10 }, ["Sentinel/PhoenixAscendant"] = { 4, 6 }, ["Sentinel/PrismShard"] = { 1, 0 }, ["Sentinel/RidgelineTopo"] = { 0, 13 }, ["Sentinel/SakuraRonin"] = { 4, 5 }, ["Sentinel/SimGrid"] = { 1, 2 }, ["Sentinel/StormHerald"] = { 4, 2 }, ["Sentinel/ToxicBloom"] = { 0, 15 },
	["Spectre/AbyssGlow"] = { 1, 7 }, ["Spectre/PlagueDoctor"] = { 5, 0 }, ["Spectre/FrostFenrir"] = { 5, 1 }, ["Spectre/AnubisEternal"] = { 5, 2 }, ["Spectre/Calavera"] = { 5, 3 }, ["Spectre/WraithKing"] = { 5, 4 }, ["Breacher/IroncladSteamworks"] = { 5, 5 }, ["Breacher/BrazenMinotaur"] = { 5, 6 }, ["Breacher/GorgonsGaze"] = { 5, 7 }, ["Breacher/KrampusYule"] = { 5, 8 }, ["Breacher/CerberusWarden"] = { 5, 9 }, ["Longshot/StrixNightwatch"] = { 5, 10 }, ["Longshot/SabretoothPrimeval"] = { 5, 11 }, ["Longshot/JaguarSunWarrior"] = { 5, 12 }, ["Longshot/WatcherBeyond"] = { 5, 13 }, ["Longshot/HeartbreakerValentine"] = { 5, 14 }, ["Spectre/BloodMoon"] = { 1, 6 }, ["Spectre/DeadChannel"] = { 1, 8 }, ["Spectre/Hyperspace"] = { 1, 10 }, ["Spectre/IonStorm"] = { 1, 5 }, ["Spectre/Opal"] = { 1, 11 }, ["Spectre/RustRuin"] = { 1, 12 }, ["Spectre/SpectralSmoke"] = { 1, 13 }, ["Spectre/SplinterCamo"] = { 1, 9 }, ["Spectre/VenomScale"] = { 1, 4 },
	["Vanguard/AmberCore"] = { 0, 0 }, ["Vanguard/Archangel"] = { 3, 13 }, ["Vanguard/CarbonOps"] = { 0, 1 }, ["Vanguard/CircuitLattice"] = { 0, 7 }, ["Vanguard/CryoFracture"] = { 0, 5 }, ["Vanguard/DarkMatter"] = { 0, 9 }, ["Vanguard/DragonEmperor"] = { 4, 1 }, ["Vanguard/EventHorizon"] = { 3, 15 }, ["Vanguard/GhostCamo"] = { 0, 6 }, ["Vanguard/GlacierOps"] = { 3, 12 }, ["Vanguard/Kitsune"] = { 4, 0 }, ["Vanguard/MoltenSovereign"] = { 3, 14 }, ["Vanguard/PlasmaFlux"] = { 0, 8 }, ["Vanguard/PulsarStorm"] = { 0, 3 }, ["Vanguard/SignalCorrupt"] = { 0, 4 }, ["Vanguard/ViridianNebula"] = { 0, 2 },
}
-- 2026-11-17: hero shells on the newer guns preview as the skin itself (the shell's own texture),
-- the same look as every other skin; sheet 6 had whole-gun photos for these. New hero skins: add the
-- shell ColorMap here (SkinKitMeshes/<Kit>_<Weapon> -> SurfaceAppearance.ColorMap).
C.Swatches = {
	["Spectre/PlagueDoctor"] = 123003619159010, ["Spectre/FrostFenrir"] = 88005365291278, ["Spectre/AnubisEternal"] = 111836895958524,
	["Spectre/Calavera"] = 84609299999963, ["Spectre/WraithKing"] = 93684237055831,
	["Breacher/IroncladSteamworks"] = 105637317532356, ["Breacher/BrazenMinotaur"] = 128102539818176, ["Breacher/GorgonsGaze"] = 103970090821096,
	["Breacher/KrampusYule"] = 91159826120130, ["Breacher/CerberusWarden"] = 82852224936635,
	["Longshot/StrixNightwatch"] = 113763814429382, ["Longshot/SabretoothPrimeval"] = 130580410395187, ["Longshot/JaguarSunWarrior"] = 90378826032053,
	["Longshot/HeartbreakerValentine"] = 80418574723575, ["Longshot/WatcherBeyond"] = 81773720257329, ["Bulwark/RhinoJuggernaut"] = 85821955760470, ["Bulwark/RiotWarden"] = 92716193771763, ["Bulwark/JackOLantern"] = 132604461102872, ["Bulwark/BehemothWorldBreaker"] = 96786267735169, ["Bulwark/OniWarlord"] = 78021100301625, ["Riptide/HammerheadApex"] = 104862289328570, ["Riptide/AbyssDiver"] = 82538061677857, ["Riptide/SunsetSurf"] = 80663783424466, ["Riptide/KrakenLord"] = 115711618215943, ["Riptide/TidecallerAtlantis"] = 123698226552739, ["Verdict/StarMarshal"] = 131942627548176, ["Verdict/DeathstalkerScorpion"] = 129213536874511, ["Verdict/ScalesOfJudgement"] = 113512583733872, ["Verdict/MidnightCountdown"] = 136056522363085, ["Verdict/SovereignLion"] = 89478881409523, ["Quill/ReconTracker"] = 122714784001980, ["Helix/ContainmentBreach"] = 83370899487466, ["Helix/IronhornRam"] = 93858414832406, ["Helix/GenesisHelix"] = 78360348502667, ["Helix/MasqueradeCarnival"] = 127830451818730, ["Helix/StormTitan"] = 129609186012589, ["Quill/RaptorRampage"] = 127028002432326, ["Quill/CelestialStag"] = 99955567233753,
}
function C.Preview(key)
	local sw = C.Swatches[key]
	if sw then
		return { Image = "rbxassetid://" .. sw, Offset = Vector2.zero, Size = Vector2.zero }
	end
	local cell = C.Cells[key]
	if not cell then return nil end
	local n = cell[2]
	return { Image = C.Images.Skins[cell[1] + 1], Offset = Vector2.new((n % 4) * 256, (n // 4) * 256), Size = Vector2.new(256, 256) }
end

-- 2026-11-18: wave-1 gun patterns preview as their own seamless swatch image (crate-system.md: swatches, never gun photos)
C.Swatches = C.Swatches or {}
for k, v in { ["Riptide/Overclock"] = 98110247930317, ["Riptide/VectorStrike"] = 85957459848586, ["Riptide/ArcWeld"] = 90125308360278, ["Riptide/KillSwitch"] = 100971563050173, ["Riptide/NeonGridRun"] = 128216599779129, ["Riptide/StaticBurst"] = 70885405622702, ["Riptide/CoolantLeak"] = 100424502126887, ["Riptide/Nanoweave"] = 120969434123396, ["Riptide/Redline"] = 80184647333444, ["Riptide/PulseDrive"] = 95967278456901,
	["Bulwark/SiegePlate"] = 126671555571994, ["Bulwark/BastionGrid"] = 88543429370468, ["Bulwark/ForgeHeat"] = 112542054826678, ["Bulwark/Dreadnought"] = 98879545136745, ["Bulwark/UrbanDigital"] = 112513101575273, ["Bulwark/AmmoBelt"] = 70861984135364, ["Bulwark/ReactorShield"] = 104598509974359, ["Bulwark/BlackOps"] = 126468093412975, ["Bulwark/FusionCoils"] = 87417551656933, ["Bulwark/TacticalOverlay"] = 84493296908768,
	["Verdict/GavelGold"] = 115482047832592, ["Verdict/NoirCity"] = 115601363179929, ["Verdict/SheriffChrome"] = 139154107419037, ["Verdict/ArtDeco"] = 82254512833679, ["Verdict/JudgementDay"] = 106766148825637, ["Verdict/DesertAlloy"] = 104599642874122, ["Verdict/Executioner"] = 122248794069823, ["Verdict/VelvetVault"] = 102443025097407, ["Verdict/SpectralLedger"] = 113354149197631, ["Verdict/SilverBullet"] = 106820301310677,
	["Quill/ShadowRail"] = 102457481790897, ["Quill/CloakField"] = 101792872126511, ["Quill/HardlightFletch"] = 133647177151898, ["Quill/SonarSweep"] = 114079802379715, ["Quill/GhostProtocol"] = 127051462320075, ["Quill/LaserMesh"] = 82495268266113, ["Quill/MidnightTrace"] = 77451598811218, ["Quill/ArcticStalker"] = 125271032291787, ["Quill/ToxinCoil"] = 131088986002522, ["Quill/MoonlitSteel"] = 87588031877117,
	["Helix/TorsionCode"] = 118182926681100, ["Helix/ParticleCollider"] = 103168097033398, ["Helix/Interference"] = 71565900512525, ["Helix/TeslaField"] = 111657489763616, ["Helix/Superconductor"] = 102538592594145, ["Helix/FusionPlasma"] = 83593151063788, ["Helix/PhotonWeave"] = 98162286132834, ["Helix/Spectrum"] = 127641739505683, ["Helix/CleanRoom"] = 74378930134891, ["Helix/Antimatter"] = 89784345435263,
	["Havoc/Demolition"] = 103710763181701, ["Havoc/Detonator"] = 117503327647522, ["Havoc/ScorchedEarth"] = 97868214728590, ["Havoc/Payload"] = 138014045650539, ["Havoc/Shrapnel"] = 96718399143230, ["Havoc/PopBlast"] = 75468734342817, ["Havoc/Thermobaric"] = 103861341210477, ["Havoc/Minefield"] = 103416867478490, ["Havoc/BunkerBuster"] = 135234014615242, ["Havoc/NuclearWinter"] = 124946243703495 } do
	C.Swatches[k] = v
end

-- the pool: every Rare+ skin of every gun, grouped by rarity ({ Weapon, Skin, Rarity, Name, Key })
local pool = nil

-- 2026-11-16: Gemini crate renders (cut out) replace the crate art everywhere Art.Full is used
local ArtV2 = { Field = "rbxassetid://121393172224433", Strike = "rbxassetid://122054061901913", Prestige = "rbxassetid://71665155085423", Apex = "rbxassetid://99928873799837" }
for _, c in C.Crates do
	if ArtV2[c.Id] then
		c.Art.FullOld = c.Art.Full
		c.Art.Full = ArtV2[c.Id]
	end
end

-- 2026-11-17: EQUIPMENT CRATES (Shield Packs + Grappling Hooks, EquipmentCatalog; starters are never in them).
-- Kept OUT of C.Crates so the crate store only lists them once its UI handles equipment results; the server
-- buys / opens them by id like any crate (C.ById). A crate with Pool = "Equipment" rolls C.Pool(crate).
-- Equipment results: { Kind = "Equipment", Slot, Id, Name, Rarity, Key = "Equipment/<Id>",
--   Weapon = "Equipment", Skin = <Id> } (Weapon/Skin only so older code that joins them never errors).
local EquipCatalog = require(game:GetService("ReplicatedStorage").Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
C.EquipmentCrates = {
	{ Id = "Equipment", Name = "Equipment Crate", Tag = "Packs + hooks", Price = 2500, Pity = 30, PityTier = "Legendary", Pool = "Equipment", Base = "Prestige",
		Odds = { Epic = 62, Mythic = 25, Legendary = 9, Exclusive = 3, Godly = 1 },
		Top = { "Equipment/Singularity", "Equipment/Starfall", "Equipment/PulsarCore", "Equipment/Lotus" } },
	{ Id = "EliteEquipment", Name = "Elite Equipment Crate", Tag = "Mythic+ guaranteed", Price = 6000, Pity = 12, PityTier = "Exclusive", Pool = "Equipment", Base = "Apex",
		Odds = { Mythic = 55, Legendary = 30, Exclusive = 10, Godly = 5 },
		Top = { "Equipment/Singularity", "Equipment/Starfall", "Equipment/PulsarCore", "Equipment/Lotus" } },
}
for _, c in C.EquipmentCrates do
	for k, v in C.ById[c.Base] or {} do -- colours / art from a skin crate until equipment crate art exists
		if c[k] == nil then
			c[k] = v
		end
	end
	C.ById[c.Id] = c
end

-- equipment crate art (user's Gemini crates, cut out 2026-11-17); other Art fields fall back to the base crate
for id, full in { Equipment = "rbxassetid://84822399344478", EliteEquipment = "rbxassetid://81393987619097" } do
	local c = C.ById[id]
	if c then
		c.Art = setmetatable({ Full = full, FullOld = full }, { __index = C.ById[c.Base] and C.ById[c.Base].Art or {} })
	end
end

local equipPool = nil
function C.EquipmentPool()
	if equipPool then return equipPool end
	equipPool = { All = {}, ByTier = {} }
	for _, t in C.Tiers do equipPool.ByTier[t] = {} end
	for _, it in EquipCatalog.Items do
		if not it.Starter and C.TierIndex[it.Rarity] then
			local e = { Kind = "Equipment", Slot = it.Slot, Id = it.Id, Weapon = "Equipment", Skin = it.Id, Rarity = it.Rarity, Name = it.Name, Key = "Equipment/" .. it.Id }
			table.insert(equipPool.All, e)
			table.insert(equipPool.ByTier[it.Rarity], e)
		end
	end
	return equipPool
end
-- C.Pool() / C.Count(tier) are the skin pool as before; pass the crate to get its own pool
function C.Count(tier, crate)
	return #(C.Pool(crate).ByTier[tier] or {})
end

-- 2026-11-17: ARSENAL CRATES (gun unlocks, bought with Ordnance / ORD; user decision).
-- Every gun except the Vanguard comes from here (WeaponUnlocks Source = "Crate"). A roll only picks guns the
-- player doesn't own yet (no duplicates) and unlocks it straight away; each locked gun has an equal chance.
-- Odds below are recomputed from the gun list so the Rates panel stays honest (weight = guns in that tier).
-- Results: { Kind = "Weapon", Weapon = <gunId>, Skin = Skins.Default, Id = <gunId>, Name, Rarity, Key = "Weapon/<gunId>" }.
local Unlocks = require(game:GetService("ReplicatedStorage").Vantage:WaitForChild("Weapons"):WaitForChild("WeaponUnlocks"))
C.WeaponCrates = {
	{ Id = "Arsenal", Name = "Arsenal Crate", Tag = "Unlocks a new gun", Price = 200, Currency = "ORD", Pool = "Weapon", Base = "Strike",
		Pity = 1, PityTier = "Rare", Odds = {}, Top = {} },
}
local weaponPool = nil
function C.WeaponPool()
	if weaponPool then return weaponPool end
	weaponPool = { All = {}, ByTier = {} }
	for _, t in C.Tiers do weaponPool.ByTier[t] = {} end
	for _, w in Unlocks.CrateWeapons() do
		local tier = if C.TierIndex[w.Rarity or ""] then w.Rarity else "Rare"
		local e = { Kind = "Weapon", Weapon = w.Id, Skin = Skins.Default, Id = w.Id, Name = w.Name, Rarity = tier, Class = w.Class, Key = "Weapon/" .. w.Id }
		table.insert(weaponPool.All, e)
		table.insert(weaponPool.ByTier[tier], e)
	end
	return weaponPool
end
for _, c in C.WeaponCrates do
	for k, v in C.ById[c.Base] or {} do -- colours / art from a skin crate until Arsenal crate art exists
		if c[k] == nil then
			c[k] = v
		end
	end
	for _, t in C.Tiers do
		local n = #C.WeaponPool().ByTier[t]
		c.Odds[t] = if n > 0 then n else nil
	end
	for _, e in C.WeaponPool().All do
		table.insert(c.Top, e.Key)
	end
	C.ById[c.Id] = c
end
-- Arsenal art (user's Gemini renders, cut out 2026-11-17; files ~/roblox-game/vantage_vfx/ord/*_v1.png)
do
	local a = C.ById.Arsenal
	if a then
		a.Art = { Full = id(78455072315351), FullOld = id(78455072315351), Lid = id(126883632075914), Body = id(89067762156477), Mask = id(90480483578210) }
		a.Color, a.Light, a.Dark = rgb(255, 150, 40), rgb(255, 222, 150), rgb(170, 70, 8)
		a.Grad = { rgb(255, 236, 170), rgb(255, 176, 60), rgb(240, 110, 20), rgb(150, 50, 10) }
		a.Banner = { "gold" }
	end
end
function C.IsWeaponCrate(crate)
	return type(crate) == "table" and crate.Pool == "Weapon"
end
-- which currency a crate costs: "ORD" for Arsenal crates, "REQ" for everything else
function C.Currency(crate)
	return if type(crate) == "table" and crate.Currency then crate.Currency else "REQ"
end
function C.Pool(crate)
	if type(crate) == "table" and crate.Pool == "Weapon" then
		return C.WeaponPool()
	end
	if type(crate) == "table" and crate.Pool == "Equipment" then
		return C.EquipmentPool()
	end
	if pool then return pool end
	pool = { All = {}, ByTier = {} }
	for _, t in C.Tiers do pool.ByTier[t] = {} end
	for _, w in Skins.Weapons do
		for _, s in Skins.List(w) do
			if C.TierIndex[s.Rarity] then
				local e = { Weapon = w, Skin = s.Id, Rarity = s.Rarity, Name = s.Name, Key = w .. "/" .. s.Id }
				table.insert(pool.All, e)
				table.insert(pool.ByTier[s.Rarity], e)
			end
		end
	end
	return pool
end

return C
