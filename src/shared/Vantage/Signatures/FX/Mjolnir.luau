--!nonstrict
--[[
	VANTAGE — Signature 01 MJÖLNIR, visuals (client) — 2026-11-19
	"The one who makes lightning": summon bolt from the sky onto the hand, a spinning hammer in a
	cage of arcs with a cyan-to-violet ribbon, forked arcs into each player it passes through, a
	homing return and a thunder catch. Visual only; the server decides hits.

	Mjolnir.Play{
		Hand = function(): CFrame   -- caster's right hand each frame
		Dir = Vector3               -- throw direction (camera look)
		Range = 90, BlockAt = number?  -- distance where a wall stops it (nil = full range)
		Targets = { Vector3 | BasePart | () -> Vector3 }  -- for preview; in game the server's Hit messages drive HitAt
	}  -- yields until the catch
	Mjolnir.HitAt(hammerPos, targetPosOrFn)   -- impact on one player (forked arc, pop, 1 s of crawling arcs)

	The hammer model is Signatures.Assets.SIG_Mjolnir when imported (pivot = grip centre, handle along +Y,
	head at the top); until then a placeholder of parts.
]]

local Signatures = script.Parent.Parent
local VFX = require(Signatures.SignatureVFX)

local Mjolnir = {}

local C = {
	White = Color3.fromRGB(255, 255, 255),
	Cyan = Color3.fromRGB(111, 232, 255),
	Blue = Color3.fromRGB(47, 107, 255),
	Violet = Color3.fromRGB(138, 124, 255),
	Glow = Color3.fromRGB(201, 216, 255), -- pale blue-lavender lightning glow (reference: GoW Thor)
	Lav = Color3.fromRGB(167, 180, 255),
	Metal = Color3.fromRGB(64, 68, 78),
	Edge = Color3.fromRGB(150, 158, 172),
	Grip = Color3.fromRGB(46, 34, 26),
}
Mjolnir.Colors = C

Mjolnir.Tuning = {
	Summon = 0.5,
	Throw = 0.15,
	Hang = 0.4,
	OutSpeed = 120,
	ReturnSpeed = 150,
	Range = 90,
	SpinPerSec = 3.2, -- turns per second
	HitRadius = 3.5,
}

-- placeholder ids (reused from the Ult) until the custom Mjölnir sounds are uploaded
Mjolnir.Sounds = {
	Summon = { "rbxassetid://9125484367", 1.2, 1.15 },
	Throw = { "rbxassetid://9120769331", 0.8, 1.6 },
	Hit = { "rbxassetid://9120769331", 0.7, 2.2 },
	Wall = { "rbxassetid://18245316227", 0.9, 1.4 },
	Catch = { "rbxassetid://9125484367", 0.8, 1.5 },
}

local LAYERS = {
	Summon = { "Thunder", "ThunderCrack" }, Throw = { "Whoosh", "Zap" }, Hit = { "Zap", "ThunderCrack" },
	Wall = { "MetalHit", "Blast" }, Catch = { "Clang", "Zap" }, Build = { "ElecHum", "Rumble" },
}
local function snd(key, pos)
	if LAYERS[key] then for _, n in LAYERS[key] do VFX.Sfx(n, pos) end return end
	local s = Mjolnir.Sounds[key]
	if s then VFX.Sound(s[1], pos, s[2], s[3]) end
end

