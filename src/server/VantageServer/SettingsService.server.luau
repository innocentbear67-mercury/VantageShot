--[[
	VANTAGE — SettingsService (server)
	Persists each player's settings in DataStore "VantageSettings_v1" (key "u_<UserId>").
	  SettingsGet   RemoteFunction  -> (values, status "Loaded" | "Default" | "Failed")
	  SettingsSave  RemoteEvent     <- (values)   sanitised against SettingsConfig, throttled
	  SettingsSaved RemoteEvent     -> (ok)
	Failures never break the game: players keep defaults / their session values and the menu
	shows that saving failed. Saves on change (throttled), on leave and on server shutdown.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Vantage.SettingsConfig)
local Remotes = ReplicatedStorage.Vantage:WaitForChild("Remotes")
local GetFn = Remotes:WaitForChild("SettingsGet") :: RemoteFunction
local SaveEv = Remotes:WaitForChild("SettingsSave") :: RemoteEvent
local SavedEv = Remotes:WaitForChild("SettingsSaved") :: RemoteEvent

local MIN_SAVE_INTERVAL = 6
local RETRIES = 3

local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore("VantageSettings_v1")
end)
if not storeOk then
	warn("[VANTAGE] Settings DataStore unavailable (" .. tostring(store) .. "); settings will not persist this session")
	store = nil
end

local cache: { [Player]: any } = {}

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function withRetries(fn)
	local lastErr
	for i = 1, RETRIES do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		task.wait(0.5 * i)
	end
	return false, lastErr
end

local function load(player: Player)
	local rec = { Values = SettingsConfig.Defaults(), Status = "Default", Loaded = false, Dirty = false, LastSave = 0 }
	cache[player] = rec
	if store then
		local ok, data = withRetries(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			if type(data) == "table" then
				rec.Values = SettingsConfig.Sanitize(data)
				rec.Status = "Loaded"
			end
		else
			rec.Status = "Failed"
			warn("[VANTAGE] Settings load failed for", player.Name, data)
		end
	else
		rec.Status = "Failed"
	end
	rec.Loaded = true
end

local function save(player: Player): boolean
	local rec = cache[player]
	if not rec or not rec.Dirty then
		return true
	end
	if not store then
		return false
	end
	local values = rec.Values
	rec.Dirty = false
	rec.LastSave = os.clock()
	local ok, err = withRetries(function()
		store:SetAsync(key(player), values, { player.UserId })
	end)
	if not ok then
		rec.Dirty = true
		warn("[VANTAGE] Settings save failed for", player.Name, err)
	end
	return ok
end

GetFn.OnServerInvoke = function(player: Player)
	local t0 = os.clock()
	while (not cache[player] or not cache[player].Loaded) and os.clock() - t0 < 8 do
		task.wait(0.1)
	end
	local rec = cache[player]
	if not rec then
		return SettingsConfig.Defaults(), "Failed"
	end
	return rec.Values, rec.Status
end

SaveEv.OnServerEvent:Connect(function(player: Player, values: any)
	local rec = cache[player]
	if not rec or type(values) ~= "table" then
		return
	end
	rec.Values = SettingsConfig.Sanitize(values)
	rec.Dirty = true
	if rec.Pending then
		return -- a save is already scheduled; it will write the newest values
	end
	rec.Pending = true
	local wait = math.max(0, MIN_SAVE_INTERVAL - (os.clock() - rec.LastSave))
	task.delay(wait, function()
		rec.Pending = false
		if cache[player] ~= rec then
			return
		end
		local ok = save(player)
		if player.Parent then
			SavedEv:FireClient(player, ok)
		end
	end)
end)

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(player)
	save(player)
	cache[player] = nil
end)
game:BindToClose(function()
	local threads = 0
	for player in cache do
		threads += 1
		task.spawn(function()
			save(player)
			threads -= 1
		end)
	end
	local t0 = os.clock()
	while threads > 0 and os.clock() - t0 < 20 do
		task.wait(0.2)
	end
end)
