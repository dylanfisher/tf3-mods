-- No Factory Passengers: GUI-thread patch of the base line editor's automatic load config.
--
-- The line editor reruns line_util.autoLoadConfig(lineState2) on every edit of a line on automatic
-- load settings (manager_window.tl:6712 new line with its first stop, 6786 add stop, 6845 remove
-- stop, 6879 move stop, 6963 add waypoint), always through the module table field, which
-- line_util.tl:495 defines and :2098 returns. autoLoadConfig turns passengers on at every
-- passenger-capable stop (addPassengerByDefault, line_util.tl:454-461). This wrapper calls the
-- original, then, on a line that can load cargo at any stop (a cargo station with an industry or
-- warehouse in reach), clears the passenger flag at every stop; towns in reach do not matter. The
-- editor then commits the result itself, so no command is sent here and the mod keeps no state.
--
-- Same module table as manager_window: ug_require caches by the resolved path
-- (base/init.lua:62-91, _ug_loadedModules[resolved]). manager_window (a base file) asks for
-- "/gui/line_vehicle_mgmt/line_util.tl", which is "absolute in the current mod" = the base game
-- (docs/wiki/modding/general/resourcetypes.md:84-88), i.e. "::/gui/line_vehicle_mgmt/line_util.tl".
-- From this mod, "/gui/..." would resolve into this mod, so the "::/" form is required (as in
-- zhenya_auto_assign_terminals gui/aat_eow.script.lua, which wraps line_util.makeNewStop).

-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, every wrapped autoLoadConfig call
-- (section "auto_load_config": the base function plus the fix) and the fix alone ("fix_line"), both on
-- the GUI thread (line editor). Calls over 16 ms are logged (at most one line per section per minute);
-- with the "Debug: performance log" mod setting On, a 30 s summary, and the per-stop "passengers OFF"
-- lines (before: logged on every edit of a factory line). Local counters only; nothing is saved.
local MOD_ID = "square_no_factory_passengers"
local sqperf = ug_require "square_no_factory_passengers::/sqperf/square_no_factory_passengers.lua"
local perf = sqperf.new({ mod = MOD_ID, ctx = "gui", paramKey = "sqperf_log" })
local perfInit = perf:start()

local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local cargo_util = ug_require "::/gui/main/cargo_util.tl"
local logic = ug_require "square_no_factory_passengers::/no_factory_passengers/nfp_logic.lua"

local PREFIX = "[NoFactoryPassengers] "
-- Marker on the wrapped module table: installing twice (doReplace called again, this module
-- reloaded) never stacks a second wrapper.
local MARKER = "_square_nfp_wrapped"

local warned = {}
local function warnOnce(key, msg)
	if not warned[key] then
		warned[key] = true
		log.warning(PREFIX .. msg .. " (further failures not logged)")
	end
end

-- Classification by the entity's own components. No fallback scans: this runs on the GUI thread on
-- every line edit, and a forEachEntityWithComponent over every town building is a visible hitch on a
-- large map.
-- Cargo station: a station that handles cargo (passenger-only stations such as bus stops never load
-- cargo, whatever is in reach).
local function isCargoStation(station)
	return api.engine.util.station.isStationOfType(station, true) == true
end

-- Cargo source: cargo catchables are stock list owners (cargo_util.tl:565-582: town building,
-- industry, warehouse). Industries and warehouses supply or take cargo; town buildings only take
-- goods, so a town in reach does not make a cargo stop.
local function isCargoSource(entity)
	return api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY) ~= nil
		or api.engine.getComponent(entity, api.type.ComponentType.WAREHOUSE) ~= nil
end

-- The stations a stop loads at: its own station (stop.station1, 1-based into STATION_GROUP.stations,
-- set by the base autoLoadConfig, line_util.tl:520-530) so a bus stop grouped with a truck station
-- stays a passenger stop; the whole group when no station is assigned (as autoLoadConfig,
-- line_util.tl:551-552).
local function stopStations(stop)
	local stgr = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	local stations = stgr and stgr.stations or {}
	local own = stop.station1 and stop.station1 > 0 and stations[stop.station1]
	if own then
		return { own }, tostring(stop.stationGroup) .. ":" .. tostring(stop.station1)
	end
	return stations, tostring(stop.stationGroup)
