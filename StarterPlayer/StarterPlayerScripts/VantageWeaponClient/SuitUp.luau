--[[
	VANTAGE — SuitUp (client)
	Third-person suit-up shot played at the start of the Deploy phase, before the dropship clip.
	The player's own Roblox avatar (untouched: exactly as Roblox builds it) stands in the dropship
	bay in a relaxed stance; the Mk1 armour (the pieces of StarterPlayer.StarterCharacter) flies in
	and locks on from the boots up, each avatar body part giving way to the armour that covers it.
	The figure is alive throughout: it breathes, shifts its weight, looks down at the armour as it
	locks, raises a forearm to check the gauntlet, dips its head for the helmet and lifts it as the
	visor ignites. The shot ends on black, where the clip takes over.

	The bay is a painted backdrop (SuitUp.Backdrop, 16:9). To make the 3D figure sit in it:
	  * the camera is locked off for the whole shot (no move, no zoom), so the picture and the
	    figure can never slide against each other;
	  * the camera height / horizon / field of view match the picture (CAM_HEIGHT, HORIZON, VFOV);
	  * the figure is lit the way the picture is lit: dark, with cold light from the open ramp
	    behind and a little green from the crates; the world's ambient light is turned down for
	    the length of the shot (client only) and put back afterwards;
	  * a soft contact shadow sits under the feet.

	Both bodies (avatar and suit) are posed by the same joint angles every frame with plain
	forward kinematics over their own R15 joints, so they move as one whatever their proportions.

	SuitUp.Play({ Hide = fn, Show = fn })  yields for the whole shot (about SuitUp.Length seconds).
		Hide() is called once our own black cover is up (hide the menu so the 3D shot is visible),
		Show() once the shot is over and the cover is black again.
	SuitUp.Skip()  ends the shot early (SPACE during deploy).
	Debug: opts.HoldAt = seconds freezes the timeline there until SuitUp.Release() (screenshots).
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local V = Vector3.new
local rad = math.rad
local A = CFrame.Angles

local SuitUp = {}
SuitUp.Length = 4.7
SuitUp.Backdrop = "rbxassetid://136289446427213" -- dropship-bay-empty-1920x1080

-- swap any of these for your own uploads
SuitUp.Sounds = {
	Slide = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.2, Speed = 0.75 },
	Lock = { Id = "rbxasset://sounds/switch.wav", Volume = 0.8, Speed = 0.55 },
	LockThump = { Id = "rbxassetid://1837830050", Volume = 0.16, Speed = 1.7 },
	Visor = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Speed = 0.8 },
	Helmet = { Id = "rbxassetid://1837830050", Volume = 0.6, Speed = 0.9 },
}

local LIME = Color3.fromRGB(182, 255, 0)
local GREEN = Color3.fromRGB(110, 255, 70)
local TINT = Color3.fromRGB(150, 162, 182) -- armour colour multiplier: pulls it toward the bay's cold light
local ORIGIN = V(0, 3000, 0) -- far above the map, inside a closed box so no daylight reaches it

-- how the backdrop picture was "shot" (measured off the picture: door height, floor lines, horizon)
local VFOV = 46 -- vertical field of view of the picture, degrees
local CAM_HEIGHT = 3.2 -- camera height above the bay floor, studs
local HORIZON = -1.4 -- camera pitch that puts the horizon where the picture has it, degrees
local PLATE_DIST = 24
local STAND = V(0.55, 0, -14) -- where the operative stands, relative to the point under the camera
local FACING = 164 -- degrees: 180 = square to the camera

