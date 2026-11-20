--[[
	VANTAGE — Ability client: the GRAPPLE
	Aim at solid map geometry, press E: the hook flies out, bites, and the cable pulls you in.
	Move keys bend the path, the camera stays free, E again or Jump lets go (momentum kept).
	It also lets go by itself on arrival, after MaxTime, when something solid cuts the cable,
	when you stop moving against a wall, when the anchor is destroyed, and on death.

	Everything is predicted locally (hook, cable and pull start on the key press); AbilityServer
	checks the same shot with its own ray and can refuse it ("GrappleReject"), in which case the
	cable lets go at once. Other players' hooks and cables are drawn from the server's relay.
	Tuning: ReplicatedStorage.Vantage.Abilities.AbilityConfig. Effects: GrappleFX (child module).
	The visor HUD draws the ability slot; it reads the "VantageAbilityUsed" player attribute.

	The DROPSHIP (VantageAircraftClient.AircraftRuntime, tuning Vantage.Aircraft.AircraftConfig):
	if a free hook under the flying dropship is under the crosshair, E grapples IT instead of the
	map: the hook flies to the moving hook point, bites, the cable reels you up (the same pull,
	relative to the aircraft), then you swing into a rope hang beneath it. Space or E lets go
	(part of the aircraft's speed kept, grapple ready again in ~1 s). The server checks the shot
	(AircraftService) and can refuse it, or detach you (flight end, drop point, leash).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("Abilities"):WaitForChild("AbilityConfig"))
local remote = Vantage:WaitForChild("Remotes"):WaitForChild("Ability") :: RemoteEvent
local MovementController = require(script.Parent:WaitForChild("VantageMovementClient"):WaitForChild("MovementController"))
local GrappleFX = require(script:WaitForChild("GrappleFX"))
-- first-person arm animation (Viewmodel reads it): the left arm reaches out at the hook
local Feed = require(Vantage:WaitForChild("Abilities"):WaitForChild("GrappleFeed"))
local function feedFire(now: number, target: Vector3?, track: any?, endAt: number?)
	Feed.FiredAt, Feed.Target, Feed.Track, Feed.BiteAt, Feed.EndAt = now, target, track, nil, endAt
end
local AircraftRuntime = require(script.Parent:WaitForChild("VantageAircraftClient"):WaitForChild("AircraftRuntime")).Start()
local AircraftConfig = require(Vantage:WaitForChild("Aircraft"):WaitForChild("AircraftConfig"))

local player = Players.LocalPlayer
local G = Config.Abilities.Grapple

-- the visor HUD waits for this ScreenGui and takes its "Slots" frame; the slot itself is the visor's
local gui = Instance.new("ScreenGui")
gui.Name = "VantageAbilities"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1
gui.Enabled = false
local slotsFrame = Instance.new("Frame")
slotsFrame.Name = "Slots"
slotsFrame.BackgroundTransparency = 1
slotsFrame.Size = UDim2.fromOffset(0, 0)
slotsFrame.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local readyAt = 0
-- 2026-11-17: the equipped Grappling Hook sets range / cooldown / charges (mirrors AbilityServer)
local EquipCatalog = require(Vantage:WaitForChild("Equipment"):WaitForChild("EquipmentCatalog"))
-- 2026-11-19: the cooldown counts from LET-GO (mirrors AbilityServer); every hook has one charge (the HUD feed keeps
-- an empty ChargeTimes). Kraken's Relay: a real let-go opens a free grapple for Params.Window seconds, once.
local charges: { number } = {}
local relayUntil = 0
local function hookStats()
	return EquipCatalog.HookStats(player)
end
local function hookProfile()
	return EquipCatalog.HookProfile(player)
end
local function isReady(now: number): boolean
	return now >= readyAt or now <= relayUntil
end
-- a shot is out: the cooldown waits for the let-go. Returns whether it used the Relay window.
local function startCooldown(now: number): boolean
	local relayed = now < readyAt and now <= relayUntil
	relayUntil = 0
	readyAt = math.huge
	return relayed
end
-- 2026-11-18 hook abilities (EquipmentCatalog Ability.Id / Params; server side in AbilityServer):
--   Hunter (Harpoon)    an enemy under the crosshair is hooked instead of the map: pulled to them, they are marked
--   Perch (Mag-Anchor)  arriving at a wall holds you there for Params.Time (jump / E lets go); you can shoot
--   Swing (Lotus)       pendulum round an anchor above you (MovementController, cfg.Swing), jump / E flings off
--   Blink (Starfall)    the beam bites at once and you are zipped straight to the point
local function hookAbility()
	return EquipCatalog.AbilityOf(player, "Hook")
end
local swingCfg = nil
local function getSwingCfg(AP)
	swingCfg = table.clone(hookProfile())
	swingCfg.Swing = true
	swingCfg.ReelSpeed, swingCfg.MinLength = AP.ReelSpeed or 7, AP.MinLength or 14
	return swingCfg
end
local function teamKey(m: Model?): string?
	if not m then
		return nil
	end
	local p = Players:GetPlayerFromCharacter(m)
	if p then
		return if p.Team and not p.Neutral then p.Team.Name else nil
	end
	local t = m:GetAttribute("Team")
	return if type(t) == "string" then t else nil
end
local function hostile(m: Model): boolean
	local a, b = teamKey(player.Character), teamKey(m)
	return not (a ~= nil and b ~= nil and a == b)
end

-- the grapple in flight / pulling: { Shot, Point, Part, PartCFrame, Phase = "Fly" | "Pull", FiredAt, PullAt, BlockedSince }
local live = nil :: any

-- ── what can be grappled ──────────────────────────────────────────────────────────────────
local ignoreCache, ignoreAt = nil, 0
local function ignoreList(): { Instance }
	local now = os.clock()
	if ignoreCache and now - ignoreAt < 0.5 then
		return table.clone(ignoreCache)
	end
	local list = { Workspace.CurrentCamera }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, tag in { "VantageDummy", "VantageBot" } do
		for _, m in CollectionService:GetTagged(tag) do
			table.insert(list, m)
		end
	end
	for _, name in { "VantageGrappleFX", "VantageAircraftFX", "VantageShieldFX", "VantageIntroStandIns", "VantageIntroFX", "VantageSpawnZone" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	ignoreCache, ignoreAt = list, now
	return table.clone(list)
end

-- first SOLID thing along a ray: characters are never targets, non-colliding parts are stepped through
local function solidHit(origin: Vector3, dir: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = ignoreList()
	params.FilterDescendantsInstances = ignore
	for _ = 1, 6 do
		local hit = Workspace:Raycast(origin, dir, params)
		if not hit then
			return nil
		end
		if hit.Instance.CanCollide and not hit.Instance:GetAttribute("NoGrapple") then
			return hit
		end
		table.insert(ignore, hit.Instance)
		params.FilterDescendantsInstances = ignore
	end
	return nil
end

-- Hunter: an enemy (alive, hostile) close to the crosshair, in range, with no map geometry in between
local function hunterTarget(cam: CFrame, range: number, radius: number): (Model?, number?)
	local me = player.Character
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and c ~= me and hostile(c) then
			table.insert(list, c)
		end
	end
	for _, tag in { "VantageDummy", "VantageBot" } do
		for _, c in CollectionService:GetTagged(tag) do
			if c:IsA("Model") and hostile(c) then
				table.insert(list, c)
			end
		end
	end
	if #list == 0 or not me then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local res = Workspace:Spherecast(cam.Position, radius, cam.LookVector * (range + 6), params)
	if not res then
		return nil
	end
	local m = res.Instance:FindFirstAncestorWhichIsA("Model")
	while m and not m:FindFirstChildOfClass("Humanoid") do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	local h = m and m:FindFirstChildOfClass("Humanoid")
	local r = m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not m or not h or h.Health <= 0 or not r then
		return nil
	end
	local head = me:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else (me:GetPivot() * CFrame.new(0, 1.5, 0)).Position
	local dist = (r.Position - eye).Magnitude
	if dist > range or dist < G.MinRange then
		return nil
	end
	return m, dist
end

local function eyeOf(character: Model): Vector3
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return (character:GetPivot() * CFrame.new(0, 1.5, 0)).Position
end

-- Mag-Anchor's Magnet: a near miss bends onto the closest valid surface (rings of rays out to Params.Magnet degrees,
-- no further than Params.MagnetReach studs from the aim line); the server checks the new point like any other
local function magnetHit(cam: CFrame, range: number, AP): RaycastResult?
	local character = player.Character
	if not character then
		return nil
	end
	local eye = eyeOf(character)
	local maxA = math.rad(AP.Magnet or 7)
	for ring = 1, 3 do
		local ang = maxA * ring / 3
		local best, bestD = nil, math.huge
		for k = 0, 7 do
			local dir = (cam * CFrame.Angles(0, 0, k * math.pi / 4) * CFrame.Angles(ang, 0, 0)).LookVector
			local hit = solidHit(cam.Position, dir * (range + 4))
			if hit then
				local v = hit.Position - cam.Position
				local perp = (v - cam.LookVector * v:Dot(cam.LookVector)).Magnitude
				local d = (hit.Position - eye).Magnitude
				if d >= G.MinRange and d <= range and perp <= (AP.MagnetReach or 10) and perp < bestD then
					local los = solidHit(eye, (hit.Position - eye).Unit * (d + 2))
					if los and (los.Position - hit.Position).Magnitude < 2.5 then
						best, bestD = hit, perp
					end
				end
			end
		end
		if best then
			return best
		end
	end
	return nil
end

-- ── letting go ────────────────────────────────────────────────────────────────────────────
local function release(kind: string, tellServer: boolean)
	local g = live
	if not g then
		return
	end
	live = nil
	g.Shot:Release()
	if Feed.EndAt == nil then
		Feed.EndAt = os.clock() -- the arm comes back with the cable
	end
	local movement = MovementController.Current
	if g.Aircraft then
		if movement then
			if movement:IsHanging() then
				movement:HangEnd(AircraftConfig.Release)
			elseif movement:IsGrappling() then
				movement:GrappleEnd(kind)
			end
		end
		AircraftRuntime.SetLocalRide(nil)
		readyAt = os.clock() + AircraftConfig.Release.Cooldown -- free to hook a building on the way down
		if tellServer then
			remote:FireServer("AircraftRelease")
		end
		return
	end
	if movement and movement:IsPerched() then
		movement:PerchEnd(kind == "Release")
	end
	if movement and movement:IsGrappling() then
		movement:GrappleEnd(kind)
	end
	-- the cooldown starts now (a refused shot: the server's "GrappleReject" sets it right after this)
	local now = os.clock()
	readyAt = now + hookStats().Cooldown
	if g.Ability == "Relay" and not g.Relayed and kind ~= "Cancel" and kind ~= "Dead" and g.PullStartedAt
		and now - g.PullStartedAt >= ((g.AP and g.AP.MinPull) or 0.4) then
		relayUntil = now + ((g.AP and g.AP.Window) or 1.5)
		GrappleFX.Cue("RelayReady", player.Character)
	end
	if tellServer then
		remote:FireServer("GrappleEnd")
	end
end

-- ── firing ────────────────────────────────────────────────────────────────────────────────
local function use()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not gui.Enabled then
		return
	end
	if (player.Team == nil and not player:GetAttribute("InTutorial")) or character:GetAttribute("VantageHolstered") then
		return -- lobby: the grapple is disabled (AbilityServer refuses it too)
	end
	if live then
		if live.Phase == "Pull" or live.Phase == "Hang" or live.Phase == "Perch" then
			release("Release", true) -- E again lets go
		end
		return
	end
	local now = os.clock()
	local movement = MovementController.Current
	if not isReady(now) or not movement then
		return
	end
	-- the dropship first: a free hook under the crosshair
	local air = AircraftRuntime.GetTarget()
	if air then
		local track = AircraftRuntime.Tracker(air.Flight, air.Hook)
		local shot = GrappleFX.FireTracked(character, track, true, AircraftConfig.Grapple.ProjectileSpeed)
		if shot then
			relayUntil = 0
			readyAt = now + hookStats().Cooldown -- this hook's own cooldown (was the base for every hook)
			live = {
				Aircraft = true, Flight = air.Flight, Hook = air.Hook, Track = track, Shot = shot,
				Phase = "Fly", FiredAt = now, PullAt = now + air.Distance / (AircraftConfig.Grapple.ProjectileSpeed or G.ProjectileSpeed), BlockedSince = nil,
			}
			AircraftRuntime.SetLocalRide("Pull", air.Hook)
			feedFire(now, nil, function()
				return (track())
			end, nil)
			player:SetAttribute("VantageAbilityUsed", "Grapple@" .. string.format("%.3f", now))
			remote:FireServer("Use", "GrappleAircraft", { Flight = air.Flight, Hook = air.Hook, Time = AircraftRuntime.ServerTime() })
			return
		end
	end
	local hs = hookStats()
	local cam = Workspace.CurrentCamera.CFrame
	local ability, AP = hookAbility()
	if ability == "Hunter" then
		local target, tdist = hunterTarget(cam, hs.Range, AP.Radius or 3)
		local troot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local eye0 = eyeOf(character)
		if target and troot and not solidHit(eye0, troot.Position - eye0) then
			local function track(): (Vector3?, Vector3)
				local h = target:FindFirstChildOfClass("Humanoid")
				if troot.Parent and target.Parent and h and h.Health > 0 then
					return troot.Position, troot.AssemblyLinearVelocity
				end
				return nil, Vector3.zero
			end
			local shot = GrappleFX.FireTracked(character, track, true, G.ProjectileSpeed)
			if shot then
				live = {
					Target = target, Track = track, Shot = shot, Phase = "Fly", FiredAt = now, Ability = ability, AP = AP,
					PullAt = now + (tdist or 0) / G.ProjectileSpeed, Arrive = AP.ArriveDistance or 7,
				}
				live.Relayed = startCooldown(now)
				feedFire(now, nil, function()
					return (track())
				end, nil)
				player:SetAttribute("VantageAbilityUsed", "Grapple@" .. string.format("%.3f", now))
				remote:FireServer("Use", "GrappleTarget", target)
				return
			end
		end
	end
	local hit = solidHit(cam.Position, cam.LookVector * (hs.Range + 4))
	local eye = eyeOf(character)
	local valid = false
	if hit then
		local dist = (hit.Position - eye).Magnitude
		if dist >= G.MinRange and dist <= hs.Range then
			-- nothing solid between YOU (not just the camera) and the point
			local los = solidHit(eye, (hit.Position - eye).Unit * (dist + 2))
			valid = los ~= nil and (los.Position - hit.Position).Magnitude < 2.5
		end
	end
	local magnet = false
	if (not valid or not hit) and AP.Magnet then
		local mh = magnetHit(cam, hs.Range, AP)
		if mh then
			hit, valid, magnet = mh, true, true
		end
	end
	if not valid or not hit then
		-- nothing to bite: the hook goes out a short way and comes back (a Relay window stays open)
		if now > relayUntil then
			readyAt = now + G.MissCooldown
		end
		GrappleFX.Miss(character, cam.Position + cam.LookVector * 38, true)
		-- the arm still punches out with the shot and comes back as the hook does
		feedFire(now, cam.Position + cam.LookVector * 38, nil, now + math.max(0.24, 38 / G.ProjectileSpeed))
		return
	end
	local relayed = startCooldown(now)
	if magnet then
		GrappleFX.Cue("Magnet", character, hit.Position, hit.Normal)
	end
	local part = hit.Instance
	live = {
		Relayed = relayed,
		Shot = GrappleFX.Fire(character, hit.Position, true, hit.Normal),
		Point = hit.Position, Part = part, PartCFrame = part.CFrame, Normal = hit.Normal, Ability = ability, AP = AP,
		Phase = "Fly", FiredAt = now,
		-- Starfall's beam of light bites at once
		PullAt = now + (if ability == "Blink" then 0.06 else (hit.Position - eye).Magnitude / G.ProjectileSpeed),
		BlockedSince = nil,
	}
	feedFire(now, hit.Position, nil, nil)
	player:SetAttribute("VantageAbilityUsed", "Grapple@" .. string.format("%.3f", now)) -- visor HUD slot + cooldown
	remote:FireServer("Use", "Grapple", hit.Position)
end

RunService.Heartbeat:Connect(function()
	local g = live
	if not g then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local movement = MovementController.Current
	if not character or not humanoid or humanoid.Health <= 0 or not movement then
		release("Dead", true)
		return
	end
	local now = os.clock()
	if g.Aircraft then
		-- ── on the dropship ──
		local point = g.Track()
		if not point then
			release("Lost", true) -- the flight is over
			return
		end
		if AircraftRuntime.PastDrop(g.Flight) then
			release("Drop", true) -- it is about to climb out of the map: everyone off
			return
		end
		if g.Phase == "Fly" then
			if now >= g.PullAt then
				g.Phase = "Pull"
				g.PullStartedAt = now
				g.Shot:Attach()
				Feed.BiteAt = now
				movement:GrappleStart(point, AircraftConfig.Grapple, g.Track)
				AircraftRuntime.OnBite() -- third person for the ride (back to first person on letting go)
			end
			return
		end
		if g.Phase == "Pull" then
			local dist, stuck = movement:GrappleStatus()
			if not movement:IsGrappling() then
				release("Lost", true)
			elseif dist <= AircraftConfig.Hang.Length + 2.5 then
				-- reached the hook: swing into the hang (no snap; the rope eases in)
				g.Phase = "Hang"
				g.HangStartedAt = now
				movement:HangStart(g.Track, AircraftConfig.Hang)
				AircraftRuntime.SetLocalRide("Hang", g.Hook)
				remote:FireServer("AircraftHang")
			elseif movement.Input.JumpPressedAt > g.PullStartedAt then
				release("Release", true)
			elseif now - g.PullStartedAt > AircraftConfig.Grapple.MaxPullTime or stuck then
				release("Release", true)
			else
				local eye = eyeOf(character)
				local los = solidHit(eye, point - eye)
				if los and (los.Position - point).Magnitude > 3 then
					g.BlockedSince = g.BlockedSince or now
					if now - g.BlockedSince > 0.9 then
						release("Release", true)
					end
				else
					g.BlockedSince = nil
				end
			end
			return
		end
		-- hanging: Space (or E, in use()) lets go
		if not movement:IsHanging() then
			release("Lost", true)
		elseif movement.Input.JumpPressedAt > g.HangStartedAt then
			release("Release", true)
		end
		return
	end
	if g.Target then
		-- ── Hunter: hooked to an enemy ──
		local point = g.Track()
		if not point then
			release("Lost", true)
			return
		end
		if g.Phase == "Fly" then
			if now >= g.PullAt then
				g.Phase = "Pull"
				g.PullStartedAt = now
				g.Shot:Attach()
				Feed.BiteAt = now
				movement:GrappleStart(point, hookProfile(), g.Track)
			end
			return
		end
		local dist, stuck = movement:GrappleStatus()
		if not movement:IsGrappling() then
			release("Lost", true)
		elseif dist <= g.Arrive then
			release("Arrive", true)
		elseif movement.Input.JumpPressedAt > g.PullStartedAt then
			release("Release", true)
		elseif now - g.PullStartedAt > G.MaxTime or stuck then
			release("Release", true)
		end
		return
	end
	if g.Phase == "Perch" then
		-- ── Mag-Anchor: holding on to the wall ──
		if not movement:IsPerched() or not g.Part:IsDescendantOf(Workspace) then
			release("Lost", true)
		elseif movement.Input.JumpPressedAt > g.PerchAt then
			release("Release", true) -- jump: hop off the wall
		elseif now > g.PerchUntil then
			release("Lost", true)
		end
		return
	end
	-- the anchor went away or moved (a door, a destroyed prop): nothing to hold on to
	if not g.Part:IsDescendantOf(Workspace) or (g.Part.CFrame.Position - g.PartCFrame.Position).Magnitude > 1.5 then
		release("Lost", true)
		return
	end
	if g.Phase == "Fly" then
		if now >= g.PullAt then
			if g.Ability == "Blink" then
				-- Starfall: zipped straight to the point (the server exempted the jump and reveals enemies there)
				g.Shot:Attach()
				Feed.BiteAt = now
				local n = g.Normal or Vector3.yAxis
				local pos = if n.Y > 0.5 then g.Point + Vector3.new(0, 3.2, 0) else g.Point + n * 3 - Vector3.new(0, 1, 0)
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					GrappleFX.Blink(character, root.Position, pos, n, true)
					character:PivotTo(CFrame.new(pos) * root.CFrame.Rotation)
					root.AssemblyLinearVelocity = Vector3.new(n.X * 8, 16, n.Z * 8)
					movement.Velocity = Vector3.zero
				end
				release("Arrive", true)
				return
			end
			g.Phase = "Pull"
			g.PullStartedAt = now
			g.Shot:Attach()
			Feed.BiteAt = now
			movement:GrappleStart(g.Point, if g.Ability == "Swing" then getSwingCfg(g.AP) else hookProfile())
		end
		return
	end
	local dist, stuck = movement:GrappleStatus()
	if not movement:IsGrappling() then
		release("Lost", true)
	elseif dist <= G.ArriveDistance then
		if g.Ability == "Perch" and g.Normal and math.abs(g.Normal.Y) < 0.55 then
			g.Phase = "Perch"
			g.PerchAt = now
			g.PerchUntil = now + ((g.AP and g.AP.Time) or 3)
			movement:PerchStart(g.Point + g.Normal * 2.3 - Vector3.new(0, 1, 0), g.Normal)
			remote:FireServer("Perch")
		else
			release("Arrive", true)
		end
	elseif movement.Input.JumpPressedAt > g.PullStartedAt then
		release("Release", true) -- jump lets go
	elseif now - g.PullStartedAt > G.MaxTime or stuck then
		release("Release", true)
	else
		-- something solid between you and the hook for most of a second (swung right round a
		-- corner): the cable is cut. Brief clips (a branch, a railing) are ignored.
		local eye = eyeOf(character)
		local los = solidHit(eye, g.Point - eye)
		if los and (los.Position - g.Point).Magnitude > 3 then
			g.BlockedSince = g.BlockedSince or now
			if now - g.BlockedSince > 0.9 then
				release("Release", true)
			end
		else
			g.BlockedSince = nil
		end
	end
end)

local touch = UserInputService.TouchEnabled
ContextActionService:BindActionAtPriority("VantageAbility_Grapple", function(_, state)
	if state == Enum.UserInputState.Begin and not game:GetService("Players").LocalPlayer:GetAttribute("VantageVehicleLocal") then
		use() -- (no grapple from a vehicle seat)
	end
	return Enum.ContextActionResult.Pass
end, touch, Enum.ContextActionPriority.High.Value, table.unpack(G.Keys))
if touch then
	ContextActionService:SetImage("VantageAbility_Grapple", G.Icon)
end

-- ── server messages ───────────────────────────────────────────────────────────────────────
remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
	if kind == "FX" and b ~= "GrappleTarget" then
		-- another player's hook: a = character, b = "Grapple", c = hook point, d = surface normal (2026-11-19)
		if typeof(a) == "Instance" and a:IsA("Model") and a ~= player.Character and b == "Grapple" and typeof(c) == "Vector3" then
			GrappleFX.Fire(a, c, false, if typeof(d) == "Vector3" then d else nil)
		elseif typeof(a) == "Instance" and a:IsA("Model") and a ~= player.Character and b == "Blink" and type(c) == "table"
			and typeof(c.From) == "Vector3" and typeof(c.To) == "Vector3" then
			GrappleFX.Blink(a, c.From, c.To, if typeof(c.Normal) == "Vector3" then c.Normal else Vector3.yAxis, false)
		elseif typeof(a) == "Instance" and a:IsA("Model") and a ~= player.Character and b == "GrappleAircraft" and type(c) == "table"
			and type(c.Flight) == "number" and type(c.Hook) == "number" then
			GrappleFX.FireTracked(a, AircraftRuntime.Tracker(c.Flight, c.Hook), false, AircraftConfig.Grapple.ProjectileSpeed)
		end
	elseif kind == "FX" and typeof(a) == "Instance" and a:IsA("Model") and a ~= player.Character and b == "GrappleTarget"
		and typeof(c) == "Instance" and c:IsA("Model") then
		-- another player's Harpoon on a character: the cable follows them
		local tr = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if tr then
			GrappleFX.FireTracked(a, function()
				if tr.Parent then
					return tr.Position, tr.AssemblyLinearVelocity
				end
				return nil, Vector3.zero
			end, false, G.ProjectileSpeed)
		end
	elseif kind == "Hooked" then
		-- a Harpoon speared you: a heavy thunk, and the hunter's line flashes
		GrappleFX.Hooked(if typeof(a) == "Instance" then a else nil)
	elseif kind == "GrappleCut" then
		-- Harpoon: the target shot you, or went down
		if live and live.Target then
			release("Release", false)
		end
	elseif kind == "AircraftDetach" then
		-- the server let go for us (flight over, drop point, leash)
		if live and live.Aircraft then
			release(if type(a) == "string" then a else "Ended", false)
		end
	elseif kind == "GrappleEnd" then
		if typeof(a) == "Instance" and a:IsA("Model") and a ~= player.Character then
			GrappleFX.ReleaseAll(a)
		end
	elseif kind == "GrappleReject" then
		-- the server saw it differently (cooldown, range, something in the way): let go, show its cooldown
		release("Cancel", false) -- no fling, no float (2026-11-19)
		relayUntil = 0
		if type(a) == "number" then
			readyAt = os.clock() + a
		end
	elseif kind == "Cooldown" and a == "Grapple" and type(b) == "number" then
		readyAt = os.clock() + b
	end
end)

-- ── life cycle: usable while alive, cooldown resets on spawn (mirrors the server) ───────────
local function onCharacter(character: Model)
	release("Dead", false)
	Feed.FiredAt, Feed.EndAt, Feed.Track = 0, nil, nil -- a fresh life starts with the arm on the gun
	AircraftRuntime.SetLocalRide(nil)
	readyAt = 0
	relayUntil = 0
	table.clear(charges)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	gui.Enabled = true
	humanoid.Died:Connect(function()
		gui.Enabled = false
		release("Dead", true)
	end)
end
-- Studio test hooks (player attributes): bump GrappleTestFire to fire as if E was pressed;
-- GrappleHoldAt = seconds freezes the first-person arm at that time into the grapple (< 0 = live)
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("GrappleTestFire"):Connect(use)
	player:GetAttributeChangedSignal("GrappleHoldAt"):Connect(function()
		local v = player:GetAttribute("GrappleHoldAt")
		Feed.HoldAt = if type(v) == "number" and v >= 0 then v else nil
	end)
	-- GrappleTune_<field> (Wrist, Follow, Straight, ShoulderBias, Pole, Roll, Cone, Kick, Jolt,
	-- ReachIn, Retract) overrides Viewmodel's GRAPPLE values live; remove the attribute to restore
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 12) == "GrappleTune_" then
			Feed.Tune = Feed.Tune or {}
			Feed.Tune[string.sub(name, 13)] = player:GetAttribute(name)
		end
	end)
end

-- HUD v4: the ability tile reads the grapple cooldown / charges from the shared feed
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if live and not live.Aircraft then
		Feed.ReadyAt = now + hookStats().Cooldown -- on the cable: the cooldown waits for the let-go
	elseif now <= relayUntil then
		Feed.ReadyAt = now -- Kraken's free grapple: the tile shows ready
	else
		if readyAt == math.huge then
			readyAt = now + hookStats().Cooldown
		end
		Feed.ReadyAt = readyAt
	end
	Feed.ChargeTimes = charges
end)

