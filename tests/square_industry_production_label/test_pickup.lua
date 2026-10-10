-- production_label_pickup: the pure aggregation (stockList -> {cargo -> summed line rate}) against a
-- stub adapter (dedupe per line, load filtering, passenger-only stops, terminal cargoLoad, unload-only
-- stops, stopIndex fallback, memoisation), the stale/paused logic, refresh's error handling and
-- ratesFor against a small fake api. Shapes: api/tealdef/api/engine/system.d.tl:44-45 (line stops map),
-- api/tealdef/api/engine.d.tl:492-552 (Line.Stop).

local pickup = ug_require "square_industry_production_label::/production_label/production_label_pickup.tl"

local PASSENGER = 0
local FISH, GRAIN, COAL = 7, 3, 5

-- load vector (IdVector, index = cargo + 1) for cargo types 0..9
local function loads(...)
	local v = {}
	for i = 1, 10 do v[i] = false end
	for _, c in ipairs({ ... }) do v[c + 1] = true end
	return v
end

local function stop(sg, load, extra)
	local s = { stationGroup = sg, station = 0, terminal = 0, loadMode = 0, load = load }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

-- world: { map = {sg -> {{line, idx0}}}, lines = {line -> stops}, rates = {line -> rate},
--          reach = {sg -> {stockList}}, outputs = {stockList -> {cargo}}, cargoLoad = {"sg:st:t" -> bool} }
local function adapter(world)
	local calls = { lineStops = {}, lineRate = {}, reach = {}, outputs = {}, map = 0 }
	local a = { fallbackStations = 0 }
	a.lineStopsMap = function() calls.map = calls.map + 1; return world.map end
	a.lineStops = function(line) calls.lineStops[line] = (calls.lineStops[line] or 0) + 1; return world.lines[line] end
	a.lineRate = function(line) calls.lineRate[line] = (calls.lineRate[line] or 0) + 1; return world.rates[line] end
	a.reachableStockLists = function(sg) calls.reach[sg] = (calls.reach[sg] or 0) + 1; return (world.reach or {})[sg] end
	a.outputCargoTypes = function(sl) calls.outputs[sl] = (calls.outputs[sl] or 0) + 1; return (world.outputs or {})[sl] end
	a.terminalCargoLoad = function(sg, st, t)
		local v = (world.cargoLoad or {})[sg .. ":" .. tostring(st) .. ":" .. tostring(t)]
		return v
	end
	a.passengerCargoType = function() return PASSENGER end
	return a, calls
end

-- Fishing ground 100 (output fish) with built-in group 1; farm 200 (grain) and mine 300 (coal) by group 2.
local function baseWorld()
	return {
		map = {
			[1] = { { 10, 0 } },
			[2] = { { 11, 0 }, { 12, 1 } },
			[3] = { { 11, 1 }, { 12, 0 } },
		},
		lines = {
			[10] = { stop(1, loads(FISH)), stop(3, loads()) },
			[11] = { stop(2, loads(GRAIN)), stop(3, loads()) },
			[12] = { stop(3, loads()), stop(2, loads(GRAIN, COAL)) },
		},
		rates = { [10] = 112, [11] = 40, [12] = 25 },
		reach = { [1] = { 100 }, [2] = { 200, 300 }, [3] = { 400 } },
		outputs = { [100] = { FISH }, [200] = { GRAIN }, [300] = { COAL }, [400] = {} },
	}
end

before_each(function()
	pickup.REFRESH_INTERVAL = 15
	pickup.LEGACY_UNLOAD_ONLY = 3
	pickup.SLICE_BUDGET_MS, pickup.SLICE_GAP_MS, pickup.BUILD_MAX_MS = 4, 100, 3000
end)

-- aggregate -----------------------------------------------------------------------

test("sums the rate of every line loading the output cargo in reach", function()
	local rates, stats = pickup.aggregate((adapter(baseWorld())))
	eq(rates, {
		[100] = { [FISH] = 112 },
		[200] = { [GRAIN] = 65 },
		[300] = { [COAL] = 25 }, -- mixed-cargo line 12: full rate on each cargo (known over-count)
	})
	eq(stats.stationGroups, 3)
	eq(stats.lines, 3)
	eq(stats.stockLists, 3)
	eq(stats.stopIndexMismatches, 0)
end)

