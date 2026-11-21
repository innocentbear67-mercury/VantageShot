--[[
	VANTAGE — REQ feed (client). v4 "kill line" 2026-11-18 (HyperShot's normal kill reward):
	  • One line up and right of the crosshair: "<victim> +<REQ> [REQ]  +<ORD> [ORD]", replaced by
	    the next payout. Placement / sizes: RequisitionConfig.Feed (Line*).
	  • Chunky Fredoka One with a dark outline, red amount, REQ emblem after the amount.
	  • Motion: pop in (1.15 -> 1, 0.12 s), the amount counts up, holds Life, fades.
	  • Running total (emblem + balance) sits just above the ammo block.
	Only draws what the server sends (Remotes.ReqAward); the balance is the player attribute REQ.
	Tuning: ReplicatedStorage.Vantage.Requisition.RequisitionConfig.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("Requisition"):WaitForChild("RequisitionConfig"))
local Remote = Vantage:WaitForChild("Remotes"):WaitForChild("ReqAward") :: RemoteEvent
local F = Config.Feed

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

-- ─── v2 feedback (2026-11-14) ─────────────────────────────────────────────────────
-- Lines slam in from the right with an overshoot pop, the amount flashes white then settles
-- red while it counts up, the emblem spins in. A credit chime plays per line (follow-up lines a
-- step higher); awards inside COMBO_WINDOW of each other climb in pitch. The running total
-- punches, flashes red and drops a "+N" ghost.
-- 2026-11-14 v3: no bell / coin "ting" (it read as a kill sound). REQ is a fast rising whoosh
-- plus a short mechanical ratchet roll under the count-up: a "credits loading in" sound.
local WHOOSH_ID = "rbxassetid://9125648149" -- Magic Zoom Up Sharp Tubular Whoosh Fast Hiss (SFX)
local RATCHET_ID = "rbxassetid://9117613062" -- Plastic Ratchet Robot Arm Element 12 (SFX)
local COMBO_WINDOW = 2.5
-- 2026-11-16: the REQ sound waits until the kill cue (HitFeedback) has landed, and plays softer,
-- so a kill is one clear sound followed by a quiet secondary reward
local REQ_SOUND_DELAY, REQ_SOUND_VOLUME = 0.24, 0.55
local layerNow
local lastAward, combo = -10, 0
local function layer(id: string, volume: number, speed: number, stopAt: number?)
	task.delay(REQ_SOUND_DELAY, layerNow, id, volume * REQ_SOUND_VOLUME, speed, stopAt)
end
function layerNow(id: string, volume: number, speed: number, stopAt: number?)
	local snd = Instance.new("Sound")
	snd.SoundId = id
	snd.Volume = volume
	snd.PlaybackSpeed = speed
	local g = SoundService:FindFirstChild("VantageEffects")
	if g and g:IsA("SoundGroup") then
		snd.SoundGroup = g
	end
	snd.Parent = SoundService
	snd:Play()
	if stopAt then
		task.delay(stopAt, function()
			if snd.Parent then
				TweenService:Create(snd, TweenInfo.new(0.08), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(2, function()
		snd:Destroy()
	end)
end
local function chime(pitch: number, volume: number)
	-- 2026-11-17 (Hypershot): one short two-note coin blip, just after the kill cue
	local PING = "rbxasset://sounds/electronicpingshort.wav"
	layer(PING, 0.55 * volume, 2.0 * pitch, 0.25)
	task.delay(0.07, layer, PING, 0.5 * volume, 2.52 * pitch, 0.3)
end
local function tween(obj, t: number, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

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

-- ─── v4 "kill line" (2026-11-18): HyperShot's normal kill reward, frame by frame ──────────────
-- Studied from footage (v_v4ZBA_ZYo, 95.6 s / 383.7 s / 384.7 s): ONE line, "nickLexi23 +100 [coin]",
-- left edge ~190 px right of the crosshair and ~140 px above it (1080p). Name white in its own
-- case, amount yellow, same size (~32 px), coin a bit taller; thin dark outline + soft drop shadow,
-- no plate, no count-up. It slams in at ~2.2x and eases to 1x in ~0.45 s (scaled from its left
-- edge), holds, and is gone ~3 s after the kill. The next kill REPLACES it in the same spot.
-- Ours: "<victim> +<REQ of the kill> [REQ]  +<ORD> [ORD]" (headshot / melee bonus folded into the
-- one amount; XP shows on the level bar / results). Tuning: RequisitionConfig.Feed (Line*).
local gui = new("ScreenGui", { Name = "VantageReqFeed", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local holder = new("Frame", { Name = "Feed", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(10, 10) }, gui)
local scale = new("UIScale", {}, holder)
local LINE_FONT = Font.new(F.LineFont or "rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

local function place()
	local vs = (Workspace.CurrentCamera :: Camera).ViewportSize
	local s = math.max(0.5, vs.Y / 900) -- authored for a ~900 px tall view
	scale.Scale = s
	holder.Position = UDim2.new(0.5, (F.LineX or 158) * s, 0.5, (F.LineY or -117) * s)
end
place()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)

local function stroke(parent, th: number?)
	return new("UIStroke", { Color = F.Outline, Thickness = th or F.OutlineThickness, LineJoinMode = Enum.LineJoinMode.Round }, parent)
end
-- (also used by the running total below)
local function text(parent, props)
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		FontFace = FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in props do
		t[k] = v
	end
	stroke(t)
	return t
end
local function emblem(parent, px: number)
	if Config.Icon ~= "" then
		return new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), Image = Config.Icon, ScaleType = Enum.ScaleType.Fit }, parent)
	end
	local f = new("Frame", { BackgroundColor3 = Color3.fromRGB(196, 202, 212), Size = UDim2.fromOffset(px * 0.8, px * 0.8) }, parent)
	new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, f)
	new("UIStroke", { Color = F.Outline, Thickness = 2 }, f)
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), FontFace = FONT, Text = "R", TextScaled = true, TextColor3 = Color3.fromRGB(40, 90, 200) }, f)
	return f
