--!nocheck
--[[
	VANTAGE — Lobby pages (client)  ·  2026-11-15
	The modal screens opened from the lobby HUD, all built on Gloss.shell:
	  Modes       game mode cards (live modes queue straight away; others show COMING SOON)
	  Challenges  Daily Directives + the weekly Operation (real data: ProgressionGet)
	  Profile     level, rank, XP and career stats (real data)
	  Inventory · Trading · Battlepass · Store   layout in place, systems to be filled in later
	Pages.Build(layer, env) -> { [name] = { Root, OnShow?, OnHide?, OnData? } }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Assets = require(Vantage:WaitForChild("UI"):WaitForChild("LobbyAssets"))
local ReqConfig = require(Vantage:WaitForChild("Requisition"):WaitForChild("RequisitionConfig"))

local player = Players.LocalPlayer
local Pages = {}

function Pages.Build(layer, env)
	local G = env.G
	local C, F = G.C, G.F
	local new, text = G.new, G.text
	local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
	local pages = {}

	local function shell(name, title, w, h)
		local root, content = G.shell(layer, { Name = name, Title = title, Width = w, Height = h, OnClose = env.Close })
		local page = { Root = root, Content = content }
		pages[name] = page
		return page, content
	end

	-- a "coming soon" ribbon for systems that aren't built yet
	local function soon(parent, line)
		local r = new("Frame", { Name = "Soon", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(600, 124), BackgroundColor3 = Color3.fromRGB(16, 16, 22), ZIndex = 30 }, parent)
		G.corner(r, 22)
		G.stroke(r, 5, C.Gold)
		text(r, { Text = "COMING SOON", Position = O(0, 12), Size = UDim2.new(1, 0, 0, 58), TextSize = 56, Font = F.Black, Color = C.Gold, Stroke = 3.6, ZIndex = 31 })
		text(r, { Text = line or "", Position = O(0, 72), Size = UDim2.new(1, 0, 0, 34), TextSize = 24, Font = F.Bold, Color = C.Muted, Stroke = 0, ZIndex = 31 })
		return r
	end

	-- ── Modes ─────────────────────────────────────────────────────────────────────────
	do
		local page, c = shell("Modes", "Game Modes", 1500, 760)
		local row = new("Frame", { BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 22 }, c)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 26), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
		local cards = {}
		for i, m in env.Modes do
			local card = G.artCard(row, { Name = m.Id, Color = m.Color, Size = O(math.min(320, math.floor((1440 - (#env.Modes - 1) * 26) / #env.Modes)), 580), LayoutOrder = i, Button = true, OnClick = function()
				if m.Live then
					env.SelectMode(i, true)
				end
			end })
			text(card, { Text = m.Short, Position = O(10, 34), Size = UDim2.new(1, -20, 0, 60), TextSize = 50, Font = F.Black, Stroke = 4, ZIndex = 24, Scaled = true, MaxSize = 50 })
			text(card, { Text = if m.TeamSize > 0 then (m.TeamSize .. " v " .. m.TeamSize) else "Objective", Position = O(0, 100), Size = UDim2.new(1, 0, 0, 44), TextSize = 38, Stroke = 3, ZIndex = 24 })
			text(card, { Text = m.Desc, Position = O(26, 168), Size = UDim2.new(1, -52, 0, 140), TextSize = 27, Wrapped = true, Stroke = 2.6, ZIndex = 24, Y = Enum.TextYAlignment.Top })
			local q = text(card, { Name = "Queue", Text = "", Position = O(0, 330), Size = UDim2.new(1, 0, 0, 36), TextSize = 28, Stroke = 2.6, ZIndex = 24 })
			local play = G.wide(card, { Name = "Play", Color = if m.Live then "Green" else "Blue", Text = if m.Live then "PLAY" else "SOON", Width = 230, Height = 115, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), ZIndex = 24, OnClick = function()
				if m.Live then
					env.SelectMode(i, true)
				end
			end })
			if not m.Live then
				G.setDisabled(play, true)
				G.setDisabled(card, true)
			end
			local sel = G.square(card, "Check", 76, { AnchorPoint = V2(1, 0), Position = UDim2.new(1, 16, 0, -16), ZIndex = 26 })
			sel.Active = false
			cards[i] = { Card = card, Queue = q, Sel = sel, Mode = m }
		end
		page.OnShow = function()
			local mf = Vantage:FindFirstChild("Match")
			for i, k in cards do
				local n = mf and mf:GetAttribute("Queue_" .. k.Mode.Id) or 0
				k.Queue.Text = if k.Mode.Live then (n .. " in queue") else "Coming soon"
				k.Sel.Visible = env.State.Selected == i
			end
		end
	end

	-- ── Challenges ───────────────────────────────────────────────────────────────────
	do
		local page, c = shell("Challenges", "Challenges", 1500, 860)
		local hd = G.header(c, { Text = "Daily", Height = 64, Gap = 110 })
		hd.Size = UDim2.new(0.56, 0, 0, 64)
		local refresh = text(c, { Text = "", Position = O(0, 64), Size = UDim2.new(0.56, 0, 0, 40), TextSize = 32, Color = C.Pink, Stroke = 2.6, ZIndex = 23 })
		local rows = {}
		for i = 1, 3 do
			local card = G.card(c, { Position = O(0, 116 + (i - 1) * 172), Size = UDim2.new(0.56, 0, 0, 156), Color = Color3.fromRGB(46, 48, 64) })
			local tile = new("ImageLabel", { BackgroundTransparency = 1, Image = G.A.Tile[({ "Purple", "Blue", "Orange" })[i]], Position = O(14, 14), Size = O(128, 128), ZIndex = 23, ScaleType = Enum.ScaleType.Fit }, card)
			new("ImageLabel", { BackgroundTransparency = 1, Image = G.A.Pack.Target or G.A.Icon.Book, Position = S(0.1, 0.06), Size = S(0.8, 0.8), ZIndex = 24, ScaleType = Enum.ScaleType.Fit }, tile)
			local title = text(card, { Text = "", Position = O(160, 16), Size = UDim2.new(1, -360, 0, 76), X = Enum.TextXAlignment.Left, Y = Enum.TextYAlignment.Top, TextSize = 30, Wrapped = true, Stroke = 2.6, ZIndex = 24 })
			local _, set = G.bar(card, { Position = O(160, 104), Size = UDim2.new(1, -360, 0, 30), Color = C.Green, ZIndex = 24 })
			local prog = text(card, { Text = "", Position = O(160, 104), Size = UDim2.new(1, -360, 0, 30), TextSize = 22, Stroke = 2, ZIndex = 27 })
			local reward, rv = G.pill(card, { Width = 170, Height = 56, Icon = ReqConfig.Icon, TextSize = 30, AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0) })
			reward.ZIndex = 24
			local done = G.square(card, "Check", 86, { AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0), ZIndex = 27 })
			done.Active = false
			rows[i] = { Card = card, Title = title, Set = set, Prog = prog, Reward = reward, RewardText = rv, Done = done }
		end
		local opCol = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), ZIndex = 22 }, c)
		G.header(opCol, { Text = "Weekly", Height = 64, Gap = 110 })
		local ends = text(opCol, { Text = "", Position = O(0, 64), Size = UDim2.new(1, 0, 0, 40), TextSize = 32, Color = C.Pink, Stroke = 2.6, ZIndex = 23 })
		local op = G.artCard(opCol, { Color = "Orange", Position = O(0, 116), Size = UDim2.new(1, 0, 0, 500) })
		local opName = text(op, { Text = "", Position = O(10, 28), Size = UDim2.new(1, -20, 0, 56), TextSize = 46, Font = F.Black, Stroke = 4, ZIndex = 24, Scaled = true, MaxSize = 46 })
		local opText = text(op, { Text = "", Position = O(30, 92), Size = UDim2.new(1, -60, 0, 70), TextSize = 28, Wrapped = true, Stroke = 2.6, ZIndex = 24 })
		local _, opSet = G.bar(op, { Position = O(40, 176), Size = UDim2.new(1, -80, 0, 34), Color = C.Gold, ZIndex = 24 })
		local opProg = text(op, { Text = "", Position = O(40, 176), Size = UDim2.new(1, -80, 0, 34), TextSize = 24, Stroke = 2, ZIndex = 27 })
		local tiers = {}
		for i = 1, 3 do
			local t = G.card(op, { Position = UDim2.new((i - 1) / 3, if i == 1 then 30 elseif i == 2 then 10 else -10, 0, 240), Size = UDim2.new(1 / 3, -20, 0, 220), Color = Color3.fromRGB(40, 30, 24), ZIndex = 24 })
			text(t, { Text = "Tier " .. i, Position = O(0, 12), Size = UDim2.new(1, 0, 0, 36), TextSize = 30, Font = F.Black, Stroke = 2.6, ZIndex = 26 })
			new("ImageLabel", { BackgroundTransparency = 1, Image = ReqConfig.Icon, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = O(72, 72), ZIndex = 26, ScaleType = Enum.ScaleType.Fit }, t)
			local amt = text(t, { Text = "", Position = O(0, 132), Size = UDim2.new(1, 0, 0, 36), TextSize = 30, Stroke = 2.6, ZIndex = 26 })
			local goal = text(t, { Text = "", Position = O(0, 170), Size = UDim2.new(1, 0, 0, 30), TextSize = 22, Font = F.Bold, Color = C.Muted, Stroke = 0, ZIndex = 26 })
			local chk = G.square(t, "Check", 64, { AnchorPoint = V2(1, 0), Position = UDim2.new(1, 14, 0, -16), ZIndex = 28 })
			chk.Active = false
			tiers[i] = { Amt = amt, Goal = goal, Check = chk }
		end
		local function render(d)
			if not d then
				return
			end
			local now = os.time()
			refresh.Text = "Refreshes in " .. G.clock((d.DailyEnds or now) - now)
			for i, r in rows do
				local dir = d.Daily and d.Daily[i]
				r.Card.Visible = dir ~= nil
				if dir then
					r.Title.Text = dir.Text
					r.Set(dir.Progress / math.max(dir.Goal, 1))
					r.Prog.Text = if dir.Done then "Complete!" else (G.abbrev(dir.Progress) .. " / " .. G.abbrev(dir.Goal))
					r.RewardText.Text = G.abbrev(dir.Reward)
					r.Reward.Visible = not dir.Done
					r.Done.Visible = dir.Done
				end
			end
			local o = d.Operation
			if o then
				opName.Text = "Operation " .. tostring(o.Name)
				opText.Text = tostring(o.Text)
				local last = o.Tiers[#o.Tiers]
				local goal = last and last.Goal or 1
				opSet(o.Progress / goal)
				opProg.Text = G.abbrev(math.min(o.Progress, goal)) .. " / " .. G.abbrev(goal)
				ends.Text = "Ends in " .. G.clock((o.Ends or now) - now)
				for i, t in tiers do
					local tier = o.Tiers[i]
					t.Amt.Text = tier and ("+" .. G.abbrev(tier.Reward)) or ""
					t.Goal.Text = tier and ("at " .. G.abbrev(tier.Goal)) or ""
					t.Check.Visible = tier ~= nil and tier.Paid == true
				end
			end
		end
		page.OnShow = render
		page.OnData = render
		task.spawn(function()
			while true do
				task.wait(1)
				if page.Root.Visible then
					local d = env.Data()
					if d then
						local now = os.time()
						refresh.Text = "Refreshes in " .. G.clock((d.DailyEnds or now) - now)
						if d.Operation then
							ends.Text = "Ends in " .. G.clock((d.Operation.Ends or now) - now)
						end
					end
				end
			end
		end)
	end

	-- ── Profile ──────────────────────────────────────────────────────────────────────
	do
		local page, c = shell("Profile", "Profile", 1400, 800)
		local left = G.card(c, { Position = O(0, 0), Size = O(440, 660), Color = Color3.fromRGB(60, 74, 120) })
		local av = new("ImageLabel", { BackgroundTransparency = 1, Position = O(20, 60), Size = O(400, 400), ZIndex = 23 }, left)
		text(left, { Text = player.DisplayName, Position = O(0, 12), Size = UDim2.new(1, 0, 0, 50), TextSize = 42, Font = F.Black, Stroke = 3.4, ZIndex = 24 })
		local shield = new("ImageLabel", { BackgroundTransparency = 1, Position = O(20, 470), Size = O(110, 110), ZIndex = 24, ScaleType = Enum.ScaleType.Fit }, left)
		local lvl = text(left, { Text = "", Position = O(140, 476), Size = O(280, 50), X = Enum.TextXAlignment.Left, TextSize = 44, Font = F.Black, Stroke = 3.4, ZIndex = 24 })
		local tier = text(left, { Text = "", Position = O(140, 526), Size = O(280, 40), X = Enum.TextXAlignment.Left, TextSize = 28, Color = C.Gold, Stroke = 2.4, ZIndex = 24 })
		local _, setXP = G.bar(left, { Position = O(20, 600), Size = UDim2.new(1, -40, 0, 34), Color = C.Gold, ZIndex = 24 })
		local xpText = text(left, { Text = "", Position = O(20, 600), Size = UDim2.new(1, -40, 0, 34), TextSize = 22, Stroke = 2, ZIndex = 27 })
		local grid = new("Frame", { BackgroundTransparency = 1, Position = O(480, 0), Size = UDim2.new(1, -480, 1, 0), ZIndex = 22 }, c)
		new("UIGridLayout", { CellSize = O(260, 150), CellPadding = O(22, 22), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local NAMES = { Elims = "Eliminations", Kills = "Eliminations", Deaths = "Deaths", Wins = "Wins", Matches = "Matches", Headshots = "Headshots", Assists = "Assists", Damage = "Damage" }
		local COLORS = { "Blue", "Red", "Green", "Orange", "White" }
		local cells = {}
		local function render(d)
			local level = player:GetAttribute("Level") or (d and d.Level) or 1
			local into = player:GetAttribute("LevelXP") or (d and d.LevelXP) or 0
			local need = player:GetAttribute("LevelNeed") or (d and d.LevelNeed) or 1000
			local ok, img, tn = pcall(G.RankFor, level)
			shield.Image = ok and img or ""
			lvl.Text = "Level " .. level
			tier.Text = (ok and tn and (tostring(tn) .. " Rank")) or ""
			setXP(into / math.max(need, 1))
			xpText.Text = G.abbrev(into) .. " / " .. G.abbrev(need) .. " XP"
			if d and d.Stats then
				local keys = {}
				for k in d.Stats do
					table.insert(keys, k)
				end
				table.sort(keys)
				for i, k in keys do
					local cell = cells[k]
					if not cell then
						cell = G.artCard(grid, { Color = COLORS[(i - 1) % #COLORS + 1], Size = O(260, 150), LayoutOrder = i })
						cell.Name = k
						text(cell, { Name = "V", Text = "", Position = O(0, 18), Size = UDim2.new(1, 0, 0, 64), TextSize = 58, Font = F.Black, Stroke = 4, ZIndex = 24 })
						text(cell, { Text = NAMES[k] or k, Position = O(0, 86), Size = UDim2.new(1, 0, 0, 40), TextSize = 30, Stroke = 2.8, ZIndex = 24 })
						cells[k] = cell
					end
					cell.V.Text = G.abbrev(d.Stats[k])
				end
			end
		end
		page.OnShow = function(d)
			if av.Image == "" then
				task.spawn(function()
					local ok, img = pcall(function()
						return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
					end)
					if ok then
						av.Image = img
					end
				end)
			end
			render(d)
		end
		page.OnData = render
	end

	-- ── Inventory (layout only, system to come) ───────────────────────────────────────
	do
		local _, c = shell("Inventory", "Inventory", 1500, 860)
		local tabs = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 100), ZIndex = 22 }, c)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
		for i, t in { { "SKINS", "Blue" }, { "EQUIPMENT", "Red" }, { "EFFECTS", "Purple" }, { "COLLECTIBLES", "Yellow" } } do
			local b = G.wide(tabs, { Text = t[1], Color = t[2], Width = 230, Height = 92, LayoutOrder = i, TextSize = 30 })
			G.setDisabled(b, i > 1)
		end
		local grid = new("Frame", { BackgroundTransparency = 1, Position = O(0, 124), Size = UDim2.new(1, 0, 1, -124), ZIndex = 22 }, c)
		new("UIGridLayout", { CellSize = O(200, 190), CellPadding = O(22, 22), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i = 1, 12 do
			local cell = G.artCard(grid, { Color = "White", Size = O(200, 190), LayoutOrder = i })
		end
		soon(c, "Owned skins, armour and collectibles will live here.")
	end

	-- ── Trading (layout only) ────────────────────────────────────────────────────────
	do
		local _, c = shell("Trading", "Trading", 1500, 860)
		for i, side in { "Your Offer", "Their Offer" } do
			local card = G.card(c, { Position = UDim2.new((i - 1) * 0.52, 0, 0, 0), Size = UDim2.new(0.48, 0, 1, -150), Color = Color3.fromRGB(46, 48, 64) })
			text(card, { Text = side, Position = O(0, 14), Size = UDim2.new(1, 0, 0, 56), TextSize = 46, Font = F.Black, Stroke = 3.4, ZIndex = 24 })
			local g = new("Frame", { BackgroundTransparency = 1, Position = O(24, 90), Size = UDim2.new(1, -48, 1, -110), ZIndex = 23 }, card)
			new("UIGridLayout", { CellSize = O(146, 146), CellPadding = O(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }, g)
			for k = 1, 8 do
				local slot = G.card(g, { Size = O(146, 146), Color = Color3.fromRGB(26, 27, 36), LayoutOrder = k, ZIndex = 24 })
				slot.BackgroundTransparency = 0.2
			end
		end
		local accept = G.wide(c, { Text = "ACCEPT", Color = "Green", Width = 260, Height = 116, AnchorPoint = V2(1, 1), Position = UDim2.new(1, 0, 1, 0) })
		local invite = G.wide(c, { Text = "INVITE", Color = "Blue", Width = 260, Height = 116, AnchorPoint = V2(0, 1), Position = UDim2.new(0, 0, 1, 0) })
		G.setDisabled(accept, true)
		G.setDisabled(invite, true)
		soon(c, "Trade skins and collectibles with other Legionaries.")
	end

	-- ── Battlepass (layout only) ─────────────────────────────────────────────────────
	do
		local _, c = shell("Battlepass", "Battlepass", 1560, 820)
		text(c, { Text = "Season 1", Position = O(0, -8), Size = UDim2.new(1, 0, 0, 70), TextSize = 64, Font = F.Black, Color = C.Gold, Stroke = 4.4, ZIndex = 23 })
		local track = new("ScrollingFrame", { BackgroundTransparency = 1, Position = O(0, 84), Size = UDim2.new(1, 0, 0, 440), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = O(0, 0), ScrollBarThickness = 8, BorderSizePixel = 0, ZIndex = 22 }, c)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, track)
		local colors = { "Blue", "Green", "Orange", "Red", "White" }
		for i = 1, 20 do
			local col = new("Frame", { BackgroundTransparency = 1, Size = O(200, 420), LayoutOrder = i, ZIndex = 22 }, track)
			text(col, { Text = "Tier " .. i, Size = UDim2.new(1, 0, 0, 44), TextSize = 32, Stroke = 2.8, ZIndex = 24 })
			for r = 0, 1 do
				local cell = G.artCard(col, { Color = if r == 0 then colors[(i - 1) % #colors + 1] else "White", Position = O(0, 52 + r * 178), Size = O(200, 166), ZIndex = 23 })
				text(cell, { Text = if r == 0 then "Free" else "Premium", Position = O(0, 112), Size = UDim2.new(1, 0, 0, 36), TextSize = 26, Stroke = 2.2, ZIndex = 25 })
			end
		end
		local buy = G.wide(c, { Text = "UNLOCK PREMIUM", Color = "Purple", Width = 380, Height = 130, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, 10), TextSize = 36 })
		G.setDisabled(buy, true)
		soon(c, "Earn tiers with XP from every match.")
	end

	-- ── Store (layout only) ──────────────────────────────────────────────────────────
	do
		local _, c = shell("Store", "Store", 1500, 820)
		G.header(c, { Text = "REQ Packs", Height = 64, Gap = 200 })
		local row = new("Frame", { BackgroundTransparency = 1, Position = O(0, 100), Size = UDim2.new(1, 0, 0, 440), ZIndex = 22 }, c)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 30), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
		for i, p in { { "Small", "Blue" }, { "Medium", "Green" }, { "Large", "Orange" }, { "Huge", "Red" } } do
			local card = G.artCard(row, { Color = p[2], Size = O(300, 420), LayoutOrder = i })
			text(card, { Text = p[1] .. " Pack", Position = O(0, 22), Size = UDim2.new(1, 0, 0, 50), TextSize = 42, Font = F.Black, Stroke = 3.6, ZIndex = 24 })
			new("ImageLabel", { BackgroundTransparency = 1, Image = ReqConfig.Icon, AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = O(140, 140), ZIndex = 24, ScaleType = Enum.ScaleType.Fit }, card)
			local b = G.wide(card, { Text = "R$ —", Color = "Green", Width = 220, Height = 104, AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), ZIndex = 24 })
			G.setDisabled(b, true)
		end
		soon(c, "Robux packs and gamepasses are not set up yet.")
	end

	return pages
end

return Pages
