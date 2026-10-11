-- Problem Radar engine (sim-thread) game script (PLAN "Architecture"). Owns the per-savegame
-- state { version, settings, alerts, total, kindCounts, memory }, applies settings sent by the GUI,
-- scans the game's own problem flags into state.alerts (Phase 2) and infers stuck / blocked / old /
-- idle vehicles (Phase 3; the stuck and blocked timers live in state.memory), measures line
-- quality on a rotating slice of lines (Phase 4; sustain timers in state.memory), raises game
-- notifications for new alerts of "notify" kinds (Phase 5, decisions in radar_notify.tl) and judges
-- line economics (Phase 7: 12-month balances on their own rotating slice, and a yearly utilisation
-- average per line fed by the line-quality measurements; the averages' saved copy in state.memory).
-- Every kind is smoothed over settings.smoothSec game seconds (radar_checks.merge: new problems wait
-- in state.pending, gone ones linger), so a flag that toggles between scans does not flicker. Game
-- time stands still while paused, so the smoothing simply holds then.
-- READ-ONLY toward the simulation: the only commands it sends are "Notifications"/"add" events to
-- the base notifications game script (the same event the base sim scripts and the official
-- cosmetic campaign mods send; it only appends to the notification list). It never changes
-- entities; it reads the API and keeps its own small state (plain tables; entity ids are stored as
-- plain numbers the game never resolves).
-- Everything that must survive save/load lives in GameScriptState. The engine runs this script in
-- ~14 simulation Lua states and each tick goes to whichever one is free (PERF_VMS.md): state is
-- shared by all of them, module-level values are per Lua state. So what one scan hands to the next
-- (notification priming, the toast budget, failure counters, the line-quality and economy cursors,
-- the young stuck timers, the ineligible-vehicle marks) lives in state.rt (radar_checks.cleanRuntime /
-- packRuntime), read with the state:get every scan slot does anyway. Module-level values are only
-- caches whose loss or divergence changes the cost, never a result (listed below). state:set runs
-- only when alerts, timers, settings, the notify maps or state.rt changed; state.seq (the window's
-- poll) moves only when what the window shows changed. Every engine entry point (update,
-- handleEvent) runs in a pcall: a script error is logged once and never reaches the game's update
-- loop or a save.
--
-- Layers: gather* functions below are the ONLY place that calls api.*; they build the plain input
-- tables of radar_types.d.tl. radar_checks.tl (pure, unit-tested) turns them into alerts and
-- merges them into the state.
--
-- Console (debug mode), e.g.:
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting", { hudMode = "compact" }))
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting", { notify = { veh_stuck = "off" } }))
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.resetSettings", {}))
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.snooze", { id = "line_unprofitable:123" }))
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.unsnooze", {}))
-- src (console pattern): .cache/game/base/content/game_mechanics/subventions/subventions.script.tl:9-12

-- SQPERF (plans/sqperf/README.md): load time of this Lua state, the first scan of each group, slow
-- updates / scans / events (> 50 ms, at most one line per section per minute), and with the
-- "Debug: performance log" mod setting a 30 s summary. Local counters only; nothing is saved.
-- Created before the other modules load, so phase=init includes them.
local sqperf = ug_require "square_problem_radar::/sqperf/square_problem_radar.lua" as SquareProblemRadarSqPerf
local perf = sqperf.new({ mod = "square_problem_radar", ctx = "gs", paramKey = "sqperf_log",
	first = { "scan_lines", "scan_stations", "scan_vehicles", "scan_fleet" } })
local perfInit = perf:start()

local radar_settings = ug_require "square_problem_radar::/radar/radar_settings.tl" as ProblemRadarSettingsModule
local radar_checks = ug_require "square_problem_radar::/radar/radar_checks.tl" as ProblemRadarChecks
-- Also required by the base sim script vehicle_warning.sim.script.tl:2 (sim-side use is proven).
local vehicle_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl" as VehicleUtil

local radar_notify = ug_require "square_problem_radar::/radar/radar_notify.tl" as ProblemRadarNotifyModule
-- Sim-side use proven by the base sim scripts (types/industry_close.sim.script.tl:1).
local entity_util = ug_require "::/scripts/entity_util.tl" as EntityUtil

local EVENT_ID <const> = "ProblemRadar"
local EV_SET_SETTING <const> = "ProblemRadar.setSetting"
local EV_RESET_SETTINGS <const> = "ProblemRadar.resetSettings"
-- Snooze one listed alert ({ id = "<alert id>" }, for settings.snoozeMonths) / end one ({ id = ... }) or
-- every snooze ({}).
local EV_SNOOZE <const> = "ProblemRadar.snooze"
local EV_UNSNOOZE <const> = "ProblemRadar.unsnooze"
-- Rev 6: after the fleet window's Upgrade ({ vehicles = { <entity>, ... } }): re-read those vehicles now
-- and drop their fleet_old / fleet_worn alerts that no longer hold (radar_checks.fleetCleared / dropAlerts).
local EV_RECHECK <const> = "ProblemRadar.recheckVehicles"
local PREFIX <const> = "[ProblemRadar] "
-- Notification type: content/radar/notify/radar_notification.{res.lua,script.tl}. The base maps the
-- type string "<mod>::/<path>.script" to "<path>.res" (notification_util.tl:12-14) and calls
-- "<type>@useDataState" on the GUI thread (gui/notification_popups.tl:62).
local NOTIFY_TYPE <const> = "square_problem_radar::/radar/notify/radar_notification.script"
-- notification_util.defaultAutoDismissDurationMs (notification_util.tl:9): hide the popup after 60 s.
local NOTIFY_DISMISS_MS <const> = 60000

-- Staggering (PLAN: "slice by tick count, like the base notifications script",
-- notifications.script.tl:48-49). One scan group runs every SLOT_SPACING updates, so a full
-- refresh of all 4 groups takes 4 * 3 = 12 updates. A sim update is 0.2 s of real time at any
-- game speed (mission_sim.script.tl:625: dt / speedup, default 0.2), so about 2.4 s.
-- While paused the base still scans, on tickCount (notifications.script.tl:48); tickCount runs
-- "once per frame" when paused (engine.d.tl GameTime), so space the slots wider there.
local SLOT_SPACING <const> = 3
-- About 45 frames per slot (4 slots = 180 frames, ~3 s at 60 fps), so the paused cycle costs
-- about the same as the live 2.4 s one.
local PAUSED_SLOT_SPACING <const> = 45
-- getFailedPathReason may run a path search: look up at most this many new no-path vehicles per
-- scan; known ones reuse the reason stored in their alert.
local MAX_FAILURE_LOOKUPS <const> = 4
-- veh_stuck: "speed ~ 0". The base stuck rule tests getSpeed(v) == 0 (notifications.script.tl:556);
-- a tiny margin also catches float noise.
local STANDING_SPEED <const> = 0.01
-- fleet_old: ages are read for 1 / AGE_SLICES of the fleet per fleet pass (one TRANSPORT_VEHICLE
-- copy per vehicle read), so each vehicle is re-checked every AGE_SLICES * 2.4 s, about 19 s.
local AGE_SLICES <const> = 8
-- Phase 4 line quality: each lines pass measures the next few lines after lineCursor
-- (radar_checks.lineRotation), at most QUALITY_MAX_LINES, and stops early once a line pushed the
-- waiting-count queries (stops x carried cargo types) past QUALITY_MAX_QUERIES. At least one line
-- is always measured, so a full rotation of L lines takes about L / 8 lines passes of 2.4 s.
local QUALITY_MAX_LINES <const> = 8
local QUALITY_MAX_QUERIES <const> = 160
-- Phase 7 line_unprofitable: each lines pass checks the money of at most this many lines (1 to 7
-- calculateBalance calls each, radar_checks.lineMoney) on its own rotating cursor, and only lines
-- whose last check is a game month old (radar_checks.dueRotation, ECON_RECHECKS_PER_YEAR): money
-- moves over game months. Up to about 200 lines that is one check per line and game month; above,
-- the cap makes a full rotation take L / 4 passes of 2.4 s.
local ECON_MAX_LINES <const> = 4

-- Shared bookkeeping (state.rt, ProblemRadarRuntime): the working copy for the scan slot being run.
-- scanGroupBody sets it from the state before the scan (radar_checks.cleanRuntime) and stores it back
-- (packRuntime) after; the scan functions read and change its fields. Never carried from one slot to
-- the next in this variable (the next slot may run in another Lua state): only through the state.
--   prime       Phase 6 notification priming (radar_notify.step silentAll / silentKinds): set when the
--               mod is added to a save (fresh state) or kinds switch to "notify"; dropped after a notify
--               step that followed one scan of every group (prime.seen), so old alerts never burst.
--   budget      Phase 6 toast budget (radar_notify.applyBudget).
--   fails       Phase 6 failure isolation: consecutive failures per scan group / sub-scan ("stuck",
--               "lineQuality", Phase 7 "econMoney", "econUse"). radar_checks.carryOver / FAIL_DROP_AFTER.
--   lineCursor  Phase 4 rotating line cursor: the last line measured.
--   econCursor  Phase 7 line_unprofitable cursor; econGen / econOff: switching it off drops every Lua
--               state's econCheckedAt (below), so switching it back on re-checks every line at once.
--   young       stopped / blocked timers younger than PERSIST_TIMER_AFTER_MS (state.memory keeps the
--               older ones), so vehicles that stop for a few seconds don't rewrite state.memory.
--   ineligible  standing vehicles found foreign / user-stopped / not en route (with the time;
--               re-checked after INELIGIBLE_RECHECK_MS), so their timers don't fill the timer cap.
local rt : ProblemRadarRuntime = {}

-- Per-Lua-state caches. Each state has its own copy; losing or diverging changes the cost, never a
-- result (PERF_VMS "Side effects", reviewed 2026-10-10):
-- Cached once per Lua state: the map editor and a game are separate loads, so this never changes
-- while the script runs.
local mapEditorCache : boolean = nil
-- Warn once per scan group when a gather fails (log hygiene only: one line per Lua state at most).
local warned : {string : boolean} = {}
-- Model lifespans (ms) by model id: resource data, fixed for the whole load.
local lifespanCache : {integer : integer} = {}
-- Phase 7: the game time each line's money was last checked by this Lua state (pruned to the
-- eligible lines every pass). Due lines are taken after the shared rt.econCursor, so the rotation
-- covers every line at the designed rate; a line is re-checked at most once a game month per Lua
-- state (more often in total, still at most ECON_MAX_LINES per pass). A fresh Lua state (a load)
-- re-checks every line once at the capped rate. econGen: the rt.econGen these belong to.
local econCheckedAt : {integer : integer} = {}
local econGen : integer = nil
-- Phase 7: all eligible lines' yearly vehicle costs (> 0; nil = unknown), the size reference of
-- radar_checks.judgeLoss, and the game time it was computed (re-computed once a game month per Lua
-- state: every copy is at most a game month old, as designed).
local econNetworkCost : integer = nil
local econNetworkAt : integer = nil
-- Phase 7 line_low_use: float copy of the averages (updated on every sample) and the game time it was
-- last updated. state.memory.useAvg is the shared copy, rewritten on every pass that took a sample;
-- radar_checks.reconcileUseAvg keeps this copy only while it is still the newest (no other Lua state
-- sampled since), else rebuilds it from the state.
local liveUse : {integer : ProblemRadarUseAvg} = nil
local liveUseAt : integer = nil
-- Phase 6 stuck-scan cache (pruned every vehicles pass): the carrier of owned standing vehicles
-- (read once per Lua state; a carrier never changes).
local carrierCache : {integer : string} = {}
local INELIGIBLE_RECHECK_MS <const> = 10 * 60 * 1000
-- Phase 6 fleet_old: creation revision per listed entity, so a reused id drops the kept row. A Lua
-- state without the entry keeps the row; the vehicle's age slice re-decides it within AGE_SLICES
-- fleet passes either way (inside the smoothing window, so no visible difference).
local oldRevs : {integer : integer} = {}
-- Phase 6: getVehiclesWithState fallback list per state, re-scanned only every
-- FALLBACK_REFRESH calls (in between: the cached list, minus entities that are gone).
local fallbackLists : {string : {integer}} = {}
local fallbackAge : {string : integer} = {}
local FALLBACK_REFRESH <const> = 8

