--!nocheck
--[[
	FarmStage v4 — the 3D half of the ICHOR FARM (2026-11-20).
	A deterministic, keyframed cinematic: every shot, pose, body position, hammer state, aura level and lighting value is a
	function of one timeline clock t, and one-shot effects/sounds are events at fixed times. So any moment can be frozen
	and inspected (Studio hook: player attribute FarmSeek = t; clear it to resume).

	FULL (11 s; first open each day, always in Studio):
	  0.00-3.00  WIND-UP at the player's own spot on the map: Mjölnir whirls round his fist faster and faster, the storm
	             gathers (sky darkens, rain, vortex, strikes), aura builds (Highlight, blue spirit fire, arcs, ground wind,
	             rising rocks), eyes ignite at 2.2 (face close-up), anticipation crouch.
	  3.00-8.00  LAUNCH + FLIGHT: impact frames, lightning pillar, speed-ramped lift-off seen from the ground, then a chase
	             camera behind him; sonic booms, a barrel roll, speed streaks; at 6.0 he becomes a streak of lightning.
	  8.00-11.0  LANDING: wide island shot, a star flares, the lightning column slams down, impact frames, dust; the Thor
	             landing kneel, eyes flare, he rises (from behind) and turns to the cauldron; glide to the farm framing.
	SHORT (3 s): the landing only.
	Then FARMING: every 5 s he raises Mjölnir, the sky darkens, a bolt crashes into the cauldron.
	Effects follow the Signatures rule: particles, beams, trails, highlights only (no primitive shapes); invisible carriers.
	The avatar (Vantage.Ichor.Avatars.u_<UserId>, AnimationConstraint or Motor6D joints) is posed with Transform.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Ichor = Vantage:WaitForChild("Ichor")
local VFX = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureVFX"))
local KB = VFX.KB
local player = Players.LocalPlayer

local V3, CF = Vector3.new, CFrame.new
local ANG = CFrame.Angles
local Y = Vector3.yAxis
local I = CFrame.identity
local GOLD = Color3.fromRGB(255, 190, 64)
local GOLD_HOT = Color3.fromRGB(255, 236, 170)
local ELEC = Color3.fromRGB(110, 190, 255)
local ELEC_HOT = Color3.fromRGB(225, 242, 255)
local GLOW = "rbxassetid://103142630740394"
local ORIGIN = V3(6000, 1400, -6000)
local HSCALE = 1.3
local GRIP = 0.85
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local TAU = math.pi * 2
local function cs(a, b) return ColorSequence.new(a, b or a) end
local function clamp01(x) return math.clamp(x, 0, 1) end
local function ease(t) t = clamp01(t) return t * t * (3 - 2 * t) end
local function easeIn(t) t = clamp01(t) return t * t * t end
local function easeOut(t) t = clamp01(t) return 1 - (1 - t) ^ 3 end
local function rnd(a, b) return a + math.random() * (b - a) end
local function seg(t, a, b) return clamp01((t - a) / (b - a)) end
local function lerp(a, b, k) return a + (b - a) * k end

-- timeline marks
local T_LAUNCH, T_STREAK, T_LAND, T_IMPACT, T_RISE, T_TURN, T_END = 3.0, 6.0, 8.0, 8.7, 9.85, 10.45, 11.0

-- sound library (all checked to load, 2026-11-20). { id, volume }
local SND = {
	Music = { 1835343134, 0.55 }, -- APM "Decimate The Enemy Tag 2": war drums, horns, rises (18 s)
	Riser = { 94077390731779, 0.9 }, -- 3.1 s riser
	Riser2 = { 101937236820642, 0.8 },
	DarkBraam = { 79894991988109, 1 },
	ElasticBraam = { 109288666701517, 0.9 },
	Sting = { 87681931953984, 0.8 }, -- APM "Vast Horizon - Sting"
	Strike = { 18650085033, 1 },
	ThunderHeavy = { 100307922248267, 1 },
	Artillery = { 9113169432, 0.8 },
	WindHowl = { 6544555787, 0.5 },
	PlasmaWind = { 9125742262, 0.7 },
	ImpactLarge = { 138174580847844, 1 },
	Downslam = { 94552730819110, 1 },
	Rubble = { 102757491685632, 0.9 },
	WindExplosion = { 105311054820133, 1 },
	MachineRise = { 9046345603, 0.6 },
}

local Stage = {}
Stage.__index = Stage
function Stage.new() return setmetatable({}, Stage) end

------------------------------------------------------------------ sound helpers (2D, owned by the stage)
function Stage:_snd(name, vol, speed, timePos)
	local e = SND[name]
	if not e or not self.SndFolder then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. e[1]
	s.Volume = e[2] * (vol or 1)
	s.PlaybackSpeed = speed or 1
	s.TimePosition = timePos or 0
	s.Parent = self.SndFolder
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	return s
end
function Stage:_loop(name, vol, speed)
	local s = self:_snd(name, 0, speed)
	if not s then return end
	s.Looped = true
	s:SetAttribute("Base", SND[name][2] * (vol or 1))
	return s
end
function Stage:_fade(s, vol, dur)
	if s and s.Parent then TweenService:Create(s, TweenInfo.new(dur or 0.4), { Volume = vol }):Play() end
end

------------------------------------------------------------------ lighting mood
local MOOD = {
	ClockTime = 17.35, Brightness = 2.4, ExposureCompensation = 0.1,
	OutdoorAmbient = Color3.fromRGB(150, 120, 110), Ambient = Color3.fromRGB(80, 64, 70),
}
local STORM = {
	ClockTime = 17.5, Brightness = 2.0, ExposureCompensation = 0,
	OutdoorAmbient = Color3.fromRGB(100, 115, 165), Ambient = Color3.fromRGB(64, 72, 108),
}
local ATM = { Density = 0.36, Offset = 0.2, Color = Color3.fromRGB(255, 205, 160), Decay = Color3.fromRGB(150, 96, 120), Glare = 0.7, Haze = 2.2 }
local ATM_STORM = { Density = 0.46, Offset = 0.1, Color = Color3.fromRGB(150, 170, 210), Decay = Color3.fromRGB(70, 80, 120), Glare = 0.2, Haze = 2.6 }

function Stage:_mood(on)
	if on then
		self.SavedLight = {}
		for k in MOOD do self.SavedLight[k] = Lighting[k] end
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		self.Atm = atm
		if atm then
			self.SavedAtm = {}
			for k in ATM do self.SavedAtm[k] = atm[k] end
		end
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		self.Dof = dof
		if dof then self.SavedDof = { Enabled = dof.Enabled, FarIntensity = dof.FarIntensity, NearIntensity = dof.NearIntensity, FocusDistance = dof.FocusDistance, InFocusRadius = dof.InFocusRadius } end
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "FarmGrade"; cc.Saturation = -0.3; cc.Contrast = 0.16; cc.Brightness = -0.03; cc.TintColor = Color3.fromRGB(255, 232, 206)
		cc.Parent = Lighting
		self.Grade = cc
		local ic = Instance.new("ColorCorrectionEffect")
		ic.Name = "FarmImpact"; ic.Enabled = false; ic.Saturation = -1; ic.Contrast = 2.2; ic.Brightness = 0.15; ic.TintColor = Color3.fromRGB(210, 228, 255)
		ic.Parent = Lighting
		self.ImpactCC = ic
		self:_stormMix(0)
	else
		if self.SavedLight then for k, v in self.SavedLight do Lighting[k] = v end end
		if self.Atm and self.SavedAtm then for k, v in self.SavedAtm do self.Atm[k] = v end end
		if self.Dof and self.SavedDof then for k, v in self.SavedDof do self.Dof[k] = v end end
		if self.Grade then self.Grade:Destroy() end
		if self.ImpactCC then self.ImpactCC:Destroy() end
		self.SavedLight, self.SavedAtm, self.SavedDof, self.Grade, self.ImpactCC = nil, nil, nil, nil, nil
	end
end

-- 0 = golden-hour farm mood, 1 = full storm. Applied every frame during the cinematic (deterministic).
function Stage:_stormMix(k)
	k = clamp01(k)
	self.StormK = k
	for key, a in MOOD do
		local b = STORM[key]
		if typeof(a) == "Color3" then Lighting[key] = a:Lerp(b, k) else Lighting[key] = lerp(a, b, k) end
	end
	if self.Atm then
		for key, a in ATM do
			local b = ATM_STORM[key]
			if typeof(a) == "Color3" then self.Atm[key] = a:Lerp(b, k) else self.Atm[key] = lerp(a, b, k) end
		end
	end
	if self.Grade then
		self.Grade.TintColor = Color3.fromRGB(255, 232, 206):Lerp(Color3.fromRGB(196, 214, 255), k)
		self.Grade.Saturation = lerp(-0.12, -0.25, k)
		self.Grade.Contrast = lerp(0.16, 0.3, k)
	end
end
-- tweened storm for the farming loop (outside the cinematic)
function Stage:_storm(on, dur)
	local from = self.StormK or 0
	local to = on and 0.8 or 0
	local nv = Instance.new("NumberValue"); nv.Value = from
	nv.Changed:Connect(function(v) if self.Folder then self:_stormMix(v) end end)
	local tw = TweenService:Create(nv, TweenInfo.new(dur or 1, Enum.EasingStyle.Sine), { Value = to })
	tw.Completed:Connect(function() nv:Destroy() end)
	tw:Play()
end

-- depth of field for close-ups (dist = focus distance, far = blur strength)
function Stage:_dof(dist, far)
	local d = self.Dof
	if not d then return end
	d.Enabled = true
	d.FocusDistance = dist
	d.InFocusRadius = math.max(2, dist * 0.35)
	d.FarIntensity = far
	d.NearIntensity = 0
end

------------------------------------------------------------------ helpers
local function carrier(parent, cf, name, size)
	local p = Instance.new("Part")
	p.Name = name or "FX"; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Transparency = 1; p.Size = size or V3(0.2, 0.2, 0.2); p.CFrame = cf; p.Parent = parent
	return p
end

------------------------------------------------------------------ build
function Stage:_build()
	local folder = Instance.new("Folder")
	folder.Name = "FarmStage"
	folder.Parent = Workspace
	self.Folder = folder
	local sf = Instance.new("Folder"); sf.Name = "FarmSounds"; sf.Parent = SoundService
	self.SndFolder = sf
	local scene = Ichor.FarmScene.Scene:Clone()
	scene:PivotTo(CF(ORIGIN))
	for _, d in scene:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = d.Transparency < 0.9; d.CanTouch = false end
	end
	scene.Parent = folder
	self.Scene = scene
	self.CauldronM = scene:FindFirstChild("Cauldron")
	self.CauldronCF = self.CauldronM and self.CauldronM:GetPivot()
	local A = function(n) return scene:GetAttribute(n) end
	local C = ORIGIN + A("Cauldron")
	self.C = V3(C.X, ORIGIN.Y + A("IslandTop"), C.Z)
	self.Floor, self.Top = ORIGIN.Y + A("BowlFloor"), ORIGIN.Y + A("BowlTop")
	self.R0, self.R1 = A("BowlR0"), A("BowlR1")
	self.LaunchG = ORIGIN + A("Launch")
	self.LedgeC = ORIGIN + (A("LedgeC") or A("Launch"))
	local k = (V3(self.LaunchG.X, 0, self.LaunchG.Z) - V3(self.C.X, 0, self.C.Z)).Unit
	k = (CFrame.fromAxisAngle(Y, math.rad(-18)) * k).Unit
	self.K = k
	self.RightK = (-k):Cross(Y).Unit
	self.LandG = self.C - self.RightK * 5.2 + k * 1.3
	self.Ct = V3(self.C.X, self.Top, self.C.Z)

	-- liquid (particles only)
	local liq = carrier(folder, CF(self.C.X, self.Floor, self.C.Z), "Liquid")
	self.Liq = liq
	self.LiqAtt = Instance.new("Attachment"); self.LiqAtt.Parent = liq
	local function flat(props)
		local t = { Orientation = Enum.ParticleOrientation.VelocityPerpendicular, LockedToPart = true, ZOffset = 0,
			EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(0.001), SpreadAngle = Vector2.zero }
		for a, b in props do t[a] = b end
		return VFX.Emitter(liq, t)
	end
	self.Pool = flat({ Texture = GLOW, Color = cs(GOLD), LightEmission = 0.75, Brightness = 3.2, Rate = 8, Lifetime = NumberRange.new(1.4),
		Size = NS(4), Transparency = NS({ NK(0, 1), NK(0.3, 0.05), NK(0.7, 0.05), NK(1, 1) }) })
	self.PoolCore = flat({ Texture = GLOW, Color = cs(GOLD_HOT), LightEmission = 1, Brightness = 3.2, Rate = 4, Lifetime = NumberRange.new(1.2),
		Size = NS(2.2), Transparency = NS({ NK(0, 1), NK(0.3, 0.2), NK(0.7, 0.2), NK(1, 1) }) })
	self.Swirl = flat({ Texture = KB.Rift, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop, FlipbookFramerate = NumberRange.new(10),
		Color = cs(Color3.fromRGB(255, 214, 120)), LightEmission = 1, Brightness = 1.8, Rate = 1.2, Lifetime = NumberRange.new(2.5),
		Size = NS(3), Transparency = NS({ NK(0, 1), NK(0.3, 0.4), NK(0.7, 0.4), NK(1, 1) }), RotSpeed = NumberRange.new(25, 40), Rotation = NumberRange.new(0, 360) })
	self.Pops = flat({ Texture = KB.WaterRing, Color = cs(GOLD_HOT), LightEmission = 1, Brightness = 2, Rate = 3, Lifetime = NumberRange.new(0.5, 0.7),
		Size = NS(0.2, 1.1), Transparency = NS(0.1, 1), ZOffset = 0.05 })
	self.Bubbles = VFX.Emitter(liq, { Texture = KB.FireDots, Color = cs(GOLD_HOT, GOLD), LightEmission = 1, Brightness = 2, Rate = 10,
		Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
		Size = NS({ NK(0, 0.25), NK(1, 0) }), Transparency = NS(0, 1), Acceleration = V3(0, -2, 0) })
	self.Embers = VFX.Emitter(liq, { Texture = KB.Star, Color = cs(GOLD_HOT, GOLD), LightEmission = 1, Brightness = 2.2, Rate = 5,
		Lifetime = NumberRange.new(2, 3.4), Speed = NumberRange.new(1.5, 4), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top,
		Size = NS({ NK(0, 0.35), NK(1, 0) }), Transparency = NS({ NK(0, 0.2), NK(1, 1) }), Drag = 0.6 })
	self.Steam = VFX.Emitter(liq, { Texture = KB.SmokeFlip, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = cs(Color3.fromRGB(255, 226, 180)), LightEmission = 0.4, LightInfluence = 0.4, Rate = 3, Lifetime = NumberRange.new(2.4, 3.4),
		Speed = NumberRange.new(1.6, 2.8), SpreadAngle = Vector2.new(18, 18), EmissionDirection = Enum.NormalId.Top,
		Size = NS({ NK(0, 2), NK(1, 6) }), Transparency = NS({ NK(0, 1), NK(0.25, 0.72), NK(1, 1) }), RotSpeed = NumberRange.new(-20, 20), Rotation = NumberRange.new(0, 360) })
	self.LiqArcs = VFX.Emitter(liq, { Texture = KB.Arc2, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, GOLD_HOT),
		LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0), Size = NS(1.2, 2.4), Rotation = NumberRange.new(0, 360) })
	local light = Instance.new("PointLight")
	light.Color = GOLD; light.Range = 16; light.Brightness = 1.5; light.Shadows = false
	light.Parent = liq
	self.Light = light

	-- floating amount over the cauldron
	local bb = Instance.new("BillboardGui")
	bb.Name = "FarmAmount"; bb.Size = UDim2.fromOffset(240, 84); bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.MaxDistance = 400; bb.ResetOnSpawn = false
	bb.Adornee = carrier(folder, CF(self.C.X, self.Top + 3.6, self.C.Z), "AmountAnchor")
	bb.Enabled = false
	bb.Parent = player:WaitForChild("PlayerGui")
	self.AmountGui = bb

	-- sea of clouds + motes
	local cloud = carrier(folder, CF(ORIGIN + V3(0, -62, 0)), "Clouds", V3(520, 1, 520))
	VFX.Emitter(cloud, { Texture = KB.SmokeBall, Color = cs(Color3.fromRGB(255, 236, 222), Color3.fromRGB(255, 210, 196)),
		LightEmission = 0.15, LightInfluence = 0.85, Rate = 16, Lifetime = NumberRange.new(26, 34), Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(90, 90), EmissionDirection = Enum.NormalId.Top, Shape = Enum.ParticleEmitterShape.Box,
		Size = NS({ NK(0, 60), NK(1, 110) }), Transparency = NS({ NK(0, 1), NK(0.15, 0.3), NK(0.85, 0.3), NK(1, 1) }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-2, 2), Acceleration = V3(0.4, -0.02, 0.1) }):Emit(260)
	local motes = carrier(folder, CF(ORIGIN + V3(0, 30, 0)), "Motes", V3(90, 40, 90))
	VFX.Emitter(motes, { Texture = KB.Star, Color = cs(GOLD_HOT), LightEmission = 1, Brightness = 1.6, Rate = 10, Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(0.3, 1), SpreadAngle = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Box,
		Size = NS({ NK(0, 0), NK(0.5, 0.3), NK(1, 0) }), Transparency = NS(0.2), Acceleration = V3(0, 0.25, 0) })

	-- flash / fade / letterbox overlay
	local sg = Instance.new("ScreenGui")
	sg.Name = "FarmStageFX"; sg.IgnoreGuiInset = true; sg.DisplayOrder = 29; sg.ResetOnSpawn = false
	local fl = Instance.new("Frame")
	fl.Name = "Flash"; fl.Size = UDim2.fromScale(1, 1); fl.BackgroundColor3 = Color3.new(1, 1, 1); fl.BackgroundTransparency = 1; fl.BorderSizePixel = 0; fl.ZIndex = 5
	fl.Parent = sg
	local fade = fl:Clone(); fade.Name = "Fade"; fade.BackgroundColor3 = Color3.new(0, 0, 0); fade.ZIndex = 6; fade.Parent = sg
	local barT = fl:Clone(); barT.Name = "BarT"; barT.BackgroundColor3 = Color3.new(0, 0, 0); barT.BackgroundTransparency = 0; barT.Size = UDim2.new(1, 0, 0, 0); barT.ZIndex = 7; barT.Parent = sg
	local barB = barT:Clone(); barB.Name = "BarB"; barB.AnchorPoint = Vector2.new(0, 1); barB.Position = UDim2.fromScale(0, 1); barB.Parent = sg
	sg.Parent = player:WaitForChild("PlayerGui")
	self.FXGui, self.FlashF, self.FadeF, self.BarT, self.BarB = sg, fl, fade, barT, barB

	self:_avatar()
	self:SetFill(self.Fill or 0, true)
