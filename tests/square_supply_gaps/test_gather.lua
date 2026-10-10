-- sg_gather: engine reads against a fake api (userdata-like load vectors with a non-table
-- metatable, 0-based stop station / terminal indices, pcall skips of failing entities).
-- Shapes: api/tealdef/api/engine.d.tl (LINE, STATION_GROUP, TOWN_BUILDING, STOCK_LIST,
-- PERSON_CAPACITY, TOWN), api/tealdef/api/type.d.tl:1286-1291 (Terminal).

local gather = ug_require "square_supply_gaps::/supply_gaps/sg_gather.tl"

local PASS, FISH, TOOLS, FOOD = 0, 7, 9, 4
local INPUT, OUTPUT = 0, 1

local CT = {
	LINE = "LINE", STATION_GROUP = "STATION_GROUP", STATION = "STATION", TOWN_BUILDING = "TOWN_BUILDING",
	STOCK_LIST = "STOCK_LIST", PERSON_CAPACITY = "PERSON_CAPACITY", BOUNDING_VOLUME = "BOUNDING_VOLUME",
	TOWN = "TOWN", NAME = "NAME",
}

-- Userdata-like vector: values behind __index / __len only (no raw fields), like engine IdVectors.
local function vec(t)
	return setmetatable({}, {
		__index = function(_, k) return t[k] end,
		__len = function() return #t end,
		__ipairs = function()
			return function(_, i)
				i = i + 1
				if t[i] ~= nil then return i, t[i] end
			end, nil, 0
		end,
	})
end

-- load vector for cargo ids 0..11 (index = cargo + 1)
local function loads(...)
	local v = {}
	for i = 1, 12 do v[i] = false end
	for _, c in ipairs({ ... }) do v[c + 1] = true end
	return vec(v)
end

local function stop(sg, station, terminal, load)
	return { stationGroup = sg, station = station, terminal = terminal, stopConfig = { load = load } }
end

local function term(unload)
	return { cargoUnload = unload, cargoLoad = true }
end

