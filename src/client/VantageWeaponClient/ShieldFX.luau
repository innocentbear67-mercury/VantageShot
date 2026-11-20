--[[
	VANTAGE — ShieldFX (client)
	The exosuit energy shield, drawn from the server-owned shield state: ShieldService writes the
	replicated character attributes Shield / MaxShield / ShieldBrokenAt / ShieldRecharging and
	broadcasts every hit the shield takes as WeaponEvent "ShieldHit" (character, impact point, bullet
	direction, shield left 0..1, absorbed, broke) from the real server hit detection.

	Halo-style presentation (2026-11-11): the shield is INVISIBLE at rest. It only shows
	  • recharge   while ShieldRecharging is true (server-authoritative, written on start / stop only):
	                 forms   the field flickers in around every armour piece, small arcs crawl over the plates
	                 during  faint shimmer, pulses flowing up the suit (third person) / down the arms (first)
	                 done    ShieldRecharging -> false with Shield = MaxShield: brief bright intensify,
	                         a small energy pulse, smooth fade back to invisible
	                 cut     ShieldRecharging -> false with Shield < MaxShield (damage): quick flickering
	                         fade, no completion
	  • hits       a short flare of the skin near the impact + ripple, sparks, arcs (unchanged)
	  • break      outward burst of the skin, electrical fragments, light, break sound (unchanged)
	  • skin       third person: a ForceField copy of each exosuit armour MeshPart (follows the suit's
	               real shape; plain avatars: the limb), moved only while visible (one BulkMoveTo);
	               first person: the same film + surface hex tiles over the viewmodel's arm armour
	  • audio      ReplicatedStorage.Vantage.Shield.RechargeSounds (Start / Loop / Complete /
	               Interrupted placeholders + spatial settings as attributes). Your own = 2D; other
	               players = 3D on their torso, quieter, attenuated, only the nearest few hums at once.
	               One loop per character, ever: started / stopped only on the state transitions.
	Your own feedback (screen edges, direction, camera wobble, visor) is drawn by the Hud / visor.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Cfg = require(ReplicatedStorage.Vantage.Shield.ShieldConfig)
local EnergyFX = require(script.Parent.EnergyFX)
local VIS = Cfg.Visual
-- 2026-11-17: every Shield Pack has its own colours (character attributes ShieldColor / ShieldColor2 from
-- EquipmentCatalog). COL is switched to the character being drawn (useCol) before each skin / hex / burst.
local COL = table.clone(VIS.Colors)
local EquipCatalog = nil
pcall(function()
	EquipCatalog = require(ReplicatedStorage.Vantage:WaitForChild("Equipment", 10):WaitForChild("EquipmentCatalog"))
end)
local function useCol(character: Instance?)
	if not EquipCatalog then
		return
	end
	local a, b = EquipCatalog.ShieldColors(character)
	COL.Lime, COL.White, COL.Arc = a, b, a:Lerp(b, 0.45)
end
local RC = VIS.Recharge
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local SOUNDS = ReplicatedStorage.Vantage.Shield:WaitForChild("RechargeSounds")

local BODY = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
	"Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", -- R6
}
local CRACKED = { UpperTorso = true, LowerTorso = true, Torso = true }
local FULL_GAP = 0.05 -- rapid fire: at most one full impact burst per target per this many seconds
local STRENGTH = { Full = 0.55, Damaged = 0.8, Critical = 1 }

local ShieldFX = {}
local recs: { [Model]: any } = {}
local started = false
local rng = Random.new()
local moveParts: { BasePart } = {} -- everything that follows a body this frame (one BulkMoveTo)
local moveCFrames: { CFrame } = {}
-- first-person film state (declared here: the hit / break handlers above the drawing code feed it)
local fp = { Arms = nil :: Model?, Skins = {}, Flare = 0, HitAt = -math.huge, Side = 0, Strength = 0, BreakAt = -math.huge, LastFrac = nil :: number?, ReformUntil = 0, NextArc = 0, NextScan = 0 }

local function folder(): Folder
	return EnergyFX.Folder("VantageShieldFX")
end

local function stageOf(frac: number): string
	if frac <= 0 then
		return "Broken"
	elseif frac < VIS.CriticalBelow then
		return "Critical"
	elseif frac < VIS.DamagedBelow then
		return "Damaged"
	end
	return "Full"
end

local function torsoOf(character: Model): BasePart?
	return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function inRange(character: Model): boolean
	local t = torsoOf(character)
	return t ~= nil and (t.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude <= VIS.MaxDistance
end

-- ─── hexagonal layers ─────────────────────────────────────────────────────────────────────
-- The honeycomb: around a body part, a hexagonal prism of six flat panels (its axis along the
-- part's length), each a SurfaceGui tiled with a glowing hex grid. `layers` (ShieldConfig.Visual.Hex)
-- nests several prisms: Pad = stand-off, Rot = degrees turned about the axis (30 puts a layer's
-- panels over the edges of the one below), Cell = hexagon size in studs, Bright, Alpha = image
-- transparency at full shield. Unlit (LightInfluence 0), so it reads the same in shadow.
-- Returns { { Part, Offset (relative to the body part), Label, Layer, Alpha, CellY } }.
local HEX = VIS.Hex or { Enabled = false }
local hexImage = HEX.Image
if HEX.Enabled then
	task.spawn(function() -- if the grid image ever fails to load, fall back to the visor's hex cell
		local ok = pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ HEX.Image }, function(_, status)
				if status ~= Enum.AssetFetchStatus.Success and HEX.Fallback then
					hexImage = HEX.Fallback
				end
			end)
		end)
		if not ok and HEX.Fallback then
			hexImage = HEX.Fallback
		end
	end)
end

-- 2026-11-20 perf: a SurfaceGui costs a render pass even when its image is fully transparent, and
-- every character carried ~56 of them (726 live in a 6v6). A hex gui is only Enabled while it shows.
local function guiOn(label: ImageLabel, on: boolean)
	local g = label.Parent :: SurfaceGui
	if g and g.Enabled ~= on then
		g.Enabled = on
	end
end

