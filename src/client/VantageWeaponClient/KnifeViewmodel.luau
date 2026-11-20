--[[
	VANTAGE — KnifeViewmodel (client, Combat Knife; still supports a hinged balisong asset)
	The knife sits in the player's own right hand (Roblox grip convention: the handle axis runs
	through the fist, blade out of the thumb side). Blade and bite handle swing on their hinge
	(pivot pin, Z axis) from the shared clips, so flips are real articulation of the knife plus
	wrist / hand motion, never the whole model spinning on its own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Skins = require(ReplicatedStorage.Vantage.Weapons.Skins) -- cosmetic
local SkinFX = require(ReplicatedStorage.Vantage.Weapons.SkinFX) -- swing trail style (shot overhaul stage 3)
local VFXKit = require(ReplicatedStorage.Vantage.Weapons.VFXKit)
local Workspace = game:GetService("Workspace")

local MoveConfig = require(ReplicatedStorage.Vantage.Movement.MovementConfig)
local ViewmodelArms = require(script.Parent.ViewmodelArms)
local Spring = require(script.Parent.Viewmodel).Spring

local V = Vector3.new
local rad = math.rad

local SHOULDER = { Right = V(0.82, -1.05, -0.22), Left = V(-0.85, -1.08, -0.3) }
local POLE = { Right = V(0.7, -1, 0.35), Left = V(-0.75, -1, 0.3) }

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- The shoulder anchors are virtual (off-screen). If the hand is beyond the arm's reach, slide the
-- shoulder toward it so the hand stays exactly where the clip puts it (same rule as Viewmodel).
local REACH_USE = 0.93
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

local KnifeViewmodel = {}
KnifeViewmodel.__index = KnifeViewmodel

function KnifeViewmodel.new(weapon, asset: Model, camera: Camera, character: Model)
	local self = setmetatable({}, KnifeViewmodel)
	self.Weapon = weapon
	self.Cfg = weapon.Viewmodel
	self.Camera = camera
	local root = Instance.new("Model")
	root.Name = "VantageKnifeViewmodel"
	self.Root = root

	local knife = asset:Clone()
	Skins.Apply(knife, weapon.Id, Skins.ForPlayer(game:GetService("Players").LocalPlayer, weapon.Id))
	local S = self.Cfg.Scale or 1
	if S ~= 1 then
		knife:ScaleTo(S)
	end
	self.Scale = S
	local handle = knife.PrimaryPart :: BasePart
	-- remove joints (we place anchored parts directly) but read the hinge frames first
	local function hinge(name)
		local m = handle:FindFirstChild(name) :: Motor6D?
		return if m then { C0 = m.C0, C1 = m.C1, Part = m.Part1 } else nil
	end
	self.BladeHinge = hinge("BladeHinge")
	self.BiteHinge = hinge("BiteHinge")
	self.Groups = {}
	local function addGroup(rootPart: BasePart, list)
		local inv = rootPart.CFrame:Inverse()
		local g = { Root = rootPart, Parts = {}, Offsets = {} }
		for _, d in rootPart.Parent:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(g.Parts, d)
				table.insert(g.Offsets, inv * d.CFrame)
			end
		end
		return g
	end
	-- fixed blade: one rigid group (every part of the model); balisong: handle + two hinged groups
	self.SafeGroup = addGroup(handle)
	self.BladeGroup = self.BladeHinge and addGroup(self.BladeHinge.Part)
	self.BiteGroup = self.BiteHinge and addGroup(self.BiteHinge.Part)
	self.AllParts = {}
	for _, d in knife:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			table.insert(self.AllParts, d)
		end
	end
	self.GripLocal = (handle:FindFirstChild("Grip") :: Attachment).CFrame
	local tip = (self.BladeHinge and self.BladeHinge.Part:FindFirstChild("Tip")) or handle:FindFirstChild("Tip")
	self.TipAttachment = tip
	knife.Parent = root
	self.Knife = knife

	local armScale = S / (weapon.ThirdPerson and weapon.ThirdPerson.Scale or S)
	self.Arms = ViewmodelArms.new(character, armScale, root)

	self.Kick = Spring.new(self.Cfg.KickStiffness, self.Cfg.KickDamping)
	self.KickRot = Spring.new(self.Cfg.KickRotStiffness, self.Cfg.KickRotDamping)
	self.Land = Spring.new(120, 14)
	self.Sway = Vector2.zero
	self.LastCam = camera.CFrame
	self.BobPhase = 0
	self.BobWeight = 0
	self.Air = 0
	self.Strafe = 0
	self.Inertia = Vector3.zero
	self.LastVel = Vector3.zero
	self.CrouchW = 0
	self.SlideW = 0
	self.Visible = false
	self.Hidden = false
	self:_trail()
	return self
end

function KnifeViewmodel:SetVisible(on: boolean)
	self.Visible = on
	self.Root.Parent = if on then self.Camera else nil
end

function KnifeViewmodel:SetHidden(hidden: boolean)
	if self.Hidden == hidden then
		return
	end
	self.Hidden = hidden
	for _, p in self.AllParts do
		p.LocalTransparencyModifier = if hidden then 1 else 0
	end
	self.Arms:SetHidden(hidden)
end

function KnifeViewmodel:LandImpulse(impact: number)
	if impact < 12 then
		return
	end
	local s = math.clamp((impact - 12) / (MoveConfig.HardLandingVelocity - 12), 0.2, 1)
	self.Land.Vel += V(0, -self.Cfg.LandDip * s * 14, 0)
end

-- small physical reaction when a strike connects
function KnifeViewmodel:HitReaction(heavy: boolean)
	self.Kick.Vel += V(0, 0, (if heavy then 0.9 else 0.5) * self.Scale)
	self.KickRot.Vel += V(if heavy then -40 else -22, 0, 0)
end

-- swing trail between the grip→tip line of the blade, styled by the knife skin (def.Swing for patterns,
-- the finish colour otherwise). Enabled only during a swing (Swing), so it never lingers in view.
function KnifeViewmodel:_trail()
	for _, k in { "Trail", "TrailA", "TrailB" } do
		if self[k] then self[k]:Destroy(); self[k] = nil end
	end
	local knife = self.Knife
	local mesh = knife and knife:FindFirstChild("KnifeMesh", true)
	local handle = knife and knife.PrimaryPart
	local tip = handle and handle:FindFirstChild("Tip")
	local grip = handle and handle:FindFirstChild("Grip")
	if not (mesh and tip and grip) then return end
	local a0 = Instance.new("Attachment")
	a0.Name = "SwingA"
	a0.Position = mesh.CFrame:PointToObjectSpace(grip.WorldPosition:Lerp(tip.WorldPosition, 0.35))
	a0.Parent = mesh
	local a1 = Instance.new("Attachment")
	a1.Name = "SwingB"
	a1.Position = mesh.CFrame:PointToObjectSpace(tip.WorldPosition)
	a1.Parent = mesh
	local def = SkinFX.Get(knife:GetAttribute("SkinFX"))
	local sw = def and def.Swing
	if not sw then
		local f = VFXKit.Finishes[knife:GetAttribute("Skin") or ""]
		local c = (f and (f.TracerColor or f.Hot)) or Color3.fromRGB(235, 240, 255)
		sw = { c1 = c, c2 = (f and f.Warm) or c, Transp = if f and next(f) then 0.35 else 0.6 }
	end
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.FaceCamera = false
	t.Lifetime = sw.Life or 0.16
	t.MinLength = 0.02
	t.LightEmission = sw.Emission or 1
	t.LightInfluence = 0
	t.Color = sw.Seq or ColorSequence.new(sw.c1, sw.c2 or sw.c1)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, sw.Transp or 0.25), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new(1, 0.4)
	if sw.Tex then
		t.Texture = sw.Tex
		t.TextureMode = sw.Mode or Enum.TextureMode.Stretch
		t.TextureLength = sw.TexLen or 1
	end
	t.Enabled = false
	t.Parent = mesh
	self.Trail, self.TrailA, self.TrailB = t, a0, a1
