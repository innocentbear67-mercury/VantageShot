--[[
	VANTAGE — GrappleFX (client)
	Everything you see and hear of a grapple, for your own shot and for other players':
	the launcher's muzzle flash, the hook flying out, the energy cable (a lime sheath around a white
	core, with pulses running along it; slack while the hook flies, snapping taut on the bite,
	whipping back on release), the bite itself (flash, sparks, ripple, ring) and the sounds.
	Purely cosmetic: client-only parts under Workspace.VantageGrappleFX, anchored, no collision,
	invisible to raycasts. The pull itself is MovementController:GrappleStart.

	local shot = GrappleFX.Fire(character, point, isLocal, normal?)   hook flies to `point`
	shot:Attach()     the bite (remote players' shots do this themselves on arrival)
	shot:Release()    cable whips back to the launcher and is gone
	GrappleFX.Miss(character, toward, isLocal)   a shot at nothing: out a short way and back
	local shot = GrappleFX.FireTracked(character, track, isLocal)
		a hook on something that MOVES (the dropship): track() -> (point, velocity, anchorCFrame) or nil
		when it is gone. The cable follows it, stays up as long as the ride lasts (no 8 s clean-up),
		sends a bright pulse down the cable when it bites and bursts when let go.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Abilities.AbilityConfig)
local EnergyFX = require(script.Parent.Parent:WaitForChild("VantageWeaponClient"):WaitForChild("EnergyFX"))
local G = Config.Abilities.Grapple
local LIME, WHITE = Config.Colors.Lime, Config.Colors.LimeWhite
-- 2026-11-17: every Grappling Hook has its own colours (character attributes HookColor / HookColor2,
-- EquipmentCatalog) and its own head, which flies out on the cable while the docked one hides
local EquipCatalog, EquipBuild = nil, nil
pcall(function()
	local eq = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Equipment", 10)
	EquipCatalog = require(eq:WaitForChild("EquipmentCatalog"))
	EquipBuild = require(eq:WaitForChild("EquipmentBuild"))
end)
local function useCol(character: Instance?)
	if EquipCatalog then
		LIME, WHITE = EquipCatalog.HookColors(character)
	end
end
-- ── particles (2026-11-17): every hook has its own particle style, drawn in its own colours ──────────
local PT = "rbxasset://textures/particles/"
local STYLES = {
	Talon = { Tex = PT .. "sparkles_main.dds", Size = 0.22, Life = 0.35, Speed = 2.5, Spread = 35, Rate = 70, Drag = 2 },
	Harpoon = { Tex = PT .. "sparkles_main.dds", Size = 0.16, Life = 0.24, Speed = 7, Spread = 12, Rate = 90, Squash = 2.2, Orient = Enum.ParticleOrientation.VelocityParallel },
	MagAnchor = { Tex = PT .. "explosion01_shockwave_main.dds", Size = 0.55, Grow = true, Life = 0.32, Speed = 0.2, Spread = 0, Rate = 24 },
	Kraken = { Tex = PT .. "fire_sparks_main.dds", Size = 0.24, Life = 0.55, Speed = 4, Spread = 70, Rate = 60, Accel = Vector3.new(0, -16, 0) },
	Lotus = { Tex = PT .. "sparkles_main.dds", Size = 0.3, Life = 0.8, Speed = 1.2, Spread = 180, Rate = 40, Drag = 3, Spin = 200, Squash = 0.7 },
	Starfall = { Tex = PT .. "sparkles_main.dds", Size = 0.36, Life = 0.9, Speed = 0.5, Spread = 180, Rate = 55, Accel = Vector3.new(0, -1.5, 0), Twinkle = true },
}
local function styleOf(character: Instance?)
	local id = character and character:GetAttribute("EquipHook")
	return STYLES[id or ""] or STYLES.Talon
end
-- 2026-11-19: the hook's pull profile (EquipmentCatalog Profile): Rigid cable (Harpoon's winch), body Trail size
local function profileOf(character: Instance?)
	if not EquipCatalog then
		return {}
	end
	local ok, p = pcall(EquipCatalog.HookProfileFor, character and character:GetAttribute("EquipHook"))
	return if ok and p then p else {}
