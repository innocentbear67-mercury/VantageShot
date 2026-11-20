--!nonstrict
--[[
	VANTAGE — CreatureGait (client) — 2026-11-19
	Procedural run / gallop for the rigged Signature creatures (Fenrir, Sleipnir) by writing
	Bone.Transform every frame. No animation assets: the Tripo rigs came without clips, and a coded
	cycle can be matched exactly to the server's path speed.

	local g = Gait.new(model, Gait.Presets.Fenrir)
	g:Step(dt, speedScale)   -- speedScale 0..1.5 (0 = stand)
	g:Reset()

	Each leg swings about the creature's side axis (upper bone) and folds at the knee (lower bone).
	The direction of every rotation is worked out once from the rest pose, so the presets don't depend
	on how Tripo rolled each bone. The body bobs twice per stride, the spine rocks, the tail sways and
	the head counters the spine.
]]

local Gait = {}
Gait.__index = Gait

local function find(model, name)
	return name and model:FindFirstChild(name, true) or nil
end

local function rotAxisSign(bone, axisW, probeVec, wantDir, wantPositive)
	-- does +angle about axisW move probeVec along wantDir? returns +1 / -1
	local rotated = CFrame.fromAxisAngle(axisW, math.rad(10)):VectorToWorldSpace(probeVec)
	local d = (rotated - probeVec):Dot(wantDir)
	if wantPositive then return d >= 0 and 1 or -1 end
	return d <= 0 and 1 or -1
end

function Gait.new(model: Model, cfg)
	local self = setmetatable({ Model = model, Cfg = cfg, Phase = 0, Legs = {}, Extra = {} }, Gait)
	local piv = model:GetPivot()
	local fwd, up = piv.LookVector, piv.UpVector
	local side = piv.RightVector
	self.Fwd, self.Up, self.Side = fwd, up, side
	for _, leg in cfg.Legs do
		local upper, lower = find(model, leg.Upper), find(model, leg.Lower)
		if not (upper and lower) then continue end
		upper.Transform = CFrame.identity
		lower.Transform = CFrame.identity
		local tip = find(model, leg.Tip)
		local uPos, lPos = upper.WorldPosition, lower.WorldPosition
		local lowerVec = tip and (tip.WorldPosition - lPos) or (lPos - uPos)
		local L = {
			Upper = upper, Lower = lower, Phase = leg.Phase, Front = leg.Front,
			UAxis = upper.WorldCFrame:VectorToObjectSpace(side),
			LAxis = lower.WorldCFrame:VectorToObjectSpace(side),
			USign = rotAxisSign(upper, side, lPos - uPos, fwd, true), -- + swings the leg forward
			-- the knee folds so the foot comes up behind (front: carpus, back: hock)
			LSign = rotAxisSign(lower, side, lowerVec, fwd, false),
		}
		table.insert(self.Legs, L)
	end
	local function boneSet(names, axisW)
		local t = {}
		for _, n in names or {} do
			local b = find(model, n)
			if b then b.Transform = CFrame.identity; table.insert(t, { Bone = b, Axis = b.WorldCFrame:VectorToObjectSpace(axisW) }) end
		end
		return t
	end
	self.Spine = boneSet(cfg.Spine, side)
	self.Neck = boneSet(cfg.Neck, side)
	self.Tail = boneSet(cfg.Tail, up)
	self.TailLift = boneSet(cfg.Tail, side)
	self.Root = find(model, cfg.Root or "Root")
	if self.Root then
		self.Root.Transform = CFrame.identity
		self.RootUp = self.Root.WorldCFrame:VectorToObjectSpace(up)
	end
	return self
end

