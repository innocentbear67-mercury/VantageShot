--!nonstrict
--[[
	VANTAGE — Signature 10 YGGDRASIL, visuals (client) — v1 2026-11-19
	"Dew and white clay." An emerald rune circle spreads from the caster's hand, the ground trembles and
	cracks; the World Tree's roots burst up through the dirt with gold sap glowing in the cracks and pale
	white mist (the white clay) rolling round their base. While they stand, golden dew drips from them and
	leaves drift; allies inside get an emerald shield shimmer. When shot they throw bark chips and gold
	sap sparks. At the end the roots grey, crack and crumble into dust with a last fall of leaves.

	Yggdrasil.Play{ Origin = CFrame, At = Vector3, Duration = 4, Allies = { Model } }  (yields)
	Yggdrasil.Shot(pos, normal)   -- bark chips + sap sparks where a root is hit
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Yggdrasil = {}
local C = {
	Emerald = Color3.fromRGB(47, 224, 122), Deep = Color3.fromRGB(10, 120, 60), Gold = Color3.fromRGB(255, 205, 80), Clay = Color3.fromRGB(240, 238, 228),
	Dirt = Color3.fromRGB(96, 74, 52), Leaf = Color3.fromRGB(110, 210, 80), Bark = Color3.fromRGB(110, 80, 56), Grey = Color3.fromRGB(140, 140, 135),
}
Yggdrasil.Colors = C
Yggdrasil.Tuning = { Windup = 0.9, Rise = 0.4, Duration = 6, Crumble = 1.2, Spread = 9.5, RootScale = 1.75, Radius = 14 }

function Yggdrasil.Shot(pos: Vector3, normal: Vector3?)
	normal = normal or Vector3.yAxis
	local cf = VFX.Facing(pos, normal)
	VFX.Burst(pos, { CF = cf, Count = 6, Texture = KB.IceDebris, Color = C.Bark, Size = { 0.9, 1.1 }, Life = { 0.4, 0.7 }, Speed = { 10, 22 }, Spread = 45,
		Accel = Vector3.new(0, -50, 0), Light = 0, Flip = { VFX.G4 } })
	VFX.Burst(pos, { CF = cf, Count = 10, Texture = KB.FireDots, Color = C.Gold, Size = { 0.6, 0 }, Life = { 0.2, 0.4 }, Speed = { 10, 25 }, Spread = 50, Drag = 2, Light = 1, Brightness = 2 })
end

function Yggdrasil.HitAt(_from: Vector3, target: BasePart, kind: string?)
	local pos = target.Position
	if kind == "Impale" then -- a root spears up through an enemy caught in the grove
		local feet = pos - Vector3.new(0, 2.8, 0)
		VFX.Burst(feet, { CF = VFX.Facing(feet, Vector3.yAxis), Count = 10, Texture = KB.SmokeBall, Color = C.Dirt, Size = NumberSequence.new(3, 7),
			Transparency = NumberSequence.new(0.3, 1), Life = { 0.6, 1 }, Speed = { 10, 22 }, Spread = 60, Drag = 2.5, Light = 0 })
		VFX.Burst(feet, { CF = VFX.Facing(feet, Vector3.yAxis), Count = 12, Texture = KB.IceDebris, Color = C.Dirt, Size = NumberSequence.new(1.3, 1.6),
			Life = { 0.6, 1 }, Speed = { 18, 36 }, Spread = 45, Accel = Vector3.new(0, -70, 0), Light = 0, Flip = { VFX.G4 } })
		VFX.Burst(feet, { CF = VFX.Facing(feet, Vector3.yAxis), Count = 10, Texture = KB.Spikes, Color = C.Bark, Size = { 3, 4.5 }, Life = { 0.5, 0.8 },
			Speed = { 2, 6 }, Spread = 10, Light = 0, Flip = { VFX.G4 } })
		VFX.Burst(pos, { Count = 18, Texture = KB.FireDots, Color = C.Gold, Size = { 0.8, 0 }, Life = { 0.4, 0.8 }, Speed = { 12, 30 }, Drag = 2, Light = 1, Brightness = 2 })
		VFX.Sprite(pos, { Tex = KB.Impact, Color = C.Emerald, Size = { 3, 13 }, Life = 0.22, Bright = 2 })
		VFX.GlowColumn(feet, C.Emerald, 18, 4, 0.7, 1.4)
		VFX.Sfx("WoodSplinter", pos, 1)
		return
	end
	local up = VFX.Facing(pos - Vector3.new(0, 2.5, 0), Vector3.yAxis)
	VFX.Burst(pos - Vector3.new(0, 2.5, 0), { CF = up, Count = 14, Texture = KB.FireDots, Color = C.Emerald, Size = { 0.7, 0 }, Life = { 0.6, 1 },
		Speed = { 4, 9 }, Spread = 25, Drag = 1, Accel = Vector3.new(0, 10, 0), Light = 1, Brightness = 2.5 })
	VFX.Burst(pos, { CF = up, Count = 5, Texture = KB.FireDots, Color = C.Gold, Size = { 0.5, 0 }, Life = { 0.5, 0.8 }, Speed = { 3, 6 }, Spread = 60, Drag = 1, Light = 1, Brightness = 2 })
	VFX.Sprite(pos, { Tex = VFX.Tex.Glow, Color = C.Leaf, Size = { 4, 7 }, Life = 0.35, Bright = 1.5, T = { 0.4, 1 } })
end

local function dirt(pos, scale)
	local up = VFX.Facing(pos, Vector3.yAxis)
	VFX.Burst(pos, { CF = up, Count = math.floor(10 * scale), Texture = KB.SmokeBall, Color = C.Dirt, Size = NumberSequence.new(3 * scale, 7 * scale),
		Transparency = NumberSequence.new(0.3, 1), Life = { 0.6, 1 }, Speed = { 10, 22 }, Spread = 60, Drag = 2.5, Light = 0 })
	VFX.Burst(pos, { CF = up, Count = math.floor(12 * scale), Texture = KB.IceDebris, Color = C.Dirt, Size = NumberSequence.new(1.3 * scale, 1.6 * scale),
		Life = { 0.6, 1 }, Speed = { 18, 36 }, Spread = 45, Accel = Vector3.new(0, -70, 0), Light = 0, Flip = { VFX.G4 } })
	VFX.Burst(pos, { CF = up, Count = math.floor(16 * scale), Texture = KB.FireDots, Color = C.Gold, Size = NumberSequence.new(0.8, 0), Life = { 0.4, 0.8 },
		Speed = { 12, 30 }, Spread = 50, Drag = 2, Accel = Vector3.new(0, -20, 0), Light = 1, Brightness = 2 })
end

function Yggdrasil.Play(o)
	local T = Yggdrasil.Tuning
	local at = o.At
	local dur = o.Duration or T.Duration

	-- 1. anticipation: emerald circle, trembling ground, cracks with gold sap
	VFX.RuneCircle(CFrame.new(at), T.Radius, T.Windup + 0.8, { Main = C.Emerald, Deep = C.Deep, Mist = C.Clay }, { Points = 8, Glyphs = 20 })
	VFX.Decal(at, KB.Crack, C.Gold, 8, T.Radius * 3, dur + 1.5, { Bright = 1.3, T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0.35), NumberSequenceKeypoint.new(1, 1) }) })
	VFX.Shake(at, 60, 0.5, T.Windup + 0.2)
	VFX.Sfx("Rumble", at, 1.3); VFX.Sfx("Charge", at, 0.8, 0.7)
	VFX.Wait(T.Windup)

	-- 2. the roots burst up
	local roots = {}
	local names = { "SIG_YggRoot_B", "SIG_YggRoot_A", "SIG_YggRoot_C", "SIG_YggRoot_B", "SIG_YggRoot_A", "SIG_YggRoot_C" }
	local base = o.Base or math.random() * math.pi * 2 -- 2026-11-20: the server picks it so the collision matches
	local model = Instance.new("Model"); model.Name = "YggRoots"
	for i, n in names do
		local a = base + (i - 1) * (math.pi * 2 / #names)
		local p = at + Vector3.new(math.cos(a), 0, math.sin(a)) * T.Spread * (i % 2 == 0 and 0.62 or 1)
		local r = Signatures.Assets[n]:Clone()
		r:ScaleTo(r:GetScale() * T.RootScale * (i % 2 == 0 and 0.8 or 1))
		local cf = CFrame.new(p) * CFrame.Angles(0, -a + math.pi / 2 + (math.random() - 0.5) * 0.6, 0)
		local h = r:GetExtentsSize().Y
		r:PivotTo(cf - Vector3.new(0, h, 0))
		r.Parent = model
		roots[i] = { m = r, cf = cf, h = h, p = p }
	end
	model.Parent = VFX.Folder()
	local hl = Instance.new("Highlight"); hl.FillColor = C.Grey; hl.FillTransparency = 1; hl.OutlineColor = C.Gold; hl.OutlineTransparency = 0.5
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Parent = model
	for _, r in roots do dirt(r.p, 1.4) end
	VFX.Decal(at, KB.Shock, C.Emerald, 6, T.Radius * 3.2, 0.5, { Bright = 1.6 })
	VFX.Decal(at, KB.WaterRing, C.Gold, 4, T.Radius * 2.6, 0.6, { Bright = 1.4 })
	VFX.Sfx("WoodSplinter", at, 1.4, 0.8); VFX.Sfx("Boom", at, 0.8, 0.7); VFX.Sfx("Choir", at, 0.5, 0.9)
	VFX.Shake(at, 60, 1.4, 0.4)
	VFX.Sound("rbxassetid://9125484367", at, 1, 0.45)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Rise, 0, 1)
		local e = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2 -- ease-out-back
		for _, r in roots do r.m:PivotTo(r.cf - Vector3.new(0, r.h * (1 - e), 0)) end
		return t < T.Rise
	end)

	-- 3. standing: dew, leaves, white clay mist, ally shimmer
	local ems = {}
	for _, r in roots do
		local top = VFX.Part({ Transparency = 1, Size = Vector3.new(8, 0.2, 8), CFrame = r.cf + Vector3.new(0, r.h * 0.8, 0) })
		ems[#ems + 1] = VFX.Emitter(top, { Texture = KB.Star, Color = ColorSequence.new(C.Gold), LightEmission = 1, Brightness = 2.5,
			Size = NumberSequence.new(0.45, 0.25), Lifetime = NumberRange.new(0.8, 1.2), Rate = 10, Speed = NumberRange.new(0), Acceleration = Vector3.new(0, -14, 0),
			Shape = Enum.ParticleEmitterShape.Box, Rotation = NumberRange.new(0, 45) })
		ems[#ems + 1] = VFX.Emitter(top, { Texture = KB.Crescents, Color = ColorSequence.new(C.Leaf, C.Emerald), LightEmission = 0.3, Brightness = 1.3,
			Size = NumberSequence.new(0.8, 0.7), Lifetime = NumberRange.new(1.5, 2.2), Rate = 4, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -2.5, 0), RotSpeed = NumberRange.new(-150, 150), Drag = 1, Shape = Enum.ParticleEmitterShape.Box,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }) })
		local foot = VFX.Part({ Transparency = 1, Size = Vector3.new(9, 0.2, 9), CFrame = r.cf + Vector3.new(0, 0.3, 0) })
		ems[#ems + 1] = VFX.Emitter(foot, { Texture = KB.Air, Color = ColorSequence.new(C.Clay), LightEmission = 0.3, Size = NumberSequence.new(4, 8),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1, 1.6), Rate = 8, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(80, 10), Shape = Enum.ParticleEmitterShape.Box,
			FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Rotation = NumberRange.new(0, 360) })
		ems[#ems + 1] = VFX.Emitter(foot, { Texture = KB.FireDots, Color = ColorSequence.new(C.Gold), LightEmission = 1, Brightness = 2,
			Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(0.4, 0.8), Rate = 10, Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(30, 30),
			Shape = Enum.ParticleEmitterShape.Box })
		r.parts = { top, foot }
	end
	local light = Instance.new("PointLight"); light.Color = C.Emerald; light.Brightness = 3; light.Range = 24; light.Shadows = false
	light.Parent = roots[1].parts[2]
	light.Range = 40
	local creakAt = 1.5
	local shields = {}
	for _, a in o.Allies or {} do
		local s = Instance.new("Highlight"); s.FillColor = C.Emerald; s.OutlineColor = C.Emerald; s.FillTransparency = 0.8; s.OutlineTransparency = 0.2
		s.DepthMode = Enum.HighlightDepthMode.Occluded; s.Parent = a
		shields[#shields + 1] = s
		local hrp = a:FindFirstChild("HumanoidRootPart")
		if hrp then
			shields[#shields + 1] = VFX.Emitter(hrp, { Texture = KB.Star, Color = ColorSequence.new(C.Emerald, C.Gold), LightEmission = 1, Brightness = 2,
				Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(0.4, 0.7), Rate = 16, Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
				Shape = Enum.ParticleEmitterShape.Box })
		end
	end
	VFX.Step(function(_, t)
		for _, s in shields do if s:IsA("Highlight") then s.FillTransparency = 0.75 + 0.15 * math.sin(t * 6) end end
		if t >= creakAt then creakAt = t + 1.6 + math.random(); VFX.Sfx("WoodCreak", roots[math.random(1, #roots)].p, 0.7, 0.7) end
		return t < dur
	end)
	for _, s in shields do s:Destroy() end

	-- 4. the roots grey, crack and crumble
	for _, e in ems do if e.Texture ~= KB.Crescents then e.Enabled = false end end
	VFX.Sfx("WoodSplinter", at, 1.2, 0.6); VFX.Sfx("Rumble", at, 0.7, 1.2)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Crumble, 0, 1)
		hl.FillTransparency = 1 - 0.75 * math.clamp(k * 2, 0, 1)
		hl.OutlineTransparency = 0.5 + 0.5 * k
		light.Brightness = 3 * (1 - k)
		for _, r in roots do r.m:PivotTo(r.cf - Vector3.new(0, r.h * math.clamp((k - 0.45) / 0.55, 0, 1) ^ 2 * 0.9, 0)) end
		return t < T.Crumble
	end)
	for _, r in roots do
		local mid = r.cf.Position + Vector3.new(0, 2, 0)
		VFX.Burst(mid, { Count = 14, Texture = KB.SmokeBall, Color = C.Grey, Size = { 4, 8 }, Transparency = { 0.35, 1 }, Life = { 0.8, 1.3 }, Speed = { 3, 9 }, Drag = 2, Light = 0 })
		VFX.Burst(mid, { Count = 12, Texture = KB.IceDebris, Color = C.Bark, Size = { 1.2, 1.5 }, Life = { 0.6, 1 }, Speed = { 8, 18 }, Accel = Vector3.new(0, -60, 0), Light = 0, Flip = { VFX.G4 } })
		VFX.Burst(mid + Vector3.new(0, 4, 0), { Count = 12, Texture = KB.Crescents, Color = C.Leaf, Size = { 0.8, 0.7 }, Life = { 1.4, 2 }, Speed = { 2, 6 }, Drag = 1.5,
			Accel = Vector3.new(0, -3, 0), RotSpeed = 180, Light = 0.3 })
	end
	for _, e in ems do e.Enabled = false end
	model:Destroy()
	for _, r in roots do for _, p in r.parts do VFX.Cleanup(p, 2.5) end end
end

return Yggdrasil
