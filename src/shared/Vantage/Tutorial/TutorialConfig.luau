--[[
	VANTAGE — TutorialConfig (shared), 2026-11-20
	Layout + stage list for the first-time training (server: VantageServer.TutorialService,
	client: StarterPlayerScripts.VantageTutorial). Every arena is built at Origin + slot * Spacing on X;
	L holds offsets from that arena origin (the arena faces -Z).
]]
local T = {}

T.Version = 1
T.Origin = Vector3.new(-9000, 2400, 9000)
T.Spacing = 600
T.TargetsNeeded = 3

T.Stages = {
	{ Id = "Movement", Label = "MOVEMENT" },
	{ Id = "Grapple", Label = "GRAPPLE" },
	{ Id = "Weapons", Label = "WEAPONS" },
	{ Id = "Shields", Label = "SHIELDS" },
	{ Id = "Loadout", Label = "LOADOUT" },
}
-- part 2: the lobby briefing (currencies, crates, shop, farm, play), run on the real lobby UI after ENTER THE BATTLE
T.Briefing = { "CURRENCIES", "CRATES", "SHOP", "ICHOR FARM", "PLAY" }

T.L = {
	Spawn = Vector3.new(0, 3.5, 2),
	Marker = Vector3.new(0, 0, -22),
	MarkerRadius = 5,
	BarrierZ = -34,
	BarrierH = 3.5,
	Stage2 = Vector3.new(0, 3.5, -44),
	TowerFront = -62,
	TowerBack = -96,
	TowerTop = 30,
	Anchor = Vector3.new(0, 56, -72.8),
	Stage3 = Vector3.new(0, 33.5, -86),
	Targets = { Vector3.new(-12, 30, -136), Vector3.new(0, 30, -144), Vector3.new(12, 30, -136) },
	Sentry = Vector3.new(18, 44, -118),
	FallY = -30,
}

return T
