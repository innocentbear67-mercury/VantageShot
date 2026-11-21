--[[
	VANTAGE — WeaponEffects (client)
	Purely cosmetic: muzzle flash, smoke, shell casings, tracers, surface-specific impacts and
	every weapon / feedback sound. Used for the local player's predicted shots and for other
	players' shots (server "Shot" / "Melee" broadcasts).

	Audio
	  • Sound groups: VantageWeapon (guns, knife, reload), VantageEffects (impacts, confirmations),
	    VantageMusic (reserved for music). Volumes come from the Settings module.
	  • Gunfire uses a voice limiter (MaxVoices): older shots fade out over CutFade, the last shot
	    rings out naturally as the tail — automatic fire never stacks into a wall of noise.
	  • StartAt skips measured silent lead-ins, so every cue plays on the frame it is triggered.
	  • A compressor on the weapon group tames peaks.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Vantage.Weapons.WeaponConfig)
local VFXKit = require(ReplicatedStorage.Vantage.Weapons.VFXKit)
local SkinFX = require(ReplicatedStorage.Vantage.Weapons.SkinFX) -- per-skin flash / tracer / impact (cosmetic)

local V = Vector3.new
local C = Color3.fromRGB

local FX_FOLDER_NAME = "VantageWeaponFX"
local MAX_MARKS = 40
local MAX_SHELLS = 24

local SURFACE = {
	[Enum.Material.Metal] = "Metal",
	[Enum.Material.DiamondPlate] = "Metal",
	[Enum.Material.CorrodedMetal] = "Metal",
	[Enum.Material.Foil] = "Metal",
	[Enum.Material.Glass] = "Glass",
	[Enum.Material.Ice] = "Glass",
	[Enum.Material.ForceField] = "Glass",
	[Enum.Material.Neon] = "Glass",
}

local SURFACE_FX = {
	Concrete = { Spark = C(255, 220, 160), Sparks = 5, Dust = C(176, 176, 182), DustCount = 3, Mark = C(30, 30, 34) },
	Metal = { Spark = C(255, 200, 120), Sparks = 11, Dust = C(150, 150, 156), DustCount = 1, Mark = C(46, 44, 42) },
	Glass = { Spark = C(200, 235, 255), Sparks = 9, Dust = C(220, 236, 255), DustCount = 1, Mark = C(150, 175, 200) },
	Body = { Spark = C(255, 95, 95), Sparks = 7, Dust = C(255, 120, 120), DustCount = 1 },
}

local WeaponEffects = {}
WeaponEffects.__index = WeaponEffects

local function fxFolder(): Folder
	local f = Workspace:FindFirstChild(FX_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = FX_FOLDER_NAME
		f.Parent = Workspace
	end
	return f :: Folder
end

local function makeEmitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

-- finish particle specs (VFXKit.Finishes): { Tex, c, c2?, Size = {a,b}, Life = {a,b}, Speed?, Spread?, Accel?,
-- Drag?, Transp?, Emission?, Streak?, Rot?, Flip? } -> one ParticleEmitter (shot overhaul stage 2, 2026-11-18)
local function specEmitter(parent: Instance, sp)
	local T = VFXKit.Tex
	local NS = VFXKit.NS
	local props = {
		Texture = T[sp.Tex] or sp.Tex,
		LightEmission = sp.Emission or 1,
		LightInfluence = sp.LightInf or 0,
		Color = if sp.c2 then ColorSequence.new(sp.c, sp.c2) else ColorSequence.new(sp.c),
		Size = NS(0, sp.Size[1], 1, sp.Size[2]),
		Transparency = if sp.Transp then NS(0, sp.Transp[1], 1, sp.Transp[2]) else NS(0, 0, 0.7, 0.25, 1, 1),
		Lifetime = NumberRange.new(sp.Life[1], sp.Life[2]),
		Speed = NumberRange.new(sp.Speed and sp.Speed[1] or 0, sp.Speed and sp.Speed[2] or 0),
		SpreadAngle = Vector2.new(sp.Spread or 0, sp.Spread or 0),
		Acceleration = sp.Accel or Vector3.zero,
		Drag = sp.Drag or 0,
		EmissionDirection = Enum.NormalId.Front,
		Rotation = NumberRange.new(0, 360),
		ZOffset = 0.3,
	}
	if sp.Streak then
		props.Orientation = Enum.ParticleOrientation.VelocityParallel
		props.Rotation = NumberRange.new(VFXKit.StreakRotation)
	end
	if sp.Rot then
		props.RotSpeed = NumberRange.new(-(sp.RotSpeed or 260), sp.RotSpeed or 260)
	end
	if sp.Flip == "Grid2x2" then
		props.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		props.FlipbookMode = Enum.ParticleFlipbookMode.Random
	elseif sp.Flip == "Grid4x4" then
		props.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		props.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	return makeEmitter(parent, props)
end
-- shared rigs: one Terrain attachment + emitter(s) per spec table, moved and re-emitted
local residueRigs = setmetatable({}, { __mode = "k" })
local function residueRig(sp): (ParticleEmitter, Attachment)
	local r = residueRigs[sp]
	if r and r[2].Parent then return r[1], r[2] end
	local a = Instance.new("Attachment")
	a.Name = "FinishResidue"
	a.Parent = Workspace.Terrain
	local e = specEmitter(a, sp)
	residueRigs[sp] = { e, a }
	return e, a
end
local accentRigs = setmetatable({}, { __mode = "k" })
local function accentRig(list)
	local r = accentRigs[list]
	if r and r.a.Parent then return r end
	local a = Instance.new("Attachment")
	a.Name = "FinishAccent"
	a.Parent = Workspace.Terrain
	r = { a = a, E = {} }
	for i, sp in list do r.E[i] = specEmitter(a, sp) end
	accentRigs[list] = r
	return r
end
-- lay residue along a path segment every `Spacing` studs (returns the new laid-to distance)
local function layResidue(R, from: Vector3, dir: Vector3, laid: number, upto: number): number
	local sp = R.Spacing or 2
	if laid + sp > upto then return laid end
	local e, a = residueRig(R)
	while laid + sp <= upto do
		laid += sp
		a.WorldPosition = from + dir * laid
		e:Emit(1)
	end
	return laid
end

local function group(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	return g :: SoundGroup
end

local function flashEmitters(att: Attachment, Pf)
	local T = VFXKit.Tex
	local NS = VFXKit.NS
	local s = Pf.Size
	local GRID = Enum.ParticleFlipbookLayout.Grid2x2
	local RANDOM = Enum.ParticleFlipbookMode.Random
	local flash = makeEmitter(att, {
		Name = "Flash",
		Texture = if Pf.FlashTex then T[Pf.FlashTex] elseif Pf.Energy then T.Plasma else T.FlashFront,
		FlipbookLayout = GRID,
		FlipbookMode = RANDOM,
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Pf.Hot, Pf.Warm),
		Size = NS(0, s * 0.85, 0.35, s * 1.1, 1, s * 0.6),
		Transparency = NS(0, 0.1, 0.5, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.04 * (Pf.FlashLifeK or 1), 0.06 * (Pf.FlashLifeK or 1)),
		Speed = NumberRange.new(0, 0),
		Rotation = NumberRange.new(0, 360),
		LockedToPart = true,
		ZOffset = 0.6,
	})
	local petal = makeEmitter(att, {
		Name = "Petal", -- side flame cones, read from 3rd person and at angles
		Texture = T.FlashSide,
		FlipbookLayout = GRID,
		FlipbookMode = RANDOM,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rotation = NumberRange.new(VFXKit.StreakRotation),
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Pf.Hot, Pf.Warm),
		Size = NS(0, Pf.Petal * 0.7, 1, Pf.Petal),
		Transparency = NS(0, 0.2, 0.6, 0.45, 1, 1),
		Lifetime = NumberRange.new(0.045, 0.06),
		Speed = NumberRange.new(Pf.Petal * 6, Pf.Petal * 9),
		SpreadAngle = Vector2.new(12, 12),
		EmissionDirection = Enum.NormalId.Front,
		LockedToPart = true,
		ZOffset = 0.5,
	})
	local petalL = nil
	if Pf.PetalMode == "Side" then -- brake vents: flame cones out of the sides, not forward
		petal.EmissionDirection = Enum.NormalId.Right
		petal.SpreadAngle = Vector2.new(16, 16)
		petalL = petal:Clone()
		petalL.Name = "PetalL"
		petalL.EmissionDirection = Enum.NormalId.Left
		petalL.Parent = att
	end
	local core = makeEmitter(att, {
		Name = "Core",
		Texture = T.Glow,
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Pf.Hot, Pf.Warm),
		Size = NS(0, s * 0.6, 1, s * 0.2),
		Transparency = NS(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.035, 0.05),
		Speed = NumberRange.new(0, 0),
		LockedToPart = true,
		ZOffset = 0.7,
	})
	local sparks = makeEmitter(att, {
		Name = "Sparks",
		Texture = T.Spark,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rotation = NumberRange.new(VFXKit.StreakRotation),
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Pf.SparkColor),
		Size = NS(0, 0.2, 1, 0),
		Lifetime = NumberRange.new(0.06, 0.14),
		Speed = NumberRange.new(14, 30),
		SpreadAngle = Vector2.new(Pf.SparkSpread, Pf.SparkSpread),
		EmissionDirection = Enum.NormalId.Front,
		Acceleration = V(0, -12, 0),
		Drag = 5,
	})
	local ss = Pf.SmokeScale
	local smoke = makeEmitter(att, {
		Name = "Smoke",
		Texture = T.Smoke,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		LightInfluence = 0.8,
		Color = ColorSequence.new(Pf.SmokeTint or C(198, 204, 214)),
		Size = NS(0, 0.22 * ss, 1, 1.0 * ss),
		Transparency = NS(0, 0.45, 1, 1),
		Lifetime = NumberRange.new(0.45, 0.7),
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(15, 15),
		EmissionDirection = Enum.NormalId.Front,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Acceleration = V(0, 1.2, 0),
		Drag = 3,
	})
	local wisp = makeEmitter(att, {
		Name = "Wisp", -- lingering barrel smoke after a burst
		Texture = T.Smoke,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		LightInfluence = 0.8,
		Color = ColorSequence.new(if Pf.Energy then Pf.Warm else C(212, 218, 226)),
		LightEmission = if Pf.Energy then 0.6 else 0,
		Size = NS(0, 0.1, 1, 0.55),
		Transparency = NS(0, 0.6, 1, 1),
		Lifetime = NumberRange.new(1.0, 1.4),
		Speed = NumberRange.new(0.3, 0.7),
		SpreadAngle = Vector2.new(10, 10),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
		Acceleration = V(0, 1.8, 0),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 2,
	})
	local ring = nil
	if Pf.Ring then
		ring = makeEmitter(att, {
			Name = "Ring",
			Texture = T[Pf.RingTex or "Ring"],
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(Pf.Hot, Pf.Warm),
			Size = NS(0, s * 0.3 * (Pf.RingK or 1), 1, s * 1.5 * (Pf.RingK or 1)),
			Transparency = NS(0, 0.5, 1, 1),
			Lifetime = NumberRange.new(0.09, 0.11),
			Speed = NumberRange.new(0, 0),
			Rotation = NumberRange.new(0, 360),
			LockedToPart = true,
		})
	end
	local glint, heat = nil, nil
	if Pf.Glint then -- lens glint (Gilded, Quill string-snap)
		glint = makeEmitter(att, {
			Name = "Glint", Texture = T.Glint, LightEmission = 1, LightInfluence = 0,
			Color = ColorSequence.new(Pf.Hot), Size = NS(0, s * 1.6, 1, s * 0.5), Transparency = NS(0, 0.05, 1, 1),
			Lifetime = NumberRange.new(0.06, 0.08), Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(-12, 12),
			LockedToPart = true, ZOffset = 0.8,
		})
	end
	if Pf.HeatGlow then -- LMG barrel heat (sustained fire)
		heat = makeEmitter(att, {
			Name = "HeatGlow", Texture = T.Glow, LightEmission = 1, LightInfluence = 0,
			Color = ColorSequence.new(C(255, 130, 50), C(255, 50, 20)), Size = NS(0, s * 0.6, 1, s * 0.3), Transparency = NS(0, 0.35, 1, 1),
			Lifetime = NumberRange.new(0.25, 0.35), Speed = NumberRange.new(0, 0), LockedToPart = true, ZOffset = 0.2,
		})
	end
	local light = Instance.new("PointLight")
	light.Name = "FlashLight"
	light.Color = Pf.Light
	light.Range = Pf.LightRange
	light.Brightness = 0
	light.Shadows = false
	light.Parent = att
	return { Flash = flash, Petal = petal, PetalL = petalL, Core = core, Sparks = sparks, Smoke = smoke, Wisp = wisp, Ring = ring, Glint = glint, Heat = heat, Light = light, P = Pf }
