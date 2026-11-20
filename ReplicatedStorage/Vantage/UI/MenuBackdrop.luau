-- MenuBackdrop — reusable frame-sequence background player for the Vantage menu (v4).
--
-- Clips come from the MenuFrames manifest:
--   { ids = {...}, fps = 24, after = "hold" | "loop", loopFrom, loopTo, once = true,
--     hold = { TL = id, TR = id, BL = id, BR = id } }
--   * after = "hold" (default): plays once, eases out into the last frame, then holds it with a
--     very slow camera drift. If `hold` tiles are given, the held frame swaps to the full-res
--     1920x1080 version (4 tiles of 960x540; Roblox caps a single image at 1024 px).
--   * after = "loop": plays once, then loops loopFrom..loopTo
--   * once = true: plays once at constant speed and fires Finished (deploy transition)
--
-- API
--   local bd = MenuBackdrop.new(parentGuiObject)
--   bd:Preload(name, onReady?)   -- builds + loads the clip's frames; onReady when all are decoded
--   bd:IsReady(name) -> bool
--   bd:Play(name, {fade = 0.5})      -- frame 1 shows at once; motion starts when the clip is ready
--   bd:Play(name, {fromEnd = true})  -- open straight onto the held last frame (return visits)
--   bd:Pause()  bd:Resume()  bd:Stop()  bd:SetSpeed(n)
--   bd:Release(name)             -- frees a clip entirely
--   bd.Finished:Connect(fn(name))
--   bd:Destroy()
--
-- How it stays smooth:
--   * One ImageLabel per frame, image set once. Playback only toggles visibility/transparency
--     (changing .Image resets IsLoaded for a few ticks, which made the first version stutter).
--   * Frame blending: frame i is opaque, frame i+1 fades in over it by the fractional time.
--   * Motion waits until every frame of the clip is decoded; frame 1 is held as a still meanwhile.
--   * A frame that misses the ready window stands in as the nearest earlier good frame, keeps
--     loading in the background (re-requested every few seconds) and is swapped in once it arrives.
--   * Hold tiles that are late are revealed as soon as all four arrive.
--   * Roblox never loads a fully transparent image, so loading layers sit at 99.5%.
-- Memory:
--   * Phones (touch, no keyboard) use every 2nd frame at half the fps.
--   * When a clip reaches its end, every frame except the last is destroyed ("trimmed"); return
--     visits only need the last frame + hold tiles. Only the clip being played holds all frames.
-- Backup of v2: ServerStorage._MenuBackup.MenuBackdrop_v2

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Manifest = require(script.Parent:WaitForChild("MenuFrames"))

local MenuBackdrop = {}
MenuBackdrop.__index = MenuBackdrop

local READY_TIMEOUT = 30
local HEAL_FOR = 90     -- keep retrying frames/tiles that missed the ready window for this long
local RETRY_EVERY = 8   -- seconds between re-requests of a frame that has not loaded
-- start early when nearly everything is in and the stragglers have stalled (a failed fetch
-- should not freeze frame 1 for the whole timeout); stragglers heal in the background
local NEAR_READY, STALL = 0.95, 2.5
local HIDDEN = 0.995
local MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
MenuBackdrop.Mobile = MOBILE

local function asId(v)
	return typeof(v) == "number" and ("rbxassetid://" .. v) or v
end

