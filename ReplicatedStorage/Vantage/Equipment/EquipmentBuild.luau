--[[
	VANTAGE — EquipmentBuild (shared, 2026-11-17)
	Puts the equipped Shield Pack and Grappling Hook on a character, on the first-person arms and on the
	flying hook. Templates: Vantage.Equipment.Models.<Id> — MeshParts named <Group>__<Mat> with RootCF
	(part CFrame in the item's own frame). Pack frame origin = the back-armour mount; hook frame origin =
	launcher centre, muzzle along -Z, saddle down (-Y).

	  EquipmentBuild.Attach(character, slot, id)  -> Model ("VantageEquipPack" / "VantageGrappleLauncher")
	  EquipmentBuild.AttachAll(character, packId, hookId)
	  EquipmentBuild.Dress(character, packId, hookId)  attributes (ids, ShieldColor*, HookColor*) + both models
	  EquipmentBuild.ApplyFP(armsModel, hookId)   first-person launcher on the viewmodel's left forearm
	  EquipmentBuild.HeadModel(hookId)            the hook head (for GrappleFX's flying hook), pivot = dock point
	Animated groups (spin / sway / clamp) are driven on clients by one RenderStepped loop (tag VantageEquipAnim).
	The launcher keeps the old names (Model "VantageGrappleLauncher", part "Emitter" + "GrappleMuzzle") so
	GrappleFX and anything else that looked for the old launcher still finds the muzzle.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Equipment = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("Equipment")
local Models = Equipment:WaitForChild("Models")
local Data = require(Equipment:WaitForChild("EquipmentModels"))
local Catalog = require(Equipment:WaitForChild("EquipmentCatalog"))

local Build = {}

-- where each slot sits (bone frame). Pack: on the back armour of UpperTorso (back = +Z, armour surface
-- ~0.94 behind the torso centre). Launcher: outer side of the left forearm (-X), muzzle toward the hand
-- (-Y), saddle on the gauntlet surface (~0.19 out from the arm axis).
local LAUNCHER_ROT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0))
Build.Mount = {
	Pack = { Bone = "UpperTorso", CF = CFrame.new(0, 0.08, 0.9), Scale = 1 },
	Hook = { Bone = "LeftLowerArm", CF = CFrame.new(-0.27, 0.06, 0) * LAUNCHER_ROT, Scale = 1 },
	HookFP = { Bone = "LeftLowerArm", CF = CFrame.new(-0.235, 0.05, 0) * LAUNCHER_ROT, Scale = 0.8 },
}
local HEAD_GROUPS = { Head = true, Claws = true, Barbs = true, Disc = true, Petals = true, Crescents = true }
Build.HeadGroups = HEAD_GROUPS

local function template(id: string): Folder?
	return Models:FindFirstChild(id) :: Folder?
end

local function animInfo(id: string, group: string)
	local d = Data[id]
	return d and d.anims and d.anims[group]
end

-- clone the template's pieces, placed at frame * RootCF (scaled), into `parent`
local function clonePieces(id: string, frame: CFrame, scale: number, filter: ((string) -> boolean)?, prefix: string?)
	local t = template(id)
	if not t then
		return {}
	end
	local out = {}
	for _, src in t:GetChildren() do
		if src:IsA("BasePart") then
			local g = src:GetAttribute("Group")
			if filter and not filter(g) then
				continue
			end
			local p = src:Clone()
			local rcf = src:GetAttribute("RootCF") :: CFrame
			p.Size = src.Size * scale
			p.CFrame = frame * (rcf.Rotation + rcf.Position * scale)
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p:SetAttribute("RootCF", nil)
			p.Name = (prefix or "") .. src.Name
			table.insert(out, p)
		end
	end
	return out
end

-- weld pieces to `anchor`; animated groups ride a Weld on their first piece (C0 driven by the animator)
local function rig(pieces, anchor: BasePart, id: string, frame: CFrame, scale: number, parent: Instance)
	local roots = {}
	for _, p in pieces do
		local g = p:GetAttribute("Group")
		local an = animInfo(id, g)
		if an then
			local root = roots[g]
			if not root then
				roots[g] = p
				local w = Instance.new("Weld")
				w.Name = "EquipAnimWeld"
				w.Part0, w.Part1 = anchor, p
				w.C0 = anchor.CFrame:ToObjectSpace(p.CFrame)
				w.Parent = p
				local pv = Instance.new("Attachment")
				pv.Name = "AnimPivot"
				pv.Position = p.CFrame:PointToObjectSpace(frame * (an.p * scale))
				pv.Parent = p
				p:SetAttribute("AnimKind", an.k)
				p:SetAttribute("AnimAxis", p.CFrame:VectorToObjectSpace(frame:VectorToWorldSpace(an.a.Unit)))
				p:SetAttribute("AnimPhase", math.random() * 6.28)
				CollectionService:AddTag(p, "VantageEquipAnim")
			else
				local wc = Instance.new("WeldConstraint")
				wc.Part0, wc.Part1 = root, p
				wc.Parent = p
			end
		else
			local wc = Instance.new("WeldConstraint")
			wc.Part0, wc.Part1 = anchor, p
			wc.Parent = p
		end
		p.Parent = parent
	end
end

-- ── fitted mounts (2026-11-17): players are their own Roblox avatars now (blocky, Rthro, slim...), so
-- each mount is worked out from the bone's own size instead of fixed exosuit offsets.
local boundsCache: { [string]: { Vector3 } } = {}
local function bounds(id: string): (Vector3, Vector3)
	local b = boundsCache[id]
	if not b then
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		local t = template(id)
		for _, p in (t and t:GetChildren() or {}) do
			if p:IsA("BasePart") then
				local rcf = p:GetAttribute("RootCF")
				local c = if typeof(rcf) == "CFrame" then rcf.Position else Vector3.zero
				lo, hi = lo:Min(c - p.Size / 2), hi:Max(c + p.Size / 2)
			end
		end
		if lo.X == math.huge then
			lo, hi = Vector3.new(-0.1, -0.1, -0.6), Vector3.new(0.1, 0.1, 0.3)
		end
		b = { lo, hi }
		boundsCache[id] = b
	end
	return b[1], b[2]
end

-- the pack: flat on the UpperTorso's back, scaled to the torso's width
function Build.PackMount(bone: BasePart, id: string): (CFrame, number)
	local s = math.clamp(bone.Size.X / 2, 0.75, 1.3)
	return CFrame.new(0, bone.Size.Y * 0.05, bone.Size.Z / 2 - 0.03), s
end

-- the launcher: on the outer side of the left forearm (-X), muzzle toward the hand (-Y), saddle on the
-- arm's surface, slid down so the tip of the docked head stops just short of the wrist (never inside
-- the hand), and scaled so the whole launcher fits the forearm's length.
function Build.HookMount(bone: BasePart, id: string): (CFrame, number)
	local lo, hi = bounds(id)
	local w, L = bone.Size.X, bone.Size.Y
	local length = math.max(0.2, hi.Z - lo.Z)
	local s = math.clamp(math.min(w / 0.95, (L * 0.98) / length), 0.45, 1.3)
	local x = -(w / 2) + lo.Y * s + 0.02 -- lo.Y < 0: the saddle (template -Y) rests on the arm surface
	local y = -L / 2 - lo.Z * s + 0.04 -- lo.Z < 0: the head tip (template -Z) ends at the wrist
	return CFrame.new(x, y, 0) * LAUNCHER_ROT, s
end

local function clear(character: Instance, slot: string)
	local name = if slot == "Pack" then "VantageEquipPack" else "VantageGrappleLauncher"
	for _, c in character:GetChildren() do
		if c.Name == name then
			c:Destroy()
		end
	end
end

function Build.Attach(character: Model, slot: string, id: string?): Model?
	id = if id and Catalog.Valid(slot, id) then id else Catalog.Default[slot]
	local m = Build.Mount[slot]
	local bone = character:FindFirstChild(m.Bone)
	if not (bone and bone:IsA("BasePart")) then
		return nil
	end
	clear(character, slot)
	local model = Instance.new("Model")
	model.Name = if slot == "Pack" then "VantageEquipPack" else "VantageGrappleLauncher"
	model:SetAttribute("EquipId", id)
	local mcf, scale = (if slot == "Pack" then Build.PackMount else Build.HookMount)(bone :: BasePart, id :: string)
	local frame = bone.CFrame * mcf
	local pieces = clonePieces(id :: string, frame, scale, nil, if slot == "Hook" then "Grapple_" else nil)
	rig(pieces, bone, id :: string, frame, scale, model)
	if slot == "Hook" then
		-- muzzle: an invisible emitter part where the cable leaves (GrappleFX looks for "Emitter")
		local headZ = (template(id :: string) and template(id :: string):GetAttribute("HeadZ")) or -0.32
		local e = Instance.new("Part")
		e.Name = "Emitter"
		e.Size = Vector3.one * 0.05
		e.Transparency = 1
		e.CanCollide, e.CanQuery, e.CanTouch, e.Massless = false, false, false, true
		e.CFrame = frame * CFrame.new(0, 0, headZ * scale)
		local wc = Instance.new("WeldConstraint")
		wc.Part0, wc.Part1 = bone, e
		wc.Parent = e
		local a = Instance.new("Attachment")
		a.Name = "GrappleMuzzle"
		a.Parent = e
		e.Parent = model
	end
	model.Parent = character
	return model
end

function Build.AttachAll(character: Model, packId: string?, hookId: string?)
	Build.Attach(character, "Pack", packId)
	Build.Attach(character, "Hook", hookId)
end
-- the whole look: character attributes (ids + colours, read by ShieldFX / GrappleFX / ShieldService)
-- and both models. Server: LoadoutService on spawn / change; also bots (SquadBots) and the lobby rig.
function Build.Dress(character: Model, packId: string?, hookId: string?)
	packId = if packId and Catalog.Valid("Pack", packId) then packId else Catalog.Default.Pack
	hookId = if hookId and Catalog.Valid("Hook", hookId) then hookId else Catalog.Default.Hook
	local pk, hk = Catalog.Get(packId), Catalog.Get(hookId)
	character:SetAttribute("EquipPack", packId)
	character:SetAttribute("EquipHook", hookId)
	character:SetAttribute("ShieldColor", pk.Color)
	character:SetAttribute("ShieldColor2", pk.Color2)
	character:SetAttribute("HookColor", hk.Color)
	character:SetAttribute("HookColor2", hk.Color2)
	if not character:FindFirstChild("UpperTorso") then
		character:WaitForChild("UpperTorso", 8)
	end
	if not character:FindFirstChild("LeftLowerArm") then
		character:WaitForChild("LeftLowerArm", 8)
	end
	Build.AttachAll(character, packId, hookId)
end

-- first person: the launcher on the viewmodel's left forearm (pieces become children of the bone so the
-- viewmodel poses them like the rest of the arm). The old Grapple* placeholder parts are hidden; the old
-- GrappleEmitter moves to the new muzzle so GrappleFX's first-person cable start stays right.
function Build.ApplyFP(arms: Model, hookId: string?, weld: boolean?)
	hookId = if hookId and Catalog.Valid("Hook", hookId) then hookId else Catalog.Default.Hook
	local bone = arms:FindFirstChild(Build.Mount.HookFP.Bone)
	if not (bone and bone:IsA("BasePart")) then
		return
	end
	for _, c in bone:GetChildren() do
		if c:IsA("BasePart") and string.sub(c.Name, 1, 8) == "Grapple_" then
			c:Destroy()
		elseif c:IsA("BasePart") and string.sub(c.Name, 1, 7) == "Grapple" and c.Name ~= "GrappleEmitter" then
			c.Transparency = 1
		end
	end
	local mcf, scale = Build.HookMount(bone, hookId :: string)
	local frame = bone.CFrame * mcf
	for _, p in clonePieces(hookId :: string, frame, scale, nil, "Grapple_") do
		p.CastShadow = false
		if weld then
			-- avatar-arm viewmodel: the limbs are moved by CFrame each frame, welded pieces ride along
			p.Anchored, p.Massless = false, true
			local wc = Instance.new("WeldConstraint")
			wc.Part0, wc.Part1 = bone, p
			wc.Parent = p
		else
			p.Anchored = true -- template viewmodel: it poses its bone children itself
		end
		p.Parent = bone
	end
	local headZ = (template(hookId :: string) and template(hookId :: string):GetAttribute("HeadZ")) or -0.32
	local e = bone:FindFirstChild("GrappleEmitter")
	if not e then
		e = Instance.new("Part")
		e.Name = "GrappleEmitter"
		e.Size = Vector3.one * 0.05
		e.CanCollide, e.CanQuery, e.CanTouch, e.CastShadow, e.Massless = false, false, false, false, true
		e.Anchored = not weld
		e.Parent = bone
	end
	if e:IsA("BasePart") then
		e.CFrame = frame * CFrame.new(0, 0, headZ * scale)
		e.Transparency = 1
		if weld and not e:FindFirstChildOfClass("WeldConstraint") then
			e.Anchored = false
			local wc = Instance.new("WeldConstraint")
			wc.Part0, wc.Part1 = bone, e
			wc.Parent = e
		end
	end
