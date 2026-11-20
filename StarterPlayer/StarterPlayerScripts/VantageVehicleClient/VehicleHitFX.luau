--[[
	VANTAGE — VehicleHitFX (client)
	Hit confirmation for everything involving vehicles — vehicle weapons hitting anything, and any
	weapon hitting a vehicle (so infantry get it too):
	  - a hitmarker that pops in big and settles, coloured by what you hit:
	      white = infantry · blue = energy shield · amber = hull · red = kill / vehicle destroyed
	  - damage numbers that rise from the impact point and stack while you keep hitting the target
	  - a ring burst + heavier marker on kills, and a TARGET DESTROYED banner for vehicles
	  - the game's own confirm cues (Vanguard Hit / Kill layers), throttled for MG streams
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Vantage.Vehicles.VehicleConfig)
local HM = Config.HitMarker

local HitFX = {}
HitFX.__index = HitFX

local COLORS = {
	Infantry = Color3.fromRGB(245, 248, 255),
	Shield = Color3.fromRGB(80, 185, 255),
	Hull = Color3.fromRGB(255, 186, 64),
	Final = Color3.fromRGB(255, 60, 70),
}
local FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

local function new(class: string, props, parent: Instance?)
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

function HitFX.new()
	local self = setmetatable({}, HitFX)
	local gui = new("ScreenGui", { Name = "VehicleHitFX", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 45 },
		Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	-- hitmarker: four bars around the centre, turned 45 degrees
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Rotation = 45 }, gui)
	self.Marker = holder
	self.Bars = {}
	for i = 0, 3 do
		local a = i * math.pi / 2
		local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * 13, 0.5, math.sin(a) * 13),
			Size = if i % 2 == 0 then UDim2.fromOffset(12, 3) else UDim2.fromOffset(3, 12), BorderSizePixel = 0, BackgroundTransparency = 1 }, holder)
		new("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 1 }, bar)
		self.Bars[i + 1] = { Frame = bar, Horizontal = i % 2 == 0, Angle = a }
	end
	-- kill ring
	self.Ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1 }, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.Ring)
	self.RingStroke = new("UIStroke", { Thickness = 3, Color = COLORS.Final, Transparency = 1 }, self.Ring)
	-- destroyed banner
	self.Banner = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.fromOffset(600, 48),
		BackgroundTransparency = 1, FontFace = FONT, TextSize = 40, Text = "", TextColor3 = COLORS.Final, TextTransparency = 1 }, gui)
	self.BannerStroke = new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(60, 8, 10), Transparency = 1 }, self.Banner)
	self.BannerSub = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.36, 26), Size = UDim2.fromOffset(600, 20),
		BackgroundTransparency = 1, FontFace = FONT, TextSize = 16, Text = "", TextColor3 = Color3.fromRGB(255, 220, 200), TextTransparency = 1 }, gui)
	self.Numbers = {} -- live damage numbers
	self.LastSound = 0
	self.Token = 0
	-- sounds (2D)
	self.Sounds = {}
	local function snd(key, spec)
		local s = new("Sound", { SoundId = spec.Id, Volume = spec.Volume or 0.5, PlaybackSpeed = spec.Speed or 1 }, gui)
		s:SetAttribute("StartAt", spec.StartAt or 0)
		self.Sounds[key] = self.Sounds[key] or {}
		table.insert(self.Sounds[key], s)
	end
	snd("Hit", HM.Hit)
	snd("Shield", HM.Shield)
	snd("Hull", HM.Hit)
	snd("Hull", HM.Hull)
	for _, l in HM.Kill do snd("Kill", l) end
	for _, l in HM.Destroyed do snd("Destroyed", l) end
	RunService.RenderStepped:Connect(function(dt)
		self:_step(dt)
	end)
	return self
end

function HitFX:_play(key: string, jitter: boolean?)
	for _, s in self.Sounds[key] or {} do
		local base = s:GetAttribute("BaseSpeed") or s.PlaybackSpeed
		s:SetAttribute("BaseSpeed", base)
		s.PlaybackSpeed = base * (if jitter then 0.94 + math.random() * 0.12 else 1)
		s.TimePosition = s:GetAttribute("StartAt") or 0
		s:Play()
	end
end

