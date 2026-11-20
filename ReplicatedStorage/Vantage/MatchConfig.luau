--[[
	VANTAGE — MatchConfig (shared)
	Modes, phase timings and sounds for the match-start flow (MatchService on the server,
	MainMenu + MatchHud on the client).

	Phases (ReplicatedStorage.Vantage.Match attribute "Phase"), all decided by the server:
	  Idle       no match running; DEPLOY queues you
	  Found      MATCH FOUND (teams assigned)                    FoundTime
	  Deploy     dropship clip; ends when every player is Ready (or DeployTimeout)
  Intro      operative introductions on the map: everyone spawned, held in formation (Intro.*)
	  Prep       spawned in the spawn zone, no damage            PrepTime
	  Countdown  3 · 2 · 1, no damage                            CountdownTime
	  Live       combat on, match clock running                  Mode.Length
	  Ended      result screen, then everyone back to the menu   EndTime
	PhaseEnds is a workspace:GetServerTimeNow() timestamp, so every client counts to the same moment.
]]

local MatchConfig = {}

MatchConfig.FoundTime = 4.5
MatchConfig.DeployMinTime = 3 -- the server never cuts a deploy shorter than this
MatchConfig.DeployTimeout = 25 -- slow loaders: start without waiting past this
MatchConfig.PrepTime = 8 -- was 15: the operative introduction now fills the wait before it
MatchConfig.CountdownTime = 3
-- 2026-11-18: the Ended phase now carries the full directed results sequence (VantageMatchResults):
-- end wash -> VICTORY / DEFEAT -> MVP reveal -> full scoreboard + match rewards -> lobby.
-- Players can leave early with CONTINUE / PLAY AGAIN (MatchRequest "Leave").
MatchConfig.EndTime = 28

-- the spawn area players are held in during Prep: the box around a team's SpawnLocations,
-- grown by this many studs on X/Z
MatchConfig.SpawnZonePad = 16

-- playtesting: anyone in the queue can start the match with whoever is queued
MatchConfig.AllowSkip = true

-- Folder = the contract: the map in play is always Workspace.Map_LiveFire (every system reads it).
-- Name = fallback label only; the real one is published as Match attribute MapName.
MatchConfig.Map = { Folder = "Map_LiveFire", Name = "LIVE FIRE" }

-- ─── maps + map vote (2026-11-18) ──────────────────────────────────────────────────────────
-- Every map waits in ServerStorage.VantageMaps under its Store name. MapService (server) moves
-- the voted map into Workspace, renames it to Map.Folder and moves the previous one back.
-- Lighting = preset in Vantage.MapLighting (applied on each client when it leaves the lobby).
-- Preview = 16:9 image asset id for the MATCH FOUND vote card (0 = name card only).
-- Enabled = false keeps a map out of every vote. Per mode, Modes.<id>.Maps = { ids } limits
-- the pool; without it every enabled map can come up.
MatchConfig.Maps = {
	{ Id = "LIVEFIRE", Name = "LIVE FIRE", Store = "Map_LiveFire", Lighting = "livefire", Theme = "Coral Arena", Size = "Medium", Preview = 0, Enabled = true },
	{ Id = "FOUNDRY", Name = "FOUNDRY ROW", Store = "Map_FoundryRow", Lighting = "foundry", Theme = "Industrial District", Size = "Large", Preview = 0, Enabled = true },
	{ Id = "PORTO", Name = "PORTO SOLE", Store = "Map_PortoSole", Lighting = "porto", Theme = "Mediterranean Coast", Size = "Large", Preview = 0, Enabled = true },
	{ Id = "MERIDIAN", Name = "MERIDIAN", Store = "Map_Meridian", Lighting = "meridian", Theme = "Downtown District", Size = "Large", Preview = 0, Enabled = true },
}
MatchConfig.DefaultMap = "LIVEFIRE" -- the map that sits in Workspace when the server starts

-- MATCH FOUND card: teams for Intro s, then the vote for Time s, then the winner for Reveal s.
-- Choices = how many maps go on the card. With one map in the pool there is no vote.
MatchConfig.MapVote = { Enabled = true, Intro = 3, Time = 10, Reveal = 3, Choices = 4 }

function MatchConfig.MapById(id: string?)
	for _, m in MatchConfig.Maps do
		if m.Id == id then
			return m
		end
	end
	return nil
end

