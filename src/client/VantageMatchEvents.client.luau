--[[
	VANTAGE — VantageMatchEvents (client, 2026-11-18)
	The match "comes alive" layer. Everything it shows comes from server state:
	  * announcement lane, top-centre UNDER the score box (never near the crosshair), one at a time
	    with priorities: OVERTIME / MATCH POINT > FIRST BLOOD > your streak > score + time warnings
	    > other players' streaks > level up
	      - FIRST BLOOD and streaks: KillFeed remote fields FirstBlood / Streak (EliminationService)
	      - score / time warnings + overtime: Match attributes (MatchService)
	      - level up: player attribute LevelUp (Progression)
	  * last 10 seconds: a soft tick each second (the HUD timer already pops)
	  * your death: a low thud; REDEPLOYING countdown low-centre from the server's RespawnAt
	  * respawn: short cyan edge flash + "REDEPLOYED"
	Tuning: MatchConfig.Streaks / ScoreWarnings / TimeWarnings / Sounds.
	Creates only its own ScreenGui "VantageMatchEvents".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("MatchConfig"))
local Match = Vantage:WaitForChild("Match")
local FeedRemote = Vantage:WaitForChild("Remotes"):WaitForChild("KillFeed") :: RemoteEvent

local C = Color3.fromRGB
local WHITE = C(245, 248, 255)
local GOLD = C(255, 205, 70)
local BLUE = C(70, 160, 255)
local RED = C(255, 70, 96)
local GREEN = C(110, 236, 120)
local CYAN = C(90, 220, 255)
local INK = C(6, 9, 18)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local O = UDim2.fromOffset
local V2 = Vector2.new

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
local function cue(name: string, speedMul: number?, volMul: number?)
	local spec = Config.Sounds[name]
	if not spec then
		return
	end
	local s = new("Sound", { SoundId = spec.Id, Volume = spec.Volume * (volMul or 1), PlaybackSpeed = (spec.Speed or 1) * (speedMul or 1) })
	local g = SoundService:FindFirstChild("VantageEffects")
	if g and g:IsA("SoundGroup") then
		s.SoundGroup = g
	end
	s.Parent = SoundService
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end
local function teamColor(t: string?): Color3
	return if t == "Blue" then BLUE elseif t == "Red" then RED else WHITE
end
local function myTeam(): string?
	return if player.Team and not player.Neutral then player.Team.Name else nil
end
local function inMatch(): boolean
	return player:GetAttribute("MatchStatus") == "Match"
end
local function live(): boolean
	return inMatch() and Match:GetAttribute("Phase") == "Live"
end

-- ─── screen ──────────────────────────────────────────────────────────────────────────────
local gui = new("ScreenGui", { Name = "VantageMatchEvents", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local root = new("Frame", { Name = "Root", AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = O(1920, 1080), BackgroundTransparency = 1 }, gui)
local uiScale = new("UIScale", {}, root)
local function fit()
	local vs = (Workspace.CurrentCamera :: Camera).ViewportSize
	uiScale.Scale = math.min(vs.X / 1920, vs.Y / 1080)
end
fit()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, TextColor3 = WHITE, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center }, parent)
	local strokeT = props.StrokeT
	props.StrokeT = nil
	for k, v in props do
		t[k] = v
	end
	new("UIStroke", { Color = INK, Thickness = strokeT or 3, LineJoinMode = Enum.LineJoinMode.Round }, t)
	return t
end

-- ─── announcement lane ───────────────────────────────────────────────────────────────────────
-- y 262 (1080 design): just below the HUD score box + player row, far above the crosshair
local LANE_Y = 262
local queue = {}
local busy = false
local PRI = { Overtime = 100, MatchPoint = 95, FirstBlood = 80, MyStreak = 70, Warning = 60, Streak = 40, Level = 30 }

local function showBanner(a)
	local big = a.Big ~= false
	local w = if big then 640 else 520
	local h = if big then 92 else 54
	local grp = new("CanvasGroup", { Name = "Announce", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, LANE_Y), Size = O(w, h), BackgroundTransparency = 1, GroupTransparency = 1 }, root)
	local sc = new("UIScale", { Scale = 1.28 }, grp)
	-- slanted dark plate with an accent edge on both ends (HUD v5 "para" language)
	local plate = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -40, 1, -18), BackgroundColor3 = C(10, 14, 30), BackgroundTransparency = 0.18, BorderSizePixel = 0, Rotation = 0 }, grp)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, plate)
	-- tinted glass: accent at the ends fading to deep navy in the middle, top gloss, light streaks
	local tintC = C(10, 14, 30):Lerp(a.Color, 0.45)
	new("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, tintC), ColorSequenceKeypoint.new(0.3, C(12, 18, 40)), ColorSequenceKeypoint.new(0.7, C(12, 18, 40)), ColorSequenceKeypoint.new(1, tintC) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.16, 0), NumberSequenceKeypoint.new(0.84, 0), NumberSequenceKeypoint.new(1, 0.85) }),
	}, plate)
	plate.BackgroundColor3 = Color3.new(1, 1, 1)
	local gloss = new("Frame", { Size = UDim2.new(1, 0, 0.48, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.86, BorderSizePixel = 0 }, plate)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, gloss)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1) }, gloss)
	for i, d in { 0.12, 0.75 } do
		local s = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(-0.2, 0.5), Size = UDim2.new(0, if i == 1 then 70 else 30, 3, 0), Rotation = 24, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72, BorderSizePixel = 0 }, plate)
		tween(s, 0.55, { Position = UDim2.fromScale(1.2, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, d)
	end
	local line = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0.7, 0, 0, 3), BackgroundColor3 = a.Color, BorderSizePixel = 0 }, plate)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, line)
	local title = label(grp, { Position = O(0, if big then 6 else 4), Size = UDim2.new(1, 0, 0, if big then 50 else 30), Text = a.Title, TextSize = if big then 46 else 28, TextColor3 = a.Color, StrokeT = if big then 4 else 3 })
	if a.Sub and a.Sub ~= "" then
		label(grp, { Position = O(0, if big then 54 else 32), Size = UDim2.new(1, 0, 0, if big then 26 else 18), Text = a.Sub, TextSize = if big then 22 else 16, TextColor3 = WHITE, StrokeT = 2.5 })
	end
	-- a light sweep across the title
	local sweep = new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.55, 0), NumberSequenceKeypoint.new(1, 0) }), Offset = V2(-1, 0) }, title)
	sweep.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.42, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, C(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) })
	tween(grp, 0.14, { GroupTransparency = 0 }, Enum.EasingStyle.Quad)
	tween(sc, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(line, 0.5, { Size = UDim2.new(0.92, 0, 0, 3) }, Enum.EasingStyle.Quint)
	if a.Sound then
		cue(a.Sound, a.SoundSpeed)
	end
	local hold = a.Hold or 1.7
	task.wait(hold)
	tween(grp, 0.25, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0, LANE_Y - 14) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.18) -- the next one may start while this fades
	task.delay(0.2, function()
		grp:Destroy()
	end)
