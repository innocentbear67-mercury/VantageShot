--[[
	VANTAGE — WeaponServer bootstrap
	Child modules: WeaponService (state/remotes), HitValidation (lag-compensated hitscan),
	DamageService (damage, friendly fire, kill credit).
]]
require(script.WeaponService).Start()
