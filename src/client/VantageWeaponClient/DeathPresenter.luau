--[[
	VANTAGE — DeathPresenter (client)
	Controlled death animations instead of a limp physics ragdoll. On death the server keeps the
	joints rigid, plants the root on the ground and sets character attribute
	"VantageDeath" = "<Style>:<serverTime>" (style from the killing hit: direction + headshot).
	Every client then plays the same keyframed collapse on the joint Transforms:
		Back     shot from the front: stagger, knees give, fall onto the back
		Front    shot from behind: lurch, knees buckle, fall forward
		Crumple  headshot: legs fold straight down, then tip to the side
		Spin     side hit: twist toward the shot and fall sideways
		Overload the Crimson Core Overload (CoreOverloadConfig, the default): stagger away from the
		         fatal hit, struggle and spasm, the chest core builds, detonation; the body is gone
		         into the blast (procedural pose here, effects in CoreOverloadFX)
		Elim     (2026-11-14, the default) the KILLER's equipped elimination effect (EffectCatalog /
		         ElimFX) plays on the body; character attribute "VantageDeathFX" = effect id
	The body fades out shortly before the respawn. For the LOCAL player it also runs a short
	death camera (looking at your body), the "eliminated by" card and a fade into the respawn.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local OV = require(ReplicatedStorage.Vantage.Elimination.CoreOverloadConfig)
local CoreOverloadFX = require(script.Parent.CoreOverloadFX)
local EffectCatalog = require(ReplicatedStorage.Vantage.Elimination.EffectCatalog)
local ElimFX = nil -- required on first use
local ELIM_MAX_DISTANCE = 450
-- in a match the effect is seen from across the map: rings, glows, shards and particles are drawn
-- this much bigger than in the shop preview (the body itself stays life-size)
local ELIM_MATCH_SCALE = 2

local rad = math.rad
local V = Vector3.new

local DeathPresenter = {}
local active: { [Model]: any } = {}
local started = false

-- keyframes: t, Drop (0..1 of the drop height), and joint rotations in degrees (X, Y, Z)
local STYLES = {
	Back = {
		Length = 0.95,
		Keys = {
			{ t = 0 },
			{ t = 0.12, Root = V(10, 0, 0), Waist = V(12, 0, 0), Neck = V(18, 0, 0), RightShoulder = V(25, 0, 25), LeftShoulder = V(25, 0, -25) },
			{ t = 0.34, Drop = 0.3, Root = V(26, 0, 0), Waist = V(10, 0, 0), Neck = V(10, 0, 0), RightHip = V(38, 0, 0), LeftHip = V(30, 0, 0), RightKnee = V(-55, 0, 0), LeftKnee = V(-45, 0, 0), RightShoulder = V(40, 0, 45), LeftShoulder = V(35, 0, -45) },
			{ t = 0.7, Drop = 1, Root = V(84, 0, 4), Waist = V(4, 0, 0), Neck = V(8, 0, 0), RightHip = V(16, 0, 0), LeftHip = V(26, 0, 0), RightKnee = V(-22, 0, 0), LeftKnee = V(-34, 0, 0), RightShoulder = V(20, 0, 70), LeftShoulder = V(10, 0, -80) },
			{ t = 0.82, Drop = 0.97, Root = V(80, 0, 4) },
			{ t = 0.95, Drop = 1, Root = V(84, 0, 4), Waist = V(4, 0, 0), Neck = V(8, 0, 0), RightHip = V(16, 0, 0), LeftHip = V(26, 0, 0), RightKnee = V(-22, 0, 0), LeftKnee = V(-34, 0, 0), RightShoulder = V(20, 0, 70), LeftShoulder = V(10, 0, -80) },
		},
	},
	Front = {
		Length = 0.95,
		Keys = {
			{ t = 0 },
			{ t = 0.12, Root = V(-12, 0, 0), Waist = V(-10, 0, 0), Neck = V(-12, 0, 0), RightShoulder = V(-10, 0, 10), LeftShoulder = V(-10, 0, -10) },
			{ t = 0.36, Drop = 0.35, Root = V(-28, 0, 0), Waist = V(-18, 0, 0), RightHip = V(55, 0, 0), LeftHip = V(48, 0, 0), RightKnee = V(-85, 0, 0), LeftKnee = V(-75, 0, 0), RightShoulder = V(40, 0, 15), LeftShoulder = V(45, 0, -15) },
			{ t = 0.72, Drop = 1, Root = V(-86, 0, -3), Waist = V(-4, 0, 0), Neck = V(-14, 18, 0), RightHip = V(8, 0, 0), LeftHip = V(14, 0, 0), RightKnee = V(-14, 0, 0), LeftKnee = V(-24, 0, 0), RightShoulder = V(150, 0, 30), LeftShoulder = V(140, 0, -35) },
			{ t = 0.84, Drop = 0.97, Root = V(-82, 0, -3) },
			{ t = 0.95, Drop = 1, Root = V(-86, 0, -3), Waist = V(-4, 0, 0), Neck = V(-14, 18, 0), RightHip = V(8, 0, 0), LeftHip = V(14, 0, 0), RightKnee = V(-14, 0, 0), LeftKnee = V(-24, 0, 0), RightShoulder = V(150, 0, 30), LeftShoulder = V(140, 0, -35) },
		},
	},
	Crumple = {
		Length = 1.0,
		Keys = {
			{ t = 0 },
			{ t = 0.1, Neck = V(-20, 0, 0), Waist = V(-8, 0, 0) },
			{ t = 0.4, Drop = 0.52, Root = V(-8, 0, 0), Waist = V(-28, 0, 0), Neck = V(-30, 0, 0), RightHip = V(84, 0, 4), LeftHip = V(80, 0, -4), RightKnee = V(-125, 0, 0), LeftKnee = V(-120, 0, 0), RightShoulder = V(10, 0, 8), LeftShoulder = V(10, 0, -8) },
			{ t = 0.78, Drop = 1, Root = V(-20, 10, 78), Waist = V(-14, 0, 0), Neck = V(-10, 0, 10), RightHip = V(60, 0, 0), LeftHip = V(50, 0, 0), RightKnee = V(-90, 0, 0), LeftKnee = V(-70, 0, 0), RightShoulder = V(30, 0, 50), LeftShoulder = V(20, 0, -20) },
			{ t = 0.88, Drop = 0.97, Root = V(-20, 10, 74) },
			{ t = 1.0, Drop = 1, Root = V(-20, 10, 78), Waist = V(-14, 0, 0), Neck = V(-10, 0, 10), RightHip = V(60, 0, 0), LeftHip = V(50, 0, 0), RightKnee = V(-90, 0, 0), LeftKnee = V(-70, 0, 0), RightShoulder = V(30, 0, 50), LeftShoulder = V(20, 0, -20) },
		},
	},
	SpinL = {
		Length = 0.95,
		Keys = {
			{ t = 0 },
			{ t = 0.16, Root = V(0, 30, 6), Waist = V(0, 18, 0), RightShoulder = V(20, 0, 30), LeftShoulder = V(10, 0, -40) },
			{ t = 0.42, Drop = 0.4, Root = V(-6, 55, 24), Waist = V(-10, 14, 0), RightHip = V(40, 0, 0), LeftHip = V(30, 0, 0), RightKnee = V(-60, 0, 0), LeftKnee = V(-50, 0, 0) },
			{ t = 0.76, Drop = 1, Root = V(-8, 70, 84), Waist = V(-6, 6, 0), Neck = V(0, 0, -12), RightHip = V(20, 0, 0), LeftHip = V(36, 0, 0), RightKnee = V(-30, 0, 0), LeftKnee = V(-52, 0, 0), RightShoulder = V(80, 0, 20), LeftShoulder = V(10, 0, -60) },
			{ t = 0.86, Drop = 0.97, Root = V(-8, 70, 80) },
			{ t = 0.95, Drop = 1, Root = V(-8, 70, 84), Waist = V(-6, 6, 0), Neck = V(0, 0, -12), RightHip = V(20, 0, 0), LeftHip = V(36, 0, 0), RightKnee = V(-30, 0, 0), LeftKnee = V(-52, 0, 0), RightShoulder = V(80, 0, 20), LeftShoulder = V(10, 0, -60) },
		},
	},
}
-- mirrored side fall
do
	local s = { Length = STYLES.SpinL.Length, Keys = {} }
	for _, k in STYLES.SpinL.Keys do
		local m = { t = k.t, Drop = k.Drop }
		for name, v in k do
			if typeof(v) == "Vector3" then
				local mirrored = string.gsub(string.gsub(string.gsub(name, "Right", "#"), "Left", "Right"), "#", "Left")
				m[mirrored] = V(v.X, -v.Y, -v.Z)
			end
		end
		table.insert(s.Keys, m)
	end
	STYLES.SpinR = s
end
DeathPresenter.Styles = STYLES

-- ─── Crimson Core Overload: procedural pose (same clock + seed on every client) ───────────
local OVERLOAD = { Length = OV.Length, Overload = true }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function ease(a: number): number
	return a * a * (3 - 2 * a)
end

-- joint angles (degrees) at time t; rec.SX / rec.SZ = push from the fatal hit in body space
local function overloadPose(rec, name: string, t: number): Vector3
	local seed = rec.Seed
	local hit = ease(clamp01(t / OV.Impact)) * (1 - 0.65 * ease(clamp01((t - OV.Impact) / 0.45)))
	local struggle = ease(clamp01((t - OV.Impact) / 0.35))
	local charge = ease(clamp01((t - OV.Charge) / (OV.Detonate - OV.Charge)))
	local amp = 2 + 5 * struggle + 13 * charge -- tremor, building toward the detonation
	local function n(i: number, f: number): number
		return math.noise(seed + i * 7.31, t * f) * 2
	end
	-- spasms: held for a beat, then snapped to a new pose (mechanical, not floppy)
	local q = math.floor(t * 11)
	local function sp(i: number): number
		return math.noise(seed + i * 3.7, q * 0.61 + 0.5) * 2
	end
	local sx, sz = rec.SX, rec.SZ
	if name == "Root" then
		return V(14 * sx * hit + 5 * struggle * n(1, 2.5) + amp * 0.3 * n(2, 18) - 5 * charge, amp * 0.3 * n(3, 17), 10 * sz * hit + 5 * struggle * n(4, 2) + amp * 0.3 * n(5, 19))
	elseif name == "Waist" then
		return V(10 * sx * hit - 4 * struggle + amp * 0.5 * n(6, 20) - 14 * charge, 8 * struggle * n(7, 2) + amp * 0.4 * n(8, 21), amp * 0.4 * n(9, 22))
	elseif name == "Neck" then
		return V(16 * sx * hit + 10 * struggle * n(10, 3) + amp * 0.6 * n(11, 24) - 22 * charge, 18 * struggle * n(12, 2.2), amp * 0.5 * n(13, 23))
	elseif name == "RightShoulder" or name == "LeftShoulder" then
		local s = if name == "RightShoulder" then 1 else -1
		local i = if s == 1 then 20 else 30
		local jerk = struggle * (1 - charge)
		-- spasming arms, then thrown wide as the core takes over
		return V(18 * hit + 28 * jerk * sp(i) + amp * 0.5 * n(i + 1, 20) + 12 * charge, 14 * jerk * sp(i + 2), s * (16 + 20 * hit + 14 * jerk * sp(i + 3) + 48 * charge))
	elseif name == "RightElbow" or name == "LeftElbow" then
		local i = if name == "RightElbow" then 40 else 50
		return V(15 * hit + 30 * struggle * (0.5 + 0.5 * sp(i)) * (1 - 0.7 * charge) + amp * 0.4 * n(i + 1, 22), 0, 0)
	elseif name == "RightHip" or name == "LeftHip" or name == "RightKnee" or name == "LeftKnee" then
		local right = string.sub(name, 1, 5) == "Right"
		-- the knees give and catch, out of step with each other
		local k = struggle * (0.55 + 0.45 * (0.5 + 0.5 * n(if right then 60 else 70, 1.6))) + 0.25 * charge
		if string.find(name, "Hip", 1, true) then
			return V(30 * k + amp * 0.2 * n(if right then 61 else 71, 18), 0, 0)
		end
		return V(-55 * k, 0, 0)
	end
	return V()
end

local function overloadDrop(rec, t: number): number
	local struggle = ease(clamp01((t - OV.Impact) / 0.35))
	local charge = ease(clamp01((t - OV.Charge) / (OV.Detonate - OV.Charge)))
	return 0.16 * struggle + 0.06 * charge + 0.04 * struggle * math.noise(rec.Seed, t * 1.6)
end

local JOINTS = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm", LeftElbow = "LeftLowerArm",
	RightHip = "RightUpperLeg", LeftHip = "LeftUpperLeg",
	RightKnee = "RightLowerLeg", LeftKnee = "LeftLowerLeg",
}

