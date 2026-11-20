--[[
	VANTAGE — VantageTutorial (client), 2026-11-20
	First-time training UI. The server (VantageServer.TutorialService) owns the flow and checks every stage;
	this script shows the stage rail, the instruction panel, objective ticks, the stage-clear toast, the
	ARMOURY (currencies + shop) and LOADOUT screens, and tells the server when a stage looks done.
	All names, icons and prices come from the live configs (RequisitionConfig, OrdnanceConfig, IchorConfig,
	CrateConfig, SignatureCatalog, EquipmentCatalog, WeaponUnlocks, UltConfig): nothing is hard-coded.
	Replay: the REPLAY TRAINING pill in the lobby, or chat /tutorial.
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local CAS = game:GetService("ContextActionService")
local TextChatService = game:GetService("TextChatService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local V = RS:WaitForChild("Vantage")
local T = require(V:WaitForChild("Tutorial"):WaitForChild("TutorialConfig"))
local L = T.L
local Remote = V:WaitForChild("Remotes"):WaitForChild("Tutorial") :: RemoteEvent
local GrappleFeed = require(V:WaitForChild("Abilities"):WaitForChild("GrappleFeed"))

-- ─── live game data (real names / icons / prices) ───────────────────────────────────────────────────────────
local function req(path: { string })
	local ok, m = pcall(function()
		local inst: Instance = V
		for _, n in path do
			inst = inst:WaitForChild(n, 5) :: Instance
		end
		return require(inst :: ModuleScript)
	end)
	return if ok then m else nil
end
local D: any = nil
local function data()
	if D then
		return D
	end
	D = {
		Req = req({ "Requisition", "RequisitionConfig" }) or {},
		Ord = req({ "Ordnance", "OrdnanceConfig" }) or {},
		Ich = req({ "Ichor", "IchorConfig" }) or {},
		Crates = req({ "Crates", "CrateConfig" }),
		Sig = req({ "Signatures", "SignatureCatalog" }),
		SigCfg = req({ "Signatures", "SignatureConfig" }) or {},
		Equip = req({ "Equipment", "EquipmentCatalog" }),
		WU = req({ "Weapons", "WeaponUnlocks" }),
		Weapons = req({ "Weapons", "WeaponConfig" }),
		Ult = req({ "Ult", "UltConfig" }) or {},
		Ability = req({ "Abilities", "AbilityConfig" }) or {},
	}
	return D
end

-- ─── look ──────────────────────────────────────────────────────────────────────────────────
local C3 = Color3.fromRGB
-- 2026-11-20 restyle: the Shop's palette (ShopHS C / GREEN / GOLD) instead of electric blue
local BLUE, BLUE_HI, BLUE_DK = C3(255, 206, 84), C3(255, 226, 120), C3(255, 172, 40) -- accent = shop gold
local INK, PANEL, CARD = C3(14, 6, 28), C3(26, 10, 48), C3(38, 16, 68)
local WHITE, MUTED, DIM = C3(255, 255, 255), C3(206, 190, 236), C3(120, 100, 160)
local EDGE, SOFT = C3(150, 80, 255), C3(44, 20, 78)
local GOOD = C3(176, 249, 81)
local GREEN = { Rim = C3(53, 80, 19), Top0 = C3(176, 249, 81), Top1 = C3(143, 239, 74), Ink = C3(25, 45, 12) }
local GOLDB = { Rim = C3(120, 70, 10), Top0 = C3(255, 226, 120), Top1 = C3(255, 172, 40), Ink = C3(70, 36, 4) }
local RED = C3(255, 82, 82)
local MONT = "rbxasset://fonts/families/Montserrat.json"
local BUILDER = "rbxasset://fonts/families/BuilderSans.json"
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local F_TITLE = FREDOKA
local F_TITLE_I = FREDOKA
local F_BODY = Font.new(MONT, Enum.FontWeight.SemiBold)
local F_BOLD = Font.new(MONT, Enum.FontWeight.Bold)
local F_HEAVY = Font.new(MONT, Enum.FontWeight.ExtraBold)
local V2, U2, O2, S2 = Vector2.new, UDim2.new, UDim2.fromOffset, UDim2.fromScale

local SOUNDS = {
	Hover = { 133432321810855, 0.3 },
	Click = { 102705143114378, 0.5 },
	Tab = { 101958858678403, 0.45 },
	Select = { 122755406072761, 0.55 },
	Clear = { 102619312277180, 0.6 },
	Deny = { 101979595621741, 0.45 },
	Riser = { 9045201066, 0.45 },
	Hit = { 9048764753, 0.6 },
	Swell = { 9040281024, 0.4 },
	Whoosh = { 9120718279, 0.3 },
}
local function sfx(name: string)
	local s = SOUNDS[name]
	if not s then
		return
	end
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://" .. s[1]
	snd.Volume = s[2]
	snd.Parent = SoundService
	snd:Play()
	Debris:AddItem(snd, 6)
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end
local function stroke(o, color, t, th)
	return new("UIStroke", { Color = color, Transparency = t or 0, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function text(parent, props): TextLabel
	local noStroke = props.NoStroke
	props.NoStroke = nil
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		FontFace = F_BODY,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = true,
		Size = O2(100, 20),
	}, parent)
	for k, v in props do
		(t :: any)[k] = v
	end
	if t.FontFace == FREDOKA and not noStroke then
		new("UIStroke", { Color = INK, Thickness = math.clamp(t.TextSize / 11, 1.5, 4.5), LineJoinMode = Enum.LineJoinMode.Round }, t)
	end
	return t
end
local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function fmt(n: number?): string
	local s = tostring(math.floor(tonumber(n) or 0))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if r:sub(1, 1) == "," then
		r = r:sub(2)
	end
	return r
end
local function asset(id: any): string
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end
	return tostring(id or "")
end
local function list(parent, dir, pad, halign, valign)
	return new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, pad or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
	}, parent)
end
local function pad(o, t, r, b, l)
	new("UIPadding", { PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b), PaddingLeft = UDim.new(0, l) }, o)
end
-- a drawn check mark (two rounded strokes), size x size
local function checkMark(parent, size, color, th)
	local h = new("Frame", { Size = O2(size, size), BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.5) }, parent)
	local a = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S2(0.36, 0.6), Size = U2(0.34, 0, 0, th), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0 }, h)
	local b = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S2(0.6, 0.49), Size = U2(0.58, 0, 0, th), Rotation = -52, BackgroundColor3 = color, BorderSizePixel = 0 }, h)
	corner(a, th)
	corner(b, th)
	return h
