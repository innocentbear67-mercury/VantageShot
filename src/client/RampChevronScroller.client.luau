-- scrolls the chevrons on vehicle boost ramps uphill (toward their tips)
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local SPEED = 16 -- studs per second
local off = 0
RS.Heartbeat:Connect(function(dt)
	off += SPEED * dt
	for _, t in CS:GetTagged("RampChevron") do
		t.OffsetStudsV = off % t.StudsPerTileV
	end
end)