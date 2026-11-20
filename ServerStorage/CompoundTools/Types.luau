local T = {}
local WHITE = Color3.fromRGB(204, 203, 198)
local CHAR = Color3.fromRGB(60, 61, 63)
local STEEL = Color3.fromRGB(110, 114, 120)
local TREAD = Color3.fromRGB(150, 152, 154)
local GLASS = Color3.fromRGB(34, 40, 48)
local YEL = Color3.fromRGB(222, 178, 46)
local hiSign
local function wedge(K, par, name, size, cf, col, mat)
  local w = Instance.new("WedgePart"); w.Name = name; w.Anchored = true; w.Size = size; w.CFrame = cf
  w.Color = col or WHITE; w.Material = mat or Enum.Material.Plaster
  w.TopSurface = Enum.SurfaceType.Smooth; w.BottomSurface = Enum.SurfaceType.Smooth
  w.Parent = par; return w
end
local function findHi(K)
  if hiSign then return hiSign end
  local w = wedge(K, workspace, "_probe", Vector3.new(4, 10, 10), CFrame.new(0, 3000, 0))
  local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include; rp.FilterDescendantsInstances = {w}
  local a = workspace:Raycast(Vector3.new(0, 3100, 4), Vector3.new(0, -200, 0), rp)
  local b = workspace:Raycast(Vector3.new(0, 3100, -4), Vector3.new(0, -200, 0), rp)
  hiSign = ((a and a.Position.Y or 0) > (b and b.Position.Y or 0)) and 1 or -1
  w:Destroy(); return hiSign
end
local function deco(p) if p then p.CanCollide = false; p.CanQuery = false; p.CastShadow = false end return p end
local function metal(p, c) if p then p.Material = Enum.Material.Metal; p.MaterialVariant = ""; p.Color = c or CHAR end return p end
-- door centres the same way BuildBlock places them
local function doorCentres(b)
  local E = 229
  local d = {N = {}, S = {}, W = {}, E = {}}
  local function f(side, a1, a2, edge)
    if edge then return end
    local L = a2 - a1
    if L > 50 then d[side] = {a1 + L / 3, a1 + 2 * L / 3} else d[side] = {(a1 + a2) / 2} end
  end
  f("N", b.x1, b.x2, b.z1 <= -E); f("S", b.x1, b.x2, b.z2 >= E); f("W", b.z1, b.z2, b.x1 <= -E); f("E", b.z1, b.z2, b.x2 >= E)
  return d
end
local function nearDoor(list, u, r) for _, c in ipairs(list or {}) do if math.abs(u - c) < r then return true end end return false end
-- exterior stair from ground up to a roof (height h) along the N or S face
local function roofStair(K, mdl, b, h)
  local useS = b.z1 <= -229
  local zs = useS and (b.z2 + 3.5) or (b.z1 - 3.5)
  local run = h * 1.6
  local xa, xb = b.x1 + 3, math.min(b.x1 + 3 + run, b.x2 - 8)
  local st = K.ramp(mdl, "RoofStair", Vector3.new(xa, 0.3, zs), Vector3.new(xb, h + 1, zs), 4, TREAD); st.Material = Enum.Material.DiamondPlate; st.MaterialVariant = ""
  local side = useS and 1 or -1
  local A = Vector3.new(xa, 3.7, zs + side * 2.1 + K.CZ); local B2 = Vector3.new(xb, h + 4.4, zs + side * 2.1 + K.CZ)
  deco(K.P(mdl, "RailTop", Vector3.new(0.28, 0.28, (B2 - A).Magnitude), CFrame.lookAt((A + B2) / 2, B2), YEL, Enum.Material.Metal))
  K.B(mdl, "Landing", xb - 1, h + 0.2, math.min(zs - 2, zs + 2), xb + 6, h + 1, math.max(zs - 2, zs + 2), TREAD, Enum.Material.DiamondPlate)
  for _, p in ipairs(mdl:GetDescendants()) do
    if p:IsA("BasePart") and p.Name == "RoofBand" and p.Size.X > 10 and math.abs(p.Position.Y - (h + 0.25)) < 4 then
      local lz = p.Position.Z - K.CZ
      if (useS and lz > b.z2 - 2) or (not useS and lz < b.z1 + 2) then
        local a1, a2 = p.Position.X - p.Size.X / 2, p.Position.X + p.Size.X / 2
        for _, seg in ipairs({{a1, xb - 2}, {xb + 7, a2}}) do
          if seg[2] - seg[1] > 0.5 then local q = p:Clone(); q.Size = Vector3.new(seg[2] - seg[1], p.Size.Y, p.Size.Z); q.Position = Vector3.new((seg[1] + seg[2]) / 2, p.Position.Y, p.Position.Z); q.Parent = p.Parent end
        end
        p:Destroy()
      end
    end
  end