end
local function keycap(parent, k: string, order: number?)
	local wide = #k > 1
	local f = new("Frame", { Size = O2(if wide then math.max(36, 14 + #k * 9) else 30, 30), BackgroundColor3 = C3(20, 10, 36), LayoutOrder = order or 0 }, parent)
	corner(f, 6)
	stroke(f, EDGE, 0, 2)
	new("Frame", { AnchorPoint = V2(0, 1), Position = U2(0, 3, 1, -2), Size = U2(1, -6, 0, 2), BackgroundColor3 = BLUE, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, f)
	text(f, { Text = k, FontFace = F_HEAVY, TextSize = if wide then 13 else 15, TextXAlignment = Enum.TextXAlignment.Center, Size = U2(1, 0, 1, -2) })
	return f
end

-- ─── screen ─────────────────────────────────────────────────────────────────────────────────
local pg = player:WaitForChild("PlayerGui")
local gui = new("ScreenGui", { Name = "VantageTutorial", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, pg)
local scales = {}
local function scaled(o)
	table.insert(scales, new("UIScale", {}, o))
	return o
end
local function fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local s = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.45, 1.5)
	for _, u in scales do
		u.Scale = s
	end
end

-- stage rail (top centre)
local RAIL_W = 1080
local rail = scaled(new("Frame", { Name = "Rail", AnchorPoint = V2(0.5, 0), Position = U2(0.5, 0, 0, 24), Size = O2(RAIL_W, 58), BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, ZIndex = 20 }, gui))
corner(rail, 10)
stroke(rail, EDGE, 0, 2.5)
local railItems = {}
do
	local n = #T.Stages
	local w = RAIL_W / n
	for i, s in T.Stages do
		local f = new("Frame", { Position = O2((i - 1) * w, 0), Size = O2(w, 58), BackgroundTransparency = 1, ZIndex = 20 }, rail)
		local num = text(f, { Text = string.format("%02d", i), FontFace = F_HEAVY, TextSize = 13, TextColor3 = DIM, Position = O2(20, 9), Size = O2(40, 16), ZIndex = 21 })
		local ck = checkMark(f, 14, GOOD, 2.5)
		ck.AnchorPoint = V2(0, 0)
		ck.Position = O2(19, 10)
		ck.Visible = false
		local lab = text(f, { Text = s.Label, FontFace = F_TITLE, TextSize = 15, TextColor3 = DIM, Position = O2(20, 25), Size = O2(w - 30, 20), ZIndex = 21 })
		local track = new("Frame", { Position = U2(0, 18, 1, -8), Size = U2(1, -36, 0, 2), BackgroundColor3 = DIM, BackgroundTransparency = 0.65, BorderSizePixel = 0, ZIndex = 21 }, f)
		local fill = new("Frame", { Size = S2(0, 1), BackgroundColor3 = BLUE, BorderSizePixel = 0, ZIndex = 22 }, track)
		if i < n then
			new("Frame", { Position = U2(1, 0, 0.5, -12), Size = O2(1, 24), BackgroundColor3 = BLUE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 21 }, f)
		end
		railItems[i] = { Num = num, Check = ck, Label = lab, Fill = fill }
	end
end
local function setRail(cur: number)
	for i, it in railItems do
		if i < cur then
			it.Num.Visible = false
			it.Check.Visible = true
			tween(it.Label, 0.3, { TextColor3 = GOOD })
			tween(it.Fill, 0.6, { Size = S2(1, 1), BackgroundColor3 = GOOD })
		elseif i == cur then
			it.Num.Visible = true
			it.Check.Visible = false
			it.Num.TextColor3 = BLUE
			tween(it.Label, 0.3, { TextColor3 = WHITE })
			it.Fill.Size = S2(0, 1)
			it.Fill.BackgroundColor3 = BLUE
			tween(it.Fill, 0.8, { Size = S2(0.35, 1) })
		else
			it.Num.Visible = true
			it.Check.Visible = false
			it.Num.TextColor3 = DIM
			it.Label.TextColor3 = DIM
			it.Fill.Size = S2(0, 1)
		end
	end
end

-- skip (top right): hold K, or click twice when the mouse is free (P is Settings)
local skip = scaled(new("TextButton", { Name = "Skip", AnchorPoint = V2(1, 0), Position = U2(1, -28, 0, 33), Size = O2(196, 40), BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, AutoButtonColor = false, Text = "", ZIndex = 20, ClipsDescendants = true }, gui))
corner(skip, 10)
stroke(skip, EDGE, 0, 2.5)
local skipFill = new("Frame", { Size = S2(0, 1), BackgroundColor3 = BLUE, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 20 }, skip)
local skipText = text(skip, { Text = "SKIP TRAINING", FontFace = F_HEAVY, TextSize = 14, TextColor3 = MUTED, Position = O2(14, 0), Size = U2(1, -60, 1, 0), ZIndex = 21 })
local skipKey = keycap(skip, "K")
skipKey.AnchorPoint = V2(1, 0.5)
skipKey.Position = U2(1, -8, 0.5, 0)
skipKey.Size = O2(26, 26)
skipKey.ZIndex = 21
for _, d in skipKey:GetDescendants() do
	if d:IsA("GuiObject") then
		d.ZIndex = 22
	end
end

-- instruction panel (left, clear of the crosshair)
local PANEL_W = 470
-- right side: the left edge holds the killstreak / ULT meter
local PANEL_HOME = U2(1, -40, 0.53, 0)
local panel = scaled(new("Frame", { Name = "Panel", AnchorPoint = V2(1, 0.5), Position = PANEL_HOME, Size = O2(PANEL_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL, BackgroundTransparency = 0.06, ZIndex = 2 }, gui))
corner(panel, 14)
stroke(panel, EDGE, 0, 3)
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 0.12) }, panel)
local accent = new("Frame", { Position = O2(0, 18), Size = U2(0, 3, 1, -36), BackgroundColor3 = BLUE, BorderSizePixel = 0, ZIndex = 3 }, panel)
local body = new("Frame", { Size = U2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3 }, panel)
pad(body, 22, 24, 22, 28)
list(body, nil, 10)

-- stage clear toast
local toast = scaled(new("Frame", { Name = "Toast", AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.29), Size = O2(460, 170), BackgroundTransparency = 1, Visible = false, ZIndex = 30 }, gui))
local tCircle = new("Frame", { AnchorPoint = V2(0.5, 0), Position = U2(0.5, 0, 0, 0), Size = O2(78, 78), BackgroundColor3 = GOOD, ZIndex = 31 }, toast)
corner(tCircle, 39)
local tCircleScale = new("UIScale", {}, tCircle)
local tCheck = checkMark(tCircle, 46, INK, 6)
tCheck.ZIndex = 32
for _, d in tCheck:GetChildren() do
	d.ZIndex = 32
end
local tRing = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = U2(0.5, 0, 0, 39), Size = O2(78, 78), BackgroundTransparency = 1, ZIndex = 30 }, toast)
corner(tRing, 200)
local tRingStroke = stroke(tRing, GOOD, 0, 4)
stroke(tCircle, GREEN.Rim, 0, 3)
local tTitle = text(toast, { Text = "STAGE CLEAR", FontFace = F_TITLE_I, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Position = O2(0, 92), Size = U2(1, 0, 0, 40), ZIndex = 31 })
local tSub = text(toast, { Text = "", FontFace = F_HEAVY, TextSize = 15, TextColor3 = GOOD, TextXAlignment = Enum.TextXAlignment.Center, Position = O2(0, 134), Size = U2(1, 0, 0, 20), ZIndex = 31 })
for _, o in { tTitle, tSub } do
	new("UIStroke", { Color = INK, Transparency = 0.4, Thickness = 1.5 }, o)
end

local function playClear(label: string, hold: number?)
	sfx("Clear")
	toast.Visible = true
	tTitle.Text = "STAGE CLEAR"
	tSub.Text = label .. " COMPLETE"
	tCircle.BackgroundTransparency = 0
	tCircleScale.Scale = 0.3
	tRing.Size = O2(78, 78)
	tRingStroke.Transparency = 0
	tTitle.TextTransparency, tSub.TextTransparency = 1, 1
	tTitle.Position = O2(0, 104)
	for _, d in tCheck:GetChildren() do
		d.BackgroundTransparency = 0
	end
	tween(tCircleScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(tRing, 0.7, { Size = O2(190, 190) })
	tween(tRingStroke, 0.7, { Transparency = 1 })
	tween(tTitle, 0.4, { TextTransparency = 0, Position = O2(0, 92) })
	tween(tSub, 0.5, { TextTransparency = 0 })
	task.delay(hold or 1.05, function()
		tween(tCircle, 0.3, { BackgroundTransparency = 1 })
		for _, d in tCheck:GetChildren() do
			tween(d, 0.3, { BackgroundTransparency = 1 })
		end
		tween(tTitle, 0.3, { TextTransparency = 1 })
		tween(tSub, 0.3, { TextTransparency = 1 })
		task.delay(0.32, function()
			toast.Visible = false
		end)
	end)
end

-- full-screen pages (ARMOURY / LOADOUT)
local overlay = new("TextButton", { Name = "Overlay", Text = "", AutoButtonColor = false, Size = S2(1, 1), BackgroundColor3 = C3(12, 4, 24), BackgroundTransparency = 1, Active = true, Visible = false, ZIndex = 10 }, gui)
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }) }, overlay)
local page = scaled(new("Frame", { Name = "Page", AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.545), Size = O2(1560, 830), BackgroundTransparency = 1, ZIndex = 11 }, overlay))
local blur: BlurEffect? = nil

-- ─── state ──────────────────────────────────────────────────────────────────────────────────
local cur = 0 -- stage shown
local objs = {} -- { Done, Row, Status, StatusStroke, Check, Label, Base }
local stageT0 = 0
local pending = false
local hintLabel: TextLabel? = nil
local hintShown: string? = nil
local meter: any = nil
local yawAcc, lastLook = 0, nil
local reloadPressed = false
local adsHeldFor, adsKeyDown = 0, false -- aim objective (gamepad L2 counts too)
local lastFired = 0
local shieldSeen = { Hit = false, Broke = false }
local finishing = false

local function origin(): Vector3?
	return player:GetAttribute("TutorialOrigin")
end
local function localPos(): Vector3?
	local o = origin()
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (o and root) then
		return nil
	end
	return root.Position - o
end

local function clearBody()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	objs = {}
	hintLabel = nil
	hintShown = nil
	meter = nil
end