-- components[entity][CT] = value; `raise[entity]` = true -> getComponent errors for that entity.
local function fakeApi(components, sys, raise)
	return {
		type = { ComponentType = CT, enum = { StockListType = { InputStock = INPUT, OutputStock = OUTPUT } } },
		res = { cargoTypeRep = { getPassengerCargoTypeId = function() return PASS end } },
		engine = {
			getComponent = function(e, ct)
				if raise and raise[e] then error("bad entity " .. e) end
				return (components[e] or {})[ct]
			end,
			getEntitiesWithComponent = function(ct)
				local out = {}
				for e, comps in pairs(components) do if comps[ct] ~= nil then out[#out + 1] = e end end
				table.sort(out)
				return out
			end,
			system = {
				lineSystem = { getStationGroup2LineStopsMap = function() return sys.lineStops or {} end },
				townBuildingSystem = { getTown2BuildingMap = function() return sys.town2b or {} end },
				-- sys.stock[stockList][stockId0] = count | "err"; missing = 0
				simEntityAtStockSystem = { getStockCount = function(sl, id)
					local t = (sys.stock or {})[sl]
					local v = t ~= nil and t[id] or 0
					if v == "err" then error("no stock " .. sl .. ":" .. id) end
					return v
				end },
			},
		},
	}
end

before_each(function()
	gather.errors = 0
	clear_logs()
end)

-- passenger / lines --------------------------------------------------------------------

test("passengerCargo reads cargoTypeRep", function()
	set_global("api", fakeApi({}, {}))
	eq(gather.passengerCargo(), PASS)
end)

-- Group 100: stations {50, 51}; station 51 terminal 1 does not unload cargo.
local function lineWorld()
	return {
		[100] = { STATION_GROUP = { stations = vec({ 50, 51 }) } },
		[200] = { STATION_GROUP = { stations = vec({ 60 }) } },
		[50] = { STATION = { terminals = vec({ term(true) }) } },
		[51] = { STATION = { terminals = vec({ term(true), term(false) }) } },
		[60] = { STATION = { terminals = vec({ term(true) }) } },
		[1] = { LINE = { stops = vec({ stop(200, 0, 0, loads(FISH)), stop(100, 1, 1, loads()), stop(100, 0, 0, loads()) }) } },
		[2] = { LINE = { stops = vec({ stop(100, 0, 0, loads(PASS)), stop(200, 0, 0, loads(PASS)) }) } },
	}
end

local function lineMap()
	return { [100] = { { 1, 1 }, { 1, 2 }, { 2, 0 } }, [200] = { { 1, 0 }, { 2, 1 } } }
end

test("lines: carried cargos = union of load vectors (0-based cargo ids), one read per line", function()
	local comps = lineWorld()
	local reads = 0
	local a = fakeApi(comps, { lineStops = lineMap() })
	local get = a.engine.getComponent
	a.engine.getComponent = function(e, ct) if ct == CT.LINE then reads = reads + 1 end return get(e, ct) end
	set_global("api", a)
	local lines = gather.lines()
	eq(#lines, 2)
	eq(lines[1].entity, 1)
	eq(lines[1].carries, { FISH })
	eq(lines[2].carries, { PASS })
	eq(reads, 2)
end)

test("lines: stop terminal resolved via 0-based station / terminal indices", function()
	set_global("api", fakeApi(lineWorld(), { lineStops = lineMap() }))
	local l1 = gather.lines()[1]
	eq(l1.stops, {
		{ stationGroup = 200, unload = true },
		{ stationGroup = 100, unload = false }, -- station index 1 = 51, terminal index 1 = second terminal
		{ stationGroup = 100, unload = true },
	})
end)

test("lines: unknown station / terminal (-1, out of range) counts as unloading", function()
	local comps = lineWorld()
	comps[3] = { LINE = { stops = vec({ stop(100, -1, -1, loads(TOOLS)), stop(100, 5, 0, loads()), stop(100, 0, 9, loads()) }) } }
	set_global("api", fakeApi(comps, { lineStops = { [100] = { { 3, 0 } } } }))
	local l = gather.lines()[1]
	eq(l.carries, { TOOLS })
	for _, s in ipairs(l.stops) do eq(s.unload, true) end
end)

test("lines: a failing line is skipped and logged", function()
	set_global("api", fakeApi(lineWorld(), { lineStops = lineMap() }, { [2] = true }))
	local lines = gather.lines()
	eq(#lines, 1)
	eq(lines[1].entity, 1)
	eq(gather.errors, 1)
	ok(log_entries()[1].msg:find("[SQSG] ERR line 2", 1, true))
end)

test("lines: a missing LINE component is skipped silently", function()
	set_global("api", fakeApi(lineWorld(), { lineStops = { [100] = { { 99, 0 } } } }))
	eq(gather.lines(), {})
	eq(gather.errors, 0)
end)

test("ERR logs stop after MAX_ERR_LOGS, errors keep counting", function()
	local comps, map = {}, { [100] = {} }
	for i = 1, 30 do map[100][i] = { i, 0 } end
	local raise = {}
	for i = 1, 30 do raise[i] = true end
	set_global("api", fakeApi(comps, { lineStops = map }, raise))
	gather.lines()
	eq(gather.errors, 30)
	eq(#log_entries(), gather.MAX_ERR_LOGS)
end)

-- groups ----------------------------------------------------------------------------------

test("unloadGroups: groups with a cargoUnload terminal; failing group skipped", function()
	local comps = lineWorld()
	comps[300] = { STATION_GROUP = { stations = vec({ 70 }) } }
	comps[70] = { STATION = { terminals = vec({ term(false) }) } }
	comps[400] = { STATION_GROUP = { stations = vec({ -1 }) } }
	set_global("api", fakeApi(comps, {}))
	eq(gather.unloadGroups(), { 100, 200 })
	set_global("api", fakeApi(comps, {}, { [100] = true }))
	eq(gather.unloadGroups(), { 200 })
	eq(gather.errors, 1)
end)

test("groupStations: plain lists, -1 entries skipped, missing groups left out", function()
	local comps = lineWorld()
	comps[300] = { STATION_GROUP = { stations = vec({ -1, 80 }) } }
	set_global("api", fakeApi(comps, {}))
	eq(gather.groupStations({ 100, 300, 999 }), { [100] = { 50, 51 }, [300] = { 80 } })
end)

-- buildings / towns --------------------------------------------------------------------------

local function stock(type_, cargo) return { type = type_, cargoType = cargo } end

local function bv(x, y, z)
	return { bbox = { min = { x = x - 1, y = y - 1, z = z - 1 }, max = { x = x + 1, y = y + 1, z = z + 1 } } }
end

local function buildingWorld()
	return {
		-- commercial, needs fish + tools (output stock and passengers ignored)
		[10] = { TOWN_BUILDING = { town = 1, stockList = 11, personCapacity = 12 }, BOUNDING_VOLUME = bv(5, 6, 7) },
		[11] = { STOCK_LIST = { stocks = vec({ stock(INPUT, TOOLS), stock(OUTPUT, FOOD), stock(INPUT, FISH), stock(INPUT, PASS), stock(INPUT, FISH) }) } },
		[12] = { PERSON_CAPACITY = { type = 1 } },
		-- residential, needs food
		[20] = { TOWN_BUILDING = { town = 1, stockList = 21, personCapacity = 22 }, BOUNDING_VOLUME = bv(0, 0, 0) },
		[21] = { STOCK_LIST = { stocks = vec({ stock(INPUT, FOOD) }) } },
		[22] = { PERSON_CAPACITY = { type = 0 } },
		-- no needs
		[30] = { TOWN_BUILDING = { town = 2, stockList = 31, personCapacity = -1 } },
		[31] = { STOCK_LIST = { stocks = vec({}) } },
		-- no stock list, no position
		[40] = { TOWN_BUILDING = { town = 2, stockList = -1, personCapacity = -1 } },
	}
end

local TOWN2B = { [1] = vec({ 20, 10 }), [2] = vec({ 30, 40 }) }

test("buildingMap: total count and the map", function()
	set_global("api", fakeApi(buildingWorld(), { town2b = TOWN2B }))
	local n, map = gather.buildingMap()
	eq(n, 4)
	ok(map[1] ~= nil)
end)

local function readAll(ids, prev)
	local out = {}
	for _, b in ipairs(ids) do
		local info = gather.readBuilding(b, 1, prev and prev[b], PASS)
		if info ~= nil and #info.needs > 0 then out[b] = info end
	end
	return out
end

test("readBuilding: needs = InputStock cargos minus passengers, sorted unique; land use = type + 1", function()
	set_global("api", fakeApi(buildingWorld(), { town2b = TOWN2B }))
	local b = readAll({ 10, 20, 30, 40 })
	eq(b[10], { entity = 10, town = 1, landUse = 2, needs = { FISH, TOOLS }, stockList = 11, pos = { 5, 6, 7 },
		stock = { [FISH] = 0, [TOOLS] = 0 }, zeroReads = { [FISH] = 1, [TOOLS] = 1 } })
	eq(b[20].landUse, 1)
	eq(b[20].needs, { FOOD })
	eq(b[30], nil) -- no needs
	eq(b[40], nil)
end)

test("readBuilding: position reused from prev, failing building skipped", function()
	local comps = buildingWorld()
	set_global("api", fakeApi(comps, { town2b = TOWN2B }, { [20] = true }))
	local b = readAll({ 20, 10 }, { [10] = { pos = { 1, 2, 3 } } })
	eq(b[10].pos, { 1, 2, 3 })
	eq(b[20], nil)
	eq(gather.errors, 1)
end)

-- stock per need (Phase 2b) ----------------------------------------------------------------

test("readBuilding: stock per need = getStockCount(stockList, 0-based stockId), same cargo summed", function()
	-- stocks of 11: [0] TOOLS, [1] FOOD (output), [2] FISH, [3] PASS, [4] FISH
	local calls = {}
	local a = fakeApi(buildingWorld(), { stock = { [11] = { [0] = 2, [1] = 9, [2] = 1, [3] = 5, [4] = 3 } } })
	local get = a.engine.system.simEntityAtStockSystem.getStockCount
	a.engine.system.simEntityAtStockSystem.getStockCount = function(sl, id) calls[#calls + 1] = id return get(sl, id) end
	set_global("api", a)
	local b, okRead = gather.readBuilding(10, 1, nil, PASS)
	ok(okRead)
	eq(b.stock, { [TOOLS] = 2, [FISH] = 4 })
	eq(b.zeroReads, { [TOOLS] = 0, [FISH] = 0 })
	eq(calls, { 0, 2, 4 }) -- input stocks of needed cargos only (no output, no passengers)
end)

test("readBuilding: zero-read streak grows from prev, resets on stock, keeps on a failed read", function()
	set_global("api", fakeApi(buildingWorld(), { stock = { [11] = { [0] = 0, [2] = 0, [4] = 0 } } }))
	local prev = { pos = { 1, 2, 3 }, zeroReads = { [TOOLS] = 2, [FISH] = 5 } }
	local b = gather.readBuilding(10, 1, prev, PASS)
	eq(b.zeroReads, { [TOOLS] = 3, [FISH] = 6 })
	set_global("api", fakeApi(buildingWorld(), { stock = { [11] = { [0] = 1, [2] = "err", [4] = 0 } } }))
	b = gather.readBuilding(10, 1, prev, PASS)
	eq(b.zeroReads, { [TOOLS] = 0, [FISH] = 5 }) -- one FISH stock failed: streak unchanged
	eq(b.stock[FISH], nil)
	eq(b.needs, { FISH, TOOLS })
end)

test("readBuilding: a raising building returns nil, false (ERR counted)", function()
	set_global("api", fakeApi(buildingWorld(), {}, { [10] = true }))
	local b, okRead = gather.readBuilding(10, 1, nil, PASS)
	eq(b, nil)
	eq(okRead, false)
	eq(gather.errors, 1)
end)

test("flatten: towns ascending, engine order inside a town, town per id", function()
	set_global("api", fakeApi({}, {}))
	local ids, towns = gather.flatten({ [2] = vec({ 30, 40 }), [1] = vec({ 20, 10 }) })
	eq(ids, { 20, 10, 30, 40 })
	eq(towns, { 1, 1, 2, 2 })
end)

-- Phase 2d: building boxes and town names --------------------------------------------------

test("buildingBox: 2D BOUNDING_VOLUME box, min/max normalised; nil without one", function()
	local comps = {
		[10] = { BOUNDING_VOLUME = { bbox = { min = { x = 5, y = -2, z = 0 }, max = { x = 1, y = 8, z = 9 } } } },
		[11] = {},
		[1] = { NAME = { name = "Fishton" } },
	}
	set_global("api", fakeApi(comps, {}))
	eq(gather.buildingBox(10), { 1, -2, 5, 8 })
	eq(gather.buildingBox(11), nil)
	eq(gather.townName(1), "Fishton")
	eq(gather.townName(2), "")
end)

-- perf review (2026-10-09) ------------------------------------------------------------------

local function countingApi(comps, sys, raise)
	local a = fakeApi(comps, sys, raise)
	local reads = {}
	local get = a.engine.getComponent
	a.engine.getComponent = function(e, ct)
		reads[ct] = (reads[ct] or 0) + 1
		if ct == CT.LINE then reads[#reads + 1] = e end
		return get(e, ct)
	end
	return a, reads
end

test("lines with a cache: first call reads every line; unchanged map -> round robin only, same list", function()
	local comps = lineWorld()
	for l = 3, 21 do comps[l] = { LINE = { stops = vec({ stop(200, 0, 0, loads(FISH)) }) } } end
	local map = lineMap()
	for l = 3, 21 do map[200][#map[200] + 1] = { l, 0 } end
	local a, reads = countingApi(comps, { lineStops = map })
	set_global("api", a)
	local lc = gather.newLineCache()
	local first, changed = gather.lines(lc)
	eq(#first, 21)
	eq(changed, true)
	eq(reads.LINE, 21)
	eq(first, gather.lines()) -- same records as the stateless read
	for k in pairs(reads) do reads[k] = nil end
	local again, changed2 = gather.lines(lc)
	eq(changed2, false)
	ok(again == first, "same list table")
	eq(reads.LINE, 3) -- ceil(21 / LINE_EVERY)
	eq({ reads[1], reads[2], reads[3] }, { 1, 2, 3 })
	for k in pairs(reads) do reads[k] = nil end
	gather.lines(lc)
	eq({ reads[1], reads[2], reads[3] }, { 4, 5, 6 })
	-- every line re-read within LINE_EVERY calls
	local seen = {}
	for _ = 1, gather.LINE_EVERY do
		for k in pairs(reads) do reads[k] = nil end
		gather.lines(lc)
		for _, l in ipairs(reads) do seen[l] = true end
	end
	for l = 1, 21 do ok(seen[l], "line " .. l) end
end)

test("lines with a cache: a changed stop set re-reads that line at once; a cargo change shows on its round robin turn", function()
	local comps = lineWorld()
	local map = lineMap()
	local a, reads = countingApi(comps, { lineStops = map })
	set_global("api", a)
	local lc = gather.newLineCache()
	gather.lines(lc)
	-- line 2 gets a new stop at group 300 (map changes), and new LINE data
	comps[2].LINE = { stops = vec({ stop(100, 0, 0, loads(PASS)), stop(200, 0, 0, loads(PASS)), stop(300, -1, -1, loads(FOOD)) }) }
	map[300] = { { 2, 2 } }
	for k in pairs(reads) do reads[k] = nil end
	local lines, changed = gather.lines(lc)
	eq(changed, true)
	ok(reads[1] == 2 or reads[2] == 2, "line 2 re-read at once")
	eq(lines[2].carries, { PASS, FOOD })
	-- line 1's load config changes without a map change: picked up within LINE_EVERY calls
	comps[1].LINE = { stops = vec({ stop(200, 0, 0, loads(TOOLS)) }) }
	local got = false
	for _ = 1, gather.LINE_EVERY do
		lines = gather.lines(lc)
		if lines[1].carries[1] == TOOLS then got = true end
	end
	ok(got, "cargo change picked up")
end)

test("lines with a cache: a removed line is dropped; a failing line is retried every call", function()
	local comps = lineWorld()
	local map = lineMap()
	local a, reads = countingApi(comps, { lineStops = map }, { [2] = true })
	set_global("api", a)
	local lc = gather.newLineCache()
	local lines = gather.lines(lc)
	eq(#lines, 1)
	eq(gather.errors, 1)
	gather.lines(lc)
	eq(gather.errors, 2) -- retried
	map[100] = { { 2, 0 } }
	map[200] = { { 2, 1 } }
	local l2, changed = gather.lines(lc)
	eq(l2, {})
	eq(changed, true)
end)

test("flatten with the previous result: unchanged -> same tables, false; changed -> new, true", function()
	set_global("api", fakeApi({}, {}))
	local map = { [2] = vec({ 30, 40 }), [1] = vec({ 20, 10 }) }
	local ids, towns, ch = gather.flatten(map)
	eq(ch, true)
	local ids2, towns2, ch2 = gather.flatten(map, ids, towns)
	eq(ch2, false)
	ok(ids2 == ids and towns2 == towns)
	local ids3, _, ch3 = gather.flatten({ [2] = vec({ 30, 41 }), [1] = vec({ 20, 10 }) }, ids, towns)
	eq(ch3, true)
	eq(ids3, { 20, 10, 30, 41 })
	local _, _, ch4 = gather.flatten({ [2] = vec({ 30, 40, 50 }), [1] = vec({ 20, 10 }) }, ids, towns)
	eq(ch4, true)
	local _, _, ch5 = gather.flatten({ [2] = vec({ 30 }), [1] = vec({ 20, 10 }) }, ids, towns)
	eq(ch5, true)
end)

test("readBuilding: no needs -> no PERSON_CAPACITY / BOUNDING_VOLUME read", function()
	local comps = buildingWorld()
	comps[30].TOWN_BUILDING.personCapacity = 12
	comps[30].BOUNDING_VOLUME = bv(1, 1, 1)
	local a, reads = countingApi(comps, {})
	set_global("api", a)
	local b, okRead = gather.readBuilding(30, 2, nil, PASS)
	ok(okRead)
	eq(b.needs, {})
	eq(reads.PERSON_CAPACITY, nil)
	eq(reads.BOUNDING_VOLUME, nil)
	gather.readBuilding(10, 1, nil, PASS)
	eq(reads.PERSON_CAPACITY, 1)
	eq(reads.BOUNDING_VOLUME, 1)
end)