local function placeholder(): Model
	local m = Instance.new("Model")
	m.Name = "MjolnirPlaceholder"
	local function add(props)
		local p = VFX.Part(props)
		p.Parent = m
		return p
	end
	local grip = add({ Name = "Grip", Material = Enum.Material.Fabric, Color = C.Grip, Size = Vector3.new(0.24, 1.3, 0.24), CFrame = CFrame.new() })
	add({ Name = "Pommel", Material = Enum.Material.Metal, Color = C.Edge, Size = Vector3.new(0.34, 0.2, 0.34), CFrame = CFrame.new(0, -0.72, 0) })
	add({ Name = "Neck", Material = Enum.Material.Metal, Color = C.Edge, Size = Vector3.new(0.32, 0.18, 0.32), CFrame = CFrame.new(0, 0.6, 0) })
	add({ Name = "Head", Material = Enum.Material.Metal, Color = C.Metal, Size = Vector3.new(1.4, 0.9, 0.9), CFrame = CFrame.new(0, 1.12, 0) })
	add({ Name = "FaceL", Material = Enum.Material.Metal, Color = C.Edge, Size = Vector3.new(0.1, 0.96, 0.96), CFrame = CFrame.new(-0.72, 1.12, 0) })
	add({ Name = "FaceR", Material = Enum.Material.Metal, Color = C.Edge, Size = Vector3.new(0.1, 0.96, 0.96), CFrame = CFrame.new(0.72, 1.12, 0) })
	for _, z in { -0.46, 0.46 } do
		add({ Name = "Rune", Color = C.Cyan, Size = Vector3.new(1.1, 0.06, 0.02), CFrame = CFrame.new(0, 1.24, z) })
		add({ Name = "Rune", Color = C.Cyan, Size = Vector3.new(1.1, 0.06, 0.02), CFrame = CFrame.new(0, 1.0, z) })
		add({ Name = "Rune", Color = C.Cyan, Size = Vector3.new(0.06, 0.3, 0.02), CFrame = CFrame.new(0, 1.12, z) })
	end
	add({ Name = "Band", Color = C.Cyan, Size = Vector3.new(0.27, 0.05, 0.27), CFrame = CFrame.new(0, 0.3, 0) })
	add({ Name = "Band", Color = C.Cyan, Size = Vector3.new(0.27, 0.05, 0.27), CFrame = CFrame.new(0, -0.35, 0) })
	m.PrimaryPart = grip
	return m
end

function Mjolnir.BuildHammer(): Model
	local src = Signatures:FindFirstChild("Assets") and Signatures.Assets:FindFirstChild("SIG_Mjolnir")
	local m
	if src then
		m = src:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
	else
		m = placeholder()
	end
	m.Parent = VFX.Folder()
	return m
end

local function resolve(t)
	if typeof(t) == "Vector3" then return t end
	if typeof(t) == "function" then return t() end
	if typeof(t) == "Instance" and t:IsA("BasePart") then return t.Position end
	return nil
end

-- impact on one player: forked arc from the hammer, white pop, then 1 s of arcs crawling over them
function Mjolnir.HitAt(fromPos: Vector3, target)
	local p = resolve(target)
	if not p then return end
	VFX.Strike(fromPos, p, 0.2, { Width = 0.13, Depth = 4, Branches = 4, Jag = 0.22, Color = C.Glow, GlowScale = 5 })
	VFX.Orb(p, C.White, 0.6, 3.2, 0.18, 0.05)
	VFX.Flash(p, C.Cyan, 6, 16, 0.25)
	VFX.Burst(p, { Count = 16, Color = C.Glow, Size = { 0.35, 0 }, Life = { 0.2, 0.45 }, Speed = { 10, 22 }, Drag = 5 })
	snd("Hit", p)
	local fl = workspace:Raycast(p, Vector3.new(0, -8, 0))
	if fl then VFX.Decal(fl.Position, VFX.KB.Crack, C.Lav, 3, 7, 3.2, { Bright = 1.3 }) end
	task.spawn(function()
		local arcs = { VFX.Bolt({ Width = 0.055, Branches = 0, Color = C.Glow, GlowScale = 5 }), VFX.Bolt({ Width = 0.05, Branches = 0, Color = C.Lav, GlowScale = 5 }), VFX.Bolt({ Width = 0.045, Branches = 0, Color = C.Glow, GlowScale = 5 }) }
		local f = 0
		VFX.Step(function(_, t)
			f += 1
			if f % 3 == 1 then
				local c = resolve(target) or p
				local fade = math.clamp((1.6 - t) / 0.5, 0, 1)
				for _, b in arcs do
					b:DrawPoints(VFX.ArcPoints(c, 1.7, VFX.Rng:NextNumber(90, 170), 0.2, 8), fade)
				end
			end
			return t < 1.6
		end)
		for _, b in arcs do b:Destroy() end
	end)
