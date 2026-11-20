--[[
	VANTAGE — PoseController (client, all characters)

	⚠ PLACEHOLDER SYSTEM ⚠
	Procedural joint offsets used ONLY while MovementAnimations has no asset for
	Crouch / Slide / Land. It bends R15 joints by offsetting the parent-side frame of
	each joint, which layers on top of whatever animation is playing
	(e.g. run + crouch pose = crouch-run). Supports both rig joint types:
		• Motor6D              -> offsets C0
		• AnimationConstraint  -> offsets Attachment0.CFrame (Roblox's newer avatar joints)

	These edits do not replicate, so every client poses every character itself:
		• local character  -> from the local MovementController (zero latency)
		• other characters -> from the server-validated "VantageStance" attribute
	Once real animations are uploaded and their IDs added, the matching pose here is
	skipped automatically.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
local Animations = require(ReplicatedStorage.Vantage.Movement.MovementAnimations)

local rad = math.rad
local ang = CFrame.Angles

-- Offsets per R15 joint (applied as C0 * offset). +X on a hip lifts the thigh forward,
-- -X on a knee folds the shin back, -X on Root leans the body forward.
local POSES = {
	Crouch = {
		Root = ang(rad(-10), 0, 0),
		Waist = ang(rad(-6), 0, 0),
		LeftHip = ang(rad(62), 0, 0),
		RightHip = ang(rad(62), 0, 0),
		LeftKnee = ang(rad(-100), 0, 0),
		RightKnee = ang(rad(-100), 0, 0),
	},
	Slide = {
		Root = ang(rad(22), 0, 0),
		Waist = ang(rad(-14), 0, 0),
		LeftHip = ang(rad(80), 0, rad(-6)),
		RightHip = ang(rad(58), 0, rad(18)),
		LeftKnee = ang(rad(-8), 0, 0),
		RightKnee = ang(rad(-120), 0, 0),
	},
	Land = {
		Root = ang(rad(-6), 0, 0),
		LeftHip = ang(rad(28), 0, 0),
		RightHip = ang(rad(28), 0, 0),
		LeftKnee = ang(rad(-45), 0, 0),
		RightKnee = ang(rad(-45), 0, 0),
	},
}

local MOTORS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
}

local BLEND_RATE = 16

local function procedural(stance: string): boolean
	local ids = Animations.R15
	if stance == "Crouch" then
		return ids.Crouch == "" or ids.CrouchWalk == ""
	elseif stance == "Slide" then
		return ids.Slide == ""
	elseif stance == "Land" then
		return ids.Land == ""
	end
	return false
end

local PoseController = {}
local records: { [Model]: any } = {}
local localSource = nil -- { character, movement }
local started = false

local function track(character: Model)
	if records[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- R6: no procedural pose (known limitation)
	end
	local motors, original, current = {}, {}, {}
	for jointName, partName in MOTORS do
		local part = character:WaitForChild(partName, 10)
		local joint = part and part:WaitForChild(jointName, 5)
		if joint and joint:IsA("Motor6D") then
			motors[jointName] = { Object = joint, Property = "C0" }
			original[jointName] = joint.C0
			current[jointName] = CFrame.identity
		elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
			motors[jointName] = { Object = joint.Attachment0, Property = "CFrame" }
			original[jointName] = joint.Attachment0.CFrame
			current[jointName] = CFrame.identity
		end
	end
	local record = {
		Motors = motors,
		Original = original,
		Current = current,
		Target = "None",
		Settled = true,
		LandUntil = 0,
	}
	records[character] = record

	local function readAttribute()
		record.Stance = character:GetAttribute("VantageStance") or "Stand"
		record.Settled = false
	end
	readAttribute()
	character:GetAttributeChangedSignal("VantageStance"):Connect(readAttribute)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			records[character] = nil
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(c)
		task.spawn(track, c)
	end)
	if player.Character then
		task.spawn(track, player.Character)
	end
end

local function step(dt: number)
	local now = os.clock()
	local alpha = 1 - math.exp(-BLEND_RATE * dt)
	for character, record in records do
		local stance
		if localSource and localSource.Character == character then
			stance = localSource.Movement.Stance
		else
			stance = record.Stance
		end
		local target = "None"
		if (stance == "Crouch" or stance == "Slide") and procedural(stance) then
			target = stance
		elseif now < record.LandUntil and procedural("Land") then
			target = "Land"
		end
		if target ~= record.Target then
			record.Target = target
			record.Settled = false
			record.SettleAt = now + 0.6
		end
		if not record.Settled then
			local pose = POSES[target]
			for jointName, joint in record.Motors do
				local goal = (pose and pose[jointName]) or CFrame.identity
				local cur = record.Current[jointName]:Lerp(goal, alpha)
				record.Current[jointName] = cur
				joint.Object[joint.Property] = record.Original[jointName] * cur
			end
			if now >= (record.SettleAt or 0) then
				record.Settled = true -- fully blended: stop touching joints until the target changes
			end
		end
	end
end

function PoseController.Start()
	if started then
		return
	end
	started = true
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	RunService.RenderStepped:Connect(step)
end

function PoseController.SetLocalSource(character: Model, movement)
	localSource = { Character = character, Movement = movement }
	task.spawn(track, character)
end

function PoseController.PlayLand(character: Model)
	local record = records[character]
	if record then
		record.LandUntil = os.clock() + Config.LandAnimTime
	end
end

return PoseController