local function warnOnce(key : string, msg : string)
	if warned[key] then return end
	warned[key] = true
	log.warning(PREFIX .. msg .. " (further failures not logged)")
end

--- A new priming request on top of `prev`: every kind (kinds == nil) or these kinds. The groups seen
--- start again, so priming lasts one full scan of every group after the latest request.
local function requestPrime(prev : ProblemRadarPrime, kinds : {string : boolean}) : ProblemRadarPrime
	local p : ProblemRadarPrime = { all = prev ~= nil and prev.all == true, kinds = {}, seen = {} }
	if prev ~= nil then
		for k, v in pairs(prev.kinds or {}) do p.kinds[k] = v end
	end
	if kinds == nil then
		p.all = true
	else
		for k in pairs(kinds) do p.kinds[k] = true end
	end
	return p
end

--- Failure isolation counters in rt.fails: +1 (returns the new count) / back to 0.
local function failed(key : string) : integer
	rt.fails = rt.fails or {}
	local n = (rt.fails[key] or 0) + 1
	rt.fails[key] = n
	return n
end

local function succeeded(key : string)
	if rt.fails ~= nil then rt.fails[key] = nil end
end

--- A state that never had the v5 notify maps (none at all, or an older version): the mod was just
--- added (or comes from a pre-notification build), so the first cycle's alerts are not "new".
local function needsPrime(raw : any) : boolean
	if type(raw) ~= "table" then return true end
	local v = (raw as ProblemRadarState).version
	return type(v) ~= "number" or v < 5
end

