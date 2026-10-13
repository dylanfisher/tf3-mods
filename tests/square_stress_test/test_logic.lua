-- stress_logic.tl: param -> config mapping, job queue throttling, money / date / grid helpers.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl"

---------------------------------------------------------------------------
-- params -> config

test("optionIndex: 1-based index, garbage and out of range fall back to 1", function()
	eq(logic.optionIndex(1, 2), 1)
	eq(logic.optionIndex(2, 2), 2)
	eq(logic.optionIndex(3, 3), 3)
	eq(logic.optionIndex(3, 2), 1)
	eq(logic.optionIndex(0, 2), 1)
	eq(logic.optionIndex(nil, 2), 1)
	eq(logic.optionIndex("x", 2), 1)
	eq(logic.optionIndex(1.5, 2), 1)
	eq(logic.optionIndex(true, 2), 2)
end)

test("configFromParams: defaults (index 1 / missing) change nothing", function()
	local def = { noCosts = false, sandboxMode = false, vehiclesNoExpire = false, noEmissions = false,
		recomputeFactor = 1.0, townDevelopInterval = nil, carTrafficMode = nil,
		townCapacityFactor = 1.0 }
	eq(logic.configFromParams(nil), def)
	eq(logic.configFromParams({}), def)
	eq(logic.configFromParams({ no_costs = 1, sandbox = 1, vehicles_no_expire = 1, no_emissions = 1,
		sim_recompute = 1, town_develop = 1 }), def)
end)

test("configFromParams: every option on", function()
	local cfg = logic.configFromParams({ no_costs = 2, sandbox = 2, vehicles_no_expire = 2, no_emissions = 2,
		sim_recompute = 3, town_develop = 2, town_streets = 2, car_traffic = 3, town_capacity = 3 })
	eq(cfg, { noCosts = true, sandboxMode = true, vehiclesNoExpire = true, noEmissions = true,
		recomputeFactor = 5.0, townDevelopInterval = 15,
		carTrafficMode = logic.CAR_TRAFFIC_MODES[3], townCapacityFactor = 4.0 })
	eq(logic.configFromParams({ sim_recompute = 2, town_develop = 3 }).recomputeFactor, 2.0)
	eq(logic.configFromParams({ town_develop = 3 }).townDevelopInterval, 5)
end)

local function baseConfig()
	return {
		noCosts = false, sandboxMode = false, townDevelopInterval = 60,
		simPersonDestinationRecomputationProbability = 1.0,
		emission = { townNoiseResidentialAffected = true, townNoiseCommercialAffected = true, townNoiseIndustrialAffected = true },
		advancedOptions = { missionEmissionsScriptFactor = 1 },
	}
end

test("applyToBaseConfig: defaults write nothing", function()
	local bc = baseConfig()
	bc.noCosts = true -- set by another mod: must stay
	eq(logic.applyToBaseConfig(logic.configFromParams({}), bc), {})
	local want = baseConfig()
	want.noCosts = true
	eq(bc, want)
end)