end

function Stage:_bars(on)
	local h = on and UDim2.new(1, 0, 0.1, 0) or UDim2.new(1, 0, 0, 0)
	TweenService:Create(self.BarT, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = h }):Play()
	TweenService:Create(self.BarB, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = h }):Play()
end

------------------------------------------------------------------ avatar + aura
local JOINTS = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "RightHip", "RightKnee", "LeftHip", "LeftKnee" }
local POSE = {
	Idle = { Waist = ANG(0, 0.18, 0), Neck = ANG(-0.06, -0.18, 0), RightShoulder = ANG(0.1, 0, 0.16), RightElbow = ANG(0.3, 0, 0), LeftShoulder = ANG(0.06, 0, -0.1), LeftElbow = ANG(0.2, 0, 0),
		RightHip = ANG(0, 0, 0.06), LeftHip = ANG(0, 0, -0.06) },
	-- power stance for the whirl: wide, low, chest up, off hand clenched forward
	Spin = { Root = CF(0, -0.45, 0), Waist = ANG(-0.06, 0.28, 0), Neck = ANG(0.08, -0.24, 0), RightShoulder = ANG(0.42, 0, 0.62), RightElbow = ANG(0.12, 0, 0),
		LeftShoulder = ANG(0.75, 0, -0.5), LeftElbow = ANG(1.0, 0, 0),
		RightHip = ANG(0.36, 0, 0.32), RightKnee = ANG(-0.62, 0, 0), LeftHip = ANG(0.36, 0, -0.32), LeftKnee = ANG(-0.62, 0, 0) },
	Charge = { Root = CF(0, -0.95, 0), Waist = ANG(-0.28, 0.32, 0), Neck = ANG(0.3, -0.25, 0), RightShoulder = ANG(0.42, 0, 0.62), RightElbow = ANG(0.12, 0, 0),
		LeftShoulder = ANG(1.0, 0, -0.75), LeftElbow = ANG(1.25, 0, 0),
		RightHip = ANG(0.8, 0, 0.34), RightKnee = ANG(-1.3, 0, 0), LeftHip = ANG(0.8, 0, -0.34), LeftKnee = ANG(-1.3, 0, 0) },
	Fly = { Waist = ANG(0.05, 0, 0), Neck = ANG(0.3, 0, 0), RightShoulder = ANG(math.pi - 0.08, 0, 0.04), RightElbow = I, LeftShoulder = ANG(-0.05, 0, -0.14), LeftElbow = ANG(0.1, 0, 0),
		RightHip = ANG(-0.12, 0, 0.04), RightKnee = ANG(-0.3, 0, 0), LeftHip = ANG(-0.2, 0, -0.04), LeftKnee = ANG(-0.5, 0, 0) },
	Slam = { Root = CF(0, -1.05, 0), Waist = ANG(-0.55, 0, 0), Neck = ANG(0.42, 0, 0), RightShoulder = ANG(0.95, 0, 0.3), RightElbow = ANG(0.25, 0, 0), LeftShoulder = ANG(-0.5, 0, -0.85), LeftElbow = ANG(0.3, 0, 0),
		RightHip = ANG(1.35, 0, 0.12), RightKnee = ANG(-1.65, 0, 0), LeftHip = ANG(0.15, 0, -0.18), LeftKnee = ANG(-1.85, 0, 0) },
	Tall = { Waist = ANG(0.1, -0.1, 0), Neck = ANG(0.18, 0.1, 0), RightShoulder = ANG(0.35, 0, 0.3), RightElbow = ANG(0.4, 0, 0), LeftShoulder = ANG(0.05, 0, -0.18), LeftElbow = ANG(0.15, 0, 0),
		RightHip = ANG(0, 0, 0.1), LeftHip = ANG(0, 0, -0.1) },
	Ready = { Waist = ANG(0.06, 0.12, 0), Neck = ANG(0.06, 0.05, 0), RightShoulder = ANG(0.3, 0, 0.24), RightElbow = ANG(0.55, 0, 0), LeftShoulder = ANG(0.12, 0, -0.2), LeftElbow = ANG(0.35, 0, 0),
		RightHip = ANG(0.08, 0, 0.12), RightKnee = ANG(-0.15, 0, 0), LeftHip = ANG(-0.06, 0, -0.12), LeftKnee = ANG(-0.08, 0, 0) },
	Raise = { Waist = ANG(0.18, 0.1, 0), Neck = ANG(0.45, 0, 0), RightShoulder = ANG(math.pi - 0.15, 0, 0.15), RightElbow = I, LeftShoulder = ANG(0.25, 0, -0.45), LeftElbow = ANG(0.5, 0, 0),
		RightHip = ANG(0, 0, 0.14), LeftHip = ANG(0, 0, -0.14) },
}

-- keyframes for the cinematic: { t, pose, easing into this key }
local KEYS = {
	{ 0.0, "Spin" }, { 2.55, "Spin" }, { 2.88, "Charge", "in" }, { 2.99, "Charge" },
	{ 3.06, "Fly", "out" }, { 7.99, "Fly" },
	{ 8.0, "Fly" }, { 8.69, "Fly" }, { 8.7, "Slam", "snap" }, { T_RISE, "Slam" },
	{ T_RISE + 0.5, "Tall", "out" }, { T_TURN + 0.1, "Tall" }, { T_END, "Ready" },
}

