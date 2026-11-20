--!nonstrict
--[[
	VANTAGE — Signature 06 RAGNARÖK (Surtr), visuals (client) — v1 2026-11-19
	"Brighter than the sun." A fire rift tears open in the sky and Surtr's sword pushes through tip
	first, its core white-hot; the ground line under it starts to glow. It slams down: a blinding flash,
	a fire shockwave, embers thrown up, then a fissure runs forward, a white-hot crack with flame jets
	bursting every 4 studs and black smoke above. Burning patches stay for 3 s while the crack cools
	from orange to dark red to black char; the sword dissolves upward into embers.

	Ragnarok.Play{ Origin = CFrame, Length = 56, Targets = {...} }  (yields)
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Ragnarok = {}
local C = {
	White = Color3.fromRGB(255, 250, 235), Hot = Color3.fromRGB(255, 214, 120), Orange = Color3.fromRGB(255, 120, 30), Red = Color3.fromRGB(200, 40, 10),
	Dark = Color3.fromRGB(70, 14, 6), Char = Color3.fromRGB(12, 10, 10), Smoke = Color3.fromRGB(30, 26, 26),
}
Ragnarok.Colors = C
Ragnarok.Tuning = { Windup = 1.0, Slam = 0.2, RunSpeed = 72, Step = 4, Burn = 5, Cool = 6.5, Width = 3.5, Forward = 8, SkyHeight = 38, Dissolve = 1.3 }

local COOL = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.White), ColorSequenceKeypoint.new(0.12, C.Orange), ColorSequenceKeypoint.new(0.45, C.Red),
	ColorSequenceKeypoint.new(0.75, C.Dark), ColorSequenceKeypoint.new(1, C.Char) })
local FIRE = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.White), ColorSequenceKeypoint.new(0.25, C.Hot), ColorSequenceKeypoint.new(0.6, C.Orange), ColorSequenceKeypoint.new(1, C.Red) })

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

local function tipOffset(model)
	local mesh = model.PrimaryPart
	local cf = model:GetPivot()
	local lo = math.huge
	for _, x in { -0.5, 0.5 } do for _, y in { -0.5, 0.5 } do for _, z in { -0.5, 0.5 } do
		local p = mesh.CFrame:PointToWorldSpace(mesh.Size * Vector3.new(x, y, z))
		lo = math.min(lo, (p - cf.Position):Dot(cf.UpVector))
	end end end
	return -lo
end

local function jet(pos, scale)
	local up = VFX.Facing(pos, Vector3.yAxis)
	VFX.Burst(pos, { CF = up, Count = math.floor(8 * scale), Texture = KB.FireFlip, Color = FIRE, Size = NumberSequence.new(3.5 * scale, 6 * scale),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Life = { 0.35, 0.6 }, Speed = { 25 * scale, 45 * scale }, Spread = 14, Drag = 3, Light = 1, Brightness = 2, Flip = { VFX.G4 } })
	VFX.Burst(pos, { CF = up, Count = math.floor(14 * scale), Texture = KB.FireDots, Color = C.Hot, Size = NumberSequence.new(0.9, 0), Life = { 0.5, 1 },
		Speed = { 20, 45 }, Spread = 30, Drag = 1, Accel = Vector3.new(0, -20, 0), Light = 1, Brightness = 2 })
	VFX.Burst(pos + Vector3.new(0, 6 * scale, 0), { CF = up, Count = math.floor(4 * scale), Texture = KB.SmokeFlip, Color = C.Smoke, Size = NumberSequence.new(5 * scale, 10 * scale),
		Transparency = NumberSequence.new(0.25, 1), Life = { 1.1, 1.6 }, Speed = { 6, 12 }, Spread = 25, Drag = 1, Light = 0, Flip = { VFX.G4 } })
end

function Ragnarok.HitAt(pos)
	VFX.Sprite(pos + Vector3.new(0, 2.5, 0), { Tex = KB.Impact, Color = C.Orange, Size = { 3, 12 }, Life = 0.22, Bright = 2 })
	jet(pos, 0.6)
end