--- Creation revision of an entity (entity_util.makeEntityAndRevision0 reads num[1]); nil if gone.
--- The state's listed alerts followed by its pending ones (smoothing). Scans that keep rows they did
--- not re-check (line-quality keep, fleet_old keepOld, failure carryOver) keep pending ones too, so a
--- pending id is not dropped just because its line / vehicle slice was not measured this pass.
local function listedAndPending(s : ProblemRadarState) : {ProblemRadarAlert}
	local out : {ProblemRadarAlert} = {}
	for __, a in ipairs(s.alerts or {}) do out[#out + 1] = a end
	for __, a in ipairs(s.pending or {}) do out[#out + 1] = a end
	return out
end

local function revOf(e : integer) : integer
	if e == nil or e < 0 or not api.engine.entityExists(e) then return nil end
	local r = api.engine.getRevision(e)
	return r ~= nil and r.num ~= nil and r.num[1] as integer or nil
end

local function isMapEditor() : boolean
	-- Do nothing at all in the map editor (no state, no subscriptions). Same check as the base:
	-- src: .cache/game/base/content/game_mechanics/company/company_growth.script.tl:74;
	-- API: .cache/game/api/tealdef/api/engine.d.tl:1807 (getModParams)
	if mapEditorCache == nil then
		local params = api.engine.config.getModParams()
		local base = params ~= nil and params[""] or nil
		mapEditorCache = base ~= nil and base["isMapEditor"] == true
	end
	return mapEditorCache
end

---------------------------------------------------------------------------
-- Gather helpers (API → plain values)

local function exists(e : integer) : boolean
	return e ~= nil and e >= 0 and api.engine.entityExists(e)
end

--- Entity name the way the base notification sim scripts get it
--- (line_warning.sim.script.tl:7 via entity_util.getEntityName = api.engine.util.getEntityName).
local function nameOf(e : integer) : string
	if not exists(e) then return "" end
	return api.engine.util.getEntityName(e) or ""
end

--- Ownership test with a per-scan cache: PLAYER_OWNED.player == getPlayer()
--- (base entity_util.isOwnedByPlayer, .cache/game/base/content/scripts/entity_util.tl:79-82).
--- The second function skips the entityExists call, for ids handed out by
--- forEachEntityWithComponent (they exist; the base vehicle-condition loop reads PLAYER_OWNED
--- directly, notifications.script.tl:307-309): one API call less per vehicle in the fleet pass.
local type OwnedFn = function(integer) : boolean
local function makeOwnership() : OwnedFn, OwnedFn
	local player = api.engine.util.getPlayer()
	local cache : {integer : boolean} = {}
	local function read(e : integer, live : boolean) : boolean
		local c = cache[e]
		if c == nil then
			c = false
			if live or exists(e) then
				local po = api.engine.getComponent(e, api.type.ComponentType.PLAYER_OWNED) as Engine.Component.PlayerOwned
				c = po ~= nil and po.player == player
			end
			cache[e] = c
		end
		return c
	end
	return function(e : integer) : boolean return read(e, false) end,
		function(e : integer) : boolean return read(e, true) end
end

local function vec(v : Vec3f) : {number}
	if v == nil then return nil end
	return { v.x, v.y, v.z }
end

local function intEnum(v : any) : integer
	return v as integer
end

--- {enumValue → name} for an integer enum record (api.type["enum"].X), listing the names we use.
local function enumNames(e : {string : integer}, names : {string}) : {integer : string}
	local m : {integer : string} = {}
	for __, n in ipairs(names) do
		local v = e[n]
		if v ~= nil then m[v] = n end
	end
	return m
end

-- Enum names: .cache/game/api/tealdef/api/type.d.tl:2144-2172 (LineProblem, LineStationProblem,
-- VehicleProblem), :5682-5733 (Failure.Reason, LineIssue.Type), :2217-2234 (TransportMode).
local LINE_PROBLEM_NAMES <const> = { "NOTHING", "ZERO_OR_ONE_STATION", "DOUBLE_STATIONS", "INCOMPATIBLE_STATIONS", "NO_PATH", "BAD_ALTERNATIVE_TERMINAL" }
local LINE_STATION_PROBLEM_NAMES <const> = { "StopUseless", "PassengerStopUseless", "CargoStopUseless", "AllPassengerStopUseless", "CargoTypeUnloadUseless", "CargoTypeLoadUseless" }
local VEHICLE_PROBLEM_NAMES <const> = { "NoPathElectric", "NoPathShip", "NoPathAircraft", "NoPathGeneric", "Blocked" }
local MODE_NAMES <const> = { "CAR", "BUS", "TRUCK", "TRAM", "ELECTRIC_TRAM", "TRAIN", "ELECTRIC_TRAIN", "AIRCRAFT", "SHIP", "SMALL_AIRCRAFT", "SMALL_SHIP", "HELICOPTER", "TRAM_TRACK", "ELECTRIC_TRAM_TRACK" }

--- {TransportMode : boolean} → {name : boolean}. Same lookups as base line_util.getRelaxationType
--- (okModes[tm.ELECTRIC_TRAIN]).
local function modeSet(m : {TransportMode : boolean}) : {string : boolean}
	if m == nil then return nil end
	local tm = api.type["enum"].TransportMode as {string : TransportMode}
	local out : {string : boolean} = {}
	for __, n in ipairs(MODE_NAMES) do
		local key = tm[n]
		if key ~= nil and m[key] then out[n] = true end
	end
	return out
end

local function lineIssueName(t : LineIssue.Type) : string
	-- Compared like base line_warning.script.tl:15-37
	local T = api.type.LineIssue.Type
	if t == T.NowhereToLoad then return "NowhereToLoad" end
	if t == T.NowhereToUnload then return "NowhereToUnload" end
	if t == T.NoVehicleToLoadCargo then return "NoVehicleToLoadCargo" end
	if t == T.VehicleUseless then return "VehicleUseless" end
	if t == T.LineCargoConfig then return "LineCargoConfig" end
	return nil -- None / unknown
end

local function failureReasonName(r : Failure.Reason) : string
	-- Compared like base manager_window.tl:5410-5421. NoPath / Unkown give no extra detail.
	local R = api.type.Failure.Reason
	if r == R.NoElectric then return "NoElectric" end
	if r == R.NoTram then return "NoTram" end
	if r == R.NoTramButTramTrack then return "NoTramButTramTrack" end
	if r == R.NoTramTrackButRail then return "NoTramTrackButRail" end
	if r == R.NoRail then return "NoRail" end
	if r == R.NoRoad then return "NoRoad" end
	if r == R.NoSmallAircraft then return "NoSmallAircraft" end
	if r == R.NoSmallShip then return "NoSmallShip" end
	return nil
end

--- Carrier name for radar_settings.STUCK_KEYS. Compared directly (like lineIssueName) rather than
--- used as a table key. Enum: .cache/game/api/tealdef/api/type.d.tl:404-418.
local function carrierName(c : Carrier) : string
	local C = api.type["enum"].Carrier
	if c == C.ROAD then return "ROAD" end
	if c == C.TRAM then return "TRAM" end
	if c == C.RAIL then return "RAIL" end
	if c == C.WATER then return "WATER" end
	if c == C.AIR then return "AIR" end
	return "OTHER"
end

local function cargoName(id : integer) : string
	if id == nil or id < 0 then return nil end
	local ct = api.res.cargoTypeRep.get(id)
	return ct ~= nil and ct.name or nil
end

---------------------------------------------------------------------------
-- Gather + check, one function per scan group (radar_checks.GROUPS). Base reference for every
-- call: .cache/game/base/content/game_mechanics/notifications/notifications.script.tl.

local function getTv(v : integer) : Engine.Component.TransportVehicle
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
end

--- Measure one line for Phase 4 (radar_types ProblemRadarLineQuality). Returns it and the number
--- of waiting-count queries it cost.
--- * Capacity / utilisation: getLineCapacityUsages(line, false), indexed by cargoTypeId + 1, like the
---   base line window "Utilization" (cargo_util.tl:709-711, 895-907; statistics_react_util.tl:194-218).
--- * Waiting: simEntityAtTerminalSystem.getLineStopSimEntitiesCount(line, 0-based stop, cargo)
---   (system.d.tl:186-192; the base passenger tooltip calls the sibling getLineStopSimEntities with the
---   same arguments, station_group.tl:664).
--- * Target interval: 1 / getMaxFrequency seconds, the base "Frequency: time interval between the
---   vehicles" (line_util.tl:1350-1354, manager_window.tl:3972-3986), here in game ms.
--- * Departures: TRANSPORT_VEHICLE.lineStopDepartures ("timestamps of the last departures at each line
---   stop", engine.d.tl:1482-1483) of the running (EN_ROUTE / AT_TERMINAL) vehicles.
--- `full` false (Phase 7: only line_low_use needs measuring): utilisation only, i.e. one
--- getLineCapacityUsages call; vehicles = the line's vehicle count from the lines pass.
local function measureLine(line : integer, name : string, full : boolean, vehicleCount : integer) : ProblemRadarLineQuality, integer
	local q : ProblemRadarLineQuality = { name = name, vehicles = 0, used = 0, capacity = 0, stops = {}, intervalMs = 0, fullLoad = false, departures = {} }
	local cargoCaps : {integer : number} = {}
	local function usages()
		for idx, u in pairs(api.engine.util.line.getLineCapacityUsages(line, false) or {}) do
			if u ~= nil and (u.capacity or 0) > 0 then
				q.used = q.used + (u.used or 0)
				q.capacity = q.capacity + u.capacity
				cargoCaps[(idx as integer) - 1] = u.capacity
			end
		end
	end
	if not full then
		usages()
		q.vehicles = vehicleCount or 0
		return q, 0
	end
	local comp = api.engine.getComponent(line, api.type.ComponentType.LINE) as Engine.Component.Line
	if comp == nil or comp.stops == nil then return q, 0 end
	usages()

	local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line) or {}
	local TVS = api.type["enum"].TransportVehicleState
	for __, v in ipairs(vehicles) do
		local tv = getTv(v)
		if tv ~= nil and (tv.state == TVS.EN_ROUTE or tv.state == TVS.AT_TERMINAL) then
			q.vehicles = q.vehicles + 1
			local d : {integer} = {}
			for i, t in ipairs(tv.lineStopDepartures or {}) do d[i] = t end
			q.departures[#q.departures + 1] = d
		end
	end

	-- Full-load stops: Engine.Component.Line.LoadMode FULL_LOAD_ANY / FULL_LOAD_ALL (engine.d.tl:496-501),
	-- read at runtime as api.type.Line.LoadMode like the base reads nested enums
	-- (api.type.TransportVehicle.LoadState in cargo_react_util.tl:111). Fallback: the values 1 / 2
	-- (the base departure toggle maps button index - 1 to loadMode, cargofilter_window.tl:812-822).
	local LM = api.type.Line ~= nil and api.type.Line.LoadMode or nil
	local fullAny = LM ~= nil and LM.FULL_LOAD_ANY as integer or 1
	local fullAll = LM ~= nil and LM.FULL_LOAD_ALL as integer or 2
	local queries = 0
	local tas = api.engine.system.simEntityAtTerminalSystem
	for i, stop in ipairs(comp.stops) do
		local mode = stop.loadMode as integer
		if mode == fullAny or mode == fullAll then q.fullLoad = true end
		for cargo, cap in pairs(cargoCaps) do
			queries = queries + 1
			local w = tas.getLineStopSimEntitiesCount(line, i - 1, cargo)
			if w ~= nil and w > 0 then
				local st : ProblemRadarStopLoad = { stop = i - 1, waiting = w, perTrip = #vehicles > 0 and cap / #vehicles or 0, name = "" }
				if w >= radar_checks.MIN_OVERLOAD_WAITING then st.name = nameOf(stop.stationGroup) end
				q.stops[#q.stops + 1] = st
			end
		end
	end

	local freq = api.engine.util.line.getMaxFrequency(line)
	if freq ~= nil and freq >= 0.0001 then q.intervalMs = math.floor(1000 / freq) end
	return q, queries
end

local QUALITY_KINDS <const> : {string : boolean} = { line_overloaded = true, line_underused = true, line_bunching = true }

--- Phase 4: measure the next slice of eligible lines and run radar_checks.lineQuality.
--- Phase 7: also returns each measured line's utilisation sample (line -> Σused / Σcapacity, the
--- line_underused measure) for line_low_use. `quality` false: only those samples are wanted (every
--- line-quality kind is off), so lines are measured light (utilisation only) and no alerts come back.
local function scanLineQuality(s : ProblemRadarState, now : integer, lines : {integer : ProblemRadarLineInfo},
		broken : {integer : boolean}, memory : ProblemRadarMemory, quality : boolean) : {ProblemRadarAlert}, ProblemRadarMemory, boolean, {integer : number}
	local eligible : {integer : boolean} = {}
	local ids : {integer} = {}
	for line, info in pairs(lines) do
		if info.owned and (info.stops or 0) >= 2 and (info.vehicles or 0) > 0 and not broken[line] then
			eligible[line] = true
			ids[#ids + 1] = line
		end
	end
	local measured : {integer : ProblemRadarLineQuality} = {}
	local samples : {integer : number} = {}
	local cursor = rt.lineCursor or -1
	local count, queries = 0, 0
	for __, line in ipairs(radar_checks.lineRotation(ids, cursor)) do
		if count >= QUALITY_MAX_LINES or queries >= QUALITY_MAX_QUERIES then break end
		local q, cost = measureLine(line, lines[line].name, quality, lines[line].vehicles)
		measured[line] = q
		-- line_low_use sample: lines with capacity and >= 1 running vehicle (light: >= 1 vehicle).
		if q.capacity > 0 and q.vehicles >= 1 then samples[line] = q.used / q.capacity end
		count = count + 1
		queries = queries + cost
		cursor = line
	end
	-- Shared (state.rt): the next lines pass, in whichever Lua state, continues after it. Unchanged
	-- (every line measured each pass) means no state write.
	if cursor ~= -1 then rt.lineCursor = cursor end
	if not quality then return {}, memory, false, samples end
	local keep : {ProblemRadarAlert} = {}
	for __, a in ipairs(listedAndPending(s)) do
		if type(a) == "table" and QUALITY_KINDS[a.kind] then keep[#keep + 1] = a end
	end
	local alerts, newMemory, changed = radar_checks.lineQuality({
		now = now,
		settings = s.settings,
		lines = measured,
		eligible = eligible,
		keep = keep,
		memory = memory,
	})
	return alerts, newMemory, changed, samples
end

--- Replace some timer maps with empty ones (a scan whose kinds are all "off"). Returns the memory
--- and whether anything was dropped (so the state is saved once, then stays unchanged).
local function clearTimers(memory : ProblemRadarMemory, keys : {string}) : ProblemRadarMemory, boolean
	local m = memory or radar_checks.freshMemory()
	local patch : {string : any} = {}
	local changed = false
	for __, k in ipairs(keys) do
		local t = (m as {string : any})[k]
		if type(t) ~= "table" or next(t as table) ~= nil then changed = true end
		patch[k] = {}
	end
	if not changed then return m, false end
	return radar_checks.patchMemory(m, patch as ProblemRadarMemory), true
end

local LINE_TIMERS <const> = { "overloadSince", "underusedSince", "bunchingSince" }
local USE_MAPS <const> = { "useAvg" }
local VEHICLE_TIMERS <const> = { "stoppedSince", "blockedSince", "blockedBy" }

local function on(s : ProblemRadarState, kind : string) : boolean
	return radar_notify.isOn(s.settings, kind)
end

---------------------------------------------------------------------------
-- Phase 7 economy (PLAN "Phase 7").

--- One line's money over the trailing year: api.engine.util.finance.calculateBalance({line}, from, to,
--- true) is exactly the base line window's 12-month "Balance" (line_react_util.tl:620-640: from =
--- gameTime - getDefaultYearDuration(), maintenance / income entries only). The base statistics window
--- sums the line's current vehicles instead (statistic_lines.tl:289-294); the line entity is used
--- here because its account keeps the history of vehicles sold or moved since.
--- Cost split: the same call with a maintenanceType (util.d.tl:841-848; base passes
--- api.type.JournalEntry.Maintenance.VEHICLE_MAINTENANCE that way, maintenance_station_eow.script.tl:134,
--- entity_window_util.tl:2177): VEHICLE = "Running Costs Vehicles", VEHICLE_MAINTENANCE = "Maintenance
--- Vehicles" (finances_util.tl:68-73). The nested enum is read at runtime like
--- api.type.Line.LoadMode; without it the split is unknown (radar_checks.judgeLoss: Warning).
--- Up to 7 calls (year, 4 quarters, 2 cost types); radar_checks.lineMoney stops as soon as the
--- verdict is settled, so a profitable line costs 1.
local function costTypes() : any, any
	local JE = api.type.JournalEntry
	local M = JE ~= nil and JE.Maintenance or nil
	if M ~= nil and M.VEHICLE ~= nil and M.VEHICLE_MAINTENANCE ~= nil then
		return M.VEHICLE, M.VEHICLE_MAINTENANCE
	end
	return nil, nil
end

local function measureMoney(line : integer, now : integer, yearMs : integer) : ProblemRadarLineMoney
	local calc = api.engine.util.finance.calculateBalance
	local ents = { line }
	local vehicleType, maintType = costTypes()
	return radar_checks.lineMoney(function(from : integer, to : integer, mt : any) : number
		if mt == nil then return calc(ents, from, to, true) end
		return calc(ents, from, to, true, mt as JournalEntry.Maintenance)
	end, now, yearMs, vehicleType, maintType)
end

--- Phase 7 eligibility, once per lines pass for both sub-scans: owned lines with >= 1 vehicle
--- (line_unprofitable; also as a list), of those the line-quality eligible ones (>= 2 stops, not
--- broken: line_low_use), and every owned line (line_low_use keeps their averages).
local record EconLines
	money : {integer : boolean}
	moneyIds : {integer}
	use : {integer : boolean}
	owned : {integer : boolean}
end

local function econEligible(lines : {integer : ProblemRadarLineInfo}, broken : {integer : boolean}) : EconLines
	local e : EconLines = { money = {}, moneyIds = {}, use = {}, owned = {} }
	for line, info in pairs(lines) do
		if info.owned then
			e.owned[line] = true
			if (info.vehicles or 0) > 0 then
				e.money[line] = true
				e.moneyIds[#e.moneyIds + 1] = line
				if (info.stops or 0) >= 2 and not broken[line] then e.use[line] = true end
			end
		end
	end
	return e
end

--- line_unprofitable: the money of the next few due lines (rt.econCursor, econCheckedAt). Nothing is
--- judged before the game is a year old (no line can have a full year of history). calculateBalance
--- is called only by base GUI code so far: this runs in its own pcall (scanLines).
local function scanMoney(s : ProblemRadarState, now : integer, lines : {integer : ProblemRadarLineInfo},
		econ : EconLines) : {ProblemRadarAlert}
	local yearMs = api.util.getDefaultYearDuration()
	local eligible = econ.money
	local money : {integer : ProblemRadarLineMoney} = {}
	local keep : {ProblemRadarAlert} = {}
	-- Lines with a pending (smoothing, not yet listed) row are re-checked once the smoothing window has
	-- passed rather than a month later, so a new row still matures after smoothSec.
	local soon : {integer : boolean} = {}
	for __, a in ipairs(listedAndPending(s)) do
		if type(a) == "table" and a.kind == "line_unprofitable" then keep[#keep + 1] = a end
	end
	for __, a in ipairs(s.pending or {}) do
		if type(a) == "table" and a.kind == "line_unprofitable" and type(a.entity) == "number" then soon[a.entity] = true end
	end
	for line in pairs(econCheckedAt) do
		if not eligible[line] then econCheckedAt[line] = nil end
	end
	if yearMs ~= nil and yearMs > 0 and now >= yearMs then
		local everyMs = math.max(1, yearMs // radar_checks.ECON_RECHECKS_PER_YEAR)
		local soonMs = math.max(0, math.floor(s.settings.smoothSec or 0)) * 1000
		local due = radar_checks.dueRotation(econ.moneyIds, rt.econCursor or -1, econCheckedAt, now, everyMs, ECON_MAX_LINES, soon, soonMs)
		-- The size reference: 2 calls over every eligible line, once a game month (only when some line
		-- is due, so a network without lines makes none). Unknown (no enum, no costs) = nil.
		if #due > 0 and (econNetworkAt == nil or now < econNetworkAt or now - econNetworkAt >= everyMs) then
			local vehicleType, maintType = costTypes()
			local cost : integer = nil
			if vehicleType ~= nil then
				local calc = api.engine.util.finance.calculateBalance
				local from = now - yearMs
				local c = -(calc(econ.moneyIds, from, now, true, vehicleType as JournalEntry.Maintenance)
					+ calc(econ.moneyIds, from, now, true, maintType as JournalEntry.Maintenance))
				if c > 0 then cost = math.floor(c) end
			end
			econNetworkCost, econNetworkAt = cost, now
		end
		for __, line in ipairs(due) do money[line] = measureMoney(line, now, yearMs) end
		-- Marked only once the whole slice succeeded: a throwing calculateBalance retries the same lines
		-- next pass, so the failure count keeps rising and FAIL_DROP_AFTER still applies.
		for __, line in ipairs(due) do
			econCheckedAt[line] = now
			rt.econCursor = line -- shared (state.rt)
		end
	end
	return radar_checks.unprofitable({ settings = s.settings, lines = lines, money = money, eligible = eligible, keep = keep,
		networkCost = econNetworkCost })
end

--- line_low_use: fold this pass's utilisation samples into the live averages, save them when lines
--- come or go or once a game month (radar_checks.persistUseAvg), and judge every tracked line.
--- Returns the alerts and the memory (+ whether it changed).
local function scanUse(s : ProblemRadarState, now : integer, lines : {integer : ProblemRadarLineInfo},
		econ : EconLines, samples : {integer : number}, memory : ProblemRadarMemory) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local yearMs = api.util.getDefaultYearDuration()
	local saved = memory.useAvg
	local live = radar_checks.reconcileUseAvg(saved, liveUse, liveUseAt, now)
	-- Lines that are gone (or no longer the player's) drop their averages; owned lines that are
	-- temporarily not measured (broken, no vehicles) keep theirs.
	live = radar_checks.sampleUseAvg(live, samples or {}, econ.owned, now, yearMs)
	liveUse, liveUseAt = live, now
	local alerts = radar_checks.lowUse({ now = now, yearMs = yearMs, settings = s.settings, lines = lines, eligible = econ.use, useAvg = live })
	-- Shared after every pass that took a sample (cadence 1 ms: any newer sample): the next lines pass
	-- usually runs in another Lua state and must continue from these averages, or the samples of every
	-- Lua state but the writer would be lost (PERF_VMS). The lines pass writes rt.lineCursor then anyway.
	local newSaved, persist = radar_checks.persistUseAvg(live, saved, 1)
	if not persist then return alerts, memory, false end
	return alerts, radar_checks.patchMemory(memory, { useAvg = newSaved }), true
end

local QUALITY_KINDS_LIST <const> = { "line_overloaded", "line_underused", "line_bunching" }
-- SQPERF: the sub-scans timed as their own sections (wrap keeps arguments, returns and errors;
-- the callers' pcalls are unchanged).
local scanLineQualityTimed = perf:wrap("lineQuality", scanLineQuality)
local scanMoneyTimed = perf:wrap("econMoney", scanMoney)
local scanUseTimed = perf:wrap("econUse", scanUse)

local MONEY_KINDS <const> : {string : boolean} = { line_unprofitable = true }
local USE_KINDS <const> : {string : boolean} = { line_low_use = true }

local function scanLines(s : ProblemRadarState, now : integer, _pass : integer) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local owned, ownedLive = makeOwnership()
	local tvs = api.engine.system.transportVehicleSystem
	local lines : {integer : ProblemRadarLineInfo} = {}

	-- line_cargo_not_unloaded: vehicles whose cargo made a full round trip without being unloaded
	-- (system.d.tl:215-217; the base cargo_rtc_warning source, notifications.script.tl:277-290, and the
	-- line manager's per-vehicle problem flag, manager_window.tl:6030-6053). One call per lines pass;
	-- each vehicle's line comes from the getLineVehicles lists read below anyway (no extra calls but
	-- one cached PLAYER_OWNED read per affected vehicle). Its own pcall: a failure keeps the other
	-- line alerts.
	local roundTrips : {integer : integer} = nil
	local vehicleLines : {integer : integer} = nil
	if on(s, "line_cargo_not_unloaded") then
		local okRt, rtCounts = pcall(function() : {Engine.Entity : integer}
			return api.engine.system.simEntityAtVehicleSystem.getVehiclesWithRoundTripCount()
		end)
		if okRt then
			roundTrips = {}
			for v, n in pairs((rtCounts or {}) as {Engine.Entity : integer}) do roundTrips[v as integer] = n end
			if next(roundTrips) ~= nil then vehicleLines = {} end
		else
			warnOnce("roundTrips", "getVehiclesWithRoundTripCount failed: " .. tostring(rtCounts))
		end
	end

	-- lineSystem.getLines (system.d.tl:14), not forEachEntityWithComponent: the engine refuses to
	-- iterate LINE ("Cannot loop over this component type"), and the base game never does.
	for __, e in ipairs(api.engine.system.lineSystem.getLines() or {}) do
		if ownedLive(e) then
			local line = api.engine.getComponent(e, api.type.ComponentType.LINE) as Engine.Component.Line
			local vehicles = tvs.getLineVehicles(e)
			if vehicleLines ~= nil and vehicles ~= nil then
				for __, v in ipairs(vehicles) do
					if roundTrips[v] ~= nil and owned(v) then vehicleLines[v] = e end
				end
			end
			lines[e] = {
				name = nameOf(e),
				owned = true,
				stops = line ~= nil and line.stops ~= nil and #line.stops or 0,
				vehicles = vehicles ~= nil and #vehicles or 0,
			}
		else
			lines[e] = { name = "", owned = false, stops = 0, vehicles = 0 }
		end
	end

	-- notifications.script.tl:125-157 (getLineProblems, location from PathProblemLocation)
	local problemNames = enumNames(api.type["enum"].LineProblem as {string : integer}, LINE_PROBLEM_NAMES)
	local problems : {ProblemRadarLineProblem} = {}
	for __, lp in ipairs(api.engine.util.line.getLineProblems() or {}) do
		local loc = lp[3]
		problems[#problems + 1] = {
			line = lp[1],
			code = problemNames[lp[2]],
			pos = loc ~= nil and vec(loc.nodePosition) or nil,
			okModes = loc ~= nil and modeSet(loc.okModes) or nil,
			relaxedModes = loc ~= nil and modeSet(loc.relaxedModes) or nil,
			allowedModes = loc ~= nil and modeSet(loc.allowedModes) or nil,
		}
	end

	-- notifications.script.tl:125,159-174 (getLinesIssues(player, false))
	local issues : {integer : {ProblemRadarLineIssue}} = {}
	for line, list in pairs(api.engine.util.line.getLinesIssues(api.engine.util.getPlayer(), false) or {}) do
		local out : {ProblemRadarLineIssue} = {}
		for __, issue in ipairs(list) do
			local code = lineIssueName(issue.type)
			if code ~= nil then
				out[#out + 1] = { code = code, stop = issue.stopIndex, cargo = cargoName(issue.cargoType) }
			end
		end
		if #out > 0 then issues[line] = out end
	end

	local alerts = radar_checks.lines({ lines = lines, problems = problems, issues = issues,
		roundTrips = roundTrips, vehicleLines = vehicleLines })
	local broken : {integer : boolean} = {}
	for __, a in ipairs(alerts) do
		if a.kind == "line_broken" then broken[a.entity] = true end
	end

	local memory = s.memory or radar_checks.freshMemory()
	local memoryChanged = false
	local wantQuality = false
	for __, k in ipairs(QUALITY_KINDS_LIST) do wantQuality = wantQuality or on(s, k) end
	local wantUse = on(s, "line_low_use")
	-- Phase 5: all three line-quality kinds "off" -> their timers are dropped (so turning a kind back
	-- on starts its sustain time fresh). Phase 7: lines are still measured (light) while line_low_use
	-- needs utilisation samples.
	if not wantQuality then
		memory, memoryChanged = clearTimers(memory, LINE_TIMERS)
	end
	local samples : {integer : number} = nil
	if wantQuality or wantUse then
		-- Phase 4 in its own pcall: a failure there must not lose the Phase 2 line alerts. On failure
		-- the previous line-quality alerts and timers stay as they are (dropped after FAIL_DROP_AFTER
		-- failures in a row); line_low_use gets no samples this pass.
		local ok, quality, qMemory, qChanged, qSamples = pcall(scanLineQualityTimed, s, now, lines, broken, memory, wantQuality)
		if not ok then
			local n = failed("lineQuality")
			warnOnce("lineQuality", "line-quality scan failed: " .. tostring(quality))
			if wantQuality then
				for __, a in ipairs(radar_checks.carryOver(listedAndPending(s), QUALITY_KINDS, n)) do alerts[#alerts + 1] = a end
			end
		else
			succeeded("lineQuality")
			for __, a in ipairs(quality as {ProblemRadarAlert}) do alerts[#alerts + 1] = a end
			memory = qMemory as ProblemRadarMemory
			memoryChanged = memoryChanged or qChanged as boolean
			samples = qSamples as {integer : number}
		end
	end

	-- Phase 7 economy: two sub-scans, each in its own pcall with the Phase 6 isolation (previous rows
	-- carried until FAIL_DROP_AFTER failures in a row). calculateBalance is unproven on the sim thread,
	-- so a failing money scan must not take line_low_use down with it.
	local econ : EconLines = nil
	if on(s, "line_unprofitable") or wantUse then econ = econEligible(lines, broken) end
	-- This Lua state's check times belong to the current rt.econGen; a newer one means the kind was
	-- switched off since (possibly while other Lua states ran the lines passes).
	local gen = rt.econGen or 0
	if econGen ~= gen then
		econCheckedAt = {}
		econNetworkCost, econNetworkAt = nil, nil
		econGen = gen
	end
	if on(s, "line_unprofitable") then
		rt.econOff = nil
		local ok, money = pcall(scanMoneyTimed, s, now, lines, econ)
		if not ok then
			local n = failed("econMoney")
			warnOnce("econMoney", "line money scan failed (calculateBalance): " .. tostring(money))
			for __, a in ipairs(radar_checks.carryOver(listedAndPending(s), MONEY_KINDS, n)) do alerts[#alerts + 1] = a end
		else
			succeeded("econMoney")
			for __, a in ipairs(money as {ProblemRadarAlert}) do alerts[#alerts + 1] = a end
		end
	else
		-- "off" drops its rows at once; forget the check times (in every Lua state: rt.econGen) so
		-- turning it back on re-checks every line at the capped rate instead of a month later.
		econCheckedAt = {}
		econNetworkCost, econNetworkAt = nil, nil
		if rt.econOff ~= true then
			rt.econOff = true
			rt.econGen = gen + 1
			econGen = rt.econGen
		end
	end
	if wantUse then
		local ok, use, uMemory, uChanged = pcall(scanUseTimed, s, now, lines, econ, samples, memory)
		if not ok then
			local n = failed("econUse")
			warnOnce("econUse", "utilisation average scan failed: " .. tostring(use))
			for __, a in ipairs(radar_checks.carryOver(listedAndPending(s), USE_KINDS, n)) do alerts[#alerts + 1] = a end
		else
			succeeded("econUse")
			for __, a in ipairs(use as {ProblemRadarAlert}) do alerts[#alerts + 1] = a end
			memory = uMemory as ProblemRadarMemory
			memoryChanged = memoryChanged or uChanged as boolean
		end
	else
		-- line_low_use "off": no sampling, and its averages are forgotten (saved and live).
		liveUse, liveUseAt = nil, nil
		local dropped : boolean
		memory, dropped = clearTimers(memory, USE_MAPS)
		memoryChanged = memoryChanged or dropped
	end
	return alerts, memory, memoryChanged
end

local function scanStations(s : ProblemRadarState, _now : integer, _pass : integer) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local owned = makeOwnership()
	local groups : {integer : ProblemRadarStationGroupInfo} = {}
	-- notifications.script.tl:588-653: overflow per station group; counts only when a player line
	-- stops there (base walks getLineStopsForTerminal; getLinesForStationGroup gives the same lines).
	-- Phase 5: skipped while station_overcrowded is "off".
	if on(s, "station_overcrowded") then api.engine.forEachEntityWithComponent(function(sg : Engine.Entity)
		local usage = api.engine.util.station.calculateStationGroupCargo(sg, -1)
		if usage ~= nil and usage.overflow then
			local served = false
			for __, line in ipairs(api.engine.system.lineSystem.getLinesForStationGroup(sg) or {}) do
				if owned(line) then
					served = true
					break
				end
			end
			groups[sg] = { name = nameOf(sg), owned = served, overflow = true, used = usage.used, capacity = usage.capacity }
		end
	end, api.type.ComponentType.STATION_GROUP) end

	-- notifications.script.tl:182-193 (getLineStationProblems: line, station group, problem)
	local problemNames = enumNames(api.type["enum"].LineStationProblem as {string : integer}, LINE_STATION_PROBLEM_NAMES)
	local lines : {integer : ProblemRadarLineInfo} = {}
	local problems : {ProblemRadarLineStationProblem} = {}
	-- Phase 5: skipped while station_useless is "off".
	local lsp = on(s, "station_useless") and api.engine.util.line.getLineStationProblems() or nil
	for __, p in ipairs(lsp or {}) do
		local line, sg = p[1], p[2]
		problems[#problems + 1] = { line = line, stationGroup = sg, code = problemNames[intEnum(p[3])] }
		if lines[line] == nil then
			local o = owned(line)
			lines[line] = { name = o and nameOf(line) or "", owned = o, stops = 0, vehicles = 0 }
		end
		if groups[sg] == nil then
			groups[sg] = { name = nameOf(sg), owned = false, overflow = false }
		end
	end

	return radar_checks.stations({ lines = lines, groups = groups, lineStationProblems = problems }), nil, false
end

--- vehicle_util.getVehicleTypeFromEntity (vehicle_util.tl:128-157, used by the base
--- vehicle_warning.sim.script.tl:13) on an already copied TRANSPORT_VEHICLE, so it is not read twice.
local function vehicleTypeOf(tv : Engine.Component.TransportVehicle) : string
	local C = api.type["enum"].Carrier
	local c = tv.carrier
	if c == C.ROAD then
		local modes = tv.config ~= nil and tv.config.transportModes or nil
		if modes ~= nil and modes[api.type["enum"].TransportMode.BUS] then return "Bus" end
		return "Truck"
	elseif c == C.RAIL then
		return "Train"
	elseif c == C.TRAM then
		return "Tram"
	elseif c == C.AIR then
		local parts = tv.transportVehicleConfig ~= nil and tv.transportVehicleConfig.vehicles or nil
		if parts ~= nil and #parts > 0 then
			local model = api.res.modelRep.get(parts[1].part.modelId)
			if model ~= nil and vehicle_util.getVehicleTypeFromModel(model) == "Helicopter" then return "Helicopter" end
		end
		return "Airplane"
	elseif c == C.WATER then
		return "Ship"
	end
	return "Train" -- OTHER becomes train by default (same as the base)
end

local function makeVehicleInfo(owned : function(integer) : boolean, v : integer, tv? : Engine.Component.TransportVehicle) : ProblemRadarVehicleInfo
	local info : ProblemRadarVehicleInfo = { name = "", owned = false, etype = "", line = -1, lineName = "" }
	if not owned(v) then return info end
	tv = tv or getTv(v)
	if tv == nil then return info end
	info.owned = true
	info.name = nameOf(v)
	info.etype = vehicleTypeOf(tv)
	info.line = tv.line or -1
	info.lineName = nameOf(info.line)
	return info
end

--- Vehicles in one TransportVehicleState. transportVehicleSystem.getVehiclesWithState
--- (system.d.tl:384) avoids copying every vehicle's TRANSPORT_VEHICLE component; no base script
--- calls it, so on any failure fall back to the base pattern (forEachEntityWithComponent +
--- tv.state, notifications.script.tl:547-560), which costs one component copy per vehicle; that
--- full pass runs only every FALLBACK_REFRESH calls, in between the cached list (minus vehicles that
--- are gone) is used. A stale member is harmless: the stuck scan re-checks the state before it
--- reports, and the depot scan checks tv.state itself.
local function vehiclesWithState(stateName : string) : {integer}
	local st = (api.type["enum"].TransportVehicleState as {string : TransportVehicleState})[stateName]
	local ok, list = pcall(api.engine.system.transportVehicleSystem.getVehiclesWithState, st)
	if ok and type(list) == "table" then return list as {integer} end
	warnOnce("vehiclesWithState", "getVehiclesWithState unavailable, using the slower fallback: " .. tostring(list))
	local cached = fallbackLists[stateName]
	local age = fallbackAge[stateName] or FALLBACK_REFRESH
	if cached ~= nil and age < FALLBACK_REFRESH then
		fallbackAge[stateName] = age + 1
		local out : {integer} = {}
		for __, v in ipairs(cached) do
			if api.engine.entityExists(v) then out[#out + 1] = v end
		end
		return out
	end
	local out : {integer} = {}
	api.engine.forEachEntityWithComponent(function(v : Engine.Entity)
		local tv = getTv(v)
		if tv ~= nil and tv.state == st then out[#out + 1] = v end
	end, api.type.ComponentType.TRANSPORT_VEHICLE)
	fallbackLists[stateName] = out
	fallbackAge[stateName] = 1
	return out
end

--- Is a standing vehicle queueing at a stop (excluded from veh_stuck)?
--- Land: MOVE_PATH.dyn.approachingStation (engine.d.tl:688). Ships and aircraft move on
--- MOVE_PATH_AIRCRAFT (engine.d.tl:712-790): a ship counts as queueing at a harbour while its
--- shipState.dyn.approachingStation is set or it holds at a waiting distance without clearance
--- (shipState.waitingDist > 0 and not clearToLand); an aircraft while it holds at
--- aircraftState.waitingDistance > 0. No base script reads these fields (semantics from the names
--- and doc comments only; to be verified in game). Only called for vehicles
--- already over their threshold: MOVE_PATH copies the whole path.
local function isQueueing(v : integer, carrier : string) : boolean
	local mp = api.engine.getComponent(v, api.type.ComponentType.MOVE_PATH) as Engine.Component.MovePath
	if mp ~= nil and mp.dyn ~= nil and mp.dyn.approachingStation then return true end
	if carrier ~= "WATER" and carrier ~= "AIR" then return false end
	local mpa = api.engine.getComponent(v, api.type.ComponentType.MOVE_PATH_AIRCRAFT) as Engine.Component.MovePathAircraft
	if mpa == nil then return false end
	if carrier == "WATER" then
		local ss = mpa.shipState
		if ss == nil then return false end
		if ss.dyn ~= nil and ss.dyn.approachingStation then return true end
		return (ss.waitingDist or 0) > 0 and not ss.clearToLand
	end
	local as = mpa.aircraftState
	return as ~= nil and (as.waitingDistance or 0) > 0
end

--- Name of the line stop a vehicle is heading to: line.stops[tv.stopIndex + 1].stationGroup,
--- like the base vehicle window's target (vehicle_eow.script.tl:41-58).
local function nextStopName(tv : Engine.Component.TransportVehicle, lineCache : {integer : Engine.Component.Line}) : string
	local lineId = tv.line
	local idx = tv.stopIndex
	if lineId == nil or lineId < 0 or idx == nil or idx < 0 or not exists(lineId) then return nil end
	local line = lineCache[lineId]
	if line == nil then
		line = api.engine.getComponent(lineId, api.type.ComponentType.LINE) as Engine.Component.Line
		if line == nil then return nil end
		lineCache[lineId] = line
	end
	local stop = line.stops ~= nil and line.stops[idx + 1] or nil
	if stop == nil then return nil end
	local name = nameOf(stop.stationGroup)
	return name ~= "" and name or nil
end

--- Phase 3: veh_stuck + train_blocked_by. Returns the alerts and the new memory (+ whether it changed).
--- Phase 6 cost: the stopped timers run on getVehiclesWithState(EN_ROUTE) + getSpeed alone. Only a
--- vehicle standing at least the smallest stuck threshold gets PLAYER_OWNED + TRANSPORT_VEHICLE read
--- (once: its carrier is cached), and only one past its own carrier's threshold gets the details.
local function scanStuck(s : ProblemRadarState, now : integer, owned : function(integer) : boolean,
		excluded : {integer : boolean}) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local thresholds = radar_settings.stuckThresholdsMs(s.settings)
	local memory = s.memory or radar_checks.freshMemory()
	local EN_ROUTE = api.type["enum"].TransportVehicleState.EN_ROUTE
	-- The saved timers plus the young ones (state.rt.young, shared by every Lua state).
	local persistMs = radar_checks.PERSIST_TIMER_AFTER_MS
	local young = rt.young
	local youngAt = young ~= nil and young.at or nil
	local prevStopped = radar_checks.withYoungTimers(memory.stoppedSince, nil, young ~= nil and young.stopped or nil, nil, youngAt, now, persistMs)
	local prevBlockedSince, prevBlockedBy = radar_checks.withYoungTimers(memory.blockedSince, memory.blockedBy,
		young ~= nil and young.blockedSince or nil, young ~= nil and young.blockedBy or nil, youngAt, now, persistMs)

	-- 1. Every en-route vehicle standing still (a number per vehicle, no component copies), minus
	--    the ones already found ineligible (foreign, user-stopped) and not due for a re-check.
	local standingAll : {integer : boolean} = {}
	local getSpeed = api.engine.util.vehicle.getSpeed
	for __, v in ipairs(vehiclesWithState("EN_ROUTE")) do
		local speed = getSpeed(v)
		if speed ~= nil and speed <= STANDING_SPEED then standingAll[v] = true end
	end
	local ineligible = radar_checks.expireMarks(rt.ineligible, now, INELIGIBLE_RECHECK_MS, standingAll)
	local standing : {integer : boolean} = {}
	for v in pairs(standingAll) do
		if ineligible[v] == nil then standing[v] = true end
	end
	local stoppedSince = radar_checks.updateStopped(prevStopped, standing, now)

	local function drop(v : integer)
		-- base stuck rule: owned, EN_ROUTE and not userStopped (notifications.script.tl:555)
		ineligible[v] = now
		carrierCache[v] = nil
		stoppedSince[v] = nil
	end

	-- 2. Carrier of vehicles past the smallest threshold, read once per vehicle.
	local tvs : {integer : Engine.Component.TransportVehicle} = {}
	local classify = radar_checks.standingDue(stoppedSince, now, carrierCache, thresholds)
	for __, v in ipairs(classify) do
		local tv = owned(v) and getTv(v) or nil
		if tv == nil or tv.userStopped or tv.state ~= EN_ROUTE then
			drop(v)
		else
			carrierCache[v] = carrierName(tv.carrier)
			tvs[v] = tv
		end
	end
	local __, due = radar_checks.standingDue(stoppedSince, now, carrierCache, thresholds)

	-- 3. Blocked train pairs (system.d.tl:403): {blocked, blocker}.
	local pairList : {{integer}} = {}
	for __, p in ipairs(api.engine.system.landVehicleMoveSystem.getBlockedTrains() or {}) do
		pairList[#pairList + 1] = { p[1], p[2] }
	end
	local blockedSince, blockedBy = radar_checks.updateBlocked(prevBlockedSince, prevBlockedBy, pairList, now)

	-- 4. Details only for vehicles over their threshold.
	local vehicles : {integer : ProblemRadarVehicleInfo} = {}
	local standingInfo : {integer : ProblemRadarStandingVehicle} = {}
	local lineCache : {integer : Engine.Component.Line} = {}
	for __, v in ipairs(due) do
		if not excluded[v] and blockedBy[v] == nil then
			local tv = tvs[v] or getTv(v)
			if tv == nil or tv.userStopped or tv.state ~= EN_ROUTE then
				drop(v)
			else
				local carrier = carrierCache[v]
				vehicles[v] = makeVehicleInfo(owned, v, tv)
				local sv : ProblemRadarStandingVehicle = { carrier = carrier }
				sv.queueing = isQueueing(v, carrier)
				if not sv.queueing then
					if carrier == "RAIL" then
						sv.waitingForPath = api.engine.system.landVehicleMoveSystem.isTrainWaitingForFreePath(v) == true
					end
					sv.nextStop = nextStopName(tv, lineCache)
				end
				standingInfo[v] = sv
			end
		end
	end
	local railMs = thresholds.RAIL
	for b, since in pairs(blockedSince) do
		if railMs ~= nil and now - since >= railMs and owned(b) then
			-- the blocked train and every train up its chain (names for the row and its blocker)
			local cur = b
			while cur ~= nil and vehicles[cur] == nil do
				vehicles[cur] = makeVehicleInfo(owned, cur)
				if vehicles[cur].name == "" then vehicles[cur].name = nameOf(cur) end
				cur = blockedBy[cur]
			end
		end
	end

	-- Prune the transient caches to the vehicles still standing.
	local keepCarrier : {integer : string} = {}
	for v in pairs(stoppedSince) do keepCarrier[v] = carrierCache[v] end
	carrierCache = keepCarrier
	rt.ineligible = ineligible

	local alerts = radar_checks.stuck({
		now = now,
		thresholds = thresholds,
		standing = standingInfo,
		stoppedSince = stoppedSince,
		blockedSince = blockedSince,
		blockedBy = blockedBy,
		vehicles = vehicles,
		excluded = excluded,
	})
	-- The young part goes to state.rt.young (rewritten only when it changed; `at` stays with unchanged
	-- maps), the old enough part to state.memory.
	local yStopped = radar_checks.youngTimers(stoppedSince, now, persistMs)
	local ySince, yBy = radar_checks.youngTimers(blockedSince, now, persistMs, blockedBy)
	local yEmpty = next(yStopped) == nil and next(ySince) == nil
	if young == nil then
		if not yEmpty then rt.young = { at = now, stopped = yStopped, blockedSince = ySince, blockedBy = yBy } end
	elseif yEmpty then
		rt.young = nil
	elseif not (radar_checks.sameTimerMap(yStopped, young.stopped) and radar_checks.sameTimerMap(ySince, young.blockedSince)
			and radar_checks.sameTimerMap(yBy, young.blockedBy)) then
		rt.young = { at = now, stopped = yStopped, blockedSince = ySince, blockedBy = yBy }
	end
	local savedStopped = radar_checks.agedTimers(stoppedSince, now, persistMs)
	local savedSince, savedBy = radar_checks.agedTimers(blockedSince, now, persistMs, blockedBy)
	local changed = not (radar_checks.sameTimerMap(savedStopped, memory.stoppedSince)
		and radar_checks.sameTimerMap(savedSince, memory.blockedSince) and radar_checks.sameTimerMap(savedBy, memory.blockedBy))
	-- patchMemory: the line timers (Phase 4) in the same memory stay untouched.
	return alerts, radar_checks.patchMemory(memory, { stoppedSince = savedStopped, blockedSince = savedSince, blockedBy = savedBy }),
		changed
end

--- Kinds off / timers dropped: forget the young timers too, so turning a kind back on starts fresh.
local scanStuckTimed = perf:wrap("stuck", scanStuck)

local function clearLiveTimers()
	rt.young = nil
end

local STUCK_KINDS <const> : {string : boolean} = { veh_stuck = true, train_blocked_by = true }

local function scanVehicles(s : ProblemRadarState, now : integer, _pass : integer) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local owned = makeOwnership()
	local vehicles : {integer : ProblemRadarVehicleInfo} = {}
	local function want(v : integer)
		if vehicles[v] == nil then vehicles[v] = makeVehicleInfo(owned, v) end
	end

	-- notifications.script.tl:262-273 (getVehicleProblems: {vehicles}, problem)
	local problemNames = enumNames(api.type["enum"].VehicleProblem as {string : integer}, VEHICLE_PROBLEM_NAMES)
	local problems : {ProblemRadarVehicleProblem} = {}
	local nopathCandidates : {integer} = {}
	for __, vp in ipairs(api.engine.util.vehicle.getVehicleProblems() or {}) do
		local vs : {integer} = {}
		for __, v in ipairs(vp[1] or {}) do
			vs[#vs + 1] = v
			want(v)
		end
		local code = problemNames[intEnum(vp[2])]
		problems[#problems + 1] = { vehicles = vs, code = code }
		if code ~= "Blocked" then
			for __, v in ipairs(vs) do nopathCandidates[#nopathCandidates + 1] = v end
		end
	end

	-- transportVehicleSystem.getNoPathVehicles (system.d.tl:374)
	local noPath : {integer} = {}
	for __, v in ipairs(api.engine.system.transportVehicleSystem.getNoPathVehicles() or {}) do
		noPath[#noPath + 1] = v
		nopathCandidates[#nopathCandidates + 1] = v
		want(v)
	end

	-- Failure reason (util.d.tl:255; base use manager_window.tl:4707-4719). Reused from the
	-- previous alert when there is one, so each stuck vehicle is looked up once.
	local prev = radar_checks.index(s.alerts)
	local failures : {integer : ProblemRadarPathFailure} = {}
	-- Phase 5: no path searches while veh_nopath is "off" (its alerts are filtered out anyway).
	local budget = on(s, "veh_nopath") and MAX_FAILURE_LOOKUPS or 0
	for __, v in ipairs(nopathCandidates) do
		local info = vehicles[v]
		if failures[v] == nil and info ~= nil and info.owned and info.line >= 0 then
			local old = prev["veh_nopath:" .. tostring(v)]
			if old ~= nil then
				failures[v] = { reason = old.arg, pos = old.pos }
			elseif budget > 0 then
				budget = budget - 1
				local ok, f = pcall(api.engine.util.line.getFailedPathReason, v, info.line)
				local failure = ok and f as Failure or nil
				if failure ~= nil then
					local reason = failureReasonName(failure.reason)
					failures[v] = { reason = reason, pos = reason ~= nil and vec(failure.pos) or nil }
				else
					failures[v] = {}
				end
			end
		end
	end

	local alerts = radar_checks.vehicles({ vehicles = vehicles, problems = problems, noPath = noPath, failures = failures })

	-- Phase 3. Vehicles the game already flags are not listed again as stuck / blocked-by.
	local excluded : {integer : boolean} = {}
	for __, a in ipairs(alerts) do
		excluded[a.entity] = true
		if a.entity2 ~= nil then excluded[a.entity2] = true end
	end
	-- Phase 5: veh_stuck and train_blocked_by both "off" -> no stuck scan; their timers are dropped.
	if not (on(s, "veh_stuck") or on(s, "train_blocked_by")) then
		clearLiveTimers()
		local m, dropped = clearTimers(s.memory, VEHICLE_TIMERS)
		return alerts, m, dropped
	end
	-- Phase 6: the stuck scan in its own pcall (getBlockedTrains / isTrainWaitingForFreePath are
	-- unproven on the sim thread). On failure the Phase 2 vehicle rows above are still delivered and
	-- the previous veh_stuck / train_blocked_by rows and timers stay (dropped after FAIL_DROP_AFTER
	-- failures in a row).
	local ok, stuck, memory, memoryChanged = pcall(scanStuckTimed, s, now, owned, excluded)
	if not ok then
		local n = failed("stuck")
		warnOnce("stuck", "stuck scan failed: " .. tostring(stuck))
		for __, a in ipairs(radar_checks.carryOver(listedAndPending(s), STUCK_KINDS, n)) do alerts[#alerts + 1] = a end
		return alerts, nil, false
	end
	succeeded("stuck")
	for __, a in ipairs(stuck as {ProblemRadarAlert}) do alerts[#alerts + 1] = a end
	return alerts, memory as ProblemRadarMemory, memoryChanged as boolean
end

--- vehicle_util.getLifespan (vehicle_util.tl:31-34), cached per model. pcall: a model without
--- maintenance metadata must not fail the whole fleet scan; it counts as "no lifespan" (0).
local function lifespanOf(modelId : integer) : integer
	local life = lifespanCache[modelId]
	if life == nil then
		local ok, l = pcall(vehicle_util.getLifespan, modelId)
		life = ok and type(l) == "number" and l as integer or 0
		lifespanCache[modelId] = life
	end
	return life
end

--- vehicle_util.getMinPurchaseTimeAndLifespan (vehicle_util.tl:36-52): the oldest part's purchase
--- time and that part's lifespan (ties: the shorter lifespan). nil for a vehicle without parts.
local function purchaseAndLifespan(tv : Engine.Component.TransportVehicle) : integer, integer
	local parts = tv.transportVehicleConfig ~= nil and tv.transportVehicleConfig.vehicles or nil
	if parts == nil or #parts == 0 then return nil, nil end
	local minPurchase = parts[1].purchaseTime
	local minLife = lifespanOf(parts[1].part.modelId)
	for i = 2, #parts do
		local p = parts[i]
		local life = lifespanOf(p.part.modelId)
		if p.purchaseTime < minPurchase or (p.purchaseTime == minPurchase and life < minLife) then
			minPurchase = p.purchaseTime
			minLife = life
		end
	end
	return minPurchase, minLife
end

local function scanFleet(s : ProblemRadarState, now : integer, pass : integer) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	local owned, ownedLive = makeOwnership()
	local prevIds : {string : boolean} = {}
	local oldCandidates : {ProblemRadarAlert} = {}
	local oldCurrent : {integer : integer} = {}
	-- Pending (smoothing) rows count too: worn hysteresis and the kept fleet_old rows apply to them.
	for id, a in pairs(radar_checks.index(listedAndPending(s))) do
		if a.kind == "fleet_worn" then prevIds[id] = true end
		if a.kind == "fleet_old" and type(a.entity) == "number" then
			local e = math.floor(a.entity)
			if owned(e) then
				oldCandidates[#oldCandidates + 1] = a
				oldCurrent[e] = revOf(e)
			end
		end
	end
	-- Kept rows of an id that now belongs to another entity (creation revision changed) are dropped.
	local keepOld, keptRevs = radar_checks.keepSameEntity(oldCandidates, oldRevs, oldCurrent)
	local slice = pass % AGE_SLICES
	local vehicles : {integer : ProblemRadarVehicleInfo} = {}
	-- Phase 5: each part is skipped while its kind is "off".
	local wornOn, oldOn = on(s, "fleet_worn"), on(s, "fleet_old")
	local wornAt, wornClear = radar_settings.wornThresholds(s.settings)
	-- notifications.script.tl:307-320 (owned TRANSPORT_VEHICLEs, getVehicleMaintenanceState)
	if wornOn or oldOn then api.engine.forEachEntityWithComponent(function(v : Engine.Entity)
		-- fleet_old: this pass's slice only (vehicle_util.getAge, vehicle_util.tl:297-315). With
		-- fleet_worn off, vehicles outside the slice need no ownership read at all.
		local inSlice = oldOn and v % AGE_SLICES == slice
		if (wornOn or inSlice) and ownedLive(v) then
			-- One TRANSPORT_VEHICLE copy per vehicle: read once for the slice, shared with the worn info.
			local tv = inSlice and getTv(v) or nil
			local condition = wornOn and api.engine.util.vehicle.getVehicleMaintenanceState(v) or nil
			-- Hysteresis needs the info only for vehicles already listed: no table for the rest.
			if condition ~= nil and (condition <= wornAt or (condition <= wornClear and prevIds["fleet_worn:" .. tostring(v)])) then
				local info = makeVehicleInfo(owned, v, tv)
				info.condition = condition
				vehicles[v] = info
			end
			if tv ~= nil then
				local purchase, life = purchaseAndLifespan(tv)
				if purchase ~= nil then
					local info = vehicles[v] or makeVehicleInfo(owned, v, tv)
					info.ageMs = now - purchase
					info.lifespanMs = life
					vehicles[v] = info
				end
			end
		end
	end, api.type.ComponentType.TRANSPORT_VEHICLE) end

	-- fleet_idle_depot: TRANSPORT_VEHICLE.daysInDepot of vehicles in a depot (engine.d.tl:1512)
	for __, v in ipairs(on(s, "fleet_idle_depot") and vehiclesWithState("IN_DEPOT") or {}) do
		if owned(v) then
			local tv = getTv(v)
			if tv ~= nil and tv.state == api.type["enum"].TransportVehicleState.IN_DEPOT and tv.daysInDepot ~= nil then
				local info = vehicles[v] or makeVehicleInfo(owned, v, tv)
				info.daysInDepot = tv.daysInDepot
				info.depotName = nameOf(tv.depot)
				vehicles[v] = info
			end
		end
	end

	-- Rev 6: game ms per calendar year at the CURRENT calendar speed, so "Age N/L y" reads like the base
	-- vehicle window's Age (formatAge uses the current speed); with a slower calendar the default year
	-- (api/util.d.tl:120) overstated the years. Old/not old compares game ms and is unchanged.
	-- (sim-side use of the api.util durations: base terrain/reforestation.script.tl:25)
	local gsp = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	local yearMs = radar_checks.calendarYearMs(gsp ~= nil and gsp.millisPerDay or 0, api.util.getYearDuration,
		api.util.getDefaultYearDuration())
	local alerts = radar_checks.fleet({
		vehicles = vehicles,
		prevIds = prevIds,
		keepOld = keepOld,
		idleDays = s.settings.idleDepotDays,
		yearMs = yearMs,
		wornThreshold = wornAt,
		wornClear = wornClear,
	})
	-- Remember the revision of every listed fleet_old vehicle (new rows: read now).
	local revs : {integer : integer} = {}
	for __, a in ipairs(alerts) do
		if a.kind == "fleet_old" then revs[a.entity] = keptRevs[a.entity] or revOf(a.entity) end
	end
	oldRevs = revs
	return alerts, nil, false
end

--- (state, gameTime ms, pass number) -> alerts [, new memory, memory changed]
-- SQPERF section per scan group (built once: no string concatenation per call).
local SCAN_SECTION : {string : string} = {}
for __, g in ipairs(radar_checks.GROUPS) do SCAN_SECTION[g] = "scan_" .. g end

local SCANS : {string : function(ProblemRadarState, integer, integer) : {ProblemRadarAlert}, ProblemRadarMemory, boolean} = {
	lines = scanLines,
	stations = scanStations,
	vehicles = scanVehicles,
	fleet = scanFleet,
}

---------------------------------------------------------------------------
-- State + events

--- GUI events only. Pattern: subscribeToNoEvents() first, then re-subscribe.
-- src: .cache/game/base/content/game_mechanics/subventions/subventions.script.tl:375-383
-- API: .cache/game/base/tealdef/scripts/gamescript.d.tl:40-49 (GameScriptState)
local function subscribe(state : GameScriptState<ProblemRadarState>)
	state:subscribeToNoEvents()
	state:subscribeToEvent(EV_SET_SETTING)
	state:subscribeToEvent(EV_RESET_SETTINGS)
	state:subscribeToEvent(EV_SNOOZE)
	state:subscribeToEvent(EV_UNSNOOZE)
	state:subscribeToEvent(EV_RECHECK)
end

--- state:set with the change counter bumped (state.seq): the window's poll compares it and skips the
--- full read while it is unchanged. Wraps well below 2^31. `quiet`: only fields the window does not
--- read changed (memory timers, notify maps, state.rt), so seq stays and the window skips the read.
--- SQPERF: "stateSet" counts every write, "stateSetQuiet" the quiet ones; section "state_set" times them.
local function save(state : GameScriptState<ProblemRadarState>, s : ProblemRadarState, quiet? : boolean)
	if not quiet then s.seq = ((s.seq or 0) + 1) % 1000000000 end
	local t0 = perf:start()
	state:set(s)
	perf:stop("state_set", t0)
	perf:count("stateSet")
	if quiet then perf:count("stateSetQuiet") end
end

-- Subscriptions are saved with the game, so a save from an older build only has the events that
-- build knew (revision 2: no snooze events, so the GUI's snooze clicks were dropped). Re-subscribe
-- once per load; module-local, so every load (and every simulation Lua state) starts false: each
-- state re-subscribes once, which is idempotent.
local subscribedThisLoad = false

local function ensureSubscribed(state : GameScriptState<ProblemRadarState>)
	if subscribedThisLoad and state:hasEventSubscriptions() then return end
	subscribe(state)
	subscribedThisLoad = true
end

--- Make sure state and subscriptions exist. Called lazily from update() and on lifecycle events
--- (initNewGame does NOT fire when the mod is added to an existing save). Map editor: nothing.
--- Older states (v1, Phase 1) are migrated by radar_checks.upgradeState.
local function ensureInitialised(state : GameScriptState<ProblemRadarState>, why : string)
	if isMapEditor() then return end
	ensureSubscribed(state)
	local raw = state:get()
	local s, changed = radar_checks.upgradeState(raw)
	if needsPrime(raw) then
		-- In the state (not a module-local): the scans and the notify step run in other Lua states.
		local r = radar_checks.cleanRuntime(s.rt)
		r.prime = requestPrime(r.prime, nil)
		s.rt = radar_checks.packRuntime(r)
		changed = true
	end
	if changed then
		save(state, s)
		log.message(PREFIX .. "state initialised (" .. why .. ")")
	end
end

--- "key=value" for every setting that differs (log line).
local function settingsDiff(oldS : ProblemRadarSettings, newS : ProblemRadarSettings) : string
	local parts : {string} = {}
	local old = oldS as {string : any}
	local new = newS as {string : any}
	for __, key in ipairs(radar_settings.KEYS) do
		if old[key] ~= new[key] then parts[#parts + 1] = key .. "=" .. tostring(new[key]) end
	end
	for __, kind in ipairs(radar_settings.NOTIFY_KINDS) do
		if oldS.notify[kind] ~= newS.notify[kind] then parts[#parts + 1] = "notify." .. kind .. "=" .. tostring(newS.notify[kind]) end
	end
	return table.concat(parts, ", ")
end

--- "ProblemRadar.setSetting" (radar_settings.apply) and "ProblemRadar.resetSettings"
--- (radar_settings.reset): validated, saved only when something changed.
local function handleSettings(state : GameScriptState<ProblemRadarState>, name : string, param : any)
	if isMapEditor() then return end
	local raw = state:get()
	local s = radar_checks.upgradeState(raw)
	local old = radar_settings.normalize(s.settings)
	local newSettings, changed, rejected : ProblemRadarSettings, boolean, {string}
	if name == EV_RESET_SETTINGS then
		newSettings, changed, rejected = radar_settings.reset(s.settings, param)
	else
		newSettings, changed, rejected = radar_settings.apply(s.settings, param)
	end
	if #rejected > 0 then
		log.warning(PREFIX .. "ignored unknown setting keys/values: " .. table.concat(rejected, ", "))
	end
	if changed then
		-- Phase 6: alerts already listed (or about to be listed) for kinds that just became
		-- "notify" are marked notified silently on the next cycle: no burst of old problems.
		local primed = radar_notify.newlyNotify(old, newSettings)
		if primed ~= nil or needsPrime(raw) then
			local r = radar_checks.cleanRuntime(s.rt)
			-- A settings event before the first scan of a save without the mod: this write makes the
			-- state current, so the priming of the mod being added must be requested here.
			if needsPrime(raw) then r.prime = requestPrime(r.prime, nil) end
			if primed ~= nil then r.prime = requestPrime(r.prime, primed) end
			s.rt = radar_checks.packRuntime(r)
		end
		s.settings = newSettings
		save(state, s)
		log.message(PREFIX .. (name == EV_RESET_SETTINGS and "settings reset: " or "settings: ") .. settingsDiff(old, newSettings))
	end
end

--- Game ms in `months` calendar months at the current calendar speed (GAME_SPEED.millisPerDay, as
--- base scripts/util.tl formatDurationWithCurrentCalenderSpeed); the default month when the calendar
--- is frozen (millisPerDay 0) or unreadable.
local function monthsMs(months : integer) : integer
	local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	local mpd = gs ~= nil and gs.millisPerDay or 0
	local month = mpd ~= nil and mpd > 0 and api.util.getMonthDuration(mpd) or api.util.getDefaultMonthDuration()
	return math.floor(months * month)
end

--- "ProblemRadar.snooze" { id } / "ProblemRadar.unsnooze" { id } or {} (all): radar_checks.snooze /
--- unsnooze, saved only when something changed. Notifications follow on the next notify step.
local function handleSnooze(state : GameScriptState<ProblemRadarState>, name : string, param : any)
	if isMapEditor() then return end
	local p = type(param) == "table" and param as {string : any} or {}
	local id = type(p.id) == "string" and p.id as string or nil
	local s = radar_checks.upgradeState(state:get())
	local new, changed : ProblemRadarState, boolean
	if name == EV_SNOOZE then
		if id == nil then return end
		local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
		if gt == nil then return end
		local months = radar_settings.normalize(s.settings).snoozeMonths
		new, changed = radar_checks.snooze(s, id, gt.gameTime + monthsMs(months))
		if changed then log.message(PREFIX .. "snoozed " .. id .. " for " .. tostring(months) .. " months") end
	else
		new, changed = radar_checks.unsnooze(s, id)
		if changed then log.message(PREFIX .. "unsnoozed " .. (id or "all")) end
	end
	if changed then save(state, new) end
end

--- Raise the notifications decided by radar_notify.step. Base pattern: a Notification table sent
--- as the "Notifications"/"add" scripting event (company_growth.script.tl:100-105; official cosmetic
--- mod: urbangames_campaign_mission_03 tasks/fatal_maintenance/fatal_maintenance.tl:57-66;
--- handler notifications.script.tl:710-718, which only appends to its own notification list).
--- Params are plain data; the entity's creation revision guards the click against a reused id
--- (entity_util.makeEntityAndRevision0 / entityChanged0, as the base types do).
local function sendNotifications(toasts : {ProblemRadarAlert}, more : integer) : boolean
	local function send(params : ProblemRadarNotificationParams)
		local notification : Notification = {
			type = NOTIFY_TYPE,
			params = params as table,
			autoDismissDuration = NOTIFY_DISMISS_MS,
		}
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "add", notification))
	end
	for __, a in ipairs(toasts) do
		local p = radar_notify.params(a)
		if p.entity ~= nil and p.entity >= 0 then
			local er = entity_util.makeEntityAndRevision0(p.entity)
			if er ~= nil then p.entityRev = er.revision.num[1] else p.entity = nil end
		end
		send(p)
	end
	if more > 0 then
		send({ more = more })
	end
	perf:count("toasts", #toasts)
	log.message(PREFIX .. "notified " .. tostring(#toasts) .. (more > 0 and (" +" .. tostring(more) .. " more") or ""))
	return true
end

--- Run one scan group and store the result. state:get() copies the whole state, so it is only
--- called here (once per slot), and state:set() only when the alerts, timers, notify maps, the shared
--- bookkeeping (state.rt) or the state version changed; at most once per slot.
--- `notifyStep`: once per full scan cycle (after the last group), decide the notifications.
local function scanGroupBody(state : GameScriptState<ProblemRadarState>, group : string, now : integer, pass : integer, notifyStep : boolean)
	local scan = SCANS[group]
	if scan == nil then return end
	local tGet = perf:start()
	local raw = state:get()
	perf:stop("state_get", tGet)
	local s, upgraded = radar_checks.upgradeState(raw)
	-- The shared bookkeeping as a working copy for this slot (see `rt` at the top).
	rt = radar_checks.cleanRuntime(s.rt)
	if needsPrime(raw) then rt.prime = requestPrime(rt.prime, nil) end
	-- pcall: an unexpected API shape must never break the game's update loop.
	local ok, result, memory, memoryChanged = pcall(scan, s, now, pass)
	local merged, changed = s, upgraded
	-- What the window shows changed (state.seq): a migration or the alerts / counts / snoozes.
	local visible = upgraded
	-- Smoothing: while priming after the mod was added (prime.all), each group's first scan lists its
	-- alerts at once (no smoothing delay; radar_notify marks them silently).
	local prime = rt.prime
	local instant = prime ~= nil and prime.all and prime.seen[group] ~= true
	if ok then
		succeeded(group)
		if prime ~= nil then prime.seen[group] = true end
		-- Phase 5: "off" kinds are never listed (and never notified).
		local fresh = radar_notify.filterOff(result as {ProblemRadarAlert}, s.settings)
		local alertsChanged : boolean
		merged, alertsChanged = radar_checks.merge(s, group, fresh, now, nil, memory as ProblemRadarMemory, instant)
		changed = changed or alertsChanged or memoryChanged == true
		visible = visible or alertsChanged
	else
		local fails = failed(group)
		warnOnce(group, "scan '" .. group .. "' failed: " .. tostring(result))
		if fails >= radar_checks.FAIL_DROP_AFTER then
			-- Phase 6: the group keeps failing; its rows would be frozen forever, so drop them
			-- (merge with no fresh alerts; timers are kept).
			local alertsChanged : boolean
			merged, alertsChanged = radar_checks.merge(s, group, {}, now)
			changed = changed or alertsChanged
			visible = visible or alertsChanged
			if alertsChanged and not warned["drop:" .. group] then
				warned["drop:" .. group] = true
				log.warning(PREFIX .. "scan '" .. group .. "' failed " .. tostring(fails) .. " times in a row; its alerts were removed")
			end
		end
	end

	local sendToasts : {ProblemRadarAlert} = {}
	local sendMore = 0
	if notifyStep then
		local nr = radar_notify.step({
			now = now,
			settings = merged.settings,
			alerts = merged.alerts,
			notified = merged.notified,
			cleared = merged.notifyCleared,
			silentAll = prime ~= nil and prime.all,
			silentKinds = prime ~= nil and prime.kinds or nil,
			snoozed = merged.snoozed,
		})
		if nr.changed then
			merged.notified = nr.notified
			merged.notifyCleared = nr.cleared
			changed = true
		end
		-- Priming ends once every group has been scanned after it was requested.
		if prime ~= nil then
			local all = true
			for __, g in ipairs(radar_checks.GROUPS) do all = all and prime.seen[g] == true end
			if all then rt.prime = nil end
		end
		-- Game-time budget (radar_notify.applyBudget): the base history holds only 100 entries. Stored
		-- only when it counted something (a toast / summary sent, or the pending count moved); an
		-- unchanged or lapsed window needs no write (applyBudget treats a lapsed one as fresh).
		local oldBudget = rt.budget
		local newBudget : ProblemRadarNotifyBudget
		sendToasts, sendMore, newBudget = radar_notify.applyBudget(oldBudget, now, nr.toasts, nr.more,
			merged.settings ~= nil and merged.settings.notifyPaused == true)
		if #sendToasts > 0 or sendMore > 0 or newBudget.pending ~= (oldBudget ~= nil and oldBudget.pending or 0) then
			rt.budget = newBudget
		end
	end

	-- The shared bookkeeping: written with the rest, or alone when only it changed.
	local packed = radar_checks.packRuntime(rt)
	if not radar_checks.sameRuntime(packed, s.rt) then changed = true end
	merged.rt = packed
	if changed then
		save(state, merged, not visible)
		if upgraded then log.message(PREFIX .. "state initialised (update)") end
	end
	if #sendToasts > 0 or sendMore > 0 then
		-- After state:set: the notified set is stored even if sending fails.
		local sent, err = pcall(sendNotifications, sendToasts, sendMore)
		if not sent then warnOnce("notify", "sending notifications failed: " .. tostring(err)) end
	end
end

--- scanGroupBody timed as SQPERF section "scan_<group>" (state:get, the scan, merge, state:set,
--- notifications). An error passes through to doUpdate's pcall unchanged (that call is not timed).
local function scanGroup(state : GameScriptState<ProblemRadarState>, group : string, now : integer, pass : integer, notifyStep : boolean)
	local section = SCAN_SECTION[group]
	if section == nil then
		scanGroupBody(state, group, now, pass, notifyStep)
		return
	end
	local t0 = perf:start()
	scanGroupBody(state, group, now, pass, notifyStep)
	perf:stop(section, t0)
end

--- update body (see script.update).
local function doUpdate(state : GameScriptState<ProblemRadarState>, dt : number) : any
	-- Lazy init, so the mod is safe to add to an existing save: no lifecycle event reaches us
	-- then. Subscribe from update when not yet subscribed
	-- (src: .cache/game/base/content/industries/industry_workers.script.tl:19-21); the state
	-- itself is built/migrated by the first scan slot (scanGroup → upgradeState).
	if isMapEditor() then return end
	if not subscribedThisLoad or not state:hasEventSubscriptions() then
		ensureInitialised(state, "update")
	end

	-- Slice by tick like the base (notifications.script.tl:45-49): updateCount while running,
	-- tickCount while paused (dt == 0).
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	if gt == nil then return end
	local paused = dt == 0.0
	local tick = paused and gt.tickCount or gt.updateCount
	local spacing = paused and PAUSED_SLOT_SPACING or SLOT_SPACING
	if tick == nil or tick % spacing ~= 0 then return end
	local slot = (tick // spacing) % #radar_checks.GROUPS + 1
	scanGroup(state, radar_checks.GROUPS[slot], gt.gameTime, tick // spacing // #radar_checks.GROUPS,
		slot == #radar_checks.GROUPS)
end

--- "ProblemRadar.recheckVehicles" { vehicles }: the GUI sends it when the game's Replace Vehicles window
--- (opened from the fleet window) closes, and once more a few seconds later in case the replace command
--- had not applied yet. Each vehicle is read like scanFleet does (purchaseAndLifespan, the maintenance
--- state); the fleet rows that no longer hold are dropped at once instead of lingering until the
--- vehicle's age slice comes round. Capped at MAX_RECHECK vehicles per event; saved only on a change.
local MAX_RECHECK <const> = 500

local function handleRecheck(state : GameScriptState<ProblemRadarState>, param : any)
	if isMapEditor() then return end
	local p = type(param) == "table" and param as {string : any} or {}
	local list = type(p.vehicles) == "table" and p.vehicles as {any} or {}
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	if gt == nil then return end
	local s = radar_checks.upgradeState(state:get())
	local __, wornClear = radar_settings.wornThresholds(s.settings)
	local ids : {string : boolean} = {}
	for i, raw in ipairs(list) do
		if i > MAX_RECHECK then break end
		local v = type(raw) == "number" and math.floor(raw as number) or nil
		if v ~= nil then
			local info : ProblemRadarFleetRecheck = { exists = exists(v) }
			if info.exists then
				local tv = getTv(v)
				if tv ~= nil then
					local purchase, life = purchaseAndLifespan(tv)
					if purchase ~= nil then info.ageMs, info.lifespanMs = gt.gameTime - purchase, life end
				end
				info.condition = api.engine.util.vehicle.getVehicleMaintenanceState(v)
			end
			for __, id in ipairs(radar_checks.fleetCleared(v, info, wornClear)) do ids[id] = true end
		end
	end
	local new, changed = radar_checks.dropAlerts(s, ids)
	if changed then
		save(state, new)
		log.message(PREFIX .. "fleet recheck: dropped rows of replaced vehicles")
	end
end

--- handleEvent body (see script.handleEvent).
local function doHandleEvent(state : GameScriptState<ProblemRadarState>, id : string, name : string, param : any) : any
	if id == "" then
		-- Engine lifecycle events. initNewGame / handleLegacy (loaded save):
		-- .cache/game/base/content/game_mechanics/finance/loan.script.tl:121,
		-- company/company.script.tl:378-392.
		if name == "initNewGame" or name == "initNewGameFromMap" or name == "handleLegacy" then
			ensureInitialised(state, name)
		end
		return
	end
	if id == EVENT_ID and (name == EV_SET_SETTING or name == EV_RESET_SETTINGS) then
		-- Sent by the GUI: api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", name, param)
		-- (.cache/game/api/tealdef/api/cmd.d.tl:788; GUI usage subventions_gui.tl:135)
		handleSettings(state, name, param)
	elseif id == EVENT_ID and (name == EV_SNOOZE or name == EV_UNSNOOZE) then
		handleSnooze(state, name, param)
	elseif id == EVENT_ID and name == EV_RECHECK then
		handleRecheck(state, param)
	end
end

-- Both entry points run their body in one pcall: an error in this script is logged once and never
-- propagates into the engine's update / event handling (or a save in progress).
-- SQPERF times each whole entry point ("update" includes the scan_<group> sections inside it).
local script : GameScript<ProblemRadarState> = {
	update = function(_userParams : table, state : GameScriptState<ProblemRadarState>, dt : number) : any
		local t0 = perf:start()
		local ok, err = pcall(doUpdate, state, dt)
		perf:stop("update", t0)
		if not ok then warnOnce("update", "update failed: " .. tostring(err)) end
	end,

	handleEvent = function(_userParams : table, state : GameScriptState<ProblemRadarState>, _src : string, id : string, name : string, param : any) : any
		local t0 = perf:start()
		local ok, err = pcall(doHandleEvent, state, id, name, param)
		perf:stop("event", t0)
		if not ok then warnOnce("handleEvent", "event '" .. tostring(name) .. "' failed: " .. tostring(err)) end
	end,
}

perf:phase("init", perfInit)

return script
