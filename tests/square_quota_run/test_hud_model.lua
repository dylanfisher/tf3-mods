-- quota_hud_model: the pure view model behind the HUD plugin (PLAN §6 Phase 3).
-- The recipe renders nothing exactly when build() returns nil.

-- v2: fixed rule/boss data so these tests do not depend on the shipped tables (quota_rules.tl /
-- quota_bosses.tl are data-only; the model only reads byId[id].name / .description).
local function dataModule(list)
	local byId = {}
	for _, e in ipairs(list) do byId[e.id] = e end
	return { list = list, byId = byId, get = function(id) return byId[id] end }
end
stub_module("/quota/quota_rules.tl", dataModule({
	{ id = "freight_only", name = "Freight Only", description = "Cargo counts triple, passengers not at all." },
	{ id = "local_hero", name = "Local Hero", description = "Deliveries into one town count x4.", target = "town" },
	{ id = "specialist", name = "Specialist", description = "One cargo type counts x10.", target = "cargoType" },
}))
stub_module("/quota/quota_bosses.tl", dataModule({
	{ id = "inspector", name = "The Inspector", description = "All vehicles run at 75% top speed.", rule = "freight_only" },
	{ id = "recession", name = "Recession", description = "Ticket income x0.6." },
}))

local config = ug_require "/quota/quota_config.tl"
local cards = ug_require "/quota/quota_cards.tl"
local logic = ug_require("/quota/quota_logic.tl").new(config, cards)
local model = ug_require "square_quota_run::/quota/gui/quota_hud_model.tl"

local MD = 1000 -- month duration in game-time units

local function running(t)
	local s = logic.activate(nil, { gameTime = t or 0, seed = 42, monthDuration = MD, statsTotal = 0 })
	return s
end

local function choosing()
	local s = running(0)
	s.progress = s.quota -- pass round 1
	s = logic.tick(s, { gameTime = s.roundEndTime, balance = 1000 })
	return s
end

-- Every test below the DEBUG section runs with DEBUG = false: that is the release behaviour, and
-- it must be unchanged by the dev panel (no "inert"/"sandbox" views, no debug fields).
before_each(function()
	config.DEBUG = false
end)

-- nil for every non-active state -----------------------------------------

test("nil state renders nothing", function()
	eq(model.build(nil, 0), nil)
end)

test("empty state (fresh script, {}) renders nothing", function()
	eq(model.build({}, 0), nil)
end)

test("active = false / missing renders nothing even with fields set", function()
	local s = running(0)
	s.active = nil
	eq(model.build(s, 0), nil)
	s.active = false
	eq(model.build(s, 0), nil)
end)

test("sandbox renders nothing", function()
	local s = running(0)
	s.phase = "sandbox"
	eq(model.build(s, 0), nil)
end)

test("unknown or missing phase renders nothing", function()
	local s = running(0)
	s.phase = nil
	eq(model.build(s, 0), nil)
	s.phase = "bogus"
	eq(model.build(s, 0), nil)
end)

-- running -----------------------------------------------------------------