-- Live = selectable now. TeamSize = players per team for a full match.
MatchConfig.Modes = {
	TDM = {
		Id = "TDM", Name = "6V6 DEATHMATCH", Short = "DEATHMATCH", TeamSize = 6, Live = true,
		ScoreLimit = 150, Length = 1200, -- 2026-11-20: official VANTAGESHOT TDM: first to 150, 20 minutes
		Overtime = true, -- tied at time: sudden death (next elimination wins)
		Objective = "Eliminate the enemy squad. First team to %d eliminations wins.",
	},
	-- Ranked queue (2026-11-17): Deathmatch rules, awards RP (RankedConfig / ProfileService)
	RTDM = {
		Id = "RTDM", Name = "RANKED DEATHMATCH", Short = "RANKED", TeamSize = 6, Live = true, Ranked = true,
		ScoreLimit = 50, Length = 600,
		Objective = "Ranked. Eliminate the enemy squad. First team to %d eliminations wins.",
	},
	TAC = {
		Id = "TAC", Name = "3V3 TACTICAL", Short = "TACTICAL", TeamSize = 3, Live = true, -- 2026-11-20: opened, same map pool as TDM
		ScoreLimit = 80, Length = 900, -- 2026-11-20: first to 80, 15 minutes
		Objective = "Hold your ground. First team to %d eliminations wins.",
	},
	DUEL = {
		Id = "DUEL", Name = "1V1 SHOOTOUT", Short = "SHOOTOUT", TeamSize = 1, Live = true, Sizes = { 1, 2 }, -- 2026-11-20: opened (1v1 / 2v2)
		ScoreLimit = 10, Length = 300,
		Objective = "One opponent. First to %d eliminations wins.",
	},
	CTF = {
		Id = "CTF", Name = "CAPTURE THE FLAG", Short = "CTF", TeamSize = 6, Live = false,
		ScoreLimit = 3, Length = 900,
		Objective = "Steal the enemy flag and return it to your base. %d captures wins.",
	},
}

-- ─── 2026-11-18: complete match system ──────────────────────────────────────────────────
-- Tied when the clock runs out (modes with Overtime = true): SUDDEN DEATH, the next elimination
-- wins. Still tied after Length seconds -> DRAW.
MatchConfig.Overtime = { Length = 120 }

-- Joining a running match (Hypershot-style backfill). Only while Live, never in overtime, only
-- with at least MinTimeLeft on the clock, only into the team with fewer players and never past
-- TeamSize. A player who disconnects and comes back gets their stats back (same match).
MatchConfig.Backfill = { Enabled = true, MinTimeLeft = 90 }

-- MVP (server-authoritative, MatchService). Combat rating =
--   Kill*K + Assist*A + Headshot*H + Damage*Dmg + Death*D (D is negative)
-- MVP = best rating on the winning team (on a draw: the whole lobby). Ties break on kills,
-- then fewer deaths, assists, damage, and finally the lower UserId, so it is deterministic.
MatchConfig.MVP = { Kill = 100, Assist = 45, Headshot = 20, Damage = 0.25, Death = -40 }

-- in-match callouts (VantageMatchEvents): kill-streak milestones and "match point" warnings
MatchConfig.Streaks = { [3] = "KILLING SPREE", [5] = "RAMPAGE", [7] = "UNSTOPPABLE", [10] = "LEGENDARY", [15] = "GODLIKE" }
MatchConfig.ScoreWarnings = { 10, 5, 1 } -- kills a team still needs
MatchConfig.TimeWarnings = { 300, 60, 10 } -- seconds left

