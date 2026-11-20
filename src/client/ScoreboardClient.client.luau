--[[
	VANTAGE — ScoreboardClient (StarterPlayer.StarterPlayerScripts.ScoreboardClient)
	  1. Hold-Tab scoreboard ("match intelligence" display; touch: SCORES toggle button) while in a
	     match during Prep / Countdown / Live. Does nothing while the main menu, armory or settings
	     are open (their ScreenGuis are Enabled), so MainMenu's own Tab (-> Modes) is never doubled up.
	  2. Post-match debrief: ResultsDelay after Phase "Ended", placed under MatchHud's VICTORY /
	     DEFEAT banner, slides out before Ended finishes. Never takes input.
	Data: MatchStats_* player attributes (MatchStatsServer) + ReplicatedStorage.Vantage.Match.
	Look: ScoreboardTheme. Flow / keys / timings: ScoreboardConfig.
	Creates only its own ScreenGui "ScoreboardGui".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("ScoreboardConfig"))
local Theme = require(Vantage:WaitForChild("ScoreboardTheme"))
local Match = Vantage:WaitForChild("Match")

local T, F, A = Theme.C, Theme.F, Theme.Anim
local BD, RD = Theme.Board, Theme.Results
local O = UDim2.fromOffset
local V2 = Vector2.new
local AX = Enum.TextXAlignment
local NS, KP = NumberSequence.new, NumberSequenceKeypoint.new
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local TEAMS = { "Blue", "Red" }

-- ─── helpers ───────────────────────────────────────────────────────────────────────────
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function tween(inst: Instance, t: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

-- letter-spacing via hair spaces (Roblox text has no tracking), as LimeKit does
local HAIR = utf8.char(0x200A)
local function spaced(s: string, n: number?): string
	local gap = string.rep(HAIR, n or 1)
	local out = {}
	for _, cp in utf8.codes(s) do
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out, gap)
end

local function text(parent: Instance, props): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextColor3 = T.Text,
		FontFace = F.Name,
		TextSize = 16,
		TextXAlignment = AX.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	for k, v in props do
		l[k] = v
	end
	-- monospace glyphs are already wide and draw a hair space at full width: no tracking (as LimeKit)
	if string.find(l.FontFace.Family, "RobotoMono", 1, true) then
		local function strip()
			if string.find(l.Text, HAIR, 1, true) then
				l.Text = string.gsub(l.Text, HAIR, "")
			end
		end
		strip()
		l:GetPropertyChangedSignal("Text"):Connect(strip)
	end
	return l
end

local function rect(parent: Instance, props): Frame
	local f = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = T.Line, BackgroundTransparency = 0 }, parent)
	for k, v in props do
		f[k] = v
	end
	return f
end

-- thin line that fades out at both ends ("illuminated divider")
local function divider(parent: Instance, props, t: number?)
	local d = rect(parent, props)
	d.BackgroundTransparency = t or 0.55
	new("UIGradient", { Transparency = NS({ KP(0, 1), KP(0.18, 0), KP(0.82, 0), KP(1, 1) }) }, d)
	return d
end

