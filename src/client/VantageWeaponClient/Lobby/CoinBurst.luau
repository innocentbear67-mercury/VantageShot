--!nocheck
--[[
	VANTAGE — CoinBurst (client) · 2026-11-18
	Claim VFX for the lobby. Whenever REQ or ORD goes UP while the lobby is open (season pass, mastery,
	shop packs, crates, daily, anything), the currency emblem bursts out of the claim point (the last
	click / tap, else screen centre) as a spray of spinning coins, hangs for a beat, then the coins
	streak one by one into the matching top-right pill. Every landing ticks the number up, bumps the
	pill and pings (rising pitch); the last one lands with a chime and a "+N" rise.
	If the top-right pills are slid away (a modal is open) a ghost copy of the pill slides in to catch
	the coins, then slides back out.
	Lobby.renderData leaves the value text alone while a burst owns it (CoinBurst.Owns(kind)).
	API: CoinBurst.Init(ctx)  ctx = { Bars = { REQ = frame, ORD = frame }, Abbrev = fn, Font = Font, HS = HS }
	     CoinBurst.Play(kind, from, to, origin?)  kind "REQ" | "ORD"; origin = Vector2 screen px (full screen)
	     CoinBurst.Owns(kind) -> bool
	Studio hook: player attribute DevCoinBurst = "REQ" | "ORD" -> plays a sample burst (no balance change).
]]

local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local V2 = Vector2.new

local CB = {}

CB.Config = {
	Sounds = { -- { id, volume, speed }
		Burst = { "rbxassetid://9113849583", 0.6, 1.12 }, -- Coin Throws 2 (ProSoundEffects)
		Fly = { "rbxassetid://9114267803", 0.32, 1.3 }, -- Electric Whoosh Bys (ProSoundEffects)
		Tick = { "rbxasset://sounds/electronicpingshort.wav", 0.2, 1.5 },
		Land = { "rbxassetid://102619312277180", 0.65, 1 }, -- lobby Purchase chime
	},
	Accent = { REQ = Color3.fromRGB(120, 214, 255), ORD = Color3.fromRGB(255, 186, 64) },
	MinCoins = 9,
	MaxCoins = 26,
	ClickMemory = 2.5, -- s: a click this recent is the burst origin
	Warmup = 5, -- s after Init: ignore balance changes (initial data load)
	CoinSize = 58, -- px at 900 px view height
	TimeScale = 1, -- coin motion speed (Studio: 0 freezes the coins for a screenshot)
}

local ctx
local owns = { REQ = 0, ORD = 0 } -- active token per kind (0 = free)
local tokens = 0
local last = {} -- last known balance per kind
local initAt = 0
local lastClick, lastClickT = nil, -100
local gui -- our ScreenGui
local parts = {}
local stepConn
local ghosts = {}
local vclock = 0 -- coin motion clock (scaled by Config.TimeScale)

-- ── helpers ────────────────────────────────────────────────────────────────
local function inset()
	local tl = GuiService:GetGuiInset()
	return tl
end

local function viewScale()
	local cam = workspace.CurrentCamera
	local y = cam and cam.ViewportSize.Y or 900
	return math.clamp(y / 900, 0.55, 1.6)
end

local function commas(n)
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function sfx(key, speed, vol)
	local s = CB.Config.Sounds[key]
	if not s then
		return
	end
	local snd = Instance.new("Sound")
	snd.SoundId = s[1]
	snd.Volume = vol or s[2]
	snd.PlaybackSpeed = speed or s[3] or 1
	snd.SoundGroup = ctx and ctx.HS and ctx.HS.SoundGroup or nil
	snd.Parent = SoundService
	snd:Play()
	Debris:AddItem(snd, 4)
end

local function ensureGui()
	if gui and gui.Parent then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "VantageCoinBurst"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 950
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function screenGuiOf(o)
	return o and o:FindFirstAncestorWhichIsA("ScreenGui")
end

