--[[
	VANTAGE — WeaponClips (shared)
	Keyframed weapon animations, used by BOTH the first-person viewmodel and the third-person
	character rig, so what you do and what others see always match.

	Clip format
		Length  seconds at nominal speed (players stretch clips to config timings)
		Tracks  name -> { key(t, posVector3, rotDegVector3), ... }   (smoothstep between keys)
		        rifle:  Gun (grip-local offset), Mag (magazine offset in gun space)
		        knife:  Hand (pos = camera / torso space offset, rot = hand-local),
		                Left (left hand offset), Blade / Bite (hinge angle about Z in rot.Z)
		Weights name -> { {t, w}, ... }   e.g. LeftOnMag (support hand on the magazine)
		Hidden  name -> { t0, t1 }        e.g. Mag hidden while it is "swapped"
		Events  { {t, name}, ... }        sounds, ammo refill (MagIn), melee strike, flips
	Sample(clip, t) -> { Tracks = {name: CFrame}, Weights = {name: number}, Hidden = {name: bool} }
]]

local V = Vector3.new

local function key(t, p, r)
	return { t = t, p = p or Vector3.zero, r = r or Vector3.zero }
end
local function ang(t, deg) -- hinge key: rotation about Z
	return { t = t, p = Vector3.zero, r = V(0, 0, deg) }
end

local WeaponClips = {}

-- ─── VX-01 Vanguard (also the default set for any gun without its own clips) ─
local Rifle = {}
Rifle.Equip = {
	Length = 0.45,
	Tracks = {
		Gun = {
			key(0, V(0.12, -0.95, 0.35), V(-42, 16, 30)),
			key(0.28, V(0, 0.03, -0.01), V(4, -1, -2)),
			key(0.45),
		},
	},
	Events = { { t = 0.04, name = "Equip" } },
}
Rifle.Unequip = {
	Length = 0.3,
	Tracks = { Gun = { key(0), key(0.3, V(0.12, -0.95, 0.35), V(-42, 16, 30)) } },
	Events = {},
}
-- Reload 2.0 s: tilt -> release + pull (MagOut 0.45) -> new mag arrives -> seat (MagIn 1.35:
-- ammo refills HERE) -> roll back, bolt release (1.62) -> settle with a small overshoot.
-- Concealment: the Tripo mesh keeps its own magazine, so the gun pitches muzzle-up and rolls its
-- TOP toward the camera while the mag is out: the mag well faces away and the receiver hides
-- both the built-in mag and the prop. The prop drops straight out and a fresh one comes up from
-- below; what you see is the hand going under, the seat jolt and the bolt release.
Rifle.Reload = {
	Length = 2.0,
	Tracks = {
		Gun = {
			key(0),
			key(0.2, V(-0.03, 0.03, 0.04), V(14, 4, 17)),
			key(0.4, V(-0.03, 0.04, 0.04), V(16, 4, 18)),
			key(0.47, V(-0.03, 0.07, 0.03), V(19, 4, 19)),
			key(0.6, V(-0.03, 0.02, 0.05), V(13, 4, 19)),
			key(1.1, V(-0.03, 0.04, 0.04), V(15, 4, 17)),
			key(1.3, V(-0.03, 0.03, 0.04), V(14, 4, 17)),
			key(1.36, V(-0.03, 0.1, 0.025), V(20, 4, 16)),
			key(1.45, V(-0.03, 0.01, 0.05), V(11, 4, 18)),
			key(1.58, V(0.0, 0.02, 0.06), V(4, 5, -8)),
			key(1.65, V(0.0, 0.0, 0.12), V(1, 6, -6)),
			key(1.82, V(0.0, 0.006, -0.008), V(-1.2, 0, 0.8)),
			key(2.0),
		},
		-- old mag pulled straight out and away (behind the receiver), swapped while hidden,
		-- fresh mag brought up from below and seated
		Mag = {
			key(0),
			key(0.4),
			key(0.48, V(0, -0.14, 0.02), V(-6, 0, 0)),
			key(0.64, V(0, -1.2, 0.2), V(-25, 0, 10)),
			key(0.8, V(-0.1, -1.4, 0.5), V(-20, 0, -10)),
			key(1.12, V(0.02, -0.42, 0.08), V(-14, 0, 4)),
			key(1.27, V(0, -0.07, 0.01), V(-4, 0, 0)),
			key(1.35),
			key(2.0),
		},
	},
	Weights = {
		LeftOnMag = { { t = 0, w = 0 }, { t = 0.3, w = 1 }, { t = 1.38, w = 1 }, { t = 1.62, w = 0 }, { t = 2.0, w = 0 } },
	},
	Hidden = { Mag = { 0.62, 0.8 } },
	Events = {
		{ t = 0.45, name = "MagOut" },
		{ t = 1.35, name = "MagIn" },
		{ t = 1.62, name = "Bolt" },
	},
}
-- ─── Inspect (F) ─────────────────────────────────────────────────────────
-- Layered on the normal grip pose (Gun = grip-local offset), so no framing value changes.
-- Firing, aiming, reloading or switching cancels it with a short blend back to ready.
-- Rifle 2.6 s: roll to show the right side -> turn to the left side / top -> magazine
-- press-check (support hand on the mag) -> settle with a small overshoot.
Rifle.Inspect = {
	Length = 2.6,
	Tracks = {
		Gun = {
			key(0),
			key(0.35, V(-0.08, 0.1, 0.1), V(10, 28, -52)),
			key(0.95, V(-0.09, 0.11, 0.1), V(12, 32, -56)),
			key(1.3, V(-0.02, 0.06, 0.06), V(18, -12, 38)),
			key(1.72, V(-0.02, 0.07, 0.06), V(16, -15, 42)),
			key(1.9, V(-0.03, 0.04, 0.05), V(6, -8, -18)),
			key(2.12, V(-0.03, 0.05, 0.05), V(8, -9, -20)),
			key(2.38, V(0, 0.008, -0.004), V(-1.5, 0, 1)),
			key(2.6),
		},
		Mag = { key(0), key(1.88), key(1.98, V(0, -0.1, 0.01), V(-5, 0, 0)), key(2.06, V(0, -0.1, 0.01), V(-5, 0, 0)), key(2.14), key(2.6) },
	},
	Weights = { LeftOnMag = { { t = 0, w = 0 }, { t = 1.74, w = 0 }, { t = 1.88, w = 1 }, { t = 2.2, w = 1 }, { t = 2.4, w = 0 }, { t = 2.6, w = 0 } } },
	Events = { { t = 0.4, name = "Bolt" }, { t = 1.98, name = "MagOut" }, { t = 2.14, name = "MagIn" } },
}
WeaponClips.Vanguard = Rifle
WeaponClips.Rifle = Rifle

