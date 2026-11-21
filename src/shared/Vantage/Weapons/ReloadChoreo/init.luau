--[[
	VANTAGE — ReloadChoreo (client)
	Stylised reload choreography that uses the REAL magazines and moving parts cut from each gun
	(Mag / Cell, Charge, Bolt, Slide, Pump: see WeaponAssetKit.Build split import, 2026-11-14).
	Approved in the VantageShot Visual Prototype Lab, ported here.

	A choreo clip is a normal clip (Length, Events, Tracks.Gun, Weights.LeftOnMag) plus:
	  MagOut / MagIn  prop keys:  { t, sp = "seat", off = studs along eject, p = Root-space offset, r = deg }
	                              { t, sp = "cam",  p = camera-space position, r = deg (seated rotation + r) }
	                              { t, sp = "free", v = camera-space studs/s, w = rad/s }   (thrown / dropped)
	  Left / Right    hand keys:  { t, hold = "Support" | "Grip" | "MagOut" | "MagIn" | "Part" | "Gun" | "Cam" | "Freeze", ... }
	  Parts           { Charge = { {t, v, e}, ... }, BoltR, BoltS, Slide, Pump }   (0..1)
	  Kicks           { { t, p, r, f, d } }  impact jolts on the gun (decaying sine)
	Asset-space (Root) values are authored unscaled and multiplied by the viewmodel scale here;
	camera-space values are in camera studs. The clip is stretched to the config time by the
	animator, so every beat (and the MagIn ammo refill) moves with the configured duration.
]]
local V = Vector3.new
local rad = math.rad

local ReloadChoreo = {}

local EASE = {
	lin = function(t) return t end,
	io = function(t) return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2 end,
	out = function(t) return 1 - (1 - t) ^ 3 end,
	["in"] = function(t) return t * t * t end,
	snap = function(t) return if t >= 1 then 1 else 1 - 2 ^ (-10 * t) end,
	back = function(t) local c1, c3 = 1.9, 2.9 return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2 end,
	hold = function(t) return 0 end,
}
ReloadChoreo.Ease = EASE

local function seg(keys, t)
	if t <= keys[1].t then
		return 1, 1, 0
	end
	for i = 1, #keys - 1 do
		local b = keys[i + 1]
		if t < b.t then
			local u = (t - keys[i].t) / math.max(1e-6, b.t - keys[i].t)
			return i, i + 1, EASE[b.e or "io"](u)
		end
	end
	return #keys, #keys, 0
end
ReloadChoreo.Seg = seg

local function ang(r: Vector3?): CFrame
	if not r then
		return CFrame.identity
	end
	return CFrame.Angles(rad(r.X), rad(r.Y), rad(r.Z))
end

-- gun track (grip-local) + impact kicks
function ReloadChoreo.SampleGun(clip, t: number): CFrame
	local keys = clip.Gun
	local i, j, u = seg(keys, t)
	local a, b = keys[i], keys[j]
	local p = a.p:Lerp(b.p, u)
	local r = a.r:Lerp(b.r, u)
	for _, kk in clip.Kicks or {} do
		if t >= kk.t then
			local dt = t - kk.t
			local env = math.exp(-dt * (kk.d or 22)) * math.sin(dt * (kk.f or 46))
			p += (kk.p or Vector3.zero) * env
			r += (kk.r or Vector3.zero) * env
		end
	end
	return CFrame.new(p) * ang(r)
end

function ReloadChoreo.PartValue(clip, name: string, t: number): number
	local keys = clip.Parts and clip.Parts[name]
	if not keys then
		return 0
	end
	local i, j, u = seg(keys, t)
	return keys[i].v + (keys[j].v - keys[i].v) * u
end

-- pose in the ViewmodelAnimator format
function ReloadChoreo.Sample(clip, t: number)
	local w = 0
	if clip.Reach then
		local i, j, u = seg(clip.Reach, t)
		w = clip.Reach[i].v + (clip.Reach[j].v - clip.Reach[i].v) * u
	end
	return { Tracks = { Gun = ReloadChoreo.SampleGun(clip, t) }, Weights = { LeftOnMag = w }, Hidden = {}, Raw = {} }
