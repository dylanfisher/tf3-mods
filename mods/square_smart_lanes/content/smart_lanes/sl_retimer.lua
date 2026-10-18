-- Smart Lanes "Re-time" (rev 8, PLAN.md "Re-time: phase lengths from measured traffic", RETIME_PLAN.md step A):
-- the measuring runtime. Reads the cars near each measured junction (several at once: "Shared runs" below) every
-- EVERY_S game seconds for WINDOW_S game seconds, within one per-frame time budget, and counts per movement (approach segment > exit segment) the cars that passed
-- and the cars queued. Also the re-route checks of the probe (a snapshot of the drivers that have the junction
-- ahead, re-read later). Runs on the GUI thread (the tool's react.onStep through sl_toolcore C.step); every
-- engine read is pcall'd. The pure part (path state, timing) is sl_retime.lua.
--
-- Candidates of a sample: the persons the engine lists as moving over the junction node and over each of its
-- street segments (simPersonSystem.getSimPersonsMovingForTransportNetwork: persons ROUTED through the entity,
-- 240-710 per edge / junction node in Stress Test probe 11c, session 2026-10-12_0905; 30-360 us per call), plus
-- the drivers that had the junction ahead at the last sample (so a car that left those lists still counts as a
-- pass). Should every one of those calls fail, the run falls back to the whole SIM_PERSON list (src=scan, as the
-- Stress Test sampler; slower, still within the frame budget: a sample then takes more frames).
-- Per candidate (cheapest read first, rev 8 v2: the user's run read 1425 candidates per sample of which ~315 were
-- near): a candidate not ahead at the last sample is first placed (vehicle.getPosition, one call); beyond RADIUS it is
-- skipped and not read again until it could have come within RADIUS at MAX_SPEED (farUntil, game s); only near
-- ones (and the drivers ahead at the last sample) are then read as Stress Test stress_flow_log: driving (SIM_PERSON
-- lastMoveMode DRIVE, a MOVE_PATH, not seated in a vehicle), then
-- its path (MOVE_PATH.path.edges elements, read as elem.edgeId.entity; pathPos.edgeIndex): the node ahead within
-- LOOK elements = approaching (its movement: the elements before / after the node); behind after being ahead at
-- the last sample = one pass of that movement (Stress Test's path count). Queued: approaching, within
-- QUEUE_RADIUS, dyn.speed < STAND_SPEED and dyn.timeStanding >= QUEUE_STAND s (Stress Test's queue).
--
-- Interval and window (the defaults; see PLAN.md for the reasoning): 3 game s between samples, 180 game s (60
-- samples): 2-4 cycles of 40-90 s, so every phase is seen green and red several times; at 3 s a car within 200 m
-- (at 15 m/s 45 m per sample) is seen ahead before it passes. Game time (GAME_TIME), so a paused game takes no
-- samples and the game speed does not change the spacing; a sample still being read when the next is due delays
-- it (samples= in the log tells).
-- Caps: CAND_MAX candidates per sample, TRACK_MAX drivers carried to the next sample, BUDGET_S per frame (the
-- clock after every CHECK_EVERY candidates and after every path read), LOOK path elements each way.
-- Gathering (user 2026-10-17: 17 recordings at once gave ~12.5 ms frames): a sample's candidates (the routed list of
-- every target entity, one engine call each) are gathered within the same BUDGET_S, the clock read after each call,
-- at least one entity a frame, so many targets spread a sample's start over frames instead of one long frame. The
-- whole-person-list fallback (src scan) is one engine call and stays in one frame.
--
-- Shared runs (Record traffic, several recordings at once, 2026-10-16; Re-time, several runs at once, 2026-10-17):
-- every run is one M.startShared run that never ends by itself; M.addTarget / M.removeTarget put up to TARGETS_MAX
-- targets (a junction or a roundabout, each { nodes, candEnts, x, y, radius, countFn, retime, windowS }) into it at
-- any time. The tool keeps two instances, each with its own run and budget: Record traffic's (C.recorder) and
-- Re-time's (C.retimer). One sample reads the union of every target's candidates once (a car routed through two
-- targets is placed and read once), within the run's one per-frame budget; a driver is near when it is within any
-- target's radius (far: skipped until it could reach the nearest one); a pass is counted per junction the driver had
-- ahead and has behind now (Retime.pathAtMulti), for every target holding that node (target.counted, target.passes,
-- key "<node>@<in>><out>"; countFn(node, inSeg, outSeg) says which passes add to counted, default every one). A
-- Re-time target (retime = true: one junction) keys its passes by movement alone ("<in>><out>") and counts its queued
-- cars per sample (target.qSum: approaching, within QUEUE_RADIUS of it, standing); with windowS, M.step returns "done"
-- once that many game s of it were measured, before the next sample (target.over; the caller removes it). Each target
-- keeps its own start (t0, moved on by a gap as the run's), its samples and the interval between them. With many
-- targets a sample takes more frames: the budget per frame stays, the samples come later (every target's interval
-- stretches alike; target.everyMax / target.late tell, PLAN.md "Traffic rate at a junction").

local Retime = ug_require "square_smart_lanes::/smart_lanes/sl_retime.lua"

local T = {}

T.WINDOW_S = 180
T.EVERY_S = 3
T.RADIUS = 200          -- m: candidates read beyond this are skipped (unless ahead at the last sample)
T.QUEUE_RADIUS = 150    -- m: queued cars counted within this
T.LOOK = 8              -- path elements looked at ahead / behind (alternating nodes and edges: 4 edges)
T.STAND_SPEED = 0.5     -- m/s
T.QUEUE_STAND = 5       -- s of timeStanding (Stress Test's queue)
T.BUDGET_S = 0.0015     -- s of clock per frame
T.CHECK_EVERY = 8       -- candidates between two clock reads
T.CAND_MAX = 5000
T.TRACK_MAX = 2000
T.REROUTE_MAX = 120     -- drivers in a re-route snapshot
T.RECHECK_LOOK = 400    -- path elements searched each way in a re-route check (one driver per budget check)
T.SCAN_MAX = 400000     -- persons of the fallback scan list (a safety stop)
T.MAX_SPEED = 40        -- m/s a far candidate is assumed to close in at (farUntil; 144 km/h)
T.FAR_MAX = 20000       -- farUntil entries kept (cleared when full)
T.GAP_FACTOR = 2        -- a step later than this x EVERY_S after the last one: the window is extended by the gap
T.TARGETS_MAX = 32      -- targets of a shared run (the tool allows Rec.MAX_RUNNING, Core.RETIME_MAX_RUNNING)
T.TARGET_NODES_MAX = 64 -- nodes per target
T.LATE_FACTOR = 2       -- a shared sample later than this x everyS after the one before counts as late

--- api: game api (or fake); clock(): seconds (os.clock); nowFn (optional): game seconds (tests; a nil answer:
-- GAME_TIME as in game).
--- opts (optional): perf (an SQPERF instance) and perfName: the candidate gathering of each frame timed as that
-- section (sl_toolcore: retime_gather / record_gather).
function T.new(api, clock, nowFn, opts)
	opts = opts or {}
	local M = { state = "idle" }
	clock = clock or os.clock
	local CT = api.type.ComponentType

	local function comp(e, ct)
		if e == nil or ct == nil then return nil end
		if M.run ~= nil then M.run.calls = M.run.calls + 1 end
		local ok, c = pcall(api.engine.getComponent, e, ct)
		if ok then return c end
		return nil
	end

	--- Game seconds and the source ("game" | "wall": GAME_TIME unreadable, the clock instead).
	function M.now()
		if nowFn ~= nil then
			local v = nowFn()
			if type(v) == "number" then return v, "game" end
		end
		local ok, gt = pcall(function()
			return api.engine.getComponent(api.engine.util.getWorld(), CT.GAME_TIME).gameTime
		end)
		if ok and type(gt) == "number" then return gt / 1000, "game" end
		return clock(), "wall"
	end

	local driveValue = nil
	--- The person's MOVE_PATH when it drives a car now, else nil (Stress Test driverPath). tracked: the driver drove
	-- its car at the last sample (step B's sampler): the two at-vehicle reads are left out (a person driving its own
	-- car 3-5 s ago, still in drive mode, is not a passenger now).
	local function driverPath(e, tracked)
		local sp = comp(e, CT.SIM_PERSON)
		if sp == nil then return nil end
		if driveValue == nil then
			local ok, v = pcall(function() return api.type.enum.MoveMode.DRIVE end)
			driveValue = (ok and v ~= nil) and v or 1
		end
		if sp.lastMoveMode ~= driveValue then return nil end
		local mp = comp(e, CT.MOVE_PATH)
		if mp == nil then return nil end
		if tracked then return mp end
		if (CT.SIM_PERSON_AT_VEHICLE ~= nil and comp(e, CT.SIM_PERSON_AT_VEHICLE) ~= nil)
			or (CT.SIM_ENTITY_AT_VEHICLE ~= nil and comp(e, CT.SIM_ENTITY_AT_VEHICLE) ~= nil) then
			return nil
		end
		return mp
	end
	M.driverPath = driverPath

	--- A car's position, nil when unreadable (exactly 0,0 = no answer).
	local function carPos(e)
		if M.run ~= nil then M.run.calls = M.run.calls + 1 end
		local ok, p = pcall(api.engine.util.vehicle.getPosition, e)
		if ok and p ~= nil and p.x ~= nil and (p.x ~= 0 or p.y ~= 0) then return p.x, p.y end
		return nil, nil
	end

	M.carPos = carPos

	--- elem.edgeId.entity (verified 2026-10-13), elem.entity as a fallback.
	local function elemEntity(elem)
		if elem == nil then return nil end
		local ok, id = pcall(function() return elem.edgeId.entity end)
		if ok and type(id) == "number" then return id end
		local ok2, id2 = pcall(function() return elem.entity end)
		if ok2 and type(id2) == "number" then return id2 end
		return nil
	end

	--- The path of mp: get(i) (0-based), n, cur; nil when unreadable.
	local function pathOf(mp)
		local ok, edges, n, cur = pcall(function()
			local list = mp.path.edges
			return list, #list, math.floor(mp.dyn.pathPos.edgeIndex)
		end)
		if not ok or edges == nil or n == nil or cur == nil then return nil end
		local function get(i)
			if M.run ~= nil then M.run.calls = M.run.calls + 1 end
			local okE, elem = pcall(function() return edges[i + 1] end)
			if not okE then return nil end
			return elemEntity(elem)
		end
		return get, n, cur
	end

	--- The node's light now: { exists, light, state, time, stateTimes (text), userModified, durations (text),
	-- locked (text: the lockedLanes sets) } (the probe's reads; never throws).
	function M.lightNow(node)
		local r = { exists = false, light = false }
		local okX, ex = pcall(api.engine.entityExists, node)
		r.exists = okX and ex == true
		local cfg = comp(node, CT.BASE_NODE_CONFIG)
		r.config = cfg ~= nil
		if cfg ~= nil then
			pcall(function() r.userModified = cfg.userModifiedTrafficLightStates end)
			local d, l = {}, {}
			pcall(function()
				for i, st in ipairs(cfg.trafficLightConfig.states) do
					if i > 32 then break end
					d[#d + 1] = st.duration
					local set = {}
					for j, x in ipairs(st.lockedLanes or {}) do
						if j > 512 then break end
						set[#set + 1] = x
					end
					table.sort(set)
					l[#l + 1] = table.concat(set, ",")
				end
			end)
			r.durations = Retime.listText(d)
			r.locked = table.concat(l, ";")
		end
		local tl = CT.BASE_NODE_TRAFFIC_LIGHT ~= nil and comp(node, CT.BASE_NODE_TRAFFIC_LIGHT) or nil
		if tl ~= nil then
			r.light = true
			pcall(function() r.state = tl.state end)
			pcall(function() r.time = tl.time end)
			pcall(function()
				local t = {}
				for i, v in ipairs(tl.stateTimes or {}) do
					if i > 32 then break end
					t[#t + 1] = v
				end
				r.stateTimes = Retime.listText(t)
			end)
		end
		return r
	end

	-- (the shared sampler of step B, sl_autoretime.lua, reads drivers with these; it sets M.run to its own run table, a
	-- table with a `calls` counter, so the calls are counted there)
	M.pathOf = pathOf

	---------------------------------------------------------------------------
	-- Measuring

	--- A shared run's union of its targets: nodeSet, nodeTargets (node -> the targets holding it), centers and the
	-- candidate entities (each once). Bounded: TARGETS_MAX x TARGET_NODES_MAX nodes, the targets' entity lists.
	local function rebuildShared(run)
		local nodeSet, nodeTargets, centers, ents, seen = {}, {}, {}, {}, {}
		local windowed = false
		local ids = {}
		for id in pairs(run.targets) do ids[#ids + 1] = id end
		table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
		for _, id in ipairs(ids) do
			local tg = run.targets[id]
			for _, n in ipairs(tg.nodes) do
				nodeSet[n] = true
				local l = nodeTargets[n]
				if l == nil then
					l = {}
					nodeTargets[n] = l
				end
				l[#l + 1] = tg
			end
			if tg.x ~= nil and tg.y ~= nil then centers[#centers + 1] = { x = tg.x, y = tg.y, r = tg.radius } end
			if tg.windowS ~= nil then windowed = true end
			for _, e in ipairs(tg.ents) do
				if not seen[e] then
					seen[e] = true
					ents[#ents + 1] = e
				end
			end
		end
		run.nodeSet, run.nodeTargets, run.centers, run.candEnts = nodeSet, nodeTargets, centers, ents
		run.targetCount = #ids
		run.windowed = windowed
	end

	--- Starts a shared run (no target yet; it never ends by itself: M.cancel). opts: everyS, budgetS.
	function M.startShared(opts)
		opts = opts or {}
		local t0, timeSrc = M.now()
		M.run = {
			shared = true, targets = {}, targetCount = 0, nodeSet = {}, nodeTargets = {}, centers = {}, candEnts = {},
			budgetS = opts.budgetS, everyS = opts.everyS or T.EVERY_S,
			t0 = t0, timeSrc = timeSrc, due = t0, samples = 0, phase = "wait",
			prevAhead = {}, prevCount = 0, passes = {}, src = nil,
			candMax = 0, candSum = 0, nearSum = 0, reads = 0, frames = 0, busyS = 0, lost = 0, capped = 0,
			calls = 0, farUntil = {}, farCount = 0, farSkipped = 0, gaps = 0, gapS = 0, lastStepAt = t0,
			sampleEnd = {},
		}
		M.state = "measuring"
		return M.run
	end

	--- The run's counters a target's stats are taken from (deltas over its life).
	local function snapStats(run)
		return { samples = run.samples, candSum = run.candSum, nearSum = run.nearSum, reads = run.reads, frames = run.frames,
			busyS = run.busyS, lost = run.lost, capped = run.capped, calls = run.calls, farSkipped = run.farSkipped,
			gaps = run.gaps, gapS = run.gapS }
	end

	--- Adds target `id` to the shared run: t = { nodes (1..TARGET_NODES_MAX), segs, candEnts (default the nodes and
	-- segs), x, y, radius (default RADIUS), countFn(node, inSeg, outSeg), retime (Re-time's target: passes by movement,
	-- queued cars counted), windowS (game s measured, then "done": Re-time's window) }. Returns the target (t0 = now,
	-- counted, passes, samples, everyMax, late; qSum with retime), or nil and a reason ("no_run" | "full" | "exists" |
	-- "bad").
	function M.addTarget(id, t)
		local run = M.run
		if run == nil or not run.shared then return nil, "no_run" end
		if run.targets[id] ~= nil then return nil, "exists" end
		if run.targetCount >= T.TARGETS_MAX then return nil, "full" end
		if type(t) ~= "table" or type(t.nodes) ~= "table" or #t.nodes == 0 then return nil, "bad" end
		local nodes = {}
		for i, n in ipairs(t.nodes) do
			if i > T.TARGET_NODES_MAX then break end
			nodes[#nodes + 1] = n
		end
		local ents = {}
		if type(t.candEnts) == "table" then
			for _, e in ipairs(t.candEnts) do ents[#ents + 1] = e end
		else
			for _, n in ipairs(nodes) do ents[#ents + 1] = n end
			for _, sg in ipairs(t.segs or {}) do ents[#ents + 1] = sg end
		end
		local now = M.now()
		local tg = { id = id, nodes = nodes, ents = ents, x = t.x, y = t.y, radius = t.radius or T.RADIUS,
			countFn = t.countFn, counted = 0, passes = {}, t0 = now, addedAt = now, samples = 0, everyMax = 0, late = 0,
			stats0 = snapStats(run), retime = t.retime == true, windowS = t.windowS }
		if tg.retime then tg.qSum, tg.sQueue = {}, {} end
		run.targets[id] = tg
		rebuildShared(run)
		-- a far-skip was measured against the targets before: a car near the new one is placed again
		run.farUntil, run.farCount = {}, 0
		return tg
	end

	--- Removes target `id` from the shared run (its counts stay in the returned target). Returns the target or nil.
	function M.removeTarget(id)
		local run = M.run
		if run == nil or not run.shared then return nil end
		local tg = run.targets[id]
		if tg == nil then return nil end
		run.targets[id] = nil
		rebuildShared(run)
		return tg
	end

	--- A target of the shared run (nil: none).
	function M.target(id)
		local run = M.run
		if run == nil or not run.shared then return nil end
		return run.targets[id]
	end

	--- The shared run's stats over target tg's life (for the log), its passes and samples; for a Re-time target also
	-- what sl_retime R.plan takes: queue (mean queued cars per sample by movement) and windowS (the game s measured).
	function M.targetResult(tg)
		local run = M.run
		if run == nil or type(tg) ~= "table" then return nil end
		local s0 = tg.stats0 or snapStats(run)
		local samples = run.samples - s0.samples
		local function mean(v) return samples > 0 and v / samples or 0 end
		local queue = nil
		if tg.qSum ~= nil then
			queue = {}
			for k, v in pairs(tg.qSum) do queue[k] = v / math.max(1, tg.samples) end
		end
		return { passes = tg.passes, queue = queue, windowS = math.max(0, M.now() - tg.t0), samples = tg.samples,
			src = run.src or "-", timeSrc = run.timeSrc, candMax = run.candMax,
			candMean = mean(run.candSum - s0.candSum), nearMean = mean(run.nearSum - s0.nearSum),
			reads = run.reads - s0.reads, frames = run.frames - s0.frames, busyMs = (run.busyS - s0.busyS) * 1000,
			lost = run.lost - s0.lost, capped = run.capped - s0.capped, err = run.err, calls = run.calls - s0.calls,
			farSkipped = run.farSkipped - s0.farSkipped, gaps = run.gaps - s0.gaps, gapS = run.gapS - s0.gapS,
			runSamples = samples, everyMax = tg.everyMax, late = tg.late, targets = run.targetCount }
	end

	--- Starts gathering a sample's candidates: the routed lists of the targets' entities (their nodes and segments),
	-- then the drivers ahead last time (gatherStep).
	local function gatherStart(run)
		run.gather = { list = {}, seen = {}, ents = run.candEnts, i = 1, okAny = false }
	end

	--- One frame of gathering within the budget (t0: the frame's clock start; at least one entity). Returns true when
	-- the candidates are complete (run.cand set).
	local function gatherStep(run, t0)
		local G = run.gather
		local list, seen = G.list, G.seen
		local function add(e)
			if type(e) == "number" and not seen[e] then
				if #list >= T.CAND_MAX then
					run.capped = run.capped + 1
					return false
				end
				seen[e] = true
				list[#list + 1] = e
			end
			return true
		end
		if run.src ~= "scan" then
			local sps = api.engine.system and api.engine.system.simPersonSystem
			local first = true
			while G.i <= #G.ents do
				if not first and clock() - t0 >= (run.budgetS or T.BUDGET_S) then return false end
				first = false
				local e = G.ents[G.i]
				G.i = G.i + 1
				local ok, got = pcall(function() return sps.getSimPersonsMovingForTransportNetwork(e) end)
				if ok and type(got) == "table" then
					G.okAny = true
					for _, p in ipairs(got) do
						if not add(p) then break end
					end
				end
			end
			if G.okAny then run.src = "routed" else run.src = "scan" end
		end
		if run.src == "scan" then
			local ok, got = pcall(api.engine.getEntitiesWithComponent, CT.SIM_PERSON)
			if ok and type(got) == "table" then
				for i, p in ipairs(got) do
					if i > T.SCAN_MAX then break end
					seen[p] = true
					list[#list + 1] = p
				end
			end
		end
		for e in pairs(run.prevAhead) do
			if not seen[e] then
				seen[e] = true
				list[#list + 1] = e
			end
		end
		run.cand, run.gather = list, nil
		return true
	end

	--- How far a car at (x, y) is outside the nearest target of a shared run: <= 0 when within a target's radius
	-- (at most TARGETS_MAX distances).
	local function excessShared(run, x, y)
		local best = nil
		for _, c in ipairs(run.centers) do
			local ex = math.sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2) - c.r
			if best == nil or ex < best then best = ex end
		end
		return best or math.huge
	end

	--- Whether a driver's car stands (dyn.speed < STAND_SPEED for QUEUE_STAND s or more: Stress Test's queue).
	local function standing(mp)
		local okD, speed, ts = pcall(function() return mp.dyn.speed, mp.dyn.timeStanding end)
		return okD and type(speed) == "number" and speed < T.STAND_SPEED and type(ts) == "number" and ts >= T.QUEUE_STAND
	end

	--- One candidate of the running sample (every target at once): not ahead last time: skipped while it can't be near
	-- yet, else placed first (one call), its path read only when near any target; a pass at a node counted for each
	-- target holding it; ahead of a Re-time target and standing within QUEUE_RADIUS of it: queued there.
	local function readOne(run, e)
		local prev = run.prevAhead[e]
		local near, x, y = false, nil, nil
		if prev == nil then
			local untilS = run.farUntil[e]
			if untilS ~= nil and run.sampleAt < untilS then
				run.farSkipped = run.farSkipped + 1
				return
			end
			x, y = carPos(e)
			if x == nil then return end
			local ex = excessShared(run, x, y)
			if ex > 0 then
				if run.farCount >= T.FAR_MAX then run.farUntil, run.farCount = {}, 0 end
				if run.farUntil[e] == nil then run.farCount = run.farCount + 1 end
				run.farUntil[e] = run.sampleAt + ex / T.MAX_SPEED
				return
			end
			near = true
		end
		local mp = driverPath(e)
		if mp == nil then
			if prev ~= nil then run.lost = run.lost + 1 end
			return
		end
		run.sNear = run.sNear + 1
		local get, n, cur = pathOf(mp)
		if get == nil then return end
		local hits, readsM = Retime.pathAtMulti(get, n, cur, run.nodeSet, T.LOOK, prev ~= nil)
		run.reads = run.reads + readsM
		local at, stands = nil, nil
		for _, h in ipairs(hits) do
			if h.state == "ahead" then
				at = at or {}
				at[h.node] = { inS = h.inSeg, outS = h.outSeg }
				local k = 0
				for _, tg in ipairs(run.nodeTargets[h.node] or {}) do
					k = k + 1
					if k > T.TARGETS_MAX then break end
					if tg.retime and tg.x ~= nil then
						-- (a driver tracked since the last sample is placed now: one call, as for its queue before)
						if x == nil then
							x, y = carPos(e)
							if x == nil then break end
						end
						if (x - tg.x) ^ 2 + (y - tg.y) ^ 2 <= T.QUEUE_RADIUS * T.QUEUE_RADIUS then
							if stands == nil then stands = standing(mp) end
							if stands then
								local mk = Retime.moveKey(h.inSeg, h.outSeg)
								tg.sQueue[mk] = (tg.sQueue[mk] or 0) + 1
							end
						end
					end
				end
			elseif prev ~= nil and prev.at ~= nil and prev.at[h.node] ~= nil then
				local pa = prev.at[h.node]
				local inS, outS = h.inSeg or pa.inS, h.outSeg or pa.outS
				local mk = Retime.moveKey(inS, outS)
				local key = tostring(h.node) .. "@" .. mk
				run.passes[key] = (run.passes[key] or 0) + 1
				local k = 0
				for _, tg in ipairs(run.nodeTargets[h.node] or {}) do
					k = k + 1
					if k > T.TARGETS_MAX then break end
					local tk = tg.retime and mk or key
					tg.passes[tk] = (tg.passes[tk] or 0) + 1
					if tg.countFn == nil or tg.countFn(h.node, inS, outS) then tg.counted = tg.counted + 1 end
				end
			end
		end
		if at ~= nil and run.sCount < T.TRACK_MAX then
			run.sCount = run.sCount + 1
			run.sAhead[e] = { at = at, near = near or prev ~= nil }
		end
	end

	local function finishSample(run)
		run.samples = run.samples + 1
		run.prevAhead = run.sAhead
		run.prevCount = run.sCount
		run.candSum = run.candSum + #run.cand
		if #run.cand > run.candMax then run.candMax = #run.cand end
		run.nearSum = run.nearSum + run.sNear
		run.lastSampleAt = run.sampleAt
		run.cand = nil
		run.phase = "wait"
		if run.shared then
			-- each target that took part in the whole sample (added before it began): its sample and the interval
			local late = run.everyS * T.LATE_FACTOR
			for _, tg in pairs(run.targets) do
				if tg.addedAt <= run.sampleAt then
					if tg.lastSampleAt ~= nil then
						local dt = run.sampleAt - tg.lastSampleAt
						if dt > tg.everyMax then tg.everyMax = dt end
						if dt > late then tg.late = tg.late + 1 end
					end
					tg.samples = tg.samples + 1
					tg.lastSampleAt = run.sampleAt
					if tg.qSum ~= nil then
						for k, v in pairs(tg.sQueue) do tg.qSum[k] = (tg.qSum[k] or 0) + v end
					end
				end
			end
		end
	end

	--- One frame of measuring within the budget. Returns "measuring" | "sample" (a sample just ended: the caller
	-- re-checks its junctions) | "done" (a target's windowS is over: target.over, no sample started this frame; the
	-- caller removes it) | "idle".
	function M.step()
		local run = M.run
		if M.state ~= "measuring" or run == nil then return M.state end
		local t0 = clock()
		run.frames = run.frames + 1
		local now = M.now()
		-- not stepped for a while (the tool closed without the background plugin, sl_toolcore C.bgStep): the window
		-- and the next sample move on by the gap, so the run still measures WINDOW_S game s of traffic
		local gap = now - (run.lastStepAt or now)
		if gap > T.GAP_FACTOR * run.everyS then
			local shift = gap - run.everyS
			run.t0, run.due = run.t0 + shift, run.due + shift
			if run.shared then
				for _, tg in pairs(run.targets) do
					tg.t0 = tg.t0 + shift
					if tg.lastSampleAt ~= nil then tg.lastSampleAt = tg.lastSampleAt + shift end
				end
			end
			run.gaps, run.gapS = run.gaps + 1, run.gapS + shift
			if run.phase == "read" or run.phase == "gather" then
				-- the half-read sample is stale: dropped (its cars are read again at the next one)
				run.cand, run.gather, run.phase = nil, nil, "wait"
			end
		end
		run.lastStepAt = now
		local res = "measuring"
		if run.phase == "wait" then
			-- a target's own window (Re-time) over: ended before the next sample (at most TARGETS_MAX targets)
			if run.windowed then
				local over = false
				for _, tg in pairs(run.targets) do
					if tg.windowS ~= nil and not tg.over and now - tg.t0 >= tg.windowS and tg.samples > 0 then
						tg.over, over = true, true
					end
				end
				if over then return "done" end
			end
			-- (a shared run without a target reads nothing)
			if now >= run.due and not (run.shared and run.targetCount == 0) then
				run.sampleAt = now
				run.due = now + run.everyS
				gatherStart(run)
				run.sAhead, run.sCount, run.sNear = {}, 0, 0
				for _, tg in pairs(run.targets) do
					if tg.sQueue ~= nil then tg.sQueue = {} end
				end
				run.phase = "gather"
			end
		end
		if run.phase == "gather" then
			local g0 = opts.perf ~= nil and opts.perf:start() or nil
			local done = gatherStep(run, t0)
			if g0 ~= nil then opts.perf:stop(opts.perfName or "gather", g0) end
			if done then
				run.cursor = 1
				run.phase = "read"
			end
		end
		if run.phase == "read" and clock() - t0 < (run.budgetS or T.BUDGET_S) then
			local k = 0
			local list = run.cand
			while run.cursor <= #list do
				local e = list[run.cursor]
				run.cursor = run.cursor + 1
				local okR, errR = pcall(readOne, run, e)
				if not okR then run.err = tostring(errR) end
				k = k + 1
				if k % T.CHECK_EVERY == 0 and clock() - t0 >= (run.budgetS or T.BUDGET_S) then break end
			end
			if run.cursor > #list then
				finishSample(run)
				res = "sample"
			end
		end
		run.busyS = run.busyS + (clock() - t0)
		return res
	end

	--- Ends the measuring run (pending re-route checks go on: the probe's baseline and after-write checks).
	function M.cancel()
		M.run = nil
		M.state = "idle"
	end

	---------------------------------------------------------------------------
	-- Re-route probe: a snapshot of the drivers with the node ahead (from the last sample's ahead set, no extra
	-- reads), re-read later in slices (the path searched for the node up to RECHECK_LOOK elements each way, so a car
	-- that passed long ago is still told from one that dropped the junction).

	--- At most REROUTE_MAX drivers that had `node` ahead and were near at the last sample: { {e, outS} }.
	function M.snapshot(node)
		local run = M.run
		local list = {}
		if run == nil then return list end
		local ids = {}
		for e, a in pairs(run.prevAhead) do
			if a.near and a.at ~= nil and a.at[node] ~= nil then ids[#ids + 1] = e end
		end
		table.sort(ids)
		for _, e in ipairs(ids) do
			if #list >= T.REROUTE_MAX then break end
			list[#list + 1] = { e = e, outS = run.prevAhead[e].at[node].outS }
		end
		return list
	end

	--- Starts a re-route check of a snapshot under `label`; onDone(label, counts) once read
	-- (counts: tracked, same, exit_changed, dropped, gone).
	M.checks = {}
	function M.recheck(label, node, snap, onDone)
		M.checks[#M.checks + 1] = { label = label, node = node, snap = snap, cursor = 1, onDone = onDone,
			counts = { tracked = #snap, same = 0, exit_changed = 0, dropped = 0, gone = 0 } }
	end

	--- Runs the pending re-route checks within the budget (called every frame, measuring or not).
	function M.stepChecks()
		local c = M.checks[1]
		if c == nil then return end
		local t0 = clock()
		while c.cursor <= #c.snap do
			local it = c.snap[c.cursor]
			c.cursor = c.cursor + 1
			local cls = "gone"
			local okR = pcall(function()
				local mp = driverPath(it.e)
				if mp == nil then return end
				local get, n, cur = pathOf(mp)
				if get == nil then
					cls = "dropped"
					return
				end
				local state, _inS, outS = Retime.pathAt(get, n, cur, c.node, math.min(n, T.RECHECK_LOOK), true)
				cls = Retime.rerouteClass(it.outS, state, outS, false)
			end)
			if not okR then cls = "dropped" end
			c.counts[cls] = (c.counts[cls] or 0) + 1
			if clock() - t0 >= T.BUDGET_S then break end
		end
		if c.cursor > #c.snap then
			table.remove(M.checks, 1)
			pcall(c.onDone, c.label, c.counts)
		end
	end

	return M
end

return T
