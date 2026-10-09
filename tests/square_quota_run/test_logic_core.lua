-- quota_logic: activation, inert behaviour, quota/reward math, RNG and offers, delivered counter,
-- card data (PLAN §3.1, §3.2, §4.1, §5.2).

local config = ug_require "/quota/quota_config.tl"
local logic = ug_require("/quota/quota_logic.tl").new(config, ug_require "/quota/quota_cards.tl")
local cards = ug_require "/quota/quota_cards.tl"

local MD = 1000 -- month duration in game-time units

local function activate(t, seed)
	local s, intents = logic.activate(nil, { gameTime = t or 0, seed = seed or (t or 0), monthDuration = MD, statsTotal = 7 })
	return s, intents
end

local function kinds(intents)
	local out = {}
	for i, it in ipairs(intents) do out[i] = it.kind end
	return out
end

local function find(intents, kind, key)
	for _, it in ipairs(intents) do
		if it.kind == kind and (key == nil or it.key == key) then return it end
	end
end

before_each(function()
	config.DEBUG = true
	config.METRIC = "events"
	config.CARGO_WEIGHT = 1
	config.PASSENGER_WEIGHT = 1
end)

-- activation -------------------------------------------------------------

test("activate builds a fresh round-1 state", function()
	local s, intents = activate(5000)
	eq(s.version, 2)
	eq(s.active, true)
	eq(s.phase, "running")
	eq(s.round, 1)
	eq(s.roundsCleared, 0)
	eq(s.runStartTime, 5000)
	eq(s.roundStartTime, 5000)
	eq(s.roundEndTime, 5000 + config.FIRST_ROUND_MONTHS * MD)
	eq(s.nextMonthTick, 5000 + MD)
	eq(s.monthDuration, MD)
	eq(s.quota, config.BASE_QUOTA)
	eq(s.progress, 0)
	eq(s.statsBaseline, 7)
	eq(s.totalTransported, 0)
	eq(s.redMonths, 0)
	eq(s.quotaMultAll, 1.0)
	eq(s.quotaMultRound, 1.0)
	eq(s.rewardMult, 1.0)
	eq(s.picked, {})
	eq(s.offer, nil)
	eq(s.endReason, nil)
	eq(s.halfwayWarned, false)
	eq(s.fx, { vehicleMods = {}, vehicleModsRev = 0, vehicleApplied = {}, industryMods = {}, nextScanTime = 5000 })
	ok(s.rngSeed > 0 and s.rngSeed < 2147483647)
	local n = find(intents, "notify", "roundStart")
	eq(n.params, { round = 1, quota = config.BASE_QUOTA, months = config.FIRST_ROUND_MONTHS })
	ok(find(intents, "log").message:find("activated", 1, true))
end)

test("activate is idempotent: an existing state (active or not) is untouched", function()
	local s = activate(0)
	s.progress = 42
	local s2, intents = logic.activate(s, { gameTime = 99, seed = 99, monthDuration = MD })
	ok(s2 == s)
	eq(s2.progress, 42)
	eq(intents, {})
	local inactive = { active = false }
	local s3, i3 = logic.activate(inactive, { gameTime = 1, seed = 1, monthDuration = MD })
	ok(s3 == inactive)
	eq(i3, {})
end)

test("activate on an empty table (state:get() == {}) activates", function()
	local s = logic.activate({}, { gameTime = 0, seed = 0, monthDuration = MD })
	eq(s.active, true)
end)

test("activate with invalid input stays inert", function()
	local s, intents = logic.activate(nil, { gameTime = 0, seed = 0, monthDuration = 0 })
	eq(s, nil)
	eq(intents[1].level, "warning")
end)

test("inert: every entry point is a no-op on nil or inactive state", function()
	for _, st in ipairs({ false, true }) do
		local s = st and { phase = "running", progress = 3 } or nil
		local function same(fn, input)
			local r, intents = fn(s, input)
			ok(r == s)
			eq(intents, {})
		end
		same(logic.tick, { gameTime = 1e9, balance = -5, statsTotal = 1 })
		same(logic.delivered, { units = 10, kind = "cargo" })
		same(logic.pickCard, { index = 1, gameTime = 0 })
		same(logic.continueSandbox, {})
		same(logic.debug, { op = "endRound", gameTime = 0 })
	end
end)

