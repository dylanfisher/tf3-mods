-- gui/nfp_patch.script.lua: the autoLoadConfig wrapper on a fake line_util and Line.ReactLine.

local PAX_ID = 0   -- load index 1
local CT = { STATION_GROUP = "STATION_GROUP", INDUSTRY = "INDUSTRY", WAREHOUSE = "WAREHOUSE" }

-- groups: 100 factory (cargo station 1000: industry 500)
--         200 town, cargo station (2000: town buildings 601, 602 only)
--         300 town + factory (cargo station 3000: town building 601, industry 500)
--         400 bus stop 4000 (passenger station) next to a factory
--         500 warehouse (cargo station 5000: warehouse 700)
--         600 bus stop 6000 grouped with truck station 6001 at the factory
--         800 town bus stop 8000
-- Catchables are the stock list owners themselves (no fallback scan).
local world = {
	groups = { [100] = { stations = { 1000 } }, [200] = { stations = { 2000 } }, [300] = { stations = { 3000 } },
		[400] = { stations = { 4000 } }, [500] = { stations = { 5000 } }, [600] = { stations = { 6000, 6001 } },
		[800] = { stations = { 8000 } } },
	cargo = { [1000] = { 500 }, [2000] = { 601, 602 }, [3000] = { 601, 500 }, [4000] = { 500 },
		[5000] = { 700 }, [6000] = { 500 }, [6001] = { 500 }, [8000] = { 601 } },
	cargoStations = { [1000] = true, [2000] = true, [3000] = true, [5000] = true, [6001] = true },
	industries = { [500] = {} },
	warehouses = { [700] = {} },
}

-- StopConfig.load behaves like the engine userdata: reads return a copy, writes replace.
local function stopConfig(load)
	local stored = load
	return setmetatable({}, {
		__index = function(_t, k)
			if k == "load" then
				local c = {}
				for i, v in ipairs(stored) do c[i] = v end
				return c
			end
		end,
		__newindex = function(_t, k, v)
			assert(k == "load")
			stored = v
		end,
	})
end

local function via(group, load, station1)
	return { stop = { stationGroup = group, station1 = station1,
		passThroughStopData = { stopConfig = stopConfig(load) } } }
end

local function loads(line)
	local out = {}
	for _i, v in ipairs(line.path) do
		if v.stop then out[#out + 1] = v.stop.passThroughStopData.stopConfig.load end
	end
	return out
end

local fakeLineUtil, patch, baseCalls, cargoFetches
-- What the faked getModParams returns for this mod (sqperf_log: 1 = Off, 2 = On), and the fake
-- SQPERF Clock (microseconds; moves only when a test moves it).
local MOD_ID = "square_no_factory_passengers"
local myParams, clockUs

before_each(function()
	reset_modules()
	clear_logs()
	baseCalls = 0
	cargoFetches = 0
	myParams, clockUs = {}, 1e9
	set_global("api", {
		type = { ComponentType = CT, Clock = { new = function() return { getTime = function() return clockUs end } end } },
		engine = {
			config = { getModParams = function() return { [MOD_ID] = myParams } end },
			getComponent = function(e, t)
				if t == CT.STATION_GROUP then return world.groups[e] end
				if t == CT.INDUSTRY then return world.industries[e] end
				if t == CT.WAREHOUSE then return world.warehouses[e] end
			end,
			util = { station = { isStationOfType = function(st, cargo)
				assert(cargo == true)
				return world.cargoStations[st] == true
			end } },
			forEachEntityWithComponent = function()
				error("full entity scan on the GUI thread")
			end,
			system = { catchmentAreaSystem = { getStationCatchables = function(st, cargo)
				assert(cargo == true, "passenger catchables are never fetched")
				cargoFetches = cargoFetches + 1
				return world.cargo[st] or {}
			end } },
		},
	})
	-- the base autoLoadConfig: passengers on at every stop (as addPassengerByDefault) but noPax ones
	fakeLineUtil = {
		autoLoadConfig = function(line)
			baseCalls = baseCalls + 1
			if line.customFilters then return end
			for _i, v in ipairs(line.path) do
				if v.stop and not v.stop.noPax then
					local cfg = v.stop.passThroughStopData.stopConfig
					local l = cfg.load
					l[PAX_ID + 1] = true
					cfg.load = l
				end
			end
		end,
	}
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", fakeLineUtil)
	stub_module("::/gui/main/cargo_util.tl", { getPassengerCargoTypeId = function() return PAX_ID end })
	ug_require "/no_factory_passengers/gui/nfp_patch.script.lua"
	patch = data()
	patch.doReplace({})
end)

local function messages()
	local out = {}
	for _i, e in ipairs(log_entries()) do
		if e.level == "message" then out[#out + 1] = e.msg end
	end
	return out
end

test("doReplace wraps line_util.autoLoadConfig and logs once", function()
	eq(messages(), { "[NoFactoryPassengers] installed (line_util.autoLoadConfig wrapped)" })
end)

test("factory -> town line: passengers off at both stops, other cargo flags untouched", function()
	local line = { path = { via(100, { false, false, true }), { waypoint = {} }, via(200, { false, true, false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(baseCalls, 1, "original called")
	eq(loads(line), { { false, false, true }, { false, true, false } })
end)

test("town station that also reaches a factory makes a cargo line", function()
	local line = { path = { via(300, { false }), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false } })
end)

test("a 1-stop line at a factory: passengers off right away", function()
	local line = { path = { via(100, { false, true }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false, true } })
end)

test("warehouse stop makes a cargo line", function()
	local line = { path = { via(800, { false }), via(500, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false } })
end)

test("cargo station in town (only town buildings in reach) keeps passengers", function()
	local line = { path = { via(200, { false }), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true }, { true } })
end)

test("bus line: a passenger-only stop next to a factory keeps passengers, no cargo fetch", function()
	local line = { path = { via(400, { false }), via(800, { false }), via(400, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true }, { true }, { true } })
	eq(cargoFetches, 0)
end)

test("mixed group: the stop's own station decides", function()
	local line = { path = { via(600, { false }, 1), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true }, { true } }, "bus stop of the group")
	line = { path = { via(600, { false }, 2), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false } }, "truck station of the group")
	line = { path = { via(600, { false }), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false } }, "no station assigned: the whole group")
end)

test("a cargo stop with passengers already off still clears the others", function()
	local line = { path = { via(800, { false }), via(100, { false }) } }
	line.path[2].stop.noPax = true -- base: no passenger terminal at the factory stop
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false } })
end)