test("running: round, months left (ceil), progress/quota, fraction", function()
	local s = running(0)
	s.progress = 625
	local v = model.build(s, 0)
	eq(v.phase, "running")
	eq(v.round, 1)
	eq(v.quota, 2500)
	eq(v.progress, 625)
	near(v.fraction, 0.25)
	eq(v.monthsLeft, config.FIRST_ROUND_MONTHS)
	eq(v.provisional, false)
	eq(v.redWarning, false)
	eq(v.offer, {})
	eq(v.picked, {})
	eq(v.endReason, nil)
	eq(v.totalTransported, nil)
	-- 0.1 month in: still 36 (ceil); just past the deadline: 0, never negative
	eq(model.build(s, MD // 10).monthsLeft, config.FIRST_ROUND_MONTHS)
	eq(model.build(s, s.roundEndTime + 5 * MD).monthsLeft, 0)
end)

test("fraction is clamped to [0, 1] and safe with quota 0", function()
	local s = running(0)
	s.progress = 99999
	near(model.build(s, 0).fraction, 1.0)
	s.quota = 0
	near(model.build(s, 0).fraction, 0.0)
end)

test("months left unknown without gameTime or monthDuration", function()
	local s = running(0)
	eq(model.build(s, nil).monthsLeft, nil)
	s.monthDuration = 0
	eq(model.build(s, 0).monthsLeft, nil)
end)

test("float fields from a save round trip come back as integers", function()
	local s = running(0)
	s.progress = 12.0
	s.quota = 2500.0
	s.round = 1.0
	local v = model.build(s, 0)
	eq(math.type(v.progress), "integer")
	eq(math.type(v.quota), "integer")
	eq(math.type(v.round), "integer")
end)

test("red-month warning while in play", function()
	local s = running(0)
	s.redMonths = 2
	local v = model.build(s, 0)
	eq(v.redWarning, true)
	eq(v.redMonths, 2)
	eq(v.bankruptMonths, config.BANKRUPT_MONTHS)
end)

test("picked card ids become names (unknown id falls back to the id)", function()
	local s = running(0)
	s.picked = { "venture", "nope" }
	eq(model.build(s, 0).picked, { "Venture Capital", "nope" })
end)

-- choosing ----------------------------------------------------------------

test("choosing: provisional quota and the offer with index/name/description", function()
	local s = choosing()
	eq(s.phase, "choosing")
	local v = model.build(s, s.roundStartTime)
	eq(v.phase, "choosing")
	eq(v.provisional, true)
	eq(v.round, 2)
	eq(v.roundsCleared, 1)
	eq(#v.offer, 3)
	for i, c in ipairs(v.offer) do
		eq(c.index, i)
		eq(c.id, s.offer[i])
		eq(c.name, cards.get(s.offer[i]).name)
		eq(c.description, cards.get(s.offer[i]).description)
	end
end)

test("view is a fresh table each call (deepEquals-friendly, not aliasing state)", function()
	local s = choosing()
	local a = model.build(s, s.roundStartTime)
	local b = model.build(s, s.roundStartTime)
	eq(a, b)
	ok(a ~= b)
	ok(a.offer ~= b.offer)
	ok(a.picked ~= s.picked)
end)

-- ended -------------------------------------------------------------------

test("ended: reason, rounds cleared, total moved; no offer, no red warning", function()
	local s = running(0)
	s.progress = 10
	s.redMonths = 3
	s = logic.tick(s, { gameTime = s.roundEndTime, balance = 1000 })
	eq(s.phase, "ended")
	local v = model.build(s, s.roundEndTime)
	eq(v.phase, "ended")
	eq(v.endReason, "quota")
	eq(v.roundsCleared, 0)
	eq(v.totalTransported, s.totalTransported)
	eq(v.offer, {})
	eq(v.redWarning, false)
end)

test("ended by bankruptcy carries the reason", function()
	local s = running(0)
	s.phase = "ended"
	s.endReason = "bankrupt"
	s.totalTransported = 1234
	local v = model.build(s, 0)
	eq(v.endReason, "bankrupt")
	eq(v.totalTransported, 1234)
end)

test("continueSandbox hides the HUD", function()
	local s = running(0)
	s.phase = "ended"
	s.endReason = "quota"
	s = logic.continueSandbox(s, {})
	eq(s.phase, "sandbox")
	eq(model.build(s, 0), nil)
end)

test("release views carry no dev fields (DEBUG = false)", function()
	for _, s in ipairs({ running(0), choosing() }) do
		local v = model.build(s, 0)
		eq(v.debug, nil)
		eq(v.fxSummary, nil)
	end
end)

-- DEBUG = true: dev panel views ------------------------------------------------

test("DEBUG: nil / {} / active=nil state gives an 'inert' dev view", function()
	config.DEBUG = true
	for _, s in ipairs({ false, true }) do
		local v = model.build(s and {} or nil, 0)
		eq(v.phase, "inert")
		eq(v.debug, true)
		eq(v.offer, {})
		eq(v.picked, {})
		eq(v.fxSummary, "no effects")
	end
	local s = running(0)
	s.active = nil
	eq(model.build(s, 0).phase, "inert")
end)

test("DEBUG: active == false (mission/tutorial turned it off) still renders nothing", function()
	config.DEBUG = true
	eq(model.build({ version = 1, active = false }, 0), nil)
end)

test("DEBUG: sandbox gives a 'sandbox' dev view; unknown phase still nil", function()
	config.DEBUG = true
	local s = running(0)
	s.phase = "sandbox"
	s.picked = { "venture" }
	local v = model.build(s, 0)
	eq(v.phase, "sandbox")
	eq(v.debug, true)
	eq(v.picked, { "Venture Capital" })
	s.phase = "bogus"
	eq(model.build(s, 0), nil)
end)

test("DEBUG: in-play views add debug + fxSummary, other fields as in release", function()
	local s = running(0)
	s.progress = 100
	config.DEBUG = false
	local release = model.build(s, 0)
	config.DEBUG = true
	local v = model.build(s, 0)
	eq(v.debug, true)
	eq(v.fxSummary, "no effects")
	v.debug, v.fxSummary = nil, nil
	eq(v, release)
end)

test("DEBUG: fxSummary lists vehicle mods, vehicles touched, industries", function()
	config.DEBUG = true
	local s = running(0)
	s.fx.vehicleMods = { TopSpeed = 1.15, Comfort = 1.3 }
	s.fx.vehicleApplied = { [10] = 1, [11] = 1 }
	s.fx.industryMods = { [5] = 1.5 }
	eq(model.build(s, 0).fxSummary, "veh Comfort=1.30,TopSpeed=1.15 x2 | ind 1")
end)

-- v2: rule / boss / next boss names (PLAN §9.3, §9.4) ------------------------------
-- Hand-built states (no logic): the model must cope with any v2 state shape.

local V2_FIELDS = { "ruleName", "ruleDescription", "bossName", "bossDescription", "nextBossName", "nextBossDescription",
	"ruleTarget", "ruleTargetKind", "ruleTargetName" }

local function v2state(phase)
	return {
		version = 2, active = true, phase = phase or "running", round = 3, roundsCleared = 2,
		roundStartTime = 0, roundEndTime = 12 * MD, monthDuration = MD,
		quota = 1000, progress = 250, redMonths = 0, picked = {}, offer = {},
	}
end

test("v2: rule, boss and next boss ids become names + descriptions", function()
	local s = v2state()
	s.rule, s.boss, s.nextBoss = "freight_only", "inspector", "recession"
	local v = model.build(s, 0)
	eq(v.ruleName, "Freight Only")
	eq(v.ruleDescription, "Cargo counts triple, passengers not at all.")
	eq(v.bossName, "The Inspector")
	eq(v.bossDescription, "All vehicles run at 75% top speed.")
	eq(v.nextBossName, "Recession")
	eq(v.nextBossDescription, "Ticket income x0.6.")
end)

test("v2: only nextBoss set (the round before a boss round) shows just Next", function()
	local s = v2state()
	s.nextBoss = "inspector"
	local v = model.build(s, 0)
	eq(v.nextBossName, "The Inspector")
	eq(v.bossName, nil)
	eq(v.ruleName, nil)
end)

test("v2: choosing shows the rule/boss of the round that just started", function()
	local s = v2state("choosing")
	s.rule, s.boss = "freight_only", "inspector"
	local v = model.build(s, 0)
	eq(v.phase, "choosing")
	eq(v.bossName, "The Inspector")
	eq(v.ruleName, "Freight Only")
end)

test("v2: unknown or non-string ids give nil fields, never an error", function()
	local s = v2state()
	s.rule, s.boss, s.nextBoss = "no_such_rule", "no_such_boss", 42
	local v = model.build(s, 0)
	for _, k in ipairs(V2_FIELDS) do eq(v[k], nil, k) end
	s.rule, s.boss, s.nextBoss = "", {}, false
	v = model.build(s, 0)
	for _, k in ipairs(V2_FIELDS) do eq(v[k], nil, k) end
end)

test("v2: ended view carries no rule/boss fields", function()
	local s = v2state("ended")
	s.endReason = "quota"
	s.rule, s.boss, s.nextBoss = "freight_only", "inspector", "recession"
	local v = model.build(s, 0)
	for _, k in ipairs(V2_FIELDS) do eq(v[k], nil, k) end
end)

test("v2: a v1-shaped state (DEBUG = false) has all new fields nil and the v1 key set", function()
	local s = v2state()
	s.version = 1
	local v = model.build(s, 0)
	for _, k in ipairs(V2_FIELDS) do eq(v[k], nil, k) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys)
	eq(keys, { "bankruptMonths", "fraction", "monthsLeft", "offer", "phase", "picked", "progress",
		"provisional", "quota", "redMonths", "redWarning", "round", "roundsCleared" })
end)

test("v2: DEBUG dev-only views (inert / sandbox) carry no rule/boss fields", function()
	config.DEBUG = true
	local s = v2state("sandbox")
	s.rule, s.boss, s.nextBoss = "freight_only", "inspector", "recession"
	local v = model.build(s, 0)
	eq(v.phase, "sandbox")
	for _, k in ipairs(V2_FIELDS) do eq(v[k], nil, k) end
end)

-- v2.1 addendum: rule targets ---------------------------------------------------------------
-- The model copies the target id + kind (pure); quota_hud.script.tl resolves the name with
-- gui/quota_target_names.tl, tested below against a fake api.

test("v2.1: local_hero / specialist expose ruleTarget + ruleTargetKind (floored), never a name", function()
	local s = v2state()
	s.rule, s.ruleTarget = "local_hero", 12
	local v = model.build(s, 0)
	eq(v.ruleName, "Local Hero")
	eq(v.ruleTarget, 12)
	eq(v.ruleTargetKind, "town")
	eq(v.ruleTargetName, nil, "the model never resolves names")
	s.rule, s.ruleTarget = "specialist", 4.0 -- float after save/load
	v = model.build(s, 0)
	eq(v.ruleTarget, 4)
	eq(math.type(v.ruleTarget), "integer")
	eq(v.ruleTargetKind, "cargoType")
end)

test("v2.1: a boss round's targeted rule exposes its target; choosing too", function()
	local s = v2state("choosing")
	s.boss, s.rule, s.ruleTarget = "inspector", "local_hero", 7
	local v = model.build(s, 0)
	eq(v.bossName, "The Inspector")
	eq(v.ruleTarget, 7)
	eq(v.ruleTargetKind, "town")
end)

test("v2.1: no target for untargeted / unknown rules, a missing or non-number target, or ended", function()
	local s = v2state()
	s.rule, s.ruleTarget = "freight_only", 7
	local v = model.build(s, 0)
	eq(v.ruleTarget, nil)
	eq(v.ruleTargetKind, nil)
	s.rule = "no_such_rule"
	v = model.build(s, 0)
	eq(v.ruleTarget, nil)
	s.rule, s.ruleTarget = "local_hero", nil
	v = model.build(s, 0)
	eq(v.ruleName, "Local Hero")
	eq(v.ruleTarget, nil)
	eq(v.ruleTargetKind, nil)
	s.ruleTarget = "7"
	eq(model.build(s, 0).ruleTarget, nil)
	s.ruleTarget = 7
	s.phase, s.endReason = "ended", "quota"
	v = model.build(s, 0)
	eq(v.ruleTarget, nil)
	eq(v.ruleTargetKind, nil)
end)

-- gui/quota_target_names.tl (GUI thread lookups) with a fake api:
-- towns 7 ("Springfield") and 8 (empty name) exist; cargo type 3 is Coal; ids >= 50 raise.
local TOWNS = { [7] = "Springfield", [8] = "" }
local CARGO = { [3] = { name = "Coal" }, [5] = {} }
local calls = {}
set_global("api", {
	engine = {
		entityExists = function(e) calls[#calls + 1] = "exists"; return TOWNS[e] ~= nil end,
		util = { getEntityName = function(e)
			assert(math.type(e) == "integer", "entity must be an integer")
			calls[#calls + 1] = "name"
			return TOWNS[e]
		end },
	},
	res = { cargoTypeRep = { get = function(id)
		calls[#calls + 1] = "cargo"
		if id >= 50 then error("invalid cargo type id " .. id) end
		return CARGO[id]
	end } },
})
local names = ug_require "/quota/gui/quota_target_names.tl"

test("v2.1 target names: town entity and cargo type id resolve to display names", function()
	calls = {}
	eq(names.resolve("town", 7), "Springfield")
	eq(names.resolve("town", 7.0), "Springfield", "float id after save/load")
	eq(names.resolve("cargoType", 3), "Coal")
	eq(calls, { "exists", "name", "exists", "name", "cargo" }, "one lookup per call (cheap enough for the 0.5 s poll)")
end)

test("v2.1 target names: nil-safe for unknown kind, bad id, missing entity, empty name, engine error", function()
	calls = {}
	eq(names.resolve(nil, 7), nil)
	eq(names.resolve("industry", 7), nil)
	eq(names.resolve("town", nil), nil)
	eq(names.resolve("town", "7"), nil)
	eq(calls, {}, "no engine call without a valid kind and number id")
	eq(names.resolve("town", 99), nil, "deleted town")
	eq(calls, { "exists" }, "getEntityName is not called for a missing entity")
	eq(names.resolve("town", 8), nil, "empty name")
	eq(names.resolve("cargoType", 4), nil, "nil resource")
	eq(names.resolve("cargoType", 5), nil, "resource without a name")
	eq(names.resolve("cargoType", 77), nil, "the repository raised")
	eq(names.resolve("cargoType", -1), nil, "negative id")
end)
