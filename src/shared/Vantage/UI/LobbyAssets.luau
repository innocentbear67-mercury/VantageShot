--[[
	VANTAGE — LobbyAssets: uploaded image ids for the lobby (2026-11-15).
	Source files: ~/roblox-game/vantage-lobby-assets (UI Icon Pack: rank shields + keycaps by
	RhosGFX, CC0; Skip_Sim chevron; concrete / wall panel / metal textures generated for VantageShot).
	Textures are MaterialVariants in MaterialService: LobbyConcrete, LobbyWallPanel, LobbyMetal.
]]
local Assets = {
	Icons = {
		Deploy = "rbxassetid://116488380866787",
	},
	Keys = {
		enter = "rbxassetid://87242522149430", backspace = "rbxassetid://96104227055401",
		escape = "rbxassetid://101868893205478", q = "rbxassetid://95573333257367",
		e = "rbxassetid://77167009394368", tab = "rbxassetid://78043338625288",
	},
	KeyAspect = { enter = 449 / 220, backspace = 2, escape = 2, tab = 2, q = 1, e = 1 },
	-- shield rank badges: Ranks[tier][step], tier 1..10 = Wood .. Master, step 1..3
	RankTiers = { "Wood", "Bronze", "Silver", "Gold", "Platinum", "Sapphire", "Ruby", "Amethyst", "Onyx", "Master" },
	Ranks = {
		[1] = { "rbxassetid://125071767155330", "rbxassetid://99123367368687", "rbxassetid://120216609720415" }, -- Wood
		[2] = { "rbxassetid://98226401181064", "rbxassetid://83231293326373", "rbxassetid://91161333719891" }, -- Bronze
		[3] = { "rbxassetid://114921636796978", "rbxassetid://131063170014592", "rbxassetid://135589391186510" }, -- Silver
		[4] = { "rbxassetid://113185108788408", "rbxassetid://95939455476382", "rbxassetid://130620241948490" }, -- Gold
		[5] = { "rbxassetid://95935294569961", "rbxassetid://78648794590732", "rbxassetid://74307079924348" }, -- Platinum
		[6] = { "rbxassetid://125009545898397", "rbxassetid://88375213151248", "rbxassetid://115274247983565" }, -- Sapphire
		[7] = { "rbxassetid://130491037294513", "rbxassetid://116521562102028", "rbxassetid://131144115390541" }, -- Ruby
		[8] = { "rbxassetid://77914438556112", "rbxassetid://130533407480291", "rbxassetid://109100631585842" }, -- Amethyst
		[9] = { "rbxassetid://120056125929052", "rbxassetid://116131823931213", "rbxassetid://88708654998413" }, -- Onyx
		[10] = { "rbxassetid://122027156718451", "rbxassetid://79591960137239", "rbxassetid://91865630282470" }, -- Master
	},
	Unranked = "rbxassetid://100649051119384",
	-- 9-slice UI kit (painted for VantageShot; Image + SliceCenter rect in pixels)
	UI = {
		Slab = { Image = "rbxassetid://94727071876071", Slice = Rect.new(20, 20, 108, 108) },
		SlabWhite = { Image = "rbxassetid://102588314429625", Slice = Rect.new(20, 20, 108, 108) },
		SlabSm = { Image = "rbxassetid://108604788537652", Slice = Rect.new(14, 14, 50, 50) },
		Header = { Image = "rbxassetid://123010118502167", Slice = Rect.new(24, 24, 464, 88) },
		Deploy = { Image = "rbxassetid://92703729672226", Slice = Rect.new(230, 30, 480, 120) },
		DeployHot = { Image = "rbxassetid://71001435602295", Slice = Rect.new(230, 30, 480, 120) },
		Plate = { Image = "rbxassetid://77235875902542", Slice = Rect.new(48, 20, 432, 76) },
	},
}

-- level 1..100 -> badge image + tier name: 10 levels per tier, 3 steps inside a tier
function Assets.RankFor(level: number): (string, string)
	level = math.clamp(math.floor(level or 1), 1, 100)
	local tier = math.min(10, (level - 1) // 10 + 1)
	local within = (level - 1) % 10 -- 0..9
	local step = if within < 3 then 1 elseif within < 7 then 2 else 3
	return Assets.Ranks[tier][step], Assets.RankTiers[tier]
end

return Assets
