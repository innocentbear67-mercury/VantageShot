--[[
	VANTAGE — DeathReplay (client)
	Instant death replay, rebuilt from what THIS client saw. Nothing is recorded on or streamed
	from the server, so it costs no network traffic and never touches anyone else's game.
	Rolling buffer (EliminationConfig.Replay.Buffer seconds, RecordRate Hz):
	  · our own camera CFrame + FOV, exactly as rendered (look direction, movement, recoil)
	  · the world CFrame of every part of every other character (players; dummies in Studio),
	    i.e. their replicated positions, poses and held weapons as they appeared on our screen
	  · shots / knife swings the server relayed to us (WeaponEvent "Shot" / "Melee")
	The killer, weapon, headshot and distance come from the server's "Died" message.
	On death (after a short look at the body) it plays from our own eyes: the last seconds,
	the final moment in slow motion with the fatal shot flashed, then the camera turns to the
	attacker (outlined through walls). Other characters are anchored ghost copies posed from
	the buffer; the live ones are hidden locally meanwhile. Skippable (Space / A / button).
	Limits: positions are the replicated ones we received (what we saw, not the attacker's or
	the server's view); our own viewmodel and body are not shown; map, drops and non-shot
	effects are live, not replayed.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ElimConfig = require(ReplicatedStorage.Vantage.Elimination.EliminationConfig)
local R = ElimConfig.Replay
local COL = ElimConfig.Colors
local ReplayRemote = ReplicatedStorage.Vantage.Remotes:WaitForChild("DeathReplay") :: RemoteEvent

local REC_BIND = "VantageReplayRecord"
local PLAY_BIND = "VantageReplayPlay"
local FONT = Enum.Font.GothamBold
local FONT_HEAVY = Enum.Font.GothamBlack
local V2 = Vector2.new

local DeathReplay = {}
local player = Players.LocalPlayer
local effects = nil
local frames = {} -- { t, Cam, Fov, Models = { [Model] = { Parts, CFs } } }
local events = {} -- { t, Kind = "Shot" | "Melee", Model, EndPos, Normal?, HitKind?, Material? }
local tracked = {} -- [Model] = { Parts, Dirty, Conns }
local alive = false
local lastCam: CFrame? = nil
local lastFov = 70
local nextSample = 0
local session = nil -- the replay currently playing

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function tween(i, t, props)
	local tw = TweenService:Create(i, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function smooth(a)
	return a * a * (3 - 2 * a)
end

-- ─── recording ─────────────────────────────────────────────────────────────────────
local function untrack(model: Model)
	local rec = tracked[model]
	if rec then
		for _, c in rec.Conns do
			c:Disconnect()
		end
		tracked[model] = nil
	end
end

local function track(model: Model)
	if tracked[model] or model == player.Character then
		return
	end
	local rec = { Parts = {}, Dirty = true, Conns = {} }
	tracked[model] = rec
	local function dirty()
		rec.Dirty = true
	end
	table.insert(rec.Conns, model.DescendantAdded:Connect(dirty))
	table.insert(rec.Conns, model.DescendantRemoving:Connect(dirty))
	table.insert(rec.Conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			untrack(model)
		end
	end))
end

local function prune(list, cutoff: number)
	local n = 0
	while list[n + 1] and list[n + 1].t < cutoff do
		n += 1
	end
	if n > 0 then
		-- 2026-11-20 perf: shift in place (was a new table every sample: GC churn -> hitches)
		local len = #list
		table.move(list, n + 1, len, 1)
		for i = len - n + 1, len do
			list[i] = nil
		end
	end
	return list
end

local function sample(now: number)
	local cam = Workspace.CurrentCamera
	if alive then
		lastCam, lastFov = cam.CFrame, cam.FieldOfView
	end
	if not lastCam then
		return
	end
	local models = {}
	for model, rec in tracked do
		if rec.Dirty then
			rec.Dirty = false
			local parts = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			rec.Parts = parts
		end
		local cfs = table.create(#rec.Parts)
		for i, p in rec.Parts do
			cfs[i] = p.CFrame
		end
		models[model] = { Parts = rec.Parts, CFs = cfs }
	end
	table.insert(frames, { t = now, Cam = lastCam, Fov = lastFov, Models = models })
	frames = prune(frames, now - R.Buffer)
	events = prune(events, now - R.Buffer)
end

local function recordStep()
	if session then
		return
	end
	local now = os.clock()
	if now >= nextSample then
		nextSample = now + 1 / R.RecordRate
		sample(now)
	end
end

function DeathReplay.RecordShot(model: any, endPos: any, normal: any, kind: any, material: any)
	if session or typeof(model) ~= "Instance" or typeof(endPos) ~= "Vector3" then
		return
	end
	table.insert(events, { t = os.clock(), Kind = "Shot", Model = model, EndPos = endPos, Normal = normal, HitKind = kind, Material = material })
end

function DeathReplay.RecordMelee(model: any, pos: any)
	if session or typeof(model) ~= "Instance" then
		return
	end
	table.insert(events, { t = os.clock(), Kind = "Melee", Model = model, EndPos = pos })
end

-- ─── playback ──────────────────────────────────────────────────────────────────────
-- the two frames around recorded time t, and the blend between them
local function bracket(t: number)
	local lo, hi = 1, #frames
	if t <= frames[lo].t then
		return frames[lo], frames[lo], 0
	end
	if t >= frames[hi].t then
		return frames[hi], frames[hi], 0
	end
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if frames[mid].t <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = frames[lo], frames[hi]
	return a, b, (t - a.t) / math.max(1e-4, b.t - a.t)
end

local function stripTags(inst: Instance)
	for _, tag in CollectionService:GetTags(inst) do
		CollectionService:RemoveTag(inst, tag)
	end
end

-- Anchored, script-free, joint-free copy of a character; Map links its parts to the originals.
local function makeGhost(model: Model, parent: Instance)
	if not model:IsDescendantOf(Workspace) then
		return nil
	end
	local originals = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(originals, d)
			d:SetAttribute("VReplayId", #originals)
		end
	end
	local archivable = model.Archivable
	model.Archivable = true
	local ok, clone = pcall(function()
		return model:Clone()
	end)
	model.Archivable = archivable
	for _, p in originals do
		p:SetAttribute("VReplayId", nil)
	end
	if not ok or not clone then
		return nil
	end
	local map = {}
	stripTags(clone)
	for _, d in clone:GetDescendants() do
		stripTags(d)
		if d:IsA("BasePart") then
			local id = d:GetAttribute("VReplayId")
			d:SetAttribute("VReplayId", nil)
			if id and originals[id] then
				map[originals[id]] = d
			end
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("WeldConstraint")
			or d:IsA("NoCollisionConstraint") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.EvaluateStateMachine = false
			d.BreakJointsOnDeath = false
		end
	end
	clone.Parent = parent
	return { Model = clone, Map = map }
end

-- live characters (players, dummies), hidden while the ghosts stand in for them
local function liveParts()
	local list = {}
	local function add(m: Instance?)
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
		end
	end
	for _, p in Players:GetPlayers() do
		add(p.Character)
	end
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		for _, m in CollectionService:GetTagged("VantageDummy") do
			add(m)
		end
	end
	return list
end

local function pose(s, t: number, cam: Camera)
	local a, b, u = bracket(t)
	cam.CFrame = a.Cam:Lerp(b.Cam, u)
	cam.FieldOfView = a.Fov + (b.Fov - a.Fov) * u
	local parts, cfs = {}, {}
	for model, ghost in s.Ghosts do
		local fa, fb = a.Models[model], b.Models[model]
		if not fa and not fb then
			-- not in the world at this moment (spawned later / already gone)
			ghost.Model.Parent = nil
			continue
		end
		ghost.Model.Parent = s.Folder
		local fr = fa or fb
		local other = if fa and fb and fa.Parts == fb.Parts then fb else nil
		for i, p in fr.Parts do
			local g = ghost.Map[p]
			if g then
				table.insert(parts, g)
				table.insert(cfs, if other then fr.CFs[i]:Lerp(other.CFs[i], u) else fr.CFs[i])
			end
		end
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function fatalFlash(s, e)
	if typeof(e.EndPos) ~= "Vector3" then
		return
	end
	local p = new("Part", { Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), Size = Vector3.one * 0.4, CFrame = CFrame.new(e.EndPos), Transparency = 0.1 }, s.Folder)
	tween(p, 0.35, { Size = Vector3.one * 2.2, Transparency = 1 })
	local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75, BorderSizePixel = 0 }, s.Ui.Gui)
	tween(flash, 0.3, { BackgroundTransparency = 1 })
end

local function fireEvents(s, from: number, to: number)
	for _, e in events do
		if e.t > from and e.t <= to then
			local ghost = s.Ghosts[e.Model]
			if ghost then
				if e.Kind == "Shot" then
					local w = ghost.Model:FindFirstChild("VantageWorldWeapon")
					local muzzle = w and w.PrimaryPart and w.PrimaryPart:FindFirstChild("Muzzle")
					if muzzle then
						pcall(function()
							effects:MuzzleFlash(muzzle)
							effects:Tracer(muzzle.WorldPosition, e.EndPos)
							effects:PlayFire3D(w:GetAttribute("WeaponId"), muzzle, ghost.Model)
						end)
					end
					if e.Normal and e.HitKind then
						pcall(function()
							effects:Impact(e.EndPos, e.Normal, e.HitKind, e.Material, w and w:GetAttribute("WeaponId"))
						end)
					end
				else
					local k = ghost.Model:FindFirstChild("VantageWorldKnife")
					if k and k.PrimaryPart then
						pcall(function()
							effects:PlayCue("Knife", "Swing", k.PrimaryPart)
						end)
					end
				end
			end
			if e == s.Fatal then
				fatalFlash(s, e)
			end
		end
	end
end

local function fitScale(): number
	local vp = Workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.6, 1.25)
end

local function buildUi(info)
	local gui = new("ScreenGui", { Name = "VantageDeathReplay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9 }, player:WaitForChild("PlayerGui"))
	local scale = fitScale()
	local black = Color3.new(0, 0, 0)
	-- cinematic bars
	local top = new("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor3 = black, BorderSizePixel = 0 }, gui)
	local bottom = new("Frame", { AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = black, BorderSizePixel = 0 }, gui)
	tween(top, 0.35, { Size = UDim2.fromScale(1, 0.065) })
	tween(bottom, 0.35, { Size = UDim2.fromScale(1, 0.065) })
	-- DEATH REPLAY tag
	local tag = new("Frame", { Position = UDim2.new(0, 28, 0.065, 16), Size = UDim2.fromOffset(190, 34), BackgroundColor3 = COL.Panel, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, gui)
	new("UIScale", { Scale = scale }, tag)
	new("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = COL.Accent, BorderSizePixel = 0 }, tag)
	local dot = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = COL.Kill, BorderSizePixel = 0 }, tag)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	new("TextLabel", { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -40, 1, 0), BackgroundTransparency = 1, Font = FONT_HEAVY, Text = "DEATH REPLAY", TextColor3 = COL.Neutral, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left }, tag)
	local slow = new("TextLabel", { AnchorPoint = V2(0, 0.5), Position = UDim2.new(1, 10, 0.5, 0), Size = UDim2.fromOffset(80, 20), BackgroundTransparency = 1, Font = FONT, Text = "SLOW-MO", TextColor3 = COL.Accent, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Visible = false }, tag)
	-- attacker card
	local card = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 0.935, -14), Size = UDim2.fromOffset(400, 96), BackgroundColor3 = COL.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0 }, gui)
	new("UIScale", { Scale = scale }, card)
	new("UIStroke", { Color = COL.Accent, Transparency = 0.6, Thickness = 1 }, card)
	new("Frame", { Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = COL.Kill, BorderSizePixel = 0 }, card)
	new("TextLabel", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = FONT, Text = "ELIMINATED BY", TextColor3 = COL.Kill, TextSize = 11 }, card)
	new("TextLabel", { Position = UDim2.fromOffset(16, 24), Size = UDim2.new(1, -32, 0, 28), BackgroundTransparency = 1, Font = FONT_HEAVY, Text = string.upper(tostring(info.Killer or "UNKNOWN")), TextColor3 = COL.Neutral, TextSize = 24, TextTruncate = Enum.TextTruncate.AtEnd }, card)
	local bits = {}
	if type(info.Weapon) == "string" and info.Weapon ~= "" then
		table.insert(bits, string.upper(info.Weapon))
	end
	if type(info.Distance) == "number" then
		table.insert(bits, string.format("%d STUDS", math.floor(info.Distance + 0.5)))
	end
	local row = new("Frame", { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	if #bits > 0 then
		new("TextLabel", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BackgroundTransparency = 1, Font = FONT, Text = table.concat(bits, "   ·   "), TextColor3 = Color3.fromRGB(170, 180, 196), TextSize = 13, LayoutOrder = 1 }, row)
	end
	if info.Headshot then
		new("TextLabel", { Size = UDim2.fromOffset(84, 18), BackgroundColor3 = COL.Headshot, BorderSizePixel = 0, Font = FONT_HEAVY, Text = "HEADSHOT", TextColor3 = COL.Ink, TextSize = 11, LayoutOrder = 2 }, row)
	end
	local bar = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -32, 0, 3), BackgroundColor3 = COL.Neutral, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, card)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = COL.Accent, BorderSizePixel = 0 }, bar)
	-- skip
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local skip = new("TextButton", { AnchorPoint = V2(1, 1), Position = UDim2.new(1, -28, 0.935, -14), Size = UDim2.fromOffset(132, 34), BackgroundColor3 = COL.Panel, BackgroundTransparency = 0.12, BorderSizePixel = 0, Font = FONT, Text = if touchOnly then "SKIP  ›" else "[SPACE]  SKIP", TextColor3 = COL.Neutral, TextSize = 13 }, gui)
	new("UIScale", { Scale = scale }, skip)
	new("UIStroke", { Color = COL.Neutral, Transparency = 0.75, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, skip)
	return { Gui = gui, Fill = fill, Slow = slow, Dot = dot, Skip = skip }
end

local function finish(s, fade: boolean)
	if s.Finished then
		return
	end
	s.Finished = true
	RunService:UnbindFromRenderStep(PLAY_BIND)
	for _, c in s.Conns do
		c:Disconnect()
	end
	local function cleanup()
		for d, v in s.Saved do
			if d.Parent then
				d.LocalTransparencyModifier = v
			end
		end
		s.Folder:Destroy()
		if s.Ui then
			s.Ui.Gui:Destroy()
		end
		Workspace.CurrentCamera.FieldOfView = s.Fov0
		if session == s then
			session = nil
		end
		ReplayRemote:FireServer("Done") -- lets the server respawn us now
	end
	if fade then
		-- stays black until the respawn fades back in (DeathPresenter.LocalSpawn)
		s.Hud:Fade(true, 0.2)
		task.delay(0.22, cleanup)
	else
		cleanup()
	end
end

local function nameTag(head: BasePart, name: string)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(180, 22), StudsOffset = Vector3.new(0, 2, 0), AlwaysOnTop = true, LightInfluence = 0 }, head)
	local l = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT_HEAVY, Text = string.upper(name), TextColor3 = COL.Kill, TextSize = 14 }, bb)
	new("UIStroke", { Color = COL.Ink, Thickness = 1.2, Transparency = 0.3 }, l)
