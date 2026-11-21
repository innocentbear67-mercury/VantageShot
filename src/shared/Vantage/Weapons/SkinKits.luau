--[[
	VANTAGE — SkinKits
	Extra skin detail built on top of a weapon's role recolour: flush decals (SurfaceGui insignia,
	stencils, chevrons, pinstripes) and, for higher tiers, added geometry. Purely cosmetic.

	Every kit part is a BasePart named "VantageSkinMesh", welded to the weapon Root, so:
	  - Skins.Apply removes it on the next skin change (it already clears that name),
	  - the Viewmodel tracks it like any gun part (initial build and live ApplySkin).
	Offsets are in Root space at the weapon's authored scale and follow model:GetScale().

	SkinKits.Build(model, weaponId, kitId)
]]

local SkinKits = {}

local function rootOf(model: Instance): BasePart?
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChild("Root") :: BasePart?
end

local function scaleOf(model: Instance): number
	return if model:IsA("Model") then model:GetScale() else 1
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- a kit part welded to the root; cf is Root-space at scale 1
local function kitPart(ctx, size: Vector3, cf: CFrame, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = "VantageSkinMesh"
	p.Size = size * ctx.k
	local rel = cf.Rotation + cf.Position * ctx.k
	p.CFrame = ctx.root.CFrame * rel
	p.Anchored = ctx.root.Anchored
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	if not p.Anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = ctx.root, p
		w.Parent = p
	end
	p:SetAttribute("SkinKit", ctx.kit)
	p.Parent = ctx.root
	return p
end

-- flush SurfaceGui decal on a side face. side = 1 (+X, Right face) or -1 (-X, Left face).
-- (x = surface offset, y/z centre, w along Z, h along Y). draw(frame, px, py) fills the canvas.
local PX = 1400 -- canvas pixels per stud
local function sideDecal(ctx, side: number, x: number, y: number, z: number, w: number, h: number, draw)
	local p = kitPart(ctx, Vector3.new(0.002, h, w), CFrame.new(side * (x + 0.0025), y, z), { Transparency = 1 })
	local g = Instance.new("SurfaceGui")
	g.Face = if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.CanvasSize = Vector2.new(math.floor(w * PX), math.floor(h * PX))
	g.LightInfluence = 1
	g.Brightness = 1.2
	g.AlwaysOnTop = false
	g.ResetOnSpawn = false
	g.ClipsDescendants = true
	g.Adornee = p
	g.Parent = p
	draw(g, g.CanvasSize.X, g.CanvasSize.Y, side)
	return p
end

local function bar(parent, cx, cy, len, thick, rot, color, zi)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(cx, cy)
	f.Size = UDim2.fromOffset(len, thick)
	f.Rotation = rot
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zi or 2
	f.Parent = parent
	return f
end

-- six-armed snowflake with branches, centre gem and a thin ring
local function snowflake(parent, cx, cy, s, arm: Color3, ring: Color3)
	local t = s * 0.055
	for i = 0, 2 do
		bar(parent, cx, cy, s * 0.86, t, i * 60, arm, 3)
	end
	for i = 0, 5 do
		local a = math.rad(i * 60)
		for _, frac in { 0.22, 0.34 } do
			local d = s * frac
			local px, py = cx + math.cos(a) * d, cy + math.sin(a) * d
			local len = s * (if frac < 0.3 then 0.15 else 0.11)
			for _, off in { 50, -50 } do
				local b = math.rad(i * 60 + off)
				bar(parent, px + math.cos(b) * len * 0.5, py + math.sin(b) * len * 0.5, len, t * 0.8, i * 60 + off, arm, 3)
			end
		end
		-- arm tip diamond
		local tip = Instance.new("Frame")
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.fromOffset(cx + math.cos(a) * s * 0.43, cy + math.sin(a) * s * 0.43)
		tip.Size = UDim2.fromOffset(t * 1.8, t * 1.8)
		tip.Rotation = 45 + i * 60
		tip.BackgroundColor3 = arm
		tip.BorderSizePixel = 0
		tip.ZIndex = 3
		tip.Parent = parent
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromOffset(cx, cy)
	hub.Size = UDim2.fromOffset(s * 0.16, s * 0.16)
	hub.Rotation = 45
	hub.BackgroundColor3 = ring
	hub.BorderSizePixel = 0
	hub.ZIndex = 4
	hub.Parent = parent
	local st = Instance.new("UIStroke")
	st.Color = arm
	st.Thickness = t * 0.6
	st.Parent = hub
	local r = Instance.new("Frame")
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromOffset(cx, cy)
	r.Size = UDim2.fromOffset(s * 0.99, s * 0.99)
	r.BackgroundTransparency = 1
	r.ZIndex = 2
	r.Parent = parent
	Instance.new("UICorner", r).CornerRadius = UDim.new(0.5, 0)
	local rs = Instance.new("UIStroke")
	rs.Color = ring
	rs.Thickness = t * 0.45
	rs.Parent = r
end

local function label(parent, text, x, y, w, h, color, font, xa)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.Text = text
	l.TextColor3 = color
	l.Font = font or Enum.Font.Sarpanch
	l.TextScaled = true
	l.TextXAlignment = xa or Enum.TextXAlignment.Left
	l.ZIndex = 3
	l.Parent = parent
	return l
end

local function recolour(ctx, name: string, color: Color3, material: Enum.Material?)
	for _, d in ctx.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			d.Color = color
			if material then
				d.Material = material
				d.MaterialVariant = ""
			end
		end
	end
end

local function frostEdge(g, w, h, fromBottom: boolean)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.ZIndex = 1
	f.Parent = g
	local gr = Instance.new("UIGradient")
	gr.Rotation = if fromBottom then 90 else -90
	gr.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 236, 255))
	gr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.8),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	gr.Parent = f
	-- a few ice crystals along the edge
	for i = 1, math.floor(w / (h * 0.9)) do
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		local sz = h * (0.12 + ((i * 37) % 7) / 60)
		c.Size = UDim2.fromOffset(sz, sz)
		c.Position = UDim2.fromOffset((i - 0.5) * h * 0.9 + ((i * 53) % 11) * h * 0.03, if fromBottom then h * 0.82 else h * 0.18)
		c.Rotation = 45
		c.BackgroundColor3 = Color3.fromRGB(235, 248, 255)
		c.BackgroundTransparency = 0.25
		c.BorderSizePixel = 0
		c.ZIndex = 2
		c.Parent = g
	end
end

-- ─── kits ─────────────────────────────────────────────────────────────────
local KITS = {}

-- RARE — Glacier Ops: finish only. Frost-white ceramic over glacier-blue anodised, brushed silver
-- hardware; a blue snowflake insignia on the receiver, a stencil call-sign on the stock, ice-blue
-- chevrons + a pinstripe on the handguard, a serial plate on the lower, frost creeping up the edges.
KITS.Glacier = {
	Vanguard = function(ctx)
		local blue, ice, navy, silver = rgb(38, 92, 156), rgb(150, 220, 255), rgb(22, 36, 60), rgb(200, 210, 222)
		-- glacier-blue magazine body so the frame / mag split reads at a distance
		recolour(ctx, "Magazine__Frame", rgb(54, 108, 172), Enum.Material.Metal)
		recolour(ctx, "Magazine__Dark", rgb(30, 44, 70))
		for _, side in { 1, -1 } do
			-- receiver insignia
			sideDecal(ctx, side, 0.097, 0.165, 0.30, 0.215, 0.215, function(g, w, h)
				snowflake(g, w / 2, h / 2, math.min(w, h) * 0.96, blue, ice)
			end)
			-- handguard: chevrons pointing at the muzzle + pinstripe + frost from the lower edge
			sideDecal(ctx, side, 0.124, 0.085, -1.45, 0.62, 0.19, function(g, w, h, sd)
				local dir = if sd > 0 then 1 else -1 -- canvas +x is toward the muzzle on the +X face
				local cy = h * 0.5
				for i = 0, 2 do
					local cx = w * 0.5 + dir * (i - 1) * h * 0.42
					local arm = h * 0.36
					bar(g, cx - dir * arm * 0.3, cy - arm * 0.36, arm, h * 0.09, dir * 50, if i == 2 then ice else blue)
					bar(g, cx - dir * arm * 0.3, cy + arm * 0.36, arm, h * 0.09, -dir * 50, if i == 2 then ice else blue)
				end
				bar(g, w * 0.5, h * 0.06, w, h * 0.035, 0, silver)
				local frost = Instance.new("Frame")
				frost.Position = UDim2.fromOffset(0, h * 0.55)
				frost.Size = UDim2.fromOffset(w, h * 0.45)
				frost.BackgroundColor3 = rgb(255, 255, 255)
				frost.BorderSizePixel = 0
				frost.ZIndex = 1
				frost.Parent = g
				local gr = Instance.new("UIGradient")
				gr.Rotation = 90
				gr.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.6, 0.75),
					NumberSequenceKeypoint.new(1, 0.35),
				})
				gr.Parent = frost
			end)
			-- stock stencil call-sign
			sideDecal(ctx, side, 0.092, 0.13, 1.20, 0.58, 0.06, function(g, w, h)
				label(g, "GLACIER OPS", w * 0.02, h * 0.04, w * 0.62, h * 0.92, navy, Enum.Font.Sarpanch)
				bar(g, w * 0.68, h * 0.5, h * 0.12, h * 0.7, 0, blue)
				label(g, "VX-01 / 07", w * 0.72, h * 0.18, w * 0.27, h * 0.66, blue, Enum.Font.RobotoMono)
			end)
			-- ice-blue pinstripe along the bottom edge of the upper receiver
			sideDecal(ctx, side, 0.097, 0.052, -0.02, 1.0, 0.012, function(g, w, h)
				bar(g, w / 2, h / 2, w, h, 0, ice)
			end)
			-- frost creeping up the stock and the lower receiver
			sideDecal(ctx, side, 0.092, 0.07, 1.20, 0.58, 0.07, function(g, w, h)
				frostEdge(g, w, h, false)
			end)
			-- lower receiver serial plate
			sideDecal(ctx, side, 0.113, -0.085, 0.15, 0.30, 0.055, function(g, w, h)
				local plate = Instance.new("Frame")
				plate.Size = UDim2.fromScale(1, 1)
				plate.BackgroundColor3 = silver
				plate.BorderSizePixel = 0
				plate.Parent = g
				Instance.new("UICorner", plate).CornerRadius = UDim.new(0.25, 0)
				label(plate, "CRYO-ANODISED  ·  SN 0417", w * 0.05, h * 0.18, w * 0.9, h * 0.64, navy, Enum.Font.RobotoMono, Enum.TextXAlignment.Center)
			end)
		end
	end,
}

-- ─── mesh kits (full sculpted shells from SkinKitMeshes/<Kit>_<Weapon>) ────────────────────────
-- Each template MeshPart carries RootCF (its Root-space CFrame at weapon scale 1). A shell kit hides
-- the base weapon's parts (SkinHiddenT, restored by Skins.Apply) and welds the sculpted pieces on;
-- the magazine piece rides the Magazine model so reloads still move it.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TagCache = require(script.Parent.Parent:WaitForChild("TagCache"))
local Meshes = script.Parent:FindFirstChild("SkinKitMeshes")

local function hideBase(ctx)
	for _, d in ctx.model:GetDescendants() do
		if d:IsA("BasePart") and d ~= ctx.root and d.Name ~= "VantageSkinMesh" and d.Transparency < 1 then
			d:SetAttribute("SkinHiddenT", d.Transparency)
			d.Transparency = 1
		end
	end
end

-- anim: { Kind = "Flap"|"Spin", Pivot = Root-space Vector3, Axis = Root-space Vector3, Amp = deg, Speed = Hz or rad/s, Phase }
local function meshPiece(ctx, folder: Instance, name: string, props, anim, parentTo: BasePart?)
	local t = folder:FindFirstChild(name)
	if not t then
		return nil
	end
	local p = t:Clone()
	p.Name = "VantageSkinMesh"
	local rcf = t:GetAttribute("RootCF") :: CFrame
	p:SetAttribute("RootCF", nil)
	p.Size = t.Size * ctx.k
	p.CFrame = ctx.root.CFrame * (rcf.Rotation + rcf.Position * ctx.k)
	p.Anchored = ctx.root.Anchored
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p:SetAttribute("SkinKit", ctx.kit)
	local anchor = parentTo or ctx.root
	if anim then
		-- pivot as an Attachment so ScaleTo keeps it right; axis in the part's own frame
		local pv = Instance.new("Attachment")
		pv.Name = "AnimPivot"
		pv.Position = p.CFrame:PointToObjectSpace(ctx.root.CFrame:PointToWorldSpace(anim.Pivot * ctx.k))
		pv.Parent = p
		p:SetAttribute("AnimKind", anim.Kind)
		p:SetAttribute("AnimAxis", p.CFrame:VectorToObjectSpace(ctx.root.CFrame:VectorToWorldSpace(anim.Axis.Unit)))
		p:SetAttribute("AnimAmp", anim.Amp or 0)
		p:SetAttribute("AnimSpeed", anim.Speed or 1)
		p:SetAttribute("AnimPhase", anim.Phase or 0)
		local w = Instance.new("Weld")
		w.Name = "SkinAnimWeld"
		w.Part0, w.Part1 = anchor, p
		w.C0 = anchor.CFrame:ToObjectSpace(p.CFrame)
		w.Parent = p
		CollectionService:AddTag(p, "VantageSkinAnim")
	elseif not p.Anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = anchor, p
		w.Parent = p
	end
	p.Parent = anchor
	return p
