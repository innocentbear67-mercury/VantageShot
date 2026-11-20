--[[
	VANTAGE — VantageVehicleClient (LocalScript)
	Every client: animates all vehicles (VehicleVisuals) and plays weapon effects (VehicleFX).
	While the local player sits in a vehicle:
	  - third-person orbit camera (mouse), smooth blend in and out, RMB zoom
	  - driver: WASD / Space handbrake; this client is the network owner and runs VehicleSim
	  - weapon controller (gunner, or the driver when the gunner seat is empty): the turret slews
	    toward the camera's aim point; the barrel reticle shows where the gun really points; LMB fires
	  - F exits (the server finds a safe spot), 1-6 change seat
	The infantry weapon / knife / grapple stand down via player attributes VantageVehicleLocal and
	VantageThirdPerson (read by VantageWeaponClient / VantageAbilityClient), and prompts are hidden.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VF = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Vehicles")
local Config = require(VF:WaitForChild("VehicleConfig"))
local Sim = require(VF:WaitForChild("VehicleSim"))
local VMath = require(VF:WaitForChild("VehicleMath"))
local InputRemote = VF:WaitForChild("VehicleInput") :: RemoteEvent
local EventRemote = VF:WaitForChild("VehicleEvent") :: RemoteEvent

local FX = require(script:WaitForChild("VehicleFX"))
local Visuals = require(script:WaitForChild("VehicleVisuals"))
local Hud = require(script:WaitForChild("VehicleHud"))
local HitFX = require(script:WaitForChild("VehicleHitFX"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local gameSettings = UserSettings():GetService("UserGameSettings")

Visuals.Start()
local hud = Hud.new()
local hitfx = HitFX.new()

local SINK = "VantageVehicleSink"
local CAM_BIND = "VantageVehicleCamera"

local session = nil
local exitBlend = nil -- { From, Start }

-- the infantry HUD is off while you crew a vehicle (like the dropship ride): every other ScreenGui,
-- the visor's holo panels, re-applied each frame and put back exactly as they were on leaving.
-- Kept: the vehicle HUD, match score / timer, VEYRA comms, elimination banners, prompts.
local KEEP_GUI = {
	VehicleHud = true, VehicleHitFX = true, VantageKillFeed = true, VantageMatchHud = true, VantageVeyraComms = true, VantageElimination = true,
	Freecam = true, ProximityPrompts = true, VantageAbilities = true, -- (Abilities is an empty holder that gates E)
	VantageMainMenu = true, VantageSettings = true, VantageArmory = true, -- menus are the menu's business
}
local hiddenGuis: { [Instance]: boolean } = {}
local function hideHud()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			if g:IsA("LayerCollector") and g.Enabled and not KEEP_GUI[g.Name] then
				g.Enabled = false
				hiddenGuis[g] = true
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

local function seatOf(hum: Humanoid?): (Model?, Seat?)
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("Seat") and seat.Parent and seat.Parent.Name == "Seats" then
		local model = seat.Parent.Parent
		if model and model:IsA("Model") and model:GetAttribute("VehicleType") then
			return model, seat
		end
	end
	return nil, nil
end

local function seatPlayer(seat: Instance?): Player?
	local h = seat and (seat :: Seat).Occupant
	return h and Players:GetPlayerFromCharacter(h.Parent)
end

local function roleSeat(model: Model, role: string): Seat?
	for _, s in model.Seats:GetChildren() do
		if s:GetAttribute("Role") == role then
			return s
		end
	end
	return nil
end

-- the gunner seat if someone sits there, else the driver
local function controllerOf(model: Model): Player?
	local cfg = Config.Vehicles[model:GetAttribute("VehicleType")]
	local p = seatPlayer(roleSeat(model, cfg.Weapon.Controller))
	if p then
		return p
	end
	return seatPlayer(roleSeat(model, "Driver"))
end

-- ─── input ───────────────────────────────────────────────────────────────
local function onAction(_name: string, state: Enum.UserInputState, input: InputObject)
	if not session then
		return Enum.ContextActionResult.Pass
	end
	local began = state == Enum.UserInputState.Begin
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	local kc, ut = input.KeyCode, input.UserInputType
	if kc == Config.Interact.ExitKey or kc == Enum.KeyCode.ButtonB then
		if began then
			InputRemote:FireServer("Exit")
		end
	elseif kc == Enum.KeyCode.Space then
		session.Brake = not ended
	elseif ut == Enum.UserInputType.MouseButton1 or kc == Enum.KeyCode.ButtonR2 then
		if began then
			InputRemote:FireServer("Trigger", true)
		elseif ended then
			InputRemote:FireServer("Trigger", false)
		end
	elseif ut == Enum.UserInputType.MouseButton2 or kc == Enum.KeyCode.ButtonL2 then
		session.Zoom = not ended
	else
		for i, key in Config.Interact.SeatKeys do
			if kc == key then
				if began then
					InputRemote:FireServer("Seat", i)
				end
				break
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bindInput()
	local keys = { Config.Interact.ExitKey, Enum.KeyCode.ButtonB, Enum.KeyCode.Space, Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2 }
	for _, k in Config.Interact.SeatKeys do
		table.insert(keys, k)
	end
	ContextActionService:BindActionAtPriority(SINK, onAction, false, 3000, table.unpack(keys))
end

-- ─── camera ──────────────────────────────────────────────────────────────
local function cameraExclude(model: Model): { Instance }
	local t = { model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(t, p.Character)
		end
	end
	local fx = Workspace:FindFirstChild("VehicleFX")
	if fx then
		table.insert(t, fx)
	end
	return t
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function ease(t: number): number
	return 1 - (1 - t) ^ 3
end

-- mouse look this frame (radians, X = yaw, Y = pitch) through the on-foot camera's own input action
local camRotAction, camMouseBinding
local function lookRotation(dt: number, rate: number): Vector2
	if not camRotAction then
		local pm = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
			or Players.LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
		camRotAction = pm and pm:FindFirstChild("CameraRotationAction", true)
		camMouseBinding = camRotAction and camRotAction:FindFirstChild("MouseBinding")
	end
	if camRotAction and camMouseBinding then
		if not camRotAction.Enabled then
			camRotAction.Enabled = true
		end
		local sc = camMouseBinding.Vector2Scale
		if math.abs(sc.X - rate) > 1e-7 then
			camMouseBinding.Vector2Scale = Vector2.new(rate, if sc.Y < 0 then -rate else rate)
		end
		return camRotAction:GetState() * dt
	end
	local d = UserInputService:GetMouseDelta()
	return d * rate
end

local function stepCamera(dt: number)
	local s = session
	local root = s.Root
	local C = s.Cfg.Camera
	-- look around (world-relative, so the view does not swing with the hull)
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	-- 2026-11-20 fix (playtest: drone look was ~5% of normal sens). The on-foot camera reads mouse look from
	-- the PlayerModule's CameraRotationAction (Loadout sets its MouseBinding to 0.12 deg per count x the game's
	-- Sensitivity); that action also swallows most of GetMouseDelta. Read the same action at the same rate.
	local vs = tonumber(Players.LocalPlayer:GetAttribute("VantageSensitivity")) or 1
	local zoomK = if s.Zoom then C.ZoomFov / C.Fov else 1
	local last = UserInputService:GetLastInputType()
	if not (last.Name:sub(1, 7) == "Gamepad") then -- the stick is read below (the action carries it too)
		local rot = lookRotation(dt, math.rad(0.12) * math.max(0.05, vs) * zoomK)
		s.CamYaw -= rot.X
		s.CamPitch = math.clamp(s.CamPitch - rot.Y, math.rad(-65), math.rad(35))
	end
	-- gamepad right stick
	for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if st.KeyCode == Enum.KeyCode.Thumbstick2 and st.Position.Magnitude > 0.15 then
			s.CamYaw -= st.Position.X * dt * 2.6
			s.CamPitch = math.clamp(s.CamPitch + st.Position.Y * dt * 1.8, math.rad(-65), math.rad(35))
		end
	end

	local fov = if s.Zoom then C.ZoomFov else C.Fov
	s.Fov += (fov - s.Fov) * math.min(1, dt * 10)
	camera.FieldOfView = s.Fov

	local rot = CFrame.fromOrientation(s.CamPitch, s.CamYaw, 0)
	local focus = root.Position + Vector3.new(0, C.PivotY, 0)
	local dist = C.Distance * (if s.Zoom then 0.55 else 1)
	local want = focus - rot.LookVector * dist + Vector3.new(0, C.Height * 0.35, 0)
	rayParams.FilterDescendantsInstances = cameraExclude(s.Model)
	local block = Workspace:Raycast(focus, want - focus, rayParams)
	if block then
		want = block.Position + (focus - want).Unit * 1.2
	end
	local target = CFrame.lookAt(want, want + rot.LookVector)
	-- shake from nearby blasts and our own cannon
	if FX.Shake > 0.01 then
		local k = FX.Shake
		target *= CFrame.Angles((math.random() - 0.5) * 0.02 * k, (math.random() - 0.5) * 0.02 * k, 0)
		FX.Shake *= math.exp(-dt * 6)
	end
	local blend = math.clamp((os.clock() - s.BlendStart) / Config.Interact.CameraBlendTime, 0, 1)
	camera.CFrame = if blend < 1 then s.BlendFrom:Lerp(target, ease(blend)) else target
	s.LastCam = camera.CFrame
end

-- ─── session ─────────────────────────────────────────────────────────────
local function finish()
	local s = session
	if not s then
		return
	end
	session = nil
	Visuals.Local = nil
	ContextActionService:UnbindAction(SINK)
	ProximityPromptService.Enabled = true
	player:SetAttribute("VantageVehicleLocal", nil)
	player:SetAttribute("VantageThirdPerson", nil)
	hud:Show(false)
	restoreHud()
	InputRemote:FireServer("Trigger", false)
	if s.Sim then
		s.Sim:Clear()
	end
	-- glide back to the eyes, then hand the camera back to the game
	exitBlend = { From = s.LastCam or camera.CFrame, Start = os.clock() }
end

local function begin(model: Model, seat: Seat)
	local cfg = Config.Vehicles[model:GetAttribute("VehicleType")]
	local root = model.PrimaryPart :: BasePart
	if session and session.Model == model then
		-- seat change inside the same vehicle
		session.Seat = seat
		session.Driver = seat:GetAttribute("Role") == "Driver"
		session.Sim = if session.Driver then (session.Sim or Sim.new(model)) else nil
		return
	end
	if session then
		finish()
	end
	exitBlend = nil
	local look = root.CFrame.LookVector
	session = {
		Model = model, Root = root, Cfg = cfg, Seat = seat,
		Driver = seat:GetAttribute("Role") == "Driver",
		CamYaw = math.atan2(-look.X, -look.Z), CamPitch = math.rad(-12),
		BlendFrom = camera.CFrame, BlendStart = os.clock(), Fov = camera.FieldOfView,
		Zoom = false, Brake = false,
		Yaw = model:GetAttribute("AimYaw") or 0, Pitch = model:GetAttribute("AimPitch") or 0,
		AimPoint = root.Position + look * 100,
		Input = Sim.ZeroInput,
		LastDrive = 0, LastSentInput = nil, LastAim = 0, LastCrew = 0,
	}
	session.Sim = if session.Driver then Sim.new(model) else nil
	camera.CameraType = Enum.CameraType.Scriptable
	player:SetAttribute("VantageVehicleLocal", true)
	player:SetAttribute("VantageThirdPerson", true)
	ProximityPromptService.Enabled = false
	bindInput()
	hud:Show(true)
end

local pendingLeave = nil
local function onSeatPart(hum: Humanoid)
	local model, seat = seatOf(hum)
	if model and seat then
		pendingLeave = nil
		begin(model, seat)
	elseif session then
		-- a seat change passes through "no seat" for a moment: wait before leaving
		local token = {}
		pendingLeave = token
		task.delay(0.2, function()
			if pendingLeave == token then
				pendingLeave = nil
				if not seatOf(hum) then
					finish()
				end
			end
		end)
	end
end

local function onCharacter(character: Model)
	if session then
		finish()
	end
	exitBlend = nil
	camera.CameraType = Enum.CameraType.Custom
	local hum = character:WaitForChild("Humanoid") :: Humanoid
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeatPart(hum)
	end)
	hum.Died:Connect(function()
		if session then
			finish()
		end
	end)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- ─── per frame ───────────────────────────────────────────────────────────
local function stepSession(dt: number)
	local s = session
	local model, root = s.Model, s.Root
	if not model.Parent or not root.Parent then
		finish()
		return
	end
	local destroyed = model:GetAttribute("Destroyed") == true
	hideHud()
	-- open seats (buggy): show your own exo-suit — the first-person setup hides it otherwise.
	-- Closed hulls keep the crew hidden (VehicleVisuals)
	if not s.Seat:GetAttribute("Hidden") then
		local ch = player.Character
		if ch then
			for _, d in ch:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					(d :: any).LocalTransparencyModifier = 0
				end
			end
		end
	end
	stepCamera(dt)

	-- aim point: what the centre of the screen looks at
	local camCF = camera.CFrame
	rayParams.FilterDescendantsInstances = cameraExclude(model)
	local hit = Workspace:Raycast(camCF.Position, camCF.LookVector * 1500, rayParams)
	s.AimPoint = if hit then hit.Position else camCF.Position + camCF.LookVector * 1500

	local controls = controllerOf(model) == player and not destroyed
	s.Controls = controls
	local W = s.Cfg.Weapon
	if controls then
		local wy, wp = VMath.AnglesTo(root.CFrame, model, s.AimPoint)
		s.Yaw, s.Pitch = VMath.Slew(s.Yaw, s.Pitch, wy, wp, W, dt)
		-- stay close to the server's turret (it is the one that fires)
		local sy, sp = model:GetAttribute("AimYaw") or 0, model:GetAttribute("AimPitch") or 0
		if math.abs(VMath.WrapAngle(sy - s.Yaw)) > 0.3 or math.abs(sp - s.Pitch) > 0.2 then
			s.Yaw = VMath.WrapAngle(s.Yaw + VMath.WrapAngle(sy - s.Yaw) * 0.25)
			s.Pitch += (sp - s.Pitch) * 0.25
		end
		local now = os.clock()
		if now - s.LastAim > 1 / 15 then
			s.LastAim = now
			InputRemote:FireServer("Aim", s.AimPoint)
		end
	end
	Visuals.Local = { Model = model, Yaw = s.Yaw, Pitch = s.Pitch, Controls = controls, Sim = s.Sim }

	-- driving input -> server (for others' visuals / fallback); physics run locally in PreSimulation
	if s.Driver then
		local thr = (if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then 1 else 0)
		local steer = (if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then 1 else 0)
		for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if st.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(st.Position.X) > 0.15 then
				steer = st.Position.X
			end
		end
		if UserInputService:GetFocusedTextBox() then
			thr, steer = 0, 0
		end
		if s.Cfg.Drive.Kind == "Flight" then
			-- drone: pure mouse flight — it faces and flies where you look (W thrust, S back, A/D strafe)
			s.Input = { Throttle = if destroyed then 0 else thr, Steer = if destroyed then 0 else steer, Brake = false,
				Yaw = s.CamYaw, Pitch = s.CamPitch, Piloted = not destroyed }
		else
			-- Halo-style: driving forward, the vehicle steers itself toward where the camera looks.
			-- A / D still steer by hand (and win); reversing is steered by hand only.
			local csa = s.Cfg.Drive.CameraSteerAngle
			if Config.Interact.CameraSteer and csa and thr > 0.05 and math.abs(steer) < 0.05 and not destroyed then
				local lv = root.CFrame.LookVector
				local heading = math.atan2(-lv.X, -lv.Z)
				local err = VMath.WrapAngle(s.CamYaw - heading) -- > 0: the camera is to the left
				steer = math.clamp(-err / math.rad(csa), -1, 1)
			end
			s.Input = { Throttle = if destroyed then 0 else thr, Steer = if destroyed then 0 else steer, Brake = s.Brake or destroyed }
		end
		local now = os.clock()
		local key = ("%.2f %.2f %s"):format(s.Input.Throttle, s.Input.Steer, tostring(s.Input.Brake))
		if (key ~= s.LastSentInput and now - s.LastDrive > 0.1) or now - s.LastDrive > 0.5 then
			s.LastDrive = now
			s.LastSentInput = key
			InputRemote:FireServer("Drive", s.Input.Throttle, s.Input.Steer, s.Input.Brake)
		end
	end

	-- HUD
	local info = {
		Model = model, Speed = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector),
		SeatName = s.Seat:GetAttribute("SeatName"), Controls = controls, Driver = s.Driver,
		SeatList = model.Seats:GetChildren(),
	}
	if controls then
		local m = VMath.Muzzle(root.CFrame, model, s.Yaw, s.Pitch)
		local bhit = Workspace:Raycast(m.Position, m.LookVector * 1500, rayParams)
		local bp = if bhit then bhit.Position else m.Position + m.LookVector * 1500
		local sp, onScreen = camera:WorldToViewportPoint(bp)
		info.BarrelScreen = if onScreen then Vector2.new(sp.X, sp.Y) else nil
		local want = (s.AimPoint - m.Position)
		info.Aligned = want.Magnitude > 1 and m.LookVector:Dot(want.Unit) > math.cos(math.rad(1.5))
	end
	-- homing lock (drone): the server's chosen target
	local lockV = model:FindFirstChild("Lock")
	local tgt = lockV and lockV.Value
	if controls and tgt and tgt.Parent then
		local part = if tgt:IsA("Model") then (tgt:FindFirstChild("HumanoidRootPart") or tgt.PrimaryPart) else tgt
		if part and part:IsA("BasePart") then
			local sp, on = camera:WorldToViewportPoint(part.Position)
			if on then
				info.LockScreen = Vector2.new(sp.X, sp.Y)
			end
		end
	end
	hud:Update(info)
	if os.clock() - s.LastCrew > 0.25 then
		s.LastCrew = os.clock()
		hud:SetCrew(model, s.Seat:GetAttribute("SeatIndex"))
	end
end

local function stepExitBlend()
	local e = exitBlend
	local ch = player.Character
	local head = ch and ch:FindFirstChild("Head") :: BasePart?
	local t = math.clamp((os.clock() - e.Start) / 0.35, 0, 1)
	if not head or t >= 1 then
		exitBlend = nil
		camera.CameraType = Enum.CameraType.Custom
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local look = e.From.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local to = CFrame.lookAt(head.Position, head.Position + (if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis))
	camera.CFrame = e.From:Lerp(to, ease(t))
end

RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Camera.Value + 20, function(dt)
	if session then
		stepSession(dt)
	elseif exitBlend then
		stepExitBlend()
	end
	Visuals.Step(dt)
	FX.StepShells(dt)
end)

-- driver physics: before every physics step on this machine (we own the vehicle)
local preSim = (RunService :: any).PreSimulation or RunService.Stepped
preSim:Connect(function(a, b)
	local dt = if typeof(b) == "number" then b else a
	local s = session
	if s and s.Driver and s.Sim and s.Model.Parent and not s.Model:GetAttribute("Destroyed") then
		s.Sim:Step(dt, s.Input)
	end
end)

-- ─── entering: F reaches the vehicle prompt ─────────────────────────────
-- The weapon client binds F (Inspect) at priority 3000 and sinks it, so the ProximityPrompt never
-- sees the key. While a vehicle's prompt is on screen, take F (and the gamepad key) above that and
-- drive the prompt ourselves; when it hides, F goes back to Inspect.
local ENTER_BIND = "VantageVehicleEnter"
local shownPrompt: ProximityPrompt? = nil
local function onEnterKey(_, state: Enum.UserInputState)
	local pr = shownPrompt
	if not pr or not pr.Parent or session then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		pr:InputHoldBegin()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		pr:InputHoldEnd()
	end
	return Enum.ContextActionResult.Sink
end
ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	if prompt.Name == "EnterPrompt" and prompt:FindFirstAncestorWhichIsA("Model") and prompt:FindFirstAncestorWhichIsA("Model"):GetAttribute("VehicleType") then
		shownPrompt = prompt
		ContextActionService:BindActionAtPriority(ENTER_BIND, onEnterKey, false, 4000, Config.Interact.Key, Config.Interact.GamepadKey)
	end
end)
ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
	if prompt == shownPrompt then
		shownPrompt = nil
		ContextActionService:UnbindAction(ENTER_BIND)
	end
end)

