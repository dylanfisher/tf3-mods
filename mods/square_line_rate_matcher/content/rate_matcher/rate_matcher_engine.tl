-- Line Rate Matcher: engine adapter (plans/square_line_rate_matcher/PLAN.md phase 2). READ-ONLY: it turns the
-- game's components into the plain records of rate_matcher_types.d.tl that rate_matcher_model.tl consumes.
-- Commands (buy / set line / sell / replace window) live in rate_matcher_commands.tl.
--
-- Every engine read is in a pcall; a failed read returns nil + a short reason ("not_a_line", or "read: <err>").
-- Engine components and their vectors are userdata (production_label_pickup.tl engineAdapter): everything
-- returned here is copied into plain tables.
--
-- Ported from the in-game probe (mods/square_line_rate_matcher_probe/content/rmprobe/rmprobe.script.lua,
-- logs plans/square_line_rate_matcher/probe_run*.log, docs/findings.md "Line Rate, cloning onto a line, sell
-- on arrival"):
--   * vehicles: transportVehicleSystem.getLineVehicles; TRANSPORT_VEHICLE.config.capacities is indexed by
--     cargo + 1; purchaseTime of the first part; sellOnArrival.
--   * Rate: api.engine.util.line.calcLineStationThroughput (per year, linear in identical vehicles).
--   * supply: stop -> STATION_GROUP.stations -> catchmentAreaSystem.getStationCatchables(station, true), or for
--     built-in industry stations the station construction's industries; producer = STOCK_LIST entity or
--     INDUSTRY.stockList; outputs = getInputsOutputsFromRules(stockList)[2]; maxPerYear =
--     getCargoMaxProductionPerYear (the industry window's 101), producedPerYear = getCargoProducedPerYear.
--   * other lines at a group: the probe used getStationGroup2LineStopsMap()[group]; here
--     lineSystem.getLinesForStationGroup(group) (system.d.tl:37-40, one group at a time, NOT yet run in game)
--     with the map as the fallback. Their stops carry loads only (no producers): the model matches them by
--     the shared station group.
-- Model catalogue: the vehicle store's own rules (base .cache/game/base/content/gui/line_vehicle_mgmt/):
--   * models = modelRep.forEachModelWithMetadata("transportVehicle") (vehicle_store_window.tl:4790-4820);
--   * year = getCalendarDate(GAME_TIME.gameTime).year (vehicle_store_window.tl:2698-2700); availability
--     yearFrom/yearTo folded like collectVehicleData (vehicle_store_util.tl:315-320) and filtered like
--     vehicleFilter (:731-736);
--   * carrier + transport modes as the Replace window gets them: line_util.getLineAndVehicleCompatibleTransport
--     ModesAndCarrier (line_util.tl:1629-1720, radar_fleet.tl replaceVehicles), filter tags as
--     vehicle_store_util.getVehicleFilterTags (:1213) + depotMatchesVehicleFilterTags (:636-667), the mission
--     vehicleFilter by model path (:711-718);
--   * capacity per cargo like getVehicleCargoCapacities (:57-104), top speed like getTopSpeed (:107-120), name
--     = description.name (getVehicleNameAndIcons, :465-475).
-- Only single-part vehicles get alternatives (road, water, air, single-car trams): a train's "model" is a
-- consist, and multiple units are not single models.
--
-- Costs and timing (2026-10-10, after the second GUI test; rate_matcher_model.tl header):
--   * vehicle capital = sum over parts of metadata cost.price x yearMs / lifespanMs (model.capitalPerYear), lifespan
--     = maintenance.lifespan x 1000 game ms (vehicle_util.getLifespan, vehicle_util.tl:31-34), yearMs = the calendar
--     year at the current speed: api.util.getYearDuration(GAME_SPEED.millisPerDay), default year when paused
--     (Problem Radar's radar_checks.calendarYearMs, docs/findings.md "vehicle age units").
--   * line timing = transportVehicleSystem.getLineCargoInfo(line, cargo) (system.d.tl:393-396): sum of sectionTimes
--     ("scheduled times for each section") vs driveSectionTimes ("drive times"), type.d.tl:4185-4199. Not used by
--     the base GUI, so its units / meaning are NOT verified in game: the window logs it ("[RateMatcher] timing").
--
-- Threads: plain engine reads (no api.gui), safe from a click handler or react.onStep; phase 3 decides.

local model = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_model.tl" as SquareRateMatcherModel

local engine : SquareRateMatcherEngine = {}

local function optional(path : string) : any
	local ok, m = pcall(ug_require, path)
	if ok and type(m) == "table" then return m end
	return nil
end

local lineUtilCache : LineUtil = nil
local function lineUtil() : LineUtil
	if lineUtilCache == nil then
		lineUtilCache = optional("::/gui/line_vehicle_mgmt/line_util.tl") as LineUtil
	end
	return lineUtilCache
end

local function fail(err : any) : string
	return "read: " .. tostring(err)
end

local function finite(v : any) : number
	if type(v) ~= "number" then return nil end
	local n = v as number
	if n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

-- pure rules -------------------------------------------------------------------------------

function engine.isAvailable(yearFrom : integer, yearTo : integer, year : integer) : boolean
	if year == nil then return true end
	-- collectVehicleData: start -1 / 5000, take the model's value unless it is -1.
	local from, to = -1, 5000
	if yearFrom ~= nil and yearFrom ~= -1 then from = math.max(from, yearFrom) end
	if yearTo ~= nil and yearTo ~= -1 then to = math.min(to, yearTo) end
	if from > 0 and year < from then return false end
	if to > 0 and year >= to then return false end
	return true
end

function engine.matchesFilterTags(modelTags : {string}, lineTags : {string}) : boolean
	if lineTags == nil then return true end
	local found : {string : boolean} = {}
	for __, t in ipairs(lineTags) do found[t] = false end
	local filterOut = true -- models with no tags are filtered out
	for __, t in ipairs(modelTags or {}) do
		if found[t] ~= nil then
			found[t] = true
			filterOut = false
		end
	end
	for __, f in pairs(found) do
		if not f then filterOut = true end
	end
	if #lineTags == 0 and modelTags ~= nil and #modelTags > 0 then filterOut = false end
	return not filterOut
end

function engine.matchesTransportModes(modelModes : {TransportMode}, allowed : {TransportMode : boolean}) : boolean
	if allowed == nil then return true end
	for __, m in ipairs(modelModes or {}) do
		if allowed[m] == true then return true end
	end
	return false
end

function engine.cargoCapacity(tv : ModelMetadata.TransportVehicle, cargo : integer) : number
	if tv == nil or tv.compartments == nil or cargo == nil then return 0 end
	local total = 0
	for __, compartment in ipairs(tv.compartments) do
		local best = 0
		for __, lc in ipairs(compartment.loadConfigs or {}) do
			local entry = lc.cargoEntry
			if entry ~= nil and entry.cargoTypeSet ~= nil then
				local takes = false
				api.res.cargoTypeRep.forEachCargoType(entry.cargoTypeSet, function(c : CargoTypeId)
					if c == cargo then takes = true end
				end)
				if takes and (entry.capacity or 0) > best then best = entry.capacity end
			end
		end
		total = total + best
	end
	return total
end

function engine.currentFor(info : SquareRateMatcherModelInfo, perVehicle : number) : SquareRateMatcherCurrent
	if info == nil then return nil end
	return { model = info.model, capacity = info.capacity, speed = info.speed, perVehicle = perVehicle,
		loadSpeed = info.loadSpeed }
end

function engine.candidatesOf(catalogue : {SquareRateMatcherModelInfo}) : {SquareRateMatcherCandidate}
	local out : {SquareRateMatcherCandidate} = {}
	for __, m in ipairs(catalogue or {}) do
		out[#out + 1] = { model = m.model, capacity = m.capacity, speed = m.speed, loadSpeed = m.loadSpeed }
	end
	return out
end

local DEFAULT_YEAR_MS <const> = 1460000 -- 365 days x 4 s (model_metadata_util.lua:500-501); fallback only

function engine.calendarYearMs(millisPerDay : integer, yearDuration : function(integer) : integer, defaultYearMs : integer) : integer
	local fallback = (defaultYearMs ~= nil and defaultYearMs > 0) and defaultYearMs or DEFAULT_YEAR_MS
	if type(millisPerDay) ~= "number" or millisPerDay <= 0 or yearDuration == nil then return fallback end
	local ok, y = pcall(yearDuration, math.floor(millisPerDay))
	if ok and type(y) == "number" and y > 0 then return math.floor(y) end
	return fallback
end

-- reads ------------------------------------------------------------------------------------

function engine.yearMs() : integer
	local util = api.util
	local defaultYear : number = nil
	if util ~= nil and util.getDefaultYearDuration ~= nil then
		local okDef, def = pcall(util.getDefaultYearDuration)
		defaultYear = okDef and finite(def) or nil
	end
	local ok, mpd = pcall(function() : integer
		local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
		return gs ~= nil and gs.millisPerDay or 0
	end)
	return engine.calendarYearMs(ok and mpd or 0, util ~= nil and util.getYearDuration or nil, defaultYear as integer)
end

local function modelMetadata(modelId : integer) : {string : any}
	local m = api.res.modelRep.get(modelId)
	return m ~= nil and m.metadata as {string : any} or nil
end

-- store price and lifespan (game ms) of a model; nil when unknown
local function priceAndLife(modelId : integer) : number, number
	local md = modelMetadata(modelId)
	if md == nil then return nil, nil end
	local cost = md["cost"] as ModelMetadata.Cost
	local maintenance = md["maintenance"] as ModelMetadata.Maintenance
	local price = cost ~= nil and finite(cost.price) or nil
	if price ~= nil and price < 0 then price = nil end
	local life = maintenance ~= nil and finite(maintenance.lifespan) or nil
	return price, life ~= nil and life * 1000 or nil
end

-- per year: each part's price over its lifespan; nil when one part is unknown
local function capitalOf(parts : {TransportVehiclePart}, yearMs : integer) : number
	local sum = 0.0
	for __, part in ipairs(parts or {}) do
		local price, life = priceAndLife(part.part.modelId)
		local c = model.capitalPerYear(price, life, yearMs)
		if c == nil then return nil end
		sum = sum + c
	end
	return sum
end

local function isLine(e : integer) : boolean
	return type(e) == "number" and e >= 0 and api.engine.entityExists(e)
		and api.engine.getComponent(e, api.type.ComponentType.LINE) ~= nil
end

function engine.currentYear() : integer, string
	local ok, y = pcall(function() : integer
		local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
		return api.engine.util.getCalendarDate(gt.gameTime).year
	end)
	if not ok then return nil, fail(y) end
	return y, nil
end

function engine.lineRate(line : integer) : number, string
	local ok, r = pcall(function() : number
		if not isLine(line) then return nil end
		return api.engine.util.line.calcLineStationThroughput(line)
	end)
	if not ok then return nil, fail(r) end
	if r == nil then return nil, "not_a_line" end
	return finite(r) or 0, nil
end

local function readVehicle(v : integer, protected : {integer : any}, yearMs : integer) : SquareRateMatcherVehicle
	local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
	if tv == nil then return nil end
	local parts = tv.transportVehicleConfig ~= nil and tv.transportVehicleConfig.vehicles or nil
	local first = parts ~= nil and parts[1] or nil
	local caps : {integer : number} = {}
	if tv.config ~= nil and tv.config.capacities ~= nil then
		for k, c in ipairs(tv.config.capacities as {number}) do
			if c ~= nil and c > 0 then caps[k - 1] = c end
		end
	end
	-- resale value as the Replace window refunds it (vehicle_store_window.tl:3525-3541) and the running cost per
	-- year the vehicle window shows (entity_window_util.tl:162); util.d.tl:461-468
	local okVal, value = pcall(api.engine.util.vehicle.getDepreciatedValue, v)
	local okRun, running = pcall(api.engine.util.vehicle.getRunningCost, v)
	local okCap, capital = pcall(capitalOf, parts, yearMs)
	return {
		id = v,
		model = first ~= nil and first.part ~= nil and first.part.modelId or nil,
		capacities = caps,
		purchaseTime = first ~= nil and first.purchaseTime or nil,
		protected = protected ~= nil and protected[v] ~= nil and protected[v] ~= false,
		selling = tv.sellOnArrival == true,
		value = okVal and finite(value) or nil,
		running = okRun and finite(running) or nil,
		capital = okCap and finite(capital) or nil,
	}
end

function engine.lineVehicles(line : integer, protected? : {integer : any}) : {SquareRateMatcherVehicle}, string
	local ok, res = pcall(function() : {SquareRateMatcherVehicle}
		if not isLine(line) then return nil end
		local out : {SquareRateMatcherVehicle} = {}
		local yearMs = engine.yearMs()
		for __, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line) or {}) do
			local rec = readVehicle(v, protected, yearMs)
			if rec ~= nil then out[#out + 1] = rec end
		end
		return out
	end)
	if not ok then return nil, fail(res) end
	if res == nil then return nil, "not_a_line" end
	return res, nil
end

-- supply -----------------------------------------------------------------------------------

local function loadsOf(s : Engine.Component.Line.Stop) : {integer : boolean}
	local out : {integer : boolean} = {}
	if s.stopConfig ~= nil and s.stopConfig.load ~= nil then
		for k, b in ipairs(s.stopConfig.load) do
			if b == true then out[k - 1] = true end
		end
	end
	return out
end

-- Entities reachable from a station group (probe `reachable`, production_label_pickup.tl reachableStockLists).
local function reachable(stationGroup : integer) : {integer}
	local CT = api.type.ComponentType
	local sg = api.engine.getComponent(stationGroup, CT.STATION_GROUP) as Engine.Component.StationGroup
	local out : {integer} = {}
	local seen : {integer : boolean} = {}
	local function add(e : integer)
		if e ~= nil and e >= 0 and not seen[e] then
			seen[e] = true
			out[#out + 1] = e
		end
	end
	if sg == nil or sg.stations == nil then return out end
	for __, station in ipairs(sg.stations) do
		local catchables = station >= 0 and api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or nil
		if catchables ~= nil and #catchables > 0 then
			for __, e in ipairs(catchables) do add(e) end
		elseif station >= 0 then
			local con = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
			local conComp = (con ~= nil and con >= 0) and api.engine.getComponent(con, CT.CONSTRUCTION) as Engine.Component.Construction or nil
			if conComp ~= nil and conComp.industries ~= nil then
				for __, industry in ipairs(conComp.industries) do add(industry) end
			end
		end
	end
	return out
end

-- Producers of the group: one per (stockList, output cargo), each stockList once.
local function producersAt(stationGroup : integer) : {SquareRateMatcherProducer}
	local CT = api.type.ComponentType
	local out : {SquareRateMatcherProducer} = {}
	local seenStock : {integer : boolean} = {}
	for __, e in ipairs(reachable(stationGroup)) do
		local stockList : integer = nil
		if api.engine.getComponent(e, CT.STOCK_LIST) ~= nil then
			stockList = e
		else
			local ind = api.engine.getComponent(e, CT.INDUSTRY) as Engine.Component.Industry
			if ind ~= nil then stockList = ind.stockList end
		end
		if stockList ~= nil and stockList >= 0 and not seenStock[stockList] then
			seenStock[stockList] = true
			local okIo, io = pcall(api.engine.util.stock.getInputsOutputsFromRules, stockList)
			local outputs = okIo and io ~= nil and io[2] or nil
			for __, c in ipairs(outputs or {}) do
				local okMax, max = pcall(api.engine.util.stock.getCargoMaxProductionPerYear, stockList, c)
				local okPr, produced = pcall(api.engine.util.stock.getCargoProducedPerYear, stockList, c)
				out[#out + 1] = {
					stockList = stockList,
					cargo = c,
					maxPerYear = okMax and finite(max) or 0,
					producedPerYear = okPr and finite(produced) or nil,
				}
			end
		end
	end
	return out
end

-- Lines stopping at a group: getLinesForStationGroup, else the global map (the probe's call).
local function linesAt(stationGroup : integer, mapRef : {{integer : {{integer, integer}}}}) : {integer}
	local ok, lines = pcall(api.engine.system.lineSystem.getLinesForStationGroup, stationGroup)
	if ok and lines ~= nil then
		local out : {integer} = {}
		for __, l in ipairs(lines) do out[#out + 1] = l end
		return out
	end
	if mapRef[1] == nil then
		mapRef[1] = api.engine.system.lineSystem.getStationGroup2LineStopsMap() as {integer : {{integer, integer}}} or {}
	end
	local out : {integer} = {}
	local seen : {integer : boolean} = {}
	for __, ls in ipairs(mapRef[1][stationGroup] or {}) do
		local l = ls[1]
		if l ~= nil and not seen[l] then
			seen[l] = true
			out[#out + 1] = l
		end
	end
	return out
end

local function otherLine(l : integer) : SquareRateMatcherOtherLine
	local comp = api.engine.getComponent(l, api.type.ComponentType.LINE) as Engine.Component.Line
	if comp == nil then return nil end
	local stops : {SquareRateMatcherStop} = {}
	for __, s in ipairs(comp.stops or {}) do
		stops[#stops + 1] = { stationGroup = s.stationGroup, loads = loadsOf(s) }
	end
	local okRate, rate = pcall(api.engine.util.line.calcLineStationThroughput, l)
	return { line = l, rate = okRate and finite(rate) or 0, stops = stops }
end

function engine.supplyInput(line : integer) : SquareRateMatcherSupplyInput, string
	local ok, res = pcall(function() : SquareRateMatcherSupplyInput
		if not isLine(line) then return nil end
		local comp = api.engine.getComponent(line, api.type.ComponentType.LINE) as Engine.Component.Line
		local passenger = api.res.cargoTypeRep.getPassengerCargoTypeId()
		local stops : {SquareRateMatcherStop} = {}
		local producersOf : {integer : {SquareRateMatcherProducer}} = {}
		local seenGroup : {integer : boolean} = {}
		local groups : {integer} = {}
		for __, s in ipairs(comp.stops or {}) do
			local g = s.stationGroup
			local loads = loadsOf(s)
			local anyCargo = false
			for c, __ in pairs(loads) do
				if c ~= passenger then anyCargo = true end
			end
			local producers : {SquareRateMatcherProducer} = {}
			if g ~= nil and g >= 0 then
				if anyCargo and not seenGroup[g] then
					seenGroup[g] = true
					groups[#groups + 1] = g
				end
				-- Only groups where we load some cargo need the catchment walk (once per group).
				if anyCargo and producersOf[g] == nil then producersOf[g] = producersAt(g) end
				producers = producersOf[g] or {}
			end
			stops[#stops + 1] = { stationGroup = g, loads = loads, producers = producers }
		end
		-- Other lines at the groups where we load cargo (the only ones the model compares), each line once.
		local mapRef : {{integer : {{integer, integer}}}} = {}
		local seenLine : {integer : boolean} = { [line] = true }
		local others : {SquareRateMatcherOtherLine} = {}
		for __, g in ipairs(groups) do
			for __, l in ipairs(linesAt(g, mapRef)) do
				if not seenLine[l] then
					seenLine[l] = true
					local o = otherLine(l)
					if o ~= nil then others[#others + 1] = o end
				end
			end
		end
		return { line = line, stops = stops, otherLines = others, passengerCargo = passenger }
	end)
	if not ok then return nil, fail(res) end
	if res == nil then return nil, "not_a_line" end
	return res, nil
end

local function sumOf(list : {number}) : number, integer
	local sum, n = 0.0, 0
	for __, t in ipairs(list or {}) do
		local x = finite(t)
		if x ~= nil then sum, n = sum + x, n + 1 end
	end
	return sum, n
end

function engine.lineTiming(line : integer, cargo : integer) : SquareRateMatcherLineTiming, string
	local ok, res = pcall(function() : SquareRateMatcherLineTiming
		if not isLine(line) then return nil end
		local c = cargo
		if c == nil then c = api.res.cargoTypeRep.getPassengerCargoTypeId() end
		local info = api.engine.system.transportVehicleSystem.getLineCargoInfo(line, c)
		local out : SquareRateMatcherLineTiming = { cargo = c }
		local okF, f = pcall(api.engine.util.line.getMaxFrequency, line)
		out.maxFrequency = okF and finite(f) or nil
		if info == nil then return out end
		local sections : {number} = {}
		local drives : {number} = {}
		for __, t in ipairs(info.sectionTimes or {}) do sections[#sections + 1] = t end
		for __, t in ipairs(info.driveSectionTimes or {}) do drives[#drives + 1] = t end
		out.section, out.sections = sumOf(sections)
		out.drive = sumOf(drives)
		out.loadShare = model.loadShare(sections, drives)
		return out
	end)
	if not ok then return nil, fail(res) end
	if res == nil then return nil, "not_a_line" end
	return res, nil
end

function engine.readLine(line : integer, protected? : {integer : any}) : SquareRateMatcherLineData, string
	local rate, err = engine.lineRate(line)
	if rate == nil then return nil, err end
	local vehicles, err2 = engine.lineVehicles(line, protected)
	if vehicles == nil then return nil, err2 end
	local supply, err3 = engine.supplyInput(line)
	if supply == nil then return nil, err3 end
	local year = engine.currentYear()
	return {
		line = line,
		rate = rate,
		vehicles = vehicles,
		supply = supply,
		passengerCargo = supply.passengerCargo,
		year = year,
	}, nil
end

-- model catalogue --------------------------------------------------------------------------

local function topSpeed(md : {string : any}) : number
	for __, key in ipairs({ "landVehicle", "waterVehicle", "airVehicle" }) do
		local v = md[key] as ModelMetadata.LandVehicle
		if v ~= nil and finite(v.topSpeed) ~= nil then return v.topSpeed end
	end
	return 0
end

local function infoOf(modelId : integer, path : string, md : {string : any}, cargo : integer, year : integer, yearMs : integer) : SquareRateMatcherModelInfo
	local tv = md["transportVehicle"] as ModelMetadata.TransportVehicle
	if tv == nil then return nil end
	local desc = md["description"] as ModelMetadata.Description
	local avail = md["availability"] as ModelMetadata.Availability
	local cost = md["cost"] as ModelMetadata.Cost
	-- per year: the store sums maintenance.runningCosts and shows "{cost}/year" (vehicle_store_util.tl:310,
	-- vehicle_store_window.tl:118-125)
	local maintenance = md["maintenance"] as ModelMetadata.Maintenance
	local price = cost ~= nil and cost.price or nil
	local life = maintenance ~= nil and finite(maintenance.lifespan) or nil
	local lifespanMs = life ~= nil and life * 1000 or nil
	return {
		model = modelId,
		path = path,
		name = desc ~= nil and desc.name or path,
		capacity = engine.cargoCapacity(tv, cargo),
		speed = topSpeed(md),
		price = price,
		running = maintenance ~= nil and finite(maintenance.runningCosts) or nil,
		available = engine.isAvailable(avail ~= nil and avail.yearFrom or -1, avail ~= nil and avail.yearTo or -1, year),
		loadSpeed = finite(tv.loadSpeed),
		lifespanMs = lifespanMs,
		capital = model.capitalPerYear(price, lifespanMs, yearMs),
	}
end

function engine.modelInfo(modelId : integer, cargo : integer, year? : integer) : SquareRateMatcherModelInfo, string
	local ok, res = pcall(function() : SquareRateMatcherModelInfo
		local md = modelMetadata(modelId)
		if md == nil then return nil end
		return infoOf(modelId, api.res.modelRep.getName(modelId), md, cargo, year or engine.currentYear(), engine.yearMs())
	end)
	if not ok then return nil, fail(res) end
	if res == nil then return nil, "not_a_vehicle_model" end
	return res, nil
end

-- Carrier, allowed transport modes and filter tags of the line's vehicles (what the Replace window filters by).
local record LineVehicleKind
	carrier : Carrier
	modes : {TransportMode : boolean}
	tags : {string}
	multiPart : boolean
end

local function kindOf(vehicleIds : {integer}) : LineVehicleKind, string
	local carrier : Carrier = nil
	local ownModes : {TransportMode : boolean} = {}
	local tags : {string} = {}
	local tagSeen : {string : boolean} = {}
	local multiPart = false
	for __, v in ipairs(vehicleIds) do
		local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
		if tv == nil then return nil, "vehicle_gone" end
		if carrier == nil then
			carrier = tv.carrier
		elseif carrier ~= tv.carrier then
			return nil, "mixed_carriers"
		end
		if tv.config ~= nil and tv.config.transportModes ~= nil then
			for k, b in pairs(tv.config.transportModes) do
				if b then ownModes[k] = true end
			end
		end
		local parts = tv.transportVehicleConfig.vehicles
		if #parts ~= 1 then multiPart = true end
		for __, part in ipairs(parts) do
			local md = modelMetadata(part.part.modelId)
			local mtv = md ~= nil and md["transportVehicle"] as ModelMetadata.TransportVehicle or nil
			for __, t in ipairs(mtv ~= nil and mtv.filterTags or {}) do
				if not tagSeen[t] then
					tagSeen[t] = true
					tags[#tags + 1] = t
				end
			end
		end
	end
	if carrier == nil then return nil, "no_vehicles" end
	local modes = ownModes
	local lu = lineUtil()
	if lu ~= nil then
		local ok, tmc = pcall(lu.getLineAndVehicleCompatibleTransportModesAndCarrier, vehicleIds)
		if ok and tmc ~= nil and tmc.carrier ~= nil and tmc.transportModes ~= nil and next(tmc.transportModes) ~= nil then
			modes = tmc.transportModes
		end
	end
	return { carrier = carrier, modes = modes, tags = tags, multiPart = multiPart }, nil
end

local function contains(list : {string}, s : string) : boolean
	for __, x in ipairs(list or {}) do
		if x == s then return true end
	end
	return false
end

--- Buyable models (this year) of the line vehicles' carrier and transport modes that carry `cargo`
--- (capacity > 0), sorted by model id; the line's own models are included when they are still buyable.
--- nil + "multi_part" for trains / multi-part vehicles, "mixed_carriers", "no_vehicles", "vehicle_gone".
function engine.modelCatalogue(vehicleIds : {integer}, cargo : integer, opts? : SquareRateMatcherCatalogueOptions) : {SquareRateMatcherModelInfo}, string
	local ok, res, reason = pcall(function() : {SquareRateMatcherModelInfo}, string
		if vehicleIds == nil or #vehicleIds == 0 then return nil, "no_vehicles" end
		local kind, why = kindOf(vehicleIds)
		if kind == nil then return nil, why end
		if kind.multiPart or kind.carrier == api.type["enum"].Carrier.RAIL then return nil, "multi_part" end
		local year = opts ~= nil and opts.year or engine.currentYear()
		local yearMs = engine.yearMs()
		local vf = opts ~= nil and opts.vehicleFilter or nil
		local out : {SquareRateMatcherModelInfo} = {}
		api.res.modelRep.forEachModelWithMetadata("transportVehicle", function(path : string)
			local okOne, err : boolean, any = pcall(function()
				if vf ~= nil then
					if vf.enabledVehicles ~= nil and #vf.enabledVehicles > 0 and not contains(vf.enabledVehicles, path) then return end
					if vf.disabledVehicles ~= nil and #vf.disabledVehicles > 0 and contains(vf.disabledVehicles, path) then return end
				end
				local id = api.res.modelRep.find(path) as integer
				if id == nil or id < 0 then return end
				local md = modelMetadata(id)
				local tv = md ~= nil and md["transportVehicle"] as ModelMetadata.TransportVehicle or nil
				if tv == nil or tv.carrier ~= kind.carrier then return end
				if not engine.matchesTransportModes(tv.transportModes, kind.modes) then return end
				if not engine.matchesFilterTags(tv.filterTags, kind.tags) then return end
				local info = infoOf(id, path, md, cargo, year, yearMs)
				if info ~= nil and info.available and info.capacity > 0 and info.speed > 0 then
					out[#out + 1] = info
				end
			end)
			if not okOne then log.warning("[RateMatcher] model " .. tostring(path) .. " skipped: " .. tostring(err)) end
		end)
		table.sort(out, function(a : SquareRateMatcherModelInfo, b : SquareRateMatcherModelInfo) : boolean
			return a.model < b.model
		end)
		return out, nil
	end)
	if not ok then return nil, fail(res) end
	return res, reason
end

return engine
