--[[
	VANTAGE — AimAssist (client)
	Two light helpers, only ever on enemies you can actually see:
	  Friction   mouse sensitivity drops while the crosshair is on / just beside an enemy, so a flick
	             that lands on someone sticks instead of sliding past (Loadout applies it each frame)
	  Magnetism  a shot that would only just miss an enemy's body is bent onto it before it is sent
	             (WeaponController._shoot). The server still runs its own lag-compensated hit test on
	             the bent ray, so nothing behind cover or out of reach can be hit.
	Shots already on a target are never touched (a body shot is never upgraded to a headshot).
	Setting: "AimAssist" (Gameplay). Tuning: AimAssist.Config.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AimAssist = {}
AimAssist.Enabled = true

AimAssist.Config = {
	-- magnetism: how far beside a hitbox (studs) a shot may pass and still be pulled on. It grows with
	-- range so a distant (small) target still gets help, but never past MagnetMaxAngle degrees.
	MagnetStuds = 1.3,
	MagnetPerStud = 0.012,
	MagnetMaxStuds = 3.2,
	MagnetMaxAngle = 3.5,
	HeadMagnet = 0.5, -- the head's share of that allowance (pulls onto the head are rare and honest)
	-- friction: sensitivity on a target's centre line, easing back to 1 at FrictionStuds beside it
	FrictionMin = 0.5,
	FrictionStuds = 2.4,
	FrictionPerStud = 0.012,
	FrictionMaxStuds = 4.5,
	ADSBoost = 1.2, -- a little more of both while aiming down sights
	MaxRange = 700,
	-- per weapon multipliers: Magnet (hip) / ADSMagnet (aimed) / Friction
	Weapons = {
		Longshot = { Magnet = 0.2, ADSMagnet = 0.8, Friction = 1 },
		Breacher = { Magnet = 1.2, ADSMagnet = 1.2, Friction = 0.8 },
		Quill = { Magnet = 0.3, ADSMagnet = 0.8, Friction = 1 },
		Havoc = { Magnet = 0.5, ADSMagnet = 0.6, Friction = 0.9 },
	},
}
local CFG = AimAssist.Config

local BODY = { "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart" }

-- ── who counts as an enemy (cached for a frame) ──
local cache = { At = -1, List = {} :: { Model } }
local function enemies(): { Model }
	local now = os.clock()
	if now - cache.At < 1 / 40 then
		return cache.List
	end
	cache.At = now
	local lp = Players.LocalPlayer
	local mine = if lp.Team and not lp.Neutral then lp.Team.Name else nil
	local list = {}
	local function consider(m: Model, team: string?)
		if m == lp.Character or m:GetAttribute("VehicleHidden") or m:FindFirstChildOfClass("ForceField") then
			return
		end
		if team ~= nil and mine ~= nil and team == mine then
			return
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			table.insert(list, m)
		end
	end
	for _, p in Players:GetPlayers() do
		if p ~= lp and p.Character then
			consider(p.Character, if p.Team and not p.Neutral then p.Team.Name else nil)
		end
	end
	for _, m in CollectionService:GetTagged("VantageDummy") do
		if m:IsA("Model") and m:IsDescendantOf(Workspace) then
			consider(m, m:GetAttribute("Team"))
		end
	end
	cache.List = list
	return list
end
AimAssist.Enemies = enemies

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

-- nothing solid between the eye and that part of that enemy
local function visible(character: Model?, origin: Vector3, model: Model, part: BasePart): boolean
	local ex: { Instance } = { Workspace.CurrentCamera }
	if character then
		table.insert(ex, character)
	end
	local fx = Workspace:FindFirstChild("VantageWeaponFX")
	if fx then
		table.insert(ex, fx)
	end
	losParams.FilterDescendantsInstances = ex
	local res = Workspace:Raycast(origin, part.Position - origin, losParams)
	return res == nil or res.Instance:IsDescendantOf(model)
end

-- rough radius of a hit part (the server scales hitboxes 1.25x and pads them)
local function radiusOf(part: BasePart): number
	local s = part.Size
	return (s.X + s.Y + s.Z) / 6 * 1.25
end

-- how far beside each enemy part a ray passes (negative = through it), nearest first per model
type Near = { Model: Model, Part: BasePart, Outside: number, Along: number, Head: boolean }
local function scan(origin: Vector3, dir: Vector3): { Near }
	local out = {}
	for _, m in enemies() do
		local function try(part: Instance?, head: boolean)
			if not part or not part:IsA("BasePart") then
				return
			end
			local to = part.Position - origin
			local along = to:Dot(dir)
			if along <= 2 or along > CFG.MaxRange then
				return
			end
			local perp = (to - dir * along).Magnitude
			table.insert(out, { Model = m, Part = part, Outside = perp - radiusOf(part), Along = along, Head = head })
		end
		try(m:FindFirstChild("Head"), true)
		for _, n in BODY do
			local p = m:FindFirstChild(n)
			if p then
				try(p, false)
				if n ~= "HumanoidRootPart" then
					-- one torso piece is enough for R6 / R15
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Outside < b.Outside
	end)
	return out
end

local function weaponMults(weapon, ads: number)
	local wc = CFG.Weapons[weapon.Id] or {}
	local aimed = ads > 0.5
	local magnet = if aimed then (wc.ADSMagnet or 1) * CFG.ADSBoost else (wc.Magnet or 1)
	local friction = (wc.Friction or 1) * (if aimed then CFG.ADSBoost else 1)
	return magnet, friction
end

-- Magnetism: returns the (possibly bent) shot direction.
function AimAssist.Bend(character: Model?, origin: Vector3, dir: Vector3, weapon, ads: number): Vector3
	if not AimAssist.Enabled or not weapon or weapon.Kind ~= "Gun" then
		return dir
	end
	local magnet = weaponMults(weapon, ads)
	if magnet <= 0 then
		return dir
	end
	for _, n in scan(origin, dir) do
		if n.Outside <= 0 then
			return dir -- the shot is already on someone: leave it exactly as aimed
		end
		local allow = math.min(CFG.MagnetStuds + n.Along * CFG.MagnetPerStud, CFG.MagnetMaxStuds) * magnet
		if n.Head then
			allow *= CFG.HeadMagnet
		end
		local angleOk = math.deg(math.atan2(n.Outside, n.Along)) <= CFG.MagnetMaxAngle * magnet
		if n.Outside <= allow and angleOk and visible(character, origin, n.Model, n.Part) then
			-- aim just inside the part toward where the shot was going (not its dead centre)
			local to = n.Part.Position - origin
			local closest = origin + dir * n.Along
			local side = closest - n.Part.Position
			local r = radiusOf(n.Part) * 0.45
			local point = n.Part.Position + (if side.Magnitude > r then side.Unit * r else side)
			return (point - origin).Unit
		end
	end
	return dir
end

-- Friction: a sensitivity multiplier (1 = none) for where the crosshair points right now.
function AimAssist.Friction(character: Model?, origin: Vector3, look: Vector3, weapon, ads: number): number
	if not AimAssist.Enabled or not weapon or weapon.Kind ~= "Gun" then
		return 1
	end
	local _, friction = weaponMults(weapon, ads)
	for _, n in scan(origin, look) do
		local allow = math.min(CFG.FrictionStuds + n.Along * CFG.FrictionPerStud, CFG.FrictionMaxStuds)
		if n.Outside > allow then
			return 1 -- sorted: nothing nearer
		end
		if visible(character, origin, n.Model, n.Part) then
			local f = math.clamp(n.Outside / allow, 0, 1)
			local factor = CFG.FrictionMin + (1 - CFG.FrictionMin) * f
			return math.clamp(1 - (1 - factor) * friction, 0.2, 1)
		end
	end
	return 1
end

return AimAssist