local function addObjective(keys: { string }, label: string, order: number)
	local row = new("Frame", { Size = U2(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 3 }, body)
	list(row, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
	local status = new("Frame", { Size = O2(22, 22), BackgroundColor3 = GOOD, BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 3 }, row)
	corner(status, 11)
	local ss = stroke(status, DIM, 0, 1.5)
	local ck = checkMark(status, 16, GREEN.Ink, 2.5)
	ck.Visible = false
	local ckScale = new("UIScale", {}, ck)
	new("Frame", { Size = O2(2, 1), BackgroundTransparency = 1, LayoutOrder = 1 }, row)
	for i, k in keys do
		keycap(row, k, 1 + i)
	end
	local lab = text(row, { Text = label, FontFace = F_BOLD, TextSize = 18, TextColor3 = WHITE, AutomaticSize = Enum.AutomaticSize.X, Size = O2(0, 30), LayoutOrder = 20, ZIndex = 3 })
	local o = { Done = false, Status = status, Stroke = ss, Check = ck, CheckScale = ckScale, Label = lab, Base = label }
	table.insert(objs, o)
	return o
end

local function complete(o)
	if o.Done then
		return
	end
	o.Done = true
	sfx("Select")
	tween(o.Status, 0.25, { BackgroundTransparency = 0 })
	tween(o.Stroke, 0.25, { Color = GREEN.Rim })
	o.Check.Visible = true
	o.CheckScale.Scale = 0.2
	tween(o.CheckScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(o.Label, 0.3, { TextColor3 = GOOD })
	task.delay(0.6, function()
		if o.Label.Parent then
			tween(o.Label, 0.5, { TextColor3 = MUTED })
		end
	end)
end

local function hint(msg: string?)
	if not hintLabel or hintShown == msg then
		return
	end
	hintShown = msg
	local holder = hintLabel.Parent :: Frame
	if not msg then
		holder.Visible = false
		return
	end
	hintLabel.Text = msg
	holder.Visible = true
	hintLabel.TextTransparency = 1
	tween(hintLabel, 0.35, { TextTransparency = 0 })
end

local function header(n: number, title: string, desc: string)
	text(body, { Text = string.format("STAGE %02d  <font color=\"#7864A0\">/  %02d</font>", n, #T.Stages), FontFace = F_HEAVY, TextSize = 14, TextColor3 = BLUE, Size = U2(1, 0, 0, 16), LayoutOrder = 1, ZIndex = 3 })
	text(body, { Text = title, FontFace = F_TITLE, TextSize = 36, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = U2(1, 0, 0, 0), LayoutOrder = 2, ZIndex = 3 })
	text(body, { Text = desc, FontFace = F_BODY, TextSize = 19, TextColor3 = MUTED, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = U2(1, 0, 0, 0), LayoutOrder = 3, ZIndex = 3 })
	new("Frame", { Size = U2(1, 0, 0, 1), BackgroundColor3 = BLUE, BackgroundTransparency = 0.75, BorderSizePixel = 0, LayoutOrder = 4, ZIndex = 3 }, body)
end

local function footer(tag: string, msg: string, order: number)
	local f = new("Frame", { Size = U2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = SOFT, BackgroundTransparency = 0, LayoutOrder = order, ZIndex = 3 }, body)
	corner(f, 5)
	pad(f, 8, 10, 8, 10)
	text(f, { Text = string.format("<font color=\"#FFCE54\"><b>%s</b></font>   %s", tag, msg), FontFace = F_BODY, TextSize = 16, TextColor3 = MUTED, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = U2(1, 0, 0, 0), ZIndex = 3 })
	return f
end

local function addHint(order: number)
	local f = new("Frame", { Size = U2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Visible = false, ZIndex = 3 }, body)
	hintLabel = text(f, { Text = "", FontFace = F_BOLD, TextSize = 16, TextColor3 = C3(255, 214, 120), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = U2(1, 0, 0, 0), ZIndex = 3 })
end

local function addMeter(order: number)
	local f = new("Frame", { Size = U2(1, 0, 0, 54), BackgroundColor3 = SOFT, BackgroundTransparency = 0, LayoutOrder = order, ZIndex = 3 }, body)
	corner(f, 6)
	local title = text(f, { Text = "SHIELD", FontFace = F_HEAVY, TextSize = 13, TextColor3 = MUTED, Position = O2(12, 6), Size = O2(120, 16), ZIndex = 3 })
	local stateL = text(f, { Text = "FULL", FontFace = F_HEAVY, TextSize = 13, TextColor3 = BLUE_HI, TextXAlignment = Enum.TextXAlignment.Right, Position = U2(1, -132, 0, 6), Size = O2(120, 16), ZIndex = 3 })
	local track = new("Frame", { Position = O2(12, 28), Size = U2(1, -24, 0, 14), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3 }, f)
	corner(track, 3)
	local fill = new("Frame", { Size = S2(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4 }, track)
	corner(fill, 3)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(120, 220, 255), C3(0, 150, 255)) }, fill)
	for i = 1, 4 do
		new("Frame", { Position = S2(i / 5, 0), Size = U2(0, 2, 1, 0), BackgroundColor3 = SOFT, BorderSizePixel = 0, ZIndex = 5 }, track)
	end
	meter = { Fill = fill, State = stateL, Title = title }
end

-- ─── pages (ARMOURY + LOADOUT) ───────────────────────────────────────────────────────────────────────
local function clearPage()
	for _, c in page:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function button(parent, label: string, size: UDim2, pos: UDim2, anchor: Vector2, primary: boolean, onClick)
	local pal = if primary == "gold" then GOLDB else GREEN
	local b = new("TextButton", { Size = size, Position = pos, AnchorPoint = anchor, BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, Text = "", ZIndex = 14 }, parent)
	corner(b, 12)
	stroke(b, pal.Rim, 0, 3.5)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(pal.Top0, pal.Top1) }, b)
	new("Frame", { AnchorPoint = V2(0.5, 0), Position = U2(0.5, 0, 0, 4), Size = U2(1, -16, 0.38, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 14 }, b)
	local sc = new("UIScale", {}, b)
	local t = text(b, { Text = label, FontFace = F_TITLE, TextSize = 26, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, Size = S2(1, 1), ZIndex = 15, NoStroke = true })
	new("UIStroke", { Color = pal.Ink, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round }, t)
	b.MouseEnter:Connect(function()
		sfx("Hover")
		tween(sc, 0.15, { Scale = 1.04 })
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.15, { Scale = 1 })
	end)
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		sfx("Click")
		tween(sc, 0.08, { Scale = 0.96 })
		task.delay(0.1, function()
			tween(sc, 0.15, { Scale = 1 })
			busy = false
		end)
		onClick(b, t)
	end)
	return b, t
end

local function pageHeader(eyebrow: string, title: string, desc: string)
	text(page, { Text = eyebrow, FontFace = F_HEAVY, TextSize = 16, TextColor3 = BLUE, Position = O2(0, 0), Size = O2(900, 20), ZIndex = 12 })
	text(page, { Text = title, FontFace = F_TITLE_I, TextSize = 54, Position = O2(0, 22), Size = O2(1200, 62), ZIndex = 12 })
	text(page, { Text = desc, FontFace = F_BODY, TextSize = 21, TextColor3 = MUTED, Position = O2(2, 86), Size = O2(1200, 26), ZIndex = 12 })
end

local function iconBox(parent, image: string?, size: UDim2, pos: UDim2, tint: Color3?)
	local box = new("Frame", { Size = size, Position = pos, BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, ZIndex = 12 }, parent)
	corner(box, 8)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(tint or C3(70, 34, 120), C3(18, 8, 34)) }, box)
	local glowF = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.55), Size = S2(0.8, 0.8), BackgroundColor3 = tint or BLUE, BackgroundTransparency = 0.6, ZIndex = 12 }, box)
	corner(glowF, 400)
	glowF.BackgroundTransparency = 0.82
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, glowF)
	if image and image ~= "" then
		new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.5), Size = S2(0.9, 0.9), ZIndex = 13 }, box)
	end
	return box
end

local function priceTag(parent, icon: string, price: string, color: Color3, pos: UDim2, size: number?)
	local f = new("Frame", { Position = pos, Size = O2(0, size or 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 13 }, parent)
	list(f, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
	new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = O2(size or 26, size or 26), ScaleType = Enum.ScaleType.Fit, ZIndex = 13 }, f)
	text(f, { Text = price, FontFace = F_HEAVY, TextSize = math.floor((size or 26) * 0.8), TextColor3 = color, AutomaticSize = Enum.AutomaticSize.X, Size = O2(0, size or 26), LayoutOrder = 2, ZIndex = 13 })
	return f
