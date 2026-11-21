--[[
	VANTAGE — ShieldConfig (shared)
	Simple energy shield: absorbs damage before health, recharges after a pause without damage.
	Kept deliberately small so it can be extended later (shield break FX, overshields, per-mode
	values, recharge sounds...). Server: WeaponServer.ShieldService. Client HUD reads the
	replicated character attributes below.

	Character attributes (server-set, replicated):
		Shield      current shield points
		MaxShield   maximum shield points
		ShieldBrokenAt  server time of the last break (0..1 clients can use it for FX)
		ShieldRecharging  true while the server is refilling the shield; written only on start / stop
		                  (false + Shield = MaxShield -> complete, false + Shield < MaxShield -> interrupted)
]]

return {
	Enabled = true,
	MaxShield = 100,       -- on top of Humanoid.MaxHealth (100)
	RegenDelay = 3,        -- seconds without taking damage before recharge starts
	RegenRate = 45,        -- shield points per second while recharging (0 -> full in ~2.2 s)
	TickRate = 10,         -- server recharge updates per second
	-- true: damage that breaks the shield does NOT carry over into health (one "free" pop).
	-- false: overflow carries into health (simple, default).
	BreakAbsorbsOverflow = false,

	-- look of the shield (client: VantageWeaponClient.ShieldFX). Stages follow Shield / MaxShield.
	Visual = {
		-- Halo-style: the energy skin is INVISIBLE at rest (full, damaged or waiting out RegenDelay).
		-- It shows only (a) while ShieldRecharging is true, (b) as a short flare where a hit lands,
		-- (c) for the break burst. Recharge sequence: forms (flicker in + small arcs on the armour),
		-- shimmers with pulses flowing over the suit, then flashes once and fades on completion;
		-- damage interrupts it with a quick fade and no completion flash.
		Recharge = {
			Level = 0.82, -- 0..1 strength of the steady shimmer while recharging (1 = brightest)
			FilmClear = 0.04, -- film transparency at strength 1 (ForceField is faint even at 0)
			FormTime = 0.32, -- seconds the field takes to flicker into place
			PulseEvery = 0.9, -- seconds between pulses flowing up the body (3P) / down the arms (1P)
			PulseTime = 0.42, -- seconds one pulse takes to cross the body
			PulseBoost = 0.45, -- extra strength under a pulse
			StartArcs = 4, -- small surface arcs while the field forms
			ArcGap = { 0.45, 1.1 }, -- seconds between occasional arcs while recharging
			ArcWidth = 0.028, -- third person (first person uses a third of this)
			CompleteFlash = 0.14, -- seconds of the completion intensify (bright, whitened)
			CompleteFade = 0.55, -- seconds to fade back to invisible after it
			InterruptFade = 0.16, -- seconds to fade out when damage interrupts the recharge
			HitFlash = 0.22, -- seconds a hit lights the (otherwise invisible) skin
			HexWorld = 0.15, -- other players' honeycomb strength relative to the film (0 = off)
			HexFirstPerson = 0.8, -- your arm-surface hex tiles relative to the film (0 = off)
		},
		MeshPadding = 0.07, -- studs the field stands off each exosuit armour piece (third person)
		DamagedBelow = 0.66, -- FULL above this, DAMAGED below
		CriticalBelow = 0.33, -- CRITICAL below this, BROKEN at 0
		Padding = 0.09, -- studs the energy skin stands off the body
		MaxDistance = 220, -- skins further from the camera than this are not drawn
		Transparency = { Full = 0.45, Damaged = 0.3, Critical = 0.2 }, -- ForceField skin (1 = invisible; ForceField is faint even at 0)
		-- hexagonal layers: every shielded body part wears a hexagonal prism of glowing honeycomb
		-- panels (first person: two nested prisms over each arm segment). Image = a seamless hex
		-- grid from the Creator Store (asset 3423005102 by THAIRIN); Fallback = the visor's own
		-- single hex cell, used if the first ever stops loading.
		Hex = {
			Enabled = true,
			Image = "rbxassetid://3423005094",
			Fallback = "rbxassetid://136242431632482",
			MaxDistance = 90, -- other players' honeycomb is only drawn this close (the film goes further)
			World = { { Pad = 0.14, Rot = 0, Cell = 0.5, Bright = 2.2, Alpha = 0.3 } },
			-- first person: single hexagon tiles laid on the surface of each arm armour piece
			-- (positions in Shield.ShieldHexData), so the honeycomb follows the shape of the
			-- forearms, gauntlets and hands. Tile = the visor's own hex cell image.
			Tile = "rbxassetid://136242431632482",
			TileAlpha = 0.08, -- image transparency of a tile at full shield
			TileBright = 2.6,
			RaisedEvery = 3, -- every Nth tile floats a little higher and dimmer: the second layer
			RaisedLift = 0.03,
			RaisedAlpha = 0.45,
		},
		-- your own shield in first person: the same skin over the viewmodel's arms and hands
		-- (never the gun), thinner and fainter so it does not get in the way of aiming
		FirstPerson = {
			Enabled = true,
			Padding = 0.016, -- studs the film stands off the arm armour (viewmodel scale)
			OuterPadding = 0.05, -- a second, fainter film further out: the shield reads as layers hugging the arm
			Transparency = { Full = 0.3, Damaged = 0.2, Critical = 0.12 },
			PulseEvery = 3.6, -- seconds between the small pulses that run down the arms at full shield
		},
		Colors = {
			-- blue since 2026-11-10 (the key names are historical: Lime = the shield's main colour)
			Lime = Color3.fromRGB(64, 170, 255),
			White = Color3.fromRGB(214, 240, 255),
			Arc = Color3.fromRGB(130, 205, 255),
		},
		Sounds = { -- licensed library sounds already used in Vantage; StartAt skips silent lead-ins
			Hit = {
				{ Id = "rbxassetid://98609496290942", Volume = 0.3, StartAt = 0.03, Speed = 1.55 },
				
			},
			Break = {
				{ Id = "rbxassetid://9114315137", Volume = 0.6, StartAt = 0.17 },
				{ Id = "rbxassetid://9114592245", Volume = 0.22, StartAt = 0.42, Speed = 1.25 },
			},
			Recharge = { { Id = "rbxassetid://9125980435", Volume = 0.32, StartAt = 0.22, Speed = 1.2 } },
		},
	},
}
