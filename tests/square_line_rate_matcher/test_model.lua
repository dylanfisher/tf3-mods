-- rate_matcher_model: supply target (dedupe, other lines by loaded cargo, passengers, unsupplied cargo),
-- per-vehicle shares, the below/above suggestion with preselection and edge cases, multi-cargo choice,
-- alternative-model ranking and the surplus pick. Real numbers from the 2026-10-10 probe
-- (docs/findings.md "Line Rate, cloning onto a line, sell on arrival", plans/square_line_rate_matcher/probe_run*.log).

local model = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_model.tl"

local PASSENGER, LOGS, GRAIN, COAL = 0, 4, 3, 5

local function set(...)
	local s = {}
	for _, c in ipairs({ ... }) do s[c] = true end
	return s
end

local function producer(stockList, cargo, max, produced)
	return { stockList = stockList, cargo = cargo, maxPerYear = max, producedPerYear = produced }
end

local function stop(group, loads, producers)
	return { stationGroup = group, loads = loads, producers = producers }
end

local function ship(id, modelId, cap, cargo, purchaseTime, extra)
	local v = { id = id, model = modelId, capacities = { [cargo or LOGS] = cap }, purchaseTime = purchaseTime or id }
	for k, x in pairs(extra or {}) do v[k] = x end
	return v
end

local function ships(n, cap, cargo)
	local out = {}
	for i = 1, n do out[i] = ship(100 + i, 7, cap or 20, cargo, i) end
	return out
end

-- helpers -------------------------------------------------------------------------

test("roundValue and loadSetFromIdVector", function()
	eq(model.roundValue(100.5), 101)
	eq(model.roundValue(-1), nil)
	eq(model.roundValue(0 / 0), nil)
	eq(model.loadSetFromIdVector({ false, false, false, false, true }), { [LOGS] = true })
	eq(model.loadSetFromIdVector({ true }), { [PASSENGER] = true })
	eq(model.loadSetFromIdVector(nil), {})
end)

-- targetsFromSupply ---------------------------------------------------------------

-- WC Logs (probe run 2): stop 1 (group 10) loads logs next to the logging camp (max 101, measured 112),
-- stop 2 (group 20) unloads. Group 10 is shared with two passenger lines (Rate 103 and 89).
local function wcLogs()
	return {
		line = 1,
		passengerCargo = PASSENGER,
		stops = {
			stop(10, set(LOGS), { producer(500, LOGS, 101, 112), producer(600, PASSENGER, 300, 280) }),
			stop(20, set(), { producer(700, COAL, 50, 50) }),
		},
		otherLines = {
			{ line = 2, rate = 103, stops = { stop(10, set(PASSENGER)), stop(30, set(PASSENGER)) } },
			{ line = 3, rate = 89, stops = { stop(10, set(PASSENGER)), stop(40, set(PASSENGER)) } },
		},
	}
end

