-- Supply Gaps: engine reads (GUI thread, read-only). Turns lines, station groups and town buildings
-- into plain records (sg_types.d.tl) for the pure model (sg_model.tl). Every entity read is in
-- pcall: a failing entity is skipped and counted (`gather.errors`, first MAX_ERR_LOGS logged as ERR).
-- Unit-tested against a fake api in tests/square_supply_gaps/test_gather.lua.
--
-- Sources:
--   * lines: lineSystem.getStationGroup2LineStopsMap() (api/tealdef/api/engine/system.d.tl:45) for the
--     set of lines with stops, then one LINE read each (engine.d.tl:492-552). Carried cargos = union of
--     stopConfig.load over the line's stops (IdVector, index = cargo + 1; cargo_util.tl:818-835),
--     copied out of the userdata vector as production_label_pickup.tl does. Every stop of the line is
--     used (the map's stop index is not needed for a per-line union). LEGACY_UNLOAD_ONLY stops still
--     unload: no skip.
--   * stop terminal: STATION_GROUP.stations[station + 1] -> STATION.terminals[terminal + 1].cargoUnload
--     (0-based, production_label_pickup.tl terminalCargoLoad; Terminal, api/tealdef/api/type.d.tl:1286-1291)
--   * buildings: townBuildingSystem.getTown2BuildingMap() (system.d.tl:122), TOWN_BUILDING
--     (engine.d.tl:1305-1325), STOCK_LIST of TownBuilding.stockList (InputStock cargoType,
--     town_building.tl:84-88), PERSON_CAPACITY.type (engine.d.tl:837-838) + 1
--   * stock per need (Phase 2b): simEntityAtStockSystem.getStockCount(stockList, stockId0)
--     (api/tealdef/api/engine/system.d.tl:161-168), one call per input stock: the per-stock read
--     cargo_util.calculateStockConfigs makes for the building window's "{count}/{capacity}"
--     (base/content/gui/main/cargo_util.tl:65, label in gui/entity_window/entity_window_util.tl:699-703;
--     the town-building window passes the stockList entity, town_building.tl:253-264). A town building
--     has one InputStock per needed cargo (townbuildingutil.lua:222-249), so the stock's count is the
--     cargo's count; several input stocks of one cargo are summed. Zero-read streaks via
--     model.zeroStreak, carried over from `prev`.
--   * position: BOUNDING_VOLUME centre (entity_util.getPosition, base/content/scripts/entity_util.tl:48),
--     read once per building id
--   * Phase 2d: buildingBox = the 2D BOUNDING_VOLUME box of a building (town extent for "Only towns in
--     view"); townName = NAME of a town (in-view header)

local model = ug_require "square_supply_gaps::/supply_gaps/sg_model.tl" as SupplyGapsModel

local gather : SupplyGapsGather = {}

gather.errors = 0
gather.MAX_ERR_LOGS = 20
-- With a line cache: each line re-read at least every LINE_EVERY calls (ticks).
gather.LINE_EVERY = 10

local LOG_PREFIX <const> = "[SQSG] "

local function fail(where : string, msg : any)
	gather.errors = gather.errors + 1
	if gather.errors <= gather.MAX_ERR_LOGS then
		log.message(LOG_PREFIX .. "ERR " .. where .. " " .. tostring(msg))
	end
end

local function setToList(set : {integer : boolean}) : {integer}
	local out : {integer} = {}
	for c in pairs(set) do out[#out + 1] = c end
	table.sort(out)
	return out
end

function gather.passengerCargo() : integer
	local ok, id = pcall(function() : integer
		return api.res.cargoTypeRep.getPassengerCargoTypeId() as integer
	end)
	if ok then return id as integer end
	fail("passenger", id)
	return nil
end

-- Per-call memo of STATION_GROUP / STATION components (they can change between ticks).
local record Reader
	group : function(g : integer) : Engine.Component.StationGroup
	station : function(s : integer) : Station
end

local function newReader() : Reader
	local CT = api.type.ComponentType
	local groups : {integer : Engine.Component.StationGroup} = {}
	local stations : {integer : Station} = {}
	local r : Reader = {}
	r.group = function(g : integer) : Engine.Component.StationGroup
		if groups[g] == nil then
			groups[g] = api.engine.getComponent(g, CT.STATION_GROUP) as Engine.Component.StationGroup
		end
		return groups[g]
	end
	r.station = function(s : integer) : Station
		if stations[s] == nil then
			stations[s] = api.engine.getComponent(s, CT.STATION) as Station
		end
		return stations[s]
	end
	return r
end

--- cargoUnload of the stop's terminal; true when it can't be resolved (the terminal is unknown,
--- e.g. -1 indices on a fresh stop): treat as unloading, like the base when `terminal` is nil
--- (line_util.tl:550-558).
local function stopUnloads(r : Reader, stationGroup : integer, station : integer, terminal : integer) : boolean
	if station == nil or terminal == nil or station < 0 or terminal < 0 then return true end
	local sg = r.group(stationGroup)
	local stationEntity = sg ~= nil and sg.stations ~= nil and sg.stations[station + 1] or nil
	if stationEntity == nil or stationEntity < 0 then return true end
	local st = r.station(stationEntity)
	local t = st ~= nil and st.terminals ~= nil and st.terminals[terminal + 1] or nil
	if t == nil then return true end
	return t.cargoUnload ~= false
end

local function readLine(r : Reader, line : integer) : SupplyGapsLine
	local comp = api.engine.getComponent(line, api.type.ComponentType.LINE) as Engine.Component.Line
	if comp == nil or comp.stops == nil then return nil end
	local carries : {integer : boolean} = {}
	local stops : {SupplyGapsStop} = {}
	for i = 1, #comp.stops do
		local s = comp.stops[i]
		if s.stopConfig ~= nil and s.stopConfig.load ~= nil then
			local load = s.stopConfig.load
			for k = 1, #load do
				if load[k] == true then carries[k - 1] = true end
			end
		end
		stops[#stops + 1] = {
			stationGroup = s.stationGroup as integer,
			unload = stopUnloads(r, s.stationGroup as integer, s.station as integer, s.terminal as integer),
		}
	end
	return { entity = line, carries = setToList(carries), stops = stops }
end

local function sameInts(a : {integer}, b : {integer}) : boolean
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function sameLine(a : SupplyGapsLine, b : SupplyGapsLine) : boolean
	if a == nil or b == nil then return a == b end
	if not sameInts(a.carries, b.carries) or #a.stops ~= #b.stops then return false end
	for i = 1, #a.stops do
		local x, y = a.stops[i], b.stops[i]
		if x.stationGroup ~= y.stationGroup or x.unload ~= y.unload then return false end
	end
	return true
end

function gather.newLineCache() : SupplyGapsLineCache
	return { lines = {}, sig = {}, cursor = -1, list = nil }
end

--- Per line: its (station group, stop index) pairs in the map, as one string ("" never occurs).
local function lineSignatures(map : {integer : {{integer, integer}}}) : {integer : string}
	local parts : {integer : {string}} = {}
	for g, lineStops in pairs(map or {}) do
		for i = 1, #lineStops do
			local ls = lineStops[i]
			local line = ls[1]
			if line ~= nil then
				local p = parts[line]
				if p == nil then
					p = {}
					parts[line] = p
				end
				p[#p + 1] = tostring(g) .. ":" .. tostring(ls[2])
			end
		end
	end
	local out : {integer : string} = {}
	for line, p in pairs(parts) do
		table.sort(p)
		out[line] = table.concat(p, ",")
	end
	return out
end

--- Every line with a stop. Without `lc`: one LINE read per line (stateless). With a line cache
--- (perf review 2026-10-09): the stop map is read every call and a line is re-read at once when it is
--- new or its (group, stop index) set changed (a stop added / removed / moved); the others are
--- re-read round robin, ceil(n / LINE_EVERY) a call (cargo load config, terminal changes). Second
--- result: the list differs from the previous call's (always true without `lc`).
function gather.lines(lc? : SupplyGapsLineCache) : {SupplyGapsLine}, boolean
	local out : {SupplyGapsLine} = {}
	local ok, map = pcall(function() : {integer : {{integer, integer}}}
		return api.engine.system.lineSystem.getStationGroup2LineStopsMap() as {integer : {{integer, integer}}}
	end)
	if not ok then
		fail("lineStopsMap", map)
		if lc ~= nil then
			lc.lines, lc.sig, lc.list = {}, {}, nil
		end
		return out, true
	end
	if lc == nil then
		local seen : {integer : boolean} = {}
		for __, lineStops in pairs(map as {integer : {{integer, integer}}} or {}) do
			for i = 1, #lineStops do
				local line = lineStops[i][1]
				if line ~= nil then seen[line] = true end
			end
		end
		local r = newReader()
		for __, line in ipairs(setToList(seen)) do
			local okLine, info = pcall(readLine, r, line)
			if not okLine then
				fail("line " .. tostring(line), info)
			elseif info ~= nil then
				out[#out + 1] = info as SupplyGapsLine
			end
		end
		return out, true
	end

	local sig = lineSignatures(map as {integer : {{integer, integer}}})
	local ids : {integer} = {}
	for line in pairs(sig) do ids[#ids + 1] = line end
	table.sort(ids)
	local changed = lc.list == nil
	-- lines gone from the map
	for line in pairs(lc.sig) do
		if sig[line] == nil then
			lc.sig[line] = nil
			if lc.lines[line] ~= nil then
				lc.lines[line] = nil
				changed = true
			end
		end
	end
	local pick : {integer : boolean} = {}
	for __, line in ipairs(ids) do
		if lc.lines[line] == nil or lc.sig[line] ~= sig[line] then pick[line] = true end
	end
	-- round robin over the rest, ascending after the cursor, wrapping once
	local n = #ids
	if n > 0 then
		local k = math.floor((n + gather.LINE_EVERY - 1) / gather.LINE_EVERY)
		local start = 1
		for i = 1, n do
			if ids[i] > lc.cursor then
				start = i
				break
			end
			if i == n then start = 1 end
		end
		local i = start
		local taken = 0
		for __ = 1, n do
			if taken >= k then break end
			local line = ids[i]
			if not pick[line] then
				pick[line] = true
				taken = taken + 1
				lc.cursor = line
			end
			i = i % n + 1
		end
	end
	local r = newReader()
	for __, line in ipairs(ids) do
		if pick[line] then
			lc.sig[line] = sig[line]
			local okLine, info = pcall(readLine, r, line)
			if not okLine then fail("line " .. tostring(line), info) end
			-- a failing / missing line is left uncached, so it is retried next call
			local rec : SupplyGapsLine = okLine and info as SupplyGapsLine or nil
			if not sameLine(lc.lines[line], rec) then changed = true end
			lc.lines[line] = rec
		end
	end
	if not changed and lc.list ~= nil then return lc.list, false end
	for __, line in ipairs(ids) do
		local rec = lc.lines[line]
		if rec ~= nil then out[#out + 1] = rec end
	end
	lc.list = out
	return out, true
end

function gather.unloadGroups() : {integer}
	local out : {integer} = {}
	local ok, groups = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.STATION_GROUP)
	if not ok then
		fail("stationGroups", groups)
		return out
	end
	local r = newReader()
	local sorted : {integer} = {}
	for __, g in ipairs(groups as {integer} or {}) do sorted[#sorted + 1] = g end
	table.sort(sorted)
	for __, g in ipairs(sorted) do
		local okG, unloads = pcall(function() : boolean
			local sg = r.group(g)
			for __, s in ipairs(sg ~= nil and sg.stations or {}) do
				if s >= 0 then
					local st = r.station(s)
					for __, t in ipairs(st ~= nil and st.terminals or {}) do
						if t.cargoUnload == true then return true end
					end
				end
			end
			return false
		end)
		if not okG then
			fail("group " .. tostring(g), unloads)
		elseif unloads then
			out[#out + 1] = g
		end
	end
	return out
end

function gather.groupStations(groups : {integer}) : {integer : {integer}}
	local out : {integer : {integer}} = {}
	local r = newReader()
	for __, g in ipairs(groups or {}) do
		local ok, stations = pcall(function() : {integer}
			local sg = r.group(g)
			if sg == nil or sg.stations == nil then return nil end
			local list : {integer} = {}
			for i = 1, #sg.stations do
				local s = sg.stations[i]
				if s ~= nil and s >= 0 then list[#list + 1] = s end
			end
			return list
		end)
		if not ok then
			fail("groupStations " .. tostring(g), stations)
		elseif stations ~= nil then
			out[g] = stations as {integer}
		end
	end
	return out
end

function gather.buildingMap() : integer, {integer : {integer}}
	local ok, map = pcall(function() : {integer : {integer}}
		return api.engine.system.townBuildingSystem.getTown2BuildingMap() as {integer : {integer}}
	end)
	if not ok or map == nil then
		if not ok then fail("town2BuildingMap", map) end
		return 0, {}
	end
	local n = 0
	for __, list in pairs(map as {integer : {integer}}) do n = n + #list end
	return n, map as {integer : {integer}}
end

local function positionOf(entity : integer) : {number}
	local bv = api.engine.getComponent(entity, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil or bv.bbox == nil then return nil end
	local mn, mx = bv.bbox.min, bv.bbox.max
	return { 0.5 * (mn.x + mx.x), 0.5 * (mn.y + mx.y), 0.5 * (mn.z + mx.z) }
end

--- Units in stock `stockId0` of `stockList`; nil when the read fails (streak then unchanged).
local function stockCount(stockList : integer, stockId0 : integer) : integer
	local ok, n = pcall(function() : integer
		return api.engine.system.simEntityAtStockSystem.getStockCount(stockList, stockId0 as StockId) as integer
	end)
	if ok and type(n) == "number" then return n as integer end
	if not ok then fail("stock " .. tostring(stockList) .. ":" .. tostring(stockId0), n) end
	return nil
end

local function readBuilding(b : integer, town : integer, prev : SupplyGapsBuilding, passenger : integer) : SupplyGapsBuilding
	local CT = api.type.ComponentType
	local tb = api.engine.getComponent(b, CT.TOWN_BUILDING) as Engine.Component.TownBuilding
	if tb == nil then return nil end
	local stockList = tb.stockList as integer
	local needs : {integer : boolean} = {}
	local stock : {integer : integer} = {}
	local failed : {integer : boolean} = {}
	if stockList ~= nil and stockList >= 0 then
		local sl = api.engine.getComponent(stockList, CT.STOCK_LIST) as Engine.Component.StockList
		local inputType = api.type["enum"].StockListType.InputStock
		if sl ~= nil and sl.stocks ~= nil then
			for i = 1, #sl.stocks do
				local s = sl.stocks[i]
				local c = s.cargoType as integer
				if s.type == inputType and c ~= nil and c >= 0 and c ~= passenger then
					needs[c] = true
					local n = stockCount(stockList, i - 1)
					if n == nil then
						failed[c] = true
					else
						stock[c] = (stock[c] or 0) + n
					end
				end
			end
		end
	end
	local zeroReads : {integer : integer} = {}
	local prevZero : {integer : integer} = prev ~= nil and prev.zeroReads or {}
	for c in pairs(needs) do
		if failed[c] then stock[c] = nil end
		zeroReads[c] = model.zeroStreak(prevZero[c], stock[c])
	end
	-- Land use and position only matter for a building with needs (the overlay drops the others):
	-- two component reads saved per re-read of every building without needs (perf review).
	local landUse = 0
	local pos : {number} = prev ~= nil and prev.pos or nil
	if next(needs) ~= nil then
		if tb.personCapacity ~= nil and tb.personCapacity >= 0 then
			local pc = api.engine.getComponent(tb.personCapacity, CT.PERSON_CAPACITY) as Engine.Component.PersonCapacity
			if pc ~= nil and pc.type ~= nil then landUse = pc.type as integer + 1 end
		end
		if pos == nil then pos = positionOf(b) end
	end
	return {
		entity = b,
		town = (tb.town as integer) or town,
		landUse = landUse,
		needs = setToList(needs),
		stockList = stockList,
		pos = pos,
		stock = stock,
		zeroReads = zeroReads,
	}
end

function gather.readBuilding(b : integer, town : integer, prev : SupplyGapsBuilding, passenger : integer) : SupplyGapsBuilding, boolean
	local ok, info = pcall(readBuilding, b, town, prev, passenger)
	if not ok then
		fail("building " .. tostring(b), info)
		return nil, false
	end
	return info as SupplyGapsBuilding, true
end

--- Flat id list (towns ascending, engine order inside a town) and the town of each. With the previous
--- result given and the map unchanged, returns those same tables and false (no allocation; perf review).
function gather.flatten(map : {integer : {integer}}, prevIds? : {integer}, prevTownOf? : {integer}) : {integer}, {integer}, boolean
	local towns : {integer} = {}
	for t in pairs(map or {}) do towns[#towns + 1] = t end
	table.sort(towns)
	if prevIds ~= nil and prevTownOf ~= nil then
		local k = 0
		local same = true
		for __, t in ipairs(towns) do
			local list = map[t]
			for i = 1, #list do
				k = k + 1
				if prevIds[k] ~= list[i] or prevTownOf[k] ~= t then
					same = false
					break
				end
			end
			if not same then break end
		end
		if same and k == #prevIds then return prevIds, prevTownOf, false end
	end
	local ids : {integer} = {}
	local townOf : {integer} = {}
	for __, t in ipairs(towns) do
		local list = map[t]
		for i = 1, #list do
			ids[#ids + 1] = list[i]
			townOf[#townOf + 1] = t
		end
	end
	return ids, townOf, true
end

function gather.buildingBox(b : integer) : SupplyGapsBox
	local bv = api.engine.getComponent(b, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil or bv.bbox == nil then return nil end
	local mn, mx = bv.bbox.min, bv.bbox.max
	return { math.min(mn.x, mx.x), math.min(mn.y, mx.y), math.max(mn.x, mx.x), math.max(mn.y, mx.y) }
end

function gather.townName(t : integer) : string
	local nameComp = api.engine.getComponent(t, api.type.ComponentType.NAME) as Engine.Component.Name
	return nameComp ~= nil and nameComp.name or ""
end

return gather
