--[[
	VANTAGE — HitValidation (server)
	Authoritative hitscan. The client only supplies WHERE it shot from (its camera) and
	WHICH DIRECTION; the server decides what was hit:
		1. Origin must be near the shooter's server-side head.
		2. World ray (map geometry) gives the maximum distance.
		3. Characters are tested against oriented hitboxes rebuilt at a rewound position
		   (lag compensation, max Config.Server.MaxRewind) AND at their current position.
	Client-provided hit positions / targets are never used.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Weapons = ReplicatedStorage.Vantage.Weapons
local Config = require(Weapons.WeaponConfig)
local WeaponMath = require(Weapons.WeaponMath)
local S = Config.Server

local HISTORY_SECONDS = 1.0
local DUMMY_TAG = "VantageDummy" -- Studio-only training targets (see WeaponService)

local HitValidation = {}
local history: { [Model]: { { t: number, cf: CFrame } } } = {}

local function targetCharacters(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c then
			table.insert(list, c)
		end
	end
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then -- live: dummies are squad bots
		for _, d in CollectionService:GetTagged(DUMMY_TAG) do
			if d:IsA("Model") then
				table.insert(list, d)
			end
		end
	end
	-- 2026-11-20 first-time training targets (TutorialService; only their trainee can damage them)
	for _, d in CollectionService:GetTagged("VantageTutorialTarget") do
		if d:IsA("Model") then
			table.insert(list, d)
		end
	end
	return list
end
HitValidation.TargetCharacters = targetCharacters

local function record()
	local now = Workspace:GetServerTimeNow()
	local seen = {}
	for _, c in targetCharacters() do
		local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			seen[c] = true
			local h = history[c]
			if not h then
				h = {}
				history[c] = h
			end
			table.insert(h, { t = now, cf = root.CFrame })
			while #h > 2 and now - h[1].t > HISTORY_SECONDS do
				table.remove(h, 1)
			end
		end
	end
	for c in history do
		if not seen[c] then
			history[c] = nil
		end
	end
end

-- Root CFrame of a character at server time t (interpolated).
local function rootAt(c: Model, t: number): CFrame?
	local h = history[c]
	if not h or #h == 0 then
		return nil
	end
	if t >= h[#h].t then
		return h[#h].cf
	end
	if t <= h[1].t then
		return h[1].cf
	end
	for i = #h, 2, -1 do
		local a, b = h[i - 1], h[i]
		if t >= a.t and t <= b.t then
			local alpha = (t - a.t) / math.max(1e-6, b.t - a.t)
			return a.cf:Lerp(b.cf, alpha)
		end
	end
	return h[#h].cf
end

HitValidation.RootAt = rootAt

local function castCharacter(c: Model, origin: Vector3, dir: Vector3, rootCF: CFrame)
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local rootInv = root.CFrame:Inverse()
	local best, bestPart = nil, nil
	local headT, headPart = nil, nil
	for _, part in c:GetChildren() do
		if part:IsA("BasePart") and WeaponMath.HitboxParts[part.Name] then
			local pad = if part.Name == "Head" then S.HeadPadding else S.HitboxPadding
			local cf = rootCF * (rootInv * part.CFrame)
			local t = WeaponMath.RayOBB(origin, dir, cf, part.Size * ((S.HitboxScale or 1) / 2) + Vector3.new(pad, pad, pad))
			if t and (not best or t < best or (part.Name == "Head" and math.abs(t - best) < 0.25)) then
				best, bestPart = t, part
			end
			if t and part.Name == "Head" then
				headT, headPart = t, part
			end
		end
	end
	return best, bestPart, headT, headPart
end

--[[
	Returns {
		Kind = "Character" | "World" | "None",
		Position, Normal, Distance, Character?, Humanoid?, Part?, IsHead?, IsLimb?, Material?
	}
]]
-- 2026-11-19: Bastion's Hex Wall is one-way: its owner's team shoots through it (EquipmentPerkServer
-- tags each wall with PerkWallTeam = team name, or "U"..UserId with no team)
local function friendlyWalls(shooter: Player): { Instance }
	local out = {}
	local f = Workspace:FindFirstChild("VantagePerkFX")
	if not f then
		return out
	end
	local key = if shooter.Team and not shooter.Neutral then shooter.Team.Name else "U" .. shooter.UserId
	for _, w in f:GetChildren() do
		if w:GetAttribute("PerkWallTeam") == key then
			table.insert(out, w)
		end
	end
	return out
end

function HitValidation.Cast(shooter: Player, origin: Vector3, dir: Vector3, range: number, clientTime: number?)
	dir = dir.Unit
	local exclude = targetCharacters()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local walls = friendlyWalls(shooter)
	if #walls > 0 then
		local filter = table.clone(exclude)
		for _, w in walls do
			table.insert(filter, w)
		end
		params.FilterDescendantsInstances = filter
	else
		params.FilterDescendantsInstances = exclude
	end
	params.IgnoreWater = true
	local world = Workspace:Raycast(origin, dir * range, params)
	local maxT = if world then (world.Position - origin).Magnitude else range

	local now = Workspace:GetServerTimeNow()
	local rewindT = now
	if type(clientTime) == "number" and clientTime == clientTime then
		rewindT = math.clamp(clientTime - S.InterpolationDelay, now - S.MaxRewind, now)
	end

	local bestT, bestChar, bestPart = nil, nil, nil
	local headHits = {} -- per character: closest head hit over both poses (current + rewound)
	for _, c in exclude do
		if c ~= shooter.Character and not c:GetAttribute("VehicleHidden") then -- crew inside a closed hull
			local hum = c:FindFirstChildOfClass("Humanoid")
			local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				-- quick reject: is the character anywhere near the ray?
				local toC = root.Position - origin
				local along = toC:Dot(dir)
				if along > -4 and along < maxT + 4 and (toC - dir * along).Magnitude < 12 then
					local poses = { root.CFrame }
					local rewound = rootAt(c, rewindT)
					if rewound then
						table.insert(poses, rewound)
					end
					for _, pose in poses do
						local t, part, ht, hpart = castCharacter(c, origin, dir, pose)
						if t and t <= maxT and (not bestT or t < bestT) then
							bestT, bestChar, bestPart = t, c, part
						end
						if ht and ht <= maxT and (not headHits[c] or ht < headHits[c].t) then
							headHits[c] = { t = ht, part = hpart }
						end
					end
				end
			end
		end
	end

	-- the ray clipped this character's head in either pose: the head wins over a body/arm box
	-- just in front of it (the enlarged boxes overlap, see Config.Server.HitboxScale)
	local hh = bestChar and headHits[bestChar]
	if hh and bestPart and bestPart.Name ~= "Head" and hh.t - bestT < 0.6 then
		bestT, bestPart = hh.t, hh.part
	end
	if bestT and bestChar and bestPart then
		return {
			Kind = "Character",
			Direction = dir,
			Position = origin + dir * bestT,
			Normal = -dir,
			Distance = bestT,
			Character = bestChar,
			Humanoid = bestChar:FindFirstChildOfClass("Humanoid"),
			Part = bestPart,
			IsHead = bestPart.Name == "Head",
			IsLimb = WeaponMath.Limbs[bestPart.Name] == true,
		}
	elseif world then
		return {
			Kind = "World",
			Position = world.Position,
			Normal = world.Normal,
			Distance = maxT,
			Material = world.Material,
			Instance = world.Instance, -- vehicles: DamageService.ApplyToVehicle
		}
	end
	return { Kind = "None", Position = origin + dir * range, Normal = -dir, Distance = range }
end

function HitValidation.Start()
	RunService.Heartbeat:Connect(record)
end

return HitValidation