-- variants for the other guns: the rifle set with a different inspect (all data, no code)
local function withInspect(inspect)
	local set = table.clone(Rifle)
	set.Inspect = inspect
	return set
end
-- Compact (SMG) 2.0 s: quick flip to the side and back, fast mag tap
local CompactInspect = {
	Length = 2.0,
	Tracks = {
		Gun = {
			key(0),
			key(0.22, V(-0.06, 0.1, 0.08), V(14, 52, -70)),
			key(0.7, V(-0.07, 0.11, 0.08), V(16, 56, -74)),
			key(0.95, V(-0.02, 0.07, 0.05), V(20, -20, 50)),
			key(1.3, V(-0.02, 0.07, 0.05), V(18, -22, 54)),
			key(1.45, V(-0.02, 0.03, 0.04), V(4, -6, -14)),
			key(1.62, V(-0.02, 0.05, 0.04), V(7, -6, -15)),
			key(1.84, V(0, 0.006, 0), V(-1, 0, 0.8)),
			key(2.0),
		},
		Mag = { key(0), key(1.46), key(1.54, V(0, -0.08, 0)), key(1.62), key(2.0) },
	},
	Weights = { LeftOnMag = { { t = 0, w = 0 }, { t = 1.36, w = 0 }, { t = 1.46, w = 1 }, { t = 1.66, w = 1 }, { t = 1.82, w = 0 }, { t = 2.0, w = 0 } } },
	Events = { { t = 0.25, name = "Bolt" }, { t = 1.54, name = "MagOut" }, { t = 1.62, name = "MagIn" } },
}
-- Heavy (shotgun) 3.0 s: slow heavy tilt, look down the barrel side, rack the pump twice
local HeavyInspect = {
	Length = 3.0,
	Tracks = {
		Gun = {
			key(0),
			key(0.45, V(-0.1, 0.12, 0.12), V(8, 24, -46)),
			key(1.1, V(-0.11, 0.13, 0.12), V(10, 27, -50)),
			key(1.5, V(-0.03, 0.04, 0.08), V(4, -6, -10)),
			key(1.7, V(-0.03, 0.04, 0.2), V(3, -6, -10)),   -- pump back
			key(1.86, V(-0.03, 0.04, 0.06), V(4, -6, -10)),  -- pump forward
			key(2.1, V(-0.03, 0.04, 0.2), V(3, -6, -10)),
			key(2.26, V(-0.03, 0.04, 0.06), V(4, -6, -10)),
			key(2.7, V(0, 0.01, -0.006), V(-1.5, 0, 1)),
			key(3.0),
		},
	},
	Events = { { t = 1.7, name = "Bolt" }, { t = 2.1, name = "Bolt" } },
}
-- Marksman (DMR / sniper) 2.8 s: raise and turn to check the optic, then a bolt check
local MarksmanInspect = {
	Length = 2.8,
	Tracks = {
		Gun = {
			key(0),
			key(0.45, V(-0.12, 0.16, 0.1), V(-14, 40, -22)),
			key(1.15, V(-0.13, 0.17, 0.1), V(-16, 44, -24)),
			key(1.5, V(-0.03, 0.05, 0.06), V(10, -8, 30)),
			key(1.9, V(-0.03, 0.05, 0.06), V(12, -9, 32)),
			key(2.05, V(-0.03, 0.05, 0.14), V(10, -8, 28)),
			key(2.2, V(-0.03, 0.05, 0.06), V(12, -9, 30)),
			key(2.55, V(0, 0.008, -0.004), V(-1.2, 0, 0.8)),
			key(2.8),
		},
	},
	Events = { { t = 2.05, name = "Bolt" }, { t = 2.2, name = "Bolt" } },
}
-- Energy (Arc) 2.6 s: turn to the side, vent the cell (a short shudder), turn back
local EnergyInspect = {
	Length = 2.6,
	Tracks = {
		Gun = {
			key(0),
			key(0.4, V(-0.07, 0.1, 0.08), V(8, 34, -48)),
			key(0.9, V(-0.08, 0.11, 0.08), V(10, 36, -52)),
			key(1.25, V(-0.02, 0.06, 0.05), V(14, -10, 30)),
			key(1.4, V(-0.02, 0.07, 0.07), V(16, -10, 33)),
			key(1.46, V(-0.02, 0.05, 0.05), V(13, -10, 29)),
			key(1.52, V(-0.02, 0.07, 0.07), V(16, -10, 33)),
			key(1.58, V(-0.02, 0.05, 0.05), V(13, -10, 29)),
			key(1.9, V(-0.02, 0.06, 0.05), V(14, -11, 31)),
			key(2.35, V(0, 0.008, -0.004), V(-1.5, 0, 1)),
			key(2.6),
		},
	},
	Events = { { t = 1.4, name = "Bolt" } },
}
-- ─── PX-9 Spectre (pistol) ───────────────────────────────────────────────────────────────────
-- Reload 1.35 s: tip the pistol in, drop the mag (MagOut 0.22), new mag up into the grip
-- (MagIn 0.82), slide release snap (1.02), settle.
local Pistol = withInspect(CompactInspect)
Pistol.Equip = {
	Length = 0.26,
	Tracks = { Gun = { key(0, V(0.08, -0.6, 0.25), V(-50, 10, 24)), key(0.18, V(0, 0.02, -0.01), V(4, -1, -2)), key(0.26) } },
	Events = { { t = 0.02, name = "Equip" } },
}
Pistol.Unequip = {
	Length = 0.18,
	Tracks = { Gun = { key(0), key(0.18, V(0.08, -0.6, 0.25), V(-50, 10, 24)) } },
	Events = {},
}
Pistol.Reload = {
	Length = 1.35,
	Tracks = {
		Gun = {
			key(0),
			-- muzzle down + top rolled to the camera: the grip base (and its built-in mag) faces away
			key(0.15, V(-0.04, 0.06, 0.04), V(-18, 6, 20)),
			key(0.22, V(-0.04, 0.09, 0.03), V(-15, 6, 21)),
			key(0.32, V(-0.04, 0.05, 0.05), V(-20, 6, 21)),
			key(0.75, V(-0.04, 0.05, 0.05), V(-20, 6, 20)),
			key(0.82, V(-0.04, 0.11, 0.03), V(-12, 6, 19)),
			key(0.92, V(-0.04, 0.04, 0.05), V(-21, 6, 20)),
			key(1.02, V(0, 0.02, 0.09), V(5, 4, -6)),
			key(1.2, V(0, 0.005, -0.005), V(-1, 0, 0.6)),
			key(1.35),
		},
		Mag = {
			key(0),
			key(0.2),
			key(0.26, V(0, -0.15, 0)),
			key(0.42, V(0, -1.2, 0.2), V(-20, 0, 8)),
			key(0.48, V(-0.05, -1.3, 0.4), V(-14, 0, -6)),
			key(0.66, V(0, -0.4, 0.06), V(-10, 0, 3)),
			key(0.78, V(0, -0.06, 0)),
			key(0.82),
			key(1.35),
		},
	},
	Weights = { LeftOnMag = { { t = 0, w = 0 }, { t = 0.3, w = 0 }, { t = 0.44, w = 1 }, { t = 0.86, w = 1 }, { t = 1.02, w = 0 }, { t = 1.35, w = 0 } } },
	Hidden = { Mag = { 0.38, 0.52 } },
	Events = { { t = 0.22, name = "MagOut" }, { t = 0.82, name = "MagIn" }, { t = 1.02, name = "Rack" } },
}
WeaponClips.Pistol = Pistol
WeaponClips.Spectre = Pistol

