--[[
	VANTAGE — CoreOverloadFX (client)
	"Crimson Core Overload": the effects half of the exosuit death. DeathPresenter poses the body on
	the same server-time clock (the death's start comes from the server attribute VantageDeath), so
	every client sees the same sequence at the same moment.
	  0 → Impact          crimson-white flash washes over the armour, impact crack + arcs
	  Impact → Charge     system failure: armour lights stutter, crimson arcs crawl over the suit
	  Charge → Detonate   the chest core builds (glow, light), warning tones speed up, charge whine rises
	  Detonate            crimson-white blast, shockwave ring, tendrils, energy fragments, boom;
	                      the body is gone from here (DeathPresenter hides it)
	  after               one-shot effects fade on their own; nothing persistent is left behind
	Timings / colours / sounds: ReplicatedStorage.Vantage.Elimination.CoreOverloadConfig.
	A client that sees the death late (joined or streamed in mid-way) skips what is already over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OV = require(ReplicatedStorage.Vantage.Elimination.CoreOverloadConfig)
local EnergyFX = require(script.Parent.EnergyFX)
local COL = OV.Colors

local BODY = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
	"Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
}
local LATE = 0.35 -- a one-shot moment more than this far in the past is skipped

local CoreOverloadFX = {}
local running: { [Model]: boolean } = {}
local rng = Random.new()

local function randomDir(flatten: number): Vector3
	return Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1) * flatten, rng:NextNumber(-1, 1)).Unit
end

local function detonate(pos: Vector3, isLocal: boolean, f: Folder)
	EnergyFX.Sound(OV.Sounds.Detonate, if isLocal then nil else pos, { RollOffMin = 14, RollOffMax = 320 })
	-- white-hot core flash, then the crimson energy shell right behind it
	EnergyFX.Flash(pos, {
		Color = COL.White, From = 0.8, To = if isLocal then 6 else 9, Life = 0.22, Transparency = 0, Folder = f,
		Light = { Color = COL.Hot, Range = 30, Brightness = 10, Life = 0.7 },
	})
	EnergyFX.Flash(pos, { Color = COL.Crimson, Material = Enum.Material.ForceField, From = 2, To = 16, Life = 0.5, Transparency = 0, Folder = f })
	-- shockwave ring at waist height, racing outward
	EnergyFX.ShockRing(CFrame.new(pos - Vector3.new(0, 0.6, 0)), {
		From = 1, To = 15, Life = 0.55, Segments = 20, Thickness = 0.35, Color = COL.Hot, Folder = f,
	})
	-- crimson electrical tendrils
	for i = 1, 9 do
		EnergyFX.Arc(pos, pos + randomDir(0.6) * rng:NextNumber(4.5, 9), {
			Color = if i % 3 == 0 then COL.White else COL.Hot, Width = 0.09, Life = 0.2, Segments = 6, Jitter = 0.16, Brightness = 6,
		})
	end
	-- glowing energy fragments (fast, bright) and slower embers that settle and fade
	EnergyFX.Sparks(CFrame.new(pos), 40, {
		Color0 = COL.White, Color1 = COL.Crimson, Spread = 180, Speed = NumberRange.new(22, 50),
		Life = NumberRange.new(0.45, 0.95), Size = 0.3, Drag = 2.2, Gravity = 22, Brightness = 5,
	})
	EnergyFX.Sparks(CFrame.new(pos), 24, {
		Color0 = COL.Hot, Color1 = COL.Blood, Spread = 180, Speed = NumberRange.new(6, 16),
		Life = NumberRange.new(0.8, 1.4), Size = 0.2, Drag = 3, Gravity = 6, Brightness = 3,
	})
end

