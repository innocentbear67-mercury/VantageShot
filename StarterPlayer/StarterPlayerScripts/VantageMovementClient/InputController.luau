--[[
	VANTAGE — InputController
	Device-agnostic movement intent. Movement code only ever asks this module for:
		:GetWishDirection(camera)  -> world-space horizontal Vector3 (magnitude 0..1)
		.JumpPressedAt / .JumpHeld
		.CrouchPressedAt / :IsCrouchActive()

	Move direction comes from Roblox's PlayerModule. Current Roblox builds expose it as an
	Input Action System action (StarterPlayer.PlayerModule.InputContexts.CharacterContext
	.MoveAction); older builds use PlayerScripts.PlayerModule:GetControls(). Both are
	supported, so keyboard (WASD), gamepad thumbstick and the mobile thumbstick all work.
	Jump / crouch keys come from MovementConfig.Keybinds via ContextActionService.
]]

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)

local JUMP_ACTION = "VantageJump"
local CROUCH_ACTION = "VantageCrouch"

local InputController = {}
InputController.__index = InputController

function InputController.new()
	local self = setmetatable({}, InputController)
	self.JumpHeld = false
	self.JumpPressedAt = -math.huge
	self.CrouchHeld = false
	self.CrouchPressedAt = -math.huge
	self._crouchToggled = false
	self._touchJumpWasDown = false
	self:_findMoveSource()

	ContextActionService:BindActionAtPriority(JUMP_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_pressJump()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self.JumpHeld = false
		end
		-- Pass so nothing else breaks; MovementController overrides Humanoid.Jump every frame anyway.
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(Config.Keybinds.Jump))

	local touchButton = Config.CreateTouchCrouchButton and UserInputService.TouchEnabled
	ContextActionService:BindActionAtPriority(CROUCH_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_pressCrouch()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self.CrouchHeld = false
		end
		return Enum.ContextActionResult.Sink
	end, touchButton, Enum.ContextActionPriority.High.Value, table.unpack(Config.Keybinds.Crouch))
	if touchButton then
		ContextActionService:SetTitle(CROUCH_ACTION, "Crouch")
	end

	return self
end

-- Locate the move input source (new Input Action System first, legacy ControlModule second).
function InputController:_findMoveSource()
	local player = Players.LocalPlayer
	local StarterPlayer = game:GetService("StarterPlayer")
	local function findContext(root: Instance?)
		local contexts = root and root:FindFirstChild("InputContexts")
		return contexts and contexts:FindFirstChild("CharacterContext")
	end
	-- server-authority places the contexts under the Player; default under StarterPlayer.PlayerModule
	local context = findContext(player) or findContext(StarterPlayer:FindFirstChild("PlayerModule"))
	if context then
		self._moveAction = context:FindFirstChild("MoveAction")
		self._jumpAction = context:FindFirstChild("JumpAction")
		if self._moveAction then
			return
		end
	end
	local legacy = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("PlayerModule")
	if legacy then
		local ok, controls = pcall(function()
			return require(legacy):GetControls()
		end)
		if ok then
			self._controls = controls
			return
		end
	end
	warn("[VANTAGE] InputController: no move input source found yet, will retry")
end

-- Raw move intent: X = right, Z = back (Roblox local convention), magnitude 0..1.
function InputController:GetMoveVector(): Vector3
	if self._moveAction then
		local v = self._moveAction:GetState() :: Vector2
		return Vector3.new(v.X, 0, -v.Y)
	elseif self._controls then
		return self._controls:GetMoveVector()
	end
	self:_findMoveSource()
	return Vector3.zero
end

function InputController:_pressJump()
	self.JumpHeld = true
	self.JumpPressedAt = os.clock()
end

function InputController:_pressCrouch()
	self.CrouchHeld = true
	self.CrouchPressedAt = os.clock()
	if Config.CrouchToggle then
		self._crouchToggled = not self._crouchToggled
	end
end

-- Polled once per frame: picks up the mobile on-screen jump button.
function InputController:Update()
	if not UserInputService.TouchEnabled then
		return -- keyboard / gamepad jumps come through ContextActionService
	end
	local down: boolean? = nil
	if self._jumpAction then
		down = self._jumpAction:GetState() == true
	else
		local touchJump = self._controls and self._controls.touchJumpController
		if touchJump and touchJump.GetIsJumping then
			down = touchJump:GetIsJumping()
		end
	end
	if down ~= nil then
		if down and not self._touchJumpWasDown then
			self:_pressJump()
		elseif not down and self._touchJumpWasDown then
			self.JumpHeld = false
		end
		self._touchJumpWasDown = down
	end
end

function InputController:IsCrouchActive(): boolean
	if Config.CrouchToggle then
		return self._crouchToggled
	end
	return self.CrouchHeld
end

function InputController:ClearCrouchToggle()
	self._crouchToggled = false
end

function InputController:ResetForSpawn()
	self.JumpPressedAt = -math.huge
	self.CrouchPressedAt = -math.huge
	self._crouchToggled = false
end

-- Camera-relative, horizontal, magnitude 0..1 (analog sticks give partial magnitude).
function InputController:GetWishDirection(camera: Camera): Vector3
	local mv = self:GetMoveVector()
	if mv.Magnitude < 0.01 then
		return Vector3.zero
	end
	local cf = camera.CFrame
	local look = cf.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		-- looking straight up/down: use the camera's up vector to find "forward"
		local up = look.Y < 0 and cf.UpVector or -cf.UpVector
		forward = Vector3.new(up.X, 0, up.Z)
	end
	forward = forward.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local wish = right * mv.X + forward * -mv.Z
	if wish.Magnitude > 1 then
		wish = wish.Unit
	end
	return wish
end

function InputController:Destroy()
	ContextActionService:UnbindAction(JUMP_ACTION)
	ContextActionService:UnbindAction(CROUCH_ACTION)
end

return InputController