test("applyToBaseConfig: every option on", function()
	local bc = baseConfig()
	bc.simPersonDestinationRecomputationProbability = 0.5
	local changes = logic.applyToBaseConfig(logic.configFromParams({ no_costs = 2, sandbox = 2, no_emissions = 2,
		sim_recompute = 2, town_develop = 3 }), bc)
	eq(bc.noCosts, true)
	eq(bc.sandboxMode, true)
	eq(bc.emission, { townNoiseResidentialAffected = false, townNoiseCommercialAffected = false, townNoiseIndustrialAffected = false })
	eq(bc.advancedOptions.missionEmissionsScriptFactor, 0)
	eq(bc.simPersonDestinationRecomputationProbability, 1.0)
	eq(bc.townDevelopInterval, 5)
	eq(#changes, 6)
	eq(changes[1], "noCosts=true")
	eq(changes[3], "missionEmissionsScriptFactor=0")
	eq(changes[6], "townDevelopInterval=5")
end)

test("applyToBaseConfig: nil inputs and a missing emission table are safe", function()
	eq(logic.applyToBaseConfig(nil, baseConfig()), {})
	eq(logic.applyToBaseConfig(logic.configFromParams({}), nil), {})
	local bc = baseConfig()
	bc.emission = nil
	bc.advancedOptions = nil
	eq(logic.applyToBaseConfig(logic.configFromParams({ no_emissions = 2 }), bc), {})
	bc = baseConfig()
	bc.emission = nil
	eq(logic.applyToBaseConfig(logic.configFromParams({ no_emissions = 2 }), bc), { "missionEmissionsScriptFactor=0" })
end)

test("zeroVehicleEmissions: vehicles and cars get 0 everywhere (missing tables created); other models untouched", function()
	local bus = { metadata = { transportVehicle = {}, emissions = {
		noise = { score = 30, idle = 12, speed = 20, power = 0.0001, unmaintained = 90 },
		pollution = { score = 25, idle = 3, speed = 5, power = 0.0002, unmaintained = 30 } } } }
	eq(logic.zeroVehicleEmissions(bus), true)
	local zero = { score = 0, idle = 0, speed = 0, power = 0, unmaintained = 0 }
	eq(bus.metadata.emissions, { noise = zero, pollution = zero })
	local car = { metadata = { car = {} } }
	eq(logic.zeroVehicleEmissions(car), true)
	eq(car.metadata.emissions, { noise = zero, pollution = zero })
	local tree = { metadata = { tree = {}, emissions = { pollution = { idle = -0.1 } } } }
	eq(logic.zeroVehicleEmissions(tree), false)
	eq(tree.metadata.emissions.pollution.idle, -0.1)
	eq(logic.zeroVehicleEmissions({ metadata = {} }), false)
	eq(logic.zeroVehicleEmissions({}), false)
	eq(logic.zeroVehicleEmissions(nil), false)
end)

test("SENSITIVITY_OFF: option index 1 (scale 0) for noise and pollution only", function()
	eq(logic.SENSITIVITY_OFF, { SensitivityNoise = 1, SensitivityPollution = 1 })
end)

test("showProbeTab: only the 2nd value (On) of our own param", function()
	eq(logic.showProbeTab({ square_stress_test = { show_probe_tab = 2 } }), true)
	eq(logic.showProbeTab({ square_stress_test = { show_probe_tab = 1 } }), false)
	eq(logic.showProbeTab({ square_stress_test = {} }), false)
	eq(logic.showProbeTab({ other = { show_probe_tab = 2 } }), false)
	eq(logic.showProbeTab({}), false)
	eq(logic.showProbeTab(nil), false)
	eq(logic.showProbeTab("x"), false)
end)

test("ratingSteps: ignore = noise + pollution per town; restore = one reset per town", function()
	local steps = logic.ratingSteps({ 5, 9 }, true)
	eq(#steps, 4)
	eq(steps[1], { town = 5, event = "setTownRatingSensitivity", param = { townEntity = 5, rating = "noise", sensitivity = 0 } })
	eq(steps[2].param.rating, "pollution")
	eq(steps[4].town, 9)
	eq(logic.ratingSteps({ 5, 9 }, false), {
		{ town = 5, event = "resetTownRatingSensitivity", param = { townEntity = 5 } },
		{ town = 9, event = "resetTownRatingSensitivity", param = { townEntity = 9 } },
	})
	eq(logic.ratingSteps({}, true), {})
	eq(logic.ratingSteps(nil, true), {})
end)

---------------------------------------------------------------------------
-- queue

local function fakeClock(stepUs)
	local t = 0
	return function()
		t = t + (stepUs or 0)
		return t
	end, function(v) t = v end
end

test("tick runs at most perFrame steps per call, oldest job first", function()
	local q = logic.newQueue(3)
	local calls = {}
	logic.push(q, { name = "a", total = 5, step = function(i) calls[#calls + 1] = "a" .. i end })
	logic.push(q, { name = "b", total = 2, step = function(i) calls[#calls + 1] = "b" .. i end })
	local now = fakeClock(0)
	eq(logic.pending(q), 7)
	eq(logic.tick(q, now), {})
	eq(calls, { "a1", "a2", "a3" })
	local done = logic.tick(q, now)
	eq(calls, { "a1", "a2", "a3", "a4", "a5", "b1" })
	eq(#done, 1)
	eq(done[1].name, "a")
	eq(done[1].count, 5)
	eq(logic.pending(q), 1)
	done = logic.tick(q, now)
	eq(done[1].name, "b")
	eq(#q.jobs, 0)
	eq(logic.tick(q, now), {})
end)

test("tick: step errors are counted and do not stop the job", function()
	local q = logic.newQueue(10)
	local n = 0
	logic.push(q, { name = "x", total = 4, step = function(i)
		n = n + 1
		if i % 2 == 0 then error("boom" .. i) end
	end })
	local done = logic.tick(q, fakeClock(0))
	eq(n, 4)
	eq(done[1].errors, 2)
	ok(done[1].firstErr:find("boom2") ~= nil, "first error kept")
	ok(logic.doneLine(done[1]):find("errors=2") ~= nil)
end)

test("tick: a delayed job waits and does not block the jobs behind it", function()
	local q = logic.newQueue(5)
	local calls = {}
	logic.push(q, { name = "later", total = 1, notBefore = 1000, step = function() calls[#calls + 1] = "later" end })
	logic.push(q, { name = "now", total = 1, step = function() calls[#calls + 1] = "now" end })
	local t = 0
	local now = function() return t end
	eq(logic.progress(q), "later (waiting) (+1 job queued)")
	logic.tick(q, now)
	eq(calls, { "now" })
	t = 999
	logic.tick(q, now)
	eq(calls, { "now" })
	t = 1000
	local done = logic.tick(q, now)
	eq(calls, { "now", "later" })
	eq(done[1].name, "later")
end)

test("tick: wall and busy time from the clock", function()
	local q = logic.newQueue(1)
	logic.push(q, { name = "t", total = 2, step = function() end })
	local now = fakeClock(500) -- every clock read advances 0.5 ms
	logic.tick(q, now)
	local done = logic.tick(q, now)
	eq(done[1].count, 2)
	near(done[1].busyMs, 1.0)
	ok(done[1].wallMs >= done[1].busyMs, "wall >= busy")
end)

test("zero-step job finishes on the next tick; total is clamped", function()
	local q = logic.newQueue(1)
	logic.push(q, { name = "empty", total = 0, step = function() error("never") end })
	logic.push(q, { name = "neg", total = -3, step = function() error("never") end })
	local done = logic.tick(q, fakeClock(0))
	eq(#done, 2)
	eq(done[1].count, 0)
	eq(done[2].errors, 0)
end)

test("progress, clear and doneLine", function()
	local q = logic.newQueue(1)
	eq(logic.progress(q), "Idle")
	logic.push(q, { name = "grow", total = 10, step = function() end })
	logic.push(q, { name = "b", total = 1, step = function() end })
	logic.push(q, { name = "c", total = 1, step = function() end })
	logic.tick(q, fakeClock(0))
	eq(logic.progress(q), "grow 1/10 (+2 jobs queued)")
	eq(logic.clear(q), 3)
	eq(logic.progress(q), "Idle")
	eq(logic.doneLine({ name = "add_money_10M", count = 1, errors = 0, wallMs = 12.34, busyMs = 0.5 }),
		"[SQST] action=add_money_10M count=1 ms=12.3 busyMs=0.50")
end)

test("newQueue: perFrame must be positive", function()
	eq(logic.newQueue(0).perFrame, 1)
	eq(logic.newQueue(nil).perFrame, 1)
	eq(logic.newQueue(8).perFrame, 8)
end)

---------------------------------------------------------------------------
-- helpers

test("parseYear", function()
	eq({ logic.parseYear("2000") }, { 2000 })
	eq({ logic.parseYear(" 1950 ") }, { 1950 })
	eq({ logic.parseYear("1850") }, { 1850 })
	eq({ logic.parseYear("2150") }, { 2150 })
	eq({ logic.parseYear("1849") }, { nil, "outside 1850-2150" })
	eq({ logic.parseYear("") }, { nil, "empty" })
	eq({ logic.parseYear(nil) }, { nil, "empty" })
	eq({ logic.parseYear("20x0") }, { nil, "not a number" })
	eq({ logic.parseYear("-1900") }, { nil, "not a number" })
	eq({ logic.parseYear("19.5") }, { nil, "not a number" })
end)

test("bookingChunks", function()
	eq(logic.bookingChunks(10000000), { 10000000 })
	eq(logic.bookingChunks(2500000000), { 1000000000, 1000000000, 500000000 })
	eq(logic.bookingChunks(250, 100), { 100, 100, 50 })
	eq(logic.bookingChunks(0), {})
	eq(logic.bookingChunks(-5), {})
	eq(logic.bookingChunks(nil), {})
	eq(logic.bookingChunks(0 / 0), {})
	eq(logic.bookingChunks(99.9), { 99 })
end)

test("topUpAmount", function()
	eq(logic.topUpAmount(60000000, 50000000, 10000000), 0)
	eq(logic.topUpAmount(50000000, 50000000, 10000000), 0)
	eq(logic.topUpAmount(20000000, 50000000, 10000000), 40000000)
	eq(logic.topUpAmount(-5000000, 50000000, 10000000), 65000000)
	eq(logic.topUpAmount(nil, 50000000, 10000000), 0)
	eq(logic.topUpAmount(0, 50000000, nil), 50000000)
end)

test("formatMoney", function()
	eq(logic.formatMoney(950), "950")
	eq(logic.formatMoney(12500), "12.5k")
	eq(logic.formatMoney(10000000), "10M")
	eq(logic.formatMoney(100000000), "100M")
	eq(logic.formatMoney(1500000000), "1.5B")
	eq(logic.formatMoney(-2000000), "-2M")
	eq(logic.formatMoney(nil), "?")
end)

test("scaledFactors", function()
	eq(logic.scaledFactors({ 1, 2, 0.5 }, 10), { 10, 20, 5 })
	eq(logic.scaledFactors(nil, 2), { 2, 2, 2 })
	eq(logic.scaledFactors({ 3 }, 2), { 6, 2, 2 })
end)

test("gridPoints", function()
	eq(logic.gridPoints(100, 200, 1, 50), { { 100, 200 } })
	local g = logic.gridPoints(0, 0, 9, 150)
	eq(#g, 9)
	eq(g[1], { -150, -150 })
	eq(g[5], { 0, 0 })
	eq(g[9], { 150, 150 })
	eq(#logic.gridPoints(0, 0, 5, 10), 5)
	eq(logic.gridPoints(0, 0, 0, 10), {})
end)

---------------------------------------------------------------------------
-- window log lines

test("oneLine: first line only, tabs as spaces, cut to max with ...", function()
	eq(logic.oneLine("short"), "short")
	eq(logic.oneLine("a\tb"), "a b")
	eq(logic.oneLine("first\nstack traceback:\n\t[C]: in ?"), "first...")
	eq(logic.oneLine("first\r\nsecond"), "first...")
	eq(logic.oneLine(string.rep("y", 160)), string.rep("y", 160))
	eq(logic.oneLine(string.rep("y", 161)), string.rep("y", 157) .. "...")
	eq(logic.oneLine("abcdefghij", 8), "abcde...")
	eq(logic.LOG_LINE_MAX, 160)
end)

test("gridStreetHalf by town size", function()
	eq(logic.gridStreetHalf(100), 1)
	eq(logic.gridStreetHalf(400), 2)
	eq(logic.gridStreetHalf(1600), 3)
	eq(logic.gridStreetHalf(3200), 3)
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	eq(logic.GRID_STREET_HALF, grid.HALF)
end)

test("street grid construction: square grid, every node free, +0 only, within the 485 m reach", function()
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	local coords, step = grid.lines(300)
	eq(#coords, 9)
	near(step, 75)
	eq(coords[1], -300)
	eq(coords[#coords], 300)
	local res = grid.result({ sqst_grid_half = 3, sqst_grid_era = 2 })
	local el = res.edgeLists[1]
	eq(el.type, "STREET")
	eq(el.params.type, "::/infrastructure/street/town/town_old_large.street_template")
	local n = #grid.lines(400) -- 11 lines per axis
	eq(#el.edges, 2 * (2 * n * (n - 1) + 4)) -- the grid + 4 corner stubs
	eq(#el.freeNodes, #el.edges)
	eq(el.freeNodes[1], 0)
	for _, entry in ipairs(el.edges) do
		for _, v in ipairs(entry[1]) do
			ok(math.abs(v) <= 445, "reach")
			ok(not (v == 0 and 1 / v < 0), "no -0")
		end
		for _, v in ipairs(entry[2]) do ok(not (v == 0 and 1 / v < 0), "no -0 tangent") end
	end
	-- each corner has a dead-end stub pointing diagonally outwards, 60 m long
	local e = grid.edges(300)
	local stub = e[#e]
	eq({ stub[1][1], stub[1][2] }, { 300, 300 })
	near(math.sqrt((stub[3][1] - 300) ^ 2 + (stub[3][2] - 300) ^ 2), 60)
	-- defaults: 600 m, new era
	eq(grid.result({}).edgeLists[1].params.type, "::/infrastructure/street/town/town_new_large.street_template")
end)

test("street grid: an even number of blocks, so a central street both ways and a node at the middle of every side", function()
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	for _, half in ipairs(grid.HALF) do
		local coords = grid.lines(half)
		eq((#coords - 1) % 2, 0, half .. ": even block count")
		local mid = coords[(#coords + 1) / 2]
		eq(mid, 0, half .. ": a line through the centre")
		-- an edge of each perimeter street ends at the side's middle, and the central street meets it there
		for _, side in ipairs({ { half, 0 }, { -half, 0 }, { 0, half }, { 0, -half } }) do
			local n = 0
			for _, e in ipairs(grid.edges(half)) do
				for _, p in ipairs({ e[1], e[3] }) do
					if p[1] == side[1] and p[2] == side[2] then n = n + 1 end
				end
			end
			eq(n, 3, string.format("%d: side middle %g,%g has 3 edges (two along the side, the central street)", half, side[1], side[2]))
		end
	end
	-- the Small grid: 6 blocks of 66.7 m (was 5 of 80 m: no central street)
	eq(#grid.lines(200), 7)
end)

test("street grid: outer ring as country road (param 2): perimeter and stubs in their own list, inner streets unchanged", function()
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	local plain = grid.result({ sqst_grid_half = 2 })
	eq(#plain.edgeLists, 1)
	for era, want in ipairs({ "country_new_large", "country_old_large" }) do
		local res = grid.result({ sqst_grid_half = 2, sqst_grid_era = era, sqst_grid_ring = 2 })
		eq(#res.edgeLists, 2)
		local inner, ring = res.edgeLists[1], res.edgeLists[2]
		eq(inner.params.type, grid.TEMPLATES[era])
		ok(ring.params.type:find("/country/" .. want .. ".street_template", 1, true), ring.params.type)
		eq(#inner.edges + #ring.edges, #plain.edgeLists[1].edges, "the same edges")
		-- the ring: 4 sides x 8 blocks + 4 stubs; every ring edge on the perimeter or outside it
		eq(#ring.edges, 2 * (4 * 8 + 4))
		for k = 1, #ring.edges, 2 do
			local a, b = ring.edges[k][1], ring.edges[k + 1][1]
			ok(math.max(math.abs(a[1]), math.abs(a[2])) >= 300 - 1e-6 and math.max(math.abs(b[1]), math.abs(b[2])) >= 300 - 1e-6, "on the ring")
		end
		for k = 1, #inner.edges, 2 do
			local a, b = inner.edges[k][1], inner.edges[k + 1][1]
			ok(not (math.abs(a[1]) == 300 and a[1] == b[1]) and not (math.abs(a[2]) == 300 and a[2] == b[2]), "no perimeter edge inside")
		end
		eq(#ring.freeNodes, #ring.edges)
	end
end)

test("wrapText: lines of at most width at spaces, existing breaks kept, long words whole", function()
	eq(logic.wrapText("one two three four", 9), "one two\nthree\nfour")
	eq(logic.wrapText("short", 60), "short")
	eq(logic.wrapText("a b\nc d", 3), "a b\nc d")
	eq(logic.wrapText("averyveryverylongword x", 5), "averyveryverylongword\nx")
	eq(logic.wrapText(nil, 5), nil)
	local long = string.rep("word ", 40)
	for line in (logic.wrapText(long, 60) .. "\n"):gmatch("(.-)\n") do ok(#line <= 60, line) end
end)