-- full-screen centre of a GuiObject (accounts for the host gui's inset mode)
local function centreOf(o)
	local sg = screenGuiOf(o)
	local c = o.AbsolutePosition + o.AbsoluteSize / 2
	if sg and not sg.IgnoreGuiInset then
		c += inset()
	end
	return c
end

local function shown(o)
	local x = o
	while x and not x:IsA("ScreenGui") do
		if x:IsA("GuiObject") and not x.Visible then
			return false
		end
		x = x.Parent
	end
	return x ~= nil and x.Enabled
end

local function onScreen(o)
	if not shown(o) then
		return false
	end
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or V2(1920, 1080)
	local c = centreOf(o)
	return c.X > 0 and c.X < vp.X - 8 and c.Y > 0 and c.Y < vp.Y
end

local function iconOf(bar)
	for _, n in { "Icon", "OrdCoin" } do
		local i = bar:FindFirstChild(n)
		if i and i:IsA("ImageLabel") and i.Visible and i.Image ~= "" then
			return i
		end
	end
	for _, d in bar:GetDescendants() do
		if d:IsA("ImageLabel") and d.Visible and d.Image ~= "" and d.Name ~= "Streak" then
			return d
		end
	end
	return nil
end

local function valueOf(bar)
	local pill = bar:FindFirstChild("Pill")
	return pill and pill:FindFirstChild("Value") or bar:FindFirstChild("Value", true)
end

local function bump(bar, amount)
	if not bar then
		return
	end
	local sc = bar:FindFirstChild("BurstBump") or Instance.new("UIScale")
	sc.Name = "BurstBump"
	sc.Parent = bar
	sc.Scale = 1 + (amount or 0.1)
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function flashStroke(bar, col)
	local pill = bar and bar:FindFirstChild("Pill")
	local st = pill and pill:FindFirstChildOfClass("UIStroke")
	if not st then
		return
	end
	local base = st:GetAttribute("BurstBase")
	if not base then
		st:SetAttribute("BurstBase", st.Color)
		base = st.Color
	end
	st.Color = col
	TweenService:Create(st, TweenInfo.new(0.35), { Color = base }):Play()
end

-- expanding ring / soft flash
local function ring(pos, col, from, to, life, thick, z)
	local g = ensureGui()
	local f = Instance.new("Frame")
	f.AnchorPoint = V2(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromOffset(pos.X, pos.Y)
	f.Size = UDim2.fromOffset(from, from)
	f.ZIndex = z or 5
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0.5, 0)
	cr.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = col
	st.Thickness = thick or 4
	st.Transparency = 0.05
	st.Parent = f
	f.Parent = g
	TweenService:Create(f, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(to, to) }):Play()
	TweenService:Create(st, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Thickness = 0.5 }):Play()
	Debris:AddItem(f, life + 0.05)
end

local function glow(pos, col, size, life, z)
	local g = ensureGui()
	local f = Instance.new("Frame")
	f.AnchorPoint = V2(0.5, 0.5)
	f.BackgroundColor3 = col
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(pos.X, pos.Y)
	f.Size = UDim2.fromOffset(size * 0.3, size * 0.3)
	f.ZIndex = z or 4
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0.5, 0)
	cr.Parent = f
	local gr = Instance.new("UIGradient")
	gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) })
	gr.Rotation = 0
	gr.Parent = f
	f.Parent = g
	TweenService:Create(f, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, life + 0.05)
end

local function sparks(pos, col, n, dist, life)
	local g = ensureGui()
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + math.random() * 0.5
		local d = dist * (0.6 + math.random() * 0.6)
		local s = Instance.new("Frame")
		s.AnchorPoint = V2(0.5, 0.5)
		s.BackgroundColor3 = i % 2 == 0 and Color3.new(1, 1, 1) or col
		s.BorderSizePixel = 0
		s.Rotation = math.deg(a)
		s.Size = UDim2.fromOffset(10, 3)
		s.Position = UDim2.fromOffset(pos.X, pos.Y)
		s.ZIndex = 9
		s.Parent = g
		local to = pos + V2(math.cos(a), math.sin(a)) * d
		TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(to.X, to.Y),
			Size = UDim2.fromOffset(2, 1),
			BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(s, life + 0.05)
	end
end

