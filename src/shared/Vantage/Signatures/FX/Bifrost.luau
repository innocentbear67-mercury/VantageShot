--!nonstrict
--[[
	VANTAGE — Signature 09 BIFRÖST, visuals (client) — v1 2026-11-19
	"The burning bridge." A three-band portal ring (red, green, blue) opens at both ends, real flames
	running round the red band, and a light column rises at the destination. A three-band arc links the
	two points, a white flash, and the caster is there. Half a second later the old ring collapses inward
	and bursts into red, green and blue shards with a ring of fire; coloured motes drift at the arrival.

	Bifrost.Play{ From = CFrame, To = Vector3 (ground), Move = function(cf) end }  (yields)
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Bifrost = {}
local C = {
	Red = Color3.fromRGB(255, 70, 50), Green = Color3.fromRGB(70, 255, 120), Blue = Color3.fromRGB(80, 140, 255), White = Color3.new(1, 1, 1),
	Fire = Color3.fromRGB(255, 150, 40), Hot = Color3.fromRGB(255, 220, 140),
}
Bifrost.Colors = C
Bifrost.Tuning = { Open = 0.9, Link = 0.5, Departure = 0.9, Linger = 2.4, RingHeight = 4.6, Radius = 4.8 }
local RAINBOW = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.Red), ColorSequenceKeypoint.new(0.35, C.Fire), ColorSequenceKeypoint.new(0.55, C.Green),
	ColorSequenceKeypoint.new(0.8, C.Blue), ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 100, 255)) })
local FIRE = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.Hot), ColorSequenceKeypoint.new(0.5, C.Fire), ColorSequenceKeypoint.new(1, C.Red) })

-- a three-band portal at cf (cf faces the travel direction). returns { stop = fn, collapse = fn }
local function portal(cf: CFrame, R: number)
	local ring = Signatures.Assets.SIG_BifrostRing:Clone()
	ring:PivotTo(cf)
	ring:ScaleTo(ring:GetScale() * (R * 2 / 8) * 0.85)
	ring.Parent = VFX.Folder()
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = C.White; hl.OutlineTransparency = 0.3
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Parent = ring
	local bands = {
		{ VFX.Bolt({ Width = 0.16, Color = C.Red, Core = C.Hot, GlowScale = 6, Branches = 0 }), 1.08 },
		{ VFX.Bolt({ Width = 0.13, Color = C.Green, GlowScale = 6, Branches = 0 }), 0.96 },
		{ VFX.Bolt({ Width = 0.13, Color = C.Blue, GlowScale = 6, Branches = 0 }), 0.84 },
	}
	local plane = cf * CFrame.Angles(math.pi / 2, 0, 0) -- ring plane = cf's XY plane (normal = LookVector)
	local carrier = VFX.Part({ Transparency = 1, Size = Vector3.new(R * 2.15, R * 2.15, 0.2), CFrame = cf })
	local flames = VFX.Emitter(carrier, { Texture = KB.FireFlip, Color = FIRE, LightEmission = 1, Brightness = 2, Size = NumberSequence.new(1.6, 2.6),
		Transparency = NumberSequence.new(0.15, 1), Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(0.5, 2), Rate = 0,
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, 10, 0), FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot })
	local swirl = VFX.Emitter(carrier, { Texture = KB.Rift, Color = RAINBOW, LightEmission = 1, Brightness = 2, Size = NumberSequence.new(R * 1.7, R * 2),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5), Rate = 0, Speed = NumberRange.new(0.001), LockedToPart = true, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Front, RotSpeed = NumberRange.new(120, 180), Rotation = NumberRange.new(0, 360), FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop })
	local light = Instance.new("PointLight"); light.Color = C.Fire; light.Brightness = 4; light.Range = 18; light.Shadows = false; light.Parent = carrier
	local alive, scale, t0 = true, 1, os.clock()
	task.spawn(function()
		VFX.Step(function(_, t)
			local open = math.clamp(t / 0.25, 0, 1)
			for i, b in bands do
				b[1]:DrawPoints(VFX.RingPts(plane, R * b[2] * scale * open, 48, t * (i % 2 == 0 and -2 or 2.4), 1, 0), alive and 1 or 0)
			end
			flames.Rate = alive and 90 * scale or 0; swirl.Rate = alive and 8 or 0
			return alive
		end)
		for _, b in bands do b[1]:Destroy() end
		flames.Enabled = false; swirl.Enabled = false
		VFX.Cleanup(carrier, 1)
	end)
	local api = {}
	function api.collapse()
		VFX.Step(function(_, t)
			local k = math.clamp(t / 0.18, 0, 1)
			scale = 1 - k * 0.9
			if ring.Parent then ring:ScaleTo(math.max(0.05, ring:GetScale() * (1 - k * 0.25))) end
			return t < 0.18
		end)
		alive = false
		ring:Destroy()
		light.Brightness = 0
		local p = cf.Position
		for _, col in { C.Red, C.Green, C.Blue } do
			VFX.Burst(p, { Count = 18, Texture = KB.IceDebris, Color = col, Size = { 1.2, 1.5 }, Life = { 0.5, 0.9 }, Speed = { 20, 45 }, Drag = 1.5,
				Accel = Vector3.new(0, -40, 0), Light = 1, Brightness = 2, Flip = { VFX.G4 } })
			VFX.Burst(p, { Count = 16, Texture = KB.Star, Color = col, Size = { 1, 0 }, Life = { 0.3, 0.6 }, Speed = { 25, 50 }, Drag = 3, Light = 1, Brightness = 2.5 })
		end
		VFX.Sprite(p, { Tex = KB.Ring, Color = C.Fire, Size = { R, R * 6 }, Life = 0.35, Dir = cf.LookVector, Bright = 2 })
		VFX.Sprite(p, { Tex = KB.WaterRing, Color = C.Red, Size = { R, R * 5 }, Life = 0.4, Dir = cf.LookVector, Bright = 2 })
		VFX.Sprite(p, { Tex = KB.Impact, Color = C.White, Size = { 3, 14 }, Life = 0.2, Bright = 2 })
	end
	function api.close()
		alive = false
		VFX.Tween(light, 0.3, { Brightness = 0 })
		if ring.Parent then
			task.spawn(function()
				VFX.Step(function(_, t) if ring.Parent then ring:ScaleTo(math.max(0.05, ring:GetScale() * 0.9)) end; return t < 0.3 end)
				ring:Destroy()
			end)
		end
	end
	return api