end

-- extra local transform of an animated kit part at time t (also used by the Viewmodel)
function SkinKits.AnimOffset(p: BasePart, t: number, D: any?): CFrame
	local kind = p:GetAttribute("AnimKind")
	if not kind then
		return CFrame.identity
	end
	local pv = p:FindFirstChild("AnimPivot") :: Attachment?
	local piv = if pv then CFrame.new(pv.Position) else CFrame.identity
	local axis = p:GetAttribute("AnimAxis") :: Vector3
	local speed = p:GetAttribute("AnimSpeed") :: number
	local phase = p:GetAttribute("AnimPhase") :: number
	local ampMul = 1
	if D then -- inspect drive (SkinInspects via Viewmodel)
		if kind == "Spin" then
			t += D.SpinT
		elseif kind == "Sway" then
			t += D.SwayT
			ampMul = D.SwayAmp
		else
			t += D.FlapT
		end
	end
	local a
	if kind == "Spin" then
		a = t * speed + phase
	elseif kind == "Sway" then -- pendulum / flicker: both ways, with a lighter second harmonic
		local w = 2 * math.pi * (t * speed + phase)
		a = math.rad(p:GetAttribute("AnimAmp") :: number) * (math.sin(w) + 0.25 * math.sin(w * 2.3 + 1.1)) * ampMul
	else -- Flap: quick downstroke, slow recovery, a small flutter on top
		local u = (t * speed + phase) % 1
		local stroke = if u < 0.35 then math.sin(u / 0.35 * math.pi * 0.5) else math.cos((u - 0.35) / 0.65 * math.pi * 0.5)
		a = math.rad(p:GetAttribute("AnimAmp") :: number) * (stroke + 0.06 * math.sin(t * 13 + phase * 7)) * (if D and D.FlapAmp then D.FlapAmp else 1)
	end
	if D and kind ~= "Spin" and kind ~= "Sway" and D.HoldW > 0.001 then
		a += (math.rad(p:GetAttribute("AnimAmp") :: number) * D.HoldA - a) * math.min(D.HoldW, 1)
	end
	return piv * CFrame.fromAxisAngle(axis, a) * piv:Inverse()
end

-- client animator for world models (the Viewmodel animates its own anchored copies)
if RunService:IsClient() and not _G.__VantageSkinAnimator then
	_G.__VantageSkinAnimator = true
	local base = setmetatable({}, { __mode = "k" })
	-- 2026-11-20 perf: only world models near the camera animate (weld writes move whole assemblies)
	local NEAR = 90
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cam = workspace.CurrentCamera
		local cp = if cam then cam.CFrame.Position else Vector3.zero
		local set = TagCache.get("VantageSkinAnim")
		local pulseSet = TagCache.get("VantageSkinPulse")
		if #set == 0 and #pulseSet == 0 then
			return
		end
		for _, p in set do
			if p:IsA("BasePart") and not p.Anchored and (p.Position - cp).Magnitude < NEAR and p:IsDescendantOf(workspace) and not p:FindFirstAncestor("VantageViewmodel") then
				local w = p:FindFirstChild("SkinAnimWeld") :: Weld?
				if w then
					if not base[w] then
						base[w] = w.C0
						-- the world-model weld pass also WeldConstraint-locks every part; release ours locally
						for _, c in p:GetChildren() do
							if c:IsA("WeldConstraint") then
								c.Enabled = false
							end
						end
					end
					w.C0 = base[w] * SkinKits.AnimOffset(p, t)
				end
			end
		end
		-- pulsing glows (Highlight fill / light brightness), world and viewmodel alike
		for _, o in pulseSet do
			if o.Parent then
				local prop = o:GetAttribute("PulseProp")
				local lo, hi, sp = o:GetAttribute("PulseMin"), o:GetAttribute("PulseMax"), o:GetAttribute("PulseSpeed")
				local k = 0.5 + 0.5 * math.sin(t * sp * 2 * math.pi + (o:GetAttribute("PulsePhase") or 0))
				local v = lo + (hi - lo) * k
				local ib = o:GetAttribute("InspectBoost")
				if ib then -- inspect flare (SkinInspects)
					if prop == "FillTransparency" then
						v = math.max(0, v - 0.4 * ib)
					else
						v *= 1 + 1.6 * ib
					end
				end
				if prop == "FillTransparency" and o:GetAttribute("FPBias") then
					v = math.min(1, v + o:GetAttribute("FPBias"))
				end
				pcall(function() (o :: any)[prop] = v end)
			end
		end
	end)
end

local function emitterOn(parent: Instance, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e:SetAttribute("SkinFXIdle", true)
	e:SetAttribute("BaseRate", e.Rate)
	e.Parent = parent
	return e
end

local function att(ctx, part: BasePart, rootPos: Vector3, name: string?)
	local a = Instance.new("Attachment")
	a.Name = name or "KitFX"
	a.Position = part.CFrame:PointToObjectSpace(ctx.root.CFrame:PointToWorldSpace(rootPos * ctx.k))
	a.Parent = part
	return a
end

local function seq(...)
	local a = { ... }
	local kps = {}
	for i = 1, #a, 2 do
		kps[#kps + 1] = NumberSequenceKeypoint.new(a[i], a[i + 1])
	end
	return NumberSequence.new(kps)
end

-- ─── Tripo shell kits (all five premium VX-01 skins) ───────────────────────────────────────────
-- spec = {
--   folder = "<Kit>_Vanguard",
--   anims = { Piece = { Kind, Pivot (Root), Axis (Root), Amp (deg), Speed (Hz | rad/s for Spin), Phase } },
--   neon = { Piece = Color3 }                          -- untextured pieces (halos / rings) glow
--   aura = { Fill, Outline, FillT = 0.72, Pulse = {Min, Max, Speed}?, Glint = {c1, c2}, Radiance = Color3,
--            Light = {Color, Brightness, Range}, Spots = { {Pos, Color, Kind = "Flare"|"Fire"|"Vortex"|"Glow", Size} } }
-- }
local function pulse(o: Instance, prop: string, lo: number, hi: number, speed: number, phase: number?)
	o:SetAttribute("PulseProp", prop)
	o:SetAttribute("PulseMin", lo)
	o:SetAttribute("PulseMax", hi)
	o:SetAttribute("PulseSpeed", speed)
	o:SetAttribute("PulsePhase", phase or 0)
	CollectionService:AddTag(o, "VantageSkinPulse")
end

local TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Soft = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}

local function spot(ctx, vol: BasePart, sp)
	local a = att(ctx, vol, sp.Pos)
	local c = sp.Color
	local z = sp.Size or 0.3
	if sp.Kind == "Fire" then -- flames that stay on the gun (short life, locked to it)
		emitterOn(a, { Name = "SpotFire", Texture = TEX.Fire, Color = ColorSequence.new(c, rgb(255, 230, 160)), LightEmission = 1, Brightness = 3,
			Size = seq(0, z, 1, z * 0.3), Transparency = seq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.25, 0.4), Rate = 30,
			Speed = NumberRange.new(0.2, 0.5), SpreadAngle = Vector2.new(15, 15), EmissionDirection = sp.Dir or Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120), LockedToPart = true, ZOffset = 0.2 })
	elseif sp.Kind == "Vortex" then
		emitterOn(a, { Name = "SpotVortex", Texture = TEX.Vortex, Color = ColorSequence.new(c), LightEmission = 1, Brightness = 3,
			Size = seq(0, z, 1, z * 0.4), Transparency = seq(0, 0.3, 1, 1), Lifetime = NumberRange.new(0.7, 1), Rate = 6,
			Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(220, 260), LockedToPart = true, ZOffset = 0.3 })
	elseif sp.Kind == "Glow" then
		emitterOn(a, { Name = "SpotGlow", Texture = TEX.Soft, Color = ColorSequence.new(c), LightEmission = 1, Brightness = 3,
			Size = seq(0, z, 1, z * 1.2), Transparency = seq(0, 0.4, 1, 1), Lifetime = NumberRange.new(0.4, 0.6), Rate = 10,
			Speed = NumberRange.new(0, 0), LockedToPart = true, ZOffset = 0.4 })
	else -- Flare
		emitterOn(a, { Name = "SpotFlare", Texture = TEX.Spark, Color = ColorSequence.new(c, rgb(255, 255, 255)), LightEmission = 1, Brightness = 6,
			Size = seq(0, 0.05, 0.3, z, 1, 0), Transparency = seq(0, 0, 1, 1), Lifetime = NumberRange.new(0.5, 0.8), Rate = 6,
			Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 90), RotSpeed = NumberRange.new(-40, 40), LockedToPart = true })
	end
	if sp.Light ~= false then
		local l = Instance.new("PointLight")
		l.Color = c; l.Brightness = sp.LightBrightness or 1.6; l.Range = sp.LightRange or 3; l.Shadows = false
		l:SetAttribute("SkinFXIdle", true)
		l.Parent = a
		if sp.Pulse then
			pulse(l, "Brightness", l.Brightness * 0.4, l.Brightness * 1.3, sp.Pulse, sp.Phase)
		end
	end
	return a
end

local function shell(spec)
	return function(ctx)
		local folder = Meshes and Meshes:FindFirstChild(spec.folder)
		if not folder then
			return
		end
		hideBase(ctx)
		local tex = { Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic }
		local mag = ctx.model:FindFirstChild("Magazine")
		local made = {}
		for _, t in folder:GetChildren() do
			if t:IsA("BasePart") then
				local n = t.Name
				local props = tex
				if spec.neon and spec.neon[n] then
					props = { Color = spec.neon[n], Material = Enum.Material.Neon }
				end
				local an = spec.anims and spec.anims[n]
				made[n] = meshPiece(ctx, folder, n, props, an, if n == "Mag" and mag then mag.PrimaryPart else nil)
			end
		end
		-- ── aura: the gun itself glows; nothing drifts off it into the player's view ──
		local A = spec.aura
		local hl = Instance.new("Highlight")
		hl.Name = "SkinAura"
		hl.FillColor = A.Fill
		hl.FillTransparency = A.FillT or 0.72
		hl.OutlineColor = A.Outline
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		-- the outline only wraps the shell: a Highlight also draws the hidden base parts, and the base
		-- magazine pokes out under some shells as a ghost box. The Mag piece stays on the magazine (reload).
		local shellM = Instance.new("Model")
		shellM.Name = "VantageSkinMesh"
		shellM.Parent = ctx.model
		for n, p in made do
			if p and n ~= "Mag" then
				p.Parent = shellM
			end
		end
		hl.Adornee = shellM
		hl.Parent = ctx.root
		if A.Pulse then
			pulse(hl, "FillTransparency", A.Pulse[1], A.Pulse[2], A.Pulse[3])
		end
		local vol = kitPart(ctx, if spec.vol then spec.vol[1] else Vector3.new(0.46, 0.85, 4.6), if spec.vol then spec.vol[2] else CFrame.new(0, -0.07, -0.55), { Transparency = 1 })
		emitterOn(vol, { Name = "Glint", Texture = TEX.Spark, Color = ColorSequence.new(A.Glint[1], A.Glint[2]), LightEmission = 1, Brightness = 5,
			Size = seq(0, 0, 0.3, 0.12, 1, 0), Transparency = seq(0, 0.1, 1, 1), Lifetime = NumberRange.new(0.5, 0.9), Rate = 90,
			Speed = NumberRange.new(0, 0), Rotation = NumberRange.new(0, 90), ZOffset = 0.25,
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, LockedToPart = true })
		emitterOn(vol, { Name = "Radiance", Texture = TEX.Soft, Color = ColorSequence.new(A.Radiance), LightEmission = 1, Brightness = 2.8, ZOffset = 0.6,
			Size = seq(0, 0.9, 0.5, 1.1, 1, 0.9), Transparency = seq(0, 1, 0.35, 0.6, 0.65, 0.6, 1, 1),
			Lifetime = NumberRange.new(1.2, 1.8), Rate = 34, Speed = NumberRange.new(0, 0),
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, LockedToPart = true })
		local L = A.Light
		local glow = Instance.new("PointLight")
		glow.Color = L[1]; glow.Brightness = L[2]; glow.Range = L[3]; glow.Shadows = false
		glow:SetAttribute("SkinFXIdle", true)
		glow.Parent = vol
		if A.LightPulse then
			pulse(glow, "Brightness", L[2] * 0.5, L[2] * 1.2, A.LightPulse)
		end
		for _, sp in A.Spots or {} do
			spot(ctx, vol, sp)
		end
		if spec.extra then
			spec.extra(ctx, made, vol)
		end
		-- first person: lighter fill, and nothing soft in front of the sight line
		if RunService:IsClient() then
			task.defer(function()
				if ctx.model:FindFirstAncestor("VantageViewmodel") then
					-- pieces that would cover the screen in first person (third person keeps them)
					for _, n in spec.fpHide or {} do
						if made[n] then
							made[n]:Destroy()
						end
					end
					-- pieces in the scope's line of sight: the Viewmodel fades them out as you aim in
					for _, n in spec.adsFade or {} do
						if made[n] then
							made[n]:SetAttribute("ADSFade", true)
						end
					end
					hl.FillTransparency = math.max(hl.FillTransparency, 0.88)
					hl.OutlineTransparency = 0.3
					if A.Pulse then
						hl:SetAttribute("FPBias", 0.16)
					end
					for _, d in vol:GetDescendants() do
						if d:IsA("ParticleEmitter") and (d.Name == "Radiance" or d.Name == "SpotGlow") then
							d.Enabled = false
						elseif d:IsA("PointLight") then
							d.Brightness *= 0.5
						end
					end
				end
			end)
		end
	end