end

local function minPrice(items, field)
	local m = math.huge
	for _, it in items or {} do
		local p = tonumber(it[field or "Price"])
		if p and p > 0 and p < m then
			m = p
		end
	end
	return if m == math.huge then nil else m
end

local finale
-- YOU'RE READY
local function loadout()
	local d = data()
	local CC = d.Crates or {}
	local function count(t)
		local n = 0
		for _ in t or {} do
			n += 1
		end
		return n
	end
	local hooks = d.Equip and d.Equip.List and count(d.Equip.List("Hook")) or 0
	local packs = d.Equip and d.Equip.List and count(d.Equip.List("Pack")) or 0
	local guns = 0
	for _, w in (d.WU and d.WU.List) or {} do
		local cfg = d.Weapons and d.Weapons.Weapons and d.Weapons.Weapons[w.Id]
		if cfg and cfg.Kind == "Gun" then
			guns += 1
		end
	end
	local sigs = d.Sig and count(d.Sig.List) or 0
	local sigKey = d.SigCfg.KeyLabel or "SHIFT"
	local ult = d.Ult
	local mj = d.Sig and d.Sig.ById and d.Sig.Default and d.Sig.ById[d.Sig.Default]
	local grapple = d.Ability.Abilities and d.Ability.Abilities.Grapple
	local tiles = {
		{ "WEAPONS", guns, "guns", "Carry 3 guns and a knife. Swap with 1 · 2 · 3.", asset(CC.WeaponCrates and CC.WeaponCrates[1] and CC.WeaponCrates[1].Art and CC.WeaponCrates[1].Art.Full) },
		{ "GRAPPLING HOOKS", hooks, "hooks", "Each with its own colours, range and perk.", asset(grapple and grapple.Icon) },
		{ "SHIELD PACKS", packs, "packs", "Trade shield size and recharge for unique perks.", asset(CC.EquipmentCrates and CC.EquipmentCrates[1] and CC.EquipmentCrates[1].Art and CC.EquipmentCrates[1].Art.Full) },
		{ "SIGNATURES", sigs, "abilities", "A signature ability you cast with " .. sigKey .. ".", asset(mj and mj.Art) },
	}
	-- 2026-11-20: the killstreak ULT was removed (playtest: two ults); its tile only shows if re-enabled
	if ult.Enabled then
		table.insert(tiles, { "ULTIMATE", ult.StreakPerCharge or 10, "kill streak", string.format("%d kills in one life charges %s. Press %s.", ult.StreakPerCharge or 10, ult.Name or "your ULT", ult.KeyLabel or "Z"), nil })
	end
	text(page, { Text = "STAGE 05  ·  LOADOUT", FontFace = F_HEAVY, TextSize = 16, TextColor3 = BLUE, TextXAlignment = Enum.TextXAlignment.Center, Position = O2(0, 0), Size = U2(1, 0, 0, 20), ZIndex = 12 })
	local title = text(page, { Text = "YOU'RE READY", FontFace = F_TITLE_I, TextSize = 84, TextXAlignment = Enum.TextXAlignment.Center, Position = O2(0, 26), Size = U2(1, 0, 0, 96), ZIndex = 12 })
	local tsc = new("UIScale", { Scale = 1.15 }, title)
	title.TextTransparency = 1
	tween(title, 0.5, { TextTransparency = 0 })
	tween(tsc, 0.7, { Scale = 1 })
	text(page, { Text = "Customise your loadout. Find your playstyle. Dominate the battlefield.", FontFace = F_BODY, TextSize = 23, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = O2(0, 124), Size = U2(1, 0, 0, 30), ZIndex = 12 })
	local TW, G = 296, 20
	for i, t in tiles do
		local x = (i - 1) * (TW + G) + (5 - #tiles) * (TW + G) / 2 -- centred in the 5-tile row
		local tile = new("Frame", { Position = O2(x, 190), Size = O2(TW, 380), BackgroundColor3 = CARD, BackgroundTransparency = 0.08, ZIndex = 12 }, page)
		corner(tile, 10)
		stroke(tile, EDGE, 0, 3)
		local sc = new("UIScale", { Scale = 0.9 }, tile)
		task.delay(0.25 + 0.06 * i, function()
			tween(sc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		local box = iconBox(tile, t[5], O2(TW - 20, 180), O2(10, 10))
		if not t[5] then
			for r = 1, 3 do
				local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.5), Size = O2(40 * r, 40 * r), BackgroundTransparency = 1, ZIndex = 13 }, box)
				corner(ring, 200)
				stroke(ring, if r == 1 then C3(255, 120, 90) else BLUE_HI, 0.15 * r, 3)
			end
			new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.5), Size = O2(4, 150), BackgroundColor3 = C3(255, 140, 110), BorderSizePixel = 0, ZIndex = 13 }, box)
		end
		text(tile, { Text = tostring(t[2]), FontFace = F_TITLE_I, TextSize = 52, TextColor3 = BLUE_HI, Position = O2(18, 196), Size = O2(120, 60), ZIndex = 13 })
		text(tile, { Text = string.upper(t[3]), FontFace = F_HEAVY, TextSize = 13, TextColor3 = MUTED, Position = O2(18, 252), Size = O2(200, 16), ZIndex = 13 })
		text(tile, { Text = t[1], FontFace = F_TITLE, TextSize = 20, Position = O2(18, 278), Size = O2(TW - 36, 26), ZIndex = 13 })
		text(tile, { Text = t[4], FontFace = F_BODY, TextSize = 16, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = O2(18, 308), Size = O2(TW - 36, 60), ZIndex = 13 })
	end
	local b = button(page, "ENTER THE BATTLE", O2(560, 92), U2(0.5, 0, 1, -20), V2(0.5, 1), "gold", function(btn)
		finale(btn)
	end)
	b.TextLabel.TextSize = 40
	-- slow light sweep + breathing glow on the CTA
	local sweep = new("Frame", { Size = U2(0, 90, 1, 0), Position = U2(-0.3, 0, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 15, Rotation = 0 }, b)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, sweep)
	b.ClipsDescendants = true
	local glowS = b:FindFirstChildOfClass("UIStroke")
	task.spawn(function()
		while b.Parent do
			sweep.Position = U2(-0.3, 0, 0, 0)
			tween(sweep, 0.9, { Position = U2(1.1, 0, 0, 0) }, Enum.EasingStyle.Sine)
			if glowS then
				tween(glowS, 1.2, { Thickness = 5, Transparency = 0.5 }, Enum.EasingStyle.Sine)
			end
			task.wait(1.3)
			if glowS then
				tween(glowS, 1.2, { Thickness = 1.5, Transparency = 0.2 }, Enum.EasingStyle.Sine)
			end
			task.wait(1.4)
		end
	end)
end

function finale(btn)
	if finishing then
		return
	end
	finishing = true
	sfx("Riser")
	btn.Active = false
	for _, c in page:GetChildren() do
		if c:IsA("GuiObject") then
			local sc = c:FindFirstChildOfClass("UIScale") or new("UIScale", {}, c)
			tween(sc, 0.5, { Scale = 0.96 })
		end
	end
	local flash = new("Frame", { Size = S2(1, 1), BackgroundColor3 = C3(190, 235, 255), BackgroundTransparency = 1, ZIndex = 40 }, gui)
	task.wait(0.45)
	tween(flash, 0.12, { BackgroundTransparency = 0.15 })
	task.wait(0.12)
	sfx("Hit")
	clearPage()
	tween(flash, 0.8, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 1)
	toast.Position = S2(0.5, 0.42)
	playClear("TRAINING", 2.2)
	tTitle.Text = "TRAINING COMPLETE"
	tSub.Text = "HEADING TO THE LOBBY..."
	task.wait(2.6)
	Remote:FireServer("Done")
end

local function showOverlay(on: boolean)
	if on then
		overlay.Visible = true
		tween(overlay, 0.4, { BackgroundTransparency = 0.12 })
		panel.Visible = false
		if not blur then
			blur = new("BlurEffect", { Name = "VantageTutorialBlur", Size = 0 }, Lighting)
		end
		tween(blur, 0.5, { Size = 16 })
		RunService:BindToRenderStep("VantageTutorialMouse", Enum.RenderPriority.Last.Value, function()
			UIS.MouseBehavior = Enum.MouseBehavior.Default
			UIS.MouseIconEnabled = true
		end)
		CAS:BindActionAtPriority("VantageTutorialSink", function()
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward, Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.E, Enum.KeyCode.R)
	else
		overlay.Visible = false
		overlay.BackgroundTransparency = 1
		clearPage()
		if blur then
			blur:Destroy()
			blur = nil
		end
		pcall(function()
			RunService:UnbindFromRenderStep("VantageTutorialMouse")
		end)
		CAS:UnbindAction("VantageTutorialSink")
	end
