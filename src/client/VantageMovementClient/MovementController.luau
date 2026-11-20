--[[
	VANTAGE — MovementController (client, one instance per character life)

	Owns horizontal velocity itself (acceleration, deceleration, air control, slide
	friction) and drives the Humanoid with :Move(dir) + WalkSpeed = |velocity| each frame.
	The Humanoid still handles collision, slopes, steps and gravity.

	Runs at RenderPriority.Input + 1, i.e. right AFTER Roblox's ControlModule, so our
	Move / Jump writes win and the default "hold space to bounce" behaviour is removed.

	Stances: "Stand" | "Crouch" | "Slide"
	Events:  Landed(impactSpeed), Jumped(), StanceChanged(new, old)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Vantage.Movement.MovementConfig)

local HST = Enum.HumanoidStateType
-- In these states we hand control back to the default Humanoid behaviour.
local PASSTHROUGH_STATES = {
	[HST.Climbing] = true,
	[HST.Swimming] = true,
	[HST.Seated] = true,
	[HST.PlatformStanding] = true,
	[HST.Physics] = true,
	[HST.Dead] = true,
	[HST.Ragdoll] = true,
	[HST.FallingDown] = true,
	[HST.GettingUp] = true,
}

local JUMP_GROUND_LOCK = 0.1 -- ignore "still touching floor" for this long after a jump

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function moveTowards(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current
	local dist = delta.Magnitude
	if dist <= maxDelta or dist < 1e-6 then
		return target
	end
	return current + delta / dist * maxDelta
end

local function smoothing(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- [VANTAGE weapons integration] speed multiplier from the held weapon.
--   VantageSpeedMult       set by the SERVER (WeaponService) — e.g. 1.14 with the knife; the
--                          MovementValidator allows the same multiplier, so it cannot be forged.
--   VantageLocalSpeedMult  client-only slow-down (aiming down sights); can only lower speed.
local function weaponSpeedMultiplier(character: Model): number
	local server = character:GetAttribute("VantageSpeedMult")
	local localMult = character:GetAttribute("VantageLocalSpeedMult")
	local a = if type(server) == "number" then math.clamp(server, 0.5, 1.5) else 1
	local b = if type(localMult) == "number" then math.clamp(localMult, 0.3, 1) else 1
	-- 2026-11-18: Singularity's gravity well (EquipmentPerkServer): server-set, can only slow
	local c = 1
	local slowUntil = character:GetAttribute("PerkSlowUntil")
	if type(slowUntil) == "number" and slowUntil > Workspace:GetServerTimeNow() then
		local s = character:GetAttribute("PerkSlow")
		c = if type(s) == "number" then math.clamp(s, 0.2, 1) else 1
	end
	-- 2026-11-19: Singularity's phase (EquipmentPerkServer): a short server-set boost the validator allows too
	local perkUntil = character:GetAttribute("PerkSpeedUntil")
	if type(perkUntil) == "number" and perkUntil > Workspace:GetServerTimeNow() then
		local m = character:GetAttribute("PerkSpeedMult")
		c *= if type(m) == "number" then math.clamp(m, 1, 1.3) else 1
	end
	return a * b * c
end

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(character: Model, humanoid: Humanoid, root: BasePart, input, remote: RemoteEvent)
	local self = setmetatable({}, MovementController)
	self.Character = character
	self.Humanoid = humanoid
	self.Root = root
	self.Input = input
	self.Remote = remote
	self.IsR15 = humanoid.RigType == Enum.HumanoidRigType.R15

	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Config.JumpHeight
	humanoid.AutoJumpEnabled = false
	humanoid.WalkSpeed = Config.RunSpeed
	humanoid:SetStateEnabled(HST.FallingDown, false)
	humanoid:SetStateEnabled(HST.Ragdoll, false)

	self.StandHipHeight = humanoid.HipHeight
	local head = character:FindFirstChild("Head") :: BasePart?
	self.RootToHeadTop = if head then (head.Position.Y + head.Size.Y / 2) - root.Position.Y else 3

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = true
	self._overlap = overlap

	local now = os.clock()
	self.Velocity = Vector3.zero -- our authoritative horizontal velocity
	self.Stance = "Stand"
	self.Grounded = true
	self.LastGroundedAt = now
	self.AirborneSince = now
	self.LastJumpAt = -math.huge
	self.LastSlideEndAt = -math.huge
	self.SlideStartedAt = -math.huge
	self.SlideSpeed = 0
	self.SlideDir = Vector3.new(0, 0, -1)
	self.HeightDrop = 0
	self._airMinVy = 0
	self._jumpConsumedAt = input.JumpPressedAt
	self._crouchPressHandled = input.CrouchPressedAt
	self._slideArmed = false
	self._dashUntil = nil :: number?
	self._dashVel = Vector3.zero
	self._dashExit = Vector3.zero
	self._grapple = nil :: any -- { Point, Cfg, StartedAt, SlowSince, Track? } while a grapple cable is pulling
	self._hang = nil :: any -- { Provider, Cfg, Bob, BobVel, StartLen, StartedAt } while hanging under the dropship

	self._landed = Instance.new("BindableEvent")
	self._jumped = Instance.new("BindableEvent")
	self._stanceChanged = Instance.new("BindableEvent")
	self.Landed = self._landed.Event
	self.Jumped = self._jumped.Event
	self.StanceChanged = self._stanceChanged.Event

	MovementController.Current = self -- read by VantageAbilityClient (Phase Dash / High Jump)
	return self
end

-- ── Stance helpers ────────────────────────────────────────────────────────────────────

function MovementController:_setStance(newStance: string)
	local old = self.Stance
	if newStance == old then
		return
	end
	self.Stance = newStance
	if newStance == "Slide" then
		self.Remote:FireServer("Slide")
	else
		self.Remote:FireServer("Stance", newStance)
	end
	self._stanceChanged:Fire(newStance, old)
end

-- Is there room above the head to return to full standing height?
function MovementController:CanStand(): boolean
	if self.HeightDrop < 0.05 or not self.IsR15 then
		return true
	end
	local rootPos = self.Root.Position
	local currentTop = rootPos.Y + self.RootToHeadTop
	local standingTop = currentTop + self.HeightDrop + Config.StandClearancePadding
	local bottom = currentTop - 0.25
	local height = standingTop - bottom
	local cf = CFrame.new(rootPos.X, bottom + height / 2, rootPos.Z)
	local parts = Workspace:GetPartBoundsInBox(cf, Vector3.new(1.6, height, 1.6), self._overlap)
	return #parts == 0
end

function MovementController:_canSlide(now: number): boolean
	return self.Grounded
		and now - self.LastSlideEndAt >= Config.SlideCooldown
		and self.Velocity.Magnitude >= Config.SlideMinStartSpeed
end

function MovementController:_startSlide(now: number, wish: Vector3)
	local speed = self.Velocity.Magnitude
	local dir = self.Velocity.Unit
	if wish.Magnitude > 0.1 and wish.Unit:Dot(dir) > 0 then
		dir = wish.Unit -- snap to intended direction for a crisp, predictable slide
	end
	self.SlideDir = dir
	self.SlideSpeed = math.clamp(speed * Config.SlideStartBoost, speed, Config.SlideMaxSpeed)
	self.SlideStartedAt = now
	self.Velocity = dir * self.SlideSpeed
	self:_setStance("Slide")
end

function MovementController:_endSlide(now: number)
	if self.Stance ~= "Slide" then
		return
	end
	self.LastSlideEndAt = now
	if Config.CrouchToggle then
		self.Input:ClearCrouchToggle()
	end
	if self.Input:IsCrouchActive() or not self:CanStand() then
		self:_setStance("Crouch")
	else
		self:_setStance("Stand")
	end
end

-- Called when the server refuses a slide (cooldown / speed check failed).
function MovementController:ForceEndSlide()
	if self.Stance == "Slide" then
		local speed = math.min(self.Velocity.Magnitude, Config.RunSpeed)
		self.Velocity = if self.Velocity.Magnitude > 0 then self.Velocity.Unit * speed else Vector3.zero
		self:_endSlide(os.clock())
	end
end

function MovementController:_updateStance(now: number, wish: Vector3)
	local input = self.Input
	local pressEdge = input.CrouchPressedAt > self._crouchPressHandled
	if pressEdge then
		self._crouchPressHandled = input.CrouchPressedAt
	end
	local wantCrouch = input:IsCrouchActive()

	if self.Stance == "Slide" then
		return -- slide ends itself (time / speed / jump)
	end

	-- Crouch pressed mid-air arms a slide for the moment you land.
	if pressEdge and not self.Grounded then
		self._slideArmed = true
	end
	if not wantCrouch then
		self._slideArmed = false
	end

	if self.Grounded and wantCrouch and (pressEdge or self._slideArmed) then
		self._slideArmed = false
		if self:_canSlide(now) then
			self:_startSlide(now, wish)
			return
		end
	end

	if self.Stance == "Stand" and wantCrouch then
		self:_setStance("Crouch")
	elseif self.Stance == "Crouch" and not wantCrouch and self:CanStand() then
		self:_setStance("Stand")
	end
end

-- ── Jump ──────────────────────────────────────────────────────────────────────────

function MovementController:_updateJump(now: number)
	local input = self.Input
	local pressedAt = input.JumpPressedAt
	if not Config.RequireJumpRepress and input.JumpHeld then
		pressedAt = now
	end
	if pressedAt <= self._jumpConsumedAt then
		return
	end
	if now - pressedAt > Config.JumpBufferTime then
		return -- buffer expired
	end
	if now - self.LastJumpAt < Config.JumpCooldown then
		return
	end
	local coyote = not self.Grounded
		and (now - self.LastGroundedAt) <= Config.CoyoteTime
		and self.LastJumpAt < self.LastGroundedAt
	if not (self.Grounded or coyote) then
		return
	end
	self._jumpConsumedAt = pressedAt
	self:_doJump(now)
end

function MovementController:_doJump(now: number)
	if self.Stance == "Slide" then
		self:_endSlide(now) -- slide-jump keeps the slide's momentum
	end
	local jumpVelocity = math.sqrt(2 * Workspace.Gravity * Config.JumpHeight)
	self.Root.AssemblyLinearVelocity = Vector3.new(self.Velocity.X, jumpVelocity, self.Velocity.Z)
	self.Humanoid:ChangeState(HST.Jumping)
	self.LastJumpAt = now
	self.Grounded = false
	self.AirborneSince = now
	self._airMinVy = 0
	self._jumped:Fire()
end

-- ── Abilities (called by VantageAbilityClient; the server exempts the validator) ──

-- Phase Dash: fixed horizontal burst, then keep exitSpeed of momentum.
function MovementController:Dash(dir: Vector3, speed: number, duration: number, exitSpeed: number)
	if self.Stance == "Slide" then
		self:_endSlide(os.clock())
	end
	self._dashVel = dir * speed
	self._dashExit = dir * exitSpeed
	self._dashUntil = os.clock() + duration
end

-- High Jump: vertical launch, horizontal momentum kept.
function MovementController:Launch(upVelocity: number)
	local now = os.clock()
	if self.Stance == "Slide" then
		self:_endSlide(now)
	end
	-- the Humanoid's own jump impulse (JumpHeight) lands after ChangeState, so the launch
	-- velocity is set after it and re-applied on the next steps until it sticks
	self.Humanoid:ChangeState(HST.Jumping)
	self.Root.AssemblyLinearVelocity = Vector3.new(self.Velocity.X, upVelocity, self.Velocity.Z)
	self._launchVy = upVelocity
	self._launchUntil = now + 0.1
	self.LastJumpAt = now
	self.Grounded = false
	self.AirborneSince = now
	self._airMinVy = 0
	self._jumped:Fire()
end

-- Grapple: while a cable is attached the controller flies the character toward the hook instead
-- of walking it. cfg = AbilityConfig.Abilities.Grapple. The pull works on the REAL velocity each
-- frame (so walls and ledges stop you like anything else): acceleration along the cable, the
-- move keys bending the path, gravity cancelled, sideways speed bled off so you home in.
-- track (optional): function() -> (point, velocity) for an anchor that MOVES (the dropship's hooks);
-- the pull then works relative to the anchor's velocity, so it catches a moving target
function MovementController:GrappleStart(point: Vector3, cfg, track: (() -> (Vector3?, Vector3))?)
	local now = os.clock()
	if self.Stance == "Slide" then
		self:_endSlide(now)
	end
	self._dashUntil = nil
	self._grapple = { Point = point, Cfg = cfg, StartedAt = now, SlowSince = nil :: number?, Track = track, V0 = self.Root.AssemblyLinearVelocity }
	-- Lotus (cfg.Swing): a pendulum round any anchor above head height (2026-11-19: was 4 studs above the root,
	-- so many hooks silently pulled straight); lower anchors get the straight pull with Lotus's big fling
	if cfg.Swing and point.Y > self.Root.Position.Y + 2 then
		self._grapple.Swing = true
		local d0 = (point - self.Root.Position).Magnitude
		self._grapple.Len = math.max(cfg.MinLength or 14, d0)
		self._grapple.LenTarget = math.max(cfg.MinLength or 14, d0 * 0.65)
	end
	self._perch = nil
	-- off the ground: a small lift so the floor lets go, then free flight
	self.Humanoid:ChangeState(HST.Freefall)
	local v = self.Root.AssemblyLinearVelocity
	if self.Grounded then
		self.Root.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, 14), v.Z)
	end
	-- Kraken (cfg.Jolt): the claws bite with a violent yank along the cable
	if cfg.Jolt and not self._grapple.Swing then
		local to = point - self.Root.Position
		if to.Magnitude > 1e-3 then
			self.Root.AssemblyLinearVelocity += to.Unit * cfg.Jolt
		end
	end
	self.LastJumpAt = now
	self.Grounded = false
	self.AirborneSince = now
	self._airMinVy = 0
end

function MovementController:IsGrappling(): boolean
	return self._grapple ~= nil
end

-- distance to the hook, and whether the pull has been blocked for cfg.StuckTime
function MovementController:GrappleStatus(): (number, boolean)
	local g = self._grapple
	if not g then
		return 0, false
	end
	local stuck = g.SlowSince ~= nil and os.clock() - g.SlowSince >= g.Cfg.StuckTime
	return (g.Point - self.Root.Position).Magnitude, stuck
end

-- kind: "Arrive" (reached the hook: slowed and popped up onto the ledge) or anything else
-- (let go: momentum kept, capped so a release is a fling and not a launch)
-- low-gravity hang after a grapple: a VectorForce cancels part of gravity, fading over FloatTime.
-- Ends early on landing, on a new grapple, or when the character goes away.
function MovementController:_startFloat(c)
	local root = self.Root
	if not root or not c.FloatTime or c.FloatTime <= 0 then
		return
	end
	local att = root:FindFirstChild("VantageFloatAtt") or Instance.new("Attachment")
	att.Name = "VantageFloatAtt"
	att.Parent = root
	local vf = root:FindFirstChild("VantageFloat") or Instance.new("VectorForce")
	vf.Name = "VantageFloat"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = root
	local token = {}
	self._floatToken = token
	local t0 = os.clock()
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local t = os.clock() - t0
		if self._floatToken ~= token or t >= c.FloatTime or self._grapple ~= nil or not root.Parent
			or (self.Grounded and t > 0.2) then
			vf.Force = Vector3.zero
			conn:Disconnect()
			return
		end
		local k = 1 - (t / c.FloatTime) ^ 2
		vf.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * c.FloatLift * k, 0)
	end)
