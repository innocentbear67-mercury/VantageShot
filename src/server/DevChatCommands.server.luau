-- DevChatCommands: owner-only chat commands for granting REQ / ORD.
--   /devgrant              +100,000 REQ and +500 ORD to everyone in the server
--   /req <amount> [all|me|name]
--   /ord <amount> [all|me|name]
-- Only the game owner (or anyone in a Studio playtest) can use these.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local VS = game:GetService("ServerScriptService"):WaitForChild("VantageServer")
local Req = require(VS:WaitForChild("Requisition"))
local Ord = require(VS:WaitForChild("Ordnance"))

local ADMINS = { [11707170334] = true } -- add more UserIds here if needed

local function isAdmin(id)
	return ADMINS[id] == true or id == game.CreatorId or RunService:IsStudio()
end

local function findTargets(caller, who)
	who = (who == nil or who == "") and "all" or who:lower()
	if who == "all" then return Players:GetPlayers() end
	if who == "me" then return { caller } end
	for _, p in Players:GetPlayers() do
		if p.Name:lower():sub(1, #who) == who or p.DisplayName:lower():sub(1, #who) == who then
			return { p }
		end
	end
	return {}
end

local GIVE = {
	-- Kind = "Purchase" skips REQ boosts and keeps it out of match earnings
	REQ = function(p, n) return pcall(Req.Award, p, { { Label = "DEV GRANT", Amount = n, Kind = "Purchase" } }) end,
	ORD = function(p, n) return pcall(Ord.Award, p, n, "DEV GRANT") end,
}

local function give(currency, caller, amount, who)
	for _, p in findTargets(caller, who) do
		local ok, err = GIVE[currency](p, amount)
		if ok then
			print(("[DevCmd] +%d %s -> %s"):format(amount, currency, p.Name))
		else
			warn(("[DevCmd] %s for %s failed: %s"):format(currency, p.Name, tostring(err)))
		end
	end
end

local function addCommand(alias, handler)
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "Dev_" .. alias:sub(2)
	cmd.PrimaryAlias = alias
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(src, text)
		local caller = Players:GetPlayerByUserId(src.UserId)
		if caller and isAdmin(caller.UserId) then handler(caller, text) end
	end)
end

local function parse(text)
	local amt, who = text:match("^%S+%s+(%d+)%s*(%S*)")
	return tonumber(amt), who
end

addCommand("/req", function(caller, text)
	local amt, who = parse(text)
	if amt then give("REQ", caller, amt, who) end
end)

addCommand("/ord", function(caller, text)
	local amt, who = parse(text)
	if amt then give("ORD", caller, amt, who) end
end)

addCommand("/devgrant", function(caller)
	give("REQ", caller, 100000, "all")
	give("ORD", caller, 500, "all")
end)

-- /allskins: unlocks every gun and every premium skin for the caller ONLY. Owner account only (not other Studio testers).
local OWNER = 11707170334
addCommand("/allskins", function(caller)
	if caller.UserId ~= OWNER then return end
	local fn = VS:WaitForChild("DevGrantAll", 10)
	if not fn then warn("[DevCmd] DevGrantAll hook missing") return end
	local ok, guns, skins = pcall(function() return fn:Invoke(caller) end)
	if ok and guns then
		print(("[DevCmd] /allskins -> %s: +%d guns, +%d skins"):format(caller.Name, guns, skins or 0))
	else
		warn("[DevCmd] /allskins failed:", guns)
	end
end)
