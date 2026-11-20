local K = require(game.ServerStorage.VantageLobbyTools.Kit:Clone())
local H = { K = K }
local RGB = Color3.fromRGB
H.C = {
	SL = RGB(76,72,112), SL2 = RGB(58,54,88), SL3 = RGB(98,94,140), GD = RGB(46,42,70), DK = RGB(30,27,46),
	FL = RGB(132,124,170), FL2 = RGB(104,98,142), GRT = RGB(88,82,124),
	SAL = RGB(255,124,108), PE = RGB(255,176,128), OR = RGB(255,150,60), YEL = RGB(255,204,40), BLK = RGB(34,30,40),
	BLUE = RGB(70,160,255), CY = RGB(90,220,255), RED = RGB(255,60,60), WH = RGB(245,242,255), GL = RGB(190,214,255),
	DM = RGB(240,62,76), FFA = RGB(255,150,40), CTF = RGB(60,142,255), BP = RGB(170,90,255), SK = RGB(255,84,170), EX = RGB(40,210,220), LB = RGB(255,206,60),
	R1 = RGB(84,76,116), R2 = RGB(66,60,94), R3 = RGB(104,94,130), IV1 = RGB(52,110,64), IV2 = RGB(70,134,72), IV3 = RGB(40,92,58),
}
local C, M = H.C, K.M
local FONT = {
	A = { " ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" }, B = { "#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### " },
	C = { " ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####" }, D = { "#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### " },
	E = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####" }, F = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    " },
	G = { " ####", "#    ", "#    ", "#  ##", "#   #", "#   #", " ####" }, H = { "#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	I = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####" }, J = { "  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  " },
	K = { "#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #" }, L = { "#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####" },
	M = { "#   #", "## ##", "# # #", "#   #", "#   #", "#   #", "#   #" }, N = { "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #" },
	O = { " ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " }, P = { "#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    " },
	R = { "#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #" }, S = { " ####", "#    ", "#    ", " ### ", "    #", "    #", "#### " },
	T = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  " }, U = { "#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	V = { "#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  " }, W = { "#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #" },
	X = { "#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #" }, Y = { "#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  " },
	["?"] = { " ### ", "#   #", "    #", "  ## ", "  #  ", "     ", "  #  " },
}
local cache = {}
local function rects(ch)
	if cache[ch] then return cache[ch] end
	local g, out, open = FONT[ch], {}, {}
	if not g then return {} end
	for r = 1, 7 do
		local row, runs, c = g[r], {}, 1
		while c <= 5 do
			if row:sub(c, c) == "#" then local s = c while c <= 5 and row:sub(c, c) == "#" do c += 1 end table.insert(runs, { s, c - 1 }) else c += 1 end
		end
		local nxt = {}
		for _, run in ipairs(runs) do
			local key = run[1] .. ":" .. run[2]
			if open[key] then open[key].y1 = r nxt[key] = open[key] else local rc = { x0 = run[1], x1 = run[2], y0 = r, y1 = r } table.insert(out, rc) nxt[key] = rc end
		end
		open = nxt
	end
	cache[ch] = out
	return out
end
function H.word(parent, name, F, lines, cell, col, outCol, slant, depth)
	if type(lines) == "string" then lines = { lines } end
	slant = slant or 0.22 depth = depth or cell * 1.6
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local lineH, gap = 7 * cell, 2.4 * cell
	local totalH = #lines * lineH + (#lines - 1) * gap
	local maxW = 0
	for li, txt in ipairs(lines) do
		local w = (#txt * 6 - 1) * cell
		maxW = math.max(maxW, w)
		local top = totalH / 2 - (li - 1) * (lineH + gap)
		for ci = 1, #txt do
			local ox = -w / 2 + (ci - 1) * 6 * cell
			for _, rc in ipairs(rects(txt:sub(ci, ci))) do
				local cx = ox + ((rc.x0 - 1) + rc.x1) / 2 * cell
				local cy = top - ((rc.y0 - 1) + rc.y1) / 2 * cell
				local sx, sy = (rc.x1 - rc.x0 + 1) * cell, (rc.y1 - rc.y0 + 1) * cell
				local x = -(cx + cy * slant)
				K.part(m, "Glyph", Vector3.new(sx, sy, depth), F * CFrame.new(x, cy, -depth / 2), col, M.SmoothPlastic, { decor = true })
				if outCol then K.part(m, "Outline", Vector3.new(sx + cell * 0.8, sy + cell * 0.8, depth * 0.7), F * CFrame.new(x, cy, -depth * 0.35 + 0.15), outCol, M.SmoothPlastic, { decor = true }) end
			end
		end
	end
	return m, maxW, totalH
end
function H.octRing(parent, name, F, r, t, depth, color, mat, opts, skip)
	local s = 2 * r * math.tan(math.rad(22.5))
	for i = 0, 7 do
		if not (skip and skip[i]) then
			local th = math.rad(i * 45)
			K.part(parent, name, Vector3.new(t, s + t * 0.83, depth), F * CFrame.new(r * math.cos(th), r * math.sin(th), 0) * CFrame.Angles(0, 0, th), color, mat or M.SmoothPlastic, opts)
		end
	end
end
function H.hex(parent, name, cf, r, h, color, mat, opts)
	local first
	for i = 0, 2 do
		local p = K.part(parent, name, Vector3.new(r, h, r * math.sqrt(3)), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(i * 60), 0), color, mat, opts)
		first = first or p
	end
	return first