end

local V = Vector3.new

-- EPIC — Archangel: pearl / gold / navy; flapping wings, three spinning halo rings, gold glow
KITS.Archangel = { Vanguard = shell({
	folder = "Archangel_Vanguard",
	anims = {
		WingL = { Kind = "Flap", Pivot = V(-0.13, 0.29, 0.68), Axis = V(0, 0.18, 1), Amp = 24, Speed = 0.45 },
		WingR = { Kind = "Flap", Pivot = V(0.13, 0.29, 0.68), Axis = V(0, -0.18, -1), Amp = 24, Speed = 0.45 },
		Halo0 = { Kind = "Spin", Pivot = V(0, 0.108, -2.76), Axis = V(0.12, 0.35, 1), Speed = 1.3 },
		Halo1 = { Kind = "Spin", Pivot = V(0, 0.108, -2.76), Axis = V(0.5, -0.4, 1), Speed = -1.8 },
		Halo2 = { Kind = "Spin", Pivot = V(0, 0.108, -2.76), Axis = V(-0.6, 0.25, 1), Speed = 2.6 },
	},
	neon = { Halo0 = rgb(255, 204, 112), Halo1 = rgb(255, 232, 170), Halo2 = rgb(90, 170, 255) },
	aura = { Fill = rgb(255, 206, 110), Outline = rgb(255, 236, 170), FillT = 0.72, Glint = { rgb(255, 232, 170), rgb(255, 204, 112) },
		Radiance = rgb(255, 214, 120), Light = { rgb(255, 214, 140), 2.2, 9 },
		Spots = {
			{ Pos = V(0.19, 0.064, -0.01), Color = rgb(120, 190, 255), Kind = "Flare", Size = 0.32, Pulse = 0.6 },
			{ Pos = V(-0.19, 0.064, -0.01), Color = rgb(120, 190, 255), Kind = "Flare", Size = 0.32, Pulse = 0.6, Phase = 1.5 },
			{ Pos = V(0, 0.108, -2.76), Color = rgb(255, 232, 170), Kind = "Glow", Size = 0.9, LightBrightness = 2.5, LightRange = 5 },
		} },
}) }

-- MYTHIC — Molten Sovereign: obsidian dragon-maw rifle; the jaw works, the lava breathes, the maw burns
KITS.Molten = { Vanguard = shell({
	folder = "Molten_Vanguard",
	anims = { Jaw = { Kind = "Flap", Pivot = V(0, 0.06, -2.4), Axis = V(-1, 0, 0), Amp = 16, Speed = 0.35 } },
	aura = { Fill = rgb(255, 90, 20), Outline = rgb(255, 140, 40), FillT = 0.8, Pulse = { 0.7, 0.88, 0.45 },
		Glint = { rgb(255, 170, 60), rgb(255, 80, 20) }, Radiance = rgb(255, 100, 30), Light = { rgb(255, 110, 40), 2.4, 9 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(0, 0.09, -2.66), Color = rgb(255, 120, 30), Kind = "Fire", Size = 0.32, Dir = Enum.NormalId.Front, LightBrightness = 2.6, LightRange = 5, Pulse = 0.9 },
			{ Pos = V(0, 0.07, -1.95), Color = rgb(255, 120, 30), Kind = "Glow", Size = 0.6, Pulse = 0.45 },
			{ Pos = V(0.17, 0.25, -0.2), Color = rgb(255, 90, 20), Kind = "Glow", Size = 0.35, Light = false },
			{ Pos = V(-0.17, 0.25, -0.2), Color = rgb(255, 90, 20), Kind = "Glow", Size = 0.35, Light = false },
		} },
}) }

-- LEGENDARY — Event Horizon: a black hole torn through the receiver; tendrils writhe, accretion rings spin
KITS.Horizon = { Vanguard = shell({
	folder = "Horizon_Vanguard",
	anims = {
		Tendrils = { Kind = "Sway", Pivot = V(0, 0.38, -0.42), Axis = V(0, 0, 1), Amp = 6, Speed = 0.45 },
		RingL = { Kind = "Spin", Pivot = V(-0.192, 0.041, -0.345), Axis = V(1, -0.25, 0.15), Speed = 2.2 },
		RingR = { Kind = "Spin", Pivot = V(0.192, 0.041, -0.345), Axis = V(1, 0.25, 0.15), Speed = -2.2 },
		RingL2 = { Kind = "Spin", Pivot = V(-0.192, 0.041, -0.345), Axis = V(1, -0.25, 0.15), Speed = -3.4 },
		RingR2 = { Kind = "Spin", Pivot = V(0.192, 0.041, -0.345), Axis = V(1, 0.25, 0.15), Speed = 3.4 },
	},
	neon = { RingL = rgb(200, 90, 255), RingR = rgb(200, 90, 255), RingL2 = rgb(255, 120, 230), RingR2 = rgb(255, 120, 230) },
	aura = { Fill = rgb(150, 60, 255), Outline = rgb(210, 140, 255), FillT = 0.76, Pulse = { 0.68, 0.84, 0.3 },
		Glint = { rgb(230, 170, 255), rgb(160, 80, 255) }, Radiance = rgb(160, 70, 255), Light = { rgb(170, 90, 255), 2.2, 9 },
		Spots = {
			{ Pos = V(0.21, 0.041, -0.345), Color = rgb(200, 110, 255), Kind = "Vortex", Size = 0.42, LightBrightness = 2, LightRange = 4, Pulse = 0.3 },
			{ Pos = V(-0.21, 0.041, -0.345), Color = rgb(200, 110, 255), Kind = "Vortex", Size = 0.42, LightBrightness = 2, LightRange = 4, Pulse = 0.3, Phase = 1.6 },
		} },
}) }

-- EXCLUSIVE — Kitsune // Lunar Festival: fox-spirit rifle; bell charm, rope tassel and shide streamers swing,
-- blue foxfire burns in the handguard
KITS.Kitsune = { Vanguard = shell({
	folder = "Kitsune_Vanguard",
	anims = {
		Charm = { Kind = "Sway", Pivot = V(-0.048, -0.12, 1.762), Axis = V(1, 0, 0), Amp = 12, Speed = 0.7 },
		Tassel = { Kind = "Sway", Pivot = V(0.06, -0.125, -1.5), Axis = V(1, 0, 0.2), Amp = 10, Speed = 0.55, Phase = 0.3 },
		Shide = { Kind = "Sway", Pivot = V(-0.009, -0.08, -0.946), Axis = V(1, 0, 0), Amp = 9, Speed = 0.8, Phase = 0.6 },
	},
	aura = { Fill = rgb(120, 210, 255), Outline = rgb(200, 240, 255), FillT = 0.78, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(210, 245, 255), rgb(90, 190, 255) }, Radiance = rgb(90, 180, 255), Light = { rgb(110, 200, 255), 2.2, 9 },
		Spots = {
			{ Pos = V(0, 0.2, -2.0), Color = rgb(70, 170, 255), Kind = "Fire", Size = 0.26, LightBrightness = 2.2, LightRange = 5, Pulse = 0.8 },
			{ Pos = V(0, 0.2, -1.6), Color = rgb(70, 170, 255), Kind = "Fire", Size = 0.24, Light = false },
			{ Pos = V(0.07, 0.17, -2.66), Color = rgb(90, 230, 255), Kind = "Flare", Size = 0.16, LightBrightness = 1.2, LightRange = 2, Pulse = 0.5 },
			{ Pos = V(-0.07, 0.17, -2.66), Color = rgb(90, 230, 255), Kind = "Flare", Size = 0.16, Light = false },
		} },
}) }

-- GODLY — Golden Dragon Emperor: a gold dragon coiled along the rifle; the jaw works, the tail flame
-- flickers, fire in the maw, gold-and-crimson glow
KITS.Dragon = { Vanguard = shell({
	folder = "Dragon_Vanguard",
	anims = {
		Jaw = { Kind = "Flap", Pivot = V(0, 0.038, -2.413), Axis = V(-1, 0, 0), Amp = 14, Speed = 0.4 },
		TailFlame = { Kind = "Sway", Pivot = V(0, 0.34, 1.53), Axis = V(1, 0, 0.3), Amp = 9, Speed = 1.4 },
	},
	aura = { Fill = rgb(255, 196, 80), Outline = rgb(255, 120, 50), FillT = 0.72, Pulse = { 0.64, 0.8, 0.4 },
		Glint = { rgb(255, 230, 150), rgb(255, 120, 40) }, Radiance = rgb(255, 170, 60), Light = { rgb(255, 170, 80), 2.6, 10 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(0, 0.09, -2.7), Color = rgb(255, 130, 40), Kind = "Fire", Size = 0.3, Dir = Enum.NormalId.Front, LightBrightness = 2.4, LightRange = 5, Pulse = 0.9 },
			{ Pos = V(0, 0.48, 1.53), Color = rgb(255, 120, 40), Kind = "Fire", Size = 0.28, LightBrightness = 1.6, LightRange = 3 },
			{ Pos = V(0.12, 0.42, -2.55), Color = rgb(255, 120, 40), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(-0.12, 0.42, -2.55), Color = rgb(255, 120, 40), Kind = "Flare", Size = 0.14, Light = false },
		} },
}) }

-- ─── BR-07 Sentinel premium shells (Tripo, fitted with fit_sentinel.py) ─────────────────────────
-- EPIC — Storm Herald: thunderbird marksman; feather wings beat on the stock, storm-cell magazine
KITS.Storm = { Sentinel = shell({
	folder = "Storm_Sentinel",
	anims = {
		WingL = { Kind = "Flap", Pivot = V(-0.12, 0.12, 0.66), Axis = V(0, 0.18, 1), Amp = 14, Speed = 0.5 },
		WingR = { Kind = "Flap", Pivot = V(0.12, 0.12, 0.66), Axis = V(0, -0.18, -1), Amp = 14, Speed = 0.5 },
	},
	aura = { Fill = rgb(70, 160, 255), Outline = rgb(170, 220, 255), FillT = 0.78, Pulse = { 0.7, 0.86, 0.9 },
		Glint = { rgb(210, 240, 255), rgb(70, 160, 255) }, Radiance = rgb(70, 150, 255), Light = { rgb(110, 180, 255), 2.2, 9 }, LightPulse = 1.2,
		Spots = {
			{ Pos = V(0, -0.33, -0.1), Color = rgb(80, 170, 255), Kind = "Glow", Size = 0.4, LightBrightness = 2, LightRange = 4, Pulse = 1.1 },
			{ Pos = V(0, 0.108, -2.45), Color = rgb(150, 210, 255), Kind = "Flare", Size = 0.2, Light = false },
			{ Pos = V(0.16, 0.2, 1.1), Color = rgb(150, 210, 255), Kind = "Flare", Size = 0.2, Light = false },
			{ Pos = V(-0.16, 0.2, 1.1), Color = rgb(150, 210, 255), Kind = "Flare", Size = 0.2, Light = false },
		} },
}) }

-- MYTHIC — Abyssal Leviathan: sea-serpent rifle; the jaw works, the tail fin sways, the tank glows
KITS.Leviathan = { Sentinel = shell({
	folder = "Leviathan_Sentinel",
	adsFade = { "Mid" }, -- the angler lure stands in the scope's line of sight
	anims = {
		Jaw = { Kind = "Flap", Pivot = V(0, -0.1, -1.93), Axis = V(-1, 0, 0), Amp = 12, Speed = 0.35 },
		TailFin = { Kind = "Sway", Pivot = V(0, -0.21, 1.51), Axis = V(0, 1, 0), Amp = 10, Speed = 0.6 },
	},
	aura = { Fill = rgb(30, 220, 200), Outline = rgb(140, 255, 240), FillT = 0.8, Pulse = { 0.72, 0.88, 0.35 },
		Glint = { rgb(200, 255, 250), rgb(40, 200, 220) }, Radiance = rgb(30, 200, 200), Light = { rgb(60, 220, 210), 2.2, 9 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0, -0.445, -0.33), Color = rgb(40, 230, 210), Kind = "Glow", Size = 0.4, LightBrightness = 2, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, 0.6, -1.55), Color = rgb(120, 255, 240), Kind = "Glow", Size = 0.25, LightBrightness = 1.4, LightRange = 3, Pulse = 0.8 },
			{ Pos = V(0.1, 0.18, -2.2), Color = rgb(90, 240, 255), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(-0.1, 0.18, -2.2), Color = rgb(90, 240, 255), Kind = "Flare", Size = 0.14, Light = false },
		} },
}) }

