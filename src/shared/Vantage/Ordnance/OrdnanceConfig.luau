--[[
	VANTAGE - OrdnanceConfig (shared), 2026-11-17
	Ordnance (ORD) = the second currency. It buys Arsenal Crates, which unlock guns (CrateConfig.WeaponCrates).
	Lore: Command issues ordnance to Legionaries for time in the field; spent at the armory to requisition new guns.
	Easy to earn (every match, every kill, every level-up) and also sold for Robux (ShopConfig "Ord" section).
	Server: ServerScriptService.VantageServer.Ordnance. Balance = player attribute "ORD" (server-set).
]]
local C = {}

C.Name = "Ordnance"
C.Short = "ORD"

-- earn rates (tune here). Rough pace: ~90-140 ORD per match + 100 per level-up,
-- so an Arsenal Crate (CrateConfig) is about one gun every 2 matches early on.
C.Rewards = {
	Elimination = 5,
	Assist = 2,
	Match = 40, -- finishing a match
	Win = 25, -- on top of Match
	LevelUp = 100, -- per account level gained
}

-- emblem: HS.ordCoin shows Icon with a masked light sweep (falls back to a drawn coin if Icon is nil)
C.Icon = "rbxassetid://79434984746847" -- ord_coin_v1 (user's Gemini hex coin, cut out)
C.IconMask = "rbxassetid://84715264786362" -- white silhouette for the light sweep
C.Color = Color3.fromRGB(255, 168, 46)
C.Light = Color3.fromRGB(255, 226, 140)
C.Dark = Color3.fromRGB(196, 86, 10)

return C