end

-- ─── stages ──────────────────────────────────────────────────────────────────────────────────
local function advance()
	if pending or finishing then
		return
	end
	pending = true
	local from = cur
	task.delay(0.35, function()
		if cur ~= from then
			return
		end
		playClear(T.Stages[from].Label)
		task.wait(1.15)
		if cur == from then
			Remote:FireServer("Stage", from + 1)
		end
	end)
end

local function buildPanel(n: number)
	clearBody()
	local d = data()
	if n == 1 then
		header(1, "WELCOME TO VANTAGESHOT", "Master your movement. Outmanoeuvre your opponents.")
		addObjective({ "W", "A", "S", "D" }, "Move to the marker", 10)
		addObjective({ "MOUSE" }, "Look around", 11)
		addObjective({ "SPACE" }, "Jump the barrier", 12)
		addHint(30)
	elseif n == 2 then
		local key = (d.Ability.Abilities and d.Ability.Abilities.Grapple and d.Ability.Abilities.Grapple.KeyLabel) or "E"
		header(2, "OWN THE MOMENTUM", "Your Grappling Hook is your greatest movement advantage.")
		addObjective({ key }, "Fire at the gold anchor", 10)
		addObjective({}, "Ride the cable to the top", 11)
		footer("PRO TIP", string.format("Press %s again or SPACE to let go mid-pull. You keep your speed and fly.", key), 20)
		addHint(30)
	elseif n == 3 then
		header(3, "MAKE EVERY SHOT COUNT", "Precision wins fights.")
		addObjective({ "LMB" }, "Hit all 3 targets", 10)
		addObjective({ "RMB" }, "Aim down sights", 11)
		addObjective({ "R" }, "Reload", 12)
		footer("LOADOUT", "1 · 2 · 3 swap guns  ·  F inspect  ·  scoped guns zoom with RMB", 20)
		addHint(30)
	elseif n == 4 then
		header(4, "STAY IN THE FIGHT", "Your Shield Pack keeps you alive when things get dangerous.")
		addMeter(5)
		addObjective({}, "Shield absorbs the hits", 10)
		addObjective({}, "Shield breaks: health is next", 11)
		addObjective({}, "Stay out of fire: it recharges", 12)
		footer("SHIELD", "Damage hits your shield before your health. Avoid fire for a few seconds and it refills. A crack and flash means it broke.", 20)
		addHint(30)
	end
end

local function enterStage(n: number)
	if n == cur then
		return
	end
	cur = n
	pending = false
	stageT0 = os.clock()
	yawAcc, lastLook = 0, nil
	reloadPressed = false
	lastFired = GrappleFeed.FiredAt or 0
	shieldSeen = { Hit = false, Broke = false }
	setRail(n)
	sfx("Tab")
	if n >= 5 then
		showOverlay(true)
		clearPage()
		loadout()
		return
	end
	showOverlay(false)
	panel.Visible = true
	-- slide the panel out, rebuild, slide in
	panel.Position = U2(1, 560, 0.53, 0)
	buildPanel(n)
	tween(panel, 0.55, { Position = PANEL_HOME })
end

-- objective checks (every frame while training)
local function step()
	if cur < 1 or cur > 4 or pending then
		return
	end
	local lp = localPos()
	local c = player.Character
	local age = os.clock() - stageT0
	if cur == 1 then
		local cam = Workspace.CurrentCamera
		local lv = cam.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		if flat.Magnitude > 0.1 then
			flat = flat.Unit
			if lastLook then
				yawAcc += math.deg(math.acos(math.clamp(flat:Dot(lastLook), -1, 1)))
			end
			lastLook = flat
		end
		local o1, o2, o3 = objs[1], objs[2], objs[3]
		if lp and o1 and not o1.Done and Vector2.new(lp.X - L.Marker.X, lp.Z - L.Marker.Z).Magnitude < L.MarkerRadius then
			complete(o1)
		end
		if o2 and not o2.Done and yawAcc > 100 then
			complete(o2)
		end
		if lp and o3 and not o3.Done and lp.Z < L.BarrierZ - 0.5 then
			complete(o3)
			if o1 and not o1.Done then
				complete(o1)
			end
		end
		if o1 and not o1.Done and age > 7 then
			hint("Walk forward into the glowing ring.")
		elseif o3 and not o3.Done and o1 and o1.Done and age > 12 then
			hint("Run at the barrier and tap SPACE to hop over it.")
		elseif o2 and not o2.Done and age > 10 then
			hint("Move your mouse to look around.")
		else
			hint(nil)
		end
	elseif cur == 2 then
		local o1, o2 = objs[1], objs[2]
		local fired = GrappleFeed.FiredAt or 0
		if o1 and not o1.Done and GrappleFeed.BiteAt and GrappleFeed.BiteAt > stageT0 then
			complete(o1)
		end
		if lp and o2 and not o2.Done and lp.Y > L.TowerTop - 1 and lp.Z < L.TowerFront and lp.Z > L.TowerBack - 2 then
			complete(o2)
			if o1 and not o1.Done then
				complete(o1)
			end
		end
		if fired > lastFired and fired > stageT0 then
			lastFired = fired
			task.delay(0.6, function()
				if cur == 2 and objs[1] and not objs[1].Done and not (GrappleFeed.BiteAt and GrappleFeed.BiteAt >= fired) then
					hint("Missed. Aim at the gold anchor panel on the tower and fire again.")
				end
			end)
		elseif o1 and not o1.Done and age > 8 and hintShown == nil then
			hint("Look up at the glowing gold anchor on the tower, then press E.")
		elseif o1 and o1.Done and o2 and not o2.Done and age > 14 and lp and lp.Y < 10 then
			hint("Hook the anchor and hold on: the cable pulls you over the edge.")
		end
	elseif cur == 3 then
		local hits = player:GetAttribute("TutorialHits") or 0
		local o1, o2, o3 = objs[1], objs[2], objs[3]
		if o1 then
			o1.Label.Text = string.format("%s  <font color=\"#B0F951\">%d/%d</font>", o1.Base, math.min(hits, T.TargetsNeeded), T.TargetsNeeded)
			if not o1.Done and hits >= T.TargetsNeeded then
				complete(o1)
			end
		end
		-- most guns use zoom ADS (Mode "Zoom"), which never sets the server's VantageADS flag:
		-- count a real aim hold instead (aim key down for 0.3 s with a gun out)
		if o2 and not o2.Done and c then
			local held = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or adsKeyDown
			if held and c:GetAttribute("VantageADS") ~= nil then
				adsHeldFor = if adsHeldFor > 0 then adsHeldFor else os.clock()
			else
				adsHeldFor = 0
			end
			if c:GetAttribute("VantageADS") == true or (adsHeldFor > 0 and os.clock() - adsHeldFor >= 0.3) then
				complete(o2)
			end
		end
		if o3 and not o3.Done and reloadPressed then
			complete(o3)
		end
		if o1 and not o1.Done and hits == 0 and age > 10 then
			hint("The targets are across the gap. Put your crosshair on one and click.")
		else
			hint(nil)
		end
	elseif cur == 4 and c then
		local s = c:GetAttribute("Shield") or 0
		local max = c:GetAttribute("MaxShield") or 0
		local charging = c:GetAttribute("ShieldRecharging") == true
		if meter and max > 0 then
			meter.Fill.Size = S2(math.clamp(s / max, 0, 1), 1)
			local label, col
			if s <= 0 then
				label, col = "DEPLETED", RED
			elseif charging then
				label, col = "RECHARGING", BLUE_HI
			elseif s < max then
				label, col = "ABSORBING  " .. math.floor(s) .. " / " .. math.floor(max), C3(255, 214, 120)
			else
				label, col = "FULL  " .. math.floor(max), BLUE_HI
			end
			meter.State.Text = label
			meter.State.TextColor3 = col
		end
		local o1, o2, o3 = objs[1], objs[2], objs[3]
		if max > 0 and s < max - 0.5 then
			shieldSeen.Hit = true
		end
		if shieldSeen.Hit and s <= 0 then
			shieldSeen.Broke = true
		end
		if o1 and not o1.Done and shieldSeen.Hit then
			complete(o1)
		end
		if o2 and not o2.Done and shieldSeen.Broke then
			complete(o2)
		end
		if o3 and not o3.Done and shieldSeen.Broke and max > 0 and s >= max - 0.5 then
			complete(o3)
		end
		if shieldSeen.Broke and not (o3 and o3.Done) then
			hint(if charging then "Recharging... stay out of fire." else "Shield down. Waiting for the recharge to kick in.")
		elseif not shieldSeen.Hit then
			hint("Incoming: a training sentry is about to fire at you.")
		else
			hint(nil)
		end
	end
	local all = #objs > 0
	for _, o in objs do
		if not o.Done then
			all = false
			break
		end
	end
	if all then
		hint(nil)
		advance()
	end
