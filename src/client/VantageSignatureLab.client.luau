--!nonstrict
--[[
	VANTAGE — SIGNATURE LAB (client, dev tool) — 2026-11-19
	A "SIGNATURE LAB" button on the lobby HUD (only while the main menu is open). It opens a panel with
	all 10 Signatures; picking one plays its effect right in the lobby hall in front of your character,
	against two practice targets. Local only: nobody else sees it, nothing is damaged.
	Shown in Studio, and in live servers only to the accounts in ALLOW (the game creator by default).
	Delete this script to remove the button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ALLOW = { [game.CreatorId] = true }
if not RunService:IsStudio() and not (game.CreatorType == Enum.CreatorType.User and ALLOW[player.UserId]) then
	return
end

local Signatures = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Signatures")
local VFX = require(Signatures:WaitForChild("SignatureVFX"))

local LIST = {
	{ "01", "MJÖLNIR", "Mjolnir", Color3.fromRGB(201, 216, 255) },
	{ "02", "FENRIR", "Fenrir", Color3.fromRGB(168, 216, 255) },
	{ "03", "GUNGNIR", "Gungnir", Color3.fromRGB(255, 201, 74) },
	{ "04", "MIDGARD", "Midgard", Color3.fromRGB(46, 230, 200) },
	{ "05", "VALKYRIE", "Valkyrie", Color3.fromRGB(255, 211, 107) },
	{ "06", "RAGNARÖK", "Ragnarok", Color3.fromRGB(255, 122, 26) },
	{ "07", "HELHEIM", "Helheim", Color3.fromRGB(159, 231, 255) },
	{ "08", "SLEIPNIR", "Sleipnir", Color3.fromRGB(230, 238, 247) },
	{ "09", "BIFRÖST", "Bifrost", Color3.fromRGB(255, 74, 42) },
	{ "10", "YGGDRASIL", "Yggdrasil", Color3.fromRGB(47, 224, 122) },
}

------------------------------------------------------------------ practice targets + scene helpers
local function character()
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	return c, root
end

local function rayParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { player.Character, VFX.Folder() }
	return p
end

local function ground(pos: Vector3): Vector3?
	local hit = Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), rayParams())
	return hit and hit.Position
end

local targets = {}
local function clearTargets()
	for _, t in targets do t:Destroy() end
	table.clear(targets)
end

local function makeTarget(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "LabTarget"
	local function part(props)
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.Material = Enum.Material.SmoothPlastic
		for k, v in props do p[k] = v end
		p.Parent = m
		return p
	end
	local body = part({ Name = "Body", Size = Vector3.new(1.8, 3.2, 1.2), Color = Color3.fromRGB(38, 42, 52), CFrame = CFrame.new(pos + Vector3.new(0, 2.9, 0)) })
	part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, Color = Color3.fromRGB(38, 42, 52), CFrame = CFrame.new(pos + Vector3.new(0, 5.1, 0)) })
	part({ Name = "Legs", Size = Vector3.new(1.4, 1.4, 1), Color = Color3.fromRGB(30, 33, 40), CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)) })
	part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 70, 70), Transparency = 0.35,
		Size = Vector3.new(0.05, 4, 4), CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	m.PrimaryPart = body
	m.Parent = VFX.Folder()
	table.insert(targets, m)
	return body
end

-- forward direction on the ground, two targets in the lane, and how far until a wall
local function stage(distA, distB)
	clearTargets()
	local _, root = character()
	if not root then return end
	local fwd = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.new(0, 0, -1)
	local function wallDist(maxD)
		local hit = Workspace:Raycast(root.Position + Vector3.new(0, 1, 0), fwd * maxD, rayParams())
		return hit and (hit.Position - root.Position).Magnitude or nil
	end
	local wall = wallDist(95)
	local list = {}
	for _, d in { distA, distB } do
		if not wall or d < wall - 4 then
			local g = ground(root.Position + fwd * d + root.CFrame.RightVector * (math.random() - 0.5) * 2)
			if g then table.insert(list, makeTarget(g)) end
		end
	end
	return root, fwd, wall, list