-- lock time of each piece (seconds). Dir = where it flies in from, in the operative's own frame.
local FLY = 0.28
local ORDER = {
	{ "Boot_R", 0.80, V(1, 0.1, -0.3) }, { "Boot_L", 0.86, V(-1, 0.1, -0.3) },
	{ "Shin_R", 0.96, V(1, 0.3, -0.2) }, { "Shin_L", 1.02, V(-1, 0.3, -0.2) },
	{ "Knee_R", 1.10, V(1, 0, -0.5) }, { "Knee_L", 1.16, V(-1, 0, -0.5) },
	{ "Thigh_R", 1.26, V(1, 0.4, -0.2) }, { "Thigh_L", 1.32, V(-1, 0.4, -0.2) },
	{ "Belt", 1.45, V(0, -1, -0.4), "LOWER BODY" },
	{ "Abdomen", 1.55, V(-1, 0, -0.3) },
	{ "Chest", 1.68, V(0, 0.4, -1), "TORSO PLATE" },
	{ "Backpack", 1.78, V(0.3, 1, 0.6), "POWER CORE" },
	{ "UpperArm_R", 1.92, V(1, 0.3, 0) }, { "UpperArm_L", 1.98, V(-1, 0.3, 0) },
	{ "Gauntlet_R", 2.08, V(1, -0.3, -0.2) }, { "Gauntlet_L", 2.14, V(-1, -0.3, -0.2), "GAUNTLETS" },
	{ "Glove_R", 2.24, V(1, -1, 0) }, { "Glove_L", 2.30, V(-1, -1, 0) },
	{ "ShoulderPad_R", 2.40, V(1, 1, 0) }, { "ShoulderPad_L", 2.46, V(-1, 1, 0) },
	{ "Helmet", 3.40, V(0, 1, 0.1), "HELMET" },
	{ "Visor", 3.68, V(0, 0, -1), "VISOR  //  ONLINE" },
}
do -- exosuits split by material (2026-11-14): each piece's other parts fly in with it. Vantage's main
	-- piece is "<base>"; the wave-2 suits' main piece is "<base>__Graphite" (it carries the log line)
	local extra = {}
	for _, e in ORDER do
		for _, m in { "Base", "Graphite", "Gunmetal", "Black", "Accent", "Energy" } do
			table.insert(extra, { e[1] .. "__" .. m, e[2], e[3], if m == "Graphite" then e[4] else nil })
		end
	end
	for _, e in extra do
		table.insert(ORDER, e)
	end
end
local HELMET_AT, VISOR_AT = 3.40, 3.68
local BLACK_START, BLACK_DUR = 4.35, 0.3
-- the avatar body part each armour piece covers (it fades out as the piece locks)
local COVERS = {
	Boot_R = "RightFoot", Boot_L = "LeftFoot", Shin_R = "RightLowerLeg", Shin_L = "LeftLowerLeg",
	Thigh_R = "RightUpperLeg", Thigh_L = "LeftUpperLeg", Belt = "LowerTorso", Chest = "UpperTorso",
	UpperArm_R = "RightUpperArm", UpperArm_L = "LeftUpperArm", Gauntlet_R = "RightLowerArm", Gauntlet_L = "LeftLowerArm",
	Glove_R = "RightHand", Glove_L = "LeftHand", Helmet = "Head",
}

local skip = false
local released = false
local playing = false
local restoreLighting: (() -> ())? = nil

function SuitUp.Skip()
	skip = true
end
function SuitUp.Release()
	released = true
end
function SuitUp.IsPlaying(): boolean
	return playing
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end
-- 0 → 1 between a and b, back to 0 between c and d
local function bump(t: number, a: number, b: number, c: number, d: number): number
	return smooth((t - a) / (b - a)) * (1 - smooth((t - c) / (d - c)))
end

