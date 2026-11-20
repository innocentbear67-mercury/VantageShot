--!nocheck
--[[
	ShopHS - VantageShot Shop modal (2026-11-16).
	Hypershot shop construction (title breaking the top border, red X, hex rail that jumps through one long scroll),
	in VantageShot's own violet skin and wording. Sections: Premium Crates, Deals, Gamepasses, REQ Packs (ShopConfig).
	Purchases prompt MarketplaceService; ShopService grants on the server and fires Remotes.ShopNotify for the toast.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local Remotes = Vantage:WaitForChild("Remotes")
local Shop = require(Vantage:WaitForChild("Shop"):WaitForChild("ShopConfig"))
local CrateConfig = require(Vantage:WaitForChild("Crates"):WaitForChild("CrateConfig"))
local SigCat = require(Vantage:WaitForChild("Signatures"):WaitForChild("SignatureCatalog"))
local IchorCfg = require(Vantage:WaitForChild("Ichor"):WaitForChild("IchorConfig"))
local Reveal = require(script.Parent:WaitForChild("SignatureReveal"))

local player = Players.LocalPlayer
local V2, O, S = Vector2.new, UDim2.fromOffset, UDim2.fromScale
local RGB = Color3.fromRGB
local CS, CK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NK = NumberSequence.new, NumberSequenceKeypoint.new
local WHITE = Color3.new(1, 1, 1)
local ROBUX = utf8.char(0xE002)
local LEFT = Enum.TextXAlignment.Left

local HEX = "rbxassetid://76747690983634"
local RAYS = "rbxassetid://113538852110620"
local BLOOM = "rbxassetid://103142630740394"
local GLOW = "rbxassetid://104786452938879"
local STAR = "rbxassetid://107113949398119"
-- painted card faces (cards.py): hot centre, fine rays, streaks, halftone, sparkles, vignette, gloss, bevel rim
local ART = {
	hero = 94064930593619, apex = 89515719064108, prestige = 109449799801339, recruit = 104933582504492, specops = 138942497801887,
	vip = 81040783658284, req2x = 102836953814365, req_s = 93856987450782, req_m = 125732064115769, req_l = 139223208464724, req_xl = 92833166653335,
}
local RunService = game:GetService("RunService")
local PolicyService = game:GetService("PolicyService")
ART.daily, ART.commander, ART.seasonpass = 128261165210728, 132559031753806, 91211646590307
-- anime key art layers (Gemini, user-supplied): bg with the subject inpainted out + fg cutout, 1024 px wide textures
-- painted bevel hexes for the rail (hexart.py) + soft hex glow
local HEXART = { Crates = "rbxassetid://105691690329170", Deals = "rbxassetid://136619029238073", Passes = "rbxassetid://112571867886804", Req = "rbxassetid://86124473377135" }
local HEXGLOW = "rbxassetid://87371756847851"
local LAYER = {
	equip = { Bg = 139563251216147, Fg = 131873164199843, W = 1024, H = 471 },
	commander = { Bg = 80136994474810, Fg = 91945291579110, W = 1024, H = 544 },
	daily = { Bg = 97143552848233, Fg = 118883371297222, W = 1024, H = 544 },
	req2x = { Bg = 137069754124638, Fg = 122121336305214, W = 1024, H = 791 },
	req_l = { Bg = 76969116728255, Fg = 101892365525049, W = 844, H = 1024 },
	req_m = { Bg = 72255100879315, Fg = 113707123684396, W = 844, H = 1024 },
	req_s = { Bg = 120890926910393, Fg = 126929361892136, W = 844, H = 1024 },
	req_xl = { Bg = 86944389434610, Fg = 96063758555679, W = 844, H = 1024 },
	seasonpass = { Bg = 82609434212132, Fg = 95584879202501, W = 1024, H = 544 },
	vip = { Bg = 96325591471276, Fg = 81154625809285, W = 1024, H = 505 },
	hero = { Bg = 129640266531610, Fg = 75904302028705, W = 1024, H = 303 },
	featured = { Bg = 119945025328475, Fg = 77340668729273, W = 1024, H = 303 },
	apex = { Bg = 87830602604413, Fg = 129379780976547, W = 1024, H = 471 },
	prestige = { Bg = 76512400038127, Fg = 89129348284569, W = 1024, H = 471 },
	recruit = { Bg = 132196460256435, Fg = 84539302691171, W = 1024, H = 544 },
}

local C = { Panel = RGB(26, 10, 48), Stripe = RGB(17, 6, 33), Edge = RGB(150, 80, 255), Ink = RGB(14, 6, 28), Muted = RGB(206, 190, 236), Gold = RGB(255, 206, 84) }
local GREEN = { Rim = RGB(53, 80, 19), Top0 = RGB(176, 249, 81), Top1 = RGB(143, 239, 74), Ink = RGB(25, 45, 12) }
local GOLD = { Rim = RGB(120, 70, 10), Top0 = RGB(255, 226, 120), Top1 = RGB(255, 172, 40), Ink = RGB(70, 36, 4) }
local GREY = { Rim = RGB(46, 44, 58), Top0 = RGB(160, 156, 176), Top1 = RGB(116, 112, 132), Ink = RGB(30, 28, 40) }
local PW, PH = 1240, 760
local CW = 1150
local SEC = {
	Crates = RGB(150, 80, 255),
	Deals = RGB(236, 72, 86),
	Passes = RGB(255, 190, 50),
	Req = RGB(70, 214, 120),
	Ord = RGB(255, 150, 40), -- 2026-11-17: Ordnance packs
}
-- ORD pack cards: layered key art from the user's Gemini images (bg with the subject inpainted out + fg cutout,
-- 844x1024 like the REQ cards; ~/roblox-game/vantage_vfx/ord/ord_*_v1.png). Animated by the LAYER path in _card/_animate:
-- Ken Burns drift, fg parallax + hover push, rising embers, light sweep, glow and stars.
LAYER.ord_s = { Bg = 137850359287188, Fg = 73689334071016, W = 844, H = 1024 }
LAYER.ord_m = { Bg = 117469444201329, Fg = 91065177341025, W = 844, H = 1024 }
LAYER.ord_l = { Bg = 89758895466173, Fg = 97341084330286, W = 844, H = 1024 }
HEXART.Ord = HEXART.Passes -- gold hex, tinted orange below
-- 2026-11-20: SIGNATURES section (Ichor Crate + Daily Shop). ICHOR_ART.Crate = the crate render and LAYER.ichor = the banner
-- key art ({ Bg, Fg, W, H }) once the user's images are uploaded; until then the Prestige crate + "featured" art stand in.
SEC.Ichor = RGB(110, 190, 255)
SEC.IchorPack = RGB(255, 196, 70) -- 2026-11-20: Ichor packs (Robux)
HEXART.IchorPack = HEXART.Passes
-- pack card art: LAYER.ichor_s / ichor_m / ichor_l ({ Bg, Fg, W = 844, H = 1024 }) once the key art is uploaded;
-- until then a gold-tinted painted face with the Ichor drop on it
HEXART.Ichor = HEXART.Crates
local CA = SigCat.Crate.Art or {}
if CA.BannerBg and CA.BannerFg then LAYER.ichor = { Bg = CA.BannerBg, Fg = CA.BannerFg, W = CA.BannerW or 1024, H = CA.BannerH or 294 } end
local function aid(n) return if n then "rbxassetid://" .. n else nil end
local ICHOR_ART = { Crate = aid(CA.Hero), Lid = aid(CA.Lid), Body = aid(CA.Body) }

local function fmt(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function floorText(crate)
	for _, t in CrateConfig.Tiers do
		if (crate.Odds[t] or 0) > 0 then
			return t .. " or better!"
		end
	end
	return ""
end

local ShopUI = {}
ShopUI.__index = ShopUI

function ShopUI.new(layer, env)
	local self = setmetatable({ Env = env, HS = env.HS, Prices = {}, SecY = {}, Hex = {}, Active = nil, Fx = {}, Stars = {}, Layers = {}, Restricted = false }, ShopUI)
	task.spawn(function()
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		self.Restricted = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == true
		self:_render()
	end)
	self:_build(layer)
	self:_buildToast()
	task.spawn(function()
		local ev = Remotes:WaitForChild("ShopNotify", 30)
		if ev then
			ev.OnClientEvent:Connect(function(p)
				if type(p) == "table" then
					self:_toast(p.Title or "Purchased!", p.Text or "", true)
				end
			end)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if self.Root.Visible then self:_animate(os.clock()) end
	end)
	player.AttributeChanged:Connect(function(a)
		if a == "Ichor" or a == "OwnedSignatures" then
			self:_renderSig()
			return
		end
		if a:sub(1, 5) == "Pass_" or a:sub(1, 11) == "ShopBought_" or a == "PassPremium" then
			self:_render()
		end
	end)
	return self
end

-- raised pill: dark rim, gradient face, gloss, bottom lip (same build as the Cases pills)
function ShopUI:_pill(parent, p)
	local HS, z = self.HS, p.Z or 27
	local b = HS.new("TextButton", { Name = p.Name or "Pill", Text = "", AutoButtonColor = false, BackgroundColor3 = p.Rim, AnchorPoint = p.AnchorPoint or V2(0, 0), Position = p.Position, Size = p.Size, ZIndex = z }, parent)
	HS.corner(b, p.R or 11)
	local face = HS.new("Frame", { Name = "Face", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(3.4, 1.6), Size = UDim2.new(1, -6.8, 1, -7), ZIndex = z }, b)
	HS.corner(face, (p.R or 11) - 2)
	local grad = HS.new("UIGradient", { Rotation = 90, Color = CS(p.Top0, p.Top1) }, face)
	HS.new("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, Position = O(5, 2), Size = UDim2.new(1, -10, 0.42, 0), ZIndex = z }, face)
	local t = HS.text(b, { Name = "Label", Text = p.Text, TextSize = p.TextSize or 30, Stroke = 2.8, StrokeColor = p.Ink, Position = O(0, -2), Size = S(1, 1), ZIndex = z + 1 })
	HS.press(b, p.OnClick, { Hover = 1.06, Press = 0.94, Sound = p.Sound })
	return b, t, grad
end

function ShopUI:_price(parent, item, kind, pos, size)
	local b, t, g = self:_pill(parent, { Name = "Buy", Text = ROBUX .. " " .. fmt(item.Robux), TextSize = 32, AnchorPoint = V2(0.5, 0), Position = pos, Size = size, Rim = GREEN.Rim, Top0 = GREEN.Top0, Top1 = GREEN.Top1, Ink = GREEN.Ink, Sound = false, OnClick = function()
		self:_buy(item, kind)
	end })
	table.insert(self.Prices, { Item = item, Kind = kind, B = b, T = t, G = g })
	return b
end

-- card: rounded CanvasGroup background (diagonal gradient + painted rays + bloom + bottom shade) with a neon rim
function ShopUI:_card(parent, name, pos, size, art, glowCol, nStars)
	local HS = self.HS
	local w, h = size.X.Offset, size.Y.Offset
	local glow = HS.new("ImageLabel", { Name = name .. "_Glow", BackgroundTransparency = 1, Image = GLOW, ImageColor3 = glowCol, ImageTransparency = 0.4, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.9, AnchorPoint = V2(0.5, 0.5), Position = O(pos.X.Offset + w / 2, pos.Y.Offset + h / 2), Size = O(w + 110, h + 110), ZIndex = 22 }, parent)
	local L = LAYER[art]
	local card
	if L then
		card = HS.new("ImageLabel", { Name = name, BackgroundColor3 = RGB(8, 4, 16), Image = "rbxassetid://" .. L.Bg, ImageRectSize = V2(L.W, L.H), Position = pos, Size = size, ZIndex = 23 }, parent)
		HS.corner(card, 18)
		local fg = HS.new("ImageLabel", { Name = "Fg", BackgroundTransparency = 1, Image = "rbxassetid://" .. L.Fg, ImageRectSize = V2(L.W, L.H), Size = S(1, 1), ZIndex = 24 }, card)
		HS.corner(fg, 18)
		local gl = HS.new("Frame", { Name = "Gloss", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = S(1, 0.4), ZIndex = 25 }, card)
		HS.corner(gl, 18)
		HS.new("UIGradient", { Rotation = 90, Transparency = NS({ NK(0, 0.84), NK(1, 1) }) }, gl)
		HS.stroke(card, 4, glowCol:Lerp(WHITE, 0.3))
		local ent = { Bg = card, Fg = fg, W = L.W, H = L.H, Phase = math.random() * 30, Hover = 0, HoverT = 0, Embers = {}, CW = w, CH = h }
		card.MouseEnter:Connect(function() ent.HoverT = 1 end)
		card.MouseLeave:Connect(function() ent.HoverT = 0 end)
		for _ = 1, math.floor(w / 60) + 4 do
			local sz = math.random(3, 7)
			local f = HS.new("Frame", { Name = "Ember", BackgroundColor3 = glowCol:Lerp(WHITE, math.random() * 0.6), BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Size = O(sz, sz), ZIndex = 25 }, card)
			HS.corner(f, UDim.new(0.5, 0))
			table.insert(ent.Embers, { F = f, X = math.random() * w, Y = math.random() * h, V = 16 + math.random() * 34, Sway = math.random() * 6.28 })
		end
		table.insert(self.Layers, ent)
	else
		card = HS.new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = "rbxassetid://" .. ART[art], Position = pos, Size = size, ZIndex = 23 }, parent)
	end
	local cg = HS.new("CanvasGroup", { Name = "Sweep", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 26 }, card)
	HS.corner(cg, 18)
	local band = HS.new("Frame", { Name = "Band", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = S(-0.3, 0.5), Size = UDim2.new(0, math.max(60, w * 0.12), 2.4, 0), Rotation = 22, ZIndex = 26 }, cg)
	HS.new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.6), NK(1, 1) }) }, band)
	table.insert(self.Fx, { Glow = glow, Band = band, Phase = math.random() * 4.5 })
	for _ = 1, nStars or 3 do
		local sz = math.random(18, 34)
		local st = HS.new("ImageLabel", { Name = "Spark", BackgroundTransparency = 1, Image = STAR, ImageColor3 = WHITE:Lerp(glowCol, 0.25), AnchorPoint = V2(0.5, 0.5), Position = O(math.random(20, w - 20), math.random(16, h - 16)), Size = O(sz, sz), ZIndex = 26 }, card)
		table.insert(self.Stars, { I = st, Sz = sz, P = math.random() * 6, Spd = 1.4 + math.random() * 1.6, W = w, H = h })
	end
	return card
