--[[
	VANTAGE — SignatureConfig (2026-11-20): gameplay tuning for the 10 Signatures (shared by SignatureServer
	and SignatureClient). Starting values from the Phase 1 plan ("Signatures soften, guns finish": no Signature
	deals more than 135 to one target). Timings the server uses for hits match the FX modules' timelines.
	Aim-mode Signatures (Gungnir, Midgard, Bifrost) cast at the crosshair for now (no hold-to-preview yet).
]]
local Cfg = {}
Cfg.KeyLabel = "SHIFT"
Cfg.Keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL1 }
Cfg.Sig = {
	-- 01 piercing throw that returns; auto-aims at the 2 closest visible enemies (FX build 0.3 + summon 0.5 + throw 0.15)
	Mjolnir = { Implemented = true, Cooldown = 40, Windup = 0.95, OutSpeed = 160, Hang = 0.15, ReturnSpeed = 190, Range = 90, HitRadius = 3.5, AutoTargets = 2,
		DamageOut = 65, DamageBack = 35, ShockTime = 1, ShockSlow = 0.8 },
	-- 02 line charge (FX: circle 0.75 + leap 0.42 + rear 0.55 before the run)
	Fenrir = { Implemented = true, Cooldown = 45, Windup = 1.72, Speed = 64, Range = 70, HitRadius = 5.5, Damage = 80, KnockSide = 45, KnockUp = 25 },
	-- 03 precision skillshot down the crosshair, pierces up to 3 (FX hold, streak at 250 st/s)
	Gungnir = { Implemented = true, Cooldown = 35, Hold = 0.45, Range = 300, Speed = 250, Damage = 95, HeadDamage = 135, Falloff = 0.2, BodyRadius = 2.4, HeadRadius = 1.1, MaxPierce = 3, Assist = 8 },
	-- 04 area knock-up at the crosshair (FX windup 1.3), dive-back further on
	Midgard = { Implemented = true, Cooldown = 50, Range = 80, Windup = 1.3, Radius = 10, Damage = 60, KnockUp = 70, KnockImmune = 4, DiveDelay = 0.9, Reach = 26, DiveRadius = 7, DiveDamage = 30 },
	-- 05 rise, hover, dive to the crosshair (FX unfold 0.6 + hover + dive 0.42; fold 0.75)
	Valkyrie = { Implemented = true, Cooldown = 40, Range = 60, Hover = 0.9, ImpactAt = 1.92, Total = 2.7, Radius = 11, DamageCore = 75, DamageEdge = 35, Kill = 999, Snap = 16, Knock = 40 },
	-- 06 sword slam + fissure + burning ground (FX windup 1.0 + slam 0.2, fissure 72 st/s)
	Ragnarok = { Implemented = true, Cooldown = 50, Length = 60, Forward = 8, ImpactAt = 1.2, TargetRange = 220, ImpactRadius = 10, ImpactDamage = 999, RunSpeed = 72, Width = 3,
		FissureDamage = 50, Burn = 3, BurnDps = 10, BurnMax = 30 },
	-- 07 cone freeze (FX gate 0.9, wave 0.85)
	Helheim = { Implemented = true, Cooldown = 55, Windup = 0.9, Wave = 0.85, Range = 35, Angle = 60, Damage = 30, Freeze = 1.25, FreezeFrac = 0.7, ChillSlow = 0.6, ChillTime = 2, Immunity = 6 },
	-- 08 mounted charge along the ground (FX form 0.7)
	Sleipnir = { Implemented = true, Cooldown = 40, Form = 0.7, Speed = 80, Range = 120, HitRadius = 5, Damage = 45, KnockSide = 55, KnockUp = 20 },
	-- 09 teleport to the crosshair; the departure point explodes 0.5 s later (FX open 0.9 + link 0.5)
	Bifrost = { Implemented = true, Cooldown = 45, Range = 70, TeleportAt = 1.4, ExplodeDelay = 0.5, Radius = 10, DamageCore = 55, DamageEdge = 25, Knock = 35 },
	-- 10 ring of root walls round the caster; allies inside get +40 shield (FX windup 0.9 + rise 0.4)
	Yggdrasil = { Implemented = true, Cooldown = 50, Windup = 0.9, Rise = 0.4, Duration = 8, Spread = 9.5, RootW = 6, RootH = 4.8, Shield = 40, HealRate = 45 },
}
------------------------------------------------ 2026-11-20 BALANCE PASS (big playtest: Signatures were aimlocked one-shots)
-- No lock-on, no homing, no guaranteed kills. Every Signature goes where the crosshair points, every hit
-- is telegraphed to the enemies it threatens, and can be dodged: leave the marked zone / lane, or press
-- DODGE (Dodge.Key) in the Window before contact. Cooldowns are 2.5-3.7x longer than the 30 s before.
-- Damage: a direct hit hurts badly but nothing one-shots a full 100 HP + 100 shield operative (200).
Cfg.Kill = nil
Cfg.StartCooldown = 45 -- a new match starts every Signature on this much cooldown
Cfg.Dodge = {
	Key = Enum.KeyCode.Z, Gamepad = Enum.KeyCode.DPadDown, KeyLabel = "Z",
	Window = 0.4, -- s before contact a press counts
	Late = 0.12, -- s after contact a press still counts (latency)
	Grace = 0.12, -- s the server waits after contact for a player's press to arrive
	Lockout = 1.5, -- any press (hit or miss) blocks the next for this long: spamming never works
	Warn = 1.4, -- s before contact the threatened player sees the DODGE prompt
	BotChance = 0, -- bots never dodge
}
do
	local S = Cfg.Sig
	local cd = { Mjolnir = 75, Gungnir = 75, Fenrir = 85, Sleipnir = 85, Bifrost = 80, Valkyrie = 90, Midgard = 90, Helheim = 90, Yggdrasil = 100, Ragnarok = 110 }
	for id, s in cd do S[id].Cooldown = s end
	S.Mjolnir.Range = 90; S.Mjolnir.DamageOut = 90; S.Mjolnir.DamageBack = 45; S.Mjolnir.AutoTargets = 0
	S.Fenrir.Windup = 2.0; S.Fenrir.Speed = 64; S.Fenrir.Range = 80; S.Fenrir.HitRadius = 5; S.Fenrir.Damage = 110
	S.Gungnir.Damage = 110; S.Gungnir.HeadDamage = 160; S.Gungnir.BodyRadius = 2.0; S.Gungnir.Assist = 0
	S.Midgard.Range = 120; S.Midgard.Radius = 10; S.Midgard.Damage = 120; S.Midgard.EdgeDamage = 60
	S.Valkyrie.Range = 70; S.Valkyrie.Rise = 11; S.Valkyrie.Kill = nil; S.Valkyrie.DamageCore = 130; S.Valkyrie.DamageEdge = 50; S.Valkyrie.Snap = 0
	S.Ragnarok.TargetRange = 120; S.Ragnarok.ImpactDamage = 140
	S.Helheim.Range = 40; S.Helheim.Angle = 70; S.Helheim.Damage = 60
	S.Sleipnir.Speed = 80; S.Sleipnir.HitRadius = 5; S.Sleipnir.Damage = 90
	S.Bifrost.Range = 2000; S.Bifrost.Radius = 10; S.Bifrost.ArriveCore = 110; S.Bifrost.ArriveEdge = 40
	S.Yggdrasil.HealRate = 30; S.Yggdrasil.ImpaleDamage = 90
