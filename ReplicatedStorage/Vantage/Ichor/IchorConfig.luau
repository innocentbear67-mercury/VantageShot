--[[
	VANTAGE — ICHOR config (2026-11-19). Premium-tier currency for SIGNATURES: the golden blood of the
	gods. Mjölnir is free; the other nine Signatures are bought with Ichor in the shop (not in crates),
	where one randomised Signature is featured each day. Earned from the ICHOR FARM (a cauldron on a Yggdrasil branch, Lobby > Farm) and
	later matches / quests. Server: SignatureService (balance, Well).
]]
return {
	Name = "ICHOR",
	Short = "ICH",
	Icon = "rbxassetid://108288759204937", -- hex rune badge, 1024 (big displays, shop, rewards)
	Drop = "rbxassetid://87035928329415", -- drop only, 512 (small counters, "+50 Ichor" ticks)
	Colors = {
		Gold = Color3.fromRGB(255, 201, 74),
		WhiteGold = Color3.fromRGB(255, 243, 196),
		Ring = Color3.fromRGB(42, 45, 53),
	},
	-- ICHOR FARM: the Well (a cauldron) fills over time, even offline, up to its storage cap. Claim to bank it.
	-- Upgrades cost REQ. Level n: Rate (Ichor / hour), Cap (hours of storage). UpgradeCost[n] = REQ to go n -> n+1.
	Well = {
		Rate = { 25, 30, 36, 42, 48, 55, 62, 70, 75, 80 },
		Cap = { 12, 12, 13, 14, 15, 16, 17, 18, 19, 20 },
		UpgradeCost = { 2000, 4000, 6500, 9500, 13000, 17000, 22000, 28000, 35000 },
		StartStored = 100, -- a brand-new Well starts with this much so the first claim pays something
		MinClaim = 1,
	},
}
