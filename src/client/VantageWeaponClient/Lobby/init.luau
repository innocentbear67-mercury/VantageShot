--!nocheck
--[[
	VANTAGE — Lobby (client)  ·  Hypershot-style lobby HUD (2026-11-15)
	Replaces the old MainMenu (backup: ServerStorage._MainMenuRemoved_20261115). Players walk around
	Workspace.HyperLobby (server: LobbyService) and this HUD sits over the hall:
	  top-left      Settings · Rewards · Store (in Roblox's top bar row)
	  left          tiles: Loadout · Operators · Shop · Inventory · Challenges · Trading + Operation card
	  top-right     REQ pill (+ opens Store) and the server's top Legionaries by level
	  bottom        MORE MODES · DEPLOY (F) · BATTLEPASS, speech bubble above
	  bottom-right  profile card → Profile
	Queue flow = the MatchService flow, restyled: DEPLOY queues, the bubble shows the queue,
	MATCH FOUND pops the team card, the suit-up shot plays, the server drops the squad.
	The ScreenGui keeps the name "VantageMainMenu" (music, armory, scoreboard, aircraft and the intro
	watch it): enabled = in the lobby. Player attribute VantageMainMenu = "Open" / "Play".
	API: Lobby.Start(ctx)  ctx = { Input, Hud, Settings, Effects, Armory }   Lobby.IsOpen()
	Studio hook: player attribute DevLobbyNav = "Shop" | "Challenges" | … | "Close".
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local G = require(script:WaitForChild("Gloss"))
local HS = require(script:WaitForChild("HS"))
local CasesHS = require(script:WaitForChild("CasesHS"))
local Pages = require(script:WaitForChild("Pages"))
local SuitUp = require(script.Parent:WaitForChild("SuitUp"))
-- CustomiseScreen / OperatorsScreen / ShopScreen (armour-era) retired 2026-11-17 -> ServerStorage._ArmourArchive_20261117
local ShopScreen = nil
local CratesScreen = require(script:WaitForChild("CratesScreen"))
local CrateOpening = require(script:WaitForChild("CrateOpening"))
local LobbySkin = require(script:WaitForChild("LobbySkin"))
local LoadoutScreen = require(script:WaitForChild("LoadoutScreen"))
local CoinBurst = require(script:WaitForChild("CoinBurst")) -- 2026-11-18: claim VFX (coins fly into the REQ / ORD pills)

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local MatchConfig = require(Vantage:WaitForChild("MatchConfig"))
local Assets = require(Vantage:WaitForChild("UI"):WaitForChild("LobbyAssets"))
local ReqConfig = require(Vantage:WaitForChild("Requisition"):WaitForChild("RequisitionConfig"))
local matchRequest = Remotes:WaitForChild("MatchRequest")

local C, F = G.C, G.F
local new, tween, text = G.new, G.tween, G.text
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale

local player = Players.LocalPlayer
local Lobby = {}

local MODES = {
	-- 2026-11-20: every live mode is queued at a chosen team size (1v1 .. 6v6, MatchConfig.SizeClasses)
	{ Id = "TDM", Name = "Deathmatch", Short = "DEATHMATCH", Color = "Red", Desc = "Two squads, 1v1 up to 6v6. First team to the score limit wins." },
	{ Id = "RTDM", Name = "Ranked Deathmatch", Short = "RANKED", Color = "Purple", Desc = "Deathmatch for Ranked Points, 1v1 up to 6v6. Climb from Wood to Legend." },
	{ Id = "TAC", Name = "Tactical", Short = "TACTICAL", Color = "Blue", Desc = "Slower pace, every fight counts. 1v1 up to 6v6." },
	{ Id = "DUEL", Name = "Shootout", Short = "SHOOTOUT", Color = "Orange", Desc = "One opponent (or two), nowhere to hide." },
	{ Id = "CTF", Name = "Capture the Flag", Short = "CTF", Color = "Green", Desc = "Steal their flag, defend your own." },
}
for _, m in MODES do
	local cfg = MatchConfig.Modes[m.Id]
	m.Live = cfg ~= nil and cfg.Live == true
	m.TeamSize = cfg and cfg.TeamSize or 0
	m.Sizes = cfg and cfg.Sizes or nil
end
local MAP_NAME = tostring(MatchConfig.Map and MatchConfig.Map.Name or "Live Fire")

local ctx
local gui, hudRoot, fader, modalLayer
local ui = {}
local clusters = {}
local state = { Selected = 1, Modal = nil, Screen = nil }
local flow = { Stage = nil, Token = 0, QueueStart = 0, Note = "", InMatch = false }
local data = nil -- ProgressionGet snapshot

-- ─── helpers ───────────────────────────────────────────────────────────────────────────
local function MF()
	return Vantage:FindFirstChild("Match")
end
local function phase()
	local m = MF()
	return m and m:GetAttribute("Phase") or "Idle"
end
local function phaseLeft()
	local m = MF()
	local e = m and m:GetAttribute("PhaseEnds")
	return if e then e - Workspace:GetServerTimeNow() else 0
end
local function myStatus()
	return player:GetAttribute("MatchStatus")
end
local function selectedMode()
	return MODES[state.Selected]
end
-- team size picked for a mode (default: its standard size) and the queue id for it ("TDM_4")
state.Size = {}
local function sizeOf(m)
	local s = state.Size[m.Id]
	if s and m.Sizes and table.find(m.Sizes, s) then
		return s
	end
	return m.TeamSize
end
local function queueId(m)
	return if MatchConfig.Variant then MatchConfig.Variant(m.Id, sizeOf(m)) else m.Id
end
local function modeLabel(m)
	local n = sizeOf(m)
	return if n and n > 0 then (n .. "v" .. n .. " " .. m.Name) else m.Name
end
local function modeById(id)
	id = MatchConfig.BaseOf and MatchConfig.BaseOf(id) or id -- "TDM_4" -> "TDM"
	for i, m in MODES do
		if m.Id == id then
			return m, i
		end
	end
	return MODES[1], 1
end
local function inLobby()
	return player.Team == nil and myStatus() ~= "Match" and player.Character ~= nil and not player:GetAttribute("InTutorial")
end

-- a design-space group pinned to a screen anchor and scaled as one (1920 x 1080 design)
local function cluster(name, ax, ay, dx, dy, w, h)
	local f = new("Frame", { Name = name, AnchorPoint = V2(ax, ay), Size = O(w, h), BackgroundTransparency = 1 }, hudRoot)
	new("UIScale", {}, f)
	local c = { f, ax, ay, dx, dy }
	table.insert(clusters, c)
	return f, c
end

local function fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	if vp.X < 50 then
		return
	end
	local scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.42, 1.6)
	HS.setScale(scale)
	local inset = GuiService.TopbarInset
	for _, c in clusters do
		local f, ax, ay, dx, dy = c[1], c[2], c[3], c[4], c[5]
		if f.Name == "TopLeft" then
			f.UIScale.Scale = 1
			c.Home = UDim2.fromOffset(inset.Min.X + 8, inset.Min.Y + math.max(0, (inset.Height - 44) / 2))
		else
			f.UIScale.Scale = scale
			local px, py = dx * scale, dy * scale
			c.Home = UDim2.new(ax, if ax == 1 then -px else px, ay, if ay == 1 then -py else py)
		end
		f.Position = c.Home
	end
	if modalLayer then
		modalLayer.UIScale.Scale = math.clamp(math.min(vp.X / 1720, vp.Y / 1000), 0.38, 1.4)
	end
end

local function slideAll()
	for _, c in clusters do
		local f = c[1]
		local off = ({ Left = O(-360, 0), Bottom = O(0, 300), TopRight = O(480, 0), Profile = O(440, 0), TopLeft = O(0, -80) })[f.Name]
		if off and c.Home then
			f.Position = c.Home + off
			tween(f, 0.55, { Position = c.Home }, Enum.EasingStyle.Back)
		end
	end
end

-- movement keys go nowhere while a modal / full screen is up
local FREEZE = "VantageLobbyFreeze"
local function freeze(on)
	if on then
		ContextActionService:BindActionAtPriority(FREEZE, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward, Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.LeftShift)
	else
		ContextActionService:UnbindAction(FREEZE)
	end
end

-- ─── modal / screen routing ───────────────────────────────────────────────────────────
local function closeModal(silent)
	local m = state.Modal
	if not m then
		return
	end
	state.Modal = nil
	if m.OnHide then
		pcall(m.OnHide)
	end
	G.closeModal(m.Root)
	tween(ui.Dim, 0.2, { BackgroundTransparency = 1 })
	freeze(false)
	if not silent then
		G.sound("Close")
	end
end

local function openModal(name)
	if state.Screen or flow.Stage == "Found" or flow.Stage == "Deploy" then
		return
	end
	local m = ui.Modals[name]
	if not m or state.Modal == m then
		return
	end
	closeModal(true)
	state.Modal = m
	if m.OnShow then
		pcall(m.OnShow, data)
	end
	G.openModal(m.Root)
	tween(ui.Dim, 0.25, { BackgroundTransparency = 0.45 })
	freeze(true)
end
Lobby.OpenModal = openModal

-- full-screen 3D screens (Operators, Shop) take over the camera; the HUD steps aside
local function hideScreen()
	local sc = state.Screen
	if not sc then
		return
	end
	state.Screen = nil
	pcall(function()
		sc:Hide()
	end)
	hudRoot.Visible = true
	freeze(false)
end
local function showScreen(sc)
	if not sc or flow.Stage == "Deploy" or flow.Stage == "Found" then
		return
	end
	closeModal(true)
	if state.Screen and state.Screen ~= sc then
		hideScreen()
	end
	state.Screen = sc
	hudRoot.Visible = false
	freeze(true)
	G.sound("Open")
	sc:Show()
end

local function openLoadout()
	closeModal(true)
	hideScreen()
	if ctx.Armory then
		ctx.Armory:SetOpen(true)
	end
end
local function openSettings()
	closeModal(true)
	if ctx.Settings and not ctx.Settings.Open then
		ctx.Settings:Toggle()
	end
end

local NAV = {
	Loadout = function()
		if ui.Loadout then
			showScreen(ui.Loadout)
		else
			openLoadout()
		end
	end,
	Operators = function() if ui.Equipment then showScreen(ui.Equipment) end end, -- armour screens retired; the Equipment screen plugs in as ui.Equipment
	Shop = function() showScreen(ui.Crates or ui.Shop) end,
	Inventory = function() openModal("Inventory") end,
	Challenges = function() openModal("Challenges") end,
	Trading = function() openModal("Trading") end,
	Battlepass = function() openModal("Battlepass") end,
	Mastery = function() openModal("Mastery") end,
	Farm = function() if ui.Farm then showScreen(ui.Farm) end end, -- 2026-11-19: Ichor Farm (FarmHS)
	Store = function()
		if ui.Modals and ui.Modals.Shop then
			openModal("Shop")
		elseif ui.Crates then
			showScreen(ui.Crates)
		else
			openModal("Store")
		end
	end,
	Crates = function() showScreen(ui.Crates) end,
	Profile = function(p)
		local po = ui.Modals and ui.Modals.Profile
		if po and po.Object then
			po.Object:SetTarget(if typeof(p) == "Instance" and p:IsA("Player") then p else player)
		end
		openModal("Profile")
	end,
	Modes = function() openModal("Modes") end,
	Settings = openSettings,
}
Lobby.Nav = NAV

-- ─── queue flow (MatchService) ────────────────────────────────────────────────────────
local renderDeploy -- forward

local function resetFlow()
	flow.Stage, flow.InMatch, flow.Note = nil, false, ""
	flow.Token += 1
	renderDeploy()
end

function Lobby.Deploy()
	if flow.Stage ~= nil then
		return
	end
	local m = selectedMode()
	if not m.Live then
		G.sound("Deny")
		return
	end
	G.sound("Play")
	closeModal(true)
	flow.Token += 1
	local tok = flow.Token
	flow.Stage, flow.Note, flow.QueueStart = "Queue", "", os.clock()
	renderDeploy()
	local ok, success, msg = pcall(function()
		return matchRequest:InvokeServer("Queue", queueId(m))
	end)
	if tok ~= flow.Token then
		return
	end
	if not (ok and success) then
		flow.Stage = "Error"
		flow.Note = "Couldn't queue: " .. string.lower(tostring(if ok then msg else success))
	end
	renderDeploy()
	Lobby._onFlow()
end

function Lobby.CancelQueue()
	if flow.Stage ~= "Queue" and flow.Stage ~= "Error" then
		return
	end
	local was = flow.Stage == "Queue"
	flow.Stage = "Leaving"
	renderDeploy()
	if was then
		pcall(function()
			matchRequest:InvokeServer("Cancel")
		end)
	end
	if myStatus() == "Match" then -- allocated a moment before the cancel landed: go in
		flow.Stage = "Queue"
		Lobby._onFlow()
		return
	end
	resetFlow()
end

-- physical DEPLOY pad in the Staging Deck (LobbyPresence): queue one specific mode, read the flow stage
function Lobby.DeployMode(id)
	if flow.Stage ~= nil then
		return
	end
	local _, i = modeById(id)
	state.Selected = i
	renderDeploy()
	Lobby.Deploy()
end
function Lobby.FlowStage()
	return flow.Stage
end

function Lobby.StartNow()
	if flow.Stage ~= "Queue" or not MatchConfig.AllowSkip then
		return
	end
	if phase() ~= "Idle" then
		G.sound("Deny")
		flow.Note = "A match is running. You're next in line!"
		return
	end
	local ok, success, msg = pcall(function()
		return matchRequest:InvokeServer("Skip")
	end)
	if not (ok and success) and flow.Stage == "Queue" then
		flow.Note = "Couldn't start: " .. string.lower(tostring(if ok then msg else success))
	end
end

local function rosters()
	local m = MF()
	local out = {}
	for _, team in { "Blue", "Red" } do
		local raw = m and m:GetAttribute(team .. "Roster")
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw or "[]")
		end)
		out[team] = ok and type(list) == "table" and list or {}
	end
	return out
