--[[
	VANTAGE — ViewmodelAnimator (client)
	Plays clips from the shared WeaponClips module (the same data the third-person rig uses).
	Two backends:
	  1. ASSET backend: if WeaponConfig.Animations[name] has an ID AND a rigged viewmodel
	     (Assets.<Asset>_ViewmodelRig with an Animator) exists, the uploaded animation plays.
	  2. PROCEDURAL backend (current): keyframes sampled with smoothstep; clip events fire at
	     exact times so audio, visuals, ammo refills and melee strikes stay in sync.
	Continuous layers (sway, bob, air, landing, stance, recoil kick, ADS) live in the viewmodels.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponClips = require(ReplicatedStorage.Vantage.Weapons.WeaponClips)
-- stylised reloads with the real magazines / moving parts (2026-11-14)
local ReloadChoreo = require(ReplicatedStorage.Vantage.Weapons.ReloadChoreo)

local ViewmodelAnimator = {}
ViewmodelAnimator.__index = ViewmodelAnimator

local function emptyPose()
	return {
		Tracks = {},
		Weights = {},
		Hidden = {},
		Raw = {},
		-- rifle convenience fields
		Gun = CFrame.identity,
		Mag = CFrame.identity,
		LeftOnMag = 0,
		MagHidden = false,
	}
end

function ViewmodelAnimator.new(weapon, rig: Model?)
	local self = setmetatable({}, ViewmodelAnimator)
	self.Weapon = weapon
	self.Clips = WeaponClips.For(weapon.Id) or {}
	local choreo = ReloadChoreo.For(weapon.Id)
	if choreo then
		local merged = table.clone(self.Clips)
		for name, c in choreo do
			merged[name] = c
		end
		self.Clips = merged
	end
	self.Clip = nil
	self.ClipName = nil
	self.StartedAt = 0
	self.Speed = 1
	self.Fired = {}
	self.OnEvent = nil -- function(name, clipName)
	self.OnFinished = nil -- function(clipName)
	self.AssetTracks = {}
	local animator = rig and rig:FindFirstChildWhichIsA("Animator", true)
	if animator and weapon.Animations then
		for name, id in weapon.Animations do
			if id ~= "" then
				local a = Instance.new("Animation")
				a.AnimationId = id
				local ok, track = pcall(animator.LoadAnimation, animator, a)
				if ok then
					self.AssetTracks[name] = track
				end
			end
		end
	end
	return self
end

function ViewmodelAnimator:HasAsset(name: string): boolean
	return self.AssetTracks[name] ~= nil
end

-- length: stretch the clip to this duration (e.g. WeaponConfig.ReloadTime)
function ViewmodelAnimator:Play(name: string, length: number?, override: any?)
	local clip = override or self.Clips[name]
	if not clip then
		return
	end
	self.Clip = clip
	self.ClipName = name
	self.StartedAt = os.clock()
	self.Speed = if length and length > 0 then clip.Length / length else 1
	self.Fired = {}
	self.BlendFrom = nil
	local track = self.AssetTracks[name]
	if track then
		track:Play(0.05, 1, self.Speed)
	end
end

-- blend: seconds to ease from the current pose back to rest (0 = snap)
function ViewmodelAnimator:Stop(blend: number?)
	if self.ClipName and self.AssetTracks[self.ClipName] then
		self.AssetTracks[self.ClipName]:Stop(blend or 0.1)
	end
	if blend and blend > 0 and self.Clip and self.LastPose then
		self.BlendFrom = self.LastPose
		self.BlendStart = os.clock()
		self.BlendTime = blend
	end
	self.Clip = nil
	self.ClipName = nil
end

function ViewmodelAnimator:IsPlaying(name: string?): boolean
	return self.Clip ~= nil and (name == nil or self.ClipName == name)
end

function ViewmodelAnimator:Progress(): number
	if not self.Clip then
		return 1
	end
	return math.clamp((os.clock() - self.StartedAt) * self.Speed / self.Clip.Length, 0, 1)
end

local function finalize(pose)
	pose.Gun = pose.Tracks.Gun or CFrame.identity
	pose.Mag = pose.Tracks.Mag or CFrame.identity
	pose.LeftOnMag = pose.Weights.LeftOnMag or 0
	pose.Left = pose.Tracks.Left or CFrame.identity -- support hand offset in gun space (pump)
	pose.Right = pose.Tracks.Right or CFrame.identity -- bolt handle offset in gun space
	pose.RightOnBolt = pose.Weights.RightOnBolt or 0
	pose.MagHidden = pose.Hidden.Mag == true
	return pose
end

function ViewmodelAnimator:Sample()
	local clip = self.Clip
	if not clip then
		local pose = emptyPose()
		local from = self.BlendFrom
		if from then
			local a = math.clamp((os.clock() - self.BlendStart) / self.BlendTime, 0, 1)
			if a >= 1 then
				self.BlendFrom = nil
			else
				local u = WeaponClips.Smooth(a)
				for name, cf in from.Tracks do
					pose.Tracks[name] = cf:Lerp(CFrame.identity, u)
				end
				for name, r in from.Raw do
					pose.Raw[name] = r:Lerp(Vector3.zero, u)
				end
				for name, w in from.Weights do
					pose.Weights[name] = w * (1 - u)
				end
			end
		end
		return finalize(pose)
	end
	local t = (os.clock() - self.StartedAt) * self.Speed
	for i, ev in clip.Events do
		if not self.Fired[i] and t >= ev.t then
			self.Fired[i] = true
			if self.OnEvent then
				task.spawn(self.OnEvent, ev.name, self.ClipName)
			end
		end
	end
	local tc = math.min(t, clip.Length)
	local pose = finalize(if clip.Choreo then ReloadChoreo.Sample(clip, tc) elseif clip.Sample then clip.Sample(clip, tc) else WeaponClips.Sample(clip, t))
	if clip.Choreo then
		pose.Choreo = { Clip = clip, T = tc }
	end
	self.LastPose = pose
	if t >= clip.Length then
		local name = self.ClipName
		self.Clip = nil
		self.ClipName = nil
		if self.OnFinished then
			task.spawn(self.OnFinished, name)
		end
	end
	return pose
end

return ViewmodelAnimator
