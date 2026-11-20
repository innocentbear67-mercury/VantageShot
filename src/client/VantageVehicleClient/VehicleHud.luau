--[[
	VANTAGE — VehicleHud (client)
	Shown only while seated. Lower centre: vehicle name, hull integrity, speed, weapon state
	(reload / heat). Right: crew list with seat keys. Centre: the camera reticle (where you look)
	and the barrel reticle (where the gun actually points — the round goes there, not to the
	camera). Hit markers and a red hull-hit flash. Lime-on-dark like the rest of the visor HUD.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Vehicles.VehicleConfig)

local H = {}
H.__index = H

local LIME = Color3.fromRGB(150, 245, 40)
local WHITE = Color3.fromRGB(236, 242, 250)
local DIM = Color3.fromRGB(140, 150, 165)
local PANEL = Color3.fromRGB(8, 12, 20)
local RED = Color3.fromRGB(255, 70, 80)
local AMBER = Color3.fromRGB(255, 190, 70)
local SHIELD = Color3.fromRGB(80, 185, 255)
local FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.SemiBold)
local FONT_B = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

local function new(class: string, props, parent: Instance?)
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	local l = new("TextLabel", props, parent)
	new("UIStroke", { Thickness = 1, Transparency = 0.55, Color = Color3.new(0, 0, 0) }, l)
	return l
end

local function bar(parent, pos: UDim2, size: UDim2, color: Color3)
	local back = new("Frame", { Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(30, 36, 48), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, parent)
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	return back, fill
end

function H.new()
	local self = setmetatable({}, H)
	local gui = new("ScreenGui", { Name = "VehicleHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Enabled = false },
		Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui

	-- lower centre panel
	local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.fromOffset(460, 110),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, panel)
	new("UIStroke", { Color = LIME, Transparency = 0.6, Thickness = 1 }, panel)
	new("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = LIME, BorderSizePixel = 0 }, panel)
	self.Name = label({ Position = UDim2.fromOffset(16, 6), Size = UDim2.fromOffset(260, 22), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, FontFace = FONT_B, TextColor3 = LIME }, panel)
	self.Seat = label({ Position = UDim2.fromOffset(16, 26), Size = UDim2.fromOffset(260, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = DIM }, panel)
	self.Speed = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 4), Size = UDim2.fromOffset(140, 34), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 30, FontFace = FONT_B }, panel)
	label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 34), Size = UDim2.fromOffset(140, 12), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11, TextColor3 = DIM, Text = "SPEED  ST/S" }, panel)
	label({ Position = UDim2.fromOffset(16, 48), Size = UDim2.fromOffset(60, 14), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = DIM, Text = "SHIELD" }, panel)
	self.ShieldBack, self.ShieldFill = bar(panel, UDim2.fromOffset(60, 52), UDim2.fromOffset(250, 7), SHIELD)
	self.ShieldText = label({ Position = UDim2.fromOffset(316, 46), Size = UDim2.fromOffset(80, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = SHIELD }, panel)
	label({ Position = UDim2.fromOffset(16, 66), Size = UDim2.fromOffset(60, 14), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = DIM, Text = "HULL" }, panel)
	self.HullBack, self.HullFill = bar(panel, UDim2.fromOffset(60, 70), UDim2.fromOffset(250, 7), LIME)
	self.HullText = label({ Position = UDim2.fromOffset(316, 64), Size = UDim2.fromOffset(60, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13 }, panel)
	self.Weapon = label({ Position = UDim2.fromOffset(16, 86), Size = UDim2.fromOffset(150, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = DIM }, panel)
	self.WeapBack, self.WeapFill = bar(panel, UDim2.fromOffset(150, 91), UDim2.fromOffset(160, 5), LIME)
	self.WeapText = label({ Position = UDim2.fromOffset(316, 84), Size = UDim2.fromOffset(130, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13 }, panel)

	-- crew list (right)
	local crew = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -26), Size = UDim2.fromOffset(220, 160), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, crew)
	self.Crew = crew
	self.CrewRows = {}

	-- key hints
	self.Hints = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -142), Size = UDim2.fromOffset(600, 16), TextSize = 13, TextColor3 = DIM }, gui)

	-- reticles
	self.CamDot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.CamDot)
	local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1 }, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	self.RingStroke = new("UIStroke", { Color = LIME, Thickness = 2, Transparency = 0.1 }, ring)
	for i = 0, 3 do
		local a = i * math.pi / 2
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * 24, 0.5, math.sin(a) * 24),
			Size = if i % 2 == 0 then UDim2.fromOffset(9, 2) else UDim2.fromOffset(2, 9), BackgroundColor3 = LIME, BorderSizePixel = 0 }, ring)
	end
	self.Ring = ring

	-- homing lock marker (drone): a red diamond on the target the guns will steer onto
	local lock = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1, Rotation = 45, Visible = false }, gui)
	new("UIStroke", { Color = RED, Thickness = 2 }, lock)
	label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(80, 14), Rotation = -45, TextSize = 12, TextColor3 = RED, Text = "LOCK" }, lock)
	self.Lock = lock

	-- hit marker
	local hm = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, Rotation = 45 }, gui)
	for i = 0, 3 do
		local a = i * math.pi / 2
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * 11, 0.5, math.sin(a) * 11),
			Size = if i % 2 == 0 then UDim2.fromOffset(8, 2) else UDim2.fromOffset(2, 8), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hm)
	end
	hm.Visible = false
	self.HitMarker = hm

	-- hull hit flash
	self.Flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0 }, gui)
	return self
end

function H:Show(on: boolean)
	self.Gui.Enabled = on
end

