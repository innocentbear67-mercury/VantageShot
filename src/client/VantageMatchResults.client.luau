--[[
	VANTAGE — VantageMatchResults (client, 2026-11-18)
	The directed end of a match (Hypershot study: the screen washes into the team colour, a slanted
	VICTORY band sweeps across, rewards land as tilted cards, then the full board).
	  1. END WASH     gameplay freezes (server anchors everyone), HUD out, camera eases back and
	                  up, colour drains into the result tint, deep end hit
	  2. VICTORY / DEFEAT / DRAW band, final score, why it ended (score / time / overtime /
	                  forfeit), victory or defeat sting
	  3. MVP REVEAL   the server-picked MVP of the winning team posed in a lit 3D viewport with
	                  rays + glow; title, avatar, name, stats count up. A separate TOP PERFORMER
	                  card when the best player overall is someone else.
	  4. SCOREBOARD   both teams, every participant (players who left are greyed), K / D / A / K/D /
	                  EXP / REQ / ORD, winner + MVP marked, your row lit; YOUR MATCH REWARDS as
	                  three cards counting up (REQ / ORD / EXP) + level bar
	  5. OUT          PLAY AGAIN (leave + queue the same mode) or LOBBY, or the server's timer;
	                  fade to black, the lobby takes over.
	SPACE / click skips 1-3 straight to the board. Data: Match.Results (JSON, MatchService) only, so
	it always shows what the server decided. Timings: MatchConfig.Results / Sounds.
	Studio: player attribute ResultsPreview = "Win" | "Loss" | "Draw" plays it with sample rows.
	Creates only its own ScreenGui "VantageMatchResults" (+ a local ColorCorrection / Blur on the
	camera, removed again).
]]
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("MatchConfig"))
local Match = Vantage:WaitForChild("Match")
local Request = Vantage:WaitForChild("Remotes"):WaitForChild("MatchRequest") :: RemoteFunction
local R = Config.Results

local ReqIcon, OrdIcon = "", ""
pcall(function()
	ReqIcon = require(Vantage.Requisition.RequisitionConfig).Icon or ""
end)
pcall(function()
	OrdIcon = require(Vantage.Ordnance.OrdnanceConfig).Icon or ""
end)

-- look: HUD v5 / lobby (dark navy, electric blue + red, gold for the MVP)
local C = Color3.fromRGB
local WHITE = C(245, 248, 255)
local DIM = C(150, 162, 196)
local INK = C(5, 8, 18)
local BG = C(7, 11, 24)
local PANEL = C(13, 19, 40)
local ROW = C(20, 29, 58)
local EDGE = C(50, 68, 118)
local BLUE = C(60, 150, 255)
local RED = C(255, 62, 92)
local GOLD = C(255, 200, 64)
local ORANGE = C(255, 168, 46)
local GREEN = C(110, 236, 120)
local DEFEAT = C(160, 26, 40)
local FRED = Font.new("rbxasset://fonts/families/FredokaOne.json")
local BS = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local BSH = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
local BSM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)
local O = UDim2.fromOffset
local V2 = Vector2.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint
local CS, CK = ColorSequence.new, ColorSequenceKeypoint
local MODE_NAMES = { TDM = "TEAM DEATHMATCH", RTDM = "RANKED DEATHMATCH" }

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local function tween(o, t, props, style, dir, delay)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, FontFace = BS, TextColor3 = WHITE, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left }, parent)
	local st = props.Stroke
	props.Stroke = nil
	for k, v in props do
		t[k] = v
	end
	if st and st > 0 then
		new("UIStroke", { Color = INK, Thickness = st, LineJoinMode = Enum.LineJoinMode.Round }, t)
	end
	return t
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end
local function stroke(p, c, th, tr)
	return new("UIStroke", { Color = c or EDGE, Thickness = th or 2, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end
local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end
local function teamColor(t: string?): Color3
	return if t == "Blue" then BLUE elseif t == "Red" then RED else WHITE
end
local function fmt(n: number): string
	local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
	local neg = s:sub(1, 1) == "-"
	if neg then
		s = s:sub(2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if neg then "-" else "") .. out
end
local function kd(k: number, d: number): string
	return string.format("%.2f", if d > 0 then k / d else k)
end
local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end
-- 2026-11-18 audio pass: cue() returns the Sound. Specs with Group = "Music" play in VantageMusic,
-- Loop = true loops, Loop / Hold sounds are faded out with the results (fadeHeld). `live` keeps
-- the handles one stage needs to fade from another (suck-back, sting, crowd).
local TS = game:GetService("TweenService")
local held: { [Sound]: boolean } = {}
local live: { [string]: any } = {}
local function cue(name: string, speedMul: number?, volMul: number?): Sound?
	local spec = Config.Sounds[name]
	if not spec then
		return nil
	end
	local s = new("Sound", { Name = "Results_" .. name, SoundId = spec.Id, Volume = spec.Volume * (volMul or 1), PlaybackSpeed = (spec.Speed or 1) * (speedMul or 1), Looped = spec.Loop == true })
	local g = (if spec.Group == "Music" then SoundService:FindFirstChild("VantageMusic") else nil) or SoundService:FindFirstChild("VantageEffects")
	if g and g:IsA("SoundGroup") then
		s.SoundGroup = g
	end
	s.Parent = SoundService
	s:Play()
	if spec.Loop or spec.Hold then
		held[s] = true
	end
	s.Ended:Once(function()
		held[s] = nil
		s:Destroy()
	end)
	if not spec.Loop then
		task.delay(spec.Life or 20, function() -- safety net if Ended never fires
			held[s] = nil
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	return s
end
local function fadeOut(s: Sound?, t: number)
	if not (s and s.Parent) then
		return
	end
	held[s] = nil
	TS:Create(s, TweenInfo.new(t, Enum.EasingStyle.Quad), { Volume = 0 }):Play()
	task.delay(t + 0.05, function()
		s:Destroy()
	end)
end
local function fadeIn(s: Sound?, t: number)
	if not s then
		return
	end
	local v = s.Volume
	s.Volume = 0
	TS:Create(s, TweenInfo.new(t, Enum.EasingStyle.Sine), { Volume = v }):Play()
end
local function fadeHeld(t: number)
	for s in held do
		fadeOut(s, t)
	end
end
local function countUp(l: TextLabel, n: number, t: number, prefix: string?, decimals: boolean?)
	local nv = new("NumberValue", { Value = 0 })
	nv.Changed:Connect(function(v)
		if l.Parent then
			l.Text = (prefix or "") .. (if decimals then string.format("%.2f", v) else fmt(v))
		end
	end)
	local tw = TweenService:Create(nv, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = n })
	tw.Completed:Connect(function()
		if l.Parent then
			l.Text = (prefix or "") .. (if decimals then string.format("%.2f", n) else fmt(n))
		end
		nv:Destroy()
	end)
	tw:Play()
end

-- avatar headshots (cached; the fetch yields, so it runs in its own thread)
local thumbs = {}
local function headshot(img: ImageLabel, userId: number)
	if thumbs[userId] then
		img.Image = thumbs[userId]
		return
	end
	task.spawn(function()
		if userId <= 0 then
			return
		end
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and url then
			thumbs[userId] = url
			if img.Parent then
				img.Image = url
			end
		end
	end)
end
local function avatar(parent, userId: number, px: number, ring: Color3, props)
	local f = new("Frame", { Size = O(px, px), BackgroundColor3 = C(30, 40, 70), BorderSizePixel = 0 }, parent)
	for k, v in props or {} do
		f[k] = v
	end
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	new("UIStroke", { Color = ring, Thickness = math.max(2, px / 22) }, f)
	local img = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "" }, f)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
	headshot(img, userId)
	return f
end

-- ─── premium kit (2026-11-18 pass 2): one animator, glossy fills, running border light, glows,
-- streaks. Everything animated is registered with animate(owner, fn) and stops when the owner
-- leaves the tree, so nothing leaks after the sequence. ──────────────────────────────────────────────────────────────────────────────────
local ANIM = {}
local function animate(owner: Instance, fn)
	table.insert(ANIM, { O = owner, F = fn, T0 = os.clock() })
end
RunService.RenderStepped:Connect(function()
	if #ANIM == 0 then
		return
	end
	local now = os.clock()
	for i = #ANIM, 1, -1 do
		local a = ANIM[i]
		if not a.O.Parent then
			table.remove(ANIM, i)
		elseif not pcall(a.F, now - a.T0) then
			table.remove(ANIM, i)
		end
	end
end)

-- a bright point of light running round a border
local function borderLight(f: GuiObject, base: Color3, thick: number?, speed: number?)
	local s = new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local hi = lighten(base, 0.75)
	local g = new("UIGradient", { Color = CS({ CK.new(0, base), CK.new(0.4, base), CK.new(0.5, hi), CK.new(0.6, base), CK.new(1, base) }) }, s)
	local sp = speed or 70
	animate(s, function(t)
		g.Rotation = (t * sp) % 360
	end)
	return s
end

-- glossy body: 4-stop vertical gradient, top gloss, bevel line, and (on a CanvasGroup) light streaks
-- that sweep across every Period seconds
local function glossy(f: GuiObject, base: Color3, opts)
	opts = opts or {}
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	new("UIGradient", { Rotation = 90, Color = CS({ CK.new(0, lighten(base, opts.Top or 0.5)), CK.new(0.2, lighten(base, 0.14)), CK.new(0.56, base), CK.new(1, darken(base, opts.Bottom or 0.55)) }) }, f)
	local gl = new("Frame", { Name = "Gloss", Size = UDim2.new(1, 0, 0.47, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = opts.Gloss or 0.8, BorderSizePixel = 0 }, f)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 0), NK.new(1, 1) }) }, gl)
	if opts.Round then
		corner(gl, opts.Round)
	end
	new("Frame", { Name = "Bevel", Position = O(opts.Round or 0, 0), Size = UDim2.new(1, -2 * (opts.Round or 0), 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.4, BorderSizePixel = 0 }, f)
	if opts.Streaks ~= false and f:IsA("CanvasGroup") then
		local period = opts.Period or 3
		for i = 1, 2 do
			local s = new("Frame", { Name = "Streak", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(-0.4, 0.5), Size = UDim2.new(0, (opts.StreakW or 30) * (if i == 1 then 1 else 0.45), 4, 0), Rotation = 24, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = if i == 1 then 0.72 else 0.8, BorderSizePixel = 0 }, f)
			local off = (opts.Phase or 0) + (i - 1) * 0.07
			animate(s, function(t)
				local u = (t / period + off) % 1
				local x = if u < 0.42 then -0.4 + (u / 0.42) * 1.8 else 1.5
				s.Position = UDim2.fromScale(x, 0.5)
			end)
		end
	end
	return f
end

-- soft round glow (stacked discs read as a radial falloff)
local function glow(parent: Instance, x: number, y: number, size: number, color: Color3, strength: number?, z: number?)
	local g = new("Frame", { Name = "Glow", AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(size, size), BackgroundTransparency = 1, ZIndex = z or 1 }, parent)
	local k = strength or 1
	for i = 1, 6 do
		local f = i / 6
		local d = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(f, f), BackgroundColor3 = color, BackgroundTransparency = 1 - 0.09 * k, BorderSizePixel = 0, ZIndex = z or 1 }, g)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
	end
	return g
end

