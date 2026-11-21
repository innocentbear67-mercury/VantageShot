--[[
	VANTAGE — ULT config (2026-11-18)
	Every StreakPerCharge kills in one life (server streak, EliminationService) banks one ULT
	(Player attribute UltReady, max 1). The charge is kept through death until used and cleared
	when a new match starts. The HUD meter overloads (chromatic, shaking, sparking) while it is
	banked and shows ACTIVATE ULT [Key].

	ULT = ORBITAL LANCE: Veyra calls Command's orbital lance onto the point you are aiming at.
	A ground ring + targeting laser warns everyone for Delay seconds (enemies can dodge), then
	the lance slams down (Damage at the centre falling to EdgeDamage at Radius; walls between the
	impact and a target block it) and the scorched ground pulses Aftershocks times.
	Damage goes through DamageService (shields, friendly fire, kill credit, kill feed = explosion).
]]

return {
	-- 2026-11-20: REMOVED after the big playtest (players effectively had two ults with Signatures).
	-- false = no charge is ever banked, UltServer / VantageUltClient are disabled, the HUD meter is a
	-- plain kill-streak counter. Set true (and re-enable both scripts) to bring it back.
	Enabled = false,
	StreakPerCharge = 10,
	Key = Enum.KeyCode.Z,
	KeyLabel = "Z",
	Gamepad = Enum.KeyCode.DPadDown,

	Name = "ORBITAL LANCE",
	MaxRange = 600, -- aim ray from the head
	Delay = 1.25, -- telegraph before impact
	Radius = 18,
	CoreRadius = 7, -- full damage inside, and no cover check (direct hit)
	Damage = 400,
	EdgeDamage = 160,
	Aftershocks = 3,
	AftershockEvery = 0.45,
	AftershockRadius = 12,
	AftershockDamage = 40,

	Sounds = {
		Mark = { Id = "rbxassetid://9120769331", Volume = 0.9, Speed = 1.0 },
		Impact = { Id = "rbxassetid://18245316227", Volume = 2.2, Speed = 0.72 },
		Impact2 = { Id = "rbxassetid://9125484367", Volume = 1.4, Speed = 0.85 },
		Pulse = { Id = "rbxassetid://18245316227", Volume = 0.6, Speed = 1.35 },
	},
}
