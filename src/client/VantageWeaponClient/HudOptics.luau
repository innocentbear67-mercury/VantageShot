--[[
	VANTAGE — HudOptics (client, weapon system)
	Weapon-specific HUD pieces kept OUT of the Hud module so HUD rewrites can't drop them:
	  • ADS reticle (ring + dot) for red-dot / iron sights          StepOptics(ads)
	  • VX-01 holo window: straight frame on the real window opening SetSightWindow(a, b, style)
	  • SR-88 scope lens: drawn over the real eyepiece + black mask  SetScopeLens(a, b, scope)
	  • ER-04 heat gauge in the ammo block                           SetHeat(heat, locked)
	  • Forge sights (ADS.Sight Holo / Lens): collimated reticle     SetHoloSight(a, b, aim, sight, alpha, mag)
	    projected along the gun's sight axis, clipped to the optic's real window (WindowA/B)
	Install(HudClass) adds these methods to the Hud class (only names it doesn't already have).
	Needs from Hud: self.Dot (crosshair dot; its parent is the crosshair frame), self.Weapon,
	self.Pips + self:_buildPips(n), self.MagLabel, self.ReserveLabel, self.Prompt.
]]

local HudOptics = {}
-- the exosuit visor draws its own weapon / match telemetry from this shared table
local Feed = require(game:GetService("ReplicatedStorage").Vantage.UI.VisorFeed)

local V2 = Vector2.new
local C = Color3.fromRGB
local function O(x, y)
	return UDim2.fromOffset(x, y)
end
local DANGER = C(255, 80, 70)
local AMBER = C(255, 190, 70)
local HEAT = C(90, 230, 255)

local function new(class: string, props, parent: Instance?)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- world point -> UDim2 relative to the crosshair centre (+ the viewport point)
local function fromCross(self, p: Vector3): (UDim2, Vector2)
	local cam = workspace.CurrentCamera
	local v = cam:WorldToViewportPoint(p)
	local c = cam.ViewportSize / 2
	local cross = self.Dot.Parent
	return UDim2.new(cross.Position.X.Scale, cross.Position.X.Offset + v.X - c.X, cross.Position.Y.Scale, cross.Position.Y.Offset + v.Y - c.Y), V2(v.X, v.Y)
end

local M = {}

function M:_optReticle(style)
	local key = style.Size .. ":" .. style.Thickness .. ":" .. tostring(style.Color)
	if self.OptReticle and self.OptReticle.Parent and self.OptReticleKey == key then
		return self.OptReticle
	end
	if self.OptReticle then
		self.OptReticle:Destroy()
	end
	local cross = self.Dot.Parent
	local r = new("Frame", { Name = "ADSReticle", AnchorPoint = V2(0.5, 0.5), Position = cross.Position, Size = O(style.Size, style.Size), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, self.Gui)
	local ring = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 }, r)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	new("UIStroke", { Color = style.Color, Thickness = style.Thickness }, ring)
	local dot = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(style.Dot, style.Dot), BackgroundColor3 = style.Color, BorderSizePixel = 0, ZIndex = 21 }, r)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	self.OptReticle, self.OptReticleKey = r, key
	return r
end

-- every frame (WeaponController:PostCamera): reticle for non-scope sights once aimed
function M:StepOptics(ads: number, weapon)
	local A = weapon and weapon.ADS
	local style = A and A.Reticle
	if style and not A.Scope and not A.Sight then
		self:_optReticle(style).Visible = ads > 0.9
	elseif self.OptReticle then
		self.OptReticle.Visible = false
	end
	if self.OptScope and not (A and A.Scope) then
		self.OptScope.Visible = false
	end
	if self.OptWindow and not (style and style.Window) then
		self.OptWindow.Visible = false
	end
end

function M:HideOptics()
	for _, k in { "OptReticle", "OptScope", "OptWindow", "OptHolo" } do
		if self[k] then
			self[k].Visible = false
		end
	end
end

