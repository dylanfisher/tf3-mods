-- radar_fleet_model: the pure model behind the rev 6 fleet window (plans/square_problem_radar/FLEET_UPGRADE.md).
-- Raw polls are faked; shape: radar_types.d.tl ProblemRadarFleetRaw.

local model = ug_require "square_problem_radar::/radar/gui/radar_fleet_model.tl"

local YEAR = 1000 -- ms per year in these tests

local function veh(entity, key, ageYears, lifeYears, condition)
	return { entity = entity, key = key, ageMs = ageYears and math.floor(ageYears * YEAR) or nil,
		lifespanMs = lifeYears and lifeYears * YEAR or 0, condition = condition }
end

local function raw(vehicles, extra)
	local r = { vehicle = vehicles[1] and vehicles[1].entity or 1, line = 500, vehicles = vehicles,
		names = { A = "Bus A", B = "Bus B" }, yearMs = YEAR, wornAt = 0.5, multiUnit = false,
		used = 30, capacity = 120, intervalS = 95, transported = 4000, balance = 1000, running = -3000,
		maintenance = -1000 }
	-- false = remove the field (a nil in the override table would not)
	for k, v in pairs(extra or {}) do if v == false then r[k] = nil else r[k] = v end end
	return r
end

local function groupKeys(view)
	local out = {}
	for i, g in ipairs(view.groups) do out[i] = g.key end
	return out
end

-- composition key / name -------------------------------------------------------

test("compositionKey: model id -> count map, order-independent", function()
	eq(model.compositionKey({ 7 }), "7x1")
	eq(model.compositionKey({ 12, 3, 3, 3 }), "3x3,12x1")
	eq(model.compositionKey({ 3, 12, 3, 3 }), model.compositionKey({ 12, 3, 3, 3 }))
	ok(model.compositionKey({ 3, 12 }) ~= model.compositionKey({ 3, 3, 12 }), "counts matter")
	eq(model.compositionKey({}), "")
	eq(model.compositionKey(nil), "")
end)

test("compositionName: first-appearance order, counts for repeats, id for unnamed", function()
	local names = { [1] = "Loco", [2] = "Wagon" }
	local nameOf = function(id) return names[id] end
	eq(model.compositionName({ 1, 2, 2, 2 }, nameOf), "Loco + 3× Wagon")
	eq(model.compositionName({ 2, 1, 2 }, nameOf), "2× Wagon + Loco")
	eq(model.compositionName({ 9 }, nameOf), "#9")
	eq(model.compositionName({}, nameOf), "")
end)

-- gone / no line ---------------------------------------------------------------

test("nil and gone polls give a gone view with no actions", function()
	for _, r in ipairs({ false, true }) do
		local v = model.build(r and { vehicle = 3, gone = true } or nil)
		eq(v.gone, true)
		eq(v.groups, {})
		eq(v.count, 0)
		eq(v.oldVehicles, nil)
		eq(v.fleetVehicles, nil)
	end
	eq(model.build({ vehicle = 3, gone = true }).vehicle, 3)
end)