end

function MovementController:GrappleEnd(kind: string?)
	local g = self._grapple
	if not g then
		return
	end
	self._grapple = nil
	local c = g.Cfg
	if kind == "Cancel" then
		-- the server refused the shot: as if it never happened (no fling, no float)
		local v0 = g.V0 or Vector3.zero
		local h0 = flat(v0)
		if h0.Magnitude > 40 then
			h0 = h0.Unit * 40
		end
		self.Root.AssemblyLinearVelocity = Vector3.new(h0.X, math.min(v0.Y, self.Root.AssemblyLinearVelocity.Y), h0.Z)
		self.Velocity = h0
		return
	end
	local v = self.Root.AssemblyLinearVelocity
	local h = flat(v)
	if kind ~= "Arrive" and c.ReleaseBoost then
		v *= c.ReleaseBoost -- a release is a fling: keep (and slightly amplify) the cable's momentum
	end
	h = flat(v)
	local y = math.clamp(v.Y, -120, c.ReleaseMaxUp)
	if h.Magnitude > c.ReleaseMaxSpeed then
		h = h.Unit * c.ReleaseMaxSpeed
	end
	if kind == "Arrive" then
		h *= (c.ArriveKeep or 0.55)
		y = math.max(y, c.ArriveHop)
	end
	self.Root.AssemblyLinearVelocity = Vector3.new(h.X, y, h.Z)
	self.Velocity = h
	self:_startFloat(c)
	local now = os.clock()
	self.LastJumpAt = now
	self.AirborneSince = now
