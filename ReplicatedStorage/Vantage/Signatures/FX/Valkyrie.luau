--!nonstrict
--[[
	VANTAGE — Signature 05 VALKYRIE, visuals (client) — v1 2026-11-19
	Swan feathers burst and a pillar of light rises as glowing wings unfold from the shoulders; the
	player lifts and hovers, wings slow-flapping white-gold, feathers drifting, an aurora ribbon
	(teal to blue to violet) hanging below. The wings sweep back for the dive, the trail becomes a full
	aurora, and the landing hits with a gold shock ring, a column of light, a feather storm and dust.
	The wings fold into light. Landing ring: gold for allies, red for enemies.

	Valkyrie.Play{ Start = CFrame, DiveTo = Vector3, Hover = 0.9, Move = function(cf) end, Targets = {...}, Enemy = false }  (yields)
	Move is called every frame with the root CFrame the caster should be at (the lab anchors the root; the server version drives it).
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Valkyrie = {}
local C = {
	Gold = Color3.fromRGB(255, 214, 120), White = Color3.new(1, 1, 1), Teal = Color3.fromRGB(70, 255, 200), Blue = Color3.fromRGB(70, 140, 255),
	Violet = Color3.fromRGB(170, 100, 255), Red = Color3.fromRGB(255, 70, 70), Dust = Color3.fromRGB(205, 195, 180),
}
Valkyrie.Colors = C
Valkyrie.Tuning = { Unfold = 0.6, Rise = 11, Hover = 1.6, Dive = 0.42, HitRadius = 11, Fold = 0.75, Linger = 2.6 }

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

local function feathers(pos, count, speed, life)
	VFX.Burst(pos, { Count = count, Texture = KB.Crescents, Color = C.White, Size = { 1.3, 1.1 }, Life = { life * 0.6, life },
		Speed = { speed * 0.4, speed }, Drag = 3, Accel = Vector3.new(0, -5, 0), Light = 0.8, Brightness = 1.5, RotSpeed = 260,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }) })
end

