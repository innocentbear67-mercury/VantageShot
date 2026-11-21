--[[
	VANTAGE — RemotesLib (shared): the one remote factory + the one rate limiter.
	get(name, class?, parent?) finds or creates a remote inside ReplicatedStorage.Vantage.Remotes —
	the game's remote folder, which this module creates if a fresh build lacks it (the module is a
	LIBRARY and must never sit on the folder's own path). RemoteEvent by default, RemoteFunction
	when class == "RemoteFunction"; on the client it waits for the server's instance instead of
	creating. rate(player, key, window) is the shared per-player-per-key throttle (true = allowed;
	the time is recorded only when it is).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local Vantage = ReplicatedStorage:WaitForChild("Vantage")

local RemotesLib = {}

local function container(): Instance
	if IS_SERVER then
		local f = Vantage:FindFirstChild("Remotes")
		if not f then
			f = Instance.new("Folder")
			f.Name = "Remotes"
			f.Parent = Vantage
		end
		return f
	end
	return Vantage:WaitForChild("Remotes")
end

function RemotesLib.get(name: string, class: string?, parent: Instance?): Instance
	local holder = if parent then parent else container()
	if not IS_SERVER then
		return holder:WaitForChild(name)
	end
	local r = holder:FindFirstChild(name)
	if not r then
		r = Instance.new(if class == "RemoteFunction" then "RemoteFunction" else "RemoteEvent")
		r.Name = name
		r.Parent = holder
	end
	return r :: Instance
end

local store: { [Player]: { [string]: number } } = {}

function RemotesLib.rate(player: Player, key: string, window: number): boolean
	local now = os.clock()
	local t = store[player]
	if not t then
		t = {}
		store[player] = t
	end
	if now - (t[key] or 0) < window then
		return false
	end
	t[key] = now
	return true
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		store[player] = nil
	end)
end

return RemotesLib
