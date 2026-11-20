--[[
	VANTAGE - OperativeIntro (client)
	The pre-match operative introductions: phase "Intro" (MatchService -> IntroService), between
	the dropship and Prep. The server has everyone spawned, lined up shoulder to shoulder and held;
	this module plays the show from Match attribute "Intro" (see IntroService for its fields):

	  * per team, ONE continuous camera move: it slides along the line and settles on each
	    operative in turn (their stance animation, dealt by the server, plays as it arrives, with a
	    nameplate beside them: name, suit, weapon and skin), then pulls back to the whole squad
	    with the team mark. Blue first, then Red; the only cut is between the teams;
	  * every time comes from the plan's Start in server time and MatchConfig.IntroSchedule, so all
	    players see the same thing at the same moment, whatever the match size;
	  * an operative alone on its team (1v1) gets a long push in from low and wide instead.

	Nothing here is authoritative and nothing outlives the phase. While it runs: the camera is
	Scriptable, other ScreenGuis / the visor panels / the first-person viewmodel are hidden, input
	is sunk, joints are posed by hand on Stepped (ThirdPersonRig is suspended), a local colour
	grade and depth of field are on. When it ends, for any reason (phase over, match cancelled, an
	error), cleanup() puts every one of those back.

	Adding an animation: put a function in ANIMS (it returns pose parameters for progress 0..1)
	and its name in MatchConfig.Intro.Anims.
	Studio: player attribute "IntroHoldAt" (seconds) freezes the timeline there for screenshots.
]]

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local MatchConfig = require(Vantage:WaitForChild("MatchConfig"))
local Weapons = Vantage:WaitForChild("Weapons")
local WeaponConfig = require(Weapons:WaitForChild("WeaponConfig"))
local Skins = require(Weapons:WaitForChild("Skins"))
local ArmRig = require(Weapons:WaitForChild("ArmRig"))
local Kit = require(script.Parent:WaitForChild("LimeKit"))
local ThirdPersonRig = require(script.Parent:WaitForChild("ThirdPersonRig"))

local K, F = Kit.C, Kit.F
local V = Vector3.new
local rad = math.rad
local O = UDim2.fromOffset
local player = Players.LocalPlayer

local OperativeIntro = {}
local ctx = nil
local running = false

local DIP = 0.2 -- half-length of the dip to black between the two teams
local SINK = "VantageIntroSink"
local BIND = "VantageOperativeIntro"
local GREEN = Color3.fromRGB(120, 255, 70)
local SUIT_NAME = "EXO MK1"

local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end
local function H(x: number, y: number, z: number, rx: number, ry: number, rz: number): CFrame
	return CFrame.new(x, y, z) * ang(rx, ry, rz)
end
local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
-- 0 -> 1 between a and b, back to 0 between c and d
local function bump(t: number, a: number, b: number, c: number, d: number): number
	return smooth((t - a) / (b - a)) * (1 - smooth((t - c) / (d - c)))
end
local function teamColor(team: string?): Color3
	return if team == "Red" then K.Red elseif team == "Blue" then K.Blue else K.White
end

-- animations ------------------------------------------------------------------------------------
--[[ The operatives' animations are motion-capture clips (Mixamo), retargeted offline onto the
	R15 joints and stored as text in the ModuleScripts under script.Clips: one line per key frame
	(12 a second): the hips' offset, then one rotation per joint in JOINT_ORDER, two characters
	per number, and a check character. They are played by writing joint Transforms (see applyClip),
	so no animation asset has to be uploaded or owned, and every client samples the same server
	time. A clip module returns { Dur = seconds, Loops = n, Data = "..." }.
	Adding one: add its module to Clips and its name to MatchConfig.Intro.Anims. ]]
local JOINT_ORDER = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
local CLIP_LEAD = 0.25 -- seconds into its shot before an operative starts moving
local CLIP_IN, CLIP_OUT = 0.25, 0.45 -- blend from / back to the idle stance

local DIGIT = {}
do
	local n = 0
	for c = 35, 126 do
		if c ~= 92 and c ~= 93 then -- no backslash, no closing bracket
			DIGIT[c] = n
			n += 1
		end
	end
end
local LINE = 6 + #JOINT_ORDER * 6 + 1

