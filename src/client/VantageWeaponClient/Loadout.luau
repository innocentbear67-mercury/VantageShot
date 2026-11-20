--[[
	VANTAGE — Loadout (client, one per character life)
	Owns one controller per loadout weapon (WeaponConfig.Loadout: guns + knife), switching
	(keys 1-7 / V knife / Q last weapon / mouse wheel), the shared recoil layer (re-targeted to
	the equipped gun's profile), aim replication and the view layer:
	  • switching: lower current (Unequip) -> raise next (Equip); the server is told at once
	    ("Equip") and enforces equip times, speed and which weapon may fire / stab.
	  • aim replication: pitch + ADS at <= Server.AimSendRate Hz (UnreliableRemoteEvent).
	  • ADS slow-down: local-only character attribute VantageLocalSpeedMult (read by movement).
	  • FOV: CameraEffects' FOV * (FOV setting / base) * ADS zoom, applied at Camera+2.
	  • Sensitivity: camera mouse binding = base rate * setting * weapon mult * ADS mult * zoom match.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage.Vantage
local Config = require(Vantage.Weapons.WeaponConfig)
local LoadoutPresets = require(game:GetService("ReplicatedStorage").Vantage.Weapons:WaitForChild("LoadoutPresets")) -- per-player loadout (2026-11-17)
local MoveConfig = require(Vantage.Movement.MovementConfig)
local Remotes = Vantage.Remotes

local MovementState = require(script.Parent.MovementState)
local Recoil = require(script.Parent.Recoil)
local WeaponController = require(script.Parent.WeaponController)
local KnifeController = require(script.Parent.KnifeController)
local AimAssist = require(script.Parent.AimAssist)

local Loadout = {}
Loadout.__index = Loadout

-- Camera turn per mouse count at sensitivity 1, in degrees (Roblox's stock binding is 0.5, and 0.77x
-- that vertically). Both axes share it; Y keeps its own sign (the sign carries the invert-camera setting).
local AIM_DEG_PER_COUNT = 0.12

local mouseBinding = nil
-- The rate is written straight to the camera's mouse binding, so every sensitivity setting reaches the
-- camera; MouseDeltaSensitivity stays 1 so it can never scale the same input twice.
local function setMouseRate(rate: number)
	-- 2026-11-18: Singularity's gravity well slows your aim too (server-set PerkAimSlow, EquipmentPerkServer)
	local me = Players.LocalPlayer.Character
	local slowUntil = me and me:GetAttribute("PerkSlowUntil")
	if type(slowUntil) == "number" and slowUntil > Workspace:GetServerTimeNow() then
		local s = me:GetAttribute("PerkAimSlow")
		if type(s) == "number" then
			rate *= math.clamp(s, 0.2, 1)
		end
	end
	if not mouseBinding then
		local module = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
			or Players.LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
		local action = module and module:FindFirstChild("CameraRotationAction", true)
		mouseBinding = action and action:FindFirstChild("MouseBinding")
	end
	if mouseBinding then
		local s = mouseBinding.Vector2Scale
		local scale = math.rad(AIM_DEG_PER_COUNT) * rate
		if math.abs(s.X - scale) > 1e-7 or math.abs(math.abs(s.Y) - scale) > 1e-7 then
			mouseBinding.Vector2Scale = Vector2.new(scale, if s.Y < 0 then -scale else scale)
		end
	end
	UserInputService.MouseDeltaSensitivity = 1
end

function Loadout.new(ctx)
	local self = setmetatable({}, Loadout)
	self.Character = ctx.Character
	self.Humanoid = ctx.Humanoid
	self.Input = ctx.Input
	self.Hud = ctx.Hud
	self.Effects = ctx.Effects
	self.Settings = ctx.Settings
	self.Menu = ctx.Menu
	self.Camera = Workspace.CurrentCamera
	self.Movement = MovementState.new(ctx.Character, ctx.Humanoid, ctx.Root)
	self.Recoil = Recoil.new(Config.Weapons[Config.DefaultWeapon])
	self.Order = LoadoutPresets.ActiveList(game:GetService("Players").LocalPlayer) -- knife (key 1) + preset guns (keys 2-4)
	self.Controllers = {}
	for _, id in self.Order do
		local w = Config.Weapons[id]
		local c = {
			Weapon = w,
			Character = ctx.Character,
			Humanoid = ctx.Humanoid,
			Input = ctx.Input,
			Hud = ctx.Hud,
			Effects = ctx.Effects,
			Movement = self.Movement,
			Recoil = self.Recoil,
		}
		self.Controllers[id] = if w.Kind == "Melee" then KnifeController.new(c) else WeaponController.new(c)
	end
	self.CurrentId = nil
	self.LastId = self.Order[3] or self.Order[2]
	self.KnifeId = nil
	for _, id in self.Order do
		if Config.Weapons[id].Kind == "Melee" then
			self.KnifeId = id
		end
	end
	self.Dead = false
	setMouseRate(ctx.Settings:Get("Sensitivity"))
	self.Movement:OnLanded(function(impact)
		local c = self:Current()
		if c then
			c.Viewmodel:LandImpulse(impact)
		end
	end)
	self._died = ctx.Humanoid.Died:Connect(function()
		self:OnDied()
	end)
	-- inventory skin change: re-skin the matching viewmodel in place (cosmetic only)
	self._skinConn = game:GetService("Players").LocalPlayer.AttributeChanged:Connect(function(name)
		local id = string.match(name, "^Skin_(.+)$")
		local c = id and self.Controllers[id]
		if c and c.Viewmodel and c.Viewmodel.ApplySkin then
			c.Viewmodel:ApplySkin(game:GetService("Players").LocalPlayer:GetAttribute(name))
		end
	end)
	self._aimSentAt = 0
	self._lastPitch = 1e9
	self._lastADS = false
	self._worldParts = {}
	self:_watchWorldModels()
	if self.Hud and self.Hud.SetLoadout then
		self.Hud:SetLoadout(self.Order)
	end
	self:SwitchTo(self.Order[2] or Config.SpawnWeapon(), true)
	return self
end

function Loadout:Current()
	return self.CurrentId and self.Controllers[self.CurrentId]
end

-- In first person the viewmodel replaces the body: our own avatar (hair / hats included) and our
-- third-person weapons must never render. Roblox's camera transparency controller normally hides
-- the body, but it can stop doing so after the death camera switched CameraType, so this is
-- enforced here every frame while the camera is in the head.
function Loadout:_watchWorldModels()
	local function scan()
		local list = {}
		for _, d in self.Character:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				table.insert(list, d)
			end
		end
		self._worldParts = list
	end
	scan()
	self._childConn = self.Character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			task.defer(scan)
		end
	end)
	self._head = self.Character:FindFirstChild("Head")
end

function Loadout:SwitchTo(id: string, instant: boolean?)
	if self.Dead or id == self.CurrentId or not self.Controllers[id] then
		return
	end
	if self.Switching then
		self.PendingId = id
		return
	end
	Remotes.WeaponAction:FireServer("Equip", id)
	local old = self:Current()
	local lower = 0
	if old and not instant then
		lower = old:Unequip()
	end
	self.Switching = true
	self.PendingId = id
	self.SwitchAt = os.clock() + lower
	self.SwitchFrom = old
end

function Loadout:_finishSwitch()
	local old = self.SwitchFrom
	if old then
		old:Holster()
		self.LastId = self.CurrentId
	end
	self.CurrentId = self.PendingId
	self.Switching = false
	self.SwitchFrom = nil
	local c = self:Current()
	if c.Weapon.Recoil then
		self.Recoil.Cfg = c.Weapon.Recoil -- each gun keeps its own recoil profile
	end
	c:Equip()
	if self.PendingId ~= self.CurrentId then
		local nxt = self.PendingId
		self.PendingId = nil
		self:SwitchTo(nxt)
	end
end

function Loadout:_handleSlotRequests()
	local r = self.Input:ConsumeSlotRequest()
	if r == nil then
		return
	end
	local target
	if type(r) == "number" then
		target = self.Order[r] -- 1 = knife, 2-4 = the preset guns
	elseif r == "knife" then
		target = self.KnifeId
	elseif r == "swap" then
		target = self.LastId or self.Order[2]
	elseif r == "next" or r == "prev" then
		local cur = table.find(self.Order, self.PendingId or self.CurrentId) or 1
		local n = #self.Order
		target = if r == "next" then self.Order[cur % n + 1] else self.Order[(cur - 2) % n + 1]
	end
	if target then
		if self.Switching then
			self.PendingId = target
		else
			self:SwitchTo(target)
		end
	end
end

function Loadout:ADSAlpha(): number
	local c = self:Current()
	if c and c.ADSAlpha then
		return c:ADSAlpha()
	end
	return 0
end

function Loadout:_sendAim(now: number, ads: boolean)
	local look = self.Camera.CFrame.LookVector
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	local interval = 1 / Config.Server.AimSendRate
	if now - self._aimSentAt < interval then
		return
	end
	if math.abs(pitch - self._lastPitch) < 1 and ads == self._lastADS and now - self._aimSentAt < 0.6 then
		return
	end
	self._aimSentAt = now
	self._lastPitch = pitch
	self._lastADS = ads
	local remote = Remotes:FindFirstChild("WeaponAim")
	if remote then
		remote:FireServer(math.floor(pitch * 2 + 0.5) / 2, ads)
	end
end

-- RenderPriority.Camera - 1
function Loadout:UndoView()
	self.Recoil:Undo(self.Camera)
end

-- RenderPriority.Camera + 2
function Loadout:Step(dt: number)
	if self.Gone then
		return
	end
	local now = os.clock()
	local settings = self.Settings
	local menuOpen = self.Menu.Open
	self.Movement:Step()
	self.Recoil.PunchEnabled = settings:Get("ScreenShake")
	self.Recoil:Step(dt)
	self.Recoil:Apply(self.Camera)

	if not self.Dead then
		if self.Switching and now >= self.SwitchAt then
			self:_finishSwitch()
		end
		self:_handleSlotRequests()
	end
	local current = self:Current()
	local hidden = not settings:Get("ShowViewmodel")
	for _, c in self.Controllers do
		c.ViewHidden = hidden
		c.Viewmodel:SetHidden(hidden or c.Scoped == true) -- full-screen scopes hide the gun
	end
	if current then
		current:Step(dt, now, menuOpen)
	end

	local ads = self:ADSAlpha()
	local weapon = current and current.Weapon or Config.Weapons[Config.DefaultWeapon]
	-- ADS movement slow-down (local only; the server only validates upper limits)
	local adsCfg = weapon.ADS
	local slow = if adsCfg then 1 - (1 - adsCfg.MoveSpeedMultiplier) * ads else 1
	if self._lastSlow ~= slow then
		self._lastSlow = slow
		self.Character:SetAttribute("VantageLocalSpeedMult", slow)
	end
	local zoomOnly = adsCfg and adsCfg.Mode == "Zoom"
	if not self.Dead then
		self:_sendAim(now, ads > 0.5 and not zoomOnly)
	end

	-- view layer: FOV + sensitivity
	local cam = self.Camera
	local base = cam.FieldOfView
	if self._lastFov and math.abs(base - self._lastFov) < 1e-3 then
		base = self._lastBase -- CameraEffects did not write this frame: avoid compounding
	end
	-- ADS zoom in magnification (tan) space, the same value the viewmodel uses to hold its
	-- on-screen size (Viewmodel.Magnification): even-feeling zoom, no viewmodel blow-up
	local hipF = math.clamp(base * (settings:Get("FOV") / MoveConfig.BaseFOV), 8, 110)
	local magNow = 1
	if adsCfg and (adsCfg.FOV or adsCfg.ZoomFOV) then
		local zf = if zoomOnly and adsCfg.ZoomFOV then adsCfg.ZoomFOV else adsCfg.FOV
		local M = math.tan(math.rad(MoveConfig.BaseFOV / 2)) / math.tan(math.rad(zf / 2))
		magNow = 1 + (M - 1) * ads
	end
	local fov = math.clamp(2 * math.deg(math.atan(math.tan(math.rad(hipF / 2)) / magNow)), 8, 110)
	cam.FieldOfView = fov
	self._lastBase = base
	self._lastFov = fov
	local weaponMult = if weapon.Kind == "Melee" then settings:Get("MeleeSensitivity") else settings:Get("RifleSensitivity")
	-- zoom match: the same mouse movement crosses the same distance on screen at every zoom level
	local hipFov = math.clamp(base * (settings:Get("FOV") / MoveConfig.BaseFOV), 8, 110)
	local zoomMatch = math.tan(math.rad(fov / 2)) / math.tan(math.rad(hipFov / 2))
	local adsMult = (1 + (settings:Get("ADSSensitivity") - 1) * ads) * zoomMatch
	-- aim assist friction: slower turning while the crosshair is on / beside a visible enemy
	AimAssist.Enabled = settings:Get("AimAssist") ~= false
	local fric = 1
	if not self.Dead and weapon.Kind == "Gun" then
		local cf = cam.CFrame
		fric = AimAssist.Friction(self.Character, cf.Position, cf.LookVector, weapon, ads)
	end
	self._fric = (self._fric or 1) + (fric - (self._fric or 1)) * 0.3
	setMouseRate(settings:Get("Sensitivity") * weaponMult * adsMult * self._fric)
	self.Recoil.PunchScale = zoomMatch

	-- HUD
	self.Hud:SetADS(if zoomOnly then 0 else ads) -- hip-fire zoom keeps the crosshair
	-- optic overlays project the 3D sight with this frame's final (zoomed) FOV
	if current and current.PostCamera then
		current:PostCamera()
	end
	local spread = if current and current.CurrentSpread then current:CurrentSpread() else 0
	self.Hud:Step(dt, spread, self.Humanoid)
	local head = self._head
	if head and not self.Dead and (cam.CFrame.Position - head.Position).Magnitude < 1.5 then
		for _, p in self._worldParts do
			p.LocalTransparencyModifier = 1
		end
	end
end

-- ─── server messages ─────────────────────────────────────────────────────
function Loadout:OnServerAmmo(weaponId, mag, reserve, reason, reloading, lastSeq)
	local c = self.Controllers[weaponId]
	if c and c.OnServerAmmo then
		c:OnServerAmmo(mag, reserve, reason, reloading, lastSeq)
	end
end

function Loadout:OnConfirm(info)
	if info.Blocked then
		return
	end
	self.Hud:ShowHit(info.Headshot, info.Killed, info.VictimName)
	local wid = info.Weapon or self.CurrentId
	-- marker upgrade, damage number, target flash and only the sound the prediction has not played
	self.Hud.Feedback:Confirm(info, self.Effects, wid)
	local c = if info.Melee then self.Controllers[self.KnifeId] else self.Controllers[wid]
	if c and c.OnConfirm then
		c:OnConfirm(info)
	end
end

function Loadout:OnDied()
	if self.Dead then
		return
	end
	self.Dead = true
	self.Input.FireHeld = false
	self.Input.AltHeld = false
	local c = self:Current()
	if c then
		c:OnDied()
	end
	self.Character:SetAttribute("VantageLocalSpeedMult", nil)
end

function Loadout:Destroy()
	self.Gone = true
	self._died:Disconnect()
	self._skinConn:Disconnect()
	self._childConn:Disconnect()
	self.Recoil:Undo(self.Camera)
	for _, c in self.Controllers do
		c:Destroy()
	end
	setMouseRate(self.Settings:Get("Sensitivity"))
end

return Loadout
