-- gold [VIP] prefix for players with the VIP pass (ShopService sets the VIP attribute)
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
TextChatService.OnIncomingMessage = function(msg)
	local props = Instance.new("TextChatMessageProperties")
	local src = msg.TextSource
	local pl = src and Players:GetPlayerByUserId(src.UserId)
	if pl and pl:GetAttribute("VIP") then
		props.PrefixText = '<font color="#FFD24A">[VIP]</font> ' .. msg.PrefixText
	end
	return props
end
