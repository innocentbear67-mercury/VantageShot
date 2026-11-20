--[[
	VANTAGE — TutorialService (server), 2026-11-20
	First-time training: MOVEMENT → GRAPPLE → WEAPONS → SHIELDS → ARMOURY → LOADOUT (client UI: VantageTutorial).
	- Completion is stored in the PROFILE (ProfileService, DataStore VantageProfile_v1, field Tut) through the
	  ProfileTutorial BindableFunction and replicated as player attribute TutorialDone (true / false; missing =
	  profile not loaded or the load failed, so the tutorial never auto-starts on a bad load).
	- A trainee has player attribute InTutorial = true and no team. The lobby gates (Team == nil) in
	  WeaponService / AbilityServer / clients let InTutorial through; LobbyService leaves trainees alone.
	- Each trainee gets a private arena (TutorialConfig.L) at Origin + slot * Spacing, streamed only to them,
	  with 3 training targets (tag VantageTutorialTarget, attribute TutorialTarget = UserId) that only they can
	  damage (DamageService). Trainees cannot be damaged by anyone else. Targets never die and give no XP / REQ.
	- Part 2 (2026-11-20): ENTER THE BATTLE saves level 1 and sends the player to the lobby with attribute
	  TutorialBriefing = true; the client runs the lobby briefing (currencies, crates, shop, farm) on the real
	  lobby UI and sends "BriefingDone" (level 2). Skip (either part) saves level 2. A player who left between
	  the parts (TutorialBriefed = false) gets the briefing on their next join.
	- Remotes.Tutorial (RemoteEvent)
	    client → server: "Stage", n | "Skip" | "Done" | "Replay" | "BriefingDone"
	    server → client: "Reject", n | "Zap", from, to, broke
	  Every stage advance is checked here against the real game state (position, server hits, shield).
	- Player attributes: InTutorial, TutorialStage, TutorialOrigin (Vector3), TutorialHits.
	- Studio: auto-start only when ReplicatedStorage.Vantage attribute TutorialInStudio = true (Replay always works).
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Vantage = RS:WaitForChild("Vantage")
local T = require(Vantage:WaitForChild("Tutorial"):WaitForChild("TutorialConfig"))
local L = T.L
local Remotes = require(Vantage:WaitForChild("RemotesLib"))
local Remote = Remotes.get("Tutorial") :: RemoteEvent

local server = script.Parent
local WS = server:WaitForChild("WeaponServer")
local ShieldService = require(WS:WaitForChild("ShieldService"))
local DamageService = require(WS:WaitForChild("DamageService"))
local exempt = server:WaitForChild("ExemptMovement", 10) :: BindableEvent?
local profileFn = server:WaitForChild("ProfileTutorial", 30) :: BindableFunction?

local folder = Workspace:FindFirstChild("VantageTutorial") or Instance.new("Folder")
folder.Name = "VantageTutorial"
folder.Parent = Workspace

local V3, C3 = Vector3.new, Color3.fromRGB
local GRAPHITE, DARK, STEEL = C3(36, 40, 49), C3(21, 24, 30), C3(52, 58, 70)
-- shop palette: purple trims, gold for the things to aim at (marker, anchor, target pads)
local BLUE, SOFT = C3(150, 80, 255), C3(110, 60, 190)
local GOLD = C3(255, 206, 84)

local state: { [Player]: any } = {}
local slots: { [number]: Player } = {}

-- ─── arena ─────────────────────────────────────────────────────────────────────────────
local function part(parent, size, cf, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = GRAPHITE
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end
local function glow(parent, size, cf, color)
	return part(parent, size, cf, { Material = Enum.Material.Neon, Color = color or BLUE, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end
local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local function wordmark(p: BasePart, face: Enum.NormalId, pos: UDim2, size: UDim2)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Wordmark"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 24
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.Parent = p
	local function label(offset: Vector2, color: Color3, z: number)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Text = "VANTAGESHOT"
		t.FontFace = FREDOKA
		t.TextScaled = true
		t.TextColor3 = color
		t.Position = pos + UDim2.fromOffset(offset.X, offset.Y)
		t.Size = size
		t.ZIndex = z
		t.Parent = sg
		return t
	end
	label(Vector2.new(0, 14), C3(150, 80, 255), 1) -- purple drop, like the shop titles
	local t = label(Vector2.zero, Color3.new(1, 1, 1), 2)
	local s = Instance.new("UIStroke")
	s.Color = C3(14, 6, 28)
	s.Thickness = 10
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), C3(255, 226, 120))
	g.Parent = t
end

local function build(o: Vector3, p: Player): Model
	local m = Instance.new("Model")
	m.Name = "Tutorial_" .. p.UserId
	local function at(x, y, z)
		return CFrame.new(o + V3(x, y, z))
	end
	local cyl = CFrame.Angles(0, 0, math.rad(90))
	-- 01 movement deck (z +14 .. -62)
	part(m, V3(40, 2, 76), at(0, -1, -24), { Name = "Deck", Color = DARK, Material = Enum.Material.Concrete })
	for _, x in { -20.5, 20.5 } do
		part(m, V3(1, 6, 76), at(x, 3, -24), { Name = "Rail", Color = STEEL, Material = Enum.Material.Metal })
		glow(m, V3(1.15, 0.22, 76), at(x, 6.05, -24))
		glow(m, V3(0.25, 0.06, 76), at(x * 0.93, 0.03, -24), SOFT)
	end
	local back = part(m, V3(42, 18, 1), at(0, 9, 14.5), { Name = "BackWall", Color = STEEL, Material = Enum.Material.Metal })
	wordmark(back, Enum.NormalId.Front, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.3))
	glow(m, V3(28, 0.3, 0.2), at(0, 10, 13.9))
	glow(m, V3(16, 0.2, 0.2), at(0, 8.8, 13.9), SOFT)
	-- marker ring + beam
	part(m, V3(0.12, L.MarkerRadius * 2, L.MarkerRadius * 2), at(L.Marker.X, 0.08, L.Marker.Z) * cyl, { Name = "Marker", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = GOLD, Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	part(m, V3(16, L.MarkerRadius * 2 - 1, L.MarkerRadius * 2 - 1), at(L.Marker.X, 8, L.Marker.Z) * cyl, { Name = "MarkerBeam", Shape = Enum.PartType.Cylinder, Material = Enum.Material.ForceField, Color = GOLD, Transparency = 0.2, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	-- barrier (needs a jump)
	part(m, V3(39, L.BarrierH, 1.4), at(0, L.BarrierH / 2, L.BarrierZ), { Name = "Barrier", Color = STEEL, Material = Enum.Material.Metal })
	glow(m, V3(39, 0.18, 1.45), at(0, L.BarrierH + 0.02, L.BarrierZ))
	-- 02 grapple tower (front z -62, top y 30) + anchor pylon
	local tower = part(m, V3(40, 30, 34), at(0, 15, -79), { Name = "Tower", Color = GRAPHITE, Material = Enum.Material.Metal })
	wordmark(tower, Enum.NormalId.Back, UDim2.fromScale(0.04, 0.37), UDim2.fromScale(0.92, 0.26))
	for _, y in { 10, 20 } do
		glow(m, V3(40.1, 0.25, 0.2), at(0, y, L.TowerFront + 0.05), SOFT)
	end
	glow(m, V3(40.2, 0.3, 0.3), at(0, 30.05, L.TowerFront + 0.1))
	local pylon = part(m, V3(10, 30, 3), at(0, 45, -74.5), { Name = "Pylon", Color = STEEL, Material = Enum.Material.Metal })
	local anchor = part(m, V3(8, 8, 0.4), at(L.Anchor.X, L.Anchor.Y, L.Anchor.Z), { Name = "GrappleAnchor", Material = Enum.Material.Neon, Color = GOLD })
	light(anchor, GOLD, 40, 3)
	for _, d in { { V3(9.4, 0.4, 0.3), V3(0, 4.7, 0) }, { V3(9.4, 0.4, 0.3), V3(0, -4.7, 0) }, { V3(0.4, 9.8, 0.3), V3(4.7, 0, 0) }, { V3(0.4, 9.8, 0.3), V3(-4.7, 0, 0) } } do
		glow(m, d[1], CFrame.new(anchor.Position + d[2] + V3(0, 0, 0.1)), Color3.new(1, 1, 1))
	end
	glow(m, V3(0.3, 30, 0.2), CFrame.new(pylon.Position + V3(-5.05, 0, 1.45)), SOFT)
	glow(m, V3(0.3, 30, 0.2), CFrame.new(pylon.Position + V3(5.05, 0, 1.45)), SOFT)
	-- 03 range: rail, void, far ledge with the targets
	part(m, V3(40, 3.2, 1), at(0, 31.6, L.TowerBack + 0.5), { Name = "RangeRail", Color = STEEL, Material = Enum.Material.Metal })
	glow(m, V3(40, 0.15, 1.05), at(0, 33.25, L.TowerBack + 0.5))
	for _, x in { -20.5, 20.5 } do
		part(m, V3(1, 5, 34), at(x, 32.5, -79), { Name = "TopRail", Color = STEEL, Material = Enum.Material.Metal })
		glow(m, V3(1.1, 0.2, 34), at(x, 35.05, -79))
	end
	part(m, V3(46, 2, 28), at(0, 29, -142), { Name = "Ledge", Color = DARK, Material = Enum.Material.Concrete })
	glow(m, V3(46, 0.25, 0.3), at(0, 30.05, -128.1))
	local backstop = part(m, V3(46, 28, 2), at(0, 44, -157), { Name = "Backstop", Color = STEEL, Material = Enum.Material.Metal })
	wordmark(backstop, Enum.NormalId.Back, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.3))
	for _, y in { 36, 46, 56 } do
		glow(m, V3(46, 0.22, 0.2), at(0, y, -155.95), SOFT)
	end
	for _, t in L.Targets do
		part(m, V3(0.12, 6, 6), at(t.X, t.Y + 0.08, t.Z) * cyl, { Name = "Pad", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = GOLD, Transparency = 0.5, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
	-- 04 shield sentry (hovers over the void)
	local sentry = part(m, V3(3.2, 3.2, 3.2), at(L.Sentry.X, L.Sentry.Y, L.Sentry.Z), { Name = "Sentry", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = C3(255, 72, 72), CanCollide = false, CanQuery = false, CanTouch = false })
	part(m, V3(0.5, 6, 6), CFrame.new(sentry.Position) * CFrame.Angles(0, math.rad(90), 0) * cyl, { Name = "SentryRing", Shape = Enum.PartType.Cylinder, Color = STEEL, Material = Enum.Material.Metal, Transparency = 0, CanCollide = false, CanQuery = false, CanTouch = false })
	light(sentry, C3(255, 80, 80), 18, 2)
	light(part(m, V3(1, 1, 1), at(0, 12, -10), { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }), C3(200, 170, 255), 45, 1.2)
	light(part(m, V3(1, 1, 1), at(0, 42, -84), { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }), C3(200, 170, 255), 45, 1.2)
	m.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	m.Parent = folder
	pcall(function()
		m:AddPersistentPlayer(p)
	end)
	return m
end

local function spawnTargets(p: Player, st)
	for i, off in L.Targets do
		local ok, rig = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if state[p] ~= st then
			if ok and rig then
				rig:Destroy()
			end
			return
		end
		if not ok or not rig then
			warn("[VANTAGE] Tutorial target failed:", rig)
			continue
		end
		rig.Name = "TrainingTarget" .. i
		local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		hum.MaxHealth = 5000
		hum.Health = 5000
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = C3(62, 68, 82)
				d.Material = Enum.Material.Metal
			elseif d:IsA("Decal") then
				d:Destroy()
			end
		end
		local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
		root.Anchored = true
		rig:SetAttribute("TutorialTarget", p.UserId)
		rig:SetAttribute("Team", "Tutorial")
		local hl = Instance.new("Highlight")
		hl.FillColor = GOLD
		hl.FillTransparency = 0.8
		hl.OutlineColor = GOLD
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = rig
		local pos = st.Origin + off + V3(0, 3, 0)
		rig:PivotTo(CFrame.lookAt(pos, pos + V3(0, 0, 10)))
		rig.Parent = st.Arena
		CollectionService:AddTag(rig, "VantageTutorialTarget")
	end
end

-- ─── flow ──────────────────────────────────────────────────────────────────────────────
local function checkpoint(st): CFrame
	local pos = if st.Stage <= 1 then L.Spawn elseif st.Stage == 2 then L.Stage2 else L.Stage3
	local w = st.Origin + pos
	return CFrame.lookAt(w, w + V3(0, 0, -1))
end

local function localPos(st, c: Model?): Vector3?
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and (root.Position - st.Origin) or nil
end

local function place(p: Player, c: Model, st)
	if exempt then
		exempt:Fire(p, 3)
	end
	c:PivotTo(checkpoint(st))
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local shieldDemo

local function respawn(p: Player)
	local st = state[p]
	if not st or not p.Parent then
		return
	end
	pcall(function()
		p:RequestStreamAroundAsync(st.Origin + L.Spawn, 5)
	end)
	if exempt then
		exempt:Fire(p, 3)
	end
	local ok, err = pcall(function()
		p:LoadCharacter()
	end)
	if not ok then
		warn("[VANTAGE] Tutorial spawn failed:", err)
	end
end

local function onCharacter(p: Player, c: Model)
	local st = state[p]
	if not st then
		return
	end
	local root = c:WaitForChild("HumanoidRootPart", 10)
	if not root or state[p] ~= st or p.Character ~= c then
		return
	end
	place(p, c, st)
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			task.delay(2, function()
				if state[p] == st and p.Character == c then
					respawn(p)
				end
			end)
		end)
	end
	if st.Stage == 4 then
		task.spawn(shieldDemo, p, st, c)
	end
end

function shieldDemo(p: Player, st, c: Model)
	st.Token += 1
	local tok = st.Token
	st.ShieldBroken = false
	task.wait(1.8)
	local hum = c:FindFirstChildOfClass("Humanoid")
	for i = 1, 4 do
		if state[p] ~= st or st.Stage ~= 4 or st.Token ~= tok or p.Character ~= c or not hum or hum.Health <= 0 then
			return
		end
		local s, max = ShieldService.Get(c)
		local amt = if i < 4 then math.min(s, math.floor(max * 0.3 + 0.5)) else s
		local torso = (c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if amt > 0 and torso then
			local from = st.Origin + L.Sentry
			local dir = (torso.Position - from).Unit
			local hitPos = torso.Position - dir * 0.8
			local toHealth, absorbed, broke = ShieldService.Absorb(c, amt)
			if toHealth > 0 and hum.Health > 1 then
				hum:TakeDamage(math.min(toHealth, hum.Health - 1)) -- the demo never kills
			end
			ShieldService.Report(c, hitPos, dir, absorbed, broke)
			Remote:FireClient(p, "Zap", from, hitPos, broke == true)
		end
		task.wait(if i == 3 then 1.1 else 0.75)
	end
	if st.Token == tok then
		st.ShieldBroken = true
	end
end

local function setStage(p: Player, st, n: number)
	st.Stage = n
	p:SetAttribute("TutorialStage", n)
	if n == 4 and p.Character then
		task.spawn(shieldDemo, p, st, p.Character)
	end
end

local function freeSlot(): number
	local i = 0
	while slots[i] do
		i += 1
	end
	return i
end

local function cleanup(p: Player, st)
	if state[p] == st then
		state[p] = nil
	end
	if slots[st.Slot] == p then
		slots[st.Slot] = nil
	end
	st.Token += 1
	if st.Arena then
		st.Arena:Destroy()
	end
	if p.Parent then
		p:SetAttribute("InTutorial", nil)
		p:SetAttribute("TutorialStage", nil)
		p:SetAttribute("TutorialOrigin", nil)
		p:SetAttribute("TutorialHits", nil)
	end
end

local function start(p: Player): boolean
	if state[p] or not p.Parent or p.Team ~= nil or p:GetAttribute("MatchStatus") ~= nil then
		return false
	end
	local slot = freeSlot()
	local origin = T.Origin + V3(slot * T.Spacing, 0, 0)
	local st = { Slot = slot, Origin = origin, Stage = 1, Hits = {}, HitCount = 0, Token = 0, ShieldBroken = false, LastMsg = 0 }
	slots[slot] = p
	state[p] = st
	st.Arena = build(origin, p)
	p:SetAttribute("TutorialOrigin", origin)
	p:SetAttribute("TutorialHits", 0)
	p:SetAttribute("TutorialStage", 1)
	p:SetAttribute("InLobby", false)
	p:SetAttribute("InTutorial", true)
	task.spawn(spawnTargets, p, st)
	respawn(p)
	return true
end

local function complete(p: Player, level: number)
	if profileFn then
		local ok, err = pcall(function()
			profileFn:Invoke("Complete", p, level)
		end)
		if not ok then
			warn("[VANTAGE] Tutorial save failed:", err)
		end
	end
end

local function finish(p: Player, completed: boolean, level: number?)
	local st = state[p]
	if not st then
		return
	end
	if completed and profileFn then
		local ok, err = pcall(function()
			profileFn:Invoke("Complete", p, level or 1)
		end)
		if not ok then
			warn("[VANTAGE] Tutorial save failed:", err)
		end
	end
	cleanup(p, st)
	if p.Parent and p.Team == nil then
		if exempt then
			exempt:Fire(p, 3)
		end
		pcall(function()
			p:LoadCharacter() -- LobbyService puts the new character in the hall
		end)
	end
end

-- the server checks each stage against the real game state before moving on
local function stageDone(p: Player, st): boolean
	local lp = localPos(st, p.Character)
	if st.Stage == 1 then
		return lp ~= nil and lp.Z < L.BarrierZ - 0.5
	elseif st.Stage == 2 then
		return lp ~= nil and lp.Y > L.TowerTop - 1 and lp.Z < L.TowerFront and lp.Z > L.TowerBack - 2
	elseif st.Stage == 3 then
		return st.HitCount >= T.TargetsNeeded
	elseif st.Stage == 4 then
		local c = p.Character
		if not (c and st.ShieldBroken) then
			return false
		end
		local s, max = ShieldService.Get(c)
		return max > 0 and s >= max - 0.5
	elseif st.Stage == 5 then
		return true
	end
	return false
end

Remote.OnServerEvent:Connect(function(p: Player, action: any, n: any)
	local st = state[p]
	if action == "Replay" then
		if not st then
			p:SetAttribute("TutorialBriefing", nil)
			start(p)
		end
		return
	end
	if not st then
		-- part 2 (lobby briefing)
		if p:GetAttribute("TutorialBriefing") and (action == "BriefingDone" or action == "Skip") then
			p:SetAttribute("TutorialBriefing", nil)
			complete(p, 2)
		end
		return
	end
	local now = os.clock()
	if now - st.LastMsg < 0.2 then
		return
	end
	st.LastMsg = now
	if action == "Stage" and type(n) == "number" then
		if n == st.Stage + 1 and n <= #T.Stages and stageDone(p, st) then
			setStage(p, st, n)
		else
			Remote:FireClient(p, "Reject", st.Stage)
		end
	elseif action == "Skip" then
		finish(p, true, 2) -- skipping skips the lobby briefing too
	elseif action == "Done" then
		if st.Stage >= #T.Stages then
			finish(p, true, 1)
			if p.Parent then
				p:SetAttribute("TutorialBriefing", true) -- part 2 starts in the lobby
			end
		end
	end
end)

-- training targets: count each one once (stage 3), keep them standing
table.insert(DamageService.HitHooks, function(shooter: Player, character: Model, _dealt: number)
	local uid = character:GetAttribute("TutorialTarget")
	if not uid then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = hum.MaxHealth
	end
	local st = state[shooter]
	if not st or uid ~= shooter.UserId or st.Stage ~= 3 or st.Hits[character] then
		return
	end
	st.Hits[character] = true
	st.HitCount += 1
	shooter:SetAttribute("TutorialHits", st.HitCount)
	local hl = character:FindFirstChildOfClass("Highlight")
	if hl then
		hl.FillColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.55
		hl.OutlineColor = C3(120, 255, 180)
	end
end)

-- auto-start for first-time players
local function auto(p: Player)
	if RunService:IsStudio() and Vantage:GetAttribute("TutorialInStudio") ~= true then
		return
	end
	local t0 = os.clock()
	while p.Parent and p:GetAttribute("TutorialDone") == nil and os.clock() - t0 < 30 do
		task.wait(0.5)
	end
	local needArena = p:GetAttribute("TutorialDone") == false
	local needBrief = p:GetAttribute("TutorialBriefed") == false
	if not (needArena or needBrief) then
		return
	end
	t0 = os.clock()
	while p.Parent and not (p.Character and p.Character:FindFirstChild("HumanoidRootPart")) and os.clock() - t0 < 30 do
		task.wait(0.3)
	end
	task.wait(1.5)
	if not p.Parent then
		return
	end
	if needArena then
		start(p)
	elseif needBrief and p.Team == nil then
		p:SetAttribute("TutorialBriefing", true) -- left between the parts: brief them in the lobby
	end
end

local function onPlayer(p: Player)
	p.CharacterAdded:Connect(function(c)
		onCharacter(p, c)
	end)
	p:GetPropertyChangedSignal("Team"):Connect(function()
		local st = state[p]
		if st and p.Team ~= nil then
			cleanup(p, st) -- pulled into a match: the match owns the character now
		end
	end)
	task.spawn(auto, p)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(p)
	local st = state[p]
	if st then
		cleanup(p, st)
	end
end)

-- falls: back to the stage checkpoint (no death, no penalty)
task.spawn(function()
	while true do
		task.wait(0.25)
		for p, st in state do
			local c = p.Character
			local lp = localPos(st, c)
			if c and lp and lp.Y < L.FallY then
				place(p, c, st)
			end
		end
	end
end)
