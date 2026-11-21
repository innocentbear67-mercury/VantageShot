--[[
	VANTAGE — TeamSpawnServer
	Players join with no team and no character (Players.CharacterAutoLoads = false).
	Teams are now assigned by MatchService (matchmaking), which also does the first spawn of
	each match. ChooseTeam("Join") is refused while MATCHMAKING is on; GetCounts still works
	(the main menu's live panel uses it). Characters spawn at the team's SpawnLocations
	(Map_LiveFire BlueSpawn / RedSpawn, matched by TeamColor).
	Backup of the pick-your-team version: ServerStorage._MatchBackup_20261110.TeamSpawnServer
	After dying, players respawn on their team after Players.RespawnTime, held a little longer
	while their death replay plays (EliminationService, capped server-side).
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local chooseTeam = ReplicatedStorage.Vantage:WaitForChild("Remotes"):WaitForChild("ChooseTeam") :: RemoteFunction
local EliminationService = require(script.Parent.WeaponServer.EliminationService)

local TEAM_NAMES = { Blue = true, Red = true }
local MATCHMAKING = true -- teams come from MatchService, not from the client

local function teamCounts()
	local counts = {}
	for name in TEAM_NAMES do
		local team = Teams:FindFirstChild(name) :: Team?
		counts[name] = team and #team:GetPlayers() or 0
	end
	return counts
end

local function spawnPlayer(player: Player)
	if player.Parent and player.Team then
		player:LoadCharacterAsync()
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	player:SetAttribute("RespawnAt", nil)
	humanoid.Died:Once(function()
		-- 2026-11-18: the earliest redeploy time (server clock) for the client's respawn countdown;
		-- the death replay can hold it a little longer (capped by EliminationService)
		player:SetAttribute("RespawnAt", workspace:GetServerTimeNow() + Players.RespawnTime)
		task.wait(Players.RespawnTime)
		EliminationService.WaitForReplay(player, character)
		-- only respawn if this is still their current (dead) character, and never into the
		-- results sequence (the match is over; MatchService sends everyone back to the lobby)
		local M = ReplicatedStorage.Vantage:FindFirstChild("Match")
		if player.Character == character and not (M and M:GetAttribute("Phase") == "Ended") then
			spawnPlayer(player)
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.Neutral = true
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
end)

chooseTeam.OnServerInvoke = function(player: Player, action: any, teamName: any)
	if action == "GetCounts" then
		return true, teamCounts()
	end
	if MATCHMAKING then
		return false, "Teams are assigned by matchmaking"
	end
	if action ~= "Join" or type(teamName) ~= "string" or not TEAM_NAMES[teamName] then
		return false, "Invalid team"
	end
	if player.Team ~= nil then
		return false, "Already on a team" -- menu is a one-time choice per session
	end
	local team = Teams:FindFirstChild(teamName) :: Team?
	if not team then
		return false, "Team missing"
	end
	player.Neutral = false
	player.Team = team
	spawnPlayer(player)
	return true, teamName
end
