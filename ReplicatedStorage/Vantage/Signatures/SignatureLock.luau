--!nonstrict
--[[
	VANTAGE — Signature lock-on (shared by SignatureServer and SignatureClient) — 2026-11-20
	Every aimed Signature picks its main target the same way on both sides, so the brackets the caster
	sees on the HUD are the enemy the server will hit:
	  1. the enemy nearest the crosshair inside the cone (and in sight, for LOS Signatures)
	  2. otherwise the nearest enemy in sight (Fallback "visible") or the nearest at all (Fallback "any")
	Candidates are { Model = Model, Body = BasePart }.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lock = {}

Lock.Settings = {
	Mjolnir = { Range = 110, Cone = 30, LOS = true, Fallback = "visible" },
	Gungnir = { Range = 300, Cone = 12, LOS = true, Fallback = "visible" },
	Valkyrie = { Range = 80, Cone = 35, LOS = true, Fallback = "visible" },
	Ragnarok = { Range = 220, Cone = 20, LOS = false, Fallback = "any" },
	Midgard = { Range = 220, Cone = 25, LOS = false, Fallback = "any" },
	Fenrir = { Range = 180, Cone = 30, LOS = false, Fallback = "any" },
	Sleipnir = { Range = 160, Cone = 30, LOS = false, Fallback = "any" },
	Helheim = { Range = 45, Cone = 45, LOS = true, Fallback = "visible" },
}

local function humanoidModel(inst: Instance): Model?
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return m end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- every character in play: players + bots / dummies at the top of Workspace
function Lock.Chars(): { Model }
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

-- world ray that ignores characters, non-solid and invisible parts
function Lock.Ray(origin: Vector3, dir: Vector3, ignore: { Instance }?)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore or Lock.Chars()
	rp.IgnoreWater = true
	for _ = 1, 10 do
		local r = Workspace:Raycast(origin, dir, rp)
		if not r then return nil end
		local inst = r.Instance
		local hm = humanoidModel(inst)
		if hm or not inst.CanCollide or inst.Transparency >= 0.95 then
			rp:AddToFilter(hm or inst)
		else
			return r
		end
	end
	return nil
end

function Lock.Visible(a: Vector3, b: Vector3, ignore: { Instance }?): boolean
	return Lock.Ray(a, b - a, ignore) == nil
end

function Lock.Pick(origin: Vector3, look: Vector3, cands, o, ignore: { Instance }?)
	if not o then return nil end
	ignore = ignore or Lock.Chars()
	local cone = math.rad(o.Cone or 25)
	local best, bestS, near, nearD, any, anyD
	for _, e in cands do
		local body = e.Body
		if body and body.Parent then
			local p = body.Position
			local to = p - origin
			local d = to.Magnitude
			if d <= o.Range and d > 0.5 then
				local vis = true
				if o.LOS or o.Fallback == "visible" then
					local head = e.Model:FindFirstChild("Head")
					vis = Lock.Visible(origin, p, ignore) or (head ~= nil and Lock.Visible(origin, head.Position, ignore))
				end
				local ang = math.acos(math.clamp(to.Unit:Dot(look), -1, 1))
				if ang <= cone and (vis or not o.LOS) then
					local s = ang + d / o.Range * 0.12
					if not best or s < bestS then best, bestS = e, s end
				end
				if vis and (not near or d < nearD) then near, nearD = e, d end
				if not any or d < anyD then any, anyD = e, d end
			end
		end
	end
	if best then return best end
	if o.Fallback == "visible" then return near end
	if o.Fallback == "any" then return near or any end
	return nil
end

return Lock
