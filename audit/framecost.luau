-- Frame-cost check for VantageShot (runs under Lune).
-- Rule:
--   R1 gettagged-in-frame-loop
--      a ':GetTagged(' line within 25 lines BELOW a RenderStepped:Connect / Heartbeat:Connect /
--      BindToRenderStep( line — GetTagged allocates a fresh array per call, so calling it from a
--      frame loop is per-frame churn; iterate a maintained TagCache set instead.
-- Matching is deliberately coarse (25-line window, no AST) — it errs toward flagging;
-- the allowlist keeps the current state honest.
-- Today's violations are grandfathered in audit/frame_violations.txt; only NEW violations
-- fail the build.
-- Regenerate the current list:  lune run audit/framecost.luau --dump
local fs = require("@lune/fs")
local process = require("@lune/process")

local DUMP = process.args[1] == "--dump"

local WINDOW = 25
local STEPPERS: { string } = { "RenderStepped:Connect", "Heartbeat:Connect", "BindToRenderStep(" }
local RULE = "gettagged-in-frame-loop"

local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, out)
		elseif name:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

local all: { string } = {}
walk("src", all)
table.sort(all)

local violations: { string } = {}

for _, path in all do
	local ok, src = pcall(fs.readFile, path)
	if ok then
		local lines: { string } = {}
		local steppers: { number } = {}
		local gettagged: { number } = {}
		for line in (src .. "\n"):gmatch("([^\n]*)\n") do
			table.insert(lines, line)
			for _, pat in STEPPERS do
				if line:find(pat, 1, true) then
					table.insert(steppers, #lines)
					break
				end
			end
			if line:find(":GetTagged(", 1, true) then
				table.insert(gettagged, #lines)
			end
		end
		for _, g in gettagged do
			for _, s in steppers do
				if s < g and g - s <= WINDOW then
					local detail = lines[g]:gsub("^%s+", ""):sub(1, 90)
					table.insert(violations, string.format("%s:%d: %s: %s", path, g, RULE, detail))
					break
				end
			end
		end
	end
end

table.sort(violations)

if DUMP then
	for _, v in violations do
		print(v)
	end
	process.exit(0)
end

local allowSet = {}
local ok, data = pcall(fs.readFile, "audit/frame_violations.txt")
if ok then
	for line in (data .. "\n"):gmatch("([^\n]*)\n") do
		if #line > 0 then
			allowSet[line] = true
		end
	end
end

local newCount = 0
for _, v in violations do
	if not allowSet[v] then
		newCount += 1
		print("NEW frame violation: " .. v)
	end
end
print(string.format("framecost: %d current, %d new", #violations, newCount))
process.exit(if newCount > 0 then 1 else 0)
