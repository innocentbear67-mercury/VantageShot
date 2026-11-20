--[[
	VANTAGE — GrenadeFeed: shared state between GrenadeClient (starts a throw) and Viewmodel
	(animates the left hand). Client only.
		Start    os.clock() of the current throw, or nil
		HoldAt   Studio tuning: freeze the throw animation at this many seconds (nil = play)
	Timeline (seconds from Start) lives in Viewmodel's THROW table; Release is when the grenade
	leaves the hand (GrenadeClient sends the throw to the server then).
]]
return {
	Start = nil :: number?,
	HoldAt = nil :: number?,
	Release = 0.38,
	Length = 0.78,
}
