--[[
	VANTAGE — ForgeCommon (Studio build tool)
	Shared scaffolding for the Forge arsenal builders (ForgeArsenal.*). Same asset contract as
	ForgeBuilds.Vanguard (see that module's header): Root + attachments, component Models with
	Role parts, Socket_* attachments, a Real Magazine model, one part per MovingPart.

	local ctx = Common.Begin(Kit, "Sentinel", origin)
	ctx.B(component, name, role, centre, size, { Bevel, Axes, Cuts, Holes, CF, Rot })   root space
	ctx.cyz(cy, cz, y1, z1, y2, z2, oy, oz)   a YZ cut through two root-space points of a block
	                                          centred at (cy, cz); (oy, oz) = the corner removed
	ctx.Rod(component, name, role, a, b, w, h, o)   block running from point a to point b
	Common.Finish(ctx, oldAsset, magBody?, attachments, attributes)
]]
local V = Vector3.new

local Common = {}

function Common.Begin(Kit, name: string, O: CFrame)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide, root.CanQuery, root.CanTouch, root.Massless = false, false, false, true
	root.CFrame = O
	root.Parent = model
	model.PrimaryPart = root

	local ctx = { Kit = Kit, O = O, Model = model, Root = root, Comps = {}, BV = Kit.Bevel, Count = 0 }
	function ctx.comp(n: string)
		local c = ctx.Comps[n]
		if not c then
			c = Instance.new("Model")
			c.Name = n
			c:SetAttribute("Component", n)
			c.Parent = model
			ctx.Comps[n] = c
		end
		return c
	end
	function ctx.B(c: string, nm: string, role: string, centre: Vector3?, size: Vector3, o)
		o = o or {}
		local cf = O * (o.CF or (CFrame.new(centre :: Vector3) * (o.Rot or CFrame.identity)))
		ctx.Count += 1
		if ctx.Count % 12 == 0 then
			task.wait()
		end
		return Kit.Block(ctx.comp(c), { Name = nm, Role = role, Size = size, CFrame = cf, Bevel = o.Bevel, Axes = o.Axes, Cuts = o.Cuts, Holes = o.Holes, Smooth = o.Smooth })
	end
	function ctx.cyz(cy, cz, y1, z1, y2, z2, oy, oz)
		return Kit.CutYZ(y1 - cy, z1 - cz, y2 - cy, z2 - cz, oy - cy, oz - cz)
	end
	function ctx.cxz(cx, cz, x1, z1, x2, z2, ox, oz)
		return Kit.CutXZ(x1 - cx, z1 - cz, x2 - cx, z2 - cz, ox - cx, oz - cz)
	end
	function ctx.sides(fn)
		fn(-1, "L")
		fn(1, "R")
	end
	-- a block whose local Z runs from a to b (root space); w = local X, h = local Y
	function ctx.Rod(c: string, nm: string, role: string, a: Vector3, b: Vector3, w: number, h: number, o)
		o = o or {}
		local mid = (a + b) / 2
		local up = o.Up or V(0, 1, 0)
		local cf = CFrame.lookAt(mid, b, up)
		return ctx.B(c, nm, role, nil, V(w, h, (b - a).Magnitude + (o.Extra or 0)), { CF = cf, Bevel = o.Bevel, Axes = o.Axes, Cuts = o.Cuts, Holes = o.Holes })
	end
	return ctx
end

local function attach(root: BasePart, name: string, cf: CFrame)
	local a = root:FindFirstChild(name) or Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = root
	return a
end
Common.Attach = attach

-- welds: magazine parts to MagBody, everything else to Root (WeaponService re-welds its clone)
function Common.Finish(ctx, oldAsset: Model?, body: BasePart?, atts, attrs)
	local model, root, O = ctx.Model, ctx.Root, ctx.O
	-- carry over every Root attachment of the old asset (grips, muzzle, shoulder, mag seat, bolt…)
	if oldAsset and oldAsset.PrimaryPart then
		for _, a in oldAsset.PrimaryPart:GetChildren() do
			if a:IsA("Attachment") then
				attach(root, a.Name, a.CFrame)
			end
		end
	end
	if body then
		local mag = ctx.Comps.Magazine
		mag.PrimaryPart = body
		mag:SetAttribute("Real", true)
		local om = oldAsset and oldAsset:FindFirstChild("Magazine")
		local og = om and om.PrimaryPart and om.PrimaryPart:FindFirstChild("MagGrip")
		local g = Instance.new("Attachment")
		g.Name = "MagGrip"
		if og then
			local rel = oldAsset.PrimaryPart.CFrame:ToObjectSpace(og.WorldCFrame)
			g.CFrame = body.CFrame:ToObjectSpace(O * rel)
		else
			g.CFrame = CFrame.new(0, -0.03, -0.15)
		end
		g.Parent = body
	end
	for name, cf in atts do
		attach(root, name, cf)
	end
	local mag = ctx.Comps.Magazine
	local magBody = mag and mag.PrimaryPart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and d ~= magBody then
			local w = Instance.new("WeldConstraint")
			w.Part0 = if mag and magBody and d:IsDescendantOf(mag) then magBody else root
			w.Part1 = d
			w.Parent = d
		end
	end
	model:SetAttribute("Split", true)
	model:SetAttribute("Source", "ForgeKit")
	model:SetAttribute("ArtStyle", "Forge")
	model:SetAttribute("SkinSchema", "Roles")
	for k, v in attrs do
		model:SetAttribute(k, v)
	end
	return model
end

-- standard rifle pistol grip (Vanguard's), around the Tripo-era Handle (0, -0.49, 0.37)
function Common.RifleGrip(ctx, gripCF: CFrame?)
	local Kit, BV, B = ctx.Kit, ctx.BV, ctx.B
	gripCF = gripCF or CFrame.new(0, -0.482, 0.387) * CFrame.Angles(math.rad(-15), 0, 0)
	B("Grip", "Body", "Grip", nil, V(0.15, 0.58, 0.19), { CF = gripCF, Bevel = BV.L, Cuts = { Kit.CutYZ(-0.29, -0.04, -0.22, -0.095, -0.29, -0.095) } })
	B("Grip", "Backstrap", "Armor", nil, V(0.16, 0.46, 0.05), { CF = gripCF * CFrame.new(0, 0.0, 0.085), Bevel = BV.M })
	B("Grip", "Ridge1", "Frame", nil, V(0.155, 0.022, 0.03), { CF = gripCF * CFrame.new(0, -0.02, -0.095), Bevel = 0.006 })
	B("Grip", "Ridge2", "Frame", nil, V(0.155, 0.022, 0.03), { CF = gripCF * CFrame.new(0, -0.14, -0.095), Bevel = 0.006 })
	B("Grip", "Cap", "Frame", nil, V(0.17, 0.045, 0.23), { CF = gripCF * CFrame.new(0, -0.29, 0.005), Bevel = BV.M })
	return gripCF
end

-- trigger group under a rifle receiver
function Common.Trigger(ctx, z: number?)
	local BV, B = ctx.BV, ctx.B
	z = z or 0
	B("Receiver", "TriggerGuard", "Frame", V(0, -0.40, 0.075 + z), V(0.06, 0.035, 0.37), { Bevel = BV.S })
	B("Receiver", "Trigger", "Metal", V(0, -0.325, 0.11 + z), V(0.028, 0.09, 0.03), { Bevel = 0.006, Rot = CFrame.Angles(math.rad(-18), 0, 0) })
end

return Common
