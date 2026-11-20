--[[
	VisorBus — the visor's event bus. One place every visor system listens to, so a single event
	(Damage, PulseScan, Boot ...) drives the honeycomb, radar, abilities, weapon panel and rim together.

	Bus.On(name, fn) -> disconnect()      Bus.Emit(name, ...)      Bus.Last[name] = os.clock() of last emit

	Events (payloads)
	  Boot ()                 helmet sealed, optics starting       Shutdown ()      optics powering down
	  Damage (dir: Vector2)   screen-space direction of the hit    ShieldBreak ()   ShieldLow ()
	  PulseScan ()            Dash ()                              Jump ()          Fire ()
	  Reload (phase: "Start"|"Done")    WeaponSwitch (name)        Lock (on: boolean)
	  AbilityReady (name)
]]
local Bus = { Last = {} }
local handlers: { [string]: { (...any) -> () } } = {}

function Bus.On(name: string, fn: (...any) -> ()): () -> ()
	local list = handlers[name]
	if not list then
		list = {}
		handlers[name] = list
	end
	table.insert(list, fn)
	return function()
		local i = table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

function Bus.Emit(name: string, ...: any)
	Bus.Last[name] = os.clock()
	local list = handlers[name]
	if not list then
		return
	end
	for _, fn in table.clone(list) do
		task.spawn(fn, ...)
	end
end

return Bus
