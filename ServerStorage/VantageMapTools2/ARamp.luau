local R = {}
local V = Vector3.new
-- extend steep ramps (WedgeParts) keeping the high end; returns list of changes
function R.fix(map, maxDeg, targetDeg, skip)
	skip = skip or {}
	local out = {}
	local geo = {}
	for _, c in ipairs(map:GetChildren()) do if c.Name ~= "Gameplay" and c.Name ~= "Systems" then table.insert(geo, c) end end
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Include
	for _, w in ipairs(map:GetDescendants()) do
		if w:IsA("WedgePart") and w.CanCollide and not skip[w.Name] and math.abs(w.CFrame.UpVector.Y - 1) < 1e-3 then
			local H, L = w.Size.Y, w.Size.Z
			local deg = math.deg(math.atan(H / L))
			if deg > maxDeg and H >= 3 and H <= 30 then
				local look = w.CFrame.LookVector
				-- find high end empirically
				rp.FilterDescendantsInstances = { w }
				local endA = w.Position + look * (L / 2 - 0.3) + V(0, H, 0)
				local endB = w.Position - look * (L / 2 - 0.3) + V(0, H, 0)
				local ha = workspace:Raycast(endA, V(0, -2 * H, 0), rp)
				local hb = workspace:Raycast(endB, V(0, -2 * H, 0), rp)
				local highDir = (ha and hb and ha.Position.Y > hb.Position.Y) and look or -look
				local highEnd = w.Position + highDir * (L / 2)
				local want = H / math.tan(math.rad(targetDeg))
				local best = L
				-- try extending in steps, checking the extra footprint is clear (ignore floors/self)
				local ov = OverlapParams.new() ov.FilterType = Enum.RaycastFilterType.Include ov.FilterDescendantsInstances = geo
				for Lt = want, L + 1, -1 do
					local ext = Lt - L
					local c = w.Position - highDir * (L / 2 + ext / 2)
					local sz = V(w.Size.X - 0.2, H * (ext / Lt) + 0.0, ext)
					local cf = CFrame.lookAt(V(c.X, w.Position.Y - H / 2 + 0.6 + (H * ext / Lt) / 2, c.Z), V(c.X, w.Position.Y - H / 2 + 0.6 + (H * ext / Lt) / 2, c.Z) + highDir)
					local clear = true
					for _, p in ipairs(workspace:GetPartBoundsInBox(cf, V(w.Size.X - 0.2, math.max(H * ext / Lt, 1), ext), ov)) do
						if p ~= w and p.CanCollide and p.Size.Y < 400 and not (p.Position.Y + p.Size.Y / 2 <= w.Position.Y - H / 2 + 0.05) then clear = false break end
					end
					if clear then best = Lt break end
				end
				if best > L + 0.5 then
					local newC = highEnd - highDir * (best / 2)
					w.Size = V(w.Size.X, H, best)
					w.CFrame = CFrame.lookAt(V(newC.X, w.Position.Y, newC.Z), V(newC.X, w.Position.Y, newC.Z) + w.CFrame.LookVector)
					table.insert(out, ("%s %.0f->%.0f deg (run %.1f->%.1f)"):format(w.Name, deg, math.deg(math.atan(H / best)), L, best))
				else
					table.insert(out, ("%s %.0f deg KEPT (no room)"):format(w.Name, deg))
				end
			end
		end
	end
	return out
end
return R
