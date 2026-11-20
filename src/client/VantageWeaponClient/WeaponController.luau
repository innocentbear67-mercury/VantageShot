--[[
	VANTAGE — WeaponController (client, VX-01; one per character life)
	State machine: Holstered -> Equipping -> Ready <-> Reloading, Lowering, Dead.
	Prediction: ammo, muzzle FX, tracer and impact are shown instantly; the server is the
	authority (WeaponService) and corrects ammo with "Ammo" messages and confirms damage with
	"Confirm". The client never sends damage or a target — only origin + direction.
	Aim down sights: smooth blend (ADS.InTime / OutTime), blocked while reloading / equipping,
	dropped by sliding. ADS scales spread, recoil, kick, sway, FOV and sensitivity.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VisorFeedADS = require(ReplicatedStorage.Vantage.UI.VisorFeed) -- ADS amount for the visor
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage.Vantage
local WeaponMath = require(Vantage.Weapons.WeaponMath)
local HitPredict = require(script.Parent:WaitForChild("HitPredict"))
local AimAssist = require(script.Parent:WaitForChild("AimAssist"))
local WeaponClips = require(Vantage.Weapons.WeaponClips)
local SkinInspects = require(Vantage.Weapons.SkinInspects) -- per-skin inspects (2026-11-15)
local MoveConfig = require(Vantage.Movement.MovementConfig)
local Remotes = Vantage:WaitForChild("Remotes")

local Viewmodel = require(script.Parent.Viewmodel)
-- weapon HUD pieces (reticle, holo frame, scope lens, heat gauge) live in HudOptics so HUD
-- rewrites can't drop them; they are attached to the Hud class here
require(script.Parent.HudOptics).Install(require(script.Parent.Hud))
local UserInputService = game:GetService("UserInputService")
local ViewmodelAnimator = require(script.Parent.ViewmodelAnimator)

local WeaponController = {}
WeaponController.__index = WeaponController

function WeaponController.new(ctx)
	local self = setmetatable({}, WeaponController)
	local weapon = ctx.Weapon
	self.Weapon = weapon
	self.Id = weapon.Id
	self.Character = ctx.Character
	self.Humanoid = ctx.Humanoid
	self.Input = ctx.Input
	self.Hud = ctx.Hud
	self.Effects = ctx.Effects
	self.Movement = ctx.Movement
	self.Recoil = ctx.Recoil
	self.Camera = Workspace.CurrentCamera
	self.Player = Players.LocalPlayer

	local asset = Vantage.Weapons.Assets:WaitForChild(weapon.Asset)
	self.Viewmodel = Viewmodel.new(weapon, asset, self.Camera, ctx.Character)
	self.Viewmodel:SetIgnore({ ctx.Character, self.Camera })
	local rig = Vantage.Weapons.Assets:FindFirstChild(weapon.Asset .. "_ViewmodelRig")
	self.Animator = ViewmodelAnimator.new(weapon, rig)

	self.Mag = weapon.MagazineSize
	self.Reserve = weapon.ReserveAmmo
	self.State = "Holstered"
	self.Active = false
	self.EquipDoneAt = 0
	self.Interval = 60 / weapon.RPM
	self.NextShotAt = 0
	self.LastShotAt = -math.huge
	self.ShotIndex = 0
	self.Seq = 0
	self.ShotsFired = 0
	self.HitsConfirmed = 0
	self.Kills = 0
	self.ReloadStartedAt = 0
	self.MagInDone = false
	self.ADS = 0
	self.ADSWanted = false
	self._reloadHandled = self.Input.ReloadPressedAt
	self._emptyHandled = self.Input.FirePressedAt
	self._pressConsumed = self.Input.FirePressedAt
	self._devReload = 0
	self.Rng = Random.new()
	-- fire-model state
	self.BurstLeft = 0
	self.RechamberAt = 0
	self.Heat, self.HeatAt, self.LockedUntil, self.LockLen = 0, 0, 0, 1
	self.ShellNextAt, self.ShellEndAt = 0, 0

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	self._params = params

	self.Animator.OnEvent = function(name)
		self:_onClipEvent(name)
	end
	self.Animator.OnFinished = function(name)
		if name == "Reload" and self.State == "Reloading" then
			self:_finishReload()
		end
	end
	return self
end

-- ─── loadout hooks ───────────────────────────────────────────────────────
function WeaponController:Equip()
	self.Active = true
	self.State = "Equipping"
	self.EquipDoneAt = os.clock() + self.Weapon.EquipTime
	self.ADS = 0
	self.Viewmodel:SetVisible(true)
	self.Animator:Play("Equip", self.Weapon.EquipTime)
	self.Hud:SetWeapon(self.Weapon)
	self.Hud:SetCrosshairStyle("Rifle")
	-- gameplay hides the mouse cursor; menus show it on open and restore this on close
	UserInputService.MouseIconEnabled = false
	self:_showAmmo()
	self.Hud:SetReload(nil)
	self.BurstLeft = 0
	self._pressConsumed = self.Input.FirePressedAt
	self._reloadHandled = self.Input.ReloadPressedAt
	self._inspectHandled = self.Input.InspectPressedAt
	self.Inspecting = false
	self:_publish()
end

-- returns seconds until the weapon is fully lowered
function WeaponController:Unequip(): number
	if self.State == "Dead" then
		return 0
	end
	if self.State == "Reloading" then
		self.Hud:SetReload(nil) -- switching cancels the reload (server agrees on Equip)
	end
	self:_cancelInspect(false)
	self:_unscope()
	self.State = "Lowering"
	self.ADSWanted = false
	self.Animator:Play("Unequip", 0.14)
	return 0.14
end

function WeaponController:_unscope()
	if self.Scoped then
		self.Scoped = false
		if self.Hud.SetScopeLens then
			self.Hud:SetScopeLens(nil)
		end
	end
	if self.Hud.SetSightWindow then
		self.Hud:SetSightWindow(nil)
	end
	if self.Hud.HideOptics then
		self.Hud:HideOptics()
	end
end

function WeaponController:Holster()
	self:_unscope()
	self.Active = false
	self.State = "Holstered"
	self.ADS = 0
	self.Viewmodel:SetVisible(false)
	self:_publish()
end

function WeaponController:IsADS(): number
	return self.ADS
end

-- ─── helpers ──────────────────────────────────────────────────────────────
-- ammo block: magazine count, or the heat gauge for energy weapons
function WeaponController:_showAmmo()
	if not self.Active then
		return
	end
	if self.Weapon.Energy then
		local now = os.clock()
		self:_heatNow(now) -- also releases an expired overheat / vent lock
		local locked = self.LockedUntil > 0
		local shown = if locked then math.clamp((self.LockedUntil - now) / self.LockLen, 0, 1) else self:_heatNow(now)
		self.Hud:SetHeat(shown, locked)
	else
		self.Hud:SetAmmo(self.Mag, self.Reserve, self.Weapon.MagazineSize)
	end
end

function WeaponController:_hasRound(): boolean
	if self.Weapon.Energy then
		return self.LockedUntil == 0
	end
	return self.Mag > 0
end

-- heat prediction (mirrors WeaponService.currentHeat; the client is stricter than the server)
function WeaponController:_heatNow(now: number): number
	local H = self.Weapon.Heat
	if self.LockedUntil > 0 then
		if now >= self.LockedUntil then
			self.LockedUntil = 0
			self.Heat = 0
			self.HeatAt = now
			self.Effects:PlayCue(self.Id, "Equip")
		else
			return self.Heat
		end
	end
	local from = math.max(self.HeatAt, self.LastShotAt + H.CoolDelay)
	if now > from then
		self.Heat = math.max(0, self.Heat - H.CoolRate * (now - from))
		self.HeatAt = now
	end
	return self.Heat
end

function WeaponController:_lock(now: number, length: number)
	self.Heat = 1
	self.LockedUntil = now + length
	self.LockLen = length
	self.BurstLeft = 0
	self.Effects:PlayCue(self.Id, "Overheat")
	self.Animator:Play("Vent", length)
end

function WeaponController:_publish()
	-- local-only debug attributes (read by automated tests; never replicated)
	local p = self.Player
	p:SetAttribute("WpnMag", self.Mag)
	p:SetAttribute("WpnReserve", self.Reserve)
	p:SetAttribute("WpnState", self.State)
	p:SetAttribute("WpnShots", self.ShotsFired)
	p:SetAttribute("WpnHits", self.HitsConfirmed)
	p:SetAttribute("WpnKills", self.Kills)
	p:SetAttribute("WpnADS", self.ADS)
	p:SetAttribute("WpnRecoil", self.Recoil:Offset())
end

function WeaponController:CurrentSpread(): number
	local s = self.Weapon.Spread
	local m = self.Movement
	local spread = s.Base
	spread += s.Moving * math.clamp(m.Speed / MoveConfig.RunSpeed, 0, 1)
	if not m.Grounded then
		spread += s.Air
	elseif m.Stance == "Crouch" then
		spread += s.Crouch
	elseif m.Stance == "Slide" then
		spread += s.Slide
	end
	spread += self.Bloom or 0
	local adsMul = 1 - (1 - (self.Weapon.ADS and self.Weapon.ADS.SpreadMultiplier or 1)) * self.ADS
	return math.max(0, spread * adsMul)
end

function WeaponController:_onClipEvent(name: string)
	if string.sub(name, 1, 3) == "FX_" then
		SkinInspects.FX(self.Viewmodel, name)
		return
	end
	if name == "MagOut" then
		self.Effects:PlayCue(self.Id, "MagOut")
	elseif name == "MagIn" then
		self.Effects:PlayCue(self.Id, "MagIn")
		if self.State == "Reloading" and not self.MagInDone then
			-- predicted refill exactly when the new magazine seats
			self.MagInDone = true
			local take = math.min(self.Weapon.MagazineSize - self.Mag, self.Reserve)
			self.Mag += take
			-- infinite reserve (mirrors server): self.Reserve -= take
			self.Hud:SetAmmo(self.Mag, self.Reserve, self.Weapon.MagazineSize)
			self:_publish()
		end
	elseif name == "Rack" then
		-- action worked after a reload (slide / pump / bolt): sound only, no case
		local R = self.Weapon.Rechamber
		self.Effects:PlayCue(self.Id, R and R.Event or "Bolt")
		if self.Effects.Rack then self.Effects:Rack(self.Viewmodel.EjectAttachment) end -- skin rack burst (cosmetic)
	elseif name == "Bolt" or name == "Pump" then
		-- rechamber: the spent case leaves when the action is worked
		self.Effects:PlayCue(self.Id, name)
		local ej = self.Viewmodel.EjectAttachment
		if ej and self.Weapon.Rechamber and not self.Weapon.NoShells then
			self.Effects:Shell(ej.WorldCFrame)
		end
		if self.Effects.Rack then self.Effects:Rack(ej) end -- skin rack burst (cosmetic, shot overhaul stage 6)
	elseif name == "Equip" then
		self.Effects:PlayCue(self.Id, "Equip")
	end
end

-- ─── reload ───────────────────────────────────────────────────────────────
function WeaponController:TryReload(): boolean
	local w = self.Weapon
	local now = os.clock()
	if w.Energy then
		-- R vents: locked for VentTime, then cold (server mirrors it)
		if self.State ~= "Ready" or self.LockedUntil > 0 or self:_heatNow(now) <= 0 then
			return false
		end
		Remotes.WeaponAction:FireServer("Reload")
		self:_lock(now, w.Heat.VentTime)
		self.Effects:PlayCue(self.Id, "Vent")
		return true
	end
	if self.State ~= "Ready" or self.Mag >= w.MagazineSize or self.Reserve <= 0 then
		return false
	end
	self.State = "Reloading"
	self.ReloadStartedAt = now
	self.MagInDone = false
	self.ADSWanted = false
	self.BurstLeft = 0
	self.RechamberAt = 0
	self._pendingAmmo = nil
	Remotes.WeaponAction:FireServer("Reload")
	if w.ReloadMode == "Shell" then
		-- shells one at a time: ReloadStart, ShellIn x n, ReloadEnd
		local sh = w.Shell
		self.ShellNextAt = now + sh.Start + sh.Each
		self.ShellEndAt = 0
		self.Animator:Play("ReloadStart", sh.Start)
		task.delay(sh.Start, function()
			if self.State == "Reloading" and self.ShellEndAt == 0 then
				self.Animator:Play("ShellIn", sh.Each)
			end
		end)
	else
		self.Animator:Play("Reload", w.ReloadTime)
	end
	self:_publish()
	return true
end

-- shotgun shell loop (predicted; the server runs the same schedule slightly ahead)
function WeaponController:_stepShells(now: number)
	local w = self.Weapon
	local sh = w.Shell
	if self.ShellEndAt > 0 then
		if now >= self.ShellEndAt then
			self:_finishReload()
		end
		return
	end
	if now >= self.ShellNextAt then
		if self.Mag < w.MagazineSize and self.Reserve > 0 then
			self.Mag += 1
			-- infinite reserve (mirrors server): self.Reserve -= 1
			self.Effects:PlayCue(self.Id, "ShellIn")
			self:_showAmmo()
			self:_publish()
		end
		if self.Mag >= w.MagazineSize or self.Reserve <= 0 then
			self.ShellEndAt = now + sh.Finish
			self.Animator:Play("ReloadEnd", sh.Finish)
		else
			self.ShellNextAt += sh.Each
			self.Animator:Play("ShellIn", sh.Each)
		end
	end
end

-- Firing with rounds left cancels a reload before the new magazine seats (server-validated).
function WeaponController:CancelReload(): boolean
	if self.State ~= "Reloading" or self.MagInDone or self.Mag <= 0 then
		return false
	end
	if self.Weapon.ReloadMode == "Shell" then
		self._pendingAmmo = nil -- shells already loaded stay; the server confirms the count
	end
	Remotes.WeaponAction:FireServer("CancelReload")
	self.Animator:Stop(0.14)
	self.State = "Ready"
	self.Hud:SetReload(nil)
	self.NextShotAt = math.max(self.NextShotAt, os.clock())
	self:_publish()
	return true
end

function WeaponController:_finishReload()
	self.State = "Ready"
	self.Hud:SetReload(nil)
	if self._pendingAmmo then
		-- the server finished the shell loop first: its numbers are final
		self.Mag, self.Reserve = self._pendingAmmo[1], self._pendingAmmo[2]
		self._pendingAmmo = nil
	end
	self:_showAmmo()
	self.NextShotAt = os.clock()
	self:_publish()
end

-- ─── firing ───────────────────────────────────────────────────────────────
function WeaponController:_shoot(now: number)
	if self.Inspecting then
		self:_cancelInspect() -- any shot ends the inspect, whatever the input path
	end
	local w = self.Weapon
	-- aim = the exact camera the crosshair is drawn on this frame (recoil pattern + punch included)
	local cam = self.Camera.CFrame
	if now - self.LastShotAt > w.Recoil.PatternResetTime then
		self.ShotIndex = 0
	end
	self.ShotIndex += 1
	self.LastShotAt = now

	local dir = WeaponMath.ApplySpread(cam.LookVector, self:CurrentSpread(), self.Rng)
	-- aim assist magnetism: a near miss on a visible enemy is bent onto it (the server re-checks)
	dir = AimAssist.Bend(self.Character, cam.Position, dir, w, self.ADS or 0)
	-- firing bloom (2026-11-14): each shot opens the spread a little (the first shot stays exact),
	-- the crosshair follows it and it recovers once you stop (Spread.PerShot / MaxBloom / BloomRecover)
	local S = w.Spread
	self.Bloom = math.min(S.MaxBloom or 1.4, (self.Bloom or 0) + (S.PerShot or 0.12))
	local origin = cam.Position
	self.Seq += 1
	-- shotgun: only a seed travels; client and server rebuild the identical pellet pattern
	local seed = if w.Shot == "Pellet" then self.Rng:NextInteger(0, 2 ^ 30) else nil
	Remotes.WeaponFire:FireServer(Workspace:GetServerTimeNow(), origin, dir, self.Seq, seed)

	if w.Energy then
		self:_heatNow(now)
		self.Heat = math.min(1, self.Heat + w.Heat.PerShot)
		self.HeatAt = now
		if self.Heat >= 0.999 then
			self:_lock(now, w.Heat.OverheatLock)
		end
	else
		self.Mag -= 1
	end
	self.ShotsFired += 1

	-- local prediction of the visual hit (the server decides damage)
	local fx = Workspace:FindFirstChild("VantageWeaponFX")
	self._params.FilterDescendantsInstances = { self.Character, self.Camera, fx }
	local vm = self.Viewmodel
	self.Effects:MuzzleFlash(vm.MuzzleAttachment)
	local dirs = if seed then WeaponMath.PelletDirs(dir, w.Pellet.Count, w.Pellet.Spread, seed) else { dir }
	local markerShown = false
	for i, d in dirs do
		local res = Workspace:Raycast(origin, d * w.MaxRange, self._params)
		local hitPos = if res then res.Position else origin + d * w.MaxRange
		if w.Shot == "Projectile" and w.Projectile.Gravity then
			-- arcing round (2026-11-18): same arc as the server simulates
			self.Effects:BoltArc(vm:MuzzlePosition(), d, w.Projectile, self._params, self.Id)
		elseif w.Shot == "Projectile" then
			-- visible bolt; its impact plays when it arrives (damage is server-simulated)
			self.Effects:Bolt(vm:MuzzlePosition(), hitPos, w.Projectile, if res then { res.Normal, res.Material, self.Id } else nil)
		elseif w.Beam then
			-- continuous beam (2026-11-18): hit feedback as for bullets, one steady beam instead of tracers
			if not markerShown then
				local ph = HitPredict.Cast(self.Character, origin, d, w.MaxRange)
				if ph then
					markerShown = true
					self.Hud:ShowPredictedHit(ph)
				end
			end
			self.Effects:BeamPulse(self, vm.MuzzleAttachment, hitPos, w.Beam)
			if res and self.ShotIndex % 3 == 0 then
				local model = res.Instance:FindFirstAncestorOfClass("Model")
				if not (model and model:FindFirstChildOfClass("Humanoid")) then
					self.Effects:Impact(res.Position, res.Normal, "World", res.Material, self.Id)
				end
			end
		else
			-- instant hit feedback: this ray passes the server's own hit test (HitPredict)
			if not markerShown then
				local ph = HitPredict.Cast(self.Character, origin, d, w.MaxRange)
				if ph then
					markerShown = true
					self.Hud:ShowPredictedHit(ph)
				end
			end
			-- 2026-11-20: tracers always draw (skin tier identity lives here); aimed in, the streak starts
			-- further out so the bright head doesn't sit on the sight picture (was: no tracer at ADS > 0.5)
			if not seed or i <= 4 then
				local skip = (if seed then 1.4 else 2.5) + 3.5 * math.clamp(self.ADS, 0, 1)
				self.Effects:Tracer(vm:MuzzlePosition(), hitPos, skip)
			end
			if res then
				local model = res.Instance:FindFirstAncestorOfClass("Model")
				local hum = model and model:FindFirstChildOfClass("Humanoid")
				if not hum then
					if i <= 5 then
						self.Effects:Impact(res.Position, res.Normal, "World", res.Material, self.Id)
					end
				elseif hum.Health > 0 and model ~= self.Character and not markerShown then
					-- predicted hit marker: instant, neutral; the server confirm upgrades it (Hud:ShowHit)
					local me = Players.LocalPlayer
					local owner = Players:GetPlayerFromCharacter(model)
					local team = if owner then (if owner.Team and not owner.Neutral then owner.Team.Name else nil) else model:GetAttribute("Team")
					local mine = if me.Team and not me.Neutral then me.Team.Name else nil
					if not (team ~= nil and mine ~= nil and tostring(team) == mine) then
						markerShown = true -- (feedback already started by HitPredict above)
					end
				end
			end
		end
	end
	if w.Rechamber then
		-- pump / bolt is worked just after the shot (the case ejects then, see _onClipEvent)
		self.RechamberAt = now + 0.1
	elseif vm.EjectAttachment and not w.NoShells then
		self.Effects:Shell(vm.EjectAttachment.WorldCFrame)
	end
	self.Effects:PlayFire(self.Id)

	-- deterministic pattern step drives both the camera and the weapon kick
	local adsRecoil = 1 - (1 - (w.ADS and w.ADS.RecoilMultiplier or 1)) * self.ADS
	local up, right = self.Recoil:Kick(self.ShotIndex, adsRecoil)
	vm:FireKick(up, right, self.ShotIndex)
	self.Hud:FireKick()
	self:_showAmmo()
end

function WeaponController:_updateFiring(now: number, menuOpen: boolean)
	local input = self.Input
	-- helmet visor deploying / retracting (black screen): no firing until the optics are up
	-- hanging under the dropship (VantageAircraftClient): both hands on the cable
	-- seated in a vehicle (VantageVehicleClient): the vehicle's weapon only
	if self.Player:GetAttribute("VisorBlackout") or self.Player:GetAttribute("VantageHangingLocal") or self.Player:GetAttribute("VantageVehicleLocal") then
		self._pressConsumed = input.FirePressedAt
		return
	end
	local fireHeld = input.FireHeld and not menuOpen
	local firePressedAt = input.FirePressedAt
	-- Studio-only test hook: HUD attribute DevFire simulates holding the trigger
	if RunService:IsStudio() then
		local gui = self.Hud.Gui
		if gui:GetAttribute("DevFire") then
			if not self._devFireWas then
				firePressedAt = now
				input.FirePressedAt = now
			end
			fireHeld = true
		end
		self._devFireWas = gui:GetAttribute("DevFire") == true
		local dr = gui:GetAttribute("DevReload") or 0
		if dr ~= self._devReload then
			self._devReload = dr
			input.ReloadPressedAt = now
		end
		local da = gui:GetAttribute("DevADS")
		if da ~= nil then
			self._devADS = da
		end
	end

	if input.ReloadPressedAt > self._reloadHandled then
		self._reloadHandled = input.ReloadPressedAt
		self:TryReload()
	end

	local w = self.Weapon
	-- a click not yet turned into a shot (input buffer: taps are never swallowed)
	local pending = firePressedAt > self._pressConsumed
	if pending and self.State == "Reloading" and w.ReloadCancelByFire then
		self:CancelReload()
	end
	if pending and not fireHeld then
		-- a released click fires as soon as the weapon is ready, if that is within the buffer
		local readyAt = math.max(self.NextShotAt, if self.State == "Equipping" then self.EquipDoneAt else 0)
		local canBecomeReady = self.State == "Ready" or self.State == "Equipping"
		if not canBecomeReady or readyAt - firePressedAt > w.FireInputBuffer then
			self._pressConsumed = firePressedAt
			pending = false
		end
	end
	local burst = if w.Trigger == "Burst" then w.Burst else nil
	local wants = pending or (fireHeld and (w.Automatic or burst ~= nil)) or self.BurstLeft > 0
	if self.State ~= "Ready" or not wants then
		return
	end
	if w.Energy then
		if self.LockedUntil > 0 then
			self._pressConsumed = firePressedAt -- overheated: the click is spent
			return
		end
	elseif self.Mag <= 0 then
		self.BurstLeft = 0
		self._pressConsumed = firePressedAt -- a dry click must not fire after the reload
		if firePressedAt > self._emptyHandled then
			self._emptyHandled = firePressedAt
			self.Effects:PlayCue(self.Id, "Empty")
			self.Viewmodel:DryFire()
			if self.Reserve > 0 then
				task.delay(0.12, function()
					if self.State == "Ready" and self.Mag <= 0 then
						self:TryReload()
					end
				end)
			end
		end
		return
	end
	if now - self.NextShotAt > self.Interval then
		self.NextShotAt = now
	end
	if burst then
		-- one pull = Count rounds at RPM, then the burst cooldown
		if self.BurstLeft <= 0 then
			if now < self.NextShotAt then
				return
			end
			self.BurstLeft = burst.Count
			self._pressConsumed = firePressedAt
		end
		if now >= self.NextShotAt then
			self:_shoot(now)
			self.BurstLeft -= 1
			self.NextShotAt += self.Interval
			if self.BurstLeft <= 0 or self.Mag <= 0 then
				self.BurstLeft = 0
				self.NextShotAt = now + burst.Cooldown
			end
		end
		if self.Mag <= 0 then
			self._emptyHandled = firePressedAt
		end
		return
	end
	local shots = 0
	while self:_hasRound() and now >= self.NextShotAt and shots < 3 do
		self:_shoot(now)
		self._pressConsumed = firePressedAt
		self.NextShotAt += self.Interval
		shots += 1
		-- semi-auto: exactly one shot per click; auto: keep going only while held
		if not w.Automatic or not fireHeld then
			break
		end
	end
	if not w.Energy and self.Mag <= 0 then
		self._emptyHandled = firePressedAt -- next pull of the trigger clicks / auto-reloads
	end
end

function WeaponController:_updateADS(dt: number, menuOpen: boolean)
	local A = self.Weapon.ADS
	if not A then
		self.ADS = 0
		return
	end
	local m = self.Movement
	local want = (self.Input.AltHeld or self._devADS == true) and not menuOpen and not self.Player:GetAttribute("VisorBlackout") and not self.Player:GetAttribute("VantageHangingLocal") and not self.Player:GetAttribute("VantageVehicleLocal")
	if A.CancelOnSlide and m.Stance == "Slide" then
		want = false
	end
	if self.State ~= "Ready" then
		want = false -- no aiming while equipping / reloading / lowering
	end
	self.ADSWanted = want
	-- direction change: re-map the linear progress so the eased visual curve stays continuous
	-- (tapping aim mid-transition never jumps)
	if want ~= (self._adsIn == true) then
		local v = self:ADSAlpha()
		self._adsIn = want
		self.ADS = if want then 1 - (1 - v) ^ (1 / 3) else v ^ (1 / 2.4)
	end
	local rate = if want then 1 / A.InTime else 1 / A.OutTime
	local target = if want then 1 else 0
	if self.ADS < target then
		self.ADS = math.min(target, self.ADS + rate * dt)
	elseif self.ADS > target then
		self.ADS = math.max(target, self.ADS - rate * dt)
	end
end

-- ─── inspect (F) ─────────────────────────────────────────────────────────
-- Plays the weapon's Inspect clip on top of the normal grip pose. Any combat input (fire, aim,
-- reload) or state change cancels it at once with a short blend back to ready.
function WeaponController:_cancelInspect(notify: boolean?)
	if not self.Inspecting then
		return
	end
	self.Inspecting = false
	SkinInspects.Cancel() -- fade the inspect sounds
	if self.Animator:IsPlaying("Inspect") then
		self.Animator:Stop(0.1)
	end
	if notify ~= false then
		Remotes.WeaponAction:FireServer("Anim", "Stop")
	end
end

function WeaponController:_updateInspect(now: number, menuOpen: boolean)
	local input = self.Input
	if input.InspectPressedAt > (self._inspectHandled or -math.huge) then
		self._inspectHandled = input.InspectPressedAt
		-- VX-01 skins have their own inspect (SkinInspects); everything else uses the weapon clip
		local gun = self.Viewmodel and self.Viewmodel.Gun
		local skinClip = if gun then SkinInspects.For(gun:GetAttribute("Skin"), self.Id) else nil
		local clip = skinClip or WeaponClips.Get(self.Id, "Inspect")
		if clip and not menuOpen and not self.Inspecting and self.State == "Ready" and self.ADS < 0.05 and now - self.LastShotAt > 0.25 then
			local length = if skinClip then skinClip.Length else (self.Weapon.InspectTime or clip.Length)
			self.Inspecting = true
			self.InspectEndsAt = now + length
			self._skinInspect = skinClip
			self.Animator:Play("Inspect", length, skinClip)
			Remotes.WeaponAction:FireServer("Anim", "Inspect")
		end
	end
	if self.Inspecting then
		local cancel = input.FireHeld
			or input.FirePressedAt > self._pressConsumed
			or input.AltHeld
			or self._devADS == true
			or input.ReloadPressedAt > self._reloadHandled
			or self.State ~= "Ready"
		if cancel then
			self:_cancelInspect()
		elseif now >= self.InspectEndsAt then
			self.Inspecting = false
		end
	end
end

-- eased ADS amount for visuals / FOV / sensitivity (2026-11-14):
--   aiming in  = ease-out cubic: the gun lifts the instant you press, then settles softly
--   aiming out = p^2.4 (as p falls 1 -> 0): it leaves the eye at once and lands gently at the hip
function WeaponController:ADSAlpha(): number
	local a = math.clamp(self.ADS, 0, 1)
	if self._adsIn then
		return 1 - (1 - a) ^ 3
	end
	return a ^ 2.4
end

-- ─── per frame (RenderPriority.Camera + 2, called by the loadout) ─────────
function WeaponController:Step(dt: number, now: number, menuOpen: boolean)
	if not self.Active or self.State == "Gone" then
		return
	end
	if self.State == "Equipping" and now >= self.EquipDoneAt then
		self.State = "Ready"
		self:_publish()
	end
	if self.State ~= "Dead" and self.State ~= "Lowering" then
		self:_updateInspect(now, menuOpen)
		self:_updateFiring(now, menuOpen)
	end
	self:_updateADS(dt, menuOpen)
	if (self.Bloom or 0) > 0 and now - self.LastShotAt > (self.Weapon.Spread.BloomDelay or 0.09) then
		self.Bloom = math.max(0, self.Bloom - (self.Weapon.Spread.BloomRecover or 4.5) * dt)
	end

	if self.ShotIndex >= 5 and now - self.LastShotAt > 0.12 and not self._smoked then
		self._smoked = true
		self.Effects:BurstSmoke(self.Viewmodel.MuzzleAttachment)
	elseif now - self.LastShotAt <= 0.12 then
		self._smoked = false
	end
	-- rechamber (pump / bolt) shortly after each shot
	if self.RechamberAt > 0 and now >= self.RechamberAt then
		self.RechamberAt = 0
		local R = self.Weapon.Rechamber
		if self.State == "Ready" then
			if WeaponClips.Get(self.Id, R.Clip or "Rechamber") then
				self.Animator:Play(R.Clip or "Rechamber", R.Time)
			else
				task.delay(R.Time * 0.5, function()
					self:_onClipEvent(R.Event or "Bolt")
				end)
			end
		end
	end
	if self.State == "Reloading" and self.Weapon.ReloadMode == "Shell" then
		self:_stepShells(now)
	end
	if self.Weapon.Energy and self.Active then
		self:_showAmmo() -- heat drains continuously
	end

	local pose = self.Animator:Sample()
	local ads = self:ADSAlpha()
	-- hip-fire guns (ADS.Mode = "Zoom"): right-click only zooms; the gun, sight overlays and visor stay as at the hip
	if self.Weapon.ADS and self.Weapon.ADS.Mode == "Zoom" then
		ads = 0
	end
	-- full-screen scopes replace the gun once fully aimed
	if self.Weapon.ADS and self.Weapon.ADS.Scope then
		-- the real scope comes up centred on its axis; at full aim the HUD lens takes over exactly
		-- over the projected eyepiece and the gun is hidden (applied by the Loadout)
		self.Scoped = self.Active and ads > 0.985 and self.Viewmodel.LensA ~= nil
		-- same frame as the HUD lens (the Loadout re-applies it with the viewmodel setting)
		self.Viewmodel:SetHidden(self.ViewHidden == true or self.Scoped)
	end
	-- third-person ride under the dropship (VantageAircraftClient): no first-person gun / arms
	local thirdPerson = self.Player:GetAttribute("VantageThirdPerson") == true
	if thirdPerson or self._wasThirdPerson then
		self._wasThirdPerson = thirdPerson
		self.Viewmodel:SetHidden(thirdPerson or self.ViewHidden == true or self.Scoped == true)
	end
	local sc = self._skinInspect
	self.Viewmodel.InspectDrive = if sc and self.Inspecting and self.Animator:IsPlaying("Inspect") then SkinInspects.DriveAt(sc, self.Animator:Progress() * sc.Length) else nil
	local presenting = sc and self.Inspecting and self.Animator:IsPlaying("Inspect")
	SkinInspects.Present(self.Viewmodel, if presenting then sc else nil, if presenting then self.Animator:Progress() * sc.Length else 0)
	self.Viewmodel:Step(dt, { Movement = self.Movement, Pose = pose, Firing = now - self.LastShotAt < 0.16, ADS = ads, Hanging = self.Player:GetAttribute("VantageHangingLocal") == true, Busy = self.State ~= "Ready" or self.Inspecting == true })
	-- straight sight-window frame over the 3D holo window while fully aimed
	local R = self.Weapon.ADS and self.Weapon.ADS.Reticle
	self._adsVisual = ads

	if self.State == "Reloading" then
		if self.Weapon.ReloadMode == "Shell" then
			self.Hud:SetReload(self.Mag / self.Weapon.MagazineSize)
		else
			self.Hud:SetReload((now - self.ReloadStartedAt) / self.Weapon.ReloadTime)
		end
	end
	if self.ShotsFired ~= self._lastPublishedShots or self.State ~= self._lastPublishedState or math.abs(self.ADS - (self._lastADS or 0)) > 0.2 then
		self._lastPublishedShots = self.ShotsFired
		self._lastPublishedState = self.State
		self._lastADS = self.ADS
		self:_publish()
	end
end

-- after the Loadout has applied this frame's FOV: project the 3D optic for the HUD overlays
function WeaponController:PostCamera()
	if not self.Active or self.State == "Gone" then
		return
	end
	local A = self.Weapon.ADS
	local ads = self._adsVisual or 0
	local vm = self.Viewmodel
	VisorFeedADS.ADS = ads -- the visor hides its centre ring while aiming
	if self.Hud.StepOptics then
		self.Hud:StepOptics(ads, self.Weapon)
	end
	local SC = A and A.Scope
	if SC and self.Hud.SetScopeLens then
		self.Hud:SetScopeLens(if self.Scoped then vm.LensA else nil, vm.LensB, SC)
	end
	-- Forge sights (ADS.Sight): the reticle is projected along the gun's real sight axis and
	-- clipped to the optic's real window, so it behaves like a collimated holo / prism sight
	local SI = A and A.Sight
	if SI and self.Hud.SetHoloSight then
		local projected = SI.Kind == "Holo" or SI.Kind == "Lens"
		local alpha = math.clamp((ads - 0.45) / 0.4, 0, 1)
		self.Hud:SetHoloSight(if projected then vm.WindowA else nil, vm.WindowB, vm.SightAim, SI, alpha, vm.Mag or 1)
		return
	end
	-- holo sight: straight frame lining the real window opening (corners measured in Blender)
	local R = A and A.Reticle
	if R and R.Window and self.Hud.SetSightWindow then
		local on = ads > 0.92 and vm.WindowA ~= nil
		self.Hud:SetSightWindow(if on then vm.WindowA else nil, vm.WindowB, R.Window)
	end
end

-- ─── server messages ──────────────────────────────────────────────────────
function WeaponController:OnServerAmmo(mag: number, reserve: number, reason: string, _reloading: boolean?, lastSeq: number?)
	if self.Weapon.Energy then
		return -- no magazine: heat is predicted locally and enforced by the server
	end
	-- shots we fired that the server had not processed yet when it sent this
	if type(lastSeq) == "number" then
		mag = math.max(0, mag - math.max(0, self.Seq - lastSeq))
	end
	if reason == "ReloadDenied" and self.State == "Reloading" then
		self.Animator:Stop(0.12)
		self.State = "Ready"
		self.Hud:SetReload(nil)
	end
	if reason == "ReloadCancelled" and self.State == "Reloading" then
		self.Animator:Stop(0.14)
		self.State = "Ready"
		self.Hud:SetReload(nil)
	end
	if self.State == "Reloading" and self.Weapon.ReloadMode == "Shell" and reason ~= "ReloadDenied" then
		if reason == "Reloaded" then
			self._pendingAmmo = { mag, reserve } -- applied when the local shell loop ends
		end
		return
	end
	if self.State == "Reloading" and reason ~= "Reloaded" and reason ~= "ReloadDenied" then
		return -- keep the predicted reload; "Reloaded" will deliver the final numbers
	end
	if reason == "Reloaded" and self.State == "Reloading" and not self.MagInDone then
		return -- animation will refill at the MagIn marker; numbers already agree
	end
	self.Mag = mag
	self.Reserve = reserve
	self:_showAmmo()
	self:_publish()
end

function WeaponController:OnConfirm(info)
	self.HitsConfirmed += 1
	if info.Killed then
		self.Kills += 1
	end
	self:_publish()
end

function WeaponController:OnDied()
	self:_unscope()
	self.State = "Dead"
	self.ADS = 0
	self.Hud:SetReload(nil)
	self.Animator:Play("Unequip", self.Weapon.UnequipTime)
	task.delay(self.Weapon.UnequipTime, function()
		if self.State == "Dead" then
			self.Viewmodel:SetVisible(false)
		end
	end)
	self:_publish()
end

function WeaponController:Destroy()
	self.State = "Gone"
	self.Viewmodel:Destroy()
end

return WeaponController
