--[[
	ShopService - Robux purchases for the VantageShot Shop (2026-11-16).
	- Developer products: MarketplaceService.ProcessReceipt grants crates (CrateGrant hook in CrateService) and REQ
	  (Requisition.Award, Kind "Purchase", so pass boosts don't apply). Receipts are recorded per player in
	  DataStore "VantageShop_v1" so a retried receipt is never granted twice. One-time deals are tracked there too.
	- Gamepasses: VIP (+25% match REQ, chat tag, 2 Apex crates once) and Double REQ (+100%). Ownership is checked on join
	  and on PromptGamePassPurchaseFinished; perks are the player attributes Pass_<key>, ReqBoost, VIP.
	- Remotes.ShopNotify(payload) tells the buyer what they got.
	- Studio test hook: player attribute DevShopGrant = "<product or pass key>" simulates a purchase (Studio only).
]]
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Shop = require(Vantage:WaitForChild("Shop"):WaitForChild("ShopConfig"))
local Requisition = require(script.Parent:WaitForChild("Requisition"))
local Ordnance = require(script.Parent:WaitForChild("Ordnance")) -- 2026-11-17: ORD packs
local CrateGrant = script.Parent:WaitForChild("CrateGrant", 60)

local remotes = require(Vantage:WaitForChild("RemotesLib"))
local Notify = remotes.get("ShopNotify") :: RemoteEvent

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("VantageShop_v1")
end)

local data: { [Player]: any } = {}
local seen: { [string]: boolean } = {} -- receipts granted by this server

local function key(p: Player): string
	return "u_" .. p.UserId
end

local function publish(p: Player)
	local d = data[p]
	if not d then return end
	for k in d.OneTime do
		p:SetAttribute("ShopBought_" .. k, true)
	end
	local boost, vip = 0, false
	for _, pass in Shop.Passes do
		if p:GetAttribute("Pass_" .. pass.Key) then
			boost += pass.Boost or 0
			if pass.Key == "vip" then vip = true end
		end
	end
	p:SetAttribute("ReqBoost", boost)
	p:SetAttribute("VIP", vip)
end

local function save(p: Player): boolean
	local d = data[p]
	if not (d and store) then return true end
	local rec, one, gifts = table.clone(d.Receipts), table.clone(d.OneTime), table.clone(d.Gifts)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			old = if type(old) == "table" then old else {}
			local R = old.Receipts or {}
			for k, v in rec do R[k] = v end
			local list = {}
			for k, v in R do table.insert(list, { k, v }) end
			if #list > 300 then
				table.sort(list, function(a, b) return a[2] > b[2] end)
				R = {}
				for i = 1, 200 do R[list[i][1]] = list[i][2] end
			end
			local O = old.OneTime or {}
			for k in one do O[k] = true end
			local G = old.Gifts or {}
			for k in gifts do G[k] = true end
			return { V = 1, Receipts = R, OneTime = O, Gifts = G }
		end)
	end)
	if not ok then warn("[VANTAGE] Shop: save failed:", err) end
	return ok
end

-- crates are granted atomically through CrateService; REQ goes through Requisition (toast + immediate save)
-- players Roblox restricts from paid random items never receive crates from Robux: they get the crates' REQ value instead
local PolicyService = game:GetService("PolicyService")
local CrateConfig = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local restrictedCache: { [Player]: boolean } = {}
local function restricted(p: Player): boolean
	if restrictedCache[p] == nil then
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, p)
		restrictedCache[p] = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == true or false
	end
	return restrictedCache[p]
end

