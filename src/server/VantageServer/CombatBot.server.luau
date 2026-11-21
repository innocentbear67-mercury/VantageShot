--[[
	VANTAGE — CombatBot (Studio only, never runs in a live server)
	A training dummy that fights back. When the first player spawns on a team, a bot on the other
	team appears in the open lane outside that player's base (BOT_X studs from the map centre),
	clear of the spawn-room shield. It turns to the nearest enemy, waits a short reaction
	time once it has line of sight, then fires 3-round bursts with some spread.
	Its hits do real damage (WeaponMath falloff + headshots, spawn ForceFields respected), show the
	damage arcs, and count as the killer for elimination effects and the death replay.
	Shoot it like any dummy; it respawns where it stood after RESPAWN seconds.
]]

local ENABLED = true
local RANGE = 150
local SPREAD_DEG = 2.5 -- random aim error per shot
local HEAD_CHANCE = 0.25 -- share of shots aimed at the head (the rest at the chest)
local BURST, BURST_GAP, BURST_DELAY = 3, 0.11, 1.3
local REACTION = 0.6 -- seconds of sight before the first burst
local RESPAWN = 4
local BOT_X = 80 -- distance from the map centre toward the player's base (open floor, sight of the spawn exit)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not ENABLED or not RunService:IsStudio() then
	return
end

local WeaponServer = script.Parent:WaitForChild("WeaponServer")
local hook = WeaponServer:WaitForChild("WeaponDebug") :: BindableFunction
local EliminationService = require(WeaponServer.EliminationService)
local Weapons = ReplicatedStorage.Vantage.Weapons
local Config = require(Weapons.WeaponConfig)
local WeaponMath = require(Weapons.WeaponMath)
local EventRemote = ReplicatedStorage.Vantage:WaitForChild("Remotes"):WaitForChild("WeaponEvent") :: RemoteEvent
local ShieldService = require(WeaponServer.ShieldService)
local DamageService = require(WeaponServer.DamageService)

local weapon = Config.Weapons[Config.DefaultWeapon]
local rng = Random.new()
local rad = math.rad

local function rayParams(exclude)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = exclude
	return p
end

local function ownerOf(part: Instance): Player?
	for _, p in Players:GetPlayers() do
		if p.Character and part:IsDescendantOf(p.Character) then
			return p
		end
	end
	return nil
end

-- nearest living enemy player in range: (player, character)
local function nearestTarget(bot: Model, team: string)
	local head = bot:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local best, bestDist = nil, RANGE
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local th = c and c:FindFirstChild("Head") :: BasePart?
		if h and th and h.Health > 0 and p.Team and p.Team.Name ~= team then
			local d = (th.Position - head.Position).Magnitude
			if d < bestDist then
				best, bestDist = p, d
			end
		end
	end
	return best
end

local function canSee(bot: Model, target: Player): boolean
	local head = bot.Head :: BasePart
	local th = target.Character.Head :: BasePart
	local res = Workspace:Raycast(head.Position, th.Position - head.Position, rayParams({ bot }))
	return res ~= nil and res.Instance:IsDescendantOf(target.Character)
end

local function shoot(bot: Model, target: Player)
	local head = bot:FindFirstChild("Head") :: BasePart?
	local c = target.Character
	if not head or not c then
		return
	end
	local aimPart = (if rng:NextNumber() < HEAD_CHANCE then c:FindFirstChild("Head") else nil) or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Head")
	if not aimPart then
		return
	end
	local dir = (aimPart.Position - head.Position).Unit
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(rad(rng:NextNumber(-SPREAD_DEG, SPREAD_DEG)), rad(rng:NextNumber(-SPREAD_DEG, SPREAD_DEG)), 0)).LookVector
	-- tracer / muzzle / sound for every client (same ray as below)
	hook:Invoke("DummyShoot", bot, head.Position + dir * 100)
	local res = Workspace:Raycast(head.Position, dir * 500, rayParams({ bot }))
	local victim = res and ownerOf(res.Instance)
	local character = victim and victim.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or character:FindFirstChildOfClass("ForceField") then
		return
	end
	local isHead = res.Instance.Name == "Head" or res.Instance.Parent:IsA("Accessory")
	local dmg = WeaponMath.Damage(weapon, isHead, false, res.Distance)
	character:SetAttribute("LastHitHead", isHead)
	character:SetAttribute("LastHitDir", dir)
	character:SetAttribute("LastHitWeapon", weapon.Id)
	character:SetAttribute("LastHitKind", weapon.Kind)
	character:SetAttribute("LastHitExplosive", false)
	local toHealth, absorbed, broke = ShieldService.Absorb(character, dmg)
	ShieldService.Report(character, res.Position, dir, absorbed, broke)
	if toHealth >= hum.Health then
		EliminationService.SetDebugKiller(character, bot)
	end
	if toHealth > 0 then
		hum:TakeDamage(toHealth)
	end
	EventRemote:FireClient(victim, "Damaged", head.Position, dmg)