-- ─── Forge sights ─────────────────────────────────────────────────────────────────────
-- Reticle shapes, built at 100 px and scaled by UIScale (Size = px at the hip FOV; holo
-- reticles subtend a fixed angle, so they grow with the ADS magnification).
local function buildReticle(parent: Instance, R)
	local col = R.Color or C(90, 230, 255)
	local th = R.Thickness or 2
	local root = new("Frame", { Name = "Reticle", AnchorPoint = V2(0.5, 0.5), Size = O(100, 100), BackgroundTransparency = 1, ZIndex = 21 }, parent)
	local parts = {}
	local scale = new("UIScale", { Scale = 0.2 }, root)
	local function bar(x, y, w, h, rot)
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, y), Size = O(w, h), Rotation = rot or 0, BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 21 }, root)
		table.insert(parts, { f, "BackgroundTransparency" })
		return f
	end
	local function dot(d)
		local f = bar(0, 0, d, d)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		return f
	end
	local function ring(d, t)
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(d, d), BackgroundTransparency = 1, ZIndex = 21 }, root)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		local st = new("UIStroke", { Color = col, Thickness = t }, f)
		table.insert(parts, { st, "Transparency" })
	end
	local style = R.Style or "RingDot"
	local k = 100 / (R.Size or 20) -- authored in screen px; drawn at 100 px
	local t = th * k
	if style == "RingDot" then
		ring(100 - t, t)
		dot((R.Dot or 3) * k)
	elseif style == "Chevron" then
		-- prism chevron: tip on the aim point, stadia ticks below
		bar(-14, 10, 40, t, -45)
		bar(14, 10, 40, t, 45)
		for i = 1, 3 do
			bar(0, 18 + i * 14, 22 - i * 4, t * 0.8)
		end
		dot((R.Dot or 2) * k)
	elseif style == "Ring4" then
		ring(70, t)
		for _, a in { 0, 90, 180, 270 } do
			local r = math.rad(a)
			bar(math.cos(r) * 44, math.sin(r) * 44, if a % 180 == 0 then 18 else t, if a % 180 == 0 then t else 18)
		end
		dot((R.Dot or 3) * k)
	else -- "Dot"
		dot((R.Dot or 4) * k)
	end
	return root, scale, parts
end

-- a / b = opposite window corners (world), aim = a far point along the sight axis (world)
function M:SetHoloSight(a: Vector3?, b: Vector3?, aim: Vector3?, sight, alpha: number, mag: number)
	local f = self.OptHolo
	if not a or not b or not aim or alpha <= 0.01 then
		if f then
			f.Visible = false
		end
		return
	end
	local R = sight.Reticle or {}
	local key = (R.Style or "RingDot") .. ":" .. tostring(R.Color) .. ":" .. tostring(R.Size) .. ":" .. tostring(R.Thickness)
	if not f or not f.Parent or self.OptHoloKey ~= key then
		if f then
			f:Destroy()
		end
		f = new("Frame", { Name = "ADSHolo", AnchorPoint = V2(0.5, 0.5), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 20, Visible = false }, self.Gui)
		local ret, sc, parts = buildReticle(f, R)
		self.OptHolo, self.OptHoloKey = f, key
		self.OptHoloRet, self.OptHoloScale, self.OptHoloParts = ret, sc, parts
	end
	local cam = workspace.CurrentCamera
	local v = cam:WorldToViewportPoint(aim)
	if v.Z <= 0 then
		f.Visible = false
		return
	end
	local _, pa = fromCross(self, a)
	local _, pb = fromCross(self, b)
	local inset = sight.WindowInset or 1
	f.Size = O(math.max(0, math.abs(pa.X - pb.X) - inset * 2), math.max(0, math.abs(pa.Y - pb.Y) - inset * 2))
	f.Position = fromCross(self, (a + b) / 2)
	local mid = (pa + pb) / 2
	self.OptHoloRet.Position = UDim2.new(0.5, v.X - mid.X, 0.5, v.Y - mid.Y)
	self.OptHoloScale.Scale = (R.Size or 20) * mag / 100
	local tr = 1 - alpha * (R.Opacity or 1)
	for _, p in self.OptHoloParts do
		local inst, prop = p[1], p[2]
		inst[prop] = tr
	end
	f.Visible = true
	if self.OptReticle then
		self.OptReticle.Visible = false
	end
	if self.OptWindow then
		self.OptWindow.Visible = false
	end
end

