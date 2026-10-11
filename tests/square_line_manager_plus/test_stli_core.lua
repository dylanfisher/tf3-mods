-- stli_core.lua: model grouping, text lines, line check, collection with failing calls, the 1 s cache.

local core = ug_require "square_line_manager_plus::/line_manager_plus/stli_core.lua"

-- plain formatting stand-ins: {name} placeholders filled, ints as decimals
local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end
local fmt = {
	format = format,
	int = function(n) return tostring(n) end,
	percent = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
	minutes = function(s) return string.format("%d:%02d", s // 60, s % 60) end,
}

test("groupModels: most vehicles first, ties by name, empty names counted as ?", function()
	local g = core.groupModels({ "Bus B", "Bus A", "Bus B", "", "Bus A", "Bus B", nil })
	eq(g, { { name = "Bus B", count = 3 }, { name = "Bus A", count = 2 }, { name = "?", count = 1 } })
	eq(core.groupModels({}), {})
	eq(core.groupModels(nil), {})
end)

test("formatLines: vehicles, model rows and one stats row", function()
	local lines = core.formatLines({
		names = { "Foo", "Bar", "Foo", "Foo" }, capacity = 120, utilization = 0.45, frequency = 200, rate = 1200,
	}, fmt)
	eq(lines, {
		"Vehicles on this line: 4",
		"3× Foo",
		"1× Bar",
		"Capacity: 120  ·  Utilization: 45%  ·  Frequency: 3:20  ·  Rate: 1200",
	})
end)

test("formatLines: no vehicles, failed stats left out", function()
	local lines = core.formatLines({ names = {}, capacity = 0, frequency = 0 }, fmt)
	eq(lines, { "No vehicles on this line.", "Capacity: 0  ·  Frequency: 0:00" })
	eq(core.formatLines({}, fmt), { "No vehicles on this line." })
end)

test("formatLines: more than MAX_GROUPS models are summed into one row", function()
	local names = {}
	for i = 1, 8 do
		for _j = 1, 9 - i do names[#names + 1] = "M" .. i end
	end
	local lines = core.formatLines({ names = names }, fmt)
	eq(#lines, 1 + core.MAX_GROUPS + 1)
	eq(lines[2], "8× M1")
	eq(lines[6], "4× M5")
	eq(lines[7], "6× other models") -- M6 3 + M7 2 + M8 1
end)

test("formatLines: exactly one model too many is shown, not summed", function()
	local names = {}
	for i = 1, core.MAX_GROUPS + 1 do names[i] = "M" .. i end
	local lines = core.formatLines({ names = names }, fmt)
	eq(#lines, 1 + core.MAX_GROUPS + 1)
	eq(lines[#lines], "1× M6")
end)

-- a fake game: lines with vehicles, vehicles with model ids or multiple units
local world, calls, warnings, now

local function fakeApi()
	return {
		type = { ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" } },
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil or world.vehicles[e] ~= nil or world.other[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] and {} or nil end
				if ct == "TV" then return world.vehicles[e] end
			end,
			system = { transportVehicleSystem = { getLineVehicles = function(line)
				calls.vehicles = calls.vehicles + 1
				return world.lines[line]
			end } },
			util = { line = { calcLineStationThroughput = function(line)
				if world.failRate then error("rate boom") end
				return 1000 + line
			end } },
		},
		res = {
			modelRep = { get = function(id) return { metadata = { description = { name = world.models[id] } } } end },
			multipleUnitRep = {
				find = function(name) return world.mus[name] and 7 or -1 end,
				get = function(_id) return { name = "MU Set" } end,
			},
		},
	}
end

local function vehicle(modelId, mu)
	return { transportVehicleConfig = { vehicles = { { part = { modelId = modelId } } }, muFileNames = mu and { mu } or {} } }
end

local function newModel()
	return core.new({
		api = fakeApi(),
		stats = { calculateCargoColumnDataForLine = function(_line)
			if world.failCargo then error("cargo boom") end
			return { demand = 90, coverage = 0.5 }
		end },
		lineUtil = { calculateFrequencySeconds = function(_line) return 75 end },
		fmt = fmt,
		now = function() return now end,
		warn = function(key, err) warnings[#warnings + 1] = key .. ": " .. tostring(err) end,
	})
end

before_each(function()
	world = {
		lines = { [1] = { 11, 12, 13 }, [2] = {} },
		vehicles = { [11] = vehicle(100), [12] = vehicle(100), [13] = vehicle(200, "res/mu/set.mu") },
		models = { [100] = "Bus A", [200] = "Train car" },
		mus = { ["res/mu/set.mu"] = true },
		other = { [5] = true },
	}
	calls, warnings, now = { vehicles = 0 }, {}, 1e9
end)

test("isLine: only existing entities with a LINE component", function()
	local m = newModel()
	ok(m.isLine(1))
	ok(not m.isLine(5)) -- exists, not a line
	ok(not m.isLine(99)) -- gone
	ok(not m.isLine(-1))
	ok(not m.isLine(nil))
	ok(not m.isLine("1"))
end)

test("lines: models (multiple unit name first), stats, nil for a non-line", function()
	local m = newModel()
	eq(m.lines(1), {
		"Vehicles on this line: 3",
		"2× Bus A",
		"1× MU Set",
		"Capacity: 90  ·  Utilization: 50%  ·  Frequency: 1:15  ·  Rate: 1001",
	})
	eq(m.lines(2)[1], "No vehicles on this line.")
	eq(m.lines(5), nil)
	eq(m.lines(99), nil)
	eq(warnings, {})
end)

test("lines: a failing stat is left out and logged, the rest still shows", function()
	world.failCargo, world.failRate = true, true
	local m = newModel()
	eq(m.lines(1)[4], "Frequency: 1:15")
	eq(#warnings, 2)
	ok(warnings[1]:find("cargo boom", 1, true))
	ok(warnings[2]:find("rate boom", 1, true))
end)

test("lines: a vehicle whose model can't be read shows as ?", function()
	world.vehicles[12] = { transportVehicleConfig = { vehicles = {} } } -- no parts, no muFileNames
	world.vehicles[11] = nil -- component gone
	local m = newModel()
	local lines = m.lines(1)
	eq(lines[1], "Vehicles on this line: 3")
	eq(lines[2], "2× ?")
	eq(lines[3], "1× MU Set")
end)

test("lines: cached for 1 s per line, then read again", function()
	local m = newModel()
	m.lines(1)
	m.lines(1)
	eq(calls.vehicles, 1)
	now = now + core.CACHE_US - 1
	m.lines(1)
	eq(calls.vehicles, 1)
	m.lines(2)
	eq(calls.vehicles, 2)
	now = now + 1
	world.lines[1] = { 11 }
	eq(m.lines(1)[1], "Vehicles on this line: 1")
	eq(calls.vehicles, 3)
	-- a clock that went backwards doesn't keep a stale entry forever
	now = now - 5 * core.CACHE_US
	m.lines(1)
	eq(calls.vehicles, 4)
end)

test("lines: a line deleted after caching is no longer shown once the entry expires", function()
	local m = newModel()
	ok(m.lines(1) ~= nil)
	world.lines[1] = nil
	now = now + core.CACHE_US
	eq(m.lines(1), nil)
end)

test("lines: the cache is cleared when it gets too big", function()
	local m = newModel()
	for i = 1, core.CACHE_MAX + 3 do world.lines[100 + i] = {} end
	for i = 1, core.CACHE_MAX + 3 do m.lines(100 + i) end
	ok(m.size <= core.CACHE_MAX)
	ok(m.size >= 1)
end)

test("lines: errors from the vehicle list propagate (the script's pcall catches them)", function()
	local m = newModel()
	m = core.new({
		api = (function()
			local a = fakeApi()
			a.engine.system.transportVehicleSystem.getLineVehicles = function() error("list boom") end
			return a
		end)(),
		stats = { calculateCargoColumnDataForLine = function() return { demand = 1, coverage = 0 } end },
		lineUtil = { calculateFrequencySeconds = function() return 0 end },
		fmt = fmt, now = function() return now end, warn = function() end,
	})
	raises(function() m.lines(1) end, "list boom")
end)