function Stage:_avatar()
	local folder = Ichor:FindFirstChild("Avatars")
	local src = folder and folder:FindFirstChild("u_" .. player.UserId)
	if not src then
		local ch = player.Character
		if ch and ch:FindFirstChild("HumanoidRootPart") then src = ch end
	end
	if not src then return end
	local was = src.Archivable
	src.Archivable = true
	local rig = src:Clone()
	src.Archivable = was
	if not rig then return end
	for _, d in rig:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Animator") or d:IsA("ForceField") or d:IsA("Tool") or d:IsA("BillboardGui") then d:Destroy() end
	end
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false; hum.RequiresNeck = false
		hum.MaxHealth = math.huge; hum.Health = math.huge
		pcall(function() hum.AutomaticScalingEnabled = false end)
		hum.PlatformStand = true
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if not hrp then rig:Destroy() return end
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = d == hrp; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true end
	end
	rig.Name = "FarmAvatar"
	rig.Parent = self.Folder
	self.Rig, self.HRP = rig, hrp
	self.Hand = rig:FindFirstChild("RightHand")
	self.Head = rig:FindFirstChild("Head")
	self.J = {}
	for _, d in rig:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(JOINTS, d.Name) then
			self.J[d.Name] = d
			if d:IsA("AnimationConstraint") then pcall(function() d.IsKinematic = true end) end
		end
	end
	self.HipH = (hum and hum.HipHeight or 2) + hrp.Size.Y / 2
	self.Cur = {}
	for _, n in JOINTS do self.Cur[n] = I end
	self.Target, self.PoseRate = POSE.Ready, 8

	-- aura outline (Highlight) on the body and the hammer
	local hl = Instance.new("Highlight")
	hl.Name = "Aura"; hl.Adornee = rig; hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = ELEC; hl.OutlineColor = ELEC_HOT; hl.FillTransparency = 1; hl.OutlineTransparency = 1
	hl.Parent = self.Folder
	self.HL = hl

	-- eyes
	self.Eyes = {}
	local head = self.Head
	if head then
		local hs = head.Size.Y / 1.2
		for _, sx in { -1, 1 } do
			local a = Instance.new("Attachment"); a.Name = "Eye"; a.Position = V3(0.15 * sx * hs, 0.15 * hs, -0.7 * hs); a.Parent = head
			local halo = VFX.Emitter(a, { Texture = KB.BigGlow, Color = cs(Color3.fromRGB(40, 140, 255)), LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.08, 0.12),
				Speed = NumberRange.new(0), Size = NS(1.1), LockedToPart = true, ZOffset = 0.2 })
			local core = VFX.Emitter(a, { Texture = KB.BigGlow, Color = cs(ELEC_HOT), LightEmission = 1, Brightness = 6, Rate = 0, Lifetime = NumberRange.new(0.08, 0.12),
				Speed = NumberRange.new(0), Size = NS(0.5), LockedToPart = true, ZOffset = 0.3 })
			local flare = VFX.Emitter(a, { Texture = KB.Flare, Color = cs(Color3.fromRGB(60, 160, 255)), LightEmission = 1, Brightness = 6, Rate = 0, Lifetime = NumberRange.new(0.08, 0.12),
				Speed = NumberRange.new(0), Size = NS(1.1), Squash = NS(-1.6), LockedToPart = true, ZOffset = 0.25 })
			local t0 = Instance.new("Attachment"); t0.Position = a.Position + V3(0, 0.05, 0); t0.Parent = head
			local t1 = Instance.new("Attachment"); t1.Position = a.Position - V3(0, 0.05, 0); t1.Parent = head
			local tr = Instance.new("Trail"); tr.Attachment0, tr.Attachment1 = t0, t1; tr.Color = cs(ELEC_HOT, ELEC); tr.LightEmission = 1; tr.LightInfluence = 0
			tr.Lifetime = 0.22; tr.Transparency = NS(0.05, 1); tr.MinLength = 0.02; tr.Enabled = false; tr.Parent = head
			table.insert(self.Eyes, { Core = core, Flare = flare, Halo = halo, Trail = tr })
		end
		local el = Instance.new("PointLight"); el.Color = ELEC; el.Range = 6; el.Brightness = 0; el.Parent = head
		self.EyeLight = el
		self.HeadArcs = VFX.Emitter(head, { Texture = KB.Arc1, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
			LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0), Size = NS(1.2, 2), Rotation = NumberRange.new(0, 360), LockedToPart = true })
	end

	-- spirit-fire aura rising off the body, arcs, sparks, glow
	self.Fire = {}
	for _, pn in { "UpperTorso", "LowerTorso", "RightUpperArm", "LeftUpperArm", "RightUpperLeg", "LeftUpperLeg" } do
		local part = rig:FindFirstChild(pn)
		if part then
			local big = pn == "UpperTorso" or pn == "LowerTorso"
			local e = VFX.Emitter(part, { Texture = KB.BlueFire, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
				LightEmission = 1, Brightness = 2.2, Rate = 0, Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(25, 25), Acceleration = V3(0, 9, 0), Size = NS({ NK(0, big and 2.6 or 1.6), NK(1, 0.4) }),
				Transparency = NS({ NK(0, 0.15), NK(0.7, 0.4), NK(1, 1) }), ZOffset = -0.4, Shape = Enum.ParticleEmitterShape.Box,
				Rotation = NumberRange.new(-15, 15) })
			table.insert(self.Fire, { E = e, W = big and 1 or 0.45 })
		end
	end
	self.Wisps = VFX.Emitter(hrp, { Texture = KB.Air, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 0.9, Brightness = 2, Rate = 0, Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(60, 60), Size = NS(4, 6.5), Transparency = NS(0.35, 1), Rotation = NumberRange.new(0, 360), Shape = Enum.ParticleEmitterShape.Box })
	self.BodyArcs = VFX.Emitter(hrp, { Texture = KB.Arc1, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0), Size = NS(1.8, 3.2), Rotation = NumberRange.new(0, 360),
		Shape = Enum.ParticleEmitterShape.Box, LockedToPart = true })
	self.BodyArcs2 = VFX.Emitter(hrp, { Texture = KB.Arc2, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0), Size = NS(2.5, 4.5), Rotation = NumberRange.new(0, 360),
		Shape = Enum.ParticleEmitterShape.Box, LockedToPart = true })
	self.BodySparks = VFX.Emitter(hrp, { Texture = KB.Sparks, Color = cs(ELEC_HOT), LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180), Size = NS(0.2, 0), Drag = 3, Shape = Enum.ParticleEmitterShape.Box })
	self.Implode = VFX.Emitter(hrp, { Texture = KB.WavesIn, Color = cs(ELEC_HOT, ELEC), LightEmission = 1, Brightness = 2, Rate = 0, Lifetime = NumberRange.new(0.45),
		Speed = NumberRange.new(0), Size = NS(12, 0.5), Transparency = NS(0.6, 0), Rotation = NumberRange.new(0, 360), LockedToPart = true })
	self.Aura = VFX.Emitter(hrp, { Texture = KB.BigGlow, Color = cs(ELEC), LightEmission = 1, Brightness = 1.5, Rate = 0, Lifetime = NumberRange.new(0.2, 0.3),
		Speed = NumberRange.new(0), Size = NS(8, 10), Transparency = NS(0.6, 1), LockedToPart = true, ZOffset = -1 })
	local bl = Instance.new("PointLight"); bl.Color = ELEC; bl.Range = 14; bl.Brightness = 0; bl.Parent = hrp
	self.BodyLight = bl

	-- Mjölnir
	local hm = Vantage.Signatures.Assets.SIG_Mjolnir:Clone()
	hm:ScaleTo(HSCALE)
	local hp = hm:FindFirstChildWhichIsA("BasePart", true)
	for _, d in hm:GetDescendants() do if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false end end
	hm.Parent = self.Folder
	self.Hammer, self.HamPart = hm, hp
	local hhl = hl:Clone(); hhl.Name = "HammerAura"; hhl.Adornee = hm; hhl.Parent = self.Folder
	self.HHL = hhl
	local head2 = Instance.new("Attachment"); head2.Name = "Head"; head2.Position = V3(0.87 * HSCALE, 0, 0); head2.Parent = hp
	self.HeadAtt = head2
	local ta = Instance.new("Attachment"); ta.Position = V3(0.87 * HSCALE, 0.95 * HSCALE, 0); ta.Parent = hp
	local tb = Instance.new("Attachment"); tb.Position = V3(0.87 * HSCALE, -0.95 * HSCALE, 0); tb.Parent = hp
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = ta, tb
	tr.Color = cs(ELEC_HOT, ELEC); tr.LightEmission = 1; tr.LightInfluence = 0; tr.Lifetime = 0.16; tr.FaceCamera = false
	tr.Transparency = NS({ NK(0, 0.05), NK(1, 1) }); tr.Enabled = false
	tr.Parent = hp
	self.HamTrail = tr
	self.HamArcs = VFX.Emitter(head2, { Texture = KB.Arc1, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 1, Brightness = 3, Rate = 0, Lifetime = NumberRange.new(0.18, 0.28), Speed = NumberRange.new(0), Size = NS(1.8, 2.8), Rotation = NumberRange.new(0, 360) })
	self.HamSparks = VFX.Emitter(head2, { Texture = KB.Sparks, Color = cs(ELEC_HOT), LightEmission = 1, Brightness = 3, Rate = 0,
		Lifetime = NumberRange.new(0.2, 0.45), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180), Size = NS(0.25, 0), Drag = 4 })
	self.HamGlow = VFX.Emitter(head2, { Texture = KB.BigGlow, Color = cs(ELEC), LightEmission = 1, Brightness = 2, Rate = 0, Lifetime = NumberRange.new(0.12, 0.18),
		Speed = NumberRange.new(0), Size = NS(3.5, 5), Transparency = NS(0.4, 1), LockedToPart = true })
	local hl2 = Instance.new("PointLight"); hl2.Color = ELEC; hl2.Range = 14; hl2.Brightness = 0; hl2.Parent = head2
	self.HamLight = hl2
	-- the whirl disc: a slash-ring sprite in the whirl's plane at the fist
	local disc = carrier(self.Folder, CF(), "WhirlDisc")
	self.Disc = disc
	self.DiscE = VFX.Emitter(disc, { Texture = KB.SlashRing, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 1, Brightness = 2.5, Rate = 0, Lifetime = NumberRange.new(0.16, 0.22), Speed = NumberRange.new(0.01), EmissionDirection = Enum.NormalId.Front,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Size = NS(7.2), Transparency = NS(0.15, 1), LockedToPart = true, Rotation = NumberRange.new(0, 360) })
	self.DiscE2 = VFX.Emitter(disc, { Texture = KB.Crescents, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 1, Brightness = 2.5, Rate = 0, Lifetime = NumberRange.new(0.14, 0.2), Speed = NumberRange.new(0.01), EmissionDirection = Enum.NormalId.Front,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Size = NS(7.8), Transparency = NS(0.3, 1), LockedToPart = true, Rotation = NumberRange.new(0, 360) })
	-- crackle beam hand -> hammer head, and the bolt hammer -> liquid
	local bh = Instance.new("Attachment"); bh.Parent = self.Hand or hrp
	local function bolt(a0, a1, w0, w1, col)
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.Texture = KB.Bolt; b.TextureMode = Enum.TextureMode.Stretch; b.LightEmission = 1; b.LightInfluence = 0
		b.Color = cs(col or ELEC_HOT); b.Width0, b.Width1 = w0, w1; b.FaceCamera = true; b.Enabled = false; b.Segments = 12
		b.Parent = hp
		return b
	end
	self.HamBeam = bolt(bh, head2, 1, 0.7)
	self.Chan = { bolt(head2, self.LiqAtt, 1.6, 1.2), bolt(head2, self.LiqAtt, 0.8, 0.6, ELEC) }
	-- flight trails + comet
	local b0 = Instance.new("Attachment"); b0.Position = V3(-1, 0, 0); b0.Parent = hrp
	local b1 = Instance.new("Attachment"); b1.Position = V3(1, 0, 0); b1.Parent = hrp
	local bt = Instance.new("Trail")
	bt.Attachment0, bt.Attachment1 = b0, b1
	bt.Color = cs(ELEC_HOT, ELEC); bt.LightEmission = 1; bt.LightInfluence = 0; bt.Lifetime = 0.5; bt.Transparency = NS({ NK(0, 0.15), NK(1, 1) })
	bt.WidthScale = NS(1.4, 0.1); bt.Enabled = false
	bt.Parent = hrp
	self.BodyTrail = bt
	self.Comet = VFX.Emitter(hrp, { Texture = KB.Air, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC),
		LightEmission = 1, Brightness = 2.5, Rate = 0, Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(0), Size = NS(5, 9), Transparency = NS(0.2, 1) })
	self.HammerMode = "hand"
	self.SpinA = 0
	self.Body = CF(self.LandG + V3(0, self.HipH, 0)) * self:_faceCauldron()
end

function Stage:_faceCam()
	local look = (CFrame.fromAxisAngle(Y, math.rad(28)) * self.K).Unit
	return CFrame.lookAt(Vector3.zero, look).Rotation
end
function Stage:_faceCauldron()
	local d = V3(self.C.X - self.LandG.X, 0, self.C.Z - self.LandG.Z).Unit
	return CFrame.lookAt(Vector3.zero, d).Rotation
end

function Stage:_pose(name, rate)
	self.Target = POSE[name] or POSE.Idle
	self.PoseRate = rate or 8
	self.Keyed = nil
end

-- aura level 0..1: outline, spirit fire, arcs, sparks, glow
function Stage:_aura(a)
	a = clamp01(a)
	self.AuraK = a
	if self.HL then
		self.HL.OutlineTransparency = 1 - 0.95 * math.min(1, a * 1.6)
		self.HL.FillTransparency = 1
		self.HHL.OutlineTransparency = self.HL.OutlineTransparency
		self.HHL.FillTransparency = 1 - 0.25 * a
	end
	for _, f in self.Fire or {} do f.E.Rate = 70 * a * f.W end
	if self.Wisps then
		self.Wisps.Rate = 14 * a
		self.BodyArcs.Rate, self.BodyArcs2.Rate = 6 + 40 * a, 16 * a
		self.BodySparks.Rate = 50 * a
		self.Aura.Rate = 22 * a
		self.BodyLight.Brightness = 1.5 * a
		if self.HeadArcs then self.HeadArcs.Rate = 10 * a end
	end
end

function Stage:_eyes(k) -- 0..1
	for _, e in self.Eyes or {} do
		e.Core.Rate, e.Flare.Rate = k > 0.05 and 40 or 0, k > 0.05 and 40 or 0
		e.Halo.Rate = k > 0.05 and 40 or 0
		e.Halo.Size = NS(0.5 + 0.8 * k)
		e.Core.Size = NS(0.25 + 0.15 * k)
		e.Flare.Size = NS(0.8 + 2.0 * k)
		e.Trail.Enabled = k > 0.05
	end
	if self.EyeLight then self.EyeLight.Brightness = 1 * k end
end

function Stage:_visible(on)
	local m = on and 0 or 1
	for _, inst in { self.Rig, self.Hammer } do
		if inst then
			for _, d in inst:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = m end
			end
		end
	end
	if self.HL then self.HL.Enabled = on; self.HHL.Enabled = on end
	self.Hidden = not on
end

