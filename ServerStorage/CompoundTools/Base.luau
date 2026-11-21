local K = require(script.Parent.Kit)
local C = require(script.Parent.Constructs)
local B = {}
local WHITE = Color3.fromRGB(226, 228, 228)
local DARK = Color3.fromRGB(58, 62, 68)
local TREADC = Color3.fromRGB(92, 96, 100)
local MIDC = Color3.fromRGB(132, 136, 140)
local YEL = Color3.fromRGB(222, 178, 46)
B.LV = 12.2
local function style(p, k)
  if not p then return end
  if k == "w" then p.Material = Enum.Material.Metal; p.MaterialVariant = "VS_GlossPanel"; p.Color = WHITE; p.Reflectance = 0.06
  elseif k == "d" then p.Material = Enum.Material.Metal; p.MaterialVariant = "VS_Gunmetal"; p.Color = DARK; p.Reflectance = 0.08
  elseif k == "t" then p.Material = Enum.Material.DiamondPlate; p.MaterialVariant = "VS_TreadPlate"; p.Color = TREADC
  elseif k == "m" then p.Material = Enum.Material.Metal; p.MaterialVariant = "VS_ForgedPanel"; p.Color = MIDC
  elseif k == "y" then p.Material = Enum.Material.Metal; p.MaterialVariant = ""; p.Color = YEL
  elseif k == "n" then p.Material = Enum.Material.Neon; p.MaterialVariant = ""; p.Color = Color3.fromRGB(236, 238, 236); p.CanCollide = false; p.CastShadow = false
  elseif k == "g" then p.Material = Enum.Material.Glass; p.MaterialVariant = ""; p.Color = Color3.fromRGB(84, 90, 96); p.Reflectance = 0.12; p.Transparency = 0.1 end
  return p
end
B.style = style
local function box(par, name, x1, y1, z1, x2, y2, z2, k) return style(K.B(par, name, x1, y1, z1, x2, y2, z2), k) end
B.box = box
local function tilted(par, name, size, x, y, z, ax, ay, k)
  return style(K.P(par, name, size, K.W(x, y, z) * CFrame.Angles(math.rad(ax or 0), math.rad(ay or 0), 0), WHITE, Enum.Material.Concrete), k)
end
-- seams + slit windows on a face. axis "x": face runs along x at z=f, outward sign n
function B.face(par, axis, a, b, f, n, y1, y2, slitY, step)
  step = step or 8
  for v = a + step, b - 2, step do
    if axis == "x" then box(par, "Seam", v - 0.1, y1 + 0.3, f, v + 0.1, y2 - 0.3, f + n * 0.12, "d")
    else box(par, "Seam", f, y1 + 0.3, v - 0.1, f + n * 0.12, y2 - 0.3, v + 0.1, "d") end
  end
  if slitY then
    for v = a + 6, b - 5, 12 do
      if axis == "x" then box(par, "Slit", v - 0.7, slitY, f, v + 0.7, slitY + 2.4, f + n * 0.16, "d")
      else box(par, "Slit", f, slitY, v - 0.7, f + n * 0.16, slitY + 2.4, v + 0.7, "d") end
    end
  end
end
-- rails on rectangle edges with gaps at points
function B.edgeRails(par, x1, z1, x2, z2, y, gaps, gw)
  gw = gw or 8; gaps = gaps or {}
  local sides = {{"x", z1, x1, x2, 0.3}, {"x", z2, x1, x2, -0.3}, {"z", x1, z1, z2, 0.3}, {"z", x2, z1, z2, -0.3}}
  for _, s in ipairs(sides) do
    local cuts = {}
    for _, g in ipairs(gaps) do
      local perp = (s[1] == "x") and g[2] or g[1]
      local along = (s[1] == "x") and g[1] or g[2]
      if math.abs(perp - s[2]) < 2.5 and along > s[3] - 3 and along < s[4] + 3 then table.insert(cuts, {along - gw / 2, along + gw / 2}) end
    end
    table.sort(cuts, function(p, q) return p[1] < q[1] end)
    local pos = s[3]
    local segs = {}
    for _, c in ipairs(cuts) do if c[1] > pos then table.insert(segs, {pos, c[1]}) end pos = math.max(pos, c[2]) end
    if pos < s[4] then table.insert(segs, {pos, s[4]}) end
    for _, sg in ipairs(segs) do
      if sg[2] - sg[1] > 1.5 then
        if s[1] == "x" then C.rail(par, sg[1], s[2] + s[5], sg[2], s[2] + s[5], y) else C.rail(par, s[2] + s[5], sg[1], s[2] + s[5], sg[2], y) end
      end
    end
  end
