-- Minimal Lune test runner: executes every tests/*.test.luau and exits 1 on
-- any failure. Run from the repo root:  lune run tests/run.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local names = fs.readDir("tests")
table.sort(names)

local failed: { string } = {}
local ran = 0

for _, name in names do
	if name:match("%.test%.luau$") then
		ran += 1
		local ok, err = pcall(function()
			require("./" .. name:gsub("%.luau$", ""))
		end)
		if not ok then
			table.insert(failed, string.format("%s: %s", name, tostring(err)))
		end
	end
end

for _, f in failed do
	print("FAIL " .. f)
end
print(string.format("tests: %d ran, %d failed", ran, #failed))
process.exit(if #failed == 0 then 0 else 1)
