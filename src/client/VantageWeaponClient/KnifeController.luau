--[[
	VANTAGE — KnifeController (client, VK-7)
	States: Equipping -> Ready <-> Attacking / Inspecting, Lowering, Dead.
	  Left click   quick slash (alternates right->left / left->right), hold to chain
	  Right click  heavy stab (backstab from behind = elimination, decided by the server)
	  Inspect key  butterfly flourish (any attack or switch interrupts it)
	The client only says "I struck now, looking this way". The server picks the target,
	checks range / cone / line of sight / cooldown and applies damage (WeaponService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage.Vantage
local Remotes = Vantage:WaitForChild("Remotes")

local KnifeViewmodel = require(script.Parent.KnifeViewmodel)
local ViewmodelAnimator = require(script.Parent.ViewmodelAnimator)

local KnifeController = {}
KnifeController.__index = KnifeController

function KnifeController.new(ctx)
	local self = setmetatable({}, KnifeController)
	local weapon = ctx.Weapon
	self.Weapon = weapon
	self.Id = weapon.Id
	self.Character = ctx.Character
	self.Humanoid = ctx.Humanoid
	self.Input = ctx.Input
	self.Hud = ctx.Hud
	self.Effects = ctx.Effects
	self.Movement = ctx.Movement
	self.Camera = Workspace.CurrentCamera
	local asset = Vantage.Weapons.Assets:WaitForChild(weapon.Asset)
	self.Viewmodel = KnifeViewmodel.new(weapon, asset, self.Camera, ctx.Character)
	self.Animator = ViewmodelAnimator.new(weapon)
	self.State = "Holstered"
	self.Active = false
	self.NextAttackAt = 0
	self.SlashToggle = false
	self.PendingKind = nil
	self._firePressedHandled = self.Input.FirePressedAt
	self._altPressedHandled = self.Input.AltPressedAt
	self._inspectHandled = self.Input.InspectPressedAt
	self.Animator.OnEvent = function(name)
		self:_onEvent(name)
	end
	self.Animator.OnFinished = function(name)
		if (self.State == "Attacking" or self.State == "Inspecting") and self.Active then
			self.State = "Ready"
		end
	end
	return self
end

function KnifeController:Equip()
	self.Active = true
	self.State = "Equipping"
	self.EquipDoneAt = os.clock() + self.Weapon.EquipTime
	self.Viewmodel:SetVisible(true)
	self.Animator:Play("Equip", self.Weapon.EquipTime)
	self.Hud:SetWeapon(self.Weapon)
	self.Hud:SetCrosshairStyle("Knife")
	self._firePressedHandled = self.Input.FirePressedAt
	self._altPressedHandled = self.Input.AltPressedAt
	self._inspectHandled = self.Input.InspectPressedAt
end

function KnifeController:Unequip(): number
	if self.State == "Dead" then
		return 0
	end
	self.State = "Lowering"
	self.Animator:Play("Unequip", self.Weapon.UnequipTime)
	return self.Weapon.UnequipTime
end

function KnifeController:Holster()
	self.Active = false
	self.State = "Holstered"
	self.Viewmodel:SetVisible(false)
end

function KnifeController:CanSwitch(): boolean
	return true
end

function KnifeController:IsADS(): number
	return 0
end

function KnifeController:_onEvent(name: string)
	if name == "Strike" then
		self:_strike()
	elseif name == "Equip" then
		self.Effects:PlayCue(self.Id, "Equip")
	elseif name == "Flip" then
		self.Effects:PlayCue(self.Id, "Flip")
	elseif name == "Catch" then
		self.Effects:PlayCue(self.Id, "Flip")
	end
end

function KnifeController:_strike()
	local kind = self.PendingKind
	if not kind or self.State == "Dead" then
		return
	end
	self.PendingKind = nil
	local spec = self.Weapon[kind]
	local cam = self.Camera.CFrame
	self.Effects:PlayCue(self.Id, "Swing")
	Remotes.WeaponAction:FireServer("Melee", kind, Workspace:GetServerTimeNow(), cam.LookVector)
	-- predicted world contact (sparks on walls). Body hits wait for the server's confirmation.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Character, self.Camera, Workspace:FindFirstChild("VantageWeaponFX") }
	local res = Workspace:Raycast(cam.Position, cam.LookVector * (spec.Range - 0.5), params)
	if res then
		local model = res.Instance:FindFirstAncestorOfClass("Model")
		local isChar = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
		if not isChar then
			self.Effects:MeleeImpact(res.Position, res.Normal, false)
			self.Viewmodel:HitReaction(kind == "Secondary")
		end
	end
end

function KnifeController:_attack(kind: string, now: number)
	local spec = self.Weapon[kind]
	self.NextAttackAt = now + spec.Cooldown
	self.State = "Attacking"
	self.PendingKind = kind
	local clip
	if kind == "Primary" then
		self.SlashToggle = not self.SlashToggle
		clip = if self.SlashToggle then "Slash1" else "Slash2"
	else
		clip = "Stab"
	end
	local length = self.Animator.Clips[clip].Length
	self.Animator:Play(clip, length)
	if self.Viewmodel.Swing then
		self.Viewmodel:Swing(math.min(length, 0.32)) -- skin swing trail
	end
	-- replicated so other players see the same swing
	Remotes.WeaponAction:FireServer("Anim", clip)
end

function KnifeController:Step(dt: number, now: number, menuOpen: boolean)
	if not self.Active then
		return
	end
	local input = self.Input
	-- third-person ride under the dropship (VantageAircraftClient): no first-person knife / arms
	local thirdPerson = game:GetService("Players").LocalPlayer:GetAttribute("VantageThirdPerson") == true
	if thirdPerson or self._wasThirdPerson then
		self._wasThirdPerson = thirdPerson
		self.Viewmodel:SetHidden(thirdPerson or self.ViewHidden == true)
	end
	if self.State == "Equipping" and now >= self.EquipDoneAt then
		self.State = "Ready"
	end
	local canAct = (self.State == "Ready" or self.State == "Inspecting") and not menuOpen
		and not game:GetService("Players").LocalPlayer:GetAttribute("VantageHangingLocal") -- hanging under the dropship
		and not game:GetService("Players").LocalPlayer:GetAttribute("VantageVehicleLocal") -- seated in a vehicle
	local firePending = input.FirePressedAt > self._firePressedHandled
	local altPending = input.AltPressedAt > self._altPressedHandled
	if canAct and now >= self.NextAttackAt then
		if altPending then
			self._altPressedHandled = input.AltPressedAt
			self:_attack("Secondary", now)
		elseif firePending or input.FireHeld then
			self._firePressedHandled = input.FirePressedAt
			self:_attack("Primary", now)
		end
	elseif not canAct then
		-- clicks during equip are not queued forever
		if firePending and now - input.FirePressedAt > 0.2 then
			self._firePressedHandled = input.FirePressedAt
		end
		if altPending and now - input.AltPressedAt > 0.2 then
			self._altPressedHandled = input.AltPressedAt
		end
	end
	if input.InspectPressedAt > self._inspectHandled then
		self._inspectHandled = input.InspectPressedAt
		if self.State == "Ready" and not menuOpen then
			self.State = "Inspecting"
			self.Animator:Play("Inspect", self.Weapon.InspectTime)
			Remotes.WeaponAction:FireServer("Anim", "Inspect")
		end
	end
	local pose = self.Animator:Sample()
	self.Viewmodel:Step(dt, { Movement = self.Movement, Pose = pose })
end

function KnifeController:OnConfirm(info)
	if info.Melee and info.Position and not info.Blocked then
		local cam = self.Camera.CFrame
		self.Effects:MeleeImpact(info.Position, (cam.Position - info.Position).Unit, true)
		self.Viewmodel:HitReaction(info.Kind == "Secondary")
	end
end

function KnifeController:OnDied()
	self.State = "Dead"
	self.Animator:Play("Unequip", self.Weapon.UnequipTime)
	task.delay(self.Weapon.UnequipTime, function()
		self.Viewmodel:SetVisible(false)
	end)
end

function KnifeController:Destroy()
	self.State = "Gone"
	self.Viewmodel:Destroy()
end

return KnifeController