end

-- name, bullet lines, crossed-out price + discount, price pill (deal cards)
function ShopUI:_dealInfo(card, it, cx, h, top)
	top = top or 18
	self:_text(card, { Text = it.Name, TextSize = 36, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = O(cx, top), Size = O(276, 46) })
	for j, line in it.Lines or {} do
		self:_text(card, { Text = "• " .. line, TextSize = 21, Font = self.HS.MontX, X = LEFT, Position = O(cx - 132, top + 54 + (j - 1) * 30), Size = O(268, 28) })
	end
	if it.Was then
		self:_text(card, { Text = ROBUX .. " " .. fmt(it.Was), TextSize = 24, Color = RGB(255, 110, 110), X = LEFT, Position = O(cx - 132, h - 118), Size = O(120, 30) })
		self.HS.new("Frame", { BackgroundColor3 = RGB(255, 70, 70), BorderSizePixel = 0, Position = O(cx - 136, h - 104), Size = O(100, 4), Rotation = -8, ZIndex = 28 }, card)
		local off = math.floor((1 - it.Robux / it.Was) * 100 + 0.5)
		self:_chip(card, "-" .. off .. "%", O(cx - 6, h - 120), O(84, 34), RGB(255, 70, 80), RGB(70, 6, 12))
	end
	self:_price(card, it, "product", O(cx, h - 74), O(250, 58))
end

function ShopUI:_gun(parent, key, pos, size, rot, glowCol)
	local ok, g = pcall(CrateConfig.Gun, key)
	if not (ok and g) then return end
	self.HS.new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = glowCol, ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = O(pos.X.Offset + size.X.Offset / 2, pos.Y.Offset + size.Y.Offset / 2), Size = O(size.X.Offset * 1.1, size.X.Offset * 1.1), ZIndex = 24 }, parent)
	return self.HS.new("ImageLabel", { BackgroundTransparency = 1, Image = g.Image, ImageRectOffset = g.Offset, ImageRectSize = g.Size, ScaleType = Enum.ScaleType.Fit, Position = pos, Size = size, Rotation = rot or 0, ZIndex = 25 }, parent)
end

function ShopUI:_chip(parent, text, pos, size, bg, ink, anchor)
	local HS = self.HS
	local f = HS.new("Frame", { Name = "Chip", BackgroundColor3 = bg, AnchorPoint = anchor or V2(0, 0), Position = pos, Size = size, ZIndex = 28 }, parent)
	HS.corner(f, 9)
	HS.stroke(f, 2.6, ink)
	HS.text(f, { Text = text, TextSize = 22, Stroke = 2.2, StrokeColor = ink, Size = S(1, 1), Position = O(0, -1), ZIndex = 29 })
	return f
end