test("WC Logs: target 101 = logging camp max, passenger lines at the group not subtracted", function()
	local targets, unsupplied = model.targetsFromSupply(wcLogs())
	eq(#targets, 1)
	local t = targets[1]
	eq(t.cargo, LOGS)
	eq(t.maxSupply, 101)
	eq(t.produced, 112)
	eq(t.otherRate, 0)
	eq(t.otherLines, {})
	eq(t.producers, { 500 })
	eq(t.target, 101)
	eq(unsupplied, {})
end)

test("other lines loading the same cargo at the group are subtracted, once each", function()
	local input = wcLogs()
	input.otherLines[#input.otherLines + 1] =
		{ line = 4, rate = 30, stops = { stop(10, set(LOGS)), stop(10, set(LOGS)), stop(50, set()) } }
	input.otherLines[#input.otherLines + 1] = { line = 4, rate = 30, stops = { stop(10, set(LOGS)) } } -- duplicate
	input.otherLines[#input.otherLines + 1] = { line = 1, rate = 66, stops = { stop(10, set(LOGS)) } } -- ourselves
	input.otherLines[#input.otherLines + 1] = { line = 5, rate = 20, stops = { stop(10, set()), stop(60, set(LOGS)) } }
	local t = model.targetsFromSupply(input)[1]
	eq(t.otherRate, 30)
	eq(t.otherLines, { 4 })
	eq(t.target, 71)
end)

test("a competitor at another group counts when it reaches one of our producers", function()
	local input = wcLogs()
	input.otherLines = {
		{ line = 8, rate = 40, stops = { stop(77, set(LOGS), { producer(500, LOGS, 101) }) } },
		{ line = 9, rate = 40, stops = { stop(78, set(LOGS), { producer(999, LOGS, 80) }) } },
	}
	local t = model.targetsFromSupply(input)[1]
	eq(t.otherLines, { 8 })
	eq(t.target, 61)
end)

test("target clamps at 0 when other lines take more than the supply", function()
	local input = wcLogs()
	input.otherLines = { { line = 4, rate = 250, stops = { stop(10, set(LOGS)) } } }
	local t = model.targetsFromSupply(input)[1]
	eq(t.otherRate, 250)
	eq(t.target, 0)
end)

test("a producer reachable from several loading stops counts once; two producers add up", function()
	local input = {
		line = 1, passengerCargo = PASSENGER,
		stops = {
			stop(10, set(LOGS), { producer(500, LOGS, 101, 98) }),
			stop(11, set(LOGS), { producer(500, LOGS, 101, 98), producer(501, LOGS, 50, nil) }),
			stop(12, set(), { producer(502, LOGS, 70, 70) }), -- unload-only stop: not counted
		},
		otherLines = {},
	}
	local t = model.targetsFromSupply(input)[1]
	eq(t.maxSupply, 151)
	eq(t.produced, 98)
	eq(t.producers, { 500, 501 })
	eq(t.target, 151)
end)

test("multi-cargo line: one target per cargo; unsupplied cargo and passengers get none", function()
	local input = {
		line = 1, passengerCargo = PASSENGER,
		stops = {
			stop(10, set(GRAIN, COAL, PASSENGER), { producer(1, GRAIN, 80, 75), producer(2, PASSENGER, 200, 200) }),
			stop(20, set(COAL, LOGS), { producer(3, COAL, 40, nil) }),
		},
		otherLines = { { line = 6, rate = 15, stops = { stop(20, set(COAL)) } } },
	}
	local targets, unsupplied = model.targetsFromSupply(input)
	eq(#targets, 2)
	eq(targets[1].cargo, GRAIN)
	eq(targets[1].target, 80)
	eq(targets[1].otherRate, 0)
	eq(targets[2].cargo, COAL)
	eq(targets[2].target, 25)
	eq(targets[2].produced, nil)
	eq(unsupplied, { LOGS })
end)

test("targetsFromSupply survives bad input", function()
	local t, u = model.targetsFromSupply(nil)
	eq(t, {})
	eq(u, {})
	t = model.targetsFromSupply({ stops = { stop(1, set(LOGS), { producer(1, LOGS, 0 / 0, -5) }) } })
	eq(t[1].maxSupply, 0)
	eq(t[1].produced, nil)
	eq(t[1].target, 0)
end)

-- perVehicleRates -----------------------------------------------------------------

test("perVehicleRates: equal shares for identical vehicles, capacity shares for mixed lines", function()
	local pv, pm = model.perVehicleRates(66, ships(2), LOGS)
	eq(pv, { [101] = 33, [102] = 33 })
	eq(pm, { [7] = 33 })
	local mixed = { ship(1, 7, 20), ship(2, 7, 20), ship(3, 9, 40) }
	pv, pm = model.perVehicleRates(160, mixed, LOGS)
	eq(pm, { [7] = 40, [9] = 80 })
	eq(model.perVehicleRates(100, { ship(1, 7, 0) }, LOGS), nil)
	pv = model.perVehicleRates(90, { ship(1, 7, 20), ship(2, 7, 20, LOGS, 2, { selling = true }) }, LOGS)
	eq(pv, { [1] = 90 })
end)

-- suggest ---------------------------------------------------------------------------

test("WC Logs: 2 ships Rate 66, target 101 -> 3 = 99 / 4 = 132, preselect 3", function()
	local s = model.suggest(66, ships(2), LOGS, 101)
	eq(s.status, "ok")
	eq(s.perVehicle, 33)
	eq(s.below.count, 3)
	eq(s.below.rate, 99)
	eq(s.above.count, 4)
	eq(s.above.rate, 132)
	eq(s.preselected.count, 3)
	eq(s.delta, 1)
	eq(s.capped, false)
	eq(s.templateModel, 7)
	eq(s.templateVehicle, 102)
end)

test("WC Logs end to end: supply target feeds the suggestion", function()
	local target = model.targetsFromSupply(wcLogs())[1].target
	local s = model.suggest(66, ships(2), LOGS, target)
	eq(s.preselected.delta, 1)
	eq(s.preselected.count, 3)
end)

test("passenger ship line 1/2/3 ships = 51/103/154: perVehicle predicts the others", function()
	-- From 2 ships (103): 1 ship and 3 ships.
	local s = model.suggest(103, ships(2, 20, PASSENGER), PASSENGER, 154)
	near(s.above.rate, 154, 1)
	eq(s.above.count, 3)
	eq(s.preselected.count, 3)
	s = model.suggest(103, ships(2, 20, PASSENGER), PASSENGER, 51)
	eq(s.preselected.count, 1)
	near(s.preselected.rate, 51, 1)
	eq(s.preselected.remove, { 102 })
	-- From 1 ship (51) up to 3, and from 3 (154) down to 1.
	s = model.suggest(51, ships(1, 20, PASSENGER), PASSENGER, 154)
	eq(s.preselected.count, 3)
	near(s.preselected.rate, 154, 1)
	s = model.suggest(154, ships(3, 20, PASSENGER), PASSENGER, 51)
	eq(s.preselected.count, 1)
	near(s.preselected.rate, 51, 1)
	eq(s.preselected.remove, { 103, 102 })
end)

test("exact hit: below and above are the same option", function()
	local s = model.suggest(66, ships(2), LOGS, 99)
	eq(s.below.count, 3)
	ok(s.below == s.above)
	s = model.suggest(66, ships(2), LOGS, 66)
	eq(s.delta, 0)
	eq(s.preselected.remove, nil)
end)

test("tie between below and above goes to fewer vehicles", function()
	local s = model.suggest(60, ships(2), LOGS, 75) -- 60 vs 90
	eq(s.below.count, 2)
	eq(s.above.count, 3)
	eq(s.preselected.count, 2)
end)

test("target 0 removes down to MIN_VEHICLES, never protected vehicles", function()
	local v = ships(4)
	v[4].protected = true
	local s = model.suggest(132, v, LOGS, 0)
	eq(s.status, "ok")
	eq(s.below, nil)
	eq(s.above.count, 1)
	eq(s.preselected.delta, -3)
	eq(s.preselected.remove, { 103, 102, 101 })
	-- All but one protected: nothing to remove.
	v[1].protected, v[2].protected, v[3].protected = true, true, nil
	s = model.suggest(132, v, LOGS, 0)
	eq(s.preselected.delta, -1)
	eq(s.preselected.remove, { 103 })
end)

test("huge target caps at MAX_ADD clones", function()
	local s = model.suggest(33, ships(1), LOGS, 1e9)
	eq(s.capped, true)
	eq(s.above, nil)
	eq(s.below.delta, model.MAX_ADD)
	eq(s.preselected.delta, model.MAX_ADD)
	eq(s.preselected.rate, 33 * (1 + model.MAX_ADD))
end)

test("edge cases: no vehicles, Rate 0, no capacity, bad target", function()
	eq(model.suggest(66, {}, LOGS, 101).status, "no_vehicles")
	eq(model.suggest(66, { ship(1, 7, 20, LOGS, 1, { selling = true }) }, LOGS, 101).status, "no_vehicles")
	eq(model.suggest(0, ships(2), LOGS, 101).status, "no_rate")
	eq(model.suggest(0 / 0, ships(2), LOGS, 101).status, "no_rate")
	eq(model.suggest(66, ships(2, 20, GRAIN), LOGS, 101).status, "no_capacity")
	eq(model.suggest(66, ships(2), LOGS, -1).status, "invalid_target")
	eq(model.suggest(66, ships(2), LOGS, nil).status, "invalid_target")
end)

test("mixed models: clones use the most common model, removals subtract each vehicle's share", function()
	-- Rate 160: model 7 (cap 20) = 40 each x2, model 9 (cap 40) = 80, the newest.
	local v = { ship(1, 7, 20, LOGS, 1), ship(2, 7, 20, LOGS, 2), ship(3, 9, 40, LOGS, 3) }
	local s = model.suggest(160, v, LOGS, 200)
	eq(s.templateModel, 7)
	eq(s.templateVehicle, 2)
	eq(s.perVehicle, 40)
	eq(s.preselected.count, 4)
	eq(s.preselected.rate, 200)
	s = model.suggest(160, v, LOGS, 80)
	-- Newest first: removing #3 (80) leaves exactly 80.
	eq(s.preselected.remove, { 3 })
	eq(s.preselected.rate, 80)
	-- Tie in vehicle count: the model with the newest vehicle.
	s = model.suggest(120, { ship(1, 7, 20, LOGS, 1), ship(2, 9, 40, LOGS, 5) }, LOGS, 200)
	eq(s.templateModel, 9)
end)

test("vehicles carrying none of the cargo are neither template nor removed", function()
	local v = { ship(1, 7, 20, LOGS, 1), ship(2, 8, 30, GRAIN, 9) }
	local s = model.suggest(50, v, LOGS, 0)
	eq(s.templateModel, 7)
	eq(s.preselected.delta, -1)
	eq(s.preselected.remove, { 1 })
	eq(s.preselected.rate, 0)
end)

-- suggestForCargos --------------------------------------------------------------------

test("multi-cargo: the cargo needing the most vehicles wins", function()
	local v = {}
	for i = 1, 2 do v[i] = { id = i, model = 7, capacities = { [GRAIN] = 20, [COAL] = 20 }, purchaseTime = i } end
	local s = model.suggestForCargos(60, v, { [GRAIN] = 90, [COAL] = 150 })
	eq(s.status, "ok")
	eq(s.cargo, COAL)
	eq(s.reason, "most_vehicles")
	eq(s.preselected.count, 5)
	eq(#s.perCargo, 2)
	eq(s.perCargo[1].cargo, GRAIN)
	eq(s.perCargo[1].preselected.count, 3)
end)

test("single cargo reason, empty targets, all failing", function()
	local s = model.suggestForCargos(66, ships(2), { [LOGS] = 101 })
	eq(s.reason, "single_cargo")
	eq(s.preselected.count, 3)
	eq(model.suggestForCargos(66, ships(2), {}).status, "invalid_target")
	s = model.suggestForCargos(0, ships(2), { [LOGS] = 101, [COAL] = 5 })
	eq(s.status, "no_rate")
	eq(s.cargo, LOGS)
end)

-- rankModels --------------------------------------------------------------------------

test("rankModels: estimate by capacity and speed, closest first, fewer vehicles on ties", function()
	local current = { model = 7, capacity = 20, speed = 10, perVehicle = 33 }
	local candidates = {
		{ model = 7, capacity = 20, speed = 10 },  -- current: skipped
		{ model = 11, capacity = 40, speed = 10 }, -- 66/veh: 2 -> 132 (diff 31) vs 1 -> 66 (diff 35)
		{ model = 12, capacity = 30, speed = 10 }, -- 49.5: 2 -> 99 (diff 2)
		{ model = 13, capacity = 20, speed = 15 }, -- 49.5 too: same diff, same count, higher id
		{ model = 14, capacity = 10, speed = 5 },  -- 8.25: 12 -> 99 (diff 2), more vehicles
		{ model = 15, capacity = 0, speed = 10 },  -- no capacity: skipped
		{ model = 16, capacity = 101, speed = 10 },-- 166.65: 1 -> diff 65.65
	}
	local r = model.rankModels(candidates, current, 101)
	eq(#r, 5)
	eq(r[1].model, 12)
	eq(r[1].count, 2)
	near(r[1].rate, 99, 1e-9)
	eq(r[2].model, 13)
	eq(r[3].model, 14)
	eq(r[3].count, 12)
	eq(r[4].model, 11)
	eq(r[4].count, 2)
	eq(r[5].model, 16)
	eq(r[5].count, 1)
	eq(#model.rankModels(candidates, current, 101, 2), 2)
end)

test("rankModels: bad current / target, count above MAX_MODEL_COUNT", function()
	local cands = { { model = 1, capacity = 1, speed = 1 } }
	eq(model.rankModels(cands, { capacity = 0, speed = 1, perVehicle = 1 }, 10), {})
	eq(model.rankModels(cands, { capacity = 1, speed = 1, perVehicle = 0 }, 10), {})
	eq(model.rankModels(cands, { capacity = 1, speed = 1, perVehicle = 1 }, 0), {})
	eq(model.rankModels(cands, { capacity = 1, speed = 1, perVehicle = 1 }, 1e6), {})
	local r = model.rankModels(cands, { model = 9, capacity = 1, speed = 1, perVehicle = 1 }, 0.3)
	eq(r[1].count, 1)
end)

-- pickSurplus ---------------------------------------------------------------------------

test("pickSurplus: newest first, id breaks ties, skips protected / selling / no capacity", function()
	local v = {
		ship(1, 7, 20, LOGS, 10),
		ship(2, 7, 20, LOGS, 30, { protected = true }),
		ship(3, 7, 20, LOGS, 20),
		ship(4, 7, 20, LOGS, 20),
		ship(5, 7, 20, LOGS, 40, { selling = true }),
		ship(6, 8, 30, GRAIN, 50),
		ship(7, 7, 20, LOGS, nil),
	}
	v[7].purchaseTime = nil
	eq(model.pickSurplus(v, nil, LOGS), { 4, 3, 1, 7 })
	eq(model.pickSurplus(v, 2, LOGS), { 4, 3 })
	eq(model.pickSurplus(v, 0, LOGS), {})
	eq(model.pickSurplus(v, 2), { 6, 4 })
end)

-- plans and costs -----------------------------------------------------------------------

local function costed(n, value, running, capital)
	local out = ships(n)
	for _, v in ipairs(out) do v.value, v.running, v.capital = value, running, capital end
	return out
end

test("modelPerVehicle and fleetRunning", function()
	local cur = { model = 7, capacity = 20, speed = 10, perVehicle = 33 }
	near(model.modelPerVehicle(cur, { model = 9, capacity = 60, speed = 5 }), 49.5)
	eq(model.modelPerVehicle(cur, { model = 9, capacity = 0, speed = 5 }), nil)
	eq(model.modelPerVehicle({ capacity = 20, speed = 10 }, { model = 9, capacity = 60, speed = 5 }), nil)
	eq(model.modelPerVehicle(nil, {}), nil)
	local vs = costed(3, 1000, 400)
	vs[3].selling = true
	vs[2].running = nil
	eq(model.fleetRunning(vs), 400, "selling and unknown vehicles are left out")
	eq(model.fleetRunning(ships(2)), nil)
	eq(model.fleetRunning({}), nil)
end)

test("plansFromSuggestion: clones and sells with purchase, refund, running, cost per year and per rate", function()
	local vs = costed(2, 30000, 5000, 2800)
	local s = model.suggest(66, vs, LOGS, 101)
	local plans = model.plansFromSuggestion(s, vs, { price = 70000, running = 6000, capital = 2800 })
	eq(#plans, 2)
	eq(plans[1].count, 3); eq(plans[1].buy, 1); eq(plans[1].suggested, true)
	eq(plans[1].price, 70000); eq(plans[1].refund, 0); eq(plans[1].net, 70000)
	eq(plans[1].running, 16000); eq(plans[1].capital, 3 * 2800); eq(plans[1].costYear, 16000 + 8400)
	near(plans[1].perRate, 24400 / 99, 1e-9, "per rate = this row's cost per year / this row's rate")
	eq(plans[2].count, 4); eq(plans[2].net, 140000); eq(plans[2].running, 22000); eq(plans[2].suggested, false)
	eq(plans[2].costYear, 22000 + 4 * 2800); near(plans[2].perRate, 33200 / 132, 1e-9)

	s = model.suggest(66, vs, LOGS, 20)
	plans = model.plansFromSuggestion(s, vs, { price = 70000, running = 6000, capital = 2800 })
	eq(#plans, 1, "below = above = the 1-ship floor")
	eq(plans[1].remove, { 102 }); eq(plans[1].price, 0); eq(plans[1].refund, 30000); eq(plans[1].net, -30000)
	eq(plans[1].running, 5000); eq(plans[1].costYear, 7800)

	eq(model.plansFromSuggestion(model.suggest(0, vs, LOGS, 101), vs, {}), {}, "no plans for a failed suggestion")
	eq(model.plansFromSuggestion(nil, vs, {}), {})
end)

test("planCost: unknown price or running, mixed fleet, selling vehicles ignored", function()
	local vs = costed(2, 30000, 5000)
	vs[3] = ship(103, 8, 40, LOGS, 3, { value = 50000, running = 9000 })
	vs[4] = ship(104, 7, 20, LOGS, 4, { value = 99999, running = 99999, selling = true })
	for i = 1, 2 do vs[i].capital = 1000 end
	vs[3].capital = 3000
	local p = model.planCost({ model = 7, switch = false, count = 4, delta = 1, rate = 120, buy = 1, remove = {}, replace = {} },
		vs, { price = nil, running = nil })
	eq(p.price, nil); eq(p.net, nil); eq(p.refund, 0)
	eq(p.running, 5000 + 5000 + 9000 + 5000, "clone running = mean of the fleet model's vehicles")
	eq(p.capital, 1000 + 1000 + 3000 + 1000, "clone capital = mean of the fleet model's vehicles")
	near(p.perRate, (24000 + 6000) / 120)
	-- one kept vehicle without a known capital: no cost per year, no per rate (running still known)
	vs[3].capital = nil
	p = model.planCost({ model = 7, switch = false, count = 4, delta = 1, rate = 120, buy = 1, remove = {}, replace = {} },
		vs, { price = 1, running = 1, capital = 1 })
	eq(p.running, 5000 + 5000 + 9000 + 1); eq(p.capital, nil); eq(p.costYear, nil); eq(p.perRate, nil)
	vs[3].capital = 3000
	-- a switch: everything that leaves is refunded, new running x count
	p = model.planCost({ model = 9, switch = true, count = 2, delta = -1, rate = 0, buy = 0, remove = { 103 }, replace = { 101, 102 } },
		vs, { price = 100000, running = 7000, capital = 4000 })
	eq(p.price, 200000); eq(p.refund, 110000); eq(p.net, 90000); eq(p.running, 14000)
	eq(p.capital, 8000, "a switch counts only the new model's vehicles"); eq(p.costYear, 22000)
	eq(p.perRate, nil, "rate 0: no per-rate figure")
	-- a switch with an unknown new running cost
	p = model.planCost({ model = 9, switch = true, count = 3, delta = 0, rate = 90, buy = 0, remove = {}, replace = { 101, 102, 103 } },
		vs, { price = 100000 })
	eq(p.running, nil); eq(p.perRate, nil)
	eq(model.planCost(nil, vs, {}), nil)
end)

test("capitalPerYear: price over the lifespan in calendar years", function()
	-- Sydfart: 548,640, lifespan 36525 (x 1000 game ms), default year 1,460,000 ms: 25.0 years -> 21,931/yr
	near(model.capitalPerYear(548640, 36525000, 1460000), 548640 / (36525 / 1460), 1e-6)
	-- a slower calendar (longer year in game ms) means fewer calendar years of life: more per year
	near(model.capitalPerYear(1000, 10000, 2000), 200)
	eq(model.capitalPerYear(nil, 1, 1), nil)
	eq(model.capitalPerYear(1, 0, 1), nil)
	eq(model.capitalPerYear(1, 1, 0), nil)
	eq(model.capitalPerYear(-1, 1, 1), nil)
	eq(model.capitalPerYear(0, 10, 1), 0)
end)

test("loadShare: time at stops from section and drive times", function()
	near(model.loadShare({ 60, 40 }, { 45, 25 }), 0.3)
	eq(model.loadShare({ 50 }, { 50 }), 0, "drives only")
	eq(model.loadShare({ 100 }, { 1 }), model.MAX_LOAD_SHARE, "clamped")
	eq(model.loadShare({}, {}), nil)
	eq(model.loadShare({ 10 }, { 20 }), nil, "drive longer than the section: not what we think it is")
	eq(model.loadShare({ 10 }, { 0 }), nil)
	eq(model.loadShare({ 10, -1 }, { 5 }), nil)
	eq(model.loadShare(nil, { 5 }), nil)
end)

test("modelPerVehicle with time at stops: exact for the current model, slower big loaders", function()
	-- WC Logs-like: Sydfart 80 @ 8.33 m/s, loadSpeed 20; 33 per ship; 30 % of the round trip at stops
	local cur = { model = 1, capacity = 80, speed = 8.3333, loadSpeed = 20, perVehicle = 33, loadShare = 0.3 }
	near(model.modelPerVehicle(cur, { model = 1, capacity = 80, speed = 8.3333, loadSpeed = 20 }), 33, 1e-9)
	-- Sternwheeler 120 @ 11.11 m/s, loadSpeed 10: drive 0.7 x 0.75, stops 0.3 x (12 / 4) = 1.425 -> 33 x 1.5 / 1.425
	local stern = { model = 2, capacity = 120, speed = 11.1111, loadSpeed = 10 }
	near(model.modelPerVehicle(cur, stern), 33 * 1.5 / (0.7 * 8.3333 / 11.1111 + 0.3 * 3), 1e-9)
	-- without the split (or a load speed) it is the capacity x speed scaling
	local noShare = { model = 1, capacity = 80, speed = 8.3333, loadSpeed = 20, perVehicle = 33 }
	near(model.modelPerVehicle(noShare, stern), 33 * 1.5 * 11.1111 / 8.3333, 1e-9)
	near(model.modelPerVehicle(cur, { model = 2, capacity = 120, speed = 11.1111 }), 33 * 1.5 * 11.1111 / 8.3333, 1e-9)
	-- rankModels uses the same estimate
	local r = model.rankModels({ stern }, cur, 101)
	near(r[1].perVehicle, model.modelPerVehicle(cur, stern), 1e-9)
	eq(r[1].count, 3)
end)

test("bestByPerRate: the lowest per rate (with a small tolerance); nothing on a tie or unknowns", function()
	eq(model.bestByPerRate({ { perRate = 100 }, { perRate = 90 }, { perRate = 120 } }), { [2] = true })
	eq(model.bestByPerRate({ { perRate = 100 }, { perRate = 100.2 }, { perRate = 120 } }), { [1] = true, [2] = true })
	eq(model.bestByPerRate({ { perRate = 2771 }, { perRate = 2771 }, { perRate = 2771 } }), {}, "all equal: no tag")
	eq(model.bestByPerRate({ { perRate = 100 }, {} }), {}, "a single known row")
	eq(model.bestByPerRate({}), {})
	eq(model.bestByPerRate(nil), {})
end)

test("switchPlans: floor / ceil counts, rankModels' pick, newest sold first, buys beyond the fleet", function()
	local vs = costed(2, 30000, 5000)
	-- 49.5 each, target 101: 2 (99, diff 2) beats 3 (148.5)
	local plans, why = model.switchPlans(9, 49.5, 101, vs, { price = 100000, running = 7000 })
	eq(why, nil)
	eq(#plans, 2)
	eq(plans[1].count, 2); eq(plans[1].suggested, true); eq(plans[1].replace, { 102, 101 }); eq(plans[1].remove, {})
	eq(plans[1].buy, 0); eq(plans[1].delta, 0); near(plans[1].rate, 99); near(plans[1].diff, -2)
	eq(plans[1].net, 200000 - 60000); eq(plans[1].running, 14000)
	eq(plans[2].count, 3); eq(plans[2].buy, 1); eq(plans[2].delta, 1); eq(plans[2].replace, { 102, 101 })
	eq(plans[2].net, 300000 - 60000); eq(plans[2].running, 21000)
	-- a bigger model: one is enough, the newer old ship is sold, the older replaced
	plans = model.switchPlans(9, 200, 101, vs, { price = 1, running = 1 })
	eq(#plans, 1); eq(plans[1].count, 1); eq(plans[1].remove, { 102 }); eq(plans[1].replace, { 101 })
	-- the same pick as rankModels
	local ranked = model.rankModels({ { model = 9, capacity = 30, speed = 10 } }, { model = 7, capacity = 20, speed = 10, perVehicle = 33 }, 101)
	plans = model.switchPlans(9, ranked[1].perVehicle, 101, vs, {})
	local pick
	for _, p in ipairs(plans) do if p.suggested then pick = p end end
	eq(pick.count, ranked[1].count)
	eq(pick.net, nil, "unknown price")
	-- refusals
	local protected = costed(2, 1, 1)
	protected[1].protected = true
	eq({ model.switchPlans(9, 50, 101, protected, {}) }, { {}, "protected" })
	eq({ model.switchPlans(9, 50, 101, {}, {}) }, { {}, "no_vehicles" })
	eq({ model.switchPlans(9, 0, 101, vs, {}) }, { {}, "invalid" })
	eq({ model.switchPlans(9, 50, 0, vs, {}) }, { {}, "invalid" })
	eq(#model.switchPlans(9, 0.5, 101, vs, {}), 0, "more than MAX_MODEL_COUNT vehicles")
	-- selling vehicles are not part of the fleet that is switched
	local selling = costed(3, 10, 10)
	selling[3].selling = true
	plans = model.switchPlans(9, 50, 100, selling, {})
	eq(plans[1].count, 2); eq(plans[1].replace, { 102, 101 })
end)