end

local function pump()
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		while #queue > 0 do
			table.sort(queue, function(a, b)
				if a.P ~= b.P then
					return a.P > b.P
				end
				return a.T < b.T
			end)
			local a = table.remove(queue, 1)
			-- stale low-priority items are dropped instead of piling up
			if os.clock() - a.T < (a.TTL or 4) and inMatch() then
				local ok, err = pcall(showBanner, a)
				if not ok then
					warn("[VANTAGE] match events:", err)
				end
			end
		end
		busy = false
	end)
end

local function announce(kind: string, a)
	a.P = PRI[kind] or 10
	a.T = os.clock()
	-- one of each kind at a time: a newer one replaces an older queued one
	for i = #queue, 1, -1 do
		if queue[i].Kind == kind then
			table.remove(queue, i)
		end
	end
	a.Kind = kind
	table.insert(queue, a)
	if #queue > 4 then
		table.sort(queue, function(x, y)
			return x.P > y.P
		end)
		queue[#queue] = nil
	end
	pump()
end

-- ─── kill feed: first blood + streaks ─────────────────────────────────────────────────────────────
FeedRemote.OnClientEvent:Connect(function(e)
	if type(e) ~= "table" or not live() or type(e.Killer) ~= "table" then
		return
	end
	local k = e.Killer
	local mine = k.UserId == player.UserId
	local name = string.upper(tostring(k.Name or ""))
	if e.FirstBlood then
		announce("FirstBlood", { Title = "FIRST BLOOD", Sub = if mine then "You drew first blood" else name .. " drew first blood", Color = if mine then GOLD else teamColor(k.Team), Sound = "Callout", SoundSpeed = 0.9, Hold = 1.8 })
	end
	local title = type(e.Streak) == "number" and Config.Streaks[e.Streak]
	if title then
		if mine then
			announce("MyStreak", { Title = title, Sub = e.Streak .. " ELIMINATIONS WITHOUT DYING", Color = GOLD, Sound = "Callout", SoundSpeed = 1 + math.min(e.Streak, 15) * 0.02, Hold = 1.6 })
		else
			announce("Streak", { Big = false, Title = name .. " — " .. title, Sub = e.Streak .. " streak", Color = teamColor(k.Team), Hold = 1.4, TTL = 2.5 })
		end
	end
end)

-- ─── score + time warnings, overtime ───────────────────────────────────────────────────────────────
local said = {} -- per match: which warnings already played
local saidMatch = nil
local function resetSaid()
	local id = Match:GetAttribute("MatchId")
	if id ~= saidMatch then
		saidMatch = id
		said = {}
	end
end
local function onScore(team: string)
	resetSaid()
	if not live() then
		return
	end
	local limit = Match:GetAttribute("ScoreLimit") or 0
	local score = Match:GetAttribute(team .. "Score") or 0
	local need = limit - score
	if need <= 0 or limit <= 0 then
		return
	end
	for _, n in Config.ScoreWarnings do
		local key = team .. n
		if need <= n and not said[key] then
			said[key] = true
			-- mark the larger thresholds too (a jump from 11 to 4 plays only one line)
			for _, m in Config.ScoreWarnings do
				if m >= n then
					said[team .. m] = true
				end
			end
			local ours = team == myTeam()
			if n == 1 then
				announce("MatchPoint", { Title = "MATCH POINT", Sub = if ours then "One more elimination wins it" else "The enemy is one elimination from victory", Color = teamColor(team), Sound = "Warn", SoundSpeed = if ours then 1.25 else 0.9, Hold = 1.8, TTL = 3 })
			else
				announce("Warning", { Big = false, Title = if ours then n .. " ELIMINATIONS TO VICTORY" else "ENEMY NEEDS " .. n .. " ELIMINATIONS", Color = teamColor(team), Sound = "Warn", SoundSpeed = if ours then 1.15 else 0.85, Hold = 1.6, TTL = 3 })
			end
			break
		end
	end
end
Match:GetAttributeChangedSignal("BlueScore"):Connect(function()
	onScore("Blue")
end)
Match:GetAttributeChangedSignal("RedScore"):Connect(function()
	onScore("Red")
end)
Match:GetAttributeChangedSignal("Overtime"):Connect(function()
	if Match:GetAttribute("Overtime") == true and live() then
		announce("Overtime", { Title = "OVERTIME", Sub = "SUDDEN DEATH — next elimination wins", Color = GOLD, Sound = "Warn", SoundSpeed = 0.7, Hold = 2.6, TTL = 4 })
	end
end)

local lastSec = -1
RunService.Heartbeat:Connect(function()
	if not live() or Match:GetAttribute("Overtime") == true then
		lastSec = -1
		return
	end
	resetSaid()
	local left = Match:GetAttribute("TimeLeft")
	if type(left) ~= "number" then
		return
	end
	local sec = math.ceil(left)
	if sec == lastSec then
		return
	end
	lastSec = sec
	for _, t in Config.TimeWarnings do
		if sec == t and not said["T" .. t] then
			said["T" .. t] = true
			local txt = if t >= 120 then (t // 60) .. " MINUTES REMAINING" elseif t >= 60 then "1 MINUTE REMAINING" else t .. " SECONDS REMAINING"
			announce("Warning", { Big = false, Title = txt, Color = if t <= 60 then C(255, 150, 160) else WHITE, Sound = "Warn", Hold = 1.6, TTL = 2 })
		end
	end
	if sec <= 10 and sec >= 1 then
		cue("Tick", 1 + (10 - sec) * 0.03, 0.9)
	end
end)

-- ─── level up (Progression) ─────────────────────────────────────────────────────────────────────────────────
player:GetAttributeChangedSignal("LevelUp"):Connect(function()
	local lv = player:GetAttribute("LevelUp")
	if live() and type(lv) == "number" then
		announce("Level", { Big = false, Title = "LEVEL " .. lv, Sub = "Account level up", Color = GREEN, Sound = "Reward", SoundSpeed = 0.8, Hold = 1.6, TTL = 6 })
	end
end)

-- ─── death → redeploy countdown → respawn feedback ────────────────────────────────────────────────────────
local rs = new("CanvasGroup", { Name = "Redeploy", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 760), Size = O(420, 64), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, root)
local rsText = label(rs, { Size = UDim2.new(1, 0, 0, 34), Text = "REDEPLOYING IN 3", TextSize = 30 })
local rsTrack = new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 42), Size = O(300, 8), BackgroundColor3 = C(16, 22, 44), BorderSizePixel = 0 }, rs)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, rsTrack)
new("UIStroke", { Color = INK, Thickness = 2 }, rsTrack)
local rsFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, rsTrack)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, rsFill)