------------------------------------------------------------------ rig stepping
-- pose from the keyframe table at time t (cinematic) or from the lerp target (farming)
local function keyPose(t)
	local a, b = KEYS[1], KEYS[#KEYS]
	for i = 1, #KEYS - 1 do
		if t >= KEYS[i][1] and t <= KEYS[i + 1][1] then a, b = KEYS[i], KEYS[i + 1] break end
	end
	if t < KEYS[1][1] then return POSE[KEYS[1][2]], POSE[KEYS[1][2]], 0 end
	if t > KEYS[#KEYS][1] then return POSE[b[2]], POSE[b[2]], 1 end
	local u = (t - a[1]) / math.max(1e-3, b[1] - a[1])
	local mode = b[3]
	if mode == "snap" then u = 1 elseif mode == "in" then u = easeIn(u) elseif mode == "out" then u = easeOut(u) else u = ease(u) end
	return POSE[a[2]], POSE[b[2]], u
end

function Stage:_stepRig(dt, t)
	if not self.Rig then return end
	self.HRP.CFrame = self.Body
	local breathe = math.sin(t * 1.6) * 0.025
	local pa, pb, u
	if self.Keyed then pa, pb, u = keyPose(self.Keyed) end
	local k = 1 - math.exp(-self.PoseRate * dt)
	for _, n in JOINTS do
		local j = self.J[n]
		if j and not j:IsDescendantOf(self.Rig) then
			j = nil
			for _, d in self.Rig:GetDescendants() do if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and d.Name == n then j = d break end end
			self.J[n] = j
		end
		if j then
			if pa then
				self.Cur[n] = (pa[n] or I):Lerp(pb[n] or I, u)
			else
				self.Cur[n] = self.Cur[n]:Lerp(self.Target[n] or I, k)
			end
			if self.HammerMode == "spin" and n == "RightShoulder" then
				self.Cur[n] = ANG(0.42 + 0.14 * math.sin(self.SpinA), 0, 0.62 + 0.08 * math.cos(self.SpinA))
			elseif self.HammerMode == "spin" and n == "RightElbow" then
				self.Cur[n] = ANG(0.12, 0, 0)
			end
			local extra = (n == "Waist" and ANG(breathe, 0, 0)) or (n == "Neck" and ANG(-breathe * 0.6, 0, 0)) or I
			if self.HammerMode == "spin" and n == "Waist" then extra = extra * ANG(0, math.sin(self.SpinA - 0.6) * 0.08, 0) end
			j.Transform = self.Cur[n] * extra
		end
	end
	local hand = self.Hand
	if hand and self.HamPart then
		if self.HammerMode == "spin" then
			local bodyCF = self.Body
			local radial = (bodyCF.UpVector * math.cos(self.SpinA) + bodyCF.LookVector * math.sin(self.SpinA)).Unit
			local g = CFrame.fromMatrix(hand.Position, bodyCF.RightVector, radial)
			-- handle along the whirl's radius, striking faces leading the swing
			self.HamPart.CFrame = g * CF(0, GRIP * HSCALE, 0) * ANG(0, 0, math.pi / 2) * ANG(math.pi / 2, 0, 0)
			self.Disc.CFrame = VFX.Facing(hand.Position + bodyCF.RightVector * 0.15, bodyCF.RightVector)
		else
			local g = hand.CFrame * ANG(math.pi, 0, 0) * CF(0, 0.12, 0)
			if self.HammerMode == "twirl" then
				g = hand.CFrame * ANG(self.SpinA, 0, 0) * ANG(math.pi, 0, 0) * CF(0, 0.12, 0)
			end
			self.HamPart.CFrame = g * CF(0, GRIP * HSCALE, 0) * ANG(0, 0, math.pi / 2) * ANG(math.pi / 2, 0, 0)
		end
	end
	if self.Channeling then
		for i, b in self.Chan do
			b.Enabled = math.random() < 0.8
			b.CurveSize0, b.CurveSize1 = rnd(-3, 3), rnd(-2, 2)
			b.Width0 = (i == 1 and 1.6 or 0.8) * rnd(0.6, 1.3) * (self.ChanBoost or 1)
		end
	else
		for _, b in self.Chan do b.Enabled = false end
	end
end

------------------------------------------------------------------ liquid
function Stage:SetFill(f, instant)
	self.FillGoal = math.clamp(f or 0, 0, 1)
	if instant or not self.Fill then self.Fill = self.FillGoal end
end
function Stage:_stepLiquid(dt, t)
	if not self.Liq then return end
	self.Fill += (self.FillGoal - self.Fill) * (1 - math.exp(-(self.FillRate or 1.5) * dt))
	local f = self.Fill
	local y = self.Floor + (self.Top - self.Floor) * f + math.sin(t * 2.2) * 0.04
	self.Liq.CFrame = CF(self.C.X, y, self.C.Z)
	local r = self.R0 + (self.R1 - self.R0) * f
	local on = f > 0.015
	self.Pool.Enabled, self.PoolCore.Enabled, self.Swirl.Enabled, self.Pops.Enabled = on, on, on, on
	self.Pool.Size = NS(r * 2.3)
	self.PoolCore.Size = NS(r * 1.3)
	self.Swirl.Size = NS(r * 1.9)
	local surge = self.Surge or 0
	self.Bubbles.Rate = (if on then 4 + 14 * f else 0) + surge * 40
	self.Embers.Rate = 2 + 8 * f + surge * 20
	self.Steam.Rate = 1 + 3.5 * f
	self.LiqArcs.Rate = (if self.Channeling then 10 else 0) + surge * 30
	self.Light.Brightness = 0.6 + 2.6 * f + math.sin(t * 3.1) * 0.15 + surge * 4
	self.Light.Range = 10 + 10 * f + surge * 8
	self.Surge = math.max(0, surge - dt * 1.6)
	if f > 0.995 and (self.NextFullPulse or 0) < t then
		self.NextFullPulse = t + 2.4
		VFX.GlowColumn(self.Ct, GOLD, 12, 3.4, 1.6, 1.2)
	end
end

------------------------------------------------------------------ camera
function Stage:_finalCam(t)
	local pos = self.Ct + self.K * 15 + Y * 9.2 - self.RightK * 3.4 + V3(math.sin(t * 0.21) * 0.35, math.sin(t * 0.33) * 0.22, 0)
	local look = self.Ct + self.RightK * 1.4 - Y * 2.8
	return CFrame.lookAt(pos, look), 50
end
function Stage:_safeCam(target, want)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { self.Rig, self.Hammer }
	if self.HiddenCharModel then table.insert(ex, self.HiddenCharModel) end
	rp.FilterDescendantsInstances = ex
	local d = want - target
	if d.Magnitude < 0.01 then return want end
	local hit
	for _ = 1, 6 do
		hit = Workspace:Raycast(target, d, rp)
		if hit and (hit.Instance.Transparency > 0.9 or hit.Instance.Size.Magnitude < 1) then rp:AddToFilter(hit.Instance) else break end
	end
	if hit then return target + d.Unit * math.max(1.5, (hit.Position - target).Magnitude - 0.8) end
	return want
end
function Stage:_stepCam(dt, t)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local cf, fov = self.CamCF, self.CamFov
	if not cf then cf, fov = self:_finalCam(t) end
	local sh = self.ShakeAmp or 0
	if sh > 0.01 then
		cf *= CF((math.random() - 0.5) * sh, (math.random() - 0.5) * sh, 0) * ANG(0, 0, (math.random() - 0.5) * sh * 0.03)
		self.ShakeAmp = sh * math.exp(-6 * dt)
	end
	cam.CFrame = cf
	cam.FieldOfView = math.clamp((fov or 50) + (self.FovKick or 0), 10, 115)
	self.FovKick = (self.FovKick or 0) * math.exp(-5 * dt)
end
function Stage:_shake(a) self.ShakeAmp = math.max(self.ShakeAmp or 0, a) end
function Stage:_flash(a, dur, col)
	self.FlashF.BackgroundColor3 = col or Color3.new(1, 1, 1)
	self.FlashF.BackgroundTransparency = 1 - a
	TweenService:Create(self.FlashF, TweenInfo.new(dur or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end
-- manga-style impact frames: white -> stark mono -> back
function Stage:_impactFrames(len)
	len = len or 0.14
	local fl, ic = self.FlashF, self.ImpactCC
	fl.BackgroundColor3 = Color3.new(1, 1, 1)
	fl.BackgroundTransparency = 0
	task.delay(0.045, function()
		if not self.Folder then return end
		fl.BackgroundTransparency = 1
		if ic then ic.Enabled = true end
		task.delay(len, function()
			if ic then ic.Enabled = false end
			if self.Folder then self:_flash(0.45, 0.35) end
		end)
	end)
end

------------------------------------------------------------------ fx bits
function Stage:_strike(pos, h, scale, dur)
	scale = scale or 1
	local top = carrier(self.Folder, CF(pos + V3(rnd(-6, 6), h or 180, rnd(-6, 6))), "StrikeTop")
	local bot = carrier(self.Folder, CF(pos), "StrikeBot")
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = top, bot
	local beams = {}
	local spec = { { ELEC_HOT, 7, 3, 0 }, { ELEC, 20, 10, 0.35 }, { ELEC_HOT, 3, 2, 0 } }
	for i, s in spec do
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.Texture = if i == 2 then GLOW else KB.Bolt; b.TextureMode = Enum.TextureMode.Stretch; b.LightEmission = 1; b.LightInfluence = 0
		b.Color = cs(s[1]); b.Width0, b.Width1 = s[2] * scale, s[3] * scale; b.FaceCamera = true; b.Transparency = NS(s[4]); b.Segments = 16
		b.CurveSize0, b.CurveSize1 = rnd(-8, 8) * scale, rnd(-6, 6) * scale
		b.Parent = top
		beams[i] = b
	end
	local n = math.max(3, math.floor((dur or 0.32) / 0.035))
	task.spawn(function()
		for k = 1, n do
			for i, b in beams do
				b.Enabled = (k + i) % 3 ~= 0 or k < 3
				if i ~= 2 then b.CurveSize0, b.CurveSize1 = rnd(-8, 8) * scale, rnd(-6, 6) * scale end
				b.Transparency = NS(math.min(1, spec[i][4] + (k / n) ^ 2 * 0.9))
			end
			task.wait(0.035)
		end
		top:Destroy(); bot:Destroy()
	end)
	VFX.Sprite(pos + V3(0, 1.5, 0), { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 10 * scale, 22 * scale }, Life = 0.45, Bright = 3 })
end

function Stage:_impact(g, big)
	local s = big and 1.3 or 1
	VFX.Decal(g, KB.Crack, Color3.fromRGB(140, 200, 255), 6 * s, 18 * s, 4, { Rot = NumberRange.new(0, 360) })
	VFX.Decal(g, KB.CrackGlow, ELEC_HOT, 4 * s, 14 * s, 1.2, { Rot = NumberRange.new(0, 360) })
	for i, sz in { 26, 44, 66 } do
		task.delay((i - 1) * 0.08, function()
			VFX.Shockwave(VFX.Facing(g + V3(0, 0.4 + i * 0.2, 0), Y), i == 2 and GOLD_HOT or ELEC, sz * s, 0.5 + i * 0.12, { Texture = i == 3 and KB.Ring or KB.Shock })
		end)
	end
	VFX.Sprite(g + V3(0, 0.4, 0), { Tex = KB.ArcRing, Color = ELEC_HOT, Size = { 6 * s, 20 * s }, Life = 0.5, Dir = Y, Flip = { VFX.G4, nil, 32 }, Bright = 3 })
	VFX.Sprite(g + V3(0, 2, 0), { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 10 * s, 36 * s }, Life = 0.55, Bright = 3 })
	VFX.Burst(g, { CF = VFX.Facing(g, Y), Count = math.floor(26 * s), Texture = KB.SmokeBall, Color = Color3.fromRGB(150, 140, 140), Size = { 3, 10 },
		Life = { 1, 1.9 }, Speed = { 10, 28 }, Spread = 84, Drag = 4, Light = 0, Transparency = { 0.3, 1 } })
	VFX.Burst(g, { CF = VFX.Facing(g, Y), Count = math.floor(16 * s), Texture = KB.IceDebris, Color = Color3.fromRGB(120, 112, 110), Size = { 1.3, 0.6 },
		Life = { 0.9, 1.5 }, Speed = { 18, 36 }, Spread = 55, Drag = 1, Light = 0, Accel = V3(0, -60, 0), Flip = { VFX.G4, Enum.ParticleFlipbookMode.Loop, 12 }, Transparency = { 0, 0.3 } })
	VFX.Burst(g, { CF = VFX.Facing(g, Y), Count = math.floor(50 * s), Texture = KB.Sparks, Color = ELEC_HOT, Size = { 0.4, 0 }, Life = { 0.3, 0.8 }, Speed = { 22, 50 }, Spread = 75, Drag = 3, Accel = V3(0, -30, 0) })
	VFX.Burst(g + V3(0, 0.3, 0), { CF = VFX.Facing(g, Y), Count = 10, Texture = KB.Spikes, Color = ELEC_HOT, Size = { 4 * s, 6 * s }, Life = { 0.35, 0.5 }, Speed = { 0.01, 0.01 },
		Spread = 0, Flip = { VFX.G2 } })
	VFX.Flash(g + V3(0, 3, 0), ELEC, 10, 60, 0.45)
	self:_shake(big and 2.4 or 1.8)
	self.FovKick = 10
	task.spawn(function()
		for _ = 1, 12 do
			task.wait(0.11)
			if not self.Folder then return end
			local p = g + V3(rnd(-9, 9) * s, 0.4, rnd(-9, 9) * s)
			VFX.Sprite(p, { Tex = KB.Arc1, Color = ELEC_HOT, Size = { 2, 3.5 }, Life = 0.22, Flip = { VFX.G4 }, Bright = 3 })
		end
	end)
end

function Stage:_rain(center, radius, n, dur, scale)
	task.spawn(function()
		for _ = 1, n do
			if not self.Folder then return end
			local a, r = rnd(0, TAU), math.sqrt(math.random()) * radius
			local g = center + V3(math.cos(a) * r, 0, math.sin(a) * r)
			self:_strike(g, rnd(140, 220), rnd(0.5, 1) * (scale or 1), rnd(0.15, 0.3))
			VFX.Decal(g, KB.CrackGlow, ELEC_HOT, 1.5, 5, 0.5)
			VFX.Burst(g, { CF = VFX.Facing(g, Y), Count = 8, Texture = KB.Sparks, Color = ELEC_HOT, Size = { 0.3, 0 }, Life = { 0.2, 0.4 }, Speed = { 10, 22 }, Spread = 70, Drag = 3 })
			if math.random() < 0.35 then VFX.Sfx(if math.random() < 0.5 then "ThunderCrack" else "Zap", g, rnd(0.35, 0.6), rnd(0.9, 1.2)) end
			task.wait(dur / n * rnd(0.5, 1.5))
		end
	end)
end

------------------------------------------------------------------ the lightning streak
function Stage:_streakInit()
	local head = carrier(self.Folder, CF(self.LandG), "StreakHead")
	VFX.Emitter(head, { Texture = KB.BigGlow, Color = cs(ELEC_HOT), LightEmission = 1, Brightness = 4, Rate = 60, Lifetime = NumberRange.new(0.08, 0.12),
		Speed = NumberRange.new(0), Size = NS(10, 15), LockedToPart = true })
	VFX.Emitter(head, { Texture = KB.Arc1, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = cs(ELEC_HOT, ELEC), LightEmission = 1,
		Brightness = 3, Rate = 45, Lifetime = NumberRange.new(0.12, 0.2), Speed = NumberRange.new(0), Size = NS(5, 9), Rotation = NumberRange.new(0, 360) })
	VFX.Emitter(head, { Texture = KB.Sparks, Color = cs(ELEC_HOT), LightEmission = 1, Brightness = 3, Rate = 90, Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(10, 30), SpreadAngle = Vector2.new(180, 180), Size = NS(0.4, 0), Drag = 3 })
	local a0 = Instance.new("Attachment"); a0.Position = V3(0, 1.8, 0); a0.Parent = head
	local a1 = Instance.new("Attachment"); a1.Position = V3(0, -1.8, 0); a1.Parent = head
	local tr = Instance.new("Trail"); tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Color = cs(ELEC_HOT, ELEC); tr.LightEmission = 1; tr.LightInfluence = 0; tr.Lifetime = 0.35; tr.Transparency = NS({ NK(0, 0), NK(1, 1) }); tr.WidthScale = NS(1, 0.2)
	tr.Parent = head
	local light = Instance.new("PointLight"); light.Color = ELEC; light.Range = 50; light.Brightness = 6; light.Parent = head
	self.StreakHead = head
	self.StreakPts, self.StreakSegs = {}, {}
	local prev
	for i = 1, 12 do
		local p = carrier(self.Folder, CF(self.LandG), "StreakPt")
		local at = Instance.new("Attachment"); at.Parent = p
		if prev then
			for kk = 1, 2 do
				local bm = Instance.new("Beam")
				bm.Attachment0, bm.Attachment1 = prev, at
				bm.Texture = if kk == 1 then KB.Bolt else GLOW; bm.TextureMode = Enum.TextureMode.Stretch; bm.LightEmission = 1; bm.LightInfluence = 0
				bm.Color = cs(kk == 1 and ELEC_HOT or ELEC); bm.FaceCamera = true; bm.Segments = 8
				local w = (1 - i / 13) * (kk == 1 and 3.4 or 9)
				bm.Width0, bm.Width1 = w, w * 0.85; bm.Transparency = NS(kk == 1 and 0 or 0.45)
				bm.Parent = p
				table.insert(self.StreakSegs, bm)
			end
		end
		self.StreakPts[i] = p
		prev = at
	end
	self.StreakHist = {}
	self:_streakOn(false)
end
function Stage:_streakOn(on)
	if not self.StreakHead then return end
	for _, d in self.StreakHead:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("PointLight") then d.Enabled = on end
	end
	for _, bm in self.StreakSegs do bm.Enabled = on end
	self.StreakLive = on
	if not on then self.StreakHist = {} end
end
function Stage:_streakStep(pos)
	if not self.StreakLive then return end
	self.StreakHead.CFrame = CF(pos)
	table.insert(self.StreakHist, 1, pos)
	if #self.StreakHist > 40 then table.remove(self.StreakHist) end
	for i, p in self.StreakPts do
		local h = self.StreakHist[math.min(#self.StreakHist, 1 + (i - 1) * 3)] or pos
		local j = if i == 1 then Vector3.zero else V3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)) * (i * 0.35)
		p.CFrame = CF(h + j)
	end
	for _, bm in self.StreakSegs do bm.Enabled = math.random() < 0.85 end
end

-- camera-space rushing streaks (speed read)
function Stage:_rushInit()
	local r = carrier(self.Folder, CF(), "Rush", V3(36, 22, 1))
	self.Rush = VFX.Emitter(r, { Texture = KB.Streak, Color = cs(Color3.fromRGB(230, 240, 255)), LightEmission = 1, Brightness = 1.5, Rate = 0,
		Lifetime = NumberRange.new(0.12, 0.2), Speed = NumberRange.new(180, 260), EmissionDirection = Enum.NormalId.Back, Shape = Enum.ParticleEmitterShape.Box,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Size = NS(1.6), Squash = NS(0.5), Transparency = NS({ NK(0, 1), NK(0.3, 0.3), NK(1, 1) }), LockedToPart = true })
	self.RushPart = r
end

-- storm set dressing at the launch spot: vortex, rain, ground wind, rising rocks
function Stage:_stormInit(g0)
	local vortex = carrier(self.Folder, CF(g0 + Y * 62), "Vortex", V3(110, 2, 110))
	self.Vortex = VFX.Emitter(vortex, { Texture = KB.SmokeBall, Color = cs(Color3.fromRGB(56, 62, 92), Color3.fromRGB(26, 30, 50)), LightEmission = 0, LightInfluence = 0.6,
		Rate = 0, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(90, 90), Shape = Enum.ParticleEmitterShape.Box,
		Size = NS({ NK(0, 20), NK(1, 46) }), Transparency = NS({ NK(0, 1), NK(0.25, 0.12), NK(0.8, 0.2), NK(1, 1) }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(30, 60) })
	self.VortexPart = vortex
	local rain = carrier(self.Folder, CF(g0 + Y * 40), "Rain", V3(70, 1, 70))
	self.Rain = VFX.Emitter(rain, { Texture = KB.Streak, Color = cs(Color3.fromRGB(190, 210, 240)), LightEmission = 0.3, LightInfluence = 0.6, Rate = 0,
		Lifetime = NumberRange.new(0.5, 0.7), Speed = NumberRange.new(80, 100), EmissionDirection = Enum.NormalId.Bottom, Shape = Enum.ParticleEmitterShape.Box,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Size = NS(0.12), Squash = NS(4), Transparency = NS(0.45), Acceleration = V3(6, 0, 0) })
	local ground = carrier(self.Folder, CF(g0 + Y * 0.25), "GroundAura", V3(16, 0.4, 16))
	self.GroundWind = VFX.Emitter(ground, { Texture = KB.FloorWind, Color = cs(ELEC_HOT, ELEC), LightEmission = 1, Brightness = 2, Rate = 0,
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(0.01), EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = NS(6, 18), Transparency = NS(0.3, 1), RotSpeed = NumberRange.new(180, 260), Rotation = NumberRange.new(0, 360), LockedToPart = true })
	self.GroundDust = VFX.Emitter(ground, { Texture = KB.SmokeBall, Color = cs(Color3.fromRGB(150, 150, 170)), LightEmission = 0, LightInfluence = 0.8, Rate = 0,
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(6, 12), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(85, 85),
		Size = NS(2, 6), Transparency = NS(0.55, 1), Acceleration = V3(0, -6, 0), Drag = 2, Shape = Enum.ParticleEmitterShape.Box })
	self.Rocks = VFX.Emitter(ground, { Texture = KB.IceDebris, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop, FlipbookFramerate = NumberRange.new(6),
		Color = cs(Color3.fromRGB(110, 104, 112)), LightEmission = 0, LightInfluence = 1, Rate = 0, Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15), Acceleration = V3(0, 3.5, 0), Shape = Enum.ParticleEmitterShape.Box,
		Size = NS(0.6, 1), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), Transparency = NS({ NK(0, 0), NK(0.8, 0), NK(1, 1) }) })
	self.GroundGlow = VFX.Emitter(ground, { Texture = KB.CrackGlow, Color = cs(ELEC_HOT, ELEC), LightEmission = 1, Brightness = 2, Rate = 0,
		Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(0.01), EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = NS(8, 13), Transparency = NS(0.4, 1), Rotation = NumberRange.new(0, 360), LockedToPart = true, Shape = Enum.ParticleEmitterShape.Box })
	self.GroundPart = ground
end

------------------------------------------------------------------ the cinematic: state at time t
function Stage:_setupCine(full)
	local hipH = self.HipH or 3
	self.Full = full
	self.LandBody = CF(self.LandG + V3(0, hipH, 0)) * self:_faceCam()
	self.Apex = self.LandG + V3(0, 110, 0)
	if full then
		local ch = player.Character
		local chr = ch and ch:FindFirstChild("HumanoidRootPart")
		local p0, look
		if chr and chr.Position.Y > -300 then
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { ch, self.Folder }
			local hit = Workspace:Raycast(chr.Position + Y * 2, -Y * 60, rp)
			p0 = (hit and hit.Position or (chr.Position - Y * hipH)) + Y * hipH
			look = chr.CFrame.LookVector * V3(1, 0, 1)
			look = if look.Magnitude > 0.1 then look.Unit else V3(0, 0, -1)
			self:_hideChar(ch)
			self.HiddenCharModel = ch
		else
			p0 = self.LaunchG + Y * hipH
			local d = V3(p0.X - self.LedgeC.X, 0, p0.Z - self.LedgeC.Z)
			look = if d.Magnitude > 0.5 then d.Unit else self.K
		end
		self.P0, self.G0, self.Look = p0, p0 - Y * hipH, look
		self.RightV = look:Cross(Y).Unit
		local P0, P3 = p0, self.Apex
		local horiz = V3(P3.X - P0.X, 0, P3.Z - P0.Z)
		self.HDir = if horiz.Magnitude > 1 then horiz.Unit else look
		self.BP = { P0, P0 + Y * math.max(600, horiz.Magnitude * 0.25), P3 + Y * math.max(220, horiz.Magnitude * 0.12) - self.HDir * math.min(1200, horiz.Magnitude * 0.3), P3 }
		self:_stormInit(self.G0)
		local B = self.BP
		local function bez(x)
			local v = 1 - x
			return B[1] * v * v * v + B[2] * 3 * v * v * x + B[3] * 3 * v * x * x + B[4] * x * x * x
		end
		for i = 1, 150 do
			local e = 0.02 + 0.93 * (i / 150)
			local p, q = bez(e), bez(math.min(1, e + 0.003))
			local tn = (q - p).Unit
			local r = V3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))
			r = (r - tn * r:Dot(tn))
			r = if r.Magnitude > 0.05 then r.Unit else Y
			local c = carrier(self.Folder, CF(p + r * rnd(12, 45) + tn * rnd(-20, 20)), "FlightCloud", V3(20, 8, 20))
			VFX.Emitter(c, { Texture = KB.SmokeBall, Color = cs(Color3.fromRGB(235, 238, 250), Color3.fromRGB(190, 196, 220)), LightEmission = 0.1, LightInfluence = 0.7,
				Rate = 0, Lifetime = NumberRange.new(60), Speed = NumberRange.new(0.2), SpreadAngle = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Box,
				Size = NS(rnd(14, 32)), Transparency = NS({ NK(0, 0.35), NK(1, 0.35) }), Rotation = NumberRange.new(0, 360) }):Emit(3)
		end
	end
	self:_streakInit()
	self:_rushInit()
	-- events
	local E = {}
	local function ev(t, fn) table.insert(E, { t = t, fn = fn }) end
	if full then
		local g0, p0 = self.G0, self.P0
		ev(0.0, function()
			self.MusicS = self:_snd("Music", 1)
			self.WindL = self:_loop("WindHowl", 1, 0.85)
			self:_snd("Riser", 1)
			self.HumS = VFX.SfxLoop("ElecHum", self.HamPart, 0.9, 0.7)
			VFX.RuneCircle(CF(g0 + Y * 0.25), 8, 3.1, { Main = ELEC_HOT, Deep = ELEC, Mist = Color3.fromRGB(150, 200, 255) }, { Points = 14 })
			self.HamTrail.Enabled = true
		end)
		ev(0.3, function() self:_snd("Artillery", 0.8, 0.9) end)
		for i, at in { 0.7, 1.35, 1.95, 2.35, 2.6, 2.78, 2.9 } do
			ev(at, function()
				local a = rnd(0, TAU)
				local r = rnd(7, 15)
				local p = g0 + V3(math.cos(a) * r, 0, math.sin(a) * r)
				self:_strike(p, 170, 0.5 + i * 0.12, 0.22)
				VFX.Decal(p, KB.CrackGlow, ELEC_HOT, 1.5, 5, 0.6)
				VFX.Sfx(if i % 2 == 0 then "ThunderCrack" else "Zap", p0, 0.45 + i * 0.06, rnd(0.9, 1.15))
				VFX.Sprite(self.VortexPart.Position + V3(rnd(-30, 30), rnd(-4, 4), rnd(-30, 30)), { Tex = KB.BigGlow, Color = ELEC, Size = { 18, 30 }, Life = 0.25, Bright = 2 })
			end)
		end
		ev(1.15, function() VFX.Sfx("WhooshShort", p0, 0.9, 0.9) end)
		ev(1.6, function() self:_snd("MachineRise", 1) end)
		ev(2.2, function() -- eyes ignite
			self.EyesLit = true
			local h = self.Head and self.Head.Position or p0
			VFX.Sprite(h, { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 2, 8 }, Life = 0.35, Bright = 3 })
			VFX.Sprite(h, { Tex = KB.Flare, Color = ELEC, Size = { 10, 2 }, Life = 0.4, Bright = 3, Squash = NS(-2) })
			self:_snd("Strike", 0.6)
			VFX.Sfx("Zap", h, 1, 0.7)
			self:_flash(0.35, 0.25, Color3.fromRGB(210, 230, 255))
			self.FovKick = -6
		end)
		ev(2.6, function()
			VFX.Decal(g0, KB.Crack, Color3.fromRGB(140, 200, 255), 4, 14, 2, { Rot = NumberRange.new(0, 360) })
			VFX.Burst(g0, { CF = VFX.Facing(g0, Y), Count = 14, Texture = KB.IceDebris, Color = Color3.fromRGB(120, 112, 110), Size = { 0.9, 0.5 }, Life = { 1, 1.6 }, Speed = { 6, 12 },
				Spread = 30, Drag = 1, Light = 0, Accel = V3(0, -10, 0), Flip = { VFX.G4, Enum.ParticleFlipbookMode.Loop, 10 } })
			VFX.Sfx("Charge", p0, 1.1, 0.9)
		end)
		-- LAUNCH
		ev(T_LAUNCH, function()
			self:_impactFrames(0.12)
			self:_strike(g0, 320, 2.8, 0.6)
			self:_impact(g0, false)
			self:_snd("DarkBraam", 1)
			self:_snd("ThunderHeavy", 1)
			self:_snd("WindExplosion", 1)
			VFX.Sfx("WarpBoom", p0, 1.2)
			if self.HumS then self.HumS(0.3) self.HumS = nil end
			self:_fade(self.WindL, 0, 0.8)
			self.FlyL = self:_loop("PlasmaWind", 1, 1)
			self:_fade(self.FlyL, SND.PlasmaWind[2], 0.6)
			self.BodyTrail.Enabled = true
			self.Comet.Rate = 30
			self.Vortex.Rate = 0
			self.Rain.Rate = 0
			self.GroundWind.Rate, self.GroundDust.Rate, self.Rocks.Rate, self.GroundGlow.Rate = 0, 0, 0, 0
		end)
		ev(3.7, function() VFX.Sfx("WhooshLong", self.Body.Position, 1.2, 0.8) end)
		local function boom(big)
			local pos, tan = self.Body.Position, self.Tan or Y
			VFX.Shockwave(VFX.Facing(pos, tan), ELEC_HOT, big and 70 or 40, 0.5, { Texture = KB.Ring })
			VFX.Shockwave(VFX.Facing(pos, tan), big and GOLD_HOT or Color3.new(1, 1, 1), big and 40 or 24, 0.4, { Texture = KB.Shock })
			self:_snd("WindExplosion", big and 1 or 0.8)
			VFX.Sfx("Boom", pos, 1, 1.25)
			self:_shake(big and 1.3 or 0.9)
			self:_flash(big and 0.35 or 0.2, 0.3)
		end
		ev(4.3, function() boom(false) end)
		ev(4.65, function() VFX.Sfx("WhooshLong", self.Body.Position, 1, 1.1) end)
		ev(5.45, function() boom(true) end)
		ev(5.6, function() self:_snd("Riser", 1) end)
		ev(T_STREAK, function()
			local pos = self.Body.Position
			VFX.Sprite(pos, { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 6, 34 }, Life = 0.35, Bright = 4 })
			self:_snd("Strike", 1)
			VFX.Sfx("ThunderCrack", pos, 1.1, 1.1)
			self:_flash(0.6, 0.3, Color3.fromRGB(210, 230, 255))
			self:_visible(false)
			self.BodyTrail.Enabled, self.HamTrail.Enabled = false, false
			self.Comet.Rate = 0
			self:_streakOn(true)
			self.StreakHist = {}
		end)
		ev(7.3, function() VFX.Sfx("WhooshLong", self.Body.Position, 1.2, 1.2) end)
	else
		ev(T_LAND - 0.01, function()
			self.MusicS = self:_snd("Music", 0.8, 1, 11.5)
			self:_snd("Riser", 1, 1, 2.3)
			self:_visible(false)
			self:_streakOn(true)
		end)
	end
	-- LANDING (both)
	ev(T_LAND, function()
		self:_fade(self.FlyL, 0, 0.5)
		self:_rain(self.LandG, 32, 30, 2.4, 1.1)
		local cl = carrier(self.Folder, CF(self.LandG + Y * 75), "LandStorm", V3(140, 6, 140))
		local ce = VFX.Emitter(cl, { Texture = KB.SmokeBall, Color = cs(Color3.fromRGB(58, 64, 96), Color3.fromRGB(28, 32, 54)), LightEmission = 0, LightInfluence = 0.5,
			Rate = 0, Lifetime = NumberRange.new(3, 4), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(90, 90), Shape = Enum.ParticleEmitterShape.Box,
			Size = NS({ NK(0, 30), NK(1, 60) }), Transparency = NS({ NK(0, 1), NK(0.2, 0.15), NK(0.75, 0.25), NK(1, 1) }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(20, 45) })
		ce:Emit(45)
		task.delay(5, function() cl:Destroy() end)
		task.spawn(function()
			for _ = 1, 10 do
				task.wait(0.15)
				if not cl.Parent then return end
				VFX.Sprite(cl.Position + V3(rnd(-50, 50), rnd(-4, 4), rnd(-50, 50)), { Tex = KB.BigGlow, Color = ELEC, Size = { 25, 45 }, Life = 0.22, Bright = 2 })
			end
		end)
		local star = self.Apex
		VFX.Sprite(star, { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 2, 30 }, Life = 0.9, Bright = 4 })
		VFX.Sprite(star, { Tex = KB.Flare, Color = ELEC, Size = { 12, 80 }, Life = 0.9, Bright = 4, Squash = NS(-2.5) })
		VFX.Sfx("Charge", self.LandG, 1, 1.3)
	end)
	ev(8.35, function() self:_snd("ThunderHeavy", 0.9) self:_strike(self.LandG, 115, 3.4, 0.55) end)
	ev(T_IMPACT, function()
		self:_streakOn(false)
		self:_visible(true)
		self:_impactFrames(0.16)
		self:_strike(self.LandG, 320, 3.6, 0.6)
		self:_impact(self.LandG + self:_faceCam().LookVector * 1.6, true)
		self:_snd("ElasticBraam", 1)
		self:_snd("ImpactLarge", 1)
		self:_snd("Downslam", 1)
		self:_snd("Rubble", 1)
		self:_snd("ThunderHeavy", 0.8)
		VFX.Sfx("WarpBoom", self.LandG, 1.2, 0.9)
		VFX.Burst(self.LandG + Y * 1.5, { CF = VFX.Facing(self.LandG, Y), Count = 40, Texture = KB.SmokeBall, Color = Color3.fromRGB(170, 176, 196), Size = { 8, 22 },
			Life = { 1.2, 2.2 }, Speed = { 6, 18 }, Spread = 88, Drag = 2.5, Light = 0.1, Transparency = { 0.15, 1 } })
		if self.CauldronM then
			task.spawn(function()
				local base = self.CauldronCF
				for i = 1, 8 do
					if not self.CauldronM.Parent then return end
					self.CauldronM:PivotTo(base * CF(0, (i % 2) * 0.25, 0) * ANG(rnd(-0.03, 0.03), 0, rnd(-0.03, 0.03)))
					task.wait(0.04)
				end
				self.CauldronM:PivotTo(base)
			end)
			VFX.Burst(self.Ct, { CF = VFX.Facing(self.Ct, Y), Count = 26, Texture = KB.Splash, Color = GOLD_HOT, Size = { 1.2, 0.2 }, Life = { 0.5, 0.9 }, Speed = { 10, 20 }, Spread = 30, Accel = V3(0, -40, 0), Drag = 1 })
			self.Surge = 1
		end
	end)
	ev(9.25, function()
		local h = self.Head and self.Head.Position or self.LandG
		VFX.Sprite(h, { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 2, 9 }, Life = 0.4, Bright = 3 })
		VFX.Sprite(h, { Tex = KB.Flare, Color = ELEC, Size = { 12, 2 }, Life = 0.45, Bright = 3, Squash = NS(-2) })
		VFX.Sfx("Zap", h, 1, 0.75)
		self.FovKick = -5
	end)
	ev(T_RISE, function() VFX.Sfx("WhooshShort", self.LandG, 0.8, 1.2) self:_snd("Sting", 1) end)
	ev(T_RISE + 0.2, function() VFX.Sfx("WhooshShort", self.LandG, 0.7, 1.4) end)
	ev(T_TURN, function() self:_bars(false) self:_snd("Artillery", 0.5, 1.1) end)
	ev(T_END - 0.05, function()
		if self.MusicS then self:_fade(self.MusicS, 0, 2.5) end
	end)
	self.Events = E
