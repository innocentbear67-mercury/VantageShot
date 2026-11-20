-- lime jump pads: stand on one and get thrown in an arc onto its target (PadTarget attribute)
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local player = Players.LocalPlayer
local last = 0
RS.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or os.clock() - last < 0.8 then return end
	local pos = root.Position
	for _, pad in CS:GetTagged("JumpPad") do
		local target = pad:GetAttribute("PadTarget")
		if typeof(target) == "Vector3" then
			local rel = pad.CFrame:PointToObjectSpace(pos)
			local h = pad.Size
			if math.abs(rel.X) <= h.X / 2 + 0.5 and math.abs(rel.Z) <= h.Z / 2 + 0.5 and rel.Y > 0 and rel.Y < 6 then
				last = os.clock()
				local g = workspace.Gravity
				local start = pad.Position + Vector3.new(0, h.Y / 2, 0)
				local rise = math.max(target.Y - start.Y, 0)
				local apex = rise + 10
				local vy = math.sqrt(2 * g * apex)
				local t = vy / g + math.sqrt(2 * (apex - rise) / g)
				local flat = Vector3.new(target.X - start.X, 0, target.Z - start.Z)
				root.AssemblyLinearVelocity = flat / t + Vector3.new(0, vy, 0)
				break
			end
		end
	end
end)