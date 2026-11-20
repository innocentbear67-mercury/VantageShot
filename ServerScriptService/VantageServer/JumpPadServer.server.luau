-- players standing on a jump pad get a movement-validator grace so the launch is not rubber-banded
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local exempt = script.Parent:WaitForChild("ExemptMovement")
while true do
	task.wait(0.1)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			for _, pad in CS:GetTagged("JumpPad") do
				local rel = pad.CFrame:PointToObjectSpace(root.Position)
				if math.abs(rel.X) <= pad.Size.X / 2 + 2 and math.abs(rel.Z) <= pad.Size.Z / 2 + 2 and rel.Y > -1 and rel.Y < 8 then
					exempt:Fire(player, 3)
					break
				end
			end
		end
	end
end