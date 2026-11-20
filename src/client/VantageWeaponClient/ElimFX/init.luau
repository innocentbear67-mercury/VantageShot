--[[
	VANTAGE — ElimFX (client)
	Plays the 19 elimination effects (ReplicatedStorage.Vantage.Elimination.EffectCatalog) on a body.
	Port of the approved browser prototype (v2). Everything is Roblox-native: the body is copied into
	anchored clones that move / scale / spin / flash Neon / fade per armour piece; ParticleEmitters
	(built-in textures), segmented Neon rings, ForceField shells, Neon lightning, Billboard glows,
	PointLights, a ColorCorrection punch and camera shake. Client-only, nothing collides or is
	raycastable, everything is removed when the effect ends.

	ElimFX.Play(rig, effectId, opts) -> Session
	  opts.Parent     where the FX live (default Workspace.VantageElimFX; a WorldModel for tiles)
	  opts.Start      clock time of t = 0 (default now). opts.Clock() replaces os.clock
	  opts.Manual     true: no RenderStepped; call session:Step(dt) / session:Seek(t) yourself
	  opts.Particles  false: no ParticleEmitters / Billboards / lights (ViewportFrames can't draw them)
	  opts.Screen     true: allow screen flash + camera shake (default true)
	  opts.Sound      true: play sounds (default true); opts.SoundAt = Vector3 for 3D sound
	  opts.HideRig    true (default): hide the source rig's parts (LocalTransparencyModifier) while it plays
	  opts.KeepRigHidden  true: leave the rig hidden afterwards (deaths)
	  opts.OnHidden / opts.OnDone  callbacks: the body is gone / the effect has fully cleared
Session.HideAt / Session.Duration (played seconds), :Step(dt), :Seek(t), :Destroy()
	ElimFX.CameraOffset() -> CFrame shake to apply on top of a scripted camera
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Elimination"):WaitForChild("EffectCatalog"))

local V3 = Vector3.new
local CF = CFrame.new
local K = 2.9 -- studs per prototype metre (the Legionary is ~1.95 m in the prototype, ~5.6 studs here)

local TEX = {
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Core = "rbxasset://textures/particles/explosion01_core_main.dds",
	Implode = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	FireSpark = "rbxasset://textures/particles/fire_sparks_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Square = "rbxasset://textures/ui/dialog_white.png",
	Circle = "rbxasset://textures/whiteCircle.png",
}

local ElimFX = {}
ElimFX.K = K
ElimFX.TEX = TEX

-- ─── math helpers (same names as the prototype) ─────────────────────────────────────────────
local function clamp01(x: number) return math.clamp(x, 0, 1) end
local function seg(t: number, a: number, b: number) return clamp01((t - a) / (b - a)) end
local function lerp(a, b, k) return a + (b - a) * k end
local function env(t, a, p, b)
	if t < a or t > b then return 0 end
	return if t < p then seg(t, a, p) else 1 - seg(t, p, b)
end
local ease = {
	inQuad = function(x) return x * x end,
	outQuad = function(x) return 1 - (1 - x) * (1 - x) end,
	inCubic = function(x) return x * x * x end,
	outCubic = function(x) return 1 - (1 - x) ^ 3 end,
	inQuart = function(x) return x ^ 4 end,
	outQuart = function(x) return 1 - (1 - x) ^ 4 end,
	outExpo = function(x) return if x >= 1 then 1 else 1 - 2 ^ (-10 * x) end,
	inOutSine = function(x) return -(math.cos(math.pi * x) - 1) / 2 end,
	outBack = function(x) local c1 = 1.9; local c3 = c1 + 1; return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2 end,
}
ElimFX.seg, ElimFX.env, ElimFX.ease, ElimFX.lerp, ElimFX.clamp01 = seg, env, ease, lerp, clamp01

local function hash(a: number, b: number, c: number): number
	local s = math.sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453
	return s - math.floor(s)
end

-- ─── shared screen state (one ColorCorrection, one shake) ──────────────────────────────────
local cc: ColorCorrectionEffect? = nil
local screen = { Trauma = 0, Seed = 0 }
local screenOwners = 0
local function ensureCC()
	if not cc or not cc.Parent then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "VantageElimCC"
		cc.Parent = Lighting
	end
end
function ElimFX.CameraOffset(): CFrame
	local tr = screen.Trauma
	if tr <= 0 then return CFrame.identity end
	local s, n = tr * tr * 0.55, screen.Seed
	return CF(math.sin(n * 1.7) * math.cos(n * 2.9) * s, math.sin(n * 2.3 + 1.2) * math.cos(n * 1.3) * s, 0)
		* CFrame.Angles(0, 0, math.sin(n * 3.1) * s * 0.03)
end

-- ─── Session ────────────────────────────────────────────────────────────────────────────────
local Session = {}
Session.__index = Session

local function folderFor(opts)
	if opts.Parent then return opts.Parent end
	local f = Workspace:FindFirstChild("VantageElimFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "VantageElimFX"
		f.Parent = Workspace
	end
	return f
end

local function newPart(props, parent, class: string?)
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Neon
	for k, v in props do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- body capture: every visible part becomes an anchored clone we can move freely
local KEEP = { SurfaceAppearance = true, SpecialMesh = true, Decal = true, Texture = true }
local function captureBody(self)
	local rig = self.Rig
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = rig:FindFirstChildOfClass("Humanoid")
	local rcf = if root then root.CFrame else rig:GetPivot()
	-- feet on the ground under the root, facing the rig's look direction
	local footY = rcf.Position.Y - (if hum then hum.HipHeight else 2) - (if root then root.Size.Y / 2 else 1)
	local look = rcf.LookVector
	local flat = V3(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then flat = V3(0, 0, -1) end
	local origin = CFrame.lookAt(V3(rcf.Position.X, footY, rcf.Position.Z), V3(rcf.Position.X, footY, rcf.Position.Z) + flat)
	self.O = origin
	local model = Instance.new("Model")
	model.Name = "Body"
	local parts = {}
	local rng = Random.new(self.Seed)
	local totalArea = 0
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.98 and d.Size.Magnitude > 0.05 then
			local c = d:Clone()
			for _, ch in c:GetChildren() do
				if not KEEP[ch.ClassName] then ch:Destroy() end
			end
			c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
			c.CastShadow = true
			c.LocalTransparencyModifier = 0
			c.Parent = model
			local localCF = origin:ToObjectSpace(d.CFrame)
			local cp = localCF.Position / K
			local rec = {
				P = c, Rot = d.CFrame - d.CFrame.Position, Size0 = d.Size,
				C = V3(cp.X, cp.Y, -cp.Z), -- prototype space: +z = toward the front
				Id = 0.04 + rng:NextNumber() * 0.92,
				Axis = V3(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
				SA = c:FindFirstChildOfClass("SurfaceAppearance"),
				Mat = c.Material, Col = c.Color, T0 = c.Transparency,
				Area = d.Size.X * d.Size.Y + d.Size.Y * d.Size.Z + d.Size.X * d.Size.Z,
				Src = d,
			}
			totalArea += rec.Area
			table.insert(parts, rec)
		end
	end
	model.Parent = self.Folder
	self.Body = model
	self.Parts = parts
	self.TotalArea = math.max(totalArea, 1e-3)
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillTransparency, hl.OutlineTransparency = 1, 1
	hl.Adornee = model
	hl.Parent = model
	self.HL = hl
	if self.Opts.HideRig ~= false then
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				self.Hidden[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		end
	end
end

-- prototype space -> world
function Session:W(p: Vector3): Vector3
	return self.O:PointToWorldSpace(V3(p.X, p.Y, -p.Z) * K)
end
function Session:WDir(d: Vector3): Vector3
	return self.O:VectorToWorldSpace(V3(d.X, d.Y, -d.Z))
end

-- random points on the body surface (prototype space) with outward normals
function Session:Sample(n: number)
	local out = {}
	local rng = self.Rng
	if #self.Parts == 0 then return out end
	for _ = 1, n do
		local r = rng:NextNumber() * self.TotalArea
		local rec = self.Parts[1]
		for _, q in self.Parts do
			r -= q.Area
			if r <= 0 then rec = q break end
		end
		local s = rec.Size0 / 2
		local axis = rng:NextInteger(1, 3)
		local sign = if rng:NextNumber() < 0.5 then -1 else 1
		local lp = V3(rng:NextNumber(-1, 1) * s.X, rng:NextNumber(-1, 1) * s.Y, rng:NextNumber(-1, 1) * s.Z)
		if axis == 1 then lp = V3(sign * s.X, lp.Y, lp.Z) elseif axis == 2 then lp = V3(lp.X, sign * s.Y, lp.Z) else lp = V3(lp.X, lp.Y, sign * s.Z) end
		local wp = (CF(self:W(rec.C)) * rec.Rot):PointToWorldSpace(lp)
		local o = self.O:PointToObjectSpace(wp) / K
		local p = V3(o.X, o.Y, -o.Z)
		local nrm = (p - rec.C)
		nrm = if nrm.Magnitude > 1e-4 then nrm.Unit else V3(0, 1, 0)
		table.insert(out, { p = p, n = nrm, part = rec })
	end
	return out
end

-- ─── body state, applied per frame (Roblox-style: CFrame, Size, Material, Transparency) ─────
local function resetBodyState(B)
	B.Pinch, B.PinchC, B.PinchW, B.Bias, B.Swirl = 0, V3(0, 1.12, 0), V3(1, 1, 1), 0, 0
	B.Sag, B.Glitch, B.Jitter, B.Lift, B.Offset = 0, 0, 0, 0, V3()
	B.Diss, B.DissMode, B.DissC, B.Edge = 0, 0, V3(0, 1.12, 0), Color3.new(1, 1, 1)
	B.Cut = 0
	B.Skin, B.SkinColor, B.SkinT = "normal", Color3.new(1, 1, 1), 0
	B.Glow, B.GlowColor, B.Outline, B.OutlineColor = 0, Color3.new(1, 1, 1), 0, Color3.new(1, 1, 1)
	B.Flicker = 0 -- 0..1: a share of pieces flashes Neon in FlickerColor (cracks / arcs / heat)
	B.FlickerColor = Color3.new(1, 1, 1)
	B.Explode = nil -- { [rec] = {Dir, Dist, K, Axis, Ang} } (Deconstruct)
end
ElimFX.resetBodyState = resetBodyState

local SKINS = {
	neon = Enum.Material.Neon, glass = Enum.Material.Glass, ff = Enum.Material.ForceField,
	dark = Enum.Material.SmoothPlastic, plastic = Enum.Material.SmoothPlastic,
}

function Session:_setLook(rec, mat: Enum.Material?, color: Color3?, transp: number)
	local p = rec.P
	if mat then
		if rec.SA and rec.SA.Parent then rec.SA.Parent = nil end
		if p.Material ~= mat then p.Material = mat end
		if p.Color ~= color then p.Color = color :: Color3 end
	else
		if rec.SA and rec.SA.Parent == nil then rec.SA.Parent = p end
		if p.Material ~= rec.Mat then p.Material = rec.Mat end
		if p.Color ~= rec.Col then p.Color = rec.Col end
	end
	local t = math.max(rec.T0, transp)
	if p.Transparency ~= t then p.Transparency = t end
end

function Session:_applyBody()
	local B = self.B
	if self.BodyGone then return end
	local C, W = B.PinchC, B.PinchW
	local st = math.floor(self.T * 22)
	local st2 = math.floor(self.T * 28)
	local parts, cfs = {}, {}
	for _, rec in self.Parts do
		local p = rec.C + B.Offset
		local s, sy, spin = 1, 1, 0
		local rot = rec.Rot
		local look, lookColor, transp = nil, nil, B.SkinT
		if B.Skin ~= "normal" then look, lookColor = SKINS[B.Skin], B.SkinColor end
		if B.Explode and B.Explode[rec] then
			local e = B.Explode[rec]
			p += e.Dir * e.Dist * e.K
			rot = CFrame.fromAxisAngle(self:WDir(e.Axis).Unit, e.Ang * e.K) * rot
		end
		if B.Sag > 0 then
			local k = clamp01(p.Y / 1.95)
			local w = 1 + B.Sag * 0.7 * (1 - k)
			p = V3(p.X * w, p.Y * (1 - B.Sag * (0.4 + 0.6 * k)), p.Z * w)
			sy = 1 - B.Sag * 0.45
		end
		if B.Jitter > 0 and hash(rec.Id * 13, st, 5) > 0.45 then
			p += V3(hash(rec.Id * 91, st, 1) - 0.5, hash(rec.Id * 91, st, 2) - 0.5, hash(rec.Id * 91, st, 3) - 0.5) * B.Jitter * 1.6
		end
		if B.Glitch > 0 then
			local band = math.floor(rec.C.Y * 9)
			local h = hash(band, st2, 7)
			if h > 0.55 then p += V3((h - 0.5) * B.Glitch * 2.2, 0, (hash(band, st2, 9) - 0.5) * B.Glitch) end
		end
		if B.Pinch > 0 then
			local d = p - C
			local r = d.Magnitude
			local f = clamp01(B.Pinch * (1 + B.Bias * (r - 0.6)))
			if B.Swirl ~= 0 then
				local a = B.Swirl * f * (1.6 - math.min(r, 1.6))
				local c, sn = math.cos(a), math.sin(a)
				d = V3(d.X * c - d.Z * sn, d.Y, d.X * sn + d.Z * c)
			end
			p = V3(C.X + d.X * (1 - f * W.X), C.Y + d.Y * (1 - f * W.Y), C.Z + d.Z * (1 - f * W.Z))
			s *= 1 - 0.88 * f
			spin += f * 1.8
		end
		if B.Lift ~= 0 then p += V3(0, B.Lift * rec.C.Y, 0) end
		-- piece flicker (cracks / heat / arcs): a share of pieces, re-rolled 14x a second
		if B.Flicker > 0 and hash(rec.Id * 37, math.floor(self.T * 14), 11) < B.Flicker then
			look, lookColor = Enum.Material.Neon, B.FlickerColor
		end
		if B.Cut > 0 and rec.Id < B.Cut then s = 0 end
		-- dissolve: each piece flashes Neon in the edge colour, then shrinks and fades
		if B.Diss > 0 then
			local m = B.DissMode
			local metric
			if m == 0 or m == 4 then metric = rec.Id
			elseif m == 1 then metric = clamp01(rec.C.Y / 1.95) * 0.8 + rec.Id * 0.2
			elseif m == 2 then metric = (1 - clamp01(rec.C.Y / 1.95)) * 0.8 + rec.Id * 0.2
			elseif m == 3 then metric = clamp01((rec.C - B.DissC).Magnitude / 1.1) * 0.72 + rec.Id * 0.28
			else metric = clamp01(math.abs(rec.C.X - B.DissC.X) / 0.45) * 0.6 + rec.Id * 0.4 end
			metric *= 0.82
			local e = (B.Diss - metric) / 0.2
			if e > 0 then
				look, lookColor = Enum.Material.Neon, B.Edge
				s *= 1 - ease.inQuad(clamp01((e - 0.3) / 0.7))
				transp = math.max(transp, clamp01((e - 0.5) / 0.5))
				if not rec.DissStarted then
					rec.DissStarted = true
					if self.OnPieceDissolve then self.OnPieceDissolve(rec, p) end
				end
			end
		end
		self:_setLook(rec, look, lookColor, transp)
		if s < 0.02 then
			if rec.P.Transparency ~= 1 then rec.P.Transparency = 1 end
			s = 0.02
		end
		local size = rec.Size0 * s
		if sy ~= 1 then size = V3(size.X, size.Y * sy, size.Z) end
		if rec.P.Size ~= size then rec.P.Size = size end
		local cf = CF(self:W(p)) * rot
		if spin ~= 0 then cf = cf * CFrame.fromAxisAngle(rec.Axis, spin) end
		table.insert(parts, rec.P)
		table.insert(cfs, cf)
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- whole-body glow: a Highlight (fill = glow, outline = rim)
	local hl = self.HL
	if hl then
		hl.FillColor = B.GlowColor
		hl.FillTransparency = 1 - clamp01(B.Glow)
		hl.OutlineColor = B.OutlineColor
		hl.OutlineTransparency = 1 - clamp01(B.Outline)
	end
end

-- ─── primitives ─────────────────────────────────────────────────────────────────────────────
-- segmented Neon ring. o: Color, Segments, Thick (prototype metres), Pattern (uneven brightness)
function Session:Ring(o)
	o = o or {}
	local n = o.Segments or 32
	local segs = {}
	for i = 1, n do
		segs[i] = newPart({ Color = o.Color or Color3.new(1, 1, 1), Transparency = 1, Size = V3(0.1, 0.1, 0.1) }, self.Folder)
	end
	local ring = { Segs = segs, Thick = o.Thick or 0.02, Visible = true, Spin = 0 }
	local pat = {}
	for i = 1, n do pat[i] = if o.Pattern then 0.25 + 0.75 * hash(i, n, 3) else 1 end
	-- center (proto), radius (proto), axis: "h" flat, "cam" facing the camera, or a tilt (radians) about X
	function ring.Set(_, center: Vector3, radius: number, alpha: number, axis, color: Color3?)
		local vis = alpha > 0.01 and radius > 0.005 and ring.Visible
		local frame
		local wc = self:W(center)
		if axis == "cam" then
			local cam = Workspace.CurrentCamera
			frame = CFrame.lookAt(wc, cam.CFrame.Position) * CFrame.Angles(math.pi / 2, 0, 0)
		else
			local tilt = if type(axis) == "number" then axis else 0
			frame = CF(wc) * (self.O - self.O.Position) * CFrame.Angles(tilt, 0, 0)
		end
		local Rr = radius * K * self.FXS
		local th = math.max(0.03, ring.Thick * K * self.FXS)
		local segLen = 2 * math.pi * Rr / n * 1.08
		local parts, cfs = {}, {}
		for i, p in segs do
			if not vis then
				if p.Transparency ~= 1 then p.Transparency = 1 end
			else
				local a = (i - 0.5) / n * math.pi * 2 + ring.Spin
				local cf = frame * CF(math.cos(a) * Rr, 0, math.sin(a) * Rr) * CFrame.Angles(0, -a, 0)
				p.Size = V3(th, th * 0.6, segLen)
				p.Transparency = 1 - clamp01(alpha * pat[i])
				if color then p.Color = color end
				table.insert(parts, p)
				table.insert(cfs, cf)
			end
		end
		if #parts > 0 then Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
	end
	return ring
end

-- ball: ForceField shell (Material ForceField) or Neon / black core
function Session:Ball(o)
	o = o or {}
	local p = newPart({ Shape = Enum.PartType.Ball, Material = o.Material or Enum.Material.ForceField, Color = o.Color or Color3.new(1, 1, 1), Transparency = 1, Size = V3(0.1, 0.1, 0.1) }, self.Folder)
	local b = { P = p }
	function b.Set(_, center: Vector3, radius: number, alpha: number, color: Color3?)
		if alpha <= 0.01 or radius <= 0.002 then p.Transparency = 1 return end
		p.Size = Vector3.one * math.max(0.05, radius * 2 * K * self.FXS)
		p.CFrame = CF(self:W(center))
		p.Transparency = 1 - clamp01(alpha)
		if color then p.Color = color end
	end
	return b
end

-- vertical light column (Neon cylinder)
function Session:Pillar(o)
	o = o or {}
	local p = newPart({ Shape = Enum.PartType.Cylinder, Color = o.Color or Color3.new(1, 1, 1), Transparency = 1, Size = V3(1, 1, 1) }, self.Folder)
	local b = { P = p }
	function b.Set(_, base: Vector3, radius: number, height: number, alpha: number)
		if alpha <= 0.01 then p.Transparency = 1 return end
		local h, r2 = height * self.FXS, radius * 2 * K * self.FXS
		p.Size = V3(h * K, r2, r2)
		p.CFrame = CF(self:W(base + V3(0, h / 2, 0))) * CFrame.Angles(0, 0, math.pi / 2)
		p.Transparency = 1 - clamp01(alpha) * 0.85
	end
	return b
end

-- raw plate part (rift slices, glass panes)
function Session:Plate(o)
	o = o or {}
	return newPart({ Shape = o.Shape or Enum.PartType.Block, Material = o.Material or Enum.Material.Neon, Color = o.Color or Color3.new(1, 1, 1), Transparency = 1, Size = V3(0.05, 1, 1) }, self.Folder)
end

-- Billboard glow (soft additive light). Not drawn in ViewportFrames.
function Session:Glow(o)
	o = o or {}
	local g = {}
	if not self.Particles then
		function g.Set() end
		return g
	end
	local anchor = newPart({ Transparency = 1, Size = V3(0.05, 0.05, 0.05) }, self.Folder)
	local bb = Instance.new("BillboardGui")
	bb.LightInfluence = 0
	bb.Brightness = o.Brightness or 3
	bb.AlwaysOnTop = o.OnTop == true
	bb.Adornee = anchor
	bb.Size = UDim2.fromScale(1, 1)
	bb.Enabled = false
	bb.Parent = anchor
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = o.Image or TEX.Glow
	img.ImageColor3 = o.Color or Color3.new(1, 1, 1)
	img.Size = UDim2.fromScale(1, 1)
	img.Parent = bb
	local streak
	if o.Streak then
		streak = img:Clone()
		streak.Image = TEX.Core
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Position = UDim2.fromScale(0.5, 0.5)
		streak.Size = UDim2.fromScale(3.2, 0.08)
		streak.Parent = bb
		bb.ClipsDescendants = false
	end
	function g.Set(_, center: Vector3, size: number, alpha: number, color: Color3?, sx: number?)
		if alpha <= 0.01 or size <= 0.001 then bb.Enabled = false return end
		bb.Enabled = true
		anchor.CFrame = CF(self:W(center))
		local s = size * K * self.FXS
		bb.Size = UDim2.new((sx or 1) * s, 0, s, 0)
		img.ImageTransparency = 1 - clamp01(alpha)
		if color then img.ImageColor3 = color end
		if streak then
			streak.ImageTransparency = 1 - clamp01(alpha * (o.Streak or 1))
			if color then streak.ImageColor3 = color end
		end
	end
	return g
end

-- immediate-mode Neon lightning (pooled segments, redrawn every frame)
function Session:BeginBolts()
	self.BoltUsed = 0
end
function Session:Bolt(pts, width: number, color: Color3, frac: number?, alpha: number?)
	if (alpha or 1) <= 0.01 then return end
	local count = math.max(2, math.floor((#pts - 1) * (frac or 1)) + 1)
	local pool = self.BoltPool
	local parts, cfs = {}, {}
	for i = 1, count - 1 do
		self.BoltUsed += 1
		local p = pool[self.BoltUsed]
		if not p then
			p = newPart({ Size = V3(0.1, 0.1, 0.1), Transparency = 1 }, self.Folder)
			pool[self.BoltUsed] = p
		end
		local a, b = self:W(pts[i]), self:W(pts[i + 1])
		local len = (b - a).Magnitude
		local w = math.max(0.03, width * K * self.FXS ^ 0.7 * (1 - 0.5 * i / #pts))
		p.Size = V3(w, w, len + w * 0.5)
		p.Color = color
		p.Transparency = 1 - clamp01(alpha or 1)
		if len > 1e-4 then
			table.insert(parts, p)
			table.insert(cfs, CFrame.lookAt((a + b) / 2, b))
		end
	end
	if #parts > 0 then Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end
function Session:EndBolts()
	for i = self.BoltUsed + 1, #self.BoltPool do
		local p = self.BoltPool[i]
		if p.Transparency ~= 1 then p.Transparency = 1 end
	end
end

-- midpoint-displacement lightning with branches (prototype space). Returns { {pts, w, start} }
function Session:Lightning(a: Vector3, b: Vector3, o)
	o = o or {}
	local rng = self.Rng
	local depth, jag, branch, w = o.depth or 5, o.jag or 0.22, o.branch or 0.25, o.w or 1
	local level = o.level or 0
	local pts = { a, b }
	local len = (b - a).Magnitude
	local function rdir() return V3(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) end
	for d = 0, depth - 1 do
		local np = { pts[1] }
		local amp = jag * len / 2 ^ d
		for i = 1, #pts - 1 do
			local m = (pts[i] + pts[i + 1]) / 2 + rdir() * amp * rng:NextNumber()
			table.insert(np, m)
			table.insert(np, pts[i + 1])
		end
		pts = np
	end
	local out = { { pts = pts, w = w } }
	if branch > 0 and level < 2 and depth > 1 then
		for i = 3, #pts - 2 do
			if rng:NextNumber() < branch / #pts * 6 then
				local dir = (pts[math.min(#pts, i + 3)] - pts[i]) + rdir() * 0.9 * len * 0.2
				dir = if dir.Magnitude > 1e-3 then dir.Unit else V3(0, 1, 0)
				local L = len * rng:NextNumber(0.15, 0.4) * (1 - i / #pts)
				for _, sb in self:Lightning(pts[i], pts[i] + dir * L, { depth = depth - 1, jag = jag, branch = branch * 0.6, w = w * 0.55, level = level + 1 }) do
					sb.start = i / #pts
					table.insert(out, sb)
				end
			end
		end
	end
	return out
end
function Session:DrawBolts(list, width: number, color: Color3, frac: number?, alpha: number?)
	frac = frac or 1
	for _, b in list do
		local f = if b.start then math.max(0, (frac - b.start) / math.max(1e-3, 1 - b.start)) else frac
		if f > 0 then self:Bolt(b.pts, width * b.w, color, f, alpha) end
	end
end

-- shards: small rigid pieces with simple physics (anchored, integrated here)
local SHARD_MAT = { metal = Enum.Material.Metal, crystal = Enum.Material.Glass, neon = Enum.Material.Neon, cube = Enum.Material.SmoothPlastic, dark = Enum.Material.Slate }
function Session:Shard(o)
	local rng = self.Rng
	local kind = o.kind or "metal"
	local size = (o.size or 0.05) * K * self.FXS ^ 0.6
	local scale = o.scale or V3(rng:NextNumber(0.5, 1.4), rng:NextNumber(0.5, 1.6), rng:NextNumber(0.3, 1.0))
	local shape = if kind == "crystal" then V3(0.45, 1.25, 0.45) elseif kind == "metal" then V3(1.4, 0.35, 1) else V3(1, 1, 1)
	local sz = V3(shape.X * scale.X, shape.Y * scale.Y, shape.Z * scale.Z) * size
	local p = newPart({
		Material = SHARD_MAT[kind] or Enum.Material.Metal,
		Color = o.color or (if kind == "metal" then Color3.fromRGB(80, 86, 76) else Color3.fromRGB(190, 225, 255)),
		Size = sz, Transparency = 1,
	}, self.Folder, if kind == "crystal" then "WedgePart" else "Part")
	if o.e0 then p.Material = Enum.Material.Neon; p.Color = o.e0 end
	local s = {
		P = p, Pos = o.p, Vel = (o.v or V3()) * self.FXS, Rot = CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3)),
		W = o.w or V3(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * rng:NextNumber(4, 14),
		Age = -(o.delay or 0), Life = o.life or 1, G = (o.g or -9.8) * self.FXS, Drag = o.drag or 0.6, Bounce = o.bounce ~= false,
		Size = sz, ShrinkAt = o.shrinkAt or 0.6, E0 = o.e0, E1 = o.e1, Cool = o.cool,
		Attract = o.attract or 0, Swirl = o.swirl or 0, To = o.to or V3(0, 1.1, 0),
		Glass = kind == "crystal",
	}
	table.insert(self.ShardList, s)
	return s
end
function Session:_stepShards(dt: number)
	local parts, cfs = {}, {}
	local rot0 = self.O - self.O.Position
	for i = #self.ShardList, 1, -1 do
		local s = self.ShardList[i]
		s.Age += dt
		if s.Age < 0 then continue end
		if s.Age >= s.Life then
			s.P:Destroy()
			table.remove(self.ShardList, i)
			continue
		end
		if s.Attract ~= 0 or s.Swirl ~= 0 then
			local d = s.To - s.Pos
			local r = d.Magnitude + 1e-4
			if s.Attract ~= 0 then s.Vel += d * (s.Attract * dt / r * (1 + 0.4 / (r + 0.05))) end
			if s.Swirl ~= 0 then s.Vel += V3(-d.Z / r, 0, d.X / r) * s.Swirl * dt end
			if s.Attract > 0 and r < 0.06 then s.Age = s.Life end
		end
		s.Vel += V3(0, s.G * dt, 0)
		if s.Drag > 0 then s.Vel *= math.exp(-s.Drag * dt) end
		s.Pos += s.Vel * dt
		if s.Bounce and s.Pos.Y < 0.02 then
			s.Pos = V3(s.Pos.X, 0.02, s.Pos.Z)
			s.Vel = V3(s.Vel.X * 0.6, math.abs(s.Vel.Y) * 0.32, s.Vel.Z * 0.6)
			s.W *= 0.6
		end
		local wl = s.W.Magnitude
		if wl > 1e-4 then s.Rot = CFrame.fromAxisAngle(s.W.Unit, wl * dt) * s.Rot end
		local k = s.Age / s.Life
		local sc = if k < s.ShrinkAt then 1 else 1 - (k - s.ShrinkAt) / (1 - s.ShrinkAt)
		s.P.Size = s.Size * math.max(sc, 0.02)
		s.P.Transparency = if sc < 0.03 then 1 elseif s.Glass then 0.2 else 0
		if s.E0 then
			s.P.Color = s.E0:Lerp(s.E1 or s.E0, k)
			if s.Cool and k > 0.75 and s.P.Material == Enum.Material.Neon then
				s.P.Material = Enum.Material.Metal -- cooled: stops glowing
			end
		end
		table.insert(parts, s.P)
		table.insert(cfs, CF(self:W(s.Pos)) * rot0 * s.Rot)
	end
	if #parts > 0 then Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end

-- flat Neon disc on the ground (pools, scorch, shadows)
function Session:Disc(o)
	o = o or {}
	local p = newPart({ Shape = Enum.PartType.Cylinder, Material = o.Material or Enum.Material.Neon, Color = o.Color or Color3.new(1, 1, 1), Transparency = 1, Size = V3(0.05, 1, 1) }, self.Folder)
	local d = { P = p }
	function d.Set(_, center: Vector3, radius: number, alpha: number, color: Color3?)
		if alpha <= 0.01 or radius <= 0.001 then p.Transparency = 1 return end
		p.Size = V3(0.04, radius * 2 * K * self.FXS, radius * 2 * K * self.FXS)
		p.CFrame = CF(self:W(center)) * (self.O - self.O.Position) * CFrame.Angles(0, 0, math.pi / 2)
		p.Transparency = 1 - clamp01(alpha) * 0.9
		if color then p.Color = color end
	end
	return d
end

-- a tinted Neon echo of the body as it looks right now (Prism)
function Session:Ghost(color: Color3)
	local m = Instance.new("Model")
	m.Name = "Ghost"
	local list = {}
	for _, rec in self.Parts do
		local c = rec.P:Clone()
		for _, ch in c:GetChildren() do ch:Destroy() end
		c.Material, c.Color, c.Transparency = Enum.Material.Neon, color, 1
		c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
		c.Parent = m
		table.insert(list, { P = c, CF = rec.P.CFrame })
	end
	m.Parent = self.Folder
	local g = { Model = m }
	function g.Set(_, offset: Vector3, alpha: number)
		local w = self:WDir(offset) * K * self.FXS
		for _, q in list do
			q.P.CFrame = q.CF + w
			q.P.Transparency = 1 - clamp01(alpha)
		end
	end
	return g
end

-- body landmarks in prototype space: Top, Back, Chest, feet / hands / shoulders
function Session:Landmarks()
	local top, back = nil, nil
	local feet, hands, shoulders = {}, {}, {}
	for _, r in self.Parts do
		local c = r.C
		if not top or c.Y > top.Y then top = c end
		if not back or c.Z < back.Z then back = c end
		local side = if c.X < 0 then 1 else 2
		if c.Y < 0.35 and (not feet[side] or c.Y < feet[side].Y) then feet[side] = c end
		if c.Y > 0.6 and c.Y < 1.35 and (not hands[side] or math.abs(c.X) > math.abs(hands[side].X)) then hands[side] = c end
		if c.Y > 1.3 and (not shoulders[side] or math.abs(c.X) > math.abs(shoulders[side].X)) then shoulders[side] = c end
	end
	local L = { Top = (top or V3(0, 1.9, 0)) + V3(0, 0.1, 0), Back = back or V3(0, 1.3, -0.25), Chest = V3(0, 1.35, 0.16) }
	L.List = { L.Top, L.Back }
	for _, t in { feet, hands, shoulders } do
		for _, v in t do table.insert(L.List, v) end
	end
	return L
end

-- ─── particles (ParticleEmitter:Emit). Not drawn in ViewportFrames. ─────────────────────────
-- o: tex, color (Color3 or {c0, c1}), size {s0, s1} (proto m), life {a, b}, speed {a, b} (proto m/s),
--    spread (deg, default 180), dir (proto vector), g (proto m/s^2 vector), drag, stretch (streak),
--    bright, alpha, light (LightEmission), shape "inward" / "ring" (r = radius), box (proto size)
local function seqN(a, b) return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }) end
function Session:Burst(at: Vector3, n: number, o)
	if not self.Particles or n <= 0 then return end
	n = math.floor(n * (if o.noAmp then 1 else self.Tier.Amp ^ 0.8) * (self.Opts.ParticleScale or 1) * self.FXS ^ 0.6 + 0.5)
	local X = K * self.FXS -- prototype metres -> studs, at this play's effect scale
	if n <= 0 then return end
	local wat = self:W(at)
	local dir = if o.dir and o.dir.Magnitude > 1e-4 then self:WDir(o.dir).Unit else V3(0, 1, 0)
	local up = if math.abs(dir.Y) > 0.98 then V3(1, 0, 0) else V3(0, 1, 0)
	local c0, c1 = o.color, o.color
	if type(o.color) == "table" then c0, c1 = o.color[1], o.color[2] end
	c0 = c0 or Color3.new(1, 1, 1)
	c1 = c1 or c0
	-- one emitter per look (texture, colours, sizes, physics, shape); position / direction / speed /
	-- lifetime are set per emission, so repeated small bursts reuse it instead of spawning parts
	local key = table.concat({ o.tex or "g", c0:ToHex(), c1:ToHex(), tostring(o.size and o.size[1]), tostring(o.size and o.size[2]),
		tostring(o.alpha), tostring(o.light), tostring(o.bright), tostring(o.stretch), tostring(o.shape), tostring(o.r), tostring(o.box),
		tostring(o.drag), tostring(o.g and o.g.Y), tostring(o.inward) }, "|")
	local cached = self.EmitCache[key]
	local host, e
	if cached and not o.delay then
		host, e = cached.Host, cached.E
	else
		host = newPart({ Transparency = 1, Size = V3(0.2, 0.2, 0.2) }, self.Folder)
		e = Instance.new("ParticleEmitter")
		if not o.delay then self.EmitCache[key] = { Host = host, E = e } end
	end
	host.CFrame = CFrame.lookAt(wat, wat + dir, up) * CFrame.Angles(-math.pi / 2, 0, 0)
	e.Rate = 0
	e.Texture = o.tex or TEX.Glow
	e.Color = ColorSequence.new(c0, c1)
	local s0 = (if o.size then o.size[1] else 0.03) * X
	local s1 = (if o.size then (o.size[2] or o.size[1]) else 0.01) * X
	e.Size = seqN(s0, s1)
	local a0 = 1 - (o.alpha or 1)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, a0), NumberSequenceKeypoint.new(0.6, a0 + (1 - a0) * 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(if o.life then o.life[1] else 0.3, if o.life then (o.life[2] or o.life[1]) else 0.5)
	local amp = if o.speed and o.speed[2] > 0 and not o.noAmp then self.Tier.Amp ^ 0.35 else 1
	local sp0 = if o.speed then o.speed[1] else 1
	local sp1 = if o.speed then (o.speed[2] or o.speed[1]) else 3
	e.Speed = NumberRange.new(sp0 * X * amp, sp1 * X * amp)
	local sp = o.spread or 180
	e.SpreadAngle = Vector2.new(sp, sp)
	e.Acceleration = if o.g then V3(0, o.g.Y * X, 0) else Vector3.zero
	e.Drag = o.drag or 0
	e.LightEmission = o.light or 1
	e.Brightness = o.bright or 2
	e.ZOffset = 0.5
	e.LockedToPart = false
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	if o.stretch then
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Squash = seqN(-o.stretch, -o.stretch * 0.6)
		e.Rotation = NumberRange.new(0, 0)
		e.RotSpeed = NumberRange.new(0, 0)
	end
	if o.shape == "inward" then
		local r = (o.r or 1) * X
		host.Size = Vector3.one * r * 2
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.SpreadAngle = Vector2.new(4, 4)
	elseif o.shape == "ring" then
		local r = (o.r or 1) * X
		host.Size = V3(r * 2, 0.1, r * 2)
		host.CFrame = CF(wat) * (self.O - self.O.Position)
		e.Shape = Enum.ParticleEmitterShape.Disc
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = if o.inward then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
		e.SpreadAngle = Vector2.new(o.spread or 6, o.spread or 6)
	elseif o.box then
		host.Size = o.box * X
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	if e.Parent ~= host then e.Parent = host end
	if o.delay and o.delay > 0 then
		task.delay(o.delay, function() if e.Parent then e:Emit(n) end end)
	else
		e:Emit(n)
	end
	return e
end
-- particles off the body surface
function Session:BodyBurst(n: number, o)
	if not self.Particles or n <= 0 then return end
	n = math.floor(n * self.Tier.Amp ^ 0.8 + 0.5)
	for _, s in self:Sample(n) do
		local oo = table.clone(o)
		oo.noAmp = true
		oo.dir = if o.dirFn then o.dirFn(s) else s.n
		self:Burst(s.p, 1, oo)
	end
end

-- PointLight at a prototype position (slots 1..3)
function Session:Light(i: number, at: Vector3, color: Color3, brightness: number, range: number?)
	if not self.Particles then return end
	local L = self.Lights[i]
	if not L then
		local host = newPart({ Transparency = 1, Size = V3(0.1, 0.1, 0.1) }, self.Folder)
		local pl = Instance.new("PointLight")
		pl.Shadows = false
		pl.Parent = host
		L = { Host = host, PL = pl }
		self.Lights[i] = L
	end
	L.Host.CFrame = CF(self:W(at))
	L.PL.Color = color
	L.PL.Brightness = math.max(0, brightness) * self.Tier.Amp
	L.PL.Range = math.min(60, (range or 9) * K * self.FXS * math.sqrt(self.Tier.Amp))
	L.Set = true
end

-- screen punch (ColorCorrection) and shake; only for effects near the camera
function Session:Flash(color: Color3, amt: number)
	if not self.ScreenOK or amt <= 0 then return end
	self.Scr.Bright += amt * 0.5
	self.Scr.Tint = self.Scr.Tint:Lerp(color, clamp01(amt * 1.5))
end
function Session:Desat(v: number) if self.ScreenOK then self.Scr.Sat = math.min(self.Scr.Sat, -v) end end
function Session:Contrast(v: number) if self.ScreenOK then self.Scr.Contrast = math.max(self.Scr.Contrast, v) end end
function Session:Dim(v: number) if self.ScreenOK then self.Scr.Bright -= v * 0.25 end end
function Session:Shake(a: number)
	if not self.ScreenOK then return end
	screen.Trauma = math.min(1, screen.Trauma + a * self.Tier.Amp ^ 0.6 * self.ShakeScale)
end

function Session:Sound(id: string, at: number, o)
	if not self.SoundOK then return end
	o = o or {}
	local delay = self:_toReal(at) - self.T
	local function play()
		if self.Dead and not o.after then return end
		local s = Instance.new("Sound")
		s.SoundId = id
		-- 2026-11-17 mix: the kill cue + coin blip lead; the cosmetic's own sounds sit under them
		s.Volume = (o.vol or 0.5) * (self.Opts.Volume or 1) * 0.45
		s.SoundGroup = SoundService:FindFirstChild("VantageEffects") :: SoundGroup?
		s.PlaybackSpeed = o.speed or 1
		if self.Opts.SoundAt then
			local att = Instance.new("Attachment")
			att.WorldPosition = self.Opts.SoundAt
			att.Parent = Workspace.Terrain
			s.RollOffMinDistance, s.RollOffMaxDistance = 14, 320
			s.Parent = att
			task.delay(o.len or 3, function() att:Destroy() end)
		else
			s.Parent = SoundService
		end
		s:Play()
		task.delay(o.len or 3, function() s:Destroy() end)
	end
	if delay <= 0.01 then play() else task.delay(delay, play) end
end

-- ─── timeline ───────────────────────────────────────────────────────────────────────────────
-- the effects are authored in prototype time; the rarity tier stretches build-up and release
function Session:_warp(t: number): number
	local e, T = self.E, self.Tier
	if t < self.HideAt then return t / T.Kb end
	return e.Hide + (t - self.HideAt) / T.Kr
end
function Session:_toReal(tA: number): number
	local e, T = self.E, self.Tier
	if tA < e.Hide then return tA * T.Kb end
	return self.HideAt + (tA - e.Hide) * T.Kr
end
function Session:At(tA: number, fn)
	table.insert(self.Events, { T = tA, Fn = fn })
end
function Session:Tick(key: string, rate: number): boolean
	local q = math.floor(self.T * rate)
	if self.Ticks[key] ~= q then
		self.Ticks[key] = q
		return true
	end
	return false
end

-- rarity layer for Epic and above: charging pool + energy off the suit + levitation, release rings
function Session:_initAura()
	local T = self.Tier
	if T.Rank < 2 then return end
	local c = self.E.Color
	local A = { C = c }
	A.Pool = self:Ring({ Color = c, Thick = 0.02, Segments = 36 })
	A.Ring = self:Ring({ Color = c, Thick = 0.035, Segments = 40 })
	if T.Rank >= 4 then
		A.Ring2 = self:Ring({ Color = c, Thick = 0.025, Segments = 36 })
		A.Pillar = self:Pillar({ Color = c })
	end
	A.Under = self:Glow({ Color = c, Image = TEX.Glow, Brightness = 2 })
	self.Aura = A
	self:At(self.E.Hide, function()
		if T.Rank >= 3 then
			self:Burst(V3(0, 0.2, 0), 40 * T.Rank, { noAmp = true, tex = TEX.Spark, color = { c, c }, size = { 0.035, 0.006 }, life = { 0.8, 1.6 }, speed = { 0.6, 2.2 }, spread = 25, drag = 0.6, shape = "ring", r = 1.0, bright = 3 })
		end
	end)
end
function Session:_stepAura()
	local A = self.Aura
	if not A then return end
	local T, e = self.Tier, self.E
	local b = seg(self.TA, 0, e.Hide)
	local after = self.T - self.HideAt
	local fadeAfter = 1 - seg(after, 0, 0.6)
	A.Pool:Set(V3(0, 0.02, 0), 0.35 + 0.35 * b, (0.2 + 0.6 * b) * (if after > 0 then fadeAfter else b), "h")
	A.Under:Set(V3(0, 0.05, 0), 1.6 + b, 0.5 * b * (if after > 0 then fadeAfter else 1))
	if not self.Hidden0 then
		self.B.Offset += V3(0, 0.05 * T.Rank * ease.inOutSine(b), 0) -- levitation while it charges
		if self.T > 0.02 and self:Tick("aura", 30) then
			for _, s in self:Sample(1 + T.Rank) do
				self:Burst(s.p, 1, { noAmp = true, tex = TEX.Glow, color = A.C, size = { 0.025, 0.003 }, life = { 0.35, 0.6 }, speed = { 0.8, 1.8 }, dir = V3(0, 1, 0), spread = 15, drag = 1, stretch = 2, bright = 1 + 3 * b })
			end
		end
	end
	if after > 0 then
		local k = seg(after, 0, 0.75 * T.Kr)
		A.Ring:Set(V3(0, 0.03, 0), 0.3 + 3.4 * T.Amp * ease.outCubic(k) * 0.55, (1 - k) ^ 1.3, "h")
		if A.Ring2 then
			local k2 = seg(after, 0.12, 0.9 * T.Kr)
			A.Ring2:Set(V3(0, 1.1, 0), 0.3 + 2.8 * T.Amp * ease.outCubic(k2) * 0.5, (1 - k2) ^ 1.4 * (if after > 0.12 then 1 else 0), 0.3)
		end
		if A.Pillar then
			local kp = seg(after, 0, 0.6)
			A.Pillar:Set(V3(0, 0, 0), 0.45 * (1 - ease.inQuad(kp)) + 0.01, 14, 1 - kp)
		end
	else
		A.Ring:Set(V3(), 0, 0, "h")
		if A.Ring2 then A.Ring2:Set(V3(), 0, 0, "h") end
		if A.Pillar then A.Pillar:Set(V3(), 0, 0, 0) end
	end
end

-- ─── main loop ──────────────────────────────────────────────────────────────────────────────
function Session:Step(dt: number)
	if self.Dead then return end
	self.T += dt
	local tA = self:_warp(self.T)
	local dtA = tA - self.TA
	self.TA = tA
	resetBodyState(self.B)
	self.Scr = { Bright = 0, Contrast = 0, Sat = 0, Tint = Color3.new(1, 1, 1) }
	for _, L in self.Lights do L.Set = false end
	for _, ev in self.Events do
		if not ev.Done and tA >= ev.T then
			ev.Done = true
			local ok, err = pcall(ev.Fn, self)
			if not ok then warn("[ElimFX] event: " .. tostring(err)) end
		end
	end
	self:BeginBolts()
	if self.Def and self.Def.Update then
		local ok, err = pcall(self.Def.Update, self, tA, dtA, self.S)
		if not ok and not self.Warned then
			self.Warned = true
			warn("[ElimFX] " .. self.E.Id .. ": " .. tostring(err))
		end
	end
	self:_stepAura()
	self:EndBolts()
	if not self.Hidden0 and self.T >= self.HideAt then
		self.Hidden0 = true
		self.BodyGone = true
		self.Body.Parent = nil
		if self.Opts.OnHidden then task.spawn(self.Opts.OnHidden) end
	end
	self:_applyBody()
	self:_stepShards(dt)
	for _, L in self.Lights do if not L.Set then L.PL.Brightness = 0 end end
	if self.ScreenOK and cc then
		local s = self.Scr
		cc.Brightness = math.clamp(s.Bright, -0.4, 0.6)
		cc.Contrast = math.clamp(s.Contrast, 0, 1.5)
		cc.Saturation = math.clamp(s.Sat, -1, 0)
		cc.TintColor = Color3.new(1, 1, 1):Lerp(s.Tint, math.clamp(s.Bright * 0.6, 0, 0.35))
	end
	if self.T >= self.Duration then
		self:Destroy()
		if self.Opts.OnDone then task.spawn(self.Opts.OnDone) end
	end
end

function Session:Seek(t: number)
	local step = 1 / 60
	while self.T < t - 1e-6 and not self.Dead do
		self:Step(math.min(step, t - self.T))
	end
end

function Session:Destroy()
	if self.Dead then return end
	self.Dead = true
	if self.Conn then self.Conn:Disconnect() end
	for d, v in self.Hidden do
		if d.Parent then d.LocalTransparencyModifier = if self.Opts.KeepRigHidden then 1 else v end
	end
	if self.ScreenOK then
		screenOwners -= 1
		if screenOwners <= 0 and cc then
			cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = 0, 0, 0, Color3.new(1, 1, 1)
		end
	end
	self.Folder:Destroy()
	if self.Body then self.Body:Destroy() end
end

-- ─── public ─────────────────────────────────────────────────────────────────────────────────
local Effects = nil
function ElimFX.Play(rig: Model, effectId: string, opts)
	opts = opts or {}
	Effects = Effects or require(script:WaitForChild("Effects"))
	local e = Catalog.ById[effectId] or Catalog.ById[Catalog.Default]
	local self = setmetatable({}, Session)
	self.Opts = opts
	-- effect scale: sizes, reach and particle speed grow; the body itself stays life-size
	self.FXS = math.clamp(opts.Scale or 1, 0.25, 4)
	self.E, self.Def, self.Tier = e, Effects[e.Id], Catalog.Tiers[e.Rarity]
	self.Rig = rig
	self.Seed = opts.Seed or (1234 + e.Index * 97)
	self.Rng = Random.new(self.Seed)
	local f = Instance.new("Folder")
	f.Name = "Elim_" .. e.Id
	f.Parent = folderFor(opts)
	self.Folder = f
	self.Particles = opts.Particles ~= false
	self.Hidden = {}
	self.BoltPool, self.BoltUsed = {}, 0
	self.ShardList, self.Lights, self.EmitCache = {}, {}, {}
	self.Events, self.Ticks = {}, {}
	self.B = {}
	resetBodyState(self.B)
	self.Scr = { Bright = 0, Contrast = 0, Sat = 0, Tint = Color3.new(1, 1, 1) }
	self.HideAt, self.Duration = Catalog.Timing(e.Id)
	self.T, self.TA = 0, 0
	captureBody(self)
	-- screen effects only when this is close to the viewer
	local cam = Workspace.CurrentCamera
	local dist = (cam.CFrame.Position - self.O.Position).Magnitude
	self.ScreenOK = opts.Screen ~= false and self.Particles and dist < 90
	self.ShakeScale = math.clamp(1 - dist / 90, 0, 1)
	if self.ScreenOK then
		screenOwners += 1
		ensureCC()
	end
	self.SoundOK = opts.Sound ~= false and self.Particles
	self.OnPieceDissolve = function(_rec, p)
		if self.Particles then
			local c = self.B.Edge
			self:Burst(p, 6, { noAmp = true, tex = TEX.Glow, color = { c, c }, size = { 0.035, 0.004 }, life = { 0.3, 0.55 }, speed = { 0.3, 1.3 }, drag = 2, stretch = 1.5, bright = 3 })
		end
	end
	self.S = {}
	if self.Def and self.Def.Init then
		local ok, err = pcall(function() self.S = self.Def.Init(self) or {} end)
		if not ok then warn("[ElimFX] init " .. e.Id .. ": " .. tostring(err)) end
	end
	self:_initAura()
	if self.SoundOK and self.Def and self.Def.Sound then pcall(self.Def.Sound, self) end
	if not opts.Manual then
		local clock = opts.Clock or os.clock
		local t0 = opts.Start or clock()
		local late = clock() - t0
		if late > 0.05 then
			-- seen late (joined / streamed in mid-way): fast-forward silently
			local snd = self.SoundOK
			self.SoundOK = false
			self:Seek(late)
			self.SoundOK = snd
		end
		self.Conn = RunService.RenderStepped:Connect(function()
			local dt = (clock() - t0) - self.T
			if dt > 0 then self:Step(math.min(dt, 0.1)) end
		end)
	end
	return self
end

-- camera shake decay (one global)
RunService.RenderStepped:Connect(function(dt)
	if screen.Trauma > 0 then
		screen.Seed += dt * 60
		screen.Trauma = math.max(0, screen.Trauma - dt * 1.4)
	end
end)

return ElimFX