-- ─── SG-12 Breacher (pump shotgun) ────────────────────────────────────────────────────────
-- Rechamber 0.55 s after every shot: support hand racks the pump back (Pump 0.16: the hull
-- ejects) and forward. Shell reload = ReloadStart -> ShellIn (one per shell, loops) -> ReloadEnd.
-- The shell clips all meet in one loading pose (LOAD) so the loop never snaps.
local LOAD_P, LOAD_R = V(-0.05, 0.07, 0.05), V(12, -10, -30)
local SHELL_LOW = V(0.02, -0.38, 0.18) -- support hand down at the shell carrier
local Shotgun = withInspect(HeavyInspect)
Shotgun.Rechamber = {
	Length = 0.55,
	Tracks = {
		Gun = {
			key(0),
			key(0.12, V(0, -0.012, 0.04), V(-3, 1, -5)),
			key(0.3, V(0, -0.01, 0.035), V(-2, 1, -4)),
			key(0.44, V(0, 0.004, -0.004), V(0.6, 0, 0.5)),
			key(0.55),
		},
		Left = { key(0), key(0.05), key(0.16, V(0, 0, 0.24)), key(0.24, V(0, 0, 0.24)), key(0.36), key(0.55) },
	},
	Events = { { t = 0.16, name = "Pump" } },
}
Shotgun.ReloadStart = {
	Length = 0.35,
	Tracks = { Gun = { key(0), key(0.35, LOAD_P, LOAD_R) }, Mag = { key(0), key(0.35, SHELL_LOW) } },
	Weights = { LeftOnMag = { { t = 0, w = 0 }, { t = 0.3, w = 1 }, { t = 0.35, w = 1 } } },
	Events = {},
}
Shotgun.ShellIn = {
	Length = 0.48,
	Tracks = {
		Gun = {
			key(0, LOAD_P, LOAD_R),
			key(0.26, LOAD_P, LOAD_R),
			key(0.31, LOAD_P + V(0, 0.03, -0.01), LOAD_R + V(3, 0, 1)),
			key(0.4, LOAD_P, LOAD_R),
			key(0.48, LOAD_P, LOAD_R),
		},
		Mag = { key(0, SHELL_LOW), key(0.12, SHELL_LOW + V(0, 0.05, 0)), key(0.26, V(0, -0.04, 0.01), V(-6, 0, 0)), key(0.31), key(0.48, SHELL_LOW) },
	},
	Weights = { LeftOnMag = { { t = 0, w = 1 }, { t = 0.48, w = 1 } } },
	Events = {},
}
Shotgun.ReloadEnd = {
	Length = 0.4,
	Tracks = {
		Gun = { key(0, LOAD_P, LOAD_R), key(0.14, V(0, 0.01, 0.03), V(2, -2, -6)), key(0.3, V(0, 0.005, 0.02), V(-1, 0, -2)), key(0.4) },
		Mag = { key(0, SHELL_LOW), key(0.14) },
		Left = { key(0), key(0.14), key(0.22, V(0, 0, 0.24)), key(0.32), key(0.4) },
	},
	Weights = { LeftOnMag = { { t = 0, w = 1 }, { t = 0.14, w = 0 }, { t = 0.4, w = 0 } } },
	Events = { { t = 0.22, name = "Rack" } },
}
WeaponClips.Shotgun = Shotgun
WeaponClips.Breacher = Shotgun