-- results sequence timings (client, VantageMatchResults). Total must fit inside EndTime.
MatchConfig.Results = {
	Wash = 1.2, -- 2026-11-18: 0.9 -> 1.2 so the suck-back has room to build into the slam -- gameplay drains into the team tint
	Banner = 3.4, -- VICTORY / DEFEAT
	MVP = 6.0, -- MVP (and top performer) reveal
	Rewards = 4.8, -- Hypershot-style reward cards: +REQ / +ORD / +EXP (then the board)
	LeaveFade = 0.5,
	-- reward card art (844 x 1024, bg = scene with the subject removed, fg = subject cut-out on the
	-- same canvas). REQ / ORD reuse the approved shop pack art; XP is drawn until art is uploaded.
	Cards = {
		REQ = { Bg = 72255100879315, Fg = 113707123684396 }, -- req_m (shop)
		ORD = { Bg = 117469444201329, Fg = 91065177341025 }, -- ord_m drop pod (shop)
		XP = { Bg = 119922504751991, Fg = "" }, -- user's Gemini EXP card (single layer)
	},
	-- backdrop art (user's Gemini images 2026-11-18, 1600x900). Each is uploaded as two 800x900
	-- tiles { left, right } so it keeps full resolution (Roblox caps one image at 1024 px).
	Art = {
		VictoryBlue = { 113079649385897, 72909448964736 },
		VictoryRed = { 125945563181998, 124952590496747 },
		Defeat = { 121468946975751, 71379569492193 },
		MVP = { 79680194921875, 102770997646765 },
		Board = { 95136767677585, 97959994611708 },
	},
	-- reward emblems (MATCH REWARDS): REQ / ORD use their currency icons, XP = the user's XP emblem cut out
	Icons = { XP = 72244010799692 },

}

-- ─── 2026-11-20: team sizes 1v1 .. 6v6 for every mode, with map size per team size ─────────────
-- Every live mode can be queued at any size in its Sizes list (default 1..6). Each size is a
-- hidden variant mode "<Base>_<n>" (e.g. TDM_4) generated below with the size's TeamSize and a
-- score limit / length scaled to it, so the server (queue, bots, backfill) works unchanged.
-- Map size follows the team size (SizeClasses): MapService shrinks the play area of the voted map
-- for Small / Medium (boundary walls pulled in, spawns moved closer, dropship off).
MatchConfig.SizeClasses = {
	-- Axial = fraction of the spawn-to-spawn distance kept, Lateral = fraction of the map's width kept
	S = { Name = "SMALL", Sizes = { 1, 2 }, Axial = 0.42, Lateral = 0.6 },
	M = { Name = "MEDIUM", Sizes = { 3, 4 }, Axial = 0.7, Lateral = 0.85 },
	L = { Name = "LARGE", Sizes = { 5, 6 }, Axial = 1, Lateral = 1 },
}
function MatchConfig.SizeClass(teamSize: number): string
	if teamSize <= 2 then return "S" elseif teamSize <= 4 then return "M" end
	return "L"
end
MatchConfig.DefaultSizes = { 1, 2, 3, 4, 5, 6 }
function MatchConfig.BaseOf(modeId: string?): string?
	if type(modeId) ~= "string" then return nil end
	local m = MatchConfig.Modes[modeId]
	return m and m.Base or modeId
end
function MatchConfig.Variant(baseId: string, size: number?): string
	local base = MatchConfig.Modes[baseId]
	if not base or not size or size == base.TeamSize then return baseId end
	local id = baseId .. "_" .. size
	return if MatchConfig.Modes[id] then id else baseId
end
do
	local NAMES = { TDM = "DEATHMATCH", RTDM = "RANKED DEATHMATCH", TAC = "TACTICAL", DUEL = "SHOOTOUT" }
	local add = {}
	for id, m in MatchConfig.Modes do
		if m.Live and not m.Base then
			m.Sizes = m.Sizes or MatchConfig.DefaultSizes
			for _, n in m.Sizes do
				if n ~= m.TeamSize then
					local k = n / m.TeamSize
					local v = table.clone(m)
					v.Id = id .. "_" .. n
					v.Base = id
					v.Hidden = true
					v.TeamSize = n
					v.Name = n .. "V" .. n .. " " .. (NAMES[id] or m.Short)
					v.ScoreLimit = math.max(if m.ScoreLimit <= 10 then 5 else 10, math.floor(m.ScoreLimit * k / 5 + 0.5) * 5)
					v.Length = math.floor(m.Length * math.clamp(0.5 + 0.5 * k, 0.5, 1.15) / 60 + 0.5) * 60
					add[v.Id] = v
				end
			end
		end
	end
	for id, v in add do MatchConfig.Modes[id] = v end
end

function MatchConfig.Needed(modeId: string): number
	local m = MatchConfig.Modes[modeId]
	return if m then m.TeamSize * 2 else 0
end

function MatchConfig.Objective(modeId: string): string
	local m = MatchConfig.Modes[modeId]
	return if m then string.format(m.Objective, m.ScoreLimit) else ""
end

-- swap any of these for your own uploads
MatchConfig.Sounds = {
	SearchPing = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.12, Speed = 0.7 },
	Found = { Id = "rbxassetid://9125484367", Volume = 0.55, Speed = 1.1 }, -- deep hit + boom (ProSoundEffects)
	FoundPing = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Speed = 1.25 },
	Prep = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 0.9 },
	Tick = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.22, Speed = 1.6 },
	Count = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Speed = 1.0 },
	CountHit = { Id = "rbxassetid://1837830050", Volume = 0.45, Speed = 1.0 }, -- sub boom (APM)
	Live = { Id = "rbxassetid://9125484526", Volume = 0.8, Speed = 1.0 }, -- deep reverberant boom (ProSoundEffects)
	-- 2026-11-18 match events / results (ids already used elsewhere in the game)
	EndHit = { Id = "rbxassetid://9125484526", Volume = 0.7, Speed = 0.82 }, -- match over: the Live boom, lower
	Victory = { Id = "rbxassetid://9125484367", Volume = 0.75, Speed = 1.0 }, -- deep hit + boom
	VictoryPing = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Speed = 1.5 },
	Defeat = { Id = "rbxassetid://1837830050", Volume = 0.6, Speed = 0.7 }, -- sub boom, slowed
	MVP = { Id = "rbxassetid://9125484367", Volume = 0.6, Speed = 1.25 },
	Row = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.08, Speed = 2.2 },
	Reward = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 2.0 },
	Callout = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.28, Speed = 1.15 },
	Warn = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 0.8 },
	Respawn = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Speed = 1.3 },
	LivePing = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 1.5 },
	Zone = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 0.55 },

	-- 2026-11-18 results audio pass (VantageMatchResults). Licensed Roblox library audio only:
	-- APM Music + Pro Sound Effects (+ one free Daily Sounds riser/tick). Group = "Music" plays in
	-- VantageMusic (music volume setting), everything else in VantageEffects. Loop = looped bed,
	-- Hold = faded out with the results screen. Levels measured with AudioAnalyzer (RMS dB at vol 1).
	ResSuck = { Id = "rbxassetid://9039693361", Volume = 0.8 }, -- APM "Gobstopper Sucker" sub suck-back (peak 2.0 s, -11 dB)
	ResSlam = { Id = "rbxassetid://9125484367", Volume = 0.85, Speed = 0.95 }, -- PSE deep hit + boom
	ResBoom = { Id = "rbxassetid://1840977493", Volume = 0.5 }, -- APM "Explosive Hit 13" (long tail)
	ResFanfare = { Id = "rbxassetid://1836473422", Volume = 1.1, Group = "Music", Hold = true }, -- APM "Victory Fanfare Sting" (~5 s)
	ResCrowd = { Id = "rbxassetid://9120975130", Volume = 0.36, Hold = true }, -- PSE crowd cheers + pyro (12 s)
	ResFireworks = { Id = "rbxassetid://9114447104", Volume = 0.6 }, -- PSE fireworks whistler
	ResSparkle = { Id = "rbxassetid://9125635650", Volume = 0.42 }, -- PSE magical sparkle pass-by
	ResSparkleSoft = { Id = "rbxassetid://9125635430", Volume = 0.32 },
	ResDefeatSting = { Id = "rbxassetid://125909120236588", Volume = 0.75, Group = "Music", Hold = true }, -- APM "Mounting Consequences"
	ResPowerDown = { Id = "rbxassetid://96795857757261", Volume = 0.45 }, -- Daily Sounds power down
	ResDrawSting = { Id = "rbxassetid://9043812656", Volume = 0.8, Group = "Music", Hold = true }, -- APM "Over The Dunes" end sting
	ResWhoosh = { Id = "rbxassetid://9126229255", Volume = 0.42 }, -- PSE fast airy whoosh
	ResCrowdSurge = { Id = "rbxassetid://9120974515", Volume = 0.4 }, -- PSE crowd surge (5 s)
	ResCoinTick = { Id = "rbxassetid://130378474223829", Volume = 0.2 }, -- Daily Sounds coin pickup (count-up ticks)
	ResCoins = { Id = "rbxassetid://9113849583", Volume = 0.7 }, -- PSE multiple coins
	ResPrize = { Id = "rbxassetid://1839997938", Volume = 0.42, Group = "Music" }, -- APM "Correct Answer 3" rising sparkle
	ResRiser = { Id = "rbxassetid://94077390731779", Volume = 0.2 }, -- Daily Sounds cinematic riser (3.1 s)
	ResBedVictory = { Id = "rbxassetid://1839431755", Volume = 0.24, Group = "Music", Loop = true }, -- APM "Glorious Day"
	ResBedDefeat = { Id = "rbxassetid://9043813272", Volume = 0.34, Group = "Music", Hold = true }, -- APM "Stargazing Connection" end sting
	ResBedDraw = { Id = "rbxassetid://9046503137", Volume = 0.22, Group = "Music", Loop = true }, -- APM "Imminent Closure"
}

