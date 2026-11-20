local K = require(script.Parent.Kit)
local M = {}
M.C = 24      -- cell size
M.FH = 13     -- storey height
local WHITE = Color3.fromRGB(238, 238, 234)
local INNER = Color3.fromRGB(226, 225, 220)
local CHAR = Color3.fromRGB(56, 59, 64)
local FLOOR = Color3.fromRGB(166, 166, 162)
local ROOF = Color3.fromRGB(205, 205, 200)
local VAR = {"VS_WhitePrecast", "VS_WhitePrecast1", "VS_WhitePrecast2", "VS_WhitePrecast3"}
M.colors = {WHITE = WHITE, CHAR = CHAR}

local function parse(code)
  if not code or code == "C" then return nil end
  local c = {code = code}
  c.stair = code:sub(1, 1) == "S" and code ~= "SP"
  c.spawn = code == "SP"
  c.hangar = code:find("H") ~= nil or c.spawn
  c.kind = c.spawn and "SP" or (c.hangar and "H" or "N")
  c.storeys = tonumber(code:match("%d")) or 3
  return c
end
M.parse = parse

-- grid[j][i] = code; origin = local x,z of the NW corner of cell (1,1)
-- opts.openN / openE / openS / openW: ground doors on that outer edge
function M.build(par, name, grid, X0, Z0, opts)
  opts = opts or {}
  local C, FH = M.C, M.FH
  local root = Instance.new("Model"); root.Name = name
  local rng = Random.new(opts.seed or 1)
  local fWalls = Instance.new("Model"); fWalls.Name = "Walls"; fWalls.Parent = root
  local fFloors = Instance.new("Model"); fFloors.Name = "Floors"; fFloors.Parent = root
  local fTrim = Instance.new("Model"); fTrim.Name = "Trim"; fTrim.Parent = root
  local fStairs = Instance.new("Model"); fStairs.Name = "Stairs"; fStairs.Parent = root
  local fLights = Instance.new("Model"); fLights.Name = "Lights"; fLights.Parent = root
  local rows = #grid; local cols = #grid[1]
  local cells = {}
  for j = 1, rows do cells[j] = {}; for i = 1, cols do cells[j][i] = parse(grid[j][i]) end end
  local function at(i, j) return cells[j] and cells[j][i] end
  local function inGrid(i, j) return i >= 1 and i <= cols and j >= 1 and j <= rows end
  local function paint(p, inner)
    if not p then return end
    p.Material = Enum.Material.Concrete
    p.MaterialVariant = VAR[rng:NextInteger(1, 4)]
    p.Color = inner and INNER or WHITE
  end
  local function charcoal(p) if p then p.Material = Enum.Material.Metal; p.MaterialVariant = ""; p.Color = CHAR; p.CastShadow = p.Size.Magnitude > 6 end end

  -- wall along a side of cell (i,j) at level k with openings
  local function wall(i, j, side, k, t, ops, inner)
    local x0, z0 = X0 + (i - 1) * C, Z0 + (j - 1) * C
    local y0 = k * FH
    local parts = {}
    local before = #fWalls:GetChildren()
    if side == "N" then K.wallX(fWalls, "Wall", x0 - t / 2, x0 + C + t / 2, z0, y0, FH, t, ops)
    elseif side == "S" then K.wallX(fWalls, "Wall", x0 - t / 2, x0 + C + t / 2, z0 + C, y0, FH, t, ops)
    elseif side == "W" then K.wallZ(fWalls, "Wall", z0, z0 + C, x0, y0, FH, t, ops)
    else K.wallZ(fWalls, "Wall", z0, z0 + C, x0 + C, y0, FH, t, ops) end
    local kids = fWalls:GetChildren()
    for n = before + 1, #kids do paint(kids[n], inner) end
  end
  -- opening helpers (u measured along the wall from its start)
  local function door(centre, w, h) return {centre - w / 2, centre + w / 2, 0, h} end
  local function windows(a) return {{a + 4, a + 8, 4.5, 8}, {a + C - 8, a + C - 4, 4.5, 8}} end

  local dirs = {N = {0, -1}, S = {0, 1}, W = {-1, 0}, E = {1, 0}}
  for j = 1, rows do for i = 1, cols do
    local c = at(i, j)
    if c then
      local x0, z0 = X0 + (i - 1) * C, Z0 + (j - 1) * C
      local cx, cz = x0 + C / 2, z0 + C / 2
      -- ground slab
      local g = K.B(fFloors, "Floor", x0, 0, z0, x0 + C, 0.4, z0 + C, FLOOR, Enum.Material.Pavement); g.MaterialVariant = "VS_ConcreteSlab"
      -- upper slabs
      for k = 1, c.storeys do
        if not (c.hangar and k == 1) then
          local y = k * FH
          local isRoof = k == c.storeys
          local hole
          if c.stair then
            local r = k - 1
            if r % 2 == 0 then hole = {x0 + 0.5, cz - 10, x0 + 6.5, cz + 1.5} else hole = {x0 + 5.5, cz - 1.5, x0 + 11.5, cz + 10} end
          end
          local before = #fFloors:GetChildren()
          K.slab(fFloors, isRoof and "Roof" or "Floor", x0, z0, x0 + C, z0 + C, y, hole, isRoof and ROOF or FLOOR)
          for _, p in ipairs(fFloors:GetChildren()) do end
          local kids = fFloors:GetChildren()
          for n = before + 1, #kids do kids[n].Material = Enum.Material.Pavement; kids[n].MaterialVariant = "VS_ConcreteSlab" end
        end
      end
      -- switchback stairs
      if c.stair then
        for r = 0, c.storeys - 1 do
          local a, b
          if r % 2 == 0 then a = Vector3.new(x0 + 3.5, r * FH + (r == 0 and 0.4 or 0), cz + 10); b = Vector3.new(x0 + 3.5, (r + 1) * FH, cz - 10)
          else a = Vector3.new(x0 + 8.5, r * FH, cz - 10); b = Vector3.new(x0 + 8.5, (r + 1) * FH, cz + 10) end
          local st = K.ramp(fStairs, "Stair", a, b, 5, Color3.fromRGB(150, 152, 154)); st.MaterialVariant = ""
          -- yellow handrail on the open side of each flight
          local railX = (r % 2 == 0) and (x0 + 6.1) or (x0 + 11.1)
          local A2 = Vector3.new(railX, a.Y + 3.2, a.Z + K.CZ); local B2 = Vector3.new(railX, b.Y + 3.2, b.Z + K.CZ)
          local hr = K.P(fStairs, "RailTop", Vector3.new(0.25, 0.25, (B2 - A2).Magnitude), CFrame.lookAt((A2 + B2) / 2, B2), Color3.fromRGB(230, 182, 40), Enum.Material.Metal)
          hr.CanCollide = false; hr.CastShadow = false
        end
      end
      -- walls per side per level
      for side, d in pairs(dirs) do
        local ni, nj = i + d[1], j + d[2]
        local n = at(ni, nj)
        local alongX = (side == "N" or side == "S")
        local base = alongX and x0 or z0
        for k = 0, c.storeys - 1 do
          local shared = n and k < n.storeys
          if shared then
            if side == "E" or side == "S" then
              local merged = (k <= 1) and c.hangar and n.hangar and c.kind == n.kind
              if not merged then
                local ops = {}
                local hallVoid = (k == 1) and (c.hangar or n.hangar)
                local stairBlock = (side == "E" and n.stair)
                if not hallVoid and not stairBlock then
                  local off = (alongX and (c.stair or n.stair)) and 6 or 0
                  ops = {door(base + C / 2 + off, 6, 9)}
                end
                wall(i, j, side, k, 1.5, ops, true)
              end
            end
          else
            -- exterior wall at this level
            local ops = {}
            local stairWest = (side == "W" and c.stair)
            local off = (alongX and c.stair) and 6 or 0
            if k == 0 and not n then
              local outward = (not inGrid(ni, nj)) and ((side == "N" and opts.openN) or (side == "E" and opts.openE) or (side == "S" and opts.openS) or (side == "W" and opts.openW))
              local court = inGrid(ni, nj)
              if (court or outward) and not stairWest then
                if c.hangar then ops = {door(base + C / 2, 10, 11)} else ops = {door(base + C / 2 + off, 6, 9)} end
              end
            elseif n and k == n.storeys and not stairWest and not (c.hangar and k == 1) then
              ops = {door(base + C / 2 + off, 6, 9)}       -- out onto the neighbour's roof
            end
            if #ops == 0 and k > 0 then ops = windows(base) end
            wall(i, j, side, k, 2, ops, false)
            -- charcoal band at the floor line above (not at the roof line)
            if k + 1 < c.storeys then
              local y = (k + 1) * FH
              if side == "N" then charcoal(K.B(fTrim, "Band", x0 - 1, y - 0.7, z0 - 1.3, x0 + C + 1, y + 0.7, z0 - 0.9))
              elseif side == "S" then charcoal(K.B(fTrim, "Band", x0 - 1, y - 0.7, z0 + C + 0.9, x0 + C + 1, y + 0.7, z0 + C + 1.3))
              elseif side == "W" then charcoal(K.B(fTrim, "Band", x0 - 1.3, y - 0.7, z0 - 1, x0 - 0.9, y + 0.7, z0 + C + 1))
              else charcoal(K.B(fTrim, "Band", x0 + C + 0.9, y - 0.7, z0 - 1, x0 + C + 1.3, y + 0.7, z0 + C + 1)) end
            end
            if k == 0 then
              -- plinth with the same ground openings
              local pops = ops
              if side == "N" then K.wallX(fTrim, "Plinth", x0 - 1, x0 + C + 1, z0 - 1.1, 0, 1.5, 0.4, pops, CHAR, Enum.Material.Metal)
              elseif side == "S" then K.wallX(fTrim, "Plinth", x0 - 1, x0 + C + 1, z0 + C + 1.1, 0, 1.5, 0.4, pops, CHAR, Enum.Material.Metal)
              elseif side == "W" then K.wallZ(fTrim, "Plinth", z0 - 1, z0 + C + 1, x0 - 1.1, 0, 1.5, 0.4, pops, CHAR, Enum.Material.Metal)
              else K.wallZ(fTrim, "Plinth", z0 - 1, z0 + C + 1, x0 + C + 1.1, 0, 1.5, 0.4, pops, CHAR, Enum.Material.Metal) end
            end
          end
        end
        -- roof edge: thick charcoal parapet band where the neighbour is lower or absent
        local top = c.storeys * FH
        if not n or n.storeys < c.storeys then
          local p
          if side == "N" then p = K.B(fTrim, "RoofBand", x0 - 1.2, top - 2.2, z0 - 1.2, x0 + C + 1.2, top + 3.2, z0 + 0.4)
          elseif side == "S" then p = K.B(fTrim, "RoofBand", x0 - 1.2, top - 2.2, z0 + C - 0.4, x0 + C + 1.2, top + 3.2, z0 + C + 1.2)
          elseif side == "W" then p = K.B(fTrim, "RoofBand", x0 - 1.2, top - 2.2, z0 - 1.2, x0 + 0.4, top + 3.2, z0 + C + 1.2)
          else p = K.B(fTrim, "RoofBand", x0 + C - 0.4, top - 2.2, z0 - 1.2, x0 + C + 1.2, top + 3.2, z0 + C + 1.2) end
          charcoal(p)
        end
      end
      -- ceiling light on the ground room (and the hall)
      local cy = (c.hangar and 2 or 1) * FH - 1.15
      local lp = K.P(fLights, "CeilingLight", Vector3.new(5, 0.3, 1.6), K.W(cx + (c.stair and 5 or 0), cy, cz), Color3.fromRGB(240, 242, 246), Enum.Material.Neon)
      lp.CanCollide = false; lp.CanQuery = false; lp.CastShadow = false
      local sl = Instance.new("SurfaceLight"); sl.Face = Enum.NormalId.Bottom; sl.Angle = 120; sl.Range = c.hangar and 28 or 18; sl.Brightness = 1.3; sl.Shadows = false; sl.Parent = lp
    end
  end end
  root.Parent = par
  return root, cells
end
return M
