--[[ Spawn shields: lime force-field walls around each team's spawn room on Live Fire.
	Own team walks through; the enemy team is blocked. Bullets and grapples pass (CanQuery off).
	Works with collision groups: each character is put in VS_Team<Red|Blue>; shield parts tagged
	"SpawnShield" (attribute Team) go in VS_Shield<Team>. Parts already in another non-default group
	(for example vehicle occupants set by VehicleService) are left alone. ]]
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")
local TEAMS = { "Red", "Blue" }
local function reg(g) if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end end
for _, t in TEAMS do reg("VS_Team" .. t) reg("VS_Shield" .. t) end
for _, t in TEAMS do
	local shield = "VS_Shield" .. t
	PhysicsService:CollisionGroupSetCollidable(shield, "Default", false)
	for _, u in TEAMS do
		PhysicsService:CollisionGroupSetCollidable(shield, "VS_Team" .. u, u ~= t)
		PhysicsService:CollisionGroupSetCollidable(shield, "VS_Shield" .. u, false)
	end
end
local function setupShield(p)
	if p:IsA("BasePart") then
		local team = p:GetAttribute("Team")
		if team then p.CollisionGroup = "VS_Shield" .. team end
	end
end
for _, p in CollectionService:GetTagged("SpawnShield") do setupShield(p) end
CollectionService:GetInstanceAddedSignal("SpawnShield"):Connect(setupShield)

local function groupFor(player)
	local team = player.Team
	if team and (team.Name == "Red" or team.Name == "Blue") then return "VS_Team" .. team.Name end
	return "Default"
end
local function isOurs(g) return g == "Default" or g == "VS_TeamRed" or g == "VS_TeamBlue" end
local function apply(player, inst)
	if inst:IsA("BasePart") and isOurs(inst.CollisionGroup) then inst.CollisionGroup = groupFor(player) end
end
local function onCharacter(player, character)
	for _, d in character:GetDescendants() do apply(player, d) end
	character.DescendantAdded:Connect(function(d) apply(player, d) end)
end
local function onPlayer(player)
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
	if player.Character then onCharacter(player, player.Character) end
	player:GetPropertyChangedSignal("Team"):Connect(function()
		if player.Character then for _, d in player.Character:GetDescendants() do apply(player, d) end end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end
