--[[
	VANTAGE — LobbySkin (client, 2026-11-15)
	Re-skins the older menu screens (Legionary / Customise, Store / Shop, matchmaking) to the
	Roblox-native lobby look without rewriting them:
	  • fonts -> BuilderSans (same weights), the hair-space "tracking" stripped from text
	  • the old top bar (Mark / Word / Tabs / Player) hidden; a lobby header added instead:
	    BACK TO LOBBY + the screen's title beside Roblox's buttons, level badge + REQ top right
	  • keyboard hint rows shown only to keyboard players
	LobbySkin.apply(gui, { Title, OnBack, Canvas?, Hints? })
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent:WaitForChild("LobbyKit"))
local Assets = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("UI"):WaitForChild("LobbyAssets"))
local K, F = Kit.C, Kit.F
local new, text = Kit.new, Kit.text
local O, S, V2 = UDim2.fromOffset, UDim2.fromScale, Vector2.new

local player = Players.LocalPlayer
local HAIR = utf8.char(0x200A)
local THIN = utf8.char(0x2009)

local Skin = {}

local function keyboardUser(): boolean
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch or last.Name:match("^Gamepad") then
		return false
	end
	return UserInputService.KeyboardEnabled
end

local function strip(s: string): string
	if s:find(HAIR, 1, true) or s:find(THIN, 1, true) then
		s = s:gsub(HAIR, ""):gsub(THIN, "")
	end
	return s
end

-- one text object: BuilderSans at the same weight, tracking removed (and kept removed)
function Skin.text(t: TextLabel | TextButton | TextBox)
	local ff = t.FontFace
	if ff and not ff.Family:find("BuilderSans") and not ff.Family:find("Mono") then
		t.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", ff.Weight, ff.Style)
	end
	local s = strip(t.Text)
	if s ~= t.Text then
		t.Text = s
	end
	if not t:GetAttribute("Skinned") then
		t:SetAttribute("Skinned", true)
		t:GetPropertyChangedSignal("Text"):Connect(function()
			local v = strip(t.Text)
			if v ~= t.Text then
				t.Text = v
			end
		end)
	end
end

function Skin.fonts(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			Skin.text(d)
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			task.defer(Skin.text, d)
		end
	end)
end

function Skin.apply(gui: ScreenGui, opts)
	opts = opts or {}
	local canvas = opts.Canvas or gui:FindFirstChild("Canvas")
	Skin.fonts(gui)
	-- the old top bar steps aside
	if canvas then
		for _, n in { "Mark", "Word", "Tabs", "Player" } do
			local c = canvas:FindFirstChild(n)
			if c and c:IsA("GuiObject") then
				c.Visible = false
			end
		end
	end
	-- the lobby header
	local hdr = new("Frame", { Name = "LobbyHeader", Size = S(1, 1), BackgroundTransparency = 1, ZIndex = 50 }, gui)
	local left = new("Frame", { Name = "Left", Size = O(620, 56), BackgroundTransparency = 1 }, hdr)
	local ls = new("UIScale", {}, left)
	local back = new("TextButton", { Size = O(196, 56), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, left)
	local slab = new("ImageLabel", { Size = S(1, 1), BackgroundTransparency = 1, Image = Assets.UI.Slab.Image, ScaleType = Enum.ScaleType.Slice, SliceCenter = Assets.UI.Slab.Slice, SliceScale = 0.45 }, back)
	local bi = Kit.icon(back, "Back", 18, K.White, { Position = O(20, 19) })
	local bl = text(back, { Position = O(48, 0), Size = O(140, 56), Text = "LOBBY", FontFace = F.Heavy, TextSize = 21 })
	local key = new("ImageLabel", { AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = O(52, 26), BackgroundTransparency = 1, Image = Assets.Keys.backspace, ScaleType = Enum.ScaleType.Fit }, back)
	back.MouseEnter:Connect(function()
		slab.Image = Assets.UI.SlabWhite.Image
		bl.TextColor3 = K.Ink
		Kit.recolor(bi, K.Ink)
		key.ImageColor3 = Color3.fromRGB(70, 74, 82)
	end)
	back.MouseLeave:Connect(function()
		slab.Image = Assets.UI.Slab.Image
		bl.TextColor3 = K.Text
		Kit.recolor(bi, K.White)
		key.ImageColor3 = Color3.new(1, 1, 1)
	end)
	back.Activated:Connect(function()
		if opts.OnBack then
			opts.OnBack()
		end
	end)
	text(left, { Position = O(216, 0), Size = O(400, 56), Text = opts.Title or "", FontFace = F.Heavy, TextSize = 34 })
	-- top right: level badge + REQ
	local right = new("Frame", { Name = "Right", AnchorPoint = V2(1, 0), Size = O(380, 56), BackgroundTransparency = 1 }, hdr)
	local rs = new("UIScale", {}, right)
	local lv = new("Frame", { Size = O(170, 56), BackgroundTransparency = 1 }, right)
	new("ImageLabel", { Size = S(1, 1), BackgroundTransparency = 1, Image = Assets.UI.Slab.Image, ScaleType = Enum.ScaleType.Slice, SliceCenter = Assets.UI.Slab.Slice, SliceScale = 0.4 }, lv)
	local badge = new("ImageLabel", { Position = O(10, 6), Size = O(44, 44), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit }, lv)
	local lvt = text(lv, { Position = O(62, 0), Size = O(100, 56), Text = "LV. 1", FontFace = F.Heavy, TextSize = 22 })
	local req = new("Frame", { Position = O(180, 0), Size = O(200, 56), BackgroundTransparency = 1 }, right)
	new("ImageLabel", { Size = S(1, 1), BackgroundTransparency = 1, Image = Assets.UI.Slab.Image, ScaleType = Enum.ScaleType.Slice, SliceCenter = Assets.UI.Slab.Slice, SliceScale = 0.4 }, req)
	Kit.icon(req, "Req", 24, K.Lime, { Position = O(16, 16) })
	local reqT = text(req, { Position = O(52, 0), Size = O(100, 56), Text = "0", FontFace = F.Heavy, TextSize = 22 })
	text(req, { AnchorPoint = V2(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = O(40, 56), Text = "REQ", FontFace = F.Bold, TextSize = 13, TextColor3 = K.Muted, TextXAlignment = Enum.TextXAlignment.Right })
	local function refresh()
		local level = player:GetAttribute("Level") or 1
		badge.Image = Assets.RankFor(level)
		lvt.Text = "LV. " .. level
		reqT.Text = Kit.abbrev(player:GetAttribute("REQ") or 0)
	end
	refresh()
	player:GetAttributeChangedSignal("Level"):Connect(refresh)
	player:GetAttributeChangedSignal("REQ"):Connect(refresh)
	-- hints only for keyboard players
	local hints = opts.Hints or (canvas and canvas:FindFirstChild("Hints"))
	local function hintVis()
		local kb = keyboardUser()
		if hints then
			hints.Visible = kb
		end
		key.Visible = kb
	end
	hintVis()
	UserInputService.LastInputTypeChanged:Connect(hintVis)
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		if vp.X < 50 then
			return
		end
		local s = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.45, 1.6)
		ls.Scale, rs.Scale = s, s
		local inset = GuiService.TopbarInset
		local rowH = math.max(inset.Max.Y, 44)
		local y = math.max(4, (rowH - 56 * s) / 2) + 2
		left.Position = UDim2.new(0, inset.Min.X + 6, 0, y)
		right.Position = UDim2.new(1, -16, 0, y)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)
	return hdr
end

return Skin
