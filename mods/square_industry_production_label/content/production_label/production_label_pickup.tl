-- Industry Production Label: shared pickup-rate cache (PLAN "Pickup rate pill").
--
-- stockList entity -> {cargoTypeId -> summed line rate} for every line that loads that output cargo
-- at a station group whose cargo catchment reaches the industry. There is no industry -> lines API,
-- so the inverse is built in one pass from api.engine.system.lineSystem.getStationGroup2LineStopsMap()
-- (.cache/game/api/tealdef/api/engine/system.d.tl:44-45).
--
-- ONE cache for all labels: ug_require caches modules (.cache/game/base/content/init.lua ~56-110), so
-- every ProductionLabelHudIcon in the GUI Lua state shares `pickup.cache`. Whichever label first finds
-- it stale rebuilds it from inside its existing 2 s useStepStateTimer read, at most every
-- REFRESH_INTERVAL real seconds and never while the simulation is paused (GAME_TIME.updateCount
-- unchanged, api/tealdef/api/engine.d.tl:425-436). Per label per refresh: one table lookup.
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

local LOG_PREFIX <const> = "square_industry_production_label: pickup "

function pickup.newCache() : SquareProductionLabelPickupCache
	return { rates = {}, builtAt = nil, builtUpdateCount = nil, building = false, builds = 0, errorLogged = false }
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

function pickup.aggregate(a : SquareProductionLabelPickupAdapter) : {integer : {integer : integer}}, SquareProductionLabelPickupStats
	local stats : SquareProductionLabelPickupStats = { stationGroups = 0, lines = 0, cargoStops = 0, stockLists = 0, stopIndexMismatches = 0 }
	local passenger = a.passengerCargoType()
	local map = a.lineStopsMap() or {}

	-- Per-rebuild memos: each line's stops and rate, each group's reach and each StockList's outputs
	-- are read at most once.
	local NONE : {any} = {}
	local stopsOf : {integer : {SquareProductionLabelPickupStop}} = {}
	local reachOf : {integer : {integer}} = {}
	local outputsOf : {integer : {integer}} = {}
	-- served[stockList][cargo][line] = true: a set, so each line counts once per (stockList, cargo)
	-- however often it stops at the group (or at several terminals of it).
	local served : {integer : {integer : {integer : boolean}}} = {}

	local function consider(line : integer, stationGroup : integer, stop : SquareProductionLabelPickupStop)
		if stop.loadMode == pickup.LEGACY_UNLOAD_ONLY then return end
		local load = stop.load
		if load == nil or not loadsCargo(load, passenger) then return end
		if a.terminalCargoLoad(stationGroup, stop.station, stop.terminal) == false then return end
		stats.cargoStops = stats.cargoStops + 1
		local reach = reachOf[stationGroup]
		if reach == nil then
			reach = a.reachableStockLists(stationGroup) or NONE as {integer}
			reachOf[stationGroup] = reach
		end
		for __, stockList in ipairs(reach) do
			local outputs = outputsOf[stockList]
			if outputs == nil then
				outputs = a.outputCargoTypes(stockList) or NONE as {integer}
				outputsOf[stockList] = outputs
			end
			for __, cargo in ipairs(outputs) do
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
					lines[line] = true
				end
			end
		end
	end

	for stationGroup, lineStops in pairs(map) do
		if #lineStops > 0 then
			stats.stationGroups = stats.stationGroups + 1
		end
		for __, pair in ipairs(lineStops) do
			local line, stopIndex0 = pair[1], pair[2]
			local stops = stopsOf[line]
			if stops == nil then
				stops = a.lineStops(line) or NONE as {SquareProductionLabelPickupStop}
				stopsOf[line] = stops
				stats.lines = stats.lines + 1
			end
			-- The pair's index is 0-based like getLineStopsForTerminal's stopIndex0
			-- (station_group.tl:695-702). On a mismatch, every stop of the line at this group is used.
			local stop = stopIndex0 ~= nil and stops[stopIndex0 + 1] or nil
			if stop ~= nil and stop.stationGroup == stationGroup then
				consider(line, stationGroup, stop)
			else
				stats.stopIndexMismatches = stats.stopIndexMismatches + 1
				for __, s in ipairs(stops) do
					if s.stationGroup == stationGroup then
						consider(line, stationGroup, s)
					end
				end
			end
		end
	end

	-- Sum: calcLineStationThroughput at most once per line, and only for lines that serve something.
	local rateOf : {integer : number} = {}
	local result : {integer : {integer : integer}} = {}
	for stockList, byCargo in pairs(served) do
		local out : {integer : integer} = {}
		local any = false
		for cargo, lines in pairs(byCargo) do
			local sum = 0.0
			for line, __ in pairs(lines) do
				local rate = rateOf[line]
				if rate == nil then
					local r = a.lineRate(line)
					-- NaN / negative / non-number count as 0.
					rate = (type(r) == "number" and r == r and r > 0 and r < math.huge) and r or 0
					rateOf[line] = rate
				end
				sum = sum + rate
			end
			local rounded = math.floor(sum + 0.5)
			if rounded > 0 then
				out[cargo] = rounded
				any = true
			end
		end
		if any then
			result[stockList] = out
			stats.stockLists = stats.stockLists + 1
		end
	end
	return result, stats
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
	local now = os.time()
	if pickup.isStale(cache, now, readUpdateCount) then
		local adapter = pickup.engineAdapter()
		local t0 = os.clock()
		local built, stats = pickup.refresh(cache, adapter, now, readUpdateCount)
		if built and pickup.DEBUG and cache.builds == 1 then
			local ms = (os.clock() - t0) * 1000
			log.message(LOG_PREFIX .. "cache built in " .. string.format("%.1f", ms) .. " ms: "
				.. tostring(stats.stationGroups) .. " station groups, " .. tostring(stats.lines) .. " lines, "
				.. tostring(stats.cargoStops) .. " cargo stops, " .. tostring(stats.stockLists) .. " industries with pickup, "
				.. tostring(stats.stopIndexMismatches) .. " stopIndex mismatches, "
				.. tostring(adapter.fallbackStations) .. " fallback stations")
		end
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