-- ─── operative introduction (phase "Intro", between Deploy and Prep) ─────────────────────────
-- Server: IntroService. Client: VantageWeaponClient.OperativeIntro. Set Enabled = false to go
-- straight from the dropship to Prep, exactly as before.
MatchConfig.Intro = {
	Enabled = true,
	Budget = 32, -- seconds for the whole sequence (6v6: 12 x ~2.1 s solos + 2 team shots); solo shots shrink to fit bigger matches
	ShotMin = 1.6, -- shortest solo shot (big matches)
	ShotMax = 4, -- longest solo shot (small matches)
	TeamShot = 2.6, -- each team's formation shot
	Lead = 1.2, -- black lead-in while characters land
	Tail = 0.5, -- fade back to first person
	-- animations the server deals out (never the same one twice on a team until all are used).
	-- Each name is a motion-capture clip module under VantageWeaponClient.OperativeIntro.Clips.
	Anims = { "Salute", "YellingOut", "Charge", "BatterOnDeck", "Punching" },
	-- Studio playtests only: pad each team with stand-in operatives up to this many per team,
	-- so 3v3 / 6v6 introductions can be watched alone. 0 = off. Never runs in a live server.
	StudioFill = 0, StudioHold = 0,
	-- intro music (client, VantageMusic SoundGroup). Its beat drop lands on the LAST squad shot,
	-- the moment everyone has been introduced, whatever the lobby size: for long intros (6v6)
	-- the build's identical bars (BuildStart..BuildEnd) are repeated before it, for short ones
	-- the track starts part-way into the build. The rest plays on through Prep and fades out
	-- when the match goes Live (battle music takes over). Id = "" -> no intro music.
	-- Times are seconds into the track file.
	Music = {
		Id = "rbxassetid://73338097854495", -- rbxassetid://... (or just the number)
		Volume = 0.6,
		Drop = 17.8, -- the beat drop
		BuildStart = 0.6, -- first impact of the loopable build bars
		BuildEnd = 14.36, -- end of the 4th build bar (the riser starts here)
		DropOffset = 0, -- + seconds after the last squad shot starts
		FadeIn = 0.8,
		FadeOut = 1.5,
	},
}