end

local function runBot(spawnCF: CFrame, team: string)
	while true do
		-- a /squad (SquadBots) is running: stand down until it is cleared
		while Workspace:GetAttribute("SquadBotsActive") do
			task.wait(1)
		end
		local bot = hook:Invoke("SpawnDummy", spawnCF.Position, "VantageBot", true, team) :: Model?
		if not bot then
			return
		end
		bot:PivotTo(spawnCF)
		local hum = bot:WaitForChild("Humanoid") :: Humanoid
		local root = bot:WaitForChild("HumanoidRootPart") :: BasePart
		local seenSince, nextBurst = nil, 0
		while hum.Health > 0 and bot.Parent and not Workspace:GetAttribute("SquadBotsActive") do
			-- holds fire until the match is Live (MatchService: Match.Combat)
			local target = DamageService.CombatEnabled() and nearestTarget(bot, team)
			if target and canSee(bot, target) then
				-- face the target and pitch the rifle at it
				local th = target.Character.Head :: BasePart
				local flat = Vector3.new(th.Position.X, root.Position.Y, th.Position.Z)
				if (flat - root.Position).Magnitude > 0.5 then
					root.CFrame = CFrame.lookAt(root.Position, flat)
				end
				local d = (th.Position - bot.Head.Position).Unit
				hook:Invoke("DummyAim", bot, math.deg(math.asin(math.clamp(d.Y, -1, 1))), false)
				seenSince = seenSince or os.clock()
				if os.clock() - seenSince >= REACTION and os.clock() >= nextBurst then
					for _ = 1, BURST do
						if hum.Health <= 0 then
							break
						end
						shoot(bot, target)
						task.wait(BURST_GAP)
					end
					nextBurst = os.clock() + BURST_DELAY
				end
			else
				seenSince = nil
			end
			task.wait(0.1)
		end
		if not Workspace:GetAttribute("SquadBotsActive") then
			task.wait(RESPAWN)
		end
		if bot.Parent then
			bot:Destroy()
		end
	end
end

-- one bot, placed in front of the first player to spawn on a team, on the other team
local started = false
local function onCharacter(player: Player, character: Model)
	if started or not player.Team then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root or started then
		return
	end
	started = true
	task.wait(1)
	-- the map can mark where the bot stands (Map_*/Gameplay/BotSpots/<Team>), else fall back to BOT_X
	local marker
	for _, m in Workspace:GetChildren() do
		local spots = m:FindFirstChild("Gameplay") and m.Gameplay:FindFirstChild("BotSpots")
		marker = spots and spots:FindFirstChild(player.Team.Name) :: BasePart?
		if marker then
			break
		end
	end
	local pos
	if marker then
		pos = marker.Position + Vector3.new(0, 3, 0)
	else
		local spot = Vector3.new(if root.Position.X < 0 then -BOT_X else BOT_X, 0, 0)
		local floor = Workspace:Raycast(spot + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rayParams({ character }))
		pos = if floor then floor.Position + Vector3.new(0, 3, 0) else spot + Vector3.new(0, 3, 0)
	end
	local team = if player.Team.Name == "Red" then "Blue" else "Red"
	runBot(CFrame.lookAt(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z)), team)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
end
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
