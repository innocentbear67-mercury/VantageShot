--[[
	VANTAGE — TeamOutlines (client)
	Friend / foe identification on every other character (players and squad bots).
	  • Highlight outlines, DepthMode = Occluded: only visible parts are outlined, nobody is
		revealed through walls. Enemies glow hot red, teammates get a solid cyan line.
		Obeys the "Team outlines" setting. (Roblox allows 31 active Highlights per client.)
	  • 2026-11-19 friend / foe pass:
		  - Teammates: a cyan name + ▼ overhead, through walls (enemies never get one).
		  - Squad bots are repainted per viewer: blue-grey on your side, red on the other.
			(The server tints them Blue/Red by team, which said nothing about sides.)
		  - Enemies: a HyperShot-style name + shield + health bar overhead, only when they're
			within BAR_RANGE studs and in line of sight (head or torso), or for BAR_HURT_TIME s
			after they take damage within BAR_HURT_RANGE.
		Overheads are drawn in a ScreenGui ("VantageOverheads") projected from the head every
		frame (same approach as the aircraft HUD tags), so they keep a fixed on-screen size.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local COLORS = {
	Blue = { Outline = Color3.fromRGB(70, 200, 255), Fill = Color3.fromRGB(40, 140, 255) },
	Red = { Outline = Color3.fromRGB(255, 104, 60), Fill = Color3.fromRGB(255, 60, 50) },
}
local OUTLINE_T = 0.12
local FILL_T = 0.9
-- once you're on a team, outlines go by relationship, not colour
local ENEMY = { Outline = Color3.fromRGB(255, 40, 64), Fill = Color3.fromRGB(255, 30, 60), OutlineT = 0, FillT = 0.6 }
local FRIEND = { Outline = Color3.fromRGB(80, 220, 255), Fill = Color3.fromRGB(40, 150, 255), OutlineT = 0, FillT = 0.8 }

local MARKER = Color3.fromRGB(80, 220, 255)
local MARKER_MAX = 600 -- studs
local BOT_PAINT = {
	Friend = { Body = Color3.fromRGB(58, 110, 190), Head = Color3.fromRGB(165, 195, 225) },
	Enemy = { Body = Color3.fromRGB(165, 36, 44), Head = Color3.fromRGB(205, 150, 140) },
}
local BAR_RANGE = 110 -- studs: enemy bars appear inside this
local BAR_HURT_RANGE = 250 -- studs: a hurt enemy shows its bar this far out ...
local BAR_HURT_TIME = 2.5 -- ... for this long
local BAR_W = 108
local BAR = {
	Back = Color3.fromRGB(18, 20, 28),
	Health = Color3.fromRGB(255, 72, 72),
	HealthLow = Color3.fromRGB(200, 28, 40),
	Shield = Color3.fromRGB(80, 220, 255),
	Trail = Color3.fromRGB(255, 255, 255),
}
local HEAD_LIFT = 1.4 -- studs above the head centre the overhead's bottom edge sits

local TRAIL_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3)
local FILL_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Linear)
local FADE_IN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ─── overhead widgets ──────────────────────────────────────────────────────
local screen: ScreenGui? = nil
local function overheadGui(): ScreenGui
	if screen and screen.Parent then
		return screen
	end
	local g = Instance.new("ScreenGui")
	g.Name = "VantageOverheads"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = -5 -- under the HUD
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen = g
	return g
end

local function stroke(parent: Instance, thickness: number, border: boolean?)
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = thickness
	st.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	st.Parent = parent
	return st
end

local function label(parent: Instance, props): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextStrokeTransparency = 1
	for k, v in props do
		(t :: any)[k] = v
	end
	stroke(t, 2)
	t.Parent = parent
	return t
end

