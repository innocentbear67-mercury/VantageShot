--[[
	VANTAGE — Kill feed (client)
	Draws what the server decided (Remotes.KillFeed, sent by EliminationService.OnDeath for every
	death). Nothing here detects or reports a kill.
	Upper-right stack, newest on top: KILLER (+ASSIST) [icon] VICTIM. Lime = the killer,
	red = the eliminated. Weapon / vehicle icons are white silhouettes of the game's own models;
	headshot, blast, environment and suicide marks are drawn from UI primitives.
	Tuning: ReplicatedStorage.Vantage.Elimination.KillFeedConfig
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Cfg = require(Vantage:WaitForChild("Elimination"):WaitForChild("KillFeedConfig"))
local WeaponConfig = require(Vantage.Weapons:WaitForChild("WeaponConfig"))
local FeedRemote = Vantage:WaitForChild("Remotes"):WaitForChild("KillFeed") :: RemoteEvent
local player = Players.LocalPlayer
local COL = Cfg.Colors

local O = UDim2.fromOffset
local V2 = Vector2.new
local ROW_H, GAP = 32, 5

-- support badges on YOUR rows (2026-11-14 marker set v3): assist on kills you helped with,
-- double / triple on your kills inside MULTI_WINDOW of each other. Empty id = no badge.
local SUPPORT = { Assist = "rbxassetid://116699437749786", Double = "rbxassetid://79392575299585", Triple = "rbxassetid://130508795227922" }
local MULTI_WINDOW = 4.5
local lastMyKill, myMulti = -100, 0
local ICON_H = 24
local FONT_NAME = Font.new("rbxasset://fonts/families/FredokaOne.json") -- HUD v5 (Hypershot)
local FONT_SMALL = Font.new("rbxasset://fonts/families/FredokaOne.json")

local function new(class: string, props, parent: Instance?)
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- ─── screen ──────────────────────────────────────────────────────────────────────────
local gui = new("ScreenGui", { Name = "VantageKillFeed", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
local root = new("Frame", { Name = "Feed", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -26, 0, 66), Size = O(560, (ROW_H + GAP) * (Cfg.MaxRows + 1)), BackgroundTransparency = 1 }, gui)
local scale = new("UIScale", {}, root)
local function rescale()
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	scale.Scale = math.clamp(vp.Y / 1080, 0.72, 1.6)
end
rescale()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

-- ─── icons ───────────────────────────────────────────────────────────────────────────
local iconSources = {}
for _, src in { Vantage.Vehicles:FindFirstChild("FeedIcons"), Vantage.Weapons:FindFirstChild("Assets"), Vantage:FindFirstChild("Aircraft") } do
	if src then
		table.insert(iconSources, src)
	end
end
local preloaded = false
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(iconSources)
	end)
	preloaded = true
end)
-- silhouettes: a model rendered flat white in a ViewportFrame (built once per model, cloned per row)
local iconCache: { [string]: ViewportFrame } = {}
local function silhouette(key: string, source: Instance?, w: number, view: string?): ViewportFrame?
	local cached = iconCache[key]
	if cached == nil and source then
		local vp = new("ViewportFrame", { Size = O(w, ICON_H), BackgroundTransparency = 1, Ambient = Color3.new(1, 1, 1), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(0, -1, -0.2), ImageColor3 = COL.Icon })
		local m = source:Clone()
		if m:IsA("BasePart") then
			local holder = Instance.new("Model")
			m.Parent = holder
			m = holder
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.new(1, 1, 1)
				d.Material = Enum.Material.SmoothPlastic
				if d.Transparency >= 0.95 then
					d:Destroy() -- invisible handles / hitboxes would skew the framing
					continue
				end
				d.Transparency = 0
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("LuaSourceContainer") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sound") then
				d:Destroy()
			end
		end
		m.Parent = vp
		local cf, size = m:GetBoundingBox()
		if view == "Flat" then
			-- thin items (blades): measure on the biggest visible part's own axes, not the model's
			local big, vol = nil, 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Size.X * d.Size.Y * d.Size.Z > vol then
					big, vol = d, d.Size.X * d.Size.Y * d.Size.Z
				end
			end
			if big then
				cf, size = big.CFrame, big.Size
			end
		end
		local cam = Instance.new("Camera")
		cam.FieldOfView = 20
		local t = math.tan(math.rad(10))
		local aspect = w / ICON_H
		local dir
		local camUp = Vector3.yAxis
		if view == "Top" then
			dir = (cf.UpVector * 1.4 + cf.RightVector).Unit -- three-quarter from above (drone / aircraft)
		elseif view == "Flat" then
			-- the widest face toward the camera (thin blades would otherwise be seen edge-on)
			local axes = { { cf.RightVector, size.X }, { cf.UpVector, size.Y }, { cf.LookVector, size.Z } }
			table.sort(axes, function(a, b)
				return a[2] < b[2]
			end)
			dir = axes[1][1]   -- look along the thinnest side
			camUp = axes[2][1] -- and lay the longest side across the icon
		else
			dir = cf.RightVector -- side profile
		end
		-- frame the model's extent across the view
		local right = dir:Cross(camUp)
		if right.Magnitude < 0.1 then
			right = dir:Cross(Vector3.zAxis)
		end
		right = right.Unit
		local up = right:Cross(dir).Unit
		local function extent(axis: Vector3): number
			local ax = cf:VectorToObjectSpace(axis)
			return math.abs(ax.X) * size.X + math.abs(ax.Y) * size.Y + math.abs(ax.Z) * size.Z
		end
		local dist = math.max((extent(right) / 2) / (aspect * t), (extent(up) / 2) / t) * 1.1 + extent(dir) / 2
		cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position, up)
		cam.Parent = vp
		vp.CurrentCamera = cam
		cached = vp
		if preloaded then
			iconCache[key] = vp
		end
	end
	if not cached then
		return nil
	end
	local c = cached:Clone()
	c.CurrentCamera = c:FindFirstChildOfClass("Camera")
	return c