-- full-screen streak field: long thin light lines sliding along a diagonal at mixed speeds
local function streakField(parent: Instance, colors: { Color3 }, count: number, z: number?)
	local f = new("Frame", { Name = "StreakField", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z or 1, ClipsDescendants = true }, parent)
	for i = 1, count do
		local len = math.random(260, 900)
		local th = if math.random() < 0.25 then 4 else 2
		local y = math.random()
		local speed = 0.12 + math.random() * 0.35
		local off = math.random()
		local l = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(len, th), Rotation = -14, BackgroundColor3 = colors[(i % #colors) + 1], BackgroundTransparency = 0.55 + math.random() * 0.35, BorderSizePixel = 0, ZIndex = z or 1 }, f)
		new("UIGradient", { Transparency = NS({ NK.new(0, 1), NK.new(0.75, 0), NK.new(1, 1) }) }, l)
		animate(l, function(t)
			local u = (off + t * speed) % 1
			l.Position = UDim2.new(-0.3 + u * 1.6, 0, y - u * 0.25, 0)
		end)
	end
	return f
end

-- text with a looping shine band (uses the label's one UIGradient) + a soft drop shadow
local function shinyText(lbl: TextLabel, tint: Color3, period: number?)
	local g = new("UIGradient", { Rotation = 18, Color = CS({ CK.new(0, tint), CK.new(0.42, tint), CK.new(0.5, Color3.new(1, 1, 1)), CK.new(0.58, tint), CK.new(1, tint) }), Offset = V2(-1, 0) }, lbl)
	local p = period or 2.4
	animate(g, function(t)
		local u = (t % p) / p
		g.Offset = V2(-1 + u * 2.4, 0)
	end)
	local sh = lbl:Clone()
	for _, c in sh:GetChildren() do
		c:Destroy()
	end
	sh.Name = lbl.Name .. "Shadow"
	sh.TextColor3 = Color3.new(0, 0, 0)
	sh.TextTransparency = math.max(lbl.TextTransparency, 0.45)
	sh.Position = lbl.Position + O(5, 7)
	sh.ZIndex = lbl.ZIndex - 1
	sh.Parent = lbl.Parent
	return g, sh
end

-- an expanding shockwave ring
local function shockwave(parent: Instance, x: number, y: number, color: Color3, size: number, t: number?, delay: number?)
	local r = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(40, 40), BackgroundTransparency = 1 }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, r)
	local s = new("UIStroke", { Color = color, Thickness = 10, Transparency = 0.1 }, r)
	tween(r, t or 0.7, { Size = O(size, size) }, Enum.EasingStyle.Quart, nil, delay)
	tween(s, t or 0.7, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quad, nil, delay)
	task.delay((t or 0.7) + (delay or 0) + 0.05, function()
		r:Destroy()
	end)
end

-- a premium plate: outer CanvasGroup (fades as one), inset edge frame carrying the border (so the
-- group never clips it), and a glossy body. Clip = true makes the body a CanvasGroup so the light
-- streaks are clipped to the rounded shape. Put content in the returned outer group (ZIndex 2+).
local function plate(parent: Instance, props, base: Color3, opts)
	opts = opts or {}
	local th = opts.Border or 2
	local r = opts.Round or 10
	local outer = new("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = if opts.Hidden then 1 else 0 }, parent)
	for k, v in props do
		outer[k] = v
	end
	local edge = new("Frame", { Name = "Edge", Position = O(th, th), Size = UDim2.new(1, -2 * th, 1, -2 * th), BackgroundTransparency = 1, ZIndex = 0 }, outer) -- under any content
	corner(edge, r)
	local body = new(if opts.Clip then "CanvasGroup" else "Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = base, BackgroundTransparency = opts.Alpha or 0, BorderSizePixel = 0, ZIndex = 1 }, edge)
	corner(body, r)
	glossy(body, base, { Period = opts.Period, StreakW = opts.StreakW, Phase = opts.Phase, Gloss = opts.Gloss, Top = opts.Top, Bottom = opts.Bottom, Round = r, Streaks = opts.Clip == true })
	if opts.Light then
		borderLight(edge, opts.Light, th, opts.LightSpeed)
	elseif opts.Stroke then
		new("UIStroke", { Color = opts.Stroke, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, edge)
	end
	return outer, body
end

-- 3D operative copy for the MVP (mocap clip decoder mirrors OperativeIntro, read-only)
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
			local f = { Pos = Vector3.new(v(1, 4), v(3, 4), v(5, 4)), Rot = table.create(#JOINT_ORDER) }
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
local CLIP = nil -- the MVP celebrates with the first clip that decodes from this list
task.spawn(function()
	local wc = player:WaitForChild("PlayerScripts"):WaitForChild("VantageWeaponClient", 30)
	local intro = wc and wc:WaitForChild("OperativeIntro", 30)
	local folder = intro and intro:WaitForChild("Clips", 30)
	if not folder then
		return
	end
	for _, name in { "YellingOut", "Charge", "Salute" } do
		local mod = folder:FindFirstChild(name)
		if mod and mod:IsA("ModuleScript") then
			local ok, def = pcall(require, mod)
			local clip = ok and type(def) == "table" and type(def.Data) == "string" and decodeClip(def)
			if clip then
				CLIP = clip
				break
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
local STANCE = {
	Waist = { -3, 0, 0 }, Neck = { 4, 0, 0 },
	RightShoulder = { 0, 0, 8 }, LeftShoulder = { 0, 0, -8 }, RightElbow = { 14, 0, 0 }, LeftElbow = { 14, 0, 0 },
	RightHip = { 2, -8, 6 }, LeftHip = { -2, 10, -7 }, RightKnee = { -4, 0, 0 }, LeftKnee = { -6, 0, 0 },
	RightAnkle = { 2, 0, -6 }, LeftAnkle = { 4, 0, 6 },
}
local SLUNG = CFrame.new(0.42, 0.25, 1.02) * ang(0, 0, -16) * ang(78, 0, 0)
local STRIP = { "Script", "LocalScript", "ModuleScript", "Sound", "ParticleEmitter", "Beam", "Trail", "BillboardGui", "SurfaceGui", "ForceField", "Fire", "Smoke", "Sparkles", "Highlight", "ProximityPrompt", "ClickDetector" }
local function copyCharacter(p: Player?): Model?
	local ch = p and p.Character
	if not (ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChild("UpperTorso")) then
		return nil
	end
	local was = ch.Archivable
	ch.Archivable = true
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
local function rigOf(model: Model)
	local rig = { Model = model, J = {} }
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
local function poseRig(rig, t: number)
	local breath = math.sin(t * 1.8)
	local T = {}
	for name in rig.J do
		local d = STANCE[name]
		T[name] = if d then ang(d[1], d[2], d[3]) else CFrame.identity
	end
	T.Waist = (T.Waist or CFrame.identity) * ang(-1.2 * breath, 0, 0)
	T.Neck = (T.Neck or CFrame.identity) * ang(0.6 * breath, 0, 0)
	local clip = CLIP
	if clip and t > 0 then
		local into = math.clamp(t / 0.3, 0, 1)
		local out = math.clamp((t - (clip.Dur - 0.6)) / 0.6, 0, 1)
		local w = into * (1 - out * 0.65)
		local pos, rot = sampleClip(clip, math.min(t, clip.Dur))
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

-- sequence state
local token = 0
local state = nil
local CAM_BIND = "VantageResultsCam"
local MOUSE_BIND = "VantageResultsMouse"

local function restore(st)
	pcall(function()
		RunService:UnbindFromRenderStep(CAM_BIND)
	end)
	pcall(function()
		RunService:UnbindFromRenderStep(MOUSE_BIND)
	end)
	pcall(function()
		ContextActionService:UnbindAction("VantageResultsSkip")
	end)
	for _, c in st.Conns do
		c:Disconnect()
	end
	for _, e in st.Effects do
		e:Destroy()
	end
	-- 2026-11-18 fix: never put back the camera captured at match end. It could be mid-ADS (zoomed
	-- FOV) or the death camera (Scriptable), and this runs after the lobby character has spawned,
	-- so it left players stuck zoomed in or with a frozen camera in the lobby. Hand back a clean
	-- Custom camera on the current character instead.
	local cam = Workspace.CurrentCamera
	if st.CamType then
		cam.CameraType = Enum.CameraType.Custom
		if player.Team == nil then
			cam.FieldOfView = 70 -- lobby FOV (VantageMovementClient)
		elseif st.Preview then
			cam.FieldOfView = st.FOV
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
	for _, g in st.Disabled do
		if g.Parent then
			g.Enabled = true
		end
	end
	if st.Gui then
		st.Gui:Destroy()
	end
end

local function teardown(instant: boolean?)
	local st = state
	if not st then
		return
	end
	state = nil
	token += 1
	fadeHeld(if instant then 0.25 else R.LeaveFade + 0.5) -- music bed / stings / crowd out with the screen
	if instant or not st.Gui then
		restore(st)
		return
	end
	local curtain = new("Frame", { Name = "Curtain", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 100 }, st.Gui)
	tween(curtain, R.LeaveFade, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(R.LeaveFade + 0.05, function()
		restore(st)
	end)
end

-- stage 2: the result band
local function reasonText(res): string
	local r = res.Reason
	local why = if r == "SCORE" then "SCORE LIMIT REACHED" elseif r == "TIME" then "TIME EXPIRED" elseif r == "OVERTIME" then "DECIDED IN SUDDEN DEATH" elseif r == "FORFEIT" then "THE OTHER TEAM LEFT" else ""
	return why .. (if (res.Duration or 0) > 0 then "   ·   " .. clock(res.Duration) else "")
end

local function scorePills(parent, res, y: number, h: number)
	local f = new("Frame", { Name = "Score", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = O(560, h), BackgroundTransparency = 1 }, parent)
	local function pill(team: string, x: number, left: boolean)
		local win = res.Winner == team
		local tc = teamColor(team)
		local p = plate(f, { AnchorPoint = V2(if left then 1 else 0, 0), Position = UDim2.new(0.5, x, 0, 0), Size = O(240, h) }, tc, {
			Round = 12, Border = if win then 3 else 2, Light = if win then GOLD else nil, Stroke = lighten(tc, 0.35), LightSpeed = 110,
			Clip = true, Period = 2.6, StreakW = 46, Phase = if left then 0 else 0.5, Gloss = 0.7,
		})
		label(p, { ZIndex = 3, Position = O(if left then 18 else 92, 0), Size = O(130, h), Text = string.upper(team), TextSize = math.floor(h * 0.42), FontFace = FRED, Stroke = 2.5, TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right })
		label(p, { ZIndex = 3, Position = O(if left then 140 else 14, 0), Size = O(86, h), Text = tostring(res[team] or 0), TextSize = math.floor(h * 0.7), FontFace = FRED, Stroke = 3, TextXAlignment = if left then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left })
		if win then
			glow(f, if left then 280 + x - 120 else 280 + x + 120, h / 2, 360, GOLD, 0.7).ZIndex = 0
		end
	end
	pill("Blue", -26, true)
	pill("Red", 26, false)
	label(f, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(52, h), Text = "—", TextSize = math.floor(h * 0.5), FontFace = FRED, Stroke = 2, TextXAlignment = Enum.TextXAlignment.Center })
	return f
end

local function buildBanner(layer, res, outcome: string, accent: Color3)
	local grp = new("Frame", { Name = "Banner", Size = O(1920, 1080), BackgroundTransparency = 1 }, layer)
	local bandColor = if outcome == "DEFEAT" then DEFEAT elseif outcome == "DRAW" then C(70, 80, 110) else accent
	local band = new("CanvasGroup", { Name = "Band", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, -2400, 0, 440), Size = O(2700, 230), Rotation = -4, BackgroundColor3 = bandColor, BorderSizePixel = 0 }, grp)
	-- glossy band: deep gradient, gloss, bevel, fast light streaks
	glossy(band, bandColor, { Period = 1.5, StreakW = 160, Gloss = 0.74, Top = 0.55, Bottom = 0.65 })
	-- bright rails top + bottom with a travelling hot spot
	for _, yy in { 0, 1 } do
		local rail = new("Frame", { AnchorPoint = V2(0, yy), Position = UDim2.fromScale(0, yy), Size = UDim2.new(1, 0, 0, 7), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, band)
		local rg = new("UIGradient", { Color = CS({ CK.new(0, lighten(bandColor, 0.45)), CK.new(0.45, lighten(bandColor, 0.45)), CK.new(0.5, Color3.new(1, 1, 1)), CK.new(0.55, lighten(bandColor, 0.45)), CK.new(1, lighten(bandColor, 0.45)) }) }, rail)
		animate(rg, function(t)
			rg.Offset = V2(((t * (if yy == 0 then 0.55 else -0.55)) % 2) - 1, 0)
		end)
	end
	-- chevrons racing along the band (speed lines)
	for i = 1, 14 do
		local ch = new("Frame", { Name = "Chevron", AnchorPoint = V2(0.5, 0.5), Size = O(70, 230), BackgroundTransparency = 1 }, band)
		for _, sgn in { -1, 1 } do
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, sgn * 34), Size = O(16, 90), Rotation = -sgn * 32, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, ch)
		end
		local off = i / 14
		animate(ch, function(t)
			ch.Position = UDim2.new((off + t * 0.08) % 1, 0, 0.5, 0)
		end)
	end
	tween(band, 0.5, { Position = UDim2.new(0.5, 0, 0, 440) }, Enum.EasingStyle.Quint)
	-- a slow breathing glow behind the band
	local bandGlow = glow(grp, 960, 440, 1500, bandColor, 0.9)
	bandGlow.ZIndex = 0
	animate(bandGlow, function(t)
		local k = 1 + 0.05 * math.sin(t * 2.2)
		bandGlow.Size = O(1500 * k, 1500 * k * 0.42)
	end)
	band.ZIndex = 1

	local word = label(grp, { Name = "Word", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 432), Size = O(1500, 200), Text = outcome, TextSize = 176, FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Rotation = -4, TextTransparency = 1, Stroke = 9 })
	word.ZIndex = 3
	local ws = new("UIScale", { Scale = 2.1 }, word)
	local _, wordShadow = shinyText(word, if outcome == "VICTORY" then C(255, 246, 214) elseif outcome == "DEFEAT" then C(255, 214, 218) else C(226, 232, 246), 2.2)
	local wss = new("UIScale", { Scale = 2.1 }, wordShadow)
	tween(word, 0.18, { TextTransparency = 0 }, Enum.EasingStyle.Quad, nil, 0.22)
	tween(wordShadow, 0.18, { TextTransparency = 0.45 }, Enum.EasingStyle.Quad, nil, 0.22)
	tween(ws, 0.55, { Scale = 1 }, Enum.EasingStyle.Back, nil, 0.22)
	tween(wss, 0.55, { Scale = 1 }, Enum.EasingStyle.Back, nil, 0.22)
	-- a slow "heartbeat" on the word after it lands
	task.delay(0.8, function()
		animate(ws, function(t)
			ws.Scale = 1 + 0.018 * math.sin(t * 3.2)
			wss.Scale = ws.Scale
		end)
	end)
	-- impact: double shockwave from the word
	shockwave(grp, 960, 432, Color3.new(1, 1, 1), 1500, 0.7, 0.32)
	shockwave(grp, 960, 432, lighten(bandColor, 0.4), 2100, 0.95, 0.42)
	local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, layer.Parent)
	task.delay(0.32, function()
		flash.BackgroundTransparency = if outcome == "VICTORY" then 0.55 else 0.8
		tween(flash, 0.5, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end)
	task.delay(1, function()
		flash:Destroy()
	end)

	local sub = if outcome == "DRAW" then "NO WINNER" elseif res.Winner == "Blue" or res.Winner == "Red" then string.upper(res.Winner) .. " TEAM WINS" else ""
	local info = new("CanvasGroup", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 620), Size = O(900, 190), BackgroundTransparency = 1, GroupTransparency = 1 }, grp)
	label(info, { Position = O(0, 0), Size = O(900, 40), Text = sub, TextSize = 34, FontFace = FRED, Stroke = 3, TextColor3 = if res.Winner == "Blue" or res.Winner == "Red" then lighten(teamColor(res.Winner), 0.2) else WHITE, TextXAlignment = Enum.TextXAlignment.Center })
	scorePills(info, res, 52, 70)
	label(info, { Position = O(0, 136), Size = O(900, 26), Text = reasonText(res), TextSize = 22, FontFace = BSM, TextColor3 = DIM, Stroke = 2, TextXAlignment = Enum.TextXAlignment.Center })
	tween(info, 0.5, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 590) }, Enum.EasingStyle.Quint, nil, 0.75)

	-- particles: rising gold sparks on a win, slow falling embers on a loss
	local win = outcome == "VICTORY"
	for i = 1, (if win then 46 else 22) do
		local x = math.random(80, 1840)
		local sz = math.random(5, if win then 13 else 9)
		local p = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, if win then 1120 else -30), Size = O(sz, sz), Rotation = 45, BorderSizePixel = 0,
			BackgroundColor3 = if win then (if i % 3 == 0 then Color3.new(1, 1, 1) else GOLD) else C(200, 50, 60), BackgroundTransparency = if win then 0.1 else 0.45 }, grp)
		local dur = if win then math.random(18, 34) / 10 else math.random(40, 60) / 10
		tween(p, dur, { Position = O(x + math.random(-80, 80), if win then math.random(80, 520) else math.random(700, 1100)), BackgroundTransparency = 1, Rotation = 45 + math.random(-180, 180) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, math.random() * (if win then 0.9 else 1.6))
	end

	task.delay(0.22, function()
		-- 2026-11-18 audio pass: a layered slam (impact + boom + music sting + crowd / fireworks)
		fadeOut(live.Suck, 0.06)
		live.Suck = nil
		if outcome == "VICTORY" then
			cue("ResSlam")
			cue("ResBoom")
			live.Sting = cue("ResFanfare")
			live.Crowd = cue("ResCrowd")
			task.delay(0.12, cue, "ResSparkle")
			task.delay(0.55, cue, "ResFireworks")
			task.delay(1.7, cue, "ResFireworks", 0.88, 0.8)
			task.delay(2.6, cue, "ResFireworks", 1.1, 0.6)
		elseif outcome == "DEFEAT" then
			cue("Defeat")
			cue("ResPowerDown")
			live.Sting = cue("ResDefeatSting")
		else
			cue("ResSlam", 0.9, 0.8)
			live.Sting = cue("ResDrawSting")
		end
	end)

	return grp, function()
		tween(band, 0.45, { Position = UDim2.new(0.5, 2600, 0, 440) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(word, 0.3, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(wordShadow, 0.3, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(bandGlow, 0.3, { Size = O(0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(info, 0.3, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local ust = word:FindFirstChildOfClass("UIStroke")
		if ust then
			tween(ust, 0.3, { Transparency = 1 })
		end
		task.delay(0.5, function()
			grp:Destroy()
		end)
	end
end

-- stage 3: MVP reveal
local function statTile(parent, x: number, y: number, title: string, value: number, color: Color3, delay: number, decimals: boolean?)
	local t = plate(parent, { Position = O(x, y + 24), Size = O(166, 104) }, PANEL:Lerp(color, 0.2), { Hidden = true, Round = 10, Stroke = darken(color, 0.25), Gloss = 0.86, Top = 0.3, Bottom = 0.6 })
	local bar = new("Frame", { ZIndex = 3, Position = O(10, 2), Size = UDim2.new(1, -20, 0, 4), BackgroundColor3 = color, BorderSizePixel = 0 }, t)
	corner(bar, 2)
	local bg = new("UIGradient", { Color = CS({ CK.new(0, color), CK.new(0.45, color), CK.new(0.5, Color3.new(1, 1, 1)), CK.new(0.55, color), CK.new(1, color) }) }, bar)
	animate(bg, function(tt)
		bg.Offset = V2(((tt * 0.6 + x / 900) % 2) - 1, 0)
	end)
	label(t, { ZIndex = 3, Position = O(0, 12), Size = O(166, 22), Text = title, TextSize = 18, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center })
	local v = label(t, { ZIndex = 3, Position = O(0, 38), Size = O(166, 54), Text = "0", TextSize = 48, FontFace = FRED, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, Stroke = 2.5 })
	tween(t, 0.4, { GroupTransparency = 0, Position = O(x, y) }, Enum.EasingStyle.Quint, nil, delay)
	task.delay(delay, function()
		countUp(v, value, 0.8, nil, decimals)
	end)
	return t
end

local function rowById(res, id: number)
	for _, r in res.Rows do
		if r.U == id then
			return r
		end
	end
	return nil
end

local function buildMVP(layer, res, st)
	local mvp = rowById(res, res.MVP)
	if not mvp then
		return nil
	end
	local tc = teamColor(mvp.T)
	local grp = new("Frame", { Name = "MVP", Size = O(1920, 1080), BackgroundTransparency = 1 }, layer)

	-- rays + halo + floor glow behind the operative
	local rays = new("Frame", { Name = "Rays", AnchorPoint = V2(0.5, 0.5), Position = O(600, 520), Size = O(1300, 1300), BackgroundTransparency = 1 }, grp)
	for i = 1, 16 do
		local r = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(if i % 2 == 0 then 70 else 36, 1300), Rotation = i * (180 / 16), BackgroundColor3 = if i % 2 == 0 then GOLD else tc, BorderSizePixel = 0, BackgroundTransparency = 0.25 }, rays)
		new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(0.42, 0.55), NK.new(0.5, 0.35), NK.new(0.58, 0.55), NK.new(1, 1) }) }, r)
	end
	local raysScale = new("UIScale", { Scale = 0.2 }, rays)
	tween(raysScale, 0.9, { Scale = 1 }, Enum.EasingStyle.Quint)
	-- a second, thinner white set turning the other way
	local rays2 = new("Frame", { Name = "Rays2", AnchorPoint = V2(0.5, 0.5), Position = O(600, 520), Size = O(1100, 1100), BackgroundTransparency = 1 }, grp)
	for i = 1, 10 do
		local r = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(14, 1100), Rotation = i * 18 + 9, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, BackgroundTransparency = 0.5 }, rays2)
		new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(0.46, 0.6), NK.new(0.54, 0.6), NK.new(1, 1) }) }, r)
	end
	local rays2Scale = new("UIScale", { Scale = 0.2 }, rays2)
	tween(rays2Scale, 1.1, { Scale = 1 }, Enum.EasingStyle.Quint)
	animate(rays2, function(t)
		rays2.Rotation = -t * 5
	end)
	glow(grp, 600, 470, 900, tc, 0.8).ZIndex = 0
	-- twinkles around the operative, all through the reveal
	local nextTw = 0
	animate(grp, function(t)
		if t < nextTw then
			return
		end
		nextTw = t + 0.09
		local sz = math.random(8, 18)
		local p = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(math.random(330, 870), math.random(140, 900)), Size = O(sz, sz), Rotation = 45, BackgroundColor3 = if math.random() < 0.35 then Color3.new(1, 1, 1) else GOLD, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, grp)
		local sc = new("UIScale", { Scale = 0.2 }, p)
		tween(p, 0.25, { BackgroundTransparency = 0.05 }, Enum.EasingStyle.Quad)
		tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(p, 0.5, { BackgroundTransparency = 1, Rotation = 135, Position = p.Position - O(0, 30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.3)
		task.delay(0.85, function()
			p:Destroy()
		end)
	end)
	local halo = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(600, 470), Size = O(620, 620), BackgroundColor3 = GOLD, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, grp)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
	new("UIGradient", { Transparency = NS({ NK.new(0, 0.2), NK.new(0.7, 0.85), NK.new(1, 1) }) }, halo)
	local floor = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(600, 930), Size = O(640, 110), BackgroundColor3 = GOLD, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, grp)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, floor)
	new("UIGradient", { Transparency = NS({ NK.new(0, 1), NK.new(0.5, 0.2), NK.new(1, 1) }) }, floor)

	-- the operative (3D copy) or, if their character is gone, a large avatar bust
	local mp = Players:GetPlayerByUserId(mvp.U)
	local copy = copyCharacter(mp)
	local rig = nil
	if copy then
		local vp = new("ViewportFrame", { Name = "Operative", AnchorPoint = V2(0.5, 0.5), Position = O(600, 560), Size = O(820, 1000), BackgroundTransparency = 1, Ambient = C(120, 120, 140), LightColor = C(255, 236, 200), LightDirection = Vector3.new(-0.6, -1, -0.8), ImageTransparency = 1 }, grp)
		local world = new("WorldModel", {}, vp)
		local root = copy:FindFirstChild("HumanoidRootPart") :: BasePart
		copy:PivotTo(CFrame.Angles(0, math.rad(-14), 0) * root.CFrame:Inverse() * copy:GetPivot())
		copy.Parent = world
		local cam = new("Camera", { FieldOfView = 26, CFrame = CFrame.lookAt(Vector3.new(0.9, 0.9, -11.5), Vector3.new(0, 0.15, 0)) }, vp)
		vp.CurrentCamera = cam
		rig = rigOf(copy)
		tween(vp, 0.5, { ImageTransparency = 0 }, Enum.EasingStyle.Quad, nil, 0.15)
		local c0 = cam.CFrame
		tween(cam, R.MVP, { CFrame = c0 * CFrame.new(0, 0, -1.4) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	else
		local a = avatar(grp, mvp.U, 420, GOLD, { AnchorPoint = V2(0.5, 0.5), Position = O(600, 500) })
		local s = new("UIScale", { Scale = 0.6 }, a)
		tween(s, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local t0 = os.clock()
	table.insert(st.Conns, RunService.RenderStepped:Connect(function()
		if not grp.Parent then
			return
		end
		local t = os.clock() - t0
		rays.Rotation = t * 9
		halo.BackgroundTransparency = 0.6 + 0.08 * math.sin(t * 2.4)
		if rig and rig.Model.Parent then
			poseRig(rig, t - 0.3)
		end
	end))

	-- the card
	local card = new("CanvasGroup", { Name = "Card", Position = O(1140, 150), Size = O(760, 300), BackgroundTransparency = 1, GroupTransparency = 1 }, grp)
	local title = label(card, { ZIndex = 3, Position = O(0, 0), Size = O(400, 130), Text = "MVP", TextSize = 140, FontFace = FRED, TextColor3 = WHITE, Stroke = 6 })
	shinyText(title, GOLD, 1.8)
	-- name plate: dark gold glass with a running gold border
	plate(card, { Position = O(0, 170), Size = O(760, 120), ZIndex = 1 }, PANEL:Lerp(GOLD, 0.16), { Clip = true, Light = GOLD, Round = 14, Border = 3, Period = 2.8, StreakW = 70, Gloss = 0.84, LightSpeed = 90 })
	label(card, { Position = O(6, 128), Size = O(740, 28), Text = "MOST VALUABLE PLAYER   ·   " .. string.upper(tostring(mvp.T)) .. " TEAM", TextSize = 24, FontFace = BSH, TextColor3 = lighten(tc, 0.25), Stroke = 2 })
	avatar(card, mvp.U, 100, GOLD, { Position = O(12, 180), ZIndex = 3 })
	label(card, { ZIndex = 3, Position = O(136, 186), Size = O(620, 56), Text = mvp.N, TextSize = 52, FontFace = FRED, Stroke = 3.5, TextTruncate = Enum.TextTruncate.AtEnd })
	label(card, { ZIndex = 3, Position = O(138, 244), Size = O(500, 26), Text = "@" .. tostring(mvp.Name or ""), TextSize = 22, FontFace = BSM, TextColor3 = DIM })
	if mvp.U == player.UserId then
		local you = new("Frame", { ZIndex = 4, Position = O(430, 34), Size = O(170, 46), BackgroundColor3 = GOLD, BorderSizePixel = 0, Rotation = -6 }, card)
		corner(you, 8)
		label(you, { Size = UDim2.fromScale(1, 1), Text = "THAT'S YOU!", TextSize = 24, FontFace = FRED, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center })
	end
	tween(card, 0.6, { GroupTransparency = 0, Position = O(1080, 150) }, Enum.EasingStyle.Quint, nil, 0.25)
	local tiles = new("Frame", { Name = "Stats", Position = O(1080, 470), Size = O(760, 240), BackgroundTransparency = 1 }, grp)
	local list = {
		{ "ELIMS", mvp.K, GOLD }, { "ASSISTS", mvp.A, BLUE }, { "DEATHS", mvp.D, RED }, { "K/D", if mvp.D > 0 then mvp.K / mvp.D else mvp.K, WHITE, true },
		{ "DAMAGE", mvp.Dmg, ORANGE }, { "HEADSHOTS", mvp.HS, C(255, 120, 200) }, { "RATING", mvp.R, GREEN }, { "EXP", mvp.XP, GREEN },
	}
	for i, s in list do
		local col, row = (i - 1) % 4, (i - 1) // 4
		statTile(tiles, col * 186, row * 120, s[1], s[2], s[3], 0.7 + i * 0.07, s[4])
	end

	-- top performer (best player overall) when it is not the MVP
	local top = rowById(res, res.Top)
	if top and top.U ~= mvp.U then
		local tcol = teamColor(top.T)
		local tp = plate(grp, { Name = "TopPerformer", Position = O(1080, 780), Size = O(740, 132) }, PANEL:Lerp(tcol, 0.22), { Hidden = true, Clip = true, Light = lighten(tcol, 0.2), Round = 12, Border = 2, Period = 3.4, StreakW = 60, Gloss = 0.86 })
		local acc = new("Frame", { ZIndex = 3, Position = O(2, 10), Size = UDim2.new(0, 6, 1, -20), BackgroundColor3 = tcol, BorderSizePixel = 0 }, tp)
		corner(acc, 3)
		avatar(tp, top.U, 92, C(220, 228, 245), { Position = O(24, 20), ZIndex = 3 })
		label(tp, { ZIndex = 3, Position = O(134, 14), Size = O(400, 26), Text = "TOP PERFORMER   ·   " .. string.upper(tostring(top.T)), TextSize = 21, FontFace = BSH, TextColor3 = lighten(tcol, 0.3) })
		label(tp, { ZIndex = 3, Position = O(134, 40), Size = O(420, 44), Text = top.N, TextSize = 38, FontFace = FRED, Stroke = 2.5, TextTruncate = Enum.TextTruncate.AtEnd })
		label(tp, { ZIndex = 3, Position = O(134, 88), Size = O(600, 28), Text = string.format("%d ELIMS   %d DEATHS   %d ASSISTS   K/D %s   RATING %s", top.K, top.D, top.A, kd(top.K, top.D), fmt(top.R)), TextSize = 21, FontFace = BS, TextColor3 = DIM })
		tween(tp, 0.5, { GroupTransparency = 0, Position = O(1080, 740) }, Enum.EasingStyle.Quint, nil, 1.6)
		task.delay(1.6, cue, "ResSparkleSoft", 1.2)
	end

	-- MVP sparkle burst + sound
	for i = 1, 26 do
		local a = math.random() * math.pi * 2
		local d = math.random(180, 460)
		local sz = math.random(6, 14)
		local p = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(600, 470), Size = O(sz, sz), Rotation = 45, BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else GOLD, BorderSizePixel = 0 }, grp)
		tween(p, 1.1, { Position = O(600 + math.cos(a) * d, 470 + math.sin(a) * d), BackgroundTransparency = 1, Size = O(2, 2) }, Enum.EasingStyle.Quart, nil, 0.1)
	end
	cue("MVP")
	if live.Outcome == "VICTORY" then
		cue("ResCrowdSurge") -- the crowd answers the MVP reveal (the fanfare rings out underneath)
	end
	task.delay(0.15, cue, "ResSparkle", 1.1)

	return grp, function()
		for _, d in grp:GetDescendants() do
			if d:IsA("CanvasGroup") then
				tween(d, 0.3, { GroupTransparency = 1 })
			end
		end
		tween(raysScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(halo, 0.3, { Size = O(0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local vp = grp:FindFirstChild("Operative")
		if vp then
			tween(vp, 0.3, { ImageTransparency = 1 })
		end
		task.delay(0.35, function()
			grp:Destroy()
		end)
	end
end

-- stage 4: the full board + your rewards
local COLS = { -- key, title, x, w
	{ "K", "K", 372, 58 }, { "D", "D", 432, 58 }, { "A", "A", 492, 58 }, { "KD", "K/D", 552, 72 },
	{ "XP", "EXP", 628, 80 }, { "REQ", "REQ", 712, 80 }, { "ORD", "ORD", 796, 70 },
}
local PANEL_W, ROW_H, ROW_GAP, MAX_ROWS = 880, 44, 4, 10

local function teamPanel(parent, res, team: string, x: number, delay0: number)
	local tc = teamColor(team)
	local win = res.Winner == team
	local rows = {}
	for _, r in res.Rows do
		if r.T == team then
			table.insert(rows, r)
		end
	end -- already in rating order (server)
	-- the panel: dark tinted glass; the winner's gets a running gold border + glow
	local ph = 92 + MAX_ROWS * (ROW_H + ROW_GAP)
	if win then
		glow(parent, x + PANEL_W / 2, 150 + ph / 2, 1100, GOLD, 0.45).ZIndex = 0
	end
	local p = plate(parent, { Name = team .. "Panel", Position = O(x, 150), Size = O(PANEL_W, ph) }, PANEL:Lerp(tc, 0.08), {
		Round = 14, Border = if win then 3 else 2, Light = if win then GOLD else nil, Stroke = EDGE, LightSpeed = 45, Gloss = 0.93, Top = 0.18, Bottom = 0.4, Alpha = 0.06,
	})
	local head = plate(p, { Size = UDim2.new(1, 0, 0, 58) }, tc, { Round = 12, Border = 0, Clip = true, Period = 3.2, StreakW = 90, Phase = if team == "Red" then 0.5 else 0, Gloss = 0.72 })
	label(head, { Position = O(20, 0), Size = O(400, 58), Text = string.upper(team) .. " TEAM", TextSize = 34, FontFace = FRED, Stroke = 2.5 })
	label(head, { AnchorPoint = V2(1, 0), Position = UDim2.new(1, -20, 0, 0), Size = O(140, 58), Text = tostring(res[team] or 0), TextSize = 46, FontFace = FRED, Stroke = 3, TextXAlignment = Enum.TextXAlignment.Right })
	if win then
		local wt = new("Frame", { Position = O(270, 13), Size = O(130, 32), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, head)
		corner(wt, 6)
		label(wt, { Size = UDim2.fromScale(1, 1), Text = "WINNER", TextSize = 22, FontFace = FRED, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center })
	end
	label(p, { Position = O(92, 62), Size = O(200, 24), Text = "PLAYER", TextSize = 17, FontFace = BSH, TextColor3 = DIM })
	for _, c in COLS do
		label(p, { Position = O(c[3], 62), Size = O(c[4], 24), Text = c[2], TextSize = 17, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center })
	end
	for i = 1, MAX_ROWS do
		local r = rows[i]
		local y = 90 + (i - 1) * (ROW_H + ROW_GAP)
		if not r then
			if i <= 8 then
				local e = new("Frame", { Position = O(10, y), Size = O(PANEL_W - 20, ROW_H), BackgroundColor3 = ROW, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, p)
				corner(e, 7)
			end
			continue
		end
		local me = r.U == player.UserId
		local isMvp = r.U == res.MVP
		local special = me or isMvp
		local base = if isMvp then ROW:Lerp(GOLD, 0.24) elseif me then lighten(ROW, 0.16) else ROW:Lerp(tc, 0.1)
		local row = plate(p, { Position = O(40, y), Size = O(PANEL_W - 20, ROW_H) }, base, {
			Hidden = true, Round = 8, Border = 2, Light = if isMvp then GOLD elseif me then WHITE else nil, Stroke = if r.Left then nil else darken(tc, 0.35),
			Clip = special, Period = 2.6, StreakW = 50, Phase = i * 0.09, Gloss = 0.88, Top = 0.25, Alpha = if r.Left then 0.5 else 0,
		})
		local acc = new("Frame", { Position = O(3, 6), Size = UDim2.new(0, 4, 1, -12), BackgroundColor3 = if isMvp then GOLD else tc, BorderSizePixel = 0 }, row)
		corner(acc, 2)
		local fade = if r.Left then 0.5 else 0
		label(row, { Position = O(8, 0), Size = O(30, ROW_H), Text = tostring(i), TextSize = 20, FontFace = FRED, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = fade })
		avatar(row, r.U, 34, tc, { Position = O(42, 5) })
		local nm = label(row, { Position = O(82, 0), Size = O(240, ROW_H), Text = r.N, TextSize = 22, FontFace = BSH, TextTruncate = Enum.TextTruncate.AtEnd, TextTransparency = fade })
		local tag, tagColor = nil, nil
		if isMvp then
			tag, tagColor = "MVP", GOLD
		elseif r.U == res.Top then
			tag, tagColor = "TOP", C(200, 210, 235)
		elseif r.Left then
			tag = "LEFT"
		end
		if tag then
			nm.Size = O(178, ROW_H)
			if tagColor then
				local b = new("Frame", { Position = O(266, 10), Size = O(56, 24), BackgroundColor3 = tagColor, BorderSizePixel = 0 }, row)
				corner(b, 5)
				label(b, { Size = UDim2.fromScale(1, 1), Text = tag, TextSize = 17, FontFace = FRED, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center })
			else
				label(row, { Position = O(266, 0), Size = O(56, ROW_H), Text = tag, TextSize = 16, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center })
			end
		end
		local vals = { K = fmt(r.K), D = fmt(r.D), A = fmt(r.A), KD = kd(r.K, r.D), XP = fmt(r.XP), REQ = fmt(r.REQ), ORD = fmt(r.ORD) }
		local colors = { XP = GREEN, REQ = C(150, 200, 255), ORD = ORANGE }
		for _, c in COLS do
			label(row, { Position = O(c[3] - 10, 0), Size = O(c[4], ROW_H), Text = vals[c[1]], TextSize = 22, FontFace = BSH, TextColor3 = colors[c[1]] or WHITE, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = fade })
		end
		local d = delay0 + (i - 1) * 0.05
		tween(row, 0.35, { GroupTransparency = 0, Position = O(10, y) }, Enum.EasingStyle.Quint, nil, d)
		task.delay(d, cue, "Row", 1 + i * 0.02)
	end
	return p
end

-- ─── Hypershot-style reward card: illustrated art, big +amount, currency name ───────────────────────────────────────────────────
local KIND_COL = { REQ = C(70, 140, 255), ORD = ORANGE, XP = C(60, 205, 90) }
local function asset(id: any): string
	if id == nil or id == "" or id == 0 then
		return ""
	end
	local s = tostring(id)
	return if s:find("rbxasset") then s else "rbxassetid://" .. s
end

-- the drawn EXP illustration (until card art is uploaded): rays, rank chevrons, glossy XP badge
local function drawXp(body: GuiObject, w: number, h: number, x: number)
	local col = KIND_COL.XP
	local rays = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = O(h * 1.4, h * 1.4), BackgroundTransparency = 1, ZIndex = 1 }, body)
	for i = 1, 12 do
		local r = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, w * 0.13, 1, 0), Rotation = i * 15, BackgroundColor3 = lighten(col, 0.5), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 1 }, rays)
		new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(0.5, 0.2), NK.new(1, 1) }) }, r)
	end
	animate(rays, function(t)
		rays.Rotation = t * 12
	end)
	local emblem = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = O(w * 0.7, w * 0.7), BackgroundTransparency = 1, ZIndex = 2 }, body)
	-- three gold rank chevrons
	for i = 1, 3 do
		local yy = 0.06 + (i - 1) * 0.11
		for _, sgn in { -1, 1 } do
			local bar = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, sgn * w * 0.085, yy, 0), Size = O(w * 0.2, w * 0.055), Rotation = sgn * -28, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2 }, emblem)
			corner(bar, 3)
			new("UIGradient", { Rotation = 90, Color = CS(C(255, 236, 150), C(230, 150, 30)) }, bar)
			new("UIStroke", { Color = INK, Thickness = 2 }, bar)
		end
	end
	local badge = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.68), Size = O(w * 0.62, w * 0.4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2 }, emblem)
	corner(badge, math.floor(w * 0.07))
	new("UIGradient", { Rotation = 90, Color = CS({ CK.new(0, C(190, 255, 170)), CK.new(0.45, C(80, 220, 100)), CK.new(1, C(20, 120, 50)) }) }, badge)
	new("UIStroke", { Color = INK, Thickness = math.max(3, w * 0.018) }, badge)
	local gl = new("Frame", { Size = UDim2.new(1, 0, 0.45, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 2 }, badge)
	corner(gl, math.floor(w * 0.07))
	new("UIGradient", { Rotation = 90, Transparency = NS(0, 1) }, gl)
	label(badge, { ZIndex = 3, Size = UDim2.fromScale(1, 1), Text = "XP", TextSize = math.floor(w * 0.27), FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Stroke = math.max(3, w * 0.018) })
	animate(emblem, function(t)
		emblem.Position = UDim2.new(0.5, 0, 0.4, math.sin(t * 2 + x) * h * 0.012)
		emblem.Rotation = math.sin(t * 1.4 + x) * 2
	end)
end

-- w x h at (x, y). big = the rewards stage version.
-- 2026-11-18 v3: no CanvasGroups (they render through a texture budget: soft + darker). Plain frames
-- and images at full brightness; the art pans / zooms through ImageRect so it moves inside its own
-- rounded frame; light rays spin behind the card; a shine band sweeps across; sparkles twinkle.
local function artCard(parent, x: number, y: number, w: number, h: number, kind: string, amount: number, delay: number, rot: number, big: boolean?)
	local col = KIND_COL[kind] or WHITE
	local art = (R.Cards and R.Cards[kind]) or {}
	local bgId, fgId = asset(art.Bg), asset(art.Fg)
	local rad = if big then 22 else 14
	local IW, IH = 844, 1024 -- card art canvas

	-- behind: spinning light rays + a pulsing glow in the card colour
	local aura = new("Frame", { Name = kind .. "Aura", AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(w * 2.2, w * 2.2), BackgroundTransparency = 1, Visible = false, ZIndex = 0 }, parent)
	for i = 1, 12 do
		local ray = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, w * (if i % 2 == 0 then 0.2 else 0.1), 1, 0), Rotation = i * 15, BackgroundColor3 = lighten(col, 0.45), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 0 }, aura)
		new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(0.3, 0.6), NK.new(0.5, 0.25), NK.new(0.7, 0.6), NK.new(1, 1) }) }, ray)
	end
	local auraScale = new("UIScale", { Scale = 0.2 }, aura)
	local halo = glow(parent, x, y, w * 1.8, lighten(col, 0.2), 1.5)
	halo.ZIndex = 0
	halo.Visible = false

	local card = new("Frame", { Name = kind .. "Card", AnchorPoint = V2(0.5, 0.5), Position = O(x, y - h * 0.25), Size = O(w, h), Rotation = rot, BackgroundColor3 = darken(col, 0.25), BorderSizePixel = 0, Visible = false, ZIndex = 2 }, parent)
	corner(card, rad)
	borderLight(card, lighten(col, 0.7), if big then 4 else 3, 140)
	local function layer(name: string, id: string, z: number)
		local im = new("ImageLabel", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = id, ScaleType = Enum.ScaleType.Stretch, ImageRectSize = V2(IW, IH), ZIndex = z }, card)
		corner(im, rad)
		return im
	end
	if bgId ~= "" then
		local bg = layer("ArtBg", bgId, 2)
		-- visible slow zoom + pan inside the card (zoom 1.03 .. 1.15)
		animate(bg, function(t)
			local k = 1.09 + 0.06 * math.sin(t * 0.8 + x)
			local sw, sh = IW / k, IH / k
			local ox = (IW - sw) * (0.5 + 0.45 * math.sin(t * 0.55 + x))
			local oy = (IH - sh) * (0.5 + 0.45 * math.cos(t * 0.47 + x))
			bg.ImageRectSize = V2(sw, sh)
			bg.ImageRectOffset = V2(ox, oy)
		end)
	elseif kind == "XP" then
		drawXp(card, w, h, x)
	end
	-- a soft light behind the subject (lifts the middle of the art)
	local lift = glow(card, w / 2, h * 0.4, w * 1.05, lighten(col, 0.75), 0.9, 3)
	animate(lift, function(t)
		local k = 1 + 0.1 * math.sin(t * 2.4 + x)
		lift.Size = O(w * 1.05 * k, w * 1.05 * k)
	end)
	if fgId ~= "" then
		local fg = layer("ArtFg", fgId, 4)
		animate(fg, function(t)
			local b = math.sin(t * 2.1 + x)
			local k = 1 + 0.025 * (0.5 + 0.5 * math.sin(t * 1.3 + x))
			fg.Size = UDim2.fromScale(k, k)
			fg.Position = UDim2.new((1 - k) / 2, 0, (1 - k) / 2, b * h * 0.025)
		end)
	end
	-- top gloss
	local gl = new("Frame", { Size = UDim2.fromScale(1, 0.4), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 5 }, card)
	corner(gl, rad)
	new("UIGradient", { Rotation = 90, Transparency = NS(0, 1) }, gl)
	-- light shine band sweeping across every 2.6 s
	local sh = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 6 }, card)
	corner(sh, rad)
	local shg = new("UIGradient", { Rotation = 24, Transparency = NS({ NK.new(0, 1), NK.new(0.4, 1), NK.new(0.5, 0.55), NK.new(0.6, 1), NK.new(1, 1) }), Offset = V2(-1.2, 0) }, sh)
	animate(shg, function(t)
		local u = ((t + x / 400) % 2.6) / 2.6
		shg.Offset = V2(-1.2 + u * 3, 0)
	end)
	-- light shade under the number only (keeps the art bright)
	local foot = new("Frame", { Position = UDim2.fromScale(0, 0.7), Size = UDim2.fromScale(1, 0.3), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 5 }, card)
	corner(foot, rad)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(1, 0.4) }) }, foot)
	-- twinkles over the card
	local nextTw = 0
	animate(card, function(t)
		if not card.Visible or t < nextTw then
			return
		end
		nextTw = t + (if big then 0.18 else 0.4)
		local s = math.random(5, if big then 12 else 8)
		local p = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.1 + math.random() * 0.8, 0.08 + math.random() * 0.6), Size = O(s, s), Rotation = 45, BackgroundColor3 = if math.random() < 0.5 then Color3.new(1, 1, 1) else lighten(col, 0.6), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 7 }, card)
		local ps = new("UIScale", { Scale = 0.2 }, p)
		tween(p, 0.2, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
		tween(ps, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(p, 0.45, { BackgroundTransparency = 1, Rotation = 135 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.3)
		task.delay(0.8, function()
			p:Destroy()
		end)
	end)
	local amt = label(card, { Name = "Amount", ZIndex = 9, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -math.floor(h * 0.12)), Size = UDim2.new(1, -8, 0, math.floor(h * 0.2)), Text = "+0", TextSize = math.floor(h * (if big then 0.17 else 0.16)), FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Stroke = if big then 5 else 3.5 })
	local _, amtSh = shinyText(amt, Color3.new(1, 1, 1):Lerp(col, 0.12), 2.2)
	amtSh.ZIndex = 8
	label(card, { Name = "Unit", ZIndex = 9, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -math.floor(h * 0.045)), Size = UDim2.new(1, 0, 0, math.floor(h * 0.09)), Text = if kind == "XP" then "EXP" else kind, TextSize = math.floor(h * 0.08), FontFace = FRED, TextColor3 = lighten(col, 0.6), TextXAlignment = Enum.TextXAlignment.Center, Stroke = if big then 3 else 2.5 })

	-- in: pop in from small with a drop, rays open, count up, land pop + burst, then float
	local sc = new("UIScale", { Scale = 0.35 }, card)
	task.delay(delay, function()
		if not card.Parent then
			return
		end
		card.Visible, aura.Visible, halo.Visible = true, true, true
		tween(card, 0.5, { Position = O(x, y) }, Enum.EasingStyle.Back)
		tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(auraScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Quint)
	end)
	animate(aura, function(t)
		aura.Rotation = t * 16
	end)
	local countT = if big then 1.1 else 0.7
	task.delay(delay + 0.2, function()
		if not card.Parent then
			return
		end
		countUp(amt, amount, countT, "+")
		cue("Reward", if kind == "REQ" then 1 elseif kind == "ORD" then 1.12 else 1.26, if big then 1 else 0.6)
		if big then
			for k = 1, 7 do
				task.delay(k * 0.13, cue, "ResCoinTick", 0.9 + k * 0.07) -- count-up: coin ticks rising in pitch
			end
		end
		task.delay(countT + 0.05, function()
			if not card.Parent then
				return
			end
			sc.Scale = 1.12
			tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			if big then
				shockwave(parent, x, y, lighten(col, 0.4), w * 2.2, 0.6)
				for i = 1, 16 do
					local a = math.random() * math.pi * 2
					local d = math.random(math.floor(w * 0.5), math.floor(w * 1.1))
					local s = math.random(6, 13)
					local p = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(s, s), Rotation = 45, BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else lighten(col, 0.3), BorderSizePixel = 0, ZIndex = 10 }, parent)
					tween(p, 0.8, { Position = O(x + math.cos(a) * d, y + math.sin(a) * d), BackgroundTransparency = 1, Size = O(2, 2) }, Enum.EasingStyle.Quart)
					task.delay(0.85, function()
						p:Destroy()
					end)
				end
			end
			animate(sc, function(t)
				card.Position = O(x, y + math.sin(t * 2 + x) * (if big then 8 else 4))
				card.Rotation = rot + math.sin(t * 1.3 + x) * 1.5
				local g = w * 1.8 * (1 + 0.08 * math.sin(t * 2.4))
				halo.Size = O(g, g)
			end)
		end)
	end)
	return card
