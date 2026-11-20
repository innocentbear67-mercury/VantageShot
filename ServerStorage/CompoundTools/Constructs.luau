local K = require(script.Parent.Kit)
local C = {}
C.METAL = Color3.fromRGB(184, 188, 192)
C.DARK = Color3.fromRGB(78, 82, 88)
C.TREAD = Color3.fromRGB(150, 152, 154)
C.YEL = Color3.fromRGB(222, 178, 46)
C.STEEL = Color3.fromRGB(110, 114, 120)
local VAR = {"VS_ForgedPanel", "VS_ForgedPanel1", "VS_ForgedPanel2", "VS_ForgedPanel3"}
local rng = Random.new(51)
function C.panel(p, col) if p then p.Material = Enum.Material.Metal; p.MaterialVariant = VAR[rng:NextInteger(1, 4)]; p.Color = col or C.METAL end return p end
function C.dark(p) if p then p.Material = Enum.Material.Metal; p.MaterialVariant = ""; p.Color = C.DARK end return p end
function C.slab(p) if p then p.Material = Enum.Material.Pavement; p.MaterialVariant = "VS_ConcreteSlab"; p.Color = Color3.fromRGB(176, 176, 172) end return p end
function C.stair(par, a, b, w)
  local s = K.ramp(par, "Stair", a, b, w or 5, C.TREAD); s.Material = Enum.Material.DiamondPlate; s.MaterialVariant = ""; return s
end
function C.rail(par, x1, z1, x2, z2, y)
  local A = Vector3.new(x1, y, z1 + K.CZ); local B = Vector3.new(x2, y, z2 + K.CZ)
  local L = (B - A).Magnitude; if L < 1 then return end
  local cf = CFrame.lookAt((A + B) / 2, B)
  K.P(par, "RailTop", Vector3.new(0.28, 0.28, L), cf * CFrame.new(0, 3.4, 0), C.YEL, Enum.Material.Metal).CastShadow = false
  local mid = K.P(par, "RailMid", Vector3.new(0.18, 0.18, L), cf * CFrame.new(0, 1.8, 0), C.STEEL, Enum.Material.Metal); mid.CastShadow = false; mid.CanCollide = false
  local n = math.max(1, math.floor(L / 4))
  for i = 0, n do K.P(par, "RailPost", Vector3.new(0.25, 3.5, 0.25), cf * CFrame.new(0, 1.75, -L / 2 + L * i / n), C.STEEL, Enum.Material.Metal).CastShadow = false end
  local blk = K.P(par, "RailBlocker", Vector3.new(0.4, 3.5, L), cf * CFrame.new(0, 1.75, 0), C.STEEL, Enum.Material.Metal); blk.Transparency = 1; blk.CastShadow = false
end
function C.label() end
function C._oldLabel(par, text, x, y, z, nx, nz, w)
  local pos = Vector3.new(x, y, z + K.CZ)
  local plate = K.P(par, "Label", Vector3.new(w or (#text * 1.3 + 4), 3.6, 0.3), CFrame.lookAt(pos, pos + Vector3.new(nx, 0, nz)), Color3.fromRGB(34, 36, 40), Enum.Material.Metal)
  plate.CanCollide = false
  local g = Instance.new("SurfaceGui"); g.Face = Enum.NormalId.Front; g.PixelsPerStud = 40; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.LightInfluence = 0.4; g.Parent = plate
  local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1, 0.74); t.BackgroundTransparency = 1; t.Text = text; t.TextScaled = true; t.Font = Enum.Font.GothamBlack; t.TextColor3 = Color3.fromRGB(236, 238, 240); t.Parent = g
  local s = Instance.new("Frame"); s.Size = UDim2.fromScale(1, 0.12); s.Position = UDim2.fromScale(0, 0.88); s.BorderSizePixel = 0; s.BackgroundColor3 = C.YEL; s.Parent = g
end
function C.sandbags(par, x, y, z, n, rot)
  local cf = K.W(x, y, z) * CFrame.Angles(0, math.rad(rot or 0), 0)
  for row = 0, 1 do for i = 0, n - 1 - row do
    local s = K.P(par, "Sandbag", Vector3.new(2.9, 1.1, 1.7), cf * CFrame.new((i - (n - 1) / 2) * 3 + row * 1.5, 0.55 + row * 1.05, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-5, 5)), 0), Color3.fromRGB(150, 146, 132), Enum.Material.Fabric)
    s.CastShadow = false
  end end
