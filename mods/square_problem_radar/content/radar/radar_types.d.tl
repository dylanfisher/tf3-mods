recordDef = true

-- Problem Radar shared contract: every record the engine script, the pure modules and the GUI share.
-- Loaded as module "radar.radar_types" (every content/**/*.d.tl; tools/tealrt.py def_modules).
-- tealdef/radar/radar_types.d.tl is a byte-for-byte editor copy (make check flags drift).
-- Every global name is prefixed ProblemRadar (globals are shared by all loaded mods).

--- One problem, written by the engine script into state.alerts (Phase 2+).
--- Language-neutral: the engine stores codes and entity names; the GUI model
--- (radar_hud_model.tl) turns kind/code/arg into translated text.
--- Integer fields may come back as floats after save/load: floor before comparing.
global record ProblemRadarAlert
	id : string            -- unique and stable while the problem lasts, e.g. "veh_nopath:12345"
	kind : string          -- catalogue id (PLAN "Alert catalogue"), e.g. "veh_blocked", "line_broken"
	tab : string           -- "vehicles" | "lines" | "stations" | "fleet" | "economy" (Phase 7)
	tier : integer         -- 1 = critical, 2 = warning, 3 = info (Phase 7 economy kinds: per row, by size)
	entity : integer       -- primary entity (row click focuses + selects it)
	entity2 : integer      -- optional secondary entity (the other blocked train, the line of a stop); nil if none
	etype : string         -- entity type: "Train" | "Tram" | "Bus" | "Truck" | "Ship" | "Airplane" | "Helicopter" | "Line" | "Station" | ""
	label : string         -- entity name (untranslated game name), "" if unknown
	context : string       -- related name (a vehicle's line, a stop's line), "" if none
	code : string          -- problem code, e.g. "NO_PATH", "NoPathElectric", "Blocked", "NowhereToLoad"
	arg : string           -- optional detail argument (failure reason, relaxation, other train, cargo, stop count); nil if none
	metric : string        -- optional language-neutral metric ("18%", "412/300", "+2"); nil if none
	firstSeen : integer    -- GAME_TIME.gameTime (ms) when the alert was first listed (smoothing: when it
	                       -- became shown, not first detected); in state.pending: when first detected
	pos : {number}         -- optional {x, y, z}: focus this position instead of the entity
	-- Smoothing (settings.smoothSec, radar_checks.merge). Optional; older saves have neither.
	missedAt : integer     -- gameTime (ms) of the first scan that no longer detected it (a listed row
	                       -- lingering, or a pending entry); nil while detected
	carried : boolean      -- transient: set on a row a scan kept without re-checking it (line-quality
	                       -- keep, fleet_old keepOld, carryOver); merge removes it, never saved
end

--- Catalogue entry per alert kind (radar_checks.KINDS).
global record ProblemRadarKindInfo
	tab : string
	tier : integer
	group : string         -- scan group that produces it (radar_checks.GROUPS)
	maxTier : integer      -- Phase 7: kinds whose tier scales with the problem's size (line_unprofitable,
	                       -- line_low_use) carry their most severe tier here; `tier` is then the mildest
	                       -- (used for counts over the stored cap). nil = fixed tier.
end

--- Per-savegame settings (PLAN "Settings": in-window Settings tab, saved per savegame).
--- Schema and validation: radar_settings.tl (ALLOWED strings, NUMBERS ranges).
global record ProblemRadarSettings
	hudMode : string       -- "badge" (default) | "compact"
	-- veh_stuck thresholds per carrier, in game-time minutes (Phase 3)
	stuckMinRoad : integer -- default 3
	stuckMinTram : integer -- default 3
	stuckMinRail : integer -- default 5 (also the train_blocked_by threshold)
	stuckMinWater : integer -- default 10
	stuckMinAir : integer  -- default 5
	idleDepotDays : integer -- fleet_idle_depot when daysInDepot >= this (default 30)
	-- Phase 4 line quality (radar_settings.NUMBERS has the ranges)
	lineOverloadFactor : integer -- line_overloaded: waiting >= this x capacity per trip (default 3)
	lineUnderusedPct : integer   -- line_underused: utilisation below this % (default 10)
	lineClumpPct : integer       -- line_bunching: headway below this % of the target interval (default 20)
	lineGapPct : integer         -- line_bunching: gap above this % of the target interval (default 300)
	lineSustainMin : integer     -- line conditions must hold this many game-time minutes (default 10)
	-- Phase 5
	wornPct : integer            -- fleet_worn at condition <= this % (default 20 = base 0.2); clears above +10 points
	notifyPaused : boolean       -- true: no radar notifications at all (alerts still listed)
	notify : {string : string}   -- alert kind -> "off" | "passive" | "notify" (radar_settings.NOTIFY_DEFAULTS)
	-- Smoothing for every kind (radar_checks.merge): game seconds a problem must be detected before it
	-- is listed, and missing before a listed one clears (default 30, 0 = off)
	smoothSec : integer
	-- Phase 7 economy (radar_settings.NUMBERS has the ranges)
	econLossWarnPct : integer    -- line_unprofitable is a Warning when income covers less than this % of its running costs (default 75)
	econLossCritPct : integer    -- ... and Critical below this % (default 50)
	econLossSharePct : integer   -- a "big" loss is at least this % of all lines' vehicle costs, 3x = very big (default 2)
	econLowUsePct : integer      -- line_low_use: yearly average utilisation below this % (default 20; Warning below half, Critical below a quarter)
	-- Snooze: game months a row's snooze button mutes its alert for (default 6)
	snoozeMonths : integer
end

--- One integer setting's schema entry (radar_settings.NUMBERS), for validation and phase 5's Settings tab.
global record ProblemRadarNumberSetting
	default : integer
	min : integer
	max : integer
	unit : string          -- "min" (game-time minutes) | "days" (calendar days) | "%" | "x" (factor) | "s" (game seconds)
end