function Gait:Step(dt: number, speed: number?)
	local cfg = self.Cfg
	speed = speed or 1
	self.Phase = (self.Phase + dt * cfg.Freq * math.max(speed, 0.15)) % 1
	local a = speed > 0.05 and math.min(speed, 1.3) or 0
	local tau = math.pi * 2
	for _, L in self.Legs do
		local p = (self.Phase + L.Phase) % 1
		local swing = math.sin(p * tau) * math.rad(cfg.Swing) * a
		-- fold the knee while the leg travels forward (cos > 0 half of the cycle)
		local fold = math.max(0, math.cos(p * tau)) ^ 1.4 * math.rad(L.Front and cfg.KneeFront or cfg.KneeBack) * a
		L.Upper.Transform = CFrame.fromAxisAngle(L.UAxis, swing * L.USign)
		L.Lower.Transform = CFrame.fromAxisAngle(L.LAxis, fold * L.LSign)
	end
	local twice = math.sin(self.Phase * tau * 2)
	for i, s in self.Spine do
		s.Bone.Transform = CFrame.fromAxisAngle(s.Axis, math.rad(cfg.SpineRock) * a * math.sin(self.Phase * tau + i * 0.6))
	end
	for i, s in self.Neck do
		s.Bone.Transform = CFrame.fromAxisAngle(s.Axis, -math.rad(cfg.NeckRock) * a * math.sin(self.Phase * tau + 0.4 + i * 0.3))
	end
	for i, s in self.Tail do
		local lift = self.TailLift[i]
		s.Bone.Transform = CFrame.fromAxisAngle(s.Axis, math.rad(cfg.TailSway) * a * math.sin(self.Phase * tau * 0.5 + i * 0.8))
			* CFrame.fromAxisAngle(lift.Axis, math.rad(cfg.TailLift) * a)
	end
	if self.Root then
		self.Root.Transform = CFrame.new(self.RootUp * cfg.Bob * a * twice)
	end
end

function Gait:Reset()
	for _, d in self.Model:GetDescendants() do
		if d:IsA("Bone") then d.Transform = CFrame.identity end
	end
	self.Phase = 0
end

-- bob in the bones' own units (the rigs are scaled with Model:ScaleTo, so 0.3 = 0.3 studs)
Gait.Presets = {
	-- rotary gallop: lead leg pairs a tenth of a stride apart, hind pair half a stride later
	Fenrir = {
		Freq = 3.6, Swing = 38, KneeFront = 55, KneeBack = 45, Bob = 0.35, SpineRock = 5, NeckRock = 6, TailSway = 14, TailLift = 10,
		Legs = {
			{ Upper = "Leg_FL_1", Lower = "Leg_FL_2", Tip = "Leg_FL_3", Phase = 0.0, Front = true },
			{ Upper = "Leg_FR_1", Lower = "Leg_FR_2", Tip = "Leg_FR_3", Phase = 0.1, Front = true },
			{ Upper = "Leg_BL_1", Lower = "Leg_BL_2", Phase = 0.5, Front = false },
			{ Upper = "Leg_BR_1", Lower = "Leg_BR_2", Phase = 0.6, Front = false },
		},
		Spine = { "Spine0", "Spine1", "Spine2" }, Neck = { "Neck", "Head" }, Tail = { "Tail0", "Tail1" },
	},
	-- eight legs: each extra leg runs a quarter stride behind its partner, so the legs read as a blur
	Sleipnir = {
		Freq = 3.2, Swing = 34, KneeFront = 60, KneeBack = 50, Bob = 0.4, SpineRock = 4, NeckRock = 7, TailSway = 12, TailLift = 18,
		Legs = {
			{ Upper = "Leg_FL_1", Lower = "Leg_FL_2", Tip = "Leg_FL_3", Phase = 0.0, Front = true },
			{ Upper = "Leg_FR_1", Lower = "Leg_FR_2", Tip = "Leg_FR_3", Phase = 0.12, Front = true },
			{ Upper = "Leg_BL_1", Lower = "Leg_BL_2", Tip = "Leg_BL_3", Phase = 0.55, Front = false },
			{ Upper = "Leg_BR_1", Lower = "Leg_BR_2", Tip = "Leg_BR_3", Phase = 0.67, Front = false },
			{ Upper = "Leg_FL2_1", Lower = "Leg_FL2_2", Tip = "Leg_FL2_3", Phase = 0.25, Front = true },
			{ Upper = "Leg_FR2_1", Lower = "Leg_FR2_2", Tip = "Leg_FR2_3", Phase = 0.37, Front = true },
			{ Upper = "Leg_BL2_1", Lower = "Leg_BL2_2", Tip = "Leg_BL2_3", Phase = 0.8, Front = false },
			{ Upper = "Leg_BR2_1", Lower = "Leg_BR2_2", Tip = "Leg_BR2_3", Phase = 0.92, Front = false },
		},
		Spine = { "Spine0", "Spine1", "Spine2" }, Neck = { "Neck0", "Neck1", "Head" }, Tail = { "Tail0", "Tail1", "Tail2" },
	},
}

return Gait
