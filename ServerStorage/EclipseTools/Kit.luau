--[[
	ECLIPSE — greybox Kit (edit-time helpers shared by the area builders)
	Parts are anchored SmoothPlastic in a fixed greybox palette; terrain is carved with FillBlock.
]]
local HF = require(script.Parent.Heightfield)
local Kit = {}
local V, CF = Vector3.new, CFrame.new
local abs = math.abs

local C3 = Color3.fromRGB
Kit.PAL = {
	Floor = C3(150, 153, 160),
	Wall = C3(112, 117, 128),
	Ancient = C3(82, 90, 108),
	Cover = C3(70, 74, 84),
	Metal = C3(96, 100, 110),
	Energy = C3(80, 200, 255),
	Glass = C3(150, 195, 230),
	Blue = C3(60, 120, 230),
	Red = C3(220, 72, 60),
	Light = C3(225, 232, 245),
	Water = C3(70, 140, 200),
}
local PAL = Kit.PAL
Kit.count = 0

function Kit.ground(x, z)
	return (HF.H(x, z))
end

function Kit.folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end
function Kit.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.P(parent, name, size, cf, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or PAL.Wall
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.Parent = parent
	Kit.count += 1
	if Kit.count % 150 == 0 then
		task.wait()
	end
	return p
end
local P = Kit.P

-- axis-aligned box from two corners
function Kit.box(parent, name, x0, y0, z0, x1, y1, z1, color, props)
	local size = V(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
	return P(parent, name, size, CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, props)
end

function Kit.carveBox(x0, y0, z0, x1, y1, z1)
	workspace.Terrain:FillBlock(CF((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), V(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), Enum.Material.Air)
end
function Kit.carve(cf, size)
	workspace.Terrain:FillBlock(cf, size, Enum.Material.Air)
end

-- walkable slab whose top surface runs from a to b
function Kit.ramp(parent, name, a, b, width, color, thick)
	thick = thick or 1.2
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b) * CF(0, -thick / 2, 0)
	return P(parent, name, V(width, thick, len + 0.6), cf, color or PAL.Floor)
end

-- tunnel through terrain: carve, floor slab per segment, ceiling light every ~28 studs
function Kit.tunnel(parent, name, pts, w, h, color)
	local f = Kit.model(parent, name)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local look = CFrame.lookAt(mid, b)
		Kit.carve(look * CF(0, h / 2, 0), V(w, h, len + w * 0.6))
		Kit.ramp(f, "Floor", a, b, w - 0.5, color or PAL.Floor)
		local n = math.max(1, math.floor(len / 28))
		for k = 1, n do
			local p = a:Lerp(b, (k - 0.5) / n)
			P(f, "Light", V(w * 0.5, 0.3, 1.2), CFrame.lookAt(p, p + (b - a)) * CF(0, h - 1.2, 0), PAL.Light, { Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		end
	end
	for _, p in pts do
		Kit.carve(CF(p) * CF(0, h / 2, 0), V(w + 1, h, w + 1))
	end
	return f
end

-- straight walls with rectangular openings: openings = { {u0, u1, v0, v1}, ... } in wall-local
-- coordinates (u along the wall from its start, v up from its base)
function Kit.wall(parent, name, a, b, y0, y1, thick, openings, color)
	local dir = (b - a)
	local len = dir.Magnitude
	local cfBase = CFrame.lookAt(a, b) -- -Z along the wall
	local cuts = {}
	for _, o in openings or {} do
		table.insert(cuts, o)
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local function seg(u0, u1, v0, v1)
		if u1 - u0 < 0.05 or v1 - v0 < 0.05 then
			return
		end
		local cf = cfBase * CF(0, y0 - a.Y + (v0 + v1) / 2, -(u0 + u1) / 2)
		P(parent, name, V(thick, v1 - v0, u1 - u0), cf, color)
	end
	local h = y1 - y0
	local u = 0
	for _, o in cuts do
		seg(u, o[1], 0, h)
		seg(o[1], o[2], 0, o[3]) -- below the opening (sill)
		seg(o[1], o[2], o[4], h) -- above (header)
		u = o[2]
	end
	seg(u, len, 0, h)
end

-- floating callout for greybox review screenshots (Gameplay/Callouts, delete for release)
function Kit.callout(parent, pos, title, sub)
	local a = P(parent, "Callout_" .. title, V(1, 1, 1), CF(pos), PAL.Light, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(280, 60)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 140
	bb.Parent = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0.6, 0)
	t.BackgroundTransparency = 1
	t.Text = title
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
	t.TextScaled = true
	t.Parent = bb
	local s = t:Clone()
	s.Position = UDim2.new(0, 0, 0.62, 0)
	s.Size = UDim2.new(1, 0, 0.38, 0)
	s.Text = sub or ""
	s.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
	s.Parent = bb
	return a
end

-- gravity lift: launch pad + trigger volume (handled by Map_Eclipse/Systems)
function Kit.lift(liftFolder, visParent, name, base, height, push)
	P(visParent, name .. "_Pad", V(8, 0.6, 8), CF(base + V(0, 0.3, 0)), PAL.Energy, { Material = Enum.Material.Neon, CastShadow = false })
	P(visParent, name .. "_Ring", V(10, 0.4, 10), CF(base + V(0, 0.2, 0)), PAL.Metal)
	local vol = P(liftFolder, name, V(7, 5, 7), CF(base + V(0, 3, 0)), PAL.Energy, { Transparency = 1, CanCollide = false, CanQuery = false })
	vol:SetAttribute("LiftHeight", height)
	vol:SetAttribute("LiftPush", push or Vector3.zero)
	return vol
end

function Kit.spawnPad(parent, pos, team)
	local s = Instance.new("SpawnLocation")
	s.Name = team .. "Spawn"
	s.Anchored = true
	s.Size = V(6, 0.4, 6)
	s.Position = pos + V(0, 0.2, 0)
	s.Material = Enum.Material.Metal
	s.Color = if team == "Blue" then C3(30, 60, 120) else C3(120, 30, 30)
	s.TeamColor = BrickColor.new(if team == "Blue" then "Really blue" else "Really red")
	s.Neutral = false
	s.AllowTeamChangeOnTouch = false
	s.Duration = 3
	s.TopSurface = Enum.SurfaceType.Smooth
	s.Parent = parent
	Kit.count += 1
	return s
end

return Kit
