--[[
	VANTAGE — LobbyPresence (client) · 2026-11-18
	Staging Deck interactions (Workspace.HyperLobby):
	- DEPLOY pad: parts tagged "LobbyDeployZone" (attribute Mode). Stepping in queues that mode through
	  Lobby.DeployMode (same path as the HUD DEPLOY button); stepping out while the pad's own queue is still
	  waiting cancels it through Lobby.CancelQueue. A queue started from the HUD is never touched.
	- ProximityPrompts tagged "LobbyNavPrompt" (attribute Nav) open that lobby menu through Lobby.Nav.
	- Click / tap another Legionary on the deck to open their Profile (Lobby.Nav.Profile); hover outlines them.
	- Spawn effect (ring, light column, motes, sound) whenever a character appears on the deck.
	- An occasional dropship flyby in the background.
	- Keeps the camera on the current character after returning from a match.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local lobby = workspace:WaitForChild("HyperLobby", 60)
if not lobby then return end
local LOBBY_Y = 3000

local Lobby
task.spawn(function()
	local wc = player:WaitForChild("PlayerScripts"):WaitForChild("VantageWeaponClient", 30)
	local mod = wc and wc:WaitForChild("Lobby", 30)
	if not mod then return end
	task.wait(2) -- let VantageWeaponClient require and start it first
	local ok, m = pcall(require, mod)
	if ok then Lobby = m end
end)

local function onDeck(pos: Vector3): boolean
	local d = pos - Vector3.new(0, LOBBY_Y, 0)
	return d.Y > -30 and d.Y < 120 and math.abs(d.X) < 200 and d.Z > -220 and d.Z < 160
end
local function inLobby(): boolean
	return player:GetAttribute("InLobby") == true and player.Team == nil
end

-- ── sounds (ids already used in the game) ─────────────────────────────────────────────
local SPAWN_SOUND
do
	local ok, MC = pcall(require, RS:WaitForChild("Vantage"):WaitForChild("MatchConfig"))
	if ok and type(MC.Sounds) == "table" then
		local s = MC.Sounds.Respawn
		SPAWN_SOUND = type(s) == "table" and (s.Id or s.SoundId) or s
	end
end
local PASS_SOUND = "rbxassetid://9120742158"
local PAD_SOUND = "rbxassetid://1844164399"

-- ── DEPLOY pad ────────────────────────────────────────────────────────────────────────
local zones = {}
local function addZone(z) if z:IsDescendantOf(lobby) then zones[z] = true end end
for _, z in CS:GetTagged("LobbyDeployZone") do addZone(z) end
CS:GetInstanceAddedSignal("LobbyDeployZone"):Connect(addZone)

local inside, padQueued = nil, false
local function padRing(zone, on)
	local ring = zone.Parent and zone.Parent:FindFirstChild("PadRing")
	if ring then
		TweenService:Create(ring, TweenInfo.new(0.35), { Transparency = on and 0.55 or 0.85 }):Play()
	end
end
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.15 then return end
	acc = 0
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local now = nil
	if root and hum and hum.Health > 0 and inLobby() then
		for z in zones do
			if z.Parent then
				local rel = z.CFrame:PointToObjectSpace(root.Position)
				local h = z.Size / 2
				if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
					now = z
					break
				end
			else
				zones[z] = nil
			end
		end
	end
	if now == inside then return end
	if inside then padRing(inside, false) end
	if now then padRing(now, true) end
	local was = inside
	inside = now
	if not Lobby or not Lobby.DeployMode then return end
	if now and not was then
		if Lobby.FlowStage() == nil then
			padQueued = true
			local mode = now:GetAttribute("Mode") or "TDM"
			task.spawn(Lobby.DeployMode, mode)
		end
	elseif was and not now then
		if padQueued and Lobby.FlowStage() == "Queue" then
			task.spawn(Lobby.CancelQueue)
		end
		padQueued = false
	end
end)
player:GetAttributeChangedSignal("InLobby"):Connect(function()
	if not inLobby() then
		if inside then padRing(inside, false) end
		inside, padQueued = nil, false
	end
end)

-- ambient hum on the pad (3D)
for z in zones do
	local core = z.Parent and z.Parent:FindFirstChild("PadCore")
	if core and not core:FindFirstChild("PadHum") then
		local s = Instance.new("Sound")
		s.Name = "PadHum" s.SoundId = PAD_SOUND s.Looped = true s.Volume = 0.3 s.RollOffMaxDistance = 40 s.RollOffMinDistance = 6
		s.Parent = core
		s:Play()
	end
end

-- ── menu prompts ──────────────────────────────────────────────────────────────────────
local function hookPrompt(pp)
	if not pp:IsA("ProximityPrompt") or pp:GetAttribute("_Hooked") then return end
	pp:SetAttribute("_Hooked", true)
	pp.Triggered:Connect(function()
		local nav = pp:GetAttribute("Nav")
		local f = Lobby and Lobby.Nav and Lobby.Nav[nav]
		if f and inLobby() then f() end
	end)
end
for _, pp in CS:GetTagged("LobbyNavPrompt") do hookPrompt(pp) end
CS:GetInstanceAddedSignal("LobbyNavPrompt"):Connect(hookPrompt)

-- ── inspect other Legionaries ─────────────────────────────────────────────────────────
local hl = Instance.new("Highlight")
hl.FillTransparency = 1
hl.OutlineColor = Color3.fromRGB(70, 155, 255)
hl.OutlineTransparency = 0.1
hl.DepthMode = Enum.HighlightDepthMode.Occluded
hl.Enabled = false
hl.Parent = workspace.CurrentCamera
local tip = Instance.new("BillboardGui")
tip.Size = UDim2.fromOffset(150, 26) tip.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0) tip.AlwaysOnTop = true tip.Enabled = false tip.LightInfluence = 0
local tipText = Instance.new("TextLabel")
tipText.Size = UDim2.fromScale(1, 1) tipText.BackgroundColor3 = Color3.fromRGB(12, 16, 24) tipText.BackgroundTransparency = 0.2
tipText.TextColor3 = Color3.fromRGB(225, 235, 250) tipText.TextScaled = true tipText.Text = "CLICK TO INSPECT"
tipText.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
Instance.new("UICorner", tipText).CornerRadius = UDim.new(0, 6)
local pad = Instance.new("UIPadding", tipText) pad.PaddingTop = UDim.new(0, 4) pad.PaddingBottom = UDim.new(0, 4)
tipText.Parent = tip
tip.Parent = player:WaitForChild("PlayerGui")

