--[[
	VANTAGE — LobbyBoards (server) · 2026-11-18
	Fills the Staging Deck screens (Workspace.HyperLobby, tag "LobbyBoard", attribute Board) with live data and
	poses the top 3 of the ranked ladder on the Hall of Records podium (parts with attribute Rank under 20_Records).
	Boards: Welcome · Status · Brand · Modes · Level · Ladder · Streak · Tiers · Season.
	Sources: Vantage.Match attributes, Vantage attribute RankedTop (ProfileService), player attributes
	(Level, LevelXP, RP, BestStreak, InLobby), MatchConfig.Modes, RankedConfig.Ranks, SeasonPass config.
	Screens whose front faces outward carry attribute Face = "Back".
]]
local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local V = RS:WaitForChild("Vantage")
local MatchConfig = require(V:WaitForChild("MatchConfig"))
local RankedConfig = require(V:WaitForChild("Ranked"):WaitForChild("RankedConfig"))
local seasonCfg
do
	local f = V:FindFirstChild("SeasonPass")
	local m = f and f:FindFirstChildWhichIsA("ModuleScript")
	if m then
		local ok, c = pcall(require, m)
		if ok then seasonCfg = c end
	end
end
local lobby = workspace:WaitForChild("HyperLobby", 30)
if not lobby then return end
local matchF = V:WaitForChild("Match", 30)

local TITLE = Font.fromEnum(Enum.Font.Michroma)
local BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local MED = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local BLUE = Color3.fromRGB(70, 155, 255)
local RED = Color3.fromRGB(235, 72, 78)
local WHITE = Color3.fromRGB(232, 238, 246)
local DIM = Color3.fromRGB(128, 140, 158)
local GOLD = Color3.fromRGB(240, 198, 96)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do i[k] = v end
	i.Parent = parent
	return i
end
local function text(parent, t, font, pos, size, col, align)
	return new("TextLabel", {
		BackgroundTransparency = 1, Text = t, FontFace = font, Position = pos, Size = size,
		TextColor3 = col or WHITE, TextScaled = true, TextXAlignment = align or Enum.TextXAlignment.Left,
	}, parent)
end
local function attr(name, default)
	local v = matchF and matchF:GetAttribute(name)
	if v == nil then return default end
	return v
end
local function modeName(id)
	local m = MatchConfig.Modes and MatchConfig.Modes[id]
	return m and (m.Name or m.Title) or "6V6 DEATHMATCH"
end
local function rankName(rp)
	local per = (RankedConfig.TierRP or 100) * (RankedConfig.TiersPerRank or 3)
	local ranks = RankedConfig.Ranks or {}
	if rp >= (RankedConfig.LegendRP or math.huge) and ranks[#ranks] then
		return string.upper(ranks[#ranks].Id), ranks[#ranks].Color
	end
	local i = math.clamp(math.floor(rp / per) + 1, 1, math.max(#ranks - 1, 1))
	local tier = math.clamp(math.floor((rp % per) / (RankedConfig.TierRP or 100)) + 1, 1, RankedConfig.TiersPerRank or 3)
	local r = ranks[i]
	return r and (string.upper(r.Id) .. " " .. tier) or "UNRANKED", r and r.Color or WHITE
end
local function clock(s)
	s = math.max(0, math.floor(s or 0))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- a board shell: dark glass, header with title + accent rule, corner brackets; returns body frame
local function shell(part, title, sub, accent)
	local old = part:FindFirstChild("BoardGui")
	if old then old:Destroy() end
	local face = if part:GetAttribute("Face") == "Back" then Enum.NormalId.Back else Enum.NormalId.Front
	local h = math.floor(1000 * part.Size.Y / part.Size.X)
	local sg = new("SurfaceGui", {
		Name = "BoardGui", Face = face, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(1000, h), LightInfluence = 0, Brightness = 1.25, MaxDistance = 240,
	}, part)
	local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(12, 15, 22), BorderSizePixel = 0 }, sg)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(26, 32, 46), Color3.fromRGB(9, 11, 16)) }, bg)
	-- faint scan lines
	for y = 0, h, 14 do
		new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, y), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.965, BorderSizePixel = 0 }, bg)
	end
	-- corner brackets
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local ax, ay = c[1], c[2]
		new("Frame", { AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, ax == 0 and 14 or -14, ay, ay == 0 and 14 or -14), Size = UDim2.fromOffset(40, 4), BackgroundColor3 = accent or BLUE, BorderSizePixel = 0 }, bg)
		new("Frame", { AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, ax == 0 and 14 or -14, ay, ay == 0 and 14 or -14), Size = UDim2.fromOffset(4, 40), BackgroundColor3 = accent or BLUE, BorderSizePixel = 0 }, bg)
	end
	local headH = math.clamp(math.floor(h * 0.2), 70, 130)
	text(bg, title, TITLE, UDim2.fromOffset(48, 30), UDim2.new(0.62, 0, 0, headH * 0.55), WHITE)
	if sub then
		text(bg, sub, BODY, UDim2.new(0.62, 0, 0, 30 + headH * 0.1), UDim2.new(0.36, -48, 0, headH * 0.3), DIM, Enum.TextXAlignment.Right)
	end
	new("Frame", { Position = UDim2.fromOffset(48, 30 + headH * 0.62), Size = UDim2.fromOffset(120, 5), BackgroundColor3 = accent or BLUE, BorderSizePixel = 0 }, bg)
	new("Frame", { Position = UDim2.fromOffset(174, 30 + headH * 0.62), Size = UDim2.fromOffset(18, 5), BackgroundColor3 = RED, BorderSizePixel = 0 }, bg)
	local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(48, 30 + headH * 0.62 + 26), Size = UDim2.new(1, -96, 1, -(30 + headH * 0.62 + 26) - 36) }, bg)
	return body, h
