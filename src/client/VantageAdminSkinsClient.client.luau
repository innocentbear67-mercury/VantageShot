--[[
	VANTAGE — AdminSkinsClient (2026-11-15)
	Hotkeys for the admin skin checker (server: ServerScriptService.VantageAdminSkins):
	  =  next skin     -  previous skin     (+ /skin chat command)
	Shows a small toast with the skin name. The server ignores non-admins, so nothing happens for them.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("VantageAdminSkin")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "VantageAdminSkinToast"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 200
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 74)
label.Size = UDim2.fromOffset(0, 34)
label.AutomaticSize = Enum.AutomaticSize.X
label.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
label.BackgroundTransparency = 1
label.TextTransparency = 1
label.TextColor3 = Color3.fromRGB(240, 244, 250)
label.Font = Enum.Font.GothamBold
label.TextSize = 16
label.Text = ""
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)
pad.Parent = label
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = label
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local shown = 0
remote.OnClientEvent:Connect(function(text: string)
	shown += 1
	local me = shown
	label.Text = "SKIN  ·  " .. text
	label.BackgroundTransparency = 0.25
	label.TextTransparency = 0
	task.delay(2.4, function()
		if me == shown then
			local ti = TweenInfo.new(0.35)
			TweenService:Create(label, ti, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end
	end)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Equals then
		remote:FireServer("next")
	elseif input.KeyCode == Enum.KeyCode.Minus then
		remote:FireServer("prev")
	end
end)
