--[=[
	VANTAGE — StudioBotTagger (Studio only)
	Any NPC with a Humanoid dropped into Workspace (a Rig Builder dummy, a test bot) is tagged as a
	training target, so weapons, vehicle guns and the drone's homing treat it as an enemy.
	Does nothing in live servers.
]=]
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
if not RunService:IsStudio() then
	return
end
local TAG = "VantageDummy"
local function consider(h: Instance)
	if not h:IsA("Humanoid") then
		return
	end
	local m = h.Parent
	if m and m:IsA("Model") and not Players:GetPlayerFromCharacter(m) and not CollectionService:HasTag(m, TAG) then
		task.defer(function()
			if m.Parent and not Players:GetPlayerFromCharacter(m) then
				CollectionService:AddTag(m, TAG)
			end
		end)
	end
end
for _, d in workspace:GetDescendants() do
	consider(d)
end
workspace.DescendantAdded:Connect(consider)