end

-- body CF, hammer, visibility-independent state at time t
function Stage:_cineAt(t, dt)
	local full = self.Full
	local hipH = self.HipH or 3
	local cf, fov
	local aura, eyes, storm = 0, 0, 0
	self.Keyed = t
	if full and t < T_LAUNCH then
		------------------------------------------------ WIND-UP
		local p0, g0, look, right = self.P0, self.G0, self.Look, self.RightV
		self.Body = CFrame.lookAt(p0, p0 + look)
		self.HammerMode = if t < 2.99 then "spin" else "hand"
		self.SpinA = 9 * t + 60 * (math.min(t, 3) / 3) ^ 2.5
		local w = t / T_LAUNCH
		aura = 0.45 + 0.55 * ease(seg(t, 0, 2.6))
		eyes = if t >= 2.2 then math.min(1, (t - 2.2) / 0.15) else 0
		storm = ease(seg(t, 0, 1.5))
		-- whirl effects
		self.DiscE.Rate = 4 + 26 * w
		self.DiscE2.Rate = 10 * w
		self.HamArcs.Rate, self.HamSparks.Rate, self.HamGlow.Rate = 6 + 46 * w, 6 + 60 * w, 6 + 20 * w
		self.HamBeam.Enabled = w > 0.3 and math.random() < 0.3 + 0.6 * w
		self.HamLight.Brightness = 1 + 3 * w + math.random() * w
		self.HamTrail.Enabled = true
		-- storm + ground aura
		self.Vortex.Rate = 30 * storm
		self.Rain.Rate = 380 * storm
		self.GroundWind.Rate = 8 * aura
		self.GroundDust.Rate = 20 * aura
		self.Rocks.Rate = if t > 1.0 then 24 * aura else 0
		self.GroundGlow.Rate = if t > 2.2 then 6 else 0
		self.Implode.Rate = if t > 2.5 then 9 else 0
		if self.HumS and self.HamPart:FindFirstChildOfClass("Sound") then self.HamPart:FindFirstChildOfClass("Sound").PlaybackSpeed = 0.7 + 0.8 * w end
		if self.WindL then self.WindL.Volume = SND.WindHowl[2] * (0.3 + 0.9 * w); self.WindL.PlaybackSpeed = 0.85 + 0.35 * w end
		-- camera shots
		local hand = self.Hand and self.Hand.Position or p0
		local head = self.Head and self.Head.Position or (p0 + Y * 1.5)
		if t < 1.15 then -- S1 establishing hero, low front three-quarter, dolly in
			local k = ease(t / 1.15)
			local dir = (CFrame.fromAxisAngle(Y, math.rad(34 - 12 * k)) * look).Unit
			local tgt = p0 + Y * 0.6
			local want = g0 + Y * 1.4 + dir * (15 - 3 * k)
			cf, fov = CFrame.lookAt(self:_safeCam(tgt, want), tgt + Y * 0.6), 50
			self:_dof(15, 0.1)
		elseif t < 2.05 then -- S2 orbit the whirling hammer
			local k = (t - 1.15) / 0.9
			local ang = math.rad(80 - 70 * ease(k))
			local dir = (CFrame.fromAxisAngle(Y, ang) * look).Unit
			local tgt = hand + Y * 0.2
			local want = tgt + dir * (6.2 - 0.8 * k) + Y * (0.4 - 0.5 * k)
			local cp = self:_safeCam(tgt, want)
			cf, fov = CFrame.lookAt(cp, tgt), 56
			self:_dof((cp - tgt).Magnitude, 0.55)
		elseif t < 2.6 then -- S3 the face: eyes ignite
			local k = ease((t - 2.05) / 0.55)
			local dir = (CFrame.fromAxisAngle(Y, math.rad(-12)) * look).Unit
			local tgt = head + Y * 0.08
			local want = tgt + dir * (4.6 - 1.2 * k) - Y * 0.35
			local cp = self:_safeCam(tgt, want)
			cf, fov = CFrame.lookAt(cp, tgt), 38
			self:_dof((cp - tgt).Magnitude, 0.7)
		else -- S4 ground-level wide: everything peaks
			local k = ease((t - 2.6) / 0.4)
			local dir = (CFrame.fromAxisAngle(Y, math.rad(-24)) * look).Unit
			local tgt = p0 + Y * (1.8 + 0.6 * k)
			local want = g0 + Y * 0.55 + dir * (11 - 2 * k)
			cf, fov = CFrame.lookAt(self:_safeCam(tgt, want), tgt), 62 - 6 * k
			self:_dof(10, 0.1)
		end
		self:_shake(0.03 + 0.45 * w * w)
	elseif full and t < T_LAND then
		------------------------------------------------ LAUNCH + FLIGHT
		local u = (t - T_LAUNCH) / (T_LAND - T_LAUNCH)
		local e = u ^ 2.2
		local B = self.BP
		local function bez(x)
			local v = 1 - x
			return B[1] * v * v * v + B[2] * 3 * v * v * x + B[3] * 3 * v * x * x + B[4] * x * x * x
		end
		local pos = bez(e)
		local ahead = bez(math.min(1, e + 0.004))
		local tan = ahead - pos
		tan = if tan.Magnitude > 1e-4 then tan.Unit else Y
		self.Tan = tan
		local axis = self.HDir:Cross(Y).Unit
		local back = axis:Cross(tan)
		back = if back.Magnitude > 0.05 then back.Unit else Y
		local right = tan:Cross(back).Unit
		local roll = TAU * ease(seg(t, 4.6, 5.25)) -- barrel roll
		self.Body = CFrame.fromMatrix(pos, right, tan, back) * ANG(0, roll, 0)
		self.HammerMode = "hand"
		self:_streakStep(pos)
		aura = if t < T_STREAK then 0.85 else 0
		eyes = if t < T_STREAK then 1 else 0
		storm = math.max(lerp(1, 0, ease(seg(t, 3.6, 5.2))), ease(seg(t, 7.2, T_LAND)))
		self.HamArcs.Rate, self.HamSparks.Rate, self.HamGlow.Rate = 25, 25, 20
		self.DiscE.Rate, self.DiscE2.Rate = 0, 0
		self.HamBeam.Enabled = false
		local side, upP = right, back
		if t < 3.7 then -- S5 the lift-off, seen from the ground: he rips up into the storm
			local g0, look, right = self.G0, self.Look, self.RightV
			local cp = self:_safeCam(self.P0, g0 - look * 9 + right * 3.5 + Y * 0.9)
			local chase = pos - tan * 10 + side * 3.5 + upP * 2.5
			local k = ease(seg(t, 3.45, 3.7))
			cp = cp:Lerp(chase, k)
			cf = CFrame.lookAt(cp, pos + Y * 0.5)
			fov = 66 + 8 * k
			self:_dof(20, 0)
		else -- S6 chase: behind, to the side, a little above; widening with speed
			local k2 = seg(t, 3.7, T_LAND)
			local h = math.clamp(1 - math.abs(tan.Y), 0, 1)
			local cp = pos - tan * (6 + 4 * k2) + side * (2.5 + 1.5 * k2) + upP * (5.5 + 1 * k2)
			local camUp = tan * (1 - h) + upP * h
			cf = CFrame.lookAt(cp, pos + tan * (4 + 10 * k2), camUp) * ANG(0, 0, math.sin(t * 2.2) * 0.04 * k2)
			fov = 70 + 22 * ease(k2)
		end
		if self.RushPart then
			self.RushPart.CFrame = cf * CF(0, 0, -22)
			self.Rush.Rate = if t < 3.6 then 0 else 60 + 600 * u
		end
		self:_shake(0.06 + 0.3 * u)
		-- clouds whipping past
		if t > 3.6 and t < 7.8 and math.random() < 0.18 then
			local cpos = pos + tan * rnd(60, 160) * (0.4 + u) + side * rnd(-40, 40) + Y * rnd(-25, 25)
			VFX.Sprite(cpos, { Tex = KB.SmokeBall, Color = Color3.fromRGB(255, 244, 236), Size = { rnd(25, 50), rnd(40, 70) }, Life = 0.9, Bright = 1, Light = 0.25, T = NS({ NK(0, 1), NK(0.3, 0.35), NK(1, 1) }) })
		end
		if t < T_STREAK and math.random() < 0.2 then
			VFX.Sprite(pos + V3(rnd(-2, 2), rnd(-2, 2), rnd(-2, 2)), { Tex = KB.Arc2, Color = ELEC_HOT, Size = { 3, 6 }, Life = 0.18, Flip = { VFX.G4 }, Bright = 3 })
		end
	else
		------------------------------------------------ LANDING (8.0 - 11.0)
		if self.RushPart then self.Rush.Rate = 0 end
		local land = self.LandG
		local star = self.Apex
		self.HammerMode = if t >= T_RISE and t < T_RISE + 0.45 then "twirl" else "hand"
		self.SpinA = (t - T_RISE) * 22
		storm = if t < T_RISE then 1 else lerp(1, 0, ease(seg(t, T_RISE, T_END)))
		if t < T_IMPACT then
			-- S8 wide, low: the star flares, the column comes down
			local pos = if t < 8.35 then star + Y * 30 * (1 - seg(t, T_LAND, 8.35)) else star:Lerp(land + Y * 1.5, easeIn(seg(t, 8.35, T_IMPACT)))
			self:_streakStep(pos)
			self.Body = CF(land + Y * 200)
			local kk = seg(t, T_LAND, T_IMPACT)
			local wide = self:_safeCam(land + Y * 6, land + self.K * (140 - 20 * kk) + Y * 20 - self.RightK * 36)
			cf, fov = CFrame.lookAt(wide, land + Y * (54 - 20 * easeIn(kk))), 66
			self:_shake(0.1 + 0.6 * seg(t, 8.35, T_IMPACT))
			aura, eyes = 0, 0
			self:_dof(40, 0)
		else
			local r0, r1 = self:_faceCam(), self:_faceCauldron()
			local turn = ease(seg(t, T_TURN - 0.15, T_TURN + 0.35))
			self.Body = CF(self.LandBody.Position) * r0:Lerp(r1, turn)
			aura = if t < T_RISE then 1 else lerp(1, 0.3, ease(seg(t, T_RISE, T_END)))
			eyes = 1
			if t < T_RISE then -- S9 the Thor landing: low front three-quarter through the dust, slow push
				local k = ease(seg(t, T_IMPACT, T_RISE))
				local fl = r0.LookVector
				local away = V3(land.X - self.C.X, 0, land.Z - self.C.Z).Unit
				local dir = (fl + away * (0.9 - 0.3 * k)).Unit
				local tgt = land + Y * (1.3 + 0.2 * k)
				local cp = self:_safeCam(tgt, land + dir * (12 - 2.5 * k) + Y * (1.0 + 0.3 * k))
				cf, fov = CFrame.lookAt(cp, tgt), 42 - 4 * k
				self:_dof((cp - tgt).Magnitude, 0.45)
			elseif t < T_TURN then -- S10 rising, low behind his shoulder looking toward the cauldron
				local k = ease(seg(t, T_RISE, T_TURN))
				local back = -r1.LookVector
				local cp = land + back * (6.5 - 0.8 * k) + Y * (1.2 + 0.8 * k) - r1.RightVector * (2.4 - 0.4 * k)
				cf, fov = CFrame.lookAt(cp, self.Ct + Y * (0.2 + 0.6 * k)), 52
				self:_dof((cp - land).Magnitude, 0.25)
			else -- S11 glide to the farm framing
				local k = ease(seg(t, T_TURN, T_END))
				local back = -r1.LookVector
				local c0 = CFrame.lookAt(land + back * 5.7 + Y * 2 - r1.RightVector * 2, self.Ct + Y * 0.8)
				local c1, f1 = self:_finalCam(t)
				cf, fov = c0:Lerp(c1, k), lerp(52, f1, k)
				self:_dof(20, 0.1 * (1 - k))
			end
		end
	end
	local streak = t < T_IMPACT and (t >= T_STREAK or not full)
	if streak ~= (self.StreakLive == true) then self:_streakOn(streak) end
	if self.Hidden ~= streak then self:_visible(not streak) end
	if streak then aura, eyes = 0, 0 end
	self.BodyTrail.Enabled = full and t >= T_LAUNCH and t < T_STREAK
	self.HamTrail.Enabled = not streak and (t < T_STREAK or (t >= T_RISE and t < T_RISE + 0.5))
	self.Comet.Rate = if full and t >= T_LAUNCH and t < T_STREAK then 30 else 0
	self:_aura(aura)
	self:_eyes(eyes)
	self:_stormMix(storm)
	self.CamCF, self.CamFov = cf, fov