-- ─── SR-88 Longshot (bolt-action sniper) ─────────────────────────────────────────────────
-- Right hand leaves the grip for the bolt handle (RightOnBolt), lift -> pull back (Bolt 0.42:
-- the case ejects) -> push -> lock down -> back to the grip.
local BOLT_UP, BOLT_BACK = V(0.03, 0.06, 0), V(0.03, 0.06, 0.26)
local BoltCycle = function(t0)
	return {
		Right = { key(t0 + 0.12), key(t0 + 0.24, BOLT_UP), key(t0 + 0.4, BOLT_BACK), key(t0 + 0.5, BOLT_BACK), key(t0 + 0.62, BOLT_UP), key(t0 + 0.72) },
		Weight = { { t = t0, w = 0 }, { t = t0 + 0.12, w = 1 }, { t = t0 + 0.72, w = 1 }, { t = t0 + 0.85, w = 0 } },
	}
end
local Sniper = withInspect(MarksmanInspect)
local rc = BoltCycle(0)
Sniper.Rechamber = {
	Length = 0.9,
	Tracks = {
		-- straight up-and-back (no sideways roll): a small lift while the bolt is worked
		Gun = {
			key(0),
			key(0.15, V(0, 0.03, 0.02), V(5, 0, 0)),
			key(0.42, V(0, 0.04, 0.025), V(6, 0, 0)),
			key(0.48, V(0, 0.03, 0.02), V(5, 0, 0)),
			key(0.75, V(0, 0.005, 0), V(1, 0, 0)),
			key(0.9),
		},
		Right = rc.Right,
	},
	Weights = { RightOnBolt = rc.Weight },
	Events = { { t = 0.42, name = "Bolt" } },
}
-- Reload 3.0 s: tilt, mag out (0.5), new mag (MagIn 1.6), bolt cycle (BoltCue 2.1), settle
local rr = BoltCycle(1.85)
Sniper.Reload = {
	Length = 3.0,
	Tracks = {
		Gun = {
			key(0),
			-- straight up-and-back (user, 2026-11-08): the muzzle lifts slightly for the mag swap
			-- and the bolt, then settles; no sideways roll
			key(0.3, V(0, 0.05, 0.03), V(8, 0, 0)),
			key(0.5, V(0, 0.07, 0.03), V(10, 0, 0)),
			key(0.65, V(0, 0.05, 0.04), V(8, 0, 0)),
			key(1.45, V(0, 0.05, 0.04), V(8, 0, 0)),
			key(1.6, V(0, 0.09, 0.02), V(11, 0, 0)),
			key(1.72, V(0, 0.04, 0.04), V(7, 0, 0)),
			key(1.95, V(0, 0.04, 0.03), V(6, 0, 0)),
			key(2.45, V(0, 0.04, 0.03), V(6, 0, 0)),
			key(2.75, V(0, 0.006, -0.006), V(-1, 0, 0.8)),
			key(3.0),
		},
		Mag = {
			key(0),
			key(0.45),
			key(0.55, V(0, -0.14, 0.02), V(-6, 0, 0)),
			key(0.85, V(0, -1.2, 0.2), V(-24, 0, 10)),
			key(0.92, V(-0.1, -1.4, 0.5), V(-20, 0, -10)),
			key(1.3, V(0.02, -0.4, 0.08), V(-14, 0, 4)),
			key(1.5, V(0, -0.06, 0.01), V(-4, 0, 0)),
			key(1.6),
			key(3.0),
		},
		Right = rr.Right,
	},
	Weights = {
		LeftOnMag = { { t = 0, w = 0 }, { t = 0.35, w = 1 }, { t = 1.62, w = 1 }, { t = 1.85, w = 0 }, { t = 3.0, w = 0 } },
		RightOnBolt = rr.Weight,
	},
	Hidden = { Mag = { 0.78, 0.95 } },
	Events = { { t = 0.5, name = "MagOut" }, { t = 1.6, name = "MagIn" }, { t = 2.25, name = "Rack" } },
}
WeaponClips.Sniper = Sniper
WeaponClips.Longshot = Sniper

