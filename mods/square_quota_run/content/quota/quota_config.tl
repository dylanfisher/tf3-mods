-- Quota Run tunables (PLAN.md §3.1). Constants only: no engine calls, no run state.
local config : QuotaRunConfig = {
	DEBUG = true,
	METRIC = "events",
	CARGO_WEIGHT = 1,
	PASSENGER_WEIGHT = 1,
	BASE_QUOTA = 2500,
	GROWTH = 1.6,
	ROUND_MONTHS = 24,
	FIRST_ROUND_MONTHS = 36,
	MIN_MONTHS_LEFT = 3,
	REWARD_BASE = 2000000,
	REWARD_BONUS_THRESHOLD = 1.5,
	REWARD_BONUS = 0.5,
	BANKRUPT_MONTHS = 6,
	BANKRUPT_WARN_MONTHS = 3,
	VEHICLE_MOD_CAP = 2.0,
	OFFER_SIZE = 3,
	SEED_MIX = 0x51A7E,
	SCAN_INTERVAL_FRACTION = 0.25,
	-- Phase 4: at most this many VehicleModifier/ChangeModifier events per scan call. The base
	-- handler copies its whole per-vehicle state on every event (state:get()/set(),
	-- .cache/game/base/content/vehicle/vehicle_modifier.script.tl:72-120), so N events cost O(N^2);
	-- capped scans continue on the next frame.
	VEHICLE_SENDS_PER_FRAME = 200,
	-- Phase 4: true = old inline 3-card picker / end screen inside the button ridge (may be clipped,
	-- see plans/square_quota_run/GUI_FALLBACK.md); false = compact HUD + button that opens a
	-- centered dialog window.
	GUI_INLINE_PICKER = false,
	-- v2 (PLAN §9.3-9.4)
	-- Every 3rd round is a boss round (3, 6, 9, ...); the boss is announced when the round before
	-- it starts. 0 = no bosses.
	BOSS_EVERY = 3,
	-- v2.1 placeholder for the boss bonus: clearing a boss round pays double (v2.2 adds charter
	-- points, PLAN §9.6, and may drop this back to 1).
	BOSS_REWARD_MULT = 2.0,
	-- PLAN §9.3 (c): random rule on every non-boss round from this round on. Off for v2.1; turn
	-- on (e.g. 4) after the playtest has calibrated the rules' quotaMult.
	RANDOM_RULE_FROM_ROUND = 0,
	-- Resolve cargoType/toTown for every delivery (not only while a rule needs them), so
	-- local_hero / specialist targets can be drawn from last round's tallies.
	TALLY_FACTS = true,
}

return config
