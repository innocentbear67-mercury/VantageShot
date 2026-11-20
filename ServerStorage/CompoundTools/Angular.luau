local K = require(script.Parent.Kit)
local A = {}
local METAL = Color3.fromRGB(128, 132, 136)
local DARK = Color3.fromRGB(70, 74, 80)
local LIGHT = Color3.fromRGB(210, 235, 255)
local hi
local function wedge(par, name, size, cf, col)
  local w = Instance.new("WedgePart"); w.Name = name; w.Anchored = true; w.Size = size; w.CFrame = cf
  w.Color = col or METAL; w.Material = Enum.Material.Metal; w.MaterialVariant = A.variant or ""
  w.TopSurface = Enum.SurfaceType.Smooth; w.BottomSurface = Enum.SurfaceType.Smooth; w.Parent = par; return w
end
local function hiSign()
  if hi then return hi end
  local w = wedge(workspace, "_probe", Vector3.new(4, 10, 10), CFrame.new(0, 3000, 0))
  local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include; rp.FilterDescendantsInstances = {w}
  local a = workspace:Raycast(Vector3.new(0, 3100, 4), Vector3.new(0, -200, 0), rp)
  local b = workspace:Raycast(Vector3.new(0, 3100, -4), Vector3.new(0, -200, 0), rp)
  hi = ((a and a.Position.Y or 0) > (b and b.Position.Y or 0)) and 1 or -1
  w:Destroy(); return hi
end
-- wedge along an edge: centre point (local), length along edge axis, 'inward' unit vector (high side toward it)
local function edgeWedge(par, name, cx, cy, cz, len, h, d, inward, col)
  local pos = K.W(cx, cy, cz).Position
  local look = pos - inward * hiSign()
  local w = wedge(par, name, Vector3.new(len, h, d), CFrame.lookAt(pos, look), col)
  return w
end
local function nearDoor(list, u, r) for _, c in ipairs(list) do if math.abs(u - c) < r then return true end end return false end
-- b = {x1,z1,x2,z2, base, top, doors={N={},S={},W={},E={}}, crown=bool, skirt=bool, blades=bool}
function A.apply(par, b, rng)
  local g = Instance.new("Model"); g.Name = "Angular"; g.Parent = par
  local x1, z1, x2, z2, y0, top = b.x1, b.z1, b.x2, b.z2, b.base, b.top
  local h = top - y0
  local faces = {
    {side = "N", axis = "x", a = x1, c = x2, fixed = z1 - 0.6, inward = Vector3.new(0, 0, 1)},
    {side = "S", axis = "x", a = x1, c = x2, fixed = z2 + 0.6, inward = Vector3.new(0, 0, -1)},
    {side = "W", axis = "z", a = z1, c = z2, fixed = x1 - 0.6, inward = Vector3.new(1, 0, 0)},
    {side = "E", axis = "z", a = z1, c = z2, fixed = x2 + 0.6, inward = Vector3.new(-1, 0, 0)},
  }
  for _, f in ipairs(faces) do
    local L = f.c - f.a
    local mid = (f.a + f.c) / 2
    -- 1) chamfered crown: sloped band rising inward above the roof edge
    if b.crown then
      local d, ch = 6, 6
      local off = -f.inward * 0 + f.inward * (d / 2)
      local cx = f.axis == "x" and mid or (f.fixed + off.X)
      local cz = f.axis == "x" and (f.fixed + off.Z) or mid
      edgeWedge(g, "Crown", cx, top + 3.5 + ch / 2, cz, L + 1.2, ch, d, f.inward, DARK)
      local ls = K.B(g, "CrownLight", 0, 0, 0, 1, 1, 1, LIGHT, Enum.Material.Neon)
      ls.Size = f.axis == "x" and Vector3.new(L - 4, 0.25, 0.25) or Vector3.new(0.25, 0.25, L - 4)
      ls.CFrame = K.W(f.axis == "x" and mid or f.fixed - f.inward.X * 0.05, top + 3.2, f.axis == "x" and f.fixed - f.inward.Z * 0.05 or mid)
      ls.CanCollide = false; ls.CanQuery = false; ls.CastShadow = false
    end
    -- 2) battered skirt between doors
    if b.skirt then
      local sh = math.min(10, h * 0.35)
      local list = b.doors[f.side] or {}
      local u = f.a + 1
      while u < f.c - 1 do
        local e = u
        while e < f.c - 1 and not nearDoor(list, e + 0.5, 7) do e += 1 end
        if e - u > 6 then
          local cm = (u + e) / 2
          local d = 2.2
          local cx = f.axis == "x" and cm or (f.fixed - f.inward.X * (d / 2 - 0.6))
          local cz = f.axis == "x" and (f.fixed - f.inward.Z * (d / 2 - 0.6)) or cm
          edgeWedge(g, "Skirt", cx, y0 + sh / 2, cz, e - u, sh, d, f.inward, METAL)
        end
        u = e + 1
        while u < f.c - 1 and nearDoor(list, u + 0.5, 7) do u += 1 end
      end
    end
  end
  -- 3) leaning blades at two diagonal corners
  if b.blades then
    local corners = {{x1, z1, -1, -1}, {x2, z2, 1, 1}}
    if rng:NextNumber() < 0.5 then corners = {{x2, z1, 1, -1}, {x1, z2, -1, 1}} end
    for _, c in ipairs(corners) do
      local bh = h + 14
      local out = Vector3.new(c[3], 0, c[4]).Unit
      local base = K.W(c[1] + c[3] * 1.2, y0 + bh / 2 - 1, c[2] + c[4] * 1.2)
      local yaw = math.atan2(out.X, out.Z)
      local cf = CFrame.new(base.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-9), 0, 0)
      local blade = K.P(g, "Blade", Vector3.new(9, bh, 3), cf, DARK, Enum.Material.Metal)
      blade.MaterialVariant = A.variant or ""
      local edge = K.P(g, "BladeLight", Vector3.new(0.3, bh - 6, 0.3), cf * CFrame.new(4.4, 0, -1.55), LIGHT, Enum.Material.Neon)
      edge.CanCollide = false; edge.CanQuery = false; edge.CastShadow = false
      local cap = K.P(g, "BladeCap", Vector3.new(9.4, 1.2, 3.4), cf * CFrame.new(0, bh / 2, 0), METAL, Enum.Material.Metal)
    end
  end
  return g
end
return A
