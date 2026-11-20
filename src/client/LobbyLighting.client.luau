-- Applies the HyperLobby lighting preset only while the camera is inside the lobby; restores the place lighting when it leaves.
local Lighting = game:GetService("Lighting")
local lobby = workspace:WaitForChild("HyperLobby", 30)
if not lobby then return end
local cfg = lobby:WaitForChild("LobbyLighting", 10)
if not cfg then return end
local ORIGIN = Vector3.new(0, 3000, 0)
local KEYS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }
local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local grade
if cfg:FindFirstChild("LobbyGrade") then grade = cfg.LobbyGrade:Clone() grade.Name = "LobbyGrade" grade.Enabled = false grade.Parent = Lighting end
local lb = cfg:FindFirstChild("LobbyBloom")
local saved, inLobby = nil, false
-- 2026-11-18 map vote: outside the lobby the current map's preset (Match attribute MapLighting,
-- Vantage.MapLighting) is applied on top of the restored place lighting
local Vantage = game:GetService("ReplicatedStorage"):WaitForChild("Vantage")
local okML, MapLighting = pcall(require, Vantage:WaitForChild("MapLighting", 10))
local Match = Vantage:WaitForChild("Match", 30)
local function applyMap()
	local name = Match and Match:GetAttribute("MapLighting")
	if okML and type(name) == "string" and name ~= "" then
		pcall(MapLighting.apply, name)
	end
end
if Match then
	Match:GetAttributeChangedSignal("MapLighting"):Connect(function()
		if not inLobby then
			applyMap()
		end
	end)
end
local function capture()
	local s = {}
	for _, k in ipairs(KEYS) do s[k] = Lighting[k] end
	if atmos then s.ad, s.ac, s.adc, s.ah = atmos.Density, atmos.Color, atmos.Decay, atmos.Haze end
	if bloom then s.bi, s.bs, s.bt = bloom.Intensity, bloom.Size, bloom.Threshold end
	return s
end
local function apply()
	saved = capture()
	for _, k in ipairs(KEYS) do local v = cfg:GetAttribute(k) if v ~= nil then Lighting[k] = v end end
	if atmos then
		atmos.Density = cfg:GetAttribute("AtmosDensity") or atmos.Density
		atmos.Color = cfg:GetAttribute("AtmosColor") or atmos.Color
		atmos.Decay = cfg:GetAttribute("AtmosDecay") or atmos.Decay
		atmos.Haze = cfg:GetAttribute("AtmosHaze") or atmos.Haze
	end
	if bloom and lb then bloom.Intensity, bloom.Size, bloom.Threshold = lb.Intensity, lb.Size, lb.Threshold end
	if grade then grade.Enabled = true end
end
local function restore()
	if not saved then return end
	for _, k in ipairs(KEYS) do Lighting[k] = saved[k] end
	if atmos and saved.ad then atmos.Density, atmos.Color, atmos.Decay, atmos.Haze = saved.ad, saved.ac, saved.adc, saved.ah end
	if bloom and saved.bi then bloom.Intensity, bloom.Size, bloom.Threshold = saved.bi, saved.bs, saved.bt end
	if grade then grade.Enabled = false end
	saved = nil
	applyMap()
end
local function inside(p)
	local d = p - ORIGIN
	return d.Y > -40 and d.Y < 180 and math.abs(d.X) < 240 and d.Z > -170 and d.Z < 280
end
while true do
	local cam = workspace.CurrentCamera
	if cam then
		local now = inside(cam.CFrame.Position)
		if now ~= inLobby then inLobby = now if now then apply() else restore() end end
	end
	task.wait(0.25)
end
