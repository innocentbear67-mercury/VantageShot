local A = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local function refresh()
  params.FilterDescendantsInstances = { workspace.Map_LiveFire.Arena }
  params.RespectCanCollide = true
end
A.refresh = refresh
local function solidRay(o, d)
  local r = workspace:Raycast(o, d, params)
  return r
end
A.ray = solidRay
-- ground (walkable top) under x,z from above, at or below yMax
function A.ground(x, z, yMax)
  local r = solidRay(Vector3.new(x, (yMax or 200), z), Vector3.new(0, -260, 0))
  return r and r.Position.Y or nil, r
end
-- exposure: mean of horizontal free distances in 8 dirs at eye height, capped
function A.exposureMap(cell, cap)
  refresh()
  local rows = {}
  local chars = " .:-=+*#%@"
  local exposed = 0
  for z = 400 - cell/2, -400, -cell do
    local row = {}
    for x = -400 + cell/2, 400, cell do
      local gy = A.ground(x, z, 2) -- ground level only (y<=2)
      local c = "~"
      if gy then
        local o = Vector3.new(x, gy + 5, z)
        local sum = 0
        for i = 0, 7 do
          local a = i * math.pi / 4
          local d = Vector3.new(math.cos(a), 0, math.sin(a)) * cap
          local r = solidRay(o, d)
          sum += r and (r.Position - o).Magnitude or cap
        end
        local m = sum / 8
        if m > cap * 0.6 then exposed += 1 end
        c = chars:sub(math.clamp(math.floor(m / cap * 9) + 1, 1, 10), math.clamp(math.floor(m / cap * 9) + 1, 1, 10))
      end
      table.insert(row, c)
    end
    table.insert(rows, table.concat(row))
  end
  return table.concat(rows, "\n"), exposed
end
-- sightlines between two rects at eye height on walkable ground
function A.sightlines(r1, r2, n, seed)
  refresh()
  local rng = Random.new(seed or 7)
  local clear, tested, examples = 0, 0, {}
  for i = 1, n do
    local x1, z1 = rng:NextNumber(r1[1], r1[2]), rng:NextNumber(r1[3], r1[4])
    local x2, z2 = rng:NextNumber(r2[1], r2[2]), rng:NextNumber(r2[3], r2[4])
    local g1, g2 = A.ground(x1, z1, 120), A.ground(x2, z2, 120)
    if g1 and g2 then
      tested += 1
      local a, b = Vector3.new(x1, g1 + 5, z1), Vector3.new(x2, g2 + 5, z2)
      if not solidRay(a, b - a) then
        clear += 1
        if #examples < 6 then table.insert(examples, string.format("(%d,%d,%d)->(%d,%d,%d)", a.X, a.Y, a.Z, b.X, b.Y, b.Z)) end
      end
    end
  end
  return clear, tested, examples
end
return A