end
local function sandbags(K, par, cf, n, rng)
  for row = 0, 1 do for i = 0, n - 1 - row do
    local s = K.P(par, "Sandbag", Vector3.new(2.9, 1.1, 1.7), cf * CFrame.new((i - (n - 1) / 2) * 3 + row * 1.5, 0.55 + row * 1.05, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-5, 5)), 0), Color3.fromRGB(150, 142, 116), Enum.Material.Fabric)
    s.CastShadow = false
  end end
end
local function vent(K, par, x, y, z)
  local v = K.P(par, "VentStack", Vector3.new(3.6, 1.4, 1.4), K.W(x, y + 1.8, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(176, 178, 176), Enum.Material.Metal); v.Shape = Enum.PartType.Cylinder; v.CastShadow = false
  deco(K.P(par, "VentCap", Vector3.new(2, 0.4, 2), K.W(x, y + 3.8, z), CHAR, Enum.Material.Metal))
end
local function hvac(K, par, x, y, z)
  K.P(par, "HVAC", Vector3.new(8, 4, 5), K.W(x, y + 2.6, z), Color3.fromRGB(180, 182, 180), Enum.Material.Metal)
  K.P(par, "HVACBase", Vector3.new(8.4, 0.6, 5.4), K.W(x, y + 0.3, z), CHAR, Enum.Material.Metal)
  for _, sx in ipairs({-2, 2}) do local f = K.P(par, "Fan", Vector3.new(0.3, 3, 3), K.W(x + sx, y + 4.75, z) * CFrame.Angles(0, 0, math.rad(90)), CHAR, Enum.Material.Metal); f.Shape = Enum.PartType.Cylinder; deco(f) end
end

-- 1 BUNKER (outpost): low, sloped corner berms, slit band, roof nest
function T.bunker(H, K, BB, par, b, ups, rng)
  local h = 12
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = h}, nil)
  local hs = findHi(K)
  for _, c in ipairs({{b.x1, b.z1, -1, -1}, {b.x2, b.z1, 1, -1}, {b.x1, b.z2, -1, 1}, {b.x2, b.z2, 1, 1}}) do
    -- berm on the X face (sloping outward in x) and on the Z face
    local dx = Vector3.new(c[3], 0, 0); local dz = Vector3.new(0, 0, c[4])
    local px = K.W(c[1] + c[3] * 2, 4, c[2] - c[4] * 6)
    wedge(K, mdl, "Berm", Vector3.new(10, 8, 4), CFrame.lookAt(px.Position, px.Position + dx * hs), WHITE)
    local pz = K.W(c[1] - c[3] * 6, 4, c[2] + c[4] * 2)
    wedge(K, mdl, "Berm", Vector3.new(10, 8, 4), CFrame.lookAt(pz.Position, pz.Position + dz * hs), WHITE)
  end
  -- dark slit band
  for _, s in ipairs({{b.x1, b.z1 - 0.15, b.x2, b.z1 + 0.1}, {b.x1, b.z2 - 0.1, b.x2, b.z2 + 0.15}}) do
    for x = s[1] + 4, s[3] - 4, 7 do deco(K.B(mdl, "Slit", x, 8, s[2], x + 3, 9.2, s[4], GLASS, Enum.Material.SmoothPlastic)) end
  end
  roofStair(K, mdl, b, h)
  sandbags(K, mdl, K.W((b.x1 + b.x2) / 2, h + 1, (b.z1 + b.z2) / 2), 6, rng)
  return mdl
