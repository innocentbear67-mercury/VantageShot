local K = require(game.ServerStorage.VantageLobbyTools.Kit:Clone())
local H = {}
local RGB = Color3.fromRGB
H.C = { LAV = RGB(178,170,206), LAV2 = RGB(146,138,180), LAV3 = RGB(212,206,232), FL = RGB(200,194,218), FL2 = RGB(170,162,196),
	PE = RGB(255,198,160), OR = RGB(255,140,60), TR = RGB(124,116,156), DK = RGB(66,62,90), DK2 = RGB(36,32,52), GL = RGB(220,226,240),
	YEL = RGB(255,204,40), BLK = RGB(34,30,40), MET = RGB(132,128,150),
	DM = RGB(240,62,76), FFA = RGB(255,150,40), CTF = RGB(60,142,255), BP = RGB(170,90,255), SK = RGB(255,84,170), EX = RGB(40,210,220), LB = RGB(255,206,60) }
H.X0, H.X1, H.Z0, H.Z1, H.EAVE, H.UP = -78, 78, -120, 110, 58, 16
local FONT = {
	A = { " ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	B = { "#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### " },
	C = { " ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####" },
	D = { "#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### " },
	E = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####" },
	F = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    " },
	G = { " ####", "#    ", "#    ", "#  ##", "#   #", "#   #", " ####" },
	H = { "#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	I = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####" },
	J = { "  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  " },
	K = { "#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #" },
	L = { "#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####" },
	M = { "#   #", "## ##", "# # #", "#   #", "#   #", "#   #", "#   #" },
	N = { "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #" },
	O = { " ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	P = { "#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    " },
	R = { "#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #" },
	S = { " ####", "#    ", "#    ", " ### ", "    #", "    #", "#### " },
	T = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  " },
	U = { "#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	V = { "#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  " },
	X = { "#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #" },
	Y = { "#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  " },
}
H.FONT = FONT
local function rects(g)
	local out, open = {}, {}
	for r = 1, 7 do
		local row, runs, c = g[r], {}, 1
		while c <= 5 do
			if row:sub(c, c) == "#" then local s = c while c <= 5 and row:sub(c, c) == "#" do c += 1 end table.insert(runs, { s, c - 1 }) else c += 1 end
		end
		local nextOpen = {}
		for _, run in ipairs(runs) do
			local key = run[1] .. ":" .. run[2]
			if open[key] then open[key].y1 = r nextOpen[key] = open[key] else
				local rc = { x0 = run[1], x1 = run[2], y0 = r, y1 = r } table.insert(out, rc) nextOpen[key] = rc end
		end
		open = nextOpen
	end
	return out
end
function H.text3d(parent, name, F, lines, cell, depth, color, mat)
	if type(lines) == "string" then lines = { lines } end
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local lineH, gap = 7 * cell, 2.2 * cell
	local totalH = #lines * lineH + (#lines - 1) * gap
	local maxW = 0
	for li, txt in ipairs(lines) do
		local w = (#txt * 6 - 1) * cell
		maxW = math.max(maxW, w)
		local top = totalH / 2 - (li - 1) * (lineH + gap)
		for ci = 1, #txt do
			local g = FONT[txt:sub(ci, ci)]
			if g then
				local ox = -w / 2 + (ci - 1) * 6 * cell
				for _, rc in ipairs(rects(g)) do
					local cx = ox + ((rc.x0 - 1) + rc.x1) / 2 * cell
					local cy = top - ((rc.y0 - 1) + rc.y1) / 2 * cell
					K.part(m, "Glyph", Vector3.new((rc.x1 - rc.x0 + 1) * cell, (rc.y1 - rc.y0 + 1) * cell, depth), F * CFrame.new(-cx, cy, -depth / 2), color, mat or K.M.SmoothPlastic, { decor = true })
				end
			end
		end
	end
	return m, maxW, totalH
end
function H.sign3d(parent, name, F, lines, cell, color, plate, pad)
	local m = Instance.new("Model") m.Name = name m.Parent = parent
	local tm, w, h = H.text3d(m, "Letters", F * CFrame.new(0, 0, -0.6), lines, cell, cell * 1.4, color)
	pad = pad or cell * 3
	K.part(m, "Plate", Vector3.new(w + pad * 2, h + pad * 2, 1.2), F, plate or H.C.DK2, K.M.SmoothPlastic, { decor = true })
	K.part(m, "PlateRim", Vector3.new(w + pad * 2 + 0.8, h + pad * 2 + 0.8, 0.8), F * CFrame.new(0, 0, 0.3), color, K.M.Neon, { decor = true, neon = true })
	return m, w + pad * 2, h + pad * 2
end
function H.hazard(part, face, tile)
	local g = K.gui(part, face, 8, 1)
	g.LightInfluence = 1
	local sz = part.Size
	local w, h
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then w, h = sz.X, sz.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then w, h = sz.Z, sz.Y else w, h = sz.X, sz.Z end
	tile = tile or h
	local kps, n = {}, 8
	for i = 0, n - 1 do
		local col = (i % 2 == 0) and H.C.YEL or H.C.BLK
		table.insert(kps, ColorSequenceKeypoint.new(i / n, col))
		table.insert(kps, ColorSequenceKeypoint.new(math.min((i + 1) / n - 0.0005, 1), col))
	end
	kps[#kps] = ColorSequenceKeypoint.new(1, kps[#kps].Value)
	local nx = math.ceil(w / tile)
	for i = 0, nx - 1 do
		local f = K.frame(g, Color3.new(1, 1, 1), UDim2.fromScale(i * tile / w, 0), UDim2.new(tile / w, 1, 1, 0))
		local gr = Instance.new("UIGradient") gr.Color = ColorSequence.new(kps) gr.Rotation = 45 gr.Parent = f
	end
	return g
end
function H.octRing(parent, name, F, r, t, depth, color, mat, opts)
	local s = 2 * r * math.tan(math.rad(22.5))
	for i = 0, 7 do
		local th = math.rad(i * 45)
		K.part(parent, name, Vector3.new(t, s + t * 0.83, depth), F * CFrame.new(r * math.cos(th), r * math.sin(th), 0) * CFrame.Angles(0, 0, th), color, mat or K.M.SmoothPlastic, opts)
	end
end
function H.disc(parent, name, F, radius, thick, color, mat, opts)
	local p = K.part(parent, name, Vector3.new(thick, radius * 2, radius * 2), F * CFrame.Angles(0, math.pi / 2, 0), color, mat, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end
H.K = K
return H