end

-- ─── wiring ──────────────────────────────────────────────────────────────────────────────────
local hideHud
local stepConn: RBXScriptConnection? = nil
-- match HUD pieces that make no sense in training (timer / score bar, killstreak meter, ability buttons, ULT)
-- (VantageAbilities stays ENABLED: the grapple refuses to fire while that ScreenGui is off; only its Slots hide)
local HIDE_GUIS = { "VantageMatchHud", "VantageUltOverlay" }
local HIDE_HUD = { "Score", "Killstreak", "Abilities" }
local hidden: { [Instance]: boolean } = {}
hideHud = function(on: boolean)
	if on then
		for _, n in HIDE_GUIS do
			local g = pg:FindFirstChild(n) :: ScreenGui?
			if g and g.Enabled then
				if hidden[g] == nil then hidden[g] = true end
				g.Enabled = false
			end
		end
		local ab = pg:FindFirstChild("VantageAbilities")
		local slots = ab and ab:FindFirstChild("Slots") :: GuiObject?
		if slots and slots.Visible then
			if hidden[slots] == nil then hidden[slots] = true end
			slots.Visible = false
		end
		local root = pg:FindFirstChild("VantageHUD") and pg.VantageHUD:FindFirstChild("Root")
		if root and overlay.Visible and root.Visible then
			if hidden[root] == nil then hidden[root] = true end
			root.Visible = false
		end
		for _, n in HIDE_HUD do
			local f = root and root:FindFirstChild(n) :: GuiObject?
			if f and f.Visible then
				if hidden[f] == nil then hidden[f] = true end
				f.Visible = false
			end
		end
	else
		for o in hidden do
			if o.Parent then
				if o:IsA("ScreenGui") then o.Enabled = true else (o :: GuiObject).Visible = true end
			end
		end
		table.clear(hidden)
	end
end
local skipHeld, skipProgress, skipArmed = false, 0, 0
local function doSkip()
	if finishing then
		return
	end
	finishing = true
	sfx("Click")
	skipText.Text = "SKIPPING..."
	Remote:FireServer("Skip")
end

local function activate(on: boolean)
	if on then
		if gui.Enabled then
			return
		end
		finishing = false
		cur = 0
		skipText.Text = "SKIP TRAINING"
		skipFill.Size = S2(0, 1)
		toast.Position = S2(0.5, 0.29)
		player:SetAttribute("VantageMainMenu", "Play")
		fit()
		gui.Enabled = true
		enterStage(player:GetAttribute("TutorialStage") or 1)
		if not stepConn then
			stepConn = RunService.Heartbeat:Connect(function(dt)
				hideHud(true)
				step()
				if skipHeld and not finishing then
					skipProgress = math.min(1, skipProgress + dt / 1.0)
					skipFill.Size = S2(skipProgress, 1)
					if skipProgress >= 1 then
						skipHeld = false
						doSkip()
					end
				end
			end)
		end
	else
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		showOverlay(false)
		gui.Enabled = false
		toast.Visible = false
		hideHud(false)
		cur = 0
		pending = false
		finishing = false
		clearBody()
	end
end

player:GetAttributeChangedSignal("InTutorial"):Connect(function()
	activate(player:GetAttribute("InTutorial") == true)
end)
player:GetAttributeChangedSignal("TutorialStage"):Connect(function()
	local n = player:GetAttribute("TutorialStage")
	if gui.Enabled and type(n) == "number" then
		enterStage(n)
	end
end)
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

Remote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Reject" then
		pending = false
		if cur >= 5 then
			return
		end
		sfx("Deny")
		hint("Almost. Finish the objective first.")
	elseif kind == "Zap" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		local len = (b - a).Magnitude
		local beam = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Color = if c then C3(255, 255, 255) else RED, Size = Vector3.new(0.22, 0.22, len), CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2) }, Workspace)
		tween(beam, 0.25, { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }, Enum.EasingStyle.Quad)
		Debris:AddItem(beam, 0.3)
		sfx("Whoosh")
	end
end)

UIS.InputBegan:Connect(function(input, gp)
	if not gui.Enabled then
		return
	end
	-- gp is true for keys the weapon system binds (R), so only a focused text box blocks these
	if UIS:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		skipHeld = true
		skipProgress = 0
	elseif input.KeyCode == Enum.KeyCode.R and cur == 3 then
		reloadPressed = true
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		adsKeyDown = true
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.ButtonL2 then
		adsKeyDown = false
	end
	if input.KeyCode == Enum.KeyCode.K then
		skipHeld = false
		if not finishing then
			tween(skipFill, 0.2, { Size = S2(0, 1) })
		end
	end
end)
skip.Activated:Connect(function()
	if finishing then
		return
	end
	if os.clock() - skipArmed < 3 then
		doSkip()
		return
	end
	skipArmed = os.clock()
	sfx("Click")
	skipText.Text = "CLICK AGAIN TO SKIP"
	task.delay(3, function()
		if not finishing then
			skipText.Text = "SKIP TRAINING"
		end
	end)
end)

-- ─── part 2: LOBBY BRIEFING (after ENTER THE BATTLE) ────────────────────────────────────────────
-- Runs on the real lobby: dims the screen, spotlights the actual element (currency pills, CRATES / SHOP /
-- FARM tiles, DEPLOY) and explains it in a shop-style callout. Server attribute TutorialBriefing = pending.
local bgui = new("ScreenGui", { Name = "VantageTutorialBriefing", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 14, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, pg)
local shade = {}
for k = 1, 4 do
	shade[k] = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C3(8, 3, 18), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 1 }, bgui)
end
local hole = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = 2 }, bgui) -- the lit element can't be clicked mid-brief
local ring = new("Frame", { BackgroundTransparency = 1, ZIndex = 3 }, bgui)
corner(ring, 16)
local ringStroke = stroke(ring, BLUE, 0, 4)
local ringGlow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S2(0.5, 0.5), Size = U2(1, 14, 1, 14), ZIndex = 3 }, ring)
corner(ringGlow, 22)
local ringGlowStroke = stroke(ringGlow, BLUE, 0.5, 6)
local callout = scaled(new("Frame", { Name = "Callout", Size = O2(600, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL, ZIndex = 5 }, bgui))
corner(callout, 14)
stroke(callout, EDGE, 0, 3)
local cbody = new("Frame", { Size = U2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 5 }, callout)
pad(cbody, 22, 24, 22, 24)
list(cbody, nil, 12)

local brief = { Step = 1, Shown = false, Target = nil :: any, Done = false }
local function hudEl(cluster: string, name: string): GuiObject?
	local mm = pg:FindFirstChild("VantageMainMenu")
	local hud = mm and mm:FindFirstChild("Hud")
	local c = hud and hud:FindFirstChild(cluster)
	return c and c:FindFirstChild(name) :: GuiObject?
end
local function rectOf(items): (Vector2?, Vector2?)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, o in items do
		if o and o:IsA("GuiObject") and o.AbsoluteSize.X > 1 then
			local p, z = o.AbsolutePosition, o.AbsoluteSize
			x0, y0 = math.min(x0, p.X), math.min(y0, p.Y)
			x1, y1 = math.max(x1, p.X + z.X), math.max(y1, p.Y + z.Y)
		end
	end
	if x0 == math.huge then
		return nil, nil
	end
	-- AbsolutePosition is screen space; this gui's own origin sits at the device inset (e.g. y -58)
	local base = bgui.AbsolutePosition
	return Vector2.new(x0, y0) - base, Vector2.new(x1 - x0, y1 - y0)
end

local function placeBrief()
	local vp = bgui.AbsoluteSize -- this gui's own space (it can be taller than the viewport by the inset)
	local p0, sz
	if brief.Target then
		p0, sz = rectOf(brief.Target())
	end
	if not p0 then
		p0, sz = Vector2.new(vp.X / 2, vp.Y / 2), Vector2.zero
		ring.Visible = false
	else
		p0, sz = p0 - Vector2.new(10, 10), sz + Vector2.new(20, 20)
		-- whole pixels: fractional edges leave a hairline seam between the dim panels
		p0 = Vector2.new(math.floor(p0.X), math.floor(p0.Y))
		sz = Vector2.new(math.ceil(sz.X), math.ceil(sz.Y))
		ring.Visible = true
	end
	shade[1].Position, shade[1].Size = O2(0, 0), O2(vp.X, p0.Y)
	shade[2].Position, shade[2].Size = O2(0, p0.Y + sz.Y), O2(vp.X, math.max(0, vp.Y - p0.Y - sz.Y))
	shade[3].Position, shade[3].Size = O2(0, p0.Y), O2(p0.X, sz.Y)
	shade[4].Position, shade[4].Size = O2(p0.X + sz.X, p0.Y), O2(math.max(0, vp.X - p0.X - sz.X), sz.Y)
	ring.Position, ring.Size = O2(p0.X, p0.Y), O2(sz.X, sz.Y)
	hole.Position, hole.Size = ring.Position, ring.Size
	local cs = callout.AbsoluteSize
	local x
	if not ring.Visible then
		x = (vp.X - cs.X) / 2
	elseif p0.X + sz.X / 2 > vp.X / 2 then
		x = p0.X - cs.X - 28
	else
		x = p0.X + sz.X + 28
	end
	local y = if ring.Visible then p0.Y + sz.Y / 2 - cs.Y / 2 else (vp.Y - cs.Y) / 2
	callout.Position = O2(math.clamp(x, 16, math.max(16, vp.X - cs.X - 16)), math.clamp(y, 16, math.max(16, vp.Y - cs.Y - 16)))
end

local function bText(props)
	props.ZIndex = 6
	return text(cbody, props)
end
local function row(order: number, h: number)
	local f = new("Frame", { Size = U2(1, 0, 0, h), BackgroundColor3 = SOFT, LayoutOrder = order, ZIndex = 6 }, cbody)
	corner(f, 10)
	return f
end
local function img(parent, image, size, pos)
	return new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Size = size, Position = pos, ZIndex = 7 }, parent)