end

function MovementController:_grappleStep(dt: number, wish: Vector3, now: number)
	local g = self._grapple
	local c = g.Cfg
	local root = self.Root
	-- a moving anchor: follow it, and pull relative to its velocity
	local anchorVel = Vector3.zero
	if g.Track then
		local p, av = g.Track()
		if p then
			g.Point = p
			anchorVel = av
		end
	end
	local to = g.Point - root.Position
	local dist = to.Magnitude
	local dir = if dist > 1e-3 then to / dist else Vector3.yAxis
	if g.Swing then
		-- rope pendulum: gravity stays on, the rope (slowly reeled in) only stops you flying away from the
		-- anchor, the move keys pump the swing. Never "stuck"; jump / E / MaxTime let go with a fling.
		-- a fast reel to LenTarget (yanks you up into the arc), then a slow one
		if g.Len > g.LenTarget then
			g.Len = math.max(g.LenTarget, g.Len - 34 * dt)
		else
			g.Len = math.max(c.MinLength or 14, g.Len - (c.ReelSpeed or 7) * dt)
		end
		local v = root.AssemblyLinearVelocity
		v += wish * c.SteerAccel * 1.6 * dt
		if dist > g.Len then
			local away = v:Dot(-dir)
			if away > 0 then
				v += dir * away -- the rope never lets you move away from the anchor
			end
			local want = math.min(60, (dist - g.Len) * 7) -- and pulls you back to its length
			local closing = v:Dot(dir)
			if closing < want then
				v += dir * (want - closing)
			end
		end
		if v.Magnitude > c.MaxSpeed then
			v = v.Unit * c.MaxSpeed
		end
		root.AssemblyLinearVelocity = v
		self.Velocity = flat(v)
		local st = self.Humanoid:GetState()
		if st ~= HST.Freefall and st ~= HST.Jumping then
			self.Humanoid:ChangeState(HST.Freefall)
		end
		g.SlowSince = nil
		return
	end
	local v = root.AssemblyLinearVelocity - anchorVel
	v += (dir * c.PullAccel + wish * c.SteerAccel + Vector3.new(0, Workspace.Gravity, 0)) * dt
	local along = v:Dot(dir)
	local side = (v - dir * along) * math.exp(-c.SideDamp * dt)
	-- ease off as the hook comes up so you arrive instead of slamming into it
	local cap = math.min(c.MaxSpeed, (c.BrakeBase or 18) + dist * (c.BrakePerStud or 3.2))
	v = dir * math.clamp(along, -12, cap) + side
	if v.Magnitude > c.MaxSpeed then
		v = v.Unit * c.MaxSpeed
	end
	v += anchorVel
	root.AssemblyLinearVelocity = v
	self.Velocity = flat(v)
	v -= anchorVel -- the stuck test below is about closing on the anchor
	local state = self.Humanoid:GetState()
	if state ~= HST.Freefall and state ~= HST.Jumping then
		self.Humanoid:ChangeState(HST.Freefall) -- brushing a floor must not turn the pull into a walk
	end
	-- blocked? (a wall, a ledge underside): GrappleStatus reports it and the ability lets go
	if v.Magnitude < c.StuckSpeed and now - g.StartedAt > 0.25 then
		g.SlowSince = g.SlowSince or now
	else
		g.SlowSince = nil
	end
