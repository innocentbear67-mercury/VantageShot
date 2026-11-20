--[[
	VANTAGE — Variants (shared), 2026-11-17
	Weapon variants: earned sidegrades unlocked by weapon mastery (MasteryConfig.VariantLevels: 10, 25).
	Each weapon has its Standard version plus two variants; every variant trades some stats for one
	passive trait. Plan: project doc weapon-progression-proposal.md.

	Single source for names, trait text and the display stat bars used by the Mastery screen and the
	Loadout version picker. Gameplay overrides (config deltas + trait hooks) are added per variant when
	each trait ships; until then a variant only exists in the UI.
	A weapon with no entry here (e.g. a new crate weapon) simply has no variants yet.

	Display stats are 0–100 bars in the order Variants.StatKeys (UI only, not gameplay numbers).
]]
local Variants = {}

Variants.StatKeys = { "Damage", "Fire rate", "Range", "Accuracy", "Mobility", "Magazine" }

Variants.Standard = {
	Vanguard = { Blurb = "The all-rounder. Forgiving at every range.", Stats = { 55, 80, 65, 85, 70, 62 } },
	Sentinel = { Blurb = "Three-round burst with a 2x scope.", Stats = { 60, 60, 78, 82, 66, 66 } },
	Spectre = { Blurb = "Fast semi-auto sidearm with quick swaps.", Stats = { 62, 52, 45, 70, 85, 34 } },
	Breacher = { Blurb = "Pump shotgun. Two shots up close.", Stats = { 90, 20, 22, 40, 62, 16 } },
	Longshot = { Blurb = "Bolt-action sniper. One headshot kills.", Stats = { 98, 12, 100, 90, 50, 14 } },
	Arc = { Blurb = "Energy rifle. Heat instead of ammo.", Stats = { 50, 76, 72, 80, 70, 60 } },
	Knife = { Blurb = "Combat knife. Backstabs hit hardest.", Stats = { 45, 50, 8, 100, 100, 0 } },
	Riptide = { Blurb = "Bullet-hose SMG. Melts up close, fades past 25 studs.", Stats = { 48, 96, 30, 66, 90, 58 } },
	Bulwark = { Blurb = "Rotary LMG. A 100-round belt to hold a lane.", Stats = { 50, 74, 70, 60, 40, 100 } },
	Verdict = { Blurb = "Six-shot hand cannon. Two headshots kill.", Stats = { 84, 24, 60, 82, 80, 12 } },
	Quill = { Blurb = "Crossbow. One bolt to the body kills.", Stats = { 100, 8, 85, 88, 64, 4 } },
	Helix = { Blurb = "Beam rifle. Constant damage, no ammo, heat.", Stats = { 36, 100, 42, 92, 72, 60 } },
	Havoc = { Blurb = "Grenade launcher. Four heavy rounds per drum.", Stats = { 92, 16, 50, 46, 56, 8 } },
}

