--[[
	VANTAGE — IntroService (server)
	The operative-introduction phase, run by MatchService between the deploy (everyone spawned)
	and Prep. The server only decides and holds; every camera, pose and effect is client-side
	(VantageWeaponClient.OperativeIntro), driven by what is published here:

	  Match attribute "Intro" (JSON):
	    Id      match id
	    Start   server time of the first shot (clients count from this, so they stay in step)
	    Order   { { U = userId (0 for a stand-in), M = model name (stand-ins), N = display name,
	                T = team, A = animation name, W = weapon id, S = skin id }, ... }  Blue first
	    Teams   { Blue = { C = {x,y,z} formation centre on the floor, D = {x,z} facing }, Red = ... }
	  Phase "Intro" with PhaseEnds, like every other phase.

	What it does to characters: moves each one to a formation slot in its own spawn zone, facing
	the middle of the map, and anchors the root so nobody walks off. Roots are released and the
	attribute cleared when the phase ends, however it ends. Damage is already off (Match.Combat).
	Players whose character did not load are left out; players who leave are simply missing from
	their shot. Studio-only stand-ins (MatchConfig.Intro.StudioFill) fill teams for solo testing.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Config = require(Vantage:WaitForChild("MatchConfig"))
local WeaponConfig = require(Vantage:WaitForChild("Weapons"):WaitForChild("WeaponConfig"))

local IntroService = {}

local TEAM_ORDER = { "Blue", "Red" }
local STANDIN_FOLDER = "VantageIntroStandIns"
local SPACING = 4.1 -- line-up: studs between neighbours

-- Studio only: type "/bots 9" in chat to fill the NEXT match's intro with that many stand-in
-- operatives (teams are padded evenly, so 11 = a full 6v6 around you). "/bots 0" turns it off.
local botsWanted = 0
if RunService:IsStudio() then
	local function setBots(text: string)
		local n = tonumber(string.match(text, "^/bots%s+(%d+)"))
		if n then
			botsWanted = math.clamp(n, 0, 11)
			print("[VANTAGE] intro stand-ins for the next match:", botsWanted)
		end
	end
	task.spawn(function()
		local TextChatService = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "VantageBots"
		cmd.PrimaryAlias = "/bots"
		cmd.Triggered:Connect(function(_, text)
			setBots(text)
		end)
		cmd.Parent = TextChatService
	end)
	local function watch(p: Player)
		p.Chatted:Connect(setBots)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

local function shuffled(list)
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- line-up slot k of n (0-based), shoulder to shoulder and centred: the camera slides along it
local function slotOffset(k: number, n: number): (number, number)
	return (k - (n - 1) / 2) * SPACING, 0
end

-- Studio stand-ins carry the default rifle the same way a player's character does (a world model
-- on an UpperTorso motor), so the client treats them exactly like players.
local function armStandIn(rig: Model)
	local w = WeaponConfig.Weapons[WeaponConfig.DefaultWeapon]
	local assets = Vantage.Weapons:FindFirstChild("Assets")
	local asset = assets and w and assets:FindFirstChild(w.Asset)
	local torso = rig:FindFirstChild("UpperTorso")
	if not (asset and torso and torso:IsA("BasePart") and w.ThirdPerson) then
		return
	end
	local model = asset:Clone()
	model.Name = "VantageWorldWeapon"
	if w.ThirdPerson.Scale and w.ThirdPerson.Scale ~= 1 then
		model:ScaleTo(w.ThirdPerson.Scale)
	end
	local body = model.PrimaryPart
	if not body then
		model:Destroy()
		return
	end
	model:PivotTo(torso.CFrame * w.ThirdPerson.Hold * body.CFrame:ToObjectSpace(model:GetPivot()))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, false, true
			if d ~= body then
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = body, d
				weld.Parent = d
			end
		end
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "VantageGunMotor"
	motor.Part0, motor.Part1 = torso, body
	motor.C0 = w.ThirdPerson.Hold
	motor.Parent = body
	model.Parent = rig
	rig:SetAttribute("VantageWeapon", WeaponConfig.DefaultWeapon)
end

local function floorY(pos: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else pos.Y - 3
end

--[[ m = MatchService's match table. api = { M, now, setPhase, waitUntil, exempt }.
     Returns false if the match ended / emptied while the intro ran (same contract as waitUntil). ]]
function IntroService.Run(m, api): boolean
	local I = Config.Intro
	if not (I and I.Enabled) then
		return true
	end
	local M, now = api.M, api.now

	-- characters were just requested: give them a moment to exist
	local deadline = os.clock() + 4
	while os.clock() < deadline do
		local all = true
		for p in m.Players do
			if p.Parent and not (p.Character and p.Character:FindFirstChild("HumanoidRootPart")) then
				all = false
			end
		end
		if all then
			break
		end
		task.wait(0.1)
	end
	task.wait(0.35) -- weapons / attributes land just after the character

	local held: { BasePart } = {}
	local standIns: Folder? = nil
	local function release()
		for _, root in held do
			if root.Parent then
				root.Anchored = false
			end
		end
		table.clear(held)
		if standIns then
			standIns:Destroy()
			standIns = nil
		end
		M:SetAttribute("Intro", "")
	end

	local ok, result = pcall(function(): boolean
		-- who is introduced, per team, in a stable order
		local byTeam: { [string]: { any } } = { Blue = {}, Red = {} }
		for p, teamName in m.Players do
			local c = p.Parent and p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart")
			if c and root and byTeam[teamName] then
				table.insert(byTeam[teamName], { Player = p, Model = c, Root = root, Name = p.DisplayName })
			end
		end
		for _, list in byTeam do
			table.sort(list, function(a, b)
				return a.Name < b.Name
			end)
		end
		-- Studio stand-ins, so bigger line-ups can be watched alone
		local fill = if RunService:IsStudio() then math.max(I.StudioFill or 0, if botsWanted > 0 then math.ceil((botsWanted + 1) / 2) else 0) else 0
		local template = ServerStorage:FindFirstChild("VantageExosuit_Rig")
		if fill > 0 and template then
			local folder = Instance.new("Folder")
			folder.Name = STANDIN_FOLDER
			local serial = 0
			for _, teamName in TEAM_ORDER do
				while #byTeam[teamName] < fill do
					serial += 1
					local rig = template:Clone()
					rig.Name = "StandIn_" .. serial
					local hum = rig:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
						hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
					end
					for _, d in rig:GetDescendants() do
						if d:IsA("BasePart") then
							d.CanCollide = false
							d.Anchored = d.Name == "HumanoidRootPart"
						end
					end
					pcall(armStandIn, rig)
					rig.Parent = folder
					table.insert(byTeam[teamName], { Model = rig, Root = rig:FindFirstChild("HumanoidRootPart"), Name = string.format("OPERATIVE %02d", serial), StandIn = true })
				end
			end
			folder.Parent = Workspace
			standIns = folder
		end

		-- formations: in each team's own spawn zone, facing the middle of the map
		local ignore: { Instance } = {}
		for _, list in byTeam do
			for _, e in list do
				table.insert(ignore, e.Model)
			end
		end
		local teams = {}
		local order = {}
		for _, teamName in TEAM_ORDER do
			local list = byTeam[teamName]
			local zone = m.Zones[teamName]
			if #list > 0 then
				local centre: Vector3
				if zone then
					centre = Vector3.new((zone.Min.X + zone.Max.X) / 2, list[1].Root.Position.Y, (zone.Min.Y + zone.Max.Y) / 2)
				else
					centre = list[1].Root.Position
				end
				local toMid = Vector3.new(-centre.X, 0, -centre.Z)
				local dir = if toMid.Magnitude > 1 then toMid.Unit else Vector3.new(0, 0, -1)
				local right = dir:Cross(Vector3.yAxis)
				-- Where the line stands: toward the map from the zone centre, at the first distance
				-- where nobody is inside something and the camera's lane in front of the line is
				-- clear (spawn shelters have pillars), without leaving the spawn zone.
				local sight = RaycastParams.new()
				sight.FilterType = Enum.RaycastFilterType.Exclude
				sight.FilterDescendantsInstances = ignore
				local function solid(from: Vector3, by: Vector3): boolean
					local hit = Workspace:Raycast(from, by, sight)
					return hit ~= nil and hit.Instance.Transparency < 0.9
				end
				local reach = 11 + 2.1 * #list -- as far as the squad shot pulls back
				local inside = OverlapParams.new()
				inside.FilterType = Enum.RaycastFilterType.Exclude
				inside.FilterDescendantsInstances = ignore
				local function blocked(at: Vector3): number
					local n = 0
					for i = 1, #list do
						local p = at + right * slotOffset(i - 1, #list)
						if zone and (p.X < zone.Min.X + 1 or p.X > zone.Max.X - 1 or p.Z < zone.Min.Y + 1 or p.Z > zone.Max.Y - 1) then
							n += 4
						end
						for _, part in Workspace:GetPartBoundsInBox(CFrame.new(p), Vector3.new(2.6, 4, 2.6), inside) do
							if part.CanCollide and part.Transparency < 0.9 then
								n += 4
								break
							end
						end
						for _, side in { -1.6, 0, 1.6 } do
							if solid(p + right * side, dir * reach) then
								n += 1
							end
						end
					end
					return n
				end
				local front, best = centre, math.huge
				for _, out in { 0, 3, -3, 6, -6, 9 } do
					for _, along in { 0, 4, -4, 8, -8, 12, -12, 16, -16 } do
						local at = centre + dir * out + right * along
						local b = blocked(at) + (math.abs(out) + math.abs(along)) * 0.01 -- ties: stay central
						if b < best then
							front, best = at, b
						end
					end
				end
				local anims = shuffled(I.Anims)
				for i, e in list do
					local lateral, back = slotOffset(i - 1, #list)
					local pos = front + right * lateral - dir * back
					local y = floorY(pos, ignore) + 3
					pos = Vector3.new(pos.X, y, pos.Z)
					if e.Player and api.exempt then
						api.exempt:Fire(e.Player, I.Budget + 8)
					end
					e.Root.AssemblyLinearVelocity = Vector3.zero
					e.Model:PivotTo(CFrame.lookAt(pos, pos + dir))
					e.Root.Anchored = true
					table.insert(held, e.Root)
					local weapon = e.Model:GetAttribute("VantageWeapon") or WeaponConfig.DefaultWeapon
					table.insert(order, {
						U = if e.Player then e.Player.UserId else 0,
						M = if e.StandIn then e.Model.Name else nil,
						N = e.Name,
						T = teamName,
						A = anims[(i - 1) % #anims + 1],
						W = weapon,
						S = if e.Player then e.Player:GetAttribute("Skin_" .. tostring(weapon)) else nil,
					})
				end
				local fy = floorY(front, ignore)
				teams[teamName] = { C = { front.X, fy, front.Z }, D = { dir.X, dir.Z }, N = #list }
			end
		end
		if #order == 0 then
			return true
		end

		-- both line-ups must be loaded on every client before its cameras go there
		for p in m.Players do
			if p.Parent then
				for _, t in teams do
					task.spawn(pcall, function()
						p:RequestStreamAroundAsync(Vector3.new(t.C[1], t.C[2], t.C[3]), 3)
					end)
				end
			end
		end

		local _, total = Config.IntroSchedule(order)
		local length = I.Lead + total + I.Tail + (if RunService:IsStudio() then (I.StudioHold or 0) else 0) -- StudioHold: extra seconds for screenshots
		M:SetAttribute("Intro", HttpService:JSONEncode({ Id = m.Id, Start = now() + I.Lead, Order = order, Teams = teams }))
		api.setPhase("Intro", length)
		return api.waitUntil(now() + length, m)
	end)
	release()
	if not ok then
		warn("[VANTAGE] IntroService:", result)
		return true -- never hold the match up over a presentation error
	end
	return result
end

return IntroService