end

-- ── Perch (Mag-Anchor, 2026-11-18): held in place against the wall the hook bit ─────────────────────
-- The grapple ends and the controller holds the root at pos (a spring that also cancels gravity); you can
-- aim and shoot as normal. PerchEnd(push) lets go (push = a small hop off the wall).
function MovementController:PerchStart(pos: Vector3, normal: Vector3)
	if self.Stance == "Slide" then
		self:_endSlide(os.clock())
	end
	self._grapple = nil
	self._perch = { Pos = pos, Normal = normal, At = os.clock() }
	self.Velocity = Vector3.zero
	self.Root.AssemblyLinearVelocity = Vector3.zero
	self.Humanoid:ChangeState(HST.Freefall)
end

function MovementController:IsPerched(): boolean
	return self._perch ~= nil
end

function MovementController:PerchEnd(push: boolean?)
	local p = self._perch
	if not p then
		return
	end
	self._perch = nil
	local now = os.clock()
	self.LastJumpAt = now
	self.AirborneSince = now
	self.Grounded = false
	self._airMinVy = 0
	if push then
		local v = flat(p.Normal) * 24 + Vector3.new(0, 32, 0)
		self.Root.AssemblyLinearVelocity = v
		self.Velocity = flat(v)
	end
end

-- ── Hanging under the dropship (VantageAircraftClient / VantageAbilityClient) ──────────────────────
-- The character becomes the bob of a rope pendulum hung from a MOVING hook: gravity, an
-- inextensible rope, damping relative to the aircraft and a swing limit. It lags, swings into
-- banks and settles, instead of being glued under the hull. The Humanoid is put in Physics
-- state so it doesn't fight; the camera stays free (the body turns to face where you look).
-- provider() -> (hookPos, hookVel, aircraftCFrame) or nil when the aircraft is gone.
-- cfg = AircraftConfig.Hang
function MovementController:HangStart(provider: () -> (Vector3?, Vector3, CFrame?), cfg)
	local now = os.clock()
	if self.Stance == "Slide" then
		self:_endSlide(now)
	end
	self._grapple = nil
	self._dashUntil = nil
	local root = self.Root
	local hook, hookVel = provider()
	-- keep only part of the arrival speed as swing, so you swing in rather than whip round
	local v = root.AssemblyLinearVelocity
	if hook then
		v = hookVel + (v - hookVel) * (cfg.EntrySwing or 0.4)
	end
	-- cancel gravity between frames: the body is placed every frame, so without this the physics
	-- step would drop it a little in between (visible at low frame rates, wrong replicated speed)
	local att = Instance.new("Attachment")
	att.Name = "VantageHangAttach"
	att.Parent = root
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Name = "VantageHangLift"
	antiGravity.Attachment0 = att
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity, 0)
	antiGravity.Parent = root
	self._hang = {
		Provider = provider, Cfg = cfg, StartedAt = now, Fwd = root.CFrame.LookVector,
		Bob = root.Position, BobVel = v, Lift = antiGravity, LiftAttach = att,
		StartLen = if hook then math.max((root.Position - hook).Magnitude, cfg.Length) else cfg.Length,
	}
	self.Humanoid:ChangeState(HST.Physics)
	self.Grounded = false
	self.AirborneSince = now
	self._airMinVy = 0