Variants.ByWeapon = {
	Vanguard = {
		{ Id = "Cadence", Name = "Cadence", Code = "VX-01R", Index = 1, Trait = "Cadence",
			Blurb = "After 4 hits in a row, bloom per shot halves until you miss.", Short = "Hit streaks tighten spread",
			Stats = { 55, 72, 65, 92, 70, 55 } },
		{ Id = "Bastion", Name = "Bastion", Code = "VX-01H", Index = 2, Trait = "Brace",
			Blurb = "Standing still or crouching cuts recoil by 30%. Heavy long-range rifle.", Short = "Heavy long-range rifle",
			Stats = { 68, 60, 82, 80, 62, 52 } },
	},
	Sentinel = {
		{ Id = "Headhunter", Name = "Headhunter", Code = "BR-07H", Index = 1, Trait = "Headhunter",
			Blurb = "A burst that opens with a headshot recovers faster.", Short = "Head-led bursts recover faster",
			Stats = { 58, 60, 78, 82, 66, 52 } },
		{ Id = "Marksman", Name = "Marksman", Code = "BR-07M", Index = 2, Trait = "Steady",
			Blurb = "Shots 0.35 s or more apart have no bloom. Semi-auto marksman rifle.", Short = "Semi-auto marksman rifle",
			Stats = { 80, 40, 85, 88, 66, 30 } },
	},
	Spectre = {
		{ Id = "Disruptor", Name = "Disruptor", Code = "PX-9D", Index = 1, Trait = "Disruptor rounds",
			Blurb = "1.5x damage to shields, 0.75x to health. Breaks shields fast.", Short = "Breaks shields fast",
			Stats = { 62, 52, 45, 70, 85, 30 } },
		{ Id = "Quickdraw", Name = "Quickdraw", Code = "PX-9A", Index = 2, Trait = "Quickdraw",
			Blurb = "Full-auto. 0.12 s swap; half the magazine refills after 3 s holstered.", Short = "Full-auto, instant swap",
			Stats = { 42, 90, 30, 62, 90, 46 } },
	},
	Breacher = {
		{ Id = "Kinetic", Name = "Kinetic", Code = "SG-12K", Index = 1, Trait = "Kinetic Loader",
			Blurb = "Each slide loads a shell. Wider spread, shorter range.", Short = "Slides load a shell",
			Stats = { 90, 20, 18, 34, 70, 12 } },
		{ Id = "Slug", Name = "Slug", Code = "SG-12S", Index = 2, Trait = "Choke",
			Blurb = "Fires one slug. The first shot after 0.8 s idle has zero spread.", Short = "Single-slug mid-range",
			Stats = { 80, 18, 60, 75, 62, 12 } },
	},
	Longshot = {
		{ Id = "Tempo", Name = "Tempo", Code = "SR-88T", Index = 1, Trait = "Clean Shot",
			Blurb = "A headshot kill rechambers instantly. Loses power past 300 studs.", Short = "Headshot kills rechamber",
			Stats = { 90, 12, 80, 90, 58, 10 } },
		{ Id = "Recon", Name = "Recon", Code = "SR-88R", Index = 2, Trait = "Follow-up",
			Blurb = "Semi-auto. A headshot within 2 s of a body hit kills.", Short = "Body, then head, kills",
			Stats = { 70, 28, 95, 85, 52, 20 } },
	},
	Arc = {
		{ Id = "Capacitor", Name = "Capacitor", Code = "ER-04C", Index = 1, Trait = "Heat Sink",
			Blurb = "Every hit vents 60% of its own heat. Accurate players fire longer.", Short = "Hits vent heat",
			Stats = { 54, 70, 76, 82, 70, 60 } },
		{ Id = "Overcharge", Name = "Overcharge", Code = "ER-04O", Index = 2, Trait = "Overcharge",
			Blurb = "Hold fire for 0.6 s to release a charged bolt that costs 35% heat.", Short = "Hold fire for a charged bolt",
			Stats = { 50, 70, 72, 80, 70, 60 } },
	},
	Knife = {
		{ Id = "Balisong", Name = "Balisong", Code = "CK-3B", Index = 1, Trait = "Flow",
			Blurb = "A hit within 0.6 s of the last one makes the next swing 20% faster.", Short = "Quick follow-ups swing faster",
			Stats = { 40, 62, 8, 100, 100, 0 } },
		{ Id = "Hardlight", Name = "Hardlight", Code = "CK-3H", Index = 2, Trait = "Lunge",
			Blurb = "The heavy attack lunges up to 6 studs toward the enemy you aim at.", Short = "Heavy attack lunges",
			Stats = { 38, 50, 20, 100, 100, 0 } },
	},
}

function Variants.Get(weaponId: string, index: number?)
	local list = Variants.ByWeapon[weaponId]
	return list and index and list[index] or nil
end

function Variants.Name(weaponId: string, index: number?): string
	local v = Variants.Get(weaponId, index)
	return if v then v.Name else "Standard"
end

return Variants
