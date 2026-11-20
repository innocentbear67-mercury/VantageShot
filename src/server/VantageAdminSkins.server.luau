--[[
	VANTAGE — AdminSkins (server, 2026-11-15)
	Skin checker for admins: swap your weapon skin live in a match and auto-play its inspect.
	  /skin                 next skin (current weapon, default VX-01 Vanguard) + inspect
	  /skin prev            previous skin
	  /skin <name>          e.g. /skin dragon, /skin kitsune, /skin glacier
	  /skin <weapon> [name] switch weapon (e.g. /skin sentinel, /skin sentinel phoenix)
	  /skin list            list the weapon's skins
	  /skin tour            play every skin that has its own inspect, one after another (/skin stop)
	  /skin noinspect       toggle the auto-inspect after a swap
	Hotkeys (client): = next, - previous.
	Admins: everyone in Studio; in live servers only the game owner. Cosmetic only (sets Skin_<weapon>).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Weapons = ReplicatedStorage.Vantage.Weapons
local Skins = require(Weapons.Skins)
local Config = require(Weapons.WeaponConfig)
local SkinInspects = require(Weapons.SkinInspects)

local remote = ReplicatedStorage:FindFirstChild("VantageAdminSkin") or Instance.new("RemoteEvent")
remote.Name = "VantageAdminSkin"
remote.Parent = ReplicatedStorage

local function isAdmin(p: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return p.UserId == game.CreatorId
	end
	local ok, rank = pcall(p.GetRankInGroup, p, game.CreatorId)
	return ok and rank >= 254
end

local function norm(s: string): string
	return string.lower((string.gsub(s, "[^%w]", "")))
end

local function weaponFrom(word: string?): string?
	if not word or word == "" then
		return nil
	end
	local q = norm(word)
	for id, w in Config.Weapons do
		if norm(id) == q or (type(w) == "table" and w.Name and norm(w.Name) == q) then
			if #Skins.List(id) > 0 then
				return id
			end
		end
	end
	return nil
end

local function findSkin(weaponId: string, q: string)
	q = norm(q)
	if q == "" then
		return nil
	end
	local list = Skins.List(weaponId)
	for _, s in list do
		if norm(s.Id) == q or norm(s.Name) == q then
			return s
		end
	end
	for _, s in list do
		if string.find(norm(s.Id), q, 1, true) or string.find(norm(s.Name), q, 1, true) then
			return s
		end
	end
	return nil
end

local state: { [Player]: { Weapon: string, Inspect: boolean, Tour: number? } } = {}
local function st(p: Player)
	local s = state[p]
	if not s then
		s = { Weapon = "Vanguard", Inspect = true }
		state[p] = s
	end
	return s
end

local function tell(p: Player, text: string)
	remote:FireClient(p, text)
end

local function equip(p: Player, weaponId: string, skin, inspect: boolean?)
	p:SetAttribute("Skin_" .. weaponId, skin.Id)
	local has = SkinInspects.For(skin.Id, weaponId) ~= nil
	tell(p, string.format("%s  ·  %s%s", skin.Name, skin.Rarity or "", if has then "  ·  custom inspect" else ""))
	if inspect ~= false and st(p).Inspect then
		task.delay(0.15, function()
			if p.Parent then
				p:SetAttribute("VantageAutoInspect", os.clock()) -- WeaponInput plays the inspect
			end
		end)
	end
end

local function step(p: Player, dir: number)
	local S = st(p)
	local list = Skins.List(S.Weapon)
	if #list == 0 then
		return
	end
	local cur = Skins.ForPlayer(p, S.Weapon)
	local idx = 0
	for i, s in list do
		if s.Id == cur then
			idx = i
		end
	end
	idx = ((idx - 1 + dir) % #list) + 1
	equip(p, S.Weapon, list[idx])
end

local function command(p: Player, rest: string)
	if not isAdmin(p) then
		return
	end
	local S = st(p)
	local args = string.split(string.gsub(rest, "^%s+", ""), " ")
	local a1 = string.lower(args[1] or "")
	if a1 ~= "tour" then
		S.Tour = nil
	end
	if a1 == "" or a1 == "next" then
		step(p, 1)
	elseif a1 == "prev" or a1 == "back" then
		step(p, -1)
	elseif a1 == "list" then
		local names = {}
		for _, s in Skins.List(S.Weapon) do
			table.insert(names, s.Name .. (if SkinInspects.For(s.Id, S.Weapon) then "*" else ""))
		end
		tell(p, S.Weapon .. ": " .. table.concat(names, ", ") .. "   (* custom inspect)")
	elseif a1 == "noinspect" or a1 == "inspect" then
		S.Inspect = not S.Inspect
		tell(p, "Auto-inspect after swap: " .. (if S.Inspect then "ON" else "OFF"))
	elseif a1 == "stop" then
		tell(p, "Tour stopped")
	elseif a1 == "tour" then
		local token = os.clock()
		S.Tour = token
		local tw = S.Weapon
		task.spawn(function()
			for _, s in Skins.List(tw) do
				local clip = SkinInspects.For(s.Id, tw)
				if clip then
					if S.Tour ~= token or not p.Parent then
						return
					end
					equip(p, tw, s, true)
					task.wait(clip.Length + 0.9)
				end
			end
			if S.Tour == token then
				S.Tour = nil
				tell(p, "Tour done")
			end
		end)
	else
		local w = weaponFrom(args[1])
		if w then
			S.Weapon = w
			local q = table.concat(args, "", 2)
			local s = q ~= "" and findSkin(w, q)
			if s then
				equip(p, w, s)
			else
				tell(p, "Weapon: " .. w .. "  (=/- to cycle, /skin list)")
			end
		else
			local s = findSkin(S.Weapon, table.concat(args, ""))
			if s then
				equip(p, S.Weapon, s)
			else
				tell(p, "No skin matching '" .. rest .. "' on " .. S.Weapon .. " (/skin list)")
			end
		end
	end
end

local last: { [Player]: number } = {}
local function fromChat(p: Player, msg: string)
	local rest = string.match(msg, "^/skins?%s*(.*)$")
	if not rest then
		return
	end
	if last[p] and os.clock() - last[p] < 0.3 then
		return
	end
	last[p] = os.clock()
	task.spawn(command, p, rest)
end

pcall(function()
	local parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	local old = parent:FindFirstChild("AdminSkinCommand")
	if old then
		old:Destroy()
	end
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "AdminSkinCommand"
	cmd.PrimaryAlias = "/skin"
	cmd.SecondaryAlias = "/skins"
	cmd.Parent = parent
	cmd.Triggered:Connect(function(source: TextSource, text: string)
		local p = Players:GetPlayerByUserId(source.UserId)
		if p then
			fromChat(p, text)
		end
	end)
end)
local function hook(p: Player)
	p.Chatted:Connect(function(m)
		fromChat(p, m)
	end)
end
Players.PlayerAdded:Connect(hook)
for _, p in Players:GetPlayers() do
	hook(p)
end
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
	last[p] = nil
end)

remote.OnServerEvent:Connect(function(p: Player, action)
	if not isAdmin(p) then
		return
	end
	if last[p] and os.clock() - last[p] < 0.15 then
		return
	end
	last[p] = os.clock()
	st(p).Tour = nil
	if action == "next" then
		step(p, 1)
	elseif action == "prev" then
		step(p, -1)
	end
end)