end

local function play(character: Model, hud, info, tDeath: number)
	local tEnd = tDeath + R.After
	local tStart = math.max(frames[1].t, tDeath - R.Window)
	local cam = Workspace.CurrentCamera
	local s = { Hud = hud, Conns = {}, Saved = {}, Ghosts = {}, Fov0 = cam.FieldOfView }
	session = s
	s.Folder = new("Folder", { Name = "VantageReplay" }, Workspace)

	-- ghosts for every character seen during the window (clones of how they look now)
	local seen = {}
	for _, f in frames do
		if f.t >= tStart - 0.1 then
			for model in f.Models do
				seen[model] = true
			end
		end
	end
	for model in seen do
		s.Ghosts[model] = makeGhost(model, s.Folder)
	end
	local killerGhost = info.KillerModel and s.Ghosts[info.KillerModel]
	if killerGhost then
		new("Highlight", { Adornee = killerGhost.Model, FillColor = COL.Kill, FillTransparency = 0.8, OutlineColor = COL.Kill, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, killerGhost.Model)
		local head = killerGhost.Model:FindFirstChild("Head")
		if head then
			nameTag(head, tostring(info.Killer))
		end
	end
	-- the attacker's last relayed shot / swing before the death is the fatal one
	for _, e in events do
		if e.Model == info.KillerModel and e.t <= tEnd then
			s.Fatal = e
		end
	end
	s.Ui = buildUi(info)
	hud:HideDeath()
	hud:Fade(false, 0.25)
	cam.CameraType = Enum.CameraType.Scriptable

	local rt, lastRt = tStart, tStart - 1e-3
	local phase = "Replay"
	local revealT, revealFrom, revealFov = 0, cam.CFrame, s.Fov0
	local total = (tDeath - R.SlowLast - tStart) + (R.SlowLast + R.After) / R.SlowSpeed + R.Reveal
	local elapsed, hideAt, hidden = 0, 0, {}

	table.insert(s.Conns, UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			finish(s, true)
		end
	end))
	table.insert(s.Conns, s.Ui.Skip.Activated:Connect(function()
		finish(s, true)
	end))

	RunService:BindToRenderStep(PLAY_BIND, Enum.RenderPriority.Last.Value, function(dt)
		if player.Character ~= character then
			finish(s, false) -- respawned underneath us: hand straight back
			return
		end
		elapsed += dt
		local now = os.clock()
		if now >= hideAt then
			hideAt = now + 0.5
			hidden = liveParts()
		end
		for _, d in hidden do
			if s.Saved[d] == nil then
				s.Saved[d] = d.LocalTransparencyModifier
			end
			d.LocalTransparencyModifier = 1
		end
		if phase == "Replay" then
			local slow = rt >= tDeath - R.SlowLast
			rt = math.min(rt + dt * (if slow then R.SlowSpeed else 1), tEnd)
			s.Ui.Slow.Visible = slow
			pose(s, rt, cam)
			fireEvents(s, lastRt, rt)
			lastRt = rt
			if rt >= tEnd then
				phase = "Reveal"
				revealFrom, revealFov = cam.CFrame, cam.FieldOfView
				s.Ui.Slow.Visible = false
			end
		else
			-- turn to face the attacker and push in a little
			revealT += dt
			local a = smooth(math.clamp(revealT / (R.Reveal * 0.6), 0, 1))
			local head = killerGhost and killerGhost.Model:FindFirstChild("Head")
			local target = if head then head.Position else info.KillerPosition
			if typeof(target) == "Vector3" and (target - revealFrom.Position).Magnitude > 0.5 then
				cam.CFrame = revealFrom:Lerp(CFrame.lookAt(revealFrom.Position, target), a)
				cam.FieldOfView = revealFov + (math.max(revealFov - 25, 40) - revealFov) * a
			end
			if revealT >= R.Reveal then
				finish(s, true)
				return
			end
		end
		s.Ui.Fill.Size = UDim2.fromScale(math.clamp(elapsed / total, 0, 1), 1)
		s.Ui.Dot.BackgroundTransparency = 0.5 + 0.5 * math.sin(now * 8)
	end)