end

-- ground-hugging path ahead of the player (stops at walls), like the server will build it
local function groundPath(root, fwd, length, step)
	local pts = {}
	local prev = ground(root.Position + fwd * 3) or (root.Position - Vector3.new(0, 3, 0))
	table.insert(pts, prev)
	local d = 3
	while d < length do
		d += step
		local g = ground(root.Position + fwd * d)
		if not g or math.abs(g.Y - prev.Y) > 6 then break end
		if Workspace:Raycast(prev + Vector3.new(0, 2, 0), (g - prev) + Vector3.zero, rayParams()) then break end
		table.insert(pts, g)
		prev = g
	end
	return pts
end

------------------------------------------------------------------ the effects
local PLAY = {}

PLAY.Mjolnir = function()
	local FX = require(Signatures.FX.Mjolnir)
	local root, fwd, wall, list = stage(22, 38)
	if not root then return end
	local c = player.Character
	local hand = c:FindFirstChild("RightHand") or root
	FX.Play({
		Hand = function() return (hand.Parent and hand or root).CFrame * CFrame.new(0, 0.6, 0) end,
		Dir = fwd + Vector3.new(0, 0.02, 0),
		Range = 90,
		BlockAt = wall and wall - 1.5 or nil,
		Targets = list,
	})
end

PLAY.Fenrir = function()
	local FX = require(Signatures.FX.Fenrir)
	local root, fwd, _, list = stage(24, 40)
	if not root then return end
	local path = groundPath(root, fwd, 70, 4)
	if #path < 3 then return end
	FX.Play({ Origin = root.CFrame, Path = path, Speed = 80, Targets = list })
end

-- the caster's root is anchored and driven by the effect for movement Signatures (the server will do this in game)
local function rider()
	local _, root = character()
	if not root then return nil end
	local was = root.Anchored
	root.Anchored = true
	return function(cf) if root.Parent then root.CFrame = cf end end, function() if root.Parent then root.Anchored = was end end
end

local function groundAhead(root, fwd, d, wall)
	if wall then d = math.min(d, wall - 5) end
	return ground(root.Position + fwd * d) or (root.Position + fwd * d - Vector3.new(0, 3, 0))
end

PLAY.Gungnir = function()
	local FX = require(Signatures.FX.Gungnir)
	local root, fwd, wall, list = stage(22, 38)
	if not root then return end
	local c = player.Character
	local hand = c:FindFirstChild("RightHand") or root
	FX.Play({ Hand = function() return (hand.Parent and hand or root).CFrame * CFrame.new(0, 0.6, 0) end, Dir = fwd + Vector3.new(0, 0.01, 0),
		Range = 110, BlockAt = wall and wall - 1 or nil, Targets = list })
end

PLAY.Midgard = function()
	local FX = require(Signatures.FX.Midgard)
	local root, fwd, wall, list = stage(16, 30)
	if not root then return end
	FX.Play({ Origin = root.CFrame, At = groundAhead(root, fwd, 16, wall), Targets = list })
end

PLAY.Valkyrie = function()
	local FX = require(Signatures.FX.Valkyrie)
	local root, fwd, wall, list = stage(22, 30)
	if not root then return end
	local move, release = rider()
	local ok, err = pcall(FX.Play, { Start = root.CFrame, DiveTo = groundAhead(root, fwd, 24, wall), Move = move, Targets = list })
	release()
	if not ok then error(err) end
end

PLAY.Ragnarok = function()
	local FX = require(Signatures.FX.Ragnarok)
	local root, fwd, wall, list = stage(20, 36)
	if not root then return end
	FX.Play({ Origin = root.CFrame, Length = wall and math.max(12, math.min(56, wall - 12)) or 56, Targets = list })
end