-- LEGENDARY — Celestial Astrolabe: marble-and-gold rifle with a galaxy inside; the astrolabe ring turns
KITS.Celestial = { Sentinel = shell({
	folder = "Celestial_Sentinel",
	anims = { Ring = { Kind = "Spin", Pivot = V(0.005, 0.11, -1.587), Axis = V(0, 0, 1), Speed = 1.4 } },
	aura = { Fill = rgb(255, 214, 120), Outline = rgb(150, 180, 255), FillT = 0.8, Pulse = { 0.72, 0.86, 0.3 },
		Glint = { rgb(255, 255, 255), rgb(140, 170, 255) }, Radiance = rgb(110, 140, 255), Light = { rgb(200, 200, 255), 2.2, 9 },
		Spots = {
			{ Pos = V(0, 0.15, -0.35), Color = rgb(255, 220, 140), Kind = "Glow", Size = 0.4, LightBrightness = 2, LightRange = 4, Pulse = 0.4 },
			{ Pos = V(0, 0.15, 0.9), Color = rgb(90, 120, 255), Kind = "Vortex", Size = 0.3, Light = false },
			{ Pos = V(0.22, 0.11, -1.59), Color = rgb(255, 240, 200), Kind = "Flare", Size = 0.18, Light = false },
			{ Pos = V(-0.22, 0.11, -1.59), Color = rgb(255, 240, 200), Kind = "Flare", Size = 0.18, Light = false },
		} },
}) }

-- EXCLUSIVE — Sakura Ronin // Spring Festival: lacquered samurai rifle; the silk tassel swings, petals glint
KITS.Sakura = { Sentinel = shell({
	folder = "Sakura_Sentinel",
	anims = { Tassel = { Kind = "Sway", Pivot = V(0, -0.56, 1.48), Axis = V(1, 0, 0), Amp = 12, Speed = 0.7 } },
	aura = { Fill = rgb(255, 110, 160), Outline = rgb(255, 200, 220), FillT = 0.8, Pulse = { 0.72, 0.88, 0.35 },
		Glint = { rgb(255, 220, 235), rgb(255, 120, 170) }, Radiance = rgb(255, 120, 170), Light = { rgb(255, 150, 190), 2, 8 },
		Spots = {
			{ Pos = V(0, 0.68, -0.95), Color = rgb(255, 210, 120), Kind = "Flare", Size = 0.18, LightBrightness = 1.2, LightRange = 2, Pulse = 0.5 },
			{ Pos = V(0, 0.05, 1.0), Color = rgb(255, 120, 170), Kind = "Glow", Size = 0.35, Light = false },
		} },
}) }

-- GODLY — Phoenix Ascendant: holy firebird; the wings beat, the tail plumes sway, fire at the beak, sun-orb core
KITS.Phoenix = { Sentinel = shell({
	folder = "Phoenix_Sentinel",
	fpHide = { "Wings" },
	anims = {
		Wings = { Kind = "Sway", Pivot = V(0.015, 0.42, 0.9), Axis = V(1, 0, 0), Amp = 6, Speed = 0.45 },
		Tail = { Kind = "Sway", Pivot = V(0.025, -0.3, 1.0), Axis = V(1, 0, 0.3), Amp = 7, Speed = 0.6, Phase = 1 },
	},
	aura = { Fill = rgb(255, 220, 140), Outline = rgb(255, 250, 220), FillT = 0.74, Pulse = { 0.66, 0.82, 0.4 },
		Glint = { rgb(255, 250, 220), rgb(255, 190, 80) }, Radiance = rgb(255, 200, 100), Light = { rgb(255, 210, 130), 2.6, 10 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(0, 0.108, -2.45), Color = rgb(255, 200, 90), Kind = "Fire", Size = 0.3, Dir = Enum.NormalId.Front, LightBrightness = 2.4, LightRange = 5, Pulse = 0.9 },
			{ Pos = V(0, 0.33, -0.1), Color = rgb(255, 240, 180), Kind = "Glow", Size = 0.45, LightBrightness = 2, LightRange = 4, Pulse = 0.4 },
			{ Pos = V(0, 0.9, 1.1), Color = rgb(255, 220, 140), Kind = "Flare", Size = 0.22, Light = false },
		} },
}) }

-- ─── SMG-07 Spectre premium shells (Tripo, fitted with fit_spectre.py, 2026-11-16) ──────────────
-- the Spectre is ~1.2 studs long, so its glint volume is sized to it (spec.vol)
local SPECTRE_VOL = { Vector3.new(0.32, 0.75, 1.6), CFrame.new(0, -0.05, -0.12) }

-- EPIC — Plague Doctor: leather beak mask, brass, three bubbling acid vials; the strap swings
KITS.Plague = { Spectre = shell({
	folder = "Plague_Spectre", vol = SPECTRE_VOL,
	anims = { Strap = { Kind = "Sway", Pivot = V(0, -0.026, 0.591), Axis = V(1, 0, 0), Amp = 12, Speed = 0.7 } },
	aura = { Fill = rgb(110, 255, 60), Outline = rgb(200, 255, 150), FillT = 0.8, Pulse = { 0.72, 0.88, 0.5 },
		Glint = { rgb(210, 255, 170), rgb(90, 220, 40) }, Radiance = rgb(90, 220, 40), Light = { rgb(140, 255, 80), 1.8, 6 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(0, 0.075, 0.141), Color = rgb(110, 255, 50), Kind = "Glow", Size = 0.3, LightBrightness = 1.6, LightRange = 3, Pulse = 0.8 },
			{ Pos = V(0.08, -0.023, -0.722), Color = rgb(130, 255, 70), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(-0.08, -0.023, -0.722), Color = rgb(130, 255, 70), Kind = "Flare", Size = 0.1, Light = false },
		} },
}) }

-- MYTHIC — Frost Fenrir: the bound ice wolf; the jaw works, the broken chain swings
KITS.Fenrir = { Spectre = shell({
	folder = "Fenrir_Spectre", vol = SPECTRE_VOL,
	anims = {
		Jaw = { Kind = "Flap", Pivot = V(0, 0.083, -0.494), Axis = V(-1, 0, 0), Amp = 12, Speed = 0.35 },
		Chain = { Kind = "Sway", Pivot = V(0, -0.128, 0.128), Axis = V(1, 0, 0), Amp = 10, Speed = 0.6, Phase = 0.4 },
	},
	aura = { Fill = rgb(130, 200, 255), Outline = rgb(225, 245, 255), FillT = 0.8, Pulse = { 0.72, 0.88, 0.35 },
		Glint = { rgb(240, 250, 255), rgb(120, 190, 255) }, Radiance = rgb(110, 180, 255), Light = { rgb(150, 210, 255), 2, 7 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0.1, 0.198, -0.686), Color = rgb(150, 230, 255), Kind = "Flare", Size = 0.12, LightBrightness = 1.2, LightRange = 2, Pulse = 0.5 },
			{ Pos = V(-0.1, 0.198, -0.686), Color = rgb(150, 230, 255), Kind = "Flare", Size = 0.12, Light = false },
			{ Pos = V(0, 0.062, -0.70), Color = rgb(140, 210, 255), Kind = "Glow", Size = 0.25, Light = false, Pulse = 0.6 },
		} },
}) }

-- LEGENDARY — Anubis Eternal: obsidian jackal, gold and lapis; the jaw works, the ankh swings, the Eye of Horus glows
KITS.Anubis = { Spectre = shell({
	folder = "Anubis_Spectre", vol = SPECTRE_VOL,
	anims = {
		Jaw = { Kind = "Flap", Pivot = V(0, 0.057, -0.484), Axis = V(-1, 0, 0), Amp = 10, Speed = 0.3 },
		Ankh = { Kind = "Sway", Pivot = V(0, -0.29, 0.279), Axis = V(1, 0, 0), Amp = 14, Speed = 0.8 },
	},
	aura = { Fill = rgb(255, 200, 90), Outline = rgb(130, 165, 255), FillT = 0.8, Pulse = { 0.72, 0.86, 0.3 },
		Glint = { rgb(255, 240, 190), rgb(70, 110, 255) }, Radiance = rgb(255, 190, 80), Light = { rgb(255, 210, 130), 2, 7 },
		Spots = {
			{ Pos = V(0, 0.13, -0.014), Color = rgb(80, 150, 255), Kind = "Glow", Size = 0.32, LightBrightness = 1.6, LightRange = 3, Pulse = 0.4 },
			{ Pos = V(0.06, 0.154, -0.659), Color = rgb(255, 210, 90), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(-0.06, 0.154, -0.659), Color = rgb(255, 210, 90), Kind = "Flare", Size = 0.1, Light = false },
		} },
}) }

-- EXCLUSIVE — Calavera // Dia de Muertos: sugar skull, marigolds, lit candles; the tassels swing, candles flicker
KITS.Calavera = { Spectre = shell({
	folder = "Calavera_Spectre", vol = SPECTRE_VOL,
	anims = { Tassels = { Kind = "Sway", Pivot = V(0, 0.04, 0.37), Axis = V(1, 0, 0.2), Amp = 12, Speed = 0.7 } },
	aura = { Fill = rgb(255, 150, 50), Outline = rgb(255, 130, 215), FillT = 0.82, Pulse = { 0.74, 0.88, 0.35 },
		Glint = { rgb(255, 230, 160), rgb(255, 90, 190) }, Radiance = rgb(255, 140, 60), Light = { rgb(255, 170, 80), 1.8, 6 }, LightPulse = 0.9,
		Spots = {
			{ Pos = V(0, 0.44, -0.449), Color = rgb(255, 170, 60), Kind = "Fire", Size = 0.06, Light = false },
			{ Pos = V(0, 0.44, -0.379), Color = rgb(255, 170, 60), Kind = "Fire", Size = 0.06, Light = false },
			{ Pos = V(0, 0.43, 0.021), Color = rgb(255, 170, 60), Kind = "Fire", Size = 0.06, LightBrightness = 1.4, LightRange = 3, Pulse = 1.2 },
			{ Pos = V(0, 0.44, 0.157), Color = rgb(255, 170, 60), Kind = "Fire", Size = 0.06, Light = false },
			{ Pos = V(0, 0.43, 0.243), Color = rgb(255, 170, 60), Kind = "Fire", Size = 0.06, Light = false },
			{ Pos = V(0.04, 0.157, -0.673), Color = rgb(255, 130, 30), Kind = "Flare", Size = 0.09, Light = false },
			{ Pos = V(-0.04, 0.157, -0.673), Color = rgb(255, 130, 30), Kind = "Flare", Size = 0.09, Light = false },
		} },
}) }

-- GODLY — Wraith King: hooded, crowned spectre with a caged soul-flame; the ghost cloak sways (translucent)
KITS.Wraith = { Spectre = shell({
	-- 2026-11-17: the Tripo export came in twisted 8.5 deg about Y; the Wraith_Spectre RootCFs were
	-- straightened about the muzzle (backup: ServerStorage._WraithSpectreBackup_20261117)
	folder = "Wraith_Spectre", vol = SPECTRE_VOL,
	anims = { Cloak = { Kind = "Sway", Pivot = V(0, 0.071, 0.403), Axis = V(0.960, 0, 0.345), Amp = 8, Speed = 0.45 } },
	aura = { Fill = rgb(150, 110, 255), Outline = rgb(235, 225, 255), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(245, 240, 255), rgb(150, 100, 255) }, Radiance = rgb(140, 90, 255), Light = { rgb(190, 160, 255), 2.4, 8 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(0, 0.071, -0.043), Color = rgb(235, 225, 255), Kind = "Glow", Size = 0.35, LightBrightness = 2, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0.05, 0.12, -0.581), Color = rgb(215, 190, 255), Kind = "Flare", Size = 0.12, LightBrightness = 1.4, LightRange = 2.5, Pulse = 0.6 },
			{ Pos = V(-0.05, 0.12, -0.581), Color = rgb(215, 190, 255), Kind = "Flare", Size = 0.12, Light = false },
		} },
	extra = function(_ctx, made)
		if made.Cloak then
			made.Cloak.Transparency = 0.3
		end
	end,
}) }

-- ─── SG Breacher premium shells (Tripo, fitted with fit_breacher.py, 2026-11-17) ──────────────
-- The shell's Pump piece carries MovingPart = "Pump", so the viewmodel racks it with the base pump.
local BREACHER_VOL = { Vector3.new(0.42, 0.8, 4.2), CFrame.new(0, 0.02, -0.45) }
local function breacherExtra(more)
	return function(ctx, made, vol)
		if made.Pump then
			made.Pump:SetAttribute("MovingPart", "Pump")
		end
		if more then
			more(ctx, made, vol)
		end
	end