--- Timers that must survive save/load (Phase 3). Plain entity-id-keyed integer maps, like the base
--- notifications state's vehicle2problem (notifications.script.tl:539-573). Pruned every vehicles
--- scan (only vehicles that are still standing / still blocked stay) and capped
--- (radar_checks.MAX_STOPPED_TIMERS / MAX_BLOCKED_TIMERS). Values may come back as floats.
global record ProblemRadarMemory
	stoppedSince : {integer : integer}  -- vehicle -> GAME_TIME.gameTime (ms) since it stands en route
	blockedSince : {integer : integer}  -- blocked train -> gameTime (ms) since its current blocker blocks it
	blockedBy : {integer : integer}     -- blocked train -> that blocker (getBlockedTrains pair)
	-- v4 (Phase 4): line -> gameTime (ms) since its line-quality condition holds. Pruned for lines
	-- that are gone / not owned / excluded and for scanned lines whose condition cleared; capped
	-- at radar_checks.MAX_LINE_TIMERS each.
	overloadSince : {integer : integer}
	underusedSince : {integer : integer}
	bunchingSince : {integer : integer}
	-- v5: the rotating line cursor (v4 lineCursor) is no longer in memory (since PERF_VMS: state.rt).
	-- v6 (Phase 7, line_low_use): line -> { average utilisation in basis points (0..10000), gameTime
	-- (ms) tracking started, gameTime (ms) of the last sample }. The shared copy of the engine's
	-- averages: rewritten on every lines pass that took a sample (all entries together), so the next
	-- pass, in whichever simulation Lua state, continues from it (PERF_VMS). Capped at
	-- radar_checks.MAX_USE_TRACKED.
	useAvg : {integer : {integer}}
end

--- One snoozed alert (state.snoozed[id]): muted until untilMs, with enough of the alert to list it
--- in the Snoozed tab while the problem is not detected.
global record ProblemRadarSnooze
	untilMs : integer      -- gameTime (ms) the snooze ends
	kind : string
	label : string
	etype : string
	context : string
	entity : integer       -- nil if none
end