PLAY.Helheim = function()
	local FX = require(Signatures.FX.Helheim)
	local root, _, _, list = stage(14, 26)
	if not root then return end
	FX.Play({ Origin = root.CFrame, Range = 36, Angle = 70, Targets = list })
end

PLAY.Sleipnir = function()
	local FX = require(Signatures.FX.Sleipnir)
	local root, fwd, _, list = stage(20, 36)
	if not root then return end
	local path = groundPath(root, fwd, 85, 4)
	if #path < 3 then return end
	local move, release = rider()
	local ok, err = pcall(FX.Play, { Start = root.CFrame, Path = path, Move = move, Targets = list })
	release()
	if not ok then error(err) end
end

PLAY.Bifrost = function(opts)
	local FX = require(Signatures.FX.Bifrost)
	local Map = require(Signatures.BifrostMap)
	clearTargets()
	local _, root = character()
	if not root then return end
	-- stand still while the map is open (anywhere on the map, 6 s to choose)
	local move, release = rider()
	local to = Map.Pick({ Timeout = 6, Teammates = {}, Auto = opts and opts.Auto })
	if not to then release(); return end
	local ok, err = pcall(FX.Play, { From = root.CFrame, To = to, Move = move })
	release()
	if not ok then error(err) end
end

PLAY.Yggdrasil = function()
	local FX = require(Signatures.FX.Yggdrasil)
	clearTargets()
	local _, root = character()
	if not root then return end
	local fwd = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.new(0, 0, -1)
	FX.Play({ Origin = root.CFrame, At = groundAhead(root, fwd, 16, nil), Allies = { player.Character } })
end

if game:GetService("RunService"):IsStudio() then -- Studio-only test hook (plugin tools run each effect by name)
	local bf = Instance.new("BindableFunction")
	bf.Name = "SigLabTest"
	bf.OnInvoke = function(name, opts)
		local fn = PLAY[name]
		if not fn then return "no " .. tostring(name) end
		local ok, err = pcall(fn, opts)
		clearTargets()
		return ok and "ok" or tostring(err)
	end
	bf.Parent = player:WaitForChild("PlayerGui")
end

------------------------------------------------------------------ UI
local gui = Instance.new("ScreenGui")
gui.Name = "VantageSignatureLab"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 990
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(255, 201, 74)
local INK = Color3.fromRGB(14, 17, 24)
local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p end
local function stroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 1.5; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p end
local function label(parent, text, size, col, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = col or Color3.new(1, 1, 1)
	l.Font = font or Enum.Font.GothamBold; l.TextSize = size; l.Parent = parent
	return l
end

local scale = Instance.new("UIScale")
local function fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	scale.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.55, 1.4)
end
fit()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

-- the lobby button: a dev pill right of the SKIN RANGE pill (top-left), same size and font
local open = Instance.new("TextButton")
open.Name = "LabButton"
open.Position = UDim2.fromOffset(140, 60)
open.Size = UDim2.fromOffset(140, 30)
open.BackgroundColor3 = GOLD
open.AutoButtonColor = true
open.Font = Enum.Font.GothamBold
open.TextSize = 13
open.TextColor3 = INK
open.Text = "SIGNATURE LAB"
open.Parent = gui
corner(open, 8)

-- panel
local panel = Instance.new("Frame")
panel.Name = "SigLabPanel" -- not "Panel": a lobby script toggles every GUI object named Panel
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(640, 400)
panel.BackgroundColor3 = INK
panel.BackgroundTransparency = 0.08
panel.Visible = false
panel.Parent = gui
scale.Parent = panel
corner(panel, 12); stroke(panel, Color3.fromRGB(60, 66, 80), 1.5)
local title = label(panel, "SIGNATURE LAB  ·  test the effects (only you see this)", 16, Color3.fromRGB(200, 205, 215))
title.Position = UDim2.fromOffset(20, 12); title.Size = UDim2.new(1, -40, 0, 22); title.TextXAlignment = Enum.TextXAlignment.Left

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -12, 0, 10)
close.Size = UDim2.fromOffset(28, 28)
close.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
close.Font = Enum.Font.GothamBold; close.TextSize = 14; close.TextColor3 = Color3.new(1, 1, 1); close.Text = "X"
close.Parent = panel
corner(close, 6)
close.Activated:Connect(function() panel.Visible = false end)

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(20, 46)
grid.Size = UDim2.new(1, -40, 0, 290)
grid.Parent = panel
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(112, 136)
layout.CellPadding = UDim2.fromOffset(9, 14)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