end

function Stage:_runEvents(t, prevT)
	for _, e in self.Events do
		if not e.done and e.t <= t then
			e.done = true
			if e.t > prevT - 0.3 then
				local ok, err = pcall(e.fn)
				if not ok then warn("[FarmStage] event " .. e.t .. ": " .. tostring(err)) end
			end
		end
	end
end

------------------------------------------------------------------ farming: every 5 s he calls lightning down onto the cauldron
function Stage:_startFarming()
	self.Keyed = nil
	self.CamCF, self.CamFov = nil, nil
	self.Body = CF(self.LandG + V3(0, self.HipH or 3, 0)) * self:_faceCauldron()
	self:_visible(true)
	self:_streakOn(false)
	self.HammerMode = "hand"
	self.HamTrail.Enabled, self.BodyTrail.Enabled, self.HamBeam.Enabled = false, false, false
	self.Comet.Rate, self.Implode.Rate, self.DiscE.Rate, self.DiscE2.Rate = 0, 0, 0, 0
	self:_aura(0.3)
	self:_eyes(1)
	self.HamArcs.Rate, self.HamSparks.Rate, self.HamGlow.Rate = 3, 3, 6
	self.Farming = true
	if self.BarT and self.BarT.Size.Y.Scale > 0 then self:_bars(false) end
	self.FarmClock = 1.5
	self.FarmCycle = nil
	self.Channeling = false
	self:_pose("Ready", 6)
	if not self.FarmHum and self.HamPart then self.FarmHum = VFX.SfxLoop("ElecHum", self.HamPart, 0.22, 0.85) end
	self:_restoreChar()
	self:_restoreGuis()
	self.Settled = true