-- quota / reward math --------------------------------------------------------

test("quota formula with growth and both multipliers", function()
	local s = { quotaMultAll = 1.0, quotaMultRound = 1.0 }
	eq(logic.computeQuota(s, 1), 2500)
	eq(logic.computeQuota(s, 2), 4000)
	eq(logic.computeQuota(s, 3), 6400)
	s.quotaMultAll = 0.85
	s.quotaMultRound = 1.3
	eq(logic.computeQuota(s, 2), math.floor(2500 * 1.6 * 0.85 * 1.3 + 0.5))
end)

test("quota formula floors at 1", function()
	eq(logic.computeQuota({ quotaMultAll = 0.0, quotaMultRound = 1.0 }, 1), 1)
	eq(logic.computeQuota({ quotaMultAll = 1e-9, quotaMultRound = 0.5 }, 1), 1)
end)

test("reward: base x round x rewardMult, +50% at 150% of quota", function()
	local s = { rewardMult = 1.0 }
	eq(logic.computeReward(s, 1, 100, 100), 2000000)
	eq(logic.computeReward(s, 3, 149, 100), 6000000)
	eq(logic.computeReward(s, 3, 150, 100), 9000000)
	s.rewardMult = 1.5
	eq(logic.computeReward(s, 2, 100, 100), 6000000)
end)

test("monthsLeft in default months", function()
	local s = activate(0)
	near(logic.monthsLeft(s, 0), config.FIRST_ROUND_MONTHS)
	near(logic.monthsLeft(s, s.roundEndTime - 500), 0.5)
end)

-- RNG / offers -------------------------------------------------------------

test("rng: deterministic, in range, state advances", function()
	local a, b = { rngSeed = logic.mixSeed(123) }, { rngSeed = logic.mixSeed(123) }
	for _ = 1, 200 do
		local x, y = logic.rngNext(a, 12), logic.rngNext(b, 12)
		eq(x, y)
		ok(x >= 1 and x <= 12 and math.type(x) == "integer")
	end
	ok(a.rngSeed == b.rngSeed)
	local c = { rngSeed = logic.mixSeed(124) }
	local seqA, seqC = {}, {}
	local a2 = { rngSeed = logic.mixSeed(123) }
	for i = 1, 10 do seqA[i] = logic.rngNext(a2, 1000); seqC[i] = logic.rngNext(c, 1000) end
	ok(not (table.concat(seqA, ",") == table.concat(seqC, ",")), "different seeds differ")
end)

test("rng: mixSeed never yields 0 or the modulus; bad seeds recover", function()
	ok(logic.mixSeed(0) > 0)
	ok(logic.mixSeed(2147483647 - config.SEED_MIX) > 0)
	ok(logic.mixSeed(-config.SEED_MIX) > 0)
	local s = { rngSeed = 0 }
	local v = logic.rngNext(s, 3)
	ok(v >= 1 and v <= 3 and s.rngSeed > 0)
end)