WeaponClips.Sentinel = withInspect(MarksmanInspect)

-- ─── ER-04 Arc (energy) ──────────────────────────────────────────────────────────────────────
-- No magazine. Vent (stretched to the overheat lock or the manual vent time): the rifle turns
-- to open its side vents, shudders while the heat bleeds out, then turns back.
local Energy = withInspect(EnergyInspect)
Energy.Vent = {
	Length = 1.0,
	Tracks = {
		Gun = {
			key(0),
			key(0.14, V(-0.04, 0.05, 0.07), V(10, -18, -34)),
			key(0.22, V(-0.04, 0.06, 0.08), V(12, -18, -36)),
			key(0.28, V(-0.04, 0.045, 0.07), V(10, -18, -33)),
			key(0.34, V(-0.04, 0.06, 0.08), V(12, -18, -36)),
			key(0.4, V(-0.04, 0.05, 0.07), V(10, -18, -34)),
			key(0.78, V(-0.04, 0.05, 0.07), V(10, -18, -34)),
			key(0.92, V(0, 0.006, -0.006), V(-1, 0, 0.8)),
			key(1.0),
		},
	},
	Weights = { LeftOnMag = { { t = 0, w = 0 }, { t = 1, w = 0 } } },
	Events = {},
}
WeaponClips.Energy = Energy
WeaponClips.Arc = Energy
WeaponClips.InspectStyles = { Rifle = Rifle.Inspect, Compact = CompactInspect, Heavy = HeavyInspect, Marksman = MarksmanInspect, Energy = EnergyInspect }