test("a vehicle without a line: one group, no line stats", function()
	local v = model.build(raw({ veh(1, "A", 12, 10) }, { line = false, capacity = 99, balance = 5 }))
	eq(v.gone, false)
	eq(v.line, nil)
	eq(v.count, 1)
	eq(v.capacity, 0)
	eq(v.balance, 0)
	eq(v.usagePct, nil)
	eq(v.income, nil)
	eq(#v.groups, 1)
	-- the only old vehicle is the vehicle itself: no separate "old vehicles" action
	eq(v.oldVehicles, nil)
	eq(v.fleetVehicles, nil)
end)

-- line stats ---------------------------------------------------------------------

test("usage %, money split, interval and transported", function()
	local v = model.build(raw({ veh(1, "A", 2, 10) }))
	eq(v.line, 500)
	eq(v.capacity, 120)
	eq(v.used, 30)
	eq(v.usagePct, 25)
	eq(v.intervalS, 95)
	eq(v.transported, 4000)
	eq(v.balance, 1000)
	eq(v.running, -3000)
	eq(v.maintenance, -1000)
	eq(v.income, 5000) -- 1000 - (-3000) - (-1000)
end)

test("zero capacity gives no usage %; unknown cost split gives no income", function()
	local v = model.build(raw({ veh(1, "A", 2, 10) }, { capacity = 0, used = 0, running = false, maintenance = false }))
	eq(v.usagePct, nil)
	eq(v.income, nil)
	eq(v.running, nil)
	eq(v.maintenance, nil)
	eq(v.balance, 1000)
end)

test("usage % rounds; float engine numbers are floored", function()
	local v = model.build(raw({ veh(1, "A", 2, 10) }, { used = 2.9, capacity = 3.2 }))
	eq(v.used, 2)
	eq(v.capacity, 3)
	eq(v.usagePct, 67)
end)

-- groups, old and worn ------------------------------------------------------------

test("old = past the lifespan (lifespan 0 never old), worn = condition at or below wornAt", function()
	local v = model.build(raw({
		veh(1, "A", 12, 10, 0.9),  -- old
		veh(2, "A", 10, 10, 0.5),  -- exactly at lifespan: not old; worn (== wornAt)
		veh(3, "A", 30, nil, 0.2), -- no lifespan: never old; worn
		veh(4, "A", 1, 10, nil),   -- condition unknown
	}))
	eq(v.count, 4)
	eq(v.old, 1)
	eq(v.worn, 2)
	eq(v.groups[1].old, 1)
	eq(v.groups[1].oldVehicles, { 1 })
end)

test("groups: the vehicle's own group first, then by count, then key; oldest age and its lifespan", function()
	local v = model.build(raw({
		veh(9, "B", 3, 20),
		veh(1, "A", 4.6, 10), veh(2, "A", 11.2, 8), veh(3, "A", 2, 10),
		veh(4, "C", 1, 10), veh(5, "C", 1, 10), veh(6, "C", 1, 10), veh(7, "C", 1, 10),
	}, { vehicle = 9 }))
	eq(groupKeys(v), { "B", "C", "A" })
	eq(v.groups[1].hasTarget, true)
	eq(v.groups[1].name, "Bus B")
	local a = v.groups[3]
	eq(a.count, 3)
	eq(a.vehicles, { 1, 2, 3 })
	eq(a.oldestYears, 11)
	eq(a.lifeYears, 8)
	eq(a.name, "Bus A")
	eq(v.groups[2].name, "") -- no name for C
end)

test("average age in whole years (rounded); nil without ages", function()
	eq(model.build(raw({ veh(1, "A", 1, 10), veh(2, "A", 2, 10) })).avgYears, 2) -- 1.5 rounds up
	eq(model.build(raw({ { entity = 1, key = "A" } })).avgYears, nil)
end)

-- actions ----------------------------------------------------------------------

test("old vehicles of one composition: one 'Upgrade old vehicles' action", function()
	local v = model.build(raw({ veh(1, "A", 2, 10), veh(3, "A", 12, 10), veh(2, "A", 15, 10) }))
	eq(v.oldVehicles, { 2, 3 })
	for _, g in ipairs(v.groups) do eq(g.offerOld, false) end
end)

test("the vehicle itself as the only old one: no extra old action", function()
	local v = model.build(raw({ veh(1, "A", 12, 10), veh(2, "A", 1, 10) }))
	eq(v.oldVehicles, nil)
	-- another single old vehicle is offered
	v = model.build(raw({ veh(1, "A", 1, 10), veh(2, "A", 12, 10) }))
	eq(v.oldVehicles, { 2 })
end)

test("old vehicles in several compositions: per group (only where not the whole group)", function()
	local v = model.build(raw({
		veh(1, "A", 12, 10), veh(2, "A", 1, 10),
		veh(3, "B", 30, 20),
	}))
	eq(v.oldVehicles, nil)
	local byKey = {}
	for _, g in ipairs(v.groups) do byKey[g.key] = g end
	eq(byKey.A.offerOld, true)
	eq(byKey.A.oldVehicles, { 1 })
	eq(byKey.B.offerOld, false) -- every B is old: its "Upgrade 1" button covers it
end)

test("whole fleet: one composition, or mixed models on a carrier without multiple units", function()
	local mixed = { veh(2, "A", 1, 10), veh(1, "B", 1, 10) }
	eq(model.build(raw(mixed)).fleetVehicles, { 1, 2 })
	eq(model.build(raw(mixed, { multiUnit = true })).fleetVehicles, nil)
	eq(model.build(raw({ veh(2, "A", 1, 10), veh(1, "A", 1, 10) }, { multiUnit = true })).fleetVehicles, { 1, 2 })
	-- a single vehicle: "Upgrade this vehicle" covers it
	eq(model.build(raw({ veh(1, "A", 1, 10) })).fleetVehicles, nil)
end)

test("views are stable between polls when only sub-year ages move", function()
	local a = model.build(raw({ veh(1, "A", 3.1, 10), veh(2, "A", 5.2, 10) }))
	local b = model.build(raw({ veh(1, "A", 3.4, 10), veh(2, "A", 5.3, 10) }))
	eq(a, b)
end)

test("malformed vehicles (no entity) are skipped", function()
	local v = model.build(raw({ { key = "A" }, veh(1, "A", 1, 10) }))
	eq(v.count, 1)
end)

-- average lifespan context (round 3) ------------------------------------------------

test("average lifespan of the vehicles that have one; past it compares the unrounded averages", function()
	local v = model.build(raw({ veh(1, "A", 9, 10), veh(2, "A", 12, 10), veh(3, "A", 30, nil) }))
	eq(v.avgYears, 17) -- (9 + 12 + 30) / 3
	eq(v.avgLifeYears, 10)
	eq(v.avgPastLife, true)
	v = model.build(raw({ veh(1, "A", 9.9, 10), veh(2, "A", 10.0, 10) }))
	eq(v.avgYears, 10)
	eq(v.avgLifeYears, 10)
	eq(v.avgPastLife, false) -- 9.95 < 10
	v = model.build(raw({ veh(1, "A", 3, nil) }))
	eq(v.avgLifeYears, nil)
	eq(v.avgPastLife, nil)
end)

test("ages use the poll's year length: a calendar twice as slow halves the years, not the old verdict", function()
	local vs = { veh(1, "A", 82, 10), veh(2, "A", 41, 10) }
	local fast = model.build(raw(vs))
	local slow = model.build(raw(vs, { yearMs = YEAR * 2 }))
	eq(fast.groups[1].oldestYears, 82)
	eq(slow.groups[1].oldestYears, 41)
	eq(slow.groups[1].lifeYears, 5)
	eq(slow.old, fast.old)
	eq(slow.avgYears, 31) -- 61.5 / 2 = 30.75
end)
