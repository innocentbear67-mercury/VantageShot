--[[
	VANTAGE — Armory (client): weapon inventory + skin customization, and (ARMOUR tab, child
	module ArmourBay) exo-suit armour mixing
	Opens with B / gamepad R3 (rebindable "Bind_Inventory"), or the LOADOUT page's ARMORY button.
	  left    weapon list (all seven arsenal entries, current skin per weapon)
	  centre  rotating preview of the selected weapon wearing the previewed skin, EQUIP button
	  right   skin cards for that weapon (rarity, finish, equipped badge)
	Equip sends Remotes.SkinEquip; the server validates ownership, saves it (LoadoutService)
	and sets the Skin_<Weapon> attribute, which re-skins the viewmodel, HUD icon and the
	third-person weapon everyone else sees. Cosmetic only.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Weapons = Vantage:WaitForChild("Weapons")
local Skins = require(Weapons:WaitForChild("Skins"))
local Config = require(Weapons:WaitForChild("WeaponConfig"))
local Remotes = Vantage:WaitForChild("Remotes")
local ArmourBay = require(script:WaitForChild("ArmourBay"))

local player = Players.LocalPlayer

local C = Color3.fromRGB
local V2 = Vector2.new
local O = UDim2.fromOffset
local FRAME = C(14, 18, 26)
local PANEL = C(20, 26, 36)
local LINE = C(78, 92, 112)
local CYAN = C(64, 222, 255)
local TEXT = C(232, 240, 248)
local MUTED = C(130, 146, 166)
local AMBER = C(255, 176, 56)
local FONT_HEAD = Font.new("rbxasset://fonts/families/Michroma.json", Enum.FontWeight.Regular)
local FONT_B = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local FONT_MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium)

local W, H = 1000, 580

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
local function label(props, parent)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or FONT
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props, parent)
end
local function accent(f: GuiObject, col: Color3)
	new("Frame", { Size = O(36, 2), BackgroundColor3 = col, BorderSizePixel = 0 }, f)
	new("Frame", { Size = O(2, 12), BackgroundColor3 = col, BorderSizePixel = 0 }, f)
	new("Frame", { AnchorPoint = V2(1, 1), Position = UDim2.fromScale(1, 1), Size = O(12, 2), BackgroundColor3 = col, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, f)
end

local function displayName(id: string): string
	local w = Config.Weapons[id]
	return if w and w.DisplayName then w.DisplayName else string.upper(id)
end

local Armory = {}
Armory.__index = Armory

function Armory.new(input, settingsMenu)
	local self = setmetatable({}, Armory)
	self.Input = input
	self.SettingsMenu = settingsMenu
	self.Open = false
	self.Selected = Skins.Weapons[1]
	self.Preview = nil :: string?
	self.Rows = {}
	self.Cards = {}

	local gui = new("ScreenGui", { Name = "VantageArmory", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 16, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	self.Gui = gui
	new("TextButton", { Name = "ModalUnlock", Modal = true, Size = O(0, 0), BackgroundTransparency = 1, Text = "" }, gui)
	self.Dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(4, 6, 10), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, gui)
	local root = new("Frame", { Name = "Panel", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(W, H), BackgroundColor3 = FRAME, BackgroundTransparency = 0.04, BorderSizePixel = 0 }, gui)
	new("UIStroke", { Color = LINE, Transparency = 0.55, Thickness = 1 }, root)
	accent(root, CYAN)
	self.Scale = new("UIScale", {}, root)
	self.Panel = root
	local function fit()
		local vp = (Workspace.CurrentCamera :: Camera).ViewportSize
		self.Scale.Scale = math.clamp(math.min(vp.X / (W + 60), vp.Y / (H + 60)), 0.5, 1.35)
	end
	fit()
	local cam0 = Workspace.CurrentCamera :: Camera
	cam0:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- header
	label({ Position = O(24, 18), Size = O(400, 30), Text = "ARMORY", FontFace = FONT_HEAD, TextSize = 26 }, root)
	self.Subtitle = label({ Position = O(24, 48), Size = O(500, 14), Text = "WEAPON INVENTORY  //  CUSTOMIZATION  //  COSMETIC ONLY", FontFace = FONT_MONO, TextSize = 11, TextColor3 = MUTED }, root)
	-- tabs: WEAPONS (skins) | ARMOUR (suit pieces)
	self.Tab = "Weapons"
	self.TabButtons = {}
	for i, t in { { Id = "Weapons", Text = "WEAPONS" } } do
		local b = new("TextButton", { Name = "Tab" .. t.Id, Position = O(200 + (i - 1) * 122, 20), Size = O(116, 26), BackgroundColor3 = PANEL, BorderSizePixel = 0, AutoButtonColor = true, Text = t.Text, FontFace = FONT_B, TextSize = 12, TextColor3 = MUTED, Selectable = true }, root)
		local line = new("Frame", { AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = CYAN, BorderSizePixel = 0, Visible = false }, b)
		b.Activated:Connect(function()
			self:SetTab(t.Id)
		end)
		self.TabButtons[t.Id] = { Button = b, Line = line }
	end
	local close = new("TextButton", { Name = "Close", AnchorPoint = V2(1, 0), Position = UDim2.new(1, -20, 0, 20), Size = O(120, 30), BackgroundColor3 = PANEL, BorderSizePixel = 0, AutoButtonColor = true, Text = "[B]  CLOSE", FontFace = FONT_B, TextSize = 12, TextColor3 = TEXT }, root)
	new("UIStroke", { Color = LINE, Transparency = 0.5 }, close)
	close.Activated:Connect(function()
		self:SetOpen(false)
	end)

	-- left: weapon list
	local list = new("ScrollingFrame", { Name = "Weapons", Position = O(20, 78), Size = O(240, H - 118), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = O(0, #Skins.Weapons * 64), ScrollBarImageColor3 = LINE }, root)
	for i, id in Skins.Weapons do
		local row = new("TextButton", { Name = id, Position = O(0, (i - 1) * 64), Size = O(232, 58), BackgroundColor3 = PANEL, BackgroundTransparency = 0.35, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Selectable = true }, list)
		local bar = new("Frame", { Size = O(3, 58), BackgroundColor3 = CYAN, BorderSizePixel = 0, Visible = false }, row)
		label({ Position = O(14, 8), Size = O(210, 18), Text = displayName(id), FontFace = FONT_B, TextSize = 15 }, row)
		local playable = Config.Weapons[id] ~= nil
		label({ Position = O(14, 26), Size = O(210, 12), Text = string.upper(Skins.Category[id]) .. (if playable then "" else "  ·  NOT IN ROTATION"), FontFace = FONT_MONO, TextSize = 10, TextColor3 = MUTED }, row)
		local skinText = label({ Position = O(14, 40), Size = O(210, 12), Text = "", FontFace = FONT_MONO, TextSize = 10, TextColor3 = CYAN }, row)
		row.Activated:Connect(function()
			self:Select(id)
		end)
		self.Rows[id] = { Button = row, Bar = bar, Skin = skinText }
	end

	-- centre: preview
	local pv = new("Frame", { Name = "Preview", Position = O(276, 78), Size = O(430, 330), BackgroundColor3 = C(10, 13, 19), BorderSizePixel = 0 }, root)
	new("UIStroke", { Color = LINE, Transparency = 0.7 }, pv)
	for k = 1, 7 do
		new("Frame", { Position = UDim2.new(0, 0, k / 8, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = LINE, BackgroundTransparency = 0.92, BorderSizePixel = 0 }, pv)
	end
	local vp = new("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = C(150, 160, 175), LightColor = C(255, 255, 255), LightDirection = Vector3.new(-0.4, -1, -0.6) }, pv)
	self.Viewport = vp
	self.PreviewName = label({ Position = O(276, 418), Size = O(430, 30), Text = "", FontFace = FONT_HEAD, TextSize = 22 }, root)
	self.PreviewTag = label({ Position = O(276, 450), Size = O(430, 14), Text = "", FontFace = FONT_MONO, TextSize = 11, TextColor3 = MUTED }, root)
	local equip = new("TextButton", { Name = "Equip", Position = O(276, 478), Size = O(200, 40), BackgroundColor3 = CYAN, BorderSizePixel = 0, AutoButtonColor = true, Text = "EQUIP", FontFace = FONT_B, TextSize = 15, TextColor3 = C(8, 14, 20), Selectable = true }, root)
	equip.Activated:Connect(function()
		self:EquipPreview()
	end)
	self.EquipButton = equip
	self.Status = label({ Position = O(490, 478), Size = O(216, 40), Text = "", FontFace = FONT_MONO, TextSize = 11, TextColor3 = MUTED, TextWrapped = true }, root)

	-- right: skin cards
	self.Grid = new("ScrollingFrame", { Name = "Skins", Position = O(724, 78), Size = O(256, H - 118), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = LINE }, root)
	label({ Position = O(724, 62), Size = O(256, 12), Text = "FINISHES & DESIGNS", FontFace = FONT_MONO, TextSize = 10, TextColor3 = MUTED }, root)

	self.Footer = label({ Position = O(20, H - 30), Size = O(W - 40, 14), Text = "SELECT A WEAPON  ·  PICK A FINISH TO PREVIEW  ·  EQUIP TO APPLY  ·  SAVED TO YOUR PROFILE", FontFace = FONT_MONO, TextSize = 10, TextColor3 = MUTED, ZIndex = 6 }, root)

	-- ARMOUR tab content sits over the weapon content
	self.Bay = ArmourBay.new(root, O(20, 78), Vector2.new(W - 40, H - 118))

	-- live: server confirms / attribute changes
	local result = Remotes:WaitForChild("SkinResult", 10) :: RemoteEvent?
	if result then
		result.OnClientEvent:Connect(function(ok, weaponId, skinId, reason)
			if ok then
				self:_status(string.upper(Skins.Get(weaponId, skinId).Name) .. " EQUIPPED", CYAN)
			else
				self:_status("COULD NOT EQUIP: " .. string.upper(tostring(reason)), AMBER)
			end
		end)
	end
	player.AttributeChanged:Connect(function(name)
		if self.Open and string.sub(name, 1, 5) == "Skin_" then
			self:_refresh()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if self.Open and self.PreviewModel then
			self.Spin = (self.Spin or 0) + dt * 0.5
			self.PreviewModel:PivotTo(CFrame.Angles(0.08, self.Spin, 0) * self.PreviewBase)
		end
	end)
	if RunService:IsStudio() then
		-- Studio test hook: DevArmory = "open" | "close" | "select:<Weapon>" | "preview:<Skin>" | "equip"
		player:GetAttributeChangedSignal("DevArmory"):Connect(function()
			local cmd = tostring(player:GetAttribute("DevArmory") or "")
			local verb, arg = string.match(cmd, "^(%a+):?(.*)$")
			if verb == "open" then
				self:SetOpen(true)
			elseif verb == "close" then
				self:SetOpen(false)
			elseif verb == "select" then
				self:Select(arg)
			elseif verb == "preview" then
				self.Preview = arg
				self:_refresh(true)
			elseif verb == "equip" then
				self:EquipPreview()
			elseif verb == "tab" then
				self:SetTab(arg)
			elseif verb == "slot" then
				self.Bay:SelectSlot(arg)
			elseif verb == "suit" then
				self.Bay.Preview = arg
				self.Bay:Refresh(true)
			elseif verb == "wear" then
				self.Bay:Equip(arg == "full")
			end
		end)
	end
	return self
end

function Armory:SetTab(id: string)
	if id ~= "Weapons" then -- the ARMOUR tab was retired with armour customisation (2026-11-17)
		return
	end
	self.Tab = id
	for tid, t in self.TabButtons do
		local on = tid == id
		t.Line.Visible = on
		t.Button.TextColor3 = if on then TEXT else MUTED
		t.Button.BackgroundTransparency = if on then 0 else 0.5
	end
	local armour = id == "Armour"
	self.Subtitle.Text = if armour then "EXO-SUIT ARMOUR  //  MIX ANY PIECE FROM ANY SUIT  //  COSMETIC ONLY" else "WEAPON INVENTORY  //  CUSTOMIZATION  //  COSMETIC ONLY"
	self.Footer.Text = if armour then "SELECT A SLOT  ·  PICK A SUIT TO PREVIEW  ·  EQUIP TO APPLY  ·  SAVED TO YOUR PROFILE" else "SELECT A WEAPON  ·  PICK A FINISH TO PREVIEW  ·  EQUIP TO APPLY  ·  SAVED TO YOUR PROFILE"
	if self.Open then
		self.Bay:SetVisible(armour)
		if armour then
			self.Viewport:ClearAllChildren()
			self.PreviewModel = nil
		else
			self:Select(self.Selected)
		end
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = if armour then self.Bay:FirstButton() else self.Rows[self.Selected].Button
		end
	end
end

function Armory:_status(text: string, col: Color3?)
	self.Status.Text = text
	self.Status.TextColor3 = col or MUTED
end

function Armory:_buildPreview()
	local vp = self.Viewport
	vp:ClearAllChildren()
	self.PreviewModel = nil
	local asset = Weapons.Assets:FindFirstChild(self.Selected)
	if not asset then
		return
	end
	local m = asset:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	Skins.Apply(m, self.Selected, self.Preview)
	local cf, size = m:GetBoundingBox()
	-- pivot relative to the bounding-box centre: puts the centre at the origin, side-on, and the
	-- RenderStepped spin turns it around its own centre
	self.PreviewBase = CFrame.Angles(0, math.rad(90), 0) * cf:ToObjectSpace(m:GetPivot())
	m:PivotTo(self.PreviewBase)
	m.Parent = vp
	self.PreviewModel = m
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local longest = math.max(size.X, size.Y, size.Z)
	local dist = (longest / 2) / math.tan(math.rad(15)) * 1.05
	cam.CFrame = CFrame.lookAt(Vector3.new(0, longest * 0.12, dist), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

function Armory:_buildCards()
	for _, c in self.Cards do
		c.Button:Destroy()
	end
	self.Cards = {}
	local equipped = Skins.ForPlayer(player, self.Selected)
	local list = Skins.List(self.Selected)
	for i, s in list do
		local cx, cy = (i - 1) % 2, math.floor((i - 1) / 2)
		local rc = Skins.RarityColor[s.Rarity] or MUTED
		local b = new("TextButton", { Name = s.Id, Position = O(cx * 126, cy * 96), Size = O(120, 88), BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Selectable = true }, self.Grid)
		local stroke = new("UIStroke", { Color = LINE, Transparency = 0.6, Thickness = 1 }, b)
		new("Frame", { Position = O(8, 8), Size = O(104, 30), BackgroundColor3 = s.Swatch, BorderSizePixel = 0 }, b)
		if s.Kind == "Texture" then
			label({ Position = O(8, 8), Size = O(104, 30), Text = "DESIGN", FontFace = FONT_MONO, TextSize = 10, TextColor3 = C(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Center }, b)
		end
		new("Frame", { Position = O(0, 0), Size = O(2, 88), BackgroundColor3 = rc, BorderSizePixel = 0 }, b)
		label({ Position = O(8, 44), Size = O(108, 16), Text = s.Name, FontFace = FONT_B, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd }, b)
		label({ Position = O(8, 60), Size = O(108, 12), Text = string.upper(s.Rarity), FontFace = FONT_MONO, TextSize = 10, TextColor3 = rc }, b)
		local badge = label({ Position = O(8, 72), Size = O(108, 12), Text = if s.Id == equipped then "● EQUIPPED" else "", FontFace = FONT_MONO, TextSize = 9, TextColor3 = CYAN }, b)
		b.Activated:Connect(function()
			self.Preview = s.Id
			self:_refresh(true)
		end)
		self.Cards[s.Id] = { Button = b, Stroke = stroke, Badge = badge }
	end
	self.Grid.CanvasSize = O(0, math.ceil(#list / 2) * 96)
end

function Armory:_refresh(previewChanged: boolean?)
	local equipped = Skins.ForPlayer(player, self.Selected)
	for id, r in self.Rows do
		local sel = id == self.Selected
		r.Bar.Visible = sel
		r.Button.BackgroundTransparency = if sel then 0.05 else 0.4
		local s = Skins.Get(id, Skins.ForPlayer(player, id))
		r.Skin.Text = string.upper(s.Name)
		r.Skin.TextColor3 = Skins.RarityColor[s.Rarity] or CYAN
	end
	for id, c in self.Cards do
		local sel = id == self.Preview
		c.Stroke.Color = if sel then CYAN else LINE
		c.Stroke.Transparency = if sel then 0 else 0.6
		c.Stroke.Thickness = if sel then 2 else 1
		c.Badge.Text = if id == equipped then "● EQUIPPED" else ""
	end
	local s = Skins.Get(self.Selected, self.Preview)
	self.PreviewName.Text = string.upper(s.Name)
	local kind = if s.Kind == "Texture" then "DESIGN" elseif s.Kind == "Factory" then "ORIGINAL FINISH" else "MATERIAL FINISH"
	self.PreviewTag.Text = string.upper(s.Rarity) .. "  //  " .. kind .. "  //  " .. displayName(self.Selected)
	self.PreviewTag.TextColor3 = Skins.RarityColor[s.Rarity] or MUTED
	local isEquipped = s.Id == equipped
	self.EquipButton.Text = if isEquipped then "EQUIPPED" else "EQUIP"
	self.EquipButton.BackgroundColor3 = if isEquipped then PANEL else CYAN
	self.EquipButton.TextColor3 = if isEquipped then MUTED else C(8, 14, 20)
	if previewChanged then
		self:_buildPreview()
	end
end

function Armory:Select(id: string)
	self.Selected = id
	self.Preview = Skins.ForPlayer(player, id)
	self:_buildCards()
	self:_refresh(true)
end

function Armory:EquipPreview()
	local s = Skins.Get(self.Selected, self.Preview)
	if s.Id == Skins.ForPlayer(player, self.Selected) then
		return
	end
	self:_status("EQUIPPING…")
	Remotes.SkinEquip:FireServer(self.Selected, s.Id)
end

local function mainMenuOpen(): boolean
	local g = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("VantageMainMenu")
	return g ~= nil and (g :: ScreenGui).Enabled
end

function Armory:SetOpen(open: boolean)
	if self.Open == open then
		return
	end
	self.Open = open
	if open then
		if self.SettingsMenu and self.SettingsMenu.Open then
			self.SettingsMenu:SetOpen(false)
		end
		self.Input:SetBlocked(true)
		self._prevIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
		self.Gui.Enabled = true
		self.Scale.Scale = self.Scale.Scale * 0.97
		TweenService:Create(self.Scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = self.Scale.Scale / 0.97 }):Play()
		self:_status("")
		self:SetTab(self.Tab)
		ContextActionService:BindActionAtPriority("VantageArmoryClose", function(_, state)
			if state == Enum.UserInputState.Begin then
				self:SetOpen(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("VantageArmoryClose")
		self.Bay:SetVisible(false)
		self.Gui.Enabled = false
		self.Viewport:ClearAllChildren()
		self.PreviewModel = nil
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Gui) then
			GuiService.SelectedObject = nil
		end
		if self._prevIcon ~= nil then
			UserInputService.MouseIconEnabled = self._prevIcon
		end
		if not (self.SettingsMenu and self.SettingsMenu.Open) and not mainMenuOpen() then
			self.Input:SetBlocked(false)
		end
	end
end

function Armory:Toggle()
	self:SetOpen(not self.Open)
end

return Armory
