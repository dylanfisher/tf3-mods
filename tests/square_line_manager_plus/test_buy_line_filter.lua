-- Line Manager Plus "Buy Vehicles: line's cargo filter" (buy_line_filter.lua) with fake base modules and a fake api.
-- Covers: install (wraps once, keeps the base results, skips when a base function is missing), the Buy Vehicles click
-- (getBestDepotForLine) arming a one-cargo line only, the store's first filter getting the cargo for the matching
-- carrier and tags within the time window only, the marker surviving the store's deep copies (rail: locomotive tab
-- first, wagon tab ticks it; a ticked or cleared filter on a tab with the bar is left alone), another store never
-- getting it, errors in our part logged once without touching the base result, and the quiet depot read
-- (bestDepotQuiet, the Rate Matcher's estimate) arming nothing.

local script, su, lu, cu, vu, nowUs, lineTypes, failTypes, lineStops, vehicles

local PASS = 0
local COAL = 5
local BUS, TRAIN = "ROAD", "RAIL"

local function copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[copy(k)] = copy(v) end
	return r
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	nowUs, failTypes = 1e9, false
	lineTypes = { [1] = { PASS }, [2] = { PASS, 7 }, [3] = {}, [4] = { COAL } }
	-- stop load configs (index = cargo + 1) of lines without vehicles: the fallback when capacity gives no cargo
	lineStops = {}
	-- vehicle -> TRANSPORT_VEHICLE (line, carrier) for the Replace / Modify store
	vehicles = { [101] = { line = 4, carrier = BUS }, [102] = { line = 4, carrier = BUS },
		[103] = { line = 2, carrier = BUS }, [104] = { line = -1, carrier = BUS } }
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return nowUs end } end },
			ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" },
		},
		engine = { getComponent = function(e, ct)
			if ct == "TV" then return vehicles[e] end
			eq(ct, "LINE")
			local loads = lineStops[e]
			if not loads then return nil end
			local stops = {}
			for i, l in ipairs(loads) do stops[i] = { stopConfig = { load = l } } end
			return { stops = stops }
		end },
	})
	-- the base vehicle_store_util.tl:799-900 handlers, reduced to what decides the cargo filter bar
	local function finish(f)
		if not su.showCargoFilters(f) then f.cargoFilters = {} end
		return f
	end
	su = {
		showCargoFilters = function(f) return (f.withCargoCapacity or f.withCapacity) or false end,
		getDepotFilterTags = function(depot) return depot == 30 and { "europe" } or {} end,
		handleDefaultCarrier = function(f)
			f.withCapacity = nil
			f.withPassengerCapacity, f.withCargoCapacity = true, true
			return finish(f)
		end,
		handleRailCarrier = function(f, _ids, index)
			f.withCapacity, f.withCargoCapacity = nil, nil
			if index == 1 then f.withCapacity = false -- locomotive
			elseif index == 2 then f.withCargoCapacity = true -- wagon
			elseif index == 3 then f.withCapacity = true end -- multiple unit
			return finish(f)
		end,
		handleTramCarrier = function(f) return finish(f) end,
		getVehicleFilterTags = function(ids) return #ids == 1 and ids[1] == 102 and { "europe" } or {} end,
	}
	if opts.noShow then su.showCargoFilters = nil end
	lu = { getBestDepotForLine = function(line) return line == 99 and -1 or 10 * line end }
	cu = { getSortedProducedCargoTypes = function(params, order, passengersFirst, filterFn, allCaps)
		if failTypes then error("types boom") end
		eq(order, "CAPACITY"); eq(passengersFirst, nil); eq(filterFn, nil); eq(allCaps, true)
		ok(params.showEmpty == true)
		return lineTypes[params.lineEntity] or {}
	end }
	vu = { getDepotCarrier = function(depot) return depot == 40 and TRAIN or BUS end }
	stub_module("::/gui/line_vehicle_mgmt/vehicle_store_util.tl", su)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", lu)
	stub_module("::/gui/main/cargo_util.tl", cu)
	stub_module("::/gui/line_vehicle_mgmt/vehicle_util.tl", vu)
	script = ug_require "square_line_manager_plus::/line_manager_plus/buy_line_filter.lua"
end

-- the store's first filter (vehicle_store_window.tl:2511-2539)
local function storeFilter(carrier, tags, tab)
	local f = { carrier = carrier, filterTags = tags or {}, text = "", cargoFilters = {}, engines = {} }
	if carrier == TRAIN then return su.handleRailCarrier(f, {}, tab or 1) end
	return su.handleDefaultCarrier(f)
