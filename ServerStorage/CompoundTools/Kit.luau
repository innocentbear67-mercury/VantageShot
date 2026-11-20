local K = {}
K.CZ = -60
K.C = {
  white = Color3.fromRGB(222,222,216), steel = Color3.fromRGB(58,62,68),
  yellow = Color3.fromRGB(226,178,34), dark = Color3.fromRGB(38,42,50),
  glow = Color3.fromRGB(80,190,255), floor = Color3.fromRGB(150,150,146),
}
function K.P(par, name, size, cf, col, mat)
  local p = Instance.new("Part")
  p.Name = name; p.Anchored = true; p.Size = size; p.CFrame = cf
  p.Color = col or K.C.white; p.Material = mat or Enum.Material.Concrete
  p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
  p.Parent = par
  return p
end
function K.W(x, y, z) return CFrame.new(x, y, z + K.CZ) end
function K.B(par, name, x1, y1, z1, x2, y2, z2, col, mat)
  local sx, sy, sz = math.abs(x2-x1), math.abs(y2-y1), math.abs(z2-z1)
  if sx < 0.05 or sy < 0.05 or sz < 0.05 then return end
  return K.P(par, name, Vector3.new(sx, sy, sz), K.W((x1+x2)/2, (y1+y2)/2, (z1+z2)/2), col, mat)
end
-- wall running along X at z; ops = {{a, b, bottom, top}} openings (y relative to y0)
function K.wallX(par, name, x1, x2, z, y0, h, t, ops, col, mat)
  ops = ops or {}
  table.sort(ops, function(a, b) return a[1] < b[1] end)
  local cur = x1
  for _, o in ipairs(ops) do
    if o[1] > cur then K.B(par, name, cur, y0, z-t/2, o[1], y0+h, z+t/2, col, mat) end
    if o[3] > 0 then K.B(par, name, o[1], y0, z-t/2, o[2], y0+o[3], z+t/2, col, mat) end
    if o[4] < h then K.B(par, name, o[1], y0+o[4], z-t/2, o[2], y0+h, z+t/2, col, mat) end
    cur = o[2]
  end
  if cur < x2 then K.B(par, name, cur, y0, z-t/2, x2, y0+h, z+t/2, col, mat) end
end
-- wall running along Z at x
function K.wallZ(par, name, z1, z2, x, y0, h, t, ops, col, mat)
  ops = ops or {}
  table.sort(ops, function(a, b) return a[1] < b[1] end)
  local cur = z1
  for _, o in ipairs(ops) do
    if o[1] > cur then K.B(par, name, x-t/2, y0, cur, x+t/2, y0+h, o[1], col, mat) end
    if o[3] > 0 then K.B(par, name, x-t/2, y0, o[1], x+t/2, y0+o[3], o[2], col, mat) end
    if o[4] < h then K.B(par, name, x-t/2, y0+o[4], o[1], x+t/2, y0+h, o[2], col, mat) end
    cur = o[2]
  end
  if cur < z2 then K.B(par, name, x-t/2, y0, cur, x+t/2, y0+h, z2, col, mat) end
end
-- slab (top surface at y) with an optional rectangular hole {hx1, hz1, hx2, hz2}
function K.slab(par, name, x1, z1, x2, z2, y, hole, col)
  col = col or K.C.floor
  if not hole then return K.B(par, name, x1, y-1, z1, x2, y, z2, col) end
  local hx1, hz1, hx2, hz2 = hole[1], hole[2], hole[3], hole[4]
  K.B(par, name, x1, y-1, z1, x2, y, hz1, col)
  K.B(par, name, x1, y-1, hz2, x2, y, z2, col)
  K.B(par, name, x1, y-1, hz1, hx1, y, hz2, col)
  K.B(par, name, hx2, y-1, hz1, x2, y, hz2, col)
end
-- straight ramp between two surface points (local coords), width w
function K.ramp(par, name, a, b, w, col)
  local A = Vector3.new(a.X, a.Y, a.Z + K.CZ)
  local Bv = Vector3.new(b.X, b.Y, b.Z + K.CZ)
  local len = (Bv - A).Magnitude
  local cf = CFrame.lookAt((A + Bv)/2, Bv) * CFrame.new(0, -0.5, 0)
  return K.P(par, name, Vector3.new(w, 1, len), cf, col or K.C.steel, Enum.Material.DiamondPlate)
end
-- railing strip (yellow hazard) along a segment at height y
function K.rail(par, x1, z1, x2, z2, y)
  local A = Vector3.new(x1, y + 1.75, z1 + K.CZ)
  local Bv = Vector3.new(x2, y + 1.75, z2 + K.CZ)
  local len = (Bv - A).Magnitude
  return K.P(par, "Rail", Vector3.new(0.4, 3.5, len), CFrame.lookAt((A+Bv)/2, Bv), K.C.yellow, Enum.Material.SmoothPlastic)
end
return K
