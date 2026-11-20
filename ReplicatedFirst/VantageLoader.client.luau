--[[
	VANTAGE — Loader (ReplicatedFirst)
	2026-11-09: the "EXPERIMENT LOG 0417" intro cinematic was removed at the owner's request
	(backup: ServerStorage._LoaderBackup.VantageLoader_Cinematic). What remains is the loading
	pipeline itself and a plain branded screen: real asset preload with progress, profile sync,
	other screens held hidden until hand-off, then a quick fade straight into the main menu.
	VantageLoaded attribute marks the hand-off (ambience + menu music start on it).
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local MAX_TIME = 30
local SYNC_TIMEOUT = 6

local VOID = Color3.fromHex("#050709")
local STEEL = Color3.fromHex("#303C46")
local SLATE = Color3.fromHex("#697986")
local OFFWHITE = Color3.fromHex("#E5E9EC")
local CYAN = Color3.fromHex("#58BBD4")
local TITLE = "rbxasset://fonts/families/TitilliumWeb.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

local function new(cls: string, props, parent: Instance?)
	local i = Instance.new(cls)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- ─── screen (other ScreenGuis are held hidden until hand-off) ───────────────
local gui = new("ScreenGui", { Name = "VantageLoader", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100 }, player:WaitForChild("PlayerGui"))
local held: { [ScreenGui]: boolean } = {}
local holdConns = {}
local holding = true
local function holdGui(g: Instance)
	if not g:IsA("ScreenGui") or g == gui or held[g] ~= nil then
		return
	end
	held[g] = g.Enabled
	g.Enabled = false
	table.insert(holdConns, g:GetPropertyChangedSignal("Enabled"):Connect(function()
		if holding and g.Enabled then
			held[g] = true
			g.Enabled = false
		end
	end))
end
local function releaseGuis()
	holding = false
	for _, c in holdConns do
		c:Disconnect()
	end
	for g, wanted in held do
		if g.Parent then
			g.Enabled = wanted
		end
	end
end
for _, g in gui.Parent:GetChildren() do
	holdGui(g)
end
table.insert(holdConns, gui.Parent.ChildAdded:Connect(holdGui))

local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = VOID, BorderSizePixel = 0 }, gui)
local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 140), BackgroundTransparency = 1 }, bg)
new("UIScale", { Scale = 1 }, box)
local word = new("TextLabel", { Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Text = "VANTAGESHOT", FontFace = Font.new(TITLE, Enum.FontWeight.Bold), TextSize = 64, TextColor3 = OFFWHITE }, box)
local track = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(320, 2), BackgroundColor3 = STEEL, BorderSizePixel = 0 }, box)
local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, track)
local label = new("TextLabel", { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "LOADING  0%", FontFace = Font.new(MONO, Enum.FontWeight.Regular), TextSize = 13, TextColor3 = SLATE }, box)

local frac = 0
local function setProgress(f: number)
	f = math.clamp(f, frac, 1)
	if f - frac < 0.004 and f < 1 then
		return
	end
	frac = f
	label.Text = string.format("%s  %d%%", if f >= 1 then "READY" else "LOADING", math.floor(f * 100))
	TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(f, 1) }):Play()
end

-- ─── loading pipeline ──────────────────────────────────────────────────────
local t0 = os.clock()
setProgress(0.02)
if not game:IsLoaded() then
	game.Loaded:Wait()
end
setProgress(0.15)
local list, seen, typedHolders = {}, {}, {}
local function scanTable(t, depth)
	if depth > 6 then
		return
	end
	for k, v in t do
		if type(v) == "string" and string.find(v, "^rbxassetid://%d+") and not seen[v] then
			seen[v] = true
			local key = string.lower(tostring(k))
			local isImage = string.find(key, "icon") or string.find(key, "image") or string.find(key, "texture") or string.find(key, "decal")
			local holder = if isImage then Instance.new("ImageLabel") else Instance.new("Sound")
			if isImage then
				(holder :: ImageLabel).Image = v
			else
				(holder :: Sound).SoundId = v
			end
			table.insert(typedHolders, holder)
			table.insert(list, holder)
		elseif type(v) == "table" then
			scanTable(v, depth + 1)
		end
	end
end
local vantage = ReplicatedStorage:WaitForChild("Vantage", 20)
if vantage then
	local weapons = vantage:WaitForChild("Weapons", 10)
	for _, path in { { "Weapons", "WeaponConfig" }, { "Abilities", "AbilityConfig" } } do
		local folder = vantage:FindFirstChild(path[1])
		local mod = folder and folder:WaitForChild(path[2], 10)
		if mod then
			local ok, cfg = pcall(require, mod)
			if ok and type(cfg) == "table" then
				scanTable(cfg, 0)
			end
		end
	end
	if weapons then
		for _, name in { "Assets", "SkinAssets" } do
			local f = weapons:FindFirstChild(name)
			if f then
				table.insert(list, f)
			end
		end
	end
	for _, d in vantage:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("Sound") or d:IsA("ImageLabel") or d:IsA("ImageButton") then
			table.insert(list, d)
		end
	end
end
-- the menu music loads with everything else so it starts the instant the menu appears
local musicId = vantage and vantage:FindFirstChild("UI") and vantage.UI:GetAttribute("MenuMusicId")
for _, id in { "rbxassetid://9114315137", "rbxassetid://9114592245", "rbxassetid://9125980435", "rbxassetid://9112839511", musicId } do
	if type(id) == "string" and id ~= "" and not seen[id] then
		seen[id] = true
		local snd = Instance.new("Sound")
		snd.SoundId = id
		table.insert(typedHolders, snd)
		table.insert(list, snd)
	end
end
local items = {}
for _, it in list do
	if typeof(it) == "Instance" and it:IsA("Folder") then
		for _, c in it:GetChildren() do
			table.insert(items, c)
		end
	else
		table.insert(items, it)
	end
end
local total = math.max(1, #items)
local done, failed = 0, 0
for _, it in items do
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ it })
		end)
		if not ok then
			failed += 1
		end
		done += 1
		setProgress(0.15 + 0.7 * (done / total))
	end)
end
while done < total and os.clock() - t0 < MAX_TIME do
	task.wait(0.1)
end
if failed > 0 then
	warn("[VANTAGE] Loader: " .. failed .. " preload item(s) failed (continuing)")
end
setProgress(0.85)
do
	local deadline = os.clock() + SYNC_TIMEOUT
	while player:GetAttribute("Skin_Vanguard") == nil and os.clock() < deadline and os.clock() - t0 < MAX_TIME do
		task.wait(0.1)
	end
end
setProgress(1)
player:SetAttribute("VantageLoadStats", string.format("assets=%d loaded=%d t=%.1fs", total, done, os.clock() - t0))
task.wait(0.25)

-- ─── hand-off: straight into the main menu ─────────────────────────────────
player:SetAttribute("VantageLoaded", true)
releaseGuis()
local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad)
TweenService:Create(bg, info, { BackgroundTransparency = 1 }):Play()
for _, l in { word, label } do
	TweenService:Create(l, info, { TextTransparency = 1 }):Play()
end
for _, f in { track, fill } do
	TweenService:Create(f, info, { BackgroundTransparency = 1 }):Play()
end
task.wait(0.5)
for _, h in typedHolders do
	h:Destroy()
end
gui:Destroy()