end

-- a tab change (vehicle_store_window.tl:2829): a deep copy of the current filter through the handler
local function tabChange(f, tab)
	if f.carrier == TRAIN then return su.handleRailCarrier(copy(f), {}, tab) end
	return su.handleDefaultCarrier(copy(f))
end

local function countWarnings()
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" then n = n + 1 end
	end
	return n
end

test("install wraps once and keeps the base results", function()
	setup()
	local origDepot = lu.getBestDepotForLine
	ok(script.install())
	ok(lu.getBestDepotForLine ~= origDepot)
	local wrapped = lu.getBestDepotForLine
	ok(script.install())
	ok(lu.getBestDepotForLine == wrapped)
	eq(lu.getBestDepotForLine(2), 20)
	eq(lu.getBestDepotForLine(99), -1)
	local f = storeFilter(BUS)
	eq(f.cargoFilters, {})
	eq(f.withCargoCapacity, true)
end)

test("install: a missing base function wraps nothing and warns once", function()
	setup({ noShow = true })
	local origDepot, origDefault = lu.getBestDepotForLine, su.handleDefaultCarrier
	ok(not script.install())
	ok(lu.getBestDepotForLine == origDepot)
	ok(su.handleDefaultCarrier == origDefault)
	eq(countWarnings(), 1)
end)

test("a passenger-only line: the store opens with passengers ticked", function()
	setup()
	script.install()
	eq(lu.getBestDepotForLine(1), 10)
	local f = storeFilter(BUS)
	eq(f.cargoFilters, { [PASS] = true })
	eq(f[script.MARK], PASS)
	-- re-renders rebuild the (discarded) first filter the same way while the click is recent
	eq(storeFilter(BUS).cargoFilters, { [PASS] = true })
	-- the search tab (default carrier, bar shown before and after) leaves the player's choice alone
	f.cargoFilters = {}
	eq(tabChange(f, 0).cargoFilters, {})
	eq(countWarnings(), 0)
end)

test("lines with several or no cargo types, and no depot, arm nothing", function()
	setup()
	script.install()
	for _i, line in ipairs({ 2, 3, 99 }) do
		lu.getBestDepotForLine(line)
		local f = storeFilter(BUS)
		eq(f.cargoFilters, {})
		eq(f[script.MARK], nil)
	end
end)

test("the cargo the stops load decides, also without vehicles (one type only)", function()
	setup()
	script.install()
	-- line 5: no capacity yet; stop 1 loads coal (index COAL + 1), stop 2 loads nothing
	lineStops[5] = { { false, false, false, false, false, true }, {} }
	lu.getBestDepotForLine(5)
	local f = storeFilter(BUS)
	eq(f.cargoFilters, { [COAL] = true })
	eq(f[script.MARK], COAL)
	-- two cargo types loaded: nothing
	lineStops[6] = { { true }, { false, false, false, false, false, true } }
	nowUs = nowUs + 2 * script.PENDING_US
	lu.getBestDepotForLine(6)
	eq(storeFilter(BUS).cargoFilters, {})
	-- the stops win over the vehicles: line 2's vehicles carry two types, its stops load only coal
	lineStops[2] = { { false, false, false, false, false, true }, {} }
	nowUs = nowUs + 2 * script.PENDING_US
	lu.getBestDepotForLine(2)
	eq(storeFilter(BUS).cargoFilters, { [COAL] = true })
	-- and the other way: one type of capacity, but the stops load two
	lineStops[4] = { { true }, { false, false, false, false, false, true } }
	nowUs = nowUs + 2 * script.PENDING_US
	lu.getBestDepotForLine(4)
	eq(storeFilter(BUS).cargoFilters, {})
	eq(countWarnings(), 0)
end)

test("Replace / Modify: vehicles of one one-cargo line open the store with its cargo", function()
	setup()
	script.install()
	eq(su.getVehicleFilterTags({ 101, 102 }), {})
	local f = storeFilter(BUS, {})
	eq(f.cargoFilters, { [COAL] = true })
	eq(f[script.MARK], COAL)
	-- the tags the base returned must match the store's
	eq(su.getVehicleFilterTags({ 102 }), { "europe" })
	eq(storeFilter(BUS, {}).cargoFilters, {})
	eq(su.getVehicleFilterTags({ 102 }), { "europe" })
	eq(storeFilter(BUS, { "europe" }).cargoFilters, { [COAL] = true })
	-- two lines, a mixed-cargo line, a vehicle without a line: nothing, and the call clears an earlier arm
	for _i, ids in ipairs({ { 101, 103 }, { 103 }, { 104 }, {} }) do
		su.getVehicleFilterTags({ 101 })
		su.getVehicleFilterTags(ids)
		eq(storeFilter(BUS, {}).cargoFilters, {})
	end
	eq(countWarnings(), 0)
end)

