return function(H, K, par, b, ups)
  local E = 229
  local doors = {}
  local function sideDoors(side, a1, a2, edge)
    if edge then return end
    local L = a2 - a1
    if L > 50 then table.insert(doors, {side, a1 + L / 3, 10, 11}); table.insert(doors, {side, a1 + 2 * L / 3, 10, 11})
    else table.insert(doors, {side, (a1 + a2) / 2, 10, 11}) end
  end
  sideDoors("N", b.x1, b.x2, b.z1 <= -E)
  sideDoors("S", b.x1, b.x2, b.z2 >= E)
  sideDoors("W", b.z1, b.z2, b.x1 <= -E)
  sideDoors("E", b.z1, b.z2, b.x2 >= E)
  -- keep upper doors away from ground doors overlap issues: upper doors are at y13+, fine
  for _, u in ipairs(ups or {}) do table.insert(doors, {u[1], u[2], 8, 8, 13}) end
  local mdl = H.build(par, b.name, b.x1, b.z1, b.x2, b.z2, b.h, doors)
  local STEEL = Color3.fromRGB(92, 96, 102)
  local CHAR = Color3.fromRGB(60, 61, 63)
  local Y = 13
  -- mezzanine + stair for each upper door side
  for _, u in ipairs(ups or {}) do
    local side, c = u[1], u[2]
    local dx1, dz1, dx2, dz2, sa, sb
    if side == "N" then dx1, dz1, dx2, dz2 = b.x1 + 2, b.z1 + 2, b.x2 - 2, b.z1 + 8
      local sx = (c + 10 < b.x2 - 4) and c + 10 or c - 10
      sa = Vector3.new(sx, Y, b.z1 + 8.5); sb = Vector3.new(sx, 0.4, b.z1 + 30)
    elseif side == "S" then dx1, dz1, dx2, dz2 = b.x1 + 2, b.z2 - 8, b.x2 - 2, b.z2 - 2
      local sx = (c + 10 < b.x2 - 4) and c + 10 or c - 10
      sa = Vector3.new(sx, Y, b.z2 - 8.5); sb = Vector3.new(sx, 0.4, b.z2 - 30)
    elseif side == "W" then dx1, dz1, dx2, dz2 = b.x1 + 2, b.z1 + 2, b.x1 + 8, b.z2 - 2
      local sz = (c + 10 < b.z2 - 4) and c + 10 or c - 10
      sa = Vector3.new(b.x1 + 8.5, Y, sz); sb = Vector3.new(b.x1 + 30, 0.4, sz)
    else dx1, dz1, dx2, dz2 = b.x2 - 8, b.z1 + 2, b.x2 - 2, b.z2 - 2
      local sz = (c + 10 < b.z2 - 4) and c + 10 or c - 10
      sa = Vector3.new(b.x2 - 8.5, Y, sz); sb = Vector3.new(b.x2 - 30, 0.4, sz)
    end
    K.B(mdl, "Mezzanine", dx1, Y - 0.8, dz1, dx2, Y, dz2, STEEL, Enum.Material.DiamondPlate)
    H.metal(K.B(mdl, "MezzEdge", dx1, Y - 1.8, dz1, dx2, Y - 0.8, dz2), CHAR)
    local st = K.ramp(mdl, "Stair", sb, sa, 4, Color3.fromRGB(150, 152, 154)); st.Material = Enum.Material.DiamondPlate; st.MaterialVariant = ""
  end
  return mdl
end