test("each distinct stop fetched once, scan stops at the first cargo stop", function()
	local line = { path = { via(200, { false }), via(200, { false }), via(100, { false }), via(300, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false }, { false }, { false } })
	eq(cargoFetches, 2)
end)

test("customFilters lines are skipped", function()
	local line = { customFilters = true, path = { via(100, { true, false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(baseCalls, 1)
	eq(loads(line), { { true, false } }, "manual filters untouched")
end)

test("Debug log Off (default): no per-stop log lines", function()
	clear_logs()
	local line = { path = { via(100, { false }), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false } })
	eq(messages(), {})
end)

test("Debug log On: one log line per cleared stop, none on passenger lines", function()
	myParams = { sqperf_log = 2 }
	clear_logs()
	fakeLineUtil.autoLoadConfig({ path = { via(800, { false }), via(400, { false }) } })
	eq(messages(), {})
	fakeLineUtil.autoLoadConfig({ path = { via(800, { false }), via(100, { false }) } })
	eq(messages(), {
		"[NoFactoryPassengers] stop 1 group 800: cargo line (stop 2 reaches an industry or warehouse) -> passengers OFF",
		"[NoFactoryPassengers] stop 2 group 100: cargo line (stop 2 reaches an industry or warehouse) -> passengers OFF",
	})
end)

test("wrapping is idempotent", function()
	local wrapped = fakeLineUtil.autoLoadConfig
	patch.doReplace({})
	ok(not patch.install(fakeLineUtil), "second install is a no-op")
	ok(fakeLineUtil.autoLoadConfig == wrapped)
	fakeLineUtil.autoLoadConfig({ path = { via(800, { false }) } })
	eq(baseCalls, 1, "original runs once per call")
end)

test("errors in the fix are caught, logged once, and the base result stands", function()
	api.engine.system.catchmentAreaSystem.getStationCatchables = function() error("boom") end
	local line = { path = { via(100, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true } })
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and e.msg:find("boom", 1, true) then n = n + 1 end
	end
	eq(n, 1)
end)

local function sqperfLines(pattern)
	local out = {}
	for _i, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern, 1, true)) then out[#out + 1] = e.msg end
	end
	return out
end

test("SQPERF: Debug log On gives a 30 s summary of auto_load_config and fix_line", function()
	myParams = { sqperf_log = 2 }
	clear_logs()
	local line = { path = { via(100, { false }), via(800, { false }) } }
	fakeLineUtil.autoLoadConfig(line) -- first stop opens the window (gate read: On)
	fakeLineUtil.autoLoadConfig({ customFilters = true, path = {} })
	clockUs = clockUs + 31e6
	fakeLineUtil.autoLoadConfig(line)
	local lines = sqperfLines("win_ms=")
	eq(#lines, 1)
	ok(lines[1]:find("mod=square_no_factory_passengers ctx=gui", 1, true), lines[1])
	ok(lines[1]:find("auto_load_config n=2 ms=", 1, true), lines[1])
	ok(lines[1]:find("fix_line n=2 ms=", 1, true), lines[1])
end)

test("SQPERF: Debug log Off: no SQPERF lines from edits; a slow edit (> 16 ms) is logged", function()
	clear_logs()
	local line = { path = { via(200, { false }), via(300, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	clockUs = clockUs + 31e6
	fakeLineUtil.autoLoadConfig(line)
	eq(#sqperfLines(), 0)
	-- 20 ms per catchables fetch: two cargo stations, nothing in reach = 40 ms
	api.engine.system.catchmentAreaSystem.getStationCatchables = function()
		clockUs = clockUs + 20000
		return {}
	end
	fakeLineUtil.autoLoadConfig(line)
	eq(#sqperfLines("slow=fix_line max=40.0 over=1/"), 1)
	eq(#sqperfLines("slow=auto_load_config max=40.0 over=1/"), 1)
end)
