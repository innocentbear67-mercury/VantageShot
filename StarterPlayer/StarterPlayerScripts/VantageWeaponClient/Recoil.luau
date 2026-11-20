--[[
	VANTAGE — Recoil (client camera recoil)
	Deterministic, learnable pattern: shot N of a spray always adds WeaponConfig.Recoil.Pattern[N]
	(degrees up / right). No randomness anywhere, so players can learn to pull against it.

	Layers on the camera (the movement system's camera is untouched):
		RenderPriority.Camera - 1  Undo()   remove last frame's offset before Roblox's camera
		                                    reads camera.CFrame (prevents inherited drift)
		RenderPriority.Camera + 2  Apply()  pattern offset * visual punch, after CameraEffects (+1)
	Bullets leave along the final camera, so they go exactly where the crosshair is drawn.
	Recovery only starts RecoveryDelay after the last shot (longer than the shot interval), so it
	never fights the pattern mid-spray; then it eases the offset back to zero.
]]

local Recoil = {}
Recoil.__index = Recoil

local PUNCH_ATTACK = 60 -- per second: the punch eases in over a few frames instead of landing on one
local SHAKE_W = 24 -- hit wobble spring (rad/s); underdamped so it rings once and settles

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function Recoil.new(weapon)
	local self = setmetatable({}, Recoil)
	self.Cfg = weapon.Recoil
	self.Target = Vector2.zero   -- (pitch up, yaw right) degrees
	self.Current = Vector2.zero
	self.Punch = 0               -- shown pitch, degrees; eases toward PunchTarget
	self.PunchTarget = 0
	self.PunchScale = 1          -- zoom match: the punch crosses the same distance on screen at every zoom
	self.BasePitch = nil         -- camera pitch without recoil, last frame (detects a mouse pull against the kick)
	self.Shake = 0               -- hit wobble, roll degrees (roll only: the aim never moves)
	self.ShakeVel = 0
	self.Applied = CFrame.identity
	self.PunchRot = CFrame.identity
	self.LastKick = -math.huge
	return self
end

-- Returns this shot's pattern step (up, right) so the viewmodel kick can match it.
function Recoil:Kick(shotIndex: number, scale: number?): (number, number)
	local c = self.Cfg
	local pattern = c.Pattern
	local n = #pattern
	local idx = shotIndex
	if idx > n then
		idx = n - 3 + ((idx - n - 1) % 4) -- past the table: loop the last four steps
	end
	local step = pattern[math.max(1, idx)]
	local k = c.Scale * (scale or 1)
	local up, right = step[1] * k, step[2] * k
	self.Target = Vector2.new(
		math.min(self.Target.X + up, c.MaxVertical),
		math.clamp(self.Target.Y + right, -c.MaxHorizontal, c.MaxHorizontal)
	)
	if self.PunchEnabled ~= false then
		self.PunchTarget += c.PunchPitch * self.PunchScale -- disabled by the "Screen shake" setting
		-- 2026-11-17: a small alternating camera roll per shot (roll only: the aim never moves)
		self.ShakeVel += (if shotIndex % 2 == 0 then 1 else -1) * (c.ShotRoll or 0.35) * SHAKE_W
	end
	self.LastKick = os.clock()
	return up, right
end

-- the player was hit: a short roll wobble (roll only, so the aim and the crosshair stay put)
function Recoil:HitShake(deg: number)
	if self.PunchEnabled == false then
		return -- "Screen shake" setting off
	end
	self.ShakeVel += deg * SHAKE_W * 1.6
end

function Recoil:Reset()
	self.Target = Vector2.zero
	self.Current = Vector2.zero
	self.Punch = 0
	self.PunchTarget = 0
	self.BasePitch = nil
end

function Recoil:Step(dt: number)
	local c = self.Cfg
	if os.clock() - self.LastKick > c.RecoveryDelay then
		self.Target = self.Target:Lerp(Vector2.zero, expAlpha(c.RecoverySpeed, dt))
	end
	self.Current = self.Current:Lerp(self.Target, expAlpha(c.Snap, dt))
	self.PunchTarget *= math.exp(-c.PunchDecay * dt)
	self.Punch += (self.PunchTarget - self.Punch) * expAlpha(PUNCH_ATTACK, dt)
	if self.PunchTarget < 1e-3 and self.Punch < 1e-3 then
		self.PunchTarget, self.Punch = 0, 0
	end
	-- hit wobble: sub-stepped spring, stable at any frame rate
	local left = dt
	while left > 0 and (self.Shake ~= 0 or self.ShakeVel ~= 0) do
		local h = math.min(left, 1 / 120)
		left -= h
		self.ShakeVel += (-SHAKE_W * SHAKE_W * self.Shake - 2 * 0.3 * SHAKE_W * self.ShakeVel) * h
		self.Shake += self.ShakeVel * h
		if math.abs(self.Shake) < 1e-3 and math.abs(self.ShakeVel) < 1e-2 then
			self.Shake, self.ShakeVel = 0, 0
		end
	end
end

local function rotationFor(v: Vector2): CFrame
	-- positive Y = recoil to the right
	return CFrame.Angles(0, -math.rad(v.Y), 0) * CFrame.Angles(math.rad(v.X), 0, 0)
end

function Recoil:Undo(camera: Camera)
	if self.Applied ~= CFrame.identity then
		camera.CFrame = camera.CFrame * self.Applied:Inverse()
		self.Applied = CFrame.identity
	end
end

function Recoil:Apply(camera: Camera)
	-- a mouse pull against the kick replaces that much recoil: it moves into the base aim, so recovery
	-- can only return what the player has not already corrected
	local pitch = math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
	local pulled = if self.BasePitch then self.BasePitch - pitch else 0
	local owed = math.max(self.Current.X, self.Target.X) -- includes a kick still easing in
	if pulled > 0 and owed > 0 then
		local taken = math.min(pulled, owed)
		self.Current -= Vector2.new(taken, 0)
		self.Target = Vector2.new(math.max(self.Target.X - taken, 0), self.Target.Y)
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(taken), 0, 0)
		pitch += taken
	end
	self.BasePitch = pitch

	local rot = CFrame.identity
	if self.Current.Magnitude > 1e-4 then
		rot = rotationFor(self.Current)
	end
	self.PunchRot = if self.Punch > 0 then CFrame.Angles(math.rad(self.Punch), 0, 0) else CFrame.identity
	rot = rot * self.PunchRot
	if self.Shake ~= 0 then
		rot = rot * CFrame.Angles(0, 0, math.rad(self.Shake))
	end
	if rot ~= CFrame.identity then
		camera.CFrame = camera.CFrame * rot
	end
	self.Applied = rot
end

-- Current pattern offset in degrees (for tests / UI)
function Recoil:Offset(): Vector2
	return self.Current
end

return Recoil
