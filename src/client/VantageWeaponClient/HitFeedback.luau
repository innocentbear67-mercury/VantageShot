--[[
	VANTAGE — HitFeedback (client)  ·  v4 "clean centre" (2026-11-16)
	The crosshair area holds exactly two things: the crosshair and this marker.
	Owned by Hud (Hud.Feedback). Two entry points:
	  :Predicted(p)  the local shot's ray matches the server's hit test (HitPredict) -> marker + tick
	                 play THIS frame, no round trip
	  :Confirm(info) the server's "Confirm" -> upgrades the marker (shield / break / head / kill /
	                 head kill) and plays only the sound the prediction has not already played
	One sound per event, all layers start on the same frame as the marker (no StartAt offsets).
	Hit sounds go through SoundService.VantageHitConfirm, which side-chains (ducks) music, ambience
	and gunfire for ~0.15 s so the tick is heard without being loud.
	Secondary info stays off the crosshair: damage numbers sit above the victim's head, shield
	feedback flares on the victim's body (Halo-style), no text near the centre.
	Settings: HitMarkers (marker), DamageIndicators (numbers). Tuning: HitFeedback.Config.
	Previous version: ServerStorage._CombatFeedbackBackup_20261116.HitFeedback
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")

local C = Color3.fromRGB
local V2 = Vector2.new
local O = UDim2.fromOffset

local SkinFX = require(game:GetService("ReplicatedStorage").Vantage.Weapons.SkinFX)
local HitFeedback = {}
HitFeedback.__index = HitFeedback

-- hit_marker (2.07 s file; the click sits 0.967 s in). TICK_REGION plays only the click, so it lands
-- on the marker's frame. The old 109382655728953 was the silent first 70 ms of this same file —
-- that is why plain hits made no sound before 2026-11-16.
local TICK_ID = "rbxassetid://133107789309462"
local TICK_REGION = NumberRange.new(0.962, 1.052)
local RING_ID = "rbxassetid://137096881472307" -- metallic ring
local SPARK_ID = "rbxassetid://9126073318" -- electric crack
local THUMP_ID = "rbxassetid://138148057831879" -- low confirm thump

local WHITE, CYAN, CYAN_HI, GOLD, RED = C(255, 255, 255), C(110, 222, 255), C(175, 244, 255), C(255, 204, 70), C(255, 54, 62)

HitFeedback.Config = {
	-- marker: four diagonal ticks around the crosshair. Len / Thick px, Radius = tick centre from
	-- screen centre, Life s, Pop = extra scale on arrival (settles in PopTime)
	-- 2026-11-17 Hypershot marker: every hit launches four white pills from far out (From px at
	-- 1080p) that snap in to the crosshair (To px) in In s, hold, and fade out by Life s. Each new hit
	-- re-launches them. Kills keep our red so a kill still reads at a glance.
	Kinds = {
		Hit = { Color = WHITE, Life = 0.3, Hold = 0.15, In = 0.08, From = 64, To = 24, Len = 14, Thick = 4 },
		Shield = { Color = C(176, 236, 255), Life = 0.3, Hold = 0.15, In = 0.08, From = 64, To = 24, Len = 14, Thick = 4 },
		Break = { Color = C(176, 236, 255), Life = 0.36, Hold = 0.2, In = 0.08, From = 72, To = 26, Len = 16, Thick = 4, Flash = CYAN_HI },
		Head = { Color = WHITE, Life = 0.34, Hold = 0.18, In = 0.08, From = 72, To = 26, Len = 16, Thick = 5 },
		HeadBreak = { Color = WHITE, Life = 0.36, Hold = 0.2, In = 0.08, From = 72, To = 26, Len = 16, Thick = 5, Flash = CYAN_HI },
		Kill = { Color = RED, Life = 0.45, Hold = 0.26, In = 0.09, From = 80, To = 28, Len = 18, Thick = 5 },
		HeadKill = { Color = RED, Life = 0.5, Hold = 0.3, In = 0.09, From = 84, To = 30, Len = 19, Thick = 5, Flash = GOLD },
	},
	Rank = { Hit = 1, Shield = 1, Break = 2, Head = 3, HeadBreak = 3, Kill = 4, HeadKill = 5 },
	PopTime = 0.06,
	MatchWindow = 0.9, -- a confirm this soon after a prediction is that prediction's confirm
	-- crosshair "bite" (px pulled in) per rank
	Bite = { 0, 0, 0, 0, 0 }, -- Hypershot: the crosshair never bites; the marker does the work
	-- the owner-made marker art (v3) is kept here; UseArt = true draws it instead of the ticks
	UseArt = false,
	Images = {
		Hit = "rbxassetid://90774000394872",
		Shield = "rbxassetid://102228696527634",
		Break = "rbxassetid://86112718734073",
		Head = "rbxassetid://112207245407271",
		Kill = "rbxassetid://132408962358190",
		HeadKill = "rbxassetid://129406414639740",
	},
	ArtSize = { Hit = 40, Shield = 42, Break = 46, Head = 46, HeadBreak = 46, Kill = 56, HeadKill = 60 },
	-- sounds: one event = one cue (layers start together). Volume ladder matches the visual ranks.
	Sounds = {
		Hit = { { Id = TICK_ID, Region = TICK_REGION, Volume = 1.0 } },
		-- 2026-11-16: the electric "ting" (SPARK_ID) layer removed everywhere at the user's request
		Shield = { { Id = TICK_ID, Region = TICK_REGION, Volume = 0.95, Speed = 1.22 } },
		Break = { { Id = THUMP_ID, Volume = 0.4, Speed = 1.35 } },
		Head = { { Id = TICK_ID, Region = TICK_REGION, Volume = 1.05, Speed = 1.3 }, { Id = RING_ID, Volume = 0.6, Speed = 1.05 } },
		HeadUpgrade = { { Id = RING_ID, Volume = 0.6, Speed = 1.05 } }, -- predicted body, server says head
		HeadBreak = { { Id = THUMP_ID, Volume = 0.4, Speed = 1.35 }, { Id = RING_ID, Volume = 0.6, Speed = 1.05 } },
		Kill = { { Id = THUMP_ID, Volume = 0.55, Speed = 0.85 } }, -- one deep confirm (+ REQ coin blip just after)
		HeadKill = { { Id = THUMP_ID, Volume = 0.6, Speed = 0.85 }, { Id = RING_ID, Volume = 0.45, Speed = 1.0 } },
	},
	PitchLift = 0.012, -- per rapid consecutive hit (max 4): keeps a spray lively without changing the cue
	-- duck music / ambience / gunfire under hit cues (side-chain compressor)
	Duck = { Threshold = -34, Ratio = 3.5, Attack = 0.004, Release = 0.16 },
	-- damage numbers above the victim's head; hits on one target within Combine s add up
	-- Hypershot numbers: one pop per hit, stacking up; crits big gold with a red CRIT tag
	Numbers = { Combine = 0.9, Life = 0.7, Size = 22, BigSize = 30, HeadOffset = 1.9, Rise = 1.1, Max = 14 },
	-- on-body flare (Highlight fill): start transparency + life per kind. Kill: none (death FX takes over)
	BodyFlash = {
		Hit = { Color = WHITE, From = 0.86, Life = 0.08 },
		Shield = { Color = CYAN, From = 0.62, Life = 0.12 },
		Break = { Color = CYAN_HI, From = 0.3, Life = 0.24 },
		Head = { Color = GOLD, From = 0.74, Life = 0.1 },
		HeadBreak = { Color = CYAN_HI, From = 0.3, Life = 0.24 },
	},
	-- small impact puff at the hit point (sparks only, no flare except on a break)
	Burst = {
		Hit = { Count = 3, Color = C(255, 245, 225) },
		Shield = { Count = 4, Color = CYAN },
		Break = { Count = 12, Color = CYAN_HI, Flare = 1.8 },
		Head = { Count = 5, Color = GOLD },
		HeadBreak = { Count = 12, Color = CYAN_HI, Flare = 1.8 },
	},
}
local CFG = HitFeedback.Config

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

-- the hit-cue bus: a child of VantageEffects (so the effects volume setting still applies)
local hitGroup: SoundGroup? = nil
local function getHitGroup(): SoundGroup
	if hitGroup and hitGroup.Parent then
		return hitGroup
	end
	local parent = SoundService:FindFirstChild("VantageEffects") or SoundService
	hitGroup = parent:FindFirstChild("VantageHitConfirm") :: SoundGroup?
	if not hitGroup then
		hitGroup = new("SoundGroup", { Name = "VantageHitConfirm", Volume = 1 }, parent)
	end
	return hitGroup :: SoundGroup
end

local DUCK_TARGETS = { VantageWeapon = true, VantageMusic = true, VantageBattleMusic = true, VantageAmbience = true }
local function attachDuck(target: Instance)
	if not DUCK_TARGETS[target.Name] or not (target:IsA("SoundGroup") or target:IsA("Sound")) then
		return
	end
	if target:FindFirstChild("VantageHitDuck") then
		return
	end
	local d = CFG.Duck
	new("CompressorSoundEffect", { Name = "VantageHitDuck", Threshold = d.Threshold, Ratio = d.Ratio, Attack = d.Attack, Release = d.Release, GainMakeup = 0, SideChain = getHitGroup() }, target)
end

-- voice pool: each sound id keeps VOICES pre-loaded Sound instances that are reused round-robin,
-- so a hit never waits on loading / seeking a fresh Sound (fresh ones started up to 280 ms late
-- under rapid fire)
local VOICES = 6
local pools = {}
local function voice(l): Sound
	local key = l.Id .. (if l.Region then "@" .. l.Region.Min else "")
	local p = pools[key]
	if not p then
		p = { i = 0 }
		local g = getHitGroup()
		for n = 1, VOICES do
			local s = Instance.new("Sound")
			s.Name = "HitVoice"
			s.SoundId = l.Id
			if l.Region then
				s.PlaybackRegionsEnabled = true
				s.PlaybackRegion = l.Region
			end
			s.SoundGroup = g
			s.Parent = g
			p[n] = s
		end
		pools[key] = p
	end
	p.i = p.i % VOICES + 1
	local s = p[p.i]
	if not s.Parent then -- the group was rebuilt: re-home the voice
		s.SoundGroup = getHitGroup()
		s.Parent = s.SoundGroup
	end
	return s
end

local function playLayers(layers, pitch: number?)
	if not layers then
		return
	end
	for _, l in layers do
		local s = voice(l)
		s.Volume = l.Volume or 0.5
		s.PlaybackSpeed = (l.Speed or 1) * (pitch or 1)
		if s.IsPlaying then
			s:Stop()
		end
		s:Play()
	end
end
HitFeedback.PlayLayers = playLayers

function HitFeedback.new(hud, gui: ScreenGui)
	local self = setmetatable({}, HitFeedback)
	self.Hud = hud
	self.Gui = gui

	local root = new("Frame", { Name = "HitMarkerV4", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = O(0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, gui)
	self.Root = root
	self.Scale = new("UIScale", { Scale = 1 }, root)
	self.Ticks = {}
	for _, a in { 45, 135, 225, 315 } do
		local t = new("Frame", { AnchorPoint = V2(0.5, 0.5), Rotation = a, BorderSizePixel = 0, ZIndex = 21 }, root)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, t)
		local st = new("UIStroke", { Color = C(12, 16, 34), Thickness = 1.5, Transparency = 0.15 }, t)
		table.insert(self.Ticks, { Frame = t, Stroke = st, Angle = math.rad(a) })
	end
	-- headshot diamond (centre, small) and a single thin flash ring (shield break / head kill)
	self.Diamond = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(5, 5), Rotation = 45, BorderSizePixel = 0, Visible = false, ZIndex = 22 }, root)
	new("UIStroke", { Color = C(0, 0, 0), Thickness = 1, Transparency = 0.5 }, self.Diamond)
	self.Ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = O(24, 24), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, root)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.Ring)
	self.RingStroke = new("UIStroke", { Thickness = 1.5 }, self.Ring)
	self.Image = new("ImageLabel", { AnchorPoint = V2(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 22, ScaleType = Enum.ScaleType.Fit }, root)

	self.Kind = "Hit"
	self.Start, self.Until, self.PopAt, self.PopAmp = 0, 0, 0, 0
	self.Streak, self.LastHitAt = 0, 0
	self.LastSoundAt, self.LastSoundRank = 0, 0
	self.Pending = {}
	self.Numbers = {}
	self.NumRng = Random.new()
	self.Flashes = {}

	local att = Instance.new("Attachment")
	att.Name = "VantageHitPuff"
	att.Parent = Workspace.Terrain
	self.PuffAtt = att
	self.Burst = new("ParticleEmitter", {
		Enabled = false,
		LightEmission = 1,
		LightInfluence = 0,
		Lifetime = NumberRange.new(0.1, 0.18),
		Speed = NumberRange.new(10, 20),
		SpreadAngle = V2(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) }),
		Drag = 8,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	}, att)
	self.Flare = new("ParticleEmitter", {
		Enabled = false,
		LightEmission = 1,
		LightInfluence = 0,
		Lifetime = NumberRange.new(0.08, 0.1),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
	}, att)

	-- ducking: attach side-chain compressors to music / ambience / gunfire as they appear
	task.spawn(function()
		SoundService:WaitForChild("VantageEffects", 15)
		getHitGroup()
		for _, d in SoundService:GetDescendants() do
			attachDuck(d)
		end
		SoundService.DescendantAdded:Connect(function(d)
			task.defer(attachDuck, d)
		end)
	end)

	-- build the voice pools and preload them so the first hit of a session is never late or silent
	task.spawn(function()
		SoundService:WaitForChild("VantageEffects", 15)
		local list = {}
		for _, layers in CFG.Sounds do
			for _, l in layers do
				local s = voice(l)
				local key = l.Id .. (if l.Region then "@" .. l.Region.Min else "")
				for n = 1, VOICES do
					table.insert(list, pools[key][n])
				end
				local _ = s
			end
		end
		if CFG.UseArt then
			for _, id in CFG.Images do
				table.insert(list, new("Decal", { Texture = id }))
			end
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
	return self
end

function HitFeedback:_setting(name: string): boolean
	return self.Hud:_setting(name, true)
end

-- one cue per event: a weaker-or-equal cue in the same frame (shotgun pellets, a confirm and a
-- prediction landing together) is dropped; separate shots always get their own cue
function HitFeedback:_cue(name: string, rank: number)
	local now = os.clock()
	if now - self.LastSoundAt < 0.012 and rank <= self.LastSoundRank then
		return
	end
	self.LastSoundAt, self.LastSoundRank = now, rank
	playLayers(CFG.Sounds[name], 1 + self.Streak * CFG.PitchLift)
end

-- show / upgrade the marker. upgrade = the server confirming a marker already on screen
function HitFeedback:_show(kind: string, upgrade: boolean)
	local now = os.clock()
	local rank = CFG.Rank[kind] or 1
	local live = self.Root.Visible and now < self.Until
	if not upgrade then
		self.Streak = if now - self.LastHitAt < 0.25 then math.min(self.Streak + 1, 4) else 0
		self.LastHitAt = now
	end
	-- never downgrade a stronger marker still showing
	if live and rank < (CFG.Rank[self.Kind] or 1) then
		return
	end
	if not self:_setting("HitMarkers") then
		return
	end
	local k = CFG.Kinds[kind]
	-- a confirm of the same marker keeps its clock (no second pop); anything else restarts it
	local same = upgrade and live and kind == self.Kind
	self.Kind = kind
	if not same then
		self.Start = now
		self.PopAt = now
		self.PopAmp = k.Pop or 0
	end
	self.Until = self.Start + k.Life
	for _, t in self.Ticks do
		t.Frame.BackgroundColor3 = k.Color
		t.Frame.Visible = not CFG.UseArt
	end
	self.Diamond.Visible = k.Diamond ~= nil and not CFG.UseArt
	if k.Diamond then
		self.Diamond.BackgroundColor3 = k.Diamond
	end
	self.Ring.Visible = k.Flash ~= nil
	if k.Flash then
		self.RingStroke.Color = k.Flash
	end
	self.Image.Visible = CFG.UseArt
	if CFG.UseArt then
		self.Image.Image = CFG.Images[kind] or ""
	end
	self.Root.Visible = true
	local bite = CFG.Bite[rank] or 1
	self.Hud.Kick = math.max(-4, math.min(self.Hud.Kick or 0, 0) - bite)
end

function HitFeedback:Predicted(p)
	local kind = if p.Head then "Head" elseif p.Shielded then "Shield" else "Hit"
	table.insert(self.Pending, { At = os.clock(), Kind = kind })
	self:_show(kind, false)
	self:_cue(kind, CFG.Rank[kind])
end

local function takePending(self): string?
	local now = os.clock()
	while self.Pending[1] and now - self.Pending[1].At > CFG.MatchWindow do
		table.remove(self.Pending, 1)
	end
	local p = table.remove(self.Pending, 1)
	return p and p.Kind
end

-- server confirm: info = { Damage, Headshot, Killed, Position, Victim?, ShieldDamage, ShieldBroken, Melee, Weapon }
function HitFeedback:Confirm(info, _effects, _weaponId: string?)
	local predicted = if info.Melee then nil else takePending(self)
	local kind
	if info.Killed then
		kind = if info.Headshot then "HeadKill" else "Kill"
	elseif info.Headshot and info.ShieldBroken then
		kind = "HeadBreak"
	elseif info.Headshot then
		kind = "Head"
	elseif info.ShieldBroken then
		kind = "Break"
	elseif (info.ShieldDamage or 0) > 0 then
		kind = "Shield"
	else
		kind = "Hit"
	end
	self:_show(kind, predicted ~= nil)

	-- sound: only what the prediction has not already played
	local rank = CFG.Rank[kind]
	if info.Killed then
		self:_cue(kind, rank)
	elseif not predicted then
		self:_cue(kind, rank)
	elseif kind == "Head" and predicted ~= "Head" then
		self:_cue("HeadUpgrade", rank)
	elseif kind == "Break" then
		self:_cue("Break", rank)
	elseif kind == "HeadBreak" then
		self:_cue(if predicted == "Head" then "Break" else "HeadBreak", rank)
	end

	local victim = if typeof(info.Victim) == "Instance" and info.Victim:IsA("Model") then info.Victim else nil
	self:_number(info, kind, victim)
	self:_puff(info, kind)
	if not info.Melee and typeof(info.Position) == "Vector3" then
		SkinFX.HitAccent(info.Position) -- skin hit accent (shot overhaul stage 4), hollow + brief
	end
	if victim and not info.Killed then
		self:_flash(victim, kind)
	end
end

function HitFeedback:_puff(info, kind: string)
	local b = CFG.Burst[kind]
	if not b or typeof(info.Position) ~= "Vector3" then
		return
	end
	self.PuffAtt.WorldPosition = info.Position
	self.Burst.Color = ColorSequence.new(C(255, 255, 255), b.Color)
	self.Burst:Emit(b.Count)
	if b.Flare then
		self.Flare.Color = ColorSequence.new(b.Color)
		self.Flare.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, b.Flare), NumberSequenceKeypoint.new(1, b.Flare * 0.15) })
		self.Flare:Emit(1)
	end
