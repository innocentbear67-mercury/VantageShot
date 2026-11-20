--[[
	VANTAGE — SignatureServer (2026-11-20): casting the 10 Signatures in a match.
	Client -> server  Remotes.Signature:FireServer("Cast", cameraLookVector)
	Server -> all     "Begin" { Id, Caster, T, ...per-Signature geometry }  every client plays FX.<Id>.Play
	                  "Hit"   { Id, Caster, Target, From }                 (Mjölnir impact arcs)
	Server -> owner   "Denied" { Reason, ReadyIn }   |   "Reset" (new match)
	The server checks: equipped + owned, alive, combat on, not in a vehicle / frozen, cooldown. It builds every
	path / point / cone itself from the caster's head and camera look, and decides every hit; damage goes through
	DamageService.Apply as { Id = "Sig_<Id>", Kind = "Signature" }; statuses through StatusService.
	A handler may return a reason string before "Begin" (no valid spot...) to refund the cooldown.
	Cooldown starts at cast; death doesn't reset it; a new match sets it to Cfg.StartCooldown.
	2026-11-20 balance pass: no lock-on / homing / guaranteed kills; every hit is telegraphed (Begin.Threat)
	and can be dodged (leave the zone, or "Dodge" press in time; see the shared block below).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Remote = Remotes:FindFirstChild("Signature")
if not Remote then Remote = Instance.new("RemoteEvent"); Remote.Name = "Signature"; Remote.Parent = Remotes end
local Catalog = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureCatalog"))
local Cfg = require(Vantage.Signatures:WaitForChild("SignatureConfig"))
local DamageService = require(script.Parent:WaitForChild("WeaponServer"):WaitForChild("DamageService"))
local Status = require(script.Parent:WaitForChild("StatusService"))
local Lock = require(Vantage.Signatures:WaitForChild("SignatureLock"))
local PathfindingService = game:GetService("PathfindingService")
local ShieldService
pcall(function()
	local m = script.Parent:FindFirstChild("ShieldService", true)
	ShieldService = m and require(m)
end)

local readyAt: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local Handlers = {}
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

local function now(): number return Workspace:GetServerTimeNow() end

local function humanoidModel(part: Instance): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return m end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end
local function bodyOf(m: Model): BasePart?
	return (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- every character in play: players + bots / dummies at the top of Workspace
local function allChars(): { Model }
	local seen, out = {}, {}
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		if ch then seen[ch] = true; table.insert(out, ch) end
	end
	for _, m in Workspace:GetChildren() do
		if m:IsA("Model") and not seen[m] and m:FindFirstChildOfClass("Humanoid") then table.insert(out, m) end
	end
	return out
end
local function collect(owner: Player, friendly: boolean)
	local list = {}
	for _, m in allChars() do
		local isOwner = m == owner.Character
		local hum = m:FindFirstChildOfClass("Humanoid")
		local body = bodyOf(m)
		if hum and hum.Health > 0 and body then
			local f = isOwner or DamageService.IsFriendly(owner, m)
			if f == friendly then table.insert(list, { Model = m, Hum = hum, Body = body }) end
		end
	end
	return list
end
local function hostiles(owner: Player) return collect(owner, false) end
local function allies(owner: Player) return collect(owner, true) end
local function flatDist(a: Vector3, b: Vector3): number return ((a - b) * FLAT).Magnitude end
-- hostiles whose body is within r (flat) of a point and not far above / below it
local function around(list, point: Vector3, r: number, below: number?, above: number?)
	local out = {}
	for _, e in list do
		local dy = e.Body.Position.Y - point.Y
		if flatDist(e.Body.Position, point) <= r and dy > -(below or 6) and dy < (above or 12) then table.insert(out, e) end
	end
	return out
end

-- world ray that ignores every character and non-solid parts
local function worldRay(origin: Vector3, dir: Vector3, caster: Model?)
	local ex = { caster }
	for _, m in allChars() do table.insert(ex, m) end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ex
	rp.IgnoreWater = true
	for _ = 1, 8 do
		local r = Workspace:Raycast(origin, dir, rp)
		if not r then return nil end
		local inst = r.Instance
		if humanoidModel(inst) or not inst.CanCollide or inst.Transparency >= 0.95 then
			rp:AddToFilter(humanoidModel(inst) or inst)
		else
			return r
		end
	end
	return nil
end
local function los(a: Vector3, b: Vector3, caster: Model?): boolean return worldRay(a, b - a, caster) == nil end
local function groundAt(pos: Vector3, caster: Model?, depth: number?): Vector3?
	local r = worldRay(pos + UP * 3, -UP * (depth or 40), caster)
	return r and r.Position or nil
end
local function flatOf(v: Vector3, fallback: Vector3): Vector3
	local f = v * FLAT
	return if f.Magnitude > 1e-3 then f.Unit else fallback
end

local function pathLen(pts: { Vector3 }): number
	local L = 0
	for i = 2, #pts do L += (pts[i] - pts[i - 1]).Magnitude end
	return L
end
local function along(pts: { Vector3 }, d: number): (Vector3, Vector3)
	for i = 2, #pts do
		local seg = pts[i] - pts[i - 1]
		local l = seg.Magnitude
		if d <= l or i == #pts then
			local dir = if l > 1e-3 then seg.Unit else Vector3.zAxis
			return pts[i - 1] + dir * math.clamp(d, 0, l), dir
		end
		d -= l
	end
	return pts[1], Vector3.zAxis
end

local function hurt(owner: Player, id: string, e, dmg: number, dir: Vector3?, isHead: boolean?)
	local w = { Id = "Sig_" .. id, Kind = "Signature", DisplayName = Catalog.ById[id] and Catalog.ById[id].Name or id }
	local ok, res = pcall(DamageService.Apply, owner, w, {
		Character = e.Model, Humanoid = e.Hum, IsHead = isHead == true, IsLimb = false, Distance = 0, Position = e.Body.Position, Direction = dir,
	}, dmg)
	if not ok then warn("[VANTAGE] Signature damage: " .. tostring(res)) end
	return ok and res or nil
end
local function outward(from: Vector3, to: Vector3, h: number, up: number): Vector3
	return flatOf(to - from, Vector3.zAxis) * h + UP * up
end
local function begin(p: Player, d)
	d.Caster = p.UserId
	d.T = now()
	Remote:FireAllClients("Begin", d)
end
local function parts(p: Player)
	local char = p.Character
	return char, char and char:FindFirstChild("Head") :: BasePart?, char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

------------------------------------------------ shared (2026-11-20 balance pass after the big playtest)
-- No lock-on, no homing, no auto-targets, no "always lands": every Signature goes where the crosshair
-- points and every hit is telegraphed to the enemies it threatens ("Threat" in the Begin data: the
-- client shows a DODGE prompt to anyone inside it). A hit on a player is resolved Dodge.Grace s after
-- contact; a DODGE press (Cfg.Dodge.Key) from Dodge.Window s before contact up to Dodge.Late s after it
-- cancels that hit completely. Presses are rate-limited (Dodge.Lockout) so spamming never works.
local D = Cfg.Dodge or { Window = 0.4, Late = 0.12, Grace = 0.12, Lockout = 1.5, BotChance = 0 }
local dodgeAt: { [Player]: number } = {}
local dodgeLast: { [Player]: number } = {}
local function alive(e): boolean
	return e ~= nil and e.Body.Parent ~= nil and e.Model.Parent ~= nil and e.Hum.Health > 0
end
local function hitFx(p: Player, id: string, e, from: Vector3, kind: string?)
	Remote:FireAllClients("Hit", { Id = id, Caster = p.UserId, Target = e.Model, From = from, Kind = kind })
end
local function segDist(a: Vector3, b: Vector3, pt: Vector3): number
	local ab = b - a
	local l2 = ab:Dot(ab)
	local t = if l2 > 1e-6 then math.clamp((pt - a):Dot(ab) / l2, 0, 1) else 0
	return (a + ab * t - pt).Magnitude
end
local function dodged(e, tHit: number, caster: Player, id: string): boolean
	local pl = Players:GetPlayerFromCharacter(e.Model)
	if not pl then
		return (D.BotChance or 0) > 0 and math.random() < D.BotChance
	end
	local at = dodgeAt[pl]
	if at and tHit - at <= D.Window and at - tHit <= D.Late then
		Remote:FireClient(pl, "Dodged", { Id = id, By = caster.DisplayName })
		if caster ~= pl then Remote:FireClient(caster, "Dodged", { Id = id, Target = pl.DisplayName, Mine = true }) end
		return true
	end
	return false
end
-- one hit on one enemy (players get Dodge.Grace s for their press to arrive; bots are hit at once)
local function strike(p: Player, id: string, e, dmg: number, dir: Vector3?, o)
	local tHit = now()
	local function apply()
		if not alive(e) or dodged(e, tHit, p, id) then return end
		hurt(p, id, e, dmg, dir, o and o.Head)
		if not o then return end
		if o.Knock then Status.Knock(e.Model, o.Knock, o.KnockTime or 1.2) end
		if o.KnockUp then Status.KnockUp(e.Model, o.KnockUp, o.KnockImmune or 4) end
		if o.Slow then Status.Slow(e.Model, o.Slow, o.SlowTime or 1) end
		if o.Freeze and not Status.Freeze(e.Model, o.Freeze, o.Immunity or 6) and o.Chill then Status.Slow(e.Model, o.Chill, o.ChillTime or 2) end
		if o.Fx then o.Fx() end
	end
	if Players:GetPlayerFromCharacter(e.Model) then task.delay(D.Grace, apply) else apply() end
end
local function sideOf(e, pos: Vector3, dir: Vector3): Vector3
	local side = (e.Body.Position - pos) * FLAT
	side -= dir * side:Dot(dir)
	return if side.Magnitude > 0.2 then side.Unit else dir:Cross(UP)
end

------------------------------------------------ 2026-11-20 (pm) homing is back: lock-on + homing, but every hit is still dodgeable
-- The locked player gets a live "Self" threat (exact time of contact, re-sent as the summon closes in)
-- so their DODGE prompt closes on the real moment of impact. No "always lands" fallbacks: a dodged or
-- outrun Signature misses. Damage is the 60% cut values in SignatureConfig.
local LS = Lock.Settings
local function pick(p: Player, id: string, from: Vector3, look: Vector3)
	return Lock.Pick(from, look, hostiles(p), LS[id])
end
local function mark(p: Player, list, id: string)
	for _, e in list do
		local pl = Players:GetPlayerFromCharacter(e.Model)
		if pl then Remote:FireClient(pl, "Marked", { Id = id, By = p.DisplayName }) end
	end
end
local function feet(e): Vector3 return e.Body.Position - UP * 3 end
local warned = setmetatable({}, { __mode = "k" })
-- tell a threatened player exactly when this Signature reaches them (rate-limited)
local function warnTarget(id: string, e, eta: number)
	local pl = Players:GetPlayerFromCharacter(e.Model)
	if not pl or eta < -0.05 or eta > (D.Warn or 1.4) + 0.3 then return end
	local hit, t = now() + eta, os.clock()
	local w = warned[e.Model]
	if w and w.Id == id and (t - w.At < 0.12 or (math.abs(w.Hit - hit) < 0.06 and t - w.At < 0.6)) then return end
	warned[e.Model] = { Id = id, Hit = hit, At = t }
	Remote:FireClient(pl, "Threat", { Id = id, Kind = "Self", Hit = hit })
end
local function navPath(a: Vector3, b: Vector3): { Vector3 }
	local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5 })
	local ok = pcall(function() path:ComputeAsync(a, b) end)
	if ok and path.Status == Enum.PathStatus.Success then
		local pts = {}
		for _, w in path:GetWaypoints() do
			local q = w.Position
			if #pts == 0 or (q - pts[#pts]).Magnitude > 1 then table.insert(pts, q) end
		end
		if #pts >= 2 then return pts end
	end
	return { a, b }
end
-- a summon running a path, then chasing its quarry straight in (the client FX runs the same rule)
local function runner(path: { Vector3 }, d0: number)
	local self = { Path = table.clone(path), D = d0 }
	self.L = pathLen(self.Path)
	function self:Step(dt: number, speed: number, quarry, chasing: boolean)
		self.D += speed * dt
		if self.D >= self.L and chasing and quarry and alive(quarry) then
			local last = self.Path[#self.Path]
			local q = feet(quarry)
			if flatDist(q, last) > 1 then
				table.insert(self.Path, q)
				self.L += (q - last).Magnitude
			end
		end
		return along(self.Path, math.min(self.D, self.L))
	end
	return self
end

------------------------------------------------ 01 MJÖLNIR: homes onto the lock (+ a second enemy); a weak hit that STUNS (1.5 s)
Handlers.Mjolnir = function(p: Player, look: Vector3, c)
	local char, head = parts(p)
	if not head then return end
	local first = pick(p, "Mjolnir", head.Position, look)
	if not first then return "NO TARGET IN SIGHT" end
	local targets = { first }
	local second, sd
	for _, e in hostiles(p) do
		if e.Model ~= first.Model and (e.Body.Position - head.Position).Magnitude <= LS.Mjolnir.Range and los(head.Position, e.Body.Position, char) then
			local d = (e.Body.Position - first.Body.Position).Magnitude
			if not second or d < sd then second, sd = e, d end
		end
	end
	if second and (c.AutoTargets or 2) >= 2 then table.insert(targets, second) end
	local models = {}
	for i, e in targets do models[i] = e.Model end
	mark(p, targets, "Mjolnir")
	begin(p, { Id = "Mjolnir", Dir = look, Range = c.Range, Targets = models })
	for _, e in targets do
		warnTarget("Mjolnir", e, c.Windup + (e.Body.Position - head.Position).Magnitude / c.OutSpeed)
	end
	task.wait(c.Windup)
	if not (char.Parent and head.Parent) then return end
	local hand = (char:FindFirstChild("RightHand") or head) :: BasePart
	local pos = hand.Position
	local hitSet = {}
	for _, e in targets do
		local t0 = os.clock()
		while os.clock() - t0 < 3 and alive(e) do
			local dt = RunService.Heartbeat:Wait()
			local to = e.Body.Position - pos
			warnTarget("Mjolnir", e, math.max(0, to.Magnitude - c.HitRadius) / c.OutSpeed)
			local prev = pos
			if to.Magnitude <= c.OutSpeed * dt + c.HitRadius then pos = e.Body.Position else pos += to.Unit * c.OutSpeed * dt end
			-- anyone the hammer passes through on the way is struck too
			for _, o in hostiles(p) do
				if not hitSet[o.Model] and segDist(prev, pos, o.Body.Position) <= c.HitRadius then
					hitSet[o.Model] = true
					strike(p, "Mjolnir", o, c.DamageOut, (o.Body.Position - head.Position).Unit,
						{ Freeze = c.Stun, Immunity = c.StunImmunity, Fx = function() hitFx(p, "Mjolnir", o, pos) end })
				end
			end
			if hitSet[e.Model] then break end
		end
	end
end

------------------------------------------------ 02 FENRIR: the wolf hunts the lock down (navmesh route, then a straight chase)
Handlers.Fenrir = function(p: Player, look: Vector3, c)
	local char, head, hrp = parts(p)
	if not (head and hrp) then return end
	local tgt = pick(p, "Fenrir", head.Position, look)
	if not tgt then return "NO TARGET IN RANGE" end
	local fwd = flatOf(tgt.Body.Position - hrp.Position, flatOf(look, Vector3.zAxis))
	local g0 = groundAt(hrp.Position + fwd * 3, char) or (hrp.Position - UP * 3)
	local path = navPath(g0, groundAt(tgt.Body.Position, char, 60) or feet(tgt))
	mark(p, { tgt }, "Fenrir")
	begin(p, { Id = "Fenrir", Origin = CFrame.lookAt(g0, g0 + fwd), Path = path, Speed = c.Speed, Chase = tgt.Model, ChaseTime = c.ChaseTime })
	task.wait(c.Windup)
	local run = runner(path, 6)
	local L0 = run.L
	local t0, hit = os.clock(), {}
	while os.clock() - t0 < L0 / c.Speed + c.ChaseTime + 0.5 do
		local dt = RunService.Heartbeat:Wait()
		local pos, dir = run:Step(dt, c.Speed, tgt, os.clock() - t0 < L0 / c.Speed + c.ChaseTime)
		if alive(tgt) and not hit[tgt.Model] then
			warnTarget("Fenrir", tgt, (math.max(0, run.L - run.D) + math.max(0, flatDist(tgt.Body.Position, pos) - c.HitRadius) * 0.3) / c.Speed)
		end
		for _, e in around(hostiles(p), pos, c.HitRadius, 4, 9) do
			if not hit[e.Model] then
				hit[e.Model] = true
				strike(p, "Fenrir", e, c.Damage, dir, { Knock = sideOf(e, pos, dir) * c.KnockSide + UP * c.KnockUp })
			end
		end
		if hit[tgt.Model] or not alive(tgt) then break end
	end
end

------------------------------------------------ 03 GUNGNIR: locks, homes onto the target, pierces anyone in between
Handlers.Gungnir = function(p: Player, look: Vector3, c)
	local char, head = parts(p)
	if not head then return end
	local tgt = pick(p, "Gungnir", head.Position, look)
	if not tgt then return "NO TARGET IN SIGHT" end
	local dir = (tgt.Body.Position - head.Position).Unit
	mark(p, { tgt }, "Gungnir")
	begin(p, { Id = "Gungnir", Dir = dir, Range = c.Range, Hold = c.Hold, Target = tgt.Model })
	warnTarget("Gungnir", tgt, c.Hold + (tgt.Body.Position - head.Position).Magnitude / c.Speed)
	task.wait(c.Hold)
	if not head.Parent then return end
	local pos, hit, n = head.Position, {}, 0
	local t0 = os.clock()
	while os.clock() - t0 < 3 and alive(tgt) and not hit[tgt.Model] do
		local dt = RunService.Heartbeat:Wait()
		local to = tgt.Body.Position - pos
		warnTarget("Gungnir", tgt, math.max(0, to.Magnitude - c.BodyRadius) / c.Speed)
		local prev = pos
		pos = if to.Magnitude <= c.Speed * dt + 1 then tgt.Body.Position else pos + to.Unit * c.Speed * dt
		for _, e in hostiles(p) do
			if not hit[e.Model] and n < c.MaxPierce and segDist(prev, pos, e.Body.Position) <= c.BodyRadius then
				hit[e.Model] = true
				n += 1
				local at = pos
				strike(p, "Gungnir", e, c.Damage * (1 - c.Falloff) ^ (n - 1), to.Unit, { Fx = function() hitFx(p, "Gungnir", e, at) end })
			end
		end
	end
end

------------------------------------------------ 04 MIDGARD: Jörmungandr erupts under the locked enemy (the ring follows them)
Handlers.Midgard = function(p: Player, look: Vector3, c)
	local char, head, hrp = parts(p)
	if not (head and hrp) then return end
	local tgt = pick(p, "Midgard", head.Position, look)
	if not tgt then return "NO TARGET IN RANGE" end
	local g = groundAt(tgt.Body.Position, char, 60) or feet(tgt)
	local gO = groundAt(hrp.Position, char) or (hrp.Position - UP * 3)
	local fwd = flatOf(g - gO, flatOf(look, Vector3.zAxis))
	local hitT = c.Windup + 0.3
	mark(p, { tgt }, "Midgard")
	begin(p, { Id = "Midgard", Origin = CFrame.lookAt(gO, gO + fwd), At = g, Target = tgt.Model,
		Threat = { Kind = "Circle", At = g, R = c.Radius, Hit = now() + hitT } })
	warnTarget("Midgard", tgt, hitT)
	task.wait(hitT)
	local at = g
	if alive(tgt) then
		local q = groundAt(tgt.Body.Position, char, 60) or feet(tgt)
		at = Vector3.new(q.X, if math.abs(q.Y - g.Y) < 10 then q.Y else g.Y, q.Z)
	end
	for _, e in around(hostiles(p), at, c.Radius, 8, 14) do
		local k = math.clamp(flatDist(e.Body.Position, at) / c.Radius, 0, 1)
		strike(p, "Midgard", e, c.Damage + ((c.EdgeDamage or c.Damage) - c.Damage) * k, UP, { KnockUp = c.KnockUp, KnockImmune = c.KnockImmune })
	end
end

------------------------------------------------ 05 VALKYRIE: rise, hover, dive onto the locked enemy
Handlers.Valkyrie = function(p: Player, look: Vector3, c)
	local char, head, hrp = parts(p)
	if not (head and hrp) then return end
	local tgt = pick(p, "Valkyrie", head.Position, look)
	if not tgt then return "NO TARGET IN SIGHT" end
	local roof = worldRay(hrp.Position, UP * (c.Rise + 3), char)
	local rise = if roof then math.max(1, roof.Position.Y - hrp.Position.Y - 3.5) else c.Rise
	local hover = hrp.Position + UP * rise
	local land = groundAt(tgt.Body.Position, char, 60) or feet(tgt)
	if worldRay(hover, land + UP * 3 - hover, char) then
		if not worldRay(hrp.Position, land + UP * 3 - hrp.Position, char) then
			rise, hover = 0.5, hrp.Position + UP * 0.5
		else
			return "NO CLEAR PATH"
		end
	end
	Status.Exempt(p, c.Total + 1.5)
	mark(p, { tgt }, "Valkyrie")
	begin(p, { Id = "Valkyrie", Start = hrp.CFrame, DiveTo = land, Hover = c.Hover, Rise = rise, Target = tgt.Model,
		Threat = { Kind = "Circle", At = land, R = c.Radius, Hit = now() + c.ImpactAt } })
	warnTarget("Valkyrie", tgt, c.ImpactAt)
	task.wait(c.ImpactAt - 0.42) -- the dive starts: lock the landing on where the target is now
	if alive(tgt) then
		local q = groundAt(tgt.Body.Position, char, 60) or feet(tgt)
		if math.abs(q.Y - land.Y) < 12 and not worldRay(hover, q + UP * 3 - hover, char) then land = q end
		warnTarget("Valkyrie", tgt, 0.42)
	end
	task.wait(0.42)
	for _, e in around(hostiles(p), land, c.Radius) do
		local k = math.clamp(flatDist(e.Body.Position, land) / c.Radius, 0, 1)
		strike(p, "Valkyrie", e, c.DamageCore + (c.DamageEdge - c.DamageCore) * k, -UP, { Knock = outward(land, e.Body.Position, c.Knock, 15) })
	end
end

------------------------------------------------ 06 RAGNARÖK: the rift follows the locked enemy, the sword drops on them, the fissure burns on
Handlers.Ragnarok = function(p: Player, look: Vector3, c)
	local char, head, hrp = parts(p)
	if not (hrp and head) then return end
	local best = pick(p, "Ragnarok", head.Position, look)
	if not best then return "NO TARGET IN RANGE" end
	mark(p, { best }, "Ragnarok")
	local function under(e) return groundAt(e.Body.Position, char, 60) or (e.Body.Position - UP * 3) end
	local fwd = flatOf(best.Body.Position - hrp.Position, flatOf(look, Vector3.zAxis))
	local tg = under(best)
	local g0 = tg - fwd * c.Forward
	local wall = worldRay(tg + UP * 2.5, fwd * (c.Length - c.Forward), char)
	local run = if wall then math.max(4, (wall.Position - (tg + UP * 2.5)).Magnitude) else c.Length - c.Forward
	begin(p, { Id = "Ragnarok", Origin = CFrame.lookAt(g0, g0 + fwd), Length = run, Target = best.Model,
		Threat = { Kind = "Circle", At = tg, R = c.ImpactRadius, Hit = now() + c.ImpactAt } })
	warnTarget("Ragnarok", best, c.ImpactAt)
	task.wait(c.ImpactAt)
	local impact = if alive(best) then under(best) else tg
	impact = Vector3.new(impact.X, if math.abs(impact.Y - tg.Y) < 10 then impact.Y else tg.Y, impact.Z)
	g0 = impact - fwd * c.Forward
	local L = c.Forward + run
	local done, burned = {}, {}
	for _, e in around(hostiles(p), impact, c.ImpactRadius, 8, 16) do
		done[e.Model] = true
		strike(p, "Ragnarok", e, c.ImpactDamage, fwd)
	end
	local t0, lastTick = os.clock(), 0
	local total = run / c.RunSpeed + c.Burn
	while os.clock() - t0 < total do
		RunService.Heartbeat:Wait()
		local el = os.clock() - t0
		local front = math.min(L, c.Forward + el * c.RunSpeed)
		local tick = el - lastTick >= 0.25
		if tick then lastTick = el end
		for _, e in hostiles(p) do
			local v = e.Body.Position - g0
			local a = v:Dot(fwd)
			local side = ((v - fwd * a) * FLAT).Magnitude
			if a >= c.Forward - 1 and a <= front and side <= c.Width and math.abs(v.Y) < 9 then
				if not done[e.Model] then
					done[e.Model] = true
					strike(p, "Ragnarok", e, c.FissureDamage, fwd)
				elseif tick and (burned[e.Model] or 0) < c.BurnMax then
					burned[e.Model] = (burned[e.Model] or 0) + c.BurnDps * 0.25
					hurt(p, "Ragnarok", e, c.BurnDps * 0.25, UP)
				end
			end
		end
	end
end

------------------------------------------------ 07 HELHEIM: Hel's gate opens toward the locked enemy; the wave freezes the near part of the cone
Handlers.Helheim = function(p: Player, look: Vector3, c)
	local char, head, hrp = parts(p)
	if not (head and hrp) then return end
	local tgt = pick(p, "Helheim", head.Position, look)
	if not tgt then return "NO TARGET IN SIGHT" end
	local fwd = flatOf(tgt.Body.Position - hrp.Position, flatOf(look, Vector3.zAxis))
	local g0 = groundAt(hrp.Position, char) or (hrp.Position - UP * 3)
	local gate = g0 + fwd * 3.5 + UP * 3
	mark(p, { tgt }, "Helheim")
	begin(p, { Id = "Helheim", Origin = CFrame.lookAt(g0, g0 + fwd), Range = c.Range, Angle = c.Angle, Freeze = c.Freeze, Target = tgt.Model,
		Threat = { Kind = "Cone", O = g0, Dir = fwd, R = c.Range, Angle = c.Angle, Hit = now() + c.Windup, Wave = c.Wave } })
	warnTarget("Helheim", tgt, c.Windup + math.clamp(flatDist(tgt.Body.Position, g0) / c.Range, 0, 1) * c.Wave)
	task.wait(c.Windup)
	local t0, done, half = os.clock(), {}, math.rad(c.Angle / 2)
	while os.clock() - t0 < c.Wave + 0.1 do
		RunService.Heartbeat:Wait()
		local front = math.min(1, (os.clock() - t0) / c.Wave) * c.Range
		for _, e in hostiles(p) do
			if not done[e.Model] then
				local v = (e.Body.Position - g0) * FLAT
				local d = v.Magnitude
				local ang = if d > 1e-3 then math.acos(math.clamp(v.Unit:Dot(fwd), -1, 1)) else 0
				local dy = e.Body.Position.Y - g0.Y
				local inCone = ang <= half or e.Model == tgt.Model -- the wave bends to reach the lock
				if d <= front + (if e.Model == tgt.Model then 2 else 0) and d <= c.Range + 2 and inCone and dy > -6 and dy < 12 and los(gate, e.Body.Position, char) then
					done[e.Model] = true
					local o = if d <= c.Range * c.FreezeFrac
						then { Freeze = c.Freeze, Immunity = c.Immunity, Chill = c.ChillSlow, ChillTime = c.ChillTime }
						else { Slow = c.ChillSlow, SlowTime = c.ChillTime }
					strike(p, "Helheim", e, c.Damage, fwd, o)
				end
			end
		end
	end
end

------------------------------------------------ 08 SLEIPNIR: ride a navmesh route to the locked enemy (then chase), trampling anyone on the way
Handlers.Sleipnir = function(p: Player, look: Vector3, c)
	local char, head, hrp = parts(p)
	if not (head and hrp) then return end
	local tgt = pick(p, "Sleipnir", head.Position, look)
	if not tgt then return "NO TARGET IN RANGE" end
	local g0 = groundAt(hrp.Position, char) or (hrp.Position - UP * 3)
	local path = navPath(g0, groundAt(tgt.Body.Position, char, 60) or feet(tgt))
	local L = pathLen(path)
	Status.Exempt(p, c.Form + L / c.Speed + c.ChaseTime + 3)
	mark(p, { tgt }, "Sleipnir")
	begin(p, { Id = "Sleipnir", Start = hrp.CFrame, Path = path, Speed = c.Speed, Chase = tgt.Model, ChaseTime = c.ChaseTime })
	task.wait(c.Form)
	local run = runner(path, 0)
	local t0, hit = os.clock(), {}
	while os.clock() - t0 < L / c.Speed + c.ChaseTime + 0.5 do
		local dt = RunService.Heartbeat:Wait()
		local pos, dir = run:Step(dt, c.Speed, tgt, os.clock() - t0 < L / c.Speed + c.ChaseTime)
		if alive(tgt) and not hit[tgt.Model] then
			warnTarget("Sleipnir", tgt, (math.max(0, run.L - run.D) + math.max(0, flatDist(tgt.Body.Position, pos) - c.HitRadius) * 0.3) / c.Speed)
		end
		for _, e in around(hostiles(p), pos, c.HitRadius, 4, 9) do
			if not hit[e.Model] then
				hit[e.Model] = true
				strike(p, "Sleipnir", e, c.Damage, dir, { Knock = sideOf(e, pos, dir) * c.KnockSide + UP * c.KnockUp })
			end
		end
		if hit[tgt.Model] or not alive(tgt) then break end
	end
end

------------------------------------------------ 09 BIFRÖST: pick a spot on the map; the bridge opens (telegraphed), you cross, the landing blasts
Handlers.Bifrost = function(p: Player, look: Vector3, c, dest: any)
	local char, head, hrp = parts(p)
	if not (head and hrp) then return end
	if typeof(dest) ~= "Vector3" or dest ~= dest then return "PICK A SPOT ON THE MAP" end
	local g = groundAt(dest + UP * 2, char, 14)
	if not g then return "NO GROUND THERE" end
	if worldRay(g + UP * 0.5, UP * 6, char) then return "NO ROOM THERE" end
	if (g - hrp.Position).Magnitude > c.Range then return "TOO FAR" end
	if g.Y < Workspace.FallenPartsDestroyHeight + 30 then return "NO GROUND THERE" end
	local from = groundAt(hrp.Position, char) or (hrp.Position - UP * 3)
	Status.Exempt(p, c.TeleportAt + 3)
	begin(p, { Id = "Bifrost", From = CFrame.lookAt(hrp.Position, hrp.Position + flatOf(g - hrp.Position, flatOf(look, Vector3.zAxis))), To = g,
		Threat = { Kind = "Circle", At = g, R = c.Radius, Hit = now() + c.TeleportAt } })
	task.wait(c.TeleportAt)
	for _, e in around(hostiles(p), g, c.Radius, 6, 12) do
		local k = math.clamp(flatDist(e.Body.Position, g) / c.Radius, 0, 1)
		strike(p, "Bifrost", e, c.ArriveCore + (c.ArriveEdge - c.ArriveCore) * k, UP,
			{ Knock = outward(g, e.Body.Position, c.Knock, 15), Fx = function() hitFx(p, "Bifrost", e, g, "Arrive") end })
	end
	task.wait(c.ExplodeDelay)
	for _, e in around(hostiles(p), from, c.Radius) do
		local k = math.clamp(flatDist(e.Body.Position, from) / c.Radius, 0, 1)
		strike(p, "Bifrost", e, c.DamageCore + (c.DamageEdge - c.DamageCore) * k, UP, { Knock = outward(from, e.Body.Position, c.Knock, 15) })
	end
end

------------------------------------------------ 10 YGGDRASIL: a ring of root walls; allies inside get shield + heal, enemies caught are impaled
Handlers.Yggdrasil = function(p: Player, look: Vector3, c)
	local char, _, hrp = parts(p)
	if not hrp then return end
	local g = groundAt(hrp.Position, char) or (hrp.Position - UP * 3)
	local base = math.random() * math.pi * 2
	local inside = {}
	for _, e in allies(p) do
		if flatDist(e.Body.Position, g) <= c.Spread + 1 and math.abs(e.Body.Position.Y - g.Y) < 10 then table.insert(inside, e) end
	end
	local models = {}
	for i, e in inside do models[i] = e.Model end
	local riseT = c.Windup + c.Rise * 0.5
	begin(p, { Id = "Yggdrasil", Origin = CFrame.lookAt(g, g + flatOf(look, Vector3.zAxis)), At = g, Duration = c.Duration, Base = base, Allies = models,
		Threat = { Kind = "Circle", At = g, R = c.Spread + 3, Hit = now() + riseT } })
	task.wait(riseT)
	for _, e in inside do
		if ShieldService and ShieldService.Add then pcall(ShieldService.Add, e.Model, c.Shield) end
	end
	for _, e in around(hostiles(p), g, c.Spread + 3, 4, 9) do
		strike(p, "Yggdrasil", e, c.ImpaleDamage or 90, UP, { Slow = 0.5, SlowTime = 2,
			Fx = function() Remote:FireAllClients("Hit", { Id = "Yggdrasil", Caster = p.UserId, Target = e.Model, From = g, Kind = "Impale" }) end })
	end
	local folder = Instance.new("Folder")
	folder.Name = "SigRoots_" .. p.UserId
	for i = 1, 6 do
		local a = base + (i - 1) * (math.pi * 2 / 6)
		local inner = i % 2 == 0
		local pos = g + Vector3.new(math.cos(a), 0, math.sin(a)) * c.Spread * (if inner then 0.62 else 1)
		local part = Instance.new("Part")
		part.Name = "Root"
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(c.RootW * (if inner then 0.8 else 1), c.RootH, 2.2)
		part.CFrame = CFrame.new(pos + UP * (c.RootH / 2)) * CFrame.Angles(0, -a + math.pi / 2, 0)
		part.Parent = folder
	end
	folder.Parent = Workspace
	-- the World Tree heals everyone of the caster's team standing in the grove
	local t0, lastFx = os.clock(), {}
	while os.clock() - t0 < c.Duration do
		local dt = task.wait(0.1)
		for _, e in allies(p) do
			if flatDist(e.Body.Position, g) <= c.Spread + 1.5 and math.abs(e.Body.Position.Y - g.Y) < 10 and e.Hum.Health < e.Hum.MaxHealth then
				e.Hum.Health = math.min(e.Hum.MaxHealth, e.Hum.Health + c.HealRate * dt)
				if os.clock() - (lastFx[e.Model] or 0) > 0.45 then
					lastFx[e.Model] = os.clock()
					Remote:FireAllClients("Hit", { Id = "Yggdrasil", Caster = p.UserId, Target = e.Model, From = g })
				end
			end
		end
	end
	folder:Destroy()
end

------------------------------------------------ casting
local function deny(p: Player, reason: string, readyIn: number?)
	Remote:FireClient(p, "Denied", { Reason = reason, ReadyIn = readyIn })
end

local function cast(p: Player, look: any, extra: any)
	if typeof(look) ~= "Vector3" or look ~= look or look.Magnitude < 0.5 or look.Magnitude > 1.5 then return end
	local id = p:GetAttribute("Signature")
	if not (type(id) == "string" and Catalog.Valid(id) and Catalog.Owns(p, id)) then return deny(p, "NO SIGNATURE") end
	local c, h = Cfg.Sig[id], Handlers[id]
	if not (c and c.Implemented and h) then return deny(p, "COMING SOON") end
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum and hum.Health > 0) then return end
	if not DamageService.CombatEnabled() then return deny(p, "COMBAT OFFLINE") end
	if char:GetAttribute("InVehicle") or char:GetAttribute("VantageHanging") or (char:GetAttribute("Status_FrozenUntil") or 0) > now() then return deny(p, "CAN'T CAST NOW") end
	local t = os.clock()
	if RunService:IsStudio() and p:GetAttribute("DevSigNoCooldown") then readyAt[p] = 0 end -- Studio test hook
	if (readyAt[p] or 0) > t then return deny(p, "ON COOLDOWN", readyAt[p] - t) end
	local devFree = RunService:IsStudio() and p:GetAttribute("DevSigNoCooldown") and not ({ Valkyrie = true, Sleipnir = true, Bifrost = true })[id]
	if busy[p] and not devFree then return end
	readyAt[p] = t + c.Cooldown
	local holds = not devFree -- Studio no-cooldown casts of non-movers don't block the next cast
	if holds then busy[p] = true end
	task.spawn(function()
		local ok, res = pcall(h, p, look.Unit, c, extra)
		if not ok then
			warn("[VANTAGE] Signature " .. id .. ": " .. tostring(res))
		elseif type(res) == "string" then
			readyAt[p] = nil -- nothing was cast: refund the cooldown
			deny(p, res, 0)
		end
		if holds then busy[p] = nil end
	end)
end

Remote.OnServerEvent:Connect(function(p: Player, action: any, look: any, extra: any)
	if action == "Cast" then
		cast(p, look, extra)
	elseif action == "Dodge" then
		-- look = the client's press time (synced server clock); trusted only within 0.4 s of arrival
		local t = now()
		if t - (dodgeLast[p] or -1e9) < (D.Lockout or 1.5) then return end
		dodgeLast[p] = t
		local at = if type(look) == "number" and look == look and look <= t + 0.05 and look >= t - 0.4 then look else t
		dodgeAt[p] = at
	end
end)

local match = DamageService.MatchFolder()
match:GetAttributeChangedSignal("MatchId"):Connect(function()
	table.clear(readyAt)
	-- 2026-11-20: a new match starts every Signature on Cfg.StartCooldown
	local sc = Cfg.StartCooldown or 0
	if sc > 0 then
		for _, pl in Players:GetPlayers() do readyAt[pl] = os.clock() + sc end
	end
	Remote:FireAllClients("Reset", sc)
end)
Players.PlayerRemoving:Connect(function(p) readyAt[p] = nil; busy[p] = nil; dodgeAt[p] = nil; dodgeLast[p] = nil end)

-- Studio test hook: player attribute DevSigCast = look Vector3 casts the equipped Signature from the server
if RunService:IsStudio() then
	local function hook(p: Player)
		p:GetAttributeChangedSignal("DevSigCast"):Connect(function()
			local v = p:GetAttribute("DevSigCast")
			if typeof(v) == "Vector3" then cast(p, v, p:GetAttribute("DevSigDest")) end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do hook(p) end
end
