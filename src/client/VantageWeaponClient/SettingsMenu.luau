--[[
	VANTAGE — SettingsMenu (client UI)
	Centre panel (~62% x 66% of the screen), dark translucent, thin cyan borders. Categories on
	the left, rows built from SettingsConfig.Schema. Opens with the Settings key (default P) or
	the touch button; a Modal button frees the first-person mouse lock while it is open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SettingsConfig = require(ReplicatedStorage.Vantage.SettingsConfig)

local C = Color3.fromRGB
local FONT = Enum.Font.GothamMedium
local FONT_B = Enum.Font.GothamBold
local FONT_H = Enum.Font.GothamBlack
local ACCENT = C(60, 170, 255)
local PANEL = C(9, 13, 21)
local ROW = C(16, 22, 34)
local TEXT = C(232, 238, 248)
local DIM = C(130, 145, 168)

local KEY_LABELS = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	MouseButton2 = "Right mouse", MouseButton3 = "Middle mouse", LeftShift = "Left Shift", RightShift = "Right Shift",
	LeftAlt = "Left Alt", CapsLock = "Caps Lock",
}

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 4) }, p)
end
local function stroke(p, color, t, tr)
	return new("UIStroke", { Color = color, Thickness = t or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local SettingsMenu = {}
SettingsMenu.__index = SettingsMenu

function SettingsMenu.new(settings, input)
	local self = setmetatable({}, SettingsMenu)
	self.Settings = settings
	self.Input = input
	self.Open = false
	self.Rows = {}
	self.RowConns = {}
	local gui = new("ScreenGui", {
		Name = "VantageSettings",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Scale = new("UIScale", {}, gui)
	local dim = new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(2, 4, 8), BackgroundTransparency = 0.5, BorderSizePixel = 0 }, gui)
	self.Dim = dim
	-- frees the first-person mouse lock while the menu is visible
	new("TextButton", { Name = "ModalUnlock", Modal = true, Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Text = "" }, gui)

	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.66),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	}, gui)
	corner(panel, 6)
	stroke(panel, ACCENT, 1, 0.55)
	new("UISizeConstraint", { MinSize = Vector2.new(640, 430), MaxSize = Vector2.new(1080, 700) }, panel)
	self.PanelScale = new("UIScale", {}, panel)
	self.Panel = panel
	new("Frame", { Name = "TopAccent", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, panel)

	-- header
	new("TextLabel", {
		Name = "Title", Position = UDim2.fromOffset(26, 16), Size = UDim2.fromOffset(300, 30), BackgroundTransparency = 1,
		Font = FONT_H, Text = "SETTINGS", TextColor3 = TEXT, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	new("TextLabel", {
		Name = "Sub", Position = UDim2.fromOffset(28, 46), Size = UDim2.fromOffset(300, 16), BackgroundTransparency = 1,
		Font = FONT_B, Text = "VANTAGE  //  PLAYER PREFERENCES", TextColor3 = ACCENT, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	local close = new("TextButton", {
		Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = ROW, Text = "X", Font = FONT_B, TextSize = 16, TextColor3 = TEXT, AutoButtonColor = true,
	}, panel)
	corner(close, 4)
	stroke(close, ACCENT, 1, 0.75)
	close.Activated:Connect(function()
		self:SetOpen(false)
	end)

	-- category nav
	local nav = new("Frame", { Name = "Nav", Position = UDim2.fromOffset(16, 78), Size = UDim2.new(0, 170, 1, -140), BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, nav)
	self.NavButtons = {}
	for i, cat in SettingsConfig.Categories do
		local b = new("TextButton", {
			Name = cat, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = ROW, BackgroundTransparency = 0.2,
			Text = "   " .. string.upper(cat), Font = FONT_B, TextSize = 14, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false,
		}, nav)
		corner(b, 4)
		local bar = new("Frame", { Name = "Bar", Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = ACCENT, BorderSizePixel = 0, Visible = false }, b)
		b.Activated:Connect(function()
			self:ShowCategory(cat)
		end)
		self.NavButtons[cat] = { Button = b, Bar = bar }
	end

	-- content
	local content = new("ScrollingFrame", {
		Name = "Content", Position = UDim2.fromOffset(202, 78), Size = UDim2.new(1, -220, 1, -140), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = ACCENT, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	new("UIPadding", { PaddingRight = UDim.new(0, 10) }, content)
	self.Content = content

	-- footer
	local reset = new("TextButton", {
		Name = "Reset", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(200, 38),
		BackgroundColor3 = ROW, Text = "RESET TO DEFAULTS", Font = FONT_B, TextSize = 13, TextColor3 = TEXT,
	}, panel)
	corner(reset, 4)
	stroke(reset, C(255, 120, 120), 1, 0.6)
	reset.Activated:Connect(function()
		self.Settings:ResetToDefaults()
	end)
	local done = new("TextButton", {
		Name = "Done", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(150, 38),
		BackgroundColor3 = ACCENT, Text = "CLOSE", Font = FONT_B, TextSize = 14, TextColor3 = C(6, 10, 18),
	}, panel)
	corner(done, 4)
	done.Activated:Connect(function()
		self:SetOpen(false)
	end)
	self.StatusLabel = new("TextLabel", {
		Name = "Status", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -180, 1, -24), Size = UDim2.fromOffset(330, 22),
		BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	}, panel)

	settings.Changed:Connect(function(key)
		if key == "*" then
			self:_refreshAll()
		elseif key == "_status" then
			self:_status()
		else
			local r = self.Rows[key]
			if r then
				r.Refresh()
			end
			self:_status()
		end
	end)
	self:ShowCategory(SettingsConfig.Categories[1])
	self:_fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_fit()
	end)
	-- Studio-only test hook: LocalPlayer attribute DevMenuTab selects a category (same path as the nav buttons)
	if game:GetService("RunService"):IsStudio() then
		local lp = game:GetService("Players").LocalPlayer
		lp:GetAttributeChangedSignal("DevMenuTab"):Connect(function()
			local cat = lp:GetAttribute("DevMenuTab")
			if type(cat) == "string" and self.NavButtons[cat] then
				self:ShowCategory(cat)
			end
		end)
	end
	return self
end

function SettingsMenu:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	self.Scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.62, 1.2)
end

function SettingsMenu:_status()
	local s = self.Settings.Status
	local map = {
		Saved = "Saved to your profile",
		Saving = "Saving...",
		Unsaved = "Changes pending...",
		SaveFailed = "Saving failed - settings kept for this session",
		LoadFailed = "Could not load saved settings - using defaults",
		Loaded = "Loaded from your profile",
		Offline = "Settings service unavailable",
		Default = "Default settings",
	}
	self.StatusLabel.Text = map[s] or ""
	self.StatusLabel.TextColor3 = if s == "SaveFailed" or s == "LoadFailed" then C(255, 130, 120) else DIM
end

function SettingsMenu:_refreshAll()
	for _, r in self.Rows do
		r.Refresh()
	end
	self:_status()
end

local function keyLabel(name: string?): string
	if not name then
		return "-"
	end
	return KEY_LABELS[name] or name
end

function SettingsMenu:_row(order: number, height: number?)
	local f = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, height or 50), BackgroundColor3 = ROW, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, self.Content)
	corner(f, 4)
	return f
end

function SettingsMenu:_label(f, row)
	f.Name = row.Key -- stable names (automation / debugging)
	new("TextLabel", {
		Position = UDim2.fromOffset(16, if row.Hint then 7 else 0), Size = UDim2.new(0.5, 0, 0, if row.Hint then 22 else 50), BackgroundTransparency = 1,
		Font = FONT_B, Text = row.Label, TextColor3 = TEXT, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
	}, f)
	if row.Hint then
		new("TextLabel", {
			Position = UDim2.fromOffset(16, 28), Size = UDim2.new(0.55, 0, 0, 16), BackgroundTransparency = 1,
			Font = FONT, Text = row.Hint, TextColor3 = DIM, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		}, f)
	end
end

function SettingsMenu:_bool(row, order)
	local f = self:_row(order)
	self:_label(f, row)
	local track = new("TextButton", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(50, 24),
		BackgroundColor3 = C(40, 48, 62), Text = "", AutoButtonColor = false,
	}, f)
	corner(track, 12)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C(240, 244, 250), BorderSizePixel = 0 }, track)
	corner(knob, 9)
	local function refresh()
		local on = self.Settings:Get(row.Key) == true
		TweenService:Create(knob, TweenInfo.new(0.12), { Position = if on then UDim2.new(1, -21, 0.5, 0) else UDim2.new(0, 3, 0.5, 0) }):Play()
		TweenService:Create(track, TweenInfo.new(0.12), { BackgroundColor3 = if on then ACCENT else C(40, 48, 62) }):Play()
	end
	track.Activated:Connect(function()
		self.Settings:Set(row.Key, not self.Settings:Get(row.Key))
	end)
	refresh()
	self.Rows[row.Key] = { Refresh = refresh }
