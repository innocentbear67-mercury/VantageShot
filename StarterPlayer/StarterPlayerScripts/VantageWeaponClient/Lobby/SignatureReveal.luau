--!nocheck
--[[
	SignatureReveal (2026-11-20): the unlock moment for the Ichor Crate and Daily Shop buys.
	Own ScreenGui (DisplayOrder 65) above the lobby and the Shop.
	Crate path:  the crate charges (shake that builds, light leaks, sparks, ticking riser) -> white flash + hit ->
	             the Signature card bursts in (art, 3D model, tier glow, spinning rays, embers) -> EQUIP / DONE.
	Direct buy:  straight to the card burst.
	Click anywhere during the charge to skip to the reveal.
	R.Background: burst backdrop (placeholder: the gold crate-opening burst until the user's art is uploaded).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Cat = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureCatalog"))
local Remotes = Vantage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local V2, V3, O, S = Vector2.new, Vector3.new, UDim2.fromOffset, UDim2.fromScale
local RGB, WHITE = Color3.fromRGB, Color3.new(1, 1, 1)
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local RAYS = "rbxassetid://113538852110620"
local BLOOM = "rbxassetid://103142630740394"
local GLOW = "rbxassetid://104786452938879"
local STAR = "rbxassetid://107113949398119"

local R = {}
local CA = Cat.Crate and Cat.Crate.Art or {}
R.Background = "rbxassetid://" .. (CA.Reveal or 101751407252217)
local SFX = { Riser = 9045201066, Hit = 9048764753, Swell = 9040281024, Whoosh = 9120718279, Tick = 9125746460 }

local function sfx(name, vol, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. SFX[name]; s.Volume = vol or 0.8; s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(12, function() if s.Parent then s:Destroy() end end)
	return s
end

-- 3D Signature model in a ViewportFrame (same hero yaw as the Loadout). Returns step(t, amp).
function R.Model(vp, sig, fill, tilt)
	vp:ClearAllChildren()
	local assets = Vantage.Signatures:FindFirstChild("Assets")
	local src = assets and assets:FindFirstChild(sig.Asset or "")
	if not src then return function() end end
	local m = src:Clone()
	for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.Anchored = true end end
	m:PivotTo(CFrame.Angles(0, math.rad(sig.Yaw or 215), 0))
	if tilt then
		local c0 = (m:GetBoundingBox()).Position
		m:PivotTo(CFrame.new(c0) * CFrame.Angles(0, 0, tilt) * CFrame.new(-c0) * m:GetPivot())
	end
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	local c = cf.Position
	local base = m:GetPivot()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 24
	cam.Parent = vp
	vp.CurrentCamera = cam
	local r = math.max(size.X, size.Y, size.Z) * 0.5 / (fill or 0.85)
	cam.CFrame = CFrame.lookAt(c + V3(0, r * 0.12, r / math.tan(math.rad(12))), c)
	vp.Ambient = RGB(120, 118, 135):Lerp(sig.Color, 0.3)
	vp.LightColor = WHITE:Lerp(sig.Color, 0.35)
	vp.LightDirection = V3(-0.6, -1, -0.8)
	local mag = size.Magnitude
	return function(t, amp)
		if not m.Parent then return end
		m:PivotTo(CFrame.new(c) * CFrame.new(0, math.sin(t * 1.1) * mag * 0.025, 0) * CFrame.Angles(math.sin(t * 0.7) * 0.04, math.sin(t * 0.55) * (amp or 0.3), 0) * CFrame.new(-c) * base)
	end
end

-- id: Signature id. opts: { CrateArt = image, Left = n, Pill = function(parent, p) (ShopHS pill), OnDone = fn }
function R.Play(HS, id, opts)
	opts = opts or {}
	local sig = Cat.ById[id]
	if not sig then return end
	if R.Close then R.Close(true) end
	local tier = Cat.TierColor[sig.Tier] or WHITE
	local mythic = sig.Tier == "MYTHIC"
	local new = HS.new
	local gui = new("ScreenGui", { Name = "SignatureReveal", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 65, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local root = new("TextButton", { Name = "Root", Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(6, 3, 14), BackgroundTransparency = 1, Size = S(1, 1) }, gui)
	local bg = new("ImageLabel", { Name = "Bg", BackgroundTransparency = 1, Image = R.Background, ScaleType = Enum.ScaleType.Crop, ImageTransparency = 1, ImageColor3 = WHITE, Size = S(1, 1) }, root)
	local vig = new("ImageLabel", { Name = "Vignette", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(0, 0, 0), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1.6, 2.4) }, root)
	local stage = new("Frame", { Name = "Stage", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1920, 1080) }, root)
	local fit = new("UIScale", {}, stage)
	local function refit()
		local vp = Workspace.CurrentCamera.ViewportSize
		fit.Scale = math.min(vp.X / 1920, vp.Y / 1080)
	end
	refit()
	local CX, CY = 960, 470
	local glowBig = new("ImageLabel", { Name = "Bloom", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 200, 90), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(CX, CY), Size = O(1100, 1100) }, stage)
	local rays = new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(255, 214, 120), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(CX, CY), Size = O(1700, 1700) }, stage)
	local rays2 = new("ImageLabel", { Name = "Rays2", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = WHITE, ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(CX, CY), Size = O(1150, 1150) }, stage)

	-- the crate
	local crate = new("Frame", { Name = "Crate", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(CX, CY + 40), Size = O(440, 440), Visible = opts.CrateArt ~= nil }, stage)
	local crateScale = new("UIScale", {}, crate)
	local crateGlow = new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 200, 80), ImageTransparency = 0.6, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.55), Size = S(1.7, 1.7) }, crate)
	-- lid-pop only when both halves actually load (a freshly uploaded image can sit in moderation); else the 3/4 render
	local function loads(img)
		local st
		pcall(function() game:GetService("ContentProvider"):PreloadAsync({ img }, function(_, x) st = x end) end)
		return st == Enum.AssetFetchStatus.Success
	end
	local lidMode = opts.Lid ~= nil and opts.Body ~= nil and loads(opts.Lid) and loads(opts.Body)
	local leak, lid
	if lidMode then
		-- front view split at the seam (same canvas): light leaks from the seam as the lid rattles, then it blows off
		new("ImageLabel", { Name = "Body", BackgroundTransparency = 1, Image = opts.Body, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1) }, crate)
		leak = new("ImageLabel", { Name = "Leak", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 214, 110), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.33), Size = S(1.2, 0.3) }, crate)
		lid = new("ImageLabel", { Name = "Lid", BackgroundTransparency = 1, Image = opts.Lid, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1) }, crate)
	else
		new("ImageLabel", { BackgroundTransparency = 1, Image = opts.CrateArt or "", ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1) }, crate)
	end
	local crateFlare = new("ImageLabel", { BackgroundTransparency = 1, Image = STAR, ImageColor3 = RGB(255, 236, 170), ImageTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.42), Size = O(10, 10) }, crate)
	local hint = HS.text(stage, { Name = "Hint", Text = "TAP TO OPEN", TextSize = 30, Stroke = 3, StrokeColor = RGB(20, 10, 30), AnchorPoint = V2(0.5, 0), Position = O(CX, CY + 300), Size = O(500, 40) })
	hint.Visible = opts.CrateArt ~= nil

	-- the card
	local card = new("Frame", { Name = "Card", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = O(CX, CY), Size = O(440, 560), Visible = false }, stage)
	local cardScale = new("UIScale", { Scale = 0.3 }, card)
	local cardGlow = new("ImageLabel", { BackgroundTransparency = 1, Image = GLOW, ImageColor3 = tier, ImageTransparency = 0.15, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 1.2, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, 200, 1, 200) }, card)
	local face = new("ImageLabel", { Name = "Face", BackgroundColor3 = sig.Deep, Image = sig.Art or "", ScaleType = Enum.ScaleType.Crop, Size = S(1, 1) }, card)
	HS.corner(face, 26)
	HS.stroke(face, 6, tier:Lerp(WHITE, 0.25))
	local shade = new("Frame", { BackgroundColor3 = RGB(0, 0, 0), BorderSizePixel = 0, Size = S(1, 1) }, face)
	HS.corner(shade, 26)
	new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 1), NK(0.55, 1), NK(1, 0.2) }) }, shade)
	local vp = new("ViewportFrame", { Name = "Model", BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.48), Size = S(1.15, 0.92) }, face)
	local step = R.Model(vp, sig, 0.8)
	local sweepCg = new("CanvasGroup", { BackgroundTransparency = 1, Size = S(1, 1) }, face)
	HS.corner(sweepCg, 26)
	local band = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = S(-0.3, 0.5), Size = UDim2.new(0, 90, 2.4, 0), Rotation = 22 }, sweepCg)
	new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.5), NK(1, 1) }) }, band)
	local chip = new("Frame", { BackgroundColor3 = tier, Position = O(18, 18), Size = O(150, 38) }, face)
	HS.corner(chip, 10)
	HS.stroke(chip, 2.6, tier:Lerp(RGB(0, 0, 0), 0.7))
	HS.text(chip, { Text = sig.Tier, TextSize = 22, Stroke = 2.2, StrokeColor = tier:Lerp(RGB(0, 0, 0), 0.7), Size = S(1, 1), Position = O(0, -1) })

	-- text + buttons (faded in as a group)
	local info = new("CanvasGroup", { Name = "Info", BackgroundTransparency = 1, GroupTransparency = 1, Size = O(1920, 1080) }, stage)
	local top = HS.text(info, { Text = if opts.CrateArt then "NEW SIGNATURE UNLOCKED" else "SIGNATURE UNLOCKED", TextSize = 44, Stroke = 4, StrokeColor = RGB(40, 20, 4), AnchorPoint = V2(0.5, 0), Position = O(CX, 92), Size = O(900, 56) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(255, 250, 220), RGB(255, 196, 60)) }, top)
	local name = HS.text(info, { Text = string.upper(sig.Name), TextSize = 96, Stroke = 6, StrokeColor = RGB(10, 6, 24), AnchorPoint = V2(0.5, 0), Position = O(CX, 768), Size = O(1100, 110) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, tier:Lerp(WHITE, 0.35)) }, name)
	HS.text(info, { Text = sig.Title or "", TextSize = 32, Font = HS.MontX, Color = RGB(214, 204, 236), Stroke = 2.6, StrokeColor = RGB(10, 6, 24), AnchorPoint = V2(0.5, 0), Position = O(CX, 872), Size = O(900, 40) })
	if opts.Left then
		HS.text(info, { Text = if opts.Left > 0 then string.format("%d Signature%s left to unlock", opts.Left, if opts.Left == 1 then "" else "s") else "You now own every Signature!", TextSize = 22, Font = HS.MontX, Color = RGB(255, 214, 140), Stroke = 2, StrokeColor = RGB(10, 6, 24), AnchorPoint = V2(0.5, 0), Position = O(CX, 1032), Size = O(600, 30) })
	end
	local closing = false
	local conn
	local function close(instant)
		if closing then return end
		closing = true
		R.Close = nil
		if instant then
			if conn then conn:Disconnect() end
			gui:Destroy()
			return
		end
		HS.tween(root, 0.3, { BackgroundTransparency = 1 })
		HS.tween(bg, 0.3, { ImageTransparency = 1 })
		HS.tween(info, 0.25, { GroupTransparency = 1 })
		HS.tween(cardScale, 0.3, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.32, function()
			if conn then conn:Disconnect() end
			gui:Destroy()
			if opts.OnDone then opts.OnDone() end
		end)
	end
	R.Close = close
	if opts.Pill then
		local equipped = false
		local _, et
		_, et = opts.Pill(info, { Name = "Equip", Text = "EQUIP", TextSize = 36, AnchorPoint = V2(0.5, 0), Position = O(CX - 150, 940), Size = O(270, 74), Z = 2,
			Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Ink = RGB(25, 45, 12), OnClick = function()
				if equipped then return end
				equipped = true
				local ev = Remotes:FindFirstChild("SignatureEquip")
				if ev then ev:FireServer(id) end
				et.Text = "EQUIPPED"
				task.delay(0.35, function() close() end)
			end })
		opts.Pill(info, { Name = "Done", Text = "DONE", TextSize = 36, AnchorPoint = V2(0.5, 0), Position = O(CX + 150, 940), Size = O(270, 74), Z = 2,
			Rim = RGB(46, 44, 58), Top0 = RGB(160, 156, 176), Top1 = RGB(116, 112, 132), Ink = RGB(30, 28, 40), OnClick = function() close() end })
	end

	-- embers
	local embers = {}
	for i = 1, 46 do
		local sz = math.random(4, 10)
		local f = new("Frame", { BackgroundColor3 = (if i % 3 == 0 then sig.Color else tier):Lerp(WHITE, math.random() * 0.6), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz, sz), BackgroundTransparency = 1 }, stage)
		HS.corner(f, UDim.new(1, 0))
		embers[i] = { F = f, X = math.random(200, 1720), Y = math.random(0, 1080), V = 60 + math.random() * 140, Sw = math.random() * 6.28 }
	end
	local white = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 5 }, gui)

	-- sequence
	local t0 = time()
	local revealed, revealT = false, 0
	local popped = false
	local function reveal()
		if revealed or closing then return end
		if lidMode and not popped then
			-- the lid blows off in a burst of gold, then the flash
			popped = true
			hint.Visible = false
			sfx("Whoosh", 0.9, 1.2)
			HS.tween(lid, 0.45, { Position = UDim2.new(0.5, 60, 0.5, -620), Rotation = 28, ImageTransparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			HS.tween(leak, 0.25, { ImageTransparency = 0, Size = S(2.4, 1.6), Position = S(0.5, 0.25) })
			task.delay(0.24, function() popped = "done" reveal() end)
			return
		end
		if lidMode and popped ~= "done" then return end
		revealed, revealT = true, time()
		crate.Visible, hint.Visible = false, false
		white.BackgroundTransparency = 0
		HS.tween(white, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		sfx("Hit", 1, 0.9)
		sfx("Swell", 0.8, if mythic then 0.9 else 1.05)
		bg.ImageColor3 = WHITE:Lerp(tier, 0.35)
		HS.tween(bg, 0.5, { ImageTransparency = 0.05 })
		HS.tween(vig, 0.5, { ImageTransparency = 0.25 })
		glowBig.ImageColor3 = tier
		rays.ImageColor3, rays2.ImageColor3 = tier:Lerp(WHITE, 0.35), WHITE
		HS.tween(rays, 0.5, { ImageTransparency = 0.45 })
		HS.tween(rays2, 0.5, { ImageTransparency = 0.7 })
		HS.tween(glowBig, 0.5, { ImageTransparency = 0.3 })
		card.Visible = true
		cardScale.Scale = 0.3
		HS.tween(cardScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.delay(0.35, function() if not closing then HS.tween(info, 0.45, { GroupTransparency = 0 }) end end)
	end
	HS.tween(root, 0.3, { BackgroundTransparency = 0.12 })
	local CHARGE = 2.6
	local riser
	if opts.CrateArt then
		crateScale.Scale = 0.5
		HS.tween(crateScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		HS.tween(rays, 0.6, { ImageTransparency = 0.82 })
		riser = sfx("Riser", 0.9)
		sfx("Whoosh", 0.7)
		root.MouseButton1Click:Connect(function()
			if not revealed then
				if riser then riser:Stop() end
				reveal()
			end
		end)
	else
		task.delay(0.15, reveal)
	end
	local lastTick = 0
	conn = RunService.RenderStepped:Connect(function(dt)
		if not gui.Parent then return end
		refit()
		local t = time() - t0
		rays.Rotation = (t * 14) % 360
		rays2.Rotation = -(t * 22) % 360
		if not revealed and opts.CrateArt then
			local k = math.clamp(t / CHARGE, 0, 1)
			local sh = 2 + 22 * k * k
			crate.Position = O(CX + (math.random() - 0.5) * sh, CY + 40 + (math.random() - 0.5) * sh * 0.6 + math.sin(t * 3) * 6)
			crate.Rotation = (math.random() - 0.5) * k * 7
			crateGlow.ImageTransparency = 0.6 - 0.5 * k + math.sin(t * 20) * 0.05 * k
			crateGlow.Size = S(1.7 + 0.8 * k, 1.7 + 0.8 * k)
			crateFlare.ImageTransparency = 1 - k
			local fs = 40 + 520 * k * k
			crateFlare.Size = O(fs, fs)
			crateFlare.Rotation = t * 90
			if lidMode and not popped then
				lid.Position = UDim2.new(0.5, (math.random() - 0.5) * 6 * k, 0.5, -(k ^ 3) * 18 - math.random() * 6 * k * k)
				lid.Rotation = (math.random() - 0.5) * 4 * k
				leak.ImageTransparency = 1 - 0.9 * k ^ 1.5
			end
			hint.TextTransparency = 0.2 + 0.5 * (0.5 + 0.5 * math.sin(t * 5))
			if k > 0.3 and t - lastTick > (0.32 - 0.24 * k) then
				lastTick = t
				sfx("Tick", 0.35 + 0.4 * k, 0.9 + 0.6 * k)
			end
			if t >= CHARGE then reveal() end
		end
		if revealed then
			local rt = time() - revealT
			step(rt, 0.35)
			local k = (rt % 3.6) / 0.8
			band.Visible = k <= 1
			if k <= 1 then band.Position = UDim2.new(-0.3 + 1.6 * k, 0, 0.5, 0) end
			cardGlow.ImageTransparency = 0.12 + math.sin(rt * 2.4) * 0.1
			card.Position = O(CX, CY + math.sin(rt * 1.3) * 8)
			for _, e in embers do
				e.Y -= e.V * dt
				if e.Y < -10 then e.Y, e.X = 1090, math.random(200, 1720) end
				e.F.Position = O(e.X + math.sin(rt * 1.4 + e.Sw) * 12, e.Y)
				e.F.BackgroundTransparency = 0.1 + 0.9 * math.clamp(1 - e.Y / 900, 0, 1) ^ 2
			end
		end
	end)
	return close
end

return R