--- The whole game-script state, stored via GameScriptState:set.
global record ProblemRadarState
	version : integer                -- schema version, 6 (5 = Phase 5/6: no useAvg / tierCounts; 4 = Phase 4: lineCursor in memory, no notify maps; 3 = Phase 3: no line timers; 2 = Phase 2: no memory; 1 = Phase 1: no total/kindCounts, alerts always empty)
	settings : ProblemRadarSettings
	alerts : {ProblemRadarAlert}     -- at most radar_checks.MAX_STORED_ALERTS, sorted tier, firstSeen, id
	total : integer                  -- every current alert, including the ones over the cap
	kindCounts : {string : integer}  -- current alerts per kind (including the ones over the cap); 0 counts omitted
	memory : ProblemRadarMemory      -- v3: stuck / blocked timers; v4: + line-quality timers
	-- v5 (Phase 5, radar_notify.tl): alert id -> gameTime (ms). notified: listed ids already
	-- notified (or silently marked); notifyCleared: notified ids that cleared, while their cooldown runs.
	notified : {string : integer}
	notifyCleared : {string : integer}
	-- Smoothing (optional, still v5: nil in older saves and whenever nothing is pending): alerts
	-- detected but not listed yet (not counted, not shown, not notified), firstSeen = first
	-- detection, missedAt while undetected. At most radar_checks.MAX_PENDING_ALERTS, oldest first.
	pending : {ProblemRadarAlert}
	-- v6 (Phase 7): current alerts per tier [1] critical, [2] warning, [3] info (stored rows by their own
	-- tier, rows over the stored cap by their kind's tier), so the ridge HUD needs no alert rows even
	-- though the economy kinds' tier varies per row. Kept by radar_checks.merge / upgradeState.
	tierCounts : {integer}
	-- Snooze (optional, still v6: nil in older saves and whenever nothing is snoozed): alert id ->
	-- snooze. A snoozed alert is still detected and stored in `alerts`, but left out of total,
	-- kindCounts and tierCounts, and never notified. Expired entries are dropped by radar_checks.merge
	-- (for its group's kinds). At most radar_checks.MAX_SNOOZED.
	snoozed : {string : ProblemRadarSnooze}
	-- Change counter (optional, still v6): +1 on every state:set that changes what the window shows
	-- (alerts, counts, snoozes, settings; radar.script.tl save), so the window's poll reads one number
	-- and skips the full read while nothing changed. nil in older saves.
	seq : integer
	-- Shared engine bookkeeping (optional, still v6: nil in older saves and whenever all of it is empty;
	-- radar_checks.cleanRuntime / packRuntime). The game script runs in ~14 simulation Lua states and
	-- each tick goes to any one of them (plans/square_problem_radar/PERF_VMS.md), so values that must
	-- carry from one scan to the next live here, not in module-local variables. Never shown.
	rt : ProblemRadarRuntime
end

-- ======================================================================
-- Scan inputs: plain tables the engine script's gather layer builds from the API
-- (radar.script.tl), so radar_checks.tl stays pure and unit-tested.
-- Entity-keyed maps use the entity id as an integer key.

global record ProblemRadarLineInfo
	name : string
	owned : boolean        -- PLAYER_OWNED.player == api.engine.util.getPlayer()
	stops : integer        -- #LINE.stops
	vehicles : integer     -- #transportVehicleSystem.getLineVehicles(line)
end

global record ProblemRadarLineProblem
	line : integer
	code : string                     -- LineProblem name: "NO_PATH", "ZERO_OR_ONE_STATION", ... ("NOTHING" is ignored)
	pos : {number}                    -- PathProblemLocation.nodePosition {x, y, z}, or nil
	okModes : {string : boolean}      -- TransportMode names, e.g. { ELECTRIC_TRAIN = true }; nil if no location
	relaxedModes : {string : boolean}
	allowedModes : {string : boolean}
end

global record ProblemRadarLineIssue
	code : string          -- LineIssue.Type name: "NowhereToLoad", "NowhereToUnload", "NoVehicleToLoadCargo", "VehicleUseless", "LineCargoConfig"
	stop : integer         -- 0-based stop index (-1 if none)
	cargo : string         -- cargo type name, or nil
end

global record ProblemRadarLinesInput
	lines : {integer : ProblemRadarLineInfo}            -- every line (ownership decides)
	problems : {ProblemRadarLineProblem}               -- getLineProblems()
	issues : {integer : {ProblemRadarLineIssue}}       -- getLinesIssues(player, false)
	-- line_cargo_not_unloaded (nil when that kind is off):
	roundTrips : {integer : integer}                   -- vehicle -> cargo count, simEntityAtVehicleSystem.getVehiclesWithRoundTripCount()
	vehicleLines : {integer : integer}                 -- vehicle -> line, for owned vehicles of owned lines (getLineVehicles)
end

global record ProblemRadarStationGroupInfo
	name : string
	owned : boolean        -- a player line serves it (base overcrowding rule)
	overflow : boolean     -- calculateStationGroupCargo(sg, -1).overflow
	used : integer
	capacity : integer
end

global record ProblemRadarLineStationProblem
	line : integer
	stationGroup : integer
	code : string          -- LineStationProblem name: "StopUseless", "CargoTypeLoadUseless", ...
end

global record ProblemRadarStationsInput
	lines : {integer : ProblemRadarLineInfo}            -- name + owned of the lines referenced
	groups : {integer : ProblemRadarStationGroupInfo}   -- overflowing groups + groups referenced by problems
	lineStationProblems : {ProblemRadarLineStationProblem}
end

global record ProblemRadarVehicleInfo
	name : string
	owned : boolean
	etype : string         -- vehicle_util.getVehicleTypeFromEntity ("Train", "Bus", ...)
	line : integer         -- TRANSPORT_VEHICLE.line, -1 if none
	lineName : string      -- "" if none
	condition : number     -- getVehicleMaintenanceState (0..1); fleet scan only, nil if not a worn candidate
	ageMs : integer        -- fleet: gameTime - min part purchaseTime (vehicle_util.getAge); nil if not read this pass
	lifespanMs : integer   -- fleet: lifespan of that part (vehicle_util.getLifespan, ms); nil if not read
	daysInDepot : integer  -- fleet: TRANSPORT_VEHICLE.daysInDepot of an IN_DEPOT vehicle; nil otherwise
	depotName : string     -- fleet: name of that depot, "" if unknown
end

global record ProblemRadarVehicleProblem
	vehicles : {integer}
	code : string          -- VehicleProblem name: "Blocked", "NoPathElectric", "NoPathShip", "NoPathAircraft", "NoPathGeneric"
end

global record ProblemRadarPathFailure
	reason : string        -- Failure.Reason name ("NoElectric", ...); nil when unknown / generic
	pos : {number}         -- Failure.pos {x, y, z}, or nil
end

global record ProblemRadarVehiclesInput
	vehicles : {integer : ProblemRadarVehicleInfo}       -- every vehicle referenced below
	problems : {ProblemRadarVehicleProblem}             -- getVehicleProblems()
	noPath : {integer}                                  -- transportVehicleSystem.getNoPathVehicles()
	failures : {integer : ProblemRadarPathFailure}      -- getFailedPathReason, where looked up
end

--- One owned vehicle standing still en route (Phase 3, veh_stuck / train_blocked_by).
--- Every field but carrier is filled only once the vehicle is over its threshold (they cost API calls).
global record ProblemRadarStandingVehicle
	carrier : string       -- Carrier name: "ROAD" | "TRAM" | "RAIL" | "WATER" | "AIR" | "OTHER"
	queueing : boolean     -- approaching / queueing at a station, harbour or runway (excluded)
	waitingForPath : boolean -- rail: landVehicleMoveSystem.isTrainWaitingForFreePath
	nextStop : string      -- name of the line stop it is heading to; nil if unknown
end

global record ProblemRadarStuckInput
	now : integer                                       -- GAME_TIME.gameTime (ms)
	thresholds : {string : integer}                     -- carrier name -> ms (radar_settings.stuckThresholdsMs)
	standing : {integer : ProblemRadarStandingVehicle}  -- owned, EN_ROUTE, not userStopped, speed ~ 0
	stoppedSince : {integer : integer}                  -- memory after updateStopped
	blockedSince : {integer : integer}                  -- memory after updateBlocked
	blockedBy : {integer : integer}
	vehicles : {integer : ProblemRadarVehicleInfo}       -- over-threshold vehicles + every train of a reported chain
	excluded : {integer : boolean}                      -- already in veh_blocked / veh_nopath
end

--- One (line stop, cargo type) with people/cargo waiting (Phase 4, line_overloaded).
global record ProblemRadarStopLoad
	stop : integer         -- 0-based line stop index
	name : string          -- station group name; filled only when waiting >= radar_checks.MIN_OVERLOAD_WAITING
	waiting : integer      -- simEntityAtTerminalSystem.getLineStopSimEntitiesCount(line, stop, cargo)
	perTrip : number       -- capacity of one vehicle for that cargo: getLineCapacityUsages(line,false)[c].capacity / #vehicles
end

--- One line measured by the rotating line-quality scan (Phase 4).
global record ProblemRadarLineQuality
	name : string
	vehicles : integer     -- running vehicles (EN_ROUTE / AT_TERMINAL) of the line
	used : number          -- sum of getLineCapacityUsages(line, false)[*].used (cargo on board now)
	capacity : number      -- sum of [*].capacity (base "Utilization" = used / capacity)
	stops : {ProblemRadarStopLoad}   -- stop/cargo pairs with waiting > 0
	intervalMs : integer   -- target headway in game ms: 1000 / getMaxFrequency (base calculateFrequencySeconds); 0 = unknown
	fullLoad : boolean     -- a stop uses a full-load mode (departures follow demand: no bunching check)
	departures : {{integer}}  -- per running vehicle: TRANSPORT_VEHICLE.lineStopDepartures (gameTime ms per stop)
end

--- Result of radar_checks.headways for one line.
global record ProblemRadarHeadways
	stopsUsed : integer    -- stops with a valid departure of every vehicle
	minGapMs : integer     -- median over those stops of the smallest headway
	maxGapMs : integer     -- median of the largest headway (the gap still open since the last departure included)
	clump : integer        -- vehicles in the largest clump at the median stop (consecutive headways < clumpMs)
	clumpSpanMs : integer  -- first to last departure of that clump
end

global record ProblemRadarLineQualityInput
	now : integer
	settings : ProblemRadarSettings
	lines : {integer : ProblemRadarLineQuality}   -- lines measured this pass
	eligible : {integer : boolean}                -- every owned line that may carry these alerts (not broken, has vehicles)
	keep : {ProblemRadarAlert}                    -- previous line-quality alerts (kept for eligible lines not measured)
	memory : ProblemRadarMemory                   -- previous timers
end

-- Phase 7 economy ----------------------------------------------------------------------------

--- One line's money over the trailing year (radar.script.tl measureMoney), all from
--- api.engine.util.finance.calculateBalance({line}, from, to, true[, maintenanceType]): game money as
--- integers, negative = money lost.
global record ProblemRadarLineMoney
	year : integer         -- balance of the last 12 months (the base line window's "Balance")
	quarters : {integer}   -- the same year split into 4 windows, oldest first (radar_checks.lineMoney
	                       -- leaves out those that can't change the verdict)
	vehicleCost : integer  -- balance of JournalEntry.Maintenance.VEHICLE (running costs, <= 0); nil if unknown
	maintCost : integer    -- balance of JournalEntry.Maintenance.VEHICLE_MAINTENANCE (<= 0); nil if unknown
end

--- radar_checks.judgeLoss result for a line that loses money consistently.
global record ProblemRadarLoss
	tier : integer         -- 3 / 2 / 1 by coverage + size points (radar_checks.judgeLoss)
	balance : integer      -- the 12-month balance (< 0)
	negQuarters : integer  -- quarters with a negative balance (>= radar_checks.ECON_MIN_NEG_QUARTERS)
	coveragePct : number   -- income / costs x 100; nil when the cost split is unknown
	sharePct : number      -- loss / all lines' vehicle costs x 100; nil when those costs are unknown
end

global record ProblemRadarUnprofitableInput
	settings : ProblemRadarSettings
	lines : {integer : ProblemRadarLineInfo}      -- every line (name, owned)
	money : {integer : ProblemRadarLineMoney}     -- lines checked this pass (rotating cursor)
	eligible : {integer : boolean}                -- owned lines with >= 1 vehicle
	keep : {ProblemRadarAlert}                    -- previous line_unprofitable rows (kept for eligible lines not checked)
	networkCost : integer                         -- all eligible lines' yearly vehicle costs (> 0), nil if unknown
end

--- Live utilisation average of one line (line_low_use; a per-Lua-state float cache). Saved as
--- ProblemRadarMemory.useAvg { basis points, start, last }.
global record ProblemRadarUseAvg
	avg : number           -- 0..1, time-weighted, exponentially decayed (time constant 1 game year)
	start : integer        -- gameTime (ms) tracking started (first sample)
	last : integer         -- gameTime (ms) of the last sample
end

global record ProblemRadarLowUseInput
	now : integer
	yearMs : integer                              -- api.util.getDefaultYearDuration()
	settings : ProblemRadarSettings
	lines : {integer : ProblemRadarLineInfo}
	eligible : {integer : boolean}                -- owned, >= 2 stops, >= 1 vehicle, not broken (the line-quality rule)
	useAvg : {integer : ProblemRadarUseAvg}       -- the live averages
end

global record ProblemRadarFleetInput
	vehicles : {integer : ProblemRadarVehicleInfo}       -- worn candidates (condition <= WORN_CLEAR_THRESHOLD),
	                                                    -- vehicles whose age was read (ageMs), IN_DEPOT ones (daysInDepot)
	prevIds : {string : boolean}                        -- alert ids of the previous state (hysteresis)
	keepOld : {ProblemRadarAlert}                       -- previous fleet_old alerts of owned vehicles not read this pass
	idleDays : integer                                  -- settings.idleDepotDays
	yearMs : integer                                    -- game ms per year (api.util.getDefaultYearDuration)
	wornThreshold : number                              -- fleet_worn at condition <= this (settings.wornPct / 100; nil: WORN_THRESHOLD)
	wornClear : number                                  -- an existing fleet_worn stays while <= this (nil: WORN_CLEAR_THRESHOLD)
end

-- ======================================================================
-- from radar_checks.tl (pure checks + state merge; unit-tested)
-- Module: ug_require "square_problem_radar::/radar/radar_checks.tl" as ProblemRadarChecks
global record ProblemRadarChecks
	STATE_VERSION : integer
	MAX_STORED_ALERTS : integer         -- cap on state.alerts (save size)
	WORN_THRESHOLD : number             -- default fleet_worn threshold (base: 0.2; Phase 5: settings.wornPct)
	WORN_CLEAR_THRESHOLD : number       -- default: an existing fleet_worn alert stays until condition > this (base: 0.3)
	MAX_STOPPED_TIMERS : integer        -- cap on memory.stoppedSince (save size)
	MAX_BLOCKED_TIMERS : integer        -- cap on memory.blockedSince / blockedBy
	MAX_LINE_TIMERS : integer           -- cap on each memory.*Since line map (Phase 4)
	MAX_PENDING_ALERTS : integer        -- cap on state.pending (smoothing)
	MIN_OVERLOAD_WAITING : integer      -- line_overloaded needs at least this many waiting at the stop
	HOLD_FRACTION : number              -- hysteresis: a running timer holds while the value is within this fraction of the threshold
	KINDS : {string : ProblemRadarKindInfo}
	-- Phase 7 economy
	ECON_MIN_NEG_QUARTERS : integer     -- line_unprofitable needs at least this many of the 4 quarters negative
	ECON_RECHECKS_PER_YEAR : integer    -- line_unprofitable re-checks a line's money at most this often per game year
	MAX_USE_TRACKED : integer           -- cap on memory.useAvg (lines; the longest tracked kept)
	USE_MIN_TRACK_FRACTION : number     -- line_low_use judges a line once tracked this fraction of a game year
	GROUPS : {string}                   -- scan groups in slot order: "lines", "stations", "vehicles", "fleet"
	GROUP_KINDS : {string : {string}}

	freshState : function() : ProblemRadarState
	freshMemory : function() : ProblemRadarMemory
	--- A valid current-version state from whatever the save holds (nil, v1, partial).
	--- Returns the state and whether it differs from the input (so it must be saved).
	upgradeState : function(s : any) : ProblemRadarState, boolean

	--- Relaxation of a path problem (base line_util.getRelaxationType, on mode-name sets):
	--- "Catenary" | "TramLanes" | "TramTrack" | "Train" | "Road" | nil
	relaxationType : function(ok : {string : boolean}, relaxed : {string : boolean}, allowed : {string : boolean}) : string

	lines : function(input : ProblemRadarLinesInput) : {ProblemRadarAlert}
	stations : function(input : ProblemRadarStationsInput) : {ProblemRadarAlert}
	vehicles : function(input : ProblemRadarVehiclesInput) : {ProblemRadarAlert}
	fleet : function(input : ProblemRadarFleetInput) : {ProblemRadarAlert}
	--- veh_stuck + train_blocked_by (Phase 3).
	stuck : function(input : ProblemRadarStuckInput) : {ProblemRadarAlert}
	--- line_overloaded, line_underused, line_bunching (Phase 4). Returns the alerts and the new
	--- memory (a copy of input.memory with the three line timer maps replaced) and whether they changed.
	lineQuality : function(input : ProblemRadarLineQualityInput) : {ProblemRadarAlert}, ProblemRadarMemory, boolean
	--- Headway statistics from per-vehicle stop departures (pure, see PLAN Phase 4). nil when no
	--- stop has a recent departure of every vehicle.
	headways : function(departures : {{integer}}, now : integer, intervalMs : integer, clumpMs : integer) : ProblemRadarHeadways
	--- Line ids in scan order for the rotating cursor: ids after `cursor` ascending, then the rest (wrap).
	--- The cursor is state.rt.lineCursor (shared by the simulation Lua states; not in memory since v5).
	lineRotation : function(ids : {integer}, cursor : integer) : {integer}
	--- Phase 7 (perf review): the lines to check this pass, in lineRotation order: those never checked
	--- (no checkedAt entry), checked at a later game time (a load), or at least `everyMs` ago; lines in
	--- `soon` already after `soonMs` (a pending row, so it can mature). At most `max`.
	dueRotation : function(ids : {integer}, cursor : integer, checkedAt : {integer : integer}, now : integer, everyMs : integer, max : integer, soon? : {integer : boolean}, soonMs? : integer) : {integer}
	--- Phase 7: one line's money from `balance(from, to, maintenanceType or nil)` (the engine's
	--- calculateBalance for that line). Stops early once judgeLoss's verdict is settled: a year >= 0
	--- costs 1 call, an empty oldest quarter 2, two quarters >= 0 at most 5; a losing line 7.
	lineMoney : function(balance : function(integer, integer, any) : number, now : integer, yearMs : integer, vehicleType : any, maintType : any) : ProblemRadarLineMoney
	--- Phase 7: line_unprofitable verdict for one line's money (nil: not losing money consistently, or
	--- too young: the oldest quarter has no journal entries).
	judgeLoss : function(money : ProblemRadarLineMoney, settings : ProblemRadarSettings, networkCost? : integer) : ProblemRadarLoss
	--- Phase 7: line_unprofitable rows for the lines checked this pass + carried rows of the others.
	unprofitable : function(input : ProblemRadarUnprofitableInput) : {ProblemRadarAlert}
	--- Phase 7: line_low_use rows from the live utilisation averages.
	lowUse : function(input : ProblemRadarLowUseInput) : {ProblemRadarAlert}
	--- One time-weighted EMA step: `sample` (0..1) stands for the time since prev.last; weight
	--- 1 - exp(-dt / yearMs), normalised by the weight so far. nil / later prev: tracking starts now.
	updateUseAvg : function(prev : ProblemRadarUseAvg, sample : number, now : integer, yearMs : integer) : ProblemRadarUseAvg
	--- Apply this pass's samples (line -> 0..1) to the live averages; lines not in `keep` are dropped,
	--- new lines over `cap` (default MAX_USE_TRACKED) are not tracked.
	sampleUseAvg : function(live : {integer : ProblemRadarUseAvg}, samples : {integer : number}, keep : {integer : boolean}, now : integer, yearMs : integer, cap? : integer) : {integer : ProblemRadarUseAvg}
	--- The live averages if they still belong to the saved ones (same lines and starts, samples not
	--- older), else rebuilt from the save (a load, another save, time going back).
	reconcileUseAvg : function(saved : any, live : {integer : ProblemRadarUseAvg}, liveAt : integer, now : integer) : {integer : ProblemRadarUseAvg}
	--- The averages to save: `saved` unchanged unless a line was added / removed (or restarted), or the
	--- newest sample is `everyMs` newer than the newest saved one (then every entry is written).
	persistUseAvg : function(live : {integer : ProblemRadarUseAvg}, saved : any, everyMs : integer) : {integer : {integer}}, boolean
	--- n rounded to two significant digits (save churn of re-checked money rows).
	roundSig2 : function(n : integer) : integer
	--- Alerts per tier { critical, warning, info }: stored rows by their tier, kindCounts over the
	--- stored rows by the kind's tier.
	tierCounts : function(alerts : {ProblemRadarAlert}, kindCounts : any) : {integer}
	--- A shallow copy of `memory` (or fresh memory) with the fields of `patch` replaced.
	patchMemory : function(memory : ProblemRadarMemory, patch : ProblemRadarMemory) : ProblemRadarMemory
	--- "2:30" for seconds (language-neutral).
	formatSeconds : function(sec : integer) : string

	--- New stoppedSince map: the time kept for vehicles still standing, `now` for new ones, others
	--- dropped; capped at `cap` (oldest kept). Returns the map and whether it differs from `prev`.
	updateStopped : function(prev : {integer : integer}, standing : {integer : any}, now : integer, cap? : integer) : {integer : integer}, boolean
	--- New blockedSince/blockedBy maps from getBlockedTrains pairs {blocked, blocker}: the time is kept
	--- while the same blocker blocks the same train, else restarts at `now`. Capped like updateStopped.
	updateBlocked : function(prevSince : {integer : integer}, prevBy : {integer : integer}, pairs : {{integer}}, now : integer, cap? : integer) : {integer : integer}, {integer : integer}, boolean
	--- Whether two timer maps hold the same entries (`b` may be raw save data: values compared as integers).
	sameTimerMap : function(a : {integer : integer}, b : any) : boolean
	--- Timers younger than this stay out of state.memory (they live in state.rt.young, which is
	--- rewritten only while young timers come and go; memory changes only when a timer crosses this age).
	PERSIST_TIMER_AFTER_MS : integer
	--- The entries of `since` at least `minAge` old (the part that is saved), and `by` filtered to the same keys.
	agedTimers : function(since : {integer : integer}, now : integer, minAge : integer, by? : {integer : integer}) : {integer : integer}, {integer : integer}
	--- The saved timers plus the young entries (state.rt.young) that the saved memory lacks because they
	--- were younger than `minAge` at `liveAt` (the game time they were written). Older ones are
	--- ignored (dropped from the state); all of them when liveAt is nil or after `now`.
	withYoungTimers : function(saved : {integer : integer}, savedBy : {integer : integer}, live : {integer : integer}, liveBy : {integer : integer}, liveAt : integer, now : integer, minAge : integer) : {integer : integer}, {integer : integer}
	--- The entries of `since` younger than `minAge` (the part agedTimers leaves out: state.rt.young), and
	--- `by` filtered to the same keys.
	youngTimers : function(since : {integer : integer}, now : integer, minAge : integer, by? : {integer : integer}) : {integer : integer}, {integer : integer}
	--- state.rt from whatever the save holds: a fresh, sanitised table the engine script may modify.
	cleanRuntime : function(raw : any) : ProblemRadarRuntime
	--- `rt` without its empty / default parts (nil when nothing is left), as stored in state.rt.
	packRuntime : function(rt : ProblemRadarRuntime) : ProblemRadarRuntime
	--- Whether a packed runtime equals the stored one (`b` may be raw save data).
	sameRuntime : function(a : ProblemRadarRuntime, b : any) : boolean
	--- Root of a blocking chain (follows blockedBy; in a cycle, the lowest id of the cycle).
	chainRoot : function(by : {integer : integer}, train : integer) : integer
	--- "12m", "2h05m" for a duration in game ms (language-neutral metric).
	formatMinutes : function(ms : integer) : string

	--- Replace the alerts of one scan group with `fresh`: firstSeen kept for ids already present
	--- (else `now`), kind counts updated, sorted, capped at `cap` (default MAX_STORED_ALERTS).
	--- Smoothing over settings.smoothSec (game seconds; 0 = off): a new id waits in state.pending
	--- until detected for the window (misses up to the window don't reset it; longer ones drop it),
	--- then is listed with firstSeen = now; a listed id that is not detected lingers with its last
	--- data until missed for longer than the window. Rows marked `carried` are no news (no timer
	--- starts or stops). `instant`: new ids are listed at once (priming after the mod is added).
	--- Kinds set to "off" go at once. Returns a new state (settings and the notify maps carried
	--- over) and whether alerts/counts/pending changed.
	--- memory: the state's memory is carried over unless `memory` is given.
	merge : function(state : ProblemRadarState, group : string, fresh : {ProblemRadarAlert}, now : integer, cap? : integer, memory? : ProblemRadarMemory, instant? : boolean) : ProblemRadarState, boolean
	--- The state's alerts by id.
	index : function(alerts : {ProblemRadarAlert}) : {string : ProblemRadarAlert}
	--- Sort order of state.alerts (tier, firstSeen, id); never errors on bad field types.
	alertBefore : function(a : ProblemRadarAlert, b : ProblemRadarAlert) : boolean

	--- Snooze: at most this many snoozed alerts are stored (the latest-ending kept).
	MAX_SNOOZED : integer
	--- The month presets the window offers (radar_settings snoozeMonths accepts any value in its range).
	SNOOZE_MONTHS : {integer}
	--- Sanitised copy of a saved snooze map (garbage dropped, capped); nil when empty.
	cleanSnoozed : function(snoozed : any) : {string : ProblemRadarSnooze}
	--- Snooze a listed alert until `untilMs`. Returns the new state and whether it changed (false
	--- when the id is not listed). The alert stays stored; counts drop it.
	snooze : function(state : ProblemRadarState, id : string, untilMs : integer) : ProblemRadarState, boolean
	--- End a snooze (id), or every snooze (id == nil). The alerts count again at once.
	unsnooze : function(state : ProblemRadarState, id : string) : ProblemRadarState, boolean

	--- Phase 6 failure isolation: a scan that failed this many times in a row drops its kept rows.
	FAIL_DROP_AFTER : integer
	--- The previous alerts of `kinds` to keep after a failed scan (copies marked `carried`); none once
	--- `failures` (consecutive, this one included) reaches `limit` (default FAIL_DROP_AFTER).
	carryOver : function(prev : {ProblemRadarAlert}, kinds : {string : boolean}, failures : integer, limit? : integer) : {ProblemRadarAlert}
	--- Phase 6 deferred reads for veh_stuck: vehicles standing at least the smallest threshold whose
	--- carrier is unknown (classify), and those past their known carrier's threshold (due); both ascending.
	standingDue : function(stoppedSince : {integer : integer}, now : integer, carriers : {integer : string}, thresholds : {string : integer}) : {integer}, {integer}
	--- Marks (entity -> time marked) still valid: entity in `present`, marked less than `ttl` ago.
	expireMarks : function(marks : {integer : integer}, now : integer, ttl : integer, present : {integer : boolean}) : {integer : integer}
	--- Alerts whose entity still exists (`current`: entity -> creation revision) and, when a revision
	--- was saved for it, still has that revision (a reused id is dropped). Returns the kept alerts and
	--- the revisions to remember.
	keepSameEntity : function(alerts : {ProblemRadarAlert}, saved : {integer : integer}, current : {integer : integer}) : {ProblemRadarAlert}, {integer : integer}
end

-- ======================================================================
-- from radar_settings.tl (pure; shared by the engine script and the GUI model)
-- Module: ug_require "square_problem_radar::/radar/radar_settings.tl" as ProblemRadarSettingsModule
global record ProblemRadarSettingsModule
	HUD_MODES : {string}                -- allowed hudMode values, default first
	KEYS : {string}                     -- every flat setting key, in display order ("notify" is separate)
	NUMBERS : {string : ProblemRadarNumberSetting}  -- integer settings: default and allowed range
	STUCK_KEYS : {string : string}      -- carrier name ("ROAD", ...) -> its stuckMin* key
	NOTIFY_LEVELS : {string}            -- "off", "passive", "notify"
	NOTIFY_KINDS : {string}             -- every alert kind, in Settings tab order
	NOTIFY_DEFAULTS : {string : string} -- default notify level per kind
	WORN_HYSTERESIS_PCT : integer       -- fleet_worn clears above wornPct + this
	--- A fresh settings table with every default.
	defaults : function() : ProblemRadarSettings
	--- A fresh, valid copy of any value (nil, garbage, partial): unknown keys dropped, bad values defaulted.
	normalize : function(settings : any) : ProblemRadarSettings
	--- Apply a "ProblemRadar.setSetting" param ({ hudMode = "compact" }, { notify = { veh_stuck = "off" } },
	--- any subset of keys) to `current`. Returns a fresh settings table, whether anything changed, and
	--- the rejected keys (sorted; "notify.<kind>" for a bad notify entry). A non-table param rejects as "<param>".
	apply : function(current : ProblemRadarSettings, param : any) : ProblemRadarSettings, boolean, {string}
	--- "ProblemRadar.resetSettings": every setting back to its default. param must be nil or a table
	--- (contents ignored), else rejected as "<param>". Returns the settings, whether they changed, rejected.
	reset : function(current : ProblemRadarSettings, param : any) : ProblemRadarSettings, boolean, {string}
	--- Whether `raw` (e.g. straight from a save) already equals its normalized form on every key.
	same : function(raw : any, normalized : ProblemRadarSettings) : boolean
	--- The notify level of an alert kind (default for missing / invalid entries).
	level : function(settings : ProblemRadarSettings, kind : string) : string
	--- carrier name -> veh_stuck threshold in game ms, from (normalised) settings.
	stuckThresholdsMs : function(settings : ProblemRadarSettings) : {string : integer}
	--- fleet_worn thresholds as conditions 0..1: alert at <= first, kept while <= second.
	wornThresholds : function(settings : ProblemRadarSettings) : number, number
end

-- ======================================================================
-- from radar_notify.tl (pure notification decisions, Phase 5)
-- Module: ug_require "square_problem_radar::/radar/radar_notify.tl" as ProblemRadarNotifyModule

global record ProblemRadarNotifyInput
	now : integer
	settings : ProblemRadarSettings
	alerts : {ProblemRadarAlert}         -- the state's current (listed) alerts, after merge
	notified : {string : integer}        -- state.notified
	cleared : {string : integer}         -- state.notifyCleared
	maxToasts : integer                  -- optional, default MAX_TOASTS
	silentAll : boolean                  -- optional: mark every new alert notified without a toast (mod just added)
	silentKinds : {string : boolean}     -- optional: the same for these kinds (just switched to "notify")
	snoozed : {string : any}             -- optional: state.snoozed; these ids never toast and are forgotten
	                                     -- (not notified, no cooldown), so a snooze that ends toasts again
end

--- Game-time toast budget (radar_notify.applyBudget). Kept in state.rt.budget (shared by every
--- simulation Lua state), stored only when a toast or summary was sent or the pending count changed.
global record ProblemRadarNotifyBudget
	windowStart : integer                -- gameTime (ms) the current window started
	toasts : integer                     -- toasts sent in this window
	summaries : integer                  -- summary toasts sent in this window
	pending : integer                    -- new problems not toasted yet, for the next summary
end

--- Notification priming (state.rt.prime; radar_notify.step silentAll / silentKinds). Requested when
--- the mod is added to a save (no v5 notify maps) or kinds switch to "notify"; dropped by the notify
--- step once every group was scanned after the request (`seen`).
global record ProblemRadarPrime
	all : boolean                        -- every new alert silently (the mod was just added)
	kinds : {string : boolean}           -- these kinds silently (just switched to "notify")
	seen : {string : boolean}            -- scan groups scanned since the request
end

--- Stuck / blocked timers younger than radar_checks.PERSIST_TIMER_AFTER_MS (state.rt.young): the
--- part of the vehicles scan's timer maps that state.memory leaves out. `at` = gameTime (ms) of the
--- scan that wrote them (kept while the maps are unchanged).
global record ProblemRadarYoungTimers
	at : integer
	stopped : {integer : integer}
	blockedSince : {integer : integer}
	blockedBy : {integer : integer}
end

--- state.rt: engine bookkeeping that every simulation Lua state must see (a tick runs in any one of
--- them). Every field is optional; packRuntime leaves out empty ones (nil = default).
global record ProblemRadarRuntime
	prime : ProblemRadarPrime                -- nil: not priming
	budget : ProblemRadarNotifyBudget        -- nil: no toast sent in a window yet
	fails : {string : integer}               -- consecutive failures per scan group / sub-scan (> 0 only)
	lineCursor : integer                     -- line-quality rotation: the last line measured (nil = -1)
	econCursor : integer                     -- line_unprofitable rotation: the last line checked (nil = -1)
	econGen : integer                        -- +1 each time line_unprofitable is switched off (drops each Lua state's check times)
	econOff : boolean                        -- line_unprofitable is off (true only)
	young : ProblemRadarYoungTimers          -- nil: none
	ineligible : {integer : integer}         -- standing vehicles found foreign / user-stopped -> gameTime marked
end

global record ProblemRadarNotifyResult
	toasts : {ProblemRadarAlert}         -- alerts to raise a notification for now (tier, firstSeen, id order)
	more : integer                       -- further new alerts over the cap: one "+N more problems" toast when > 0
	notified : {string : integer}
	cleared : {string : integer}
	changed : boolean                    -- notified / cleared differ from the input (state:set needed)
end

--- Notification params (plain data: stored by the base Notifications script with the save).
--- A summary toast has only `more`.
global record ProblemRadarNotificationParams
	kind : string
	tier : integer
	etype : string
	label : string
	context : string
	code : string
	arg : string
	metric : string
	entity : integer       -- nil if none
	entityRev : integer    -- api.engine.getRevision(entity).num[1] when sent (entity_util.makeEntityAndRevision0); nil if unknown
	pos : {number}         -- focus this position instead (path problems)
	more : integer         -- summary toast: number of further new problems
end

global record ProblemRadarNotifyModule
	MAX_TOASTS : integer                 -- toasts per call (once per scan cycle)
	COOLDOWN_MS : integer                -- a cleared alert that returns within this is not notified again
	MAX_NOTIFIED : integer
	MAX_CLEARED : integer
	MIN_AGE_MS : {string : integer}      -- per kind: wait this long after firstSeen before toasting
	BUDGET_WINDOW_MS : integer           -- budget window (game ms)
	BUDGET_TOASTS : integer              -- toasts per window
	BUDGET_SUMMARIES : integer           -- summary toasts per window
	--- The alerts whose kind is not "off".
	filterOff : function(alerts : {ProblemRadarAlert}, settings : ProblemRadarSettings) : {ProblemRadarAlert}
	--- Whether a kind is detected at all (level ~= "off").
	isOn : function(settings : ProblemRadarSettings, kind : string) : boolean
	step : function(input : ProblemRadarNotifyInput) : ProblemRadarNotifyResult
	--- Apply the game-time budget to one step's toasts: returns the toasts to send now, the summary
	--- count to send now (0 = none) and the new budget. Over-budget toasts and `more` are carried in
	--- budget.pending into the next allowed summary. paused: nothing is sent, pending is dropped.
	applyBudget : function(budget : ProblemRadarNotifyBudget, now : integer, toasts : {ProblemRadarAlert}, more : integer, paused? : boolean) : {ProblemRadarAlert}, integer, ProblemRadarNotifyBudget
	--- Kinds whose level became "notify" between two settings (nil if none).
	newlyNotify : function(old : ProblemRadarSettings, new : ProblemRadarSettings) : {string : boolean}
	--- Toast order (tier, firstSeen, id); never errors on bad field types.
	toastBefore : function(a : ProblemRadarAlert, b : ProblemRadarAlert) : boolean
	--- Toast params for an alert (entityRev is added by the engine, which can read revisions).
	params : function(alert : ProblemRadarAlert) : ProblemRadarNotificationParams
end

-- ======================================================================
-- from gui/radar_hud_model.tl (pure view model)
-- Module: ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl" as ProblemRadarHudModel

--- One display row: a sanitised copy of an alert plus its translated texts.
global record ProblemRadarHudRow
	id : string
	kind : string
	tab : string
	tier : integer         -- 1..3
	entity : integer       -- nil when the alert had none
	entity2 : integer
	label : string         -- entity name; "#<entity>" when the alert had none; never nil
	context : string       -- never nil
	etype : string         -- the alert's entity type code; never nil
	code : string          -- the alert's code; nil if none
	arg : string           -- the alert's arg; nil if none
	-- Translated texts: "" until model.decorate fills them (build decorates every row,
	-- buildRaw none, visibleRows decorated copies of the rendered ones).
	kindLabel : string     -- translated short kind, e.g. "No path"
	typeLabel : string     -- translated entity type, e.g. "Train"; never nil
	detail : string        -- translated problem text; never nil
	tip : string           -- longer text for the row tooltip (line_unprofitable); nil = detail + metric
	metric : string        -- never nil
	firstSeen : integer    -- 0 when missing
	pos : {number}         -- {x, y, z} or nil
	snoozedUntil : integer -- snoozed rows: gameTime (ms) the snooze ends; nil otherwise
	gone : boolean         -- snoozed rows: the problem is not detected right now
end

global record ProblemRadarHudView
	hudMode : string                    -- "badge" | "compact" (normalised)
	settings : ProblemRadarSettings     -- normalised (Settings tab)
	total : integer                     -- every current alert (incl. the ones over the stored cap)
	hidden : integer                    -- total - #rows (alerts over the cap, not listed)
	hiddenByTab : {string : integer}    -- same per tab ("all" included)
	tierCounts : {integer}              -- [1] critical, [2] warning, [3] info
	tabCounts : {string : integer}      -- "all", "vehicles", "lines", "stations", "fleet", "economy", "snoozed"
	worstTier : integer                 -- 1..3, or 0 when there are no alerts
	badgeLabel : string                 -- "Radar" (translated)
	badgeText : string                  -- "Radar ● 3"
	compactText : string                -- "3 crit · 2 warn · 5 info"
	rows : {ProblemRadarHudRow}         -- tier ascending, then firstSeen ascending, then id
	snoozedRows : {ProblemRadarHudRow}  -- snoozed alerts (not in rows or any count but "snoozed"), soonest end first
end

--- The ridge HUD's counts-only view (no rows, no texts), from state.kindCounts.
global record ProblemRadarHudCounts
	hudMode : string                    -- "badge" | "compact" (normalised)
	total : integer
	tierCounts : {integer}              -- [1] critical, [2] warning, [3] info
	worstTier : integer                 -- 1..3, or 0 when there are no alerts
end

global record ProblemRadarHudModel
	TABS : {string}                     -- alert tabs in display order: all, vehicles, lines, stations, fleet, economy
	--- Money text for the economy rows (integer game money). Pure default: "-1,200,000"; the GUI
	--- scripts set it to api.util.formatMoney.
	formatMoney : function(money : integer) : string
	MAX_RENDERED_ROWS : integer         -- rows the window renders per tab (the rest: "+N more")
	SNOOZED_TAB : string                -- "snoozed": the tab of the snoozed alerts (after TABS)
	--- A fresh view for any state (nil / {} / malformed alerts give the empty view).
	build : function(state : ProblemRadarState) : ProblemRadarHudView
	--- Like build, but the rows carry no translated texts and badge/compact texts are "" (window poll).
	buildRaw : function(state : ProblemRadarState) : ProblemRadarHudView
	--- Fill a row's translated texts (in place; returns the row).
	decorate : function(row : ProblemRadarHudRow) : ProblemRadarHudRow
	--- Counts-only view for the ridge HUD from state.kindCounts and settings.hudMode; the tiers from
	--- state.tierCounts (v6) when it matches the kind counts, else by each kind's catalogue tier.
	counts : function(kindCounts : any, hudMode : any, tierCounts? : any) : ProblemRadarHudCounts
	--- "3 crit · 2 warn · 5 info" (translated).
	compactText : function(tierCounts : {integer}) : string
	--- Up to `cap` (default MAX_RENDERED_ROWS) decorated rows of a tab and how many more it has. The
	--- view's own rows are never changed (decorated copies), so a poll's deepEquals still matches.
	visibleRows : function(view : ProblemRadarHudView, tab : string, cap? : integer) : {ProblemRadarHudRow}, integer
	--- Snooze clicks not confirmed by the engine yet, applied on top of a view: `snooze` id -> estimated
	--- end moves a row to snoozedRows, `wake` ids move back (gone ones vanish). Counts follow. Returns
	--- the view itself when nothing applies.
	applyPending : function(view : ProblemRadarHudView, snooze : {string : integer}, wake : {string : boolean}) : ProblemRadarHudView
	--- Alert id -> creation revision of its entity: kept for known ids, looked up for new ones.
	trackRevisions : function(prev : {string : integer}, rows : {ProblemRadarHudRow}, revOf : function(integer) : integer) : {string : integer}
	--- false when the entity's creation revision is newer than the saved one (its id was reused).
	sameRevision : function(saved : integer, current : integer) : boolean
	--- The view's rows for one tab ("all" = every row), in view order.
	rowsForTab : function(view : ProblemRadarHudView, tab : string) : {ProblemRadarHudRow}
	--- Translated problem text for an alert-like row (kind, code, arg; metric for veh_stuck / train_blocked_by).
	detailText : function(kind : string, code : string, arg : string, metric? : string) : string
	--- line_unprofitable: the full sentence behind the short detail (row tooltip, notification); nil otherwise.
	tipText : function(kind : string, arg : string) : string
	-- The engine's metric with its unit letters translated for display ("12m", "31d", "3 veh · 42").
	metricText : function(kind : string, metric : string) : string
	--- Translated severity of a kind for the Settings table: "Warning", or "Info to Critical" for a
	--- kind whose tier scales (maxTier).
	kindTierLabel : function(kind : string) : string
	--- Translated short kind label ("Stuck"); the kind itself if unknown.
	kindLabel : function(kind : string) : string
	--- Translated tier name: "Critical" | "Warning" | "Info".
	tierLabel : function(tier : integer) : string
	--- Notification title, description and icon path for ProblemRadarNotificationParams (any value: a
	--- summary toast, or garbage from a save, gives a generic text).
	notificationText : function(params : any) : string, string, string
end

recordDef = false
