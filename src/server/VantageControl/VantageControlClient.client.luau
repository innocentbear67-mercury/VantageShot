--[[
	VANTAGE CONTROL — client radio + VEYRA comms bar (StarterPlayerScripts.VantageControlClient)
	Plays the lines the server sends this player (Remotes.VantageControl) plus #4 "Target
	eliminated" from Remotes.Elimination "Confirm" (sent by the server only to the credited killer).
	One voice at a time; critical lines (>= InterruptPriority) cut lower ones, others wait their turn
	(or drop if stale); the same line never repeats within its Cooldown. Every line also shows in the
	VEYRA bar, typed in step with the voice, held briefly, then faded. Critical lines get a red accent.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

if script.Parent and script.Parent.Name == "VantageControlHost" then
	local ps = player:FindFirstChildOfClass("PlayerScripts")
	if ps and ps:FindFirstChild("VantageControlClient") then
		return
	end
end

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Cfg = require(Vantage:WaitForChild("VantageControlConfig"))
local LINES = Cfg.Lines
local R = Cfg.Radio
local B = Cfg.Bar
local Remotes = Vantage:WaitForChild("Remotes")
local remote = Remotes:WaitForChild("VantageControl") :: RemoteEvent
local Match = Vantage:WaitForChild("Match")

local function log(...)
	if Cfg.Debug then
		print("[VANTAGE CONTROL]", ...)
	end
end

-- ─── radio channel ───────────────────────────────────────────────────────────
local group = SoundService:FindFirstChild("VantageControl") :: SoundGroup?
if not group then
	local g = Instance.new("SoundGroup")
	g.Name = "VantageControl"
	g.Volume = R.GroupVolume
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain, eq.MidGain, eq.HighGain = R.Equalizer.LowGain, R.Equalizer.MidGain, R.Equalizer.HighGain
	pcall(function()
		(eq :: any).MidRange = R.Equalizer.MidRange -- not available on every Studio build
	end)
	eq.Priority = 3
	eq.Parent = g
	local dist = Instance.new("DistortionSoundEffect")
	dist.Level = R.Distortion
	dist.Priority = 2
	dist.Parent = g
	local comp = Instance.new("CompressorSoundEffect")
	comp.Threshold, comp.Ratio = R.Compressor.Threshold, R.Compressor.Ratio
	comp.Attack, comp.Release, comp.GainMakeup = R.Compressor.Attack, R.Compressor.Release, R.Compressor.GainMakeup
	comp.Priority = 1
	comp.Parent = g
	g.Parent = SoundService
	group = g
end

local function attachDuck(g: Instance)
	if g:IsA("SoundGroup") and g ~= group and not g:FindFirstChild("VantageControlDuck") then
		local c = Instance.new("CompressorSoundEffect")
		c.Name = "VantageControlDuck"
		c.Threshold, c.Ratio, c.Attack, c.Release = R.Duck.Threshold, R.Duck.Ratio, R.Duck.Attack, R.Duck.Release
		pcall(function()
			c.SideChain = group
		end)
		c.Priority = 0
		c.Parent = g
	end
end
local duckNames = {}
for _, n in R.DuckGroups or {} do
	duckNames[n] = true
	local g = SoundService:FindFirstChild(n)
	if g then
		attachDuck(g)
	end
end
SoundService.ChildAdded:Connect(function(c)
	if duckNames[c.Name] then
		attachDuck(c)
	end
end)

-- ─── VEYRA comms bar ─────────────────────────────────────────────────────────
local function new(class: string, props, parent: Instance?)
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local bar = {} :: any
local PORTRAIT = B.Height
local GAP = 10
local PAD_X = 18

local function buildBar()
	local gui = new("ScreenGui", {
		Name = "VantageVeyraComms",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = B.DisplayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	local root = new("CanvasGroup", {
		Name = "Comms",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, B.Top),
		Size = UDim2.fromOffset(PORTRAIT + GAP + 300, B.Height),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, gui)
	local scale = new("UIScale", { Scale = 1 }, root)

	local tile = new("Frame", {
		Name = "Portrait",
		Size = UDim2.fromOffset(PORTRAIT, PORTRAIT),
		BackgroundColor3 = B.Background,
		BackgroundTransparency = B.BackgroundTransparency,
		BorderSizePixel = 0,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, tile)
	local tileStroke = new("UIStroke", { Color = B.Lime, Thickness = 1, Transparency = 0.7 }, tile)
	local img = new("ImageLabel", {
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
		Image = B.Portrait,
		ScaleType = Enum.ScaleType.Crop,
	}, tile)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, img)

	local panel = new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(PORTRAIT + GAP, 0),
		Size = UDim2.new(1, -(PORTRAIT + GAP), 1, 0),
		BackgroundColor3 = B.Background,
		BackgroundTransparency = B.BackgroundTransparency,
		BorderSizePixel = 0,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
	local stroke = new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.9 }, panel)
	local accent = new("Frame", {
		Name = "Accent",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(0, 3, 1, -20),
		BackgroundColor3 = B.Critical,
		BorderSizePixel = 0,
		Visible = false,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, accent)

	local label = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(PAD_X, 0),
		Size = UDim2.new(1, -PAD_X * 2, 1, 0),
		BackgroundTransparency = 1,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		FontFace = B.TextFont,
		TextSize = B.TextSize,
		TextColor3 = Color3.fromRGB(245, 247, 245),
		Text = "",
		MaxVisibleGraphemes = 0,
	}, panel)

	bar = { Gui = gui, Root = root, Scale = scale, Label = label, Stroke = stroke, TileStroke = tileStroke, Accent = accent, Token = 0 }
	pcall(ContentProvider.PreloadAsync, ContentProvider, { img })
end

local function viewScale(): number
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	return math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.62, 1.3)
end

