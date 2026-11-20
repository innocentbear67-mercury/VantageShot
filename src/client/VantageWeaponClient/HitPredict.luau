--[[
	VANTAGE — HitPredict (client)
	Instant client-side guess of what the server's HitValidation.Cast will decide, using the SAME
	maths: world ray first (characters excluded) for the max distance, then each character's body
	parts as oriented boxes scaled by Config.Server.HitboxScale plus the same padding, with the
	same head priority. Only the target's current (replicated) pose is tested; the server also
	tests a rewound pose, so it accepts at least everything this accepts in normal play.
	Used only to start the hit feedback without waiting a round trip; damage is still server-only.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Weapons = ReplicatedStorage.Vantage.Weapons
local Config = require(Weapons.WeaponConfig)
local WeaponMath = require(Weapons.WeaponMath)
local S = Config.Server

local HitPredict = {}

local function targets(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if RunService:IsStudio() or workspace:GetAttribute("LiveBots") == true then
		for _, d in CollectionService:GetTagged("VantageDummy") do
			if d:IsA("Model") then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function teamOf(model: Model): string?
	local p = Players:GetPlayerFromCharacter(model)
	if p then
		return if p.Team and not p.Neutral then p.Team.Name else nil
	end
	local t = model:GetAttribute("Team")
	return if t ~= nil then tostring(t) else nil
end

local function castModel(c: Model, origin: Vector3, dir: Vector3)
	local scale = (S.HitboxScale or 1) / 2
	local best, bestPart = nil, nil
	local headT, headPart = nil, nil
	for _, part in c:GetChildren() do
		if part:IsA("BasePart") and WeaponMath.HitboxParts[part.Name] then
			local pad = if part.Name == "Head" then S.HeadPadding else S.HitboxPadding
			local t = WeaponMath.RayOBB(origin, dir, part.CFrame, part.Size * scale + Vector3.new(pad, pad, pad))
			if t and (not best or t < best or (part.Name == "Head" and math.abs(t - best) < 0.25)) then
				best, bestPart = t, part
			end
			if t and part.Name == "Head" then
				headT, headPart = t, part
			end
		end
	end
	if best and headT and bestPart ~= headPart and headT - best < 0.6 then
		best, bestPart = headT, headPart
	end
	return best, bestPart
end

--[[ Returns nil, or { Model, Head, Position, Shielded } for the enemy the server should hit.
	shooter: the local character (excluded), dir: unit or not. ]]
function HitPredict.Cast(shooter: Model?, origin: Vector3, dir: Vector3, range: number)
	dir = dir.Unit
	local list = targets()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = table.clone(list)
	local fx = Workspace:FindFirstChild("VantageWeaponFX")
	if fx then
		table.insert(ignore, fx)
	end
	if Workspace.CurrentCamera then
		table.insert(ignore, Workspace.CurrentCamera)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local world = Workspace:Raycast(origin, dir * range, params)
	local maxT = if world then (world.Position - origin).Magnitude else range

	local me = Players.LocalPlayer
	local mine = if me.Team and not me.Neutral then me.Team.Name else nil
	local bestT, bestModel, bestPart = nil, nil, nil
	for _, c in list do
		if c ~= shooter and not c:GetAttribute("VehicleHidden") then
			local hum = c:FindFirstChildOfClass("Humanoid")
			local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				local team = teamOf(c)
				if not (team ~= nil and mine ~= nil and team == mine) then
					local toC = root.Position - origin
					local along = toC:Dot(dir)
					if along > -4 and along < maxT + 4 and (toC - dir * along).Magnitude < 12 then
						local t, part = castModel(c, origin, dir)
						if t and t <= maxT and (not bestT or t < bestT) then
							bestT, bestModel, bestPart = t, c, part
						end
					end
				end
			end
		end
	end
	if not bestModel then
		return nil
	end
	return {
		Model = bestModel,
		Head = bestPart.Name == "Head",
		Position = origin + dir * bestT,
		Shielded = (bestModel:GetAttribute("Shield") or 0) > 0.5,
	}
end

return HitPredict
