--!nonstrict
--[[
	VANTAGE — Signature 07 HELHEIM, visuals (client) — v1 2026-11-19
	"Half dead, half living." Frost mist rolls out along the ground and the gate of Hel rises, its
	opening sealed by a sheet of ice; its glow is split down the middle, frost white on one side and
	blue-black on the other. The sheet shatters outward and a wall of ice spikes and freezing mist rolls
	across the cone with a mournful howl under it. Anyone caught is encased in jagged ice with a blue rim
	and growing frost crystals; at the thaw the ice cracks and explodes. The gate sinks and frost lingers.

	Helheim.Play{ Origin = CFrame, Range = 36, Angle = 70, Targets = {...}, Freeze = 1.25 }  (yields until the gate is gone)
]]
local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)
local KB = VFX.KB
local Helheim = {}
local C = {
	Frost = Color3.fromRGB(225, 242, 255), Ice = Color3.fromRGB(150, 205, 255), Deep = Color3.fromRGB(40, 70, 160), Void = Color3.fromRGB(10, 14, 40),
	Mist = Color3.fromRGB(210, 228, 245),
}
Helheim.Colors = C
Helheim.Tuning = { Windup = 0.9, Wave = 0.85, Freeze = 1.25, Linger = 3.2, GateAhead = 3.5, Stay = 1.5, Sink = 0.9 }

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

-- encase one target in jagged ice for `dur`, then thaw (crack + explode)
function Helheim.Encase(pos: Vector3, dur: number)
	local ice = Signatures.Assets.SIG_IceEncase:Clone()
	ice:ScaleTo(ice:GetScale() * 1.15)
	local feet = pos - Vector3.new(0, 2.5, 0)
	ice:PivotTo(CFrame.new(feet) * CFrame.Angles(0, math.random() * 6.28, 0))
	local mesh = ice.PrimaryPart
	mesh.Transparency = 0.15
	ice.Parent = VFX.Folder()
	local hl = Instance.new("Highlight"); hl.FillColor = C.Ice; hl.FillTransparency = 0.7; hl.OutlineColor = C.Ice; hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Parent = ice
	-- the encase mesh is low; a frost shell of sprites covers the body above it
	local shellP = VFX.Part({ Transparency = 1, Size = Vector3.new(3.2, 5.5, 3.2), CFrame = CFrame.new(feet + Vector3.new(0, 3, 0)) })
	local shell = {
		VFX.Emitter(shellP, { Texture = KB.IceDebris, Color = ColorSequence.new(C.Frost, C.Ice), LightEmission = 0.6, Brightness = 1.5, Size = NumberSequence.new(2.4, 2.8),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.25), NumberSequenceKeypoint.new(0.85, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.5, 0.8), Rate = 26, Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360), LockedToPart = true,
			FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.Loop, FlipbookFramerate = NumberRange.new(0.001), Shape = Enum.ParticleEmitterShape.Box }),
		VFX.Emitter(shellP, { Texture = KB.Star, Color = ColorSequence.new(C.Frost), LightEmission = 1, Brightness = 3,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.1), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.4, 0.7), Rate = 14, Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 45), LockedToPart = true, Shape = Enum.ParticleEmitterShape.Box }),
	}
	VFX.Sfx("IceShatter2", feet, 0.8, 0.7)
	VFX.Burst(feet + Vector3.new(0, 2.5, 0), { Count = 14, Texture = KB.Snow, Color = C.Frost, Size = { 0.6, 0 }, Life = { 0.4, 0.8 }, Speed = { 6, 14 }, Drag = 2, Light = 1, Brightness = 2 })
	task.spawn(function()
		VFX.Wait(dur - 0.25)
		-- crack...
		VFX.Sprite(feet + Vector3.new(0, 3, 0), { Tex = KB.Crack, Color = C.Frost, Size = { 4, 7 }, Life = 0.25, Bright = 2 })
		VFX.Wait(0.25)
		-- ...and explode
		for _, e in shell do e.Enabled = false end
		VFX.Sfx("IceShatter", feet, 1, 1.1)
		VFX.Burst(feet + Vector3.new(0, 3, 0), { Count = 14, Texture = KB.IceDebris, Color = C.Ice, Size = { 1.8, 2.2 }, Life = { 0.6, 1 }, Speed = { 18, 36 },
			Drag = 1, Accel = Vector3.new(0, -70, 0), Light = 0.6, Flip = { VFX.G4 } })
		VFX.Burst(feet + Vector3.new(0, 3, 0), { Count = 24, Texture = KB.Snow, Color = C.Frost, Size = { 0.6, 0 }, Life = { 0.5, 1 }, Speed = { 12, 26 }, Drag = 2, Light = 1, Brightness = 2 })
		VFX.Sprite(feet + Vector3.new(0, 3, 0), { Tex = KB.Impact, Color = C.Ice, Size = { 3, 10 }, Life = 0.2, Bright = 2 })
		VFX.Decal(feet, KB.Shock, C.Ice, 2, 10, 0.3)
		ice:Destroy(); VFX.Cleanup(shellP, 1)
	end)
