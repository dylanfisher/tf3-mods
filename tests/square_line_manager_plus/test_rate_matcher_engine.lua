-- rate_matcher_engine + rate_matcher_commands against a small fake api: line reading (vehicles, capacities by
-- cargo + 1, protected / selling), the supply walk (catchables, built-in industry station fallback, stockList
-- dedupe, other lines per group with the map fallback), the model catalogue (carrier, transport modes, filter
-- tags, availability year rule, mission vehicleFilter, cargo capacity, multi-part refusal), and the commands
-- (clone with depot fallbacks, money cap, mission refusal, failed buy; sell skipping; replace window event).
-- Shapes follow the probe (mods/square_line_rate_matcher_probe) and plans/square_line_manager_plus/rm_probe_run*.log.

local engine, commands, model

local function load()
	engine = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_engine.tl"
	commands = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_commands.tl"
	model = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_model.tl"
end

local PASSENGER, LOGS, GRAIN = 0, 4, 3
local ROAD, WATER, RAIL = "ROAD", "WATER", "RAIL"
local SHIP, SMALL_SHIP, BUS, TRUCK = "SHIP", "SMALL_SHIP", "BUS", "TRUCK"

local function names()
	return setmetatable({}, { __index = function(_, k) return k end })
end

local function idvec(t) -- {cargo -> v} -> 1-based vector up to the highest cargo
	local out, max = {}, -1
	for c in pairs(t) do if c > max then max = c end end
	for i = 0, max do out[i + 1] = t[i] or false end
	return out
end

local function caps(t) -- {cargo -> cap} -> capacities vector (0 elsewhere)
	local out, max = {}, -1
	for c in pairs(t) do if c > max then max = c end end
	for i = 0, max do out[i + 1] = t[i] or 0 end
	return out
end

local W -- the world of the current test

local function tvComp(id, o)
	local parts = {}
	for i, m in ipairs(o.models) do
		parts[i] = { part = { modelId = m, compartment2loadConfig = { -1, -1 } }, purchaseTime = o.purchaseTime or 0,
			maintenanceState = 0.5 }
	end
	return {
		carrier = o.carrier or WATER,
		transportVehicleConfig = { vehicles = parts },
		config = { capacities = caps(o.capacities or {}), transportModes = o.modes or { [SHIP] = true } },
		sellOnArrival = o.sell or false,
		depot = o.depot or -1,
		line = o.line or -1,
	}
end

local function cargoSet(...) return { cargos = { ... } } end

local function modelMd(o)
	return {
		transportVehicle = {
			carrier = o.carrier or WATER,
			transportModes = o.modes or { SHIP },
			filterTags = o.tags or { "default" },
			compartments = o.compartments,
			loadSpeed = o.loadSpeed,
		},
		waterVehicle = (o.carrier or WATER) == WATER and { topSpeed = o.speed or 10 } or nil,
		landVehicle = (o.carrier == ROAD or o.carrier == RAIL) and { topSpeed = o.speed or 20 } or nil,
		description = { name = o.name },
		availability = { yearFrom = o.from or 0, yearTo = o.to or 0 },
		cost = { price = o.price or 1000 },
		maintenance = { runningCosts = o.running or 500, lifespan = o.life },
	}
end

local function oneCompartment(cargo, cap)
	return { { loadConfigs = { { cargoEntry = { cargoTypeSet = cargoSet(cargo), capacity = cap } } } } }
end

local function newWorld()
	return {
		year = 1900,
		gameTime = 5000,
		balance = 1000000,
		comps = {}, -- [entity][componentType] = table
		catchables = {},
		construction = {}, -- station -> construction entity
		rates = {},
		lineVehicles = {},
		linesForGroup = {},
		linesForGroupFails = false,
		map = {},
		max = {}, produced = {}, outputs = {},
		models = {}, -- id -> { path, md }
		bestLineDepot = {},
		bestDepotForLine = {},
		partPrice = 1000,
		value = {}, running = {},
		replaceFails = false,
		missionError = nil,
		buyFails = false,
		setLineFails = false,
		sent = {},
		events = {},
		nextEntity = 9000,
	}
end

local function comp(e, ct, t)
	W.comps[e] = W.comps[e] or {}
	W.comps[e][ct] = t
end

