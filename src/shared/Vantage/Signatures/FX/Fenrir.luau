--!nonstrict
--[[
	VANTAGE — Signature 02 FENRIR, visuals (client) — v2 2026-11-19
	A rune circle burns into the ground (two spinning rings, a band of runes, a valknut at the centre),
	a column of ice-light erupts from it and a GIANT spectral wolf bursts out howling. It gallops the
	server's path wreathed in crackling energy, ghost ribbons and frost mist, splitting a frost trail of
	ice shards through the ground, rakes anyone in the lane with huge claw slashes and, at the end,
	lunges and detonates into light. Ember eyes from the myth. Visual only; the server decides hits.

	Fenrir.Play{ Origin = CFrame, Path = { Vector3 }, Speed = 80, Targets = { ... } }   (yields)
	Fenrir.HitAt(pos, along)
]]

local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local Gait = require(Signatures.CreatureGait)

local Fenrir = {}

local C = {
	White = Color3.new(1, 1, 1),
	Ice = Color3.fromRGB(150, 210, 255),
	Deep = Color3.fromRGB(70, 140, 255),
	Mist = Color3.fromRGB(214, 234, 255),
	Ember = Color3.fromRGB(255, 122, 46),
	Shard = Color3.fromRGB(170, 225, 255),
}
Fenrir.Colors = C
Fenrir.Tuning = { Windup = 1.0, Speed = 64, Length = 34, HitRadius = 6, Lunge = 0.5, Dissolve = 0.9, CircleRadius = 7.5, Rear = 0.55, Linger = 3.5 }

Fenrir.Sounds = {
	Erupt = { "rbxassetid://18245316227", 1.0, 1.3 },
	Hit = { "rbxassetid://9125484367", 0.8, 1.6 },
	Burst = { "rbxassetid://18245316227", 1.1, 0.9 },
}
local LAYERS = { Build = { "Charge", "Rumble" }, Erupt = { "IceShatter", "Blast" }, Howl = { "WolfHowl" }, Hit = { "IceShatter2", "WhooshShort" }, Burst = { "IceShatter", "Boom" } }
local function snd(k, pos) for _, n in LAYERS[k] or {} do VFX.Sfx(n, pos) end end

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "function" then return t() end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.TimeScale = VFX.TimeScale
	for k, v in props do e[k] = v end
	e.Parent = parent
	return e
end

local KB = VFX.KB
local G4 = Enum.ParticleFlipbookLayout.Grid4x4
local G2 = Enum.ParticleFlipbookLayout.Grid2x2
local UP = Vector3.yAxis
local function flatAt(pos) return VFX.Facing(pos + Vector3.new(0, 0.15, 0), Vector3.yAxis) end
-- a single flat decal on the ground (cracks, shock rings)
local function groundDecal(pos, tex, color, s0, s1, life, o)
	o = o or {}
	return VFX.Burst(pos, { CF = flatAt(pos), Count = o.Count or 1, Texture = tex, Color = color, Size = NumberSequence.new(s0, s1),
		Transparency = o.T or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Life = { life, life }, Speed = { 0.001, 0.001 }, Spread = 0, Drag = 0, Light = o.Light or 1, Brightness = o.Brightness or 2,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Flip = o.Flip, ZOffset = o.Z or 0.2 })
end

------------------------------------------------------------------ rune circle
local GLYPHS = { -- strokes in a unit cell (x across, y outward), rune-like shapes
	{ { { 0, -0.5 }, { 0, 0.5 } }, { { 0, 0.2 }, { 0.35, 0.5 } }, { { 0, -0.05 }, { 0.35, 0.25 } } }, -- fehu-ish
	{ { { -0.3, -0.5 }, { 0, 0.5 } }, { { 0, 0.5 }, { 0.3, -0.5 } } },                               -- ingwaz-ish
	{ { { 0, -0.5 }, { 0, 0.5 } }, { { -0.3, 0.5 }, { 0.3, -0.5 } } },                                -- naudiz-ish
	{ { { -0.25, -0.5 }, { -0.25, 0.5 } }, { { -0.25, 0.5 }, { 0.25, 0 } }, { { 0.25, 0 }, { -0.25, -0.5 } } }, -- thurisaz-ish
}

