--[[ CardArt: photographed skin cutouts packed one atlas per weapon (cards + arsenal thumbs).
	Image ids are filled in once the atlases are uploaded; a weapon with Image = nil falls back to the live 3D viewport.
	Re-shoot: the CardBooth script (see project doc lobby-gloss-ui) photographs every Skins.List entry on black + white. ]]
local CardArt = {}
local A = {
	Vanguard = { Image = "rbxassetid://98246574567715", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Carbon = 3, Cobalt = 4, Gilded = 5, GlacierOps = 6, Archangel = 7, AmberCore = 8, CarbonOps = 9, ViridianNebula = 10, PulsarStorm = 11, SignalCorrupt = 12, CryoFracture = 13, GhostCamo = 14, CircuitLattice = 15, PlasmaFlux = 16, DarkMatter = 17, MoltenSovereign = 18, EventHorizon = 19, Kitsune = 20, DragonEmperor = 21 } },
	Sentinel = { Image = "rbxassetid://123540032300219", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Carbon = 3, Cobalt = 4, Gilded = 5, StormHerald = 6, ObsidianMagma = 7, HexBulwark = 8, AuroraVeil = 9, RidgelineTopo = 10, CrimsonDamascus = 11, ToxicBloom = 12, PrismShard = 13, Kintsugi = 14, SimGrid = 15, LiquidCobalt = 16, AbyssalLeviathan = 17, CelestialAstrolabe = 18, SakuraRonin = 19, PhoenixAscendant = 20 } },
	Breacher = { Image = "rbxassetid://96601843280446", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Carbon = 3, Cobalt = 4, Gilded = 5, HardlightPlating = 6, ReactorCore = 7, PlasmaConduit = 8, QuantumLattice = 9, PowerCells = 10, AnodizedTitanium = 11, Mainframe = 12, ThermiteBurn = 13, TreadPlate = 14, Shockwave = 15, IroncladSteamworks = 16, BrazenMinotaur = 17, GorgonsGaze = 18, KrampusYule = 19, CerberusWarden = 20 } },
	Longshot = { Image = "rbxassetid://95058072244734", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Carbon = 3, Cobalt = 4, Gilded = 5, ForerunnerGlyph = 6, Waveform = 7, DataCascade = 8, TargetingArray = 9, GravityWell = 10, NaniteSwarm = 11, HullBreach = 12, StarChart = 13, ThermalSight = 14, Faceted = 15, StrixNightwatch = 16, SabretoothPrimeval = 17, JaguarSunWarrior = 18, WatcherBeyond = 19, HeartbreakerValentine = 20 } },
	Spectre = { Image = "rbxassetid://100732755839972", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Carbon = 3, Cobalt = 4, Gilded = 5, PlagueDoctor = 6, VenomScale = 7, IonStorm = 8, BloodMoon = 9, AbyssGlow = 10, DeadChannel = 11, SplinterCamo = 12, Hyperspace = 13, Opal = 14, RustRuin = 15, SpectralSmoke = 16, FrostFenrir = 17, AnubisEternal = 18, Calavera = 19, WraithKing = 20 } },
	Knife = { Image = "rbxassetid://81566012959892", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Cobalt = 3, Emberline = 4, Gilded = 5, NeonFade = 6, Blueprint = 7, LiquidChrome = 8, FiberOptic = 9, Holofoil = 10, Magnetar = 11, CipherBlock = 12, DieShot = 13, SatelliteFoil = 14, Tesseract = 15 } },
	Arc = { Image = "rbxassetid://96349430923911", CW = 256, CH = 170, Cols = 4, Skins = { Factory = 0, Graphite = 1, Whiteout = 2, Carbon = 3, Cobalt = 4, Gilded = 5, Tidebreaker = 6, Emberline = 7 } },
	Riptide = { Image = "rbxassetid://113044725729780", CW = 256, CH = 170, Cols = 4, Skins = { AbyssDiver = 0, HammerheadApex = 1, TidecallerAtlantis = 2, SunsetSurf = 3, KrakenLord = 4 } },
	Bulwark = { Image = "rbxassetid://72251274394605", CW = 256, CH = 170, Cols = 4, Skins = { RiotWarden = 0, RhinoJuggernaut = 1, OniWarlord = 2, JackOLantern = 3, BehemothWorldBreaker = 4 } },
}
CardArt.Atlas = A
function CardArt.get(weaponId, skinId)
	local a = A[weaponId]
	local i = a and a.Image and a.Skins[skinId]
	if not i then
		return nil
	end
	return { Image = a.Image, Offset = Vector2.new((i % a.Cols) * a.CW, (i // a.Cols) * a.CH), Size = Vector2.new(a.CW, a.CH) }
end
return CardArt