end

function MovementController:IsHanging(): boolean
	return self._hang ~= nil
end

-- letting go: keep `inherit` of the aircraft's velocity plus the swing, capped, small hop
-- release = AircraftConfig.Release
function MovementController:HangEnd(release)
	local h = self._hang
	if not h then
		return
	end
	self._hang = nil
	h.Lift:Destroy()
	h.LiftAttach:Destroy()
	local _, hookVel = h.Provider()
	local swing = h.BobVel - hookVel
	local v = hookVel * release.Inherit + swing * 0.5
	local flatV = flat(v)
	if flatV.Magnitude > release.MaxHorizontal then
		flatV = flatV.Unit * release.MaxHorizontal
	end
	v = Vector3.new(flatV.X, math.clamp(v.Y, -40, 30) + release.Up, flatV.Z)
	local root = self.Root
	-- stand the body back up (keep the facing), then fall with the carried speed
	local look = root.CFrame.LookVector
	local yawLook = Vector3.new(look.X, 0, look.Z)
	if yawLook.Magnitude < 1e-3 then
		yawLook = Vector3.new(0, 0, -1)
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + yawLook.Unit)
	root.AssemblyAngularVelocity = Vector3.zero
	self.Humanoid:ChangeState(HST.Freefall)
	root.AssemblyLinearVelocity = v
	self.Velocity = flatV
	local now = os.clock()
	self.LastJumpAt = now
	self.AirborneSince = now
	self.Grounded = false
	self._airMinVy = 0
	self._jumpConsumedAt = self.Input.JumpPressedAt -- the Space that let go is not also a jump