function Valkyrie.Play(o)
	local T = Valkyrie.Tuning
	local start = o.Start
	local move = o.Move or function() end
	local fwd = start.LookVector * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.zAxis
	local ground = start.Position - Vector3.new(0, 3, 0)
	local hoverAt = start.Position + Vector3.new(0, o.Rise or T.Rise, 0)
	local landAt = o.DiveTo
	local tRoot = typeof(o.Target) == "Instance" and o.Target:FindFirstChild("HumanoidRootPart") or nil
	local function trackLand()
		if tRoot and tRoot.Parent then
			local rp = tRoot.Position
			landAt = Vector3.new(rp.X, landAt.Y, rp.Z)
		end
	end
	local ringCol = o.Enemy and C.Red or C.Gold

	-- wings (one mesh mirrored by a half-turn), glowing white-gold
	local wings = Instance.new("Model"); wings.Name = "ValkyrieWings"
	local R = Signatures.Assets.SIG_ValkyrieWing_R:Clone(); R.Parent = wings
	local L = Signatures.Assets.SIG_ValkyrieWing_R:Clone(); L.Parent = wings
	wings.Parent = VFX.Folder()
	for _, w in { R, L } do w:ScaleTo(w:GetScale() * 1.25); w.PrimaryPart.Transparency = 1 end
	local hl = Instance.new("Highlight"); hl.FillColor = C.Gold; hl.OutlineColor = C.White; hl.FillTransparency = 1; hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Parent = wings
	local glows = {}
	for _, w in { R, L } do
		glows[#glows + 1] = VFX.Emitter(w.PrimaryPart, { Texture = KB.Star, Color = ColorSequence.new(C.White, C.Gold), LightEmission = 1, Brightness = 2,
			Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(0.5, 2), Rate = 0, SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -3, 0), Shape = Enum.ParticleEmitterShape.Box })
		glows[#glows + 1] = VFX.Emitter(w.PrimaryPart, { Texture = KB.Crescents, Color = ColorSequence.new(C.White), LightEmission = 0.8, Brightness = 1.5,
			Size = NumberSequence.new(0.9, 0.8), Lifetime = NumberRange.new(0.9, 1.4), Speed = NumberRange.new(0.5, 2), Rate = 0, SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -4, 0), RotSpeed = NumberRange.new(-200, 200), Drag = 1.5, Shape = Enum.ParticleEmitterShape.Box,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) }) })
	end
	local light = Instance.new("PointLight"); light.Color = C.Gold; light.Brightness = 0; light.Range = 18; light.Shadows = false; light.Parent = R.PrimaryPart

	-- aurora ribbon hanging under the player
	local carrier = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = start })
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, -1.2, 0); a0.Parent = carrier
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -4.5, 0); a1.Parent = carrier
	local aurora = Instance.new("Trail")
	aurora.Attachment0 = a0; aurora.Attachment1 = a1; aurora.FaceCamera = true; aurora.LightEmission = 1; aurora.LightInfluence = 0
	aurora.Texture = VFX.Tex.Glow; aurora.TextureMode = Enum.TextureMode.Stretch
	aurora.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.Teal), ColorSequenceKeypoint.new(0.5, C.Blue), ColorSequenceKeypoint.new(1, C.Violet) })
	aurora.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.5), NumberSequenceKeypoint.new(1, 1) })
	aurora.Lifetime = 0.6 / math.max(VFX.TimeScale, 0.05); aurora.WidthScale = NumberSequence.new(1, 0.3); aurora.Parent = carrier
	local auroraMotes = VFX.Emitter(carrier, { Texture = KB.Star, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.Teal), ColorSequenceKeypoint.new(1, C.Violet) }),
		LightEmission = 1, Brightness = 2, Size = NumberSequence.new(0.7, 0), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rate = 0 })

	local function place(root, back, flap)
		carrier.CFrame = root
		local scale = 1
		R:PivotTo(root * CFrame.new(0.45 * scale, 1.3, 0.75) * CFrame.Angles(0, -back, 0) * CFrame.Angles(0, 0, flap))
		L:PivotTo(root * CFrame.new(-0.45 * scale, 1.3, 0.75) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, back, 0) * CFrame.Angles(0, 0, flap))
	end
	local face = CFrame.lookAt(Vector3.zero, fwd)

	-- 1. anticipation: feathers, pillar, wings unfold, rise
	VFX.GlowColumn(ground, C.Gold, 30, 7, 1.0, 1.4)
	VFX.Decal(ground, KB.WaterRing, C.Gold, 2, 16, 0.45, { Bright = 1.5 })
	feathers(start.Position + Vector3.new(0, 1.5, 0), 26, 16, 1.4)
	VFX.Sfx("Wings", start.Position, 1.2); VFX.Sfx("Choir", start.Position, 0.9); VFX.Sfx("Rise", start.Position)
	for _, e in glows do e.Rate = (e.Texture == KB.Star) and 30 or 5 end
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Unfold, 0, 1)
		local e = 1 - (1 - k) ^ 3
		local root = CFrame.new(start.Position:Lerp(hoverAt, e)) * face
		move(root)
		place(root, 1.35 - 1.1 * e, -1.05 + 1.3 * e)
		R.PrimaryPart.Transparency = 1 - 0.75 * e; L.PrimaryPart.Transparency = R.PrimaryPart.Transparency
		hl.FillTransparency = 1 - 0.55 * e; hl.OutlineTransparency = 1 - 0.8 * e
		light.Brightness = 4 * e
		return t < T.Unfold
	end)

	-- 2. hover: slow flaps, aurora below, landing ring telegraph
	aurora.Enabled = true; auroraMotes.Rate = 25
	local stopFlap = VFX.SfxLoop("WingsLoop", carrier, 0.8, 0.85)
	local hover = o.Hover or T.Hover
	local marker = VFX.Marker(ringCol, 6)
	local lookDown = CFrame.lookAt(Vector3.zero, ((landAt - hoverAt) * Vector3.new(1, 0, 1)).Magnitude > 1 and ((landAt - hoverAt) * Vector3.new(1, 0, 1)).Unit or fwd)
	VFX.Step(function(_, t)
		trackLand()
		marker:Draw(landAt, t, math.clamp(t / 0.15, 0, 1))
		local root = CFrame.new(hoverAt + Vector3.new(0, math.sin(t * 6) * 0.35, 0)) * lookDown
		move(root)
		place(root, 0.25, 0.22 + math.sin(t * 7) * 0.32)
		return t < hover
	end)

	stopFlap(0.2)
	trackLand()
	marker:Destroy()
	VFX.Sfx("WhooshLong", hoverAt, 1.2, 0.9)
	-- 3. dive: wings sweep back, full aurora
	aurora.Lifetime = 0.9 / math.max(VFX.TimeScale, 0.05); auroraMotes.Rate = 70
	a1.Position = Vector3.new(0, -6, 0)
	local from = hoverAt
	local to = landAt + Vector3.new(0, 3, 0)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Dive, 0, 1)
		local p = from:Lerp(to, k ^ 1.6)
		local root = CFrame.lookAt(p, p + (to - from).Unit) * CFrame.Angles(math.rad(20), 0, 0)
		move(CFrame.new(p) * lookDown)
		place(root, 1.05, 0.1)
		return t < T.Dive
	end)

	-- 4. impact
	move(CFrame.new(to) * lookDown)
	place(CFrame.new(to) * lookDown, 0.6, 0.6)
	VFX.Decal(landAt, KB.Ring, ringCol, 3, 34, 0.45, { Bright = 2 })
	VFX.Decal(landAt, KB.WaterRing, C.Gold, 2, 26, 0.55, { Bright = 1.6 })
	VFX.Decal(landAt, KB.Crack, C.Gold, 5, 16, 1.6, { Bright = 1.3 })
	VFX.GlowColumn(landAt, C.Gold, 38, 9, 1.3, 1.5)
	feathers(landAt + Vector3.new(0, 2, 0), 46, 34, T.Linger)
	VFX.Decal(landAt, KB.Crack, C.Gold, 6, 18, T.Linger + 0.5, { Bright = 1.2 })
	VFX.Burst(landAt + Vector3.new(0, 1, 0), { CF = VFX.Facing(landAt, Vector3.yAxis), Count = 14, Texture = KB.SmokeBall, Color = C.Dust,
		Size = { 4, 9 }, Transparency = { 0.4, 1 }, Life = { 0.7, 1.2 }, Speed = { 14, 28 }, Spread = 85, Drag = 3, Light = 0 })
	VFX.Burst(landAt + Vector3.new(0, 2, 0), { Count = 30, Texture = KB.Star, Color = C.Gold, Size = { 1.2, 0 }, Life = { 0.3, 0.6 }, Speed = { 25, 50 }, Drag = 3, Light = 1, Brightness = 2 })
	VFX.Sprite(landAt + Vector3.new(0, 3, 0), { Tex = KB.Impact, Color = C.Gold, Size = { 4, 20 }, Life = 0.25, Bright = 1.8 })
	VFX.Flash(landAt + Vector3.new(0, 3, 0), C.Gold, 8, 34, 0.45)
	VFX.Shake(landAt, 60, 1.6, 0.4)
	VFX.Sfx("Boom", landAt, 1.1); VFX.Sfx("Blast", landAt, 0.8, 1.2); VFX.Sfx("Choir", landAt, 0.6, 1.2)
	for i, tg in o.Targets or {} do
		local p = resolve(tg)
		if p and (p - landAt).Magnitude <= T.HitRadius + 3 then
			VFX.Sprite(p, { Tex = KB.Crescent, Color = C.Gold, Size = { 6, 8 }, Life = 0.25, Bright = 2, Flip = { VFX.G4 } })
		end
	end
	aurora.Enabled = false; auroraMotes.Rate = 0
	local drift = VFX.Part({ Transparency = 1, Size = Vector3.new(14, 0.2, 14), CFrame = CFrame.new(landAt + Vector3.new(0, 12, 0)) })
	local driftE = VFX.Emitter(drift, { Texture = KB.Crescents, Color = ColorSequence.new(C.White), LightEmission = 0.6, Brightness = 1.4,
		Size = NumberSequence.new(1, 0.9), Lifetime = NumberRange.new(2, 2.6), Rate = 16, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -4, 0), RotSpeed = NumberRange.new(-160, 160), Drag = 1, Shape = Enum.ParticleEmitterShape.Box, EmissionDirection = Enum.NormalId.Bottom,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }) })
	task.delay(T.Linger / math.max(VFX.TimeScale, 0.05), function() driftE.Enabled = false end)
	VFX.Cleanup(drift, (T.Linger + 3) / math.max(VFX.TimeScale, 0.05))

	-- 5. wings fold into light
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Fold, 0, 1)
		place(CFrame.new(to) * lookDown, 0.6 + 0.8 * k, 0.6 - 1.6 * k)
		hl.FillTransparency = 0.45 - 0.35 * math.sin(k * math.pi) + 0.55 * k
		hl.OutlineTransparency = 0.2 + 0.8 * k
		R.PrimaryPart.Transparency = 0.25 + 0.75 * k; L.PrimaryPart.Transparency = R.PrimaryPart.Transparency
		light.Brightness = 4 * (1 - k)
		return t < T.Fold
	end)
	VFX.Sfx("Wings", to, 0.6, 1.2)
	for _, e in glows do e.Rate = 0 end
	VFX.Burst(to + Vector3.new(0, 1.3, 0.6), { Count = 24, Texture = KB.Star, Color = C.Gold, Size = { 0.8, 0 }, Life = { 0.4, 0.8 }, Speed = { 3, 8 }, Drag = 2, Light = 1, Brightness = 2 })
	VFX.Cleanup(wings, 0.05); VFX.Cleanup(carrier, 1.5)
end

return Valkyrie