end
-- 2 LAB (research complex): base + set-back upper storey with ribbon glazing
function T.lab(H, K, BB, par, b, ups, rng)
  local h = 14
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = h}, nil)
  roofStair(K, mdl, b, h)
  local useS = b.z1 <= -229
  local ux1, uz1, ux2, uz2 = b.x1 + 10, b.z1 + 10, b.x2 - 6, b.z2 - 6
  if useS then uz1, uz2 = b.z1 + 6, b.z2 - 10 end
  local cx, cz = (ux1 + ux2) / 2, (uz1 + uz2) / 2
  local up = H.build(mdl, "Upper", ux1, uz1, ux2, uz2, 28, {{"N", cx, 8, 9}, {"S", cx, 8, 9}, {"W", cz, 8, 9}, {"E", cz, 8, 9}})
  up:PivotTo(up:GetPivot() + Vector3.new(0, h + 0.6, 0))
  local y0 = h + 0.6
  for _, s in ipairs({{ux1, uz1 - 0.2, ux2, uz1 + 0.05}, {ux1, uz2 - 0.05, ux2, uz2 + 0.2}}) do
    for x = s[1] + 2, s[3] - 2, 4 do
      if math.abs(x + 1.5 - cx) > 6 then deco(K.B(up, "Ribbon", x, y0 + 5, s[2], x + 3, y0 + 8.5, s[4], GLASS, Enum.Material.Glass)) end
    end
  end
  hvac(K, mdl, cx, y0 + 28, cz); vent(K, mdl, ux1 + 4, y0 + 28, uz1 + 4)
  return mdl
end
-- 3 WAREHOUSE (industrial): tall, pitched roof
function T.warehouse(H, K, BB, par, b, ups, rng)
  ups = nil
  local h = 38
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = h}, ups)
  local hs = findHi(K)
  local W, L = b.z2 - b.z1, b.x2 - b.x1
  local alongX = L >= W
  local rh = 9
  local cx, cz = (b.x1 + b.x2) / 2, (b.z1 + b.z2) / 2
  local y = h + 3.5 + rh / 2
  if alongX then
    for _, s in ipairs({-1, 1}) do
      local pos = K.W(cx, y, cz + s * W / 4).Position
      local d = Vector3.new(0, 0, -s)
      local w = wedge(K, mdl, "RoofSlope", Vector3.new(L + 1, rh, W / 2 + 0.5), CFrame.lookAt(pos, pos - d * hs), Color3.fromRGB(76, 78, 82), Enum.Material.Metal)
      w.MaterialVariant = "VS_CorrugatedSteel"
    end
  else
    for _, s in ipairs({-1, 1}) do
      local pos = K.W(cx + s * L / 4, y, cz).Position
      local d = Vector3.new(-s, 0, 0)
      local w = wedge(K, mdl, "RoofSlope", Vector3.new(W + 1, rh, L / 2 + 0.5), CFrame.lookAt(pos, pos - d * hs), Color3.fromRGB(76, 78, 82), Enum.Material.Metal)
      w.MaterialVariant = "VS_CorrugatedSteel"
    end
  end
  return mdl
end
-- 4 FACTORY (industrial): sawtooth north-light roof
function T.factory(H, K, BB, par, b, ups, rng)
  ups = nil
  local h = 34
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = h}, ups)
  local hs = findHi(K)
  local n = 4
  local W = b.x2 - b.x1; local L = b.z2 - b.z1
  local seg = L / n
  for i = 0, n - 1 do
    local z = b.z1 + seg * (i + 0.5)
    local pos = K.W((b.x1 + b.x2) / 2, h + 3.5 + 3.5, z).Position
    wedge(K, mdl, "Sawtooth", Vector3.new(W + 0.5, 7, seg), CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1) * hs), Color3.fromRGB(196, 196, 192), Enum.Material.Metal)
    -- glazing on the vertical face
    deco(K.B(mdl, "Glazing", b.x1 + 1, h + 4, b.z1 + seg * (i + 1) + 0.05, b.x2 - 1, h + 9.6, b.z1 + seg * (i + 1) + 0.25, GLASS, Enum.Material.Glass))
  end
  return mdl
