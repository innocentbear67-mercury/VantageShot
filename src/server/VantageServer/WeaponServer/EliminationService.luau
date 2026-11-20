--[[
	VANTAGE — EliminationService (server)
	Decides who eliminated whom; the client is never asked. Only the hit that dealt the lethal
	damage counts (DamageService stamps "VantageKiller" on the victim). A death without one —
	fall, reset, suicide — is environmental: no kill credit, no streak, no replay.
	On a credited kill it advances the killer's streak (kills this life, reset when they die) and
	multikill count (kills each within MultiKillWindow of the previous; reset by a gap or death).
	Session stats (main menu MASTERY) are server-set Player attributes: SessionEliminations,
	SessionDeaths, SessionHeadshots — counted here, never by the client.
	The killer alone gets the full feedback ("Confirm": HUD, screen effect, announcer); everyone
	else gets only the small in-world effect ("World").
	It also holds the victim's respawn while their death replay plays: the client reports "Done"
	(Remotes.DeathReplay) and the server never waits past Replay.MaxRespawnDelay after the death,
	so a client can only end its own wait early, never lengthen it or affect anyone else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage.Vantage
local Config = require(Vantage.Weapons.WeaponConfig)
local ElimConfig = require(Vantage.Elimination.EliminationConfig)
local KillRemote = Vantage.Remotes.Elimination :: RemoteEvent
local ReplayRemote = Vantage.Remotes.DeathReplay :: RemoteEvent
local FeedRemote = Vantage.Remotes:WaitForChild("KillFeed") :: RemoteEvent
local WeaponEvent = Vantage.Remotes:WaitForChild("WeaponEvent") :: RemoteEvent
local FeedConfig = require(Vantage.Elimination.KillFeedConfig)
local VehicleConfig = require(Vantage.Vehicles.VehicleConfig)
local DamageService = require(script.Parent.DamageService)
-- REQ (main earned currency, 2026-11-14): credited here on every credited elimination
local Requisition = require(script.Parent.Parent:WaitForChild("Requisition"))
local Progression = require(script.Parent.Parent:WaitForChild("Progression"))
local Mastery = require(script.Parent.Parent:WaitForChild("Mastery")) -- weapon mastery (2026-11-17)
local ReqConfig = require(Vantage:WaitForChild("Requisition"):WaitForChild("RequisitionConfig"))
-- ULT (2026-11-18): the streak is mirrored to Player.KillStreak; every StreakPerCharge banks UltReady
local ULT_EVERY = 10
local ULT_ON = false -- 2026-11-20: killstreak ULT removed (UltConfig.Enabled)
pcall(function()
	local uc = require(Vantage:WaitForChild("Ult"):WaitForChild("UltConfig"))
	ULT_EVERY = uc.StreakPerCharge or 10
	ULT_ON = uc.Enabled == true
end)

-- SUPPLY SURGE (2026-11-18): random bonus cache on a credited elimination (ReqConfig.Surge)
local Ledger = require(script.Parent.Parent:WaitForChild("MatchLedger"))
local Ordnance = nil
pcall(function()
	Ordnance = require(script.Parent.Parent:WaitForChild("Ordnance", 5))
end)
local SurgeRemote = Vantage.Remotes:FindFirstChild("SupplySurge") :: RemoteEvent?
if not SurgeRemote then
	local r = Instance.new("RemoteEvent")
	r.Name = "SupplySurge"
	r.Parent = Vantage.Remotes
	SurgeRemote = r
end
local function rollSurge(p: Player, position: Vector3?, force: boolean?)
	local S = ReqConfig.Surge
	if not (S and S.Enabled ~= false and p and p.Parent) then
		return
	end
	if not force and not (RunService:IsStudio() and p:GetAttribute("ForceSurge") == true) then
		if math.random() >= (S.Chance or 0) then
			return
		end
	end
	local req = math.random(S.REQ.Min, S.REQ.Max)
	local od = if Ordnance then math.random(S.ORD.Min, S.ORD.Max) else 0
	-- the heal lands with the burst
	local heal = 0
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and (S.Heal or 0) > 0 then
		heal = math.floor(math.min(S.Heal, hum.MaxHealth - hum.Health))
		if heal > 0 then
			hum.Health += heal
		end
	end
	local delay = S.PayDelay or 2.9
	;(SurgeRemote :: RemoteEvent):FireClient(p, { Position = position, REQ = req, ORD = od, Heal = heal, Delay = delay, Title = S.Title })
	p:SetAttribute("SessionSurges", (tonumber(p:GetAttribute("SessionSurges")) or 0) + 1)
	-- paid when the ticks land in the counter, as one amber feed line (+ ORD chip)
	task.delay(delay, function()
		if not p.Parent then
			return
		end
		if Ordnance and od > 0 then
			Ordnance.Credit(p, od)
			Ledger.Add(p, "ORD", od)
		end
		Requisition.Award(p, { { Label = S.Label or "SUPPLY SURGE", Amount = req, Kind = "Surge" } }, { ORD = od, XP = 0 })
	end)
end
if RunService:IsStudio() then
	-- Studio: SurgeTest (any new value) = one surge now, 20 studs in front of the player
	local function hookSurge(p: Player)
		p:GetAttributeChangedSignal("SurgeTest"):Connect(function()
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local pos = r and (r.Position + r.CFrame.LookVector * 20 + Vector3.new(0, 1.5, 0))
			rollSurge(p, pos, true)
		end)
	end
	Players.PlayerAdded:Connect(hookSurge)
	for _, p in Players:GetPlayers() do
		hookSurge(p)
	end
end

-- vehicle weapon id -> { Kind = vehicle, Name = weapon display name }
local vehicleWeapons: { [string]: { Kind: string, Name: string } } = {}
for kind, v in VehicleConfig.Vehicles do
	if v.Weapon and v.Weapon.Id then
		vehicleWeapons[v.Weapon.Id] = { Kind = kind, Name = v.Weapon.DisplayName or kind }
	end
end

local EliminationService = {}
local streaks: { [Player]: number } = {}
local multis: { [Player]: { Count: number, Last: number } } = {}
local pending: { [Player]: { Character: Model, Deadline: number, Done: boolean } } = {}
local debugKillers: { [Model]: Model } = {} -- Studio tests: a training dummy eliminating someone

local function bump(p: Player, key: string)
	p:SetAttribute(key, (p:GetAttribute(key) or 0) + 1)
end

local function teamName(character: Model?, plr: Player?): string?
	if plr then
		return if plr.Team and not plr.Neutral then plr.Team.Name else nil
	end
	return character and character:GetAttribute("Team")
end

local function rootOf(m: Model?): BasePart?
	return m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- 2026-11-18 match system: a kill only earns credit (streak, score stats, REQ / ORD / XP) while
-- combat is on (match Live). Studio keeps training-dummy kills.
local function credits(killerPlayer: Player?, victim: Player?): boolean
	return killerPlayer ~= nil and (victim ~= nil or RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true) and DamageService.CombatEnabled()
end
local firstBloodFor = 0 -- MatchId that already had its first blood
local function matchId(): number
	return tonumber(DamageService.MatchFolder():GetAttribute("MatchId")) or 0
end

-- ─── kill feed ────────────────────────────────────────────────────────────────────────
local feedId = 0
local function who(model: Model?, plr: Player?)
	if plr then
		return { Name = plr.DisplayName, Team = teamName(model, plr), UserId = plr.UserId }
	end
	if model then
		local n = model:GetAttribute("DisplayName")
		return { Name = if type(n) == "string" then n else (FeedConfig.BotNames[model.Name] or model.Name), Team = teamName(model, nil) }
	end
	return nil
end

-- one entry per death, for everyone. Everything here is read from server state stamped by
-- DamageService / VehicleService / the map at the lethal moment — never from a client.
local function sendFeed(character: Model, victim: Player?, killerPlayer: Player?, killerModel: Model?, selfKill: boolean)
	feedId += 1
	local e: any = { Id = feedId, Victim = who(character, victim) }
	if killerModel then
		e.Killer = who(killerModel, killerPlayer)
		-- match callouts (VantageMatchEvents): first blood of the match, the killer's new streak
		if credits(killerPlayer, victim) and victim then
			e.Streak = (streaks[killerPlayer :: Player] or 0) + 1
			local id = matchId()
			if id ~= 0 and firstBloodFor ~= id and DamageService.MatchFolder():GetAttribute("Phase") == "Live" then
				firstBloodFor = id
				e.FirstBlood = true
			end
		end
		local wid = character:GetAttribute("LastHitWeapon")
		local kind = character:GetAttribute("LastHitKind")
		local explosive = character:GetAttribute("LastHitExplosive") == true
		local headshot = character:GetAttribute("LastHitHead") == true
		local base = if type(wid) == "string" then (string.gsub(wid, "_RunOver$", "")) else nil
		local vw = base and vehicleWeapons[base]
		local w = wid and Config.Weapons[wid]
		e.Weapon = wid
		e.WeaponName = if w then w.DisplayName elseif vw then vw.Name else nil
		e.Vehicle = vw and vw.Kind
		e.RunOver = type(wid) == "string" and string.find(wid, "_RunOver$") ~= nil
		e.Explosive = explosive
		if wid == "VehicleDestroyed" or explosive then
			e.Type = "Explosion"
		elseif vw and vw.Kind == "Drone" then
			e.Type = "Drone"
		elseif vw then
			e.Type = "Vehicle"
		elseif kind == "Aircraft" then
			e.Type = "Aircraft"
		elseif (w and w.Kind == "Melee") or kind == "Melee" then
			e.Type = "Melee"
		elseif headshot then
			e.Type = "Headshot"
		else
			e.Type = "Weapon"
		end
		-- assist: the top other contributor inside the window (display only)
		local A = FeedConfig.Assists
		if A and A.Enabled then
			local list = {}
			for _, c in DamageService.Contributors(character, A.Window) do
				if c.Damage >= A.MinDamage and (not killerPlayer or c.UserId ~= killerPlayer.UserId) and (not victim or c.UserId ~= victim.UserId) then
					local p = Players:GetPlayerByUserId(c.UserId)
					if p then
						table.insert(list, who(p.Character, p))
						if #list >= A.Max then
							break
						end
					end
				end
			end
			if #list > 0 then
				e.Assists = list
			end
		end
	else
		local cause = character:GetAttribute("DeathCause")
		local root = rootOf(character)
		if cause == "Explosion" then
			e.Type, e.Cause = "Explosion", "Explosion"
		elseif cause == "Void" or (root and root.Position.Y < -40) then
			e.Type, e.Cause = "Environment", "Void"
		elseif selfKill or cause == nil then
			e.Type, e.Cause = "Suicide", "Self"
		else
			e.Type, e.Cause = "Environment", tostring(cause)
		end
	end
	FeedRemote:FireAllClients(e)
	-- the visor's one-line "last kill" readout reads the HUD's small feed: keep it fed (credited kills)
	if e.Killer then
		WeaponEvent:FireAllClients("Feed", e.Killer.Name, e.Killer.Team, e.Weapon, e.Victim and e.Victim.Name, e.Victim and e.Victim.Team, e.Type == "Headshot")
	end
end

--[[ Returns what the victim is told: { KillerName, KillerModel?, KillerPosition?, Weapon?,
	Headshot, Distance? } — KillerModel is nil for environmental deaths. ]]
-- 2026-11-18 equipment abilities (Halo Ring: a kill starts your recharge): f(killerModel, victimCharacter)
EliminationService.KillHooks = EliminationService.KillHooks or {}
function EliminationService.OnDeath(character: Model, victim: Player?)
	-- one death = one elimination: a second call for the same body never credits anything again
	if character:GetAttribute("VantageElimHandled") then
		return { KillerName = "Environment", Headshot = false }
	end
	character:SetAttribute("VantageElimHandled", true)
	local killerPlayer: Player?, killerModel: Model? = nil, nil
	local id = character:GetAttribute("VantageKiller")
	if type(id) == "number" then
		killerPlayer = Players:GetPlayerByUserId(id)
		killerModel = killerPlayer and killerPlayer.Character
	elseif debugKillers[character] then
		killerModel = debugKillers[character]
	end
	debugKillers[character] = nil
	local selfKill = killerModel == character
	if selfKill then
		killerPlayer, killerModel = nil, nil
	end
	-- never credit a teammate (DamageService already refuses friendly hits; this guards stale tags)
	if killerPlayer and victim and killerPlayer.Team and victim.Team and not killerPlayer.Neutral and killerPlayer.Team == victim.Team then
		killerPlayer, killerModel = nil, nil
	end
	-- the kill feed sees every death, credited or not
	local okFeed, feedErr = pcall(sendFeed, character, victim, killerPlayer, killerModel, selfKill)
	if not okFeed then
		warn("[VANTAGE] kill feed: " .. tostring(feedErr))
	end
	if victim then
		streaks[victim] = 0 -- dying ends your streak and any multikill run
		victim:SetAttribute("KillStreak", 0)
		multis[victim] = nil
		bump(victim, "SessionDeaths")
	end
	if not killerModel then
		return { KillerName = "Environment", Headshot = false }
	end
	for _, f in EliminationService.KillHooks do
		task.spawn(pcall, f, killerModel, character)
	end

	local root, kroot = rootOf(character), rootOf(killerModel)
	local head = character:FindFirstChild("Head") :: BasePart?
	local at = head or root
	local wid = character:GetAttribute("LastHitWeapon")
	local w = wid and Config.Weapons[wid]
	local headshot = character:GetAttribute("LastHitHead") == true
	local killerName = if killerPlayer then killerPlayer.DisplayName else killerModel.Name
	local streak, multi = 0, 0
	-- streaks count player victims (training dummies too, but only in Studio)
	if credits(killerPlayer, victim) and killerPlayer then
		streak = (streaks[killerPlayer] or 0) + 1
		streaks[killerPlayer] = streak
		killerPlayer:SetAttribute("KillStreak", streak)
		if ULT_ON and streak % ULT_EVERY == 0 then
			killerPlayer:SetAttribute("UltReady", true)
		end
		bump(killerPlayer, "SessionEliminations")
		if headshot then
			bump(killerPlayer, "SessionHeadshots")
		end
		local now = os.clock()
		local m = multis[killerPlayer]
		if m and now - m.Last <= ElimConfig.MultiKillWindow then
			m.Count += 1
			m.Last = now
		else
			m = { Count = 1, Last = now }
			multis[killerPlayer] = m
		end
		multi = m.Count
		-- REQ: elimination (+ headshot / melee) for the killer, assist for other contributors
		local okReq, reqErr = pcall(function()
			local R = ReqConfig.Rewards
			local vname = if victim then victim.DisplayName else (character:GetAttribute("DisplayName") or character.Name)
			local entries = { { Label = tostring(vname), Amount = R.Elimination, Kind = "Elimination" } }
			if headshot then
				table.insert(entries, { Label = "HEADSHOT", Amount = R.Headshot, Kind = "Headshot" })
			end
			if w and w.Kind == "Melee" then
				table.insert(entries, { Label = "MELEE", Amount = R.Melee, Kind = "Melee" })
			end
			-- XP + ORD first, so the REQ feed line carries all three rewards of this elimination
			local xp, od = Progression.OnElimination(killerPlayer, headshot)
			Requisition.Award(killerPlayer, entries, { ORD = od, XP = xp })
			local okSurge, surgeErr = pcall(rollSurge, killerPlayer, at and at.Position)
			if not okSurge then
				warn("[VANTAGE] supply surge: " .. tostring(surgeErr))
			end
			pcall(Mastery.OnElimination, killerPlayer, wid, headshot)
			for _, c in DamageService.Contributors(character, ReqConfig.AssistWindow) do
				if c.Damage >= ReqConfig.AssistMinDamage and c.UserId ~= killerPlayer.UserId and (not victim or c.UserId ~= victim.UserId) then
					local ap = Players:GetPlayerByUserId(c.UserId)
					if ap then
						local axp, aod = Progression.OnAssist(ap)
						Requisition.Award(ap, { { Label = tostring(vname) .. " [ASSIST]", Amount = R.Assist, Kind = "Assist" } }, { ORD = aod, XP = axp })
						pcall(Mastery.OnAssist, ap, character)
						ap:SetAttribute("MatchStats_Assists", (tonumber(ap:GetAttribute("MatchStats_Assists")) or 0) + 1) -- profile KDA (ProfileService)
					end
				end
			end
		end)
		if not okReq then
			warn("[VANTAGE] REQ award: " .. tostring(reqErr))
		end
	end
	local effect = killerPlayer and killerPlayer:GetAttribute("EliminationEffect")
	effect = if type(effect) == "string" then effect else ElimConfig.DefaultEffect
	local position = at and at.Position
	local killerTeam = teamName(killerModel, killerPlayer)
	for _, p in Players:GetPlayers() do
		if p == killerPlayer then
			KillRemote:FireClient(p, "Confirm", {
				VictimName = if victim then victim.DisplayName else character.Name,
				Headshot = headshot,
				Special = w ~= nil and w.Kind == "Melee", -- knife elimination
				Streak = streak,
				Multi = multi,
				Effect = effect,
				Position = position,
			})
		else
			KillRemote:FireClient(p, "World", { Position = position, KillerTeam = killerTeam, Headshot = headshot, Effect = effect })
		end
	end
	if victim then
		pending[victim] = { Character = character, Deadline = os.clock() + ElimConfig.Replay.MaxRespawnDelay, Done = false }
	end
	return {
		KillerName = killerName,
		KillerModel = killerModel,
		KillerPosition = kroot and kroot.Position,
		Weapon = if w then w.DisplayName .. " " .. w.Class else "",
		Headshot = headshot,
		Distance = if root and kroot then (root.Position - kroot.Position).Magnitude else nil,
	}
end

-- Called by the respawn flow after Players.RespawnTime: waits while this death's replay is
-- still playing (until the client says Done or the deadline passes).
function EliminationService.WaitForReplay(player: Player, character: Model)
	local p = pending[player]
	if not p or p.Character ~= character then
		return
	end
	while not p.Done and player.Parent and os.clock() < p.Deadline do
		task.wait(0.1)
	end
	if pending[player] == p then
		pending[player] = nil
	end
end

function EliminationService.SetDebugKiller(victim: Model, killer: Model)
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		debugKillers[victim] = killer
	end
end

ReplayRemote.OnServerEvent:Connect(function(player: Player, msg: any)
	if msg == "Done" then
		local p = pending[player]
		if p then
			p.Done = true
		end
	end
end)

-- real zeros from the start, so the menu can tell "none yet" from "not loaded"
local function initStats(p: Player)
	for _, key in { "SessionEliminations", "SessionDeaths", "SessionHeadshots" } do
		if p:GetAttribute(key) == nil then
			p:SetAttribute(key, 0)
		end
	end
end
Players.PlayerAdded:Connect(initStats)
for _, p in Players:GetPlayers() do
	initStats(p)
end

Players.PlayerRemoving:Connect(function(p)
	streaks[p] = nil
	multis[p] = nil
	pending[p] = nil
end)

return EliminationService