local function decodeClip(def)
	local frames = {}
	for line in string.gmatch(def.Data, "[^\r\n]+") do
		local ok = #line == LINE
		local sum = 0
		if ok then
			for i = 1, LINE - 1 do
				local c = string.byte(line, i)
				if not DIGIT[c] then
					ok = false
					break
				end
				sum += c
			end
		end
		if ok and DIGIT[string.byte(line, LINE)] == sum % 90 then
			local function num(i: number, range: number): number
				return ((DIGIT[string.byte(line, i)] * 90 + DIGIT[string.byte(line, i + 1)]) / 8099 * 2 - 1) * range
			end
			local f = { Pos = V(num(1, 4), num(3, 4), num(5, 4)), Rot = table.create(#JOINT_ORDER) }
			for j = 1, #JOINT_ORDER do
				local i = 7 + (j - 1) * 6
				local x, y, z = num(i, 1), num(i + 2, 1), num(i + 4, 1)
				f.Rot[j] = CFrame.new(0, 0, 0, x, y, z, math.sqrt(math.max(0, 1 - x * x - y * y - z * z)))
			end
			table.insert(frames, f)
		elseif #frames > 0 then
			table.insert(frames, frames[#frames]) -- a damaged line: hold the frame before it
		end
	end
	return if #frames >= 2 then { Dur = def.Dur, Loops = def.Loops or 1, Frames = frames } else nil
end

local CLIPS = {}
do
	local folder = script:FindFirstChild("Clips")
	for _, mod in (if folder then folder:GetChildren() else {}) do
		if mod:IsA("ModuleScript") then
			local ok, def = pcall(require, mod)
			local clip = ok and type(def) == "table" and type(def.Data) == "string" and decodeClip(def)
			if clip then
				CLIPS[mod.Name] = clip
			else
				warn("[VANTAGE] OperativeIntro: clip", mod.Name, "could not be read")
			end
		end
	end
end

-- pose of a clip at `t` seconds: hips offset + one rotation per joint
local function sampleClip(clip, t: number)
	local n = #clip.Frames
	local k = math.clamp(t / clip.Dur, 0, 1) * (n - 1)
	local i = math.min(math.floor(k), n - 2)
	local w = k - i
	local a, b = clip.Frames[i + 1], clip.Frames[i + 2]
	local rot = table.create(#JOINT_ORDER)
	for j = 1, #JOINT_ORDER do
		rot[j] = a.Rot[j]:Lerp(b.Rot[j], w)
	end
	return a.Pos:Lerp(b.Pos, w), rot
end

-- rigs -------------------------------------------------------------------------------------------
local JOINTS = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}
-- the rifle slung on the back (upper-torso space), muzzle up over the right shoulder
local SLUNG = H(0.42, 0.25, 1.02, 0, 0, -16) * ang(78, 0, 0)

local function resolve(e): Model?
	if e.U and e.U ~= 0 then
		local p = Players:GetPlayerByUserId(e.U)
		return p and p.Character
	end
	local f = Workspace:FindFirstChild("VantageIntroStandIns")
	local m = f and e.M and f:FindFirstChild(e.M)
	return if m and m:IsA("Model") then m else nil
end

-- the operative's rifle motor (WeaponService.attachGun). 2026-11-18 fix: the server attaches /
-- re-attaches the gun a moment AFTER the character spawns (and again when the spawn weapon is
-- equipped), so a rig built before that had no Gun (or a destroyed motor) and the rifle sat at
-- its Hold offset on the chest for the whole intro. applyClip now re-binds it whenever stale.
local function bindGun(rig)
	local model = rig.Model
	local world = model:FindFirstChild("VantageWorldWeapon")
	local body = world and world:IsA("Model") and world.PrimaryPart
	local motor = body and body:FindFirstChild("VantageGunMotor")
	local wid = model:GetAttribute("VantageWeapon")
	local w = wid and WeaponConfig.Weapons[wid]
	if body and motor and motor:IsA("Motor6D") and motor.Part0 and motor.Part0.Name == "UpperTorso" then
		local gr = body:FindFirstChild("Handle")
		local gl = body:FindFirstChild("SupportTP") or body:FindFirstChild("Support")
		local tp = w and w.Kind == "Gun" and w.ThirdPerson or WeaponConfig.Weapons[WeaponConfig.DefaultWeapon].ThirdPerson
		rig.Gun = {
			Motor = motor,
			Right = if gr and gr:IsA("Attachment") then gr else nil,
			Left = if gl and gl:IsA("Attachment") then gl else nil,
			Hold = tp.Hold, Pivot = tp.AimPivot or V(0.4, 0.45, -0.25),
			Mag = body:FindFirstChild("VantageMagMotor"),
			Usable = (w ~= nil and w.Kind == "Gun") and gr ~= nil, -- can be held (rifle equipped)
		}
	else
		rig.Gun = nil
	end
	return rig.Gun
end

local function buildRig(model: Model, index: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local rig = { Model = model, Root = root, J = {}, Seed = index, Pieces = {}, Touched = false, Roll = {} }
	for name, partName in JOINTS do
		local part = model:FindFirstChild(partName)
		local j = part and part:FindFirstChild(name)
		if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
			rig.J[name] = j
		end
	end
	if not (rig.J.Root and rig.J.Waist) then
		return nil -- not a rig we can pose (it still appears in its shot, standing as it is)
	end
	rig.Arms = { Right = ArmRig.Read(model, "Right", 1), Left = ArmRig.Read(model, "Left", 1) }
	bindGun(rig)
	local floor = root.Position.Y - 3
	for _, bone in model:GetChildren() do
		if bone:IsA("BasePart") then
			for _, c in bone:GetChildren() do
				if c:IsA("MeshPart") then
					table.insert(rig.Pieces, { Part = c, H = clamp01((c.Position.Y - floor) / 5), Color = c.Color, Material = c.Material })
					if c.Name == "Visor" then
						rig.Visor = rig.Pieces[#rig.Pieces]
					elseif c.Name == "Backpack" then
						rig.Pack = c
					end
				end
			end
		end
	end
	rig.LeftArm = model:FindFirstChild("LeftLowerArm")
	return rig
end

-- pose -------------------------------------------------------------------------------------------
local IDLE = { -- the stance between clips (degrees), mirrored for every other operative
	RightShoulder = { 0, 0, 5 }, LeftShoulder = { 0, 0, -5 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 12, 0, 0 },
	RightHip = { 3, -6, 4 }, LeftHip = { -1, 7, -5 }, RightKnee = { -5, 0, 0 }, LeftKnee = { -3, 0, 0 },
	RightAnkle = { 2, 0, -4 }, LeftAnkle = { 4, 0, 5 },
}
local FOOT_CORNERS = { V(0.2, -0.265, -0.4), V(-0.2, -0.265, -0.4), V(0.2, -0.265, 0.4), V(-0.2, -0.265, 0.4) }

-- Writes the rig's joints: the idle stance, blended by `w` (0..1) toward a clip pose (pos, rot
-- from sampleClip), then the lower foot is put back on the floor (the suit's legs are not the
-- capture actor's, so a straight copy of the hips would float or sink).
local function applyClip(rig, pos: Vector3?, rot, w: number, tt: number)
	local J = rig.J
	local s = if rig.Seed % 2 == 0 then -1 else 1
	local breath = math.sin(tt * 2.0 + rig.Seed * 1.7)
	local sway = math.sin(tt * 1.1 + rig.Seed)
	local T = {}
	for name in J do
		local d = IDLE[name]
		T[name] = if d then ang(d[1], d[2], d[3]) else CFrame.identity
	end
	T.Root = CFrame.new(0, -0.012 * (1 + breath), 0) * ang(0, 3 * s, 0.6 * sway)
	T.Waist = ang(-2 - 1.1 * breath, -2 * s, -0.4 * sway)
	T.Neck = ang(1 + 0.6 * breath, -2 * s, 0)
	if rot and pos and w > 0 then
		for j, name in JOINT_ORDER do
			if T[name] then
				local c = if name == "Root" then CFrame.new(pos) * rot[j] else rot[j]
				T[name] = T[name]:Lerp(c, w)
			end
		end
	end
	-- feet: forward kinematics down both legs, then lift / lower the hips so the lowest sole
	-- corner sits on the floor
	local floor = rig.Root.Position.Y - 3
	local lower = ArmRig.JointChild(J.Root, rig.Root.CFrame, T.Root)
	local lowest = math.huge
	if lower then
		for _, side in { "Right", "Left" } do
			local hip, knee, ankle = J[side .. "Hip"], J[side .. "Knee"], J[side .. "Ankle"]
			if hip and knee and ankle then
				local thigh = ArmRig.JointChild(hip, lower, T[side .. "Hip"])
				local shin = thigh and ArmRig.JointChild(knee, thigh, T[side .. "Knee"])
				local foot = shin and ArmRig.JointChild(ankle, shin, T[side .. "Ankle"])
				if foot then
					for _, c in FOOT_CORNERS do
						lowest = math.min(lowest, (foot * c).Y)
					end
				end
			end
		end
	end
	if lowest < math.huge then
		T.Root = CFrame.new(0, math.clamp(floor - lowest, -1.5, 1.5), 0) * T.Root
	end
	rig.Y = T.Root.Position.Y
	rig.Touched = true
	for name, j in J do
		j.Transform = T[name]
	end
	local gun = rig.Gun
	if not gun or gun.Motor.Parent == nil or not gun.Motor:IsDescendantOf(rig.Model) then
		gun = bindGun(rig) -- the gun arrived / was swapped after the rig was built
	end
	if gun then
		gun.Motor.Transform = gun.Motor.C0:Inverse() * SLUNG * gun.Motor.C1 -- slung on the back
		if gun.Mag and gun.Mag:IsA("Motor6D") then
			gun.Mag.Transform = CFrame.identity
		end
	end
end

local function resetRig(rig)
	if rig.Touched then
		for _, j in rig.J do
			j.Transform = CFrame.identity
		end
		if rig.Gun then
			rig.Gun.Motor.Transform = CFrame.identity
		end
	end
	for _, pc in rig.Pieces do
		if pc.Part.Parent then
			pc.Part.Color = pc.Color
			pc.Part.Material = pc.Material
		end
	end
end

-- the show ---------------------------------------------------------------------------------------
local function MF()
	return Vantage:FindFirstChild("Match")
end
local function attr(name: string)
	local m = MF()
	return m and m:GetAttribute(name)
end
local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function cue(id: string, volume: number, speed: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Parent = SoundService
	s:Play()
	task.delay(5, function()
		s:Destroy()
	end)
end

-- intro music ------------------------------------------------------------------------------------
--[[ MatchConfig.Intro.Music. The drop lands on the start of the last squad shot (everyone
	introduced). The main track is started so that it reaches Drop at that moment; any time left
	before it (bigger lobbies) is filled by a second copy looping the build bars, which hands over
	to the main track on a bar line. Every position comes from server time, so all clients hear
	the drop together, and a client that starts late joins in at the right place. It lives on
	after the intro screens close and fades out when the match goes Live (or is cancelled). ]]
local stopMusic: (() -> ())? = nil
local function startMusic(plan, segs)
	if stopMusic then
		stopMusic()
	end
	local M = MatchConfig.Intro.Music
	local id = M and M.Id
	if type(id) == "number" then
		id = tostring(id)
	end
	if type(id) ~= "string" or id == "" then
		return
	end
	if tonumber(id) then
		id = "rbxassetid://" .. id
	end
	local D = nil
	for n = #segs, 1, -1 do
		if segs[n].Kind == "Team" then
			D = segs[n].Start + (M.DropOffset or 0)
			break
		end
	end
	if not D then
		return
	end
	local group = SoundService:FindFirstChild("VantageMusic")
	local function make(name: string): Sound
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = id
		s.Volume = 0
		if group and group:IsA("SoundGroup") then
			s.SoundGroup = group
		end
		s.Parent = SoundService
		return s
	end
	local loopLen = M.BuildEnd - M.BuildStart
	local tb = D - (M.Drop - M.BuildStart) -- intro time the main track is at BuildStart
	local main = make("VantageIntroMusic")
	local build = if tb > 0.05 then make("VantageIntroMusicBuild") else nil
	if build then
		build.Looped = true
		build.PlaybackRegionsEnabled = true
		build.LoopRegion = NumberRange.new(M.BuildStart, M.BuildEnd)
	end
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ main })
		end)
	end)
	local function buildPos(t: number): number
		return M.BuildStart + ((t - tb) % loopLen)
	end
	local function mainPos(t: number): number
		return M.Drop + (t - D)
	end
	local okPhase = { Intro = true, Prep = true, Countdown = true }
	local conn: RBXScriptConnection
	local outAt: number? = nil
	local handed = false
	local function finish()
		if conn then
			conn:Disconnect()
		end
		main:Destroy()
		if build then
			build:Destroy()
		end
		if stopMusic == finish then
			stopMusic = nil
		end
	end
	stopMusic = finish
	conn = RunService.Heartbeat:Connect(function()
		local t = serverNow() - plan.Start
		if not outAt and not (okPhase[attr("Phase")] and player:GetAttribute("MatchStatus") == "Match") then
			outAt = os.clock()
		end
		local out = if outAt then 1 - (os.clock() - outAt) / M.FadeOut else 1
		if out <= 0 or (main.TimeLength > 0 and mainPos(t) > main.TimeLength + 0.3) then
			finish()
			return
		end
		if t < 0 then
			return
		end
		local vol = M.Volume * clamp01(t / M.FadeIn) * out
		if build and t < tb then
			-- the repeated build bars, kept on the shared clock
			local want = buildPos(t)
			if not build.IsPlaying then
				build.TimePosition = want
				build:Play()
			else
				local d = (build.TimePosition - want + loopLen / 2) % loopLen - loopLen / 2
				if math.abs(d) > 0.15 then
					build.TimePosition = want
				end
			end
			build.Volume = vol
			return
		end
		-- the track itself (from the hand-over, or from the start in small lobbies)
		local want = mainPos(t)
		if not main.IsPlaying and not handed then
			handed = true
			main.TimePosition = math.max(0, want)
			main:Play()
		elseif main.IsPlaying and t < D + 0.5 and math.abs(main.TimePosition - want) > 0.12 then
			main.TimePosition = want -- never let the drop slip
		end
		main.Volume = vol
		if build then
			-- a very short crossfade over the bar line, then the build copy goes
			local x = clamp01((t - tb) / 0.08)
			build.Volume = vol * (1 - x)
			if x >= 1 then
				build:Destroy()
				build = nil
			end
		end
		if handed and not main.IsPlaying and main.TimeLength > 0 and want > main.TimeLength - 0.2 then
			finish()
		end
	end)
end

local function play(plan)
	local camera = Workspace.CurrentCamera
	local playerGui = player:WaitForChild("PlayerGui")
	local order = plan.Order
	local segs, total = MatchConfig.IntroSchedule(order)
	local I = MatchConfig.Intro
	pcall(startMusic, plan, segs)

	-- everything we change, so cleanup() can undo exactly that
	local S = { Guis = {}, Holo = {}, LTM = {}, Rigs = {}, Base = {}, Conns = {}, Folder = Instance.new("Folder") }
	S.Chat = select(2, pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
	end)) == true
	S.Folder.Name = "VantageIntroFX"
	S.Folder.Parent = Workspace

	local function teamFrame(teamName: string): (Vector3, Vector3, number)
		local tm = plan.Teams and plan.Teams[teamName]
		if tm then
			return V(tm.C[1], tm.C[2], tm.C[3]), V(tm.D[1], 0, tm.D[2]).Unit, tm.N or 1
		end
		return camera.CFrame.Position, V(0, 0, -1), 1
	end

	-- screen: black cover, letterbox, the nameplate ------------------------------------------------
	local gui = Kit.new("ScreenGui", { Name = "VantageOperativeIntro", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9500, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	S.Gui = gui
	local cover = Kit.new("Frame", { Name = "Cover", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 50 }, gui)
	local barTop = Kit.new("Frame", { Name = "BarTop", Size = UDim2.new(1, 0, 0.07, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 20 }, gui)
	local barBot = Kit.new("Frame", { Name = "BarBot", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.07, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 20 }, gui)
	local plate = Kit.new("CanvasGroup", { Name = "Nameplate", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.58, 0.6), Size = O(520, 96), BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = 10 }, gui)
	local plateScale = Kit.new("UIScale", {}, plate)
	local pBack = Kit.rect(plate, 0, 0, 520, 96, K.Obs, 0.35, 1)
	pBack.Size = UDim2.fromScale(1, 1)
	Kit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, pBack)
	local pBar = Kit.rect(plate, 0, 0, 4, 96, K.White, 0, 3)
	local pNum = Kit.text(plate, { Position = O(18, 12), Size = O(60, 72), Text = "01", FontFace = F.Head, TextSize = 52, ZIndex = 3 })
	local pName = Kit.text(plate, { Position = O(84, 14), Size = O(420, 40), Text = "", FontFace = F.Head, TextSize = 34, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	local pKit = Kit.text(plate, { Position = O(86, 58), Size = O(420, 20), Text = "", FontFace = F.MonoM, TextSize = 12, TextColor3 = K.Muted, ZIndex = 3 })
	local function fit()
		local vp = camera.ViewportSize
		plateScale.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.45, 2)
	end
	fit()

	-- the team mark that rises in front of the line for the squad shot -----------------------------
	local marks = {}
	for teamName in plan.Teams or {} do
		local c, d, n = teamFrame(teamName)
		local color = teamColor(teamName)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = V(0.2, 0.2, 0.2)
		p.Position = c + d * 3.2 + V(0, 0.95, 0)
		p.Parent = S.Folder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(8.4, 2.4)
		bb.LightInfluence = 0
		bb.Brightness = 3
		bb.MaxDistance = 400
		bb.Parent = p
		local cg = Kit.new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1 }, bb)
		Kit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.06), Size = UDim2.fromScale(0.5, 0.025), BackgroundColor3 = color, BorderSizePixel = 0 }, cg)
		Kit.new("TextLabel", { Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.62), BackgroundTransparency = 1, Text = Kit.spaced(string.upper(teamName), 2), FontFace = F.Head, TextScaled = true, TextColor3 = color }, cg)
		Kit.new("TextLabel", { Position = UDim2.fromScale(0, 0.76), Size = UDim2.fromScale(1, 0.17), BackgroundTransparency = 1, Text = string.format("TEAM   //   %d %s", n, if n == 1 then "OPERATIVE" else "OPERATIVES"), FontFace = F.MonoM, TextScaled = true, TextColor3 = K.White }, cg)
		marks[teamName] = cg
	end

	-- lights that follow the operative on screen, flames, wrist blink (client-only parts) ------------
	local function ghost(): Part
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = V(0.2, 0.2, 0.2)
		p.Parent = S.Folder
		return p
	end
	local function lamp(color: Color3, range: number)
		local p = ghost()
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range, l.Shadows = color, 0, range, false
		l.Parent = p
		return p, l
	end
	local keyPart, keyLight = lamp(Color3.fromRGB(255, 226, 190), 14)
	local rimPart, rimLight = lamp(K.White, 12)
	local fxPart, fxLight = lamp(GREEN, 8)
	local flames = {}
	for i = 1, 2 do
		local f = ghost()
		f.Material = Enum.Material.Neon
		f.Color = Color3.fromRGB(170, 235, 255)
		f.Shape = Enum.PartType.Ball
		flames[i] = f
	end
	local blink = ghost()
	blink.Material = Enum.Material.Neon
	blink.Color = GREEN
	blink.Size = V(0.2, 0.05, 0.3)

	-- grade: darker, warmer, shallow focus (local to this client, removed in cleanup)
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "VantageIntroGrade"
	grade.Brightness, grade.Contrast, grade.Saturation = -0.07, 0.16, -0.12
	grade.TintColor = Color3.fromRGB(255, 240, 226)
	grade.Parent = Lighting
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "VantageIntroFocus"
	dof.NearIntensity, dof.FarIntensity, dof.InFocusRadius, dof.FocusDistance = 0, 0.42, 4, 6
	dof.Parent = Lighting

	-- take the stage ------------------------------------------------------------------------------
	ThirdPersonRig.Suspended = true
	if ctx and ctx.Input then
		ctx.Input:SetBlocked(true)
	end
	pcall(function()
		ContextActionService:BindActionAtPriority(SINK, function()
			return Enum.ContextActionResult.Sink
		end, false, 9000, Enum.UserInputType.Keyboard, Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3, Enum.UserInputType.MouseWheel, Enum.UserInputType.Gamepad1)
	end)
	-- our own root is held by the server, but the first-person controls still turn it locally
	local myHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if myHum then
		S.Hum, S.AutoRotate = myHum, myHum.AutoRotate
		myHum.AutoRotate = false
	end

	local function rigFor(i: number)
		local model = resolve(order[i])
		local rig = S.Rigs[i]
		if rig and rig.Model == model and model and model.Parent then
			return rig
		end
		if rig then
			pcall(resetRig, rig)
			S.Rigs[i] = nil
		end
		if model and model.Parent then
			rig = buildRig(model, i)
			S.Rigs[i] = rig
			return rig
		end
		return nil
	end

	-- where operative i stands: position from its root, facing from the plan (never the live
	-- rotation, which a client may have turned)
	local function baseOf(i: number): CFrame
		local rig = rigFor(i)
		local c, d = teamFrame(order[i].T)
		if rig then
			local p = rig.Root.Position
			S.Base[i] = CFrame.lookAt(p, p + d)
		end
		return S.Base[i] or CFrame.lookAt(c + V(0, 3, 0), c + V(0, 3, 0) + d)
	end

	local function segmentAt(t: number)
		for n = #segs, 1, -1 do
			if t >= segs[n].Start then
				return segs[n], n
			end
		end
		return segs[1], 1
	end

	local studio = RunService:IsStudio()
	local function held(): number?
		local h = if studio then player:GetAttribute("IntroHoldAt") else nil
		return if type(h) == "number" then h else nil
	end
	local function clock(): number
		local t = serverNow() - plan.Start
		local h = held()
		return if h and t > h then h else t
	end

	local soloOf = {}
	for _, sg in segs do
		if sg.Kind == "Solo" then
			soloOf[sg.Index] = sg
		end
	end
	local teamSize = {}
	for _, e in order do
		teamSize[e.T] = (teamSize[e.T] or 0) + 1
	end
	-- operative i's clip at time t: pose and blend weight (0 = idle stance)
	local warned = false
	local function clipFor(i: number, t: number)
		local sg = soloOf[i]
		local clip = CLIPS[order[i].A]
		if not (sg and clip) then
			return nil, nil, 0
		end
		local ct = t - sg.Start - CLIP_LEAD
		local total = clip.Dur * clip.Loops
		if ct <= 0 or ct >= total + CLIP_OUT then
			return nil, nil, 0
		end
		local w = math.min(smooth(ct / CLIP_IN), 1 - smooth((ct - total) / CLIP_OUT))
		local pos, rot = sampleClip(clip, if ct >= total then clip.Dur else ct % clip.Dur)
		return pos, rot, w
	end

	-- joints: every operative, every frame, after the Animator -------------------------------------
	table.insert(S.Conns, RunService.Stepped:Connect(function()
		local t = clock()
		local tt = os.clock()
		for i = 1, #order do
			local rig = rigFor(i)
			if rig then
				if rig.Model == player.Character then
					local b = baseOf(i)
					if rig.Root.CFrame.LookVector:Dot(b.LookVector) < 0.9999 then
						rig.Root.CFrame = b
					end
				end
				local pos, rot, w = clipFor(i, t)
				local ok, err = pcall(applyClip, rig, pos, rot, w, tt)
				if not ok and not warned then
					warned = true
					warn("[VANTAGE] OperativeIntro pose:", err)
				end
				-- the visor comes on as the operative's shot starts and stays on
				local own = soloOf[i]
				local visor = if own then smooth((t - own.Start - CLIP_LEAD) / 0.3) else 1
				local pc = rig.Visor
				if pc then
					if visor > 0.02 then
						pc.Part.Material = Enum.Material.Neon
						pc.Part.Color = pc.Color:Lerp(Color3.fromRGB(150, 255, 110), visor * (0.75 + 0.25 * math.sin(tt * 3 + i)))
					else
						pc.Part.Material = pc.Material
						pc.Part.Color = pc.Color
					end
				end
			end
		end
	end))

	-- camera ---------------------------------------------------------------------------------------
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local function clearView(target: Vector3, pos: Vector3): Vector3
		local ignore = { S.Folder, camera }
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		for _, name in { "VantageIntroStandIns", "VantageSpawnZone" } do
			local f = Workspace:FindFirstChild(name)
			if f then
				table.insert(ignore, f)
			end
		end
		rayParams.FilterDescendantsInstances = ignore
		local d = pos - target
		local hit = Workspace:Raycast(target, d, rayParams)
		if hit and hit.Instance.Transparency < 0.9 then
			-- pull in front of a wall, but never into the operative's face
			return target + d.Unit * math.max(math.min(4.2, d.Magnitude), (hit.Position - target).Magnitude - 0.7)
		end
		return pos
	end

	-- operative-space points: X = its right, Y = up from the root, Z = out in front of it
	local function at(base: CFrame, x: number, y: number, z: number): Vector3
		return base:PointToWorldSpace(V(x, y, -z))
	end
	-- the camera rides up and down with an operative that leaves the ground or kneels
	local function follow(i: number): number
		local rig = S.Rigs[i]
		return if rig and rig.Y then math.clamp(rig.Y * 0.6, -0.6, 1.2) else 0
	end
	-- the settled medium shot on operative i (k 0..1 = slow drift while it holds). The operative
	-- sits left of centre, the nameplate goes in the space on the right.
	local function mediumShot(i: number, k: number): (Vector3, Vector3, number)
		local b = baseOf(i)
		local x = -1.15 - 0.3 * k
		local y = follow(i)
		return at(b, x, 0.85 + y, 7.2 - 0.5 * k), at(b, x, 0.8 + y, 0), 37
	end
	local function wideShot(teamName: string, u: number): (Vector3, Vector3, number)
		local c, d, n = teamFrame(teamName)
		local right = d:Cross(Vector3.yAxis)
		local e = smooth(u)
		local dist = lerp(9.5 + 2.1 * n, 8.2 + 1.9 * n, e)
		return c + d * dist + right * lerp(0.8, 0, e) + V(0, 2.4, 0), c + V(0, 3.1, 0), 43
	end

	local function shotAt(t: number): (Vector3, Vector3, number, number)
		local sg, n = segmentAt(math.max(t, 0))
		local prev = segs[n - 1]
		local sameTeam = prev ~= nil and prev.Team == sg.Team
		local u = clamp01((t - sg.Start) / sg.Dur)
		if sg.Kind == "Solo" then
			local i = sg.Index
			local p1, l1, f1 = mediumShot(i, u)
			local p0, l0, f0
			local blend = math.min(0.6, sg.Dur * 0.42)
			if teamSize[sg.Team] == 1 then
				-- alone (1v1): a long push in from low and wide
				local b = baseOf(i)
				p0, l0, f0 = at(b, 0.8, -1.2, 11), at(b, -0.4, 0.5, 0), 40
				blend = sg.Dur * 0.5
			elseif sameTeam and prev.Kind == "Solo" then
				p0, l0, f0 = mediumShot(prev.Index, 1) -- slide along the line from the last operative
			else
				local b = baseOf(i)
				p0, l0, f0 = at(b, -1.15 + 2.6, 0.85, 8.2), at(b, -1.15 + 2.6, 0.8, 0), 37
			end
			local w = smooth((t - sg.Start) / blend)
			return p0:Lerp(p1, w), l0:Lerp(l1, w), lerp(f0, f1, w), 3.5
		end
		-- squad: pull back from the last operative to the whole line
		local p1, l1, f1 = wideShot(sg.Team, u)
		local last = nil
		for k = n - 1, 1, -1 do
			if segs[k].Kind == "Solo" and segs[k].Team == sg.Team then
				last = segs[k].Index
				break
			end
		end
		if last then
			local p0, l0, f0 = mediumShot(last, 1)
			local w = smooth((t - sg.Start) / math.min(1.1, sg.Dur * 0.5))
			return p0:Lerp(p1, w), l0:Lerp(l1, w), lerp(f0, f1, w), lerp(3.5, 9, w)
		end
		return p1, l1, f1, 9
	end

	local lastSeg, lastCore, ended = 0, 0, false
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value + 10, function()
		local t = clock()
		local sg, sgIndex = segmentAt(math.max(t, 0))
		local u = clamp01((t - sg.Start) / sg.Dur)

		-- nothing else on screen
		for _, g in playerGui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
				g.Enabled = false
				if g.Name ~= "VantageMainMenu" then
					S.Guis[g] = true
				end
			end
		end
		local holo = Workspace:FindFirstChild("VantageVisorHolo")
		if holo then
			for _, d in holo:GetDescendants() do
				if d:IsA("SurfaceGui") and d.Enabled then
					d.Enabled = false
					S.Holo[d] = true
				end
			end
		end
		for _, m in camera:GetChildren() do
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					if S.LTM[d] == nil then
						S.LTM[d] = d.LocalTransparencyModifier
					end
					d.LocalTransparencyModifier = 1
				end
			end
		end
		local ch = player.Character
		local mine = nil
		for _, r in S.Rigs do
			if r.Model == ch then
				mine = r
			end
		end
		if ch and not (mine and mine.Hidden) then
			for _, d in ch:GetDescendants() do
				if d:IsA("BasePart") and d.LocalTransparencyModifier ~= 0 then
					if S.LTM[d] == nil then
						S.LTM[d] = d.LocalTransparencyModifier
					end
					d.LocalTransparencyModifier = 0
				end
			end
		end
		if os.clock() - lastCore > 0.4 then
			lastCore = os.clock()
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false)
		end

		-- camera
		local pos, look, fov, focus = shotAt(t)
		pos = clearView(look, pos)
		local rig = if sg.Kind == "Solo" then rigFor(sg.Index) else nil
		local shake = 0
		local cf = CFrame.lookAt(pos, look)
			* ang(math.sin(os.clock() * 0.9) * 0.1 + (math.random() - 0.5) * shake, math.sin(os.clock() * 0.7) * 0.1 + (math.random() - 0.5) * shake, 0)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cf
		camera.FieldOfView = fov
		dof.FocusDistance = (look - pos).Magnitude
		dof.InFocusRadius = focus

		-- lights: warm key from the camera side, team-coloured rim from behind
		local subject = if rig then rig.Root.Position + V(0, 1, 0) else look
		local away = subject - pos
		away = if away.Magnitude > 0.1 then away.Unit else V(0, 0, -1)
		keyPart.Position = subject - away * 5 - cf.RightVector * 3 + V(0, 2, 0)
		rimPart.Position = subject + away * 3.2 + cf.RightVector * 2.2 + V(0, 1.8, 0)
		rimLight.Color = teamColor(sg.Team)
		keyLight.Brightness = if sg.Kind == "Solo" then 0.9 else 0.5
		rimLight.Brightness = if sg.Kind == "Solo" then 2.6 else 1.2
		rimLight.Range = if sg.Kind == "Solo" then 12 else 30

		-- thruster flames / wrist blink of the operative on screen
		local fx = {}
		local thrust = fx.Thrust or 0
		for i, f in flames do
			if rig and rig.Pack and thrust > 0.01 then
				local sx = if i == 1 then -1 else 1
				local len = (0.5 + 1.3 * thrust) * (0.9 + 0.2 * math.sin(os.clock() * 60 + i))
				f.Size = V(0.22 + 0.12 * thrust, len, 0.22 + 0.12 * thrust)
				f.CFrame = rig.Pack.CFrame * CFrame.new(sx * 0.2, -rig.Pack.Size.Y / 2 - len / 2 + 0.1, 0.05)
				f.Transparency = 0.15 + 0.85 * (1 - thrust)
			else
				f.Transparency = 1
			end
		end
		local wrist = fx.Wrist or 0
		if rig and rig.LeftArm and wrist > 0.01 then
			blink.CFrame = rig.LeftArm.CFrame * CFrame.new(-0.02, -0.05, -0.36)
			blink.Transparency = 1 - wrist
		else
			blink.Transparency = 1
		end
		fxLight.Brightness = math.max(thrust * 2.6, wrist * 1.4)
		fxLight.Color = if thrust > 0.01 then Color3.fromRGB(170, 235, 255) else GREEN
		if rig then
			fxPart.Position = if thrust > 0.01 and rig.Pack then (rig.Pack.CFrame * CFrame.new(0, -1.2, 0.3)).Position else rig.Root.Position - away * 1.2
		end

		-- black: the phase opens from it and closes to it; the one cut (between teams) dips through it
		local dark = math.max(1 - clamp01(t / 0.5), clamp01((t - (total - 0.3)) / 0.3))
		for n = 2, #segs do
			if segs[n].Team ~= segs[n - 1].Team then
				dark = math.max(dark, clamp01(1.25 - math.abs(t - segs[n].Start) / DIP))
			end
		end
		cover.BackgroundTransparency = 1 - dark

		-- nameplate rides beside the operative
		if sg.Kind == "Solo" then
			local b = baseOf(sg.Index)
			local sp = camera:WorldToViewportPoint(at(b, -1.75, 0.15, 0.4))
			plate.Position = O(sp.X, sp.Y)
		end
		if sgIndex ~= lastSeg and t >= 0 then
			lastSeg = sgIndex
			fit()
			local color = teamColor(sg.Team)
			if sg.Kind == "Solo" then
				local e = order[sg.Index]
				local nth = 0
				for i, o in order do
					if o.T == e.T and i <= sg.Index then
						nth += 1
					end
				end
				local w = WeaponConfig.Weapons[e.W or ""]
				local skin = nil
				if e.S and e.W then
					local okS, sk = pcall(Skins.Get, e.W, e.S)
					skin = if okS and type(sk) == "table" then sk.Name else nil
				end
				local kit = SUIT_NAME
				if w then
					kit ..= "  //  " .. string.upper(tostring(w.DisplayName or e.W))
					if skin then
						kit ..= "  //  " .. string.upper(skin)
					end
				end
				local wait = if teamSize[sg.Team] == 1 then sg.Dur * 0.4 else math.min(0.45, sg.Dur * 0.25)
				plate.GroupTransparency = 1
				task.delay(wait, function()
					if lastSeg ~= sgIndex or not plate.Parent then
						return
					end
					pBar.BackgroundColor3 = color
					pNum.Text = string.format("%02d", nth)
					pNum.TextColor3 = color
					pName.Text = string.upper(e.N or "OPERATIVE")
					pKit.Text = kit
					Kit.tween(plate, 0.22, { GroupTransparency = 0 })
					cue("rbxasset://sounds/electronicpingshort.wav", 0.16, 0.8 + 0.06 * nth)
				end)
				cue("rbxassetid://1837830050", 0.18, 1.5)
			else
				Kit.tween(plate, 0.2, { GroupTransparency = 1 })
				local mark = marks[sg.Team]
				if mark then
					task.delay(math.min(0.8, sg.Dur * 0.35), function()
						if mark.Parent then
							Kit.tween(mark, 0.45, { GroupTransparency = 0 })
							cue("rbxassetid://9125484526", 0.4, 1.1)
						end
					end)
				end
			end
		end
		if t > total - 0.35 and not ended then
			ended = true
			Kit.tween(plate, 0.25, { GroupTransparency = 1 })
		end
	end)

	-- run until the timeline or the phase ends -----------------------------------------------------
	local function cleanup()
		pcall(function()
			RunService:UnbindFromRenderStep(BIND)
		end)
		for _, c in S.Conns do
			c:Disconnect()
		end
		for _, rig in S.Rigs do
			pcall(resetRig, rig)
		end
		ThirdPersonRig.Suspended = false
		pcall(function()
			ContextActionService:UnbindAction(SINK)
		end)
		if ctx and ctx.Input then
			ctx.Input:SetBlocked(false)
		end
		if S.Hum and S.Hum.Parent then
			S.Hum.AutoRotate = S.AutoRotate
		end
		for d, v in S.LTM do
			if d.Parent then
				d.LocalTransparencyModifier = v
			end
		end
		for g in S.Guis do
			if g.Parent then
				g.Enabled = true
			end
		end
		for d in S.Holo do
			if d.Parent then
				d.Enabled = true
			end
		end
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, player:GetAttribute("MatchStatus") == "Match")
		if S.Chat then
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, true)
		end
		grade:Destroy()
		dof:Destroy()
		-- hand the camera back to the game's own first-person camera, looking the way the
		-- operative faces (out at the map), not wherever the last shot pointed
		local head = player.Character and player.Character:FindFirstChild("Head")
		for _, e in order do
			if e.U == player.UserId and head and head:IsA("BasePart") then
				local _, d = teamFrame(e.T)
				camera.CFrame = CFrame.lookAt(head.Position, head.Position + d)
			end
		end
		camera.FieldOfView = 80
		camera.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		S.Folder:Destroy()
	end

	local ok, err = pcall(function()
		while true do
			if clock() >= total then
				break
			end
			-- (a Studio hold keeps the shot up after the server has moved on, for screenshots)
			if not held() and (attr("Phase") ~= "Intro" or player:GetAttribute("MatchStatus") ~= "Match") then
				break
			end
			task.wait()
		end
	end)
	cover.BackgroundTransparency = 0
	cleanup()
	if not ok then
		warn("[VANTAGE] OperativeIntro:", err)
	end
	-- back in first person: lift the black
	task.wait(0.1)
	plate.Visible, barTop.Visible, barBot.Visible = false, false, false
	Kit.tween(cover, I.Tail, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	task.wait(I.Tail + 0.05)
	gui:Destroy()
end

local function run()
	local raw = attr("Intro")
	local ok, plan = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not (ok and type(plan) == "table" and type(plan.Order) == "table" and #plan.Order > 0 and type(plan.Start) == "number") then
		return
	end
	local okP, err = pcall(play, plan)
	if not okP then
		warn("[VANTAGE] OperativeIntro failed:", err)
		-- last-resort restore, in case play() died before its own cleanup
		pcall(function()
			RunService:UnbindFromRenderStep(BIND)
		end)
		pcall(function()
			ContextActionService:UnbindAction(SINK)
		end)
		ThirdPersonRig.Suspended = false
		if ctx and ctx.Input then
			ctx.Input:SetBlocked(false)
		end
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.AutoRotate = true
		end
		for _, name in { "VantageIntroGrade", "VantageIntroFocus" } do
			local e = Lighting:FindFirstChild(name)
			if e then
				e:Destroy()
			end
		end
		local pg = player:FindFirstChild("PlayerGui")
		local g = pg and pg:FindFirstChild("VantageOperativeIntro")
		if g then
			g:Destroy()
		end
		local f = Workspace:FindFirstChild("VantageIntroFX")
		if f then
			f:Destroy()
		end
	end
end

-- c = { Input = WeaponInput, Hud = Hud, Effects = WeaponEffects } (all optional)
function OperativeIntro.Start(c)
	ctx = c
	local lastPlan = nil
	RunService.Heartbeat:Connect(function()
		if running then
			return
		end
		if attr("Phase") ~= "Intro" or player:GetAttribute("MatchStatus") ~= "Match" then
			return
		end
		local raw = attr("Intro")
		if type(raw) ~= "string" or raw == "" or raw == lastPlan then
			return -- each plan (it carries its own Id and Start) plays once
		end
		lastPlan = raw
		running = true
		task.spawn(function()
			run()
			running = false
		end)
	end)
end

function OperativeIntro.IsRunning(): boolean
	return running
end

return OperativeIntro