end

-- ranked list rows inside a body frame
local function rows(body, list, maxRows, emptyText)
	for _, c in body:GetChildren() do c:Destroy() end
	if #list == 0 then
		text(body, emptyText or "NO DATA YET", BODY, UDim2.fromScale(0, 0.35), UDim2.fromScale(1, 0.14), DIM, Enum.TextXAlignment.Center)
		return
	end
	local rh = 1 / maxRows
	for i = 1, math.min(#list, maxRows) do
		local e = list[i]
		local row = new("Frame", { Position = UDim2.fromScale(0, (i - 1) * rh), Size = UDim2.new(1, 0, rh, -6), BackgroundColor3 = i == 1 and Color3.fromRGB(46, 40, 22) or Color3.fromRGB(22, 27, 38), BackgroundTransparency = 0.15, BorderSizePixel = 0 }, body)
		new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = i == 1 and GOLD or (i <= 3 and BLUE or Color3.fromRGB(60, 70, 88)), BorderSizePixel = 0 }, row)
		text(row, tostring(i), TITLE, UDim2.new(0, 18, 0.18, 0), UDim2.new(0.08, 0, 0.64, 0), i == 1 and GOLD or WHITE, Enum.TextXAlignment.Center)
		text(row, e.Name, BODY, UDim2.new(0.12, 0, 0.2, 0), UDim2.new(0.55, 0, 0.6, 0), WHITE)
		if e.Sub then text(row, e.Sub, MED, UDim2.new(0.5, 0, 0.26, 0), UDim2.new(0.22, 0, 0.48, 0), e.SubColor or DIM, Enum.TextXAlignment.Right) end
		text(row, e.Value, TITLE, UDim2.new(0.74, 0, 0.2, 0), UDim2.new(0.24, 0, 0.6, 0), i == 1 and GOLD or BLUE, Enum.TextXAlignment.Right)
	end
end

local boards = {} -- part -> { kind, body, refs }

local BUILD = {}
function BUILD.Welcome(part)
	local body = shell(part, "FORWARD STAGING DECK", "LEGION COMMAND")
	text(body, "VANTAGESHOT", TITLE, UDim2.fromScale(0, 0.0), UDim2.fromScale(1, 0.26), WHITE, Enum.TextXAlignment.Center)
	text(body, "LEGIONARIES, STAND BY FOR DEPLOYMENT", BODY, UDim2.fromScale(0, 0.3), UDim2.fromScale(1, 0.1), BLUE, Enum.TextXAlignment.Center)
	text(body, "Step onto the DEPLOY pad in Bay 01, or press DEPLOY, to join 6v6 Team Deathmatch.", MED, UDim2.fromScale(0.04, 0.46), UDim2.fromScale(0.92, 0.08), DIM, Enum.TextXAlignment.Center)
	text(body, "Loadouts in the Armory  ·  Leaderboards in the Hall of Records", MED, UDim2.fromScale(0.04, 0.57), UDim2.fromScale(0.92, 0.07), DIM, Enum.TextXAlignment.Center)
	local online = text(body, "", TITLE, UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.14), WHITE, Enum.TextXAlignment.Center)
	text(body, "LEGIONARIES ONLINE", BODY, UDim2.fromScale(0, 0.88), UDim2.fromScale(1, 0.08), DIM, Enum.TextXAlignment.Center)
	return { Online = online }
