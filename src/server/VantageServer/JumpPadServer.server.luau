-- players standing on a jump pad get a movement-validator grace so the launch is not rubber-banded
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TagCache = require(ReplicatedStorage.Vantage.TagCache)
local exempt = script.Parent:WaitForChild("ExemptMovement")

-- C4: pad Touched events replace the old 10Hz proximity poll (zero wake-ups with no one
-- near); the 1 s re-fire cap keeps the 3 s grace continuous during sustained contact
local recent: { [Player]: number } = {}
local wired: { [Instance]: boolean } = {}

local function wire(pad: Instance)
	if wired[pad] or not pad:IsA("BasePart") then
		return
	end
	wired[pad] = true
	local part = pad :: BasePart
	part.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		local player = model and Players:GetPlayerFromCharacter(model)
		if player and (recent[player] or 0) < os.clock() then
			recent[player] = os.clock() + 1
			exempt:Fire(player, 3)
		end
	end)
end

for _, pad in TagCache.get("JumpPad") do
	wire(pad)
end
CS:GetInstanceAddedSignal("JumpPad"):Connect(wire)
Players.PlayerRemoving:Connect(function(p)
	recent[p] = nil
end)