end
function H.cyl(parent, name, cf, r, h, color, mat, opts)
	local p = K.part(parent, name, Vector3.new(h, r * 2, r * 2), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, mat, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end
function H.beam(parent, name, a, b, w, h, color, mat, opts)
	local up = math.abs((b - a).Unit.Y) > 0.95 and Vector3.zAxis or Vector3.yAxis
	return K.part(parent, name, Vector3.new(w, h, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b, up), color, mat or M.Metal, opts)
end
function H.hazard(part, face, tile)
	local g = K.gui(part, face, 8, 1) g.LightInfluence = 1
	local sz = part.Size
	local w, h
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then w, h = sz.X, sz.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then w, h = sz.Z, sz.Y else w, h = sz.X, sz.Z end
	tile = tile or h
	local kps, n = {}, 8
	for i = 0, n - 1 do
		local col = (i % 2 == 0) and C.YEL or C.BLK
		table.insert(kps, ColorSequenceKeypoint.new(i / n, col))
		table.insert(kps, ColorSequenceKeypoint.new(math.min((i + 1) / n - 0.0005, 1), col))
	end
	kps[#kps] = ColorSequenceKeypoint.new(1, kps[#kps].Value)
	for i = 0, math.ceil(w / tile) - 1 do
		local f = K.frame(g, Color3.new(1, 1, 1), UDim2.fromScale(i * tile / w, 0), UDim2.new(tile / w, 1, 1, 0))
		local gr = Instance.new("UIGradient") gr.Color = ColorSequence.new(kps) gr.Rotation = 45 gr.Parent = f
	end
end
function H.rail(parent, a, b, h)
	h = h or 3.4
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	K.part(parent, "RailTop", Vector3.new(0.5, 0.35, len), cf * CFrame.new(0, h, 0), C.GD, M.Metal)
	K.part(parent, "RailGlass", Vector3.new(0.25, h - 0.3, len), cf * CFrame.new(0, (h - 0.3) / 2, 0), C.GL, M.Glass, { tr = 0.6 })
	K.part(parent, "RailGlow", Vector3.new(0.3, 0.15, len), cf * CFrame.new(0, 0.2, 0), C.OR, M.Neon, { decor = true, neon = true })
end
function H.portal(parent, name, F, w, h, col, surroundCol)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	K.part(m, "Surround", Vector3.new(w + 10, h + 6, 2), F * CFrame.new(0, (h + 6) / 2, 1), surroundCol or C.SL2, M.SmoothPlastic)
	K.part(m, "PortalBack", Vector3.new(w, h, 0.3), F * CFrame.new(0, h / 2, -0.15), C.DK, M.SmoothPlastic, { decor = true })
	K.part(m, "PortalGlow", Vector3.new(w - 0.6, h - 0.6, 0.3), F * CFrame.new(0, h / 2, -0.45), col, M.Neon, { decor = true, neon = true, tr = 0.3 })
	for _, sx in ipairs({ -1, 1 }) do
		K.part(m, "Jamb", Vector3.new(2.4, h, 3), F * CFrame.new(sx * (w / 2 + 1.2), h / 2, -1.5), C.SL3, M.SmoothPlastic)
		K.part(m, "JambGlow", Vector3.new(0.35, h - 2, 0.35), F * CFrame.new(sx * (w / 2 + 0.05), h / 2, -2.6), col, M.Neon, { decor = true, neon = true })
		K.part(m, "Chamfer", Vector3.new(3.6, 3.6, 3.1), F * CFrame.new(sx * (w / 2), h, -1.5) * CFrame.Angles(0, 0, math.rad(45)), C.SL3, M.SmoothPlastic)
	end
	K.part(m, "Head", Vector3.new(w + 4.8, 2.4, 3), F * CFrame.new(0, h + 1.2, -1.5), C.SL3, M.SmoothPlastic)
	K.part(m, "HeadGlow", Vector3.new(w + 2, 0.4, 0.3), F * CFrame.new(0, h + 0.3, -3.05), col, M.Neon, { decor = true, neon = true })
	local lp = K.part(m, "Light", Vector3.new(1, 1, 1), F * CFrame.new(0, h / 2, -5), col, M.SmoothPlastic, { decor = true, tr = 1 })
	local l = Instance.new("PointLight") l.Color = col l.Range = 20 l.Brightness = 1.4 l.Parent = lp
	return m
end
function H.stairs(parent, name, F, width, rise, steps, run, col, nose)
	local m = K.stairs(parent, name, F, width, rise, steps, run, col, nose)
	for _, n in ipairs(m:GetChildren()) do
		n.MaterialVariant = ""
		if n.Name == "Nose" then n.Material = M.Neon n.CastShadow = false else n.Material = M.SmoothPlastic end
	end
	return m
end
function H.prompt(part, action, object, station)
	local pp = Instance.new("ProximityPrompt") pp.ActionText = action pp.ObjectText = object
	pp.MaxActivationDistance = 12 pp.RequiresLineOfSight = false pp.Parent = part
	part:SetAttribute("Station", station)
end
function H.queuePad(part, mode)
	part:SetAttribute("Mode", mode) game:GetService("CollectionService"):AddTag(part, "LobbyQueuePad")
end
return H