end
-- a streak off the body in the hook's colours, seen by everyone while the cable pulls and through the fling after
local function bodyTrail(character: Model): Trail?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local old = torso:FindFirstChild("VantageGrappleTrail")
	if old then
		old:Destroy()
	end
	local tp = profileOf(character).Trail or { Width = 0.4, Life = 0.3 }
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Name, a1.Name = "VantageGrappleTrailA", "VantageGrappleTrailB"
	a0.Position, a1.Position = Vector3.new(0, tp.Width * 1.6, 0), Vector3.new(0, -tp.Width * 1.6, 0)
	a0.Parent, a1.Parent = torso, torso
	local t = Instance.new("Trail")
	t.Name = "VantageGrappleTrail"
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = tp.Life
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = true
	t.MinLength = 0.2
	t.Color = ColorSequence.new(WHITE, LIME)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new(1, 0.2)
	t.Parent = torso
	t.Destroying:Connect(function()
		a0:Destroy()
		a1:Destroy()
	end)
	return t
end
local function particles(parent: Instance, st, rate: number?, size: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "GrapplePFX"
	e.Texture = st.Tex
	e.Color = ColorSequence.new(WHITE, LIME)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 2.5
	e.Lifetime = NumberRange.new(st.Life * 0.6, st.Life)
	e.Speed = NumberRange.new(st.Speed * 0.5, st.Speed)
	e.SpreadAngle = Vector2.new(st.Spread, st.Spread)
	e.Acceleration = st.Accel or Vector3.zero
	e.Drag = st.Drag or 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(st.Spin or 0), st.Spin or 0)
	local z = size or st.Size
	if st.Grow then
		e.Size = NumberSequence.new(z * 0.15, z)
	elseif st.Twinkle then
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, z), NumberSequenceKeypoint.new(0.45, z * 0.35), NumberSequenceKeypoint.new(0.7, z * 0.9), NumberSequenceKeypoint.new(1, 0) })
	else
		e.Size = NumberSequence.new(z, 0)
	end
	e.Transparency = NumberSequence.new(0.1, 1)
	if st.Squash then
		e.Squash = NumberSequence.new(st.Squash)
	end
	if st.Orient then
		e.Orientation = st.Orient
	end
	e.Rate = rate or st.Rate
	e.Parent = parent
	return e
end
-- a one-off burst (fire, bite, let go)
local function burstAt(pos: Vector3, st, n: number)
	local p = EnergyFX.Part({ Name = "PFXBurst", Transparency = 1, Size = Vector3.one * 0.1, CFrame = CFrame.new(pos) }, EnergyFX.Folder("VantageGrappleFX"))
	local a = Instance.new("Attachment")
	a.Parent = p
	local e = particles(a, st, 0, st.Size * 1.3)
	e.Speed = NumberRange.new(st.Speed + 4, st.Speed + 11)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = math.max(e.Drag, 4)
	e:Emit(n)
	Debris:AddItem(p, st.Life + 0.8)
end

-- the head pieces still sitting on the launcher (third person, and your first-person arm)
local function dockedParts(character: Model, isLocal: boolean): { BasePart }
	if not EquipBuild then
		return {}
	end
	local out = EquipBuild.DockedHead(character)
	if isLocal then
		for _, vm in Workspace.CurrentCamera:GetChildren() do
			local arms = vm:FindFirstChild("Arms")
			local fore = arms and arms:FindFirstChild("LeftLowerArm")
			if fore then
				for _, p in fore:GetChildren() do
					if p:IsA("BasePart") and EquipBuild.HeadGroups[p:GetAttribute("Group") or ""] then
						table.insert(out, p)
					end
				end
			end
		end
	end
	return out
end

local GrappleFX = {}
local shots = {}
local RETRACT_TIME = 0.16

local function folder(): Folder
	return EnergyFX.Folder("VantageGrappleFX")
end