end

function WeaponEffects.new()
	local self = setmetatable({}, WeaponEffects)
	self.Rng = Random.new()
	self.Marks = {}
	self.Shells = {}
	self.Rigs = {} -- attachment -> emitters (strong: weak Instance keys get dropped by the GC; cleared on Destroying)
	self.Voices = setmetatable({}, { __mode = "k" }) -- key -> { sounds }
	self.Flags = { Impacts = true, Shells = true, Smoke = true }
	self._flashes = {} -- recent muzzle flashes { pos, def, t } for matching skin tracers / impacts
	self._endFX = {} -- tracer end position key -> skin def / finish
	self._heat = {} -- muzzle attachment -> sustained-fire state (strong; cleared with the rig)

	self.WeaponGroup = group("VantageWeapon")
	self.EffectsGroup = group("VantageEffects")
	self.MusicGroup = group("VantageMusic")
	if not self.WeaponGroup:FindFirstChildOfClass("CompressorSoundEffect") then
		local comp = Instance.new("CompressorSoundEffect")
		comp.Threshold = -16
		comp.Ratio = 3.5
		comp.Attack = 0.004
		comp.Release = 0.18
		comp.GainMakeup = 2
		comp.Parent = self.WeaponGroup
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 2.5 -- a little extra body on the shots
		eq.MidGain = 0
		eq.HighGain = -1
		eq.Parent = self.WeaponGroup
	end

	-- preload every configured sound so the first shot is never late
	local ids = {}
	local function collect(t)
		for k, v in t do
			if type(v) == "table" then
				collect(v)
			elseif (k == "Id") and type(v) == "string" then
				table.insert(ids, v)
			end
		end
		if t.Ids then
			for _, id in t.Ids do
				table.insert(ids, id)
			end
		end
	end
	for _, w in Config.Weapons do
		if w.Sounds then
			collect(w.Sounds)
		end
	end
	local preload = {}
	for _, id in ids do
		local s = Instance.new("Sound")
		s.SoundId = id
		table.insert(preload, s)
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, preload)
	end)
	return self