end

-- EPIC — Ironclad Steamworks: copper and brass clockwork, amber furnace window; the pressure gauge wobbles
KITS.Ironclad = { Breacher = shell({
	folder = "Ironclad_Breacher", vol = BREACHER_VOL, extra = breacherExtra(),
	anims = { Gauge = { Kind = "Sway", Pivot = V(0, 0.351, -0.171), Axis = V(0, 0, 1), Amp = 4, Speed = 1.8 } },
	aura = { Fill = rgb(255, 160, 60), Outline = rgb(255, 225, 170), FillT = 0.82, Pulse = { 0.74, 0.88, 0.6 },
		Glint = { rgb(255, 235, 190), rgb(255, 150, 50) }, Radiance = rgb(255, 140, 40), Light = { rgb(255, 170, 80), 1.8, 7 }, LightPulse = 0.6,
		Spots = {
			{ Pos = V(0, 0.134, 0.037), Color = rgb(255, 150, 40), Kind = "Glow", Size = 0.45, LightBrightness = 1.8, LightRange = 4, Pulse = 0.7 },
			{ Pos = V(0, 0.473, -0.164), Color = rgb(255, 190, 90), Kind = "Glow", Size = 0.22, Light = false },
			{ Pos = V(0.12, -0.038, -1.627), Color = rgb(255, 140, 40), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(-0.12, -0.038, -1.357), Color = rgb(255, 140, 40), Kind = "Flare", Size = 0.1, Light = false },
		} },
}) }

-- MYTHIC — Brazen Minotaur: bronze bull's head at the muzzle; the jaw works, the nose ring swings
KITS.Minotaur = { Breacher = shell({
	folder = "Minotaur_Breacher", vol = BREACHER_VOL, extra = breacherExtra(),
	anims = {
		Jaw = { Kind = "Flap", Pivot = V(0, -0.16, -2.061), Axis = V(-1, 0, 0), Amp = 12, Speed = 0.35 },
		Ring = { Kind = "Sway", Pivot = V(0, -0.088, -2.564), Axis = V(1, 0, 0), Amp = 16, Speed = 0.8, Phase = 0.6 },
	},
	aura = { Fill = rgb(255, 70, 30), Outline = rgb(255, 190, 120), FillT = 0.8, Pulse = { 0.72, 0.88, 0.45 },
		Glint = { rgb(255, 220, 160), rgb(255, 60, 20) }, Radiance = rgb(255, 60, 20), Light = { rgb(255, 110, 50), 2, 8 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(0.1, 0.173, -2.293), Color = rgb(255, 40, 20), Kind = "Flare", Size = 0.14, LightBrightness = 1.4, LightRange = 2.5, Pulse = 0.5 },
			{ Pos = V(-0.1, 0.173, -2.293), Color = rgb(255, 40, 20), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(0, -0.208, -2.39), Color = rgb(255, 90, 30), Kind = "Fire", Size = 0.16, Dir = Enum.NormalId.Front, Light = false },
			{ Pos = V(0, 0.195, 0.037), Color = rgb(255, 70, 20), Kind = "Glow", Size = 0.4, LightBrightness = 1.4, LightRange = 3, Pulse = 0.8 },
		} },
}) }

-- LEGENDARY — Gorgon's Gaze: gold Medusa, jade and emerald; the serpent crown sways, her eyes burn
KITS.Gorgon = { Breacher = shell({
	folder = "Gorgon_Breacher", vol = BREACHER_VOL, extra = breacherExtra(),
	anims = {
		Snakes = { Kind = "Sway", Pivot = V(0, 0.293, -0.39), Axis = V(0, 0, 1), Amp = 4, Speed = 0.5 },
		Snakes2 = { Kind = "Sway", Pivot = V(0, 0.293, -0.39), Axis = V(0, 0, 1), Amp = 4, Speed = 0.5 },
	},
	aura = { Fill = rgb(40, 230, 130), Outline = rgb(255, 220, 120), FillT = 0.8, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(255, 240, 180), rgb(40, 230, 120) }, Radiance = rgb(30, 220, 120), Light = { rgb(80, 255, 160), 2, 8 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0, 0.135, -0.339), Color = rgb(60, 255, 150), Kind = "Glow", Size = 0.4, LightBrightness = 2, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0.09, 0.149, -2.512), Color = rgb(80, 255, 160), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(-0.09, 0.149, -2.512), Color = rgb(80, 255, 160), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(0, 0.054, 0.12), Color = rgb(40, 230, 120), Kind = "Glow", Size = 0.3, Light = false },
		} },
}) }

-- EXCLUSIVE — Krampus // Yule Night: horned goat demon, crimson lacquer, pine fur; bells and lantern swing
KITS.Krampus = { Breacher = shell({
	folder = "Krampus_Breacher", vol = BREACHER_VOL, extra = breacherExtra(),
	anims = {
		Bells = { Kind = "Sway", Pivot = V(0, -0.303, -1.598), Axis = V(1, 0, 0), Amp = 10, Speed = 0.9 },
		Lantern = { Kind = "Sway", Pivot = V(0, -0.397, 1.548), Axis = V(1, 0, 0.2), Amp = 12, Speed = 0.7, Phase = 0.5 },
	},
	aura = { Fill = rgb(255, 40, 60), Outline = rgb(220, 255, 230), FillT = 0.82, Pulse = { 0.74, 0.88, 0.35 },
		Glint = { rgb(240, 250, 255), rgb(255, 60, 70) }, Radiance = rgb(255, 50, 60), Light = { rgb(255, 120, 110), 1.8, 7 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(0, -0.624, 1.548), Color = rgb(255, 180, 80), Kind = "Fire", Size = 0.08, LightBrightness = 1.6, LightRange = 3, Pulse = 1.2 },
			{ Pos = V(0.08, 0.186, -0.816), Color = rgb(255, 30, 30), Kind = "Flare", Size = 0.12, LightBrightness = 1.2, LightRange = 2, Pulse = 0.6 },
			{ Pos = V(-0.08, 0.186, -0.816), Color = rgb(255, 30, 30), Kind = "Flare", Size = 0.12, Light = false },
			{ Pos = V(0, 0.101, 0.037), Color = rgb(60, 255, 120), Kind = "Glow", Size = 0.3, Light = false },
		} },
}) }

-- GODLY — Cerberus, Warden of Hades: three hound heads, obsidian and gold, azure hellfire; jaw works, chain swings
KITS.Cerberus = { Breacher = shell({
	folder = "Cerberus_Breacher", vol = BREACHER_VOL, extra = breacherExtra(),
	anims = {
		Jaw = { Kind = "Flap", Pivot = V(0, -0.126, -2.229), Axis = V(-1, 0, 0), Amp = 12, Speed = 0.4 },
		Chain = { Kind = "Sway", Pivot = V(0, -0.073, -1.625), Axis = V(1, 0, 0), Amp = 12, Speed = 0.7, Phase = 0.4 },
	},
	aura = { Fill = rgb(60, 160, 255), Outline = rgb(255, 215, 120), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(230, 245, 255), rgb(60, 150, 255) }, Radiance = rgb(40, 130, 255), Light = { rgb(110, 190, 255), 2.4, 9 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(0, 0.155, -2.437), Color = rgb(70, 170, 255), Kind = "Fire", Size = 0.28, Dir = Enum.NormalId.Front, LightBrightness = 2.2, LightRange = 5, Pulse = 0.9 },
			{ Pos = V(0.1, 0.41, -2.236), Color = rgb(170, 230, 255), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(-0.1, 0.41, -2.236), Color = rgb(170, 230, 255), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(0, 0.22, 0.254), Color = rgb(60, 160, 255), Kind = "Glow", Size = 0.45, LightBrightness = 1.6, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, 0.073, 1.528), Color = rgb(120, 200, 255), Kind = "Flare", Size = 0.1, Light = false },
		} },
}) }

-- ─── LR Longshot premium shells (Tripo, fitted with fit_longshot.py, 2026-11-17) ──────────────
-- One shot at a time, so these beams can be heavier than the shotgun's. Rings spin about the lateral axis.
local LONGSHOT_VOL = { Vector3.new(0.36, 0.9, 5.0), CFrame.new(0, -0.05, -0.85) }

-- EPIC — Strix Nightwatch: armoured night owl on the scope; the owl head tilts
KITS.Strix = { Longshot = shell({
	folder = "Strix_Longshot", vol = LONGSHOT_VOL, adsFade = { "Owl" },
	anims = { Owl = { Kind = "Sway", Pivot = V(0, 0.19, 0.082), Axis = V(0, 0, 1), Amp = 6, Speed = 0.3 } },
	aura = { Fill = rgb(90, 140, 255), Outline = rgb(210, 230, 255), FillT = 0.82, Pulse = { 0.74, 0.88, 0.35 },
		Glint = { rgb(230, 240, 255), rgb(110, 160, 255) }, Radiance = rgb(80, 130, 255), Light = { rgb(140, 180, 255), 1.8, 7 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0.06, 0.326, 0.07), Color = rgb(255, 180, 70), Kind = "Flare", Size = 0.12, LightBrightness = 1.2, LightRange = 2.5, Pulse = 0.5 },
			{ Pos = V(-0.06, 0.326, 0.07), Color = rgb(255, 180, 70), Kind = "Flare", Size = 0.12, Light = false },
			{ Pos = V(0, -0.031, -1.749), Color = rgb(120, 180, 255), Kind = "Glow", Size = 0.35, LightBrightness = 1.2, LightRange = 3, Pulse = 0.6 },
			{ Pos = V(0, 0.03, -3.308), Color = rgb(140, 200, 255), Kind = "Glow", Size = 0.2, Light = false },
		} },
}) }

-- MYTHIC — Sabretooth Primeval: black-chrome sabre-tooth skull muzzle, amber ribcage core; the jaw works
KITS.Sabretooth = { Longshot = shell({
	folder = "Sabretooth_Longshot", vol = LONGSHOT_VOL,
	anims = { Jaw = { Kind = "Flap", Pivot = V(0, -0.115, -2.533), Axis = V(-1, 0, 0), Amp = 10, Speed = 0.35 } },
	aura = { Fill = rgb(255, 130, 30), Outline = rgb(255, 225, 170), FillT = 0.8, Pulse = { 0.72, 0.88, 0.45 },
		Glint = { rgb(255, 230, 170), rgb(255, 110, 20) }, Radiance = rgb(255, 110, 20), Light = { rgb(255, 150, 60), 2, 8 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(0.06, 0.087, -2.772), Color = rgb(255, 120, 30), Kind = "Flare", Size = 0.13, LightBrightness = 1.4, LightRange = 2.5, Pulse = 0.5 },
			{ Pos = V(-0.06, 0.087, -2.772), Color = rgb(255, 120, 30), Kind = "Flare", Size = 0.13, Light = false },
			{ Pos = V(0, 0.02, -1.38), Color = rgb(255, 150, 40), Kind = "Glow", Size = 0.55, LightBrightness = 2, LightRange = 4, Pulse = 0.8 },
		} },
}) }

-- LEGENDARY — Jaguar Sun Warrior: obsidian and gold, sun-disc reactor; the gold ring spins, hard-light fins sway
KITS.Jaguar = { Longshot = shell({
	folder = "Jaguar_Longshot", vol = LONGSHOT_VOL,
	anims = {
		SunRing = { Kind = "Spin", Pivot = V(0, -0.001, -0.353), Axis = V(1, 0, 0), Speed = 0.6 },
		Fins = { Kind = "Sway", Pivot = V(0, 0.109, 0.289), Axis = V(1, 0, 0), Amp = 6, Speed = 0.5 },
	},
	aura = { Fill = rgb(40, 230, 210), Outline = rgb(255, 215, 120), FillT = 0.8, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(255, 240, 180), rgb(40, 230, 210) }, Radiance = rgb(255, 190, 80), Light = { rgb(120, 255, 230), 2, 8 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0, -0.004, -0.36), Color = rgb(170, 255, 240), Kind = "Glow", Size = 0.45, LightBrightness = 2, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0.05, 0.12, -3.278), Color = rgb(60, 240, 220), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(-0.05, 0.12, -3.278), Color = rgb(60, 240, 220), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(0, 0.437, 0.633), Color = rgb(80, 255, 230), Kind = "Glow", Size = 0.25, Light = false },
		} },
}) }

