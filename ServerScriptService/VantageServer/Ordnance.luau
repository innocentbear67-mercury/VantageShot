--[[
	VANTAGE - Ordnance service (server), 2026-11-17. ORD = second currency, spent on Arsenal Crates (gun unlocks).
	Same storage pattern as Requisition:
	  - DataStore "VantageOrdnance_v1", key "u_<UserId>" -> { V = 1, ORD = number }, saved as INCREMENTS
	    through UpdateAsync (a failed load can never wipe a balance; two servers can't overwrite each other).
	  - replicated as the player attribute "ORD" (server-set only).
	  - Studio playtests never save. Studio test hook: player attribute DevOrdGrant = <ORD to add>.
	API: Award(p, amount, label?) (fires Remotes.OrdAward to that player), Credit(p, amount) (silent),
	     Spend(p, amount) -> bool, Balance(p), Flush(p).
	Earned through Progression hooks (eliminations, assists, match end, level-ups; rates in OrdnanceConfig).
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage.Vantage.Remotes
local Remote = Remotes:FindFirstChild("OrdAward")
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = "OrdAward"
	Remote.Parent = Remotes
end

local Ordnance = {}
local STORE = "VantageOrdnance_v1"
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local base: { [Player]: number } = {}
local delta: { [Player]: number } = {}
local SAVE = not RunService:IsStudio()

local function key(p: Player): string
	return "u_" .. p.UserId
end

local function publish(p: Player)
	p:SetAttribute("ORD", (base[p] or 0) + (delta[p] or 0))
end

local function load(p: Player)
	local b = 0
	if store then
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync(key(p))
		end)
		if ok and type(res) == "table" and type(res.ORD) == "number" then
			b = math.max(0, math.floor(res.ORD))
		elseif not ok then
			warn("[VANTAGE] Ordnance: load failed (balance shows session earnings only):", res)
		end
	end
	if p.Parent then
		base[p] = b
		delta[p] = delta[p] or 0
		publish(p)
	end
end

local function save(p: Player)
	local d = delta[p]
	if not SAVE or not store or not d or d == 0 then
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			local cur = if type(old) == "table" and type(old.ORD) == "number" then old.ORD else 0
			return { V = 1, ORD = math.max(0, cur + d) }
		end)
	end)
	if ok then
		delta[p] = (delta[p] or 0) - d
		base[p] = (base[p] or 0) + d
	else
		warn("[VANTAGE] Ordnance: save failed (kept for the next try):", err)
	end
end

local function add(p: Player, amount: number): number
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not (p and p.Parent) then
		return 0
	end
	delta[p] = (delta[p] or 0) + amount
	publish(p)
	return amount
end

-- credits ORD and tells that player's client (Remotes.OrdAward: amount, label, balance)
function Ordnance.Award(p: Player, amount: number, label: string?)
	local a = add(p, amount)
	if a > 0 then
		Remote:FireClient(p, a, tostring(label or ""), p:GetAttribute("ORD"))
	end
end

-- credits ORD without telling the client (per-kill trickle; the balance attribute still updates)
function Ordnance.Credit(p: Player, amount: number): boolean
	return add(p, amount) > 0
end

-- false while loading or when the balance is short
function Ordnance.Spend(p: Player, amount: number): boolean
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

function Ordnance.Balance(p: Player): number
	return (base[p] or 0) + (delta[p] or 0)
end

function Ordnance.Flush(p: Player)
	save(p)
end

local function onPlayer(p: Player)
	if p:GetAttribute("ORD") == nil then
		p:SetAttribute("ORD", 0)
	end
	load(p)
	if RunService:IsStudio() then
		p:GetAttributeChangedSignal("DevOrdGrant"):Connect(function()
			local n = tonumber(p:GetAttribute("DevOrdGrant"))
			if n and n > 0 then
				Ordnance.Award(p, n, "DEV GRANT")
			end
		end)
	end
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

return Ordnance