end

-- ─── 2026-11-18 v4: rewards are EMBLEMS, not cards ────────────────────────────────────────────
-- The currency logo itself is the hero: big, full brightness, floating over spinning light rays
-- with an orbit ring, a glint, a coin fountain on landing, then "+amount" + a name pill.
local function rewardIcon(kind: string): string
	if kind == "REQ" then
		return asset(ReqIcon)
	elseif kind == "ORD" then
		return asset(OrdIcon)
	end
	return asset(R.Icons and R.Icons.XP)
end

local function glint(parent: GuiObject, x: number, y: number, size: number)
	local g = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(size, size), BackgroundTransparency = 1, ZIndex = 8 }, parent)
	for _, rot in { 0, 90 } do
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.12, 0, 1, 0), Rotation = rot, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 8 }, g)
		new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(0.5, 0), NK.new(1, 1) }) }, f)
		corner(f, 4)
	end
	local sc = new("UIScale", { Scale = 0 }, g)
	tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(g, 0.5, { Rotation = 90 }, Enum.EasingStyle.Quad)
	tween(sc, 0.25, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.28)
	task.delay(0.6, function()
		g:Destroy()
	end)
end

-- (x, y) = emblem centre; size = icon size; big = MATCH REWARDS stage, else the board strip
local function rewardEmblem(parent, x: number, y: number, size: number, kind: string, amount: number, delay: number, big: boolean?)
	local col = KIND_COL[kind] or WHITE
	local icon = rewardIcon(kind)
	local root = new("Frame", { Name = kind .. "Reward", Size = O(1920, 1080), BackgroundTransparency = 1, Visible = false }, parent)

	-- light rays: two sets turning opposite ways, colour + white
	local function rays(n: number, len: number, wide: number, c: Color3, tr: number)
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(len, len), BackgroundTransparency = 1, ZIndex = 0 }, root)
		for i = 1, n do
			local ray = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, wide * (if i % 2 == 0 then 1 else 0.55), 1, 0), Rotation = i * (180 / n), BackgroundColor3 = c, BackgroundTransparency = tr, BorderSizePixel = 0, ZIndex = 0 }, f)
			new("UIGradient", { Rotation = 90, Transparency = NS({ NK.new(0, 1), NK.new(0.32, 0.55), NK.new(0.5, 0.1), NK.new(0.68, 0.55), NK.new(1, 1) }) }, ray)
		end
		local s = new("UIScale", { Scale = 0 }, f)
		return f, s
	end
	local raysA, raysAS = rays(12, size * 2.6, size * 0.2, lighten(col, 0.35), 0.35)
	local raysB, raysBS = rays(8, size * 2.1, size * 0.07, Color3.new(1, 1, 1), 0.45)
	local halo = glow(root, x, y, size * 2, lighten(col, 0.25), 1.6)
	halo.ZIndex = 0
	-- orbit ring (tilted ellipse) with two travelling sparks
	local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y + size * 0.18), Size = O(size * 1.5, size * 0.5), BackgroundTransparency = 1, ZIndex = 1 }, root)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local ringStroke = new("UIStroke", { Color = lighten(col, 0.6), Thickness = if big then 3 else 2, Transparency = 0.35 }, ring)
	local ringGrad = new("UIGradient", { Transparency = NS({ NK.new(0, 0), NK.new(0.5, 0.9), NK.new(1, 0) }) }, ringStroke)
	local sparks = {}
	for i = 1, 2 do
		local d = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(size * 0.07, size * 0.07), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 6 }, root)
		new("UIStroke", { Color = lighten(col, 0.4), Thickness = 2 }, d)
		sparks[i] = d
	end
	local ringScale = new("UIScale", { Scale = 0 }, ring)

	-- the logo
	local img = new("ImageLabel", { Name = "Icon", AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(size, size), BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, ZIndex = 5 }, root)
	local isc = new("UIScale", { Scale = 0 }, img)
	-- soft shadow under the logo
	local shadow = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y + size * 0.62), Size = O(size * 0.8, size * 0.14), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 1 }, root)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, shadow)
	new("UIGradient", { Transparency = NS({ NK.new(0, 1), NK.new(0.5, 0.2), NK.new(1, 1) }) }, shadow)

	-- amount + name pill
	local amtY = y + size * 0.62 + (if big then 34 else 18)
	local amt = label(root, { Name = "Amount", ZIndex = 7, AnchorPoint = V2(0.5, 0), Position = O(x, amtY), Size = O(size * 2, math.floor(size * 0.36)), Text = "+0", TextSize = math.floor(size * (if big then 0.32 else 0.36)), FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Stroke = if big then 5 else 3, TextTransparency = 1 })
	local _, amtSh = shinyText(amt, lighten(col, 0.55), 2.4)
	amtSh.ZIndex = 6
	local pillW, pillH = (if big then 120 else 64), (if big then 34 else 20)
	local pill = new("Frame", { AnchorPoint = V2(0.5, 0), Position = O(x, amtY + size * 0.36 + (if big then 6 else 2)), Size = O(pillW, pillH), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 7, BackgroundTransparency = 1 }, root)
	corner(pill, pillH // 2)
	new("UIGradient", { Rotation = 90, Color = CS({ CK.new(0, lighten(col, 0.4)), CK.new(0.5, col), CK.new(1, darken(col, 0.35)) }) }, pill)
	local pillStroke = new("UIStroke", { Color = INK, Thickness = 2, Transparency = 1 }, pill)
	local pillText = label(pill, { ZIndex = 8, Size = UDim2.fromScale(1, 1), Text = if kind == "XP" then "EXP" else kind, TextSize = math.floor(pillH * 0.72), FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Stroke = 2, TextTransparency = 1 })

	-- ── timeline ──
	task.delay(delay, function()
		if not root.Parent then
			return
		end
		root.Visible = true
		-- slam in with a spin, rays + ring open, flash ring
		img.Rotation = -160
		tween(isc, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(img, 0.55, { Rotation = 0 }, Enum.EasingStyle.Back)
		tween(raysAS, 0.7, { Scale = 1 }, Enum.EasingStyle.Quint)
		tween(raysBS, 0.8, { Scale = 1 }, Enum.EasingStyle.Quint)
		tween(ringScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back, nil, 0.15)
		shockwave(root, x, y, lighten(col, 0.5), size * (if big then 3 else 2), 0.55, 0.2)
		tween(amt, 0.25, { TextTransparency = 0 }, nil, nil, 0.25)
		tween(amtSh, 0.25, { TextTransparency = 0.45 }, nil, nil, 0.25)
		tween(pill, 0.25, { BackgroundTransparency = 0 }, nil, nil, 0.3)
		tween(pillStroke, 0.25, { Transparency = 0 }, nil, nil, 0.3)
		tween(pillText, 0.25, { TextTransparency = 0 }, nil, nil, 0.3)
		cue("Reward", if kind == "REQ" then 1 elseif kind == "ORD" then 1.12 else 1.26, if big then 1 else 0.5)
		if big then -- the emblem spins in: air + a pitched slam per currency
			cue("ResWhoosh", 1.25, 0.7)
			cue("ResSlam", if kind == "REQ" then 1.5 elseif kind == "ORD" then 1.6 else 1.7, 0.4)
		end
	end)
	-- idle motion (starts with the slam so it never sits still)
	local nextGlint = 1.4
	animate(img, function(t)
		local tt = t - delay
		if tt < 0 then
			return
		end
		raysA.Rotation = tt * 14
		raysB.Rotation = -tt * 9
		ringGrad.Rotation = (tt * 90) % 360
		for i, d in sparks do
			local a = tt * 1.6 + i * math.pi
			d.Position = O(x + math.cos(a) * size * 0.75, y + size * 0.18 + math.sin(a) * size * 0.25)
			d.ZIndex = if math.sin(a) > 0 then 6 else 1 -- in front on the near side of the orbit
		end
		if tt > 0.6 then
			img.Position = O(x, y + math.sin(tt * 2 + x) * size * 0.035)
			img.Rotation = math.sin(tt * 1.4 + x) * 4
		end
		local hs = size * 2 * (1 + 0.08 * math.sin(tt * 2.6))
		halo.Size = O(hs, hs)
		if big and tt > nextGlint then
			nextGlint = tt + 1.3 + math.random() * 0.8
			glint(root, x + size * (0.22 + math.random() * 0.12), y - size * (0.2 + math.random() * 0.15), size * 0.36)
		end
	end)
	-- count up, then the payoff: pop, coin fountain, spark burst
	local countT = if big then 1.15 else 0.7
	task.delay(delay + 0.35, function()
		if not root.Parent then
			return
		end
		countUp(amt, amount, countT, "+")
		if big then
			for k = 1, 7 do
				task.delay(k * 0.13, cue, "ResCoinTick", 0.9 + k * 0.07) -- count-up: coin ticks rising in pitch
			end
		end
		task.delay(countT + 0.05, function()
			if not root.Parent then
				return
			end
			isc.Scale = 1.18
			tween(isc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			local as = new("UIScale", { Scale = 1.25 }, amt)
			tween(as, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			if not big then
				return
			end
			-- payoff: coin shower for the currencies, the rising prize flourish for EXP (the last one)
			if kind == "XP" then
				cue("ResPrize")
			else
				cue("ResCoins", if kind == "REQ" then 1 else 1.08)
			end
			cue("ResSparkle", if kind == "REQ" then 1 elseif kind == "ORD" then 1.12 else 1.26, 0.8)
			-- coin fountain: little copies of the logo arc up and fall
			for i = 1, 12 do
				local cs = math.random(math.floor(size * 0.12), math.floor(size * 0.2))
				local c = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(cs, cs), BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, ZIndex = 9, Rotation = math.random(-40, 40) }, root)
				local dx = math.random(-math.floor(size * 1.1), math.floor(size * 1.1))
				local up = math.random(math.floor(size * 0.5), math.floor(size * 1.0))
				local t1 = 0.3 + math.random() * 0.15
				tween(c, t1, { Position = O(x + dx * 0.5, y - up), Rotation = c.Rotation + math.random(-180, 180) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				task.delay(t1, function()
					if c.Parent then
						tween(c, 0.55, { Position = O(x + dx, y + size * 0.9), ImageTransparency = 1, Rotation = c.Rotation + math.random(-180, 180) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					end
				end)
				task.delay(t1 + 0.6, function()
					c:Destroy()
				end)
			end
			for i = 1, 14 do
				local ang = math.random() * math.pi * 2
				local dd = math.random(math.floor(size * 0.5), math.floor(size * 1.2))
				local ps = math.random(5, 12)
				local p = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(ps, ps), Rotation = 45, BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else lighten(col, 0.3), BorderSizePixel = 0, ZIndex = 9 }, root)
				tween(p, 0.75, { Position = O(x + math.cos(ang) * dd, y + math.sin(ang) * dd), BackgroundTransparency = 1, Size = O(2, 2) }, Enum.EasingStyle.Quart)
				task.delay(0.8, function()
					p:Destroy()
				end)
			end
			shockwave(root, x, y, Color3.new(1, 1, 1), size * 2.4, 0.5)
		end)
	end)
	return root
end

-- stage: MATCH REWARDS (three big emblems)
local function buildRewards(layer, myRow)
	local r = myRow or { REQ = 0, ORD = 0, XP = 0 }
	local grp = new("Frame", { Name = "Rewards", Size = O(1920, 1080), BackgroundTransparency = 1 }, layer)
	local title = label(grp, { ZIndex = 3, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = O(1200, 100), Text = "MATCH REWARDS", TextSize = 92, FontFace = FRED, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, Stroke = 6, TextTransparency = 1 })
	local _, tsh = shinyText(title, GOLD, 2)
	local ts = new("UIScale", { Scale = 1.6 }, title)
	local ts2 = new("UIScale", { Scale = 1.6 }, tsh)
	tween(title, 0.2, { TextTransparency = 0 })
	tween(tsh, 0.2, { TextTransparency = 0.45 })
	tween(ts, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ts2, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	local sub = label(grp, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 212), Size = O(1200, 30), Text = "EARNED THIS MATCH", TextSize = 26, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, Stroke = 2 })
	tween(sub, 0.4, { TextTransparency = 0 }, nil, nil, 0.25)
	rewardEmblem(grp, 520, 500, 250, "REQ", r.REQ, 0.35, true)
	rewardEmblem(grp, 960, 480, 250, "ORD", r.ORD, 0.75, true)
	rewardEmblem(grp, 1400, 500, 250, "XP", r.XP, 1.15, true)
	local hint = label(grp, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 900), Size = O(800, 30), Text = "CLICK TO CONTINUE", TextSize = 24, FontFace = BSH, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, Stroke = 2 })
	task.delay(2.2, function()
		if hint.Parent then
			animate(hint, function(t)
				hint.TextTransparency = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 3))
			end)
		end
	end)
	return grp, function()
		for _, d in grp:GetDescendants() do
			if d:IsA("TextLabel") then
				tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("ImageLabel") then
				tween(d, 0.3, { ImageTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, 0.3, { Transparency = 1 })
			elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
				tween(d, 0.3, { BackgroundTransparency = 1 })
			end
		end
		task.delay(0.35, function()
			grp:Destroy()
		end)
	end
end

-- board version: a compact emblem strip (same logos, smaller, no fountain)
local function rewardCard(parent, x: number, rot: number, kind: string, amount: number, delay: number)
	local _ = rot
	return rewardEmblem(parent, x, 812, 104, kind, amount, delay, false)
end

local function rewardCardOld(parent, x: number, rot: number, kind: string, amount: number, delay: number)
	local col = if kind == "REQ" then C(70, 130, 230) elseif kind == "ORD" then ORANGE else C(60, 190, 80)
	local cardGlow = glow(parent, x, 860, 380, col, 0)
	cardGlow.ZIndex = 0
	local card = plate(parent, { Name = kind .. "Card", AnchorPoint = V2(0.5, 0.5), Position = O(x, 800), Size = O(196, 206), Rotation = rot }, col, {
		Hidden = true, Clip = true, Light = lighten(col, 0.55), Border = 3, Round = 16, Period = 2.4, StreakW = 64, Phase = x / 1000, Gloss = 0.68, Top = 0.6, Bottom = 0.6, LightSpeed = 120,
	})
	-- after it lands: float, sway, breathe the glow
	task.delay(delay + 0.5, function()
		if not card.Parent then
			return
		end
		for _, d in cardGlow:GetChildren() do
			tween(d, 0.5, { BackgroundTransparency = 0.9 })
		end
		animate(card, function(t)
			card.Position = O(x, 860 + math.sin(t * 2 + x) * 5)
			card.Rotation = rot + math.sin(t * 1.3 + x) * 1.2
			cardGlow.Size = O(380 + math.sin(t * 2.4) * 24, 380 + math.sin(t * 2.4) * 24)
		end)
	end)
	local shine = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(-0.4, 0.5), Size = O(50, 400), Rotation = 25, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0 }, card)
	if kind == "XP" then
		local icon = new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = O(108, 70), BackgroundColor3 = C(30, 110, 45), BorderSizePixel = 0 }, card)
		corner(icon, 12)
		stroke(icon, INK, 3)
		new("UIGradient", { Rotation = 90, Color = CS(C(160, 255, 160), C(50, 190, 70)) }, icon)
		label(icon, { Size = UDim2.fromScale(1, 1), Text = "XP", TextSize = 50, FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Stroke = 3 })
	else
		new("ImageLabel", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = O(96, 96), BackgroundTransparency = 1, Image = if kind == "REQ" then ReqIcon else OrdIcon, ScaleType = Enum.ScaleType.Fit }, card)
	end
	local amt = label(card, { Position = O(0, 112), Size = O(196, 52), Text = "+0", TextSize = 46, FontFace = FRED, Stroke = 3.5, TextXAlignment = Enum.TextXAlignment.Center })
	label(card, { Position = O(0, 160), Size = O(196, 30), Text = if kind == "XP" then "EXP" else kind, TextSize = 24, FontFace = FRED, Stroke = 2.5, TextXAlignment = Enum.TextXAlignment.Center })
	local sc = new("UIScale", { Scale = 1.25 }, card)
	tween(card, 0.45, { GroupTransparency = 0, Position = O(x, 860) }, Enum.EasingStyle.Back, nil, delay)
	tween(sc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, nil, delay)
	tween(shine, 0.9, { Position = UDim2.fromScale(1.4, 0.5) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, delay + 0.4)
	task.delay(delay + 0.15, function()
		if not card.Parent then
			return
		end
		countUp(amt, amount, 1.1, "+")
		cue("Reward", if kind == "REQ" then 1 elseif kind == "ORD" then 1.12 else 1.26)
		for k = 1, 6 do
			task.delay(k * 0.13, cue, "ResCoinTick", 0.9 + k * 0.07) -- count-up: coin ticks rising in pitch
		end
		task.delay(1.15, function()
			if card.Parent then
				sc.Scale = 1.12
				tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end)
	return card
end

local function button(parent, frameProps, text: string, textColor: Color3?, size: number?, strokeT: number?)
	local b = new("TextButton", { AutoButtonColor = false, Text = "", BorderSizePixel = 0, Modal = true }, parent)
	for k, v in frameProps do
		b[k] = v
	end
	local base = b.BackgroundColor3
	b.BackgroundTransparency = 1
	plate(b, { Size = UDim2.fromScale(1, 1), ZIndex = 1 }, base, { Clip = true, Round = 12, Border = 2, Light = lighten(base, 0.6), LightSpeed = 140, Period = 2.2, StreakW = 46, Gloss = 0.62, Top = 0.55 })
	local l = label(b, { ZIndex = 3, Size = UDim2.fromScale(1, 1), Text = text, TextSize = size or 28, FontFace = FRED, TextColor3 = textColor or WHITE, TextXAlignment = Enum.TextXAlignment.Center, Stroke = strokeT })
	local sc = new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		tween(sc, 0.12, { Scale = 1.05 })
		cue("Row", 1.6, 1.5)
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.12, { Scale = 1 })
	end)
	return b, l