local function playerAt(screenPos: Vector2)
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local ray = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 160, params)
	if not hit then return nil end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorOfClass("Model")
	end
	local p = model and Players:GetPlayerFromCharacter(model)
	if p and p ~= player and p.Team == nil then return p, model end
	return nil
end
local hoverAcc = 0
RunService.RenderStepped:Connect(function(dt)
	hoverAcc += dt
	if hoverAcc < 0.1 then return end
	hoverAcc = 0
	if not inLobby() or UIS.TouchEnabled and not UIS.MouseEnabled then
		hl.Enabled, tip.Enabled = false, false
		return
	end
	local m = UIS:GetMouseLocation()
	local over = (#player.PlayerGui:GetGuiObjectsAtPosition(m.X, m.Y - 36) > 0)
	local p, model = nil, nil
	if not over then p, model = playerAt(m) end
	if p then
		hl.Adornee = model hl.Enabled = true
		tip.Adornee = model:FindFirstChild("Head") or model.PrimaryPart tip.Enabled = true
	else
		hl.Enabled, tip.Enabled = false, false
	end
end)
local pressAt, pressPos
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pressAt, pressPos = os.clock(), Vector2.new(input.Position.X, input.Position.Y)
	end
end)
UIS.InputEnded:Connect(function(input, gp)
	if gp or not pressAt then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	local quick = os.clock() - pressAt < 0.35 and (pos - pressPos).Magnitude < 12
	pressAt = nil
	if not quick or not inLobby() then return end
	local inset = game:GetService("GuiService"):GetGuiInset()
	local p = playerAt(pos + inset)
	if p and Lobby and Lobby.Nav and Lobby.Nav.Profile then
		Lobby.Nav.Profile(p)
	end
end)

