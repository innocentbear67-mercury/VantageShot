--[[
	VANTAGE — ThirdPersonRig (client, every other character)
	What other players see. Each client poses every armed character itself (joint Transforms
	never replicate), driven only by server-set character attributes:
		VantageWeapon  weapon id ("Vanguard", ...) VantageAim  aim pitch (deg, ~12 Hz)
		VantageADS     aiming down sights          VantageAction "<Clip>:<serverTime>"
	Rifle: the world model rides a Motor6D on the UpperTorso (server). Here the upper body blades
	into a rifle stance and pitches with the aim, the gun follows the aim + ADS raise + the shared
	clip (reload) + a firing kick, and BOTH hands are placed on its grips with the same two-bone IK
	the first-person arms use (ArmRig). The magazine motor plays the reload's Mag track.
	Knife: the knife rides a Motor6D on the RightHand; the right arm is IK-driven to the hold /
	slash / stab / inspect track and the blade + bite hinges play the same clip as first person.
	Runs on RunService.Stepped, after the Animator, so it layers on top of locomotion.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Weapons = ReplicatedStorage.Vantage.Weapons
local Config = require(Weapons.WeaponConfig)
local ArmRig = require(Weapons.ArmRig)
local WeaponClips = require(Weapons.WeaponClips)

local rad = math.rad
local A = CFrame.Angles

local ThirdPersonRig = {}
local records: { [Model]: any } = {}
local started = false

local function expAlpha(rate, dt)
	return 1 - math.exp(-rate * dt)
end

local function joint(character: Model, partName: string, jointName: string)
	local part = character:FindFirstChild(partName)
	local j = part and part:FindFirstChild(jointName)
	if j and (j:IsA("AnimationConstraint") or j:IsA("Motor6D")) then
		return j
	end
	return nil
end

-- read-back Transforms are not bit-identical to what was written, so compare with a tolerance
local function nearly(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3
		and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

-- the joint's animation value this frame (without our own layer from last frame)
local function animBase(rec, key: string, j): CFrame
	local base = j.Transform
	local last = rec.Written[key]
	if last and nearly(base, last.Written) then
		base = last.Base -- the Animator didn't write this joint this frame: reuse its last value
	end
	return base
end

-- layer an extra rotation on a joint the Animator may also drive, without accumulating
local function layered(rec, key: string, j, extra: CFrame): CFrame
	local base = animBase(rec, key, j)
	local t = base * extra
	j.Transform = t
	rec.Written[key] = { Written = t, Base = base }
	return t
end

local function track(character: Model)
	if records[character] or character == Players.LocalPlayer.Character then
		return
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hrp or not hum or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	character:WaitForChild("RightHand", 5)
	character:WaitForChild("LeftHand", 5)
	local rec = {
		Character = character,
		Humanoid = hum,
		Root = hrp,
		Joints = {
			Root = joint(character, "LowerTorso", "Root"),
			Waist = joint(character, "UpperTorso", "Waist"),
			Neck = joint(character, "Head", "Neck"),
			RightShoulder = joint(character, "RightUpperArm", "RightShoulder"),
			RightElbow = joint(character, "RightLowerArm", "RightElbow"),
			RightWrist = joint(character, "RightHand", "RightWrist"),
			LeftShoulder = joint(character, "LeftUpperArm", "LeftShoulder"),
			LeftElbow = joint(character, "LeftLowerArm", "LeftElbow"),
			LeftWrist = joint(character, "LeftHand", "LeftWrist"),
		},
		Arms = { Right = ArmRig.Read(character, "Right", 1), Left = ArmRig.Read(character, "Left", 1) },
		Written = {},
		Pitch = 0,
		ADS = 0,
		Blade = 0,
		KickP = Vector3.zero,
		KickV = Vector3.zero,
		Active = false,
	}
	records[character] = rec
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			records[character] = nil
		end
	end)
end

local function parseAction(s)
	if type(s) ~= "string" then
		return nil, nil
	end
	local name, t = string.match(s, "^(%a+%d?):([%d%.]+)$")
	return name, tonumber(t)
end

-- ─── third-person knife swing trail (shot overhaul stage 6) ───────────────────────────
-- Same style as the first-person trail (KnifeViewmodel:_trail): the skin's Swing spec, or the finish colours.
local SkinFXOk, SkinFX = pcall(require, Weapons:WaitForChild("SkinFX"))
local VFXKitOk, VFXKit = pcall(require, Weapons:WaitForChild("VFXKit"))
local knifeTrails = {} -- strong (weak Instance keys get dropped by the GC); cleared when the knife is destroyed
local SWING_CLIPS = { Slash1 = true, Slash2 = true, Stab = true }
local function tpKnifeTrail(knife: Model): Trail?
	local key = tostring(knife:GetAttribute("Skin"))
	local rec = knifeTrails[knife]
	if not rec then
		local old = knife:FindFirstChild("TPSwingTrail", true)
		if old then
			rec = { key = old:GetAttribute("Key"), trail = old, a0 = old.Attachment0, a1 = old.Attachment1 }
			knifeTrails[knife] = rec
		end
	end
	if rec and rec.key == key and rec.trail.Parent then
		return rec.trail
	end
	if rec and rec.trail then
		rec.trail:Destroy()
		if rec.a0 then rec.a0:Destroy() end
		if rec.a1 then rec.a1:Destroy() end
	else
		knife.Destroying:Once(function() knifeTrails[knife] = nil end)
	end
	knifeTrails[knife] = nil
	local handle = knife.PrimaryPart
	local blade = knife:FindFirstChild("KnifeMesh", true) :: BasePart?
	if not (blade and blade:IsA("BasePart")) then
		local best = 0
		for _, p in knife:GetDescendants() do
			if p:IsA("BasePart") and p ~= handle and p.Size.Magnitude > best then blade, best = p, p.Size.Magnitude end
		end
	end
	if not (blade and handle) then return nil end
	local tip = handle:FindFirstChild("Tip") :: Attachment?
	local grip = handle:FindFirstChild("Grip") :: Attachment?
	local p0, p1
	if tip and grip then
		p0, p1 = grip.WorldPosition:Lerp(tip.WorldPosition, 0.35), tip.WorldPosition
	else
		-- the blade's long axis, tip = the end away from the handle
		local sz = blade.Size
		local ax = if sz.X >= sz.Y and sz.X >= sz.Z then blade.CFrame.RightVector * sz.X / 2
			elseif sz.Y >= sz.Z then blade.CFrame.UpVector * sz.Y / 2 else blade.CFrame.LookVector * sz.Z / 2
		local e1, e2 = blade.Position + ax, blade.Position - ax
		if (e2 - handle.Position).Magnitude > (e1 - handle.Position).Magnitude then e1, e2 = e2, e1 end
		p0, p1 = e2:Lerp(e1, 0.35), e1
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TPSwingA"
	a0.Position = blade.CFrame:PointToObjectSpace(p0)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TPSwingB"
	a1.Position = blade.CFrame:PointToObjectSpace(p1)
	a1.Parent = blade
	local def = SkinFXOk and SkinFX.Get(knife:GetAttribute("SkinFX")) or nil
	local sw = def and def.Swing
	if not sw then
		local f = VFXKitOk and VFXKit.Finishes[knife:GetAttribute("Skin") or ""] or nil
		local c = (f and (f.TracerColor or f.Hot)) or Color3.fromRGB(235, 240, 255)
		sw = { c1 = c, c2 = (f and f.Warm) or c, Transp = if f and next(f) then 0.35 else 0.6 }
	end
	local t = Instance.new("Trail")
	t.Name = "TPSwingTrail"
	t:SetAttribute("Key", key)
	t.Attachment0, t.Attachment1 = a0, a1
	t.FaceCamera = false
	t.Lifetime = sw.Life or 0.16
	t.MinLength = 0.02
	t.LightEmission = sw.Emission or 1
	t.LightInfluence = 0
	t.Color = sw.Seq or ColorSequence.new(sw.c1, sw.c2 or sw.c1)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, sw.Transp or 0.25), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new(1, 0.4)
	if sw.Tex then
		t.Texture = sw.Tex
		t.TextureMode = sw.Mode or Enum.TextureMode.Stretch
		t.TextureLength = sw.TexLen or 1
	end
	t.Enabled = false
	t.Parent = blade
	knifeTrails[knife] = { key = key, trail = t, a0 = a0, a1 = a1 }
	return t
end

local function clipPose(rec, weaponId: string, now: number)
	local name, t0 = parseAction(rec.Character:GetAttribute("VantageAction"))
	if not name then
		return nil
	end
	local clip = WeaponClips.Get(weaponId, name)
	if not clip then
		return nil
	end
	local w = Config.Weapons[weaponId]
	local length = clip.Length
	if name == "Reload" then
		length = w.ReloadTime
	elseif name == "Equip" then
		length = w.EquipTime
	elseif name == "Inspect" then
		length = w.InspectTime or clip.Length
	end
	local t = (now - t0) * (clip.Length / length)
	if t < 0 or t > clip.Length then
		return nil
	end
	return WeaponClips.Sample(clip, t)
end

local function poseArm(rec, side: string, upperTorsoCF: CFrame, handCF: CFrame, pole: Vector3)
	local arm = rec.Arms[side]
	local J = rec.Joints
	local sh, el, wr = J[side .. "Shoulder"], J[side .. "Elbow"], J[side .. "Wrist"]
	if not (arm and sh and el and wr and sh:IsA("AnimationConstraint") == el:IsA("AnimationConstraint")) then
		return
	end
	local a0 = if sh:IsA("AnimationConstraint") then sh.Attachment0 else nil
	local shoulderPos = if a0 then (upperTorsoCF * a0.CFrame).Position else (upperTorsoCF * sh.C0).Position
	local upper, lower, hand = ArmRig.Solve(arm, shoulderPos, handCF, pole)
	local t1 = ArmRig.JointTransform(sh, upperTorsoCF, upper)
	local t2 = ArmRig.JointTransform(el, upper, lower)
	local t3 = ArmRig.JointTransform(wr, lower, hand)
	if t1 and t2 and t3 then
		sh.Transform = t1
		el.Transform = t2
		wr.Transform = t3
	end
end

local function step(_, dt)
	if ThirdPersonRig.Suspended then
		return -- OperativeIntro poses every character itself for the length of the Intro phase
	end
	local now = Workspace:GetServerTimeNow()
	-- 2026-11-20 perf: characters off screen (or very far) skip the arm IK this frame; nobody sees them
	local cam = Workspace.CurrentCamera
	local camCF = cam.CFrame
	local camPos, camLook = camCF.Position, camCF.LookVector
	local halfFov = math.rad(cam.FieldOfView) * 0.5
	local vp = cam.ViewportSize
	local cosLimit = math.cos(math.min(math.pi * 0.49, math.atan(math.tan(halfFov) * math.max(1, vp.X / math.max(vp.Y, 1)) * 1.25) + 0.12))
	local me = Players.LocalPlayer.Character
	for character, rec in records do
		if character ~= me and rec.Root then
			local to = rec.Root.Position - camPos
			local d = to.Magnitude
			if d > 6 and (d > 400 or to:Dot(camLook) / d < cosLimit) then
				continue
			end
		end
		local weaponId = character:GetAttribute("VantageWeapon")
		local hum = rec.Humanoid
		local J = rec.Joints
		if not weaponId or hum.Health <= 0 or character:GetAttribute("VantageDeath") or character:GetAttribute("VantageHolstered") or not (J.Root and J.Waist) then
			if rec.Active then
				rec.Active = false
				rec.Written = {}
				local gun = character:FindFirstChild("VantageWorldWeapon")
				local gm = gun and gun.PrimaryPart and gun.PrimaryPart:FindFirstChild("VantageGunMotor")
				if gm then
					gm.Transform = CFrame.identity -- rest on the sling, not in the last aim pose
				end
			end
			continue
		end
		rec.Active = true
		local w = Config.Weapons[weaponId]
		local tp = w.ThirdPerson
		local isGun = w.Kind == "Gun"

		-- replicated aim, smoothed
		local pitch = math.clamp(character:GetAttribute("VantageAim") or 0, -80, 80)
		rec.Pitch += (pitch - rec.Pitch) * expAlpha(14, dt)
		local adsT = if character:GetAttribute("VantageADS") and isGun then 1 else 0
		rec.ADS += (adsT - rec.ADS) * expAlpha(10, dt)
		local bladeT = if isGun then (tp.BladeAngle or 0) else 0
		rec.Blade += (bladeT - rec.Blade) * expAlpha(8, dt)

		-- firing kick spring
		local kv = rec.KickV + (-260 * rec.KickP - 22 * rec.KickV) * dt
		rec.KickV = kv
		rec.KickP += kv * dt

		-- torso chain (FK from the root so this frame's values are used)
		local share = if isGun then (tp.WaistPitchShare or 0.35) else 0.3
		local waistPitch = rad(rec.Pitch * share)
		local blade = rad(rec.Blade)
		local lowerTorso = ArmRig.JointChild(J.Root, rec.Root.CFrame, J.Root.Transform)
		local waistBase = animBase(rec, "Waist", J.Waist)
		local waistT = layered(rec, "Waist", J.Waist, A(waistPitch, -blade, 0))
		local upperTorso = ArmRig.JointChild(J.Waist, lowerTorso, waistT)
		local aimFrame = ArmRig.JointChild(J.Waist, lowerTorso, waistBase * A(waistPitch, 0, 0))
		if J.Neck then
			layered(rec, "Neck", J.Neck, A(rad(rec.Pitch * (1 - share) * 0.8), blade, 0))
		end
		if not (upperTorso and aimFrame) then
			continue
		end
		local up = upperTorso
		local poleR = up:VectorToWorldSpace(Vector3.new(0.7, -1, 0.35))
		local poleL = up:VectorToWorldSpace(Vector3.new(-0.8, -1, 0.1))
		local clip = clipPose(rec, weaponId, now)
		local posScale = (tp.Scale or 0.7) / (w.Viewmodel and w.Viewmodel.Scale or 0.6)

		-- the holstered weapon: knife folded shut on the hip / slung rifle at rest
		local knifeModel = character:FindFirstChild("VantageWorldKnife")
		local knifeHandle = knifeModel and knifeModel.PrimaryPart
		local rifleModel = character:FindFirstChild("VantageWorldWeapon")
		local rifleBody = rifleModel and rifleModel.PrimaryPart
		if isGun and knifeHandle then
			local bh = knifeHandle:FindFirstChild("BladeHinge")
			local ih = knifeHandle:FindFirstChild("BiteHinge")
			if bh then
				bh.Transform = A(0, 0, math.pi)
			end
			if ih then
				ih.Transform = CFrame.identity
			end
		elseif not isGun and rifleBody then
			local gm = rifleBody:FindFirstChild("VantageGunMotor")
			local mm = rifleBody:FindFirstChild("VantageMagMotor")
			if gm then
				gm.Transform = CFrame.identity
			end
			if mm then
				mm.Transform = CFrame.identity
			end
		end

		if isGun then
			local gun = character:FindFirstChild("VantageWorldWeapon")
			local body = gun and gun.PrimaryPart
			local motor = body and body:FindFirstChild("VantageGunMotor")
			if motor and motor.Part0 and motor.Part0.Name == "UpperTorso" then
				local pivot = tp.AimPivot or Vector3.new(0.4, 0.45, -0.25)
				local restPitch = rad(rec.Pitch * (1 - share))
				local clipGun = CFrame.identity
				if clip and clip.Tracks.Gun then
					local g = clip.Tracks.Gun
					clipGun = CFrame.new(g.Position * posScale) * g.Rotation
				end
				local kick = CFrame.new(0, rec.KickP.Y * 0.4, rec.KickP.Z) * A(rad(rec.KickP.X), 0, 0)
				local gunCF = aimFrame * CFrame.new(pivot) * A(restPitch, 0, 0) * CFrame.new(-pivot)
					* tp.Hold * CFrame.identity:Lerp(tp.ADSRaise or CFrame.identity, rec.ADS) * clipGun * kick
				local t = ArmRig.JointTransform(motor, up, gunCF)
				if t then
					motor.Transform = t
				end
				-- magazine (reload)
				local magMotor = body:FindFirstChild("VantageMagMotor")
				local magCF = nil
				if magMotor then
					local m = CFrame.identity
					if clip and clip.Tracks.Mag then
						local mt = clip.Tracks.Mag
						m = CFrame.new(mt.Position * posScale) * mt.Rotation
					end
					magMotor.Transform = m
					local magBody = magMotor.Part1
					if magBody then
						magCF = gunCF * magMotor.C0 * m * magMotor.C1:Inverse()
					end
				end
				-- hands on the grips
				local gr = body:FindFirstChild("Handle")
				local gl = body:FindFirstChild("SupportTP") or body:FindFirstChild("Support")
				if gr and gl and rec.Arms.Right and rec.Arms.Left then
					local rightHand = ArmRig.HandFromGrip(rec.Arms.Right, gunCF * gr.CFrame)
					local leftHand = ArmRig.HandFromGrip(rec.Arms.Left, gunCF * gl.CFrame)
					local onMag = clip and clip.Weights.LeftOnMag or 0
					if onMag > 0 and magCF and magMotor.Part1 then
						local mg = magMotor.Part1:FindFirstChild("MagGrip")
						if mg then
							leftHand = leftHand:Lerp(ArmRig.HandFromGrip(rec.Arms.Left, magCF * mg.CFrame), onMag)
						end
					elseif onMag > 0 and body:FindFirstChild("Magazine") then
						-- single-mesh gun: hand to the mag well, following the clip's Mag track
						local m = CFrame.identity
						if clip and clip.Tracks.Mag then
							local mt = clip.Tracks.Mag
							m = CFrame.new(mt.Position * posScale) * mt.Rotation
						end
						local well = gunCF * m * body.Magazine.CFrame
						leftHand = leftHand:Lerp(ArmRig.HandFromGrip(rec.Arms.Left, well), onMag)
					end
					poseArm(rec, "Right", up, rightHand, poleR)
					poseArm(rec, "Left", up, leftHand, poleL)
				end
			end
		else
			-- knife: right hand to the hold (+ clip), hinges from the clip
			local handTrack = clip and clip.Tracks.Hand or CFrame.identity
			local handCF = aimFrame * CFrame.new(handTrack.Position * posScale) * tp.Hold * handTrack.Rotation
			poseArm(rec, "Right", up, handCF, poleR)
			local knife = character:FindFirstChild("VantageWorldKnife")
			local handle = knife and knife.PrimaryPart
			if handle then
				local bh = handle:FindFirstChild("BladeHinge")
				local ih = handle:FindFirstChild("BiteHinge")
				local braw = clip and clip.Raw.Blade
				local iraw = clip and clip.Raw.Bite
				if bh then
					bh.Transform = A(0, 0, rad(braw and braw.Z or 0))
				end
				if ih then
					ih.Transform = A(0, 0, rad(iraw and iraw.Z or 0))
				end
				-- swing trail while a slash / stab clip is in its first 0.32 s
				local tr = tpKnifeTrail(knife)
				if tr then
					local nm, t0 = parseAction(character:GetAttribute("VantageAction"))
					local el = if t0 then now - t0 else -1
					local on = nm ~= nil and SWING_CLIPS[nm] == true and el >= 0 and el < 0.32
					if tr.Enabled ~= on then tr.Enabled = on end
				end
			end
		end
	end
end

-- called for another player's shot (server "Shot" broadcast)
function ThirdPersonRig.OnShot(character: Model)
	local rec = records[character]
	if rec then
		rec.KickV += Vector3.new(14, 0.5, 2.2)
	end
end

-- pose a model that isn't a player character (the main menu's avatar showcase)
function ThirdPersonRig.Track(model: Model)
	task.spawn(track, model)
end

function ThirdPersonRig.Start()
	if started then
		return
	end
	started = true
	local function onPlayer(plr: Player)
		plr.CharacterAdded:Connect(function(c)
			task.spawn(track, c)
		end)
		if plr.Character then
			task.spawn(track, plr.Character)
		end
	end
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	Players.PlayerAdded:Connect(onPlayer)
	-- Studio training dummies (armed ones show exactly what other players see)
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		CollectionService:GetInstanceAddedSignal("VantageDummy"):Connect(function(m)
			task.spawn(track, m)
		end)
		for _, m in CollectionService:GetTagged("VantageDummy") do
			task.spawn(track, m)
		end
	end
	RunService.Stepped:Connect(step)
end

return ThirdPersonRig