local function getClip(name)
	local c = Manifest.Clips[name]
	if not c then
		warn("[MenuBackdrop] no clip named", name)
		return nil
	end
	if not c._ids then
		local ids = {}
		for _, v in ipairs(c.ids) do
			if v and v ~= 0 and v ~= "" then table.insert(ids, asId(v)) end
		end
		if #ids < #c.ids then
			warn(("[MenuBackdrop] %s: %d of %d frames have no ID"):format(name, #c.ids - #ids, #c.ids))
		end
		c._fps = c.fps
		if MOBILE and c.fps >= 20 and #ids > 2 then
			-- phones: every 2nd frame at half rate (same duration, half the memory)
			local half = {}
			for i = 1, #ids, 2 do table.insert(half, ids[i]) end
			if half[#half] ~= ids[#ids] then table.insert(half, ids[#ids]) end
			ids = half
			c._fps = c.fps / 2
		end
		c._ids = ids
		if c.hold then
			c._hold = {}
			for k, v in c.hold do
				if v and v ~= 0 then c._hold[k] = asId(v) end
			end
			if not (c._hold.TL and c._hold.TR and c._hold.BL and c._hold.BR) then
				c._hold = nil
			end
		end
	end
	return c
end

local function mkLabel(parent, name, image)
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = UDim2.fromScale(1, 1)
	l.ScaleType = Enum.ScaleType.Crop
	l.ZIndex = 1
	l.Image = image or ""
	l.Parent = parent
	return l
end

function MenuBackdrop.new(parent)
	local root = Instance.new("Frame")
	root.Name = "MenuBackdrop"
	root.BackgroundColor3 = Color3.fromRGB(8, 13, 8) -- obsidian until frame 1 lands
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 0
	root.ClipsDescendants = true
	root.Parent = parent

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local fade = mkLabel(holder, "ClipFade")
	fade.ZIndex = 5
	fade.Visible = false

	local self = setmetatable({
		Root = root,
		Holder = holder,
		Scale = scale,
		Fade = fade,
		pools = {}, -- name -> { labels = {[i] = ImageLabel}, map, ready, trimmed, grid, tiles }
		waiters = {},
		clip = nil,
		name = nil,
		t = 0,
		speed = 1,
		playing = false,
		ended = false,
		startedAt = 0,
		vi = nil, vj = nil,
		fadeTween = nil,
		driftTween = nil,
		_finished = Instance.new("BindableEvent"),
	}, MenuBackdrop)
	self.Finished = self._finished.Event
	self._conn = RunService.RenderStepped:Connect(function(dt) self:_step(dt) end)
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, p in self.pools do
			if p.grid then self:_cover(p.grid) end
		end
	end)
	return self
end

-- size a 16:9 frame to cover the holder (same framing as ScaleType.Crop on the frames)
function MenuBackdrop:_cover(f)
	local a = self.Holder.AbsoluteSize
	if a.X < 2 or a.Y < 2 then
		f.Size = UDim2.fromScale(1, 1)
		return
	end
	local ar = 16 / 9
	if a.X / a.Y > ar then
		f.Size = UDim2.fromScale(1, (a.X / ar) / a.Y)
	else
		f.Size = UDim2.fromScale((a.Y * ar) / a.X, 1)
	end
end

function MenuBackdrop:IsReady(name)
	local p = self.pools[name]
	return p ~= nil and p.ready
end

function MenuBackdrop:Preload(name, onReady)
	local c = getClip(name)
	if not c or #c._ids == 0 then
		if onReady then task.spawn(onReady) end
		return
	end
	local p = self.pools[name]
	if p and p.ready then
		if onReady then task.spawn(onReady) end
		return
	end
	if onReady then
		self.waiters[name] = self.waiters[name] or {}
		table.insert(self.waiters[name], onReady)
	end
	if p then return end -- already loading

	p = { labels = {}, ready = false, trimmed = false, map = {}, tiles = {} }
	self.pools[name] = p
	for i, id in ipairs(c._ids) do
		local l = mkLabel(self.Holder, ("%s_%03d"):format(name, i), id)
		l.ImageTransparency = HIDDEN -- invisible, but decoded
		p.labels[i] = l
	end
	if c._hold then
		local grid = Instance.new("Frame")
		grid.Name = "Hold_" .. name
		grid.BackgroundTransparency = 1
		grid.AnchorPoint = Vector2.new(0.5, 0.5)
		grid.Position = UDim2.fromScale(0.5, 0.5)
		grid.ZIndex = 3
		grid.Parent = self.Holder
		self:_cover(grid)
		for k, pos in { TL = { 0, 0 }, TR = { 0.5, 0 }, BL = { 0, 0.5 }, BR = { 0.5, 0.5 } } do
			local t = Instance.new("ImageLabel")
			t.Name = k
			t.BackgroundTransparency = 1
			t.BorderSizePixel = 0
			t.Position = UDim2.fromScale(pos[1], pos[2])
			-- a hair of overlap hides any seam between tiles
			t.Size = UDim2.new(0.5, 1, 0.5, 1)
			t.ScaleType = Enum.ScaleType.Stretch
			t.Image = c._hold[k]
			t.ImageTransparency = HIDDEN
			t.ZIndex = 3
			t.Parent = grid
			table.insert(p.tiles, t)
		end
		p.grid = grid
	end

	task.spawn(function()
		local t0, lastRetry = os.clock(), os.clock()
		p.lastCount, p.lastProgress = -1, os.clock()
		while os.clock() - t0 < READY_TIMEOUT do
			if os.clock() - lastRetry > RETRY_EVERY then
				lastRetry = os.clock()
				self:_retry(p)
			end
			local loaded = 0
			for _, l in p.labels do
				if l.IsLoaded then loaded += 1 end
			end
			local tiles = 0
			for _, t in p.tiles do
				if t.IsLoaded then tiles += 1 end
			end
			if loaded == #p.labels and tiles == #p.tiles then break end
			if loaded + tiles ~= p.lastCount then
				p.lastCount, p.lastProgress = loaded + tiles, os.clock()
			elseif loaded >= #p.labels * NEAR_READY and os.clock() - p.lastProgress > STALL then
				break
			end
			task.wait(0.05)
		end
		if self.pools[name] ~= p then return end -- released meanwhile
		local missing = self:_remap(name, p)
		if #missing > 0 then
			warn(("[MenuBackdrop] %s: %d frames still loading at start (standing in with the previous frame): %s"):format(name, #missing, table.concat(missing, ",")))
		end
		p.tilesOk = self:_tilesLoaded(p)
		if p.grid and p.tilesOk then
			p.grid.Visible = false
			for _, t in p.tiles do t.ImageTransparency = 0 end
		end -- (late tiles stay in the tree at 99.5% so they keep loading)
		for i, l in p.labels do
			if not (self.name == name and (i == self.vi or i == self.vj)) then
				if l.IsLoaded then
					l.Visible = false
					l.ImageTransparency = 0
				else
					-- keep it loading underneath everything
					l.ZIndex = 0
				end
			end
		end
		p.ready = true
		for _, fn in ipairs(self.waiters[name] or {}) do task.spawn(fn) end
		self.waiters[name] = nil
		if #missing > 0 or (p.grid and not p.tilesOk) then
			self:_heal(name, p)
		end
	end)
end

function MenuBackdrop:_tilesLoaded(p)
	if not p.grid then return false end
	for _, t in p.tiles do
		if not t.IsLoaded then return false end
	end
	return true
end

-- rebuild frame -> label map from what has loaded; returns indices still missing
function MenuBackdrop:_remap(name, p)
	local c = Manifest.Clips[name]
	local lastGood, firstGood = nil, nil
	local missing = {}
	for i = 1, #c._ids do
		local l = p.labels[i]
		if l and l.IsLoaded then
			lastGood = i
			firstGood = firstGood or i
		else
			table.insert(missing, i)
		end
		p.map[i] = lastGood
	end
	-- leading gap: borrow the first good frame (or frame 1 if nothing loaded at all)
	for i = 1, #c._ids do
		if p.map[i] then break end
		p.map[i] = firstGood or 1
	end
	return missing
end

-- a failed fetch (HTTP 502 etc.) is not retried by the engine; re-request anything not loaded
function MenuBackdrop:_retry(p)
	local function again(l)
		if not l.IsLoaded then
			local img = l.Image
			l.Image = ""
			l.Image = img
		end
	end
	if not p.trimmed then
		for _, l in p.labels do again(l) end
	end
	if p.grid and not p.tilesOk then
		for _, t in p.tiles do again(t) end
	end
end

-- background retry for frames / hold tiles that missed the ready window
function MenuBackdrop:_heal(name, p)
	if p.healing then return end
	p.healing = true
	task.spawn(function()
		local t0, lastRetry = os.clock(), os.clock()
		while os.clock() - t0 < HEAL_FOR and self.pools[name] == p do
			task.wait(0.25)
			local changed, pending = false, false
			for i, l in (if p.trimmed then {} else p.labels) do
				if l.IsLoaded then
					if p.map[i] ~= i then changed = true end
					if l.ZIndex == 0 and not (self.name == name and (i == self.vi or i == self.vj)) then
						l.Visible = false
						l.ImageTransparency = 0
						l.ZIndex = 1
					end
				else
					pending = true
				end
			end
			if changed and not p.trimmed then self:_remap(name, p) end
			if p.grid and not p.tilesOk and self:_tilesLoaded(p) then
				p.tilesOk = true
				-- clip already settled on its last frame: reveal the full-res still now
				if self.name == name and self.ended then
					p.grid.Visible = true
					for _, t in p.tiles do
						t.ImageTransparency = 0.99
						TweenService:Create(t, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { ImageTransparency = 0 }):Play()
					end
				else
					p.grid.Visible = false
					for _, t in p.tiles do t.ImageTransparency = 0 end
				end
			end
			if not pending and (not p.grid or p.tilesOk) then break end
			if os.clock() - lastRetry > RETRY_EVERY then
				lastRetry = os.clock()
				self:_retry(p)
			end
		end
		p.healing = false
	end)
end

function MenuBackdrop:Release(name)
	local p = self.pools[name]
	if not p or self.name == name then return end
	for _, l in p.labels do l:Destroy() end
	if p.grid then p.grid:Destroy() end
	self.pools[name] = nil
end

-- keep only what a held clip needs: its last frame (+ hold tiles)
function MenuBackdrop:_trim(name)
	local p = self.pools[name]
	if not p or p.trimmed or not p.ready then return end
	local c = Manifest.Clips[name]
	local keep = p.map[#c._ids] or #c._ids
	for i, l in p.labels do
		if i ~= keep then
			l:Destroy()
			p.labels[i] = nil
		end
	end
	for i = 1, #c._ids do p.map[i] = keep end
	p.trimmed = true
	if p.grid and not p.tilesOk then
		-- frames are gone but the full-res still is not here yet: keep fetching the tiles
		self:_heal(name, p)
	end
end

function MenuBackdrop:_overlayFade(image, dur)
	if self.fadeTween then self.fadeTween:Cancel() end
	self.Fade.Image = image
	self.Fade.ImageTransparency = 0
	self.Fade.Visible = true
	local tw = TweenService:Create(self.Fade, TweenInfo.new(dur, Enum.EasingStyle.Sine), { ImageTransparency = 1 })
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then self.Fade.Visible = false end
	end)
	self.fadeTween = tw
	tw:Play()
end

function MenuBackdrop:_drift(on)
	if self.driftTween then self.driftTween:Cancel() self.driftTween = nil end
	if on then
		self.driftTween = TweenService:Create(self.Scale,
			TweenInfo.new(20, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.06 })
		self.driftTween:Play()
	else
		self.Scale.Scale = 1
	end
end

function MenuBackdrop:_show(i, j, tj)
	local p = self.pools[self.name]
	if not p then return end
	local ready = p.ready
	local function hide(k)
		local l = k and p.labels[k]
		if l and ready then l.Visible = false end
	end
	if self.vi ~= i and self.vi ~= j then hide(self.vi) end
	if self.vj ~= i and self.vj ~= j then hide(self.vj) end
	local li, lj = p.labels[i], j and p.labels[j]
	if li then li.Visible = true li.ZIndex = 1 li.ImageTransparency = 0 end
	if lj and j ~= i then
		lj.Visible = true lj.ZIndex = 2 lj.ImageTransparency = tj
	end
	self.vi, self.vj = i, j
end

function MenuBackdrop:_hideAll(name)
	local p = name and self.pools[name]
	if not p then return end
	for _, l in p.labels do
		if p.ready then l.Visible = false else l.ImageTransparency = HIDDEN end
	end
	if p.grid and p.ready then p.grid.Visible = false end
end

function MenuBackdrop:_lastImage()
	local p = self.name and self.pools[self.name]
	local l = p and self.vi and p.labels[self.vi]
	return l and l.Image
end

function MenuBackdrop:Play(name, opts)
	local c = getClip(name)
	if not c or #c._ids == 0 then return end
	opts = opts or {}
	local fade = opts.fade or 0.5
	local prev = self:_lastImage()
	if prev and fade > 0 then self:_overlayFade(prev, fade) end
	self:_hideAll(self.name)
	self:_drift(false)

	local fromEnd = opts.fromEnd == true and not c.once
	local p = self.pools[name]
	if p and p.trimmed and not fromEnd then
		-- a full replay needs the frames back
		self.name = nil
		self:Release(name)
	end

	self.clip, self.name = c, name
	self.t, self.ended = 0, false
	self.vi, self.vj = nil, nil
	self.playing = true
	self.startedAt = os.clock()
	self.jumpEnd = fromEnd
	self:Preload(name)
	p = self.pools[name]
	if self.jumpEnd and p and p.ready then
		self.jumpEnd = false
		self:_finish(true)
		return
	end
	self:_show(1, nil, 1)
end

function MenuBackdrop:Pause() self.playing = false end
function MenuBackdrop:Resume() if self.clip and not self.ended then self.playing = true end end
function MenuBackdrop:SetSpeed(s) self.speed = math.max(0, s) end

function MenuBackdrop:Stop()
	self.playing = false
	self:_drift(false)
	self:_hideAll(self.name)
	self.clip, self.name, self.vi, self.vj = nil, nil, nil, nil
end

function MenuBackdrop:_index(f)
	local c = self.clip
	local n = #c._ids
	local i = math.floor(f) + 1
	if c.after == "loop" and not c.once then
		local a = math.clamp(c.loopFrom or 1, 1, n)
		local b = math.clamp(c.loopTo or n, a, n)
		if i > b then i = a + (i - a) % (b - a + 1) end
		return i
	end
	return math.min(i, n)
end

function MenuBackdrop:_finish(instant)
	local c = self.clip
	local name = self.name
	local p = self.pools[name]
	local n = #c._ids
	self.ended = true
	self.playing = false
	self:_show(p.map[n] or n, nil, 1)
	if p.grid and p.tilesOk then
		-- swap the 1024 frame for the full-resolution held frame
		p.grid.Visible = true
		for _, t in p.tiles do
			if instant then
				t.ImageTransparency = 0
			else
				t.ImageTransparency = 0.99
				TweenService:Create(t, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { ImageTransparency = 0 }):Play()
			end
		end
	end
	if c.once then
		self._finished:Fire(name)
	else
		self:_drift(true)
	end
	-- free every frame this clip no longer needs
	task.delay(0.8, function()
		if self.pools[name] == p then self:_trim(name) end
	end)
end

-- clip time -> frame position. Held clips decelerate over their last EASE_PART of frames
-- (quadratic ease-out down to END_SPEED) so the camera settles into the held frame instead of
-- stopping dead; the drift then eases in from rest. Deploy + looping clips run at constant speed.
local EASE_PART, END_SPEED = 0.35, 0.06
function MenuBackdrop:_frameAt(t)
	local c = self.clip
	local fps = c._fps or c.fps
	local total = #c._ids - 1
	local f = t * fps
	if c.once or c.after == "loop" then
		return f
	end
	local f0 = total * (1 - EASE_PART)
	if f <= f0 then
		return f
	end
	local R = total - f0
	local v0, v1 = fps, fps * END_SPEED
	local Td = 2 * R / (v0 + v1)
	local u = math.min(t - f0 / fps, Td)
	return math.min(total, f0 + v0 * u - (v0 - v1) * u * u / (2 * Td))
end

function MenuBackdrop:_step(dt)
	local c = self.clip
	if not c or not self.playing then return end
	if not self.Root.Visible or not self.Root:FindFirstAncestorWhichIsA("LayerCollector") then return end
	local p = self.pools[self.name]
	if not p or not p.ready then return end -- frame 1 held as a still until the clip is decoded
	if self.jumpEnd then
		self.jumpEnd = false
		self:_finish(true)
		return
	end
	local n = #c._ids
	self.t += dt * self.speed
	local f = self:_frameAt(self.t)
	if c.after ~= "loop" and f >= n - 1 - 1e-4 then
		self:_finish()
		return
	end
	local i = p.map[self:_index(f)]
	local j = p.map[self:_index(f + 1)]
	local a = f - math.floor(f)
	self:_show(i, j, 1 - a)
end

function MenuBackdrop:Destroy()
	if self._conn then self._conn:Disconnect() end
	if self.fadeTween then self.fadeTween:Cancel() end
	if self.driftTween then self.driftTween:Cancel() end
	self._finished:Destroy()
	self.Root:Destroy()
end

return MenuBackdrop
