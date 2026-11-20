-- animates jump pad chevrons: "^^" rising out of the pad and fading, looping (Hypershot style)
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local CYCLE = 1.1      -- seconds for one chevron to travel bottom -> top
local Y0, Y1 = 0.92, 0.12
local icons = {}
local function scan()
	table.clear(icons)
	for _, trig in CS:GetTagged("JumpPad") do
		local model = trig.Parent
		local anchor = model and model:FindFirstChild("PadIcon")
		local bb = anchor and anchor:FindFirstChildOfClass("BillboardGui")
		local f = bb and bb:FindFirstChildOfClass("Frame")
		if f then
			local chevs = {}
			for _, c in f:GetChildren() do if c.Name == "Chev" then table.insert(chevs, c) end end
			-- 2026-11-20 perf: cache each chevron's arms + strokes once (was GetChildren every frame)
			local parts = {}
			for i, c in chevs do
				local list = {}
				for _, arm in c:GetChildren() do
					if arm:IsA("Frame") then table.insert(list, { arm, arm:FindFirstChildOfClass("UIStroke") }) end
				end
				parts[i] = list
			end
			if #chevs > 0 then table.insert(icons, { bb = bb, chevs = chevs, arms = parts, pos = anchor.Position, phase = (anchor.Position.X * 0.37 + anchor.Position.Z * 0.21) % 1 }) end
		end
	end
end
scan()
CS:GetInstanceAddedSignal("JumpPad"):Connect(function() task.defer(scan) end)
CS:GetInstanceRemovedSignal("JumpPad"):Connect(function() task.defer(scan) end)
local function setAlpha(list, a)
	for _, e in list do
		e[1].BackgroundTransparency = a
		if e[2] then e[2].Transparency = a end
	end
end
-- only pads near the camera animate, at 30 Hz (each GUI write re-lays out the billboard)
local NEAR = 160
local nextAt = 0
RS.RenderStepped:Connect(function()
	local t = os.clock()
	if t < nextAt then return end
	nextAt = t + 1 / 30
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	for _, ic in icons do
		if ic.bb.Parent and (ic.pos - cp).Magnitude < NEAR then
			local n = #ic.chevs
			for i, chev in ic.chevs do
				local p = ((t / CYCLE) + ic.phase + (i - 1) / n) % 1
				chev.Position = UDim2.fromScale(0.5, Y0 + (Y1 - Y0) * p)
				local a = 1
				if p < 0.2 then a = p / 0.2 elseif p > 0.7 then a = (1 - p) / 0.3 end
				local s = 0.85 + 0.15 * p
				chev.Size = UDim2.fromScale(s, s)
				setAlpha(ic.arms[i], 1 - a)
			end
			ic.bb.StudsOffsetWorldSpace = Vector3.new(0, math.sin(t * 2.2 + ic.phase * 6.28) * 0.25, 0)
		end
	end
end)