end

-- 2026-11-20: the marked enemy shatters into ice
function Helheim.HitAt(_from: Vector3, target: BasePart, _kind: string?)
	local pos = target.Position
	local feet = pos - Vector3.new(0, 2.8, 0)
	VFX.Sprite(pos, { Tex = KB.Impact, Color = C.Frost, Size = { 3, 15 }, Life = 0.22, Bright = 2.2 })
	VFX.Sprite(pos, { Tex = VFX.Tex.Glow, Color = C.Ice, Size = { 6, 16 }, Life = 0.3, Bright = 1.8, T = { 0.2, 1 } })
	VFX.Burst(pos, { Count = 24, Texture = KB.IceDebris, Color = C.Ice, Size = { 1.3, 1.7 }, Life = { 0.7, 1.2 }, Speed = { 16, 40 }, Drag = 1,
		Accel = Vector3.new(0, -70, 0), Light = 0.6, Flip = { VFX.G4 } })
	VFX.Burst(pos, { Count = 30, Texture = KB.Snow, Color = C.Frost, Size = { 0.6, 0 }, Life = { 0.8, 1.4 }, Speed = { 8, 30 }, Drag = 2, Light = 1, Brightness = 2, RotSpeed = 180 })
	VFX.Burst(pos, { Count = 8, Texture = KB.Air, Color = C.Mist, Size = { 4, 9 }, Transparency = { 0.4, 1 }, Life = { 0.6, 1 }, Speed = { 4, 12 }, Drag = 2, Light = 0.5, Flip = { VFX.G4 } })
	VFX.Decal(feet, KB.Crack, C.Ice, 3, 10, 2.5, { Bright = 1.5 })
	VFX.Decal(feet, KB.WaterRing, C.Frost, 2, 16, 0.4, { Bright = 1.6 })
	VFX.Flash(pos, C.Ice, 6, 26, 0.35)
	VFX.Sfx("IceShatter", pos, 1.1)
end

