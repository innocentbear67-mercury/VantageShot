--!nonstrict
--[[
	VANTAGE — Admin Panel (client, 2026-11-20)
	Everyone runs this script for the announcement banner; the panel itself is only built for admins.
	Open / close: F2 or the small ADMIN button (bottom-left). The server re-checks every request
	(ServerScriptService.VantageAdminPanel), so this UI grants nothing on its own.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local ADMINS = { [11707170334] = true } -- keep in sync with the server script

local Fn = ReplicatedStorage:WaitForChild("VantageAdminPanel", 30)
local AnnounceEv = ReplicatedStorage:WaitForChild("VantageAdminAnnounce", 30)

local C = {
	bg = Color3.fromRGB(14, 17, 24), panel = Color3.fromRGB(22, 27, 38), panel2 = Color3.fromRGB(30, 36, 50),
	btn = Color3.fromRGB(42, 50, 68), accent = Color3.fromRGB(70, 160, 255), good = Color3.fromRGB(60, 190, 110),
	bad = Color3.fromRGB(215, 70, 70), gold = Color3.fromRGB(235, 185, 60), text = Color3.fromRGB(235, 240, 250),
	dim = Color3.fromRGB(140, 150, 170),
}
local RARITY = {
	Common = Color3.fromRGB(110, 115, 125), Uncommon = Color3.fromRGB(70, 150, 90), Rare = Color3.fromRGB(55, 115, 210),
	Epic = Color3.fromRGB(140, 70, 210), Legendary = Color3.fromRGB(215, 150, 35), Mythic = Color3.fromRGB(210, 55, 70),
	Exotic = Color3.fromRGB(40, 190, 190),
}

local function mk(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end
local function pad(o, p) mk("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }, o) end

------------------------------------------------------------------ announcement banner (everyone)
local bannerGui = mk("ScreenGui", { Name = "VantageAdminAnnounce", ResetOnSpawn = false, DisplayOrder = 950, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))
local bannerSeq = 0
if AnnounceEv then
	AnnounceEv.OnClientEvent:Connect(function(text, from)
		bannerSeq += 1
		local seq = bannerSeq
		bannerGui:ClearAllChildren()
		local f = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = UDim2.new(0, 640, 0, 74),
			BackgroundColor3 = C.bg, BackgroundTransparency = 0.1, BorderSizePixel = 0 }, bannerGui)
		corner(f, 10)
		mk("UIStroke", { Color = C.gold, Thickness = 2 }, f)
		mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 6), Size = UDim2.new(1, -32, 0, 18), Font = Enum.Font.GothamBold,
			TextSize = 13, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left, Text = "ANNOUNCEMENT  ·  " .. string.upper(tostring(from)) }, f)
		mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 26), Size = UDim2.new(1, -32, 0, 40), Font = Enum.Font.GothamBold,
			TextSize = 20, TextColor3 = C.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(text) }, f)
		TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
		task.delay(7, function()
			if seq ~= bannerSeq or not f.Parent then return end
			TweenService:Create(f, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
			task.delay(0.35, function() if seq == bannerSeq then f:Destroy() end end)
		end)
	end)
end

------------------------------------------------------------------ panel (admins only)
if not (ADMINS[player.UserId] or RunService:IsStudio()) or not Fn then
	return
end

local gui = mk("ScreenGui", { Name = "VantageAdminPanel", ResetOnSpawn = false, DisplayOrder = 960, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player.PlayerGui)

local toggleBtn = mk("TextButton", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(0, 64, 0, 24),
	BackgroundColor3 = C.bg, BackgroundTransparency = 0.25, Text = "ADMIN", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.gold, BorderSizePixel = 0 }, gui)
corner(toggleBtn, 5)
mk("UIStroke", { Color = C.gold, Transparency = 0.5 }, toggleBtn)

local main = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 860, 0, 540),
	BackgroundColor3 = C.bg, BorderSizePixel = 0, Visible = false }, gui)
corner(main, 10)
mk("UIStroke", { Color = C.accent, Transparency = 0.4, Thickness = 1.5 }, main)
mk("UISizeConstraint", { MaxSize = Vector2.new(860, 540) }, main)
local modal = mk("TextButton", { Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, Text = "", Modal = true }, main) -- frees the mouse in first person

-- title bar (drag to move)
local title = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, main)
corner(title, 10)
mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(0.6, 0, 1, 0), Font = Enum.Font.GothamBlack, TextSize = 16,
	TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "VANTAGESHOT  ·  ADMIN PANEL" }, title)
