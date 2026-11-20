--[[
	VANTAGE — GaitFeed (client, shared state)
	The local player's running gait, written every frame by the gun Viewmodel so the gun bob, the
	camera bob (CameraEffects) and the footstep sounds (Footsteps) all agree on the same footfalls.
	  Phase       0..2pi   footfalls at 0 and pi (the LOW point of the bob)
	  Weight      0..1     how much of the gait is active (ground speed)
	  Sprint      >= 1     extra swing while sprinting
	  At          os.clock() of the last write (readers fall back to their own timing when stale)
	  StepCount / StepAt / StepSpeed / StepFoot   last footfall event
]]
return {}
