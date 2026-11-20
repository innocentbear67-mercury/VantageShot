local K = require(script.Parent.Kit)
local H = {}
local WHITE = Color3.fromRGB(204, 203, 198)
local INNER = Color3.fromRGB(184, 186, 186)
local CHAR = Color3.fromRGB(60, 61, 63)
local STEEL = Color3.fromRGB(92, 96, 102)
local FLOOR = Color3.fromRGB(170, 168, 164)
local YEL = Color3.fromRGB(222, 178, 46)
local function plaster(p, c) if p then p.Material = Enum.Material.Plaster; p.MaterialVariant = ""; p.Color = c or WHITE end return p end
local function metal(p, c) if p then p.Material = Enum.Material.Metal; p.MaterialVariant = ""; p.Color = c or CHAR; p.CastShadow = p.Size.Magnitude > 6 end return p end
local function deco(p) if p then p.CanCollide = false; p.CanQuery = false; p.CastShadow = false end return p end
H.metal = metal; H.plaster = plaster
-- doors: list of {side, centre(u in local coords along wall), width, height}
function H.build(par, name, x1, z1, x2, z2, h, doors, opts)
  opts = opts or {}
  local m = Instance.new("Model"); m.Name = name
  local T = 2
  -- floor + roof
  local f = K.B(m, "Floor", x1, 0, z1, x2, 0.4, z2, FLOOR, Enum.Material.Pavement); f.MaterialVariant = "VS_ConcreteSlab"
  local r = K.B(m, "Roof", x1, h, z1, x2, h + 1, z2, Color3.fromRGB(196, 194, 190), Enum.Material.Pavement); r.MaterialVariant = "VS_ConcreteSlab"
  local sides = {N = {}, S = {}, E = {}, W = {}}
  for _, d in ipairs(doors) do table.insert(sides[d[1]], {d[2] - d[3] / 2, d[2] + d[3] / 2, d[5] or 0, (d[5] or 0) + d[4]}) end
  -- small high windows on long faces
  local function addWin(list, a, b)
    for u = a + 10, b - 10, 12 do
      local clash = false
      for _, o in ipairs(list) do if u + 2 > o[1] - 2 and u - 2 < o[2] + 2 then clash = true end end
      if not clash then table.insert(list, {u - 1.5, u + 1.5, h - 9, h - 5}) end
    end
  end
  addWin(sides.N, x1, x2); addWin(sides.S, x1, x2); addWin(sides.W, z1, z2); addWin(sides.E, z1, z2)
  local wf = Instance.new("Model"); wf.Name = "Walls"; wf.Parent = m
  K.wallX(wf, "Wall", x1, x2, z1 + T / 2, 0, h, T, sides.N)
  K.wallX(wf, "Wall", x1, x2, z2 - T / 2, 0, h, T, sides.S)
  K.wallZ(wf, "Wall", z1, z2, x1 + T / 2, 0, h, T, sides.W)
  K.wallZ(wf, "Wall", z1, z2, x2 - T / 2, 0, h, T, sides.E)
  for _, p in ipairs(wf:GetChildren()) do plaster(p) end
  -- exterior: roof band, plinth, dark vertical pilasters
  local o = 0.6
  metal(K.B(m, "RoofBand", x1 - o, h - 3, z1 - o, x2 + o, h + 3.5, z1 + 0.3))
  metal(K.B(m, "RoofBand", x1 - o, h - 3, z2 - 0.3, x2 + o, h + 3.5, z2 + o))
  metal(K.B(m, "RoofBand", x1 - o, h - 3, z1, x1 + 0.3, h + 3.5, z2))
  metal(K.B(m, "RoofBand", x2 - 0.3, h - 3, z1, x2 + o, h + 3.5, z2))
  local function pil(x, z) metal(K.B(m, "Pilaster", x - 1, 0, z - 1, x + 1, h - 3, z + 1)) end
  for _, c in ipairs({{x1, z1}, {x2, z1}, {x1, z2}, {x2, z2}}) do pil(c[1], c[2]) end
  local function onDoor(list, u) for _, op in ipairs(list) do if u > op[1] - 2 and u < op[2] + 2 and op[3] == 0 then return true end end return false end
  for x = x1 + 16, x2 - 8, 16 do
    if not onDoor(sides.N, x) then metal(K.B(m, "Pilaster", x - 0.8, 0, z1 - 0.8, x + 0.8, h - 3, z1)) end
    if not onDoor(sides.S, x) then metal(K.B(m, "Pilaster", x - 0.8, 0, z2, x + 0.8, h - 3, z2 + 0.8)) end
  end
  for z = z1 + 16, z2 - 8, 16 do
    if not onDoor(sides.W, z) then metal(K.B(m, "Pilaster", x1 - 0.8, 0, z - 0.8, x1, h - 3, z + 0.8)) end
    if not onDoor(sides.E, z) then metal(K.B(m, "Pilaster", x2, 0, z - 0.8, x2 + 0.8, h - 3, z + 0.8)) end
  end
  -- door frames: thick charcoal surround + hazard stripes on jambs
  for side, list in pairs(sides) do
    for _, op in ipairs(list) do
      if op[3] == 0 then
        local a, b, top = op[1], op[2], op[4]
        local function fr(u1, y1, u2, y2)
          if side == "N" then return K.B(m, "DoorFrame", u1, y1, z1 - 0.9, u2, y2, z1 + T + 0.6)
          elseif side == "S" then return K.B(m, "DoorFrame", u1, y1, z2 - T - 0.6, u2, y2, z2 + 0.9)
          elseif side == "W" then return K.B(m, "DoorFrame", x1 - 0.9, y1, u1, x1 + T + 0.6, y2, u2)
          else return K.B(m, "DoorFrame", x2 - T - 0.6, y1, u1, x2 + 0.9, y2, u2) end
        end
        metal(fr(a - 1.4, 0, a, top + 1.4)); metal(fr(b, 0, b + 1.4, top + 1.4)); metal(fr(a - 1.4, top, b + 1.4, top + 1.4))
        for i = 0, 5 do
          local y = 0.4 + i * 1.2
          local c = (i % 2 == 0) and YEL or Color3.fromRGB(28, 28, 30)
          local s1, s2 = fr(a - 1.5, y, a - 1.38, y + 1.2), fr(b + 1.38, y, b + 1.5, y + 1.2)
          for _, s in ipairs({s1, s2}) do if s then s.Material = Enum.Material.SmoothPlastic; s.Color = c; deco(s) end end
        end
      end
    end
  end
  m.Parent = par -- early
  -- INTERIOR: dark wainscot, steel ribs, wall inset panels, ceiling trusses, light strips
  local inX1, inX2, inZ1, inZ2 = x1 + T, x2 - T, z1 + T, z2 - T
  local function inner(name, a1, y1, b1, a2, y2, b2, col, mat)
    local p = K.B(m, name, a1, y1, b1, a2, y2, b2, col, mat); if p then deco(p) end; return p
  end
  local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include; rp.FilterDescendantsInstances = {wf}
  local walls = {{"N", inZ1, inX1, inX2, 1}, {"S", inZ2, inX1, inX2, -1}, {"W", inX1, inZ1, inZ2, 1}, {"E", inX2, inZ1, inZ2, -1}}
  for _, w in ipairs(walls) do
    local side, v, a, b, n = w[1], w[2], w[3], w[4], w[5]
    local alongX = side == "N" or side == "S"
    local function box(u1, y1, u2, y2, d, col, mat, name)
      local p
      if alongX then p = K.B(m, name, u1, y1, math.min(v, v + n * d), u2, y2, math.max(v, v + n * d), col, mat)
      else p = K.B(m, name, math.min(v, v + n * d), y1, u1, math.max(v, v + n * d), y2, u2, col, mat) end
      return deco(p)
    end
    local function solid(u, y)
      local origin = alongX and Vector3.new(u, y, v + n * 1.5 + K.CZ) or Vector3.new(v + n * 1.5, y, u + K.CZ)
      local dir = alongX and Vector3.new(0, 0, -n * 3) or Vector3.new(-n * 3, 0, 0)
      return workspace:Raycast(origin, dir, rp) ~= nil
    end
    -- wainscot only where wall is solid at y=2
    local u = a; local runStart
    while u <= b do
      local s = solid(u, 2)
      if s and not runStart then runStart = u end
      if (not s or u + 1 > b) and runStart then
        local e = s and b or u - 1
        if e - runStart > 1 then
          local p = box(runStart, 0.4, e, 3.4, 0.3, Color3.fromRGB(70, 72, 76), Enum.Material.Metal, "Wainscot")
          box(runStart, 3.4, e, 3.8, 0.4, YEL, Enum.Material.SmoothPlastic, "WainscotCap")
        end
        runStart = nil
      end
      u += 1
    end
    -- steel ribs every 8 studs + recessed panels between
    for rib = a + 4, b - 2, 8 do
      if solid(rib, 6) and solid(rib, h - 4) then
        local p = box(rib - 0.6, 3.8, rib + 0.6, h - 0.5, 0.9, STEEL, Enum.Material.Metal, "Rib"); if p then p.CanCollide = false end
        if rib + 8 <= b and solid(rib + 4, 8) and solid(rib + 4, h - 6) then
          box(rib + 1.4, 6, rib + 6.6, h - 5, 0.15, INNER, Enum.Material.SmoothPlastic, "InsetPanel")
          box(rib + 2.6, h - 6.5, rib + 5.4, h - 6, 0.25, Color3.fromRGB(235, 242, 250), Enum.Material.Neon, "WallLight")
        end
      end
    end
  end
  -- ceiling trusses (across the short span) + light strips
  local spanX = (x2 - x1) <= (z2 - z1)
  local L1, L2 = spanX and z1 or x1, spanX and z2 or x2
  for t = L1 + 8, L2 - 6, 12 do
    local beam
    if spanX then beam = K.B(m, "Truss", inX1, h - 3, t - 0.8, inX2, h - 0.0, t + 0.8, STEEL, Enum.Material.Metal)
    else beam = K.B(m, "Truss", t - 0.8, h - 3, inZ1, t + 0.8, h - 0.0, inZ2, STEEL, Enum.Material.Metal) end
    deco(beam)
    local ls
    if spanX then ls = K.B(m, "LightStrip", inX1 + 4, h - 3.25, t - 0.3, inX2 - 4, h - 3, t + 0.3, Color3.fromRGB(240, 244, 250), Enum.Material.Neon)
    else ls = K.B(m, "LightStrip", t - 0.3, h - 3.25, inZ1 + 4, t + 0.3, h - 3, inZ2 - 4, Color3.fromRGB(240, 244, 250), Enum.Material.Neon) end
    deco(ls)
    local sl = Instance.new("SurfaceLight"); sl.Face = Enum.NormalId.Bottom; sl.Angle = 140; sl.Range = math.min(40, h + 6); sl.Brightness = 1.2; sl.Shadows = false; sl.Parent = ls
  end
  -- interior faces darker-white
  m.Parent = par
  return m
end
-- mezzanine catwalk along an inner wall: side, depth, height, with a stair
function H.mezz(par, name, x1, z1, x2, z2, y)
  local m = Instance.new("Model"); m.Name = name
  local d = K.B(m, "Deck", x1, y - 0.8, z1, x2, y, z2, STEEL, Enum.Material.DiamondPlate)
  local ed = K.B(m, "Edge", x1, y - 1.6, z1, x2, y - 0.8, z2, CHAR, Enum.Material.Metal)
  m.Parent = par
  return m
end
return H
