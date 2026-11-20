--[[
	VANTAGE — WeaponService (server)
	Authoritative combat state per player: equipped weapon, ammo, fire rate, reload, melee,
	aim replication, movement speed multiplier, deaths.
	Remotes (ReplicatedStorage.Vantage.Remotes):
		WeaponFire   C->S  (clientServerTime, origin, direction, seq)
		WeaponAction C->S  ("Reload") | ("CancelReload") | ("Equip", id) | ("Anim", clip)
		                   | ("Melee", "Primary"|"Secondary", clientServerTime, lookDir)
		WeaponAim    C->S  unreliable (pitchDeg, ads)
		WeaponEvent  S->C  ("Ammo", weaponId, mag, reserve, reason, reloading, lastSeq) | ("Confirm", info)
		                   | ("Shot", shooterCharacter, pelletEnds[]) — one message per shot; each end
	                   |   { Position, Normal, Kind, Material?, Extra? } (Extra = { Quiet = true }
	                   |   for pellets after the first, { Projectile = speed } for energy bolts;
	                   |   the debug dummy hook still sends the legacy flat endPos/normal/kind/material)
		                   | ("Melee", attackerCharacter, hitPos?, hitBody?)
		                   | ("Damaged", sourcePos, amount)
		                   | ("Died", killer, killerPos, weapon, headshot, distance?, killerCharacter?)
	Replicated character attributes (read by every client's ThirdPersonRig / DeathPresenter):
		VantageWeapon, VantageAim, VantageADS, VantageAction "<Clip>:<serverTime>",
		VantageSpeedMult (validated by MovementValidator), VantageDeath "<Style>:<serverTime>"
	Every message is type-checked and rate limited; nothing the client sends is trusted for damage.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage.Vantage
local Weapons = Vantage.Weapons
local Skins = require(Weapons.Skins) -- cosmetic only
local Config = require(Weapons.WeaponConfig)
local LoadoutPresets = require(game:GetService("ReplicatedStorage").Vantage.Weapons:WaitForChild("LoadoutPresets")) -- per-player loadout (2026-11-17)
local CoreOverload = require(Vantage.Elimination.CoreOverloadConfig)
local EffectCatalog = require(Vantage.Elimination.EffectCatalog)
local WeaponMath = require(Weapons.WeaponMath)
local HitValidation = require(script.Parent.HitValidation)
local DamageService = require(script.Parent.DamageService)
local EliminationService = require(script.Parent.EliminationService)
local ShieldService = require(script.Parent.ShieldService)
local S = Config.Server

local Remotes = Vantage.Remotes
local FireRemote = Remotes.WeaponFire :: RemoteEvent
local ActionRemote = Remotes.WeaponAction :: RemoteEvent
local EventRemote = Remotes.WeaponEvent :: RemoteEvent
local AimRemote = Remotes:WaitForChild("WeaponAim")

local WeaponService = {}
local states: { [Player]: any } = {}
WeaponService.States = states
WeaponService.Stats = { Accepted = 0, Rejected = {}, Hits = 0, Damage = 0, MeleeHits = 0 }

local ANIM_WHITELIST = { Knife = { Slash1 = true, Slash2 = true, Stab = true, Inspect = true } }
local GUN_ANIMS = { Inspect = true } -- every gun: replicated inspect (F)

local function reject(st, reason: string)
	local r = WeaponService.Stats.Rejected
	r[reason] = (r[reason] or 0) + 1
	return false
end

-- Per-weapon ammo / fire-rate record (every gun in the loadout keeps its own magazine).
local function newAmmo(weapon)
	return {
		Mag = weapon.MagazineSize,
		Reserve = weapon.ReserveAmmo,
		Tokens = S.FireBurstTokens,
		LastRefill = os.clock(),
		LastSeq = 0, -- the client's shot counter (per weapon) restarts with each life
		LastShotAt = 0,
		BurstCount = 0,
		Heat = 0, HeatAt = 0, LockedUntil = 0, -- energy weapons only
	}
end

local function ammoOf(st, id: string?)
	id = id or st.Equipped
	return st.Ammo[id], id
end

-- lastSeq = newest client shot the server has processed: the client re-applies shots still
-- in flight, so a sync never "gives back" a round it already fired
local function sendAmmo(player: Player, st, reason: string?, id: string?)
	local a, wid = ammoOf(st, id)
	if not a then
		return
	end
	EventRemote:FireClient(player, "Ammo", wid, a.Mag, a.Reserve, reason or "Sync", st.Reloading and st.ReloadingId == wid, a.LastSeq)
end

local function setAction(character: Model, clip: string)
	character:SetAttribute("VantageAction", string.format("%s:%.3f", clip, Workspace:GetServerTimeNow()))
end

local function dropsFolder(): Folder
	local f = Workspace:FindFirstChild("VantageDrops")
	if not f then
		f = Instance.new("Folder")
		f.Name = "VantageDrops"
		f.Parent = Workspace
	end
	return f :: Folder
end

-- ─── third-person models ────────────────────────────────────────────────────
local function prepModel(model: Model, primary: BasePart, weldAll: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = not (d.Material == Enum.Material.Neon or d.Material == Enum.Material.Glass)
		end
	end
	if weldAll then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= primary then
				local w = Instance.new("WeldConstraint")
				w.Part0 = primary
				w.Part1 = d
				w.Parent = d
			end
		end
	end
end

local RIFLE_SLING = CFrame.lookAt(Vector3.new(0.05, 0.1, 0.66), Vector3.new(0.05, 0.1, 0.66) + Vector3.new(-0.55, 0.83, 0), Vector3.new(0, 0, 1))
local KNIFE_HIP = CFrame.new(-0.62, -0.05, 0.25) * CFrame.Angles(math.rad(180), 0, math.rad(8))

-- The world model of the gun in hand (or slung while the knife is out). One gun model at a time:
-- equipping another gun swaps the model.
local function attachGun(character: Model, weapon)
	local asset = Weapons.Assets:FindFirstChild(weapon.Asset)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not asset or not torso then
		warn("[VANTAGE] WeaponService: cannot attach gun", weapon.Id, asset, torso)
		return
	end
	local old = character:FindFirstChild("VantageWorldWeapon")
	if old then
		old:Destroy()
	end
	local model = asset:Clone()
	model.Name = "VantageWorldWeapon"
	model:SetAttribute("WeaponId", weapon.Id)
	Skins.Apply(model, weapon.Id, Skins.ForPlayer(Players:GetPlayerFromCharacter(character), weapon.Id))
	if weapon.ThirdPerson.Scale ~= 1 then
		model:ScaleTo(weapon.ThirdPerson.Scale)
	end
	local body = model.PrimaryPart :: BasePart
	local mag = model:FindFirstChild("Magazine")
	local magBody = mag and mag.PrimaryPart
	-- start at the hold so every weld / motor offset is created in place (no first-frame jump)
	model:PivotTo(torso.CFrame * weapon.ThirdPerson.Hold * body.CFrame:ToObjectSpace(model:GetPivot()))
	prepModel(model, body, false)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body and d ~= magBody then
			local w = Instance.new("WeldConstraint")
			w.Part0 = if mag and d:IsDescendantOf(mag) then magBody else body
			w.Part1 = d
			w.Parent = d
		end
	end
	if magBody then
		local mm = Instance.new("Motor6D")
		mm.Name = "VantageMagMotor"
		mm.Part0 = body
		mm.Part1 = magBody
		mm.C0 = body.CFrame:ToObjectSpace(magBody.CFrame)
		mm.C1 = CFrame.identity
		mm.Parent = body
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "VantageGunMotor"
	motor.Part0 = torso
	motor.Part1 = body
	motor.C0 = weapon.ThirdPerson.Hold
	motor.C1 = CFrame.identity
	motor.Parent = body
	model.Parent = character
end

local function attachKnife(character: Model, weapon)
	local asset = Weapons.Assets:FindFirstChild(weapon.Asset)
	local lower = character:WaitForChild("LowerTorso", 5)
	if not asset or not lower then
		return
	end
	local old = character:FindFirstChild("VantageWorldKnife")
	if old then
		old:Destroy()
	end
	local model = asset:Clone()
	model.Name = "VantageWorldKnife"
	model:SetAttribute("WeaponId", "Knife")
	Skins.Apply(model, "Knife", Skins.ForPlayer(Players:GetPlayerFromCharacter(character), "Knife"))
	if weapon.ThirdPerson.Scale ~= 1 then
		model:ScaleTo(weapon.ThirdPerson.Scale)
	end
	local handle = model.PrimaryPart :: BasePart
	model:PivotTo(lower.CFrame * KNIFE_HIP * handle.CFrame:ToObjectSpace(model:GetPivot()))
	prepModel(model, handle, false) -- the builder already welded pieces + hinge motors
	local grip = handle:FindFirstChild("Grip") :: Attachment
	local motor = Instance.new("Motor6D")
	motor.Name = "VantageKnifeMotor"
	motor.Part0 = lower
	motor.Part1 = handle
	motor.C0 = KNIFE_HIP
	motor.C1 = grip and grip.CFrame or CFrame.identity
	motor.Parent = handle
	model.Parent = character
end

-- equipped weapon in the hands, the other one holstered (rifle slung, knife on the hip)
local function applyHolster(character: Model, equipped: string)
	local rifle = character:FindFirstChild("VantageWorldWeapon")
	local gm = rifle and rifle.PrimaryPart and rifle.PrimaryPart:FindFirstChild("VantageGunMotor")
	local torso = character:FindFirstChild("UpperTorso")
	if gm and torso then
		local held = Config.Weapons[rifle:GetAttribute("WeaponId") or ""]
		gm.Part0 = torso
		gm.C0 = if held and equipped == held.Id then held.ThirdPerson.Hold else (held and held.ThirdPerson.Sling or RIFLE_SLING)
	end
	local knife = character:FindFirstChild("VantageWorldKnife")
	local km = knife and knife.PrimaryPart and knife.PrimaryPart:FindFirstChild("VantageKnifeMotor")
	if km then
		local hand = character:FindFirstChild("RightHand")
		local lower = character:FindFirstChild("LowerTorso")
		local gripAtt = hand and hand:FindFirstChild("RightGripAttachment")
		if equipped == "Knife" and hand then
			km.Part0 = hand
			km.C0 = if gripAtt then gripAtt.CFrame else CFrame.identity
		elseif lower then
			km.Part0 = lower
			km.C0 = KNIFE_HIP
		end
	end
end

local function setEquippedAttributes(character: Model, id: string)
	local w = Config.Weapons[id]
	if w.Kind == "Gun" then
		local cur = character:FindFirstChild("VantageWorldWeapon")
		if not cur or cur:GetAttribute("WeaponId") ~= id then
			attachGun(character, w)
		end
	end
	character:SetAttribute("VantageWeapon", id)
	character:SetAttribute("VantageSpeedMult", w.SpeedMultiplier or 1)
	character:SetAttribute("VantageADS", false)
	applyHolster(character, id)
end

-- ─── deaths ───────────────────────────────────────────────────────────────
local function chooseDeathStyle(character: Model): string
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return "Back"
	end
	if character:GetAttribute("LastHitHead") then
		return "Crumple"
	end
	local dir = character:GetAttribute("LastHitDir")
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then
		return "Back"
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1e-3 then
		return "Back"
	end
	dir = dir.Unit
	local along = root.CFrame.LookVector:Dot(dir)
	if along < -0.4 then
		return "Back" -- shot from the front: pushed backwards
	elseif along > 0.4 then
		return "Front"
	end
	return if root.CFrame.RightVector:Dot(dir) > 0 then "SpinR" else "SpinL"
end

local function dropModel(model: Model?, root: BasePart?)
	if not model then
		return
	end
	local primary = model.PrimaryPart
	if not primary then
		model:Destroy()
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and (d.Name == "VantageGunMotor" or d.Name == "VantageKnifeMotor") then
			d:Destroy()
		end
	end
	primary.CanCollide = true
	primary.Massless = false
	model.Parent = dropsFolder()
	pcall(function()
		primary:SetNetworkOwner(nil)
	end)
	local v = if root then root.AssemblyLinearVelocity else Vector3.zero
	primary.AssemblyLinearVelocity = Vector3.new(v.X * 0.4, 6, v.Z * 0.4)
	primary.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6
	task.delay(S.DropLifetime - 0.6, function()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
	end)
	Debris:AddItem(model, S.DropLifetime)
end

local function onCharacterDied(character: Model, player: Player?)
	-- the killer's equipped elimination effect plays on the body (EffectCatalog, 2026-11-14);
	-- EffectCatalog.ReplaceDeath = false: back to the Crimson Core Overload / directional collapse
	local style = if CoreOverload.Enabled then "Overload" else chooseDeathStyle(character)
	if EffectCatalog.ReplaceDeath then
		style = "Elim"
		local fx = EffectCatalog.Default
		local killerId = character:GetAttribute("VantageKiller")
		local killer = if type(killerId) == "number" then Players:GetPlayerByUserId(killerId) else nil
		if killer and killer ~= player then
			fx = EffectCatalog.ForPlayer(killer)
		end
		character:SetAttribute("VantageDeathFX", fx)
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local equipped = character:GetAttribute("VantageWeapon")
	local rifle = character:FindFirstChild("VantageWorldWeapon")
	local knife = character:FindFirstChild("VantageWorldKnife")
	if equipped == "Knife" then
		dropModel(knife, root)
		if rifle then
			rifle:Destroy()
		end
	else
		dropModel(rifle, root)
		if knife then
			knife:Destroy()
		end
	end
	character:SetAttribute("VantageWeapon", nil)
	character:SetAttribute("VantageADS", false)
	character:SetAttribute("VantageAction", nil)
	-- kill credit / streak / elimination broadcast, then victim feedback: who / where / with what
	local record = EliminationService.OnDeath(character, player)
	if player then
		EventRemote:FireClient(player, "Died", record.KillerName, record.KillerPosition, record.Weapon, record.Headshot,
			record.Distance, record.KillerModel)
	end
	-- controlled collapse: keep the joints rigid and plant the root on the ground; every client
	-- then plays the same keyframed death (DeathPresenter). Runs after the engine's own
	-- death handling (which disables the avatar joints for a physics ragdoll).
	task.defer(function()
		if not root or not character.Parent then
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, dropsFolder() }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(S.DeathAnchorMaxDrop + 3), 0), params)
		if hit and hum then
			local standHeight = hum.HipHeight + root.Size.Y / 2
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude < 1e-3 then
				flat = Vector3.new(0, 0, -1)
			end
			local pos = Vector3.new(root.Position.X, hit.Position.Y + standHeight, root.Position.Z)
			root.CFrame = CFrame.lookAt(pos, pos + flat)
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
		for _, d in character:GetDescendants() do
			if d:IsA("AnimationConstraint") then
				d.Enabled = true
			end
		end
		character:SetAttribute("VantageDeath", string.format("%s:%.3f", style, Workspace:GetServerTimeNow()))
	end)
end
WeaponService.OnCharacterDied = onCharacterDied

-- ─── character lifecycle ──────────────────────────────────────────────────
local function onCharacter(player: Player, character: Model)
	local st = states[player]
	if not st then
		return
	end
	st.Ammo = {}
	st.List = LoadoutPresets.ActiveList(player) -- knife + the selected preset's 3 guns
	for _, id in st.List do
		local w = Config.Weapons[id]
		if w.Kind == "Gun" then
			st.Ammo[id] = newAmmo(w)
		end
	end
	st.Reloading = false
	st.ReloadingId = nil
	st.ReloadToken += 1
	st.EquippedAt = os.clock()
	st.Equipped = st.List[2] or Config.SpawnWeapon()
	st.NextMeleeAt = 0
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		-- keep the joints on death: the death animation (DeathPresenter) poses them instead of
		-- the engine destroying them for a physics ragdoll
		hum.BreakJointsOnDeath = false
	end
	ShieldService.Setup(character)
	if Config.Weapons.Knife then
		attachKnife(character, Config.Weapons.Knife)
	end
	setEquippedAttributes(character, st.Equipped) -- attaches the first gun
	character:SetAttribute("VantageAim", 0)
	if player.Team == nil and not player:GetAttribute("InTutorial") then -- trainees (TutorialService) are armed
		-- lobby (LobbyService / Workspace.HyperLobby): equipped gun strapped across the back, knife on
		-- the hip, nothing usable. ThirdPersonRig skips holstered characters (no aim stance).
		character:SetAttribute("VantageHolstered", true)
		applyHolster(character, "")
	end
	if hum then
		hum.Died:Connect(function()
			st.ReloadToken += 1 -- death cancels any reload
			st.Reloading = false
			onCharacterDied(character, player)
		end)
	end
	for id in st.Ammo do
		sendAmmo(player, st, "Spawn", id)
	end
end

local function onPlayer(player: Player)
	states[player] = {
		Equipped = Config.SpawnWeapon(),
		Ammo = {},
		Reloading = false,
		ReloadingId = nil,
		ReloadToken = 0,
		MsgWindow = os.clock(),
		MsgCount = 0,
		EquippedAt = 0,
		NextMeleeAt = 0,
		LastAimAt = 0,
	}
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function rateLimited(st): boolean
	local now = os.clock()
	if now - st.MsgWindow >= 1 then
		st.MsgWindow = now
		st.MsgCount = 0
	end
	st.MsgCount += 1
	return st.MsgCount > S.RemoteRateLimit
end

local function aliveCharacter(player: Player): (Model?, Humanoid?)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not c or not hum or hum.Health <= 0 then
		return nil, nil
	end
	return c, hum
end

local function notifyVictim(result, sourcePos: Vector3)
	local vp = result and result.VictimPlayer
	if vp and result.Damage > 0 then
		EventRemote:FireClient(vp, "Damaged", sourcePos, result.Damage)
	end
end

-- ─── fire ─────────────────────────────────────────────────────────────────
-- ─── energy heat (ER-04 Arc) ─────────────────────────────────────────────
-- Heat drains CoolRate/s once CoolDelay has passed since the last shot; reaching 1 locks the
-- weapon for OverheatLock seconds, after which it is vented to 0. Server times are slightly
-- forgiving so client prediction never gets a legit shot rejected.
local function currentHeat(a, w, now: number): number
	local H = w.Heat
	if a.LockedUntil > 0 then
		if now >= a.LockedUntil then
			a.LockedUntil = 0
			a.Heat = 0
			a.HeatAt = now
		end
		return a.Heat
	end
	local from = math.max(a.HeatAt, a.LastShotAt + H.CoolDelay)
	if now > from then
		a.Heat = math.max(0, a.Heat - H.CoolRate * (now - from))
		a.HeatAt = now
	end
	return a.Heat
end

-- ─── projectiles (server-simulated, stepped with the same hit validation as bullets) ─
local projectiles = {}
-- 2026-11-18: Projectile.Splash = { Radius, Inner, Edge, Scale }: line-of-sight blast damage with falloff
-- (GL-4 Havoc). The direct-hit victim already took the impact damage and is skipped. Everyone sees the
-- frag-grenade blast (Remotes.Grenade "Explode").
local GrenadeRemote = Remotes:FindFirstChild("Grenade")
local function splash(p, pos: Vector3, directChar, tag)
	local W = p.Weapon
	local S = W.Projectile.Splash
	if GrenadeRemote then
		GrenadeRemote:FireAllClients("Explode", pos)
	end
	if not p.Player.Parent then
		return
	end
	local targets = HitValidation.TargetCharacters()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = targets
	local origin = pos + Vector3.new(0, 0.4, 0)
	for _, c in targets do
		if c == directChar or c == p.Player.Character or c:GetAttribute("VehicleHidden") then
			continue
		end
		local hum = c:FindFirstChildOfClass("Humanoid")
		local body = (c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart")) :: BasePart?
		local head = c:FindFirstChild("Head") :: BasePart?
		if not hum or hum.Health <= 0 or not body then
			continue
		end
		local d = (body.Position - pos).Magnitude
		if d >= S.Radius then
			continue
		end
		local seen = Workspace:Raycast(origin, body.Position - origin, rp) == nil
		if not seen and head then
			seen = Workspace:Raycast(origin, head.Position - origin, rp) == nil
		end
		if not seen then
			continue
		end
		local f = if d <= (S.Inner or 0) then 1 else 1 - (1 - (S.Edge or 0.25)) * math.clamp((d - (S.Inner or 0)) / (S.Radius - (S.Inner or 0)), 0, 1)
		local dir = if d > 0.1 then (body.Position - pos).Unit else Vector3.yAxis
		local result = DamageService.Apply(p.Player, W, {
			Character = c, Humanoid = hum, IsHead = false, IsLimb = false,
			Distance = d, Position = body.Position, Direction = dir,
		}, W.Damage * (S.Scale or 1) * f)
		if result and not result.Blocked and result.Damage > 0 then
			WeaponService.Stats.Hits += 1
			WeaponService.Stats.Damage += result.Damage
			EventRemote:FireClient(p.Player, "Confirm", {
				Damage = result.Damage, Headshot = false, Killed = result.Killed, Blocked = false,
				VictimName = result.VictimName, Position = body.Position, Seq = p.Seq, Weapon = W.Id,
				ShieldDamage = result.ShieldDamage, ShieldBroken = result.ShieldBroken, Victim = c,
			})
			notifyVictim(result, pos)
		end
	end
end
local function stepProjectiles(dt: number)
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local P = p.Weapon.Projectile
		-- 2026-11-18: Projectile.Gravity (studs/s^2) bends the path (Quill bolts drop, Havoc rounds lob)
		p.Vel = p.Vel or p.Dir * P.Speed
		local stepLen = math.min(p.Vel.Magnitude * dt, p.Weapon.MaxRange - p.Travelled)
		p.Dir = p.Vel.Unit
		-- a shooter who has died deals no further damage, even with bolts still in flight
		local dead = not p.Player.Parent or aliveCharacter(p.Player) == nil
		local done = stepLen <= 0.01 or dead
		if done and not dead and P.Splash then
			splash(p, p.Pos, nil, "air") -- end of its flight: airburst
		end
		if not done then
			-- first step rewinds to the shooter's view time; later steps use current positions
			local hit = HitValidation.Cast(p.Player, p.Pos, p.Dir, stepLen, if p.First then p.ClientTime else nil)
			p.First = false
			if hit.Kind == "None" then
				p.Pos += p.Dir * stepLen
				p.Travelled += stepLen
				if P.Gravity then
					p.Vel += Vector3.new(0, -P.Gravity * dt, 0)
				end
			else
				done = true
				if P.Splash then
					task.defer(splash, p, hit.Position - p.Dir * 0.3, if hit.Kind == "Character" then hit.Character else nil, "hit" .. hit.Kind)
				end
				if hit.Kind == "Character" then
					hit.Distance = p.Travelled + hit.Distance
					local result = DamageService.Apply(p.Player, p.Weapon, hit)
					if result then
						WeaponService.Stats.Hits += 1
						WeaponService.Stats.Damage += result.Damage
						EventRemote:FireClient(p.Player, "Confirm", {
							Damage = result.Damage, Headshot = result.Headshot, Killed = result.Killed,
							Blocked = result.Blocked, VictimName = result.VictimName, Position = hit.Position,
							Seq = p.Seq, Weapon = p.Weapon.Id, ShieldDamage = result.ShieldDamage, ShieldBroken = result.ShieldBroken, Victim = hit.Character,
						})
						notifyVictim(result, p.Origin)
					end
				elseif hit.Kind == "World" then
					hit.Distance = p.Travelled + hit.Distance
					DamageService.ApplyToVehicle(p.Player, p.Weapon, hit)
				end
			end
		end
		if done then
			table.remove(projectiles, i)
		end
	end
end

-- one validated hitscan ray -> damage + confirm; returns the hit (for the effects broadcast)
local function hitscan(player: Player, weapon, origin: Vector3, dir: Vector3, clientTime: number, seq)
	local hit = HitValidation.Cast(player, origin, dir, weapon.MaxRange, clientTime)
	if hit.Kind == "Character" then
		local result = DamageService.Apply(player, weapon, hit)
		if result then
			WeaponService.Stats.Hits += 1
			WeaponService.Stats.Damage += result.Damage
			EventRemote:FireClient(player, "Confirm", {
				Damage = result.Damage, Headshot = result.Headshot, Killed = result.Killed,
				Blocked = result.Blocked, VictimName = result.VictimName, Position = hit.Position,
				Seq = seq, Weapon = weapon.Id, ShieldDamage = result.ShieldDamage, ShieldBroken = result.ShieldBroken, Victim = hit.Character,
			})
			notifyVictim(result, origin)
		end
	elseif hit.Kind == "World" then
		DamageService.ApplyToVehicle(player, weapon, hit)
	end
	return hit
end

-- shotgun: every pellet is its own validated ray; damage is summed per victim and applied once
local function pellets(player: Player, weapon, origin: Vector3, dir: Vector3, clientTime: number, seq, seed: number)
	local P = weapon.Pellet
	local dirs = WeaponMath.PelletDirs(dir, P.Count, P.Spread, seed)
	local perVictim, order, hits = {}, {}, {}
	for _, d in dirs do
		local hit = HitValidation.Cast(player, origin, d, weapon.MaxRange, clientTime)
		table.insert(hits, hit)
		if hit.Kind == "World" then
			DamageService.ApplyToVehicle(player, weapon, hit) -- each pellet on a vehicle hull
		end
		if hit.Kind == "Character" and hit.Character then
			local v = perVictim[hit.Character]
			if not v then
				v = { Hit = hit, Amount = 0, Head = false, Pellets = 0 }
				perVictim[hit.Character] = v
				table.insert(order, hit.Character)
			end
			v.Amount += WeaponMath.Damage(weapon, hit.IsHead, hit.IsLimb, hit.Distance)
			v.Head = v.Head or hit.IsHead
			v.Pellets += 1
		end
	end
	for _, c in order do
		local v = perVictim[c]
		v.Hit.IsHead = v.Head
		local result = DamageService.Apply(player, weapon, v.Hit, v.Amount)
		if result then
			WeaponService.Stats.Hits += 1
			WeaponService.Stats.Damage += result.Damage
			EventRemote:FireClient(player, "Confirm", {
				Damage = result.Damage, Headshot = result.Headshot, Killed = result.Killed,
				Blocked = result.Blocked, VictimName = result.VictimName, Position = v.Hit.Position,
				Seq = seq, Weapon = weapon.Id, ShieldDamage = result.ShieldDamage, ShieldBroken = result.ShieldBroken,
				Pellets = v.Pellets, Victim = c,
			})
			notifyVictim(result, origin)
		end
	end
	return hits
end

local function onFire(player: Player, clientTime: any, origin: any, direction: any, seq: any, seed: any)
	local st = states[player]
	if not st or rateLimited(st) then
		return reject(st, "Spam")
	end
	if type(clientTime) ~= "number" or not WeaponMath.IsFiniteVector(origin) or not WeaponMath.IsFiniteVector(direction) then
		return reject(st, "BadArgs")
	end
	if direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then
		return reject(st, "BadDirection")
	end
	local character = aliveCharacter(player)
	if not character then
		return reject(st, "Dead")
	end
	if character:GetAttribute("VantageHolstered") then
		return reject(st, "Lobby") -- weapons are strapped away in the lobby
	end
	if character:GetAttribute("VantageHanging") then
		return reject(st, "Hanging") -- hanging under the dropship (AircraftService sets this)
	end
	if character:GetAttribute("InVehicle") then
		return reject(st, "InVehicle") -- seated: the vehicle's weapon only (VehicleService)
	end
	if (character:GetAttribute("Status_FrozenUntil") or 0) > workspace:GetServerTimeNow() then
		return reject(st, "Frozen") -- 2026-11-20: Helheim freeze (StatusService)
	end
	local weapon = Config.Weapons[st.Equipped]
	local a = st.Ammo[st.Equipped]
	if not weapon or weapon.Kind ~= "Gun" or not a then
		return reject(st, "NotEquipped")
	end
	if type(seq) == "number" and seq == seq and seq > a.LastSeq and seq < a.LastSeq + 10000 then
		a.LastSeq = math.floor(seq)
	end
	local now = os.clock()
	if now - st.EquippedAt < weapon.EquipTime * 0.6 then
		sendAmmo(player, st)
		return reject(st, "Equipping")
	end
	if st.Reloading then
		sendAmmo(player, st)
		return reject(st, "Reloading")
	end
	if weapon.Energy then
		if currentHeat(a, weapon, now) >= 1 or a.LockedUntil > 0 then
			return reject(st, "Overheated")
		end
	elseif a.Mag <= 0 then
		sendAmmo(player, st)
		return reject(st, "Empty")
	end
	-- fire rate: token bucket refilled at RPM * tolerance, small burst for network jitter
	local rate = weapon.RPM / 60 * S.FireRateTolerance
	a.Tokens = math.min(S.FireBurstTokens, a.Tokens + (now - a.LastRefill) * rate)
	a.LastRefill = now
	if a.Tokens < 1 then
		sendAmmo(player, st)
		return reject(st, "FireRate")
	end
	-- burst: at most Count rounds, then the burst cooldown must pass (20% latency allowance)
	if weapon.Trigger == "Burst" then
		local B = weapon.Burst
		local gap = now - a.LastShotAt
		if a.BurstCount >= B.Count and gap < B.Cooldown * 0.8 then
			sendAmmo(player, st)
			return reject(st, "BurstCooldown")
		end
		if gap > (60 / weapon.RPM) * 2.2 then
			a.BurstCount = 0
		end
		a.BurstCount += 1
	end
	a.Tokens -= 1
	if weapon.Energy then
		currentHeat(a, weapon, now)
		a.Heat = math.min(1, a.Heat + weapon.Heat.PerShot)
		a.HeatAt = now
		if a.Heat >= 0.999 then
			a.LockedUntil = now + weapon.Heat.OverheatLock * 0.85
		end
	else
		a.Mag -= 1
	end
	a.LastShotAt = now

	-- origin must be the shooter's own head area (camera), never an arbitrary point
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return reject(st, "NoHead")
	end
	if (origin - head.Position).Magnitude > S.MaxOriginDistance then
		WeaponService.Stats.Rejected.OriginClamped = (WeaponService.Stats.Rejected.OriginClamped or 0) + 1
		origin = head.Position
	end

	WeaponService.Stats.Accepted += 1
	direction = direction.Unit

	-- resolve the shot by its fire model; collect the visible end points for the broadcast
	local visuals = {}
	if weapon.Shot == "Pellet" then
		if type(seed) ~= "number" or seed ~= seed or seed < 0 or seed > 2 ^ 31 then
			seed = 0
		end
		for i, hit in pellets(player, weapon, origin, direction, clientTime, seq, math.floor(seed)) do
			table.insert(visuals, { hit, if i > 1 then { Quiet = true } else nil })
		end
	elseif weapon.Shot == "Projectile" then
		table.insert(projectiles, {
			Player = player, Weapon = weapon, Origin = origin, Pos = origin, Dir = direction,
			Travelled = 0, ClientTime = clientTime, First = true, Seq = seq,
		})
		-- remote clients animate the bolt toward where it is currently heading
		local preview = HitValidation.Cast(player, origin, direction, weapon.MaxRange, nil)
		-- arcing rounds: remote clients simulate the same arc from the muzzle (Dir), not a straight line
		table.insert(visuals, { preview, { Projectile = weapon.Projectile.Speed, Dir = if weapon.Projectile.Gravity then direction else nil } })
	else
		table.insert(visuals, { hitscan(player, weapon, origin, direction, clientTime, seq), nil })
	end

	-- replicate the shot to everyone else (effects only); C3: one FireClient per player per
	-- shot, carrying each pellet's end in fire order (was one message per pellet per player)
	local pelletEnds = table.create(#visuals)
	for i, v in visuals do
		local hit, extra = v[1], v[2]
		pelletEnds[i] = {
			Position = hit.Position,
			Normal = hit.Normal,
			Kind = hit.Kind,
			Material = if hit.Material then hit.Material.Name else nil,
			Extra = extra,
		}
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			EventRemote:FireClient(other, "Shot", character, pelletEnds)
		end
	end
	return true
end

-- ─── melee ────────────────────────────────────────────────────────────────
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The server picks the target: closest to the aim within range + cone + line of sight.
local function meleeHit(attacker: Model, attackerPlayer: Player?, kind: string, lookDir: Vector3, clientTime: number?)
	local w = Config.Weapons.Knife
	local spec = w[kind]
	local root = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = attacker:FindFirstChild("Head") :: BasePart?
	if not root or not head then
		return nil
	end
	local now = Workspace:GetServerTimeNow()
	local rewindT = now
	if type(clientTime) == "number" and clientTime == clientTime then
		rewindT = math.clamp(clientTime - S.InterpolationDelay, now - S.MaxRewind, now)
	end
	local best, bestScore, bestPos = nil, math.huge, nil
	local cone = math.cos(math.rad(spec.ConeAngle + 8))
	for _, c in HitValidation.TargetCharacters() do
		if c ~= attacker then
			local hum = c:FindFirstChildOfClass("Humanoid")
			local croot = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			local friendly = attackerPlayer and DamageService.IsFriendly(attackerPlayer, c) and not Config.FriendlyFire
			if hum and croot and hum.Health > 0 and not friendly then
				local poses = { croot.Position }
				local rw = HitValidation.RootAt(c, rewindT)
				if rw then
					table.insert(poses, rw.Position)
				end
				for _, pos in poses do
					local chest = pos + Vector3.new(0, 0.6, 0)
					local dist = (pos - root.Position).Magnitude - 1.0
					if dist <= spec.Range + S.MeleeRangeTolerance then
						local to = chest - head.Position
						local dot = if to.Magnitude > 1e-3 then to.Unit:Dot(lookDir) else 1
						if dot >= cone or dist < 1.2 then
							local score = (1 - dot) * 4 + dist * 0.05
							if score < bestScore then
								best, bestScore, bestPos = c, score, chest
							end
						end
					end
				end
			end
		end
	end
	if not best then
		return nil
	end
	-- line of sight (walls block knives)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = HitValidation.TargetCharacters()
	local blocked = Workspace:Raycast(head.Position, bestPos - head.Position, params)
	if blocked then
		return nil
	end
	local amount = spec.Damage
	local backstab = false
	if kind == "Secondary" and spec.BackstabDamage then
		local vroot = best:FindFirstChild("HumanoidRootPart") :: BasePart
		local toVictim = flat(vroot.Position - root.Position)
		if toVictim.Magnitude > 1e-3 and flat(vroot.CFrame.LookVector):Dot(toVictim.Unit) > spec.BackstabDot then
			amount = spec.BackstabDamage
			backstab = true
		end
	end
	return {
		Character = best,
		Humanoid = best:FindFirstChildOfClass("Humanoid"),
		IsHead = false,
		IsLimb = false,
		Distance = (bestPos - head.Position).Magnitude,
		Position = bestPos,
		Direction = flat(bestPos - head.Position).Unit,
		Amount = amount,
		Backstab = backstab,
	}
end
WeaponService.MeleeHit = meleeHit

local function onMelee(player: Player, st, kind: any, clientTime: any, lookDir: any)
	if st.Equipped ~= "Knife" then
		return reject(st, "MeleeNotEquipped")
	end
	if kind ~= "Primary" and kind ~= "Secondary" then
		return reject(st, "MeleeKind")
	end
	if not WeaponMath.IsFiniteVector(lookDir) or lookDir.Magnitude < 0.5 or lookDir.Magnitude > 1.5 then
		return reject(st, "MeleeBadArgs")
	end
	lookDir = lookDir.Unit
	local character = aliveCharacter(player)
	if not character then
		return reject(st, "Dead")
	end
	if character:GetAttribute("VantageHanging") then
		return reject(st, "Hanging")
	end
	if character:GetAttribute("InVehicle") then
		return reject(st, "InVehicle")
	end
	local w = Config.Weapons.Knife
	local spec = w[kind]
	local now = os.clock()
	if now - st.EquippedAt < w.EquipTime * 0.6 then
		return reject(st, "Equipping")
	end
	if now < st.NextMeleeAt then
		return reject(st, "MeleeCooldown")
	end
	st.NextMeleeAt = now + spec.Cooldown - S.MeleeCooldownTolerance
	-- the body faces the camera yaw in first person: a look direction far from it is forged
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local fl = flat(lookDir)
	if root and fl.Magnitude > 0.2 and flat(root.CFrame.LookVector).Unit:Dot(fl.Unit) < math.cos(math.rad(75)) then
		return reject(st, "MeleeLook")
	end
	local hit = meleeHit(character, player, kind, lookDir, if type(clientTime) == "number" then clientTime else nil)
	local result = hit and DamageService.Apply(player, w, hit, hit.Amount)
	if result then
		WeaponService.Stats.MeleeHits += 1
		WeaponService.Stats.Damage += result.Damage
		EventRemote:FireClient(player, "Confirm", {
			Damage = result.Damage,
			Headshot = false,
			Killed = result.Killed,
			Blocked = result.Blocked,
			VictimName = result.VictimName,
			Position = hit.Position,
			Melee = true,
			Kind = kind,
			Backstab = hit.Backstab,
			Weapon = w.Id,
			ShieldDamage = result.ShieldDamage,
			ShieldBroken = result.ShieldBroken,
			Victim = hit.Character,
		})
		if root then
			notifyVictim(result, root.Position)
		end
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			EventRemote:FireClient(other, "Melee", character, if result then hit.Position else nil, result ~= nil)
		end
	end
	return true
end

-- ─── actions ──────────────────────────────────────────────────────────────
local function startReload(player: Player, st, character: Model)
	local id = st.Equipped
	local weapon = Config.Weapons[id]
	local a = st.Ammo[id]
	-- energy weapons: R vents the heat (locked for VentTime, then cold)
	if weapon and weapon.Energy and a then
		local now = os.clock()
		if a.LockedUntil == 0 and currentHeat(a, weapon, now) > 0 then
			a.Heat = 1
			a.LockedUntil = now + weapon.Heat.VentTime * 0.85
			setAction(character, "Reload")
		end
		return
	end
	if not a or st.Reloading or a.Mag >= weapon.MagazineSize or a.Reserve <= 0 then
		sendAmmo(player, st, "ReloadDenied")
		return
	end
	st.Reloading = true
	st.ReloadingId = id
	st.ReloadToken += 1
	local token = st.ReloadToken
	setAction(character, "Reload")
	-- shotgun: shells go in one at a time; firing (CancelReload) keeps the shells already loaded
	if weapon.ReloadMode == "Shell" then
		local sh = weapon.Shell
		task.spawn(function()
			task.wait(math.max(0.05, sh.Start - S.ReloadLatencyAllowance))
			while states[player] == st and st.ReloadToken == token and st.Reloading and st.Equipped == id do
				if a.Mag >= weapon.MagazineSize or a.Reserve <= 0 then
					break
				end
				task.wait(sh.Each * 0.92)
				if states[player] ~= st or st.ReloadToken ~= token or not st.Reloading or st.Equipped ~= id then
					return
				end
				a.Mag += 1
			end
			if states[player] == st and st.ReloadToken == token and st.Reloading then
				sendAmmo(player, st, "Reloaded", id)
				st.Reloading = false
				st.ReloadingId = nil
			end
		end)
		return
	end
	task.delay(math.max(0.1, weapon.ReloadTime - S.ReloadLatencyAllowance), function()
		if states[player] ~= st or st.ReloadToken ~= token or not st.Reloading or st.Equipped ~= id then
			return
		end
		local take = math.min(weapon.MagazineSize - a.Mag, a.Reserve)
		a.Mag += take
		sendAmmo(player, st, "Reloaded", id)
		st.Reloading = false
		st.ReloadingId = nil
	end)
end

local function onAction(player: Player, action: any, a: any, b: any, c: any)
	local st = states[player]
	if not st or rateLimited(st) then
		return
	end
	if type(action) ~= "string" then
		return reject(st, "BadAction")
	end
	local character = aliveCharacter(player)
	if not character then
		return
	end
	if character:GetAttribute("VantageHolstered") then
		return -- lobby: no reload / equip / inspect / melee
	end
	if action == "Reload" then
		startReload(player, st, character)
	elseif action == "CancelReload" then
		if st.Reloading then
			st.ReloadToken += 1
			character:SetAttribute("VantageAction", nil)
			sendAmmo(player, st, "ReloadCancelled", st.ReloadingId)
			st.Reloading = false
			st.ReloadingId = nil
		else
			sendAmmo(player, st, "Sync")
		end
	elseif action == "Equip" then
		if type(a) ~= "string" or not table.find(st.List or Config.Loadout, a) or st.Equipped == a then
			return
		end
		if st.Reloading then
			st.ReloadToken += 1
			sendAmmo(player, st, "ReloadCancelled", st.ReloadingId)
			st.Reloading = false
			st.ReloadingId = nil
		end
		st.Equipped = a
		st.EquippedAt = os.clock()
		setEquippedAttributes(character, a)
		setAction(character, "Equip")
	elseif action == "Anim" then
		local w = Config.Weapons[st.Equipped]
		local list = ANIM_WHITELIST[st.Equipped] or (if w and w.Kind == "Gun" then GUN_ANIMS else nil)
		if a == "Stop" then
			-- inspect cancelled by fire / aim / reload / switch: clear it for everyone
			local cur = character:GetAttribute("VantageAction")
			if type(cur) == "string" and string.sub(cur, 1, 8) == "Inspect:" then
				character:SetAttribute("VantageAction", nil)
			end
		elseif type(a) == "string" and list and list[a] and not st.Reloading then
			setAction(character, a)
		end
	elseif action == "Melee" then
		onMelee(player, st, a, b, c)
	else
		reject(st, "UnknownAction")
	end
end

local function onAim(player: Player, pitch: any, ads: any)
	local st = states[player]
	if not st then
		return
	end
	local now = os.clock()
	if now - st.LastAimAt < 0.5 / S.AimSendRate then
		return -- over the allowed rate: drop
	end
	st.LastAimAt = now
	if type(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local character = aliveCharacter(player)
	if not character or character:GetAttribute("VantageHolstered") then
		return
	end
	character:SetAttribute("VantageAim", math.clamp(math.floor(pitch * 2 + 0.5) / 2, -85, 85))
	local held = Config.Weapons[st.Equipped]
	character:SetAttribute("VantageADS", ads == true and held ~= nil and held.ADS ~= nil)
end

-- ─── Studio-only test helpers (training dummies) ─────────────────────────
function WeaponService.SpawnDummy(position: Vector3, name: string?, armed: boolean?, team: string?): Model?
	if not RunService:IsStudio() and Workspace:GetAttribute("LiveBots") ~= true then -- 2026-11-19: live bot fill
		return nil
	end
	local desc = Instance.new("HumanoidDescription")
	local ok, dummy = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not dummy then
		return nil
	end
	dummy.Name = name or "TrainingDummy"
	dummy:PivotTo(CFrame.new(position))
	if team then
		dummy:SetAttribute("Team", team)
	end
	CollectionService:AddTag(dummy, "VantageDummy")
	dummy.Parent = Workspace
	ShieldService.Setup(dummy)
	local hum = dummy:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		hum.Died:Connect(function()
			onCharacterDied(dummy, nil)
		end)
	end
	if armed then
		-- emulates a remote player: same world models + attributes the real flow uses
		task.spawn(function()
			attachKnife(dummy, Config.Weapons.Knife)
			setEquippedAttributes(dummy, Config.DefaultWeapon)
			dummy:SetAttribute("VantageAim", 0)
		end)
	end
	return dummy
end

function WeaponService.Start()
	HitValidation.Start()
	ShieldService.Start()
	DamageService.MatchFolder()
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
	end)
	FireRemote.OnServerEvent:Connect(onFire)
	RunService.Heartbeat:Connect(stepProjectiles)
	ActionRemote.OnServerEvent:Connect(onAction)
	AimRemote.OnServerEvent:Connect(onAim)
	-- debug/test hooks (server-only BindableFunction, not reachable from clients)
	local hook = script.Parent:FindFirstChild("WeaponDebug") or Instance.new("BindableFunction")
	hook.Name = "WeaponDebug"
	hook.OnInvoke = function(cmd, ...)
		local args = { ... }
		if cmd == "Stats" then
			return WeaponService.Stats
		elseif cmd == "State" then
			local st = states[args[1]]
			local a = st and st.Ammo[st.Equipped]
			return st and { Mag = a and a.Mag, Reserve = a and a.Reserve, Reloading = st.Reloading, Equipped = st.Equipped } or nil
		elseif cmd == "SpawnDummy" then
			return WeaponService.SpawnDummy(args[1], args[2], args[3], args[4])
		elseif cmd == "DummyEquip" then
			setEquippedAttributes(args[1], args[2])
			setAction(args[1], "Equip")
		elseif cmd == "DummyAim" then
			args[1]:SetAttribute("VantageAim", args[2])
			args[1]:SetAttribute("VantageADS", args[3] == true)
		elseif cmd == "DummyAction" then
			setAction(args[1], args[2])
		elseif cmd == "DummyShoot" then
			-- broadcast a shot from a dummy exactly like another player's shot
			local d = args[1]
			local head = d:FindFirstChild("Head")
			local target: Vector3 = args[2]
			if head then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { d }
				local res = Workspace:Raycast(head.Position, (target - head.Position).Unit * 500, params)
				local pos = if res then res.Position else head.Position + (target - head.Position).Unit * 500
				for _, other in Players:GetPlayers() do
					EventRemote:FireClient(other, "Shot", d, pos, if res then res.Normal else Vector3.yAxis, if res then "World" else "None", if res then res.Material.Name else nil)
				end
			end
		elseif cmd == "DummyMelee" then
			local d = args[1]
			for _, other in Players:GetPlayers() do
				EventRemote:FireClient(other, "Melee", d, nil, false)
			end
		elseif cmd == "Kill" then
			local c: Model = args[1]
			c:SetAttribute("LastHitHead", args[2] == true)
			if typeof(args[3]) == "Vector3" then
				c:SetAttribute("LastHitDir", args[3])
			end
			local h = c:FindFirstChildOfClass("Humanoid")
			if h then
				h.Health = 0
			end
		elseif cmd == "KillBy" then
			-- a training dummy eliminates a character (tests kill credit + the death replay)
			local victim: Model = args[1]
			EliminationService.SetDebugKiller(victim, args[2])
			victim:SetAttribute("LastHitHead", args[3] == true)
			victim:SetAttribute("LastHitWeapon", Config.DefaultWeapon)
			victim:SetAttribute("LastHitKind", "Gun")
			victim:SetAttribute("LastHitExplosive", false)
			local h = victim:FindFirstChildOfClass("Humanoid")
			if h then
				h.Health = 0
			end
		elseif cmd == "DamagePlayer" then
			-- hurt a player from a source position (tests the health HUD / damage arcs)
			local plr: Player = args[1]
			local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
			if h then
				h:TakeDamage(args[2])
				EventRemote:FireClient(plr, "Damaged", args[3], args[2])
			end
		elseif cmd == "DamageShielded" then
			-- like a weapon hit: shield first, overflow into health (tests shield HUD / FX)
			local plr: Player = args[1]
			local c = plr.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if h then
				local toHealth, absorbed, broke = ShieldService.Absorb(c, args[2])
				if toHealth > 0 then
					h:TakeDamage(toHealth)
				end
				EventRemote:FireClient(plr, "Damaged", args[3], args[2])
				return { Absorbed = absorbed, ToHealth = toHealth, Broke = broke }
			end
		end
		return nil
	end
	hook.Parent = script.Parent
end

return WeaponService
