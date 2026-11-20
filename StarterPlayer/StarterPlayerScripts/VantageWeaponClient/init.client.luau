--[[
	VANTAGE — Weapon / combat client bootstrap
	Session level: input, effects, HUD, settings (+ menu), team outlines, third-person rig for
	other players, death presentation, elimination effects, death replay. Per character life: Loadout (VX-01 + VK-7 controllers).

	Frame order (together with VantageMovementClient):
		Input + 1    VantageMovement      (movement)
		Camera - 1   VantageRecoilUndo    remove last frame's recoil offset
		Camera       Roblox first-person camera
		Camera + 1   VantageCamera        movement FOV / tilt / dip / bob
		Camera + 2   VantageWeapon        recoil, weapons, viewmodels, FOV / sensitivity, HUD
		Stepped      ThirdPersonRig / DeathPresenter (other characters' joints)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Weapons = Vantage:WaitForChild("Weapons")
local Remotes = Vantage:WaitForChild("Remotes")
Remotes:WaitForChild("WeaponFire")
Remotes:WaitForChild("WeaponAction")
local EventRemote = Remotes:WaitForChild("WeaponEvent") :: RemoteEvent
Weapons:WaitForChild("Assets"):WaitForChild("Knife")
Vantage:WaitForChild("SettingsConfig")

local WeaponConfig = require(Weapons:WaitForChild("WeaponConfig"))
local WeaponInput = require(script.WeaponInput)
local WeaponEffects = require(script.WeaponEffects)
local Hud = require(script.Hud)
local Settings = require(script.Settings)
local SettingsMenu = require(script.SettingsMenu)
local TeamOutlines = require(script.TeamOutlines)
local ThirdPersonRig = require(script.ThirdPersonRig)
local DeathPresenter = require(script.DeathPresenter)
local Lobby = require(script.Lobby) -- Hypershot-style lobby HUD (replaced MainMenu 2026-11-15)
local DeathReplay = require(script.DeathReplay)
local EliminationFX = require(script.EliminationFX)
local ShieldFX = require(script.ShieldFX)
local Armory = require(script.Armory)
local Loadout = require(script.Loadout)
local MatchHud = require(script.MatchHud)

local player = Players.LocalPlayer

local UNDO_BIND = "VantageRecoilUndo"
local WEAPON_BIND = "VantageWeapon"

-- the custom health module replaces Roblox's default health bar (Humanoid health is untouched)
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false) then
			break
		end
		task.wait(0.5)
	end
end)

local input = WeaponInput.new()
local effects = WeaponEffects.new()
local hud = Hud.new()
hud.Gui.Enabled = false -- hidden until we have a character (team select menu comes first)
local settings = Settings.new(input, effects)
hud:BindSettings(settings)
local menu = SettingsMenu.new(settings, input)
local armory = Armory.new(input, menu)
Lobby.Start({ Input = input, Hud = hud, Settings = menu, Effects = effects, Armory = armory })
TeamOutlines.new(settings)
ThirdPersonRig.Start()
DeathPresenter.Start()
DeathReplay.Start(effects)
EliminationFX.Start(effects, hud)
ShieldFX.Start()
MatchHud.Start(hud, effects) -- prepare / countdown / live / result overlays (server phases)
require(script.OperativeIntro).Start({ Input = input, Hud = hud, Effects = effects }) -- pre-match operative introductions (phase "Intro")
require(script.GrenadeClient).Start({ Input = input, Effects = effects }) -- VX-G1 frag: Fire + Alt together (2026-11-11)
require(script.SignatureClient).Start({ Input = input, Hud = hud }) -- Signatures: Shift / L1 / HUD tile (2026-11-20)

-- settings menu key (works alive or dead) + armory key (in match or over the main menu)
local menuHandled = input.MenuPressedAt
local inventoryHandled = input.InventoryPressedAt
RunService.Heartbeat:Connect(function()
	if input.MenuPressedAt > menuHandled then
		menuHandled = input.MenuPressedAt
		if hud.Gui.Enabled or menu.Open then
			if armory.Open then
				armory:SetOpen(false)
			end
			menu:Toggle()
		end
	end
	if input.InventoryPressedAt > inventoryHandled then
		inventoryHandled = input.InventoryPressedAt
		if not menu.Open then
			armory:Toggle()
		end
	end
end)

-- master volume reaches Roblox's character sounds (footsteps etc.) too
local function groupSounds(character: Model)
	local function apply(d)
		if d:IsA("Sound") and d.SoundGroup == nil then
			d.SoundGroup = effects.EffectsGroup
		end
	end
	for _, d in character:GetDescendants() do
		apply(d)
	end
	character.DescendantAdded:Connect(apply)
end
local function onAnyPlayer(plr: Player)
	plr.CharacterAdded:Connect(groupSounds)
	if plr.Character then
		groupSounds(plr.Character)
	end
end
for _, plr in Players:GetPlayers() do
	onAnyPlayer(plr)
end
Players.PlayerAdded:Connect(onAnyPlayer)

local active = nil
local deathInfo = nil

local function teardown()
	if not active then
		return
	end
	RunService:UnbindFromRenderStep(UNDO_BIND)
	RunService:UnbindFromRenderStep(WEAPON_BIND)
	for _, c in active.Connections do
		c:Disconnect()
	end
	active.Loadout:Destroy()
	active = nil
end

local firstSpawn = true
local function onCharacter(character: Model)
	teardown()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	character:WaitForChild("Head")
	for _, n in ipairs({ "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }) do
		character:WaitForChild(n, 5)
	end
	if player.Character ~= character then
		return
	end
	if player.Team == nil and not player:GetAttribute("InTutorial") then -- trainees (VantageTutorial) are armed
		-- lobby (Workspace.HyperLobby, see LobbyService): no weapons and no combat HUD; Lobby owns the screen
		hud.Gui.Enabled = false
		-- 2026-11-18 fix: clear match-end leftovers so the lobby always starts clean (held aim /
		-- fire, the death fade, a Scriptable death / results camera, a zoomed ADS FOV)
		input.FireHeld, input.AltHeld = false, false
		input._fireDown, input._altDown, input._chord, input._pendingFire = false, false, false, nil
		pcall(function()
			hud:HideDeath()
			hud:Fade(false, 0)
		end)
		local cam = Workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = humanoid
		cam.FieldOfView = 70
		return
	end
	input:SetBlocked(false)
	local loadout = Loadout.new({
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Input = input,
		Hud = hud,
		Effects = effects,
		Settings = settings,
		Menu = menu,
	})
	active = { Loadout = loadout, Connections = {} }
	DeathReplay.OnSpawn()
	if firstSpawn or not hud.Gui.Enabled then
		-- first life of a match (the server's Match.TimeLeft drives the clock)
		hud.TimerStart = os.clock()
		firstSpawn = false
	else
		DeathPresenter.LocalSpawn(hud)
	end
	hud.Gui.Enabled = true
	hud:SetCombatVisible(true)
	deathInfo = nil
	-- Camera - 2: undo order is the reverse of apply (grenade shake -3, recoil -2, movement tilt -1)
	RunService:BindToRenderStep(UNDO_BIND, Enum.RenderPriority.Camera.Value - 2, function()
		loadout:UndoView()
	end)
	RunService:BindToRenderStep(WEAPON_BIND, Enum.RenderPriority.Camera.Value + 2, function(dt)
		loadout:Step(dt)
	end)
	table.insert(active.Connections, humanoid.Died:Connect(function()
		task.defer(function()
			local stopDeathCam = DeathPresenter.LocalDeath(character, hud, deathInfo)
			DeathReplay.OnDeath(character, hud, function()
				return deathInfo
			end, stopDeathCam)
		end)
	end))
	table.insert(active.Connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			teardown()
		end
	end))
end

-- Server -> client messages
EventRemote.OnClientEvent:Connect(function(kind: string, a, b, c, d, e, f)
	if kind == "Ammo" then
		-- a = weapon id, b = mag, c = reserve, d = reason, e = reloading, f = lastSeq
		if active then
			active.Loadout:OnServerAmmo(a, b, c, d, e, f)
		end
	elseif kind == "Confirm" then
		if active then
			active.Loadout:OnConfirm(a)
		end
	elseif kind == "Shot" then
		-- another player's shot: effects only. a = shooter character
		local character: Model? = a
		local endPos: Vector3 = b
		DeathReplay.RecordShot(character, endPos, c, d, e)
		hud:NoteShot(character)
		local world = character and character:FindFirstChild("VantageWorldWeapon")
		local muzzle = world and world.PrimaryPart and world.PrimaryPart:FindFirstChild("Muzzle")
		local wid = world and world:GetAttribute("WeaponId")
		-- f = extra: { Quiet = true } for the extra pellets of one shotgun blast,
		-- { Projectile = speed } for energy bolts (impact plays on arrival)
		local extra = if type(f) == "table" then f else {}
		local wcfg = wid and WeaponConfig.Weapons[wid]
		if muzzle then
			if extra.Projectile and extra.Dir and wcfg and wcfg.Projectile then
				-- arcing round (2026-11-18): simulate the same arc from this shooter's muzzle
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { character, workspace.CurrentCamera, workspace:FindFirstChild("VantageWeaponFX") }
				effects:BoltArc(muzzle.WorldPosition, extra.Dir, wcfg.Projectile, rp, wid)
			elseif extra.Projectile and wcfg and wcfg.Projectile then
				effects:Bolt(muzzle.WorldPosition, endPos, wcfg.Projectile, if c and d == "World" then { c, e and Enum.Material[e], wid } else nil)
			elseif wcfg and wcfg.Beam then
				effects:BeamPulse(character, muzzle, endPos, wcfg.Beam)
			else
				effects:Tracer(muzzle.WorldPosition, endPos)
			end
			if not extra.Quiet then
				effects:MuzzleFlash(muzzle)
				effects:PlayFire3D(wid, muzzle, character)
				ThirdPersonRig.OnShot(character)
			end
		end
		if c and d and not extra.Projectile then
			effects:Impact(endPos, c, d, e, wid)
		end
	elseif kind == "Melee" then
		-- another player's knife swing: a = attacker character, b = hit position?, c = hit body?
		local character: Model? = a
		DeathReplay.RecordMelee(character, b)
		local knife = character and character:FindFirstChild("VantageWorldKnife")
		if knife and knife.PrimaryPart then
			effects:PlayCue("Knife", "Swing", knife.PrimaryPart)
		end
		if typeof(b) == "Vector3" then
			effects:MeleeImpact(b, Vector3.new(0, 1, 0), c == true)
		end
	elseif kind == "Feed" then
		-- someone was eliminated: a = killer, b = killer team, c = weapon id, d = victim, e = victim team, f = headshot
		hud:AddFeed(a, b, c, d, e, f)
	elseif kind == "Damaged" then
		-- we were hit: a = source position, b = amount
		if typeof(a) == "Vector3" then
			hud:ShowIncoming(a)
			-- screen edges toward the attacker + a short roll wobble, both stronger while the shield is critical
			local ch = player.Character
			local max = ch and ch:GetAttribute("MaxShield") or 0
			local sh = ch and ch:GetAttribute("Shield") or 0
			local strength, side = hud:ShieldImpact(a, if max > 0 then math.clamp(sh / max, 0, 1) else 0, sh > 0.5)
			if active then
				local sign = if math.abs(side) > 0.2 then math.sign(side) elseif math.random() < 0.5 then -1 else 1
				active.Loadout.Recoil:HitShake(strength * 1.6 * sign)
			end
		end
	elseif kind == "Died" then
		-- our elimination: a = killer name, b = killer position, c = weapon name, d = headshot,
		-- e = distance?, f = killer character? (nil: environmental death → no replay)
		deathInfo = {
			Killer = a,
			KillerPosition = b,
			Weapon = c,
			Headshot = d == true,
			Distance = e,
			KillerModel = f,
			HasKiller = typeof(f) == "Instance",
			Detail = (c or "") .. (if d then "  //  HEADSHOT" else ""),
		}
		hud:ShowDeath(a, deathInfo.Detail)
	end
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