end

-- ─── per-frame solve (called by Viewmodel:Step while a choreo clip plays) ────────────────
-- returns { MagOut = CFrame?, MagIn = CFrame?, Shell = CFrame?, Parts = {name = Root-space motion}, Left = handCF?, Right = handCF? }
function ReloadChoreo.Solve(vm, clip, t: number, cam: CFrame, gunCF: CFrame)
	local S = vm.Scale
	local G = clip.Geo or {}
	local st = vm._choreoState
	if not st or st.Clip ~= clip or t < st.T - 1e-3 then
		st = { Clip = clip, Free = {}, Frozen = {} }
		vm._choreoState = st
	end
	st.T = t
	local out = { Parts = {} }

	-- moving parts (Root-space motion applied on top of each part's rest)
	for name, info in vm.Moving or {} do
		local g = G[name]
		if g then
			local m = CFrame.identity
			if name == "Bolt" then
				local r = ReloadChoreo.PartValue(clip, "BoltR", t)
				local s = ReloadChoreo.PartValue(clip, "BoltS", t)
				local pv = info.Rest.Position + (g.Pivot or Vector3.zero) * S
				m = CFrame.new((g.Axis or V(0, 0, 1)) * g.Travel * S * s) * CFrame.new(pv) * CFrame.fromAxisAngle(g.Axis or V(0, 0, 1), rad(g.Angle) * r) * CFrame.new(-pv)
			else
				local slide = CFrame.new((g.Axis or V(0, 0, 1)) * (g.Travel or 0) * S * ReloadChoreo.PartValue(clip, name, t))
				local swing = CFrame.identity
				if g.Angle then -- 2026-11-18: swing about a Root-space pivot (revolver crane, crossbow limbs)
					local pv = (g.Pivot or Vector3.zero) * S
					swing = CFrame.new(pv) * CFrame.fromAxisAngle(g.RotAxis or V(0, 0, 1), rad(g.Angle) * ReloadChoreo.PartValue(clip, name .. "R", t)) * CFrame.new(-pv)
				end
				local spin = CFrame.identity
				if g.Spin then -- 2026-11-18: spin about the part's own axis, in turns (drums, rotary barrels, coils)
					local sp = (g.SpinPivot or Vector3.zero) * S
					spin = CFrame.new(sp) * CFrame.fromAxisAngle(g.SpinAxis or V(0, 0, 1), 2 * math.pi * ReloadChoreo.PartValue(clip, name .. "Spin", t)) * CFrame.new(-sp)
				end
				m = slide * swing * spin
			end
			out.Parts[name] = m
		end
	end

	local eject = (G.Eject or V(0, -1, 0)).Unit
	local magRest = vm.MagRest
	local seatCF = gunCF * magRest
	local seatRotCam = cam:ToObjectSpace(seatCF).Rotation

	local function propKey(name: string, keys, idx: number): CFrame
		local k = keys[idx]
		if k.sp == "seat" then
			local off = (k.off or 0) * S
			return gunCF * CFrame.new(eject * off + (k.p or Vector3.zero) * S) * magRest * ang(k.r)
		elseif k.sp == "cam" then
			return cam * CFrame.new(k.p) * ang(k.r) * seatRotCam
		elseif k.sp == "gunpt" then
			return gunCF * CFrame.new(k.p * S) * ang(k.r)
		elseif k.sp == "free" then
			local f = st.Free[name]
			if not f then
				-- release: start from where the previous key puts the prop right now
				local prev = if idx > 1 then propKey(name, keys, idx - 1) else seatCF
				f = { CF = cam:ToObjectSpace(prev), T0 = k.t }
				st.Free[name] = f
			end
			local dt = math.max(0, t - f.T0)
			local v = k.v or Vector3.zero
			local g = V(0, -(k.g or 31), 0)
			local pos = f.CF.Position + v * dt + g * (0.5 * dt * dt)
			local w = k.w or Vector3.zero
			local rot = if w.Magnitude > 0 then CFrame.fromAxisAngle(w.Unit, w.Magnitude * dt) * f.CF.Rotation else f.CF.Rotation
			return cam * CFrame.new(pos) * rot
		end
		return seatCF
	end
	local function prop(name: string): CFrame?
		local P = clip[name]
		if not P then
			return nil
		end
		local vis = P.Vis
		if vis and (t < vis[1] or t >= vis[2]) then
			return nil
		end
		local keys = P.Keys
		local i, j, u = seg(keys, t)
		if keys[j].sp == "free" and i ~= j then
			return propKey(name, keys, i) -- hold until the throw
		end
		if i == j then
			return propKey(name, keys, i)
		end
		return propKey(name, keys, i):Lerp(propKey(name, keys, j), u)
	end
	out.MagOut = prop("MagOut")
	out.MagIn = prop("MagIn")
	out.Shell = prop("Shell")
	out.MagOutVisible = clip.MagOut == nil or out.MagOut ~= nil

	-- hands
	local arms = vm.Arms
	local function sideGrip(side: string): CFrame
		return if side == "Left" then vm.GripLeft else vm.GripRight
	end
	local function handKey(side: string, keys, idx: number): CFrame
		local k = keys[idx]
		local h = k.hold
		local gripCF
		if h == "Support" then
			local pump = out.Parts.Pump or CFrame.identity
			gripCF = gunCF * pump * vm.GripLeft * ang(k.r)
		elseif h == "Grip" then
			gripCF = gunCF * vm.GripRight * ang(k.r)
		elseif h == "MagOut" or h == "MagIn" or h == "Shell" then
			local m = out[h] or seatCF
			if h == "Shell" then
				gripCF = m * CFrame.new((k.p or Vector3.zero) * S) * ang(k.r)
			else
				gripCF = m * vm.MagGripLocal * CFrame.new((k.p or Vector3.zero) * S) * ang(k.r)
			end
		elseif h == "Part" then
			local info = vm.Moving and vm.Moving[k.part]
			local motion = out.Parts[k.part] or CFrame.identity
			local restPos = if info then info.Rest.Position else Vector3.zero
			gripCF = gunCF * motion * CFrame.new(restPos + (k.p or Vector3.zero) * S) * sideGrip(side).Rotation * ang(k.r)
		elseif h == "Gun" then
			gripCF = gunCF * CFrame.new((k.p or Vector3.zero) * S) * sideGrip(side).Rotation * ang(k.r)
		elseif h == "Cam" then
			local g0 = cam:ToObjectSpace(gunCF * sideGrip(side)).Rotation
			gripCF = cam * CFrame.new(k.p) * ang(k.r) * g0
		elseif h == "Freeze" then
			local key = side .. idx
			local fz = st.Frozen[key]
			if not fz then
				local prevGrip = if idx > 1 then handKey(side, keys, idx - 1) else gunCF * sideGrip(side)
				fz = cam:ToObjectSpace(prevGrip)
				st.Frozen[key] = fz
			end
			gripCF = cam * CFrame.new(k.d or Vector3.zero) * fz * ang(k.r)
		else
			gripCF = gunCF * sideGrip(side)
		end
		return gripCF
	end
	local function hand(side: string): CFrame?
		local keys = clip[side]
		if not keys then
			return nil
		end
		local i, j, u = seg(keys, t)
		local g = if i == j then handKey(side, keys, i) else handKey(side, keys, i):Lerp(handKey(side, keys, j), u)
		return arms:HandFromGrip(side, g)
	end
	if arms and arms:IsValid() then
		out.Left = hand("Left")
		out.Right = hand("Right")
	end
	return out
end

-- ─── clips ─────────────────────────────────────────────────────────────────────────────────
local function k(t, p, r, e)
	return { t = t, p = p or Vector3.zero, r = r or Vector3.zero, e = e }
end
local function pv(t, v, e)
	return { t = t, v = v, e = e }
end
local Clips = {}
ReloadChoreo.Clips = Clips

ReloadChoreo.Build = function() end -- replaced below by the clip data

function ReloadChoreo.For(weaponId: string)
	local data = script:FindFirstChild("Clips")
	return data and require(data)[weaponId] or nil
end

return ReloadChoreo