local deadSince: number? = nil
local deadConn: RBXScriptConnection? = nil
local function hideRedeploy()
	deadSince = nil
	if deadConn then
		deadConn:Disconnect()
		deadConn = nil
	end
	if rs.Visible then
		tween(rs, 0.15, { GroupTransparency = 1 })
		task.delay(0.16, function()
			if not deadSince then
				rs.Visible = false
			end
		end)
	end
end
local function onDied()
	if not live() then
		return
	end
	cue("Defeat", 1.6, 0.45) -- a low, short thud (not the defeat sting: same sub boom, faster, quieter)
	deadSince = Workspace:GetServerTimeNow()
	-- after the elimination card has had its moment
	task.delay(0.9, function()
		if not deadSince or not live() then
			return
		end
		rs.Visible = true
		tween(rs, 0.2, { GroupTransparency = 0 })
	end)
	if deadConn then
		deadConn:Disconnect()
	end
	deadConn = RunService.RenderStepped:Connect(function()
		if not deadSince then
			return
		end
		local at = tonumber(player:GetAttribute("RespawnAt")) or (deadSince + Players.RespawnTime)
		local total = math.max(0.1, at - deadSince)
		local left = at - Workspace:GetServerTimeNow()
		if left > 0 then
			rsText.Text = string.format("REDEPLOYING IN %.1f", left)
			rsFill.Size = UDim2.fromScale(1 - left / total, 1)
		else
			rsText.Text = "REDEPLOYING" .. string.rep(".", 1 + math.floor(os.clock() * 3) % 3)
			rsFill.Size = UDim2.fromScale(1, 1)
		end
	end)