end

-- Signature kills (weapon id "Sig_<Id>"): the Signature's art in a ring of its colour + its name
local SigCatalog = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureCatalog"))
local function sigIcon(id: string): Frame?
	local it = SigCatalog.ById[id]
	if not it then return nil end
	local col = it.Color or Color3.new(1, 1, 1)
	local f = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 24), BackgroundTransparency = 1 })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local ring = new("Frame", { LayoutOrder = 1, Size = O(24, 24), BackgroundColor3 = Color3.fromRGB(14, 16, 24), BorderSizePixel = 0 }, f)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	new("UIStroke", { Color = col, Thickness = 1.6 }, ring)
	local img = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(20, 20), BackgroundTransparency = 1,
		Image = it.Art or "", ScaleType = Enum.ScaleType.Crop }, ring)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
	new("TextLabel", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 13,
		TextColor3 = col, Text = it.Name or id, TextStrokeTransparency = 0.6 }, f)
	return f
end

local function weaponIcon(id: string?): ViewportFrame?
	local w = id and WeaponConfig.Weapons[id]
	local assets = Vantage.Weapons:FindFirstChild("Assets")
	local asset = w and w.Asset and assets and assets:FindFirstChild(w.Asset)
	return asset and silhouette("W_" .. id, asset, if w.Kind == "Melee" then 40 else 58, if w.Kind == "Melee" then "Flat" else nil)
end
local function vehicleIcon(kind: string?): ViewportFrame?
	local icons = Vantage.Vehicles:FindFirstChild("FeedIcons")
	local m = kind and icons and icons:FindFirstChild(kind)
	return m and silhouette("V_" .. kind, m, if kind == "Drone" then 42 else 54, if kind == "Drone" then "Top" else nil)
end
local function aircraftIcon(): ViewportFrame?
	local A = Vantage:FindFirstChild("Aircraft")
	local m = A and A:FindFirstChild("AircraftModel")
	return m and silhouette("Aircraft", m, 56, "Top")
end

