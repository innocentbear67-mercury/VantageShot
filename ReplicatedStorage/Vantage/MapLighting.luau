-- MapLighting (shared, 2026-11-18): per-map lighting presets. A copy of
-- ServerStorage.VantageMapTools2.LightingPresets the clients can read. The client applies the
-- current map's preset (Match attribute MapLighting) when the camera leaves the lobby
-- (StarterPlayerScripts.LobbyLighting); the server's Lighting is never changed by a map swap.
local P = {}
P.foundry = {
	ClockTime = 15.2, GeographicLatitude = 30, Brightness = 2.6,
	Ambient = Color3.fromRGB(132, 126, 122), OutdoorAmbient = Color3.fromRGB(146, 140, 134),
	EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.4, ExposureCompensation = -0.1, ShadowSoftness = 0.2,
	ColorShift_Top = Color3.fromRGB(255, 226, 196), ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	Atmosphere = { Density = 0.12, Offset = 0, Haze = 0, Glare = 0, Color = Color3.fromRGB(220, 226, 236), Decay = Color3.fromRGB(200, 206, 222) },
	Grade = { Brightness = 0, Contrast = 0.1, Saturation = 0.15, TintColor = Color3.fromRGB(255, 250, 244) },
	Bloom = { Intensity = 0.25, Size = 20, Threshold = 2 },
	SunRays = { Intensity = 0.04, Spread = 0.4 },
	Clouds = { Cover = 0.45, Density = 0.3, Color = Color3.fromRGB(255, 255, 255) },
}
P.livefire = {
	ClockTime = 13.80, GeographicLatitude = 38.00, Brightness = 3.20, Ambient = Color3.new(0.5725, 0.5569, 0.5647), OutdoorAmbient = Color3.new(0.6902, 0.6667, 0.6588),
	EnvironmentDiffuseScale = 0.22, EnvironmentSpecularScale = 0.50, ExposureCompensation = 0.10, ShadowSoftness = 0.15,
	ColorShift_Top = Color3.new(1.0000, 0.9333, 0.8392), ColorShift_Bottom = Color3.new(0.0000, 0.0000, 0.0000),
	Atmosphere = { Density = 0.120, Offset = 0.000, Haze = 0.200, Glare = 0.000, Color = Color3.new(0.8392, 0.8941, 0.9569), Decay = Color3.new(0.6902, 0.7843, 0.9020) },
	Grade = { Brightness = 0.030, Contrast = 0.040, Saturation = 0.150, TintColor = Color3.new(1.0000, 1.0000, 1.0000) },
	Bloom = { Intensity = 0.400, Size = 24.0, Threshold = 1.500 },
	SunRays = { Intensity = 0.040, Spread = 0.600 },
	Clouds = { Cover = 0.55, Density = 0.4, Color = Color3.new(1, 1, 1) },
}
P.porto = {
	ClockTime = 14.6, GeographicLatitude = 34, Brightness = 2.6,
	Ambient = Color3.fromRGB(140, 136, 132), OutdoorAmbient = Color3.fromRGB(152, 148, 142),
	EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.45, ExposureCompensation = -0.1, ShadowSoftness = 0.2,
	ColorShift_Top = Color3.fromRGB(255, 238, 214), ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	Atmosphere = { Density = 0.12, Offset = 0, Haze = 0, Glare = 0, Color = Color3.fromRGB(214, 232, 250), Decay = Color3.fromRGB(190, 214, 240) },
	Grade = { Brightness = 0, Contrast = 0.08, Saturation = 0.18, TintColor = Color3.fromRGB(255, 252, 246) },
	Bloom = { Intensity = 0.22, Size = 20, Threshold = 2.1 },
	SunRays = { Intensity = 0.04, Spread = 0.4 },
	Clouds = { Cover = 0.4, Density = 0.3, Color = Color3.fromRGB(255, 255, 255) },
}
P.meridian = {
	ClockTime = 17.3, GeographicLatitude = 30, Brightness = 2.6,
	Ambient = Color3.fromRGB(150, 140, 168), OutdoorAmbient = Color3.fromRGB(160, 150, 176),
	EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.4, ExposureCompensation = 0, ShadowSoftness = 0.25,
	ColorShift_Top = Color3.fromRGB(255, 196, 170), ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	Atmosphere = { Density = 0.16, Offset = 0, Haze = 0.1, Glare = 0, Color = Color3.fromRGB(214, 196, 222), Decay = Color3.fromRGB(150, 120, 190) },
	Grade = { Brightness = 0, Contrast = 0.1, Saturation = 0.2, TintColor = Color3.fromRGB(250, 244, 255) },
	Bloom = { Intensity = 0.22, Size = 20, Threshold = 2.2 },
	SunRays = { Intensity = 0.05, Spread = 0.4 },
	Clouds = { Cover = 0.35, Density = 0.25, Color = Color3.fromRGB(255, 214, 220) },
}
function P.apply(name)
	local p = P[name]; if not p then return false end
	local L = game:GetService("Lighting")
	for _, k in ipairs({"ClockTime","GeographicLatitude","Brightness","Ambient","OutdoorAmbient","EnvironmentDiffuseScale","EnvironmentSpecularScale","ExposureCompensation","ShadowSoftness","ColorShift_Top","ColorShift_Bottom"}) do
		if p[k] ~= nil then L[k] = p[k] end
	end
	local a = L:FindFirstChildOfClass("Atmosphere"); if a and p.Atmosphere then for k, v in pairs(p.Atmosphere) do a[k] = v end end
	local g = L:FindFirstChild("VantageGrade"); if g and p.Grade then for k, v in pairs(p.Grade) do g[k] = v end end
	local b = L:FindFirstChildOfClass("BloomEffect"); if b and p.Bloom then for k, v in pairs(p.Bloom) do b[k] = v end end
	local s = L:FindFirstChildOfClass("SunRaysEffect"); if s and p.SunRays then for k, v in pairs(p.SunRays) do s[k] = v end end
	local c = workspace.Terrain:FindFirstChildOfClass("Clouds"); if c and p.Clouds then for k, v in pairs(p.Clouds) do c[k] = v end end
	return true
