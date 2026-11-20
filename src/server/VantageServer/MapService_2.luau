--[[
	VANTAGE — MapService (server, 2026-11-18)
	Map rotation loader for the map vote (MatchConfig.Maps / MapVote, driven by MatchService).

	* Exactly one map is in Workspace, always named MatchConfig.Map.Folder ("Map_LiveFire"), the
	  name every system reads (spawns, bots, kill volumes). Its id is the attribute MapId.
	* Every other map waits in ServerStorage.VantageMaps under its Store name. Load(id) moves
	  the current map back there and the chosen one in (moved, not cloned: one copy of each).
	* Maps keep their built position (Foundry Row sits at x 2400), nothing is pivoted.
	* The SpawnLocations of the loaded map are enabled; a map without a Systems folder gets a
	  copy of Live Fire's (kill volumes, gravity lifts, ambient motion).
	* Publishes on Vantage.Match: MapId, MapName, MapLighting (clients apply the preset when they
	  leave the lobby, see StarterPlayerScripts.LobbyLighting).
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("MatchConfig"))

local MapService = {}

local store = ServerStorage:FindFirstChild("VantageMaps")
if not store then
	store = Instance.new("Folder")
	store.Name = "VantageMaps"
	store.Parent = ServerStorage
end

local M: Instance? = nil
local current: string? = nil
local systemsTemplate: Instance? = nil

local function active(): Instance?
	return Workspace:FindFirstChild(Config.Map.Folder)
end

local function publish()
	local def = Config.MapById(current)
	if M then
		M:SetAttribute("MapId", current or "")
		M:SetAttribute("MapName", def and def.Name or Config.Map.Name)
		M:SetAttribute("MapLighting", def and def.Lighting or "")
	end
end

-- the map in Workspace when the server starts is the default map
do
	local map = active()
	if map then
		current = map:GetAttribute("MapId") or Config.DefaultMap
		map:SetAttribute("MapId", current)
		local sys = map:FindFirstChild("Systems")
		if sys then
			systemsTemplate = sys:Clone()
		end
	end
end

function MapService.Attach(matchFolder: Instance)
	M = matchFolder
	publish()
end

function MapService.Current(): string?
	return current
end

function MapService.CurrentName(): string
	local def = Config.MapById(current)
	return def and def.Name or Config.Map.Name
end

-- a map can be voted for if it is enabled and its model exists (in Workspace or in the store)
function MapService.Available(id: string): boolean
	local def = Config.MapById(id)
	if not def or def.Enabled == false then
		return false
	end
	return id == current or store:FindFirstChild(def.Store) ~= nil
end

-- up to n random maps from the mode's pool
function MapService.Candidates(modeId: string, n: number): { string }
	local mode = Config.Modes[modeId]
	local pool = {}
	if mode and mode.Maps then
		for _, id in mode.Maps do
			if MapService.Available(id) then
				table.insert(pool, id)
			end
		end
	else
		for _, def in Config.Maps do
			if MapService.Available(def.Id) then
				table.insert(pool, def.Id)
			end
		end
	end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(n, #pool) do
		out[i] = pool[i]
	end
	-- card order follows MatchConfig.Maps, so the same map is always in the same place
	table.sort(out, function(a, b)
		local ia, ib = 0, 0
		for k, def in Config.Maps do
			if def.Id == a then ia = k end
			if def.Id == b then ib = k end
		end
		return ia < ib
	end)
	if #out == 0 and current then
		out[1] = current
	end
	return out
end

-- most votes wins; ties (and no votes at all) are a random pick among the leaders
function MapService.Tally(choices: { string }, byPlayer: { [Player]: string }): string
	local counts = {}
	for _, id in choices do
		counts[id] = 0
	end
	for p, id in byPlayer do
		if p.Parent and counts[id] then
			counts[id] += 1
		end
	end
	local best, leaders = -1, {}
	for _, id in choices do
		if counts[id] > best then
			best, leaders = counts[id], { id }
		elseif counts[id] == best then
			table.insert(leaders, id)
		end
	end
	return leaders[math.random(1, #leaders)] or choices[1]
end

-- put the map with this id in Workspace (no-op when it already is). Returns true when it is in.
function MapService.Load(id: string?): boolean
	if not id or id == current then
		return id ~= nil
	end
	local def = Config.MapById(id)
	if not def then
		warn("[MapService] unknown map " .. tostring(id))
		return false
	end
	local nextMap = store:FindFirstChild(def.Store)
	if not nextMap then
		warn("[MapService] ServerStorage.VantageMaps." .. def.Store .. " is missing")
		return false
	end
	local t0 = os.clock()
	-- the old map back to the store under its own name
	local old = active()
	if old then
		local oldDef = Config.MapById(old:GetAttribute("MapId") or current)
		old.Name = if oldDef then oldDef.Store else ("Map_" .. tostring(current))
		old.Parent = store
	end
	-- the new map in, with live spawns and the shared map scripts
	nextMap:SetAttribute("MapId", id)
	for _, d in nextMap:GetDescendants() do
		if d:IsA("SpawnLocation") then
			d.Enabled = true
		end
	end
	if not nextMap:FindFirstChild("Systems") and systemsTemplate then
		systemsTemplate:Clone().Parent = nextMap
	end
	nextMap.Name = Config.Map.Folder
	nextMap.Parent = Workspace
	current = id
	publish()
	print(string.format("[MapService] loaded %s in %.2f s", def.Name, os.clock() - t0))
	return true
end

return MapService
