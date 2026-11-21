--[[
	VANTAGE — Battle music (client)
	Loops the battle track while this player's match is Live (MatchService phase "Live"),
	fades in at the start of combat and out when the match ends. Every new match starts the
	track from the top. Routed through the VantageMusic SoundGroup, so the Settings
	"Music volume" slider controls it, and VANTAGE CONTROL voice lines duck it automatically.
	ID: ReplicatedStorage.Vantage.UI attribute BattleMusicId.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local VOLUME = 0.2 -- 2026-11-14: halved so hit feedback cuts through
local FADE_IN, FADE_OUT = 2.5, 2

local player = Players.LocalPlayer
local Vantage = ReplicatedStorage:WaitForChild("Vantage")
local UI = Vantage:WaitForChild("UI")
local Match = Vantage:WaitForChild("Match")

local music = Instance.new("Sound")
music.Name = "VantageBattleMusic"
music.SoundId = UI:GetAttribute("BattleMusicId") or ""
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
				music:Stop()
			end
		end)
	end
end

local playingFor = nil -- MatchId the track is currently playing for
local function inLiveMatch(): boolean
	return Match:GetAttribute("Phase") == "Live"
		and player:GetAttribute("MatchStatus") == "Match"
		and player:GetAttribute("MatchId") == Match:GetAttribute("MatchId")
end

local function refresh()
	local g = SoundService:FindFirstChild("VantageMusic")
	if g and g:IsA("SoundGroup") and music.SoundGroup ~= g then
		music.SoundGroup = g
	end
	if inLiveMatch() then
		local id = Match:GetAttribute("MatchId")
		if playingFor ~= id then
			playingFor = id
			music.TimePosition = 0
			music:Play()
		elseif not music.IsPlaying then
			music:Resume()
		end
		to(VOLUME, FADE_IN)
	elseif playingFor ~= nil then
		playingFor = nil
		to(0, FADE_OUT, true)
	end
end

Match:GetAttributeChangedSignal("Phase"):Connect(refresh)
Match:GetAttributeChangedSignal("MatchId"):Connect(refresh)
player:GetAttributeChangedSignal("MatchStatus"):Connect(refresh)
player:GetAttributeChangedSignal("MatchId"):Connect(refresh)
SoundService.ChildAdded:Connect(function(c)
	if c.Name == "VantageMusic" then
		refresh()
	end
end)
UI:GetAttributeChangedSignal("BattleMusicId"):Connect(function()
	music.SoundId = UI:GetAttribute("BattleMusicId") or ""
end)
refresh()
