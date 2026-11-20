--[[
	ProfileService - VantageShot Profile + Ranked (server), 2026-11-17.
	- DataStore "VantageProfile_v1", key "u_<UserId>" -> { RP, Shield, Protect, Streak, Best, Banner, H = { Casual = {...}, Ranked = {...} } }
	  Studio playtests never write (same rule as REQ / Progression).
	- Match results arrive through the ProfileMatch BindableEvent (MatchService.endMatch):
	    entry = { M = modeId, R = "W"|"L"|"D", K, D, A, S = "my-their", Map, RP = delta|nil, T = os.time() }
	  K / D from MatchStatsServer (MatchStats_Kills / _Deaths), A from MatchStats_Assists (EliminationService).
	  Ranked modes (MatchConfig Ranked = true) change RP: win / loss / draw + performance, daily shield, rank-up protection.
	- Replicated player attributes (every client can read them, so viewing someone else's profile needs no remote):
	    RP, RankIndex, RankName, RankTier, RankInto, RankNeed, RankLegend, Streak, BestStreak, Banner, ProfileHist (JSON)
	- Global ladder: OrderedDataStore "VantageRP_v1", top 100 cached every 120 s into Vantage attribute "RankedTop" (JSON
	  { {U, N, RP}, ... }). In Studio the ladder is built from the players in the server. Legend = RP >= LegendRP and top 100.
	- Remotes.ProfileBanner(id) picks a banner.
	- Studio hooks (player attributes): DevRP = n (sets RP), DevMatch = "W" | "L" | "D" (adds a fake ranked result),
	  DevMatchCasual = "W" | "L" (adds a fake casual result).
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local R = require(Vantage:WaitForChild("Ranked"):WaitForChild("RankedConfig"))
local MatchConfig = require(Vantage:WaitForChild("MatchConfig"))
local remotes = Vantage:WaitForChild("Remotes")

local SAVE = not RunService:IsStudio()
local store, ordered
pcall(function()
	store = DataStoreService:GetDataStore("VantageProfile_v1")
	ordered = DataStoreService:GetOrderedDataStore("VantageRP_v1")
end)

local data, dirty = {}, {}
local loadedOk = {} -- 2026-11-20 tutorial: false = the profile failed to load (never auto-start, never save Tut)
local legendSet = {}
local function key(p) return "u_" .. p.UserId end
local function today() return math.floor(os.time() / 86400) end

local function fresh()
	return { RP = 0, Shield = -1, Protect = 0, Streak = 0, Best = 0, Banner = R.DefaultBanner, H = { Casual = {}, Ranked = {} } }
end

local function publish(p)
	local d = data[p]
	if not d then return end
	local legend = legendSet[p.UserId] == true and d.RP >= R.LegendRP
	local r = R.RankOf(d.RP, legend)
	p:SetAttribute("RP", d.RP)
	p:SetAttribute("RankIndex", r.Index)
	p:SetAttribute("RankName", r.Name)
	p:SetAttribute("RankTier", r.Tier or 0)
	p:SetAttribute("RankInto", r.Into)
	p:SetAttribute("RankNeed", r.Need)
	p:SetAttribute("RankLegend", legend)
	p:SetAttribute("Streak", d.Streak)
	p:SetAttribute("BestStreak", d.Best)
	p:SetAttribute("Banner", d.Banner)
	if loadedOk[p] ~= false then
		p:SetAttribute("TutorialDone", d.Tut ~= nil) -- TutorialService: arena training done (Tut >= 1)
		p:SetAttribute("TutorialBriefed", (tonumber(d.Tut) or 0) >= 2) -- lobby briefing done (Tut >= 2)
	end
	local ok, js = pcall(HttpService.JSONEncode, HttpService, d.H)
	if ok then p:SetAttribute("ProfileHist", js) end
end

local function save(p)
	local d = data[p]
	if not (SAVE and store and d and dirty[p]) then return end
	dirty[p] = nil
	local ok, err = pcall(function() store:SetAsync(key(p), d) end)
	if not ok then
		dirty[p] = true
		warn("[VANTAGE] Profile save failed:", err)
	end
	if ordered then pcall(function() ordered:SetAsync(tostring(p.UserId), d.RP) end) end
end

local function load(p)
	local d = fresh()
	local okLoad = true
	if SAVE and store then
		local ok, res = pcall(function() return store:GetAsync(key(p)) end)
		if ok and type(res) == "table" then
			for k, v in res do d[k] = v end
			d.H = type(d.H) == "table" and d.H or { Casual = {}, Ranked = {} }
			d.H.Casual, d.H.Ranked = d.H.Casual or {}, d.H.Ranked or {}
			if not R.BannerById[d.Banner] then d.Banner = R.DefaultBanner end
			-- players who played before the tutorial existed count as trained
			if d.Tut == nil and (#d.H.Casual + #d.H.Ranked > 0 or (tonumber(d.RP) or 0) > 0) then d.Tut = 2 end
		elseif not ok then
			warn("[VANTAGE] Profile load failed:", res)
			okLoad = false
		end
	end
	if not p.Parent then return end
	loadedOk[p] = okLoad
	data[p] = d
	publish(p)
end

local function push(list, e)
	table.insert(list, 1, e)
	while #list > R.HistoryMax do table.remove(list) end
end

-- one finished match for one player
local function record(p, modeId, result, mine, theirs)
	local d = data[p]
	if not d then return end
	local mode = MatchConfig.Modes[modeId] or {}
	local k = tonumber(p:GetAttribute("MatchStats_Kills")) or 0
	local dd = tonumber(p:GetAttribute("MatchStats_Deaths")) or 0
	local a = tonumber(p:GetAttribute("MatchStats_Assists")) or 0
	local e = { M = modeId, R = result, K = k, D = dd, A = a, S = string.format("%d-%d", mine or 0, theirs or 0), Map = (game:GetService("ReplicatedStorage").Vantage:FindFirstChild("Match") and game:GetService("ReplicatedStorage").Vantage.Match:GetAttribute("MapName")) or (MatchConfig.Map and MatchConfig.Map.Name) or "LIVE FIRE", T = os.time() }
	if result == "W" then
		d.Streak += 1
		d.Best = math.max(d.Best, d.Streak)
	else
		d.Streak = 0
	end
	if mode.Ranked then
		local before = R.RankOf(d.RP)
		local perf = R.Perf(k, dd, a)
		local delta
		if result == "W" then
			delta = R.Win + perf
		elseif result == "L" then
			if d.Shield ~= today() then
				d.Shield = today()
				delta = math.max(0, perf) -- daily shield: the first loss of the day costs nothing
			else
				delta = R.Loss + perf
			end
		else
			delta = R.Draw + perf
		end
		local floorRP = (before.Index - 1) * R.TiersPerRank * R.TierRP
		local rp = math.max(0, d.RP + delta)
		if d.Protect > 0 then
			rp = math.max(rp, math.min(floorRP, d.RP)) -- rank-up protection: no drop below this rank
			d.Protect -= 1
		end
		e.RP = rp - d.RP
		d.RP = rp
		if R.RankOf(d.RP).Index > before.Index then d.Protect = R.ProtectMatches end
		push(d.H.Ranked, e)
	else
		push(d.H.Casual, e)
	end
	dirty[p] = true
	publish(p)
	task.spawn(save, p)
end

local Ev = script.Parent:FindFirstChild("ProfileMatch") or Instance.new("BindableEvent")
Ev.Name = "ProfileMatch"
Ev.Parent = script.Parent
Ev.Event:Connect(function(p, teamName, winner, modeId, blue, red)
	local result = if winner == teamName then "W" elseif winner == "Blue" or winner == "Red" then "L" else "D"
	local mine, theirs = if teamName == "Blue" then blue else red, if teamName == "Blue" then red else blue
	local ok, err = pcall(record, p, modeId, result, mine, theirs)
	if not ok then warn("[VANTAGE] Profile record failed:", err) end
end)

-- 2026-11-20 tutorial completion (TutorialService): ("Complete", p, level) saves at once (1 = arena training,
-- 2 = lobby briefing too); ("Get", p) -> level
local TutFn = script.Parent:FindFirstChild("ProfileTutorial") or Instance.new("BindableFunction")
TutFn.Name = "ProfileTutorial"
TutFn.Parent = script.Parent
TutFn.OnInvoke = function(action, p, level)
	local d = data[p]
	if not d then return false end
	if action == "Complete" then
		local level = math.clamp(tonumber(level) or 1, 1, 2)
		if (tonumber(d.Tut) or 0) < level then
			d.Tut = level
			if loadedOk[p] ~= false then dirty[p] = true end -- never overwrite a profile that failed to load
		end
		publish(p)
		task.spawn(save, p)
		return true
	end
	return tonumber(d.Tut) or 0
end

local Banner = remotes:FindFirstChild("ProfileBanner") or Instance.new("RemoteEvent")
Banner.Name = "ProfileBanner"
Banner.Parent = remotes
Banner.OnServerEvent:Connect(function(p, bid)
	local d = data[p]
	if d and type(bid) == "string" and R.BannerById[bid] and d.Banner ~= bid then
		d.Banner = bid
		dirty[p] = true
		publish(p)
	end
end)

-- assists are counted per match by EliminationService (MatchStats_Assists); reset with the other match stats
local Match = Vantage:WaitForChild("Match", 30)
if Match then
	local function reset()
		for _, p in Players:GetPlayers() do p:SetAttribute("MatchStats_Assists", 0) end
	end
	Match:GetAttributeChangedSignal("MatchId"):Connect(reset)
	Match:GetAttributeChangedSignal("Phase"):Connect(function()
		if Match:GetAttribute("Phase") == "Prep" then reset() end
	end)
end

-- global ladder (top 100) and Legend
local nameCache = {}
local function refreshTop()
	local list = {}
	if SAVE and ordered then
		local ok, pages = pcall(function() return ordered:GetSortedAsync(false, R.LegendTop) end)
		if ok and pages then
			for _, item in pages:GetCurrentPage() do
				local uid = tonumber(item.key)
				if uid then
					if not nameCache[uid] then
						local okN, nm = pcall(Players.GetNameFromUserIdAsync, Players, uid)
						nameCache[uid] = okN and nm or ("Player " .. uid)
					end
					table.insert(list, { U = uid, N = nameCache[uid], RP = item.value })
				end
			end
		end
	else
		for p, d in data do
			table.insert(list, { U = p.UserId, N = p.DisplayName, RP = d.RP })
		end
		table.sort(list, function(a, b) return a.RP > b.RP end)
	end
	table.clear(legendSet)
	for i, e in list do
		if i <= R.LegendTop then legendSet[e.U] = true end
	end
	local ok, js = pcall(HttpService.JSONEncode, HttpService, list)
	if ok then Vantage:SetAttribute("RankedTop", js) end
	for p in data do publish(p) end
end

local function devHooks(p)
	if not RunService:IsStudio() then return end
	p:GetAttributeChangedSignal("DevRP"):Connect(function()
		local n = tonumber(p:GetAttribute("DevRP"))
		if n and data[p] then
			p:SetAttribute("DevRP", nil)
			data[p].RP = math.max(0, math.floor(n))
			publish(p)
			refreshTop()
		end
	end)
	local function fake(attr, modeId)
		p:GetAttributeChangedSignal(attr):Connect(function()
			local r = p:GetAttribute(attr)
			if type(r) == "string" then
				p:SetAttribute(attr, nil)
				p:SetAttribute("MatchStats_Kills", math.random(2, 18))
				p:SetAttribute("MatchStats_Deaths", math.random(1, 10))
				p:SetAttribute("MatchStats_Assists", math.random(0, 6))
				local a, b = 50, math.random(12, 47)
				if r == "L" then a, b = b, 50 elseif r == "D" then b = a end
				record(p, modeId, r, a, b)
			end
		end)
	end
	fake("DevMatch", "RTDM")
	fake("DevMatchCasual", "TDM")
end

Players.PlayerAdded:Connect(function(p)
	devHooks(p)
	load(p)
	refreshTop()
end)
for _, p in Players:GetPlayers() do
	devHooks(p)
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p], dirty[p], loadedOk[p] = nil, nil, nil
end)
task.spawn(function()
	while true do
		task.wait(120)
		for p in dirty do task.spawn(save, p) end
		refreshTop()
	end
end)
game:BindToClose(function()
	if not (SAVE and store) then return end
	for p in data do task.spawn(save, p) end
	task.wait(2)
end)