end

function MovementController:_hangStep(dt: number, camera: Camera)
	local h = self._hang
	local c = h.Cfg
	local hook, hookVel, acf = h.Provider()
	if not hook or not acf then
		self:HangEnd({ Inherit = 0.6, MaxHorizontal = 46, Up = 0 })
		return
	end
	dt = math.min(dt, 1 / 20)
	local now = os.clock()
	-- rope length eases from the arrival distance down to the hang length
	local k = math.clamp((now - h.StartedAt) / c.EnterTime, 0, 1)
	k = k * k * (3 - 2 * k)
	local len = h.StartLen + (c.Length - h.StartLen) * k
	-- integrate: gravity, then damping of the swing relative to the hook
	local v = h.BobVel + Vector3.new(0, -Workspace.Gravity, 0) * dt
	v = hookVel + (v - hookVel) * math.exp(-c.Damping * dt)
	local p = h.Bob + v * dt
	-- the rope: bob on a sphere around the hook, no velocity along the rope (relative to the hook)
	local d = p - hook
	local n = if d.Magnitude > 1e-3 then d.Unit else -acf.UpVector
	-- swing limit, measured from the aircraft's down axis (the hull is above you)
	local down = -acf.UpVector
	local maxA = math.rad(c.MaxAngle)
	local ang = math.acos(math.clamp(n:Dot(down), -1, 1))
	if ang > maxA then
		local axis = down:Cross(n)
		if axis.Magnitude > 1e-4 then
			n = CFrame.fromAxisAngle(axis.Unit, maxA):VectorToWorldSpace(down)
		end
	end
	p = hook + n * len
	local rel = v - hookVel
	rel -= n * rel:Dot(n)
	v = hookVel + rel
	h.Bob, h.BobVel = p, v
	-- the body hangs along the rope and turns, unhurried, toward where the camera looks
	local up = -n
	local look = camera.CFrame.LookVector
	local want = look - up * look:Dot(up)
	if want.Magnitude < 1e-3 then
		want = acf.LookVector - up * acf.LookVector:Dot(up)
	end
	local fwd = h.Fwd:Lerp(want.Unit, 1 - math.exp(-3.2 * dt))
	fwd -= up * fwd:Dot(up)
	if fwd.Magnitude < 1e-3 then
		fwd = want
	end
	fwd = fwd.Unit
	h.Fwd = fwd
	local root = self.Root
	root.CFrame = CFrame.lookAt(p, p + fwd, up)
	root.AssemblyLinearVelocity = v
	root.AssemblyAngularVelocity = Vector3.zero
	self.Velocity = flat(v)
	if self.Humanoid:GetState() ~= HST.Physics then
		self.Humanoid:ChangeState(HST.Physics)
	end
