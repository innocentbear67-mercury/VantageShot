-- AElev (2026-11-19): adds ramp-accessible high-ground decks to an arena map.
-- Deck = dark HSX body + accent cap, a parapet on the enemy-facing edge, a ramp off one end and a
-- jump pad behind it. Placed where the deck top overlooks the most ground; twinned by the map's symmetry.
local E = {}
local V = Vector3.new
local function part(parent, name, size, cf, variant, color, cls)
	local p = Instance.new(cls or "Part")
	p.Name = name p.Anchored = true p.Size = size p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic p.MaterialVariant = variant p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
-- local (axis-aligned) helpers: t = coordinate along the team axis, l = lateral
local function toWorld(O, axis, t, l, y) if axis == "Z" then return O + V(l, y, t) else return O + V(t, y, l) end end
local function dirT(axis, s) if axis == "Z" then return V(0, 0, s) else return V(s, 0, 0) end end
local function dirL(axis, s) if axis == "Z" then return V(s, 0, 0) else return V(0, 0, s) end end
local function twinPos(O, sym, p) local r = p - O if sym == "mirror" then return O + V(r.X, r.Y, -r.Z) else return O + V(-r.X, r.Y, -r.Z) end end

-- footprint boxes for a deck spec (world AABBs as {cf,size})
function E.layout(O, axis, t, l, H, lsign, tsign, opt)
	local W, D, RW = opt.W or 18, opt.D or 12, opt.RW or 7
	local RL = H / math.tan(math.rad(opt.Slope or 29))
	local L = {}
	local c = toWorld(O, axis, t, l, H / 2)
	local sizeAxisT, sizeAxisL = D, W
	local function box(center, sl, st, sy) -- sizes along lateral, team, y
		if axis == "Z" then return { CFrame.new(center), V(sl, sy, st) } else return { CFrame.new(center), V(st, sy, sl) } end
	end
	L.deck = box(c, W, D, H)
	-- ramp off the lateral end (lsign), flush with the deck's own-side edge
	local rc = c + dirL(axis, lsign) * (W / 2 + RL / 2) + dirT(axis, tsign) * (D / 2 - RW / 2)
	L.ramp = { center = V(rc.X, O.Y + H / 2, rc.Z), RL = RL, RW = RW, away = dirL(axis, lsign) }
	L.rampBox = box(V(rc.X, O.Y + H / 2, rc.Z), RL, RW, H)
	-- pad behind the deck (own side), 7 studs out
	local pc = c + dirT(axis, tsign) * (D / 2 + 7) + dirL(axis, -lsign) * (W / 4)
	L.pad = V(pc.X, O.Y, pc.Z)
	L.padBox = box(V(pc.X, O.Y + 4, pc.Z), 11, 11, 8)
	L.top = c + V(0, H / 2, 0)
	return L
end

function E.clear(map, cf, size, floorTop)
	local op = OverlapParams.new() op.FilterType = Enum.RaycastFilterType.Include op.FilterDescendantsInstances = { map }
	local s = size + V(7.5, 0, 7.5) -- >=3.5 clear on every side: no slits next to existing blocks
	local hits = workspace:GetPartBoundsInBox(cf + V(0, 1, 0), s - V(0, 1.2, 0), op)
	for _, h in ipairs(hits) do
		if h.CanCollide and h.Transparency < 0.95 and not h:FindFirstAncestor("Gameplay") then
			local top = h.Position.Y + h.Size.Y / 2
			if not (h.Name:find("Floor") and top <= floorTop + 0.6) then return false, h.Name end
		elseif h:FindFirstAncestor("Gameplay") and (h.Name:find("Spawn") or h:IsA("SpawnLocation")) then
			return false, "spawn"
		end
	end
	return true
end

function E.build(parent, L, axis, tsign, H, k, accent, name)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local body, cap = "HSX_Body_" .. k, "HSX_Accent"
	local bodyCol = Color3.fromRGB(214, 216, 224)
	local cf, s = L.deck[1], L.deck[2]
	part(m, "Deck", s - V(0, 1.2, 0), cf - V(0, 0.6, 0), body, bodyCol)
	part(m, "Deck_Cap", V(s.X + 0.4, 1.2, s.Z + 0.4), cf + V(0, s.Y / 2 - 0.6, 0), cap, accent)
	-- parapet on the enemy-facing edge with a 4-stud firing gap in the middle
	local enemy = dirT(axis, -tsign)
	local edge = cf.Position + enemy * ((axis == "Z" and s.Z or s.X) / 2 - 0.6) + V(0, s.Y / 2 + 1.75, 0)
	local W = axis == "Z" and s.X or s.Z
	local seg = (W - 4) / 2
	for _, sg in ipairs({ -1, 1 }) do
		local lat = dirL(axis, sg) * (2 + seg / 2)
		local sz = axis == "Z" and V(seg, 3.5, 1.2) or V(1.2, 3.5, seg)
		part(m, "Parapet", sz, CFrame.new(edge + lat), cap, accent)
	end
	-- ramp: wedge high end at the deck, low end away
	local r = L.ramp
	local w = part(m, "DeckRamp", V(r.RW, H, r.RL), CFrame.lookAt(r.center, r.center + r.away), cap, accent, "WedgePart")
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d:SetAttribute("Elev", true) end end
	return m
