--[[
	VisorHoneycomb — the helmet shell's honeycomb as individually lit cells.

	Every hex on the shell is its own ImageLabel (positions from VisorHexGrid, 1920x1080 design px,
	scaled to the screen). One update loop at ~30 Hz computes each cell's light:

	    light = reveal * level * intensity * (base glow + shimmer + drifting light band) + sum(waves)

	and writes a cell only when its value or colour actually changed. Colour is a slowly drifting
	green <-> teal <-> blue (per-cell offset, so the shell never looks flat); waves blend their own colour in.

	Waves (speeds in design px/s, widths in px, angles in degrees, life in s):
	  hc:Radial{Origin = Vector2, Speed, Width, Color, Strength, Life}      expanding ring of light
	  hc:Directional{Angle, Spread, Color, Strength, Life}                   one side of the shell flares
	  hc:Perimeter{From, Speed, Width, Color, Strength, Life}                light running around the shell
	  hc:Spark(color?)                                                       one cell lights and spreads
	  hc:Boot(origin?) / hc:Shutdown(origin?) / hc:SetOn(bool)               progressive reveal / collapse
	Controls: hc.Params.{Intensity, Speed, HueCenter, HueRange, HueSpeed, Saturation, Shimmer, Combat, BandAngle}
]]
local RunService = game:GetService("RunService")

local Honeycomb = {}
Honeycomb.__index = Honeycomb

local exp, sin, cos, rad, clamp = math.exp, math.sin, math.cos, math.rad, math.clamp
local DESIGN_H = 1080
local STEP = 1 / 30

function Honeycomb.new(parent: Instance, grid, sprite: { Image: string, Size: number, Rotation: number? }, z: number?)
	local self = setmetatable({}, Honeycomb)
	self.Frame = Instance.new("Frame")
	self.Frame.Name = "Honeycomb"
	self.Frame.BackgroundTransparency = 1
	self.Frame.Size = UDim2.fromScale(1, 1)
	self.Frame.ZIndex = z or 3
	self.Sprite = sprite
	self.Cells = {}
	self.Waves = {}
	self.Level = 1
	self.RevealFront = math.huge -- design px from RevealOrigin; cells beyond it are dark
	self.RevealOrigin = Vector2.new(960, 0)
	self.RevealSpeed = 0
	self.Params = {
		Intensity = 1, -- overall brightness
		Speed = 1, -- animation speed multiplier
		HueCenter = 0.48, -- 0.40 green .. 0.48 teal .. 0.58 blue
		HueRange = 0.075,
		HueSpeed = 0.07,
		Saturation = 0.72,
		Shimmer = 1,
		Combat = 0, -- 0..1: brighter, faster
		BandAngle = 35, -- direction the slow light band travels (deg)
	}
	for i, c in grid do
		local x, y, d, a = c[1], c[2], c[3], c[4]
		local im = Instance.new("ImageLabel")
		im.Name = "Hex"
		im.BackgroundTransparency = 1
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromScale(x / 1920, y / 1080)
		im.Image = sprite.Image
		im.Rotation = sprite.Rotation or 0
		im.ImageTransparency = 1
		im.ZIndex = z or 3
		im.Parent = self.Frame
		local ar = rad(a)
		-- light falls off away from the glass; the shell catches more light upper-left / right
		local lit = 0.55 + 0.45 * cos(ar + rad(40)) ^ 2
		local fall = 0.3 + 0.7 * exp(-d / 110)
		self.Cells[i] = {
			Image = im,
			P = Vector2.new(x, y),
			X = x,
			Y = y,
			D = d,
			A = a,
			Base = lit * fall,
			Phase = (i * 2.399) % (math.pi * 2), -- golden-angle scatter
			Rate = 0.6 + ((i * 7) % 13) / 13 * 0.9,
			Out = -1,
			Hue = -1,
		}
	end
	self.Frame.Parent = parent
	local cam = workspace.CurrentCamera
	self:Resize(if cam then cam.ViewportSize.Y else DESIGN_H)
	self.T = 0
	self.Acc = 0
	self.Conn = RunService.Heartbeat:Connect(function(dt)
		self.Acc += dt
		if self.Acc < STEP then
			return
		end
		local step = math.min(self.Acc, 0.1)
		self.Acc = 0
		self.T += step * self.Params.Speed
		if self.RevealSpeed ~= 0 then
			self.RevealFront += self.RevealSpeed * step
		end
		local gui = self.Frame:FindFirstAncestorWhichIsA("ScreenGui")
		if self.Frame.Visible and (not gui or gui.Enabled) then
			self:Update(os.clock())
		end
	end)
	return self