end

-- the hook head on its own (for the flying hook): pivot = the dock point, facing -Z
function Build.HeadModel(hookId: string?, scale: number?): Model?
	hookId = if hookId and Catalog.Valid("Hook", hookId) then hookId else Catalog.Default.Hook
	local t = template(hookId :: string)
	if not t then
		return nil
	end
	local headZ = t:GetAttribute("HeadZ") or -0.32
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "VantageHookHead"
	local frame = CFrame.new(0, 0, -headZ * s) -- dock point at the origin
	local first
	for _, p in clonePieces(hookId :: string, frame, s, function(g)
		return HEAD_GROUPS[g] == true
	end) do
		p.Anchored = true
		p.CastShadow = false
		p.Parent = model
		first = first or p
	end
	if not first then
		model:Destroy()
		return nil
	end
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.one * 0.05
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide, pivot.CanQuery, pivot.CanTouch = false, false, false
	pivot.CFrame = CFrame.new()
	pivot.Parent = model
	model.PrimaryPart = pivot
	return model
end

-- the dock (head) pieces on a character's launcher, so GrappleFX can hide them while the hook is out
function Build.DockedHead(character: Instance): { BasePart }
	local out = {}
	local l = character:FindFirstChild("VantageGrappleLauncher")
	if l then
		for _, p in l:GetChildren() do
			if p:IsA("BasePart") and HEAD_GROUPS[p:GetAttribute("Group") or ""] then
				table.insert(out, p)
			end
		end
	end
	return out