local function barTop(k: number): number
	local y = B.Top * k
	-- in a match the comms bar sits low-centre, just above the ability tiles (the top-centre is the
	-- HS score bar + player row and the medal lane)
	local mh = player.PlayerGui:FindFirstChild("VantageHUD")
	local ab = mh and mh.Enabled and mh:FindFirstChild("Root") and mh.Root:FindFirstChild("Abilities")
	if ab and ab:IsA("GuiObject") and ab.Visible and ab.AbsoluteSize.Y > 0 then
		local inset = if mh.IgnoreGuiInset then 0 else game:GetService("GuiService"):GetGuiInset().Y
		return ab.AbsolutePosition.Y + inset - B.Height * k - 26 * k
	end
	local hud = player.PlayerGui:FindFirstChild("VantageMatchHud")
	local prep = hud and hud:FindFirstChild("Prep")
	if prep and prep:IsA("GuiObject") and prep.Visible and (not prep:IsA("CanvasGroup") or prep.GroupTransparency < 0.95) then
		y = math.max(y, prep.AbsolutePosition.Y + prep.AbsoluteSize.Y + B.PrepGap * k)
	end
	return y
end

local function measure(text: string, width: number): Vector2
	local ok, size = pcall(function()
		local p = Instance.new("GetTextBoundsParams")
		p.Text = text
		p.Font = B.TextFont
		p.Size = B.TextSize
		p.Width = width
		return TextService:GetTextBoundsAsync(p)
	end)
	if ok and size then
		return size
	end
	return Vector2.new(#text * B.TextSize * 0.48, B.TextSize)
end

local function showLine(line, duration: number)
	if not B.Enabled then
		return
	end
	if not bar.Root then
		buildBar()
	end
	bar.Token += 1
	local token = bar.Token
	local critical = line.Critical == true
	local tint = if critical then B.Critical else B.Lime

	local name = string.format('<font weight="bold" color="%s">%s:</font> ', hex(tint), B.Speaker)
	local plain = B.Speaker .. ": " .. line.Text
	bar.Label.Text = name .. line.Text
	local nameLen = utf8.len(B.Speaker .. ": ") or (#B.Speaker + 2)
	local total = utf8.len(plain) or #plain

	local maxText = B.MaxWidth - PORTRAIT - GAP - PAD_X * 2
	local bounds = measure(plain, maxText)
	local textW = math.min(bounds.X + 14, maxText)
	local h = math.max(B.Height, bounds.Y + 22)
	local k = viewScale()
	bar.Scale.Scale = k
	bar.Root.Size = UDim2.fromOffset(PORTRAIT + GAP + PAD_X * 2 + textW, h)
	bar.Root.Position = UDim2.new(0.5, 0, 0, barTop(k))
	bar.Accent.Visible = critical
	bar.Stroke.Color = if critical then B.Critical else Color3.new(1, 1, 1)
	bar.Stroke.Transparency = if critical then 0.55 else 0.9
	bar.TileStroke.Color = tint

	bar.Root.Visible = true
	TweenService:Create(bar.Root, TweenInfo.new(B.FadeIn, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
	if critical then
		bar.Stroke.Transparency = 0.1
		TweenService:Create(bar.Stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Transparency = 0.55 }):Play()
	end
	bar.Label.MaxVisibleGraphemes = nameLen
	local typeTime = math.max(0.35, duration * B.TypeShare)
	local chars = total - nameLen
	local start = os.clock()
	task.spawn(function()
		while bar.Token == token do
			local f = math.clamp((os.clock() - start) / typeTime, 0, 1)
			bar.Label.MaxVisibleGraphemes = nameLen + math.floor(chars * f + 0.5)
			if f >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function releaseLine()
	if not bar.Root then
		return
	end
	local token = bar.Token
	task.delay(0.05, function()
		if bar.Token == token then
			bar.Label.MaxVisibleGraphemes = -1
		end
	end)
	task.delay(B.Hold, function()
		if bar.Token ~= token then
			return
		end
		local tw = TweenService:Create(bar.Root, TweenInfo.new(B.FadeOut, Enum.EasingStyle.Quad), { GroupTransparency = 1 })
		tw:Play()
		tw.Completed:Once(function()
			if bar.Token == token then
				bar.Root.Visible = false
			end
		end)
	end)
end

-- ─── playback ────────────────────────────────────────────────────────────────
type Current = { Key: string, Priority: number, Sound: Sound? }
local current: Current? = nil
local pending: { Key: string, Priority: number, Expires: number }? = nil
local lastPlayed: { [string]: number } = {}
local warned: { [string]: boolean } = {}

local playPending

local function hasVoice(line): boolean
	return type(line.Id) == "string" and line.Id ~= ""
end

local function speaking(): boolean
	return current ~= nil
end

local function stopCurrent(fade: boolean)
	local c = current
	current = nil
	local s = c and c.Sound
	if not s then
		return
	end
	if fade and s.IsPlaying then
		TweenService:Create(s, TweenInfo.new(R.FadeOut), { Volume = 0 }):Play()
		task.delay(R.FadeOut + 0.02, function()
			s:Destroy()
		end)
	else
		s:Destroy()
	end
end

local function squelch()
	local q = R.Squelch
	if not q or not q.Enabled then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "VantageControl_Squelch"
	s.SoundId = q.Id
	s.Volume = q.Volume
	s.PlaybackSpeed = q.Speed
	s.SoundGroup = group
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(2, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function play(key: string)
	local line = LINES[key]
	if current then
		log("CUT", current.Key, "for", key)
	end
	stopCurrent(true)
	log("PLAY", key, line.Text)
	lastPlayed[key] = os.clock()
	if line.Priority >= Cfg.InterruptPriority then
		pending = nil
	end
	local me: Current = { Key = key, Priority = line.Priority, Sound = nil }
	current = me
	local textLen = utf8.len(line.Text) or #line.Text

	local function finished()
		if current == me then
			current = nil
			if me.Sound then
				me.Sound:Destroy()
			end
			releaseLine()
			task.delay(0.15, playPending)
		end
	end

	if not hasVoice(line) then
		local dur = math.max(1.2, textLen * B.CharTime)
		showLine(line, dur)
		task.delay(dur, finished)
		return
	end

	local s = Instance.new("Sound")
	s.Name = "VantageControl_" .. key
	s.SoundId = line.Id
	s.Volume = R.Volume
	s.SoundGroup = group
	s.Parent = SoundService
	me.Sound = s
	squelch()
	s.Ended:Once(finished)
	local lead = if R.Squelch and R.Squelch.Enabled then R.Squelch.Lead else 0
	task.spawn(function()
		if not s.IsLoaded then
			local t0 = os.clock()
			while not s.IsLoaded and os.clock() - t0 < 0.35 and current == me do
				task.wait()
			end
		end
		if current ~= me then
			return
		end
		local dur = if s.TimeLength > 0 then s.TimeLength else textLen * B.CharTime
		task.wait(lead)
		if current ~= me then
			return
		end
		s:Play()
		showLine(line, dur)
		task.delay(dur + 1.5, function()
			if current == me then
				finished()
			end
		end)
	end)
end

function playPending()
	local p = pending
	pending = nil
	if p and os.clock() > p.Expires then
		log("DROP", p.Key, "(waited too long)")
		return
	end
	if p and not speaking() then
		local cd = LINES[p.Key].Cooldown or 0
		if not (lastPlayed[p.Key] and os.clock() - lastPlayed[p.Key] < cd) then
			play(p.Key)
		end
	end
end

local COMBAT = { Contact = true, Kill = true, ShieldCritical = true, ShieldFail = true, ShieldRestored = true, Losing = true }

local function request(key: string, sentAt: number?, test: boolean?)
	local line = LINES[key]
	if not line then
		return
	end
	if not hasVoice(line) and not warned[key] then
		warned[key] = true
		warn(("[VANTAGE CONTROL] %s has no voice asset Id yet (VantageControlConfig) — showing text only"):format(key))
	end
	-- 2026-11-17: Hypershot has no radio / announcer voice in a match: VEYRA stays silent once you
	-- leave the lobby (VantageControlConfig.MatchComms = true brings her back)
	if not test and Cfg.MatchComms ~= true and (player:GetAttribute("InLobby") == false or player:GetAttribute("MatchStatus") == "Match" or Match:GetAttribute("Phase") == "Live") then
		return log("DROP", key, "(match comms off)")
	end
	if COMBAT[key] and not test and Match:GetAttribute("Phase") ~= "Live" then
		return log("DROP", key, "(not live)")
	end
	if sentAt and Workspace:GetServerTimeNow() - sentAt > (line.MaxDelay or 2) then
		return log("DROP", key, "(stale)")
	end
	local t = os.clock()
	if lastPlayed[key] and t - lastPlayed[key] < (line.Cooldown or 0) then
		return log("DROP", key, "(duplicate)")
	end
	if current and current.Key == key then
		return log("DROP", key, "(already speaking)")
	end
	if not speaking() then
		play(key)
	elseif line.Priority >= Cfg.InterruptPriority and line.Priority > (current :: Current).Priority then
		play(key)
	elseif not pending or line.Priority >= pending.Priority then
		if not pending or pending.Key ~= key then
			log("WAIT", key, "behind", (current :: Current).Key)
			pending = { Key = key, Priority = line.Priority, Expires = t + (line.MaxDelay or 2) }
		end
	else
		log("DROP", key, "(lower than waiting", pending.Key .. ")")
	end
end

remote.OnClientEvent:Connect(function(key: any, sentAt: any, test: any)
	if type(key) == "string" then
		request(key, if type(sentAt) == "number" then sentAt else nil, test == true)
	end
end)

Remotes:WaitForChild("Elimination").OnClientEvent:Connect(function(kind: any)
	if kind == "Confirm" then
		request("Kill", nil)
	end
end)

Match:GetAttributeChangedSignal("MatchId"):Connect(function()
	pending = nil
end)

task.spawn(function()
	if B.Enabled then
		buildBar()
	end
	local list = {}
	for _, line in LINES do
		if hasVoice(line) then
			local s = Instance.new("Sound")
			s.SoundId = line.Id
			table.insert(list, s)
		end
	end
	if #list > 0 then
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end
end)
