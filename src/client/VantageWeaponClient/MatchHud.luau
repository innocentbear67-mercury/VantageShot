--[[
	VANTAGE — MatchHud (client)
	In-match overlays for the server's match phases (MatchService / MatchConfig). Shows only
	what the server published; every countdown reads Match.PhaseEnds in server time, so all
	players see the same second.
	  Prep       PREPARE FOR COMBAT panel (top centre, compact): seconds left, mode, team,
	             objective, drain bar. Spawn-zone boundary drawn as team-coloured walls;
	             "RETURN TO DEPLOYMENT ZONE" when the server pulls you back.
	  Countdown  3 · 2 · 1, one hit per second.
	  Live       MATCH LIVE banner; the HUD score strip + match clock switch on.
	  Ended      VICTORY / DEFEAT / DRAW with the final score until the server returns you to
	             the menu.
	The HUD score strip (Hud.ScoreFrame) is hidden until the match is Live.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local MatchConfig = require(Vantage:WaitForChild("MatchConfig"))
local Kit = require(script.Parent:WaitForChild("LimeKit"))

local K, F = Kit.C, Kit.F
local new, tween, text, rect, glass, spaced = Kit.new, Kit.tween, Kit.text, Kit.rect, Kit.glass, Kit.spaced
local V2 = Vector2.new
local O = UDim2.fromOffset
local S = UDim2.fromScale
local AX = Enum.TextXAlignment
local NS, KP = NumberSequence.new, NumberSequenceKeypoint.new

local player = Players.LocalPlayer
local MatchHud = {}

local hud = nil
local effects = nil
local ui = {}
local last = { Phase = nil, Count = nil, PrepTick = nil, Bounce = 0, ZoneUntil = 0 }
local zoneFolder: Folder? = nil

local function MF()
	return Vantage:FindFirstChild("Match")
end
local function attr(name)
	local m = MF()
	return m and m:GetAttribute(name)
end
local function phaseLeft(): number
	return math.max(0, (attr("PhaseEnds") or 0) - Workspace:GetServerTimeNow())
end
local function teamColor(team: string?)
	return if team == "Red" then K.Red elseif team == "Blue" then K.Blue else K.White
end
local function cue(name: string, speedMul: number?)
	local spec = MatchConfig.Sounds[name]
	if not spec then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume
	s.PlaybackSpeed = spec.Speed * (speedMul or 1)
	s.SoundGroup = effects and effects.EffectsGroup
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 8)
end

-- ─── build ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
local scales = {}
local function scaled(f)
	table.insert(scales, new("UIScale", {}, f))
	return f
end
local function fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	if vp.X < 50 then
		return
	end
	local s = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.45, 2)
	for _, sc in scales do
		sc.Scale = s
	end
end

