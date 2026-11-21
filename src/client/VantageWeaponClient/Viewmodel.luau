--[[
	VANTAGE — Viewmodel (client, any gun)
	Attachment convention on the asset's PrimaryPart (Root): Handle (right hand), Support (left
	hand), Muzzle, ADSPoint (sight / reticle), EjectPoint (shell port); optional Magazine model
	with a MagGrip attachment on its PrimaryPart.
	First-person rifle + the player's own arms (ViewmodelArms), a client-only model under the
	Camera (never replicated, no collision, no queries, no shadows).

	Every frame (RenderPriority.Camera + 2, after the camera, movement effects and recoil):
	  ADS (2026-11-14 rebuild) is SIGHT-ANCHORED:
	    sight    = (camera * Offset * sightFromGrip):Lerp(camera * (0, 0, -SightDistance * mag), ads)
	               * transition swing (roll / pitch / yaw / dip, a 4a(1-a) bump: zero at hip and aimed)
	    layers   = stance * fire stance * sprint * movement * bob * sway * air * land * wall * kick * settle * clip
	    grip     = sight * pivot(layers) * sightFromGrip^-1
	  The layer pivot slides from the grip (hip, identical to the old pose) to the SIGHT (aimed), so
	  sway / kick / breathing / strafe tilt rotate the gun around the sight and the sight never
	  leaves the screen centre. mag = Viewmodel.Magnification: the gun moves out as the FOV zooms,
	  so it keeps its on-screen size (a fixed "viewmodel FOV") while the world magnifies.
	  hands    = gun grips (Handle / Support <-> magazine MagGrip during reloads)
	  arms     = shared two-bone IK from camera-space shoulders to the hands
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Skins = require(ReplicatedStorage.Vantage.Weapons.Skins) -- cosmetic
local SkinKits = require(ReplicatedStorage.Vantage.Weapons.SkinKits) -- cosmetic (animated skin pieces)
local Workspace = game:GetService("Workspace")

local MoveConfig = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
local ViewmodelArms = require(script.Parent.ViewmodelArms)
-- stylised reloads with the real magazines / moving parts (2026-11-14)
local ReloadChoreo = require(ReplicatedStorage.Vantage.Weapons.ReloadChoreo)
-- exosuit visor: both hands leave the gun to pull the visor down / push it up (VantageVisorClient)
local VisorFeed = require(ReplicatedStorage.Vantage.UI.VisorFeed)
-- grenade throw (2026-11-11): the left hand leaves the handguard, throws, comes back (GrenadeClient)
local GrenadeFolder = ReplicatedStorage.Vantage:WaitForChild("Grenade")
local GrenadeFeed = require(GrenadeFolder:WaitForChild("GrenadeFeed"))
-- grapple (2026-11-11): the left arm punches out at the hook, holds while it flies and pulls, comes back
local GrappleFeed = require(ReplicatedStorage.Vantage:WaitForChild("Abilities"):WaitForChild("GrappleFeed"))

local V = Vector3.new
local rad = math.rad

-- shared gait (gun bob, camera bob and footsteps agree on the same footfalls) -- 2026-11-17
local GaitFeed = require(ReplicatedStorage.Vantage.Movement:WaitForChild("GaitFeed"))
local GAIT = {
	Amp = 1.35, -- x the weapon's BobAmount
	SprintBoost = 0.55, -- extra swing at full sprint
	StepPitch = 0.55, -- degrees the muzzle dips as each foot lands
	Roll = 0.8, -- degrees of roll across a stride
	StepDip = 0.2, -- landing-spring kick per footfall (weight)
}
-- Hypershot-style hip hold (2026-11-17): the gun sits lower and nearer the centre line with the
-- barrel close to parallel to the view. Applied on top of each weapon's own pose; a weapon can
-- override any field with Viewmodel.Hold = { ... }. Studio: LocalPlayer attributes VMHold_<Field>
-- override live (bump VMHold_Rev to re-apply).
local HOLD = { X = 0.07, Y = -0.12, Z = -0.1, Pitch = -2.5, Yaw = 0, Roll = -1.5, Converge = 40 }
local IS_STUDIO = game:GetService("RunService"):IsStudio()
local function holdFor(weapon)
	local h = table.clone(HOLD)
	local over = weapon.Viewmodel and weapon.Viewmodel.Hold
	if over then
		for k, v in over do
			h[k] = v
		end
	end
	if IS_STUDIO then
		local lp = game:GetService("Players").LocalPlayer
		for k in HOLD do
			local v = lp and lp:GetAttribute("VMHold_" .. k)
			if type(v) == "number" then
				h[k] = v
			end
		end
	end
	return h
end

-- camera-space shoulder anchors (hip -> ADS) and elbow pole directions
-- (below / behind the screen edges so only the forearms enter the view). The left (support)
-- shoulder sits under the gun so that arm rises from beneath it and stays mostly hidden.
local SHOULDER = {
	Right = { Hip = V(0.72, -1.08, -0.12), ADS = V(0.42, -1.05, -0.1) },
	Left = { Hip = V(0.12, -1.35, -0.45), ADS = V(0.02, -1.3, -0.4) },
}
local POLE = { Right = V(0.65, -1, 0.3), Left = V(-0.15, -1, 0.35) }

-- The camera-space shoulder anchors are virtual (off-screen). If a grip is beyond the arm's
-- reach, slide the shoulder toward the hand along its original direction so the hand lands
-- exactly on the grip instead of stopping short (long guns / far handguards).
local REACH_USE = 0.93
-- The forearm continues from the hand with a natural wrist bend: elbow = wrist + (hand's wrist
-- axis + a per-arm camera-space bias) * forearm length; the shoulder sits one upper-arm length
-- from the elbow toward its nominal (off-screen) anchor. Returns shoulder + elbow pole so the IK
-- reproduces exactly that elbow (no contorted wrists, no stretching).
local BEND = { Right = V(0.2, -0.85, 0.1), Left = V(0, -0.7, 0.25) }
local function armTarget(arm, handCF: CFrame, nominal: Vector3, bias: Vector3, cam: CFrame)
	local wrist = (handCF * CFrame.new(arm.HandWrist)).Position
	local dir = handCF.UpVector + cam:VectorToWorldSpace(bias)
	if dir.Magnitude < 1e-3 then
		dir = handCF.UpVector
	end
	local elbow = wrist + dir.Unit * arm.L2
	local toNom = nominal - elbow
	local shoulder = elbow + (if toNom.Magnitude > 1e-3 then toNom.Unit else dir.Unit) * arm.L1 * 0.98
	return shoulder, elbow - (shoulder + wrist) / 2
end

local function reachableShoulder(arm, shoulder: Vector3, handCF: CFrame): Vector3
	if not arm then
		return shoulder
	end
	local wrist = (handCF * CFrame.new(arm.HandWrist)).Position
	local d = wrist - shoulder
	local maxD = arm.Reach * REACH_USE
	if d.Magnitude > maxD then
		return wrist - d.Unit * maxD
	end
	return shoulder
end

-- Sprint carry: after a moment of running forward without shooting / aiming / reloading, the gun
-- comes off the shoulder line into a carry (lowered, muzzle up and across the body) and swings
-- with the stride. Any combat action brings it straight back. HEFT scales how far and how
-- slowly a weapon moves (a config can override it with a top-level Heft field).
local CARRY = CFrame.new(-0.05, -0.1, 0.05) * CFrame.Angles(math.rad(-7), math.rad(16), math.rad(11)) -- 2026-11-17: low-ready, muzzle down (was raised across the body)
local CARRY_DELAY = 0.4 -- seconds of running before the gun lowers
local CARRY_REST = 0.55 -- seconds after the last shot / aim / reload before it lowers again
local HEFT = { Spectre = 0.8, Vanguard = 1, Sentinel = 1.05, Arc = 1.1, Breacher = 1.2, Longshot = 1.35, Riptide = 0.9, Bulwark = 1.45, Verdict = 0.85, Quill = 1.2, Helix = 1.15, Havoc = 1.3 }

-- Left-hand grenade throw. Keys are the support-hand GRIP in camera space: P position, R extra
-- rotation (degrees, camera axes) applied on top of the grip's own orientation on the gun.
-- Key 0 is the live handguard grip. Grenade in the palm from ShowFrom until GrenadeFeed.Release.
local THROW = {
	{ T = 0.13, P = V(-0.42, -0.85, -0.75), R = V(-25, 15, 30) },  -- down to the belt, take the grenade
	{ T = 0.29, P = V(-0.62, -0.1, -1.05), R = V(40, 20, 40) },    -- wind-up: raised to the left, grenade up
	{ T = 0.38, P = V(-0.34, -0.06, -1.6), R = V(-5, 0, 10) },     -- snap forward: release
	{ T = 0.53, P = V(0.02, -0.7, -1.25), R = V(-55, 0, -12) },    -- follow-through, across and down
}
local THROW_IN, THROW_OUT_AT = 0.08, 0.53
local THROW_SHOW_FROM = 0.1
local THROW_SHOULDER = V(-0.55, 0.3, 0.3) -- the left shoulder anchor moves out to the real shoulder while throwing
local HELD_OFFSET = CFrame.new(0, 0, -0.2) * CFrame.Angles(math.rad(-90), 0, 0) -- grip -Z = toward the fingertips
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Left-arm grapple (Halo-style). The launcher sits on the left gauntlet, so the arm itself aims:
-- the hand leaves the handguard and the forearm lines up with the hook point (live: it follows
-- the target while the hook flies and while the cable pulls you in), elbow nearly straight; a
-- small recoil at the shot, a tug when the hook bites, then a smooth retraction to the handguard.
-- Solved by the same two-bone IK as everything else (shoulder anchor moves out to the real
-- shoulder), so the upper arm, elbow and wrist all follow — no rotated static pose.
local GRAPPLE = {
	ReachIn = 0.13, -- seconds to full extension
	Overshoot = 1.15, -- ease-out-back strength (a few % past full extension, then settles)
	Retract = 0.34, -- seconds from the arm out back to the handguard grip
	Wrist = V(-0.28, -0.27, -1.62), -- camera space: where the wrist sits at full reach (lower left of view)
	Follow = 0.32, -- the wrist also slides this far toward the target's place on the screen
	Straight = 0.95, -- shoulder this share of the arm's length straight back along the aim (1 = locked)
	ShoulderBias = V(-0.22, -0.42, 0), -- camera space: shoulder a touch down / out (the elbow keeps some life)
	Pole = V(-0.7, -1, 0.15), -- camera space: the elbow points down and out
	Shoulder = V(-0.5, 0.36, 0.32), -- camera-space shift of the nominal left shoulder anchor while reaching
	Roll = -70, -- degrees about the aim axis: the palm turns down / out, gauntlet top up
	Cone = 55, -- degrees: the arm never points further than this from the view direction
	AimRate = 18, -- how fast the arm re-aims when the target moves across the view
	Kick = 0.07, -- studs the launcher's recoil pushes the hand back just after the shot
	Jolt = 0.05, -- studs the cable going taut tugs the hand forward at the bite
	Gun = { P = V(0.05, -0.1, 0.08), R = V(-6, -5, -12) }, -- gun held one-handed: dips and cants away
}
local function gv(name: string): any
	local T = GrappleFeed.Tune
	local v = T and T[name]
	if v ~= nil then
		return v
	end
	return GRAPPLE[name]
end
local function reachCurve(x: number): number
	x = math.clamp(x, 0, 1)
	local s = GRAPPLE.Overshoot
	local u = x - 1
	return 1 + (s + 1) * u * u * u + s * u * u
end

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- semi-implicit spring on Vector3
local Spring = {}
Spring.__index = Spring
function Spring.new(k, d)
	return setmetatable({ P = Vector3.zero, Vel = Vector3.zero, K = k, D = d }, Spring)
end
function Spring:Step(dt)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		local a = -self.K * self.P - self.D * self.Vel
		self.Vel += a * h
		self.P += self.Vel * h
	end
	return self.P
end

local Viewmodel = {}
Viewmodel.__index = Viewmodel
Viewmodel.Spring = Spring

-- ADS magnification (tan-space, so the zoom feels even): 1 at the hip, tan(Base/2)/tan(ADS.FOV/2)
-- fully aimed. The Loadout derives the camera FOV from the same value.
function Viewmodel.Magnification(weapon, ads: number): number
	local A = weapon and weapon.ADS
	if not A or not A.FOV then
		return 1
	end
	local base = MoveConfig.BaseFOV or 80
	local M = math.tan(math.rad(base / 2)) / math.tan(math.rad(A.FOV / 2))
	return 1 + (M - 1) * math.clamp(ads, 0, 1)
end

-- per-weapon ADS feel (config ADS.Transition / ADS.Settle override these)
local DEFAULT_TRANSITION = { Roll = -6, Pitch = -2.5, Yaw = 1.5, Dip = 0.012 }
local DEFAULT_SETTLE = { Pitch = -0.9, Yaw = 0.25, Roll = 0.7 }

-- Hip pose from OffsetPosition / Converge / Roll: rotate the gun about its grip so the bore line
-- (muzzle, barrel along the body's -Z) passes through the crosshair Converge studs ahead. The muzzle
-- position depends on the rotation, so iterate (damped; the plain fixed point oscillates).
function Viewmodel.SolveOffset(cfg, muzzle: Vector3, handle: Vector3): CFrame
	local P = cfg.OffsetPosition or Vector3.new(0.44, -0.86, -0.9)
	local T = Vector3.new(0, 0, -(cfg.Converge or 5))
	local roll = CFrame.Angles(0, 0, math.rad(cfg.Roll or 0))
	local Mg = muzzle - handle
	local R = roll
	for _ = 1, 40 do
		local m = P + R:VectorToWorldSpace(Mg)
		R = R:Lerp(CFrame.lookAt(Vector3.zero, T - m) * roll, 0.5)
	end
	return CFrame.new(P) * R.Rotation
end

function Viewmodel.new(weapon, asset: Model, camera: Camera, character: Model)
	local self = setmetatable({}, Viewmodel)
	self.Weapon = weapon
	self.Cfg = weapon.Viewmodel
	self.Camera = camera

	local root = Instance.new("Model")
	root.Name = "VantageViewmodel"
	self.Root = root

	-- gun
	local gun = asset:Clone()
	Skins.Apply(gun, weapon.Id, Skins.ForPlayer(game:GetService("Players").LocalPlayer, weapon.Id))
	gun.Name = "Gun"
	local S = self.Cfg.Scale or 1
	self.Scale = S
	if S ~= 1 then
		gun:ScaleTo(S)
	end
	local body = gun.PrimaryPart :: BasePart
	self.Body = body
	local bodyInv = body.CFrame:Inverse()
	self.GunParts, self.GunOffsets = {}, {}
	self.MagParts, self.MagOffsets = {}, {}
	self.AllParts = {}
	self.Moving = {} -- split guns: Charge / Bolt / Slide / Pump, moved by reloads (ReloadChoreo)
	local mag = gun:FindFirstChild("Magazine")
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			table.insert(self.AllParts, d)
			local moving = d:GetAttribute("MovingPart")
			if moving then
				-- several parts may share one MovingPart (Blender guns split by colour role):
				-- the MovingMain part's rest drives hands / pivots, the rest ride along as Extra
				local entry = { Part = d, Rest = bodyInv * d.CFrame, Extra = {} }
				local cur = self.Moving[moving]
				if not cur then
					self.Moving[moving] = entry
				elseif d:GetAttribute("MovingMain") then
					entry.Extra = cur.Extra
					table.insert(entry.Extra, { Part = cur.Part, Rest = cur.Rest })
					self.Moving[moving] = entry
				else
					table.insert(cur.Extra, entry)
				end
			elseif mag and d:IsDescendantOf(mag) then
				table.insert(self.MagParts, d)
				table.insert(self.MagOffsets, bodyInv * d.CFrame)
			else
				table.insert(self.GunParts, d)
				table.insert(self.GunOffsets, bodyInv * d.CFrame)
			end
		end
	end
	self.MagRest = mag and (bodyInv * mag.PrimaryPart.CFrame) or CFrame.identity
	-- real magazine: a second copy is the fresh mag the hand brings in while the old one is thrown
	self.MagInParts = {}
	if mag and mag:GetAttribute("Real") then
		local mi = mag:Clone()
		mi.Name = "MagazineIn"
		mi.Parent = gun
		for _, d in mi:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
				table.insert(self.MagInParts, d)
				table.insert(self.AllParts, d)
			end
		end
	end
	local magGrip = mag and mag.PrimaryPart:FindFirstChild("MagGrip")
	self.MagGripLocal = magGrip and magGrip.CFrame or CFrame.identity
	local function att(name)
		local a = body:FindFirstChild(name)
		return a and a.CFrame or CFrame.identity
	end
	-- single-mesh guns (Tripo) have no Magazine model: the support hand uses the Root "Magazine"
	-- attachment and follows the clip's Mag track (pull the old mag / seat the new one)
	if not magGrip and body:FindFirstChild("Magazine") then
		self.MagGripLocal = att("Magazine")
	end
	self.GripRight = att("Handle")
	self.GripLeft = att("Support")
	-- bolt-action: the right hand works the bolt handle (right side of the receiver), same wrist angle
	local bolt = body:FindFirstChild("Bolt")
	self.GripBolt = bolt and (CFrame.new(bolt.Position + Vector3.new(0.12 * S, 0.06 * S, 0)) * self.GripRight.Rotation) or nil
	self.SightLocal = att("ADSPoint")
	self.MuzzleAttachment = body:FindFirstChild("Muzzle") :: Attachment
	self.EjectAttachment = body:FindFirstChild("EjectPoint") :: Attachment
	self.GripPivot = CFrame.new(-self.GripRight.Position)
	self.Offset = self.Cfg.Offset or Viewmodel.SolveOffset(self.Cfg, self.MuzzleAttachment and self.MuzzleAttachment.Position or Vector3.new(0, 0, -2), self.GripRight.Position)
	if weapon.ADS and weapon.ADS.Mode == "Zoom" then
		-- hip-fire pose (2026-11-14): same grip position, barrel held almost straight ahead
		local pos = (self.Cfg.Offset and self.Cfg.Offset.Position) or self.Cfg.OffsetPosition
		self.Offset = Viewmodel.SolveOffset({ OffsetPosition = pos, Converge = self.Cfg.HipConverge or 18, Roll = self.Cfg.HipRoll or -1.5 },
			self.MuzzleAttachment and self.MuzzleAttachment.Position or Vector3.new(0, 0, -2), self.GripRight.Position)
	end
	self.BaseOffset = self.Offset
	self:_applyHold()
	-- ADS: grip pose that puts the reticle exactly on the camera axis at SightDistance
	local ads = weapon.ADS
	self.ADSOffset = CFrame.new(0, 0, -(ads and ads.SightDistance or 1.2)) * CFrame.new(self.GripRight.Position - self.SightLocal.Position)
	-- sight-anchored ADS: the sight point in grip space (gun axes, already at viewmodel scale)
	self.SightFromGrip = self.SightLocal.Position - self.GripRight.Position
	self.Settle = Spring.new(190, 19)
	self.Mag = 1
	gun.Parent = root
	self.Gun = gun
	self.GunScale = gun:GetScale()

	-- the grenade in the left hand during a throw (client-only copy of the real model)
	self.HeldParts, self.HeldOffsets = {}, {}
	local gt = GrenadeFolder:FindFirstChild("FragModel")
	if gt then
		local held = gt:Clone()
		held.Name = "HeldGrenade"
		held:ScaleTo(held:GetScale() * 0.8) -- palm-sized next to the glove
		local hroot = held.PrimaryPart :: BasePart
		local hinv = hroot.CFrame:Inverse()
		for _, d in held:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
				table.insert(self.HeldParts, d)
				table.insert(self.HeldOffsets, hinv * d.CFrame)
				table.insert(self.AllParts, d)
			end
		end
		for _, d in held:GetDescendants() do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
		held:PivotTo(CFrame.new(0, -10000, 0)) -- parked until a throw puts it in the hand
		held.Parent = root
	end

	-- arms: the player's own avatar arms at the shared proportion
	local armScale = S / (weapon.ThirdPerson and weapon.ThirdPerson.Scale or S)
	self.Arms = ViewmodelArms.new(character, armScale, root)

	-- state
	self.Kick = Spring.new(self.Cfg.KickStiffness, self.Cfg.KickDamping)
	self.KickRot = Spring.new(self.Cfg.KickRotStiffness or self.Cfg.KickStiffness * 0.8, self.Cfg.KickRotDamping or self.Cfg.KickDamping)
	self.Land = Spring.new(120, 14)
	self.FireW = 0
	self.Strafe = 0
	self.Inertia = Vector3.zero
	self.LastVel = Vector3.zero
	self.Sway = Vector2.zero
	self.LastCam = camera.CFrame
	self.BobPhase = 0
	self.BobWeight = 0
	self.Air = 0
	self.CrouchW = 0
	self.SlideW = 0
	self.Wall = 0
	self.ADS = 0
	self.Heft = math.clamp(weapon.Heft or HEFT[weapon.Id] or 1, 0.6, 1.6)
	self.SprintW = 0
	self.RunTime = 0
	self.LastBusyAt = -math.huge
	self.WasGrounded = true
	self.Visible = false
	self.Hidden = false

	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	return self
end

-- re-solve the hip pose with the shared hold (HOLD + weapon.Viewmodel.Hold + Studio overrides)
function Viewmodel:_applyHold()
	local h = holdFor(self.Weapon)
	local cfg = self.Cfg
	local base = (cfg.Offset and cfg.Offset.Position) or cfg.OffsetPosition or V(0.44, -0.86, -0.9)
	local muzzle = self.MuzzleAttachment and self.MuzzleAttachment.Position or V(0, 0, -2)
	self.Offset = Viewmodel.SolveOffset({ OffsetPosition = base + V(h.X, h.Y, h.Z), Converge = h.Converge, Roll = h.Roll }, muzzle, self.GripRight.Position)
		* CFrame.Angles(rad(h.Pitch), rad(h.Yaw), 0)
end

function Viewmodel:SetVisible(on: boolean)
	self.Visible = on
	self.Root.Parent = if on then self.Camera else nil
end

-- settings: "Show viewmodel" off keeps effects (muzzle position) but renders nothing
function Viewmodel:SetHidden(hidden: boolean)
	if self.Hidden == hidden then
		return
	end
	self.Hidden = hidden
	for _, p in self.AllParts do
		p.LocalTransparencyModifier = if hidden then 1 else 0
	end
	-- hidden (full-screen scope, viewmodel off): skin particles, lights and outlines go too, or they ghost
	-- through the scope picture
	for _, d in self.Gun:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Highlight") or d:IsA("Beam") then
			if hidden then
				if d.Enabled then
					d:SetAttribute("VmHid", true)
					d.Enabled = false
				end
			elseif d:GetAttribute("VmHid") then
				d:SetAttribute("VmHid", nil)
				d.Enabled = true
			end
		end
	end
	self._adsK = nil -- re-apply the aim fade on the next step
	self.Arms:SetHidden(hidden)
end

function Viewmodel:SetIgnore(list)
	self._rayParams.FilterDescendantsInstances = list
end

-- Deterministic kick that mirrors this shot's recoil-pattern step (up / right, degrees).
function Viewmodel:FireKick(up: number?, right: number?, shotIndex: number?)
	local c = self.Cfg
	local m = 1 - (1 - (self.Weapon.ADS and self.Weapon.ADS.KickMultiplier or 1)) * self.ADS
	local f = math.clamp((up or 0.45) / 0.45, 0.35, 1.3) * m
	self.Kick.Vel += V(0, c.KickRise * 18 * f, c.KickBack * 30 * (0.7 + 0.3 * f)) * self.Scale
	local roll = c.KickRoll * (if (shotIndex or 1) % 2 == 0 then 1 else -1) * m
	self.KickRot.Vel += V(c.KickPitch * 30 * f, -(right or 0) * c.KickYaw * 30 * m, roll * 30)
end

function Viewmodel:DryFire()
	self.KickRot.Vel += V(-12, 0, 0)
	self.Kick.Vel += V(0, 0, 0.35 * self.Scale)
end

function Viewmodel:LandImpulse(impact: number)
	if impact < 12 then
		return
	end
	local s = math.clamp((impact - 12) / (MoveConfig.HardLandingVelocity - 12), 0.2, 1)
	self.Land.Vel += V(0, -self.Cfg.LandDip * s * 14, 0)
end

function Viewmodel:MuzzlePosition(): Vector3
	return self.MuzzleAttachment.WorldPosition
end

--[[ ctx: { Movement, Pose, Firing, ADS (0..1) } ]]
function Viewmodel:Step(dt: number, ctx)
	if not self.Visible then
		return
	end
	if IS_STUDIO then
		local rev = game:GetService("Players").LocalPlayer:GetAttribute("VMHold_Rev")
		if rev ~= self._holdRev then
			self._holdRev = rev
			self:_applyHold()
		end
	end
	local c = self.Cfg
	local cam = self.Camera.CFrame
	local m = ctx.Movement
	local now = os.clock()
	local ads = ctx.ADS or 0
	self.ADS = ads
	local A = self.Weapon.ADS or {}
	local swayMul = 1 - (1 - (A.SwayMultiplier or 1)) * ads
	local bobMul = 1 - (1 - (A.BobMultiplier or 1)) * ads

	-- sway from look delta (gun lags slightly behind fast turns)
	local rel = self.LastCam:ToObjectSpace(cam)
	self.LastCam = cam
	local rx, ry = rel:ToEulerAnglesYXZ()
	local target = Vector2.new(
		math.clamp(math.deg(ry) / math.max(dt, 1e-3) * 0.02 * c.SwayAmount, -c.SwayMax, c.SwayMax),
		math.clamp(math.deg(rx) / math.max(dt, 1e-3) * 0.02 * c.SwayAmount, -c.SwayMax, c.SwayMax)
	)
	local firing = ctx.Firing == true
	self.FireW += ((if firing then 1 else 0) - self.FireW) * expAlpha(if firing then c.FireStanceIn else c.FireStanceOut, dt)
	local fireCF = CFrame.identity:Lerp(c.FireStance or CFrame.identity, self.FireW * (1 - ads))
	target *= (1 - (1 - (c.FireSwayFactor or 1)) * self.FireW) * swayMul
	self.Sway = self.Sway:Lerp(target, expAlpha(10, dt))
	local swayCF = CFrame.Angles(rad(self.Sway.Y * 0.6), rad(self.Sway.X * 0.6), rad(self.Sway.X * 0.4))
		* CFrame.new(-self.Sway.X * 0.004, -self.Sway.Y * 0.004, 0)

	-- movement response: roll into strafes, lag slightly against acceleration
	local vel = m.Velocity
	local localVel = cam:VectorToObjectSpace(vel)
	self.Strafe += (math.clamp(localVel.X / MoveConfig.RunSpeed, -1.2, 1.2) - self.Strafe) * expAlpha(8, dt)
	local accel = (vel - self.LastVel) / math.max(dt, 1 / 240)
	self.LastVel = vel
	local heft = self.Heft
	local la = cam:VectorToObjectSpace(accel) * -(c.Inertia or 0) * heft
	if la.Magnitude > 0.06 then
		la = la.Unit * 0.06
	end
	self.Inertia = self.Inertia:Lerp(V(la.X, 0, la.Z) * swayMul, expAlpha(9, dt))
	-- strafing: the gun trails the move (shifts and yaws against it) as well as rolling into it
	local moveCF = CFrame.new(self.Inertia.X * (1 - 0.75 * ads) - self.Strafe * 0.018 * swayMul, 0, self.Inertia.Z * 0.6)
		* CFrame.Angles(0, rad(self.Strafe * 1.2 * swayMul), rad(-self.Strafe * (c.StrafeTilt or 0) * swayMul))

	-- run bob + idle breathing
	local speedFrac = math.clamp(m.Speed / MoveConfig.RunSpeed, 0, 1.4)
	local bobTarget = if m.Grounded and m.Stance ~= "Slide" and m.Speed > 1 then math.min(speedFrac, 1) else 0
	self.BobWeight += (bobTarget - self.BobWeight) * expAlpha(10, dt)
	self.BobPhase = (self.BobPhase + dt * c.BobFrequency * math.pi * 2 * math.max(speedFrac, 0.35)) % (math.pi * 2)
	local bw = self.BobWeight * bobMul
	local BA = c.BobAmount * GAIT.Amp
	-- footfall-synced gait (2026-11-17): footfalls at phase 0 / pi are the LOW point with a hard
	-- bottom (the weight lands); the gun floats up through mid-stance; sprinting swings harder
	local ph = self.BobPhase
	local sprintK = 1 + GAIT.SprintBoost * math.clamp((m.Speed - MoveConfig.RunSpeed * 0.85) / (MoveConfig.RunSpeed * 0.35), 0, 1)
	local gA = BA * bw * sprintK
	local s1 = math.sin(ph)
	local lift = math.abs(s1) -- 0 at a footfall, 1 mid-stance
	local breathe = math.sin(now * 1.6) * 0.006 * bobMul
	local idleX = math.sin(now * 0.8) * 0.004 * bobMul * (1 - math.min(bw, 1))
	local bob = CFrame.new(s1 * gA * 0.9 + idleX, (lift - 0.6) * gA * 1.1 + breathe, 0)
		* CFrame.Angles(rad(math.sin(now * 1.6) * 0.3 * bobMul - (1 - lift) * GAIT.StepPitch * bw * sprintK), rad(-s1 * 0.6 * bw), rad(s1 * GAIT.Roll * bw * sprintK))
	-- footfall events: the phase crossed 0 or pi while the gait is live
	local half = math.floor(ph / math.pi)
	if self._lastHalf ~= nil and half ~= self._lastHalf and self.BobWeight > 0.35 and m.Grounded then
		self.Land.Vel += V(0, -GAIT.StepDip * self.BobWeight * sprintK * (1 - ads * 0.85), 0)
		GaitFeed.StepCount = (GaitFeed.StepCount or 0) + 1
		GaitFeed.StepAt = now
		GaitFeed.StepSpeed = m.Speed
		GaitFeed.StepFoot = half % 2
	end
	self._lastHalf = half
	GaitFeed.Phase, GaitFeed.Weight, GaitFeed.Sprint, GaitFeed.At = ph, self.BobWeight, sprintK, now

	-- airborne: gun follows vertical motion
	local airTarget = if m.Grounded then 0 else math.clamp(-m.VerticalSpeed / 45, -1, 1)
	self.Air += (airTarget - self.Air) * expAlpha(9, dt)
	local airCF = CFrame.new(0, self.Air * c.AirLift * bobMul, 0) * CFrame.Angles(rad(self.Air * 3 * bobMul), 0, 0)

	-- jumping: the gun stays behind for a moment as the body goes up
	if self.WasGrounded and not m.Grounded and m.VerticalSpeed > 8 then
		self.Land.Vel += V(0, -c.LandDip * 4.5 * heft, 0)
	end
	self.WasGrounded = m.Grounded

	-- landing spring
	local land = self.Land:Step(dt)
	local landCF = CFrame.new(0, land.Y * (1 - ads * 0.9), 0) * CFrame.Angles(rad(land.Y * 25 * (1 - ads * 0.6)), 0, 0)

	-- stance
	self.CrouchW += ((if m.Stance == "Crouch" then 1 else 0) - self.CrouchW) * expAlpha(10, dt)
	self.SlideW += ((if m.Stance == "Slide" then 1 else 0) - self.SlideW) * expAlpha(10, dt)
	local stanceCF = CFrame.identity:Lerp(c.CrouchOffset, self.CrouchW * (1 - ads)) * CFrame.identity:Lerp(c.SlideOffset, self.SlideW * (1 - ads))

	-- wall avoidance: pull the gun back / down instead of clipping through geometry
	local reach = 2.4
	local hit = Workspace:Raycast(cam.Position, cam.LookVector * reach, self._rayParams)
	local wallTarget = if hit then math.clamp((reach - hit.Distance) / 1.6, 0, 1) else 0
	self.Wall += (wallTarget - self.Wall) * expAlpha(12, dt)
	local wallCF = CFrame.new(0.04 * self.Wall, -self.Wall * 0.22, self.Wall * c.WallPushback) * CFrame.Angles(rad(-self.Wall * 35), rad(self.Wall * 18), rad(-self.Wall * 10))

	-- sprint carry (see CARRY): lowered and across the body while running, swinging with the
	-- stride (the same phase as the run bob, so it follows real movement, not a timer)
	local VHn = VisorFeed.Hands
	-- grenade throw: time into it and the blend weight (0 = hand on the gun, 1 = throwing)
	local throwT, throwW = nil, 0
	if GrenadeFeed.Start then
		throwT = if GrenadeFeed.HoldAt then GrenadeFeed.HoldAt else now - GrenadeFeed.Start
		if throwT >= GrenadeFeed.Length then
			throwT = nil
			if not GrenadeFeed.HoldAt then
				GrenadeFeed.Start = nil
			end
		else
			throwW = if throwT < THROW_IN then smooth(throwT / THROW_IN)
				elseif throwT > THROW_OUT_AT then 1 - smooth((throwT - THROW_OUT_AT) / (GrenadeFeed.Length - THROW_OUT_AT))
				else 1
			self.LastBusyAt = now
		end
	end
	-- grapple: weight of the reaching arm (can briefly pass 1: the reach overshoots a touch)
	local GF = GrappleFeed
	local gW, gT, gHeld = 0, 0, false
	if GF.FiredAt > 0 then
		gT = if GF.HoldAt then GF.HoldAt else now - GF.FiredAt
		local at = GF.FiredAt + gT
		if GF.EndAt == nil or at < GF.EndAt then
			gHeld = true
			gW = reachCurve(gT / gv("ReachIn"))
		else
			local wEnd = math.min(1, reachCurve((GF.EndAt - GF.FiredAt) / gv("ReachIn")))
			local r = (at - GF.EndAt) / gv("Retract")
			if r < 1 then
				gW = wEnd * (1 - smooth(r))
			end
		end
		if gW > 0 then
			self.LastBusyAt = now
		end
	end
	if not gHeld and gW <= 0 then
		self.GrappleAimC = nil
	end
	if firing or ads > 0.05 or ctx.Busy or self.Wall > 0.15 or (VHn and (VHn.W or 0) > 0) then
		self.LastBusyAt = now
	end
	local running = m.Grounded and m.Stance == "Stand" and m.Speed > MoveConfig.RunSpeed * 0.82 and -localVel.Z > m.Speed * 0.55
	self.RunTime = if running then self.RunTime + dt else 0
	local sinceBusy = now - self.LastBusyAt
	-- hanging under the dropship: the gun goes to the same lowered carry (it cannot fire)
	local carryOn = ctx.Hanging == true or (running and self.RunTime > CARRY_DELAY and sinceBusy > CARRY_REST)
	local carryRate = if carryOn then 7 / math.sqrt(heft) elseif sinceBusy < 0.12 then 22 else 9 / math.sqrt(heft)
	self.SprintW += ((if carryOn then 1 else 0) - self.SprintW) * expAlpha(carryRate, dt)
	local sw = self.SprintW * (1 - ads)
	local se = sw * sw * (3 - 2 * sw)
	local sp = self.BobPhase + math.pi / 2 -- the carry swing keeps its footfall alignment
	local sprintCF = CFrame.identity:Lerp(CARRY, se)
		* CFrame.new(math.sin(sp) * 0.05 * heft * se, (math.cos(sp * 2) * 0.022 - 0.01) * heft * se, 0)
		* CFrame.Angles(rad(math.cos(sp * 2) * 1.6 * heft * se), rad(math.sin(sp) * 3.2 * heft * se), rad(math.sin(sp) * 2.6 * heft * se))

	-- firing kick
	local kp = self.Kick:Step(dt)
	local kr = self.KickRot:Step(dt)
	-- aimed: vertical kick travel would lift the sight off the centre (the rotation pivots on it)
	local kickCF = CFrame.new(0, kp.Y * (1 - 0.85 * ads), kp.Z) * CFrame.Angles(rad(kr.X), rad(kr.Y), rad(kr.Z))

	local pose = ctx.Pose
	-- ── sight-anchored ADS pose (see header) ──
	local mag = Viewmodel.Magnification(self.Weapon, ads)
	self.Mag = mag
	local sfg = self.SightFromGrip
	local D = (A.SightDistance or 0.4) * (if A.CompensateZoom == false then 1 else mag)
	local sightCF = (self.Offset * CFrame.new(sfg)):Lerp(CFrame.new(0, 0, -D), ads)
	local TR = A.Transition or DEFAULT_TRANSITION
	local bump = 4 * ads * (1 - ads)
	if bump > 1e-3 then
		sightCF *= CFrame.new(0, -(TR.Dip or 0) * bump, 0) * CFrame.Angles(rad((TR.Pitch or 0) * bump), rad((TR.Yaw or 0) * bump), rad((TR.Roll or 0) * bump))
	end
	-- arrival settle: a small damped rock about the sight once fully aimed (reticle stays centred)
	if ads >= 0.985 and not self._adsSettled then
		self._adsSettled = true
		local st = A.Settle or DEFAULT_SETTLE
		self.Settle.Vel += V(st.Pitch or 0, st.Yaw or 0, st.Roll or 0) * 30
	elseif ads < 0.6 then
		self._adsSettled = false
	end
	local se = self.Settle:Step(dt)
	local settleCF = CFrame.Angles(rad(se.X), rad(se.Y), rad(se.Z))
	local layers = stanceCF * fireCF * sprintCF * moveCF * bob * swayCF * airCF * landCF * wallCF * kickCF * settleCF * pose.Gun
	local pivot = sfg * -(1 - ads) -- grip at the hip (old pose exactly), the sight when aimed
	local grip = cam * sightCF * CFrame.new(pivot) * layers * CFrame.new(-pivot) * CFrame.new(-sfg)
	-- visor hands: the gun dips out of view while both hands work the visor
	local VH = VisorFeed.Hands
	local vw = if VH then math.clamp(VH.W or 0, 0, 1) else 0
	if vw > 0 then
		local e = vw * vw * (3 - 2 * vw)
		grip = grip * CFrame.new(0.06 * e, -0.85 * e, 0.3 * e) * CFrame.Angles(rad(-38 * e), rad(-14 * e), rad(22 * e))
	end
	-- grenade throw: held one-handed, the gun drops a little and cants away from the throwing arm
	if throwW > 0 then
		local e = throwW
		grip = grip * CFrame.new(0.06 * e, -0.13 * e, 0.1 * e) * CFrame.Angles(rad(-9 * e), rad(-7 * e), rad(-16 * e))
	end
	-- grapple: the same one-handed dip while the left arm is out
	if gW > 0 then
		local e = math.min(gW, 1)
		local P, R = GRAPPLE.Gun.P, GRAPPLE.Gun.R
		grip = grip * CFrame.new(P * e) * CFrame.Angles(rad(R.X * e), rad(R.Y * e), rad(R.Z * e))
	end
	local gunCF = grip * self.GripPivot
	-- inspect flight (SkinInspects "Fly" track): the gun leaves the hands and spins about its own centre;
	-- the hands keep following the un-flown grip (handCF)
	local handCF = gunCF
	local fly = pose.Tracks and pose.Tracks.Fly
	if fly then
		if pose.FlyPivot then
			self._flyPivot = pose.FlyPivot
		end
		local pv = CFrame.new((self._flyPivot or Vector3.zero) * (self.GunScale or 1))
		gunCF = handCF * pv * fly * pv:Inverse()
	end
	self.GunCF = gunCF
	-- choreographed reload: real mags, moving parts and both hands come from ReloadChoreo
	local CH = if pose.Choreo then ReloadChoreo.Solve(self, pose.Choreo.Clip, pose.Choreo.T, cam, gunCF) else nil
	self.ChoreoOut = CH

	-- scoped skins (2026-11-15): pieces flagged ADSFade (SkinKits adsFade) fade out as you aim in, and the
	-- kit outline switches off while aimed, so nothing stands in the sight picture
	local adsK = math.clamp((ads - 0.15) / 0.35, 0, 1)
	if adsK ~= self._adsK then
		self._adsK = adsK
		local hasFade = false
		for _, p in self.GunParts do
			if p:GetAttribute("ADSFade") then
				hasFade = true
				p.LocalTransparencyModifier = if self.Hidden then 1 else adsK
			end
		end
		-- 2026-11-20: only scoped skins (ADSFade pieces) drop their outline when aimed; every other skin keeps its glow
		for _, h in self.Gun:GetDescendants() do
			if h:IsA("Highlight") then
				h.Enabled = not self.Hidden and (not hasFade or adsK < 0.5)
			end
		end
	end

	-- move gun + magazine
	local parts, cfs = {}, {}
	local animT = os.clock()
	-- skin-piece drive (SkinInspects): inspect curves speed up / hold / swing the kit pieces, smoothed
	local SD = self._skinDrive
	if not SD then
		SD = { SpinRate = 1, SwayRate = 1, FlapRate = 1, SwayAmp = 1, FlapAmp = 1, HoldW = 0, HoldA = 0, SpinT = 0, SwayT = 0, FlapT = 0 }
		self._skinDrive = SD
	end
	do
		local tgt = self.InspectDrive
		local al = 1 - math.exp(-30 * dt)
		for _, key in { "SpinRate", "SwayRate", "FlapRate", "SwayAmp", "FlapAmp", "HoldW", "HoldA" } do
			local goal = if tgt then tgt[key] elseif key == "HoldW" or key == "HoldA" then 0 else 1
			SD[key] += (goal - SD[key]) * al
		end
		SD.SpinT += (SD.SpinRate - 1) * dt
		SD.SwayT += (SD.SwayRate - 1) * dt
		SD.FlapT += (SD.FlapRate - 1) * dt
	end
	for i, p in self.GunParts do
		table.insert(parts, p)
		if p:GetAttribute("AnimKind") then -- skin pieces that flap / spin (cosmetic)
			table.insert(cfs, gunCF * self.GunOffsets[i] * SkinKits.AnimOffset(p, animT, SD))
		else
			table.insert(cfs, gunCF * self.GunOffsets[i])
		end
	end
	local magCF = gunCF * self.MagRest * pose.Mag
	local magRestInv = self.MagRest:Inverse()
	local parked = cam * CFrame.new(0, -50, 0)
	for i, p in self.MagParts do
		table.insert(parts, p)
		if CH then
			table.insert(cfs, if CH.MagOut then CH.MagOut * magRestInv * self.MagOffsets[i] elseif CH.MagOutVisible then magCF * magRestInv * self.MagOffsets[i] else parked)
		elseif pose.MagHidden then
			table.insert(cfs, parked) -- out of view while "swapping"
		else
			table.insert(cfs, magCF * magRestInv * self.MagOffsets[i])
		end
	end
	for i, p in self.MagInParts do
		table.insert(parts, p)
		table.insert(cfs, if CH and CH.MagIn then CH.MagIn * magRestInv * self.MagOffsets[i] else parked)
	end
	for name, info in self.Moving do
		local motion = CH and CH.Parts[name]
		if not motion then
			-- outside a choreo the pump follows the shotgun's own pump track (support-hand offset)
			motion = if name == "Pump" then CFrame.new(pose.Left.Position) else CFrame.identity
		end
		table.insert(parts, info.Part)
		table.insert(cfs, gunCF * motion * info.Rest)
		for _, x in info.Extra or {} do
			table.insert(parts, x.Part)
			table.insert(cfs, gunCF * motion * x.Rest)
		end
	end

	-- hands on the grips, arms solved from camera-space shoulders
	local arms = self.Arms
	if arms:IsValid() then
		local rightGrip = self.GripRight
		if self.GripBolt and pose.RightOnBolt > 0 then
			rightGrip = rightGrip:Lerp(pose.Right * self.GripBolt, pose.RightOnBolt)
		end
		local rightHand = arms:HandFromGrip("Right", handCF * rightGrip)
		local leftGun = arms:HandFromGrip("Left", handCF * pose.Left * self.GripLeft)
		local leftMag = arms:HandFromGrip("Left", magCF * self.MagGripLocal)
		local leftHand = leftGun:Lerp(leftMag, pose.LeftOnMag)
		if CH then
			leftHand = CH.Left or leftHand
			rightHand = CH.Right or rightHand
		end
		if vw > 0 then
			-- hands up in front of the face: palms forward, fingers up (h 0 = below view, 1 = above the top edge)
			local h = math.clamp(VH.H or 0, 0, 1)
			local y = -0.95 + 1.75 * h
			local e = vw * vw * (3 - 2 * vw)
			-- fists raised in front of the visor, fingers curled toward the face (gripping its edge);
			-- the hand's up axis points back down the forearm, so ~145° about camera X drops the forearms
			local T = VisorFeed.Tune or {}
			local function target(sx: number): CFrame
				return cam * CFrame.new(sx * (T.X or 0.52), y, T.Z or -1.7) * CFrame.Angles(rad(T.RX or 145), rad(sx * (T.RY or 0)), rad(-sx * (T.RZ or 14)))
			end
			rightHand = rightHand:Lerp(target(1), e)
			leftHand = leftHand:Lerp(target(-1), e)
		end
		-- grenade throw: the left hand follows THROW (grip keys in camera space, from the live handguard grip)
		if throwT and throwW > 0 then
			local g0 = cam:ToObjectSpace(gunCF * pose.Left * self.GripLeft)
			local function key(i: number): CFrame
				if i == 0 then
					return g0
				end
				local k = THROW[i]
				local tune = GrenadeFeed.Tune
				local P = tune and tune["P" .. i] or k.P
				local R = tune and tune["R" .. i] or k.R
				return CFrame.new(P) * CFrame.Angles(rad(R.X), rad(R.Y), rad(R.Z)) * g0.Rotation
			end
			local target = key(#THROW)
			local prevT = 0
			for i, k in THROW do
				if throwT <= k.T then
					target = key(i - 1):Lerp(key(i), smooth((throwT - prevT) / (k.T - prevT)))
					break
				end
				prevT = k.T
			end
			leftHand = leftHand:Lerp(arms:HandFromGrip("Left", cam * target), throwW)
		end
		-- grapple: the left arm reaches out, the gauntlet (launcher) pointed at the hook point
		local gWrist, gAim = nil, nil
		if gW > 0 and arms.Left then
			local A = arms.Left
			local aimC = self.GrappleAimC
			local baseC = gv("Wrist") + (if aimC then V(aimC.X, aimC.Y, 0) * gv("Follow") else Vector3.zero)
			local baseW = cam * baseC
			if gHeld then
				local P = (GF.Track and GF.Track()) or GF.Target
				if P then
					local d = cam:VectorToObjectSpace(P - baseW)
					if d.Magnitude > 1e-3 then
						d = d.Unit
						-- looking away from the hook (free camera while pulled): the arm stays in a cone
						-- in front of you instead of twisting off the screen
						local fwd = V(0, 0, -1)
						local cone = rad(gv("Cone"))
						if math.acos(math.clamp(d:Dot(fwd), -1, 1)) > cone then
							local ax = fwd:Cross(d)
							ax = if ax.Magnitude > 1e-4 then ax.Unit else V(1, 0, 0)
							d = CFrame.fromAxisAngle(ax, cone):VectorToWorldSpace(fwd)
						end
						aimC = if aimC then aimC:Lerp(d, expAlpha(GRAPPLE.AimRate, dt)).Unit else d
					end
				end
				self.GrappleAimC = aimC
			end
			local aim = cam:VectorToWorldSpace(aimC or V(0, 0, -1))
			-- forearm along the aim: the hand's up axis points back toward the elbow
			local up, want = leftHand.UpVector, -aim
			local ax = up:Cross(want)
			local turn = if ax.Magnitude > 1e-4 then CFrame.fromAxisAngle(ax.Unit, math.acos(math.clamp(up:Dot(want), -1, 1))) else CFrame.identity
			local handRot = CFrame.fromAxisAngle(aim, rad(gv("Roll"))) * turn * leftHand.Rotation
			-- the launcher's recoil pushes the hand back just after full reach; the bite tugs it forward
			local push = 0
			local k = (gT - gv("ReachIn") * 0.7) / 0.05
			if k > 0 then
				push -= gv("Kick") * k * math.exp(1 - k)
			end
			if GF.BiteAt then
				local b = (GF.FiredAt + gT) - GF.BiteAt
				if b >= 0 then
					push += gv("Jolt") * math.exp(-b * 12) * math.min(1, b / 0.025)
				end
			end
			local wrist = cam * (gv("Wrist") + (if aimC then V(aimC.X, aimC.Y, 0) * gv("Follow") else Vector3.zero)) + aim * push
			local target = CFrame.new(wrist - handRot:VectorToWorldSpace(A.HandWrist)) * handRot
			leftHand = leftHand:Lerp(target, gW)
			gWrist, gAim = wrist, aim
		end
		local rs = cam * SHOULDER.Right.Hip:Lerp(SHOULDER.Right.ADS, ads)
		local ls = cam * SHOULDER.Left.Hip:Lerp(SHOULDER.Left.ADS, ads)
		if throwW > 0 then
			ls += cam:VectorToWorldSpace(THROW_SHOULDER) * throwW
		end
		if gW > 0 then
			ls += cam:VectorToWorldSpace(GRAPPLE.Shoulder) * math.min(gW, 1)
		end
		local lsReload = ls + cam:VectorToWorldSpace(V(0.1, -0.15, 0.35)) * pose.LeftOnMag
		-- forearms continue from the gloves with a natural wrist bend (see armTarget)
		local rPole, lPole
		rs, rPole = armTarget(arms.Right, rightHand, rs, BEND.Right, cam)
		lsReload, lPole = armTarget(arms.Left, leftHand, lsReload, BEND.Left, cam)
		-- grapple: the arm is extended along the line to the hook — shoulder straight back from the
		-- wrist (a touch down / out), elbow pointing down and out; blended in with the reach
		if gWrist and gAim and arms.Left then
			local A = arms.Left
			local e = math.min(gW, 1)
			local gShoulder = gWrist - gAim * (A.L1 + A.L2) * gv("Straight") + cam:VectorToWorldSpace(gv("ShoulderBias"))
			lsReload = lsReload:Lerp(gShoulder, e)
			lPole = lPole:Lerp(cam:VectorToWorldSpace(gv("Pole")), e)
		end
		local rFinal = arms:Pose("Right", rs, rightHand, rPole, parts, cfs)
		-- the visor plate's edge rides on the knuckles: publish their screen height (0 top .. 1 bottom)
		if vw > 0 and rFinal then
			local top = rFinal.Position + cam.UpVector * 0.11
			local sp = self.Camera:WorldToViewportPoint(top)
			VisorFeed.TipY = sp.Y / math.max(1, self.Camera.ViewportSize.Y)
		else
			VisorFeed.TipY = nil
		end
		local lFinal = arms:Pose("Left", lsReload, leftHand, lPole, parts, cfs)
		-- the grenade sits in the left palm from the grab until it leaves the hand
		local showHeld = throwT ~= nil and throwT >= THROW_SHOW_FROM and throwT < GrenadeFeed.Release and lFinal ~= nil and arms.Left ~= nil
		if #self.HeldParts > 0 then
			local heldOffset = GrenadeFeed.Tune and GrenadeFeed.Tune.Held or HELD_OFFSET
			local hcf = if showHeld then lFinal * arms.Left.Grip * heldOffset else cam * CFrame.new(0, -50, 0)
			for i, p in self.HeldParts do
				table.insert(parts, p)
				table.insert(cfs, hcf * self.HeldOffsets[i])
			end
		end
		-- the support hand would poke out beside the handguard in the sight picture: hide it when aimed
		if arms.SetSideHidden then
			arms:SetSideHidden("Left", (ads > 0.75 and pose.LeftOnMag < 0.05 and vw <= 0 and throwW <= 0 and gW <= 0) or (pose.Weights.LeftOff or 0) > 0.5)
		end
	end

	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	-- sight window corners this frame (world space), for the HUD's straight window frame
	-- scope eyepiece (centre + rim point) for the HUD lens
	local la, lb = self.Body:FindFirstChild("ADSPoint"), self.Body:FindFirstChild("LensEdge")
	if la and lb then
		self.LensA = (gunCF * la.CFrame).Position
		self.LensB = (gunCF * lb.CFrame).Position
	end
	local so = gunCF * self.SightLocal
	self.SightOrigin = so.Position
	self.SightAim = so.Position + gunCF.LookVector * 600
	local wa, wb = self.Body:FindFirstChild("WindowA"), self.Body:FindFirstChild("WindowB")
	if wa and wb then
		self.WindowA = (gunCF * wa.CFrame).Position
		self.WindowB = (gunCF * wb.CFrame).Position
	end
end

function Viewmodel:Destroy()
	self.Root:Destroy()
end

-- live skin change from the inventory (materials / textures only; no transform changes)
function Viewmodel:ApplySkin(skinId: string)
	if not self.Gun then
		return
	end
	Skins.Apply(self.Gun, self.Weapon.Id, skinId)
	self._adsK = nil
	-- drop removed skin meshes from the tracked lists, register new ones (same offset rules)
	local function prune(parts, offsets)
		for i = #parts, 1, -1 do
			if not parts[i].Parent then
				table.remove(parts, i)
				if offsets then
					table.remove(offsets, i)
				end
			end
		end
	end
	prune(self.GunParts, self.GunOffsets)
	prune(self.AllParts)
	local bodyInv = self.Body.CFrame:Inverse()
	for _, d in self.Gun:GetDescendants() do
		if d.Name == "VantageSkinMesh" and d:IsA("BasePart") and not table.find(self.AllParts, d) then
			d.Anchored = true
			d.CastShadow = false
			d.LocalTransparencyModifier = if self.Hidden then 1 else 0
			table.insert(self.AllParts, d)
			table.insert(self.GunParts, d)
			table.insert(self.GunOffsets, bodyInv * d.CFrame)
		end
	end
end

return Viewmodel
