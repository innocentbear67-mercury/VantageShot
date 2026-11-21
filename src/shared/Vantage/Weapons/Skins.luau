--!strict
--[[
	VANTAGE — Skins (shared)
	Cosmetic weapon skins. Pure data + one Apply() used by every place a weapon is rendered:
	server third-person model, client viewmodel, HUD icon, inventory previews.
	Cosmetic only: no stat changes anywhere.

	A skin definition:
	  Id, Name, Rarity ("Standard" | "Elite" | "Prime")
	  Kind = "Factory"   original asset look
	       | "Finish"    material finish over the original texture: Material + MaterialVariant
	                     (PBR metal / roughness from the variant), optional Color tint (only shows
	                     through texture-less parts), Accent (neon trim colour)
	       | "Solid"     texture removed: Material / MaterialVariant / Color (clean painted look)
	       | "Texture"   AI-generated design: SkinAssets/<Weapon>/<Id> is the retextured MeshPart
	                     (generate_texture re-unwraps the mesh, so the skin brings its own MeshId +
	                     TextureID). Apply hides the original mesh and welds the skin mesh in its exact
	                     place — same size and CFrame, so grips / attachments / framing are unchanged.
	       | "Pattern"   Hypershot-style mass skin: one seamless image tiled (Texture objects on all 6
                     faces) over the pattern roles (Frame / Armor, magazine kept factory). Tile in
                     studs (scaled with the model); Scroll / Pulse / Jitter animate it on clients.
  Swatch = Color3 for the inventory card stripe
	Part-built weapons (the knife) map Body / Metal / Accent colours onto their parts instead.
	Forge guns (model attribute SkinSchema = "Roles", built by VantageWeaponTools.ForgeBuilds)
	tag every part with a Role (Armor / Frame / Metal / Grip / Dark / Accent / Glow / Glass). A
	finish repaints roles through its Roles table ({ Role = { Color, Material, MaterialVariant } });
	roles it doesn't name keep the factory look. Texture skins are mesh-specific, so they are not
	offered for Forge guns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skins = {}
Skins.Default = "Factory"
Skins.Version = 1

local RARITY = {
	Standard = Color3.fromRGB(150, 172, 196),
	Elite = Color3.fromRGB(64, 222, 255),
	Prime = Color3.fromRGB(255, 186, 72),
	-- premium skin ladder (2026-11): Rare → Epic → Mythic → Legendary → Exclusive → Godly
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(176, 124, 255),
	Mythic = Color3.fromRGB(206, 218, 238), -- platinum (2026-11-17)
	Legendary = Color3.fromRGB(255, 190, 40), -- gold
	Exclusive = Color3.fromRGB(255, 61, 110),
	Godly = Color3.fromRGB(255, 232, 160),
}
Skins.Ladder = { "Rare", "Epic", "Mythic", "Legendary", "Exclusive", "Godly" }
Skins.RarityColor = RARITY

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- finishes shared by every gun (all data; MaterialVariants live in MaterialService)
local GUN_FINISHES = {
	{ Id = "Factory", Name = "Factory Issue", Rarity = "Standard", Kind = "Factory", Swatch = rgb(70, 78, 92) },
	{ Id = "Graphite", Name = "Graphite", Rarity = "Standard", Kind = "Solid", Material = Enum.Material.Metal, MaterialVariant = "VantageGraphite", Color = rgb(52, 56, 64), Swatch = rgb(52, 56, 64),
		Roles = { Armor = { Color = rgb(70, 75, 84), Material = Enum.Material.Metal, MaterialVariant = "VS_Gunmetal" }, Frame = { Color = rgb(28, 30, 35) } } },
	{ Id = "Whiteout", Name = "Whiteout", Rarity = "Standard", Kind = "Solid", Material = Enum.Material.SmoothPlastic, MaterialVariant = "VantageCeramic", Color = rgb(226, 232, 238), Swatch = rgb(226, 232, 238),
		Roles = { Armor = { Color = rgb(240, 243, 247) }, Frame = { Color = rgb(168, 176, 188), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" }, Grip = { Color = rgb(120, 128, 140) } } },
	{ Id = "Carbon", Name = "Carbon Weave", Rarity = "Elite", Kind = "Solid", Material = Enum.Material.Fabric, MaterialVariant = "VantageCarbon", Color = rgb(40, 42, 48), Swatch = rgb(30, 32, 38),
		Roles = { Armor = { Color = rgb(44, 46, 52), Material = Enum.Material.Fabric, MaterialVariant = "VantageCarbon" }, Glow = { Color = rgb(255, 140, 60) }, Accent = { Color = rgb(64, 222, 255), Material = Enum.Material.Neon } } },
	{ Id = "Cobalt", Name = "Cobalt Anodized", Rarity = "Elite", Kind = "Solid", Material = Enum.Material.Foil, MaterialVariant = "VantageAnodized", Color = rgb(40, 96, 190), Swatch = rgb(40, 96, 190),
		Roles = { Armor = { Color = rgb(40, 96, 190), Material = Enum.Material.Foil, MaterialVariant = "VantageAnodized" }, Frame = { Color = rgb(24, 28, 40) }, Glow = { Color = rgb(150, 205, 255) } } },
	{ Id = "Gilded", Name = "Gilded", Rarity = "Prime", Kind = "Solid", Material = Enum.Material.Foil, MaterialVariant = "VantageGilded", Color = rgb(222, 172, 74), Swatch = rgb(222, 172, 74),
		Roles = { Armor = { Color = rgb(222, 172, 74), Material = Enum.Material.Foil, MaterialVariant = "VantageGilded" }, Frame = { Color = rgb(30, 28, 26) }, Metal = { Color = rgb(240, 200, 120), Material = Enum.Material.Foil, MaterialVariant = "VantageGilded" }, Glow = { Color = rgb(255, 214, 140) } } },
}

-- Premium ladder skins, per gun. Until each design's sculpted kit is built these are palette
-- stand-ins on the Forge roles; FX = SkinFX id (flash / tracer / impact / idle aura).
local G, F = Enum.Material.Foil, "VantageGilded"
local PREMIUM = {
	Vanguard = {
		{ Id = "GlacierOps", Name = "Glacier Ops", Rarity = "Rare", Kind = "Solid", FX = "Glacier", Kit = "Glacier", Swatch = rgb(150, 210, 245),
			Material = Enum.Material.SmoothPlastic, Color = rgb(226, 236, 246),
			-- frost-white ceramic body, glacier-blue anodised panels + grip, brushed silver hardware
			Roles = { Frame = { Color = rgb(236, 242, 248), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" },
				Armor = { Color = rgb(60, 118, 184), Material = Enum.Material.Metal, MaterialVariant = "" },
				Grip = { Color = rgb(54, 108, 172), Material = Enum.Material.Metal, MaterialVariant = "" },
				Metal = { Color = rgb(196, 204, 216), Material = Enum.Material.Metal, MaterialVariant = "VantageGraphite" },
				Dark = { Color = rgb(24, 34, 52), Material = Enum.Material.Metal, MaterialVariant = "VantageGraphite" },
				Accent = { Color = rgb(170, 225, 255), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" },
				Glow = { Color = rgb(150, 228, 255) }, Glass = { Color = rgb(170, 220, 245) } } },
		{ Id = "Archangel", Name = "Archangel", Rarity = "Epic", Kind = "Solid", FX = "Archangel", Kit = "Archangel", Swatch = rgb(255, 214, 140),
			Material = Enum.Material.SmoothPlastic, Color = rgb(248, 246, 240),
			-- pearl body, royal-navy grip + recesses, gilded hardware; wing / plates / halo / crown come from the kit
			Roles = { Frame = { Color = rgb(250, 248, 243), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" },
				Armor = { Color = rgb(240, 192, 98), Material = G, MaterialVariant = F },
				Grip = { Color = rgb(30, 38, 84), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" },
				Metal = { Color = rgb(236, 190, 96), Material = G, MaterialVariant = F },
				Dark = { Color = rgb(24, 30, 66), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" },
				Accent = { Color = rgb(255, 204, 110), Material = G, MaterialVariant = F },
				Glow = { Color = rgb(70, 160, 255) }, Glass = { Color = rgb(255, 226, 160) } } },
		{ Id = "MoltenSovereign", Name = "Molten Sovereign", Rarity = "Mythic", Kind = "Solid", FX = "Molten", Kit = "Molten", Swatch = rgb(255, 90, 20),
			Material = Enum.Material.SmoothPlastic, Color = rgb(16, 13, 14),
			Roles = { Armor = { Color = rgb(18, 14, 15), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" }, Frame = { Color = rgb(36, 30, 30) },
				Metal = { Color = rgb(150, 92, 46), Material = Enum.Material.Metal, MaterialVariant = "" }, Accent = { Color = rgb(255, 90, 10), Material = Enum.Material.Neon },
				Grip = { Color = rgb(22, 18, 18) }, Glow = { Color = rgb(255, 100, 20) } } },
		{ Id = "EventHorizon", Name = "Event Horizon", Rarity = "Legendary", Kind = "Solid", FX = "Horizon", Kit = "Horizon", Swatch = rgb(200, 70, 255),
			Material = Enum.Material.SmoothPlastic, Color = rgb(12, 10, 18),
			Roles = { Armor = { Color = rgb(14, 11, 20), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" }, Frame = { Color = rgb(40, 24, 70) },
				Metal = { Color = rgb(138, 84, 230), Material = Enum.Material.Foil, MaterialVariant = "" }, Accent = { Color = rgb(150, 60, 255), Material = Enum.Material.Neon },
				Grip = { Color = rgb(20, 14, 30) }, Glow = { Color = rgb(230, 40, 200) } } },
		{ Id = "Kitsune", Name = "Kitsune // Lunar Festival", Rarity = "Exclusive", Kind = "Solid", FX = "Kitsune", Kit = "Kitsune", Swatch = rgb(255, 61, 110),
			Material = Enum.Material.SmoothPlastic, Color = rgb(246, 244, 240),
			Roles = { Armor = { Color = rgb(248, 246, 242), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" }, Frame = { Color = rgb(120, 8, 24) },
				Metal = { Color = rgb(232, 186, 92), Material = G, MaterialVariant = F }, Accent = { Color = rgb(200, 20, 40) },
				Grip = { Color = rgb(30, 24, 26) }, Glow = { Color = rgb(60, 190, 255) } } },
		{ Id = "DragonEmperor", Name = "Golden Dragon Emperor", Rarity = "Godly", Kind = "Solid", FX = "Dragon", Kit = "Dragon", Swatch = rgb(255, 196, 80),
			Material = Enum.Material.SmoothPlastic, Color = rgb(110, 8, 16),
			Roles = { Armor = { Color = rgb(120, 10, 18), Material = Enum.Material.SmoothPlastic, MaterialVariant = "" }, Frame = { Color = rgb(20, 16, 16) },
				Metal = { Color = rgb(236, 180, 70), Material = G, MaterialVariant = F }, Accent = { Color = rgb(255, 200, 90), Material = G, MaterialVariant = F },
				Grip = { Color = rgb(24, 18, 18) }, Glow = { Color = rgb(255, 120, 30) } } },
	},	Sentinel = {
		{ Id = "StormHerald", Name = "Storm Herald", Rarity = "Epic", Kind = "Solid", FX = "Storm", Kit = "Storm", Swatch = rgb(70, 160, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(40, 46, 58) },
		{ Id = "AbyssalLeviathan", Name = "Abyssal Leviathan", Rarity = "Mythic", Kind = "Solid", FX = "Leviathan", Kit = "Leviathan", Swatch = rgb(30, 220, 200), Material = Enum.Material.SmoothPlastic, Color = rgb(14, 30, 48) },
		{ Id = "CelestialAstrolabe", Name = "Celestial Astrolabe", Rarity = "Legendary", Kind = "Solid", FX = "Celestial", Kit = "Celestial", Swatch = rgb(255, 214, 120), Material = Enum.Material.SmoothPlastic, Color = rgb(232, 232, 240) },
		{ Id = "SakuraRonin", Name = "Sakura Ronin // Spring Festival", Rarity = "Exclusive", Kind = "Solid", FX = "Sakura", Kit = "Sakura", Swatch = rgb(255, 110, 160), Material = Enum.Material.SmoothPlastic, Color = rgb(120, 10, 20) },
		{ Id = "PhoenixAscendant", Name = "Phoenix Ascendant", Rarity = "Godly", Kind = "Solid", FX = "Phoenix", Kit = "Phoenix", Swatch = rgb(255, 220, 140), Material = Enum.Material.SmoothPlastic, Color = rgb(240, 230, 210) },
	},
	Spectre = {
		{ Id = "PlagueDoctor", Name = "Plague Doctor", Rarity = "Epic", Kind = "Solid", FX = "Plague", Kit = "Plague", Swatch = rgb(110, 255, 50), Material = Enum.Material.SmoothPlastic, Color = rgb(30, 28, 26) },
		{ Id = "FrostFenrir", Name = "Frost Fenrir", Rarity = "Mythic", Kind = "Solid", FX = "Fenrir", Kit = "Fenrir", Swatch = rgb(130, 200, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(20, 36, 70) },
		{ Id = "AnubisEternal", Name = "Anubis Eternal", Rarity = "Legendary", Kind = "Solid", FX = "Anubis", Kit = "Anubis", Swatch = rgb(255, 200, 90), Material = Enum.Material.SmoothPlastic, Color = rgb(20, 40, 140) },
		{ Id = "Calavera", Name = "Calavera // Dia de Muertos", Rarity = "Exclusive", Kind = "Solid", FX = "Calavera", Kit = "Calavera", Swatch = rgb(255, 140, 30), Material = Enum.Material.SmoothPlastic, Color = rgb(240, 232, 220) },
		{ Id = "WraithKing", Name = "Wraith King", Rarity = "Godly", Kind = "Solid", FX = "Wraith", Kit = "Wraith", Swatch = rgb(170, 120, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(20, 18, 30) },
	},
	Breacher = {
		{ Id = "IroncladSteamworks", Name = "Ironclad Steamworks", Rarity = "Epic", Kind = "Solid", FX = "Ironclad", Kit = "Ironclad", Swatch = rgb(255, 150, 50), Material = Enum.Material.SmoothPlastic, Color = rgb(120, 70, 40) },
		{ Id = "BrazenMinotaur", Name = "Brazen Minotaur", Rarity = "Mythic", Kind = "Solid", FX = "Minotaur", Kit = "Minotaur", Swatch = rgb(255, 70, 30), Material = Enum.Material.SmoothPlastic, Color = rgb(70, 50, 40) },
		{ Id = "GorgonsGaze", Name = "Gorgon's Gaze", Rarity = "Legendary", Kind = "Solid", FX = "Gorgon", Kit = "Gorgon", Swatch = rgb(40, 230, 130), Material = Enum.Material.SmoothPlastic, Color = rgb(20, 90, 60) },
		{ Id = "KrampusYule", Name = "Krampus // Yule Night", Rarity = "Exclusive", Kind = "Solid", FX = "Krampus", Kit = "Krampus", Swatch = rgb(255, 40, 60), Material = Enum.Material.SmoothPlastic, Color = rgb(120, 15, 25) },
		{ Id = "CerberusWarden", Name = "Cerberus, Warden of Hades", Rarity = "Godly", Kind = "Solid", FX = "Cerberus", Kit = "Cerberus", Swatch = rgb(60, 150, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(18, 22, 40) },
	},
	Longshot = {
		{ Id = "StrixNightwatch", Name = "Strix Nightwatch", Rarity = "Epic", Kind = "Solid", FX = "Strix", Kit = "Strix", Swatch = rgb(110, 160, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(20, 28, 60) },
		{ Id = "SabretoothPrimeval", Name = "Sabretooth Primeval", Rarity = "Mythic", Kind = "Solid", FX = "Sabretooth", Kit = "Sabretooth", Swatch = rgb(255, 130, 30), Material = Enum.Material.SmoothPlastic, Color = rgb(22, 18, 16) },
		{ Id = "JaguarSunWarrior", Name = "Jaguar Sun Warrior", Rarity = "Legendary", Kind = "Solid", FX = "Jaguar", Kit = "Jaguar", Swatch = rgb(40, 230, 210), Material = Enum.Material.SmoothPlastic, Color = rgb(16, 18, 20) },
		{ Id = "HeartbreakerValentine", Name = "Heartbreaker // Valentine's", Rarity = "Exclusive", Kind = "Solid", FX = "Heartbreaker", Kit = "Heartbreaker", Swatch = rgb(255, 70, 150), Material = Enum.Material.SmoothPlastic, Color = rgb(120, 20, 50) },
		{ Id = "WatcherBeyond", Name = "The Watcher Beyond", Rarity = "Godly", Kind = "Solid", FX = "Watcher", Kit = "Watcher", Swatch = rgb(40, 220, 210), Material = Enum.Material.SmoothPlastic, Color = rgb(12, 14, 18) },
	},
	Riptide = {
		{ Id = "AbyssDiver", Name = "Abyss Diver", Rarity = "Epic", Kind = "Solid", FX = "Diver", Kit = "Diver", Swatch = rgb(255, 170, 60), Material = Enum.Material.SmoothPlastic, Color = rgb(40, 52, 58) },
		{ Id = "HammerheadApex", Name = "Hammerhead Apex", Rarity = "Mythic", Kind = "Solid", FX = "Hammerhead", Kit = "Hammerhead", Swatch = rgb(255, 40, 70), Material = Enum.Material.SmoothPlastic, Color = rgb(30, 30, 34) },
		{ Id = "TidecallerAtlantis", Name = "Tidecaller of Atlantis", Rarity = "Legendary", Kind = "Solid", FX = "Atlantis", Kit = "Atlantis", Swatch = rgb(40, 230, 200), Material = Enum.Material.SmoothPlastic, Color = rgb(190, 200, 205) },
		{ Id = "SunsetSurf", Name = "Sunset Surf // Summer Festival", Rarity = "Exclusive", Kind = "Solid", FX = "Sunset", Kit = "Sunset", Swatch = rgb(255, 120, 80), Material = Enum.Material.SmoothPlastic, Color = rgb(215, 220, 222) },
		{ Id = "KrakenLord", Name = "Kraken, Lord of the Abyss", Rarity = "Godly", Kind = "Solid", FX = "Kraken", Kit = "Kraken", Swatch = rgb(40, 220, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(14, 16, 20) },
	},
	Bulwark = {
		{ Id = "RiotWarden", Name = "Riot Warden", Rarity = "Epic", Kind = "Solid", FX = "Warden", Kit = "Warden", Swatch = rgb(120, 170, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(30, 36, 52) },
		{ Id = "RhinoJuggernaut", Name = "Rhino Juggernaut", Rarity = "Mythic", Kind = "Solid", FX = "Rhino", Kit = "Rhino", Swatch = rgb(220, 230, 40), Material = Enum.Material.SmoothPlastic, Color = rgb(48, 52, 36) },
		{ Id = "OniWarlord", Name = "Oni Warlord", Rarity = "Legendary", Kind = "Solid", FX = "Oni", Kit = "Oni", Swatch = rgb(170, 80, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(30, 22, 44) },
		{ Id = "JackOLantern", Name = "Jack-o'-Lantern // Halloween Night", Rarity = "Exclusive", Kind = "Solid", FX = "Lantern", Kit = "Lantern", Swatch = rgb(255, 130, 30), Material = Enum.Material.SmoothPlastic, Color = rgb(24, 22, 24) },
		{ Id = "BehemothWorldBreaker", Name = "Behemoth, World Breaker", Rarity = "Godly", Kind = "Solid", FX = "Behemoth", Kit = "Behemoth", Swatch = rgb(255, 200, 80), Material = Enum.Material.SmoothPlastic, Color = rgb(16, 15, 14) },
	},
	Verdict = {
		{ Id = "StarMarshal", Name = "Star Marshal", Rarity = "Epic", Kind = "Solid", FX = "Marshal", Kit = "Marshal", Swatch = rgb(110, 200, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(28, 32, 40) },
		{ Id = "DeathstalkerScorpion", Name = "Deathstalker Scorpion", Rarity = "Mythic", Kind = "Solid", FX = "Scorpion", Kit = "Scorpion", Swatch = rgb(255, 160, 30), Material = Enum.Material.SmoothPlastic, Color = rgb(40, 32, 26) },
		{ Id = "ScalesOfJudgement", Name = "Scales of Judgement", Rarity = "Legendary", Kind = "Solid", FX = "Justice", Kit = "Justice", Swatch = rgb(90, 130, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(24, 34, 90) },
		{ Id = "MidnightCountdown", Name = "Midnight Countdown // New Year's Eve", Rarity = "Exclusive", Kind = "Solid", FX = "Countdown", Kit = "Countdown", Swatch = rgb(255, 80, 200), Material = Enum.Material.SmoothPlastic, Color = rgb(22, 26, 60) },
		{ Id = "SovereignLion", Name = "Sovereign Lion, King's Verdict", Rarity = "Godly", Kind = "Solid", FX = "Lion", Kit = "Lion", Swatch = rgb(255, 205, 110), Material = Enum.Material.SmoothPlastic, Color = rgb(20, 16, 16) },
	},
	Quill = {
		{ Id = "ReconTracker", Name = "Recon Tracker", Rarity = "Epic", Kind = "Solid", FX = "Tracker", Kit = "Tracker", Swatch = rgb(90, 255, 140), Material = Enum.Material.SmoothPlastic, Color = rgb(30, 34, 28) },
		{ Id = "RaptorRampage", Name = "Raptor Rampage", Rarity = "Mythic", Kind = "Solid", FX = "Raptor", Kit = "Raptor", Swatch = rgb(110, 255, 70), Material = Enum.Material.SmoothPlastic, Color = rgb(40, 32, 26) },
		{ Id = "CelestialStag", Name = "Celestial Stag, Spirit of the Hunt", Rarity = "Godly", Kind = "Solid", FX = "Stag", Kit = "Stag", Swatch = rgb(70, 235, 220), Material = Enum.Material.SmoothPlastic, Color = rgb(18, 20, 24) },
	},
	Helix = {
		{ Id = "ContainmentBreach", Name = "Containment Breach", Rarity = "Epic", Kind = "Solid", FX = "Containment", Kit = "Containment", Swatch = rgb(255, 60, 220), Material = Enum.Material.SmoothPlastic, Color = rgb(30, 28, 34) },
		{ Id = "IronhornRam", Name = "Ironhorn Ram", Rarity = "Mythic", Kind = "Solid", FX = "Ram", Kit = "Ram", Swatch = rgb(40, 220, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(28, 32, 40) },
		{ Id = "GenesisHelix", Name = "Genesis Helix", Rarity = "Legendary", Kind = "Solid", FX = "Genesis", Kit = "Genesis", Swatch = rgb(255, 215, 120), Material = Enum.Material.SmoothPlastic, Color = rgb(220, 214, 200) },
		{ Id = "MasqueradeCarnival", Name = "Masquerade // Carnival Night", Rarity = "Exclusive", Kind = "Solid", FX = "Masquerade", Kit = "Masquerade", Swatch = rgb(170, 70, 255), Material = Enum.Material.SmoothPlastic, Color = rgb(34, 22, 48) },
		{ Id = "StormTitan", Name = "Storm Titan, Lord of Lightning", Rarity = "Godly", Kind = "Solid", FX = "Titan", Kit = "Titan", Swatch = rgb(255, 210, 90), Material = Enum.Material.SmoothPlastic, Color = rgb(18, 16, 16) },
	},
}

-- EPIC pattern skins (2026-11-15): one seamless 1024px image tiled over the body (Frame / Armor roles,
-- magazine stays factory). The fast, mass-produced tier. Images VS_Pattern_* (procedural, seamless;
-- generator: Claude workspace patterns/gen.py). Anim (clients only): Scroll = tiles/sec { U, V },
-- Pulse = { min brightness, Hz }, Jitter = glitch jumps. Roles here recolour the non-pattern roles.
local function pattern(id: string, name: string, img: number, fx: string, swatch: Color3, glow: Color3, extra: any?): any
	local s: any = { Id = id, Name = name, Rarity = "Epic", Kind = "Pattern", FX = fx, Swatch = swatch,
		Pattern = "rbxassetid://" .. img, Tile = 1.6, Roles = { Glow = { Color = glow }, Glass = { Color = glow } } }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end
local PATTERNS: { [string]: { any } } = {
	Vanguard = {
		pattern("AmberCore", "Amber Core", 87061353932047, "P_Amber", rgb(255, 150, 30), rgb(255, 170, 50), { Scroll = { 0.03, 0.012 }, Pulse = { 0.86, 0.5 } }),
		pattern("CarbonOps", "Carbon Ops", 128417484446530, "P_Carbon", rgb(60, 70, 86), rgb(120, 180, 255), { Tile = 1.2, Pulse = { 0.8, 0.35 } }),
		pattern("ViridianNebula", "Viridian Nebula", 97186515528805, "P_Viridian", rgb(60, 200, 120), rgb(90, 240, 150), { Tile = 2.0, Scroll = { 0.06, 0.02 } }),
		pattern("PulsarStorm", "Pulsar Storm", 78629200660555, "P_Pulsar", rgb(220, 60, 190), rgb(255, 90, 200), { Tile = 2.0, Scroll = { -0.05, 0.03 }, Pulse = { 0.85, 0.7 } }),
		pattern("SignalCorrupt", "Signal Corrupt", 107820944778493, "P_Signal", rgb(255, 80, 160), rgb(40, 230, 255), { Tile = 1.8, Jitter = true }),
		pattern("CryoFracture", "Cryo Fracture", 122169889738973, "P_Cryo", rgb(140, 210, 250), rgb(170, 230, 255), { Scroll = { 0.015, -0.01 }, Pulse = { 0.88, 0.6 } }),
		pattern("GhostCamo", "Ghost Camo", 112994848964282, "P_Camo", rgb(50, 140, 150), rgb(70, 220, 210), { Tile = 1.4, Scroll = { 0.02, 0 } }),
		pattern("CircuitLattice", "Circuit Lattice", 139130839844908, "P_Circuit", rgb(30, 200, 240), rgb(40, 220, 255), { Tile = 2.2, Scroll = { 0.04, 0 }, Pulse = { 0.7, 1.1 } }),
		pattern("PlasmaFlux", "Plasma Flux", 71034315685428, "P_Plasma", rgb(110, 100, 255), rgb(150, 120, 255), { Tile = 1.8, Scroll = { 0.14, 0.03 } }),
		pattern("DarkMatter", "Dark Matter", 71747503647036, "P_DarkMatter", rgb(120, 50, 220), rgb(190, 90, 255), { Tile = 1.8, Scroll = { 0.03, 0.05 }, Pulse = { 0.8, 0.45 } }),
	},
	-- BR-07 Sentinel (its own themes). The Sentinel has no Armor role: Frame carries the pattern.
	Sentinel = {
		pattern("ObsidianMagma", "Obsidian Magma", 85051262862488, "P_Magma", rgb(255, 90, 10), rgb(255, 110, 20), { Tile = 2.0, Pulse = { 0.7, 0.6 } }),
		pattern("HexBulwark", "Hex Bulwark", 103610241651017, "P_Hex", rgb(60, 110, 140), rgb(40, 200, 255), { Tile = 2.6, Pulse = { 0.75, 0.8 } }),
		pattern("AuroraVeil", "Aurora Veil", 106338223767027, "P_Aurora", rgb(40, 220, 150), rgb(60, 240, 170), { Tile = 2.4, Scroll = { 0.04, 0.02 } }),
		pattern("RidgelineTopo", "Ridgeline Topo", 106673639824393, "P_Topo", rgb(20, 60, 100), rgb(60, 220, 255), { Tile = 2.4, Scroll = { 0.02, 0.01 } }),
		pattern("CrimsonDamascus", "Crimson Damascus", 138375972130061, "P_Damascus", rgb(190, 20, 30), rgb(255, 40, 50), { Tile = 2.0, Scroll = { 0.01, 0 }, Pulse = { 0.85, 0.4 } }),
		pattern("ToxicBloom", "Toxic Bloom", 95702926874703, "P_Toxic", rgb(110, 230, 30), rgb(140, 255, 50), { Tile = 1.8, Scroll = { 0.01, 0.06 }, Pulse = { 0.85, 0.9 } }),
		pattern("PrismShard", "Prism Shard", 123910298980252, "P_Prism", rgb(230, 120, 240), rgb(140, 230, 255), { Tile = 2.4, Scroll = { 0.05, 0.05 } }),
		pattern("Kintsugi", "Kintsugi", 113656090428655, "P_Kintsugi", rgb(240, 225, 190), rgb(255, 200, 80), { Tile = 2.2, Pulse = { 0.9, 0.5 } }),
		pattern("SimGrid", "Sim Grid", 133658405368759, "P_SimGrid", rgb(200, 50, 220), rgb(255, 60, 210), { Tile = 2.0, Scroll = { 0, 0.12 }, Pulse = { 0.8, 1.2 } }),
		pattern("LiquidCobalt", "Liquid Cobalt", 76741200587700, "P_Cobalt", rgb(30, 80, 230), rgb(60, 130, 255), { Tile = 2.0, Scroll = { 0.08, 0.03 } }),
	},
	-- SMG-07 Spectre (its own themes). Small gun (~1.1 studs), so tighter tiles. Frame = Body + Slide.
	Spectre = {
		pattern("VenomScale", "Venom Scale", 101322869185658, "P_Venom", rgb(30, 170, 70), rgb(60, 240, 110), { Tile = 0.9, Pulse = { 0.85, 0.7 } }),
		pattern("IonStorm", "Ion Storm", 100659147278723, "P_Ion", rgb(30, 50, 130), rgb(120, 170, 255), { Tile = 1.1, Jitter = true }),
		pattern("BloodMoon", "Blood Moon", 121417870104104, "P_BloodMoon", rgb(150, 20, 24), rgb(255, 40, 40), { Tile = 1.0, Pulse = { 0.8, 0.35 } }),
		pattern("AbyssGlow", "Abyss Glow", 74866039964865, "P_Abyss", rgb(10, 90, 90), rgb(30, 240, 200), { Tile = 1.0, Scroll = { 0.03, 0.05 }, Pulse = { 0.75, 0.6 } }),
		pattern("DeadChannel", "Dead Channel", 89860477072666, "P_DeadChannel", rgb(150, 150, 160), rgb(255, 50, 80), { Tile = 1.0, Jitter = true }),
		pattern("SplinterCamo", "Splinter Camo", 124713044585625, "P_Splinter", rgb(90, 96, 106), rgb(255, 122, 26), { Tile = 1.0 , Pulse = { 0.9, 0.3 } }),
		pattern("Hyperspace", "Hyperspace", 132702882899570, "P_Hyperspace", rgb(60, 40, 160), rgb(140, 160, 255), { Tile = 1.1, Scroll = { 0.6, 0 } }),
		pattern("Opal", "Opal", 75456658867466, "P_Opal", rgb(210, 220, 240), rgb(180, 220, 255), { Tile = 1.0, Scroll = { 0.03, 0.02 }, Pulse = { 0.88, 0.5 } }),
		pattern("RustRuin", "Rust & Ruin", 105998286483261, "P_Rust", rgb(60, 110, 110), rgb(232, 120, 40), { Tile = 1.0, Pulse = { 0.9, 0.25 } }),
		pattern("SpectralSmoke", "Spectral Smoke", 75442925078929, "P_Spectral", rgb(120, 115, 170), rgb(210, 205, 255), { Tile = 1.1, Scroll = { 0.05, 0.04 } }),
	},
	-- SG Breacher (its own themes, sci-fi). ~4.3 studs long; Frame (3 parts) carries the pattern.
	Breacher = {
		pattern("HardlightPlating", "Hardlight Plating", 94001795157525, "P_Plating", rgb(70, 74, 84), rgb(255, 50, 40), { Tile = 2.2, Pulse = { 0.8, 0.7 } }),
		pattern("ReactorCore", "Reactor Core", 131089333932185, "P_Reactor", rgb(60, 44, 24), rgb(255, 170, 40), { Tile = 2.2, Pulse = { 0.75, 0.9 } }),
		pattern("PlasmaConduit", "Plasma Conduit", 130236268232323, "P_Conduit", rgb(60, 30, 100), rgb(170, 60, 255), { Tile = 2.0, Scroll = { 0.06, 0 }, Pulse = { 0.8, 0.8 } }),
		pattern("QuantumLattice", "Quantum Lattice", 117526305989530, "P_Lattice", rgb(30, 70, 56), rgb(40, 255, 160), { Tile = 2.2, Pulse = { 0.82, 0.5 } }),
		pattern("PowerCells", "Power Cells", 99957529590427, "P_Cells", rgb(30, 120, 120), rgb(30, 220, 200), { Tile = 2.0, Pulse = { 0.75, 0.6 } }),
		pattern("AnodizedTitanium", "Anodized Titanium", 116487113759166, "P_Titanium", rgb(90, 70, 190), rgb(80, 140, 255), { Tile = 2.4, Scroll = { 0.01, 0.005 } }),
		pattern("Mainframe", "Mainframe", 76323304926573, "P_Mainframe", rgb(36, 42, 56), rgb(60, 140, 255), { Tile = 2.0, Jitter = true }),
		pattern("ThermiteBurn", "Thermite Burn", 94936770744417, "P_Thermite", rgb(255, 150, 50), rgb(255, 170, 60), { Tile = 2.0, Pulse = { 0.72, 0.55 } }),
		pattern("TreadPlate", "Tread Plate", 116478787595359, "P_Tread", rgb(90, 96, 108), rgb(255, 130, 40), { Tile = 1.8, Pulse = { 0.82, 0.4 } }),
		pattern("Shockwave", "Shockwave", 128066446828479, "P_Shockwave", rgb(20, 120, 170), rgb(60, 220, 255), { Tile = 2.2, Scroll = { 0.09, 0 }, Pulse = { 0.78, 1.0 } }),
	},
	-- LR Longshot (its own themes, sci-fi). ~5.2 studs long; Frame (5 parts) carries the pattern.
	Longshot = {
		pattern("ForerunnerGlyph", "Forerunner Glyph", 107674905687031, "P_Glyph", rgb(150, 156, 166), rgb(80, 230, 255), { Tile = 2.6, Pulse = { 0.8, 0.6 } }),
		pattern("Waveform", "Waveform", 85295368501418, "P_Waveform", rgb(10, 40, 40), rgb(60, 255, 220), { Tile = 2.4, Scroll = { 0.12, 0 } }),
		pattern("DataCascade", "Data Cascade", 139671126454437, "P_Cascade", rgb(70, 36, 6), rgb(255, 170, 40), { Tile = 2.2, Scroll = { 0, -0.15 } }),
		pattern("TargetingArray", "Targeting Array", 116871282827837, "P_Targeting", rgb(44, 32, 34), rgb(255, 40, 40), { Tile = 2.6, Pulse = { 0.7, 1.2 } }),
		pattern("GravityWell", "Gravity Well", 83591769674963, "P_Gravity", rgb(70, 34, 130), rgb(170, 90, 255), { Tile = 2.6, Scroll = { 0.01, 0.01 }, Pulse = { 0.8, 0.5 } }),
		pattern("NaniteSwarm", "Nanite Swarm", 98666035490680, "P_Nanite", rgb(20, 70, 90), rgb(60, 200, 230), { Tile = 2.2, Scroll = { 0.05, 0.03 } }),
		pattern("HullBreach", "Hull Breach", 115612413074470, "P_Breach", rgb(40, 44, 52), rgb(90, 160, 255), { Tile = 2.4, Pulse = { 0.75, 0.8 } }),
		pattern("StarChart", "Star Chart", 108415343724225, "P_StarChart", rgb(20, 30, 80), rgb(255, 210, 120), { Tile = 2.6, Scroll = { 0.01, 0.004 }, Pulse = { 0.85, 0.6 } }),
		pattern("ThermalSight", "Thermal Sight", 84383390314869, "P_Thermal", rgb(240, 80, 40), rgb(255, 200, 60), { Tile = 2.4, Scroll = { 0.02, 0.03 }, Pulse = { 0.8, 0.9 } }),
		pattern("Faceted", "Faceted", 118708823459765, "P_Faceted", rgb(30, 90, 160), rgb(90, 230, 255), { Tile = 2.4, Scroll = { 0.025, 0.015 }, Pulse = { 0.85, 0.6 } }),
	},
	-- ═══ 2026-11-18: wave-1 crate guns, 10 Epic patterns each (generator: Claude workspace patterns/gen_wave1.py) ═══
	Riptide = {
		pattern("Overclock", "Overclock", 98110247930317, "P_Overclock", rgb(40, 200, 110), rgb(255, 190, 40), { Tile = 1.8, Pulse = { 0.75, 1.4 } }),
		pattern("VectorStrike", "Vector Strike", 85957459848586, "P_Vector", rgb(255, 40, 160), rgb(60, 220, 255), { Tile = 1.8, Scroll = { 0.25, 0 } }),
		pattern("ArcWeld", "Arc Weld", 90125308360278, "P_ArcWeld", rgb(70, 74, 84), rgb(120, 180, 255), { Tile = 1.8, Pulse = { 0.7, 2.2 } }),
		pattern("KillSwitch", "Kill Switch", 100971563050173, "P_KillSwitch", rgb(200, 30, 36), rgb(255, 60, 50), { Tile = 1.6, Pulse = { 0.85, 0.8 } }),
		pattern("NeonGridRun", "Neon Grid Run", 128216599779129, "P_GridRun", rgb(120, 20, 160), rgb(255, 40, 200), { Tile = 1.8, Scroll = { 0, 0.15 } }),
		pattern("StaticBurst", "Static Burst", 70885405622702, "P_Static", rgb(90, 94, 104), rgb(40, 230, 255), { Tile = 1.6, Jitter = true }),
		pattern("CoolantLeak", "Coolant Leak", 100424502126887, "P_Coolant", rgb(0, 160, 150), rgb(120, 255, 230), { Tile = 1.8, Scroll = { 0, -0.05 }, Pulse = { 0.85, 0.5 } }),
		pattern("Nanoweave", "Nanoweave", 120969434123396, "P_Nanoweave", rgb(30, 34, 40), rgb(40, 220, 210), { Tile = 1.4, Pulse = { 0.85, 0.6 } }),
		pattern("Redline", "Redline", 80184647333444, "P_Redline", rgb(255, 40, 30), rgb(255, 60, 40), { Tile = 1.8, Pulse = { 0.8, 1.6 } }),
		pattern("PulseDrive", "Pulse Drive", 95967278456901, "P_PulseDrive", rgb(20, 80, 50), rgb(60, 255, 140), { Tile = 1.8, Scroll = { 0.2, 0 } }),
	},
	Bulwark = {
		pattern("SiegePlate", "Siege Plate", 126671555571994, "P_Siege", rgb(80, 84, 92), rgb(255, 120, 30), { Tile = 2.6, Pulse = { 0.8, 0.6 } }),
		pattern("BastionGrid", "Bastion Grid", 88543429370468, "P_Bastion", rgb(40, 52, 66), rgb(60, 200, 255), { Tile = 2.2, Pulse = { 0.8, 0.7 } }),
		pattern("ForgeHeat", "Forge Heat", 112542054826678, "P_Forge", rgb(120, 50, 120), rgb(255, 170, 60), { Tile = 2.6, Scroll = { 0.01, 0.006 } }),
		pattern("Dreadnought", "Dreadnought", 98879545136745, "P_Dreadnought", rgb(22, 30, 44), rgb(255, 50, 60), { Tile = 2.6 }),
		pattern("UrbanDigital", "Urban Digital", 112513101575273, "P_UrbanDigi", rgb(120, 124, 130), rgb(230, 235, 240), { Tile = 2.4 }),
		pattern("AmmoBelt", "Ammo Belt", 70861984135364, "P_AmmoBelt", rgb(200, 150, 50), rgb(255, 190, 80), { Tile = 2.0, Scroll = { 0.08, 0 } }),
		pattern("ReactorShield", "Reactor Shield", 104598509974359, "P_ShieldHex", rgb(255, 110, 20), rgb(255, 160, 40), { Tile = 2.4, Pulse = { 0.7, 0.9 } }),
		pattern("BlackOps", "Black Ops", 126468093412975, "P_BlackOps", rgb(24, 24, 28), rgb(230, 20, 30), { Tile = 2.2, Pulse = { 0.85, 0.4 } }),
		pattern("FusionCoils", "Fusion Coils", 87417551656933, "P_FusionCoils", rgb(200, 110, 40), rgb(120, 240, 255), { Tile = 2.2, Scroll = { 0, 0.05 }, Pulse = { 0.8, 1.0 } }),
		pattern("TacticalOverlay", "Tactical Overlay", 84493296908768, "P_Tactical", rgb(52, 60, 40), rgb(170, 255, 140), { Tile = 2.4, Pulse = { 0.8, 1.2 } }),
	},
	Verdict = {
		pattern("GavelGold", "Gavel Gold", 115482047832592, "P_Gavel", rgb(230, 180, 70), rgb(255, 210, 100), { Tile = 1.0, Pulse = { 0.9, 0.4 } }),
		pattern("NoirCity", "Noir City", 115601363179929, "P_Noir", rgb(30, 30, 32), rgb(255, 236, 190), { Tile = 1.0, Pulse = { 0.88, 0.3 } }),
		pattern("SheriffChrome", "Sheriff Chrome", 139154107419037, "P_Sheriff", rgb(200, 210, 225), rgb(200, 230, 255), { Tile = 1.0, Scroll = { 0.02, 0.01 } }),
		pattern("ArtDeco", "Art Deco", 82254512833679, "P_Deco", rgb(20, 22, 26), rgb(255, 215, 120), { Tile = 0.9, Pulse = { 0.88, 0.5 } }),
		pattern("JudgementDay", "Judgement Day", 106766148825637, "P_Judgement", rgb(120, 10, 10), rgb(255, 60, 20), { Tile = 1.0, Pulse = { 0.7, 0.8 } }),
		pattern("DesertAlloy", "Desert Alloy", 104599642874122, "P_Desert", rgb(180, 156, 112), rgb(255, 180, 90), { Tile = 1.0 }),
		pattern("Executioner", "Executioner", 122248794069823, "P_Executioner", rgb(110, 8, 16), rgb(255, 40, 50), { Tile = 0.9, Pulse = { 0.85, 0.5 } }),
		pattern("VelvetVault", "Velvet Vault", 102443025097407, "P_Vault", rgb(80, 30, 96), rgb(220, 180, 255), { Tile = 1.1, Scroll = { 0.01, 0 } }),
		pattern("SpectralLedger", "Spectral Ledger", 113354149197631, "P_Ledger", rgb(14, 40, 50), rgb(140, 255, 240), { Tile = 1.0, Scroll = { 0, -0.06 } }),
		pattern("SilverBullet", "Silver Bullet", 106820301310677, "P_SilverBullet", rgb(200, 206, 218), rgb(140, 200, 255), { Tile = 1.0, Pulse = { 0.9, 0.5 } }),
	},
	Quill = {
		pattern("ShadowRail", "Shadow Rail", 102457481790897, "P_ShadowRail", rgb(30, 22, 50), rgb(150, 90, 255), { Tile = 2.2, Scroll = { 0.06, 0 } }),
		pattern("CloakField", "Cloak Field", 101792872126511, "P_Cloak", rgb(30, 60, 64), rgb(120, 255, 230), { Tile = 2.2, Scroll = { 0.02, 0.03 }, Pulse = { 0.8, 0.5 } }),
		pattern("HardlightFletch", "Hardlight Fletch", 133647177151898, "P_Fletch", rgb(14, 40, 70), rgb(60, 220, 255), { Tile = 2.0, Scroll = { 0.1, 0 } }),
		pattern("SonarSweep", "Sonar Sweep", 114079802379715, "P_Sonar", rgb(6, 40, 20), rgb(60, 255, 120), { Tile = 2.4, Pulse = { 0.75, 1.0 } }),
		pattern("GhostProtocol", "Ghost Protocol", 127051462320075, "P_Ghost", rgb(36, 38, 44), rgb(200, 215, 235), { Tile = 2.0, Jitter = true }),
		pattern("LaserMesh", "Laser Mesh", 82495268266113, "P_LaserMesh", rgb(30, 10, 12), rgb(255, 50, 50), { Tile = 2.2, Pulse = { 0.75, 1.3 } }),
		pattern("MidnightTrace", "Midnight Trace", 77451598811218, "P_Midnight", rgb(14, 22, 52), rgb(255, 210, 110), { Tile = 2.2, Pulse = { 0.85, 0.6 } }),
		pattern("ArcticStalker", "Arctic Stalker", 125271032291787, "P_Arctic", rgb(200, 215, 230), rgb(170, 230, 255), { Tile = 2.4 }),
		pattern("ToxinCoil", "Toxin Coil", 131088986002522, "P_ToxinCoil", rgb(40, 70, 20), rgb(150, 255, 40), { Tile = 2.0, Scroll = { 0.05, 0 }, Pulse = { 0.8, 0.9 } }),
		pattern("MoonlitSteel", "Moonlit Steel", 87588031877117, "P_Moonlit", rgb(100, 120, 156), rgb(200, 220, 255), { Tile = 2.4, Pulse = { 0.9, 0.3 } }),
	},
	Helix = {
		pattern("TorsionCode", "Torsion Code", 118182926681100, "P_Torsion", rgb(20, 40, 70), rgb(60, 170, 255), { Tile = 2.0, Scroll = { 0.12, 0 } }),
		pattern("ParticleCollider", "Particle Collider", 103168097033398, "P_Collider", rgb(16, 10, 28), rgb(120, 200, 255), { Tile = 2.0, Pulse = { 0.8, 0.9 } }),
		pattern("Interference", "Interference", 71565900512525, "P_Interference", rgb(150, 80, 200), rgb(120, 230, 255), { Tile = 2.2, Scroll = { 0.03, 0.02 } }),
		pattern("TeslaField", "Tesla Field", 111657489763616, "P_Tesla", rgb(40, 20, 80), rgb(170, 100, 255), { Tile = 2.0, Jitter = true }),
		pattern("Superconductor", "Superconductor", 102538592594145, "P_Supercon", rgb(200, 225, 250), rgb(60, 180, 255), { Tile = 2.0, Pulse = { 0.85, 0.7 } }),
		pattern("FusionPlasma", "Fusion Plasma", 83593151063788, "P_FusionPlasma", rgb(220, 60, 120), rgb(255, 140, 60), { Tile = 2.0, Scroll = { 0.08, 0.04 } }),
		pattern("PhotonWeave", "Photon Weave", 98162286132834, "P_Photon", rgb(20, 16, 40), rgb(255, 200, 120), { Tile = 1.8, Pulse = { 0.8, 0.8 } }),
		pattern("Spectrum", "Spectrum", 127641739505683, "P_Spectrum", rgb(255, 120, 40), rgb(255, 255, 255), { Tile = 2.4, Scroll = { 0.06, 0 } }),
		pattern("CleanRoom", "Clean Room", 74378930134891, "P_CleanRoom", rgb(225, 230, 236), rgb(40, 210, 255), { Tile = 2.2, Pulse = { 0.88, 0.5 } }),
		pattern("Antimatter", "Antimatter", 89784345435263, "P_Antimatter", rgb(70, 10, 70), rgb(255, 120, 230), { Tile = 2.0, Pulse = { 0.75, 0.8 } }),
	},
	Havoc = {
		pattern("Demolition", "Demolition", 103710763181701, "P_Demolition", rgb(250, 200, 20), rgb(255, 200, 40), { Tile = 2.2 }),
		pattern("Detonator", "Detonator", 117503327647522, "P_Detonator", rgb(30, 10, 10), rgb(255, 40, 30), { Tile = 2.0, Pulse = { 0.65, 2.0 } }),
		pattern("ScorchedEarth", "Scorched Earth", 97868214728590, "P_Scorched", rgb(40, 34, 30), rgb(255, 90, 10), { Tile = 2.2, Pulse = { 0.75, 0.7 } }),
		pattern("Payload", "Payload", 138014045650539, "P_Payload", rgb(80, 90, 54), rgb(230, 210, 130), { Tile = 2.2 }),
		pattern("Shrapnel", "Shrapnel", 96718399143230, "P_Shrapnel", rgb(110, 114, 122), rgb(255, 140, 40), { Tile = 2.0, Pulse = { 0.88, 0.5 } }),
		pattern("PopBlast", "Pop Blast", 75468734342817, "P_PopBlast", rgb(240, 40, 50), rgb(255, 210, 30), { Tile = 2.0, Pulse = { 0.85, 1.0 } }),
		pattern("Thermobaric", "Thermobaric", 103861341210477, "P_Thermobaric", rgb(40, 18, 10), rgb(255, 140, 40), { Tile = 2.2, Pulse = { 0.7, 0.9 } }),
		pattern("Minefield", "Minefield", 103416867478490, "P_Minefield", rgb(150, 130, 90), rgb(255, 40, 30), { Tile = 2.2, Pulse = { 0.7, 1.4 } }),
		pattern("BunkerBuster", "Bunker Buster", 135234014615242, "P_Bunker", rgb(130, 130, 130), rgb(255, 140, 40), { Tile = 2.2 }),
		pattern("NuclearWinter", "Nuclear Winter", 124946243703495, "P_NuclearWinter", rgb(100, 104, 112), rgb(90, 255, 220), { Tile = 2.4, Pulse = { 0.8, 0.6 } }),
	},
	-- CK-3 Edge knife (sci-fi). One mesh, no Role schema: the pattern covers the whole knife (~1.7 studs).
	Knife = {
		pattern("NeonFade", "Neon Fade", 99508296921099, "P_NeonFade", rgb(255, 60, 150), rgb(255, 80, 170), { Tile = 2.4, Scroll = { 0.05, 0 }, Pulse = { 0.88, 0.5 } }),
		pattern("Blueprint", "Blueprint", 138247018127831, "P_Blueprint", rgb(26, 64, 140), rgb(200, 225, 255), { Tile = 1.4, Scroll = { 0.01, 0.006 } }),
		pattern("LiquidChrome", "Liquid Chrome", 103986066184986, "P_Chrome", rgb(200, 210, 225), rgb(170, 210, 255), { Tile = 1.4, Scroll = { 0.03, 0.02 } }),
		pattern("FiberOptic", "Fiber Optic", 74417597214457, "P_Fiber", rgb(40, 200, 120), rgb(255, 80, 200), { Tile = 1.0, Pulse = { 0.7, 0.9 } }),
		pattern("Holofoil", "Holofoil", 73598325052355, "P_Holofoil", rgb(160, 200, 220), rgb(200, 140, 255), { Tile = 1.6, Scroll = { 0.04, 0.02 } }),
		pattern("Magnetar", "Magnetar", 130584622149737, "P_Magnetar", rgb(60, 20, 70), rgb(255, 60, 200), { Tile = 1.4, Pulse = { 0.75, 0.8 } }),
		pattern("CipherBlock", "Cipher Block", 105401144481668, "P_Cipher", rgb(30, 34, 40), rgb(40, 230, 200), { Tile = 1.0, Jitter = true }),
		pattern("DieShot", "Die Shot", 104804970321722, "P_DieShot", rgb(170, 140, 70), rgb(255, 210, 110), { Tile = 1.2, Pulse = { 0.88, 0.4 } }),
		pattern("SatelliteFoil", "Satellite Foil", 132030555278450, "P_Foil", rgb(230, 180, 60), rgb(255, 220, 120), { Tile = 1.0, Pulse = { 0.85, 0.6 } }),
		pattern("Tesseract", "Tesseract", 110347232073118, "P_Tesseract", rgb(30, 24, 60), rgb(40, 220, 255), { Tile = 1.4, Scroll = { 0.03, 0.03 }, Pulse = { 0.8, 0.7 } }),
	},
}
-- slot them in after the gun's last Rare / Epic so the ladder order holds
for weapon, list in PATTERNS do
	local prem = (PREMIUM :: any)[weapon]
	if not prem then
		(PREMIUM :: any)[weapon] = table.clone(list)
	else
		local at = 1
		for i, s in prem do
			if s.Rarity == "Rare" or s.Rarity == "Epic" then
				at = i + 1
			end
		end
		for k, s in list do
			table.insert(prem, at + k - 1, s)
		end
	end
end
Skins.PatternRoles = { Frame = true, Armor = true }

-- AI-textured designs, per gun (only listed when the asset exists, see Skins.List)
local GUN_TEXTURES = {
	{ Id = "Tidebreaker", Name = "Tidebreaker", Rarity = "Prime", Kind = "Texture", Swatch = rgb(64, 222, 255) },
	{ Id = "Emberline", Name = "Emberline", Rarity = "Elite", Kind = "Texture", Swatch = rgb(255, 120, 48) },
}

local KNIFE = {
	{ Id = "Factory", Name = "Factory Issue", Rarity = "Standard", Kind = "Factory", Swatch = rgb(70, 78, 92) },
	{ Id = "Graphite", Name = "Graphite", Rarity = "Standard", Kind = "Parts", Body = rgb(46, 50, 58), Metal = rgb(90, 96, 106), Accent = rgb(150, 160, 175), Swatch = rgb(46, 50, 58) },
	{ Id = "Whiteout", Name = "Whiteout", Rarity = "Standard", Kind = "Parts", Body = rgb(226, 232, 238), Metal = rgb(196, 204, 214), Accent = rgb(64, 222, 255), Swatch = rgb(226, 232, 238) },
	{ Id = "Cobalt", Name = "Cobalt Anodized", Rarity = "Elite", Kind = "Parts", Body = rgb(24, 32, 52), Metal = rgb(40, 96, 190), MetalMaterial = Enum.Material.Foil, Accent = rgb(110, 190, 255), Swatch = rgb(40, 96, 190) },
	{ Id = "Emberline", Name = "Emberline", Rarity = "Elite", Kind = "Parts", Body = rgb(28, 24, 24), Metal = rgb(70, 64, 62), Accent = rgb(255, 120, 48), Swatch = rgb(255, 120, 48) },
	{ Id = "Gilded", Name = "Gilded", Rarity = "Prime", Kind = "Parts", Body = rgb(30, 28, 26), Metal = rgb(222, 172, 74), MetalMaterial = Enum.Material.Foil, Accent = rgb(255, 214, 140), Swatch = rgb(222, 172, 74) },
}

-- weapon id -> asset folder name (all seven arsenal entries; only configured ones are playable)
Skins.Weapons = { "Vanguard", "Sentinel", "Spectre", "Breacher", "Longshot", "Arc", "Riptide", "Bulwark", "Verdict", "Quill", "Helix", "Havoc", "Knife" }
Skins.Category = {
	Vanguard = "Assault Rifle",
	Sentinel = "Marksman Rifle",
	Spectre = "SMG",
	Breacher = "Shotgun",
	Longshot = "Sniper",
	Arc = "Energy Rifle",
	Riptide = "SMG",
	Bulwark = "LMG",
	Verdict = "Hand Cannon",
	Quill = "Crossbow",
	Helix = "Beam Rifle",
	Havoc = "Launcher",
	Knife = "Melee",
}

local function assetsFolder(): Instance?
	local v = ReplicatedStorage:FindFirstChild("Vantage")
	local w = v and v:FindFirstChild("Weapons")
	return w and w:FindFirstChild("SkinAssets")
end

local function textureAsset(weaponId: string, skinId: string): Instance?
	local f = assetsFolder()
	local wf = f and f:FindFirstChild(weaponId)
	return wf and wf:FindFirstChild(skinId)
end

-- Forge guns (part-built, Role-tagged): see the header
local function roleSchema(weaponId: string): boolean
	local v = ReplicatedStorage:FindFirstChild("Vantage")
	local w = v and v:FindFirstChild("Weapons")
	local a = w and w:FindFirstChild("Assets")
	local m = a and a:FindFirstChild(weaponId)
	return m ~= nil and m:GetAttribute("SkinSchema") == "Roles"
end
Skins.IsRoleSchema = roleSchema

-- every skin available for a weapon (texture designs only once their asset exists)
function Skins.List(weaponId: string): { any }
	if weaponId == "Knife" then
		-- knife finishes, then its Epic patterns (PATTERNS.Knife lands in PREMIUM.Knife)
		local out = table.clone(KNIFE)
		for _, p in (PREMIUM :: any).Knife or {} do
			table.insert(out, p)
		end
		return out
	end
	local out = table.clone(GUN_FINISHES)
	for _, p in PREMIUM[weaponId] or {} do
		table.insert(out, p)
	end
	local forge = roleSchema(weaponId)
	for _, t in GUN_TEXTURES do
		if not forge and textureAsset(weaponId, t.Id) then
			table.insert(out, t)
		end
	end
	return out
end

function Skins.Get(weaponId: string, skinId: string?): any
	for _, s in Skins.List(weaponId) do
		if s.Id == skinId then
			return s
		end
	end
	return Skins.List(weaponId)[1]
end

function Skins.Valid(weaponId: string, skinId: string): boolean
	if type(weaponId) ~= "string" or type(skinId) ~= "string" or not Skins.Category[weaponId] then
		return false
	end
	for _, s in Skins.List(weaponId) do
		if s.Id == skinId then
			return true
		end
	end
	return false
end

-- ownership (2026-11-16): Standard / Elite / Prime finishes are free; Rare+ (Skins.Ladder) skins come from
-- supply crates. The server (CrateService) replicates the owned set as the player attribute OwnedSkins.
local LADDER_SET = {}
for _, r in Skins.Ladder do
	LADDER_SET[r] = true
end
function Skins.Owns(player: Player?, weaponId: string, skinId: string): boolean
	if not Skins.Valid(weaponId, skinId) then
		return false
	end
	local def = Skins.Get(weaponId, skinId)
	if not (def and LADDER_SET[def.Rarity]) or not player then
		return true
	end
	local owned = player:GetAttribute("OwnedSkins")
	if type(owned) ~= "string" then
		return true -- still loading: don't strip anything
	end
	return string.find("," .. owned .. ",", "," .. weaponId .. "/" .. skinId .. ",", 1, true) ~= nil
end

function Skins.ForPlayer(player: Player?, weaponId: string): string
	local id = player and player:GetAttribute("Skin_" .. weaponId)
	return if type(id) == "string" then id else Skins.Default
end

-- ─── apply ───────────────────────────────────────────────────────────────
local function remember(p: BasePart)
	if p:GetAttribute("SkinOrig") then
		return
	end
	p:SetAttribute("SkinOrig", true)
	p:SetAttribute("SkinOrigMat", p.Material.Name)
	p:SetAttribute("SkinOrigVar", p.MaterialVariant)
	p:SetAttribute("SkinOrigColor", p.Color)
	if p:IsA("MeshPart") then
		p:SetAttribute("SkinOrigTex", p.TextureID)
	end
end

local function restore(p: BasePart)
	if not p:GetAttribute("SkinOrig") then
		return
	end
	local hiddenT = p:GetAttribute("SkinHiddenT")
	if hiddenT ~= nil then
		p.Transparency = hiddenT :: number
		p:SetAttribute("SkinHiddenT", nil)
	end
	p.Material = (Enum.Material :: any)[p:GetAttribute("SkinOrigMat") :: string]
	p.MaterialVariant = p:GetAttribute("SkinOrigVar") :: string
	p.Color = p:GetAttribute("SkinOrigColor") :: Color3
	if p:IsA("MeshPart") then
		p.TextureID = p:GetAttribute("SkinOrigTex") :: string
	end
	for _, c in p:GetChildren() do
		if c.Name == "VantageSkinTex" then
			c:Destroy()
		end
	end
	local sa = p:FindFirstChild("VantageSkinSA")
	if sa then
		sa:Destroy()
	end
	-- original SurfaceAppearance (stashed while a skin is active) goes back on the part
	local stash = p:FindFirstChild("VantageSkinStash")
	if stash then
		for _, c in stash:GetChildren() do
			c.Parent = p
		end
		stash:Destroy()
	end
end

-- a SurfaceAppearance only renders when parented directly to the MeshPart, so park originals
local function stashOriginal(p: BasePart)
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") and c.Name ~= "VantageSkinSA" then
			local stash = p:FindFirstChild("VantageSkinStash")
			if not stash then
				stash = Instance.new("Folder")
				stash.Name = "VantageSkinStash"
				stash.Parent = p
			end
			c.Parent = stash
		end
	end
end

-- role of a part in a part-built weapon
local function role(p: BasePart): string
	if p.Material == Enum.Material.Neon or p:GetAttribute("SkinOrigMat") == "Neon" then
		return "Accent"
	end
	local m = p:GetAttribute("SkinOrigMat") or p.Material.Name
	if m == "Metal" or m == "Foil" or m == "DiamondPlate" then
		return "Metal"
	end
	return "Body"
end

-- ─── pattern skins ───
-- Every pattern Texture is tagged. One client Heartbeat loop animates them and keeps each texture's
-- visibility in step with its part (Roblox draws textures even on a Transparency = 1 part).
local RunService = game:GetService("RunService")
local TagCache = require(script.Parent.Parent:WaitForChild("TagCache"))
local PAT_TAG = "VantagePatternTex"
local patCache = setmetatable({}, { __mode = "k" })
local animOn = false
local function startPatternLoop()
	if animOn or not RunService:IsClient() or not RunService:IsRunning() then
		return
	end
	animOn = true
	local nextJump = 0
	-- 2026-11-20 perf: textures further than PAT_NEAR from the camera are left alone (a few pixels on screen),
	-- and visibility is only written when it changes
	local PAT_NEAR = 140
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local jump = now >= nextJump
		if jump then
			nextJump = now + 0.05 + math.random() * 0.25
		end
		local cam = workspace.CurrentCamera
		local cp = if cam then cam.CFrame.Position else Vector3.zero
		local set = TagCache.get(PAT_TAG)
		if #set == 0 then
			return
		end
		for _, t in set do
			local d = patCache[t]
			if not d then
				if not t:IsA("Texture") then
					continue
				end
				d = { su = t:GetAttribute("ScrollU") or 0, sv = t:GetAttribute("ScrollV") or 0, pm = t:GetAttribute("PulseMin"),
					hz = t:GetAttribute("PulseHz") or 0.5, jit = t:GetAttribute("Jitter") == true }
				patCache[t] = d
			end
			local tex = t :: Texture
			local p = tex.Parent
			if not (p and p:IsA("BasePart")) then
				continue
			end
			local tr = if p.Transparency >= 0.99 then 1 else p.Transparency
			if tex.Transparency ~= tr then tex.Transparency = tr end
			local ltm = p.LocalTransparencyModifier
			if tex.LocalTransparencyModifier ~= ltm then tex.LocalTransparencyModifier = ltm end
			if tr >= 1 or ltm >= 0.99 or (p.Position - cp).Magnitude > PAT_NEAR then
				continue
			end
			local tile = tex.StudsPerTileU
			if d.jit then
				if jump and math.random() < 0.6 then
					tex.OffsetStudsU = math.random() * tile
					tex.OffsetStudsV = math.floor(math.random() * 8) * tile / 8
					local c = 0.75 + math.random() * 0.25
					tex.Color3 = Color3.new(c, c, c)
				end
			else
				if d.su ~= 0 or d.sv ~= 0 then
					tex.OffsetStudsU = (now * d.su * tile) % tile
					tex.OffsetStudsV = (now * d.sv * tile) % tile
				end
				if d.pm then
					local c = d.pm + (1 - d.pm) * (0.5 + 0.5 * math.sin(now * d.hz * math.pi * 2))
					tex.Color3 = Color3.new(c, c, c)
				end
			end
		end
	end)
end
startPatternLoop()

local FACES = Enum.NormalId:GetEnumItems()
local function paintPattern(p: BasePart, skin: any, scale: number)
	if p:IsA("MeshPart") then
		stashOriginal(p)
		p.TextureID = ""
	end
	p.Material = Enum.Material.SmoothPlastic
	p.MaterialVariant = ""
	p.Color = skin.Tint or Color3.new(1, 1, 1)
	local tile = (skin.Tile or 1.6) * scale
	for _, f in FACES do
		local t = Instance.new("Texture")
		t.Name = "VantageSkinTex"
		t.Texture = skin.Pattern
		t.Face = f
		t.StudsPerTileU, t.StudsPerTileV = tile, tile
		if skin.Scroll then
			t:SetAttribute("ScrollU", skin.Scroll[1])
			t:SetAttribute("ScrollV", skin.Scroll[2])
		end
		if skin.Pulse then
			t:SetAttribute("PulseMin", skin.Pulse[1])
			t:SetAttribute("PulseHz", skin.Pulse[2])
		end
		if skin.Jitter then
			t:SetAttribute("Jitter", true)
		end
		t:AddTag(PAT_TAG)
		t.Parent = p
	end
end

function Skins.Apply(model: Instance, weaponId: string, skinId: string?)
	if not model then
		return
	end
	local skin = Skins.Get(weaponId, skinId)
	-- previous texture-skin meshes go first, then every visible (or skin-hidden) part
	for _, d in model:GetDescendants() do
		if d.Name == "VantageSkinMesh" then
			d:Destroy()
		end
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Transparency < 1 or d:GetAttribute("SkinHiddenT") ~= nil) then
			table.insert(parts, d)
		end
	end
	for _, p in parts do
		remember(p)
		restore(p)
	end
	model:SetAttribute("Skin", skin.Id)
	-- per-skin idle aura + the FX id WeaponEffects reads for flash / tracer / impact
	local okFX, SkinFX = pcall(require, script.Parent:FindFirstChild("SkinFX"))
	if okFX and SkinFX then
		SkinFX.AttachIdle(model, skin.FX)
	end
	if skin.Kind == "Factory" then
		return
	end
	local forge = model:GetAttribute("SkinSchema") == "Roles"
	local isPattern = skin.Kind == "Pattern" and skin.Pattern ~= nil
	local patRoles = skin.PatternRoles or Skins.PatternRoles
	local scale = if model:IsA("Model") then (model :: Model):GetScale() else 1
	for _, p in parts do
		-- (2026-11-18) was `local role`, which shadowed role() and broke the "Parts" branch below (knife finishes)
		local prole = if forge then p:GetAttribute("Role") else nil
		if prole and isPattern and patRoles[prole] and (skin.PatternMag or not p.Name:find("^Magazine")) then
			paintPattern(p, skin, scale)
		elseif prole then
			local r = skin.Roles and skin.Roles[prole]
			if r then
				if r.Color then
					p.Color = r.Color
				end
				if r.Material then
					p.Material = r.Material
					p.MaterialVariant = r.MaterialVariant or ""
				elseif r.MaterialVariant then
					p.MaterialVariant = r.MaterialVariant
				end
			end
		elseif skin.Kind == "Parts" then
			local r = role(p)
			if r == "Accent" then
				p.Color = skin.Accent
			elseif r == "Metal" then
				p.Color = skin.Metal
				if skin.MetalMaterial then
					p.Material = skin.MetalMaterial
				end
			else
				p.Color = skin.Body
			end
		elseif p:IsA("MeshPart") then
			stashOriginal(p)
			if isPattern then
				if p.Material ~= Enum.Material.Neon then
					paintPattern(p, skin, scale)
				end
			elseif skin.Kind == "Solid" then
				p.TextureID = ""
				p.Material = skin.Material
				p.MaterialVariant = skin.MaterialVariant or ""
				p.Color = skin.Color
			elseif skin.Kind == "Texture" then
				local a = textureAsset(weaponId, skin.Id)
				if a and a:IsA("MeshPart") then
					local m = a:Clone()
					m.Name = "VantageSkinMesh"
					m.Size = p.Size -- follows any ScaleTo already applied to the weapon
					m.CFrame = p.CFrame
					m.Anchored = false -- welded follower (the viewmodel re-anchors and tracks it itself)
					m.CanCollide, m.CanQuery, m.CanTouch, m.Massless = false, false, false, true
					m.CastShadow = p.CastShadow
					m.LocalTransparencyModifier = p.LocalTransparencyModifier
					for _, c in m:GetChildren() do
						if not c:IsA("SurfaceAppearance") then
							c:Destroy()
						end
					end
					local weld = Instance.new("WeldConstraint")
					weld.Part0, weld.Part1 = p, m
					weld.Parent = m
					m.Parent = p
					p:SetAttribute("SkinHiddenT", p.Transparency)
					p.Transparency = 1
				elseif a and a:IsA("SurfaceAppearance") then
					local sa = a:Clone()
					sa.Name = "VantageSkinSA"
					sa.Parent = p
				end
			end
		end
	end
	-- extra detail (decals / added geometry) for skins that have a kit
	if skin.Kit then
		local okKit, SkinKits = pcall(require, script.Parent:FindFirstChild("SkinKits"))
		if okKit and SkinKits then
			SkinKits.Build(model, weaponId, skin.Kit)
		end
	end
end

return Skins
