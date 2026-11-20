--!strict
--[[
	VANTAGE — AircraftPath (shared, deterministic)
	Turns AircraftConfig.Route into a flight that the server and every client evaluate
	identically from the same clock (workspace:GetServerTimeNow()):

		local flight = AircraftPath.Get(direction)          -- 1 = Blue->Red, -1 = Red->Blue (cached)
		local cf, vel = AircraftPath.Sample(flight, t)      -- t = seconds since the flight started
		local cf, vel = AircraftPath.At(direction, startAt, serverTime)
		AircraftPath.HookLocal(i)  -> CFrame of hook i relative to the aircraft (cached)
		AircraftPath.MeshLocal(v)  -> mesh-unit point -> aircraft-local offset
		AircraftPath.ArmedAt(dir, t) / PastDropAt(dir, t) / StudsToDropAt(dir, t)
			the grapple window and the drop point, by DISTANCE ALONG THE ROUTE (works for any shape,
			loops included): Config.Zone.OpenAt / DropAt name waypoints of the Blue->Red route; in
			either direction hooks open at whichever comes first and riders drop at the other.

	Nothing is replicated per frame: the server publishes (flight id, direction, start time) once
	and everyone derives the same CFrame. That keeps the aircraft perfectly smooth on clients and
	gives the server the exact hook positions to validate against.

	Build: centripetal Catmull-Rom through the waypoints -> resampled at equal arc length ->
	per-sample speed (blended between waypoints), time, heading and bank (from yaw rate * speed^2).
]]

local Config = require(script.Parent:WaitForChild("AircraftConfig"))

local AircraftPath = {}

export type Flight = {
	Direction: number,
	P: { Vector3 },
	T: { number },
	CF: { CFrame },
	Length: number,
	Duration: number,
	OpenS: number, -- arc length where the hooks open (travel order)
	DropS: number, -- arc length where riders are dropped
}

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	-- centripetal (alpha 0.5): no cusps or overshoot between unevenly spaced points
	local function tj(ti: number, a: Vector3, b: Vector3): number
		return ti + math.max((b - a).Magnitude, 1e-4) ^ 0.5
	end
	local t0 = 0
	local t1 = tj(t0, p0, p1)
	local t2 = tj(t1, p1, p2)
	local t3 = tj(t2, p2, p3)
	local u = t1 + (t2 - t1) * t
	local a1 = p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	local b1 = a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))
end

