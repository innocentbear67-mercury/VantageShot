--[[
	VANTAGE — Supply Surge (client FX), 2026-11-18
	HyperShot's random "SUPER BONUS!!" elimination, in lore: Command drops a bonus cache on a kill.
	The server (EliminationService.rollSurge) decides and pays; this only draws what it is sent:
	  Remotes.SupplySurge { Position, REQ, ORD, Heal, Delay, Title }
	Timeline (s after the kill):
	  0.00        white-gold flash, light rays from the kill point, impact + whoosh
	  0.00-0.60   big REQ / ORD emblems blast out of the body toward the camera; the title pops there
	  0.45-1.10   a rain of small "+n" REQ / ORD ticks scatters over the screen (they add up to the
	              real payout), green heal crosses rise on the left
	  Delay-0.75  the ticks fly into the REQ total by the ammo with rising pings; the server pays at
	              Delay, so the amber SUPPLY SURGE feed line lands with them
	Tuning: RequisitionConfig.Surge. Studio: player attribute SurgeTest = one surge now.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remote = Vantage:WaitForChild("Remotes"):WaitForChild("SupplySurge") :: RemoteEvent
local ReqCfg = require(Vantage:WaitForChild("Requisition"):WaitForChild("RequisitionConfig"))
local OrdCfg = nil
pcall(function()
	OrdCfg = require(Vantage:WaitForChild("Ordnance", 5):WaitForChild("OrdnanceConfig", 5))
end)

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
local REQ_ICON = ReqCfg.Icon or ""
local ORD_ICON = (OrdCfg and OrdCfg.Icon) or ""
local REQ_COLOR = ReqCfg.Feed.AmountColor
local ORD_COLOR = (OrdCfg and OrdCfg.Color) or Color3.fromRGB(255, 168, 46)
local OUTLINE = ReqCfg.Feed.Outline
local GOLD = Color3.fromRGB(255, 212, 84)
local FLASH = Color3.fromRGB(255, 246, 214)
local HEAL = Color3.fromRGB(110, 236, 120)
local SND_IMPACT = "rbxassetid://9125484526"
local SND_WHOOSH = "rbxassetid://9125648149"
local SND_PING = "rbxasset://sounds/electronicpingshort.wav"

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
local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function sound(id, volume, speed)
	local s = new("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = speed or 1 })
	local g = SoundService:FindFirstChild("VantageEffects")
	if g and g:IsA("SoundGroup") then
		s.SoundGroup = g
	end
	s.Parent = SoundService
	s:Play()
	task.delay(3, s.Destroy, s)
end
local function later(t, fn, ...)
	task.delay(t, fn, ...)
end

local gui = new("ScreenGui", { Name = "VantageSupplySurge", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 7, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

local function viewport(): Vector2
	return (Workspace.CurrentCamera :: Camera).ViewportSize
end
local function uiScale(): number
	return math.max(0.5, viewport().Y / 900) -- authored for a ~900 px tall view, like the REQ feed
end
-- kill point on screen (screen centre when it is behind the camera / unknown)
local function screenPoint(pos: Vector3?): Vector2
	local vs = viewport()
	if typeof(pos) == "Vector3" then
		local p, onScreen = (Workspace.CurrentCamera :: Camera):WorldToViewportPoint(pos)
		if p.Z > 0 then
			local v = Vector2.new(math.clamp(p.X, vs.X * 0.12, vs.X * 0.88), math.clamp(p.Y, vs.Y * 0.15, vs.Y * 0.8))
			if onScreen or p.Z > 0 then
				return v
			end
		end
	end
	return vs / 2
end
-- where the ticks fly: the REQ total above the ammo block (VantageReqFeed), else bottom right
local function target(): Vector2
	local vs = viewport()
	local hud = playerGui:FindFirstChild("VantageHUD")
	local root = hud and hud:FindFirstChild("Root")
	local ammo = root and root:FindFirstChild("Ammo")
	local total = ammo and ammo:FindFirstChild("ReqTotal")
	if total and total:IsA("GuiObject") and total.AbsoluteSize.X > 0 then
		local inset = if (hud :: ScreenGui).IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
		return total.AbsolutePosition + total.AbsoluteSize / 2 + inset
	end
	return Vector2.new(vs.X * 0.9, vs.Y * 0.86)
end

local function icon(kind: string, px: number, parent)
	local id = if kind == "ORD" then ORD_ICON else REQ_ICON
	if id ~= "" then
		return new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), Image = id, ScaleType = Enum.ScaleType.Fit }, parent)
	end
	local f = new("Frame", { BackgroundColor3 = if kind == "ORD" then ORD_COLOR else REQ_COLOR, Size = UDim2.fromOffset(px * 0.8, px * 0.8) }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	new("UIStroke", { Color = OUTLINE, Thickness = 2 }, f)
	return f
end
local function label(props, parent, thickness)
	local t = new("TextLabel", { BackgroundTransparency = 1, FontFace = FONT, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, parent)
	for k, v in props do
		t[k] = v
	end
	new("UIStroke", { Color = OUTLINE, Thickness = thickness or 2.5, LineJoinMode = Enum.LineJoinMode.Round }, t)
	return t
end

-- ─── 0.00 s: flash + light rays ──────────────────────────────────────────────────────
local function flash(c: Vector2, s: number)
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = FLASH, BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 1 }, gui)
	-- brighter at the kill point: a radial-ish glow sitting on top
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c.X, c.Y), Size = UDim2.fromOffset(120 * s, 120 * s), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2 }, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), GOLD), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, glow)
	tween(f, 0.55, { BackgroundTransparency = 1 })
	tween(glow, 0.5, { Size = UDim2.fromOffset(900 * s, 900 * s), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
	later(0.6, function()
		f:Destroy()
		glow:Destroy()
	end)
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2 + (math.random() - 0.5) * 0.25
		local dir = Vector2.new(math.cos(a), math.sin(a))
		local w = (if i % 2 == 0 then 10 else 5) * s
		local function at(len, off)
			local m = c + dir * (off + len / 2)
			return UDim2.fromOffset(m.X, m.Y), UDim2.fromOffset(len, w)
		end
		local p0, s0 = at(30 * s, 10 * s)
		local ray = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = p0, Size = s0, Rotation = math.deg(a), BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else GOLD, BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 3 }, gui)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0), NumberSequenceKeypoint.new(1, 1) }) }, ray)
		local p1, s1 = at((520 + math.random() * 380) * s, (60 + math.random() * 40) * s)
		tween(ray, 0.42, { Position = p1, Size = s1 }, Enum.EasingStyle.Quart)
		later(0.22, tween, ray, 0.25, { BackgroundTransparency = 1 })
		later(0.5, ray.Destroy, ray)
	end
