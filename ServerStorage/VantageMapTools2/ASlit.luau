local F = {}
local V = Vector3.new
local function aabb(p)
	local cf, s = p.CFrame, p.Size
	local ax = V(math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
		math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
		math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z) / 2
	return cf.Position - ax, cf.Position + ax
end
local function isBox(p)
	if not p:IsA("Part") or p.Shape ~= Enum.PartType.Block then return false end
	local cf = p.CFrame
	local function ax(v) return math.abs(math.abs(v.X) - 1) < 1e-3 or math.abs(math.abs(v.Y) - 1) < 1e-3 or math.abs(math.abs(v.Z) - 1) < 1e-3 end
	return ax(cf.RightVector) and ax(cf.UpVector)
end
function F.fix(map, O, box, ceilY, minGap, maxGap)
	minGap, maxGap = minGap or 0.3, maxGap or 3.0
	local geo = {}
	for _, c in ipairs(map:GetChildren()) do if c.Name ~= "Gameplay" and c.Name ~= "Systems" then table.insert(geo, c) end end
	local inc = RaycastParams.new() inc.FilterType = Enum.RaycastFilterType.Include inc.FilterDescendantsInstances = geo
	local pairsDone, made, skipped = {}, 0, 0
	local folder = map:FindFirstChild("SlitFill") or Instance.new("Folder") folder.Name = "SlitFill" folder.Parent = map
	for x = box[1] + 1, box[2] - 1, 1 do
		for z = box[3] + 1, box[4] - 1, 1 do
			local f = workspace:Raycast(O + V(x, ceilY - 2, z), V(0, -(ceilY + 30), 0), inc)
			if f and f.Normal.Y > 0.7 then
				local p = f.Position + V(0, 2.5, 0)
				for _, dir in ipairs({ V(1, 0, 0), V(0, 0, 1) }) do
					local a = workspace:Raycast(p, dir * 3, inc) local b = workspace:Raycast(p, -dir * 3, inc)
					if a and b then
						local g = (a.Position - b.Position).Magnitude
						if g > minGap and g < maxGap and a.Instance ~= b.Instance then
							local A, B = a.Instance, b.Instance
							local key = (A:GetDebugId() < B:GetDebugId()) and (A:GetDebugId() .. B:GetDebugId()) or (B:GetDebugId() .. A:GetDebugId())
							if not pairsDone[key] then
								pairsDone[key] = true
								if isBox(A) and isBox(B) or (isBox(A) or isBox(B)) then
									local amin, amax = aabb(A) local bmin, bmax = aabb(B)
									local fy = f.Position.Y
									local top = math.min(amax.Y, bmax.Y)
									local gx0, gx1, gz0, gz1
									if dir.X ~= 0 then
										gx0, gx1 = math.min(amax.X, bmax.X), math.max(amin.X, bmin.X)
										if amax.X < bmin.X + 0.01 then gx0, gx1 = amax.X, bmin.X else gx0, gx1 = bmax.X, amin.X end
										gz0, gz1 = math.max(amin.Z, bmin.Z), math.min(amax.Z, bmax.Z)
									else
										if amax.Z < bmin.Z + 0.01 then gz0, gz1 = amax.Z, bmin.Z else gz0, gz1 = bmax.Z, amin.Z end
										gx0, gx1 = math.max(amin.X, bmin.X), math.min(amax.X, bmax.X)
									end
									local w, d, h = gx1 - gx0, gz1 - gz0, top - fy
									if w > 0.05 and d > 0.05 and h > 0.5 and w < maxGap + 0.5 or d < maxGap + 0.5 and w > 0.05 and d > 0.05 and h > 0.5 then
										local src = (isBox(A) and A) or B
										local q = Instance.new("Part") q.Anchored = true
										q.Size = V(w, h, d) q.CFrame = CFrame.new((gx0 + gx1) / 2, fy + h / 2, (gz0 + gz1) / 2)
										q.Color = src.Color q.Material = src.Material q.MaterialVariant = src.MaterialVariant
										q.TopSurface = Enum.SurfaceType.Smooth q.BottomSurface = Enum.SurfaceType.Smooth
										q.Name = "SlitFill" if src:GetAttribute("NoGrapple") then q:SetAttribute("NoGrapple", true) end
										q.Parent = folder made += 1
									else skipped += 1 end
								else skipped += 1 end
							end
						end
					end
				end
			end
		end
		if math.floor(x) % 10 == 0 then task.wait() end
	end
	return made, skipped
end
return F