test("bestDepotQuiet: the base depot, nothing armed, the wrapper arms again after; errors pass through", function()
	setup()
	ok(script.install())
	eq(script.bestDepotQuiet(lu, 1), 10)
	eq(storeFilter(BUS).cargoFilters, {}, "the quiet read armed nothing")
	lu.getBestDepotForLine(1) -- a real click still arms
	eq(storeFilter(BUS).cargoFilters, { [PASS] = true })
	local orig = lu.getBestDepotForLine
	lu.getBestDepotForLine = function() error("depot boom") end
	local okCall, err = pcall(script.bestDepotQuiet, lu, 1)
	eq(okCall, false); ok(tostring(err):find("depot boom") ~= nil)
	lu.getBestDepotForLine = orig
	-- the counter is back at 0 after the error: a click for a mixed line runs our part and clears the filter
	lu.getBestDepotForLine(2)
	eq(storeFilter(BUS).cargoFilters, {})
end)

test("a later click for a mixed line clears an earlier one-cargo click", function()
	setup()
	script.install()
	lu.getBestDepotForLine(1)
	lu.getBestDepotForLine(2)
	eq(storeFilter(BUS).cargoFilters, {})
end)

test("another store (other carrier or tags, or opened too late) is never filtered", function()
	setup()
	script.install()
	lu.getBestDepotForLine(1) -- bus depot 10, no tags
	eq(storeFilter(TRAIN, {}, 2).cargoFilters, {})
	eq(storeFilter(BUS, { "europe" }).cargoFilters, {})
	nowUs = nowUs + script.PENDING_US + 1
	eq(storeFilter(BUS).cargoFilters, {})
	nowUs = nowUs - script.PENDING_US -- expired pending was dropped, not just skipped
	eq(storeFilter(BUS).cargoFilters, {})
end)

test("filter tags must match the depot's", function()
	setup()
	script.install()
	lineTypes[3] = { PASS }
	lu.getBestDepotForLine(3) -- depot 30, tags { "europe" }
	eq(storeFilter(BUS, {}).cargoFilters, {})
	eq(storeFilter(BUS, { "europe" }).cargoFilters, { [PASS] = true })
end)

test("rail: locomotive tab first, the wagon tab ticks the line's cargo, the marker survives copies", function()
	setup()
	script.install()
	lu.getBestDepotForLine(4) -- coal, depot 40 = rail
	local f = storeFilter(TRAIN, {}, 1)
	eq(f.cargoFilters, {}) -- locomotives: no cargo bar
	eq(f[script.MARK], COAL)
	nowUs = nowUs + 10 * script.PENDING_US -- long after the click: the marker alone carries it
	local wagons = tabChange(f, 2)
	eq(wagons.cargoFilters, { [COAL] = true })
	-- wagon -> multiple unit (bar before and after): the player's untick stays
	wagons.cargoFilters = {}
	eq(tabChange(wagons, 3).cargoFilters, {})
	-- locomotives clear the bar (base); back on wagons the line's cargo is ticked again
	local loco = tabChange(wagons, 1)
	eq(loco.cargoFilters, {})
	eq(tabChange(loco, 2).cargoFilters, { [COAL] = true })
	-- an unmarked rail store stays unfiltered
	eq(tabChange(storeFilter(TRAIN, {}, 1), 2).cargoFilters, {})
end)

test("errors in the cargo lookup arm nothing and are logged once", function()
	setup()
	script.install()
	failTypes = true
	for _i = 1, 3 do
		eq(lu.getBestDepotForLine(1), 10)
		eq(storeFilter(BUS).cargoFilters, {})
	end
	eq(countWarnings(), 1)
end)

test("an error in our filter part keeps the base result and logs once", function()
	setup()
	script.install()
	lu.getBestDepotForLine(1)
	su.showCargoFilters = function(f)
		if f[script.MARK] then error("bar boom") end
		return (f.withCargoCapacity or f.withCapacity) or false
	end
	for _i = 1, 3 do
		local f = storeFilter(BUS)
		eq(f.withCargoCapacity, true)
	end
	eq(countWarnings(), 1)
end)
