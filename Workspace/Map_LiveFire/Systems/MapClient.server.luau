-- ECLIPSE map client: gravity lifts launch the local character (it owns its physics).
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local map = script.Parent.Parent
local lifts = map:WaitForChild("Gameplay"):WaitForChild("Lifts")
local cool = 0
local function hook(lift)
	lift.Touched:Connect(function(hit)
		local char = player.Character
		if not char or not hit:IsDescendantOf(char) or os.clock() < cool then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not (root and hum) or hum.Health <= 0 then
			return
		end
		cool = os.clock() + 1
		local h = lift:GetAttribute("LiftHeight") or 30
		local push = lift:GetAttribute("LiftPush") or Vector3.zero
		local vy = math.sqrt(2 * workspace.Gravity * (h + 4))
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		-- LiftClearY: hold the push until the player has risen out of a shaft
		local clearY = lift:GetAttribute("LiftClearY")
		root.AssemblyLinearVelocity = if clearY then Vector3.new(0, vy, 0) else Vector3.new(push.X, vy, push.Z)
		if push.Magnitude > 0 then
			-- carry the player along the push until they land, so the lift delivers them onto its landing
			local t0 = os.clock()
			local conn
			conn = game:GetService("RunService").Heartbeat:Connect(function()
				local st = hum:GetState()
				local landed = os.clock() - t0 > 0.25 and (st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed)
				if landed or os.clock() - t0 > 2.5 or hum.Health <= 0 or not root.Parent then
					conn:Disconnect()
					return
				end
				local v = root.AssemblyLinearVelocity
				if clearY and root.Position.Y < clearY then
					root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
					return
				end
				local flat = Vector3.new(v.X, 0, v.Z)
				local want = push + hum.MoveDirection * 8
				if flat:Dot(push.Unit) < push.Magnitude then
					root.AssemblyLinearVelocity = Vector3.new(want.X, v.Y, want.Z)
				end
			end)
		end
	end)
end
for _, l in lifts:GetChildren() do hook(l) end
lifts.ChildAdded:Connect(hook)
