-- ECLIPSE map server: kill volumes, and movement-validator exemptions for gravity lifts.
local Players = game:GetService("Players")
local map = script.Parent.Parent
local g = map:WaitForChild("Gameplay")
local vs = game:GetService("ServerScriptService"):FindFirstChild("VantageServer")
local exempt = vs and vs:WaitForChild("ExemptMovement", 10)
local function fromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return model, hum, model and Players:GetPlayerFromCharacter(model)
end
for _, kv in g:WaitForChild("KillVolumes"):GetChildren() do
	kv.Touched:Connect(function(hit)
		local model, hum = fromHit(hit)
		if hum and hum.Health > 0 then
			if model then
				model:SetAttribute("DeathCause", "Void") -- kill feed: fell out of the map
			end
			hum.Health = 0
		end
	end)
end
local recent = {}
for _, lift in g:WaitForChild("Lifts"):GetChildren() do
	lift.Touched:Connect(function(hit)
		local _, hum, plr = fromHit(hit)
		if plr and hum and hum.Health > 0 and (recent[plr] or 0) < os.clock() then
			recent[plr] = os.clock() + 1
			if exempt then
				exempt:Fire(plr, 3.5) -- the launch exceeds normal jump height
			end
		end
	end)
end
Players.PlayerRemoving:Connect(function(p) recent[p] = nil end)
