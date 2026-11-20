--[[
	VANTAGE — AbilityServer
	Authoritative side of the GRAPPLE (the suit's one ability). The client flies its own character
	(it owns its physics, like all movement here); the server decides whether a grapple exists:
		- cooldown per player (with latency tolerance); a refused shot sends the real cooldown back
		- the hook point must be in range, on solid map geometry (never a character), and visible
		  from the player: the server casts its own ray, so nothing attaches through walls
		- while the cable is out the movement validator is exempted a fraction of a second at a
		  time, and only as long as the player really is on the cable: inside the leash around the
		  hook and under the cable's top speed. Break either and the exemption simply stops, so
		  the normal movement checks take over again
		- ends on the client's release, on time-out, on death, respawn or leaving
		- relays the shot and the release to every other client (they draw hook and cable)
		- makes sure each character wears its launcher (the equipped Grappling Hook, EquipmentBuild)

	Remote: ReplicatedStorage.Vantage.Remotes.Ability
		client -> server  ("Use", "Grapple", hookPoint: Vector3)   ("GrappleEnd")
		                  ("Use", "GrappleAircraft", { Flight, Hook, Time })   ("AircraftHang")   ("AircraftRelease")
		server -> client  ("FX", casterCharacter, "Grapple", hookPoint)   ("GrappleEnd", casterCharacter)
		                  ("FX", casterCharacter, "GrappleAircraft", { Flight, Hook })
		                  ("GrappleReject", secondsLeft)   ("Cooldown", abilityName, secondsLeft)
		                  ("AircraftDetach", reason)
	The aircraft side (hooks on the moving dropship) is validated by AircraftService; this script
	keeps owning the one grapple cooldown, so both kinds of shot share it.

	2026-11-19 equipment redesign:
		- the cooldown counts from LET-GO (EquipmentCatalog HookStats; Kraken's Relay opens a free 1.5 s window)
		- every hook flies its own Profile (EquipmentCatalog.HookProfile): the leash speed check uses its MaxSpeed
		- after let-go the validator gets a short grace + a ballistic momentum allowance (MovementValidator.Momentum),
		  not a blanket 4.5 s exemption
		- the item worn THIS life counts (EquipmentCatalog.Active), so mid-match equips wait for the next spawn
		- relays the hit normal (bite ripple), Blink from / to (beam + afterimage), Perch (PerchAt / PerchN on the
		  character: rings + hum for everyone), and tells a Harpoon victim it was hooked ("Hooked")
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Vantage.Abilities.AbilityConfig)
local G = Config.Abilities.Grapple
-- 2026-11-17: the equipped Grappling Hook sets range / cooldown / charges (EquipmentCatalog.HookStats)
-- and its model is the launcher (EquipmentBuild; LoadoutService dresses each spawn)
local EquipCatalog = require(ReplicatedStorage.Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local EquipBuild = require(ReplicatedStorage.Vantage.Equipment:WaitForChild("EquipmentBuild"))
local remote = ReplicatedStorage.Vantage.Remotes.Ability :: RemoteEvent
local exempt = script.Parent:WaitForChild("ExemptMovement") :: BindableEvent
local momentumEv = script.Parent:WaitForChild("MomentumMovement", 10) :: BindableEvent?
local AircraftService = require(script.Parent:WaitForChild("AircraftService"))
local AircraftConfig = require(ReplicatedStorage.Vantage.Aircraft.AircraftConfig)

-- 2026-11-18 hook abilities (EquipmentCatalog Ability.Id): Hunter (Harpoon) hooks enemy players and marks them,
-- Perch (Mag-Anchor) holds you on the wall, Blink (Starfall) zips you there and reveals enemies, Swing (Lotus)
-- is client physics only. Marks: character attributes MarkedUntil (server time) + MarkedBy (team name or "U"..UserId),
-- drawn by VantagePerkClient for that team only.
local DamageService = require(script.Parent:WaitForChild("WeaponServer"):WaitForChild("DamageService"))
local function markKey(p: Player): string
	return if p.Team and not p.Neutral then p.Team.Name else "U" .. p.UserId
end
local function mark(m: Model, by: Player, secs: number)
	m:SetAttribute("MarkedUntil", Workspace:GetServerTimeNow() + secs)
	m:SetAttribute("MarkedBy", markKey(by))
end

local readyAt: { [Player]: { [string]: number } } = {}
-- player -> { Point, Leash, Until, LastPos, LastAt, Strikes, Character }
local active: { [Player]: any } = {}

local function resetCooldowns(player: Player)
	readyAt[player] = {}
end

-- every character model (players, bots, dummies): the hook never attaches to them, and they
-- never block the server's line-of-sight ray
local function characters(): { Instance }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, tag in { "VantageDummy", "VantageBot" } do
		for _, m in CollectionService:GetTagged(tag) do
			table.insert(list, m)
		end
	end
	local standIns = Workspace:FindFirstChild("VantageIntroStandIns")
	if standIns then
		table.insert(list, standIns)
	end
	return list
end

-- the first solid thing along a ray (non-colliding / invisible-to-physics parts are stepped through)
local function solidHit(origin: Vector3, to: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = characters()
	params.FilterDescendantsInstances = ignore
	local dir = to - origin
	for _ = 1, 6 do
		local hit = Workspace:Raycast(origin, dir, params)
		if not hit then
			return nil
		end
		if hit.Instance.CanCollide and not hit.Instance:GetAttribute("NoGrapple") then
			return hit
		end
		table.insert(ignore, hit.Instance)
		params.FilterDescendantsInstances = ignore
	end
	return nil
end

-- 2026-11-19: ready when the cooldown (from the last let-go) is over, or inside Kraken's Relay window
local function isReady(cd, now: number): boolean
	if now >= (cd.Grapple or 0) - Config.ServerCooldownTolerance then
		return true
	end
	return cd.RelayUntil ~= nil and now <= cd.RelayUntil + Config.ServerCooldownTolerance
end
-- a shot starts: blocks the next one until this cable is let go; returns whether it used the Relay window
local function startShot(cd, hs, now: number, untilT: number): boolean
	local relayed = cd.RelayUntil ~= nil and now < (cd.Grapple or 0) - Config.ServerCooldownTolerance
	cd.RelayUntil = nil
	cd.Grapple = untilT + hs.Cooldown
	return relayed
end
local function newActive(player: Player, character: Model, fields)
	local ability, AP = EquipCatalog.AbilityOf(player, "Hook")
	fields.Character = character
	fields.Ability, fields.AP = ability, AP
	fields.Profile = EquipCatalog.HookProfile(player)
	fields.Cooldown = EquipCatalog.HookStats(player).Cooldown
	fields.Strikes = 0
	return fields
end

local function relay(caster: Player, ...)
	for _, p in Players:GetPlayers() do
		if p ~= caster then
			remote:FireClient(p, ...)
		end
	end
end

-- noCooldown: a stale / respawn clean-up, not a real let-go
local function endGrapple(player: Player, tail: boolean, noCooldown: boolean?)
	local a = active[player]
	if not a then
		return
	end
	active[player] = nil
	local now = os.clock()
	local cd = readyAt[player]
	if cd and not noCooldown then
		cd.Grapple = now + (a.Cooldown or G.Cooldown)
		-- Kraken: a real let-go after a real pull opens one free grapple
		if a.Ability == "Relay" and tail and not a.Relayed and now - (a.PullAt or now) >= ((a.AP and a.AP.MinPull) or 0.4) then
			cd.RelayUntil = now + ((a.AP and a.AP.Window) or 1.5)
		end
	end
	if a.Character and a.Character.Parent then
		a.Character:SetAttribute("PerchAt", nil)
		a.Character:SetAttribute("PerchN", nil)
	end
	if tail and player.Parent then
		-- a short blanket grace for the let-go itself, then a ballistic allowance (every other check keeps running)
		exempt:Fire(player, G.ExemptTail)
		local prof = a.Profile or G
		if momentumEv then
			momentumEv:Fire(player, (prof.ReleaseMaxSpeed or 82) * 1.15, math.max(prof.ReleaseMaxUp or 88, prof.ArriveHop or 26, 32), G.MomentumTime or 3.5)
		end
	end
	relay(player, "GrappleEnd", a.Character)
end

-- letting go of the aircraft: the grapple is ready again almost at once (hook a building on the way down)
AircraftService.SetReleaseHandler(function(player: Player)
	local cd = readyAt[player]
	if cd then
		cd.Grapple = os.clock() + AircraftConfig.Release.Cooldown
		remote:FireClient(player, "Cooldown", "Grapple", AircraftConfig.Release.Cooldown)
	end
end)

local function useAircraft(player: Player, arg: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local cd = readyAt[player]
	if not character or not humanoid or humanoid.Health <= 0 or not cd or active[player] then
		return
	end
	local now = os.clock()
	if not isReady(cd, now) then
		remote:FireClient(player, "GrappleReject", cd.Grapple - now)
		return
	end
	if type(arg) ~= "table" then
		return
	end
	local ok = AircraftService.TryAttach(player, arg.Flight, arg.Hook, arg.Time)
	if not ok then
		cd.Grapple = now + G.MissCooldown
		remote:FireClient(player, "GrappleReject", G.MissCooldown)
		return
	end
	cd.RelayUntil = nil
	cd.Grapple = now + EquipCatalog.HookStats(player).Cooldown -- this hook's own cooldown (was the base 3.5 for every hook)
end

-- Hunter (Harpoon): the hook bites an enemy character; you are pulled to them and they are marked
local function useTarget(player: Player, target: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cd = readyAt[player]
	if not character or not humanoid or humanoid.Health <= 0 or not root or not cd then
		return
	end
	if active[player] then
		endGrapple(player, false, true) -- stale (the client only fires with no cable out)
	end
	if character:GetAttribute("InVehicle") or AircraftService.IsRider(player) then
		return
	end
	local now = os.clock()
	if not isReady(cd, now) then
		remote:FireClient(player, "GrappleReject", cd.Grapple - now)
		return
	end
	local ability, AP = EquipCatalog.AbilityOf(player, "Hook")
	if ability ~= "Hunter" or typeof(target) ~= "Instance" or not target:IsA("Model") or target == character then
		return
	end
	local function refuse()
		cd.Grapple = now + G.MissCooldown
		remote:FireClient(player, "GrappleReject", G.MissCooldown)
	end
	local th = target:FindFirstChildOfClass("Humanoid")
	local tr = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not th or th.Health <= 0 or not tr or DamageService.IsFriendly(player, target) then
		refuse()
		return
	end
	local hs = EquipCatalog.HookStats(player)
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local dist = (tr.Position - eye).Magnitude
	if dist > hs.Range + 16 or dist < 3 or solidHit(eye, tr.Position) ~= nil then
		refuse() -- out of range, or map geometry between you (characters never block)
		return
	end
	local untilT = now + dist / G.ProjectileSpeed + G.MaxTime + 0.6
	local a = newActive(player, character, {
		Point = tr.Position, Target = target, Leash = dist + G.LeashSlack + 30,
		Until = untilT, LastPos = root.Position, LastAt = now, PullAt = now + dist / G.ProjectileSpeed,
	})
	a.Relayed = startShot(cd, hs, now, untilT)
	active[player] = a
	exempt:Fire(player, 0.7)
	mark(target, player, AP.Mark or 4)
	relay(player, "FX", character, "GrappleTarget", target)
	local vp = Players:GetPlayerFromCharacter(target)
	if vp then
		remote:FireClient(vp, "Hooked", character) -- the victim hears and sees where it came from
	end
end

-- the hooked player shoots the hunter: the line is cut
table.insert(DamageService.HitHooks, function(shooter: Player, victim: Model)
	for p, a in active do
		if a.Target and a.Character == victim and shooter.Character == a.Target then
			endGrapple(p, true)
			remote:FireClient(p, "GrappleCut")
		end
	end
end)

-- Perch (Mag-Anchor): the client arrived and holds on to the wall; keep the grapple (and its exemption) alive
local function perch(player: Player)
	local a = active[player]
	if not a or a.Target or a.Perched then
		return
	end
	local ability, AP = EquipCatalog.AbilityOf(player, "Hook")
	if ability == "Perch" then
		a.Perched = true
		a.Until = math.max(a.Until, os.clock() + (AP.Time or 3) + 0.5)
		local head = a.Character:FindFirstChild("Head") :: BasePart?
		if head then
			local hit = solidHit(head.Position, a.Point + (a.Point - head.Position).Unit * 2)
			if hit and (hit.Position - a.Point).Magnitude < 6 then
				a.Character:SetAttribute("PerchAt", hit.Position)
				a.Character:SetAttribute("PerchN", hit.Normal)
			end
		end
	end
end

remote.OnServerEvent:Connect(function(player: Player, action: any, name: any, arg: any)
	if action == "GrappleEnd" then
		endGrapple(player, true)
		AircraftService.Release(player, "Release", false)
		return
	elseif action == "AircraftHang" then
		AircraftService.MarkHanging(player)
		return
	elseif action == "AircraftRelease" then
		AircraftService.Release(player, "Release", false)
		return
	elseif action == "Use" and ((player.Team == nil and not player:GetAttribute("InTutorial")) or (player.Character and player.Character:GetAttribute("VantageHolstered"))) then
		return -- lobby: the grapple is disabled
	elseif action == "Use" and name == "GrappleAircraft" then
		useAircraft(player, arg)
		return
	elseif action == "Use" and name == "GrappleTarget" then
		useTarget(player, arg)
		return
	elseif action == "Perch" then
		perch(player)
		return
	end
	if action ~= "Use" or name ~= "Grapple" then
		return
	end
	if player.Character and player.Character:GetAttribute("InVehicle") then
		return -- seated in a vehicle (VehicleService)
	end
	if AircraftService.IsRider(player) then
		return -- on the aircraft's cable already
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cd = readyAt[player]
	if not character or not humanoid or humanoid.Health <= 0 or not root or not cd then
		return
	end
	if active[player] then
		endGrapple(player, false, true) -- stale (the client only fires with no cable out)
	end
	local now = os.clock()
	if not isReady(cd, now) then
		remote:FireClient(player, "GrappleReject", cd.Grapple - now)
		return
	end
	local hs = EquipCatalog.HookStats(player)
	local function refuse()
		cd.Grapple = now + G.MissCooldown
		remote:FireClient(player, "GrappleReject", G.MissCooldown)
	end
	if typeof(arg) ~= "Vector3" or arg ~= arg then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local dist = (arg - eye).Magnitude
	if dist > hs.Range + 12 or dist < 3 then
		refuse()
		return
	end
	-- the server's own ray: the first solid thing between the player and the claimed point must
	-- BE that point (within a little slack for latency and the eye / camera offset)
	local hit = solidHit(eye, arg + (arg - eye).Unit * 2)
	if not hit or (hit.Position - arg).Magnitude > 4 then
		-- 2026-11-19: moving fast at real ping the server's copy of you lags behind; try where you are on your screen
		local lead = root.AssemblyLinearVelocity * math.clamp(player:GetNetworkPing(), 0, 0.3)
		local eye2 = eye + lead
		local hit2 = if lead.Magnitude > 1 and (arg - eye2).Magnitude <= hs.Range + 12 then solidHit(eye2, arg + (arg - eye2).Unit * 2) else nil
		if not hit2 or (hit2.Position - arg).Magnitude > 4 then
			refuse()
			return
		end
		hit = hit2
	end
	local flight = dist / G.ProjectileSpeed
	local untilT = now + flight + G.MaxTime + 0.6
	local a = newActive(player, character, {
		Point = hit.Position, Leash = dist + G.LeashSlack,
		Until = untilT, LastPos = root.Position, LastAt = now, PullAt = now + flight,
	})
	a.Relayed = startShot(cd, hs, now, untilT)
	active[player] = a
	local ability, AP = a.Ability, a.AP
	if ability == "Blink" then
		-- Starfall: the client zips straight to the point (a teleport), then enemies near it are revealed.
		-- 0.6 s grace covers the jump arriving; the leash check below still ends a fake one
		exempt:Fire(player, 0.6)
		local at = hit.Position
		relay(player, "FX", character, "Blink", { From = root.Position, To = hit.Position, Normal = hit.Normal })
		task.delay(0.12, function()
			for _, c in characters() do
				local r = c:IsA("Model") and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				local h = c:IsA("Model") and c:FindFirstChildOfClass("Humanoid")
				if r and h and h.Health > 0 and c ~= character and not DamageService.IsFriendly(player, c)
					and (r.Position - at).Magnitude <= (AP.Radius or 30) then
					mark(c, player, AP.Reveal or 1.5)
				end
			end
		end)
		return
	end
	exempt:Fire(player, 0.7)
	relay(player, "FX", character, "Grapple", hit.Position, hit.Normal)
end)

-- five times a second: keep the exemption alive for players who really are on their cable
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then
		return
	end
	acc = 0
	local now = os.clock()
	for player, a in active do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character ~= a.Character or not humanoid or humanoid.Health <= 0 or not root or now > a.Until then
			endGrapple(player, root ~= nil and humanoid ~= nil and humanoid.Health > 0)
			continue
		end
		if a.Target then
			local tr = a.Target:FindFirstChild("HumanoidRootPart") :: BasePart?
			local th = a.Target:FindFirstChildOfClass("Humanoid")
			if not tr or not th or th.Health <= 0 or not a.Target:IsDescendantOf(Workspace) then
				endGrapple(player, true)
				remote:FireClient(player, "GrappleCut")
				continue
			end
			a.Point = tr.Position
		end
		local pos = root.Position
		local speed = (pos - a.LastPos).Magnitude / math.max(now - a.LastAt, 1e-3)
		a.LastPos, a.LastAt = pos, now
		local maxSpeed = (a.Profile and a.Profile.MaxSpeed) or G.MaxSpeed
		if (pos - a.Point).Magnitude > a.Leash or speed > maxSpeed * 1.35 + 8 + (if a.Target then 40 else 0) then
			a.Strikes += 1
			if a.Strikes >= 2 then
				endGrapple(player, false) -- not a grapple any more: no grace, the validator resumes
			end
			continue
		end
		a.Strikes = 0
		exempt:Fire(player, 0.7)
	end
end)

-- ── the launcher on the left forearm (replicated: everyone sees it on everyone) ──────────
local function buildLauncher(character: Model)
	local arm = character:WaitForChild("LeftLowerArm", 8)
	if not arm or not arm:IsA("BasePart") then
		return
	end
	task.wait() -- LoadoutService dresses every spawn; this only covers a character it missed
	if character:FindFirstChild("VantageGrappleLauncher") or not character.Parent then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	local ok, err = pcall(EquipBuild.Dress, character, EquipCatalog.Equipped(player, "Pack"), EquipCatalog.Equipped(player, "Hook"))
	if not ok then
		warn("[VANTAGE] AbilityServer: launcher build failed:", err)
	end
end

local function onPlayer(player: Player)
	resetCooldowns(player)
	player.CharacterAdded:Connect(function(character)
		endGrapple(player, false, true)
		resetCooldowns(player)
		task.spawn(buildLauncher, character)
	end)
	if player.Character then
		task.spawn(buildLauncher, player.Character)
	end
end
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	endGrapple(p, false, true)
	readyAt[p] = nil
end)