end
-- 5 TRANSIT (raised station): hall lifted on columns, covered ground passage, stair up
function T.transit(H, K, BB, par, b, ups, rng)
  local lift = 12
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = 28}, nil)
  mdl:PivotTo(mdl:GetPivot() + Vector3.new(0, lift, 0))
  -- underside + columns
  metal(K.B(mdl, "Underside", b.x1, lift - 1.4, b.z1, b.x2, lift, b.z2), STEEL)
  for x = b.x1 + 3, b.x2 - 2, 14 do for z = b.z1 + 3, b.z2 - 2, 14 do
    local c = K.B(mdl, "Column", x - 1.2, 0, z - 1.2, x + 1.2, lift - 1.4, z + 1.2, WHITE, Enum.Material.Plaster)
    deco(K.B(mdl, "ColumnBand", x - 1.3, 0, z - 1.3, x + 1.3, 3.5, z + 1.3, YEL, Enum.Material.SmoothPlastic))
  end end
  -- stair to the first door on the alley side
  local d = doorCentres(b)
  local useS = b.z1 <= -229
  local dx = (useS and d.S[1]) or d.N[1] or (b.x1 + b.x2) / 2
  local face = useS and b.z2 or b.z1
  local zs = useS and (face + 3) or (face - 3)
  local st = K.ramp(mdl, "Stair", Vector3.new(dx - 26, 0.3, zs), Vector3.new(dx - 6, lift + 0.4, zs), 4, TREAD); st.Material = Enum.Material.DiamondPlate; st.MaterialVariant = ""
  K.B(mdl, "Landing", dx - 7, lift - 0.4, math.min(face, zs - 2), dx + 5, lift + 0.4, math.max(face, zs + 2), TREAD, Enum.Material.DiamondPlate)
  hvac(K, mdl, (b.x1 + b.x2) / 2, lift + 29, (b.z1 + b.z2) / 2)
  return mdl
end
-- 6 RELAY (comms tower + annex)
function T.relay(H, K, BB, par, b, ups, rng)
  local tw = 18
  local annex = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2 - tw, z2 = b.z2, h = 30}, nil)
  local tz1 = b.z1 + 6; local tz2 = tz1 + tw
  local tower = BB(H, K, annex, {name = "RelayTower", x1 = b.x2 - tw, z1 = tz1, x2 = b.x2, z2 = tz2, h = 64}, nil)
  local cx, cz = b.x2 - tw / 2, (tz1 + tz2) / 2
  -- lattice antenna
  for _, o in ipairs({{-3, -3}, {3, -3}, {-3, 3}, {3, 3}}) do
    local p = K.B(annex, "Lattice", cx + o[1] - 0.3, 67.5, cz + o[2] - 0.3, cx + o[1] + 0.3, 90, cz + o[2] + 0.3, Color3.fromRGB(170, 172, 172), Enum.Material.Metal); p.CastShadow = false
  end
  for y = 72, 88, 4 do deco(K.B(annex, "LatticeRing", cx - 3.3, y, cz - 3.3, cx + 3.3, y + 0.4, cz + 3.3, Color3.fromRGB(170, 172, 172), Enum.Material.Metal)) end
  local bcn = K.P(annex, "Beacon", Vector3.new(1, 1, 1), K.W(cx, 90.8, cz), Color3.fromRGB(255, 50, 40), Enum.Material.Neon); deco(bcn)
  local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(255, 50, 40); pl.Range = 10; pl.Shadows = false; pl.Parent = bcn
  local dish = K.P(annex, "Dish", Vector3.new(0.6, 8, 8), K.W(b.x1 + 12, 35.5, (b.z1 + b.z2) / 2) * CFrame.Angles(0, math.rad(40), math.rad(25)), Color3.fromRGB(226, 226, 222), Enum.Material.SmoothPlastic); dish.Shape = Enum.PartType.Cylinder
  K.B(annex, "DishPost", b.x1 + 11.5, 31, (b.z1 + b.z2) / 2 - 0.5, b.x1 + 12.5, 35.5, (b.z1 + b.z2) / 2 + 0.5, CHAR, Enum.Material.Metal)
  return annex
