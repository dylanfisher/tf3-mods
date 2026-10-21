-- rate_matcher_view: the popup's view model and texts. WC Logs numbers from the 2026-10-10 probe
-- (docs/findings.md "Line Rate, cloning onto a line, sell on arrival"): 2 ships, Rate 66, logging camp max 101,
-- so 3 ships ≈ 99 (preselected) and 4 ships ≈ 132.

local view = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_view.tl"

local PASSENGER, LOGS, GRAIN = 0, 4, 3

local function set(...)
	local s = {}
	for _, c in ipairs({ ... }) do s[c] = true end
	return s
end

local function ships(n, cap, cargo)
	local out = {}
	for i = 1, n do
		out[i] = { id = 100 + i, model = 7, capacities = { [cargo or LOGS] = cap or 20 }, purchaseTime = i,
			value = 30000, running = 5000, capital = 2800 }
	end
	return out
end

local function wcLogs(rate, n)
	return {
		line = 1,
		rate = rate or 66,
		vehicles = ships(n or 2),
		passengerCargo = PASSENGER,
		supply = {
			line = 1,
			passengerCargo = PASSENGER,
			stops = {
				{ stationGroup = 10, loads = set(LOGS), producers = {
					{ stockList = 500, cargo = LOGS, maxPerYear = 101, producedPerYear = 112 },
				} },
				{ stationGroup = 20, loads = set(), producers = {} },
			},
			otherLines = {
				{ line = 2, rate = 103, stops = { { stationGroup = 10, loads = set(PASSENGER) } } },
			},
		},
	}
end

local function passengerLine()
	return {
		line = 3,
		rate = 103,
		vehicles = ships(2, 20, PASSENGER),
		passengerCargo = PASSENGER,
		supply = {
			line = 3,
			passengerCargo = PASSENGER,
			stops = {
				{ stationGroup = 30, loads = set(PASSENGER), producers = {} },
				{ stationGroup = 31, loads = set(PASSENGER), producers = {} },
			},
			otherLines = {},
		},
	}
end

test("number formatting and placeholders", function()
	eq(view.fmt(98.5), "99")
	eq(view.fmt(nil), "?")
	eq(view.fmt(0 / 0), "?")
	eq(view.fmtPer(33), "33")
	eq(view.fmtPer(33.4), "33")
	eq(view.fmtPer(2.46), "2.5")
	eq(view.fmtPer(3.0), "3")
	eq(view.fill("{a} of {b} {c}", { a = 1, b = "x" }), "1 of x {c}")
	eq(view.clampTarget(100.6), 101)
	eq(view.clampTarget(-5), 0)
	eq(view.clampTarget("x"), nil)
	eq(view.clampTarget(1e12), view.MAX_TARGET)
end)

-- models: 7 = the fleet's ship; 9 carries 3x (one ≈ 99); 11 is twice as fast (≈ 66 each)
local INFO = {
	[7] = { model = 7, name = "Small Ship", capacity = 20, speed = 10, price = 70000, running = 6000, capital = 2800, available = true },
	[9] = { model = 9, name = "Big Ship", capacity = 60, speed = 10, price = 200000, running = 15000, capital = 8000, available = true },
	[11] = { model = 11, name = "Fast Ship", capacity = 20, speed = 20, price = 90000, running = 8000, capital = 3600, available = true },
}

local function input(o)
	o = o or {}
	return {
		selectedModel = o.model,
		selectedCount = o.count,
		catalogue = o.catalogue ~= false and (o.catalogue or { INFO[7], INFO[9], INFO[11] }) or nil,
		catalogueWhy = o.why,
		infoOf = function(m) return INFO[m] end,
		clonePrice = o.clonePrice,
	}
end

local function dollars(m) return "$" .. tostring(m) end

test("parseTarget: digits of the typed text, clamped", function()
	eq(view.parseTarget("101"), 101)
	eq(view.parseTarget("0099"), 99)
	eq(view.parseTarget("1a2"), 12)
	eq(view.parseTarget(""), nil)
	eq(view.parseTarget(nil), nil)
	eq(view.parseTarget("99999999999999"), view.MAX_TARGET)
end)