-- holo sight: a straight frame lining the real window opening (a / b = opposite corners, world)
function M:SetSightWindow(a: Vector3?, b: Vector3?, style)
	if not a or not b then
		if self.OptWindow then
			self.OptWindow.Visible = false
		end
		return
	end
	local f = self.OptWindow
	if not f or not f.Parent then
		local cross = self.Dot.Parent
		f = new("Frame", { Name = "ADSWindow", AnchorPoint = V2(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 19, Visible = false }, self.Gui)
		new("UIStroke", { Name = "Edge", Color = style.Color, Thickness = style.Thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter }, f)
		self.OptWindow = f
	end
	local _, pa = fromCross(self, a)
	local _, pb = fromCross(self, b)
	local inset = style.Inset or 0
	f.Size = O(math.abs(pa.X - pb.X) + inset * 2, math.abs(pa.Y - pb.Y) + inset * 2)
	f.Position = fromCross(self, (a + b) / 2)
	f.Visible = true
end

-- energy weapon heat gauge in the ammo block (0..1; locked = overheated / venting)
function M:SetHeat(heat: number, locked: boolean)
	Feed.Heat, Feed.Locked = heat, locked
	if not self.Pips or #self.Pips ~= 20 then
		self:_buildPips(20)
	end
	self.MagLabel.Text = tostring(math.floor(heat * 100 + 0.5))
	self.ReserveLabel.Text = if locked then "VENT" else "HEAT"
	local col = if locked then DANGER elseif heat > 0.75 then AMBER else HEAT
	self.MagLabel.TextColor3 = if locked then DANGER elseif heat > 0.75 then AMBER else C(255, 255, 255)
	for i, p in self.Pips do
		p.BackgroundTransparency = if i <= math.ceil(heat * 20 - 0.01) then 0 else 0.82
		p.BackgroundColor3 = col
	end
	self.Prompt.Text = if locked then "OVERHEATED" elseif heat > 0.75 then "HEAT HIGH" else ""
end

function M:_optScope(sc)
	local key = sc.Kind
	if self.OptScope and self.OptScope.Parent and self.OptScopeKey == key then
		return self.OptScope
	end
	if self.OptScope then
		self.OptScope:Destroy()
	end
	local cross = self.Dot.Parent
	local lens = new("Frame", { Name = "ADSScope", AnchorPoint = V2(0.5, 0.5), Position = cross.Position, Size = O(100, 100), BackgroundColor3 = sc.Tint or C(255, 255, 255), BackgroundTransparency = 0.94, BorderSizePixel = 0, Visible = false, ZIndex = 16 }, self.Gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, lens)
	-- a huge stroke around the round lens darkens (translucent) the rest of the screen
	new("UIStroke", { Color = C(0, 0, 0), Thickness = 3000, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, lens)
	local rim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 16 }, lens)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, rim)
	new("UIStroke", { Color = C(30, 34, 40), Thickness = 6 }, rim)
	local line = C(10, 10, 12)
	local function bar(px, py, sx, sy, col, z)
		return new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(px, py), Size = UDim2.new(sx[1], sx[2], sy[1], sy[2]), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = z or 17 }, lens)
	end
	bar(0.5, 0.5, { 1, 0 }, { 0, 1 }, line)
	bar(0.5, 0.5, { 0, 1 }, { 1, 0 }, line)
	for _, s in { -1, 1 } do
		bar(0.5 + s * 0.36, 0.5, { 0.28, 0 }, { 0, 5 }, line)
		bar(0.5, 0.5 + s * 0.36, { 0, 5 }, { 0.28, 0 }, line)
		for k = 1, 3 do
			bar(0.5, 0.5 + s * k * 0.05, { 0, 5 }, { 0, 5 }, line)
		end
	end
	local d = bar(0.5, 0.5, { 0, 4 }, { 0, 4 }, C(255, 70, 60), 18)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
	self.OptScope, self.OptScopeKey = lens, key
	return lens
end

-- scope lens over the real eyepiece glass (a = centre, b = a rim point, world)
function M:SetScopeLens(a: Vector3?, b: Vector3?, sc)
	if not a or not b or not sc then
		if self.OptScope then
			self.OptScope.Visible = false
		end
		return
	end
	local lens = self:_optScope(sc)
	local _, pa = fromCross(self, a)
	local _, pb = fromCross(self, b)
	local d = math.floor((pa - pb).Magnitude * 2 + 0.5)
	lens.Size = O(d, d)
	-- sized from the eyepiece, but centred on the camera axis: the reticle must not follow gun sway / bob
	lens.Position = self.Dot.Parent.Position
	lens.Visible = true
end

-- publish what the HUD is told to the visor feed (wraps, never replaces, the Hud's own methods)
local function wrapFeed(HudClass)
	if rawget(HudClass, "_visorFeedWrapped") then
		return
	end
	HudClass._visorFeedWrapped = true
	local function after(name, fn)
		local orig = HudClass[name]
		if type(orig) ~= "function" then
			return
		end
		HudClass[name] = function(self, ...)
			local r = table.pack(orig(self, ...))
			pcall(fn, self, ...)
			return table.unpack(r, 1, r.n)
		end
	end
	after("SetWeapon", function(_, weapon)
		Feed.Weapon = weapon
		Feed.Heat, Feed.Locked, Feed.Reload = nil, false, nil
		Feed.Size = weapon and weapon.MagazineSize or 0
	end)
	after("SetAmmo", function(_, mag, reserve, size)
		Feed.Mag, Feed.Reserve, Feed.Size = mag, reserve, size
	end)
	after("SetReload", function(_, progress)
		Feed.Reload = progress
	end)
	after("Step", function(self)
		if self.Timer then
			Feed.Timer = self.Timer.Text
		end
	end)
end

function HudOptics.Install(HudClass)
	for name, fn in M do
		if HudClass[name] == nil then
			HudClass[name] = fn
		end
	end
	wrapFeed(HudClass)
	return HudClass
end

return HudOptics