-- ─── VK-7 balisong ────────────────────────────────────────────────────────
local Knife = {}
Knife.Equip = {
	Length = 0.32,
	Tracks = {
		Hand = {
			key(0, V(0.15, -0.55, 0.25), V(-60, 20, 30)),
			key(0.2, V(0, 0.02, 0), V(8, 0, -4)),
			key(0.32),
		},
		Blade = { ang(0, 180), ang(0.07, 180), ang(0.2, -14), ang(0.27, 4), ang(0.32, 0) },
		Bite = { ang(0, 0), ang(0.1, -50), ang(0.19, 12), ang(0.32, 0) },
	},
	Events = { { t = 0.02, name = "Equip" }, { t = 0.12, name = "Flip" } },
}
Knife.Unequip = {
	Length = 0.14,
	Tracks = { Hand = { key(0), key(0.14, V(0.1, -0.55, 0.2), V(-40, 0, 20)) } },
	Events = {},
}
-- quick slash, right -> left (Strike event = server hit request + swing sound)
Knife.Slash1 = {
	Length = 0.42,
	Tracks = {
		Hand = {
			key(0),
			key(0.07, V(0.22, 0.14, 0.12), V(25, -30, -40)),
			key(0.17, V(-0.48, -0.18, -0.18), V(-10, 55, 35)),
			key(0.26, V(-0.42, -0.22, -0.1), V(-14, 50, 30)),
			key(0.42),
		},
		Left = { key(0), key(0.12, V(-0.04, -0.05, 0.08), V(0, 0, 0)), key(0.42) },
	},
	Events = { { t = 0.07, name = "Strike" } },
}
-- backhand slash, left -> right
Knife.Slash2 = {
	Length = 0.42,
	Tracks = {
		Hand = {
			key(0),
			key(0.07, V(-0.25, 0.12, 0.06), V(20, 40, 40)),
			key(0.17, V(0.32, -0.2, -0.2), V(-12, -50, -30)),
			key(0.26, V(0.3, -0.24, -0.12), V(-14, -45, -28)),
			key(0.42),
		},
		Left = { key(0), key(0.12, V(-0.04, -0.05, 0.08), V(0, 0, 0)), key(0.42) },
	},
	Events = { { t = 0.07, name = "Strike" } },
}
-- heavy stab: wind up, thrust to centre, recover
Knife.Stab = {
	Length = 0.65,
	Tracks = {
		Hand = {
			key(0),
			key(0.2, V(0.1, 0.06, 0.28), V(-8, 4, -10)),
			key(0.3, V(-0.2, 0.05, -0.62), V(-22, 12, 0)),
			key(0.37, V(-0.19, 0.04, -0.58), V(-22, 12, 0)),
			key(0.65),
		},
		Left = { key(0), key(0.2, V(0.02, -0.02, 0.1)), key(0.3, V(-0.03, -0.08, 0.05)), key(0.65) },
	},
	Events = { { t = 0.2, name = "Strike" } },
}
-- butterfly-knife flourish: wrist flicks drive two rollovers, a reverse flip and a twirl catch
Knife.Inspect = {
	Length = 2.3,
	Tracks = {
		Hand = {
			key(0),
			key(0.25, V(-0.18, 0.14, -0.05), V(20, 25, 60)),
			key(0.45, V(-0.16, 0.08, -0.05), V(-6, 35, 100)),
			key(0.62, V(-0.15, 0.13, -0.05), V(28, 25, 55)),
			key(0.8, V(-0.15, 0.09, -0.05), V(-4, 32, 105)),
			key(0.95, V(-0.15, 0.13, -0.05), V(24, 25, 62)),
			key(1.1, V(-0.14, 0.14, -0.04), V(30, 22, 58)),
			key(1.25, V(-0.13, 0.08, -0.04), V(0, 30, 112)),
			key(1.45, V(-0.12, 0.14, -0.05), V(38, 20, 60)),
			key(1.6, V(-0.11, 0.1, -0.04), V(18, 18, 40)),
			key(1.75, V(-0.09, 0.07, -0.03), V(8, 12, 26)),
			key(2.05, V(0.02, 0, 0), V(-6, -4, 4)),
			key(2.3),
		},
		Blade = {
			ang(0, 0), ang(0.25, 0), ang(0.45, -90), ang(0.62, -180), ang(0.8, -280), ang(0.95, -360),
			ang(1.1, -360), ang(1.25, -250), ang(1.45, -90), ang(1.6, 0), ang(1.75, 40), ang(1.95, 0), ang(2.3, 0),
		},
		Bite = {
			ang(0, 0), ang(0.25, 0), ang(0.45, -140), ang(0.62, -200), ang(0.8, -330), ang(0.95, -360),
			ang(1.1, -360), ang(1.25, -300), ang(1.45, -120), ang(1.6, 0), ang(1.75, 25), ang(1.95, 0), ang(2.3, 0),
		},
	},
	Events = {
		{ t = 0.4, name = "Flip" },
		{ t = 0.78, name = "Flip" },
		{ t = 1.28, name = "Flip" },
		{ t = 1.58, name = "Catch" },
	},
}
WeaponClips.Balisong = Knife -- kept for the old VK-7 asset