-- ── speed lines (2026-11-19): thin streaks in the OUTER ring of the screen while you fly on the cable or the fling
-- right after it; nothing near the crosshair. Off with the camera-FX setting.
do
	local sgui = Instance.new("ScreenGui")
	sgui.Name = "VantageGrappleSpeed"
	sgui.ResetOnSpawn = false
	sgui.IgnoreGuiInset = true
	sgui.DisplayOrder = 0
	sgui.Parent = player:WaitForChild("PlayerGui")
	local rng = Random.new()
	local lines = {}
	for i = 1, 22 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(2, 90)
		f.Parent = sgui
		lines[i] = { F = f, A = rng:NextNumber(0, math.pi * 2), R = rng:NextNumber(0.39, 0.5), T = rng:NextNumber(), L = rng:NextNumber(60, 150) }
	end
	local level, afterAt = 0, -math.huge
	RunService.RenderStepped:Connect(function(dt)
		local mv = MovementController.Current
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		local want = 0
		if mv and root and player:GetAttribute("VantageCameraFX") ~= false and not player:GetAttribute("VantageThirdPerson") then
			local s = root.AssemblyLinearVelocity.Magnitude
			if mv:IsGrappling() then
				afterAt = os.clock()
			end
			if os.clock() - afterAt < 0.6 then
				want = math.clamp((s - 55) / 50, 0, 1)
			end
		end
		level += (want - level) * math.min(1, dt * 10)
		if level < 0.01 then
			if lines[1].F.BackgroundTransparency < 1 then
				for _, l in lines do
					l.F.BackgroundTransparency = 1
				end
			end
			return
		end
		local col = Color3.new(1, 1, 1)
		if ch then
			local a = EquipCatalog.HookColors(ch)
			col = a:Lerp(Color3.new(1, 1, 1), 0.55)
		end
		for _, l in lines do
			l.T += dt * 3.2
			if l.T >= 1 then
				l.T, l.A, l.R, l.L = 0, rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.39, 0.47), rng:NextNumber(60, 150)
			end
			local r = l.R + l.T * 0.06
			local cx, cy = math.cos(l.A), math.sin(l.A)
			l.F.Position = UDim2.fromScale(0.5 + cx * r, 0.5 + cy * r)
			l.F.Rotation = math.deg(l.A) + 90
			l.F.Size = UDim2.fromOffset(2, l.L * (0.6 + level * 0.6))
			l.F.BackgroundColor3 = col
			l.F.BackgroundTransparency = 1 - level * 0.55 * math.sin(l.T * math.pi)
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