end

-- ── Velocity integration ──────────────────────────────────────────────────────────────

function MovementController:_groundStep(dt: number, wish: Vector3)
	local maxSpeed = (if self.Stance == "Crouch" then Config.CrouchSpeed else Config.RunSpeed) * weaponSpeedMultiplier(self.Character)
	local target = wish * maxSpeed
	local vel = self.Velocity
	local speed = vel.Magnitude
	local targetSpeed = target.Magnitude

	if targetSpeed < 0.01 then
		local decel = if speed > maxSpeed then Config.OverspeedDeceleration + Config.GroundDeceleration * 0.5 else Config.GroundDeceleration
		vel = moveTowards(vel, Vector3.zero, decel * dt)
	elseif speed > targetSpeed + 0.5 and vel.Unit:Dot(target.Unit) > 0.5 then
		-- carrying extra momentum (after slide / hop): bleed it gradually, steer freely
		local newSpeed = math.max(targetSpeed, speed - Config.OverspeedDeceleration * dt)
		local dir = vel.Unit:Lerp(target.Unit, smoothing(12, dt))
		vel = if dir.Magnitude > 1e-3 then dir.Unit * newSpeed else target
	else
		local sharpTurn = speed > 1 and vel.Unit:Dot(target.Unit) < 0.7
		local accel = if sharpTurn then Config.TurnAcceleration else Config.GroundAcceleration
		vel = moveTowards(vel, target, accel * dt)
	end
	self.Velocity = vel
end

function MovementController:_airStep(dt: number, wish: Vector3)
	local vel = self.Velocity
	local speed = vel.Magnitude
	local newVel = vel + wish * Config.AirAcceleration * dt
	local cap = Config.AirMaxWishSpeed * weaponSpeedMultiplier(self.Character)
	if speed > cap then
		-- keep momentum, never gain speed from air strafing
		cap = math.max(cap, speed - Config.AirOverspeedDrag * dt)
	end
	if newVel.Magnitude > cap then
		newVel = newVel.Unit * cap
	end
	self.Velocity = newVel
end

function MovementController:_slideStep(dt: number, wish: Vector3, now: number)
	local t = now - self.SlideStartedAt
	local decel = Config.SlideFriction + Config.SlideFrictionRamp * t
	self.SlideSpeed = math.max(0, self.SlideSpeed - decel * dt)

	if wish.Magnitude > 0.1 then
		local cur = self.SlideDir
		local tgt = wish.Unit
		if cur:Dot(tgt) > -0.3 then -- steer, but you can't reverse a slide
			local angle = math.atan2(cur:Cross(tgt).Y, cur:Dot(tgt))
			local maxStep = Config.SlideSteerRate * dt
			local step = math.clamp(angle, -maxStep, maxStep)
			self.SlideDir = CFrame.Angles(0, step, 0):VectorToWorldSpace(cur)
		end
	end
	self.Velocity = self.SlideDir * self.SlideSpeed

	local airTooLong = not self.Grounded and (now - self.AirborneSince) > Config.SlideAirGraceTime
	if t >= Config.SlideDuration or self.SlideSpeed <= Config.SlideEndSpeed or airTooLong then
		self:_endSlide(now)
	end
end

-- If a wall / obstacle is stopping us, adopt the real velocity so momentum isn't "stored".
function MovementController:_syncWithPhysics(actualHorizontal: Vector3, now: number)
	local speed = self.Velocity.Magnitude
	if speed < 4 or now - self.LastJumpAt < 0.05 or now - self.SlideStartedAt < 0.08 then
		return
	end
	local along = actualHorizontal:Dot(self.Velocity / speed)
	if along < speed * 0.5 then
		self.Velocity = actualHorizontal
		if self.Stance == "Slide" then
			self.SlideSpeed = actualHorizontal.Magnitude
			if self.SlideSpeed > 0.1 then
				self.SlideDir = actualHorizontal.Unit
			end
		end
	end
end

-- ── Height (crouch / slide) ───────────────────────────────────────────────────────────────

