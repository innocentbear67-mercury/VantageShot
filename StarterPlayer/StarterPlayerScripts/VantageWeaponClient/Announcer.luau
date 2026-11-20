--[[
	VANTAGE — Announcer (client)
	One voice at a time. A new line plays only if nothing is speaking and the cooldown has passed,
	or if it outranks the line currently speaking (which is cut off). Equal / lower lines are
	dropped, so rapid kills never stack voices.
	Lines live in EliminationConfig.Announcer.Lines. A line with Id = "" has no voice asset yet
	and plays the configured non-voice placeholder sting (pitched by priority) instead.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local ElimConfig = require(ReplicatedStorage.Vantage.Elimination.EliminationConfig)
local A = ElimConfig.Announcer

local Announcer = {}
local group: SoundGroup? = nil
local current: Sound? = nil
local currentPriority = 0
local lastStart = -math.huge

function Announcer.Init(soundGroup: SoundGroup?)
	group = soundGroup
end

-- Returns true if the line was played.
function Announcer.Play(line): boolean
	if A.Enabled == false then
		return false -- 2026-11-17: no announcer voice (Hypershot)
	end
	local now = os.clock()
	local speaking = current ~= nil and current.Parent ~= nil and current.IsPlaying
	local busy = speaking or now - lastStart < A.Cooldown
	if busy and line.Priority <= currentPriority then
		return false
	end
	if current then
		current:Destroy()
		current = nil
	end
	local s = Instance.new("Sound")
	s.Name = "Announcer_" .. line.Text
	if line.Id ~= "" then
		s.SoundId = line.Id
		s.Volume = A.Volume
	else
		-- PLACEHOLDER: no voice recording for this line yet
		local P = A.Placeholder
		s.SoundId = P.Id
		s.Volume = P.Volume
		s.PlaybackSpeed = P.BaseSpeed + P.SpeedPerPriority * line.Priority
	end
	s.SoundGroup = group
	s.Parent = SoundService
	s:Play()
	current, currentPriority, lastStart = s, line.Priority, now
	s.Ended:Once(function()
		if current == s then
			current = nil
			currentPriority = 0
		end
		s:Destroy()
	end)
	Debris:AddItem(s, 5)
	return true
end

return Announcer
