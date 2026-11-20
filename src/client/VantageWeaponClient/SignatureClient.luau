--!nocheck
--[[
	VANTAGE — SignatureClient (2026-11-20): Shift / L1 (or a tap on the HUD tile) casts the equipped Signature.
	The client only sends where the camera looks; SignatureServer validates, builds the geometry, decides hits
	and broadcasts "Begin" so every client plays the same FX.<Id> module. The caster's own client also moves
	its character for Valkyrie / Sleipnir / Bifröst (the FX's Move callback; the server exempts the validator).
	Remotes.Status "Impulse" applies knockbacks / knock-ups to this player through MovementController.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Sig = Vantage:WaitForChild("Signatures")
local Catalog = require(Sig:WaitForChild("SignatureCatalog"))
local Cfg = require(Sig:WaitForChild("SignatureConfig"))
local Feed = require(Sig:WaitForChild("SignatureFeed"))
local Lock = require(Sig:WaitForChild("SignatureLock")) -- ray helpers only (no lock-on since 2026-11-20)
local FX = Sig:WaitForChild("FX")
local player = Players.LocalPlayer

local MovementController
pcall(function()
	MovementController = require(player:WaitForChild("PlayerScripts"):WaitForChild("VantageMovementClient"):WaitForChild("MovementController"))
end)

local SignatureClient = {}
local modules = {}
local function fx(id)
	if modules[id] == nil then
		local m = FX:FindFirstChild(id)
		local ok, mod = pcall(function() return m and require(m) end)
		modules[id] = (ok and mod) or false
	end
	return modules[id] or nil
end

local MOVERS = { Valkyrie = true, Sleipnir = true, Bifrost = true }
local STUDIO = game:GetService("RunService"):IsStudio()
local function devFree() return STUDIO and player:GetAttribute("DevSigNoCooldown") == true end
local DEV_ORDER = { "Mjolnir", "Fenrir", "Gungnir", "Midgard", "Valkyrie", "Ragnarok", "Helheim", "Sleipnir", "Bifrost", "Yggdrasil" }

local function teamOf(m)
	local pl = Players:GetPlayerFromCharacter(m)
	if pl then return if pl.Team and not pl.Neutral then pl.Team.Name else nil end
	return m:GetAttribute("Team")
end
local function isEnemyOf(caster, m)
	if caster.Character == m then return false end
	local a = if caster.Team and not caster.Neutral then caster.Team.Name else nil
	local b = teamOf(m)
	return not (a and b and a == b)
end
-- living enemies of the caster (torso parts), for the FX's own hit reactions
local function enemyTargets(caster)
	local out, seen = {}, {}
	local function consider(m)
		if seen[m] then return end
		seen[m] = true
		local hum = m:FindFirstChildOfClass("Humanoid")
		local body = m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and body and isEnemyOf(caster, m) then table.insert(out, body) end
	end
	for _, pl in Players:GetPlayers() do if pl.Character then consider(pl.Character) end end
	for _, m in Workspace:GetChildren() do if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then consider(m) end end
	return out
end

-- the caster's right hand each frame (first person: a camera-space hand so the caster sees it)
local function handFn(caster)
	local last = CFrame.new()
	return function()
		local ch = caster.Character
		if caster == player then
			local cam = Workspace.CurrentCamera
			local head = ch and ch:FindFirstChild("Head")
			if cam and (not head or (cam.CFrame.Position - head.Position).Magnitude < 2.5) then
				last = cam.CFrame * CFrame.new(1.15, -1.05, -2.4)
				return last
			end
		end
		local hand = ch and (ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm"))
		if hand then
			last = hand.CFrame
		else
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp then last = hrp.CFrame * CFrame.new(1.5, 0.6, -1) end
		end
		return last
	end
end

-- the caster's own character follows the FX (MovementController pauses while VantageSigMove is set)
local function mover()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return nil, function() end end
	ch:SetAttribute("VantageSigMove", true)
	return function(cf)
		if root.Parent then
			root.CFrame = cf
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end, function()
		if ch.Parent then ch:SetAttribute("VantageSigMove", nil) end
	end
end

local function buildArgs(d, caster)
	local a = {}
	for k, v in d do a[k] = v end
	a.Id, a.Caster, a.T = nil, nil, nil
	a.Hand = handFn(caster)
	a.Targets = enemyTargets(caster)
	local c = Cfg.Sig[d.Id] or {}
	if d.Id == "Mjolnir" then
		local wps = {}
		for _, m in (type(d.Targets) == "table" and d.Targets or {}) do
			if typeof(m) == "Instance" then
				local last
				table.insert(wps, function()
					local b = m.Parent and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart"))
					if b then last = b.Position end
					return last
				end)
			end
		end
		a.Targets = {}
		a.Waypoints = wps
		a.OutSpeed, a.ReturnSpeed, a.Hang = c.OutSpeed, c.ReturnSpeed, c.Hang
	elseif d.Id == "Valkyrie" then
		a.Enemy = isEnemyOf(caster, player.Character or Instance.new("Model"))
	elseif d.Id == "Yggdrasil" then
		a.Targets = nil
	end
	return a
end

function SignatureClient.Start(ctx)
	local input, hud = ctx.Input, ctx.Hud
	local Remotes = Vantage:WaitForChild("Remotes")
	local Remote = Remotes:WaitForChild("Signature", 30)
	if not Remote then
		warn("[VANTAGE] SignatureClient: no Signature remote")
		return
	end
	local function sync()
		Feed.Id = Catalog.Equipped(player)
		local c = Cfg.Sig[Feed.Id]
		Feed.Cooldown = c and c.Cooldown or 40
	end
	sync()
	player:GetAttributeChangedSignal("Signature"):Connect(sync)
	player:GetAttributeChangedSignal("OwnedSignatures"):Connect(sync)

	local function canCast()
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not (ch and hum and hum.Health > 0) then return false end
		if hud and hud.Gui and not hud.Gui.Enabled then return false end -- only in a match
		if input and input.Blocked then return false end
		if player:GetAttribute("VisorBlackout") or player:GetAttribute("VantageHangingLocal") or player:GetAttribute("VantageVehicleLocal") then return false end
		if ch:GetAttribute("InVehicle") then return false end
		if (ch:GetAttribute("Status_FrozenUntil") or 0) > Workspace:GetServerTimeNow() then
			Feed.Denied = { Text = "FROZEN", At = os.clock() }
			return false
		end
		local match = Vantage:FindFirstChild("Match")
		if match and match:GetAttribute("Combat") == false then
			Feed.Denied = { Text = "COMBAT OFFLINE", At = os.clock() }
			return false
		end
		return true
	end
	------------------------------------------------ 2026-11-20 rework: lock-on brackets, MARKED warning, Bifröst map picker
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local GuiService = game:GetService("GuiService")
	local pgui = player:WaitForChild("PlayerGui")
	local SIGCOL = {
		Mjolnir = Color3.fromRGB(150, 205, 255), Fenrir = Color3.fromRGB(175, 228, 255), Gungnir = Color3.fromRGB(255, 212, 110),
		Midgard = Color3.fromRGB(60, 235, 200), Valkyrie = Color3.fromRGB(255, 222, 140), Ragnarok = Color3.fromRGB(255, 140, 50),
		Helheim = Color3.fromRGB(150, 210, 255), Sleipnir = Color3.fromRGB(165, 190, 255), Bifrost = Color3.fromRGB(255, 255, 255), Yggdrasil = Color3.fromRGB(70, 230, 130),
	}
	local function sigName(id) local it = Catalog.ById[id]; return string.upper(it and it.Name or tostring(id)) end
	local function corner(parent, r) local c = Instance.new("UICorner"); c.CornerRadius = r or UDim.new(1, 0); c.Parent = parent; return c end
	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBlack; l.TextColor3 = Color3.new(1, 1, 1); l.TextStrokeTransparency = 0.5
		for k, v in props do l[k] = v end
		l.Parent = parent
		return l
	end
	local bif = { Open = false }

	-- 2026-11-20 balance pass: no lock-on. Instead, any enemy Signature whose telegraphed zone / lane you are
	-- standing in shows a DODGE prompt: the outer ring closes on the inner one at the moment of contact and
	-- turns green inside the dodge window. Press DODGE (Cfg.Dodge.Key) while it is green, or get out of the zone.
	local DG = Cfg.Dodge or { Window = 0.4, Lockout = 1.5, Warn = 1.4, KeyLabel = "Z" }
	local threats = {}
	local dodgeLast = -1e9
	local dgGui = Instance.new("ScreenGui")
	dgGui.Name = "VantageDodge"; dgGui.ResetOnSpawn = false; dgGui.IgnoreGuiInset = true; dgGui.DisplayOrder = 61; dgGui.Enabled = false
	dgGui.Parent = pgui
	local dgRoot = Instance.new("Frame")
	dgRoot.AnchorPoint = Vector2.new(0.5, 0.5); dgRoot.Position = UDim2.fromScale(0.5, 0.62); dgRoot.Size = UDim2.fromOffset(84, 84); dgRoot.BackgroundTransparency = 1
	dgRoot.Parent = dgGui
	local dgCore = Instance.new("Frame")
	dgCore.AnchorPoint = Vector2.new(0.5, 0.5); dgCore.Position = UDim2.fromScale(0.5, 0.5); dgCore.Size = UDim2.fromScale(1, 1); dgCore.BackgroundTransparency = 0.55
	dgCore.BackgroundColor3 = Color3.fromRGB(10, 12, 20); dgCore.Parent = dgRoot
	corner(dgCore)
	local dgCoreStroke = Instance.new("UIStroke"); dgCoreStroke.Thickness = 3; dgCoreStroke.Color = Color3.new(1, 1, 1); dgCoreStroke.Parent = dgCore
	local dgKey = label(dgCore, { Size = UDim2.fromScale(1, 1), TextSize = 34, Text = DG.KeyLabel or "Z" })
	local dgRing = Instance.new("Frame")
	dgRing.AnchorPoint = Vector2.new(0.5, 0.5); dgRing.Position = UDim2.fromScale(0.5, 0.5); dgRing.BackgroundTransparency = 1; dgRing.Parent = dgRoot
	corner(dgRing)
	local dgRingStroke = Instance.new("UIStroke"); dgRingStroke.Thickness = 4; dgRingStroke.Parent = dgRing
	local dgText = label(dgRoot, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -16), Size = UDim2.fromOffset(520, 30), TextSize = 24, Text = "" })
	local dgSub = label(dgRoot, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 14), Size = UDim2.fromOffset(520, 18), TextSize = 14,
		Font = Enum.Font.GothamBold, Text = "" })
	local toast = label(dgGui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(700, 60), TextSize = 46, Text = "", TextTransparency = 1 })
	local toastAt, toastLen = -10, 1
	local function showToast(txt, col, len)
		toast.Text = txt; toast.TextColor3 = col; toastAt = os.clock(); toastLen = len or 1
		dgGui.Enabled = true
	end
	-- seconds until this threat reaches the local character (nil = it doesn't)
	local function etaFor(t, pos: Vector3, nowT: number): number?
		if t.Kind == "Self" then
			return t.Hit - nowT
		elseif t.Kind == "Circle" then
			local d = ((pos - t.At) * Vector3.new(1, 0, 1)).Magnitude
			if d <= t.R + 2.5 and math.abs(pos.Y - t.At.Y) < 16 then return t.Hit - nowT end
		elseif t.Kind == "Line" then
			local ab = t.B - t.A
			local l2 = ab:Dot(ab)
			local k = if l2 > 1e-6 then math.clamp((pos - t.A):Dot(ab) / l2, 0, 1) else 0
			local q = t.A + ab * k
			if ((pos - q) * Vector3.new(1, 0, 1)).Magnitude <= t.W + 2.5 and math.abs(pos.Y - q.Y) < 10 then
				return t.T0 + math.sqrt(l2) * k / math.max(t.Speed, 1) - nowT
			end
		elseif t.Kind == "Cone" then
			local v = (pos - t.O) * Vector3.new(1, 0, 1)
			local d = v.Magnitude
			local ang = if d > 1e-3 then math.deg(math.acos(math.clamp(v.Unit:Dot(t.Dir), -1, 1))) else 0
			if d <= t.R + 2 and ang <= t.Angle / 2 + 6 and math.abs(pos.Y - t.O.Y) < 14 then
				return t.Hit + (d / math.max(t.R, 1)) * (t.Wave or 0) - nowT
			end
		end
		return nil
	end
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local nowT = Workspace:GetServerTimeNow()
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local best, bestEta
		for i = #threats, 1, -1 do
			local th = threats[i]
			if nowT > th.Expire then
				table.remove(threats, i)
			elseif root and hum and hum.Health > 0 then
				local eta = etaFor(th, root.Position, nowT)
				if eta and eta > -0.15 and eta <= (DG.Warn or 1.4) and (not best or eta < bestEta) then best, bestEta = th, eta end
			end
		end
		local tk = t - toastAt
		local toastOn = tk < toastLen
		toast.TextTransparency = if toastOn then math.clamp((tk - (toastLen - 0.3)) / 0.3, 0, 1) else 1
		toast.TextStrokeTransparency = 0.3 + 0.7 * toast.TextTransparency
		if toastOn then
			local s = 1 + 0.25 * math.max(0, 1 - tk * 6)
			toast.Size = UDim2.fromOffset(700 * s, 60 * s)
		end
		dgRoot.Visible = best ~= nil
		dgGui.Enabled = best ~= nil or toastOn
		if best then
			local inWin = bestEta <= (DG.Window or 0.4)
			local ready = t - dodgeLast >= (DG.Lockout or 1.5)
			local col = if not ready then Color3.fromRGB(140, 140, 150) elseif inWin then Color3.fromRGB(80, 255, 140) else Color3.fromRGB(255, 70, 80)
			local k = math.clamp(bestEta / (DG.Warn or 1.4), 0, 1)
			local sz = 84 * (1 + 1.6 * k)
			dgRing.Size = UDim2.fromOffset(sz, sz)
			dgRingStroke.Color = col
			dgRingStroke.Transparency = 0.1
			dgCoreStroke.Color = col
			dgKey.TextColor3 = col
			dgText.TextColor3 = col
			dgText.Text = if inWin then "DODGE NOW!" else "⚠  " .. sigName(best.Id) .. " INCOMING"
			dgSub.Text = if ready then "PRESS [" .. (DG.KeyLabel or "Z") .. "] AS THE RING CLOSES  ·  OR GET OUT OF THE ZONE" else "DODGE RECHARGING"
			dgRoot.Size = UDim2.fromOffset(84, 84)
		end
	end)
	local function dodgePress()
		local t = os.clock()
		if t - dodgeLast < (DG.Lockout or 1.5) then return end
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not (hum and hum.Health > 0) then return end
		dodgeLast = t
		Remote:FireServer("Dodge", Workspace:GetServerTimeNow())
	end
	ContextActionService:BindActionAtPriority("VantageSigDodge", function(_, state)
		if state == Enum.UserInputState.Begin then
			if input and input.Blocked then return Enum.ContextActionResult.Pass end
			dodgePress()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3000, DG.Key or Enum.KeyCode.Z, DG.Gamepad or Enum.KeyCode.DPadDown)
	bif.AddThreat = function(d, caster)
		local th = d.Threat
		if type(th) ~= "table" or not caster or caster == player then return end
		if not isEnemyOf(caster, player.Character or Instance.new("Model")) then return end
		th.Id = d.Id
		local last = th.Hit or ((th.T0 or 0) + (if th.A and th.B then (th.B - th.A).Magnitude / math.max(th.Speed or 1, 1) else 0))
		th.Expire = last + (th.Wave or 0) + 0.5
		table.insert(threats, th)
	end
	bif.SelfThreat = function(d)
		if type(d.Hit) ~= "number" then return end
		for i = #threats, 1, -1 do
			if threats[i].Kind == "Self" and threats[i].Id == d.Id then table.remove(threats, i) end
		end
		table.insert(threats, { Kind = "Self", Id = d.Id, Hit = d.Hit, Expire = d.Hit + 0.4 })
	end
	bif.ShowDodged = function(d)
		if d.Mine then
			showToast(string.upper(tostring(d.Target or "ENEMY")) .. " DODGED " .. sigName(d.Id), Color3.fromRGB(255, 200, 90), 1.2)
		else
			showToast("DODGED!", Color3.fromRGB(80, 255, 140), 0.9)
		end
	end
	if STUDIO then
		player:GetAttributeChangedSignal("DevDodge"):Connect(function() dodgeLast = -1e9; dodgePress() end)
	end

	-- 2026-11-20 (pm): lock-on is back (homing Signatures); brackets restored
	-- lock brackets: the enemy this Signature will hit, shown while it is ready
	local lockBB = Instance.new("BillboardGui")
	lockBB.Name = "VantageSigLock"; lockBB.AlwaysOnTop = true; lockBB.LightInfluence = 0; lockBB.ResetOnSpawn = false
	lockBB.Size = UDim2.fromOffset(78, 78); lockBB.Enabled = false; lockBB.MaxDistance = 100000
	lockBB.Parent = pgui
	local lockFrame = Instance.new("Frame")
	lockFrame.AnchorPoint = Vector2.new(0.5, 0.5); lockFrame.Position = UDim2.fromScale(0.5, 0.5); lockFrame.Size = UDim2.fromScale(1, 1); lockFrame.BackgroundTransparency = 1
	lockFrame.Parent = lockBB
	local lockBars = {}
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1; holder.Size = UDim2.fromOffset(20, 20); holder.AnchorPoint = Vector2.new(c[1], c[2]); holder.Position = UDim2.fromScale(c[1], c[2])
		holder.Parent = lockFrame
		local h = Instance.new("Frame"); h.BorderSizePixel = 0; h.Size = UDim2.new(1, 0, 0, 3); h.AnchorPoint = Vector2.new(0, c[2]); h.Position = UDim2.fromScale(0, c[2]); h.Parent = holder
		local v = Instance.new("Frame"); v.BorderSizePixel = 0; v.Size = UDim2.new(0, 3, 1, 0); v.AnchorPoint = Vector2.new(c[1], 0); v.Position = UDim2.fromScale(c[1], 0); v.Parent = holder
		for _, bar in { h, v } do
			local st = Instance.new("UIStroke"); st.Thickness = 1.2; st.Transparency = 0.45; st.Color = Color3.new(0, 0, 0); st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = bar
			table.insert(lockBars, bar)
		end
	end
	local lockDot = Instance.new("Frame")
	lockDot.AnchorPoint = Vector2.new(0.5, 0.5); lockDot.Position = UDim2.fromScale(0.5, 0.5); lockDot.Size = UDim2.fromOffset(7, 7); lockDot.Rotation = 45; lockDot.BorderSizePixel = 0
	lockDot.Parent = lockFrame
	table.insert(lockBars, lockDot)
	local lockTag = label(lockFrame, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 7), Size = UDim2.fromOffset(220, 16), TextSize = 12, Text = "" })
	local lockedModel, lockT, nextScan = nil, 0, 0
	local function enemyCands()
		local ch = player.Character
		local out = {}
		for _, m in Lock.Chars() do
			if m ~= ch and isEnemyOf(player, m) then
				local hum = m:FindFirstChildOfClass("Humanoid")
				local body = m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and body then table.insert(out, { Model = m, Body = body }) end
			end
		end
		return out
	end
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t >= nextScan then
			nextScan = t + 1 / 10 -- 2026-11-20 perf: 10 Hz
			local target
			local ls = Lock.Settings[Feed.Id]
			local ch = player.Character
			local head = ch and ch:FindFirstChild("Head")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if ls and head and hum and hum.Health > 0 and not Feed.Active and Feed.ReadyAt <= t and not bif.Open and hud and hud.Gui and hud.Gui.Enabled then
				local e = Lock.Pick(head.Position, Workspace.CurrentCamera.CFrame.LookVector, enemyCands(), ls)
				target = e and e.Model
			end
			if target ~= lockedModel then
				lockedModel, lockT = target, t
				if target then
					lockBB.Adornee = target:FindFirstChild("UpperTorso") or target:FindFirstChild("HumanoidRootPart")
					local col = SIGCOL[Feed.Id] or Color3.new(1, 1, 1)
					for _, b in lockBars do b.BackgroundColor3 = col end
					lockTag.TextColor3 = col
					lockTag.Text = sigName(Feed.Id) .. "  ·  LOCKED"
				end
				lockBB.Enabled = target ~= nil
			end
		end
		if lockedModel then
			local k = math.clamp((t - lockT) / 0.2, 0, 1)
			local e = 1 - (1 - k) ^ 3
			lockFrame.Size = UDim2.fromScale(1.7 - 0.7 * e, 1.7 - 0.7 * e)
			lockFrame.Rotation = 45 * (1 - e)
			for _, b in lockBars do b.BackgroundTransparency = 1 - e end
			lockDot.BackgroundTransparency = 0.15 + 0.45 * (0.5 + 0.5 * math.sin(t * 7))
			lockTag.TextTransparency = 1 - e
			lockTag.TextStrokeTransparency = 0.5 + 0.5 * (1 - e)
		end
	end)

	-- MARKED: a red warning for the player a Signature is coming for
	local markGui = Instance.new("ScreenGui")
	markGui.Name = "VantageSigMarked"; markGui.ResetOnSpawn = false; markGui.IgnoreGuiInset = true; markGui.DisplayOrder = 60; markGui.Enabled = false
	markGui.Parent = pgui
	local edges = {}
	for _, e in { { UDim2.new(1, 0, 0.16, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0.16, 0), UDim2.new(0, 0, 0.84, 0), -90 },
		{ UDim2.new(0.1, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0.1, 0, 1, 0), UDim2.new(0.9, 0, 0, 0), 180 } } do
		local f = Instance.new("Frame"); f.BorderSizePixel = 0; f.BackgroundColor3 = Color3.fromRGB(255, 40, 50); f.Size = e[1]; f.Position = e[2]; f.Parent = markGui
		local g = Instance.new("UIGradient"); g.Rotation = e[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }); g.Parent = f
		table.insert(edges, f)
	end
	local markText = label(markGui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.17, 0), Size = UDim2.fromOffset(600, 34), TextSize = 26,
		TextColor3 = Color3.fromRGB(255, 70, 80), TextStrokeTransparency = 0.2, Text = "" })
	local markSub = label(markGui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.17, 36), Size = UDim2.fromOffset(600, 20), TextSize = 14,
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 210, 210), Text = "" })
	local markToken = 0
	local function showMarked(d)
		markToken += 1
		local my = markToken
		markText.Text = "⚠  MARKED  ⚠"
		markSub.Text = string.upper(tostring(d.By or "AN ENEMY")) .. "'S " .. sigName(d.Id) .. " IS COMING FOR YOU"
		markGui.Enabled = true
		local t0 = os.clock()
		task.spawn(function()
			while my == markToken and os.clock() - t0 < 1.8 do
				local t = os.clock() - t0
				local fade = math.clamp((1.8 - t) / 0.4, 0, 1)
				local pulse = 0.5 + 0.5 * math.sin(t * 16)
				for _, f in edges do f.BackgroundTransparency = 1 - fade * (0.55 + 0.45 * pulse) end
				markText.TextTransparency = 1 - fade
				markSub.TextTransparency = 1 - fade
				markText.Size = UDim2.fromOffset(600, 34 + 6 * math.max(0, 1 - t * 4))
				RunService.Heartbeat:Wait()
			end
			if my == markToken then markGui.Enabled = false end
		end)
	end
	bif.ShowMarked = showMarked

	-- BIFRÖST: a top-down view of the arena; click where the bridge should open
	local function arenaBounds()
		local map = Workspace:FindFirstChild("Map_LiveFire")
		if not map then
			for _, m in Workspace:GetChildren() do
				if m.Name:match("^Map_") and m:FindFirstChild("Gameplay") then map = m break end
			end
		end
		if not map then return nil end
		local mn, mx, found = Vector3.one * 1e9, -Vector3.one * 1e9, false
		-- 1. the boundary walls (every arena has Gameplay.Boundary North/South/East/West)
		local boundary = map:FindFirstChild("Gameplay") and map.Gameplay:FindFirstChild("Boundary")
		if boundary then
			for _, p in boundary:GetChildren() do
				if p:IsA("BasePart") and p.Name ~= "Ceiling" then
					mn = Vector3.new(math.min(mn.X, p.Position.X), mn.Y, math.min(mn.Z, p.Position.Z))
					mx = Vector3.new(math.max(mx.X, p.Position.X), mx.Y, math.max(mx.Z, p.Position.Z))
					found = true
				end
			end
		end
		-- 2. fallback: the extent of the arena's solid, visible geometry
		local parts = {}
		for _, p in map:GetDescendants() do
			if p:IsA("BasePart") and p.CanCollide and p.Transparency < 0.95 and math.max(p.Size.X, p.Size.Z) < 400 then table.insert(parts, p) end
		end
		if not found then
			for _, p in parts do
				mn = Vector3.new(math.min(mn.X, p.Position.X - p.Size.X / 2), mn.Y, math.min(mn.Z, p.Position.Z - p.Size.Z / 2))
				mx = Vector3.new(math.max(mx.X, p.Position.X + p.Size.X / 2), mx.Y, math.max(mx.Z, p.Position.Z + p.Size.Z / 2))
				found = true
			end
		end
		if not found then return nil end
		-- height: floor to the top of what's inside the play area
		local lo, hi = math.huge, -math.huge
		for _, p in parts do
			local q = p.Position
			if q.X > mn.X and q.X < mx.X and q.Z > mn.Z and q.Z < mx.Z then
				lo = math.min(lo, q.Y - p.Size.Y / 2); hi = math.max(hi, q.Y + p.Size.Y / 2)
			end
		end
		if lo == math.huge then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			lo = root and root.Position.Y - 3 or 0
			hi = lo + 60
		end
		return Vector3.new(mn.X, lo, mn.Z), Vector3.new(mx.X, math.min(hi, lo + 220), mx.Z)
	end
	local function spotAt(cam, screen: Vector2, mn: Vector3, mx: Vector3)
		local ray = cam:ViewportPointToRay(screen.X, screen.Y)
		local r = Lock.Ray(ray.Origin, ray.Direction * 4000)
		if not r then return nil, false end
		local p = r.Position
		local ok = r.Normal.Y > 0.55 and p.X > mn.X and p.X < mx.X and p.Z > mn.Z and p.Z < mx.Z
			and Lock.Ray(p + Vector3.new(0, 0.5, 0), Vector3.new(0, 6, 0)) == nil
		return p, ok
	end
	function bif.Close(fireAt: Vector3?)
		if not bif.Open then return end
		bif.Open = false
		RunService:UnbindFromRenderStep("VantageBifrostMap")
		for _, c in bif.Conns or {} do c:Disconnect() end
		bif.Conns = nil
		if bif.Gui then bif.Gui:Destroy(); bif.Gui = nil end
		for _, b in bif.Pins or {} do b:Destroy() end
		bif.Pins = nil
		local cam = Workspace.CurrentCamera
		cam.CameraType = bif.SavedType or Enum.CameraType.Custom
		cam.FieldOfView = bif.SavedFov or 70
		if bif.SavedSubject then cam.CameraSubject = bif.SavedSubject end
		if bif.SavedCF then cam.CFrame = bif.SavedCF end
		UIS.MouseIconEnabled = bif.SavedIcon
		if input then input.Blocked = bif.SavedBlocked end
		if fireAt then Remote:FireServer("Cast", bif.Look, fireAt) end
	end
	function bif.Start()
		local mn, mx = arenaBounds()
		if not mn then
			Feed.Denied = { Text = "NO MAP", At = os.clock() }
			return
		end
		local cam = Workspace.CurrentCamera
		bif.Open = true
		bif.Look = cam.CFrame.LookVector
		bif.SavedType, bif.SavedFov, bif.SavedSubject, bif.SavedCF = cam.CameraType, cam.FieldOfView, cam.CameraSubject, cam.CFrame
		bif.SavedIcon = UIS.MouseIconEnabled
		bif.SavedBlocked = input and input.Blocked or false
		if input then input.Blocked = true end
		local center = (mn + mx) / 2
		local vp = cam.ViewportSize
		local aspect = vp.X / math.max(vp.Y, 1)
		local fov = 50
		local tanH = math.tan(math.rad(fov / 2))
		local h = math.max(((mx.Z - mn.Z) / 2) / tanH, ((mx.X - mn.X) / 2) / (tanH * aspect)) * 1.1
		local camCF = CFrame.lookAt(Vector3.new(center.X, mx.Y + h, center.Z), Vector3.new(center.X, mn.Y, center.Z), Vector3.new(0, 0, -1))

		local gui = Instance.new("ScreenGui")
		gui.Name = "VantageBifrostMap"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.DisplayOrder = 70
		gui.Parent = pgui
		bif.Gui = gui
		-- framing: dark gradient edges + a thin rainbow rule under the title
		for _, e in { { UDim2.new(1, 0, 0.2, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0.2, 0), UDim2.new(0, 0, 0.8, 0), -90 } } do
			local f = Instance.new("Frame"); f.BorderSizePixel = 0; f.BackgroundColor3 = Color3.fromRGB(6, 8, 18); f.Size = e[1]; f.Position = e[2]; f.Parent = gui
			local g = Instance.new("UIGradient"); g.Rotation = e[3]
			g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }); g.Parent = f
		end
		local RAINBOW = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 60)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 110)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 240, 140)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(80, 170, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)) })
		local title = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(600, 46), TextSize = 42, Text = "BIFRÖST",
			TextStrokeTransparency = 0.6 })
		local tg = Instance.new("UIGradient"); tg.Color = RAINBOW; tg.Parent = title
		local rule = Instance.new("Frame"); rule.BorderSizePixel = 0; rule.AnchorPoint = Vector2.new(0.5, 0); rule.Position = UDim2.new(0.5, 0, 0, 84)
		rule.Size = UDim2.fromOffset(300, 2); rule.BackgroundColor3 = Color3.new(1, 1, 1); rule.Parent = gui
		local rg = Instance.new("UIGradient"); rg.Color = RAINBOW
		rg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) })
		rg.Parent = rule
		label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(700, 20), TextSize = 15, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(220, 228, 255), Text = "CHOOSE WHERE THE BRIDGE OPENS  ·  THE LANDING BLASTS EVERY ENEMY NEAR IT" })
		label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(700, 20), TextSize = 15, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(200, 208, 235), Text = "CLICK  open the bridge      ·      RIGHT CLICK / SHIFT  cancel" })
		local btn = Instance.new("TextButton")
		btn.Name = "Pick"; btn.BackgroundTransparency = 1; btn.Text = ""; btn.Size = UDim2.fromScale(1, 1); btn.Modal = true; btn.AutoButtonColor = false; btn.ZIndex = 0
		btn.Parent = gui
		-- the cursor: a rainbow ring that turns red where the bridge can't land
		local ret = Instance.new("Frame"); ret.AnchorPoint = Vector2.new(0.5, 0.5); ret.Size = UDim2.fromOffset(54, 54); ret.BackgroundTransparency = 1; ret.ZIndex = 5; ret.Parent = gui
		corner(ret)
		local rs = Instance.new("UIStroke"); rs.Thickness = 3; rs.Color = Color3.new(1, 1, 1); rs.Parent = ret
		local rsg = Instance.new("UIGradient"); rsg.Color = RAINBOW; rsg.Parent = rs
		local inner = Instance.new("Frame"); inner.AnchorPoint = Vector2.new(0.5, 0.5); inner.Position = UDim2.fromScale(0.5, 0.5); inner.Size = UDim2.fromOffset(8, 8)
		inner.BackgroundColor3 = Color3.new(1, 1, 1); inner.BorderSizePixel = 0; inner.ZIndex = 5; inner.Parent = ret
		corner(inner)
		local retTag = label(ret, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.fromOffset(240, 16), TextSize = 13, ZIndex = 5, Text = "" })
		-- pins: you, your team, enemies
		bif.Pins = {}
		local ch = player.Character
		for _, m in Lock.Chars() do
			local hum = m:FindFirstChildOfClass("Humanoid")
			local root = m:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root then
				local me = m == ch
				local enemy = not me and isEnemyOf(player, m)
				local col = if me then Color3.fromRGB(90, 255, 230) elseif enemy then Color3.fromRGB(255, 70, 80) else Color3.fromRGB(80, 160, 255)
				local bb = Instance.new("BillboardGui"); bb.AlwaysOnTop = true; bb.Size = UDim2.fromOffset(me and 22 or 14, me and 22 or 14); bb.Adornee = root
				bb.LightInfluence = 0; bb.MaxDistance = 100000; bb.Parent = gui
				local d = Instance.new("Frame"); d.Size = UDim2.fromScale(1, 1); d.BackgroundColor3 = col; d.BorderSizePixel = 0; d.Parent = bb
				corner(d)
				local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = Color3.new(1, 1, 1); st.Transparency = 0.2; st.Parent = d
				if me then
					local yb = Instance.new("BillboardGui"); yb.AlwaysOnTop = true; yb.Size = UDim2.fromOffset(60, 16); yb.StudsOffsetWorldSpace = Vector3.new(0, 0, 9)
					yb.Adornee = root; yb.LightInfluence = 0; yb.MaxDistance = 100000; yb.Parent = gui
					label(yb, { Size = UDim2.fromScale(1, 1), TextSize = 12, TextColor3 = col, Text = "YOU" })
				end
				table.insert(bif.Pins, bb)
			end
		end
		local t0 = os.clock()
		local function pickAt(screen: Vector2)
			bif.LastPick = screen
			if os.clock() - t0 < 0.4 then return end
			local p, ok = spotAt(cam, screen, mn, mx)
			if ok and p then
				bif.Close(p)
			else
				retTag.Text = "THE BRIDGE CAN'T LAND THERE"
			end
		end
		bif.PickAt = pickAt
		bif.Conns = {
			btn.MouseButton2Click:Connect(function() bif.Close() end),
			UIS.InputBegan:Connect(function(io)
				if io.KeyCode == Enum.KeyCode.LeftShift or io.KeyCode == Enum.KeyCode.ButtonL1 or io.KeyCode == Enum.KeyCode.ButtonB then
					if os.clock() - t0 > 0.25 then bif.Close() end
				end
			end),
			btn.InputBegan:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.MouseButton1 then
					pickAt(UIS:GetMouseLocation())
				elseif io.UserInputType == Enum.UserInputType.Touch then
					pickAt(Vector2.new(io.Position.X, io.Position.Y) + GuiService:GetGuiInset())
				end
			end),
		}
		RunService:BindToRenderStep("VantageBifrostMap", Enum.RenderPriority.Last.Value, function()
			local t = os.clock() - t0
			local k = math.clamp(t / 0.45, 0, 1)
			local e = 1 - (1 - k) ^ 3
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = bif.SavedCF:Lerp(camCF, e)
			cam.FieldOfView = bif.SavedFov + (fov - bif.SavedFov) * e
			UIS.MouseBehavior = Enum.MouseBehavior.Default
			UIS.MouseIconEnabled = true
			local m = UIS:GetMouseLocation()
			ret.Position = UDim2.fromOffset(m.X, m.Y)
			rsg.Rotation = (t * 120) % 360
			local p, ok = nil, false
			if k >= 1 then p, ok = spotAt(cam, m, mn, mx) end
			rs.Color = if ok then Color3.new(1, 1, 1) else Color3.fromRGB(255, 70, 80)
			rsg.Enabled = ok
			inner.BackgroundColor3 = rs.Color
			ret.Size = UDim2.fromOffset(54 + (ok and math.sin(t * 6) * 4 or 0), 54 + (ok and math.sin(t * 6) * 4 or 0))
			if ok then retTag.Text = "OPEN THE BRIDGE"; retTag.TextColor3 = Color3.new(1, 1, 1)
			elseif p then retTag.TextColor3 = Color3.fromRGB(255, 90, 100); if retTag.Text == "OPEN THE BRIDGE" or retTag.Text == "" then retTag.Text = "CAN'T LAND THERE" end
			else retTag.Text = "" end
			local myHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if t > 15 or not myHum or myHum.Health <= 0 or not (hud and hud.Gui and hud.Gui.Enabled) then bif.Close() end
		end)
	end

	local lastPress = 0
	local function press()
		local t = os.clock()
		if t - lastPress < 0.25 then return end
		lastPress = t
		if bif.Open then bif.Close() return end
		if not canCast() then return end
		if Feed.Active then return end
		if Feed.ReadyAt > t then
			Feed.Denied = { Text = "ON COOLDOWN", At = t }
			return
		end
		local c = Cfg.Sig[Feed.Id]
		if not (c and c.Implemented) then
			Feed.Denied = { Text = "COMING SOON", At = t }
			return
		end
		if Feed.Id == "Bifrost" then bif.Start() return end
		Remote:FireServer("Cast", Workspace.CurrentCamera.CFrame.LookVector.Unit)
	end
	Feed.Press = press
	if STUDIO then
		-- Studio test hooks (set from the command bar / MCP on the LocalPlayer):
		--   DevSigPress = any new value      presses the Signature key
		--   DevBifrostPick = Vector2 (0..1)   clicks that spot of the open Bifröst map (viewport fraction)
		player:GetAttributeChangedSignal("DevSigPress"):Connect(function() lastPress = 0; press() end)
		player:GetAttributeChangedSignal("DevBifrostPick"):Connect(function()
			local v = player:GetAttribute("DevBifrostPick")
			if typeof(v) == "Vector2" and bif.Open and bif.PickAt then
				local vp = Workspace.CurrentCamera.ViewportSize
				bif.PickAt(Vector2.new(v.X * vp.X, v.Y * vp.Y))
			end
		end)
	end
	ContextActionService:BindActionAtPriority("VantageSignature", function(_, state)
		if state == Enum.UserInputState.Begin then
			if input and input.Blocked then return Enum.ContextActionResult.Pass end
			press()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3000, table.unpack(Cfg.Keys))

	Remote.OnClientEvent:Connect(function(kind, d)
		if kind == "Begin" and type(d) == "table" then
			local caster = Players:GetPlayerByUserId(d.Caster)
			local mod = fx(d.Id)
			local mine = caster == player
			if mine then
				local c = Cfg.Sig[d.Id]
				Feed.Cooldown = c and c.Cooldown or Feed.Cooldown
				Feed.ReadyAt = os.clock() + (if devFree() then 0 else Feed.Cooldown)
				Feed.Active = not devFree() or MOVERS[d.Id] == true
			end
			if bif.AddThreat then pcall(bif.AddThreat, d, caster) end
			task.spawn(function()
				local done = function() end
				if caster and mod and mod.Play then
					local a = buildArgs(d, caster)
					if mine and MOVERS[d.Id] then
						a.Move, done = mover()
					end
					local ok, err = pcall(mod.Play, a)
					if not ok then warn("[VANTAGE] Signature FX " .. tostring(d.Id) .. ": " .. tostring(err)) end
				end
				done()
				if mine then Feed.Active = false end
			end)
		elseif kind == "Hit" and type(d) == "table" then
			local mod = fx(d.Id)
			local target = typeof(d.Target) == "Instance" and (d.Target:FindFirstChild("UpperTorso") or d.Target:FindFirstChild("HumanoidRootPart"))
			if mod and mod.HitAt and target and typeof(d.From) == "Vector3" then
				task.spawn(pcall, mod.HitAt, d.From, target, d.Kind)
			end
		elseif kind == "Marked" and type(d) == "table" then
			bif.ShowMarked(d)
		elseif kind == "Threat" and type(d) == "table" then
			if bif.SelfThreat then bif.SelfThreat(d) end
		elseif kind == "Dodged" and type(d) == "table" then
			if bif.ShowDodged then bif.ShowDodged(d) end
		elseif kind == "Denied" and type(d) == "table" then
			Feed.Denied = { Text = tostring(d.Reason or "DENIED"), At = os.clock() }
			if type(d.ReadyIn) == "number" then Feed.ReadyAt = os.clock() + d.ReadyIn end
		elseif kind == "Reset" then
			Feed.ReadyAt, Feed.Active = if type(d) == "number" and d > 0 then os.clock() + d else 0, false
		end
	end)

	-- knockbacks / knock-ups from Signatures (StatusService)
	local StatusRemote = Remotes:WaitForChild("Status", 30)
	if StatusRemote then
		StatusRemote.OnClientEvent:Connect(function(kind, vel)
			if kind ~= "Impulse" or typeof(vel) ~= "Vector3" then return end
			local mc = MovementController and MovementController.Current
			local h = Vector3.new(vel.X, 0, vel.Z)
			if mc then
				if vel.Y > 4 then mc:Launch(vel.Y) end
				if h.Magnitude > 2 then mc:Dash(h.Unit, h.Magnitude, 0.25, h.Magnitude * 0.3) end
			else
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then root.AssemblyLinearVelocity = vel end
			end
		end)
	end
end

return SignatureClient
