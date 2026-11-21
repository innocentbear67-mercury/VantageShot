--!nonstrict
--[[
	VANTAGE — Signature 08 SLEIPNIR, visuals (client) — v1 2026-11-19
	"Eight legs for speed." Storm-grey mist gathers and Odin's horse forms out of it, silver outline
	first. The rider charges: every hoof strike drops a blue spark and a glowing print, the legs leave
	short after-images so the eight blur into a wheel of motion, and silver speed streaks rush past.
	Hits ring silver with a dust burst. At the end the rider drops off and the horse runs on as mist.

	Sleipnir.Play{ Start = CFrame, Path = { Vector3 }, Speed = 70, Move = function(cf) end, Targets = {...} }  (yields)
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local Gait = require(Signatures.CreatureGait)
local KB = VFX.KB
local Sleipnir = {}
local C = {
	Silver = Color3.fromRGB(225, 232, 245), Storm = Color3.fromRGB(120, 130, 150), Blue = Color3.fromRGB(110, 180, 255), Dust = Color3.fromRGB(190, 180, 165),
}
Sleipnir.Colors = C
Sleipnir.Tuning = { Form = 0.7, Speed = 56, Seat = 6.3, HitRadius = 7, RunOn = 20, RunOnTime = 1.2, Length = 22 }

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

function Sleipnir.HitAt(pos, fwd)
	VFX.Sprite(pos + Vector3.new(0, 2.5, 0), { Tex = KB.WaterRing, Color = C.Silver, Size = { 2, 14 }, Life = 0.3, Dir = fwd, Bright = 2 })
	VFX.Sprite(pos + Vector3.new(0, 2.5, 0), { Tex = KB.Impact, Color = C.Silver, Size = { 3, 11 }, Life = 0.2, Bright = 2 })
	VFX.Sfx("Hit", pos, 1, 1.2); VFX.Sfx("WhooshShort", pos)
	VFX.Burst(pos, { CF = VFX.Facing(pos, Vector3.yAxis), Count = 10, Texture = KB.SmokeBall, Color = C.Dust, Size = { 3, 7 }, Transparency = { 0.4, 1 },
		Life = { 0.6, 1 }, Speed = { 8, 18 }, Spread = 80, Drag = 3, Light = 0 })
end

function Sleipnir.Play(o)
	local T = Sleipnir.Tuning
	local path = o.Path
	local move = o.Move or function() end
	local speed = o.Speed or T.Speed
	local first = path[1]
	local dir0 = ((path[2] or first + o.Start.LookVector) - first) * Vector3.new(1, 0, 1)
	dir0 = dir0.Magnitude > 1e-3 and dir0.Unit or o.Start.LookVector

	local horse = Signatures.Assets.SIG_Sleipnir:Clone()
	horse:ScaleTo(horse:GetScale() * (T.Length / (horse:GetAttribute("Length") or 12)))
	local mesh = horse.PrimaryPart
	mesh.Transparency = 1
	horse.Parent = VFX.Folder()
	local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(150, 190, 255); hl.OutlineColor = Color3.fromRGB(235, 242, 255); hl.FillTransparency = 1; hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = horse
	local gait = Gait.new(horse, Gait.Presets.Sleipnir)
	local function place(pos, h)
		local hh = h * Vector3.new(1, 0, 1)
		hh = hh.Magnitude > 1e-3 and hh.Unit or dir0
		horse:PivotTo(VFX.Facing(pos, hh))
		return VFX.Facing(pos, hh)
	end
	local seat = T.Seat * (T.Length / 12)

	-- after-image ribbons on every lower leg bone (parent -> bone)
	local trails = {}
	for _, b in horse:GetDescendants() do
		if b:IsA("Bone") and b.Name:find("^Leg_") and not b:FindFirstChildWhichIsA("Bone") and b.Parent:IsA("Bone") then
			local tr = Instance.new("Trail")
			tr.Attachment0 = b.Parent; tr.Attachment1 = b; tr.FaceCamera = true
			tr.Color = ColorSequence.new(C.Silver, C.Blue); tr.LightEmission = 0.7; tr.LightInfluence = 0
			tr.Transparency = NumberSequence.new(0.45, 1); tr.Lifetime = 0.12 / math.max(VFX.TimeScale, 0.05); tr.Enabled = false; tr.Parent = mesh
			trails[#trails + 1] = tr
		end
	end
	local mist = VFX.Emitter(mesh, { Texture = KB.Air, Color = ColorSequence.new(C.Storm), LightEmission = 0.3, Size = NumberSequence.new(3, 6),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Shape = Enum.ParticleEmitterShape.Box })
	local streaks = VFX.Emitter(mesh, { Texture = VFX.Tex.Spark, Color = ColorSequence.new(C.Silver), LightEmission = 1, Brightness = 2,
		Size = NumberSequence.new(0.35, 0), Squash = NumberSequence.new(-3), Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(50, 80), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Back,
		Shape = Enum.ParticleEmitterShape.Box })
	local light = Instance.new("PointLight"); light.Color = C.Blue; light.Brightness = 0; light.Range = 36; light.Shadows = false; light.Parent = mesh
	-- glowing eyes, spirit fire on the mane and tail
	local function B(n) return horse:FindFirstChild(n, true) end
	local spirit = {}
	for _, n in { "Head" } do
		local b = B(n)
		if b then
			spirit[#spirit + 1] = VFX.Emitter(b, { Texture = KB.Star, Color = ColorSequence.new(Color3.fromRGB(150, 220, 255)), LightEmission = 1, Brightness = 4,
				Size = NumberSequence.new(1.1, 0.6), Lifetime = NumberRange.new(0.06, 0.1), Speed = NumberRange.new(0), Rate = 0, LockedToPart = true, Rotation = NumberRange.new(0, 45) })
		end
	end
	for _, n in { "Neck0", "Neck1", "Forelock", "Back0", "Tail0", "Tail1", "Tail2" } do
		local b = B(n)
		if b then
			spirit[#spirit + 1] = VFX.Emitter(b, { Texture = KB.BlueFire, Color = ColorSequence.new(Color3.fromRGB(170, 220, 255), Color3.fromRGB(60, 110, 255)), LightEmission = 1, Brightness = 1.6,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 2.6) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(25, 25), Rate = 0, EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 10, 0), FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot })
		end
	end
	local function spiritOn(on) for k, e in spirit do e.Rate = on and (k == 1 and 30 or 22) or 0 end end

	-- 1. mist gathers, the horse forms (outline first)
	local gatherP = VFX.Part({ Transparency = 1, Size = Vector3.new(10, 6, 10), CFrame = CFrame.new(first + Vector3.new(0, 3, 0)) })
	local gather = VFX.Emitter(gatherP, { Texture = KB.Air, Color = ColorSequence.new(C.Storm, C.Silver), LightEmission = 0.4, Size = NumberSequence.new(5, 2),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.3), Speed = NumberRange.new(-16, -10), Rate = 90, Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot })
	VFX.Sfx("WhooshLong", first, 0.9, 0.7); VFX.Sfx("Ghost", first, 0.6, 0.9)
	VFX.Step(function(dt, t)
		local k = math.clamp(t / T.Form, 0, 1)
		local cf = place(first, dir0)
		move(cf + Vector3.new(0, seat, 0))
		hl.OutlineTransparency = 1 - k
		hl.FillTransparency = 1 - 0.3 * math.clamp((k - 0.4) / 0.6, 0, 1)
		mesh.Transparency = 1 - math.clamp((k - 0.3) / 0.7, 0, 1)
		if k > 0.5 then spiritOn(true) end
		light.Brightness = 7 * k
		gait:Step(dt, 0.3)
		return t < T.Form
	end)
	gather.Enabled = false
	VFX.Decal(first, KB.Shock, C.Silver, 3, 16, 0.45)
	VFX.Sfx("Neigh", first, 1.2)
	local stopGallop = VFX.SfxLoop("Gallop", mesh, 1.2, 1.05)

	-- 2. charge along the path
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
	for _, tr in trails do tr.Enabled = true end
	mist.Rate = 12; streaks.Rate = 60
	local done = {}
	local d, nextStep, side = 0, 0, 1
	local chaseRoot = typeof(o.Chase) == "Instance" and o.Chase:FindFirstChild("HumanoidRootPart") or nil
	local chaseHum = typeof(o.Chase) == "Instance" and o.Chase:FindFirstChildOfClass("Humanoid") or nil
	local chaseUntil = total / speed + (o.ChaseTime or 3)
	VFX.Step(function(dt, t)
		d += speed * dt
		if chaseRoot and chaseRoot.Parent and chaseHum and chaseHum.Health > 0 and t < chaseUntil and d >= total then
			local last = path[#path]
			local q = chaseRoot.Position - Vector3.new(0, 3, 0)
			if (Vector3.new(q.X, 0, q.Z) - Vector3.new(last.X, 0, last.Z)).Magnitude > 1 then
				local l = (q - last).Magnitude
				segs[#segs + 1] = { a = last, b = q, l = l, s = total }
				total += l
				path[#path + 1] = q
			end
		end
		local pos, tan = at(d)
		local cf = place(pos, tan)
		move(cf + Vector3.new(0, seat + math.abs(math.sin(t * 20)) * 0.4, 0))
		gait:Step(dt, 1.2)
		if t >= nextStep then
			nextStep = t + 0.07
			side = -side
			local p = pos + cf.RightVector * side * 1.1 + cf.LookVector * (math.random() * 3 - 1)
			VFX.Decal(p, KB.Impact, C.Blue, 1.3, 1.6, 1.3, { Bright = 1.6, T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) }) })
			VFX.Burst(p + Vector3.new(0, 0.3, 0), { CF = VFX.Facing(p, Vector3.yAxis), Count = 4, Texture = KB.Star, Color = C.Blue, Size = { 0.9, 0 }, Life = { 0.15, 0.3 },
				Speed = { 6, 14 }, Spread = 60, Drag = 2, Light = 1, Brightness = 2 })
		end
		for i, tg in o.Targets or {} do
			local p = resolve(tg)
			if p and not done[i] and (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= T.HitRadius then
				done[i] = true
				Sleipnir.HitAt(p - Vector3.new(0, 2.5, 0), cf.LookVector)
			end
		end
		if chaseRoot and chaseRoot.Parent and (Vector3.new(chaseRoot.Position.X, 0, chaseRoot.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= T.HitRadius then
			return false -- rode them down
		end
		return d < total
	end)

	-- 3. rider drops off; the horse runs on as mist and thins out
	local endPos, endTan = at(total)
	local endCf = CFrame.lookAt(endPos, endPos + endTan * Vector3.new(1, 0, 1))
	move(endCf + Vector3.new(0, 3, 0))
	streaks.Rate = 0; mist.Rate = 80
	stopGallop(T.RunOnTime)
	VFX.Sfx("Neigh", endPos, 0.7, 1.1)
	VFX.Step(function(dt, t)
		local k = math.clamp(t / T.RunOnTime, 0, 1)
		place(endPos + endCf.LookVector * T.RunOn * k, endCf.LookVector)
		gait:Step(dt, 1.1 - 0.5 * k)
		mesh.Transparency = k
		hl.FillTransparency = 0.7 + 0.3 * k; hl.OutlineTransparency = k
		light.Brightness = 7 * (1 - k)
		if k > 0.6 then spiritOn(false) end
		return t < T.RunOnTime
	end)
	mist.Enabled = false
	for _, tr in trails do tr.Enabled = false end
	VFX.Cleanup(horse, 0.9); VFX.Cleanup(gatherP, 0.6)
end

return Sleipnir
