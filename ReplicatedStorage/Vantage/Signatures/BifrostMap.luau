--!nonstrict
--[[
	VANTAGE — Bifröst destination picker (client UI) — v1 2026-11-19
	A full-screen, top-down live map of the current arena (a near-orthographic ViewportFrame camera over a
	cached clone of the map). Shows you (gold) and teammates (blue). Hover shows a marker: green = standable
	ground, red = not allowed (walls, roofs too steep, off the map, no headroom). Click/tap a green spot to
	travel. Shift or Esc cancels. Times out after 6 s. The caster stands still while it is open.

	BifrostMap.Pick{ MapRoot = Instance?, Timeout = 6, Teammates = { Player }, Auto = Vector3? } -> Vector3? (yields)
	BifrostMap.Valid(pos) -> Vector3?   ground point if a spot is allowed (the server repeats this check)
]]
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local BifrostMap = {}
local GOLD = Color3.fromRGB(255, 201, 74)
local INK = Color3.fromRGB(10, 12, 18)
local OK = Color3.fromRGB(90, 255, 140)
local BAD = Color3.fromRGB(255, 80, 70)
local RAINBOW = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 50)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 255, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 140, 255)) })

local SKIP = { Camera = true, Terrain = true, SignatureFX = true }

-- the arena the player is standing in: the smallest top-level Model/Folder whose bounds contain them
local function boundsOf(root)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Size.Magnitude > 2 then
			local c, h = d.Position, d.Size / 2
			local r = Vector3.one * h.Magnitude
			lo = lo:Min(c - r); hi = hi:Max(c + r)
			n += 1
		end
	end
	if n == 0 then return nil end
	return lo, hi, n
end

function BifrostMap.FindArena(pos: Vector3)
	local best, bestArea
	for _, c in Workspace:GetChildren() do
		if (c:IsA("Model") or c:IsA("Folder")) and not SKIP[c.Name] and not Players:GetPlayerFromCharacter(c) then
			local lo, hi = boundsOf(c)
			if lo and pos.X >= lo.X and pos.X <= hi.X and pos.Z >= lo.Z and pos.Z <= hi.Z then
				local area = (hi.X - lo.X) * (hi.Z - lo.Z)
				if area > 400 and (not bestArea or area < bestArea) then best, bestArea = c, area end
			end
		end
	end
	return best
end