test("WC Logs: suggested target 101, fleet plans 3 ≈ 99 (suggested) and 4 ≈ 132 with costs", function()
	local data = wcLogs()
	local supply = view.supplyView(data)
	eq(supply.kind, "cargo")
	eq(supply.cargo, LOGS)
	eq(supply.suggested, 101)
	eq(supply.reason, "single_cargo")
	eq(view.defaultTarget(data, supply), 101)

	local v = view.build(data, supply, 101, input())
	eq(v.status, "ok")
	eq(v.count, 2)
	near(v.perVehicle, 33)
	eq(v.fleetRunning, 10000)
	eq(v.templateVehicle, 102, "newest ship is the template")
	eq(v.selectedModel, v.models[1])
	eq(v.models[1].current, true); eq(v.models[1].name, "Small Ship")
	eq(#v.plans, 2)
	local p3, p4 = v.plans[1], v.plans[2]
	eq(p3.count, 3); eq(p3.delta, 1); eq(p3.buy, 1); near(p3.rate, 99); eq(p3.suggested, true); eq(p3.switch, false)
	eq(p3.price, 70000); eq(p3.refund, 0); eq(p3.net, 70000); eq(p3.running, 16000)
	eq(p3.capital, 8400); eq(p3.costYear, 24400); near(p3.perRate, 24400 / 99)
	eq(p4.count, 4); near(p4.rate, 132); eq(p4.net, 140000); eq(p4.running, 22000); eq(p4.suggested, false)
	eq(p4.costYear, 33200); near(p4.perRate, 33200 / 132)
	eq(v.selected, p3)
	eq(view.planCells(p3, dollars), { "3", "+1", "99", "$70000", "$24400", "$246" })
	eq(view.planCells(p4, dollars), { "4", "+2", "132", "$140000", "$33200", "$252" }, "per rate from the row's own numbers")
	eq(view.costTip(p3, dollars), "Running costs $16000/yr\n+ purchase prices spread over the lifespan $8400/yr")
	local stats = view.statsCells(v, data, dollars)
	eq(#stats, 4)
	eq({ stats[1].title, stats[1].value, stats[2].value, stats[3].value, stats[4].value },
		{ "Rate", "66/yr", "2", "33/yr", "$10000" })
	eq(stats[4].title, "Running costs per year")
	ok(stats[4].tip:find("\n") ~= nil)
	eq(view.costTip({ running = 1 }, dollars), nil)
	eq(view.planActionText(p3, "Small Ship"), "Buys 1 copy of the line's vehicle for this line.")
	eq(view.planActionText(p4, "Small Ship"), "Buys 2 copies of the line's vehicle for this line.")
	eq(view.statusText(v), nil)
	eq(view.summaryText(v, data, dollars), "Rate 66/yr · 2 vehicles · 33 each · running $10000/yr")
	-- a clone price from the template overrides the catalogue price
	eq(view.build(data, supply, 101, input({ clonePrice = 1000 })).plans[1].net, 1000)
end)

test("compare models: other models as whole-fleet switches, ranked by distance to the target", function()
	local data = wcLogs()
	local supply = view.supplyView(data)
	local v = view.build(data, supply, 101, input())
	eq(#v.models, 3)
	eq(v.modelsWhy, nil)
	local big, fast = v.models[2], v.models[3]
	eq(big.model, 9); eq(big.current, false); eq(view.modelName(big), "Big Ship")
	eq(view.modelName(v.models[1]), "Small Ship (current)")
	-- Big Ship ≈ 99 each: 1 (≈ 99) beats 2 (≈ 198)
	eq(big.plan.count, 1); near(big.plan.rate, 99); eq(big.plan.switch, true)
	eq(big.plan.replace, { 101 }); eq(big.plan.remove, { 102 }, "the newest old ship is sold"); eq(big.plan.buy, 0)
	eq(big.plan.price, 200000); eq(big.plan.refund, 60000); eq(big.plan.net, 140000); eq(big.plan.running, 15000)
	eq(big.plan.costYear, 23000); near(big.plan.perRate, 23000 / 99)
	-- Fast Ship ≈ 66 each: 2 (≈ 132) beats 1 (≈ 66)
	eq(fast.model, 11); eq(fast.plan.count, 2); near(fast.plan.rate, 132)
	eq(fast.plan.replace, { 102, 101 }); eq(fast.plan.remove, {}); eq(fast.plan.net, 180000 - 60000)
	near(fast.plan.perRate, 2 * (8000 + 3600) / 132)
	-- "best": the lowest cost per year per Rate (Fast Ship 176 vs Big 232 vs current 246)
	eq(fast.best, true); eq(big.best, nil); eq(v.models[1].best, nil)

	-- select Big Ship: its plans become the option rows
	v = view.build(data, supply, 101, input({ model = 9 }))
	eq(v.selectedModel.model, 9)
	eq(#v.plans, 2)
	eq(v.selected.count, 1)
	eq(view.planCells(v.selected, dollars), { "1", "-1", "99", "$140000", "$23000", "$232" })
	eq(view.planActionText(v.selected, "Big Ship"), "Replaces every vehicle with Big Ship and sells the rest: 1 in total.")
	v = view.build(data, supply, 101, input({ model = 9, count = 2 }))
	eq(v.selected.count, 2); eq(v.selected.buy, 0); eq(v.selected.replace, { 102, 101 })
	eq(view.planActionText(v.selected, "Big Ship"), "Replaces every vehicle with Big Ship: 2 in total.")
	v = view.build(data, supply, 200, input({ model = 11 }))
	eq(v.selected.count, 3); eq(v.selected.buy, 1)
	eq(view.planActionText(v.selected, "Fast Ship"), "Replaces every vehicle with Fast Ship and buys more: 3 in total.")
	-- a model that is no longer listed: back to the fleet's model
	eq(view.build(data, supply, 101, input({ model = 404 })).selectedModel.current, true)
end)

test("compare models: the line's time at stops and load speeds change the estimate", function()
	local data = wcLogs()
	local supply = view.supplyView(data)
	local loadInfo = {
		[7] = setmetatable({ loadSpeed = 10 }, { __index = INFO[7] }),
		[9] = setmetatable({ loadSpeed = 10 }, { __index = INFO[9] }),
	}
	local inp = input({ catalogue = { loadInfo[7], loadInfo[9] } })
	inp.infoOf = function(m) return loadInfo[m] end
	-- no split known: capacity scaling only (Big Ship ≈ 99 each)
	near(view.build(data, supply, 101, inp).models[2].plan.rate, 99)
	-- half the round trip at stops: 3x the cargo takes 3x as long there -> 33 x 3 / (0.5 + 1.5) = 49.5 each, so 2
	data.timing = { loadShare = 0.5 }
	local big = view.build(data, supply, 101, inp).models[2]
	eq(big.plan.count, 2); near(big.plan.rate, 99)
	near(big.plans[1].rate / big.plans[1].count, 49.5)
	-- the fleet's own model is unaffected (its Rate is measured)
	near(view.build(data, supply, 101, inp).plans[1].rate, 99)
end)

test("compare models: mission vehicles block a switch; hints without a catalogue", function()
	local data = wcLogs()
	data.vehicles[1].protected = true
	local supply = view.supplyView(data)
	local v = view.build(data, supply, 101, input())
	eq(#v.models, 1)
	eq(v.modelsWhy, "protected")
	eq(view.modelsHint(v.modelsWhy), "No model switch: the line has mission vehicles.")

	data = wcLogs()
	v = view.build(data, supply, 101, input({ catalogue = false, why = "multi_part" }))
	eq(#v.models, 1); eq(v.modelsWhy, "multi_part")
	eq(view.modelsHint("multi_part"), "No model suggestions for trains and multiple units.")
	eq(view.modelsHint(nil), "No other buyable model carries this cargo.")
	v = view.build(data, supply, 101, input({ catalogue = {} }))
	eq(v.modelsWhy, "none")
	-- target 0: no switch suggestions
	eq(#view.build(data, supply, 0, input()).models, 1)
end)

test("the selection is kept by count and falls back to the suggestion", function()
	local data = wcLogs()
	local supply = view.supplyView(data)
	eq(view.build(data, supply, 101, input({ count = 4 })).selected.count, 4)
	eq(view.build(data, supply, 101, input({ count = 5 })).selected.count, 3)
	local noInfo = view.build(data, supply, 101, { })
	eq(noInfo.plans[1].net, nil, "no price, no cost")
	eq(noInfo.plans[1].running, 16000 - 6000 + 5000, "unknown new running: kept known + clone like the fleet")
	eq(view.planCells(noInfo.plans[1], dollars)[4], "?")
	eq(view.pickPlan({}, 1), nil)
end)

test("a typed target recomputes: sell plans with refunds and an exact hit", function()
	local data = wcLogs()
	local supply = view.supplyView(data)
	local v = view.build(data, supply, 33, input())
	eq(#v.plans, 1, "1 ship hits 33 exactly: one plan")
	local p = v.plans[1]
	eq(p.delta, -1); eq(p.count, 1); eq(p.remove, { 102 }); eq(p.price, 0); eq(p.refund, 30000); eq(p.net, -30000)
	eq(p.running, 5000)
	eq(view.planCells(p, dollars), { "1", "-1", "33", "$-30000", "$7800", "$236" })
	eq(view.planActionText(p, "x"), "Sells the newest vehicle at once.")

	v = view.build(wcLogs(99, 3), view.supplyView(wcLogs(99, 3)), 40, input())
	eq(v.plans[1].count, 1); eq(v.plans[2].count, 2)
	eq(view.planActionText(v.plans[1], "x"), "Sells the 2 newest vehicles at once.")

	v = view.build(data, supply, 66, input())
	eq(#v.plans, 1)
	eq(v.plans[1].delta, 0)
	eq(view.planCells(v.plans[1], dollars), { "2", "=", "66", "–", "$15600", "$236" })
	eq(view.planActionText(nil, "x"), "Nothing to change.")
end)

test("passenger line: no supply target, box starts at the current Rate", function()
	local data = passengerLine()
	local supply = view.supplyView(data)
	eq(supply.kind, "passenger")
	eq(supply.cargo, PASSENGER)
	eq(supply.suggested, nil)
	eq(view.defaultTarget(data, supply), 103)
	eq(view.supplyLines(supply, nil), { "No supply target for passengers: type a target." })
	local v = view.build(data, supply, 103, input({ catalogue = false, why = "multi_part" }))
	eq(v.status, "ok")
	eq(v.plans[1].delta, 0)
	v = view.build(data, supply, 160, input({ catalogue = false, clonePrice = 500 }))
	eq(v.selected.count, 3); eq(v.selected.net, 500)
end)

test("no producer in reach, and a guessed cargo the vehicles don't carry", function()
	local data = wcLogs()
	data.supply.stops[1].producers = {}
	local supply = view.supplyView(data)
	eq(supply.kind, "no_producer")
	eq(supply.cargo, LOGS)
	eq(view.defaultTarget(data, supply), 66)
	eq(view.supplyLines(supply, nil), { "No producer in reach where this line loads: type a target." })

	-- loads grain, vehicles only carry logs: options fall back to equal shares
	data.supply.stops[1].loads = set(GRAIN)
	supply = view.supplyView(data)
	eq(supply.cargo, GRAIN)
	local v = view.build(data, supply, 101, input())
	eq(v.status, "ok"); eq(v.cargo, nil); eq(v.selected.count, 3)

	data.supply.stops[1].loads = set()
	supply = view.supplyView(data)
	eq(supply.kind, "none")
	eq(view.supplyLines(supply, nil), { "This line loads nothing: type a target." })
end)

test("supply lines: max, measured hint, other lines, unsupplied cargo, the deciding cargo", function()
	local data = wcLogs()
	data.supply.otherLines[#data.supply.otherLines + 1] =
		{ line = 4, rate = 30, stops = { { stationGroup = 10, loads = set(LOGS) } } }
	data.supply.stops[1].loads = set(LOGS, GRAIN)
	local supply = view.supplyView(data)
	eq(supply.suggested, 71)
	local names = { [LOGS] = "Logs", [GRAIN] = "Grain" }
	eq(view.supplyLines(supply, function(c) return names[c] end), {
		"Logs in reach: up to 101/yr · measured 112 · other lines take 30",
		"Grain: no producer in reach",
	})
	supply.reason = "most_vehicles"
	local lines = view.supplyLines(supply, function(c) return names[c] end)
	eq(lines[#lines], "The target follows Logs: it needs the most vehicles.")
	supply.targets[1].produced = nil
	eq(view.supplyLines(supply, nil)[1], "4 in reach: up to 101/yr · other lines take 30")
end)

test("status texts and the summary for 0 or 1 vehicles", function()
	local data = wcLogs()
	data.vehicles = {}
	local v = view.build(data, view.supplyView(data), 101, input())
	eq(v.status, "no_vehicles")
	eq(view.statusText(v), "This line has no vehicles to copy.")
	eq(view.summaryText(v, data, dollars), "Rate 66/yr · no vehicles")
	data = wcLogs(0, 2)
	v = view.build(data, view.supplyView(data), 101, input())
	eq(v.status, "no_rate")
	data = wcLogs(33, 1)
	v = view.build(data, view.supplyView(data), 101, input())
	eq(view.summaryText(v, data, dollars), "Rate 33/yr · 1 vehicle · running $5000/yr")
	data.vehicles[1].running = nil
	v = view.build(data, view.supplyView(data), 101, input())
	eq(view.summaryText(v, data, nil), "Rate 33/yr · 1 vehicle")
	eq(view.statusText(nil), "No line selected.")
	-- capped: even MAX_ADD clones stay below
	data = wcLogs(1, 1)
	v = view.build(data, view.supplyView(data), 100000, input({ catalogue = false }))
	eq(v.capped, true)
	eq(view.statusText(v), "Even 100 more vehicles stay below the target.")
end)

test("result messages after Apply", function()
	local function res(status, done, requested, reasons, message)
		return { status = status, done = done, requested = requested, reasons = reasons or {}, message = message }
	end
	eq({ view.resultText("clone", res("ok", { 1, 2 }, 2)) }, { "Bought 2 vehicles for this line.", false })
	eq({ view.resultText("clone", res("ok", { 1 }, 1)) }, { "Bought 1 vehicle for this line.", false })
	eq({ view.resultText("clone", res("partial", { 1 }, 3, { not_enough_money = 2 })) },
		{ "Bought 1 of 3 vehicles: not enough money for the rest.", true })
	eq({ view.resultText("clone", res("failed", {}, 1, { not_enough_money = 1 })) },
		{ "Not enough money to buy a vehicle.", true })
	eq({ view.resultText("clone", res("failed", {}, 1, { mission = 1 }, "No ships yet")) },
		{ "The mission does not allow this: No ships yet", true })
	eq({ view.resultText("clone", res("failed", {}, 1, { no_depot = 1 })) }, { "No depot found for this line.", true })
	eq({ view.resultText("clone", res("failed", {}, 1, { set_line_failed = 1 })) },
		{ "The vehicles were bought but could not join the line; they wait in the depot.", true })
	eq({ view.resultText("sell", res("ok", { 5 }, 1)) }, { "Sold 1 vehicle.", false })
	eq({ view.resultText("sell", res("ok", { 5, 6 }, 2)) }, { "Sold 2 vehicles.", false })
	eq({ view.resultText("sell", res("partial", { 5 }, 2, { protected = 1 })) },
		{ "Sold 1 of 2 vehicles.", true })
	eq({ view.resultText("sell", res("failed", {}, 1, { sell_failed = 1 })) },
		{ "Could not sell the vehicles.", true })
	eq({ view.resultText("clone", nil) }, { "Nothing was changed.", true })
	local sw = { status = "ok", done = { 1, 2, 3 }, requested = 3, reasons = {}, replaced = { 1 }, bought = { 2 }, sold = { 3 } }
	eq({ view.resultText("switch", sw, "Big Ship") },
		{ "Switched to Big Ship: 1 replaced, 1 bought, 1 sold.", false })
	sw.status = "partial"
	eq({ view.resultText("switch", sw, "Big Ship") },
		{ "Switched in part to Big Ship: 1 replaced, 1 bought, 1 sold.", true })
	eq({ view.resultText("switch", res("failed", {}, 2, { not_enough_money = 2 }), "X") },
		{ "Not enough money for this switch.", true })
	eq({ view.resultText("switch", res("failed", {}, 2, { mission = 2 }, "No")) },
		{ "The mission does not allow this: No", true })
	eq({ view.resultText("switch", res("failed", {}, 2, { replace_failed = 2 })) },
		{ "Could not switch the model (see the game log).", true })
end)

-- a line with no vehicles ---------------------------------------------------------------------------
-- Route 6072 m, 2 stops, line 124996's times (docs/findings/lines-vehicles.md): a 20-log ship at 8.33 m/s makes
-- 29.2/yr, a 50-log one 72.9/yr.
local function emptyEstimate(o)
	o = o or {}
	return { line = 1, depot = 300, cargo = LOGS, distance = 6072, stops = 2, yearSeconds = 1460,
		times = o.times or { carrier = "water", detour = 955.2 / (6072 / 8.3333), dwell = (1001 - 955.2) / 2, n = 5, fallback = false },
		catalogue = o.catalogue or {
			{ model = 3, name = "Small Ship", capacity = 20, speed = 8.3333, price = 1000, running = 500, capital = 100 },
			{ model = 4, name = "Big Ship", capacity = 50, speed = 8.3333, price = 1000, running = 600, capital = 100 },
		} }
end

local function emptyLine()
	local data = wcLogs(0)
	data.vehicles = {}
	return data
end

test("no vehicles: the estimate's rows, the cheapest per unit preselected and best; a selection by model", function()
	local data = emptyLine()
	local supply = view.supplyView(data)
	local inp = input({ catalogue = false })
	inp.empty = emptyEstimate()
	local v = view.build(data, supply, 101, inp)
	eq(v.status, "estimate")
	eq(v.count, 0)
	eq(#v.models, 2)
	-- closest first: 3 x 29.2 = 87.5 (diff 13.5) before 1 x 72.9 (diff 28.1)
	eq({ v.models[1].name, v.models[1].plan.count, v.models[2].name, v.models[2].plan.count }, { "Small Ship", 3, "Big Ship", 1 })
	-- per unit: Small 3 x 600 / 87.5 = 20.6, Big 700 / 72.9 = 9.6: Big is preselected and best
	local cheapest = v.models[2]
	eq(v.selectedModel, cheapest)
	eq({ v.models[1].best, cheapest.best }, { nil, true })
	eq(v.selected, cheapest.plan)
	eq(v.selected.fresh, true)
	eq(view.statusText(v), nil)
	-- the other row by model
	local other = v.models[1]
	inp.selectedModel = other.model
	v = view.build(data, supply, 101, inp)
	eq(v.selectedModel.model, other.model)
	eq(v.selected.model, other.model)
	eq(view.planActionText(v.selected, "Small Ship"), "Buys " .. v.selected.count .. " new vehicles (Small Ship) for this line.")
	eq(view.planActionText({ fresh = true, count = 1, delta = 1 }, "Big Ship"), "Buys 1 new vehicle (Big Ship) for this line.")
end)

test("no vehicles: target 0, nothing within reach, and why there is no estimate", function()
	local data = emptyLine()
	local supply = view.supplyView(data)
	local inp = input({ catalogue = false })
	inp.empty = emptyEstimate()
	local v = view.build(data, supply, 0, inp)
	eq(v.status, "estimate_target")
	eq(view.statusText(v), "Type a target above 0 for a suggestion.")
	eq(v.empty, inp.empty, "the note still shows the route")
	inp.empty = emptyEstimate({ catalogue = { { model = 3, name = "Tiny", capacity = 1, speed = 1, price = 1 } } })
	v = view.build(data, supply, 5000, inp)
	eq(v.status, "estimate_none")
	eq(view.statusText(v), "No model reaches the target with at most 100 vehicles.")
	inp.empty = nil
	local reasons = {
		[false] = "This line has no vehicles to copy.",
		rail = "No estimate for a train line without trains: buy its first train in the vehicle store.",
		no_depot = "No estimate: no depot reaches this line.",
		no_positions = "No estimate: the positions of this line's stops could not be read.",
		few_stops = "No estimate: the line needs at least 2 stops in different places.",
		too_many_stops = "No estimate: this line has too many stops.",
		no_cargo = "No estimate: this line loads nothing yet.",
		no_models = "No estimate: no buyable model carries this line's cargo.",
		["read: boom"] = "No estimate for this line (see the game log).",
	}
	for why, text in pairs(reasons) do
		inp.emptyWhy = why or nil
		v = view.build(data, supply, 101, inp)
		eq(v.status, "no_vehicles")
		eq(view.statusText(v), text, tostring(why))
	end
end)

test("estimate note: route and where the times come from", function()
	local e = emptyEstimate()
	eq(view.estimateNote(e), "Estimated from the route: 6.1 km round trip, 2 stops. Times from 5 other ship lines.")
	e.distance = 23456
	e.times = { carrier = "water", detour = 1.5, dwell = 25, n = 1, fallback = true }
	eq(view.estimateNote(e), "Estimated from the route: 23 km round trip, 2 stops. Typical ship times.")
	local cases = {
		{ "road", false, "Times from 5 other road vehicle lines." }, { "road", true, "Typical road vehicle times." },
		{ "tram", false, "Times from 5 other tram lines." }, { "tram", true, "Typical tram times." },
		{ "air", false, "Times from 5 other aircraft lines." }, { "air", true, "Typical aircraft times." },
		{ "other", true, "Typical road vehicle times." },
	}
	for _, c in ipairs(cases) do
		e.times = { carrier = c[1], n = 5, fallback = c[2] }
		eq(view.estimateNote(e), "Estimated from the route: 23 km round trip, 2 stops. " .. c[3])
	end
	e.times = nil
	eq(view.estimateNote(e), "Estimated from the route: 23 km round trip, 2 stops.")
	eq(view.estimateNote(nil), nil)
end)

test("result messages after buying onto an empty line", function()
	local function res(status, done, requested, reasons)
		return { status = status, done = done, requested = requested, reasons = reasons or {}, bought = done }
	end
	eq({ view.resultText("buy", res("ok", { 1, 2 }, 2)) }, { "Bought 2 vehicles for this line.", false })
	eq({ view.resultText("buy", res("ok", { 1 }, 1)) }, { "Bought 1 vehicle for this line.", false })
	eq({ view.resultText("buy", res("failed", {}, 3, { not_enough_money = 3 })) }, { "Not enough money for these vehicles.", true })
	eq({ view.resultText("buy", res("failed", {}, 3, { no_depot = 3 })) }, { "No depot found for this line.", true })
	eq({ view.resultText("buy", res("partial", { 1 }, 2, { set_line_failed = 1 })) },
		{ "Bought 1 of 2 vehicles; the others could not join the line and wait in the depot.", true })
end)