end

-- 2026-11-20: anyone standing where the bridge lands is struck by a pillar of the rainbow
function Bifrost.HitAt(_from: Vector3, target: BasePart, _kind: string?)
	local pos = target.Position
	local feet = pos - Vector3.new(0, 2.8, 0)
	for i, col in { C.Red, C.Green, C.Blue } do
		VFX.GlowColumn(feet + Vector3.new(math.cos(i * 2.1) * 0.8, 0, math.sin(i * 2.1) * 0.8), col, 30, 3.2, 0.7, 1.6)
	end
	VFX.Sprite(pos, { Tex = KB.Impact, Color = C.White, Size = { 3, 14 }, Life = 0.22, Bright = 2.2 })
	VFX.Burst(pos, { Count = 30, Texture = KB.Star, Color = C.White, Size = { 0.9, 0 }, Life = { 0.4, 0.8 }, Speed = { 15, 40 }, Drag = 3, Light = 1, Brightness = 2 })
	VFX.Burst(pos, { Count = 12, Texture = KB.Sparks, Color = C.Hot, Size = { 1, 0 }, Life = { 0.25, 0.5 }, Speed = { 20, 45 }, Drag = 3, Light = 1,
		Orientation = Enum.ParticleOrientation.VelocityParallel })
	VFX.Decal(feet, KB.Ring, C.White, 2, 14, 0.4, { Bright = 2 })
end