end
-- low cover wall (metal panel with dark cap)
function C.lowWall(par, x1, z1, x2, z2, y, h)
  h = h or 3.6
  C.panel(K.B(par, "LowWall", x1, y, z1, x2, y + h, z2))
  C.dark(K.B(par, "LowWallCap", x1 - 0.15, y + h, z1 - 0.15, x2 + 0.15, y + h + 0.4, z2 + 0.15))
end
-- shipping container (grey, yellow stripe), optional stack level
function C.container(par, x, z, rotDeg, level, tone)
  local cf = K.W(x, 0, z) * CFrame.Angles(0, math.rad(rotDeg or 0), 0) * CFrame.new(0, 4.5 + (level or 0) * 9, 0)
  local g = tone or rng:NextNumber(0.85, 1.05)
  local c = K.P(par, "Container", Vector3.new(24, 9, 9), cf, Color3.new(0.43 * g, 0.45 * g, 0.47 * g), Enum.Material.Metal)
  c.MaterialVariant = "VS_CorrugatedSteel"
  for _, s in ipairs({-1, 1}) do K.P(par, "ContainerEnd", Vector3.new(0.4, 9.2, 9.2), cf * CFrame.new(s * 12, 0, 0), C.DARK, Enum.Material.Metal).CastShadow = false end
  local st = K.P(par, "ContainerStripe", Vector3.new(24.1, 0.6, 9.1), cf * CFrame.new(0, 3.6, 0), C.YEL, Enum.Material.SmoothPlastic); st.CanCollide = false; st.CastShadow = false
  return c
end
-- raised terrace (high ground): retaining walls, slab top, ramps on two ends, low walls on top edges
function C.terrace(par, name, x1, z1, x2, z2, h, rampSides)
  local m = Instance.new("Model"); m.Name = name; m.Parent = par
  C.panel(K.B(m, "TerraceCore", x1, 0, z1, x2, h, z2))
  C.slab(K.B(m, "TerraceTop", x1, h, z1, x2, h + 0.3, z2))
  C.dark(K.B(m, "TerraceLip", x1 - 0.4, h - 1.2, z1 - 0.4, x2 + 0.4, h + 0.35, z1 + 0.6))
  C.dark(K.B(m, "TerraceLip", x1 - 0.4, h - 1.2, z2 - 0.6, x2 + 0.4, h + 0.35, z2 + 0.4))
  C.dark(K.B(m, "TerraceLip", x1 - 0.4, h - 1.2, z1, x1 + 0.6, h + 0.35, z2))
  C.dark(K.B(m, "TerraceLip", x2 - 0.6, h - 1.2, z1, x2 + 0.4, h + 0.35, z2))
  local run = h * 2.6
  local cz, cx = (z1 + z2) / 2, (x1 + x2) / 2
  for _, s in ipairs(rampSides) do
    if s == "W" then C.stair(m, Vector3.new(x1 - run, 0.2, cz), Vector3.new(x1, h + 0.3, cz), 8)
    elseif s == "E" then C.stair(m, Vector3.new(x2 + run, 0.2, cz), Vector3.new(x2, h + 0.3, cz), 8)
    elseif s == "N" then C.stair(m, Vector3.new(cx, 0.2, z1 - run), Vector3.new(cx, h + 0.3, z1), 8)
    else C.stair(m, Vector3.new(cx, 0.2, z2 + run), Vector3.new(cx, h + 0.3, z2), 8) end
  end
  return m
end
return C
