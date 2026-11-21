--[[
	VANTAGE — CrateUX (client): one interaction system for the crate store and the crate opening (2026-11-16).
	Why it exists: G.press gives every control the same bouncy Back-eased scale and plays a double pop on click
	(press 0.93 → release → snap 0.9 → Back again), with stock Roblox click sounds. This replaces that for the
	crate screens only (other screens still use G.press).

	UX.bind(button, kind, opts) -> ctl
	  kinds    primary   purchase CTAs: lifts brightness on hover, firm press, confirm pulse
	           secondary other CTAs / panel buttons
	           card      selectable products: lift + glow, press settle, selected state
	           tab       navigation: text/fill change only, no scaling
	           toggle    switches: no scale, edge brightens
	           utility   small icon buttons
	  opts     OnClick, Sound (name | false), Pitch, Art (Image* whose ImageColor3 is the tone), Bloom (glow image),
	           Stroke (UIStroke to brighten), OnHover(on, selected), OnPress(down), Cooldown (s)
	  ctl      :SetSelected(on) :SetDisabled(on, quiet) :Shake() :Pulse() .Selected .Disabled
	Timing: hover 0.12 s Quart Out, press 0.05 s Quad Out, release 0.16 s Quart Out. No overshoot anywhere.
	Input: mouse, touch (InputBegan/Ended), gamepad selection. Activated is debounced per button.

	UX.sound(name, pitch, volume): the crate UI sound kit (vantage_vfx/crates/sfx; short, mixed low; hover throttled).
]]
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UX = {}

local function id(n)
	return "rbxassetid://" .. n
end
UX.Sounds = {
	Hover = { id(133432321810855), 0.45 },
	Click = { id(102705143114378), 0.5 },
	Tab = { id(101958858678403), 0.45 },
	Select = { id(122755406072761), 0.55 },
	ToggleOn = { id(104813282067857), 0.5 },
	ToggleOff = { id(104813282067857), 0.45 },
	Purchase = { id(102619312277180), 0.6 },
	Deny = { id(101979595621741), 0.55 },
	Open = { id(136434924728183), 0.5 },
	Tick = { id(89658557478425), 0.3 },
	Lock = { id(131042770615213), 0.55 },
	Shimmer = { id(74567426909562), 0.42 },
}

local lastHover = 0
function UX.sound(name, pitch, vol)
	local spec = UX.Sounds[name]
	if not spec then
		return
	end
	if name == "Hover" then
		local now = os.clock()
		if now - lastHover < 0.06 then
			return
		end
		lastHover = now
	end
	local s = Instance.new("Sound")
	s.SoundId = spec[1]
	s.Volume = spec[2] * (vol or 1)
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end

-- preload so the first hover isn't silent
task.defer(function()
	local list = {}
	for _, spec in UX.Sounds do
		local s = Instance.new("Sound")
		s.SoundId = spec[1]
		table.insert(list, s)
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(list)
	end)
	for _, s in list do
		s:Destroy()
	end
end)

local function tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
UX.tween = tween

local KIND = {
	primary = { Hover = 1.035, Press = 0.955, Idle = 0.9, Bright = 1, Down = 0.74, HoverSound = true, Sound = "Click", Bloom = 0.42 },
	secondary = { Hover = 1.025, Press = 0.96, Idle = 0.86, Bright = 1, Down = 0.74, HoverSound = true, Sound = "Click", Bloom = 0.6 },
	card = { Hover = 1.015, Press = 0.985, Lift = 6, SelLift = 10, HoverSound = true, Sound = "Select" },
	tab = { Hover = 1, Press = 0.97, HoverSound = true, Sound = "Tab" },
	toggle = { Hover = 1, Press = 0.97, Sound = false },
	utility = { Hover = 1.06, Press = 0.92, Sound = "Click" },
}

local function gray(v)
	return Color3.new(v, v, v)
end