end

function Honeycomb:Resize(viewportY: number)
	local s = self.Sprite.Size * viewportY / DESIGN_H
	for _, c in self.Cells do
		c.Image.Size = UDim2.fromOffset(s, s)
	end
end

function Honeycomb:SetSprite(sprite)
	self.Sprite = sprite
	for _, c in self.Cells do
		c.Image.Image = sprite.Image
		c.Image.Rotation = sprite.Rotation or 0
	end
	local cam = workspace.CurrentCamera
	self:Resize(if cam then cam.ViewportSize.Y else DESIGN_H)
end

-- waves ------------------------------------------------------------------------------------
local function add(self, w)
	w.T0 = os.clock()
	w.Strength = w.Strength or 0.8
	w.Life = w.Life or 1.2
	w.Age = 0
	w.Env = 1
	table.insert(self.Waves, w)
	if #self.Waves > 24 then
		table.remove(self.Waves, 1)
	end
	return w
end
function Honeycomb:Radial(o)
	o.Kind = "Radial"
	o.Origin = o.Origin or Vector2.new(960, 540)
	o.Speed = o.Speed or 900
	o.Width = o.Width or 70
	o.Front = 0
	return add(self, o)
end
function Honeycomb:Directional(o)
	o.Kind = "Dir"
	o.Spread = o.Spread or 4 -- cosine power (higher = narrower)
	return add(self, o)
end
function Honeycomb:Perimeter(o)
	o.Kind = "Perim"
	o.From = o.From or -90
	o.Speed = o.Speed or 240
	o.Width = o.Width or 14
	o.FrontA = o.From
	return add(self, o)
