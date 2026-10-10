-- stress_logic.tl Traffic tab helpers and the action button labels: buy plan, early stop, price and
-- money check, the readout text.

local logic
before_each(function()
	reset_modules()
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
end)

test("buyPlan: round robin over lines with a vehicle; lines without one are skipped", function()
	local plan, skipped = logic.buyPlan({ { line = 1, vehicle = 10 }, { line = 2 }, { line = 3, vehicle = 30 } }, 2)
	eq(plan, { { line = 1, vehicle = 10 }, { line = 3, vehicle = 30 }, { line = 1, vehicle = 10 }, { line = 3, vehicle = 30 } })
	eq(skipped, { 2 })
	local none, sk = logic.buyPlan({ { line = 5 } }, 25)
	eq(#none, 0)
	eq(sk, { 5 })
	eq(#logic.buyPlan({}, 5), 0)
end)

test("stop: the queue reports the job done at the next tick with the steps so far", function()
	local q = logic.newQueue(4)
	local job = logic.push(q, { name = "buy", total = 10, serial = true, step = function() end })
	local t = 0
	local function now() return t end
	logic.tick(q, now)
	eq(job.done, 1)
	logic.stop(job)
	local done = logic.tick(q, now)
	eq(#done, 1)
	eq(done[1].count, 1)
	eq(#q.jobs, 0)
	logic.stop(nil) -- harmless
end)

test("configPrice and canAfford", function()
	eq(logic.configPrice({ 100, 250 }), 350)
	eq(logic.configPrice({}), 0)
	eq(logic.configPrice(nil), nil)
	eq(logic.canAfford(500, 350), true)
	eq(logic.canAfford(349, 350), false)
	eq(logic.canAfford(nil, 350), true) -- infinite money
	eq(logic.canAfford(10, nil), true)  -- price unknown: let the engine decide
end)

test("trafficReadout leaves out unknown counts and a zero added count", function()
	eq(logic.trafficReadout(4, 37, 12345, 0), "Lines 4   Vehicles 37   Sim persons 12.3k")
	eq(logic.trafficReadout(4, 1500, nil, 10), "Lines 4   Vehicles 1.5k   Added 10")
	eq(logic.trafficReadout(nil, nil, nil, nil), "Traffic: readout unavailable")
end)

test("action labels name what the button does", function()
	eq(logic.growLabel(false, 10), "Grow all towns x10")
	eq(logic.growLabel(true, 2), "Grow nearest town x2")
	eq(logic.growLabel(false, nil), "Reset all towns to x1")
	eq(logic.growLabel(true, nil), "Reset nearest town to x1")
	eq(logic.spawnLabel(1, "Medium"), "Spawn 1 medium town")
	eq(logic.spawnLabel(25, "Huge"), "Spawn 25 huge towns")
	eq(logic.addVehiclesLabel(1), "Add 1 vehicle per line")
	eq(logic.addVehiclesLabel(5), "Add 5 vehicles per line")
end)

test("VEHICLES_PER_LINE options", function()
	eq(logic.VEHICLES_PER_LINE, { 1, 5, 10, 25 })
	eq(logic.MAX_BUY_FAILURES, 3)
end)

test("trafficReadout shows Driving now when a scan ran", function()
	eq(logic.trafficReadout(3, 10, 700, 0, 63), "Lines 3   Vehicles 10   Sim persons 700   Driving now 63")
	eq(logic.trafficReadout(3, 10, 700, 2, 0), "Lines 3   Vehicles 10   Sim persons 700   Driving now 0   Added 2")
	eq(logic.trafficReadout(3, 10, 700, 0, nil), "Lines 3   Vehicles 10   Sim persons 700")
end)

test("isDriver: DRIVE with a path, not in a vehicle, never a transport vehicle", function()
	eq(logic.isDriver(true, true, false, false), true)
	eq(logic.isDriver(false, true, false, false), false) -- walking
	eq(logic.isDriver(true, false, false, false), false) -- parked / at home
	eq(logic.isDriver(true, true, true, false), false)   -- seated in a bus
	eq(logic.isDriver(true, true, false, true), false)   -- a transport vehicle
end)

test("chunkLast and clearStepsLeft", function()
	eq(logic.chunkLast(1, 12000, 5000), 5000)
	eq(logic.chunkLast(10001, 12000, 5000), 12000)
	eq(logic.chunkLast(1, 0, 200), 0)
	eq(logic.clearStepsLeft(12000, 0, 5000, 200), 3)
	eq(logic.clearStepsLeft(0, 401, 5000, 200), 3)
	eq(logic.clearStepsLeft(-1, 0, 5000, 200), 0)
	eq(logic.clearStepsLeft(1, 1, 5000, 200), 2)
end)

test("clearLine: answered only when callbacks are missing, plus a note", function()
	eq(logic.clearLine("clear_traffic", 693, 63, 63, 63, 63, 12.4), "[SQST] clear_traffic scanned=693 drivers=63 sent=63 ok=63 ms=12")
	eq(logic.clearLine("clear_traffic", 10, 2, 2, 1, 1, 5, "stopped (queue cleared)"),
		"[SQST] clear_traffic scanned=10 drivers=2 sent=2 ok=1 ms=5 answered=1 stopped (queue cleared)")
end)

test("maxPerTick: one step per tick, the jobs behind it still run", function()
	local q = logic.newQueue(4)
	local a, b = 0, 0
	logic.push(q, { name = "chunked", total = 3, maxPerTick = 1, step = function() a = a + 1 end })
	logic.push(q, { name = "other", total = 6, step = function() b = b + 1 end })
	local t = 0
	local function now() return t end
	logic.tick(q, now)
	eq(a, 1)
	eq(b, 3)
	local done2 = logic.tick(q, now)
	eq(a, 2)
	eq(b, 6)
	eq(done2[1].name, "other")
	local done = logic.tick(q, now)
	eq(a, 3)
	eq(#done, 1)
	eq(#q.jobs, 0)
end)

test("a step can grow or end its job by setting total", function()
	local q = logic.newQueue(4)
	local n = 0
	logic.push(q, { name = "dyn", total = 1, maxPerTick = 1, step = function(_i, job)
		n = n + 1
		job.total = job.done + (n < 3 and 1 or 0)
	end })
	local function now() return 0 end
	eq(#logic.tick(q, now), 0)
	eq(#logic.tick(q, now), 0)
	local done = logic.tick(q, now)
	eq(n, 3)
	eq(done[1].count, 3)
end)
