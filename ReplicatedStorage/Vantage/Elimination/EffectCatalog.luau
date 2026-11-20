--[[
	VANTAGE — EffectCatalog (shared)
	The 19 elimination effects (prototype v2, approved 2026-11-13). The killer's effect plays on the victim's
	body when they are eliminated (it replaces the Crimson Core Overload).
	Picker removed (user, 2026-11-17): players no longer choose an effect. Every kill plays Catalog.Default
	until top skins (Legendary / Exclusive / Godly at their top evolution level) carry their own effect,
	which will be resolved in Catalog.ForPlayer. Saved choices stay in VantageLoadout_v1 but are ignored.
	Set Catalog.PlayerChoice = true to bring the picker back.
	  • player attribute "EliminationStyle" = effect id (LoadoutService, saved in VantageLoadout_v1)
	  • Remotes.EliminationEquip(id) -> Remotes.EliminationResult(ok, id, reason)
	  • the effects themselves: StarterPlayerScripts.VantageWeaponClient.ElimFX
	Hide / Dur are the AUTHORED times (seconds); the rarity tier stretches them (Tiers below), so the
	played times are Catalog.Timing(id). All effects are free for now (Price = nil, Owns = true).
]]

local C = Color3.fromRGB

local Catalog = {}

Catalog.Default = "collapse"
Catalog.ReplaceDeath = true -- false: deaths go back to the Crimson Core Overload
Catalog.PlayerChoice = false -- 2026-11-17: elimination-effect picker removed; only the default is owned

Catalog.Rarities = {
	{ Id = "default", Name = "Default", Color = C(195, 201, 207) },
	{ Id = "rare", Name = "Rare", Color = C(76, 141, 255) },
	{ Id = "epic", Name = "Epic", Color = C(166, 107, 255) },
	{ Id = "mythic", Name = "Mythic", Color = C(255, 77, 106) },
	{ Id = "legendary", Name = "Legendary", Color = C(255, 193, 77) },
}
Catalog.RarityById = {}
for i, r in Catalog.Rarities do
	r.Rank = i - 1
	Catalog.RarityById[r.Id] = r
end

-- Kb: build-up stretch, Kr: release stretch, Amp: scale / intensity
Catalog.Tiers = {
	default = { Kb = 1.0, Kr = 1.0, Amp = 1.0, Rank = 0 },
	rare = { Kb = 1.25, Kr = 1.15, Amp = 1.15, Rank = 1 },
	epic = { Kb = 1.8, Kr = 1.35, Amp = 1.4, Rank = 2 },
	mythic = { Kb = 2.1, Kr = 1.5, Amp = 1.65, Rank = 3 },
	legendary = { Kb = 2.5, Kr = 1.7, Amp = 1.9, Rank = 4 },
}