local function riseText(pos, text, col, font, sizePx)
	local g = ensureGui()
	local t = Instance.new("TextLabel")
	t.AnchorPoint = V2(1, 0.5)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = col
	t.TextSize = sizePx
	if font then
		t.FontFace = font
	else
		t.Font = Enum.Font.FredokaOne
	end
	t.Size = UDim2.fromOffset(300, sizePx + 8)
	t.TextXAlignment = Enum.TextXAlignment.Right
	t.Position = UDim2.fromOffset(pos.X, pos.Y)
	t.ZIndex = 12
	local st = Instance.new("UIStroke")
	st.Thickness = math.max(2, sizePx / 11)
	st.Color = Color3.fromRGB(10, 12, 16)
	st.Parent = t
	local sc = Instance.new("UIScale")
	sc.Scale = 1.6
	sc.Parent = t
	t.Parent = g
	TweenService:Create(sc, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.55, function()
		TweenService:Create(t, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(pos.X, pos.Y + sizePx * 1.4),
			TextTransparency = 1,
		}):Play()
		TweenService:Create(st, TweenInfo.new(0.7), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(t, 1.4)
end

-- ── ghost pill (when the real one is slid away by a modal) ────────────────
local function ghostFor(kind, bar)
	local gh = ghosts[kind]
	if gh and gh.f.Parent then
		gh.keep = os.clock()
		return gh
	end
	local g = ensureGui()
	local c = bar:Clone()
	for _, d in c:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("GuiButton") then
			d.Active = false
		end
	end
	local plus = c:FindFirstChild("Plus")
	if plus then
		plus.Visible = false
	end
	-- keep the on-screen size the real pill would have (the cluster has a UIScale)
	local base = bar.Size.X.Offset > 0 and bar.Size.X.Offset or 268
	local k = bar.AbsoluteSize.X > 1 and (bar.AbsoluteSize.X / base) or viewScale()
	local old = c:FindFirstChildOfClass("UIScale")
	if old then
		old:Destroy()
	end
	local sc = Instance.new("UIScale")
	sc.Scale = k
	sc.Parent = c
	c.AnchorPoint = V2(1, 0)
	local ins = inset()
	local y = (kind == "ORD") and (ins.Y + 70 * k) or (ins.Y + 16 * k)
	local home = UDim2.new(1, -18 * k, 0, y)
	c.Position = home + UDim2.fromOffset(base * k + 40, 0)
	c.ZIndex = 10
	c.Parent = g
	TweenService:Create(c, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
	gh = { f = c, keep = os.clock(), home = home, off = home + UDim2.fromOffset(base * k + 40, 0) }
	ghosts[kind] = gh
	return gh
end

local function retireGhost(kind)
	local gh = ghosts[kind]
	if not gh then
		return
	end
	local myKeep = gh.keep
	task.delay(0.75, function()
		if ghosts[kind] ~= gh or gh.keep ~= myKeep then
			return
		end
		ghosts[kind] = nil
		local tw = TweenService:Create(gh.f, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = gh.off })
		tw:Play()
		tw.Completed:Wait()
		gh.f:Destroy()
	end)
end

-- ── particle loop ──────────────────────────────────────────────────────────
local function bez(a, c, b, t)
	local u = 1 - t
	return a * (u * u) + c * (2 * u * t) + b * (t * t)
end

local function step(dt)
	vclock += dt * (CB.Config.TimeScale or 1)
	local now = vclock
	for i = #parts, 1, -1 do
		local p = parts[i]
		local t = now - p.t0
		local pos, sc, rot, wx
		if t < 0 then
			p.img.Visible = false
			continue
		end
		p.img.Visible = true
		if t < p.tb then -- burst out
			local a = t / p.tb
			local e = 1 - (1 - a) ^ 3
			pos = p.o:Lerp(p.b, e)
			sc = a < 0.45 and (0.25 + (a / 0.45) * 1.0) or (1.25 - (a - 0.45) / 0.55 * 0.25)
			rot = p.rot0 + p.spin * t
			wx = 0.3 + 0.7 * math.abs(math.cos(p.ph + t * p.flip))
		elseif t < p.tb + p.th then -- hang
			local a = (t - p.tb) / p.th
			pos = p.b + V2(0, -5 * a) * p.k
			sc = 1
			rot = p.rot0 + p.spin * t
			wx = 0.3 + 0.7 * math.abs(math.cos(p.ph + t * p.flip))
		elseif t < p.tb + p.th + p.tf then -- streak to the pill
			if not p.flying then
				p.flying = true
				p.rotF = p.rot0 + p.spin * t
				p.wxF = 0.3 + 0.7 * math.abs(math.cos(p.ph + t * p.flip))
			end
			local a = (t - p.tb - p.th) / p.tf
			local e = a ^ 2.15
			local tgt = p.target()
			pos = bez(p.b + V2(0, -5) * p.k, p.c, tgt, e)
			sc = 1 - 0.42 * e
			rot = p.rotF * (1 - e)
			wx = p.wxF + (1 - p.wxF) * math.min(1, a * 2)
			p.glow.ImageTransparency = 0.55 + 0.35 * (1 - e)
		else
			p.img:Destroy()
			table.remove(parts, i)
			task.spawn(p.land)
			continue
		end
		local s = p.size * sc
		p.img.Position = UDim2.fromOffset(pos.X, pos.Y)
		p.img.Size = UDim2.fromOffset(s * wx, s)
		p.img.Rotation = rot
	end
	if #parts == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

-- ── public ─────────────────────────────────────────────────────────────────
function CB.Owns(kind)
	return (owns[kind] or 0) ~= 0
end

function CB.Play(kind, from, to, origin)
	if not ctx or not ctx.Bars then
		return
	end
	local bar = ctx.Bars[kind]
	if not bar or not bar.Parent then
		return
	end
	local amount = (to or 0) - (from or 0)
	if amount <= 0 then
		return
	end
	local g = ensureGui()
	local cfg = CB.Config
	local k = viewScale()
	local col = cfg.Accent[kind] or Color3.new(1, 1, 1)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or V2(1920, 1080)

	-- origin: explicit, else the claim click, else screen centre
	if not origin then
		if lastClick and os.clock() - lastClickT < cfg.ClickMemory then
			origin = lastClick
		else
			origin = vp / 2
		end
	end

	-- target: the real pill if it's on screen, else a ghost pill
	local catchBar = bar
	local useGhost = not onScreen(bar)
	local gh
	if useGhost then
		gh = ghostFor(kind, bar)
		catchBar = gh.f
	end
	local icon = iconOf(catchBar) or iconOf(bar)
	local valueLabels = { valueOf(bar) }
	if gh then
		table.insert(valueLabels, valueOf(gh.f))
	end
	local target = function()
		local o = icon and icon:IsDescendantOf(game) and icon or catchBar
		return centreOf(o)
	end
	local image = icon and icon.Image or ""
	local abbrev = ctx.Abbrev or function(n)
		return commas(n)
	end

	tokens += 1
	local token = tokens
	owns[kind] = token
	for _, v in valueLabels do
		if v then
			v.Text = abbrev(from)
		end
	end

	local n = math.clamp(math.floor(cfg.MinCoins + math.log10(math.max(amount, 1)) * 3.2), cfg.MinCoins, cfg.MaxCoins)
	local size = cfg.CoinSize * k
	local landed = 0
	local lastTick = 0

	-- burst flash at the claim point
	glow(origin, col, 260 * k, 0.45, 3)
	glow(origin, Color3.new(1, 1, 1), 140 * k, 0.25, 4)
	ring(origin, col, 30 * k, 320 * k, 0.5, 5 * k, 5)
	ring(origin, Color3.new(1, 1, 1), 20 * k, 190 * k, 0.32, 3 * k, 5)
	sparks(origin, col, 14, 170 * k, 0.45)
	sfx("Burst")
	task.delay(0.42, function()
		sfx("Fly")
	end)

	local tgt0 = target()
	for i = 1, n do
		local ang = math.random() * math.pi * 2
		local r = (90 + math.random() * 170) * k
		local b = origin + V2(math.cos(ang), math.sin(ang) * 0.8 - 0.25) * r
		b = V2(math.clamp(b.X, size, vp.X - size), math.clamp(b.Y, size, vp.Y - size))
		-- curve control: swing out sideways, away from the straight line
		local dir = (tgt0 - b)
		local perp = V2(-dir.Y, dir.X).Unit * ((math.random() < 0.5 and -1 or 1) * (60 + math.random() * 120) * k)
		local c = b:Lerp(tgt0, 0.35) + perp + V2(0, -60 * k)

		local img = Instance.new("ImageLabel")
		img.Name = "Coin"
		img.AnchorPoint = V2(0.5, 0.5)
		img.BackgroundTransparency = 1
		img.Image = image
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 8
		img.Visible = false
		img.Position = UDim2.fromOffset(origin.X, origin.Y)
		img.Size = UDim2.fromOffset(size * 0.3, size * 0.3)
		local gl = Instance.new("ImageLabel")
		gl.Name = "Glow"
		gl.AnchorPoint = V2(0.5, 0.5)
		gl.BackgroundTransparency = 1
		gl.Image = image
		gl.ImageColor3 = col
		gl.ImageTransparency = 0.75
		gl.ScaleType = Enum.ScaleType.Fit
		gl.Position = UDim2.fromScale(0.5, 0.5)
		gl.Size = UDim2.fromScale(1.45, 1.45)
		gl.ZIndex = 7
		gl.Parent = img
		if image == "" then -- no emblem found: plain accent disc
			img.BackgroundTransparency = 0
			img.BackgroundColor3 = col
			local cr = Instance.new("UICorner")
			cr.CornerRadius = UDim.new(0.5, 0)
			cr.Parent = img
		end
		img.Parent = g

		local p = {
			img = img,
			glow = gl,
			o = origin,
			b = b,
			c = c,
			k = k,
			size = size * (0.85 + math.random() * 0.3),
			t0 = vclock + (i - 1) * 0.012,
			tb = 0.3 + math.random() * 0.12,
			th = 0.12 + (i - 1) * 0.045,
			tf = 0.48 + math.random() * 0.14,
			rot0 = math.random(-25, 25),
			spin = math.random(-220, 220),
			flip = 7 + math.random() * 6,
			ph = math.random() * math.pi,
			target = target,
		}
		p.land = function()
			landed += 1
			local here = target()
			-- count up as coins arrive
			if owns[kind] == token then
				local v = from + math.floor(amount * landed / n + 0.5)
				if landed >= n then
					v = to
				end
				for _, lbl in valueLabels do
					if lbl and lbl.Parent then
						lbl.Text = abbrev(v)
					end
				end
			end
			bump(catchBar, landed >= n and 0.22 or 0.07)
			ring(here, col, 10 * k, 70 * k, 0.28, 3 * k, 9)
			local now = os.clock()
			if now - lastTick > 0.04 then
				lastTick = now
				sfx("Tick", 1.35 + 0.75 * (landed / n))
			end
			if landed >= n then
				-- final: chime, big ring + sparks, "+N", stroke flash
				sfx("Land")
				glow(here, col, 170 * k, 0.4, 6)
				ring(here, Color3.new(1, 1, 1), 20 * k, 150 * k, 0.4, 4 * k, 9)
				sparks(here, col, 10, 70 * k, 0.4)
				flashStroke(catchBar, col)
				local pillLeft = (catchBar:FindFirstChild("Pill") and centreOf(catchBar.Pill) or here)
				riseText(V2(pillLeft.X + 80 * k, here.Y + 34 * k), "+" .. commas(amount), col, ctx.Font, math.floor(30 * k))
				if owns[kind] == token then
					task.delay(0.15, function()
						if owns[kind] == token then
							owns[kind] = 0
							local now2 = tonumber(player:GetAttribute(kind)) or to
							for _, lbl in valueLabels do
								if lbl and lbl.Parent then
									lbl.Text = abbrev(now2)
								end
							end
						end
					end)
				end
				if gh then
					retireGhost(kind)
				end
			end
		end
		table.insert(parts, p)
	end
	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(step)
	end
end

local function lobbyOpen()
	if ctx and ctx.IsOpen then
		local ok, r = pcall(ctx.IsOpen)
		if ok then
			return r
		end
	end
	local bar = ctx and ctx.Bars and ctx.Bars.REQ
	local sg = bar and screenGuiOf(bar)
	return sg ~= nil and sg.Enabled
end

function CB.Init(c)
	ctx = c
	initAt = os.clock()
	ensureGui()
	UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			lastClick = V2(input.Position.X, input.Position.Y) + inset()
			lastClickT = os.clock()
		end
	end)
	for _, kind in { "REQ", "ORD" } do
		last[kind] = tonumber(player:GetAttribute(kind))
		player:GetAttributeChangedSignal(kind):Connect(function()
			local new = tonumber(player:GetAttribute(kind))
			local old = last[kind]
			last[kind] = new
			if not new or not old or new <= old then
				return
			end
			if os.clock() - initAt < CB.Config.Warmup or not lobbyOpen() then
				return
			end
			CB.Play(kind, old, new)
		end)
	end
	-- Studio hooks: DevCoinBurst = "REQ" | "ORD" (optionally "REQ@x,y" for the origin in px);
	-- DevCoinBurstTimeScale = number (0 freezes the coins)
	player:GetAttributeChangedSignal("DevCoinBurst"):Connect(function()
		local raw = tostring(player:GetAttribute("DevCoinBurst") or "")
		local kind, x, y = raw:match("^(%u+)@([%d%.]+),([%d%.]+)")
		kind = kind or raw:match("^(%u+)")
		if kind == "REQ" or kind == "ORD" then
			local cur = tonumber(player:GetAttribute(kind)) or 0
			CB.Play(kind, math.max(0, cur - 250), cur, x and V2(tonumber(x), tonumber(y)) or nil)
		end
	end)
	player:GetAttributeChangedSignal("DevCoinBurstTimeScale"):Connect(function()
		CB.Config.TimeScale = tonumber(player:GetAttribute("DevCoinBurstTimeScale")) or 1
	end)
end

return CB