function Bifrost.Play(o)
	local T = Bifrost.Tuning
	local move = o.Move or function() end
	local fromP = o.From.Position
	local to = o.To
	local flat = (to - fromP) * Vector3.new(1, 0, 1)
	local dir = flat.Magnitude > 1e-3 and flat.Unit or o.From.LookVector
	local aCf = CFrame.lookAt(fromP + dir * 2.5 + Vector3.new(0, T.RingHeight - 3, 0), fromP + dir * 3.5 + Vector3.new(0, T.RingHeight - 3, 0))
	local bCf = CFrame.lookAt(to + Vector3.new(0, T.RingHeight, 0), to + Vector3.new(0, T.RingHeight, 0) + dir)

	-- 1. both portals open; light column at the destination
	local A = portal(aCf, T.Radius)
	local B = portal(bCf, T.Radius)
	VFX.GlowColumn(to, C.White, 30, 6, T.Open + 0.5, 1.3)
	VFX.Decal(to, KB.WaterRing, C.Fire, 2, 14, T.Open + 0.3, { Bright = 1.5 })
	VFX.Sfx("Portal", fromP, 1.2); VFX.Sfx("Charge", fromP, 0.8, 1.1); VFX.Sfx("Portal2", to, 1, 0.9); VFX.Sfx("Burning", fromP, 0.7, 1.2)
	VFX.Wait(T.Open)

	-- 2. the three-band arc links them; white flash; the caster is there
	local p0, p1 = aCf.Position, bCf.Position
	local dist = (p1 - p0).Magnitude
	local h = math.clamp(dist * 0.22, 4, 20)
	local arcs = {
		{ VFX.Bolt({ Width = 0.3, Color = C.Red, Core = C.Hot, GlowScale = 5, Branches = 0 }), 0.9 },
		{ VFX.Bolt({ Width = 0.26, Color = C.Green, GlowScale = 5, Branches = 0 }), 0 },
		{ VFX.Bolt({ Width = 0.26, Color = C.Blue, GlowScale = 5, Branches = 0 }), -0.9 },
	}
	VFX.Sprite(p0, { Tex = KB.Impact, Color = C.White, Size = { 3, 16 }, Life = 0.2, Bright = 2.5 })
	VFX.Flash(p0, C.White, 10, 30, 0.3)
	VFX.Sfx("WhooshLong", p0, 1.2, 1.1); VFX.Sfx("ThunderCrack", p1, 0.6, 1.4)
	task.spawn(function()
		VFX.Step(function(_, t)
			local grow = math.clamp(t / 0.12, 0, 1)
			local fade = 1 - math.clamp((t - 0.12) / (T.Link - 0.12), 0, 1)
			for _, a in arcs do
				local pts = {}
				for i = 0, 24 do
					local u = i / 24 * grow
					pts[#pts + 1] = p0:Lerp(p1, u) + Vector3.new(0, math.sin(u * math.pi) * h + a[2], 0)
				end
				a[1]:DrawPoints(pts, fade)
			end
			return t < T.Link
		end)
		for _, a in arcs do a[1]:Destroy() end
	end)
	VFX.Wait(0.08)
	move(CFrame.lookAt(to + Vector3.new(0, 3, 0), to + Vector3.new(0, 3, 0) + dir))
	VFX.Sprite(p1, { Tex = KB.Impact, Color = C.White, Size = { 4, 18 }, Life = 0.22, Bright = 2.5 })
	VFX.Sprite(p1, { Tex = VFX.Tex.Glow, Color = C.White, Size = { 10, 24 }, Life = 0.3, Bright = 2, T = { 0.1, 1 } })
	VFX.Decal(to, KB.Ring, C.White, 3, 18, 0.35, { Bright = 2 })
	VFX.Flash(p1, C.White, 10, 34, 0.35)
	VFX.Sfx("Blast", p1, 0.9, 1.3);
	VFX.Sfx("Choir", p1, 0.5, 1.3)
	VFX.ScreenTint(p1, 30, Color3.fromRGB(255, 250, 240), 0.25, 0.25)
	local motesP = VFX.Part({ Transparency = 1, Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(to + Vector3.new(0, 3, 0)) })
	local motes = VFX.Emitter(motesP, { Texture = KB.Star, Color = RAINBOW, LightEmission = 1, Brightness = 2.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180), Rate = 50, Shape = Enum.ParticleEmitterShape.Box,
		Acceleration = Vector3.new(0, 2, 0) })
	B.close()

	-- 3. departure burst half a second later
	VFX.Wait(T.Departure)
	A.collapse()
	VFX.Sfx("IceShatter2", p0, 1, 1.3); VFX.Sfx("Boom", p0, 0.7, 1.1)
	-- 4. motes linger at the arrival
	VFX.Wait(math.max(0, T.Linger - T.Departure))
	motes.Enabled = false
	VFX.Cleanup(motesP, 1.2)
end

return Bifrost