end

-- ─── audio ────────────────────────────────────────────────────────────────
local CONFIRM = { Hit = true, Headshot = true, Kill = true }

function WeaponEffects:_newSound(cfg, id: string, parent: Instance?, groupOverride: SoundGroup?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = cfg.Volume or 0.5
	local speed = cfg.Speed or 1
	if cfg.PitchMin then
		speed *= self.Rng:NextNumber(cfg.PitchMin, cfg.PitchMax)
	end
	s.PlaybackSpeed = speed
	if cfg.StartAt then
		s.TimePosition = cfg.StartAt
	end
	-- 2026-11-17: Region = NumberRange (seconds) plays only that slice (trim long tails / pick one
	-- shot out of a multi-shot file)
	if cfg.Region then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = cfg.Region
	end
	s.SoundGroup = groupOverride or self.WeaponGroup
	s.Parent = parent or self.WeaponGroup
	return s
end

local function pick(self, cfg): string?
	if cfg.Ids then
		return cfg.Ids[self.Rng:NextInteger(1, #cfg.Ids)]
	end
	return cfg.Id
end

-- A weapon's sound entry, falling back to the default weapon's (placeholder audio for weapons
-- that do not define that cue yet, and the shared hit / headshot / kill confirmations).
local function soundFor(weaponId: string?, name: string)
	local w = weaponId and Config.Weapons[weaponId]
	local cfg = w and w.Sounds and w.Sounds[name]
	if cfg then
		return cfg
	end
	local d = Config.Weapons[Config.DefaultWeapon]
	return d and d.Sounds and d.Sounds[name]
end
WeaponEffects.SoundFor = soundFor

-- 2026-11-17 mix (measured, Hypershot ladder): own gunfire is the loudest thing; reload / handling
-- sits ~10 dB under it, footsteps ~24 dB under it
local OWN_FIRE_MIX = 1.8
local CUE_MIX = { MagOut = 0.5, MagIn = 0.5, Bolt = 0.55, ShellIn = 0.55, Equip = 0.8, Empty = 0.6, Vent = 0.7, Overheat = 0.8 }

-- name: sound key inside WeaponConfig.Weapons[weaponId].Sounds
function WeaponEffects:PlayCue(weaponId: string, name: string, parent: Instance?)
	local cfg = soundFor(weaponId, name)
	if not cfg then
		return
	end
	local g = if CONFIRM[name] then self.EffectsGroup else self.WeaponGroup
	local layers = cfg.Layers or { cfg }
	for _, layer in layers do
		local id = pick(self, layer)
		if id then
			local s = self:_newSound(layer, id, parent, g); s.Volume *= (CUE_MIX[name] or 1)
			if parent and parent:IsA("BasePart") or (parent and parent:IsA("Attachment")) then
				s.RollOffMode = Enum.RollOffMode.InverseTapered
				s.RollOffMinDistance = 6
				s.RollOffMaxDistance = cfg.RollOff or 120
			end
			s:Play()
			Debris:AddItem(s, 3)
		end
	end
end

-- voice-limited gunfire; key = any table/instance identifying the shooter
function WeaponEffects:_voiceLimited(key, cfg, parent: Instance?, is3D: boolean)
	local voices = self.Voices[key]
	if not voices then
		voices = {}
		self.Voices[key] = voices
	end
	local max = cfg.MaxVoices or 2
	while #voices >= max do
		local old = table.remove(voices, 1)
		if old and old.Parent then
			local fade = cfg.CutFade or 0.07
			local start = old.Volume
			local t0 = os.clock()
			local conn
			conn = RunService.Heartbeat:Connect(function()
				local a = (os.clock() - t0) / fade
				if a >= 1 or not old.Parent then
					conn:Disconnect()
					old:Destroy()
				else
					old.Volume = start * (1 - a)
				end
			end)
		end
	end
	local id = pick(self, cfg)
	if not id then
		return
	end
	local s = self:_newSound(cfg, id, parent, self.WeaponGroup)
	if not is3D then
		s.Volume *= OWN_FIRE_MIX
	end
	if is3D then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = cfg.RollOff or 300
	end
	s:Play()
	table.insert(voices, s)
	Debris:AddItem(s, 4)
	-- 2026-11-17: layered gunfire. Each layer (crack / body / mechanism) starts on the same frame as
	-- the main shot; layers are short one-shots, so they are not voice-limited.
	if cfg.Layers then
		for _, l in cfg.Layers do
			if is3D and l.FirstPersonOnly then
				continue
			end
			local lid = pick(self, l)
			if lid then
				local ls = self:_newSound(l, lid, parent, self.WeaponGroup)
				if not is3D then
					ls.Volume *= OWN_FIRE_MIX
				end
				if is3D then
					ls.RollOffMode = Enum.RollOffMode.InverseTapered
					ls.RollOffMinDistance = 8
					ls.RollOffMaxDistance = l.RollOff or cfg.RollOff or 300
				end
				ls:Play()
				Debris:AddItem(ls, 2)
			end
		end
	end
end

function WeaponEffects:PlayFire(weaponId: string)
	local cfg = soundFor(weaponId, "Fire")
	self:_voiceLimited(self, cfg, self.WeaponGroup, false)
end

function WeaponEffects:PlayFire3D(weaponId: string?, parent: Instance, key)
	local w = weaponId and Config.Weapons[weaponId]
	local own = w and w.Sounds
	local cfg = if own and (own.FireThirdPerson or own.Fire) then (own.FireThirdPerson or own.Fire) else (soundFor(nil, "FireThirdPerson") or soundFor(nil, "Fire"))
	self:_voiceLimited(key or parent, cfg, parent, true)
end

-- ─── visuals ──────────────────────────────────────────────────────────────
local function pointAttachment(pos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	return a
end

-- skin FX matching: a shot's tracer / impact find the skin of the flash at the same muzzle
local SKIN_WINDOW = 0.15
local function endKey(p: Vector3): string
	return string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z)
end
function WeaponEffects:_skinAt(pos: Vector3)
	local now, best, bestD = os.clock(), nil, 1.5
	for i = #self._flashes, 1, -1 do
		local f = self._flashes[i]
		if now - f.t > SKIN_WINDOW then
			table.remove(self._flashes, i)
		else
			local dd = (f.pos - pos).Magnitude
			if dd < bestD then best, bestD = f, dd end
		end
	end
	return best and best.def or nil
end

-- skin burst at the ejection port when a pump / bolt is worked (shot overhaul stage 6). Cosmetic only;
-- small, off to the side of the view, never at the crosshair.
function WeaponEffects:Rack(att: Attachment?)
	if not att then
		return
	end
	local def = SkinFX.Get(SkinFX.ForAttachment(att))
	if not (def and def.Rack) then
		return
	end
	local cam = workspace.CurrentCamera
	local n = (Vector3.yAxis + (if cam then cam.CFrame.RightVector * 0.7 else Vector3.zero)).Unit
	SkinFX.Burst(def.Rack, att.WorldPosition, n)
end

function WeaponEffects:MuzzleFlash(att: Attachment)
	local skinDef = SkinFX.Get(SkinFX.ForAttachment(att))
	local Pf, _, skinId = VFXKit.ResolveForInstance(att)
	local rig = self.Rigs[att]
	if rig and rig.SkinId ~= skinId then -- skin changed on this gun: rebuild the flash rig
		for _, k in { "Flash", "Petal", "PetalL", "Core", "Sparks", "Smoke", "Wisp", "Ring", "Glint", "Heat", "Light" } do
			local o = rig[k]
			if o then o:Destroy() end
		end
		self.Rigs[att] = nil
		rig = nil
	end
	-- sustained fire: consecutive shots less than 0.3 s apart
	local now = os.clock()
	local st = self._heat[att]
	if not st then
		st = { n = 0, t = 0, shot = 0 }
		self._heat[att] = st
	end
	st.n = if now - st.t < 0.3 then st.n + 1 else 1
	st.t = now
	st.shot += 1
	table.insert(self._flashes, { pos = att.WorldPosition, def = skinDef, t = now, P = Pf, Shot = st.shot, Heat = st.n })
	if skinDef then
		SkinFX.Flash(att, skinDef)
		return
	end
	if not rig then
		rig = flashEmitters(att, Pf)
		rig.SkinId = skinId
		self.Rigs[att] = rig
		att.Destroying:Once(function()
			self.Rigs[att] = nil
			self._heat[att] = nil
		end)
		self._rigAdds = (self._rigAdds or 0) + 1
		if self._rigAdds % 64 == 0 then
			for a in self.Rigs do
				if not a.Parent then self.Rigs[a] = nil; self._heat[a] = nil end
			end
		end
	end
	local H = Pf.Heat
	local heat = st.n
	if Pf.FlashCount > 0 then
		rig.Flash:Emit(Pf.FlashCount)
	end
	rig.Core:Emit(1)
	if Pf.PetalCount > 0 then
		if rig.PetalL then
			if H and H.Alternate then
				local side = if st.shot % 2 == 0 then rig.PetalL else rig.Petal
				side:Emit(Pf.PetalCount)
			else
				rig.PetalL:Emit(Pf.PetalCount)
				rig.Petal:Emit(Pf.PetalCount)
			end
		else
			rig.Petal:Emit(Pf.PetalCount)
		end
	end
	local sparks = self.Rng:NextInteger(Pf.Sparks[1], Pf.Sparks[2]) + (Pf.SparkAdd or 0)
	if H and H.SparkAdd and heat >= (H.From or 1) then
		sparks += H.SparkAdd
	end
	if sparks > 0 then
		rig.Sparks:Emit(sparks)
	end
	if self.Flags.Smoke and Pf.SmokeChance > 0 and self.Rng:NextNumber() < Pf.SmokeChance then
		rig.Smoke:Emit(Pf.SmokeCount)
	end
	if H and H.Wisp and heat >= (H.From or 1) and st.shot % H.Wisp == 0 then
		rig.Wisp:Emit(1)
	end
	if rig.Ring and (not (H and H.RingFrom) or heat >= H.RingFrom) then
		rig.Ring:Emit(1)
	end
	if rig.Glint then
		rig.Glint:Emit(1)
	end
	if rig.Heat and heat >= Pf.HeatGlow then
		rig.Heat:Emit(1)
	end
	rig.Light.Brightness = Pf.LightB
	task.delay(0.045, function()
		rig.Light.Brightness = 0
	end)
end

-- lingering barrel smoke after a sustained burst
function WeaponEffects:BurstSmoke(att: Attachment)
	if not self.Flags.Smoke then
		return
	end
	local rig = self.Rigs[att]
	if rig then
		rig.Wisp:Emit(3)
		task.delay(0.25, function()
			if rig.Wisp.Parent then
				rig.Wisp:Emit(2)
			end
		end)
	end
end

function WeaponEffects:_flashAt(pos: Vector3)
	local now, best, bestD = os.clock(), nil, 1.5
	for i = #self._flashes, 1, -1 do
		local f = self._flashes[i]
		if now - f.t <= SKIN_WINDOW then
			local dd = (f.pos - pos).Magnitude
			if dd < bestD then
				best, bestD = f, dd
			end
		end
	end
	return best
end

function WeaponEffects:Tracer(from: Vector3, to: Vector3, skip: number?)
	task.defer(function()
		local rec = self:_flashAt(from)
		local def = self:_skinAt(from)
		if def then
			self._endFX[endKey(to)] = { def = def, t = os.clock() }
			SkinFX.Tracer(from, to, skip, def, rec)
		else
			if rec and rec.P and rec.P.Finish then
				self._endFX[endKey(to)] = { fin = rec.P, t = os.clock() }
			end
			self:_TracerDefault(from, to, skip, rec and rec.P, rec)
		end
	end)
end

-- textured beam streak travelling at bullet speed; bright head, fading tail
-- pooled default tracers (shot overhaul stage 1, 2026-11-18): each slot is one Beam + two Terrain
-- attachments, reused; one RenderStepped steps every live tracer (was a new beam + connection per shot)
local trFree, trLive, trConn = {}, {}, nil
local function trStep()
	local now = SkinFX.Now()
	local i, n = 1, #trLive
	while i <= n do
		local s = trLive[i]
		-- 2026-11-19 fix: tail runs off the UNclamped head, so it reaches the end and the slot is freed
		-- (was: head clamped first -> tail stuck one streak short -> every tracer froze at the hit point)
		local raw = s.start + (now - s.t0) * s.speed
		local head = math.min(raw, s.len)
		local tail = math.max(s.start, raw - s.streak)
		if tail >= s.len - 0.1 or not s.a0.Parent then
			s.beam.Enabled = false
			if s.a0.Parent then table.insert(trFree, s) end
			trLive[i] = trLive[n]; trLive[n] = nil; n -= 1
		else
			s.a0.WorldPosition = s.from + s.dir * tail
			s.a1.WorldPosition = s.from + s.dir * head
			if s.res then
				s.laid = layResidue(s.res, s.from, s.dir, s.laid, math.min(head, s.len * 0.75))
			end
			i += 1
		end
	end
	if n == 0 and trConn then
		trConn:Disconnect()
		trConn = nil
	end
end
function WeaponEffects:_TracerDefault(from: Vector3, to: Vector3, skip: number?, Pf, rec)
	Pf = Pf or VFXKit.Default
	local d = to - from
	local len = d.Magnitude
	if len < 3 then
		return
	end
	local dir = d.Unit
	local startAt = math.min(skip or 0, len - 1)
	local s = table.remove(trFree)
	while s and not s.a0.Parent do s = table.remove(trFree) end
	if not s then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = "TracerA0", "TracerA1"
		a0.Parent, a1.Parent = Workspace.Terrain, Workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = VFXKit.Tex.Tracer
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Transparency = NumberSequence.new(0)
		beam.Parent = a0
		s = { a0 = a0, a1 = a1, beam = beam }
	end
	-- finish tracer variant (Carbon: dashed strip) + rhythm (Gilded: every 4th round)
	local Tt = Pf.Tracer
	local tex = Tt and Tt.Tex
	if s.tex ~= tex then
		s.tex = tex
		if tex then
			s.beam.Texture = VFXKit.Tex[tex]
			s.beam.TextureMode = Enum.TextureMode.Wrap
			s.beam.TextureLength = Tt.Wrap or 1.5
		else
			s.beam.Texture = VFXKit.Tex.Tracer
			s.beam.TextureMode = Enum.TextureMode.Stretch
			s.beam.TextureLength = 1
		end
	end
	local col, wk = Pf.TracerColor, 1
	local E = Pf.Every
	if E and rec and rec.Shot and rec.Shot % E.N == 0 then
		col, wk = E.Color or col, E.WidthK or 1.6
	end
	if s.col ~= col then
		s.col = col
		s.beam.Color = ColorSequence.new(col)
	end
	s.beam.Width0 = Pf.TracerWidth * 0.4 * wk
	s.beam.Width1 = Pf.TracerWidth * wk
	s.res = Pf.Residue
	s.laid = startAt
	local p0 = from + dir * startAt
	s.a0.WorldPosition, s.a1.WorldPosition = p0, p0
	s.from, s.dir, s.len, s.start, s.streak, s.speed, s.t0 = from, dir, len, startAt, math.min(len, Pf.TracerLen), 950, SkinFX.Now()
	s.beam.Enabled = true
	table.insert(trLive, s)
	if not trConn then
		trConn = RunService.Heartbeat:Connect(trStep) -- runs even when frames are not drawn
	end
end

local function surfaceOf(kind: string, material): string
	if kind == "Character" then
		return "Body"
	end
	if typeof(material) == "EnumItem" then
		return SURFACE[material] or "Concrete"
	elseif type(material) == "string" then
		local ok, m = pcall(function()
			return Enum.Material[material]
		end)
		if ok and m then
			return SURFACE[m] or "Concrete"
		end
	end
	return "Concrete"
end
WeaponEffects.SurfaceOf = surfaceOf

-- energy bolt (ER-04 Arc): a glowing slug travelling at the projectile speed; the impact
-- ({ normal, material, weaponId }) plays when it arrives.
-- Stage 1 (2026-11-18): resolved one tick later (task.defer) so the muzzle flash has registered the
-- shooter's skin; a skinned bolt takes the skin's laser colours and the skin's impact. Body, light
-- and impact emitters are pooled.
local boltRigs = {}
local function boltImpactRig(color: Color3)
	local key = color:ToHex()
	local r = boltRigs[key]
	if r and r.a.Parent then return r end
	local a = Instance.new("Attachment")
	a.Name = "BoltImpactRig"
	a.Parent = Workspace.Terrain
	local NS = VFXKit.NS
	r = {
		a = a,
		e = makeEmitter(a, {
			Texture = VFXKit.Tex.Plasma,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.Random,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(color),
			Size = NS(0, 0.7, 1, 1.6),
			Transparency = NS(0, 0, 1, 1),
			Lifetime = NumberRange.new(0.12, 0.2),
			Speed = NumberRange.new(0, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-220, 220),
		}),
		sp = makeEmitter(a, {
			Texture = VFXKit.Tex.Spark,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Rotation = NumberRange.new(VFXKit.StreakRotation),
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(color),
			Size = NS(0, 0.28, 1, 0),
			Lifetime = NumberRange.new(0.1, 0.25),
			Speed = NumberRange.new(6, 16),
			SpreadAngle = Vector2.new(70, 70),
			Drag = 3,
		}),
		rg = makeEmitter(a, {
			Texture = VFXKit.Tex.Ring,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(color),
			Size = NS(0, 0.3, 1, 2.4),
			Transparency = NS(0, 0.1, 1, 1),
			Lifetime = NumberRange.new(0.18, 0.18),
			Speed = NumberRange.new(0, 0),
		}),
	}
	boltRigs[key] = r
	return r
end

local function skinLaser(def)
	return def and def.Tracer and def.Tracer.Laser or nil
end

function WeaponEffects:Bolt(from: Vector3, to: Vector3, P, impact)
	task.defer(function()
		self:_Bolt(from, to, P, impact, self:_skinAt(from), self:_flashAt(from))
	end)
end

function WeaponEffects:_Bolt(from: Vector3, to: Vector3, P, impact, def, rec)
	local d = to - from
	local len = d.Magnitude
	if len < 0.5 then
		return
	end
	local dir = d.Unit
	local L = skinLaser(def)
	local fin = if rec and rec.P and rec.P.Finish then rec.P else nil
	local color = (L and L.Color) or (fin and fin.Bolt) or P.Color or C(80, 235, 255)
	local size = P.Size or 0.35
	local body = SkinFX._cyl(color, size, 0)
	body.Size = V(size * 4, size, size)
	local coreCol = (L and (L.Core or C(255, 255, 245))) or (fin and fin.BoltCore) or nil
	local core = if coreCol then SkinFX._cyl(coreCol, size * 0.45, 0) else nil
	local laid = 0
	if core then core.Size = V(size * 4.3, size * 0.45, size * 0.45) end
	local light = SkinFX._poolLight(from, color, 2.2, 7)
	local speed = P.Speed or 360
	local maxT = (P.Lifetime or 1.6) + 0.2
	local t0 = SkinFX.Now()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local el = SkinFX.Now() - t0
		local travelled = math.min(el * speed, len)
		local at = from + dir * travelled
		local cf = CFrame.lookAt(at, at + dir) * CFrame.Angles(0, math.rad(90), 0)
		body.CFrame = cf
		if core then core.CFrame = cf end
		;(light.Parent :: Attachment).WorldPosition = at
		if fin and fin.Residue then
			laid = layResidue(fin.Residue, from, dir, laid, math.min(travelled, len * 0.9))
		end
		if travelled >= len or el > maxT then
			conn:Disconnect()
			SkinFX._freeCyl(body)
			if core then SkinFX._freeCyl(core) end
			SkinFX._freeLight(light)
			if impact and travelled >= len then
				if def then
					self._endFX[endKey(to)] = { def = def, t = os.clock() }
				elseif fin then
					self._endFX[endKey(to)] = { fin = fin, t = os.clock() }
				end
				self:Impact(to, impact[1], "World", impact[2], impact[3])
				local r = boltImpactRig(color)
				r.a.WorldPosition = to + impact[1] * 0.1
				r.e:Emit(2)
				r.sp:Emit(12)
				r.rg:Emit(1)
			end
		end
	end)
end

-- 2026-11-18: arcing projectile (Projectile.Gravity: Quill bolts, Havoc rounds). The path is simulated
-- here with the same steps as the server (straight segments per 1/60 s); the round flies along it.
-- Rounds with Splash leave the blast to the server's "Explode" broadcast.
function WeaponEffects:BoltArc(from: Vector3, dir: Vector3, P, params: RaycastParams?, weaponId: string?)
	task.defer(function()
		self:_BoltArc(from, dir, P, params, weaponId, self:_skinAt(from), self:_flashAt(from))
	end)
end

function WeaponEffects:_BoltArc(from: Vector3, dir: Vector3, P, params: RaycastParams?, weaponId: string?, def, rec)
	local speed, g = P.Speed or 200, P.Gravity or 0
	local dt = 1 / 60
	local pts, pos, vel = { from }, from, dir.Unit * speed
	local hitRes
	for _ = 1, math.floor((P.Lifetime or 2) / dt) do
		local step = vel * dt
		local r = if params then Workspace:Raycast(pos, step, params) else Workspace:Raycast(pos, step)
		if r then
			table.insert(pts, r.Position)
			hitRes = r
			break
		end
		pos += step
		vel += V(0, -g * dt, 0)
		table.insert(pts, pos)
	end
	if #pts < 2 then
		return
	end
	local L = skinLaser(def)
	local fin = if rec and rec.P and rec.P.Finish then rec.P else nil
	local color = (L and L.Color) or (fin and fin.Bolt) or P.Color or C(80, 235, 255)
	local size = P.Size or 0.3
	local BS = def and def.Bolt -- skin path design: { Marks = spec, Ghost = true, Blink = true }
	local acc, lastAt, lastGhost = 0, pts[1], 0
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Shape = if P.Splash then Enum.PartType.Ball else Enum.PartType.Cylinder
	p.Size = if P.Splash then V(size, size, size) else V(size * 5, size * 0.5, size * 0.5)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = V(-p.Size.X / 2, 0, 0), V(p.Size.X / 2, 0, 0)
	if P.Splash then a0.Position, a1.Position = V(0, size * 0.3, 0), V(0, -size * 0.3, 0) end
	a0.Parent, a1.Parent = p, p
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = if P.Splash then 0.35 else 0.18
	tr.LightEmission = 1
	tr.FaceCamera = true
	tr.Color = ColorSequence.new(color)
	tr.Transparency = NumberSequence.new(0.2, 1)
	tr.WidthScale = NumberSequence.new(1, 0)
	tr.Parent = p
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = color, 6, 2
	light.Parent = p
	p.CFrame = CFrame.lookAt(pts[1], pts[2]) * CFrame.Angles(0, math.rad(90), 0)
	p.Parent = fxFolder()
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local k = (os.clock() - t0) / dt
		local i = math.floor(k) + 1
		if i >= #pts then
			conn:Disconnect()
			p.Transparency = 1
			light.Enabled = false
			Debris:AddItem(p, tr.Lifetime)
			if P.Splash and def and def.Explode then -- the skin's blast (cosmetic, inside the real blast radius)
				SkinFX.Burst(def.Explode, pts[#pts], if hitRes then hitRes.Normal else Vector3.yAxis, def.ExplodeDecal)
			end
			if hitRes and not P.Splash then
				if def then
					self._endFX[endKey(hitRes.Position)] = { def = def, t = os.clock() }
				elseif fin then
					self._endFX[endKey(hitRes.Position)] = { fin = fin, t = os.clock() }
				end
				self:Impact(hitRes.Position, hitRes.Normal, "World", hitRes.Material, weaponId)
			end
			return
		end
		local a, b = pts[i], pts[i + 1]
		local at = a:Lerp(b, k - (i - 1))
		if BS then
			local now2 = os.clock()
			if BS.Marks then
				acc += (at - lastAt).Magnitude
				local sp = BS.Marks.Spacing or 2
				while acc >= sp do
					acc -= sp
					SkinFX.EmitMark(BS.Marks, at)
				end
			end
			if BS.Ghost and now2 - lastGhost > 0.03 then
				lastGhost = now2
				SkinFX.Ghost(at, color, size * 1.4, 0.2)
			end
			if BS.Blink then -- blinks faster as it flies (Detonator, Minefield)
				local el = now2 - t0
				light.Brightness = if math.floor(el * (4 + el * 14)) % 2 == 0 then 4 else 0.3
			end
		end
		lastAt = at
		if (b - a).Magnitude > 1e-3 then
			p.CFrame = CFrame.lookAt(at, b) * CFrame.Angles(0, math.rad(90), 0)
		else
			p.Position = at
		end
	end)
end

-- 2026-11-18: continuous beam (Beam config: BX-3 Helix). Every shot refreshes the beam for `key`
-- (the controller / the shooter's character); it follows the muzzle each frame and fades out ~0.12 s
-- after the last shot, so rapid ticks read as one steady beam.
local beams = {}
local beamConn
function WeaponEffects:BeamPulse(key, att: Attachment, to: Vector3, B)
	local def = SkinFX.Get(SkinFX.ForAttachment(att))
	local L = skinLaser(def)
	local fp = VFXKit.ResolveForInstance(att)
	local fin = if fp.Finish then fp else nil
	local b = beams[key]
	if b and (b.Def ~= def or b.Fin ~= fin) and b.A1.Parent then
		b.A1:Destroy()
	end
	if not b or not b.A1.Parent or b.Def ~= def or b.Fin ~= fin then
		local a1 = Instance.new("Attachment")
		a1.WorldPosition = to
		a1.Parent = Workspace.Terrain
		local function beam(color, width, tex)
			local bm = Instance.new("Beam")
			bm.Attachment0, bm.Attachment1 = att, a1
			bm.FaceCamera = true
			bm.LightEmission = 1
			bm.LightInfluence = 0
			bm.Segments = 1
			bm.Color = ColorSequence.new(color)
			bm.Width0, bm.Width1 = width, width * 0.8
			bm.Transparency = NumberSequence.new(0.05)
			if tex then
				bm.Texture = tex
				bm.TextureMode = Enum.TextureMode.Wrap
				bm.TextureLength = 3
				bm.TextureSpeed = 4
			end
			bm.Parent = a1
			return bm
		end
		local col = (L and L.Color) or (fin and fin.Bolt) or B.Color or C(90, 190, 255)
		local glow = beam(col, B.Width or 0.35, (def and def.BeamTex) or (VFXKit.Tex and VFXKit.Tex.Plasma) or nil)
		glow.Transparency = NumberSequence.new(0.35)
		local core = beam((L and L.Core) or (fin and fin.BoltCore) or C(235, 250, 255), (B.Width or 0.35) * 0.3)
		local spark = Instance.new("ParticleEmitter")
		spark.Texture = VFXKit.Tex and VFXKit.Tex.Spark or ""
		spark.LightEmission = 1
		spark.Color = ColorSequence.new(col)
		spark.Size = NumberSequence.new(0.25, 0)
		spark.Lifetime = NumberRange.new(0.1, 0.25)
		spark.Speed = NumberRange.new(4, 10)
		spark.SpreadAngle = Vector2.new(70, 70)
		spark.Rate = 40
		spark.Parent = a1
		b = { A1 = a1, Glow = glow, Core = core, W = B.Width or 0.35, Def = def, Fin = fin }
		beams[key] = b
	end
	b.Glow.Attachment0, b.Core.Attachment0 = att, att
	b.To = to
	b.Last = os.clock()
	if not beamConn then
		beamConn = RunService.RenderStepped:Connect(function(dt)
			local now = os.clock()
			local any = false
			for k, s in beams do
				any = true
				local age = now - s.Last
				if age > 0.12 or not s.A1.Parent then
					s.A1:Destroy()
					beams[k] = nil
				else
					s.A1.WorldPosition = s.A1.WorldPosition:Lerp(s.To, math.min(1, dt * 30))
					local w = s.W * (0.85 + 0.3 * math.random())
					s.Glow.Width0, s.Glow.Width1 = w, w * 0.8
					local D = s.Def
					if D and D.BeamL and now - (s.SigT or 0) > (D.BeamEvery or 0.12) then -- skin extras along the beam
						s.SigT = now
						local a0 = s.Glow.Attachment0
						if a0 and a0.Parent then
							SkinFX.Extras(a0.WorldPosition, s.A1.WorldPosition, D.BeamL)
						end
					end
				end
			end
			if not any then
				beamConn:Disconnect()
				beamConn = nil
			end
		end)
	end
end

function WeaponEffects:Impact(pos: Vector3, normal: Vector3, kind: string, material, weaponId: string?)
	task.defer(function()
		local k = endKey(pos)
		local rec = self._endFX[k]
		self._endFX[k] = nil
		local def = (rec and os.clock() - rec.t < 1 and rec.def) or self:_skinAt(pos) or nil
		local fin = rec and os.clock() - rec.t < 1 and rec.fin or nil
		if def then
			SkinFX.Impact(pos, normal, def, kind)
		end
		self:_ImpactDefault(pos, normal, kind, material, weaponId, def, fin)
	end)
end

-- 2026-11-17: a bullet mark only goes on a VISIBLE world surface. Shots that hit the local player
-- (their shield panels / body) or invisible zone walls used to leave 0.2-stud black discs right in
-- front of the camera.
local function markSurfaceOk(pos: Vector3, normal: Vector3): boolean
	local cam = Workspace.CurrentCamera
	if cam and (cam.CFrame.Position - pos).Magnitude < 4 then
		return false
	end
	local hit = Workspace:Raycast(pos + normal * 0.15, -normal * 0.4)
	if not hit then
		return false
	end
	local p = hit.Instance
	if p.Transparency >= 0.9 or (cam and p:IsDescendantOf(cam)) then
		return false
	end
	local model = p:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false
	end
	return true
end

-- pooled impact rigs (stage 1, 2026-11-18): one emitter set per surface, moved and re-emitted;
-- bullet marks are reused (capped at MAX_MARKS, hidden after 12 s) instead of created + Debris'd
local impactRigs = {}
local function impactRig(surface: string, fx)
	local r = impactRigs[surface]
	if r and r.a.Parent then return r end
	local a = Instance.new("Attachment")
	a.Name = "ImpactRig_" .. surface
	a.Parent = Workspace.Terrain
	local T = VFXKit.Tex
	local NS = VFXKit.NS
	local metal = surface == "Metal"
	r = { a = a }
	r.e = makeEmitter(a, {
		Texture = T.Spark,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rotation = NumberRange.new(VFXKit.StreakRotation),
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(fx.Spark),
		Size = NS(0, if metal then 0.3 else 0.22, 1, 0),
		Lifetime = NumberRange.new(0.08, if metal then 0.32 else 0.2),
		Speed = NumberRange.new(8, if metal then 26 else 16),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = V(0, -40, 0),
		Drag = 2,
		EmissionDirection = Enum.NormalId.Front,
	})
	if surface ~= "Body" then
		r.g = makeEmitter(a, {
			Texture = T.Glow,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(fx.Spark),
			Size = NS(0, if metal then 0.7 else 0.45, 1, 0.1),
			Transparency = NS(0, 0.1, 1, 1),
			Lifetime = NumberRange.new(0.06, 0.08),
			Speed = NumberRange.new(0, 0),
			ZOffset = 0.3,
		})
	end
	r.dust = makeEmitter(a, {
		Texture = T.Dust,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		LightInfluence = 0.85,
		Color = ColorSequence.new(fx.Dust),
		Size = NS(0, 0.25, 1, if surface == "Concrete" then 1.3 else 0.8),
		Transparency = NS(0, if surface == "Body" then 0.5 else 0.1, 0.4, if surface == "Body" then 0.7 else 0.35, 1, 1),
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(1.5, 4),
		SpreadAngle = Vector2.new(30, 30),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Acceleration = V(0, -2, 0),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 4,
	})
	impactRigs[surface] = r
	return r
end
local markT = setmetatable({}, { __mode = "k" })
local markFree = {}
local MARK_FAR = CFrame.new(0, -5000, 0)

function WeaponEffects:_ImpactDefault(pos: Vector3, normal: Vector3, kind: string, material, weaponId: string?, skinDef, fin)
	local surface = surfaceOf(kind, material)
	local fx = SURFACE_FX[surface]
	local a = pointAttachment(pos + normal * 0.05)
	a.CFrame = CFrame.lookAt(a.Position, a.Position + normal)
	if (self.Flags.Impacts or surface == "Body") and not skinDef then
		local r = impactRig(surface, fx)
		r.a.CFrame = a.CFrame
		r.e:Emit(fx.Sparks)
		if r.g then r.g:Emit(1) end
		r.dust:Emit(fx.DustCount)
	end
	if surface ~= "Body" and markSurfaceOk(pos, normal) then
		-- bullet mark (capped, pooled; hidden after 12 s)
		local now = os.clock()
		while #self.Marks > 0 and now - (markT[self.Marks[1]] or 0) > 12 do
			local old = table.remove(self.Marks, 1)
			if old.Parent then
				old.CFrame = MARK_FAR
				table.insert(markFree, old)
			end
		end
		local mark = table.remove(markFree)
		if not mark and #self.Marks >= MAX_MARKS then
			mark = table.remove(self.Marks, 1)
		end
		if not mark or not mark.Parent then
			mark = Instance.new("Part")
			mark.Shape = Enum.PartType.Cylinder
			mark.Size = V(0.02, 0.2, 0.2)
			mark.Anchored = true
			mark.CanCollide = false
			mark.CanQuery = false
			mark.CanTouch = false
			mark.CastShadow = false
			mark.Material = Enum.Material.SmoothPlastic
			mark.Parent = fxFolder()
		end
		mark.Color = fx.Mark
		mark.Transparency = if surface == "Glass" then 0.4 else 0
		mark.CFrame = CFrame.lookAt(pos + normal * 0.012, pos + normal * 2) * CFrame.Angles(0, math.rad(90), 0)
		markT[mark] = now
		table.insert(self.Marks, mark)
	end
	if fin and fin.Accent and surface ~= "Body" and self.Flags.Impacts then -- finish impact accent
		local r = accentRig(fin.Accent)
		r.a.CFrame = a.CFrame
		for i, sp in fin.Accent do
			r.E[i]:Emit(sp.Count or 1)
		end
	end
	-- surface sound
	local impact = soundFor(weaponId, "Impact")
	local scfg = impact[surface]
	if scfg then
		local id = pick(self, scfg)
		local s = self:_newSound(scfg, id, a, self.EffectsGroup)
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 6
		s.RollOffMaxDistance = impact.RollOff or 110
		s:Play()
	end
	local ric = impact.Ricochet
	if ric and surface ~= "Body" and self.Rng:NextNumber() < (ric.Chance or 0) then
		local s = self:_newSound(ric, pick(self, ric), a, self.EffectsGroup)
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMaxDistance = impact.RollOff or 110
		s:Play()
	end
	Debris:AddItem(a, 2.5)
end

-- the local player's knife skin (the knife model under the camera carries the SkinFX attribute)
local knifeAt, knifeCache = -1, nil
function WeaponEffects:_knifeDef()
	if os.clock() - knifeAt < 0.5 then return knifeCache end
	knifeAt, knifeCache = os.clock(), nil
	local cam = Workspace.CurrentCamera
	if cam then
		for _, d in cam:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("SkinFX") and (d:GetAttribute("WeaponId") == "Knife" or string.find(d.Name, "Knife")) then
				knifeCache = SkinFX.Get(d:GetAttribute("SkinFX"))
				break
			end
		end
	end
	return knifeCache
end

-- knife contact: sparks on world, a short puff on bodies + the matching sound
function WeaponEffects:MeleeImpact(pos: Vector3, normal: Vector3, isBody: boolean)
	local a = pointAttachment(pos + normal * 0.05)
	a.CFrame = CFrame.lookAt(a.Position, a.Position + normal)
	local fx = if isBody then SURFACE_FX.Body else SURFACE_FX.Metal
	local kdef = self:_knifeDef()
	local KL = skinLaser(kdef)
	if kdef and kdef.Impact then
		SkinFX.Impact(pos, normal, kdef)
	end
	local e = makeEmitter(a, {
		Texture = VFXKit.Tex.Spark, Orientation = Enum.ParticleOrientation.VelocityParallel, Rotation = NumberRange.new(VFXKit.StreakRotation),
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new((KL and KL.Color) or fx.Spark),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.08, 0.2),
		Speed = NumberRange.new(5, 12),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = V(0, -30, 0),
		EmissionDirection = Enum.NormalId.Front,
	})
	e:Emit(if isBody then 6 else 9)
	self:PlayCue("Knife", if isBody then "HitBody" else "HitWorld", a)
	Debris:AddItem(a, 2)
end

function WeaponEffects:Shell(cf: CFrame)
	if not self.Flags.Shells then
		return
	end
	local p = Instance.new("Part")
	p.Size = V(0.05, 0.05, 0.14)
	p.Material = Enum.Material.Metal
	p.Color = C(205, 160, 70)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = cf
	p.Parent = fxFolder()
	p.AssemblyLinearVelocity = cf.RightVector * self.Rng:NextNumber(8, 12) + cf.UpVector * self.Rng:NextNumber(5, 8) + cf.LookVector * -1.5
	p.AssemblyAngularVelocity = V(self.Rng:NextNumber(-20, 20), self.Rng:NextNumber(-20, 20), 0)
	table.insert(self.Shells, p)
	if #self.Shells > MAX_SHELLS then
		local oldest = table.remove(self.Shells, 1)
		if oldest.Parent then
			oldest:Destroy()
		end
	end
	Debris:AddItem(p, 0.7)
end

function WeaponEffects:Destroy() end

return WeaponEffects
