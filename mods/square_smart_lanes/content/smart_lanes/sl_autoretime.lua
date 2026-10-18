-- Smart Lanes "Keep timing adjusted" (rev 8 step B v4, plans/square_smart_lanes/RETIME_PLAN.md "Step B v4: queue
-- snapshots"; PLAN.md "Keep timing adjusted"): the runtime that re-times the enrolled junctions (sl_auto.lua: the saved
-- list) now and then, without the tool open. Low importance in the game (user 2026-10-15): it keeps the lights
-- reasonable over a long game, occasionally; no continuous measuring. GUI thread: stepped every frame by the
-- background plugin (sl_bg.script.lua, R.step); every engine read is pcall'd; nothing here throws out of R.step (the
-- plugin pcalls it too).
--
-- Idle (user 2026-10-17, a player's "stutter fest" report while nothing was opted in): while no junction is enrolled
-- under Junctions I choose (no sl_auto zone, no listing, snapshot, pending write or new-light look either), or while
-- the mode in force is Off (sl_allmode.lua), a frame does nothing but count: the mirror and the zones are read every
-- IDLE_FRAMES frames (not MIRROR_FRAMES / ZONES_FRAMES), unsent records go out, and the new-light look still runs
-- (its Smart lights plans are not timing). Off also drops a snapshot or a wanted write in progress and never starts
-- one: nothing is counted, decided or written, and the zones and the listing enroll nothing. R.wake() (the tool, after
-- it sends a SmartLanes.auto event) keeps the busy cadence for IDLE_FRAMES frames, so the change shows soon.
--
-- One frame (R.step), cheapest first:
--   mirror    every MIRROR_FRAMES frames: the saved aseq (one state read); the list and its requests (areq: "decide
--             now", aall: "enroll every lit junction") only when aseq changed. A record per enrolled junction (R.recs,
--             keyed by its position: Auto.posKey), in memory only.
--   zones     every ZONES_FRAMES frames: zseq; one sl_auto zone per frame whose junction is not enrolled yet is looked
--             at (octree BASE_NODE in its circle, at most every ZONE_RECHECK_S game s per zone): its lit junctions are
--             enrolled (SmartLanes.auto add, src=zone).
--   all       an "enroll all" request: the lit nodes (getEntitiesWithComponent(BASE_NODE_TRAFFIC_LIGHT), else the
--             octree around the map centre), ALL_PER_FRAME looked at per frame within ALL_BUDGET_S (the clock checked
--             every CHECK_CALLS nodes), then add events (src=all), at most
--             Auto.MAX in all. All lights (sl_allmode.lua: the setting "Automatic light timing" or the save's amode):
--             the same listing every AllMode.LIST_EVERY_S game s (60 game min; the first right after the mirror is
--             read or the mode turns all; new lights of player builds come at once, "new" below), lights built later
--             included; a node without a standing light (BASE_NODE_TRAFFIC_LIGHT) is passed over with that one read,
--             before its position or config, without the junctions already enrolled, opted out (aout)
--             or timed by hand (AllMode.handTimed); first come up to Auto.MAX (AUTORETIME op=cap_hit, once per
--             session). Its enroll_all phase=done line (run=allmode) only when it sent or capped something (and the
--             first time in a session).
--   new       all lights, new lights at once (sl_allmode.lua "New lights at once"): the nodes recent player builds
--             touched (the saved alit, read with the mirror) are looked at at once, NEW_PER_FRAME a frame: a standing
--             light there, not enrolled, opted out or timed by hand -> enrolled (add src=build); no light yet ->
--             looked at again NEW_RETRY_S game s after the first look, then given up (the listing above stays the
--             safety net). AUTORETIME op=enroll_new src=build ... when it sent, skipped a light or capped something.
--             New lights get Smart lights (sl_allmode.lua): a node saved with the phases look (a config-only build
--             with Light phases = Smart Lanes) whose light still has the game's default phases gets the axis plan
--             first (planLook, W.planLights src=new_light; NEW_PLANS_PER_FRAME a frame), its enrollment look 3 s later.
--   snapshot  every SNAP_EVERY_S game s: the cars standing (speed < STAND_SPEED, timeStanding >= QUEUE_STAND s) on each
--             approach of every watched junction, counted in ONE pass over the drivers (no route reads): a car counts
--             at a junction when it lies on an approach's queue corridor (Retime.onCorridor: the inbound half of a
--             strip CORRIDOR_HALF m to each side of the arm's axis, BOX..QUEUE_LEN m out, no further than the next node;
--             the Stress Test's arm corridors, plans/square_stress_test/FLOW.md "Measured area"). The drivers: the
--             routed lists of the junctions' approach segments when there are at most ROUTED_ENTS_MAX of them (cheap
--             for a few junctions), else the whole SIM_PERSON list (one engine call, then one SIM_PERSON read per
--             person; a grid of CELL m finds the junctions near a car, so hundreds of junctions cost about what a few
--             do). Spread over frames within BUDGET_S each (the clock checked every CHECK_CALLS engine calls; every
--             budget here is wall time, api.type.Clock: T.wallClock). The line logs fetch_ms (the list calls alone)
--             and finish_ms (the averages and wake checks of every member, in the frame the reads end).
--             Per junction and approach the count becomes an arrival estimate under the timing in force
--             (Retime.arrivalOf), averaged over the snapshots (exponential, time constant TAU_S; a running mean
--             for the first ones).
--   looks     LOOKS_PER_FRAME records per frame (round robin) are checked; the ones due for a refresh (REFRESH_S, or
--             only with the next decision after one that kept the timing: quiet, fits, small;
--             resolve / re-attach / prune, light read, adopt, the corridors and the timing) or a decision (MIN_SNAPS
--             snapshots, Retime.planQueue on the averages: cycle rule v3, damping, hysteresis HYST_ABS / HYST_REL)
--             wait in R.dueSet; each frame runs them oldest due first within HEAVY_BUDGET_S (at least one, at most
--             HEAVY_MAX), none while a snapshot reads or in a frame that wrote; the rest carry to the next frames
--             (city run 2026-10-15: 30 ms frames when 243 junctions came due together). A junction's first decision
--             is spread over one snapshot interval (T.firstDelay, from its position). A wanted write waits in
--             R.pending. The snapshot line reports heavy= (steps since the last snapshot) and backlog= (the most
--             carried over at once).
--   writes    at most one per WRITE_GAP_S game s map-wide, the pending one of the largest expected gain first; held
--             (op=hold) while the player builds within BUILD_R m or a tool proposal is pending there, dropped after
--             PENDING_MAX_S (op=skip reason=stale). Per junction at most one write (ours or a hand edit) per
--             Auto.EVERY_WRITE (times the interval factor, below).
--   records   the outcome of every decision and write ("last measured": Auto.record, src auto) goes to the saved
--             rlast list, sent in batches every LAST_FLUSH_S game s (SmartLanes.auto op=last).
--
-- Writes (W.retimeLights, durations only) only when the plan changed a phase by the hysteresis, the phases and lanes
-- read at the decision still stand (the signature is re-checked by the write), no tool proposal is pending there, the
-- player is not building nearby (R.setBuild: the construction menu open with its cursor near, BUILD_HOLD_S after). The
-- cycle moves at most MAX_CYCLE_STEP s per write.
-- Adopt: phases whose structure (lockedLanes, canSkip, count) or durations changed by something other than our write
-- become the new base (AUTORETIME op=adopt): only lengths are ever written, never the structure; the junction then
-- waits Auto.EVERY_WRITE (scaled) before our next write. Lanes changed (the connections): its averages start again
-- (op=reset).
-- Intervals between decisions (Auto.nextEvery): a write -> 10 game min; fits / too little traffic -> 10, 20, 40, 60
-- (cap); a long cycle not confirmed yet -> 5 min. All times the setting "Keep timing adjusted: check interval"
-- (sqrl_auto_every, x0.5 / x1 / x2 / x4, or this save's in-game setting, sl_settings.lua; Auto.setEveryFactor, set in
-- T.new from getModParams of this Lua state and again when the in-game setting changes, x1 when unreadable;
-- AUTORETIME op=config every_factor= [src=save]); retries (Auto.RETRY_S), snapshots and averages unscaled.
-- Early wake (wakeCheck, T.WAKE_*; AUTORETIME op=wake reason=quiet_rise | fits_grow | fits_shift): after each snapshot,
-- a junction whose last decision was quiet (standing cars below quietQueue) or fits is due at once when its averaged
-- standing cars rose to 1.5 x quietQueue (quiet), grew by half and at least 1.5 cars to at least 3 (fits), or an
-- approach's share of them moved by more than 0.2 and at least 1.5 cars with at least 3 standing (fits); never within
-- the write gap after its last write, at most once per decision. Only the averages the snapshot just updated are
-- compared (no game reads).
-- Nothing of this is saved but the list itself and the records: after a load the averages start again (MIN_SNAPS
-- snapshots before the first decision).
--
-- Log: [SQRL] AUTORETIME op=<op> ... (PLAN.md "Logging"); zid= on the lines of junctions in a zone with an id, also
-- on the write's LIGHTS ... to=retime action=auto line.

local Retime = ug_require "square_smart_lanes::/smart_lanes/sl_retime.lua"
local Retimer = ug_require "square_smart_lanes::/smart_lanes/sl_retimer.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Kept = ug_require "square_smart_lanes::/smart_lanes/sl_kept.lua"

local T = {}

-- snapshots
T.SNAP_EVERY_S = 120     -- game s between snapshots (a snapshot that takes longer delays the next one)
T.TAU_S = 1200           -- game s, the averages' time constant (20 game min)
T.MIN_SNAPS = 8          -- snapshots before the first decision (16 game min)
T.BUDGET_S = 0.001       -- s of clock per frame for a snapshot
T.CHECK_CALLS = 8        -- engine calls between clock checks
T.ROUTED_ENTS_MAX = 48   -- approach segments up to which the routed lists are read (else the SIM_PERSON list)
T.CAND_MAX = 60000       -- routed candidates per snapshot (deduplicated)
T.SCAN_MAX = 400000      -- persons of the SIM_PERSON list read (a safety stop)
T.QUEUE_LEN = 150        -- m, a corridor's reach from the junction (no further than the next node)
T.CORRIDOR_HALF = 12     -- m to each side of an arm's axis
T.BOX = 6                -- m from the centre: the junction itself, not an approach
T.CELL = 200             -- m, the grid of junctions (at least QUEUE_LEN + CORRIDOR_HALF)
T.STAND_SPEED = 0.5      -- m/s
T.QUEUE_STAND = 5        -- s of timeStanding (the Stress Test's queue)
T.ARMS_MAX = 8
-- records, decisions, writes
T.REFRESH_S = 300        -- game s between refreshes of a watched junction (light read, corridors, timing)
T.LOOKS_PER_FRAME = 32
T.HEAVY_BUDGET_S = 0.001 -- s of clock per frame for refreshes and decisions (at least one, at most HEAVY_MAX)
T.HEAVY_MAX = 4
T.WRITE_GAP_S = 5        -- game s between two writes map-wide
T.PENDING_MAX_S = 120    -- game s a wanted write may wait (building nearby, a tool proposal) before it is dropped
T.LAST_FLUSH_S = 30      -- game s between batches of last-measured records
T.MAX_CYCLE_STEP = 20
T.SMOOTH = 0.5           -- weight of a decision's loads against the junction's previous decision (R.plan smooth)
T.HIST_MAX_S = 3600      -- a previous decision older than this is not used (smoothing, confirmation)
T.HYST_ABS = 4           -- s: a veh phase must move by max(HYST_ABS, HYST_REL x its length) for a write
T.HYST_REL = 0.2
-- early wake (between decisions, after a snapshot; at most one per decision): a junction last decided quiet whose
-- standing cars (all approaches, the averages) rose to WAKE_QUIET_X x quietQueue (sl_retime, 1 car), or decided "fits"
-- whose standing cars grew by WAKE_GROW_REL and at least WAKE_GROW_ABS cars to at least WAKE_MIN_CARS, or whose
-- approaches' shares of them moved by more than WAKE_SHIFT (share points, as HYST_REL) and by at least WAKE_SHIFT_CARS
-- cars (the share moved x the standing cars now), with at least WAKE_MIN_CARS standing at the decision and now, is
-- decided at the next look (never within the write gap). City run 2 (RESULTS.md "City lights at scale, run 2"): 45
-- fits wakes at 1-6.6 standing cars (share moves 0.20-0.35 = 0.2-1.4 cars) re-decided "fits" 44 times; the minimums
-- keep its 6 quiet_rise wakes (5 wrote) and drop those 45.
T.WAKE_QUIET_X = 1.5
T.WAKE_GROW_REL = 0.5
T.WAKE_GROW_ABS = 1.5
T.WAKE_SHIFT = 0.2
T.WAKE_MIN_CARS = 3
T.WAKE_SHIFT_CARS = 1.5
T.LINES_MAX = 4000       -- AUTORETIME lines per session (plan, snapshot, skip, ...)
T.KEY_LINES_MAX = 4000   -- ...and of the lines tools/flow_report.py reads (write, enroll_all), counted apart
T.MIRROR_FRAMES = 30
T.ZONES_FRAMES = 120
T.IDLE_FRAMES = 300      -- frames between mirror and zone reads while idle (nothing enrolled, or Off)
T.ZONE_RECHECK_S = 30
T.ZONE_NODES_MAX = 64    -- nodes read per sl_auto zone look
T.ALL_PER_FRAME = 64
T.ALL_BUDGET_S = 0.001   -- s of clock per frame for the listing's reads (at least one node a frame; user 2026-10-17:
                         -- 2.4-2.9 ms frames listing 3642 octree nodes, game log 2026-10-17 22:14-22:22Z)
T.ALL_LIST_MAX = 200000
T.ALL_R = 20000          -- m: the octree fallback's circle around (0, 0) (a 16 / 20 km map fits)
T.BUILD_R = 300
T.BUILD_HOLD_S = 30
-- lightRead reasons that end an entry (no lit junction at the spot any more); others (stale_conns, crosswalks: a write
-- landing) retry
T.PRUNE_WHY = { no_light = true, no_phases = true, no_config = true }
local KEY_OPS = { write = true, enroll_all = true }

--- The delay (game s, 0 .. SNAP_EVERY_S) of a junction's first decision once it has enough snapshots, from its
-- position key: junctions enrolled together don't all come due in one frame.
function T.firstDelay(key)
	local h = 0
	local s = tostring(key)
	for i = 1, math.min(#s, 64) do h = (h * 31 + s:byte(i)) % 1000003 end
	return (h % 1000) / 1000 * T.SNAP_EVERY_S
end

local function structSig(states)
	local parts = { tostring(#states) }
	for i, st in ipairs(states) do
		if i > 64 then break end
		local l = {}
		for j, x in ipairs(st.locked or {}) do
			if j > 512 then break end
			l[#l + 1] = tostring(x)
		end
		parts[#parts + 1] = tostring(st.canSkip == true) .. ":" .. table.concat(l, ",")
	end
	return table.concat(parts, ";")
end
T.structSig = structSig

local function durText(states)
	local d = {}
	for i, st in ipairs(states) do d[i] = st.duration end
	return Retime.listText(d)
end

local function sortedKeys(t)
	local list = {}
	for k in pairs(t) do list[#list + 1] = k end
	table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	return list
end

--- The arms of node n whose cars can queue into it (an approach: incoming car lanes), as queue corridors
-- (Retime.onCorridor): { seg, ux, uy, len, half, box, side }. Outwards along the segment's tangent at the node (its
-- chord when unread); len up to QUEUE_LEN and no further than the segment's other end; side from the lanes (+1
-- right-hand traffic: incoming lanes on the lower indices, as sl_slip S.sideOf; -1 left-hand; 0 one-way in or mixed:
-- both halves). world: sl_write's world, nd = world.node(n).
function T.armsOf(world, n, nd)
	local arms = {}
	for _, sid in ipairs(nd.segs or {}) do
		if #arms >= T.ARMS_MAX then break end
		local s = world.seg(sid)
		local la = s and Ring.lanesAt(s, n) or nil
		if la ~= nil and #la.incoming > 0 then
			local atStart = s.node0 == n
			local t = atStart and s.t0 or s.t1
			local far = atStart and s.p1 or s.p0
			local fx, fy = (far and far.x or nd.x) - nd.x, (far and far.y or nd.y) - nd.y
			local chord = math.sqrt(fx * fx + fy * fy)
			local ux, uy = fx, fy
			if t ~= nil and type(t.x) == "number" and type(t.y) == "number" and t.x * t.x + t.y * t.y > 1e-9 then
				ux, uy = t.x, t.y
				if not atStart then ux, uy = -ux, -uy end
			end
			local l = math.sqrt(ux * ux + uy * uy)
			if l > 1e-6 and chord > 1e-6 then
				local side = 0
				if #la.outgoing > 0 then
					if la.incoming[#la.incoming] < la.outgoing[1] then side = 1
					elseif la.incoming[1] > la.outgoing[#la.outgoing] then side = -1 end
				end
				arms[#arms + 1] = { seg = sid, ux = ux / l, uy = uy / l, len = math.min(T.QUEUE_LEN, chord),
					half = T.CORRIDOR_HALF, box = T.BOX, side = side }
			end
		end
	end
	return arms
end

--- A wall clock in seconds (api.type.Clock, findings "Timers and threads"), and its name: "wall", or "os" (os.clock)
-- when the api has no Clock. os.clock is the process CPU time of all threads on macOS: city run 2 logged snapshot
-- frames of 49.2 and 81.5 "ms" by it where SQPERF's wall clock saw at most 13.8 ms in those 30 s windows, and every
-- budget ran out early by the same factor (docs/findings/gui.md "Timers").
function T.wallClock(api)
	local ok, c = pcall(function() return api.type.Clock.new() end)
	if ok and c ~= nil and pcall(function() return c:getTime() end) then
		return function() return c:getTime() / 1000000 end, "wall"
	end
	return os.clock, "os"
end

--- api: game api (or fake); out(kind, fields): log; clock(): seconds (nil: T.wallClock; tests pass a fake); opts:
-- { now (game s; tests), toolBusy(node) (a proposal of the tool pending, or its Re-time at node), manualBusy() (any
-- of the tool's Re-time runs measures: no snapshot starts meanwhile), lastSent(records) (each new last-measured record, before
-- its batch is sent: the tool's mirror, sl_toolcore C.noteLast) }.
function T.new(api, out, clock, opts)
	opts = opts or {}
	local clockSrc = "given"
	if clock == nil then clock, clockSrc = T.wallClock(api) end
	local R = { frames = 0, recs = {}, order = {}, cursor = 0, lines = 0, keyLines = 0,
		mirror = { seq = nil, idx = Auto.index(nil), frame = -math.huge, read = false },
		zones = {}, zseq = nil, autoZones = {}, zoneCursor = 0, build = {}, snap = nil, nextSnapAt = -math.huge,
		pending = {}, lastWriteAt = -math.huge, outRecs = {}, flushAt = -math.huge, snaps = 0, dueSet = {}, heavyN = 0,
		backlogMax = 0, wroteFrame = nil, newQ = AllMode.newQueue(), litSeq = nil, mode = nil, wakeUntil = nil,
		kept = { seq = nil, idx = Kept.index(nil), read = false }, planLines = 0 }
	local CT = api.type.ComponentType
	-- the light reads and the write (zid= on its LIGHTS line through `log`)
	local log
	local W = Write.new(api, function(kind, fields) return log(kind, fields) end,
		{ probeOn = function() return false end })
	R.W = W
	-- the snapshot's driver reads (sl_retimer's; its M.run is pointed at the snapshot for the call count)
	local H = Retimer.new(api, clock, function() return nil end)
	local driveValue = nil
	local planOpts = { maxCycleStep = T.MAX_CYCLE_STEP, smooth = T.SMOOTH, confirmLong = true, hystAbs = T.HYST_ABS,
		hystRel = T.HYST_REL, minSnaps = T.MIN_SNAPS, queueStand = T.QUEUE_STAND }

	function R.now()
		if opts.now ~= nil then
			local v = opts.now()
			if type(v) == "number" then return v end
		end
		local ok, gt = pcall(function()
			return api.engine.getComponent(api.engine.util.getWorld(), CT.GAME_TIME).gameTime
		end)
		if ok and type(gt) == "number" then return gt / 1000 end
		return clock()
	end

	--- zid= of a position (the zones last read).
	local function zidAt(x, y)
		if #R.zones == 0 or x == nil then return nil end
		return Zones.idOf(Zones.zoneAt(R.zones, x, y))
	end
	local function nodePos(n)
		local ok, p = pcall(function()
			local bn = api.engine.getComponent(n, CT.BASE_NODE)
			return bn and bn.position
		end)
		if not ok or p == nil or type(p.x) ~= "number" then return nil end
		return p
	end
	log = function(kind, fields)
		if (kind == "LIGHTS" or kind == "SKIP") and #R.zones > 0 and type(fields) == "table" then
			local node, has = nil, false
			for _, kv in ipairs(fields) do
				if kv[1] == "node" and type(kv[2]) == "number" then node = kv[2] end
				if kv[1] == "zid" then has = true end
			end
			local p = (node ~= nil and not has) and nodePos(node) or nil
			local id = p and zidAt(p.x, p.y) or nil
			if id ~= nil then fields[#fields + 1] = { "zid", id } end
		end
		return out(kind, fields)
	end
	--- An AUTORETIME line: op first, then node / pos, the fields, zid=. At most LINES_MAX per session, the lines
	-- tools/flow_report.py reads (KEY_OPS) KEY_LINES_MAX apart, so the plan lines of many junctions never hide them.
	local function line(op, rec, fields, node)
		local key = KEY_OPS[op] == true
		if key then
			if R.keyLines >= T.KEY_LINES_MAX then return end
			R.keyLines = R.keyLines + 1
		else
			if R.lines >= T.LINES_MAX then return end
			R.lines = R.lines + 1
		end
		local f = { { "op", op } }
		if rec ~= nil then
			f[#f + 1] = { "node", node or rec.n }
			f[#f + 1] = { "pos", rec.key }
		end
		for _, kv in ipairs(fields or {}) do f[#f + 1] = kv end
		if (key and R.keyLines == T.KEY_LINES_MAX) or (not key and R.lines == T.LINES_MAX) then
			f[#f + 1] = { "more", "suppressed" }
		end
		local id = rec ~= nil and zidAt(rec.x, rec.y) or nil
		if id ~= nil then f[#f + 1] = { "zid", id } end
		out("AUTORETIME", f)
	end
	R.line = line

	-- The setting "Keep timing adjusted: check interval" and Light phases: the mod params (fixed for a session; x1 when
	-- this Lua state cannot read them) with the save's in-game settings (sl_settings.lua), derived again whenever
	-- those change (Settings.mirror.version, polled in R.step): AUTORETIME op=config ... src=save.
	local function deriveConfig(first)
		local ok, all = pcall(function() return api.engine.config.getModParams() end)
		local raw = ok and type(all) == "table" and all[Rules.MOD_ID] or nil
		local eff = Settings.merged(raw, Settings.overNow())
		R.setVer = Settings.mirror.version
		local factor = Auto.setEveryFactor(Auto.everyFactorOf(eff))
		local sl = Rules.fromModParams(eff).phases == "sl"
		-- "Automatic light timing" (sl_allmode.lua): the mod setting; the save's override is the mirror's amode
		R.allSetting = AllMode.settingOf(raw)
		if not first and factor == R.everyFactor and sl == R.slPhases then return end
		R.everyFactor = factor
		-- Light phases (Smart Lanes plans are whole seconds: never "timed by hand" then)
		R.slPhases = sl
		local f = { { "every_factor", R.everyFactor }, { "params", ok and "read" or "unread" },
			{ "clock", clockSrc }, { "lights", R.allSetting } }
		if not first then f[#f + 1] = { "src", "save" } end
		line("config", nil, f)
	end
	R.deriveConfig = deriveConfig
	deriveConfig(true)

	--- Sends a SmartLanes.auto event (never throws).
	local function send(payload)
		local ok, e = pcall(function()
			local cmd = api.cmd
			if cmd == nil or cmd.makeScriptingSendEventCmd == nil then return end
			cmd.sendCommand(cmd.makeScriptingSendEventCmd("", Auto.EVENT_ID, Auto.EV_AUTO, payload))
		end)
		if not ok then out("ERROR", { { "where", "auto_send" }, { "err", tostring(e) } }) end
	end
	R.send = send

	--- The saved record of junction rec (rlast, re-read only when lseq changed; shared with the new-light look), nil
	-- when none.
	local function savedRecord(rec)
		local lseq, last = Auto.readLast(api, R.newLastSeq)
		if last ~= nil then R.newLastSeq, R.newLastIdx = lseq, Auto.lastIndex(last) end
		return Auto.match(R.newLastIdx, rec.n, rec.x, rec.y)
	end

	--- A last-measured record of rec (sent with the next batch; the latest per junction). written: the durations our
	-- write set (the record's signature, Auto.durSig: Smart lights tells our timing from the player's by it); a
	-- not-written outcome carries the previous record's (this runtime's unsent one, else the saved one; cur: the
	-- durations now, for a 7-field saved record). A written record goes out at once (one write per WRITE_GAP_S
	-- map-wide), and every record is handed to the tool of this Lua state (opts.lastSent) for its status.
	local function addRecord(rec, kind, c0, c1, written, cur)
		local d
		if kind == "written" then d = Auto.durSig(written) or 0
		else
			local okS, prev = pcall(function() return R.outRecs[rec.key] or savedRecord(rec) end)
			d = Auto.carrySig(okS and prev or nil, cur)
		end
		local r = Auto.record(rec.n, rec.x, rec.y, R.now(), "auto", kind, c0, c1, d)
		if r == nil then return end
		R.outRecs[rec.key] = r
		if kind == "written" then R.flushAt = -math.huge end
		if opts.lastSent ~= nil then pcall(opts.lastSent, { r }) end
	end

	local function flush(now)
		if next(R.outRecs) == nil or now < R.flushAt then return end
		R.flushAt = now + T.LAST_FLUSH_S
		local list = {}
		for _, k in ipairs(sortedKeys(R.outRecs)) do list[#list + 1] = R.outRecs[k] end
		R.outRecs = {}
		for _, pl in ipairs(Auto.payloads("last", list, "auto")) do send(pl) end
	end
	R.flush = function() R.flushAt = -math.huge flush(R.now()) end

	---------------------------------------------------------------------------
	-- The mirror of the saved list and its records

	local function recOf(e, now)
		local key = Auto.posKey(e[2], e[3])
		local rec = R.recs[key]
		if rec == nil then
			-- the same junction re-keyed (re-attached at a slightly different position): by id
			for k, r in pairs(R.recs) do
				if r.n == e[1] then
					rec = r
					R.recs[k] = nil
					rec.key = key
					break
				end
			end
		end
		if rec == nil then
			rec = { key = key, n = e[1], x = e[2], y = e[3], snaps = 0, ema = {}, every = Auto.EVERY_FIRST,
				refreshAt = now }
		end
		rec.n, rec.x, rec.y = e[1], e[2], e[3]
		R.recs[key] = rec
		return rec
	end

	local function refreshMirror(now)
		local m = R.mirror
		m.frame = R.frames
		local seq, list, extra = Auto.readSaved(api, m.seq)
		if list == nil then return end
		local first = not m.read
		m.read = true
		m.seq = seq
		m.idx = Auto.index(list)
		local keep = {}
		for _, e in ipairs(m.idx.list) do
			local rec = recOf(e, now)
			keep[rec.key] = true
		end
		for k, rec in pairs(R.recs) do
			if not keep[k] then
				rec.gone = true
				R.recs[k] = nil
				R.pending[k] = nil
			end
		end
		R.order = sortedKeys(R.recs)
		if R.cursor > #R.order then R.cursor = 0 end
		extra = extra or {}
		local req = type(extra.req) == "table" and extra.req or nil
		local reqSeq = req and tonumber(req.seq) or nil
		if first then
			R.reqSeq = reqSeq
		elseif reqSeq ~= nil and reqSeq ~= R.reqSeq then
			R.reqSeq = reqSeq
			for _, ne in ipairs(type(req.nodes) == "table" and req.nodes or {}) do
				local e = Auto.entryOf(ne)
				local hit = e and Auto.match(m.idx, e[1], e[2], e[3]) or nil
				local rec = hit and R.recs[Auto.posKey(hit[2], hit[3])] or nil
				if rec ~= nil then rec.due = now end
			end
		end
		local all = type(extra.all) == "table" and extra.all or nil
		local allSeq = all and tonumber(all.seq) or nil
		if first then
			R.allSeq = allSeq
		elseif allSeq ~= nil and allSeq ~= R.allSeq then
			R.allSeq = allSeq
			R.allJob = { run = tostring(all.run or "-"), phase = "list", cursor = 1, found = {}, lit = 0, already = 0 }
		end
		-- all lights: the mode in force, the opt-outs; a switch to all lists at once
		local was = R.allMode == true
		R.amode = type(extra.mode) == "string" and extra.mode or nil
		R.mode = AllMode.effective(R.allSetting, R.amode)
		R.allMode = R.mode == "all"
		if R.mode == "off" then
			-- nothing counted, decided or written while Off; the averages start again with the next mode
			R.snap, R.pending, R.allJob = nil, {}, nil
		end
		R.outIdx = Auto.index(type(extra.out) == "table" and extra.out or nil)
		if R.allMode and not was then R.nextListAt = now end
		if not R.allMode then R.nextListAt = nil end
		-- all lights, new lights at once: the nodes builds touched since the last read (the first read only takes the
		-- seq: older ones are the listing's)
		-- (new lights get Smart lights: the ids saved with the phases look are queued without all lights too)
		local ids, litSeq, planSet = AllMode.litSince(extra.lit, first and math.huge or R.litSeq)
		if litSeq ~= nil then R.litSeq = litSeq end
		if R.allMode then
			if #ids > 0 then AllMode.queueAdd(R.newQ, ids, now, planSet) end
		else
			local planIds = {}
			for _, id in ipairs(ids) do
				if planSet[id] then planIds[#planIds + 1] = id end
			end
			AllMode.queueKeepPlans(R.newQ)
			if #planIds > 0 then AllMode.queueAdd(R.newQ, planIds, now, planSet) end
		end
	end
	R.refreshMirror = refreshMirror

	--- Whether the saved list holds node n at (x, y) (the mirror as last read).
	function R.enrolled(n, x, y)
		return Auto.match(R.mirror.idx, n, x, y) ~= nil
	end

	---------------------------------------------------------------------------
	-- Zones: sl_auto zones enroll their lit junctions

	local function refreshZones()
		local zs = Zones.readSeq(api)
		if zs == R.zseq and R.zonesRead then return end
		R.zseq, R.zonesRead = zs, true
		R.zones = Zones.readSaved(api) or {}
		local az = {}
		for _, z in ipairs(R.zones) do
			if z.ab == "sl_auto" then az[#az + 1] = { z = z, nextAt = -math.huge, done = false } end
		end
		R.autoZones = az
		R.zoneCursor = 0
	end
	R.refreshZones = refreshZones

	--- The lit junctions (a standing light with phases) among the nodes of a list: { {n, x, y} }.
	local function litOf(list, max)
		local res = {}
		for i, n in ipairs(list or {}) do
			if i > max then break end
			local r = W.lightRead(n)
			if r ~= nil then
				local p = nodePos(n)
				if p ~= nil then res[#res + 1] = { n, p.x, p.y } end
			end
		end
		return res
	end

	local function octreeNodes(x, y, r)
		local ok, list = pcall(function()
			return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), r, CT.BASE_NODE)
		end)
		if ok and type(list) == "table" then return list end
		return nil
	end

	local function zoneStep(now)
		local n = #R.autoZones
		if n == 0 then return false end
		for _ = 1, n do
			R.zoneCursor = R.zoneCursor % n + 1
			local az = R.autoZones[R.zoneCursor]
			if not az.done and now >= az.nextAt then
				az.nextAt = now + T.ZONE_RECHECK_S
				local z = az.z
				local lit = litOf(octreeNodes(z.x, z.y, z.r), T.ZONE_NODES_MAX)
				local add = {}
				for _, e in ipairs(lit) do
					if Auto.match(R.mirror.idx, e[1], e[2], e[3]) == nil then add[#add + 1] = e end
				end
				if #lit > 0 then az.done = true end
				for _, pl in ipairs(Auto.payloads("add", add, "zone")) do send(pl) end
				return true
			end
		end
		return false
	end

	---------------------------------------------------------------------------
	-- "Enroll all": every lit junction on the map

	--- Whether a lit junction (readJunction result rd at node n, (x, y)) counts as timed by hand (AllMode.handTimed):
	-- the flag, no record of ours, whole-second greens, Light phases not Smart Lanes.
	local function handTimedAt(rd, n, x, y, lastIdx)
		local um = nil
		pcall(function() um = rd.r.cfg.userModifiedTrafficLightStates end)
		if um ~= true then return false end
		return AllMode.handTimedOf(um, rd.states, #(rd.connList or {}), #(rd.cws or {}), Retime.kinds,
			Auto.match(lastIdx, n, x, y) ~= nil, R.slPhases)
	end

	--- Whether node n has a standing light (BASE_NODE_TRAFFIC_LIGHT; true when it cannot be told: the full read decides).
	local function litNode(n)
		if CT.BASE_NODE_TRAFFIC_LIGHT == nil then return true end
		local ok, c = pcall(api.engine.getComponent, n, CT.BASE_NODE_TRAFFIC_LIGHT)
		return not ok or c ~= nil
	end

	local function allStep()
		local job = R.allJob
		if job.phase == "list" then
			if job.periodic then
				-- the junctions Smart Lanes measured (both Re-time modes' records): never "timed by hand"
				local _, last = Auto.readLast(api, nil)
				job.lastIdx = Auto.lastIndex(last)
			end
			local ok, list = pcall(api.engine.getEntitiesWithComponent, CT.BASE_NODE_TRAFFIC_LIGHT)
			if ok and type(list) == "table" then
				job.list, job.src = list, "component"
			else
				job.list, job.src = octreeNodes(0, 0, T.ALL_R) or {}, "octree"
			end
			job.phase = "read"
			return
		end
		local list = job.list
		local stop = math.min(#list, T.ALL_LIST_MAX, job.cursor + T.ALL_PER_FRAME - 1)
		local t0 = clock()
		local last = job.cursor - 1
		for i = job.cursor, stop do
			if i > job.cursor and (i - job.cursor) % T.CHECK_CALLS == 0 and clock() - t0 >= T.ALL_BUDGET_S then break end
			last = i
			local n = list[i]
			-- no standing light: passed over with this one read (W.lightRead's own test, before its config read; the
			-- octree list holds every node of the map)
			if type(n) == "number" and n >= 0 and not litNode(n) then n = nil end
			if job.periodic and type(n) == "number" and n >= 0 then
				-- all lights: enrolled and opted-out junctions are not read (cheap: by id or position)
				local p = nodePos(n)
				if p ~= nil then
					if Auto.match(R.mirror.idx, n, p.x, p.y) ~= nil then job.already = job.already + 1
					elseif Auto.match(R.outIdx, n, p.x, p.y) ~= nil then job.optout = job.optout + 1
					else
						local rd = R.readJunction(n)
						if rd ~= nil then
							job.lit = job.lit + 1
							if handTimedAt(rd, n, p.x, p.y, job.lastIdx) then job.hand = job.hand + 1
							else job.found[#job.found + 1] = { n, p.x, p.y } end
						end
					end
				end
			elseif type(n) == "number" and n >= 0 then
				local r = W.lightRead(n)
				if r ~= nil then
					local p = nodePos(n)
					if p ~= nil then
						job.lit = job.lit + 1
						if Auto.match(R.mirror.idx, n, p.x, p.y) ~= nil then job.already = job.already + 1
						else job.found[#job.found + 1] = { n, p.x, p.y } end
					end
				end
			end
		end
		job.cursor = last + 1
		if job.cursor > math.min(#list, T.ALL_LIST_MAX) then
			R.allJob = nil
			-- all lights switched off meanwhile (Stop for all lights): nothing sent
			if job.periodic and not R.allMode then return end
			local room = math.max(0, Auto.MAX - (R.mirror.idx.n or 0))
			local sendList = {}
			for i = 1, math.min(room, #job.found) do sendList[i] = job.found[i] end
			for _, pl in ipairs(Auto.payloads("add", sendList, "all")) do send(pl) end
			local capped = #job.found - #sendList
			if job.periodic then
				if #sendList > 0 or capped > 0 or not R.listLogged then
					R.listLogged = true
					line("enroll_all", nil, { { "phase", "done" }, { "run", job.run }, { "src", job.src }, { "nodes", #list },
						{ "lit", job.lit }, { "already", job.already }, { "optout", job.optout }, { "hand", job.hand },
						{ "sent", #sendList }, { "capped", capped } })
				end
				if capped > 0 and not R.capLogged then
					R.capLogged = true
					line("cap_hit", nil, { { "src", "allmode" }, { "max", Auto.MAX }, { "enrolled", R.mirror.idx.n or 0 },
						{ "capped", capped } })
				end
				return
			end
			line("enroll_all", nil, { { "phase", "done" }, { "run", job.run }, { "src", job.src }, { "nodes", #list },
				{ "lit", job.lit }, { "already", job.already }, { "sent", #sendList }, { "capped", capped } })
		end
	end
	R.allStep = allStep

	--- All lights, new lights at once (AllMode "New lights at once"): the queued nodes of recent builds due now, at most
	-- NEW_PER_FRAME: a standing light with phases there, not enrolled, not opted out, not timed by hand -> enrolled
	-- (SmartLanes.auto add src=build; the game script logs op=enroll ... src=build); no light yet -> looked at again
	-- (AllMode.NEW_RETRY_S), then given up (the periodic listing stays the safety net). AUTORETIME op=enroll_new
	-- src=build checked= sent= already= optout= hand= wait= gaveup= gone= capped= when it sent, skipped a light or
	-- capped something.
	--- New lights get Smart lights (sl_allmode.lua, PLAN.md "New lights get Smart lights"): the Light phases mode at
	-- node n at (x, y): the save's (R.slPhases) unless a zone says otherwise (sl_phases / sl_auto: Smart Lanes;
	-- game / sl_lock / sl_exitfan / sl_fan: never here, the automatic pass and the tool handle those).
	local NO_PLAN_ZONES = { game = true, sl_lock = true, sl_exitfan = true, sl_fan = true }
	local function planWantedAt(world, n)
		local ab = nil
		if #R.zones > 0 then
			local okZ, a = pcall(Zones.nodeAb, R.zones, world, n)
			if okZ then ab = a end
		end
		if ab == "sl_phases" or ab == "sl_auto" then return true end
		if ab ~= nil and NO_PLAN_ZONES[ab] then return false end
		return R.slPhases == true
	end

	--- The tool's Reset kept node n at (x, y) (the saved kept list, re-read when kseq moved).
	local function keptAt(n, x, y)
		local k = R.kept
		local seq, list = Kept.readSaved(api, k.read and k.seq or nil)
		if list ~= nil then
			k.idx = Kept.index(list)
			k.read = true
		end
		if seq ~= nil then k.seq = seq end
		return Kept.match(k.idx, n, x, y) ~= nil
	end

	--- A PHASES src=new_light line (at most AllMode.NEW_PLAN_LINES_MAX per session).
	local function planLine(fields)
		if R.planLines >= AllMode.NEW_PLAN_LINES_MAX then return end
		R.planLines = R.planLines + 1
		if R.planLines == AllMode.NEW_PLAN_LINES_MAX then fields[#fields + 1] = { "more", "suppressed" } end
		log("PHASES", fields)
	end

	--- The phases look at one queued node (it.plan) with its read rd (readJunction): "sent" (the plan went out), or
	-- why not ("off" | "not_x" | "kept" | "busy" | "not_default:<why>" | "same" | "plan_fail:<why>" | "error..").
	-- Never for a node whose phases are not the game's own default: those were timed by hand, re-timed or planned
	-- already (Retime.phasesDefault; the flag userModifiedTrafficLightStates set by any phases write).
	local function planLook(n, p, rd)
		local world = W.makeWorld()
		if not planWantedAt(world, n) then return "off" end
		local okD, isDef, whyD = pcall(Retime.phasesEngineMade, rd.r)
		if not okD or isDef ~= true then return "not_default:" .. tostring(okD and whyD or "error") end
		if keptAt(n, p.x, p.y) then return "kept" end
		if opts.toolBusy ~= nil and opts.toolBusy(n) then return "busy" end
		local okV, v = pcall(Slip.classify, world, n)
		if not okV or type(v) ~= "table" or v.kind ~= "slip" or v.case ~= "X" then return "not_x" end
		local okP, k, why, text, pattern = pcall(W.planLights, n, { view = v, world = world }, "new_light", nil,
			{ { "action", "new_light" } })
		if not okP then return "error:" .. tostring(k) end
		if k > 0 then
			planLine({ { "src", "new_light" }, { "node", n }, { "phases", "sl" }, { "pattern", pattern or "none" },
				{ "plan", text or "-" } })
			return "sent"
		end
		why = tostring(why)
		if why:find("^plan_fail:") then
			-- no axis plan (PLAN.md "No classic fallback"): the game's phases stay
			planLine({ { "src", "new_light" }, { "node", n }, { "phases", "sl" }, { "pattern", "none" },
				{ "plan_fail", (why:gsub("^plan_fail:", "")) } })
		end
		return why
	end
	R.planLook = planLook

	local function newStep(now)
		local q = R.newQ
		if #q.items == 0 then return end
		if not R.allMode then
			-- all lights off: only the Smart lights looks stay
			if AllMode.queueKeepPlans(q) == 0 then return end
		end
		local due = AllMode.queueTake(q, now, AllMode.NEW_PER_FRAME)
		if #due == 0 then return end
		-- the junctions Smart Lanes measured (never "timed by hand"): re-read only when lseq changed
		local lseq, last = Auto.readLast(api, R.newLastSeq)
		if last ~= nil then R.newLastSeq, R.newLastIdx = lseq, Auto.lastIndex(last) end
		local c = { checked = 0, already = 0, optout = 0, hand = 0, wait = 0, gaveup = 0, gone = 0 }
		local pc = { sent = 0, skipped = 0, later = 0, why = {} }
		local found = {}
		for _, it in ipairs(due) do
			local n = it.n
			c.checked = c.checked + 1
			local p = nodePos(n)
			local planned, rd0 = false, nil
			if p ~= nil and it.plan then
				local rd = R.readJunction(n)
				rd0 = rd
				if rd == nil then
					-- no light (with phases) yet: looked at again (the plan look first, then the enrollment)
					if AllMode.queueRetry(q, it, now) then c.wait = c.wait + 1 else c.gaveup = c.gaveup + 1 end
					planned = true
				elseif pc.sent >= AllMode.NEW_PLANS_PER_FRAME then
					-- the frame's proposals used: the next frame (no try counted)
					it.at = now
					if q.byId[n] == nil and #q.items < AllMode.NEW_QUEUE_MAX then
						q.items[#q.items + 1] = it
						q.byId[n] = it
					end
					pc.later = pc.later + 1
					planned = true
				else
					local okL, res = pcall(planLook, n, p, rd)
					it.plan = nil
					if okL and res == "sent" then
						-- the enrollment look after the plan landed (Keep timing adjusted starts from the plan)
						pc.sent = pc.sent + 1
						if R.allMode then AllMode.queueRetry(q, it, now) end
						planned = true
					else
						pc.skipped = pc.skipped + 1
						-- why, for the plan_new line (a few reasons, counted)
						local r = okL and tostring(res) or "error"
						pc.why[r] = (pc.why[r] or 0) + 1
					end
				end
			end
			if planned then
				-- done above
			elseif not R.allMode then
				-- a Smart lights look only
			elseif p == nil then c.gone = c.gone + 1
			elseif Auto.match(R.mirror.idx, n, p.x, p.y) ~= nil then c.already = c.already + 1
			elseif Auto.match(R.outIdx, n, p.x, p.y) ~= nil then c.optout = c.optout + 1
			else
				local rd = rd0 or R.readJunction(n)
				if rd == nil then
					if AllMode.queueRetry(q, it, now) then c.wait = c.wait + 1 else c.gaveup = c.gaveup + 1 end
				elseif handTimedAt(rd, n, p.x, p.y, R.newLastIdx) then c.hand = c.hand + 1
				else found[#found + 1] = { n, p.x, p.y } end
			end
		end
		local room = math.max(0, Auto.MAX - (R.mirror.idx.n or 0))
		local sendList = {}
		for i = 1, math.min(room, #found) do sendList[i] = found[i] end
		for _, pl in ipairs(Auto.payloads("add", sendList, "build")) do send(pl) end
		local capped = #found - #sendList
		if pc.sent > 0 or pc.skipped > 0 then
			local whys, k = {}, 0
			for r, c in pairs(pc.why) do
				k = k + 1
				if k > 6 then break end
				whys[#whys + 1] = r .. ":" .. c
			end
			table.sort(whys)
			line("plan_new", nil, { { "src", "build" }, { "sent", pc.sent }, { "skipped", pc.skipped }, { "later", pc.later },
				{ "why", #whys > 0 and table.concat(whys, ",") or "-" } })
		end
		if R.allMode and (#sendList > 0 or c.hand > 0 or capped > 0) then
			line("enroll_new", nil, { { "src", "build" }, { "checked", c.checked }, { "sent", #sendList },
				{ "already", c.already }, { "optout", c.optout }, { "hand", c.hand }, { "wait", c.wait },
				{ "gaveup", c.gaveup }, { "gone", c.gone }, { "capped", capped } })
		end
		if capped > 0 and not R.capLogged then
			R.capLogged = true
			line("cap_hit", nil, { { "src", "build" }, { "max", Auto.MAX }, { "enrolled", R.mirror.idx.n or 0 },
				{ "capped", capped } })
		end
	end
	R.newStep = newStep

	--- All lights: the periodic listing is due (the mirror read, no listing running).
	local function listDue(now)
		return R.allMode == true and R.allJob == nil and R.mirror.read and R.nextListAt ~= nil and now >= R.nextListAt
	end

	---------------------------------------------------------------------------
	-- The player building nearby (sl_bg.script.lua sets it every frame)

	--- active: the construction menu is open with another tool than Smart Lanes'; x, y: its cursor on the terrain.
	function R.setBuild(active, x, y)
		if active and type(x) == "number" and type(y) == "number" then
			R.build = { x = x, y = y, at = R.now() }
		end
	end
	local function buildNear(x, y, now)
		local b = R.build
		if b.at == nil or now - b.at > T.BUILD_HOLD_S then return false end
		return (b.x - x) ^ 2 + (b.y - y) ^ 2 <= T.BUILD_R * T.BUILD_R
	end
	R.buildNear = buildNear

	---------------------------------------------------------------------------
	-- Reading a junction

	--- The node's phases now: { r, sig, struct, dur, conns (text), connList, cws, states }, or nil, why.
	local function readJunction(node)
		local r, why = W.lightRead(node)
		if r == nil then return nil, why end
		local states = {}
		for i, st in ipairs(r.tlc.states) do
			local l = {}
			for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
			states[i] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip == true }
		end
		return { r = r, sig = W.statesSig(r.tlc), struct = structSig(states), dur = durText(states),
			conns = Rules.connsText(r.conns), connList = r.conns, cws = r.cws, states = states }
	end
	R.readJunction = readJunction

	--- The node at the record's spot: its id when it still stands there, else the nearest node within Auto.R m with a
	-- standing light (re-attach), else nil.
	local function resolve(rec)
		local p = nodePos(rec.n)
		if p ~= nil and (p.x - rec.x) ^ 2 + (p.y - rec.y) ^ 2 <= Auto.R * Auto.R then return rec.n, p end
		local list = octreeNodes(rec.x, rec.y, Auto.R) or {}
		local best, bestP, bestD = nil, nil, nil
		for i, n in ipairs(list) do
			if i > 16 then break end
			local q = nodePos(n)
			if q ~= nil then
				local d = (q.x - rec.x) ^ 2 + (q.y - rec.y) ^ 2
				if d <= Auto.R * Auto.R and (bestD == nil or d < bestD) then best, bestP, bestD = n, q, d end
			end
		end
		return best, bestP
	end
	R.resolve = resolve

	local function prune(rec, reason, n)
		line("prune", rec, { { "reason", reason } }, n)
		send({ op = "remove", src = "prune", nodes = { { rec.n, rec.x, rec.y } } })
		rec.active, rec.refreshAt, rec.due = false, math.huge, nil
		R.pending[rec.key], rec.pending = nil, nil
	end

	--- Refresh of a watched junction: resolve (re-attach, prune), light read, adopt, lanes changed (averages reset),
	-- the corridors and the timing. Returns "ok" | "skip" | "prune".
	local function refresh(rec, now)
		rec.refreshAt = now + T.REFRESH_S
		local n = resolve(rec)
		if n == nil then
			prune(rec, "gone")
			return "prune"
		end
		local rd, why = readJunction(n)
		if rd == nil then
			if T.PRUNE_WHY[why] then
				prune(rec, tostring(why), n)
				return "prune"
			end
			-- a passing state (connections being rewritten): later
			rec.refreshAt = now + Auto.RETRY_S
			line("skip", rec, { { "reason", "read:" .. tostring(why) }, { "retry_s", Auto.RETRY_S } }, n)
			return "skip"
		end
		if n ~= rec.n then
			line("reattach", rec, { { "old", rec.n }, { "new", n } }, n)
			rec.n = n
			send({ op = "update", src = "auto", nodes = { { rec.n, rec.x, rec.y } } })
		end
		-- other lanes: the approaches are other roads now, the averages start again
		if rec.conns ~= nil and rd.conns ~= rec.conns then
			line("reset", rec, { { "reason", "lanes" }, { "snaps", rec.snaps } }, n)
			rec.ema, rec.snaps, rec.hist, rec.due, rec.wake = {}, 0, nil, nil, nil
		end
		-- adopt: the phases changed by something other than our write (the player's Crossing window, Lights only, the
		-- tool's Re-time, the automatic pass's re-plan): the new base, only their lengths are adjusted from now on; our
		-- next write there waits as after one of ours
		if rec.struct ~= nil and (rd.struct ~= rec.struct or (rd.dur ~= rec.dur and rd.dur ~= rec.wrote)) then
			line("adopt", rec, { { "reason", rd.struct ~= rec.struct and "phases" or "durations" }, { "old", rec.dur or "-" },
				{ "new", rd.dur } }, n)
			if rd.struct ~= rec.struct then rec.hist = nil end
			rec.lastWrite = now
			R.pending[rec.key], rec.pending = nil, nil
		end
		rec.struct, rec.dur, rec.sig, rec.conns, rec.rd = rd.struct, rd.dur, rd.sig, rd.conns, rd
		local world = W.makeWorld()
		local nd = world.node(n)
		if nd == nil then
			rec.refreshAt = now + Auto.RETRY_S
			return "skip"
		end
		rec.cx, rec.cy = nd.x, nd.y
		rec.arms = T.armsOf(world, n, nd)
		rec.timing = Retime.timingOf(rd.connList, #rd.cws, rd.states)
		-- pedestrian floors: each crosswalk's crossed road (its segment's road and tram lanes)
		local roadLanes = {}
		for _, cw in ipairs(rd.cws) do
			local sg = world.seg(cw)
			if sg ~= nil then
				local k = 0
				for _, l in ipairs(sg.lanes or {}) do
					if l.road or l.tram then k = k + 1 end
				end
				if k > 0 then roadLanes[cw] = k end
			end
		end
		rec.pedNeed = Retime.pedNeed(rd.cws, roadLanes)
		rec.active = true
		return "ok"
	end
	R.refresh = refresh

	---------------------------------------------------------------------------
	-- Snapshots: the standing cars on every watched junction's approaches, one pass over the drivers

	local function startSnap(now)
		local members, ents = {}, {}
		for _, key in ipairs(R.order) do
			local rec = R.recs[key]
			if rec ~= nil and rec.active and rec.arms ~= nil and #rec.arms > 0 and rec.timing ~= nil then
				members[#members + 1] = { key = key, rec = rec, x = rec.cx, y = rec.cy, arms = rec.arms }
				for _, a in ipairs(rec.arms) do ents[#ents + 1] = { e = a.seg, rec = rec } end
			end
		end
		if #members == 0 then return false end
		local sps = api.engine.system and api.engine.system.simPersonSystem
		local routed = #ents <= T.ROUTED_ENTS_MAX and sps ~= nil and sps.getSimPersonsMovingForTransportNetwork ~= nil
		R.snap = { t0 = now, members = members, idx = Retime.queueIndex(members, T.CELL), counts = {}, phase = "list",
			src = routed and "routed" or "scan", ents = ents, entCursor = 1, cand = {}, seen = {}, cursor = 1, buf = {},
			calls = 0, frames = 0, busyS = 0, maxFrameS = 0, fetchS = 0, read = 0, drivers = 0, near = 0, counted = 0,
			capped = 0, gone = 0 }
		return true
	end

	--- One candidate person of the snapshot: placed (one call; scan: a driver first), then, only on a corridor, the
	-- driving and standing reads (Stress Test's queue: speed < STAND_SPEED, timeStanding >= QUEUE_STAND).
	local function readOne(snap, e)
		if type(e) ~= "number" then return end
		snap.read = snap.read + 1
		if snap.src == "scan" then
			if driveValue == nil then
				local ok, v = pcall(function() return api.type.enum.MoveMode.DRIVE end)
				driveValue = (ok and v ~= nil) and v or 1
			end
			snap.calls = snap.calls + 1
			local ok, sp = pcall(api.engine.getComponent, e, CT.SIM_PERSON)
			if not ok or sp == nil or sp.lastMoveMode ~= driveValue then return end
		end
		snap.drivers = snap.drivers + 1
		local x, y = H.carPos(e)
		if x == nil then return end
		local k = Retime.queueHits(snap.idx, x, y, snap.buf)
		if k == 0 then return end
		snap.near = snap.near + 1
		local mp = H.driverPath(e, false)
		if mp == nil then return end
		local okD, speed, ts = pcall(function() return mp.dyn.speed, mp.dyn.timeStanding end)
		if not (okD and type(speed) == "number" and speed < T.STAND_SPEED and type(ts) == "number" and ts >= T.QUEUE_STAND) then
			return
		end
		snap.counted = snap.counted + 1
		for i = 1, k do
			local h = snap.buf[i]
			local c = snap.counts[h.j.key]
			if c == nil then
				c = {}
				snap.counts[h.j.key] = c
			end
			c[h.arm.seg] = (c[h.arm.seg] or 0) + 1
		end
	end

	--- The averaged standing cars of rec's approaches under the timing in force (as decide reads them): { [approach] =
	-- mean cars }, their sum.
	local function queueOf(rec)
		local q, sum = {}, 0
		for a, e in pairs(rec.ema) do
			if rec.timing ~= nil and rec.timing.red[a] ~= nil then
				q[a] = e.q
				sum = sum + e.q
			end
		end
		return q, sum
	end

	--- The largest change of an approach's share of the standing cars between q0 (sum s0) and q (sum s).
	local function shareShift(q0, s0, q, s)
		if s0 <= 0 or s <= 0 then return 0 end
		local m = 0
		for a, v in pairs(q) do m = math.max(m, math.abs(v / s - (q0[a] or 0) / s0)) end
		for a, v in pairs(q0) do
			if q[a] == nil then m = math.max(m, v / s0) end
		end
		return m
	end
	T.shareShift = shareShift

	--- Early wake (T.WAKE_*): after a snapshot, a junction last decided quiet / fits whose traffic clearly changed is
	-- decided at the next look instead of after its back-off (at the earliest when the write gap after its last write
	-- ends). Once per decision (rec.wake is cleared); the interval after that decision follows Auto.nextEvery as usual.
	local function wakeCheck(rec, now, quietQueue)
		local w = rec.wake
		if w == nil or rec.pending ~= nil or rec.due == nil or rec.due <= now then return end
		local q, sum = queueOf(rec)
		local reason, shift = nil, 0
		if w.kind == "quiet" then
			if sum >= T.WAKE_QUIET_X * quietQueue then reason = "quiet_rise" end
		elseif w.kind == "fits" then
			shift = shareShift(w.q, w.sum, q, sum)
			if sum >= T.WAKE_MIN_CARS and sum >= w.sum * (1 + T.WAKE_GROW_REL) and sum - w.sum >= T.WAKE_GROW_ABS then
				reason = "fits_grow"
			elseif math.min(sum, w.sum) >= math.max(T.WAKE_MIN_CARS, quietQueue) and shift > T.WAKE_SHIFT
				and shift * sum >= T.WAKE_SHIFT_CARS then
				reason = "fits_shift"
			end
		end
		if reason == nil then return end
		local due = now
		if rec.lastWrite ~= nil then due = math.max(due, rec.lastWrite + Auto.every(Auto.EVERY_WRITE)) end
		if due >= rec.due then return end
		rec.wake = nil
		line("wake", rec, { { "reason", reason }, { "queued", string.format("%.1f>%.1f", w.sum, sum) },
			{ "shift", string.format("%.2f", shift) }, { "shift_cars", string.format("%.1f", shift * sum) }, { "decided_s", string.format("%.0f", now - w.at) },
			{ "due_was_s", string.format("%.0f", rec.due - now) }, { "due_s", string.format("%.0f", due - now) } })
		rec.due = due
	end
	R.wakeCheck = wakeCheck

	--- The snapshot's counts into every member's averages (arrivals per approach under the timing in force, and the
	-- standing cars), then its line.
	local function finishSnap(snap, now)
		local f0 = clock()
		local o = Retime.options(planOpts)
		for _, m in ipairs(snap.members) do
			local rec = m.rec
			if R.recs[m.key] == rec and rec.active and rec.timing ~= nil then
				local c = snap.counts[m.key] or {}
				local dt = rec.lastSnapAt ~= nil and math.max(0, now - rec.lastSnapAt) or T.TAU_S
				-- a running mean for the first snapshots, then exponential (time constant TAU_S)
				local alpha = math.max(1 - math.exp(-dt / T.TAU_S), 1 / (rec.snaps + 1))
				for _, arm in ipairs(rec.arms) do
					local a = arm.seg
					local red = rec.timing.red[a]
					local q = c[a] or 0
					local lam = red ~= nil and Retime.arrivalOf(q, rec.timing.cycle, red, o) or nil
					if lam ~= nil then
						local e = rec.ema[a]
						if e == nil then
							rec.ema[a] = { a = lam, q = q }
						else
							e.a = e.a + alpha * (lam - e.a)
							e.q = e.q + alpha * (q - e.q)
						end
					end
				end
				rec.snaps = math.min(rec.snaps + 1, 1000000)
				rec.lastSnapAt = now
				if rec.snaps >= T.MIN_SNAPS and rec.due == nil then rec.due = now + T.firstDelay(rec.key) end
				wakeCheck(rec, now, o.quietQueue)
			end
		end
		R.snaps = R.snaps + 1
		line("snapshot", nil, { { "n", #snap.members }, { "src", snap.src }, { "cand", snap.cand and #snap.cand or 0 },
			{ "read", snap.read }, { "drivers", snap.drivers }, { "near", snap.near }, { "counted", snap.counted },
			{ "calls", snap.calls }, { "frames", snap.frames }, { "busy_ms", string.format("%.1f", snap.busyS * 1000) },
			{ "max_frame_ms", string.format("%.2f", snap.maxFrameS * 1000) },
			{ "fetch_ms", string.format("%.2f", snap.fetchS * 1000) },
			{ "finish_ms", string.format("%.2f", (clock() - f0) * 1000) },
			{ "span_s", string.format("%.0f", now - snap.t0) }, { "gone", snap.gone }, { "capped", snap.capped },
			{ "enrolled", R.mirror.idx.n or 0 }, { "err", snap.err or "-" }, { "heavy", R.heavyN },
			{ "backlog", R.backlogMax } })
		R.heavyN, R.backlogMax = 0, 0
		R.snap = nil
		R.nextSnapAt = math.max(snap.t0 + T.SNAP_EVERY_S, now + 1)
	end

	--- One frame of the snapshot within BUDGET_S.
	local function snapStep(now)
		local snap = R.snap
		local t0 = clock()
		snap.frames = snap.frames + 1
		H.run = snap
		if snap.phase == "list" then
			if snap.src == "scan" then
				-- the whole list in one engine call (Photo Mode: 8765 persons in 0.5-0.9 ms, findings lines-vehicles);
				-- its own time is fetch_ms on the line, and the reads start in this frame only when it left budget
				snap.calls = snap.calls + 1
				local f0 = clock()
				local ok, got = pcall(api.engine.getEntitiesWithComponent, CT.SIM_PERSON)
				snap.fetchS = snap.fetchS + (clock() - f0)
				if ok and type(got) == "table" then snap.cand = got else snap.err = "scan" end
				snap.phase = "read"
			else
				local sps = api.engine.system.simPersonSystem
				local checked = snap.calls
				while snap.entCursor <= #snap.ents do
					local it = snap.ents[snap.entCursor]
					snap.entCursor = snap.entCursor + 1
					-- the segment first (a removed one asserts in the engine and cost a 249 ms frame in run 2,
					-- docs/findings/lines-vehicles.md): gone -> not asked, the junction refreshed at its next look
					snap.calls = snap.calls + 1
					local okC, c = pcall(api.engine.getComponent, it.e, CT.BASE_EDGE)
					if not okC or c == nil then
						snap.gone = snap.gone + 1
						it.rec.refreshAt = now
					else
						snap.calls = snap.calls + 1
						local ok, got = pcall(function() return sps.getSimPersonsMovingForTransportNetwork(it.e) end)
						if ok and type(got) == "table" then
							for _, p in ipairs(got) do
								if not snap.seen[p] then
									if #snap.cand >= T.CAND_MAX then
										snap.capped = snap.capped + 1
										break
									end
									snap.seen[p] = true
									snap.cand[#snap.cand + 1] = p
								end
							end
						end
					end
					if snap.calls - checked >= T.CHECK_CALLS then
						checked = snap.calls
						if clock() - t0 >= T.BUDGET_S then break end
					end
				end
				snap.fetchS = snap.fetchS + (clock() - t0)
				if snap.entCursor > #snap.ents then
					snap.phase, snap.seen = "read", nil
				end
			end
		end
		if snap.phase == "read" and clock() - t0 < T.BUDGET_S then
			local list = snap.cand
			local stop = math.min(#list, T.SCAN_MAX)
			local checked = snap.calls
			while snap.cursor <= stop do
				local e = list[snap.cursor]
				snap.cursor = snap.cursor + 1
				local okR, errR = pcall(readOne, snap, e)
				if not okR then snap.err = tostring(errR) end
				if snap.calls - checked >= T.CHECK_CALLS then
					checked = snap.calls
					if clock() - t0 >= T.BUDGET_S then break end
				end
			end
			if snap.cursor > stop then snap.phase = "done" end
		end
		local spent = clock() - t0
		snap.busyS = snap.busyS + spent
		if spent > snap.maxFrameS then snap.maxFrameS = spent end
		H.run = nil
		if snap.phase == "done" then finishSnap(snap, now) end
	end

	---------------------------------------------------------------------------
	-- Decisions and writes

	local function greensText(kinds, list)
		local g = {}
		for i, k in ipairs(kinds or {}) do
			if k == "veh" and list[i] ~= nil then g[#g + 1] = list[i] end
		end
		return Retime.listText(g)
	end

	--- The states with other durations (the timing after our write).
	local function withDurations(states, durations)
		local res = {}
		for i, st in ipairs(states) do
			res[i] = { locked = st.locked, duration = durations[i] or st.duration, minDuration = st.minDuration,
				canSkip = st.canSkip }
		end
		return res
	end

	--- Decides at a junction with enough snapshots: Retime.planQueue on its averages; a write wanted waits in
	-- R.pending, otherwise its outcome is recorded and the next decision scheduled.
	local function decide(rec, now)
		local gap = Auto.every(Auto.EVERY_WRITE)
		if rec.lastWrite ~= nil and now - rec.lastWrite < gap then
			rec.due = rec.lastWrite + gap
			return
		end
		if refresh(rec, now) ~= "ok" then
			if rec.active then rec.due = now + Auto.RETRY_S end
			return
		end
		if rec.snaps < T.MIN_SNAPS then return end
		local rd = rec.rd
		local arrive, queue = {}, {}
		for a, e in pairs(rec.ema) do
			if rec.timing.red[a] ~= nil then arrive[a], queue[a] = e.a, e.q end
		end
		local h = rec.hist
		local prev = (h ~= nil and h.struct == rd.struct and now - (h.at or -math.huge) <= T.HIST_MAX_S) and h or nil
		local plan = Retime.planQueue({ conns = rd.connList, nCross = #rd.cws, states = rd.states, arrive = arrive,
			queue = queue, snaps = rec.snaps, pedNeed = rec.pedNeed, prev = prev }, planOpts)
		rec.wake = nil
		if not plan.keep and plan.load ~= nil then
			-- kept in memory only (a reload starts unsmoothed and unconfirmed: the cycle holds one decision longer)
			local ld = {}
			for p, v in pairs(plan.load) do
				if type(p) == "number" and p <= 64 then ld[p] = v end
			end
			rec.hist = { load = ld, long = plan.long == true, at = now, struct = rd.struct }
		end
		local old = {}
		for i, st in ipairs(rd.states) do old[i] = st.duration end
		local qtext = {}
		for a, v in pairs(queue) do qtext[a] = math.floor(v * 10 + 0.5) / 10 end
		local atext = {}
		for a, v in pairs(plan.arrive or {}) do atext[a] = math.floor(v + 0.5) end
		line("plan", rec, { { "result", plan.reason }, { "snaps", rec.snaps }, { "queued", string.format("%.1f", plan.queued) },
			{ "queue", Retime.mapText(qtext) }, { "arrive", Retime.mapText(atext) },
			{ "load", Retime.mapText(plan.loadRaw or {}) },
			{ "load_s", plan.smoothed and Retime.mapText(plan.load or {}) or "-" },
			{ "share", string.format("%.2f", plan.share or 0) }, { "balanced", plan.balanced and 1 or 0 },
			{ "old", Retime.listText(old) }, { "new", Retime.listText(plan.durations or old) },
			{ "cycle", string.format("%.0f>%.0f", plan.oldCycle or 0, plan.cycle or plan.oldCycle or 0) },
			{ "cycle_wanted", string.format("%.0f", plan.cycleWanted or plan.oldCycle or 0) },
			{ "stepped", plan.cycleStepped == true and 1 or 0 },
			{ "greens", greensText(plan.kinds, old) .. ">" .. greensText(plan.kinds, plan.durations or old) },
			{ "y", string.format("%.2f", plan.y or 0) }, { "cycle_reason", plan.cycleReason or "-" }, { "every", rec.every } },
			rec.n)
		if plan.keep or not plan.changed then
			local kind = plan.reason == "fits" and "fits" or "small"
			rec.every = Auto.nextEvery(rec.every, kind)
			-- a long cycle waiting for its confirmation: the next decision soon, not after a back-off
			if plan.cycleReason == "unconfirmed" then rec.every = Auto.every(Auto.EVERY_SOON) end
			rec.due = now + rec.every
			-- no refresh of its own before that decision (which refreshes it first): a quiet or fitting junction is read
			-- once per decision, not every REFRESH_S (user 2026-10-17: 194 decisions, all quiet). A removed approach
			-- segment still refreshes it at the next snapshot, an early wake decides it sooner.
			rec.refreshAt = math.max(rec.refreshAt or now, rec.due + T.REFRESH_S)
			-- an early wake when its traffic clearly changes (wakeCheck): quiet and fits only (not the other keeps)
			if plan.reason == "quiet" or plan.reason == "fits" then
				local q0, sum0 = {}, 0
				for a, v in pairs(queue) do
					q0[a] = v
					sum0 = sum0 + v
				end
				rec.wake = { kind = plan.reason, q = q0, sum = sum0, at = now }
			end
			addRecord(rec, kind, plan.oldCycle or 0, plan.oldCycle or 0, nil, old)
			return
		end
		-- the expected gain: how far the greens move (share of the cycle) x the cars standing there
		local moved = 0
		for i, k in ipairs(plan.kinds) do
			if k == "veh" then moved = moved + math.abs((plan.durations[i] or 0) - (old[i] or 0)) end
		end
		local gain = plan.queued * moved / math.max(1, plan.oldCycle or 1)
		rec.pending = { plan = plan, sig = rd.sig, conns = rd.conns, at = now, gain = gain, old = old, n = rec.n, rd = rd }
		R.pending[rec.key] = rec
		rec.due = now + Auto.RETRY_S
	end
	R.decide = decide

	--- The write of a decided plan (the pending one of the largest gain; one per WRITE_GAP_S map-wide).
	local function writeStep(now)
		if next(R.pending) == nil or now - R.lastWriteAt < T.WRITE_GAP_S then return end
		local best = nil
		for _, k in ipairs(sortedKeys(R.pending)) do
			local rec = R.pending[k]
			local pd = rec.pending
			if R.recs[k] ~= rec or pd == nil then
				R.pending[k] = nil
			elseif now - pd.at > T.PENDING_MAX_S then
				line("skip", rec, { { "reason", "stale" }, { "held", pd.held or "-" }, { "retry_s", Auto.RETRY_S } }, pd.n)
				rec.pending, R.pending[k] = nil, nil
				rec.due = now + Auto.RETRY_S
			else
				local hold = nil
				if buildNear(rec.x, rec.y, now) then hold = "building"
				elseif opts.toolBusy ~= nil and opts.toolBusy(pd.n) then hold = "busy" end
				if hold ~= nil then
					if pd.held ~= hold then
						pd.held = hold
						line("hold", rec, { { "reason", hold } }, pd.n)
					end
				elseif best == nil or pd.gain > best.pending.gain then
					best = rec
				end
			end
		end
		if best == nil then return end
		local rec, pd = best, best.pending
		rec.pending, R.pending[rec.key] = nil, nil
		R.lastWriteAt = now
		R.wroteFrame = R.frames
		local plan = pd.plan
		local want = Retime.listText(plan.durations)
		local c0, c1 = plan.oldCycle or 0, plan.cycle or 0
		local sent, whyW = W.retimeLights(pd.n, plan.durations, plan.minDurations, pd.sig, pd.conns, "auto",
			function(success)
				line("write", rec, { { "at", "cb" }, { "success", success } }, pd.n)
				if success then
					addRecord(rec, "written", c0, c1, plan.durations)
					-- the written phases are the base now (no adopt for our own write)
					local after = readJunction(pd.n)
					if after ~= nil then rec.struct, rec.dur = after.struct, after.dur end
				else
					addRecord(rec, "notwritten", c0, c0, nil, pd.old)
					rec.every = Auto.nextEvery(rec.every, "refused")
					rec.due = now + rec.every
					rec.timing = Retime.timingOf(pd.rd.connList, #pd.rd.cws, pd.rd.states)
					rec.refreshAt = R.now()
				end
			end, { { "action", "auto" } })
		local nextEvery = Auto.nextEvery(rec.every, sent > 0 and "write" or "refused")
		line("write", rec, { { "sent", sent }, { "why", whyW or "-" }, { "durations", want },
			{ "cycle", string.format("%.0f>%.0f", c0, c1) },
			{ "greens", greensText(plan.kinds, pd.old) .. ">" .. greensText(plan.kinds, plan.durations) },
			{ "stepped", plan.cycleStepped == true and 1 or 0 }, { "gain", string.format("%.1f", pd.gain) },
			{ "every", nextEvery } }, pd.n)
		if sent > 0 then
			rec.lastWrite = now
			rec.wrote = want
			rec.every = nextEvery
			rec.due = now + rec.every
			-- the timing in force from now on (the snapshots' arrival estimates)
			rec.timing = Retime.timingOf(pd.rd.connList, #pd.rd.cws, withDurations(pd.rd.states, plan.durations))
		elseif whyW == "changed" then
			-- the junction changed since the decision: read it again, decide later
			rec.due = now + Auto.RETRY_S
			rec.refreshAt = now
		else
			addRecord(rec, "notwritten", c0, c0, nil, pd.old)
			rec.every = nextEvery
			rec.due = now + rec.every
		end
	end

	--- LOOKS_PER_FRAME records round robin; at most one heavy step (a refresh or a decision).
	--- The time a record's next heavy step is due (a refresh, else a decision), nil when none is due at `now`.
	local function heavyAt(rec, now)
		if rec == nil or rec.gone then return nil end
		if rec.refreshAt ~= nil and now >= rec.refreshAt then return rec.refreshAt end
		if rec.active and rec.pending == nil and rec.snaps >= T.MIN_SNAPS and rec.due ~= nil and now >= rec.due then
			return rec.due
		end
		return nil
	end

	local function looks(now)
		local n = #R.order
		if n == 0 then return end
		for _ = 1, math.min(n, T.LOOKS_PER_FRAME) do
			R.cursor = R.cursor % n + 1
			local key = R.order[R.cursor]
			local rec = R.recs[key]
			if heavyAt(rec, now) ~= nil then R.dueSet[key] = rec end
		end
		-- no heavy step in a frame that wrote (the write's proposal is this frame's work)
		if R.wroteFrame == R.frames then return end
		local t0 = clock()
		local done = 0
		while done < T.HEAVY_MAX do
			-- the oldest due first (stale entries dropped)
			local best, bestAt, backlog = nil, nil, 0
			for k, rec in pairs(R.dueSet) do
				local at = R.recs[k] == rec and heavyAt(rec, now) or nil
				if at == nil then
					R.dueSet[k] = nil
				else
					backlog = backlog + 1
					if bestAt == nil or at < bestAt or (at == bestAt and k < best.key) then best, bestAt = rec, at end
				end
			end
			if backlog - 1 > R.backlogMax and done == 0 then R.backlogMax = backlog - 1 end
			if best == nil then return end
			R.dueSet[best.key] = nil
			if best.refreshAt ~= nil and now >= best.refreshAt then refresh(best, now) else decide(best, now) end
			done = done + 1
			R.heavyN = R.heavyN + 1
			if clock() - t0 >= T.HEAVY_BUDGET_S then return end
		end
	end
	R.looks = looks

	--- Whether this frame only counts (the header's "Idle"): Off, or nothing enrolled and nothing in progress.
	local function idle()
		if not R.mirror.read or (R.wakeUntil ~= nil and R.frames < R.wakeUntil) then return false end
		if #R.newQ.items > 0 or R.allJob ~= nil then return false end
		if R.mode == "off" then return true end
		return R.mode == "pick" and (R.mirror.idx.n or 0) == 0 and #R.autoZones == 0 and R.snap == nil
			and next(R.pending) == nil
	end
	R.idle = idle

	--- The busy cadence for IDLE_FRAMES frames (the tool sent a SmartLanes.auto event: an enrollment or a mode).
	function R.wake()
		R.wakeUntil = R.frames + T.IDLE_FRAMES
	end

	--- fn(...) timed as SQPERF section `name` (opts.perf: the background plugin's instrument, sl_bg.script.lua; the
	-- whole frame is its section `auto`), so a slow frame names the part it came from. Without opts.perf: fn(...).
	local perf = opts.perf
	local function timed(name, fn, ...)
		if perf == nil then return fn(...) end
		local t0 = perf:start()
		local r = fn(...)
		perf:stop(name, t0)
		return r
	end

	local function mirrorStep(now)
		if R.frames - R.mirror.frame >= T.MIRROR_FRAMES then refreshMirror(now) end
		-- the save's in-game settings (sl_settings.lua; at most every Settings.POLL_S)
		pcall(Settings.poll, api, false)
		if Settings.mirror.version ~= R.setVer then deriveConfig(false) end
		if (R.frames - 1) % T.ZONES_FRAMES == 0 then refreshZones() end
	end

	local function listStep(now)
		if R.allJob ~= nil then allStep()
		elseif listDue(now) then
			R.nextListAt = now + AllMode.LIST_EVERY_S
			R.allJob = { run = "allmode", phase = "list", cursor = 1, found = {}, lit = 0, already = 0, optout = 0, hand = 0,
				periodic = true }
			allStep()
		elseif #R.autoZones > 0 then zoneStep(now) end
	end

	--- The snapshot part of a frame; true when a snapshot read in it (the frame ends there).
	local function snapPart(now)
		if R.snap ~= nil then
			snapStep(now)
			return true
		end
		if now >= R.nextSnapAt and not (opts.manualBusy ~= nil and opts.manualBusy()) then
			if startSnap(now) then
				snapStep(now)
				return true
			end
			-- nothing watched yet: look again in a while (no member list built every frame)
			R.nextSnapAt = now + 10
		end
		return false
	end

	--- One frame (the background plugin). Never throws. SQPERF sections (opts.perf): auto_mirror, auto_new (the
	-- new-light look), auto_list (the all-lights listing, op=all, zones), auto_snap, auto_write, auto_looks (refreshes
	-- and decisions), auto_flush.
	function R.step()
		R.frames = R.frames + 1
		local ok, e = pcall(function()
			local now = R.now()
			if idle() then
				if R.frames - R.mirror.frame >= T.IDLE_FRAMES then refreshMirror(now) end
				if R.mode ~= "off" and (R.frames - 1) % T.IDLE_FRAMES == 0 then refreshZones() end
				flush(now)
				return
			end
			timed("auto_mirror", mirrorStep, now)
			if #R.newQ.items > 0 and R.mirror.read then timed("auto_new", newStep, now) end
			if R.mode == "off" then
				-- the new-light look above only (its Smart lights plans); nothing timed
				flush(now)
				return
			end
			timed("auto_list", listStep, now)
			if timed("auto_snap", snapPart, now) then return end
			timed("auto_write", writeStep, now)
			timed("auto_looks", looks, now)
			timed("auto_flush", flush, now)
		end)
		if not ok then
			R.errors = (R.errors or 0) + 1
			if R.errors <= 5 then out("ERROR", { { "where", "auto_step" }, { "err", tostring(e) } }) end
			-- a broken snapshot is dropped (the next one starts in SNAP_EVERY_S)
			if R.snap ~= nil then
				R.nextSnapAt = R.now() + T.SNAP_EVERY_S
				R.snap = nil
			end
		end
	end

	--- Status of node n at (x, y) for the tool (nil: not enrolled): { snaps, need (MIN_SNAPS), due (game s of the next
	-- decision; nil before enough snapshots), pending (a write waits), active (watched) }.
	function R.statusOf(n, x, y)
		local e = Auto.match(R.mirror.idx, n, x, y)
		if e == nil then return nil end
		local rec = R.recs[Auto.posKey(e[2], e[3])]
		local st = { snaps = 0, need = T.MIN_SNAPS, active = false }
		if rec ~= nil then
			st.snaps, st.due, st.pending, st.active = rec.snaps, rec.due, rec.pending ~= nil, rec.active == true
		end
		return st
	end

	--- Decides at node n at (x, y) at the next look once it has enough snapshots (the Stress Test's op=now).
	function R.requestNow(n, x, y)
		local e = Auto.match(R.mirror.idx, n, x, y)
		local rec = e and R.recs[Auto.posKey(e[2], e[3])] or nil
		if rec == nil then return false end
		rec.due = R.now()
		return true
	end

	return R
end

return T
