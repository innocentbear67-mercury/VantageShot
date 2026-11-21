-- Animates HyperLobby props on the client. Tags: HL_Anim (spin + bob around the stored BasePivot attribute),
-- HL_Pulse (glow transparency), HL_Scroll (UIGradient offset). Safe with StreamingEnabled: positions come from
-- the BasePivot attribute saved at edit time, and models are only moved once their parts have streamed in.
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local lobby = workspace:WaitForChild("HyperLobby", 30)
if not lobby then return end
local ORIGIN = Vector3.new(0, 3000, -20)
local RANGE = 340
local anims, pulses, scrolls = {}, {}, {}
local function addAnim(inst)
	if not inst:IsDescendantOf(lobby) then return end
	local base = inst:GetAttribute("BasePivot")
	if typeof(base) ~= "CFrame" then return end
	anims[inst] = { base = base, spin = inst:GetAttribute("Spin") or 0, bob = inst:GetAttribute("Bob") or 0,
		period = math.max(inst:GetAttribute("BobPeriod") or 3, 0.1), phase = inst:GetAttribute("Phase") or 0 }
end
local function addPulse(p) if p:IsDescendantOf(lobby) then pulses[p] = { base = p.Transparency, amp = p:GetAttribute("PulseAmp") or 0.5, period = math.max(p:GetAttribute("PulsePeriod") or 2, 0.1), phase = p:GetAttribute("Phase") or 0 } end end
local function addScroll(g) if g:IsDescendantOf(lobby) then scrolls[g] = g:GetAttribute("Speed") or 0.3 end end
for _, i in ipairs(CS:GetTagged("HL_Anim")) do addAnim(i) end
for _, i in ipairs(CS:GetTagged("HL_Pulse")) do addPulse(i) end
for _, i in ipairs(CS:GetTagged("HL_Scroll")) do addScroll(i) end
CS:GetInstanceAddedSignal("HL_Anim"):Connect(addAnim)
CS:GetInstanceAddedSignal("HL_Pulse"):Connect(addPulse)
CS:GetInstanceAddedSignal("HL_Scroll"):Connect(addScroll)
local function hasParts(m) return m:FindFirstChildWhichIsA("BasePart", true) ~= nil end
local t = 0
RunService.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - ORIGIN).Magnitude > RANGE then return end
	t += dt
	for inst, a in pairs(anims) do
		if inst.Parent then
			local y = a.bob ~= 0 and a.bob * math.sin(t * 2 * math.pi / a.period + a.phase) or 0
			local cf = a.base + Vector3.new(0, y, 0)
			if a.spin ~= 0 then cf = CFrame.new(cf.Position) * CFrame.Angles(0, math.rad(a.spin * t), 0) * a.base.Rotation end
			if inst:IsA("Model") then
				if hasParts(inst) then inst:PivotTo(cf) end
			else inst.CFrame = cf end
		else anims[inst] = nil end
	end
	for p, a in pairs(pulses) do
		if p.Parent then p.Transparency = math.clamp(a.base + a.amp * (0.5 + 0.5 * math.sin(t * 2 * math.pi / a.period + a.phase)), 0, 1)
		else pulses[p] = nil end
	end
	for g, s in pairs(scrolls) do
		if g.Parent then g.Offset = Vector2.new(((t * s) % 2) - 1, 0) else scrolls[g] = nil end
	end
end)