end

-- ── client animator ──────────────────────────────────────────────────────────────────────
-- Spin: constant turn. Swing: slow sway (wings / fins). Clamp: a gentle breathing open-close.
local SPEC = {
	Spin = function(t, ph) return t * 1.6 + ph end,
	Swing = function(t, ph) return math.rad(5) * math.sin(t * 1.3 + ph) end,
	Clamp = function(t, ph) return math.rad(9) * (0.5 + 0.5 * math.sin(t * 2.2 + ph)) end,
}
function Build.AnimOffset(p: BasePart, t: number): CFrame
	local f = SPEC[p:GetAttribute("AnimKind") or ""]
	if not f then
		return CFrame.identity
	end
	local pv = p:FindFirstChild("AnimPivot") :: Attachment?
	local piv = if pv then CFrame.new(pv.Position) else CFrame.identity
	local axis = p:GetAttribute("AnimAxis") :: Vector3
	return piv * CFrame.fromAxisAngle(axis, f(t, p:GetAttribute("AnimPhase") or 0)) * piv:Inverse()
end

if RunService:IsClient() and not _G.__VantageEquipAnimator then
	_G.__VantageEquipAnimator = true
	local base = setmetatable({}, { __mode = "k" })
	-- 2026-11-20 perf: only parts near the camera animate (weld writes move whole assemblies)
	local NEAR = 90
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cam = workspace.CurrentCamera
		local cp = if cam then cam.CFrame.Position else Vector3.zero
		for _, p in CollectionService:GetTagged("VantageEquipAnim") do
			if p:IsA("BasePart") and (p.Position - cp).Magnitude < NEAR and p:IsDescendantOf(workspace) then
				local w = p:FindFirstChild("EquipAnimWeld") :: Weld?
				if w then
					if not base[w] then
						base[w] = w.C0
					end
					w.C0 = base[w] * Build.AnimOffset(p, t)
				end
			end
		end
	end)
end

return Build
