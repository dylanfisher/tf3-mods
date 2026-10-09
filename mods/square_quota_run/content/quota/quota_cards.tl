-- Quota Run cards (PLAN.md §3.2). Data only: no engine calls, no run state.
-- "Round" always means the round that just started when the card is picked.
-- name/description are plain English; the GUI wraps them in _().
-- Order matters: the offer draw indexes into `list`, so append new cards at the end.

local list : {QuotaRunCard} = {
	{
		id = "venture",
		name = "Venture Capital",
		description = "Receive $4M x round.",
		effects = { { kind = "cash", amount = 4000000 } },
	},
	{
		id = "hostile_loan",
		name = "Hostile Loan",
		description = "Receive $12M x round, but this round's quota is 30% higher.",
		effects = {
			{ kind = "cash", amount = 12000000 },
			{ kind = "quotaMultRound", mult = 1.3 },
		},
	},
	{
		id = "express",
		name = "Express Timetables",
		description = "All your vehicles run 15% faster for the rest of the run.",
		effects = { { kind = "vehicleMod", mods = { TopSpeed = 1.15 } } },
	},
	{
		id = "overdrive",
		name = "Overdrive",
		description = "All your vehicles run 30% faster, but pollute twice as much and are 50% louder.",
		effects = { { kind = "vehicleMod", mods = { TopSpeed = 1.30, Pollution = 2.0, Noise = 1.5 } } },
	},
	{
		id = "luxury",
		name = "Luxury Fleet",
		description = "All your vehicles are 30% more comfortable for the rest of the run.",
		effects = { { kind = "vehicleMod", mods = { Comfort = 1.30 } } },
	},
	{
		id = "boomtown",
		name = "Boomtown",
		description = "3 random industries produce 50% more for the rest of the run.",
		effects = { { kind = "industryProd", mult = 1.5, count = 3 } },
	},
	{
		id = "industrial_policy",
		name = "Industrial Policy",
		description = "All industries produce 15% more for the rest of the run. Costs $3M x round.",
		effects = {
			{ kind = "industryProd", mult = 1.15 },
			{ kind = "cash", amount = -3000000 },
		},
	},
	{
		id = "lean_year",
		name = "Lean Year",
		description = "This round's quota is 20% lower.",
		effects = { { kind = "quotaMultRound", mult = 0.8 } },
	},
	{
		id = "extension",
		name = "Deadline Extension",
		description = "This round lasts 6 months longer.",
		effects = { { kind = "roundMonths", months = 6 } },
	},
	{
		id = "crunch",
		name = "Crunch Time",
		description = "This round is 6 months shorter, but all future round rewards are 50% higher.",
		effects = {
			{ kind = "roundMonths", months = -6 },
			{ kind = "rewardMult", mult = 1.5 },
		},
	},
	{
		id = "austerity",
		name = "Austerity",
		description = "Pay $5M x round now; this and all future quotas are 15% lower.",
		effects = {
			{ kind = "cash", amount = -5000000 },
			{ kind = "quotaMultAll", mult = 0.85 },
		},
	},
	{
		id = "gamble",
		name = "Double or Nothing",
		description = "This round's quota is 50% higher; all future round rewards are doubled.",
		effects = {
			{ kind = "quotaMultRound", mult = 1.5 },
			{ kind = "rewardMult", mult = 2.0 },
		},
	},
	-- v2.1 round-modifier cards (PLAN §9.5): they set this round's scoring rule (quota_rules.tl).
	-- The offer never shows them in a boss round with a rule (the boss rule wins), nor when the
	-- rule's target can't be drawn (no matching deliveries last round), nor without rules data.
	{
		id = "freight_contract",
		name = "Freight Contract",
		description = "This round only freight counts (triple; passengers count for nothing). This round's reward is 50% higher.",
		effects = {
			{ kind = "rule", rule = "freight_only" },
			{ kind = "rewardMultRound", mult = 1.5 },
		},
	},
	{
		id = "rush_hour",
		name = "Rush Hour",
		description = "This round only passengers count (double; freight counts for nothing). This round's reward is 30% higher.",
		effects = {
			{ kind = "rule", rule = "commuter_rush" },
			{ kind = "rewardMultRound", mult = 1.3 },
		},
	},
	{
		id = "local_hero_card",
		name = "Hometown Hero",
		description = "This round only deliveries into one of last round's destination towns count (four times). This round's quota is 20% lower.",
		effects = {
			{ kind = "rule", rule = "local_hero" },
			{ kind = "quotaMultRound", mult = 0.8 },
		},
	},
}

-- Lookup table built once from constant data (rebuildable cache, not run state).
local byId : {string : QuotaRunCard} = {}
for _, card in ipairs(list) do
	byId[card.id] = card
end

local cards : QuotaRunCards = {
	list = list,
	byId = byId,
	get = function(id : string) : QuotaRunCard
		return byId[id]
	end,
}

return cards