end

local function buildBoard(layer, res, st, outcome: string, accent: Color3, myRow)
	local grp = new("Frame", { Name = "Board", Size = O(1920, 1080), BackgroundTransparency = 1 }, layer)
	local word = label(grp, { Position = O(60, 34), Size = O(520, 90), Text = outcome, TextSize = 88, FontFace = FRED, TextColor3 = if outcome == "DEFEAT" then C(255, 90, 100) else accent, Stroke = 5 })
	local meta = string.format("%s   ·   %s   ·   %s%s", MODE_NAMES[res.Mode] or tostring(res.Mode), string.upper(tostring(Match:GetAttribute("MapName") or "")), clock(res.Duration or 0), if res.Overtime then "   ·   OVERTIME" else "")
	label(grp, { Position = O(64, 114), Size = O(900, 26), Text = meta, TextSize = 22, FontFace = BSH, TextColor3 = DIM })
	scorePills(grp, res, 46, 64)
	local tint = word.TextColor3
	word.TextColor3 = WHITE
	local _, wsh = shinyText(word, lighten(tint, 0.15), 2.6)
	local ws = new("UIScale", { Scale = 1.3 }, word)
	local ws2 = new("UIScale", { Scale = 1.3 }, wsh)
	tween(ws, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ws2, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	-- your team on the left
	local myT = (myRow and myRow.T) or (if player.Team then player.Team.Name else "Blue")
	local leftT = if myT == "Red" then "Red" else "Blue"
	local rightT = if leftT == "Blue" then "Red" else "Blue"
	teamPanel(grp, res, leftT, 60, 0.15)
	teamPanel(grp, res, rightT, 980, 0.3)

	-- your match: stats, reward cards, level, buttons
	local r = myRow or { K = 0, D = 0, A = 0, Dmg = 0, REQ = 0, ORD = 0, XP = 0, R = 0 }
	label(grp, { Position = O(64, 728), Size = O(460, 30), Text = "YOUR MATCH", TextSize = 26, FontFace = FRED, TextColor3 = DIM, Stroke = 2 })
	local mine = {
		{ "ELIMS", fmt(r.K) }, { "DEATHS", fmt(r.D) }, { "ASSISTS", fmt(r.A) },
		{ "K/D", kd(r.K, r.D) }, { "DAMAGE", fmt(r.Dmg) }, { "RATING", fmt(r.R) },
	}
	for i, s in mine do
		local col, row = (i - 1) % 3, (i - 1) // 3
		local t = plate(grp, { Position = O(64 + col * 160, 768 + row * 92), Size = O(148, 82) }, PANEL:Lerp(BLUE, 0.1), { Round = 10, Stroke = EDGE, Gloss = 0.86, Top = 0.3 })
		label(t, { Position = O(0, 6), Size = O(148, 22), Text = s[1], TextSize = 17, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center })
		label(t, { Position = O(0, 28), Size = O(148, 48), Text = s[2], TextSize = 40, FontFace = FRED, TextXAlignment = Enum.TextXAlignment.Center, Stroke = 2 })
	end
	label(grp, { Position = O(580, 728), Size = O(680, 30), Text = "MATCH REWARDS", TextSize = 26, FontFace = FRED, TextColor3 = GOLD, Stroke = 2, TextXAlignment = Enum.TextXAlignment.Center })
	local d0 = 0.9
	rewardCard(grp, 700, -6, "REQ", r.REQ, d0)
	rewardCard(grp, 920, 0, "ORD", r.ORD, d0 + 0.35)
	rewardCard(grp, 1140, 6, "XP", r.XP, d0 + 0.7)

	-- level bar (live attributes, so a level-up during the match shows)
	local lv = new("Frame", { Position = O(1300, 740), Size = O(560, 70), BackgroundTransparency = 1 }, grp)
	label(lv, { Size = O(560, 30), Text = "LEVEL " .. tostring(player:GetAttribute("Level") or 1), TextSize = 28, FontFace = FRED, Stroke = 2.5 })
	local xpText = label(lv, { Size = O(560, 30), Text = "", TextSize = 20, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right })
	local track = new("Frame", { Position = O(0, 38), Size = O(560, 18), BackgroundColor3 = C(16, 24, 48), BorderSizePixel = 0 }, lv)
	corner(track, 9)
	stroke(track, INK, 2)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, track)
	corner(fill, 9)
	local fg = new("UIGradient", { Color = CS({ CK.new(0, C(70, 200, 95)), CK.new(0.4, C(140, 250, 140)), CK.new(0.5, Color3.new(1, 1, 1)), CK.new(0.6, C(140, 250, 140)), CK.new(1, C(70, 200, 95)) }) }, fill)
	animate(fg, function(t)
		fg.Offset = V2(((t * 0.5) % 2) - 1, 0)
	end)
	local into, need = tonumber(player:GetAttribute("LevelXP")) or 0, math.max(1, tonumber(player:GetAttribute("LevelNeed")) or 1)
	xpText.Text = fmt(into) .. " / " .. fmt(need) .. " XP"
	tween(fill, 1.2, { Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1) }, Enum.EasingStyle.Quart, nil, d0 + 1.2)
	task.delay(d0 + 1.2, cue, "ResRiser", 2.6) -- riser squeezed to the 1.2 s fill
	task.delay(d0 + 2.4, cue, "ResSparkleSoft", 1.3, 0.7)

	-- buttons + the server's countdown
	local back = label(grp, { Name = "Countdown", Position = O(1300, 836), Size = O(560, 26), Text = "", TextSize = 21, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right })
	local againGlow = glow(grp, 1720, 914, 420, GOLD, 0.6)
	againGlow.ZIndex = 0
	animate(againGlow, function(t)
		local k = 1 + 0.08 * math.sin(t * 3)
		againGlow.Size = O(420 * k, 200 * k)
	end)
	local again, againL = button(grp, { Name = "PlayAgain", Position = O(1580, 876), Size = O(280, 76), BackgroundColor3 = C(255, 190, 52) }, "PLAY AGAIN", INK, 30)
	local lobby, lobbyL = button(grp, { Name = "Lobby", Position = O(1300, 876), Size = O(260, 76), BackgroundColor3 = C(34, 52, 104) }, "LOBBY", WHITE, 28, 2)
	label(grp, { Position = O(1300, 960), Size = O(560, 22), Text = "ENTER  play again", TextSize = 18, FontFace = BSM, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right })
	local busy = false
	local function leave(queueAgain: boolean)
		if busy then
			return
		end
		busy = true
		cue("Reward", 0.9)
		if queueAgain then
			againL.Text = "JOINING..."
		else
			lobbyL.Text = "LEAVING..."
		end
		if st.Preview then
			task.delay(0.4, teardown)
			return
		end
		task.spawn(function()
			local ok, done = pcall(function()
				return Request:InvokeServer("Leave")
			end)
			if not (ok and done) then
				-- 2026-11-18 fix: the server already sent us back (match cleaned up) -> just close
				if player:GetAttribute("MatchStatus") ~= "Match" or Match:GetAttribute("Phase") ~= "Ended" then
					teardown()
					return
				end
				busy = false
				againL.Text, lobbyL.Text = "PLAY AGAIN", "LOBBY"
				return
			end
			if queueAgain then
				local t = os.clock()
				while player:GetAttribute("MatchStatus") == "Match" and os.clock() - t < 3 do
					task.wait(0.05)
				end
				pcall(function()
					return Request:InvokeServer("Queue", res.Mode)
				end)
			end
		end)
	end
	again.Activated:Connect(function()
		leave(true)
	end)
	lobby.Activated:Connect(function()
		leave(false)
	end)
	st.OnEnter = function()
		leave(true)
	end
	local lastBackSec: number? = nil
	table.insert(st.Conns, RunService.Heartbeat:Connect(function()
		local ends = tonumber(Match:GetAttribute("PhaseEnds")) or 0
		if st.Preview or Match:GetAttribute("Phase") ~= "Ended" or ends <= 0 then
			lastBackSec = nil
			if back.Text ~= "" then
				back.Text = ""
			end
			return
		end
		-- B3: the countdown ticks once a second; write the label only when the second changed
		local sec = math.max(0, math.ceil(ends - Workspace:GetServerTimeNow()))
		if sec ~= lastBackSec then
			lastBackSec = sec
			back.Text = "RETURNING TO LOBBY IN " .. sec
		end
	end))
	return grp
