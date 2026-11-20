-- ECLIPSE ambient motion (client only, ~30 Hz, skipped when far from the camera)
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local items = {}
local function add(m)
	if m:IsA("Model") then
		items[m] = m:GetPivot()
	end
end
for _, m in CS:GetTagged("EclipseAnim") do
	add(m)
end
CS:GetInstanceAddedSignal("EclipseAnim"):Connect(add)
CS:GetInstanceRemovedSignal("EclipseAnim"):Connect(function(m)
	items[m] = nil
end)
local acc = 0
RS.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < 1 / 30 then
		return
	end
	acc = 0
	local t = os.clock()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	for m, base in items do
		if not m.Parent then
			items[m] = nil
			continue
		end
		if (base.Position - cp).Magnitude > (m:GetAttribute("AnimRange") or 500) then
			continue
		end
		local cf = base
		local spin = m:GetAttribute("Spin")
		if spin then
			cf = cf * CFrame.Angles(0, t * spin, 0)
		end
		local bob = m:GetAttribute("Bob")
		if bob then
			cf = cf + Vector3.new(0, math.sin(t * (m:GetAttribute("BobSpeed") or 1) + (m:GetAttribute("Phase") or 0)) * bob, 0)
		end
		m:PivotTo(cf)
	end
end)
