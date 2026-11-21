--[[
	VANTAGE CONTROL — config (shared)
	Lives in ReplicatedStorage.Vantage (static Rojo sync from src/shared; the client and
	the VantageControl server script both require it directly).

	ASSET IDS: each line's voice recording ("rbxassetid://<number>"). A line with Id = "" still shows
	its text in the VEYRA bar (timed from its length) — no placeholder sound is ever played.

	Priority: higher wins. A line at or above InterruptPriority cuts off anything lower that is
	speaking. Anything else waits (at most MaxDelay seconds) for the current line to finish, and is
	dropped if it goes stale. Cooldown = the same line never plays twice within this many seconds.
]]

local Config = {}

Config.Lines = {
	-- #1  once, when the player enters the deployment sequence (Phase "Deploy"); never on respawn
	Deployment = {
		Text = "Legionary, your deployment has been authorised.",
		Id = "rbxassetid://138518742424974", -- VC01_Deployment
		Priority = 70, Cooldown = 20, MaxDelay = 4,
	},
	-- #2  once, when the countdown ends and the match goes Live
	Engage = {
		Text = "Legionaries, deployment is authorised. Engage.",
		Id = "rbxassetid://122575397606556", -- VC02_Engage
		Priority = 75, Cooldown = 20, MaxDelay = 3,
	},
	-- #3  first enemy within ContactRange with line of sight (server), then ContactCooldown
	Contact = {
		Text = "Hostile contact ahead. Stay alert.",
		Id = "rbxassetid://70714299754640", -- VC03_Contact
		Priority = 10, Cooldown = 30, MaxDelay = 2,
	},
	-- #4  only when the server credits YOU with the elimination (Remotes.Elimination "Confirm")
	Kill = {
		Text = "Target eliminated. Move.",
		Id = "rbxassetid://75194901111082", -- VC04_Kill
		Priority = 30, Cooldown = 4, MaxDelay = 1.5,
	},
	-- #5  shield below CriticalFraction of max, once per damage cycle
	ShieldCritical = {
		Text = "Warning. Shield integrity critical.",
		Id = "rbxassetid://137520005272642", -- VC05_ShieldCritical
		Priority = 40, Cooldown = 3, MaxDelay = 1, Critical = true,
	},
	-- #6  shield reaches 0 — critical, interrupts ordinary lines
	ShieldFail = {
		Text = "Shield failure! Disengage!",
		Id = "rbxassetid://119277623888895", -- VC06_ShieldFail
		Priority = 85, Cooldown = 2, MaxDelay = 0.75, Critical = true,
	},
	-- #7  shield back to full after a real damage cycle
	ShieldRestored = {
		Text = "Shield systems restored.",
		Id = "rbxassetid://70475441521396", -- VC07_ShieldRestored
		Priority = 20, Cooldown = 6, MaxDelay = 2,
	},
	-- #8  the player dies (before the respawn / death replay sequence)
	Down = {
		Text = "Legionary down. Stand by for redeployment.",
		Id = "rbxassetid://92607946033167", -- VC08_Down
		Priority = 90, Cooldown = 3, MaxDelay = 1, Critical = true,
	},
	-- #9  your team falls LosingMargin behind (re-arms once the gap closes)
	Losing = {
		Text = "We're losing ground. Regroup immediately.",
		Id = "rbxassetid://72063270909383", -- VC09_Losing
		Priority = 50, Cooldown = 45, MaxDelay = 5,
	},
	-- #10 once, to the winning team only, when the match ends (never on a draw)
	Victory = {
		Text = "That's it, Legionaries. Battlefield secured.",
		Id = "rbxassetid://124240239181953", -- VC10_Victory
		Priority = 100, Cooldown = 20, MaxDelay = 3,
	},
	-- #11 every match player, when a dropship flyby is published (it is still outside the map then;
	--     the hooks open ~15 s later). Source: AircraftService -> Vantage.Aircraft attribute FlightId
	AircraftInbound = {
		Text = "Legionaries, aerial transport inbound. Grapple systems ready.",
		Id = "rbxassetid://113634181329656", -- VC11_AircraftInbound
		Priority = 60, Cooldown = 20, MaxDelay = 6,
	},
}

