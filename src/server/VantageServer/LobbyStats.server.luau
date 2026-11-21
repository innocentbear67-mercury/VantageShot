--[[
	VANTAGE — LobbyStats (server) · 2026-11-18
	Feeds the four plaza leaderboards in Workspace.HyperLobby.02_Leaderboards (Screen parts with attribute Stat =
	KILLS | WINS | LEVEL | PLAYTIME; rows Row1..Row10 with Rank / Player / Value labels).
	Global, all-time boards from OrderedDataStores:
	  VantageLB_Kills_v1, VantageLB_Wins_v1  — added at each match end (ProfileMatch BindableEvent from MatchService;
	                                            kills = the player's MatchStats_Kills at that moment)
	  VantageLB_Playtime_v1                   — minutes, added every 5 min and on leave
	  VantageLB_Level_v1                      — player attribute Level, written when it changes (throttled) and on leave
	Studio never writes (same rule as REQ / Progression / ProfileService); in Studio the boards show this server's
	players with this session's numbers.
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SAVE = not RunService:IsStudio()
local lobby = workspace:WaitForChild("HyperLobby", 30)
if not lobby then return end

local STORES = { KILLS = "VantageLB_Kills_v1", WINS = "VantageLB_Wins_v1", PLAYTIME = "VantageLB_Playtime_v1", LEVEL = "VantageLB_Level_v1" }
local ordered = {}
if SAVE then
	for stat, name in STORES do
		pcall(function() ordered[stat] = DataStoreService:GetOrderedDataStore(name) end)
	end
end

-- session numbers (Studio display + pending playtime)
local session = {} -- [Player] = { Kills, Wins, Joined, LastFlush, LevelSaved }
local function rec(p)
	local r = session[p]
	if not r then
		r = { Kills = 0, Wins = 0, Joined = os.clock(), LastFlush = os.clock(), LevelSaved = 0 }
		session[p] = r
	end
	return r
end

local function bump(stat, p, amount)
	if not SAVE or amount <= 0 or not ordered[stat] then return end
	task.spawn(function()
		local ok, err = pcall(function() ordered[stat]:IncrementAsync("u_" .. p.UserId, math.floor(amount)) end)
		if not ok then warn("[VANTAGE] LobbyStats " .. stat .. ": " .. tostring(err)) end
	end)
end
local function saveLevel(p)
	local r = session[p]
	local lv = p:GetAttribute("Level") or 0
	if not r or lv <= 0 or lv == r.LevelSaved or not SAVE or not ordered.LEVEL then return end
	r.LevelSaved = lv
	task.spawn(function()
		pcall(function() ordered.LEVEL:SetAsync("u_" .. p.UserId, lv) end)
	end)
end
local function flushPlaytime(p)
	local r = session[p]
	if not r then return end
	local mins = math.floor((os.clock() - r.LastFlush) / 60)
	if mins >= 1 then
		r.LastFlush += mins * 60
		bump("PLAYTIME", p, mins)
	end
end

local ev = script.Parent:WaitForChild("ProfileMatch", 30)
if ev then
	ev.Event:Connect(function(p, teamName, winner)
		if typeof(p) ~= "Instance" or not p:IsA("Player") then return end
		local r = rec(p)
		local k = p:GetAttribute("MatchStats_Kills") or 0
		local won = teamName ~= nil and teamName == winner
		r.Kills += k
		if won then r.Wins += 1 end
		bump("KILLS", p, k)
		if won then bump("WINS", p, 1) end
	end)
end

Players.PlayerAdded:Connect(rec)
for _, p in Players:GetPlayers() do rec(p) end
Players.PlayerRemoving:Connect(function(p)
	flushPlaytime(p)
	saveLevel(p)
	session[p] = nil
end)
game:BindToClose(function()
	for _, p in Players:GetPlayers() do
		flushPlaytime(p)
		saveLevel(p)
	end
	task.wait(2)
end)

-- ── boards ────────────────────────────────────────────────────────────────────────────
local boards = {}
for _, d in lobby:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Stat") then
		local gui = d:FindFirstChildWhichIsA("SurfaceGui")
		if gui then boards[d:GetAttribute("Stat")] = gui end
	end
end

local names = {}
local function nameOf(userId)
	if names[userId] then return names[userId] end
	local p = Players:GetPlayerByUserId(userId)
	if p then names[userId] = p.DisplayName return p.DisplayName end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	names[userId] = ok and n or ("#" .. userId)
	return names[userId]
end
local function fmt(stat, v)
	if stat == "PLAYTIME" then
		local h, m = v // 60, v % 60
		return if h > 0 then string.format("%dh %02dm", h, m) else string.format("%dm", m)
	elseif stat == "LEVEL" then
		return "LV " .. v
	end
	return tostring(v)
end
local function paint(stat, list)
	local frame = boards[stat]
	if not frame then return end
	for i = 1, 10 do
		local row = frame:FindFirstChild("Row" .. i, true)
		if row then
			local e = list[i]
			local pl, val = row:FindFirstChild("Player"), row:FindFirstChild("Value")
			if pl then pl.Text = e and e.Name or "---" end
			if val then val.Text = e and fmt(stat, e.V) or "0" end
		end
	end
end

local function studioList(stat)
	local list = {}
	for _, p in Players:GetPlayers() do
		local r = rec(p)
		local v = if stat == "KILLS" then r.Kills elseif stat == "WINS" then r.Wins elseif stat == "PLAYTIME" then math.floor((os.clock() - r.Joined) / 60) else (p:GetAttribute("Level") or 0)
		if v > 0 or stat == "PLAYTIME" or stat == "LEVEL" then table.insert(list, { Name = p.DisplayName, V = v }) end
	end
	table.sort(list, function(a, b) return a.V > b.V end)
	return list
end
local function globalList(stat)
	local store = ordered[stat]
	if not store then return nil end
	local ok, pages = pcall(function() return store:GetSortedAsync(false, 10) end)
	if not ok then return nil end
	local list = {}
	for _, e in pages:GetCurrentPage() do
		local uid = tonumber(string.match(e.key, "%d+"))
		if uid then table.insert(list, { Name = nameOf(uid), V = e.value }) end
	end
	return list
end

-- level writes when it changes (throttled to one per player per 60 s)
local lastLevelWrite = {}
task.spawn(function()
	while true do
		task.wait(15)
		for _, p in Players:GetPlayers() do
			if os.clock() - (lastLevelWrite[p] or 0) > 60 then
				lastLevelWrite[p] = os.clock()
				saveLevel(p)
			end
		end
	end
end)
-- playtime every 5 min
task.spawn(function()
	while true do
		task.wait(300)
		for _, p in Players:GetPlayers() do flushPlaytime(p) end
	end
end)

local lastGlobal = 0
while true do
	for stat in boards do
		local list
		if SAVE then
			if os.clock() - lastGlobal > 120 or lastGlobal == 0 then
				list = globalList(stat)
			end
		else
			list = studioList(stat)
		end
		if list then paint(stat, list) end
	end
	if SAVE and (os.clock() - lastGlobal > 120 or lastGlobal == 0) then lastGlobal = os.clock() end
	task.wait(if SAVE then 10 else 3)
end