end
-- sloped ramp from ground to a top point with side skirts + sloped hand rails
function B.ramp(par, ax, az, bx, bz, y, w)
  w = w or 6
  local s = C.stair(par, Vector3.new(ax, 0.2, az), Vector3.new(bx, y, bz), w)
  local A = Vector3.new(ax, 0.2, az + K.CZ); local Bv = Vector3.new(bx, y, bz + K.CZ)
  local cf = CFrame.lookAt((A + Bv) / 2, Bv); local L = (Bv - A).Magnitude
  for _, sd in ipairs({-1, 1}) do
    local top = K.P(par, "RailTop", Vector3.new(0.28, 0.28, L), cf * CFrame.new(sd * (w / 2 - 0.2), 3.4, 0), YEL, Enum.Material.Metal); top.CastShadow = false
    local blk = K.P(par, "RailBlocker", Vector3.new(0.4, 3.4, L), cf * CFrame.new(sd * (w / 2 - 0.2), 1.7, 0), DARK, Enum.Material.Metal); blk.Transparency = 1
    for i = 0, math.floor(L / 5) do
      local p = K.P(par, "RailPost", Vector3.new(0.25, 3.4, 0.25), cf * CFrame.new(sd * (w / 2 - 0.2), 1.7, -L / 2 + i * L / math.floor(L / 5)), DARK, Enum.Material.Metal); p.CastShadow = false
    end
    style(K.P(par, "RampSkirt", Vector3.new(0.6, 1.6, L), cf * CFrame.new(sd * (w / 2 + 0.3), -1.1, 0), WHITE, Enum.Material.Concrete), "d")
  end
  -- support piers
  local n = math.floor(L / 14)
  for i = 1, n do
    local t = i / (n + 1); local p = A:Lerp(Bv, t)
    if p.Y > 3 then style(K.P(par, "RampPier", Vector3.new(w - 1, p.Y - 0.6, 1.6), CFrame.lookAt(Vector3.new(p.X, (p.Y - 0.6) / 2, p.Z), Vector3.new(p.X, (p.Y - 0.6) / 2, p.Z) + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit), WHITE, Enum.Material.Concrete), "w") end
  end
  return s
end
-- catwalk at LV between two axis-aligned points
function B.catwalk(par, ax, az, bx, bz, y)
  y = y or B.LV
  local m = Instance.new("Model"); m.Name = "Catwalk"; m.Parent = par
  local alongX = math.abs(bx - ax) > math.abs(bz - az)
  local w = 3
  if alongX then
    box(m, "Deck", ax, y - 1.2, az - w, bx, y, az + w, "t")
    for _, s in ipairs({-1, 1}) do box(m, "EdgeBeam", ax, y - 2.2, az + s * w - 0.4, bx, y - 0.6, az + s * w + 0.4, "d"); C.rail(m, ax, az + s * (w - 0.3), bx, az + s * (w - 0.3), y) end
  else
    box(m, "Deck", ax - w, y - 1.2, az, ax + w, y, bz, "t")
    for _, s in ipairs({-1, 1}) do box(m, "EdgeBeam", ax + s * w - 0.4, y - 2.2, az, ax + s * w + 0.4, y - 0.6, bz, "d"); C.rail(m, ax + s * (w - 0.3), az, ax + s * (w - 0.3), bz, y) end
  end
  local L = alongX and math.abs(bx - ax) or math.abs(bz - az)
  local n = math.max(1, math.floor(L / 16))
  local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = {m}
  for i = 1, n - 1 + ((L > 20) and 0 or 1) do
    local t = (n == 1) and 0.5 or i / n
    local x = ax + (bx - ax) * t; local z = az + (bz - az) * t
    local hit = workspace:Raycast(Vector3.new(x, y - 2.5, z + K.CZ), Vector3.new(0, -60, 0), rp)
    local gy = hit and hit.Position.Y or 0
    if y - 2.4 - gy > 1 then
      for _, s in ipairs({-1, 1}) do
        local px, pz = alongX and x or x + s * 2.2, alongX and z + s * 2.2 or z
        box(m, "Pillar", px - 0.8, gy, pz - 0.8, px + 0.8, y - 2.2, pz + 0.8, "w")
      end
      if alongX then box(m, "PillarBeam", x - 0.6, y - 3.4, z - 3, x + 0.6, y - 2.2, z + 3, "d") else box(m, "PillarBeam", x - 3, y - 3.4, z - 0.6, x + 3, y - 2.2, z + 0.6, "d") end
    end
  end
  return m
end
local function door(par, side, x, z, y0, w, h, inward)
  -- frame on outer face
  if side == "x" then
    box(par, "DoorFrame", x - w / 2 - 0.6, y0, z, x - w / 2, y0 + h + 0.6, z + inward * -0.4, "d")
    box(par, "DoorFrame", x + w / 2, y0, z, x + w / 2 + 0.6, y0 + h + 0.6, z + inward * -0.4, "d")
    box(par, "DoorFrame", x - w / 2 - 0.6, y0 + h, z, x + w / 2 + 0.6, y0 + h + 0.6, z + inward * -0.4, "d")
    box(par, "Jamb", x - w / 2 - 0.2, y0, z - 0.05, x - w / 2, y0 + h, z + inward * -0.5, "y")
    box(par, "DoorLight", x - 1.6, y0 + h + 0.8, z, x + 1.6, y0 + h + 1.1, z + inward * -0.3, "n")
  else
    box(par, "DoorFrame", x, y0, z - w / 2 - 0.6, x + inward * -0.4, y0 + h + 0.6, z - w / 2, "d")
    box(par, "DoorFrame", x, y0, z + w / 2, x + inward * -0.4, y0 + h + 0.6, z + w / 2 + 0.6, "d")
    box(par, "DoorFrame", x, y0 + h, z - w / 2 - 0.6, x + inward * -0.4, y0 + h + 0.6, z + w / 2 + 0.6, "d")
    box(par, "Jamb", x - 0.05, y0, z - w / 2 - 0.2, x + inward * -0.5, y0 + h, z - w / 2, "y")
    box(par, "DoorLight", x, y0 + h + 0.8, z - 1.6, x + inward * -0.3, y0 + h + 1.1, z + 1.6, "n")
  end