-- crates/skins are granted atomically through CrateService; REQ goes through Requisition (toast + immediate save)
local function grant(p: Player, g, label: string, dupeReq: number?): (boolean, string?)
	local crates, req = g.Crates or {}, g.Req or 0
	if next(crates) and restricted(p) then
		for id, n in crates do
			req += (CrateConfig.ById[id] and CrateConfig.ById[id].Price or 0) * n
		end
		crates = {}
	end
	local extra
	if next(crates) or (g.Skins and #g.Skins > 0) then
		if not CrateGrant then return false end
		local ok, res, dupes = pcall(function() return CrateGrant:Invoke(p, crates, g.Skins) end)
		if not (ok and res) then return false end
		if type(dupes) == "table" and #dupes > 0 and dupeReq then
			req += dupeReq * #dupes
			extra = "Skin already owned: +" .. tostring(dupeReq * #dupes) .. " REQ instead"
		end
	end
	if g.Pass then -- Season Pass premium / tier skips (SeasonPassService)
		local PG = script.Parent:FindFirstChild("PassGrant")
		if not PG then return false end
		local okP, resP = pcall(function() return PG:Invoke(p, g.Pass) end)
		if not (okP and resP) then return false end
	end
	if (tonumber(g.Ichor) or 0) > 0 then -- 2026-11-20: Ichor packs (SignatureService; nil = data not loaded -> retry the receipt)
		local api = game:GetService("ServerStorage"):FindFirstChild("SignatureAPI")
		if not api then return false end
		local okI, resI = pcall(function() return api:Invoke("AddIchor", p, math.floor(g.Ichor), "Purchase") end)
		if not (okI and resI) then return false end
	end
	if req > 0 then
		Requisition.Award(p, { { Label = label, Amount = req, Kind = "Purchase" } })
		task.spawn(function() pcall(Requisition.Flush, p) end)
	end
	if (tonumber(g.Ord) or 0) > 0 then
		Ordnance.Award(p, g.Ord, label)
		task.spawn(function() pcall(Ordnance.Flush, p) end)
	end
	return true, extra
end

local function applyPass(p: Player, pass, fresh: boolean?)
	p:SetAttribute("Pass_" .. pass.Key, true)
	publish(p)
	local d = data[p]
	if pass.Gift and d and not d.Gifts[pass.Key] then
		task.spawn(function()
			for _ = 1, 12 do
				if not p.Parent then return end
				if grant(p, pass.Gift, pass.Name) then
					d.Gifts[pass.Key] = true
					save(p)
					return
				end
				task.wait(5)
			end
		end)
	end
	if fresh then
		Notify:FireClient(p, { Title = pass.Name .. " unlocked!", Text = table.concat(pass.Lines or {}, " · ") })
	end
end

local function grantProduct(p: Player, prod, purchaseId: string?): boolean
	local d = data[p]
	if not d then return false end
	local ok, extra = grant(p, prod.Grant, prod.Name, prod.DupeReq)
	if not ok then return false end
	if purchaseId then
		seen[purchaseId] = true
		d.Receipts[purchaseId] = os.time()
	end
	if prod.OneTime then d.OneTime[prod.Key] = true end
	publish(p)
	Notify:FireClient(p, { Title = prod.Name .. (if prod.Count and prod.Count > 1 then " x" .. prod.Count else ""), Text = extra or Shop.Summary(prod.Grant) })
	task.spawn(save, p)
	return true
end

MarketplaceService.ProcessReceipt = function(info)
	local prod = Shop.ByProductId[info.ProductId]
	local p = Players:GetPlayerByUserId(info.PlayerId)
	if not prod then
		warn("[VANTAGE] Shop: unknown product", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not (p and data[p]) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(info.PurchaseId)
	if seen[id] or data[p].Receipts[id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not grantProduct(p, prod, id) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, passId, bought)
	local pass = Shop.ByPassId[passId]
	if bought and pass then
		applyPass(p, pass, true)
	end
end)

local function load(p: Player)
	local d = { Receipts = {}, OneTime = {}, Gifts = {} }
	if store then
		local ok, res = pcall(function() return (store :: DataStore):GetAsync(key(p)) end)
		if ok and type(res) == "table" then
			d.Receipts, d.OneTime, d.Gifts = res.Receipts or {}, res.OneTime or {}, res.Gifts or {}
		elseif not ok then
			warn("[VANTAGE] Shop: load failed:", res)
		end
	end
	data[p] = d
	publish(p)
	for _, pass in Shop.Passes do
		if pass.PassId and pass.PassId > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, pass.PassId)
			if ok and owns then applyPass(p, pass, false) end
		end
	end
	if RunService:IsStudio() then
		p:GetAttributeChangedSignal("DevShopGrant"):Connect(function()
			local k = p:GetAttribute("DevShopGrant")
			if type(k) ~= "string" then return end
			local item = Shop.ByKey[k]
			if not item then return end
			if item.Grant then grantProduct(p, item, nil) else applyPass(p, item, true) end
		end)
	end
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p] = nil
	restrictedCache[p] = nil
end)