end

local function showFound()
	flow.Stage, flow.InMatch = "Found", true
	flow.Token += 1
	closeModal(true)
	hideScreen()
	if ctx.Armory and ctx.Armory.Open then
		pcall(function() ctx.Armory:SetOpen(false) end)
	end
	local m = MF()
	local mode = modeById(m and m:GetAttribute("Mode"))
	local f = ui.Found
	local live = MatchConfig.Modes[m and m:GetAttribute("Mode") or ""]
	f.ModeName = if live then (live.TeamSize .. "v" .. live.TeamSize .. " " .. mode.Name) else mode.Name
	-- 2026-11-18: with a map vote the map is named once it is picked (renderVote)
	local voting = m and (m:GetAttribute("VoteMaps") or "") ~= ""
	f.Mode.Text = if voting then f.ModeName else (f.ModeName .. "  •  " .. tostring(m and m:GetAttribute("MapName") or MAP_NAME))
	f.Vote.Ids, f.Vote.Stage, f.Vote.Mine = "", nil, nil
	f.Vote.Root.Visible = false
	f.VS.Visible = true
	f.Title.Text = "MATCH FOUND!"
	for _, col in f.Cols do
		col.Card.Visible = true
	end
	local r = rosters()
	for team, col in f.Cols do
		for _, c in col.List:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, name in r[team] do
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = if name == player.Name then 0.2 else 0.6, LayoutOrder = i, ZIndex = 43 }, col.List)
			G.corner(row, 12)
			text(row, { Text = name, Position = O(16, 0), Size = UDim2.new(1, -24, 1, 0), X = Enum.TextXAlignment.Left, TextSize = 28, Color = if name == player.Name then C.Gold else C.White, Stroke = 2.2, ZIndex = 44 })
		end
	end
	local mine = player.Team and player.Team.Name
	f.You.Text = if mine then "You are on " .. mine .. " Team!" else ""
	f.You.TextColor3 = if mine == "Red" then C.TeamRed elseif mine == "Blue" then C.TeamBlue else C.White
	hudRoot.Visible = false
	f.Root.Visible = true
	f.Root.Pop.Scale = 0.6
	tween(f.Root.Pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ui.Dim, 0.4, { BackgroundTransparency = 0.35 })
	G.sound("Found")
	f.Title.Rotation = -6
	tween(f.Title, 0.8, { Rotation = 0 }, Enum.EasingStyle.Elastic)
end