-- character: the dying character; start: the death's server time (VantageDeath)
function CoreOverloadFX.Play(character: Model, start: number)
	if running[character] then
		return -- one sequence per death, however often the attribute is seen
	end
	if Workspace:GetServerTimeNow() - start > OV.Detonate + LATE then
		return -- seen too late: nothing left to show
	end
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not torso or (torso.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude > OV.MaxDistance then
		return
	end
	running[character] = true
	local isLocal = character == Players.LocalPlayer.Character
	local parts = {}
	for _, n in BODY do
		local p = character:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	local f = EnergyFX.Folder("VantageDeathFX")

	-- the armour: a crimson wash / flicker over the whole body (occluded: never seen through walls)
	local hl = Instance.new("Highlight")
	hl.Name = "VantageOverload"
	hl.Adornee = character
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = COL.White
	hl.OutlineColor = COL.White
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.Parent = f
	-- the chest core: inner neon ball + outer energy halo + a light that rides on the torso
	local core = EnergyFX.Part({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = COL.Crimson, Size = Vector3.one * 0.1, Transparency = 1, CFrame = torso.CFrame }, f)
	local halo = EnergyFX.Part({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = COL.Hot, Size = Vector3.one * 0.1, Transparency = 1, CFrame = torso.CFrame }, f)
	local lightAtt = Instance.new("Attachment")
	lightAtt.Position = Vector3.new(0, 0.15, -0.3)
	lightAtt.Parent = torso
	local light = Instance.new("PointLight")
	light.Color = COL.Crimson
	light.Range = 8
	light.Brightness = 0
	light.Shadows = false
	light.Parent = lightAtt

	local at = function(pos: Vector3): Vector3?
		return if isLocal then nil else pos
	end
	local fired = {}
	local function once(key: string, t: number, moment: number): boolean
		if fired[key] or t < moment then
			return false
		end
		fired[key] = true
		return t - moment <= LATE
	end
	local charge: Sound? = nil
	local nextArc, nextWarn = 0, 0
	local conn: RBXScriptConnection
	local function finish()
		conn:Disconnect()
		running[character] = nil
		hl:Destroy()
		core:Destroy()
		halo:Destroy()
		lightAtt:Destroy()
		if charge then
			charge:Destroy()
		end
	end
	conn = RunService.RenderStepped:Connect(function()
		local t = Workspace:GetServerTimeNow() - start
		if not character:IsDescendantOf(Workspace) or t > OV.Length + 0.5 then
			finish() -- done, or the character left (respawn / disconnect)
			return
		end
		local clock = os.clock()
		local corePos = (torso.CFrame * CFrame.new(0, 0.15, -0.3)).Position

		-- phase 1: fatal impact
		if once("impact", t, 0) then
			EnergyFX.Sound(OV.Sounds.Impact, at(corePos))
			EnergyFX.Flash(corePos, {
				Color = COL.White, From = 0.4, To = 3.2, Life = 0.16, Transparency = 0.25, Folder = f,
				Light = { Color = COL.Hot, Range = 12, Brightness = 4, Life = 0.25 },
			})
			for _ = 1, 3 do
				EnergyFX.Arc(parts[rng:NextInteger(1, #parts)].Position, parts[rng:NextInteger(1, #parts)].Position, { Color = COL.White, Width = 0.06, Life = 0.12, Segments = 5, Jitter = 0.22 })
			end
		end
		if t < OV.Impact + 0.06 then
			-- the crimson-white wash travels over the armour and settles into crimson
			local a = math.clamp(t / (OV.Impact + 0.06), 0, 1)
			hl.FillColor = COL.White:Lerp(COL.Crimson, a)
			hl.FillTransparency = 0.1 + 0.7 * a
			hl.OutlineTransparency = 0.2 + 0.6 * a
		elseif t < OV.Detonate then
			local charging = math.clamp((t - OV.Charge) / (OV.Detonate - OV.Charge), 0, 1)
			-- phase 2: system failure, the armour lights stutter
			local on = rng:NextNumber() < 0.55 + 0.4 * charging
			hl.FillColor = COL.Crimson
			hl.FillTransparency = if on then 0.75 - 0.4 * charging else 0.95
			hl.OutlineTransparency = if on then 0.45 - 0.3 * charging else 0.9
			light.Brightness = (if on then rng:NextNumber(0.6, 1.6) else 0.1) + charging * 9
			light.Range = 8 + charging * 12
			if clock >= nextArc and #parts > 1 then
				nextArc = clock + (if charging > 0 then rng:NextNumber(0.03, 0.07) else rng:NextNumber(0.06, 0.14))
				local a = if charging > 0 and rng:NextNumber() < 0.5 then corePos else parts[rng:NextInteger(1, #parts)].Position
				local b = parts[rng:NextInteger(1, #parts)].Position
				EnergyFX.Arc(a, b, {
					Color = if rng:NextNumber() < 0.3 then COL.White else COL.Hot,
					Width = 0.05 + 0.06 * charging, Life = 0.08, Segments = 5, Jitter = 0.22,
				})
			end
			-- phase 3: the core builds
			if charging > 0 then
				local pulse = 1 + 0.12 * math.sin(t * (30 + 40 * charging))
				core.CFrame = CFrame.new(corePos)
				halo.CFrame = CFrame.new(corePos)
				core.Transparency = 0.6 - 0.6 * charging
				core.Size = Vector3.one * (0.25 + 1.25 * charging ^ 1.5) * pulse
				core.Color = COL.Crimson:Lerp(COL.White, 0.7 * charging ^ 2)
				halo.Transparency = 0.9 - 0.6 * charging
				halo.Size = Vector3.one * (0.8 + 2.2 * charging) * pulse
			end
			if once("charge", t, OV.Charge) then
				charge = EnergyFX.Sound(OV.Sounds.Charge, at(corePos), { Life = 3 })[1]
			end
			if charge then
				charge.PlaybackSpeed = OV.ChargePitch[1] + (OV.ChargePitch[2] - OV.ChargePitch[1]) * charging
			end
			-- warning tones, faster as the core builds
			if t >= OV.Charge and clock >= nextWarn then
				nextWarn = clock + (0.24 - 0.17 * charging)
				EnergyFX.Sound(OV.Sounds.Warn, at(corePos), { Speed = 1 + 0.5 * charging })
			end
		end
		-- phase 4: detonation
		if once("detonate", t, OV.Detonate) then
			detonate(corePos, isLocal, f)
		end
		if t >= OV.Detonate then
			hl.FillTransparency, hl.OutlineTransparency = 1, 1
			core.Transparency, halo.Transparency = 1, 1
			light.Brightness = 0
			if charge and charge.IsPlaying then
				charge:Stop()
			end
		end
	end)
end

return CoreOverloadFX
