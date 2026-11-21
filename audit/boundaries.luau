-- Boundary check for VantageShot (runs under Lune).
-- Rules:
--   R1 client-script-outside-client-container
--      *.client.luau outside the client roots (src/client, ReplicatedFirst, StarterPlayer)
--   R2 server-script-outside-server-container
--      *.server.luau outside the server roots (src/server, ServerStorage, Workspace)
--   R3 client-reaches-into-server
--      client code referencing ServerScriptService / ServerStorage
--   R4 server-uses-client-state
--      runtime server code (src/server, Workspace) referencing
--      StarterPlayerScripts / Players.LocalPlayer — both are nil/absent on the
--      server, so any such reference is dead or broken.
--   R5 inline-remote-factory
--      src/server code creating RemoteEvent / RemoteFunction instances directly instead of
--      going through the shared factory (src/shared/Vantage/RemotesLib.luau — Remotes.get)
-- Today's violations are grandfathered in audit/boundary_violations.txt; only
-- NEW violations fail the build. String matching is deliberately coarse — it
-- errs toward flagging; the allowlist keeps the current state honest.
-- Regenerate the current list:  lune run audit/boundaries.luau --dump
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DUMP = process.args[1] == "--dump"

local CLIENT_ROOTS: { string } = { "src/client", "ReplicatedFirst", "StarterPlayer" }
local SERVER_ROOTS: { string } = { "src/server", "ServerStorage", "Workspace" }
local RUNTIME_SERVER_ROOTS: { string } = { "src/server", "Workspace" }

-- Client-context scripts: files whose default.project.json node sets RunContext=Client.
-- They may legally use LocalPlayer / RenderStepped even outside src/client.
local clientContext: { [string]: boolean } = {}
do
	local okRaw, raw = pcall(fs.readFile, "default.project.json")
	if okRaw then
		local okParse, tree = pcall(serde.decode, "json", raw)
		if okParse and type(tree) == "table" then
			local function walkTree(node: any)
				if type(node) ~= "table" then
					return
				end
				local props = node["$properties"]
				local isClient = type(props) == "table" and props["RunContext"] == "Client"
				local p = node["$path"]
				if isClient then
					if type(p) == "string" then
						clientContext[p] = true
					elseif type(p) == "table" then
						for _, pp in p do
							clientContext[pp] = true
						end
					end
				end
				for _, v in node do
					if type(v) == "table" then
						walkTree(v)
					end
				end
			end
			walkTree(tree)
		end
	end
end

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function under(path: string, roots: { string }): boolean
	for _, r in roots do
		if startsWith(path, r .. "/") then
			return true
		end
	end
	return false
end

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

local violations: { string } = {}

local function report(path: string, line: number, rule: string, detail: string)
	table.insert(violations, string.format("%s:%d: %s: %s", path, line, rule, detail))
end

local all: { string } = {}
for _, r in CLIENT_ROOTS do
	walk(r, all)
end
for _, r in SERVER_ROOTS do
	walk(r, all)
end

for _, path in all do
	local name = path:match("([^/]+)$") or path
	if name:match("%.client%.luau$") and not under(path, CLIENT_ROOTS) then
		report(path, 0, "client-script-outside-client-container", "move into src/client (or ReplicatedFirst/StarterPlayer)")
	elseif name:match("%.server%.luau$") and not under(path, SERVER_ROOTS) then
		report(path, 0, "server-script-outside-server-container", "move into src/server (or ServerStorage/Workspace)")
	end
end

local function scanContent(path: string, patterns: { string }, rule: string)
	local ok, src = pcall(fs.readFile, path)
	if not ok then
		return
	end
	local lineNo = 0
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		lineNo += 1
		for _, pat in patterns do
			if line:find(pat, 1, true) then
				local detail = line:gsub("^%s+", ""):sub(1, 90)
				report(path, lineNo, rule, detail)
				break
			end
		end
	end
end

for _, path in all do
	if under(path, CLIENT_ROOTS) then
		scanContent(path, { "ServerScriptService", "ServerStorage" }, "client-reaches-into-server")
	elseif under(path, RUNTIME_SERVER_ROOTS) and not clientContext[path] then
		scanContent(path, { "StarterPlayerScripts", ".LocalPlayer" }, "server-uses-client-state")
	end
end

-- R5: the factory itself (src/shared/Vantage/RemotesLib.luau), tests/ and audit/ are exempt.
local function inlineRemoteFactoryExempt(path: string): boolean
	return path == "src/shared/Vantage/RemotesLib.luau"
		or startsWith(path, "tests/")
		or startsWith(path, "audit/")
end
for _, path in all do
	if under(path, { "src/server" }) and not inlineRemoteFactoryExempt(path) then
		scanContent(path, { 'Instance.new("RemoteEvent")', 'Instance.new("RemoteFunction")' }, "inline-remote-factory")
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
local ok, data = pcall(fs.readFile, "audit/boundary_violations.txt")
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
		print("NEW boundary violation: " .. v)
	end
end
print(string.format("boundary: %d current, %d new", #violations, newCount))
process.exit(if newCount > 0 then 1 else 0)
