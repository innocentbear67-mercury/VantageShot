--[[
	VANTAGE — Requisition service (server). REQ = the main earned currency.
	  • DataStore "VantageRequisition_v1", key "u_<UserId>" -> { V = 1, REQ = number }
	    Saved as INCREMENTS through UpdateAsync, so a failed load can never wipe a balance and
	    two servers can't overwrite each other.
	  • replicated as the player attribute "REQ" (server-set only)
	  • Requisition.Award(player, entries) credits { Label, Amount, Kind } entries and sends them
	    to that player's tick feed (Remotes.ReqAward -> VantageReqFeed). Only the server awards.
	Awards come from EliminationService.OnDeath (elimination / headshot / melee / assists).
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remote = ReplicatedStorage.Vantage.Remotes:WaitForChild("ReqAward") :: RemoteEvent

local Requisition = {}
local Ledger = require(script.Parent:WaitForChild("MatchLedger")) -- per-match earnings (results screen)
local STORE = "VantageRequisition_v1"
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local base: { [Player]: number } = {} -- balance loaded from the store
local delta: { [Player]: number } = {} -- earned this session, not yet saved

local function key(p: Player): string
	return "u_" .. p.UserId
end

local function publish(p: Player)
	p:SetAttribute("REQ", (base[p] or 0) + (delta[p] or 0))
end

local function load(p: Player)
	local b = 0
	if store then
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync(key(p))
		end)
		if ok and type(res) == "table" and type(res.REQ) == "number" then
			b = math.max(0, math.floor(res.REQ))
		elseif not ok then
			warn("[VANTAGE] Requisition: load failed (balance shows session earnings only):", res)
		end
	end
	if p.Parent then
		base[p] = b
		delta[p] = delta[p] or 0
		publish(p)
	end
end

-- Studio playtests never write REQ (test awards must not reach real balances)
local SAVE = not RunService:IsStudio()

local function save(p: Player)
	local d = delta[p]
	if not SAVE or not store or not d or d == 0 then
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			local cur = if type(old) == "table" and type(old.REQ) == "number" then old.REQ else 0
			return { V = 1, REQ = math.max(0, cur + d) }
		end)
	end)
	if ok then
		delta[p] = (delta[p] or 0) - d
		base[p] = (base[p] or 0) + d
	else
		warn("[VANTAGE] Requisition: save failed (kept for the next try):", err)
	end
end

-- entries: { { Label = string, Amount = number, Kind = string } }
-- extra (optional, 2026-11-18): { ORD = n, XP = n } granted for the same event by Progression,
-- forwarded to the feed so one elimination shows REQ + ORD + XP together
function Requisition.Award(p: Player, entries, extra)
	if not (p and p.Parent and type(entries) == "table" and #entries > 0) then
		return
	end
	local total = 0
	local earned = 0
	local clean = {}
	local boost = 1 + (tonumber(p:GetAttribute("ReqBoost")) or 0) -- VIP / Double REQ passes (ShopService)
		+ (tonumber(p:GetAttribute("MasteryBoostREQ")) or 0) / 100 -- weapon mastery boosts (MasteryConfig.Boosts)
	for _, e in entries do
		local a = math.floor(tonumber(e.Amount) or 0)
		if boost ~= 1 and tostring(e.Kind or "") ~= "Purchase" then
			a = math.floor(a * boost + 0.5)
		end
		if a > 0 then
			total += a
			if tostring(e.Kind or "") ~= "Purchase" then
				earned += a
			end
			table.insert(clean, { Label = tostring(e.Label or ""), Amount = a, Kind = tostring(e.Kind or "") })
		end
	end
	if total <= 0 then
		return
	end
	delta[p] = (delta[p] or 0) + total
	publish(p)
	Ledger.Add(p, "REQ", earned)
	local ex = nil
	if type(extra) == "table" then
		ex = { ORD = math.max(0, math.floor(tonumber(extra.ORD) or 0)), XP = math.max(0, math.floor(tonumber(extra.XP) or 0)) }
	end
	Remote:FireClient(p, clean, p:GetAttribute("REQ"), ex)
end

-- spends REQ (server only); false while loading or when the balance is short
function Requisition.Spend(p: Player, amount: number): boolean
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not (p and p.Parent) or base[p] == nil then
		return false
	end
	if (base[p] or 0) + (delta[p] or 0) < amount then
		return false
	end
	delta[p] = (delta[p] or 0) - amount
	publish(p)
	return true
end

-- adds REQ without the ReqAward toast (crate refunds are shown by the opening itself)
function Requisition.Credit(p: Player, amount: number): boolean
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not (p and p.Parent) or base[p] == nil then
		return false
	end
	delta[p] = (delta[p] or 0) + amount
	publish(p)
	return true
end

function Requisition.Balance(p: Player): number
	return (base[p] or 0) + (delta[p] or 0)
end

-- writes pending REQ now (used after Robux purchases)
function Requisition.Flush(p: Player)
	save(p)
end

local function onPlayer(p: Player)
	if p:GetAttribute("REQ") == nil then
		p:SetAttribute("REQ", 0)
	end
	load(p)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	base[p], delta[p] = nil, nil
end)
task.spawn(function()
	while true do
		task.wait(45)
		for p in delta do
			task.spawn(save, p)
		end
	end
end)
game:BindToClose(function()
	if not store or not SAVE then
		return
	end
	local n = 0
	for p in delta do
		n += 1
		task.spawn(function()
			save(p)
			n -= 1
		end)
	end
	local t = os.clock()
	while n > 0 and os.clock() - t < 20 do
		task.wait(0.1)
	end
end)
if RunService:IsStudio() then
	-- Studio test hook: bump the player attribute ReqTest to get a sample award
	local function hook(p: Player)
		p:GetAttributeChangedSignal("ReqTest"):Connect(function()
			Requisition.Award(p, {
				{ Label = "KESTREL-7", Amount = 100, Kind = "Elimination" },
				{ Label = "HEADSHOT", Amount = 50, Kind = "Headshot" },
			})
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Requisition
