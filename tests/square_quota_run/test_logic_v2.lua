-- quota_logic v2.1 (PLAN §9.3 rules, §9.4 bosses, §9.5 round-modifier cards, §9.8 contract):
-- migrate, weight, delivered with facts + tallies, factsNeeded, boss schedule and vehicle mods,
-- rule targets, rule cards, offer exclusion, boss reward, v2 debug ops, nil rules/bosses = MVP.

local config = ug_require "/quota/quota_config.tl"
local cards = ug_require "/quota/quota_cards.tl"
local rules = ug_require "/quota/quota_rules.tl"
local bosses = ug_require "/quota/quota_bosses.tl"
local Logic = ug_require "/quota/quota_logic.tl"
local logic = Logic.new(config, cards, rules, bosses)
local mvp = Logic.new(config, cards)

local MD = 1000
local FAR = 1000000000

local function activate(seed, lg)
	return ((lg or logic).activate(nil, { gameTime = 0, seed = seed or 42, monthDuration = MD, statsTotal = 0 }))
end

local function find(intents, kind, key)
	for _, it in ipairs(intents) do
		if it.kind == kind and (key == nil or it.key == key) then return it end
	end
end

local function count(intents, kind)
	local n = 0
	for _, it in ipairs(intents) do if it.kind == kind then n = n + 1 end end
	return n
end

local function warned(intents, text)
	for _, it in ipairs(intents) do
		if it.kind == "log" and it.level == "warning" and (text == nil or it.message:find(text, 1, true)) then return true end
	end
	return false
end

local function logged(intents, text)
	for _, it in ipairs(intents) do
		if it.kind == "log" and it.message:find(text, 1, true) then return true end
	end
	return false
end

--- Clear the round in progress at its deadline (progress = quota); returns the tick intents.
--- The state is then choosing with the next round in progress.
local function clearRound(s, lg)
	s.nextMonthTick = FAR
	s.progress = math.max(s.progress, s.quota)
	local _, intents = (lg or logic).tick(s, { gameTime = s.roundEndTime, balance = 1 })
	return intents
end

--- Pick a plain card (cash only) so the round runs without rule changes.
local function pickPlain(s, lg)
	s.offer = { "venture", "express", "lean_year" }
	local _, intents = (lg or logic).pickCard(s, { index = 1, gameTime = s.roundStartTime })
	return intents
end

--- Advance to round n (each round cleared, then a plain pick).
local function toRound(s, n, lg)
	while s.round < n do
		clearRound(s, lg)
		pickPlain(s, lg)
	end
	return s
end

local function fakeBosses(list)
	local byId = {}
	for _, b in ipairs(list) do byId[b.id] = b end
	return { list = list, byId = byId, get = function(id) return byId[id] end }
end

before_each(function()
	config.DEBUG = true
	config.METRIC = "events"
	config.CARGO_WEIGHT = 1
	config.PASSENGER_WEIGHT = 1
	config.BOSS_EVERY = 3
	config.BOSS_REWARD_MULT = 2.0
	config.RANDOM_RULE_FROM_ROUND = 0
	config.TALLY_FACTS = true
end)

-- data -----------------------------------------------------------------------