end

--[[ Local player died. getInfo() returns the server's "Died" info once it has arrived;
	stopDeathCam ends DeathPresenter's death camera when the replay takes over. ]]
function DeathReplay.OnDeath(character: Model, hud, getInfo: () -> any, stopDeathCam: (() -> ())?)
	alive = false
	local tDeath = os.clock()
	task.delay(R.Delay, function()
		if player.Character ~= character or session then
			return
		end
		local info = getInfo()
		local ok = info and info.HasKiller and #frames > 0 and tDeath - frames[1].t >= R.MinBuffer
		if not ok then
			-- environmental death / no history: the normal death camera + respawn carry on
			ReplayRemote:FireServer("Done")
			return
		end
		hud:Fade(true, 0.2)
		task.wait(0.22)
		if player.Character ~= character then
			return
		end
		if stopDeathCam then
			stopDeathCam()
		end
		local played, err = pcall(play, character, hud, info, tDeath)
		if not played then
			warn("[DeathReplay] " .. tostring(err))
			if session then
				finish(session, false)
			else
				ReplayRemote:FireServer("Done")
			end
		end
	end)
end

function DeathReplay.OnSpawn()
	if session then
		finish(session, false)
	end
	alive = true
	frames, events = {}, {}
	lastCam = nil
end

function DeathReplay.Start(fx)
	effects = fx
	local function onPlayer(plr: Player)
		if plr == player then
			return
		end
		plr.CharacterAdded:Connect(track)
		if plr.Character then
			track(plr.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		CollectionService:GetInstanceAddedSignal("VantageDummy"):Connect(track)
		for _, m in CollectionService:GetTagged("VantageDummy") do
			track(m)
		end
	end
	RunService:BindToRenderStep(REC_BIND, Enum.RenderPriority.Last.Value, recordStep)
end

return DeathReplay
