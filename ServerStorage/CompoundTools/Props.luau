local K = require(script.Parent.Kit)
local C = K.C
local P = {}
P.grey = Color3.fromRGB(92, 97, 104)
P.light = Color3.fromRGB(190, 192, 190)
P.tan = Color3.fromRGB(160, 138, 104)
P.olive = Color3.fromRGB(88, 96, 72)
P.screen = Color3.fromRGB(46, 128, 166)
-- one piece relative to a base frame (local coords origin + yaw)
local function piece(par, name, base, off, size, col, mat, collide)
  local p = K.P(par, name, size, base * CFrame.new(off), col, mat or Enum.Material.Metal)
  if collide == false then p.CanCollide = false end
  if size.Magnitude < 6 then p.CastShadow = false end
  return p
end
P.piece = piece
function P.base(x, y, z, rot) return K.W(x, y, z) * CFrame.Angles(0, math.rad(rot or 0), 0) end
function P.desk(par, x, y, z, rot, screens)
  local b = P.base(x, y, z, rot)
  piece(par, "DeskTop", b, Vector3.new(0, 3, 0), Vector3.new(6, 0.3, 3), P.light)
  piece(par, "DeskSide", b, Vector3.new(-2.8, 1.45, 0), Vector3.new(0.3, 2.9, 2.8), P.grey)
  piece(par, "DeskSide", b, Vector3.new(2.8, 1.45, 0), Vector3.new(0.3, 2.9, 2.8), P.grey)
  for i = 1, (screens or 1) do
    local sx = (screens == 2) and (i == 1 and -1.3 or 1.3) or 0
    piece(par, "Monitor", b, Vector3.new(sx, 4.1, 0.9), Vector3.new(2.2, 1.4, 0.2), C.dark, Enum.Material.SmoothPlastic, false)
    piece(par, "Screen", b, Vector3.new(sx, 4.1, 0.78), Vector3.new(1.9, 1.1, 0.05), P.screen, Enum.Material.Neon, false)
  end
  piece(par, "Chair", b, Vector3.new(0, 1.4, -2.2), Vector3.new(1.8, 0.3, 1.8), C.dark, Enum.Material.Fabric, false)
  piece(par, "ChairBack", b, Vector3.new(0, 2.6, -3.0), Vector3.new(1.8, 2.2, 0.3), C.dark, Enum.Material.Fabric, false)
end
function P.rack(par, x, y, z, rot)   -- server / equipment rack
  local b = P.base(x, y, z, rot)
  piece(par, "Rack", b, Vector3.new(0, 3.5, 0), Vector3.new(3, 7, 2.5), C.dark)
  for h = 1.5, 6, 1.1 do piece(par, "RackLight", b, Vector3.new(0.8, h, -1.27), Vector3.new(0.6, 0.15, 0.05), P.screen, Enum.Material.Neon, false) end
end
function P.lockers(par, x, y, z, rot, n, col)
  local b = P.base(x, y, z, rot)
  for i = 0, (n or 4) - 1 do
    local ox = (i - ((n or 4) - 1) / 2) * 2.1
    piece(par, "Locker", b, Vector3.new(ox, 3.5, 0), Vector3.new(2, 7, 2), col or P.grey)
    piece(par, "LockerVent", b, Vector3.new(ox, 6, -1.02), Vector3.new(1.2, 0.6, 0.05), C.dark, Enum.Material.Metal, false)
  end
end
function P.bench(par, x, y, z, rot, len)
  local b = P.base(x, y, z, rot)
  piece(par, "Bench", b, Vector3.new(0, 1.6, 0), Vector3.new(len or 8, 0.4, 1.6), P.tan, Enum.Material.WoodPlanks)
  piece(par, "BenchLeg", b, Vector3.new(-(len or 8)/2 + 0.6, 0.7, 0), Vector3.new(0.4, 1.4, 1.4), C.steel)
  piece(par, "BenchLeg", b, Vector3.new((len or 8)/2 - 0.6, 0.7, 0), Vector3.new(0.4, 1.4, 1.4), C.steel)
end
function P.table(par, x, y, z, rot, w, d)
  local b = P.base(x, y, z, rot)
  piece(par, "Table", b, Vector3.new(0, 3, 0), Vector3.new(w or 10, 0.4, d or 4), P.light)
  piece(par, "TableBase", b, Vector3.new(0, 1.4, 0), Vector3.new((w or 10) - 2, 2.8, 0.6), P.grey)
end
function P.crates(par, x, y, z, rot, n)
  local b = P.base(x, y, z, rot)
  for i = 0, (n or 2) - 1 do
    piece(par, "Crate", b, Vector3.new(i * 4.2, 2, 0), Vector3.new(4, 4, 4), P.olive, Enum.Material.Metal)
    piece(par, "CrateBand", b, Vector3.new(i * 4.2, 2, -2.02), Vector3.new(4, 0.5, 0.05), C.yellow, Enum.Material.SmoothPlastic, false)
  end
end
function P.drum(par, x, y, z, col)
  local d = K.P(par, "Drum", Vector3.new(4, 2.6, 2.6), K.W(x, y + 2, z) * CFrame.Angles(0, 0, math.rad(90)), col or Color3.fromRGB(70, 92, 120), Enum.Material.Metal)
  d.Shape = Enum.PartType.Cylinder; d.CastShadow = false
end
function P.weaponRack(par, x, y, z, rot)
  local b = P.base(x, y, z, rot)
  piece(par, "WRack", b, Vector3.new(0, 3, 0), Vector3.new(6, 6, 1), C.dark)
  for i = -2, 2 do piece(par, "WRackSlot", b, Vector3.new(i * 1.1, 3.4, -0.55), Vector3.new(0.3, 4, 0.2), P.grey, Enum.Material.Metal, false) end
end
function P.pipe(par, a, b, d, col)  -- straight pipe between two local points
  local A = Vector3.new(a.X, a.Y, a.Z + K.CZ); local B = Vector3.new(b.X, b.Y, b.Z + K.CZ)
  local p = K.P(par, "Pipe", Vector3.new((B - A).Magnitude, d, d), CFrame.lookAt((A + B)/2, B) * CFrame.Angles(0, math.rad(90), 0), col or C.steel, Enum.Material.Metal)
  p.Shape = Enum.PartType.Cylinder
  return p
end
return P