test("rules: six §9.3 rules, unique ids, sane fields, accurate needs", function()
	local ids = {}
	for _, r in ipairs(rules.list) do
		ok(r.id:match("^[a-z_]+$"), r.id)
		ok(#r.name > 0 and #r.description > 0, r.id)
		ok(r.quotaMult > 0, r.id)
		ok(type(r.needs) == "table", r.id)
		ok(rules.get(r.id) == r and rules.byId[r.id] == r)
		ids[#ids + 1] = r.id
	end
	eq(ids, { "freight_only", "commuter_rush", "local_hero", "specialist", "rail_day", "long_haul" })
	eq(rules.get("freight_only").needs, {})
	eq(rules.get("commuter_rush").needs, {})
	eq(rules.get("local_hero").needs, { "toTown" })
	eq(rules.get("specialist").needs, { "cargoType" })
	eq(rules.get("rail_day").needs, { "carrier" })
	eq(rules.get("long_haul").needs, { "fromTown", "toTown" })
	eq(rules.get(nil), nil)
	eq(rules.get("nope"), nil)
end)

test("bosses: inspector + rule-only bosses whose rules exist", function()
	local seen = {}
	for _, b in ipairs(bosses.list) do
		ok(b.id:match("^[a-z_]+$") and #b.name > 0 and #b.description > 0, b.id)
		ok(b.rule ~= nil or b.vehicleMods ~= nil, b.id)
		if b.rule then ok(rules.get(b.rule), b.id .. " rule") end
		ok(bosses.get(b.id) == b)
		seen[b.id] = b.rule or "vehicleMods"
	end
	eq(seen, { inspector = "vehicleMods", cargo_baron = "freight_only", transit_commissioner = "commuter_rush",
		monopolist = "specialist", mayor = "local_hero" })
	eq(bosses.get("inspector").vehicleMods, { TopSpeed = 0.75 })
end)

test("config: v2.1 defaults (fresh copy of the shipped module)", function()
	reset_modules()
	local fresh = ug_require "/quota/quota_config.tl"
	ok(fresh ~= config)
	eq(fresh.BOSS_EVERY, 3)
	eq(fresh.BOSS_REWARD_MULT, 2.0)
	eq(fresh.RANDOM_RULE_FROM_ROUND, 0)
	eq(fresh.TALLY_FACTS, true)
end)

-- migrate --------------------------------------------------------------------

local function v1State(lg)
	local s = activate(42, lg or mvp)
	s.version = 1
	s.rewardMultRound, s.tally, s.lastTally, s.cardVehicleMods = nil, nil, nil, nil
	s.rule, s.ruleTarget, s.boss, s.nextBoss = nil, nil, nil, nil
	s.fx.vehicleMods = { TopSpeed = 1.15, Comfort = 1.3 }
	s.fx.vehicleModsRev = 2
	return s
end

test("migrate: v1 -> v2 fills defaults, copies card vehicle mods, logs", function()
	local s = v1State()
	local s2, intents = logic.migrate(s)
	ok(s2 == s)
	eq(s.version, 2)
	eq(s.rewardMultRound, 1.0)
	eq(s.tally, { cargoTypes = {}, towns = {} })
	eq(s.lastTally, { cargoTypes = {}, towns = {} })
	eq(s.cardVehicleMods, { TopSpeed = 1.15, Comfort = 1.3 })
	ok(s.cardVehicleMods ~= s.fx.vehicleMods, "a copy, not the fx table")
	eq(s.fx.vehicleModsRev, 2, "fx untouched")
	eq(s.rule, nil)
	eq(s.boss, nil)
	eq(s.nextBoss, nil, "round 2 is no boss round")
	ok(logged(intents, "migrated v1 -> v2"))
	eq(warned(intents), false)
end)

test("migrate: no-op on nil, inactive and v2 states", function()
	local s, i = logic.migrate(nil)
	eq(s, nil); eq(i, {})
	local inactive = { version = 1, active = false }
	s, i = logic.migrate(inactive)
	eq(s, { version = 1, active = false }); eq(i, {})
	local v2 = activate()
	local before = logic.dump(v2)
	s, i = logic.migrate(v2)
	eq(logic.dump(s), before); eq(i, {})
end)

test("migrate: v1 state in round 2 announces the round-3 boss", function()
	local s = v1State()
	s.round = 2
	local _, intents = logic.migrate(s)
	ok(bosses.get(s.nextBoss), tostring(s.nextBoss))
	ok(logged(intents, "next boss (round 3)"))
	-- without bosses: nothing announced
	local m = v1State()
	m.round = 2
	mvp.migrate(m)
	eq(m.nextBoss, nil)
	eq(m.version, 2)
end)

test("entry points tolerate a v1 state that was never migrated", function()
	local s = v1State()
	logic.delivered(s, { units = 2, kind = "cargo", facts = { { kind = "cargo", cargoType = 3, toTown = 9 } } })
	eq(s.progress, 1)
	eq(s.tally.cargoTypes[3], 1)
	clearRound(s)
	eq(s.round, 2)
	eq(s.lastTally.towns[9], 1)
	s.offer = { "express", "venture", "lean_year" }
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	near(s.fx.vehicleMods.TopSpeed, 1.30, 1e-9, "v1 card mods kept and stacked")
	near(s.fx.vehicleMods.Comfort, 1.3, 1e-9)
end)

-- weight -----------------------------------------------------------------------

local function ruled(id, target)
	local s = activate()
	s.rule, s.ruleTarget = id, target
	return s
end

test("weight: no rule = MVP kind weights", function()
	local s = activate()
	eq(logic.weight(s, { kind = "cargo" }), 1)
	eq(logic.weight(s, { kind = "passenger" }), 1)
	eq(logic.weight(s, { kind = "other" }), 1.0)
	eq(logic.weight(s, nil), 0)
	config.CARGO_WEIGHT, config.PASSENGER_WEIGHT = 2, 0.5
	eq(logic.weight(s, { kind = "cargo" }), 2)
	eq(logic.weight(s, { kind = "passenger" }), 0.5)
	-- an unknown rule id behaves like no rule
	s.rule = "nope"
	eq(logic.weight(s, { kind = "cargo" }), 2)
	-- MVP logic ignores rules entirely
	local m = ruled("freight_only")
	eq(mvp.weight(m, { kind = "passenger" }), 0.5)
end)

test("weight: freight_only / commuter_rush (kind parts; config weight multiplies)", function()
	local s = ruled("freight_only")
	eq(logic.weight(s, { kind = "cargo" }), 3)
	eq(logic.weight(s, { kind = "passenger", toTown = 1 }), 0)
	s = ruled("commuter_rush")
	eq(logic.weight(s, { kind = "cargo", cargoType = 1 }), 0)
	eq(logic.weight(s, { kind = "passenger" }), 2)
	config.PASSENGER_WEIGHT = 0.5
	eq(logic.weight(s, { kind = "passenger" }), 1)
end)

test("weight: local_hero (town target, float ids, missing toTown)", function()
	local s = ruled("local_hero", 7)
	eq(logic.weight(s, { kind = "cargo", toTown = 7 }), 4)
	eq(logic.weight(s, { kind = "passenger", toTown = 7 }), 4)
	eq(logic.weight(s, { kind = "passenger", toTown = 7.0 }), 4)
	eq(logic.weight(s, { kind = "cargo", toTown = 8 }), 0)
	eq(logic.weight(s, { kind = "cargo" }), 0)
	s.ruleTarget = nil
	eq(logic.weight(s, { kind = "cargo", toTown = 7 }), 0, "no target: nothing matches")
end)

test("weight: specialist (cargo only, 10 vs 1)", function()
	local s = ruled("specialist", 3)
	eq(logic.weight(s, { kind = "cargo", cargoType = 3 }), 10)
	eq(logic.weight(s, { kind = "cargo", cargoType = 4 }), 1)
	eq(logic.weight(s, { kind = "cargo" }), 1)
	eq(logic.weight(s, { kind = "passenger", toTown = 3 }), 0)
end)

test("weight: rail_day (carrier weights, unresolved carrier counts 1, cargo only)", function()
	local s = ruled("rail_day")
	eq(logic.weight(s, { kind = "cargo", carrier = "RAIL" }), 2)
	eq(logic.weight(s, { kind = "cargo", carrier = "ROAD" }), 0)
	eq(logic.weight(s, { kind = "cargo", carrier = "WATER" }), 1)
	eq(logic.weight(s, { kind = "cargo" }), 1)
	eq(logic.weight(s, { kind = "passenger", carrier = "RAIL" }), 0)
end)

test("weight: long_haul (both towns known and different)", function()
	local s = ruled("long_haul")
	eq(logic.weight(s, { kind = "passenger", fromTown = 1, toTown = 2 }), 3)
	eq(logic.weight(s, { kind = "cargo", fromTown = 1, toTown = 2 }), 3)
	eq(logic.weight(s, { kind = "passenger", fromTown = 1, toTown = 1.0 }), 1)
	eq(logic.weight(s, { kind = "passenger", toTown = 2 }), 1)
	eq(logic.weight(s, { kind = "cargo", fromTown = 2 }), 1)
end)

-- delivered ---------------------------------------------------------------------

test("delivered with facts: progress += round(sum of weights), units ignored, raw tallies", function()
	local s = activate()
	logic.delivered(s, { units = 99, kind = "cargo", facts = {
		{ kind = "cargo", cargoType = 3, toTown = 9 },
		{ kind = "cargo", cargoType = 3.0 },
		{ kind = "passenger", toTown = 9, fromTown = 4 },
		{ kind = "passenger" },
	} })
	eq(s.progress, 4)
	eq(s.tally, { cargoTypes = { [3] = 2 }, towns = { [9] = 2 } })
	s.rule = "freight_only"
	logic.delivered(s, { facts = { { kind = "cargo", cargoType = 5, toTown = 1 }, { kind = "passenger", toTown = 1 } } })
	eq(s.progress, 4 + 3)
	eq(s.tally, { cargoTypes = { [3] = 2, [5] = 1 }, towns = { [9] = 2, [1] = 2 } }, "tallies are unweighted")
	logic.delivered(s, { facts = {} })
	eq(s.progress, 7)
	-- fractional config weights round once per call (half up), like the MVP path
	s.rule = nil
	config.PASSENGER_WEIGHT = 0.5
	logic.delivered(s, { facts = { { kind = "passenger" }, { kind = "passenger" }, { kind = "passenger" } } })
	eq(s.progress, 7 + 2)
end)

test("delivered without facts: MVP path, or the rule's kind weight", function()
	local s = activate()
	logic.delivered(s, { units = 5, kind = "passenger" })
	eq(s.progress, 5)
	s.rule = "freight_only"
	logic.delivered(s, { units = 5, kind = "passenger" })
	logic.delivered(s, { units = 2, kind = "cargo" })
	eq(s.progress, 5 + 6)
	eq(s.tally, { cargoTypes = {}, towns = {} })
	-- ignored outside play
	s.phase = "ended"
	logic.delivered(s, { facts = { { kind = "cargo", toTown = 1 } } })
	eq(s.progress, 11)
	eq(s.tally.towns, {})
end)

-- factsNeeded ------------------------------------------------------------------

test("factsNeeded: nil for MVP logic; tally fields + rule needs; cached; nil when not in play", function()
	local s = activate()
	eq(mvp.factsNeeded(s), nil)
	eq(logic.factsNeeded(s), { cargoType = true, toTown = true })
	ok(logic.factsNeeded(s) == logic.factsNeeded(s), "cached")
	s.rule = "long_haul"
	eq(logic.factsNeeded(s), { cargoType = true, toTown = true, fromTown = true })
	s.rule = "rail_day"
	eq(logic.factsNeeded(s), { cargoType = true, toTown = true, carrier = true })
	config.TALLY_FACTS = false
	eq(logic.factsNeeded(s), { carrier = true })
	s.rule = "freight_only"
	eq(logic.factsNeeded(s), nil, "kind-only rule: the units path is exact")
	s.rule = nil
	eq(logic.factsNeeded(s), nil)
	s.rule = "local_hero"
	eq(logic.factsNeeded(s), { toTown = true })
	config.TALLY_FACTS = true
	s.phase = "ended"
	eq(logic.factsNeeded(s), nil)
	eq(logic.factsNeeded(nil), nil)
	s.phase = "running"
	config.METRIC = "stats"
	eq(logic.factsNeeded(s), nil)
end)

-- boss schedule ----------------------------------------------------------------

test("bosses: every 3rd round, announced when the round before starts", function()
	local s = activate()
	eq(s.boss, nil)
	eq(s.nextBoss, nil)
	local intents = clearRound(s) -- round 2 starts
	local announced = s.nextBoss
	ok(bosses.get(announced), tostring(announced))
	eq(s.boss, nil)
	ok(logged(intents, "next boss (round 3): " .. announced))
	local pickIntents = pickPlain(s)
	eq(find(pickIntents, "notify", "roundStart").params.nextBoss, announced)
	intents = clearRound(s) -- round 3 starts
	eq(s.round, 3)
	eq(s.boss, announced)
	eq(s.nextBoss, nil)
	ok(logged(intents, "boss round 3: " .. announced))
	pickIntents = pickPlain(s)
	local p = find(pickIntents, "notify", "roundStart").params
	eq(p.boss, announced)
	eq(p.rule, s.rule)
	toRound(s, 4)
	eq(s.boss, nil)
	eq(s.rule, nil)
	eq(s.nextBoss, nil)
	toRound(s, 5)
	ok(s.nextBoss ~= nil)
	local second = s.nextBoss
	toRound(s, 6)
	eq(s.boss, second)
end)

test("bosses: deterministic for a seed; without tallies only untargeted bosses are drawn", function()
	local function schedule(seed)
		local s = activate(seed)
		local out = {}
		for r = 2, 9 do
			toRound(s, r)
			out[#out + 1] = tostring(s.boss)
		end
		return table.concat(out, ",")
	end
	eq(schedule(7), schedule(7))
	local seen = {}
	for seed = 1, 40 do
		local s = activate(seed)
		toRound(s, 3)
		ok(s.boss == "inspector" or s.boss == "cargo_baron" or s.boss == "transit_commissioner", s.boss)
		seen[s.boss] = true
	end
	ok(seen.inspector and seen.cargo_baron and seen.transit_commissioner, "all eligible bosses appear")
end)

test("bosses: rule bosses set their rule; quota uses the rule's quotaMult for that round only", function()
	local s = activate()
	toRound(s, 2)
	logic.debug(s, { op = "setNextBoss", id = "cargo_baron", gameTime = 0 })
	clearRound(s)
	eq(s.boss, "cargo_baron")
	eq(s.rule, "freight_only")
	local base = config.BASE_QUOTA * config.GROWTH ^ 2
	eq(s.quota, math.floor(base * 0.3 + 0.5))
	eq(logic.computeQuota(s, 4), math.floor(config.BASE_QUOTA * config.GROWTH ^ 3 + 0.5), "other rounds: no rule mult")
end)

test("bosses: BOSS_EVERY = 0 or no bosses module -> never a boss", function()
	config.BOSS_EVERY = 0
	local s = activate()
	toRound(s, 7)
	eq(s.boss, nil)
	eq(s.nextBoss, nil)
	config.BOSS_EVERY = 3
	local m = activate(42, mvp)
	toRound(m, 7, mvp)
	eq(m.boss, nil)
	eq(m.nextBoss, nil)
end)

test("boss vehicle mods: applied with the round, removed after, rev bumps only on change", function()
	local s = activate()
	toRound(s, 2)
	eq(s.fx.vehicleModsRev, 0, "no change, no bump")
	logic.debug(s, { op = "setNextBoss", id = "inspector", gameTime = 0 })
	local intents = clearRound(s)
	eq(s.boss, "inspector")
	eq(s.fx.vehicleMods, { TopSpeed = 0.75 })
	eq(s.fx.vehicleModsRev, 1)
	eq(count(intents, "vehicleMods"), 1)
	eq(s.cardVehicleMods, {})
	-- a speed card during the boss round stacks additively with the curse
	s.offer = { "express", "venture", "lean_year" }
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	near(s.fx.vehicleMods.TopSpeed, 0.90)
	near(s.cardVehicleMods.TopSpeed, 1.15)
	eq(s.fx.vehicleModsRev, 2)
	intents = clearRound(s) -- round 4: boss gone, card mods stay
	eq(s.boss, nil)
	near(s.fx.vehicleMods.TopSpeed, 1.15)
	eq(s.fx.vehicleModsRev, 3)
	eq(count(intents, "vehicleMods"), 1)
	pickPlain(s)
	clearRound(s) -- round 5: unchanged
	eq(s.fx.vehicleModsRev, 3)
end)

test("boss vehicle mods: key dropped when back at 1.0; cap and floor", function()
	local s = activate()
	toRound(s, 2)
	logic.debug(s, { op = "setNextBoss", id = "inspector", gameTime = 0 })
	toRound(s, 4)
	eq(s.fx.vehicleMods, {})
	eq(s.fx.vehicleModsRev, 2)
	local lg = Logic.new(config, cards, rules, fakeBosses({
		{ id = "crawl", name = "Crawl", description = "x", vehicleMods = { TopSpeed = 0.01, Comfort = 5 } },
	}))
	local t = activate(1, lg)
	toRound(t, 3, lg)
	eq(t.boss, "crawl")
	eq(t.fx.vehicleMods, { TopSpeed = 0.1, Comfort = config.VEHICLE_MOD_CAP })
end)

test("run end keeps cardVehicleMods as history and clears nextBoss", function()
	local s = activate()
	toRound(s, 2)
	s.offer = { "express", "venture", "lean_year" }
	s.phase = "choosing"
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	s.progress = 0
	s.nextMonthTick = FAR
	local _, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.phase, "ended")
	ok(find(intents, "clearEffects"))
	near(s.cardVehicleMods.TopSpeed, 1.15)
	eq(s.nextBoss, nil)
end)

-- rule targets ---------------------------------------------------------------------

local function withTally(towns, cargoTypes, seed)
	local s = activate(seed)
	s.nextMonthTick = FAR
	s.tally = { towns = towns or {}, cargoTypes = cargoTypes or {} }
	clearRound(s) -- round 2: lastTally = that tally
	pickPlain(s)
	return s
end

test("targets: drawn from lastTally keys (weighted, deterministic); string/float keys normalised", function()
	local s = withTally({ [5] = 1, [9] = 3 })
	eq(s.lastTally.towns, { [5] = 1, [9] = 3 })
	eq(s.tally, { cargoTypes = {}, towns = {} })
	local copy = withTally({ [5] = 1, [9] = 3 })
	local _, intents = logic.debug(s, { op = "setRule", id = "local_hero", gameTime = 0 })
	logic.debug(copy, { op = "setRule", id = "local_hero", gameTime = 0 })
	ok(s.ruleTarget == 5 or s.ruleTarget == 9, tostring(s.ruleTarget))
	eq(s.ruleTarget, copy.ruleTarget)
	ok(logged(intents, "rule local_hero target=" .. s.ruleTarget))
	-- weighted: the big destination wins most draws
	local big = 0
	for seed = 1, 60 do
		local t = withTally({ [1] = 1, [2] = 99 }, nil, seed)
		logic.debug(t, { op = "setRule", id = "local_hero", gameTime = 0 })
		if t.ruleTarget == 2 then big = big + 1 end
	end
	ok(big >= 50, "big town drawn " .. big .. "/60")
	-- keys that came back as strings / floats after a save
	local u = activate()
	u.lastTally = { towns = { ["12"] = 3 }, cargoTypes = { [4.0] = 2 } }
	logic.debug(u, { op = "setRule", id = "local_hero", gameTime = 0 })
	eq(u.ruleTarget, 12)
	logic.debug(u, { op = "setRule", id = "specialist", gameTime = 0 })
	eq(u.ruleTarget, 4)
	eq(math.type(u.ruleTarget), "integer")
end)

test("targets: empty lastTally -> targeted rule ineligible (warning, no change)", function()
	local s = withTally({}, { [3] = 1 })
	local before = logic.dump(s)
	local _, intents = logic.debug(s, { op = "setRule", id = "local_hero", gameTime = 0 })
	ok(warned(intents, "has no town target"))
	eq(logic.dump(s), before)
	logic.debug(s, { op = "setRule", id = "specialist", gameTime = 0 })
	eq(s.rule, "specialist")
	eq(s.ruleTarget, 3)
end)

test("targets: announced targeted boss without a target is replaced at round start", function()
	local s = activate()
	toRound(s, 2)
	logic.debug(s, { op = "setNextBoss", id = "mayor", gameTime = 0 })
	local intents = clearRound(s) -- round 2 delivered nothing with facts
	ok(warned(intents, "announced boss mayor has no target this round; replaced by"))
	ok(s.boss ~= "mayor" and s.boss ~= "monopolist" and bosses.get(s.boss), tostring(s.boss))
	-- with a town tally the announced mayor stays and draws the town
	local t = activate()
	toRound(t, 2)
	logic.debug(t, { op = "setNextBoss", id = "mayor", gameTime = 0 })
	logic.delivered(t, { facts = { { kind = "passenger", toTown = 77 } } })
	clearRound(t)
	eq(t.boss, "mayor")
	eq(t.rule, "local_hero")
	eq(t.ruleTarget, 77)
	-- v2.1 addendum: the boss round's roundStart (after the pick) carries the target town
	local pickIntents = pickPlain(t)
	local p = find(pickIntents, "notify", "roundStart").params
	eq(p.boss, "mayor")
	eq(p.rule, "local_hero")
	eq(p.ruleTarget, 77)
end)

test("targets: only targeted bosses and no rules data -> boss runs without its rule", function()
	local lg = Logic.new(config, cards, rules, fakeBosses({
		{ id = "m", name = "M", description = "x", rule = "local_hero" },
	}))
	local s = activate(1, lg)
	local intents
	while s.round < 3 do
		intents = clearRound(s, lg)
		pickPlain(s, lg)
	end
	eq(s.boss, "m")
	eq(s.rule, nil)
	ok(warned(intents, "runs without its rule"))
end)

-- round-modifier cards ----------------------------------------------------------

local function choosingRound2(towns)
	local s = activate()
	s.tally = { towns = towns or {}, cargoTypes = {} }
	clearRound(s)
	return s
end

test("freight_contract: rule freight_only + rewardMultRound 1.5, paid when the round clears", function()
	local s = choosingRound2()
	s.offer = { "freight_contract", "venture", "lean_year" }
	local _, intents = logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	eq(warned(intents), false)
	eq(s.rule, "freight_only")
	eq(s.rewardMultRound, 1.5)
	eq(s.quota, math.floor(4000 * 0.3 + 0.5))
	eq(find(intents, "notify", "roundStart").params.rule, "freight_only")
	eq(find(intents, "notify", "roundStart").params.ruleTarget, nil, "untargeted rule: no ruleTarget")
	eq(logic.computeReward(s, 2, s.quota, s.quota), 2000000 * 2 * 1.5)
	eq(logic.computeReward(s, 3, s.quota, s.quota), 2000000 * 3, "other rounds: no round mult")
	intents = clearRound(s)
	eq(find(intents, "cash").amount, 6000000)
	eq(s.rewardMultRound, 1.0, "reset at round start")
end)

test("rush_hour and Hometown Hero", function()
	local s = choosingRound2()
	s.offer = { "rush_hour", "venture", "lean_year" }
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	eq(s.rule, "commuter_rush")
	eq(s.rewardMultRound, 1.3)
	eq(s.quota, math.floor(4000 * 1.8 + 0.5))
	local t = choosingRound2({ [42] = 10 })
	t.offer = { "local_hero_card", "venture", "lean_year" }
	local _, intents = logic.pickCard(t, { index = 1, gameTime = t.roundStartTime })
	eq(warned(intents), false)
	eq(t.rule, "local_hero")
	eq(t.ruleTarget, 42)
	-- v2.1 addendum: pickCard notifies roundStart after applying the card, with the target
	local p = find(intents, "notify", "roundStart").params
	eq(p.rule, "local_hero")
	eq(p.ruleTarget, 42)
	eq(t.quotaMultRound, 0.8)
	eq(t.quota, math.floor(4000 * 0.8 * 1.0 + 0.5))
	-- forced without a target (debug applyCard): warning, no rule, the quota cut still applies
	local u = choosingRound2()
	_, intents = logic.debug(u, { op = "applyCard", id = "local_hero_card", gameTime = u.roundStartTime })
	ok(warned(intents, "has no town target"))
	eq(u.rule, nil)
	eq(u.quota, 3200)
end)

-- offers -------------------------------------------------------------------------

local function offerSeen(s, n)
	local seen = {}
	for _ = 1, n or 200 do
		for _, id in ipairs(logic.drawOffer(s)) do seen[id] = true end
	end
	return seen
end

test("offers: rule cards need rules data, a drawable target, and no boss rule", function()
	local s = choosingRound2()
	local seen = offerSeen(s)
	ok(seen.freight_contract and seen.rush_hour, "untargeted rule cards offered")
	eq(seen.local_hero_card, nil, "no towns last round")
	seen = offerSeen(choosingRound2({ [1] = 1 }))
	ok(seen.local_hero_card, "towns last round")
	local m = activate(42, mvp)
	m.lastTally = { towns = { [1] = 1 }, cargoTypes = {} }
	local mseen = {}
	for _ = 1, 200 do for _, id in ipairs(mvp.drawOffer(m)) do mseen[id] = true end end
	eq(mseen.freight_contract, nil)
	eq(mseen.rush_hour, nil)
	eq(mseen.local_hero_card, nil)
end)

test("offers: boss rule round excludes rule cards; a rule-less boss does not", function()
	local s = activate()
	s.tally = { towns = { [1] = 5 }, cargoTypes = {} }
	clearRound(s)
	pickPlain(s)
	logic.debug(s, { op = "setNextBoss", id = "cargo_baron", gameTime = 0 })
	s.tally = { towns = { [1] = 5 }, cargoTypes = {} }
	clearRound(s)
	eq(s.boss, "cargo_baron")
	local seen = offerSeen(s)
	eq(seen.freight_contract, nil)
	eq(seen.rush_hour, nil)
	eq(seen.local_hero_card, nil)
	-- forcing one anyway: the boss rule wins
	local _, intents = logic.debug(s, { op = "applyCard", id = "rush_hour", gameTime = s.roundStartTime })
	ok(warned(intents, "the boss rule freight_only wins"))
	eq(s.rule, "freight_only")
	eq(s.rewardMultRound, 1.3, "the card's other effects still apply")
	logic.debug(s, { op = "setBoss", id = "inspector", gameTime = 0 })
	eq(s.rule, nil)
	seen = offerSeen(s)
	ok(seen.freight_contract and seen.rush_hour and seen.local_hero_card)
end)

-- boss reward ---------------------------------------------------------------------

test("boss round pays BOSS_REWARD_MULT (times rewardMultRound and the bonus)", function()
	local s = activate()
	toRound(s, 3)
	ok(s.boss ~= nil)
	eq(logic.computeReward(s, 3, s.quota, s.quota), 2000000 * 3 * 2)
	s.rewardMultRound = 1.5
	eq(logic.computeReward(s, 3, s.quota * 2, s.quota), 2000000 * 3 * 2 * 1.5 * 1.5)
	s.rewardMultRound = 1.0
	local intents = clearRound(s)
	eq(find(intents, "cash").amount, 12000000)
	eq(s.lastReward, 12000000)
	eq(s.boss, nil)
	clearRound(s) -- round 4 -> no boss multiplier
	eq(s.lastReward, 2000000 * 4)
end)

-- RANDOM_RULE_FROM_ROUND ------------------------------------------------------------

test("RANDOM_RULE_FROM_ROUND: non-boss rounds from that round get an eligible rule", function()
	config.RANDOM_RULE_FROM_ROUND = 2
	local s = activate()
	eq(s.rule, nil, "round 1")
	toRound(s, 2)
	ok(s.rule ~= nil and rules.get(s.rule).target == nil, tostring(s.rule))
	eq(s.boss, nil)
	toRound(s, 3)
	eq(rules.get(s.rule) ~= nil or s.boss == "inspector", true)
	ok(s.boss ~= nil)
	-- off (0): nothing
	config.RANDOM_RULE_FROM_ROUND = 0
	local t = activate()
	toRound(t, 2)
	eq(t.rule, nil)
end)

-- debug ops ----------------------------------------------------------------------

test("debug setRule: set, clear with '' or 'none', unknown -> warning, no change", function()
	local s = activate()
	local _, intents = logic.debug(s, { op = "setRule", id = "commuter_rush", gameTime = 0 })
	eq(s.rule, "commuter_rush")
	eq(s.quota, math.floor(config.BASE_QUOTA * 1.8 + 0.5))
	ok(logged(intents, "debug setRule commuter_rush"))
	logic.debug(s, { op = "setRule", id = "", gameTime = 0 })
	eq(s.rule, nil)
	eq(s.quota, config.BASE_QUOTA)
	logic.debug(s, { op = "setRule", id = "freight_only" })
	logic.debug(s, { op = "setRule", id = "none" })
	eq(s.rule, nil)
	for _, bad in ipairs({ "nope", false }) do
		local before = logic.dump(s)
		_, intents = logic.debug(s, { op = "setRule", id = bad or nil, gameTime = 0 })
		eq(logic.dump(s), before)
		ok(warned(intents), tostring(bad))
	end
	-- MVP logic has no rules
	local m = activate(42, mvp)
	_, intents = mvp.debug(m, { op = "setRule", id = "freight_only" })
	ok(warned(intents, "unknown rule id"))
	eq(m.rule, nil)
end)

test("debug setBoss: boss now (rule + vehicle mods + reward), '' clears and restores", function()
	local s = activate()
	local _, intents = logic.debug(s, { op = "setBoss", id = "inspector" })
	eq(s.boss, "inspector")
	eq(s.fx.vehicleMods, { TopSpeed = 0.75 })
	eq(count(intents, "vehicleMods"), 1)
	eq(logic.computeReward(s, 1, s.quota, s.quota), 2000000 * 2)
	_, intents = logic.debug(s, { op = "setBoss", id = "transit_commissioner" })
	eq(s.boss, "transit_commissioner")
	eq(s.rule, "commuter_rush")
	eq(s.fx.vehicleMods, {})
	eq(s.quota, math.floor(config.BASE_QUOTA * 1.8 + 0.5))
	_, intents = logic.debug(s, { op = "setBoss", id = "" })
	eq(s.boss, nil)
	eq(s.rule, nil, "the boss's rule goes with it")
	eq(s.quota, config.BASE_QUOTA)
	eq(s.fx.vehicleModsRev, 2)
	local before = logic.dump(s)
	_, intents = logic.debug(s, { op = "setBoss", id = "nope" })
	ok(warned(intents, "unknown boss id"))
	_, intents = logic.debug(s, { op = "setBoss", id = "mayor" })
	ok(warned(intents, "no rule target"))
	eq(logic.dump(s), before)
end)

test("debug clearEffects also forgets card vehicle mods (a later boss does not re-send them)", function()
	local s = activate()
	logic.debug(s, { op = "applyCard", id = "express", gameTime = 0 })
	eq(s.fx.vehicleMods.TopSpeed, 1.15)
	logic.debug(s, { op = "clearEffects", gameTime = 0 })
	s.fx.vehicleMods = {} -- what quota_effects.clearEffects does with the intent
	logic.debug(s, { op = "setBoss", id = "inspector", gameTime = 0 })
	eq(s.fx.vehicleMods.TopSpeed, 0.75)
end)

test("debug setNextBoss: set, clear, unknown; refused when the next round is no boss round", function()
	local s = activate()
	local _, refused = logic.debug(s, { op = "setNextBoss", id = "inspector" })
	ok(warned(refused, "is not a boss round"))
	eq(s.nextBoss, nil)
	toRound(s, 2)
	logic.debug(s, { op = "setNextBoss", id = "monopolist" })
	eq(s.nextBoss, "monopolist")
	logic.debug(s, { op = "setNextBoss", id = "none" })
	eq(s.nextBoss, nil)
	local _, intents = logic.debug(s, { op = "setNextBoss", id = "x" })
	ok(warned(intents, "unknown boss id"))
	eq(s.nextBoss, nil)
end)

test("v2 debug ops: DEBUG=false gated; not in play -> warning; no gameTime needed", function()
	config.DEBUG = false
	for _, op in ipairs({ "setRule", "setBoss", "setNextBoss", "incomeProbe", "factsProbe" }) do
		local s = activate()
		local before = logic.dump(s)
		local _, intents = logic.debug(s, { op = op, id = "inspector", n = 1, gameTime = 0 })
		eq(logic.dump(s), before, op)
		ok(warned(intents, "DEBUG is off"), op)
		eq(#intents, 1)
	end
	config.DEBUG = true
	local s = activate()
	s.phase = "ended"
	local before = logic.dump(s)
	local _, intents = logic.debug(s, { op = "setBoss", id = "inspector" })
	ok(warned(intents, "ignored in phase"))
	eq(logic.dump(s), before)
end)

test("probe ops are adapter-only: acknowledged without warning or change", function()
	for _, op in ipairs({ "incomeProbe", "factsProbe", "jumpYears", "closeIndustry", "townProbe" }) do
		local s = activate()
		local before = logic.dump(s)
		local _, intents = logic.debug(s, { op = op, n = 2, gameTime = 0 })
		eq(logic.dump(s), before, op)
		eq(warned(intents), false, op)
		ok(logged(intents, "adapter-only"), op)
	end
end)

test("debug dump shows the v2 fields", function()
	local s = activate()
	s.rule, s.nextBoss = "freight_only", "inspector"
	local _, intents = logic.debug(s, { op = "dump" })
	ok(logged(intents, "dump v2: version=2 rule=freight_only ruleTarget=nil boss=nil nextBoss=inspector rewardMultRound=1"))
	ok(logged(intents, "factsNeeded=cargoType,toTown"))
	ok(logged(intents, 'rule="freight_only"'))
end)

-- nil rules / bosses = MVP -----------------------------------------------------------

test("nil rules/bosses: MVP behaviour over many rounds (no boss/rule, MVP pool, MVP rewards)", function()
	local s = activate(42, mvp)
	eq(s.version, 2)
	for r = 2, 8 do
		local intents = clearRound(s, mvp)
		eq(find(intents, "cash").amount, 2000000 * (r - 1))
		for _, id in ipairs(s.offer) do
			local idx
			for i, c in ipairs(cards.list) do if c.id == id then idx = i end end
			ok(idx <= 12, id)
		end
		eq(count(intents, "vehicleMods"), 0)
		pickPlain(s, mvp)
		eq(s.boss, nil)
		eq(s.rule, nil)
		eq(s.nextBoss, nil)
		eq(s.rewardMultRound, 1.0)
	end
	eq(mvp.factsNeeded(s), nil)
	-- same seed, same offers as a second MVP instance (no hidden extra RNG draws)
	local a, b = activate(9, mvp), activate(9, Logic.new(config, cards, nil, nil))
	clearRound(a, mvp)
	clearRound(b, mvp)
	eq(a.offer, b.offer)
	eq(a.rngSeed, b.rngSeed)
end)
