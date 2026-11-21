-- players standing on a jump pad get a movement-validator grace so the launch is not rubber-banded
-- proximity poll, NOT Touched: most pads in the place have CanTouch off, so touch events never fire;
-- the TagCache swap only removes the per-tick GetTagged allocation (same box test, same 10 Hz)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TagCache = require(ReplicatedStorage.Vantage.TagCache)
local exempt = script.Parent:WaitForChild("ExemptMovement")

while true do
	task.wait(0.1)
	local pads = TagCache.get("JumpPad")
	if #pads > 0 then
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				for _, pad in pads do
					local rel = pad.CFrame:PointToObjectSpace(root.Position)
					if math.abs(rel.X) <= pad.Size.X / 2 + 2 and math.abs(rel.Z) <= pad.Size.Z / 2 + 2 and rel.Y > -1 and rel.Y < 8 then
						exempt:Fire(player, 3)
						break
					end
				end
			end
		end
	end
end
