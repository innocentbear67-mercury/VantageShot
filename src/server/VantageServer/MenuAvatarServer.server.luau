--[[
	VANTAGE — MenuAvatarServer
	Builds each joining player's own avatar for the main-menu showcase (avatar models can only
	be created on the server) and hands it to that player alone: the model is parented into
	their PlayerGui, which replicates to nobody else. Always R15 (the showcase poses the rifle
	with the R15 arm rig). Player attribute "MenuAvatar" tells the client what happened:
		"Ready"   their real avatar
		"Default" their avatar couldn't be fetched (e.g. Studio test players): a default one
		"Failed"  nothing could be built; the client falls back to the stock menu character
]]

local Players = game:GetService("Players")

local function stripScripts(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- would run inside PlayerGui otherwise
		end
	end
end

local function build(player: Player)
	local status = "Ready"
	local ok, model = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		status = "Default"
		ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
	end
	local playerGui = player:WaitForChild("PlayerGui", 20)
	if not (ok and model and playerGui and player.Parent) then
		if model then
			model:Destroy()
		end
		player:SetAttribute("MenuAvatar", "Failed")
		return
	end
	stripScripts(model)
	model.Name = "VantageMenuAvatar"
	model.Parent = playerGui
	player:SetAttribute("MenuAvatar", status)
end

Players.PlayerAdded:Connect(build)
for _, p in Players:GetPlayers() do
	task.spawn(build, p)
end
