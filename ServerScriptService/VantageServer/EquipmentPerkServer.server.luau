--[[
	VANTAGE — EquipmentPerkServer (2026-11-18, reworked 2026-11-19)
	The Shield Pack traits (EquipmentCatalog Ability.Id / Ability.Params). Grappling Hook traits live in AbilityServer
	(server) and VantageAbilityClient (client); Overshield lives in ShieldService; Glide's physics in VantagePerkClient.

	HexWall      (Bastion)      the shield drops below 25 % (ShieldService.Hooks.Low) -> a ONE-WAY hardlight wall toward the
	                            attacker: enemy bullets stop on it (HitValidation hits it as world geometry, DamageService.
	                            ApplyToVehicle takes its HP); the owner's team shoots through it (PerkWallTeam, HitValidation).
	                            Players walk through it, the grapple steps through it. 20 s cooldown. Only while alive.
	SquadPulse   (Pulsar Core)  recharge starts -> +Self to you, +Ally to teammates in Radius and their recharge starts now.
	                            Params.Cooldown between pulses; each ally takes one pulse per Params.AllyLock seconds.
	EventHorizon (Singularity)  the shield breaks and you SURVIVE -> phase: PerkSpeedMult / PerkSpeedUntil (MovementController
	                            + MovementValidator), PhaseUntil (VantagePerkClient draws the shimmer), and a gravity well left
	                            where you broke that slows enemies' MOVEMENT (PerkSlow / PerkSlowUntil, no aim slow).
	Glide        (Seraph Array) the client says when it glides (Remotes.PerkState "Glide"); the server checks the pack and
	                            sets the character attribute Gliding, so every client draws the wings.
	Works on bots and dummies too (their EquipPack attribute), except Glide (players only).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Catalog = require(ReplicatedStorage.Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
local WS = script.Parent:WaitForChild("WeaponServer")
local ShieldService = require(WS:WaitForChild("ShieldService"))
local DamageService = require(WS:WaitForChild("DamageService"))
local Elim = require(WS:WaitForChild("EliminationService"))

local folder = Workspace:FindFirstChild("VantagePerkFX") or Instance.new("Folder")
folder.Name = "VantagePerkFX"
folder.Parent = Workspace

local Remotes = ReplicatedStorage.Vantage:WaitForChild("Remotes")
local PerkState = Remotes:FindFirstChild("PerkState") or Instance.new("RemoteEvent")
PerkState.Name = "PerkState"
PerkState.Parent = Remotes

local function rootOf(m: Model): BasePart?
	return m:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local function alive(m: Model): boolean
	local h = m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and m:IsDescendantOf(Workspace)
end
local function hostile(a: Model, b: Model): boolean
	if a == b then
		return false
	end
	local ta, tb = DamageService.TeamOf(a), DamageService.TeamOf(b)
	return not (ta ~= nil and tb ~= nil and ta == tb)
end
-- the key HitValidation compares with the shooter's: team name, or "U"..UserId with no team
local function teamKey(m: Model): string
	local p = Players:GetPlayerFromCharacter(m)
	if p then
		return if p.Team and not p.Neutral then p.Team.Name else "U" .. p.UserId
	end
	return DamageService.TeamOf(m) or ("B" .. m.Name)
end
local function characters(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, tag in { "VantageBot", "VantageDummy" } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end
local function tween(o, t, goal, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
local function fxPart(props): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end
-- silent lead-ins of the library sounds used here (AudioAnalyzer onsets, as in AbilityConfig.Sounds)
local LEAD = { ["rbxassetid://9125981410"] = 0.42, ["rbxassetid://9114315137"] = 0.17, ["rbxassetid://9114592245"] = 0.42,
	["rbxassetid://9125648149"] = 0.05, ["rbxassetid://9125577419"] = 0.24, ["rbxassetid://9120769331"] = 0.05, ["rbxassetid://9125980435"] = 0.22 }
local function sound(parent: Instance, id: string, vol: number, speed: number)
	local snd = Instance.new("Sound")
	snd.SoundId, snd.Volume, snd.PlaybackSpeed = id, vol, speed
	snd.TimePosition = LEAD[id] or 0
	snd.RollOffMinDistance, snd.RollOffMaxDistance = 8, 160
	snd.Parent = parent
	snd:Play()
	game:GetService("Debris"):AddItem(snd, 4)
end
local readyAt: { [Model]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local function onCooldown(ch: Model, key: string, secs: number): boolean
	local t = readyAt[ch]
	if not t then
		t = {}
		readyAt[ch] = t
	end
	local now = os.clock()
	if (t[key] or 0) > now then
		return true
	end
	t[key] = now + secs
	return false
end

-- ── Hex Wall (one-way) ─────────────────────────────────────────────────────────────────────
local function hexWall(ch: Model, P, it)
	if not alive(ch) or onCooldown(ch, "Wall", P.Cooldown or 20) then
		return
	end
	local root = rootOf(ch)
	if not root then
		return
	end
	-- toward whoever is shooting you, else back along the last shot, else where you face
	local dir: Vector3? = nil
	local uid = ch:GetAttribute("LastDamagedBy")
	local att = type(uid) == "number" and Players:GetPlayerByUserId(uid)
	local ar = att and att.Character and rootOf(att.Character)
	if ar then
		dir = ar.Position - root.Position
	else
		local hd = ch:GetAttribute("LastHitDir")
		if typeof(hd) == "Vector3" then
			dir = -hd
		end
	end
	dir = Vector3.new((dir or root.CFrame.LookVector).X, 0, (dir or root.CFrame.LookVector).Z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	local W, H = P.Width or 8, P.Height or 7
	local pos = root.Position + dir * (P.Distance or 4) + Vector3.new(0, H / 2 - 3, 0)
	local cf = CFrame.lookAt(pos, pos + dir)
	local wall = fxPart({ Name = "HexWall", Material = Enum.Material.ForceField, Color = it.Color, Size = Vector3.new(W, H, 0.6), CFrame = cf, CanQuery = true, Transparency = 0 })
	wall:SetAttribute("PerkWallHP", P.HP or 175)
	wall:SetAttribute("PerkWallOwner", ch.Name)
	wall:SetAttribute("PerkWallTeam", teamKey(ch))
	local glow = fxPart({ Name = "Glow", Color = it.Color2, Size = Vector3.new(W - 0.3, H - 0.3, 0.08), CFrame = cf, Transparency = 0.86 })
	local rimTop = fxPart({ Name = "Rim", Color = it.Color2, Size = Vector3.new(W, 0.18, 0.7), CFrame = cf * CFrame.new(0, H / 2, 0), Transparency = 0.1 })
	local rimBot = fxPart({ Name = "Rim", Color = it.Color2, Size = Vector3.new(W, 0.18, 0.7), CFrame = cf * CFrame.new(0, -H / 2, 0), Transparency = 0.1 })
	glow.Parent, rimTop.Parent, rimBot.Parent = wall, wall, wall
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = it.Color, 12, 1.5
	light.Parent = glow
	wall.Size = Vector3.new(W, 0.3, 0.6)
	wall.CFrame = cf * CFrame.new(0, -H / 2, 0)
	glow.Size = Vector3.new(W - 0.3, 0.2, 0.08)
	glow.CFrame = wall.CFrame
	wall.Parent = folder
	tween(wall, 0.14, { Size = Vector3.new(W, H, 0.6), CFrame = cf }, Enum.EasingStyle.Back)
	tween(glow, 0.14, { Size = Vector3.new(W - 0.3, H - 0.3, 0.08), CFrame = cf }, Enum.EasingStyle.Back)
	sound(wall, "rbxassetid://9125981410", 0.75, 1.2)
	sound(wall, "rbxassetid://9114315137", 0.35, 1.8)
	local gone = false
	local cracked = false
	local function shatter(broken: boolean)
		if gone then
			return
		end
		gone = true
		wall.CanQuery = false
		wall:SetAttribute("PerkWallHP", nil)
		wall:SetAttribute("PerkWallTeam", nil)
		if broken then
			sound(wall, "rbxassetid://9125648149", 0.8, 0.8)
		end
		for _, p in { wall, glow, rimTop, rimBot } do
			tween(p, 0.22, { Transparency = 1 })
		end
		tween(wall, 0.22, { Size = Vector3.new(W * 1.15, H * 1.05, 0.2) })
		task.delay(0.3, function()
			wall:Destroy()
		end)
	end
	local maxHP = P.HP or 175
	wall:GetAttributeChangedSignal("PerkWallHP"):Connect(function()
		local hp = wall:GetAttribute("PerkWallHP")
		if type(hp) ~= "number" then
			return
		end
		glow.Transparency = 0.45
		tween(glow, 0.2, { Transparency = 0.86 })
		wall.Transparency = math.clamp(0.55 * (1 - hp / maxHP), 0, 0.55)
		if not cracked and hp <= maxHP * 0.5 then
			cracked = true
			sound(wall, "rbxassetid://9114592245", 0.5, 1.4)
		end
		if hp <= 0 then
			shatter(true)
		end
	end)
	task.delay(P.Duration or 2.5, shatter, false)
end

-- ── Event Horizon ──────────────────────────────────────────────────────────────────────────
local function eventHorizon(ch: Model, P, it)
	local root = rootOf(ch)
	if not root or not alive(ch) or onCooldown(ch, "Horizon", P.Cooldown or 18) then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local phase = P.Phase or 1.2
	ch:SetAttribute("PerkSpeedMult", P.Speed or 1.3)
	ch:SetAttribute("PerkSpeedUntil", now + phase)
	ch:SetAttribute("PhaseUntil", now + phase)
	-- the well stays where the shield broke
	local R, T = P.Radius or 10, P.Duration or 2
	local at = root.Position - Vector3.new(0, 1.5, 0)
	local shell = fxPart({ Name = "Horizon", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = it.Color, Size = Vector3.one * 2, CFrame = CFrame.new(at) })
	local core = fxPart({ Name = "Core", Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic, Size = Vector3.one * 0.5, CFrame = CFrame.new(at) })
	local disc = fxPart({ Name = "Disc", Shape = Enum.PartType.Cylinder, Color = it.Color, Size = Vector3.new(0.12, 3, 3), CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.3 })
	core.Parent, disc.Parent = shell, shell
	shell.Parent = folder
	tween(shell, 0.22, { Size = Vector3.one * R * 2 }, Enum.EasingStyle.Back)
	tween(core, 0.22, { Size = Vector3.one * 2 })
	tween(disc, 0.22, { Size = Vector3.new(0.12, R * 1.1, R * 1.1) })
	sound(shell, "rbxassetid://9125577419", 0.85, 0.5)
	sound(shell, "rbxassetid://9120769331", 0.4, 0.7)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < T and shell.Parent do
			local until_ = Workspace:GetServerTimeNow() + 0.35
			for _, m in characters() do
				local r = rootOf(m)
				if r and alive(m) and hostile(ch, m) and (r.Position - at).Magnitude <= R then
					m:SetAttribute("PerkSlowUntil", until_)
					m:SetAttribute("PerkSlow", P.Slow or 0.65)
					m:SetAttribute("PerkAimSlow", nil)
				end
			end
			task.wait(0.25)
		end
		for _, p in { shell, core, disc } do
			tween(p, 0.25, { Transparency = 1 })
		end
		tween(shell, 0.25, { Size = Vector3.one })
		task.delay(0.3, function()
			shell:Destroy()
		end)
	end)
end

-- ── Squad Pulse ────────────────────────────────────────────────────────────────────────────
local allyLock: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local function squadPulse(ch: Model, P, it)
	local root = rootOf(ch)
	if not root or not alive(ch) or onCooldown(ch, "Pulse", P.Cooldown or 10) then
		return
	end
	ShieldService.Add(ch, P.Self or 15)
	local R = P.Radius or 18
	local now = os.clock()
	for _, m in characters() do
		local r = rootOf(m)
		if m ~= ch and r and alive(m) and not hostile(ch, m) and (r.Position - root.Position).Magnitude <= R
			and (allyLock[m] or 0) <= now then
			allyLock[m] = now + (P.AllyLock or 5)
			ShieldService.Add(m, P.Ally or 30)
			ShieldService.StartRecharge(m)
			m:SetAttribute("PulsedAt", Workspace:GetServerTimeNow()) -- allies' edge flash (VantagePerkClient)
		end
	end
	local ring = fxPart({ Name = "Pulse", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = it.Color, Size = Vector3.new(0.15, 3, 3),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.2 })
	local dome = fxPart({ Name = "PulseDome", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = it.Color2, Size = Vector3.one * 3, CFrame = CFrame.new(root.Position) })
	ring.Parent, dome.Parent = folder, folder
	tween(ring, 0.6, { Size = Vector3.new(0.15, R * 2, R * 2), Transparency = 1 })
	tween(dome, 0.45, { Size = Vector3.one * R * 2, Transparency = 1 })
	sound(ring, "rbxassetid://9120769331", 0.6, 1.25)
	sound(ring, "rbxassetid://9125981410", 0.4, 1.6)
	task.delay(0.65, function()
		ring:Destroy()
		dome:Destroy()
	end)
end

-- ── Glide (replicated state) ───────────────────────────────────────────────────────────────
local glideMsgs: { [Player]: { number } } = {}
PerkState.OnServerEvent:Connect(function(player: Player, kind: any, on: any)
	if kind ~= "Glide" or type(on) ~= "boolean" then
		return
	end
	local now = os.clock()
	local w = glideMsgs[player]
	if not w or now - w[1] > 1 then
		w = { now, 0 }
		glideMsgs[player] = w
	end
	w[2] += 1
	if w[2] > 12 then
		return
	end
	local ch = player.Character
	if not ch or not alive(ch) then
		return
	end
	local id = Catalog.AbilityOf(ch, "Pack")
	ch:SetAttribute("Gliding", on and id == "Glide" or nil)
end)
Players.PlayerRemoving:Connect(function(p)
	glideMsgs[p] = nil
end)

-- Studio test hook (the command bar runs in its own VM): PerkTest:Fire(character, "Kill") runs the kill hooks
if RunService:IsStudio() then
	local test = Instance.new("BindableEvent")
	test.Name = "PerkTest"
	test.Event:Connect(function(ch: Model, kind: string)
		if kind == "Kill" then
			for _, f in Elim.KillHooks do
				task.spawn(f, ch, nil)
			end
		end
	end)
	test.Parent = script
end

-- ── wiring (hooks run deferred, after the hit that caused them is applied) ───────────────────
table.insert(ShieldService.Hooks.Low, function(ch: Model)
	local id, P, it = Catalog.AbilityOf(ch, "Pack")
	if id == "HexWall" then
		hexWall(ch, P, it)
	end
end)
table.insert(ShieldService.Hooks.Break, function(ch: Model)
	local id, P, it = Catalog.AbilityOf(ch, "Pack")
	if id == "EventHorizon" then
		eventHorizon(ch, P, it)
	end
end)
table.insert(ShieldService.Hooks.RechargeStart, function(ch: Model)
	local id, P, it = Catalog.AbilityOf(ch, "Pack")
	if id == "SquadPulse" then
		squadPulse(ch, P, it)
	end
end)
