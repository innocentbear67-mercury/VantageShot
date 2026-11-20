-- Writes Live Fire terrain from a heightmap decal (R,G = (h+40)*2 as 16-bit; B = material*40). 161x161, 8-stud cells over x,z -640..640.
local M = {}
local IS = game:GetService("InsertService")
local AS = game:GetService("AssetService")
local Mat = Enum.Material
local MAT = {[0] = Mat.Grass, Mat.Ground, Mat.Rock, Mat.Concrete, Mat.Asphalt, Mat.Mud}

function M.load(decalId)
	local m = IS:LoadAsset(decalId); local tex = m:FindFirstChildWhichIsA("Decal", true).Texture; m:Destroy()
	local img
	for _ = 1, 20 do
		local ok, r = pcall(function() return AS:CreateEditableImageAsync(Content.fromUri(tex)) end)
		if ok then img = r break end
		task.wait(3)
	end
	assert(img, "heightmap image did not load")
	local W = img.Size.X
	local buf = img:ReadPixelsBuffer(Vector2.zero, img.Size)
	local Hg, Mg = {}, {}
	for r = 0, W - 1 do for c = 0, W - 1 do
		local i = (r * W + c) * 4
		Hg[r * W + c] = (buffer.readu8(buf, i) * 256 + buffer.readu8(buf, i + 1)) / 2 - 42
		Mg[r * W + c] = math.floor(buffer.readu8(buf, i + 2) / 40 + 0.5)
	end end
	img:Destroy()
	local C = 1280 / (W - 1)
	local hm = {W = W, H = Hg, M = Mg, C = C}
	function hm.h(x, z)
		local fx, fz = (x + 640) / C, (z + 640) / C
		local c0, r0 = math.clamp(math.floor(fx), 0, W - 2), math.clamp(math.floor(fz), 0, W - 2)
		local tx, tz = math.clamp(fx - c0, 0, 1), math.clamp(fz - r0, 0, 1)
		local a, b = Hg[r0 * W + c0], Hg[r0 * W + c0 + 1]
		local c, d = Hg[(r0 + 1) * W + c0], Hg[(r0 + 1) * W + c0 + 1]
		return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz
	end
	function hm.m(x, z)
		local c = math.clamp(math.floor((x + 640) / C + 0.5), 0, W - 1); local r = math.clamp(math.floor((z + 640) / C + 0.5), 0, W - 1)
		return MAT[Mg[r * W + c]] or Mat.Grass
	end
	return hm
end

function M.write(hm)
	local T = workspace.Terrain
	local Y0, NY, CH = -84, 57, 32
	for cx = -640, 639, CH * 4 do
		for cz = -640, 639, CH * 4 do
			local mats, occ = {}, {}
			for i = 1, CH do
				mats[i], occ[i] = {}, {}
				for j = 1, NY do mats[i][j], occ[i][j] = {}, {} end
				local x = cx + (i - 0.5) * 4
				for k = 1, CH do
					local z = cz + (k - 0.5) * 4
					local h = hm.h(x, z); local sm = hm.m(x, z)
					for j = 1, NY do
						local yb = Y0 + (j - 1) * 4
						local o = math.clamp((h - yb) / 4, 0, 1)
						occ[i][j][k] = o
						mats[i][j][k] = o <= 0 and Mat.Air or ((h - yb) > 10 and (sm == Mat.Grass or sm == Mat.Ground) and Mat.Ground or sm)
					end
				end
			end
			T:WriteVoxels(Region3.new(Vector3.new(cx, Y0, cz), Vector3.new(cx + CH * 4, Y0 + NY * 4, cz + CH * 4)), 4, mats, occ)
			task.wait()
		end
	end
end
return M
