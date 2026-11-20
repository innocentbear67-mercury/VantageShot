--!nonstrict
--[[
	VANTAGE — SignatureVFX (shared, client visuals only) — 2026-11-19
	The toolkit every Signature FX module builds on. Nothing here deals damage or replicates:
	each client builds the effects locally from the server's timestamped messages.

	Pieces
		VFX.Bolt{...}        pooled lightning (midpoint displacement + branches, white core + glow shell).
		                     :Draw(a, b, alpha) regenerates the path (call every 2-3 frames to flicker),
		                     :Hide(), :Destroy()
		VFX.Flash            short PointLight flash
		VFX.Orb              Neon sphere that pops outward and fades
		VFX.Burst            one-shot particle burst (built-in Roblox textures, VFX.Tex)
		VFX.Shockwave        flat expanding ring sprite lying in a plane
		VFX.Trail            Trail between two attachments on a part
		VFX.Sound            positional one-shot sound
		VFX.Step(fn)         per-frame loop; fn(dt, elapsed) returns false to stop. Yields until done.
		VFX.Wait(t)          scaled wait
	VFX.TimeScale slows every effect down together (previews / screenshots). 1 in game.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VFX = {}
VFX.TimeScale = 1
VFX.Rng = Random.new()

local P = "rbxasset://textures/particles/"
-- KitsBlox free VFX textures (commercial use OK; see ServerStorage._KitsBloxVFX / project doc)
VFX.KB = {
	IceBurst = "rbxassetid://91232721419654",   -- Frost: 4x4 flipbook streak burst (VelocityParallel)
	BlueFire = "rbxassetid://110564757834474",  -- Frost: 4x4 flipbook spirit fire
	Air = "rbxassetid://118110017695954",       -- Frost: 4x4 flipbook air / mist wisps
	Star = "rbxassetid://112189862477193",      -- Frost: 4-point twinkle
	IceDebris = "rbxassetid://128630631346110", -- Frost: 4x4 flipbook ice chunks
	Snow = "rbxassetid://105632878942315",      -- Frost: snow flake
	Streak = "rbxassetid://87019992743834",     -- Frost: sharp streak
	Crack = "rbxassetid://113173568786954",     -- ShadowFloorExplode: ground crack decal (flat)
	CrackGlow = "rbxassetid://108544079490811", -- ShadowFloorExplode: ground burst decal (flat)
	Spikes = "rbxassetid://121215145577644",    -- ShadowFloorExplode: 2x2 flipbook upward spikes
	Crescent = "rbxassetid://18776539591",      -- CritSlash: 4x4 flipbook crescent slash
	SlashRing = "rbxassetid://18126715143",     -- CritSlash: 4x4 flipbook slash ring
	SlashFlash = "rbxassetid://129383903493952",-- Rift_Slash: big slash flash (FacingCameraWorldUp)
	Rift = "rbxassetid://137686776000721",      -- Rift_Slash: 4x4 flipbook rift swirl (flat)
	FloorWind = "rbxassetid://98541001614957",  -- Rift_Slash: flat wind burst
	Arc1 = "rbxassetid://86472590451811",       -- ElecFinalHit: 4x4 flipbook lightning arc
	Arc2 = "rbxassetid://133996520116611",      -- ElecFinalHit: 4x4 flipbook lightning arc
	ArcRing = "rbxassetid://131629476210411",   -- ElecFinalHit: 4x4 flipbook arc ring (flat)
	Bolt = "rbxassetid://72218922167176",       -- ElecFinalHit: lightning bolt sprite
	Impact = "rbxassetid://120084729167270",    -- ElecFinalHit: flat impact
	BigGlow = "rbxassetid://79623550313180",    -- ElecFinalHit: soft glow
	Crescents = "rbxassetid://122791656811096", -- ElecFinalHit: 4x4 flipbook crescents
	Ring = "rbxassetid://119603221376769",      -- Explosion: expanding ring
	SmokeBall = "rbxassetid://100387724784021", -- Explosion: smoke puff
	BlastDebris = "rbxassetid://119288437483941", -- Explosion: debris burst
	Sparks = "rbxassetid://130653388990969",    -- Explosion: spark
	Splash = "rbxassetid://71141867763767",     -- Explosion: splash streak
	Shock = "rbxassetid://93139677162221",      -- Explosion: flat shockwave
	WavesIn = "rbxassetid://82388399646103",    -- Charge: imploding waves (anticipation)
	WaterRing = "rbxassetid://110265326121717", -- Charge: ring
	FireFlip = "rbxassetid://14708864187",      -- Fire Path: 4x4 flipbook flame
	SmokeFlip = "rbxassetid://14709077788",     -- Fire Path: 4x4 flipbook smoke
	FireSoft = "rbxassetid://14709312927",      -- Fire Path: soft flame
	FloorSmoke = "rbxassetid://112475387538929",-- Floor Fire: smoke
	FireLines = "rbxassetid://115078726218564", -- Floor Fire: flame licks
	HandFire = "rbxassetid://99044193651360",   -- Charge: 2x2 flipbook fire
	FireBurst = "rbxassetid://84110881037737",  -- Charge: burst
	FireDots = "rbxassetid://77591378141559",   -- Charge: ember dots
	Flare = "rbxassetid://95914353191223",      -- Charge: flare
}

VFX.Tex = {
	Spark = P .. "sparkles_main.dds",
	Fire = P .. "fire_main.dds",
	FireSparks = P .. "fire_sparks_main.dds",
	Smoke = P .. "smoke_main.dds",
	Shock = P .. "explosion01_shockwave_main.dds",
	Core = P .. "explosion01_core_main.dds",
	Implode = P .. "explosion01_implosion_main.dds",
	Glow = P .. "forcefield_glow_main.dds",
	Vortex = P .. "forcefield_vortex_main.dds",
}

function VFX.Folder(): Instance
	local f = Workspace:FindFirstChild("SignatureFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SignatureFX"
		f.Parent = Workspace
	end
	return f
end

function VFX.Part(props): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = VFX.Folder()
	for k, v in props do
		if k == "Parent" then parent = v elseif k ~= "ClassName" then p[k] = v end
	end
	p.Parent = parent
	return p
end

function VFX.Tween(inst: Instance, dur: number, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(dur / VFX.TimeScale, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function VFX.Later(dur: number, fn)
	task.delay(dur / VFX.TimeScale, fn)
end

function VFX.Cleanup(inst: Instance, dur: number)
	VFX.Later(dur, function()
		if inst then inst:Destroy() end
	end)
end

function VFX.Wait(t: number)
	local left = t
	while left > 0 do
		left -= RunService.Heartbeat:Wait() * VFX.TimeScale
	end
end

-- per-frame loop, yields until fn returns false (or maxTime passes)
function VFX.Step(fn, maxTime: number?)
	local elapsed = 0
	while true do
		local dt = RunService.Heartbeat:Wait() * VFX.TimeScale
		elapsed += dt
		if fn(dt, elapsed) == false then break end
		if maxTime and elapsed >= maxTime then break end
	end
end

function VFX.RandomUnit(): Vector3
	local r = VFX.Rng
	local v = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(-1, 1), r:NextNumber(-1, 1))
	return if v.Magnitude < 1e-3 then Vector3.yAxis else v.Unit
end

------------------------------------------------------------------ lightning
local Bolt = {}
Bolt.__index = Bolt

local function jagged(a: Vector3, b: Vector3, depth: number, jag: number, rng: Random)
	local pts = { a, b }
	for _ = 1, depth do
		local out = { pts[1] }
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			local d = q - p
			local len = d.Magnitude
			local mid = (p + q) / 2
			if len > 0.02 then
				local perp = d.Unit:Cross(VFX.RandomUnit())
				if perp.Magnitude > 1e-3 then
					mid += perp.Unit * rng:NextNumber(-1, 1) * jag * len
				end
			end
			out[#out + 1] = mid
			out[#out + 1] = q
		end
		pts = out
	end
	return pts
end

function VFX.Bolt(o)
	o = o or {}
	local parent = o.Parent or VFX.Folder()
	local holder = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.1, CFrame = CFrame.identity, Parent = parent })
	holder.Name = "BoltHolder"
	return setmetatable({
		Color = o.Color or Color3.fromRGB(111, 232, 255),
		Core = o.Core or Color3.new(1, 1, 1),
		Width = o.Width or 0.12,
		Jag = o.Jag or 0.3,
		Depth = o.Depth or 4,
		Branches = o.Branches or 2,
		GlowScale = o.GlowScale or 5,
		BranchNear = o.BranchNear or { 0.1, 0.9 }, -- where along the main channel forks start (0 = start point)
		BranchLen = o.BranchLen or { 0.12, 0.3 }, -- fork length as a fraction of the whole bolt
		GlowAlpha = o.GlowAlpha or 0.28,
		Pool = {},
		Used = 0,
		Atts = {},
		AttUsed = 0,
		Beams = {},
		BeamUsed = 0,
		Holder = holder,
		Parent = parent,
	}, Bolt)
end

function Bolt:_get(): BasePart
	self.Used += 1
	local p = self.Pool[self.Used]
	if not p then
		p = VFX.Part({ Size = Vector3.one * 0.1, Transparency = 1, Parent = self.Parent })
		self.Pool[self.Used] = p
	end
	return p
end

function Bolt:_att(pos: Vector3): Attachment
	self.AttUsed += 1
	local a = self.Atts[self.AttUsed]
	if not a then
		a = Instance.new("Attachment")
		a.Parent = self.Holder
		self.Atts[self.AttUsed] = a
	end
	a.Position = pos
	return a
end

function Bolt:_beam(a0: Attachment, a1: Attachment, w0: number, w1: number, color: Color3, transparency: number)
	self.BeamUsed += 1
	local b = self.Beams[self.BeamUsed]
	if not b then
		b = Instance.new("Beam")
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Parent = self.Holder
		self.Beams[self.BeamUsed] = b
	end
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = w0
	b.Width1 = w1
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(transparency)
	b.Enabled = true
end

-- white Neon core (parts) + two soft additive glow ribbons (beams sharing attachments, so no seams)
function Bolt:_line(pts, w: number, alpha: number, parts, cfs)
	local n = #pts
	local atts = table.create(n)
	local widths = table.create(n)
	for i = 1, n do
		atts[i] = self:_att(pts[i])
		widths[i] = w * (1 - 0.5 * ((i - 1) / math.max(1, n - 1)))
	end
	for i = 1, n - 1 do
		local p, q = pts[i], pts[i + 1]
		local len = (q - p).Magnitude
		if len > 1e-3 then
			self:_beam(atts[i], atts[i + 1], widths[i], widths[i + 1], self.Core, 1 - alpha) -- hot white core
		end
		local g0, g1 = widths[i] * self.GlowScale, widths[i + 1] * self.GlowScale
		self:_beam(atts[i], atts[i + 1], g0, g1, self.Color, 1 - alpha * self.GlowAlpha)
		self:_beam(atts[i], atts[i + 1], g0 * 0.45, g1 * 0.45, self.Color, 1 - alpha * 0.6)
	end
end

function Bolt:Draw(a: Vector3, b: Vector3, alpha: number?)
	alpha = alpha or 1
	self.Used = 0
	self.AttUsed = 0
	self.BeamUsed = 0
	local parts, cfs = {}, {}
	local rng = VFX.Rng
	local main = jagged(a, b, self.Depth, self.Jag, rng)
	self:_line(main, self.Width, alpha, parts, cfs)
	local len = (b - a).Magnitude
	for _ = 1, self.Branches do
		local lo = math.clamp(math.floor(#main * self.BranchNear[1]) + 1, 2, #main - 1)
		local hi = math.clamp(math.floor(#main * self.BranchNear[2]), lo, math.max(lo, #main - 2))
		local i = rng:NextInteger(lo, hi)
		local from = main[i]
		local along = (main[math.min(i + 1, #main)] - from)
		local dir = if along.Magnitude > 1e-3 then along.Unit else (b - a).Unit
		local bend = dir:Cross(VFX.RandomUnit())
		if bend.Magnitude > 1e-3 then dir = (dir + bend.Unit * rng:NextNumber(0.5, 1.1)).Unit end
		local to = from + dir * len * rng:NextNumber(self.BranchLen[1], self.BranchLen[2])
		self:_line(jagged(from, to, math.max(1, self.Depth - 2), self.Jag, rng), self.Width * 0.5, alpha * 0.85, parts, cfs)
	end
	for i = self.Used + 1, #self.Pool do
		local p = self.Pool[i]
		if p.Transparency ~= 1 then p.Transparency = 1 end
	end
	for i = self.BeamUsed + 1, #self.Beams do
		self.Beams[i].Enabled = false
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Bolt:DrawPoints(pts, alpha: number?)
	alpha = alpha or 1
	self.Used = 0
	self.AttUsed = 0
	self.BeamUsed = 0
	local parts, cfs = {}, {}
	self:_line(pts, self.Width, alpha, parts, cfs)
	for i = self.Used + 1, #self.Pool do
		local p = self.Pool[i]
		if p.Transparency ~= 1 then p.Transparency = 1 end
	end
	for i = self.BeamUsed + 1, #self.Beams do
		self.Beams[i].Enabled = false
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- points along a jittered circular arc round a centre: curved crackle that wraps an object
function VFX.ArcPoints(center: Vector3, radius: number, spanDeg: number, jitter: number, count: number?)
	local rng = VFX.Rng
	local axis = VFX.RandomUnit()
	local ref = axis:Cross(if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local n = count or 9
	local start = rng:NextNumber(0, math.pi * 2)
	local span = math.rad(spanDeg)
	local pts = table.create(n)
	for i = 1, n do
		local a = start + span * (i - 1) / (n - 1)
		local v = CFrame.fromAxisAngle(axis, a):VectorToWorldSpace(ref)
		local r = radius * (1 + rng:NextNumber(-jitter, jitter))
		pts[i] = center + v * r + VFX.RandomUnit() * jitter * radius * 0.4
	end
	return pts
end

function Bolt:Hide()
	for _, p in self.Pool do p.Transparency = 1 end
	for _, b in self.Beams do b.Enabled = false end
end

function Bolt:Destroy()
	for _, p in self.Pool do p:Destroy() end
	table.clear(self.Pool)
	if self.Holder then self.Holder:Destroy() end
end

-- flicker a bolt between two (possibly moving) points for dur seconds, fading out over the last fadeFrac
function VFX.Strike(a, b, dur: number, o)
	local bolt = VFX.Bolt(o)
	local frame = 0
	task.spawn(function()
		VFX.Step(function(_, t)
			frame += 1
			local pa = if typeof(a) == "function" then a() else a
			local pb = if typeof(b) == "function" then b() else b
			local fade = math.clamp((dur - t) / (dur * 0.5), 0, 1)
			if frame % 2 == 1 then bolt:Draw(pa, pb, fade) end
			return t < dur
		end)
		bolt:Destroy()
	end)
	return bolt
end

------------------------------------------------------------------ light, orbs, particles
function VFX.Flash(pos: Vector3, color: Color3, brightness: number, range: number, dur: number)
	local p = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = p
	VFX.Tween(l, dur, { Brightness = 0 })
	VFX.Cleanup(p, dur + 0.05)
	return p
end

function VFX.Pop(pos: Vector3, o)
	-- one soft particle that grows and fades; o: Color, Texture, Size {a,b}, Life, T0, Flat (lie on the ground), Rot
	local holder = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.Texture or VFX.Tex.Glow
	e.Color = if typeof(o.Color) == "ColorSequence" then o.Color else ColorSequence.new(o.Color or Color3.new(1, 1, 1))
	e.LightEmission = o.Light or 1
	e.LightInfluence = 0
	e.Size = if typeof(o.Size) == "NumberSequence" then o.Size else NumberSequence.new(o.Size[1], o.Size[2])
	e.Transparency = if typeof(o.Transparency) == "NumberSequence" then o.Transparency else NumberSequence.new(o.T0 or 0, 1)
	e.Lifetime = NumberRange.new(o.Life or 0.3)
	e.Speed = NumberRange.new(o.Flat and 0.001 or 0)
	e.SpreadAngle = Vector2.zero
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, o.Rot or 360)
	e.RotSpeed = NumberRange.new(o.RotSpeed or 0)
	e.ZOffset = o.ZOffset or 0.5
	e.LockedToPart = true
	e.Rate = 0
	if o.Flat then e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end
	e.TimeScale = VFX.TimeScale
	e.Parent = holder
	e:Emit(o.Count or 1)
	VFX.Cleanup(holder, (o.Life or 0.3) / math.max(VFX.TimeScale, 0.05) + 0.1)
	return holder, e
end

function VFX.Orb(pos: Vector3, color: Color3, size0: number, size1: number, dur: number, transparency0: number?)
	local t0 = transparency0 or 0.15
	VFX.Pop(pos, { Color = color, Size = { size0 * 1.8, size1 * 1.9 }, Life = dur, T0 = t0 })
	VFX.Pop(pos, { Color = Color3.new(1, 1, 1), Size = { size0 * 0.9, size1 * 0.8 }, Life = dur * 0.7, T0 = t0, ZOffset = 1 })
	VFX.Pop(pos, { Color = color, Texture = VFX.Tex.Spark, Size = { size0 * 1.4, size1 * 1.6 }, Life = dur * 0.8, T0 = t0 })
end

-- flat glowing pool on the ground that spreads and fades (soft particles lying on the floor)
function VFX.GroundPool(pos: Vector3, color: Color3, radius: number, dur: number)
	local p = pos + Vector3.new(0, 0.12, 0)
	VFX.Pop(p, { Flat = true, Color = color, Size = { radius * 0.8, radius * 2.6 }, Life = dur, T0 = 0.25 })
	VFX.Pop(p, { Flat = true, Color = Color3.new(1, 1, 1), Size = { radius * 0.6, radius * 1.2 }, Life = dur * 0.6, T0 = 0.1 })
	VFX.Pop(p, { Flat = true, Color = color, Texture = VFX.Tex.Shock, Size = { radius * 0.4, radius * 2.4 }, Life = dur * 0.8, T0 = 0.2 })
end

-- brief local colour grade (only for a camera within range of pos)
function VFX._TintRaw(pos: Vector3, range: number, tint: Color3, brightness: number, dur: number)
	local cam = Workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - pos).Magnitude > range then return end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = tint
	cc.Brightness = brightness
	cc.Parent = cam
	VFX.Tween(cc, dur, { TintColor = Color3.new(1, 1, 1), Brightness = 0 })
	VFX.Cleanup(cc, dur + 0.05)
end

local function seq(a, b)
	return NumberSequence.new(a, b)
end

-- one-shot particle burst. o: Count, Color (Color3 or ColorSequence), Texture, Size {a,b}, Life {min,max},
-- Speed {min,max}, Spread, Drag, Accel, Light, Transparency {a,b}, Rotation, RotSpeed, CF (direction = LookVector)
function VFX.Burst(pos: Vector3, o)
	local cf = o.CF or CFrame.new(pos)
	local holder = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = cf })
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.Texture or VFX.Tex.Spark
	e.Color = if typeof(o.Color) == "ColorSequence" then o.Color else ColorSequence.new(o.Color or Color3.new(1, 1, 1))
	e.LightEmission = o.Light or 1
	e.LightInfluence = 0
	e.Size = if typeof(o.Size) == "NumberSequence" then o.Size else seq((o.Size or { 0.4, 0 })[1], (o.Size or { 0.4, 0 })[2])
	e.Transparency = if typeof(o.Transparency) == "NumberSequence" then o.Transparency else seq((o.Transparency or { 0, 1 })[1], (o.Transparency or { 0, 1 })[2])
	e.Lifetime = NumberRange.new((o.Life or { 0.2, 0.5 })[1], (o.Life or { 0.2, 0.5 })[2])
	e.Speed = NumberRange.new((o.Speed or { 6, 14 })[1], (o.Speed or { 6, 14 })[2])
	e.SpreadAngle = Vector2.new(o.Spread or 180, o.Spread or 180)
	e.EmissionDirection = Enum.NormalId.Front
	e.Drag = o.Drag or 3
	e.Acceleration = o.Accel or Vector3.zero
	e.Rotation = o.Rot or NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(o.RotSpeed or 0), o.RotSpeed or 0)
	e.Orientation = o.Orientation or Enum.ParticleOrientation.FacingCamera
	e.Squash = o.Squash or NumberSequence.new(0)
	e.ZOffset = o.ZOffset or 0
	e.Brightness = o.Brightness or 1
	if o.Flip then -- o.Flip = { Enum.ParticleFlipbookLayout, Enum.ParticleFlipbookMode?, fps? }
		e.FlipbookLayout = o.Flip[1]
		e.FlipbookMode = o.Flip[2] or Enum.ParticleFlipbookMode.OneShot
		if o.Flip[3] then e.FlipbookFramerate = NumberRange.new(o.Flip[3]) end
	end
	if o.LockedToPart then e.LockedToPart = true end
	e.Rate = 0
	e.TimeScale = VFX.TimeScale
	e.Parent = holder
	e:Emit(o.Count or 12)
	VFX.Cleanup(holder, (o.Life or { 0.2, 0.5 })[2] / math.max(VFX.TimeScale, 0.05) + 0.2)
	return e
end

-- flat ring sprite that grows from 0 to size in the plane whose normal is cf.LookVector
function VFX.Shockwave(cf: CFrame, color: Color3, size: number, dur: number, o)
	o = o or {}
	return VFX.Burst(cf.Position, {
		CF = cf,
		Count = 1,
		Texture = o.Texture or VFX.Tex.Shock,
		Color = color,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.08), NumberSequenceKeypoint.new(0.35, size * 0.75), NumberSequenceKeypoint.new(1, size) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Life = { dur, dur },
		Speed = { 0.001, 0.001 },
		Spread = 0,
		Drag = 0,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Light = 1,
	})
end

function VFX.Trail(part: BasePart, a: Vector3, b: Vector3, color, life: number, o)
	o = o or {}
	local a0 = Instance.new("Attachment"); a0.Position = a; a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = b; a1.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = if typeof(color) == "ColorSequence" then color else ColorSequence.new(color)
	t.Transparency = o.Transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	t.Lifetime = life / VFX.TimeScale
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = o.FaceCamera ~= false
	t.WidthScale = o.WidthScale or NumberSequence.new(1, 0.1)
	t.MinLength = 0.05
	t.Parent = part
	return t, a0, a1
end

function VFX.Sound(id: string?, pos: Vector3, volume: number?, speed: number?)
	if not id or id == "" then return end
	local p = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = (speed or 1) * math.min(1, VFX.TimeScale * 4)
	s.RollOffMinDistance = 18
	s.RollOffMaxDistance = 300
	s.Parent = p
	s:Play()
	VFX.Cleanup(p, 12)
	return s
end

-- Signature sound library (all checked to load in this experience, 2026-11-19). Entry = { id, volume, speed }
VFX.SFX = {
	Thunder = { "rbxassetid://9126099928", 1.2, 1 }, ThunderCrack = { "rbxassetid://118195482769396", 1, 1 },
	Zap = { "rbxassetid://9114246605", 0.8, 1 }, ElecHum = { "rbxassetid://93664018931780", 0.7, 1 },
	WolfHowl = { "rbxassetid://9120790529", 1.2, 0.9 }, WolfBay = { "rbxassetid://9120789309", 0.9, 0.85 }, Growl = { "rbxassetid://9113971531", 1.2, 0.8 },
	IceShatter = { "rbxassetid://9114855870", 1.1, 0.9 }, IceShatter2 = { "rbxassetid://80067573243829", 1, 1 },
	Gallop = { "rbxassetid://118636555040923", 1, 1.15 }, Hooves = { "rbxassetid://74590166641102", 0.9, 1 }, Neigh = { "rbxassetid://101153462816009", 1.1, 0.95 },
	Whoosh = { "rbxassetid://9126229255", 1, 1 }, WhooshLong = { "rbxassetid://9126228631", 0.9, 1 }, WhooshShort = { "rbxassetid://9126229267", 1, 1.1 },
	Boom = { "rbxassetid://9117876706", 1.3, 1 }, WarpBoom = { "rbxassetid://9126102254", 1.1, 1 },
	FireLoop = { "rbxassetid://111280053910468", 0.9, 1 }, Burning = { "rbxassetid://116275103627699", 0.8, 1 },
	Rumble = { "rbxassetid://132594602076716", 1.1, 1 },
	Splash = { "rbxassetid://83673781452193", 1.2, 0.8 }, Dive = { "rbxassetid://132575463084009", 1.1, 0.85 },
	Roar = { "rbxassetid://133651202885353", 1.2, 0.8 }, Roar2 = { "rbxassetid://110716346002611", 1, 0.9 },
	Wings = { "rbxassetid://9125386815", 1, 0.7 }, WingsLoop = { "rbxassetid://18902441110", 0.8, 1 },
	Choir = { "rbxassetid://121538758381608", 0.9, 1 },
	Portal = { "rbxassetid://86284095824874", 1, 1 }, Portal2 = { "rbxassetid://137532880997663", 1, 0.9 },
	Charge = { "rbxassetid://113813942754476", 0.9, 1 }, Rise = { "rbxassetid://113662490644023", 0.9, 1 },
	MetalGrind = { "rbxassetid://9116824995", 0.9, 0.8 }, Ghost = { "rbxassetid://9113950206", 0.9, 0.6 },
	WoodSplinter = { "rbxassetid://9120963490", 1, 0.9 }, WoodCreak = { "rbxassetid://9120831000", 0.9, 0.8 },
	MetalHit = { "rbxassetid://9116709512", 1, 0.8 }, Clang = { "rbxassetid://9118270242", 0.9, 0.7 },
	Hit = { "rbxassetid://9125484367", 0.9, 1 }, Blast = { "rbxassetid://18245316227", 1, 1 },
}

-- play a library sound at pos. vol/speed multiply the entry's values
function VFX._SfxRaw(name: string, pos: Vector3, vol: number?, speed: number?)
	local e = VFX.SFX[name]
	if not e then return end
	return VFX.Sound(e[1], pos, e[2] * (vol or 1), e[3] * (speed or 1))
end

-- a looping library sound on a part (follows it). returns stop(fadeTime)
function VFX.SfxLoop(name: string, part: Instance, vol: number?, speed: number?)
	local e = VFX.SFX[name]
	if not e then return function() end end
	local s = Instance.new("Sound")
	s.SoundId = e[1]; s.Looped = true
	s.Volume = 0
	s.PlaybackSpeed = e[3] * (speed or 1) * math.min(1, VFX.TimeScale * 4)
	s.RollOffMinDistance = 12; s.RollOffMaxDistance = 160
	s.Parent = part
	s:Play()
	VFX.Tween(s, 0.2, { Volume = e[2] * (vol or 1) })
	return function(fade)
		if not s.Parent then return end
		VFX.Tween(s, fade or 0.4, { Volume = 0 })
		task.delay((fade or 0.4) + 0.05, function() s:Destroy() end)
	end
end

------------------------------------------------------------------ v4 helpers (particles/beams only)
local G4 = Enum.ParticleFlipbookLayout.Grid4x4
VFX.G4 = G4
VFX.G2 = Enum.ParticleFlipbookLayout.Grid2x2

function VFX.Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.Rate = 0
	e.TimeScale = VFX.TimeScale
	for k, v in props do e[k] = v end
	e.Parent = parent
	return e
end

local function seqOf(v, d) if v == nil then return d end if typeof(v) == "number" then return NumberSequence.new(v) end if typeof(v) == "table" then return NumberSequence.new(v[1], v[2]) end return v end

-- one sprite that sits still and grows/fades. o: Tex, Color, Size {a,b}|NS, T {a,b}|NS, Life, Bright, Light, Rot, Ori, Flip, Z, Dir (Vector3 for flat sprites)
-- a CFrame at pos whose LookVector is dir (safe when dir is straight up or down, where lookAt is degenerate)
function VFX.Facing(pos: Vector3, dir: Vector3): CFrame
	local d = dir.Unit
	if math.abs(d.Y) > 0.98 then
		return CFrame.new(pos) * CFrame.Angles(d.Y > 0 and math.pi / 2 or -math.pi / 2, 0, 0)
	end
	return CFrame.lookAt(pos, pos + d)
end

function VFX.Sprite(pos: Vector3, o)
	local dir = o.Dir
	return VFX.Burst(pos, {
		CF = dir and VFX.Facing(pos, dir) or nil, Count = o.Count or 1, Texture = o.Tex, Color = o.Color,
		Size = seqOf(o.Size, NumberSequence.new(4)), Transparency = seqOf(o.T, NumberSequence.new(0, 1)),
		Life = { o.Life or 0.3, o.Life or 0.3 }, Speed = { dir and 0.001 or 0, dir and 0.001 or 0 }, Spread = 0, Drag = 0,
		Light = o.Light or 1, Brightness = o.Bright or 1.5, Rot = o.Rot,
		Orientation = o.Ori or (dir and Enum.ParticleOrientation.VelocityPerpendicular or nil), Flip = o.Flip, ZOffset = o.Z or 0.5,
		Squash = o.Squash,
	})
end

-- flat decal on the ground
function VFX.Decal(pos: Vector3, tex, color, s0, s1, life, o)
	o = o or {}
	return VFX.Sprite(pos + Vector3.new(0, 0.15, 0), { Tex = tex, Color = color, Size = { s0, s1 }, Life = life, Dir = Vector3.yAxis,
		T = o.T or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Bright = o.Bright or 1.5, Light = o.Light, Flip = o.Flip, Rot = o.Rot, Z = o.Z or 0.2, Count = o.Count })
end

-- a column of soft light (stacked glows stretched up)
function VFX.GlowColumn(pos: Vector3, color, height, width, life, bright)
	for h = 0, height, width * 0.7 do
		VFX.Sprite(pos + Vector3.new(0, h + width * 0.4, 0), { Tex = VFX.Tex.Glow, Color = color, Size = { width * (1 - h / height * 0.5), width * 0.25 },
			T = NumberSequence.new(0.4 + h / height * 0.4, 1), Life = life, Bright = bright or 1.2,
			Ori = Enum.ParticleOrientation.FacingCameraWorldUp, Squash = NumberSequence.new(-2.2) })
	end
end

-- smooth ring of points round a centre in the plane of cf (XZ of cf)
local function ringPts(cf, r, n, a0, frac, lift)
	local pts = {}
	local m = math.max(2, math.floor(n * (frac or 1)))
	for i = 0, m do
		local a = a0 + (i / n) * math.pi * 2
		pts[#pts + 1] = cf:PointToWorldSpace(Vector3.new(math.cos(a) * r, lift or 0.08, math.sin(a) * r))
	end
	return pts
end
VFX.RingPts = ringPts

local GLYPHS = {
	{ { { 0, -0.5 }, { 0, 0.5 } }, { { 0, 0.2 }, { 0.35, 0.5 } }, { { 0, -0.05 }, { 0.35, 0.25 } } },
	{ { { -0.3, -0.5 }, { 0, 0.5 } }, { { 0, 0.5 }, { 0.3, -0.5 } } },
	{ { { 0, -0.5 }, { 0, 0.5 } }, { { -0.3, 0.5 }, { 0.3, -0.5 } } },
	{ { { -0.25, -0.5 }, { -0.25, 0.5 } }, { { -0.25, 0.5 }, { 0.25, 0 } }, { { 0.25, 0 }, { -0.25, -0.5 } } },
	{ { { -0.3, -0.5 }, { -0.3, 0.5 } }, { { 0.3, -0.5 }, { 0.3, 0.5 } }, { { -0.3, 0.5 }, { 0.3, -0.5 } } },
}
VFX.Glyphs = GLYPHS

-- rune circle on a plane (cf: Y = plane normal). colors: { Main, Deep, Mist }. Returns a stop() function; auto-stops after life.
function VFX.RuneCircle(cf: CFrame, R: number, life: number, colors, o)
	o = o or {}
	local Main, Deep, Mist = colors.Main, colors.Deep or colors.Main, colors.Mist or Color3.new(1, 1, 1)
	local outer = VFX.Bolt({ Width = 0.14 * R / 7, Color = Main, GlowScale = 6, Branches = 0 })
	local outer2 = VFX.Bolt({ Width = 0.06 * R / 7, Color = Deep, GlowScale = 5, Branches = 0 })
	local inner = VFX.Bolt({ Width = 0.09 * R / 7, Color = Main, GlowScale = 5, Branches = 0 })
	local NG = o.Glyphs or 14
	local glyphs = {}
	for g = 1, NG do glyphs[g] = VFX.Bolt({ Width = 0.06 * R / 7, Color = Main, GlowScale = 5, Branches = 0 }) end
	local star = VFX.Bolt({ Width = 0.08 * R / 7, Color = Main, GlowScale = 5, Branches = 0 })
	local pool = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = cf * CFrame.new(0, 0.12, 0) })
	local light = Instance.new("PointLight"); light.Color = Main; light.Brightness = 0; light.Range = R * 3.5; light.Shadows = false; light.Parent = pool
	local up = cf.UpVector
	local flat = { Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(0.001),
		SpreadAngle = Vector2.zero, LockedToPart = true, Rotation = NumberRange.new(0, 360), LightEmission = 1 }
	local function flatE(p) local t = table.clone(flat); for k2, v in p do t[k2] = v end; return VFX.Emitter(pool, t) end
	pool.CFrame = VFX.Facing(cf.Position + up * 0.12, up) * CFrame.Angles(-math.pi / 2, 0, 0)
	local ems = {
		flatE({ Texture = VFX.Tex.Glow, Color = ColorSequence.new(Main), Size = NumberSequence.new(R * 2.9),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.5), Rate = 12 }),
		flatE({ Texture = VFX.Tex.Shock, Color = ColorSequence.new(Color3.new(1, 1, 1), Main), Size = NumberSequence.new(R * 0.3, R * 2.5),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.4, 0.4), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.55), Rate = 4 }),
		flatE({ Texture = VFX.KB.Rift, Color = ColorSequence.new(Main), Brightness = 2.5, Size = NumberSequence.new(R * 1.5, R * 1.8),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.3), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.6),
			Rate = 5, RotSpeed = NumberRange.new(90, 140), FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop }),
		flatE({ Texture = VFX.Tex.Smoke, Color = ColorSequence.new(Mist), LightEmission = 0.4, Size = NumberSequence.new(R * 2.2, R * 2.6),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.65), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.9), Rate = 4, RotSpeed = NumberRange.new(-20, 20) }),
	}
	local holder = VFX.Part({ Transparency = 1, Size = Vector3.new(R * 2, 0.2, R * 2), CFrame = pool.CFrame })
	ems[#ems + 1] = VFX.Emitter(holder, { Texture = VFX.KB.Star, Color = ColorSequence.new(Color3.new(1, 1, 1), Main), LightEmission = 1, Brightness = 3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 1.2 * R / 7), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 6), Rate = 22, Rotation = NumberRange.new(0, 45),
		Shape = Enum.ParticleEmitterShape.Disc, EmissionDirection = Enum.NormalId.Top })
	local stopped = false
	local function stop() stopped = true end
	task.spawn(function()
		local t0
		VFX.Step(function(_, t)
			if stopped and not t0 then t0 = t end
			local reveal = math.clamp(t / 0.35, 0, 1)
			local fade = t0 and math.clamp(1 - (t - t0) / 0.35, 0, 1) or math.clamp((life - t) / 0.45, 0, 1)
			local a = fade * (0.75 + 0.25 * math.sin(t * 22))
			outer:DrawPoints(ringPts(cf, R, 64, t * 0.9, reveal), a)
			outer2:DrawPoints(ringPts(cf, R * 1.07, 64, -t * 0.6, reveal), a * 0.8)
			inner:DrawPoints(ringPts(cf, R * 0.72, 48, -t * 1.3, reveal), a)
			for g, b in glyphs do
				local ang = -t * 1.3 + (g / NG) * math.pi * 2
				local centre = cf:PointToWorldSpace(Vector3.new(math.cos(ang) * R * 0.86, 0.08, math.sin(ang) * R * 0.86))
				local out = cf:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
				local across = up:Cross(out)
				local gl = GLYPHS[(g % #GLYPHS) + 1]
				local pts = {}
				local sc = 0.9 * R / 7
				for _, st in gl do
					pts[#pts + 1] = centre + across * st[1][1] * sc + out * st[1][2] * sc
					pts[#pts + 1] = centre + across * st[2][1] * sc + out * st[2][2] * sc
				end
				b:DrawPoints(pts, reveal >= g / NG and a or 0)
			end
			-- inner star (o.Points sides, default 6), turning
			local np = o.Points or 6
			local sp = {}
			for v = 0, np do
				local ang = t * 0.7 + v * (math.pi * 2 / np) * 2
				sp[#sp + 1] = cf:PointToWorldSpace(Vector3.new(math.cos(ang) * R * 0.55 * reveal, 0.09, math.sin(ang) * R * 0.55 * reveal))
			end
			star:DrawPoints(sp, a)
			light.Brightness = 4 * a
			return (t0 and (t - t0) < 0.35) or (not t0 and t < life)
		end)
		for _, e in ems do e.Enabled = false end
		outer:Destroy(); outer2:Destroy(); inner:Destroy(); star:Destroy()
		for _, b in glyphs do b:Destroy() end
		VFX.Cleanup(pool, 1.2); VFX.Cleanup(holder, 1.2)
	end)
	return stop
end

-- simple camera shake for the local camera (decays). 2026-11-20: one shared, self-undoing shake
-- (applied after the camera, removed before it next frame), so shakes never drift the aim.
local shakeList = {}
local shakeApplied = CFrame.identity
local shakeBound = false
function VFX._ShakeRaw(pos: Vector3, range: number, amp: number, dur: number)
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - pos).Magnitude > range then return end
	table.insert(shakeList, { T0 = os.clock(), Amp = amp, Dur = dur })
	if shakeBound then return end
	shakeBound = true
	local RS = game:GetService("RunService")
	RS:BindToRenderStep("VantageSigShakeUndo", Enum.RenderPriority.Camera.Value - 4, function()
		if shakeApplied ~= CFrame.identity then
			local c = workspace.CurrentCamera
			if c then c.CFrame = c.CFrame * shakeApplied:Inverse() end
			shakeApplied = CFrame.identity
		end
	end)
	RS:BindToRenderStep("VantageSigShake", Enum.RenderPriority.Camera.Value + 4, function()
		local now, k = os.clock(), 0
		for i = #shakeList, 1, -1 do
			local s = shakeList[i]
			local f = 1 - (now - s.T0) / s.Dur
			if f <= 0 then table.remove(shakeList, i) else k = math.max(k, f * s.Amp) end
		end
		if k <= 0 then return end
		local c = workspace.CurrentCamera
		if not c then return end
		shakeApplied = CFrame.Angles(math.rad((math.random() - 0.5) * k), math.rad((math.random() - 0.5) * k), 0)
		c.CFrame = c.CFrame * shakeApplied
	end)
end

------------------------------------------------ lock marker (2026-11-20): a turning double ring + 4 inward ticks that can follow a target
function VFX.Marker(color: Color3, radius: number)
	local outer = VFX.Bolt({ Width = 0.16, Color = color, Core = Color3.new(1, 1, 1), GlowScale = 5, Branches = 0 })
	local inner = VFX.Bolt({ Width = 0.09, Color = color, GlowScale = 4, Branches = 0 })
	local ticks = {}
	for i = 1, 4 do ticks[i] = VFX.Bolt({ Width = 0.14, Color = color, Core = Color3.new(1, 1, 1), GlowScale = 4, Branches = 0 }) end
	local self = {}
	function self:Draw(pos: Vector3, t: number, alpha: number)
		local cf = CFrame.new(pos + Vector3.new(0, 0.2, 0))
		local tighten = 1 + 0.25 * math.max(0, 1 - t * 2) -- snaps in when it appears
		outer:DrawPoints(VFX.RingPts(cf, radius * tighten, 56, t * 0.9, 1, 0), alpha)
		inner:DrawPoints(VFX.RingPts(cf, radius * 0.58 * tighten, 40, -t * 1.6, 0.78, 0), alpha * 0.85)
		local pulse = 1 + math.sin(t * 9) * 0.07
		for i, b in ticks do
			local a = t * 0.9 + i * math.pi / 2
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			local c0 = pos + Vector3.new(0, 0.25, 0)
			b:DrawPoints({ c0 + d * radius * 1.32 * pulse * tighten, c0 + d * radius * 0.86 * pulse * tighten }, alpha)
		end
	end
	function self:Destroy()
		outer:Destroy(); inner:Destroy()
		for _, b in ticks do b:Destroy() end
	end
	return self
end

------------------------------------------------ noise budget (2026-11-20): Signatures were "noise pollution"
-- at most SfxBurst one-shot sounds per 0.3 s window, quieter overall, quieter / silent far away;
-- shake and screen tint only reach players close to the action.
VFX.SfxGain, VFX.SfxBurst, VFX.SfxRange, VFX.ShakeRange, VFX.TintRange = 0.6, 3, 170, 30, 34
local sfxWin, sfxCount = 0, 0
function VFX.Sfx(name: string, pos: Vector3, vol: number?, speed: number?)
	local cam = workspace.CurrentCamera
	local d = cam and (cam.CFrame.Position - pos).Magnitude or 0
	if d > VFX.SfxRange then return nil end
	local t = os.clock()
	if t - sfxWin > 0.3 then sfxWin, sfxCount = t, 0 end
	sfxCount += 1
	if sfxCount > VFX.SfxBurst then return nil end
	return VFX._SfxRaw(name, pos, (vol or 1) * VFX.SfxGain * (if d > 50 then 0.55 else 1), speed)
end
function VFX.Shake(pos: Vector3, range: number, amp: number, dur: number)
	return VFX._ShakeRaw(pos, math.min(range, VFX.ShakeRange), amp * 0.6, math.min(dur, 0.6))
end
function VFX.ScreenTint(pos: Vector3, range: number, tint: Color3, brightness: number, dur: number)
	return VFX._TintRaw(pos, math.min(range, VFX.TintRange), tint, brightness * 0.6, dur)
end

return VFX