end
local function twinF(O, sym) return function(p) local r = p - O if sym == "mirror" then return O + V(r.X, r.Y, -r.Z) else return O + V(-r.X, r.Y, -r.Z) end end end
local function twinCF(O, sym, cf)
	local tw = twinF(O, sym)
	local p = tw(cf.Position)
	local look = cf.LookVector
	local tl = if sym == "mirror" then V(look.X, look.Y, -look.Z) else V(-look.X, look.Y, -look.Z)
	return CFrame.lookAt(p, p + tl)
end
E.twinCF = twinCF
-- build the deck (side A, tsign = -1 half) + its twin + pads; returns models
function E.place(map, O, axis, sym, pick, k, accent, idx)
	local APad = require(game.ServerStorage.VantageMapTools2.APad:Clone())
	local folder = map:FindFirstChild("Z_Elev") or Instance.new("Folder")
	folder.Name = "Z_Elev" folder.Parent = map
	local L = E.layout(O, axis, pick.t, pick.l, pick.H, pick.ls, -1, {})
	local a = E.build(folder, L, axis, -1, pick.H, k, accent, "Deck" .. idx .. "A")
	local b = a:Clone() b.Name = "Deck" .. idx .. "B" b.Parent = folder
	for _, p in ipairs(b:GetDescendants()) do if p:IsA("BasePart") then
		if sym == "mirror" and p:IsA("WedgePart") then
			local r = p.Position - O
			local np = O + V(r.X, r.Y, -r.Z)
			local lk = p.CFrame.LookVector
			p.CFrame = CFrame.lookAt(np, np + V(lk.X, lk.Y, -lk.Z))
		else
			p.CFrame = twinCF(O, sym, p.CFrame)
		end
	end end
	-- pads (launch onto the deck top, slightly toward the parapet)
	local tw = twinF(O, sym)
	local tgt = L.top + dirT(axis, 1) * 1.5 + V(0, 0.2, 0)
	APad.make(folder, L.pad, tgt, accent, "DeckPad" .. idx .. "A")
	APad.make(folder, tw(L.pad), tw(tgt), accent, "DeckPad" .. idx .. "B")
	return a, b
end
function E.search(m, O, b, axis, sym, maxN)
	local excl = {} for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") and (d.Transparency > 0.9 or d.Name:find("SpawnShield")) then table.insert(excl, d) end end
	table.insert(excl, m.Gameplay)
	local los = RaycastParams.new() los.FilterType = Enum.RaycastFilterType.Exclude los.FilterDescendantsInstances = excl
	local rng = Random.new(11) local gp = {} local tries = 0
	while #gp < 260 and tries < 6000 do tries += 1
		local x, z = rng:NextNumber(b[1] + 4, b[2] - 4), rng:NextNumber(b[3] + 4, b[4] - 4)
		local r = workspace:Raycast(O + V(x, 200, z), V(0, -260, 0), los)
		if r and r.Normal.Y > 0.7 and r.Position.Y - O.Y < 10 then table.insert(gp, r.Position + V(0, 3, 0)) end
	end
	local function flat(bx) local p, s = bx[1].Position, bx[2]
		for _, o in ipairs({ V(0, 0, 0), V(s.X / 2 - 1, 0, s.Z / 2 - 1), V(-s.X / 2 + 1, 0, s.Z / 2 - 1), V(s.X / 2 - 1, 0, -s.Z / 2 + 1), V(-s.X / 2 + 1, 0, -s.Z / 2 + 1) }) do
			local r = workspace:Raycast(V(p.X, O.Y + 0.5, p.Z) + o, V(0, -6, 0), los)
			if not r or math.abs(r.Position.Y - O.Y) > 0.6 then return false end
		end
		return true
	end
	local tw = function(p) local r = p - O if sym == "mirror" then return O + V(r.X, r.Y, -r.Z) else return O + V(-r.X, r.Y, -r.Z) end end
	local halfT = (b[4] - b[3]) / 2
	local cands = {}
	for t = -0.46 * halfT, -0.08 * halfT, 5 do
		for l = b[1] + 16, b[2] - 16, 5 do for _, H in ipairs({ 12, 14 }) do for _, ls in ipairs({ -1, 1 }) do
			local L = E.layout(O, axis, t, l, H, ls, -1, {})
			local ok = true
			for _, bx in ipairs({ L.deck, L.rampBox, L.padBox }) do
				local p = bx[1].Position - O local sz = bx[2]
				if not (p.X - sz.X / 2 > b[1] + 4 and p.X + sz.X / 2 < b[2] - 4 and p.Z - sz.Z / 2 > b[3] + 4 and p.Z + sz.Z / 2 < b[4] - 4) then ok = false break end
				if not E.clear(m, bx[1], bx[2], O.Y) or not E.clear(m, CFrame.new(tw(bx[1].Position)), bx[2], O.Y) then ok = false break end
			end
			if ok then ok = flat(L.deck) and flat(L.rampBox) and flat(L.padBox) end
			if ok then
				local eye = L.top + V(0, 4.5, 0) local vis = 0
				for _, g in ipairs(gp) do local d = (g - eye).Magnitude if d > 20 and d < 110 and not workspace:Raycast(eye, g - eye, los) then vis += 1 end end
				table.insert(cands, { t = t, l = l, H = H, ls = ls, vis = vis, top = L.top })
			end
		end end end
		task.wait()
	end
	table.sort(cands, function(a, c) return a.vis > c.vis end)
	local pick = {}
	for _, c in ipairs(cands) do
		local far = true for _, p in ipairs(pick) do if (p.top - c.top).Magnitude < 45 then far = false end end
		if far then table.insert(pick, c) end
		if #pick >= maxN then break end
	end
	return pick, #cands
end
return E
