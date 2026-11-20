--[[
	VANTAGE — SettingsConfig (shared)
	Schema for the settings menu. The server sanitises every saved value against it, the
	client builds the menu from it. Add a row here and it appears in the menu, saves and loads.
	Types: Bool | Number (Min/Max/Step) | Key (KeyCode or UserInputType name)
]]

local SettingsConfig = {}

SettingsConfig.Version = 1
SettingsConfig.Categories = { "Gameplay", "Sensitivity", "Audio", "Visuals", "Controls" }

SettingsConfig.Schema = {
	-- Gameplay
	{ Key = "Crosshair", Category = "Gameplay", Type = "Bool", Default = true, Label = "Crosshair" },
	{ Key = "HitMarkers", Category = "Gameplay", Type = "Bool", Default = true, Label = "Hit markers" },
	{ Key = "AimAssist", Category = "Gameplay", Type = "Bool", Default = true, Label = "Aim assist", Hint = "Slows your aim on enemies and pulls near-miss shots onto them" },
	{ Key = "DamageIndicators", Category = "Gameplay", Type = "Bool", Default = true, Label = "Damage indicators", Hint = "Damage numbers + incoming damage direction" },
	{ Key = "ScreenShake", Category = "Gameplay", Type = "Bool", Default = true, Label = "Screen shake", Hint = "Recoil punch, landing dip, head bob" },
	{ Key = "CameraEffects", Category = "Gameplay", Type = "Bool", Default = true, Label = "Camera effects", Hint = "Strafe / slide tilt and speed FOV" },
	-- Sensitivity
	{ Key = "Sensitivity", Category = "Sensitivity", Type = "Number", Default = 1, Min = 0.05, Max = 4, Step = 0.01, Label = "Mouse sensitivity" },
	{ Key = "ADSSensitivity", Category = "Sensitivity", Type = "Number", Default = 0.8, Min = 0.1, Max = 2, Step = 0.01, Label = "ADS sensitivity multiplier" },
	{ Key = "RifleSensitivity", Category = "Sensitivity", Type = "Number", Default = 1, Min = 0.25, Max = 2, Step = 0.01, Label = "Rifle sensitivity multiplier" },
	{ Key = "MeleeSensitivity", Category = "Sensitivity", Type = "Number", Default = 1, Min = 0.25, Max = 2, Step = 0.01, Label = "Knife sensitivity multiplier" },
	-- Audio
	{ Key = "MasterVolume", Category = "Audio", Type = "Number", Default = 1, Min = 0, Max = 1, Step = 0.01, Label = "Master volume", Percent = true },
	{ Key = "WeaponVolume", Category = "Audio", Type = "Number", Default = 1, Min = 0, Max = 1, Step = 0.01, Label = "Weapon volume", Percent = true },
	{ Key = "EffectsVolume", Category = "Audio", Type = "Number", Default = 1, Min = 0, Max = 1, Step = 0.01, Label = "Sound effects volume", Percent = true },
	{ Key = "MusicVolume", Category = "Audio", Type = "Number", Default = 0.6, Min = 0, Max = 1, Step = 0.01, Label = "Music volume", Percent = true, Hint = "Controls the VantageMusic sound group" },
	-- Visuals
	{ Key = "TeamOutlines", Category = "Visuals", Type = "Bool", Default = true, Label = "Team outlines" },
	{ Key = "ImpactEffects", Category = "Visuals", Type = "Bool", Default = true, Label = "Impact particles" },
	{ Key = "ShellCasings", Category = "Visuals", Type = "Bool", Default = true, Label = "Shell casings" },
	{ Key = "MuzzleSmoke", Category = "Visuals", Type = "Bool", Default = true, Label = "Muzzle smoke" },
	{ Key = "FOV", Category = "Visuals", Type = "Number", Default = 80, Min = 70, Max = 100, Step = 1, Label = "Field of view" },
	{ Key = "ShowViewmodel", Category = "Visuals", Type = "Bool", Default = true, Label = "Show weapon viewmodel" },
	-- Controls (fire is fixed to left click; movement keys belong to the movement system)
	{ Key = "Bind_Alt", Category = "Controls", Type = "Key", Default = "MouseButton2", Label = "Aim down sights / heavy stab" },
	{ Key = "Bind_Reload", Category = "Controls", Type = "Key", Default = "R", Label = "Reload" },
	{ Key = "Bind_Inspect", Category = "Controls", Type = "Key", Default = "F", Label = "Inspect weapon" },
	{ Key = "Bind_Inventory", Category = "Controls", Type = "Key", Default = "B", Label = "Armory (weapon skins)" },
	{ Key = "Bind_Primary", Category = "Controls", Type = "Key", Default = "One", Label = "Knife / melee (number keys 1-7 pick a slot: 1 knife, 2-7 guns)" },
	{ Key = "Bind_Knife", Category = "Controls", Type = "Key", Default = "V", Label = "Knife" },
	{ Key = "Bind_Swap", Category = "Controls", Type = "Key", Default = "Q", Label = "Next weapon (cycles 1-7)" },
	{ Key = "Bind_Settings", Category = "Controls", Type = "Key", Default = "P", Label = "Settings menu" },
}

-- read-only rows shown under Controls
SettingsConfig.FixedBinds = {
	{ "Fire / quick slash", "Left mouse" },
	{ "Jump", "Space" },
	{ "Crouch / slide", "Left Ctrl / C" },
	{ "Move", "W A S D" },
	{ "Cycle weapons", "Mouse wheel" },
}

-- keys that may never be bound (movement + reserved)
SettingsConfig.ReservedKeys = {
	Space = true, LeftControl = true, C = true, W = true, A = true, S = true, D = true,
	Escape = true, Backquote = true, Tab = true, MouseButton1 = true, Unknown = true,
}

local byKey = {}
for _, row in SettingsConfig.Schema do
	byKey[row.Key] = row
end
SettingsConfig.ByKey = byKey

function SettingsConfig.Defaults()
	local t = {}
	for _, row in SettingsConfig.Schema do
		t[row.Key] = row.Default
	end
	return t
end

local function validKeyName(v): boolean
	if type(v) ~= "string" or #v > 32 or SettingsConfig.ReservedKeys[v] then
		return false
	end
	local ok1, k = pcall(function()
		return Enum.KeyCode[v]
	end)
	if ok1 and k then
		return true
	end
	return v == "MouseButton2" or v == "MouseButton3"
end

-- Returns a clean table: unknown keys dropped, wrong types replaced by defaults, numbers clamped,
-- duplicate key binds reset to their defaults.
function SettingsConfig.Sanitize(input)
	local out = SettingsConfig.Defaults()
	if type(input) ~= "table" then
		return out
	end
	for _, row in SettingsConfig.Schema do
		local v = input[row.Key]
		if row.Type == "Bool" then
			if type(v) == "boolean" then
				out[row.Key] = v
			end
		elseif row.Type == "Number" then
			if type(v) == "number" and v == v then
				local step = row.Step or 0.01
				v = math.clamp(v, row.Min, row.Max)
				out[row.Key] = math.floor(v / step + 0.5) * step
			end
		elseif row.Type == "Key" then
			if validKeyName(v) then
				out[row.Key] = v
			end
		end
	end
	local seen = {}
	for _, row in SettingsConfig.Schema do
		if row.Type == "Key" then
			local v = out[row.Key]
			if seen[v] then
				out[row.Key] = row.Default
			end
			seen[out[row.Key]] = true
		end
	end
	return out
end

return SettingsConfig
