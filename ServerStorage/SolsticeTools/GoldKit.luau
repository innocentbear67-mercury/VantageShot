local K = require(game.ServerStorage.SolsticeTools.Kit:Clone())
local C = Color3.fromRGB
local M = Enum.Material
K.Pal.gdark = C(74, 78, 88)
K.Pal.gold = C(255, 112, 84)
K.Pal.goldDeep = C(214, 86, 64)
K.Pal.gfloor = C(128, 124, 122)
K.Pal.gwall = C(96, 98, 104)
K.Pal.gglow = C(255, 140, 100)
K.Team.Blue.gteam = C(40, 130, 255) K.Team.Red.gteam = C(220, 30, 80)
K.Look.dark = { M.SmoothPlastic, "VS_Soft", "gdark" }
K.Look.darkL = { M.SmoothPlastic, "VS_Soft", "gdark" }
K.Look.gold = { M.SmoothPlastic, "VS_Soft", "gold" }
K.Look.goldDeep = { M.SmoothPlastic, "VS_Soft", "goldDeep" }
K.Look.gfloor = { M.SmoothPlastic, "VS_Soft", "gfloor" }
K.Look.gwall = { M.SmoothPlastic, "VS_Soft", "gwall" }
K.Look.glow = { M.Neon, "", "gglow" }
K.Look.gteam = { M.SmoothPlastic, "", "gteam" }
K.Look.gteamNeon = { M.Neon, "", "gteam" }
-- dark block with a gold cap band on top (Hypershot signature)
function K.capped(name, x0, x1, z0, z1, h, o)
  o = o or {}
  local y0 = o.y0 or 0
  local cap = o.cap or 4
  K.box(name, x0, x1, y0, y0 + h - cap, z0, z1, o.look or "dark", o)
  K.box(name .. "_Cap", x0, x1, y0 + h - cap, y0 + h, z0, z1, o.capLook or "gold", o)
end
-- gold ramp (smooth wedge) rising toward dir
function K.ramp(name, x0, x1, z0, z1, ya, yb, dir, o)
  o = o or {}
  return K.stairs(name, x0, x1, z0, z1, ya, yb, dir, { ramp = true, look = o.look or "gold", solo = o.solo })
end
-- free-standing gate frame (П), along z (opening faces x) unless alongX
function K.gate(name, cx, cz, w, h, alongX, o)
  local t = 4
  if alongX then
    K.box(name .. "_L", cx - w/2 - t, cx - w/2, 0, h, cz - t/2, cz + t/2, "gold", o)
    K.box(name .. "_R", cx + w/2, cx + w/2 + t, 0, h, cz - t/2, cz + t/2, "gold", o)
    K.box(name .. "_T", cx - w/2 - t, cx + w/2 + t, h, h + t, cz - t/2, cz + t/2, "gold", o)
  else
    K.box(name .. "_L", cx - t/2, cx + t/2, 0, h, cz - w/2 - t, cz - w/2, "gold", o)
    K.box(name .. "_R", cx - t/2, cx + t/2, 0, h, cz + w/2, cz + w/2 + t, "gold", o)
    K.box(name .. "_T", cx - t/2, cx + t/2, h, h + t, cz - w/2 - t, cz + w/2 + t, "gold", o)
  end
end
-- jump pad (PadTarget set for Blue; Red copy fixed after finish by K.fixPads)
function K.pad(name, x, z, target, o)
  local p = K.box(name, x - 5, x + 5, 0, 0.6, z - 5, z + 5, "glow", { tag = "JumpPad" })
  p:SetAttribute("PadTarget", target)
  K.box(name .. "_Ring", x - 6.5, x + 6.5, 0, 0.3, z - 6.5, z + 6.5, "goldDeep")
  return p
end
function K.fixPads(zoneName)
  local z = K.arena():FindFirstChild(zoneName)
  local r = z and z:FindFirstChild("Red")
  if not r then return 0 end
  local n = 0
  for _, p in ipairs(r:GetChildren()) do
    local t = p:GetAttribute("PadTarget")
    if typeof(t) == "Vector3" then p:SetAttribute("PadTarget", Vector3.new(-t.X, t.Y, -t.Z)) n += 1 end
  end
  return n
end
return K