function UX.bind(btn, kind, opts)
	opts = opts or {}
	local k = KIND[kind] or KIND.secondary
	local sc = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Parent = btn
	local ctl = { Selected = false, Disabled = false, Quiet = false, Button = btn }
	local hover, down = false, false
	local home = btn.Position
	local art, bloom, stroke = opts.Art, opts.Bloom, opts.Stroke
	local bloomBase = bloom and bloom.ImageTransparency or 1
	local strokeBase = stroke and stroke.Transparency or 0
	local last = 0

	local function scaleTarget()
		if ctl.Disabled then
			return 1
		end
		if down then
			return k.Press
		end
		if hover then
			return k.Hover
		end
		return 1
	end
	local function apply(t, style)
		t = t or 0.12
		tween(sc, t, { Scale = scaleTarget() }, style)
		if art then
			local v = if ctl.Disabled then 0.45 elseif down then k.Down elseif hover or ctl.Selected then k.Bright else k.Idle
			tween(art, t, { ImageColor3 = gray(v or 1) }, style)
		end
		if bloom then
			local v = if ctl.Disabled then 1 elseif hover or ctl.Selected then (k.Bloom or bloomBase) else bloomBase
			tween(bloom, t, { ImageTransparency = v }, style)
		end
		if stroke then
			tween(stroke, t, { Transparency = if (hover or ctl.Selected) and not ctl.Disabled then 0 else strokeBase }, style)
		end
		if k.Lift then
			local lift = if ctl.Selected then k.SelLift elseif hover and not ctl.Disabled then k.Lift else 0
			tween(btn, t + 0.04, { Position = home - UDim2.fromOffset(0, lift) }, style)
		end
		if opts.OnHover then
			opts.OnHover(hover and not ctl.Disabled, ctl.Selected)
		end
	end
	ctl.Apply = apply
	if art then
		art.ImageColor3 = gray(k.Idle or 1)
	end

	btn.MouseEnter:Connect(function()
		if hover then
			return
		end
		hover = true
		if k.HoverSound and not ctl.Disabled and not ctl.Selected then
			UX.sound("Hover", 1 + math.random() * 0.06)
		end
		apply(0.12)
	end)
	btn.MouseLeave:Connect(function()
		hover, down = false, false
		apply(0.16)
	end)
	btn.SelectionGained:Connect(function()
		hover = true
		apply(0.12)
	end)
	btn.SelectionLost:Connect(function()
		hover = false
		apply(0.16)
	end)
	btn.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			down = true
			if t == Enum.UserInputType.Touch then
				hover = true
			end
			apply(0.05, Enum.EasingStyle.Quad)
			if opts.OnPress then
				opts.OnPress(true)
			end
		end
	end)
	btn.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			down = false
			if t == Enum.UserInputType.Touch then
				hover = false
			end
			apply(0.16)
			if opts.OnPress then
				opts.OnPress(false)
			end
		end
	end)
	btn.Activated:Connect(function()
		if ctl.Disabled then
			if not ctl.Quiet then
				UX.sound("Deny")
				ctl:Shake()
			end
			return
		end
		local now = os.clock()
		if now - last < (opts.Cooldown or 0.22) then
			return
		end
		last = now
		local snd = if opts.Sound == nil then k.Sound else opts.Sound
		if snd then
			UX.sound(snd, opts.Pitch)
		end
		if opts.OnClick then
			task.spawn(opts.OnClick)
		end
	end)

	function ctl:SetSelected(on)
		self.Selected = on and true or false
		apply(0.16)
	end
	function ctl:SetDisabled(on, quiet)
		self.Disabled = on and true or false
		self.Quiet = quiet and true or false
		apply(0.12)
	end
	-- a short horizontal shake (denied purchase)
	function ctl:Shake()
		local base = home - UDim2.fromOffset(0, if k.Lift and self.Selected then k.SelLift else 0)
		task.spawn(function()
			for _, dx in { 9, -7, 5, -3, 0 } do
				tween(btn, 0.04, { Position = base + UDim2.fromOffset(dx, 0) }, Enum.EasingStyle.Quad)
				task.wait(0.04)
			end
		end)
	end
	-- confirm pulse (purchase registered): a bright overlay of the art plus a firm settle
	function ctl:Pulse()
		sc.Scale = k.Press
		tween(sc, 0.22, { Scale = scaleTarget() })
		if art and art:IsA("GuiObject") and (art:IsA("ImageButton") or art:IsA("ImageLabel")) then
			local f = Instance.new("ImageLabel")
			f.Name = "Pulse"
			f.BackgroundTransparency = 1
			f.Image = art.Image
			f.ImageTransparency = 0.2
			f.ScaleType = art.ScaleType
			f.Size = UDim2.fromScale(1, 1)
			f.ZIndex = art.ZIndex + 1
			f.Parent = art
			tween(f, 0.32, { ImageTransparency = 1 })
			task.delay(0.34, function()
				f:Destroy()
			end)
		end
	end
	function ctl:SetHome(pos)
		home = pos
		apply(0)
	end
	return ctl
end

return UX