local function round(f: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
end

local function pill(parent: Instance, name: string, y: number, h: number): (Frame, Frame, Frame)
	local back = Instance.new("Frame")
	back.Name = name
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, y)
	back.Size = UDim2.fromOffset(BAR_W, h)
	back.BackgroundColor3 = BAR.Back
	back.BackgroundTransparency = 0.1
	back.BorderSizePixel = 0
	round(back)
	stroke(back, 2, true)
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.BorderSizePixel = 0
	trail.BackgroundColor3 = BAR.Trail
	trail.Size = UDim2.fromScale(1, 1)
	round(trail)
	trail.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	round(fill)
	fill.Parent = back
	local gloss = Instance.new("Frame") -- glossy top half, like the HUD pills
	gloss.Name = "Gloss"
	gloss.BorderSizePixel = 0
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.7
	gloss.Position = UDim2.fromScale(0.03, 0.08)
	gloss.Size = UDim2.fromScale(0.94, 0.4)
	round(gloss)
	gloss.Parent = fill
	back.Parent = parent
	return back, fill, trail
end

local function makeMarker(): Frame
	local f = Instance.new("Frame")
	f.Name = "FriendMarker"
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Size = UDim2.fromOffset(160, 36)
	f.BackgroundTransparency = 1
	f.Visible = false
	label(f, { Name = "Label", Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = MARKER })
	label(f, { Name = "Chevron", Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBlack, Text = "▼", TextSize = 17, TextColor3 = MARKER })
	f.Parent = overheadGui()
	return f
end

local function makeBar()
	local g = Instance.new("CanvasGroup")
	g.Name = "EnemyBar"
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Size = UDim2.fromOffset(BAR_W + 16, 46)
	g.BackgroundTransparency = 1
	g.GroupTransparency = 1
	g.Visible = false
	local name = label(g, { Name = "Label", Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = Color3.new(1, 1, 1) })
	local sBack, sFill, sTrail = pill(g, "Shield", 21, 7)
	sFill.BackgroundColor3 = BAR.Shield
	local _, hFill, hTrail = pill(g, "Health", 32, 11)
	hFill.BackgroundColor3 = BAR.Health
	g.Parent = overheadGui()
	return {
		Gui = g, Label = name,
		ShieldBack = sBack, ShieldFill = sFill, ShieldTrail = sTrail,
		HealthFill = hFill, HealthTrail = hTrail,
		Enemy = false, Shown = false, HurtUntil = 0, LastHp = nil, LastSh = nil,
	}
end

local function setFrac(fill: Frame, trail: Frame, frac: number, instant: boolean?)
	frac = math.clamp(frac, 0, 1)
	-- only react to real changes: shield recharge ticks would otherwise restart the trail forever
	local last = fill:GetAttribute("Goal")
	if not instant and last ~= nil and math.abs(last - frac) < 1e-3 then
		return
	end
	fill:SetAttribute("Goal", frac)
	local goal = UDim2.fromScale(frac, 1)
	fill.Visible = frac > 0.001
	if instant then
		fill.Size, trail.Size = goal, goal
		return
	end
	TweenService:Create(fill, FILL_INFO, { Size = goal }):Play()
	if trail.Size.X.Scale < frac then
		trail.Size = goal -- healing: the trail never lags behind upward
	else
		TweenService:Create(trail, TRAIL_INFO, { Size = goal }):Play()
	end
end

local function displayName(character: Model): string
	local plr = Players:GetPlayerFromCharacter(character)
	if plr then
		return plr.DisplayName
	end
	return tostring(character:GetAttribute("DisplayName") or character.Name)
end

local function paintBot(character: Model, friend: boolean)
	if Players:GetPlayerFromCharacter(character) or not character:GetAttribute("SquadBot") then
		return
	end
	local c = if friend then BOT_PAINT.Friend else BOT_PAINT.Enemy
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Color = if p.Name == "Head" then c.Head else c.Body
		end
	end
end

-- ─── module ───────────────────────────────────────────────────────────────
local TeamOutlines = {}
TeamOutlines.__index = TeamOutlines