local closeBtn = mk("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 28, 0, 28), BackgroundColor3 = C.bad,
	Text = "X", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text, BorderSizePixel = 0 }, title)
corner(closeBtn, 6)
do
	local dragging, startPos, startMouse
	title.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, startPos, startMouse = true, main.Position, i.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Position - startMouse
			main.Position = startPos + UDim2.new(0, d.X, 0, d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
end

-- status line
local status = mk("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -8), Size = UDim2.new(1, -24, 0, 22), BackgroundColor3 = C.panel,
	Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "  Pick a target on the left, then click an action.", BorderSizePixel = 0 }, main)
corner(status, 5)
local function setStatus(ok, msg)
	status.Text = "  " .. tostring(msg)
	status.TextColor3 = ok == nil and C.dim or (ok and C.good or C.bad)
end

------------------------------------------------------------------ target list
local target = "ALL"
local left = mk("Frame", { Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(0, 190, 1, -90), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, main)
corner(left, 8)
mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 22), Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "TARGET" }, left)
local plist = mk("ScrollingFrame", { Position = UDim2.new(0, 6, 0, 28), Size = UDim2.new(1, -12, 1, -34), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, left)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, plist)

local targetBtns = {}
local function paintTargets()
	for id, b in targetBtns do
		b.BackgroundColor3 = (tostring(id) == tostring(target)) and C.accent or C.btn
	end
end
local function rebuildTargets()
	for _, b in targetBtns do b:Destroy() end
	table.clear(targetBtns)
	local function add(id, text, order)
		local b = mk("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.btn, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
			Text = text, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = order, BorderSizePixel = 0, AutoButtonColor = true }, plist)
		corner(b, 5)
		b.MouseButton1Click:Connect(function()
			target = id
			paintTargets()
			setStatus(nil, "Target: " .. text)
		end)
		targetBtns[id] = b
	end
	add("ALL", "★ EVERYONE (" .. #Players:GetPlayers() .. ")", 0)
	local list = Players:GetPlayers()
	table.sort(list, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)
	for i, p in list do
		add(p.UserId, (p == player and "(you) " or "") .. p.DisplayName .. "  @" .. p.Name, i)
	end
	if target ~= "ALL" and not Players:GetPlayerByUserId(target) then target = "ALL" end
	paintTargets()
end
Players.PlayerAdded:Connect(rebuildTargets)
Players.PlayerRemoving:Connect(function() task.defer(rebuildTargets) end)
rebuildTargets()

------------------------------------------------------------------ request helper
local busy = false
local function send(action, a, b)
	if busy then return end
	busy = true
	setStatus(nil, "Working...")
	local ok, res, msg = pcall(function() return Fn:InvokeServer(action, target, a, b) end)
	busy = false
	if not ok then setStatus(false, "Error: " .. tostring(res)) return end
	setStatus(res, msg)
end

------------------------------------------------------------------ tabs
local tabBar = mk("Frame", { Position = UDim2.new(0, 212, 0, 50), Size = UDim2.new(1, -224, 0, 32), BackgroundTransparency = 1 }, main)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, tabBar)
local pages, tabBtns = {}, {}
local function showTab(name)
	for n, p in pages do p.Visible = (n == name) end
	for n, b in tabBtns do b.BackgroundColor3 = (n == name) and C.accent or C.panel2 end
end
local function page(name, scroll)
	local p
	if scroll ~= false then
		p = mk("ScrollingFrame", { Position = UDim2.new(0, 212, 0, 90), Size = UDim2.new(1, -224, 1, -130), BackgroundColor3 = C.panel, BorderSizePixel = 0,
			ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, main)
		mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, p)
		pad(p, 10)
	else
		p = mk("Frame", { Position = UDim2.new(0, 212, 0, 90), Size = UDim2.new(1, -224, 1, -130), BackgroundColor3 = C.panel, BorderSizePixel = 0, Visible = false }, main)
	end
	corner(p, 8)
	pages[name] = p
	local b = mk("TextButton", { Size = UDim2.new(0, 112, 1, 0), BackgroundColor3 = C.panel2, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
		Text = name, BorderSizePixel = 0 }, tabBar)
	corner(b, 6)
	b.MouseButton1Click:Connect(function() showTab(name) end)
	tabBtns[name] = b
	return p
end

