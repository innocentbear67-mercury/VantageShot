--[[
	VANTAGE — EquipmentCatalog (shared, 2026-11-17)
	The two equipment slots that replaced armour customisation: Shield Pack ("Pack") and Grappling Hook ("Hook").
	Every item has its own look, colours, stats and signature ability (Ability.Id; tuning in Ability.Params).
	2026-11-18: every ability is live (server: EquipmentPerkServer + AbilityServer, client: VantageAbilityClient +
	VantagePerkClient) and the stats + ability show in Loadout > Equipment and the Inventory tooltip (EquipmentStatsUI).

	Player attributes (server-set, replicated):
	  Equip_Pack / Equip_Hook     equipped item id (LoadoutService)
	  OwnedEquipment              "Id,Id,..." owned items (CrateService); starters are always owned
	Character attributes (server-set on spawn / change):
	  ShieldColor, ShieldColor2   shield film + hexagon colours (ShieldFX)
	  HookColor, HookColor2       cable / bite / spark colours (GrappleFX)
	  EquipPack, EquipHook        the item ids on this character
	Remotes: EquipmentEquip(slot, id) -> EquipmentResult(ok, slot, id, reason)

	Stats are multipliers on the live configs (ShieldConfig / AbilityConfig.Abilities.Grapple), so tuning
	the base game still carries through. PackStats / HookStats return absolute numbers.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")

local Catalog = {}
local C3 = Color3.fromRGB

Catalog.Slots = { "Pack", "Hook" }
Catalog.SlotNames = { Pack = "Shield Pack", Hook = "Grappling Hook" }
Catalog.Default = { Pack = "Aegis", Hook = "Talon" }
Catalog.Ladder = { "Rare", "Epic", "Mythic", "Legendary", "Exclusive", "Godly" }

-- Color = main glow (shield film / cable sheath), Color2 = hot core (hex highlights / cable core)
Catalog.Items = {
	-- ── Shield Packs (2026-11-19 redesign: one visible trait each, costs tied to the trait) ──
	{ Id = "Aegis", Slot = "Pack", Name = "Aegis Mk1", Rarity = "Rare", Starter = true,
		Color = C3(64, 170, 255), Color2 = C3(214, 240, 255),
		Stats = { Shield = 1, Delay = 1, Rate = 1 },
		Ability = { Id = "None", Name = "Standard Issue", Text = "The most raw shield, with no conditions.", Cost = "None" },
		Desc = "Twin capacitor cells on a field frame. Every Legionary drops in with one." },
	{ Id = "Bastion", Slot = "Pack", Name = "Bastion", Rarity = "Epic",
		Color = C3(165, 95, 255), Color2 = C3(232, 214, 255),
		Stats = { Shield = 1, Delay = 3.5 / 3, Rate = 1 },
		Ability = { Id = "HexWall", Name = "Hex Wall", Text = "When your shield drops below 25%, a one-way hex wall snaps up toward your attacker for 2.5 s. Your team shoots through it; enemies can't.", Cost = "3.5 s recharge delay · 20 s cooldown",
			Params = { Duration = 2.5, HP = 175, Cooldown = 20, Width = 8, Height = 7, Distance = 4, Below = 0.25 } },
		Desc = "A hexagonal slab with one hardlight emitter and two folding wall projectors." },
	{ Id = "HaloRing", Slot = "Pack", Name = "Halo Ring", Rarity = "Mythic",
		Color = C3(255, 60, 40), Color2 = C3(255, 214, 200),
		Stats = { Shield = 0.9, Delay = 1, Rate = 1 },
		Ability = { Id = "Overshield", Name = "Overshield", Text = "After 4 s at full shield without damage, the ring spins up and adds +30 gold overshield. Enemies can see the glow.", Cost = "90 shield",
			Params = { Amount = 30, Wait = 4, Fill = 1 } },
		Desc = "A slim spine carrying a floating emitter ring." },
	{ Id = "SeraphArray", Slot = "Pack", Name = "Seraph Array", Rarity = "Legendary",
		Color = C3(255, 196, 70), Color2 = C3(255, 246, 214),
		Stats = { Shield = 0.9, Delay = 1, Rate = 1 },
		Ability = { Id = "Glide", Name = "Glide", Text = "Hold jump in the air to glide for 2 s. Refills on landing and when you let go of a grapple. Everyone sees the wings.", Cost = "90 shield",
			Params = { Time = 2, FallSpeed = 8 } },
		Desc = "Six gilded fins on an ivory solar core." },
	{ Id = "PulsarCore", Slot = "Pack", Name = "Pulsar Core", Rarity = "Exclusive",
		Color = C3(255, 80, 200), Color2 = C3(150, 245, 255),
		Stats = { Shield = 0.9, Delay = 1, Rate = 1 },
		Ability = { Id = "SquadPulse", Name = "Squad Pulse", Text = "When your recharge starts you pulse: +15 shield to you, +30 to allies within 18 studs, and their recharge starts at once.", Cost = "90 shield · 10 s cooldown",
			Params = { Self = 15, Ally = 30, Radius = 18, Cooldown = 10, AllyLock = 5 } },
		Desc = "A caged pink star circled by two cyan orbits. Event exclusive." },
	{ Id = "Singularity", Slot = "Pack", Name = "Singularity", Rarity = "Godly",
		Color = C3(255, 150, 60), Color2 = C3(200, 160, 255),
		Stats = { Shield = 0.85, Delay = 1, Rate = 1 },
		Ability = { Id = "EventHorizon", Name = "Event Horizon", Text = "When your shield breaks and you survive, you phase for 1.2 s (+30% speed, shimmering) and leave a 2 s gravity well that slows chasers by 35%.", Cost = "85 shield · 18 s cooldown",
			Params = { Phase = 1.2, Speed = 1.3, Radius = 10, Duration = 2, Slow = 0.65, Cooldown = 18 } },
		Desc = "A black orb inside a burning accretion disc, with three crystal shards in orbit." },
	-- ── Grappling Hooks (Profile = this hook's own pull feel, overrides on AbilityConfig.Abilities.Grapple) ──
	{ Id = "Talon", Slot = "Hook", Name = "Talon", Rarity = "Rare", Starter = true,
		Color = C3(70, 160, 255), Color2 = C3(225, 242, 255),
		Stats = { Range = 1, Cooldown = 1, Charges = 1 },
		Ability = { Id = "None", Name = "Standard Issue", Text = "A balanced pull and fling, and the fastest hook to reuse.", Cost = "None" },
		Profile = { Trail = { Width = 0.35, Life = 0.25 } },
		Desc = "Three-prong claw on a braided blue line." },
	{ Id = "Harpoon", Slot = "Hook", Name = "Harpoon", Rarity = "Epic",
		Color = C3(175, 110, 255), Color2 = C3(240, 228, 255),
		Stats = { Range = 200 / 220, Cooldown = 1.6, Charges = 1 },
		Ability = { Id = "Hunter", Name = "Hunter", Text = "A rigid winch: the fastest, straightest pull, with no fling. Aim at an enemy to spear them, drag yourself in and mark them for 4 s.", Cost = "No fling · longer cooldown",
			Params = { Mark = 4, ArriveDistance = 7, Radius = 3 } },
		Profile = { PullAccel = 380, MaxSpeed = 115, ReleaseBoost = 1.0, FloatTime = 0.8, ArriveKeep = 0.35, Rigid = true, Trail = { Width = 0.25, Life = 0.15 } },
		Desc = "A barbed spearhead on a violet energy line. The barbs flare on impact." },
	{ Id = "MagAnchor", Slot = "Hook", Name = "Mag-Anchor", Rarity = "Mythic",
		Color = C3(255, 60, 40), Color2 = C3(255, 220, 205),
		Stats = { Range = 1, Cooldown = 1.4, Charges = 1 },
		Ability = { Id = "Perch", Name = "Perch + Magnet", Text = "Near misses bend onto the closest ledge. Arrive at a wall to clamp on for 3 s and shoot. Jump to kick off.", Cost = "Slower pull · longer cooldown",
			Params = { Time = 3, Magnet = 7, MagnetReach = 10 } },
		Profile = { PullAccel = 200, MaxSpeed = 95, Trail = { Width = 0.45, Life = 0.35 } },
		Desc = "A spinning magnetic disc on a coil launcher. It clamps on with a red ripple." },
	{ Id = "Kraken", Slot = "Hook", Name = "Kraken", Rarity = "Legendary",
		Color = C3(255, 186, 60), Color2 = C3(255, 244, 210),
		Stats = { Range = 170 / 220, Cooldown = 1.52, Charges = 1 },
		Ability = { Id = "Relay", Name = "Relay", Text = "The claws bite with a violent yank. After you let go, your next grapple is free for 1.5 s, once.", Cost = "Shorter range · longer cooldown",
			Params = { Window = 1.5, MinPull = 0.4 } },
		Profile = { PullAccel = 220, MaxSpeed = 100, Jolt = 45, FloatTime = 2.0, Trail = { Width = 0.6, Life = 0.3 } },
		Desc = "Four curled gold claws and a twin-drum launcher." },
	{ Id = "Lotus", Slot = "Hook", Name = "Lotus", Rarity = "Exclusive",
		Color = C3(255, 80, 200), Color2 = C3(120, 240, 255),
		Stats = { Range = 1, Cooldown = 1.28, Charges = 1 },
		Ability = { Id = "Swing", Name = "Pendulum", Text = "Swing under the anchor, pump with the move keys and let go at the bottom for the biggest fling in the game.", Cost = "Longer cooldown",
			Params = { ReelSpeed = 7, MinLength = 14 } },
		Profile = { ReleaseBoost = 1.3, ReleaseMaxSpeed = 100, Trail = { Width = 0.7, Life = 0.6 } },
		Desc = "Six petals bloom open around a glowing core. Event exclusive." },
	{ Id = "Starfall", Slot = "Hook", Name = "Starfall", Rarity = "Godly",
		Color = C3(190, 140, 255), Color2 = C3(255, 240, 210),
		Stats = { Range = 130 / 220, Cooldown = 2.4, Charges = 1 },
		Ability = { Id = "Blink", Name = "Blink", Text = "Zip instantly along a beam of light. Enemies within 30 studs of where you land are revealed for 1.5 s.", Cost = "Short range · long cooldown",
			Params = { Reveal = 1.5, Radius = 30 } },
		Desc = "Three hardlight crescents around a gold ring. The cable is a beam of light." },
}

Catalog.ById = {}
for i, it in Catalog.Items do
	it.Order = i
	Catalog.ById[it.Id] = it
end

function Catalog.Get(id: string?)
	return id and Catalog.ById[id] or nil
end

function Catalog.List(slot: string?)
	local out = {}
	for _, it in Catalog.Items do
		if not slot or it.Slot == slot then
			table.insert(out, it)
		end
	end
	return out
end

function Catalog.Valid(slot: string, id: string): boolean
	local it = Catalog.ById[id]
	return it ~= nil and it.Slot == slot
end

-- owned: starters always; others need OwnedEquipment (true while it is still loading, like Skins.Owns)
function Catalog.Owns(player: Player?, id: string): boolean
	local it = Catalog.ById[id]
	if not it then
		return false
	end
	if it.Starter or not player then
		return true
	end
	local owned = player:GetAttribute("OwnedEquipment")
	if type(owned) ~= "string" then
		return true
	end
	return string.find("," .. owned .. ",", "," .. id .. ",", 1, true) ~= nil
end

-- 2026-11-17: equipment drops from crates as shards; Catalog.Shards of one item unlock it (CrateService).
-- Progress replicates as player attribute EquipShards (JSON { [Id] = n }), cleared for an item once it unlocks.
Catalog.Shards = 3
function Catalog.ShardCount(player: Player?, id: string): number
	local raw = player and player:GetAttribute("EquipShards")
	if type(raw) ~= "string" then
		return 0
	end
	local ok, t = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	return ok and type(t) == "table" and tonumber(t[id]) or 0
end

function Catalog.Equipped(player: Player?, slot: string): string
	if player and player:GetAttribute("InTutorial") then
		return Catalog.Default[slot] -- 2026-11-20 first-time training: starter hook + pack for everyone
	end
	local id = player and player:GetAttribute("Equip_" .. slot)
	if type(id) == "string" and Catalog.Valid(slot, id) then
		return id
	end
	return Catalog.Default[slot]
end

-- stats ───────────────────────────────────────────────────────────────────────────────────
local function shieldCfg()
	local ok, c = pcall(require, Vantage:WaitForChild("Shield"):WaitForChild("ShieldConfig"))
	return ok and c or { MaxShield = 100, RegenDelay = 3, RegenRate = 45 }
end
local function grappleCfg()
	local ok, c = pcall(require, Vantage:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
	return ok and c.Abilities.Grapple or { Range = 220, Cooldown = 2.5 }
end

function Catalog.PackStatsFor(id: string?)
	local it = Catalog.ById[id or ""] or Catalog.ById[Catalog.Default.Pack]
	local c, s = shieldCfg(), it.Stats
	return { MaxShield = math.floor(c.MaxShield * s.Shield + 0.5), RegenDelay = c.RegenDelay * s.Delay, RegenRate = c.RegenRate * s.Rate }
end

function Catalog.HookStatsFor(id: string?)
	local it = Catalog.ById[id or ""] or Catalog.ById[Catalog.Default.Hook]
	local g, s = grappleCfg(), it.Stats
	return { Range = g.Range * s.Range, Cooldown = g.Cooldown * s.Cooldown, Charges = s.Charges or 1 }
end

-- 2026-11-19: the item a character WEARS this life (EquipPack / EquipHook, set by EquipmentBuild.Dress on spawn).
-- Stats, traits and cooldowns read this, so equipping mid-match only applies on the next spawn.
function Catalog.Active(who: Instance?, slot: string): string
	local ch = who
	if who and who:IsA("Player") then
		ch = who.Character
	end
	local id = ch and ch:GetAttribute("Equip" .. slot)
	if type(id) == "string" and Catalog.Valid(slot, id) then
		return id
	end
	if who and who:IsA("Player") then
		return Catalog.Equipped(who, slot)
	end
	local p = who and game:GetService("Players"):GetPlayerFromCharacter(who)
	return if p then Catalog.Equipped(p, slot) else Catalog.Default[slot]
end

function Catalog.PackStats(player: Player?)
	return Catalog.PackStatsFor(Catalog.Active(player, "Pack"))
end

function Catalog.HookStats(player: Player?)
	return Catalog.HookStatsFor(Catalog.Active(player, "Hook"))
end

-- the hook's pull feel: AbilityConfig.Abilities.Grapple with the item's Profile on top (cached per id)
local profileCache = {}
function Catalog.HookProfileFor(id: string?)
	local it = Catalog.ById[id or ""] or Catalog.ById[Catalog.Default.Hook]
	local cfg = profileCache[it.Id]
	if not cfg then
		cfg = table.clone(grappleCfg())
		for k, v in it.Profile or {} do
			cfg[k] = v
		end
		profileCache[it.Id] = cfg
	end
	return cfg
end
function Catalog.HookProfile(who: Instance?)
	return Catalog.HookProfileFor(Catalog.Active(who, "Hook"))
end

-- ability of the item a player / character has in a slot (players: Equip_<slot>; bots, dummies: the character's Equip<slot>)
function Catalog.AbilityOf(who: Instance?, slot: string)
	local id = if who then Catalog.Active(who, slot) else nil
	local it = Catalog.ById[id or ""] or Catalog.ById[Catalog.Default[slot] ]
	return it.Ability.Id, it.Ability.Params or {}, it
end

-- colours for a character (works for bots and dummies too: falls back to the starters)
function Catalog.ShieldColors(character: Instance?)
	local a = character and character:GetAttribute("ShieldColor")
	local b = character and character:GetAttribute("ShieldColor2")
	local d = Catalog.ById[Catalog.Default.Pack]
	a = if typeof(a) == "Color3" then a else d.Color
	b = if typeof(b) == "Color3" then b else d.Color2
	return a, b
end

function Catalog.HookColors(character: Instance?)
	local a = character and character:GetAttribute("HookColor")
	local b = character and character:GetAttribute("HookColor2")
	local d = Catalog.ById[Catalog.Default.Hook]
	a = if typeof(a) == "Color3" then a else d.Color
	b = if typeof(b) == "Color3" then b else d.Color2
	return a, b
end

return Catalog