end

-- Applies the rule to a Line.ReactLine after the base autoLoadConfig ran (logic.findCargoStop):
-- when any stop can load cargo, passengers off at every stop of the line.
local function fixLine(line)
	if line.customFilters then
		return
	end
	local paxIndex = cargo_util.getPassengerCargoTypeId() + 1
	-- every stop in path order (a cargo stop with passengers already off still makes a cargo line),
	-- each distinct stop station once
	local stops, keyIndex, stopInfo = {}, {}, {}
	local stopNumber = 0
	for __, via in ipairs(line.path or {}) do
		local stop = via.stop
		if stop then
			stopNumber = stopNumber + 1
			local stations, key = stopStations(stop)
			if not keyIndex[key] then
				stops[#stops + 1] = stations
				keyIndex[key] = #stops
			end
			stopInfo[#stopInfo + 1] = { number = stopNumber, stop = stop, index = keyIndex[key] }
		end
	end
	if #stops == 0 then
		return
	end
	local cargoStop = logic.findCargoStop(stops, api.engine.system.catchmentAreaSystem.getStationCatchables,
		isCargoStation, isCargoSource)
	if not cargoStop then
		return
	end
	local cargoNumber = nil
	for __, s in ipairs(stopInfo) do
		if s.index == cargoStop then
			cargoNumber = s.number
			break
		end
	end
	-- Per-stop log lines only with the "Debug: performance log" setting On (read once per edit, and
	-- only when a stop is cleared).
	local verbose = nil
	for __, s in ipairs(stopInfo) do
		local cfg = s.stop.passThroughStopData and s.stop.passThroughStopData.stopConfig
		-- the load table read from the StopConfig is a copy: read, change, assign back
		-- (as keepCargo does, line_util.tl:501-512)
		local load = cfg and cfg.load
		if load and load[paxIndex] == true then
			load[paxIndex] = false
			cfg.load = load
			if verbose == nil then
				verbose = sqperf.readParam(MOD_ID, "sqperf_log")
			end
			if verbose then
				log.message(PREFIX .. "stop " .. tostring(s.number) .. " group " .. tostring(s.stop.stationGroup)
					.. ": cargo line (stop " .. tostring(cargoNumber) .. " reaches an industry or warehouse)"
					.. " -> passengers OFF")
			end
		end
	end
end

--- Wraps target.autoLoadConfig once. Returns true when it installed the wrapper.
local function install(target)
	if target[MARKER] then
		return false
	end
	local original = target.autoLoadConfig
	if type(original) ~= "function" then
		warnOnce("install", "line_util.autoLoadConfig not found, patch not installed")
		return false
	end
	target.autoLoadConfig = function(line, ...)
		local tPerf = perf:start() -- SQPERF section "auto_load_config" (GUI thread)
		local result = original(line, ...)
		if line then
			local tFix = perf:start() -- SQPERF section "fix_line" (failed fixes count too)
			local ok, err = pcall(fixLine, line)
			perf:stop("fix_line", tFix)
			if not ok then
				warnOnce("fix", "passenger fix failed: " .. tostring(err))
			end
		end
		perf:stop("auto_load_config", tPerf)
		return result
	end
	target[MARKER] = true
	return true
end

-- Called by the GUI bootstrap (see nfp_patch.res.lua). The original is read here, not at module
-- load, so wrappers of other mods that run earlier stay in the chain.
local function doReplace(_replacementApi)
	if install(line_util) then
		log.message(PREFIX .. "installed (line_util.autoLoadConfig wrapped)")
	end
end

perf:phase("init", perfInit)

-- .script.lua resources expose their exports through data()
function data()
	return {
		doReplace = doReplace,
		install = install,
	}
end