local order = 0
local function section(parent, text, cell)
	order += 1
	local s = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
	mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left, Text = text }, s)
	local g = mk("Frame", { Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, s)
	mk("UIGridLayout", { CellSize = cell or UDim2.new(0, 112, 0, 30), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, g)
	return g
end
local function button(parent, text, color, cb)
	local b = mk("TextButton", { BackgroundColor3 = color or C.btn, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text, Text = text,
		TextWrapped = true, BorderSizePixel = 0, AutoButtonColor = true }, parent)
	corner(b, 5)
	b.MouseButton1Click:Connect(cb)
	return b
end
local function textbox(parent, placeholder, default)
	local t = mk("TextBox", { BackgroundColor3 = C.bg, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text, PlaceholderText = placeholder,
		PlaceholderColor3 = C.dim, Text = default or "", ClearTextOnFocus = false, BorderSizePixel = 0 }, parent)
	corner(t, 5)
	mk("UIStroke", { Color = C.btn }, t)
	return t
end
local function short(n)
	if n >= 1000000 then return (n / 1000000) .. "M" elseif n >= 1000 then return (n / 1000) .. "K" end
	return tostring(n)
end

------------------------------------------------------------------ ECONOMY
local eco = page("ECONOMY")
local CUR = {
	{ "REQ", "REQ", { 1000, 10000, 100000, 1000000 }, true },
	{ "ORD", "ORD", { 50, 500, 5000, 50000 }, true },
	{ "ICHOR", "ICHOR", { 100, 1000, 10000, 100000 }, true },
	{ "XP", "ACCOUNT EXP", { 1000, 10000, 100000, 1000000 }, false },
}
for _, c in CUR do
	local action, label, presets, canTake = c[1], c[2], c[3], c[4]
	local g = section(eco, label, UDim2.new(0, 84, 0, 30))
	for _, n in presets do
		button(g, "+" .. short(n), C.good, function() send(action, n) end)
	end
	local box = textbox(g, "amount")
	button(g, "GIVE", C.accent, function()
		local n = tonumber(box.Text)
		if n and n > 0 then send(action, math.floor(n)) else setStatus(false, "Type an amount first.") end
	end)
	if canTake then
		button(g, "TAKE", C.bad, function()
			local n = tonumber(box.Text)
			if n and n > 0 then send(action, -math.floor(n)) else setStatus(false, "Type an amount first.") end
		end)
	end
end
do
	local g = section(eco, "SEASON PASS")
	button(g, "PREMIUM PASS", C.gold, function() send("PASS_PREMIUM") end)
	button(g, "+1 TIER", C.btn, function() send("PASS_TIERS", 1) end)
	button(g, "+10 TIERS", C.btn, function() send("PASS_TIERS", 10) end)
	button(g, "MAX PASS", C.btn, function() send("PASS_MAX") end)
end

------------------------------------------------------------------ SKINS (filled once the catalog arrives)
local skinsPage = page("SKINS", false)
local weaponCol = mk("ScrollingFrame", { Position = UDim2.new(0, 8, 0, 44), Size = UDim2.new(0, 130, 1, -52), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, skinsPage)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, weaponCol)
local skinGrid = mk("ScrollingFrame", { Position = UDim2.new(0, 146, 0, 44), Size = UDim2.new(1, -154, 1, -52), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, skinsPage)
mk("UIGridLayout", { CellSize = UDim2.new(0, 148, 0, 40), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, skinGrid)
local skinTop = mk("Frame", { Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(1, -16, 0, 30), BackgroundTransparency = 1 }, skinsPage)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, skinTop)
local function topBtn(text, color, w, cb)
	local b = button(skinTop, text, color, cb)
	b.Size = UDim2.new(0, w, 1, 0)
	return b
end
topBtn("ALL GUNS + ALL SKINS", C.gold, 190, function() send("ALLSKINS") end)
local skinHint = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0, 360, 1, 0), Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "Pick a gun, then click a skin to give it." }, skinTop)

------------------------------------------------------------------ UNLOCKS
local unl = page("UNLOCKS")
local masteryBox