end
------------------------------------------------ 2026-11-20 (pm, user): homing / lock-on is BACK (SignatureLock), the dodge stays,
-- every Signature's damage is cut by 60% (x0.4 of the values above). Mjölnir: 20% damage and a 1.5 s STUN.
do
	local S = Cfg.Sig
	local K = 0.4
	S.Fenrir.Damage *= K; S.Fenrir.ChaseTime = 3.5
	S.Sleipnir.Damage *= K; S.Sleipnir.ChaseTime = 3
	S.Gungnir.Damage *= K; S.Gungnir.HeadDamage *= K
	S.Midgard.Damage *= K; S.Midgard.EdgeDamage *= K
	S.Valkyrie.DamageCore *= K; S.Valkyrie.DamageEdge *= K
	S.Ragnarok.ImpactDamage *= K; S.Ragnarok.FissureDamage *= K; S.Ragnarok.BurnDps *= K; S.Ragnarok.BurnMax *= K
	S.Helheim.Damage *= K
	S.Bifrost.ArriveCore *= K; S.Bifrost.ArriveEdge *= K; S.Bifrost.DamageCore *= K; S.Bifrost.DamageEdge *= K
	S.Yggdrasil.ImpaleDamage *= K
	-- Mjolnir: 20% of its damage (90 -> 18 per hit), and every hit stuns for 1.5 s instead of slowing
	S.Mjolnir.DamageOut = 18; S.Mjolnir.DamageBack = 9; S.Mjolnir.AutoTargets = 2
	S.Mjolnir.Stun = 1.5; S.Mjolnir.StunImmunity = 3
end

return Cfg
