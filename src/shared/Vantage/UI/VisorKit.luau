-- VANTAGE — visor texture kit (generated PNGs, imported to the owner's inventory 2026-11-09).
-- White sprites are tinted in-game via ImageColor3. Frame/Rim/Threat are full-screen quadrants.
local function id(n) return "rbxassetid://" .. n end
local K = {
	FrameLTop = id(86102939087334), FrameLBot = id(73868736159337), FrameRTop = id(99097171356357), FrameRBot = id(124212682868860),
	RimLTop = id(121233949614162), RimLBot = id(79026221272545), RimRTop = id(102490062802500), RimRBot = id(110573427058253),
	ThreatLTop = id(93503138442216), ThreatLBot = id(97495305181148), ThreatRTop = id(70603788584573), ThreatRBot = id(103625315519660),
	ArcShield = id(86657094148642), ArcHealth = id(100570877781710), ArcTrack = id(137648969312238), ArcAmmoGlow = id(135352895839561),
	Glow = id(122724098620067), GlowLine = id(128802258528153),
	ReticleSeg = id(98016613397870), TrackSeg = id(120263381489520), Ring = id(80799966088748), RingHalf = id(121319850094310),
	Bracket = id(117131553479865), Diamond = id(109747718056659), HexNode = id(137145278290442), Chevron = id(84847304994229),
	IconDash = id(76922474383384), IconJump = id(91880503851509), IconPulse = id(127810699916667),
	EyeMask = id(129859681272189), EyeGlow = id(79729244479961), VisorPlate = id(123455249123813),
	RadarRings = id(103133620674097), RadarSweep = id(101761537656253),
	-- Kit4 (living visor): shell without baked honeycomb, one hex cell, new ability glyphs, thicker strokes
	ShellLTop = id(113397487864426), ShellRTop = id(90667977255475), ShellLBot = id(82205828389924), ShellRBot = id(77990857180268),
	HexCell = id(136242431632482),
	IconDash2 = id(101423008501876), IconJump2 = id(117473008733500), IconScan2 = id(97595691279216),
	ReticleSeg4 = id(136988170730125), TrackSeg4 = id(133919195487300), Ring4 = id(94326406848824),
	Bracket4 = id(91140428718812), Diamond4 = id(103709050512199),
	-- HoloKit (v6 holographic HUD): reference frame, energy veins, weapon wireframe sheets (8 frames, 2x4 of 512x256)
	HoloFrameLTop = id(75799817198419), HoloFrameRTop = id(95364625887819), HoloFrameLBot = id(127100441646870), HoloFrameRBot = id(129872057764710),
	HoloVeinsLTop = id(116259212322323), HoloVeinsRTop = id(78948321557057), HoloVeinsLBot = id(70645647813864), HoloVeinsRBot = id(114967451711814),
	Wire_VX01_Vanguard = id(122930831099278), Wire_BR07_Sentinel = id(83852456712740), Wire_SR88_Longshot = id(109918277257903),
	Wire_SG12_Breacher = id(111916539548049), Wire_PX9_Spectre = id(112652597376485), Wire_ER04_Arc = id(122423022817093),
	Wire_Combat_Knife = id(101400529592938),
}
-- the thicker Kit4 strokes replace the thin originals everywhere they are used
K.ReticleSeg, K.TrackSeg, K.Ring, K.Bracket, K.Diamond = K.ReticleSeg4, K.TrackSeg4, K.Ring4, K.Bracket4, K.Diamond4
return K