-- drawn glyphs (16x16), all lines are Frames so they fade with the row
local function bar(parent, x, y, w, h, rot, color)
	return new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(x, y), Size = O(w, h), Rotation = rot or 0, BackgroundColor3 = color or COL.Icon, BorderSizePixel = 0 }, parent)
end
local function ring(parent, d, thick, color)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(8, 8), Size = O(d, d), BackgroundTransparency = 1 }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	new("UIStroke", { Color = color or COL.Icon, Thickness = thick }, f)
	return f
end
local function dot(parent, d, color)
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = O(8, 8), Size = O(d, d), BackgroundColor3 = color or COL.Icon, BorderSizePixel = 0 }, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	return f
end
local GLYPHS = {}
function GLYPHS.Headshot(g) -- precision reticle, red centre
	ring(g, 12, 1.5)
	bar(g, 8, 1, 1.5, 4) bar(g, 8, 15, 1.5, 4) bar(g, 1, 8, 4, 1.5) bar(g, 15, 8, 4, 1.5)
	dot(g, 4, COL.Victim)
end
function GLYPHS.Blast(g) -- starburst
	for k = 0, 7 do
		local a = math.rad(k * 45 + 22.5)
		local len = if k % 2 == 0 then 7 else 5
		bar(g, 8 + math.sin(a) * (2.5 + len / 2), 8 - math.cos(a) * (2.5 + len / 2), 2, len, k * 45 + 22.5)
	end
	dot(g, 5, COL.Victim)
end
function GLYPHS.Void(g) -- falling out of the map: a chevron dropping past an edge
	bar(g, 8, 3, 14, 2)
	bar(g, 5.4, 9.5, 2, 7, -40) bar(g, 10.6, 9.5, 2, 7, 40)
	bar(g, 8, 14.5, 2, 3)
end
function GLYPHS.Hazard(g) -- generic environment: warning triangle
	bar(g, 4.6, 8.5, 2, 12, 30) bar(g, 11.4, 8.5, 2, 12, -30) bar(g, 8, 14, 13, 2)
	bar(g, 8, 8.3, 2, 4) bar(g, 8, 11.4, 2, 1.6)
end
function GLYPHS.Knife(g) -- combat knife, edge down, point right
	bar(g, 1.5, 8.5, 2, 5)          -- pommel
	bar(g, 6.5, 8.5, 8, 3.4)        -- grip
	bar(g, 11.5, 8.5, 1.8, 9)       -- guard
	bar(g, 19, 7.6, 13, 3.2)        -- blade
	bar(g, 19, 9.6, 11, 1.2)        -- edge bevel
	local tip = bar(g, 25.6, 8.3, 3.4, 3.4, 45)
	tip.Size = O(3, 3)
end
function GLYPHS.Suicide(g) -- prohibited sign
	ring(g, 13, 1.6)
	bar(g, 8, 8, 1.8, 13, 45)
end
local GLYPH_W = { Knife = 28 }
local function glyph(name: string): Frame
	-- drawn on a 16-high grid, shown 1.25x
	local w = GLYPH_W[name] or 16
	local g = new("Frame", { Size = O(w * 1.25, 20), BackgroundTransparency = 1 })
	local inner = new("Frame", { Size = O(w, 16), Position = O(2, 2), BackgroundTransparency = 1 }, g)
	GLYPHS[name](inner)
	new("UIScale", { Scale = 1.25 }, inner)
	inner.Position = O(0, 0)
	return g
end

-- ─── rows ────────────────────────────────────────────────────────────────────────────
local rows = {} -- newest first: { Frame, Alpha (NumberValue), Born, Dying }

local function cut(name: string?): string
	local s = string.upper(name or "?")
	local n = utf8.len(s) or #s
	if n > Cfg.MaxNameChars then
		local stop = utf8.offset(s, Cfg.MaxNameChars) or Cfg.MaxNameChars
		s = string.sub(s, 1, stop - 1) .. "…"
	end
	return s
end