local slow = false
local busy = false
local status = label(panel, "", 14, Color3.fromRGB(170, 176, 188), Enum.Font.Gotham)
status.Position = UDim2.new(0, 20, 1, -40); status.Size = UDim2.new(1, -220, 0, 24); status.TextXAlignment = Enum.TextXAlignment.Left

local slowBtn = Instance.new("TextButton")
slowBtn.AnchorPoint = Vector2.new(1, 1)
slowBtn.Position = UDim2.new(1, -20, 1, -14)
slowBtn.Size = UDim2.fromOffset(170, 34)
slowBtn.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
slowBtn.Font = Enum.Font.GothamBold; slowBtn.TextSize = 14; slowBtn.TextColor3 = Color3.new(1, 1, 1)
slowBtn.Text = "SLOW MOTION: OFF"
slowBtn.Parent = panel
corner(slowBtn, 8); stroke(slowBtn, Color3.fromRGB(80, 86, 100), 1)
slowBtn.Activated:Connect(function()
	slow = not slow
	slowBtn.Text = slow and "SLOW MOTION: ON" or "SLOW MOTION: OFF"
	slowBtn.TextColor3 = slow and GOLD or Color3.new(1, 1, 1)
end)

local function run(entry)
	local fn = PLAY[entry[3]]
	if not fn or busy then return end
	busy = true
	panel.Visible = false
	status.Text = ""
	VFX.TimeScale = slow and 0.3 or 1
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then warn("[SignatureLab] " .. entry[3] .. ": " .. tostring(err)) end
		task.wait(1)
		clearTargets()
		VFX.TimeScale = 1
		busy = false
		if not ok then status.Text = "Error — see Output" end
	end)
end

for i, e in LIST do
	local ready = PLAY[e[3]] ~= nil and Signatures.FX:FindFirstChild(e[3]) ~= nil
	local card = Instance.new("TextButton")
	card.LayoutOrder = i
	card.Text = ""
	card.AutoButtonColor = ready
	card.BackgroundColor3 = ready and Color3.fromRGB(28, 32, 42) or Color3.fromRGB(22, 24, 30)
	card.Parent = grid
	corner(card, 10); stroke(card, ready and e[4] or Color3.fromRGB(48, 52, 62), ready and 2 or 1)
	local num = label(card, e[1], 30, ready and e[4] or Color3.fromRGB(70, 74, 86), Enum.Font.GothamBlack)
	num.Position = UDim2.fromOffset(0, 18); num.Size = UDim2.new(1, 0, 0, 36)
	local nm = label(card, e[2], 15, ready and Color3.new(1, 1, 1) or Color3.fromRGB(90, 94, 106))
	nm.Position = UDim2.fromOffset(0, 66); nm.Size = UDim2.new(1, 0, 0, 20)
	local st = label(card, ready and "PLAY" or "SOON", 12, ready and GOLD or Color3.fromRGB(80, 84, 96))
	st.Position = UDim2.fromOffset(0, 100); st.Size = UDim2.new(1, 0, 0, 16)
	if ready then card.Activated:Connect(function() run(e) end) end
end

open.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

-- only while the main menu (lobby HUD) is open
local function refresh()
	local inLobby = player:GetAttribute("VantageMainMenu") == "Open"
	gui.Enabled = inLobby
	if not inLobby then panel.Visible = false end
end
player:GetAttributeChangedSignal("VantageMainMenu"):Connect(refresh)
refresh()
