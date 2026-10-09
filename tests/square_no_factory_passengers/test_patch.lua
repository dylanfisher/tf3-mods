-- gui/nfp_patch.script.lua: the autoLoadConfig wrapper on a fake line_util and Line.ReactLine.

local PAX_ID = 0   -- load index 1
local CT = { STATION_GROUP = "STATION_GROUP", INDUSTRY = "INDUSTRY", TOWN_BUILDING = "TOWN_BUILDING" }

-- groups: 100 factory only (station 1000: industry 500, no homes)
--         200 town only (station 2000: town building 601)
--         300 town + factory (station 3000: industry 500, town buildings 601 and 602)
--         400 factory whose catchable is a separate stock list 811 (not an industry: no fallback scan)
--         700 dock: no industry, no town buildings (only another station's workplace 900 in reach)
-- As in game, the factory's own workplaces are passenger catchables too (500 at 1000/3000); only
-- town buildings count as homes. Town buildings and industries hold their own stock list and
-- person capacity.
local world = {
	groups = { [100] = { stations = { 1000 } }, [200] = { stations = { 2000 } }, [300] = { stations = { 3000 } },
		[400] = { stations = { 4000 } }, [700] = { stations = { 7000 } } },
	cargo = { [1000] = { 500 }, [2000] = { 601 }, [3000] = { 601, 500 }, [4000] = { 811 }, [7000] = {} },
	pax = { [1000] = { 500 }, [2000] = { 601 }, [3000] = { 500, 602 }, [4000] = { 810 }, [7000] = { 900 } },
	industries = { [500] = { stockList = 500 }, [810] = { stockList = 811 } },
	townBuildings = { [601] = { personCapacity = 601 }, [602] = { personCapacity = 602 } },
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

local function via(group, load)
	return { stop = { stationGroup = group, passThroughStopData = { stopConfig = stopConfig(load) } } }
end

local function loads(line)
	local out = {}
	for _i, v in ipairs(line.path) do
		if v.stop then out[#out + 1] = v.stop.passThroughStopData.stopConfig.load end
	end
	return out
end

local fakeLineUtil, patch, baseCalls, paxFetches, cargoFetches, componentReads

before_each(function()
	reset_modules()
	clear_logs()
	baseCalls = 0
	paxFetches = 0
	cargoFetches = 0
	componentReads = 0
	set_global("api", {
		type = { ComponentType = CT },
		engine = {
			getComponent = function(e, t)
				componentReads = componentReads + 1
				if t == CT.STATION_GROUP then return world.groups[e] end
				if t == CT.INDUSTRY then return world.industries[e] end
				if t == CT.TOWN_BUILDING then return world.townBuildings[e] end
			end,
			forEachEntityWithComponent = function()
				error("full entity scan on the GUI thread")
			end,
			system = { catchmentAreaSystem = { getStationCatchables = function(st, cargo)
				if cargo then
					cargoFetches = cargoFetches + 1
					return world.cargo[st] or {}
				end
				paxFetches = paxFetches + 1
				return world.pax[st] or {}
			end } },
		},
	})
	-- the base autoLoadConfig: passengers on at every stop (as addPassengerByDefault)
	fakeLineUtil = {
		autoLoadConfig = function(line)
			baseCalls = baseCalls + 1
			if line.customFilters then return end
			for _i, v in ipairs(line.path) do
				if v.stop then
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

test("factory-only stop cleared, town stop kept, other cargo flags untouched", function()
	local line = { path = { via(100, { false, false, true }), { waypoint = {} }, via(200, { false, true, false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(baseCalls, 1, "original called")
	eq(loads(line), { { false, false, true }, { true, true, false } })
end)

test("town station that also reaches the factory keeps passengers", function()
	local line = { path = { via(300, { false, false }), via(100, { false, false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true, false }, { false, false } })
end)

test("a 1-stop line at a factory: passengers off right away", function()
	local line = { path = { via(100, { false, true }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false, true } })
end)

test("a catchable that is not itself an industry keeps passengers (no fallback scan)", function()
	local line = { path = { via(400, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true } })
end)

test("factory -> dock: both stops cleared", function()
	local line = { path = { via(100, { false, true }), via(700, { false, false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false, true }, { false, false } })
end)

test("dock -> town without a factory keeps passengers", function()
	local line = { path = { via(700, { false }), via(200, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true }, { true } })
	eq(cargoFetches, 1, "only the dock (no homes) is tested for an industry")
end)

test("town line: one passenger fetch and one home test per group, no cargo scan", function()
	local line = { path = { via(200, { false }), via(300, { false }), via(200, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { true }, { true }, { true } })
	eq(paxFetches, 2)
	eq(cargoFetches, 0)
	-- 2 STATION_GROUP reads + 601 (home) at 2000 + 500 (workplace), 602 (home) at 3000
	eq(componentReads, 5)
end)

test("factory -> dock -> town: town stop keeps passengers", function()
	local line = { path = { via(100, { false }), via(700, { false }), via(200, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(loads(line), { { false }, { false }, { true } })
end)

test("passenger catchables fetched once per group", function()
	local line = { path = { via(200, { false }), via(100, { false }), via(200, { false }), via(100, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(paxFetches, 2, "once per distinct group, not per stop")
	eq(cargoFetches, 1, "only group 100 reaches no homes")
	eq(loads(line), { { true }, { false }, { true }, { false } })
end)

test("customFilters lines are skipped", function()
	local line = { customFilters = true, path = { via(100, { true, false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(baseCalls, 1)
	eq(loads(line), { { true, false } }, "manual filters untouched")
end)

test("one log line per cleared stop, none for kept stops", function()
	clear_logs()
	local line = { path = { via(100, { false }), via(200, { false }), via(300, { false }), via(700, { false }) } }
	fakeLineUtil.autoLoadConfig(line)
	eq(messages(), {
		"[NoFactoryPassengers] stop 1 group 100: industry in reach, no town buildings -> passengers OFF",
		"[NoFactoryPassengers] stop 4 group 700: no town buildings, line serves an industry-only stop -> passengers OFF",
	})
end)

test("wrapping is idempotent", function()
	local wrapped = fakeLineUtil.autoLoadConfig
	patch.doReplace({})
	ok(not patch.install(fakeLineUtil), "second install is a no-op")
	ok(fakeLineUtil.autoLoadConfig == wrapped)
	fakeLineUtil.autoLoadConfig({ path = { via(200, { false }) } })
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
