return function(H, K, MS)
  local old = MS:FindFirstChild("BlueHalls"); if old then old:Destroy() end
  local BH = Instance.new("Model"); BH.Name = "BlueHalls"; BH.Parent = MS
  local Y = 13
  local STEEL = Color3.fromRGB(92, 96, 102)
  local CHAR = Color3.fromRGB(60, 61, 63)
  local YEL = Color3.fromRGB(222, 178, 46)
  H.build(BH, "Hangar", -230, 100, -198, 176, 48, {{"N", -214, 12, 16}, {"S", -214, 12, 16}, {"E", 158, 12, 16}, {"E", 122, 8, 8, Y}})
  H.build(BH, "SpawnHall", -186, 108, -134, 160, 46, {{"N", -160, 12, 14}, {"S", -160, 10, 14}, {"W", 140, 10, 14}, {"E", 146, 10, 14}, {"W", 122, 8, 8, Y}, {"E", 116, 8, 8, Y}})
  H.build(BH, "Passage", -124, 100, -110, 176, 40, {{"N", -117, 8, 12}, {"S", -117, 8, 12}, {"W", 158, 8, 12}, {"E", 140, 8, 12}, {"W", 116, 8, 8, Y}})
  H.build(BH, "SouthBlock", -230, 188, -142, 230, 44, {{"N", -214, 12, 14}, {"N", -160, 12, 14}, {"E", 210, 10, 14}})
  H.build(BH, "Tower", -130, 188, -110, 230, 62, {{"N", -120, 8, 12}, {"W", 210, 8, 12}})
  local function deck(par, x1, z1, x2, z2, y)
    K.B(par, "Mezzanine", x1, y - 0.8, z1, x2, y, z2, STEEL, Enum.Material.DiamondPlate)
    H.metal(K.B(par, "MezzEdge", x1, y - 1.8, z1, x2, y - 0.8, z2), CHAR)
  end
  local function stair(par, ax, ay, az, bx, by, bz, w)
    local r = K.ramp(par, "Stair", Vector3.new(ax, ay, az), Vector3.new(bx, by, bz), w, Color3.fromRGB(150, 152, 154))
    r.Material = Enum.Material.DiamondPlate; r.MaterialVariant = ""
  end
  local function rail(par, x1, z1, x2, z2, y)
    local A = Vector3.new(x1, y, z1 + K.CZ); local B = Vector3.new(x2, y, z2 + K.CZ)
    local L = (B - A).Magnitude; local cf = CFrame.lookAt((A + B) / 2, B)
    local t = K.P(par, "RailTop", Vector3.new(0.28, 0.28, L), cf * CFrame.new(0, 3.4, 0), YEL, Enum.Material.Metal); t.CastShadow = false
    local m = K.P(par, "RailMid", Vector3.new(0.18, 0.18, L), cf * CFrame.new(0, 1.8, 0), STEEL, Enum.Material.Metal); m.CastShadow = false; m.CanCollide = false
    for i = 0, math.max(1, math.floor(L / 4)) do
      local p = K.P(par, "RailPost", Vector3.new(0.25, 3.5, 0.25), cf * CFrame.new(0, 1.75, -L / 2 + L * i / math.max(1, math.floor(L / 4))), STEEL, Enum.Material.Metal); p.CastShadow = false
    end
    local blk = K.P(par, "RailBlocker", Vector3.new(0.4, 3.5, L), cf * CFrame.new(0, 1.75, 0), STEEL, Enum.Material.Metal); blk.Transparency = 1; blk.CastShadow = false
  end
  local sh = BH.SpawnHall
  deck(sh, -184, 110, -177, 128, Y); deck(sh, -184, 110, -136, 116, Y); deck(sh, -143, 110, -136, 128, Y)
  rail(sh, -177, 116, -177, 128, Y); rail(sh, -177, 116, -143, 116, Y); rail(sh, -143, 116, -143, 128, Y)
  stair(sh, -182.5, 0.4, 152, -182.5, Y, 128.5, 3)
  stair(sh, -137.5, 0.4, 152, -137.5, Y, 128.5, 3)
  local hg = BH.Hangar
  deck(hg, -207, 112, -200, 170, Y); rail(hg, -207, 112, -207, 170, Y)
  stair(hg, -226, 0.4, 170, -208, Y, 170, 5)
  local pg = BH.Passage
  deck(pg, -122, 102, -117, 174, Y); rail(pg, -117, 102, -117, 148, Y)
  stair(pg, -114, 0.4, 172, -114, Y, 150, 4)
  local function bridge(x1, z1, x2, z2)
    K.B(BH, "Bridge", x1, Y - 0.8, z1, x2, Y, z2, STEEL, Enum.Material.DiamondPlate)
    H.metal(K.B(BH, "BridgeEdge", x1, Y - 1.8, z1, x2, Y - 0.8, z2), CHAR)
    if (x2 - x1) > (z2 - z1) then rail(BH, x1, z1 + 0.2, x2, z1 + 0.2, Y); rail(BH, x1, z2 - 0.2, x2, z2 - 0.2, Y)
    else rail(BH, x1 + 0.2, z1, x1 + 0.2, z2, Y); rail(BH, x2 - 0.2, z1, x2 - 0.2, z2, Y) end
  end
  bridge(-200, 118, -184, 126)
  bridge(-136, 112, -122, 120)
  -- concrete paving in the alleys and the north lane
  local PAVE = Color3.fromRGB(190, 188, 184)
  local function pave(x1, z1, x2, z2)
    local p = K.B(BH, "AlleyPave", x1, -0.2, z1, x2, 0.25, z2, PAVE, Enum.Material.Pavement); p.MaterialVariant = "VS_ConcreteSlab"; p.CastShadow = false
  end
  pave(-198, 100, -186, 186); pave(-134, 100, -124, 186); pave(-232, 176, -110, 188); pave(-232, 86, -110, 100); pave(-186, 100, -134, 108); pave(-186, 160, -134, 176); pave(-142, 188, -130, 232)
  -- yellow lane markings in the alleys
  for z = 104, 180, 7 do
    local m1 = K.B(BH, "LaneMark", -192.3, 0.25, z, -191.7, 0.33, z + 3.5, YEL, Enum.Material.SmoothPlastic); m1.CanCollide = false; m1.CastShadow = false
  end
  return BH
end