-- ─── server events ───────────────────────────────────────────────────────
EventRemote.OnClientEvent:Connect(function(kind: string, a, b, c, d, e)
	if kind == "Shell" then
		FX.Shell(a, b, c, d, e)
	elseif kind == "Impact" then
		FX.Impact(a, b, c, d, e)
	elseif kind == "Shots" then
		FX.Shots(a, b)
	elseif kind == "Destroyed" then
		FX.Destroyed(a, b)
	elseif kind == "HitConfirm" then
		-- a = amount, b = "Infantry" | "Shield" | "Hull", c = world position, d = kill / destroyed
		if type(a) == "number" and type(b) == "string" then
			hitfx:Confirm(a, b, if typeof(c) == "Vector3" then c else nil, d == true)
			if session then
				FX.Shake = math.max(FX.Shake, if d then 0.9 else 0.18)
			end
		end
	elseif kind == "ShieldHit" then
		Visuals.ShieldHit(a, b, c or 0, d == true)
	elseif kind == "Hull" then
		-- a = amount, b = position, c = all of it stopped by the shield
		hud:HullHit(a or 0, c == true)
		if typeof(b) == "Vector3" and not c then
			FX.HullHit(b)
		end
		FX.Shake = math.max(FX.Shake, math.clamp((a or 0) / 300, 0.15, 1.6) * (if c then 0.5 else 1))
	end
end)