local function hexPanels(size: Vector3, layers, pixelsPerStud: number, parent: Instance)
	local out = {}
	for li, L in layers do
		local rx, rz = size.X / 2 + L.Pad, size.Z / 2 + L.Pad
		local cellX = math.max(8, math.floor(L.Cell * pixelsPerStud))
		local cellY = math.max(7, math.floor(cellX * 0.78))
		for k = 0, 5 do
			local th = math.rad(k * 60 + (L.Rot or 0))
			local p = Vector3.new(rx * math.cos(th), 0, rz * math.sin(th))
			local n = Vector3.new(math.cos(th) / rx, 0, math.sin(th) / rz).Unit
			local part = Instance.new("Part")
			part.Name = "ShieldHex"
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
			part.Transparency = 1
			part.Size = Vector3.new(p.Magnitude * 1.17, size.Y + L.Pad * 2, 0.01)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.LightInfluence = 0
			gui.Brightness = L.Bright or 2
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = pixelsPerStud
			gui.ClipsDescendants = true
			gui.Enabled = false
			gui.Parent = part
			local label = Instance.new("ImageLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, 1, cellY) -- one cell taller than the panel: room to scroll
			label.Image = hexImage
			label.ImageColor3 = COL.Lime
			label.ImageTransparency = 1
			label.ScaleType = Enum.ScaleType.Tile
			label.TileSize = UDim2.fromOffset(cellX, cellY)
			label.Parent = gui
			part.Parent = parent
			table.insert(out, { Part = part, Offset = CFrame.lookAt(p, p + n), Label = label, Layer = li, Alpha = L.Alpha or 0.3, CellY = cellY })
		end
	end
	return out
end

-- one frame of a honeycomb: follow the body part; `show` 0..1 (0 = off), `hot` 0..1 whitens it
local function hexDraw(panels, cf: CFrame, show: number, hot: number, now: number)
	for _, h in panels do
		if show <= 0.01 then
			if h.Label.ImageTransparency < 1 then
				h.Label.ImageTransparency = 1
			end
			guiOn(h.Label, false)
			continue
		end
		guiOn(h.Label, true)
		table.insert(moveParts, h.Part)
		table.insert(moveCFrames, cf * h.Offset)
		-- the layers breathe against each other and drift along the limb in opposite directions
		local breathe = 0.06 * math.sin(now * 2.2 + h.Layer * 2.1)
		h.Label.ImageTransparency = math.clamp(1 - (1 - h.Alpha - breathe) * show - hot * 0.3, 0, 1)
		h.Label.ImageColor3 = COL.Lime:Lerp(COL.White, math.clamp(hot, 0, 1))
		if h.Label.Image ~= hexImage then
			h.Label.Image = hexImage
		end
		local dir = if h.Layer % 2 == 0 then 1 else -1
		h.Label.Position = UDim2.fromOffset(0, -((now * 7 * dir) % h.CellY))
	end
end

-- First person: one hexagon per tile, each lying on the armour's surface (ShieldHexData), so
-- the honeycomb takes the shape of the arm and hand instead of boxing them in.
local HexData = require(ReplicatedStorage.Vantage.Shield:WaitForChild("ShieldHexData"))

local function hexTiles(def, parent: Instance)
	local out = {}
	local size = def.Size
	for i, t in def.Tiles do
		local n = Vector3.new(t[4], t[5], t[6])
		if n.Magnitude < 0.5 then
			continue
		end
		n = n.Unit
		local raised = (HEX.RaisedEvery or 0) > 0 and i % HEX.RaisedEvery == 0
		local p = Vector3.new(t[1], t[2], t[3]) + n * (if raised then HEX.RaisedLift or 0.03 else 0)
		local part = Instance.new("Part")
		part.Name = "ShieldHex"
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		part.Transparency = 1
		part.Size = Vector3.new(size, size, 0.005)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		gui.Brightness = HEX.TileBright or 2.4
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(48, 48)
		gui.Enabled = false
		gui.Parent = part
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Image = HEX.Tile or HEX.Fallback or hexImage
		label.ImageColor3 = COL.Lime
		label.ImageTransparency = 1
		label.Parent = gui
		part.Parent = parent
		table.insert(out, { Part = part, Offset = EnergyFX.Facing(p, n), Label = label, Alpha = if raised then HEX.RaisedAlpha or 0.45 else HEX.TileAlpha or 0.1, Last = 1, LastHot = 0, Seed = i * 0.37 })
	end
	return out
end

-- one frame of the tiles: follow the armour piece; `show` 0..1, `hot` 0..1 whitens. Cells
-- sparkle a few at a time; a label is only touched when its value really changes.
local function tilesDraw(tiles, cf: CFrame, show: number, hot: number, now: number)
	for _, h in tiles do
		local target = 1
		if show > 0.01 then
			target = 1 - (1 - h.Alpha) * show - hot * 0.3
			local tw = math.noise(h.Seed, now * 0.9)
			if tw > 0.2 then
				target -= (tw - 0.2) * 0.9
			elseif tw < -0.3 then
				target += (-0.3 - tw) * 0.8
			end
			target = math.clamp(target, 0, 0.95)
			table.insert(moveParts, h.Part)
			table.insert(moveCFrames, cf * h.Offset)
		end
		if math.abs(target - h.Last) > 0.02 or (target >= 1 and h.Last < 1) then
			h.Label.ImageTransparency = target
			h.Last = target
			guiOn(h.Label, target < 0.995)
		end
		if math.abs(hot - h.LastHot) > 0.05 then
			h.Label.ImageColor3 = COL.Lime:Lerp(COL.White, math.clamp(hot, 0, 1))
			h.LastHot = hot
		end
	end
end

-- ─── the skin ─────────────────────────────────────────────────────────────────────────────
-- jagged crack lines over the front and back of a torso skin (lit while critical)
local function buildCracks(skin: BasePart, size: Vector3): { Beam }
	local beams = {}
	local color = ColorSequence.new(COL.White)
	for _, face in { -1, 1 } do
		for _ = 1, 2 do
			local x = rng:NextNumber(-0.35, 0.35) * size.X
			local prev
			for i = 0, 4 do
				local att = Instance.new("Attachment")
				att.Position = Vector3.new(x, size.Y * (0.45 - i * 0.22), face * size.Z * 0.5)
				att.Parent = skin
				x = math.clamp(x + rng:NextNumber(-0.3, 0.3) * size.X, -0.46 * size.X, 0.46 * size.X)
				if prev then
					local b = Instance.new("Beam")
					b.Attachment0, b.Attachment1 = prev, att
					b.Width0, b.Width1 = 0.035, 0.02
					b.FaceCamera = true
					b.LightEmission = 1
					b.LightInfluence = 0
					b.Brightness = 3
					b.Color = color
					b.Segments = 1
					b.Enabled = false
					b.Parent = skin
					table.insert(beams, b)
				end
				prev = att
			end
		end
	end
	return beams
end

local function clearSkin(rec)
	for _, s in rec.Skins do
		s.Part:Destroy()
		for _, h in s.Hex or {} do
			h.Part:Destroy()
		end
	end
	table.clear(rec.Skins)
	rec.Built = false
	rec.Shown = false
end

-- a ForceField copy of `src`, `padding` studs bigger all round
local function makeSkin(src: BasePart, padding: number, name: string): (BasePart?, Vector3)
	local was = src.Archivable
	src.Archivable = true
	local ok, skin = pcall(src.Clone, src)
	src.Archivable = was
	if not ok or not skin then
		return nil, src.Size
	end
	for _, c in skin:GetChildren() do
		if not c:IsA("DataModelMesh") then
			c:Destroy()
		end
	end
	local size = src.Size + Vector3.one * padding * 2
	local mesh = skin:FindFirstChildWhichIsA("DataModelMesh")
	if mesh and mesh:IsA("SpecialMesh") then
		mesh.Scale *= size / src.Size
	end
	if skin:IsA("MeshPart") then
		pcall(function()
			skin.TextureID = "" -- the ForceField pattern, not the avatar's texture
		end)
	end
	skin.Name = "Skin_" .. name
	skin.Anchored, skin.CanCollide, skin.CanQuery, skin.CanTouch, skin.CastShadow = true, false, false, false, false
	skin.Massless = true
	skin.Material = Enum.Material.ForceField
	skin.Color = COL.Lime
	skin.Transparency = 1
	skin.Size = size
	skin.CFrame = src.CFrame
	skin.Parent = folder()
	return skin, size
end

local function buildSkin(rec)
	clearSkin(rec)
	local character = rec.Character
	useCol(character)
	for _, name in BODY do
		local bone = character:FindFirstChild(name)
		if not (bone and bone:IsA("BasePart")) then
			continue
		end
		-- exosuit rig: the bones are invisible hitboxes with the armour MeshParts riding on them, so
		-- the field wraps each armour piece (the suit's real outline). Plain avatars: the limb itself.
		local pieces = {}
		if bone.Transparency >= 0.95 then
			for _, v in bone:GetChildren() do
				if v:IsA("MeshPart") and v.Transparency < 0.95 and string.sub(v.Name, 1, 7) ~= "Grapple" then
					table.insert(pieces, v)
				end
			end
		end
		local meshMode = #pieces > 0
		if not meshMode then
			pieces = { bone }
		end
		local biggest = nil
		for _, src in pieces do
			local skin, size = makeSkin(src, if meshMode then (VIS.MeshPadding or 0.04) else VIS.Padding, src.Name)
			if skin then
				local e = { Src = src, Part = skin, Size = size }
				table.insert(rec.Skins, e)
				if not biggest or src.Size.Magnitude > biggest.Src.Size.Magnitude then
					biggest = e
				end
			end
		end
		if biggest then
			-- honeycomb over the torso, head, arms and legs (hands and feet are too small to read)
			if HEX.Enabled and not string.find(name, "Hand", 1, true) and not string.find(name, "Foot", 1, true) then
				biggest.Hex = hexPanels(bone.Size, HEX.World, 72, folder())
				biggest.HexSrc = bone
			end
			if CRACKED[name] then
				biggest.Cracks = buildCracks(biggest.Part, biggest.Size)
			end
		end
	end
	rec.Built = #rec.Skins > 0
end

local function hide(rec)
	rec.Shown = false
	for _, s in rec.Skins do
		s.Part.Transparency = 1
		for _, h in s.Hex or {} do
			h.Label.ImageTransparency = 1
			guiOn(h.Label, false)
		end
		if s.Cracks then
			for _, b in s.Cracks do
				b.Enabled = false
			end
		end
	end
end
-- ─── recharge state (from the server's ShieldRecharging attribute) ───────────────────────────
local function newCharge()
	return { On = false, StartAt = -math.huge, EndAt = -math.huge, EndKind = nil :: string?, Last = 0, NextArc = 0, ArcsLeft = 0 }
end

-- strength 0..1 of the recharge field right now, and how white it burns
local function chargeLevel(c, now: number): (number, number)
	if c.On then
		local age = now - c.StartAt
		local form = math.clamp(age / RC.FormTime, 0, 1)
		local v = RC.Level * form * (0.9 + 0.1 * math.sin(age * 8.3))
		if age < RC.FormTime + 0.1 and rng:NextNumber() < 0.4 then
			v *= 0.15 -- forming: the field stutters into place
		end
		c.Last = v
		return v, (1 - form) * 0.35
	end
	local age = now - c.EndAt
	if c.EndKind == "Complete" then
		if age < RC.CompleteFlash then
			local k = math.sin(age / RC.CompleteFlash * math.pi * 0.5)
			return c.Last + (1 - c.Last) * k, 0.85 * k
		end
		local f = (age - RC.CompleteFlash) / RC.CompleteFade
		if f < 1 then
			return (1 - f) ^ 2, 0.85 * (1 - f) ^ 3
		end
	elseif c.EndKind == "Interrupted" then
		local f = age / RC.InterruptFade
		if f < 1 then
			return c.Last * (1 - f) * (if rng:NextNumber() < 0.5 then 0.3 else 1), 0
		end
	end
	return 0, 0
end

-- 0..1 position of the energy pulse currently flowing over the suit (nil between pulses)
local function pulsePhase(c, now: number): number?
	if not c.On then
		return nil
	end
	local age = now - c.StartAt - RC.FormTime * 0.5
	if age < 0 then
		return nil
	end
	local t = age % RC.PulseEvery
	return if t <= RC.PulseTime then t / RC.PulseTime else nil
end

local function nextArc(c, now: number)
	if c.ArcsLeft > 0 then
		c.ArcsLeft -= 1
		c.NextArc = now + RC.FormTime / math.max(1, RC.StartArcs)
	else
		c.NextArc = now + rng:NextNumber(RC.ArcGap[1], RC.ArcGap[2])
	end
end

-- a small arc between two points on the surface of one armour piece (never across the body)
local function surfacePoint(cf: CFrame, size: Vector3): Vector3
	local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	d /= math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z), 1e-3)
	return cf * (d * size * 0.5)
end
local function surfaceArc(cf: CFrame, size: Vector3, width: number, brightness: number)
	local a, b = surfacePoint(cf, size), surfacePoint(cf, size)
	if (a - b).Magnitude > 0.12 then
		EnergyFX.Arc(a, b, { Color = COL.Arc, Width = width, Life = 0.09, Segments = 4, Jitter = 0.1, Brightness = brightness })
	end
end

-- ─── recharge audio ─────────────────────────────────────────────────────────────────────────
local function aud(name: string, default: number): number
	local v = SOUNDS:GetAttribute(name)
	return if type(v) == "number" then v else default
end
local function soundTemplate(name: string): Sound?
	local s = SOUNDS:FindFirstChild(name)
	return if s and s:IsA("Sound") and s.SoundId ~= "" then s else nil
end
-- your own: 2D. Anyone else: 3D on their torso (follows them), quieter, fades out with distance
local function emitter(rec, s: Sound, isLocal: boolean): boolean
	s.SoundGroup = SoundService:FindFirstChild("VantageEffects") :: SoundGroup?
	if isLocal then
		s.Parent = SoundService
		return true
	end
	local torso = torsoOf(rec.Character)
	if not torso then
		return false
	end
	s.Volume *= aud("RemoteVolumeScale", 0.45)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = aud("RemoteMinDistance", 6)
	s.RollOffMaxDistance = aud("RemoteMaxDistance", 70)
	s.Parent = torso
	return true
end
local function inEarshot(rec): boolean
	local t = torsoOf(rec.Character)
	return t ~= nil and (t.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude <= aud("RemoteMaxDistance", 70)
end
local remoteShots: { number } = {} -- big fights: at most 4 other-player one-shots per half second
local function remoteShotAllowed(now: number): boolean
	for i = #remoteShots, 1, -1 do
		if now - remoteShots[i] > 0.5 then
			table.remove(remoteShots, i)
		end
	end
	if #remoteShots >= 4 then
		return false
	end
	table.insert(remoteShots, now)
	return true
end
local function playOne(name: string, rec, isLocal: boolean)
	if not isLocal and (not inEarshot(rec) or not remoteShotAllowed(os.clock())) then
		return
	end
	local t = soundTemplate(name)
	if not t then
		-- until a real start sound is assigned, your own recharge keeps the old charge-up sound
		if isLocal and name == "ShieldRechargeStart" and VIS.Sounds.Recharge and not soundTemplate("ShieldRechargeLoop") then
			EnergyFX.Sound(VIS.Sounds.Recharge, nil)
		end
		return
	end
	local s = t:Clone()
	s.Looped = false
	if not emitter(rec, s, isLocal) then
		s:Destroy()
		return
	end
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 10)
end
local function loopStart(rec, isLocal: boolean)
	if rec.Loop then
		return -- never two copies
	end
	local t = soundTemplate("ShieldRechargeLoop")
	if not t then
		return
	end
	local s = t:Clone()
	s.Name = "ShieldRechargeLoop_Live"
	s.Looped = t.Looped -- a designed one-shot charge-up (Looped off) or a hum (Looped on)
	if not emitter(rec, s, isLocal) then
		s:Destroy()
		return
	end
	local target = s.Volume
	s.Volume = 0
	rec.Loop, rec.LoopSpeed = s, t.PlaybackSpeed
	s:Play()
	rec.LoopTween = TweenService:Create(s, TweenInfo.new(aud("LoopFadeIn", 0.35), Enum.EasingStyle.Sine), { Volume = target })
	rec.LoopTween:Play()
end
local function loopStop(rec, fade: number)
	local s = rec.Loop
	if not s then
		return
	end
	rec.Loop = nil
	if rec.LoopTween then
		rec.LoopTween:Cancel()
		rec.LoopTween = nil
	end
	if fade <= 0 or not s.Parent then
		s:Destroy()
		return
	end
	TweenService:Create(s, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 }):Play()
	Debris:AddItem(s, fade + 0.05)