function H:SetCrew(model: Model, mySeat: number?)
	local seats = model:FindFirstChild("Seats")
	if not seats then
		return
	end
	local list = {}
	for _, s in seats:GetChildren() do
		if s:IsA("Seat") then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		return a:GetAttribute("SeatIndex") < b:GetAttribute("SeatIndex")
	end)
	for i, s in list do
		local row = self.CrewRows[i]
		if not row then
			row = label({ Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14, LayoutOrder = i }, self.Crew)
			self.CrewRows[i] = row
		end
		local occ = s.Occupant and Players:GetPlayerFromCharacter(s.Occupant.Parent)
		local mine = i == mySeat
		row.Text = ("[%d]  %s   %s"):format(i, string.upper(s:GetAttribute("SeatName") or "SEAT"), if occ then occ.DisplayName else "—")
		row.TextColor3 = if mine then LIME elseif occ then WHITE else DIM
	end
	for i = #list + 1, #self.CrewRows do
		self.CrewRows[i]:Destroy()
		self.CrewRows[i] = nil
	end
end

function H:Update(info)
	local m = info.Model
	local cfg = Config.Vehicles[m:GetAttribute("VehicleType")]
	self.Name.Text = cfg.DisplayName
	self.Seat.Text = string.upper(info.SeatName or "") .. (if info.Controls then "  ·  WEAPON CONTROL" else "")
	self.Speed.Text = ("%d"):format(math.floor(math.abs(info.Speed) + 0.5))
	local hp, max = m:GetAttribute("Health") or 0, m:GetAttribute("MaxHealth") or 1
	local f = math.clamp(hp / max, 0, 1)
	self.HullFill.Size = UDim2.fromScale(f, 1)
	self.HullFill.BackgroundColor3 = if f < 0.25 then RED elseif f < 0.5 then AMBER else LIME
	self.HullText.Text = ("%d%%"):format(math.ceil(f * 100))
	local sh, shMax = m:GetAttribute("Shield") or 0, m:GetAttribute("MaxShield") or 1
	local sf = math.clamp(sh / math.max(1, shMax), 0, 1)
	self.ShieldFill.Size = UDim2.fromScale(sf, 1)
	self.ShieldText.Text = if sf <= 0 then "DOWN" else ("%d%%"):format(math.ceil(sf * 100))
	self.ShieldText.TextColor3 = if sf <= 0 then RED else SHIELD
	local W = cfg.Weapon
	self.Weapon.Text = W.DisplayName
	if W.Kind == "Cannon" then
		local left = (m:GetAttribute("ReadyAt") or 0) - Workspace:GetServerTimeNow()
		local r = 1 - math.clamp(left / W.Reload, 0, 1)
		self.WeapFill.Size = UDim2.fromScale(r, 1)
		self.WeapFill.BackgroundColor3 = if r >= 1 then LIME else AMBER
		self.WeapText.Text = if r >= 1 then "READY" else ("RELOADING %.1f"):format(math.max(0, left))
		self.WeapText.TextColor3 = if r >= 1 then LIME else AMBER
	else
		local heat = m:GetAttribute("Heat") or 0
		local over = m:GetAttribute("Overheated") == true
		self.WeapFill.Size = UDim2.fromScale(heat, 1)
		self.WeapFill.BackgroundColor3 = if over then RED elseif heat > 0.7 then AMBER else LIME
		self.WeapText.Text = if over then "OVERHEATED" else ("HEAT %d%%"):format(math.floor(heat * 100))
		self.WeapText.TextColor3 = if over then RED else WHITE
	end
	local hints = { "[X] EXIT", "[1-" .. #info.SeatList .. "] SEAT", "[RMB] ZOOM" }
	if info.Driver then
		if cfg.Drive.Kind == "Flight" then
			table.insert(hints, 1, "[MOUSE] STEER")
			table.insert(hints, 2, "[W/S] THRUST")
			table.insert(hints, 3, "[A/D] STRAFE")
		else
			table.insert(hints, 1, "[WASD] DRIVE")
			if cfg.Drive.Kind == "Wheels" then
				table.insert(hints, 2, "[SPACE] HANDBRAKE")
			end
		end
	end
	if info.Controls then
		table.insert(hints, "[LMB] FIRE")
	end
	self.Hints.Text = table.concat(hints, "     ")
	-- barrel reticle
	self.Ring.Visible = info.Controls and info.BarrelScreen ~= nil
	if info.BarrelScreen then
		self.Ring.Position = UDim2.fromOffset(info.BarrelScreen.X, info.BarrelScreen.Y)
		self.RingStroke.Color = if info.Aligned then LIME else AMBER
	end
	self.CamDot.Visible = info.Controls
	self.Lock.Visible = info.LockScreen ~= nil
	if info.LockScreen then
		self.Lock.Position = UDim2.fromOffset(info.LockScreen.X, info.LockScreen.Y)
	end
end

function H:Hit(killed: boolean, vehicle: boolean)
	local hm = self.HitMarker
	hm.Visible = true
	for _, c in hm:GetChildren() do
		if c:IsA("Frame") then
			c.BackgroundColor3 = if killed then RED elseif vehicle then AMBER else WHITE
		end
	end
	hm.Size = UDim2.fromOffset(if killed then 40 else 30, if killed then 40 else 30)
	local token = {}
	self._hitToken = token
	task.delay(if killed then 0.35 else 0.15, function()
		if self._hitToken == token then
			hm.Visible = false
		end
	end)
end

function H:HullHit(amount: number, shielded: boolean?)
	self.Flash.BackgroundColor3 = if shielded then SHIELD else RED
	self.Flash.BackgroundTransparency = math.clamp(1 - amount / 400, if shielded then 0.82 else 0.7, 0.94)
	TweenService:Create(self.Flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

return H