end
function Honeycomb:Spark(color: Color3?, strength: number?)
	local c = self.Cells[math.random(1, #self.Cells)]
	if not c then
		return
	end
	return self:Radial({ Origin = c.P, Speed = 160 + math.random() * 120, Width = 26, Color = color, Strength = strength or 0.55, Life = 0.9 + math.random() * 0.5 })
end
function Honeycomb:Boot(origin: Vector2?)
	self.RevealOrigin = origin or Vector2.new(960, 0)
	self.RevealFront = -60
	self.RevealSpeed = 1500
	self.Level = 1
	self:Radial({ Origin = self.RevealOrigin, Speed = 1500, Width = 90, Color = Color3.fromRGB(225, 250, 255), Strength = 1.1, Life = 1.4 })
end
function Honeycomb:Shutdown(origin: Vector2?)
	self.RevealOrigin = origin or Vector2.new(960, 0)
	self.RevealFront = 2300
	self.RevealSpeed = -3400
	-- the last light runs back up toward the brow as the cells go dark behind it
	self:Perimeter({ From = 90, Speed = -420, Width = 22, Strength = 0.7, Life = 0.6 })
	self:Perimeter({ From = 90, Speed = 420, Width = 22, Strength = 0.7, Life = 0.6 })
end
function Honeycomb:SetOn(on: boolean)
	self.RevealSpeed = 0
	self.RevealFront = if on then math.huge else -1e4
end

-- the update ------------------------------------------------------------------------------
local function hsv(h: number, s: number, v: number): Color3
	return Color3.fromHSV(h % 1, s, v)
end

function Honeycomb:Update(now: number)
	local P = self.Params
	local t = self.T
	local combat = P.Combat
	local waves = self.Waves
	for i = #waves, 1, -1 do
		local w = waves[i]
		w.Age = now - w.T0
		if w.Age >= w.Life then
			table.remove(waves, i)
		else
			local k = w.Age / w.Life
			w.Env = (1 - k) * (1 - k)
			if w.Kind == "Radial" then
				w.Front = w.Speed * w.Age
			elseif w.Kind == "Perim" then
				w.FrontA = w.From + w.Speed * w.Age
			end
		end
	end
	local base0 = (0.26 + 0.14 * combat) * P.Intensity * self.Level
	local shimAmp = (0.22 + 0.22 * combat) * P.Shimmer * P.Intensity
	local shimSpeed = 1 + 1.4 * combat
	local ba = rad(P.BandAngle)
	local bx, by = cos(ba), sin(ba)
	local bandPos = ((t * 160) % 3400) - 700
	local hueT = t * P.HueSpeed
	local front, ro = self.RevealFront, self.RevealOrigin
	for _, c in self.Cells do
		local reveal = 1
		if front < 1e6 then
			reveal = clamp((front - (c.P - ro).Magnitude) / 140, 0, 1)
		end
		local hue = (P.HueCenter + P.HueRange * sin(hueT + c.X * 0.0021 - c.Y * 0.0013 + c.Phase * 0.25)) % 1
		local v, r, g, b, wsum = 0, 0, 0, 0, 0
		if reveal > 0 then
			local sh = 0.5 + 0.5 * sin(t * c.Rate * 1.9 * shimSpeed + c.Phase)
			sh = sh * sh * sh * sh -- mostly quiet, an occasional glint
			local band = exp(-((c.X * bx + c.Y * by - bandPos) / 260) ^ 2) * 0.35
			v = base0 * c.Base * (1 + band) + shimAmp * sh * c.Base
			for _, w in waves do
				local k = 0
				if w.Kind == "Radial" then
					local x = ((c.P - w.Origin).Magnitude - w.Front) / w.Width
					if x > -3 and x < 3 then
						k = exp(-x * x)
					end
				elseif w.Kind == "Dir" then
					local cc = cos(rad(c.A - w.Angle))
					if cc > 0 then
						k = cc ^ w.Spread * (0.75 + 0.25 * sin(w.Age * 38 + c.Phase))
					end
				elseif w.Kind == "Perim" then
					local da = (c.A - w.FrontA + 540) % 360 - 180
					k = exp(-(da / w.Width) ^ 2)
				end
				if k > 0.002 then
					k *= w.Strength * w.Env
					v += k
					wsum += k
					local col = w.Color or hsv(hue, P.Saturation * 0.4, 1)
					r += col.R * k
					g += col.G * k
					b += col.B * k
				end
			end
			v *= reveal
		end
		local out = math.floor(clamp(v, 0, 0.97) * 120 + 0.5) / 120
		if out ~= c.Out then
			c.Out = out
			c.Image.ImageTransparency = 1 - out
		end
		if out > 0 then
			local mix = if wsum > 0 then clamp(wsum / (wsum + base0 * c.Base + 0.05), 0, 1) else 0
			local key = math.floor(hue * 400 + 0.5) + math.floor(mix * 24 + 0.5) * 1000
			if key ~= c.Hue or wsum > 0 then
				c.Hue = key
				local col = hsv(hue, P.Saturation, 1)
				if wsum > 0 then
					col = col:Lerp(Color3.new(r / wsum, g / wsum, b / wsum), mix)
				end
				c.Image.ImageColor3 = col
			end
		end
	end
end

function Honeycomb:Destroy()
	if self.Conn then
		self.Conn:Disconnect()
	end
	self.Frame:Destroy()
end

return Honeycomb