end
-- other players' hums: only the nearest MaxRemoteLoops recharging players within earshot (4 Hz)
local function budgetRemoteLoops(me: Model?)
	local cam = Workspace.CurrentCamera.CFrame.Position
	local maxD = aud("RemoteMaxDistance", 70)
	local list = {}
	for character, rec in recs do
		if character ~= me and rec.Charge.On and not rec.Dead then
			local t = torsoOf(character)
			local d = t and (t.Position - cam).Magnitude
			if d and d <= maxD then
				table.insert(list, { rec, d })
			end
		end
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	local keep = {}
	for i, e in list do
		if i <= aud("MaxRemoteLoops", 3) then
			keep[e[1]] = true
		end
	end
	for character, rec in recs do
		if character ~= me then
			if keep[rec] then
				loopStart(rec, false)
			elseif rec.Loop then
				loopStop(rec, aud("LoopFadeOut", 0.25))
			end
		end
	end
end

-- shield-down alarm: loops in YOUR helmet only (2D) while Shield = 0, alive and the server has not
-- started the recharge; stops (short fade) the moment the recharge starts, you die or respawn.
local SHIELD_DOWN_ALARM = false -- 2026-11-17: no looping alarm (Hypershot-clean mix); the break plays once
local downLoop: Sound? = nil
local function stepDownAlarm(me: Model?)
	local want = false
	if me then
		local hum = me:FindFirstChildOfClass("Humanoid")
		want = hum ~= nil and hum.Health > 0 and (me:GetAttribute("MaxShield") or 0) > 0
			and (me:GetAttribute("Shield") or 0) <= 0 and me:GetAttribute("ShieldRecharging") ~= true
	end
	if want and SHIELD_DOWN_ALARM and not downLoop then
		local t = soundTemplate("ShieldDown")
		if t then
			local s = t:Clone()
			s.Name = "ShieldDown_Live"
			s.SoundGroup = SoundService:FindFirstChild("VantageEffects") :: SoundGroup?
			s.Parent = SoundService
			s:Play()
			downLoop = s
		end
	elseif not want and downLoop then
		local s = downLoop
		downLoop = nil
		TweenService:Create(s, TweenInfo.new(0.15), { Volume = 0 }):Play()
		Debris:AddItem(s, 0.2)
	end
