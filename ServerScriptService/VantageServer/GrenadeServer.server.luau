--[[
	VANTAGE — GrenadeServer (VX-G1 frag), built 2026-11-11
	The server owns everything that matters:
		- cooldown per player (one grenade, regenerates; refilled on respawn)
		- the throw: starts at the server's own view of the head, along the claimed look direction
		  (only checked to be a real unit vector: any direction is one you could have looked at)
		- the flight: a server-owned physics part (bounces and rolls for real, nobody can steer it)
		- the fuse and the blast: line-of-sight damage with falloff through DamageService, so
		  shields, friendly fire, spawn protection, kill credit, assists and the kill feed
		  ("Explosion" row: weapon is Explosive) all work as for every other weapon
		- vehicles in the radius take VehicleService damage with the same falloff

	Remote: ReplicatedStorage.Vantage.Remotes.Grenade
		client -> server  ("Throw", lookDirection: Vector3)
		server -> client  ("Reject", secondsLeft)            to the thrower
		                  ("Thrown", grenadeModel, throwerCharacter)   to everyone (sound)
		                  ("Explode", position)                to everyone (effects)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Folder = Vantage:WaitForChild("Grenade")
local Config = require(Folder:WaitForChild("GrenadeConfig"))
local Template = Folder:WaitForChild("FragModel") :: Model
local Remote = Vantage.Remotes:WaitForChild("Grenade") :: RemoteEvent
local WeaponEvent = Vantage.Remotes:WaitForChild("WeaponEvent") :: RemoteEvent

local VantageServer = script.Parent
local WeaponServer = VantageServer:WaitForChild("WeaponServer")
local DamageService = require(WeaponServer:WaitForChild("DamageService"))
local HitValidation = require(WeaponServer:WaitForChild("HitValidation"))
local VehicleService = require(VantageServer:WaitForChild("VehicleService"))

local WEAPON = { Id = Config.Id, Kind = "Grenade", Explosive = true, DisplayName = Config.DisplayName }

local live = Workspace:FindFirstChild("VantageGrenades") or Instance.new("Folder")
live.Name = "VantageGrenades"
live.Parent = Workspace

local readyAt: { [Player]: number } = {}

local function characters(): { Instance }
	local list: { Instance } = { live }
	for _, c in HitValidation.TargetCharacters() do
		table.insert(list, c)
	end
	for _, tag in { "VantageDummy", "VantageBot" } do
		for _, m in CollectionService:GetTagged(tag) do
			table.insert(list, m)
		end
	end
	return list
end

-- 1 at or inside InnerRadius, EdgeFraction at Radius, 0 beyond
local function falloff(d: number): number
	if d >= Config.Radius then
		return 0
	end
	if d <= Config.InnerRadius then
		return 1
	end
	local t = (d - Config.InnerRadius) / (Config.Radius - Config.InnerRadius)
	return 1 - (1 - Config.EdgeFraction) * t
end

local function explode(model: Model, thrower: Player)
	local root = model.PrimaryPart
	if not root or not model.Parent then
		return
	end
	local pos = root.Position
	model:Destroy()
	Remote:FireAllClients("Explode", pos)
	if not thrower.Parent then
		return -- the thrower left: the blast is only a show
	end
	local origin = pos + Vector3.new(0, 0.4, 0)

	-- infantry: line of sight to the torso or the head, damage by distance
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = characters()
	local totals, killedAny = 0, false
	for _, c in HitValidation.TargetCharacters() do
		local hum = c:FindFirstChildOfClass("Humanoid")
		local body = (c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart")) :: BasePart?
		local head = c:FindFirstChild("Head") :: BasePart?
		if not hum or hum.Health <= 0 or not body or c:GetAttribute("VehicleHidden") then
			continue
		end
		local d = (body.Position - pos).Magnitude
		local f = falloff(d)
		if f <= 0 then
			continue
		end
		local seen = Workspace:Raycast(origin, body.Position - origin, rp) == nil
		if not seen and head then
			seen = Workspace:Raycast(origin, head.Position - origin, rp) == nil
		end
		if not seen then
			continue
		end
		local dir = if d > 0.1 then (body.Position - pos).Unit else Vector3.yAxis
		local result = DamageService.Apply(thrower, WEAPON, {
			Character = c, Humanoid = hum, IsHead = false, IsLimb = false,
			Distance = d, Position = body.Position, Direction = dir,
		}, Config.MaxDamage * f)
		if result and not result.Blocked and result.Damage > 0 then
			totals += result.Damage
			killedAny = killedAny or result.Killed == true
			if result.VictimPlayer then
				WeaponEvent:FireClient(result.VictimPlayer, "Damaged", pos, result.Damage)
			end
			-- the thrower's hit marker / damage number (Weapon left out: the current gun's hit cue plays)
			WeaponEvent:FireClient(thrower, "Confirm", {
				Damage = result.Damage, Headshot = false, Killed = result.Killed, Blocked = false,
				VictimName = result.VictimName, Position = body.Position,
				ShieldDamage = result.ShieldDamage, ShieldBroken = result.ShieldBroken, Grenade = true,
			})
		end
	end

	-- vehicles: distance from the hull's edge, same falloff
	for vmodel, st in VehicleService.Vehicles or {} do
		local vroot = st.Root
		if vroot and vroot.Parent and not vmodel:GetAttribute("Destroyed") then
			local d = math.max(0, (vroot.Position - pos).Magnitude - math.max(vroot.Size.X, vroot.Size.Z) * 0.35)
			local f = falloff(d)
			if f > 0 then
				VehicleService.DamageVehicle(vmodel, Config.VehicleDamage * f, thrower, Config.Id, pos)
			end
		end
	end
end

local function throw(player: Player, look: Vector3)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not character or not hum or hum.Health <= 0 or not root or not head then
		return
	end
	if character:GetAttribute("InVehicle") or character:GetAttribute("VantageHanging") or player:GetAttribute("VantageHanging") then
		return
	end
	local now = os.clock()
	local ready = readyAt[player] or 0
	if now < ready - Config.ServerTolerance then
		Remote:FireClient(player, "Reject", ready - now)
		return
	end
	if not DamageService.CombatEnabled() then
		Remote:FireClient(player, "Reject", 0)
		return
	end
	if typeof(look) ~= "Vector3" or look ~= look or math.abs(look.Magnitude - 1) > 0.05 then
		return
	end
	readyAt[player] = now + Config.Cooldown

	local eye = head.Position
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = characters()
	local ahead = Config.SpawnAhead
	local wall = Workspace:Raycast(eye, look * (ahead + 0.5), rp)
	if wall then
		ahead = math.max(0, (wall.Position - eye).Magnitude - 0.5)
	end
	local spawnPos = eye + look * ahead

	local g = Template:Clone()
	g.Name = "Frag_" .. player.UserId
	g:SetAttribute("Thrower", player.UserId)
	g:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0))
	CollectionService:AddTag(g, "VantageGrenade")
	g.Parent = live
	local gr = g.PrimaryPart :: BasePart
	pcall(gr.SetNetworkOwner, gr, nil)
	local carry = root.AssemblyLinearVelocity * Config.InheritVelocity
	gr.AssemblyLinearVelocity = look * Config.ThrowSpeed + Vector3.new(0, Config.ThrowLift, 0) + carry
	gr.AssemblyAngularVelocity = look:Cross(Vector3.yAxis).Unit * Config.Spin
		+ Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 4
	Remote:FireAllClients("Thrown", g, character)

	task.delay(Config.Fuse, function()
		local ok, err = pcall(explode, g, player)
		if not ok then
			warn("[GrenadeServer] blast failed: " .. tostring(err))
			if g.Parent then
				g:Destroy()
			end
		end
	end)