local function block(parent: Instance, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

local function light(parent: Instance, pos: Vector3, color: Color3, brightness: number, range: number, aimAt: Vector3?, angle: number?)
	local p = block(parent, V(0.2, 0.2, 0.2), CFrame.new(pos), color)
	p.Transparency = 1
	p.CastShadow = false
	local l
	if aimAt then
		p.CFrame = CFrame.lookAt(pos, aimAt)
		l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Front
		l.Angle = angle or 60
	else
		l = Instance.new("PointLight")
	end
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = aimAt ~= nil
	l.Parent = p
	return l
end

local function playSound(def)
	if not def then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	s.PlaybackSpeed = def.Speed or 1
	s.Parent = game:GetService("SoundService")
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

-- Load the backdrop and the armour ahead of time (the module is required while the menu is up).
-- The asset ids are preloaded by name: handing PreloadAsync the character model was not enough to
-- have the armour's texture ready, and the pieces arrived white.
local preloaded = false
local function armourRoots(): { Instance }
	local roots = {}
	local sc = StarterPlayer:FindFirstChild("StarterCharacter")
	if sc then
		table.insert(roots, sc)
	end
	local pieces = ReplicatedStorage:FindFirstChild("Vantage") and ReplicatedStorage.Vantage:FindFirstChild("Armour")
	pieces = pieces and pieces:FindFirstChild("Pieces")
	if pieces then
		table.insert(roots, pieces) -- every suit a player can pick
	end
	return roots
end
local function armourContent(): { string }
	local ids, seen = {}, {}
	for _, sc in armourRoots() do
		for _, d in sc:GetDescendants() do
			if d:IsA("MeshPart") then
				-- textures only: an id given by name is fetched as an image, so mesh ids must not go here
				local id = d.TextureID
				if id ~= "" and not seen[id] then
					seen[id] = true
					table.insert(ids, id)
				end
			end
		end
	end
	return ids
end

function SuitUp.Preload()
	task.spawn(function()
		local pg = Players.LocalPlayer:WaitForChild("PlayerGui", 20)
		local keep
		if pg and not pg:FindFirstChild("VantageSuitUpPreload") then
			-- a 2-pixel label keeps the backdrop in memory for the whole session
			local g = Instance.new("ScreenGui")
			g.Name = "VantageSuitUpPreload"
			g.ResetOnSpawn = false
			g.DisplayOrder = -100
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromOffset(2, 2)
			img.BackgroundTransparency = 1
			img.ImageTransparency = 0.98
			img.Image = SuitUp.Backdrop
			img.Parent = g
			g.Parent = pg
			keep = img
		end
		local list: { any } = armourContent()
		if keep then
			table.insert(list, keep)
		end
		local armourPieces = ReplicatedStorage:FindFirstChild("Vantage") and ReplicatedStorage.Vantage:FindFirstChild("Armour")
		armourPieces = armourPieces and armourPieces:FindFirstChild("Pieces")
		if armourPieces then
			table.insert(list, armourPieces)
		end
		local sc = StarterPlayer:FindFirstChild("StarterCharacter")
		if sc then
			table.insert(list, sc) -- the meshes themselves
			-- A mesh texture is only really made ready by a part that wears it near the camera, and
			-- that takes a few seconds the first time. So one tiny armour piece rides just behind
			-- the camera (never in view) for the whole session; by the first deploy it is long done.
			local piece = sc:FindFirstChild("Visor", true) or sc:FindFirstChildWhichIsA("MeshPart", true)
			if piece and piece:IsA("MeshPart") and not Workspace:FindFirstChild("VantageSuitUpWarm") then
				local warm = piece:Clone()
				warm:ClearAllChildren()
				warm.Name = "VantageSuitUpWarm"
				warm.Size = piece.Size * 0.1
				warm.Anchored = true
				warm.CanCollide = false
				warm.CanQuery = false
				warm.CanTouch = false
				warm.CastShadow = false
				warm.Parent = Workspace
				RunService.RenderStepped:Connect(function()
					local cam = Workspace.CurrentCamera
					if cam and warm.Parent then
						warm.CFrame = cam.CFrame * CFrame.new(0, 0, 3)
					end
				end)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		preloaded = true
	end)
end
SuitUp.Preload()

-- ── bodies ───────────────────────────────────────────────────────────────────

-- the R15 joints of a model, parents before children, with their rest frames
local function gatherJoints(model: Model, root: BasePart)
	local found = {}
	local seen = {}
	for _, d in model:GetDescendants() do
		local j
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			j = { Name = d.Name, P0 = d.Part0, P1 = d.Part1, C0 = d.C0, C1 = d.C1 }
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			j = { Name = d.Name, P0 = d.Attachment0.Parent, P1 = d.Attachment1.Parent, C0 = d.Attachment0.CFrame, C1 = d.Attachment1.CFrame }
		end
		if j and j.P0 and j.P1 and not seen[j.P1] then
			seen[j.P1] = true
			table.insert(found, j)
		end
	end
	local ordered, placed = {}, { [root] = true }
	local progress = true
	while progress do
		progress = false
		for _, j in found do
			if not j.Done and placed[j.P0] then
				j.Done = true
				placed[j.P1] = true
				table.insert(ordered, j)
				progress = true
			end
		end
	end
	return ordered
end

local function freeze(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- the suit: its bones (hidden) and its armour pieces with their place on each bone
local function buildSuit(parent: Instance, figureCF: CFrame)
	local src = StarterPlayer:FindFirstChild("StarterCharacter")
	if not src then
		return nil
	end
	local rig = src:Clone()
	rig.Name = "Suit"
	for _, d in rig:GetDescendants() do
		if d:IsA("Humanoid") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	-- the player's equipment (Shield Pack + Grappling Hook); the suit itself is the baked Mk1
	pcall(function()
		local eq = ReplicatedStorage.Vantage:FindFirstChild("Equipment")
		if eq then
			local Catalog = require(eq.EquipmentCatalog)
			local lp = Players.LocalPlayer
			require(eq.EquipmentBuild).Dress(rig, Catalog.Equipped(lp, "Pack"), Catalog.Equipped(lp, "Hook"))
		end
	end)
	freeze(rig)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	rig.PrimaryPart = root
	rig:PivotTo(figureCF * CFrame.new(0, 3, 0))
	local pieces = {}
	local feet = {}
	for _, bone in rig:GetChildren() do
		if bone:IsA("BasePart") then
			bone.Transparency = 1
			bone.CastShadow = false
			if string.find(bone.Name, "Foot") then
				table.insert(feet, bone)
			end
			for _, c in bone:GetChildren() do
				if c:IsA("MeshPart") then
					pieces[c.Name] = { Part = c, Bone = bone, Off = bone.CFrame:ToObjectSpace(c.CFrame), Size = c.Size,
						-- textured armour is tinted to the bay light; the plain-coloured Vantage suit keeps its own colours
						Base = if c.TextureID ~= "" then TINT else c.Color }
					c.Transparency = 1
					c.CastShadow = false
					c.Color = TINT
					for _, w in c:GetChildren() do
						if w:IsA("JointInstance") then
							w:Destroy()
						end
					end
				end
			end
		end
	end
	local body = { Model = rig, Root = root, Joints = gatherJoints(rig, root), Feet = feet, Follow = {} }
	rig.Parent = parent
	return body, pieces
end

-- the player's own avatar, as built by the server for the menu; nothing about it is changed
local function buildAvatar(parent: Instance, figureCF: CFrame)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local src = pg and pg:FindFirstChild("VantageMenuAvatar")
	if not (src and src:IsA("Model") and src:FindFirstChild("HumanoidRootPart")) then
		return nil
	end
	local av = src:Clone()
	av.Name = "Avatar"
	local root = av:FindFirstChild("HumanoidRootPart") :: BasePart
	av.PrimaryPart = root
	av:PivotTo(figureCF * CFrame.new(0, 3, 0))
	freeze(av)
	root.Transparency = 1
	local groups: { [string]: { Instance } } = {}
	local function add(name: string, inst: Instance)
		groups[name] = groups[name] or {}
		table.insert(groups[name], inst)
	end
	local follow = {}
	local feet = {}
	for _, child in av:GetChildren() do
		if child:IsA("Accessory") then
			-- accessories ride on (and leave with) the body part they are worn on
			-- (the stored model is not assembled, so the place comes from the accessory's own joint)
			local handle = child:FindFirstChild("Handle")
			local on, off
			if handle and handle:IsA("BasePart") then
				for _, c in handle:GetChildren() do
					if c:IsA("Constraint") and c.Attachment0 and c.Attachment1 then
						local a0, a1 = c.Attachment0, c.Attachment1
						if a0.Parent == handle and a1.Parent and a1.Parent:IsA("BasePart") then
							on, off = a1.Parent, a1.CFrame * a0.CFrame:Inverse()
						elseif a1.Parent == handle and a0.Parent and a0.Parent:IsA("BasePart") then
							on, off = a0.Parent, a0.CFrame * a1.CFrame:Inverse()
						end
					elseif c:IsA("JointInstance") and c.Part0 and c.Part1 then
						if c.Part0 == handle then
							on, off = c.Part1, c.C1 * c.C0:Inverse()
						else
							on, off = c.Part0, c.C0 * c.C1:Inverse()
						end
					end
					if on then
						break
					end
				end
			end
			if handle and on and off and on ~= handle then
				table.insert(follow, { Part = handle, On = on, Off = off })
				add(on.Name, handle)
			end
		elseif child:IsA("BasePart") and child ~= root then
			add(child.Name, child)
			for _, d in child:GetChildren() do
				if d:IsA("Decal") then
					add(child.Name, d)
				end
			end
			if string.find(child.Name, "Foot") then
				table.insert(feet, child)
			end
		end
	end
	local hum = av:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local body = { Model = av, Root = root, Joints = gatherJoints(av, root), Feet = feet, Follow = follow }
	av.Parent = parent
	return body, groups
end

-- pose one body: forward kinematics down its joints, then drop it so its lowest foot is on the floor
local function poseBody(body, rootCF: CFrame, pose: { [string]: CFrame }, floorY: number)
	body.Root.CFrame = rootCF
	for _, j in body.Joints do
		-- the pose turns the child about the joint point in the parent's own axes, so it means the
		-- same thing on classic Motor6D rigs and on avatars whose joint attachments are rotated
		j.P1.CFrame = j.P0.CFrame * CFrame.new(j.C0.Position) * (pose[j.Name] or CFrame.identity) * j.C0.Rotation * j.C1:Inverse()
	end
	local low = math.huge
	for _, foot in body.Feet do
		local h = foot.Size / 2
		for dx = -1, 1, 2 do
			for dz = -1, 1, 2 do
				low = math.min(low, (foot.CFrame * V(h.X * dx, -h.Y, h.Z * dz)).Y)
			end
		end
	end
	if low < math.huge then
		local shift = V(0, floorY - low, 0)
		body.Root.CFrame += shift
		for _, j in body.Joints do
			j.P1.CFrame += shift
		end
	end
	for _, f in body.Follow do
		f.Part.CFrame = f.On.CFrame * f.Off
	end
end

-- ── the performance ──────────────────────────────────────────────────────────
-- Joint angles (degrees) for time t. R15 joint space: X pitches (+ = forward/up for arms and
-- head-up for the neck), Y turns, Z rolls (+ = right arm/leg outward).
local function performance(t: number, lastLockAt: number, lastLockSide: number): { [string]: CFrame }
	local breath = math.sin(t * 2.1)
	local sway = math.sin(t * 1.15 + 0.6)
	local settle = smooth(t / 0.9) -- eases into the stance as the shot fades in
	-- looks down at the legs as they lock, then at the right gauntlet, dips for the helmet, lifts for the visor
	local lookLegs = bump(t, 0.55, 0.95, 1.45, 1.85)
	local check = bump(t, 2.3, 2.7, 2.95, 3.3) -- right forearm comes up to be looked at
	local dip = bump(t, 3.05, 3.3, 3.5, 3.8)
	local proud = smooth((t - VISOR_AT) / 0.45)
	-- a small jolt through the body each time a piece slams on
	local k = math.exp(-11 * math.max(0, t - lastLockAt)) * (if t >= lastLockAt then 1 else 0)
	local jx, jz = -1.6 * k, lastLockSide * 1.8 * k

	local pose = {}
	pose.Root = CFrame.new(0.05 * settle, -0.02 * (1 + breath) * 0.5, 0) * A(rad(1.2 * proud), rad(4 * settle), rad(2.2 * settle + 0.7 * sway))
	pose.Waist = A(rad(3 + 1.1 * breath + jx - 5 * proud - 4 * lookLegs), rad(-5 * settle + 6 * check), rad(-3 * settle - 0.5 * sway + jz))
	pose.Neck = A(
		rad(2 - 0.6 * breath - 24 * lookLegs - 20 * check - 12 * dip + 7 * proud),
		rad(10 * settle * (1 - proud) - 26 * check - 8 * lookLegs),
		rad(2 * settle - 4 * check)
	)
	pose.RightShoulder = A(rad(5 + 34 * check + 0.8 * breath - 3 * proud), rad(-10 * check), rad(8 + 0.8 * breath + 4 * check + 3 * proud))
	pose.RightElbow = A(rad(14 + 68 * check - 4 * proud), 0, 0)
	pose.RightWrist = A(rad(-6 * check), rad(-25 * check), 0)
	pose.LeftShoulder = A(rad(2 + 5 * check + 0.8 * breath - 3 * proud), 0, rad(-7 - 0.8 * breath - 3 * proud))
	pose.LeftElbow = A(rad(9 + 10 * check - 2 * proud), 0, 0)
	pose.RightHip = A(rad(6 * settle), rad(-6 * settle), rad(3 * settle))
	pose.RightKnee = A(rad(-9 * settle), 0, 0)
	pose.RightAnkle = A(rad(3 * settle), 0, rad(-3 * settle))
	pose.LeftHip = A(rad(-3 * settle), rad(8 * settle), rad(-4 * settle - 0.7 * sway))
	pose.LeftKnee = A(rad(-2 * settle), 0, 0)
	pose.LeftAnkle = A(rad(5 * settle), 0, rad(4 * settle + 0.7 * sway))
	return pose
end

local function playInner(opts)
	playing, skip, released = true, false, false
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera

	-- our own black cover, so nothing of the world shows while the menu is swapped out
	local gui = Instance.new("ScreenGui")
	gui.Name = "VantageSuitUp"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9000
	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BorderSizePixel = 0
	cover.ZIndex = 10
	cover.Parent = gui
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = GREEN
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 5
	flash.Parent = gui
	local log = Instance.new("TextLabel")
	log.BackgroundTransparency = 1
	log.AnchorPoint = Vector2.new(0, 1)
	log.Position = UDim2.new(0, 56, 1, -52)
	log.Size = UDim2.fromOffset(700, 190)
	log.Font = Enum.Font.RobotoMono
	log.TextSize = 20
	log.TextColor3 = LIME
	log.TextStrokeTransparency = 0.6
	log.TextXAlignment = Enum.TextXAlignment.Left
	log.TextYAlignment = Enum.TextYAlignment.Bottom
	log.Text = ""
	log.Parent = gui
	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Position = UDim2.fromOffset(56, 46)
	head.Size = UDim2.fromOffset(700, 26)
	head.Font = Enum.Font.RobotoMono
	head.TextSize = 18
	head.TextColor3 = LIME
	head.TextStrokeTransparency = 0.6
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Text = "EXO MK1  //  SEAL SEQUENCE"
	head.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	if opts.Hide then
		opts.Hide()
	end

	-- anything the visor draws in front of the camera stays off during the shot
	local hiddenGuis = {}
	local holo = Workspace:FindFirstChild("VantageVisorHolo")
	if holo then
		for _, d in holo:GetDescendants() do
			if d:IsA("SurfaceGui") and d.Enabled then
				d.Enabled = false
				table.insert(hiddenGuis, d)
			end
		end
	end

	-- the bay is dark: turn the world's ambient light down for this client until the shot ends
	local savedAmbient, savedOutdoor = Lighting.Ambient, Lighting.OutdoorAmbient
	restoreLighting = function()
		Lighting.Ambient, Lighting.OutdoorAmbient = savedAmbient, savedOutdoor
		restoreLighting = nil
	end
	Lighting.Ambient = Color3.fromRGB(30, 35, 44)
	Lighting.OutdoorAmbient = Color3.fromRGB(30, 35, 44)

	local scene = Instance.new("Folder")
	scene.Name = "VantageSuitUpScene"
	scene.Parent = Workspace

	-- closed black box round everything, so the sun and sky never reach the figure
	local black = Color3.new(0, 0, 0)
	for _, s in { { V(120, 2, 120), V(0, -30, -10) }, { V(120, 2, 120), V(0, 50, -10) }, { V(2, 82, 120), V(-60, 10, -10) }, { V(2, 82, 120), V(60, 10, -10) }, { V(120, 82, 2), V(0, 10, -70) }, { V(120, 82, 2), V(0, 10, 50) } } do
		block(scene, s[1], CFrame.new(ORIGIN + s[2]), black)
	end

	-- camera: locked off, matched to the picture
	local camPos = ORIGIN + V(0, CAM_HEIGHT, 0)
	local camCF = CFrame.new(camPos) * A(rad(HORIZON), 0, 0)
	local vp = camera.ViewportSize
	local aspect = if vp.Y > 0 then vp.X / vp.Y else 16 / 9
	-- wider screens crop the picture top and bottom, narrower ones crop its sides
	local fov = math.deg(2 * math.atan(math.tan(rad(VFOV / 2)) * math.min(1, (16 / 9) / aspect)))

	-- the backdrop: a self-lit plate that exactly fills the picture's own field of view
	local plateH = 2 * PLATE_DIST * math.tan(rad(VFOV / 2))
	local plate = block(scene, V(plateH * 16 / 9, plateH, 0.2), camCF * CFrame.new(0, 0, -PLATE_DIST), black)
	plate.CastShadow = false
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.LightInfluence = 0
	sg.Brightness = 1
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(1920, 1080)
	sg.Parent = plate
	local pic = Instance.new("ImageLabel")
	pic.Size = UDim2.fromScale(1, 1)
	pic.BackgroundColor3 = black
	pic.BorderSizePixel = 0
	pic.Image = SuitUp.Backdrop
	pic.Parent = sg

	-- the operative's spot on the bay floor
	local floorPoint = ORIGIN + STAND
	local figureCF = CFrame.new(floorPoint) * A(0, rad(FACING), 0)
	local chest = floorPoint + V(0, 3.4, 0)

	-- contact shadow: soft, stretched toward the camera because the light is behind the figure
	local kitOk, kit = pcall(require, ReplicatedStorage.Vantage.UI.VisorKit)
	if kitOk and kit and kit.Glow then
		for _, s in { { V(3.4, 0.05, 2.6), V(0, 0.03, 0.2), 0.1 }, { V(5.2, 0.05, 7.5), V(-0.3, 0.02, 2.2), 0.45 } } do
			local sh = block(scene, s[1], CFrame.new(floorPoint + s[2]), black)
			sh.Transparency = 1
			sh.CastShadow = false
			local ssg = Instance.new("SurfaceGui")
			ssg.Face = Enum.NormalId.Top
			ssg.LightInfluence = 0
			ssg.Parent = sh
			local blob = Instance.new("ImageLabel")
			blob.Size = UDim2.fromScale(1, 1)
			blob.BackgroundTransparency = 1
			blob.Image = kit.Glow
			blob.ImageColor3 = black
			blob.ImageTransparency = s[3]
			blob.Parent = ssg
		end
	end

	-- lighting, copied from the picture: cold daylight from the open ramp behind (camera right),
	-- a weaker edge from the left, a faint cool fill from the door lamp, green from the crates
	light(scene, floorPoint + V(4.5, 6.5, -7), Color3.fromRGB(196, 218, 240), 3.2, 24, chest, 70)
	light(scene, floorPoint + V(-5, 5, -5), Color3.fromRGB(150, 176, 205), 1.1, 20, chest, 70)
	light(scene, floorPoint + V(-4.5, 4, 5), Color3.fromRGB(120, 140, 165), 0.14, 16)
	light(scene, floorPoint + V(4.5, 1.2, 3), GREEN, 0.28, 10)

	local suit, suitPieces = buildSuit(scene, figureCF)
	local avatar, groups = buildAvatar(scene, figureCF)
	local pieces = {}
	local fades = {}
	local lockLight
	if suit and suitPieces then
		local frame = figureCF.Rotation
		for _, e in ORDER do
			local sp = suitPieces[e[1]]
			if sp then
				table.insert(pieces, {
					Name = e[1], Part = sp.Part, Bone = sp.Bone, Off = sp.Off, Size = sp.Size, Base = sp.Base, Lock = e[2],
					Dir = frame:VectorToWorldSpace(e[3].Unit), Side = if e[3].X > 0.3 then -1 elseif e[3].X < -0.3 then 1 else 0,
					Line = e[4], Spin = if e[3].X < 0 then -80 else 80, Started = false, Locked = false,
					Fade = groups and groups[COVERS[e[1]] or ""],
				})
			end
		end
		lockLight = light(scene, floorPoint, GREEN, 0, 6)
	end
	local hood = suitPieces and suitPieces.Neck

	-- Point the camera at the bay first (the screen is still black): a picture on a surface far
	-- from the camera is never loaded, so waiting for it before moving the camera would wait forever.
	local saved = { Type = camera.CameraType, CFrame = camera.CFrame, FOV = camera.FieldOfView }
	local waitStart = os.clock()
	repeat
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camCF
		camera.FieldOfView = fov
		task.wait()
	until (pic.IsLoaded and preloaded) or os.clock() - waitStart > 3 or skip

	local lines = {}
	local t0 = os.clock()
	local holdStart
	local function now(): number
		local t = os.clock() - t0
		if opts.HoldAt and not released then
			if t >= opts.HoldAt then
				holdStart = holdStart or os.clock()
				if os.clock() - holdStart > 60 then
					released = true
				end
				t0 = os.clock() - opts.HoldAt
				return opts.HoldAt
			end
		end
		return t
	end

	local lastLock, lastLockAt, lastLockSide = nil, -10, 0
	local rootCF = figureCF * CFrame.new(0, 3, 0)
	local function step(t: number)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camCF
		camera.FieldOfView = fov
		cover.BackgroundTransparency = math.min(clamp01(t / 0.5), 1 - clamp01((t - BLACK_START) / BLACK_DUR))
		local textOut = clamp01((t - BLACK_START + 0.1) / 0.25)
		head.TextTransparency = 0.25 + 0.75 * math.max(1 - clamp01((t - 0.3) / 0.4), textOut)
		log.TextTransparency = 0.1 + 0.9 * textOut

		-- both bodies take the same pose
		local pose = performance(t, lastLockAt, lastLockSide)
		if suit then
			poseBody(suit, rootCF, pose, floorPoint.Y)
		end
		if avatar then
			poseBody(avatar, rootCF, pose, floorPoint.Y)
		end

		for _, pc in pieces do
			local p = (t - (pc.Lock - FLY)) / FLY
			local part = pc.Part
			local home = pc.Bone.CFrame * pc.Off -- follows the moving body
			if p <= 0 then
				part.Transparency = 1
				part.CFrame = home
			elseif p < 1 then
				if not pc.Started then
					pc.Started = true
					if not string.find(pc.Name, "__", 1, true) or string.find(pc.Name, "__Graphite", 1, true) then
						playSound(SuitUp.Sounds.Slide)
					end
				end
				local e = p * p * p -- hangs back, then slams home
				part.Transparency = 1 - clamp01(p * 3)
				part.Size = pc.Size * (1 + 0.22 * (1 - e))
				part.CFrame = CFrame.new(pc.Dir * (1 - e) * 7.5) * home * A(0, rad((1 - e) * pc.Spin), 0)
				part.Color = GREEN
			else
				if not pc.Locked then
					pc.Locked = true
					lastLock, lastLockAt, lastLockSide = pc, pc.Lock, pc.Side
					part.Transparency = 0
					part.Size = pc.Size
					part.CastShadow = true
					if pc.Fade then
						table.insert(fades, { List = pc.Fade, At = pc.Lock })
					end
					if not string.find(pc.Name, "__", 1, true) or string.find(pc.Name, "__Graphite", 1, true) then
						playSound(SuitUp.Sounds.Lock)
						playSound(SuitUp.Sounds.LockThump)
					end
					if pc.Name == "Helmet" or pc.Name == "Helmet__Graphite" then
						playSound(SuitUp.Sounds.Helmet)
					elseif pc.Name == "Visor" then
						playSound(SuitUp.Sounds.Visor)
					end
					if pc.Line then
						table.insert(lines, "> " .. pc.Line .. (if pc.Name == "Visor" then "" else "  //  LOCKED"))
						log.Text = table.concat(lines, "\n")
					end
				end
				part.CFrame = home
				-- the piece flashes green as it locks, then settles to its own colours
				if pc.Name == "Visor" then
					part.Color = pc.Base or GREEN:Lerp(Color3.new(1, 1, 1), 0.3) -- the suit's own visor colour
				else
					part.Color = GREEN:Lerp(pc.Base or TINT, clamp01((t - pc.Lock) / 0.3))
				end
			end
		end
		-- the undersuit hood appears under the helmet as the avatar's head gives way
		if hood then
			hood.Part.CFrame = hood.Bone.CFrame * hood.Off
			hood.Part.Transparency = 1 - clamp01((t - HELMET_AT) / 0.1)
		end
		-- the avatar gives way under each piece
		for _, f in fades do
			local a = clamp01((t - f.At) / 0.12)
			for _, inst in f.List do
				(inst :: any).Transparency = a
			end
		end
		if lockLight and lastLock then
			lockLight.Brightness = 1.2 * (1 - clamp01((t - lastLockAt) / 0.3))
			local holder = lockLight.Parent :: BasePart
			holder.CFrame = CFrame.new((lastLock.Bone.CFrame * lastLock.Off).Position + lastLock.Dir * 0.8)
		end
		-- visor ignition washes the frame green for a moment
		local vq = (t - VISOR_AT) / 0.35
		flash.BackgroundTransparency = if vq >= 0 and vq < 1 then 0.8 + 0.2 * vq else 1
	end

	local ok, err = pcall(function()
		while true do
			local t = now()
			if t >= SuitUp.Length or skip then
				break
			end
			step(t)
			RunService.RenderStepped:Wait()
		end
	end)
	if not ok then
		warn("[VANTAGE] SuitUp:", err)
	end

	-- end on black, put everything back
	if cover.BackgroundTransparency > 0.02 then
		local a0, s0 = cover.BackgroundTransparency, os.clock()
		while os.clock() - s0 < 0.15 do
			cover.BackgroundTransparency = a0 * (1 - (os.clock() - s0) / 0.15)
			RunService.RenderStepped:Wait()
		end
	end
	cover.BackgroundTransparency = 0
	head.Visible, log.Visible, flash.Visible = false, false, false
	scene:Destroy()
	if restoreLighting then
		restoreLighting()
	end
	camera.CameraType = saved.Type
	camera.FieldOfView = saved.FOV
	camera.CFrame = saved.CFrame
	for _, d in hiddenGuis do
		if d.Parent then
			d.Enabled = true
		end
	end
	if opts.Show then
		opts.Show()
	end
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	gui:Destroy()
	playing = false
end

SuitUp.Enabled = false -- 2026-11-17: armour retired, players are their own avatars; the suit-up shot is skipped
function SuitUp.Play(opts)
	if not SuitUp.Enabled then
		return
	end
	opts = opts or {}
	if playing then
		return
	end
	local camera = Workspace.CurrentCamera
	local saved = { Type = camera.CameraType, CFrame = camera.CFrame, FOV = camera.FieldOfView }
	local ok, err = pcall(playInner, opts)
	if not ok then
		-- never leave the player on a black screen, a stray camera or dimmed lighting
		warn("[VANTAGE] SuitUp failed:", err)
		local scene = Workspace:FindFirstChild("VantageSuitUpScene")
		if scene then
			scene:Destroy()
		end
		if restoreLighting then
			restoreLighting()
		end
		camera.CameraType = saved.Type
		camera.FieldOfView = saved.FOV
		camera.CFrame = saved.CFrame
		local holo = Workspace:FindFirstChild("VantageVisorHolo")
		if holo then
			for _, d in holo:GetDescendants() do
				if d:IsA("SurfaceGui") then
					d.Enabled = true
				end
			end
		end
		if opts.Show then
			pcall(opts.Show)
		end
		local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local g = pg and pg:FindFirstChild("VantageSuitUp")
		if g then
			g:Destroy()
		end
		playing = false
	end
end

return SuitUp
