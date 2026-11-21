--[[
	VANTAGE — AnimationController (client, local character)
	Replaces Roblox's default Animate script (suppressed via an empty
	StarterCharacterScripts.Animate). Exactly ONE locomotion track plays at a time and
	switches with a cross-fade, so states never stack or snap.
	Tracks played on the local Animator replicate to other players automatically.

	States: Idle, Run, Jump, Fall, Crouch, CrouchWalk, Slide (+ one-shot Land).
	Missing assets (empty IDs in MovementAnimations) fall back to:
		Crouch -> Idle track + procedural crouch pose
		CrouchWalk -> Run track (slowed) + procedural crouch pose
		Slide -> no locomotion track + procedural slide pose
		Land -> procedural land pose
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
local Animations = require(ReplicatedStorage.Vantage.Movement.MovementAnimations)
local PoseController = require(script.Parent.PoseController)

local AP = Enum.AnimationPriority
local PRIORITY = {
	Idle = AP.Idle,
	Crouch = AP.Idle,
	Run = AP.Movement,
	CrouchWalk = AP.Movement,
	Jump = AP.Movement,
	Fall = AP.Movement,
	Slide = AP.Action,
	Land = AP.Action2,
}
local ONE_SHOT = { Jump = true, Land = true }

local AnimationController = {}
AnimationController.__index = AnimationController

function AnimationController.new(character: Model, humanoid: Humanoid, movement)
	local self = setmetatable({}, AnimationController)
	self.Character = character
	self.Movement = movement
	self.Tracks = {}
	self.CurrentName = nil
	self.Current = nil
	self._lastSpeedScale = 1
	self._moving = false

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	-- stop anything that might already be playing (e.g. a leftover default Animate)
	for _, t in animator:GetPlayingAnimationTracks() do
		t:Stop(0)
	end

	local ids = if humanoid.RigType == Enum.HumanoidRigType.R15 then Animations.R15 else Animations.R6
	for name, id in ids do
		if id ~= "" then
			local anim = Instance.new("Animation")
			anim.Name = "Vantage" .. name
			anim.AnimationId = id
			local ok, trackOrErr = pcall(animator.LoadAnimation, animator, anim)
			if ok then
				trackOrErr.Priority = PRIORITY[name] or AP.Core
				trackOrErr.Looped = not ONE_SHOT[name]
				self.Tracks[name] = trackOrErr
			else
				warn("[VANTAGE] Failed to load animation", name, id, trackOrErr)
			end
		end
	end

	self._landedConn = movement.Landed:Connect(function(impact: number)
		if impact < 20 then
			return
		end
		local land = self.Tracks.Land
		if land then
			land:Play(0.05)
		else
			PoseController.PlayLand(character)
		end
	end)
	return self
end

function AnimationController:_play(name: string?)
	if name == self.CurrentName then
		return
	end
	local fade = Config.AnimFadeTime
	if self.Current then
		self.Current:Stop(fade)
	end
	self.CurrentName = name
	self.Current = name and self.Tracks[name] or nil
	if self.Current then
		self.Current:Play(fade)
		self._lastSpeedScale = 1
	end
end

function AnimationController:Step()
	local m = self.Movement
	local speed = m.Velocity.Magnitude
	-- hysteresis so tiny speed jitter never flickers idle <-> run
	if self._moving then
		self._moving = speed > 0.5
	else
		self._moving = speed > 1.5
	end

	local name: string?
	if m.Stance == "Slide" then
		name = if self.Tracks.Slide then "Slide" else nil
	elseif not m.Grounded then
		local vy = m.Root.AssemblyLinearVelocity.Y
		if vy > 2 and os.clock() - m.LastJumpAt < 0.4 then
			name = "Jump"
		else
			name = "Fall"
		end
	elseif m.Stance == "Crouch" then
		if self._moving then
			name = if self.Tracks.CrouchWalk then "CrouchWalk" else "Run"
		else
			name = if self.Tracks.Crouch then "Crouch" else "Idle"
		end
	else
		name = if self._moving then "Run" else "Idle"
	end
	self:_play(name)

	if self.Current and (name == "Run" or name == "CrouchWalk") then
		local ref = if name == "CrouchWalk" then Config.CrouchSpeed else Config.RunAnimReferenceSpeed
		local scale = math.clamp(speed / ref, 0.4, 2)
		if math.abs(scale - self._lastSpeedScale) > 0.05 then
			self._lastSpeedScale = scale
			self.Current:AdjustSpeed(scale)
		end
	end
end

function AnimationController:Destroy()
	self._landedConn:Disconnect()
	for _, t in self.Tracks do
		t:Stop(0)
		t:Destroy()
	end
end

return AnimationController