end

function Stage:_stepFarm(dt)
	if not self.Farming or self.Busy or not self.Rig then return end
	self.FarmClock += dt
	local cycle = math.floor(self.FarmClock / 5)
	local c = self.FarmClock % 5
	if cycle ~= self.FarmCycle then self.FarmCycle, self.FarmDone = cycle, {} end
	local done = self.FarmDone
	local function once(key, at, fn) if c >= at and not done[key] then done[key] = true fn() end end
	once("raise", 2.4, function()
		self:_pose("Raise", 7)
		self:_aura(0.75)
		self.HamArcs.Rate, self.HamSparks.Rate, self.HamGlow.Rate = 30, 30, 20
		VFX.Sfx("Charge", self.C, 0.55, 1.1)
	end)
	once("darken", 2.8, function()
		self:_storm(true, 0.7)
		local top = self.Ct + Y * 55
		local cl = carrier(self.Folder, CF(top), "FarmStorm", V3(50, 2, 50))
		local e = VFX.Emitter(cl, { Texture = KB.SmokeBall, Color = cs(Color3.fromRGB(56, 62, 92), Color3.fromRGB(30, 34, 56)), LightEmission = 0, LightInfluence = 0.6,
			Rate = 24, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(90, 90), Shape = Enum.ParticleEmitterShape.Box,
			Size = NS({ NK(0, 14), NK(1, 32) }), Transparency = NS({ NK(0, 1), NK(0.3, 0.2), NK(0.8, 0.3), NK(1, 1) }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(30, 60) })
		e:Emit(30)
		self.FarmCloud = { Part = cl, E = e }
		VFX.Sfx("Rumble", self.C, 0.6, 1.1)
		task.spawn(function()
			for _ = 1, 6 do
				task.wait(0.12)
				if not cl.Parent then return end
				VFX.Sprite(top + V3(rnd(-18, 18), rnd(-3, 3), rnd(-18, 18)), { Tex = KB.BigGlow, Color = ELEC, Size = { 10, 18 }, Life = 0.2, Bright = 2 })
			end
		end)
	end)
	once("strike", 3.6, function()
		local tgt = self.Liq.Position
		self:_strike(tgt, 260, 2, 0.5)
		task.delay(0.12, function() if self.Folder then self:_strike(tgt, 240, 1.2, 0.3) end end)
		self.HamLight.Brightness = 7
		self.Surge = 1
		VFX.Burst(tgt, { CF = VFX.Facing(tgt, Y), Count = 30, Texture = KB.Splash, Color = GOLD_HOT, Size = { 1.2, 0.2 }, Life = { 0.5, 0.9 }, Speed = { 10, 24 }, Spread = 30, Accel = V3(0, -40, 0), Drag = 1 })
		VFX.Burst(tgt, { CF = VFX.Facing(tgt, Y), Count = 24, Texture = KB.Sparks, Color = ELEC_HOT, Size = { 0.35, 0 }, Life = { 0.3, 0.6 }, Speed = { 14, 32 }, Spread = 60, Drag = 3 })
		VFX.Sprite(tgt + Y * 0.3, { Tex = KB.ArcRing, Color = GOLD_HOT, Size = { 2, 8 }, Life = 0.45, Dir = Y, Flip = { VFX.G4, nil, 32 }, Bright = 3 })
		VFX.Sprite(tgt + Y * 1.5, { Tex = KB.BigGlow, Color = ELEC_HOT, Size = { 6, 18 }, Life = 0.45, Bright = 3 })
		VFX.Shockwave(VFX.Facing(V3(self.C.X, self.C.Y + 0.3, self.C.Z), Y), ELEC, 20, 0.5, { Texture = KB.Shock })
		VFX.Decal(V3(self.C.X, self.C.Y, self.C.Z), KB.CrackGlow, ELEC_HOT, 3, 9, 0.6)
		for _ = 1, 4 do
			VFX.Sprite(tgt + V3(rnd(-2, 2), rnd(0, 1.5), rnd(-2, 2)), { Tex = KB.Arc2, Color = ELEC_HOT, Size = { 2.5, 4 }, Life = 0.25, Flip = { VFX.G4 }, Bright = 3 })
		end
		self:_snd("Strike", 0.8)
		VFX.Sfx("ThunderCrack", tgt, 1, rnd(0.95, 1.05))
		VFX.Sfx("Splash", tgt, 0.55, 1.2)
		self:_shake(0.8)
		self:_flash(0.4, 0.3, Color3.fromRGB(220, 236, 255))
		if self.CauldronM then
			local base = self.CauldronCF
			task.spawn(function()
				for i = 1, 6 do
					if not self.CauldronM.Parent then return end
					self.CauldronM:PivotTo(base * CF(0, (i % 2) * 0.18, 0) * ANG(rnd(-0.02, 0.02), 0, rnd(-0.02, 0.02)))
					task.wait(0.04)
				end
				self.CauldronM:PivotTo(base)
			end)
		end
	end)
	once("clear", 4.2, function()
		self:_storm(false, 0.9)
		if self.FarmCloud then
			self.FarmCloud.E.Rate = 0
			local p = self.FarmCloud.Part
			task.delay(3, function() p:Destroy() end)
			self.FarmCloud = nil
		end
	end)
	once("lower", 4.45, function()
		self:_pose("Ready", 5)
		self:_aura(0.3)
		self.HamArcs.Rate, self.HamSparks.Rate, self.HamGlow.Rate = 3, 3, 6
		self.HamLight.Brightness = 1
	end)
end

------------------------------------------------------------------ claim / upgrade
function Stage:Claim(newFill)
	if not self.Folder then return end
	task.spawn(function()
		self.Busy = true
		self.Channeling = false
		if self.FarmCloud then self.FarmCloud.Part:Destroy() self.FarmCloud = nil end
		self:_storm(false, 0.4)
		self:_pose("Raise", 9)
		self:_aura(0.8)
		VFX.Sfx("Rise", self.C, 0.9)
		task.wait(0.35)
		if not self.Folder then return end
		local a0 = Instance.new("Attachment"); a0.Parent = self.Liq
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, self.HeadAtt
		b.Texture = KB.Splash; b.TextureMode = Enum.TextureMode.Wrap; b.TextureLength = 3; b.TextureSpeed = 2.5
		b.Color = cs(GOLD_HOT, GOLD); b.LightEmission = 1; b.LightInfluence = 0; b.Width0, b.Width1 = 1.8, 0.5
		b.CurveSize0, b.CurveSize1 = 5, -2; b.FaceCamera = true; b.Transparency = NS(0.1)
		b.Parent = self.Liq
		local glowB = b:Clone(); glowB.Texture = GLOW; glowB.TextureMode = Enum.TextureMode.Stretch; glowB.Width0, glowB.Width1 = 4, 1.4; glowB.Transparency = NS(0.5); glowB.Parent = self.Liq
		self.FillRate = 1.2
		self:SetFill(newFill or 0)
		self.Surge = 1
		VFX.Sfx("Splash", self.C, 0.9, 1.2)
		VFX.Sfx("Charge", self.C, 0.8, 1.1)
		local s0 = time()
		while time() - s0 < 1.1 do
			local a, h = a0.WorldPosition, self.HeadAtt.WorldPosition
			local u = math.random()
			VFX.Sprite(a:Lerp(h, u) + V3(0, math.sin(u * math.pi) * 3, 0), { Tex = KB.Star, Color = GOLD_HOT, Size = { 0.7, 0 }, Life = 0.4, Bright = 2.5 })
			self.HamLight.Brightness = 2 + math.random() * 2
			self.HamLight.Color = GOLD
			task.wait(0.03)
			if not self.Folder then return end
		end
		b:Destroy(); glowB:Destroy(); a0:Destroy()
		local h = self.HeadAtt.WorldPosition
		VFX.Sprite(h, { Tex = KB.BigGlow, Color = GOLD_HOT, Size = { 4, 14 }, Life = 0.5, Bright = 3 })
		VFX.Burst(h, { Count = 30, Texture = KB.Star, Color = GOLD_HOT, Size = { 0.6, 0 }, Life = { 0.4, 0.9 }, Speed = { 8, 20 }, Drag = 3 })
		VFX.Burst(h, { Count = 5, Texture = KB.Arc1, Color = ELEC_HOT, Size = { 2.5, 4 }, Life = { 0.2, 0.3 }, Speed = { 0, 0 }, Flip = { VFX.G4 } })
		self:_strike(h, 170, 1.2, 0.4)
		self:_snd("Strike", 0.7)
		VFX.Sfx("Zap", h, 0.8)
		self:_shake(0.7)
		self:_flash(0.35, 0.35)
		task.wait(0.45)
		if not self.Folder then return end
		self.HamLight.Color = ELEC
		self.FillRate = 1.5
		self:_pose("Ready", 6)
		self:_aura(0.3)
		self.Busy = false
		self.FarmClock = 0
		self.FarmCycle = nil
	end)
end

function Stage:Upgrade()
	if not self.Folder then return end
	local base = V3(self.C.X, self.C.Y + 0.2, self.C.Z)
	VFX.RuneCircle(CF(base), 7, 2.6, { Main = GOLD_HOT, Deep = GOLD, Mist = Color3.fromRGB(255, 220, 150) }, { Points = 14 })
	VFX.GlowColumn(self.Ct, GOLD_HOT, 26, 5, 2.2, 1.6)
	VFX.Burst(self.Ct, { CF = VFX.Facing(self.Ct, Y), Count = 40, Texture = KB.Star, Color = GOLD_HOT, Size = { 0.6, 0 }, Life = { 0.8, 1.6 }, Speed = { 10, 26 }, Spread = 40, Drag = 2 })
	self:_strike(self.Ct, 200, 1.4, 0.4)
	self:_snd("Sting", 0.7)
	VFX.Sfx("Choir", self.C, 0.9)
	self.Surge = 1
	self:_shake(0.6)
	self:_flash(0.3, 0.5)
end

------------------------------------------------------------------ character hide/restore
function Stage:_hideChar(ch)
	self.HiddenChar = {}
	for _, d in ch:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(self.HiddenChar, { d, d.LocalTransparencyModifier })
			d.LocalTransparencyModifier = 1
		end
	end
end
function Stage:_restoreGuis()
	for _, g in self.HiddenGuis or {} do if g.Parent then g.Enabled = true end end
	self.HiddenGuis = nil
end
function Stage:_restoreChar()
	for _, e in self.HiddenChar or {} do if e[1].Parent then e[1].LocalTransparencyModifier = e[2] end end
	self.HiddenChar = nil
	self.HiddenCharModel = nil
end

------------------------------------------------------------------ enter / leave / skip
function Stage:Enter(full)
	if self.Folder then self:Leave(true) end
	self.T0 = time()
	self.Busy, self.Farming, self.Settled = false, false, false
	self:_mood(true)
	self:_build()
	self.SavedCam = self.SavedCam or (function()
		local c = Workspace.CurrentCamera
		return { Type = c.CameraType, CF = c.CFrame, Fov = c.FieldOfView, Subject = c.CameraSubject }
	end)()
	if not self.Rig then
		self:_stormMix(0)
		self.Settled = true
	else
		self:_setupCine(full)
		self.CineT = if full then 0 else T_LAND - 0.02
		self.PrevT = self.CineT - 0.001
		self.Cine = true
		self.HiddenGuis = {}
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and g ~= self.FXGui and g.Name ~= "VantageFarm" then table.insert(self.HiddenGuis, g); g.Enabled = false end
		end
		self:_bars(true)
		self.FadeF.BackgroundTransparency = 0
		TweenService:Create(self.FadeF, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		self:_cineAt(self.CineT, 0)
	end
	local seekConn = player:GetAttributeChangedSignal("FarmSeek"):Connect(function()
		if not RunService:IsStudio() or not self.Cine then return end
		local v = player:GetAttribute("FarmSeek")
		if type(v) == "number" then
			self.SeekT = v
			-- re-arm events and fire the ones right at the seek point so effects show
			for _, e in self.Events do e.done = e.t < v - 0.35 end
			self.PrevT = v - 0.35
			self.CineT = v
		else
			self.SeekT = nil
		end
	end)
	self.SeekConn = seekConn
	RunService:BindToRenderStep("FarmStage", Enum.RenderPriority.Camera.Value + 20, function(dt)
		if not self.Folder then return end
		local wall = time() - self.T0
		if self.Cine then
			local t
			if self.SeekT then
				t = self.SeekT
			else
				-- speed ramp: the first instant of the launch plays in slow motion
				local rate = if self.CineT >= T_LAUNCH and self.CineT < T_LAUNCH + 0.3 then 0.3 else 1
				t = self.CineT + math.min(dt, 1 / 20) * rate
			end
			self:_runEvents(t, self.PrevT)
			self.PrevT, self.CineT = t, t
			self:_cineAt(t, dt)
			if t >= T_END and not self.SeekT then
				self.Cine = false
				self:_startFarming()
			end
		else
			self:_stepFarm(dt)
		end
		self:_stepRig(dt, wall)
		self:_stepLiquid(dt, wall)
		self:_stepCam(dt, wall)
	end)
end

function Stage:Skip()
	if not self.Folder or not self.Cine then return end
	self.Cine = false
	self.SeekT = nil
	self:_bars(false)
	self:_stormMix(0)
	if self.MusicS then self:_fade(self.MusicS, 0, 1) end
	for _, s in { self.WindL, self.FlyL } do self:_fade(s, 0, 0.3) end
	if self.HumS then self.HumS(0.2) self.HumS = nil end
	if self.RushPart then self.Rush.Rate = 0 end
	if self.Vortex then self.Vortex.Rate, self.Rain.Rate = 0, 0 end
	if self.GroundWind then self.GroundWind.Rate, self.GroundDust.Rate, self.Rocks.Rate, self.GroundGlow.Rate = 0, 0, 0, 0 end
	self:_dof(20, 0)
	if self.Rig then self:_startFarming() else self.Settled = true end
	self.FadeF.BackgroundTransparency = 0
	TweenService:Create(self.FadeF, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
end

function Stage:IsSettled()
	return self.Folder ~= nil and self.Settled == true
end

function Stage:Leave(keepCam)
	self.Cine, self.SeekT = false, nil
	self.Farming, self.Channeling, self.Busy, self.Settled = false, false, false, false
	if self.SeekConn then self.SeekConn:Disconnect() self.SeekConn = nil end
	if self.FarmHum then self.FarmHum(0.1) self.FarmHum = nil end
	if self.HumS then self.HumS(0.1) self.HumS = nil end
	pcall(RunService.UnbindFromRenderStep, RunService, "FarmStage")
	self:_restoreChar()
	self:_restoreGuis()
	if self.Folder then self.Folder:Destroy() end
	if self.FXGui then self.FXGui:Destroy() end
	if self.AmountGui then self.AmountGui:Destroy() end
	if self.SndFolder then self.SndFolder:Destroy() end
	self.Folder, self.FXGui, self.Rig, self.Liq, self.AmountGui, self.SndFolder = nil, nil, nil, nil, nil, nil
	self.StreakHead, self.RushPart, self.StreakLive, self.Events = nil, nil, false, nil
	self.MusicS, self.WindL, self.FlyL = nil, nil, nil
	self.CamCF, self.CamFov, self.ShakeAmp, self.FovKick = nil, nil, 0, 0
	self:_mood(false)
	local sv = self.SavedCam
	if sv and not keepCam then
		local c = Workspace.CurrentCamera
		c.CameraType, c.CFrame, c.FieldOfView = sv.Type, sv.CF, sv.Fov
		if sv.Subject then c.CameraSubject = sv.Subject end
		self.SavedCam = nil
	end
end

return Stage