-- ─── Combat Knife (fixed blade) ──────────────────────────────────────────────────────────────────────
-- No hinges. Hand = wrist / arm motion, Spin = the knife rolling in the fingers about its blade
-- axis (degrees in r.Z), Left = support hand. Slashes keep the VK-7 timings the server validates.
local Combat = {}
Combat.Equip = {
	Length = 0.34,
	Tracks = {
		Hand = {
			key(0, V(0.12, -0.6, 0.3), V(-70, 15, 35)),
			key(0.16, V(0.04, -0.12, 0.08), V(-20, 8, 10)),
			key(0.26, V(0, 0.025, -0.01), V(6, -2, -4)),
			key(0.34),
		},
		Spin = { ang(0, -200), ang(0.2, -20), ang(0.27, 6), ang(0.34, 0) },
	},
	Events = { { t = 0.02, name = "Equip" } },
}
Combat.Unequip = Knife.Unequip
Combat.Slash1 = Knife.Slash1
Combat.Slash2 = Knife.Slash2
-- heavy stab: draw back with the edge turned, drive to centre, twist out
Combat.Stab = {
	Length = 0.65,
	Tracks = {
		Hand = {
			key(0),
			key(0.2, V(0.12, 0.08, 0.3), V(-10, 6, -14)),
			key(0.3, V(-0.2, 0.05, -0.64), V(-24, 12, 0)),
			key(0.38, V(-0.19, 0.04, -0.6), V(-24, 12, 0)),
			key(0.65),
		},
		Spin = { ang(0, 0), ang(0.3, 0), ang(0.4, 35), ang(0.55, 0), ang(0.65, 0) },
		Left = Knife.Stab.Tracks.Left,
	},
	Events = { { t = 0.2, name = "Strike" } },
}
-- inspect 2.4 s: present the flat, roll to the other flat, thumb along the spine, then a
-- full roll through the fingers and a reverse-grip flick back to the ready hold
Combat.Inspect = {
	Length = 2.4,
	Tracks = {
		Hand = {
			key(0),
			key(0.3, V(-0.2, 0.14, -0.06), V(18, 30, 62)),
			key(0.8, V(-0.21, 0.15, -0.06), V(20, 32, 66)),
			key(1.15, V(-0.16, 0.12, -0.05), V(26, -24, 40)),
			key(1.4, V(-0.16, 0.13, -0.05), V(28, -26, 42)),
			key(1.6, V(-0.08, 0.08, -0.04), V(10, 6, 20)),
			key(1.95, V(-0.06, 0.07, -0.03), V(8, 4, 18)),
			key(2.15, V(0.02, 0, 0), V(-6, -4, 4)),
			key(2.4),
		},
		Spin = {
			ang(0, 0), ang(0.3, 0), ang(0.8, 0), ang(1.15, 180), ang(1.4, 180),
			ang(1.6, 180), ang(1.95, 540), ang(2.15, 720), ang(2.4, 720),
		},
	},
	Events = { { t = 1.0, name = "Flip" }, { t = 1.75, name = "Flip" }, { t = 2.12, name = "Catch" } },
}
WeaponClips.Knife = Combat

