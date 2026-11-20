-- ForgeTools.FP : props and cover built from the FK styles
local FK = require(script.Parent.FK)
local FP = {}
local V, C = Vector3.new, Color3.fromRGB
local FY = FK.FY
local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
local function lp(m, name, size, cf, off, style, o)
	return FK.part(m, name, size, cf * CFrame.new(off), style, o)
end
-- heavy machine block: w along local X, d along local Z; pos = floor centre
function FP.machine(parent, x, z, w, d, h, o)
	o = o or {}
	local m = model(parent, o.name or "Machine")
	local cf = CFrame.new(x, o.y or FY, z) * CFrame.Angles(0, math.rad(o.rot or 0), 0)
	lp(m, "Base", V(w + 1.6, 1.4, d + 1.6), cf, V(0, 0.7, 0), "Trim")
	lp(m, "Body", V(w, h - 2.4, d), cf, V(0, 1.4 + (h - 2.4) / 2, 0), o.style or "Gun")
	lp(m, "Top", V(w + 0.8, 1, d + 0.8), cf, V(0, h - 0.5, 0), "Trim")
	lp(m, "PanelA", V(w * 0.7, (h - 4) * 0.55, d + 0.3), cf, V(0, 2.4 + (h - 4) * 0.45, 0), "Rib", {deco = true})
	lp(m, "PanelB", V(w + 0.3, (h - 4) * 0.4, d * 0.6), cf, V(0, 2.4 + (h - 4) * 0.4, 0), "Titan", {deco = true})
	lp(m, "Stripe", V(w + 0.12, 1.1, d + 0.12), cf, V(0, 2.1, 0), "Hazard", {deco = true})
	lp(m, "Slit", V(w + 0.14, 0.3, d + 0.14), cf, V(0, h - 1.6, 0), o.glow or "Lime", {deco = true})
	if o.stack then
		lp(m, "Stack", V(w * 0.3, o.stack, d * 0.3), cf, V(w * 0.2, h + o.stack / 2, -d * 0.15), "Steel")
		lp(m, "StackCap", V(w * 0.3 + 0.8, 0.8, d * 0.3 + 0.8), cf, V(w * 0.2, h + o.stack, -d * 0.15), "Trim", {noshadow = true})
	end
	return m
end
-- cargo crate
function FP.crate(parent, x, z, w, h, d, o)
	o = o or {}
	local m = model(parent, "Crate")
	local cf = CFrame.new(x, o.y or FY, z) * CFrame.Angles(0, math.rad(o.rot or 0), 0)
	lp(m, "Body", V(w, h, d), cf, V(0, h / 2, 0), o.style or "Forged")
	lp(m, "Lid", V(w + 0.4, 0.5, d + 0.4), cf, V(0, h - 0.25, 0), "Trim", {noshadow = true})
	lp(m, "Skid", V(w + 0.4, 0.5, d + 0.4), cf, V(0, 0.25, 0), "Trim", {noshadow = true})
	lp(m, "Band", V(w + 0.1, h * 0.22, d + 0.1), cf, V(0, h * 0.55, 0), o.band or "Titan", {deco = true})
	return m
end
-- waist-high barricade, len along local X
function FP.barricade(parent, x, z, len, o)
	o = o or {}
	local m = model(parent, "Barricade")
	local cf = CFrame.new(x, o.y or FY, z) * CFrame.Angles(0, math.rad(o.rot or 0), 0)
	lp(m, "Foot", V(len + 0.6, 0.8, 3.2), cf, V(0, 0.4, 0), "Trim", {noshadow = true})
	lp(m, "Body", V(len, 3.4, 2.2), cf, V(0, 2.5, 0), "ForgedDark")
	lp(m, "Cap", V(len + 0.3, 0.5, 2.6), cf, V(0, 4.45, 0), "Steel", {noshadow = true})
	lp(m, "Stripe", V(len + 0.06, 0.6, 2.26), cf, V(0, 3.3, 0), o.band or "Hazard", {deco = true})
	return m
