--[[
	VANTAGE — StatusService (2026-11-20): status effects for Signatures, written as character attributes so
	every client sees them, with immunity windows.
	  Freeze(model, secs)      can't move (root anchored on the server), shoot or cast; 6 s freeze immunity after
	  Slow(model, mult, secs)  uses the PerkSlow / PerkSlowUntil pair MovementController already honours
	  Knock(model, vel, secs)  players: Remotes.Status "Impulse" to their client + a movement-check exemption;
	                           bots: velocity set on the server
	  KnockUp(model, up, immuneSecs)  vertical knock with its own immunity
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Remotes = require(ReplicatedStorage:WaitForChild("Vantage"):WaitForChild("RemotesLib"))
local Remote = Remotes.get("Status") :: RemoteEvent

local Status = {}
local function now() return Workspace:GetServerTimeNow() end
Status.Now = now

local function exempt(p: Player, secs: number)
	local ev = script.Parent:FindFirstChild("ExemptMovement")
	if ev then ev:Fire(p, secs) end
end
Status.Exempt = exempt

function Status.Slow(model: Model, mult: number, secs: number)
	local untilT = now() + secs
	local cur = model:GetAttribute("PerkSlowUntil")
	local curM = model:GetAttribute("PerkSlow")
	if type(cur) == "number" and cur > now() and type(curM) == "number" and curM < mult then mult = curM end
	model:SetAttribute("PerkSlow", mult)
	model:SetAttribute("PerkSlowUntil", math.max(untilT, if type(cur) == "number" then cur else 0))
	if not Players:GetPlayerFromCharacter(model) then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			local base = model:GetAttribute("Status_BaseWalk") or hum.WalkSpeed
			model:SetAttribute("Status_BaseWalk", base)
			hum.WalkSpeed = base * mult
			task.delay(secs, function()
				if model.Parent and (model:GetAttribute("PerkSlowUntil") or 0) <= now() + 0.05 then
					hum.WalkSpeed = model:GetAttribute("Status_BaseWalk") or base
					model:SetAttribute("Status_BaseWalk", nil)
				end
			end)
		end
	end
end

function Status.Freeze(model: Model, secs: number, immunity: number?): boolean
	if (model:GetAttribute("Status_FreezeImmuneUntil") or 0) > now() then return false end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end
	model:SetAttribute("Status_FrozenUntil", now() + secs)
	model:SetAttribute("Status_FreezeImmuneUntil", now() + secs + (immunity or 6))
	local was = root.Anchored
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	local pl = Players:GetPlayerFromCharacter(model)
	if pl then exempt(pl, secs + 0.5) end
	task.delay(secs, function()
		if root.Parent and (model:GetAttribute("Status_FrozenUntil") or 0) <= now() + 0.05 then
			root.Anchored = was
		end
	end)
	return true
end

function Status.Knock(model: Model, vel: Vector3, secs: number?)
	local pl = Players:GetPlayerFromCharacter(model)
	if (model:GetAttribute("Status_FrozenUntil") or 0) > now() then return end
	if pl then
		exempt(pl, secs or 1.2)
		Remote:FireClient(pl, "Impulse", vel)
	else
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not root.Anchored then
			root.AssemblyLinearVelocity = vel
		end
	end
end

function Status.KnockUp(model: Model, up: number, immuneSecs: number): boolean
	if (model:GetAttribute("Status_KnockImmuneUntil") or 0) > now() then return false end
	model:SetAttribute("Status_KnockImmuneUntil", now() + immuneSecs)
	Status.Knock(model, Vector3.new(0, up, 0), 1.5)
	return true
end

return Status