local function rayParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for _, pl in Players:GetPlayers() do if pl.Character then ex[#ex + 1] = pl.Character end end
	local fx = Workspace:FindFirstChild("SignatureFX"); if fx then ex[#ex + 1] = fx end
	p.FilterDescendantsInstances = ex
	p.RespectCanCollide = true
	return p
end

local bounds -- { lo, hi } of the open map
function BifrostMap.Valid(xz: Vector3)
	if bounds and (xz.X < bounds[1].X or xz.X > bounds[2].X or xz.Z < bounds[1].Z or xz.Z > bounds[2].Z) then return nil end
	local top = (bounds and bounds[2].Y or xz.Y + 200) + 20
	local hit = Workspace:Raycast(Vector3.new(xz.X, top, xz.Z), Vector3.new(0, -(top - (bounds and bounds[1].Y or xz.Y - 200)) - 40, 0), rayParams())
	if not hit or hit.Normal.Y < 0.75 then return nil end
	-- headroom for a player
	if Workspace:Raycast(hit.Position + Vector3.new(0, 0.3, 0), Vector3.new(0, 6, 0), rayParams()) then return nil end
	return hit.Position
end

-- clone the arena into a WorldModel once per arena (visual only: no scripts, sounds, lights or effects)
local cache = {}
local function worldOf(root, floorY)
	if cache[root] then return cache[root] end
	local wm = Instance.new("WorldModel")
	wm.Name = "BifrostMapWorld"
	local ok, clone = pcall(function()
		local was = root.Archivable
		root.Archivable = true
		local c = root:Clone()
		root.Archivable = was
		return c
	end)
	if ok and clone then
		for _, d in clone:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail")
				or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("ProximityPrompt") then
				d:Destroy()
			elseif d:IsA("BasePart") and floorY then
				-- strip ceilings / roofs so the play space shows from above: wide, thin, high slabs
				local sz = d.Size
				local cf = d.CFrame
				local up = math.abs(cf.UpVector.Y) > 0.9 and sz.Y or (math.abs(cf.RightVector.Y) > 0.9 and sz.X or sz.Z)
				local bottom = d.Position.Y - up / 2
				local wide = (sz.X * sz.Y * sz.Z) / math.max(up, 0.05)
				if bottom > floorY + 13 and up < 5 and wide > 600 then d:Destroy() end
			end
		end
		clone.Parent = wm
	end
	cache[root] = wm
	return wm
end

function BifrostMap.Pick(o)
	o = o or {}
	local player = Players.LocalPlayer
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local arena = o.MapRoot or BifrostMap.FindArena(root.Position)
	local lo, hi
	if arena then lo, hi = boundsOf(arena) end
	if not lo then lo, hi = root.Position - Vector3.new(150, 40, 150), root.Position + Vector3.new(150, 80, 150) end
	bounds = { lo, hi }
	if o.Auto then return BifrostMap.Valid(o.Auto) end

	local size = hi - lo
	local half = math.max(size.X, size.Z) / 2 * 1.04
	local center = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local FOV = 12
	local h = half / math.tan(math.rad(FOV / 2))

	-- UI
	local gui = Instance.new("ScreenGui")
	gui.Name = "BifrostMap"; gui.IgnoreGuiInset = true; gui.DisplayOrder = 1000; gui.ResetOnSpawn = false
	local back = Instance.new("Frame"); back.Size = UDim2.fromScale(1, 1); back.BackgroundColor3 = INK; back.BackgroundTransparency = 0.08; back.Parent = gui
	local vpSize = workspace.CurrentCamera.ViewportSize
	local side = math.floor(math.min(vpSize.X * 0.9, vpSize.Y * 0.78))
	local vf = Instance.new("ViewportFrame")
	vf.AnchorPoint = Vector2.new(0.5, 0.5); vf.Position = UDim2.new(0.5, 0, 0.5, 18); vf.Size = UDim2.fromOffset(side, side)
	vf.BackgroundColor3 = Color3.fromRGB(20, 24, 32); vf.Ambient = Color3.fromRGB(200, 200, 210); vf.LightColor = Color3.new(1, 1, 1); vf.LightDirection = Vector3.new(-0.3, -1, -0.4)
	vf.Parent = back
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = vf
	local stroke = Instance.new("UIStroke"); stroke.Thickness = 3; stroke.Color = Color3.new(1, 1, 1); stroke.Parent = vf
	local grad = Instance.new("UIGradient"); grad.Color = RAINBOW; grad.Parent = stroke
	local cam = Instance.new("Camera"); cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(center + Vector3.new(0, h, 0), center, Vector3.new(0, 0, -1))
	cam.Parent = vf; vf.CurrentCamera = cam
	if arena then worldOf(arena, root.Position.Y - 3).Parent = vf end

	local function label(text, size, y, col)
		local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, y); l.Size = UDim2.new(1, 0, 0, size + 6); l.Font = Enum.Font.GothamBlack; l.TextSize = size
		l.TextColor3 = col or Color3.new(1, 1, 1); l.Text = text; l.Parent = back
		return l
	end
	label("BIFRÖST", 30, 14, GOLD)
	local hint = label(UIS.TouchEnabled and "Tap where you want to go" or "Click where you want to go  ·  Shift / Esc to cancel", 15, 50, Color3.fromRGB(200, 205, 215))
	hint.Font = Enum.Font.GothamBold
	local barBack = Instance.new("Frame"); barBack.AnchorPoint = Vector2.new(0.5, 1); barBack.Position = UDim2.new(0.5, 0, 1, -16)
	barBack.Size = UDim2.fromOffset(side, 8); barBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56); barBack.Parent = back
	Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
	local bar = Instance.new("Frame"); bar.Size = UDim2.fromScale(1, 1); bar.BackgroundColor3 = Color3.new(1, 1, 1); bar.Parent = barBack
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local barGrad = Instance.new("UIGradient"); barGrad.Color = RAINBOW; barGrad.Parent = bar
	if UIS.TouchEnabled then
		local cancel = Instance.new("TextButton"); cancel.AnchorPoint = Vector2.new(1, 0); cancel.Position = UDim2.new(1, -16, 0, 16); cancel.Size = UDim2.fromOffset(110, 40)
		cancel.BackgroundColor3 = Color3.fromRGB(40, 44, 56); cancel.Font = Enum.Font.GothamBold; cancel.TextSize = 16; cancel.TextColor3 = Color3.new(1, 1, 1); cancel.Text = "CANCEL"
		cancel.Parent = back; Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 8)
		cancel.Activated:Connect(function() o.__cancel = true end)
	end

	-- world <-> map (linear: the camera is near-orthographic)
	local function toUV(p) return Vector2.new((p.X - center.X) / (2 * half) + 0.5, (p.Z - center.Z) / (2 * half) + 0.5) end
	local function fromScreen(sp)
		local rel = (sp - vf.AbsolutePosition) / vf.AbsoluteSize
		if rel.X < 0 or rel.X > 1 or rel.Y < 0 or rel.Y > 1 then return nil end
		return Vector3.new(center.X + (rel.X - 0.5) * 2 * half, center.Y, center.Z + (rel.Y - 0.5) * 2 * half)
	end
	local function dot(color, sz)
		local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5); f.Size = UDim2.fromOffset(sz, sz); f.BackgroundColor3 = color; f.ZIndex = 5; f.Parent = vf
		Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
		local s2 = Instance.new("UIStroke"); s2.Thickness = 2; s2.Color = INK; s2.Parent = f
		return f
	end
	local me = dot(GOLD, 16)
	local mates = {}
	for _, pl in o.Teammates or {} do if pl ~= player then mates[pl] = dot(Color3.fromRGB(90, 170, 255), 12) end end
	local marker = Instance.new("Frame"); marker.AnchorPoint = Vector2.new(0.5, 0.5); marker.Size = UDim2.fromOffset(34, 34); marker.BackgroundTransparency = 1; marker.ZIndex = 6
	marker.Visible = false; marker.Parent = vf
	local ms = Instance.new("UIStroke"); ms.Thickness = 3; ms.Color = OK; ms.Parent = marker
	Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)
	local cross = Instance.new("Frame"); cross.AnchorPoint = Vector2.new(0.5, 0.5); cross.Position = UDim2.fromScale(0.5, 0.5); cross.Size = UDim2.fromOffset(6, 6)
	cross.BackgroundColor3 = OK; cross.ZIndex = 7; cross.Parent = marker
	Instance.new("UICorner", cross).CornerRadius = UDim.new(1, 0)

	gui.Parent = player:WaitForChild("PlayerGui")
	local result, done = nil, false
	local lastCheck, lastValid, lastPos = 0, nil, nil
	local function screenPoint(input)
		if input and input.UserInputType == Enum.UserInputType.Touch then return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset() end
		return UIS:GetMouseLocation()
	end
	local function evaluate(sp)
		local w = fromScreen(sp)
		if not w then marker.Visible = false; return nil end
		marker.Visible = true
		marker.Position = UDim2.fromOffset(sp.X - vf.AbsolutePosition.X, sp.Y - vf.AbsolutePosition.Y)
		local v = BifrostMap.Valid(w)
		ms.Color = v and OK or BAD; cross.BackgroundColor3 = ms.Color
		return v
	end
	local conns = {}
	conns[#conns + 1] = UIS.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonB then
			done = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local v = evaluate(screenPoint(input))
			if v then result = v; done = true end
		end
	end)
	local timeout = o.Timeout or 6
	local t0 = os.clock()
	while not done and not o.__cancel do
		local t = os.clock() - t0
		bar.Size = UDim2.fromScale(math.max(0, 1 - t / timeout), 1)
		if t >= timeout then break end
		-- live positions
		local uv = toUV(root.Position); me.Position = UDim2.fromScale(uv.X, uv.Y)
		for pl, f in mates do
			local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			f.Visible = r ~= nil
			if r then local u = toUV(r.Position); f.Position = UDim2.fromScale(u.X, u.Y) end
		end
		if not UIS.TouchEnabled and os.clock() - lastCheck > 0.05 then
			lastCheck = os.clock()
			evaluate(UIS:GetMouseLocation())
		end
		task.wait()
	end
	for _, c in conns do c:Disconnect() end
	local wm = arena and cache[arena]
	if wm then wm.Parent = nil end
	gui:Destroy()
	return result
end

return BifrostMap