local function build()
	local gui = new("ScreenGui", { Name = "VantageMatchHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	ui.Gui = gui

	-- ── PREPARE FOR COMBAT: compact, top centre, under the compass ──
	local prep = scaled(new("CanvasGroup", { Name = "Prep", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = O(820, 150), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, gui))
	ui.Prep = prep
	local pan = glass(prep, { W = 820, H = 150, Cut = 20, FillT = 0.32, Name = "Panel" })
	ui.PrepTeamBar = rect(pan.Root, 0, 0, 5, 150, K.White, 0, 5)
	text(pan.Root, { Position = O(28, 16), Size = O(560, 18), Text = spaced("PREPARATION PHASE   //   WEAPONS SAFE", 1), FontFace = F.MonoM, TextSize = 12, TextColor3 = K.Lime, ZIndex = 5 })
	text(pan.Root, { Position = O(26, 36), Size = O(560, 56), Text = spaced("PREPARE FOR COMBAT", 1), FontFace = F.Head, TextSize = 44, ZIndex = 5 })
	ui.PrepMode = text(pan.Root, { Position = O(28, 94), Size = O(560, 20), Text = "", FontFace = F.MonoB, TextSize = 13, ZIndex = 5 })
	ui.PrepObjective = text(pan.Root, { Position = O(28, 116), Size = O(600, 20), Text = "", FontFace = F.Label, TextSize = 14, TextColor3 = K.Muted, ZIndex = 5 })
	rect(pan.Root, 640, 22, 1, 106, K.Line, 0.8, 5)
	ui.PrepSecs = text(pan.Root, { Position = O(650, 6), Size = O(150, 100), Text = "15", FontFace = F.Head, TextSize = 76, TextColor3 = K.Lime, TextXAlignment = AX.Center, ZIndex = 5 })
	text(pan.Root, { Position = O(650, 104), Size = O(150, 16), Text = "SECONDS", FontFace = F.Mono, TextSize = 11, TextColor3 = K.Muted, TextXAlignment = AX.Center, ZIndex = 5 })
	local track = rect(pan.Root, 0, 149, 820, 1, K.Line, 0.85, 5)
	ui.PrepBar = rect(pan.Root, 0, 147, 820, 3, K.Lime, 0, 6)

	-- ── zone warning ──
	local zw = scaled(new("CanvasGroup", { Name = "ZoneWarn", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.7), Size = O(700, 70), BackgroundTransparency = 1, GroupTransparency = 1 }, gui))
	ui.ZoneWarn = zw
	local zb = new("Frame", { Size = S(1, 1), BackgroundColor3 = K.Obs, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, zw)
	new("UIStroke", { Color = K.Red, Transparency = 0.2, Thickness = 1 }, zb)
	text(zw, { Position = O(0, 8), Size = O(700, 32), Text = spaced("RETURN TO DEPLOYMENT ZONE", 1), FontFace = F.Head, TextSize = 26, TextColor3 = K.Red, TextXAlignment = AX.Center })
	text(zw, { Position = O(0, 42), Size = O(700, 18), Text = "THE AREA OPENS WHEN THE MATCH GOES LIVE", FontFace = F.Mono, TextSize = 11, TextColor3 = K.Muted, TextXAlignment = AX.Center })

	-- ── 3 · 2 · 1 ──
	local cd = scaled(new("Frame", { Name = "Countdown", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.42), Size = O(600, 420), BackgroundTransparency = 1, Visible = false }, gui))
	ui.Count = cd
	local ring = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.48), Size = O(300, 300), BackgroundTransparency = 1 }, cd)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	ui.CountRingStroke = new("UIStroke", { Color = K.Lime, Transparency = 1, Thickness = 3 }, ring)
	ui.CountRing = ring
	ui.CountDigitScale = new("UIScale", { Scale = 1 }, new("Frame", { Name = "DigitHolder", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.48), Size = O(300, 300), BackgroundTransparency = 1 }, cd))
	local holder = ui.CountDigitScale.Parent
	-- the digit is drawn at 100 and scaled (Roblox caps TextSize at 100)
	ui.CountDigit = new("TextLabel", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(150, 150), BackgroundTransparency = 1, Text = "3", FontFace = F.Head, TextSize = 100, TextColor3 = K.White, TextStrokeTransparency = 0.6, TextStrokeColor3 = K.Obs }, holder)
	new("UIScale", { Scale = 2.9 }, ui.CountDigit)
	ui.CountSub = text(cd, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = O(600, 22), Text = spaced("MATCH STARTS IN", 2), FontFace = F.MonoM, TextSize = 14, TextColor3 = K.Lime, TextXAlignment = AX.Center })

	-- ── MATCH LIVE ──
	local lv = scaled(new("CanvasGroup", { Name = "Live", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.33), Size = O(1400, 260), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, gui))
	ui.Live = lv
	local bandL = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.45), Size = O(1400, 150), BackgroundColor3 = K.Obs, BorderSizePixel = 0 }, lv)
	new("UIGradient", { Transparency = NS({ KP(0, 1), KP(0.25, 0.35), KP(0.75, 0.35), KP(1, 1) }) }, bandL)
	ui.LiveBarTop = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, -76), Size = O(0, 2), BackgroundColor3 = K.Lime, BorderSizePixel = 0 }, lv)
	ui.LiveBarBot = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 76), Size = O(0, 2), BackgroundColor3 = K.Lime, BorderSizePixel = 0 }, lv)
	ui.LiveTitle = text(lv, { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.42), Size = O(1400, 140), Text = "", FontFace = F.Head, TextSize = 120, TextColor3 = K.Lime, TextXAlignment = AX.Center })
	ui.LiveSub = text(lv, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 104), Size = O(1400, 24), Text = "", FontFace = F.MonoB, TextSize = 15, TextXAlignment = AX.Center })
	ui.LiveFlash = new("Frame", { Name = "LiveFlash", Size = S(1, 1), BackgroundColor3 = K.Lime, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0 }, gui)

	-- ── result ──
	local rs = scaled(new("CanvasGroup", { Name = "Result", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.42), Size = O(1200, 320), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, gui))
	ui.Result = rs
	local bandR = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(1200, 300), BackgroundColor3 = K.Obs, BorderSizePixel = 0 }, rs)
	new("UIGradient", { Transparency = NS({ KP(0, 1), KP(0.2, 0.25), KP(0.8, 0.25), KP(1, 1) }) }, bandR)
	text(rs, { Position = O(0, 22), Size = O(1200, 20), Text = spaced("MATCH COMPLETE", 2), FontFace = F.MonoM, TextSize = 14, TextColor3 = K.Lime, TextXAlignment = AX.Center })
	ui.ResultTitle = text(rs, { Position = O(0, 44), Size = O(1200, 130), Text = "", FontFace = F.Head, TextSize = 110, TextXAlignment = AX.Center })
	ui.ResultScore = text(rs, { Position = O(0, 184), Size = O(1200, 44), Text = "", FontFace = F.Head6, TextSize = 34, TextXAlignment = AX.Center })
	ui.ResultWhy = text(rs, { Position = O(0, 234), Size = O(1200, 20), Text = "", FontFace = F.Mono, TextSize = 13, TextColor3 = K.Muted, TextXAlignment = AX.Center })
	ui.ResultBack = text(rs, { Position = O(0, 262), Size = O(1200, 20), Text = "", FontFace = F.Mono, TextSize = 12, TextColor3 = K.Muted, TextXAlignment = AX.Center })

	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- ─── spawn-zone boundary (local parts, never replicated) ──────────────────────────────────────────────────────────────────────────────
