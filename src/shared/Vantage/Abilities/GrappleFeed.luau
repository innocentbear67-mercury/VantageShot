--[[
	VANTAGE — GrappleFeed (client, shared table)
	Your own grapple's timeline, written by VantageAbilityClient and read every frame by the
	first-person Viewmodel, which reaches the left arm out at the hook (the launcher is on the left
	gauntlet, so GrappleFX's cable leaves the extended arm automatically).

	  FiredAt   os.clock() of the shot (0 = no grapple yet)
	  Target    world point the hook flies to / bit into (fixed anchors)
	  Track     function() -> point?  for a moving anchor (the dropship); overrides Target
	  BiteAt    os.clock() the hook bit (nil before; the arm jolts with the cable going taut)
	  EndAt     os.clock() the arm starts to come back (nil = held out). A miss sets it at
	            fire time (hook out and back); letting go / arriving / dying sets it then.

	Studio test hook: set HoldAt to a number of seconds to freeze the pose at that time into the
	grapple (nil = live).
]]
return {
	FiredAt = 0,
	Target = nil :: Vector3?,
	Track = nil :: (() -> Vector3?)?,
	BiteAt = nil :: number?,
	EndAt = nil :: number?,
	HoldAt = nil :: number?,
}