-- where the cable leaves the suit: the launcher's emitter. Your own shot leaves the first-person
-- arm (the viewmodel's left forearm under the camera); everyone else's leaves the character.
local function muzzle(character: Model, isLocal: boolean): Vector3
	-- third person on the dropship (VantageAircraftClient): your cable leaves your body's launcher
	if isLocal and Players.LocalPlayer:GetAttribute("VantageThirdPerson") then
		isLocal = false
	end
	if isLocal then
		local cam = Workspace.CurrentCamera
		for _, vm in cam:GetChildren() do
			local arms = vm:FindFirstChild("Arms")
			local fore = arms and arms:FindFirstChild("LeftLowerArm")
			if fore and fore:IsA("BasePart") then
				local e = fore:FindFirstChild("GrappleEmitter")
				if e and e:IsA("BasePart") then
					return e.Position
				end
				return (fore.CFrame * CFrame.new(-0.3, -0.4, 0)).Position
			end
		end
		return (cam.CFrame * CFrame.new(-0.55, -0.6, -1.1)).Position
	end
	local launcher = character:FindFirstChild("VantageGrappleLauncher")
	local e = launcher and launcher:FindFirstChild("Emitter")
	if e and e:IsA("BasePart") then
		return e.Position
	end
	local arm = character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("HumanoidRootPart")
	return if arm and arm:IsA("BasePart") then arm.Position else Vector3.zero
end

local function beam(a0: Attachment, a1: Attachment, width: number, color: Color3, parent: Instance): Beam
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Width0, b.Width1 = width, width
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = 3
	b.Color = ColorSequence.new(color)
	b.Segments = 24
	b.Parent = parent
	return b
end

local Shot = {}
Shot.__index = Shot

local function newShot(character: Model, point: Vector3, isLocal: boolean, normal: Vector3?, miss: boolean, track: any?)
	local self = setmetatable({}, Shot)
	useCol(character)
	self.Character, self.Point, self.IsLocal, self.Miss, self.Track = character, point, isLocal, miss, track
	self.Style = styleOf(character)
	self.Rigid = profileOf(character).Rigid == true
	local from = muzzle(character, isLocal)
	self.Normal = normal or (from - point).Unit
	self.Phase = "Fly"
	self.At = os.clock()
	self.Flight = math.max(0.05, (point - from).Magnitude / G.ProjectileSpeed)
	self.Tip = from
	self.Slack = 0.12
	local f = folder()
	-- the two ends of the cable
	self.Base = EnergyFX.Part({ Name = "Base", Transparency = 1, Size = Vector3.one * 0.1, CFrame = CFrame.new(from) }, f)
	self.Hook = EnergyFX.Part({ Name = "Hook", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = WHITE, Size = Vector3.one * 0.3, CFrame = CFrame.new(from) }, f)
	self.A0 = Instance.new("Attachment")
	self.A0.Parent = self.Base
	self.A1 = Instance.new("Attachment")
	self.A1.Parent = self.Hook
	-- claws: a lime blade through the hook, so it reads as a device and not a ball of light
	self.Claw = EnergyFX.Part({ Name = "Claw", Material = Enum.Material.Neon, Color = LIME, Size = Vector3.new(0.08, 0.08, 0.7), CFrame = CFrame.new(from) }, f)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = LIME, 9, 2.2, false
	light.Parent = self.Hook
	self.Light = light
	-- particles: a trail off the flying hook, motes running along the cable, a burst at the muzzle
	local pa = Instance.new("Attachment")
	pa.Name = "PFX"
	pa.Parent = self.Hook
	self.Trail = particles(pa, self.Style)
	self.Motes = EnergyFX.Part({ Name = "Motes", Transparency = 1, Size = Vector3.one * 0.1, CFrame = CFrame.new(from) }, f)
	local ma = Instance.new("Attachment")
	ma.Parent = self.Motes
	self.MoteFX = particles(ma, self.Style, 10, self.Style.Size * 0.7)
	burstAt(from, self.Style, 10)
	if EquipBuild then
		local ok, head = pcall(EquipBuild.HeadModel, character:GetAttribute("EquipHook"), if isLocal then 0.85 else 1)
		if ok and head then
			for _, p in head:GetDescendants() do
				if p:IsA("BasePart") then
					p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
				end
			end
			head:PivotTo(CFrame.new(from))
			head.Parent = f
			self.Head = head
			self.Claw.Transparency = 1
			self.Hook.Transparency = 1
			self.Docked = dockedParts(character, isLocal)
			for _, p in self.Docked do
				p.LocalTransparencyModifier = 1
			end
		end
	end
	local t0, t1 = Instance.new("Attachment"), Instance.new("Attachment")
	t0.Position, t1.Position = Vector3.new(0, 0.12, 0), Vector3.new(0, -0.12, 0)
	t0.Parent, t1.Parent = self.Hook, self.Hook
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = t0, t1
	trail.Lifetime = 0.12
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(WHITE, LIME)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = self.Hook
	self.Sheath = beam(self.A0, self.A1, 0.17, LIME, self.Base)
	self.Core = beam(self.A0, self.A1, 0.055, WHITE, self.Base)
	self.Core.Transparency = NumberSequence.new(0.05)
	-- the launcher fires
	EnergyFX.Flash(from, { Color = WHITE, From = 0.15, To = 0.7, Life = 0.08, Folder = f, Light = { Color = LIME, Range = 7, Brightness = 3, Life = 0.12 } })
	EnergyFX.Sparks(EnergyFX.UpFrame(from, (point - from).Unit), 8, { Color0 = WHITE, Color1 = LIME, Spread = 28, Speed = NumberRange.new(14, 26), Life = NumberRange.new(0.08, 0.2), Size = 0.1 })
	EnergyFX.Sound(Config.Sounds.GrappleFire, if isLocal then nil else from, { RollOffMin = Config.SoundRollOff.Min, RollOffMax = Config.SoundRollOff.Max })
	table.insert(shots, self)
	return self
end

function Shot:Attach()
	useCol(self.Character)
	if self.Phase ~= "Fly" and self.Phase ~= "Arrived" then
		return
	end
	self.Phase = "Taut"
	self.At = os.clock()
	self.Tip = self.Point
	local f = folder()
	if not self.Miss and self.Character:GetAttribute("EquipHook") ~= "Starfall" then
		self.BodyTrail = bodyTrail(self.Character)
	end
	if self.Track then
		-- on a moving hull: effects that stay put would be left behind, so a short flash, sparks,
		-- and an energy pulse that runs down the cable (drawn in step)
		local _, _, acf = self.Track()
		local n = if acf then -acf.UpVector else Vector3.new(0, -1, 0)
		self.PulseAt = self.At
		EnergyFX.Flash(self.Point, { Color = WHITE, From = 0.4, To = 2.2, Life = 0.1, Folder = f, Light = { Color = LIME, Range = 16, Brightness = 5, Life = 0.2 } })
		EnergyFX.Sparks(EnergyFX.UpFrame(self.Point, n), 18, { Color0 = WHITE, Color1 = LIME, Spread = 70, Speed = NumberRange.new(10, 26), Life = NumberRange.new(0.12, 0.3), Size = 0.15 })
		EnergyFX.Sound(Config.Sounds.GrappleAttach, if self.IsLocal then nil else self.Point, { RollOffMin = Config.SoundRollOff.Min, RollOffMax = Config.SoundRollOff.Max })
		return
	end
	local p, n = self.Point, self.Normal
	burstAt(p + n * 0.1, self.Style or STYLES.Talon, 26)
	EnergyFX.Flash(p, { Color = WHITE, From = 0.3, To = 1.7, Life = 0.12, Folder = f, Light = { Color = LIME, Range = 14, Brightness = 4, Life = 0.25 } })
	EnergyFX.Ripple(p + n * 0.05, n, { Color = LIME, From = 0.4, To = 3.2, Life = 0.28, Folder = f })
	EnergyFX.ShockRing(EnergyFX.UpFrame(p + n * 0.06, n), { From = 0.2, To = 1.5, Life = 0.3, Segments = 10, Thickness = 0.07, Color = WHITE, Folder = f })
	EnergyFX.Sparks(EnergyFX.UpFrame(p, n), 22, { Color0 = WHITE, Color1 = LIME, Spread = 62, Speed = NumberRange.new(12, 32), Life = NumberRange.new(0.15, 0.4), Size = 0.16 })
	for _ = 1, 3 do
		local r = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		local side = r - n * r:Dot(n)
		if side.Magnitude > 0.05 then
			EnergyFX.Arc(p, p + side.Unit * (0.8 + math.random()), { Color = LIME, Width = 0.05, Life = 0.12, Segments = 4, Jitter = 0.25 })
		end
	end
	EnergyFX.Sound(Config.Sounds.GrappleAttach, if self.IsLocal then nil else p, { RollOffMin = Config.SoundRollOff.Min, RollOffMax = Config.SoundRollOff.Max })
end

function Shot:Release()
	useCol(self.Character)
	if self.Phase == "Retract" or self.Phase == "Gone" then
		return
	end
	self.Phase = "Retract"
	self.At = os.clock()
	self.From = self.Tip
	local bt = self.BodyTrail
	if bt then
		self.BodyTrail = nil
		task.delay(1.1, function() -- keeps streaking through the fling
			if bt.Parent then
				bt.Enabled = false
				Debris:AddItem(bt, bt.Lifetime + 0.1)
			end
		end)
	end
	if not self.Miss then
		burstAt(self.Tip, self.Style or STYLES.Talon, 10)
	end
	if self.Track and not self.Miss then
		-- let go of the dropship: a small lime burst where the hook lets go
		EnergyFX.Sparks(EnergyFX.UpFrame(self.Tip, Vector3.new(0, -1, 0)), 12, { Color0 = WHITE, Color1 = LIME, Spread = 80, Speed = NumberRange.new(8, 20), Life = NumberRange.new(0.1, 0.25), Size = 0.12 })
		EnergyFX.Flash(self.Tip, { Color = LIME, From = 0.3, To = 1.4, Life = 0.08, Folder = folder() })
	end
	EnergyFX.Sound(Config.Sounds.GrappleRelease, if self.IsLocal then nil else self.Tip, { RollOffMin = Config.SoundRollOff.Min, RollOffMax = Config.SoundRollOff.Max })
end

function Shot:Destroy()
	self.Phase = "Gone"
	for _, p in self.Docked or {} do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	self.Docked = nil
	for _, k in { "Base", "Hook", "Claw", "Head", "Motes" } do
		if self[k] then
			self[k]:Destroy()
		end
	end
end

local function step()
	local now = os.clock()
	for i = #shots, 1, -1 do
		local s = shots[i]
		local hum = s.Character:FindFirstChildOfClass("Humanoid")
		if s.Phase ~= "Gone" and (not s.Character:IsDescendantOf(Workspace) or not hum or hum.Health <= 0) and s.Phase ~= "Retract" then
			s:Release() -- death, respawn, leaving: the cable never outlives its owner
		end
		-- a moving anchor: follow it; if it is gone, the cable comes home
		if s.Track and s.Phase ~= "Retract" and s.Phase ~= "Gone" then
			local p = s.Track()
			if p then
				s.Point = p
			else
				s:Release()
			end
		end
		local riding = s.Track ~= nil and s.Phase == "Taut"
		if s.Phase == "Gone" or (not riding and now - s.At > 15) or now - s.At > 120 then
			s:Destroy()
			table.remove(shots, i)
			continue
		end
		local from = muzzle(s.Character, s.IsLocal)
		local t = now - s.At
		if s.Phase == "Fly" then
			local k = math.clamp(t / s.Flight, 0, 1)
			s.Tip = from:Lerp(s.Point, k)
			s.Slack = 0.12 * (1 - k * 0.5)
			if k >= 1 then
				if s.Miss then
					s:Release()
				elseif s.IsLocal then
					s.Phase = "Arrived" -- your own shot: the ability decides (it calls Attach or Release)
					s.At = now
				else
					s:Attach()
				end
			end
		elseif s.Phase == "Arrived" then
			s.Tip = s.Point
			if t > 0.5 then
				s:Release()
			end
		elseif s.Phase == "Taut" then
			s.Tip = s.Point
			-- the bite: the cable snaps straight and rings for a moment, then holds a hair of give
			-- (Harpoon's winch: dead straight, no give)
			s.Slack = if s.Rigid then 0 else 0.05 * math.exp(-9 * t) * math.cos(t * 46) + 0.006 * math.sin(now * 9)
		elseif s.Phase == "Retract" then
			local k = math.clamp(t / RETRACT_TIME, 0, 1)
			s.Tip = s.From:Lerp(from, k * k)
			s.Slack = 0.22 * math.sin(k * math.pi)
			if k >= 1 then
				s:Destroy()
				table.remove(shots, i)
				continue
			end
		end
		local tip = s.Tip
		local d = tip - from
		local len = d.Magnitude
		if len < 0.05 then
			d, len = Vector3.new(0, 0, -0.05), 0.05
		end
		-- both ends carry a frame whose X axis runs along the cable, pitched so the control
		-- points hang below the straight line by `Slack` (negative slack = bowed upward)
		local along = EnergyFX.Facing(Vector3.zero, d) * CFrame.Angles(0, math.pi / 2, 0)
		local tilt = math.clamp(s.Slack * 3, -0.8, 0.8)
		s.Base.CFrame = CFrame.new(from)
		s.A0.WorldCFrame = CFrame.new(from) * (along * CFrame.Angles(0, 0, -tilt)).Rotation
		s.Hook.CFrame = CFrame.new(tip)
		s.A1.WorldCFrame = CFrame.new(tip) * (along * CFrame.Angles(0, 0, tilt)).Rotation
		s.Claw.CFrame = EnergyFX.Facing(tip, d) * CFrame.Angles(0, 0, now * 14)
		if s.Head then
			s.Head:PivotTo(EnergyFX.Facing(tip, d))
		end
		local curve = len * 0.33
		for _, b in { s.Sheath, s.Core } do
			b.CurveSize0, b.CurveSize1 = curve, curve
		end
		-- energy pulses: a bright band travelling from the launcher to the hook
		local p = (now * 1.7) % 1.3 - 0.15
		local base = if s.Phase == "Taut" then 0.42 else 0.3
		local pulseW = 0.09
		-- the bite on a moving hook: one bright, wide pulse running from the hook down to you
		local biteK = if s.PulseAt then (now - s.PulseAt) / 0.3 else 2
		if biteK < 1 then
			p = 1 - biteK
			pulseW = 0.14
		end
		local keys = { NumberSequenceKeypoint.new(0, base) }
		for _, o in { -pulseW, 0, pulseW } do
			local x = p + o
			if x > 0.01 and x < 0.99 then
				table.insert(keys, NumberSequenceKeypoint.new(x, if o == 0 then 0 else base))
			end
		end
		table.insert(keys, NumberSequenceKeypoint.new(1, base))
		s.Sheath.Transparency = NumberSequence.new(keys)
		if s.Trail then
			local st = s.Style or STYLES.Talon
			s.Trail.Rate = if s.Phase == "Taut" then st.Rate * 0.3 else st.Rate
			s.MoteFX.Rate = if s.Phase == "Taut" then 30 else 10
			s.Motes.CFrame = CFrame.new(from:Lerp(tip, math.clamp(p, 0.02, 0.98)))
		end
		s.Sheath.Width0 = 0.17 + (if s.Phase == "Taut" then 0.03 * math.sin(now * 30) else 0) + (if biteK < 1 then 0.12 * (1 - biteK) else 0)
		s.Light.Brightness = 2.2 + 0.8 * math.sin(now * 20)
	end
end

function GrappleFX.Fire(character: Model, point: Vector3, isLocal: boolean, normal: Vector3?)
	return newShot(character, point, isLocal, normal, false)
end

function GrappleFX.FireTracked(character: Model, track: () -> (Vector3?, Vector3, CFrame?), isLocal: boolean, speed: number?)
	local point = track()
	if not point then
		return nil
	end
	local shot = newShot(character, point, isLocal, Vector3.new(0, -1, 0), false, track)
	if speed then
		shot.Flight = math.max(0.05, (point - shot.Tip).Magnitude / speed)
	end
	return shot
end

function GrappleFX.Miss(character: Model, toward: Vector3, isLocal: boolean)
	return newShot(character, toward, isLocal, nil, true)
end

-- 2026-11-19 trait cues ────────────────────────────────────────────────────────────────────
-- a one-off cue: Config.Sounds[name] (2D for you, 3D at pos for others); "Magnet" also rings where the hook bent to
function GrappleFX.Cue(name: string, character: Model?, pos: Vector3?, normal: Vector3?)
	useCol(character)
	local isLocal = character ~= nil and character == Players.LocalPlayer.Character
	local list = Config.Sounds[name]
	if list then
		EnergyFX.Sound(list, if isLocal or not pos then nil else pos, { RollOffMin = Config.SoundRollOff.Min, RollOffMax = Config.SoundRollOff.Max })
	end
	if name == "Magnet" and pos and normal then
		local f = folder()
		EnergyFX.ShockRing(EnergyFX.UpFrame(pos + normal * 0.06, normal), { From = 0.4, To = 2.6, Life = 0.35, Segments = 12, Thickness = 0.08, Color = LIME, Folder = f })
		EnergyFX.Ripple(pos + normal * 0.05, normal, { Color = WHITE, From = 0.3, To = 2, Life = 0.25, Folder = f })
	end
end

-- Starfall's Blink as everyone sees it: a beam of light from where you were to where you land, an afterimage
-- left behind, a star burst on arrival, and the zip sound
function GrappleFX.Blink(character: Model, from: Vector3, to: Vector3, normal: Vector3, isLocal: boolean)
	useCol(character)
	local f = folder()
	local d = to - from
	local len = d.Magnitude
	if len > 0.5 then
		local beamPart = EnergyFX.Part({ Name = "BlinkBeam", Material = Enum.Material.Neon, Color = WHITE, Transparency = 0.05,
			Size = Vector3.new(0.35, 0.35, len), CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to) }, f)
		local sheath = EnergyFX.Part({ Name = "BlinkSheath", Material = Enum.Material.ForceField, Color = LIME, Transparency = 0.1,
			Size = Vector3.new(1.1, 1.1, len), CFrame = beamPart.CFrame }, f)
		EnergyFX.Tween(beamPart, 0.28, { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) })
		EnergyFX.Tween(sheath, 0.32, { Transparency = 1, Size = Vector3.new(0.2, 0.2, len) })
		Debris:AddItem(beamPart, 0.35)
		Debris:AddItem(sheath, 0.4)
	end
	-- afterimage: a body-sized shimmer where you stood
	local ghost = EnergyFX.Part({ Name = "BlinkGhost", Material = Enum.Material.ForceField, Color = LIME, Transparency = 0.15,
		Size = Vector3.new(2.2, 5, 1.2), CFrame = CFrame.lookAt(from, from + Vector3.new(d.X, 0, d.Z) + Vector3.new(0, 0, 1e-3)) }, f)
	EnergyFX.Tween(ghost, 0.45, { Transparency = 1, Size = Vector3.new(2.8, 5.6, 1.6) })
	Debris:AddItem(ghost, 0.5)
	EnergyFX.Flash(to, { Color = WHITE, From = 0.5, To = 3, Life = 0.16, Folder = f, Light = { Color = LIME, Range = 16, Brightness = 4, Life = 0.3 } })
	EnergyFX.Sparks(EnergyFX.UpFrame(to, normal), 24, { Color0 = WHITE, Color1 = LIME, Spread = 90, Speed = NumberRange.new(10, 24), Life = NumberRange.new(0.2, 0.5), Size = 0.16 })
	burstAt(to, STYLES.Starfall, 30)
	EnergyFX.Sound(Config.Sounds.Blink, if isLocal then nil else to, { RollOffMin = Config.SoundRollOff.Min, RollOffMax = Config.SoundRollOff.Max })
