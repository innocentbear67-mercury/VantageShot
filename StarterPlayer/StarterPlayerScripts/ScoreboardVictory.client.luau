--[[
	DISABLED 2026-11-18: replaced by VantageMatchResults (directed results sequence with MVP).
	Re-enable this script only if VantageMatchResults is disabled.

	VANTAGE — ScoreboardVictory (StarterPlayer.StarterPlayerScripts.ScoreboardVictory)
	The end-of-match "champion shot": when Match.Phase becomes "Ended", a poster-style screen
	takes over until the lobby returns.
	  * the winning squad's real operatives (local copies of their characters) stand in a lit
	    viewport, the top scorer front and centre playing one of the game's mocap clips;
	  * a huge VICTORY / DEFEAT / DRAW sits BEHIND them (poster layering);
	  * the hero's earned title, name and headline stat; the final score; your own result;
	    a VANTAGESHOT watermark so every screenshot carries the brand.
	Self-contained: reads Match attributes, MatchStats_* player attributes and (read-only) the
	OperativeIntro clip modules. Changes nothing outside its own ScreenGui "ScoreboardVictoryGui";
	the real characters are never touched (only copies are posed).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Match = Vantage:WaitForChild("Match")

-- ─── look ──────────────────────────────────────────────────────────────────────────────
local C = Color3.fromRGB
local LIME = C(182, 255, 0) -- VantageShot lime (LimeKit)
local WHITE = C(240, 244, 236)
local BLUE = C(77, 166, 255)
local RED = C(255, 86, 72)
local INK = C(8, 10, 12)
local function fam(n, w)
	return Font.new("rbxasset://fonts/families/" .. n .. ".json", w or Enum.FontWeight.Regular)
end
local F = {
	Display = fam("Oswald", Enum.FontWeight.Bold),
	Head = fam("Oswald", Enum.FontWeight.SemiBold),
	Label = fam("TitilliumWeb", Enum.FontWeight.Bold),
	Body = fam("TitilliumWeb", Enum.FontWeight.SemiBold),
}
local DISPLAY_ORDER = 50 -- above the combat HUD / visor / MatchHud, below loader + intro screens
local HIDE_BEFORE = 0.15 -- finish fading this long before Ended runs out
local OUT_TIME = 0.35

local O = UDim2.fromOffset
local V2 = Vector2.new
local V3 = Vector3.new
local AX = Enum.TextXAlignment
local NS, KP = NumberSequence.new, NumberSequenceKeypoint.new

local function new(class: string, props, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local function tween(i: Instance, t: number, props, style, dir, delay)
	local tw = TweenService:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end
local function text(parent, props): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		FontFace = F.Body,
		TextSize = 18,
		TextXAlignment = AX.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end
local function num(v: any): number
	return if type(v) == "number" then v else 0
end
local function teamColor(t: string?): Color3
	return if t == "Blue" then BLUE elseif t == "Red" then RED else WHITE
end
local function stats(p: Player)
	return {
		K = num(p:GetAttribute("MatchStats_Kills")),
		D = num(p:GetAttribute("MatchStats_Deaths")),
		HS = num(p:GetAttribute("MatchStats_Headshots")),
		Score = num(p:GetAttribute("MatchStats_Score")),
	}
end
local function byScore(a: Player, b: Player): boolean
	local sa, sb = stats(a), stats(b)
	if sa.Score ~= sb.Score then
		return sa.Score > sb.Score
	elseif sa.K ~= sb.K then
		return sa.K > sb.K
	end
	return sa.D < sb.D
end
local function matchPlayers(): { Player }
	local id = Match:GetAttribute("MatchId")
	local out = {}
	for _, p in Players:GetPlayers() do
		if id and id ~= 0 and p:GetAttribute("MatchId") == id and p.Team and (p.Team.Name == "Blue" or p.Team.Name == "Red") then
			table.insert(out, p)
		end
	end
	table.sort(out, byScore)
	return out
end

-- earned title from real numbers (first match wins)
local function titleFor(p: Player, all: { Player }): string
	local s = stats(p)
	if s.K >= 3 and s.HS / s.K >= 0.5 then
		return "SHARPSHOOTER"
	end
	if s.K >= 3 and s.D == 0 then
		return "UNTOUCHABLE"
	end
	local mostKills = true
	for _, o in all do
		if o ~= p and stats(o).K >= s.K then
			mostKills = false
		end
	end
	if mostKills and s.K > 0 then
		return "TOP FRAGGER"
	end
	return "SQUAD LEADER"
end

-- ─── mocap clips (decoder mirrors OperativeIntro's text format; the modules are only read) ─
local JOINT_ORDER = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
local JOINT_PART = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}
local DIGIT = {}
do
	local n = 0
	for c = 35, 126 do
		if c ~= 92 and c ~= 93 then
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
			local function v(i: number, range: number): number
				return ((DIGIT[string.byte(line, i)] * 90 + DIGIT[string.byte(line, i + 1)]) / 8099 * 2 - 1) * range
			end
			local f = { Pos = V3(v(1, 4), v(3, 4), v(5, 4)), Rot = table.create(#JOINT_ORDER) }
			for j = 1, #JOINT_ORDER do
				local i = 7 + (j - 1) * 6
				local x, y, z = v(i, 1), v(i + 2, 1), v(i + 4, 1)
				f.Rot[j] = CFrame.new(0, 0, 0, x, y, z, math.sqrt(math.max(0, 1 - x * x - y * y - z * z)))
			end
			table.insert(frames, f)
		elseif #frames > 0 then
			table.insert(frames, frames[#frames])
		end
	end
	return if #frames >= 2 then { Dur = def.Dur, Frames = frames } else nil
end
local CLIPS = {}
task.spawn(function()
	local wc = player:WaitForChild("PlayerScripts"):WaitForChild("VantageWeaponClient", 30)
	local intro = wc and wc:WaitForChild("OperativeIntro", 30)
	local folder = intro and intro:WaitForChild("Clips", 30)
	if not folder then
		return
	end
	for _, mod in folder:GetChildren() do
		if mod:IsA("ModuleScript") then
			local ok, def = pcall(require, mod)
			local clip = ok and type(def) == "table" and type(def.Data) == "string" and decodeClip(def)
			if clip then
				CLIPS[mod.Name] = clip
			end
		end
	end
end)
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
local function ang(x, y, z)
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end
-- a confident stance (degrees) used under / after the clip; mirrored for flankers on the left
local STANCE = {
	Waist = { -3, 0, 0 }, Neck = { 4, 0, 0 },
	RightShoulder = { 0, 0, 8 }, LeftShoulder = { 0, 0, -8 }, RightElbow = { 14, 0, 0 }, LeftElbow = { 14, 0, 0 },
	RightHip = { 2, -8, 6 }, LeftHip = { -2, 10, -7 }, RightKnee = { -4, 0, 0 }, LeftKnee = { -6, 0, 0 },
	RightAnkle = { 2, 0, -6 }, LeftAnkle = { 4, 0, 6 },
}
local SLUNG = CFrame.new(0.42, 0.25, 1.02) * ang(0, 0, -16) * ang(78, 0, 0) -- rifle on the back

-- ─── operative copies ──────────────────────────────────────────────────────────────────
local STRIP = { "Script", "LocalScript", "ModuleScript", "Sound", "ParticleEmitter", "Beam", "Trail", "BillboardGui", "SurfaceGui", "ForceField", "Fire", "Smoke", "Sparkles", "Highlight", "ProximityPrompt", "ClickDetector" }
local function copyCharacter(p: Player): Model?
	local ch = p.Character
	if not (ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChild("UpperTorso")) then
		return nil
	end
	local was = ch.Archivable
	ch.Archivable = true -- local only, restored right after: needed to copy the model
	local ok, copy = pcall(function()
		return ch:Clone()
	end)
	ch.Archivable = was
	if not ok or not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		for _, cls in STRIP do
			if d:IsA(cls) then
				d:Destroy()
				break
			end
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			end
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = copy:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			animator:Destroy()
		end
	end
	copy.HumanoidRootPart.Anchored = true
	return copy
end

local function rigOf(model: Model, seed: number, mirror: boolean)
	local rig = { Model = model, J = {}, Seed = seed, Mirror = mirror }
	for name, partName in JOINT_PART do
		local part = model:FindFirstChild(partName)
		local j = part and part:FindFirstChild(name)
		if j and j:IsA("Motor6D") then
			rig.J[name] = j
		end
	end
	local world = model:FindFirstChild("VantageWorldWeapon")
	local body = world and world:IsA("Model") and world.PrimaryPart
	local motor = body and body:FindFirstChild("VantageGunMotor")
	if motor and motor:IsA("Motor6D") then
		rig.Gun = motor
	end
	return rig
end

-- stance blended toward the clip pose by w, plus a slow breath
local function poseRig(rig, clip, t: number, w: number)
	local s = if rig.Mirror then -1 else 1
	local breath = math.sin(t * 1.8 + rig.Seed)
	local T = {}
	for name in rig.J do
		local d = STANCE[name]
		T[name] = if d then ang(d[1], d[2] * s, d[3] * s) else CFrame.identity
	end
	T.Waist = (T.Waist or CFrame.identity) * ang(-1.2 * breath, 0, 0)
	T.Neck = (T.Neck or CFrame.identity) * ang(0.6 * breath, 0, 0)
	if clip and w > 0 then
		local pos, rot = sampleClip(clip, t)
		for j, name in JOINT_ORDER do
			if T[name] then
				local c = if name == "Root" then CFrame.new(pos.X * 0.25, math.clamp(pos.Y, -0.6, 0.2), pos.Z * 0.25) * rot[j] else rot[j]
				T[name] = T[name]:Lerp(c, w)
			end
		end
	end
	for name, j in rig.J do
		j.Transform = T[name]
	end
	if rig.Gun then
		rig.Gun.Transform = rig.Gun.C0:Inverse() * SLUNG * rig.Gun.C1
	end
end

-- ─── screen ────────────────────────────────────────────────────────────────────────────
local gui: ScreenGui? = nil
local token = 0
local stepConn: RBXScriptConnection? = nil

local function teardown()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
end

-- Studio only: player attribute ScoreboardVictoryPreview = "Blue" / "Red" / "Draw" opens the
-- screen on demand (during a match, so characters exist) and holds it until cleared
local function previewing(): boolean
	return RunService:IsStudio() and player:GetAttribute("ScoreboardVictoryPreview") ~= nil
end

local function hide(instant: boolean?)
	if previewing() then
		return
	end
	token += 1
	if not gui then
		return
	end
	if instant then
		teardown()
		return
	end
	-- out: fade to black over everything, then hand over to the lobby
	local g = gui
	local curtain = new("Frame", { Name = "Curtain", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20 }, g)
	tween(curtain, OUT_TIME, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(OUT_TIME + 0.02, function()
		if gui == g then
			teardown()
		end
	end)
end

local function build(myToken: number, forcedWinner: string?)
	teardown()
	local all = matchPlayers()
	if forcedWinner and #all == 0 then
		all = { player }
	end
	local winner = forcedWinner or tostring(Match:GetAttribute("Winner") or "")
	local reason = tostring(Match:GetAttribute("EndReason") or "")
	local myTeam = player.Team and player.Team.Name
	local isDraw = winner ~= "Blue" and winner ~= "Red"
	-- whose moment: the winning squad (on a draw, the top scorer's squad)
	local squadTeam = if isDraw then (all[1] and all[1].Team and all[1].Team.Name or "Blue") else winner
	local squad = {}
	for _, p in all do
		if p.Team and p.Team.Name == squadTeam then
			table.insert(squad, p)
		end
	end
	local hero = squad[1]
	local tc = teamColor(squadTeam)

	local word, wordColor
	if isDraw then
		word, wordColor = "DRAW", WHITE
	elseif myTeam == winner then
		word, wordColor = "VICTORY", LIME
	elseif myTeam == "Blue" or myTeam == "Red" then
		word, wordColor = "DEFEAT", RED
	else
		word, wordColor = string.upper(winner) .. " WINS", tc
	end

	local g = new("ScreenGui", { Name = "ScoreboardVictoryGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = DISPLAY_ORDER, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	gui = g
	-- full-screen layers are plain Frames (full-screen CanvasGroups blow the texture budget);
	-- only the small info blocks are CanvasGroups
	local function layer(name: string, z: number)
		return new("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z }, g)
	end

	-- 1 backdrop: near-black, a team-coloured light pool behind the squad, floor fade
	local back = layer("Backdrop", 1)
	back.BackgroundColor3 = INK
	back.BackgroundTransparency = 0
	local pool = new("Frame", { Name = "Pool", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(1.3, 1.1), BackgroundColor3 = tc, BackgroundTransparency = 0, BorderSizePixel = 0 }, back)
	new("UIGradient", { Transparency = NS({ KP(0, 1), KP(0.3, 0.86), KP(0.5, 0.62), KP(0.7, 0.86), KP(1, 1) }) }, pool)
	local poolV = new("Frame", { Name = "PoolV", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0, BorderSizePixel = 0 }, back)
	new("UIGradient", { Rotation = 90, Transparency = NS({ KP(0, 0.15), KP(0.45, 1), KP(0.78, 1), KP(1, 0.05) }) }, poolV)
	-- floor: a soft contact shadow under the squad so they stand on something
	for i, sz in { { 0.42, 0.06, 0.55 }, { 0.2, 0.035, 0.35 } } do
		local sh = new("Frame", { Name = "FloorShadow" .. i, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.875), Size = UDim2.fromScale(sz[1], sz[2]), BackgroundColor3 = C(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0 }, back)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, sh)
		-- feathered: dark in the middle, gone at the ends
		new("UIGradient", { Transparency = NS({ KP(0, 1), KP(0.5, sz[3]), KP(1, 1) }) }, sh)
	end
	-- slow light sweep (the only motion during the hold)
	local sweep = new("Frame", { Name = "Sweep", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.94, BorderSizePixel = 0 }, back)
	local sweepGrad = new("UIGradient", { Rotation = 20, Offset = V2(-1, 0), Transparency = NS({ KP(0, 1), KP(0.4, 1), KP(0.5, 0), KP(0.6, 1), KP(1, 1) }) }, sweep)

	-- 2 the word, behind the operatives
	local wordLayer = layer("Word", 2)
	-- Roblox caps TextSize at 100: draw at 100 and scale the holder up to ~90 % of the width
	local wordOuter = new("Frame", { Name = "Holder", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.37), Size = O(600, 120), BackgroundTransparency = 1 }, wordLayer)
	local wordFit = new("UIScale", { Scale = 1 }, wordOuter)
	local wordInner = new("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, wordOuter)
	local wordScale = new("UIScale", { Scale = 1.3 }, wordInner)
	local wordLabel = text(wordInner, { Name = "Word", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(600, 120), Text = word, FontFace = F.Display, TextSize = 100, TextColor3 = wordColor, TextTransparency = 1, TextXAlignment = AX.Center })

	-- 3 the squad (3D)
	local stage = layer("Squad", 3)
	local vp = new("ViewportFrame", { Name = "Viewport", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ImageTransparency = 1, Ambient = C(70, 76, 88), LightColor = C(255, 248, 236), LightDirection = V3(-0.5, -0.45, -0.75) }, stage)
	local worldModel = new("WorldModel", {}, vp)
	local cam = new("Camera", { FieldOfView = 26 }, vp)
	vp.CurrentCamera = cam
	-- hero ~64 % of the screen height, feet low (under the floor fade), a slightly low, heroic angle
	cam.CFrame = CFrame.lookAt(V3(0, 2.3, 17.5), V3(0, 3.3, 0))
	-- V formation: hero front and centre, the rest flanking further back
	local SPOTS = { { 0, 0, 0 }, { 3.4, -2.4, -14 }, { -3.4, -2.4, 14 }, { 6.6, -4.8, -22 }, { -6.6, -4.8, 22 } }
	local rigs = {}
	local clipNames = { "YellingOut", "Salute", "Charge", "Punching", "BatterOnDeck" }
	for i, p in squad do
		if i > #SPOTS then
			break
		end
		local copy = copyCharacter(p)
		if copy then
			local spot = SPOTS[i]
			copy.Parent = worldModel
			copy:PivotTo(CFrame.new(spot[1], 3, spot[2]) * ang(0, 180 + spot[3], 0))
			-- stand it on y = 0, centred on its spot (suits are not default-sized avatars)
			local bcf, bsize = copy:GetBoundingBox()
			copy:PivotTo(copy:GetPivot() + V3(spot[1] - bcf.Position.X, -(bcf.Position.Y - bsize.Y / 2), spot[2] - bcf.Position.Z))
			-- the suit's visor lit in VantageShot lime
			for _, d in copy:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Visor" then
					d.Color = LIME
					d.Material = Enum.Material.Neon
				end
			end
			local rig = rigOf(copy, i, spot[1] < 0)
			rig.Clip = clipNames[i]
			table.insert(rigs, rig)
		end
	end

	-- 4 foreground: fade over the feet so the squad stands in light, not on a cut
	local fore = layer("Foreground", 4)
	fore.Active = false
	local floorFade = new("Frame", { Name = "FloorFade", AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.34), BackgroundColor3 = INK, BorderSizePixel = 0 }, fore)
	new("UIGradient", { Rotation = 90, Transparency = NS({ KP(0, 1), KP(0.55, 0.25), KP(1, 0) }) }, floorFade)

	-- 5 information: everything in one 1920x1080 frame, scaled to fit
	local info = layer("Info", 5)
	local stageFrame = new("Frame", { Name = "Frame", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(1920, 1080), BackgroundTransparency = 1 }, info)
	local fit = new("UIScale", {}, stageFrame)
	-- the word's own width at TextSize 100, measured once without any scaling
	local wordW = 360
	pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = word
		params.Font = F.Display
		params.Size = 100
		params.Width = 100000
		wordW = game:GetService("TextService"):GetTextBoundsAsync(params).X
	end)
	wordLabel.Size = O(wordW + 20, 120)
	wordOuter.Size = O(wordW + 20, 120)
	local function rescale()
		local c = Workspace.CurrentCamera
		if c then
			local v = c.ViewportSize
			fit.Scale = math.min(v.X / 1920, v.Y / 1080)
			wordFit.Scale = math.min(v.X * 0.9 / (wordW + 20), v.Y * 0.5 / 100)
		end
	end
	rescale()

	-- hero plate (lower-left)
	local plate = new("CanvasGroup", { Name = "HeroPlate", Position = O(110, 690), Size = O(720, 300), BackgroundTransparency = 1, GroupTransparency = 1 }, stageFrame)
	if hero then
		local hs = stats(hero)
		local isMvp = all[1] == hero
		local badge = new("Frame", { Name = "Badge", Position = O(0, 0), AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 34), BackgroundColor3 = if isMvp then LIME else WHITE, BorderSizePixel = 0 }, plate)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, badge)
		text(badge, { Name = "Text", AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 34), Text = if isMvp then "MATCH MVP" else "SQUAD MVP", FontFace = F.Label, TextSize = 18, TextColor3 = INK })
		text(plate, { Name = "Title", Position = O(0, 44), Size = O(720, 30), Text = titleFor(hero, all), FontFace = F.Head, TextSize = 28, TextColor3 = tc })
		local nameL = text(plate, { Name = "Name", Position = O(-3, 72), Size = O(720, 110), Text = string.upper(hero.DisplayName), FontFace = F.Display, TextScaled = true, TextTruncate = Enum.TextTruncate.AtEnd })
		new("UITextSizeConstraint", { MaxTextSize = 100 }, nameL)
		local statRow = new("Frame", { Name = "Stats", Position = O(0, 196), Size = O(720, 80), BackgroundTransparency = 1 }, plate)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 40), SortOrder = Enum.SortOrder.LayoutOrder }, statRow)
		for i, s in { { tostring(hs.K), "ELIMS" }, { tostring(hs.HS), "HEADSHOTS" }, { tostring(hs.Score), "SCORE" } } do
			local cell = new("Frame", { Name = s[2], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 80), BackgroundTransparency = 1 }, statRow)
			text(cell, { Name = "Value", AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 54), Text = s[1], FontFace = F.Display, TextSize = 56 })
			text(cell, { Name = "Label", Position = O(2, 54), AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 22), Text = s[2], FontFace = F.Label, TextSize = 16, TextTransparency = 0.4 })
		end
	end

	-- final score (lower-right)
	local score = new("CanvasGroup", { Name = "FinalScore", AnchorPoint = V2(1, 0), Position = O(1920 - 110, 770), Size = O(560, 140), BackgroundTransparency = 1, GroupTransparency = 1 }, stageFrame)
	local bs, rs = num(Match:GetAttribute("BlueScore")), num(Match:GetAttribute("RedScore"))
	local row = new("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, score)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, part in { { "BLUE", tostring(bs), BLUE, winner == "Red" }, { "–", nil, nil, false }, { "RED", tostring(rs), RED, winner == "Blue" } } do
		if part[2] == nil then
			text(row, { Name = "Dash", LayoutOrder = i, Size = O(30, 96), Text = "–", FontFace = F.Head, TextSize = 48, TextTransparency = 0.6, TextXAlignment = AX.Center })
		else
			local cell = new("Frame", { Name = part[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 126), BackgroundTransparency = 1 }, row)
			text(cell, { Name = "Team", Size = O(120, 24), Text = part[1], FontFace = F.Label, TextSize = 18, TextColor3 = part[3] })
			text(cell, { Name = "Value", Position = O(0, 24), AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 100), Text = part[2], FontFace = F.Display, TextSize = 100, TextTransparency = if part[4] then 0.55 else 0 })
		end
	end
	local why = if reason == "SCORE" then "SCORE LIMIT" elseif reason == "TIME" then "TIME" elseif reason == "FORFEIT" then "FORFEIT" else ""
	text(score, { Name = "Why", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = O(300, 20), Text = if why ~= "" then "FINAL  ·  " .. why else "FINAL", FontFace = F.Label, TextSize = 15, TextTransparency = 0.45, TextXAlignment = AX.Right })

	-- your result (top-right, small) — only if you were in the match
	local mine = new("CanvasGroup", { Name = "YourResult", AnchorPoint = V2(1, 0), Position = O(1920 - 110, 92), Size = O(420, 90), BackgroundTransparency = 1, GroupTransparency = 1 }, stageFrame)
	local myRank = table.find(all, player)
	if myRank then
		local s = stats(player)
		text(mine, { Name = "Label", Size = O(420, 20), Text = string.format("YOU  ·  #%d OF %d", myRank, #all), FontFace = F.Label, TextSize = 16, TextTransparency = 0.35, TextXAlignment = AX.Right })
		text(mine, { Name = "Line", Position = O(0, 22), Size = O(420, 44), Text = string.format("%d / %d / %d", s.K, s.D, s.Score), FontFace = F.Head, TextSize = 40, TextXAlignment = AX.Right })
		text(mine, { Name = "Key", Position = O(0, 64), Size = O(420, 18), Text = "ELIMS / DEATHS / SCORE", FontFace = F.Label, TextSize = 13, TextTransparency = 0.55, TextXAlignment = AX.Right })
	end

	-- watermark (top-left): brand, mode, map, date
	local mark = new("CanvasGroup", { Name = "Watermark", Position = O(110, 92), Size = O(700, 70), BackgroundTransparency = 1, GroupTransparency = 1 }, stageFrame)
	new("Frame", { Name = "Tick", Position = O(0, 6), Size = O(4, 30), BackgroundColor3 = LIME, BorderSizePixel = 0 }, mark)
	text(mark, { Name = "Brand", Position = O(16, 0), Size = O(600, 42), Text = "VANTAGESHOT", FontFace = F.Display, TextSize = 40 })
	local modeNames = { TDM = "TEAM DEATHMATCH" }
	local mode = tostring(Match:GetAttribute("Mode") or "")
	local map = string.upper(tostring(Match:GetAttribute("MapName") or ""))
	text(mark, { Name = "Meta", Position = O(18, 42), Size = O(680, 20), Text = string.format("%s  ·  %s  ·  %s", modeNames[mode] or mode, map, os.date("%d %b %Y"):upper()), FontFace = F.Label, TextSize = 15, TextTransparency = 0.45 })

	-- flash (top)
	local flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 10 }, g)

	-- ── timeline ──
	tween(flash, 0.55, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	tween(wordLabel, 0.35, { TextTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.05)
	tween(wordScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.05)
	tween(vp, 0.7, { ImageTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.3)
	local plateHome = plate.Position
	plate.Position = plateHome + O(-40, 0)
	tween(plate, 0.6, { GroupTransparency = 0, Position = plateHome }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 1.0)
	local scoreHome = score.Position
	score.Position = scoreHome + O(0, 24)
	tween(score, 0.6, { GroupTransparency = 0, Position = scoreHome }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 1.25)
	tween(mine, 0.5, { GroupTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1.5)
	tween(mark, 0.5, { GroupTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1.6)
	tween(sweepGrad, 2.4, { Offset = V2(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2.0)

	-- operatives: clip plays once from 0.3 s, then settles into the stance and breathes
	local t0 = os.clock() + 0.3
	stepConn = RunService.RenderStepped:Connect(function()
		if myToken ~= token then
			return
		end
		local t = os.clock() - t0
		for _, rig in rigs do
			local clip = CLIPS[rig.Clip]
			local w = 0
			if clip and t > 0 then
				local into = math.clamp(t / 0.3, 0, 1)
				local out = math.clamp((t - (clip.Dur - 0.6)) / 0.6, 0, 1)
				w = into * (1 - out * 0.65) -- keep a third of the clip's last pose
			end
			poseRig(rig, clip, math.max(0, if clip then math.min(t, clip.Dur) else t), w)
		end
		rescale()
	end)
end

-- ─── flow ──────────────────────────────────────────────────────────────────────────────
local function onEnded()
	token += 1
	local my = token
	if player:GetAttribute("MatchStatus") ~= "Match" then
		return
	end
	local endsAt = num(Match:GetAttribute("PhaseEnds"))
	task.delay(0.15, function()
		if my ~= token or Match:GetAttribute("Phase") ~= "Ended" then
			return
		end
		local ok, err = pcall(build, my)
		if not ok then
			warn("[VANTAGE] ScoreboardVictory:", err)
			teardown()
			return
		end
		local hold = if endsAt > 0 then endsAt - Workspace:GetServerTimeNow() - HIDE_BEFORE - OUT_TIME else 8
		task.delay(math.max(0.5, hold), function()
			if my == token then
				hide()
			end
		end)
	end)
end

local last = Match:GetAttribute("Phase")
Match:GetAttributeChangedSignal("Phase"):Connect(function()
	local ph = Match:GetAttribute("Phase")
	if ph == "Ended" and last ~= "Ended" then
		onEnded()
	elseif ph ~= "Ended" then
		hide(ph == "Idle")
	end
	last = ph
end)
player:GetAttributeChangedSignal("MatchStatus"):Connect(function()
	if player:GetAttribute("MatchStatus") ~= "Match" then
		hide(true)
	end
end)

if RunService:IsStudio() then
	player:GetAttributeChangedSignal("ScoreboardVictoryPreview"):Connect(function()
		local v = player:GetAttribute("ScoreboardVictoryPreview")
		token += 1
		if v == nil then
			teardown()
			return
		end
		local ok, err = pcall(build, token, tostring(v))
		if not ok then
			warn("[VANTAGE] ScoreboardVictory preview:", err)
			teardown()
		end
	end)
end