local function nameLabel(text: string, color: Color3, order: number, parent: Instance, small: boolean?)
	local l = new("TextLabel", {
		LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, ROW_H), BackgroundTransparency = 1,
		FontFace = if small then FONT_SMALL else FONT_NAME, TextSize = if small then 17 else 20, Text = text, TextColor3 = color,
		TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	new("UISizeConstraint", { MaxSize = V2(Cfg.MaxNameWidth, ROW_H) }, l)
	new("UIStroke", { Color = Color3.fromRGB(12, 16, 34), Transparency = 0, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end

-- every faded property, captured at its resting value so a single 0..1 alpha drives the whole row
local function captureFade(row: Instance)
	local list = {}
	local function add(inst, prop)
		table.insert(list, { inst, prop, (inst :: any)[prop] })
	end
	for _, d in row:GetDescendants() do
		if d:IsA("TextLabel") then
			add(d, "TextTransparency")
		elseif d:IsA("ViewportFrame") then
			add(d, "ImageTransparency")
		elseif d:IsA("UIStroke") then
			add(d, "Transparency")
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			add(d, "BackgroundTransparency")
		end
	end
	if row:IsA("Frame") then
		add(row, "BackgroundTransparency")
	end
	return function(a: number) -- a = 1 fully shown, 0 gone
		for _, e in list do
			(e[1] :: any)[e[2]] = 1 - (1 - e[3]) * a
		end
	end
end

local function layout(instant: boolean?)
	for i, r in rows do
		local y = (i - 1) * (ROW_H + GAP)
		if instant then
			r.Frame.Position = UDim2.new(1, r.X or 0, 0, y)
		else
			TweenService:Create(r.Frame, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(1, r.X or 0, 0, y) }):Play()
		end
	end
end

local function remove(r, fast: boolean?)
	if r.Dying then
		return
	end
	r.Dying = true
	local t = if fast then 0.18 else Cfg.FadeTime
	TweenService:Create(r.Alpha, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 }):Play()
	local y = r.Frame.Position.Y.Offset
	TweenService:Create(r.Frame, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, 24, 0, y) }):Play()
	task.delay(t, function()
		local i = table.find(rows, r)
		if i then
			table.remove(rows, i)
		end
		r.Frame:Destroy()
		layout()
	end)
end

