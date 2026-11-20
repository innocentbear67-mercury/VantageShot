--[[
	VANTAGE — ShieldService (server)
	Shield-first damage. DamageService (guns, knife) and CombatBot call Absorb() before applying
	health damage; everything else (kill volumes, falls) bypasses the shield and hits health.
	State lives in replicated character attributes so any client can draw it.

	API
		ShieldService.Setup(character)               full shield (called on spawn)
		ShieldService.Absorb(character, amount)      -> toHealth, absorbed, broke
		ShieldService.Get(character)                 -> shield, maxShield
		ShieldService.Report(character, position, direction, absorbed, broke)
		                                             tells every client where the shield was hit
		                                             (WeaponEvent "ShieldHit", drawn by ShieldFX)

	Recharge state: the character attribute ShieldRecharging (bool) is written ONLY when the
	recharge starts or stops (never per tick), so clients can drive the recharge FX / audio from
	the authoritative state with no extra RemoteEvents. It goes false the moment Absorb() takes
	damage (interrupted: Shield < MaxShield) or the shield reaches max (complete: Shield = MaxShield),
	and on death. Shield is always written before ShieldRecharging, so clients reading Shield in
	the ShieldRecharging change handler see the final value.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Vantage.Shield.ShieldConfig)
local EventRemote = ReplicatedStorage.Vantage.Remotes:WaitForChild("WeaponEvent") :: RemoteEvent

local ShieldService = {}
local tracked: { [Model]: { LastHit: number, Charging: boolean } } = {}

-- 2026-11-17: each Shield Pack has its own capacity / recharge delay / recharge rate (EquipmentCatalog,
-- multipliers on ShieldConfig). Players: their Equip_Pack; bots and dummies: the character's EquipPack.
local Players = game:GetService("Players")
local EquipCatalog = nil
pcall(function()
	EquipCatalog = require(ReplicatedStorage.Vantage:WaitForChild("Equipment", 5):WaitForChild("EquipmentCatalog", 5))
end)
local packCache: { [string]: any } = {}
local function packStats(character: Model): (number, number, number)
	if not EquipCatalog then
		return Cfg.MaxShield, Cfg.RegenDelay, Cfg.RegenRate
	end
	-- 2026-11-19: the pack this character wears this life (EquipPack, set on spawn), so a mid-match equip waits for the next spawn
	local id = EquipCatalog.Active(character, "Pack")
	local st = packCache[id]
	if not st then
		st = EquipCatalog.PackStatsFor(id)
		packCache[id] = st
	end
	return st.MaxShield, st.RegenDelay, st.RegenRate
end
ShieldService.PackStats = packStats

-- 2026-11-18 equipment abilities (EquipmentPerkServer registers): Break(character) when a shield breaks,
-- RechargeStart(character) when a recharge begins. Hooks run deferred, after the hit that caused them is applied.
-- 2026-11-19: Low(character) when a hit takes the shield from >= 25 % to below it (Bastion's Hex Wall).
ShieldService.Hooks = { Break = {}, RechargeStart = {}, Low = {} }
local function fire(kind: string, character: Model)
	for _, f in ShieldService.Hooks[kind] do
		task.defer(function()
			local ok, err = pcall(f, character)
			if not ok then
				warn("[VANTAGE] ShieldService " .. kind .. " hook: " .. tostring(err))
			end
		end)
	end
end

local function setCharging(character: Model, rec, on: boolean)
	if rec.Charging ~= on then
		rec.Charging = on
		character:SetAttribute("ShieldRecharging", on)
		if on then
			fire("RechargeStart", character)
		end
	end
end

-- Kill Charge: skip the rest of the recharge delay
function ShieldService.StartRecharge(character: Model)
	local rec = tracked[character]
	if rec then
		rec.LastHit = -math.huge
	end
end

-- add shield points (capped at the pack's max); returns what was added
function ShieldService.Add(character: Model, amount: number): number
	if not tracked[character] or amount <= 0 then
		return 0
	end
	local s = character:GetAttribute("Shield") or 0
	local max = character:GetAttribute("MaxShield") or 0
	local nxt = math.min(max, s + amount)
	if nxt > s then
		character:SetAttribute("Shield", nxt)
	end
	return nxt - s
end

function ShieldService.Setup(character: Model)
	if not Cfg.Enabled then
		return
	end
	local maxShield = packStats(character)
	character:SetAttribute("MaxShield", maxShield)
	character:SetAttribute("Shield", maxShield)
	character:SetAttribute("ShieldRecharging", false)
	character:SetAttribute("Overshield", 0)
	tracked[character] = { LastHit = -math.huge, Charging = false }
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			tracked[character] = nil
		end
	end)
end

function ShieldService.Get(character: Model): (number, number)
	return character:GetAttribute("Shield") or 0, character:GetAttribute("MaxShield") or 0
end

function ShieldService.Absorb(character: Model, amount: number): (number, number, boolean)
	local rec = tracked[character]
	if not Cfg.Enabled or not rec or amount <= 0 then
		return amount, 0, false
	end
	rec.LastHit = os.clock()
	-- 2026-11-19 Halo Ring: the gold overshield (character attribute Overshield) takes the hit first
	local over = character:GetAttribute("Overshield") or 0
	local fromOver = 0
	if over > 0 then
		fromOver = math.min(over, amount)
		character:SetAttribute("Overshield", over - fromOver)
		amount -= fromOver
		if amount <= 0 then
			setCharging(character, rec, false)
			return 0, fromOver, false
		end
	end
	local shield = character:GetAttribute("Shield") or 0
	if shield <= 0 then
		setCharging(character, rec, false) -- hit while recharging from empty: interrupted
		return amount, fromOver, false
	end
	local absorbed = math.min(shield, amount)
	local left = shield - absorbed
	character:SetAttribute("Shield", left)
	setCharging(character, rec, false) -- after Shield, so clients see the lowered value
	local maxS = character:GetAttribute("MaxShield") or 0
	if maxS > 0 and shield >= maxS * 0.25 and left < maxS * 0.25 then
		fire("Low", character)
	end
	absorbed += fromOver
	local broke = left <= 0
	if broke then
		character:SetAttribute("ShieldBrokenAt", Workspace:GetServerTimeNow())
		fire("Break", character)
	end
	local toHealth = amount - (absorbed - fromOver)
	if broke and Cfg.BreakAbsorbsOverflow then
		toHealth = 0
	end
	return toHealth, absorbed, broke
end

-- Called by the damage paths right after Absorb with the real impact point and bullet direction
-- from the server's hit detection. Every client draws the reaction (shooter, victim, bystanders);
-- the shield value itself still only comes from the replicated attributes.
function ShieldService.Report(character: Model, position: Vector3, direction: Vector3, absorbed: number, broke: boolean)
	if not Cfg.Enabled or (absorbed <= 0 and not broke) then
		return
	end
	local shield, max = ShieldService.Get(character)
	EventRemote:FireAllClients("ShieldHit", character, position, direction, if max > 0 then shield / max else 0, absorbed, broke)
end

-- recharge (one shared loop at Cfg.TickRate, not per frame)
local acc = 0
function ShieldService.Start()
	if RunService:IsStudio() then
		-- Studio-only test hook (the command bar runs in its own Lua VM, so it can't call this module):
		--   ShieldService.ShieldTest:Fire(character, "Damage", amount)  shield-first damage, like a bullet
		--   ShieldService.ShieldTest:Fire(model, "Setup")               give a test dummy a shield
		local test = Instance.new("BindableEvent")
		test.Name = "ShieldTest"
		test.Event:Connect(function(character: Model, kind: string, amount: number?)
			if kind == "Setup" then
				ShieldService.Setup(character)
			elseif kind == "Damage" then
				local toHealth, absorbed, broke = ShieldService.Absorb(character, amount or 25)
				local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
				if torso then
					ShieldService.Report(character, torso.Position + torso.CFrame.LookVector, -torso.CFrame.LookVector, absorbed, broke)
				end
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum and toHealth > 0 then
					hum:TakeDamage(toHealth)
				end
			end
		end)
		test.Parent = script
	end
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		local step = 1 / Cfg.TickRate
		if acc < step then
			return
		end
		local elapsed = acc
		acc = 0
		local now = os.clock()
		for character, rec in tracked do
			local hum = character:FindFirstChildOfClass("Humanoid")
			local charging = false
			local packMax, regenDelay, regenRate = packStats(character)
			if character:GetAttribute("MaxShield") ~= packMax then
				-- the pack changed (lobby swap): new capacity, current shield clamped to it
				character:SetAttribute("MaxShield", packMax)
				if (character:GetAttribute("Shield") or 0) > packMax then
					character:SetAttribute("Shield", packMax)
				end
			end
			if hum and hum.Health > 0 and now - rec.LastHit >= regenDelay then
				local s = character:GetAttribute("Shield") or 0
				local max = character:GetAttribute("MaxShield") or Cfg.MaxShield
				if s < max then
					local nxt = math.min(max, s + regenRate * elapsed)
					character:SetAttribute("Shield", nxt)
					-- stays true on the tick that fills it only if it was already charging; a
					-- top-up of a few points finished in one tick (< 1 tick) shows no recharge FX
					charging = nxt < max
				end
			end
			setCharging(character, rec, charging)
			-- Halo Ring: 4 s at full shield with no damage -> the overshield fills over Params.Fill seconds
			if EquipCatalog then
				local abil, AP = EquipCatalog.AbilityOf(character, "Pack")
				local o = character:GetAttribute("Overshield") or 0
				if abil == "Overshield" then
					local s = character:GetAttribute("Shield") or 0
					local mx = character:GetAttribute("MaxShield") or 0
					local amt = AP.Amount or 30
					if hum and hum.Health > 0 and s >= mx and now - rec.LastHit >= (AP.Wait or 4) and o < amt then
						character:SetAttribute("Overshield", math.min(amt, o + amt / math.max(0.05, AP.Fill or 1) * elapsed))
					end
				elseif o > 0 then
					character:SetAttribute("Overshield", 0)
				end
			end
		end
	end)
end

return ShieldService
