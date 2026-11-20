--[[
	VANTAGE — minimal HUD (user decision 2026-11-14: no visor HUD).
	The exosuit visor (VantageVisorClient) is live and H-toggleable; this script never touches it. What stays on screen: the crosshair, the
	ammo count and the hit markers / damage numbers (all drawn by VantageWeaponClient.Hud).
	Parked here, still updated, never shown: Vitals, Score, Radar and the settings hint.
	VantageAbilities is left alone: disabling that ScreenGui also kills the grapple (E) input.
	To bring the parked HUD panels back: delete this script.
]]
local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local PARK = { "Vitals", "Score", "Radar", "SettingsHint" }

local function park(hudGui: Instance)
	local root = hudGui:WaitForChild("Root", 10)
	if not root then
		return
	end
	local stash = hudGui:FindFirstChild("MinimalStash")
	if not stash then
		stash = Instance.new("Frame")
		stash.Name = "MinimalStash"
		stash.Visible = false
		stash.BackgroundTransparency = 1
		stash.Size = UDim2.fromScale(1, 1)
		stash.Parent = hudGui
	end
	for _, n in PARK do
		local c = root:FindFirstChild(n) or root:WaitForChild(n, 5)
		if c then
			c.Parent = stash
		end
	end
end

local function watch(g: Instance)
	if g.Name == "VantageHUD" then
		task.spawn(park, g)
	end
end
for _, g in playerGui:GetChildren() do
	watch(g)
end
playerGui.ChildAdded:Connect(watch)