end
function BUILD.Status(part)
	local body = shell(part, "OPERATIONS", "BAY 01  ·  LIVE FEED")
	local r = {}
	r.Phase = text(body, "", TITLE, UDim2.fromScale(0, 0.02), UDim2.fromScale(1, 0.16), WHITE)
	r.Mode = text(body, "", BODY, UDim2.fromScale(0, 0.21), UDim2.fromScale(1, 0.09), DIM)
	r.Blue = text(body, "", TITLE, UDim2.fromScale(0, 0.36), UDim2.fromScale(0.4, 0.2), BLUE, Enum.TextXAlignment.Right)
	r.Sep = text(body, ":", TITLE, UDim2.fromScale(0.4, 0.36), UDim2.fromScale(0.2, 0.2), DIM, Enum.TextXAlignment.Center)
	r.Red = text(body, "", TITLE, UDim2.fromScale(0.6, 0.36), UDim2.fromScale(0.4, 0.2), RED)
	r.Time = text(body, "", BODY, UDim2.fromScale(0, 0.58), UDim2.fromScale(1, 0.09), WHITE, Enum.TextXAlignment.Center)
	r.Queue = text(body, "", BODY, UDim2.fromScale(0, 0.78), UDim2.fromScale(0.48, 0.1), WHITE)
	r.Lobby = text(body, "", BODY, UDim2.fromScale(0.52, 0.78), UDim2.fromScale(0.48, 0.1), WHITE, Enum.TextXAlignment.Right)
	return r
end
function BUILD.Brand(part)
	local body = shell(part, "LEGION COMMAND", "SECTOR 7  ·  ALT 3000")
	-- chevron emblem
	local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.5, 0.62) }, body)
	new("UIAspectRatioConstraint", { AspectRatio = 1.25 }, holder)
	for i, s in { -1, 1 } do
		local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + s * 0.2, 0.42), Size = UDim2.fromScale(0.16, 0.86), Rotation = -s * 24, BackgroundColor3 = BLUE, BorderSizePixel = 0 }, holder)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(120, 190, 255), Color3.fromRGB(20, 80, 200)) }, bar)
	end
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.88), Size = UDim2.fromScale(0.12, 0.06), BackgroundColor3 = RED, BorderSizePixel = 0 }, holder)
	text(body, "VANTAGE", TITLE, UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.16), WHITE, Enum.TextXAlignment.Center)
	text(body, "NO LEGIONARY LEFT BEHIND", BODY, UDim2.fromScale(0, 0.88), UDim2.fromScale(1, 0.08), DIM, Enum.TextXAlignment.Center)
	return {}
end
function BUILD.Modes(part)
	local body = shell(part, "OPERATIONS ROSTER", "GAME MODES")
	local list = {}
	for id, m in MatchConfig.Modes or {} do
		table.insert(list, { Id = id, Name = m.Name or id, Live = m.Live == true })
	end
	table.sort(list, function(a, b)
		if a.Live ~= b.Live then return a.Live end
		return a.Name < b.Name
	end)
	local n = math.max(#list, 1)
	for i, e in list do
		local row = new("Frame", { Position = UDim2.fromScale(0, (i - 1) / n), Size = UDim2.new(1, 0, 1 / n, -8), BackgroundColor3 = Color3.fromRGB(22, 27, 38), BackgroundTransparency = 0.15, BorderSizePixel = 0 }, body)
		new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = e.Live and BLUE or Color3.fromRGB(60, 70, 88), BorderSizePixel = 0 }, row)
		text(row, e.Name, BODY, UDim2.new(0, 22, 0.2, 0), UDim2.new(0.62, 0, 0.6, 0), e.Live and WHITE or DIM)
		local pill = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0.26, 0, 0.62, 0), BackgroundColor3 = e.Live and Color3.fromRGB(20, 70, 160) or Color3.fromRGB(40, 46, 58), BorderSizePixel = 0 }, row)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
		text(pill, e.Live and "LIVE" or "COMING SOON", BODY, UDim2.fromScale(0.06, 0.18), UDim2.fromScale(0.88, 0.64), e.Live and WHITE or DIM, Enum.TextXAlignment.Center)
	end
	return {}
end
function BUILD.Level(part)
	local body = shell(part, "TOP LEGIONARIES", "THIS SERVER  ·  LEVEL")
	return { Body = body }
end
function BUILD.Streak(part)
	local body = shell(part, "WIN STREAK", "THIS SERVER  ·  BEST")
	return { Body = body }
end
function BUILD.Ladder(part)
	local body = shell(part, "RANKED LADDER", "GLOBAL  ·  TOP 10", GOLD)
	return { Body = body }
