-- Quota Run scoring rules (PLAN.md §9.3). Data only: no engine calls, no run state.
-- A rule is interpreted by logic.weight (formula on QuotaRunRule in quota_types.d.tl). The
-- logic multiplies the rule's parts with the config kind weight (CARGO_WEIGHT /
-- PASSENGER_WEIGHT), so a later retune of those weights keeps working under every rule.
-- name/description are plain English; the GUI wraps them in _().
-- Order matters: random-rule draws index into `list`, so append new rules at the end.
--
-- quotaMult calibration (placeholders until the v2 playtest logs real fact mixes).
-- Principle: a rule is roughly NEUTRAL for a reference MVP network, i.e. quotaMult is about the
-- expected weight per delivered unit of that network, so a rule round is as hard as a normal round
-- if you change nothing, easier if you build for the rule, and much harder for a one-trick
-- network (e.g. pure bus spam under freight_only scores 0). Reference network (PLAN §9.1:
-- "passenger trips far outnumber cargo"):
--   c = 0.10   cargo share of units (1 cargo unit per 9 passenger trips)
--   T = 0.25   share of all units that go to the drawn town (target draws are weighted by
--              last round's units, so the target is usually one of the bigger destinations)
--   S = 0.40   share of cargo units that are the drawn cargo type (same weighted draw)
--   rail 0.4 / road 0.5 / other 0.1   carrier mix of cargo
--   X = 0.15   share of units with known, different source and destination towns
-- Weights are integers on purpose: logic.delivered rounds the weight sum once per call, and the
-- frozen v2 state has no field for a fractional carry, so fractional rule weights would be biased
-- when the adapter sends one fact per call. Specialist therefore uses 10 vs 1 (the same 10:1
-- ratio as PLAN §9.3's 5 vs 0.5) with a quotaMult twice as large.

local list : {QuotaRunRule} = {
	{
		-- E = 3 * c = 0.30
		id = "freight_only",
		name = "Freight Only",
		description = "Only freight counts, and it counts triple. Passengers count for nothing.",
		quotaMult = 0.3,
		needs = {},
		cargoWeight = 3,
		passengerWeight = 0,
	},
	{
		-- E = 2 * (1 - c) = 1.80
		id = "commuter_rush",
		name = "Commuter Rush",
		description = "Only passengers count, and they count double. Freight counts for nothing.",
		quotaMult = 1.8,
		needs = {},
		cargoWeight = 0,
		passengerWeight = 2,
	},
	{
		-- E = 4 * T = 1.00 (cargo and passengers alike; needs the destination town)
		id = "local_hero",
		name = "Local Hero",
		description = "Only deliveries into one town count, and they count four times. The town is picked from last round's destinations.",
		quotaMult = 1.0,
		needs = { "toTown" },
		target = "town",
		targetWeight = 4,
		otherWeight = 0,
	},
	{
		-- E = c * (10 * S + 1 * (1 - S)) = 0.1 * 4.6 = 0.46 -> 0.45. Cargo only: the rule is about
		-- one cargo type, and passengers at "other" weight would keep bus spam the best strategy.
		id = "specialist",
		name = "Specialist",
		description = "One cargo type counts ten times as much as other freight. Passengers count for nothing. The type is picked from last round's cargo.",
		quotaMult = 0.45,
		needs = { "cargoType" },
		cargoOnly = true,
		target = "cargoType",
		targetWeight = 10,
		otherWeight = 1,
	},
	{
		-- E = c * (2 * 0.4 + 0 * 0.5 + 1 * 0.1) = 0.09 -> 0.1. Cargo only (no carrier fact for
		-- passengers). A cargo fact without a carrier (unresolved) counts 1.
		id = "rail_day",
		name = "Iron Horse",
		description = "Only freight counts: by rail it counts double, by road it counts for nothing, anything else counts normally.",
		quotaMult = 0.1,
		needs = { "carrier" },
		cargoOnly = true,
		carrierWeights = { RAIL = 2, ROAD = 0 },
	},
	{
		-- E = 3 * X + 1 * (1 - X) = 1.30. otherWeight 1: local trips still count normally, so the
		-- rule rewards linking towns without wiping out an existing network.
		id = "long_haul",
		name = "Long Haul",
		description = "Deliveries from one town to a different town count triple. Everything else counts normally.",
		quotaMult = 1.3,
		needs = { "fromTown", "toTown" },
		crossTownWeight = 3,
		otherWeight = 1,
	},
}

-- Lookup table built once from constant data (rebuildable cache, not run state).
local byId : {string : QuotaRunRule} = {}
for _, rule in ipairs(list) do
	byId[rule.id] = rule
end

local rules : QuotaRunRules = {
	list = list,
	byId = byId,
	get = function(id : string) : QuotaRunRule
		if id == nil then return nil end
		return byId[id]
	end,
}

return rules
