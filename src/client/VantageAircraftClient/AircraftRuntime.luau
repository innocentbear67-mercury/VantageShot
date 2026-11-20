--[[
	VANTAGE — AircraftRuntime (client)
	The dropship as every player sees it. Nothing here is authoritative: the server publishes the
	flight (id, direction, start time) and the hook owners as attributes on
	ReplicatedStorage.Vantage.Aircraft, and this module derives everything from the shared
	AircraftPath at workspace:GetServerTimeNow(), so all clients agree with the server.

	Each frame
		- moves a local copy of the user's model (ReplicatedStorage.Vantage.Aircraft.AircraftModel),
		  fading it in / out at the ends of the route; engine glow + blinking nav lights
		- engine audio: a turbine whine and a low roar on the hull (3D roll-off = louder as it
		  approaches), a Doppler pitch shift, and a one-off pass whoosh when it is closest to you
		- finds the hook under the crosshair (aim assist, range, below the hull, line of sight, free,
		  aircraft inside the grapple band) and marks it; free hooks in reach get a faint dot
		- other players hanging (server attribute VantageHanging): their body is pinned under the
		  hook here with the same rope pendulum the rider uses, so it never trails behind the hull
		- the hanging pose (arms up the cable, legs dangling) on every hanging character
		- prompts: E GRAPPLE on a target, SPACE RELEASE while hanging, a warning before the drop
		  point, NO GROUND BELOW when letting go now would land you in a void, and DROPSHIP
		  INBOUND when a flight starts

	API (VantageAbilityClient)
		Runtime.GetTarget()                 -> { Flight, Hook, Point, Distance } | nil (fresh)
		Runtime.Tracker(flightId, hook)     -> function() -> (point, velocity, aircraftCFrame) | nil
		Runtime.PastDrop(flightId)          -> the aircraft left the drop band (riders let go)
		Runtime.ServerTime()
		Runtime.SetLocalRide(phase | nil)   "Pull" | "Hang" | nil (HUD + local flags)
		Runtime.SetThirdPerson(on)          the ride camera (Config.Camera): an over-the-shoulder orbit
		                                    with mouse / stick look while on the dropship, straight back to
		                                    first person (same aim) when you let go. While it is on, the
		                                    player attribute VantageThirdPerson hides the first-person gun
		                                    and arms (WeaponController / KnifeController) and GrappleFX draws
		                                    your cable from the character's own forearm launcher.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Folder = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Aircraft")
local Config = require(Folder:WaitForChild("AircraftConfig"))
local Path = require(Folder:WaitForChild("AircraftPath"))
local MovementController = require(script.Parent.Parent:WaitForChild("VantageMovementClient"):WaitForChild("MovementController"))

local player = Players.LocalPlayer
local Runtime = {}

local LIME, WHITE = Config.Colors.Lime, Config.Colors.LimeWhite
local TITLE = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local started = false
local localRide: string? = nil -- "Pull" | "Hang" | nil
local target: any = nil

-- ── flight state (server attributes) ──────────────────────────────────────────────────────────────────

local function flightInfo(): (number, number, number, boolean)
	return Folder:GetAttribute("FlightId") or 0, Folder:GetAttribute("FlightDir") or 0,
		Folder:GetAttribute("FlightStart") or 0, Folder:GetAttribute("FlightActive") == true
end

function Runtime.ServerTime(): number
	return Workspace:GetServerTimeNow()
end

-- the aircraft right now (nil when there is none)
function Runtime.Aircraft(): (CFrame?, Vector3, number)
	local id, dir, startAt, active = flightInfo()
	if not active or id == 0 or dir == 0 then
		return nil, Vector3.zero, 0
	end
	local cf, vel = Path.At(dir, startAt, Runtime.ServerTime())
	return cf, vel, id
end

local function hookOwner(i: number): number
	return Folder:GetAttribute("Hook" .. i) or 0
end

local function riderCount(): number
	local n = 0
	for i = 1, Path.HookCount() do
		if hookOwner(i) ~= 0 then
			n += 1
		end
	end
	return n
end

-- follows hook i of flight `flightId`; returns nil once that flight is over
function Runtime.Tracker(flightId: number, i: number): () -> (Vector3?, Vector3, CFrame?)
	local hookLocal = Path.HookLocal(i)
	return function()
		local cf, vel, id = Runtime.Aircraft()
		if not cf or id ~= flightId then
			return nil, Vector3.zero, nil
		end
		return (cf * hookLocal).Position, vel, cf
	end
end

-- direction and seconds into the current flight (nil when there is none)
function Runtime.FlightClock(): (number?, number)
	local id, dir, startAt, active = flightInfo()
	if not active or id == 0 or dir == 0 then
		return nil, 0
	end
	return dir, Runtime.ServerTime() - startAt
end

function Runtime.PastDrop(flightId: number): boolean
	local cf, _, id = Runtime.Aircraft()
	local dir, t = Runtime.FlightClock()
	return not cf or id ~= flightId or not dir or Path.PastDropAt(dir, t)
end

function Runtime.Armed(): boolean
	local dir, t = Runtime.FlightClock()
	return dir ~= nil and Path.ArmedAt(dir, t)
end

-- ── targeting ───────────────────────────────────────────────────────────────────────────────────────

local function ignoreList(): { Instance }
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
	for _, name in { "VantageAircraftFX", "VantageGrappleFX", "VantageShieldFX", "VantageIntroStandIns", "VantageIntroFX", "VantageSpawnZone" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

-- is there solid geometry between a and b (other than at b)?
local function blocked(a: Vector3, b: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = ignoreList()
	params.FilterDescendantsInstances = ignore
	local dir = b - a
	local dist = dir.Magnitude
	for _ = 1, 6 do
		local hit = Workspace:Raycast(a, dir, params)
		if not hit then
			return false
		end
		if hit.Instance.CanCollide then
			return (hit.Position - a).Magnitude < dist - 2.5
		end
		table.insert(ignore, hit.Instance)
		params.FilterDescendantsInstances = ignore
	end
	return false
end

local function eyeOf(character: Model): Vector3?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

-- per hook: "Target" | "Idle" | nil  (for the markers)
local hookShow: { [number]: string? } = {}

local function computeTarget(): any
	table.clear(hookShow)
	if localRide then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local eye = character and eyeOf(character)
	if not character or not humanoid or humanoid.Health <= 0 or not eye then
		return nil
	end
	local acf, _, id = Runtime.Aircraft()
	if not acf or not Runtime.Armed() or riderCount() >= Config.MaxRiders then
		return nil
	end
	local G = Config.Grapple
	local cam = Workspace.CurrentCamera.CFrame
	local down = -acf.UpVector
	local best, bestAngle = nil, math.huge
	-- aiming anywhere at the dropship itself (its whole ~72-stud body, plus the aim cone) counts:
	-- then every free hook in range and in sight qualifies and the one nearest the crosshair wins
	local toShip = acf.Position - cam.Position
	local shipDist = toShip.Magnitude
	local shipAngle = math.acos(math.clamp(cam.LookVector:Dot(toShip / shipDist), -1, 1))
	local aimedAtShip = shipAngle <= math.max(math.rad(G.AimConeDeg), math.atan(math.max(G.AimRadius, Config.Length * 0.5) / shipDist))
	for i = 1, Path.HookCount() do
		if hookOwner(i) ~= 0 then
			continue
		end
		local hook = (acf * Path.HookLocal(i)).Position
		local dist = (hook - eye).Magnitude
		if dist > G.Range * 1.15 or (eye - hook).Unit:Dot(down) < G.MinBelowDot then
			continue
		end
		local inRange = dist <= G.Range
		local toHook = hook - cam.Position
		local camDist = toHook.Magnitude
		local angle = math.acos(math.clamp(cam.LookVector:Dot(toHook / camDist), -1, 1))
		local allowed = math.max(math.rad(G.AimConeDeg), math.atan(G.AimRadius / camDist))
		if inRange and (angle <= allowed or aimedAtShip) and angle < bestAngle and not blocked(eye, hook) then
			best, bestAngle = { Flight = id, Hook = i, Point = hook, Distance = dist }, angle
		end
		hookShow[i] = "Idle"
	end
	if best then
		hookShow[best.Hook] = "Target"
	end
	return best
end

function Runtime.GetTarget(): any
	target = computeTarget()
	return target
end

-- ── the local copy of the aircraft ─────────────────────────────────────────────────────────────────────────

local fxFolder: Folder? = nil
local function getFolder(): Folder
	if not fxFolder or not fxFolder.Parent then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "VantageAircraftFX"
		fxFolder.Parent = Workspace
	end
	return fxFolder :: Folder
end

-- { Id, Model, Hull, Parts = { {Part, Base} }, Sounds, Markers, Nav, PassPlayed, LastVr }
local visual: any = nil

local function hullLocal(meshPoint: Vector3): Vector3
	return (meshPoint - Config.MeshCenter) * Config.Length -- the hull part's own frame
end

local function newSound(spec, parent: Instance, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = 0
	s.PlaybackSpeed = spec.Speed or 1
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = spec.RollOffMin or 40
	s.RollOffMaxDistance = spec.RollOffMax or 800
	s.Parent = parent
	return s
end

local function marker(parent: Attachment): any
	local gui = Instance.new("BillboardGui")
	gui.Name = "HookMarker"
	gui.Size = UDim2.fromOffset(54, 54)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Adornee = parent
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(30, 30)
	ring.BackgroundTransparency = 1
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = LIME
	stroke.Thickness = 2.5
	stroke.Parent = ring
	ring.Parent = gui
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(7, 7)
	dot.BackgroundColor3 = WHITE
	dot.BorderSizePixel = 0
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1, 0)
	dc.Parent = dot
	dot.Parent = gui
	gui.Parent = parent
	return { Gui = gui, Ring = ring, Stroke = stroke, Dot = dot, Shown = nil, ShownAt = 0 }
end

local function destroyVisual()
	if visual then
		visual.Model:Destroy()
		visual = nil
	end
end

local function buildVisual(id: number): any
	local template = Folder:FindFirstChild(Config.ModelName)
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = "Dropship"
	local hull = model:FindFirstChild("Hull") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			table.insert(parts, { Part = d, Base = d.Transparency, Offset = hull.CFrame:ToObjectSpace(d.CFrame) })
			d.Transparency = 1
		end
	end
	-- engine glow
	for _, p in Config.Lights.Engines do
		local a = Instance.new("Attachment")
		a.Name = "Engine"
		a.Position = hullLocal(p)
		a.Parent = hull
		local light = Instance.new("PointLight")
		light.Color = Config.Colors.Engine
		light.Range = 16
		light.Brightness = 2.2
		light.Shadows = false
		light.Parent = a
		local pe = Instance.new("ParticleEmitter")
		pe.LightEmission = 1
		pe.LightInfluence = 0
		pe.Color = ColorSequence.new(WHITE, Config.Colors.Engine)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.4) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(0.08, 0.14)
		pe.Rate = 70
		pe.Speed = NumberRange.new(0)
		pe.LockedToPart = true
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Parent = a
	end
	-- nav lights
	local nav = {}
	for _, side in { { Config.Lights.NavLeft, Config.Colors.NavLeft }, { Config.Lights.NavRight, Config.Colors.NavRight } } do
		local a = Instance.new("Attachment")
		a.Name = "Nav"
		a.Position = hullLocal(side[1])
		a.Parent = hull
		local light = Instance.new("PointLight")
		light.Color = side[2]
		light.Range = 10
		light.Brightness = 3
		light.Shadows = false
		light.Parent = a
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(1.6, 1.6)
		gui.LightInfluence = 0
		gui.Adornee = a
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = side[2]
		f.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		f.Parent = gui
		gui.Parent = a
		table.insert(nav, { Light = light, Gui = gui })
	end
	-- hook attachments + markers
	local markers = {}
	for i = 1, Path.HookCount() do
		local a = Instance.new("Attachment")
		a.Name = "Hook_" .. Config.Hooks[i].Name
		a.CFrame = Config.ModelRotation:Inverse() * Path.HookLocal(i)
		a.Parent = hull
		markers[i] = marker(a)
	end
	local S = Config.Sounds
	local sounds = {
		Whine = newSound(S.Whine, hull, true),
		Roar = newSound(S.Roar, hull, true),
	}
	sounds.Whine:Play()
	sounds.Roar:Play()
	model.Parent = getFolder()
	return {
		Id = id, Model = model, Hull = hull, Parts = parts, Sounds = sounds, Markers = markers,
		Nav = nav, PassPlayed = false, LastVr = nil,
	}
end

local function playPass(hull: BasePart)
	local spec = Config.Sounds.Pass
	local s = newSound({ Id = spec.Id, Speed = spec.Speed, RollOffMin = 60, RollOffMax = 600 }, hull, false)
	s.Volume = spec.Volume
	s:Play()
	task.delay(spec.Length * 0.6, function()
		local t0 = os.clock()
		while s.Parent and os.clock() - t0 < spec.Length * 0.4 do
			s.Volume = spec.Volume * (1 - (os.clock() - t0) / (spec.Length * 0.4))
			task.wait()
		end
		s:Destroy()
	end)
end

local function stepVisual(now: number)
	local id, dir, startAt, active = flightInfo()
	local acf, vel = nil, Vector3.zero
	if active and id ~= 0 and dir ~= 0 then
		acf, vel = Path.At(dir, startAt, now)
	end
	if not acf then
		destroyVisual()
		return
	end
	if visual and visual.Id ~= id then
		destroyVisual()
	end
	if not visual then
		visual = buildVisual(id)
		if not visual then
			return
		end
	end
	local hull = visual.Hull
	local hullCF = acf * Config.ModelRotation
	hull.CFrame = hullCF
	for _, e in visual.Parts do
		if e.Part ~= hull then
			e.Part.CFrame = hullCF * e.Offset
		end
	end
	-- fade at both ends of the route
	local t = now - startAt
	local duration = Path.Duration(dir)
	local fade = math.clamp(math.min(t, duration - t) / Config.FadeTime, 0, 1)
	if fade ~= visual.Fade then
		visual.Fade = fade
		for _, e in visual.Parts do
			e.Part.Transparency = 1 - (1 - e.Base) * fade
		end
	end
	-- audio: volume with the fade; Doppler from the speed toward / away from the camera
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local toCam = camPos - acf.Position
	local dist = toCam.Magnitude
	local vr = if dist > 1e-3 then vel:Dot(toCam / dist) else 0
	local S = Config.Sounds
	local doppler = math.clamp(vr / 420, -S.Doppler, S.Doppler)
	visual.Sounds.Whine.Volume = S.Whine.Volume * fade
	visual.Sounds.Roar.Volume = S.Roar.Volume * fade
	visual.Sounds.Whine.PlaybackSpeed = S.Whine.Speed * (1 + doppler)
	visual.Sounds.Roar.PlaybackSpeed = S.Roar.Speed * (1 + doppler * 0.6)
	if not visual.PassPlayed and visual.LastVr and visual.LastVr > 0 and vr <= 0 and dist < S.Pass.Within then
		visual.PassPlayed = true
		playPass(hull)
	end
	visual.LastVr = vr
	-- nav lights: a double blink every 1.4 s
	local ph = now % 1.4
	local on = ph < 0.08 or (ph > 0.2 and ph < 0.28)
	for _, n in visual.Nav do
		n.Light.Enabled = on and fade > 0.5
		n.Gui.Enabled = on and fade > 0.5
	end
	-- hook markers
	local pulse = 1 + 0.12 * math.sin(now * 9)
	for i, m in visual.Markers do
		local show = hookShow[i]
		if show == "Idle" and not Config.ShowIdleMarkers then
			show = nil
		end
		if show ~= m.Shown then
			m.Shown = show
			m.ShownAt = now
			m.Gui.Enabled = show ~= nil
		end
		if show == "Target" then
			local k = math.clamp((now - m.ShownAt) / 0.12, 0, 1)
			m.Ring.Visible = true
			m.Ring.Size = UDim2.fromOffset(44 - 14 * k, 44 - 14 * k)
			m.Ring.Size = UDim2.fromOffset(m.Ring.Size.X.Offset * pulse, m.Ring.Size.Y.Offset * pulse)
			m.Stroke.Transparency = 0
			m.Dot.BackgroundTransparency = 0
			m.Dot.Size = UDim2.fromOffset(7, 7)
		elseif show == "Idle" then
			m.Ring.Visible = false
			m.Dot.BackgroundTransparency = 0.45
			m.Dot.Size = UDim2.fromOffset(6, 6)
		end
	end
end

-- ── riders: other players pinned under their hook, and the hanging pose for everyone ─────────

-- the body on the cable is solved every frame by HangRig (arms along the real cable, legs
-- trailing the swing with follow-through, breathing, head look) - see that module
local HangRig = require(script.Parent:WaitForChild("HangRig"))

-- character -> { Weight, Motors, Rig (HangRig state), Tf, PrevRel, Swing, Bob, BobVel, Len }
local riders: { [Model]: any } = {}
local localHook: number? = nil

-- "Pull" | "Hang" | nil, and the hook index, for any character
local function ridePhase(character: Model): (string?, number?)
	if character == player.Character then
		local m = MovementController.Current
		if not m or not localHook then
			return nil, nil
		end
		if m:IsHanging() then
			return "Hang", localHook
		elseif localRide == "Pull" and m:IsGrappling() then
			return "Pull", localHook
		end
		return nil, nil
	end
	local hook = character:GetAttribute("VantageAircraftHook")
	if type(hook) ~= "number" then
		return nil, nil
	end
	return if character:GetAttribute("VantageHanging") == true then "Hang" else "Pull", hook
end

local function riderRecord(character: Model): any
	local r = riders[character]
	if not r then
		local owner = Players:GetPlayerFromCharacter(character)
		r = { Weight = 0, Motors = HangRig.Motors(character), Rig = HangRig.NewState(owner and owner.UserId or 0), Swing = Vector3.zero }
		riders[character] = r
	end
	return r
end

-- the same rope pendulum MovementController uses for the local rider
local function pendulum(r, hook: Vector3, hookVel: Vector3, acf: CFrame, dt: number)
	local H = Config.Hang
	local v = r.BobVel + Vector3.new(0, -Workspace.Gravity, 0) * dt
	v = hookVel + (v - hookVel) * math.exp(-H.Damping * dt)
	local p = r.Bob + v * dt
	local d = p - hook
	local down = -acf.UpVector
	local n = if d.Magnitude > 1e-3 then d.Unit else down
	local maxA = math.rad(H.MaxAngle)
	local ang = math.acos(math.clamp(n:Dot(down), -1, 1))
	if ang > maxA then
		local axis = down:Cross(n)
		if axis.Magnitude > 1e-4 then
			n = CFrame.fromAxisAngle(axis.Unit, maxA):VectorToWorldSpace(down)
		end
	end
	local len = r.Len + (H.Length - r.Len) * math.min(1, dt * 6)
	r.Len = len
	p = hook + n * len
	local rel = v - hookVel
	rel -= n * rel:Dot(n)
	r.Bob, r.BobVel = p, hookVel + rel
	return p, n
end

local function stepRemoteRiders(dt: number)
	local acf, vel = Runtime.Aircraft()
	dt = math.min(dt, 1 / 20)
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if p == player or not character then
			continue
		end
		local hookIndex = character:GetAttribute("VantageAircraftHook")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not acf or not root or type(hookIndex) ~= "number" or character:GetAttribute("VantageHanging") ~= true then
			local r = riders[character]
			if r then
				r.Bob = nil
			end
			continue
		end
		local r = riderRecord(character)
		local hook = (acf * Path.HookLocal(hookIndex)).Position
		if not r.Bob then
			r.Bob = root.Position
			r.BobVel = vel
			r.Len = math.max((root.Position - hook).Magnitude, Config.Hang.Length)
		end
		-- facing: whatever the rider's own client says (replicated), about the rope
		local look = root.CFrame.LookVector
		local pos, n = pendulum(r, hook, vel, acf, dt)
		local up = -n
		local fwd = look - up * look:Dot(up)
		if fwd.Magnitude < 1e-3 then
			fwd = acf.LookVector
		end
		root.CFrame = CFrame.lookAt(pos, pos + fwd.Unit, up)
	end
end

-- after the Animator: solve the body on the cable and blend it in / out on every character
local function stepPose(dt: number)
	local acf = Runtime.Aircraft()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if not character then
			continue
		end
		local phase, hookIndex = ridePhase(character)
		if not phase and not riders[character] then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local r = riderRecord(character)
		local want = if phase and acf and root then 1 else 0
		r.Weight += (want - r.Weight) * (1 - math.exp(-(if want == 1 then 9 else 7) * dt))
		if want == 0 and r.Weight < 0.01 then
			riders[character] = nil
			continue
		end
		if want == 1 and root and acf and hookIndex then
			local hook = (acf * Path.HookLocal(hookIndex)).Position
			-- the body's swing relative to the hook (how the legs should trail)
			local rel = root.Position - hook
			if r.PrevRel and dt > 0 then
				r.Swing = r.Swing:Lerp((rel - r.PrevRel) / dt, 1 - math.exp(-10 * dt))
			end
			r.PrevRel = rel
			local look = if character == player.Character then Workspace.CurrentCamera.CFrame.LookVector else nil
			r.Tf = HangRig.Solve(r.Motors, root.CFrame, hook, r.Swing, phase :: string, look, r.Rig, dt)
		else
			r.PrevRel = nil -- letting go: keep the last solved pose and blend out of it
		end
		local w = r.Weight
		if r.Tf then
			for joint, m in r.Motors do
				local t = r.Tf[joint]
				if t and m.Parent then
					m.Transform = m.Transform:Lerp(t, w)
				end
			end
		end
	end
	for character in riders do
		if not character.Parent then
			riders[character] = nil
		end
	end
end

-- ── prompts ──────────────────────────────────────────────────────────────────────────────────────────────

-- if you let go now: does the fall end in a void? (ballistic path with the release velocity)
local voidCheckAt, voidBelow = 0, false
local function predictVoid(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local acf, vel = Runtime.Aircraft()
	if not root or not acf then
		return false
	end
	local R = Config.Release
	local v = vel * R.Inherit
	local flatV = Vector3.new(v.X, 0, v.Z)
	if flatV.Magnitude > R.MaxHorizontal then
		flatV = flatV.Unit * R.MaxHorizontal
	end
	v = Vector3.new(flatV.X, v.Y + R.Up, flatV.Z)
	local p = root.Position
	local g = Workspace.Gravity
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList()
	local voidY = Config.Hang.VoidY
	for _ = 1, 40 do
		local nv = v + Vector3.new(0, -g * 0.1, 0)
		local np = p + (v + nv) * 0.05
		local hit = Workspace:Raycast(p, np - p, params)
		if hit then
			return hit.Position.Y < voidY
		end
		if np.Y < voidY then
			return true
		end
		p, v = np, nv
	end
	return false
end

local hud: any = nil
local function buildHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "VantageAircraftHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	local function label(name: string, y: number, size: number, font: Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromOffset(520, size + 8)
		l.BackgroundTransparency = 1
		l.FontFace = font
		l.TextSize = size
		l.TextColor3 = WHITE
		l.TextStrokeTransparency = 0.6
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		l.RichText = true
		l.Text = ""
		l.Visible = false
		l.Parent = gui
		return l
	end
	-- the pointer to the dropship: a marker over it on screen, an edge arrow when it is not
	local marker = Instance.new("Frame")
	marker.Name = "DropshipMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(22, 22)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromOffset(14, 14)
	diamond.Rotation = 45
	diamond.BackgroundTransparency = 1
	local ds = Instance.new("UIStroke")
	ds.Thickness = 2
	ds.Color = LIME
	ds.Parent = diamond
	diamond.Parent = marker
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.Rotation = 45
	dot.BackgroundColor3 = LIME
	dot.BorderSizePixel = 0
	dot.Parent = marker
	marker.Parent = gui
	local arrow = Instance.new("TextLabel")
	arrow.Name = "DropshipArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(30, 30)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▲"
	arrow.TextSize = 26
	arrow.FontFace = TITLE
	arrow.TextColor3 = LIME
	arrow.TextStrokeTransparency = 0.5
	arrow.Visible = false
	arrow.Parent = gui
	local tag = Instance.new("TextLabel")
	tag.Name = "DropshipTag"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Size = UDim2.fromOffset(260, 18)
	tag.BackgroundTransparency = 1
	tag.FontFace = MONO
	tag.TextSize = 13
	tag.TextColor3 = LIME
	tag.TextStrokeTransparency = 0.55
	tag.Visible = false
	tag.Parent = gui
	local lime = string.format("#%02X%02X%02X", LIME.R * 255, LIME.G * 255, LIME.B * 255)
	hud = {
		Marker = marker, Diamond = diamond, DiamondStroke = ds, Dot = dot, Arrow = arrow, Tag = tag,
		Gui = gui,
		Prompt = label("Prompt", 0.6, 17, MONO),
		Warn = label("Warn", 0.645, 15, MONO),
		Void = label("Void", 0.685, 15, MONO),
		Banner = label("Banner", 0.16, 22, TITLE),
		Lime = lime,
		BannerUntil = 0,
	}
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function keyName(kind: string): string
	local pad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	if kind == "Grapple" then
		return if pad then "R1" else "E"
	end
	return if pad then "A" else "SPACE"
end

-- the pointer to the dropship (marker on screen / arrow at the edge), while a flyby is on
local function stepPointer(now: number)
	local P = Config.Pointer
	local function hide()
		hud.Marker.Visible = false
		hud.Arrow.Visible = false
		hud.Tag.Visible = false
	end
	if not P or not P.Enabled then
		hide()
		return
	end
	local acf = Runtime.Aircraft()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local menu = pg and pg:FindFirstChild("VantageMainMenu")
	if not acf or not visual or (visual.Fade or 0) < 0.05 or localRide or not humanoid or humanoid.Health <= 0
		or (menu and menu:IsA("ScreenGui") and menu.Enabled) or player:GetAttribute("VisorBlackout") then
		hide()
		return
	end
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local pos = acf.Position
	local sp = cam:WorldToViewportPoint(pos)
	local dist = (pos - cam.CFrame.Position).Magnitude
	local armed = Runtime.Armed()
	local color = if armed then LIME else WHITE
	local alpha = if armed then 0 else 0.35
	hud.Tag.Text = string.format("%s  %dm%s", P.Label, math.floor(dist + 0.5), if armed then "  ·  GRAPPLE" else "")
	hud.Tag.TextColor3 = color
	hud.Tag.TextTransparency = alpha
	hud.Tag.Visible = true
	local m = P.EdgeMargin
	if sp.Z > 0 and sp.X >= m and sp.X <= vp.X - m and sp.Y >= m and sp.Y <= vp.Y - m then
		-- on screen: a diamond over the aircraft, the tag under it
		local pulse = if armed then 1 + 0.12 * math.sin(now * 6) else 1
		hud.Marker.Position = UDim2.fromOffset(sp.X, sp.Y)
		hud.Marker.Size = UDim2.fromOffset(22 * pulse, 22 * pulse)
		hud.DiamondStroke.Color = color
		hud.DiamondStroke.Transparency = alpha
		hud.Dot.BackgroundColor3 = color
		hud.Dot.BackgroundTransparency = alpha
		hud.Marker.Visible = true
		hud.Arrow.Visible = false
		hud.Tag.Position = UDim2.fromOffset(sp.X, sp.Y + 16)
	else
		-- off screen (or behind you): an arrow on the screen edge pointing at it
		local center = vp / 2
		local d = Vector2.new(sp.X, sp.Y) - center
		if sp.Z < 0 then
			d = -d
		end
		if d.Magnitude < 1 then
			d = Vector2.new(0, -1)
		end
		local hx, hy = center.X - m, center.Y - m
		local k = math.min(hx / math.max(math.abs(d.X), 1e-4), hy / math.max(math.abs(d.Y), 1e-4))
		local edge = center + d * k
		hud.Arrow.Position = UDim2.fromOffset(edge.X, edge.Y)
		hud.Arrow.Rotation = math.deg(math.atan2(d.Y, d.X)) + 90
		hud.Arrow.TextColor3 = color
		hud.Arrow.TextTransparency = alpha
		hud.Arrow.Visible = true
		hud.Marker.Visible = false
		local inward = edge - d.Unit * 30
		hud.Tag.Position = UDim2.fromOffset(math.clamp(inward.X, 130, vp.X - 130), math.clamp(inward.Y - 9, 8, vp.Y - 26))
	end
end

local function stepHud(now: number)
	if not hud then
		return
	end
	stepPointer(now)
	local L = hud.Lime
	if localRide == "Hang" then
		hud.Prompt.Visible = true
		hud.Prompt.Text = string.format('<font color="%s">[%s]</font>  RELEASE', L, keyName("Release"))
		local acf, vel = Runtime.Aircraft()
		local dirNow, tNow = Runtime.FlightClock()
		local left = if acf and dirNow then Path.StudsToDropAt(dirNow, tNow) else nil
		if left and left < Config.Zone.WarnAhead then
			hud.Warn.Visible = (now * 3) % 1 < 0.6
			hud.Warn.Text = string.format("DROP ZONE ENDS  %.0f", math.max(0, left / math.max(vel.Magnitude, 1)))
		else
			hud.Warn.Visible = false
		end
		if now >= voidCheckAt then
			voidCheckAt = now + 0.15
			voidBelow = predictVoid()
		end
		hud.Void.Visible = voidBelow
		hud.Void.TextColor3 = Color3.fromRGB(255, 90, 90)
		hud.Void.Text = "▼ NO GROUND BELOW"
	elseif target and not localRide then
		hud.Prompt.Visible = true
		hud.Prompt.Text = string.format('<font color="%s">[%s]</font>  GRAPPLE DROPSHIP', L, keyName("Grapple"))
		hud.Warn.Visible = false
	else
		hud.Prompt.Visible = false
		hud.Warn.Visible = false
	end
	if localRide ~= "Hang" then
		hud.Void.Visible = false
	end
	hud.Banner.Visible = now < hud.BannerUntil
	if hud.Banner.Visible then
		hud.Banner.TextTransparency = math.clamp((now - (hud.BannerUntil - 0.6)) / 0.6, 0, 1)
	end
end

-- ── the ride camera ──────────────────────────────────────────────────────────────────────────────────────────────────

local tp: any = nil -- { Yaw, Pitch, From, StartedAt, Stick }
local stick2 = Vector2.zero
UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local v = Vector2.new(input.Position.X, input.Position.Y)
		stick2 = if v.Magnitude > 0.15 then v else Vector2.zero
	end
end)

-- the HUD is off for the ride (the visor panels and screen HUD don't work from a third-person
-- camera): every other ScreenGui and the 3D visor panels, re-applied each frame like the
-- operative intro does, and put back exactly as they were when you let go. Only the
-- dropship prompts stay.
local hiddenGuis: { [Instance]: boolean } = {}
local function hideHud()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			-- VantageAbilities is an empty holder (the visor draws the slot) and gates the E key: leave it
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "VantageAircraftHud" and g.Name ~= "Freecam" and g.Name ~= "VantageAbilities" then
				g.Enabled = false
				if g.Name ~= "VantageMainMenu" then
					hiddenGuis[g] = true
				end
			end
		end
	end
	local holo = Workspace:FindFirstChild("VantageVisorHolo")
	if holo then
		for _, d in holo:GetDescendants() do
			if (d:IsA("SurfaceGui") or d:IsA("BillboardGui")) and d.Enabled then
				d.Enabled = false
				hiddenGuis[d] = true
			end
		end
	end
end

local function restoreHud()
	for g in hiddenGuis do
		if g.Parent then
			(g :: any).Enabled = true
		end
	end
	table.clear(hiddenGuis)
end

local function showBody(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
	end
end

local function stepThirdPerson(dt: number)
	if not tp then
		return
	end
	local C = Config.Camera
	local cam = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	-- look: mouse (locked to the centre, like first person) and the right stick
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	-- 2026-11-20: mouse look through the on-foot camera's own input action at the game's Sensitivity
	-- (GetMouseDelta loses most of the movement to that action; same fix as the drone camera)
	local md = Vector2.zero
	do
		local pm = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
		local act = pm and pm:FindFirstChild("CameraRotationAction", true)
		local mb = act and act:FindFirstChild("MouseBinding")
		local rate = math.rad(0.12) * math.max(0.05, tonumber(Players.LocalPlayer:GetAttribute("VantageSensitivity")) or 1)
		if act and mb and not UserInputService:GetLastInputType().Name:find("^Gamepad") then
			if not act.Enabled then act.Enabled = true end
			local sc = mb.Vector2Scale
			if math.abs(sc.X - rate) > 1e-7 then mb.Vector2Scale = Vector2.new(rate, if sc.Y < 0 then -rate else rate) end
			md = act:GetState() * dt
		elseif not act then
			md = UserInputService:GetMouseDelta() * rate
		end
	end
	tp.Yaw -= md.X + stick2.X * C.StickSpeed * dt
	tp.Pitch = math.clamp(tp.Pitch - md.Y + stick2.Y * C.StickSpeed * 0.7 * dt, math.rad(C.PitchMin), math.rad(C.PitchMax))
	local rot = CFrame.fromEulerAnglesYXZ(tp.Pitch, tp.Yaw, 0)
	local focus = root.Position + Vector3.new(0, C.Height, 0)
	local pos = focus - rot.LookVector * C.Distance + rot.RightVector * C.Shoulder
	-- never inside the hull: stay below the aircraft's belly
	local acf = Runtime.Aircraft()
	if acf then
		local up = acf.UpVector
		local belly = acf.Position + up * (-(Config.MeshCenter.Y * Config.Length) - C.HullGap)
		local above = (pos - belly):Dot(up)
		if above > 0 then
			pos -= up * above
		end
	end
	-- never through map geometry
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList()
	local hit = Workspace:Raycast(focus, pos - focus, params)
	if hit then
		pos = hit.Position + (focus - pos).Unit * 1
	end
	local target = CFrame.lookAt(pos, pos + rot.LookVector)
	local k = math.clamp((os.clock() - tp.StartedAt) / C.BlendIn, 0, 1)
	k = k * k * (3 - 2 * k)
	cam.CFrame = if k < 1 then tp.From:Lerp(target, k) else target
	if character then
		showBody(character)
	end
	hideHud()
end

function Runtime.SetThirdPerson(on: boolean)
	if not Config.Camera.ThirdPerson then
		return
	end
	local cam = Workspace.CurrentCamera
	if on then
		if tp then
			return
		end
		local look = cam.CFrame.LookVector
		tp = {
			Yaw = math.atan2(-look.X, -look.Z),
			-- start near level (you aimed steeply up at the hook; the ride should open on the view)
			Pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), math.rad(Config.Camera.StartPitchMin), math.rad(Config.Camera.StartPitchMax)),
			From = cam.CFrame,
			StartedAt = os.clock(),
		}
		player:SetAttribute("VantageThirdPerson", true)
		return
	end
	if not tp then
		return
	end
	local look = CFrame.fromEulerAnglesYXZ(tp.Pitch, tp.Yaw, 0).LookVector
	tp = nil
	player:SetAttribute("VantageThirdPerson", nil)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		restoreHud()
	else
		-- died on the cable: leave the screen to the death presenter, bring the HUD back next life
		player.CharacterAdded:Once(function()
			if not tp then
				restoreHud()
			end
		end)
	end
	local head = character and character:FindFirstChild("Head") :: BasePart?
	-- dead: the death presenter takes the camera; don't fight it
	if humanoid and humanoid.Health > 0 and head and cam.CameraType == Enum.CameraType.Scriptable then
		-- hide the body this very frame: first person must never open inside the armour
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
		cam.CameraType = Enum.CameraType.Custom
		cam.CFrame = CFrame.lookAt(head.Position, head.Position + look) -- first person resumes with the same aim
	end
end

function Runtime.SetLocalRide(phase: string?, hookIndex: number?)
	localRide = phase
	if hookIndex then
		localHook = hookIndex
	elseif phase == nil then
		localHook = nil
	end
	player:SetAttribute("VantageHangingLocal", phase == "Hang" or nil) -- WeaponController: no fire / aim, weapon lowered
	if phase == nil then
		Runtime.SetThirdPerson(false)
	elseif phase == "Hang" and Config.Camera.From == "Hang" then
		Runtime.SetThirdPerson(true)
	end
end

-- the cable bit the hull (VantageAbilityClient)
function Runtime.OnBite()
	if Config.Camera.From == "Bite" then
		Runtime.SetThirdPerson(true)
	end
end

function Runtime.LocalRide(): string?
	return localRide
end

-- ── start ────────────────────────────────────────────────────────────────────────────────────────────────────

function Runtime.Start()
	if started then
		return Runtime
	end
	started = true
	buildHud()
	Folder:GetAttributeChangedSignal("FlightId"):Connect(function()
		local id, _, _, active = flightInfo()
		if active and id ~= 0 and hud then
			hud.Banner.Text = string.format('<font color="%s">▲</font>  DROPSHIP INBOUND', hud.Lime)
			hud.Banner.TextTransparency = 0
			hud.BannerUntil = os.clock() + 3.5
		end
	end)
	-- before movement (Input + 1) so the aircraft, markers and target are this frame's
	RunService:BindToRenderStep("VantageAircraft", Enum.RenderPriority.Input.Value - 1, function(dt)
		local now = Runtime.ServerTime()
		target = computeTarget()
		stepVisual(now)
		stepRemoteRiders(dt)
		stepHud(os.clock())
	end)
	RunService.Stepped:Connect(function(_, dt)
		stepPose(dt)
	end)
	-- after Roblox's camera and VANTAGE's camera effects, so the ride camera has the last word
	RunService:BindToRenderStep("VantageAircraftCamera", Enum.RenderPriority.Camera.Value + 10, stepThirdPerson)
	return Runtime
end

return Runtime