end
function BUILD.Tiers(part)
	local body = shell(part, "RANK TIERS", "RANKED DEATHMATCH")
	local ranks = RankedConfig.Ranks or {}
	local per = (RankedConfig.TierRP or 100) * (RankedConfig.TiersPerRank or 3)
	local n = #ranks
	for i, r in ranks do
		local col = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale((i - 1) / n, 0), Size = UDim2.fromScale(1 / n, 1) }, body)
		if r.Badge then
			local img = new("ImageLabel", { BackgroundTransparency = 1, Image = r.Badge, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.86, 0.55), ScaleType = Enum.ScaleType.Fit }, col)
			if r.Tint then img.ImageColor3 = r.Tint end
		end
		text(col, string.upper(r.Id), BODY, UDim2.fromScale(0.04, 0.62), UDim2.fromScale(0.92, 0.13), r.Color or WHITE, Enum.TextXAlignment.Center)
		local rp = if i == n then (RankedConfig.LegendRP or 0) else (i - 1) * per
		text(col, (i == n and "TOP 100 · " or "") .. rp .. " RP", MED, UDim2.fromScale(0.04, 0.78), UDim2.fromScale(0.92, 0.1), DIM, Enum.TextXAlignment.Center)
	end
	return {}
end
function BUILD.Season(part)
	local name = seasonCfg and seasonCfg.Name or "Season 1"
	local body = shell(part, string.upper(name), "BATTLEPASS")
	local tiers = seasonCfg and seasonCfg.MaxTier or 50
	text(body, tiers .. " TIERS OF REWARDS", TITLE, UDim2.fromScale(0, 0.04), UDim2.fromScale(1, 0.18), WHITE)
	text(body, "Every match earns EXP toward the pass. Open BATTLEPASS from the menu to claim tiers.", MED, UDim2.fromScale(0, 0.3), UDim2.fromScale(1, 0.12), DIM)
	local ends = text(body, "", BODY, UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.14), BLUE)
	return { Ends = ends }
end

local function setup(part)
	if not part:IsDescendantOf(lobby) then return end
	local kind = part:GetAttribute("Board")
	local f = BUILD[kind]
	if not f then return end
	local ok, refs = pcall(f, part)
	if ok then
		boards[part] = { Kind = kind, Refs = refs }
	else
		warn("[VANTAGE] LobbyBoards " .. tostring(kind) .. ": " .. tostring(refs))
	end
end
for _, p in CS:GetTagged("LobbyBoard") do setup(p) end
CS:GetInstanceAddedSignal("LobbyBoard"):Connect(setup)

-- podium: top 3 of the ranked ladder posed in the Hall of Records
local slots = {}
for _, d in lobby:GetDescendants() do
	if d.Name == "PodiumSlot" and d:GetAttribute("Rank") then
		slots[d:GetAttribute("Rank")] = d
	end
end
local posed = {} -- rank -> { UserId, Model }
local IDLE = "rbxassetid://507766666"
local function pose(rank, entry)
	local slot = slots[rank]
	if not slot then return end
	local cur = posed[rank]
	if cur and entry and cur.UserId == entry.U then return end
	if cur and cur.Model then cur.Model:Destroy() end
	posed[rank] = nil
	if not entry then return end
	posed[rank] = { UserId = entry.U }
	task.spawn(function()
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromUserId(entry.U)
		end)
		if not ok or not model or not posed[rank] or posed[rank].UserId ~= entry.U then
			if ok and model then model:Destroy() end
			return
		end
		model.Name = "Podium_" .. rank
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = (d == root)
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
		local hip = hum and hum.HipHeight or 2
		local rootH = root and root.Size.Y / 2 or 1
		local look = -lobby:GetPivot().Position + slot.Position
		local facing = Vector3.new(-1, 0, 0) -- toward the atrium
		local base = slot.Position + Vector3.new(0, slot.Size.Y / 2 + hip + rootH, 0)
		model:PivotTo(CFrame.lookAt(base, base + facing))
		model.Parent = slot.Parent
		local bb = new("BillboardGui", { Size = UDim2.fromOffset(220, 56), StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0), AlwaysOnTop = false, MaxDistance = 70, LightInfluence = 0 }, root or model)
		text(bb, entry.N or "?", BODY, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55), rank == 1 and GOLD or WHITE, Enum.TextXAlignment.Center)
		text(bb, rankName(entry.RP or 0) .. "  ·  " .. tostring(entry.RP or 0) .. " RP", MED, UDim2.fromScale(0, 0.58), UDim2.fromScale(1, 0.38), DIM, Enum.TextXAlignment.Center)
		if hum then
			local animator = hum:FindFirstChildOfClass("Animator") or new("Animator", {}, hum)
			local a = new("Animation", { AnimationId = IDLE }, model)
			local ok2, track = pcall(function() return animator:LoadAnimation(a) end)
			if ok2 and track then track.Looped = true track:Play() end
		end
		if posed[rank] and posed[rank].UserId == entry.U then
			posed[rank].Model = model
		else
			model:Destroy()
		end
	end)
