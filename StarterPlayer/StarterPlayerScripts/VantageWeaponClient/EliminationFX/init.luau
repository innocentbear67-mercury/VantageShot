--[[
	VANTAGE — EliminationFX (client)
	Presents eliminations the server has already decided (Remotes.Elimination):
	  "Confirm" — only the player who earned it, as one coordinated moment:
	      golden screen burst (edge flash, centre shockwave, flakes, drifting fragments)
	      + the callout's own emblem (Lines[...].Icon) impacting below the crosshair + callout + victim name
	      + exactly one announcer line (Announcer) + a bright ring on headshots
	  "World"   — everyone else nearby: the small in-world insignia above the eliminated player
	Callout = the highest-priority line that applies (EliminationConfig.Announcer.Lines):
	streak milestone > multikill > headshot > knife (FATALITY) > ELIMINATED.
	Nothing here blocks input; the crosshair area stays clear (the burst starts outside it).
	Effects are child modules (Insignia = default); see Insignia for the interface.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ElimConfig = require(ReplicatedStorage.Vantage.Elimination.EliminationConfig)
local Announcer = require(script.Parent.Announcer)
local COL = ElimConfig.Colors
local GOLD = ElimConfig.Gold
local LINES = ElimConfig.Announcer.Lines

local V2 = Vector2.new
local CK = ColorSequenceKeypoint.new

local EliminationFX = {}
local effectModules = {}
for _, m in script:GetChildren() do
	if m:IsA("ModuleScript") then
		effectModules[m.Name] = require(m)
	end
end

local gui: ScreenGui = nil
local layer: Frame = nil -- full-screen burst layer (under the confirmation)
local current = nil -- the confirmation on screen
local sfxGroup: SoundGroup? = nil

local TEXT_GOLD = ColorSequence.new({ CK(0, GOLD.Glint), CK(0.45, GOLD.Light), CK(0.75, GOLD.Base), CK(1, GOLD.Deep) })

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function tween(i, t, props, style, dir)
	local tw = TweenService:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function EliminationFX.EffectFor(id: any)
	return (type(id) == "string" and effectModules[id]) or effectModules[ElimConfig.DefaultEffect]
end

-- one callout per elimination: the highest priority that applies
function EliminationFX.ChooseLine(info)
	local best = LINES.Eliminated
	local function consider(line)
		if line and line.Priority > best.Priority then
			best = line
		end
	end
	if info.Special then
		consider(LINES.Fatality)
	end
	if info.Headshot then
		consider(LINES.Headshot)
	end
	local multi = tonumber(info.Multi) or 0
	if multi == 2 then
		consider(LINES.DoubleKill)
	elseif multi == 3 then
		consider(LINES.TripleKill)
	elseif multi >= 4 then
		consider(LINES.MultiKill)
	end
	local milestone = ElimConfig.StreakMilestones[tonumber(info.Streak) or 0]
	if milestone then
		consider(LINES[milestone])
	end
	return best
end

-- emblem art: the streak tier (see ElimConfig.TierIcons); double / triple kills keep their badge
function EliminationFX.IconFor(info, line): string
	local I, T = ElimConfig.TierIcons, ElimConfig.TierStreak
	if not I then
		return line.Icon
	end
	if line == LINES.DoubleKill then
		return I.Double
	elseif line == LINES.TripleKill then
		return I.Triple
	end
	local n = tonumber(info.Streak) or 1
	if n >= T.Mythic then
		return I.Mythic
	elseif n >= T.Premium then
		return I.Premium
	elseif n >= T.Legendary then
		return I.Legendary
	elseif n >= T.Stylized then
		return I.Stylized
	elseif info.Headshot then
		return I.HeadKill
	elseif info.Special then
		return I.Kill
	end
	return I.Clean
end

local function playSound(spec)
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume or 0.6
	s.PlaybackSpeed = spec.Speed or 1
	s.SoundGroup = sfxGroup
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

local function fitScale(): number
	local vp = Workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.6, 1.25)
end

-- 2026-11-16 clean centre: a kill is confirmed by the red crosshair marker + kill cue (HitFeedback).
-- No centre text, no screen burst; the announcer speaks only for exceptional lines (multikills,
-- streaks, fatality) so a plain kill stays one sound. ElimConfig.CentreConfirm = true restores the
-- old centre callout below (showConfirmLegacy).
local showConfirmLegacy
local function showConfirm(info, effect)
	if ElimConfig.CentreConfirm then
		return showConfirmLegacy(info, effect)
	end
	local line = EliminationFX.ChooseLine(info)
	if line ~= LINES.Eliminated and line ~= LINES.Headshot then
		task.delay(0.12, Announcer.Play, line) -- after the kill cue, never on top of it
	end
end

function showConfirmLegacy(info, effect)
	local line = EliminationFX.ChooseLine(info)
	local tier = math.max(line.Tier, if info.Headshot then 2 else 1)
	local life = ElimConfig.ConfirmTime + (tier - 1) * 0.25

	effect.Screen(layer, tier)
	if current then
		current:Destroy() -- a rapid follow-up kill replaces the previous confirmation
	end
	local top = 0 -- HUD v5: medal sits above the crosshair (Hypershot), see Position below
	local holder = new("Frame", { Name = "Confirm", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.19, top), Size = UDim2.fromOffset(380, 200), BackgroundTransparency = 1 }, gui)
	new("UIScale", { Scale = fitScale() }, holder)
	current = holder
	local fades = {} -- { instance, property, shown value } faded together at the end

	-- insignia (2026-11-14: off by default, the animated crosshair kill marker is the one emblem;
	-- ElimConfig.ShowEmblem = true brings this second one back)
	local y = 0
	if ElimConfig.ShowEmblem then
		local size = if tier >= 3 then 118 elseif tier == 2 then 106 else 96
		local box = new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(190, 0), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, holder)
		local icon = effect.Build(box, line.Glow or (if tier >= 2 then GOLD.Light else GOLD.Base), tier, EliminationFX.IconFor(info, line))
		effect.Impact(icon, tier, box)
		table.insert(fades, { icon.Root, "GroupTransparency", 0 })
		y = size + 2
	end

	-- small HEADSHOT tag when a bigger callout (multikill / streak) took the line
	if info.Headshot and line ~= LINES.Headshot then
		local tag = new("TextLabel", { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(190, y), Size = UDim2.fromOffset(200, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "HEADSHOT", TextColor3 = GOLD.Light, TextSize = 12 }, holder)
		table.insert(fades, { tag, "TextTransparency", 0 })
		y += 15
	end

	-- callout: gold metal type, punches in a beat after the insignia lands
	local callout = new("TextLabel", { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(190, y), Size = UDim2.fromOffset(380, 34), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = line.Text, TextColor3 = Color3.new(1, 1, 1), TextSize = if tier >= 3 then 31 else 26, TextTransparency = 1 }, holder)
	new("UIGradient", { Color = TEXT_GOLD, Rotation = 90 }, callout)
	local cs = new("UIStroke", { Color = COL.Ink, Thickness = 1.6, Transparency = 1 }, callout)
	local cScale = new("UIScale", { Scale = 1.45 }, callout)
	table.insert(fades, { callout, "TextTransparency", 0 })
	table.insert(fades, { cs, "Transparency", 0.25 })
	task.delay(0.08, function()
		tween(callout, 0.12, { TextTransparency = 0 })
		tween(cs, 0.12, { Transparency = 0.25 })
		tween(cScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if tier >= 3 then
		-- streak flare: a hot line racing out behind the callout
		local flare = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(190, y + 17), Size = UDim2.fromOffset(0, 2), BackgroundColor3 = GOLD.Glint, BorderSizePixel = 0, ZIndex = 0 }, holder)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, flare)
		tween(flare, 0.3, { Size = UDim2.fromOffset(340, 2) }, Enum.EasingStyle.Quart)
		task.delay(0.3, function()
			tween(flare, 0.5, { BackgroundTransparency = 1 })
		end)
	end
	y += 36

	-- —— VICTIM NAME ——
	local row = new("Frame", { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(190, y + 6), Size = UDim2.fromOffset(380, 18), BackgroundTransparency = 1 }, holder)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local function rule(order)
		local r = new("Frame", { Size = UDim2.fromOffset(28, 1), BackgroundColor3 = GOLD.Base, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order }, row)
		table.insert(fades, { r, "BackgroundTransparency", 0.25 })
	end
	rule(1)
	local name = new("TextLabel", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = string.upper(tostring(info.VictimName or "ENEMY")), TextColor3 = COL.Neutral, TextSize = 15, TextTransparency = 1, LayoutOrder = 2 }, row)
	new("UIStroke", { Color = COL.Ink, Thickness = 1, Transparency = 0.4 }, name)
	table.insert(fades, { name, "TextTransparency", 0 })
	rule(3)
	task.delay(0.14, function()
		tween(row, 0.22, { Position = UDim2.fromOffset(190, y) })
		for _, f in fades do
			if f[1] == name or (f[1]:IsA("Frame") and f[1].Parent == row) then
				tween(f[1], 0.22, { [f[2]] = f[3] })
			end
		end
	end)

	-- out: everything lifts slightly and dissolves together
	task.delay(life - 0.35, function()
		if current ~= holder then
			return
		end
		tween(holder, 0.35, { Position = UDim2.new(0.5, 0, 0.19, top - 8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, f in fades do
			if f[1].Parent then
				tween(f[1], 0.35, { [f[2]] = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
	end)
	Debris:AddItem(holder, life + 0.1)

	-- audio: weapon Kill cue (Loadout) + one announcer line + a ring on headshots
	Announcer.Play(line)
	if info.Headshot then
		-- (2026-11-17) headshot ring removed: HitFeedback's HeadKill cue covers it
	end
end

local function onElimination(kind: any, info: any)
	if type(info) ~= "table" then
		return
	end
	local effect = EliminationFX.EffectFor(info.Effect)
	if kind == "Confirm" then
		showConfirm(info, effect)
		if typeof(info.Position) == "Vector3" then
			local line = EliminationFX.ChooseLine(info)
			pcall(effect.World, info.Position, line.Glow or GOLD.Base, info.Headshot == true, EliminationFX.IconFor(info, line))
		end
	elseif kind == "World" and typeof(info.Position) == "Vector3" then
		local cam = Workspace.CurrentCamera
		if (cam.CFrame.Position - info.Position).Magnitude <= ElimConfig.WorldMaxDistance then
			local line = if info.Headshot then LINES.Headshot else LINES.Eliminated
			pcall(effect.World, info.Position, COL[tostring(info.KillerTeam)] or COL.Neutral, info.Headshot == true, EliminationFX.IconFor(info, line))
		end
	end
end

function EliminationFX.Start(effects, hud)
	sfxGroup = effects.EffectsGroup
	Announcer.Init(sfxGroup)
	hud.SuppressKillBanner = true -- the confirmation replaces the old text banner
	gui = new("ScreenGui", { Name = "VantageElimination", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6 }, Players.LocalPlayer:WaitForChild("PlayerGui"))
	layer = new("Frame", { Name = "Burst", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 }, gui)
	ReplicatedStorage.Vantage.Remotes:WaitForChild("Elimination").OnClientEvent:Connect(onElimination)
	-- load the emblem art up front so the first kill never shows an empty frame
	task.spawn(function()
		local images = {}
		for _, line in LINES do
			if line.Icon and line.Icon ~= "" then
				local img = Instance.new("ImageLabel")
				img.Image = line.Icon
				table.insert(images, img)
			end
		end
		for _, id in ElimConfig.TierIcons or {} do
			local img = Instance.new("ImageLabel")
			img.Image = id
			table.insert(images, img)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, images)
	end)
end

return EliminationFX