end

function SettingsMenu:_number(row, order)
	local f = self:_row(order)
	self:_label(f, row)
	local track = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.new(0.38, 0, 0, 6),
		BackgroundColor3 = C(40, 48, 62), BorderSizePixel = 0, Active = true,
	}, f)
	corner(track, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, track)
	corner(fill, 3)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C(240, 244, 250), BorderSizePixel = 0 }, track)
	corner(knob, 8)
	local box = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(66, 28),
		BackgroundColor3 = C(8, 12, 20), Font = FONT_B, TextSize = 14, TextColor3 = TEXT, Text = "", ClearTextOnFocus = false,
	}, f)
	corner(box, 4)
	stroke(box, ACCENT, 1, 0.7)
	local function fmt(v)
		if row.Percent then
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		elseif (row.Step or 1) >= 1 then
			return string.format("%d", v)
		end
		return string.format("%.2f", v)
	end
	local function refresh()
		local v = self.Settings:Get(row.Key)
		local a = (v - row.Min) / (row.Max - row.Min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		if not box:IsFocused() then
			box.Text = fmt(v)
		end
	end
	local dragging = false
	local function setFromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		self.Settings:Set(row.Key, row.Min + a * (row.Max - row.Min))
	end
	track.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(io.Position.X)
		end
	end)
	table.insert(self.RowConns, UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			setFromX(io.Position.X)
		end
	end))
	table.insert(self.RowConns, UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	box.FocusLost:Connect(function()
		local n = tonumber((string.gsub(box.Text, "%%", "")))
		if n then
			if row.Percent then
				n /= 100
			end
			self.Settings:Set(row.Key, n)
		end
		box.Text = fmt(self.Settings:Get(row.Key))
	end)
	refresh()
	self.Rows[row.Key] = { Refresh = refresh }
end

function SettingsMenu:_key(row, order)
	local f = self:_row(order)
	self:_label(f, row)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(150, 30),
		BackgroundColor3 = C(8, 12, 20), Font = FONT_B, TextSize = 14, TextColor3 = TEXT, Text = "",
	}, f)
	corner(b, 4)
	local st = stroke(b, ACCENT, 1, 0.6)
	local function refresh()
		b.Text = keyLabel(self.Settings:Get(row.Key))
		st.Color = ACCENT
	end
	b.Activated:Connect(function()
		if self.Capturing then
			return
		end
		self.Capturing = true
		b.Text = "PRESS A KEY..."
		local conn
		conn = UserInputService.InputBegan:Connect(function(io)
			local name
			if io.UserInputType == Enum.UserInputType.Keyboard then
				name = io.KeyCode.Name
			elseif io.UserInputType == Enum.UserInputType.MouseButton2 or io.UserInputType == Enum.UserInputType.MouseButton3 then
				name = io.UserInputType.Name
			else
				return
			end
			conn:Disconnect()
			task.defer(function()
				self.Capturing = false
			end)
			if name == "Escape" then
				refresh()
				return
			end
			if not self.Settings:Set(row.Key, name) then
				b.Text = "IN USE / RESERVED"
				st.Color = C(255, 110, 110)
				task.delay(0.9, refresh)
			end
		end)
	end)
	refresh()
	self.Rows[row.Key] = { Refresh = refresh }
