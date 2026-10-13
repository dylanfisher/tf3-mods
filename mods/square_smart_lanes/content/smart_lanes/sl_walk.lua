-- Smart Lanes: bounded road walks (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_walk.lua. plans/square_smart_lanes/PHASE7.md "Step 1".
--
-- Follows one road from a node along a segment through plain nodes (exactly two road segments) and
-- records the road lanes of one travel direction on every segment it passes, so the lane rules can
-- look ahead (where the road ends, gains or drops lanes, the next junction). Only road segments count
-- (a lane with CAR, BUS or TRUCK, as sl_ring); tram-only tracks are ignored.
--
-- Walk.follow(world, node, seg, opt) -> walk:
--   opt.dir "out": traffic leaving `node` along seg (downstream), "in": traffic arriving at `node`
--     on seg (upstream; the walk still moves away from node, against that traffic).
--   opt.maxDist (m), opt.maxNodes: caps (default MAX_DIST, MAX_NODES; never above the hard caps).
-- walk = { steps = { { seg, from, to, at (m from the start node to `from`), len, lanes } ... },
--   stop = reason, node = node the walk stopped at (nil when it stopped before a segment), dist (m),
--   roads = road segments at that node }
-- stop: "junction" (3+ road segments), "dead_end" (1), "no_lanes" (the next segment has no lane in the
-- followed direction: a one-way road against it), "loop" (back at a node already passed), "no_node" /
-- "no_seg" (missing from the world, e.g. bulldozed: the walk never indexes nil), "max_dist", "max_nodes".
-- Every walk ends after at most maxNodes segments, so a pathological network cannot hang a frame.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local Walk = {}

Walk.MAX_DIST = 400  -- m
Walk.MAX_NODES = 12  -- segments (plain nodes passed + 1)
Walk.HARD_DIST = 3000
Walk.HARD_NODES = 64

local function roadSegsOf(world, n)
	local node = world.node(n)
	if not node then return nil, "no_node" end
	local out = {}
	for _, sid in ipairs(node.segs or {}) do
		local s = world.seg(sid)
		if not s then return nil, "no_seg" end
		local la = Ring.lanesAt(s, n)
		if la and (#la.incoming + #la.outgoing) > 0 then out[#out + 1] = { sid = sid, la = la } end
	end
	return out
end

--- Road segments at node n: list of { sid, la } (la = Ring.lanesAt), or nil, reason when the node or
-- one of its segments is missing (the topology is unknown there).
-- A game world (sl_write W.makeWorld: world.memo) keeps the result per node, so the walks of one job
-- or one pick that pass a node again (bypass walks, look-aheads) build it once; callers only read it.
function Walk.roadSegs(world, n)
	local memo = world.memo
	if memo == nil then return roadSegsOf(world, n) end
	local m = memo.roadSegs
	if m == nil then
		m = {}
		memo.roadSegs = m
	end
	local hit = m[n]
	if hit == nil then
		local list, why = roadSegsOf(world, n)
		hit = { list = list, why = why }
		if type(n) == "number" then m[n] = hit end
	end
	return hit.list, hit.why
end

local function laneCount(la, dir)
	if dir == "out" then return #la.outgoing end
	return #la.incoming
end

--- Walks from `node` along `seg` (see the header). Never fails: a missing node / segment ends the walk.
function Walk.follow(world, node, seg, opt)
	opt = opt or {}
	local dir = opt.dir == "in" and "in" or "out"
	local maxDist = math.min(opt.maxDist or Walk.MAX_DIST, Walk.HARD_DIST)
	local maxNodes = math.min(opt.maxNodes or Walk.MAX_NODES, Walk.HARD_NODES)
	local w = { steps = {}, dist = 0 }
	local seen = { [node] = true }
	local at, sid = node, seg
	while true do
		local s = sid and world.seg(sid)
		if not s then
			w.stop = "no_seg"
			return w
		end
		local la = Ring.lanesAt(s, at)
		if not la then
			w.stop = "no_seg"
			return w
		end
		local lanes = laneCount(la, dir)
		if lanes == 0 then
			w.stop, w.node = "no_lanes", at
			return w
		end
		local to = (la.e == 0) and s.node1 or s.node0
		local len = Ring.segLength(s)
		w.steps[#w.steps + 1] = { seg = sid, from = at, to = to, at = w.dist, len = len, lanes = lanes }
		w.dist = w.dist + len
		w.node, w.roads = to, nil
		if seen[to] then
			w.stop = "loop"
			return w
		end
		seen[to] = true
		local roads, why = Walk.roadSegs(world, to)
		if not roads then
			w.stop = why
			return w
		end
		w.roads = #roads
		if #roads >= 3 then
			w.stop = "junction"
			return w
		end
		if #roads <= 1 then
			w.stop = "dead_end"
			return w
		end
		if w.dist >= maxDist then
			w.stop = "max_dist"
			return w
		end
		if #w.steps >= maxNodes then
			w.stop = "max_nodes"
			return w
		end
		local nxt = nil
		for _, r in ipairs(roads) do
			if r.sid ~= sid then nxt = r.sid end
		end
		if nxt == nil then
			-- both ends of one segment at this node (a self-loop)
			w.stop = "loop"
			return w
		end
		at, sid = to, nxt
	end
end

--- Fewest lanes on the walk's segments (0 for an empty walk).
function Walk.minLanes(w)
	local m = nil
	for _, st in ipairs(w.steps) do
		if m == nil or st.lanes < m then m = st.lanes end
	end
	return m or 0
end

--- Distance (m from the start node) of the first node where the lane count falls below `lanes`, or
-- nil. Only plain nodes count (a junction ends the walk).
function Walk.firstBelow(w, lanes)
	for _, st in ipairs(w.steps) do
		if st.lanes < lanes then return st.at end
	end
	return nil
end

--- Distance to the junction the walk stopped at, or nil (it stopped for another reason).
function Walk.junctionDist(w)
	if w.stop == "junction" then return w.dist end
	return nil
end

--- The last segment walked (arriving at w.node), or nil.
function Walk.lastSeg(w)
	local st = w.steps[#w.steps]
	return st and st.seg
end

return Walk