function ShopUI:_header(parent, title, y, col)
	local HS = self.HS
	HS.text(parent, { Name = "H_" .. title, Text = title, TextSize = 46, Stroke = 4, StrokeColor = C.Ink, AnchorPoint = V2(0.5, 0), Position = O(CW / 2, y), Size = O(520, 58), ZIndex = 24 })
	for side = -1, 1, 2 do
		local bar = HS.new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = V2(if side < 0 then 1 else 0, 0.5), Position = O(CW / 2 + side * 236, y + 30), Size = O(300, 5), ZIndex = 23 }, parent)
		HS.new("UIGradient", { Transparency = if side < 0 then NS(1, 0) else NS(0, 1) }, bar)
		local d = HS.new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = O(CW / 2 + side * 226, y + 30), Size = O(16, 16), Rotation = 45, ZIndex = 24 }, parent)
		HS.stroke(d, 2.5, C.Ink)
	end
end

function ShopUI:_img(parent, image, pos, size, z)
	return self.HS.new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Position = pos, Size = size, ZIndex = z or 24 }, parent)
end

function ShopUI:_text(parent, p)
	p.Stroke = p.Stroke or 2.6
	p.StrokeColor = p.StrokeColor or C.Ink
	p.ZIndex = p.ZIndex or 27
	return self.HS.text(parent, p)
end

------------------------------------------------------------------ sections
function ShopUI:_crates(sc, y)
	local hero = self:_card(sc, "Hero", O(0, y), O(CW, 340), "hero", RGB(190, 90, 255), 6)
	self:_text(hero, { Text = "PREMIUM CRATES", TextSize = 64, Stroke = 6, AnchorPoint = V2(0.5, 0), Position = O(CW / 2 - 60, 194), Size = O(640, 78) })
	self:_text(hero, { Text = "Mythic, Legendary and Godly skins inside", TextSize = 24, Font = self.HS.MontX, AnchorPoint = V2(0.5, 0), Position = O(CW / 2 - 60, 272), Size = O(600, 32) })
	self:_pill(hero, { Name = "Odds", Text = "VIEW ODDS", TextSize = 28, AnchorPoint = V2(0.5, 0), Position = O(CW - 150, 262), Size = O(230, 56), Rim = GOLD.Rim, Top0 = GOLD.Top0, Top1 = GOLD.Top1, Ink = GOLD.Ink, OnClick = function()
		if self.Env.Open then self.Env.Open("Cases") end
	end })
	y += 360
	for i, k in { "crate_apex_1", "crate_apex_3", "crate_prestige_1", "crate_prestige_3" } do
		local it = Shop.ByKey[k]
		local crate = CrateConfig.ById[it.Crate]
		local light = crate.Light or WHITE
		local x, yy = ((i - 1) % 2) * 585, y + math.floor((i - 1) / 2) * 280
		local card = self:_card(sc, k, O(x, yy), O(565, 260), if it.Crate == "Apex" then "apex" else "prestige", if it.Crate == "Apex" then RGB(170, 100, 255) else RGB(255, 190, 60), 3)
		if it.Count > 1 then
			self:_text(card, { Text = "x" .. it.Count, TextSize = 60, Stroke = 6, X = LEFT, Position = O(22, 12), Size = O(110, 70) })
		end
		self:_text(card, { Text = it.Name .. " x" .. it.Count, TextSize = 38, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = O(424, 30), Size = O(266, 48) })
		self:_text(card, { Text = floorText(crate), TextSize = 22, Font = self.HS.MontX, Color = light:Lerp(WHITE, 0.55), AnchorPoint = V2(0.5, 0), Position = O(424, 82), Size = O(266, 28) })
		if it.Count > 1 then
			local one = Shop.ByKey[k:gsub("_%d$", "_1")]
			if one then
				local save = math.floor((1 - it.Robux / (one.Robux * it.Count)) * 100 + 0.5)
				self:_chip(card, "SAVE " .. save .. "%", O(424, 122), O(130, 34), RGB(255, 196, 50), RGB(80, 40, 4), V2(0.5, 0))
			end
		end
		self:_price(card, it, "product", O(424, 182), O(236, 56))
	end
	-- equipment crates (shield packs + grappling hooks); painted placeholder faces until their own art exists
	y += 560
	self:_header(sc, "EQUIPMENT CRATES", y, RGB(64, 224, 255))
	y += 80
	for i, k in { "crate_eliteequip_1", "crate_eliteequip_3", "crate_equip_1", "crate_equip_3" } do
		local it = Shop.ByKey[k]
		local crate = it and CrateConfig.ById[it.Crate]
		if crate then
			local elite = it.Crate == "EliteEquipment"
			local x, yy = ((i - 1) % 2) * 585, y + math.floor((i - 1) / 2) * 280
			local card = self:_card(sc, k, O(x, yy), O(565, 260), "equip", if elite then RGB(64, 224, 255) else RGB(110, 150, 255), 3)
			self:_img(card, crate.Art.Full, O(196, 146), O(140, 106), 26)
			if it.Count > 1 then
				self:_text(card, { Text = "x" .. it.Count, TextSize = 60, Stroke = 6, X = LEFT, Position = O(22, 12), Size = O(110, 70) })
			end
			self:_text(card, { Text = it.Name .. " x" .. it.Count, TextSize = 38, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = O(424, 30), Size = O(266, 48) })
			self:_text(card, { Text = "Equipment Shards", TextSize = 22, Font = self.HS.MontX, Color = RGB(190, 236, 255), AnchorPoint = V2(0.5, 0), Position = O(424, 82), Size = O(266, 28) })
			if it.Count > 1 then
				local one = Shop.ByKey[k:gsub("_%d$", "_1")]
				if one then
					local save = math.floor((1 - it.Robux / (one.Robux * it.Count)) * 100 + 0.5)
					self:_chip(card, "SAVE " .. save .. "%", O(424, 122), O(130, 34), RGB(255, 196, 50), RGB(80, 40, 4), V2(0.5, 0))
				end
			elseif elite then
				self:_chip(card, "MYTHIC+", O(424, 122), O(130, 34), RGB(64, 224, 255), RGB(6, 40, 70), V2(0.5, 0))
			end
			self:_price(card, it, "product", O(424, 182), O(236, 56))
		end
	end
	return y + 560
end

function ShopUI:_daily(card)
	local HS = self.HS
	self:_chip(card, "DAILY DEAL", O(16, 16), O(150, 34), RGB(255, 140, 40), RGB(70, 24, 0))
	self.DailyTimer = self:_text(card, { Text = "", TextSize = 21, Font = HS.MontX, Color = RGB(255, 226, 180), X = LEFT, Position = O(176, 18), Size = O(240, 30) })
	self.DailyPanels = {}
	for _, key in Shop.Daily do
		local it = Shop.ByKey[key]
		local pnl = HS.new("Frame", { Name = key, BackgroundTransparency = 1, Size = S(1, 1), Visible = false, ZIndex = 26 }, card)
		if it.Crate then
			self:_text(pnl, { Text = "x" .. (it.Grant.Crates[it.Crate] or 1), TextSize = 64, Stroke = 6, Position = O(190, 200), Size = O(100, 76) })
		end
		self:_dealInfo(pnl, it, 424, 300, 58)
		self.DailyPanels[key] = pnl
	end
end

function ShopUI:_deals(sc, y)
	self:_header(sc, "DEALS", y, SEC.Deals)
	y += 76
	-- featured weapon drop (gun + crates)
	local ft = Shop.ByKey.deal_featured
	local f = self:_card(sc, "deal_featured", O(0, y), O(CW, 340), "featured", RGB(190, 100, 255), 6)
	self:_chip(f, "FEATURED WEAPON", O(650, 22), O(220, 34), RGB(200, 120, 255), RGB(30, 8, 50))
	self:_chip(f, "ONE-TIME", O(880, 22), O(130, 34), C.Gold, RGB(80, 40, 4))
	self:_text(f, { Text = ft.Name, TextSize = 54, Stroke = 5, X = LEFT, Position = O(650, 64), Size = O(480, 64) })
	for j, line in ft.Lines do
		self:_text(f, { Text = "• " .. line, TextSize = 24, Font = self.HS.MontX, X = LEFT, Position = O(654, 134 + (j - 1) * 32), Size = O(460, 30) })
	end
	self:_text(f, { Text = ROBUX .. " " .. fmt(ft.Was), TextSize = 26, Color = RGB(255, 110, 110), X = LEFT, Position = O(654, 268), Size = O(130, 32) })
	self.HS.new("Frame", { BackgroundColor3 = RGB(255, 70, 70), BorderSizePixel = 0, Position = O(650, 283), Size = O(110, 4), Rotation = -8, ZIndex = 28 }, f)
	self:_chip(f, "-" .. math.floor((1 - ft.Robux / ft.Was) * 100 + 0.5) .. "%", O(790, 266), O(84, 34), RGB(255, 70, 80), RGB(70, 6, 12))
	self:_price(f, ft, "product", O(1010, 258), O(230, 58))
	y += 360
	-- recruit | daily
	local rc = Shop.ByKey.deal_recruit
	local r = self:_card(sc, "deal_recruit", O(0, y), O(565, 300), "recruit", RGB(70, 200, 255), 4)
	self:_chip(r, "STARTER", O(16, 16), O(120, 34), RGB(80, 220, 255), RGB(4, 30, 50))
	self:_dealInfo(r, rc, 424, 300)
	local d = self:_card(sc, "daily", O(585, y), O(565, 300), "daily", RGB(255, 150, 60), 4)
	self:_daily(d)
	y += 320
	-- commander (anchor) | season pass (coming soon)
	local cm = Shop.ByKey.deal_commander
	local c = self:_card(sc, "deal_commander", O(0, y), O(565, 300), "commander", RGB(255, 200, 70), 5)
	self:_chip(c, "BEST VALUE", O(16, 16), O(150, 34), C.Gold, RGB(80, 40, 4))
	self:_dealInfo(c, cm, 424, 300)
	local sp = Shop.ByKey.deal_pass
	local p = self:_card(sc, "deal_pass", O(585, y), O(565, 300), "seasonpass", RGB(170, 120, 255), 5)
	self:_chip(p, "COMING SOON", O(16, 16), O(170, 34), RGB(170, 120, 255), RGB(24, 8, 50))
	self:_text(p, { Text = sp.Name, TextSize = 36, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = O(424, 18), Size = O(276, 46) })
	for j, line in sp.Lines do
		self:_text(p, { Text = "• " .. line, TextSize = 21, Font = self.HS.MontX, X = LEFT, Position = O(292, 72 + (j - 1) * 30), Size = O(268, 28) })
	end
	self:_price(p, sp, "product", O(424, 226), O(250, 58))
	return y + 320
