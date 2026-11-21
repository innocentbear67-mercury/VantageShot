--[[
	VANTAGE — MapService (server, 2026-11-18)
	Map rotation loader for the map vote (MatchConfig.Maps / MapVote, driven by MatchService).

	* Exactly one map is in Workspace, always named MatchConfig.Map.Folder ("Map_LiveFire"), the
	  name every system reads (spawns, bots, kill volumes). Its id is the attribute MapId.
	* Every other map waits in ServerStorage.VantageMaps under its Store name. Load(id) moves
	  the current map back there and the chosen one in (moved, not cloned: one copy of each).
	* Maps keep their built position (Foundry Row sits at x 2400), nothing is pivoted.
	* The SpawnLocations of the loaded map are enabled; a map without a Systems folder gets a
	  copy of Live Fire's (kill volumes, gravity lifts, ambient motion).
	* Publishes on Vantage.Match: MapId, MapName, MapLighting (clients apply the preset when they
	  leave the lobby, see StarterPlayerScripts.LobbyLighting).
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("MatchConfig"))

local MapService = {}

local store = ServerStorage:FindFirstChild("VantageMaps")
if not store then
	store = Instance.new("Folder")
	store.Name = "VantageMaps"
	store.Parent = ServerStorage
end

local M: Instance? = nil
local current: string? = nil
local systemsTemplate: Instance? = nil

local function active(): Instance?
	return Workspace:FindFirstChild(Config.Map.Folder)
end

local function publish()
	local def = Config.MapById(current)
	if M then
		M:SetAttribute("MapId", current or "")
		M:SetAttribute("MapName", def and def.Name or Config.Map.Name)
		M:SetAttribute("MapLighting", def and def.Lighting or "")
	end
end

-- the map in Workspace when the server starts is the default map
do
	local map = active()
	if map then
		current = map:GetAttribute("MapId") or Config.DefaultMap
		map:SetAttribute("MapId", current)
		local sys = map:FindFirstChild("Systems")
		if sys then
			systemsTemplate = sys:Clone()
		end
	end
end

function MapService.Attach(matchFolder: Instance)
	M = matchFolder
	publish()
end

function MapService.Current(): string?
	return current
end

function MapService.CurrentName(): string
	local def = Config.MapById(current)
	return def and def.Name or Config.Map.Name
end

-- a map can be voted for if it is enabled and its model exists (in Workspace or in the store)
function MapService.Available(id: string): boolean
	local def = Config.MapById(id)
	if not def or def.Enabled == false then
		return false
	end
	return id == current or store:FindFirstChild(def.Store) ~= nil
end

-- up to n random maps from the mode's pool
function MapService.Candidates(modeId: string, n: number): { string }
	local mode = Config.Modes[modeId]
	local pool = {}
	if mode and mode.Maps then
		for _, id in mode.Maps do
			if MapService.Available(id) then
				table.insert(pool, id)
			end
		end
	else
		for _, def in Config.Maps do
			if MapService.Available(def.Id) then
				table.insert(pool, def.Id)
			end
		end
	end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(n, #pool) do
		out[i] = pool[i]
	end
	-- card order follows MatchConfig.Maps, so the same map is always in the same place
	table.sort(out, function(a, b)
		local ia, ib = 0, 0
		for k, def in Config.Maps do
			if def.Id == a then ia = k end
			if def.Id == b then ib = k end
		end
		return ia < ib
	end)
	if #out == 0 and current then
		out[1] = current
	end
	return out
end

-- most votes wins; ties (and no votes at all) are a random pick among the leaders
function MapService.Tally(choices: { string }, byPlayer: { [Player]: string }): string
	local counts = {}
	for _, id in choices do
		counts[id] = 0
	end
	for p, id in byPlayer do
		if p.Parent and counts[id] then
			counts[id] += 1
		end
	end
	local best, leaders = -1, {}
	for _, id in choices do
		if counts[id] > best then
			best, leaders = counts[id], { id }
		elseif counts[id] == best then
			table.insert(leaders, id)
		end
	end
	return leaders[math.random(1, #leaders)] or choices[1]
end

-- ─── 2026-11-20: play-area size per team size (MatchConfig.SizeClasses) ───────────────────────────────
-- Small / Medium pull the map's boundary walls in around the middle, move every team spawn (and the
-- bot rally spots) toward the centre along the spawn axis onto standable ground, and draw the new
-- edge as a low energy barrier. Every moved part keeps its original CFrame in _ZoneOrigCF; Large
-- (and moving the map back to the store) restores it.
local ORIG = "_ZoneOrigCF"
local function restoreSize(map: Instance)
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			local o = d:GetAttribute(ORIG)
			if typeof(o) == "CFrame" then
				d.CFrame = o
				d:SetAttribute(ORIG, nil)
			end
		end
	end
	local edge = map:FindFirstChild("ZoneEdge", true)
	if edge then
		edge:Destroy()
	end
end
local function moveTo(p: BasePart, cf: CFrame)
	if p:GetAttribute(ORIG) == nil then
		p:SetAttribute(ORIG, p.CFrame)
	end
	p.CFrame = cf
end

function MapService.ApplySize(cls: string?): boolean
	local map = active()
	if not map then
		return false
	end
	restoreSize(map)
	if M then
		M:SetAttribute("SizeClass", cls or "L")
	end
	local C = Config.SizeClasses and Config.SizeClasses[cls or "L"]
	if not C or (C.Axial >= 1 and C.Lateral >= 1) then
		return true
	end
	local Teams = game:GetService("Teams")
	local blueT, redT = Teams:FindFirstChild("Blue") :: Team?, Teams:FindFirstChild("Red") :: Team?
	if not (blueT and redT) then
		return false
	end
	local spawns, blue, red, nb, nr = {}, Vector3.zero, Vector3.zero, 0, 0
	for _, d in map:GetDescendants() do
		if d:IsA("SpawnLocation") and not d.Neutral then
			if d.TeamColor == blueT.TeamColor then
				blue += d.Position; nb += 1; table.insert(spawns, d)
			elseif d.TeamColor == redT.TeamColor then
				red += d.Position; nr += 1; table.insert(spawns, d)
			end
		end
	end
	if nb == 0 or nr == 0 then
		return false
	end
	blue /= nb
	red /= nr
	local FLAT = Vector3.new(1, 0, 1)
	local center = (blue + red) / 2
	local span = (red - blue) * FLAT
	if span.Magnitude < 20 then
		return false
	end
	local axis = span.Unit
	local lat = Vector3.yAxis:Cross(axis)
	local boundary = map:FindFirstChild("Gameplay") and map.Gameplay:FindFirstChild("Boundary")
	-- original lateral half-width of the play area (from the side walls)
	local latHalf = 0
	if boundary then
		for _, w in boundary:GetChildren() do
			if w:IsA("BasePart") and w.Name ~= "Ceiling" then
				local d = w.Position - center
				if math.abs(d:Dot(lat)) > math.abs(d:Dot(axis)) then
					latHalf = math.max(latHalf, math.abs(d:Dot(lat)))
				end
			end
		end
	end
	if latHalf <= 0 then
		latHalf = span.Magnitude / 2
	end
	local newLat = math.max(70, latHalf * C.Lateral)
	-- ray filter: characters and the boundary itself are not ground
	local ex = { boundary }
	for _, m in Workspace:GetChildren() do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			table.insert(ex, m)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ex
	rp.IgnoreWater = true
	local function ground(q: Vector3, refY: number): Vector3?
		local hit = Workspace:Raycast(Vector3.new(q.X, refY + 24, q.Z), Vector3.new(0, -48, 0), rp)
		if hit and hit.Normal.Y > 0.7 and math.abs(hit.Position.Y - refY) < 14 then
			if not Workspace:Raycast(hit.Position + Vector3.new(0, 0.6, 0), Vector3.new(0, 8, 0), rp) then
				return hit.Position
			end
		end
		return nil
	end
	local function standable(target: Vector3, refY: number): Vector3?
		for r = 0, 40, 5 do
			local steps = if r == 0 then 1 else 10
			for i = 0, steps - 1 do
				local a = i / steps * math.pi * 2
				local g = ground(target + Vector3.new(math.cos(a), 0, math.sin(a)) * r, refY)
				if g then
					return g
				end
			end
		end
		return nil
	end
	local function squeeze(p: Vector3, k: number): Vector3
		local d = p - center
		local a, l = d:Dot(axis), d:Dot(lat)
		return center + axis * (a * k) + lat * math.clamp(l, -(newLat - 10), newLat - 10) + Vector3.yAxis * d.Y
	end
	-- spawns: closer along the spawn axis, onto ground at their own height
	local maxAx = 0
	for _, s in spawns do
		local o = s.CFrame
		local placed = nil
		local k = C.Axial
		while not placed and k <= 1.001 do
			placed = standable(squeeze(o.Position, k), o.Position.Y - s.Size.Y / 2)
			k += 0.08
		end
		if placed then
			moveTo(s, CFrame.new(placed + Vector3.new(0, s.Size.Y / 2, 0)) * o.Rotation)
		end
		maxAx = math.max(maxAx, math.abs((s.Position - center):Dot(axis)))
	end
	-- bot rally spots follow the spawns
	local bots = map:FindFirstChild("Gameplay") and map.Gameplay:FindFirstChild("BotSpots")
	if bots then
		for _, b in bots:GetChildren() do
			if b:IsA("BasePart") then
				local g = standable(squeeze(b.Position, C.Axial), b.Position.Y - b.Size.Y / 2)
				if g then
					moveTo(b, CFrame.new(g + Vector3.new(0, b.Size.Y / 2, 0)) * b.CFrame.Rotation)
				end
			end
		end
	end
	-- walls: end walls just behind the furthest spawn, side walls at the new width; barrier visuals
	local wallAx = maxAx + 14
	local floorY = (blue.Y + red.Y) / 2
	local edge = Instance.new("Folder")
	edge.Name = "ZoneEdge"
	local function barrier(cf: CFrame, length: number)
		local v = Instance.new("Part")
		v.Name = "Barrier"
		v.Anchored, v.CanCollide, v.CanQuery, v.CanTouch, v.CastShadow = true, false, false, false, false
		v.Material = Enum.Material.Neon
		v.Color = Color3.fromRGB(70, 200, 255)
		v.Transparency = 0.86
		v.Size = Vector3.new(length, 34, 0.5)
		v.CFrame = cf
		v.Parent = edge
	end
	if boundary then
		for _, w in boundary:GetChildren() do
			if w:IsA("BasePart") and w.Name ~= "Ceiling" then
				local d = w.Position - center
				local a, l = d:Dot(axis), d:Dot(lat)
				local y = w.Position.Y
				if math.abs(a) >= math.abs(l) then
					local pos = center * FLAT + axis * (math.sign(a) * wallAx) + lat * l + Vector3.yAxis * y
					moveTo(w, CFrame.new(pos) * w.CFrame.Rotation)
					local bp = center * FLAT + axis * (math.sign(a) * wallAx) + Vector3.yAxis * (floorY + 14)
					barrier(CFrame.lookAt(bp, bp + axis), newLat * 2)
				else
					local pos = center * FLAT + lat * (math.sign(l) * newLat) + axis * a + Vector3.yAxis * y
					moveTo(w, CFrame.new(pos) * w.CFrame.Rotation)
					local bp = center * FLAT + lat * (math.sign(l) * newLat) + Vector3.yAxis * (floorY + 14)
					barrier(CFrame.lookAt(bp, bp + lat), wallAx * 2)
				end
			end
		end
	end
	edge.Parent = boundary or map
	print(string.format("[MapService] play area %s: spawns at %.0f, walls %.0f x %.0f", tostring(cls), maxAx, wallAx * 2, newLat * 2))
	return true
end

-- put the map with this id in Workspace (no-op when it already is). Returns true when it is in.
function MapService.Load(id: string?): boolean
	if not id or id == current then
		return id ~= nil
	end
	local def = Config.MapById(id)
	if not def then
		warn("[MapService] unknown map " .. tostring(id))
		return false
	end
	local nextMap = store:FindFirstChild(def.Store)
	if not nextMap then
		warn("[MapService] ServerStorage.VantageMaps." .. def.Store .. " is missing")
		return false
	end
	local t0 = os.clock()
	-- the old map back to the store under its own name
	local old = active()
	if old then
		restoreSize(old) -- 2026-11-20: back to full size before it is stored
		local oldDef = Config.MapById(old:GetAttribute("MapId") or current)
		old.Name = if oldDef then oldDef.Store else ("Map_" .. tostring(current))
		old.Parent = store
	end
	-- the new map in, with live spawns and the shared map scripts
	nextMap:SetAttribute("MapId", id)
	for _, d in nextMap:GetDescendants() do
		if d:IsA("SpawnLocation") then
			d.Enabled = true
		end
	end
	if not nextMap:FindFirstChild("Systems") and systemsTemplate then
		systemsTemplate:Clone().Parent = nextMap
	end
	nextMap.Name = Config.Map.Folder
	nextMap.Parent = Workspace
	current = id
	publish()
	print(string.format("[MapService] loaded %s in %.2f s", def.Name, os.clock() - t0))
	return true
end

return MapService
