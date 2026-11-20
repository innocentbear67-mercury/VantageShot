--[[
	VANTAGE — MovementValidator (server)

	The client simulates its own character (Roblox network ownership) for zero-latency
	movement. The server never trusts reported speeds or states; instead it:
		1. Samples each root position every Server.SampleInterval and checks horizontal
		   distance against the speed the player is ALLOWED to have right now.
		2. Checks height above the last known ground against the max jump height
		   (catches infinite / repeated mid-air jumps and flying).
		3. Approves or rejects slides (cooldown + measured speed). Slide-level speed is
		   only allowed during an approved slide window, so faked infinite slides are capped
		   at RunSpeed.
		4. Publishes the validated stance as character attribute "VantageStance".
	Repeated violations snap the player back to their last valid position.

	Public API (for future systems, e.g. knockback, launch pads, teleports):
		MovementValidator.Exempt(player, seconds)
		MovementValidator.GetStance(player) -> "Stand" | "Crouch" | "Slide"
	Also exposed without require() as ServerScriptService.VantageServer.ExemptMovement
	(BindableEvent): ExemptMovement:Fire(player, seconds). Call it BEFORE any
	server-side teleport / launch, or the validator will treat it as an exploit.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
local S = Config.Server
local remote = ReplicatedStorage.Vantage:WaitForChild("Remotes"):WaitForChild("MovementState") :: RemoteEvent

local VALID_STANCES = { Stand = true, Crouch = true }

local MovementValidator = {}
local data: { [Player]: any } = {}

local function getRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?, character:FindFirstChildOfClass("Humanoid")
end

local function setStance(player: Player, d, stance: string)
	if d.Stance == stance then
		return
	end
	if d.Stance == "Slide" then
		d.SlideEndAt = os.clock()
	end
	d.Stance = stance
	if player.Character then
		player.Character:SetAttribute("VantageStance", stance)
	end
end

local function resetBaseline(d, root: BasePart)
	d.LastPos = root.Position
	d.LastTime = os.clock()
	d.LastValidCFrame = root.CFrame
end

local function onCharacter(player: Player, character: Model)
	local d = data[player]
	if not d then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	d.Stance = "Stand"
	d.SlideApprovedAt = -math.huge
	d.SlideEndAt = -math.huge
	d.SlideId = 0
	d.Violations = 0
	d.ExemptUntil = os.clock() + 1.5 -- spawn settle
	d.StandRootHeight = humanoid.HipHeight + root.Size.Y / 2
	d.LastGroundY = root.Position.Y - d.StandRootHeight
	d.LastSpeed = 0
	character:SetAttribute("VantageStance", "Stand")
	resetBaseline(d, root)
end

local function onPlayer(player: Player)
	data[player] = {
		Stance = "Stand",
		SlideApprovedAt = -math.huge,
		SlideEndAt = -math.huge,
		SlideId = 0,
		Violations = 0,
		LastDecay = os.clock(),
		ExemptUntil = 0,
		MsgWindowStart = os.clock(),
		MsgCount = 0,
		LastSpeed = 0,
	}
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function snapBack(player: Player, d, root: BasePart, reason: string)
	warn(("[VANTAGE] Movement correction for %s: %s"):format(player.Name, reason))
	if d.LastValidCFrame then
		root.CFrame = d.LastValidCFrame
	end
	root.AssemblyLinearVelocity = Vector3.zero
	d.Violations = 0
	d.ExemptUntil = os.clock() + 0.5
	resetBaseline(d, root)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function sample(player: Player, d, now: number)
	local root, humanoid = getRoot(player)
	if not root or not humanoid or humanoid.Health <= 0 or not d.LastPos then
		return
	end
	local dt = now - d.LastTime
	if dt <= 0 then
		return
	end
	local pos = root.Position

	-- forgive old violations slowly
	if now - d.LastDecay >= S.ViolationDecayTime then
		d.LastDecay = now
		d.Violations = math.max(0, d.Violations - 1)
	end

	-- ground tracking
	groundParams.FilterDescendantsInstances = { player.Character }
	local hit = Workspace:Raycast(pos, Vector3.new(0, -(d.StandRootHeight + 1.5), 0), groundParams)
	if hit then
		d.LastGroundY = hit.Position.Y
		d.LastGroundAt = now
	end

	if now < d.ExemptUntil then
		resetBaseline(d, root)
		return
	end

	local delta = pos - d.LastPos
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	d.LastSpeed = horizontal / dt

	-- [VANTAGE weapons integration] the server-set weapon speed multiplier (knife) raises the cap;
	-- it is written only by WeaponService, so clients cannot grant themselves extra speed.
	local weaponMult = player.Character and player.Character:GetAttribute("VantageSpeedMult")
	weaponMult = if type(weaponMult) == "number" then math.clamp(weaponMult, 1, 1.5) else 1
	-- 2026-11-19: equipment speed boosts (Singularity's phase), server-set, short-lived
	local perkUntil = player.Character and player.Character:GetAttribute("PerkSpeedUntil")
	local perkMult = player.Character and player.Character:GetAttribute("PerkSpeedMult")
	if type(perkUntil) == "number" and perkUntil > Workspace:GetServerTimeNow() - 0.3 and type(perkMult) == "number" then
		weaponMult *= math.clamp(perkMult, 1, 1.3)
	end
	local allowedSpeed = Config.RunSpeed * weaponMult
	-- 2026-11-19: momentum after a grapple (Momentum below): the release speed is allowed for 1 s, then
	-- fades to normal; the rise allowed shrinks like a thrown body's (gravity, float included)
	local momentum = d.MomUntil ~= nil and now < d.MomUntil
	local upAllowed = 0
	if momentum then
		local t = now - d.MomAt
		local k = math.clamp(1 - math.max(0, t - 1) / math.max(0.1, d.MomUntil - d.MomAt - 1), 0, 1)
		allowedSpeed = math.max(allowedSpeed, d.MomH * k)
		upAllowed = d.MomUp - Workspace.Gravity * 0.3 * t + 10
	end
	if d.Stance == "Slide" or now - d.SlideApprovedAt <= Config.SlideDuration + S.MomentumGraceTime then
		allowedSpeed = math.max(allowedSpeed, Config.SlideMaxSpeed)
	end
	local maxDistance = (allowedSpeed * S.SpeedTolerance + S.SpeedFlatAllowance) * dt

	local violation: string? = nil
	local severity = 1
	if horizontal > S.TeleportDistance then
		violation = ("teleport %.1f studs"):format(horizontal)
		severity = S.MaxViolations
	elseif horizontal > maxDistance then
		violation = ("speed %.1f > allowed %.1f"):format(horizontal / dt, maxDistance / dt)
	end

	-- vertical: rising too far above the last ground means extra jumps / flight
	if momentum and not hit then
		-- a fling's arc: its peak is the new reference, so a later small rise is not "flying"
		d.LastGroundY = math.max(d.LastGroundY, (pos.Y - d.StandRootHeight) - Config.JumpHeight)
		if now - (d.LastGroundAt or 0) < 0.6 then
			upAllowed = math.max(upAllowed, math.sqrt(2 * Workspace.Gravity * Config.JumpHeight) + 10) -- a normal jump off the ground
		end
		if delta.Y / dt > upAllowed then
			violation = ("rising %.1f > allowed %.1f after grapple"):format(delta.Y / dt, upAllowed)
		end
	elseif not hit and delta.Y > 0 then
		local rise = (pos.Y - d.StandRootHeight) - d.LastGroundY
		if rise > Config.JumpHeight + S.JumpRiseAllowance then
			violation = ("height %.1f above ground (max %.1f)"):format(rise, Config.JumpHeight + S.JumpRiseAllowance)
			severity = S.MaxViolations
		end
	end

	if violation then
		d.Violations += severity
		if d.Violations >= S.MaxViolations then
			snapBack(player, d, root, violation)
			return
		end
	elseif hit then
		d.LastValidCFrame = root.CFrame -- only remember grounded, legal positions
	end
	d.LastPos = pos
	d.LastTime = now
end

local function onRemote(player: Player, action: any, arg: any)
	local d = data[player]
	if not d or typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	-- rate limit
	if now - d.MsgWindowStart >= 1 then
		d.MsgWindowStart = now
		d.MsgCount = 0
	end
	d.MsgCount += 1
	if d.MsgCount > S.RemoteRateLimit then
		return
	end

	if action == "Slide" then
		local _, humanoid = getRoot(player)
		local cooldownOk = now - d.SlideEndAt >= Config.SlideCooldown - S.SlideCooldownTolerance
		local speedOk = d.LastSpeed >= Config.SlideMinStartSpeed * 0.6 or now < d.ExemptUntil
		if d.Stance == "Slide" or not cooldownOk or not speedOk or not humanoid or humanoid.Health <= 0 then
			remote:FireClient(player, "SlideRejected")
			return
		end
		d.SlideApprovedAt = now
		d.SlideId += 1
		setStance(player, d, "Slide")
		-- the server, not the client, decides when a slide is over
		local id = d.SlideId
		task.delay(Config.SlideDuration + 0.25, function()
			if data[player] == d and d.SlideId == id and d.Stance == "Slide" then
				setStance(player, d, "Crouch")
			end
		end)
	elseif action == "Stance" then
		if VALID_STANCES[arg] then
			setStance(player, d, arg)
		end
	end
end

function MovementValidator.Exempt(player: Player, seconds: number)
	local d = data[player]
	if d then
		d.ExemptUntil = math.max(d.ExemptUntil, os.clock() + seconds)
	end
end

-- a launch the server approved (grapple let-go): horizontal speed `horizontal` and upward speed `up` are
-- allowed right away, fading to normal by `seconds`. Unlike Exempt, every other check keeps running.
function MovementValidator.Momentum(player: Player, horizontal: number, up: number, seconds: number)
	local d = data[player]
	if d then
		local now = os.clock()
		d.MomAt, d.MomUntil = now, now + seconds
		d.MomH = horizontal * S.SpeedTolerance + S.SpeedFlatAllowance
		d.MomUp = up
	end
end

function MovementValidator.GetStance(player: Player): string
	local d = data[player]
	return d and d.Stance or "Stand"
end

function MovementValidator.Start()
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		data[p] = nil
	end)
	remote.OnServerEvent:Connect(onRemote)

	local exemptEvent = script.Parent:FindFirstChild("ExemptMovement") or Instance.new("BindableEvent")
	exemptEvent.Name = "ExemptMovement"
	exemptEvent.Parent = script.Parent
	exemptEvent.Event:Connect(function(player, seconds)
		if typeof(player) == "Instance" and player:IsA("Player") and type(seconds) == "number" then
			MovementValidator.Exempt(player, seconds)
		end
	end)

	local momentumEvent = script.Parent:FindFirstChild("MomentumMovement") or Instance.new("BindableEvent")
	momentumEvent.Name = "MomentumMovement"
	momentumEvent.Parent = script.Parent
	momentumEvent.Event:Connect(function(player, horizontal, up, seconds)
		if typeof(player) == "Instance" and player:IsA("Player") and type(horizontal) == "number" and type(up) == "number" and type(seconds) == "number" then
			MovementValidator.Momentum(player, horizontal, up, seconds)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < S.SampleInterval then
			return
		end
		accumulator = 0
		local now = os.clock()
		for player, d in data do
			sample(player, d, now)
		end
	end)
end

return MovementValidator