function Ragnarok.Play(o)
	local T = Ragnarok.Tuning
	local origin = o.Origin
	local fwd = origin.LookVector * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.zAxis
	local length = o.Length or 56
	local base = origin.Position - Vector3.new(0, 3, 0)
	local Q = base + fwd * T.Forward
	local sky = Q + Vector3.new(0, T.SkyHeight, 0)
	local tRoot = typeof(o.Target) == "Instance" and (o.Target:FindFirstChild("HumanoidRootPart") or o.Target.PrimaryPart) or nil
	local tOff = tRoot and (Q - tRoot.Position) * Vector3.new(1, 0, 1) or Vector3.zero
	local function track()
		if tRoot and tRoot.Parent then
			local rp = tRoot.Position
			Q = Vector3.new(rp.X + tOff.X, Q.Y, rp.Z + tOff.Z)
			sky = Q + Vector3.new(0, T.SkyHeight, 0)
		end
	end

	-- 1. rift in the sky, sword tip pushes through, ground line starts glowing
	local riftP = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(sky) })
	local riftE = {
		VFX.Emitter(riftP, { Texture = KB.Rift, Color = ColorSequence.new(C.Hot, C.Orange), LightEmission = 1, Brightness = 3, Size = NumberSequence.new(16, 20),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.15), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.5), Rate = 10, LockedToPart = true, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(60, 120),
			FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop }),
		VFX.Emitter(riftP, { Texture = KB.FireFlip, Color = FIRE, LightEmission = 1, Brightness = 2, Size = NumberSequence.new(5, 9),
			Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 30),
			Rate = 40, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Shape = Enum.ParticleEmitterShape.Disc }),
		VFX.Emitter(riftP, { Texture = KB.SmokeFlip, Color = ColorSequence.new(C.Smoke), LightEmission = 0, Size = NumberSequence.new(10, 18),
			Transparency = NumberSequence.new(0.35, 1), Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180),
			Rate = 12, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot }),
	}
	riftP.Size = Vector3.new(14, 0.2, 14)
	local skyLight = Instance.new("PointLight"); skyLight.Color = C.Orange; skyLight.Brightness = 6; skyLight.Range = 50; skyLight.Shadows = false; skyLight.Parent = riftP
	local sword = Signatures.Assets.SIG_SurtrSword:Clone()
	local mesh = sword.PrimaryPart
	sword.Parent = VFX.Folder()
	local hl = Instance.new("Highlight"); hl.FillColor = C.Hot; hl.FillTransparency = 0.45; hl.OutlineColor = C.White; hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Parent = sword
	local yaw = CFrame.lookAt(Vector3.zero, fwd)
	sword:PivotTo(CFrame.new(sky) * yaw)
	local tipD = tipOffset(sword)
	local blade = VFX.Emitter(mesh, { Texture = KB.FireFlip, Color = FIRE, LightEmission = 1, Brightness = 2, Size = NumberSequence.new(2.5, 4.5),
		Transparency = NumberSequence.new(0.25, 1), Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(180, 180),
		Rate = 60, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Acceleration = Vector3.new(0, 15, 0), Shape = Enum.ParticleEmitterShape.Box })
	local swordLight = Instance.new("PointLight"); swordLight.Color = C.Hot; swordLight.Brightness = 5; swordLight.Range = 30; swordLight.Shadows = false; swordLight.Parent = mesh
	local line = VFX.Bolt({ Width = 0.12, Color = C.Orange, Core = C.Hot, GlowScale = 6, Branches = 0, Jag = 0.05, Depth = 3 })
	VFX.Sfx("Rumble", Q, 1.3); VFX.Sfx("Burning", sky, 1.2); VFX.Sfx("Roar2", sky, 0.7, 0.6)
	VFX.ScreenTint(Q, 120, Color3.fromRGB(255, 170, 130), -0.05, T.Windup + 0.3)
	VFX.Shake(Q, 100, 0.5, T.Windup)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Windup, 0, 1)
		track(); riftP.CFrame = CFrame.new(sky)
		-- tip pushes out of the rift: pivot sits tipD above the rift, so the blade slides down out of it
		sword:PivotTo(CFrame.new(sky + Vector3.new(0, tipD * (1 - k * 0.55), 0)) * yaw)
		line:Draw(Q + Vector3.new(0, 0.12, 0), Q + fwd * length * k + Vector3.new(0, 0.12, 0), 0.35 * k)
		return t < T.Windup
	end)
	-- 2. slam
	local hang = sword:GetPivot()
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Slam, 0, 1)
		track()
		local target = Q + Vector3.new(0, tipD - 2.5, 0)
		sword:PivotTo(CFrame.new(hang.Position:Lerp(target, k * k)) * yaw)
		return t < T.Slam
	end)
	for _, e in riftE do e.Enabled = false end
	VFX.Tween(skyLight, 0.4, { Brightness = 0 })
	VFX.ScreenTint(Q, 120, Color3.fromRGB(255, 225, 190), 0.45, 0.5)
	VFX.Flash(Q + Vector3.new(0, 4, 0), C.Hot, 14, 70, 0.7)
	VFX.Shake(Q, 120, 2.6, 0.6)
	VFX.Sfx("Boom", Q, 1.4); VFX.Sfx("MetalHit", Q, 1.2, 0.6); VFX.Sfx("Blast", Q, 1, 0.7)
	VFX.Sprite(Q + Vector3.new(0, 4, 0), { Tex = KB.Impact, Color = C.Hot, Size = { 6, 30 }, Life = 0.3, Bright = 2.5 })
	VFX.Sprite(Q + Vector3.new(0, 4, 0), { Tex = VFX.Tex.Glow, Color = C.White, Size = { 18, 40 }, Life = 0.35, Bright = 2, T = { 0.1, 1 } })
	VFX.Decal(Q, KB.Ring, C.Orange, 4, 46, 0.5, { Bright = 2 })
	VFX.Decal(Q, KB.WaterRing, C.Hot, 3, 36, 0.55, { Bright = 2 })
	VFX.Decal(Q, KB.Crack, COOL, 8, 24, T.Cool + 1, { Bright = 2, T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) }) })
	jet(Q, 1.6)
	VFX.Burst(Q + Vector3.new(0, 1, 0), { CF = VFX.Facing(Q, Vector3.yAxis), Count = 60, Texture = KB.FireDots, Color = C.Hot, Size = { 1.2, 0 }, Life = { 0.7, 1.4 },
		Speed = { 30, 70 }, Spread = 70, Drag = 1, Accel = Vector3.new(0, -30, 0), Light = 1, Brightness = 2 })

	-- 3. fissure runs forward
	local runner = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(Q) })
	local stopRunner = VFX.SfxLoop("FireLoop", runner, 1.3, 1.2)
	local done = {}
	local patches = {}
	local d, nextJet = 0, 0
	VFX.Step(function(dt, t)
		d = math.min(length, d + T.RunSpeed * dt)
		line:Draw(Q + Vector3.new(0, 0.15, 0), Q + fwd * d + Vector3.new(0, 0.15, 0), 1)
		runner.CFrame = CFrame.new(Q + fwd * d)
		while nextJet <= d do
			local p = Q + fwd * nextJet
			if nextJet > 0 then
				jet(p, 0.9)
				VFX.Decal(p, KB.Crack, COOL, 5, 9, T.Cool, { Bright = 1.8, Rot = NumberRange.new(math.random(0, 360)),
					T = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 1) }) })
				local patch = VFX.Part({ Transparency = 1, Size = Vector3.new(3, 0.2, 3), CFrame = CFrame.new(p) })
				patches[#patches + 1] = VFX.Emitter(patch, { Texture = KB.FireFlip, Color = FIRE, LightEmission = 1, Brightness = 1.8, Size = NumberSequence.new(2, 3.5),
					Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(20, 20),
					Rate = 14, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 6, 0) })
				patches[#patches + 1] = VFX.Emitter(patch, { Texture = KB.SmokeFlip, Color = ColorSequence.new(C.Smoke), LightEmission = 0, Size = NumberSequence.new(3, 7),
					Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(0.9, 1.4), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(15, 15),
					Rate = 4, FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, EmissionDirection = Enum.NormalId.Top })
				VFX.Cleanup(patch, T.Burn / math.max(VFX.TimeScale, 0.05) + 1.6)
			end
			nextJet += T.Step
		end
		for i, tg in o.Targets or {} do
			local p = resolve(tg)
			if p and not done[i] then
				local rel = (p - Q) * Vector3.new(1, 0, 1)
				local along = rel:Dot(fwd)
				if along >= 0 and along <= d and (rel - fwd * along).Magnitude <= T.Width then done[i] = true; Ragnarok.HitAt(p - Vector3.new(0, 2.5, 0)) end
			end
		end
		return d < length
	end)

	stopRunner(0.6)
	VFX.Cleanup(runner, 1.5)
	local mid = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(Q + fwd * length * 0.5) })
	local stopBurn = VFX.SfxLoop("Burning", mid, 1.1, 0.9)
	task.delay(T.Burn / math.max(VFX.TimeScale, 0.05), function() stopBurn(1.2); VFX.Cleanup(mid, 2) end)
	-- 4. burning, the line cools, the sword dissolves upward into embers
	VFX.Wait(1.0)
	VFX.Sfx("WhooshLong", sword:GetPivot().Position, 0.6, 0.5)
	blade.Acceleration = Vector3.new(0, 40, 0)
	blade.Texture = KB.FireDots; blade.Size = NumberSequence.new(1, 0); blade.Rate = 140; blade.Lifetime = NumberRange.new(0.6, 1.1)
	local swordAt = sword:GetPivot()
	task.spawn(function()
		VFX.Step(function(_, t)
			local k = math.clamp(t / T.Burn, 0, 1)
			local col = k < 0.4 and C.Orange:Lerp(C.Red, k / 0.4) or C.Red:Lerp(C.Dark, (k - 0.4) / 0.6)
			line.Color = col; line.Core = C.Hot:Lerp(C.Red, k)
			line:Draw(Q + Vector3.new(0, 0.15, 0), Q + fwd * length + Vector3.new(0, 0.15, 0), 1 - k * 0.85)
			return t < T.Burn
		end)
		for _, e in patches do e.Enabled = false end
		line:Destroy()
	end)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Dissolve, 0, 1)
		sword:PivotTo(swordAt + Vector3.new(0, k * 7, 0))
		mesh.Transparency = k
		hl.FillTransparency = 0.45 + 0.55 * k; hl.OutlineTransparency = 0.1 + 0.9 * k
		swordLight.Brightness = 5 * (1 - k)
		return t < T.Dissolve
	end)
	blade.Enabled = false
	VFX.Cleanup(sword, 1.2 / math.max(VFX.TimeScale, 0.05)); VFX.Cleanup(riftP, 1.5)
end

return Ragnarok