local function addEntry(e)
	if type(e) ~= "table" or type(e.Victim) ~= "table" then
		return
	end
	local me = player.UserId
	local mineKill = e.Killer and e.Killer.UserId == me
	local mineDeath = e.Victim.UserId == me
	local row = new("Frame", {
		Name = "Entry", AnchorPoint = V2(1, 0), AutomaticSize = Enum.AutomaticSize.X, Size = O(0, ROW_H),
		BackgroundColor3 = COL.Back, BackgroundTransparency = if mineKill or mineDeath then COL.SelfBackAlpha else COL.BackAlpha, BorderSizePixel = 0,
	})
	-- the plate fades toward the left edge, a hairline on top
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, row) -- HUD v5: solid rounded row (Hypershot)
	new("UIStroke", { Color = Color3.fromRGB(70, 78, 104), Transparency = 0.5, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
	if mineKill or mineDeath then
		new("Frame", { Name = "Edge", AnchorPoint = V2(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = if mineKill then COL.Killer else COL.Victim, BorderSizePixel = 0 }, row)
	end
	local content = new("Frame", { Name = "Content", AutomaticSize = Enum.AutomaticSize.X, Size = O(0, ROW_H), BackgroundTransparency = 1 }, row)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, if mineKill or mineDeath then 16 else 13) }, content)

	-- killer (+ assist)
	if e.Killer then
		nameLabel(cut(e.Killer.Name), COL.Killer, 1, content)
		if type(e.Assists) == "table" and e.Assists[1] then
			local a = nameLabel("+ " .. cut(e.Assists[1].Name), COL.Killer, 2, content, true)
			a.TextTransparency = 0.35
		end
	end

	-- icon(s): what did it
	local icons = new("Frame", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = O(0, ROW_H), BackgroundTransparency = 1 }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, icons)
	local function put(inst: GuiObject?, order: number)
		if inst then
			inst.LayoutOrder = order
			inst.Parent = icons
		end
	end
	local t = e.Type
	if t == "Vehicle" or t == "Drone" then
		put(vehicleIcon(e.Vehicle) or weaponIcon(e.Weapon), 1)
	elseif t == "Aircraft" then
		put(aircraftIcon(), 1)
	elseif t == "Explosion" then
		if e.Killer then
			put(if e.Vehicle then vehicleIcon(e.Vehicle) else weaponIcon(e.Weapon), 1)
		end
		put(glyph("Blast"), 2)
	elseif t == "Environment" then
		put(glyph(if e.Cause == "Void" then "Void" else "Hazard"), 1)
	elseif t == "Suicide" then
		put(glyph("Suicide"), 1)
	elseif t == "Melee" then
		put(glyph("Knife"), 1)
	elseif type(e.Weapon) == "string" and string.sub(e.Weapon, 1, 4) == "Sig_" then
		put(sigIcon(string.sub(e.Weapon, 5)), 1)
	else -- Weapon / Headshot
		put(weaponIcon(e.Weapon), 1)
		if t == "Headshot" then
			put(glyph("Headshot"), 2)
		end
	end
	if #icons:GetChildren() <= 1 then -- unknown weapon: a neutral mark rather than a gap
		put(glyph("Hazard"), 1)
	end

	-- victim
	nameLabel(cut(e.Victim.Name), COL.Victim, 4, content)

	-- support badge (assist / double / triple) at the end of your rows
	local multi = 0
	if mineKill then
		local now = os.clock()
		myMulti = if now - lastMyKill <= MULTI_WINDOW then myMulti + 1 else 1
		lastMyKill = now
		multi = myMulti
	end
	local assisted = false
	if not mineKill and type(e.Assists) == "table" then
		for _, a in e.Assists do
			if type(a) == "table" and a.UserId == me then
				assisted = true
			end
		end
	end
	local badgeId = if multi >= 3 then SUPPORT.Triple elseif multi == 2 then SUPPORT.Double elseif assisted then SUPPORT.Assist else ""
	if badgeId ~= "" then
		local b = new("ImageLabel", { Name = "Badge", LayoutOrder = 5, Size = O(ICON_H + 8, ICON_H + 8), BackgroundTransparency = 1, Image = badgeId, ScaleType = Enum.ScaleType.Fit }, content)
		local sc = new("UIScale", { Scale = 1.9 }, b)
		TweenService:Create(sc, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	local r = { Frame = row, Born = os.clock(), Alpha = Instance.new("NumberValue"), X = 0 }
	local apply = captureFade(row)
	r.Alpha.Changed:Connect(apply)
	r.Alpha.Value = 0
	apply(0)
	row.Position = UDim2.new(1, 60, 0, 0)
	row.Parent = root
	table.insert(rows, 1, r)
	-- slide in from the right; everything below steps down
	TweenService:Create(r.Alpha, TweenInfo.new(Cfg.SlideTime * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 }):Play()
	layout()
	TweenService:Create(row, TweenInfo.new(Cfg.SlideTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(1, 0, 0, 0) }):Play()
	-- a soft flash on rows you are in
	if mineKill or mineDeath then
		local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = if mineKill then COL.Killer else COL.Victim, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 0 }, row)
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		task.delay(0.55, function()
			flash:Destroy()
		end)
	end
	-- overflow: the oldest go quickly
	local live = 0
	for _, x in rows do
		if not x.Dying then
			live += 1
			if live > Cfg.MaxRows then
				remove(x, true)
			end
		end
	end
	task.delay(Cfg.Lifetime, function()
		remove(r)
	end)
end

FeedRemote.OnClientEvent:Connect(addEntry)

-- Studio preview hook: set the LocalPlayer attribute KillFeedPreview to a JSON entry to draw it
if game:GetService("RunService"):IsStudio() then
	player:GetAttributeChangedSignal("KillFeedPreview"):Connect(function()
		local raw = player:GetAttribute("KillFeedPreview")
		if type(raw) == "string" and raw ~= "" then
			local ok, e = pcall(function()
				return game:GetService("HttpService"):JSONDecode(raw)
			end)
			if ok then
				addEntry(e)
			end
		end
	end)
end
