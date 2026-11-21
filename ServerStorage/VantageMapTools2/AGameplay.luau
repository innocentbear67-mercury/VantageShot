local G = {}
local V = Vector3.new
function G.build(map, O, g, sym, box, extra)
	local BK = game.ServerStorage:FindFirstChild("_ClutteredMaps_20261119")
	local stpl
	if BK then
		local mp = BK:FindFirstChild("Map_PortoSole")
		local gp = mp and mp:FindFirstChild("Gameplay")
		local sp = gp and gp:FindFirstChild("Spawns")
		stpl = sp and sp:FindFirstChild("BlueSpawn")
	end
	if not stpl then
		error("AGameplay: spawn template archive game.ServerStorage._ClutteredMaps_20261119.Map_PortoSole.Gameplay.Spawns is missing — restore it or point BK at a new template before rebuilding")
	end
	local Gp = map:FindFirstChild("Gameplay") or Instance.new("Folder")
	Gp.Name = "Gameplay" Gp:ClearAllChildren() Gp.Parent = map
	local function fold(n) local f = Instance.new("Folder") f.Name = n f.Parent = Gp return f end
	local Sp, Bd, KV, BS, FS = fold("Spawns"), fold("Boundary"), fold("KillVolumes"), fold("BotSpots"), fold("FlagStands")
	fold("VehicleSpawns") local Lf = fold("Lifts")
	local function red(p) if sym == "mirror" then return V(p.X, p.Y, -p.Z) end return V(-p.X, p.Y, -p.Z) end
	for _, p in ipairs(g.spawns) do
		for _, team in ipairs({ "Blue", "Red" }) do
			local s = stpl:Clone()
			local pos = team == "Blue" and p or red(p)
			local dir = team == "Blue" and V(0, 0, 1) or V(0, 0, -1)
			s.CFrame = CFrame.lookAt(O + pos, O + pos + dir)
			s.TeamColor = BrickColor.new(team == "Blue" and "Really blue" or "Really red")
			s.Name = team .. "Spawn" s:SetAttribute("Team", team) s.Enabled = false s.Parent = Sp
		end
	end
	local function inv(name, size, pos, parent, attrs, cc)
		local p = Instance.new("Part") p.Name = name p.Size = size p.CFrame = CFrame.new(O + pos) p.Anchored = true p.Transparency = 1
		p.CanCollide = cc or false p.CanQuery = cc or false p.CanTouch = true p.CastShadow = false
		for k, v in pairs(attrs or {}) do p:SetAttribute(k, v) end p.Parent = parent return p
	end
	local x0, x1, z0, z1 = box[1], box[2], box[3], box[4]
	local cx, cz, w, d = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
	inv("West", V(4, 340, d + 8), V(x0 - 2, 160, cz), Bd, { NoGrapple = true }, true)
	inv("East", V(4, 340, d + 8), V(x1 + 2, 160, cz), Bd, { NoGrapple = true }, true)
	inv("South", V(w + 8, 340, 4), V(cx, 160, z0 - 2), Bd, { NoGrapple = true }, true)
	inv("North", V(w + 8, 340, 4), V(cx, 160, z1 + 2), Bd, { NoGrapple = true }, true)
	inv("Ceiling", V(w + 8, 4, d + 8), V(cx, 170, cz), Bd, { NoGrapple = true }, true)
	for _, b in ipairs(Bd:GetChildren()) do b.CanQuery = true end
	inv("Void", V(2048, 8, 2048), V(0, -60, 0), KV)
	inv("Blue", V(2, 1, 2), g.bot, BS) inv("Red", V(2, 1, 2), red(g.bot), BS)
	inv("BlueFlag", V(6, 1, 6), g.flag, FS) inv("RedFlag", V(6, 1, 6), red(g.flag), FS)
	for _, l in ipairs(extra and extra.lifts or {}) do inv(l.name, l.size, l.pos, Lf, l.attrs) end
	return Gp
end
return G
