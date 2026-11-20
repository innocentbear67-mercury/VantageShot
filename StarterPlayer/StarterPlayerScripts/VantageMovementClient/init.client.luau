--[[
	VANTAGE — Movement client bootstrap
	Creates one Input layer for the session, and a fresh Movement / Animation / Camera
	stack for every character life (handles respawn cleanly).

	Frame order:
		RenderPriority.Input      Roblox ControlModule (reads WASD/stick)
		RenderPriority.Input + 1  VantageMovement   (our velocity, jump, crouch, slide)
		RenderPriority.Camera     Roblox first-person camera
		RenderPriority.Camera + 1 VantageCamera     (FOV, tilt, landing dip, bob)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
local InputController = require(script.InputController)
local MovementController = require(script.MovementController)
local AnimationController = require(script.AnimationController)
local CameraEffects = require(script.CameraEffects)
local PoseController = require(script.PoseController)

local remote = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Remotes"):WaitForChild("MovementState") :: RemoteEvent
local player = Players.LocalPlayer

local MOVE_BIND = "VantageMovement"
local CAMERA_BIND = "VantageCamera"
local CAMERA_UNDO_BIND = "VantageCameraUndo"

local input = InputController.new()
PoseController.Start()

local active = nil -- { Movement, Animation, Camera, Connections }

local function teardown()
	if not active then
		return
	end
	RunService:UnbindFromRenderStep(MOVE_BIND)
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	RunService:UnbindFromRenderStep(CAMERA_UNDO_BIND)
	for _, c in active.Connections do
		c:Disconnect()
	end
	active.Animation:Destroy()
	active.Camera:Destroy(Workspace.CurrentCamera)
	active.Movement:Destroy()
	active = nil
end

local function onCharacter(character: Model)
	teardown()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	character:WaitForChild("Head")
	if player.Character ~= character then
		return -- respawned again while we were waiting
	end
	-- lobby (no team, Workspace.HyperLobby): third-person Roblox camera with a free mouse
	local lobby = player.Team == nil and not player:GetAttribute("InTutorial") -- trainees play first-person
	if lobby then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 16
		player.CameraMinZoomDistance = 7
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		Workspace.CurrentCamera.FieldOfView = 70
	else
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		Workspace.CurrentCamera.FieldOfView = Config.BaseFOV
	end

	input:ResetForSpawn()
	local movement = MovementController.new(character, humanoid, root, input, remote)
	local animation = AnimationController.new(character, humanoid, movement)
	local cameraFx = CameraEffects.new(movement)
	PoseController.SetLocalSource(character, movement)

	active = {
		Movement = movement,
		Animation = animation,
		Camera = cameraFx,
		Connections = {},
	}

	RunService:BindToRenderStep(MOVE_BIND, Enum.RenderPriority.Input.Value + 1, function(dt)
		input:Update()
		movement:Step(dt, Workspace.CurrentCamera)
		animation:Step()
		if Config.DebugAttributes then
			character:SetAttribute("DbgStance", movement.Stance)
			character:SetAttribute("DbgSpeed", movement.Velocity.Magnitude)
			character:SetAttribute("DbgGrounded", movement.Grounded)
			character:SetAttribute("DbgDrop", movement.HeightDrop)
			character:SetAttribute("DbgAnim", animation.CurrentName or "none")
		end
	end)
	if not lobby then -- FOV kick, tilt and bob are first-person effects
		-- undo last frame's tilt / dip pitch before Roblox's camera reads the look (after the recoil
		-- undo at Camera - 2), so the effects never accumulate into the aim
		RunService:BindToRenderStep(CAMERA_UNDO_BIND, Enum.RenderPriority.Camera.Value - 1, function()
			cameraFx:Undo(Workspace.CurrentCamera)
		end)
		RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
			cameraFx:Step(dt, Workspace.CurrentCamera)
		end)
	end

	table.insert(active.Connections, humanoid.Died:Connect(teardown))
	table.insert(active.Connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			teardown()
		end
	end))
end

-- Server refused a slide (cooldown / speed check): cancel it locally.
remote.OnClientEvent:Connect(function(action: string)
	if action == "SlideRejected" and active then
		active.Movement:ForceEndSlide()
	end
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Default to first-person (also set on StarterPlayer; this guards against other scripts).
if player.Team ~= nil then
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	Workspace.CurrentCamera.FieldOfView = Config.BaseFOV
end