-- GODLY — The Watcher Beyond: eldritch eye in the receiver, tendrils, small eyes; the gold eye ring spins
KITS.Watcher = { Longshot = shell({
	folder = "Watcher_Longshot", vol = LONGSHOT_VOL,
	anims = { EyeRing = { Kind = "Spin", Pivot = V(0, -0.025, -0.389), Axis = V(1, 0, 0), Speed = -0.4 } },
	aura = { Fill = rgb(40, 220, 210), Outline = rgb(255, 90, 220), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(220, 255, 250), rgb(255, 80, 210) }, Radiance = rgb(30, 200, 200), Light = { rgb(90, 240, 225), 2.4, 9 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(0, -0.021, -0.386), Color = rgb(60, 255, 230), Kind = "Glow", Size = 0.5, LightBrightness = 2.4, LightRange = 5, Pulse = 0.45 },
			{ Pos = V(0, 0.156, -1.117), Color = rgb(60, 255, 230), Kind = "Flare", Size = 0.11, Light = false },
			{ Pos = V(0, 0.122, -2.423), Color = rgb(255, 80, 210), Kind = "Flare", Size = 0.11, Light = false },
			{ Pos = V(0, 0.03, -3.287), Color = rgb(60, 240, 220), Kind = "Glow", Size = 0.3, LightBrightness = 1.4, LightRange = 3, Pulse = 0.9 },
			{ Pos = V(0, -0.066, 1.335), Color = rgb(255, 80, 210), Kind = "Flare", Size = 0.09, Light = false },
		} },
}) }

-- EXCLUSIVE — Heartbreaker // Valentine's: cracked crystal heart reactor, rose-gold arrowhead; the heart rocks to a heartbeat glow
KITS.Heartbreaker = { Longshot = shell({
	folder = "Heartbreaker_Longshot", vol = LONGSHOT_VOL,
	anims = { Heart = { Kind = "Sway", Pivot = V(0, -0.056, -0.32), Axis = V(1, 0, 0), Amp = 6, Speed = 1.2 } },
	aura = { Fill = rgb(255, 80, 160), Outline = rgb(255, 220, 235), FillT = 0.8, Pulse = { 0.72, 0.88, 1.2 },
		Glint = { rgb(255, 235, 245), rgb(255, 60, 140) }, Radiance = rgb(255, 60, 140), Light = { rgb(255, 120, 180), 2, 8 }, LightPulse = 1.2,
		Spots = {
			{ Pos = V(0, -0.057, -0.323), Color = rgb(255, 70, 150), Kind = "Glow", Size = 0.55, LightBrightness = 2.2, LightRange = 4, Pulse = 1.2 },
			{ Pos = V(0, 0.03, -3.298), Color = rgb(255, 120, 190), Kind = "Glow", Size = 0.22, Light = false },
			{ Pos = V(0, 0.134, 0.452), Color = rgb(255, 90, 160), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(0, 0.314, -0.486), Color = rgb(255, 150, 200), Kind = "Flare", Size = 0.09, Light = false },
		} },
}) }

-- ─── SM-21 Riptide premium shells (Tripo, fitted with fit_riptide.py, 2026-11-18) ──────────────
-- 1000 RPM SMG: beams are kept slim. Sea theme. Features are modelled on the gun's left side (-X).
local RIPTIDE_VOL = { Vector3.new(0.3, 0.6, 3.2), CFrame.new(0, 0, -0.2) }

-- EPIC — Abyss Diver: brass-and-gunmetal diving helmet on the receiver, amber porthole; the helmet turns
KITS.Diver = { Riptide = shell({
	folder = "Diver_Riptide", vol = RIPTIDE_VOL,
	anims = {
		Helmet = { Kind = "Sway", Pivot = V(0, 0.287, 0.038), Axis = V(0, 1, 0), Amp = 9, Speed = 0.25 },
		Helmet2 = { Kind = "Sway", Pivot = V(0, 0.287, 0.038), Axis = V(0, 1, 0), Amp = 9, Speed = 0.25 },
	},
	aura = { Fill = rgb(255, 170, 60), Outline = rgb(150, 230, 225), FillT = 0.84, Pulse = { 0.76, 0.9, 0.4 },
		Glint = { rgb(255, 235, 190), rgb(60, 200, 190) }, Radiance = rgb(255, 160, 50), Light = { rgb(255, 185, 90), 1.6, 6 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(-0.15, 0.447, 0.033), Color = rgb(255, 180, 60), Kind = "Glow", Size = 0.3, LightBrightness = 1.4, LightRange = 3, Pulse = 0.5 },
			{ Pos = V(-0.13, 0.434, -0.195), Color = rgb(255, 190, 80), Kind = "Flare", Size = 0.08, Light = false },
			{ Pos = V(0, 0.073, -1.696), Color = rgb(90, 220, 210), Kind = "Glow", Size = 0.22, Light = false },
		} },
}) }

-- MYTHIC — Hammerhead Apex: gunmetal shark head forms the front, red eyes and gills; the jaw works
KITS.Hammerhead = { Riptide = shell({
	folder = "Hammerhead_Riptide", vol = RIPTIDE_VOL,
	anims = { Jaw = { Kind = "Flap", Pivot = V(0, -0.169, -0.998), Axis = V(-1, 0, 0), Amp = 10, Speed = 0.35 } },
	aura = { Fill = rgb(255, 40, 70), Outline = rgb(255, 190, 200), FillT = 0.82, Pulse = { 0.74, 0.88, 0.45 },
		Glint = { rgb(255, 210, 220), rgb(255, 40, 70) }, Radiance = rgb(230, 30, 60), Light = { rgb(255, 70, 90), 1.8, 7 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(0.12, 0.06, -1.169), Color = rgb(255, 40, 80), Kind = "Flare", Size = 0.11, LightBrightness = 1.2, LightRange = 2.5, Pulse = 0.5 },
			{ Pos = V(-0.12, 0.06, -1.169), Color = rgb(255, 40, 80), Kind = "Flare", Size = 0.11, Light = false },
			{ Pos = V(0, -0.111, -0.722), Color = rgb(255, 50, 80), Kind = "Glow", Size = 0.4, LightBrightness = 1.4, LightRange = 3, Pulse = 0.7 },
			{ Pos = V(0, -0.14, -1.25), Color = rgb(255, 60, 70), Kind = "Glow", Size = 0.2, Light = false },
		} },
}) }

-- LEGENDARY — Tidecaller of Atlantis: white-and-gold, glyph reactor ring with an aquamarine core, trident muzzle; the ring spins
KITS.Atlantis = { Riptide = shell({
	folder = "Atlantis_Riptide", vol = RIPTIDE_VOL,
	anims = { Ring = { Kind = "Spin", Pivot = V(0, 0.047, 0.096), Axis = V(1, 0, 0), Speed = 0.5 } },
	aura = { Fill = rgb(40, 230, 200), Outline = rgb(255, 215, 130), FillT = 0.8, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(255, 240, 190), rgb(40, 230, 200) }, Radiance = rgb(255, 195, 90), Light = { rgb(110, 255, 225), 2, 7 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0, 0.049, 0.096), Color = rgb(120, 255, 230), Kind = "Glow", Size = 0.42, LightBrightness = 2, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, 0.044, -1.80), Color = rgb(60, 240, 220), Kind = "Glow", Size = 0.24, LightBrightness = 1.2, LightRange = 3, Pulse = 0.8 },
			{ Pos = V(0.04, 0.09, -1.70), Color = rgb(255, 220, 140), Kind = "Flare", Size = 0.08, Light = false },
			{ Pos = V(-0.04, 0.0, -1.70), Color = rgb(255, 220, 140), Kind = "Flare", Size = 0.08, Light = false },
		} },
}) }

-- EXCLUSIVE — Sunset Surf // Summer Festival: pearl-white and turquoise, hard-light sunset over a chrome wave; the seashell charm swings
KITS.Sunset = { Riptide = shell({
	folder = "Sunset_Riptide", vol = RIPTIDE_VOL,
	anims = { Charm = { Kind = "Sway", Pivot = V(0, -0.048, 0.702), Axis = V(1, 0, 0), Amp = 14, Speed = 0.8 } },
	aura = { Fill = rgb(255, 120, 80), Outline = rgb(120, 240, 230), FillT = 0.82, Pulse = { 0.74, 0.88, 0.4 },
		Glint = { rgb(255, 230, 190), rgb(60, 220, 210) }, Radiance = rgb(255, 130, 70), Light = { rgb(255, 170, 110), 1.8, 7 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(0, -0.001, 0.103), Color = rgb(255, 190, 110), Kind = "Glow", Size = 0.45, LightBrightness = 1.8, LightRange = 4, Pulse = 0.4 },
			{ Pos = V(0, 0.02, -1.75), Color = rgb(80, 230, 220), Kind = "Glow", Size = 0.2, Light = false },
			{ Pos = V(0, -0.16, 0.70), Color = rgb(255, 225, 200), Kind = "Flare", Size = 0.07, Light = false },
		} },
}) }

-- GODLY — Kraken, Lord of the Abyss: mechanical kraken head with cyan eyes, tentacles round the barrel and mag; the front tentacle sways
KITS.Kraken = { Riptide = shell({
	folder = "Kraken_Riptide", vol = RIPTIDE_VOL,
	anims = { Tentacle = { Kind = "Sway", Pivot = V(0, 0.075, -1.289), Axis = V(0, 0, 1), Amp = 8, Speed = 0.4 } },
	aura = { Fill = rgb(40, 220, 255), Outline = rgb(180, 120, 255), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(210, 250, 255), rgb(160, 90, 255) }, Radiance = rgb(30, 190, 255), Light = { rgb(90, 220, 255), 2.4, 8 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(-0.15, -0.012, -0.225), Color = rgb(60, 240, 255), Kind = "Flare", Size = 0.13, LightBrightness = 1.6, LightRange = 3, Pulse = 0.45 },
			{ Pos = V(-0.15, -0.012, -0.044), Color = rgb(60, 240, 255), Kind = "Flare", Size = 0.13, Light = false },
			{ Pos = V(0, -0.1, -0.13), Color = rgb(60, 220, 255), Kind = "Glow", Size = 0.5, LightBrightness = 2.2, LightRange = 4, Pulse = 0.45 },
			{ Pos = V(0, 0.0, -1.80), Color = rgb(170, 110, 255), Kind = "Glow", Size = 0.24, LightBrightness = 1.2, LightRange = 3, Pulse = 0.9 },
			{ Pos = V(0, -0.75, -0.29), Color = rgb(60, 230, 255), Kind = "Flare", Size = 0.08, Light = false },
		} },
}) }

-- ─── LM-60 Bulwark premium shells (Tripo, fitted with fit_bulwark.py, 2026-11-18) ──────────────
-- 700 RPM LMG: beams a touch heavier than the Riptide's. Heavy armour / big beasts. Features on the gun's left side (-X).
-- The base rotary Barrels are hidden under the shells (the shells' shrouds don't spin).
local BULWARK_VOL = { Vector3.new(0.5, 0.7, 5.0), CFrame.new(0, -0.05, -1.0) }

-- EPIC — Riot Warden: riot-trooper helmet in the receiver, ice-white visor, red/blue light bar
KITS.Warden = { Bulwark = shell({
	folder = "Warden_Bulwark", vol = BULWARK_VOL,
	anims = {},
	aura = { Fill = rgb(120, 170, 255), Outline = rgb(235, 245, 255), FillT = 0.84, Pulse = { 0.76, 0.9, 0.5 },
		Glint = { rgb(235, 245, 255), rgb(120, 170, 255) }, Radiance = rgb(110, 160, 255), Light = { rgb(170, 200, 255), 1.6, 7 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(0, 0.436, -0.645), Color = rgb(40, 110, 255), Kind = "Flare", Size = 0.16, LightBrightness = 1.6, LightRange = 3, Pulse = 1.6 },
			{ Pos = V(0, 0.436, -0.43), Color = rgb(255, 40, 50), Kind = "Flare", Size = 0.16, LightBrightness = 1.6, LightRange = 3, Pulse = 1.1 },
			{ Pos = V(-0.3, 0.005, -0.59), Color = rgb(220, 240, 255), Kind = "Glow", Size = 0.3, Light = false },
			{ Pos = V(0, -0.029, -3.5), Color = rgb(170, 210, 255), Kind = "Glow", Size = 0.25, Light = false },
		} },
}) }

-- MYTHIC — Rhino Juggernaut: armoured rhino head over the barrels, electric-yellow eyes and seams; the head nods
KITS.Rhino = { Bulwark = shell({
	folder = "Rhino_Bulwark", vol = BULWARK_VOL,
	anims = { Head = { Kind = "Flap", Pivot = V(0, -0.12, -1.208), Axis = V(-1, 0, 0), Amp = 4, Speed = 0.3 } },
	aura = { Fill = rgb(220, 230, 40), Outline = rgb(255, 250, 190), FillT = 0.82, Pulse = { 0.74, 0.88, 0.45 },
		Glint = { rgb(255, 250, 190), rgb(220, 230, 40) }, Radiance = rgb(210, 220, 30), Light = { rgb(240, 240, 90), 1.8, 8 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(-0.3, -0.12, -1.521), Color = rgb(240, 250, 60), Kind = "Flare", Size = 0.13, LightBrightness = 1.4, LightRange = 3, Pulse = 0.5 },
			{ Pos = V(0.3, -0.12, -1.521), Color = rgb(240, 250, 60), Kind = "Flare", Size = 0.13, Light = false },
			{ Pos = V(0, 0.05, -0.3), Color = rgb(230, 240, 60), Kind = "Glow", Size = 0.45, LightBrightness = 1.4, LightRange = 4, Pulse = 0.6 },
			{ Pos = V(0, -0.016, -3.5), Color = rgb(240, 240, 120), Kind = "Glow", Size = 0.25, Light = false },
		} },
}) }