end

local lastTop = ""
local function ladder()
	local raw = V:GetAttribute("RankedTop") or "[]"
	local ok, top = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(top) ~= "table" then top = {} end
	return top, raw
end

local function serverList(key, fmt, minValue)
	local list = {}
	for _, p in Players:GetPlayers() do
		local v = p:GetAttribute(key) or 0
		if v >= (minValue or 0) then
			table.insert(list, { Name = p.DisplayName, V = v, Tie = p:GetAttribute("LevelXP") or 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.V ~= b.V then return a.V > b.V end
		return a.Tie > b.Tie
	end)
	for _, e in list do e.Value = fmt(e.V) end
	return list
end

local function refresh()
	local phase = attr("Phase", "Idle")
	local mode = attr("Mode", "")
	local qTotal = 0
	for id in MatchConfig.Modes or {} do qTotal += attr("Queue_" .. id, 0) end
	local inLobby = 0
	for _, p in Players:GetPlayers() do if p:GetAttribute("InLobby") then inLobby += 1 end end
	local top, raw = ladder()
	for part, b in boards do
		if not part.Parent then
			boards[part] = nil
			continue
		end
		local r = b.Refs
		if b.Kind == "Welcome" then
			r.Online.Text = tostring(#Players:GetPlayers())
		elseif b.Kind == "Status" then
			local live = phase == "Live" or phase == "Overtime"
			if phase == "Idle" then
				r.Phase.Text = qTotal > 0 and "ASSEMBLING SQUADS" or "STANDING BY"
				r.Phase.TextColor3 = WHITE
			elseif live then
				r.Phase.Text = attr("Overtime", false) and "SUDDEN DEATH" or "MATCH LIVE"
				r.Phase.TextColor3 = attr("Overtime", false) and GOLD or Color3.fromRGB(110, 230, 140)
			else
				r.Phase.Text = string.upper(phase)
				r.Phase.TextColor3 = WHITE
			end
			r.Mode.Text = (mode ~= "" and modeName(mode) or modeName("TDM")) .. "  ·  " .. string.upper(attr("MapName", "LIVE FIRE"))
			local showScore = phase ~= "Idle"
			r.Blue.Text = showScore and tostring(attr("BlueScore", 0)) or "—"
			r.Red.Text = showScore and tostring(attr("RedScore", 0)) or "—"
			r.Time.Text = showScore and (clock(attr("TimeLeft", 0)) .. " REMAINING  ·  FIRST TO " .. tostring(attr("ScoreLimit", 150))) or "NO MATCH IN PROGRESS"
			r.Queue.Text = "IN QUEUE  " .. qTotal
			r.Lobby.Text = "ON DECK  " .. inLobby
		elseif b.Kind == "Level" then
			rows(r.Body, serverList("Level", function(v) return "LV " .. v end, 1), 8)
		elseif b.Kind == "Streak" then
			rows(r.Body, serverList("BestStreak", function(v) return v .. (v == 1 and " WIN" or " WINS") end, 1), 8, "WIN A MATCH TO START A STREAK")
		elseif b.Kind == "Ladder" then
			if b.Last ~= raw then
				b.Last = raw
				local list = {}
				for i, e in top do
					if i > 10 then break end
					local rn, rc = rankName(e.RP or 0)
					table.insert(list, { Name = e.N or "?", Value = tostring(e.RP or 0) .. " RP", Sub = rn, SubColor = rc })
				end
				rows(r.Body, list, 10, "PLAY RANKED DEATHMATCH TO ENTER THE LADDER")
			end
		elseif b.Kind == "Season" then
			local ends = seasonCfg and seasonCfg.EndsAt
			if ends then
				local left = math.max(0, ends - os.time())
				r.Ends.Text = string.format("SEASON ENDS IN %dD %dH", left // 86400, (left % 86400) // 3600)
			else
				r.Ends.Text = ""
			end
		end
	end
	if raw ~= lastTop then
		lastTop = raw
		for rank = 1, 3 do pose(rank, top[rank]) end
	end
end

while true do
	local ok, err = pcall(refresh)
	if not ok then warn("[VANTAGE] LobbyBoards refresh: " .. tostring(err)) end
	task.wait(2)
end
