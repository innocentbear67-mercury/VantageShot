--[[
	VANTAGE — MatchLedger (server, 2026-11-18)
	What a player earned in the CURRENT match, for the results screen and the scoreboard.
	It never grants anything: the real currencies stay in Requisition (REQ), Ordnance (ORD) and
	Progression (XP), which call Ledger.Add with the amount they actually credited (after boosts).
	Replicated player attributes (server-set): MatchStats_REQ, MatchStats_ORD, MatchStats_XP,
	MatchStats_Damage. MatchStatsServer zeroes them with the other MatchStats_* at a new match.
	Counts only while the player is in the running match (MatchStatus "Match") and the match is
	Live or Ended (match-end bonuses are paid at the start of Ended).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ledger = {}
Ledger.Keys = { "REQ", "ORD", "XP", "Damage" }

local M: Instance? = nil
local function match(): Instance?
	if not M then
		M = ReplicatedStorage:FindFirstChild("Vantage") and ReplicatedStorage.Vantage:FindFirstChild("Match")
	end
	return M
end

function Ledger.Counting(p: Player): boolean
	local m = match()
	if not (m and p and p.Parent) then
		return false
	end
	local ph = m:GetAttribute("Phase")
	return p:GetAttribute("MatchStatus") == "Match" and p:GetAttribute("MatchId") == m:GetAttribute("MatchId")
		and (ph == "Live" or ph == "Ended")
end

function Ledger.Add(p: Player, key: string, amount: number)
	amount = tonumber(amount) or 0
	if amount <= 0 or not Ledger.Counting(p) then
		return
	end
	local attr = "MatchStats_" .. key
	local v = (tonumber(p:GetAttribute(attr)) or 0) + amount
	if key == "Damage" then
		v = math.floor(v * 10 + 0.5) / 10
	else
		v = math.floor(v + 0.5)
	end
	p:SetAttribute(attr, v)
end

return Ledger