end

local OrdCfg = nil
pcall(function()
	OrdCfg = require(Vantage:WaitForChild("Ordnance", 5):WaitForChild("OrdnanceConfig", 5))
end)
local ORD_COLOR = (OrdCfg and OrdCfg.Color) or Color3.fromRGB(255, 168, 46)
local SHADOW = Color3.fromRGB(0, 0, 0)

-- one row of the line; drawn twice: a soft shadow copy (offset) and the real one on top
local function row(parent, parts, shadow: boolean)
	local r = new("Frame", { Name = if shadow then "Shadow" else "Line", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Position = if shadow then UDim2.fromOffset(2, 3) else UDim2.fromOffset(0, 0), ZIndex = if shadow then 1 else 2 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, F.LineGap or 7), SortOrder = Enum.SortOrder.LayoutOrder }, r)
	for i, p in parts do
		if p.Text then
			local t = new("TextLabel", { LayoutOrder = i, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), FontFace = LINE_FONT, Text = p.Text, TextSize = p.Size, TextColor3 = if shadow then SHADOW else p.Color, TextTransparency = if shadow then 0.55 else 0, ZIndex = r.ZIndex }, r)
			if not shadow then
				new("UIStroke", { Color = F.Outline, Thickness = F.LineOutline or 2, Transparency = 0.15, LineJoinMode = Enum.LineJoinMode.Round }, t)
			end
		elseif p.Icon then
			local ic = p.Icon(r, p.Size)
			ic.LayoutOrder = i
			ic.ZIndex = r.ZIndex
			if shadow then
				if ic:IsA("ImageLabel") then
					ic.ImageColor3 = SHADOW
					ic.ImageTransparency = 0.55
				else
					ic.BackgroundTransparency = 1
					for _, d in ic:GetDescendants() do
						if d:IsA("GuiObject") then
							d.Visible = false
						elseif d:IsA("UIStroke") then
							d.Enabled = false
						end
					end
				end
			end
		elseif p.Gap then
			new("Frame", { LayoutOrder = i, BackgroundTransparency = 1, Size = UDim2.fromOffset(p.Gap, 2) }, r)
		end
	end
	return r
end

local current = nil
local seq = 0
local function fade(line)
	if not line.Parent then
		return
	end
	for _, d in line:GetDescendants() do
		if d:IsA("TextLabel") then
			tween(d, F.Fade, { TextTransparency = 1 })
		elseif d:IsA("ImageLabel") then
			tween(d, F.Fade, { ImageTransparency = 1 })
		elseif d:IsA("UIStroke") then
			tween(d, F.Fade, { Transparency = 1 })
		end
	end
	task.delay(F.Fade + 0.05, function()
		line:Destroy()
	end)
end

