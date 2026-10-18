-- Smart Lanes "Re-time" (rev 8, PLAN.md "Re-time: phase lengths from measured traffic", RETIME_PLAN.md step A):
-- the pure part. No api here: tests/square_smart_lanes/test_retime.lua drives it.
--
--   R.pathAt(get, n, cur, node, look, behind): where junction `node` lies on a driver's path (its MOVE_PATH
--     elements alternate junction nodes and street edges, docs/findings/lines-vehicles.md): "ahead" (at or after
--     the element the driver is on: approaching or inside the junction) or "behind" (passed), with the movement
--     through it (the street edge before and after it on the path).
--   R.plan(input): new phase durations from the measured movements. Only durations (and a minDuration that
--     would exceed its duration) change: which lanes are red in a phase (lockedLanes) and canSkip stay.
--   R.planQueue(input): the same from averaged standing queues per approach (step B v4, the automatic mode's
--     snapshots; RETIME_PLAN.md "Step B v4"): R.timingOf / R.arrivalOf turn a snapshot's queue into an arrival
--     estimate, R.onCorridor / R.queueIndex / R.queueHits place a car on a junction's approach.
--
-- Timing (R.plan; constants in R.DEFAULTS):
--   * Phase kinds: "all_red" (every connection and crosswalk locked: the pause phases), "walk" (every vehicle
--     connection locked, a crosswalk green: the pedestrian-only phase), "veh" (the rest). all_red and walk
--     phases keep their durations; only veh phases are re-timed.
--   * A movement is "in>out" (approach segment > exit segment). It is served in a veh phase when any road
--     connection in>out is unlocked there (a movement on several lanes, or sharing a lane with another movement,
--     is served as soon as one of its connections is green). A movement served in every veh phase (a curb turn
--     freed all cycle) sets no phase's length and is left out; one served in no phase (red all cycle, or not a
--     connection of the node: a path through a dead end, a U-turn the lanes don't allow) is counted as unmapped.
--   * Demand of a movement: its passes over the window plus queueWeight x its mean queue (cars standing for
--     queueStand s or more, near the junction) x (window / cycle): a queue that stands at every sample is cars
--     the green did not clear, once per cycle, so it is added as that many extra passes per cycle (weighted down:
--     part of every queue is the normal wait through red, already counted as passes once served).
--   * Phase load: per approach, the demand of its movements served in the phase (a movement served in k phases
--     adds 1/k to each), divided by the approach's entry lanes (a 3-lane approach clears three cars in the time
--     a 1-lane one clears one); the phase's load is its largest approach (the critical approach).
--   * Cycle (rev 8 v2, user 2026-10-14: "the cycle stays" left a saturated junction at the game's / our short cycle;
--     players: "shorter phases than default harm busy junctions"): chosen from the measurement, Webster's optimum
--     cycle C = (1.5 L + 5) / (1 - Y), clamped into cycleMin..cycleMax (40..120 s):
--       - flow q of a veh phase = its load (the critical approach's demand per entry lane, below) per hour;
--       - saturation flow s (cars per entry lane per hour of green): estimated from the measurement where a phase's
--         critical approach queued all the time (mean queue >= queueSat cars per lane: its green ran full, so its
--         passes per lane over its green seconds in the window are what a green clears); the mean of those
--         estimates, clamped to satMin..satMax; else the option satFlow (1800, the textbook value);
--       - Y = sum of q / s over the veh phases (the critical flow ratios);
--       - L = lost time per cycle: every non-veh phase's duration (all-reds, pedestrian phases: counted whole, a
--         skippable one may end earlier) + startLost (2 s) per veh phase (the first cars' start-up);
--       - saturated (Y >= yMax 0.9, where Webster's C runs away) or persistent queues (a critical approach with
--         queueSat or more cars per lane on average): cycleMax. The reason is logged (cycle_reason=webster | min |
--         max | saturated | queues | floors | balanced | unconfirmed).
--       - v3 (Light plans A/B run 2, RETIME_PLAN.md "Cycle rule v3"): such a long cycle (saturated, queues, max) is
--         capped at max(balancedCycle 75 s, the current cycle) when the junction is balanced (the busiest veh
--         phase's share of the loads at most balanceRatio 1.25 x an equal share: 62.5 % for two roads): every road
--         is waiting alike, a longer cycle only lengthens every red (reason balanced). Manual and automatic.
--       - Step B damping (opts.smooth, opts.confirmLong; input.prev = { load, long } of the junction's previous
--         window): the loads are smoothed with the previous window's (smooth x this + (1 - smooth) x previous), and a
--         long cycle is only lengthened toward when the previous window was long too, else the cycle holds and only
--         the greens move (reason unconfirmed). res.loadRaw: this window's loads; res.load: the ones used; res.long,
--         res.balanced, res.share.
--     The fixed phases (all_red, walk) keep their seconds; the veh phases share the rest in
--     proportion to w = (1 - keepShare) x load share + keepShare x current share (keepShare 0.25 damps sampling
--     noise and keeps a phase with no measured traffic from collapsing to its floor), each at least its floor,
--     with one scale factor solved by bisection (as sl_phaseplan durations); at most 60 s each (the slider).
--   * Floors: minGreen (6 s), or the phase's current duration when the player made it shorter; pedestrians: a
--     crosswalk green in veh phases keeps at least its crossing time (crossed road width / 1.2 m/s + 3 s, as
--     sl_phaseplan pedMin; input pedNeed[k]) over those phases (less what the walk phases it is green in give),
--     split in proportion to their current durations.
--   * Live city run 2026-10-15 (R.alwaysGreen, options keepLoadedOnShrink / idleCrosswalkCap / freedQueueOut):
--     connections green in more than half of the phases (freed curb turns) make no phase "veh" and add no queue to
--     their approach; a phase without traffic gets at most its current seconds (crosswalk floor, a capped phase's
--     rest); a cycle shrinking for light traffic keeps phases with at least half an equal share of the loads at
--     min(current, PP.gameGreen of their critical approach's lanes).
--   * Whole seconds 1..60 (the Crossing window's slider); minDuration = min(current minDuration, new duration).
--   * Too small a sample (fewer than minSamples samples, or fewer than minPasses passes and minQueue queued cars)
--     or no measured traffic on a movement that some phase serves: keep (reason small_sample / no_mapped_traffic).
--   * Hysteresis: changed only when some veh phase moves by at least max(hystAbs, hystRel x its current
--     duration) seconds; else keep (reason fits). Step B's periodic re-timing uses the same threshold.
--   * Gradual steps (opts.maxCycleStep, step B only; the manual Re-time passes none): the cycle Webster asks for
--     (res.cycleWanted) is clamped to the current cycle +- maxCycleStep before the greens are split
--     (res.cycleStepped = true when it was), so automatic writes walk toward it over several intervals.

local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"

local R = {}

R.DEFAULTS = {
	minGreen = 6,        -- s, least green of a re-timed vehicle phase (sl_phaseplan minGreen)
	cycleMin = 40,       -- s (sl_phaseplan cycleMin)
	cycleMax = 120,      -- s, the longest cycle Re-time picks (saturated junctions; the game's default cycles: 71-78 s)
	satFlow = 1800,      -- cars per entry lane per hour of green when the measurement gives no estimate
	satMin = 1200,       -- range of a measured saturation flow estimate
	satMax = 3600,
	queueSat = 4,        -- mean queued cars per entry lane of a critical approach that count as a standing queue
	startLost = 2,       -- s lost per veh phase (start-up)
	yMax = 0.9,          -- critical flow ratio sum at and above which the junction counts as saturated
	keepShare = 0.25,    -- share of the current durations kept in the weights (damping)
	queueWeight = 0.5,   -- weight of the queue term in a movement's demand
	pedSpeed = 1.2,      -- m/s (sl_phaseplan)
	pedClear = 3,        -- s (sl_phaseplan)
	laneWidth = 4.5,     -- m per road lane (sl_phaseplan)
	defaultCrossLen = 14, -- m (sl_phaseplan)
	minSamples = 20,     -- samples (of 60 at 3 s over 180 s)
	minPasses = 12,      -- passes over the window...
	minQueue = 3,        -- ...or this many queued cars summed over the movements' means
	hystAbs = 3,         -- s
	hystRel = 0.15,      -- of the phase's current duration
	maxCycleStep = nil,  -- s: the most the cycle may move in one write (nil: any; step B's automatic re-timing passes 20)
	balanceRatio = 1.25, -- balanced: the busiest veh phase's load share at most this x an equal share (2 phases: 62.5 %)
	balancedCycle = 75,  -- s: a balanced saturated junction's cycle is not lengthened beyond max(this, the current cycle)
	smooth = nil,        -- weight of this window's loads against input.prev's (step B passes 0.5; nil: no smoothing)
	confirmLong = false, -- step B: a long cycle (saturated / queues / max) is only lengthened toward after two such windows
	-- R.planQueue (step B v4, the automatic mode's queue snapshots)
	minSnaps = 8,        -- snapshots a junction needs before a decision
	quietQueue = 1,      -- mean standing cars on all approaches together below which a junction is quiet (never written)
	queueStand = 5,      -- s a car stands before it counts as queued (R.arrivalOf: the red time it can be seen in)
	minRedE = 2,         -- s, the least effective red R.arrivalOf divides by
	arriveMax = 10,      -- cars per s, the most one approach's arrival estimate may say
	-- live city run 2026-10-15 fixes (false: the old behavior, for the regression tests)
	keepLoadedOnShrink = true, -- a shorter cycle for light traffic keeps loaded phases at min(current, the game's green)
	idleCrosswalkCap = true,   -- a phase without traffic gets at most its current seconds (a crosswalk, a capped phase)
	freedQueueOut = true,      -- a movement green all cycle (a freed turn) adds no queue to its approach (cycle rule)
}
R.MIN_DURATION = 1
R.MAX_DURATION = 60
R.MAX_MIN_DURATION = 30

local function options(opts)
	local o = {}
	for k, v in pairs(R.DEFAULTS) do o[k] = v end
	for k, v in pairs(opts or {}) do o[k] = v end
	return o
end
R.options = options

local function sortedKeys(t)
	local list = {}
	for k in pairs(t) do list[#list + 1] = k end
	table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	return list
end

--- Movement key of a pass through a junction: "<in segment>><out segment>".
function R.moveKey(inSeg, outSeg)
	return tostring(inSeg) .. ">" .. tostring(outSeg)
end

--- The approach segment of a movement key (nil when malformed).
function R.approachOf(key)
	local a = tostring(key):match("^([^>]+)>")
	return tonumber(a) or a
end

--- Where `node` lies on a driver's path. get(i): the entity of path element i (0-based; nil when unreadable),
-- n: the number of elements, cur: the element the driver is on (pathPos.edgeIndex). Looks at most `look`
-- elements ahead (cur .. cur + look), and, with behind = true, as many behind (cur - 1 down to cur - look).
-- Returns state ("ahead" | "behind" | nil), inSeg, outSeg (the elements before and after the node; nil at
-- the path's ends), reads (elements read).
function R.pathAt(get, n, cur, node, look, behind)
	if type(n) ~= "number" or type(cur) ~= "number" or n <= 0 then return nil, nil, nil, 0 end
	look = look or 8
	local reads = 0
	local function at(i)
		if i < 0 or i >= n then return nil end
		reads = reads + 1
		return get(i)
	end
	local found, state = nil, nil
	local last = math.min(n - 1, cur + look)
	for i = math.max(0, cur), last do
		if at(i) == node then
			found, state = i, "ahead"
			break
		end
	end
	if found == nil and behind then
		for i = math.min(cur - 1, n - 1), math.max(0, cur - look), -1 do
			if at(i) == node then
				found, state = i, "behind"
				break
			end
		end
	end
	if found == nil then return nil, nil, nil, reads end
	return state, at(found - 1), at(found + 1), reads
end

--- R.pathAt for several junctions at once (step B's shared sampler, sl_autoretime.lua): every node of nodeSet
-- ({ [node] = true }) on the driver's path within `look` elements ahead (cur .. cur + look) is "ahead"; with
-- behind = true, every other one within `look` elements behind (cur - 1 down to cur - look) is "behind". Each path
-- element is read at most once. Returns a list { { node, state, inSeg, outSeg } } (in path order: ahead ones
-- nearest first, then behind ones nearest first) and the elements read.
function R.pathAtMulti(get, n, cur, nodeSet, look, behind)
	if type(n) ~= "number" or type(cur) ~= "number" or n <= 0 or type(nodeSet) ~= "table" then return {}, 0 end
	look = look or 8
	local reads, cache = 0, {}
	local function at(i)
		if i < 0 or i >= n then return nil end
		local v = cache[i]
		if v == nil then
			reads = reads + 1
			v = get(i)
			cache[i] = v == nil and false or v
		end
		return v or nil
	end
	local hits, seen = {}, {}
	for i = math.max(0, cur), math.min(n - 1, cur + look) do
		local e = at(i)
		if e ~= nil and nodeSet[e] and not seen[e] then
			seen[e] = true
			hits[#hits + 1] = { node = e, i = i, state = "ahead", inSeg = at(i - 1), outSeg = at(i + 1) }
		end
	end
	if behind then
		for i = math.min(cur - 1, n - 1), math.max(0, cur - look), -1 do
			local e = at(i)
			if e ~= nil and nodeSet[e] and not seen[e] then
				seen[e] = true
				hits[#hits + 1] = { node = e, i = i, state = "behind", inSeg = at(i - 1), outSeg = at(i + 1) }
			end
		end
	end
	return hits, reads
end

--- R.pathAtMulti for a driver tracked since the last sample (step B's sampler; Light plans A/B run 2: 4-junction
-- windows read ~12.8k path elements per sample, ~16 per near driver, mostly re-reading paths read 3 s earlier).
-- track: what the last call returned for this driver ({ n, hi (the furthest element read), at = { [node] = { i, inS,
-- outS } } }), nil for a driver not tracked. While the path keeps its length and every tracked node is still at its
-- index (one read each), the known nodes are placed by their index (ahead: i >= cur, else behind) and only the
-- elements that came within `look` ahead since are read; otherwise (a new driver, a re-route) the full R.pathAtMulti
-- (behind = a track was given). Returns hits (as R.pathAtMulti, with i, in path order), reads, the new track (the
-- nodes still ahead) and "full" | "inc".
function R.pathAtTrack(get, n, cur, nodeSet, look, track)
	if type(n) ~= "number" or type(cur) ~= "number" or n <= 0 or type(nodeSet) ~= "table" then return {}, 0, nil, "full" end
	look = look or 8
	local valid = type(track) == "table" and track.n == n and type(track.at) == "table" and type(track.hi) == "number"
	local reads = 0
	if valid then
		local k = 0
		for node, a in pairs(track.at) do
			k = k + 1
			if k > 16 or type(a) ~= "table" or type(a.i) ~= "number" or a.i < 0 or a.i >= n then
				valid = false
				break
			end
			reads = reads + 1
			if get(a.i) ~= node then
				valid = false
				break
			end
		end
	end
	if not valid then
		local hits, r = R.pathAtMulti(get, n, cur, nodeSet, look, track ~= nil)
		local t = { n = n, hi = math.min(n - 1, cur + look), at = {} }
		for _, h in ipairs(hits) do
			if h.state == "ahead" then t.at[h.node] = { i = h.i, inS = h.inSeg, outS = h.outSeg } end
		end
		return hits, r + reads, t, "full"
	end
	local hits, t = {}, { n = n, hi = track.hi, at = {} }
	for node, a in pairs(track.at) do
		local st = a.i >= cur and "ahead" or "behind"
		hits[#hits + 1] = { node = node, i = a.i, state = st, inSeg = a.inS, outSeg = a.outS }
		if st == "ahead" then t.at[node] = a end
	end
	local cache = {}
	local function at(i)
		if i < 0 or i >= n then return nil end
		local v = cache[i]
		if v == nil then
			reads = reads + 1
			v = get(i)
			cache[i] = v == nil and false or v
		end
		return v or nil
	end
	local last = math.min(n - 1, cur + look)
	for i = math.max(track.hi + 1, cur), last do
		local e = at(i)
		if e ~= nil and nodeSet[e] and t.at[e] == nil and track.at[e] == nil then
			local h = { node = e, i = i, state = "ahead", inSeg = at(i - 1), outSeg = at(i + 1) }
			hits[#hits + 1] = h
			t.at[e] = { i = i, inS = h.inSeg, outS = h.outSeg }
		end
	end
	if last > t.hi then t.hi = last end
	table.sort(hits, function(a, b) return a.i < b.i end)
	return hits, reads, t, "inc"
end

--- The connections (0-based) that are green in more than half of the phases (with at least two phases): freed
-- turns (Free curb turn Always / When safe, sl_lights) green in the pauses and the pedestrian phase too. They don't
-- make a phase a vehicle phase (R.kinds). { [x] = true }.
function R.alwaysGreen(nConns, states)
	local n = #(states or {})
	local out = {}
	if n < 2 then return out end
	local count = {}
	for _, st in ipairs(states) do
		local set = {}
		for _, l in ipairs(st.locked or {}) do set[l] = true end
		for x = 0, nConns - 1 do
			if not set[x] then count[x] = (count[x] or 0) + 1 end
		end
	end
	for x, c in pairs(count) do
		if c * 2 > n then out[x] = true end
	end
	return out
end

--- Phase kind of each state: "all_red" | "walk" | "veh" (see the header). states[i].locked: 0-based indices
-- into the connections (0 .. nConns - 1) and then the crosswalks. A connection green in more than half of the
-- phases (R.alwaysGreen: a freed curb turn) does not count: live city run 2026-10-15 (session live, free_turn=always):
-- the game's 6 phases all read as veh, the pedestrian phase got the crosswalks' 26 s floor and the through phases
-- were squeezed to 6-9 s (27.1/6/27.1/6/3/9 -> 6/6/9/6/26/6).
function R.kinds(nConns, nCross, states)
	local out = {}
	local always = R.alwaysGreen(nConns, states)
	for p, st in ipairs(states) do
		local set = {}
		for _, l in ipairs(st.locked or {}) do set[l] = true end
		local vehGreen, walkGreen = false, false
		for x = 0, nConns - 1 do
			if not set[x] and not always[x] then vehGreen = true break end
		end
		for k = 0, nCross - 1 do
			if not set[nConns + k] then walkGreen = true break end
		end
		if vehGreen then out[p] = "veh" elseif walkGreen then out[p] = "walk" else out[p] = "all_red" end
	end
	return out
end

--- Movements of a node's connections and the veh phases each is served in: { [key] = { [p] = true } }, plus
-- the entry lanes per approach { [seg] = n } (distinct lane0 of its road connections).
function R.served(conns, states, kinds)
	local served, laneSet, lanes = {}, {}, {}
	for i, c in ipairs(conns) do
		if c.withRoad ~= false then
			local key = R.moveKey(c.segment0, c.segment1)
			if served[key] == nil then served[key] = {} end
			local x = i - 1
			for p, st in ipairs(states) do
				if kinds[p] == "veh" then
					local red = false
					for _, l in ipairs(st.locked or {}) do
						if l == x then red = true break end
					end
					if not red then served[key][p] = true end
				end
			end
			local s = c.segment0
			laneSet[s] = laneSet[s] or {}
			if not laneSet[s][c.lane0] then
				laneSet[s][c.lane0] = true
				lanes[s] = (lanes[s] or 0) + 1
			end
		end
	end
	return served, lanes
end

--- Pedestrian need (s) of each crosswalk k (1-based): its crossed road's road lanes x laneWidth / pedSpeed +
-- pedClear, defaultCrossLen when unknown. cws[k]: the crosswalk entity (a segment id at the node);
-- roadLanes[seg]: road + tram lanes of that segment (both ways).
function R.pedNeed(cws, roadLanes, opts)
	local o = options(opts)
	local out = {}
	for k, cw in ipairs(cws or {}) do
		local n = roadLanes and roadLanes[cw]
		local len = (type(n) == "number" and n > 0) and n * o.laneWidth or o.defaultCrossLen
		out[k] = len / o.pedSpeed + o.pedClear
	end
	return out
end

local function round(v) return math.floor(v + 0.5) end

--- The cycle Re-time aims for (see the header, "Cycle"). c: { veh (veh phase indices), cur (durations), oldCycle,
-- fixed (s of the non-veh phases), window (s), load ({ [p] = critical demand per entry lane over the window }),
-- crit ({ [p] = its approach }), lanes ({ [approach] = entry lanes }), servedPasses ({ [p] = { [approach] = passes
-- served in p } }), apQueue ({ [approach] = mean queued cars }) }. Fills res.y, res.lost, res.sat, res.satSrc,
-- res.flow, res.cycleReason; returns the cycle in s (before the floors: R.plan may need more).
function R.cycleFor(c, o, res)
	o = o or options()
	local window = (type(c.window) == "number" and c.window > 0) and c.window or 180
	-- saturation flow: from the phases whose critical approach queued all the time
	local est, nEst, queued = 0, 0, false
	for _, p in ipairs(c.veh) do
		local a = c.crit[p]
		if a ~= nil then
			local ln = math.max(1, c.lanes[a] or 1)
			if (c.apQueue[a] or 0) / ln >= o.queueSat then
				queued = true
				local greenS = (c.oldCycle > 0) and (c.cur[p] / c.oldCycle * window) or 0
				local served = (c.servedPasses[p] and c.servedPasses[p][a] or 0) / ln
				if greenS > 0 and served > 0 then
					est = est + served / greenS * 3600
					nEst = nEst + 1
				end
			end
		end
	end
	local sat, satSrc = o.satFlow, "opt"
	if nEst > 0 then
		sat = math.min(o.satMax, math.max(o.satMin, est / nEst))
		satSrc = "est"
	end
	local Y, flow = 0, {}
	for _, p in ipairs(c.veh) do
		flow[p] = (c.load[p] or 0) / window * 3600
		Y = Y + flow[p] / sat
	end
	local lost = c.fixed + o.startLost * #c.veh
	local cycle, why
	if Y >= o.yMax then
		cycle, why = o.cycleMax, "saturated"
	elseif queued then
		cycle, why = o.cycleMax, "queues"
	else
		cycle, why = (1.5 * lost + 5) / (1 - Y), "webster"
		if cycle < o.cycleMin then cycle, why = o.cycleMin, "min"
		elseif cycle > o.cycleMax then cycle, why = o.cycleMax, "max" end
	end
	res.y, res.lost, res.sat, res.satSrc, res.flow, res.cycleReason = Y, lost, sat, satSrc, flow, why
	return cycle
end

--- The cycle and the greens from the veh phases' loads (R.plan and R.planQueue share it). c: { states, kinds, cur,
-- oldCycle, veh, nConns, nCross, load ({ [p] = { [approach] = demand over the window } }), lanes, servedPasses, apQueue,
-- window (s), pedNeed, prev, samples }. Fills and returns res.
local function finishPlan(res, c, o)
	local states, kinds, cur, oldCycle, veh = c.states, c.kinds, c.cur, c.oldCycle, c.veh
	local nConns, nCross, load, lanes, window = c.nConns, c.nCross, c.load, c.lanes, c.window
	-- the critical approach of each veh phase, per entry lane
	local y, sumY, sumCur, crit, raw = {}, 0, 0, {}, {}
	local prev = type(c.prev) == "table" and c.prev or nil
	local prevLoad = (prev ~= nil and type(prev.load) == "table") and prev.load or nil
	for _, p in ipairs(veh) do
		local m = 0
		for _, a in ipairs(sortedKeys(load[p])) do
			local v = load[p][a] / math.max(1, lanes[a] or 1)
			if v > m then m, crit[p] = v, a end
		end
		raw[p] = m
		-- damping (step B): exponential smoothing with the junction's previous window
		if type(o.smooth) == "number" and o.smooth > 0 and o.smooth < 1 and prevLoad ~= nil and type(prevLoad[p]) == "number" then
			m = o.smooth * m + (1 - o.smooth) * prevLoad[p]
			res.smoothed = true
		end
		y[p] = m
		sumY = sumY + m
		sumCur = sumCur + cur[p]
	end
	res.load, res.loadRaw = y, raw
	-- balanced: the roads' critical flow ratios about equal (the busiest phase's share of the loads)
	local maxY = 0
	for _, p in ipairs(veh) do
		if y[p] > maxY then maxY = y[p] end
	end
	res.share = sumY > 0 and maxY / sumY or 0
	res.balanced = #veh >= 2 and sumY > 0 and res.share <= o.balanceRatio / #veh
	-- weights
	local w = {}
	for _, p in ipairs(veh) do
		local share = sumY > 0 and y[p] / sumY or 1 / #veh
		local keep = sumCur > 0 and cur[p] / sumCur or 1 / #veh
		w[p] = (1 - o.keepShare) * share + o.keepShare * keep
	end
	-- floors
	local f = {}
	for _, p in ipairs(veh) do
		f[p] = (cur[p] > 0 and cur[p] < o.minGreen) and cur[p] or o.minGreen
	end
	local need = c.pedNeed or {}
	for k = 1, nCross do
		local x = nConns + k - 1
		local fixedGreen, on, sumOn = 0, {}, 0
		for p, st in ipairs(states) do
			local red = false
			for _, l in ipairs(st.locked or {}) do
				if l == x then red = true break end
			end
			if not red then
				if kinds[p] == "veh" then
					on[#on + 1] = p
					sumOn = sumOn + cur[p]
				else
					fixedGreen = fixedGreen + cur[p]
				end
			end
		end
		local nk = (type(need[k]) == "number" and need[k] or (o.defaultCrossLen / o.pedSpeed + o.pedClear)) - fixedGreen
		if nk > 0 and #on > 0 then
			for _, p in ipairs(on) do
				local part = sumOn > 0 and nk * cur[p] / sumOn or nk / #on
				-- a phase without traffic is not lengthened for a crosswalk (at most its current seconds)
				if y[p] <= 0 and o.idleCrosswalkCap ~= false then part = math.min(part, cur[p]) end
				if part > f[p] then f[p] = part end
			end
		end
	end
	-- cycle and the veh phases' share of it
	local fixed = 0
	for p = 1, #states do
		if kinds[p] ~= "veh" then fixed = fixed + cur[p] end
	end
	local target = R.cycleFor({ veh = veh, cur = cur, oldCycle = oldCycle, fixed = fixed, window = window, load = y,
		crit = crit, lanes = lanes, servedPasses = c.servedPasses, apQueue = c.apQueue, samples = c.samples }, o, res)
	res.cycleWanted = target
	-- a long cycle (Re-time v3, Light plans A/B run 2, RETIME_PLAN.md "Cycle rule v3"): saturated, standing queues or
	-- Webster beyond cycleMax
	local why = res.cycleReason
	res.long = why == "saturated" or why == "queues" or why == "max"
	if res.long then
		-- every road about equally saturated: a longer cycle only lengthens every red (run 2: 112-120 s cycles gave
		-- +0-2 % throughput and +27 % queues against the axis plan's 52-62 s); shift green, stretch at most to
		-- balancedCycle (or keep a longer current cycle)
		if res.balanced then
			local cap = math.max(o.balancedCycle, oldCycle)
			if target > cap then target, res.cycleReason = cap, "balanced" end
		end
		-- damping (step B): lengthening needs the previous window long too (run 2: g2v 62 > 82 > 62 > 82 s, g6v 53 >
		-- 73 > 53 s, a one-window saturation estimate that came and went)
		if o.confirmLong and target > oldCycle and not (prev ~= nil and prev.long == true) then
			target, res.cycleReason = oldCycle, "unconfirmed"
		end
	end
	-- step B (automatic re-timing, RETIME_PLAN.md "Step B"): the cycle moves at most maxCycleStep s per write, so a
	-- run converges over several writes instead of jumping (50 -> 120 s at once can spill queues into the neighbors)
	if type(o.maxCycleStep) == "number" and o.maxCycleStep > 0 and oldCycle > 0 then
		local lo, hi = oldCycle - o.maxCycleStep, oldCycle + o.maxCycleStep
		if target > hi then target, res.cycleStepped = hi, true
		elseif target < lo then target, res.cycleStepped = lo, true end
	end
	-- a shorter cycle for light traffic (not a long one being capped) never cuts a phase carrying at least half an
	-- equal share of the loads below min(its current seconds, the game's default green for its critical approach's lanes,
	-- sl_phaseplan PP.gameGreen): the idle phases give the time back (live city run 2026-10-15: through phases at the
	-- game's 27.1 s cut to 6-9 s). Applied after the split: it only raises such a phase (the cycle may end above
	-- the target, never above the current one), never lowers another.
	local keepF = {}
	if o.keepLoadedOnShrink ~= false and target < oldCycle and not res.long and sumY > 0 then
		for _, p in ipairs(veh) do
			if y[p] > 0 and y[p] * #veh * 2 >= sumY then
				keepF[p] = math.min(cur[p], PP.gameGreen(lanes[crit[p]] or 1))
			end
		end
	end
	local green = target - fixed
	local sumF = 0
	for _, p in ipairs(veh) do sumF = sumF + f[p] end
	if green <= sumF then res.cycleReason = "floors" end
	-- a phase without traffic gets at most its current seconds (or its floor): the time a loaded phase can't take
	-- (60 s slider cap) is not handed to it (live city run 2026-10-15 node 9594: 36 s for an empty side road)
	local cap = {}
	for _, p in ipairs(veh) do
		cap[p] = (y[p] <= 0 and o.idleCrosswalkCap ~= false) and math.max(f[p], cur[p]) or R.MAX_DURATION
	end
	local function total(s)
		local t = 0
		for _, p in ipairs(veh) do t = t + math.max(f[p], math.min(cap[p], s * w[p])) end
		return t
	end
	local d = {}
	if green <= sumF then
		for _, p in ipairs(veh) do d[p] = f[p] end
	else
		local lo, hi = 0, 0
		for _, p in ipairs(veh) do
			if w[p] > 0 then hi = math.max(hi, green / w[p] * #veh) end
		end
		for _ = 1, 60 do
			local mid = (lo + hi) / 2
			if total(mid) < green then lo = mid else hi = mid end
		end
		-- (a phase at the 60 s slider cap leaves its share to the others)
		for _, p in ipairs(veh) do d[p] = math.max(f[p], math.min(cap[p], hi * w[p])) end
	end
	for _, p in ipairs(veh) do
		if keepF[p] ~= nil and d[p] < keepF[p] then
			d[p] = keepF[p]
			res.keptLoaded = true
		end
	end
	local durations, mins, cycle, maxDelta, changed = {}, {}, 0, 0, false
	for p, st in ipairs(states) do
		local v
		if kinds[p] == "veh" then
			v = round(d[p])
			local floorUp = math.ceil(math.max(f[p], keepF[p] or 0) - 1e-9)
			if v < floorUp then v = floorUp end
			v = math.max(R.MIN_DURATION, math.min(R.MAX_DURATION, v))
			local delta = math.abs(v - cur[p])
			if delta > maxDelta then maxDelta = delta end
			if delta >= math.max(o.hystAbs, o.hystRel * cur[p]) then changed = true end
		else
			v = cur[p]
		end
		durations[p] = v
		local m = type(st.minDuration) == "number" and st.minDuration or 0
		if m > v then m = math.floor(v * 2) / 2 end
		if m > R.MAX_MIN_DURATION then m = R.MAX_MIN_DURATION end
		mins[p] = m
		cycle = cycle + v
	end
	res.durations, res.minDurations, res.cycle, res.maxDelta, res.changed = durations, mins, cycle, maxDelta, changed
	res.reason = changed and "write" or "fits"
	return res
end

--- New durations from measured traffic. input:
--   conns     the node's connections (config order; Rules.conn tables: segment0, lane0, segment1, lane1, withRoad)
--   nCross    crosswalk count
--   states    { { locked = {indices}, duration, minDuration, canSkip } } as read
--   passes    { [moveKey] = cars that passed in the window }
--   queue     { [moveKey] = mean cars queued per sample }
--   windowS   the measured game seconds; samples: samples taken
--   pedNeed   { [k] = s } per crosswalk (optional; R.pedNeed)
-- opts: R.DEFAULTS overrides.
-- Returns { keep = true, reason } or { durations, minDurations, cycle, oldCycle, changed, maxDelta, load,
-- kinds, unmapped, always, reason = "write" | "fits", y (critical flow ratio sum), lost (s per cycle), sat (cars per
-- lane per green hour), satSrc ("est" | "opt"), cycleReason, flow ({ [p] = cars per lane per hour }) }; every result
-- has kinds, total (passes), queued, demand.
function R.plan(input, opts)
	local o = options(opts)
	local conns, states = input.conns or {}, input.states or {}
	local nConns, nCross = #conns, input.nCross or 0
	local kinds = R.kinds(nConns, nCross, states)
	local served, lanes = R.served(conns, states, kinds)
	local cur, oldCycle = {}, 0
	for p, st in ipairs(states) do
		cur[p] = type(st.duration) == "number" and st.duration or 0
		oldCycle = oldCycle + cur[p]
	end
	local veh = {}
	for p = 1, #states do
		if kinds[p] == "veh" then veh[#veh + 1] = p end
	end
	local res = { kinds = kinds, oldCycle = oldCycle, unmapped = 0, always = 0, total = 0, queued = 0, demand = {} }
	local passes, queue = input.passes or {}, input.queue or {}
	for _, k in ipairs(sortedKeys(passes)) do res.total = res.total + (passes[k] or 0) end
	for _, k in ipairs(sortedKeys(queue)) do res.queued = res.queued + (queue[k] or 0) end
	if #veh == 0 then
		res.keep, res.reason = true, "no_vehicle_phase"
		return res
	end
	if (input.samples or 0) < o.minSamples or (res.total < o.minPasses and res.queued < o.minQueue) then
		res.keep, res.reason = true, "small_sample"
		return res
	end
	-- demand per movement
	local cycleRef = oldCycle > 0 and oldCycle or o.cycleMax
	local window = (type(input.windowS) == "number" and input.windowS > 0) and input.windowS or cycleRef
	local keys = {}
	for k in pairs(passes) do keys[k] = true end
	for k in pairs(queue) do keys[k] = true end
	local load, servedPasses, apQueue = {}, {}, {}
	for _, p in ipairs(veh) do load[p], servedPasses[p] = {}, {} end
	local mapped = false
	for _, key in ipairs(sortedKeys(keys)) do
		local d = (passes[key] or 0) + o.queueWeight * (queue[key] or 0) * (window / cycleRef)
		res.demand[key] = d
		local sv = served[key]
		local list = {}
		if sv ~= nil then
			for _, p in ipairs(veh) do
				if sv[p] then list[#list + 1] = p end
			end
		end
		-- the approach's standing queue (the cycle rule's "queues"), without a movement green all cycle (a freed curb
		-- turn: live city run 2026-10-15 node 9594, a 20-car queue on the freed 12085>7448 lengthened the cycle to 120 s)
		local qa = R.approachOf(key)
		if qa ~= nil and (queue[key] or 0) ~= 0 and not (#list == #veh and #veh > 1 and o.freedQueueOut ~= false) then
			apQueue[qa] = (apQueue[qa] or 0) + queue[key]
		end
		if #list == 0 then
			res.unmapped = res.unmapped + (passes[key] or 0)
		elseif #list == #veh and #veh > 1 then
			res.always = res.always + (passes[key] or 0)
		elseif d > 0 then
			mapped = true
			local a = R.approachOf(key)
			for _, p in ipairs(list) do
				load[p][a] = (load[p][a] or 0) + d / #list
				servedPasses[p][a] = (servedPasses[p][a] or 0) + (passes[key] or 0) / #list
			end
		end
	end
	if not mapped then
		res.keep, res.reason = true, "no_mapped_traffic"
		return res
	end
	return finishPlan(res, { states = states, kinds = kinds, cur = cur, oldCycle = oldCycle, veh = veh, nConns = nConns,
		nCross = nCross, load = load, lanes = lanes, servedPasses = servedPasses, apQueue = apQueue, window = window,
		pedNeed = input.pedNeed, prev = input.prev, samples = input.samples }, o)
end

--- The veh phases each approach (its approach segment) has green in: { [approach] = { p, ... } } (ascending). A
-- movement served in every veh phase (a curb turn freed all cycle) gives its approach no phase (it never waits for
-- one); an approach whose movements are all such has no entry. served, veh: R.served's map and the veh phase list.
function R.approachPhases(served, veh)
	local sets = {}
	for _, key in ipairs(sortedKeys(served)) do
		local a = R.approachOf(key)
		local sv = served[key]
		local k = 0
		for _, p in ipairs(veh) do
			if sv[p] then k = k + 1 end
		end
		if a ~= nil and k > 0 and not (k == #veh and #veh > 1) then
			sets[a] = sets[a] or {}
			for _, p in ipairs(veh) do
				if sv[p] then sets[a][p] = true end
			end
		end
	end
	local out = {}
	for a, set in pairs(sets) do
		local list = {}
		for _, p in ipairs(veh) do
			if set[p] then list[#list + 1] = p end
		end
		out[a] = list
	end
	return out
end

--- A junction's timing as the queue snapshots need it (step B v4): { cycle (s), red = { [approach] = s of the cycle
-- the approach has no green in }, lanes = { [approach] = entry lanes }, phases = R.approachPhases }. conns / states as
-- R.plan's input (states[i].locked / duration).
function R.timingOf(conns, nCross, states)
	conns, states = conns or {}, states or {}
	local kinds = R.kinds(#conns, nCross or 0, states)
	local served, lanes = R.served(conns, states, kinds)
	local veh, cycle = {}, 0
	for p, st in ipairs(states) do
		local d = type(st.duration) == "number" and st.duration or 0
		cycle = cycle + d
		if kinds[p] == "veh" then veh[#veh + 1] = p end
	end
	local phases = R.approachPhases(served, veh)
	local red = {}
	for a, list in pairs(phases) do
		local g = 0
		for _, p in ipairs(list) do g = g + (type(states[p].duration) == "number" and states[p].duration or 0) end
		red[a] = math.max(0, cycle - g)
	end
	return { cycle = cycle, red = red, lanes = lanes, phases = phases }
end

--- Arrivals (cars per s, all its lanes) of an approach from its standing queue (step B v4): q = the cars standing
-- queueStand s or more at one snapshot, cycle and red (s) the timing in force then. A fixed-time queue (D/D/1) holds
-- on average lambda' x r^2 / (2 C) cars, lambda' = lambda / (1 - lambda / s) (the arrivals swollen by the discharge);
-- a car is counted only after queueStand s of standing, so r is the red less that (at least minRedE). Returns
-- lambda' (R.planQueue turns it back into lambda), capped at arriveMax; nil without a cycle.
function R.arrivalOf(q, cycle, red, opts)
	local o = opts or R.DEFAULTS
	if type(q) ~= "number" or type(cycle) ~= "number" or cycle <= 0 or type(red) ~= "number" then return nil end
	local re = math.max(o.minRedE or 2, red - (o.queueStand or 5))
	local v = 2 * cycle * math.max(0, q) / (re * re)
	return math.min(o.arriveMax or 10, v)
end

--- New durations from the averaged queue snapshots (step B v4, the automatic mode; RETIME_PLAN.md "Step B v4"). input:
--   conns, nCross, states, pedNeed, prev  as R.plan
--   arrive  { [approach] = lambda' (cars per s, all its lanes), the snapshots' average of R.arrivalOf }
--   queue   { [approach] = mean standing cars }
--   snaps   snapshots behind the averages
-- Per approach: lambda' per entry lane, back to arrivals lambda = lambda' s / (s + lambda') (s = satFlow), so a queue
-- that grows without end (saturated) reads as lambda -> s; its flow (cars per lane per hour) is the approach's load in
-- EVERY veh phase it has green in (R.approachPhases; the axis plan: one phase per road, its two approaches; a classic
-- or hand-made plan that splits an approach's movements over phases gets the whole approach in each: approach-level
-- queues can't tell which movement waits). Then as R.plan (critical approach per phase, Webster's cycle with
-- satFlow, the v3 balanced cap, maxCycleStep, damping, floors, hysteresis). Keep reasons: no_vehicle_phase,
-- few_snapshots (fewer than minSnaps), quiet (mean standing cars on all approaches below quietQueue),
-- no_mapped_traffic. res.arrive: the flows per approach (cars per lane per hour).
function R.planQueue(input, opts)
	local o = options(opts)
	local conns, states = input.conns or {}, input.states or {}
	local nConns, nCross = #conns, input.nCross or 0
	local kinds = R.kinds(nConns, nCross, states)
	local served, lanes = R.served(conns, states, kinds)
	local cur, oldCycle = {}, 0
	for p, st in ipairs(states) do
		cur[p] = type(st.duration) == "number" and st.duration or 0
		oldCycle = oldCycle + cur[p]
	end
	local veh = {}
	for p = 1, #states do
		if kinds[p] == "veh" then veh[#veh + 1] = p end
	end
	local arrive, queue = input.arrive or {}, input.queue or {}
	local res = { kinds = kinds, oldCycle = oldCycle, unmapped = 0, always = 0, total = 0, queued = 0, demand = {},
		snaps = input.snaps or 0, arrive = {} }
	for _, a in ipairs(sortedKeys(queue)) do res.queued = res.queued + (queue[a] or 0) end
	if #veh == 0 then
		res.keep, res.reason = true, "no_vehicle_phase"
		return res
	end
	if (input.snaps or 0) < o.minSnaps then
		res.keep, res.reason = true, "few_snapshots"
		return res
	end
	if res.queued < o.quietQueue then
		res.keep, res.reason = true, "quiet"
		return res
	end
	local phases = R.approachPhases(served, veh)
	local s = o.satFlow / 3600
	local load, servedPasses, apQueue = {}, {}, {}
	for _, p in ipairs(veh) do load[p], servedPasses[p] = {}, {} end
	local mapped = false
	for _, a in ipairs(sortedKeys(arrive)) do
		local list = phases[a]
		local v = arrive[a]
		if type(v) == "number" and v > 0 then
			if list == nil or #list == 0 then
				res.unmapped = res.unmapped + (queue[a] or 0)
			else
				local ln = math.max(1, lanes[a] or 1)
				local perLane = v / ln
				local flow = perLane * s / (s + perLane) * 3600
				res.arrive[a] = flow
				res.demand[a] = flow
				apQueue[a] = queue[a] or 0
				for _, p in ipairs(list) do load[p][a] = flow * ln end
				mapped = true
			end
		end
	end
	if not mapped then
		res.keep, res.reason = true, "no_mapped_traffic"
		return res
	end
	-- window 3600 s: a load is cars per hour, so R.cycleFor's flow is the load itself
	return finishPlan(res, { states = states, kinds = kinds, cur = cur, oldCycle = oldCycle, veh = veh, nConns = nConns,
		nCross = nCross, load = load, lanes = lanes, servedPasses = servedPasses, apQueue = apQueue, window = 3600,
		pedNeed = input.pedNeed, prev = input.prev, samples = input.snaps }, o)
end

--- Whether the offset (dx, dy) from a junction lies on an arm's queue corridor (step B v4; the Stress Test's arm
-- corridors, plans/square_stress_test/FLOW.md "Measured area"): arm = { ux, uy (unit vector outwards along the road),
-- len (m out from the centre), half (m to each side of the axis), box (m: closer is the junction itself), side (+1:
-- right-hand traffic, the inbound lanes left of the outward heading; -1 left-hand; 0 both sides count) }. On the axis
-- counts as inbound.
function R.onCorridor(arm, dx, dy)
	local along = dx * arm.ux + dy * arm.uy
	if along < (arm.box or 0) or along > arm.len then return false end
	local side = dx * arm.uy - dy * arm.ux
	if side > arm.half or side < -arm.half then return false end
	if arm.side == 1 then return side <= 0 end
	if arm.side == -1 then return side >= 0 end
	return true
end

--- A grid over junctions for the snapshot (step B v4): list = { { key, x, y, arms = { arm, ... } } }, cell (m, at least
-- the longest corridor). Returns { cell, buckets }.
function R.queueIndex(list, cell)
	local idx = { cell = cell, buckets = {} }
	for _, j in ipairs(list or {}) do
		-- (+ 0: a -0 cell index would make another key than 0)
		local k = (math.floor(j.x / cell) + 0) .. ":" .. (math.floor(j.y / cell) + 0)
		local b = idx.buckets[k]
		if b == nil then
			b = {}
			idx.buckets[k] = b
		end
		b[#b + 1] = j
	end
	return idx
end

--- The corridors (x, y) lies on: fills out[1..n] with { j, arm } pairs (a junction once: its first arm that holds the
-- point; every junction whose corridor holds it) and returns n. The 3 x 3 cells around the point.
function R.queueHits(idx, x, y, out)
	local n = 0
	if idx == nil or type(x) ~= "number" or type(y) ~= "number" then return 0 end
	local cell = idx.cell
	local cx, cy = math.floor(x / cell) + 0, math.floor(y / cell) + 0
	for ix = cx - 1, cx + 1 do
		for iy = cy - 1, cy + 1 do
			local b = idx.buckets[(ix + 0) .. ":" .. (iy + 0)]
			if b ~= nil then
				for _, j in ipairs(b) do
					local dx, dy = x - j.x, y - j.y
					for _, arm in ipairs(j.arms) do
						if R.onCorridor(arm, dx, dy) then
							n = n + 1
							out[n] = out[n] or {}
							out[n].j, out[n].arm = j, arm
							break
						end
					end
				end
			end
		end
	end
	return n
end

--- Cars per minute through each road of a junction (the status showed it until step B v4's last-measured line; kept
-- for the tests and a later status): approaches are
-- joined into one road when some veh phase serves movements of both (a movement served in every veh phase, a curb
-- turn freed all cycle, joins nothing); roads in the order of their first veh phase; each road's rate = the passes
-- of its approaches' movements per minute of the window. kinds: R.kinds' list (nil: computed).
function R.roadRates(conns, states, kinds, passes, windowS)
	conns, states, passes = conns or {}, states or {}, passes or {}
	kinds = kinds or R.kinds(#conns, 0, states)
	local served = R.served(conns, states, kinds)
	local nVeh = 0
	for _, k in ipairs(kinds) do
		if k == "veh" then nVeh = nVeh + 1 end
	end
	-- union-find over approaches
	local parent = {}
	local function find(a)
		local r, steps = a, 0
		while parent[r] ~= nil and parent[r] ~= r and steps < 1000 do
			r = parent[r]
			steps = steps + 1
		end
		return r
	end
	local first = {}
	local byPhase = {}
	for _, key in ipairs(sortedKeys(served)) do
		local a = R.approachOf(key)
		if a ~= nil then
			if parent[a] == nil then parent[a] = a end
			local list = {}
			for p in pairs(served[key]) do list[#list + 1] = p end
			table.sort(list)
			if #list > 0 and not (#list == nVeh and nVeh > 1) then
				for _, p in ipairs(list) do
					if byPhase[p] == nil then byPhase[p] = a
					else
						local ra, rb = find(a), find(byPhase[p])
						if ra ~= rb then parent[ra] = rb end
					end
					if first[a] == nil or p < first[a] then first[a] = p end
				end
			end
		end
	end
	local sum, order = {}, {}
	for _, key in ipairs(sortedKeys(passes)) do
		local a = R.approachOf(key)
		if a ~= nil and parent[a] ~= nil then
			local r = find(a)
			sum[r] = (sum[r] or 0) + (passes[key] or 0)
		end
	end
	local rootFirst = {}
	for a in pairs(parent) do
		local r = find(a)
		local f = first[a] or math.huge
		if rootFirst[r] == nil or f < rootFirst[r] then rootFirst[r] = f end
	end
	for r in pairs(rootFirst) do order[#order + 1] = r end
	table.sort(order, function(x, y)
		if rootFirst[x] ~= rootFirst[y] then return rootFirst[x] < rootFirst[y] end
		return tostring(x) < tostring(y)
	end)
	local minutes = ((type(windowS) == "number" and windowS > 0) and windowS or 180) / 60
	local out = {}
	for _, r in ipairs(order) do
		if rootFirst[r] ~= math.huge then out[#out + 1] = (sum[r] or 0) / minutes end
	end
	return out
end

--- "k:v,k:v" of a map in key order (numbers with at most one decimal), at most max entries (then ",+n").
function R.mapText(map, max)
	local parts, keys = {}, sortedKeys(map or {})
	max = max or 24
	for i, k in ipairs(keys) do
		if i > max then
			parts[#parts + 1] = "+" .. (#keys - max)
			break
		end
		local v = map[k]
		if type(v) == "number" then v = (v == math.floor(v)) and string.format("%d", v) or string.format("%.1f", v) end
		parts[#parts + 1] = tostring(k) .. ":" .. tostring(v)
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- "a/b/c" of a list of numbers (one decimal where needed).
function R.listText(list)
	local parts = {}
	for i, v in ipairs(list or {}) do
		if type(v) == "number" then
			parts[i] = (v == math.floor(v)) and string.format("%d", v) or string.format("%.1f", v)
		else
			parts[i] = tostring(v)
		end
	end
	return #parts > 0 and table.concat(parts, "/") or "-"
end

--- Re-route classes of a driver re-read after a snapshot: was { node ahead with exit outSeg }; now
-- state/outSeg from R.pathAt with behind = true; gone = the driver no longer drives (arrived, despawned).
-- Returns "same" (still through the node by the same exit, ahead or passed), "exit_changed" (through the node
-- by another exit), "dropped" (the node no longer on its path near where it is) or "gone".
function R.rerouteClass(wasOut, state, outSeg, gone)
	if gone then return "gone" end
	if state == nil then return "dropped" end
	if outSeg ~= wasOut then return "exit_changed" end
	return "same"
end

--- Whether the read phases of a node (W.lightRead result r) are the game's own default (PLAN.md "Reset after
-- Lights only / Re-time"; the tool's C.phasesDefault, the runtime's new-light Smart lights): true, or false and why
-- ("user_modified" | "shape" | "whole_s" | "no_phases"). The heuristic, from the measured defaults (docs/findings/roads.md "Default traffic light phases, measured in game"): not flagged
-- userModifiedTrafficLightStates, 6 phases veh / all-red 6 s / veh / all-red 6 s / pedestrians 3 s (all-red
-- without crosswalks) / all-red 9 s, every phase canSkip with minDuration 1.5, and both greens NOT whole seconds
-- (the engine's are 18.86 / 21.55 / 23.70 / 27.09 s; the Crossing window's slider, Lights only and Re-time write
-- whole seconds). Failure cases: a default green that happens to be a whole second (none seen) reads as changed
-- (Reset then offers "light phases": harmless, it writes states = {} again); a script that writes the default
-- shape with fractional greens reads as default.
local DEFAULT_FIXED = { [2] = 6, [4] = 6, [5] = 3, [6] = 9 }
function R.phasesDefault(r)
	if r == nil or r.tlc == nil then return false, "no_phases" end
	local um = nil
	pcall(function() um = r.cfg.userModifiedTrafficLightStates end)
	if um == true then return false, "user_modified" end
	local states = {}
	for i, st in ipairs(r.tlc.states) do
		if i > 8 then return false, "shape" end
		local l = {}
		for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
		states[i] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip == true }
	end
	if #states ~= 6 then return false, "shape" end
	local kinds = R.kinds(#(r.conns or {}), #(r.cws or {}), states)
	for i, st in ipairs(states) do
		if type(st.duration) ~= "number" or not st.canSkip or math.abs((st.minDuration or 0) - 1.5) > 0.01 then
			return false, "shape"
		end
		local want = DEFAULT_FIXED[i]
		if want ~= nil then
			if math.abs(st.duration - want) > 0.05 then return false, "shape" end
			if kinds[i] == "veh" then return false, "shape" end
			if i ~= 5 and kinds[i] ~= "all_red" then return false, "shape" end
		else
			if kinds[i] ~= "veh" then return false, "shape" end
			if math.abs(st.duration - math.floor(st.duration + 0.5)) < 0.01 then return false, "whole_s" end
		end
	end
	return true
end

--- Looser than R.phasesDefault, for the new-light Smart lights look (sl_autoretime planLook; PLAN.md "New lights get
-- Smart lights"): phases the engine made, of any shape. Seen in game 2026-10-16 (session live, 1-lane T-junctions
-- switched on in the Crossing Tool): every queued light skipped, as R.phasesDefault wants the measured 6-phase shape
-- and no user-modified flag, while a 1-lane T's default has 7 phases (node 35512) and the light switch itself may
-- set the flag. Here: 2..8 phases, every one canSkip with minDuration 1.5, every duration fractional or one of the
-- engine's fixed pauses (3 / 6 / 9 s), at least one fractional. The Crossing window's slider, Smart lights and
-- Re-time write whole seconds, so their phases (a hand-timed light) fail. Returns true, or false and why
-- ("no_phases" | "shape" | "whole_s").
local ENGINE_FIXED = { 3, 6, 9 }
function R.phasesEngineMade(r)
	if r == nil or r.tlc == nil then return false, "no_phases" end
	local n, frac = 0, 0
	for i, st in ipairs(r.tlc.states) do
		if i > 8 then return false, "shape" end
		n = i
		local d = st.duration
		if type(d) ~= "number" or d ~= d or st.canSkip ~= true or math.abs((st.minDuration or 0) - 1.5) > 0.01 then
			return false, "shape"
		end
		if math.abs(d - math.floor(d + 0.5)) >= 0.01 then
			frac = frac + 1
		else
			local fixed = false
			for _, f in ipairs(ENGINE_FIXED) do if math.abs(d - f) < 0.01 then fixed = true end end
			if not fixed then return false, "whole_s" end
		end
	end
	if n < 2 then return false, "shape" end
	if frac == 0 then return false, "whole_s" end
	return true
end

return R
