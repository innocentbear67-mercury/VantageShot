--[[
	VANTAGE — LoadoutService (server)
	Owns cosmetic skin selections.
	  • DataStore "VantageLoadout_v1", key "u_<UserId>" -> { V = 1, Skins = { [WeaponId] = SkinId } }
	  • replicated as player attributes "Skin_<WeaponId>" (everyone renders everyone's skin)
	  • Remotes.SkinEquip(weaponId, skinId): validated against the Skins catalog + ownership,
	    rate limited, re-skins the weapon the player is holding right now
	Cosmetic only — never touches damage, stats or hit validation.

	Equipment (2026-11-17, replaces armour customisation): same record gains Equip = { Pack = id, Hook = id }
	(EquipmentCatalog). The old Armour table is kept in the record untouched (inert) so no saved data is lost.
	  • replicated as player attributes "Equip_Pack" / "Equip_Hook"
	  • Remotes.EquipmentEquip(slot, id) -> Remotes.EquipmentResult(ok, slot, id, reason); ownership = EquipmentCatalog.Owns
	  • every character is dressed by EquipmentBuild.Dress on spawn and on change (models + colour attributes)

	Elimination effects (2026-11-14): same record gains Elimination = effect id (EffectCatalog).
	  • replicated as player attribute "EliminationStyle" (the killer's effect plays on the victim)
	  • Remotes.EliminationEquip(id) -> Remotes.EliminationResult(ok, id, reason)
	  (the StarterCharacter keeps Mk1 baked in, so a failure still leaves a suited player)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Skins = require(Vantage.Weapons.Skins)
local EquipCatalog = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local Presets = require(Vantage.Weapons:WaitForChild("LoadoutPresets")) -- loadout presets (2026-11-17)
local EquipBuild = require(Vantage.Equipment:WaitForChild("EquipmentBuild"))
local EffectCatalog = require(Vantage:WaitForChild("Elimination"):WaitForChild("EffectCatalog"))
local Remotes = Vantage:WaitForChild("Remotes")

local function remote(name: string): RemoteEvent
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r :: RemoteEvent
end
local SkinEquip = remote("SkinEquip")
local PresetEvent = remote("LoadoutPreset") -- client -> server: ("Select", index) / ("Set", index, slot, gunId)
local SkinResult = remote("SkinResult") -- server -> client: (ok, weaponId, skinId, reason)
local EquipmentEquip = remote("EquipmentEquip")
local EquipmentResult = remote("EquipmentResult") -- server -> client: (ok, slot, id, reason)
local ElimEquip = remote("EliminationEquip")
local ElimResult = remote("EliminationResult") -- server -> client: (ok, effectId, reason)

local STORE_NAME = "VantageLoadout_v1"
local store: DataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = s
	end
end

local data: { [Player]: { V: number, Skins: { [string]: string }, Armour: { [string]: any }, Equip: { [string]: string }, Elimination: string? } } = {}
local dirty: { [Player]: boolean } = {}
local lastEquip: { [Player]: number } = {}
local loaded: { [Player]: boolean } = {}

local function key(p: Player): string
	return "u_" .. p.UserId
end

local function publish(p: Player)
	local d = data[p]
	for _, w in Skins.Weapons do
		local id = d and d.Skins[w]
		if not (id and Skins.Owns(p, w, id)) then
			id = Skins.Default
		end
		p:SetAttribute("Skin_" .. w, id)
	end
end

-- re-skin what the player is holding / carrying right now
local function reskinWorld(p: Player, weaponId: string)
	local c = p.Character
	if not c then
		return
	end
	for _, name in { "VantageWorldWeapon", "VantageWorldKnife" } do
		local m = c:FindFirstChild(name)
		if m then
			local id = m:GetAttribute("WeaponId") or (if name == "VantageWorldKnife" then "Knife" else nil)
			if id == weaponId then
				Skins.Apply(m, weaponId, Skins.ForPlayer(p, weaponId))
			end
		end
	end
end

-- equipment: attributes + the live character
local function buildEquipment(p: Player)
	local c = p.Character
	if not c then
		return
	end
	local ok, err = pcall(EquipBuild.Dress, c, EquipCatalog.Equipped(p, "Pack"), EquipCatalog.Equipped(p, "Hook"))
	if not ok then
		warn("[VANTAGE] LoadoutService: equipment build failed:", err)
	end
end

local function publishEquipment(p: Player)
	local d = data[p]
	for _, slot in EquipCatalog.Slots do
		local id = d and d.Equip and d.Equip[slot]
		if not (id and EquipCatalog.Valid(slot, id) and EquipCatalog.Owns(p, id)) then
			id = EquipCatalog.Default[slot]
		end
		p:SetAttribute("Equip_" .. slot, id)
	end
end

local function publishElimination(p: Player)
	local d = data[p]
	local id = d and d.Elimination
	if not (id and EffectCatalog.Owns(p, id)) then
		id = EffectCatalog.Default
	end
	p:SetAttribute("EliminationStyle", id)
end

-- loadout presets: LoadoutPresets / LoadoutActive / ActiveLoadout attributes (WeaponService reads ActiveLoadout at spawn)
local function publishPresets(p: Player)
	local d = data[p]
	local enc = Presets.Encode((d and d.Presets) or {})
	local dec = Presets.Decode(enc)
	local a = math.clamp((d and d.Active) or 1, 1, Presets.Count)
	p:SetAttribute("LoadoutPresets", enc)
	p:SetAttribute("LoadoutActive", a)
	p:SetAttribute("ActiveLoadout", table.concat(dec[a], ","))
end

local function load(p: Player)
	local d = { V = 1, Skins = {}, Armour = {}, Equip = {}, Presets = {}, Active = 1 }
	if store then
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync(key(p))
		end)
		if ok and type(res) == "table" and type(res.Skins) == "table" then
			for w, s in res.Skins do
				if type(w) == "string" and type(s) == "string" and Skins.Valid(w, s) then
					d.Skins[w] = s
				end
			end
			if type(res.Armour) == "table" then
				d.Armour = res.Armour -- retired armour picks: carried through unchanged, never read
			end
			if type(res.Equip) == "table" then
				for slot, id in res.Equip do
					if type(slot) == "string" and type(id) == "string" and EquipCatalog.Valid(slot, id) then
						d.Equip[slot] = id
					end
				end
			end
			if EffectCatalog.Valid(res.Elimination) then
				d.Elimination = res.Elimination
			end
			if type(res.Presets) == "table" then
				for i = 1, Presets.Count do
					d.Presets[i] = Presets.Clean(res.Presets[i], Presets.Default[i])
				end
			end
			if type(res.Active) == "number" then
				d.Active = math.clamp(math.floor(res.Active), 1, Presets.Count)
			end
		elseif not ok then
			warn("[VANTAGE] LoadoutService: load failed (skins default this session):", res)
		end
	end
	if p.Parent then
		data[p] = d
		loaded[p] = true
		publish(p)
		publishEquipment(p)
		publishElimination(p)
		publishPresets(p)
		buildEquipment(p)
	end
end

local function save(p: Player)
	local d = data[p]
	if not (store and d and dirty[p] and loaded[p]) then
		return
	end
	dirty[p] = nil
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(p), d, { p.UserId })
	end)
	if not ok then
		dirty[p] = true
		warn("[VANTAGE] LoadoutService: save failed:", err)
	end
end

SkinEquip.OnServerEvent:Connect(function(p: Player, weaponId, skinId)
	local now = os.clock()
	if now - (lastEquip[p] or 0) < 0.15 then
		return
	end
	lastEquip[p] = now
	if type(weaponId) ~= "string" or type(skinId) ~= "string" or #weaponId > 32 or #skinId > 32 then
		return
	end
	if not Skins.Owns(p, weaponId, skinId) then
		SkinResult:FireClient(p, false, weaponId, skinId, "Not owned")
		return
	end
	local d = data[p]
	if not d then
		SkinResult:FireClient(p, false, weaponId, skinId, "Loading")
		return
	end
	d.Skins[weaponId] = if skinId == Skins.Default then nil else skinId
	dirty[p] = true
	p:SetAttribute("Skin_" .. weaponId, skinId)
	reskinWorld(p, weaponId)
	SkinResult:FireClient(p, true, weaponId, skinId)
end)

local lastEquipment: { [Player]: number } = {}
EquipmentEquip.OnServerEvent:Connect(function(p: Player, slot, id)
	local now = os.clock()
	if now - (lastEquipment[p] or 0) < 0.15 then
		return
	end
	lastEquipment[p] = now
	if type(slot) ~= "string" or type(id) ~= "string" or #slot > 16 or #id > 32 then
		return
	end
	if not EquipCatalog.Valid(slot, id) then
		EquipmentResult:FireClient(p, false, slot, id, "Unknown item")
		return
	end
	if not EquipCatalog.Owns(p, id) then
		EquipmentResult:FireClient(p, false, slot, id, "Not owned")
		return
	end
	local d = data[p]
	if not d then
		EquipmentResult:FireClient(p, false, slot, id, "Loading")
		return
	end
	d.Equip = d.Equip or {}
	d.Equip[slot] = if id == EquipCatalog.Default[slot] then nil else id
	dirty[p] = true
	p:SetAttribute("Equip_" .. slot, id)
	-- 2026-11-19: in a match the new item waits for the next spawn (stats and traits read the worn item,
	-- EquipmentCatalog.Active); in the lobby the character is re-dressed at once so the preview updates
	local c = p.Character
	if p.Team == nil or (c and c:GetAttribute("VantageHolstered")) then
		buildEquipment(p)
	end
	EquipmentResult:FireClient(p, true, slot, id)
end)

local lastPreset: { [Player]: number } = {}
PresetEvent.OnServerEvent:Connect(function(p: Player, action, idx, slot, gun)
	local now = os.clock()
	if now - (lastPreset[p] or 0) < 0.08 then
		return
	end
	lastPreset[p] = now
	local d = data[p]
	if not d or type(idx) ~= "number" then
		return
	end
	idx = math.floor(idx)
	if idx < 1 or idx > Presets.Count then
		return
	end
	d.Presets = d.Presets or {}
	for k = 1, Presets.Count do -- keep the array dense (DataStore)
		d.Presets[k] = Presets.Clean(d.Presets[k], Presets.Default[k])
	end
	if action == "Select" then
		d.Active = idx
	elseif action == "Set" then
		if type(slot) ~= "number" or not Presets.IsGun(gun) or not Presets.Owns(p, gun) then
			return -- 2026-11-17: locked guns (Arsenal Crates) can't be put in a preset
		end
		slot = math.floor(slot)
		if slot < 1 or slot > Presets.Slots then
			return
		end
		local list = d.Presets[idx]
		local at = table.find(list, gun)
		if at then
			list[at] = list[slot]
		end
		list[slot] = gun
	else
		return
	end
	dirty[p] = true
	publishPresets(p)
end)

local lastElim: { [Player]: number } = {}
ElimEquip.OnServerEvent:Connect(function(p: Player, effectId)
	local now = os.clock()
	if now - (lastElim[p] or 0) < 0.15 then
		return
	end
	lastElim[p] = now
	if type(effectId) ~= "string" or #effectId > 32 then
		return
	end
	if not EffectCatalog.Owns(p, effectId) then
		ElimResult:FireClient(p, false, effectId, "Not available")
		return
	end
	local d = data[p]
	if not d then
		ElimResult:FireClient(p, false, effectId, "Loading")
		return
	end
	d.Elimination = if effectId == EffectCatalog.Default then nil else effectId
	dirty[p] = true
	p:SetAttribute("EliminationStyle", effectId)
	ElimResult:FireClient(p, true, effectId)
end)

local function onPlayer(p: Player)
	publishPresets(p) -- defaults until the save loads
	if p:GetAttribute("EliminationStyle") == nil then
		p:SetAttribute("EliminationStyle", EffectCatalog.Default)
	end
	p.CharacterAdded:Connect(function()
		buildEquipment(p) -- before the save loads this is the starters (Equip_* attributes default)
	end)
	-- ownership (CrateService) can arrive after the save: re-check the equipped items against it
	p:GetAttributeChangedSignal("OwnedEquipment"):Connect(function()
		if not data[p] then
			return
		end
		local pack, hook = p:GetAttribute("Equip_Pack"), p:GetAttribute("Equip_Hook")
		publishEquipment(p)
		if p:GetAttribute("Equip_Pack") ~= pack or p:GetAttribute("Equip_Hook") ~= hook then
			buildEquipment(p)
		end
	end)
	load(p)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p], dirty[p], lastEquip[p], loaded[p], lastEquipment[p], lastElim[p] = nil, nil, nil, nil, nil, nil
end)
-- periodic flush (selections are tiny; one write per change batch, max every 30 s)
task.spawn(function()
	while true do
		task.wait(30)
		for p in dirty do
			task.spawn(save, p)
		end
	end
end)
game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	local n = 0
	for p in dirty do
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
