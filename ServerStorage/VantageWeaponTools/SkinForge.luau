--[[ VANTAGE — SkinForge (Studio concept tool, 2026-11-14)
  Builds skin CONCEPT previews on CLONES of Forge weapons inside Workspace._SkinShowcase.
  Never edits Assets/*, never edits gameplay. Local coordinates are relative to the gun pivot:
  X lateral, Y up, Z toward the stock (muzzle is -Z).
]]
local F = {}
F.Kit = require(game.ServerStorage.VantageWeaponTools.ForgeKit:Clone())
F.ORIGIN = CFrame.new(7000, 320, 7000)

function F.rgb(r,g,b) return Color3.fromRGB(r,g,b) end

function F.Stage()
	local old = workspace:FindFirstChild("_SkinShowcase")
	if old then old:Destroy() end
	local st = Instance.new("Folder"); st.Name = "_SkinShowcase"
	local O = F.ORIGIN
	local function wall(name, size, off, col)
		local p = Instance.new("Part"); p.Name=name; p.Anchored=true; p.Size=size; p.CFrame=O*CFrame.new(off)
		p.Color=col or F.rgb(9,10,15); p.Material=Enum.Material.SmoothPlastic; p.CastShadow=true; p.Parent=st; return p
	end
	wall("Floor", Vector3.new(40,1,60), Vector3.new(0,-4,0), F.rgb(7,8,12))
	wall("Ceil", Vector3.new(40,1,60), Vector3.new(0,9,0))
	wall("Back", Vector3.new(1,14,60), Vector3.new(5,2.5,0))
	wall("Front", Vector3.new(1,14,60), Vector3.new(-14,2.5,0))
	wall("SideA", Vector3.new(40,14,1), Vector3.new(0,2.5,-30))
	wall("SideB", Vector3.new(40,14,1), Vector3.new(0,2.5,30))
	st.Parent = workspace
	return st
end

-- concentric-circle glow painted on the back wall behind a display slot
function F.Backdrop(st, slotZ, slotY, color, label, sub)
	local back = st.Back
	local holder = Instance.new("Part"); holder.Name="Plate_"..label; holder.Anchored=true; holder.CanCollide=false
	holder.Size = Vector3.new(0.05, 7, 9); holder.Transparency=1
	holder.CFrame = F.ORIGIN * CFrame.new(4.45, slotY, slotZ); holder.Parent = st
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Left; sg.LightInfluence = 0; sg.Brightness = 1.4
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 60; sg.Parent = holder
	for i = 1, 16 do
		local f = Instance.new("Frame"); local s = 1.15 - i*0.062
		f.AnchorPoint = Vector2.new(.5,.5); f.Position = UDim2.fromScale(.5,.47)
		f.Size = UDim2.fromScale(s*0.95, s*1.22); f.BackgroundColor3 = color; f.BackgroundTransparency = 0.935; f.BorderSizePixel=0
		local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(.5,0); fc.Parent = f; f.Parent = sg
	end
	if label then
		local t = Instance.new("TextLabel"); t.BackgroundTransparency=1; t.Size=UDim2.fromScale(.9,.07); t.Position=UDim2.fromScale(.05,.80)
		t.Font=Enum.Font.GothamBlack; t.TextScaled=true; t.TextColor3=Color3.new(1,1,1); t.Text=label; t.Parent=sg
		local s2 = Instance.new("TextLabel"); s2.BackgroundTransparency=1; s2.Size=UDim2.fromScale(.9,.04); s2.Position=UDim2.fromScale(.05,.875)
		s2.Font=Enum.Font.GothamBold; s2.TextScaled=true; s2.TextColor3=color; s2.Text=sub or ""; s2.Parent=sg
		local bar = Instance.new("Frame"); bar.BorderSizePixel=0; bar.BackgroundColor3=color; bar.Size=UDim2.fromScale(.18,.006); bar.Position=UDim2.fromScale(.41,.785); bar.Parent=sg
	end
	return holder
end

function F.Light(st, kind, pos, color, brightness, range, face, angle)
	local a = Instance.new("Part"); a.Name="Light"; a.Anchored=true; a.CanCollide=false; a.Transparency=1; a.Size=Vector3.new(.2,.2,.2)
	a.CFrame = F.ORIGIN * CFrame.new(pos); a.Parent = st
	local l = Instance.new(kind); l.Color=color; l.Brightness=brightness; l.Range=range; l.Shadows=true
	if kind=="SpotLight" then l.Face=face or Enum.NormalId.Front; l.Angle=angle or 70 end
	l.Parent = a; return l
end

function F.CloneGun(st, id, name, localCF)
	local g = game.ReplicatedStorage.Vantage.Weapons.Assets[id]:Clone()
	g.Name = name
	g:PivotTo(F.ORIGIN * localCF)
	g:SetAttribute("SkinConcept", name)
	g.Parent = st
	return g
end

function F.Comp(gun, c) return gun:FindFirstChild(c, true) end
function F.Find(gun, comp, part) local m = gun:FindFirstChild(comp, true); return m and m:FindFirstChild(part) end

-- style = {Color, Material, Variant, Reflectance, Transparency}
function F.Apply(p, s)
	if s.Color then p.Color = s.Color end
	if s.Material then p.Material = s.Material end
	p.MaterialVariant = s.Variant or ""
	if s.Reflectance then p.Reflectance = s.Reflectance end
	if s.Transparency then p.Transparency = s.Transparency end
	if p:IsA("PartOperation") then p.UsePartColor = true end
end
function F.Paint(gun, roles)
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then local r = d:GetAttribute("Role"); if r and roles[r] then F.Apply(d, roles[r]) end end
	end
end
function F.PaintParts(gun, list, s)
	for _, pair in list do local p = F.Find(gun, pair[1], pair[2]); if p then F.Apply(p, s) end end
end

-- chamfered block in gun-local space
function F.Block(gun, compName, spec, style)
	local pv = gun:GetPivot()
	local parent = F.Comp(gun, compName) or gun
	local s = table.clone(spec); s.CFrame = pv * spec.CFrame
	local p = F.Kit.Block(parent, s)
	p:SetAttribute("SkinGeo", true)
	if style then F.Apply(p, style) end
	return p
end
-- plain part (glow lines, gems)
function F.Part(gun, compName, name, size, lcf, style, shape)
	local p = Instance.new("Part"); p.Name=name; p.Size=size; p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.Massless=true
	if shape then p.Shape = shape end
	p.CFrame = gun:GetPivot() * lcf; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
	F.Apply(p, style); p.CastShadow = style.Material ~= Enum.Material.Neon
	p:SetAttribute("SkinGeo", true)
	p.Parent = F.Comp(gun, compName) or gun
	return p
end
-- ring (cylinder minus cylinder), axis along local X of lcf
function F.Ring(gun, compName, name, outerD, innerD, thick, lcf, style)
	local pv = gun:GetPivot() * lcf
	local a = Instance.new("Part"); a.Shape=Enum.PartType.Cylinder; a.Size=Vector3.new(thick, outerD, outerD); a.CFrame=pv; a.Anchored=true
	local b = Instance.new("Part"); b.Shape=Enum.PartType.Cylinder; b.Size=Vector3.new(thick+0.2, innerD, innerD); b.CFrame=pv; b.Anchored=true
	local ok, res = pcall(function() return game:GetService("GeometryService"):SubtractAsync(a, {b}, {SplitApart=false, RenderFidelity=Enum.RenderFidelity.Precise}) end)
	a:Destroy(); b:Destroy()
	local p = res[1]; p.Name=name; p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.Massless=true; p.UsePartColor=true
	F.Apply(p, style); p.CastShadow = style.Material ~= Enum.Material.Neon
	p:SetAttribute("SkinGeo", true)
	p.Parent = F.Comp(gun, compName) or gun
	return p
end

function F.Emitter(part, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in props do e[k] = v end
	e.Parent = part
	return e
end
function F.Attach(gun, part, lpos)
	local a = Instance.new("Attachment"); a.Parent = part
	a.WorldPosition = (gun:GetPivot() * CFrame.new(lpos)).Position
	return a
end

return F
