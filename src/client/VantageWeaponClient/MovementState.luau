--[[
	VANTAGE — MovementState (client, read-only)
	Derives the local player's movement state for weapon feel WITHOUT touching the
	movement system: reads the physical character the MovementController drives.
		.Speed, .Velocity, .Grounded, .VerticalSpeed, .Stance ("Stand"|"Crouch"|"Slide")
		.Landed(callback(impact)), .Jumped(callback())
	Stance comes from the HipHeight drop the MovementController applies (Config.CrouchHeightDrop
	/ SlideHeightDrop), so it is zero-latency and matches what the player feels.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MoveConfig = require(ReplicatedStorage.Vantage.Movement.MovementConfig)

local MovementState = {}
MovementState.__index = MovementState

function MovementState.new(character: Model, humanoid: Humanoid, root: BasePart)
	local self = setmetatable({}, MovementState)
	self.Character = character
	self.Humanoid = humanoid
	self.Root = root
	self.StandHipHeight = humanoid.HipHeight
	self.Speed = 0
	self.Velocity = Vector3.zero
	self.VerticalSpeed = 0
	self.Grounded = true
	self.Stance = "Stand"
	self._minVy = 0
	self._landed = {}
	self._jumped = {}
	return self
end

function MovementState:OnLanded(cb)
	table.insert(self._landed, cb)
end

function MovementState:OnJumped(cb)
	table.insert(self._jumped, cb)
end

function MovementState:Step()
	local v = self.Root.AssemblyLinearVelocity
	self.Velocity = Vector3.new(v.X, 0, v.Z)
	self.Speed = self.Velocity.Magnitude
	self.VerticalSpeed = v.Y
	local grounded = self.Humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded and not self.Grounded then
		local impact = -self._minVy
		for _, cb in self._landed do
			task.spawn(cb, impact)
		end
	elseif not grounded and self.Grounded then
		self._minVy = 0
		if v.Y > 8 then
			for _, cb in self._jumped do
				task.spawn(cb)
			end
		end
	end
	if not grounded then
		self._minVy = math.min(self._minVy, v.Y)
	end
	self.Grounded = grounded

	local drop = self.StandHipHeight - self.Humanoid.HipHeight
	if drop > (MoveConfig.CrouchHeightDrop + MoveConfig.SlideHeightDrop) * 0.5 then
		self.Stance = "Slide"
	elseif drop > MoveConfig.CrouchHeightDrop * 0.45 then
		self.Stance = "Crouch"
	else
		self.Stance = "Stand"
	end
end

return MovementState