end
B.door = door

---------------- HQ: two-tier block, finned lower terrace, glazed set-back upper ----------------
function B.hq(par, name, x1, z1, x2, z2, s, o)
  local m = Instance.new("Model"); m.Name = name
  local zf = s > 0 and z2 or z1; local zb = s > 0 and z1 or z2
  local d = math.abs(z2 - z1); local zu = zb + s * d * 0.5
  local px = o.passX or (x1 + x2) / 2
  box(m, "Lower", x1, 0, z1, px - 5, 12, z2, "w"); box(m, "Lower", px + 5, 0, z1, x2, 12, z2, "w"); box(m, "Lower", px - 5, 8.4, z1, px + 5, 12, z2, "w")
  door(m, "x", px, z1, 0, 10, 8.4, 1); door(m, "x", px, z2, 0, 10, 8.4, -1)
  box(m, "PassLight", px - 0.3, 8.1, z1 + 2, px + 0.3, 8.4, z2 - 2, "n")
  for _, f in ipairs({{zf, s}, {zb, -s}}) do
    box(m, "Base", x1 - 0.3, 0, f[1], px - 5.6, 1.4, f[1] + f[2] * 0.35, "d"); box(m, "Base", px + 5.6, 0, f[1], x2 + 0.3, 1.4, f[1] + f[2] * 0.35, "d")
    box(m, "Cornice", x1 - 0.4, 11, f[1], x2 + 0.4, 12, f[1] + f[2] * 0.45, "d")
    B.face(m, "x", x1, x2, f[1], f[2], 1.4, 11, 6, 8)
  end
  for _, f in ipairs({{x1, -1}, {x2, 1}}) do
    box(m, "Base", f[1], 0, z1 - 0.3, f[1] + f[2] * 0.35, 1.4, z2 + 0.3, "d"); box(m, "Cornice", f[1], 11, z1 - 0.4, f[1] + f[2] * 0.45, 12, z2 + 0.4, "d")
    B.face(m, "z", z1, z2, f[1], f[2], 1.4, 11, 6, 8)
  end
  for x = x1 + 7, x2 - 7, 12 do
    if math.abs(x - px) > 9 and not (o.noFin and x > o.noFin[1] and x < o.noFin[2]) then
      tilted(m, "Fin", Vector3.new(2, 12.6, 3), x, 6.1, zf + s * 1.3, s * -11, 0, "w")
      box(m, "FinCap", x - 1.1, 11.8, zf, x + 1.1, 12.2, zf + s * 3.2, "d")
    end
  end
  box(m, "LowerDeck", x1, 12, math.min(zu, zf), x2, 12.2, math.max(zu, zf), "t")
  -- upper tier
  box(m, "Upper", x1 + 4, 12, zb, x2 - 4, 26, zu, "w")
  box(m, "GlazeFrame", x1 + 5.5, 14.6, zu, x2 - 5.5, 23.4, zu + s * 0.25, "d")
  box(m, "Glass", x1 + 6, 15, zu + s * 0.25, x2 - 6, 23, zu + s * 0.45, "g")
  for x = x1 + 7, x2 - 7, 8 do tilted(m, "UpperFin", Vector3.new(1.4, 14.4, 2.4), x, 19, zu + s * 1.4, s * 9, 0, "w") end
  box(m, "UpperCap", x1 + 3.5, 26, math.min(zb, zu) - 0.5, x2 - 3.5, 27.4, math.max(zb, zu) + 0.5, "d")
  B.face(m, "x", x1 + 4, x2 - 4, zb, -s, 12, 26, 18, 8)
  B.face(m, "z", math.min(zb, zu), math.max(zb, zu), x1 + 4, -1, 12, 26, 18, 8)
  B.face(m, "z", math.min(zb, zu), math.max(zb, zu), x2 - 4, 1, 12, 26, 18, 8)
  local r = Random.new(#name)
  for i = 1, 4 do
    local x = x1 + 10 + (x2 - x1 - 20) * (i - 0.5) / 4; local z = (zb + zu) / 2 + r:NextNumber(-3, 3)
    box(m, "RoofUnit", x - 3, 27.4, z - 2.2, x + 3, 30, z + 2.2, "m"); box(m, "RoofUnitGrille", x - 2.4, 30, z - 1.6, x + 2.4, 30.2, z + 1.6, "d")
  end
  if o.dome then
    local cx, cz = o.dome[1], o.dome[2]
    box(m, "DomeDrum", cx - 6, 27.4, cz - 6, cx + 6, 31, cz + 6, "d")
    local ball = K.P(m, "Dome", Vector3.new(19, 19, 19), K.W(cx, 38, cz), Color3.fromRGB(214, 216, 216), Enum.Material.SmoothPlastic); ball.Shape = Enum.PartType.Ball
    local sb = K.P(m, "Dome", Vector3.new(5, 5, 5), K.W(cx + 10, 31.5, cz), Color3.fromRGB(214, 216, 216), Enum.Material.SmoothPlastic); sb.Shape = Enum.PartType.Ball
  end
  if o.mast then
    local cx, cz = o.mast[1], o.mast[2]
    box(m, "MastBase", cx - 3, 27.4, cz - 3, cx + 3, 30, cz + 3, "d")
    for _, c in ipairs({{-1.2, -1.2}, {1.2, -1.2}, {-1.2, 1.2}, {1.2, 1.2}}) do box(m, "MastLeg", cx + c[1] - 0.2, 30, cz + c[2] - 0.2, cx + c[1] + 0.2, 52, cz + c[2] + 0.2, "d") end
    for y = 33, 50, 4 do box(m, "MastRing", cx - 1.5, y, cz - 1.5, cx + 1.5, y + 0.3, cz + 1.5, "d") end
    box(m, "MastArm", cx - 5, 46, cz - 0.3, cx + 5, 46.5, cz + 0.3, "m")
    box(m, "MastLight", cx - 0.5, 52, cz - 0.5, cx + 0.5, 53, cz + 0.5, "n")
  end
  -- lower terrace furniture
  local zc = (zu + zf) / 2
  local k = 0
  for x = x1 + 14, x2 - 14, 22 do
    k += 1
    if k % 2 == 1 then C.lowWall(m, x - 4, zc - 0.6, x + 4, zc + 0.6, 12.2, 3.4) else C.sandbags(m, x, 12.2, zc + s * 2, 3, 0) end
  end
  B.edgeRails(m, x1, math.min(zu, zf), x2, math.max(zu, zf), 12.2, o.gaps)
  if o.label then C.label(m, o.label, px, 10.2, zf + s * 0.55, 0, s, 12) end
  m.Parent = par
  return m
end

---------------- STILT: box on pillars, enterable, roof via inner ramp ----------------
function B.stilt(par, name, x1, z1, x2, z2, doors, rampSide, o)
  o = o or {}
  local m = Instance.new("Model"); m.Name = name
  local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
  for _, x in ipairs({x1 + 2, cx, x2 - 2}) do for _, z in ipairs({z1 + 2, cz, z2 - 2}) do
    if not (x == cx and z == cz) then
      box(m, "Pillar", x - 1.3, 0, z - 1.3, x + 1.3, 10.5, z + 1.3, "w"); box(m, "PillarFoot", x - 1.8, 0, z - 1.8, x + 1.8, 0.8, z + 1.8, "d")
    end
  end end
  box(m, "FloorSlab", x1 - 0.5, 10.5, z1 - 0.5, x2 + 0.5, 12, z2 + 0.5, "d"); box(m, "Floor", x1, 12, z1, x2, 12.2, z2, "t")
  -- angled skirts under the slab edge
  tilted(m, "Skirt", Vector3.new(x2 - x1, 0.6, 3), cx, 9.9, z1 + 1.2, -32, 0, "d")
  tilted(m, "Skirt", Vector3.new(x2 - x1, 0.6, 3), cx, 9.9, z2 - 1.2, 32, 0, "d")
  tilted(m, "Skirt", Vector3.new(z2 - z1, 0.6, 3), x1 + 1.2, 9.9, cz, 32, 90, "d")
  tilted(m, "Skirt", Vector3.new(z2 - z1, 0.6, 3), x2 - 1.2, 9.9, cz, -32, 90, "d")
  local Y0, Y1 = 12.2, 23
  local hasDoor = {}; for _, d in ipairs(doors) do hasDoor[d] = true end
  local function wall(side)
    local alongX = (side == "N" or side == "S")
    local a, b = alongX and x1 or z1, alongX and x2 or z2
    local c = alongX and cx or cz
    local f1, f2
    if side == "N" then f1, f2 = z1, z1 + 1 elseif side == "S" then f1, f2 = z2 - 1, z2 elseif side == "W" then f1, f2 = x1, x1 + 1 else f1, f2 = x2 - 1, x2 end
    local segs = hasDoor[side] and {{a, c - 3, Y0, Y1}, {c + 3, b, Y0, Y1}, {c - 3, c + 3, Y0 + 7.4, Y1}} or {{a, b, Y0, Y1}}
    for _, sg in ipairs(segs) do
      if alongX then box(m, "Wall", sg[1], sg[3], f1, sg[2], sg[4], f2, "w") else box(m, "Wall", f1, sg[3], sg[1], f2, sg[4], sg[2], "w") end
    end
    local out = (side == "N" or side == "W") and -1 or 1
    local fo = (out < 0) and f1 or f2
    if hasDoor[side] then
      if alongX then door(m, "x", c, fo, Y0, 6, 7.4, -out) else door(m, "z", fo, c, Y0, 6, 7.4, -out) end
    end
    if alongX then box(m, "Band", a - 0.3, 20, fo, b + 0.3, 21.2, fo + out * 0.35, "d") else box(m, "Band", fo, 20, a - 0.3, fo + out * 0.35, 21.2, b + 0.3, "d") end
    B.face(m, alongX and "x" or "z", a, b, fo, out, Y0, 20, if hasDoor[side] then nil else 15.5, 7.5)
  end
  for _, sd in ipairs({"N", "S", "W", "E"}) do wall(sd) end
  -- roof with stair hole
  local hx1, hz1, hx2, hz2, A, Bv
  local L
  if rampSide == "E" or rampSide == "W" then
    local bx = (rampSide == "E") and x2 - 3.5 or x1 + 3.5
    A = Vector3.new(bx, Y0, z1 + 2); Bv = Vector3.new(bx, 24.2, z2 - 2); L = z2 - z1 - 4
    hx1, hx2 = bx - 2.5, bx + 2.5; hz1, hz2 = z1 + 2 + L * 0.3, z2 - 1
  else
    local bz = (rampSide == "S") and z2 - 3.5 or z1 + 3.5
    A = Vector3.new(x1 + 2, Y0, bz); Bv = Vector3.new(x2 - 2, 24.2, bz); L = x2 - x1 - 4
    hz1, hz2 = bz - 2.5, bz + 2.5; hx1, hx2 = x1 + 2 + L * 0.3, x2 - 1
  end
  C.stair(m, A, Bv, 4)
  local function roofPiece(a1, b1, a2, b2)
    if a2 - a1 > 0.1 and b2 - b1 > 0.1 then box(m, "Roof", a1, 23, b1, a2, 24, b2, "d"); box(m, "RoofDeck", a1, 24, b1, a2, 24.2, b2, "t") end
  end
  roofPiece(x1 - 0.4, z1 - 0.4, hx1, z2 + 0.4); roofPiece(hx2, z1 - 0.4, x2 + 0.4, z2 + 0.4)
  roofPiece(hx1, z1 - 0.4, hx2, hz1); roofPiece(hx1, hz2, hx2, z2 + 0.4)
  if rampSide == "E" or rampSide == "W" then C.rail(m, (rampSide == "E") and hx1 or hx2, hz1, (rampSide == "E") and hx1 or hx2, hz2, 24.2); C.rail(m, hx1, hz1, hx2, hz1, 24.2)
  else C.rail(m, hx1, (rampSide == "S") and hz1 or hz2, hx2, (rampSide == "S") and hz1 or hz2, 24.2); C.rail(m, hx1, hz1, hx1, hz2, 24.2) end
  B.edgeRails(m, x1 - 0.4, z1 - 0.4, x2 + 0.4, z2 + 0.4, 24.2, {})
  C.sandbags(m, cx - 5, 24.2, cz + ((rampSide == "N") and 5 or -5), 3, 0)
  box(m, "RoofBox", cx + 2, 24.2, cz - 2, cx + 7, 27, cz + 2, "m")
  -- ground cover underneath
  box(m, "Crate", cx - 6, 0, cz - 2, cx - 2, 3.2, cz + 2, "m"); box(m, "Crate", cx + 3, 0, cz + 3, cx + 7, 3.2, cz + 7, "m")
  if o.label then
    local sd = o.labelSide or "S"
    if sd == "S" then C.label(m, o.label, cx + 8, 17.5, z2 + 0.6, 0, 1, 9) elseif sd == "N" then C.label(m, o.label, cx - 8, 17.5, z1 - 0.6, 0, -1, 9)
    elseif sd == "E" then C.label(m, o.label, x2 + 0.6, 17.5, cz + 8, 1, 0, 9) else C.label(m, o.label, x1 - 0.6, 17.5, cz - 8, -1, 0, 9) end
  end
  m.Parent = par
  return m
end

---------------- BARRACKS: long low block, chamfered edges, walk-on roof ----------------
function B.barracks(par, name, x1, z1, x2, z2, o)
  local m = Instance.new("Model"); m.Name = name
  local passes = o.passes or {}
  -- mass with through-passages across z at given x's
  local xs = {x1}
  for _, p in ipairs(passes) do table.insert(xs, p - 4); table.insert(xs, p + 4) end
  table.insert(xs, x2)
  for i = 1, #xs, 2 do box(m, "Mass", xs[i], 0, z1, xs[i + 1], 12, z2, "w") end
  for _, p in ipairs(passes) do
    box(m, "Mass", p - 4, 8.4, z1, p + 4, 12, z2, "w")
    door(m, "x", p, z1, 0, 8, 8.4, 1); door(m, "x", p, z2, 0, 8, 8.4, -1)
    box(m, "PassLight", p - 0.3, 8.1, z1 + 2, p + 0.3, 8.4, z2 - 2, "n")
  end
  -- chamfered long edges (rotated 45 bars)
  for _, z in ipairs({z1, z2}) do
    style(K.P(m, "Chamfer", Vector3.new(x2 - x1, 2.2, 2.2), K.W((x1 + x2) / 2, 11.2, z) * CFrame.Angles(math.rad(45), 0, 0), WHITE, Enum.Material.Concrete), "w")
    box(m, "Base", x1, 0, z, x2, 1.4, z + ((z == z1) and -0.35 or 0.35), "d")
    B.face(m, "x", x1, x2, z, (z == z1) and -1 or 1, 1.4, 9.6, 5.5, 6)
    box(m, "Band", x1, 9.6, z, x2, 10.2, z + ((z == z1) and -0.3 or 0.3), "d")
  end
  for _, x in ipairs({x1, x2}) do
    box(m, "Base", x, 0, z1, x + ((x == x1) and -0.35 or 0.35), 1.4, z2, "d")
    B.face(m, "z", z1, z2, x, (x == x1) and -1 or 1, 1.4, 11, 5.5, 6)
  end
  box(m, "RoofDeck", x1 + 1, 12, z1 + 1, x2 - 1, 12.2, z2 - 1, "t")
  -- roof cover: units + vents, alternating
  local k = 0
  for x = x1 + 10, x2 - 8, 15 do
    k += 1
    local z = (k % 2 == 0) and z1 + (z2 - z1) * 0.33 or z1 + (z2 - z1) * 0.67
    box(m, "RoofUnit", x - 3.5, 12.2, z - 2.5, x + 3.5, 15.6, z + 2.5, "m"); box(m, "RoofUnitTop", x - 3.8, 15.6, z - 2.8, x + 3.8, 16, z + 2.8, "d")
  end
  B.edgeRails(m, x1 + 1, z1 + 1, x2 - 1, z2 - 1, 12.2, o.gaps)
  if o.label then C.label(m, o.label, o.labelX or (x1 + x2) / 2, 7.6, (o.labelZ == "z1") and z1 - 0.55 or z2 + 0.55, 0, (o.labelZ == "z1") and -1 or 1, 11) end
  m.Parent = par
  return m
end

---------------- WATCHTOWER with scaffold stair (scaffold on west, door at z dz) ----------------
function B.watch(par, name, tx1, tz1, o)
  local m = Instance.new("Model"); m.Name = name
  local tx2, tz2 = tx1 + 14, tz1 + 14
  box(m, "Shaft", tx1, 0, tz1, tx2, 22, tz2, "w")
  for _, x in ipairs({tx1 + 4, tx2 - 4}) do box(m, "ShaftRecess", x - 0.8, 2, tz2, x + 0.8, 21, tz2 + 0.2, "d"); box(m, "ShaftRecess", x - 0.8, 2, tz1 - 0.2, x + 0.8, 21, tz1, "d") end
  box(m, "Base", tx1 - 0.4, 0, tz1 - 0.4, tx2 + 0.4, 1.6, tz2 + 0.4, "d")
  box(m, "Collar", tx1 - 0.6, 21, tz1 - 0.6, tx2 + 0.6, 22.2, tz2 + 0.6, "d")
  -- cabin: posts + low wall + big windows
  local Y0 = 22.2
  box(m, "CabinFloor", tx1, 22, tz1, tx2, 22.2, tz2, "t")
  for _, c in ipairs({{tx1, tz1}, {tx2 - 1.2, tz1}, {tx1, tz2 - 1.2}, {tx2 - 1.2, tz2 - 1.2}}) do box(m, "CabinPost", c[1], Y0, c[2], c[1] + 1.2, 30, c[2] + 1.2, "w") end
  local dz = o.doorZ
  -- sill walls (west side has the door)
  box(m, "Sill", tx1 + 1.2, Y0, tz1, tx2 - 1.2, Y0 + 3.4, tz1 + 1, "w"); box(m, "Sill", tx1 + 1.2, Y0, tz2 - 1, tx2 - 1.2, Y0 + 3.4, tz2, "w")
  box(m, "Sill", tx2 - 1, Y0, tz1 + 1.2, tx2, Y0 + 3.4, tz2 - 1.2, "w")
  box(m, "Sill", tx1, Y0, tz1 + 1.2, tx1 + 1, Y0 + 3.4, dz - 3, "w"); box(m, "Sill", tx1, Y0, dz + 3, tx1 + 1, Y0 + 3.4, tz2 - 1.2, "w")
  box(m, "Header", tx1, 28.4, tz1, tx2, 30, tz2, "w")
  box(m, "Roof", tx1 - 1.2, 30, tz1 - 1.2, tx2 + 1.2, 31.2, tz2 + 1.2, "d")
  tilted(m, "Visor", Vector3.new(16.4, 0.5, 2.4), (tx1 + tx2) / 2, 29.6, tz2 + 1.4, 25, 0, "d")
  tilted(m, "Visor", Vector3.new(16.4, 0.5, 2.4), (tx1 + tx2) / 2, 29.6, tz1 - 1.4, -25, 0, "d")
  box(m, "Antenna", tx2 - 3, 31.2, tz1 + 2, tx2 - 2.6, 42, tz1 + 2.4, "d"); box(m, "AntennaTip", tx2 - 3.2, 42, tz1 + 1.8, tx2 - 2.4, 42.6, tz1 + 2.6, "n")
  -- scaffold west of tower: x tx1-10..tx1, z sz1..sz2 (26 long), flights
  local sx1, sx2 = tx1 - 10, tx1
  local sz1, sz2 = o.sz1, o.sz1 + 26
  for _, c in ipairs({{sx1, sz1}, {sx1, sz2}, {sx2, sz1}, {sx2, sz2}, {sx1, sz1 + 13}, {sx2, sz1 + 13}}) do box(m, "ScaffoldPost", c[1] - 0.3, 0, c[2] - 0.3, c[1] + 0.3, 31, c[2] + 0.3, "d") end
  for _, y in ipairs({6, 18, 30}) do
    box(m, "ScaffoldBeam", sx1 - 0.3, y, sz1 - 0.3, sx1 + 0.3, y + 0.4, sz2 + 0.3, "d"); box(m, "ScaffoldBeam", sx2 - 0.3, y, sz1 - 0.3, sx2 + 0.3, y + 0.4, sz2 + 0.3, "d")
  end
  for i = 0, 2 do
    local a = sz1 + i * 8.6
    local p = K.P(m, "Brace", Vector3.new(0.3, 0.3, 14), K.W(sx1 - 0.4, 0, a + 4.3) * CFrame.new(0, 12, 0) * CFrame.Angles(math.rad(52), 0, 0), DARK, Enum.Material.Metal); style(p, "d")
  end
  -- flight 1: ground (sz2) -> L1 at sz1 (y12.2), band x sx1..sx1+5
  C.stair(m, Vector3.new(sx1 + 2.6, 0.2, sz2), Vector3.new(sx1 + 2.6, 12.2, sz1 + 4), 5)
  box(m, "Landing", sx1, 11, sz1, sx2, 12.2, sz1 + 4, "t")
  -- flight 2: L1 -> L2 near tower door (y22.2), band x sx2-5..sx2
  C.stair(m, Vector3.new(sx2 - 2.4, 12.2, sz1 + 4), Vector3.new(sx2 - 2.4, 22.2, dz - 2), 4.8)
  box(m, "Landing", sx1 + 5, 21, dz - 2, sx2, 22.2, dz + 2, "t")
  C.rail(m, sx1 + 5.2, dz - 2, sx1 + 5.2, dz + 2, 22.2); C.rail(m, sx1 + 5, dz + 2, sx2, dz + 2, 22.2)
  C.rail(m, sx1 + 0.3, sz1, sx1 + 0.3, sz1 + 4, 12.2)
  if o.label then C.label(m, o.label, (tx1 + tx2) / 2, 18, tz2 + 0.55, 0, 1, 8) end
  m.Parent = par
  return m
end

---------------- PUMP STATION: chamfered block + tanks + chimney ----------------
function B.pump(par, name, x1, z1, x2, z2, o)
  local m = Instance.new("Model"); m.Name = name
  local c = 4
  box(m, "Core", x1 + c, 0, z1, x2 - c, 12, z2, "w"); box(m, "Core", x1, 0, z1 + c, x2, 12, z2 - c, "w")
  for _, p in ipairs({{x1 + c, z1 + c}, {x2 - c, z1 + c}, {x1 + c, z2 - c}, {x2 - c, z2 - c}}) do
    style(K.P(m, "Corner", Vector3.new(c * 1.414, 12, c * 1.414), K.W(p[1], 6, p[2]) * CFrame.Angles(0, math.rad(45), 0), WHITE, Enum.Material.Concrete), "w")
  end
  box(m, "Base", x1 + c, 0, z1 - 0.35, x2 - c, 1.4, z2 + 0.35, "d"); box(m, "Base", x1 - 0.35, 0, z1 + c, x2 + 0.35, 1.4, z2 - c, "d")
  box(m, "Cap", x1 + c, 11, z1 - 0.4, x2 - c, 12, z2 + 0.4, "d"); box(m, "Cap", x1 - 0.4, 11, z1 + c, x2 + 0.4, 12, z2 - c, "d")
  B.face(m, "x", x1 + c, x2 - c, z1, -1, 1.4, 11, 6, 6); B.face(m, "x", x1 + c, x2 - c, z2, 1, 1.4, 11, 6, 6)
  B.face(m, "z", z1 + c, z2 - c, x1, -1, 1.4, 11, nil, 6); B.face(m, "z", z1 + c, z2 - c, x2, 1, 1.4, 11, nil, 6)
  box(m, "RoofDeck", x1 + c, 12, z1 + 1, x2 - c, 12.2, z2 - 1, "t"); box(m, "RoofDeck", x1 + 1, 12, z1 + c, x2 - 1, 12.2, z2 - c, "t")
  -- tanks on roof (cover) + chimney (tall landmark)
  local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
  for i, t in ipairs(o.tanks) do
    local p = K.P(m, "Tank", Vector3.new(9, 7, 7), K.W(t[1], 12.2 + 3.5, t[2]) * CFrame.Angles(0, 0, 0), MIDC, Enum.Material.Metal)
    p.Shape = Enum.PartType.Cylinder; p.CFrame = K.W(t[1], 12.2 + 3.6, t[2]) * CFrame.Angles(0, math.rad(t[3] or 0), 0); style(p, "m")
    box(m, "TankSaddle", t[1] - 0.6, 12.2, t[2] - 3, t[1] + 0.6, 13.6, t[2] + 3, "d")
    local band = K.P(m, "TankBand", Vector3.new(0.6, 7.2, 7.2), p.CFrame, YEL, Enum.Material.Metal); band.Shape = Enum.PartType.Cylinder; band.CanCollide = false
  end
  local ch = o.chimney
  local cyl = K.P(m, "Chimney", Vector3.new(30, 5, 5), K.W(ch[1], 12.2 + 15, ch[2]) * CFrame.Angles(0, 0, math.rad(90)), MIDC, Enum.Material.Metal); cyl.Shape = Enum.PartType.Cylinder; style(cyl, "m")
  for _, y in ipairs({20, 30, 40}) do local r = K.P(m, "ChimneyRing", Vector3.new(0.6, 5.6, 5.6), K.W(ch[1], y, ch[2]) * CFrame.Angles(0, 0, math.rad(90)), DARK, Enum.Material.Metal); r.Shape = Enum.PartType.Cylinder end
  box(m, "ChimneyLight", ch[1] - 0.5, 42.2, ch[2] - 0.5, ch[1] + 0.5, 43, ch[2] + 0.5, "n")
  -- pipe run down the side
  for _, pp in ipairs(o.pipes or {}) do
    local p = K.P(m, "Pipe", Vector3.new(pp[3], 1.4, 1.4), K.W(pp[1], pp[4], pp[2]), MIDC, Enum.Material.Metal); p.Shape = Enum.PartType.Cylinder
    if pp[5] then p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(90), 0) end; style(p, "m")
  end
  B.edgeRails(m, x1 + c, z1 + 1, x2 - c, z2 - 1, 12.2, o.gaps)
  if o.label then C.label(m, o.label, cx, 8, z2 + 0.55, 0, 1, 12) end
  m.Parent = par
  return m