local function clearZone()
	if zoneFolder then
		zoneFolder:Destroy()
		zoneFolder = nil
	end
end

local function drawZone(team: string)
	clearZone()
	local mn, mx = attr("Zone_" .. team), attr("ZoneMax_" .. team)
	if typeof(mn) ~= "Vector3" or typeof(mx) ~= "Vector3" then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local floorY = if root then root.Position.Y - 3 else 2.4
	local f = Instance.new("Folder")
	f.Name = "VantageSpawnZone"
	local color = teamColor(team)
	local H = 12
	local cx, cz = (mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2
	local w, d = mx.X - mn.X, mx.Y - mn.Y
	local walls = {
		{ Vector3.new(cx, floorY + H / 2, mn.Y), Vector3.new(w, H, 0.2) },
		{ Vector3.new(cx, floorY + H / 2, mx.Y), Vector3.new(w, H, 0.2) },
		{ Vector3.new(mn.X, floorY + H / 2, cz), Vector3.new(0.2, H, d) },
		{ Vector3.new(mx.X, floorY + H / 2, cz), Vector3.new(0.2, H, d) },
	}
	for _, wl in walls do
		local p = Instance.new("Part")
		p.Name = "ZoneWall"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.ForceField
		p.Color = color
		p.Transparency = 0.1
		p.Size = wl[2]
		p.Position = wl[1]
		p.Parent = f
		-- a bright base line where the wall meets the floor
		local b = Instance.new("Part")
		b.Name = "ZoneEdge"
		b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.CastShadow = true, false, false, false, false
		b.Material = Enum.Material.Neon
		b.Color = color
		b.Transparency = 0.3
		b.Size = Vector3.new(math.max(wl[2].X, 0.25), 0.15, math.max(wl[2].Z, 0.25))
		b.Position = Vector3.new(wl[1].X, floorY + 0.1, wl[1].Z)
		b.Parent = f
	end
	f.Parent = Workspace
	zoneFolder = f
end

-- ─── phase entrances ───────────────────────────────────────────────────────────────────────────────────────────────────────
local function setScoreStrip(on: boolean)
	if hud and hud.ScoreFrame then
		hud.ScoreFrame.Visible = on
	end
end

local function enterPrep()
	local team = player.Team and player.Team.Name
	local modeId = attr("Mode") or "TDM"
	local mode = MatchConfig.Modes[modeId] or MatchConfig.Modes.TDM
	ui.PrepMode.Text = mode.Name .. "   ·   " .. (if team then string.upper(team) .. " TEAM" else "") .. "   ·   " .. string.upper(attr("MapName") or MatchConfig.Map.Name)
	ui.PrepMode.TextColor3 = teamColor(team)
	ui.PrepTeamBar.BackgroundColor3 = teamColor(team)
	ui.PrepObjective.Text = MatchConfig.Objective(modeId)
	ui.Prep.Visible = true
	ui.Prep.Position = UDim2.new(0.5, 0, 0, 76)
	tween(ui.Prep, 0.6, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 96) })
	cue("Prep")
	setScoreStrip(false)
	if team then
		task.delay(0.4, drawZone, team) -- once the character has landed
	end