end

function KnifeViewmodel:Swing(dur: number?)
	if not self.Trail then return end
	self.Trail.Enabled = true
	self.TrailOff = os.clock() + (dur or 0.22)
end

function KnifeViewmodel:TipPosition(): Vector3?
	return self.TipAttachment and self.TipAttachment.WorldPosition
end

local function placeGroup(g, rootCF: CFrame, parts, cfs)
	for i, p in g.Parts do
		table.insert(parts, p)
		table.insert(cfs, rootCF * g.Offsets[i])
	end
end

function KnifeViewmodel:Step(dt: number, ctx)
	if self.TrailOff and os.clock() > self.TrailOff then
		self.TrailOff = nil
		if self.Trail then self.Trail.Enabled = false end
	end
	if not self.Visible then
		return
	end
	local c = self.Cfg
	local cam = self.Camera.CFrame
	local m = ctx.Movement
	local now = os.clock()
	local pose = ctx.Pose

	-- sway
	local rel = self.LastCam:ToObjectSpace(cam)
	self.LastCam = cam
	local rx, ry = rel:ToEulerAnglesYXZ()
	local target = Vector2.new(
		math.clamp(math.deg(ry) / math.max(dt, 1e-3) * 0.02 * c.SwayAmount, -c.SwayMax, c.SwayMax),
		math.clamp(math.deg(rx) / math.max(dt, 1e-3) * 0.02 * c.SwayAmount, -c.SwayMax, c.SwayMax)
	)
	self.Sway = self.Sway:Lerp(target, expAlpha(10, dt))
	local swayCF = CFrame.Angles(rad(self.Sway.Y * 0.7), rad(self.Sway.X * 0.7), rad(self.Sway.X * 0.5))
		* CFrame.new(-self.Sway.X * 0.005, -self.Sway.Y * 0.005, 0)

	-- strafe roll + inertia
	local vel = m.Velocity
	local localVel = cam:VectorToObjectSpace(vel)
	self.Strafe += (math.clamp(localVel.X / MoveConfig.RunSpeed, -1.2, 1.2) - self.Strafe) * expAlpha(8, dt)
	local accel = (vel - self.LastVel) / math.max(dt, 1 / 240)
	self.LastVel = vel
	local la = cam:VectorToObjectSpace(accel) * -(c.Inertia or 0)
	if la.Magnitude > 0.07 then
		la = la.Unit * 0.07
	end
	self.Inertia = self.Inertia:Lerp(V(la.X, 0, la.Z), expAlpha(9, dt))

	-- knife running: energetic pump + bob, synced to stride
	local speedFrac = math.clamp(m.Speed / MoveConfig.RunSpeed, 0, 1.4)
	local bobTarget = if m.Grounded and m.Stance ~= "Slide" and m.Speed > 1 then math.min(speedFrac, 1.2) else 0
	self.BobWeight += (bobTarget - self.BobWeight) * expAlpha(10, dt)
	self.BobPhase = (self.BobPhase + dt * c.BobFrequency * math.pi * 2 * math.max(speedFrac, 0.35)) % (math.pi * 2)
	local bw = self.BobWeight
	local BA = c.BobAmount
	local s1 = math.sin(self.BobPhase)
	local run = CFrame.new(s1 * BA * 0.8 * bw, -math.abs(s1) * BA * bw + math.sin(now * 1.6) * 0.006, -s1 * BA * 0.9 * bw)
		* CFrame.Angles(rad(s1 * 6 * bw + 8 * bw), rad(-s1 * 4 * bw), rad(s1 * 3 * bw))
	local leftRun = CFrame.new(-s1 * BA * 0.8 * bw, -math.abs(s1) * BA * bw, s1 * BA * 1.2 * bw) * CFrame.Angles(rad(-s1 * 8 * bw), 0, 0)

	local airTarget = if m.Grounded then 0 else math.clamp(-m.VerticalSpeed / 45, -1, 1)
	self.Air += (airTarget - self.Air) * expAlpha(9, dt)
	local airCF = CFrame.new(0, self.Air * c.AirLift, 0) * CFrame.Angles(rad(self.Air * 4), 0, 0)
	local land = self.Land:Step(dt)
	local landCF = CFrame.new(0, land.Y, 0) * CFrame.Angles(rad(land.Y * 25), 0, 0)
	self.SlideW += ((if m.Stance == "Slide" then 1 else 0) - self.SlideW) * expAlpha(10, dt)
	local slideCF = CFrame.identity:Lerp(CFrame.new(-0.06, -0.04, 0.05) * CFrame.Angles(0, 0, rad(-14)), self.SlideW)
	local kp = self.Kick:Step(dt)
	local kr = self.KickRot:Step(dt)
	local kickCF = CFrame.new(0, kp.Y, kp.Z) * CFrame.Angles(rad(kr.X), rad(kr.Y), rad(kr.Z))
	local moveCF = CFrame.new(self.Inertia.X, 0, self.Inertia.Z * 0.6) * CFrame.Angles(0, 0, rad(-self.Strafe * (c.StrafeTilt or 0)))

	local handTrack = pose.Tracks.Hand or CFrame.identity
	local leftTrack = pose.Tracks.Left or CFrame.identity
	local layers = moveCF * run * swayCF * airCF * landCF * slideCF * kickCF
	local handCF = cam * CFrame.new(handTrack.Position) * c.Offset * layers * handTrack.Rotation
	local leftCF = cam * CFrame.new(leftTrack.Position) * c.LeftOffset * moveCF * leftRun * swayCF * airCF * landCF * leftTrack.Rotation

	local parts, cfs = {}, {}
	local arms = self.Arms
	if arms:IsValid() then
		handCF = arms:Pose("Right", reachableShoulder(arms.Right, cam * SHOULDER.Right, handCF), handCF, cam:VectorToWorldSpace(POLE.Right), parts, cfs)
		arms:Pose("Left", reachableShoulder(arms.Left, cam * SHOULDER.Left, leftCF), leftCF, cam:VectorToWorldSpace(POLE.Left), parts, cfs)
		-- Spin track: the knife rolls in the fingers about its own blade axis (grip Y)
		local spin = pose.Raw.Spin and pose.Raw.Spin.Z or 0
		local handleCF = handCF * arms.Right.Grip * CFrame.Angles(0, rad(spin), 0) * self.GripLocal:Inverse()
		local bladeDeg = pose.Raw.Blade and pose.Raw.Blade.Z or 0
		local biteDeg = pose.Raw.Bite and pose.Raw.Bite.Z or 0
		local bh, ih = self.BladeHinge, self.BiteHinge
		placeGroup(self.SafeGroup, handleCF, parts, cfs)
		if bh and ih then
			placeGroup(self.BladeGroup, handleCF * bh.C0 * CFrame.Angles(0, 0, rad(bladeDeg)) * bh.C1:Inverse(), parts, cfs)
			placeGroup(self.BiteGroup, handleCF * ih.C0 * CFrame.Angles(0, 0, rad(biteDeg)) * ih.C1:Inverse(), parts, cfs)
		end
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function KnifeViewmodel:Destroy()
	self.Root:Destroy()
end

-- live skin change from the inventory (materials / textures only; no transform changes)
function KnifeViewmodel:ApplySkin(skinId: string)
	if self.Knife then
		Skins.Apply(self.Knife, self.Weapon.Id, skinId)
	self:_trail()
	end
end

return KnifeViewmodel