local function runDeploy()
	flow.Stage, flow.InMatch = "Deploy", true
	tween(fader, 0.3, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
	ui.Found.Root.Visible = false
	ui.Dim.BackgroundTransparency = 1
	hudRoot.Visible = false
	closeModal(true)
	hideScreen()
	-- suit-up shot (third person, the player's avatar taking the armour); starts and ends on black
	local ok, err = pcall(SuitUp.Play, {
		Hide = function() gui.Enabled = false end,
		Show = function() gui.Enabled = true end,
	})
	if not ok then
		warn("[VANTAGE] SuitUp: " .. tostring(err))
	end
	gui.Enabled = true
	if myStatus() ~= "Match" then
		tween(fader, 0.4, { BackgroundTransparency = 1 })
		hudRoot.Visible = true
		resetFlow()
		return
	end
	ui.Wait.Visible = true
	task.spawn(function()
		pcall(function()
			matchRequest:InvokeServer("Ready")
		end)
	end)
	while phase() == "Deploy" and myStatus() == "Match" do
		task.wait()
	end
	if myStatus() ~= "Match" then
		ui.Wait.Visible = false
		tween(fader, 0.4, { BackgroundTransparency = 1 })
		hudRoot.Visible = true
		resetFlow()
		return
	end
	flow.Stage = "Handoff"
	player:SetAttribute("VantageMainMenu", "Play")
	task.delay(0.35, function()
		gui.Enabled = false
		fader.BackgroundTransparency = 1
		ui.Wait.Visible = false
		hudRoot.Visible = true
	end)
end

function Lobby._onFlow()
	local st, ph = myStatus(), phase()
	if st == "Match" then
		if flow.Stage == nil or flow.Stage == "Queue" or flow.Stage == "Error" or flow.Stage == "Leaving" then
			if ph == "Found" then
				task.spawn(showFound)
			elseif ph ~= "Idle" and ph ~= "Ended" then
				task.spawn(runDeploy)
			end
		elseif flow.Stage == "Found" and ph ~= "Found" and ph ~= "Idle" and ph ~= "Ended" then
			task.spawn(runDeploy)
		end
	elseif st == "Queued" then
		if flow.Stage == nil then -- queued from a JOIN pad in the hall
			flow.Stage, flow.QueueStart = "Queue", os.clock()
			local mode = player:GetAttribute("QueueMode")
			if mode then
				local _, i = modeById(mode)
				state.Selected = i
				local v = MatchConfig.Modes[mode]
				if v then state.Size[MODES[i].Id] = v.TeamSize end
			end
			renderDeploy()
		end
	else
		if flow.Stage == "Found" then -- cancelled before deployment
			ui.Found.Root.Visible = false
			tween(ui.Dim, 0.2, { BackgroundTransparency = 1 })
			hudRoot.Visible = true
			resetFlow()
		elseif flow.Stage == "Handoff" then
			resetFlow() -- match over: LobbyService puts us back in the hall
		elseif flow.Stage == "Queue" and os.clock() - flow.QueueStart > 3 then
			resetFlow() -- the server dropped us from the queue
		end
	end
end

-- ─── build (Hypershot reconstruction, measured; see Lobby.HS) ─────────────────────────
-- All coordinates are 1920x1080 design px taken from the reference capture (x 0.6531).
local function buildTopLeft()
	local f = cluster("TopLeft", 0, 0, 0, 0, 420, 44)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
	HS.topChip(f, { Name = "Settings", Icon = G.A.Icon.Settings, Order = 1, OnClick = openSettings })
	HS.topChip(f, { Name = "Trading", Icon = G.A.Icon.Trade, Order = 2, OnClick = function() NAV.Trading() end })
	ui.RewardsChip = HS.topChip(f, { Name = "Rewards", Icon = G.A.Icon.Gift, Label = "Rewards", Width = 134, Order = 3, OnClick = function() NAV.Challenges() end })
end

local function buildLeft()
	-- tiles: outer 86.9 at x 26.1 / 130.0, y 440.8 / 536.8 (pitch 103.9 x 96.0); NEW pill at 231.8, 465.0
	local f = cluster("Left", 0, 0.5, 24.1, 48.8, 400, 300)
	ui.Tiles = {}
	local tiles = {
		{ "Loadout", "blue", G.A.Icon.Rifle, 0, 0, 76 },
		{ "Shop", "red", HS.Img.Shop, 103.9, 0, 66 },
		{ "Crates", "purple", HS.CasesIcon or G.A.Icon.Case, 0, 96.0, 72 },
		{ "Inventory", "gold", G.A.Icon.Inventory, 103.9, 96.0, 72 },
		{ "Mastery", "blue", "rbxassetid://114502105680644", 0, 192.0, 84 }, -- weapon mastery (MasteryHS)
		{ "Farm", "gold", "rbxassetid://108288759204937", 103.9, 192.0, 70 }, -- 2026-11-19: Ichor Farm (FarmHS; IchorConfig.Icon)
	}
	local route = { Loadout = "Loadout", Shop = "Store", Crates = "Crates", Inventory = "Inventory", Mastery = "Mastery", Farm = "Farm" }
	for _, t in tiles do
		local b = HS.tile(f, t[2], { Name = t[1], Label = t[1], Icon = t[3], IconSize = t[6], Position = O(t[4], t[5]), OnClick = function()
			local fn = NAV[route[t[1]]]
			if fn then
				fn()
			end
		end })
		ui.Tiles[t[1]] = { Button = b }
	end
	ui.NewPill = HS.pill(f, { Name = "NewItems", Text = "Fresh Drops!", TextSize = 27, Position = O(207.7, 26.2), Size = O(159.4, 38.5), OnClick = function() NAV.Store() end })
end

local function buildTopRight()
	-- REQ bar: plus square at x 1636.0, y 66.6; leaderboard panel x 1555.7, y 284.7, w 327.9
	local f = cluster("TopRight", 1, 0, 0, 0, 364.3, 760)
	local _, val = HS.currency(f, { Name = "Req", Position = O(80.3, 66.6), Icon = ReqConfig.Icon or HS.Img.Req, OnPlus = function() NAV.Store() end })
	ui.ReqText = val
	-- 2026-11-17: Ordnance (ORD) pill under REQ; + opens the Shop (ORD packs) / Cases (Arsenal Crates)
	local ordF, ordVal = HS.currency(f, { Name = "Ord", Coin = "ORD", Position = O(80.3, 122), OnPlus = function()
		local fn = NAV.Crates or NAV.Store
		if fn then fn() end
	end })
	ui.OrdText = ordVal
	ui.OrdPill = ordF
	-- 2026-11-19: Ichor (Signature currency) pill under ORD; + opens the Shop (daily Signature)
	local ichorCfg
	pcall(function() ichorCfg = require(game:GetService("ReplicatedStorage").Vantage:WaitForChild("Ichor"):WaitForChild("IchorConfig")) end)
	local ichF, ichVal = HS.currency(f, { Name = "Ichor", Position = O(80.3, 177.4), Icon = ichorCfg and ichorCfg.Icon or nil, OnPlus = function()
		local fn = NAV.Store
		if fn then fn() end
	end })
	ichVal.TextColor3 = Color3.fromRGB(255, 236, 190)
	ui.IchorText = ichVal
	ui.IchorPill = ichF
	local function renderIchor() ichVal.Text = G.abbrev(player:GetAttribute("Ichor") or 0) end
	renderIchor()
	player:GetAttributeChangedSignal("Ichor"):Connect(renderIchor)
	local lb = new("Frame", { Name = "Board", BackgroundColor3 = Color3.fromRGB(14, 14, 16), BackgroundTransparency = 0.18, Position = O(0, 284.7), Size = O(327.9, 37.2), ClipsDescendants = true }, f)
	HS.corner(lb, 15.7)
	lb.AutomaticSize = Enum.AutomaticSize.Y
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, lb)
	local head = new("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 37.2), LayoutOrder = 0 }, lb)
	local hide = new("TextButton", { Name = "Hide", Text = "X", FontFace = HS.MontX, TextSize = 24, TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Position = O(9.8, 0), Size = O(30, 37.2), AutoButtonColor = false, ZIndex = 3 }, head)
	local hl = HS.text(head, { Text = "Ranked RP", Font = HS.MontXI, TextSize = 22, X = Enum.TextXAlignment.Right, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -7.8, 0, 0), Size = O(220, 37.2), ZIndex = 3 })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(176, 255, 112), Color3.fromRGB(110, 226, 72)) }, hl)
	ui.BoardRows = {}
	for i = 1, 11 do
		local row = new("Frame", { Name = "Row" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 37.0), LayoutOrder = i, Visible = false }, lb)
		new("Frame", { Name = "Line", BackgroundColor3 = Color3.fromRGB(78, 78, 82), BackgroundTransparency = 0.25, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2) }, row)
		local name = HS.text(row, { Name = "Name", Font = HS.Mont, TextSize = 20.5, X = Enum.TextXAlignment.Left, Position = O(11.8, 1), Size = UDim2.new(1, -120, 1, 0), ZIndex = 3 })
		local lvl = HS.text(row, { Name = "Value", Font = HS.MontX, TextSize = 20.5, X = Enum.TextXAlignment.Right, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -14.4, 0, 1), Size = O(110, 37), ZIndex = 3 })
		ui.BoardRows[i] = { Row = row, Name = name, Level = lvl }
		local hit = new("TextButton", { Name = "Hit", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(176, 110, 255), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, row)
		hit.MouseEnter:Connect(function() hit.BackgroundTransparency = 0.82 end)
		hit.MouseLeave:Connect(function() hit.BackgroundTransparency = 1 end)
		hit.Activated:Connect(function()
			local rec = ui.BoardRows[i]
			if rec and rec.P and rec.P.Parent then
				HS.sound("Click")
				NAV.Profile(rec.P)
			end
		end)
	end
	new("Frame", { Name = "Pad", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), LayoutOrder = 99 }, lb)
	ui.Board = lb
	hide.Activated:Connect(function()
		HS.sound("Click")
		ui.BoardFolded = not ui.BoardFolded
		hide.Text = if ui.BoardFolded then "+" else "X"
		for _, r in ui.BoardRows do
			r.Row.Parent = if ui.BoardFolded then nil else lb
		end
	end)
