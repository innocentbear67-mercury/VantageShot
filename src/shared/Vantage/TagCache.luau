--[[
	VANTAGE — TagCache (shared)
	CollectionService:GetTagged allocates a fresh array on every call, so frame loops must not
	call it per frame: get() hands out one live, signal-maintained array per tag instead.
	Client-agnostic — the same cache works server-side.
]]

local TagCache = {}

local CollectionService = game:GetService("CollectionService")

local caches: { [string]: { Instance } } = {}

local function find(set: { Instance }, inst: Instance): number?
	for i = 1, #set do
		if set[i] == inst then
			return i
		end
	end
	return nil
end

local function ensure(tagName: string): { Instance }
	local set = caches[tagName]
	if set then
		return set
	end
	set = {}
	caches[tagName] = set
	-- signals connect before the seed so nothing tagged in between is missed; the membership
	-- guards make add/remove idempotent even if a signal lands twice around the seed
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(inst)
		if not find(set, inst) then
			set[#set + 1] = inst
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(inst)
		local i = find(set, inst)
		if i then
			set[i] = set[#set]
			set[#set] = nil
		end
	end)
	for _, inst in CollectionService:GetTagged(tagName) do
		if not find(set, inst) then
			set[#set + 1] = inst
		end
	end
	return set
end

-- The LIVE cached array for `tagName` (do not mutate; iterate it directly each frame).
function TagCache.get(tagName: string): { Instance }
	return ensure(tagName)
end

return TagCache
