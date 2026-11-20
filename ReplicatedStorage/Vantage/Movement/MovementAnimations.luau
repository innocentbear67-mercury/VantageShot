--[[
	VANTAGE — MovementAnimations
	Animation asset IDs used by the movement AnimationController.

	⚠ PLACEHOLDERS ⚠
	Idle / Run / Jump / Fall currently use Roblox's stock character animations
	(owned by Roblox, so they load in any experience). Replace them with VANTAGE's own.

	Land / Crouch / CrouchWalk / Slide are EMPTY (""). While empty, the system falls
	back to a procedural joint pose (PoseController) so crouching and sliding are still
	visible to other players. Upload proper animations and paste the IDs here:
		• Crouch      — looped, Priority = Idle       (crouched idle)
		• CrouchWalk  — looped, Priority = Movement   (crouched locomotion, authored at CrouchSpeed)
		• Slide       — looped/held pose, Priority = Action
		• Land        — one-shot ~0.2s, Priority = Action
	When an ID is filled in, the procedural fallback for that state is disabled automatically.
]]

return {
	R15 = {
		Idle = "rbxassetid://507766388",       -- PLACEHOLDER (Roblox stock idle)
		Run = "rbxassetid://913376220",        -- PLACEHOLDER (Roblox stock run)
		Jump = "rbxassetid://507765000",       -- PLACEHOLDER (Roblox stock jump)
		Fall = "rbxassetid://507767968",       -- PLACEHOLDER (Roblox stock fall)
		Land = "",                             -- TODO: insert landing animation
		Crouch = "",                           -- TODO: insert crouch idle animation
		CrouchWalk = "",                       -- TODO: insert crouch walk animation
		Slide = "",                            -- TODO: insert slide animation
	},
	R6 = {
		Idle = "rbxassetid://180435571",
		Run = "rbxassetid://180426354",
		Jump = "rbxassetid://125750702",
		Fall = "rbxassetid://180436148",
		Land = "",
		Crouch = "",
		CrouchWalk = "",
		Slide = "",
	},
}
