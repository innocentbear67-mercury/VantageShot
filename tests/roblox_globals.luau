--[[
	Engine-type environment helper for the Lune test suite (NOT a test file —
	the runner only globs *.test.luau).

	HISTORY (injection probe, 2026-11-21): Lune 0.11.1 does NOT let a test
	inject engine globals through _G — required modules get their own globals
	table and a `_G.Vector3 = roblox.Vector3` write does not even register in
	the writing script itself (`typeof(Vector3)` -> "nil" one line later).
	Verbatim probe failure:
	  WeaponMath:48: attempt to index nil with 'lookAt'

	The working, DOCUMENTED mechanism is @lune/luau's
	`luau.load(source, { debugName = ..., environment = env })`: the chunk
	runs with exactly the table passed as its globals. This helper builds
	that environment (standard library + the Roblox engine datatypes a pure
	shared module references as globals) and loads shared modules with it.

	Modules whose only DataModel dependency is a script-relative require
	(Weapons/Configs/*) get a fake `script` + fake `require` supplied by the
	calling test — the fake require hands back this helper's real ConfigBase
	module table, so the module's own merge code runs unmodified.
]]

local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local RG = {}
RG.roblox = roblox

-- Globals for luau.load-ed module chunks. Every engine datatype a shared
-- config references as a global is injected; anything not listed here is a
-- test-visible gap by design.
function RG.stdEnv(extra: { [string]: any }?)
	local env = {
		math = math,
		table = table,
		string = string,
		os = os,
		next = next,
		pairs = pairs,
		ipairs = ipairs,
		select = select,
		type = type,
		typeof = typeof,
		tostring = tostring,
		tonumber = tonumber,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		assert = assert,
		error = error,
		pcall = pcall,
		unpack = unpack,
		print = print,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		NumberRange = (roblox :: any).NumberRange,
	}
	for k, v in extra or {} do
		env[k] = v
	end
	return env
end

-- Loads a shared module from the repo (path relative to the repo root,
	-- run tests from the repo root like the audit gate does) and runs it with
	-- the injected-globals environment. `extra` adds/overrides globals
	-- (fake script/require trees are supplied this way by the tests).
function RG.loadShared(path: string, extra: { [string]: any }?): any
	local okRead, src = pcall(fs.readFile, path)
	assert(okRead, "loadShared: cannot read " .. path .. ": " .. tostring(src))
	local okLoad, chunk = pcall(luau.load, src, { debugName = "@" .. path, environment = RG.stdEnv(extra) })
	assert(okLoad, "loadShared: cannot compile " .. path .. ": " .. tostring(chunk))
	local okRun, module = pcall(chunk :: () -> any)
	assert(okRun, "loadShared: " .. path .. " errored at load: " .. tostring(module))
	return module
end

return RG
