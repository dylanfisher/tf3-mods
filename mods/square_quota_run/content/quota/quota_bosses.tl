-- Quota Run bosses (PLAN.md §9.4, v2.1 subset of §9.10 step 1). Data only: no engine calls, no
-- run state. v2.1 bosses need no new engine surface: a scoring rule (quota_rules.tl) and/or a
-- temporary vehicle modifier on the existing vehicleMods path. Every BOSS_EVERY-th round is a boss
-- round; the boss is drawn (from rngSeed) when the round before it starts. Clearing a boss round
-- pays BOSS_REWARD_MULT (v2.2 adds charter points).
-- name/description are plain English; the GUI wraps them in _().
-- Order matters: boss draws index into `list`, so append new bosses at the end.
-- quotaMult is nil (= 1) for all of them: the rule or the slowdown is the difficulty, and the
-- rules' own quotaMult already calibrates the quota for what counts.

local list : {QuotaRunBoss} = {
	{
		id = "inspector",
		name = "The Inspector",
		description = "Safety inspectors limit every vehicle to 75% of its top speed for this round.",
		vehicleMods = { TopSpeed = 0.75 },
	},
	{
		id = "cargo_baron",
		name = "The Cargo Baron",
		description = "Only freight counts this round, and it counts triple. Passengers count for nothing.",
		rule = "freight_only",
	},
	{
		id = "transit_commissioner",
		name = "The Transit Commissioner",
		description = "Only passengers count this round, and they count double. Freight counts for nothing.",
		rule = "commuter_rush",
	},
	{
		id = "monopolist",
		name = "The Monopolist",
		description = "One cargo type counts ten times as much as other freight this round. Passengers count for nothing. The type is picked from last round's cargo.",
		rule = "specialist",
	},
	{
		id = "mayor",
		name = "The Mayor",
		description = "Only deliveries into one town count this round, and they count four times. The town is picked from last round's destinations.",
		rule = "local_hero",
	},
}

-- Lookup table built once from constant data (rebuildable cache, not run state).
local byId : {string : QuotaRunBoss} = {}
for _, boss in ipairs(list) do
	byId[boss.id] = boss
end

local bosses : QuotaRunBosses = {
	list = list,
	byId = byId,
	get = function(id : string) : QuotaRunBoss
		if id == nil then return nil end
		return byId[id]
	end,
}

return bosses