end

local function buildBottom()
	-- cluster 1000 x 300 anchored bottom-centre: design x - 460, y - 780
	local f = cluster("Bottom", 0.5, 1, 0, 0, 1000, 300)
	local bub = new("Frame", { Name = "Bubble", BackgroundColor3 = Color3.new(1, 1, 1), Position = O(208.8, 17.4), Size = O(581.9, 102.5), ZIndex = 5 }, f)
	HS.corner(bub, 20)
	HS.stroke(bub, 3.3, Color3.new(1, 1, 1))
	new("UIGradient", { Rotation = 35, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(0, 0, 0)), ColorSequenceKeypoint.new(0.46, Color3.fromRGB(12, 12, 12)), ColorSequenceKeypoint.new(0.62, Color3.fromRGB(12, 12, 12)), ColorSequenceKeypoint.new(0.63, Color3.fromRGB(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 4, 4)) }) }, bub)
	local tail = new("Frame", { Name = "Tail", BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = V2(0.5, 0), Position = O(499.7, 119.3), Size = O(62.7, 32), ZIndex = 5 }, f)
	new("Frame", { Name = "Diamond", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Rotation = 45, AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Size = O(44.3, 44.3), ZIndex = 5 }, tail)
	ui.Tail = tail
	ui.BubbleText = HS.text(bub, { Name = "Text", Text = "Deploy to start playing!", TextSize = 45, ZIndex = 6, Size = UDim2.fromScale(1, 1) })
	ui.BubbleSub = HS.text(bub, { Name = "Sub", Text = "", Font = HS.Mont, TextSize = 17, Color = Color3.fromRGB(170, 170, 178), AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -40, 0, 20), ZIndex = 6 })
	local modes, _, mcap = HS.bar(f, "orange", { Name = "Modes", Text = "PLAYLISTS", TextSize = 27, Caption = selectedMode().Name, CaptionSize = 25, CaptionTop = 77.9, Position = O(35.0, 170.7), OnClick = NAV.Modes })
	modes:SetAttribute("_", 0)
	ui.ModesBtn = { Button = modes, Caption = mcap }
	local dep, dlab, dcap = HS.bar(f, "green", { Name = "Deploy", Text = "DEPLOY", TextSize = 37.3, Caption = "Press F", CaptionSize = 28.5, CaptionTop = 91.7, Position = O(321.8, 157.6), ZIndex = 6, Sound = false, OnClick = function()
		if flow.Stage == "Queue" or flow.Stage == "Error" then
			Lobby.CancelQueue()
		else
			Lobby.Deploy()
		end
	end })
	ui.DeployBtn = { Button = dep, Label = dlab, Caption = dcap }
	local pass, _, pcap = HS.bar(f, "purple", { Name = "Battlepass", Text = "SEASON PASS", TextSize = 30.8, Caption = "Season 1 Rewards!", CaptionSize = 25, CaptionTop = 77.9, Position = O(668.6, 170.7), OnClick = NAV.Battlepass })
	ui.PassBtn = { Button = pass, Caption = pcap }
	ui.StartNow = G.cta(f, "small", { Name = "StartNow", Text = "START NOW", Width = 200, Height = 70, TextSize = 28, AnchorPoint = V2(0, 0.5), Position = O(810, 68), OnClick = Lobby.StartNow })
	ui.StartNow.Visible = false
	-- 2026-11-20: TEAM SIZE picker (1v1 .. 6v6) above the bubble; map size follows (small / medium / full)
	local row = new("Frame", { Name = "TeamSize", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 1), Position = O(499.7, 8), Size = O(560, 40), ZIndex = 6 }, f)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	ui.SizePills = {}
	for n = 1, 6 do
		local b = new("TextButton", { Name = "S" .. n, LayoutOrder = n, AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.fromRGB(10, 10, 12), Size = O(80, 36), ZIndex = 6 }, row)
		HS.corner(b, 10)
		local st = HS.stroke(b, 2.5, Color3.new(1, 1, 1))
		local lbl = HS.text(b, { Name = "L", Text = n .. "v" .. n, TextSize = 22, ZIndex = 7, Size = UDim2.fromScale(1, 1) })
		b.Activated:Connect(function()
			local m = selectedMode()
			if flow.Stage ~= nil or not (m.Sizes and table.find(m.Sizes, n)) then
				G.sound("Deny")
				return
			end
			HS.sound("Click")
			state.Size[m.Id] = n
			renderDeploy()
		end)
		ui.SizePills[n] = { Button = b, Stroke = st, Label = lbl }
	end
	ui.SizeNote = HS.text(row, { Name = "Note", Text = "", TextSize = 20, Stroke = 2.5, Color = Color3.fromRGB(150, 230, 255), Size = O(150, 36), ZIndex = 7 })
	ui.SizeNote.LayoutOrder = 7
end

local function buildProfile()
	-- "View Profile!" centred at (1743.8, 803.6); card 290 x 222.7 at (1596.8, 826.8)
	local f = cluster("Profile", 1, 1, 0, 0, 323.2, 290)
	HS.text(f, { Name = "Title", Text = "My Profile", TextSize = 25, Stroke = 2.4, StrokeColor = Color3.new(0, 0, 0), AnchorPoint = V2(0.5, 0.5), Position = O(147.0, 13.6), Size = O(290, 34) })
	local card = new("ImageButton", { Name = "Card", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(16, 16, 16), Image = "rbxassetid://118119181361296", ScaleType = Enum.ScaleType.Crop, Position = O(0, 36.8), Size = O(290, 222.7), ZIndex = 3 }, f)
	HS.corner(card, 14.4)
	HS.stroke(card, 4, Color3.new(0, 0, 0))
	HS.sheen(card, UDim.new(0, 14.4), 4, 0.45)
	local strip = new("Frame", { Name = "Strip", BackgroundColor3 = Color3.fromRGB(16, 16, 16), BorderSizePixel = 0, AnchorPoint = V2(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 28.7), ZIndex = 4 }, card)
	HS.corner(strip, 12)
	new("Frame", { Name = "Square", BackgroundColor3 = Color3.fromRGB(16, 16, 16), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 12), ZIndex = 4 }, strip)
	HS.text(strip, { Name = "Name", Text = player.DisplayName, TextSize = 25, Stroke = 3, StrokeColor = Color3.new(0, 0, 0), ZIndex = 5 })
	ui.Shield = new("ImageLabel", { Name = "Badge", BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, Position = O(9.8, 17), Size = O(40.5, 40.5), ZIndex = 5 }, card)
	ui.LevelText = HS.text(card, { Name = "Level", Text = "LEVEL 1", TextSize = 21, Stroke = 3, StrokeColor = Color3.new(0, 0, 0), X = Enum.TextXAlignment.Right, AnchorPoint = V2(1, 0), Position = UDim2.new(1, -10.4, 0, 18), Size = O(160, 26), ZIndex = 5 })
	ui.ProfileCard = card
	HS.press(card, function() NAV.Profile(player) end, { Hover = 1.03, Press = 0.97 })
end

local function buildFound()
	local root = new("Frame", { Name = "Found", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1180, 660), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, modalLayer)
	new("UIScale", { Name = "Pop" }, root)
	G.glow(root, { Color = C.Cyan, Transparency = 0.55, Position = UDim2.new(0.5, 0, 0, 70), Size = O(900, 260), ZIndex = 39 })
	local title = text(root, { Name = "Title", Text = "MATCH FOUND!", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(1100, 130), TextSize = 120, Stroke = 7, Gradient = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("c8fdff")), ColorSequenceKeypoint.new(0.5, C.White), ColorSequenceKeypoint.new(1, Color3.fromHex("dcc8ff")) }), ZIndex = 45 })
	local mode = text(root, { Name = "Mode", Text = "", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 128), Size = O(1100, 50), TextSize = 40, Stroke = 3.4, ZIndex = 45 })
	local cols = {}
	for i, team in { "Blue", "Red" } do
		local card = G.artCard(root, { Name = team, Color = if team == "Blue" then "blue" else "hot", Position = O(if i == 1 then 30 else 630, 196), Size = O(520, 360), ZIndex = 41 })
		G.glow(card, { Color = if team == "Blue" then C.TeamBlue else C.TeamRed, Transparency = 0.6, Size = UDim2.new(1, 120, 1, 120), ZIndex = 40 })
		text(card, { Text = team .. " Team", Position = O(0, 14), Size = UDim2.new(1, 0, 0, 56), TextSize = 46, Stroke = 3.6, ZIndex = 46 })
		local list = new("ScrollingFrame", { Name = "List", Position = O(26, 80), Size = UDim2.new(1, -52, 1, -104), BackgroundTransparency = 1, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = O(0, 0), BorderSizePixel = 0, ZIndex = 46 }, card)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		cols[team] = { Card = card, List = list }
	end
	local vs = text(root, { Name = "VS", Text = "VS", AnchorPoint = V2(0.5, 0.5), Position = O(590, 376), Size = O(120, 90), TextSize = 84, Stroke = 6, ZIndex = 47 })
	local you = text(root, { Name = "You", Text = "", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 568), Size = O(900, 46), TextSize = 40, Stroke = 3.4, ZIndex = 45 })
	local count = text(root, { Name = "Count", Text = "", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 614), Size = O(900, 40), TextSize = 32, Stroke = 2.6, ZIndex = 45 })
	-- 2026-11-18 map vote: takes the team cards' place once MapVote.Intro has passed
	local voteRoot = new("Frame", { Name = "Vote", Position = O(0, 196), Size = O(1180, 360), BackgroundTransparency = 1, Visible = false, ZIndex = 41 }, root)
	new("UIScale", { Name = "Pop" }, voteRoot)
	ui.Found = { Root = root, Title = title, Mode = mode, Cols = cols, You = you, Count = count, VS = vs, ModeName = "", Vote = { Root = voteRoot, Cards = {}, List = {}, Ids = "", Stage = nil, Mine = nil } }