-- LEGENDARY — Oni Warlord: black-and-violet armour, oni mask in a gold tomoe ring, war-drum magazine; the ring spins
KITS.Oni = { Bulwark = shell({
	folder = "Oni_Bulwark", vol = BULWARK_VOL,
	anims = { Ring = { Kind = "Spin", Pivot = V(0, 0.018, -0.495), Axis = V(1, 0, 0), Speed = 0.35 } },
	aura = { Fill = rgb(170, 80, 255), Outline = rgb(255, 215, 130), FillT = 0.8, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(255, 225, 160), rgb(170, 80, 255) }, Radiance = rgb(150, 60, 255), Light = { rgb(190, 120, 255), 2, 8 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(-0.27, -0.01, -0.53), Color = rgb(200, 90, 255), Kind = "Flare", Size = 0.12, LightBrightness = 1.6, LightRange = 3, Pulse = 0.45 },
			{ Pos = V(-0.27, -0.01, -0.465), Color = rgb(200, 90, 255), Kind = "Flare", Size = 0.12, Light = false },
			{ Pos = V(0, 0.018, -0.495), Color = rgb(170, 90, 255), Kind = "Glow", Size = 0.5, LightBrightness = 1.8, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, -0.016, -3.52), Color = rgb(200, 140, 255), Kind = "Glow", Size = 0.25, Light = false },
		} },
}) }

-- EXCLUSIVE — Jack-o'-Lantern // Halloween Night: carved-pumpkin drum, black and pumpkin-orange, hanging lantern; the lantern swings
KITS.Lantern = { Bulwark = shell({
	folder = "Lantern_Bulwark", vol = BULWARK_VOL,
	anims = { Charm = { Kind = "Sway", Pivot = V(0, -0.366, 0.834), Axis = V(1, 0, 0), Amp = 14, Speed = 0.8 } },
	aura = { Fill = rgb(255, 130, 30), Outline = rgb(170, 255, 80), FillT = 0.82, Pulse = { 0.74, 0.88, 0.5 },
		Glint = { rgb(255, 210, 140), rgb(150, 255, 60) }, Radiance = rgb(255, 120, 20), Light = { rgb(255, 150, 60), 1.8, 8 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(-0.38, -0.70, -0.62), Color = rgb(255, 150, 30), Kind = "Glow", Size = 0.5, LightBrightness = 2, LightRange = 4, Pulse = 0.7 },
			{ Pos = V(0, -0.58, 0.834), Color = rgb(255, 170, 60), Kind = "Flare", Size = 0.08, Light = false },
			{ Pos = V(0, -0.016, -3.5), Color = rgb(150, 255, 60), Kind = "Glow", Size = 0.24, Light = false },
		} },
}) }

-- GODLY — Behemoth, World Breaker: obsidian and molten gold, beast head with great curved tusks, reactor-core drum; the tusks sway
KITS.Behemoth = { Bulwark = shell({
	folder = "Behemoth_Bulwark", vol = BULWARK_VOL,
	anims = { Tusk = { Kind = "Flap", Pivot = V(0, -0.205, -0.985), Axis = V(-1, 0, 0), Amp = 3, Speed = 0.3 } },
	aura = { Fill = rgb(255, 200, 80), Outline = rgb(255, 245, 210), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(255, 250, 225), rgb(255, 190, 60) }, Radiance = rgb(255, 180, 40), Light = { rgb(255, 215, 120), 2.4, 9 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(-0.3, 0.089, -0.901), Color = rgb(255, 240, 180), Kind = "Flare", Size = 0.14, LightBrightness = 1.8, LightRange = 3, Pulse = 0.45 },
			{ Pos = V(0.3, 0.089, -0.901), Color = rgb(255, 240, 180), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(-0.37, -0.742, -0.531), Color = rgb(255, 245, 210), Kind = "Glow", Size = 0.45, LightBrightness = 2.2, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, 0.1, -0.3), Color = rgb(255, 200, 80), Kind = "Glow", Size = 0.5, Light = false },
			{ Pos = V(0, -0.016, -3.5), Color = rgb(255, 220, 140), Kind = "Glow", Size = 0.3, LightBrightness = 1.2, LightRange = 3, Pulse = 0.9 },
		} },
}) }

-- ─── HC-50 Verdict premium shells (Tripo, fitted with fit_verdict.py, 2026-11-18) ──────────────
-- Space-western judgement set. Features on the gun's left side (-X). The Cyl piece (drum) is centred on the
-- base cylinder's spin axis and carries MovingPart = "Cylinder", so it swings out and spins with the reload.
-- The shells have no Mag piece, so the base speed-loader rounds stay visible (they ride the reload).
local VERDICT_VOL = { Vector3.new(0.26, 0.5, 1.6), CFrame.new(0, -0.08, -0.25) }
local function verdictExtra(more)
	return function(ctx, made, vol)
		if made.Cyl then
			made.Cyl:SetAttribute("MovingPart", "Cylinder")
		end
		local mag = ctx.model:FindFirstChild("Magazine")
		if mag then
			for _, d in mag:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("SkinHiddenT") ~= nil then
					d.Transparency = d:GetAttribute("SkinHiddenT")
				end
			end
		end
		if more then
			more(ctx, made, vol)
		end
	end
end

-- EPIC — Star Marshal: black and chrome, a sheriff star with an ice-blue core; the star turns
KITS.Marshal = { Verdict = shell({
	folder = "Marshal_Verdict", vol = VERDICT_VOL, extra = verdictExtra(),
	anims = { Star = { Kind = "Spin", Pivot = V(0, -0.036, -0.017), Axis = V(1, 0, 0), Speed = 0.6 } },
	aura = { Fill = rgb(110, 200, 255), Outline = rgb(230, 245, 255), FillT = 0.84, Pulse = { 0.76, 0.9, 0.5 },
		Glint = { rgb(235, 248, 255), rgb(110, 200, 255) }, Radiance = rgb(90, 180, 255), Light = { rgb(150, 215, 255), 1.4, 5 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(-0.11, -0.037, -0.015), Color = rgb(90, 220, 255), Kind = "Glow", Size = 0.22, LightBrightness = 1.4, LightRange = 2.5, Pulse = 0.7 },
			{ Pos = V(-0.1, -0.04, -0.425), Color = rgb(120, 230, 255), Kind = "Flare", Size = 0.07, Light = false },
			{ Pos = V(0, 0.02, -1.06), Color = rgb(170, 225, 255), Kind = "Glow", Size = 0.14, Light = false },
		} },
}) }

-- MYTHIC — Deathstalker Scorpion: chrome-and-bronze scorpion wrapped round the frame, amber stinger; the tail sways
KITS.Scorpion = { Verdict = shell({
	folder = "Scorpion_Verdict", vol = VERDICT_VOL, extra = verdictExtra(),
	anims = { Tail = { Kind = "Sway", Pivot = V(0, 0.146, 0.224), Axis = V(1, 0, 0), Amp = 6, Speed = 0.5 } },
	aura = { Fill = rgb(255, 160, 30), Outline = rgb(255, 230, 160), FillT = 0.82, Pulse = { 0.74, 0.88, 0.45 },
		Glint = { rgb(255, 235, 180), rgb(255, 150, 20) }, Radiance = rgb(255, 140, 10), Light = { rgb(255, 170, 60), 1.6, 5 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(0, 0.185, -0.205), Color = rgb(255, 180, 30), Kind = "Flare", Size = 0.09, LightBrightness = 1.4, LightRange = 2.5, Pulse = 0.8 },
			{ Pos = V(-0.1, -0.067, -0.114), Color = rgb(255, 150, 30), Kind = "Glow", Size = 0.2, Light = false },
			{ Pos = V(0, 0, -1.06), Color = rgb(255, 190, 80), Kind = "Glow", Size = 0.14, Light = false },
		} },
}) }

-- LEGENDARY — Scales of Judgement: royal blue and gold, blindfolded Lady Justice mask, gavel muzzle; the scales swing
KITS.Justice = { Verdict = shell({
	folder = "Justice_Verdict", vol = VERDICT_VOL, extra = verdictExtra(),
	anims = { Scales = { Kind = "Sway", Pivot = V(0, -0.113, -0.535), Axis = V(1, 0, 0), Amp = 12, Speed = 0.7 } },
	aura = { Fill = rgb(90, 130, 255), Outline = rgb(255, 225, 140), FillT = 0.8, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(255, 235, 170), rgb(110, 150, 255) }, Radiance = rgb(255, 205, 90), Light = { rgb(255, 220, 140), 1.8, 6 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(-0.11, -0.06, 0.088), Color = rgb(255, 240, 200), Kind = "Glow", Size = 0.24, LightBrightness = 1.6, LightRange = 3, Pulse = 0.5 },
			{ Pos = V(0, 0.01, -1.018), Color = rgb(255, 210, 100), Kind = "Glow", Size = 0.18, Light = false },
			{ Pos = V(0, -0.113, -0.535), Color = rgb(255, 220, 120), Kind = "Flare", Size = 0.07, Light = false },
		} },
}) }

-- EXCLUSIVE — Midnight Countdown // New Year's Eve: midnight blue and champagne gold, clock face at midnight; the clock turns
KITS.Countdown = { Verdict = shell({
	folder = "Countdown_Verdict", vol = VERDICT_VOL, extra = verdictExtra(),
	anims = { Clock = { Kind = "Spin", Pivot = V(0, -0.07, -0.315), Axis = V(1, 0, 0), Speed = 0.5 } },
	aura = { Fill = rgb(255, 80, 200), Outline = rgb(255, 230, 160), FillT = 0.82, Pulse = { 0.74, 0.88, 0.5 },
		Glint = { rgb(255, 235, 170), rgb(255, 80, 200) }, Radiance = rgb(255, 200, 90), Light = { rgb(255, 210, 140), 1.6, 5 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(-0.11, -0.07, -0.315), Color = rgb(255, 215, 120), Kind = "Glow", Size = 0.26, LightBrightness = 1.6, LightRange = 3, Pulse = 0.6 },
			{ Pos = V(-0.1, -0.053, -0.65), Color = rgb(255, 70, 200), Kind = "Flare", Size = 0.07, Light = false },
			{ Pos = V(-0.1, -0.17, -0.152), Color = rgb(255, 70, 200), Kind = "Flare", Size = 0.07, Light = false },
			{ Pos = V(0, 0, -1.06), Color = rgb(255, 220, 150), Kind = "Glow", Size = 0.14, Light = false },
		} },
}) }

-- GODLY — Sovereign Lion, King's Verdict: white-gold lion head with a blade mane, black and crimson; the jaw works
KITS.Lion = { Verdict = shell({
	folder = "Lion_Verdict", vol = VERDICT_VOL, extra = verdictExtra(),
	anims = { Jaw = { Kind = "Flap", Pivot = V(0, -0.095, -0.55), Axis = V(-1, 0, 0), Amp = 10, Speed = 0.35 } },
	aura = { Fill = rgb(255, 205, 110), Outline = rgb(255, 245, 215), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(255, 250, 225), rgb(255, 60, 60) }, Radiance = rgb(255, 190, 70), Light = { rgb(255, 215, 130), 2, 6 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(-0.12, -0.02, -0.625), Color = rgb(255, 245, 200), Kind = "Flare", Size = 0.09, LightBrightness = 1.6, LightRange = 2.5, Pulse = 0.45 },
			{ Pos = V(-0.1, -0.125, -0.625), Color = rgb(255, 210, 120), Kind = "Fire", Size = 0.1, Light = false },
			{ Pos = V(-0.06, -0.05, -0.55), Color = rgb(255, 225, 150), Kind = "Glow", Size = 0.32, Light = false },
			{ Pos = V(0, 0, -1.06), Color = rgb(255, 220, 150), Kind = "Glow", Size = 0.18, LightBrightness = 1, LightRange = 2.5, Pulse = 0.9 },
		} },
}) }

