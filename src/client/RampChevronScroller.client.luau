-- scrolls the chevrons on vehicle boost ramps uphill (toward their tips)
local TagCache = require(game:GetService("ReplicatedStorage").Vantage.TagCache)
local RS = game:GetService("RunService")
local SPEED = 16 -- studs per second
local off = 0
RS.Heartbeat:Connect(function(dt)
	off += SPEED * dt
	-- B3: TagCache keeps one signal-maintained array (no per-frame GetTagged allocation); skip while empty
	local set = TagCache.get("RampChevron")
	if #set == 0 then
		return
	end
	for _, t in set do
		t.OffsetStudsV = off % t.StudsPerTileV
	end
end)
