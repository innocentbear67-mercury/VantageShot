--[[
	VANTAGE — Menu music (client)
	"Heavy Riff of the Dragon Slayer" plays from the moment the lobby / main menu appears
	(VantageMainMenu enabled after the loader hand-off), loops, and fades out when the player
	deploys. Re-opening the menu fades it back in from where it left off.
	Routed through the VantageMusic SoundGroup, so the Settings "Music volume" slider controls it.
	ID: ReplicatedStorage.Vantage.UI attribute MenuMusicId.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local VOLUME = 0.5
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UI = ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("UI")

local music = Instance.new("Sound")
music.Name = "VantageMenuMusic"
music.SoundId = UI:GetAttribute("MenuMusicId") or ""
music.Looped = true
music.Volume = 0
music.Parent = SoundService

local fade: Tween? = nil
local function to(volume: number, t: number, thenStop: boolean?)
	if fade then
		fade:Cancel()
	end
	fade = TweenService:Create(music, TweenInfo.new(t, Enum.EasingStyle.Sine), { Volume = volume })
	fade:Play()
	if thenStop then
		local f = fade
		f.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				music:Pause()
			end
		end)
	end
end

local function menuOpen(): boolean
	local mm = playerGui:FindFirstChild("VantageMainMenu")
	return mm ~= nil and mm:IsA("ScreenGui") and mm.Enabled
end

local wasOpen = false
local function refresh()
	if not player:GetAttribute("VantageLoaded") then
		return
	end
	local g = SoundService:FindFirstChild("VantageMusic")
	if g and g:IsA("SoundGroup") and music.SoundGroup ~= g then
		music.SoundGroup = g
	end
	local open = menuOpen()
	if open == wasOpen then
		return
	end
	wasOpen = open
	if open then
		if music.IsPaused then
			music:Resume()
		elseif not music.IsPlaying then
			music:Play()
		end
		to(VOLUME, 0.4) -- in almost at once: the riff starts with the menu
	else
		to(0, 1.5, true) -- deploy: fade out under the drop-in
	end
end

local watched = {}
local function watch(g: Instance)
	if g.Name == "VantageMainMenu" and g:IsA("ScreenGui") and not watched[g] then
		watched[g] = true
		g:GetPropertyChangedSignal("Enabled"):Connect(refresh)
		refresh()
	end
end
for _, g in playerGui:GetChildren() do
	watch(g)
end
playerGui.ChildAdded:Connect(watch)
player:GetAttributeChangedSignal("VantageLoaded"):Connect(refresh)
UI:GetAttributeChangedSignal("MenuMusicId"):Connect(function()
	music.SoundId = UI:GetAttribute("MenuMusicId") or ""
end)
refresh()