end

function Mjolnir.Play(o)
	local T = Mjolnir.Tuning
	local handCF = o.Hand
	local dir = (o.Dir or Vector3.zAxis).Unit
	local range = math.min(o.Range or T.Range, o.BlockAt or math.huge)
	local targets = o.Targets or {}
	local rng = VFX.Rng
	local OUT, BACK, HANG = o.OutSpeed or T.OutSpeed, o.ReturnSpeed or T.ReturnSpeed, o.Hang or T.Hang
	-- 2026-11-20: lightning rains down along the whole flight path
	local function skyStrike(at: Vector3, big: boolean?)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { workspace.CurrentCamera }
		local down = workspace:Raycast(at, Vector3.new(0, -40, 0), rp)
		local floor = if down then down.Position else at - Vector3.new(0, 6, 0)
		local sky = at + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(34, 48), rng:NextNumber(-5, 5))
		VFX.Strike(sky, floor, if big then 0.3 else 0.18, { Width = if big then 0.38 else 0.2, Depth = 4, Branches = if big then 6 else 3, Jag = 0.2, Color = C.Glow, GlowScale = 4.2, BranchNear = { 0, 0.5 }, BranchLen = { 0.05, 0.14 } })
		VFX.Flash(floor, C.Glow, if big then 8 else 4, if big then 26 else 14, 0.25)
		VFX.Burst(floor + Vector3.new(0, 0.2, 0), { CF = VFX.Facing(floor, Vector3.yAxis), Count = if big then 18 else 8, Color = C.Glow, Size = { 0.22, 0 }, Life = { 0.2, 0.45 }, Speed = { 8, 18 }, Spread = 70, Drag = 3, Accel = Vector3.new(0, -40, 0) })
		if big then VFX.Sfx("ThunderCrack", floor, 0.8, rng:NextNumber(0.9, 1.15)) end
	end
	local strikeAcc = 0
	local function trailStrike(a: Vector3, b: Vector3)
		strikeAcc += (b - a).Magnitude
		if strikeAcc >= 16 then
			strikeAcc = 0
			skyStrike(b)
		end
	end

	local hand = handCF().Position
	local hammer = Mjolnir.BuildHammer()
	local holdOffset = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	local hidden = true
	local function setVisible(v)
		hidden = not v
		for _, d in hammer:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if v then 0 else 1
			end
		end
	end
	setVisible(false)
	hammer:PivotTo(handCF() * holdOffset)

	------------------------------------------------ 0. storm builds: sky darkens, rumble, sparks gather on the hand (0.45 s)
	snd("Build", hand)
	VFX.ScreenTint(hand, 80, Color3.fromRGB(170, 180, 230), -0.12, 0.9)
	do
		local cloud = hand + Vector3.new(0, 40, 0)
		VFX.Burst(cloud, { Count = 10, Texture = VFX.KB.SmokeBall, Color = Color3.fromRGB(70, 74, 96), Size = { 12, 22 }, Transparency = { 0.4, 1 },
			Life = { 1.2, 1.6 }, Speed = { 2, 6 }, Spread = 180, Light = 0 })
		local flick = VFX.Bolt({ Width = 0.05, Color = C.Lav, GlowScale = 5, Branches = 1, Jag = 0.35 })
		VFX.Step(function(_, t)
			local h = handCF().Position
			if math.floor(t * 30) % 3 == 0 then
				flick:Draw(h + VFX.RandomUnit() * 1.6, h + VFX.RandomUnit() * 0.4, 0.8 * math.min(1, t / 0.2))
			else
				flick:Hide()
			end
			return t < 0.3
		end)
		flick:Destroy()
	end

	------------------------------------------------ 1. summon: bolt from the sky onto the hand
	local sky = hand + Vector3.new(rng:NextNumber(-7, 7), 48, rng:NextNumber(-7, 7))
	VFX.Strike(sky, function() return handCF().Position end, 0.24, { Width = 0.34, Depth = 5, Branches = 7, Jag = 0.15, Color = C.Glow, GlowScale = 4.2, BranchNear = { 0, 0.4 }, BranchLen = { 0.05, 0.16 } })
	VFX.Strike(sky + Vector3.new(2, 4, -1.5), function() return handCF().Position end, 0.12, { Width = 0.14, Depth = 4, Branches = 3, Jag = 0.2, Color = C.Lav, BranchNear = { 0, 0.5 }, BranchLen = { 0.05, 0.12 } })
	VFX.Flash(hand, C.Glow, 10, 28, 0.45)
	VFX.ScreenTint(hand, 70, Color3.fromRGB(214, 222, 255), 0.12, 0.25)
	do
		local down = workspace:Raycast(hand, Vector3.new(0, -12, 0))
		local floor = if down then down.Position else hand - Vector3.new(0, 3, 0)
		VFX.GroundPool(floor, C.Glow, 4.5, 0.4)
		VFX.Burst(floor + Vector3.new(0, 0.2, 0), { CF = VFX.Facing(floor, Vector3.yAxis), Count = 22, Color = C.Glow, Size = { 0.22, 0 }, Life = { 0.25, 0.55 }, Speed = { 10, 20 }, Spread = 75, Drag = 2, Accel = Vector3.new(0, -45, 0) })
	end
	snd("Summon", hand)

	local crawl = { VFX.Bolt({ Width = 0.035, Branches = 0, Color = C.Glow, GlowScale = 4 }), VFX.Bolt({ Width = 0.03, Branches = 0, Color = C.Lav, GlowScale = 4 }) }
	local frame = 0
	VFX.Step(function(_, t)
		frame += 1
		local h = handCF()
		if hidden and t >= 0.1 then
			setVisible(true)
			VFX.Orb(h.Position, C.Glow, 0.4, 3.4, 0.28, 0.1)
			VFX.Burst(h.Position, { Count = 28, Color = C.Glow, Size = { 0.3, 0 }, Life = { 0.25, 0.5 }, Speed = { 8, 18 }, Drag = 4 })
		end
		hammer:PivotTo(h * holdOffset)
		if frame % 3 == 1 then
			for _, b in crawl do
				b:DrawPoints(VFX.ArcPoints(h.Position, 0.9, VFX.Rng:NextNumber(80, 160), 0.2, 7), 0.9)
			end
		end
		return t < T.Summon
	end)

	------------------------------------------------ 2. throw
	local start = handCF().Position
	VFX.Flash(start, C.White, 7, 18, 0.2)
	VFX.Shockwave(VFX.Facing(start, dir), C.Glow, 7, 0.28)
	VFX.Burst(start, { CF = VFX.Facing(start, dir), Count = 18, Color = C.White, Size = { 0.25, 0 }, Life = { 0.15, 0.35 }, Speed = { 18, 34 }, Spread = 35, Drag = 6 })
	snd("Throw", start)

	-- flight dressing: ribbon trail + a cage of arcs + a dim light
	local head = hammer.PrimaryPart
	local ribbon = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.White), ColorSequenceKeypoint.new(0.35, C.Cyan), ColorSequenceKeypoint.new(1, C.Violet) })
	local ta, tb = head:FindFirstChild("TrailA"), head:FindFirstChild("TrailB")
	local trail = if ta and tb then VFX.Trail(head, ta.Position * Vector3.new(1, 1.35, 1), tb.Position * Vector3.new(1, 1.35, 1), ribbon, 0.32) else VFX.Trail(head, Vector3.new(0, 0.6, 0), Vector3.new(0, 1.7, 0), ribbon, 0.22)
	local light = Instance.new("PointLight")
	light.Color = C.Glow
	light.Brightness = 5
	light.Range = 18
	light.Shadows = false
	light.Parent = head
	local cage = { VFX.Bolt({ Width = 0.065, Branches = 0, Color = C.Glow, GlowScale = 5 }), VFX.Bolt({ Width = 0.065, Branches = 0, Color = C.Glow, GlowScale = 5 }), VFX.Bolt({ Width = 0.055, Branches = 0, Color = C.Lav, GlowScale = 5 }), VFX.Bolt({ Width = 0.05, Branches = 0, Color = C.Glow, GlowScale = 5 }) }
	-- soft glow shell + continuous crackle sparks round the head
	local shell = VFX.Part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = head.CFrame })
	local halo = Instance.new("ParticleEmitter")
	halo.Texture = VFX.Tex.Glow; halo.Color = ColorSequence.new(C.Glow); halo.LightEmission = 1; halo.LightInfluence = 0
	halo.Size = NumberSequence.new(4.2, 4.6); halo.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) })
	halo.Lifetime = NumberRange.new(0.18, 0.26); halo.Speed = NumberRange.new(0); halo.Rate = 40; halo.LockedToPart = true
	halo.Rotation = NumberRange.new(0, 360); halo.TimeScale = VFX.TimeScale; halo.Parent = shell
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = VFX.Tex.Spark; sparks.Color = ColorSequence.new(C.Glow); sparks.LightEmission = 1; sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new(0.35, 0); sparks.Lifetime = NumberRange.new(0.12, 0.3); sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(180, 180); sparks.Rate = 70; sparks.TimeScale = VFX.TimeScale; sparks.Parent = head

	local spin = 0
	local pos = start
	local hitOut, hitBack = {}, {}
	local nextStatic = 0

	local function place(at: Vector3, heading: Vector3, dt: number)
		spin += dt * T.SpinPerSec * math.pi * 2
		local cf = VFX.Facing(at, heading) * CFrame.Angles(spin, 0, 0) * CFrame.new(0, -0.75, 0)
		hammer:PivotTo(cf)
	end
	local function dress(t: number, center: Vector3)
		frame += 1
		shell.CFrame = CFrame.new(center)
		if frame % 2 == 0 then
			for _, b in cage do
				b:DrawPoints(VFX.ArcPoints(center, 1.6, VFX.Rng:NextNumber(110, 220), 0.18, 9), 1)
			end
		end
		if t >= nextStatic then
			nextStatic = t + 0.1
			VFX.Burst(center, { Count = 3, Color = C.Cyan, Size = { 0.22, 0 }, Life = { 0.3, 0.5 }, Speed = { 1, 3 }, Drag = 2 })
		end
	end
	local function checkHits(a: Vector3, b: Vector3, done)
		for i, tg in targets do
			if not done[i] then
				local p = resolve(tg)
				if p then
					local ab = b - a
					local tt = if ab.Magnitude > 1e-4 then math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
					if (a + ab * tt - p).Magnitude <= T.HitRadius then
						done[i] = true
						Mjolnir.HitAt(a + ab * tt, tg)
					end
				end
			end
		end
	end

	------------------------------------------------ 3. outbound (auto-aim: chain through each target in turn; else straight)
	if o.Waypoints and #o.Waypoints > 0 then
		for _, wp in o.Waypoints do
			VFX.Step(function(dt, t)
				local goal = wp()
				if not goal then return false end
				local to = goal - pos
				local step = OUT * dt
				local prev = pos
				if to.Magnitude <= step + 1 then pos = goal else pos += to.Unit * step end
				if to.Magnitude > 1e-3 then dir = to.Unit end
				place(pos, dir, dt)
				dress(t, pos)
				trailStrike(prev, pos)
				return (goal - pos).Magnitude > 1 and t < 2.5
			end)
			skyStrike(pos, true)
			VFX.Shockwave(VFX.Facing(pos, dir), C.Glow, 8, 0.28)
		end
	else
		local travelled = 0
		VFX.Step(function(dt, t)
			local step = math.min(OUT * dt, range - travelled)
			local prev = pos
			pos += dir * step
			travelled += step
			place(pos, dir, dt)
			dress(t, pos + dir * 0.4)
			checkHits(prev, pos, hitOut)
			trailStrike(prev, pos)
			return travelled < range
		end)
	end

	if o.BlockAt and o.BlockAt <= (o.Range or T.Range) then
		local face = CFrame.lookAt(pos, pos - dir)
		VFX.Shockwave(face, C.Glow, 9, 0.3)
		VFX.Orb(pos, C.White, 0.8, 4, 0.2, 0.1)
		VFX.Flash(pos, C.Glow, 8, 20, 0.3)
		VFX.Burst(pos, { CF = face, Count = 30, Color = C.Glow, Size = { 0.3, 0 }, Life = { 0.3, 0.7 }, Speed = { 12, 26 }, Spread = 70, Drag = 3, Accel = Vector3.new(0, -30, 0) })
		snd("Wall", pos)
	end

	------------------------------------------------ 4. hang, then return homing on the hand
	VFX.Step(function(dt, t)
		local wobble = Vector3.new(math.sin(t * 90) * 0.06, math.cos(t * 70) * 0.06, 0)
		place(pos + wobble, dir, dt * 0.5)
		dress(t, pos)
		return t < HANG
	end)

	trail.Lifetime = 0.16 / VFX.TimeScale
	VFX.Step(function(dt, t)
		local target = handCF().Position
		local to = target - pos
		local dist = to.Magnitude
		local step = BACK * dt
		local prev = pos
		if dist <= step + 0.8 then
			pos = target
		else
			pos += to.Unit * step
		end
		place(pos, if dist > 1e-3 then to.Unit else dir, dt)
		dress(t, pos)
		checkHits(prev, pos, hitBack)
		trailStrike(prev, pos)
		return (target - pos).Magnitude > 0.8 and t < 3
	end)

	------------------------------------------------ 5. catch
	local h = handCF().Position
	VFX.Flash(h, C.Glow, 8, 20, 0.35)
	VFX.Orb(h, C.Glow, 0.6, 2.6, 0.22, 0.1)
	VFX.Burst(h, { Count = 20, Color = C.Glow, Size = { 0.25, 0 }, Life = { 0.2, 0.45 }, Speed = { 6, 14 }, Drag = 4 })
	snd("Catch", h)
	for _, b in cage do b:Destroy() end
	shell:Destroy()
	sparks.Enabled = false
	trail.Enabled = false
	light:Destroy()
	frame = 0
	VFX.Step(function(_, t)
		frame += 1
		local hc = handCF()
		hammer:PivotTo(hc * holdOffset)
		local fade = 1 - t / 0.3
		if frame % 3 == 1 then
			for _, b in crawl do
				b:DrawPoints(VFX.ArcPoints(hc.Position, 0.9, VFX.Rng:NextNumber(80, 160), 0.2, 7), fade)
			end
		end
		if t > 0.2 and not hidden then
			setVisible(false)
			VFX.Burst(hc.Position, { Count = 10, Color = C.Cyan, Size = { 0.2, 0 }, Life = { 0.2, 0.35 }, Speed = { 3, 7 } })
		end
		return t < 0.3
	end)
	for _, b in crawl do b:Destroy() end
	hammer:Destroy()
end

return Mjolnir