end

function ShopUI:_passes(sc, y)
	self:_header(sc, "GAMEPASSES", y, SEC.Passes)
	y += 76
	local vip, dbl = Shop.ByKey.vip, Shop.ByKey.req2x
	-- VIP
	local card = self:_card(sc, "vip", O(0, y), O(690, 340), "vip", RGB(255, 196, 60), 5)
	local t = self:_text(card, { Text = "VIP", TextSize = 100, Fit = false, Stroke = 6, X = LEFT, Position = O(360, 10), Size = O(300, 116) })
	self.HS.new("UIGradient", { Rotation = 90, Color = CS({ CK(0, RGB(255, 246, 170)), CK(0.5, RGB(255, 206, 70)), CK(1, RGB(255, 150, 30)) }) }, t)
	for j, line in vip.Lines do
		self:_text(card, { Text = "• " .. line, TextSize = 26, Font = self.HS.MontX, X = LEFT, Position = O(362, 124 + (j - 1) * 40), Size = O(310, 34) })
	end
	self:_price(card, vip, "pass", O(500, 262), O(250, 58))
	-- Double REQ
	local c2 = self:_card(sc, "req2x", O(710, y), O(440, 340), "req2x", RGB(90, 240, 130), 4)
	local x2 = self:_text(c2, { Text = "2x", TextSize = 90, Fit = false, Stroke = 6, X = LEFT, Position = O(22, 8), Size = O(160, 100) })
	self.HS.new("UIGradient", { Rotation = 90, Color = CS(RGB(220, 255, 210), RGB(90, 230, 120)) }, x2)
	self:_text(c2, { Text = dbl.Name, TextSize = 40, Stroke = 4, AnchorPoint = V2(0.5, 0), Position = O(220, 160), Size = O(380, 48) })
	for j, line in dbl.Lines do
		self:_text(c2, { Text = line, TextSize = 21, Font = self.HS.MontX, AnchorPoint = V2(0.5, 0), Position = O(220, 206 + (j - 1) * 26), Size = O(380, 26) })
	end
	self:_price(c2, dbl, "pass", O(220, 262), O(250, 58))
	return y + 360
end

function ShopUI:_req(sc, y)
	self:_header(sc, "REQ PACKS", y, SEC.Req)
	y += 76
	local tints = { RGB(40, 170, 120), RGB(50, 120, 220), RGB(150, 70, 230), RGB(240, 170, 40) }
	local w = (CW - 60) / 4
	for i, k in { "req_s", "req_m", "req_l", "req_xl" } do
		local it = Shop.ByKey[k]
		local c0 = tints[i]
		local card = self:_card(sc, k, O((i - 1) * (w + 20), y), O(w, 330), k, c0:Lerp(WHITE, 0.2), 3)
		local spots = ({ { { 0, 0, 120 } }, { { -34, 14, 104 }, { 34, -8, 104 } }, { { -46, 18, 92 }, { 0, -12, 100 }, { 46, 18, 92 } }, { { -48, 26, 88 }, { 48, 26, 88 }, { -18, -14, 94 }, { 30, -16, 94 } } })[it.Coins or 1]
		self:_text(card, { Text = fmt(it.Grant.Req), TextSize = 46, Stroke = 4.5, AnchorPoint = V2(0.5, 0), Position = O(w / 2, 168), Size = O(w - 20, 54) })
		self:_text(card, { Text = it.Name, TextSize = 22, Font = self.HS.MontX, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(w / 2, 220), Size = O(w - 20, 28) })
		if it.Bonus then
			self:_chip(card, it.Bonus, O(w - 12, 12), O(88, 34), RGB(255, 150, 40), RGB(80, 30, 4), V2(1, 0))
		end
		if it.Best then
			self:_chip(card, "BEST VALUE", O(12, 12), O(150, 34), C.Gold, RGB(80, 40, 4))
		end
		self:_price(card, it, "product", O(w / 2, 258), O(w - 40, 56))
	end
	return y + 350
end

-- 2026-11-17: Ordnance (ORD) packs: ORD buys Arsenal Crates (gun unlocks)
function ShopUI:_ord(sc, y)
	local HS = self.HS
	self:_header(sc, "ORDNANCE PACKS", y, SEC.Ord)
	y += 76
	local keys = { "ord_s", "ord_m", "ord_l" }
	local tints = { RGB(255, 170, 60), RGB(255, 130, 40), RGB(255, 96, 30) }
	local w = (CW - 60) / 4 -- same card size as the REQ packs, centred
	local x0 = (CW - (3 * w + 40)) / 2
	for i, k in keys do
		local it = Shop.ByKey[k]
		if it then
			local card = self:_card(sc, k, O(x0 + (i - 1) * (w + 20), y), O(w, 330), k, tints[i]:Lerp(WHITE, 0.2), 3)
			self:_text(card, { Text = fmt(it.Grant.Ord) .. " ORD", TextSize = 44, Stroke = 4.5, AnchorPoint = V2(0.5, 0), Position = O(w / 2, 168), Size = O(w - 20, 54) })
			self:_text(card, { Text = string.format("%s · %d crates", it.Name, it.Grant.Ord // 200), TextSize = 20, Font = HS.MontX, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(w / 2, 220), Size = O(w - 20, 28) })
			if it.Bonus then
				self:_chip(card, it.Bonus, O(w - 12, 12), O(88, 34), RGB(255, 150, 40), RGB(80, 30, 4), V2(1, 0))
			end
			if it.Best then
				self:_chip(card, "BEST VALUE", O(12, 12), O(150, 34), C.Gold, RGB(80, 40, 4))
			end
			self:_price(card, it, "product", O(w / 2, 258), O(w - 40, 56))
		end
	end
	return y + 350
end

------------------------------------------------------------------ 2026-11-20: SIGNATURES (Ichor Crate + Daily Shop)
function ShopUI:_ichorCrateArt()
	return ICHOR_ART.Crate or CrateConfig.ById.Prestige.Art.Full
end

-- gold pill with the Ichor drop + amount
function ShopUI:_ichorPill(parent, p)
	local b, t, g = self:_pill(parent, { Name = p.Name or "IchorBuy", Text = "", TextSize = p.TextSize or 32, AnchorPoint = V2(0.5, 0), Position = p.Position, Size = p.Size,
		Rim = GOLD.Rim, Top0 = GOLD.Top0, Top1 = GOLD.Top1, Ink = GOLD.Ink, Sound = false, OnClick = p.OnClick })
	local ih = p.Size.Y.Offset - 16
	local icon = self.HS.new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = IchorCfg.Icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, -2), Size = O(ih, ih), ZIndex = 29 }, b)
	t.Position = O(ih * 0.5, -2)
	return b, t, g, icon
end