end
-- 7 PLANT (industrial): steel exoskeleton, rooftop tanks, high pipe run
function T.plant(H, K, BB, par, b, ups, rng)
  ups = nil
  local h = 42
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = h}, ups)
  local d = doorCentres(b)
  local o = 2.2
  local function col(x, z) local p = metal(K.B(mdl, "Exo", x - 0.7, 0, z - 0.7, x + 0.7, h + 3, z + 0.7), STEEL); p.CastShadow = false end
  for x = b.x1 + 2, b.x2 - 2, 12 do
    if not nearDoor(d.N, x, 7) and b.z1 > -229 then col(x, b.z1 - o) end
    if not nearDoor(d.S, x, 7) and b.z2 < 229 then col(x, b.z2 + o) end
  end
  for _, y in ipairs({13, h + 2}) do
    if b.z1 > -229 then deco(metal(K.B(mdl, "ExoBeam", b.x1, y, b.z1 - o - 0.5, b.x2, y + 0.9, b.z1 - o + 0.5), STEEL)) end
    if b.z2 < 229 then deco(metal(K.B(mdl, "ExoBeam", b.x1, y, b.z2 + o - 0.5, b.x2, y + 0.9, b.z2 + o + 0.5), STEEL)) end
  end
  if b.z1 > -229 then
    local p = K.P(mdl, "Pipe", Vector3.new(b.x2 - b.x1, 2, 2), K.W((b.x1 + b.x2) / 2, 17, b.z1 - 1.2) , Color3.fromRGB(150, 152, 150), Enum.Material.Metal); p.Shape = Enum.PartType.Cylinder; deco(p)
  end
  for i, xo in ipairs({0.3, 0.7}) do
    local tx = b.x1 + (b.x2 - b.x1) * xo
    local t = K.P(mdl, "Tank", Vector3.new(12, 9, 9), K.W(tx, h + 7.5, (b.z1 + b.z2) / 2) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 198, 196), Enum.Material.Metal); t.Shape = Enum.PartType.Cylinder
    metal(K.B(mdl, "TankBase", tx - 5, h + 1, (b.z1 + b.z2) / 2 - 5, tx + 5, h + 2, (b.z1 + b.z2) / 2 + 5))
  end
  vent(K, mdl, b.x1 + 6, h + 1, b.z1 + 6); vent(K, mdl, b.x2 - 6, h + 1, b.z2 - 6)
  return mdl
end
-- 8 OFFICE (command offices): tall with vertical dark fins and glazing strips
function T.office(H, K, BB, par, b, ups, rng)
  ups = nil
  local h = ({46, 52, 58})[rng:NextInteger(1, 3)]
  local mdl = BB(H, K, par, {name = b.name, x1 = b.x1, z1 = b.z1, x2 = b.x2, z2 = b.z2, h = h}, ups)
  local d = doorCentres(b)
  local function faceX(z, out, list, edge)
    if edge then return end
    for x = b.x1 + 4, b.x2 - 4, 6 do
      local inDoor = nearDoor(list, x, 7)
      local y0 = inDoor and 13 or 2
      deco(metal(K.B(mdl, "Fin", x - 0.4, y0, math.min(z, z + out * 1.4), x + 0.4, h - 3, math.max(z, z + out * 1.4)), Color3.fromRGB(70, 72, 76)))
      if x + 6 <= b.x2 - 4 then deco(K.B(mdl, "Glazing", x + 1.2, 16, math.min(z, z + out * 0.15), x + 4.8, h - 6, math.max(z, z + out * 0.15), GLASS, Enum.Material.Glass)) end
    end
  end
  faceX(b.z1, -1, d.N, b.z1 <= -229); faceX(b.z2, 1, d.S, b.z2 >= 229)
  hvac(K, mdl, (b.x1 + b.x2) / 2 - 8, h + 1, (b.z1 + b.z2) / 2); hvac(K, mdl, (b.x1 + b.x2) / 2 + 8, h + 1, (b.z1 + b.z2) / 2)
  return mdl
end
return T