test("an industry with only unloading lines (or none) gets no entry", function()
	local rates = pickup.aggregate((adapter(baseWorld())))
	eq(rates[400], nil)
	eq(rates[999], nil)
end)

test("a line stopping twice at the group (or at two terminals of it) counts once", function()
	local w = baseWorld()
	w.map[1] = { { 10, 0 }, { 10, 2 } }
	w.lines[10] = { stop(1, loads(FISH)), stop(3, loads()), stop(1, loads(FISH), { terminal = 1 }) }
	local rates = pickup.aggregate((adapter(w)))
	eq(rates[100], { [FISH] = 112 })
end)

test("each line's stops and rate are read once; rates only for lines that serve something", function()
	local w = baseWorld()
	w.lines[13] = { stop(3, loads()) }
	w.rates[13] = 999
	w.map[3][#w.map[3] + 1] = { 13, 0 }
	local a, calls = adapter(w)
	pickup.aggregate(a)
	eq(calls.map, 1)
	eq(calls.lineStops, { [10] = 1, [11] = 1, [12] = 1, [13] = 1 })
	eq(calls.lineRate, { [10] = 1, [11] = 1, [12] = 1 })
end)

test("reach is queried once per group and only for groups with a cargo-loading stop", function()
	local a, calls = adapter(baseWorld())
	pickup.aggregate(a)
	eq(calls.reach, { [1] = 1, [2] = 1 }) -- group 3 only unloads
	eq(calls.outputs, { [100] = 1, [200] = 1, [300] = 1 })
end)

test("busy group with many non-producing catchables: reach and outputs read once, same sums", function()
	-- Group 2 reaches 50 town buildings (no outputs) besides the farm and the mine; four lines stop
	-- there, two of them twice. Producing pairs are built once per group (PERF_REVIEW.md 2026-10-08).
	local w = baseWorld()
	local reach = {}
	for i = 1, 50 do
		reach[i] = 1000 + i
		w.outputs[1000 + i] = {}
	end
	reach[#reach + 1] = 200
	reach[#reach + 1] = 300
	reach[#reach + 1] = 200 -- duplicate entry: still one line per (stockList, cargo)
	w.reach[2] = reach
	w.lines[13] = { stop(2, loads(GRAIN)), stop(2, loads(COAL), { terminal = 1 }) }
	w.lines[14] = { stop(2, loads(COAL)) }
	w.rates[13], w.rates[14] = 7, 3
	w.map[2] = { { 11, 0 }, { 12, 1 }, { 13, 0 }, { 13, 1 }, { 14, 0 } }
	local a, calls = adapter(w)
	local rates = pickup.aggregate(a)
	eq(rates[200], { [GRAIN] = 40 + 25 + 7 })
	eq(rates[300], { [COAL] = 25 + 7 + 3 })
	eq(calls.reach[2], 1)
	for sl, n in pairs(calls.outputs) do eq(n, 1, "outputs read once for " .. tostring(sl)) end
end)

test("passenger-only stops never query reach (bus stations cost nothing)", function()
	local w = baseWorld()
	w.map = { [5] = { { 20, 0 } } }
	w.lines = { [20] = { stop(5, loads(PASSENGER)) } }
	w.rates = { [20] = 300 }
	w.reach = { [5] = { 100 } }
	local a, calls = adapter(w)
	eq((pickup.aggregate(a)), {})
	eq(calls.reach, {})
end)

test("only cargos the stop loads count (load index = cargoTypeId + 1)", function()
	local w = baseWorld()
	w.lines[10] = { stop(1, loads(GRAIN)), stop(3, loads()) } -- loads grain at the fishing ground
	w.outputs[100] = { FISH }
	local rates = pickup.aggregate((adapter(w)))
	eq(rates[100], nil)
	-- off-by-one guard: cargo 6 (index 7) is not fish (cargo 7, index 8)
	w.lines[10] = { stop(1, loads(FISH - 1)) }
	eq(pickup.aggregate((adapter(w)))[100], nil)
end)

test("unload-only stops (LEGACY_UNLOAD_ONLY) and terminals without cargoLoad are skipped", function()
	local w = baseWorld()
	w.lines[10] = { stop(1, loads(FISH), { loadMode = 3 }) }
	eq(pickup.aggregate((adapter(w)))[100], nil)
	w.lines[10] = { stop(1, loads(FISH), { loadMode = 1 }) } -- full load: still loads
	eq(pickup.aggregate((adapter(w)))[100], { [FISH] = 112 })
	w.cargoLoad = { ["1:0:0"] = false }
	eq(pickup.aggregate((adapter(w)))[100], nil)
	w.cargoLoad = { ["1:0:0"] = true }
	eq(pickup.aggregate((adapter(w)))[100], { [FISH] = 112 })
end)

test("stopIndex mismatch: falls back to every stop of the line at that group, counted", function()
	local w = baseWorld()
	w.map[1] = { { 10, 1 } } -- 1-based index would point at stop 2 (group 3)
	local rates, stats = pickup.aggregate((adapter(w)))
	eq(rates[100], { [FISH] = 112 })
	eq(stats.stopIndexMismatches, 1)
	w.map[1] = { { 10, 7 } } -- out of range
	rates, stats = pickup.aggregate((adapter(w)))
	eq(rates[100], { [FISH] = 112 })
	eq(stats.stopIndexMismatches, 1)
end)

test("an industry reached from two groups sums distinct lines once each", function()
	local w = baseWorld()
	w.reach[2] = { 200, 300, 100 }
	w.outputs[100] = { FISH, GRAIN }
	local rates = pickup.aggregate((adapter(w)))
	eq(rates[100], { [FISH] = 112, [GRAIN] = 65 })
end)

test("malformed adapter data never errors: nil map / stops / reach / outputs / load, bad rates", function()
	eq((pickup.aggregate((adapter({ map = nil, lines = {} })))), {})
	local w = baseWorld()
	w.lines[10] = nil
	w.lines[11] = { stop(2, nil) }
	w.reach[2] = nil
	eq((pickup.aggregate((adapter(w)))), {})
	w = baseWorld()
	w.rates = { [10] = 0 / 0, [11] = -5, [12] = "x" }
	eq((pickup.aggregate((adapter(w)))), {})
end)

test("fractional rates are summed, then rounded", function()
	local w = baseWorld()
	w.rates = { [10] = 1, [11] = 0.3, [12] = 0.3 }
	local rates = pickup.aggregate((adapter(w)))
	eq(rates[200], { [GRAIN] = 1 })
	eq(rates[300], nil) -- 0.3 rounds to 0
end)

-- sliced rebuild (newBuild / step / tick, PERF_REVIEW.md 2026-10-10) ------------------------------

-- A bigger world: n groups, each with its own producer and a shared town catchable, lines that load
-- at several groups (dedupe across slices), unload-only stops and stopIndex mismatches.
local function bigWorld(n)
	local w = { map = {}, lines = {}, rates = {}, reach = {}, outputs = {}, cargoLoad = {} }
	for g = 1, n do
		local line = 1000 + (g % 7)
		local line2 = 2000 + g
		w.map[g] = { { line, g - 1 }, { line2, 5 } } -- line2's index is wrong on purpose (fallback)
		w.reach[g] = { 100 + g, 99, 100 + ((g + 1) % n) + 1 }
		w.outputs[100 + g] = (g % 3 == 0) and { FISH, GRAIN } or { (g % 2 == 0) and COAL or GRAIN }
		w.outputs[99] = {}
		w.lines[line2] = { stop(g, (g % 4 == 0) and loads() or loads(FISH, GRAIN, COAL)) }
		w.rates[line2] = g * 1.25
	end
	for l = 0, 6 do
		local stops = {}
		for g = 1, n do stops[g] = stop(g, loads(GRAIN, COAL), { loadMode = (g % 5 == 0) and 3 or 0 }) end
		w.lines[1000 + l] = stops
		w.rates[1000 + l] = 10 + l
	end
	return w
end

test("step: a build sliced after every unit gives the same rates and stats as one pass", function()
	for _, n in ipairs({ 1, 2, 5, 40 }) do
		local w = bigWorld(n)
		local whole, wholeStats = pickup.aggregate((adapter(w)))
		ok(next(whole) ~= nil, "non-trivial world")
		local b = pickup.newBuild((adapter(w)))
		local steps = 0
		while not pickup.step(b, function() return true end) do steps = steps + 1 end
		eq(b.result, whole, "n=" .. n)
		eq(b.stats, wholeStats, "n=" .. n)
		ok(n == 1 or steps > 0, "sliced at all")
		ok(pickup.step(b), "done stays done")
	end
end)

test("step: memoised reads stay once per rebuild across slices", function()
	local a, calls = adapter(bigWorld(20))
	local b = pickup.newBuild(a)
	while not pickup.step(b, function() return true end) do end
	for _, n in pairs(calls.lineStops) do eq(n, 1) end
	for _, n in pairs(calls.lineRate) do eq(n, 1) end
	for _, n in pairs(calls.reach) do eq(n, 1) end
	for _, n in pairs(calls.outputs) do eq(n, 1) end
	eq(calls.map, 1)
end)

-- tick driver with a fake ms clock and a fixed updateCount
local function ucount(value)
	return { fn = function() return value end }
end

local function msClock()
	local c = { t = 0 }
	c.fn = function() return c.t end
	return c
end

local function tickWorld(w, cache, now, uc, clock)
	return pickup.tick(cache, function() return (adapter(w)) end, now, uc, clock.fn)
end

test("tick: first build at once; a later rebuild is sliced, old rates served until it is complete", function()
	local clock = msClock()
	local c = pickup.newCache()
	local w1 = bigWorld(30)
	local built, stats, worked = tickWorld(w1, c, 0, ucount(1).fn, clock)
	ok(built and worked and stats ~= nil)
	local first = pickup.aggregate((adapter(w1)))
	eq(c.rates, first)
	-- Next interval, network changed. Every budget check reports over budget: one unit per slice.
	local w2 = bigWorld(31)
	local expected = pickup.aggregate((adapter(w2)))
	pickup.SLICE_BUDGET_MS = 0
	built, _, worked = tickWorld(w2, c, 15, ucount(2).fn, clock)
	ok(worked and not built and c.pending ~= nil)
	eq(c.rates, first) -- old rates still served
	-- Within the gap: no work.
	clock.t = 50
	built, _, worked = tickWorld(w2, c, 15, ucount(2).fn, clock)
	eq(worked, false)
	local slices = 1
	while c.pending ~= nil do
		clock.t = clock.t + 100
		built, _, worked = tickWorld(w2, c, 16, ucount(2).fn, clock)
		ok(worked)
		slices = slices + 1
		ok(slices < 500, "finishes")
	end
	ok(built)
	ok(slices > 2, "really sliced: " .. slices)
	eq(c.rates, expected)
	eq(c.builds, 2)
	eq(c.building, false)
	pickup.SLICE_BUDGET_MS = 4
end)

test("tick: a pending build older than BUILD_MAX_MS finishes in its next slice", function()
	local clock = msClock()
	local c = pickup.newCache()
	tickWorld(bigWorld(10), c, 0, ucount(1).fn, clock)
	pickup.SLICE_BUDGET_MS = 0
	tickWorld(bigWorld(10), c, 15, ucount(2).fn, clock)
	ok(c.pending ~= nil)
	clock.t = pickup.BUILD_MAX_MS
	local built = tickWorld(bigWorld(10), c, 15, ucount(2).fn, clock)
	ok(built)
	eq(c.pending, nil)
	pickup.SLICE_BUDGET_MS = 4
end)

test("tick: an error in a slice keeps the last rates, logs once, and waits for the next interval", function()
	clear_logs()
	local clock = msClock()
	local c = pickup.newCache()
	local w = bigWorld(5)
	tickWorld(w, c, 0, ucount(1).fn, clock)
	local good = c.rates
	local bad = bigWorld(5)
	bad.reach = setmetatable({}, { __index = function() error("boom") end })
	local built, _, worked = tickWorld(bad, c, 15, ucount(2).fn, clock)
	ok(worked and not built)
	eq(c.pending, nil); eq(c.building, false)
	ok(c.rates == good)
	eq((tickWorld(bad, c, 16, ucount(3).fn, clock)), false) -- not stale yet
	tickWorld(bad, c, 30, ucount(4).fn, clock)
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("rebuild failed", 1, true) then n = n + 1 end
	end
	eq(n, 1)
end)

test("tick: paused (updateCount unchanged) starts no rebuild", function()
	local clock = msClock()
	local c = pickup.newCache()
	tickWorld(bigWorld(5), c, 0, ucount(1).fn, clock)
	local built, _, worked = tickWorld(bigWorld(5), c, 100, ucount(1).fn, clock)
	eq(built, false); eq(worked, false); eq(c.pending, nil)
end)

test("micro-benchmark: sliced vs whole rebuild of a 300-group world (informational)", function()
	local w = bigWorld(300)
	local t0 = os.clock()
	local whole = pickup.aggregate((adapter(w)))
	local wholeMs = (os.clock() - t0) * 1000
	local b = pickup.newBuild((adapter(w)))
	local maxMs, slices = 0, 0
	repeat
		local s0 = os.clock()
		local done = pickup.step(b, function() return (os.clock() - s0) * 1000 >= 0.5 end)
		maxMs = math.max(maxMs, (os.clock() - s0) * 1000)
		slices = slices + 1
	until done
	eq(b.result, whole)
	print(string.format("whole %.2f ms; sliced (0.5 ms budget) %d slices, max %.2f ms", wholeMs, slices, maxMs))
end)

-- isStale -----------------------------------------------------------------------

local function counter(value)
	local c = { n = 0 }
	c.fn = function() c.n = c.n + 1; return value end
	return c
end

test("never built: stale, without reading updateCount", function()
	local uc = counter(5)
	ok(pickup.isStale(pickup.newCache(), 0, uc.fn))
	eq(uc.n, 0)
end)

test("within the interval: fresh, without reading updateCount", function()
	local c = pickup.newCache()
	c.builtAt, c.builtUpdateCount = 100, 5
	local uc = counter(99)
	ok(not pickup.isStale(c, 114.9, uc.fn))
	eq(uc.n, 0)
end)

test("interval passed and the simulation advanced: stale", function()
	local c = pickup.newCache()
	c.builtAt, c.builtUpdateCount = 100, 5
	ok(pickup.isStale(c, 115, counter(6).fn))
end)

test("paused (updateCount unchanged): fresh however long it has been", function()
	local c = pickup.newCache()
	c.builtAt, c.builtUpdateCount = 100, 5
	ok(not pickup.isStale(c, 10000, counter(5).fn))
end)

test("paused: the interval restarts, so GAME_TIME is read once per interval, not per label", function()
	local c = pickup.newCache()
	c.builtAt, c.builtUpdateCount = 100, 5
	local uc = counter(5)
	ok(not pickup.isStale(c, 200, uc.fn))
	ok(not pickup.isStale(c, 201, uc.fn))
	ok(not pickup.isStale(c, 214.9, uc.fn))
	eq(uc.n, 1)
	ok(pickup.isStale(c, 215, counter(6).fn)) -- unpaused: stale at the next interval
end)

test("another game loaded (smaller updateCount) or clock went back: stale", function()
	local c = pickup.newCache()
	c.builtAt, c.builtUpdateCount = 100, 5000
	ok(pickup.isStale(c, 200, counter(3).fn))
	ok(pickup.isStale(c, 50, counter(5001).fn))
	ok(pickup.isStale(c, 40, counter(5000).fn) == false) -- clock back but paused: nothing to redo
end)

test("while building: never stale (single flight)", function()
	local c = pickup.newCache()
	c.building = true
	ok(not pickup.isStale(c, 0, counter(1).fn))
end)

-- refresh -----------------------------------------------------------------------

test("refresh builds when stale, stores rates and stamps time + updateCount", function()
	local c = pickup.newCache()
	local built, stats = pickup.refresh(c, (adapter(baseWorld())), 10, counter(42).fn)
	ok(built)
	eq(stats.stockLists, 3)
	eq(c.rates[100], { [FISH] = 112 })
	eq(c.builtAt, 10)
	eq(c.builtUpdateCount, 42)
	eq(c.builds, 1)
	ok(not c.building)
end)

test("refresh does nothing when fresh or paused (adapter untouched)", function()
	local c = pickup.newCache()
	pickup.refresh(c, (adapter(baseWorld())), 10, counter(42).fn)
	local a, calls = adapter(baseWorld())
	eq(pickup.refresh(c, a, 20, counter(43).fn), false)
	eq(pickup.refresh(c, a, 100, counter(42).fn), false)
	eq(calls.map, 0)
	eq(pickup.refresh(c, a, 114, counter(43).fn), false) -- paused check restarted the interval
	eq(pickup.refresh(c, a, 115, counter(43).fn), true)
	eq(calls.map, 1)
	eq(c.builds, 2)
end)

test("a failing rebuild keeps the last good rates, logs once and waits for the next interval", function()
	clear_logs()
	local c = pickup.newCache()
	pickup.refresh(c, (adapter(baseWorld())), 10, counter(1).fn)
	local bad = adapter(baseWorld())
	bad.lineStopsMap = function() error("boom") end
	eq(pickup.refresh(c, bad, 30, counter(2).fn), false)
	eq(c.rates[100], { [FISH] = 112 })
	eq(c.builtAt, 30)
	ok(not c.building)
	ok(not pickup.isStale(c, 40, counter(3).fn))
	pickup.refresh(c, bad, 50, counter(3).fn)
	local warnings = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("rebuild failed", 1, true) then warnings = warnings + 1 end
	end
	eq(warnings, 1)
end)

-- ratesFor (fake api) ---------------------------------------------------------------

local function fakeApi(world)
	local t = { now = 0, updateCount = 1, mapCalls = 0 }
	local CT = setmetatable({}, { __index = function(_, k) return k end })
	local comps = {
		LINE = {}, STATION_GROUP = { [1] = { stations = { 1001 } } }, STATION = {}, STOCK_LIST = {},
		GAME_TIME = { [0] = setmetatable({}, { __index = function(_, k) if k == "updateCount" then return t.updateCount end end }) },
		CONSTRUCTION = {}, INDUSTRY = {},
	}
	comps.LINE[10] = { stops = { { stationGroup = 1, station = 0, terminal = 0, loadMode = 0, stopConfig = { load = loads(FISH) } } } }
	comps.STATION[1001] = { terminals = { { cargoLoad = true } } }
	comps.STOCK_LIST[100] = { stocks = { { type = "In" }, { type = "Out" } } }
	t.api = {
		type = { ComponentType = CT, enum = { StockListType = { OutputStock = "Out", InputStock = "In" } } },
		res = { cargoTypeRep = { getPassengerCargoTypeId = function() return PASSENGER end } },
		engine = {
			getComponent = function(e, ct) return comps[ct][e] end,
			util = {
				getWorld = function() return 0 end,
				line = { calcLineStationThroughput = function(line) return world.rates[line] end },
				stock = { getStockCargoTypes = function(sl, stockId) return stockId == 1 and { FISH } or { GRAIN } end },
			},
			system = {
				lineSystem = { getStationGroup2LineStopsMap = function() t.mapCalls = t.mapCalls + 1; return { [1] = { { 10, 0 } } } end },
				catchmentAreaSystem = { getStationCatchables = function(station, cargo) return world.catchables[station] or {} end },
				streetConnectorSystem = { getConstructionEntityForStation = function(station) return world.construction[station] or -1 end },
			},
		},
	}
	t.comps = comps
	t.os = { time = function() return t.now end, clock = os.clock }
	return t
end

local function freshModule()
	reset_modules()
	return ug_require "square_industry_production_label::/production_label/production_label_pickup.tl"
end

test("ratesFor: engine adapter end to end, shared cache, one rebuild per interval", function()
	local t = fakeApi({ rates = { [10] = 112 }, catchables = { [1001] = { 100 } }, construction = {} })
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = false
	eq(p.ratesFor(100), { [FISH] = 112 }) -- output stock 2 only (input stock 1 ignored)
	eq(p.ratesFor(555), nil)
	eq(t.mapCalls, 1)
	t.now, t.updateCount = 16, 2
	t.comps.LINE[10].stops[1].stopConfig.load = loads(GRAIN)
	eq(p.ratesFor(100), nil)
	eq(t.mapCalls, 2)
end)

test("ratesFor: SQPERF section pickup_rebuild timed once per rebuild (one slice here), never per plain lookup", function()
	local t = fakeApi({ rates = { [10] = 112 }, catchables = { [1001] = { 100 } }, construction = {} })
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = false
	local stops, counts = {}, {}
	p.perf = {
		start = function() return 5 end,
		stop = function(_self, name, t0) stops[#stops + 1] = name .. "@" .. tostring(t0); return 0 end,
		count = function(_self, name) counts[name] = (counts[name] or 0) + 1 end,
	}
	eq(p.ratesFor(100), { [FISH] = 112 })
	eq(p.ratesFor(555), nil)
	eq(stops, { "pickup_rebuild@5" })
	t.now, t.updateCount = 16, 2
	eq(p.ratesFor(100), { [FISH] = 112 })
	eq(stops, { "pickup_rebuild@5", "pickup_rebuild@5" })
	eq(counts, { pickup_built = 2 })
end)

test("ratesFor: built-in industry station (no catchables) found through the construction", function()
	local t = fakeApi({ rates = { [10] = 80 }, catchables = {}, construction = { [1001] = 900 } })
	t.comps.CONSTRUCTION[900] = { industries = { 950 } }
	t.comps.INDUSTRY[950] = { stockList = 100 }
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = false
	eq(p.ratesFor(100), { [FISH] = 80 })
end)

test("ratesFor: terminal without cargoLoad adds nothing", function()
	local t = fakeApi({ rates = { [10] = 80 }, catchables = { [1001] = { 100 } }, construction = {} })
	t.comps.STATION[1001] = { terminals = { { cargoLoad = false } } }
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = false
	eq(p.ratesFor(100), nil)
end)

test("ratesFor: -1 entries in the station group are skipped (no engine call with -1)", function()
	local t = fakeApi({ rates = { [10] = 80 }, catchables = { [1001] = { 100 } }, construction = {} })
	t.comps.STATION_GROUP[1] = { stations = { -1, 1001 } }
	t.comps.LINE[10].stops[1].station = 1
	local cs = t.api.engine.system.catchmentAreaSystem
	local orig = cs.getStationCatchables
	cs.getStationCatchables = function(station, cargo) assert(station >= 0, "called with -1"); return orig(station, cargo) end
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = false
	eq(p.ratesFor(100), { [FISH] = 80 })
end)

test("ratesFor: the stop's load vector is copied, not kept as a reference", function()
	local t = fakeApi({ rates = { [10] = 112 }, catchables = { [1001] = { 100 } }, construction = {} })
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = false
	local stops = p.engineAdapter().lineStops(10)
	ok(stops[1].load ~= t.comps.LINE[10].stops[1].stopConfig.load)
	eq(stops[1].load, loads(FISH))
end)

test("ratesFor never errors: a broken api gives nil and one warning", function()
	clear_logs()
	set_global("api", {})
	local p = freshModule()
	eq(p.ratesFor(100), nil)
	eq(p.ratesFor(100), nil)
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("lookup failed", 1, true) then n = n + 1 end
	end
	eq(n, 1)
end)

test("DEBUG logs the first build once and only the first DEBUG_LOOKUPS lookups", function()
	clear_logs()
	local t = fakeApi({ rates = { [10] = 112 }, catchables = { [1001] = { 100 } }, construction = {} })
	set_global("api", t.api); set_global("os", t.os)
	local p = freshModule()
	p.DEBUG = true
	p.DEBUG_LOOKUPS = 2
	p.ratesFor(100)
	p.ratesFor(555)
	p.ratesFor(100)
	t.now, t.updateCount = 16, 2
	p.ratesFor(100)
	local built, lookups = 0, 0
	for _, e in ipairs(log_entries()) do
		local m = e.msg
		if m:find("cache built", 1, true) then built = built + 1 end
		if m:find("pickup lookup", 1, true) then lookups = lookups + 1 end
	end
	eq(built, 1)
	eq(lookups, 2)
end)