function ShopUI:_ichor(sc, y)
	local HS = self.HS
	self:_header(sc, "SIGNATURES", y, SEC.Ichor)
	y += 76
	local hero = self:_card(sc, "IchorCrate", O(0, y), O(CW, 330), if LAYER.ichor then "ichor" else "featured", RGB(110, 190, 255), 6)
	if not LAYER.ichor then -- placeholder: the key art has its own chest; until it's uploaded, show the crate render
		local glow = HS.new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = RGB(255, 196, 80), ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = O(215, 170), Size = O(440, 440), ZIndex = 25 }, hero)
		local rays = HS.new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(255, 214, 120), ImageTransparency = 0.7, AnchorPoint = V2(0.5, 0.5), Position = O(215, 170), Size = O(600, 600), ZIndex = 25 }, hero)
		local crate = self:_img(hero, self:_ichorCrateArt(), O(0, 0), O(300, 280), 26)
		crate.AnchorPoint, crate.Position = V2(0.5, 0.5), O(215, 170)
		self.IchorFx = { Rays = rays, Glow = glow, Crate = crate }
	end
	local cx = 760
	local title = self:_text(hero, { Text = "ICHOR CRATE", TextSize = 66, Stroke = 6, AnchorPoint = V2(0.5, 0), Position = O(cx, 26), Size = O(640, 78) })
	HS.new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 252, 226), RGB(255, 200, 70)) }, title)
	self:_text(hero, { Text = "Unlocks a random Signature you don't own yet", TextSize = 24, Font = HS.MontX, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(cx, 104), Size = O(640, 32) })
	self:_chip(hero, "NO DUPLICATES", O(cx - 172, 148), O(196, 36), RGB(130, 230, 90), RGB(20, 50, 10), V2(0.5, 0))
	local odds = self:_chip(hero, "", O(cx + 104, 148), O(340, 36), RGB(46, 34, 84), RGB(10, 6, 24), V2(0.5, 0))
	self.IchorOdds = odds:FindFirstChildWhichIsA("TextLabel")
	local b, t, g, icon = self:_ichorPill(hero, { Name = "CrateBuy", Position = O(cx, 204), Size = O(320, 70), TextSize = 36, OnClick = function() self:_ichorCrate() end })
	self.IchorCrateBtn = { B = b, T = t, G = g, Icon = icon }
	self.IchorCrateNote = self:_text(hero, { Text = "", TextSize = 20, Font = HS.MontX, Color = RGB(255, 214, 140), AnchorPoint = V2(0.5, 0), Position = O(cx, 286), Size = O(640, 26) })
	y += 350
	self:_text(sc, { Text = "DAILY SHOP", TextSize = 40, Stroke = 4, X = LEFT, Position = O(6, y), Size = O(260, 50), ZIndex = 24 })
	self.SigTimer = self:_text(sc, { Text = "", TextSize = 22, Font = HS.MontX, Color = RGB(255, 226, 180), X = LEFT, Position = O(262, y + 12), Size = O(300, 30), ZIndex = 24 })
	self:_text(sc, { Text = "Buy a Signature outright · new picks every day", TextSize = 20, Font = HS.MontX, Color = C.Muted, X = Enum.TextXAlignment.Right, AnchorPoint = V2(1, 0), Position = O(CW - 6, y + 14), Size = O(560, 28), ZIndex = 24 })
	y += 60
	self.SigSlots = {}
	local w = (CW - 20) / 2
	for i = 1, SigCat.DailyCount do
		self.SigSlots[i] = self:_sigCard(sc, O((i - 1) * (w + 20), y), O(w, 300), i)
	end
	return y + 320
end