-- ─── XB-7 Quill premium shells (Tripo, fitted with fit_quill.py, 2026-11-19) ──────────────
-- Tripo can't model bow strings, so the fit cut them off and quillExtra draws them as glowing Beams.
-- Tracker / Stag: tips sit on the shell's LimbT / LimbB pieces (MovingPart, so they flex with the reload)
-- and meet at a nock on the Root. Raptor: its limbs sit at the rear (static), strings run forward to the head.
local QUILL_VOL = { Vector3.new(0.3, 1.2, 4.4), CFrame.new(0, 0, -0.6) }
local function quillExtra(strings, color, flexLimbs, more)
	return function(ctx, made, vol)
		if flexLimbs then
			if made.LimbT then made.LimbT:SetAttribute("MovingPart", "LimbT") end
			if made.LimbB then made.LimbB:SetAttribute("MovingPart", "LimbB") end
		end
		for i, s in strings do
			local a0 = att(ctx, made[s[1]] or ctx.root, s[2], "String" .. i .. "A")
			local a1 = att(ctx, made[s[3]] or ctx.root, s[4], "String" .. i .. "B")
			local bm = Instance.new("Beam")
			bm.Name = "SkinString"
			bm.Attachment0, bm.Attachment1 = a0, a1
			bm.Color = ColorSequence.new(color)
			bm.LightEmission = 1
			bm.LightInfluence = 0
			bm.Brightness = 3
			bm.Width0, bm.Width1 = 0.022 * ctx.k, 0.022 * ctx.k
			bm.FaceCamera = true
			bm.Segments = 1
			bm.Transparency = NumberSequence.new(0.05)
			bm.Parent = a0.Parent
		end
		if more then
			more(ctx, made, vol)
		end
	end
end

-- EPIC — Recon Tracker: matte black and olive, a radar dish with a green targeting lens; the dish turns
KITS.Tracker = { Quill = shell({
	folder = "Tracker_Quill", vol = QUILL_VOL,
	extra = quillExtra({ { "LimbT", V(0, 1.034, -1.383), "Root", V(0, 0.274, -0.543) }, { "LimbB", V(0, -0.808, -1.414), "Root", V(0, 0.274, -0.543) } }, rgb(110, 255, 150), true),
	anims = { Dish = { Kind = "Spin", Pivot = V(0, 0.564, -0.07), Axis = V(0, 1, 0), Speed = 1.2 } },
	aura = { Fill = rgb(90, 255, 140), Outline = rgb(210, 255, 220), FillT = 0.84, Pulse = { 0.76, 0.9, 0.5 },
		Glint = { rgb(220, 255, 230), rgb(90, 255, 140) }, Radiance = rgb(70, 230, 120), Light = { rgb(130, 255, 170), 1.4, 7 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(-0.07, 0.53, -0.178), Color = rgb(90, 255, 140), Kind = "Glow", Size = 0.25, LightBrightness = 1.4, LightRange = 3, Pulse = 0.8 },
			{ Pos = V(0, 0.108, -2.9), Color = rgb(150, 255, 180), Kind = "Flare", Size = 0.1, Light = false },
		} },
}) }

-- MYTHIC — Raptor Rampage: bronze and black raptor skull at the front, sickle-claw limbs at the rear; the jaw works
KITS.Raptor = { Quill = shell({
	folder = "Raptor_Quill", vol = QUILL_VOL,
	extra = quillExtra({ { "LimbT", V(0, 0.873, -0.548), "Root", V(0, 0.303, -1.814) }, { "LimbB", V(0, -0.722, -0.526), "Root", V(0, -0.061, -1.959) } }, rgb(120, 255, 90), false),
	anims = { Jaw = { Kind = "Flap", Pivot = V(0, -0.048, -2.111), Axis = V(-1, 0, 0), Amp = 10, Speed = 0.35 } },
	aura = { Fill = rgb(110, 255, 70), Outline = rgb(230, 200, 150), FillT = 0.82, Pulse = { 0.74, 0.88, 0.45 },
		Glint = { rgb(230, 255, 200), rgb(110, 255, 70) }, Radiance = rgb(90, 230, 50), Light = { rgb(150, 255, 110), 1.6, 7 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(-0.12, 0.232, -2.111), Color = rgb(120, 255, 80), Kind = "Flare", Size = 0.12, LightBrightness = 1.4, LightRange = 3, Pulse = 0.5 },
			{ Pos = V(0, 0.059, -2.4), Color = rgb(110, 255, 70), Kind = "Glow", Size = 0.3, Light = false },
		} },
}) }

-- GODLY — Celestial Stag, Spirit of the Hunt: white ceramic and gold, teal hard-light antlers, antler-branch limbs; the antlers sway
KITS.Stag = { Quill = shell({
	folder = "Stag_Quill", vol = QUILL_VOL,
	extra = quillExtra({ { "LimbT", V(0, 0.997, -1.295), "Root", V(0, 0.279, -0.406) }, { "LimbB", V(0, -0.766, -1.283), "Root", V(0, 0.279, -0.406) } }, rgb(90, 250, 235), true),
	anims = { Antlers = { Kind = "Sway", Pivot = V(0, 0.357, -0.098), Axis = V(1, 0, 0), Amp = 4, Speed = 0.3 } },
	aura = { Fill = rgb(70, 235, 220), Outline = rgb(255, 230, 160), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(220, 255, 250), rgb(255, 210, 110) }, Radiance = rgb(60, 220, 210), Light = { rgb(140, 255, 240), 2.2, 8 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(-0.15, 0.215, -0.209), Color = rgb(120, 255, 245), Kind = "Flare", Size = 0.12, LightBrightness = 1.6, LightRange = 3, Pulse = 0.45 },
			{ Pos = V(0, 0.75, 0.15), Color = rgb(80, 245, 230), Kind = "Glow", Size = 0.55, LightBrightness = 1.6, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, 0.108, -2.9), Color = rgb(255, 225, 150), Kind = "Glow", Size = 0.25, Light = false },
		} },
}) }

-- ─── BX-3 Helix premium shells (Tripo, fitted with fit_helix.py, 2026-11-20) ──────────────
-- Lab-to-lightning set. 1200 RPM beam rifle: the beam is BeamPulse, so the shells carry the look.
-- Every shell has a Mag piece (the top energy cell) that rides the cell-pop reload.
local HELIX_VOL = { Vector3.new(0.4, 0.8, 3.9), CFrame.new(0, -0.1, -0.5) }

-- EPIC — Containment Breach: clamped containment tank with a magenta plasma specimen, hazard chevrons
KITS.Containment = { Helix = shell({
	folder = "Containment_Helix", vol = HELIX_VOL,
	anims = {},
	aura = { Fill = rgb(255, 60, 220), Outline = rgb(255, 200, 245), FillT = 0.84, Pulse = { 0.76, 0.9, 0.6 },
		Glint = { rgb(255, 210, 250), rgb(255, 60, 220) }, Radiance = rgb(240, 50, 210), Light = { rgb(255, 110, 230), 1.6, 7 }, LightPulse = 0.6,
		Spots = {
			{ Pos = V(0, 0.153, -0.186), Color = rgb(255, 70, 230), Kind = "Glow", Size = 0.45, LightBrightness = 1.8, LightRange = 4, Pulse = 0.9 },
			{ Pos = V(0, 0, -2.40), Color = rgb(255, 120, 240), Kind = "Glow", Size = 0.22, Light = false },
		} },
}) }

-- MYTHIC — Ironhorn Ram: armoured ram head with spiral horns over the coil, electric-cyan lightning; the head nods
local RAM_NOD = { Kind = "Flap", Pivot = V(0, 0.064, -0.532), Axis = V(-1, 0, 0), Amp = 4, Speed = 0.3 }
KITS.Ram = { Helix = shell({
	folder = "Ram_Helix", vol = HELIX_VOL,
	anims = { Head = RAM_NOD, Head2 = RAM_NOD, Head3 = RAM_NOD, Head4 = RAM_NOD },
	aura = { Fill = rgb(40, 220, 255), Outline = rgb(210, 245, 255), FillT = 0.82, Pulse = { 0.74, 0.88, 0.45 },
		Glint = { rgb(210, 250, 255), rgb(40, 220, 255) }, Radiance = rgb(30, 200, 255), Light = { rgb(110, 230, 255), 1.8, 8 }, LightPulse = 0.45,
		Spots = {
			{ Pos = V(-0.15, 0.180, -1.017), Color = rgb(60, 235, 255), Kind = "Flare", Size = 0.12, LightBrightness = 1.4, LightRange = 3, Pulse = 0.5 },
			{ Pos = V(0.15, 0.180, -1.017), Color = rgb(60, 235, 255), Kind = "Flare", Size = 0.12, Light = false },
			{ Pos = V(0, 0.193, -0.118), Color = rgb(60, 220, 255), Kind = "Glow", Size = 0.35, LightBrightness = 1.4, LightRange = 3, Pulse = 0.6 },
			{ Pos = V(0, 0, -2.40), Color = rgb(150, 240, 255), Kind = "Glow", Size = 0.22, Light = false },
		} },
}) }

-- LEGENDARY — Genesis Helix: pearl ceramic and gold, a gold-and-crystal DNA strand round the barrel, seed-of-life orb; the strand spins
local GEN_SPIN = { Kind = "Spin", Pivot = V(0, 0.004, -1.313), Axis = V(0, 0, 1), Speed = 0.8 }
KITS.Genesis = { Helix = shell({
	folder = "Genesis_Helix", vol = HELIX_VOL,
	anims = { Helix = GEN_SPIN, Helix2 = GEN_SPIN },
	aura = { Fill = rgb(255, 215, 120), Outline = rgb(255, 250, 225), FillT = 0.8, Pulse = { 0.72, 0.86, 0.35 },
		Glint = { rgb(255, 250, 230), rgb(255, 200, 90) }, Radiance = rgb(255, 205, 100), Light = { rgb(255, 230, 160), 2, 8 }, LightPulse = 0.35,
		Spots = {
			{ Pos = V(0, 0, -0.471), Color = rgb(255, 240, 190), Kind = "Glow", Size = 0.5, LightBrightness = 1.8, LightRange = 4, Pulse = 0.5 },
			{ Pos = V(0, 0.301, -0.305), Color = rgb(255, 225, 150), Kind = "Flare", Size = 0.1, Light = false },
			{ Pos = V(0, 0, -2.40), Color = rgb(255, 235, 170), Kind = "Glow", Size = 0.24, Light = false },
		} },
}) }

-- EXCLUSIVE — Masquerade // Carnival Night: black-and-gold masquerade mask, purple/gold/green plume fins; the plumes sway
KITS.Masquerade = { Helix = shell({
	folder = "Masquerade_Helix", vol = HELIX_VOL,
	anims = { Plumes = { Kind = "Sway", Pivot = V(0, 0.143, -0.137), Axis = V(1, 0, 0), Amp = 6, Speed = 0.6 } },
	aura = { Fill = rgb(170, 70, 255), Outline = rgb(255, 215, 120), FillT = 0.82, Pulse = { 0.74, 0.88, 0.5 },
		Glint = { rgb(255, 225, 150), rgb(90, 255, 160) }, Radiance = rgb(150, 60, 255), Light = { rgb(190, 120, 255), 1.8, 8 }, LightPulse = 0.5,
		Spots = {
			{ Pos = V(-0.14, 0.0, -0.252), Color = rgb(190, 90, 255), Kind = "Flare", Size = 0.12, LightBrightness = 1.4, LightRange = 3, Pulse = 0.5 },
			{ Pos = V(0, 0.187, -0.771), Color = rgb(170, 80, 255), Kind = "Glow", Size = 0.3, Light = false },
			{ Pos = V(0, 0, -2.40), Color = rgb(255, 215, 120), Kind = "Glow", Size = 0.22, Light = false },
		} },
}) }

-- GODLY — Storm Titan, Lord of Lightning: black chrome and gold titan face at the muzzle, lightning halo ring; the halo spins.
-- The halo is a 1.5-stud disc facing the camera, so it is hidden in first person.
KITS.Titan = { Helix = shell({
	folder = "Titan_Helix", vol = HELIX_VOL,
	fpHide = { "Halo" },
	anims = { Halo = { Kind = "Spin", Pivot = V(0, 0.003, -1.875), Axis = V(0, 0, 1), Speed = 0.5 } },
	aura = { Fill = rgb(255, 210, 90), Outline = rgb(255, 250, 230), FillT = 0.76, Pulse = { 0.68, 0.84, 0.4 },
		Glint = { rgb(255, 250, 235), rgb(255, 200, 70) }, Radiance = rgb(255, 200, 70), Light = { rgb(255, 230, 150), 2.4, 9 }, LightPulse = 0.4,
		Spots = {
			{ Pos = V(-0.12, 0.088, -2.298), Color = rgb(255, 255, 240), Kind = "Flare", Size = 0.14, LightBrightness = 1.8, LightRange = 3, Pulse = 0.45 },
			{ Pos = V(0.12, 0.088, -2.298), Color = rgb(255, 255, 240), Kind = "Flare", Size = 0.14, Light = false },
			{ Pos = V(0, -0.203, -2.375), Color = rgb(255, 230, 140), Kind = "Glow", Size = 0.35, LightBrightness = 1.6, LightRange = 3, Pulse = 0.7 },
			{ Pos = V(0, 0.295, -0.277), Color = rgb(255, 220, 120), Kind = "Glow", Size = 0.3, Light = false },
		} },
}) }

function SkinKits.Build(model: Instance, weaponId: string, kitId: string?)
	if not kitId then
		return
	end
	local kit = KITS[kitId]
	local build = kit and kit[weaponId]
	local root = rootOf(model)
	if not build or not root then
		return
	end
	build({ root = root, k = scaleOf(model), kit = kitId, model = model })
end

SkinKits.Kits = KITS
return SkinKits