end

-- recharge complete, seen on someone else: one soft bloom of light at the chest
local function completeFlash(rec)
	useCol(rec.Character)
	local torso = torsoOf(rec.Character)
	if not torso or not inRange(rec.Character) then
		return
	end
	EnergyFX.Flash(torso.Position, {
		Color = COL.White, From = 0.6, To = 3.4, Life = 0.24, Transparency = 0.75, Folder = folder(),
		Light = { Color = COL.Lime, Range = 7, Brightness = 1.2, Life = 0.32 },
	})
end


-- ─── reactions ────────────────────────────────────────────────────────────────────────────
local function burst(rec)
	local character = rec.Character
	useCol(character)
	local torso = torsoOf(character)
	if not torso then
		return
	end
	local isLocal = character == Players.LocalPlayer.Character
	if not (isLocal and SHIELD_DOWN_ALARM and soundTemplate("ShieldDown")) then
		-- your own break: the looping shield-down alarm takes over; others still crackle in 3D
		EnergyFX.Sound(VIS.Sounds.Break, if isLocal then nil else torso.Position)
	end
	if isLocal then
		fp.BreakAt = os.clock() -- first person: the film over your arms tears and is gone
	end
	if isLocal or not inRange(character) then
		return -- your own break: the HUD edge distortion + visor show it
	end
	local f = folder()
	local centre = torso.Position
	-- the skin blows outward off the body and is gone
	if rec.Built and not rec.Dead then
		for _, s in rec.Skins do
			local shard = EnergyFX.Part({
				Material = Enum.Material.ForceField, Color = COL.White, Transparency = 0.15,
				Size = s.Part.Size, CFrame = s.Part.CFrame,
			}, f)
			EnergyFX.Tween(shard, 0.32, {
				Size = s.Part.Size * 1.9,
				CFrame = s.Part.CFrame + (s.Part.Position - centre) * 0.9,
				Transparency = 1,
			})
			game:GetService("Debris"):AddItem(shard, 0.36)
		end
	end
	EnergyFX.Flash(centre, {
		Color = COL.White, From = 1, To = 7, Life = 0.28, Transparency = 0.3, Folder = f,
		Light = { Color = COL.Lime, Range = 18, Brightness = 5, Life = 0.45 },
	})
	EnergyFX.Sparks(CFrame.new(centre), 34, {
		Color0 = COL.White, Color1 = COL.Lime, Spread = 180, Speed = NumberRange.new(18, 34),
		Life = NumberRange.new(0.3, 0.6), Size = 0.22, Gravity = 20, Drag = 3,
	})
	for _ = 1, 6 do
		local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.8), rng:NextNumber(-1, 1)).Unit
		EnergyFX.Arc(centre, centre + d * rng:NextNumber(3, 5), { Color = COL.Arc, Width = 0.07, Life = 0.16, Segments = 6, Jitter = 0.2 })
	end