-- ─── VEYRA comms bar (client) ───────────────────────────────────────────────
Config.Bar = {
	Enabled = true,
	Speaker = "VEYRA",
	Portrait = "rbxassetid://74127369409424",
	Top = 150, -- px from the top at 1080p: under the score / compass, well above the crosshair
	PrepGap = 12, -- while the PREPARE FOR COMBAT panel is up, the bar sits this far under it
	MaxWidth = 900, -- px at 1080p (long lines wrap)
	Height = 56,
	TextSize = 24,
	NameFont = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	TextFont = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium),
	Lime = Color3.fromRGB(182, 255, 0), -- VantageShot lime
	Critical = Color3.fromRGB(255, 72, 64), -- accent for Critical lines
	Background = Color3.fromRGB(14, 19, 16),
	BackgroundTransparency = 0.2,
	TypeShare = 0.85, -- the text finishes typing at 85% of the voice clip
	CharTime = 0.05, -- seconds per character when there is no voice clip to sync to
	Hold = 1.6, -- seconds the finished message stays after the voice ends
	FadeIn = 0.18,
	FadeOut = 0.35,
	DisplayOrder = 40, -- above the match HUD and the deploy clip
}

-- prints every play / cut / queue / drop decision to Output (handy while testing)
Config.Debug = false

-- lines at or above this cut off a lower line that is still speaking
Config.InterruptPriority = 80

-- ─── trigger tuning (server) ─────────────────────────────────────────────────
Config.ContactRange = 110 -- studs
Config.ContactLineOfSight = true -- require a clear raycast to the enemy
Config.ContactCooldown = 30 -- seconds between contact calls for one player
Config.ContactClear = 10 -- no enemy in range for this long = the next sighting is a "first" contact again
Config.ContactGrace = 2 -- seconds after Engage before contact can be called (lets Engage finish)
Config.ContactScanRate = 0.4 -- seconds between scans

Config.CriticalFraction = 0.25 -- #5 below 25% of MaxShield
Config.CriticalRearmFraction = 0.5 -- the critical warning re-arms once the shield climbs back above 50%
Config.RestoreAfterBelow = 0.75 -- #7 only if the shield fell below 75% this cycle (no "restored" for a scratch)

Config.LosingMargin = 3 -- #9 enemy leads by at least this many points
Config.LosingRearmAt = 1 -- re-arms when the gap is back to this or less
Config.LosingEscalate = 5 -- already behind: call again if the gap grows by this much more (after Cooldown)

-- VEYRA stays silent during matches unless this is true (the client's match-comms gate reads it)
Config.MatchComms = false

-- ─── radio sound (client) ────────────────────────────────────────────────────
Config.Radio = {
	Volume = 1.4, -- per line, inside the VantageControl SoundGroup
	GroupVolume = 1,
	Equalizer = { LowGain = -16, MidGain = 3, HighGain = -9, MidRange = NumberRange.new(380, 3800) },
	Distortion = 0.08,
	Compressor = { Threshold = -18, Ratio = 3, Attack = 0.005, Release = 0.12, GainMakeup = 4 },
	-- other SoundGroups are gently ducked while Control speaks (side-chain compressor; volume
	-- sliders are untouched). Empty the list to turn ducking off.
	DuckGroups = { "VantageWeapon", "VantageEffects", "VantageMusic" },
	Duck = { Threshold = -34, Ratio = 3.5, Attack = 0.02, Release = 0.35 },
	Squelch = { Enabled = true, Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.12, Speed = 2.2, Lead = 0.06 },
	FadeOut = 0.08, -- seconds, when a line is cut off
}

return Config