local function show(entries, extra, pitch: number)
	-- amount = every REQ entry of this payout (kill + headshot / melee), one number
	local req = 0
	for _, e in entries do
		req += math.floor(tonumber(e.Amount) or 0)
	end
	local first = entries[1]
	local event = first.Kind == "Bounty" or first.Kind == "Directive" or first.Kind == "Surge"
	local size = F.LineSize or 27
	local parts = {
		{ Text = tostring(first.Label), Size = size, Color = if event then F.EventColor else F.NameColor },
		{ Text = "+" .. req, Size = size, Color = if event then F.EventColor else F.AmountColor },
		{ Icon = emblem, Size = math.floor(size * 1.22) },
	}
	local ordN = if type(extra) == "table" then math.floor(tonumber(extra.ORD) or 0) else 0
	if ordN > 0 then
		table.insert(parts, { Gap = 4 })
		table.insert(parts, { Text = "+" .. ordN, Size = math.floor(size * 0.8), Color = ORD_COLOR })
		table.insert(parts, { Icon = function(p, px)
			if OrdCfg and OrdCfg.Icon then
				return new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), Image = OrdCfg.Icon, ScaleType = Enum.ScaleType.Fit }, p)
			end
			local f = new("Frame", { BackgroundColor3 = ORD_COLOR, Size = UDim2.fromOffset(px * 0.8, px * 0.8) }, p)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
			return f
		end, Size = math.floor(size * 0.95) })
	end
	-- the next payout replaces the line in the same spot
	if current then
		current:Destroy()
	end
	seq += 1
	local my = seq
	local line = new("Frame", { Name = "KillLine", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, holder)
	row(line, parts, true)
	row(line, parts, false)
	current = line
	-- slam in at ~2.2x, ease to 1x from the left edge (UIScale grows from the anchor: left-middle)
	local pop = new("UIScale", { Scale = F.LinePop or 2.2 }, line)
	tween(pop, F.LinePopTime or 0.45, { Scale = 1 }, Enum.EasingStyle.Quart)
	chime(pitch, 1.1)
	task.delay(F.Life, function()
		if seq == my then
			current = nil
		end
		fade(line)
	end)
end

Remote.OnClientEvent:Connect(function(entries, _balance, extra)
	if type(entries) ~= "table" or #entries == 0 or type(entries[1]) ~= "table" then
		return
	end
	local now = os.clock()
	combo = if now - lastAward < COMBO_WINDOW then math.min(combo + 1, 6) else 0
	lastAward = now
	local ok, err = pcall(show, entries, extra, 0.94 + combo * 0.06)
	if not ok then
		warn("[VANTAGE] REQ feed: " .. tostring(err))
	end
end)

-- ─── running total, just above the ammo block ───────────────────────────────────────
local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end
task.spawn(function()
	local hudGui = playerGui:WaitForChild("VantageHUD", 60)
	local root = hudGui and hudGui:WaitForChild("Root", 30)
	local ammo = root and root:WaitForChild("Ammo", 30)
	if not ammo then
		return
	end
	local total = new("Frame", { Name = "ReqTotal", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -2), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, ammo)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, total)
	local em = emblem(total, F.TotalSize + 4)
	em.LayoutOrder = 1
	local num = text(total, { LayoutOrder = 2, Text = "0", TextSize = F.TotalSize, TextColor3 = F.NameColor })
	local shown = player:GetAttribute("REQ") or 0
	num.Text = fmt(shown)
	local punch = new("UIScale", { Scale = 1 }, total)
	player:GetAttributeChangedSignal("REQ"):Connect(function()
		local target = player:GetAttribute("REQ") or 0
		local gain = target - shown
		if gain > 0 then
			-- punch + red flash on the balance, and a "+N" ghost floating up off it
			punch.Scale = 1.35
			tween(punch, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			num.TextColor3 = F.AmountColor
			tween(num, 0.6, { TextColor3 = F.NameColor })
			local ap, as = total.AbsolutePosition, total.AbsoluteSize
			local inset = if gui.IgnoreGuiInset == hudGui.IgnoreGuiInset then Vector2.zero
				else game:GetService("GuiService"):GetGuiInset()
			local ghost = text(gui, { Text = "+" .. math.floor(gain), TextSize = F.TotalSize, TextColor3 = F.AmountColor,
				AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(ap.X + as.X + inset.X, ap.Y + inset.Y) })
			tween(ghost, 0.8, { Position = ghost.Position - UDim2.fromOffset(0, 36), TextTransparency = 1 })
			local st = ghost:FindFirstChildOfClass("UIStroke")
			if st then
				tween(st, 0.8, { Transparency = 1 })
			end
			task.delay(0.85, function()
				ghost:Destroy()
			end)
		end
		local nv = new("NumberValue", { Value = shown })
		nv.Changed:Connect(function(v)
			num.Text = fmt(v)
		end)
		local tw = TweenService:Create(nv, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
		tw.Completed:Connect(function()
			nv:Destroy()
			num.Text = fmt(target)
		end)
		shown = target
		tw:Play()
	end)
end)
