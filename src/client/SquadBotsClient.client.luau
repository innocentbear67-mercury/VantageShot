--[[
	VANTAGE — SquadBotsClient (Studio only)
	Shows the server's /squad replies as a system line in chat.
]]
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local remotes = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Remotes")
local remote = remotes:WaitForChild("SquadBotsMsg", 60) :: RemoteEvent?
if not remote then
	return
end
remote.OnClientEvent:Connect(function(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local sys = channels and channels:FindFirstChild("RBXSystem") :: TextChannel?
	if sys then
		sys:DisplaySystemMessage('<font color="#7fd4ff">[SQUAD]</font> ' .. text)
	else
		print("[SQUAD] " .. text)
	end
end)
