--[[
	VANTAGE — EquipmentStatsUI (2026-11-18)
	A stat card for one piece of equipment: name, slot + rarity, the three stats as numbers with the difference
	from the starter item (green better / red worse) and a bar, then the ability, what it does and its trade-off.
	Used by LoadoutHS (Edit Loadout > EQUIPMENT, right of the list) and InventoryHS (hover tooltip).

	local card = EquipmentStatsUI.new(HS, parent, { Position = UDim2, Width = 330, ZIndex = 30, Light = false })
	card:Set(itemId)      card.Frame.Visible = ...      EquipmentStatsUI.Lines(itemId) -> rows (no UI)
]]
local Catalog = require(script.Parent:WaitForChild("EquipmentCatalog"))

local UI = {}
local RGB = Color3.fromRGB
local O = UDim2.fromOffset
local GOOD, BAD, SAME = RGB(117, 251, 134), RGB(255, 110, 120), RGB(150, 200, 255)

local function trim(n: number, whole: boolean?): string
	if whole then
		return tostring(if n < 0 then -math.floor(-n + 0.5) else math.floor(n + 0.5))
	end
	local s = string.format("%.2f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
end

-- key, label, unit, "high" | "low" is better, bar max
UI.Rows = {
	Pack = {
		{ "MaxShield", "SHIELD", "", "high", 110, true },
		{ "RegenDelay", "RECHARGE DELAY", "s", "low", 5 },
		{ "RegenRate", "RECHARGE SPEED", "/s", "high", 60 },
	},
	Hook = {
		{ "Range", "RANGE", " st", "high", 240, true },
		{ "Cooldown", "COOLDOWN", "s", "low", 7 },
		{ "Charges", "CHARGES", "", "high", 2 },
	},
}

function UI.Lines(id: string)
	local it = Catalog.ById[id]
	if not it then
		return {}
	end
	local statsOf = if it.Slot == "Pack" then Catalog.PackStatsFor else Catalog.HookStatsFor
	local st, base = statsOf(id), statsOf(Catalog.Default[it.Slot])
	local out = {}
	for _, r in UI.Rows[it.Slot] do
		local v, b = st[r[1]], base[r[1]]
		local d = v - b
		local good = nil
		if math.abs(d) > 1e-3 then
			good = if r[4] == "high" then d > 0 else d < 0
		end
		local frac = if r[4] == "low" then 1 - math.clamp(v / r[5], 0, 0.95) else math.clamp(v / r[5], 0, 1)
		table.insert(out, {
			Label = r[2], Value = trim(v, r[6]) .. r[3],
			Delta = if good == nil then "" else ((if d > 0 then "+" else "") .. trim(d, r[6]) .. r[3]),
			Good = good, Frac = math.max(0.05, frac),
		})
	end
	return out
end

local Card = {}
Card.__index = Card

function UI.new(HS, parent: Instance, p)
	p = p or {}
	local W, Z = p.Width or 330, p.ZIndex or 30
	local light = p.Light == true -- light background (inventory tooltip): dark outlines on text
	local ink = if light then RGB(10, 6, 20) else RGB(12, 6, 24)
	local self = setmetatable({}, Card)
	local f = HS.new("Frame", { Name = "EquipStats", BackgroundColor3 = RGB(12, 9, 24), BackgroundTransparency = if light then 1 else 0.06,
		Position = p.Position or O(0, 0), Size = O(W, 10), ZIndex = Z }, parent)
	if not light then
		HS.corner(f, 20)
		HS.stroke(f, 4, RGB(90, 70, 150))
		HS.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(30, 20, 56), RGB(10, 7, 20)) }, f)
	end
	self.Frame = f
	local pad = if light then 10 else 16
	local y = if light then 0 else 12
	local function text(props)
		props.Stroke = if light then math.min(props.Stroke or 2, 1.4) else (props.Stroke or 2)
		props.StrokeColor = ink
		props.ZIndex = Z + 1
		return HS.text(f, props)
	end
	if not light then
		self.Name = text({ Text = "", TextSize = 26, Stroke = 3, Position = O(pad, y), Size = O(W - pad * 2, 32), X = Enum.TextXAlignment.Left })
		y += 32
		self.Sub = text({ Text = "", Font = HS.MontX, TextSize = 15, Color = RGB(206, 192, 232), Position = O(pad, y), Size = O(W - pad * 2, 20), X = Enum.TextXAlignment.Left })
		y += 30
	end
	self.Rows = {}
	for i = 1, 3 do
		local lab = text({ Text = "", Font = HS.MontX, TextSize = 15, Position = O(pad, y), Size = O(W * 0.55, 20), X = Enum.TextXAlignment.Left })
		local val = text({ Text = "", TextSize = 18, Position = O(W * 0.45, y - 1), Size = O(W * 0.55 - pad, 22), X = Enum.TextXAlignment.Right, Rich = true })
		local track = HS.new("Frame", { BackgroundColor3 = RGB(36, 28, 60), BorderSizePixel = 0, Position = O(pad, y + 23), Size = O(W - pad * 2, 9), ZIndex = Z + 1 }, f)
		HS.corner(track, UDim.new(0.5, 0))
		local fill = HS.new("Frame", { BackgroundColor3 = SAME, BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1), ZIndex = Z + 2 }, track)
		HS.corner(fill, UDim.new(0.5, 0))
		self.Rows[i] = { Lab = lab, Val = val, Fill = fill }
		y += 42
	end
	y += 2
	local div = HS.new("Frame", { BackgroundColor3 = RGB(110, 100, 130), BorderSizePixel = 0, Position = O(pad, y), Size = O(W - pad * 2, 2), ZIndex = Z + 1 }, f)
	HS.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, div)
	y += 8
	self.Ability = text({ Text = "", TextSize = 19, Stroke = 2.2, Color = RGB(255, 210, 90), Position = O(pad, y), Size = O(W - pad * 2, 24), X = Enum.TextXAlignment.Left })
	y += 26
	local desc = HS.new("TextLabel", { Name = "Desc", BackgroundTransparency = 1, Text = "", FontFace = HS.MontX or HS.Font, TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Position = O(pad, y), Size = O(W - pad * 2, 74), ZIndex = Z + 1 }, f)
	HS.stroke(desc, if light then 1.1 else 1.6, ink)
	self.Desc = desc
	y += 76
	self.Cost = text({ Text = "", Font = HS.MontX, TextSize = 14, Color = RGB(206, 192, 232), Position = O(pad, y), Size = O(W - pad * 2, 20), X = Enum.TextXAlignment.Left })
	y += if light then 22 else 30
	f.Size = O(W, y)
	self.Height = y
	return self