-- ── spawn effect ──────────────────────────────────────────────────────────────────────
local function spawnFX(char)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root then return end
	task.wait(0.2) -- LobbyService places the character a frame after spawn
	if not root.Parent or not onDeck(root.Position) then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local feet = root.Position - Vector3.new(0, (hum and hum.HipHeight or 2) + root.Size.Y / 2 - 0.1, 0)
	local folder = Instance.new("Folder")
	folder.Name = "SpawnFX"
	folder.Parent = workspace.CurrentCamera
	local function part(props)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(60, 150, 255)
		for k, v in props do p[k] = v end
		p.Parent = folder
		return p
	end
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 2, 2), CFrame = CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.1 })
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, 10, 10), Transparency = 1 }):Play()
	local col = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 3.2, 3.2), CFrame = CFrame.new(feet + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.55, Color = Color3.fromRGB(120, 185, 255) })
	TweenService:Create(col, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(11, 0.2, 0.2), Transparency = 1 }):Play()
	local att = Instance.new("Attachment")
	att.WorldPosition = feet
	local base = part({ Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(feet) })
	att.Parent = base
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(110, 180, 255))
	pe.LightEmission = 0.7
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Speed = NumberRange.new(3, 8)
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Shape = Enum.ParticleEmitterShape.Disc
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(36)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 165, 255) light.Range = 14 light.Brightness = 3
	light.Parent = base
	TweenService:Create(light, TweenInfo.new(0.9), { Brightness = 0 }):Play()
	if SPAWN_SOUND then
		local s = Instance.new("Sound")
		s.SoundId = SPAWN_SOUND s.Volume = 0.45 s.RollOffMaxDistance = 60
		s.Parent = base
		s:Play()
	end
	Debris:AddItem(folder, 2)
end
local function watch(p)
	p.CharacterAdded:Connect(function(c) task.spawn(spawnFX, c) end)
	if p.Character then task.spawn(spawnFX, p.Character) end
end
for _, p in Players:GetPlayers() do watch(p) end
Players.PlayerAdded:Connect(watch)

-- ── dropship flyby past the Overlook ──────────────────────────────────────────────────
local shipSrc = RS:WaitForChild("Vantage"):WaitForChild("Aircraft"):WaitForChild("AircraftModel", 10)
task.spawn(function()
	task.wait(25)
	while true do
		local cam = workspace.CurrentCamera
		if shipSrc and cam and onDeck(cam.CFrame.Position) and inLobby() then
			local ship = shipSrc:Clone()
			for _, d in ship:GetDescendants() do
				if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false end
			end
			ship:ScaleTo(0.62)
			local dir = math.random() < 0.5 and 1 or -1
			local z = math.random(300, 420)
			local a = Vector3.new(-760 * dir, LOBBY_Y + math.random(40, 80), z)
			local b = Vector3.new(760 * dir, LOBBY_Y + math.random(20, 60), z + math.random(-60, 60))
			ship.Parent = cam
			local snd = Instance.new("Sound")
			snd.SoundId = PASS_SOUND snd.Volume = 0.8 snd.RollOffMinDistance = 80 snd.RollOffMaxDistance = 900 snd.Looped = true
			snd.Parent = ship:FindFirstChildWhichIsA("BasePart", true)
			snd:Play()
			local t, T = 0, 16
			local conn
			conn = RunService.RenderStepped:Connect(function(dt)
				t += dt
				local f = math.clamp(t / T, 0, 1)
				local pos = a:Lerp(b, f)
				local fwd = (b - a).Unit
				-- model nose is -Z; bank gently into the turn
				ship:PivotTo(CFrame.lookAt(pos, pos + fwd) * CFrame.Angles(0, 0, math.rad(8 * dir * math.sin(f * math.pi))))
				if f >= 1 then
					conn:Disconnect()
					ship:Destroy()
				end
			end)
			task.wait(T + 1)
		end
		task.wait(math.random(60, 110))
	end
end)

-- ── camera follows the lobby character ────────────────────────────────────────────────
-- After a match the old character is destroyed and the results sequence restores the camera while it still
-- points at the old Humanoid, which leaves the view hanging over the arena. While on the deck with a normal
-- (Custom) camera, keep the subject on the current character. Cinematics (Scriptable) are never touched.
task.spawn(function()
	while true do
		task.wait(0.5)
		local cam = workspace.CurrentCamera
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if cam and hum and inLobby() and cam.CameraType == Enum.CameraType.Custom then
			local subj = cam.CameraSubject
			if not subj or not subj:IsDescendantOf(char) then
				cam.CameraSubject = hum
			end
		end
	end
end)