end

-- ─── 0.00-0.60 s: big emblems blast toward the camera ───────────────────────────────
local function burst(c: Vector2, s: number)
	for i = 1, 13 do
		local kind = if i % 3 == 0 then "ORD" else "REQ"
		local a = math.random() * math.pi * 2
		local dist = (220 + math.random() * 330) * s
		local size = (80 + math.random() * 80) * s
		local e = icon(kind, 24 * s, gui)
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Position = UDim2.fromOffset(c.X, c.Y)
		e.Rotation = math.random(-40, 40)
		e.ZIndex = 4
		local d = Vector2.new(math.cos(a), math.sin(a) * 0.8)
		local to = c + d * dist
		local t = 0.5 + math.random() * 0.15
		tween(e, t, { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(size, size), Rotation = e.Rotation + math.random(-120, 120) }, Enum.EasingStyle.Quart)
		if e:IsA("ImageLabel") then
			later(t * 0.55, tween, e, t * 0.45, { ImageTransparency = 1 })
		else
			later(t * 0.55, tween, e, t * 0.45, { BackgroundTransparency = 1 })
		end
		later(t + 0.05, e.Destroy, e)
	end
	-- gold sparks
	for i = 1, 22 do
		local a = math.random() * math.pi * 2
		local to = c + Vector2.new(math.cos(a), math.sin(a)) * (90 + math.random() * 260) * s
		local k = (5 + math.random() * 7) * s
		local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c.X, c.Y), Size = UDim2.fromOffset(k, k), Rotation = 45, BackgroundColor3 = if i % 4 == 0 then Color3.new(1, 1, 1) else GOLD, BorderSizePixel = 0, ZIndex = 4 }, gui)
		tween(dot, 0.5 + math.random() * 0.3, { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
		later(0.85, dot.Destroy, dot)
	end
end

-- ─── title at the kill point ────────────────────────────────────────────────────────
local function title(c: Vector2, s: number, text: string)
	local t = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c.X, c.Y - 64 * s), Text = text, TextSize = math.floor(48 * s), TextColor3 = Color3.new(1, 1, 1), ZIndex = 6 }, gui, 3 * s)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.55, GOLD), ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 140, 30)) }) }, t)
	local pop = new("UIScale", { Scale = 2.6 }, t)
	tween(pop, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
	t.Rotation = -6
	tween(t, 0.32, { Rotation = -3 }, Enum.EasingStyle.Back)
	later(1.05, function()
		tween(t, 0.45, { Position = t.Position - UDim2.fromOffset(0, 34 * s), TextTransparency = 1 })
		local st = t:FindFirstChildOfClass("UIStroke")
		if st then
			tween(st, 0.45, { Transparency = 1 })
		end
	end)
	later(1.6, t.Destroy, t)
end

-- splits a total into n random-ish parts (each >= 1) that add up exactly
local function split(total: number, n: number): { number }
	total = math.max(0, math.floor(total))
	n = math.clamp(n, 0, total)
	local out = {}
	if n == 0 then
		return out
	end
	local w, sum = {}, 0
	for i = 1, n do
		w[i] = 0.7 + math.random() * 0.6
		sum += w[i]
	end
	local used = 0
	for i = 1, n do
		out[i] = math.max(1, math.floor(total * w[i] / sum))
		used += out[i]
	end
	local i = 1
	while used < total do
		out[i] += 1
		used += 1
		i = i % n + 1
	end
	while used > total do
		if out[i] > 1 then
			out[i] -= 1
			used -= 1
		end
		i = i % n + 1
	end
	return out
end

-- a random spot on screen, kept off the crosshair and the HUD edges
local function spot(vs: Vector2): Vector2
	for _ = 1, 12 do
		local p = Vector2.new(vs.X * (0.1 + math.random() * 0.8), vs.Y * (0.2 + math.random() * 0.62))
		if (p - vs / 2).Magnitude > vs.Y * 0.09 then
			return p
		end
	end
	return Vector2.new(vs.X * 0.3, vs.Y * 0.6)
end

-- ─── 0.45 s on: the rain of +n ticks, then they fly into the REQ total ─────────────────
local function rain(data, s: number)
	local vs = viewport()
	local list = {}
	for _, a in split(data.REQ or 0, math.clamp(math.floor((data.REQ or 0) / 15 + 0.5), 12, 24)) do
		table.insert(list, { Kind = "REQ", N = a })
	end
	for _, a in split(data.ORD or 0, math.clamp(math.floor((data.ORD or 0) / 3 + 0.5), 4, 9)) do
		table.insert(list, { Kind = "ORD", N = a })
	end
	-- shuffle so REQ / ORD mix on screen
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	local flyAt = math.max(1.4, (tonumber(data.Delay) or 2.9) - 0.75)
	local landed = 0
	for i, it in list do
		local born = 0.45 + (i - 1) * (0.6 / math.max(1, #list)) + math.random() * 0.05
		later(born, function()
			local p = spot(vs)
			local tag = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.X, p.Y), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), ZIndex = 5 }, gui)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4 * s), SortOrder = Enum.SortOrder.LayoutOrder }, tag)
			local ic = icon(it.Kind, 30 * s, tag)
			ic.LayoutOrder = 1
			ic.ZIndex = 5
			local tx = label({ LayoutOrder = 2, Text = "+" .. it.N, TextSize = math.floor(27 * s), TextColor3 = if it.Kind == "ORD" then ORD_COLOR else Color3.new(1, 1, 1), ZIndex = 5 }, tag, 2 * s)
			local sc = new("UIScale", { Scale = 0 }, tag)
			tween(sc, 0.26, { Scale = 1 + math.random() * 0.15 }, Enum.EasingStyle.Back)
			-- slow drift while it hangs on screen
			local hang = flyAt + math.random() * 0.35 - born
			local drift = p + Vector2.new((math.random() - 0.5) * 30, -10 - math.random() * 22) * s
			tween(tag, math.max(0.2, hang), { Position = UDim2.fromOffset(drift.X, drift.Y) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			later(math.max(0.2, hang), function()
				if not tag.Parent then
					return
				end
				local to = target()
				local t = 0.38 + math.random() * 0.14
				tween(tag, t, { Position = UDim2.fromOffset(to.X, to.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tween(sc, t, { Scale = 0.45 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				later(t, function()
					tag:Destroy()
					landed += 1
					if landed % 3 == 1 then
						sound(SND_PING, 0.22, 1.7 + math.min(landed, 30) * 0.035)
					end
					-- tiny pop where it lands
					local k = 14 * s
					local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(k, k), BackgroundTransparency = 1, ZIndex = 6 }, gui)
					new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
					local rs = new("UIStroke", { Color = if it.Kind == "ORD" then ORD_COLOR else GOLD, Thickness = 2 }, ring)
					tween(ring, 0.3, { Size = UDim2.fromOffset(k * 3, k * 3) })
					tween(rs, 0.3, { Transparency = 1 })
					later(0.32, ring.Destroy, ring)
				end)
			end)
		end)
	end
end

-- green crosses rising on the left (the heal)
local function heal(amount: number, s: number)
	if not amount or amount <= 0 then
		return
	end
	local vs = viewport()
	for i = 1, 7 do
		later(0.35 + i * 0.07, function()
			local p = Vector2.new(vs.X * (0.04 + math.random() * 0.22), vs.Y * (0.35 + math.random() * 0.45))
			local c = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.X, p.Y), Text = "+", TextSize = math.floor((26 + math.random() * 14) * s), TextColor3 = HEAL, ZIndex = 5 }, gui, 2 * s)
			tween(c, 1.1, { Position = UDim2.fromOffset(p.X, p.Y - 50 * s), TextTransparency = 1 }, Enum.EasingStyle.Sine)
			local st = c:FindFirstChildOfClass("UIStroke")
			if st then
				later(0.5, tween, st, 0.6, { Transparency = 1 })
			end
			later(1.15, c.Destroy, c)
		end)
	end
end

local function play(data)
	if type(data) ~= "table" then
		return
	end
	local s = uiScale()
	local c = screenPoint(data.Position)
	sound(SND_IMPACT, 0.75, 1.05)
	sound(SND_WHOOSH, 0.35, 1.25)
	later(0.08, sound, SND_PING, 0.35, 2.2)
	later(0.16, sound, SND_PING, 0.32, 2.75)
	flash(c, s)
	burst(c, s)
	title(c, s, tostring(data.Title or "SUPPLY SURGE!!"))
	rain(data, s)
	heal(tonumber(data.Heal) or 0, s)
end

Remote.OnClientEvent:Connect(function(data)
	local ok, err = pcall(play, data)
	if not ok then
		warn("[VANTAGE] supply surge fx: " .. tostring(err))
	end
end)
