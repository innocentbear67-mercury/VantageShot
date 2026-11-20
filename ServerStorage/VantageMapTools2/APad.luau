-- APad: Hypershot-style jump pad (dark disc + glowing ring + light beam + floating double chevron + sparkles)
local P = {}
local V = Vector3.new
local CS = game:GetService("CollectionService")
local function part(parent, name, size, cf, col, mat, t, collide)
	local p = Instance.new("Part") p.Name = name p.Anchored = true p.Size = size p.CFrame = cf
	p.Color = col p.Material = mat or Enum.Material.SmoothPlastic p.Transparency = t or 0
	p.CanCollide = collide or false p.CanQuery = collide or false p.CanTouch = false p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent return p
end
local function cyl(parent, name, pos, h, d, col, mat, t, collide)
	local p = part(parent, name, V(h, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), col, mat, t, collide)
	p.Shape = Enum.PartType.Cylinder return p
end
local function chevron(frame, y, w, col, dark)
	-- "^" : two bars rotated +-40 deg meeting at the top centre, inside an animatable "Chev" holder
	local holder = Instance.new("Frame") holder.Name = "Chev" holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1) holder.Position = UDim2.fromScale(0.5, y) holder.BackgroundTransparency = 1
	holder.Parent = frame
	for _, s in ipairs({ -1, 1 }) do
		local bar = Instance.new("Frame") bar.Name = "Arm" bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromScale(w, 0.17) bar.Position = UDim2.fromScale(0.5 + s * w * 0.36, 0.5)
		bar.Rotation = s * 40 bar.BackgroundColor3 = col bar.BorderSizePixel = 0
		local st = Instance.new("UIStroke") st.Color = dark st.Thickness = 3 st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border st.Parent = bar
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0.3, 0) c.Parent = bar
		bar.Parent = holder
	end
end
function P.make(parent, floorPos, target, accent, name)
	local m = Instance.new("Model") m.Name = name or "JumpPad" m.Parent = parent
	local dark = Color3.fromRGB(28, 30, 36)
	cyl(m, "PadRing", floorPos + V(0, 0.2, 0), 0.4, 10, accent, Enum.Material.Neon, 0, false)
	cyl(m, "PadBase", floorPos + V(0, 0.3, 0), 0.6, 8.6, dark, Enum.Material.SmoothPlastic, 0, true)
	cyl(m, "PadCore", floorPos + V(0, 0.62, 0), 0.06, 5, accent, Enum.Material.Neon, 0.35, false)
	local beam = cyl(m, "PadBeam", floorPos + V(0, 5, 0), 9.2, 6.4, accent, Enum.Material.Neon, 0.86, false)
	cyl(m, "PadBeamCore", floorPos + V(0, 4, 0), 7.2, 3, accent, Enum.Material.Neon, 0.8, false)
	local trig = part(m, "JumpPad", V(9, 0.6, 9), CFrame.new(floorPos + V(0, 0.3, 0)), accent, Enum.Material.SmoothPlastic, 1, false)
	trig:SetAttribute("PadTarget", target) trig:SetAttribute("NoGrapple", true)
	CS:AddTag(trig, "JumpPad")
	local l = Instance.new("PointLight") l.Color = accent l.Range = 16 l.Brightness = 2.2 l.Parent = beam
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds" pe.Color = ColorSequence.new(accent)
	pe.LightEmission = 1 pe.Rate = 14 pe.Lifetime = NumberRange.new(0.9, 1.5) pe.Speed = NumberRange.new(4, 8)
	pe.SpreadAngle = Vector2.new(12, 12) pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	pe.EmissionDirection = Enum.NormalId.Top
	local emit = part(m, "PadEmitter", V(5, 0.1, 5), CFrame.new(floorPos + V(0, 0.7, 0)), accent, Enum.Material.SmoothPlastic, 1, false)
	pe.Parent = emit
	-- floating double chevron (always faces the camera)
	local anchor = part(m, "PadIcon", V(0.2, 0.2, 0.2), CFrame.new(floorPos + V(0, 5.6, 0)), accent, Enum.Material.SmoothPlastic, 1, false)
	local bb = Instance.new("BillboardGui") bb.Size = UDim2.fromScale(4.2, 4.8) bb.LightInfluence = 0 bb.Brightness = 1.6
	bb.MaxDistance = 260 bb.Parent = anchor
	local f = Instance.new("Frame") f.Size = UDim2.fromScale(1, 1) f.BackgroundTransparency = 1 f.Parent = bb
	chevron(f, 0.36, 0.62, accent, dark)
	chevron(f, 0.7, 0.62, accent, dark)
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d:SetAttribute("NoGrapple", true) end end
	return m, trig
end
-- simulate JumpPadClient's arc; returns ok, landing info
function P.check(map, start, target)
	local g = workspace.Gravity
	local rise = math.max(target.Y - start.Y, 0)
	local apex = rise + 10
	local vy = math.sqrt(2 * g * apex)
	local t = vy / g + math.sqrt(2 * (apex - rise) / g)
	local flat = V(target.X - start.X, 0, target.Z - start.Z)
	local v0 = flat / t + V(0, vy, 0)
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Include rp.FilterDescendantsInstances = { map }
	local prev = start + V(0, 3, 0)
	local hit = nil
	for i = 1, 60 do
		local tt = t * i / 60
		local pos = start + V(0, 3, 0) + v0 * tt + V(0, -0.5 * g * tt * tt, 0)
		for _, off in ipairs({ V(0, 0, 0), V(0, 2.4, 0), V(0, -2.4, 0) }) do
			local r = workspace:Raycast(prev + off, (pos - prev), rp)
			if r and r.Instance.CanCollide and r.Instance.Name ~= "JumpPad" and i < 57 then hit = r.Instance:GetFullName() .. " @" .. tostring(r.Position) break end
		end
		if hit then break end
		prev = pos
	end
	local land = workspace:Raycast(target + V(0, 6, 0), V(0, -10, 0), rp)
	return hit == nil and land ~= nil and math.abs(land.Position.Y - target.Y) < 2.5, hit, land and land.Instance.Name
end
return P