end

-- ─── map vote (2026-11-18) ─────────────────────────────────────────────────────────────────────────
-- Server: MatchService (Match attributes VoteMaps / VoteStart / VoteEnds / VoteCounts / VoteWinner),
-- MapService loads the winner. Cards: preview (MatchConfig.Maps[].Preview, 1024 x 576, slow pan),
-- name, theme, live vote bar. Click / tap a card or press 1-3 (gamepad: d-pad left / right + A).
local MAP_CARD_W, MAP_CARD_H, MAP_CARD_GAP = 360, 340, 30
local CUR_CARD_W = MAP_CARD_W -- width of the cards on screen (4 maps -> narrower cards)
local PREVIEW_PX = Vector2.new(1024, 576)
local MAP_TINT = { LIVEFIRE = Color3.fromHex("ff7a45"), FOUNDRY = Color3.fromHex("e2a04a"), PORTO = Color3.fromHex("2bb3e0"), MERIDIAN = Color3.fromHex("e646be") }

local function voteState()
	local m = MF()
	if not m or phase() ~= "Found" or (m:GetAttribute("VoteMaps") or "") == "" then
		return nil
	end
	local t = Workspace:GetServerTimeNow()
	if (m:GetAttribute("VoteWinner") or "") ~= "" then
		return "Reveal"
	end
	return if t >= (m:GetAttribute("VoteStart") or 0) then "Vote" else "Teams"
end

local function castVote(id)
	if voteState() ~= "Vote" or not id then
		G.sound("Deny")
		return
	end
	local v = ui.Found.Vote
	if v.Mine == id then
		return
	end
	v.Mine = id
	G.sound("Click")
	task.spawn(function()
		local ok, res = pcall(function()
			return matchRequest:InvokeServer("Vote", id)
		end)
		if not ok or res ~= true then
			if v.Mine == id then
				v.Mine = nil
			end
		end
	end)
end

