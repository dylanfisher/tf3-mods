-- Stress Test traffic log, the sampler (plans/square_stress_test/FLOW_PLAN.md step 5; lines: FLOW.md; pure part:
-- stress/stress_flow.tl). Traffic tab > Traffic log: every 10 / 30 / 60 GAME seconds one sweep over the cars on
-- the road writes one FLOW line per zone (also with cars=0), FLOW_ALL, FLOW_BUS per "SQST Bus N" line, FLOW_TOWNS
-- (at most every 60 s wall) and every 10 samples FLOW_SUMMARY (and at the stop: Off, interval change, Clear queue).
--
-- TIME AXIS: GAME_TIME.gameTime of the world (game ms, docs/findings/lines-vehicles.md "Units"): a sample is due
-- every interval game seconds, so a paused game takes no samples and the game speed does not change the spacing.
-- FLOW_START logs gt_per_s=1000.
--
-- THREADS: everything runs from this module's rt tick hook (rt.tick <- react.onStep of the HUD button, the Main
-- Thread; never onStepTimer, which runs on worker threads: docs/findings/gui.md "Timers and threads").
--
-- COST (probes 11a / 11h, session 2026-10-12_0905): SIM_PERSON list of 43k ~1.2 ms, MOVE_PATH read ~1 us,
-- getPosition ~1 us. One sweep: the list in its own frame, then the persons in slices of at most BUDGET_US per
-- frame (READS_PER_FRAME driver reads, MOVE_PATH + getPosition, is only a safety stop), then the bus lines, the
-- towns map (its own frame), the line formatting (its own frame) and the writes (WRITES_PER_FRAME lines per
-- frame). Every engine read is pcall'd; entityExists before getPosition and every line / vehicle read
-- (component reads of a person gone since the list return nil, as in Clear traffic's scan).
-- EVERY DRIVER (v3, 2026-10-12: seed 530609 read 3000 of ~55k drivers, capped=1 every sweep, and the zones saw
-- 0-35 cars): a run starts with no target; a sample that comes due while the sweep still runs is skipped
-- (FLOW_SUMMARY skipped=) and lowers the target for the rest of the run to the drivers read by then x
-- TARGET_DROP (>= TARGET_MIN; one [SQST] FLOW_TARGET line), later sweeps read every stride-th driver (spread over
-- the list). Measured at 55k drivers / 109k persons: the v2 sweep (every person checked, 3000 read) cost ~95 ms in
-- ~75 frames; reading all 55k adds ~2-4 us each, ~0.2 s, so ~0.3 s busy in ~150 frames at 2 ms: about 2.5 s at 60
-- fps, well inside the 30 game s interval at 4x (7.5 s, ~450 frames). FLOW_ALL reports frames, sweep_ms,
-- frame_ms_max, target, stride.
--
-- THRU (2026-10-13, FLOW.md "thru method"): with every driver read, a driver near a zone (thruTrack) or one that had
-- it ahead also reads up to THRU_WINDOW path edges ahead (and, only if it had it ahead, as many behind); those reads
-- count against the frame budget (the clock after every such driver). Offline (fake costs 0.25 us per path element,
-- every one of 48k drivers near a junction): 218 frames instead of 57 for one sweep, frames still <= 2 ms. A sweep
-- that misses its interval lowers the target: then every stride-th driver by entity id is read (path reads too), and
-- thru counts among them x stride (thru_scale). The target comes back up only when the last sweep projects the
-- raised one within half the interval (its own cost per driver, path reads included: FLOW_TARGET reason=recovered).
--
-- ZONES: the session's Showcase (stress_slzones current: the twins whose zone line was written, measured r,
-- src=placement), else Smart Lanes' saved zones after a reload (src=sl_zones, r = reach estimate + 20 m, twin
-- ids from the stored id / pair labels, else recomputed from the list order). A new Showcase (or its zones
-- cleared) restarts the run once no test build runs. Buses: the twin from stress_buslines lineTwins (session),
-- else from the line's two stops (stress_flow.twinFromStops, twin_from=stops).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local flow = ug_require "square_stress_test::/stress/stress_flow.tl" as SquareStressFlow
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones
local buslines = ug_require "square_stress_test::/stress/gui/stress_buslines.tl" as SquareStressBusLines
local traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl" as SquareStressTraffic

local fl : SquareStressFlowLog = {
	ui = { on = false, interval = 2 },
	BUDGET_US = 2000,
	READS_PER_FRAME = 2000,   -- safety stop only: the time budget ends a slice first (v2: 100 with a 3000 cap)
	WRITES_PER_FRAME = 100,
	PATH_GIVE_UP = 2000,
	pathThru = true,          -- read the drivers' paths for thru_path (the bench turns it off: position is the count)      -- path elements read with no reader working before thru_path stops for the run
	TOWNS_EVERY_US = 60000000,
	TOWNS_SLOW_EVERY_US = 300000000,
	TOWNS_SLOW_MS = 50.0,
}

local ZONE_CHECK_US <const> = 2000000   -- how often the zone source is compared (a new Showcase)
local SETS_PER_FRAME <const> = 2        -- zones whose junction streets are re-read in one frame (path thru)
local CHECK_EVERY <const> = 8           -- persons between two clock reads in a slice

local record BusItem
	line : integer
	name : string
end