function ShopUI:_sigCard(parent, pos, size, i)
	local HS, new = self.HS, self.HS.new
	local w, h = size.X.Offset, size.Y.Offset
	local glow = new("ImageLabel", { Name = "SigGlow" .. i, BackgroundTransparency = 1, Image = GLOW, ImageColor3 = WHITE, ImageTransparency = 0.4, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(130, 130, 410, 310), SliceScale = 0.9, AnchorPoint = V2(0.5, 0.5), Position = O(pos.X.Offset + w / 2, pos.Y.Offset + h / 2), Size = O(w + 110, h + 110), ZIndex = 22 }, parent)
	local card = new("ImageLabel", { Name = "Sig" .. i, BackgroundColor3 = RGB(8, 4, 16), Image = "", ScaleType = Enum.ScaleType.Crop, Position = pos, Size = size, ZIndex = 23 }, parent)
	HS.corner(card, 18)
	HS.stroke(card, 4, WHITE)
	local shade = new("Frame", { Name = "Shade", BackgroundColor3 = RGB(4, 2, 10), BorderSizePixel = 0, Size = S(1, 1), ZIndex = 24 }, card)
	HS.corner(shade, 18)
	new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.4, 0.9), NK(0.6, 0.3), NK(1, 0.12) }) }, shade)
	local mglow = new("ImageLabel", { Name = "ModelGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = WHITE, ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = O(150, h / 2), Size = O(330, 330), ZIndex = 25 }, card)
	local vp = new("ViewportFrame", { Name = "Model", BackgroundTransparency = 1, Position = O(0, 0), Size = O(300, h), ZIndex = 25 }, card)
	local cg = new("CanvasGroup", { Name = "Sweep", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 26 }, card)
	HS.corner(cg, 18)
	local band = new("Frame", { Name = "Band", BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = V2(0.5, 0.5), Position = S(-0.3, 0.5), Size = UDim2.new(0, 70, 2.4, 0), Rotation = 22, ZIndex = 26 }, cg)
	new("UIGradient", { Transparency = NS({ NK(0, 1), NK(0.5, 0.6), NK(1, 1) }) }, band)
	table.insert(self.Fx, { Glow = glow, Band = band, Phase = math.random() * 4.5 })
	local cx = 424
	local chip = self:_chip(card, "", O(cx, 22), O(160, 34), WHITE, RGB(10, 6, 20), V2(0.5, 0))
	local name = self:_text(card, { Text = "", TextSize = 50, Stroke = 5, AnchorPoint = V2(0.5, 0), Position = O(cx, 62), Size = O(266, 60) })
	local title = self:_text(card, { Text = "", TextSize = 22, Font = HS.MontX, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(cx, 122), Size = O(266, 28) })
	local role = self:_text(card, { Text = "", TextSize = 18, Font = HS.MontX, Color = RGB(186, 176, 214), AnchorPoint = V2(0.5, 0), Position = O(cx, 152), Size = O(266, 24) })
	local b, t, g, icon = self:_ichorPill(card, { Name = "Buy", Position = O(cx, 212), Size = O(250, 62), OnClick = function()
		local slot = self.SigSlots and self.SigSlots[i]
		if slot and slot.Id then self:_sigBuy(slot.Id) end
	end })
	return { Card = card, Glow = glow, MGlow = mglow, VP = vp, Chip = chip, ChipT = chip:FindFirstChildWhichIsA("TextLabel"), Name = name, Title = title, Role = role, B = b, T = t, G = g, Icon = icon }
end

function ShopUI:_renderSig()
	if not self.SigSlots then return end
	local owned = SigCat.OwnedSet(player)
	local bal = player:GetAttribute("Ichor") or 0
	local today = SigCat.DailyToday(Workspace:GetServerTimeNow())
	local function paint(btn, off, text)
		local pal = if off then GREY else GOLD
		btn.B.BackgroundColor3 = pal.Rim
		btn.G.Color = CS(pal.Top0, pal.Top1)
		btn.T.Text = text
		btn.Icon.Visible = not off
		btn.B:SetAttribute("Disabled", off and true or nil)
	end
	for i, slot in self.SigSlots do
		local id = today[i]
		local it = id and SigCat.ById[id]
		slot.Card.Visible, slot.Glow.Visible = it ~= nil, it ~= nil
		if it then
			if slot.Id ~= id then
				slot.Id = id
				local tc = SigCat.TierColor[it.Tier] or WHITE
				slot.Card.Image = it.Art or ""
				local st = slot.Card:FindFirstChildOfClass("UIStroke")
				if st then st.Color = tc:Lerp(WHITE, 0.3) end
				slot.Glow.ImageColor3 = tc
				slot.Chip.BackgroundColor3 = tc
				slot.ChipT.Text = it.Tier
				slot.Name.Text = string.upper(it.Name)
				slot.Title.Text = it.Title or ""
				slot.Role.Text = it.Role or ""
				slot.MGlow.ImageColor3 = tc
				slot.Step = Reveal.Model(slot.VP, it, 0.92, math.rad(-38))
			end
			if self.SigConfirm == id then
				paint(slot, false, "CONFIRM?")
			else
				paint(slot, owned[id] == true, if owned[id] then "OWNED" else fmt(it.Price))
			end
		end
	end
	local byTier, _, left = SigCat.CrateOdds(owned)
	if self.IchorOdds then
		self.IchorOdds.Text = if left > 0 then string.format("LEGENDARY %d%%  ·  MYTHIC %d%%", math.floor((byTier.LEGENDARY or 0) * 100 + 0.5), math.floor((byTier.MYTHIC or 0) * 100 + 0.5)) else "EVERY SIGNATURE OWNED"
	end
	if self.IchorCrateBtn then
		if self.SigConfirm == "crate" then
			paint(self.IchorCrateBtn, false, "CONFIRM?")
		else
			paint(self.IchorCrateBtn, left == 0, if left == 0 then "ALL OWNED" else fmt(SigCat.Crate.Price))
		end
		self.IchorCrateNote.Text = if left > 0 then string.format("%d Signature%s left to unlock  ·  you have %s Ichor", left, if left == 1 then "" else "s", fmt(bal)) else ""
	end
end

-- two-tap confirm for big Ichor spends: the first tap turns the pill into CONFIRM? for 3 s
function ShopUI:_confirm(key)
	if self.SigConfirm == key and time() - (self.SigConfirmT or 0) <= 3 then
		self.SigConfirm = nil
		return true
	end
	self.SigConfirm, self.SigConfirmT = key, time()
	self.HS.sound("Click")
	self:_renderSig()
	task.delay(3.05, function()
		if self.SigConfirm == key and time() - self.SigConfirmT >= 3 then
			self.SigConfirm = nil
			self:_renderSig()
		end
	end)
	return false
end

function ShopUI:_ichorCrate()
	local HS = self.HS
	if self.IchorBusy then return end
	local _, _, left = SigCat.CrateOdds(SigCat.OwnedSet(player))
	if left == 0 then HS.sound("Deny") self:_toast("All unlocked", "You already own every Signature") return end
	if (player:GetAttribute("Ichor") or 0) < SigCat.Crate.Price then
		HS.sound("Deny")
		self:_toast("Not enough Ichor", "Brew more at the Ichor Farm (next to Mastery)")
		return
	end
	if not self:_confirm("crate") then return end
	self.IchorBusy = true
	self:_renderSig()
	task.spawn(function()
		local fn = Remotes:FindFirstChild("IchorCrate")
		local ok, res = pcall(function() return fn:InvokeServer() end)
		self.IchorBusy = false
		self:_renderSig()
		if not (ok and type(res) == "table" and res.Ok) then
			HS.sound("Deny")
			self:_toast("Couldn't open", if ok and type(res) == "table" then tostring(res.Error) else "Try again")
			return
		end
		Reveal.Play(HS, res.Id, { CrateArt = self:_ichorCrateArt(), Lid = ICHOR_ART.Lid, Body = ICHOR_ART.Body, Left = res.Left, Pill = function(parent, p) return self:_pill(parent, p) end })
	end)
end

function ShopUI:_sigBuy(id)
	local HS = self.HS
	local it = SigCat.ById[id]
	if not it or SigCat.Owns(player, id) then HS.sound("Deny") return end
	if (player:GetAttribute("Ichor") or 0) < it.Price then
		HS.sound("Deny")
		self:_toast("Not enough Ichor", string.format("%s costs %s Ichor", it.Name, fmt(it.Price)))
		return
	end
	if not self:_confirm(id) then return end
	self:_renderSig()
	local res, buy = Remotes:FindFirstChild("SignatureResult"), Remotes:FindFirstChild("SignatureBuy")
	if not (res and buy) then return end
	local conn
	conn = res.OnClientEvent:Connect(function(ok, rid, reason, kind)
		if kind ~= "Buy" or rid ~= id then return end
		conn:Disconnect()
		if ok then
			Reveal.Play(HS, id, { Pill = function(parent, p) return self:_pill(parent, p) end })
		else
			HS.sound("Deny")
			self:_toast("Couldn't buy", tostring(reason or "Try again"))
		end
		self:_renderSig()
	end)
	task.delay(8, function() if conn.Connected then conn:Disconnect() end end)
	buy:FireServer(id)
end

function ShopUI:_ichorPacks(sc, y)
	local HS = self.HS
	self:_header(sc, "ICHOR PACKS", y, SEC.IchorPack)
	y += 76
	local keys = { "ichor_s", "ichor_m", "ichor_l" }
	local tints = { RGB(255, 214, 120), RGB(255, 190, 70), RGB(255, 160, 40) }
	local w = (CW - 60) / 4 -- same card size as the REQ / ORD packs, centred
	local x0 = (CW - (3 * w + 40)) / 2
	for i, k in keys do
		local it = Shop.ByKey[k]
		if it then
			local layered = LAYER[k] ~= nil
			local card = self:_card(sc, k, O(x0 + (i - 1) * (w + 20), y), O(w, 330), if layered then k else ({ "req_s", "req_m", "req_l" })[i], tints[i]:Lerp(WHITE, 0.2), 3)
			if not layered then
				card.ImageColor3 = RGB(255, 222, 160)
				local sz = 110 + i * 22
				HS.new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = tints[i], ImageTransparency = 0.35, AnchorPoint = V2(0.5, 0.5), Position = O(w / 2, 96), Size = O(sz * 2, sz * 2), ZIndex = 24 }, card)
				HS.new("ImageLabel", { BackgroundTransparency = 1, Image = RAYS, ImageColor3 = WHITE, ImageTransparency = 0.82, AnchorPoint = V2(0.5, 0.5), Position = O(w / 2, 96), Size = O(sz * 2.4, sz * 2.4), ZIndex = 24 }, card)
				for n = 1, i do -- 1 / 2 / 3 drops
					local off = (n - (i + 1) / 2) * sz * 0.42
					HS.new("ImageLabel", { BackgroundTransparency = 1, Image = IchorCfg.Icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = O(w / 2 + off, 96 + math.abs(off) * 0.25), Size = O(sz * (if n == math.ceil((i + 1) / 2) then 1 else 0.82), sz * (if n == math.ceil((i + 1) / 2) then 1 else 0.82)), Rotation = off * 0.12, ZIndex = 25 + (if n == math.ceil((i + 1) / 2) then 1 else 0) }, card)
				end
			end
			self:_text(card, { Text = fmt(it.Grant.Ichor) .. " ICHOR", TextSize = 40, Stroke = 4.5, AnchorPoint = V2(0.5, 0), Position = O(w / 2, 170), Size = O(w - 20, 54) })
			self:_text(card, { Text = it.Name, TextSize = 20, Font = HS.MontX, Color = C.Muted, AnchorPoint = V2(0.5, 0), Position = O(w / 2, 220), Size = O(w - 20, 28) })
			if it.Bonus then
				self:_chip(card, it.Bonus, O(w - 12, 12), O(88, 34), RGB(255, 196, 70), RGB(80, 40, 4), V2(1, 0))
			end
			if it.Best then
				self:_chip(card, "BEST VALUE", O(12, 12), O(150, 34), C.Gold, RGB(80, 40, 4))
			end
			self:_price(card, it, "product", O(w / 2, 258), O(w - 40, 56))
		end
	end
	return y + 350
end

