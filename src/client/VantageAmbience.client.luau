--[[
	VANTAGE — Ambience (client)
	Training-facility ambience bed. Fades in when the loader hands off (VantageLoaded), so the
	loader's digital hum cross-fades into the arena's room tone. Licensed ProSoundEffects audio.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AMBIENCE_ID = "rbxassetid://9112839511" -- Oil Refinery Ambience 2 (SFX): steady industrial bed
local VOLUME = 0.18

local player = Players.LocalPlayer
local s = Instance.new("Sound")
s.Name = "VantageAmbience"
s.SoundId = AMBIENCE_ID
s.Looped = true
s.Volume = 0
s.Parent = SoundService

local function start()
	-- respect the master volume group the weapon client creates, if present
	local g = SoundService:FindFirstChild("VantageEffects")
	if g and g:IsA("SoundGroup") then
		s.SoundGroup = g
	end
	if not s.IsPlaying then
		s:Play()
	end
	TweenService:Create(s, TweenInfo.new(2.4, Enum.EasingStyle.Sine), { Volume = VOLUME }):Play()
end

if player:GetAttribute("VantageLoaded") then
	start()
else
	player:GetAttributeChangedSignal("VantageLoaded"):Once(start)
end
