--[[
	VANTAGE — UltServer (2026-11-18): ORBITAL LANCE (see ReplicatedStorage.Vantage.Ult.UltConfig)
	Client -> server  Remotes.Ult:FireServer("Activate", cameraLookVector)
	Server -> all     "Mark" { Position, Owner, Team, Delay, Radius }   telegraph
	                  "Strike" { Position, Owner, Team, Radius }        impact
	                  "Pulse" { Position, Team, Radius }               aftershock
	Server -> owner   "Denied" reason
	The charge (Player.UltReady) is set only by EliminationService; the client never sends a
	target or a damage value, only where its camera points (the server raycasts from the head).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remote = Vantage:WaitForChild("Remotes"):WaitForChild("Ult") :: RemoteEvent
local Cfg = require(Vantage:WaitForChild("Ult"):WaitForChild("UltConfig"))
local DamageService = require(script.Parent:WaitForChild("WeaponServer"):WaitForChild("DamageService"))

local WEAPON = { Id = "OrbitalLance", Kind = "Ult", Explosive = true, DisplayName = Cfg.Name }
local busy: { [Player]: boolean } = {}

local function rayParams(exclude: { Instance }): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = exclude
	rp.IgnoreWater = true
	return rp
end

local function humanoidModel(part: Instance): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then
			return m
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function teamOf(p: Player): string?
	return if p.Team and not p.Neutral then p.Team.Name else nil
end

-- one blast: everyone hostile inside `radius` (flat distance) takes damage falling from dmgCore
-- (inside coreR) to dmgEdge (at radius). Outside the core, solid cover between the impact and
-- the target blocks it.
local function blast(owner: Player, center: Vector3, radius: number, dmgCore: number, dmgEdge: number, coreR: number)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { owner.Character }
	local seen: { [Model]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(center, radius + 6, op) do
		local model = humanoidModel(part)
		if model and not seen[model] then
			seen[model] = true
			local hum = model:FindFirstChildOfClass("Humanoid")
			local body = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")) :: BasePart?
			if hum and hum.Health > 0 and body then
				local off = body.Position - center
				local flat = Vector3.new(off.X, 0, off.Z).Magnitude
				if flat <= radius and off.Y > -8 and off.Y < 80 then
					local covered = false
					if flat > coreR then
						local from = center + Vector3.new(0, 2.5, 0)
						local r = workspace:Raycast(from, body.Position - from, rayParams({ model, owner.Character :: any }))
						if r and r.Instance.CanCollide and r.Instance.Transparency < 0.9 and not humanoidModel(r.Instance) then
							covered = true
						end
					end
					if not covered then
						local k = math.clamp((flat - coreR) / math.max(1, radius - coreR), 0, 1)
						local dmg = dmgCore + (dmgEdge - dmgCore) * k
						local dir = if off.Magnitude > 0.1 then (off.Unit + Vector3.new(0, -0.5, 0)).Unit else Vector3.new(0, -1, 0)
						local ok, err = pcall(DamageService.Apply, owner, WEAPON, {
							Character = model,
							Humanoid = hum,
							IsHead = false,
							IsLimb = false,
							Distance = flat,
							Position = body.Position,
							Direction = dir,
						}, dmg)
						if not ok then
							warn("[VANTAGE] ult damage: " .. tostring(err))
						end
					end
				end
			end
		end
	end
end

local function activate(p: Player, look: any)
	if busy[p] or p:GetAttribute("UltReady") ~= true then
		return
	end
	if typeof(look) ~= "Vector3" or look ~= look or look.Magnitude < 0.5 or look.Magnitude > 1.5 then
		return
	end
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not char or not hum or hum.Health <= 0 or not head then
		return
	end
	if not DamageService.CombatEnabled() then
		Remote:FireClient(p, "Denied", "COMBAT OFFLINE")
		return
	end
	look = look.Unit
	local rp = rayParams({ char })
	local r = workspace:Raycast(head.Position, look * Cfg.MaxRange, rp)
	local target = if r then r.Position + r.Normal * 0.5 else head.Position + look * Cfg.MaxRange
	local down = workspace:Raycast(target + Vector3.new(0, 2, 0), Vector3.new(0, -500, 0), rp)
	local ground = if down then down.Position else target

	p:SetAttribute("UltReady", false)
	busy[p] = true
	local team = teamOf(p)
	Remote:FireAllClients("Mark", { Position = ground, Owner = p.UserId, Team = team, Delay = Cfg.Delay, Radius = Cfg.Radius })
	task.delay(Cfg.Delay, function()
		Remote:FireAllClients("Strike", { Position = ground, Owner = p.UserId, Team = team, Radius = Cfg.Radius })
		if p.Parent then
			blast(p, ground, Cfg.Radius, Cfg.Damage, Cfg.EdgeDamage, Cfg.CoreRadius)
		end
		for _ = 1, Cfg.Aftershocks do
			task.wait(Cfg.AftershockEvery)
			Remote:FireAllClients("Pulse", { Position = ground, Team = team, Radius = Cfg.AftershockRadius })
			if p.Parent then
				blast(p, ground, Cfg.AftershockRadius, Cfg.AftershockDamage, Cfg.AftershockDamage, Cfg.AftershockRadius)
			end
		end
		busy[p] = nil
	end)
end

Remote.OnServerEvent:Connect(function(p: Player, action: any, look: any)
	if action == "Activate" then
		activate(p, look)
	end
end)

-- a banked ULT does not carry into the next match
local match = DamageService.MatchFolder()
match:GetAttributeChangedSignal("MatchId"):Connect(function()
	for _, p in Players:GetPlayers() do
		p:SetAttribute("UltReady", false)
	end
end)

Players.PlayerAdded:Connect(function(p)
	p:SetAttribute("KillStreak", 0)
	p:SetAttribute("UltReady", false)
end)
for _, p in Players:GetPlayers() do
	if p:GetAttribute("KillStreak") == nil then
		p:SetAttribute("KillStreak", 0)
	end
end
Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
end)