end

-- the server reports a hit on this character's shield (real impact point and bullet direction)
local function onHit(character: Model, pos: Vector3, dir: Vector3, frac: number, absorbed: number, broke: boolean)
	useCol(character)
	local rec = recs[character]
	if not rec then
		return
	end
	local stage = if broke then "Critical" else stageOf(frac)
	-- 2026-11-19: scaled by the damage taken too, not only the stage (an SMG tick and a sniper round differ)
	local k = math.max((STRENGTH[stage] or 1) * 0.6, math.clamp(absorbed / 35, 0.3, 1.5))
	if character == Players.LocalPlayer.Character then
		if absorbed > 0 then
			EnergyFX.Sound(VIS.Sounds.Hit, nil, { Volume = 0.75 + 0.35 * k })
			-- first person: ripple down the arm on the side the shot came from
			local from = Workspace.CurrentCamera.CFrame:VectorToObjectSpace(-dir)
			fp.HitAt, fp.Strength, fp.Side = os.clock(), k, math.clamp(from.X * 2, -1, 1)
			fp.Flare = math.max(fp.Flare, k)
		end
		return
	end
	if not inRange(character) then
		return
	end
	local now = os.clock()
	rec.HitPos, rec.HitAt, rec.HitStrength = pos, now, k
	rec.Flare = math.max(rec.Flare, k)
	if now < rec.NextFull then
		return -- rapid fire: the flare keeps up, the burst below waits for the next window
	end
	rec.NextFull = now + FULL_GAP
	local f = folder()
	-- 2026-11-19: bystanders hear a quiet shield crackle, so shield hits and flesh hits sound different
	EnergyFX.Sound(VIS.Sounds.Hit, pos, { Volume = 0.45 + 0.35 * math.min(k, 1), RollOffMin = 8, RollOffMax = 60, Life = 2 })
	if absorbed >= 40 then
		-- a heavy round: a big hex plate lights where it landed
		local tout = (pos - (torsoOf(character) or { Position = pos - dir }).Position)
		local pn = if tout.Magnitude > 0.05 then tout.Unit else -dir.Unit
		EnergyFX.ShockRing(EnergyFX.UpFrame(pos + pn * 0.05, pn), { From = 0.5, To = 2.8, Life = 0.3, Segments = 6, Thickness = 0.1, Color = COL.White, Folder = f })
	end
	-- (2026-11-17) no extra shield-hit sound on other players: the hit tick (HitFeedback) is the one hit cue
	-- the surface normal at the impact, tipped back toward the shooter
	local torso = torsoOf(character)
	local out = if torso then pos - torso.Position else -dir
	if out.Magnitude < 0.05 then
		out = -dir
	end
	local normal = (out.Unit - dir.Unit * 0.6).Unit
	EnergyFX.Ripple(pos + normal * 0.04, normal, { Color = COL.Lime, From = 0.3, To = 1.6 + 1.1 * k, Life = 0.22, Folder = f })
	EnergyFX.Flash(pos, {
		Color = COL.White, From = 0.25, To = 0.7 + 0.6 * k, Life = 0.09, Folder = f,
		Light = { Color = COL.Lime, Range = 6 + 4 * k, Brightness = 2 + 3 * k, Life = 0.15 },
	})
	EnergyFX.Sparks(EnergyFX.UpFrame(pos, normal), math.floor(5 + 10 * k), {
		Color0 = COL.White, Color1 = COL.Lime, Spread = 50, Speed = NumberRange.new(10, 18 + 12 * k),
		Life = NumberRange.new(0.12, 0.3), Size = 0.14,
	})
	if stage ~= "Full" and #rec.Skins > 0 then
		-- weakened shields discharge: arcs jump from the impact to the nearest parts of the suit
		for _ = 1, if stage == "Critical" then 3 else 1 do
			local s = rec.Skins[rng:NextInteger(1, #rec.Skins)]
			EnergyFX.Arc(pos, s.Part.Position, { Color = COL.Arc, Width = 0.05, Life = 0.1, Segments = 5, Jitter = 0.25 })
		end
	end
end

-- ─── per frame ────────────────────────────────────────────────────────────────────────────

-- ─── first person: the film over your own arms ───────────────────────────────────────────────
-- The viewmodel (VantageWeaponClient.Viewmodel / KnifeViewmodel) keeps the arms as a Model named
-- "Arms" under the camera: invisible bones with the visible armour parts as their children (or,
-- without the exo-suit template, the limbs themselves). Each visible part gets a ForceField copy
-- that rides on it. The copies live inside that Arms model, so they appear, hide and die with it.
local FP = VIS.FirstPerson or { Enabled = false }
local ARM_ORDER = { UpperArm = 0, LowerArm = 1, Hand = 2 }

local function fpArms(): Model?
	for _, vm in Workspace.CurrentCamera:GetChildren() do
		local arms = vm:FindFirstChild("Arms")
		if arms and arms:IsA("Model") then
			return arms
		end
	end
	return nil
end

local function fpClear()
	for _, s in fp.Skins do
		s.Part:Destroy()
		for _, h in s.Tiles or {} do
			h.Part:Destroy()
		end
	end
	table.clear(fp.Skins)
end

local function fpBuild(arms: Model)
	fpClear()
	useCol(Players.LocalPlayer.Character)
	fp.Arms = arms
	local pad = Vector3.one * (FP.Padding or 0.03) * 2
	local function add(src: BasePart, bone: BasePart, outer: boolean?)
		local pad = if outer then Vector3.one * (FP.OuterPadding or 0.05) * 2 else pad
		local ok, skin = pcall(src.Clone, src)
		if not ok or not skin then
			return
		end
		for _, c in skin:GetChildren() do
			if not c:IsA("DataModelMesh") then
				c:Destroy()
			end
		end
		if skin:IsA("MeshPart") then
			pcall(function()
				skin.TextureID = ""
			end)
		end
		local size = src.Size + pad
		skin.Name = "ShieldFilm"
		skin.Anchored, skin.CanCollide, skin.CanQuery, skin.CanTouch, skin.CastShadow = true, false, false, false, false
		skin.Material = Enum.Material.ForceField
		skin.Color = COL.Lime
		skin.Transparency = 1
		skin.LocalTransparencyModifier = 0
		skin.Size = size
		skin.CFrame = src.CFrame
		skin.Parent = arms
		local order = 1
		for key, n in ARM_ORDER do
			if string.find(bone.Name, key, 1, true) then
				order = n
			end
		end
		table.insert(fp.Skins, { Src = src, Part = skin, Size = size, Outer = outer == true, Side = if string.find(bone.Name, "Right", 1, true) then 1 else -1, Order = order })
	end
	-- honeycomb: one set of nested hex prisms per arm segment, around its biggest armour part
	local function addHex(bone: BasePart)
		local best: BasePart? = nil
		for _, s in fp.Skins do
			if (s.Src == bone or s.Src.Parent == bone) and (not best or s.Src.Size.Magnitude > best.Size.Magnitude) then
				best = s.Src
			end
		end
		local def = best and HexData[bone.Name .. "/" .. best.Name]
		for _, s in fp.Skins do
			if s.Src == best and HEX.Enabled and def and not s.Outer and not s.Tiles then
				s.Tiles = hexTiles(def, arms)
			end
		end
	end
	for _, bone in arms:GetChildren() do
		if bone:IsA("BasePart") and bone.Name ~= "ShieldFilm" and bone.Name ~= "ShieldHex" then
			if bone.Transparency < 0.95 then
				add(bone, bone) -- avatar-arm fallback: the limb itself is what you see
			end
			for _, v in bone:GetChildren() do
				if v:IsA("BasePart") and v.Transparency < 0.95 and string.sub(v.Name, 1, 7) ~= "Grapple" then
					add(v, bone)
					if v:IsA("MeshPart") and FP.OuterPadding then
						add(v, bone, true) -- the outer layer
					end
				end
			end
			addHex(bone)
		end
	end
end

local function fpStep(dt: number, now: number, me: Model?)
	if not FP.Enabled then
		return
	end
	useCol(me)
	if now >= fp.NextScan then
		fp.NextScan = now + 0.25
		local arms = fpArms()
		if arms ~= fp.Arms or (arms and (#fp.Skins == 0 or not fp.Skins[1].Part.Parent)) then
			if arms then
				fpBuild(arms)
			else
				fpClear()
				fp.Arms = nil
			end
			fp.Shown = true -- force one tidy pass over the new parts
		end
	end
	if #fp.Skins == 0 then
		return
	end
	local hum = me and me:FindFirstChildOfClass("Humanoid")
	local alive = hum ~= nil and hum.Health > 0
	local rec = me and recs[me]
	local c = rec and rec.Charge
	local level, white = 0, 0
	if c and alive then
		level, white = chargeLevel(c, now)
	end
	fp.Flare = math.max(0, fp.Flare - dt * 5)
	local breaking = now - fp.BreakAt < 0.32 and alive
	local hitAge = now - fp.HitAt
	local ripple = if hitAge < 0.3 and alive then hitAge / 0.3 else nil
	if level <= 0.005 and not breaking and not ripple then
		-- at rest the shield is invisible: hide once, then skip all per-part work
		if fp.Shown then
			fp.Shown = false
			for _, s in fp.Skins do
				s.Part.Transparency = 1
				if s.Swollen then
					s.Part.Size = s.Size
					s.Swollen = false
				end
				if s.Tiles then
					tilesDraw(s.Tiles, s.Src.CFrame, 0, 0, now)
				end
			end
		end
		return
	end
	fp.Shown = true
	local breakTr = nil
	if breaking then
		-- the shield just broke: the film tears (hard white stutter, swelling off the arms), then nothing
		local k = (now - fp.BreakAt) / 0.32
		breakTr = if rng:NextNumber() < 0.55 then 0.05 + 0.5 * k else 0.9
		white = 1 - k
	end
	local pulse = if c then pulsePhase(c, now) else nil
	for _, s in fp.Skins do
		local src, part = s.Src, s.Part
		if not src.Parent or not part.Parent then
			continue
		end
		local v = level
		if pulse then
			-- recharge pulse: energy flows shoulder -> hand
			local d = (pulse * 3.2 - 0.5) - s.Order
			if d > -0.6 and d < 0.6 then
				v += RC.PulseBoost * (1 - math.abs(d) / 0.6)
			end
		end
		local glow = 0
		if ripple then
			-- hit: the arm on the side the shot came from lights first and hardest, and the
			-- brightness travels from the shoulder down to the hand
			local sideW = 0.45 + 0.55 * math.clamp(0.5 + 0.5 * fp.Side * s.Side, 0, 1)
			local wave = math.max(0, 1 - math.abs(ripple * 3.2 - 0.4 - s.Order) / 1.1)
			glow = fp.Strength * sideW * math.max(wave, (1 - ripple) * 0.5)
			v = math.max(v, glow * 0.85)
		end
		local tr = if breakTr then breakTr elseif v > 0.005 then 1 - math.clamp(v, 0, 1) * (1 - RC.FilmClear) else 1
		if src.LocalTransparencyModifier > 0.98 or src.Transparency > 0.98 then
			tr = 1 -- follows the arm's own visibility (support arm hidden when aimed, viewmodel off)
		end
		part.Transparency = math.clamp(if s.Outer and tr < 1 then tr + 0.25 else tr, 0, 1)
		part.Color = COL.Lime:Lerp(COL.White, math.clamp(white + glow, 0, 1))
		if tr < 1 then
			table.insert(moveParts, part)
			table.insert(moveCFrames, src.CFrame)
		end
		if s.Tiles then
			local show = if tr >= 1 then 0 elseif breaking then 1 else math.clamp(v * (RC.HexFirstPerson or 0.8) + glow * 0.4, 0, 1)
			tilesDraw(s.Tiles, src.CFrame, show, white + glow, now)
		end
		local swell = if breaking then 1 + 0.22 * (now - fp.BreakAt) / 0.32 else 1 + 0.05 * glow
		if swell > 1.002 then
			part.Size = s.Size * swell
			s.Swollen = true
		elseif s.Swollen then
			part.Size = s.Size
			s.Swollen = false
		end
	end
	-- recharging: tiny arcs crawl over the arm plates (a burst while the field forms, then now and then)
	if c and c.On and alive and not breaking and now >= c.NextArc then
		nextArc(c, now)
		local s = fp.Skins[rng:NextInteger(1, #fp.Skins)]
		if not s.Outer and s.Part.Transparency < 1 then
			surfaceArc(s.Src.CFrame, s.Src.Size * 0.9, RC.ArcWidth / 3, 2)
		end
	end
end

local nextAudioBudget = 0
local function step(dt: number)
	local now = os.clock()
	local me = Players.LocalPlayer.Character
	table.clear(moveParts)
	table.clear(moveCFrames)
	if now >= nextAudioBudget then
		nextAudioBudget = now + 0.25
		budgetRemoteLoops(me)
	end
	stepDownAlarm(me)
	local rise = aud("LoopPitchRise", 0.22)
	local builds = 0 -- 2026-11-20 perf: at most one skin build per frame, and only once the character is in range
	for character, rec in recs do
		useCol(character)
		if rec.RebuildAt and now >= rec.RebuildAt and (character == me or (builds == 0 and inRange(character))) then
			rec.RebuildAt = nil
			if character ~= me then
				builds += 1
				buildSkin(rec)
			end
		end
		local max = character:GetAttribute("MaxShield") or 0
		local frac = if max > 0 then math.clamp((character:GetAttribute("Shield") or 0) / max, 0, 1) else 0
		local c = rec.Charge
		if rec.Loop then
			rec.Loop.PlaybackSpeed = rec.LoopSpeed + rise * frac -- the hum rises as the shield fills
		end
		if not rec.Built or rec.Dead or character == me or not inRange(character) then
			if rec.Shown then
				hide(rec)
			end
			continue
		end
		rec.Flare = math.max(0, rec.Flare - dt * 6)
		local level, white = chargeLevel(c, now)
		local hitAge = now - rec.HitAt
		local glow = if rec.HitPos and hitAge < RC.HitFlash then (1 - hitAge / RC.HitFlash) * rec.HitStrength else 0
		if level <= 0.005 and glow <= 0 and rec.Flare <= 0.02 then
			-- at rest: invisible, nothing moved, nothing drawn
			if rec.Shown then
				hide(rec)
			end
			continue
		end
		rec.Shown = true
		local flare = rec.Flare
		local critical = stageOf(frac) == "Critical"
		local pulse = pulsePhase(c, now)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local torso = torsoOf(character)
		local nearHex = torso ~= nil and (torso.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude <= (HEX.MaxDistance or 90)
		for _, s in rec.Skins do
			local src = s.Src
			local part = s.Part
			if not src.Parent then
				part.Transparency = 1
				continue
			end
			local cf = src.CFrame
			local v = level
			if pulse and root then
				-- recharge pulse: a band of energy flowing up the suit, boots -> helmet
				local u = math.clamp(((cf.Position - root.Position):Dot(root.CFrame.UpVector) + 3) / 5.4, 0, 1)
				local d = math.abs(pulse * 1.4 - 0.2 - u)
				if d < 0.22 then
					v += RC.PulseBoost * (1 - d / 0.22)
				end
			end
			local hit = if glow > 0 then glow * math.exp(-(cf.Position - rec.HitPos).Magnitude / 1.6) else 0
			v = math.max(v, hit * 0.9) + flare * 0.1
			local tr = if v > 0.005 then 1 - math.clamp(v, 0, 1) * (1 - RC.FilmClear) else 1
			-- follow the body's own visibility (death replay hiding live characters, cloaks...)
			if src.LocalTransparencyModifier > 0.98 or src.Transparency > 0.98 then
				tr = 1
			end
			part.Transparency = tr
			part.Color = COL.Lime:Lerp(COL.White, math.clamp(white + hit * 0.6, 0, 1))
			if tr < 1 then
				table.insert(moveParts, part)
				table.insert(moveCFrames, cf)
			end
			if s.Hex then
				local show = if tr >= 1 or not nearHex then 0 else math.clamp(v * (RC.HexWorld or 0.35), 0, 1)
				hexDraw(s.Hex, (s.HexSrc or src).CFrame, show, white + hit * 0.5 + flare * 0.3, now)
			end
			if flare > 0.02 then
				part.Size = s.Size * (1 + 0.07 * flare)
				s.Swollen = true
			elseif s.Swollen then
				part.Size = s.Size
				s.Swollen = false
			end
			if s.Cracks then
				for _, b in s.Cracks do
					local on = critical and hit > 0.15 and tr < 1 and rng:NextNumber() < 0.8
					b.Enabled = on
					if on then
						b.Transparency = NumberSequence.new(rng:NextNumber(0, 0.5))
					end
				end
			end
		end
		-- recharging: small arcs flicker across the armour plates
		if c.On and now >= c.NextArc and #rec.Skins > 0 then
			nextArc(c, now)
			local s = rec.Skins[rng:NextInteger(1, #rec.Skins)]
			if s.Part.Transparency < 1 then
				surfaceArc(s.Src.CFrame, s.Src.Size * 0.9, RC.ArcWidth, 2.5)
			end
		end
	end
	fpStep(dt, now, me)
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function watch(character: Model)
	if recs[character] then
		return
	end
	local rec = {
		Character = character, Skins = {}, Built = false, Shown = false, Dead = false,
		Flare = 0, HitAt = -math.huge, HitPos = nil, HitStrength = 0, NextArc = 0, NextFull = 0,
		RebuildAt = os.clock() + 0.2, Phase = rng:NextNumber(0, 6.28), Conns = {},
		Charge = newCharge(), Loop = nil :: Sound?, LoopSpeed = 1, LoopTween = nil :: Tween?,
	}
	recs[character] = rec
	local lastBreak = character:GetAttribute("ShieldBrokenAt")
	-- the avatar's appearance swaps body parts in after spawning: rebuild the skin to match
	local function partsChanged(c: Instance)
		if c:IsA("BasePart") then
			rec.RebuildAt = os.clock() + 0.3
		end
	end
	table.insert(rec.Conns, character.ChildAdded:Connect(partsChanged))
	table.insert(rec.Conns, character.ChildRemoved:Connect(partsChanged))
	-- armour pieces ride on the bones (one level down): an armour swap rebuilds the skin too
	local function armourChanged(d: Instance)
		if d:IsA("MeshPart") and d.Parent and d.Parent.Parent == character then
			rec.RebuildAt = os.clock() + 0.3
		end
	end
	table.insert(rec.Conns, character.DescendantAdded:Connect(armourChanged))
	table.insert(rec.Conns, character.DescendantRemoving:Connect(armourChanged))
	-- a Shield Pack swap recolours the film (the per-frame colours follow at once; this redoes the cracks)
	table.insert(rec.Conns, character:GetAttributeChangedSignal("ShieldColor"):Connect(function()
		rec.RebuildAt = os.clock() + 0.1
	end))
	-- recharge: driven only by the server's ShieldRecharging transitions (start / stop), so the
	-- visuals and sounds can never run ahead of, or outlive, the real shield state
	local function syncCharge()
		if recs[character] ~= rec then
			return
		end
		-- (death and the recharge stop can arrive in the same update, before Humanoid.Died fires)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then
			rec.Dead = true
		end
		local on = character:GetAttribute("ShieldRecharging") == true and not rec.Dead
		local c = rec.Charge
		if on == c.On then
			return
		end
		local now = os.clock()
		local isLocal = character == Players.LocalPlayer.Character
		if on then
			c.On, c.StartAt, c.EndKind, c.Last = true, now, nil, 0
			c.ArcsLeft, c.NextArc = RC.StartArcs or 0, now
			playOne("ShieldRechargeStart", rec, isLocal)
			if isLocal then
				loopStart(rec, true) -- other players' hums are budgeted in step()
			end
			return
		end
		c.On, c.EndAt = false, now
		local max = character:GetAttribute("MaxShield") or 0
		local sh = character:GetAttribute("Shield") or 0
		if rec.Dead then
			c.EndKind = nil -- the death sequence takes over
			loopStop(rec, 0.08)
		elseif max > 0 and sh >= max - 0.01 then
			c.EndKind = "Complete"
			loopStop(rec, aud("LoopFadeOut", 0.25))
			playOne("ShieldRechargeComplete", rec, isLocal)
			if not isLocal then
				completeFlash(rec)
			end
		else
			c.EndKind = "Interrupted" -- damage: fade out fast, no completion sound
			loopStop(rec, aud("InterruptFadeOut", 0.12))
			playOne("ShieldRechargeInterrupted", rec, isLocal)
		end
	end
	table.insert(rec.Conns, character:GetAttributeChangedSignal("ShieldRecharging"):Connect(function()
		task.defer(syncCharge) -- a Shield value sent in the same update lands first
	end))
	task.defer(syncCharge) -- joined while this character was already recharging
	table.insert(rec.Conns, character:GetAttributeChangedSignal("ShieldBrokenAt"):Connect(function()
		local t = character:GetAttribute("ShieldBrokenAt")
		if t and t ~= lastBreak then
			lastBreak = t
			burst(rec)
		end
	end))
	task.spawn(function()
		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum and recs[character] == rec then
			if hum.Health <= 0 then
				rec.Dead = true
			end
			table.insert(rec.Conns, hum.Died:Connect(function()
				rec.Dead = true -- the death sequence takes over
				hide(rec)
				syncCharge()
			end))
		end
	end)
	table.insert(rec.Conns, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) and recs[character] == rec then
			for _, c in rec.Conns do
				c:Disconnect()
			end
			loopStop(rec, 0) -- respawn / leave: never leave a hum behind
			clearSkin(rec)
			recs[character] = nil
		end
	end))
end

function ShieldFX.Start()
	if started then
		return
	end
	started = true
	local function onPlayer(plr: Player)
		plr.CharacterAdded:Connect(function(c)
			task.defer(watch, c)
		end)
		if plr.Character then
			watch(plr.Character)
		end
	end
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	Players.PlayerAdded:Connect(onPlayer)
	-- bots / training dummies carry shields too
	for _, tag in { "VantageDummy", "VantageBot" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
		for _, m in CollectionService:GetTagged(tag) do
			watch(m)
		end
	end
	local events = ReplicatedStorage.Vantage:WaitForChild("Remotes"):WaitForChild("WeaponEvent") :: RemoteEvent
	events.OnClientEvent:Connect(function(kind, a, b, c, d, e, f)
		if kind == "ShieldHit" and typeof(a) == "Instance" and a:IsA("Model") and typeof(b) == "Vector3" and typeof(c) == "Vector3" then
			onHit(a, b, c, tonumber(d) or 0, tonumber(e) or 0, f == true)
		end
	end)
	RunService:BindToRenderStep("VantageShield", Enum.RenderPriority.Last.Value, step)
	if RunService:IsStudio() then
		ShieldFX._burst = function(character: Model) -- test hooks
			local rec = recs[character]
			if rec then
				burst(rec)
			end
		end
		ShieldFX._hit = onHit
		ShieldFX._recs = recs
	end
end

return ShieldFX