end

local briefSteps
local function showBriefStep(n: number)
	brief.Step = n
	for _, c in cbody:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local d = data()
	local step = briefSteps[n]
	brief.Target = step.Target
	bText({ Text = string.format("LOBBY BRIEFING  <font color=\"#7864A0\">%d / %d</font>", n, #briefSteps), FontFace = F_HEAVY, TextSize = 15, TextColor3 = BLUE, Size = U2(1, 0, 0, 18), LayoutOrder = 1 })
	bText({ Text = step.Title, FontFace = F_TITLE, TextSize = 38, Size = U2(1, 0, 0, 44), LayoutOrder = 2 })
	bText({ Text = step.Body, FontFace = F_BODY, TextSize = 18, TextColor3 = MUTED, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = U2(1, 0, 0, 0), LayoutOrder = 3 })
	step.Build(d)
	-- buttons
	local bar = new("Frame", { Size = U2(1, 0, 0, 60), BackgroundTransparency = 1, LayoutOrder = 50, ZIndex = 6 }, cbody)
	local sk = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = O2(150, 60), ZIndex = 6 }, bar)
	text(sk, { Text = "SKIP BRIEFING", FontFace = F_HEAVY, TextSize = 14, TextColor3 = DIM, Size = S2(1, 1), ZIndex = 7 })
	sk.Activated:Connect(function()
		if brief.Done then
			return
		end
		brief.Done = true
		sfx("Click")
		Remote:FireServer("Skip")
	end)
	local last = n == #briefSteps
	local b = button(bar, if last then "LET'S GO!" else "NEXT  ›", O2(if last then 240 else 200, 60), U2(1, 0, 0, 0), V2(1, 0), if last then "gold" else true, function()
		if brief.Done then
			return
		end
		if last then
			brief.Done = true
			sfx("Clear")
			Remote:FireServer("BriefingDone")
		else
			sfx("Tab")
			showBriefStep(n + 1)
		end
	end)
	b.ZIndex = 6
	-- pop in
	local sc = callout:FindFirstChildOfClass("UIScale")
	callout.BackgroundTransparency = 0.4
	tween(callout, 0.3, { BackgroundTransparency = 0 })
	if sc then
		local base = sc.Scale
		sc.Scale = base * 0.94
		tween(sc, 0.35, { Scale = base }, Enum.EasingStyle.Back)
	end
end

briefSteps = {
	{
		Title = "YOUR CURRENCIES",
		Body = "Everything you unlock is bought with these three. Here's how each one fills up.",
		Target = function()
			return { hudEl("TopRight", "Req"), hudEl("TopRight", "Ord"), hudEl("TopRight", "Ichor") }
		end,
		Build = function(d)
			local reqR, ordR, well = d.Req.Rewards or {}, d.Ord.Rewards or {}, d.Ich.Well or {}
			local items = {
				{ asset(d.Req.Icon), "REQUISITION  ·  REQ", BLUE_HI, string.format("+%d elimination · +%d headshot · +%d assist", reqR.Elimination or 0, reqR.Headshot or 0, reqR.Assist or 0), "Buys weapon skin + equipment crates" },
				{ asset(d.Ord.Icon), string.upper(d.Ord.Name or "Ordnance") .. "  ·  " .. (d.Ord.Short or "ORD"), d.Ord.Color or C3(255, 168, 46), string.format("+%d per match · +%d per win · +%d per level up", ordR.Match or 0, ordR.Win or 0, ordR.LevelUp or 0), "Buys Arsenal Crates: a new gun each" },
				{ asset(d.Ich.Icon), string.upper(d.Ich.Name or "Ichor"), (d.Ich.Colors and d.Ich.Colors.Gold) or C3(255, 201, 74), string.format("Brews in your Ichor Farm: %d / hour to start", (well.Rate and well.Rate[1]) or 0), "Buys Signature abilities" },
			}
			for k, it in items do
				local f = row(10 + k, 86)
				img(f, it[1], O2(62, 62), O2(12, 12))
				text(f, { Text = it[2], FontFace = F_TITLE, TextSize = 22, TextColor3 = it[3], Position = O2(88, 8), Size = O2(460, 26), ZIndex = 7 })
				text(f, { Text = it[4], FontFace = F_BOLD, TextSize = 15, Position = O2(88, 36), Size = O2(460, 20), ZIndex = 7 })
				text(f, { Text = it[5], FontFace = F_BODY, TextSize = 15, TextColor3 = MUTED, Position = O2(88, 58), Size = O2(460, 20), ZIndex = 7 })
			end
		end,
	},
	{
		Title = "CRATES",
		Body = "Spend REQ and ORD here. Each crate rolls a random reward from its pool.",
		Target = function()
			return { hudEl("Left", "Crates") }
		end,
		Build = function(d)
			local CC = d.Crates or {}
			local skins = CC.Crates or {}
			local list = {
				{ skins[1], "Weapon skins", asset(d.Req.Icon) },
				{ skins[#skins], "Top-tier skins", asset(d.Req.Icon) },
				{ CC.WeaponCrates and CC.WeaponCrates[1], "A new gun, never a duplicate", asset(d.Ord.Icon) },
				{ CC.EquipmentCrates and CC.EquipmentCrates[1], "Hook + pack shards (3 unlock)", asset(d.Req.Icon) },
			}
			local grid = new("Frame", { Size = U2(1, 0, 0, 2 * 92 + 10), BackgroundTransparency = 1, LayoutOrder = 10, ZIndex = 6 }, cbody)
			for k, it in list do
				local c = it[1]
				if c then
					local f = new("Frame", { Size = O2(271, 92), Position = O2(((k - 1) % 2) * 281, math.floor((k - 1) / 2) * 102), BackgroundColor3 = SOFT, ZIndex = 6 }, grid)
					corner(f, 10)
					img(f, asset(c.Art and (c.Art.Full or c.Art.Body)), O2(76, 76), O2(8, 8))
					text(f, { Text = string.upper(c.Name or c.Id), FontFace = F_TITLE, TextSize = 17, Position = O2(90, 8), Size = O2(175, 22), ZIndex = 7, TextTruncate = Enum.TextTruncate.AtEnd })
					text(f, { Text = it[2], FontFace = F_BODY, TextSize = 13, TextColor3 = MUTED, Position = O2(90, 32), Size = O2(175, 18), ZIndex = 7, TextTruncate = Enum.TextTruncate.AtEnd })
					local pt = priceTag(f, it[3], fmt(c.Price), BLUE, O2(90, 56), 24)
					pt.ZIndex = 7
				end
			end
		end,
	},
	{
		Title = "SHOP  ·  SIGNATURES",
		Body = "Spend Ichor on Signature abilities: roll the Ichor Crate, or buy today's picks outright.",
		Target = function()
			return { hudEl("Left", "Shop") }
		end,
		Build = function(d)
			local sig = d.Sig
			local ichIcon = asset(d.Ich.Icon)
			local gold = (d.Ich.Colors and d.Ich.Colors.Gold) or C3(255, 201, 74)
			if sig and sig.Crate then
				local f = row(10, 96)
				img(f, asset(sig.Crate.Art and sig.Crate.Art.Hero), O2(80, 80), O2(8, 8))
				text(f, { Text = string.upper(sig.Crate.Name or "Ichor Crate"), FontFace = F_TITLE, TextSize = 20, Position = O2(100, 10), Size = O2(300, 24), ZIndex = 7 })
				text(f, { Text = "A random Signature you don't own yet", FontFace = F_BODY, TextSize = 15, TextColor3 = MUTED, Position = O2(100, 36), Size = O2(440, 20), ZIndex = 7 })
				priceTag(f, ichIcon, fmt(sig.Crate.Price), gold, O2(100, 60), 24).ZIndex = 7
			end
			if sig and sig.DailyToday then
				local ok, ids = pcall(sig.DailyToday, os.time())
				local sd = ok and type(ids) == "table" and ids[1] and sig.ById[ids[1]]
				if sd then
					local f = row(11, 96)
					img(f, asset(sd.Art), O2(80, 80), O2(8, 8))
					text(f, { Text = "DAILY SHOP  ·  " .. sd.Name, FontFace = F_TITLE, TextSize = 20, Position = O2(100, 10), Size = O2(440, 24), ZIndex = 7 })
					text(f, { Text = string.format("%d new picks every day. Buy the one you want.", sig.DailyCount or 2), FontFace = F_BODY, TextSize = 15, TextColor3 = MUTED, Position = O2(100, 36), Size = O2(440, 20), ZIndex = 7 })
					priceTag(f, ichIcon, fmt(sd.Price), gold, O2(100, 60), 24).ZIndex = 7
				end
			end
		end,
	},
	{
		Title = "ICHOR FARM",
		Body = "Your Ichor brews here, even while you're away. Come back, claim it, then spend REQ to upgrade the farm so it brews faster.",
		Target = function()
			return { hudEl("Left", "Farm") }
		end,
		Build = function(d)
			local well = d.Ich.Well or {}
			local rate = well.Rate or {}
			local cap = well.Cap or {}
			local f = row(10, 96)
			img(f, asset(d.Ich.Icon), O2(72, 72), O2(12, 12))
			text(f, { Text = string.format("%d  →  %d ICHOR / HOUR", rate[1] or 0, rate[#rate] or 0), FontFace = F_TITLE, TextSize = 22, Position = O2(100, 12), Size = O2(440, 26), ZIndex = 7 })
			text(f, { Text = string.format("Stores up to %d hours at level 1  ·  %d farm levels", cap[1] or 0, #rate), FontFace = F_BODY, TextSize = 15, TextColor3 = MUTED, Position = O2(100, 40), Size = O2(440, 20), ZIndex = 7 })
			priceTag(f, asset(d.Req.Icon), "first upgrade " .. fmt(well.UpgradeCost and well.UpgradeCost[1]), BLUE, O2(100, 62), 22).ZIndex = 7
		end,
	},
	{
		Title = "PLAY TO EARN",
		Body = "Every match pays REQ and ORD. Win, level up, open crates and build the loadout that fits how you play.",
		Target = function()
			return { hudEl("Bottom", "Deploy") }
		end,
		Build = function()
			local f = new("Frame", { Size = U2(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 10, ZIndex = 6 }, cbody)
			list(f, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
			for k, w in { "PLAY", "EARN", "UNLOCK", "EQUIP", "DOMINATE" } do
				local chip = new("Frame", { Size = O2(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = if k == 5 then BLUE else SOFT, LayoutOrder = k * 2, ZIndex = 6 }, f)
				corner(chip, 8)
				pad(chip, 0, 10, 0, 10)
				text(chip, { Text = w, FontFace = F_TITLE, TextSize = 17, TextColor3 = WHITE, AutomaticSize = Enum.AutomaticSize.X, Size = O2(0, 40), ZIndex = 7 })
				if k < 5 then
					text(f, { Text = "›", FontFace = F_TITLE, TextSize = 22, TextColor3 = BLUE, Size = O2(10, 40), LayoutOrder = k * 2 + 1, ZIndex = 6 })
				end
			end
		end,
	},
}

local function briefShow(on: boolean)
	if on == brief.Shown then
		return
	end
	brief.Shown = on
	if on then
		fit()
		bgui.Enabled = true
		showBriefStep(brief.Step)
		RunService:BindToRenderStep("VantageBriefing", Enum.RenderPriority.Last.Value, function()
			placeBrief()
			local t = os.clock()
			ringGlowStroke.Transparency = 0.45 + 0.35 * math.sin(t * 4)
			ringStroke.Thickness = 4 + math.sin(t * 4)
		end)
		CAS:BindActionAtPriority("VantageBriefSink", function()
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward, Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump)
	else
		bgui.Enabled = false
		pcall(function()
			RunService:UnbindFromRenderStep("VantageBriefing")
		end)
		CAS:UnbindAction("VantageBriefSink")
	end
end

task.spawn(function()
	local readySince = nil
	while true do
		task.wait(0.3)
		local mm = pg:FindFirstChild("VantageMainMenu") :: ScreenGui?
		local want = player:GetAttribute("TutorialBriefing") == true and not player:GetAttribute("InTutorial")
			and mm ~= nil and mm.Enabled and player:GetAttribute("InLobby") == true and player:GetAttribute("MatchStatus") == nil
		if not player:GetAttribute("TutorialBriefing") then
			brief.Step, brief.Done = 1, false
		end
		if want then
			readySince = readySince or os.clock()
			if os.clock() - readySince > 1.4 then -- let the lobby HUD slide in first
				briefShow(true)
			end
		else
			readySince = nil
			briefShow(false)
		end
	end
end)

-- ─── replay (lobby pill + /tutorial) ─────────────────────────────────────────────────────────────────────────
local function replay()
	if player:GetAttribute("InTutorial") or player:GetAttribute("MatchStatus") ~= nil or player.Team ~= nil then
		sfx("Deny")
		return
	end
	sfx("Click")
	Remote:FireServer("Replay")
end
local rgui = new("ScreenGui", { Name = "VantageTutorialReplay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 11, Enabled = false }, pg)
local rbtn = new("TextButton", { AnchorPoint = V2(0, 1), Position = U2(0, 22, 1, -22), Size = O2(200, 38), BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, AutoButtonColor = false, Text = "" }, rgui)
table.insert(scales, new("UIScale", {}, rbtn))
corner(rbtn, 6)
local rStroke = stroke(rbtn, EDGE, 0.2, 2.5)
text(rbtn, { Text = "REPLAY TRAINING", FontFace = F_TITLE, TextSize = 18, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, Size = S2(1, 1) })
rbtn.MouseEnter:Connect(function()
	tween(rStroke, 0.15, { Transparency = 0.1 })
end)
rbtn.MouseLeave:Connect(function()
	tween(rStroke, 0.15, { Transparency = 0.2 })
end)
rbtn.Activated:Connect(replay)
task.spawn(function()
	while true do
		task.wait(0.5)
		local mm = pg:FindFirstChild("VantageMainMenu") :: ScreenGui?
		local show = mm ~= nil and mm.Enabled and player:GetAttribute("InLobby") == true and not player:GetAttribute("InTutorial")
			and player:GetAttribute("MatchStatus") == nil and player:GetAttribute("TutorialDone") ~= nil and not player:GetAttribute("TutorialBriefing")
		if rgui.Enabled ~= show then
			if show then
				fit()
			end
			rgui.Enabled = show
		end
	end
end)
pcall(function()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "VantageTutorialCommand"
		cmd.PrimaryAlias = "/tutorial"
		cmd.SecondaryAlias = "/training"
		cmd.Parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
		cmd.Triggered:Connect(replay)
	end
end)

fit()
if player:GetAttribute("InTutorial") == true then
	activate(true)
end