end

-- a Harpoon speared you (you are the target): heavy thunk in your ears
function GrappleFX.Hooked(hunter: Instance?)
	EnergyFX.Sound(Config.Sounds.Hooked, nil)
end

-- every cable of this character (used when the server says another player's grapple ended)
function GrappleFX.ReleaseAll(character: Model)
	for _, s in shots do
		if s.Character == character then
			s:Release()
		end
	end
end

RunService:BindToRenderStep("VantageGrappleFX", Enum.RenderPriority.Last.Value + 1, step)

-- every launcher idles with a few motes in its hook's style and colours (client-only, re-added when the
-- launcher is rebuilt after a hook swap)
task.spawn(function()
	local CollectionService = game:GetService("CollectionService")
	while true do
		task.wait(1)
		local list = {}
		for _, plr in Players:GetPlayers() do
			if plr.Character then
				table.insert(list, plr.Character)
			end
		end
		for _, tag in { "VantageDummy", "VantageBot" } do
			for _, m in CollectionService:GetTagged(tag) do
				table.insert(list, m)
			end
		end
		for _, c in list do
			local l = c:FindFirstChild("VantageGrappleLauncher")
			local e = l and l:FindFirstChild("Emitter")
			local a = e and e:FindFirstChild("GrappleMuzzle")
			if a and not a:FindFirstChild("GrapplePFX") then
				useCol(c)
				local st = styleOf(c)
				local pe = particles(a, st, 5, st.Size * 0.45)
				pe.Speed = NumberRange.new(0.2, 0.6)
				pe.Acceleration = Vector3.new(0, 0.6, 0)
				pe.Drag = 1
			end
		end
	end
end)

return GrappleFX