function HitFX:_marker(color: Color3, final: boolean, amount: number)
	self.Token += 1
	local token = self.Token
	local m = self.Marker
	local scale = if final then 1.5 else math.clamp(0.9 + amount / 260, 0.95, 1.35)
	local len, thick = (if final then 15 else 11) * scale, if final then 4 else 3
	m.Rotation = 45 + (if final then 0 else (math.random() - 0.5) * 8)
	for _, b in self.Bars do
		local f = b.Frame
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0
		f.UIStroke.Transparency = 0.4
		f.Size = if b.Horizontal then UDim2.fromOffset(len, thick) else UDim2.fromOffset(thick, len)
		-- pop: start far out, snap in
		local r0, r1 = 26 * scale, 13 * scale
		f.Position = UDim2.new(0.5, math.cos(b.Angle) * r0, 0.5, math.sin(b.Angle) * r0)
		TweenService:Create(f, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, math.cos(b.Angle) * r1, 0.5, math.sin(b.Angle) * r1) }):Play()
	end
	task.delay(if final then 0.42 else 0.16, function()
		if self.Token ~= token then
			return
		end
		for _, b in self.Bars do
			TweenService:Create(b.Frame, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(b.Frame.UIStroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
		end
	end)
	if final then
		self.Ring.Size = UDim2.fromOffset(24, 24)
		self.RingStroke.Transparency = 0
		self.RingStroke.Color = color
		TweenService:Create(self.Ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(110, 110) }):Play()
		TweenService:Create(self.RingStroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end
end

function HitFX:_number(amount: number, color: Color3, pos: Vector3?, final: boolean)
	local now = os.clock()
	-- stack onto a recent number near the same spot
	if pos then
		for _, n in self.Numbers do
			if n.Pos and (n.Pos - pos).Magnitude < 14 and now - n.Last < 0.75 and not n.Final then
				n.Total += amount
				n.Last = now
				n.Born = now
				n.Pos = n.Pos:Lerp(pos, 0.3)
				n.Label.Text = tostring(math.floor(n.Total + 0.5))
				n.Label.TextColor3 = color
				n.Pop = 1
				n.Final = final
				return
			end
		end
	end
	local l = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(120, 30), BackgroundTransparency = 1, FontFace = FONT,
		TextSize = if final then 30 else 22, Text = tostring(math.floor(amount + 0.5)), TextColor3 = color }, self.Gui)
	new("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.3 }, l)
	table.insert(self.Numbers, { Label = l, Pos = pos, Total = amount, Born = now, Last = now, Pop = 1, Final = final, Drift = (math.random() - 0.5) * 30 })
end

function HitFX:_step(dt: number)
	local cam = Workspace.CurrentCamera
	local now = os.clock()
	local vp = cam.ViewportSize
	for i = #self.Numbers, 1, -1 do
		local n = self.Numbers[i]
		local age = now - n.Born
		local life = if n.Final then 1.1 else 0.8
		if age > life then
			n.Label:Destroy()
			table.remove(self.Numbers, i)
			continue
		end
		local x, y
		if n.Pos then
			local sp, on = cam:WorldToViewportPoint(n.Pos)
			if not on then
				n.Label.Visible = false
				continue
			end
			x, y = sp.X, sp.Y
		else
			x, y = vp.X / 2 + 34, vp.Y / 2 - 30
		end
		n.Label.Visible = true
		n.Pop = math.max(0, n.Pop - dt * 9)
		local rise = age * 70
		n.Label.Position = UDim2.fromOffset(x + n.Drift * age, y - 24 - rise)
		n.Label.Size = UDim2.fromOffset(120 * (1 + n.Pop * 0.45), 30 * (1 + n.Pop * 0.45))
		n.Label.TextSize = (if n.Final then 30 else 22) * (1 + n.Pop * 0.45)
		n.Label.TextTransparency = math.clamp((age - life * 0.55) / (life * 0.45), 0, 1)
	end
end

function HitFX:ShowBanner(text: string, sub: string)
	self.Banner.Text = text
	self.BannerSub.Text = sub
	self.Banner.TextTransparency = 0
	self.BannerStroke.Transparency = 0
	self.BannerSub.TextTransparency = 0.1
	self.Banner.TextSize = 54
	TweenService:Create(self.Banner, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 40 }):Play()
	local token = {}
	self._banner = token
	task.delay(1.3, function()
		if self._banner == token then
			TweenService:Create(self.Banner, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			TweenService:Create(self.BannerStroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			TweenService:Create(self.BannerSub, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

-- amount dealt, kind "Infantry" | "Shield" | "Hull", world position (may be nil), final = kill / destroyed
function HitFX:Confirm(amount: number, kind: string, pos: Vector3?, final: boolean)
	local color = if final then COLORS.Final else (COLORS[kind] or COLORS.Infantry)
	self:_marker(color, final, amount)
	self:_number(amount, color, pos, final)
	local now = os.clock()
	if final then
		if kind == "Infantry" then
			self:_play("Kill")
		else
			self:_play("Destroyed")
			self:ShowBanner("TARGET DESTROYED", "VEHICLE ELIMINATED")
		end
		self.LastSound = now
	elseif now - self.LastSound > HM.MinGap then
		self.LastSound = now
		self:_play(if kind == "Shield" then "Shield" elseif kind == "Hull" then "Hull" else "Hit", true)
	end
end

return HitFX
