--[[
	VANTAGE — LobbyService (server)  ·  2026-11-15
	There is no main menu any more: players spawn walking around Workspace.HyperLobby (the
	Hypershot-style hall built in the map chat) and queue from the lobby HUD or the JOIN pads.

	Lobby = no team. MatchService assigns a team at MATCH FOUND and does LoadCharacter at Deploy;
	its cleanup() at match end clears the team and destroys the character, and this loop puts the
	player back in the hall. Lobby characters get attribute Lobby = true; players get InLobby.
	Spawn points: every BasePart named "LobbySpawn" under Workspace.HyperLobby (falls back to the
	hall's spawn deck). Anyone who drops below the hall (y < HALL_Y - 80) is put back on a spawn.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local exempt = script.Parent:WaitForChild("ExemptMovement", 10) :: BindableEvent?

local FALLBACK = CFrame.new(0, 3015, 155)
local RESPAWN_DELAY = 2

local loading: { [Player]: boolean } = {}
local deadAt: { [Player]: number } = {}

local function spawnPoints(): { BasePart }
	local hall = Workspace:FindFirstChild("HyperLobby")
	local pts = {}
	if hall then
		for _, d in hall:GetDescendants() do
			if d.Name == "LobbySpawn" and d:IsA("BasePart") then
				table.insert(pts, d)
			end
		end
	end
	return pts
end

local function hallY(): number
	local pts = spawnPoints()
	return if #pts > 0 then pts[1].Position.Y else FALLBACK.Position.Y
end

local function lobbyCFrame(): CFrame
	local pts = spawnPoints()
	if #pts == 0 then
		return FALLBACK
	end
	local p = pts[math.random(#pts)]
	local pos = p.Position + Vector3.new(math.random() - 0.5, p.Size.Y / 2 + 3.2, math.random() - 0.5)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)) -- the hall runs toward -Z from the spawns
end

local function inLobby(p: Player): boolean
	-- trainees (TutorialService, attribute InTutorial) live in their training arena, not the hall
	return p.Parent ~= nil and p.Team == nil and p:GetAttribute("MatchStatus") ~= "Match" and not p:GetAttribute("InTutorial")
end

local function place(p: Player, c: Model)
	if exempt then
		exempt:Fire(p, 2)
	end
	c:PivotTo(lobbyCFrame())
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function spawnInLobby(p: Player)
	if loading[p] or not inLobby(p) then
		return
	end
	loading[p] = true
	deadAt[p] = nil
	if exempt then
		exempt:Fire(p, 2)
	end
	local ok, err = pcall(function()
		p:LoadCharacter()
	end)
	if not ok then
		warn("[VANTAGE] Lobby spawn failed for " .. p.Name .. ": " .. tostring(err))
	end
	loading[p] = nil
end

local function onCharacter(p: Player, c: Model)
	if p.Team ~= nil or p:GetAttribute("InTutorial") then
		p:SetAttribute("InLobby", false)
		return
	end
	c:SetAttribute("Lobby", true)
	p:SetAttribute("InLobby", true)
	local root = c:WaitForChild("HumanoidRootPart", 10)
	if root and c.Parent and p.Character == c then
		task.defer(place, p, c)
	end
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(c)
		onCharacter(p, c)
	end)
	p:GetPropertyChangedSignal("Team"):Connect(function()
		if p.Team ~= nil then
			p:SetAttribute("InLobby", false)
		end
	end)
	task.defer(spawnInLobby, p)
end)
for _, p in Players:GetPlayers() do
	task.defer(spawnInLobby, p)
end

Players.PlayerRemoving:Connect(function(p)
	loading[p] = nil
	deadAt[p] = nil
end)

-- one slow loop covers joins, match ends (cleanup destroys the character), deaths and falls
task.spawn(function()
	while true do
		task.wait(0.4)
		local floor = hallY() - 80
		for _, p in Players:GetPlayers() do
			if inLobby(p) then
				local c = p.Character
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not c or not c.Parent or not hum then
					spawnInLobby(p)
				elseif hum.Health <= 0 then
					deadAt[p] = deadAt[p] or os.clock()
					if os.clock() - deadAt[p] >= RESPAWN_DELAY then
						spawnInLobby(p)
					end
				elseif root and root.Position.Y < floor then
					place(p, c)
				end
			else
				deadAt[p] = nil
			end
		end
	end
end)