end

function SettingsMenu:ShowCategory(cat: string)
	self.Category = cat
	for name, nb in self.NavButtons do
		local on = name == cat
		nb.Bar.Visible = on
		nb.Button.TextColor3 = if on then TEXT else DIM
		nb.Button.BackgroundTransparency = if on then 0 else 0.2
	end
	for _, c in self.RowConns or {} do
		c:Disconnect()
	end
	self.RowConns = {}
	for _, ch in self.Content:GetChildren() do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	self.Rows = {}
	local order = 0
	for _, row in SettingsConfig.Schema do
		if row.Category == cat then
			order += 1
			if row.Type == "Bool" then
				self:_bool(row, order)
			elseif row.Type == "Number" then
				self:_number(row, order)
			elseif row.Type == "Key" then
				self:_key(row, order)
			end
		end
	end
	if cat == "Controls" then
		order += 1
		local h = new("TextLabel", {
			LayoutOrder = order, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Font = FONT_B,
			Text = "FIXED BINDINGS (MOVEMENT SYSTEM)", TextColor3 = ACCENT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		}, self.Content)
		local holder = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y }, self.Content)
		h.Parent = holder
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
		for i, fb in SettingsConfig.FixedBinds do
			local r = new("Frame", { LayoutOrder = i + 1, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = ROW, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, holder)
			corner(r, 4)
			new("TextLabel", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Font = FONT, Text = fb[1], TextColor3 = DIM, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }, r)
			new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), BackgroundTransparency = 1, Font = FONT_B, Text = fb[2], TextColor3 = DIM, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right }, r)
		end
	end
	self:_status()
end

function SettingsMenu:SetOpen(open: boolean)
	if self.Open == open then
		return
	end
	self.Open = open
	self.Input:SetBlocked(open)
	if open then
		self.Gui.Enabled = true
		self.PanelScale.Scale = 0.96
		self.Dim.BackgroundTransparency = 1
		TweenService:Create(self.PanelScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		TweenService:Create(self.Dim, TweenInfo.new(0.14), { BackgroundTransparency = 0.5 }):Play()
		self._prevMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
		self:_refreshAll()
	else
		self.Capturing = false
		self.Gui.Enabled = false
		if self._prevMouseIcon ~= nil then
			UserInputService.MouseIconEnabled = self._prevMouseIcon
		end
	end
end

function SettingsMenu:Toggle()
	self:SetOpen(not self.Open)
end

return SettingsMenu
