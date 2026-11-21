--[[
	VANTAGE — ViewmodelArms (client)
	First-person arms. Since 2026-11-17 players are their own avatars: the exosuit template FPArms is
	archived (ServerStorage._ArmourArchive_20261117), so the avatar-arm path below is the one in use.
	Old default: the exo-suit template ReplicatedStorage.Vantage.Weapons.FPArms
	(bones with R15 rig attachments + visual armour parts, authored in camera-space studs, team
	stripe tinted to the player's team). Fallback (no template): clones of the player's own avatar
	arm parts scaled by Viewmodel.Scale / ThirdPerson.Scale. Posed every frame with the shared
	two-bone IK (ArmRig), so hands stay on the weapon grips and arms never stretch or detach.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ArmRig = require(ReplicatedStorage.Vantage.Weapons.ArmRig)
local EquipmentFolder = ReplicatedStorage.Vantage:WaitForChild("Equipment")
local EquipCatalog = require(EquipmentFolder:WaitForChild("EquipmentCatalog"))
local EquipBuild = require(EquipmentFolder:WaitForChild("EquipmentBuild"))

local ViewmodelArms = {}
ViewmodelArms.__index = ViewmodelArms

local KEEP = { Attachment = true, SurfaceAppearance = true, Decal = true, Texture = true }

local function cloneLimb(src: BasePart, scale: number): BasePart
	local c = src:Clone()
	for _, ch in c:GetChildren() do
		if not KEEP[ch.ClassName] then
			ch:Destroy()
		end
	end
	for _, ch in c:GetChildren() do
		if ch:IsA("Attachment") then
			ch.Position *= scale
		end
	end
	c.Size = src.Size * scale
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Massless = true
	c.Transparency = 0
	c.LocalTransparencyModifier = 0
	return c
end

local function fallbackLimb(name: string, size: Vector3, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- exo-suit template arms: bones are invisible, their child parts are visuals posed with them
function ViewmodelArms._fromTemplate(template: Model, character: Model, parent: Instance)
	local self = setmetatable({}, ViewmodelArms)
	local model = template:Clone()
	model.Name = "Arms"
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	if player then
		-- the player's Grappling Hook on the left forearm (armour customisation retired 2026-11-17)
		pcall(EquipBuild.ApplyFP, model, EquipCatalog.Equipped(player, "Hook"))
	end
	local teamColor = player and player.Team and not player.Neutral and player.TeamColor.Color or nil
	self.Parts, self.Visuals, self.AllVisual = {}, {}, {}
	self.SideVisual, self.SideHidden = { Right = {}, Left = {} }, { Right = false, Left = false }
	for _, side in ipairs({ "Right", "Left" }) do
		local n = ArmRig.Names(side)
		for _, partName in ipairs({ n.Upper, n.Lower, n.Hand }) do
			local bone = model:FindFirstChild(partName) :: BasePart
			bone.Transparency = 1
			local list = {}
			for _, v in bone:GetChildren() do
				if v:IsA("BasePart") then
					table.insert(list, { Part = v, Offset = bone.CFrame:ToObjectSpace(v.CFrame) })
					table.insert(self.AllVisual, v)
					table.insert(self.SideVisual[side], v)
					if v.Name == "TeamStripe" and teamColor then
						v.Color = teamColor
					end
				end
			end
			self.Parts[partName] = bone
			self.Visuals[partName] = list
		end
	end
	model.Parent = parent
	self.Model = model
	self.Right = ArmRig.Read(model, "Right", 1)
	self.Left = ArmRig.Read(model, "Left", 1)
	self.Reached = { Right = true, Left = true }
	self.Hidden = false
	return self
end

function ViewmodelArms.new(character: Model, scale: number, parent: Instance)
	local template = ReplicatedStorage.Vantage.Weapons:FindFirstChild("FPArms")
	if template then
		return ViewmodelArms._fromTemplate(template, character, parent)
	end
	local self = setmetatable({}, ViewmodelArms)
	local model = Instance.new("Model")
	model.Name = "Arms"
	-- a Humanoid makes classic Shirt textures render on the cloned R15 arm parts
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.Parent = model
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then
		shirt:Clone().Parent = model
	end
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		colors:Clone().Parent = model
	end
	self.Parts = {}
	for _, side in ipairs({ "Right", "Left" }) do
		local n = ArmRig.Names(side)
		for _, partName in ipairs({ n.Upper, n.Lower, n.Hand }) do
			local src = character:FindFirstChild(partName)
			local limb
			if src and src:IsA("BasePart") then
				limb = cloneLimb(src, scale)
			else
				limb = fallbackLimb(partName, Vector3.new(0.9, 1.1, 0.9) * scale, Color3.fromRGB(230, 230, 225))
			end
			limb.Parent = model
			self.Parts[partName] = limb
		end
	end
	-- 2026-11-17: the equipped Grappling Hook on the left forearm. Its pieces are children of the limb
	-- and posed with it each frame (Visuals), and hidden with that arm (SideVisual / AllVisual).
	local owner = game:GetService("Players"):GetPlayerFromCharacter(character)
	if owner then
		pcall(EquipBuild.ApplyFP, model, EquipCatalog.Equipped(owner, "Hook"))
	end
	self.Visuals, self.AllVisual = {}, {}
	self.SideVisual, self.SideHidden = { Right = {}, Left = {} }, { Right = false, Left = false }
	for name, limb in self.Parts do
		local side = if string.find(name, "Left", 1, true) then "Left" else "Right"
		table.insert(self.SideVisual[side], limb)
		self.Visuals[name] = {}
		for _, v in limb:GetChildren() do
			if v:IsA("BasePart") then
				table.insert(self.Visuals[name], { Part = v, Offset = limb.CFrame:ToObjectSpace(v.CFrame) })
				table.insert(self.AllVisual, v)
				table.insert(self.SideVisual[side], v)
			end
		end
	end
	model.Parent = parent
	self.Model = model
	self.Right = ArmRig.Read(model, "Right", 1)
	self.Left = ArmRig.Read(model, "Left", 1)
	self.Reached = { Right = true, Left = true }
	self.Hidden = false
	return self
end

function ViewmodelArms:IsValid(): boolean
	return self.Right ~= nil and self.Left ~= nil
end

function ViewmodelArms:HandFromGrip(side: string, gripCF: CFrame): CFrame
	return ArmRig.HandFromGrip(self[side], gripCF)
end

-- Solve one arm and append its three parts to the BulkMoveTo lists.
function ViewmodelArms:Pose(side: string, shoulder: Vector3, handCF: CFrame, pole: Vector3, parts, cfs)
	local arm = self[side]
	if not arm then
		return handCF
	end
	local upperCF, lowerCF, finalHand, reached = ArmRig.Solve(arm, shoulder, handCF, pole)
	self.Reached[side] = reached
	local n = arm.Names
	table.insert(parts, self.Parts[n.Upper]); table.insert(cfs, upperCF)
	table.insert(parts, self.Parts[n.Lower]); table.insert(cfs, lowerCF)
	table.insert(parts, self.Parts[n.Hand]); table.insert(cfs, finalHand)
	if self.Visuals then
		for name, cf in { [n.Upper] = upperCF, [n.Lower] = lowerCF, [n.Hand] = finalHand } do
			for _, v in self.Visuals[name] do
				table.insert(parts, v.Part)
				table.insert(cfs, cf * v.Offset)
			end
		end
	end
	return finalHand
end

-- hide one arm's visuals (e.g. the support arm while aimed down sights)
function ViewmodelArms:SetSideHidden(side: string, hidden: boolean)
	if not self.SideVisual or self.SideHidden[side] == hidden then
		return
	end
	self.SideHidden[side] = hidden
	for _, p in self.SideVisual[side] do
		p.LocalTransparencyModifier = if hidden or self.Hidden then 1 else 0
	end
end

function ViewmodelArms:SetHidden(hidden: boolean)
	if self.Hidden == hidden then
		return
	end
	self.Hidden = hidden
	for _, p in self.Parts do
		p.LocalTransparencyModifier = if hidden then 1 else 0
	end
	if self.AllVisual then
		for _, p in self.AllVisual do
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function ViewmodelArms:Destroy()
	self.Model:Destroy()
end

return ViewmodelArms