------------------------------------------------------------------ frame
function ShopUI:_build(layer)
	local HS = self.HS
	local new = HS.new
	local root = new("Frame", { Name = "Shop", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, layer)
	new("UIScale", { Name = "Pop" }, root)
	self.Root = root
	local fit = new("Frame", { Name = "Fit", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = O(PW, PH), BackgroundTransparency = 1, ZIndex = 20 }, root)
	self.Fit, self.FitFrame = new("UIScale", { Name = "Fit" }, fit), fit

	local glow = new("Frame", { Name = "Glow", AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18), BackgroundTransparency = 1, ZIndex = 20 }, fit)
	HS.corner(glow, 30)
	HS.stroke(glow, 10, RGB(190, 120, 255), 0.72)
	local panel = new("Frame", { Name = "Panel", BackgroundColor3 = C.Panel, Size = S(1, 1), ZIndex = 20 }, fit)
	HS.corner(panel, 22)
	HS.stroke(panel, 4, C.Edge)
	local stripes = new("Frame", { Name = "Stripes", BackgroundColor3 = C.Stripe, BorderSizePixel = 0, Size = S(1, 1), ZIndex = 20 }, panel)
	HS.corner(stripes, 22)
	local kp = {}
	for k = 0, 14 do
		table.insert(kp, NK(k / 14, if k % 2 == 0 then 1 else 0.5))
	end
	new("UIGradient", { Rotation = 28, Transparency = NS(kp) }, stripes)
	local neb = new("CanvasGroup", { Name = "Nebula", BackgroundTransparency = 1, Size = S(1, 1), ZIndex = 20 }, panel)
	HS.corner(neb, 22)
	for _, b in { { S(0.12, 0.05), RGB(110, 60, 255), 0.5 }, { S(0.92, 0.98), RGB(255, 50, 190), 0.55 }, { S(0.55, 0.5), RGB(60, 120, 255), 0.75 } } do
		new("ImageLabel", { BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = b[2], ImageTransparency = b[3], AnchorPoint = V2(0.5, 0.5), Position = b[1], Size = S(0.95, 0.95), SizeConstraint = Enum.SizeConstraint.RelativeXX, ZIndex = 20 }, neb)
	end
	new("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = RAYS, ImageColor3 = RGB(200, 160, 255), ImageTransparency = 0.88, AnchorPoint = V2(0.5, 0.5), Position = S(0.12, 0.05), Size = S(1.6, 1.6), SizeConstraint = Enum.SizeConstraint.RelativeXX, ZIndex = 20 }, neb)

	-- title breaking the top edge
	new("Frame", { Name = "TitleGap", BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = O(36, -8), Size = O(184, 16), ZIndex = 21 }, panel)
	HS.text(panel, { Name = "Title", Text = "SHOP", TextSize = 70, Stroke = 5.5, StrokeColor = C.Ink, X = LEFT, Fit = false, Position = O(44, -48), Size = O(240, 86), ZIndex = 26 })

	-- red close square overlapping the corner
	local x = new("TextButton", { Name = "Close", Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(110, 18, 22), AnchorPoint = V2(0.5, 0.5), Position = O(PW - 14, 8), Size = O(78, 78), ZIndex = 27 }, panel)
	HS.corner(x, 14)
	HS.stroke(x, 3.5, RGB(40, 6, 10))
	local xf = new("Frame", { Name = "Face", BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = O(4, 3), Size = UDim2.new(1, -8, 1, -10), ZIndex = 27 }, x)
	HS.corner(xf, 11)
	new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 100, 96), RGB(212, 38, 46)) }, xf)
	HS.text(x, { Text = "X", TextSize = 50, Stroke = 3.5, StrokeColor = RGB(60, 8, 12), Position = O(0, -3), Size = S(1, 1), ZIndex = 28 })
	HS.press(x, function()
		if self.Env.Close then self.Env.Close() end
	end, { Hover = 1.08, Press = 0.92, Sound = "Click" })

	-- one long scroll
	local sc = new("ScrollingFrame", { Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Position = O(36, 46), Size = O(PW - 56, PH - 66), CanvasSize = O(0, 100), ScrollBarThickness = 10, ScrollBarImageColor3 = C.Edge, ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.Never, ZIndex = 22 }, panel)
	self.Scroll = sc
	local y = 4
	self.SecY.Crates = 0
	y = self:_crates(sc, y)
	self.SecY.Ichor = y - 6
	y = self:_ichor(sc, y)
	self.SecY.Deals = y - 6
	y = self:_deals(sc, y)
	self.SecY.Passes = y - 6
	y = self:_passes(sc, y)
	self.SecY.Req = y - 6
	y = self:_req(sc, y)
	self.SecY.Ord = y - 6
	y = self:_ord(sc, y)
	self.SecY.IchorPack = y - 6
	y = self:_ichorPacks(sc, y)
	sc.CanvasSize = O(0, y + 10)

	-- hex rail (original layout): neon painted hexes with a coloured glow halo and an animated light streak clipped to the hex
	local rail = new("Frame", { Name = "Rail", BackgroundTransparency = 1, Position = O(-104, 26), Size = O(160, #Shop.Sections * 120), ZIndex = 26 }, panel)
	new("UIScale", { Scale = 0.85 }, rail)
	for i, sec in Shop.Sections do
		local col = SEC[sec.Id]
		local cy = 54 + (i - 1) * 120
		local glow = new("ImageLabel", { Name = sec.Id .. "_Glow", BackgroundTransparency = 1, Image = HEXGLOW, ImageColor3 = col:Lerp(WHITE, 0.15), ImageTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = O(80, cy), Size = O(230, 165), ZIndex = 26 }, rail)
		local b = new("ImageButton", { Name = sec.Id, BackgroundTransparency = 1, Image = HEXART[sec.Id], AnchorPoint = V2(0.5, 0.5), Position = O(80, cy), Size = O(156, 104), ZIndex = 27 }, rail)
		local streak = new("ImageLabel", { Name = "Streak", BackgroundTransparency = 1, Image = HEX, ImageColor3 = WHITE, Size = S(1, 1), ZIndex = 28 }, b)
		local sg = new("UIGradient", { Rotation = 20, Transparency = NS({ NK(0, 1), NK(0.42, 1), NK(0.5, 0.35), NK(0.58, 1), NK(1, 1) }), Offset = V2(-1, 0) }, streak)
		new("ImageLabel", { Name = "IconGlow", BackgroundTransparency = 1, Image = BLOOM, ImageColor3 = WHITE, ImageTransparency = 0.72, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.8, 1.15), ZIndex = 28 }, b)
		if sec.Id == "Crates" then
			new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = CrateConfig.ById.Apex.Art.Full, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.55, 0.5), Size = S(0.62, 0.84), ZIndex = 29 }, b)
		elseif sec.Id == "Deals" then
			new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = HS.Img.Shop, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.48), Size = S(0.5, 0.78), ZIndex = 29 }, b)
		elseif sec.Id == "Passes" then
			local v = HS.text(b, { Name = "Icon", Text = "VIP", TextSize = 46, Stroke = 4, StrokeColor = RGB(70, 34, 0), AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.7, 0.6), ZIndex = 29 })
			new("UIGradient", { Rotation = 90, Color = CS(RGB(255, 252, 220), RGB(255, 196, 50)) }, v)
		elseif sec.Id == "IchorPack" then
			b.ImageColor3 = RGB(255, 210, 110)
			new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = IchorCfg.Icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.5, 0.78), ZIndex = 29 }, b)
			new("ImageLabel", { Name = "Plus", BackgroundTransparency = 1, Image = STAR, ImageColor3 = WHITE, AnchorPoint = V2(0.5, 0.5), Position = S(0.72, 0.28), Size = O(30, 30), ZIndex = 30 }, b)
		elseif sec.Id == "Ichor" then
			b.ImageColor3 = RGB(150, 200, 255)
			new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = IchorCfg.Icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.5, 0.78), ZIndex = 29 }, b)
		elseif sec.Id == "Ord" then
			b.ImageColor3 = RGB(255, 150, 70)
			HS.ordCoin(b, { Name = "Icon", Position = S(0.5, 0.5), Size = O(76, 76), ZIndex = 29 })
		else
			new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = HS.Img.Req, ScaleType = Enum.ScaleType.Fit, AnchorPoint = V2(0.5, 0.5), Position = S(0.5, 0.5), Size = S(0.46, 0.72), ZIndex = 29 }, b)
		end
		HS.press(b, function()
			self:_jump(sec.Id)
		end, { Hover = 1.08, Press = 0.92, Sound = "Tab" })
		self.Hex[sec.Id] = { B = b, Col = col, Glow = glow, Streak = sg, Phase = (i - 1) * 0.55, Cy = cy }
	end
	sc:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_syncRail()
	end)
end