local function circlePts(cf, r, n, a0, frac)
	local pts = {}
	local m = math.max(2, math.floor(n * frac))
	for i = 0, m do
		local a = a0 + (i / n) * math.pi * 2
		pts[#pts + 1] = cf:PointToWorldSpace(Vector3.new(math.cos(a) * r, 0.08, math.sin(a) * r))
	end
	return pts
end

local function runeCircle(cf: CFrame, R: number, life: number)
	local outer = VFX.Bolt({ Width = 0.16, Color = C.Ice, GlowScale = 6, Branches = 0 })
	local outer2 = VFX.Bolt({ Width = 0.07, Color = C.Deep, GlowScale = 5, Branches = 0 })
	local inner = VFX.Bolt({ Width = 0.1, Color = C.Ice, GlowScale = 5, Branches = 0 })
	local glyphBolts, valk = {}, {}
	for i = 1, 3 do valk[i] = VFX.Bolt({ Width = 0.1, Color = C.Ice, GlowScale = 5, Branches = 0 }) end
	local NG = 16
	for i = 1, NG do glyphBolts[i] = VFX.Bolt({ Width = 0.07, Color = C.Ice, GlowScale = 5, Branches = 0 }) end
	local pool = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = cf * CFrame.new(0, 0.12, 0) })
	local light = Instance.new("PointLight"); light.Color = C.Ice; light.Brightness = 0; light.Range = R * 3.5; light.Shadows = false; light.Parent = pool
	local flat = { Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(0.001), SpreadAngle = Vector2.zero, LockedToPart = true, Rotation = NumberRange.new(0, 360) }
	local function flatEmitter(props) local t = table.clone(flat); for k, v in props do t[k] = v end; return emitter(pool, t) end
	local floorGlow = flatEmitter({ Texture = VFX.Tex.Glow, Color = ColorSequence.new(C.Ice), LightEmission = 1, Size = NumberSequence.new(R * 2.9),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.5), Rate = 12 })
	local pulse = flatEmitter({ Texture = VFX.Tex.Shock, Color = ColorSequence.new(C.White, C.Ice), LightEmission = 1, Size = NumberSequence.new(R * 0.3, R * 2.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.55), Rate = 4 })
	local swirl = flatEmitter({ Texture = KB.Rift, Color = ColorSequence.new(C.Ice), LightEmission = 1, Brightness = 3, Size = NumberSequence.new(R * 1.6, R * 1.9),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.2), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.6),
		Rate = 5, RotSpeed = NumberRange.new(90, 140), FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop })
	local twinkle = emitter(holder, { Texture = KB.Star, Color = ColorSequence.new(C.White, C.Ice), LightEmission = 1, Brightness = 3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 6), Rate = 25, Rotation = NumberRange.new(0, 45),
		Shape = Enum.ParticleEmitterShape.Disc, EmissionDirection = Enum.NormalId.Top })
	local frost = flatEmitter({ Texture = VFX.Tex.Smoke, Color = ColorSequence.new(C.Mist), LightEmission = 0.5, Size = NumberSequence.new(R * 2.2, R * 2.6),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.6), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.9), Rate = 4, RotSpeed = NumberRange.new(-20, 20) })
	local holder = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = cf * CFrame.new(0, 0.2, 0) })
	local motes = emitter(holder, {
		Texture = VFX.Tex.Spark, Color = ColorSequence.new(C.White, C.Ice), LightEmission = 1, Size = NumberSequence.new(0.45, 0),
		Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(12, 12), Rate = 120,
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		EmissionDirection = Enum.NormalId.Top,
	})
	holder.Size = Vector3.new(R * 2, 0.2, R * 2)
	local fog = emitter(holder, {
		Texture = VFX.Tex.Smoke, Color = ColorSequence.new(C.Mist), LightEmission = 0.5, Size = NumberSequence.new(3, 7),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 4), Rate = 30, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
		Shape = Enum.ParticleEmitterShape.Disc, EmissionDirection = Enum.NormalId.Top,
	})
	task.spawn(function()
		local f = 0
		VFX.Step(function(_, t)
			f += 1
			local reveal = math.clamp(t / 0.35, 0, 1)
			local fade = math.clamp((life - t) / 0.45, 0, 1)
			local pulse = 0.75 + 0.25 * math.sin(t * 22)
			local a = fade * pulse
			outer:DrawPoints(circlePts(cf, R, 64, t * 0.9, reveal), a)
			outer2:DrawPoints(circlePts(cf, R * 1.07, 64, -t * 0.6, reveal), a * 0.8)
			inner:DrawPoints(circlePts(cf, R * 0.72, 48, -t * 1.3, reveal), a)
			-- rune band between the rings, turning against the outer ring
			for i, b in glyphBolts do
				local ang = -t * 1.3 + (i / NG) * math.pi * 2
				local show = reveal >= (i / NG)
				local centre = cf:PointToWorldSpace(Vector3.new(math.cos(ang) * R * 0.86, 0.08, math.sin(ang) * R * 0.86))
				local out = (centre - cf.Position) * Vector3.new(1, 0, 1)
				out = out.Magnitude > 1e-3 and out.Unit or Vector3.xAxis
				local across = Vector3.yAxis:Cross(out)
				local g = GLYPHS[(i % #GLYPHS) + 1]
				local pts = {}
				for _, stroke in g do
					pts[#pts + 1] = centre + across * stroke[1][1] * 0.9 + out * stroke[1][2] * 0.9
					pts[#pts + 1] = centre + across * stroke[2][1] * 0.9 + out * stroke[2][2] * 0.9
				end
				b:DrawPoints(pts, show and a or 0)
			end
			-- valknut: three interlocked triangles at the centre
			for k, b in valk do
				local rot = t * 0.7 + (k - 1) * math.rad(40)
				local rr = R * 0.45 * reveal
				local tri = {}
				for v = 0, 3 do
					local ang = rot + v * (math.pi * 2 / 3)
					tri[#tri + 1] = cf:PointToWorldSpace(Vector3.new(math.cos(ang) * rr + (k - 2) * 0.35, 0.09, math.sin(ang) * rr))
				end
				b:DrawPoints(tri, a)
			end
			light.Brightness = 4 * a
			return t < life
		end)
		motes.Enabled = false; fog.Enabled = false
		outer:Destroy(); outer2:Destroy(); inner:Destroy()
		for _, b in glyphBolts do b:Destroy() end
		for _, b in valk do b:Destroy() end
		floorGlow.Enabled = false; pulse.Enabled = false; frost.Enabled = false; swirl.Enabled = false; twinkle.Enabled = false
		VFX.Tween(light, 0.4, { Brightness = 0 })
		VFX.Cleanup(pool, 1.2)
		VFX.Cleanup(holder, 1.5)
	end)
end

local function implode(pos)
	VFX.Burst(pos + Vector3.new(0, 2, 0), { Count = 1, Texture = KB.WavesIn, Color = C.Ice, Size = NumberSequence.new(40, 0),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.3), NumberSequenceKeypoint.new(1, 0.6) }),
		Life = { 0.35, 0.35 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 2 })
	VFX.Burst(pos + Vector3.new(0, 1, 0), { CF = flatAt(pos), Count = 1, Texture = KB.Shock, Color = C.Ice, Size = NumberSequence.new(26, 2),
		Transparency = NumberSequence.new(0.2, 0.6), Life = { 0.35, 0.35 }, Speed = { 0.001, 0.001 }, Spread = 0, Light = 1, Brightness = 2,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular })
end

-- column of ice-light + shockwave + shard burst where the wolf bursts out
local function eruption(pos: Vector3)
	-- ground: shatter crack + burst decal + spiky shock ring
	groundDecal(pos, KB.Crack, C.Ice, 6, 22, 1.4, { T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) }) })
	groundDecal(pos, KB.CrackGlow, C.Ice, 4, 14, 0.35, { Brightness = 1 })
	groundDecal(pos, KB.WaterRing, C.Ice, 2, 30, 0.5)
	groundDecal(pos, KB.Ring, C.Shard, 4, 26, 0.35, { Light = 1 })
	-- column of light: stacked soft glows stretched upward
	for h = 0, 30, 6 do
		VFX.Burst(pos + Vector3.new(0, h + 3, 0), { Count = 1, Texture = VFX.Tex.Glow, Color = h < 12 and C.White or C.Ice, Size = NumberSequence.new(7 - h * 0.1, 2),
			Transparency = NumberSequence.new(0.45 + h / 70, 1), Life = { 0.45, 0.45 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 1.2,
			Orientation = Enum.ParticleOrientation.FacingCameraWorldUp, Squash = NumberSequence.new(-2.2) })
	end
	-- frost spikes and ice shatter bursting up
	VFX.Burst(pos + Vector3.new(0, 1, 0), { CF = VFX.Facing(pos, UP), Count = 10, Texture = KB.Spikes, Color = C.Ice, Size = NumberSequence.new(8, 12),
		Transparency = NumberSequence.new(0.1, 1), Life = { 0.25, 0.4 }, Speed = { 70, 110 }, Spread = 30, Drag = 6, Light = 1, Brightness = 2,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Flip = { G2 } })
	VFX.Burst(pos + Vector3.new(0, 2, 0), { CF = VFX.Facing(pos, UP), Count = 14, Texture = KB.IceDebris, Color = C.Shard, Size = NumberSequence.new(2.5, 3),
		Life = { 0.8, 1.3 }, Speed = { 25, 55 }, Spread = 60, Drag = 1, Accel = Vector3.new(0, -70, 0), Light = 0.6, Flip = { G4 } })
	VFX.Burst(pos + Vector3.new(0, 1, 0), { CF = VFX.Facing(pos, UP), Count = 18, Texture = KB.Snow, Color = C.White, Size = NumberSequence.new(0.55, 0),
		Life = { 0.9, 1.6 }, Speed = { 15, 45 }, Spread = 80, Drag = 2, Accel = Vector3.new(0, -12, 0), Light = 1, Brightness = 2, RotSpeed = 180 })
	VFX.Burst(pos + Vector3.new(0, 3, 0), { Count = 1, Texture = KB.Impact, Color = C.Ice, Size = NumberSequence.new(4, 18), Transparency = NumberSequence.new(0.3, 1),
		Life = { 0.2, 0.2 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 1.5 })
	VFX.Shockwave(VFX.Facing(pos + Vector3.new(0, 0.3, 0), Vector3.yAxis), C.Ice, 26, 0.45)
	VFX.Shockwave(VFX.Facing(pos + Vector3.new(0, 0.4, 0), Vector3.yAxis), C.White, 14, 0.3)
	VFX.Burst(pos + Vector3.new(0, 1, 0), { CF = VFX.Facing(pos, Vector3.yAxis), Count = 20, Color = C.Shard, Size = { 0.6, 0 }, Life = { 0.4, 0.9 }, Speed = { 25, 55 }, Spread = 55, Drag = 2, Accel = Vector3.new(0, -60, 0), Squash = NumberSequence.new(-1.5), Orientation = Enum.ParticleOrientation.VelocityParallel })
	VFX.Burst(pos + Vector3.new(0, 2, 0), { Count = 16, Texture = KB.Air, Flip = { G4 }, Color = C.Mist, Size = { 5, 10 }, Transparency = { 0.4, 1 }, Life = { 0.7, 1.3 }, Speed = { 8, 18 }, Light = 0.4 })
	VFX.Flash(pos + Vector3.new(0, 3, 0), C.Ice, 6, 34, 0.5)
	VFX.ScreenTint(pos, 60, Color3.fromRGB(205, 228, 255), 0.15, 0.35)
	snd("Erupt", pos)
end

------------------------------------------------------------------ trail pieces
------------------------------------------------------------------ hit
function Fenrir.HitAt(pos: Vector3, along: Vector3)
	local fwd = (along * Vector3.new(1, 0, 1))
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.zAxis
	local chest = pos + Vector3.new(0, 2.5, 0)
	-- three claw crescents raking across the target (flat sprites facing along the run)
	for k, rot in { -55, -35, -15 } do
		VFX.Later((k - 1) * 0.035, function()
			VFX.Burst(chest + Vector3.new(0, (2 - k) * 0.8, 0), { CF = VFX.Facing(chest, fwd), Count = 1, Texture = KB.Crescents, Color = k == 2 and C.White or C.Ice,
				Size = NumberSequence.new(8, 10.5), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 1) }),
				Life = { 0.28, 0.28 }, Speed = { 0.001, 0.001 }, Spread = 0, Drag = 0, Light = 1, Brightness = 3, Rot = NumberRange.new(rot),
				Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Flip = { G4 }, ZOffset = 1 })
		end)
	end
	-- slash flash + shatter impact + spiky ring
	VFX.Burst(chest, { Count = 1, Texture = KB.SlashFlash, Color = C.White, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 16), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new(0, 1), Life = { 0.14, 0.14 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 4, Rot = NumberRange.new(-35),
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp, ZOffset = 1.5 })
	VFX.Burst(chest, { Count = 1, Texture = KB.Impact, Color = C.Ice, Size = NumberSequence.new(3, 13), Transparency = NumberSequence.new(0, 1),
		Life = { 0.22, 0.22 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 3 })
	VFX.Burst(chest, { CF = VFX.Facing(chest, fwd), Count = 1, Texture = KB.WaterRing, Color = C.Ice, Size = NumberSequence.new(2, 15),
		Transparency = NumberSequence.new(0.1, 1), Life = { 0.3, 0.3 }, Speed = { 0.001, 0.001 }, Spread = 0, Drag = 0, Light = 1, Brightness = 2,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular })
	-- ice shards and snow thrown along the run
	VFX.Burst(chest, { CF = VFX.Facing(chest, fwd), Count = 8, Texture = KB.IceDebris, Color = C.Shard, Size = NumberSequence.new(1.6, 2.2),
		Life = { 0.5, 0.8 }, Speed = { 20, 40 }, Spread = 55, Drag = 2, Accel = Vector3.new(0, -60, 0), Light = 0.6, Flip = { G4 } })
	VFX.Burst(chest, { CF = VFX.Facing(chest, fwd), Count = 22, Texture = KB.Star, Color = C.White, Size = NumberSequence.new(1.3, 0),
		Life = { 0.25, 0.5 }, Speed = { 18, 40 }, Spread = 70, Drag = 3, Light = 1, Brightness = 3, Rot = NumberRange.new(0, 45) })
	VFX.Flash(chest, C.Ice, 9, 22, 0.3)
	snd("Hit", pos)
end

------------------------------------------------------------------ main
function Fenrir.Play(o)
	local T = Fenrir.Tuning
	local path = o.Path
	local speed = o.Speed or T.Speed
	local origin = o.Origin
	local targets = o.Targets or {}
	local done = {}

	local first = path[1]
	local dir0 = ((path[2] or first + origin.LookVector) - first) * Vector3.new(1, 0, 1)
	dir0 = dir0.Magnitude > 1e-3 and dir0.Unit or origin.LookVector

	-- 1. rune circle on the ground where the wolf will burst out
	local circleCF = VFX.Facing(first, dir0)
	runeCircle(circleCF, T.CircleRadius, T.Windup + 1.3)
	snd("Build", first)
	VFX.Shake(first, 60, 0.4, T.Windup)

	-- the wolf, giant and spectral
	local wolf = Signatures.Assets.SIG_Fenrir:Clone()
	wolf:ScaleTo(wolf:GetScale() * (T.Length / (wolf:GetAttribute("Length") or 14)))
	local mesh = wolf.PrimaryPart
	mesh.Transparency = 1
	wolf.Parent = VFX.Folder()
	local hl = Instance.new("Highlight")
	hl.FillColor = C.Ice; hl.FillTransparency = 1; hl.OutlineColor = C.White; hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = wolf
	local gait = Gait.new(wolf, Gait.Presets.Fenrir)
	local B = function(n) return wolf:FindFirstChild(n, true) end
	local spine0, spine1, spine2, head, jaw, tail0, tail1 = B("Spine0"), B("Spine1"), B("Spine2"), B("Head"), B("Jaw"), B("Tail0"), B("Tail1")
	local crackleBones = {}
	for _, n in { "Spine0", "Spine1", "Spine2", "Neck", "Head", "Leg_FL_2", "Leg_FR_2", "Leg_BL_1", "Leg_BR_1", "Leg_BL_2", "Leg_BR_2", "Tail0", "Tail1" } do
		local b = B(n); if b then crackleBones[#crackleBones + 1] = b end
	end
	local light = Instance.new("PointLight"); light.Color = C.Ice; light.Brightness = 0; light.Range = 40; light.Shadows = false; light.Parent = mesh
	local mist = emitter(spine1, {
		Texture = KB.Air, FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(C.Ice), LightEmission = 0.6, Size = NumberSequence.new(3, 6),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(1, 4), Rate = 0, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
	})
	local wisps = emitter(spine2, {
		Texture = VFX.Tex.Spark, Color = ColorSequence.new(C.White, C.Ice), LightEmission = 1, Size = NumberSequence.new(0.8, 0),
		Squash = NumberSequence.new(-2), Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.25, 0.55), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(50, 50), Rate = 0,
		EmissionDirection = Enum.NormalId.Top,
	})
	local tailFog = emitter(tail1, {
		Texture = VFX.Tex.Smoke, Color = ColorSequence.new(C.Mist), LightEmission = 0.7, Size = NumberSequence.new(2, 4),
		Transparency = NumberSequence.new(0.45, 1), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(0.5, 2), Rate = 0,
	})
	local fireBones = {}
	for _, n in { "Spine0", "Spine1", "Spine2", "Neck", "Tail0" } do local b = B(n); if b then fireBones[#fireBones + 1] = b end end
	local spiritFire = {}
	for _, b in fireBones do
		spiritFire[#spiritFire + 1] = emitter(b, { Texture = KB.BlueFire, Color = ColorSequence.new(C.Ice, C.Deep), LightEmission = 1, Brightness = 1.3,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 3) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(30, 30), Rate = 0, EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, 12, 0), Rotation = NumberRange.new(-20, 20), FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot })
		spiritFire[#spiritFire + 1] = emitter(b, { Texture = KB.Arc1, Color = ColorSequence.new(C.Ice), LightEmission = 1, Brightness = 3,
			Size = NumberSequence.new(3, 4.5), Lifetime = NumberRange.new(0.08, 0.15), Speed = NumberRange.new(0.01), Rate = 0, Rotation = NumberRange.new(0, 360),
			FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot })
	end
	local eyes = {}
	for _, b in { head, jaw } do
		if b then
			eyes[#eyes + 1] = emitter(b, {
				Texture = KB.Star, Color = ColorSequence.new(C.Ember, Color3.fromRGB(255, 70, 30)), LightEmission = 1, Brightness = 3, Size = NumberSequence.new(0.9, 0.3),
				Transparency = NumberSequence.new(0, 1), Lifetime = NumberRange.new(0.05, 0.1), Speed = NumberRange.new(0), Rate = 0, LockedToPart = true,
			})
		end
	end
	-- ghost ribbons streaming off the spine and the tail
	local ribbonColor = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.White), ColorSequenceKeypoint.new(0.3, C.Ice), ColorSequenceKeypoint.new(1, C.Deep) })
	local function ribbon(a0, a1, life)
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0; tr.Attachment1 = a1
		tr.Color = ribbonColor; tr.LightEmission = 1; tr.LightInfluence = 0; tr.FaceCamera = true
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		tr.Lifetime = life / VFX.TimeScale; tr.WidthScale = NumberSequence.new(1, 0.2); tr.Enabled = false
		tr.Parent = mesh
		return tr
	end
	local ribbons = { ribbon(spine0, spine2, 0.35), ribbon(tail0, tail1, 0.45) }
	local crackle = { VFX.Bolt({ Width = 0.05, Color = C.Ice, GlowScale = 5, Branches = 1, Depth = 3, Jag = 0.25 }), VFX.Bolt({ Width = 0.04, Color = C.Deep, GlowScale = 5, Branches = 0, Depth = 3, Jag = 0.3 }) }

	local function setLive(on)
		mist.Rate = on and 18 or 0
		wisps.Rate = on and 45 or 0
		tailFog.Rate = on and 40 or 0
		for _, e in eyes do e.Rate = on and 30 or 0 end
		for k, e in spiritFire do e.Rate = on and (k % 2 == 1 and 14 or 6) or 0 end
		for _, r in ribbons do r.Enabled = on end
	end

	local frame = 0
	local function dress()
		frame += 1
		if frame % 2 == 0 and #crackleBones > 2 then
			for _, b in crackle do
				local i = VFX.Rng:NextInteger(1, #crackleBones)
				local j = VFX.Rng:NextInteger(1, #crackleBones)
				if i == j then j = (j % #crackleBones) + 1 end
				b:Draw(crackleBones[i].TransformedWorldCFrame.Position, crackleBones[j].TransformedWorldCFrame.Position, 0.9)
			end
		end
	end

	local function place(pos, heading, lift, pitch)
		local h = heading * Vector3.new(1, 0, 1)
		h = h.Magnitude > 1e-3 and h.Unit or dir0
		local p = pos + Vector3.new(0, lift or 0, 0)
		wolf:PivotTo(VFX.Facing(p, h) * CFrame.Angles(pitch or 0, 0, 0))
	end

	-- wind-up: circle glows; at the end the wolf erupts out of its centre with a leap
	place(first - Vector3.new(0, 9, 0), dir0, 0)
	VFX.Wait(T.Windup * 0.75)
	implode(first)
	VFX.Wait(0.3)
	eruption(first)
	setLive(true)
	local leap = 0.42
	VFX.Step(function(dt, t)
		local k = math.clamp(t / leap, 0, 1)
		local fade = math.clamp(t / 0.15, 0, 1)
		mesh.Transparency = 1 - fade
		hl.FillTransparency = 1 - fade * 0.3; hl.OutlineTransparency = 1 - fade
		light.Brightness = 8 * fade
		local pos = first + dir0 * (k * 6)
		place(pos, dir0, -6 * (1 - k) ^ 2 + math.sin(k * math.pi) * 5, math.rad(25) * (1 - k))
		gait:Step(dt, 1.2)
		dress()
		return t < leap
	end)

	-- 2b. it rears up and howls (frost breath, screen shake)
	snd("Howl", first)
	VFX.Shake(first, 70, 1.2, 0.5)
	VFX.ScreenTint(first, 60, Color3.fromRGB(200, 225, 255), 0.08, 0.6)
	local rearAt = first + dir0 * 6
	local breath = head and VFX.Emitter(head, { Texture = KB.Air, Color = ColorSequence.new(C.Mist), LightEmission = 0.5, Size = NumberSequence.new(2, 6),
		Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(8, 14), SpreadAngle = Vector2.new(15, 15),
		Rate = 40, EmissionDirection = Enum.NormalId.Front, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot })
	VFX.Step(function(dt, t)
		local k = math.clamp(t / T.Rear, 0, 1)
		place(rearAt, dir0, math.sin(k * math.pi) * 1.2, math.rad(32) * math.sin(k * math.pi))
		gait:Step(dt, 0.25)
		dress()
		return t < T.Rear
	end)
	if breath then breath.Enabled = false end

	-- 3. gallop the path: frost trail, shards, crackling body
	local stopRun = VFX.SfxLoop("Gallop", mesh, 1, 1.25)
	local segs, total = {}, 0
	for i = 1, #path - 1 do
		local l = (path[i + 1] - path[i]).Magnitude
		segs[i] = { a = path[i], b = path[i + 1], l = l, s = total }
		total += l
	end
	local function at(d)
		d = math.clamp(d, 0, total)
		for _, s in segs do
			if d <= s.s + s.l or s == segs[#segs] then
				local k = s.l > 0 and (d - s.s) / s.l or 0
				return s.a:Lerp(s.b, k), (s.b - s.a)
			end
		end
		return path[#path], dir0
	end
	local d = 6
	-- frost left behind: a soft glowing ground trail under the paws + flat frost, ice splinters and low mist
	local po = mesh.PivotOffset
	local tA = Instance.new("Attachment"); tA.Position = po:PointToWorldSpace(Vector3.new(-2.4, 0.15, 0)); tA.Parent = mesh
	local tB = Instance.new("Attachment"); tB.Position = po:PointToWorldSpace(Vector3.new(2.4, 0.15, 0)); tB.Parent = mesh
	local frostTrail = Instance.new("Trail")
	frostTrail.Attachment0 = tA; frostTrail.Attachment1 = tB; frostTrail.FaceCamera = false
	frostTrail.Texture = VFX.Tex.Glow; frostTrail.TextureMode = Enum.TextureMode.Stretch
	frostTrail.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.White), ColorSequenceKeypoint.new(0.25, C.Ice), ColorSequenceKeypoint.new(1, C.Deep) })
	frostTrail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
	frostTrail.WidthScale = NumberSequence.new(1, 0.5); frostTrail.LightEmission = 1; frostTrail.LightInfluence = 0
	frostTrail.Lifetime = 1.3 / math.max(VFX.TimeScale, 0.05); frostTrail.MinLength = 0.2; frostTrail.Parent = mesh
	local ground = VFX.Part({ Transparency = 1, Size = Vector3.new(4, 0.2, 3), CFrame = CFrame.new(at(d)) })
	local gFrost = emitter(ground, { Texture = KB.Crack, Color = ColorSequence.new(C.Ice), LightEmission = 1, Brightness = 1.5, Size = NumberSequence.new(3.5, 5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2.6, 3.2), Rate = 0, Speed = NumberRange.new(0.001), SpreadAngle = Vector2.zero, EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-15, 15) })
	local gSplinter = emitter(ground, { Texture = KB.IceDebris, Color = ColorSequence.new(C.White, C.Shard), LightEmission = 0.7, Size = NumberSequence.new(1.4, 1.8),
		FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(12, 28), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, -55, 0), Rate = 0, EmissionDirection = Enum.NormalId.Top })
	local gMist = emitter(ground, { Texture = KB.Air, FlipbookLayout = G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(C.Mist), LightEmission = 0.4, Size = NumberSequence.new(2, 5.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1), Rate = 0, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), Drag = 2 })
	local function trailOn(on)
		frostTrail.Enabled = on
		gFrost.Rate = on and 22 or 0; gSplinter.Rate = on and 45 or 0; gMist.Rate = on and 30 or 0
	end
	trailOn(true)
	local chaseRoot = typeof(o.Chase) == "Instance" and o.Chase:FindFirstChild("HumanoidRootPart") or nil
	local chaseHum = typeof(o.Chase) == "Instance" and o.Chase:FindFirstChildOfClass("Humanoid") or nil
	local chaseUntil = total / speed + (o.ChaseTime or 3)
	VFX.Step(function(dt, t)
		local prevPos = at(d)
		d += speed * dt
		local hunting = chaseRoot and chaseRoot.Parent and chaseHum and chaseHum.Health > 0 and t < chaseUntil
		if hunting and d >= total then -- the path ran out: run straight at the quarry
			local last = path[#path]
			local q = chaseRoot.Position - Vector3.new(0, 3, 0)
			if (Vector3.new(q.X, 0, q.Z) - Vector3.new(last.X, 0, last.Z)).Magnitude > 1 then
				local l = (q - last).Magnitude
				segs[#segs + 1] = { a = last, b = q, l = l, s = total }
				total += l
				path[#path + 1] = q
			end
		end
		local pos, tangent = at(d)
		place(pos, tangent, 0)
		gait:Step(dt, 1)
		dress()
		local h = tangent * Vector3.new(1, 0, 1)
		h = h.Magnitude > 1e-3 and h.Unit or dir0
		ground.CFrame = CFrame.lookAt(pos + Vector3.new(0, 0.15, 0), pos + Vector3.new(0, 0.15, 0) + h)
		for i, tg in targets do
			if not done[i] then
				local p = resolve(tg)
				if p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= T.HitRadius then
					done[i] = true
					Fenrir.HitAt(p - Vector3.new(0, 2.5, 0), pos - prevPos)
				end
			end
		end
		if chaseRoot and chaseRoot.Parent and (Vector3.new(chaseRoot.Position.X, 0, chaseRoot.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= T.HitRadius then
			return false -- caught: lunge
		end
		return d < total
	end)

	trailOn(false)
	stopRun(0.4)
	VFX.Cleanup(ground, 1.6)
	-- 4. lunge, then detonate into light
	local endPos, endTan = at(total)
	local eh = endTan * Vector3.new(1, 0, 1)
	eh = eh.Magnitude > 1e-3 and eh.Unit or dir0
	VFX.Step(function(dt, t)
		local k = math.clamp(t / T.Lunge, 0, 1)
		place(endPos + eh * 7 * k, eh, math.sin(k * math.pi) * 3.5, -math.rad(15) * math.sin(k * math.pi))
		gait:Step(dt, 1.4)
		dress()
		return t < T.Lunge
	end)
	local burstAt = spine1.TransformedWorldCFrame.Position
	setLive(false)
	for _, b in crackle do b:Destroy() end
	local floorAt = endPos + eh * 7
	VFX.Burst(burstAt, { Count = 1, Texture = KB.Impact, Color = C.Ice, Size = NumberSequence.new(6, 28), Transparency = NumberSequence.new(0.15, 1),
		Life = { 0.3, 0.3 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 1.8 })
	VFX.Burst(burstAt, { Count = 1, Texture = VFX.Tex.Glow, Color = C.Ice, Size = NumberSequence.new(10, 34), Transparency = NumberSequence.new(0, 1),
		Life = { 0.35, 0.35 }, Speed = { 0, 0 }, Spread = 0, Light = 1, Brightness = 3 })
	groundDecal(floorAt, KB.Crack, C.Ice, 8, 26, T.Linger)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		groundDecal(floorAt + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(5, 11), KB.Snow, C.White, 2.5, 3, T.Linger, { Count = 1 })
	end
	groundDecal(floorAt, KB.WaterRing, C.White, 3, 36, 0.5)
	groundDecal(floorAt, KB.Ring, C.Shard, 5, 32, 0.4)
	VFX.Burst(burstAt, { Count = 16, Texture = KB.IceDebris, Color = C.Shard, Size = NumberSequence.new(2.5, 3.2), Life = { 0.8, 1.3 },
		Speed = { 25, 60 }, Drag = 1, Accel = Vector3.new(0, -70, 0), Light = 0.6, Flip = { G4 } })
	VFX.Burst(burstAt, { Count = 26, Texture = KB.Snow, Color = C.White, Size = NumberSequence.new(0.6, 0), Life = { 1, 1.8 }, Speed = { 15, 50 },
		Drag = 2, Accel = Vector3.new(0, -10, 0), Light = 1, Brightness = 2, RotSpeed = 180 })
	VFX.Burst(burstAt, { Count = 18, Texture = KB.Air, Color = C.Mist, Size = NumberSequence.new(5, 11), Transparency = NumberSequence.new(0.3, 1),
		Life = { 0.6, 1.1 }, Speed = { 10, 25 }, Drag = 3, Light = 0.6, Flip = { G4 } })
	VFX.Flash(burstAt, C.Ice, 14, 45, 0.6)
	VFX.ScreenTint(burstAt, 60, Color3.fromRGB(205, 228, 255), 0.12, 0.3)
	snd("Burst", burstAt)
	VFX.Tween(mesh, T.Dissolve * 0.6, { Transparency = 1 })
	VFX.Tween(hl, T.Dissolve * 0.6, { FillTransparency = 1, OutlineTransparency = 1 })
	VFX.Tween(light, T.Dissolve, { Brightness = 0 })
	VFX.Step(function(dt, t) gait:Step(dt, 0.6); return t < T.Dissolve end)
	VFX.Cleanup(wolf, 0.9)
end

return Fenrir
