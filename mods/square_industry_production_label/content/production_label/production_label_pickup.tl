-- Industry Production Label: shared pickup-rate cache (PLAN "Pickup rate pill").
--
-- stockList entity -> {cargoTypeId -> summed line rate} for every line that loads that output cargo
-- at a station group whose cargo catchment reaches the industry, times its pickup visits per round
-- trip (`visits`). There is no industry -> lines API,
-- so the inverse is built in one pass from api.engine.system.lineSystem.getStationGroup2LineStopsMap()
-- (.cache/game/api/tealdef/api/engine/system.d.tl:44-45).
--
-- ONE cache for all labels: ug_require caches modules (.cache/game/base/content/init.lua ~56-110), so
-- every ProductionLabelHudIcon in the GUI Lua state shares `pickup.cache`. Whichever label first finds
-- it stale rebuilds it from inside its existing 2 s useStepStateTimer read, at most every
-- REFRESH_INTERVAL real seconds and never while the simulation is paused (GAME_TIME.updateCount
-- unchanged, api/tealdef/api/engine.d.tl:425-436). Per label per refresh: one table lookup. Rebuilds
-- after the first are sliced over several frames (`tick`, SLICE_* below).
--
-- `aggregate` is pure (fed by an adapter, unit-tested in tests/square_industry_production_label/
-- test_pickup.lua); every engine call is in `engineAdapter`.
--
-- READ-ONLY: no commands, no game script, no saved state.

local pickup : SquareProductionLabelPickup = {}

-- Wall-clock seconds between rebuilds (os.time). NOT api.util.getApplicationTime: it is "Only available
-- in GUI thread" (api/tealdef/api/util.d.tl:174) and HUD icon recipes run on a worker thread, where it
-- dereferences null and crashes the game (crash dump 2026-10-07). os.time has 1 s resolution: plenty.
-- Lines and vehicles change rarely; 15 s keeps a large network's rebuild far from every frame.
pickup.REFRESH_INTERVAL = 15.0

-- Engine.Component.Line.LoadMode (api/tealdef/api/engine.d.tl:497-502) is a number at runtime (base
-- casts it `as integer`, gui/line_vehicle_mgmt/cargofilter_window.tl:819). Declaration order gives
-- LEGACY_UNLOAD_ONLY = 3: unverified (TESTING §7). Such stops never load.
pickup.LEGACY_UNLOAD_ONLY = 3

-- One-shot debug log for the first in-game test (TESTING §7): counts and time of the first rebuild,
-- and hit/miss of the first DEBUG_LOOKUPS label lookups. Set to false after the test.
pickup.DEBUG = false
pickup.DEBUG_LOOKUPS = 5

-- Sliced rebuilds (PERF_REVIEW.md 2026-10-10). In game a rebuild took 9 ms on average and up to 27 ms
-- in one HUD step (desert save, 250 lines). After the first build (done at once: the labels have no
-- rates yet) a rebuild runs in slices of about SLICE_BUDGET_MS, at most one slice per SLICE_GAP_MS
-- (all labels' timer reads of one frame run back to back, so the gap is what spreads the slices over
-- frames). The old rates stay in use until the new ones are complete. A build still running after
-- BUILD_MAX_MS (e.g. no label polled for a while) finishes in the next slice, so its reads span at most
-- that long. Milliseconds from pickup.nowMs (production_label.script.tl sets the api.type.Clock timer,
-- safe on the HUD worker threads; default os.clock for tests).
pickup.SLICE_BUDGET_MS = 4.0
pickup.SLICE_GAP_MS = 100.0
pickup.BUILD_MAX_MS = 3000.0
pickup.nowMs = function() : number return os.clock() * 1000 end

local LOG_PREFIX <const> = "square_industry_production_label: pickup "

function pickup.newCache() : SquareProductionLabelPickupCache
	return { rates = {}, builtAt = nil, builtUpdateCount = nil, building = false, builds = 0, errorLogged = false,
		pending = nil, pendingStartMs = nil, sliceAtMs = nil }
end

pickup.cache = pickup.newCache()

-- aggregate ---------------------------------------------------------------------

--- True when the stop loads any cargo other than passengers (stopConfig.load is an IdVector:
--- index = cargoTypeId + 1, cargo_util.tl:818-835).
local function loadsCargo(load : {boolean}, passenger : integer) : boolean
	for k, v in ipairs(load) do
		if v == true and (passenger == nil or k ~= passenger + 1) then
			return true
		end
	end
	return false