local record Sweep
	gt : number
	phase : string                -- list, sets, scan, buslist, bus, towns, format, write
	setCursor : integer           -- sets: the next zone whose junction streets are re-read
	startUs : integer
	busyUs : integer
	frames : integer
	frameMaxUs : integer
	frameMaxPhase : string        -- the phase of its busiest frame (FLOW_ALL frame_phase=)
	target : integer              -- drivers to read at most (nil: every one)
	stride : integer              -- every stride-th driver is read
	lowered : boolean             -- this sweep already lowered the run's target
	persons : {integer}
	cursor : integer
	sample : SquareStressFlowSample
	buses : {BusItem}
	busCursor : integer
	busLines : {string}
	townLines : {string}
	out : {string}
	outCursor : integer
end

-- The run's state in one table (Lua 5.1: at most 60 upvalues per function).
local record State
	run : integer
	active : boolean
	zones : {SquareStressFlowZone}
	index : SquareStressFlowIndex
	src : string
	scRun : string
	zoneSig : string
	nextZoneCheckUs : integer
	nextDueGt : number
	s : integer
	totals : SquareStressFlowTotals
	sweep : Sweep
	laps : {integer : number}
	lineTwin : {integer : SquareStressLineTwin}
	lineTwinFrom : {integer : string}
	nextTownsUs : integer
	townsEveryUs : integer
	clearsSeen : integer
	lastMs : number
	lastFrames : integer
	lastDrivers : integer
	keepWarned : boolean
	wall0 : integer
	target : integer              -- the per-sweep target (nil: every driver; lowered after a skipped sample)
	prevDrivers : integer         -- drivers found by the last sweep (the stride)
	thruSets : {{integer : boolean}}  -- per zone: its junction's own street edges and nodes (flow.THRU_R; thru)
	trackIndex : SquareStressFlowIndex  -- the zones as circles of THRU_TRACK (drivers checked for a path through them)
	prevSample : SquareStressFlowSample -- the last sample (its zones' ahead sets; thru)
	prevComplete : boolean        -- it read every driver
	prevGt : number               -- its game time
	prevAheadOf : {integer : {integer}} -- driver -> the zones it had ahead in the last sample
	prevStride : integer          -- its stride (thru compares the same id subset only)
	pathDbg : integer             -- FLOW_PATHDBG lines written this run
	pathTries : integer           -- path elements read this run without any reader working (the path thru stops at PATH_GIVE_UP)
	pathOff : boolean             -- no path element read: the path thru (thru_path) is off for the run, the positional thru goes on
end

local st : State = { run = 0, active = false, zones = {}, s = 0, laps = {}, lineTwin = {}, lineTwinFrom = {}, nextTownsUs = 0,
	townsEveryUs = fl.TOWNS_EVERY_US, clearsSeen = 0, nextZoneCheckUs = 0 }

---------------------------------------------------------------------------
-- Reads (each pcall'd; nil when unreadable)

local function comp(e : integer, ct : Engine.ComponentType) : any
	if e == nil or ct == nil then return nil end
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

local function exists(e : integer) : boolean
	if e == nil or e < 0 then return false end
	local ok, x = pcall(api.engine.entityExists, e)
	return ok and x == true
end

local function gameTime() : number
	local gt = comp(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	if gt == nil or type(gt.gameTime) ~= "number" then return nil end
	return gt.gameTime
end

local function gameSpeed() : integer
	local gs = comp(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	return gs ~= nil and gs.speedup or nil
end

local function entityName(e : integer) : string
	local ok, n = pcall(api.engine.util.getEntityName, e)
	return ok and n ~= nil and tostring(n) or nil
end

local driveValue : any = nil

--- The person's MOVE_PATH when it drives a car right now (lastMoveMode DRIVE, a MOVE_PATH, not seated in a
--- vehicle: stress_traffic isDriver / probe 11a), else nil.
local function driverPath(e : integer) : Engine.Component.MovePath
	local CT = api.type.ComponentType
	local sp = comp(e, CT.SIM_PERSON) as Engine.Component.SimPerson
	if sp == nil then return nil end
	if driveValue == nil then
		local ok, v = pcall(function() : any return (api.type["enum"] as {string : {string : any}}).MoveMode.DRIVE end)
		driveValue = (ok and v ~= nil) and v or 1
	end
	if sp.lastMoveMode ~= driveValue then return nil end
	local mp = comp(e, CT.MOVE_PATH) as Engine.Component.MovePath
	if mp == nil then return nil end
	if comp(e, CT.SIM_PERSON_AT_VEHICLE) ~= nil or comp(e, CT.SIM_ENTITY_AT_VEHICLE) ~= nil then return nil end
	return mp
end

--- A car's position (getPosition; exactly 0,0 = no answer), nil when unreadable.
local function carPos(e : integer) : number, number
	local ok, p = pcall(api.engine.util.vehicle.getPosition, e)
	if ok and p ~= nil and p.x ~= nil and (p.x ~= 0 or p.y ~= 0) then return p.x, p.y end
	return nil, nil
end

---------------------------------------------------------------------------
-- Zones

local function sessionSig() : string
	local cur = slzones.current
	if cur == nil then return "saved" end
	local built = 0
	for _, z in ipairs(cur.zones or {}) do if z.built then built = built + 1 end end
	return string.format("sc%d:%s:%d", cur.seq or 0, cur.run or "-", built)
end

--- The run's zones: the session's Showcase, else Smart Lanes' saved zones.
--- A zone's junction for thru: the street edges with an end node within THRU_R of its centre, or (shorter ones) their
--- middle within it, and those nodes. The octree matches an edge by its middle (docs/findings/roads.md), so it is
--- asked THRU_LONG farther out: a junction whose arms are single long edges (the Lights showcase's crossings: 60 m
--- arms, their links' pieces longer) still gets them. Every read pcall'd.
local THRU_LONG <const> = 250.0
local function thruSetOf(z : SquareStressFlowZone) : {integer : boolean}
	local set : {integer : boolean} = {}
	local r2 = flow.THRU_R * flow.THRU_R
	pcall(function()
		local list = api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(z.x, z.y), flow.THRU_R + THRU_LONG,
			api.type.ComponentType.BASE_EDGE) as {integer}
		for _, e in ipairs(list or {}) do
			local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
			if be ~= nil then
				local pts : {{number}} = {}
				local near : {integer} = {}
				for _, n in ipairs({ be.node0, be.node1 }) do
					local bn = comp(n, api.type.ComponentType.BASE_NODE) as Engine.Component.BaseNode
					if bn ~= nil then
						local dx, dy = bn.position.x - z.x, bn.position.y - z.y
						pts[#pts + 1] = { dx, dy }
						if dx * dx + dy * dy <= r2 then near[#near + 1] = n end
					end
				end
				local mid = #pts == 2 and ((pts[1][1] + pts[2][1]) / 2) ^ 2 + ((pts[1][2] + pts[2][2]) / 2) ^ 2 <= r2
				if #near > 0 or mid then
					set[e] = true
					for _, n in ipairs(near) do set[n] = true end
				end
			end
		end
	end)
	return set
end

local function loadZones()
	local cur = slzones.current
	if cur ~= nil then
		st.zones, st.src, st.scRun = flow.zonesFromShowcase(cur.zones, cur.run), "placement", cur.run
	else
		local list, run = slzones.savedZones()
		st.zones = flow.zonesFromSaved(list, run)
		st.src = list ~= nil and "sl_zones" or "none"
		st.scRun = run
	end
	if #st.zones == 0 then st.src = "none" end
	st.index = flow.newIndex(st.zones)
	st.zoneSig = sessionSig()
	-- thru: each zone's own street edges and nodes, and the zones as THRU_TRACK circles
	st.thruSets, st.prevSample, st.prevAheadOf, st.prevComplete = {}, nil, {}, false
	-- the path thru off (fl.pathThru false: the bench, BENCH.md; thru by position is the count) or until no element reads
	st.pathDbg, st.pathTries, st.pathOff = 0, 0, fl.pathThru == false
	local circles : {SquareStressFlowZone} = {}
	for i, z in ipairs(st.zones) do
		local set : {integer : boolean} = thruSetOf(z)
		st.thruSets[i] = set
		-- the track circle covers the approach too (the positional thru looks at every car on it)
		local tr = math.max(flow.thruTrack(flow.INTERVALS[fl.ui.interval] or 30), (z.approach or 0) + 50)
		circles[i] = { zone = i, x = z.x, y = z.y, r = tr, rm = tr, measure = "circle" } as SquareStressFlowZone
	end
	st.trackIndex = flow.newIndex(circles)
end

---------------------------------------------------------------------------
-- Bus lines

local function sqstLines() : {BusItem}
	local out : {BusItem} = {}
	local ok, ls = pcall(api.engine.system.lineSystem.getLinesForPlayer, rt.player())
	if not ok or ls == nil then return out end
	for _, l in ipairs(ls as {integer}) do
		local n = entityName(l)
		if n ~= nil and string.match(n, "^SQST Bus %d+$") ~= nil then out[#out + 1] = { line = l, name = n } end
	end
	return out
end

--- A stop's position: its station's construction transform (street stops are constructions), else nil.
local function stopPos(stop : any) : number, number
	local ok, x, y = pcall(function() : number, number
		local CT = api.type.ComponentType
		local sg = (stop as Engine.Component.Line.Stop).stationGroup
		local g = comp(sg, CT.STATION_GROUP) as Engine.Component.StationGroup
		local station = g.stations[1]
		local con = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
		local cc = comp(con, CT.CONSTRUCTION) as Engine.Component.Construction
		local v = cc.transf:getTransl()
		return v.x, v.y
	end)
	if ok then return x, y end
	return nil, nil
end

--- The twin a line serves: the session map (stress_buslines lineTwins), else from its two stops (cached).
local function lineTwin(line : integer) : SquareStressLineTwin, string
	local t = buslines.lineTwins ~= nil and buslines.lineTwins[line] or nil
	if t ~= nil then return t, "session" end
	if st.lineTwinFrom[line] ~= nil then return st.lineTwin[line], st.lineTwinFrom[line] end
	local tw : SquareStressLineTwin = nil
	local ln = comp(line, api.type.ComponentType.LINE) as Engine.Component.Line
	if ln ~= nil and ln.stops ~= nil and #ln.stops == 2 then
		local ax, ay = stopPos(ln.stops[1])
		local bx, by = stopPos(ln.stops[2])
		local z = flow.twinFromStops(st.zones, ax, ay, bx, by)
		if z ~= nil and z.twin ~= nil then tw = { twin = z.twin, pair = z.pair, ab = z.ab } end
	end
	st.lineTwin[line] = tw
	st.lineTwinFrom[line] = tw ~= nil and "stops" or "-"
	return tw, st.lineTwinFrom[line]
end

--- One line's FLOW_BUS line (its vehicles' TRANSPORT_VEHICLE reads).
local function busLineText(item : BusItem, gt : number, sample : integer) : string
	if not exists(item.line) then return nil end
	local acc = flow.newBus()
	local ln = comp(item.line, api.type.ComponentType.LINE) as Engine.Component.Line
	local stops = ln ~= nil and ln.stops ~= nil and #ln.stops or nil
	local okV, vs = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, item.line)
	for _, v in ipairs((okV and vs ~= nil) and vs as {integer} or {}) do
		if exists(v) then
			local tv = comp(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
			if tv ~= nil then
				flow.busVehicle(acc, st.laps, v, { last = tv.lastLineStopDeparture, deps = tv.lineStopDepartures as {number},
					sections = tv.sectionTimes as {number} }, stops, gt)
			end
		end
	end
	local okF, f = pcall(api.engine.util.line.getMaxFrequency, item.line)
	local tw, from = lineTwin(item.line)
	return flow.busLine(st.run, sample, gt, item.line, item.name, tw, from, acc, stops, okF and f as number or nil)
end

---------------------------------------------------------------------------
-- Run start / stop

local function write(line : string)
	rt.detail(line)
end

local function wallS() : number
	return st.wall0 ~= nil and (rt.nowUs() - st.wall0) / 1e6 or nil
end

local function summary(final : boolean)
	local line = flow.summaryLine(st.run, st.totals, #st.zones, wallS(), final)
	if final then rt.log(line) else write(line) end
end

local function stopRun(why : string)
	if not st.active then return end
	st.active = false
	if st.sweep ~= nil then
		st.totals.warn["unfinished"] = (st.totals.warn["unfinished"] or 0) + 1
		st.sweep = nil
	end
	summary(true)
	if why ~= nil then rt.detail(string.format("[SQST] traffic log run %d stopped: %s", st.run, why)) end
	rt.version = rt.version + 1
end

local function intervalS() : integer
	return flow.INTERVALS[fl.ui.interval] or 30
end

local function startRun()
	local gt = gameTime()
	st.run = st.run + 1
	st.active = true
	st.s = 0
	st.totals = flow.newTotals()
	st.sweep = nil
	st.laps = {}
	st.lineTwin, st.lineTwinFrom = {}, {}
	st.nextTownsUs = 0
	st.townsEveryUs = fl.TOWNS_EVERY_US
	st.clearsSeen = rt.queueClears
	st.lastMs, st.lastFrames, st.lastDrivers = nil, nil, nil
	st.keepWarned = false
	st.wall0 = rt.nowUs()
	st.target = flow.CAP > 0 and flow.CAP or nil
	st.prevDrivers = nil
	st.nextDueGt = nil   -- the first sample at the first frame with a game time; then every interval from it
	st.nextZoneCheckUs = rt.nowUs() + ZONE_CHECK_US
	flow.DRIVE_SIDE = rt.drivingSide == "left" and "left" or "right"
	loadZones()
	local okT, towns = pcall(function() : integer return #(api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN) as {integer}) end)
	rt.log(flow.startLine({ run = st.run, interval = intervalS(), zones = #st.zones, towns = okT and towns or nil, buses = #sqstLines(),
		speed = gameSpeed(), keepCleared = traffic.ui.keepCleared == true, cap = flow.CAP, gt = gt, src = st.src, scRun = st.scRun,
		budgetUs = fl.BUDGET_US, pathThru = not st.pathOff }))
	for _, z in ipairs(st.zones) do write(flow.zoneLine(st.run, z)) end
	rt.version = rt.version + 1
end

local function warnKeepCleared()
	rt.warn("Traffic log", "Keep traffic cleared is on: it sends drivers home every few seconds, so the traffic log measures emptied roads, not real flow. Turn it off for an A/B run (the log's lines say keep_cleared).")
end

function fl.setOn(on : boolean)
	if on == fl.ui.on then return end
	fl.ui.on = on
	if on then
		startRun()
		if traffic.ui.keepCleared then
			st.keepWarned = true
			warnKeepCleared()
		end
	else
		stopRun("off")
	end
	rt.version = rt.version + 1
end

function fl.setInterval(index : integer)
	if flow.INTERVALS[index] == nil or index == fl.ui.interval then return end
	fl.ui.interval = index
	if st.active then
		stopRun("interval changed")
		startRun()
	end
	rt.version = rt.version + 1
end

function fl.status() : string
	return flow.statusText(st.active, intervalS(), st.run, st.totals ~= nil and st.totals.samples or 0, #st.zones, st.lastMs, st.lastFrames,
		st.lastDrivers)
end

--- The current run's samples logged and samples skipped (a sweep still running when the next came due), 0, 0 when off.
function fl.counts() : integer, integer
	if not st.active or st.totals == nil then return 0, 0 end
	return st.totals.samples, st.totals.skipped
end

function fl.uiSignature() : string
	return string.format("%s/%d/%s", tostring(fl.ui.on), fl.ui.interval, fl.status())
end

---------------------------------------------------------------------------
-- The sweep (one phase step per frame, each bounded)

local zoneBuf : {integer} = {}
local partBuf : {integer} = {}
local dirBuf : {integer} = {}
local trackBuf : {integer} = {}

--- thru: where driver e stands relative to the junctions near it (trackIndex) or ahead of it last time
--- (prevAheadOf): ahead -> the sample's zone ahead set; passed (and ahead last time) -> its passed set. Path edges read
--- lazily (at most THRU_WINDOW each way), every read pcall'd.
--- The entity of a path element ({EdgeId, boolean}): elem[1].entity, else elem.first.entity, else elem.entity
--- (the binding's pair layout is not documented; 2026-10-13 run 2026-10-13_0356_top-up-779299: thru stayed 0
--- with elem[1].entity only). nil when none reads.
-- In game (session 2026-10-13_0447_top-up-726115) every element of MOVE_PATH.path.edges is a userdata and the first
-- three readers below gave nothing (thru=0 everywhere). The documented layout ({EdgeId, boolean}, read as
-- edgePr[1].entity by the base game's mission_pathfinding_util users) comes first; the others are guesses for the
-- component's binding, kept until FLOW_PATHDBG shows which one works.
local function sub(v : any, k : any) : any return (v as {any : any})[k] end
local ELEM_READERS : {function(elem : any) : any} = {
	function(elem : any) : any return sub(sub(elem, 1), "entity") end,
	function(elem : any) : any return sub(sub(elem, "first"), "entity") end,
	function(elem : any) : any return sub(elem, "entity") end,
	function(elem : any) : any return sub(sub(elem, "edgeId"), "entity") end,
	function(elem : any) : any return sub(sub(elem, "edge"), "entity") end,
	function(elem : any) : any return sub(sub(elem, 0), "entity") end,
	function(elem : any) : any return sub(sub(elem, "id"), "entity") end,
}
local elemHow : integer = nil   -- the reader that worked first (tried first from then on: one pcall per read)
local function elemEntity(elem : any) : integer
	if elem == nil then return nil end
	if elemHow ~= nil then
		local ok, v = pcall(ELEM_READERS[elemHow], elem)
		if ok and type(v) == "number" then return math.floor(v as number) end
	end
	for k, f in ipairs(ELEM_READERS) do
		if k ~= elemHow then
			local ok, v = pcall(f, elem)
			if ok and type(v) == "number" then
				elemHow = k
				return math.floor(v as number)
			end
		end
	end
	return nil
end

local PATH_DEBUG_MAX <const> = 4   -- drivers per run whose path elements are logged once (FLOW_PATHDBG)

--- One FLOW_PATHDBG line (once per run for the first PATH_DEBUG_MAX drivers near a zone): the path's length and
--- position, and for its next elements how they read (Lua type, which accessor gave an entity) and what that
--- entity is (BASE_EDGE / BASE_NODE / BASE_EDGE_STREET / TRANSPORT_NETWORK / CONSTRUCTION), plus the zone's set.
local function pathDebug(e : integer, edges : {any}, n : integer, cur : integer, zone : integer)
	if (st.pathDbg or 0) >= PATH_DEBUG_MAX then return end
	st.pathDbg = (st.pathDbg or 0) + 1
	local parts : {string} = {}
	pcall(function()
		local CT = api.type.ComponentType
		for i = cur, math.min(n - 1, cur + 5) do
			local elem = edges[i + 1]
			-- which reader (ELEM_READERS index: 1 [1], 2 first, 3 entity, 4 edgeId, 5 edge, 6 [0], 7 id) reads it
			local how = "?"
			for k, f in ipairs(ELEM_READERS) do
				local okR, v = pcall(f, elem)
				if how == "?" and okR and type(v) == "number" then how = "r" .. tostring(k) end
			end
			local ent = elemEntity(elem)
			local kinds : {string} = {}
			if ent ~= nil then
				for _, nm in ipairs({ "BASE_EDGE", "BASE_NODE", "BASE_EDGE_STREET", "TRANSPORT_NETWORK", "CONSTRUCTION" }) do
					local okC, c : boolean, any = pcall(api.engine.getComponent, ent, (CT as {string : Engine.ComponentType})[nm])
					if okC and c ~= nil then kinds[#kinds + 1] = nm end
				end
			end
			parts[#parts + 1] = string.format("%d:%s/%s/%s/%s", i, type(elem), how, tostring(ent), #kinds > 0 and table.concat(kinds, "+") or "-")
		end
	end)
	-- the first element dumped as far as it reads (2026-10-13: a userdata no reader understood)
	local dump : {string} = {}
	pcall(function()
		local elem = edges[cur + 1]
		dump[#dump + 1] = "tostring=" .. flow.word(tostring(elem))
		local okM, mt = pcall(getmetatable, elem)
		if okM and mt ~= nil then
			local okN, nm = pcall(function() : any return sub(mt, "__name") end)
			dump[#dump + 1] = "mt_name=" .. flow.word(tostring(okN and nm or nil))
			local okI, idx = pcall(function() : any return sub(mt, "__index") end)
			dump[#dump + 1] = "mt_index=" .. type(okI and idx or nil)
			if okI and type(idx) == "table" then
				local keys : {string} = {}
				pcall(function()
					for k in pairs(idx as {any : any}) do
						keys[#keys + 1] = tostring(k)
						if #keys >= 16 then break end
					end
				end)
				table.sort(keys)
				dump[#dump + 1] = "index_keys=" .. flow.word(table.concat(keys, ";"))
			end
		else
			dump[#dump + 1] = "mt=" .. (okM and "nil" or "error")
		end
		for _, k in ipairs({ 0, 1, 2, "first", "second", "edgeId", "edge", "entity", "id", "index", "dir" } as {any}) do
			local okK, v = pcall(sub, elem, k)
			local t = okK and type(v) or "error"
			local extra = ""
			if okK and (type(v) == "userdata" or type(v) == "table") then
				local okE, ent = pcall(sub, v, "entity")
				local okX, ix = pcall(sub, v, "index")
				extra = string.format("(entity=%s,index=%s)", tostring(okE and ent or nil), tostring(okX and ix or nil))
			elseif okK and v ~= nil then
				extra = "(" .. flow.word(tostring(v)) .. ")"
			end
			dump[#dump + 1] = string.format("%s:%s%s", tostring(k), t, extra)
		end
	end)
	local set : {string} = {}
	for id in pairs(st.thruSets[zone] or {}) do
		if #set < 6 then set[#set + 1] = tostring(id) end
	end
	table.sort(set)
	write(string.format("[SQST] FLOW_PATHDBG run=%d driver=%d zone=%d n=%s cur=%s elems=%s set=%s elem0=%s", st.run, e, zone, tostring(n),
		tostring(cur), #parts > 0 and table.concat(parts, ",") or "-", #set > 0 and table.concat(set, ",") or "-",
		#dump > 0 and table.concat(dump, ",") or "-"))
end

--- Returns the path edges read (the caller counts them against the frame budget).
local function thruCheck(smp : SquareStressFlowSample, e : integer, mp : Engine.Component.MovePath, m : integer) : integer
	local prev = st.prevAheadOf[e]
	if m == 0 and prev == nil then return 0 end
	local reads = 0
	local okP, edges, n, cur = pcall(function() : {{any}}, integer, integer
		local list = (mp.path as {string : any}).edges as {{any}}
		return list, #list, math.floor(mp.dyn.pathPos.edgeIndex)
	end)
	if not okP or edges == nil or n == nil or cur == nil then return 0 end
	local function get(i : integer) : integer
		reads = reads + 1
		local ok, elem = pcall(function() : any return edges[i + 1] end)
		local id = ok and elemEntity(elem) or nil
		-- no reader works (every element nil so far): give the path thru up after PATH_GIVE_UP elements
		if elemHow == nil then
			st.pathTries = st.pathTries + 1
			if st.pathTries >= fl.PATH_GIVE_UP and not st.pathOff then
				st.pathOff = true
				write(string.format("[SQST] FLOW_PATHOFF run=%d tries=%d (no path element read: thru_path off, thru by position)", st.run, st.pathTries))
			end
		end
		return id
	end
	if m > 0 and n > 0 then pcall(pathDebug, e, edges as {any}, n, cur, trackBuf[1]) end
	local seen : {integer : boolean} = {}
	local function one(k : integer)
		if seen[k] then return end
		seen[k] = true
		local set = st.thruSets[k]
		local a = smp.zones[k]
		if set == nil or a == nil then return end
		-- the look behind only for a driver this junction had ahead last time (else its pass would not count)
		local wasAhead = st.prevSample ~= nil and st.prevSample.zones[k] ~= nil and st.prevSample.zones[k].ahead[e] == true
		local state = flow.pathState(get, n, cur, set, nil, not wasAhead)
		if state == "ahead" then
			a.ahead[e] = true
		elseif state == "passed" and wasAhead then
			a.passed[e] = true
		end
	end
	for j = 1, m do one(trackBuf[j]) end
	for _, k in ipairs(prev or {}) do one(k) end
	return reads
end

--- Scans persons from the cursor until the frame's budget or read limit; true when the list is done.
local function scanSlice(sw : Sweep, t0 : integer) : boolean
	local smp = sw.sample
	local list = sw.persons
	local reads, k = 0, 0
	while sw.cursor <= #list do
		k = k + 1
		if k % CHECK_EVERY == 0 and rt.nowUs() - t0 >= fl.BUDGET_US then return false end
		if reads >= fl.READS_PER_FRAME then return false end
		local e = list[sw.cursor]
		sw.cursor = sw.cursor + 1
		-- with a stride: only the persons whose entity id is a multiple of it are read at all (the same subset every
		-- sweep at that stride, so thru counts passes among them, thru_scale = stride; their driver count x stride is
		-- the drivers= estimate, drivers_est=1); the others cost nothing (2026-10-13 review: tested after the
		-- driver read, a lowered target saved little)
		local skip = sw.stride > 1 and e % sw.stride ~= 0
		-- a person gone since the list (another frame) reads as nil: the clear-traffic scan's pattern
		local mp = (not skip) and driverPath(e) or nil
		do
			if mp ~= nil then
				if sw.stride > 1 then
					smp.drivers = smp.drivers + sw.stride
					smp.driversEst = true
				else
					smp.drivers = smp.drivers + 1
				end
				-- without a stride: every driver up to the target
				local pick : boolean
				if sw.stride > 1 then pick = true else pick = sw.target == nil or smp.sampled < sw.target end
				if pick then
					smp.sampled = smp.sampled + 1
					reads = reads + 1
					local okD, speed, ts = pcall(function() : number, number return mp.dyn.speed, mp.dyn.timeStanding end)
					if okD and speed ~= nil then
						local x, y : number, number = nil, nil
						if exists(e) then x, y = carPos(e) end
						local n = 0
						if x == nil then smp.posFail = smp.posFail + 1 else n = flow.zonesAt(st.index, x, y, zoneBuf, partBuf, dirBuf) end
						flow.addCar(smp, zoneBuf, n, speed, ts, partBuf, dirBuf)
						-- thru: every driver read, or the stride's id subset (counted x stride)
						if x ~= nil and st.trackIndex ~= nil then
							local m = flow.zonesAt(st.trackIndex, x, y, trackBuf)
							-- by position: on its way in (an inbound approach or the junction) at this sample
							for j = 1, m do
								local k = trackBuf[j]
								local z = st.zones[k]
								local a = smp.zones[k]
								if z ~= nil and a ~= nil then
									local part = flow.approachOf(z, x - z.x, y - z.y)
									if part ~= nil and part >= 0 then a.posIn[e] = part end
								end
							end
							-- by path (while path elements read and the path thru is on); path reads count against the frame's
							-- budget: the clock after every driver near a zone, whatever it read
							if not st.pathOff and (m > 0 or st.prevAheadOf[e] ~= nil) then
								thruCheck(smp, e, mp, m)
							end
							if (m > 0 or st.prevAheadOf[e] ~= nil) and rt.nowUs() - t0 >= fl.BUDGET_US then return false end
						end
					end
				end
			end
		end
	end
	return true
end

local function formatSweep(sw : Sweep)
	local smp = sw.sample
	local cost : SquareStressFlowSweepCost = { persons = #(sw.persons or {}), frames = sw.frames, busyUs = sw.busyUs,
		elapsedUs = rt.nowUs() - sw.startUs, frameMaxUs = sw.frameMaxUs, framePhase = sw.frameMaxPhase }
	st.prevDrivers = smp.drivers
	st.s = st.s + 1
	local out : {string} = {}
	-- thru: the drivers this junction had ahead last sample that it has passed now, among the same drivers: both
	-- samples every driver (stride 1, nothing cut by the target), or the same id subset (the same stride: x stride)
	local stride = math.max(1, sw.stride or 1)
	local complete = stride > 1 or smp.sampled >= smp.drivers
	local both = complete and st.prevComplete and st.prevSample ~= nil and st.prevStride == stride
	local thruS : number = (both and st.prevGt ~= nil) and (sw.gt - st.prevGt) / flow.GT_PER_S or nil
	for i, z in ipairs(st.zones) do
		-- thru: by position (primary); thru_path: by the drivers' paths while path elements read
		local thru = both and flow.posCount(st.prevSample.zones[i], smp.zones[i], true) or nil
		if thru ~= nil then thru = thru * stride end
		local tp = (both and not st.pathOff) and flow.thruCount(st.prevSample.zones[i], smp.zones[i], true) or nil
		if tp ~= nil then tp = tp * stride end
		out[#out + 1] = flow.flowLine(st.run, st.s, sw.gt, z, smp.zones[i], thru, thru ~= nil and thruS or nil, thru ~= nil and stride or nil, tp)
	end
	st.prevStride = stride
	local aheadOf : {integer : {integer}} = {}
	for i, a in ipairs(smp.zones) do
		for d in pairs(a.ahead or {}) do
			aheadOf[d] = aheadOf[d] or {}
			table.insert(aheadOf[d], i)
		end
	end
	st.prevSample, st.prevComplete, st.prevGt, st.prevAheadOf = smp, complete, sw.gt, aheadOf
	out[#out + 1] = flow.allLine(st.run, st.s, sw.gt, smp, cost)
	for _, l in ipairs(sw.busLines or {}) do out[#out + 1] = l end
	for _, l in ipairs(sw.townLines or {}) do out[#out + 1] = l end
	if traffic.ui.keepCleared then
		st.totals.warn["keep_cleared"] = (st.totals.warn["keep_cleared"] or 0) + 1
		if not st.keepWarned then
			st.keepWarned = true
			warnKeepCleared()
		end
	end
	flow.addSample(st.totals, sw.gt, smp, cost)
	sw.out, sw.outCursor = out, 1
	st.lastMs, st.lastFrames, st.lastDrivers = sw.busyUs / 1000, sw.frames, smp.drivers
end

--- One frame of the sweep: its current phase only.
local function step(sw : Sweep, now : integer)
	local t0 = rt.nowUs()
	local phase = sw.phase
	if phase == "list" then
		local ok, l = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.SIM_PERSON)
		sw.persons = (ok and l ~= nil) and l as {integer} or {}
		if not ok then st.totals.warn["no_person_list"] = (st.totals.warn["no_person_list"] or 0) + 1 end
		sw.cursor = 1
		sw.setCursor = 1
		sw.phase = "sets"
	elseif phase == "sets" then
		-- the junctions' streets read fresh every sweep (a lock pass or a rebuild gives them new ids), a few zones
		-- per frame within the budget (not in the person list's frame: that one is busy already)
		-- (only for the path thru; at most SETS_PER_FRAME zones a frame: one zone's octree read can be long)
		local n = 0
		while not st.pathOff and sw.setCursor <= #st.zones and n < SETS_PER_FRAME and rt.nowUs() - t0 < fl.BUDGET_US do
			st.thruSets[sw.setCursor] = thruSetOf(st.zones[sw.setCursor])
			sw.setCursor = sw.setCursor + 1
			n = n + 1
		end
		if st.pathOff then sw.setCursor = #st.zones + 1 end
		if sw.setCursor > #st.zones then sw.phase = "scan" end
	elseif phase == "scan" then
		if scanSlice(sw, t0) then sw.phase = "buslist" end
	elseif phase == "buslist" then
		sw.buses, sw.busCursor, sw.busLines = sqstLines(), 1, {}
		sw.phase = "bus"
	elseif phase == "bus" then
		while sw.busCursor <= #sw.buses and rt.nowUs() - t0 < fl.BUDGET_US do
			local okB, text = pcall(busLineText, sw.buses[sw.busCursor], sw.gt, st.s + 1)
			if okB and text ~= nil then sw.busLines[#sw.busLines + 1] = text end
			sw.busCursor = sw.busCursor + 1
		end
		if sw.busCursor > #sw.buses then sw.phase = "towns" end
	elseif phase == "towns" then
		sw.phase = "format"
		if now >= st.nextTownsUs then
			local a = rt.nowUs()
			local ok, m = pcall(api.engine.util.town.computeTownsTrafficSpeedMap, 1.0)
			local ms = (rt.nowUs() - a) / 1000
			-- a slow call (> TOWNS_SLOW_MS) drops to every TOWNS_SLOW_EVERY_US (FLOW.md FLOW_TOWNS)
			st.townsEveryUs = ms > fl.TOWNS_SLOW_MS and fl.TOWNS_SLOW_EVERY_US or fl.TOWNS_EVERY_US
			st.nextTownsUs = now + st.townsEveryUs
			if ok and m ~= nil then
				sw.townLines = flow.townsLines(st.run, st.s + 1, sw.gt, m as {integer : {any}}, 1.0, math.floor(ms * 100 + 0.5) / 100,
					function(t : integer) : string return entityName(t) end)
			else
				st.totals.warn["towns_failed"] = (st.totals.warn["towns_failed"] or 0) + 1
			end
		end
	elseif phase == "format" then
		formatSweep(sw)
		sw.phase = "write"
	elseif phase == "write" then
		local last = math.min(#sw.out, sw.outCursor + fl.WRITES_PER_FRAME - 1)
		for i = sw.outCursor, last do write(sw.out[i]) end
		sw.outCursor = last + 1
		if sw.outCursor > #sw.out then
			sw.phase = "done"
			if st.s % flow.SUMMARY_EVERY == 0 then summary(false) end
			rt.version = rt.version + 1
		end
	end
	-- busy time of every phase; FLOW_ALL / the totals get it as of the format frame (the writes come after)
	local spent = rt.nowUs() - t0
	sw.busyUs = sw.busyUs + spent
	if spent > (sw.frameMaxUs or 0) then
		sw.frameMaxUs = spent
		sw.frameMaxPhase = phase
	end
	sw.frames = sw.frames + 1
end

function fl.tick(now : integer)
	if not st.active then return end
	if rt.queueClears ~= st.clearsSeen then
		fl.ui.on = false
		stopRun("queue cleared")
		return
	end
	local gt = gameTime()
	local sw = st.sweep
	if sw ~= nil then
		if gt ~= nil and st.nextDueGt ~= nil and gt >= st.nextDueGt then
			-- due again while this sweep runs: that sample is skipped, and (once per sweep) the run's target drops
			-- to what this sweep read in its interval x TARGET_DROP, so the next sweeps finish in time
			st.totals.skipped = st.totals.skipped + 1
			st.nextDueGt = st.nextDueGt + intervalS() * flow.GT_PER_S
			if not sw.lowered then
				sw.lowered = true
				local was = st.target
				local read = sw.sample ~= nil and sw.sample.sampled or 0
				st.target = flow.lowerTarget(was, read)
				write(flow.targetLine(st.run, st.s + 1, st.target, was, read, st.prevDrivers, "skipped"))
			end
		end
		local okS, errS : boolean, any = pcall(step, sw, now)
		if not okS then
			-- a phase that throws would repeat every frame: drop this sweep (counted), the next one starts fresh
			st.totals.warn["sweep_error"] = (st.totals.warn["sweep_error"] or 0) + 1
			rt.detail("[SQST] traffic log sweep error: " .. tostring(errS))
			sw.phase = "done"
		end
		if sw.phase == "done" then
			st.sweep = nil
			-- a lowered target comes back up when this sweep (one that ran through, its path reads included) projects
			-- the raised one to finish within half the interval: its game time x the drivers it would read / those it
			-- read (2026-10-13 review: judged on time alone, the raise to every driver flapped)
			local smp = sw.sample
			if okS and st.target ~= nil and not sw.lowered and gt ~= nil and sw.gt ~= nil and smp ~= nil then
				local was = st.target
				local nt = flow.raiseTarget(was, st.prevDrivers)
				local count = nt or st.prevDrivers or 0
				if flow.raiseOk(gt - sw.gt, smp.sampled, count, intervalS() * flow.GT_PER_S) then
					st.target = nt
					write(flow.targetLine(st.run, st.s + 1, st.target or 0, was, smp.sampled, st.prevDrivers, "recovered"))
				end
			end
		end
		return
	end
	-- idle: a new Showcase (or its zones cleared) starts a new run once no test build runs
	if now >= st.nextZoneCheckUs then
		st.nextZoneCheckUs = now + ZONE_CHECK_US
		if sessionSig() ~= st.zoneSig and rt.busyJob(rt.TEST_JOBS) == nil then
			stopRun("zones changed")
			startRun()
			return
		end
	end
	if gt == nil or (st.nextDueGt ~= nil and gt < st.nextDueGt) then return end
	local stepGt = intervalS() * flow.GT_PER_S
	st.nextDueGt = (st.nextDueGt or gt) + stepGt
	if st.nextDueGt <= gt then st.nextDueGt = gt + stepGt end   -- after a long gap (a stall): no burst
	local smp = flow.newSample(#st.zones)
	smp.target = st.target
	smp.stride = flow.stride(st.target, st.prevDrivers)
	st.sweep = { gt = gt, phase = "list", startUs = now, busyUs = 0, frames = 0, frameMaxUs = 0, cursor = 1, sample = smp,
		target = st.target, stride = smp.stride, lowered = false }
end

rt.addTickHook(function(now : integer) fl.tick(now) end)

return fl
