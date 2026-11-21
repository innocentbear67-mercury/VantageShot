--[[
	VANTAGE — DamageService (server)
	Applies validated hits (gun or knife). Damage values come from WeaponConfig only — the
	client never sends a damage value or a target. Handles friendly fire, spawn ForceFields,
	kill credit, the placeholder team score, and records the killing hit's direction / headshot
	on the victim (used to pick the death animation).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = ReplicatedStorage.Vantage.Weapons
local Config = require(Weapons.WeaponConfig)
local WeaponMath = require(Weapons.WeaponMath)
local ShieldService = require(script.Parent.ShieldService)

local DamageService = {}
DamageService.HitHooks = {} -- f(shooter: Player, victimCharacter: Model, dealt: number)

-- assist ledger (kill feed only — no score, no stats): who hurt each character, how much, when
local ledger: { [Model]: { [number]: { Damage: number, Last: number } } } = setmetatable({}, { __mode = "k" }) :: any
local Progression = nil -- lazy: progression stats (Damage directives / operations)
local function noteDamage(character: Model, shooter: Player, amount: number)
	if amount <= 0 then
		return
	end
	if character ~= shooter.Character then
		if not Progression then
			local ok, mod = pcall(require, script.Parent.Parent:WaitForChild("Progression"))
			Progression = if ok then mod else false
		end
		if Progression then
			pcall(Progression.OnDamage, shooter, amount)
		end
	end
	local t = ledger[character]
	if not t then
		t = {}
		ledger[character] = t
	end
	local e = t[shooter.UserId]
	if not e then
		e = { Damage = 0, Last = 0 }
		t[shooter.UserId] = e
	end
	e.Damage += amount
	e.Last = os.clock()
end
-- players (UserIds) who damaged this character within `window` seconds, most damage first
function DamageService.Contributors(character: Model, window: number): { { UserId: number, Damage: number } }
	local out = {}
	local now = os.clock()
	for uid, e in ledger[character] or {} do
		if now - e.Last <= window then
			table.insert(out, { UserId = uid, Damage = e.Damage })
		end
	end
	table.sort(out, function(a, b)
		return a.Damage > b.Damage
	end)
	return out
end

local function matchFolder(): Folder
	local f = ReplicatedStorage.Vantage:FindFirstChild("Match")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Match"
		f:SetAttribute("BlueScore", 0)
		f:SetAttribute("RedScore", 0)
		f.Parent = ReplicatedStorage.Vantage
	end
	return f :: Folder
end
DamageService.MatchFolder = matchFolder

-- MatchService sets Match.Combat: false outside the Live phase (matchmaking, deployment,
-- preparation, countdown, results). No match system at all (attribute missing) = combat on.
function DamageService.CombatEnabled(): boolean
	return matchFolder():GetAttribute("Combat") ~= false
end

local function teamOf(character: Model): string?
	local p = Players:GetPlayerFromCharacter(character)
	if p then
		return if p.Team and not p.Neutral then p.Team.Name else nil
	end
	return character:GetAttribute("Team") -- Studio training dummies
end
DamageService.TeamOf = teamOf

function DamageService.IsFriendly(shooter: Player, victimCharacter: Model): boolean
	if shooter.Character == victimCharacter then
		return true
	end
	local a = shooter.Team and not shooter.Neutral and shooter.Team.Name or nil
	local b = teamOf(victimCharacter)
	return a ~= nil and b ~= nil and a == b
end

--[[ hit: { Character, Humanoid, IsHead, IsLimb, Distance, Position?, Direction? }
	amount: optional explicit damage (melee); otherwise computed from the weapon.
	Returns nil when nothing was applied, else
	{ Damage, Headshot, Killed, Blocked, VictimName, VictimPlayer, ShieldDamage, ShieldBroken }
	The shield (ShieldService) absorbs first; only the remainder reaches Humanoid health. ]]
-- weapon mastery XP for damage (2026-11-17); lazy, like Progression above
local Mastery = nil
local function noteMastery(shooter: Player, weaponId: string?, character: Model, amount: number)
	if amount <= 0 or type(weaponId) ~= "string" then
		return
	end
	if Mastery == nil then
		local ok, mod = pcall(require, script.Parent.Parent:WaitForChild("Mastery"))
		Mastery = if ok then mod else false
	end
	if Mastery then
		pcall(Mastery.OnDamage, shooter, weaponId, character, amount)
	end
end

function DamageService.Apply(shooter: Player, weapon, hit, amount: number?)
	local humanoid: Humanoid? = hit.Humanoid
	local character: Model? = hit.Character
	if not humanoid or not character or humanoid.Health <= 0 then
		return nil
	end
	if shooter.Character == character then
		return nil
	end
	-- 2026-11-20 first-time training (TutorialService): a trainee only hits their own targets, and nobody
	-- can hit a trainee or someone else's targets. Training hits work outside the Live phase.
	local tutTarget = character:GetAttribute("TutorialTarget")
	if (shooter:GetAttribute("InTutorial") or tutTarget) and tutTarget ~= shooter.UserId then
		return nil
	end
	if DamageService.IsFriendly(shooter, character) and not Config.FriendlyFire then
		return nil
	end
	local victimPlayer = Players:GetPlayerFromCharacter(character)
	if victimPlayer and victimPlayer:GetAttribute("InTutorial") then
		return nil
	end
	local victimName = if victimPlayer then victimPlayer.DisplayName else character.Name
	if not DamageService.CombatEnabled() and not tutTarget then
		return { Damage = 0, Headshot = hit.IsHead, Killed = false, Blocked = true, VictimName = victimName }
	end
	if character:FindFirstChildOfClass("ForceField") then
		return { Damage = 0, Headshot = hit.IsHead, Killed = false, Blocked = true, VictimName = victimName }
	end

	local dmg = amount or WeaponMath.Damage(weapon, hit.IsHead, hit.IsLimb, hit.Distance)
	local toHealth, absorbed, broke = ShieldService.Absorb(character, dmg)
	-- every client draws the shield reaction at the real impact point, along the real shot direction
	local body = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	local hitPos = if typeof(hit.Position) == "Vector3" then hit.Position elseif body then body.Position else nil
	if hitPos then
		local from = shooter.Character and shooter.Character:FindFirstChild("Head") :: BasePart?
		local hitDir = if typeof(hit.Direction) == "Vector3" and hit.Direction.Magnitude > 1e-3 then hit.Direction.Unit
			elseif from and (hitPos - from.Position).Magnitude > 1e-3 then (hitPos - from.Position).Unit
			else Vector3.new(0, 0, -1)
		ShieldService.Report(character, hitPos, hitDir, absorbed, broke)
	end
	local before = humanoid.Health
	-- record the hit before damage so the death handler sees the killing blow
	character:SetAttribute("LastDamagedBy", shooter.UserId)
	character:SetAttribute("LastHitHead", hit.IsHead == true)
	if typeof(hit.Direction) == "Vector3" then
		character:SetAttribute("LastHitDir", hit.Direction)
	end
	character:SetAttribute("LastHitWeapon", weapon.Id)
	-- what kind of hit it was (kill feed): Gun / Melee / Vehicle / Aircraft, and whether it was a blast
	character:SetAttribute("LastHitKind", weapon.Kind)
	character:SetAttribute("LastHitExplosive", weapon.Explosive == true)
	-- the lethal hit names the killer (EliminationService credits only hits that actually kill)
	if toHealth >= before then
		character:SetAttribute("VantageKiller", shooter.UserId)
	end
	if toHealth > 0 then
		humanoid:TakeDamage(toHealth)
	end
	-- Humanoid.Health can go below 0 on the killing hit: count only what was actually removed
	local dealt = absorbed + (before - math.max(0, humanoid.Health))
	local killed = before > 0 and humanoid.Health <= 0
	if not tutTarget then -- training targets give no assists or mastery XP
		noteDamage(character, shooter, dealt)
		noteMastery(shooter, weapon and weapon.Id, character, dealt)
	end
	-- 2026-11-18 equipment abilities (Harpoon: shooting the hunter cuts the line)
	if dealt > 0 then
		for _, f in DamageService.HitHooks do
			task.spawn(pcall, f, shooter, character, dealt)
		end
	end

	if killed and Config.AwardTeamScoreOnKill and shooter.Team and victimPlayer then
		local m = matchFolder()
		local key = shooter.Team.Name .. "Score"
		m:SetAttribute(key, (m:GetAttribute(key) or 0) + 1)
	end
	-- (the kill feed is sent once per death by EliminationService.OnDeath, for every kind of death)
	return {
		Damage = dealt,
		Headshot = hit.IsHead,
		Killed = killed,
		Blocked = false,
		VictimName = victimName,
		VictimPlayer = victimPlayer,
		ShieldDamage = absorbed,
		ShieldBroken = broke,
	}
end

-- Vehicles (VehicleService sets VehicleHandler): a validated gun hit on a non-character part.
-- Returns the damage the vehicle took, or nil when the part is not part of a vehicle.
DamageService.VehicleHandler = nil :: ((Player, any, any, number?) -> number?)?
function DamageService.ApplyToVehicle(shooter: Player, weapon, hit, amount: number?): number?
	-- 2026-11-18: a Hex Wall (Bastion) soaks the bullet (EquipmentPerkServer breaks it at 0 HP)
	local inst = hit and hit.Instance
	if inst and type(inst:GetAttribute("PerkWallHP")) == "number" then
		local dmg = amount or WeaponMath.Damage(weapon, false, false, hit.Distance or 0)
		inst:SetAttribute("PerkWallHP", inst:GetAttribute("PerkWallHP") - dmg)
		return nil
	end
	local handler = DamageService.VehicleHandler
	if handler and hit and hit.Instance then
		return handler(shooter, weapon, hit, amount)
	end
	return nil
end

return DamageService