local function heading(v: Vector3): number
	return math.atan2(-v.X, -v.Z) -- yaw about +Y, 0 = looking down -Z, positive = turning left
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function build(direction: number): Flight
	local route = {}
	for i, w in Config.Route do
		route[i] = w
	end
	if direction < 0 then
		local r = {}
		for i = #route, 1, -1 do
			table.insert(r, route[i])
		end
		route = r
	end
	local n = #route
	-- dense raw polyline along the spline, remembering each waypoint's arc position
	local raw: { Vector3 } = {}
	local rawS: { number } = {}
	local wpS: { number } = {}
	local s = 0
	for i = 1, n - 1 do
		local p0 = if i > 1 then route[i - 1].Pos else route[1].Pos * 2 - route[2].Pos
		local p1, p2 = route[i].Pos, route[i + 1].Pos
		local p3 = if i + 2 <= n then route[i + 2].Pos else route[n].Pos * 2 - route[n - 1].Pos
		local steps = math.max(8, math.ceil((p2 - p1).Magnitude / 4))
		for k = (if i == 1 then 0 else 1), steps do
			local p = catmull(p0, p1, p2, p3, k / steps)
			if #raw > 0 then
				s += (p - raw[#raw]).Magnitude
			end
			if k == 0 then
				wpS[i] = s
			end
			table.insert(raw, p)
			table.insert(rawS, s)
		end
		wpS[i + 1] = s
	end
	local length = s
	-- the grapple window, in travel order (indices in Config are of the Blue->Red route)
	local function travelIndex(i: number): number
		return if direction < 0 then n - i + 1 else i
	end
	local zA = wpS[travelIndex(Config.Zone.OpenAt)] or 0
	local zB = wpS[travelIndex(Config.Zone.DropAt)] or length
	local openS, dropS = math.min(zA, zB), math.max(zA, zB)
	-- resample at equal spacing
	local ds = Config.SampleSpacing
	local count = math.floor(length / ds) + 1
	local P: { Vector3 } = table.create(count)
	local j = 1
	for k = 0, count - 1 do
		local target = k * ds
		while j < #raw - 1 and rawS[j + 1] < target do
			j += 1
		end
		local a = math.clamp((target - rawS[j]) / math.max(rawS[j + 1] - rawS[j], 1e-6), 0, 1)
		P[k + 1] = raw[j]:Lerp(raw[j + 1], a)
	end
	-- speed at each sample: blended between waypoints by arc length (smoothstep)
	local function speedAt(at: number): number
		for i = 1, n - 1 do
			if at <= wpS[i + 1] or i == n - 1 then
				local a = math.clamp((at - wpS[i]) / math.max(wpS[i + 1] - wpS[i], 1e-6), 0, 1)
				a = a * a * (3 - 2 * a)
				return route[i].Speed + (route[i + 1].Speed - route[i].Speed) * a
			end
		end
		return route[n].Speed
	end
	local V: { number } = table.create(count)
	local T: { number } = table.create(count)
	for k = 1, count do
		V[k] = speedAt((k - 1) * ds)
		T[k] = if k == 1 then 0 else T[k - 1] + ds / ((V[k - 1] + V[k]) * 0.5)
	end
	-- forward and heading
	local F: { Vector3 } = table.create(count)
	local H: { number } = table.create(count)
	for k = 1, count do
		local a = P[math.max(1, k - 3)]
		local b = P[math.min(count, k + 3)]
		local f = b - a
		F[k] = if f.Magnitude > 1e-4 then f.Unit else Vector3.new(1, 0, 0)
		H[k] = heading(F[k])
	end
	-- bank from the turn rate: roll = atan(v^2 * yawRate / g), averaged over the window
	local B = Config.Bank
	local w = math.max(1, math.floor(B.Window / ds))
	local rawRoll: { number } = table.create(count)
	for k = 1, count do
		local a, b = math.max(1, k - w), math.min(count, k + w)
		local yawRate = wrap(H[b] - H[a]) / math.max((b - a) * ds, 1e-3) -- radians per stud
		local lat = V[k] * V[k] * yawRate
		rawRoll[k] = math.clamp(math.atan(lat / B.VirtualG) * B.Gain, -math.rad(B.Max), math.rad(B.Max))
	end
	local CF: { CFrame } = table.create(count)
	for k = 1, count do
		local a, b = math.max(1, k - w), math.min(count, k + w)
		local sum = 0
		for q = a, b do
			sum += rawRoll[q]
		end
		local roll = sum / (b - a + 1)
		CF[k] = CFrame.lookAt(P[k], P[k] + F[k]) * CFrame.Angles(0, 0, roll)
	end
	return {
		Direction = direction,
		P = P,
		T = T,
		CF = CF,
		Length = length,
		Duration = T[count],
		OpenS = openS,
		DropS = dropS,
	}
end

local cache: { [number]: Flight } = {}

function AircraftPath.Get(direction: number): Flight
	local d = if direction < 0 then -1 else 1
	local f = cache[d]
	if not f then
		f = build(d)
		cache[d] = f
	end
	return f
end

local function bob(t: number): number
	local b = Config.Bob
	return b.Amplitude * math.sin(t * 2 * math.pi / b.Period)
end

-- aircraft CFrame and velocity t seconds into the flight (nil outside the flight)
function AircraftPath.Sample(flight: Flight, t: number): (CFrame?, Vector3)
	local T = flight.T
	local count = #T
	if t < 0 or t > T[count] then
		return nil, Vector3.zero
	end
	local lo, hi = 1, count
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if T[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local span = math.max(T[hi] - T[lo], 1e-6)
	local a = math.clamp((t - T[lo]) / span, 0, 1)
	local cf = flight.CF[lo]:Lerp(flight.CF[hi], a)
	local vel = (flight.P[hi] - flight.P[lo]) / span
	return cf + Vector3.new(0, bob(t), 0), vel
end

-- distance flown along the route t seconds into the flight
function AircraftPath.ArcAt(flight: Flight, t: number): number
	local T = flight.T
	local count = #T
	if t <= 0 then
		return 0
	elseif t >= T[count] then
		return flight.Length
	end
	local lo, hi = 1, count
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if T[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local a = math.clamp((t - T[lo]) / math.max(T[hi] - T[lo], 1e-6), 0, 1)
	return ((lo - 1) + a) * Config.SampleSpacing
end

-- can new grapples attach t seconds into a flight of this direction?
function AircraftPath.ArmedAt(direction: number, t: number): boolean
	local f = AircraftPath.Get(direction)
	local s = AircraftPath.ArcAt(f, t)
	return s >= f.OpenS and s <= f.DropS - Config.Zone.CloseBeforeDrop
end

-- has it reached the drop point (riders must let go)?
function AircraftPath.PastDropAt(direction: number, t: number): boolean
	local f = AircraftPath.Get(direction)
	return AircraftPath.ArcAt(f, t) >= f.DropS
end

-- studs of route left before the drop point
function AircraftPath.StudsToDropAt(direction: number, t: number): number
	local f = AircraftPath.Get(direction)
	return f.DropS - AircraftPath.ArcAt(f, t)
end

function AircraftPath.At(direction: number, startAt: number, serverTime: number): (CFrame?, Vector3)
	return AircraftPath.Sample(AircraftPath.Get(direction), serverTime - startAt)
end

function AircraftPath.Duration(direction: number): number
	return AircraftPath.Get(direction).Duration
end

-- mesh-unit point -> offset in the aircraft's own frame
function AircraftPath.MeshLocal(meshPoint: Vector3): Vector3
	return Config.ModelRotation:VectorToWorldSpace((meshPoint - Config.MeshCenter) * Config.Length)
end

local hookCache: { CFrame } = {}
function AircraftPath.HookLocal(i: number): CFrame
	local c = hookCache[i]
	if not c then
		local h = Config.Hooks[i]
		c = CFrame.new(AircraftPath.MeshLocal(h.Mesh) - Vector3.new(0, Config.HookDrop, 0))
		hookCache[i] = c
	end
	return c
end

function AircraftPath.HookCount(): number
	return #Config.Hooks
end



-- invalidate caches (Studio tuning: call after editing the config table at runtime)
function AircraftPath.Rebuild()
	table.clear(cache)
	table.clear(hookCache)
end

return AircraftPath
