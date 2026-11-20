--[[
	VANTAGE — Settings (client store)
	Loads the player's saved settings from the server (DataStore, see SettingsService), applies
	them live and saves changes (debounced). Everything is sanitised by the shared SettingsConfig.
	Applied here: key binds, audio group volumes, effect toggles, camera-effect attributes.
	Read each frame by others: Crosshair / HitMarkers / DamageIndicators (Hud), Sensitivity, FOV,
	ShowViewmodel, TeamOutlines.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SettingsConfig = require(ReplicatedStorage.Vantage.SettingsConfig)
local Remotes = ReplicatedStorage.Vantage.Remotes

local SAVE_DELAY = 1.5

local Settings = {}
Settings.__index = Settings

function Settings.new(input, effects)
	local self = setmetatable({}, Settings)
	self.Input = input
	self.Effects = effects
	self.Values = SettingsConfig.Defaults()
	self.Status = "Default"
	self._changed = Instance.new("BindableEvent")
	self.Changed = self._changed.Event
	self._saveToken = 0
	self:Apply()
	task.spawn(function()
		local fn = Remotes:WaitForChild("SettingsGet", 10)
		if not fn then
			self.Status = "Offline"
			return
		end
		local ok, data, status = pcall(function()
			return fn:InvokeServer()
		end)
		if ok and type(data) == "table" then
			self.Values = SettingsConfig.Sanitize(data)
			self.Status = if status == "Loaded" then "Loaded" elseif status == "Failed" then "LoadFailed" else "Default"
		else
			self.Status = "LoadFailed"
		end
		self:Apply()
		self._changed:Fire("*")
	end)
	local saved = Remotes:WaitForChild("SettingsSaved", 10)
	if saved then
		saved.OnClientEvent:Connect(function(ok: boolean)
			self.Status = if ok then "Saved" else "SaveFailed"
			self._changed:Fire("_status")
		end)
	end
	-- Studio-only test hook: LocalPlayer attribute DevSetting = '{"Key": value}' goes through the
	-- normal Set path; DevSettingsJSON mirrors the current values for automated checks.
	if RunService:IsStudio() then
		local lp = Players.LocalPlayer
		lp:GetAttributeChangedSignal("DevSetting"):Connect(function()
			local ok, t = pcall(HttpService.JSONDecode, HttpService, lp:GetAttribute("DevSetting") or "")
			if ok and type(t) == "table" then
				for k, v in t do
					if k == "_reset" then
						self:ResetToDefaults()
					else
						self:Set(k, v)
					end
				end
			end
		end)
		self.Changed:Connect(function()
			lp:SetAttribute("DevSettingsJSON", HttpService:JSONEncode(self.Values))
		end)
	end
	return self
end

function Settings:Get(key: string)
	return self.Values[key]
end

function Settings:Apply()
	local v = self.Values
	-- key binds (Bind_* -> action)
	local binds = {}
	for key, value in v do
		if string.sub(key, 1, 5) == "Bind_" then
			binds[string.sub(key, 6)] = value
		end
	end
	self.Input:ApplyBinds(binds)
	-- audio
	local e = self.Effects
	e.WeaponGroup.Volume = v.MasterVolume * v.WeaponVolume
	e.EffectsGroup.Volume = v.MasterVolume * v.EffectsVolume
	e.MusicGroup.Volume = v.MasterVolume * v.MusicVolume
	-- effects toggles
	e.Flags.Impacts = v.ImpactEffects
	e.Flags.Shells = v.ShellCasings
	e.Flags.Smoke = v.MuzzleSmoke
	-- read by the movement CameraEffects (tilt / FOV boost, landing dip / head bob)
	local lp = Players.LocalPlayer
	lp:SetAttribute("VantageCameraFX", v.CameraEffects)
	lp:SetAttribute("VantageScreenShake", v.ScreenShake)
	-- 2026-11-20: the game's own mouse sensitivity, for cameras outside the weapon client (drone / vehicles)
	lp:SetAttribute("VantageSensitivity", v.Sensitivity)
end

function Settings:_scheduleSave()
	self._saveToken += 1
	local token = self._saveToken
	self.Status = "Unsaved"
	task.delay(SAVE_DELAY, function()
		if token ~= self._saveToken then
			return
		end
		local ev = Remotes:FindFirstChild("SettingsSave")
		if ev then
			self.Status = "Saving"
			self._changed:Fire("_status")
			ev:FireServer(self.Values)
		end
	end)
end

function Settings:Set(key: string, value)
	local candidate = table.clone(self.Values)
	candidate[key] = value
	local clean = SettingsConfig.Sanitize(candidate)
	if clean[key] ~= value and SettingsConfig.ByKey[key] and SettingsConfig.ByKey[key].Type ~= "Number" then
		return false -- rejected (e.g. reserved / duplicate key)
	end
	self.Values = clean
	self:Apply()
	self._changed:Fire(key)
	self:_scheduleSave()
	return true
end

function Settings:ResetToDefaults()
	self.Values = SettingsConfig.Defaults()
	self:Apply()
	self._changed:Fire("*")
	self:_scheduleSave()
end

return Settings
