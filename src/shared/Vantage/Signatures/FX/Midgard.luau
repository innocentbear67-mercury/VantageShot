--!nonstrict
--[[
	VANTAGE — Signature 04 MIDGARD (Jörmungandr), visuals (client) — v1 2026-11-19
	A teal rune ring burns into the ground, cracks glow and stones hop; then the World Serpent breaches
	out of the earth like a whale, dragging sea spray with it (white water sheets, mist, drops falling
	back, flying rock), arcs over the lane and dives back in with a second splash, venom dripping off
	its jaws. Teal cracks fade from the broken ground over 4 s.

	Midgard.Play{ Origin = CFrame, At = Vector3 (breach point on the ground), Targets = {...} }  (yields)
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Midgard = {}
local C = {
	Teal = Color3.fromRGB(64, 236, 210), Deep = Color3.fromRGB(14, 120, 120), Foam = Color3.fromRGB(235, 250, 255),
	Water = Color3.fromRGB(150, 215, 240), Rock = Color3.fromRGB(96, 92, 88), Venom = Color3.fromRGB(150, 255, 70),
}
Midgard.Colors = C
Midgard.Tuning = { Windup = 1.3, Speed = 58, Height = 38, Reach = 34, Segments = 5, Spacing = 15.2, HitRadius = 11, Linger = 4.5, Scale = 1.6 }

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

local function bezier(a, b, c, t) return a:Lerp(b, t):Lerp(b:Lerp(c, t), t) end

local function splash(pos, scale, up)
	up = up or Vector3.yAxis
	local cf = VFX.Facing(pos, up)
	VFX.Burst(pos, { CF = cf, Count = math.floor(14 * scale), Texture = KB.Splash, Color = C.Foam, Size = NumberSequence.new(4 * scale, 7 * scale),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Life = { 0.5, 0.9 }, Speed = { 25 * scale, 50 * scale }, Spread = 35, Drag = 1.5, Accel = Vector3.new(0, -70, 0), Light = 0.3, Brightness = 1.5 })
	VFX.Burst(pos, { CF = cf, Count = math.floor(40 * scale), Texture = VFX.Tex.Spark, Color = C.Water, Size = NumberSequence.new(0.5 * scale, 0.2),
		Life = { 0.7, 1.2 }, Speed = { 25 * scale, 60 * scale }, Spread = 45, Drag = 0.5, Accel = Vector3.new(0, -90, 0), Light = 0.6,
		Squash = NumberSequence.new(-1.2), Orientation = Enum.ParticleOrientation.VelocityParallel })
	VFX.Burst(pos, { CF = cf, Count = math.floor(10 * scale), Texture = KB.SmokeBall, Color = C.Foam, Size = NumberSequence.new(6 * scale, 14 * scale),
		Transparency = NumberSequence.new(0.45, 1), Life = { 0.9, 1.5 }, Speed = { 6, 16 }, Spread = 80, Drag = 2, Light = 0.2 })
	VFX.Burst(pos, { CF = cf, Count = math.floor(12 * scale), Texture = KB.IceDebris, Color = C.Rock, Size = NumberSequence.new(1.6 * scale, 2 * scale),
		Life = { 0.8, 1.3 }, Speed = { 20 * scale, 45 * scale }, Spread = 55, Drag = 0.5, Accel = Vector3.new(0, -80, 0), Light = 0, Flip = { VFX.G4 } })
	VFX.Decal(pos, KB.WaterRing, C.Foam, 3 * scale, 26 * scale, 0.5, { Bright = 1.2 })
	VFX.Decal(pos, KB.Shock, C.Teal, 4 * scale, 22 * scale, 0.4, { Bright = 1.2 })
	VFX.Shake(pos, 70, 1.4 * scale, 0.45)
end

function Midgard.HitAt(pos)
	VFX.Sprite(pos + Vector3.new(0, 2.5, 0), { Tex = KB.Impact, Color = C.Teal, Size = { 3, 13 }, Life = 0.22, Bright = 2 })
	VFX.Burst(pos + Vector3.new(0, 2, 0), { Count = 14, Texture = KB.Splash, Color = C.Foam, Size = { 2, 4 }, Life = { 0.4, 0.7 }, Speed = { 15, 30 },
		Spread = 60, Accel = Vector3.new(0, -60, 0), Light = 0.3, CF = VFX.Facing(pos, Vector3.yAxis) })
end

function Midgard.Play(o)
	local T = Midgard.Tuning
	local at = o.At
	local fwd = (at - o.Origin.Position) * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or o.Origin.LookVector
	local up = Vector3.yAxis

	-- 1. anticipation: a teal lock ring follows the marked enemy, the ground trembles round them
	local tRoot = typeof(o.Target) == "Instance" and o.Target:FindFirstChild("HumanoidRootPart") or nil
	local marker = VFX.Marker(C.Teal, 6.5)
	task.spawn(function()
		VFX.Step(function(_, t)
			if tRoot and tRoot.Parent then
				local rp = tRoot.Position
				at = Vector3.new(rp.X, at.Y, rp.Z)
			end
			marker:Draw(at, t, math.clamp(t / 0.15, 0, 1))
			return t < T.Windup
		end)
		marker:Destroy()
	end)
	task.spawn(function()
		local n = 0
		VFX.Step(function(_, t)
			if t >= n * 0.12 then
				n += 1
				local p = at + Vector3.new(math.random(-6, 6), 0.3, math.random(-6, 6))
				VFX.Burst(p, { CF = VFX.Facing(p, up), Count = 3, Texture = KB.IceDebris, Color = C.Rock, Size = { 0.9, 1.1 }, Life = { 0.35, 0.5 },
					Speed = { 8, 14 }, Spread = 15, Drag = 0, Accel = Vector3.new(0, -60, 0), Light = 0, Flip = { VFX.G4 } })
			end
			return t < T.Windup
		end)
	end)
	VFX.Shake(at, 60, 0.45, T.Windup)
	VFX.Sfx("Rumble", at, 1.2); VFX.Sfx("Charge", at, 0.6, 0.7)
	VFX.Wait(T.Windup)
	fwd = (at - o.Origin.Position) * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or o.Origin.LookVector
	VFX.RuneCircle(CFrame.new(at), 7.5, 1.4, { Main = C.Teal, Deep = C.Deep, Mist = C.Water }, { Points = 5 })
	VFX.Decal(at, KB.Crack, C.Teal, 4, 20, 4.5, { Bright = 1.6, T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) }) })

	-- 2. the serpent: head + segments + tail on one arc (breach -> apex -> dive)
	local A = at - fwd * 3 - up * 10 * T.Scale
	local Bc = at + fwd * (T.Reach * 0.5) + up * (T.Height * 2)
	local Cc = at + fwd * (T.Reach + 3) - up * 10 * T.Scale
	local pts, cum = {}, { 0 }
	for i = 0, 60 do pts[#pts + 1] = bezier(A, Bc, Cc, i / 60) end
	local tailDir = (pts[#pts] - pts[#pts - 1]).Unit
	local chain = (7.6 + 16.5) * T.Scale + T.Segments * T.Spacing
	for i = 1, 20 do pts[#pts + 1] = pts[61] + tailDir * (chain * i / 20) end
	for i = 2, #pts do cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude end
	local total = cum[#cum]
	local function at_(d)
		if d <= 0 then return pts[1] + (pts[1] - pts[2]).Unit * -d, (pts[2] - pts[1]).Unit end
		for i = 2, #pts do
			if cum[i] >= d then
				local k = (d - cum[i - 1]) / (cum[i] - cum[i - 1])
				return pts[i - 1]:Lerp(pts[i], k), (pts[i] - pts[i - 1]).Unit
			end
		end
		return pts[#pts], tailDir
	end
	-- the ground crossings (breach and re-entry)
	local breachD, diveD
	for i = 2, #pts do
		if not breachD and pts[i].Y >= at.Y and pts[i - 1].Y < at.Y then breachD = cum[i] end
		if breachD and not diveD and pts[i].Y < at.Y and pts[i - 1].Y >= at.Y then diveD = cum[i] end
	end
	breachD = breachD or 10; diveD = diveD or total * 0.6
	local diveAt = (select(1, at_(diveD))) * Vector3.new(1, 0, 1) + Vector3.new(0, at.Y, 0)

	local body = Instance.new("Model"); body.Name = "Jormungandr"
	local A_ = Signatures.Assets
	local head = A_.SIG_Jormungandr_Head:Clone(); head.Parent = body
	local segs = {}
	for i = 1, T.Segments do segs[i] = A_.SIG_Jormungandr_Segment:Clone(); segs[i].Parent = body end
	local tail = A_.SIG_Jormungandr_Tail:Clone(); tail.Parent = body
	head:ScaleTo(T.Scale); tail:ScaleTo(T.Scale)
	for _, s in segs do s:ScaleTo(T.Scale) end
	body.Parent = VFX.Folder()
	local hl = Instance.new("Highlight")
	hl.FillColor = C.Teal; hl.FillTransparency = 0.72; hl.OutlineColor = Color3.fromRGB(190, 255, 240); hl.OutlineTransparency = 0; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = body
	-- teal rune glow along the back + venom from the jaws
	local glowE = {}
	for _, s in segs do
		glowE[#glowE + 1] = VFX.Emitter(s.PrimaryPart, { Texture = KB.Arc2, Color = ColorSequence.new(C.Teal), LightEmission = 1, Brightness = 2,
			Size = NumberSequence.new(3, 4), Lifetime = NumberRange.new(0.1, 0.18), Rate = 10, Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360),
			FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, LockedToPart = true })
		glowE[#glowE + 1] = VFX.Emitter(s.PrimaryPart, { Texture = VFX.Tex.Spark, Color = ColorSequence.new(C.Water), LightEmission = 0.5,
			Size = NumberSequence.new(0.35, 0.1), Lifetime = NumberRange.new(0.4, 0.7), Rate = 25, Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -60, 0), Squash = NumberSequence.new(-1), Orientation = Enum.ParticleOrientation.VelocityParallel })
	end
	local venom = VFX.Emitter(head.PrimaryPart, { Texture = VFX.Tex.Spark, Color = ColorSequence.new(C.Venom), LightEmission = 0.8, Brightness = 2,
		Size = NumberSequence.new(0.45, 0.2), Lifetime = NumberRange.new(0.5, 0.8), Rate = 30, Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -50, 0), Squash = NumberSequence.new(-1.5), Orientation = Enum.ParticleOrientation.VelocityParallel, EmissionDirection = Enum.NormalId.Bottom })
	local light = Instance.new("PointLight"); light.Color = C.Teal; light.Brightness = 7; light.Range = 40; light.Shadows = false; light.Parent = head.PrimaryPart

	-- spray column that keeps going while the body passes through the breach
	local spout = VFX.Part({ Transparency = 1, Size = Vector3.new(4, 0.2, 4), CFrame = CFrame.new(at) })
	local spoutE = VFX.Emitter(spout, { Texture = KB.Splash, Color = ColorSequence.new(C.Foam), LightEmission = 0.3, Brightness = 1.5,
		Size = NumberSequence.new(3, 6), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(20, 40), SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, -70, 0),
		Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top })
	local diveSpout = VFX.Part({ Transparency = 1, Size = Vector3.new(4, 0.2, 4), CFrame = CFrame.new(diveAt) })
	local diveE = VFX.Emitter(diveSpout, { Texture = KB.Splash, Color = ColorSequence.new(C.Foam), LightEmission = 0.3, Brightness = 1.5,
		Size = NumberSequence.new(2, 4), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, -70, 0),
		Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top })

	local done, broke, dove = {}, false, false
	local d = 0
	VFX.Step(function(dt, t)
		local hp0 = at_(d)
		local apexK = math.clamp((hp0.Y - at.Y) / (T.Height * 0.55), 0, 1)
		d += T.Speed * dt * (1 - 0.45 * apexK)
		local hp, ht = at_(d)
		head:PivotTo(VFX.Facing(hp, ht))
		local back = d - 6 * T.Scale
		for _, s in segs do
			local p, tg = at_(back)
			s:PivotTo(VFX.Facing(p, tg))
			back -= T.Spacing
		end
		local tp, tt = at_(back + T.Spacing * 0.45)
		tail:PivotTo(VFX.Facing(tp, tt))
		if not broke and d >= breachD then
			broke = true
			splash(at, 1.2)
			VFX.Flash(at + up * 3, C.Teal, 6, 30, 0.4)
			VFX.Sfx("Splash", at, 1.4); VFX.Sfx("Roar", at, 1.3); VFX.Sfx("Boom", at, 0.7, 0.8)
			for i, tg in o.Targets or {} do
				local p = resolve(tg)
				if p and (p * Vector3.new(1, 0, 1) - at * Vector3.new(1, 0, 1)).Magnitude <= T.HitRadius then done[i] = true; Midgard.HitAt(p - Vector3.new(0, 2.5, 0)) end
			end
		end
		spoutE.Rate = (broke and back < breachD) and 70 or 0
		if not dove and d >= diveD then
			dove = true
			splash(diveAt, 0.75)
			VFX.Sfx("Dive", diveAt, 1.3); VFX.Sfx("Roar2", diveAt, 0.8, 0.8)
			VFX.Decal(diveAt, KB.Crack, C.Teal, 4, 14, 4.5, { Bright = 1.4 })
		end
		diveE.Rate = (dove and back < diveD) and 50 or 0
		-- anything under the arc gets clipped by the body
		for i, tg in o.Targets or {} do
			local p = resolve(tg)
			if p and not done[i] and (p - hp).Magnitude < 7 then done[i] = true; Midgard.HitAt(p - Vector3.new(0, 2.5, 0)) end
		end
		return back + T.Spacing * 0.45 - 16.5 * T.Scale < total and d < total + 4
	end)
	spoutE.Enabled = false; diveE.Enabled = false; venom.Enabled = false
	for _, p in { at, diveAt } do
		VFX.Decal(p, KB.SmokeBall, C.Deep, 10, 13, T.Linger, { Light = 0, Bright = 1, T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.8, 0.5), NumberSequenceKeypoint.new(1, 1) }) })
		VFX.Burst(p + Vector3.new(0, 1, 0), { Count = 8, Texture = KB.Air, Color = C.Water, Size = { 6, 12 }, Transparency = { 0.55, 1 }, Life = { 2.5, 3.5 },
			Speed = { 1, 3 }, Drag = 1, Light = 0.3, Flip = { VFX.G4 } })
	end
	for _, e in glowE do e.Enabled = false end
	VFX.Cleanup(body, 0.05); VFX.Cleanup(spout, 1.2); VFX.Cleanup(diveSpout, 1.2)
end

return Midgard