local function smooth(a)
	return a * a * (3 - 2 * a)
end

local function sample(style, t: number, name: string): Vector3
	local keys = style.Keys
	local prevT, prevV = 0, V()
	for _, k in keys do
		local v = k[name]
		if v ~= nil or k.t == 0 then
			v = v or V()
			if t <= k.t then
				local u = smooth(math.clamp((t - prevT) / math.max(1e-4, k.t - prevT), 0, 1))
				return prevV:Lerp(v, u)
			end
			prevT, prevV = k.t, v
		end
	end
	return prevV
end

local function sampleDrop(style, t: number): number
	local prevT, prevV = 0, 0
	for _, k in style.Keys do
		if k.Drop ~= nil or k.t == 0 then
			local v = k.Drop or 0
			if t <= k.t then
				local u = smooth(math.clamp((t - prevT) / math.max(1e-4, k.t - prevT), 0, 1))
				return prevV + (v - prevV) * u
			end
			prevT, prevV = k.t, v
		end
	end
	return prevV
end

local function begin(character: Model)
	local value = character:GetAttribute("VantageDeath")
	if type(value) ~= "string" or active[character] then
		return
	end
	local styleName, t0 = string.match(value, "^(%a+):([%d%.]+)$")
	local overload = styleName == "Overload"
	local elim = styleName == "Elim"
	local style = if overload then OVERLOAD elseif elim then { Length = 0.05, Keys = { { t = 0 } } } else STYLES[styleName or ""] or STYLES.Back
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local joints = {}
	for name, partName in JOINTS do
		local part = character:FindFirstChild(partName)
		local j = part and part:FindFirstChild(name)
		if j and (j:IsA("AnimationConstraint") or j:IsA("Motor6D")) then
			joints[name] = j
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, Workspace:FindFirstChild("VantageWeaponFX") }
	local hit = Workspace:Raycast(root.Position, V(0, -12, 0), params)
	local groundY = if hit then hit.Position.Y else root.Position.Y - 3
	local parts, constraints, sockets = {}, {}, {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(parts, d)
		elseif d:IsA("AnimationConstraint") then
			table.insert(constraints, d)
		elseif d:IsA("BallSocketConstraint") then
			table.insert(sockets, d)
		end
	end
	active[character] = {
		Style = style,
		Start = tonumber(t0) or Workspace:GetServerTimeNow(),
		Joints = joints,
		Drop = math.max(0, (root.Position.Y - groundY) - 0.6),
		Parts = parts,
		Constraints = constraints,
		BallSockets = sockets,
		Base = {},
	}
	if elim then
		-- the body is handed to ElimFX (anchored copies play the effect); the real body stays hidden
		local rec = active[character]
		rec.Elim, rec.Vanished, rec.LastFade = true, true, 1
		for _, p in parts do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = 1
			else
				p.Transparency = 1
			end
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		local fx = character:GetAttribute("VantageDeathFX")
		fx = if EffectCatalog.Valid(fx) then fx else EffectCatalog.Default
		local _, dur = EffectCatalog.Timing(fx)
		local near = (root.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude <= ELIM_MAX_DISTANCE
		if near and Workspace:GetServerTimeNow() - rec.Start < dur then
			local isLocal = Players.LocalPlayer.Character == character
			local ok, err = pcall(function()
				ElimFX = ElimFX or require(script.Parent.ElimFX)
				ElimFX.Play(character, fx, {
					Start = rec.Start,
					Clock = function() return Workspace:GetServerTimeNow() end,
					HideRig = true, KeepRigHidden = true,
					SoundAt = if isLocal then nil else root.Position,
					Seed = math.floor(rec.Start * 1000) % 100000,
					Scale = ELIM_MATCH_SCALE,
					-- camera shake / colour grade only for the player who died: a killer (or anyone
					-- nearby) keeps a steady view to aim at the next target (2026-11-16)
					Screen = isLocal,
				})
			end)
			if not ok then
				warn("[DeathPresenter] elimination effect: " .. tostring(err))
			end
		end
	end
	if overload then
		local rec = active[character]
		rec.Seed = (rec.Start * 13.7) % 1000 -- same seed on every client: same spasms
		-- push away from the fatal hit, in the body's own space (back = shot from the front)
		local dir = character:GetAttribute("LastHitDir")
		local d = if typeof(dir) == "Vector3" and dir.Magnitude > 1e-3 then root.CFrame:VectorToObjectSpace(dir.Unit) else V(0, 0, 0.6)
		rec.SX = math.clamp(d.Z * 1.3, -1, 1)
		rec.SZ = math.clamp(-d.X * 1.3, -1, 1)
		local ok, err = pcall(CoreOverloadFX.Play, character, rec.Start)
		if not ok then
			warn("[DeathPresenter] overload effects: " .. tostring(err))
		end
	end
end

local function step()
	local now = Workspace:GetServerTimeNow()
	local respawn = Players.RespawnTime
	for character, rec in active do
		if not character:IsDescendantOf(game) then
			active[character] = nil
			continue
		end
		local t = math.clamp(now - rec.Start, 0, rec.Style.Length)
		-- the owning client's own death handling disables avatar joints locally (for a physics
		-- ragdoll) even though the server re-enabled them; keep them on so the pose renders
		for _, j in rec.Constraints do
			if not j.Enabled then
				j.Enabled = true
			end
		end
		for _, b in rec.BallSockets do
			if b.Enabled then
				b.Enabled = false
			end
		end
		local overload = rec.Style.Overload == true
		for name, j in rec.Joints do
			local r = if overload then overloadPose(rec, name, t) else sample(rec.Style, t, name)
			local cf = CFrame.Angles(rad(r.X), rad(r.Y), rad(r.Z))
			if name == "Root" then
				cf = CFrame.new(0, -rec.Drop * (if overload then overloadDrop(rec, t) else sampleDrop(rec.Style, t)), 0) * cf
			end
			j.Transform = cf
		end
		-- the body is gone into the detonation and stays hidden until the respawn removes it
		if rec.Elim or (overload and now - rec.Start >= OV.Detonate) then
			if not rec.Vanished then
				rec.Vanished = true
				rec.LastFade = 1 -- also tells the local death camera to stop re-showing the body
				for _, p in rec.Parts do
					if not p:IsA("BasePart") then
						p.Transparency = 1
					end
				end
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
			end
			for _, p in rec.Parts do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = 1
				end
			end
		end
		-- fade out just before the respawn
		local age = now - rec.Start
		local fade = math.clamp((age - (respawn - 0.55)) / 0.4, 0, 1)
		if fade > 0 and rec.LastFade ~= fade and not rec.Vanished then
			rec.LastFade = fade
			local lp = Players.LocalPlayer
			local isLocal = lp.Character == character
			for _, p in rec.Parts do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = math.max(if isLocal then 0 else p.LocalTransparencyModifier, fade)
				else
					p.Transparency = math.max(p.Transparency, fade)
				end
			end
		end
	end
end

local function watch(character: Model)
	character:GetAttributeChangedSignal("VantageDeath"):Connect(function()
		begin(character)
	end)
	if character:GetAttribute("VantageDeath") then
		begin(character)
	end
end

-- ─── local player death camera (returns a function that stops it, for DeathReplay) ───────────────────────────────────────────
function DeathPresenter.LocalDeath(character: Model, hud, info)
	local cam = Workspace.CurrentCamera
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	hud:SetCombatVisible(false)
	hud:ShowDeath(info and info.Killer, info and info.Detail)
	local startCF = cam.CFrame
	local look = root.CFrame.LookVector
	local focus = root.Position - Vector3.new(0, 1.5, 0)
	local killerPos = info and info.KillerPosition
	local dir = if killerPos then (Vector3.new(killerPos.X, focus.Y, killerPos.Z) - focus) else -look
	if dir.Magnitude < 0.1 then
		dir = -look
	end
	dir = dir.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local t0 = os.clock()
	local respawn = Players.RespawnTime
	local faded = false
	local bodyParts = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			table.insert(bodyParts, d)
		end
	end
	local conn
	cam.CameraType = Enum.CameraType.Scriptable
	conn = RunService.RenderStepped:Connect(function()
		if Players.LocalPlayer.Character ~= character then
			conn:Disconnect()
			return
		end
		local t = os.clock() - t0
		local a = smooth(math.clamp(t / 0.9, 0, 1))
		-- first person hid our own body; the death camera needs to see it (until the fade)
		local rec = active[character]
		if not (rec and rec.LastFade) then
			for _, p in bodyParts do
				p.LocalTransparencyModifier = 0
			end
		end
		local orbit = CFrame.Angles(0, rad(18 * t), 0):VectorToWorldSpace(dir)
		local desired = focus + orbit * (5 + 3 * a) + Vector3.new(0, 3.2 + 1.5 * a, 0)
		local hit = Workspace:Raycast(focus, desired - focus, params)
		if hit then
			desired = hit.Position + (focus - hit.Position).Unit * 0.6
		end
		local target = CFrame.lookAt(desired, focus)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = startCF:Lerp(target, a)
		if not faded and t >= respawn - 0.38 then
			faded = true
			hud:Fade(true, 0.3)
		end
	end)
	return function()
		conn:Disconnect()
	end
end

function DeathPresenter.LocalSpawn(hud)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	-- re-assert the subject so Roblox's camera controllers (incl. transparency) re-attach
	local character = Players.LocalPlayer.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	hud:HideDeath()
	hud:SetCombatVisible(true)
	hud:Fade(false, 0.35)
end

function DeathPresenter.Start()
	if started then
		return
	end
	started = true
	local function onPlayer(plr: Player)
		plr.CharacterAdded:Connect(watch)
		if plr.Character then
			watch(plr.Character)
		end
	end
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	Players.PlayerAdded:Connect(onPlayer)
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		CollectionService:GetInstanceAddedSignal("VantageDummy"):Connect(watch)
		for _, m in CollectionService:GetTagged("VantageDummy") do
			watch(m)
		end
	end
	RunService.Stepped:Connect(step)
end

return DeathPresenter