end

-- rolling friction: a ball rolls without losing speed, so on the ground the grenade is slowed
-- here (a frag should settle a few studs from where it lands, not roll on across the map)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local groundAcc = 0
RunService.Heartbeat:Connect(function(dt)
	local list = live:GetChildren()
	if #list == 0 then
		return
	end
	groundAcc += dt
	if groundAcc > 0.5 then
		groundAcc = 0
		groundParams.FilterDescendantsInstances = characters()
	end
	local k = math.exp(-Config.GroundDrag * dt)
	for _, g in list do
		local r = g:IsA("Model") and g.PrimaryPart
		if r then
			local below = Workspace:Raycast(r.Position, Vector3.new(0, -(r.Size.Y * 0.5 + 0.25), 0), groundParams)
			if below then
				local v = r.AssemblyLinearVelocity
				r.AssemblyLinearVelocity = Vector3.new(v.X * k, v.Y, v.Z * k)
				r.AssemblyAngularVelocity *= k
			end
		end
	end
end)

Remote.OnServerEvent:Connect(function(player: Player, action: any, look: any)
	if action == "Throw" then
		throw(player, look)
	end
end)

local function onPlayer(player: Player)
	readyAt[player] = 0
	player.CharacterAdded:Connect(function()
		if Config.RefillOnRespawn then
			readyAt[player] = 0
		end
	end)
end
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	readyAt[p] = nil
end)