end

-- director
local function run(res, preview: boolean?)
	teardown(true)
	token += 1
	local my = token
	local st = { Conns = {}, Effects = {}, Disabled = {}, Preview = preview == true }
	state = st
	local myRow = rowById(res, player.UserId)
	local myT = (myRow and myRow.T) or (if player.Team then player.Team.Name else nil)
	local outcome = if res.Winner == "Draw" then "DRAW" elseif res.Winner == myT then "VICTORY" else "DEFEAT"
	local accent = if outcome == "VICTORY" then teamColor(myT) elseif outcome == "DEFEAT" then DEFEAT else C(200, 206, 222)

	-- every other screen out of the way (restored on teardown)
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "VantageMatchResults" then
			g.Enabled = false
			table.insert(st.Disabled, g)
		end
	end
	local gui = new("ScreenGui", { Name = "VantageMatchResults", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	st.Gui = gui
	local tint = new("Frame", { Name = "Tint", Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent, BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
	local shade = new("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
	-- backdrop: optional art (MatchConfig.Results.Art) under a living streak field + drifting blooms
	local back = new("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui) -- plain frame (no CanvasGroup: full-res art)
	-- art: two 800x900 tiles side by side (full 1600x900 detail), cover-fitted to the screen, with a
	-- slow but clearly visible zoom + drift
	local art = new("Frame", { Name = "Art", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 }, back)
	local tileL = new("ImageLabel", { Name = "L", Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Stretch, Image = "", ImageTransparency = 1 }, art)
	local tileR = new("ImageLabel", { Name = "R", Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Stretch, Image = "", ImageTransparency = 1 }, art)
	animate(art, function(t)
		local vs = Workspace.CurrentCamera.ViewportSize
		local w = math.max(vs.X, vs.Y * 16 / 9)
		local k = 1.09 + 0.05 * math.sin(t * 0.22)
		art.Size = O(w * k, w * 9 / 16 * k)
		art.Position = UDim2.new(0.5, math.sin(t * 0.17) * vs.X * 0.02, 0.5, math.cos(t * 0.13) * vs.Y * 0.015)
	end)
	-- a wide light sweep crossing the art every few seconds
	local sweep = new("Frame", { Name = "Sweep", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, back)
	local swg = new("UIGradient", { Rotation = 20, Transparency = NS({ NK.new(0, 1), NK.new(0.42, 1), NK.new(0.5, 0.86), NK.new(0.58, 1), NK.new(1, 1) }), Offset = V2(-1.2, 0) }, sweep)
	animate(swg, function(t)
		local u = (t % 4.5) / 4.5
		swg.Offset = V2(-1.2 + u * 2.6, 0)
	end)
	-- embers rising through the scene
	local nextEmber = 0
	animate(back, function(t)
		if not back.Visible or t < nextEmber then
			return
		end
		nextEmber = t + 0.06
		local vs = Workspace.CurrentCamera.ViewportSize
		local x = math.random() * vs.X
		local s = math.random(2, 6)
		local e = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, vs.Y + 10), Size = O(s, s), Rotation = 45, BackgroundColor3 = if math.random() < 0.6 then lighten(accent, 0.5) else GOLD, BackgroundTransparency = 0.15, BorderSizePixel = 0 }, back)
		local dur = 3 + math.random() * 3
		tween(e, dur, { Position = O(x + math.random(-120, 120), vs.Y * (0.15 + math.random() * 0.5)), BackgroundTransparency = 1, Rotation = 45 + math.random(-200, 200) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		task.delay(dur + 0.05, function()
			e:Destroy()
		end)
	end)
	local vs0 = Workspace.CurrentCamera.ViewportSize
	for i = 1, 3 do
		local bx, by = vs0.X * (0.2 + 0.3 * (i - 1)), vs0.Y * (if i == 2 then 0.75 else 0.3)
		local b = glow(back, bx, by, vs0.Y * 0.9, if i == 2 then GOLD else accent, 0.55)
		animate(b, function(t)
			b.Position = O(bx + math.sin(t * 0.3 + i) * vs0.X * 0.06, by + math.cos(t * 0.25 + i) * vs0.Y * 0.06)
		end)
	end
	streakField(back, { lighten(accent, 0.3), Color3.new(1, 1, 1), accent }, 28)
	local function setArt(key: string?)
		local pair = key and R.Art and R.Art[key]
		if type(pair) ~= "table" then
			pair = if pair and pair ~= "" then { pair, pair } else nil
		end
		if not pair then
			tween(tileL, 0.4, { ImageTransparency = 1 })
			tween(tileR, 0.4, { ImageTransparency = 1 })
			return
		end
		tileL.Image, tileR.Image = asset(pair[1]), asset(pair[2])
		tileL.ImageTransparency, tileR.ImageTransparency = 1, 1
		tween(tileL, 0.6, { ImageTransparency = 0 })
		tween(tileR, 0.6, { ImageTransparency = 0 })
	end
	local layer = new("Frame", { Name = "Layer", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(1920, 1080), BackgroundTransparency = 1 }, gui)
	local us = new("UIScale", {}, layer)
	local function fit()
		local vs = Workspace.CurrentCamera.ViewportSize
		us.Scale = math.min(vs.X / 1920, vs.Y / 1080)
	end
	fit()
	table.insert(st.Conns, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit))
	local hint = label(gui, { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = O(600, 24), Text = "SPACE / CLICK TO SKIP", TextSize = 18, FontFace = BSH, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
	tween(hint, 0.4, { TextTransparency = 0.25 }, nil, nil, 1.2)

	-- 1. END WASH: camera eases back and up, colour drains into the result tint
	local cam = Workspace.CurrentCamera
	st.CamType, st.FOV = cam.CameraType, cam.FieldOfView
	local c0, fov0, ct0 = cam.CFrame, cam.FieldOfView, os.clock()
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Camera.Value + 60, function()
		local e = 1 - (1 - math.min((os.clock() - ct0) / 6, 1)) ^ 3
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = c0 * CFrame.new(0, 2.2 * e, 7 * e) * CFrame.Angles(-0.13 * e, 0.06 * e, 0)
		cam.FieldOfView = fov0 - 10 * e
	end)
	local cc = new("ColorCorrectionEffect", { Name = "VantageResultsCC" }, cam)
	local blur = new("BlurEffect", { Name = "VantageResultsBlur", Size = 0 }, cam)
	table.insert(st.Effects, cc)
	table.insert(st.Effects, blur)
	tween(cc, R.Wash, { Saturation = -0.75, TintColor = accent:Lerp(Color3.new(1, 1, 1), 0.55), Brightness = -0.04, Contrast = 0.1 }, Enum.EasingStyle.Quad)
	tween(tint, R.Wash, { BackgroundTransparency = 0.72 }, Enum.EasingStyle.Quad)
	cue("EndHit")
	-- the suck-back peaks 2.0 s in: time it to land on the VICTORY / DEFEAT slam (banner + 0.22 s)
	table.clear(live)
	live.Outcome = outcome
	live.Suck = cue("ResSuck", 2.0 / (R.Wash + 0.22))

	local skip = false
	ContextActionService:BindActionAtPriority("VantageResultsSkip", function(_, s, input)
		if s ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if input.KeyCode == Enum.KeyCode.Return and st.OnEnter then
			st.OnEnter()
			return Enum.ContextActionResult.Sink
		end
		if not st.Board and (input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			skip = true
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)
	-- a free cursor for the buttons (the weapon client locks it in first person)
	RunService:BindToRenderStep(MOUSE_BIND, Enum.RenderPriority.Last.Value, function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)

	-- each stage holds for its own duration; SPACE / click ends the current stage only
	-- (banner -> MVP -> rewards -> board), like Hypershot's "to continue"
	local function hold(dur: number): boolean
		local s0 = os.clock()
		while os.clock() - s0 < dur do
			if token ~= my then
				return false
			end
			if skip then
				skip = false
				return token == my
			end
			task.wait()
		end
		return token == my
	end

	if not hold(R.Wash) then
		return
	end
	-- 2. RESULT BAND
	local outBanner = nil
	if not skip then
		tween(blur, 0.6, { Size = 6 })
		setArt(if outcome == "VICTORY" then "Victory" .. tostring(myT) elseif outcome == "DEFEAT" then "Defeat" else nil)
		local bannerKey = if outcome == "VICTORY" then "Victory" .. tostring(myT) elseif outcome == "DEFEAT" then "Defeat" else nil
		back.Visible = true
		local _, out = buildBanner(layer, res, outcome, accent)
		outBanner = out
		if not hold(R.Banner) then
			return
		end
	end
	if outBanner then
		outBanner()
	end
	-- stage change: a sweep; the crowd breathes out, a long sting (draw / defeat) makes room
	cue("ResWhoosh")
	fadeOut(live.Crowd, 3)
	if outcome ~= "VICTORY" then
		fadeOut(live.Sting, 2.5)
	end
	-- 3. MVP
	local outMvp = nil
	if not skip then
		tween(shade, 0.5, { BackgroundTransparency = 0.18 }, Enum.EasingStyle.Quad)
		tween(blur, 0.5, { Size = 18 })
		tween(tint, 0.5, { BackgroundTransparency = 0.9 })
		setArt("MVP")
		back.Visible = true
		local ok, g, out = pcall(buildMVP, layer, res, st)
		if ok and g then
			outMvp = out
			if not hold(R.MVP) then
				return
			end
		elseif not ok then
			warn("[VANTAGE] results MVP:", g)
		end
	end
	if token ~= my then
		return
	end
	if outMvp then
		outMvp()
	end
	-- 3b. MATCH REWARDS: three big illustrated cards (+REQ / +ORD / +EXP)
	do
		local ok, g, out = pcall(buildRewards, layer, myRow)
		if ok and g then
			cue("MVP", 1.15, 0.7)
			cue("ResWhoosh", 0.9)
			if not hold(R.Rewards or 4.8) then
				return
			end
			out()
		elseif not ok then
			warn("[VANTAGE] results rewards:", g)
		end
	end
	if skip then -- skipping: clear whatever stage was up
		for _, c in layer:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	-- 4. BOARD
	st.Board = true
	-- the board's music bed (VantageMusic), faded in under a sweep; stings / crowd make room
	cue("ResWhoosh", 0.8, 0.8)
	fadeOut(live.Crowd, 1.2)
	fadeOut(live.Sting, 1.2)
	local bed = cue(if outcome == "VICTORY" then "ResBedVictory" elseif outcome == "DEFEAT" then "ResBedDefeat" else "ResBedDraw")
	fadeIn(bed, if outcome == "DEFEAT" then 0.8 else 2.2)
	tween(hint, 0.2, { TextTransparency = 1 })
	tween(shade, 0.4, { BackgroundTransparency = 0.08 }, Enum.EasingStyle.Quad)
	tween(blur, 0.4, { Size = 22 })
	tween(tint, 0.4, { BackgroundTransparency = 0.94 })
	setArt("Board")
	back.Visible = true
	task.wait(if skip then 0.05 else 0.3)
	if token ~= my then
		return
	end
	local ok, err = pcall(buildBoard, layer, res, st, outcome, accent, myRow)
	if not ok then
		warn("[VANTAGE] results board:", err)
	end
end

-- wiring
local function results()
	local raw = Match:GetAttribute("Results")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, res = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return if ok and type(res) == "table" and type(res.Rows) == "table" then res else nil
end

local function onEnded()
	if player:GetAttribute("MatchStatus") ~= "Match" then
		return
	end
	local res = results()
	local t = os.clock()
	while not res and os.clock() - t < 2 do -- Results is set just before the phase
		task.wait(0.05)
		res = results()
	end
	if not res or Match:GetAttribute("Phase") ~= "Ended" then
		return
	end
	-- 2026-11-18 fix: watchdog. If the server sends us back to the lobby while the results are
	-- still being built, the MatchStatus / Phase signals fire before `state` exists and the
	-- results screen would stay up forever (CONTINUE then fails with NOT IN RESULTS).
	task.spawn(function()
		local seen, t0 = false, os.clock()
		while true do
			task.wait(0.25)
			local st = state
			if st then
				seen = true
				if st.Preview then
					return
				end
				if player:GetAttribute("MatchStatus") ~= "Match" or Match:GetAttribute("Phase") ~= "Ended" then
					teardown()
					return
				end
			elseif seen or os.clock() - t0 > 5 then
				return
			end
		end
	end)
	local ok, err = pcall(run, res)
	if not ok then
		warn("[VANTAGE] results:", err)
		teardown(true)
	end
end

local last = Match:GetAttribute("Phase")
Match:GetAttributeChangedSignal("Phase"):Connect(function()
	local ph = Match:GetAttribute("Phase")
	if ph == "Ended" and last ~= "Ended" then
		task.spawn(onEnded)
	elseif ph ~= "Ended" and state and not state.Preview then
		teardown(ph ~= "Idle")
	end
	last = ph
end)
player:GetAttributeChangedSignal("MatchStatus"):Connect(function()
	if player:GetAttribute("MatchStatus") ~= "Match" and state and not state.Preview then
		teardown()
	end
end)

-- Studio preview: player attribute ResultsPreview = "Win" | "Loss" | "Draw" (sample rows around you)
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("ResultsPreview"):Connect(function()
		local v = player:GetAttribute("ResultsPreview")
		if v == nil then
			teardown(true)
			return
		end
		local mine = if player.Team and (player.Team.Name == "Blue" or player.Team.Name == "Red") then player.Team.Name else "Blue"
		local other = if mine == "Blue" then "Red" else "Blue"
		local winner = if v == "Win" then mine elseif v == "Loss" then other else "Draw"
		local rows = {}
		local W = Config.MVP
		local function add(u, n, t, k, d, a, hs, dmg)
			local r = { U = u, N = n, Name = n, T = t, K = k, D = d, A = a, HS = hs, Dmg = dmg, REQ = k * 100 + a * 40 + hs * 50, ORD = k * 5 + a * 2 + 40 + (if t == winner then 25 else 0), XP = k * 100 + a * 50 + hs * 25 + 250 + (if t == winner then 500 else 0) }
			r.R = math.floor(k * W.Kill + a * W.Assist + hs * W.Headshot + dmg * W.Damage + d * W.Death + 0.5)
			table.insert(rows, r)
		end
		add(player.UserId, player.DisplayName, mine, 14, 6, 5, 4, 2210)
		local names = { "KESTREL-7", "VOLT", "NOVA-3", "BRAVO-11", "HALCYON", "RAPTOR", "ECHO-9", "TALON", "CIPHER", "WRAITH-2", "ATLAS", "VIPER", "ORION", "SABLE", "DRIFT" }
		for i, n in names do
			add(-i, n, if i <= 7 then mine else other, math.random(2, 19), math.random(3, 14), math.random(0, 9), math.random(0, 6), math.random(400, 2900))
		end
		table.sort(rows, function(a, b)
			return a.R > b.R
		end)
		local mvp, top = nil, rows[1]
		for _, r in rows do
			if winner == "Draw" or r.T == winner then
				mvp = r
				break
			end
		end
		local res = { Mode = "TDM", Winner = winner, Reason = if winner == "Draw" then "TIME" else "SCORE", Blue = if winner == "Red" then 47 elseif winner == "Blue" then 60 else 52, Red = if winner == "Blue" then 47 elseif winner == "Red" then 60 else 52, Duration = 761, Overtime = false, MVP = mvp.U, Top = top.U, Rows = rows }
		local ok, err = pcall(run, res, true)
		if not ok then
			warn("[VANTAGE] results preview:", err)
		end
	end)
end

-- preload every results image (backdrop tiles, card art, reward icons) shortly after joining
task.delay(8, function()
	local list = {}
	local function add(id)
		local a = asset(id)
		if a ~= "" then
			local d = Instance.new("Decal")
			d.Texture = a
			table.insert(list, d)
		end
	end
	for _, v in (R.Art or {}) do
		if type(v) == "table" then
			for _, id in v do
				add(id)
			end
		else
			add(v)
		end
	end
	for _, c in (R.Cards or {}) do
		add(c.Bg)
		add(c.Fg)
	end
	for _, id in (R.Icons or {}) do
		add(id)
	end
	add(ReqIcon)
	add(OrdIcon)
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(list)
	end)
end)