end
-- 2026-11-19 HSX panel-texture pass: dark panel bodies need more fill light; each map gets its own time of day
do
	local c = Color3.fromRGB
	local f = P.foundry   -- golden hour over the furnaces
	f.ClockTime = 16.4 f.Brightness = 3.0 f.ExposureCompensation = 0.05
	f.Ambient = c(150, 138, 126) f.OutdoorAmbient = c(178, 160, 140)
	f.ColorShift_Top = c(255, 214, 170) f.EnvironmentDiffuseScale = 0.3
	f.Bloom = { Threshold = 1.6, Intensity = 0.35, Size = 22 }
	if f.Grade then f.Grade.Contrast = 0.06 f.Grade.Saturation = 0.2 end
	local p = P.porto     -- bright clear harbour morning
	p.ClockTime = 10.6 p.Brightness = 3.2 p.ExposureCompensation = 0.1
	p.Ambient = c(140, 150, 166) p.OutdoorAmbient = c(168, 182, 204)
	p.ColorShift_Top = c(255, 244, 226) p.EnvironmentDiffuseScale = 0.3
	p.Bloom = { Threshold = 1.6, Intensity = 0.3, Size = 22 }
	if p.Grade then p.Grade.Contrast = 0.05 p.Grade.Saturation = 0.2 end
	local m = P.meridian  -- neon dusk
	m.ClockTime = 17.4 m.Brightness = 2.8 m.ExposureCompensation = 0.1
	m.Ambient = c(158, 142, 178) m.OutdoorAmbient = c(176, 156, 196)
	m.Bloom = { Threshold = 1.35, Intensity = 0.5, Size = 26 }
	if m.Grade then m.Grade.Contrast = 0.06 m.Grade.Saturation = 0.22 end
end
-- 2026-11-19 brighter pass (user: "not too dark"): lift exposure and fill on every map
do
	for _, k in ipairs({ "livefire", "foundry", "porto", "meridian" }) do
		local p = P[k]
		if p then
			p.ExposureCompensation = (p.ExposureCompensation or 0) + 0.0
			local function lift(c, a) return Color3.new(math.min(1, c.R + a), math.min(1, c.G + a), math.min(1, c.B + a)) end
			if p.Ambient then p.Ambient = lift(p.Ambient, 0.04) end
			if p.OutdoorAmbient then p.OutdoorAmbient = lift(p.OutdoorAmbient, 0.04) end
		end
	end
end
return P