end

---------------- DOCK: concrete plinth + container stack top at LV ----------------
local function ctr(par, x, z, rot, yb, tone)
  local cf = K.W(x, yb + 4.5, z) * CFrame.Angles(0, math.rad(rot), 0)
  local c = K.P(par, "Container", Vector3.new(24, 9, 9), cf, Color3.new(0.36 * tone, 0.38 * tone, 0.40 * tone), Enum.Material.Metal); c.MaterialVariant = "VS_CorrugatedSteel"
  for _, s in ipairs({-1, 1}) do K.P(par, "ContainerEnd", Vector3.new(0.4, 9.2, 9.2), cf * CFrame.new(s * 12, 0, 0), DARK, Enum.Material.Metal).CastShadow = false end
  for _, s in ipairs({-1, 1}) do local r = K.P(par, "ContainerRib", Vector3.new(24.1, 0.35, 0.35), cf * CFrame.new(0, 4.4, s * 4.4), DARK, Enum.Material.Metal); r.CanCollide = false end
  local st = K.P(par, "ContainerStripe", Vector3.new(0.6, 9.1, 9.1), cf * CFrame.new(-9, 0, 0), YEL, Enum.Material.Metal); st.CanCollide = false; st.CastShadow = false
  return c
end
B.ctr = ctr
function B.dock(par, name, x1, z1, x2, z2, o)
  local m = Instance.new("Model"); m.Name = name
  local r = Random.new(#name * 7)
  box(m, "Plinth", x1 - 1, 0, z1 - 1, x2 + 1, 3, z2 + 1, "w"); box(m, "PlinthEdge", x1 - 1.3, 2.4, z1 - 1.3, x2 + 1.3, 3, z2 + 1.3, "y")
  box(m, "Fill", x1 + 9, 3, z1 + 9, x2 - 9, 12, z2 - 9, "d")
  -- perimeter containers (tier 1)
  local nx = math.floor((x2 - x1) / 24)
  local offx = ((x2 - x1) - nx * 24) / 2
  for i = 0, nx - 1 do
    local x = x1 + offx + 12 + i * 24
    ctr(m, x, z1 + 4.5, 0, 3, r:NextNumber(0.85, 1.1)); ctr(m, x, z2 - 4.5, 0, 3, r:NextNumber(0.85, 1.1))
  end
  if offx > 0.5 then box(m, "Fill", x1, 3, z1, x1 + offx, 12, z2, "d"); box(m, "Fill", x2 - offx, 3, z1, x2, 12, z2, "d") end
  local nz = math.floor((z2 - z1 - 18) / 24)
  for j = 0, nz - 1 do
    local z = z1 + 9 + 12 + j * 24
    ctr(m, x1 + offx + 4.5, z, 90, 3, r:NextNumber(0.85, 1.1)); ctr(m, x2 - offx - 4.5, z, 90, 3, r:NextNumber(0.85, 1.1))
  end
  box(m, "TopDeck", x1, 12, z1, x2, 12.2, z2, "t")
  -- tier-2 containers on top as cover, plus sandbag nests
  for _, t in ipairs(o.top) do ctr(m, t[1], t[2], t[3], 12.2, r:NextNumber(0.85, 1.1)) end
  for _, sb in ipairs(o.bags or {}) do C.sandbags(m, sb[1], 12.2, sb[2], 4, sb[3]) end
  B.edgeRails(m, x1, z1, x2, z2, 12.2, o.gaps)
  if o.label then C.label(m, o.label, (x1 + x2) / 2, 1.5, z2 + 1.05, 0, 1, 10) end
  m.Parent = par
  return m
end
return B