end
-- tall cover slab, len along local X
function FP.slab(parent, x, z, len, h, thick, o)
	o = o or {}
	local m = model(parent, "CoverSlab")
	local cf = CFrame.new(x, o.y or FY, z) * CFrame.Angles(0, math.rad(o.rot or 0), 0)
	lp(m, "Foot", V(len + 1, 1, thick + 1), cf, V(0, 0.5, 0), "Trim", {noshadow = true})
	lp(m, "Body", V(len, h - 1.6, thick), cf, V(0, 1 + (h - 1.6) / 2, 0), o.style or "ForgedDark")
	lp(m, "Cap", V(len + 0.5, 0.6, thick + 0.5), cf, V(0, h - 0.3, 0), "Steel", {noshadow = true})
	lp(m, "Inset", V(len * 0.8, h * 0.4, thick + 0.2), cf, V(0, h * 0.5, 0), "Rib", {deco = true})
	if o.glow then lp(m, "Line", V(len + 0.1, 0.3, thick + 0.1), cf, V(0, h - 1.4, 0), o.glow, {deco = true}) end
	return m
end
-- storage tank
function FP.tank(parent, x, z, dia, h, o)
	o = o or {}
	local m = model(parent, "Tank")
	local y0 = o.y or FY
	FK.cyl(m, "Plinth", x, z, y0, y0 + 2, dia + 3, "Trim")
	FK.cyl(m, "Shell", x, z, y0 + 2, y0 + h, dia, o.style or "Steel")
	local n = math.max(2, math.floor(h / 22))
	for i = 1, n do
		FK.cyl(m, "Hoop", x, z, y0 + h * i / (n + 1) - 0.8, y0 + h * i / (n + 1) + 0.8, dia + 1, "Trim", {noshadow = true})
	end
	FK.cyl(m, "Lid", x, z, y0 + h, y0 + h + 2, dia * 0.8, "Trim", {noshadow = true})
	FK.cyl(m, "Stripe", x, z, y0 + 5, y0 + 7, dia + 0.15, "Hazard", {deco = true})
	if o.glow then FK.cyl(m, "Glow", x, z, y0 + h - 4, y0 + h - 3.4, dia + 0.2, o.glow, {deco = true}) end
	return m
end
-- flood mast
function FP.mast(parent, x, z, h, o)
	o = o or {}
	local m = model(parent, "LightMast")
	local y0 = o.y or FY
	FK.box(m, "Foot", x - 2, x + 2, y0, y0 + 2, z - 2, z + 2, "Trim")
	FK.box(m, "Pole", x - 0.8, x + 0.8, y0 + 2, y0 + h, z - 0.8, z + 0.8, "Gun")
	FK.box(m, "Head", x - 3.5, x + 3.5, y0 + h, y0 + h + 1.6, z - 1.5, z + 1.5, "Trim", {noshadow = true})
	local l = FK.box(m, "Lamp", x - 3.2, x + 3.2, y0 + h - 0.4, y0 + h, z - 1.2, z + 1.2, o.style or "White", {deco = true})
	FK.light(l, "SpotLight", {Face = Enum.NormalId.Bottom, Range = o.range or 56, Angle = 110, Brightness = o.bright or 2, Color = o.color or C(226, 234, 255), Shadows = false})
	return m
end
-- hanging light bar under a roof (cables up to yTop)
function FP.hangLight(parent, x, z, y, yTop, o)
	o = o or {}
	local m = model(parent, "HangLight")
	FK.box(m, "Housing", x - 5, x + 5, y, y + 1.2, z - 1.6, z + 1.6, "Trim", {noshadow = true})
	local l = FK.box(m, "Lamp", x - 4.6, x + 4.6, y - 0.3, y, z - 1.2, z + 1.2, o.style or "White", {deco = true})
	FK.light(l, "SpotLight", {Face = Enum.NormalId.Bottom, Range = o.range or 60, Angle = 120, Brightness = o.bright or 2.2, Color = o.color or C(230, 236, 255), Shadows = o.shadows or false})
	for _, dx in ipairs({-4, 4}) do
		FK.box(m, "Cable", x + dx - 0.12, x + dx + 0.12, y + 1.2, yTop, z - 0.12, z + 0.12, "Trim", {deco = true})
	end
	return m
end
return FP