-- HUD framing: lime L-ticks on the top-left and bottom-right corners (LimeKit's glass ticks)
local function brackets(parent: Instance, color: Color3?, len: number?)
	local c, L = color or T.Lime, len or 12
	rect(parent, { Name = "TickTL1", Size = O(L, 2), BackgroundColor3 = c, BackgroundTransparency = 0.05, ZIndex = 6 })
	rect(parent, { Name = "TickTL2", Size = O(2, L), BackgroundColor3 = c, BackgroundTransparency = 0.05, ZIndex = 6 })
	rect(parent, { Name = "TickBR1", AnchorPoint = V2(1, 1), Position = UDim2.fromScale(1, 1), Size = O(L, 1), BackgroundColor3 = c, BackgroundTransparency = 0.4, ZIndex = 6 })
	rect(parent, { Name = "TickBR2", AnchorPoint = V2(1, 1), Position = UDim2.fromScale(1, 1), Size = O(1, L), BackgroundColor3 = c, BackgroundTransparency = 0.4, ZIndex = 6 })
end

--[[ glass(parent, o): layered translucent navy panel
	o.Name, o.Position, o.Size, o.Anchor
	o.Fill (colour), o.FillT (transparency), o.Shade (bottom darkening 0..1)
	o.EdgeT (hairline), o.LightT (top edge light), o.Shadow (drop shadow), o.Brackets
	returns root, fill, stroke ]]
local function glass(parent: Instance, o)
	local root = new("Frame", {
		Name = o.Name or "Glass",
		Position = o.Position or O(0, 0),
		Size = o.Size,
		AnchorPoint = o.Anchor or V2(0, 0),
		BackgroundTransparency = 1,
	}, parent)
	if o.Shadow then
		-- depth: a soft obsidian slab under the panel, offset down
		local sh = rect(root, { Name = "Shadow", Position = O(-2, 3), Size = UDim2.new(1, 4, 1, 5), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.45, ZIndex = 0 })
		new("UIGradient", { Rotation = 90, Transparency = NS({ KP(0, 0.7), KP(1, 0.1) }) }, sh)
	end
	local fill = rect(root, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = o.Fill or T.Glass, BackgroundTransparency = o.FillT or 0.18 })
	local shade = o.Shade or 0.35
	-- controlled vertical gradient: lit at the top, settling darker at the bottom
	new("UIGradient", { Rotation = 90, Color = CS({ CK(0, Color3.new(1, 1, 1)), CK(1, Color3.new(1 - shade, 1 - shade, 1 - shade * 0.8)) }) }, fill)
	local stroke = new("UIStroke", { Color = T.Line, Transparency = o.EdgeT or 0.84, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, fill)
	-- edge light along the top
	local light = rect(root, { Name = "EdgeLight", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Line, BackgroundTransparency = o.LightT or 0.45, ZIndex = 3 })
	new("UIGradient", { Transparency = NS({ KP(0, 1), KP(0.12, 0), KP(0.88, 0), KP(1, 1) }) }, light)
	if o.Brackets then
		brackets(root, o.BracketColor)
	end
	return root, fill, stroke
end

local function num(v: any): number
	return if type(v) == "number" then v else 0
end

local function teamColor(t: string?): Color3
	return if t == "Blue" then T.Blue elseif t == "Red" then T.Red else T.Draw
end

local function fmtTime(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function kdText(k: number, d: number): string
	return string.format("%.2f", if d == 0 then k else k / d)
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- ─── thumbnails ────────────────────────────────────────────────────────────────────────
local thumbs: { [number]: string } = {}
local function thumbFor(userId: number, image: ImageLabel)
	if userId <= 0 then
		image.Image = ""
		return
	end
	if thumbs[userId] then
		image.Image = thumbs[userId]
		return
	end
	thumbs[userId] = "" -- fetch once
	task.spawn(function()
		local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and url then
			thumbs[userId] = url
			if image.Parent then
				image.Image = url
			end
		end
	end)
end

-- ─── match state ───────────────────────────────────────────────────────────────────────
local function phase(): string
	return Match:GetAttribute("Phase") or "Idle"
end

local function matchPlayers(): { Player }
	local id = Match:GetAttribute("MatchId")
	local list = {}
	if not id or id == 0 then
		return list
	end
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("MatchId") == id and p.Team and (p.Team.Name == "Blue" or p.Team.Name == "Red") then
			table.insert(list, p)
		end
	end
	return list
end

local function stats(p: Player)
	return {
		K = num(p:GetAttribute("MatchStats_Kills")),
		D = num(p:GetAttribute("MatchStats_Deaths")),
		HS = num(p:GetAttribute("MatchStats_Headshots")),
		Score = num(p:GetAttribute("MatchStats_Score")),
	}
end

local function sortByScore(a: Player, b: Player): boolean
	local sa, sb = stats(a), stats(b)
	if sa.Score ~= sb.Score then
		return sa.Score > sb.Score
	elseif sa.K ~= sb.K then
		return sa.K > sb.K
	elseif sa.D ~= sb.D then
		return sa.D < sb.D
	end
	return a.DisplayName < b.DisplayName
end

local function menuOpen(): boolean
	for _, name in Config.MenuGuis do
		local g = playerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") and g.Enabled then
			return true
		end
	end
	return false
end

local function boardAllowed(): boolean
	return player:GetAttribute("MatchStatus") == "Match" and Config.ScoreboardPhases[phase()] == true and not menuOpen()
end

-- ─── gui ───────────────────────────────────────────────────────────────────────────────
local old = playerGui:FindFirstChild("ScoreboardGui")
if old then
	old:Destroy()
end
local gui = new("ScreenGui", {
	Name = "ScoreboardGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = Config.DisplayOrder,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- ═══ SCOREBOARD ════════════════════════════════════════════════════════════════════════
local INSET = 8 -- columns sit inside the roster panel
local CW = (BD.W - INSET * 2 - BD.Gap) / 2 -- column width
local STAT_W = 0
for _, c in BD.Stats do
	STAT_W += c[3]
end
local RANK_W, AV = 38, 34
local AV_X = RANK_W + 8
local NAME_X = AV_X + AV + 12
local NAME_W = CW - NAME_X - STAT_W - 14

local BOARD_POS = UDim2.fromScale(0.5, 0.5)
local board = new("CanvasGroup", {
	Name = "ScoreboardBoard",
	AnchorPoint = V2(0.5, 0.5),
	Position = BOARD_POS,
	Size = O(BD.W, 400),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
}, gui)
local boardScale = new("UIScale", { Name = "ScoreboardScale" }, board)

-- ── header: team scores | match intelligence | team scores ──
local header = glass(board, { Name = "ScoreboardHeader", Size = O(BD.W, BD.Header), FillT = 0.1, Shade = 0.45, Shadow = true, Brackets = true })
local hdr = {}
for _, team in TEAMS do
	local left = team == "Blue"
	local c = teamColor(team)
	-- team edge: a slim coloured spine with a soft glow into the panel
	rect(header, { Name = team .. "Spine", AnchorPoint = V2(if left then 0 else 1, 0), Position = UDim2.fromScale(if left then 0 else 1, 0), Size = O(3, BD.Header), BackgroundColor3 = c, ZIndex = 4 })
	local glow = rect(header, { Name = team .. "Glow", AnchorPoint = V2(if left then 0 else 1, 0), Position = UDim2.fromScale(if left then 0 else 1, 0), Size = O(220, BD.Header), BackgroundColor3 = c, BackgroundTransparency = 0.82, ZIndex = 2 })
	new("UIGradient", { Rotation = if left then 0 else 180, Transparency = NS({ KP(0, 0.2), KP(1, 1) }) }, glow)
	local x = if left then 26 else -26
	local anchorX = if left then 0 else 1
	local align = if left then AX.Left else AX.Right
	text(header, { Name = team .. "Label", AnchorPoint = V2(anchorX, 0), Position = UDim2.new(anchorX, x, 0, 16), Size = O(320, 16), Text = spaced(string.upper(team) .. " TEAM", 2), FontFace = F.MonoB, TextSize = 13, TextColor3 = c, TextXAlignment = align, ZIndex = 4 })
	hdr[team] = {
		Score = text(header, { Name = team .. "Score", AnchorPoint = V2(anchorX, 0), Position = UDim2.new(anchorX, x - (if left then 3 else -3), 0, 30), Size = O(220, 62), Text = "0", FontFace = F.Head, TextSize = 64, TextColor3 = T.Text, TextXAlignment = align, ZIndex = 4 }),
		Meta = text(header, { Name = team .. "Meta", AnchorPoint = V2(anchorX, 0), Position = UDim2.new(anchorX, x, 0, 92), Size = O(320, 14), Text = "", FontFace = F.Mono, TextSize = 11, TextColor3 = T.TextDim, TextXAlignment = align, ZIndex = 4 }),
	}
end
-- centre: match intelligence
text(header, { Name = "IntelTag", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = O(560, 14), Text = spaced("MATCH  INTELLIGENCE", 3), FontFace = F.MonoM, TextSize = 11, TextColor3 = T.Lime, TextXAlignment = AX.Center, ZIndex = 4 })
local modeLabel = text(header, { Name = "Mode", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = O(560, 26), Text = "", FontFace = F.Head6, TextSize = 24, TextXAlignment = AX.Center, ZIndex = 4 })
local clock = rect(header, { Name = "Clock", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = O(196, 38), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.25, ZIndex = 4 })
new("UIStroke", { Color = T.Line, Transparency = 0.78, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, clock)
rect(clock, { Name = "ClockLight", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Line, BackgroundTransparency = 0.6, ZIndex = 5 })
local liveDot = rect(clock, { Name = "Dot", AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = O(8, 8), BackgroundColor3 = T.Lime, ZIndex = 5 })
new("UICorner", { CornerRadius = UDim.new(1, 0) }, liveDot)
local phaseLabel = text(clock, { Name = "Phase", Position = O(30, 0), Size = O(80, 38), Text = "LIVE", FontFace = F.MonoB, TextSize = 12, TextColor3 = T.Lime, ZIndex = 5 })
local timeLabel = text(clock, { Name = "Time", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = O(96, 38), Text = "0:00", FontFace = F.MonoB, TextSize = 24, TextXAlignment = AX.Right, ZIndex = 5 })
local pulse = TweenService:Create(liveDot, TweenInfo.new(A.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.75 })
-- score-limit progress: blue grows from the left, red from the right
local track = rect(header, { Name = "LimitTrack", AnchorPoint = V2(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.2, ZIndex = 4 })
local blueBar = rect(track, { Name = "BlueBar", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.Blue, ZIndex = 5 })
local redBar = rect(track, { Name = "RedBar", AnchorPoint = V2(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.Red, ZIndex = 5 })
rect(track, { Name = "Mid", AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = O(2, 3), BackgroundColor3 = T.Line, BackgroundTransparency = 0.3, ZIndex = 6 })

-- ── roster panel: one darker glass layer behind both columns (contrast over any scene) ──
local roster = glass(board, { Name = "ScoreboardRoster", Position = O(0, BD.Header + BD.Gap), Size = O(BD.W, 100), Fill = T.Obsidian, FillT = 0.12, Shade = 0.3, Shadow = true, LightT = 0.6 })
rect(roster, { Name = "Seam", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, INSET), Size = UDim2.new(0, 1, 1, -INSET * 2), BackgroundColor3 = T.Line, BackgroundTransparency = 0.88, ZIndex = 2 })

-- ── team columns ──
local columns = {}
for i, team in TEAMS do
	local c = teamColor(team)
	local col = new("Frame", { Name = "ScoreboardColumn" .. team, BackgroundTransparency = 1, Position = O(INSET + (i - 1) * (CW + BD.Gap), BD.Header + BD.Gap + INSET), Size = O(CW, 10), ZIndex = 2 }, board)
	local ch = rect(col, { Name = "ColumnHeader", Size = O(CW, BD.ColHeader), BackgroundColor3 = T.Obsidian, BackgroundTransparency = 0.25 })
	divider(ch, { Name = "TeamLine", AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = c }, 0.2)
	rect(ch, { Name = "TeamMark", Position = O(0, 8), Size = O(3, BD.ColHeader - 16), BackgroundColor3 = c })
	text(ch, { Name = "TeamName", Position = O(14, 0), Size = O(120, BD.ColHeader), Text = spaced(string.upper(team), 2), FontFace = F.Head, TextSize = 18, TextColor3 = c })
	local count = text(ch, { Name = "Count", Position = O(90, 0), Size = O(160, BD.ColHeader), Text = "", FontFace = F.Mono, TextSize = 11, TextColor3 = T.TextDim })
	local x = CW - 14
	for _, s in BD.Stats do
		x -= s[3]
		text(ch, { Name = "Col" .. s[1], Position = O(x, 0), Size = O(s[3], BD.ColHeader), Text = s[2], FontFace = F.MonoM, TextSize = 11, TextColor3 = T.Steel, TextXAlignment = AX.Center })
	end
	columns[team] = { Frame = col, Rows = {}, Count = count }
end

local function rowY(index: number): number
	return BD.ColHeader + 6 + (index - 1) * (BD.Row + BD.RowGap)
end

local function makeRow(team: string, index: number)
	local col = columns[team]
	local tc = teamColor(team)
	local root = new("Frame", { Name = "ScoreboardRow" .. index, Position = O(0, rowY(index)), Size = UDim2.new(1, 0, 0, BD.Row), BackgroundTransparency = 1 }, col.Frame)
	local body = new("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, root)
	local row = { Root = root, Body = body, Cells = {}, Values = {}, Player = nil, IsSelf = false }
	-- glass layers
	row.Fill = rect(body, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.GlassHi, BackgroundTransparency = 0.4 })
	new("UIGradient", { Transparency = NS({ KP(0, 0), KP(1, 0.45) }) }, row.Fill)
	row.Stroke = new("UIStroke", { Color = T.Line, Transparency = 0.9, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row.Fill)
	row.Light = rect(body, { Name = "EdgeLight", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Line, BackgroundTransparency = 0.8, ZIndex = 3 })
	-- self treatment (hidden until this row is yours): lime wash fading right + lime spine
	row.Tint = rect(body, { Name = "SelfTint", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Lime, BackgroundTransparency = 1, ZIndex = 2 })
	new("UIGradient", { Transparency = NS({ KP(0, 0), KP(0.55, 0.65), KP(1, 1) }) }, row.Tint)
	row.Spine = rect(body, { Name = "SelfSpine", Size = O(3, BD.Row), BackgroundColor3 = T.Lime, BackgroundTransparency = 1, ZIndex = 5 })
	-- hover glow
	row.Hover = rect(body, { Name = "Hover", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Line, BackgroundTransparency = 1, ZIndex = 2 })
	-- rank cell (recessed)
	local rc = rect(body, { Name = "RankCell", Size = O(RANK_W, BD.Row), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.45, ZIndex = 3 })
	row.Rank = text(rc, { Name = "Rank", Size = UDim2.fromScale(1, 1), Text = "", FontFace = F.MonoB, TextSize = 15, TextColor3 = T.Steel, TextXAlignment = AX.Center, ZIndex = 4 })
	row.RankMark = rect(rc, { Name = "RankMark", AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = O(14, 2), BackgroundColor3 = T.Lime, BackgroundTransparency = 1, ZIndex = 4 })
	-- avatar: framed, team underline
	local av = rect(body, { Name = "AvatarFrame", Position = O(AV_X, (BD.Row - AV) / 2), Size = O(AV, AV), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.2, ZIndex = 3 })
	row.AvatarStroke = new("UIStroke", { Color = T.Line, Transparency = 0.75, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, av)
	row.Avatar = new("ImageLabel", { Name = "Avatar", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 }, av)
	row.AvatarLine = rect(av, { Name = "TeamLine", AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = tc, ZIndex = 5 })
	row.AvatarFrame = av
	-- name + YOU tag
	row.Name = text(body, { Name = "PlayerName", Position = O(NAME_X, 0), Size = O(NAME_W, BD.Row), Text = "", FontFace = F.Name, TextSize = 18, ZIndex = 4 })
	row.You = rect(body, { Name = "YouTag", AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, NAME_X, 0.5, 0), Size = O(34, 16), BackgroundColor3 = T.Lime, Visible = false, ZIndex = 5 })
	text(row.You, { Size = UDim2.fromScale(1, 1), Text = "YOU", FontFace = F.MonoB, TextSize = 10, TextColor3 = T.OnLime, TextXAlignment = AX.Center, ZIndex = 6 })
	-- stats
	local x = CW - 14
	for _, s in BD.Stats do
		x -= s[3]
		local isScore = s[1] == "Score"
		row.Cells[s[1]] = text(body, {
			Name = "Stat" .. s[1],
			Position = O(x, 0),
			Size = O(s[3], BD.Row),
			Text = "",
			FontFace = if isScore then F.Head else F.MonoM,
			TextSize = if isScore then 21 else 16,
			TextXAlignment = AX.Center,
			ZIndex = 4,
		})
	end
	-- hover feedback (rows never sink input: Active stays false)
	body.MouseEnter:Connect(function()
		if row.Player then
			tween(row.Hover, A.HoverTime, { BackgroundTransparency = 0.92 })
		end
	end)
	body.MouseLeave:Connect(function()
		tween(row.Hover, A.HoverTime, { BackgroundTransparency = 1 })
	end)
	col.Rows[index] = row
	return row
end

local function cellColor(row, key: string): Color3
	if key == "Score" then
		return if row.IsSelf then T.Lime else T.Text
	end
	return if row.IsSelf then T.Text else T.TextDim
end

local function setSelf(row, on: boolean)
	if row.IsSelf == on then
		return
	end
	row.IsSelf = on
	local t = A.HighlightTime
	tween(row.Tint, t, { BackgroundTransparency = if on then 0.84 else 1 })
	tween(row.Spine, t, { BackgroundTransparency = if on then 0 else 1 })
	tween(row.Stroke, t, { Transparency = if on then 0.55 else 0.9, Color = if on then T.Lime else T.Line })
	tween(row.AvatarStroke, t, { Transparency = if on then 0.35 else 0.75, Color = if on then T.Lime else T.Line })
	row.You.Visible = on
end

local function paintRow(row, p: Player?, rank: number)
	if not p then
		row.Player = nil
		row.Values = {}
		setSelf(row, false)
		row.Fill.BackgroundTransparency = 0.78
		row.Stroke.Transparency = 0.9
		row.Light.BackgroundTransparency = 0.92
		row.Rank.Text = ""
		row.RankMark.BackgroundTransparency = 1
		row.Avatar.Image = ""
		row.AvatarFrame.BackgroundTransparency = 0.75
		row.AvatarLine.BackgroundTransparency = 0.85
		row.Name.Text = "OPEN SLOT" -- mono font: no hair-space tracking
		row.Name.FontFace = F.Mono
		row.Name.TextSize = 12
		row.Name.TextColor3 = T.TextFaint
		row.Name.Position = O(NAME_X, 0)
		for _, cell in row.Cells do
			cell.Text = ""
		end
		return
	end
	local s = stats(p)
	local samePlayer = row.Player == p
	row.Player = p
	setSelf(row, p == player)
	row.Fill.BackgroundTransparency = 0.4
	if not row.IsSelf then
		row.Stroke.Transparency = 0.9
	end
	row.Light.BackgroundTransparency = 0.8
	row.Rank.Text = string.format("%02d", rank)
	row.Rank.TextColor3 = if rank == 1 then T.Lime else T.Steel
	row.RankMark.BackgroundTransparency = if rank == 1 then 0.1 else 1
	row.AvatarFrame.BackgroundTransparency = 0.2
	row.AvatarLine.BackgroundTransparency = 0
	thumbFor(p.UserId, row.Avatar)
	row.Name.FontFace = F.Name
	row.Name.TextSize = 18
	row.Name.TextColor3 = T.Text
	row.Name.Text = string.upper(p.DisplayName)
	-- YOU tag sits right after the name; the name gives up room for it
	if row.IsSelf then
		row.Name.Position = O(NAME_X + 42, 0)
		row.Name.Size = O(NAME_W - 42, BD.Row)
	else
		row.Name.Position = O(NAME_X, 0)
		row.Name.Size = O(NAME_W, BD.Row)
	end
	local values = { K = tostring(s.K), D = tostring(s.D), KD = kdText(s.K, s.D), HS = tostring(s.HS), Score = tostring(s.Score) }
	for key, value in values do
		local cell = row.Cells[key]
		local changed = samePlayer and row.Values[key] ~= nil and row.Values[key] ~= value
		cell.Text = value
		if changed then
			-- value changed while visible: flash lime, settle back
			cell.TextColor3 = T.Lime
			tween(cell, A.FlashTime, { TextColor3 = cellColor(row, key) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		else
			cell.TextColor3 = cellColor(row, key)
		end
	end
	row.Values = values
end

local function rosterHeight(rows: number): number
	return INSET + rowY(rows + 1) + INSET - BD.RowGap
end

local function boardHeight(rows: number): number
	return BD.Header + BD.Gap + rosterHeight(rows) + 6 + BD.Footer
end

-- footer: technical legend
local footer = new("Frame", { Name = "ScoreboardFooter", BackgroundTransparency = 1, AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, BD.Footer) }, board)
divider(footer, { Name = "Line", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Line }, 0.7)
local keyChip = rect(footer, { Name = "KeyChip", AnchorPoint = V2(0, 0.5), Position = UDim2.new(0, 0, 0.5, 2), Size = O(40, 16), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.3 })
new("UIStroke", { Color = T.Line, Transparency = 0.6, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, keyChip)
text(keyChip, { Size = UDim2.fromScale(1, 1), Text = "TAB", FontFace = F.MonoB, TextSize = 10, TextColor3 = T.Text, TextXAlignment = AX.Center })
text(footer, { Name = "Hint", Position = O(50, 2), Size = O(400, BD.Footer - 2), Text = spaced("HOLD TO VIEW", 1), FontFace = F.Mono, TextSize = 11, TextColor3 = T.TextDim })
local legend = text(footer, { Name = "Legend", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = O(700, BD.Footer - 2), Text = "", FontFace = F.Mono, TextSize = 11, TextColor3 = T.TextDim, TextXAlignment = AX.Right })

local currentRows = 0
local function setRows(rows: number)
	if rows == currentRows then
		return
	end
	currentRows = rows
	local h = boardHeight(rows)
	board.Size = O(BD.W, h)
	roster.Size = O(BD.W, rosterHeight(rows))
	for _, team in TEAMS do
		columns[team].Frame.Size = O(CW, rosterHeight(rows) - INSET * 2)
	end
end

local function refreshBoard()
	local byTeam = { Blue = {}, Red = {} }
	for _, p in matchPlayers() do
		table.insert(byTeam[p.Team.Name], p)
	end
	local rows = math.max(Config.SlotsPerTeam, #byTeam.Blue, #byTeam.Red)
	for _, team in TEAMS do
		local list = byTeam[team]
		table.sort(list, sortByScore)
		local col = columns[team]
		for i = 1, rows do
			local row = col.Rows[i] or makeRow(team, i)
			row.Root.Visible = true
			paintRow(row, list[i], i)
		end
		for i = rows + 1, #col.Rows do
			col.Rows[i].Root.Visible = false
		end
		col.Count.Text = string.format("%d / %d", #list, Config.SlotsPerTeam)
	end
	setRows(rows)

	local bs, rs = num(Match:GetAttribute("BlueScore")), num(Match:GetAttribute("RedScore"))
	hdr.Blue.Score.Text = tostring(bs)
	hdr.Red.Score.Text = tostring(rs)
	local limit = num(Match:GetAttribute("ScoreLimit"))
	hdr.Blue.Meta.Text = if limit > 0 then string.format("%d / %d TO WIN", bs, limit) else ""
	hdr.Red.Meta.Text = if limit > 0 then string.format("%d / %d TO WIN", rs, limit) else ""
	local half = 0.5
	blueBar.Size = UDim2.new(if limit > 0 then math.clamp(bs / limit, 0, 1) * half else 0, 0, 1, 0)
	redBar.Size = UDim2.new(if limit > 0 then math.clamp(rs / limit, 0, 1) * half else 0, 0, 1, 0)

	local mode = (string.upper(tostring(Match:GetAttribute("Mode") or "")):gsub("_(%d)", " %%1V%%1"))
	local map = string.upper(tostring(Match:GetAttribute("MapName") or ""))
	modeLabel.Text = spaced(if map ~= "" then mode .. "  ·  " .. map else mode, 1)
	local ph = phase()
	if ph == "Live" then
		timeLabel.Text = fmtTime(num(Match:GetAttribute("TimeLeft")))
		phaseLabel.Text = "LIVE"
		phaseLabel.TextColor3 = T.Lime
		liveDot.BackgroundColor3 = T.Lime
	else
		timeLabel.Text = fmtTime(num(Match:GetAttribute("PhaseEnds")) - serverNow())
		phaseLabel.Text = string.upper(ph)
		phaseLabel.TextColor3 = T.Steel
		liveDot.BackgroundColor3 = T.Steel
	end
	local matchId = num(Match:GetAttribute("MatchId"))
	legend.Text = spaced(string.format("ELIM %d  ·  HEADSHOT +%d  ·  OP %03d", Config.Score.PerKill, Config.Score.PerHeadshot, matchId), 1)
end

-- ═══ POST-MATCH DEBRIEF ════════════════════════════════════════════════════════════════
local results = new("CanvasGroup", {
	Name = "ScoreboardResults",
	AnchorPoint = V2(0.5, 0),
	Position = O(0, 0),
	Size = O(RD.W, RD.H),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
}, gui)
local resultsScale = new("UIScale", { Name = "ScoreboardResultsScale" }, results)
local resultsHome = O(0, 0) -- set by rescale(): just under MatchHud's banner

local rPanel = glass(results, { Name = "ScoreboardResultsPanel", Size = O(RD.W, RD.H), FillT = 0.08, Shade = 0.45, Brackets = true })
local accent = rect(rPanel, { Name = "Accent", AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 0, 0, 2), BackgroundColor3 = T.Lime, ZIndex = 5 })
text(rPanel, { Name = "Tag", Position = O(24, 12), Size = O(460, 18), Text = spaced("POST-OPERATION  DEBRIEF", 3), FontFace = F.MonoM, TextSize = 12, TextColor3 = T.Lime, ZIndex = 4 })
local rMeta = text(rPanel, { Name = "Meta", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -24, 0, 12), Size = O(460, 18), Text = "", FontFace = F.Mono, TextSize = 11, TextColor3 = T.TextDim, TextXAlignment = AX.Right, ZIndex = 4 })
divider(rPanel, { Name = "HeadLine", Position = O(16, 38), Size = UDim2.new(1, -32, 0, 1), BackgroundColor3 = T.Line }, 0.62)

local BLOCK_Y, BLOCK_H = 50, RD.H - 62
local function block(name: string, x: number, w: number)
	-- each block fades / rises on its own (staggered entrance); padded so shadows are not clipped
	return new("CanvasGroup", { Name = name, Position = O(x - 6, BLOCK_Y - 4), Size = O(w + 12, BLOCK_H + 10), BackgroundTransparency = 1, GroupTransparency = 1 }, rPanel)
end

-- A) outcome
local outcome = block("Outcome", 24, 300)
local oTitle = text(outcome, { Name = "Title", Position = O(6, 6), Size = O(300, 46), Text = "", FontFace = F.Head, TextSize = 44 })
local oSub = text(outcome, { Name = "Sub", Position = O(8, 54), Size = O(300, 16), Text = "", FontFace = F.MonoM, TextSize = 11, TextColor3 = T.TextDim })
local oBlue = text(outcome, { Name = "BlueFinal", Position = O(6, 78), Size = O(120, 64), Text = "0", FontFace = F.Head, TextSize = 58, TextColor3 = T.Blue, TextXAlignment = AX.Right })
text(outcome, { Name = "Colon", Position = O(126, 78), Size = O(50, 64), Text = ":", FontFace = F.Head6, TextSize = 40, TextColor3 = T.TextFaint, TextXAlignment = AX.Center })
local oRed = text(outcome, { Name = "RedFinal", Position = O(176, 78), Size = O(120, 64), Text = "0", FontFace = F.Head, TextSize = 58, TextColor3 = T.Red })
local oTrack = rect(outcome, { Name = "Split", Position = O(8, 156), Size = O(292, 3), BackgroundColor3 = T.Red })
local oBlueShare = rect(oTrack, { Name = "BlueShare", Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = T.Blue })
text(outcome, { Name = "SplitLabel", Position = O(8, 162), Size = O(292, 14), Text = spaced("FINAL SCORE", 2), FontFace = F.Mono, TextSize = 10, TextColor3 = T.TextFaint })

divider(rPanel, { Name = "SepA", Position = O(344, BLOCK_Y + 6), Size = O(1, BLOCK_H - 12), BackgroundColor3 = T.Line }, 0.7).UIGradient.Rotation = 90

-- B) MVP card (elevated)
local mvpBlock = block("MVP", 364, 300)
local mvpCard, mvpFill, mvpStroke = glass(mvpBlock, { Name = "Card", Position = O(6, 4), Size = O(300, BLOCK_H - 4), Fill = T.GlassHi, FillT = 0.35, Shade = 0.5, Shadow = true, EdgeT = 0.7, LightT = 0.3 })
mvpFill.ClipsDescendants = true -- clips the shine only; the card's shadow stays outside
local mvpChip = rect(mvpCard, { Name = "Chip", Position = O(14, 12), Size = O(42, 18), BackgroundColor3 = T.Lime, ZIndex = 5 })
text(mvpChip, { Size = UDim2.fromScale(1, 1), Text = "MVP", FontFace = F.MonoB, TextSize = 11, TextColor3 = T.OnLime, TextXAlignment = AX.Center, ZIndex = 6 })
text(mvpCard, { Name = "Label", Position = O(64, 12), Size = O(220, 18), Text = spaced("TOP OPERATIVE", 2), FontFace = F.Mono, TextSize = 10, TextColor3 = T.TextDim, ZIndex = 5 })
local mvpAvFrame = rect(mvpCard, { Name = "AvatarFrame", Position = O(14, 42), Size = O(84, 84), BackgroundColor3 = T.Midnight, BackgroundTransparency = 0.2, ZIndex = 4 })
new("UIStroke", { Color = T.Lime, Transparency = 0.45, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, mvpAvFrame)
local mvpAvatar = new("ImageLabel", { Name = "Avatar", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, mvpAvFrame)
local mvpAvLine = rect(mvpAvFrame, { Name = "TeamLine", AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = T.Blue, ZIndex = 6 })
brackets(mvpAvFrame, T.Lime, 8)
local mvpName = text(mvpCard, { Name = "PlayerName", Position = O(112, 42), Size = O(176, 32), Text = "", FontFace = F.Head, TextSize = 28, ZIndex = 5 })
local mvpTeam = text(mvpCard, { Name = "Team", Position = O(113, 74), Size = O(176, 16), Text = "", FontFace = F.MonoB, TextSize = 11, ZIndex = 5 })
local mvpScore = text(mvpCard, { Name = "Score", Position = O(113, 96), Size = O(176, 26), Text = "", FontFace = F.MonoB, TextSize = 18, TextColor3 = T.Lime, ZIndex = 5 })
local mvpElims = text(mvpCard, { Name = "Elims", Position = O(113, 120), Size = O(176, 16), Text = "", FontFace = F.Mono, TextSize = 11, TextColor3 = T.TextDim, ZIndex = 5 })
-- one-time shine sweep across the card
local shine = rect(mvpFill, { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, ZIndex = 2 })
local shineGrad = new("UIGradient", { Rotation = 18, Offset = V2(-1, 0), Transparency = NS({ KP(0, 1), KP(0.42, 1), KP(0.5, 0.2), KP(0.58, 1), KP(1, 1) }) }, shine)

divider(rPanel, { Name = "SepB", Position = O(684, BLOCK_Y + 6), Size = O(1, BLOCK_H - 12), BackgroundColor3 = T.Line }, 0.7).UIGradient.Rotation = 90

-- C) your performance: 2 x 2 elevated stat cards
local mine = block("YourStats", 702, 274)
text(mine, { Name = "Label", Position = O(6, 4), Size = O(180, 16), Text = spaced("YOUR PERFORMANCE", 2), FontFace = F.MonoM, TextSize = 11, TextColor3 = T.Lime })
local myKD = text(mine, { Name = "KD", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = O(100, 16), Text = "", FontFace = F.MonoB, TextSize = 11, TextColor3 = T.TextDim, TextXAlignment = AX.Right })
local tiles = {}
local TILES = { { "K", "ELIMS" }, { "D", "DEATHS" }, { "HS", "HEADSHOTS" }, { "Score", "SCORE" } }
local TW, TH = 131, 70
for i, t in TILES do
	local cx = 6 + ((i - 1) % 2) * (TW + 12)
	local cy = 28 + math.floor((i - 1) / 2) * (TH + 10)
	local isScore = t[1] == "Score"
	local card = glass(mine, { Name = "Card" .. t[1], Position = O(cx, cy), Size = O(TW, TH), Fill = T.GlassHi, FillT = 0.4, Shade = 0.5, Shadow = true, EdgeT = if isScore then 0.6 else 0.82, LightT = 0.4 })
	if isScore then
		rect(card, { Name = "Spine", Size = O(2, TH), BackgroundColor3 = T.Lime, ZIndex = 5 })
	end
	tiles[t[1]] = text(card, { Name = "Value", Position = O(12, 4), Size = O(TW - 20, 40), Text = "0", FontFace = F.Head, TextSize = 34, TextColor3 = if isScore then T.Lime else T.Text, ZIndex = 5 })
	text(card, { Name = "Caption", Position = O(13, TH - 24), Size = O(TW - 20, 16), Text = spaced(t[2], 1), FontFace = F.Mono, TextSize = 10, TextColor3 = T.TextDim, ZIndex = 5 })
end

local BLOCKS = { outcome, mvpBlock, mine }
local blockHome = {}
for _, b in BLOCKS do
	blockHome[b] = b.Position
end

local resultsToken = 0

-- counts a label up to its value (one tween on a temporary NumberValue, cleaned up after)
local function countUp(label: TextLabel, target: number, delay: number, token: number)
	label.Text = "0"
	if target <= 0 then
		return
	end
	local nv = Instance.new("NumberValue")
	local conn = nv.Changed:Connect(function(v)
		if token == resultsToken then
			label.Text = tostring(math.floor(v + 0.5))
		end
	end)
	local tw = tween(nv, A.CountUp, { Value = target }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, delay)
	tw.Completed:Connect(function()
		conn:Disconnect()
		nv:Destroy()
		if token == resultsToken then
			label.Text = tostring(target)
		end
	end)
end

local function fillResults(token: number, baseDelay: number)
	local winner = tostring(Match:GetAttribute("Winner") or "")
	local reason = string.upper(tostring(Match:GetAttribute("EndReason") or ""))
	local myTeam = player.Team and player.Team.Name
	local title, color
	if winner ~= "Blue" and winner ~= "Red" then
		title, color = "DRAW", T.Draw
	elseif myTeam == "Blue" or myTeam == "Red" then
		if winner == myTeam then
			title, color = "VICTORY", T.Lime
		else
			title, color = "DEFEAT", T.Red
		end
	else
		title, color = string.upper(winner) .. " WINS", teamColor(winner)
	end
	oTitle.Text = spaced(title, 2)
	oTitle.TextColor3 = color
	local who = if winner == "Blue" or winner == "Red" then string.upper(winner) .. " TEAM WINS" else "NO WINNER"
	oSub.Text = spaced(if reason ~= "" then who .. "  ·  BY " .. reason else who, 1)
	local bs, rs = num(Match:GetAttribute("BlueScore")), num(Match:GetAttribute("RedScore"))
	oBlue.Text = tostring(bs)
	oRed.Text = tostring(rs)
	oBlueShare.Size = UDim2.new(0, 0, 1, 0)
	local share = if bs + rs > 0 then bs / (bs + rs) else 0.5
	tween(oBlueShare, 0.8, { Size = UDim2.new(share, 0, 1, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, baseDelay + 0.2)

	local mode = (string.upper(tostring(Match:GetAttribute("Mode") or "")):gsub("_(%d)", " %%1V%%1"))
	local map = string.upper(tostring(Match:GetAttribute("MapName") or ""))
	rMeta.Text = spaced(string.format("%s  ·  %s  ·  OP %03d", mode, map, num(Match:GetAttribute("MatchId"))), 1)

	local list = matchPlayers()
	table.sort(list, sortByScore)
	local best = list[1]
	if best then
		local s = stats(best)
		local bt = best.Team and best.Team.Name
		mvpName.Text = string.upper(best.DisplayName)
		mvpName.TextColor3 = if best == player then T.Lime else T.Text
		mvpTeam.Text = spaced((if bt then string.upper(bt) .. " TEAM" else "") .. (if best == player then "  ·  YOU" else ""), 1)
		mvpTeam.TextColor3 = teamColor(bt)
		mvpAvLine.BackgroundColor3 = teamColor(bt)
		mvpScore.Text = string.format("%d PTS", s.Score)
		mvpElims.Text = spaced(string.format("%d ELIMS  ·  %d HS", s.K, s.HS), 1)
		thumbFor(best.UserId, mvpAvatar)
	else
		mvpName.Text = "—"
		mvpName.TextColor3 = T.TextDim
		mvpTeam.Text = ""
		mvpScore.Text = ""
		mvpElims.Text = ""
		mvpAvatar.Image = ""
	end

	local s = stats(player)
	myKD.Text = "K/D " .. kdText(s.K, s.D)
	local d = baseDelay + 2 * A.BlockStagger + 0.1
	countUp(tiles.K, s.K, d, token)
	countUp(tiles.D, s.D, d + 0.05, token)
	countUp(tiles.HS, s.HS, d + 0.1, token)
	countUp(tiles.Score, s.Score, d + 0.15, token)
end

local function hideResults(instant: boolean?)
	resultsToken += 1
	if not results.Visible then
		return
	end
	if instant then
		results.Visible = false
		results.GroupTransparency = 1
		return
	end
	local token = resultsToken
	tween(results, A.ResultsOut, { GroupTransparency = 1, Position = resultsHome + O(0, A.ResultsRise * 0.6) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(A.ResultsOut, function()
		if token == resultsToken then
			results.Visible = false
		end
	end)
end

local function showResults(token: number)
	-- reset to the pre-entrance state
	results.Position = resultsHome + O(0, A.ResultsRise)
	results.GroupTransparency = 1
	accent.Size = UDim2.new(0, 0, 0, 2)
	shineGrad.Offset = V2(-1, 0)
	mvpStroke.Transparency = 0.7
	for _, b in BLOCKS do
		b.GroupTransparency = 1
		b.Position = blockHome[b] + O(0, 10)
	end
	fillResults(token, A.ResultsIn * 0.4)
	results.Visible = true
	-- panel: rise + fade
	tween(results, A.ResultsIn, { GroupTransparency = 0, Position = resultsHome }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	-- accent wipe from the centre
	tween(accent, 0.6, { Size = UDim2.new(1, 0, 0, 2) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0.15)
	-- blocks: outcome -> MVP -> your stats
	for i, b in BLOCKS do
		tween(b, 0.4, { GroupTransparency = 0, Position = blockHome[b] }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, A.ResultsIn * 0.4 + (i - 1) * A.BlockStagger)
	end
	-- MVP emphasis: edge lights lime, one shine sweep
	local mvpAt = A.ResultsIn * 0.4 + A.BlockStagger + 0.35
	tween(mvpStroke, 0.35, { Transparency = 0.3, Color = T.Lime }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, mvpAt)
	tween(shineGrad, A.Shine, { Offset = V2(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, mvpAt)
end

local function onEnded()
	resultsToken += 1
	local token = resultsToken
	if player:GetAttribute("MatchStatus") ~= "Match" then
		return
	end
	-- 2026-11-18: the directed results sequence (VantageMatchResults) replaces this debrief
	if require(Vantage:WaitForChild("MatchConfig")).Results then
		return
	end
	local endsAt = num(Match:GetAttribute("PhaseEnds"))
	task.delay(Config.ResultsDelay, function()
		if token ~= resultsToken or phase() ~= "Ended" then
			return
		end
		showResults(token)
		local hold = Config.ResultsMaxHold
		if endsAt > 0 then
			hold = math.min(hold, endsAt - serverNow() - Config.ResultsHideBefore - A.ResultsOut)
		end
		task.delay(math.max(0.5, hold), function()
			if token == resultsToken then
				hideResults()
			end
		end)
	end)
end

-- ─── scaling ───────────────────────────────────────────────────────────────────────────
local function rescale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local v = cam.ViewportSize
	if v.X < 50 then
		return
	end
	-- same base rule as MatchHud (1920x1080 design pixels)
	local s = math.clamp(math.min(v.X / 1920, v.Y / 1080), Theme.MinScale, Theme.MaxScale)
	local bh = boardHeight(math.max(currentRows, Config.SlotsPerTeam))
	local fitW, fitH = (v.X - 24) / BD.W, (v.Y - 24) / bh
	boardScale.Scale = math.max(0.3, math.min(math.max(s, Theme.MobileMinScale), fitW, fitH))
	-- debrief: under the banner, never off the bottom of the screen
	local bannerBottom = v.Y * Theme.Banner.CenterY + Theme.Banner.HalfHeight * s
	local top = bannerBottom + RD.GapBelowBanner * s
	local room = v.Y - top - 12
	local rsc = math.min(s, (v.X - 24) / RD.W)
	if RD.H * rsc > room then
		rsc = math.max(0.3, room / RD.H)
	end
	resultsScale.Scale = rsc
	resultsHome = O(v.X / 2, top)
	if results.Visible then
		results.Position = resultsHome
	end
end

local camConn: RBXScriptConnection? = nil
local function watchCamera()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	rescale()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

-- ─── visibility / input ────────────────────────────────────────────────────────────────
local keyHeld = false
local touchOpen = false
local shown = false

local toggle = new("TextButton", {
	Name = "ScoreboardToggle",
	AnchorPoint = V2(1, 0),
	Position = UDim2.new(1, -12, 0, 64),
	Size = O(92, 34),
	BackgroundColor3 = T.Glass,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	FontFace = F.MonoB,
	TextSize = 13,
	TextColor3 = T.Text,
	Text = spaced("SCORES", 1),
	Visible = false,
}, gui)
new("UIStroke", { Color = T.Line, Transparency = 0.7, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toggle)
brackets(toggle, T.Lime, 8)
toggle.Activated:Connect(function()
	touchOpen = not touchOpen
	toggle.TextColor3 = if touchOpen then T.Lime else T.Text
end)

local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	if on then
		refreshBoard()
		rescale()
		board.Visible = true
		board.Position = BOARD_POS + O(0, A.Rise)
		tween(board, A.OpenTime, { GroupTransparency = 0, Position = BOARD_POS })
		-- rows slide in one after another
		for _, team in TEAMS do
			for i, row in columns[team].Rows do
				if row.Root.Visible then
					row.Body.Position = O(-A.RowSlide, 0)
					tween(row.Body, 0.24, { Position = O(0, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, (i - 1) * A.RowStagger)
				end
			end
		end
		pulse:Play()
	else
		local t = tween(board, A.CloseTime, { GroupTransparency = 1, Position = BOARD_POS + O(0, A.Rise * 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			if not shown then
				board.Visible = false
				pulse:Cancel()
				liveDot.BackgroundTransparency = 0
			end
		end)
	end
end

-- Tab is not gated on gameProcessed: Roblox's own player list marks Tab processed whenever it is
-- enabled. We never sink it (others still see it); typing in a TextBox and open menus block it.
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode ~= Config.Key or UserInputService:GetFocusedTextBox() then
		return
	end
	if boardAllowed() then
		keyHeld = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.Key then
		keyHeld = false
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	keyHeld = false
end)

local nextRefresh = 0
local toggleVisible = false -- B3: skip unchanged Visible writes in the Heartbeat below
RunService.Heartbeat:Connect(function()
	local allowed = boardAllowed()
	if not allowed then
		keyHeld = false
		if touchOpen then
			touchOpen = false
			toggle.TextColor3 = T.Text
		end
	end
	local visible = allowed and UserInputService.TouchEnabled
	if visible ~= toggleVisible then
		toggleVisible = visible
		toggle.Visible = visible
	end
	setShown(allowed and (keyHeld or touchOpen))
	if shown then
		local t = os.clock()
		if t >= nextRefresh then
			nextRefresh = t + Config.RefreshInterval
			refreshBoard()
		end
	end
end)

-- ─── phase flow ────────────────────────────────────────────────────────────────────────
local lastPhase = phase()
Match:GetAttributeChangedSignal("Phase"):Connect(function()
	local ph = phase()
	if ph == "Ended" and lastPhase ~= "Ended" then
		onEnded()
	elseif ph ~= "Ended" then
		hideResults(ph == "Idle")
	end
	lastPhase = ph
end)
player:GetAttributeChangedSignal("MatchStatus"):Connect(function()
	if player:GetAttribute("MatchStatus") ~= "Match" then
		hideResults(true)
	end
end)

-- build the default rows once so the first open is instant
for _, team in TEAMS do
	for i = 1, Config.SlotsPerTeam do
		paintRow(makeRow(team, i), nil, i)
	end
end
setRows(Config.SlotsPerTeam)
watchCamera()
if phase() == "Ended" then
	onEnded()
end