end

local function headPos(victim: Model?, fallback: Vector3?): Vector3?
	if victim then
		local head = victim:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head.Position + Vector3.new(0, CFG.Numbers.HeadOffset, 0)
		end
		local ok, cf = pcall(victim.GetPivot, victim)
		if ok then
			return cf.Position + Vector3.new(0, 3.4, 0)
		end
	end
	return if fallback then fallback + Vector3.new(0, 2.2, 0) else nil
end

local NUM_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
function HitFeedback:_number(info, kind: string, victim: Model?)
	if not self:_setting("DamageIndicators") then
		return
	end
	local base = headPos(victim, if typeof(info.Position) == "Vector3" then info.Position else nil)
	if not base then
		return
	end
	local now = os.clock()
	-- Hypershot: one number per hit, stacking upward (no running total)
	local rec
	for _, r in self.Numbers do
		if not r.Gui.Enabled then
			rec = r
			break
		end
	end
	if not rec then
		if #self.Numbers >= CFG.Numbers.Max then
			for _, r in self.Numbers do
				if not rec or r.Born < rec.Born then
					rec = r
				end
			end
		else
			local att = Instance.new("Attachment")
			att.Parent = Workspace.Terrain
			local bb = new("BillboardGui", { Size = O(140, 60), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 600, Adornee = att, ResetOnSpawn = false }, self.Gui.Parent or self.Gui) -- BillboardGuis do not draw inside a ScreenGui
			local l = new("TextLabel", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, FontFace = NUM_FONT, TextSize = CFG.Numbers.Size, TextColor3 = WHITE, Text = "" }, bb)
			local ls = new("UIStroke", { Color = C(12, 16, 34), Thickness = 2.2 }, l)
			local tag = new("TextLabel", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 1, -32), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, FontFace = NUM_FONT, TextSize = 17, TextColor3 = RED, Text = "CRIT", Visible = false }, bb)
			local ts = new("UIStroke", { Color = WHITE, Thickness = 2 }, tag)
			rec = { Att = att, Gui = bb, Label = l, LStroke = ls, Tag = tag, TStroke = ts, Born = 0, Last = 0 }
			table.insert(self.Numbers, rec)
		end
	end
	rec.Victim = victim
	rec.Base = base
	rec.Born = now
	rec.Last = now
	rec.Head = info.Headshot == true
	rec.Killed = info.Killed == true
	rec.Jitter = Vector2.new(self.NumRng:NextNumber(-0.75, 0.75), self.NumRng:NextNumber(-0.1, 0.3))
	rec.Label.Text = tostring(math.floor((info.Damage or 0) + 0.5))
	rec.Label.TextColor3 = if rec.Killed then RED elseif rec.Head then GOLD elseif kind == "Shield" or kind == "Break" then CYAN_HI else WHITE
	rec.Tag.Visible = rec.Head
	rec.Gui.Enabled = true
