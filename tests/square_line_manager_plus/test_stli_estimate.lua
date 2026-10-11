-- Send to Line before -> after estimate (PLAN.md feature 2): stli_core.estimate / vehicleCapacity / formatLines with
-- after-values, the model's selection path (vehicles already on the line, cargo the line doesn't carry, a line
-- without vehicles, failures that only drop the arrows, the cache per selection), stli.lua passing the captured
-- selection only when its count matches, and stli_estimate.lua's install.

local core = ug_require "square_line_manager_plus::/line_manager_plus/stli_core.lua"

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end
local fmt = {
	format = format,
	int = function(n) return tostring(n) end,
	percent = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
	minutes = function(s) return string.format("%d:%02d", s // 60, s % 60) end,
}

-- estimate ------------------------------------------------------------------------------------------------------

test("estimate: capacity adds, frequency n/(n+k), rate scales with capacity", function()
	local info = { n = 2, capacity = 40, frequency = 439, rate = 66 }
	eq(core.estimate(info, { k = 2, add = 40 }), { capacity = 80, frequency = 220, rate = 132 })
	-- 7:19 with 2 vehicles, 1 more -> 4:53 (439 * 2 / 3 = 292.67 -> 293)
	eq(core.estimate(info, { k = 1, add = 20 }), { capacity = 60, frequency = 293, rate = 99 })
end)

test("estimate: identical vehicles give the verified linear rate rule rate * (n + k) / n", function()
	-- docs/findings.md "Line Rate": 1 / 2 / 3 identical ships -> 51 / 103 / 154
	eq(core.estimate({ n = 1, capacity = 100, frequency = 600, rate = 51 }, { k = 1, add = 100 }).rate, 102)
	eq(core.estimate({ n = 1, capacity = 100, frequency = 600, rate = 51 }, { k = 2, add = 200 }).rate, 153)
end)

test("estimate: k = 0 (all already on the line) or no selection gives no after-values", function()
	local info = { n = 3, capacity = 60, frequency = 300, rate = 90 }
	eq(core.estimate(info, { k = 0, add = 0 }), {})
	eq(core.estimate(info, nil), {})
	eq(core.estimate(info, {}), {})
end)

test("estimate: a line without vehicles gets capacity only (no round trip, rate 0)", function()
	eq(core.estimate({ n = 0, capacity = 0, frequency = 0, rate = 0 }, { k = 2, add = 50 }), { capacity = 50 })
end)

test("estimate: vehicles that carry nothing of the line's cargo change frequency only (no division by 0)", function()
	eq(core.estimate({ n = 2, capacity = 40, frequency = 400, rate = 60 }, { k = 2, add = 0 }), { frequency = 200 })
	-- capacity 0 with vehicles on the line: no rate estimate
	eq(core.estimate({ n = 2, capacity = 0, frequency = 400, rate = 60 }, { k = 1, add = 30 }),
		{ capacity = 30, frequency = 267 })
end)

test("estimate: missing stats and values that round to the same number get no arrow", function()
	eq(core.estimate({ n = 2 }, { k = 1, add = 10 }), {})
	-- 1 s interval * 100 / 101 rounds to 1
	eq(core.estimate({ n = 100, capacity = 1000, frequency = 1, rate = 10000 }, { k = 1, add = 0 }), {})
end)

-- vehicleCapacity -------------------------------------------------------------------------------------------------

test("vehicleCapacity: load config for the line's cargo, else the best allCaps entry, else 0", function()
	-- index = cargo id + 1; passengers (id 0) at 1, cargo id 3 at 4
	eq(core.vehicleCapacity({ 20, 0, 0, 0 }, { 20, 0, 0, 0 }, { [1] = true }), 20)
	eq(core.vehicleCapacity({ 0, 0, 0, 12 }, { 0, 0, 10, 12 }, { [1] = true, [4] = true }), 12)
	-- set to another cargo now, can load the line's cargo after a reconfiguration
	eq(core.vehicleCapacity({ 0, 0, 10, 0 }, { 0, 0, 10, 14 }, { [4] = true }), 14)
	-- can't carry it at all
	eq(core.vehicleCapacity({ 20 }, { 20 }, { [4] = true }), 0)
	eq(core.vehicleCapacity(nil, nil, { [4] = true }), 0)
end)

test("vehicleCapacity: unknown cargo (line without capacity) counts the vehicle's load config", function()
	eq(core.vehicleCapacity({ 20, 0, 5 }, { 20, 9, 5 }, nil), 25)
	eq(core.vehicleCapacity(nil, nil, nil), 0)
end)

-- formatLines -----------------------------------------------------------------------------------------------------

test("formatLines: after-values add arrows and split the stats into two rows", function()
	local lines = core.formatLines({ names = { "Bus" }, capacity = 40, utilization = 0.5, frequency = 439, rate = 66 },
		fmt, { capacity = 80, frequency = 293, rate = 132 })
	eq(lines, {
		"Vehicles on this line: 1",
		"1× Bus",
		"Capacity: 40 → ~80  ·  Utilization: 50%",
		"Frequency: 7:19 → ~4:53  ·  Rate: 66 → ~132",
	})
end)

test("formatLines: no after-values (or only a cantCarry of 0) keeps the one-row form", function()
	local info = { names = {}, capacity = 40, utilization = 0.5, frequency = 283, rate = 103 }
	local plain = { "No vehicles on this line.", "Capacity: 40  ·  Utilization: 50%  ·  Frequency: 4:43  ·  Rate: 103" }
	eq(core.formatLines(info, fmt), plain)
	eq(core.formatLines(info, fmt, {}), plain)
	eq(core.formatLines(info, fmt, { cantCarry = 0 }), plain)
end)

test("formatLines: one stat with an arrow, the others plain; cantCarry adds a line", function()
	local lines = core.formatLines({ names = {}, capacity = 0, utilization = 0, frequency = 0, rate = 0 }, fmt,
		{ capacity = 50, cantCarry = 1 })
	eq(lines, {
		"No vehicles on this line.",
		"Capacity: 0 → ~50  ·  Utilization: 0%",
		"Frequency: 0:00  ·  Rate: 0",
		"Selected vehicles that can't carry this line's cargo: 1",
	})
end)

test("formatLines: placeholders go through the language's format string in its own order", function()
	local saved = _
	set_global("_", function(s)
		if s == "{label}: {before} → ~{after}" then return "[{after}<-{before}] {label}" end
		return s
	end)
	local lines = core.formatLines({ names = {}, capacity = 10 }, fmt, { capacity = 30 })
	set_global("_", saved)
	eq(lines[2], "[30<-10] Capacity")
end)

-- the model's selection path ------------------------------------------------------------------------------------

local world, warnings, now, calls

local function tv(line, caps, allCaps)
	return {
		line = line,
		config = { capacities = caps, allCaps = allCaps or caps },
		transportVehicleConfig = { vehicles = { { part = { modelId = 100 } } }, muFileNames = {} },
	}
end

local function newModel()
	local api = {
		type = { ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" } },
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] and {} or nil end
				if ct == "TV" then
					if world.failTv and world.failTv[e] then error("tv boom") end
					return world.vehicles[e]
				end
			end,
			system = { transportVehicleSystem = { getLineVehicles = function(line)
				calls.vehicles = calls.vehicles + 1
				return world.lines[line]
			end } },
			util = { line = {
				calcLineStationThroughput = function() return world.rate end,
				getLineCapacityUsages = function(line, all)
					eq(all, false)
					calls.usages = calls.usages + 1
					if world.failUsages then error("usages boom") end
					return world.usages[line] or {}
				end,
			} },
		},
		res = { modelRep = { get = function() return { metadata = { description = { name = "Bus" } } } end } },
	}
	return core.new({
		api = api,
		stats = { calculateCargoColumnDataForLine = function() return { demand = world.capacity, coverage = 0.5 } end },
		lineUtil = { calculateFrequencySeconds = function() return world.frequency end },
		fmt = fmt,
		now = function() return now end,
		warn = function(key, err) warnings[#warnings + 1] = key .. ": " .. tostring(err) end,
	})
end

before_each(function()
	world = {
		-- line 1: two buses (passengers, cargo id 0 -> index 1), line 2: empty, line 3: a truck line (cargo id 3)
		lines = { [1] = { 11, 12 }, [2] = {}, [3] = { 31 } },
		vehicles = {
			[11] = tv(1, { 20 }), [12] = tv(1, { 20 }),
			[21] = tv(-1, { 20 }), [22] = tv(5, { 20 }), -- a bus in the depot, a bus on another line
			[31] = tv(3, { 0, 0, 0, 12 }),
		},
		usages = { [1] = { [1] = { capacity = 40, used = 20 } }, [3] = { [4] = { capacity = 12, used = 0 } } },
		capacity = 40, frequency = 439, rate = 66,
	}
	warnings, now, calls = {}, 1e9, { vehicles = 0, usages = 0 }
end)

test("lines with vehicles: two buses to a bus line double capacity and rate, halve the interval", function()
	local m = newModel()
	eq(m.lines(1, { 21, 22 }), {
		"Vehicles on this line: 2",
		"2× Bus",
		"Capacity: 40 → ~80  ·  Utilization: 50%",
		"Frequency: 7:19 → ~3:40  ·  Rate: 66 → ~132",
	})
	eq(warnings, {})
end)

test("lines: vehicles already on the line don't count; all on it -> no arrows", function()
	local m = newModel()
	eq(m.lines(1, { 11, 12 })[3], "Capacity: 40  ·  Utilization: 50%  ·  Frequency: 7:19  ·  Rate: 66")
	-- one of two already there: k = 1
	eq(m.lines(1, { 11, 21 })[3], "Capacity: 40 → ~60  ·  Utilization: 50%")
	eq(m.lines(1, { 11, 21 })[4], "Frequency: 7:19 → ~4:53  ·  Rate: 66 → ~99")
end)

test("lines: buses sent to a truck line add no capacity and get a note", function()
	world.capacity, world.frequency, world.rate = 12, 600, 30
	local m = newModel()
	local lines = m.lines(3, { 21, 22 })
	eq(lines[3], "Capacity: 12  ·  Utilization: 50%")
	eq(lines[4], "Frequency: 10:00 → ~3:20  ·  Rate: 30")
	eq(lines[5], "Selected vehicles that can't carry this line's cargo: 2")
end)

test("lines: a line without vehicles gets the capacity estimate only, no note", function()
	world.capacity, world.frequency, world.rate = 0, 0, 0
	local m = newModel()
	eq(m.lines(2, { 21, 22 }), {
		"No vehicles on this line.",
		"Capacity: 0 → ~40  ·  Utilization: 50%",
		"Frequency: 0:00  ·  Rate: 0",
	})
end)

test("lines: a failing estimate drops only the arrows and is logged once", function()
	world.failTv = { [21] = true } -- only the selected vehicle; the line's own still read
	local m = newModel()
	local lines = m.lines(1, { 21 })
	eq(lines[3], "Capacity: 40  ·  Utilization: 50%  ·  Frequency: 7:19  ·  Rate: 66")
	eq(#warnings, 1)
	ok(warnings[1]:find("tv boom", 1, true))
end)

test("lines: failing cargo usages fall back to the vehicles' load config (no note)", function()
	world.failUsages = true
	local m = newModel()
	local lines = m.lines(1, { 21 })
	eq(lines[3], "Capacity: 40 → ~60  ·  Utilization: 50%")
	eq(#lines, 4)
	eq(#warnings, 1)
end)

test("lines: line stats cached per line, the text per selection; cargo set read once per entry", function()
	local m = newModel()
	m.lines(1)
	m.lines(1, { 21 })
	m.lines(1, { 21 })
	m.lines(1, { 21, 22 })
	eq(calls.vehicles, 1)
	eq(calls.usages, 1)
	-- the plain text is still the plain one
	eq(m.lines(1)[3], "Capacity: 40  ·  Utilization: 50%  ·  Frequency: 7:19  ·  Rate: 66")
	-- many different selections within one entry: the texts are cleared, not grown without bound
	for i = 1, core.TEXTS_MAX * 2 do m.lines(1, { 1000 + i }) end
	local n = 0
	for _k in pairs(m.cache[1].texts) do n = n + 1 end
	ok(n <= core.TEXTS_MAX)
	now = now + core.CACHE_US
	m.lines(1, { 21 })
	eq(calls.vehicles, 2)
	eq(calls.usages, 2)
end)

-- stli.lua with the estimate on, and stli_estimate.lua's install ------------------------------------------------

local selected, stliCalls

local function setupScript(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	selected, stliCalls = { 21, 22 }, {}
	set_global("api", { type = { Clock = { new = function() return { getTime = function() return 1e9 end } end } } })
	local recipeIds = {}
	local react = {
		RegisterRecipe = function(name, fn)
			local r = function(p) return fn(p) end
			recipeIds[r] = name
			return r
		end,
		GetRecipeId = function(fn) return recipeIds[fn] end,
		CallOriginalRecipe = function() return { kind = "Vanilla" } end,
	}
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", {
		type = { Orientation = { Vertical = "V" } },
		BoxLayout = function(p) return { kind = "BoxLayout", children = p.children } end,
		TextView = function(p) return { kind = "TextView", text = p.text } end,
	})
	stub_module("::/gui/line_vehicle_mgmt/manager_tooltips_util.tl",
		{ VMSendToLine = react.RegisterRecipe("VMSendToLine", function() end) })
	stub_module("square_line_manager_plus::/line_manager_plus/lmp_stats.lua", { lines = function(entity, vehicles)
		stliCalls[#stliCalls + 1] = { entity = entity, vehicles = vehicles }
		return { "stats" }
	end })
	stub_module("square_line_manager_plus::/line_manager_plus/lmp_capture.lua", {
		install = function() return opts.captureFails ~= true end,
		selectedVehicles = function()
			if opts.selectionError then error("selection boom") end
			return selected
		end,
	})
	local stli = ug_require "square_line_manager_plus::/line_manager_plus/stli.lua"
	local est = ug_require "square_line_manager_plus::/line_manager_plus/stli_estimate.lua"
	return stli, est
end

local RAPI = { ReplaceRecipe = function() end }

local function warningCount()
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" then n = n + 1 end
	end
	return n
end

test("estimate install: needs Send to Line info installed; then passes the matching selection", function()
	local stli, est = setupScript()
	ok(not est.install(RAPI))
	stli.SendToLineInfo({ numVehicles = 2, lineOrDepotEntity = 1 })
	eq(stliCalls[1].vehicles, nil)
	ok(stli.install(RAPI))
	ok(est.install(RAPI))
	stli.SendToLineInfo({ numVehicles = 2, lineOrDepotEntity = 1 })
	eq(stliCalls[2].vehicles, { 21, 22 })
	eq(warningCount(), 0)
end)

test("estimate: a selection whose count differs from the tooltip's gets current values only", function()
	local stli, est = setupScript()
	stli.install(RAPI)
	est.install(RAPI)
	stli.SendToLineInfo({ numVehicles = 3, lineOrDepotEntity = 1 })
	eq(stliCalls[1].vehicles, nil)
	selected = {}
	stli.SendToLineInfo({ numVehicles = 0, lineOrDepotEntity = 1 })
	eq(stliCalls[2].vehicles, nil)
end)

test("estimate: a failing selection read keeps the info (no arrows) and warns once", function()
	local stli, est = setupScript({ selectionError = true })
	stli.install(RAPI)
	est.install(RAPI)
	for _i = 1, 3 do
		local node = stli.SendToLineInfo({ numVehicles = 2, lineOrDepotEntity = 1 })
		eq(node.children[2].text, "stats")
	end
	eq(stliCalls[3].vehicles, nil)
	eq(warningCount(), 1)
end)

test("estimate install: a capture that can't install leaves the estimate off", function()
	local stli, est = setupScript({ captureFails = true })
	stli.install(RAPI)
	ok(not est.install(RAPI))
	stli.SendToLineInfo({ numVehicles = 2, lineOrDepotEntity = 1 })
	eq(stliCalls[1].vehicles, nil)
	eq(warningCount(), 1)
end)