local function buildVoteCards(ids)
	local v = ui.Found.Vote
	for _, c in v.Cards do
		c.Root:Destroy()
	end
	v.Cards, v.List = {}, ids
	local n = #ids
	local W, H = MAP_CARD_W, MAP_CARD_H
	local gap = MAP_CARD_GAP
	if n >= 4 then W, gap = math.floor((1180 - (n - 1) * 20) / n), 20 end -- 4 maps: all cards fit the 1180 row
	CUR_CARD_W = W
	local x0 = (1180 - (n * W + (n - 1) * gap)) / 2
	local keys = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
	for i, id in ids do
		local def = MatchConfig.MapById(id) or { Name = id, Theme = "", Size = "", Preview = 0 }
		local tint = MAP_TINT[id] or C.Violet
		local btn = new("ImageButton", { Name = id, AutoButtonColor = false, Image = "", AnchorPoint = V2(0.5, 0.5), Position = O(x0 + (i - 1) * (W + gap) + W / 2, H / 2 + 8), Size = O(W, H), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.04, ZIndex = 42 }, v.Root)
		G.corner(btn, 20)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Panel2, C.Panel) }, btn)
		local stroke = new("UIStroke", { Thickness = 3, Color = C.Panel3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
		-- full-card map background: the uploaded preview image if there is one, otherwise a live
		-- 3D render of the map (Vantage.MapPreviews.<id>, a trimmed copy built for this camera)
		local pid = tonumber(def.Preview) or 0
		local img, view, cam, pm = nil, nil, nil, nil
		local previews = Vantage:FindFirstChild("MapPreviews")
		local src = previews and previews:FindFirstChild(id)
		if pid > 0 then
			img = new("ImageLabel", { Name = "Preview", Size = S(1, 1), BackgroundTransparency = 1, Image = "rbxassetid://" .. pid, ScaleType = Enum.ScaleType.Stretch, ImageRectSize = PREVIEW_PX, ZIndex = 42 }, btn)
			G.corner(img, 20)
		elseif src then
			local sky = new("Frame", { Name = "Sky", Size = S(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 42 }, btn)
			G.corner(sky, 20)
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(src:GetAttribute("SkyTop") or C.Blue, src:GetAttribute("SkyBottom") or C.Lilac) }, sky)
			view = new("ViewportFrame", { Name = "Preview", Size = S(1, 1), BackgroundTransparency = 1, Ambient = src:GetAttribute("Ambient") or Color3.fromRGB(150, 150, 150), LightColor = src:GetAttribute("LightColor") or Color3.new(1, 1, 1), LightDirection = src:GetAttribute("LightDir") or Vector3.new(-0.4, -1, -0.3), ZIndex = 43 }, btn)
			G.corner(view, 20)
			cam = Instance.new("Camera")
			cam.FieldOfView = src:GetAttribute("Fov") or 58
			cam.Parent = view
			view.CurrentCamera = cam
			pm = { Pos = src:GetAttribute("CamPos") or Vector3.new(0, 150, -300), Look = src:GetAttribute("CamLook") or Vector3.zero }
			cam.CFrame = CFrame.lookAt(pm.Pos, pm.Look)
			src:Clone().Parent = view
		else
			img = new("Frame", { Name = "Preview", Size = S(1, 1), BackgroundColor3 = tint, ZIndex = 42 }, btn)
			G.corner(img, 20)
			new("UIGradient", { Rotation = 35, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.25, 0.22, 0.4)) }, img)
		end
		-- dark fade over the lower half so the name, theme and vote bar read on any map
		local shade = new("Frame", { Position = O(0, 120), Size = UDim2.new(1, 0, 1, -120), BackgroundColor3 = Color3.fromHex("05060d"), BackgroundTransparency = 0, ZIndex = 44 }, btn)
		G.corner(shade, 20)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 0.25), NumberSequenceKeypoint.new(1, 0.08) }) }, shade)
		if keys then
			local key = new("Frame", { Position = O(20, 20), Size = O(40, 40), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.2, ZIndex = 46 }, btn)
			G.corner(key, 10)
			new("UIStroke", { Thickness = 2, Color = C.White, Transparency = 0.4 }, key)
			text(key, { Text = tostring(i), TextSize = 28, Stroke = 0, ZIndex = 47 })
		end
		local chip = new("Frame", { Name = "Chip", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -20, 0, 20), Size = O(150, 38), BackgroundColor3 = C.Cyan, Visible = false, ZIndex = 46 }, btn)
		G.corner(chip, 19)
		local chipText = text(chip, { Text = "YOUR VOTE", TextSize = 22, Color = C.Ink, Stroke = 0, ZIndex = 47 })
		-- name + theme
		text(btn, { Text = def.Name, Position = O(16, 206), Size = O(W - 32, 46), X = Enum.TextXAlignment.Left, TextSize = if n >= 4 then 32 else 40, Stroke = 3.4, ZIndex = 45 })
		local sub = {}
		if def.Theme and def.Theme ~= "" then table.insert(sub, def.Theme) end
		if def.Size and def.Size ~= "" then table.insert(sub, def.Size) end
		text(btn, { Text = table.concat(sub, "  •  "), Position = O(18, 250), Size = O(W - 36, 26), X = Enum.TextXAlignment.Left, TextSize = if n >= 4 then 18 else 21, Font = F.Bold, Color = C.Muted, Stroke = 0, ZIndex = 45 })
		-- live vote bar
		local bar = new("Frame", { Position = O(14, 288), Size = O(W - 28, 38), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.25, ZIndex = 44 }, btn)
		G.corner(bar, 12)
		local fill = new("Frame", { Size = S(0, 1), BackgroundColor3 = tint, ZIndex = 45 }, bar)
		G.corner(fill, 12)
		new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.75, 0.75, 0.75)) }, fill)
		local votesText = text(bar, { Text = "0 VOTES", TextSize = 24, Stroke = 2.4, ZIndex = 46 })
		local dim = new("Frame", { Size = S(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 49 }, btn)
		G.corner(dim, 20)
		HS.press(btn, function()
			castVote(id)
		end, { Hover = 1.04, Press = 0.96 })
		v.Cards[id] = { Root = btn, Stroke = stroke, Img = img, HasImg = pid > 0, Cam = cam, PM = pm, Chip = chip, ChipText = chipText, Fill = fill, Votes = votesText, Dim = dim, Index = i, Share = -1 }
	end
end

local function enterVoteStage(stage, winner)
	local f = ui.Found
	local v = f.Vote
	if stage == "Teams" then
		v.Root.Visible = false
		f.VS.Visible = true
		for _, col in f.Cols do
			col.Card.Visible = true
		end
		return
	end
	for _, col in f.Cols do
		col.Card.Visible = false
	end
	f.VS.Visible = false
	if stage == "Vote" then
		v.Root.Visible = true
		v.Root.Pop.Scale = 0.85
		tween(v.Root.Pop, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		f.Title.Text = "VOTE FOR A MAP!"
		G.sound("Open")
	elseif stage == "Reveal" then
		v.Root.Visible = true
		v.Root.Pop.Scale = 1
		local def = MatchConfig.MapById(winner)
		f.Title.Text = "MAP SELECTED!"
		f.Mode.Text = f.ModeName .. "  •  " .. (def and def.Name or tostring(winner))
		for id, c in v.Cards do
			if id == winner then
				tween(c.Root, 0.5, { Size = O(CUR_CARD_W * 1.08, MAP_CARD_H * 1.08) }, Enum.EasingStyle.Back)
				c.Root.ZIndex = 48
			else
				tween(c.Dim, 0.35, { BackgroundTransparency = 0.5 })
				tween(c.Root, 0.35, { Size = O(CUR_CARD_W * 0.94, MAP_CARD_H * 0.94) })
			end
		end
		G.sound("Found")
	end
	f.Title.Rotation = -5
	tween(f.Title, 0.7, { Rotation = 0 }, Enum.EasingStyle.Elastic)
end

-- per frame while the Found card is up; returns false when there is no vote this match
local function renderVote(t)
	local f = ui.Found
	local v = f.Vote
	local stage = voteState()
	if not stage then
		return false
	end
	local m = MF()
	local raw = m:GetAttribute("VoteMaps") or ""
	if raw ~= v.Ids then
		local ok, ids = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		buildVoteCards(ok and type(ids) == "table" and ids or {})
		v.Ids, v.Stage, v.Mine = raw, nil, nil
	end
	local winner = m:GetAttribute("VoteWinner") or ""
	if stage ~= v.Stage then
		v.Stage = stage
		enterVoteStage(stage, winner)
	end
	-- counts
	local okC, counts = pcall(function()
		return HttpService:JSONDecode(m:GetAttribute("VoteCounts") or "{}")
	end)
	counts = okC and type(counts) == "table" and counts or {}
	local total = 0
	for _, n in counts do
		total += tonumber(n) or 0
	end
	for id, c in v.Cards do
		local n = tonumber(counts[id]) or 0
		local share = if total > 0 then n / total else 0
		if share ~= c.Share then
			c.Share = share
			tween(c.Fill, 0.25, { Size = S(share, 1) })
		end
		c.Fill.Visible = share > 0
		c.Votes.Text = n .. (if n == 1 then " VOTE" else " VOTES")
		local isWin, isMine = winner == id, v.Mine == id
		c.Stroke.Color = if isWin then C.Gold elseif isMine then C.Cyan else C.Panel3
		c.Stroke.Thickness = if isWin or isMine then 5 else 3
		c.Chip.Visible = isWin or (isMine and stage == "Vote")
		c.Chip.BackgroundColor3 = if isWin then C.Gold else C.Cyan
		c.ChipText.Text = if isWin then "WINNER" else "YOUR VOTE"
		-- slow pan across the preview (Ken Burns), offset per card
		if c.HasImg then
			local k = 0.86 + 0.06 * math.sin(t * 0.35 + c.Index)
			local sz = PREVIEW_PX * k
			local span = PREVIEW_PX - sz
			local u = 0.5 + 0.5 * math.sin(t * 0.22 + c.Index * 1.7)
			c.Img.ImageRectSize = sz
			c.Img.ImageRectOffset = Vector2.new(span.X * u, span.Y * 0.5)
		elseif c.Cam then
			-- live 3D preview: a slow orbit + breathing push-in around the map's look point
			local off = c.PM.Pos - c.PM.Look
			local a = 0.14 * math.sin(t * 0.25 + c.Index * 1.3)
			local k = 1 - 0.05 * math.sin(t * 0.2 + c.Index)
			c.Cam.CFrame = CFrame.lookAt(c.PM.Look + (CFrame.Angles(0, a, 0) * off) * k, c.PM.Look)
		end
	end
	-- countdown line
	local nowS = Workspace:GetServerTimeNow()
	if stage == "Teams" then
		f.Count.Text = string.format("Map vote in %d", math.max(1, math.ceil((m:GetAttribute("VoteStart") or nowS) - nowS)))
	elseif stage == "Vote" then
		f.Count.Text = string.format("Voting ends in %d", math.max(0, math.ceil((m:GetAttribute("VoteEnds") or nowS) - nowS)))
	else
		local def = MatchConfig.MapById(winner)
		f.Count.Text = string.format("Deploying to %s in %d", def and def.Name or "the map", math.max(0, math.ceil(phaseLeft())))
	end
	return true
end

local function buildWait()
	local w = new("Frame", { Name = "Wait", Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 61 }, gui)
	text(w, { Text = "Dropping in…", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.47), Size = O(900, 90), TextSize = 72, Stroke = 5, ZIndex = 62 })
	text(w, { Text = "Waiting for your squad", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.55), Size = O(900, 40), TextSize = 30, Font = F.Bold, Color = C.Muted, Stroke = 2, ZIndex = 62 })
	ui.Wait = w
end

-- ─── render ────────────────────────────────────────────────────────────────────────────
function renderDeploy()
	if not ui.DeployBtn then
		return
	end
	local queued = flow.Stage == "Queue" or flow.Stage == "Error" or flow.Stage == "Leaving"
	HS.setBar(ui.DeployBtn.Button, if queued then "red" else "green")
	ui.DeployBtn.Label.Text = if queued then "CANCEL" else "DEPLOY"
	local sm = selectedMode()
	ui.ModesBtn.Caption.Text = modeLabel(sm)
	HS.setDisabled(ui.ModesBtn.Button, queued)
	if ui.SizePills then
		local cur = sizeOf(sm)
		for n, pill in ui.SizePills do
			local ok = sm.Sizes ~= nil and table.find(sm.Sizes, n) ~= nil
			local on = ok and n == cur
			pill.Button.BackgroundColor3 = if on then Color3.fromRGB(60, 200, 90) else Color3.fromRGB(10, 10, 12)
			pill.Button.BackgroundTransparency = if ok then 0 else 0.5
			pill.Label.TextTransparency = if ok then 0 else 0.6
			pill.Stroke.Transparency = if ok then 0 else 0.7
		end
		local cls = MatchConfig.SizeClass and MatchConfig.SizeClasses and MatchConfig.SizeClasses[MatchConfig.SizeClass(cur or 6)]
		ui.SizeNote.Text = if cls then (cls.Name .. " MAP") else ""
	end
end

local function renderStep()
	local t = os.clock()
	local m = selectedMode()
	if flow.Stage == "Queue" or flow.Stage == "Leaving" then
		local mf = MF()
		local qid = queueId(m)
		local need = MatchConfig.Needed(qid)
		local have = mf and mf:GetAttribute("Queue_" .. qid) or 0
		local el = math.floor(t - flow.QueueStart)
		local running = phase() ~= "Idle"
		ui.BubbleText.Text = if running then "Match in progress. You're next!" else ("Searching" .. string.rep(".", math.floor(t * 2.5) % 4))
		ui.BubbleSub.Text = if flow.Note ~= "" then flow.Note else string.format("%s  •  %d/%d players  •  %d:%02d", modeLabel(m), have, need, el // 60, el % 60)
		ui.BubbleText.Position = UDim2.fromOffset(0, -9)
		ui.DeployBtn.Caption.Text = "Press F to cancel"
		ui.StartNow.Visible = MatchConfig.AllowSkip == true and not running and flow.Stage == "Queue"
	elseif flow.Stage == "Error" then
		ui.BubbleText.Text = "Queue unavailable"
		ui.BubbleSub.Text = flow.Note
		ui.BubbleText.Position = UDim2.fromOffset(0, -9)
		ui.StartNow.Visible = false
	else
		ui.BubbleText.Text = "Deploy to start playing!"
		ui.BubbleSub.Text = ""
		ui.BubbleText.Position = UDim2.fromOffset(0, 0)
		ui.DeployBtn.Caption.Text = "Press F"
		ui.StartNow.Visible = false
	end
	if ui.Found.Root.Visible and not renderVote(t) then
		local left = phaseLeft()
		ui.Found.Count.Text = if phase() == "Found" and left > 0 then string.format("Deploying in %d", math.ceil(left)) else "Deploying"
	end
end

local RankedCfg
do
	local okRC, mRC = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Vantage"):WaitForChild("Ranked"):WaitForChild("RankedConfig"))
	end)
	RankedCfg = okRC and mRC or nil