end

function HitFeedback:_flash(model: Model, kind: string)
	local f = CFG.BodyFlash[kind]
	if not f then
		return
	end
	local hl = self.Flashes[model]
	if not hl or not hl.Parent then
		hl = Instance.new("Highlight")
		hl.Name = "VantageHitFlash"
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.OutlineTransparency = 1
		hl.FillTransparency = 1
		hl.Adornee = model
		hl.Parent = model
		self.Flashes[model] = hl
		model.Destroying:Once(function()
			self.Flashes[model] = nil
		end)
	end
	-- a weaker flash never overrides a stronger one still fading (a break flare outlives a tick)
	local now = os.clock()
	local liveUntil = (hl:GetAttribute("At") or 0) + (hl:GetAttribute("Life") or 0)
	if hl.Enabled and now < liveUntil and f.From > (hl:GetAttribute("From") or 1) then
		return
	end
	hl.FillColor = f.Color
	hl:SetAttribute("At", now)
	hl:SetAttribute("Life", f.Life)
	hl:SetAttribute("From", f.From)
	hl.FillTransparency = f.From
	hl.Enabled = true
end

function HitFeedback:Step(_dt: number, now: number)
	-- marker
	if self.Root.Visible then
		if now >= self.Until then
			self.Root.Visible = false
		else
			local k = CFG.Kinds[self.Kind]
			local life = math.max(0.01, self.Until - self.Start)
			local a = (now - self.Start) / life
			local px = math.clamp(Workspace.CurrentCamera.ViewportSize.Y / 1080, 0.7, 1.6)
			local t = now - self.Start
			local e = 1 - (1 - math.clamp(t / (k.In or 0.08), 0, 1)) ^ 3
			local r = ((k.From or 64) + ((k.To or 24) - (k.From or 64)) * e) * px
			local hold = k.Hold or 0.15
			local fade = math.clamp((t - hold) / math.max(0.01, k.Life - hold), 0, 1)
			self.Scale.Scale = 1
			for _, tk in self.Ticks do
				tk.Frame.Size = O(math.round(k.Len * px), math.max(2, math.round(k.Thick * px)))
				tk.Frame.Position = O(math.cos(tk.Angle) * r, math.sin(tk.Angle) * r)
				tk.Frame.BackgroundTransparency = fade
				if tk.Stroke then
					tk.Stroke.Transparency = 0.15 + 0.85 * fade
				end
			end
			if self.Diamond.Visible then
				self.Diamond.BackgroundTransparency = fade
			end
			if self.Ring.Visible then
				-- one quick outward flash, gone in 0.16 s
				local ra = math.clamp((now - self.Start) / 0.16, 0, 1)
				local s = 22 + ra * 18
				self.Ring.Size = O(s, s)
				self.RingStroke.Transparency = 0.15 + 0.85 * ra
			end
			if self.Image.Visible then
				local sz = (CFG.ArtSize[self.Kind] or 40) * (1 + a * 0.06)
				self.Image.Size = O(sz, sz)
				self.Image.ImageTransparency = fade
			end
		end
	end
	-- damage numbers: one per hit, pop in, float up off the head, fade
	local camCF = Workspace.CurrentCamera.CFrame
	for _, rec in self.Numbers do
		if rec.Gui.Enabled then
			local age = now - rec.Born
			local life = CFG.Numbers.Life
			if age >= life then
				rec.Gui.Enabled = false
			else
				local base = rec.Base
				if rec.Victim and rec.Victim.Parent then
					base = headPos(rec.Victim, nil) or base
				end
				local j = rec.Jitter or Vector2.zero
				local rise = (math.min(age / life, 1) ^ 0.6) * CFG.Numbers.Rise
				rec.Att.WorldPosition = base + camCF.RightVector * j.X + Vector3.new(0, j.Y + rise, 0)
				local pop = if age < 0.09 then 1 + (1 - age / 0.09) * 0.35 else 1
				local size = if rec.Head or rec.Killed then CFG.Numbers.BigSize else CFG.Numbers.Size
				rec.Label.TextSize = math.floor(size * pop + 0.5)
				rec.Tag.TextSize = math.floor(17 * pop + 0.5)
				local f = math.clamp((age - life * 0.6) / (life * 0.4), 0, 1)
				rec.Label.TextTransparency = f
				rec.LStroke.Transparency = f
				rec.Tag.TextTransparency = f
				rec.TStroke.Transparency = f
			end
		end
	end
	-- body flares
	for _, hl in self.Flashes do
		if hl.Enabled then
			local at, life, from = hl:GetAttribute("At") or 0, hl:GetAttribute("Life") or 0.08, hl:GetAttribute("From") or 0.8
			local a = (now - at) / life
			if a >= 1 then
				hl.Enabled = false
				hl.FillTransparency = 1
			else
				hl.FillTransparency = from + (1 - from) * a
			end
		end
	end
end

return HitFeedback
