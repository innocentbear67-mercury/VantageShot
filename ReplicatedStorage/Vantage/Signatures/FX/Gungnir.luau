--!nonstrict
--[[
	VANTAGE — Signature 03 GUNGNIR, visuals (client) — v1 2026-11-19
	Odin's spear never misses. Gold motes spiral into the hand, the spear forms tip-first and its runes
	light from the point down the shaft; a four-point glint sits on the tip and a rune ring turns round
	the shaft. On release: one dead-straight white-gold streak, a sonic ring, and every target it
	pierces gets a burst shaped like a single glowing rune. It sticks in the wall, quivers, the runes
	go out tip to butt and it crumbles into gold dust.

	Gungnir.Play{ Hand = function() -> CFrame, Dir = Vector3, Range = 120, BlockAt = number?, Targets = {...}, Hold = 0.5 }  (yields)
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Gungnir = {}
local C = {
	Gold = Color3.fromRGB(255, 205, 96), Pale = Color3.fromRGB(255, 240, 196), White = Color3.new(1, 1, 1), Deep = Color3.fromRGB(255, 150, 40),
}
Gungnir.Colors = C
Gungnir.Tuning = { Hold = 0.95, Speed = 250, Quiver = 0.6, Stay = 2.2, Crumble = 1.0 }

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

local function extent(model, cf)
	-- distance from the pivot to the tip (along LookVector) and the butt
	local mesh = model.PrimaryPart
	local lo, hi = math.huge, -math.huge
	for _, x in { -0.5, 0.5 } do for _, y in { -0.5, 0.5 } do for _, z in { -0.5, 0.5 } do
		local p = mesh.CFrame:PointToWorldSpace(mesh.Size * Vector3.new(x, y, z))
		local d = (p - cf.Position):Dot(cf.LookVector)
		lo = math.min(lo, d); hi = math.max(hi, d)
	end end end
	return hi, lo
end

-- one rune drawn in gold light, facing dir (the rune burst on a pierced target)
local function runeBurst(pos, facing)
	local up = Vector3.yAxis
	local across = facing:Cross(up)
	across = across.Magnitude > 1e-3 and across.Unit or Vector3.xAxis
	local gl = VFX.Glyphs[math.random(1, #VFX.Glyphs)]
	local pts = {}
	for _, st in gl do
		pts[#pts + 1] = pos + across * st[1][1] * 3 + up * st[1][2] * 3
		pts[#pts + 1] = pos + across * st[2][1] * 3 + up * st[2][2] * 3
	end
	local b = VFX.Bolt({ Width = 0.12, Color = C.Gold, Core = C.White, GlowScale = 6, Branches = 0 })
	task.spawn(function()
		VFX.Step(function(_, t)
			b:DrawPoints(pts, 1 - math.clamp((t - 0.25) / 0.3, 0, 1))
			return t < 0.55
		end)
		b:Destroy()
	end)
	VFX.Sprite(pos, { Tex = KB.Impact, Color = C.Gold, Size = { 2, 10 }, Life = 0.22, Bright = 2 })
	VFX.Sprite(pos, { Tex = KB.Star, Color = C.White, Size = { 7, 0 }, Life = 0.25, Bright = 3, Rot = NumberRange.new(0) })
	VFX.Burst(pos, { CF = VFX.Facing(pos, facing), Count = 22, Texture = KB.Sparks, Color = C.Gold, Size = { 1.4, 0 }, Life = { 0.2, 0.45 },
		Speed = { 20, 50 }, Spread = 50, Drag = 3, Light = 1, Brightness = 2, Orientation = Enum.ParticleOrientation.VelocityParallel })
	VFX.Flash(pos, C.Gold, 6, 18, 0.25)
	VFX.Sfx("Clang", pos, 1, 1.3); VFX.Sfx("Zap", pos, 0.6, 0.8)
	VFX.Decal(pos - Vector3.new(0, 2.5, 0), KB.Crack, C.Gold, 2, 5, 2.5, { Bright = 1.2 })
end

function Gungnir.Play(o)
	local T = Gungnir.Tuning
	local dir = o.Dir.Unit
	local range = o.Range or 120
	local stopAt = math.min(range, o.BlockAt or range)
	local spear = Signatures.Assets.SIG_Gungnir:Clone()
	local mesh = spear.PrimaryPart
	mesh.Transparency = 1
	spear.Parent = VFX.Folder()
	local hl = Instance.new("Highlight")
	hl.FillColor = C.Gold; hl.OutlineColor = C.Pale; hl.FillTransparency = 1; hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Parent = spear
	local light = Instance.new("PointLight"); light.Color = C.Gold; light.Brightness = 0; light.Range = 16; light.Shadows = false; light.Parent = mesh

	local tBody = typeof(o.Target) == "Instance" and (o.Target:FindFirstChild("UpperTorso") or o.Target:FindFirstChild("HumanoidRootPart")) or nil
	local function aimFrom(p: Vector3): Vector3
		if tBody and tBody.Parent then
			local v = tBody.Position - p
			if v.Magnitude > 1 then return v.Unit end
		end
		return dir
	end
	local function held()
		local h = o.Hand()
		dir = aimFrom(h.Position)
		return VFX.Facing(h.Position, dir)
	end
	spear:PivotTo(held())
	local tipD, buttD = extent(spear, held())

	-- 1. anticipation: motes spiral in, spear forms tip-first, runes light down the shaft
	local hold = o.Hold or T.Hold
	local ring = VFX.Bolt({ Width = 0.05, Color = C.Gold, GlowScale = 6, Branches = 0 })
	local shaftRunes = VFX.Bolt({ Width = 0.045, Color = C.Pale, GlowScale = 5, Branches = 0 })
	local motesPart = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = held() })
	local motes = VFX.Emitter(motesPart, { Texture = KB.Star, Color = ColorSequence.new(C.Pale, C.Gold), LightEmission = 1, Brightness = 2,
		Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(0.25, 0.4), Speed = NumberRange.new(-14, -9), Rate = 70,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, RotSpeed = NumberRange.new(-200, 200) })
	motesPart.Size = Vector3.one * 7
	local glint = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = held() })
	local glintE = VFX.Emitter(glint, { Texture = KB.Star, Color = ColorSequence.new(C.White, C.Gold), LightEmission = 1, Brightness = 4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(0.5, 3.2), NumberSequenceKeypoint.new(1, 2.2) }),
		Lifetime = NumberRange.new(0.12), Speed = NumberRange.new(0), Rate = 30, LockedToPart = true, Rotation = NumberRange.new(0), RotSpeed = NumberRange.new(90) })
	VFX.Sfx("Charge", held().Position); VFX.Sfx("Choir", held().Position, 0.6, 1.1)
	VFX.Step(function(_, t)
		local cf = held()
		spear:PivotTo(cf)
		local k = math.clamp(t / hold, 0, 1)
		mesh.Transparency = 1 - math.clamp(k * 1.6, 0, 1)
		hl.FillTransparency = 1 - 0.6 * math.clamp(k * 2, 0, 1) + 0.4 * math.clamp((k - 0.6) / 0.4, 0, 1)
		hl.OutlineTransparency = 1 - 0.9 * math.clamp(k * 2, 0, 1)
		light.Brightness = 3 * k
		motesPart.CFrame = cf * CFrame.new(0, 0, -tipD * 0.4)
		glint.CFrame = cf * CFrame.new(0, 0, -tipD)
		-- runes light from the tip down the shaft: a zig-zag rune line growing tip -> butt
		local pts = {}
		local lit = tipD - (tipD - buttD) * k
		local n = 10
		for i = 0, n do
			local d = tipD - (tipD - lit) * (i / n)
			local side = (i % 2 == 0) and 0.12 or -0.12
			pts[#pts + 1] = cf:PointToWorldSpace(Vector3.new(side, 0.16, -d))
		end
		shaftRunes:DrawPoints(pts, k)
		-- rune ring hovering round the shaft, turning
		local rp = {}
		local rc = cf * CFrame.new(0, 0, -tipD * 0.35) * CFrame.Angles(math.pi / 2, 0, 0)
		for i = 0, 24 do
			local a = t * 4 + i / 24 * math.pi * 2
			rp[#rp + 1] = rc:PointToWorldSpace(Vector3.new(math.cos(a) * 0.75, 0, math.sin(a) * 0.75))
		end
		ring:DrawPoints(rp, math.clamp(k * 2, 0, 1))
		return t < hold
	end)
	motes.Enabled = false
	ring:Destroy()

	-- 2. release: straight white-gold streak + sonic ring
	local start = held()
	local from = start.Position
	VFX.Sprite(from + dir * 2, { Tex = KB.WaterRing, Color = C.Pale, Size = { 1, 9 }, Life = 0.15, Dir = dir, Bright = 2 })
	VFX.Sprite(from + dir * 2, { Tex = KB.Ring, Color = C.Gold, Size = { 1, 7 }, Life = 0.18, Dir = dir, Bright = 2 })
	VFX.Sfx("WhooshShort", from, 1.2); VFX.Sfx("Blast", from, 0.8, 1.6); VFX.Shake(from, 30, 0.8, 0.25)
	local streak = VFX.Bolt({ Width = 0.16, Color = C.Gold, Core = C.White, GlowScale = 5, Branches = 0, GlowAlpha = 0.35 })
	local tA = Instance.new("Attachment"); tA.Position = mesh.PivotOffset:PointToWorldSpace(Vector3.new(0, 0.25, -tipD * 0.2)); tA.Parent = mesh
	local tB = Instance.new("Attachment"); tB.Position = mesh.PivotOffset:PointToWorldSpace(Vector3.new(0, -0.25, -tipD * 0.2)); tB.Parent = mesh
	local trail = Instance.new("Trail"); trail.Attachment0 = tA; trail.Attachment1 = tB; trail.FaceCamera = true
	trail.Color = ColorSequence.new(C.White, C.Gold); trail.LightEmission = 1; trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(0.1, 1); trail.Lifetime = 0.25 / math.max(VFX.TimeScale, 0.05); trail.Parent = mesh
	local done = {}
	local d = 0
	local hitWall = o.BlockAt ~= nil and o.BlockAt <= range
	local sp, homed = from, false
	VFX.Step(function(dt, t)
		if tBody then
			if not tBody.Parent then return false end
			dir = aimFrom(sp)
			local gap = (tBody.Position - sp).Magnitude
			if gap <= T.Speed * dt + tipD * 0.8 then
				sp = tBody.Position - dir * tipD * 0.8
				homed = true
			else
				sp += dir * T.Speed * dt
			end
		else
			d = math.min(stopAt - tipD * 0.6, d + T.Speed * dt)
			sp = from + dir * d
		end
		local cf = CFrame.lookAt(sp, sp + dir)
		spear:PivotTo(cf)
		glint.CFrame = cf * CFrame.new(0, 0, -tipD)
		streak:Draw(from, cf.Position + dir * tipD, 1 - math.clamp((t - 0.12) / 0.25, 0, 1))
		local tip = cf.Position + dir * tipD
		for i, tg in o.Targets or {} do
			local p = resolve(tg)
			if p and not done[i] then
				local rel = p - from
				local along = rel:Dot(dir)
				if along <= (tip - from):Dot(dir) and (rel - dir * along).Magnitude < 3.5 then
					done[i] = true
					runeBurst(p, -dir)
				end
			end
		end
		if tBody then return not homed and t < 3 end
		return d < stopAt - tipD * 0.6
	end)
	-- 3. sticks in the wall (or drops at max range), quivers, runes go out tip to butt, crumbles
	streak:Destroy()
	trail.Enabled = false
	local rest = CFrame.lookAt(sp, sp + dir)
	if homed then
		-- the spear runs the target through, a pillar of Asgard light, then it plants itself in the ground at their feet
		local hitAt = sp + dir * tipD
		local down = require(Signatures.SignatureLock).Ray(hitAt, Vector3.new(0, -30, 0))
		local g = if down then down.Position else hitAt - Vector3.new(0, 3, 0)
		VFX.Flash(hitAt, C.Gold, 10, 40, 0.5)
		VFX.Sprite(hitAt, { Tex = KB.Impact, Color = C.Pale, Size = { 4, 18 }, Life = 0.25, Bright = 2.5 })
		VFX.Sprite(hitAt, { Tex = VFX.Tex.Glow, Color = C.Gold, Size = { 8, 22 }, Life = 0.35, Bright = 2, T = { 0.1, 1 } })
		VFX.Burst(hitAt, { CF = CFrame.lookAt(hitAt, hitAt + dir), Count = 26, Texture = KB.Sparks, Color = C.Gold, Size = { 1.3, 0 }, Life = { 0.25, 0.5 },
			Speed = { 25, 60 }, Spread = 50, Drag = 3, Light = 1, Orientation = Enum.ParticleOrientation.VelocityParallel })
		runeBurst(hitAt, -dir)
		VFX.GlowColumn(g, C.Gold, 46, 5, 1.1, 1.6)
		VFX.Decal(g, KB.Ring, C.Gold, 3, 26, 0.5, { Bright = 2 })
		VFX.Decal(g, KB.WaterRing, C.Pale, 2, 20, 0.45, { Bright = 1.6 })
		VFX.Decal(g, KB.Crack, C.Gold, 5, 12, T.Stay + 1, { Bright = 1.4 })
		VFX.Sfx("Boom", hitAt, 0.9, 1.25)
		VFX.Shake(hitAt, 30, 1, 0.3)
		local fl = dir * Vector3.new(1, 0, 1)
		fl = if fl.Magnitude > 1e-3 then fl.Unit else Vector3.zAxis
		local rd = (fl * 0.55 - Vector3.yAxis).Unit
		local plantAt = g - rd * (tipD - 1.4)
		local fromCf = CFrame.lookAt(sp, sp + dir)
		local toCf = CFrame.lookAt(plantAt, plantAt + rd)
		VFX.Step(function(_, t)
			local k = math.clamp(t / 0.12, 0, 1)
			spear:PivotTo(fromCf:Lerp(toCf, k * k))
			return t < 0.12
		end)
		dir = rd
		rest = toCf
	end
	VFX.Sfx("MetalHit", rest.Position, 1.2, 0.9)
	if hitWall then
		local tip = rest.Position + dir * tipD
		VFX.Sprite(tip, { Tex = KB.Crack, Color = C.Gold, Size = { 2, 7 }, Life = 0.8, Dir = -dir, Bright = 1.5 })
		VFX.Burst(tip, { CF = CFrame.lookAt(tip, tip - dir), Count = 18, Texture = KB.Sparks, Color = C.Gold, Size = { 1.2, 0 }, Life = { 0.2, 0.4 },
			Speed = { 15, 40 }, Spread = 60, Drag = 3, Light = 1, Orientation = Enum.ParticleOrientation.VelocityParallel })
		VFX.Burst(tip, { CF = CFrame.lookAt(tip, tip - dir), Count = 6, Texture = KB.SmokeBall, Color = Color3.fromRGB(200, 190, 170), Size = { 1.5, 4 },
			Transparency = { 0.4, 1 }, Life = { 0.4, 0.7 }, Speed = { 4, 10 }, Spread = 60, Light = 0 })
	end
	VFX.Step(function(_, t)
		local w = math.sin(t * 60) * math.rad(4) * math.max(0, 1 - t / T.Quiver)
		spear:PivotTo(rest * CFrame.new(0, 0, -tipD) * CFrame.Angles(w, w * 0.6, 0) * CFrame.new(0, 0, tipD))
		glint.CFrame = rest * CFrame.new(0, 0, -tipD)
		return t < T.Quiver
	end)
	local hum = VFX.Sfx("ElecHum", rest.Position, 0.5, 0.7)
	VFX.Step(function(_, t)
		light.Brightness = 3 + math.sin(t * 8) * 1.2
		local pts = {}
		for i = 0, 10 do
			local dd = tipD - (tipD - buttD) * (i / 10)
			pts[#pts + 1] = rest:PointToWorldSpace(Vector3.new(i % 2 == 0 and 0.12 or -0.12, 0.16, -dd))
		end
		shaftRunes:DrawPoints(pts, 0.75 + math.sin(t * 8) * 0.25)
		return t < T.Stay
	end)
	glintE.Enabled = false
	VFX.Sfx("WhooshLong", rest.Position, 0.5, 0.6)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Crumble, 0, 1)
		local lit = buttD + (tipD - buttD) * (1 - k)
		local pts = {}
		for i = 0, 10 do
			local dd = lit - (lit - buttD) * (i / 10)
			pts[#pts + 1] = rest:PointToWorldSpace(Vector3.new(i % 2 == 0 and 0.12 or -0.12, 0.16, -dd))
		end
		shaftRunes:DrawPoints(pts, 1 - k)
		mesh.Transparency = k
		hl.OutlineTransparency = 0.1 + 0.9 * k
		light.Brightness = 3 * (1 - k)
		return t < T.Crumble
	end)
	shaftRunes:Destroy()
	local mid = rest.Position + dir * (tipD + buttD) * 0.5
	VFX.Burst(mid, { Count = 40, Texture = KB.Star, Color = C.Gold, Size = { 0.6, 0 }, Life = { 0.6, 1.2 }, Speed = { 2, 7 }, Drag = 2,
		Accel = Vector3.new(0, -6, 0), Light = 1, Brightness = 2, Rot = NumberRange.new(0, 45) })
	VFX.Burst(mid, { Count = 8, Texture = KB.Air, Flip = { VFX.G4 }, Color = C.Pale, Size = { 2, 4 }, Transparency = { 0.5, 1 }, Life = { 0.5, 0.8 }, Speed = { 1, 3 }, Light = 0.6 })
	VFX.Cleanup(spear, 0.1); VFX.Cleanup(glint, 0.5); VFX.Cleanup(motesPart, 0.6)
end

return Gungnir