end

-- respawn: a short cyan edge flash + REDEPLOYED (never on the match's first spawn)
-- drawn edge glow: four gradient bands fading toward the centre (no image asset needed)
local edge = new("CanvasGroup", { Name = "RespawnEdge", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1 }, gui)
for _, e in { { V2(0, 0), UDim2.new(1, 0, 0.16, 0), 90 }, { V2(0, 1), UDim2.new(1, 0, 0.16, 0), -90 }, { V2(0, 0), UDim2.new(0.12, 0, 1, 0), 0 }, { V2(1, 0), UDim2.new(0.12, 0, 1, 0), 180 } } do
	local f = new("Frame", { AnchorPoint = e[1], Position = UDim2.fromScale(e[1].X, e[1].Y), Size = e[2], BackgroundColor3 = CYAN, BorderSizePixel = 0 }, edge)
	new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, f)
end
local function onRespawn()
	hideRedeploy()
	edge.GroupTransparency = 0.3
	tween(edge, 0.9, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
	cue("Respawn")
	local t = label(root, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 760), Size = O(420, 34), Text = "REDEPLOYED", TextSize = 28, TextColor3 = CYAN })
	local s = new("UIScale", { Scale = 1.3 }, t)
	tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(t, 0.4, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.9)
	task.delay(1.4, function()
		t:Destroy()
	end)
end

local hadDeath = false
local function hookCharacter(c: Model)
	if hadDeath and live() then
		onRespawn()
	else
		hideRedeploy()
	end
	hadDeath = false
	local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.Died:Once(function()
			hadDeath = true
			onDied()
		end)
	end
end
player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	task.spawn(hookCharacter, player.Character)
end

-- leaving the match / results: clear everything
local function clear()
	table.clear(queue)
	hideRedeploy()
	for _, c in root:GetChildren() do
		if c.Name == "Announce" then
			c:Destroy()
		end
	end
end
Match:GetAttributeChangedSignal("Phase"):Connect(function()
	if Match:GetAttribute("Phase") ~= "Live" then
		clear()
		hadDeath = false
	end
end)
player:GetAttributeChangedSignal("MatchStatus"):Connect(function()
	if not inMatch() then
		clear()
	end
end)
