--[[
	VANTAGE — default character sound mute (2026-11-17)
	Roblox's built-in RbxCharacterSounds plays a cartoon jump "boing", a falling-wind loop and a
	get-up / death grunt on every character. Hypershot has none of these; our own footstep system
	(VantageFootsteps) does steps, push-off and landings. This silences only those four on every
	character this client hears (Running / Landing stay for other players' footsteps).
]]
local Players = game:GetService("Players")

local MUTE = { Jumping = true, FreeFalling = true, GettingUp = true, Died = true }

local function lock(d: Instance)
	if not MUTE[d.Name] or not (d:IsA("Sound") or d:IsA("AudioPlayer")) then
		return
	end
	local obj = d :: any
	obj.Volume = 0
	d:GetPropertyChangedSignal("Volume"):Connect(function()
		if obj.Volume ~= 0 then
			obj.Volume = 0
		end
	end)
end

local function watch(character: Model)
	for _, d in character:GetDescendants() do
		lock(d)
	end
	character.DescendantAdded:Connect(lock)
end

local function onPlayer(p: Player)
	if p.Character then
		watch(p.Character)
	end
	p.CharacterAdded:Connect(watch)
end

for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