end

local function renderData()
	if not CoinBurst.Owns("REQ") then ui.ReqText.Text = G.abbrev(player:GetAttribute("REQ") or 0) end
	if ui.OrdText and not CoinBurst.Owns("ORD") then ui.OrdText.Text = G.abbrev(player:GetAttribute("ORD") or 0) end
	local level = player:GetAttribute("Level") or (data and data.Level) or 1
	local img = G.RankFor(level)
	ui.LevelText.Text = "LEVEL " .. tostring(level)
	ui.Shield.Image = img
	if RankedCfg then -- 2026-11-17: rank badge + chosen banner (ProfileService)
		local rr = RankedCfg.RankOf(player:GetAttribute("RP") or 0, player:GetAttribute("RankLegend") == true)
		ui.Shield.Image = rr.Rank.Badge
		ui.Shield.ImageColor3 = rr.Rank.Tint or Color3.new(1, 1, 1)
		local bn = RankedCfg.BannerById[player:GetAttribute("Banner") or RankedCfg.DefaultBanner]
		if bn and ui.ProfileCard then ui.ProfileCard.Image = bn.Image end
	end
	local open = 0
	if data and data.Daily then
		for _, d in data.Daily do
			if not d.Done then
				open += 1
			end
		end
	end
	if ui.RewardsChip then
		HS.badge(ui.RewardsChip, if open > 0 then open else nil)
	end
	for _, m in ui.Modals do
		if m.Root.Visible and m.OnData then
			pcall(m.OnData, data)
		end
	end
end

local function renderBoard()
	local list = {}
	for _, p in Players:GetPlayers() do
		table.insert(list, { p = p, rp = p:GetAttribute("RP"), l = p:GetAttribute("Level") or 1 })
	end
	table.sort(list, function(a, b)
		local ka, kb = a.rp or -1, b.rp or -1
		if ka ~= kb then
			return ka > kb
		end
		if a.l ~= b.l then
			return a.l > b.l
		end
		return a.p.Name < b.p.Name
	end)
	for i, r in ui.BoardRows do
		local e = list[i]
		r.Row.Visible = e ~= nil
		if e then
			r.P = e.p
			r.Name.Text = e.p.DisplayName
			r.Level.Text = if e.rp then (G.abbrev(e.rp) .. " RP") else ("Lv. " .. e.l)
		end
	end
end

local function fetch()
	task.spawn(function()
		local rf = Remotes:WaitForChild("ProgressionGet", 10)
		if not rf then
			return
		end
		local ok, snap = pcall(function()
			return rf:InvokeServer()
		end)
		if ok and type(snap) == "table" then
			data = snap
			renderData()
		end
	end)
end
Lobby.Refresh = fetch

-- ─── visibility: the HUD shows whenever we're in the lobby ─────────────────────────────
local function syncVisible()
	if flow.Stage == "Deploy" or flow.Stage == "Handoff" then
		return
	end
	local lobby = inLobby() or flow.Stage == "Found"
	if gui.Enabled ~= lobby then
		gui.Enabled = lobby
		if lobby then
			player:SetAttribute("VantageMainMenu", "Open")
			fetch()
			renderBoard()
			slideAll()
		end
	end
	if lobby then
		if ctx.Hud and ctx.Hud.Gui and ctx.Hud.Gui.Enabled then
			ctx.Hud.Gui.Enabled = false
		end
		if not state.Screen and not (ctx.Armory and ctx.Armory.Open) then
			UserInputService.MouseIconEnabled = true
		end
	end
end

function Lobby.IsOpen()
	return gui ~= nil and gui.Enabled
end