end

local function leavePrep()
	if ui.Prep.Visible then
		tween(ui.Prep, 0.35, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0, 80) }).Completed:Once(function()
			if last.Phase ~= "Prep" then
				ui.Prep.Visible = false
			end
		end)
	end
end

local function countBeat(n: number)
	ui.CountDigit.Text = tostring(n)
	ui.CountDigit.TextColor3 = if n == 1 then K.Lime else K.White
	ui.CountDigit.TextTransparency = 0
	ui.CountDigitScale.Scale = 1.7
	tween(ui.CountDigitScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.62, function()
		if ui.CountDigit.Text == tostring(n) then
			tween(ui.CountDigit, 0.3, { TextTransparency = 0.85 })
		end
	end)
	ui.CountRing.Size = O(170, 170)
	ui.CountRingStroke.Transparency = 0.05
	tween(ui.CountRing, 0.8, { Size = O(420, 420) }, Enum.EasingStyle.Quart)
	tween(ui.CountRingStroke, 0.8, { Transparency = 1 })
	cue("Count", 1 + (3 - n) * 0.12)
	cue("CountHit")
end

local function enterLive()
	ui.Count.Visible = false
	clearZone()
	local mode = MatchConfig.Modes[attr("Mode") or "TDM"] or MatchConfig.Modes.TDM
	ui.LiveTitle.Text = spaced("MATCH LIVE", 6)
	ui.LiveSub.Text = spaced("WEAPONS HOT   ·   FIRST TO " .. (attr("ScoreLimit") or mode.ScoreLimit), 1)
	ui.Live.Visible = true
	ui.Live.GroupTransparency = 0
	ui.Live.Position = S(0.5, 0.33)
	ui.LiveBarTop.Size, ui.LiveBarBot.Size = O(0, 2), O(0, 2)
	tween(ui.LiveBarTop, 0.5, { Size = O(1100, 2) })
	tween(ui.LiveBarBot, 0.5, { Size = O(1100, 2) })
	task.spawn(function()
		for n = 6, 2, -1 do
			ui.LiveTitle.Text = spaced("MATCH LIVE", n)
			task.wait(0.04)
		end
	end)
	ui.LiveFlash.BackgroundTransparency = 0.55
	tween(ui.LiveFlash, 0.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	cue("Live")
	cue("LivePing")
	setScoreStrip(true)
	task.delay(2.2, function()
		if last.Phase == "Live" then
			tween(ui.Live, 0.6, { GroupTransparency = 1, Position = S(0.5, 0.27) }).Completed:Once(function()
				ui.Live.Visible = false
			end)
		end
	end)
end

local function enterEnded()
	ui.Live.Visible = false
	ui.Count.Visible = false
	ui.Prep.Visible = false
	clearZone()
	-- 2026-11-18: the directed results sequence (VantageMatchResults) owns the end of the match
	if require(game:GetService("ReplicatedStorage").Vantage.MatchConfig).Results then
		return
	end
	local winner = attr("Winner") or ""
	local team = player.Team and player.Team.Name
	local title, color
	if winner == "Draw" or winner == "" then
		title, color = "DRAW", K.White
	elseif winner == team then
		title, color = "VICTORY", K.Lime
	else
		title, color = "DEFEAT", K.Red
	end
	ui.ResultTitle.Text = spaced(title, 3)
	ui.ResultTitle.TextColor3 = color
	ui.ResultScore.Text = string.format("BLUE  %d   —   %d  RED", attr("BlueScore") or 0, attr("RedScore") or 0)
	local why = attr("EndReason")
	ui.ResultWhy.Text = if why == "SCORE" then "SCORE LIMIT REACHED" elseif why == "TIME" then "TIME EXPIRED" elseif why == "FORFEIT" then "THE OTHER TEAM LEFT THE MATCH" else ""
	ui.Result.Visible = true
	ui.Result.GroupTransparency = 1
	tween(ui.Result, 0.6, { GroupTransparency = 0 })
	cue("Found")
end

local function hideAll()
	ui.Prep.Visible = false
	ui.Count.Visible = false
	ui.Live.Visible = false
	ui.Result.Visible = false
	ui.ZoneWarn.GroupTransparency = 1
	clearZone()
end

-- ─── per frame ─────────────────────────────────────────────────────────────────────────────────────────────────────────
local function step()
	local inMatch = player:GetAttribute("MatchStatus") == "Match"
	local ph = if inMatch then (attr("Phase") or "Idle") else "Idle"
	-- the overlays belong to the match on the ground: wait for the character (after the deploy)
	if ph == "Prep" and not player.Character then
		ph = "Deploy"
	end
	if ph ~= last.Phase then
		local prev = last.Phase
		last.Phase = ph
		last.Count, last.PrepTick = nil, nil
		if ph == "Prep" then
			enterPrep()
		elseif ph == "Countdown" then
			leavePrep()
			ui.Count.Visible = true
			setScoreStrip(false)
		elseif ph == "Live" then
			leavePrep()
			enterLive()
		elseif ph == "Ended" then
			enterEnded()
		elseif ph == "Intro" then
			-- operative introductions (OperativeIntro owns the screen): nothing of ours shows
			hideAll()
			setScoreStrip(false)
		else
			hideAll()
			-- out of a match the strip is back to normal (nothing else drives it)
			if prev ~= nil then
				setScoreStrip(true)
			end
		end
	end

	local left = phaseLeft()
	if ph == "Prep" then
		local secs = math.ceil(left)
		ui.PrepSecs.Text = tostring(secs)
		ui.PrepSecs.TextColor3 = if secs <= 5 then K.White else K.Lime
		ui.PrepBar.Size = O(820 * math.clamp(left / MatchConfig.PrepTime, 0, 1), 3)
		if secs <= 5 and secs > 0 and last.PrepTick ~= secs then
			last.PrepTick = secs
			cue("Tick")
			ui.PrepSecs.TextTransparency = 0.5
			tween(ui.PrepSecs, 0.3, { TextTransparency = 0 })
		end
	elseif ph == "Countdown" then
		local n = math.clamp(math.ceil(left), 1, MatchConfig.CountdownTime)
		if last.Count ~= n then
			last.Count = n
			countBeat(n)
		end
	elseif ph == "Ended" then
		ui.ResultBack.Text = string.format("RETURNING TO MENU IN %d", math.ceil(left))
	end

	-- the server pulled us back inside the spawn zone
	local bounce = player:GetAttribute("ZoneBounce") or 0
	if bounce ~= last.Bounce then
		last.Bounce = bounce
		if ph == "Prep" or ph == "Countdown" then
			if os.clock() > last.ZoneUntil then
				cue("Zone")
			end
			last.ZoneUntil = os.clock() + 1.6
		end
	end
	local want = if os.clock() < last.ZoneUntil and (ph == "Prep" or ph == "Countdown") then 0 else 1
	if ui.ZoneWarn.GroupTransparency ~= want then
		ui.ZoneWarn.GroupTransparency += (want - ui.ZoneWarn.GroupTransparency) * 0.25
		if math.abs(ui.ZoneWarn.GroupTransparency - want) < 0.02 then
			ui.ZoneWarn.GroupTransparency = want
		end
	end
end

function MatchHud.Start(hudModule, effectsModule)
	hud, effects = hudModule, effectsModule
	build()
	RunService.RenderStepped:Connect(step)
end

-- test hook (Studio playtests)
function MatchHud._state()
	return { Phase = last.Phase, Prep = ui.Prep and ui.Prep.Visible, Count = ui.Count and ui.Count.Visible, Live = ui.Live and ui.Live.Visible, Result = ui.Result and ui.Result.Visible, Zone = zoneFolder ~= nil }
end

return MatchHud
