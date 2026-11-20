--[[
	VANTAGE — VehicleService (server)
	Combined-arms vehicles: spawning from map markers, seats, safe exits, network ownership,
	movement validation, turret + weapons, damage, destruction, respawn, match resets.

	Authority:
	  - Driving physics run on the driver's client (network owner) through VehicleSim; the server
	    caps speed and position jumps and takes ownership back from a client that breaks them.
	    Empty vehicles are simulated here with the same VehicleSim.
	  - The client only sends intent: throttle / steer, an aim point, trigger down / up, exit,
	    seat change. Turret angles, rate of fire, heat, reload, projectiles and every hit are
	    computed here from the server's own turret state (VehicleMath), never from the client.
	  - Damage to infantry goes through WeaponServer.DamageService.Apply (shields, friendly fire,
	    kill credit, feed, scoring); guns hit vehicles through DamageService.ApplyToVehicle.

	Map integration: any BasePart tagged "VehicleSpawn" (or inside a "VehicleSpawns" folder under a
	map's Gameplay folder) with attributes Vehicle = "Tank" | "APC" | "Buggy", Team = "Blue" | "Red",
	optional RespawnTime. The vehicle spawns with its front along the marker's LookVector.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local VFolder = Vantage:WaitForChild("Vehicles")
local Config = require(VFolder.VehicleConfig)
local Sim = require(VFolder.VehicleSim)
local VMath = require(VFolder.VehicleMath)
local WeaponConfig = require(Vantage.Weapons.WeaponConfig)
local WeaponMath = require(Vantage.Weapons.WeaponMath)

local VantageServer = script.Parent
local WeaponServer = VantageServer:WaitForChild("WeaponServer")
local DamageService = require(WeaponServer:WaitForChild("DamageService"))
local HitValidation = require(WeaponServer:WaitForChild("HitValidation"))
local MovementValidator = require(VantageServer:WaitForChild("MovementValidator"))

local InputRemote = VFolder:WaitForChild("VehicleInput") :: RemoteEvent
local EventRemote = VFolder:WaitForChild("VehicleEvent") :: RemoteEvent
local WeaponEvent = Vantage:WaitForChild("Remotes"):WaitForChild("WeaponEvent") :: RemoteEvent

local Service = {}
Service.Vehicles = {} -- [Model] = state
Service.Stats = { Spawned = 0, Destroyed = 0, OwnershipRevoked = 0, ShellsFired = 0, RoundsFired = 0 }

local GROUP_VEHICLE = "Vehicles"
local GROUP_OCCUPANT = "VehicleOccupants"

local rng = Random.new()
local nextId = 0
local shells = {}

-- ─── helpers ─────────────────────────────────────────────────────────────
local function alive(player: Player): (Model?, Humanoid?)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if c and h and h.Health > 0 then
		return c, h
	end
	return nil, nil
end

local function combatOn(): boolean
	return DamageService.CombatEnabled()
end

local function teamName(player: Player?): string?
	if player and player.Team and not player.Neutral then
		return player.Team.Name
	end
	return nil
end

local function characters(): { Instance }
	local t = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(t, p.Character)
		end
	end
	return t
end

local function vehicleOf(inst: Instance?): (Model?, any)
	while inst and inst ~= Workspace do
		if inst:IsA("Model") and CollectionService:HasTag(inst, Config.Tag) then
			return inst, Service.Vehicles[inst]
		end
		inst = inst.Parent
	end
	return nil, nil
end
Service.VehicleOf = vehicleOf

local function seatOccupant(seat: Seat): Player?
	local h = seat.Occupant
	return h and Players:GetPlayerFromCharacter(h.Parent)
end

local function occupants(st): { Player }
	local t = {}
	for _, seat in st.Seats do
		local p = seatOccupant(seat)
		if p then
			table.insert(t, p)
		end
	end
	return t
end

-- the team a vehicle currently fights for: its crew, else the team that spawned it
local function vehicleTeam(st): string?
	if st.Bot then
		return st.Bot.Team -- driven by an AI crew (SquadBots)
	end
	for _, p in occupants(st) do
		local t = teamName(p)
		if t then
			return t
		end
	end
	return st.SpawnTeam
end

local function controllerOf(st): Player?
	local w = st.Cfg.Weapon
	local gunner = st.SeatByRole[w.Controller]
	local p = gunner and seatOccupant(gunner)
	if p then
		return p
	end
	return st.SeatByRole.Driver and seatOccupant(st.SeatByRole.Driver)
end

local function fire(kind: string, ...)
	EventRemote:FireAllClients(kind, ...)
end

-- ─── collision groups ────────────────────────────────────────────────────
local function setupGroups()
	for _, g in { GROUP_VEHICLE, GROUP_OCCUPANT } do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP_VEHICLE, GROUP_OCCUPANT, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_OCCUPANT, GROUP_OCCUPANT, false)
end

-- ─── occupants ───────────────────────────────────────────────────────────
local saved = {} -- [Player] = { Parts = { [BasePart] = {group, massless} }, Vehicle, Seat }
local intent = {} -- [Player] = { Kind = "Exit"|"Switch", CF? } while we move them ourselves

local function applyOccupant(player: Player, character: Model, st, seat: Seat)
	local rec = { Parts = {}, Vehicle = st.Model, Seat = seat }
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			rec.Parts[d] = { d.CollisionGroup, d.Massless }
			d.CollisionGroup = GROUP_OCCUPANT
			d.Massless = true
		end
	end
	saved[player] = rec
	character:SetAttribute("InVehicle", st.Model:GetAttribute("VehicleId"))
	character:SetAttribute("VehicleSeat", seat:GetAttribute("SeatIndex"))
	character:SetAttribute("VehicleHidden", seat:GetAttribute("Hidden") == true or nil)
	MovementValidator.Exempt(player, 1.5)
end

local function restoreOccupant(player: Player, character: Model?)
	local rec = saved[player]
	saved[player] = nil
	if rec then
		for part, v in rec.Parts do
			if part.Parent then
				part.CollisionGroup = v[1]
				part.Massless = v[2]
			end
		end
	end
	if character then
		character:SetAttribute("InVehicle", nil)
		character:SetAttribute("VehicleSeat", nil)
		character:SetAttribute("VehicleHidden", nil)
	end
end

-- is this a free, safe place for a character (feet at `feet`)?
local function clearSpot(st, feet: Vector3, from: Vector3): boolean
	local ex = characters()
	table.insert(ex, st.Model)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { st.Model }
	params.RespectCanCollide = true
	local size = Config.Interact.ExitClearance
	local boxCF = CFrame.new(feet + Vector3.new(0, size.Y / 2 + 0.3, 0))
	for _, p in Workspace:GetPartBoundsInBox(boxCF, size, params) do
		if p.CanCollide then
			return false -- walls, other vehicles or other players
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ex
	-- solid floor within a short drop, nothing dangerous (no void, no kill planes)
	local down = Workspace:Raycast(feet + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rp)
	if not down or down.Instance:GetAttribute("KillPlane") or (down.Instance.Name:lower():find("kill")) then
		return false
	end
	-- no wall between the seat and the spot (you climb out, you do not pass through)
	local mid = feet + Vector3.new(0, 3, 0)
	local block = Workspace:Raycast(from, mid - from, rp)
	if block then
		return false
	end
	return true
end

local function findExit(st, seat: Seat): CFrame?
	local root = st.Root
	local cf = root.CFrame
	if st.Cfg.Drive.Kind == "Flight" then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { st.Model }
		local g = Workspace:Raycast(root.Position, Vector3.new(0, -500, 0), rp)
		if not g or root.Position.Y - g.Position.Y > 10 then
			-- airborne: the pilot drops out of the belly
			local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
			local p = root.Position - Vector3.new(0, root.Size.Y / 2 + 4, 0)
			return CFrame.lookAt(p, p + (if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis))
		end
	end
	local from = seat.Position + cf.UpVector * 2
	local candidates = {}
	for _, a in root:GetChildren() do
		if a:IsA("Attachment") and a.Name:match("^Exit%d+$") then
			table.insert(candidates, { tonumber(a.Name:match("%d+")), a.WorldPosition })
		end
	end
	-- closest exits to the seat first (passengers in the back use the rear ramp)
	table.sort(candidates, function(x, y)
		return (x[2] - seat.Position).Magnitude < (y[2] - seat.Position).Magnitude
	end)
	local function try(p: Vector3): CFrame?
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local ex = characters()
		table.insert(ex, st.Model)
		rp.FilterDescendantsInstances = ex
		local hit = Workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rp)
		local feet = if hit then hit.Position else p
		if clearSpot(st, feet, from) then
			local out = Vector3.new(feet.X - root.Position.X, 0, feet.Z - root.Position.Z)
			local look = if out.Magnitude > 0.1 then out.Unit else cf.LookVector
			return CFrame.lookAt(feet + Vector3.new(0, 3, 0), feet + Vector3.new(0, 3, 0) + look)
		end
		return nil
	end
	for _, c in candidates do
		local r = try(c[2])
		if r then
			return r
		end
	end
	-- ring search around the hull
	local half = math.max(root.Size.X, root.Size.Z) / 2 + 4
	for ring = 0, 2 do
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			local p = root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * (half + ring * 4)
			local r = try(p)
			if r then
				return r
			end
		end
	end
	-- last resort: on top of the vehicle
	return CFrame.new(root.Position + Vector3.new(0, root.Size.Y / 2 + 4, 0))
end

local function placeAt(player: Player, character: Model, cf: CFrame, velocity: Vector3?)
	MovementValidator.Exempt(player, 2)
	character:PivotTo(cf)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.AssemblyLinearVelocity = velocity or Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

-- ─── ownership ───────────────────────────────────────────────────────────
local function updateOwner(st)
	local driver = st.SeatByRole.Driver and seatOccupant(st.SeatByRole.Driver)
	if st.Model:GetAttribute("Destroyed") then
		driver = nil
	end
	if driver ~= st.Owner then
		st.Owner = driver
		st.Sim:Clear()
		st.Input = { Throttle = 0, Steer = 0, Brake = false }
		if st.Root:CanSetNetworkOwnership() then
			st.Root:SetNetworkOwner(driver)
		end
		st.Model:SetAttribute("Driver", driver and driver.UserId or nil)
		st.LastGood = st.Root.CFrame
		st.LastGoodAt = os.clock()
		st.Strikes = 0
	end
end

local function updatePrompt(st)
	local free = 0
	for _, seat in st.Seats do
		if not seat.Occupant then
			free += 1
		end
	end
	local prompt = st.Prompt
	prompt.Enabled = free > 0 and not st.Model:GetAttribute("Destroyed")
	prompt.ActionText = if st.SeatByRole.Driver and not st.SeatByRole.Driver.Occupant then "Drive" else "Board"
	st.Model:SetAttribute("Team", vehicleTeam(st))
	st.Model:SetAttribute("Crew", #st.Seats - free)
end

local function onSeatChanged(st, seat: Seat)
	local now = seatOccupant(seat)
	local before = st.SeatPlayers[seat]
	if before == now then
		return
	end
	st.SeatPlayers[seat] = now
	if before then
		local character = before.Character
		local it = intent[before]
		intent[before] = nil
		restoreOccupant(before, character)
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if character and hum and hum.Health > 0 and character.Parent then
			if it and it.Kind == "Switch" then
				-- re-seated by onSwitch; nothing else to do
			else
				local cf = (it and it.CF) or findExit(st, seat)
				if cf then
					local vel = st.Root.AssemblyLinearVelocity
					placeAt(before, character, cf, Vector3.new(vel.X, 0, vel.Z) * 0.4)
				end
			end
		end
		EventRemote:FireClient(before, "Left", st.Model)
	end
	if now then
		local character = now.Character
		if character then
			applyOccupant(now, character, st, seat)
		end
		st.LastUsed = os.clock()
		EventRemote:FireClient(now, "Seated", st.Model, seat:GetAttribute("SeatIndex"))
	end
	updateOwner(st)
	updatePrompt(st)
end

-- ─── spawning ────────────────────────────────────────────────────────────
local function spawnMarkers(): { BasePart }
	local list = {}
	local seen = {}
	for _, p in CollectionService:GetTagged("VehicleSpawn") do
		if p:IsA("BasePart") and p:IsDescendantOf(Workspace) then
			seen[p] = true
			table.insert(list, p)
		end
	end
	for _, f in Workspace:GetDescendants() do
		if f:IsA("Folder") and f.Name == "VehicleSpawns" then
			for _, p in f:GetChildren() do
				if p:IsA("BasePart") and not seen[p] then
					table.insert(list, p)
				end
			end
		end
	end
	return list
end

local function setup(model: Model, marker: BasePart?)
	local root = model.PrimaryPart :: BasePart
	local kind = model:GetAttribute("VehicleType")
	local cfg = Config.Vehicles[kind]
	nextId += 1
	model:SetAttribute("VehicleId", nextId)
	model:SetAttribute("Health", cfg.Health)
	model:SetAttribute("MaxHealth", cfg.Health)
	model:SetAttribute("Shield", cfg.Shield.Max)
	model:SetAttribute("MaxShield", cfg.Shield.Max)
	model:SetAttribute("AimYaw", 0)
	model:SetAttribute("AimPitch", 0)
	model:SetAttribute("Heat", 0)
	model:SetAttribute("ReadyAt", 0)
	model:SetAttribute("Throttle", 0)
	model:SetAttribute("Steer", 0)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP_VEHICLE
		end
	end
	local st = {
		Model = model, Root = root, Kind = kind, Cfg = cfg, Marker = marker,
		SpawnTeam = marker and marker:GetAttribute("Team") or nil,
		Seats = {}, SeatByRole = {}, SeatPlayers = {},
		Sim = Sim.new(model),
		Input = { Throttle = 0, Steer = 0, Brake = false },
		Owner = nil,
		Yaw = 0, Pitch = 0, WantYaw = 0, WantPitch = 0,
		Trigger = false, Heat = 0, HeatAt = 0, LockedUntil = 0, NextShot = 0, ReadyAt = 0, Rounds = 0,
		LastUsed = os.clock(), LastGood = root.CFrame, LastGoodAt = os.clock(), Strikes = 0,
		RunOverHits = {},
		Shield = cfg.Shield.Max, ShieldHitAt = 0,
		LastAttacker = nil, LastWeapon = nil,
	}
	for _, seat in model.Seats:GetChildren() do
		if seat:IsA("Seat") then
			st.Seats[seat:GetAttribute("SeatIndex")] = seat
			local role = seat:GetAttribute("Role")
			if not st.SeatByRole[role] then
				st.SeatByRole[role] = seat
			end
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				onSeatChanged(st, seat)
			end)
		end
	end
	if cfg.Weapon.Homing then
		local lock = Instance.new("ObjectValue")
		lock.Name = "Lock" -- the homing target (clients draw the lock marker)
		lock.Parent = model
		st.LockValue = lock
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ObjectText = cfg.DisplayName
	prompt.ActionText = "Drive"
	prompt.KeyboardKeyCode = Config.Interact.Key
	prompt.GamepadKeyCode = Config.Interact.GamepadKey
	prompt.HoldDuration = Config.Interact.HoldTime
	prompt.MaxActivationDistance = math.max(root.Size.X, root.Size.Z) / 2 + 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = root
	st.Prompt = prompt
	prompt.Triggered:Connect(function(player)
		Service.Enter(player, model)
	end)
	Service.Vehicles[model] = st
	CollectionService:AddTag(model, Config.Tag)
	updatePrompt(st)
	return st
end

function Service.Spawn(kind: string, cf: CFrame, marker: BasePart?): Model
	local template = ServerStorage.Vehicles.Templates:FindFirstChild(kind) :: Model
	local model = template:Clone()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the whole vehicle streams in / out together
	model:PivotTo(cf)
	local folder = Workspace:FindFirstChild("Vehicles") or Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = Workspace
	model.Parent = folder
	local st = setup(model, marker)
	st.Root:SetNetworkOwner(nil)
	Service.Stats.Spawned += 1
	return model
end

local function markerCF(marker: BasePart): CFrame
	local look = Vector3.new(marker.CFrame.LookVector.X, 0, marker.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local base = marker.Position - Vector3.new(0, marker.Size.Y / 2, 0)
	-- the template's WorldPivot looks along the vehicle's front, so the front follows `look`
	return CFrame.lookAt(base + Vector3.new(0, 0.6, 0), base + Vector3.new(0, 0.6, 0) + look)
end

local respawnQueue = {} -- { Marker, At }
local function spawnAt(marker: BasePart)
	local kind = marker:GetAttribute("Vehicle")
	if not Config.Vehicles[kind] then
		warn("[VehicleService] spawn marker with unknown Vehicle:", marker:GetFullName(), kind)
		return
	end
	local model = Service.Spawn(kind, markerCF(marker), marker)
	marker:SetAttribute("Live", model:GetAttribute("VehicleId"))
end

local function queueRespawn(st, delay: number?)
	local marker = st.Marker
	if not marker then
		return
	end
	marker:SetAttribute("Live", nil)
	local t = delay or marker:GetAttribute("RespawnTime") or st.Cfg.RespawnTime
	table.insert(respawnQueue, { Marker = marker, At = os.clock() + t })
	marker:SetAttribute("RespawnAt", Workspace:GetServerTimeNow() + t)
end

-- ─── enter / exit / switch ───────────────────────────────────────────────
function Service.Enter(player: Player, model: Model, seatIndex: number?)
	local st = Service.Vehicles[model]
	local character, hum = alive(player)
	if not st or not character or not hum or model:GetAttribute("Destroyed") then
		return false
	end
	if hum.SeatPart or character:GetAttribute("VantageHanging") or character:GetAttribute("InVehicle") then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or (hrp.Position - st.Root.Position).Magnitude > st.Prompt.MaxActivationDistance + 6 then
		return false
	end
	-- no boarding a vehicle crewed by the other team
	local vt = vehicleTeam(st)
	local pt = teamName(player)
	if #occupants(st) > 0 and vt and pt and vt ~= pt then
		return false
	end
	if #occupants(st) == 0 and not Config.Interact.EnemyCanTakeEmpty and st.SpawnTeam and pt and st.SpawnTeam ~= pt then
		return false
	end
	if st.Bot and pt and st.Bot.Team ~= pt then
		return false -- an enemy AI is driving it
	end
	local seat: Seat? = nil
	if seatIndex then
		local s = st.Seats[seatIndex]
		if s and not s.Occupant then
			seat = s
		end
	else
		for i = 1, #st.Seats do
			if not st.Seats[i].Occupant then
				seat = st.Seats[i]
				break
			end
		end
	end
	if not seat then
		return false
	end
	-- a simultaneous claim by someone else this frame loses: the Occupant is set synchronously
	seat:Sit(hum)
	return seat.Occupant == hum
end

local function onExit(player: Player)
	local rec = saved[player]
	local character, hum = alive(player)
	if not rec or not character or not hum then
		return
	end
	local st = Service.Vehicles[rec.Vehicle]
	local seat = rec.Seat
	if not st or not seat or seat.Occupant ~= hum then
		return
	end
	local cf = findExit(st, seat)
	intent[player] = { Kind = "Exit", CF = cf }
	local w = seat:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	hum.Sit = false
end
Service.Exit = onExit

local function onSwitch(player: Player, index: any)
	local rec = saved[player]
	local character, hum = alive(player)
	if not rec or not character or not hum or type(index) ~= "number" then
		return
	end
	local st = Service.Vehicles[rec.Vehicle]
	local target = st and st.Seats[math.floor(index)]
	if not st or not target or target.Occupant or target == rec.Seat or st.Model:GetAttribute("Destroyed") then
		return
	end
	intent[player] = { Kind = "Switch" }
	local fromSeat = rec.Seat
	local w = fromSeat:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	task.defer(function()
		if hum.Health > 0 and not target.Occupant then
			target:Sit(hum)
		end
		if not hum.SeatPart then
			-- seat got taken in between: climb out instead
			intent[player] = nil
			local cf = findExit(st, fromSeat)
			if cf then
				placeAt(player, character, cf)
			end
		end
	end)
end

-- ─── damage ──────────────────────────────────────────────────────────────
local destroyVehicle

-- returns (damage dealt, of which the shield absorbed); (0, 0) if blocked.
-- The energy shield takes damage first; only the overflow reaches the hull.
function Service.DamageVehicle(model: Model, amount: number, attacker: Player?, weaponId: string?, position: Vector3?)
	local st = Service.Vehicles[model]
	if not st or model:GetAttribute("Destroyed") or amount <= 0 then
		return 0, 0
	end
	if not combatOn() then
		return 0, 0
	end
	if attacker then
		local at, vt = teamName(attacker), vehicleTeam(st)
		-- Studio solo testing: empty vehicles take hits from either team
		local neutral = RunService:IsStudio() and Config.Studio and Config.Studio.EmptyVehiclesNeutral and #occupants(st) == 0
		if at and vt and at == vt and not WeaponConfig.FriendlyFire and not neutral then
			return 0, 0
		end
		st.LastAttacker = attacker
		st.LastWeapon = weaponId
	end
	local now = os.clock()
	st.ShieldHitAt = now
	local absorbed = math.min(st.Shield, amount)
	local rest = amount - absorbed
	local pos = position or st.Root.Position
	if absorbed > 0 then
		st.Shield -= absorbed
		local broke = st.Shield <= 0.01
		if broke then
			st.Shield = 0
		end
		model:SetAttribute("Shield", math.floor(st.Shield + 0.5))
		fire("ShieldHit", model, pos, absorbed, broke)
	end
	local hp = model:GetAttribute("Health") :: number
	local new = hp
	if rest > 0 then
		new = math.max(0, hp - rest)
		model:SetAttribute("Health", new)
	end
	for _, p in occupants(st) do
		EventRemote:FireClient(p, "Hull", amount, pos, absorbed >= amount)
	end
	if new <= 0 then
		destroyVehicle(st, attacker, weaponId)
	end
	return absorbed + (hp - new), absorbed
end

-- tell a shooter what their hit did: kind = "Infantry" | "Shield" | "Hull"; final = kill / vehicle destroyed
local function confirm(shooter: Player?, amount: number, kind: string, position: Vector3?, final: boolean)
	if shooter and amount > 0 then
		EventRemote:FireClient(shooter, "HitConfirm", amount, kind, position, final)
	end
end
local function confirmVehicle(shooter: Player?, model: Model, dealt: number, absorbed: number, position: Vector3?)
	if dealt > 0 then
		confirm(shooter, dealt, if absorbed >= dealt then "Shield" else "Hull", position, model:GetAttribute("Destroyed") == true)
	end
end

-- WeaponServer hook: a validated gun hit landed on a part (non-character)
local function onGunHit(shooter: Player, weapon, hit, amount: number?)
	local model = vehicleOf(hit.Instance)
	if not model then
		return nil
	end
	local base = amount or WeaponMath.Damage(weapon, false, false, hit.Distance or 0)
	local mult = Config.SmallArms[weapon.Id]
	if mult == nil then
		mult = Config.SmallArms.Default
	end
	-- 2026-11-20: per-vehicle toughness vs small arms (the drone is fragile: SmallArmsTaken > 1)
	local vcfg = Config.Vehicles[model:GetAttribute("VehicleType")]
	if vcfg and vcfg.SmallArmsTaken then
		mult *= vcfg.SmallArmsTaken
	end
	local dealt, absorbed = Service.DamageVehicle(model, base * mult, shooter, weapon.Id, hit.Position)
	confirmVehicle(shooter, model, dealt, absorbed, hit.Position)
	return dealt
end

-- damage a character through the shared pipeline (friendly fire, shields, kill credit, feed)
local function hurtCharacter(attacker: Player, weaponId: string, character: Model, amount: number, position: Vector3, direction: Vector3, explosive: boolean?)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	-- Explosive: the kill feed shows a blast (tank splash, caught in a destroyed vehicle)
	local result = DamageService.Apply(attacker, { Id = weaponId, Kind = "Vehicle", Explosive = explosive == true }, {
		Character = character, Humanoid = hum, IsHead = false, IsLimb = false,
		Distance = 0, Position = position, Direction = direction,
	}, amount)
	if result and result.Damage > 0 then
		local victim = Players:GetPlayerFromCharacter(character)
		if victim then
			WeaponEvent:FireClient(victim, "Damaged", position - direction * 20, result.Damage)
		end
		confirm(attacker, result.Damage, "Infantry", position, result.Killed == true)
	end
	return result
end
Service.HurtCharacter = hurtCharacter

destroyVehicle = function(st, attacker: Player?, weaponId: string?)
	local model = st.Model
	if model:GetAttribute("Destroyed") then
		return
	end
	model:SetAttribute("Destroyed", true)
	model:SetAttribute("Health", 0)
	Service.Stats.Destroyed += 1
	st.Trigger = false
	local pos = st.Root.Position
	fire("Destroyed", model, pos)
	-- everyone inside is thrown clear and hurt by the blast (credited to the destroyer)
	for _, seat in st.Seats do
		local p = seatOccupant(seat)
		if p then
			local character = p.Character
			local cf = findExit(st, seat)
			intent[p] = { Kind = "Exit", CF = cf }
			local w = seat:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Sit = false
			end
			task.defer(function()
				local hum2 = character and character:FindFirstChildOfClass("Humanoid")
				if not character or not hum2 or hum2.Health <= 0 then
					return
				end
				if Config.Destruction.KillCrew then
					-- the crew goes down with the vehicle; the destroyer gets the kills (feed, score, streaks)
					local result = nil
					if attacker and attacker ~= p then
						result = hurtCharacter(attacker, weaponId or "VehicleDestroyed", character, 100000, pos, Vector3.yAxis, true)
					end
					if hum2.Health > 0 then
						-- no enemy credit possible (fell out of the world, own fire, spawn shield): still lethal
						character:SetAttribute("DeathCause", "Explosion") -- kill feed: an environmental blast
						character:SetAttribute("Shield", 0)
						hum2.Health = 0
					end
				elseif attacker and attacker ~= p then
					hurtCharacter(attacker, weaponId or "VehicleDestroyed", character, Config.Destruction.OccupantDamage, pos, Vector3.yAxis, true)
				end
			end)
		end
	end
	-- an AI driver goes down with it too (credited to the destroyer when there is one)
	local bot = st.Bot
	if bot then
		Service.BotRelease(model, true)
		task.defer(function()
			local h = bot.Hum
			if not h or h.Health <= 0 or not bot.Model.Parent then
				return
			end
			if attacker then
				hurtCharacter(attacker, weaponId or "VehicleDestroyed", bot.Model, 100000, pos, Vector3.yAxis, true)
			end
			if h.Health > 0 then
				bot.Model:SetAttribute("DeathCause", "Explosion")
				bot.Model:SetAttribute("Shield", 0)
				h.Health = 0
			end
		end)
	end
	st.Prompt.Enabled = false
	st.Sim:Clear()
	if st.Root:CanSetNetworkOwnership() then
		st.Root:SetNetworkOwner(nil)
	end
	st.Owner = nil
	-- a small upward kick so the wreck settles visibly
	st.Root:ApplyImpulse(Vector3.new(0, st.Root.AssemblyMass * 28, 0))
	queueRespawn(st)
	task.delay(Config.Destruction.WreckTime, function()
		if not model.Parent then
			return
		end
		local info = TweenInfo.new(Config.Destruction.FadeTime)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
		task.wait(Config.Destruction.FadeTime + 0.1)
		Service.Vehicles[model] = nil
		model:Destroy()
	end)
end
Service.Destroy = function(model: Model, attacker: Player?, weaponId: string?)
	local st = Service.Vehicles[model]
	if st then
		destroyVehicle(st, attacker, weaponId)
	end
end

-- quietly remove (abandoned / match reset): occupants are moved out unharmed
local function recycle(st, respawnNow: boolean)
	local model = st.Model
	if st.Bot then
		Service.BotRelease(model)
	end
	model:SetAttribute("Destroyed", true)
	for _, seat in st.Seats do
		local p = seatOccupant(seat)
		if p then
			intent[p] = { Kind = "Exit", CF = findExit(st, seat) }
			local w = seat:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
		end
	end
	Service.Vehicles[model] = nil
	task.delay(0.1, function()
		model:Destroy()
	end)
	queueRespawn(st, if respawnNow then 0.2 else 3)
end

-- ─── weapons ─────────────────────────────────────────────────────────────
local function vehicleExclude(st): { Instance }
	local ex = characters()
	table.insert(ex, st.Model)
	return ex
end

-- world/vehicle ray (characters excluded) + character hitboxes via HitValidation
local function castShot(st, shooter: Player, origin: Vector3, dir: Vector3, range: number)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = vehicleExclude(st)
	rp.IgnoreWater = true
	local world = Workspace:Raycast(origin, dir * range, rp)
	local maxT = if world then (world.Position - origin).Magnitude else range
	local ch = HitValidation.Cast(shooter, origin, dir, maxT + 0.05, nil)
	if ch.Kind == "Character" and ch.Distance <= maxT + 0.05 then
		return ch
	end
	if world then
		return { Kind = "World", Position = world.Position, Normal = world.Normal, Distance = maxT, Instance = world.Instance, Material = world.Material }
	end
	return { Kind = "None", Position = origin + dir * range, Normal = -dir, Distance = range }
end

local function explode(st, shooter: Player, pos: Vector3, directModel: Model?, directChar: Model?)
	local W = st.Cfg.Weapon
	-- vehicles: direct hit full, others in the radius take splash
	if directModel then
		local dealt, absorbed = Service.DamageVehicle(directModel, W.DirectVehicle, shooter, W.Id, pos)
		confirmVehicle(shooter, directModel, dealt, absorbed, pos)
	end
	for model, other in Service.Vehicles do
		if model ~= directModel and model ~= st.Model and not model:GetAttribute("Destroyed") then
			local d = (other.Root.Position - pos).Magnitude - math.max(other.Root.Size.X, other.Root.Size.Z) * 0.35
			if d < W.SplashRadius then
				local f = 1 - math.clamp(d / W.SplashRadius, 0, 1)
				local dealt, absorbed = Service.DamageVehicle(model, W.SplashVehicle * f, shooter, W.Id, pos)
				confirmVehicle(shooter, model, dealt, absorbed, other.Root.Position)
			end
		end
	end
	-- infantry: line-of-sight splash with falloff (crews inside hulls are protected)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = characters()
	-- every damageable character (players, and Studio training dummies)
	for _, c in HitValidation.TargetCharacters() do
		local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not c:GetAttribute("VehicleHidden") then
			local d = (root.Position - pos).Magnitude
			if c == directChar then
				hurtCharacter(shooter, W.Id, c, W.DirectInfantry, pos, (root.Position - pos).Unit)
			elseif d < W.SplashRadius then
				local blocked = Workspace:Raycast(pos, root.Position - pos, rp)
				if not blocked or vehicleOf(blocked.Instance) == st.Model then
					local f = 1 - (1 - W.SplashMin) * math.clamp(d / W.SplashRadius, 0, 1)
					local dir = if d > 0.1 then (root.Position - pos).Unit else Vector3.yAxis
					hurtCharacter(shooter, W.Id, c, W.SplashInfantry * f, pos, dir, true)
				end
			end
		end
	end
end

local function targetPoint(t: Instance): Vector3?
	if t:IsA("Model") then
		local hrp = t:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			return hrp.Position + Vector3.new(0, 0.6, 0)
		end
		-- a vehicle: the middle of its body (the Root sits down at axle height, behind every curb)
		local vst = Service.Vehicles[t]
		if vst and vst.Root.Parent then
			if not vst.AimOffset then
				local box = t:GetBoundingBox()
				vst.AimOffset = vst.Root.CFrame:PointToObjectSpace(box.Position)
			end
			return vst.Root.CFrame:PointToWorldSpace(vst.AimOffset)
		end
		if t.PrimaryPart then
			return t.PrimaryPart.Position
		end
	end
	return nil
end
local function fireCannon(st, shooter: Player, now: number)
	local W = st.Cfg.Weapon
	if now < st.ReadyAt then
		return
	end
	st.ReadyAt = now + W.Reload
	st.Model:SetAttribute("ReadyAt", Workspace:GetServerTimeNow() + W.Reload)
	local m = VMath.Muzzle(st.Root.CFrame, st.Model, st.Yaw, st.Pitch)
	nextId += 1
	local id = nextId
	local dir = m.LookVector
	-- auto-aim: with a lock, aim where the target will be (its motion + the shell's drop)
	local lockPos = if W.Homing and st.Lock and st.Lock.Parent then targetPoint(st.Lock) else nil
	if lockPos then
		local tgt = st.Lock :: Instance
		local tpart = if tgt:IsA("Model") then (tgt:FindFirstChild("HumanoidRootPart") or tgt.PrimaryPart) else tgt
		local tv = if tpart and tpart:IsA("BasePart") then tpart.AssemblyLinearVelocity else Vector3.zero
		local rel = tv - st.Root.AssemblyLinearVelocity -- the shell inherits our own velocity
		local drop = Workspace.Gravity * W.ShellGravity
		local aim = lockPos
		for _ = 1, 4 do
			local t = (aim - m.Position).Magnitude / W.ShellSpeed
			aim = lockPos + rel * t + Vector3.new(0, 0.5 * drop * t * t, 0)
		end
		dir = (aim - m.Position).Unit
	end
	local vel = dir * W.ShellSpeed + st.Root.AssemblyLinearVelocity
	table.insert(shells, { Id = id, St = st, Shooter = shooter, Pos = m.Position, Vel = vel, Travelled = 0, Born = now })
	Service.Stats.ShellsFired += 1
	fire("Shell", st.Model, id, m.Position, vel, W.ShellGravity)
	-- recoil: a short shove back along the barrel
	st.Root:ApplyImpulse(-dir * st.Root.AssemblyMass * W.Recoil)
end

local function stepShells(dt: number)
	local g = Workspace.Gravity
	for i = #shells, 1, -1 do
		local s = shells[i]
		local st = s.St
		local W = st.Cfg.Weapon
		local done = false
		if not s.Shooter.Parent or s.Travelled > W.MaxRange then
			done = true
			fire("Impact", s.Id, s.Pos, Vector3.yAxis, "None", nil)
		else
			local nv = s.Vel - Vector3.new(0, g * W.ShellGravity * dt, 0)
			local step = (s.Vel + nv) * 0.5 * dt
			local len = step.Magnitude
			local hit = castShot(st, s.Shooter, s.Pos, step.Unit, len)
			if hit.Kind ~= "None" then
				done = true
				local directModel = if hit.Kind == "World" then vehicleOf(hit.Instance) else nil
				local directChar = if hit.Kind == "Character" then hit.Character else nil
				if directModel == st.Model then
					directModel = nil
				end
				explode(st, s.Shooter, hit.Position, directModel, directChar)
				fire("Impact", s.Id, hit.Position, hit.Normal, "Explode", W.SplashRadius)
			else
				s.Pos += step
				s.Vel = nv
				s.Travelled += len
			end
		end
		if done then
			table.remove(shells, i)
		end
	end
end

-- homing (drone): the enemy closest to the gun's aim inside the cone, in range, in sight
local function lockTarget(st, shooter: Player): Instance?
	local H = st.Cfg.Weapon.Homing
	local m = VMath.Muzzle(st.Root.CFrame, st.Model, st.Yaw, st.Pitch)
	local best, bestAng = nil, math.rad(H.Cone)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = vehicleExclude(st)
	local function consider(target: Instance, pos: Vector3)
		local d = pos - m.Position
		local dist = d.Magnitude
		if dist < 3 or dist > H.Range then
			return
		end
		local ang = math.acos(math.clamp(m.LookVector:Dot(d.Unit), -1, 1))
		if ang >= bestAng then
			return
		end
		local block = Workspace:Raycast(m.Position, d, rp)
		if block and not block.Instance:IsDescendantOf(target) and vehicleOf(block.Instance) ~= target then
			return -- behind cover
		end
		best, bestAng = target, ang
	end
	local function vehiclesPass()
		for model, other in Service.Vehicles do
			if model ~= st.Model and not model:GetAttribute("Destroyed") then
				local at, vt = teamName(shooter), vehicleTeam(other)
				local neutral = RunService:IsStudio() and Config.Studio and Config.Studio.EmptyVehiclesNeutral and #occupants(other) == 0
				if not (at and vt and at == vt) or neutral then
					consider(model, targetPoint(model) or other.Root.Position)
				end
			end
		end
	end
	if H.Prefer == "Vehicles" then
		vehiclesPass()
		if best then
			return best
		end
	end
	for _, c in HitValidation.TargetCharacters() do
		local hum = c:FindFirstChildOfClass("Humanoid")
		local pos = targetPoint(c)
		if hum and pos and hum.Health > 0 and c ~= shooter.Character and not c:GetAttribute("VehicleHidden")
			and not DamageService.IsFriendly(shooter, c) then
			consider(c, pos)
		end
	end
	if best or H.Prefer == "Vehicles" then
		return best -- MGs: infantry (players and bots) take priority over vehicles
	end
	vehiclesPass()
	return best
end

-- Studio test hook: set attribute TestLock (Vector2: yaw, pitch in degrees) on a vehicle; the server
-- answers with TestLockResult (name of what the homing would lock, or "none")
if RunService:IsStudio() then
	task.spawn(function()
		while true do
			task.wait(0.2)
			for model, st in Service.Vehicles do
				if model:GetAttribute("TestHold") then
					st.LastUsed = os.clock() -- parked by a test: not abandoned
				end
				local q = model:GetAttribute("TestLock")
				if typeof(q) == "Vector2" and st.Cfg.Weapon and st.Cfg.Weapon.Homing then
					model:SetAttribute("TestLock", nil)
					local p = Players:GetPlayers()[1]
					if p then
						st.Yaw, st.Pitch = math.rad(q.X), math.rad(q.Y)
						local t = lockTarget(st, p)
						model:SetAttribute("TestLockResult", if t then t.Name else "none")
						if model:GetAttribute("TestFire") and st.Cfg.Weapon.Kind == "Cannon" then
							model:SetAttribute("TestFire", nil)
							st.Lock = t
							st.ReadyAt = 0
							fireCannon(st, p, os.clock())
						end
					end
				end
			end
		end
	end)
end

local function fireMG(st, shooter: Player, now: number)
	local W = st.Cfg.Weapon
	local interval = 60 / W.RPM
	if st.NextShot < now - interval then
		st.NextShot = now
	end
	local shots = {}
	while st.NextShot <= now and #shots < 4 do
		local H = W.Heat
		if now < st.LockedUntil then
			break
		end
		st.Heat = math.min(1, st.Heat + H.PerShot)
		st.HeatAt = now
		if st.Heat >= 1 then
			st.LockedUntil = now + H.Lock
		end
		st.NextShot += interval
		local base = VMath.Muzzle(st.Root.CFrame, st.Model, st.Yaw, st.Pitch)
		local barrels = W.Barrels or 1
		local lockPos = if W.Homing and st.Lock and st.Lock.Parent then targetPoint(st.Lock) else nil
		local spread = st.Model:GetAttribute("BarrelSpread") or 0
		for b = 1, barrels do
			-- twin guns (drone): barrel 1 on the left, 2 on the right — two lines of rounds per shot
			local m = if barrels > 1 then base * CFrame.new(if b == 1 then -spread else spread, 0, 0) else base
			local aim = if lockPos then (lockPos - m.Position).Unit else m.LookVector
			local dir = VMath.Spread(aim, W.Spread, rng)
			local hit = castShot(st, shooter, m.Position, dir, W.MaxRange)
			st.Rounds += 1
			Service.Stats.RoundsFired += 1
			if hit.Kind == "Character" then
				local dmg = W.Damage
				-- 2026-11-20: optional range falloff (drone): full to Start, down to Min at End
				local F = W.Falloff
				if F then
					local dist = (hit.Position - m.Position).Magnitude
					dmg *= 1 - (1 - F.Min) * math.clamp((dist - F.Start) / math.max(F.End - F.Start, 1), 0, 1)
				end
				hurtCharacter(shooter, W.Id, hit.Character, if hit.IsHead then dmg * 1.25 else dmg, hit.Position, dir)
			elseif hit.Kind == "World" then
				local model = vehicleOf(hit.Instance)
				if model and model ~= st.Model then
					local dealt, absorbed = Service.DamageVehicle(model, W.Damage * W.VehicleMultiplier, shooter, W.Id, hit.Position)
					confirmVehicle(shooter, model, dealt, absorbed, hit.Position)
				end
			end
			table.insert(shots, { hit.Position, hit.Normal, hit.Kind, if hit.Material then hit.Material.Name else nil, barrels > 1 or (st.Rounds % W.TracerEvery) == 0, b })
		end
	end
	if #shots > 0 then
		fire("Shots", st.Model, shots)
	end
end

-- ─── input ───────────────────────────────────────────────────────────────
-- ─── AI crews (Studio: SquadBots) ───
--[[ A bot (a Humanoid model, not a Player) sits in the Driver seat and the server simulates the
	vehicle with the bot's input (same VehicleSim as an empty vehicle). It also works the gun unless a
	player sits in the gunner seat (then the player has the turret: bot drives, you shoot).
	Bots are not Players, so their rounds and shells use their own rays here, and infantry damage goes
	through Service.BotHurt (set by SquadBots: shields, kill feed, score). Vehicles take damage through
	DamageVehicle as usual.
	  Service.BotEnter(bot, vehicle, team) -> boolean
	  Service.BotControl(vehicle, throttle, steer, brake, aimPoint?, trigger)
	  Service.BotRelease(vehicle, noPlace?)
]]
Service.BotHurt = nil :: any
local botShells = {}

local function charOf(inst: Instance?): Model?
	while inst and inst ~= Workspace do
		if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local function botFriends(st): { Instance }
	local team = st.Bot.Team
	local list: { Instance } = { st.Model, st.Bot.Model }
	for _, c in HitValidation.TargetCharacters() do
		if DamageService.TeamOf(c) == team then
			table.insert(list, c)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character and teamName(p) == team then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function botCast(st, origin: Vector3, dir: Vector3, range: number)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = botFriends(st)
	rp.IgnoreWater = true
	local res = Workspace:Raycast(origin, dir * range, rp)
	if not res then
		return { Kind = "None", Position = origin + dir * range, Normal = -dir, Distance = range }
	end
	local c = charOf(res.Instance)
	if c and not vehicleOf(res.Instance) then
		return { Kind = "Character", Character = c, Position = res.Position, Normal = res.Normal, Distance = res.Distance, IsHead = res.Instance.Name == "Head" }
	end
	return { Kind = "World", Instance = res.Instance, Position = res.Position, Normal = res.Normal, Distance = res.Distance, Material = res.Material }
end

local function botHurt(st, c: Model, amount: number, pos: Vector3, dir: Vector3, explosive: boolean?)
	local bot = st.Bot
	if not bot or c:GetAttribute("VehicleHidden") or DamageService.TeamOf(c) == bot.Team then
		return
	end
	if Service.BotHurt then
		Service.BotHurt(bot.Model, c, amount, st.Cfg.Weapon.Id, pos, dir, explosive == true)
	end
end

local function botHitVehicle(st, model: Model, amount: number, pos: Vector3)
	local other = Service.Vehicles[model]
	if not other or model == st.Model then
		return
	end
	local neutral = RunService:IsStudio() and Config.Studio and Config.Studio.EmptyVehiclesNeutral and #occupants(other) == 0 and not other.Bot
	if vehicleTeam(other) == st.Bot.Team and not neutral then
		return
	end
	Service.DamageVehicle(model, amount, nil, st.Cfg.Weapon.Id, pos)
end

local function botExplode(st, pos: Vector3, directModel: Model?, directChar: Model?)
	local W = st.Cfg.Weapon
	if directModel then
		botHitVehicle(st, directModel, W.DirectVehicle, pos)
	end
	for model, other in Service.Vehicles do
		if model ~= directModel and model ~= st.Model and not model:GetAttribute("Destroyed") then
			local d = (other.Root.Position - pos).Magnitude - math.max(other.Root.Size.X, other.Root.Size.Z) * 0.35
			if d < W.SplashRadius then
				botHitVehicle(st, model, W.SplashVehicle * (1 - math.clamp(d / W.SplashRadius, 0, 1)), other.Root.Position)
			end
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = HitValidation.TargetCharacters()
	for _, c in HitValidation.TargetCharacters() do
		local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not c:GetAttribute("VehicleHidden") then
			local d = (root.Position - pos).Magnitude
			local dir = if d > 0.1 then (root.Position - pos).Unit else Vector3.yAxis
			if c == directChar then
				botHurt(st, c, W.DirectInfantry, pos, dir, true)
			elseif d < W.SplashRadius then
				local blocked = Workspace:Raycast(pos, root.Position - pos, rp)
				if not blocked or vehicleOf(blocked.Instance) == st.Model then
					botHurt(st, c, W.SplashInfantry * (1 - (1 - W.SplashMin) * math.clamp(d / W.SplashRadius, 0, 1)), pos, dir, true)
				end
			end
		end
	end
end

local function botFireCannon(st, now: number)
	local W = st.Cfg.Weapon
	if now < st.ReadyAt then
		return
	end
	st.ReadyAt = now + W.Reload
	st.Model:SetAttribute("ReadyAt", Workspace:GetServerTimeNow() + W.Reload)
	local m = VMath.Muzzle(st.Root.CFrame, st.Model, st.Yaw, st.Pitch)
	nextId += 1
	local dir = VMath.Spread(m.LookVector, 0.6, rng)
	local vel = dir * W.ShellSpeed + st.Root.AssemblyLinearVelocity
	table.insert(botShells, { Id = nextId, St = st, Pos = m.Position, Vel = vel, Travelled = 0 })
	Service.Stats.ShellsFired += 1
	fire("Shell", st.Model, nextId, m.Position, vel, W.ShellGravity)
	st.Root:ApplyImpulse(-dir * st.Root.AssemblyMass * W.Recoil)
end

local function stepBotShells(dt: number)
	local g = Workspace.Gravity
	for i = #botShells, 1, -1 do
		local s = botShells[i]
		local st = s.St
		local W = st.Cfg.Weapon
		local done = false
		if not st.Bot or s.Travelled > W.MaxRange then
			done = true
			fire("Impact", s.Id, s.Pos, Vector3.yAxis, "None", nil)
		else
			local nv = s.Vel - Vector3.new(0, g * W.ShellGravity * dt, 0)
			local step = (s.Vel + nv) * 0.5 * dt
			local len = step.Magnitude
			local hit = botCast(st, s.Pos, step.Unit, len)
			if hit.Kind ~= "None" then
				done = true
				local directModel = if hit.Kind == "World" then vehicleOf(hit.Instance) else nil
				if directModel == st.Model then
					directModel = nil
				end
				botExplode(st, hit.Position, directModel, if hit.Kind == "Character" then hit.Character else nil)
				fire("Impact", s.Id, hit.Position, hit.Normal, "Explode", W.SplashRadius)
			else
				s.Pos += step
				s.Vel = nv
				s.Travelled += len
			end
		end
		if done then
			table.remove(botShells, i)
		end
	end
end

local function botFireMG(st, now: number)
	local W = st.Cfg.Weapon
	local interval = 60 / W.RPM
	if st.NextShot < now - interval then
		st.NextShot = now
	end
	local shots = {}
	while st.NextShot <= now and #shots < 4 do
		local H = W.Heat
		if H and now < st.LockedUntil then
			break
		end
		if H then
			st.Heat = math.min(1, st.Heat + H.PerShot)
			st.HeatAt = now
			if st.Heat >= 1 then
				st.LockedUntil = now + H.Lock
			end
		end
		st.NextShot += interval
		local m = VMath.Muzzle(st.Root.CFrame, st.Model, st.Yaw, st.Pitch)
		local dir = VMath.Spread(m.LookVector, W.Spread + 0.8, rng)
		local hit = botCast(st, m.Position, dir, W.MaxRange)
		st.Rounds += 1
		Service.Stats.RoundsFired += 1
		if hit.Kind == "Character" then
			botHurt(st, hit.Character, if hit.IsHead then W.Damage * 1.25 else W.Damage, hit.Position, dir)
		elseif hit.Kind == "World" then
			local model = vehicleOf(hit.Instance)
			if model then
				botHitVehicle(st, model, W.Damage * W.VehicleMultiplier, hit.Position)
			end
		end
		table.insert(shots, { hit.Position, hit.Normal, hit.Kind, if hit.Material then hit.Material.Name else nil, (st.Rounds % W.TracerEvery) == 0, 1 })
	end
	if #shots > 0 then
		fire("Shots", st.Model, shots)
	end
end

-- an AI driver's hull runs people over like a player's does
local function botRunOver(st, now: number)
	local R = st.Cfg.RunOver
	local root = st.Root
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if not R or speed < R.MinSpeed then
		return
	end
	local cf, size = root.CFrame, root.Size + Vector3.new(3, 4, 3)
	for _, c in HitValidation.TargetCharacters() do
		local hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and c ~= st.Bot.Model and not c:GetAttribute("InVehicle") then
			local lp = cf:PointToObjectSpace(hrp.Position)
			if math.abs(lp.X) < size.X / 2 and math.abs(lp.Y) < size.Y / 2 and math.abs(lp.Z) < size.Z / 2
				and (hrp.Position - root.Position):Dot(v) > 0 and (st.RunOverHits[c] or 0) < now then
				st.RunOverHits[c] = now + 0.6
				local dmg = if speed >= R.KillSpeed then 999 else R.Damage * math.clamp(speed / (R.DamageAt or R.KillSpeed), 0.25, 1)
				if Service.BotHurt and DamageService.TeamOf(c) ~= st.Bot.Team then
					Service.BotHurt(st.Bot.Model, c, dmg, st.Cfg.Weapon.Id .. "_RunOver", hrp.Position, v.Unit, false)
				end
			end
		end
	end
end

function Service.BotEnter(bot: Model, model: Model, team: string): boolean
	local st = Service.Vehicles[model]
	local hum = bot:FindFirstChildOfClass("Humanoid")
	local seat = st and st.SeatByRole.Driver
	if not st or not hum or hum.Health <= 0 or not seat or seat.Occupant or st.Bot or model:GetAttribute("Destroyed") then
		return false
	end
	if st.Cfg.Drive.Kind == "Flight" or not combatOn() then
		return false
	end
	if #occupants(st) > 0 and vehicleTeam(st) ~= team then
		return false
	end
	if not Config.Interact.EnemyCanTakeEmpty and st.SpawnTeam and st.SpawnTeam ~= team then
		return false
	end
	local parts = {}
	for _, d in bot:GetDescendants() do
		if d:IsA("BasePart") then
			parts[d] = { d.CollisionGroup, d.Massless }
			d.CollisionGroup = GROUP_OCCUPANT
			d.Massless = true
		end
	end
	local function restore()
		for part, v in parts do
			if part.Parent then
				part.CollisionGroup, part.Massless = v[1], v[2]
			end
		end
	end
	seat:Sit(hum)
	if seat.Occupant ~= hum then
		restore()
		return false
	end
	st.Bot = { Model = bot, Hum = hum, Team = team, Restore = restore, Input = { Throttle = 0, Steer = 0, Brake = false }, Aim = nil, Trigger = false }
	bot:SetAttribute("InVehicle", model:GetAttribute("VehicleId"))
	bot:SetAttribute("VehicleSeat", seat:GetAttribute("SeatIndex"))
	bot:SetAttribute("VehicleHidden", seat:GetAttribute("Hidden") == true or nil)
	if st.Root:CanSetNetworkOwnership() then
		st.Root:SetNetworkOwner(nil)
	end
	st.LastUsed = os.clock()
	updatePrompt(st)
	return true
end

function Service.BotControl(model: Model, throttle: number, steer: number, brake: boolean, aim: Vector3?, trigger: boolean)
	local st = Service.Vehicles[model]
	if not st or not st.Bot then
		return
	end
	st.Bot.Input = { Throttle = math.clamp(throttle, -1, 1), Steer = math.clamp(steer, -1, 1), Brake = brake == true }
	st.Bot.Aim = aim
	st.Bot.Trigger = trigger == true and aim ~= nil
end

function Service.BotRelease(model: Model, noPlace: boolean?)
	local st = Service.Vehicles[model]
	local b = st and st.Bot
	if not b then
		return
	end
	st.Bot = nil
	b.Restore()
	b.Model:SetAttribute("InVehicle", nil)
	b.Model:SetAttribute("VehicleSeat", nil)
	b.Model:SetAttribute("VehicleHidden", nil)
	local seat = st.SeatByRole.Driver
	if seat and seat.Occupant == b.Hum then
		local w = seat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
		b.Hum.Sit = false
		if not noPlace and b.Hum.Health > 0 then
			local cf = findExit(st, seat)
			if cf then
				task.defer(function()
					if b.Model.Parent then
						b.Model:PivotTo(cf)
					end
				end)
			end
		end
	end
	st.Input = { Throttle = 0, Steer = 0, Brake = false }
	st.Trigger = false
	updatePrompt(st)
end

local function isFinite(v: any): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function onInput(player: Player, action: any, a: any, b: any, c: any)
	if action == "Exit" then
		onExit(player)
		return
	elseif action == "Seat" then
		onSwitch(player, a)
		return
	end
	local rec = saved[player]
	local st = rec and Service.Vehicles[rec.Vehicle]
	if not st or st.Model:GetAttribute("Destroyed") then
		return
	end
	if action == "Drive" then
		if st.Owner ~= player then
			return
		end
		st.Input = {
			Throttle = if type(a) == "number" and a == a then math.clamp(a, -1, 1) else 0,
			Steer = if type(b) == "number" and b == b then math.clamp(b, -1, 1) else 0,
			Brake = c == true,
		}
	elseif action == "Aim" then
		if controllerOf(st) ~= player or not isFinite(a) then
			return
		end
		local wy, wp = VMath.AnglesTo(st.Root.CFrame, st.Model, a)
		st.WantYaw, st.WantPitch = wy, wp
	elseif action == "Trigger" then
		if controllerOf(st) ~= player then
			st.Trigger = false
			return
		end
		st.Trigger = a == true and combatOn()
		if st.Trigger and st.Cfg.Weapon.Kind == "Cannon" then
			st.Trigger = false
			fireCannon(st, player, os.clock())
		end
	end
end

-- ─── per-frame ───────────────────────────────────────────────────────────
local attrClock = 0
local exemptClock = 0

local function validate(st, dt: number, now: number)
	-- the driver's client simulates; cap what it may do
	local root = st.Root
	local v = root.AssemblyLinearVelocity
	local D = st.Cfg.Drive
	local limit = D.MaxForward * 1.35 + 12
	local flat = Vector3.new(v.X, 0, v.Z).Magnitude
	local moved = (root.Position - st.LastGood.Position).Magnitude
	local expect = (limit + 40) * math.max(now - st.LastGoodAt, dt) + 6
	local bad = flat > limit or moved > expect
	if D.Kind == "Flight" and root.Position.Y > D.MaxAltitude + 15 then
		bad = true -- above the drone ceiling: the client is not honouring the altitude band
	end
	if bad then
		st.Strikes += 1
	else
		st.Strikes = math.max(0, st.Strikes - dt * 2)
		st.LastGood = root.CFrame
		st.LastGoodAt = now
	end
	if st.Strikes > 6 then
		-- take the vehicle back, rewind it, give it back after a beat
		Service.Stats.OwnershipRevoked += 1
		warn(("[VehicleService] %s: %s exceeded limits (%.0f studs/s) — ownership revoked"):format(st.Kind, tostring(st.Owner), flat))
		local owner = st.Owner
		root:SetNetworkOwner(nil)
		root.CFrame = st.LastGood
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		st.Strikes = 0
		st.LastGoodAt = now
		st.Owner = nil
		task.delay(1, function()
			if st.Model.Parent and owner and st.SeatByRole.Driver and seatOccupant(st.SeatByRole.Driver) == owner then
				st.Owner = nil
				updateOwner(st)
			end
		end)
	end
end

local function runOver(st, now: number)
	local R = st.Cfg.RunOver
	local root = st.Root
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if speed < R.MinSpeed or not st.Owner then
		return
	end
	local driver = st.Owner
	local cf, size = root.CFrame, root.Size + Vector3.new(3, 4, 3)
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if c and hrp and p ~= driver and not c:GetAttribute("InVehicle") then
			local lp = cf:PointToObjectSpace(hrp.Position)
			if math.abs(lp.X) < size.X / 2 and math.abs(lp.Y) < size.Y / 2 and math.abs(lp.Z) < size.Z / 2 then
				-- only what the hull is driving into
				local toward = (hrp.Position - root.Position)
				if toward:Dot(v) > 0 and (st.RunOverHits[c] or 0) < now then
					st.RunOverHits[c] = now + 0.6
					local dmg
					if speed >= R.KillSpeed then
						dmg = 999
					else
						local full = R.DamageAt or R.KillSpeed
						dmg = R.Damage * math.clamp(speed / full, 0.25, 1)
					end
					hurtCharacter(driver, st.Cfg.Weapon.Id .. "_RunOver", c, dmg, hrp.Position, v.Unit)
				end
			end
		end
	end
end

local function heartbeat(dt: number)
	local now = os.clock()
	local sendAttrs = now - attrClock > 1 / 15
	if sendAttrs then
		attrClock = now
	end
	local doExempt = now - exemptClock > 0.4
	if doExempt then
		exemptClock = now
	end
	for model, st in Service.Vehicles do
		if not model.Parent then
			Service.Vehicles[model] = nil
			continue
		end
		if model:GetAttribute("Destroyed") then
			continue
		end
		-- AI driver gone (died, knocked out of the seat): free the vehicle
		if st.Bot then
			local b = st.Bot
			local seat = st.SeatByRole.Driver
			if not b.Model.Parent or b.Hum.Health <= 0 or not seat or seat.Occupant ~= b.Hum then
				Service.BotRelease(model, true)
			end
		end
		-- physics: server simulates only vehicles nobody drives
		if not st.Owner then
			-- server-simulated: this is the trusted pose the driver's validation starts from
			st.LastGood = st.Root.CFrame
			st.LastGoodAt = now
			st.Strikes = 0
			-- Studio test hook: model attribute TestDrive = Vector3(throttle, steer, brake 0/1)
			local td = RunService:IsStudio() and model:GetAttribute("TestDrive")
			if st.Bot then
				st.Input = st.Bot.Input
				st.Sim:Step(dt, st.Input)
				st.LastUsed = now
			elseif typeof(td) == "Vector3" then
				st.Input = { Throttle = td.X, Steer = td.Y, Brake = td.Z > 0.5,
					Pitch = td.Z, Piloted = st.Cfg.Drive.Kind == "Flight" } -- drones: Z = camera pitch (radians)
				st.Sim:Step(dt, st.Input)
				st.LastUsed = now -- a test drive counts as use (no abandonment recycle)
			else
				st.Sim:Step(dt, Sim.ZeroInput)
			end
		else
			validate(st, dt, now)
		end
		-- energy shield: recharges after a quiet spell
		local SH = st.Cfg.Shield
		if st.Shield < SH.Max and now - st.ShieldHitAt > SH.RegenDelay then
			st.Shield = math.min(SH.Max, st.Shield + SH.RegenRate * dt)
			if sendAttrs or st.Shield >= SH.Max then
				model:SetAttribute("Shield", math.floor(st.Shield + 0.5))
			end
		end
		-- turret
		local W = st.Cfg.Weapon
		local ctrl = controllerOf(st)
		if not ctrl then
			local aim = st.Bot and st.Bot.Aim
			if aim then
				if W.Kind == "Cannon" and W.ShellSpeed then
					-- lob for the shell's drop
					local t = (aim - st.Root.Position).Magnitude / W.ShellSpeed
					aim += Vector3.new(0, 0.5 * Workspace.Gravity * (W.ShellGravity or 0) * t * t, 0)
				end
				st.WantYaw, st.WantPitch = VMath.AnglesTo(st.Root.CFrame, model, aim)
			else
				st.WantYaw, st.WantPitch = 0, 0
			end
			st.Trigger = false
		end
		st.Yaw, st.Pitch = VMath.Slew(st.Yaw, st.Pitch, st.WantYaw, st.WantPitch, W, dt)
		-- weapon
		if W.Heat then
			if now - st.HeatAt > W.Heat.CoolDelay and now >= st.LockedUntil then
				st.Heat = math.max(0, st.Heat - W.Heat.CoolRate * dt)
			end
			if now >= st.LockedUntil and st.LockedUntil > 0 then
				st.LockedUntil = 0
			end
		end
		if st.Trigger and ctrl and W.Kind == "MG" then
			if not combatOn() then
				st.Trigger = false
			else
				fireMG(st, ctrl, now)
			end
		end
		if not ctrl and st.Bot and st.Bot.Trigger and combatOn() then
			if W.Kind == "MG" then
				botFireMG(st, now)
			elseif W.Kind == "Cannon" then
				botFireCannon(st, now)
			end
		end
		runOver(st, now)
		if st.Bot then
			botRunOver(st, now)
		end
		if sendAttrs and W.Homing then
			local t = if ctrl and combatOn() then lockTarget(st, ctrl) else nil
			st.Lock = t
			if st.LockValue and st.LockValue.Value ~= t then
				st.LockValue.Value = t
			end
		end
		if sendAttrs then
			model:SetAttribute("AimYaw", math.floor(st.Yaw * 1000 + 0.5) / 1000)
			model:SetAttribute("AimPitch", math.floor(st.Pitch * 1000 + 0.5) / 1000)
			if W.Heat then
				model:SetAttribute("Heat", math.floor(st.Heat * 100 + 0.5) / 100)
				model:SetAttribute("Overheated", st.LockedUntil > now or nil)
			end
			model:SetAttribute("Throttle", st.Input.Throttle)
			model:SetAttribute("Steer", st.Input.Steer)
		end
		-- crews: the movement validator must not fight the seat; keep them exempt
		if doExempt then
			local crew = occupants(st)
			for _, p in crew do
				MovementValidator.Exempt(p, 1)
			end
			if #crew > 0 then
				st.LastUsed = now
			elseif st.Marker and (st.Root.Position - st.Marker.Position).Magnitude > Config.Destruction.AbandonSpawnRadius
				and now - st.LastUsed > Config.Destruction.AbandonTime then
				recycle(st, false)
			end
			-- fell out of the world
			if st.Root.Position.Y < -60 then
				destroyVehicle(st, st.LastAttacker, st.LastWeapon)
			end
		end
	end
	stepShells(dt)
	stepBotShells(dt)
	-- respawns
	for i = #respawnQueue, 1, -1 do
		local r = respawnQueue[i]
		if now >= r.At then
			table.remove(respawnQueue, i)
			if r.Marker.Parent then
				-- wait for the pad to be clear of other vehicles
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				local roots = {}
				for _, s in Service.Vehicles do
					table.insert(roots, s.Root)
				end
				params.FilterDescendantsInstances = roots
				local busy = #roots > 0 and #Workspace:GetPartBoundsInRadius(r.Marker.Position, 18, params) > 0
				if busy then
					r.At = now + 2
					table.insert(respawnQueue, r)
				else
					r.Marker:SetAttribute("RespawnAt", nil)
					spawnAt(r.Marker)
				end
			end
		end
	end
end

-- ─── match integration ───────────────────────────────────────────────────
function Service.ResetAll()
	for _, st in Service.Vehicles do
		recycle(st, true)
	end
	table.clear(respawnQueue)
	for _, m in spawnMarkers() do
		table.insert(respawnQueue, { Marker = m, At = os.clock() + 0.3 })
	end
end

function Service.Start()
	setupGroups()
	InputRemote.OnServerEvent:Connect(onInput)
	DamageService.VehicleHandler = onGunHit
	RunService.Heartbeat:Connect(heartbeat)
	Players.PlayerRemoving:Connect(function(p)
		saved[p] = nil
		intent[p] = nil
	end)
	for _, m in spawnMarkers() do
		m:SetAttribute("Live", nil)
		spawnAt(m)
	end
	-- a new match puts every vehicle back on its pad
	local match = DamageService.MatchFolder()
	local lastMatch = match:GetAttribute("MatchId")
	match:GetAttributeChangedSignal("MatchId"):Connect(function()
		local id = match:GetAttribute("MatchId")
		if id ~= lastMatch then
			lastMatch = id
			Service.ResetAll()
		end
	end)
	-- leaving the Live phase: everyone out
	match:GetAttributeChangedSignal("Phase"):Connect(function()
		if match:GetAttribute("Phase") ~= "Live" then
			for model, st in Service.Vehicles do
				if st.Bot then
					Service.BotRelease(model)
				end
				for _, seat in st.Seats do
					local p = seatOccupant(seat)
					if p then
						onExit(p)
					end
				end
			end
		end
	end)
	_G.VantageVehicles = Service -- Studio test hook (command bar / tests)
end

return Service