-- ─── start ─────────────────────────────────────────────────────────────────────────────
function Lobby.Start(context)
	ctx = context
	G.SoundGroup = ctx.Effects and ctx.Effects.EffectsGroup
	HS.SoundGroup = G.SoundGroup
	player:SetAttribute("VantageMainMenu", "Open")
	gui = new("ScreenGui", { Name = "VantageMainMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	hudRoot = new("Frame", { Name = "Hud", Size = S(1, 1), BackgroundTransparency = 1 }, gui)
	ui.Dim = new("Frame", { Name = "Dim", Size = S(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 15 }, gui)
	modalLayer = new("Frame", { Name = "Modals", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, ZIndex = 20 }, gui)
	new("UIScale", {}, modalLayer)
	fader = new("Frame", { Name = "Fader", Size = S(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 60 }, gui)

	buildTopLeft()
	buildLeft()
	buildTopRight()
	CoinBurst.Init({
		Bars = { REQ = ui.ReqText.Parent.Parent, ORD = ui.OrdPill },
		Abbrev = G.abbrev,
		Font = HS.MontX,
		HS = HS,
		IsOpen = function()
			return Lobby.IsOpen()
		end,
	})
	buildBottom()
	buildProfile()
	buildFound()
	buildWait()
	ui.Modals = Pages.Build(modalLayer, {
		G = G, Modes = MODES, State = state, Nav = NAV,
		Close = function() closeModal() end,
		Data = function() return data end,
		SelectMode = function(i, andPlay)
			state.Selected = i
			renderDeploy()
			closeModal(true)
			if andPlay then
				Lobby.Deploy()
			end
		end,
	})
	renderDeploy()

	-- full-screen armour + shop screens (earlier builds, hosted here until their gloss pass)
	local function back()
		G.sound("Close")
		hideScreen()
	end
	local function snd(n)
		G.sound(if n == "Hover" then "Hover" else "Click")
	end
	local okS, shop = false, "replaced by the crate store (CratesScreen)"
	local _oldShop = false and ShopScreen and pcall(ShopScreen.new, {
		Tabs = { "LOBBY", "SHOP" }, OnTab = back, Sound = snd,
		IsActive = function() return state.Screen ~= nil and state.Screen == ui.Shop end,
	})
	if okS then
		ui.Shop = shop
		pcall(LobbySkin.apply, shop.Gui, { Title = "SHOP", OnBack = back })
	else
		-- old effects shop retired (module kept in Lobby.ShopScreen + ServerStorage._CratesBackup_20261116)
	end
	-- gloss Loadout + Operators (3D showcase stage); the old Armory / Customise stay as fallbacks
	local function tabTo(n)
		if n == "Operators" then
			NAV.Operators()
		elseif n == "Loadout" then
			NAV.Loadout()
		end
	end
	local function toStore()
		back()
		NAV.Store()
	end
	local okL, lo = pcall(LoadoutScreen.new, {
		G = G, OnBack = back, OnTab = tabTo, OnStore = toStore,
		IsActive = function() return state.Screen ~= nil and state.Screen == ui.Loadout end,
	})
	if okL then
		ui.Loadout = lo
	else
		warn("[VANTAGE] Loadout screen: " .. tostring(lo))
	end
	do -- Hypershot-style Loadout (presets: 3 guns + knife, used on deploy); the old screen stays as a fallback
		local okH, LH = pcall(require, script:WaitForChild("LoadoutHS"))
		if okH then
			local okN, lh = pcall(LH.new, {
				OnBack = back,
				IsActive = function() return state.Screen ~= nil and state.Screen == ui.Loadout end,
			})
			if okN then ui.Loadout = lh else warn("[VANTAGE] LoadoutHS: " .. tostring(lh)) end
		else
			warn("[VANTAGE] LoadoutHS: " .. tostring(LH))
		end
	end

	-- Store › Crates: supply crates for REQ (server roll in CrateService) + the unboxing sequence
	local okX, crates = pcall(function()
		local opening = CrateOpening.new({ G = G })
		ui.Opening = opening
		return CratesScreen.new({
			G = G, OnBack = back, OnTab = tabTo, Opening = opening, OnStore = function() end,
			IsActive = function() return state.Screen ~= nil and state.Screen == ui.Crates end,
		})
	end)
	if okX then
		ui.Crates = crates
	else
		warn("[VANTAGE] Crates screen: " .. tostring(crates))
	end

	-- Hypershot Cases modal (BUY / OPEN); opening uses the CrateOpening sequence for now
	do
		local okU, U = pcall(require, script:WaitForChild("UnboxHS"))
		if okU then
			local okN, ub = pcall(U.new, { HS = HS })
			if okN then ui.Unbox = ub else warn("UnboxHS", ub) end
		else
			warn("UnboxHS", U)
		end
	end
	local okC2, casesModal = pcall(CasesHS.Mount, modalLayer, {
		HS = HS,
		Opening = ui.Unbox or ui.Opening,
		Close = function(silent) closeModal(silent) end,
		Reopen = function(name) openModal(name) end,
		Hud = function(on) hudRoot.Visible = on end,
	})
	if okC2 then
		ui.Modals.Cases = casesModal
	do -- Hypershot-style Shop modal (Robux: crates, deals, gamepasses, REQ packs)
		local okS, ShopHS = pcall(require, script:WaitForChild("ShopHS"))
		if okS then
			local okM, shopModal = pcall(ShopHS.Mount, modalLayer, {
				HS = HS,
				Close = function(silent) closeModal(silent) end,
				Open = function(name) openModal(name) end,
			})
			if okM then ui.Modals.Shop = shopModal else warn("[VANTAGE] Shop modal: " .. tostring(shopModal)) end
		else
			warn("[VANTAGE] ShopHS: " .. tostring(ShopHS))
		end
	end
	do -- Hypershot-style Inventory modal (owned skins, rarity cards, 3D detail, EQUIP)
		local okI, InvHS = pcall(require, script:WaitForChild("InventoryHS"))
		if okI then
			local okM, invModal = pcall(InvHS.Mount, modalLayer, {
				HS = HS,
				Close = function(silent) closeModal(silent) end,
				Open = function(name) openModal(name) end,
			})
			if okM then ui.Modals.Inventory = invModal else warn("[VANTAGE] Inventory modal: " .. tostring(invModal)) end
		else
			warn("[VANTAGE] InventoryHS: " .. tostring(InvHS))
		end
	end
		NAV.Crates = function() openModal("Cases") end
	else
		warn("[VANTAGE] Cases modal: " .. tostring(casesModal))
	end

	do -- Season Pass modal (Hypershot battlepass layout; SeasonPassService)
		local okP, SPHS = pcall(require, script:WaitForChild("SeasonPassHS2")) -- v2 (2026-11-17); v1 SeasonPassHS kept as fallback
		if okP then
			local okM, passModal = pcall(SPHS.Mount, modalLayer, {
				HS = HS,
				Close = function(silent) closeModal(silent) end,
				Open = function(name) openModal(name) end,
				Badge = function(n)
					local b = hudRoot and hudRoot:FindFirstChild("Battlepass", true)
					if b then HS.badge(b, n) end
				end,
			})
			if okM then ui.Modals.Battlepass = passModal else warn("[VANTAGE] Season Pass modal: " .. tostring(passModal)) end
		else
			warn("[VANTAGE] SeasonPassHS: " .. tostring(SPHS))
		end
	end

	do -- Weapon Mastery modal (2026-11-17; MasteryService, WeaponUnlocks)
		local okR, MHS = pcall(require, script:WaitForChild("MasteryHS"))
		if okR then
			local okM, mModal = pcall(MHS.Mount, modalLayer, {
				HS = HS,
				Close = function(silent) closeModal(silent) end,
				Open = function(name) openModal(name) end,
			})
			if okM then ui.Modals.Mastery = mModal else warn("[VANTAGE] Mastery modal: " .. tostring(mModal)) end
		else
			warn("[VANTAGE] MasteryHS: " .. tostring(MHS))
		end
	end

	do -- Ichor Farm screen (2026-11-19; FarmHS + FarmStage, SignatureService Well)
		local okR, FHS = pcall(require, script:WaitForChild("FarmHS"))
		if okR then
			local okM, farm = pcall(FHS.new, { HS = HS, Close = function() hideScreen() end })
			if okM then ui.Farm = farm else warn("[VANTAGE] Farm screen: " .. tostring(farm)) end
		else
			warn("[VANTAGE] FarmHS: " .. tostring(FHS))
		end
	end

	do -- Profile + Ranked modal (2026-11-17; ProfileService, RankedConfig)
		local okR, PHS = pcall(require, script:WaitForChild("ProfileHS"))
		if okR then
			local okM, pModal = pcall(PHS.Mount, modalLayer, {
				HS = HS,
				Close = function(silent) closeModal(silent) end,
				Open = function(name) openModal(name) end,
			})
			if okM then ui.Modals.Profile = pModal else warn("[VANTAGE] Profile modal: " .. tostring(pModal)) end
		else
			warn("[VANTAGE] ProfileHS: " .. tostring(PHS))
		end
		for _, a in { "RP", "Banner", "RankLegend" } do
			player:GetAttributeChangedSignal(a):Connect(function() pcall(renderData) end)
		end
	end

	do -- Game Modes select (2026-11-18; ModesHS replaces the Pages "Modes" card row)
		local okR, MDH = pcall(require, script:WaitForChild("ModesHS"))
		if okR then
			local okM, mdModal = pcall(MDH.Mount, modalLayer, {
				HS = HS, Modes = MODES, State = state,
				Close = function(silent) closeModal(silent) end,
				SelectMode = function(i, andPlay)
					state.Selected = i
					renderDeploy()
					closeModal(true)
					if andPlay then
						Lobby.Deploy()
					end
				end,
			})
			if okM then
				local old = ui.Modals.Modes
				if old and old.Root then old.Root.Visible = false end
				ui.Modals.Modes = mdModal
			else
				warn("[VANTAGE] Modes modal: " .. tostring(mdModal))
			end
		else
			warn("[VANTAGE] ModesHS: " .. tostring(MDH))
		end
	end

	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)

	-- keys: F deploy / cancel, M modes, Esc / B / Backspace closes the open modal
	UserInputService.InputBegan:Connect(function(input, processed)
		if not gui.Enabled or UserInputService:GetFocusedTextBox() then
			return
		end
		local kc = input.KeyCode
		-- map vote: 1 / 2 / 3 (gamepad: d-pad left / up / right)
		if ui.Found and ui.Found.Root.Visible and voteState() == "Vote" then
			local list = ui.Found.Vote.List
			local pick = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.KeypadFour] = 4, [Enum.KeyCode.DPadDown] = 3, [Enum.KeyCode.DPadLeft] = 1, [Enum.KeyCode.DPadUp] = 2, [Enum.KeyCode.DPadRight] = #list })[kc]
			if pick and list[pick] then
				castVote(list[pick])
				return
			end
		end
		if state.Screen then
			if state.Screen.HandleKey then
				pcall(state.Screen.HandleKey, state.Screen, kc)
			end
			return
		end
		if (ctx.Settings and ctx.Settings.Open) or (ctx.Armory and ctx.Armory.Open) then
			return
		end
		if state.Modal then
			if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Backspace then
				closeModal()
			end
			return
		end
		if processed then
			return
		end
		if kc == Enum.KeyCode.F or kc == Enum.KeyCode.ButtonX then
			if flow.Stage == "Queue" or flow.Stage == "Error" then
				Lobby.CancelQueue()
			elseif flow.Stage == nil then
				Lobby.Deploy()
			end
		elseif kc == Enum.KeyCode.M or kc == Enum.KeyCode.ButtonY then
			if flow.Stage == nil then
				NAV.Modes()
			end
		end
	end)

	task.spawn(function()
		local m = Vantage:WaitForChild("Match", 60)
		if m then
			m:GetAttributeChangedSignal("Phase"):Connect(Lobby._onFlow)
		end
		player:GetAttributeChangedSignal("MatchStatus"):Connect(Lobby._onFlow)
		Lobby._onFlow()
	end)
	for _, a in { "REQ", "ORD", "Level", "LevelXP", "LevelNeed" } do
		player:GetAttributeChangedSignal(a):Connect(renderData)
	end
	local upd = Remotes:FindFirstChild("ProgressionUpdate")
	if upd then
		upd.OnClientEvent:Connect(function(snap)
			if type(snap) == "table" and snap.Daily then
				data = snap
				renderData()
			else
				fetch()
			end
		end)
	end
	RunService.RenderStepped:Connect(renderStep)
	RunService.Heartbeat:Connect(syncVisible)
	task.spawn(function()
		while true do
			if gui.Enabled then
				renderBoard()
			end
			task.wait(2)
		end
	end)
	fetch()
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DevLobbyNav"):Connect(function()
			local n = player:GetAttribute("DevLobbyNav")
			if n == "Close" then
				closeModal()
				hideScreen()
			elseif n == "Deploy" then
				Lobby.Deploy()
			elseif n == "StartNow" then
				Lobby.StartNow()
			elseif n == "Cancel" then
				Lobby.CancelQueue()
			elseif NAV[n] then
				NAV[n]()
			end
		end)
	end
end

return Lobby