function MovementController:_updateHeight(dt: number)
	local target = 0
	if self.Stance == "Slide" then
		target = Config.SlideHeightDrop
	elseif self.Stance == "Crouch" then
		target = Config.CrouchHeightDrop
	end
	local drop = self.HeightDrop
	if math.abs(target - drop) < 0.002 then
		if drop == target then
			return
		end
		drop = target
	else
		drop += (target - drop) * smoothing(Config.HeightTransitionSpeed, dt)
	end
	self.HeightDrop = drop
	if self.IsR15 then
		-- Lowering HipHeight physically lowers the root, torso and head: smaller hitbox, lower camera.
		self.Humanoid.HipHeight = math.max(0.2, self.StandHipHeight - drop)
	else
		-- R6 has no usable HipHeight: camera-only crouch (see report: known limitation).
		self.Humanoid.CameraOffset = Vector3.new(0, -drop, 0)
	end
end

-- ── Main step ─────────────────────────────────────────────────────────────────────

function MovementController:Step(dt: number, camera: Camera)
	local humanoid = self.Humanoid
	-- 2026-11-20: a Signature (Valkyrie / Sleipnir / Bifröst) is moving the character this frame
	if humanoid.Parent and humanoid.Parent:GetAttribute("VantageSigMove") then
		return
	end
	if humanoid.Health <= 0 then
		return
	end
	if self._hang then
		self:_hangStep(dt, camera)
		humanoid.Jump = false
		humanoid:Move(Vector3.zero, false)
		return
	end
	if self._perch then
		local root = self.Root
		root.AssemblyLinearVelocity = (self._perch.Pos - root.Position) * 12
		self.Velocity = Vector3.zero
		humanoid.Jump = false
		humanoid:Move(Vector3.zero, false)
		local st = humanoid:GetState()
		if st ~= HST.Freefall and st ~= HST.Jumping then
			humanoid:ChangeState(HST.Freefall)
		end
		self:_updateHeight(dt)
		return
	end

	local now = os.clock()
	local rootVelocity = self.Root.AssemblyLinearVelocity
	local actualHorizontal = flat(rootVelocity)

	if PASSTHROUGH_STATES[humanoid:GetState()] then
		humanoid.WalkSpeed = Config.RunSpeed
		self.Velocity = actualHorizontal
		return
	end

	-- Ground detection + landing
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air and (now - self.LastJumpAt) > JUMP_GROUND_LOCK
	if grounded then
		if not self.Grounded then
			local impact = -self._airMinVy
			if impact >= Config.HardLandingVelocity and Config.LandingSpeedPenalty > 0 then
				self.Velocity *= (1 - Config.LandingSpeedPenalty)
			end
			self.Grounded = true
			self._landed:Fire(impact)
		end
		self.LastGroundedAt = now
	else
		if self.Grounded then
			self.AirborneSince = now
			self._airMinVy = 0
		end
		self._airMinVy = math.min(self._airMinVy, rootVelocity.Y)
	end
	self.Grounded = grounded

	if not self._grapple then
		self:_syncWithPhysics(actualHorizontal, now)
	end

	local wish = self.Input:GetWishDirection(camera)
	self:_updateStance(now, wish)
	self:_updateJump(now)

	if self._launchUntil then
		if now < self._launchUntil then
			local v = self.Root.AssemblyLinearVelocity
			if v.Y < self._launchVy * 0.7 then -- overwritten by the jump impulse (gravity alone can't drop it this far in 0.1s)
				self.Root.AssemblyLinearVelocity = Vector3.new(v.X, self._launchVy, v.Z)
			end
		else
			self._launchUntil = nil
		end
	end

	if self._dashUntil and now >= self._dashUntil then
		self._dashUntil = nil
		self.Velocity = self._dashExit
	end

	if self._grapple then
		self:_grappleStep(dt, wish, now)
	elseif self._dashUntil then
		self.Velocity = self._dashVel
		self.Root.AssemblyLinearVelocity = Vector3.new(self._dashVel.X, 0, self._dashVel.Z)
	elseif self.Stance == "Slide" then
		self:_slideStep(dt, wish, now)
	elseif self.Grounded then
		self:_groundStep(dt, wish)
	else
		self:_airStep(dt, wish)
	end

	-- Drive the Humanoid. Overrides the ControlModule's Move/Jump from earlier this frame.
	humanoid.Jump = false
	local speed = self.Velocity.Magnitude
	if speed > 0.05 then
		humanoid.WalkSpeed = speed
		humanoid:Move(self.Velocity / speed, false)
	else
		self.Velocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
	end

	self:_updateHeight(dt)
end

function MovementController:Destroy()
	if self._hang then
		self._hang.Lift:Destroy()
		self._hang.LiftAttach:Destroy()
		self._hang = nil
	end
	if MovementController.Current == self then
		MovementController.Current = nil
	end
	self._landed:Destroy()
	self._jumped:Destroy()
	self._stanceChanged:Destroy()
end

return MovementController