Catalog.Effects = {
	{ Id = "collapse", Name = "Collapse", Rarity = "default", Hide = 0.30, Dur = 1.15, Color = C(174, 224, 255),
		Desc = "Ice-blue ignition, the suit implodes into its core, then a spherical shockwave throws out metal fragments." },
	{ Id = "overload", Name = "Overload", Rarity = "rare", Hide = 0.47, Dur = 1.25, Color = C(255, 42, 20),
		Desc = "Red current crawls across the exosuit, the armour cracks and shakes, then it vents in one violent discharge." },
	{ Id = "discharge", Name = "Discharge", Rarity = "rare", Hide = 0.41, Dur = 1.2, Color = C(168, 255, 58),
		Desc = "Lime arcs branch from the chest to every limb, the body burns out along them, then lightning strikes the ground all around." },
	{ Id = "aftershock", Name = "Aftershock", Rarity = "rare", Hide = 0.22, Dur = 1.2, Color = C(64, 208, 255),
		Desc = "Cyan energy crushes the Legionary into a trembling core, then four concentric shockwaves hammer outward." },
	{ Id = "phase", Name = "Phase Shift", Rarity = "epic", Hide = 0.40, Dur = 0.95, Color = C(176, 112, 255),
		Desc = "The suit drops into a purple hologram, glitches apart piece by piece and blinks out like a dying display." },
	{ Id = "meltdown", Name = "Meltdown", Rarity = "epic", Hide = 0.33, Dur = 1.35, Color = C(255, 106, 16),
		Desc = "The armour heats to white-hot, molten fractures open and the suit sags before bursting into glowing fragments." },
	{ Id = "shatter", Name = "Shatter", Rarity = "epic", Hide = 0.17, Dur = 1.2, Color = C(143, 200, 255),
		Desc = "The suit flash-freezes mid-stance and breaks into sharp blue crystal shards." },
	{ Id = "deconstruct", Name = "Deconstruct", Rarity = "epic", Hide = 0.56, Dur = 1.15, Color = C(255, 192, 112),
		Desc = "A scan line sweeps the suit, every armour piece unlocks and pulls away like an exploded diagram, then breaks into voxels." },
	{ Id = "supernova", Name = "Supernova", Rarity = "mythic", Hide = 0.24, Dur = 1.35, Color = C(255, 200, 96),
		Desc = "Stellar matter rushes in and crushes the suit into a golden star, which erupts in a radiant burst of rays and corona." },
	{ Id = "singularity", Name = "Singularity", Rarity = "mythic", Hide = 0.46, Dur = 0.95, Color = C(154, 120, 255),
		Desc = "A point of gravity warps space in front of the chest, spirals the Legionary inward and drags nearby debris in before it pops." },
	{ Id = "rift", Name = "Rift", Rarity = "mythic", Hide = 0.42, Dur = 1.05, Color = C(255, 64, 208),
		Desc = "A jagged dimensional tear splits open through the Legionary, squeezes the body into a sliver and swallows it before zipping shut." },
	{ Id = "cataclysm", Name = "Cataclysm", Rarity = "mythic", Hide = 0.29, Dur = 1.45, Color = C(255, 26, 8),
		Desc = "Black-red energy chokes the light, crushes the blackened suit into the ground, then ruptures outward with a heavy red shock." },
	{ Id = "voidborn", Name = "Voidborn", Rarity = "mythic", Hide = 0.50, Dur = 1.25, Color = C(122, 60, 255),
		Desc = "The suit breaks apart in patches into dark violet cosmic dust that spirals up into a slowly turning nebula." },
	{ Id = "horizon", Name = "Event Horizon", Rarity = "legendary", Hide = 0.45, Dur = 1.1, Color = C(255, 138, 48),
		Desc = "A miniature black hole with a spinning accretion disk opens at the chest and swallows the Legionary, then collapses in a photon flash." },
	{ Id = "ascension", Name = "Ascension", Rarity = "legendary", Hide = 0.46, Dur = 1.15, Color = C(255, 230, 160),
		Desc = "The Legionary turns to white-gold light and unravels from the boots up into streams that shoot skyward through a column of light." },
	{ Id = "fracture", Name = "Fracture", Rarity = "legendary", Hide = 0.44, Dur = 1.1, Color = C(207, 230, 255),
		Desc = "Space cracks into a shell of glass panes around the Legionary; the panes fold inward taking the body with them, and the void snaps shut." },
	{ Id = "apocalypse", Name = "Apocalypse", Rarity = "legendary", Hide = 0.27, Dur = 1.45, Color = C(168, 204, 255),
		Desc = "Electromagnetic bolts converge from all around and crush the suit to a white-out, then a plasma dome detonates across the arena." },
	{ Id = "prism", Name = "Prism", Rarity = "legendary", Hide = 0.26, Dur = 1.25, Color = C(240, 240, 255),
		Desc = "The suit crystallises with shifting colour, splits into red, green and blue echoes, then disperses as a spectrum of shards." },
	{ Id = "antimatter", Name = "Antimatter", Rarity = "legendary", Hide = 0.33, Dur = 1.3, Color = C(255, 32, 32),
		Desc = "A dark antimatter core forms and violently destabilises, then annihilates in a black, red and white pulse." },
}
Catalog.ById = {}
for i, e in Catalog.Effects do
	e.Index = i
	Catalog.ById[e.Id] = e
end

-- played timings (seconds) after the rarity stretch
function Catalog.Timing(id: string): (number, number)
	local e = Catalog.ById[id] or Catalog.ById[Catalog.Default]
	local T = Catalog.Tiers[e.Rarity]
	local hide = e.Hide * T.Kb
	return hide, hide + (e.Dur - e.Hide) * T.Kr
end

function Catalog.Valid(id: any): boolean
	return type(id) == "string" and Catalog.ById[id] ~= nil
end

function Catalog.Owns(_player: Player?, id: string): boolean
	if not Catalog.PlayerChoice then
		return id == Catalog.Default -- picker removed: nothing but the default can be equipped
	end
	return Catalog.Valid(id) -- everything is free for now
end

function Catalog.ForPlayer(player: Player): string
	if not Catalog.PlayerChoice then
		-- later: the killer's equipped top skin (at its top evolution level) supplies its own effect here
		return Catalog.Default
	end
	local id = player:GetAttribute("EliminationStyle")
	return if Catalog.Valid(id) then id else Catalog.Default
end

return Catalog
