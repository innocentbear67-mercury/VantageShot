local K = require(script.Parent.Kit)
local A = {}
A.WHITE = Color3.fromRGB(236, 236, 232)
A.JOINT = Color3.fromRGB(150, 150, 146)
A.TRIM = Color3.fromRGB(108, 112, 118)
A.DARK = Color3.fromRGB(40, 42, 46)
A.YELLOW = Color3.fromRGB(230, 182, 40)
local VAR = {"VS_WhitePrecast", "VS_WhitePrecast1", "VS_WhitePrecast2", "VS_WhitePrecast3"}
local rng = Random.new(42)
local function fin(p, collide) p.CastShadow = p.Size.Magnitude > 8; if collide == false then p.CanCollide = false; p.CanQuery = false end return p end
function A.trim(par, name, x1, y1, z1, x2, y2, z2)
  local p = K.B(par, name, x1, y1, z1, x2, y2, z2, A.TRIM, Enum.Material.Metal); if p then p.MaterialVariant = "VS_PaintedSteel" end; return p
end
-- solid massing block with dressed faces.
-- opts.faces = {"N","S","E","W"} faces to dress; opts.bands = {{y0,y1},...}; opts.slits = true; opts.cornice = h; opts.walkRoof = true (parapet)
function A.block(par, name, x1, z1, x2, z2, h, opts)
  opts = opts or {}
  local y0 = opts.y0 or 0
  local m = Instance.new("Model"); m.Name = name
  local core = K.B(m, "Core", x1, y0, z1, x2, y0 + h, z2, A.JOINT, Enum.Material.Concrete)
  core.MaterialVariant = "VS_WhitePrecast"
  local faces = opts.faces or {"N", "S", "E", "W"}
  local bands = opts.bands or {}
  if #bands == 0 then
    local nb = math.max(1, math.floor((h - 2) / 9 + 0.5))
    local bh = (h - 3) / nb
    for i = 0, nb - 1 do bands[#bands + 1] = {y0 + 1.5 + i * bh, y0 + 1.5 + (i + 1) * bh} end
  end
  local PW, GAP, T = opts.panel or 7, 0.35, 0.25
  for _, f in ipairs(faces) do
    local axis, v, a, b, n
    if f == "N" then axis, v, a, b, n = "z", z1, x1, x2, -1 elseif f == "S" then axis, v, a, b, n = "z", z2, x1, x2, 1
    elseif f == "W" then axis, v, a, b, n = "x", x1, z1, z2, -1 else axis, v, a, b, n = "x", x2, z1, z2, 1 end
    local function C3(u, y, off) if axis == "z" then return CFrame.new(u, y, v + n * off + K.CZ) else return CFrame.new(v + n * off, y, u + K.CZ) end end
    local function sz(w, hh, d) if axis == "z" then return Vector3.new(w, hh, d) else return Vector3.new(d, hh, w) end end
    for bi, band in ipairs(bands) do
      local u = a + 0.6
      while u < b - 0.6 - 0.5 do
        local w = math.min(PW, b - 0.6 - u)
        local tone = rng:NextNumber(-0.03, 0.02)
        local p = K.P(m, "Panel", sz(w - GAP, band[2] - band[1] - GAP, T), C3(u + w / 2, (band[1] + band[2]) / 2, T / 2), Color3.new(0.925 + tone, 0.925 + tone, 0.91 + tone), Enum.Material.Concrete)
        p.MaterialVariant = VAR[rng:NextInteger(1, 4)]; fin(p)
        if opts.slits ~= false and w > 4 and rng:NextNumber() < (opts.slitChance or 0.55) then
          local sy = band[2] - 2.4
          local s = K.P(m, "Slit", sz(1.1, 1.8, 0.1), C3(u + w / 2 + rng:NextNumber(-1.2, 1.2), sy, T + 0.04), A.DARK, Enum.Material.SmoothPlastic); fin(s, false)
        end
        if rng:NextNumber() < 0.3 then
          local gh = rng:NextNumber(2.5, 5.5)
          local g = K.P(m, "Grime", sz(rng:NextNumber(0.6, 1.4), gh, 0.05), C3(u + rng:NextNumber(1, w - 1), band[2] - gh / 2 - 0.3, T + 0.03), Color3.fromRGB(80, 76, 68), Enum.Material.SmoothPlastic)
          g.Transparency = 0.84; fin(g, false)
        end
        u += w
      end
    end
    -- base plinth + baked shade
    local len = b - a
    local pl = K.P(m, "Plinth", sz(len + 0.6, 1.5, 0.6), C3((a + b) / 2, y0 + 0.75, 0.3), A.TRIM, Enum.Material.Metal); pl.MaterialVariant = "VS_PaintedSteel"; fin(pl)
    local sh = K.P(m, "BakedShade", sz(len, 2.6, 0.05), C3((a + b) / 2, y0 + 2.8, T + 0.06), Color3.fromRGB(50, 46, 40), Enum.Material.SmoothPlastic)
    sh.Transparency = 0.82; fin(sh, false)
  end
  -- cornice: steel band plus an angled wedge capping it
  local ch = opts.cornice or 2.5
  local top = y0 + h
  local o = 0.8
  A.trim(m, "Cornice", x1 - o, top - ch, z1 - o, x2 + o, top, z1 + 0.6)
  A.trim(m, "Cornice", x1 - o, top - ch, z2 - 0.6, x2 + o, top, z2 + o)
  A.trim(m, "Cornice", x1 - o, top - ch, z1, x1 + 0.6, top, z2)
  A.trim(m, "Cornice", x2 - 0.6, top - ch, z1, x2 + o, top, z2)
  if opts.walkRoof then
    local rf = K.B(m, "Roof", x1, top, z1, x2, top + 0.2, z2, Color3.fromRGB(160, 160, 156), Enum.Material.Pavement); rf.MaterialVariant = "VS_ConcreteSlab"
    for _, s in ipairs({{x1, z1, x2, z1 + 1.2}, {x1, z2 - 1.2, x2, z2}, {x1, z1, x1 + 1.2, z2}, {x2 - 1.2, z1, x2, z2}}) do
      local skip = false
      for _, g in ipairs(opts.parapetGaps or {}) do if g[1] < s[3] and g[3] > s[1] and g[2] < s[4] and g[4] > s[2] then skip = true end end
      if not skip then local p = K.B(m, "Parapet", s[1], top, s[2], s[3], top + 3.2, s[4], A.WHITE, Enum.Material.Concrete); p.MaterialVariant = "VS_WhitePrecast" end
    end
  end
  m.Parent = par
  return m
end
-- open walkway deck on columns with thin yellow rails (rails on the listed sides)
function A.deck(par, name, x1, z1, x2, z2, y, opts)
  opts = opts or {}
  local m = Instance.new("Model"); m.Name = name
  local d = K.B(m, "Deck", x1, y - 0.8, z1, x2, y, z2, A.TRIM, Enum.Material.DiamondPlate); d.MaterialVariant = "VS_TreadPlate"
  K.B(m, "DeckEdge", x1, y - 1.6, z1, x2, y - 0.8, z1 + 0.5, A.TRIM, Enum.Material.Metal)
  K.B(m, "DeckEdge", x1, y - 1.6, z2 - 0.5, x2, y - 0.8, z2, A.TRIM, Enum.Material.Metal)
  if not opts.noColumns then
    local sx = math.max(1, math.floor((x2 - x1) / 18)); local szn = math.max(1, math.floor((z2 - z1) / 18))
    for i = 0, sx do for j = 0, szn do
      local cx = x1 + 1 + (x2 - x1 - 2) * (i / sx); local cz = z1 + 1 + (z2 - z1 - 2) * (j / szn)
      local c = K.B(m, "Column", cx - 0.9, 0, cz - 0.9, cx + 0.9, y - 1.6, cz + 0.9, A.WHITE, Enum.Material.Concrete); c.MaterialVariant = "VS_WhitePrecast"
    end end
  end
  for _, s in ipairs(opts.rails or {}) do
    local r = s == "N" and {x1, z1 + 0.2, x2, z1 + 0.2} or s == "S" and {x1, z2 - 0.2, x2, z2 - 0.2} or s == "W" and {x1 + 0.2, z1, x1 + 0.2, z2} or {x2 - 0.2, z1, x2 - 0.2, z2}
    K.rail(m, r[1], r[2], r[3], r[4], y)
  end
  m.Parent = par
  return m
end
-- straight stair with thin yellow side rails
function A.stair(par, name, a, b, w)
  local m = Instance.new("Model"); m.Name = name
  local r = K.ramp(m, "Stair", a, b, w, A.TRIM); r.MaterialVariant = "VS_TreadPlate"
  local dir = (b - a).Unit; local side = Vector3.new(-dir.Z, 0, dir.X) * (w / 2)
  for _, off in ipairs({side, -side}) do
    local A2 = Vector3.new(a.X + off.X, a.Y + 1.75, a.Z + off.Z + K.CZ); local B2 = Vector3.new(b.X + off.X, b.Y + 1.75, b.Z + off.Z + K.CZ)
    K.P(m, "Rail", Vector3.new(0.3, 3.5, (B2 - A2).Magnitude), CFrame.lookAt((A2 + B2) / 2, B2), A.YELLOW, Enum.Material.Metal)
  end
  m.Parent = par
  return m
end
return A