------------------------------------------------------------------ PLAYERS
local pl = page("PLAYERS")
do
	local g = section(pl, "MODERATION  (ignores you when the target is EVERYONE)")
	button(g, "HEAL", C.good, function() send("HEAL") end)
	button(g, "KILL", C.bad, function() send("KILL") end)
	button(g, "BRING TO ME", C.btn, function() send("BRING") end)
	button(g, "GO TO", C.btn, function()
		if target == "ALL" then setStatus(false, "Pick one player for GO TO.") else send("GOTO") end
	end)
	local kickArm = 0
	local kb
	kb = button(g, "KICK", C.bad, function()
		if os.clock() - kickArm > 3 then
			kickArm = os.clock()
			kb.Text = "CONFIRM KICK"
			setStatus(nil, "Click KICK again within 3 s to confirm.")
			task.delay(3, function() kb.Text = "KICK" end)
		else
			kickArm = 0
			kb.Text = "KICK"
			send("KICK")
		end
	end)
	local a = section(pl, "SERVER ANNOUNCEMENT  (shown to everyone, text is filtered)", UDim2.new(0, 440, 0, 34))
	local box = textbox(a, "type a message…")
	box.TextXAlignment = Enum.TextXAlignment.Left
	pad(box, 8)
	local sendB = button(a, "SEND ANNOUNCEMENT", C.accent, function()
		if #box.Text > 0 then send("ANNOUNCE", box.Text) end
	end)
end

------------------------------------------------------------------ catalog
local loaded = false
local function loadCatalog()
	if loaded then return end
	local ok, good, cat = pcall(function() return Fn:InvokeServer("Catalog") end)
	if not (ok and good and type(cat) == "table") then
		setStatus(false, "Could not load the catalog: " .. tostring(cat or good))
		return
	end
	loaded = true

	-- skins
	local weaponBtns = {}
	local function showWeapon(w)
		for n, b in weaponBtns do b.BackgroundColor3 = (n == w) and C.accent or C.btn end
		for _, c in skinGrid:GetChildren() do if c:IsA("GuiButton") then c:Destroy() end end
		local list = cat.Skins[w] or {}
		skinHint.Text = w .. ": " .. #list .. " skins. Click one to give it."
		for i, s in list do
			local b = button(skinGrid, tostring(s.Name) .. "\n" .. string.upper(tostring(s.Rarity or "")), RARITY[s.Rarity] or C.btn, function()
				send("SKIN", s.Key)
			end)
			b.LayoutOrder = i
			b.TextSize = 11
		end
	end
	for i, w in cat.Weapons do
		local b = button(weaponCol, w, C.btn, function() showWeapon(w) end)
		b.Size = UDim2.new(1, -4, 0, 30)
		b.LayoutOrder = i
		weaponBtns[w] = b
	end
	if cat.Weapons[1] then showWeapon(cat.Weapons[1]) end

	-- unlocks
	local g = section(unl, "UNLOCK GUN (crate guns)")
	button(g, "ALL GUNS", C.gold, function() send("ALLGUNS") end)
	for _, id in cat.Guns do button(g, id, C.btn, function() send("GUN", id) end) end

	local s = section(unl, "GIVE SIGNATURE")
	for _, it in cat.Sigs do button(s, it.Name, Color3.fromRGB(95, 60, 150), function() send("SIG", it.Id) end) end

	local cr = section(unl, "GIVE CRATES", UDim2.new(0, 112, 0, 30))
	for _, id in cat.Crates do
		button(cr, "+1 " .. id, C.btn, function() send("CRATE", id, 1) end)
		button(cr, "+10 " .. id, C.btn, function() send("CRATE", id, 10) end)
	end

	local m = section(unl, "WEAPON MASTERY XP  (amount box → click a gun)")
	masteryBox = textbox(m, "amount", "5000")
	for _, w in cat.MasteryWeapons do
		button(m, w, C.btn, function()
			local n = tonumber(masteryBox.Text)
			if n and n > 0 then send("MASTERY", w, math.floor(n)) else setStatus(false, "Type an amount first.") end
		end)
	end
end

------------------------------------------------------------------ open / close
local open = false
local function setOpen(v)
	open = v
	main.Visible = v
	modal.Visible = v
	if v then
		rebuildTargets()
		task.spawn(loadCatalog)
		RunService:BindToRenderStep("VantageAdminMouse", Enum.RenderPriority.Last.Value + 5, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep("VantageAdminMouse") end)
	end
end
showTab("ECONOMY")
toggleBtn.MouseButton1Click:Connect(function() setOpen(not open) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(i, gp)
	if i.KeyCode == Enum.KeyCode.F2 and not UserInputService:GetFocusedTextBox() then
		setOpen(not open)
	end
end)