-- ─── sampling ─────────────────────────────────────────────────────────────
local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end
WeaponClips.Smooth = smooth

local function sampleKeys(keys, t: number): (Vector3, Vector3)
	if t <= keys[1].t then
		return keys[1].p, keys[1].r
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.t then
			local u = smooth((t - a.t) / math.max(1e-6, b.t - a.t))
			return a.p:Lerp(b.p, u), a.r:Lerp(b.r, u)
		end
	end
	local last = keys[#keys]
	return last.p, last.r
end
WeaponClips.SampleKeys = sampleKeys

function WeaponClips.ToCFrame(p: Vector3, r: Vector3): CFrame
	return CFrame.new(p) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

local function sampleWeight(k, t: number): number
	local w = k[#k].w
	for i = 2, #k do
		if t <= k[i].t then
			local u = smooth(math.clamp((t - k[i - 1].t) / math.max(1e-6, k[i].t - k[i - 1].t), 0, 1))
			return k[i - 1].w + (k[i].w - k[i - 1].w) * u
		end
	end
	return w
end

function WeaponClips.Sample(clip, t: number)
	local pose = { Tracks = {}, Weights = {}, Hidden = {}, Raw = {} }
	if clip.Tracks then
		for name, keys in clip.Tracks do
			local p, r = sampleKeys(keys, t)
			pose.Tracks[name] = WeaponClips.ToCFrame(p, r)
			pose.Raw[name] = r
		end
	end
	if clip.Weights then
		for name, k in clip.Weights do
			pose.Weights[name] = sampleWeight(k, t)
		end
	end
	if clip.Hidden then
		for name, span in clip.Hidden do
			pose.Hidden[name] = t >= span[1] and t < span[2]
		end
	end
	return pose
end

-- The clip set for a weapon id: its own set, else the set named by its config's ClipSet,
-- else the default rifle set for guns (so a new gun animates before it gets bespoke clips).
function WeaponClips.For(weaponId: string)
	local own = WeaponClips[weaponId]
	if type(own) == "table" and own ~= WeaponClips then
		return own
	end
	local Config = require(script.Parent.WeaponConfig)
	local w = Config.Weapons[weaponId]
	if w and w.ClipSet and WeaponClips[w.ClipSet] then
		return WeaponClips[w.ClipSet]
	end
	return if w and w.Kind == "Gun" then Rifle else nil
end

-- Map a replicated action ("Reload", "Slash1", ...) to a clip.
function WeaponClips.Get(weaponId: string, name: string)
	local set = WeaponClips.For(weaponId)
	return set and set[name]
end

return WeaponClips