end

function Card:Set(id: string?)
	local it = id and Catalog.ById[id]
	self.Frame.Visible = it ~= nil
	if not it then
		return
	end
	self.Id = id
	if self.Name then
		self.Name.Text = it.Name
		self.Name.TextColor3 = (it.Color :: Color3):Lerp(Color3.new(1, 1, 1), 0.35)
		self.Sub.Text = string.upper((Catalog.SlotNames[it.Slot] or it.Slot) .. "  ·  " .. (it.Rarity or "")) .. (if it.Starter then "  ·  STARTER" else "")
	end
	for i, line in UI.Lines(id) do
		local r = self.Rows[i]
		r.Lab.Text = line.Label
		local col = if line.Good == true then GOOD elseif line.Good == false then BAD else SAME
		r.Val.Text = line.Value .. (if line.Delta ~= "" then string.format('  <font color="#%s">%s</font>', col:ToHex(), line.Delta) else "")
		r.Fill.BackgroundColor3 = col
		r.Fill.Size = UDim2.fromScale(line.Frac, 1)
	end
	local ab = it.Ability or {}
	if ab.Id == "None" or not ab.Id then
		self.Ability.Text = "NO ABILITY  ·  STANDARD ISSUE"
		self.Desc.Text = (ab.Text or "") .. " The baseline the other stats are compared to."
		self.Cost.Text = ""
	else
		self.Ability.Text = "ABILITY: " .. string.upper(ab.Name or ab.Id)
		self.Desc.Text = ab.Text or ""
		self.Cost.Text = "Trade-off: " .. tostring(ab.Cost or "none")
	end
end

return UI