function Helheim.Play(o)
	local T = Helheim.Tuning
	local origin = o.Origin
	local fwd = origin.LookVector * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.zAxis
	local right = fwd:Cross(Vector3.yAxis)
	local range, half = o.Range or 36, math.rad((o.Angle or 70) / 2)
	local base = origin.Position - Vector3.new(0, 3, 0)
	local G = base + fwd * T.GateAhead
	local face = VFX.Facing(G, fwd)

	-- 1. frost mist, the gate rises, ice sheet, split glow
	local mistP = VFX.Part({ Transparency = 1, Size = Vector3.new(10, 0.2, 4), CFrame = face })
	local mist = VFX.Emitter(mistP, { Texture = KB.Air, Color = ColorSequence.new(C.Mist), LightEmission = 0.4, Size = NumberSequence.new(4, 9),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(35, 5), Rate = 40, Drag = 1.5,
		FlipbookLayout = VFX.G4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot, EmissionDirection = Enum.NormalId.Front, Rotation = NumberRange.new(0, 360) })
	local gate = Signatures.Assets.SIG_HelGate:Clone()
	gate.Parent = VFX.Folder()
	local gateH = gate:GetExtentsSize().Y
	gate:PivotTo(face - Vector3.new(0, gateH, 0))
	local sheetP = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = face * CFrame.new(0, gateH * 0.42, 0) })
	local sheet = {
		VFX.Emitter(sheetP, { Texture = KB.Crack, Color = ColorSequence.new(C.Frost), LightEmission = 0.7, Brightness = 1.5, Size = NumberSequence.new(gateH * 0.6),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.3), Rate = 0, Speed = NumberRange.new(0.001), LockedToPart = true, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			EmissionDirection = Enum.NormalId.Front, Rotation = NumberRange.new(0, 360) }),
		-- split glow: frost white left, blue-black right
		VFX.Emitter(sheetP, { Texture = VFX.Tex.Glow, Color = ColorSequence.new(C.Frost), LightEmission = 1, Brightness = 2, Size = NumberSequence.new(gateH * 0.55),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.4), Rate = 0, Speed = NumberRange.new(0), LockedToPart = true, ZOffset = -1 }),
	}
	local sheetL = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = face * CFrame.new(-gateH * 0.18, gateH * 0.42, 0.4) })
	local sheetR = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = face * CFrame.new(gateH * 0.18, gateH * 0.42, 0.4) })
	sheet[#sheet + 1] = VFX.Emitter(sheetL, { Texture = VFX.Tex.Glow, Color = ColorSequence.new(C.Ice), LightEmission = 1, Brightness = 2.5, Size = NumberSequence.new(gateH * 0.42),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.4),
		Rate = 0, Speed = NumberRange.new(0), LockedToPart = true, Squash = NumberSequence.new(-1.2) })
	sheet[#sheet + 1] = VFX.Emitter(sheetR, { Texture = VFX.Tex.Smoke, Color = ColorSequence.new(C.Void), LightEmission = 0, Size = NumberSequence.new(gateH * 0.36),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.25), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(0.5),
		Rate = 0, Speed = NumberRange.new(0), LockedToPart = true, Squash = NumberSequence.new(-1.2), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40) })
	local lw = Instance.new("PointLight"); lw.Color = C.Ice; lw.Brightness = 0; lw.Range = 22; lw.Shadows = false; lw.Parent = sheetL
	VFX.Decal(G, KB.Crack, C.Frost, 6, 14, 2.5, { Bright = 1.2 })
	VFX.Sfx("MetalGrind", G, 1.1, 0.6); VFX.Sfx("Rumble", G, 1); VFX.Sfx("Ghost", G, 1.1, 0.55)
	VFX.Shake(G, 60, 0.6, T.Windup)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Windup, 0, 1)
		local e = 1 - (1 - k) ^ 3
		gate:PivotTo(face - Vector3.new(0, gateH * (1 - e), 0))
		if k > 0.35 then for _, s in sheet do s.Rate = (s.Texture == KB.Crack) and 18 or 10 end end
		lw.Brightness = 3 * e
		return t < T.Windup
	end)

	-- 2. the sheet shatters, the wave rolls out across the cone
	for _, s in sheet do s.Enabled = false end
	local sheetPos = sheetP.Position
	VFX.Sprite(sheetPos, { Tex = KB.Impact, Color = C.Frost, Size = { 6, 22 }, Life = 0.25, Bright = 2 })
	VFX.Sprite(sheetPos, { Tex = KB.WaterRing, Color = C.Ice, Size = { 4, 26 }, Life = 0.35, Dir = fwd, Bright = 2 })
	VFX.Burst(sheetPos, { CF = VFX.Facing(sheetPos, fwd), Count = 26, Texture = KB.IceDebris, Color = C.Ice, Size = { 2, 2.6 }, Life = { 0.6, 1 },
		Speed = { 30, 60 }, Spread = 40, Drag = 1, Accel = Vector3.new(0, -60, 0), Light = 0.6, Flip = { VFX.G4 } })
	VFX.Flash(sheetPos, C.Ice, 8, 40, 0.5)
	VFX.ScreenTint(sheetPos, 60, Color3.fromRGB(200, 225, 255), 0.1, 0.4)
	VFX.Sfx("IceShatter", sheetPos, 1.3, 0.8); VFX.Sfx("IceShatter2", sheetPos, 1, 0.9)
	VFX.Sfx("WhooshLong", sheetPos, 1, 0.6); VFX.Sfx("Ghost", G, 0.9, 0.45) -- low, mournful under the shatter
	mist.Rate = 90; mist.Speed = NumberRange.new(30, 50)
	local frozen = {}
	local row = 0
	VFX.Step(function(_, t)
		local reach = math.clamp(t / T.Wave, 0, 1) * range
		while row * 3.5 <= reach do
			local d = 4 + row * 3.5
			local w = math.tan(half) * d
			local n = math.max(1, math.floor(w * 2 / 4.5))
			for i = 0, n do
				local s = n == 0 and 0 or (i / n - 0.5) * 2
				local p = base + fwd * d + right * (s * w + (math.random() - 0.5) * 1.5)
				VFX.Burst(p, { CF = CFrame.lookAt(p, p + Vector3.yAxis + fwd * 0.3), Count = 2, Texture = KB.Spikes, Color = ColorSequence.new(C.Frost, C.Ice),
					Size = { 3.5, 5.5 }, Transparency = { 0.1, 1 }, Life = { 0.35, 0.55 }, Speed = { 12, 22 }, Spread = 18, Drag = 5, Light = 0.8, Brightness = 1.5,
					Orientation = Enum.ParticleOrientation.VelocityParallel, Flip = { VFX.G2 } })
				VFX.Burst(p, { CF = VFX.Facing(p, Vector3.yAxis), Count = 3, Texture = KB.IceBurst, Color = C.Ice, Size = { 2.5, 3.5 }, Life = { 0.2, 0.35 },
					Speed = { 30, 50 }, Spread = 25, Drag = 3, Light = 0.8, Orientation = Enum.ParticleOrientation.VelocityParallel, Flip = { VFX.G4 } })
				if i % 2 == 0 then
					VFX.Decal(p, KB.Snow, C.Frost, 3, 3.5, T.Linger + 0.8, { Bright = 1, Rot = NumberRange.new(0, 360) })
					VFX.Burst(p, { Count = 2, Texture = KB.Air, Color = C.Mist, Size = { 4, 8 }, Transparency = { 0.45, 1 }, Life = { 0.7, 1.1 }, Speed = { 4, 9 },
						Light = 0.4, Flip = { VFX.G4 }, CF = VFX.Facing(p, fwd) , Spread = 40 })
				end
			end
			row += 1
		end
		for i, tg in o.Targets or {} do
			local p = resolve(tg)
			if p and not frozen[i] then
				local rel = (p - base) * Vector3.new(1, 0, 1)
				local along = rel:Dot(fwd)
				if along > 0 and along <= reach and math.abs(math.atan2(rel:Dot(right), along)) <= half then
					frozen[i] = true
					Helheim.Encase(p, o.Freeze or T.Freeze)
				end
			end
		end
		return t < T.Wave
	end)
	mist.Enabled = false

	-- 3. the gate sinks, frost lingers
	-- the gate stands a moment, frost still pouring, then sinks
	mist.Enabled = true; mist.Rate = 18; mist.Speed = NumberRange.new(4, 9)
	VFX.Wait(T.Stay)
	mist.Enabled = false
	VFX.Sfx("MetalGrind", G, 0.8, 0.5)
	VFX.Step(function(_, t)
		local k = math.clamp(t / T.Sink, 0, 1)
		gate:PivotTo(face - Vector3.new(0, gateH * k * k, 0))
		lw.Brightness = 3 * (1 - k)
		return t < T.Sink
	end)
	gate:Destroy()
	VFX.Cleanup(sheetP, 1); VFX.Cleanup(sheetL, 1); VFX.Cleanup(sheetR, 1); VFX.Cleanup(mistP, 1.5)
end

return Helheim