test("offers: 3 distinct known ids; same seed -> same offer", function()
	for seed = 0, 300, 7 do
		local s1, s2 = { rngSeed = logic.mixSeed(seed) }, { rngSeed = logic.mixSeed(seed) }
		local o1, o2 = logic.drawOffer(s1), logic.drawOffer(s2)
		eq(o1, o2)
		eq(#o1, 3)
		local seen = {}
		for _, id in ipairs(o1) do
			ok(cards.get(id), "known card " .. id)
			ok(not seen[id], "distinct")
			seen[id] = true
		end
	end
end)

test("offers: all 12 MVP cards can be offered (no rules module: rule cards never offered)", function()
	local seen, n = {}, 0
	local s = { rngSeed = logic.mixSeed(1) }
	for _ = 1, 200 do
		for _, id in ipairs(logic.drawOffer(s)) do
			if not seen[id] then seen[id] = true; n = n + 1 end
		end
	end
	eq(n, 12)
end)

-- delivered ---------------------------------------------------------------

test("delivered adds weighted units in running and choosing", function()
	local s = activate(0)
	logic.delivered(s, { units = 5, kind = "cargo" })
	logic.delivered(s, { units = 3, kind = "passenger" })
	eq(s.progress, 8)
	config.CARGO_WEIGHT = 2
	config.PASSENGER_WEIGHT = 0.5
	logic.delivered(s, { units = 5, kind = "cargo" })
	logic.delivered(s, { units = 4, kind = "passenger" })
	eq(s.progress, 8 + 10 + 2)
	s.phase = "choosing"
	logic.delivered(s, { units = 1, kind = "cargo" })
	eq(s.progress, 22)
end)

test("delivered ignored when ended/sandbox, for bad input, and with METRIC=stats", function()
	local s = activate(0)
	for _, ph in ipairs({ "ended", "sandbox" }) do
		s.phase = ph
		local _, intents = logic.delivered(s, { units = 5, kind = "cargo" })
		eq(s.progress, 0)
		eq(intents, {})
	end
	s.phase = "running"
	logic.delivered(s, { units = 0, kind = "cargo" })
	logic.delivered(s, { units = -3, kind = "cargo" })
	logic.delivered(s, {})
	eq(s.progress, 0)
	config.METRIC = "stats"
	logic.delivered(s, { units = 5, kind = "cargo" })
	eq(s.progress, 0)
end)

test("METRIC=stats: progress = statsTotal - statsBaseline on tick", function()
	config.METRIC = "stats"
	local s = activate(0) -- baseline 7
	logic.tick(s, { gameTime = 10, balance = 1, statsTotal = 107 })
	eq(s.progress, 100)
	logic.tick(s, { gameTime = 20, balance = 1, statsTotal = 3 })
	eq(s.progress, 0)
end)

-- card data ----------------------------------------------------------------

test("cards: 15 cards with id, name, description, known effect kinds", function()
	local known = { cash = true, quotaMultRound = true, quotaMultAll = true, roundMonths = true,
		vehicleMod = true, industryProd = true, rewardMult = true, rule = true, rewardMultRound = true }
	local rules = ug_require "/quota/quota_rules.tl"
	local ids = {}
	eq(#cards.list, 15)
	for _, c in ipairs(cards.list) do
		ok(type(c.id) == "string" and c.id:match("^[a-z_]+$"), c.id)
		ok(type(c.name) == "string" and #c.name > 0)
		ok(type(c.description) == "string" and #c.description > 0)
		ok(#c.effects >= 1)
		for _, e in ipairs(c.effects) do
			ok(known[e.kind], c.id .. ": " .. tostring(e.kind))
			if e.kind == "industryProd" then ok(e.mult >= 1.0, "industryProd >= 1.0") end
			if e.kind == "rule" then ok(rules.get(e.rule), c.id .. ": known rule " .. tostring(e.rule)) end
			if e.kind == "rewardMultRound" then ok(e.mult > 0, c.id .. ": rewardMultRound > 0") end
		end
		ok(not ids[c.id])
		ids[c.id] = true
		ok(cards.byId[c.id] == c and cards.get(c.id) == c)
	end
	eq(ids, { venture = true, hostile_loan = true, express = true, overdrive = true, luxury = true,
		boomtown = true, industrial_policy = true, lean_year = true, extension = true, crunch = true,
		austerity = true, gamble = true, freight_contract = true, rush_hour = true, local_hero_card = true })
	-- append-only order: the MVP 12 keep their positions (offer draws index into the list)
	eq(cards.list[12].id, "gamble")
end)

test("dump is deterministic with sorted keys", function()
	eq(logic.dump({ b = 1, a = { "x" }, [3] = true }), '{[3]=true, a={[1]="x"}, b=1}')
	eq(logic.dump(nil), "nil")
end)