-- The timeline every client and the server derive from the same ordered list, so all players
-- see the same shots at the same moments. order = { { T = "Blue" | "Red", ... }, ... } sorted by
-- team. Returns segments { Kind = "Solo" | "Team", Index?, Team, Start, Dur } and the total.
function MatchConfig.IntroSchedule(order)
	local I = MatchConfig.Intro
	local teams, count = {}, {}
	for _, e in order do
		if not count[e.T] then
			count[e.T] = 0
			table.insert(teams, e.T)
		end
		count[e.T] += 1
	end
	local n = #order
	local shot = if n > 0 then math.clamp((I.Budget - #teams * I.TeamShot) / n, I.ShotMin, I.ShotMax) else 0
	local segs, t = {}, 0
	for _, team in teams do
		for i, e in order do
			if e.T == team then
				table.insert(segs, { Kind = "Solo", Index = i, Team = team, Start = t, Dur = shot })
				t += shot
			end
		end
		table.insert(segs, { Kind = "Team", Team = team, Start = t, Dur = I.TeamShot })
		t += I.TeamShot
	end
	return segs, t, shot
end

-- 2026-11-19 bot fill: from Prep on, every match tops each team up to full with SquadBots. A player
-- who joins mid-match takes a bot's place; one who leaves is replaced (no forfeits while bots fill).
-- SquadBots publishes Enabled as Workspace.LiveBots, the switch every live bot check reads.
MatchConfig.BotFill = {
	Enabled = true,
	PerTeam = nil, -- bots + players per team; nil = the mode's TeamSize (6 for TDM)
	Difficulty = "normal", -- easy | normal | hard
	InStudio = true, -- Studio playtests fill too (a /squad command replaces the fill)
	NameSuffix = " [BOT]",
}

return MatchConfig
