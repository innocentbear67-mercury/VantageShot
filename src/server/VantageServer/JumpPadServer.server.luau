-- players standing on a jump pad get a movement-validator grace so the launch is not rubber-banded
-- Proximity poll (10 Hz), not Touched: most JumpPad parts in the place have CanTouch = false, so
-- Touched never fires on them (integration review 2026-11-21). TagCache keeps the pad list
-- allocation-free, and the loop idles when no pad exists (between maps / in the lobby).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TagCache = require(ReplicatedStorage.Vantage.TagCache)
local exempt = script.Parent:WaitForChild("ExemptMovement")

local pads = TagCache.get("JumpPad")

while true do
	task.wait(0.1)
	if #pads > 0 then
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local pos = root.Position
				for _, pad in pads do
					if pad:IsA("BasePart") then
						local rel = pad.CFrame:PointToObjectSpace(pos)
						if math.abs(rel.X) <= pad.Size.X / 2 + 2 and math.abs(rel.Z) <= pad.Size.Z / 2 + 2 and rel.Y > -1 and rel.Y < 8 then
							exempt:Fire(player, 3)
							break
						end
					end
				end
			end
		end
	end
end
