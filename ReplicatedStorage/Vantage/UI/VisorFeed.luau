-- VANTAGE — VisorFeed (client): one shared table between the weapon client and the visor.
--   written by HudOptics (wraps Hud:SetWeapon / SetAmmo / SetReload / SetHeat / Step):
--     Weapon (config table), Mag, Reserve, Size, Reload (0..1 | nil), Heat (0..1 | nil), Locked, Timer
--   written by VantageVisorClient, read by Viewmodel:Step:
--     Hands = { W = 0..1 (gun -> hands blend), H = 0..1 (hand height: below view -> above the top edge) }
return {
	Weapon = nil, Mag = 0, Reserve = 0, Size = 0, Reload = nil, Heat = nil, Locked = false, Timer = nil,
	Hands = { W = 0, H = 0 },
}