function TeamOutlines.new(settings)
	local self = setmetatable({}, TeamOutlines)
	self.Settings = settings
	self.Enabled = settings:Get("TeamOutlines")
	self.Tracked = {} -- character -> { Highlight, Marker, Bar, Conns, Friend, Head }
	local lp = Players.LocalPlayer

	local function teamNameFor(character: Model): string?
		local plr = Players:GetPlayerFromCharacter(character)
		if plr then
			return plr.Team and plr.Team.Name or nil
		end
		return character:GetAttribute("Team") -- squad bots / training dummies
	end

	local function refresh(character: Model)
		local rec = self.Tracked[character]
		if not rec then
			return
		end
		local team = teamNameFor(character)
		local mine = if lp.Team and not lp.Neutral then lp.Team.Name else nil
		local colors = team and COLORS[team]
		if mine and team then
			colors = if tostring(team) == mine then FRIEND else ENEMY
		elseif mine and character:GetAttribute("Team") == nil and not Players:GetPlayerFromCharacter(character) then
			colors = nil -- an unteamed training dummy: no outline
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		local alive = hum ~= nil and hum.Health > 0
		local h = rec.Highlight
		if colors then
			h.OutlineColor = colors.Outline
			h.FillColor = colors.Fill
			h.OutlineTransparency = colors.OutlineT or OUTLINE_T
			h.FillTransparency = colors.FillT or FILL_T
		end
		h.Enabled = self.Enabled and colors ~= nil and alive

		local friend = mine ~= nil and team ~= nil and tostring(team) == mine
		local enemy = mine ~= nil and team ~= nil and not friend
		if mine and team then
			paintBot(character, friend)
		end
		rec.Head = character:FindFirstChild("Head")
		local nm = string.upper(displayName(character))
		rec.Friend = friend and alive and rec.Head ~= nil
		local ml = rec.Marker:FindFirstChild("Label") :: TextLabel?
		if ml then
			ml.Text = nm
		end
		local bar = rec.Bar
		bar.Label.Text = nm
		bar.Enemy = enemy and alive and rec.Head ~= nil
		if not bar.Enemy then
			bar.Shown = false
			bar.Gui.Visible = false
			bar.Gui.GroupTransparency = 1
		end
	end
	self._refresh = refresh

	local function track(character: Model)
		if self.Tracked[character] or (lp.Character == character) then
			return
		end
		local h = Instance.new("Highlight")
		h.Name = "VantageTeamOutline"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.OutlineTransparency = OUTLINE_T
		h.FillTransparency = FILL_T
		h.Enabled = false
		h.Adornee = character
		h.Parent = character
		local rec = { Highlight = h, Conns = {}, Marker = makeMarker(), Bar = makeBar(), Friend = false }
		self.Tracked[character] = rec

		-- enemy bar values: health + shield, with a white damage trail
		local function values(instant: boolean?)
			local hm = character:FindFirstChildOfClass("Humanoid")
			if not hm then
				return
			end
			local bar = rec.Bar
			local hp = hm.Health / math.max(1, hm.MaxHealth)
			local maxSh = tonumber(character:GetAttribute("MaxShield")) or 0
			local sh = if maxSh > 0 then (tonumber(character:GetAttribute("Shield")) or 0) / maxSh else 0
			bar.ShieldBack.Visible = maxSh > 0
			if (bar.LastHp and hp < bar.LastHp - 1e-3) or (bar.LastSh and sh < bar.LastSh - 1e-3) then
				bar.HurtUntil = os.clock() + BAR_HURT_TIME
			end
			bar.LastHp, bar.LastSh = hp, sh
			bar.HealthFill.BackgroundColor3 = if hp <= 0.3 then BAR.HealthLow else BAR.Health
			setFrac(bar.HealthFill, bar.HealthTrail, hp, instant)
			setFrac(bar.ShieldFill, bar.ShieldTrail, sh, instant)
		end

		local hum = character:WaitForChild("Humanoid", 10)
		if hum then
			table.insert(rec.Conns, (hum :: Humanoid).HealthChanged:Connect(function()
				refresh(character)
				values()
			end))
		end
		table.insert(rec.Conns, character:GetAttributeChangedSignal("Team"):Connect(function()
			refresh(character)
		end))
		table.insert(rec.Conns, character:GetAttributeChangedSignal("Shield"):Connect(function()
			values()
		end))
		table.insert(rec.Conns, character:GetAttributeChangedSignal("MaxShield"):Connect(function()
			values()
		end))
		table.insert(rec.Conns, character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(game) then
				for _, c in rec.Conns do
					c:Disconnect()
				end
				rec.Marker:Destroy()
				rec.Bar.Gui:Destroy()
				self.Tracked[character] = nil
			end
		end))
		refresh(character)
		values(true)
		-- squad bots get their server tint and DisplayName just after spawning: refresh once it lands
		if not Players:GetPlayerFromCharacter(character) then
			table.insert(rec.Conns, character:GetAttributeChangedSignal("DisplayName"):Connect(function()
				refresh(character)
			end))
			for _, t in { 0.5, 1.5, 3 } do
				task.delay(t, function()
					if self.Tracked[character] == rec then
						refresh(character)
					end
				end)
			end
		end
	end

	-- line of sight + range for enemy bars, 10x a second
	local losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Exclude
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local eye = cam.CFrame.Position
		local now = os.clock()
		for character, rec in self.Tracked do
			local bar = rec.Bar
			if bar.Enemy then
				local head = rec.Head :: BasePart?
				local want = false
				if head and head.Parent then
					local dist = (head.Position - eye).Magnitude
					if dist <= BAR_RANGE or (now < bar.HurtUntil and dist <= BAR_HURT_RANGE) then
						losParams.FilterDescendantsInstances = { character, lp.Character :: any }
						-- visible if the head or the torso can be seen (thin frames shouldn't hide it)
						for _, part in { head, character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart") } do
							local hit = Workspace:Raycast(eye, (part :: BasePart).Position - eye, losParams)
							if hit == nil or hit.Instance.Transparency >= 0.5 then
								want = true
								break
							end
						end
					end
				end
				if want ~= bar.Shown then
					bar.Shown = want
					if want then
						TweenService:Create(bar.Gui, FADE_IN, { GroupTransparency = 0 }):Play()
					else
						TweenService:Create(bar.Gui, FADE_OUT, { GroupTransparency = 1 }):Play()
					end
				end
			end
		end
	end)

	-- place the overheads every frame (projected from the head)
	RunService:BindToRenderStep("VantageOverheads", Enum.RenderPriority.Camera.Value + 2, function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local eye = cam.CFrame.Position
		for _, rec in self.Tracked do
			local head = rec.Head :: BasePart?
			local bar = rec.Bar
			local wantMarker = rec.Friend
			local wantBar = bar.Enemy and (bar.Shown or bar.Gui.GroupTransparency < 0.99)
			if (wantMarker or wantBar) and head and head.Parent then
				local top = head.Position + Vector3.new(0, HEAD_LIFT, 0)
				local v, onScreen = cam:WorldToViewportPoint(top)
				local dist = (top - eye).Magnitude
				local pos = UDim2.fromOffset(v.X, v.Y)
				local ok = onScreen and v.Z > 0
				rec.Marker.Visible = wantMarker and ok and dist <= MARKER_MAX
				rec.Marker.Position = pos
				bar.Gui.Visible = wantBar and ok
				bar.Gui.Position = pos
			else
				rec.Marker.Visible = false
				bar.Gui.Visible = false
			end
		end
	end)

	local function onPlayer(plr: Player)
		if plr == lp then
			return
		end
		plr.CharacterAdded:Connect(function(c)
			task.spawn(track, c)
		end)
		plr:GetPropertyChangedSignal("Team"):Connect(function()
			if plr.Character then
				refresh(plr.Character)
			end
		end)
		if plr.Character then
			task.spawn(track, plr.Character)
		end
	end
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	Players.PlayerAdded:Connect(onPlayer)
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		CollectionService:GetInstanceAddedSignal("VantageDummy"):Connect(function(m)
			task.spawn(track, m)
		end)
		for _, m in CollectionService:GetTagged("VantageDummy") do
			task.spawn(track, m)
		end
	end
	-- our own team change flips who is friend and who is enemy
	lp:GetPropertyChangedSignal("Team"):Connect(function()
		for c in self.Tracked do
			refresh(c)
		end
	end)
	settings.Changed:Connect(function(key)
		if key == "TeamOutlines" or key == "*" then
			self.Enabled = settings:Get("TeamOutlines")
			for c in self.Tracked do
				refresh(c)
			end
		end
	end)
	return self
end

return TeamOutlines