local function installApi()
	local CT = names()
	local api = {
		type = {
			ComponentType = CT,
			enum = { Carrier = { ROAD = ROAD, WATER = WATER, RAIL = RAIL, AIR = "AIR", TRAM = "TRAM" } },
			TransportVehicleConfig = { new = function(src)
				if src == nil then return { vehicles = {} } end
				local parts = {}
				for i, p in ipairs(src.vehicles) do
					local pc = {}
					for k, v in pairs(p) do pc[k] = v end
					parts[i] = pc
				end
				return { vehicles = parts }
			end },
		},
		engine = {
			entityExists = function(e) return type(e) == "number" and W.comps[e] ~= nil end,
			getComponent = function(e, ct) return W.comps[e] and W.comps[e][ct] end,
			util = {
				getWorld = function() return 1 end,
				getPlayer = function() return 2 end,
				getCalendarDate = function(t) return { year = W.year } end,
				line = {
					calcLineStationThroughput = function(l)
						if W.rates[l] == "error" then error("boom") end
						return W.rates[l] or 0
					end,
					getMaxFrequency = function(l) return W.maxFrequency end,
				},
				stock = {
					getInputsOutputsFromRules = function(s) return { {}, W.outputs[s] or {} } end,
					getCargoMaxProductionPerYear = function(s, c) return W.max[s .. ":" .. c] or 0 end,
					getCargoProducedPerYear = function(s, c) return W.produced[s .. ":" .. c] or 0 end,
				},
				vehicle = {
					findBestLineAndDepotForVehicle = function(v) return W.bestLineDepot[v] or { -1, -1 } end,
					getPartPrice = function() return W.partPrice end,
					getDepreciatedValue = function(v) return W.value[v] or 0 end,
					getRunningCost = function(v)
						if W.running[v] == "error" then error("no running cost") end
						return W.running[v]
					end,
				},
			},
			system = {
				transportVehicleSystem = {
					getLineVehicles = function(l) return W.lineVehicles[l] or {} end,
					getLineCargoInfo = function(l, c)
						W.cargoInfoAsked = { l, c }
						if W.cargoInfo == "error" then error("no info") end
						return W.cargoInfo
					end,
				},
				catchmentAreaSystem = { getStationCatchables = function(s) return W.catchables[s] or {} end },
				streetConnectorSystem = { getConstructionEntityForStation = function(s) return W.construction[s] or -1 end },
				lineSystem = {
					getLinesForStationGroup = function(g)
						if W.linesForGroupFails then error("no such function") end
						return W.linesForGroup[g] or {}
					end,
					getStationGroup2LineStopsMap = function() return W.map end,
				},
			},
		},
		res = {
			cargoTypeRep = {
				getPassengerCargoTypeId = function() return PASSENGER end,
				forEachCargoType = function(set, fn) for _, c in ipairs(set.cargos) do fn(c) end end,
			},
			modelRep = {
				forEachModelWithMetadata = function(kind, fn)
					local ids = {}
					for id in pairs(W.models) do ids[#ids + 1] = id end
					table.sort(ids)
					for _, id in ipairs(ids) do fn(W.models[id].path) end
				end,
				find = function(path)
					for id, m in pairs(W.models) do if m.path == path then return id end end
					return -1
				end,
				get = function(id) return W.models[id] and { metadata = W.models[id].md } end,
				getName = function(id) return W.models[id] and W.models[id].path end,
			},
		},
		cmd = {
			makeVehicleBuyCmd = function(player, depot, cfg) return { kind = "buy", depot = depot, config = cfg } end,
			makeVehicleSetLineCmd = function(v, l, s) return { kind = "setLine", vehicle = v, line = l, stop = s } end,
			makeVehicleSellCmd = function(list) return { kind = "sell", vehicles = list } end,
			makeVehicleReplaceCmd = function(v, cfg) return { kind = "replace", vehicle = v, config = cfg } end,
			sendCommand = function(cmd, cb)
				W.sent[#W.sent + 1] = cmd
				if cmd.kind == "buy" then
					if W.buyFails then return cb(cmd, false) end
					W.nextEntity = W.nextEntity + 1
					comp(W.nextEntity, "TRANSPORT_VEHICLE", tvComp(W.nextEntity, { models = { 1 } }))
					cmd.resultVehicleEntity = W.nextEntity
					return cb(cmd, true)
				elseif cmd.kind == "setLine" then
					return cb(cmd, not W.setLineFails)
				elseif cmd.kind == "replace" then
					return cb(cmd, not W.replaceFails)
				else
					return cb(cmd, true)
				end
			end,
		},
		util = {
			getDefaultYearDuration = function() return 1460000 end,
			getYearDuration = function(mpd) return mpd * 365 end,
		},
		gui = {
			fireGuiScriptEvent = function(id, name, param)
				W.events[#W.events + 1] = { id = id, name = name, param = param }
				if name == "mission.buyVehicle" then return W.missionError end
				return nil
			end,
		},
	}
	set_global("api", api)
	comp(1, "GAME_TIME", { gameTime = W.gameTime })
	comp(1, "GAME_SPEED", { millisPerDay = W.millisPerDay or 0 })
	comp(2, "ACCOUNT", { balance = W.balance })
end

-- Scene: logging camp line 50 (ships, model 1, 20 logs each), stops at groups 60 (camp) and 61 (sawmill).
-- Group 60: station 70 catches industry 80 (stockList 81) and stockList 81 directly (dedupe).
-- Group 61: station 71 is a built-in industry station: no catchables, construction 90 with industry 82 (stock 83).
-- Line 51 (passengers) and line 52 (logs) also stop at group 60; line 53 only at the unrelated group 62.
local function scene()
	W = newWorld()
	installApi()
	comp(50, "LINE", { stops = {
		{ stationGroup = 60, station = 0, terminal = 0, stopConfig = { load = idvec({ [LOGS] = true }) } },
		{ stationGroup = 61, station = 0, terminal = 0, stopConfig = { load = idvec({}) } },
		{ stationGroup = 60, station = 0, terminal = 1, stopConfig = { load = idvec({ [LOGS] = true }) } },
	} })
	comp(60, "STATION_GROUP", { stations = { 70, -1 } })
	comp(61, "STATION_GROUP", { stations = { 71 } })
	W.catchables[70] = { 80, 81, 999 }
	comp(80, "INDUSTRY", { stockList = 81 })
	comp(81, "STOCK_LIST", {})
	comp(999, "TOWN_BUILDING", {})
	W.outputs[81] = { LOGS }
	W.max["81:" .. LOGS] = 101
	W.produced["81:" .. LOGS] = 98
	W.construction[71] = 90
	comp(90, "CONSTRUCTION", { industries = { 82 } })
	comp(82, "INDUSTRY", { stockList = 83 })
	comp(83, "STOCK_LIST", {})
	W.outputs[83] = { GRAIN }
	W.max["83:" .. GRAIN] = 400
	comp(51, "LINE", { stops = { { stationGroup = 60, stopConfig = { load = idvec({ [PASSENGER] = true }) } } } })
	comp(52, "LINE", { stops = { { stationGroup = 60, stopConfig = { load = idvec({ [LOGS] = true }) } } } })
	comp(53, "LINE", { stops = { { stationGroup = 62, stopConfig = { load = idvec({ [LOGS] = true }) } } } })
	W.linesForGroup[60] = { 50, 51, 52 }
	W.linesForGroup[61] = { 50 }
	W.map = { [60] = { { 50, 0 }, { 51, 0 }, { 52, 0 }, { 50, 2 } }, [61] = { { 50, 1 } } }
	W.rates = { [50] = 66, [51] = 103, [52] = 20, [53] = 500 }
	-- vehicles: 100, 101 ships on line 50; 102 is mission protected; 103 already selling
	W.lineVehicles[50] = { 100, 101 }
	comp(100, "TRANSPORT_VEHICLE", tvComp(100, { models = { 1 }, capacities = { [LOGS] = 20, [GRAIN] = 20 }, purchaseTime = 10, line = 50 }))
	comp(101, "TRANSPORT_VEHICLE", tvComp(101, { models = { 1 }, capacities = { [LOGS] = 20 }, purchaseTime = 20, depot = 300, line = 50 }))
	-- models: 1 the line's ship (yearFrom 1850); 2 a bigger ship; 3 too new; 4 retired; 5 grain only;
	-- 6 a road truck; 7 small ship with no tags; 8 small ship (SMALL_SHIP mode only)
	W.models = {
		[1] = { path = "ship/log1.mdl", md = modelMd({ name = "Log ship", compartments = oneCompartment(LOGS, 20), from = 1850, speed = 10 }) },
		[2] = { path = "ship/log2.mdl", md = modelMd({ name = "Big log ship", speed = 8, compartments = {
			{ loadConfigs = {
				{ cargoEntry = { cargoTypeSet = cargoSet(LOGS, GRAIN), capacity = 30 } },
				{ cargoEntry = { cargoTypeSet = cargoSet(LOGS), capacity = 25 } },
			} },
			{ loadConfigs = { { cargoEntry = { cargoTypeSet = cargoSet(LOGS), capacity = 10 } } } },
		} }) },
		[3] = { path = "ship/future.mdl", md = modelMd({ name = "Future", compartments = oneCompartment(LOGS, 50), from = 1950 }) },
		[4] = { path = "ship/old.mdl", md = modelMd({ name = "Old", compartments = oneCompartment(LOGS, 50), from = 1800, to = 1900 }) },
		[5] = { path = "ship/grain.mdl", md = modelMd({ name = "Grain", compartments = oneCompartment(GRAIN, 50) }) },
		[6] = { path = "truck/log.mdl", md = modelMd({ name = "Truck", carrier = ROAD, modes = { TRUCK }, compartments = oneCompartment(LOGS, 10) }) },
		[7] = { path = "ship/notag.mdl", md = modelMd({ name = "No tag", tags = {}, compartments = oneCompartment(LOGS, 15) }) },
		[8] = { path = "ship/small.mdl", md = modelMd({ name = "Small", modes = { SMALL_SHIP }, compartments = oneCompartment(LOGS, 12) }) },
	}
end

local fakeVehicleUtil = {
	makePart = function(modelId, forward, color)
		return { part = { modelId = modelId, reversed = not forward, color = color, compartment2loadConfig = { 0 } },
			purchaseTime = 0 }
	end,
}

before_each(function()
	reset_modules()
	scene()
	stub_module("::/gui/line_vehicle_mgmt/vehicle_util.tl", fakeVehicleUtil)
	load()
end)

-- pure rules -------------------------------------------------------------------------------

test("isAvailable mirrors the store's year rule", function()
	eq(engine.isAvailable(0, 0, 1900), true)
	eq(engine.isAvailable(-1, -1, 1900), true)
	eq(engine.isAvailable(1901, 0, 1900), false)
	eq(engine.isAvailable(1900, 0, 1900), true)
	eq(engine.isAvailable(1800, 1900, 1900), false, "yearTo is exclusive")
	eq(engine.isAvailable(1800, 1901, 1900), true)
	eq(engine.isAvailable(1800, 6000, 5500), false, "yearTo folds to min(5000, yearTo)")
end)

test("matchesFilterTags and matchesTransportModes", function()
	eq(engine.matchesFilterTags({ "default" }, { "default" }), true)
	eq(engine.matchesFilterTags({}, { "default" }), false)
	eq(engine.matchesFilterTags({ "default" }, { "default", "x" }), false, "must carry all line tags")
	eq(engine.matchesFilterTags({ "default" }, {}), true, "legacy: no line tags, model has some")
	eq(engine.matchesFilterTags({}, {}), false)
	eq(engine.matchesTransportModes({ SHIP }, { [SHIP] = true }), true)
	eq(engine.matchesTransportModes({ SMALL_SHIP }, { [SHIP] = true }), false)
	eq(engine.matchesTransportModes({ BUS }, nil), true)
end)

test("cargoCapacity: per compartment the best load config, summed", function()
	eq(engine.cargoCapacity(W.models[2].md.transportVehicle, LOGS), 40)
	eq(engine.cargoCapacity(W.models[2].md.transportVehicle, GRAIN), 30)
	eq(engine.cargoCapacity(W.models[2].md.transportVehicle, PASSENGER), 0)
	eq(engine.cargoCapacity(nil, LOGS), 0)
end)

-- line reads -------------------------------------------------------------------------------

test("lineRate and lineVehicles", function()
	eq(engine.lineRate(50), 66)
	local r, err = engine.lineRate(12345)
	eq(r, nil); eq(err, "not_a_line")
	W.rates[50] = "error"
	r, err = engine.lineRate(50)
	eq(r, nil); ok(err:find("^read: ") ~= nil, err)

	comp(101, "TRANSPORT_VEHICLE", tvComp(101, { models = { 1 }, capacities = { [LOGS] = 20 }, purchaseTime = 20, sell = true }))
	W.value[100], W.running[100] = 41000, 2500
	W.running[101] = "error"
	local vs = engine.lineVehicles(50, { [100] = true })
	eq(#vs, 2)
	eq(vs[1], { id = 100, model = 1, capacities = { [LOGS] = 20, [GRAIN] = 20 }, purchaseTime = 10, protected = true, selling = false,
		value = 41000, running = 2500 })
	eq(vs[2].running, nil, "a failed read is unknown")
	eq(vs[2].selling, true)
	eq(vs[2].protected, false)
	local none, why = engine.lineVehicles(77)
	eq(none, nil); eq(why, "not_a_line")
end)

test("supplyInput: catchment walk, built-in station fallback, dedupe, other lines", function()
	local s = assert(engine.supplyInput(50))
	eq(s.line, 50)
	eq(s.passengerCargo, PASSENGER)
	eq(#s.stops, 3)
	eq(s.stops[1].stationGroup, 60)
	eq(s.stops[1].loads, { [LOGS] = true })
	eq(s.stops[1].producers, { { stockList = 81, cargo = LOGS, maxPerYear = 101, producedPerYear = 98 } },
		"industry 80 and stockList 81 are one producer")
	eq(s.stops[2].loads, {})
	eq(s.stops[2].producers, {}, "no catchment walk where nothing is loaded")
	eq(s.stops[3].producers, s.stops[1].producers)
	local lines = {}
	for _, o in ipairs(s.otherLines) do lines[#lines + 1] = o.line end
	eq(lines, { 51, 52 })
	eq(s.otherLines[2], { line = 52, rate = 20, stops = { { stationGroup = 60, loads = { [LOGS] = true } } } })

	-- through the pure model: 101 - 20 (line 52 loads logs at group 60; 51 is passengers)
	local targets = model.targetsFromSupply(s)
	eq(#targets, 1)
	eq(targets[1].target, 81)
	eq(targets[1].otherLines, { 52 })
end)

test("supplyInput: built-in industry station and the lines-map fallback", function()
	-- load grain at the sawmill stop (group 61, station 71 without catchables)
	W.comps[50].LINE.stops[2].stopConfig.load = idvec({ [GRAIN] = true })
	W.linesForGroupFails = true
	local s = assert(engine.supplyInput(50))
	eq(s.stops[2].producers, { { stockList = 83, cargo = GRAIN, maxPerYear = 400, producedPerYear = 0 } })
	local lines = {}
	for _, o in ipairs(s.otherLines) do lines[#lines + 1] = o.line end
	eq(lines, { 51, 52 }, "map fallback, line 50 itself skipped, each line once")
end)

test("readLine bundles rate, vehicles, supply and year", function()
	local d = assert(engine.readLine(50))
	eq(d.rate, 66)
	eq(#d.vehicles, 2)
	eq(d.supply.line, 50)
	eq(d.year, 1900)
	local sug = model.suggest(d.rate, d.vehicles, LOGS, 81)
	eq(sug.status, "ok")
	eq(sug.perVehicle, 33)
	local x, err = engine.readLine(4242)
	eq(x, nil); eq(err, "not_a_line")
end)

-- catalogue --------------------------------------------------------------------------------

local function ids(list)
	local out = {}
	for _, m in ipairs(list) do out[#out + 1] = m.model end
	return out
end

test("modelCatalogue: carrier, modes, tags, year, cargo", function()
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", {
		getLineAndVehicleCompatibleTransportModesAndCarrier = function()
			return { carrier = WATER, transportModes = { [SHIP] = true, [SMALL_SHIP] = true } }
		end,
	})
	local cat = assert(engine.modelCatalogue({ 100, 101 }, LOGS))
	-- 1 current, 2 bigger, 8 small ship (allowed by the Replace window's modes); not 3 (1950), 4 (retired 1900),
	-- 5 (no logs), 6 (road), 7 (no filter tag)
	eq(ids(cat), { 1, 2, 8 })
	eq(cat[2], { model = 2, path = "ship/log2.mdl", name = "Big log ship", capacity = 40, speed = 8, price = 1000, running = 500, available = true })

	-- without line_util the vehicles' own transport modes apply (SHIP only)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", {})
	reset_modules()
	load()
	eq(ids(assert(engine.modelCatalogue({ 100 }, LOGS))), { 1, 2 })
	-- a later year and a mission filter
	eq(ids(assert(engine.modelCatalogue({ 100 }, LOGS, { year = 1960 }))), { 1, 2, 3 })
	eq(ids(assert(engine.modelCatalogue({ 100 }, LOGS, { vehicleFilter = { enabledVehicles = {}, disabledVehicles = { "ship/log2.mdl" } } }))), { 1 })
	eq(ids(assert(engine.modelCatalogue({ 100 }, LOGS, { vehicleFilter = { enabledVehicles = { "ship/log2.mdl" }, disabledVehicles = {} } }))), { 2 })

	-- rankModels with the current model from the catalogue
	local cur = engine.currentFor(assert(engine.modelInfo(1, LOGS)), 33)
	eq(cur, { model = 1, capacity = 20, speed = 10, perVehicle = 33 })
	local ranked = model.rankModels(engine.candidatesOf(cat), cur, 101)
	-- 8: 33 * 12/20 = 19.8 -> 5 ships = 99 (diff 2); 2: 33 * 40/20 * 8/10 = 52.8 -> 2 ships = 105.6
	eq({ ranked[1].model, ranked[1].count }, { 8, 5 })
	eq({ ranked[2].model, ranked[2].count }, { 2, 2 })
	eq(#ranked, 2, "the current model is not an alternative")
end)

test("modelCatalogue refuses trains, mixed carriers and empty lists", function()
	local c, why = engine.modelCatalogue({}, LOGS)
	eq(c, nil); eq(why, "no_vehicles")
	comp(110, "TRANSPORT_VEHICLE", tvComp(110, { models = { 1, 1 }, carrier = RAIL }))
	c, why = engine.modelCatalogue({ 110 }, LOGS)
	eq(c, nil); eq(why, "multi_part")
	comp(111, "TRANSPORT_VEHICLE", tvComp(111, { models = { 6 }, carrier = ROAD }))
	c, why = engine.modelCatalogue({ 100, 111 }, LOGS)
	eq(c, nil); eq(why, "mixed_carriers")
	c, why = engine.modelCatalogue({ 100, 4040 }, LOGS)
	eq(c, nil); eq(why, "vehicle_gone")
end)

test("calendarYearMs / yearMs: the year at the current calendar speed, default when paused", function()
	eq(engine.calendarYearMs(8000, function(m) return m * 365 end, 1460000), 2920000)
	eq(engine.calendarYearMs(0, function(m) return m * 365 end, 1460000), 1460000, "paused")
	eq(engine.calendarYearMs(8000, function() error("x") end, 1460000), 1460000)
	eq(engine.calendarYearMs(8000, nil, nil), 1460000, "built-in default")
	eq(engine.yearMs(), 1460000, "paused game: default year")
	comp(1, "GAME_SPEED", { millisPerDay = 8000 })
	eq(engine.yearMs(), 2920000)
end)

test("capital per year: vehicles and models, price over the lifespan in calendar years", function()
	W.models[1].md.maintenance.lifespan = 36525
	W.models[1].md.cost.price = 548640
	W.models[1].md.transportVehicle.loadSpeed = 20
	local vs = engine.lineVehicles(50)
	near(vs[1].capital, 548640 * 1460000 / 36525000, 1e-6)
	local info = engine.modelInfo(1, LOGS)
	eq(info.loadSpeed, 20); eq(info.lifespanMs, 36525000)
	near(info.capital, vs[1].capital, 1e-9)
	-- a calendar twice as slow: half the calendar years of life, twice the yearly share
	comp(1, "GAME_SPEED", { millisPerDay = 8000 })
	near(engine.lineVehicles(50)[1].capital, 2 * vs[1].capital, 1e-6)
	-- no lifespan: unknown
	W.models[1].md.maintenance.lifespan = nil
	eq(engine.lineVehicles(50)[1].capital, nil)
	eq(engine.modelInfo(1, LOGS).capital, nil)
	eq(#engine.modelCatalogue({ 100, 101 }, LOGS) > 0, true, "the catalogue still lists models without one")
end)

test("lineVehicles reads each model's price and lifespan once per call; mixed fleets keep their own capital", function()
	W.models[1].md.maintenance.lifespan = 36525
	W.models[2].md.maintenance.lifespan = 36525
	W.models[2].md.cost.price = 2000
	W.lineVehicles[50] = { 100, 101, 102 }
	comp(102, "TRANSPORT_VEHICLE", tvComp(102, { models = { 2 }, capacities = { [LOGS] = 40 }, line = 50 }))
	local get = api.res.modelRep.get
	local reads = {}
	api.res.modelRep.get = function(id) reads[id] = (reads[id] or 0) + 1; return get(id) end
	local vs = engine.lineVehicles(50)
	eq(reads, { [1] = 1, [2] = 1 }, "one read per model")
	near(vs[1].capital, 1000 * 1460000 / 36525000, 1e-9)
	near(vs[2].capital, vs[1].capital, 1e-12)
	near(vs[3].capital, 2 * vs[1].capital, 1e-9)
	-- every call reads again (a price change shows at the next refresh)
	W.models[1].md.cost.price = 3000
	near(engine.lineVehicles(50)[1].capital, 3 * vs[1].capital, 1e-9)
	eq(reads, { [1] = 2, [2] = 2 })
	-- the catalogue's filter tags: one read per model of the fleet, the tags of both models count
	W.models[2].md.transportVehicle.filterTags = { "default", "big" }
	reads = {}
	local cat = assert(engine.modelCatalogue({ 100, 101, 102 }, LOGS))
	eq(ids(cat), { 2 }, "only model 2 has both tags")
	eq(reads[1], 2, "fleet tags once + the catalogue walk once")
	api.res.modelRep.get = get
end)

test("lineTiming: section and drive sums, the share at stops, max frequency", function()
	W.cargoInfo = { sectionTimes = { 60, 40 }, driveSectionTimes = { 45, 25 } }
	W.maxFrequency = 0.01
	local t = assert(engine.lineTiming(50, LOGS))
	eq(W.cargoInfoAsked, { 50, LOGS })
	eq(t.cargo, LOGS); eq(t.section, 100); eq(t.drive, 70); eq(t.sections, 2); near(t.loadShare, 0.3)
	eq(t.maxFrequency, 0.01)
	engine.lineTiming(50, nil)
	eq(W.cargoInfoAsked, { 50, PASSENGER }, "no cargo: passengers")
	W.cargoInfo = nil
	t = assert(engine.lineTiming(50, LOGS))
	eq(t.loadShare, nil); eq(t.section, nil)
	W.cargoInfo = "error"
	local x, err = engine.lineTiming(50, LOGS)
	eq(x, nil); ok(err:find("^read: ") ~= nil)
	local y, why = engine.lineTiming(12345, LOGS)
	eq(y, nil); eq(why, "not_a_line")
end)

test("modelInfo flags an unavailable current model", function()
	local i = assert(engine.modelInfo(4, LOGS))
	eq(i.available, false)
	eq(i.price, 1000); eq(i.running, 500)
	eq(i.capacity, 50)
	local x, why = engine.modelInfo(404, LOGS)
	eq(x, nil); eq(why, "not_a_vehicle_model")
end)

-- commands ---------------------------------------------------------------------------------

local function kinds()
	local out = {}
	for _, c in ipairs(W.sent) do out[#out + 1] = c.kind end
	return out
end

test("cloneOntoLine: buy + set line per clone, mission hooks, fresh config", function()
	W.bestLineDepot[101] = { 50, 300 }
	local got
	local r = commands.cloneOntoLine(101, 50, 2, function(res) got = res end)
	eq(got, r)
	eq(r.status, "ok")
	eq(r.done, { 9001, 9002 })
	eq(r.depot, 300); eq(r.depotFrom, "findBest")
	eq(kinds(), { "buy", "setLine", "buy", "setLine" })
	eq(W.sent[2].line, 50); eq(W.sent[2].stop, 0)
	local cfg = W.sent[1].config
	eq(cfg.vehicles[1].purchaseTime, 5000)
	eq(cfg.vehicles[1].maintenanceState, 1)
	eq(cfg.vehicles[1].autoLoadConfig, { true, true })
	ok(W.sent[1].config ~= W.sent[3].config, "a config per clone")
	eq(W.comps[101].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1].purchaseTime, 20, "template untouched")
	eq(W.events[1].name, "mission.buyVehicle")
	eq(W.events[1].param, { modelId2quantity = { [1] = 1 }, actuallyBuy = true })
	eq(W.events[2], { id = "vehicleStore", name = "mission.cloneVehicle", param = { entity = 101 } })
end)

test("resolveDepot fallbacks", function()
	-- findBest picks another line: line_util's depot for our line wins
	W.bestLineDepot[100] = { 77, 301 }
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", { getBestDepotForLine = function(l) return l == 50 and 302 or -1 end })
	eq({ commands.resolveDepot(100, 50) }, { 302, "line_util.getBestDepotForLine" })
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", {})
	reset_modules()
	load()
	eq({ commands.resolveDepot(100, 50) }, { 301, "findBest_other_line" })
	W.bestLineDepot[100] = nil
	eq({ commands.resolveDepot(100, 50) }, { 300, "line_vehicle_depot" })
	W.comps[101].TRANSPORT_VEHICLE.depot = -1
	eq({ commands.resolveDepot(100, 50) }, {})
	local r = commands.cloneOntoLine(100, 50, 3)
	eq(r.status, "failed"); eq(r.reasons, { no_depot = 3 })
	eq(#W.sent, 0)
end)

test("cloneOntoLine: money cap, failed buy, mission refusal, set line failure", function()
	W.bestLineDepot[101] = { 50, 300 }
	W.comps[2].ACCOUNT.balance = 2500 -- 2 clones at 1000
	local r = commands.cloneOntoLine(101, 50, 4)
	eq(r.status, "partial"); eq(#r.done, 2); eq(r.reasons, { not_enough_money = 2 })

	W.sent = {}
	W.comps[2].ACCOUNT.balance = 500
	r = commands.cloneOntoLine(101, 50, 1)
	eq(r.status, "failed"); eq(r.reasons, { not_enough_money = 1 }); eq(#W.sent, 0)

	W.comps[2].ACCOUNT.balance = 1e9
	W.buyFails = true
	r = commands.cloneOntoLine(101, 50, 2)
	eq(r.status, "failed"); eq(r.reasons, { not_enough_money = 2 })

	W.buyFails = false
	W.setLineFails = true
	r = commands.cloneOntoLine(101, 50, 1)
	eq(r.status, "failed"); eq(r.reasons, { set_line_failed = 1 }); eq(#r.unassigned, 1)

	W.setLineFails = false
	W.missionError = "Not in this mission"
	W.sent = {}
	r = commands.cloneOntoLine(101, 50, 3)
	eq(r.status, "failed"); eq(r.reasons, { mission = 3 }); eq(r.message, "Not in this mission"); eq(#W.sent, 0)

	eq(commands.cloneOntoLine(4040, 50, 1).reasons, { invalid_template = 1 })
	eq(commands.cloneOntoLine(101, 4040, 1).reasons, { invalid_line = 1 })
	eq(commands.cloneOntoLine(101, 50, 0).status, "invalid")
	W.missionError = nil
	W.comps[2].ACCOUNT.balance = 1e12
	eq(#commands.cloneOntoLine(101, 50, 1000).done, commands.MAX_CLONES)
end)

test("sellVehicles skips gone, protected and selling vehicles", function()
	comp(103, "TRANSPORT_VEHICLE", tvComp(103, { models = { 1 }, sell = true }))
	local got
	local r = commands.sellVehicles({ 100, 101, 103, 4040 }, function(res) got = res end, { [101] = true })
	eq(got, r)
	eq(r.done, { 100 })
	eq(r.reasons, { protected = 1, already_selling = 1, gone = 1 })
	eq(r.status, "partial")
	eq(W.sent[1], { kind = "sell", vehicles = { 100 } }, "the vanilla Sell, never sell on arrival")
	eq(commands.sellVehicles({}).status, "invalid")
end)

test("replaceViaWindow fires replaceVehicles like radar_fleet, falls back to the manager", function()
	local fired = {}
	stub_module("::/gui/main/react.lua", { fireEvent = function(_, name, p) fired[#fired + 1] = { name = name, p = p } end })
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", {
		getLineAndVehicleCompatibleTransportModesAndCarrier = function(list)
			return { carrier = #list == 1 and WATER or nil, transportModes = { [SHIP] = true } }
		end,
	})
	stub_module("::/gui/line_vehicle_mgmt/vehicle_store_util.tl", { getVehicleFilterTags = function() return { "default" } end })
	local closed = 0
	eq({ commands.replaceViaWindow({ 100, 4040 }, function() closed = closed + 1 end) }, { true })
	eq(fired[1].name, "replaceVehicles")
	eq(fired[1].p.vehicleEntities, { 100 })
	eq(fired[1].p.carrier, WATER)
	eq(fired[1].p.filterTags, { "default" })
	fired[1].p.onClose()
	eq(closed, 1)
	eq({ commands.replaceViaWindow({ 100, 101 }) }, { false, "fallback_manager" })
	eq(fired[2].name, "openVehicleManager")
	eq(fired[2].p, { openWithVehicleEntities = { 100, 101 } })
	eq({ commands.replaceViaWindow({}) }, { false, "no_vehicles" })
end)

test("clonePrice: the store price (metadata cost.price) of the template's parts, getPartPrice as fallback", function()
	W.models[1].md.cost.price = 70000
	W.partPrice = 12345 -- e.g. a depreciated part value: not what a new vehicle costs
	eq(commands.clonePrice(101), 70000)
	eq(commands.modelPrice(1), 70000)
	W.models[1].md.cost = nil
	eq(commands.clonePrice(101), 12345)
	eq(commands.modelPrice(1), nil)
	W.partPrice = 0
	eq(commands.clonePrice(101), nil)
	eq(commands.clonePrice(424242), nil)
end)

local function switchPlan(o)
	return { model = o.model or 2, switch = true, count = o.count, delta = o.delta or 0, rate = 1, buy = o.buy or 0,
		replace = o.replace or {}, remove = o.remove or {} }
end

test("switchModel: replace in place, buy extra onto the line, sell the surplus", function()
	W.bestLineDepot[101] = { 50, 300 }
	W.value[100], W.value[101] = 400, 600
	local got
	local r = commands.switchModel(switchPlan({ count = 3, delta = 1, buy = 1, replace = { 100, 101 } }), 50, 101,
		function(res) got = res end)
	eq(got, r)
	eq(r.status, "ok"); eq(r.requested, 3)
	eq(r.replaced, { 100, 101 }); eq(r.bought, { 9001 }); eq(r.sold, {})
	eq(kinds(), { "replace", "replace", "buy", "setLine" })
	eq(W.sent[1].vehicle, 100)
	local cfg = W.sent[1].config
	eq(cfg.vehicles[1].part.modelId, 2); eq(cfg.vehicles[1].purchaseTime, 5000); eq(cfg.vehicles[1].autoLoadConfig, { true })
	eq(cfg.vehicleGroups, { 1 }); eq(cfg.muFileNames, {})
	ok(W.sent[1].config ~= W.sent[2].config, "a config per vehicle")
	eq(W.sent[3].depot, 300); eq(W.sent[4].line, 50)
	eq(W.events[1].name, "mission.buyVehicle")
	eq(W.events[1].param, { modelId2quantity = { [2] = 3 }, actuallyBuy = true }, "one mission check for the whole order")

	W.sent, W.events = {}, {}
	r = commands.switchModel(switchPlan({ count = 1, delta = -1, replace = { 100 }, remove = { 101 } }), 50, 101)
	eq(r.status, "ok"); eq(r.replaced, { 100 }); eq(r.sold, { 101 })
	eq(kinds(), { "replace", "sell" })
	eq(W.sent[2].vehicles, { 101 })
end)

test("switchModel: all-or-nothing money check with the replace refund, mission, failures", function()
	W.bestLineDepot[101] = { 50, 300 }
	W.models[2].md.cost.price = 1000
	W.value[100], W.value[101] = 400, 600
	-- net = 3 x 1000 - (400 + 600) = 2000
	W.comps[2].ACCOUNT.balance = 1999
	local plan = switchPlan({ count = 3, delta = 1, buy = 1, replace = { 100, 101 } })
	local r = commands.switchModel(plan, 50, 101)
	eq(r.status, "failed"); eq(r.reasons, { not_enough_money = 3 }); eq(#W.sent, 0)
	W.comps[2].ACCOUNT.balance = 2000
	eq(commands.switchModel(plan, 50, 101).status, "ok")

	W.sent = {}
	W.missionError = "Not now"
	r = commands.switchModel(plan, 50, 101)
	eq(r.status, "failed"); eq(r.reasons, { mission = 3 }); eq(r.message, "Not now"); eq(#W.sent, 0)
	W.missionError = nil

	W.replaceFails = true
	r = commands.switchModel(plan, 50, 101)
	eq(r.status, "partial"); eq(r.replaced, {}); eq(r.bought, { W.nextEntity }); eq(r.reasons, { not_enough_money = 2 })
	W.replaceFails = false

	eq(commands.switchModel(plan, 50, 101, nil, { [100] = true }).reasons, { protected = 3 })
	eq(commands.switchModel(plan, 4040, 101).reasons, { invalid_line = 1 })
	eq(commands.switchModel(switchPlan({ count = 1, replace = { 4040 } }), 50, 101).reasons, { invalid_template = 1 })
	eq(commands.switchModel(switchPlan({ count = 0 }), 50, 101).status, "invalid")
	eq(commands.switchModel({ model = 2, switch = false }, 50, 101).reasons, { invalid_model = 1 })
	W.bestLineDepot[101] = nil
	W.comps[100].TRANSPORT_VEHICLE.depot = -1
	W.comps[101].TRANSPORT_VEHICLE.depot = -1
	eq(commands.switchModel(plan, 50, 101).reasons, { no_depot = 3 })
end)

-- stale ids are a fatal engine assert in the game (pcall can't catch it): every native call and command re-checks
test("stale ids: no findBest on a gone template, no set line for a vanished clone, no replace of a sold vehicle", function()
	local asked = {}
	local findBest = api.engine.util.vehicle.findBestLineAndDepotForVehicle
	api.engine.util.vehicle.findBestLineAndDepotForVehicle = function(v) asked[#asked + 1] = v; return findBest(v) end
	W.comps[101].TRANSPORT_VEHICLE.depot = 300
	eq({ commands.resolveDepot(4040, 50) }, { 300, "line_vehicle_depot" })
	eq({ commands.resolveDepot(0, 50) }, { 300, "line_vehicle_depot" })
	eq(#asked, 0, "findBestLineAndDepotForVehicle only for a live vehicle")
	eq(commands.replaceViaWindow({ 0, 60 }), false)

	-- the bought clone is gone (or the line deleted) by its callback: no set line command
	W.bestLineDepot[101] = { 50, 300 }
	local send = api.cmd.sendCommand
	api.cmd.sendCommand = function(cmd, cb)
		if cmd.kind ~= "buy" then return send(cmd, cb) end
		return send(cmd, function(c, ok2)
			W.comps[c.resultVehicleEntity] = nil
			return cb(c, ok2)
		end)
	end
	local r = commands.cloneOntoLine(101, 50, 1)
	eq(kinds(), { "buy" }); eq(r.reasons, { set_line_failed = 1 })
	W.sent = {}
	r = commands.switchModel(switchPlan({ count = 1, delta = 1, buy = 1, replace = {} }), 50, 101)
	eq(kinds(), { "buy" }); eq(r.reasons, { set_line_failed = 1 })

	-- a vehicle sold while the order is sent: its replace is skipped
	api.cmd.sendCommand = function(cmd, cb)
		if cmd.kind == "replace" and cmd.vehicle == 100 then W.comps[101] = nil end
		return send(cmd, cb)
	end
	W.sent = {}
	r = commands.switchModel(switchPlan({ count = 2, delta = 0, replace = { 100, 101 } }), 50, 100)
	eq(kinds(), { "replace" }); eq(r.replaced, { 100 }); eq(r.reasons, { gone = 1 })
	api.cmd.sendCommand = send
end)

-- empty line estimate ---------------------------------------------------------------------------
-- Empty ship line 54 (groups 64 / 65, stations 74 / 75): station 74 has a construction at (0, 0); station 75 is a
-- curbside-like station without one, bounding box centred on (3000, 4000). Round trip 10 km.
local function emptyScene()
	W.player = 2
	comp(54, "LINE", { stops = {
		{ stationGroup = 64, station = 0, terminal = 0, stopConfig = { load = idvec({ [LOGS] = true }) } },
		{ stationGroup = 65, station = 0, terminal = 0, stopConfig = { load = idvec({}) } },
	} })
	comp(64, "STATION_GROUP", { stations = { 74 } })
	comp(65, "STATION_GROUP", { stations = { 75 } })
	comp(74, "STATION", {})
	comp(75, "STATION", {})
	comp(75, "BOUNDING_VOLUME", { bbox = { min = { x = 2990, y = 3990 }, max = { x = 3010, y = 4010 } } })
	W.construction[74] = 94
	comp(94, "CONSTRUCTION", { transf = { getTransl = function() return { x = 0, y = 0, z = 5 } end } })
	comp(300, "VEHICLE_DEPOT", {})
	W.depotForLine = { [54] = 300 }
	W.depotCarrier = { [300] = WATER }
	W.depotModes = { [300] = { [SHIP] = true } }
	W.depotTags = { [300] = { "default" } }
	W.playerLines = { 50, 54 }
	W.lineModes = {}
	-- line 50 (two log ships, model 1, 10 m/s): stops at groups 60 / 61 / 60 (stations 70 / 71): give them positions
	comp(70, "STATION", {}); comp(71, "STATION", {})
	comp(70, "BOUNDING_VOLUME", { bbox = { min = { x = 0, y = 0 }, max = { x = 0, y = 0 } } })
	comp(71, "BOUNDING_VOLUME", { bbox = { min = { x = 0, y = 1000 }, max = { x = 0, y = 1000 } } })
	W.construction[71] = -1
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", {
		getBestDepotForLine = function(l) return W.depotForLine[l] or -1 end,
	})
	stub_module("::/gui/line_vehicle_mgmt/vehicle_store_util.tl", {
		getDepotFilterTags = function(d) return W.depotTags[d] or {} end,
	})
	fakeVehicleUtil.getDepotCarrier = function(d) return W.depotCarrier[d] end
	fakeVehicleUtil.getDepotTransportModes = function(d) return W.depotModes[d] or {} end
	api.engine.system.lineSystem.getLinesForPlayer = function(p)
		W.linesAskedFor = p
		return W.playerLines
	end
	api.engine.util.line.getLineTransportModesUnion = function(l) return W.lineModes[l] or {} end
	api.type.enum.TransportMode = { TRAIN = "TRAIN", ELECTRIC_TRAIN = "ELECTRIC_TRAIN" }
	api.type.ComponentType = names()
end

test("stopPositions: construction position, else the station's bounding box; missing stations refuse", function()
	emptyScene()
	local pts = engine.stopPositions(54)
	eq(pts, { { 0, 0 }, { 3000, 4000 } })
	eq(model.routeDistance(pts), 10000)
	-- a station with neither: no positions
	W.comps[75].BOUNDING_VOLUME = nil
	eq({ engine.stopPositions(54) }, { nil, "no_positions" })
	W.comps[75] = nil
	eq({ engine.stopPositions(54) }, { nil, "no_positions" }, "a gone station is never asked about")
	eq({ engine.stopPositions(4040) }, { nil, "not_a_line" })
	comp(55, "LINE", { stops = { { stationGroup = 64, station = 0 } } })
	eq({ engine.stopPositions(55) }, { nil, "few_stops" })
end)

test("calibration: samples of the carrier's other lines, single-part only, cached for a while; fallback", function()
	emptyScene()
	-- line 50: 3 stops at (0,0), (0,1000), (0,0): 2 km; its ships at 10 m/s; Σ drive 300 s, Σ section 360 s
	W.cargoInfo = { sectionTimes = { 180, 180 }, driveSectionTimes = { 150, 150 } }
	local t = engine.calibration(WATER, 54)
	eq({ t.fallback, t.n, t.carrier, t.detour, t.dwell }, { true, 1, "water", 1.5, 25 }, "one sample: fallback")
	eq(W.linesAskedFor, 2)
	eq(W.cargoInfoAsked, { 50, LOGS }, "the cargo the line's vehicle carries and loads")
	-- three lines like line 50: their medians (detour 300 / (2000 / 10) = 1.5, dwell 60 / 3 = 20)
	for _, l in ipairs({ 56, 57 }) do
		comp(l, "LINE", W.comps[50].LINE)
		W.lineVehicles[l] = { 100 }
	end
	W.playerLines = { 50, 54, 56, 57 }
	eq(engine.calibration(WATER, 54).fallback, true, "cached")
	W.comps[1].GAME_TIME.gameTime = W.gameTime + engine.CALIBRATION_TTL_MS
	t = engine.calibration(WATER, 54)
	eq({ t.fallback, t.n }, { false, 3 })
	near(t.detour, 1.5, 1e-9); near(t.dwell, 20, 1e-9)
	-- another carrier: no road lines in the save
	t = engine.calibration(ROAD, 54)
	eq({ t.fallback, t.n, t.carrier, t.detour }, { true, 0, "road", 1.9 })
	-- multi-part vehicles and failing reads are skipped
	W.comps[1].GAME_TIME.gameTime = W.gameTime + 3 * engine.CALIBRATION_TTL_MS
	W.comps[100].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[2] = W.comps[100].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[1]
	eq(engine.calibration(WATER, 54).n, 0)
	W.comps[100].TRANSPORT_VEHICLE.transportVehicleConfig.vehicles[2] = nil
	W.cargoInfo = "error"
	W.comps[1].GAME_TIME.gameTime = W.gameTime + 5 * engine.CALIBRATION_TTL_MS
	eq(engine.calibration(WATER, 54).n, 0)
end)

test("calibration scans at most MAX_SCAN_LINES lines and stops at MAX_SAMPLES samples", function()
	emptyScene()
	W.cargoInfo = { sectionTimes = { 180, 180 }, driveSectionTimes = { 150, 150 } }
	local lines = {}
	for i = 1, engine.MAX_SCAN_LINES + 50 do lines[i] = 50 end
	W.playerLines = lines
	local asked = 0
	local getLineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles
	api.engine.system.transportVehicleSystem.getLineVehicles = function(l) asked = asked + 1; return getLineVehicles(l) end
	-- every line a sample: the scan ends at MAX_SAMPLES
	eq(engine.calibration(WATER, 54).n, engine.MAX_SAMPLES)
	eq(asked, engine.MAX_SAMPLES)
	-- road lines in a water calibration give no sample: the line cap ends the scan
	engine.clearCalibration()
	asked = 0
	eq(engine.calibration(ROAD, 54).n, 0)
	eq(asked, engine.MAX_SCAN_LINES)
	-- the cache: a second call within the TTL scans nothing
	asked = 0
	engine.calibration(ROAD, 54)
	eq(asked, 0)
end)

test("model catalogue: one walk per carrier / modes / tags / cargo / year / year length / filter", function()
	local walks = 0
	local each = api.res.modelRep.forEachModelWithMetadata
	api.res.modelRep.forEachModelWithMetadata = function(kind, fn) walks = walks + 1; return each(kind, fn) end
	local a = assert(engine.modelCatalogue({ 100, 101 }, LOGS))
	eq(walks, 1)
	eq(engine.modelCatalogue({ 100, 101 }, LOGS), a, "same key: the cached list")
	eq(engine.modelCatalogue({ 100 }, LOGS), a, "the same kind from fewer vehicles")
	eq(walks, 1)
	engine.modelCatalogue({ 100 }, GRAIN)
	eq(walks, 2, "another cargo")
	engine.modelCatalogue({ 100 }, LOGS, { year = 1960 })
	eq(walks, 3, "another year")
	comp(1, "GAME_SPEED", { millisPerDay = 8000 })
	engine.modelCatalogue({ 100 }, LOGS)
	eq(walks, 4, "another calendar speed (capital per year)")
	local vf = { enabledVehicles = {}, disabledVehicles = { "ship/log2.mdl" } }
	eq(ids(assert(engine.modelCatalogue({ 100 }, LOGS, { vehicleFilter = vf }))), { 1 })
	eq(walks, 5, "a mission filter")
	engine.modelCatalogue({ 100 }, LOGS, { vehicleFilter = vf })
	eq(walks, 5)
	-- bounded: a full cache starts over
	for y = 1, engine.MAX_CATALOGUE_KEYS do engine.modelCatalogue({ 100 }, LOGS, { year = 2000 + y }) end
	walks = 0
	engine.modelCatalogue({ 100 }, LOGS, { vehicleFilter = vf })
	eq(walks, 1, "dropped with the rest")
	engine.clearCaches()
	engine.modelCatalogue({ 100 }, LOGS, { vehicleFilter = vf })
	eq(walks, 2)
	api.res.modelRep.forEachModelWithMetadata = each
end)

test("emptyLineInput: the Buy Vehicles depot's carrier, modes and tags; route, times, catalogue; reasons", function()
	emptyScene()
	W.cargoInfo = { sectionTimes = { 180, 180 }, driveSectionTimes = { 150, 150 } }
	local e, why = engine.emptyLineInput(54, LOGS)
	eq(why, nil)
	eq({ e.line, e.depot, e.cargo, e.distance, e.stops, e.yearSeconds }, { 54, 300, LOGS, 10000, 2, 1460 })
	eq(e.times.carrier, "water")
	local ids = {}
	for i, m in ipairs(e.catalogue) do ids[i] = m.model end
	eq(ids, { 1, 2 }, "log ships of the depot's SHIP mode with its tags (as for the fleet)")
	-- a small-ship depot
	W.depotModes[300] = { [SMALL_SHIP] = true }
	e = engine.emptyLineInput(54, LOGS)
	ids = {}
	for i, m in ipairs(e.catalogue) do ids[i] = m.model end
	eq(ids, { 8 })
	W.depotModes[300] = { [SHIP] = true }

	eq({ engine.emptyLineInput(54, PASSENGER) }, { nil, "no_models" })
	eq({ engine.emptyLineInput(54, nil) }, { nil, "no_cargo" })
	W.depotCarrier[300] = RAIL
	eq({ engine.emptyLineInput(54, LOGS) }, { nil, "rail" })
	W.depotCarrier[300] = WATER
	W.depotForLine[54] = nil
	eq({ engine.emptyLineInput(54, LOGS) }, { nil, "no_depot" })
	W.lineModes[54] = { ELECTRIC_TRAIN = true }
	eq({ engine.emptyLineInput(54, LOGS) }, { nil, "rail" }, "no depot for a train line: still a train line")
	W.depotForLine[54] = 300
	W.comps[75].BOUNDING_VOLUME = nil
	eq({ engine.emptyLineInput(54, LOGS) }, { nil, "no_positions" })
	eq({ engine.emptyLineInput(4040, LOGS) }, { nil, "not_a_line" })
	W.lineModes[54] = nil
	W.depotForLine[54] = 4041 -- a depot entity that no longer exists
	eq({ engine.emptyLineInput(54, LOGS) }, { nil, "no_depot" })
end)

test("emptyLineInput: re-reads reuse the catalogue and calibration; the depot read arms no store filter", function()
	emptyScene()
	W.cargoInfo = { sectionTimes = { 180, 180 }, driveSectionTimes = { 150, 150 } }
	local walks, scans = 0, 0
	local each = api.res.modelRep.forEachModelWithMetadata
	api.res.modelRep.forEachModelWithMetadata = function(kind, fn) walks = walks + 1; return each(kind, fn) end
	local getLines = api.engine.system.lineSystem.getLinesForPlayer
	api.engine.system.lineSystem.getLinesForPlayer = function(p) scans = scans + 1; return getLines(p) end
	local quiet = 0
	stub_module("square_line_manager_plus::/line_manager_plus/buy_line_filter.lua", {
		bestDepotQuiet = function(lu, l) quiet = quiet + 1; return lu.getBestDepotForLine(l) end,
	})
	local a = assert(engine.emptyLineInput(54, LOGS))
	local b = assert(engine.emptyLineInput(54, LOGS))
	eq({ walks, scans, quiet }, { 1, 1, 2 })
	eq(b.catalogue, a.catalogue)
	eq(b.depot, 300)
end)

test("yearSeconds and carrierKey", function()
	eq(engine.yearSeconds(), 1460)
	api.util.getDefaultYearDuration = function() return 0 / 0 end
	eq(engine.yearSeconds(), 1460)
	api.util.getDefaultYearDuration = function() return 2920000 end
	eq(engine.yearSeconds(), 2920)
	eq({ engine.carrierKey(WATER), engine.carrierKey(ROAD), engine.carrierKey(RAIL), engine.carrierKey("AIR"),
		engine.carrierKey("TRAM"), engine.carrierKey(nil) }, { "water", "road", "rail", "air", "tram", "other" })
end)

test("buyOntoLine: new vehicles of the model at the estimate's depot, onto the line; all or nothing", function()
	emptyScene()
	W.models[2].md.cost.price = 1000
	local got
	local r = commands.buyOntoLine(2, 3, 54, 300, function(res) got = res end)
	eq(got, r)
	eq(r.status, "ok"); eq(r.requested, 3); eq(r.depot, 300); eq(r.depotFrom, "estimate")
	eq(#r.bought, 3); eq(r.done, r.bought)
	eq(kinds(), { "buy", "setLine", "buy", "setLine", "buy", "setLine" })
	eq(W.sent[1].config.vehicles[1].part.modelId, 2)
	eq(W.sent[1].config.vehicleGroups, { 1 })
	eq(W.sent[2].line, 54); eq(W.sent[2].stop, 0)
	eq(W.events[1].param, { modelId2quantity = { [2] = 3 }, actuallyBuy = true })
	local charged = false
	for _, e in ipairs(log_entries()) do
		if e.msg:find("buy charged", 1, true) then charged = true end
	end
	ok(charged, "logs what the buy cost")

	-- the depot is gone: the line's best depot
	W.sent = {}
	r = commands.buyOntoLine(2, 1, 54, 4041)
	eq(r.status, "ok"); eq(r.depot, 300); eq(r.depotFrom, "line_util.getBestDepotForLine")
	-- money: nothing unless all are covered
	W.sent = {}
	W.comps[2].ACCOUNT.balance = 2999
	r = commands.buyOntoLine(2, 3, 54, 300)
	eq(r.status, "failed"); eq(r.reasons, { not_enough_money = 3 }); eq(#W.sent, 0)
	W.comps[2].ACCOUNT.balance = 1000000
	W.missionError = "No ships"
	r = commands.buyOntoLine(2, 1, 54, 300)
	eq(r.reasons, { mission = 1 }); eq(r.message, "No ships")
	W.missionError = nil
	eq(commands.buyOntoLine(2, 0, 54, 300).status, "invalid")
	eq(commands.buyOntoLine(nil, 1, 54, 300).reasons, { invalid_model = 1 })
	eq(commands.buyOntoLine(2, 1, 4040, 300).reasons, { invalid_line = 1 })
	eq(commands.buyOntoLine(2, 500, 54, 300).requested, commands.MAX_CLONES)
end)