end

-- One rebuild as a resumable job (PERF_REVIEW.md 2026-10-10): `newBuild` reads the line-stops map,
-- `step` works through the station groups and then the per-line sums, and returns false when
-- `overBudget()` says to stop (checked after each group / each summed StockList, so every call makes
-- progress). `aggregate` = newBuild + one step without a budget. The in-game lookup slices a rebuild
-- over several frames (`tick`); the result is the same as one pass (served is a set per line; sums
-- are per StockList), only read a little later.

function pickup.newBuild(a : SquareProductionLabelPickupAdapter) : SquareProductionLabelPickupBuild
	local b : SquareProductionLabelPickupBuild = {
		adapter = a,
		stats = { stationGroups = 0, lines = 0, cargoStops = 0, stockLists = 0, stopIndexMismatches = 0 },
		passenger = a.passengerCargoType(),
		groups = {},
		gi = 1,
		stopsOf = {},
		outputsOf = {},
		producersOf = {},
		served = {},
		servedKeys = nil,
		si = 1,
		rateOf = {},
		result = {},
		done = false,
	}
	-- (stationGroup, lineStops) pairs, so a sliced build walks a fixed list.
	for stationGroup, lineStops in pairs(a.lineStopsMap() or {} as {integer : {{integer, integer}}}) do
		b.groups[#b.groups + 1] = { stationGroup = stationGroup, lineStops = lineStops }
	end
	return b
end

local NONE : {any} = {}

-- Per group: the flat (stockList, output cargo) pairs in its reach, built once per rebuild from
-- reach x outputs. Most catchables (town buildings) produce nothing, so every stop at the group walks
-- only the few producing pairs instead of the whole reach (PERF_REVIEW.md 2026-10-08).
local function producers(b : SquareProductionLabelPickupBuild, stationGroup : integer) : {{integer, integer}}
	local pairsList = b.producersOf[stationGroup]
	if pairsList ~= nil then return pairsList end
	pairsList = {}
	local reach = b.adapter.reachableStockLists(stationGroup) or NONE as {integer}
	for __, stockList in ipairs(reach) do
		local outputs = b.outputsOf[stockList]
		if outputs == nil then
			outputs = b.adapter.outputCargoTypes(stockList) or NONE as {integer}
			b.outputsOf[stockList] = outputs
		end
		for __, cargo in ipairs(outputs) do
			pairsList[#pairsList + 1] = { stockList, cargo }
		end
	end
	b.producersOf[stationGroup] = pairsList
	return pairsList
end

-- served[stockList][cargo][line][stopIndex] = true: the line's stops (1-based) that load this cargo in
-- reach of this StockList, a set so a stop listed twice (or met again by the fallback) counts once.
local function consider(b : SquareProductionLabelPickupBuild, line : integer, index : integer, stationGroup : integer, stop : SquareProductionLabelPickupStop)
	if stop.loadMode == pickup.LEGACY_UNLOAD_ONLY then return end
	local load = stop.load
	if load == nil or not loadsCargo(load, b.passenger) then return end
	if b.adapter.terminalCargoLoad(stationGroup, stop.station, stop.terminal) == false then return end
	b.stats.cargoStops = b.stats.cargoStops + 1
	local served = b.served
	for __, pair in ipairs(producers(b, stationGroup)) do
		local stockList, cargo = pair[1], pair[2]
		if load[cargo + 1] == true then
			local byCargo = served[stockList]
			if byCargo == nil then
				byCargo = {}
				served[stockList] = byCargo
			end
			local lines = byCargo[cargo]
			if lines == nil then
				lines = {}
				byCargo[cargo] = lines
			end
			local stopSet = lines[line]
			if stopSet == nil then
				stopSet = {}
				lines[line] = stopSet
			end
			stopSet[index] = true
		end
	end
end

local function scanGroup(b : SquareProductionLabelPickupBuild, stationGroup : integer, lineStops : {{integer, integer}})
	local stats = b.stats
	if #lineStops > 0 then
		stats.stationGroups = stats.stationGroups + 1
	end
	for __, pair in ipairs(lineStops) do
		local line, stopIndex0 = pair[1], pair[2]
		local stops = b.stopsOf[line]
		if stops == nil then
			stops = b.adapter.lineStops(line) or NONE as {SquareProductionLabelPickupStop}
			b.stopsOf[line] = stops
			stats.lines = stats.lines + 1
		end
		-- The pair's index is 0-based like getLineStopsForTerminal's stopIndex0
		-- (station_group.tl:695-702). On a mismatch, every stop of the line at this group is used.
		local stop = stopIndex0 ~= nil and stops[stopIndex0 + 1] or nil
		if stop ~= nil and stop.stationGroup == stationGroup then
			consider(b, line, stopIndex0 + 1, stationGroup, stop)
		else
			stats.stopIndexMismatches = stats.stopIndexMismatches + 1
			for i, s in ipairs(stops) do
				if s.stationGroup == stationGroup then
					consider(b, line, i, stationGroup, s)
				end
			end
		end
	end
end

--- Pickup visits per round trip: the line's stops in `stopSet` whose previous stop (wrapping from the
--- first to the last) is not in it. A vehicle arrives with free space only after stopping elsewhere,
--- so ABAC at A counts 2, while two terminals of A in a row, or a last and first stop both at A,
--- count 1. At least 1 (every stop in the set).
function pickup.visits(stopSet : {integer : boolean}, stopCount : integer) : integer
	local n = 0
	for i, __ in pairs(stopSet) do
		local prev = i > 1 and i - 1 or stopCount
		if not stopSet[prev] then n = n + 1 end
	end
	return n > 0 and n or 1
end

-- Sum for one StockList: calcLineStationThroughput at most once per line per rebuild, and only for
-- lines that serve something; each line's rate times its pickup visits.
local function sumStockList(b : SquareProductionLabelPickupBuild, stockList : integer)
	local out : {integer : integer} = {}
	local any = false
	for cargo, lines in pairs(b.served[stockList]) do
		local sum = 0.0
		for line, stopSet in pairs(lines) do
			local rate = b.rateOf[line]
			if rate == nil then
				local r = b.adapter.lineRate(line)
				-- NaN / negative / non-number count as 0.
				rate = (type(r) == "number" and r == r and r > 0 and r < math.huge) and r or 0
				b.rateOf[line] = rate
			end
			sum = sum + rate * pickup.visits(stopSet, #b.stopsOf[line])
		end
		local rounded = math.floor(sum + 0.5)
		if rounded > 0 then
			out[cargo] = rounded
			any = true
		end
	end
	if any then
		b.result[stockList] = out
		b.stats.stockLists = b.stats.stockLists + 1
	end
end

function pickup.step(b : SquareProductionLabelPickupBuild, overBudget? : function() : boolean) : boolean
	if b.done then return true end
	local groups = b.groups
	while b.gi <= #groups do
		local g = groups[b.gi]
		b.gi = b.gi + 1
		scanGroup(b, g.stationGroup, g.lineStops)
		if overBudget ~= nil and b.gi <= #groups and overBudget() then return false end
	end
	if b.servedKeys == nil then
		local keys : {integer} = {}
		for stockList, __ in pairs(b.served) do keys[#keys + 1] = stockList end
		b.servedKeys = keys
		if overBudget ~= nil and #keys > 0 and overBudget() then return false end
	end
	local keys = b.servedKeys
	while b.si <= #keys do
		local stockList = keys[b.si]
		b.si = b.si + 1
		sumStockList(b, stockList)
		if overBudget ~= nil and b.si <= #keys and overBudget() then return false end
	end
	b.done = true
	return true
end

function pickup.aggregate(a : SquareProductionLabelPickupAdapter) : {integer : {integer : integer}}, SquareProductionLabelPickupStats
	local b = pickup.newBuild(a)
	pickup.step(b)
	return b.result, b.stats
end

-- staleness / refresh -------------------------------------------------------------

function pickup.isStale(cache : SquareProductionLabelPickupCache, now : number, getUpdateCount : function() : integer) : boolean
	if cache.building then return false end
	if cache.builtAt == nil then return true end
	-- Cheap check first: the GAME_TIME read only happens once the interval has passed.
	-- (now < builtAt: clock restarted, rebuild.)
	if now >= cache.builtAt and now - cache.builtAt < pickup.REFRESH_INTERVAL then return false end
	local updateCount = getUpdateCount()
	if updateCount == nil or cache.builtUpdateCount == nil then return true end
	-- A smaller count means another game was loaded: rebuild.
	if updateCount ~= cache.builtUpdateCount then return true end
	-- Paused: the simulation has not advanced since the last rebuild, nothing to redo. Restart the
	-- interval so the labels do not each read GAME_TIME on every refresh while the game stays paused.
	cache.builtAt = now
	return false
end

function pickup.refresh(cache : SquareProductionLabelPickupCache, adapter : SquareProductionLabelPickupAdapter, now : number, getUpdateCount : function() : integer) : boolean, SquareProductionLabelPickupStats
	if not pickup.isStale(cache, now, getUpdateCount) then return false, nil end
	cache.building = true
	local ok, rates, stats = pcall(pickup.aggregate, adapter)
	cache.building = false
	-- A failed attempt counts too: no retry before the next interval, and the last good rates stay.
	cache.builtAt = now
	local okCount, updateCount = pcall(getUpdateCount)
	cache.builtUpdateCount = okCount and updateCount as integer or nil
	if not ok then
		if not cache.errorLogged then
			cache.errorLogged = true
			log.warning(LOG_PREFIX .. "rebuild failed, keeping the last rates: " .. tostring(rates))
		end
		return false, nil
	end
	cache.rates = rates as {integer : {integer : integer}}
	cache.builds = cache.builds + 1
	return true, stats as SquareProductionLabelPickupStats
end

local function buildFailed(cache : SquareProductionLabelPickupCache, err : any)
	cache.pending = nil
	cache.building = false
	if not cache.errorLogged then
		cache.errorLogged = true
		log.warning(LOG_PREFIX .. "rebuild failed, keeping the last rates: " .. tostring(err))
	end
end

function pickup.tick(cache : SquareProductionLabelPickupCache, makeAdapter : function() : SquareProductionLabelPickupAdapter, now : number, getUpdateCount : function() : integer, nowMs : function() : number) : boolean, SquareProductionLabelPickupStats, boolean
	local b = cache.pending
	if b == nil then
		if not pickup.isStale(cache, now, getUpdateCount) then return false, nil, false end
		if cache.builtAt == nil then
			-- First build: at once, as before (no rates to show in the meantime).
			local built, stats = pickup.refresh(cache, makeAdapter(), now, getUpdateCount)
			return built, stats, true
		end
		-- Stamp the interval at the start (a failed start counts too, like refresh).
		cache.builtAt = now
		local okCount, updateCount = pcall(getUpdateCount)
		cache.builtUpdateCount = okCount and updateCount as integer or nil
		local okNew, nb = pcall(function() : SquareProductionLabelPickupBuild return pickup.newBuild(makeAdapter()) end)
		if not okNew then
			buildFailed(cache, nb)
			return false, nil, true
		end
		b = nb as SquareProductionLabelPickupBuild
		cache.pending = b
		cache.building = true
		cache.pendingStartMs = nowMs()
		cache.sliceAtMs = nil
	else
		local last = cache.sliceAtMs
		local t = nowMs()
		if last ~= nil and t >= last and t - last < pickup.SLICE_GAP_MS then return false, nil, false end
	end
	local t0 = nowMs()
	local started = cache.pendingStartMs
	local finishNow = started == nil or t0 < started or t0 - started >= pickup.BUILD_MAX_MS
	local overBudget : function() : boolean = nil
	if not finishNow then
		local budget = pickup.SLICE_BUDGET_MS
		overBudget = function() : boolean return nowMs() - t0 >= budget end
	end
	local ok, done = pcall(pickup.step, b, overBudget)
	cache.sliceAtMs = nowMs()
	if not ok then
		buildFailed(cache, done)
		return false, nil, true
	end
	if not done then return false, nil, true end
	cache.pending = nil
	cache.building = false
	cache.rates = b.result
	cache.builds = cache.builds + 1
	return true, b.stats, true
end

-- engine adapter ------------------------------------------------------------------

function pickup.engineAdapter() : SquareProductionLabelPickupAdapter
	local CT = api.type.ComponentType
	local OUTPUT_STOCK = api.type.enum.StockListType.OutputStock
	local stationGroupOf : {integer : Engine.Component.StationGroup} = {}
	local stationOf : {integer : Station} = {}

	local function getStationGroup(stationGroup : integer) : Engine.Component.StationGroup
		local sg = stationGroupOf[stationGroup]
		if sg == nil then
			sg = api.engine.getComponent(stationGroup, CT.STATION_GROUP) as Engine.Component.StationGroup
			stationGroupOf[stationGroup] = sg
		end
		return sg
	end

	local a : SquareProductionLabelPickupAdapter = { fallbackStations = 0 }

	a.lineStopsMap = function() : {integer : {{integer, integer}}}
		return api.engine.system.lineSystem.getStationGroup2LineStopsMap() as {integer : {{integer, integer}}}
	end

	-- LINE component (api/tealdef/api/engine.d.tl:492-552). Components and their vectors are engine
	-- userdata (base/serialize.lua:129, base/init.lua:219), so stopConfig.load is copied into a plain
	-- table (iterated with ipairs like cargo_util.getConfiguredStopCargoTypes, cargo_util.tl:828) instead
	-- of keeping a reference into a component that is not kept alive.
	a.lineStops = function(line : integer) : {SquareProductionLabelPickupStop}
		local comp = api.engine.getComponent(line, CT.LINE) as Engine.Component.Line
		if comp == nil or comp.stops == nil then return nil end
		local out : {SquareProductionLabelPickupStop} = {}
		for i, s in ipairs(comp.stops) do
			local load : {boolean} = nil
			if s.stopConfig ~= nil and s.stopConfig.load ~= nil then
				load = {}
				for k, v in ipairs(s.stopConfig.load) do load[k] = v == true end
			end
			out[i] = {
				stationGroup = s.stationGroup,
				station = s.station,
				terminal = s.terminal,
				loadMode = s.loadMode as integer,
				load = load,
			}
		end
		return out
	end

	-- The line window's "Rate" (line_eow.script.tl:43-56).
	a.lineRate = function(line : integer) : number
		return api.engine.util.line.calcLineStationThroughput(line)
	end

	-- Union over the group's stations, like base autoLoadConfig (line_util.tl:545-589 ->
	-- cargo_util.getInputOutputStocksForStation, cargo_util.tl:544-563). Built-in industry stations
	-- (fishing grounds, oil platform, sand excavator) with no cargo catchables: the industries of the
	-- station's construction (streetConnectorSystem.getConstructionEntityForStation, CONSTRUCTION.industries,
	-- INDUSTRY.stockList; system.d.tl:250-252, engine.d.tl:321-324). Only read when catchables are empty,
	-- so normal stations never pay for the CONSTRUCTION read.
	a.reachableStockLists = function(stationGroup : integer) : {integer}
		local sg = getStationGroup(stationGroup)
		if sg == nil or sg.stations == nil then return nil end
		local seen : {integer : boolean} = {}
		local out : {integer} = {}
		local function add(e : integer)
			if e ~= nil and e >= 0 and not seen[e] then
				seen[e] = true
				out[#out + 1] = e
			end
		end
		for __, station in ipairs(sg.stations) do
			-- Groups can hold -1 entries (base checks `stationEntity >= 0`, notifications.script.tl:594, 621).
			local catchables = station >= 0 and api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or nil
			if catchables ~= nil and #catchables > 0 then
				for __, e in ipairs(catchables) do add(e) end
			elseif station >= 0 then
				local con = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
				local conComp = (con ~= nil and con >= 0) and api.engine.getComponent(con, CT.CONSTRUCTION) as Engine.Component.Construction or nil
				if conComp ~= nil and conComp.industries ~= nil and #conComp.industries > 0 then
					a.fallbackStations = a.fallbackStations + 1
					for __, industry in ipairs(conComp.industries) do
						add(industry)
						local ind = api.engine.getComponent(industry, CT.INDUSTRY) as Engine.Component.Industry
						if ind ~= nil then add(ind.stockList) end
					end
				end
			end
		end
		return out
	end

	-- OutputStock cargo types, like cargo_util.getInputOutputStocksForStockList(entity, true)
	-- (cargo_util.tl:505-537).
	a.outputCargoTypes = function(stockList : integer) : {integer}
		local comp = api.engine.getComponent(stockList, CT.STOCK_LIST) as Engine.Component.StockList
		if comp == nil or comp.stocks == nil then return nil end
		local out : {integer} = {}
		for i = 1, #comp.stocks do
			if comp.stocks[i].type == OUTPUT_STOCK then
				local types = api.engine.util.stock.getStockCargoTypes(stockList, (i - 1) as StockId)
				for j = 1, #types do out[#out + 1] = types[j] end
			end
		end
		return out
	end

	-- stations[station + 1].terminals[terminal + 1].cargoLoad (0-based, line_util.tl:100-106;
	-- Terminal.cargoLoad, api/tealdef/api/type.d.tl:1286-1287). nil = unknown.
	a.terminalCargoLoad = function(stationGroup : integer, station : integer, terminal : integer) : boolean
		if station == nil or terminal == nil or station < 0 or terminal < 0 then return nil end
		local sg = getStationGroup(stationGroup)
		local stationEntity = sg ~= nil and sg.stations ~= nil and sg.stations[station + 1] or nil
		if stationEntity == nil or stationEntity < 0 then return nil end
		local st = stationOf[stationEntity]
		if st == nil then
			st = api.engine.getComponent(stationEntity, CT.STATION) as Station
			stationOf[stationEntity] = st
		end
		local t = st ~= nil and st.terminals ~= nil and st.terminals[terminal + 1] or nil
		if t == nil then return nil end
		return t.cargoLoad
	end

	a.passengerCargoType = function() : integer
		return api.res.cargoTypeRep.getPassengerCargoTypeId()
	end

	return a
end

-- in-game entry -------------------------------------------------------------------

local debugLookups = 0
local lookupErrorLogged = false

-- GAME_TIME.updateCount: does not tick while paused (engine.d.tl:425-436; read like
-- gui/statistics/statistic_lines.tl:289).
local function readUpdateCount() : integer
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return gt ~= nil and gt.updateCount or nil
end

local function formatRates(t : {integer : integer}) : string
	local parts : {string} = {}
	for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function lookup(entity : integer) : {integer : integer}
	local cache = pickup.cache
	-- Cheap checks first: a pending build only slices once per SLICE_GAP_MS, and isStale reads only
	-- os.time until the interval has passed. SQPERF section "pickup_rebuild" = one slice (or the whole
	-- first build); counter pickup_built = completed rebuilds (HUD worker thread; Clock is safe there).
	local perf = pickup.perf as SquareIndustryProductionLabelSqPerfInst
	local tPerf = perf ~= nil and perf:start() or 0
	local t0 = pickup.DEBUG and os.clock() or 0
	local adapter : SquareProductionLabelPickupAdapter = nil
	local function makeAdapter() : SquareProductionLabelPickupAdapter
		adapter = pickup.engineAdapter()
		return adapter
	end
	local built, stats, worked = pickup.tick(cache, makeAdapter, os.time(), readUpdateCount, pickup.nowMs)
	if worked and perf ~= nil then
		perf:stop("pickup_rebuild", tPerf)
		if built then perf:count("pickup_built") end
	end
	if built and pickup.DEBUG and cache.builds == 1 and adapter ~= nil then
		local ms = (os.clock() - t0) * 1000
		log.message(LOG_PREFIX .. "cache built in " .. string.format("%.1f", ms) .. " ms: "
			.. tostring(stats.stationGroups) .. " station groups, " .. tostring(stats.lines) .. " lines, "
			.. tostring(stats.cargoStops) .. " cargo stops, " .. tostring(stats.stockLists) .. " industries with pickup, "
			.. tostring(stats.stopIndexMismatches) .. " stopIndex mismatches, "
			.. tostring(adapter.fallbackStations) .. " fallback stations")
	end
	local rates = cache.rates[entity]
	if pickup.DEBUG and debugLookups < pickup.DEBUG_LOOKUPS then
		debugLookups = debugLookups + 1
		log.message(LOG_PREFIX .. "lookup " .. tostring(entity) .. ": " .. (rates ~= nil and ("hit " .. formatRates(rates)) or "miss"))
	end
	return rates
end

function pickup.ratesFor(entity : integer) : {integer : integer}
	-- Never errors into the label: a failure here only drops the pickup pill.
	local ok, rates = pcall(lookup, entity)
	if not ok then
		if not lookupErrorLogged then
			lookupErrorLogged = true
			log.warning(LOG_PREFIX .. "lookup failed: " .. tostring(rates))
		end
		return nil
	end
	return rates as {integer : integer}
end

return pickup