function ShopUI:_animate(now)
	local dt = math.clamp(now - (self.LastT or now), 0, 0.1)
	for id, h in self.Hex do
		local on = id == self.Active
		h.Glow.ImageTransparency = if on then 0.05 + (0.5 + 0.5 * math.sin(now * 3)) * 0.25 else 0.42 + math.sin(now * 2 + h.Phase * 3) * 0.08
		-- light streak sweeps across each hex in turn, then rests
		local k = ((now + h.Phase) % 3.2) / 0.9
		h.Streak.Offset = V2(if k <= 1 then -1 + 2 * k else 1, 0)
	end
	self.LastT = now
	for _, L in self.Layers do
		local t = now + L.Phase
		L.Hover += (L.HoverT - L.Hover) * math.min(1, dt * 8)
		local z = 1.03 + 0.045 * (0.5 + 0.5 * math.sin(t * 0.31))
		local px, py = math.sin(t * 0.19) * 0.3, math.cos(t * 0.15) * 0.3
		local function rect(img, zz, k)
			local rw, rh = L.W / zz, L.H / zz
			img.ImageRectSize = V2(rw, rh)
			img.ImageRectOffset = V2(math.clamp((L.W - rw) * (0.5 + px * k), 0, L.W - rw), math.clamp((L.H - rh) * (0.5 + py * k), 0, L.H - rh))
		end
		rect(L.Bg, z, 1)
		rect(L.Fg, z * (1.015 + L.Hover * 0.04), 1.5)
		for _, e in L.Embers do
			e.Y -= e.V * dt
			if e.Y < -8 then
				e.Y, e.X = L.CH + 8, math.random() * L.CW
			end
			e.F.Position = O(e.X + math.sin(t * 1.3 + e.Sway) * 7, e.Y)
			e.F.BackgroundTransparency = 0.15 + 0.85 * math.clamp(1 - e.Y / (L.CH * 0.85), 0, 1) ^ 2
		end
	end
	if self.DailyTimer and now - (self.TimerT or 0) > 0.5 then
		self.TimerT = now
		local server = Workspace:GetServerTimeNow()
		local today, ends = Shop.DailyToday(server)
		local left = math.max(0, math.floor(ends - server))
		self.DailyTimer.Text = string.format("ENDS IN %02d:%02d:%02d", left // 3600, (left % 3600) // 60, left % 60)
		if today and self.DailyKey ~= today.Key then
			self.DailyKey = today.Key
			self:_render()
		end
	end
	for _, f in self.Fx do
		local t = now + f.Phase
		f.Glow.ImageTransparency = 0.42 + math.sin(t * 2.1) * 0.14
		local k = (t % 4.5) / 1.0
		f.Band.Visible = k <= 1
		if k <= 1 then
			f.Band.Position = UDim2.new(-0.3 + 1.6 * k, 0, 0.5, 0)
		end
	end
	if self.IchorFx then
		local f = self.IchorFx
		f.Rays.Rotation = (now * 12) % 360
		f.Crate.Position = O(215, 170 + math.sin(now * 1.6) * 8)
		f.Crate.Rotation = math.sin(now * 0.9) * 2.5
		f.Glow.ImageTransparency = 0.35 + math.sin(now * 2.2) * 0.1
	end
	if self.SigSlots then
		for _, s in self.SigSlots do if s.Step then s.Step(now, 0.3) end end
		if self.SigTimer and now - (self.SigTimerT or 0) > 0.5 then
			self.SigTimerT = now
			local server = Workspace:GetServerTimeNow()
			local today, ends = SigCat.DailyToday(server)
			local left = math.max(0, math.floor(ends - server))
			self.SigTimer.Text = string.format("NEW IN %02d:%02d:%02d", left // 3600, (left % 3600) // 60, left % 60)
			if self.SigSlots[1] and today[1] ~= self.SigSlots[1].Id then self:_renderSig() end
		end
	end
	for _, st in self.Stars do
		local a = math.max(0, math.sin((now + st.P) * st.Spd))
		st.I.Size = O(st.Sz * a, st.Sz * a)
		st.I.Rotation = (now * 30 + st.P * 60) % 360
		if a <= 0.02 and not st.Moved then
			st.Moved = true
			st.I.Position = O(math.random(20, st.W - 20), math.random(16, st.H - 16))
		elseif a > 0.1 then
			st.Moved = false
		end
	end
end

function ShopUI:_jump(id)
	local sc = self.Scroll
	local maxY = math.max(0, sc.AbsoluteCanvasSize.Y - sc.AbsoluteWindowSize.Y) / math.max(self.Fit.Scale * (self.Root:FindFirstChild("Pop") and self.Root.Pop.Scale or 1), 0.01)
	local target = math.min(self.SecY[id] or 0, maxY)
	self.HS.tween(sc, 0.35, { CanvasPosition = V2(0, target) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
end

function ShopUI:_syncRail()
	local y = self.Scroll.CanvasPosition.Y + 60
	local active = "Crates"
	for _, sec in Shop.Sections do
		if y >= (self.SecY[sec.Id] or 0) then active = sec.Id end
	end
	if self.Scroll.CanvasPosition.Y + self.Scroll.AbsoluteWindowSize.Y / math.max(self.Fit.Scale, 0.01) >= self.Scroll.CanvasSize.Y.Offset - 8 then
		active = Shop.Sections[#Shop.Sections].Id
	end
	if active == self.Active then return end
	self.Active = active
	for id, h in self.Hex do
		local on = id == active
		self.HS.tween(h.B, 0.22, { Size = if on then O(180, 120) else O(156, 104) }, Enum.EasingStyle.Back)
		self.HS.tween(h.Glow, 0.22, { Size = if on then O(270, 195) else O(230, 165) })
	end
end

function ShopUI:_render()
	for _, p in self.Prices do
		local it = p.Item
		local owned = (p.Kind == "pass" and player:GetAttribute("Pass_" .. it.Key)) or (it.OneTime and player:GetAttribute("ShopBought_" .. it.Key)) or (it.Grant and it.Grant.Pass and it.Grant.Pass.Premium and player:GetAttribute("PassPremium"))
		local blocked = self.Restricted and it.Grant and it.Grant.Crates and next(it.Grant.Crates) ~= nil
		local off = owned or it.Soon or blocked
		local pal = if off then GREY else GREEN
		p.T.Text = if it.Soon then "COMING SOON" elseif owned then "OWNED" elseif blocked then "UNAVAILABLE" else ROBUX .. " " .. fmt(it.Robux)
		p.B.BackgroundColor3 = pal.Rim
		p.G.Color = CS(pal.Top0, pal.Top1)
		p.B:SetAttribute("Disabled", off and true or nil)
	end
	self:_renderSig()
	if self.DailyPanels then
		local today = Shop.DailyToday(Workspace:GetServerTimeNow())
		for key, pnl in self.DailyPanels do
			pnl.Visible = today ~= nil and key == today.Key
		end
	end
end

function ShopUI:_buy(item, kind)
	local HS = self.HS
	if kind == "pass" then
		if player:GetAttribute("Pass_" .. item.Key) then HS.sound("Deny") return end
		if (item.PassId or 0) <= 0 then
			HS.sound("Deny")
			self:_toast("Coming soon", item.Name .. " isn't on sale yet")
			return
		end
		HS.sound("Click")
		MarketplaceService:PromptGamePassPurchase(player, item.PassId)
	else
		if item.Soon then
			HS.sound("Deny")
			self:_toast("Coming soon", item.Name .. " arrives with the Season Pass")
			return
		end
		if self.Restricted and item.Grant and item.Grant.Crates and next(item.Grant.Crates) then
			HS.sound("Deny")
			self:_toast("Unavailable", "Crate purchases aren't available on your account")
			return
		end
		if item.OneTime and player:GetAttribute("ShopBought_" .. item.Key) then HS.sound("Deny") return end
		if (item.ProductId or 0) <= 0 then
			HS.sound("Deny")
			self:_toast("Coming soon", item.Name .. " isn't on sale yet")
			return
		end
		HS.sound("Click")
		MarketplaceService:PromptProductPurchase(player, item.ProductId)
	end
end

------------------------------------------------------------------ toast (own ScreenGui so it shows over everything)
function ShopUI:_buildToast()
	local HS = self.HS
	local gui = HS.new("ScreenGui", { Name = "ShopToast", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70 }, player:WaitForChild("PlayerGui"))
	local f = HS.new("Frame", { Name = "Toast", AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, -140), Size = O(560, 104), BackgroundColor3 = C.Panel, ZIndex = 2 }, gui)
	HS.corner(f, 18)
	HS.stroke(f, 4, C.Edge)
	HS.new("UIScale", { Name = "Fit" }, f)
	local bar = HS.new("Frame", { BackgroundColor3 = GREEN.Top0, BorderSizePixel = 0, Position = O(0, 0), Size = O(12, 104), ZIndex = 3 }, f)
	HS.corner(bar, 6)
	self.ToastBar = bar
	self.ToastTitle = HS.text(f, { Text = "", TextSize = 36, Stroke = 3.5, StrokeColor = C.Ink, X = LEFT, Position = O(30, 10), Size = O(510, 44), ZIndex = 3 })
	self.ToastText = HS.text(f, { Text = "", TextSize = 22, Font = HS.MontX, Color = C.Muted, Stroke = 2.2, StrokeColor = C.Ink, X = LEFT, Position = O(30, 56), Size = O(510, 30), ZIndex = 3 })
	self.ToastFrame = f
end

function ShopUI:_toast(title, text, good)
	local HS = self.HS
	local f = self.ToastFrame
	local vp = Workspace.CurrentCamera.ViewportSize
	f.Fit.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.5, 1.4)
	self.ToastTitle.Text, self.ToastText.Text = title, text
	self.ToastBar.BackgroundColor3 = if good then GREEN.Top0 else RGB(255, 170, 60)
	if good then HS.sound("Purchase") end
	self.ToastN = (self.ToastN or 0) + 1
	local n = self.ToastN
	HS.tween(f, 0.35, { Position = UDim2.new(0.5, 0, 0, 90) }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		if self.ToastN == n then
			HS.tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, -140) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end

function ShopUI:_fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	local layer = self.Root.Parent
	local ls = layer and layer:FindFirstChildOfClass("UIScale")
	local want = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.42, 1.6)
	self.Fit.Scale = want / math.max(ls and ls.Scale or 1, 0.01)
	self.FitFrame.Position = UDim2.new(0.5, 30 * self.Fit.Scale, 0.5, 34 * self.Fit.Scale)
end

function ShopUI:OnShow()
	self:_fit()
	self:_render()
	self.Scroll.CanvasPosition = V2(0, 0)
	self.Active = nil
	self:_syncRail()
end

function ShopUI.Mount(layer, env)
	local s = ShopUI.new(layer, env)
	return {
		Root = s.Root,
		OnShow = function() s:OnShow() end,
		OnData = function() s:_render() end,
		Object = s,
	}
end

return ShopUI
