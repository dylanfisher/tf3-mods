-- Smart Lanes: slip-lane junctions (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_slip.lua. plans/square_smart_lanes/PLAN.md "Phase 4".
--
-- A slip node is where a one-way slip lane, splitter leg or ramp (the "branch") leaves or joins a
-- road: the diverge and merge nodes of square_roundabouts' Channelized Junction and Roundabout
-- Interchange, or hand-built ones. The engine's default there fans every incoming lane out over
-- several outgoing lanes, crossing each other; this rule matches lanes one to one without crossings.
--
-- Node classification (S.classify). Only road segments count (a lane with CAR, BUS or TRUCK, as
-- sl_ring); tram-only tracks are ignored and their connections kept. Directions are the segments'
-- tangents at the node (BaseEdge.tangent0/1, both node0 -> node1); a turn angle is signed,
-- positive = a left turn (counterclockwise, the convention sl_ring's ring direction uses, verified
-- in game on rings).
--   * "A" all one-way, 3 segments: 1 in + 2 out = diverge, 2 in + 1 out = merge. The through road
--     is the one with the smaller turn angle (at most STRAIGHT_MAX_DEG), the branch the other
--     (MIN_SPLIT_DEG apart, else ambiguous).
--   * "B" two two-way segments (the main road, at most STRAIGHT_MAX_DEG off straight) plus one or
--     two one-way branches (3 or 4 segments; the 4-segment case is the Channelized Junction's side
--     road node, where one slip lane joins and another leaves). Each branch belongs to the travel
--     direction it turns least from (at most MAX_TURN_DEG), one branch per direction; the other
--     direction of the main road is a straight stream. When the tangents at the node do not tell
--     (a branch turning MAX_TURN_DEG or more, two branches nearest one direction, a branch on the
--     far side), shallow ramps decide (sl_cross X.shallowRamps, split=shallow): every branch a ramp
--     whose first 50 m run at most 60 deg off the road, heading along the travel direction on whose
--     kerb side it lies, one per direction (in game 2026-10-11: ramps peeling off a 3+3 road had
--     their tangents 80-100 deg off it at the node). Otherwise the crossing rule (sl_cross), which
--     keeps through traffic from turning across the oncoming carriageway into a shallow ramp. A ramp
--     the tangents do assign whose first 50 m run more than 60 deg off the road is a ramp end meeting
--     it at about a right angle (a diamond / parclo terminal): the crossing rule too (slipReason
--     "terminal"), which keeps its turns both ways. Three two-way roads and a one-way road: the
--     crossing rule too.
--   * "X" 3 or 4 two-way roads and no one-way road: a crossroads or T-junction, handed over to
--     sl_cross.lua (its own lane rule; the views and plans have the same shape, so the callers
--     treat them as slip nodes).
--   * "D" a plain node (exactly two road segments) where a travel direction's lane count changes: a
--     lane drop or gain (classifyDrop, PHASE7.md step 2); the "straight" rule per direction.
--   * anything else is not a slip node ("none": fewer than 3 road segments, or
--     one two-way road with one-way roads such as a roundabout splitter's split node;
--     "skip" with a reason for candidates that do not fit: 5+ roads, bus lanes,
--     ambiguous geometry, a branch on the far side of a two-way road).
--
-- Kerb side (lane 1 = kerb side, as on rings):
--   * two-way main road (case B): the driving side from its lane layout. Looking from the node
--     along a two-way segment, connection indices run left to right (findings.md), so right-hand
--     traffic has the incoming lanes on the left (lower indices) and the outgoing ones on the right;
--     left-hand traffic the opposite. The base game decides the same way from lane positions
--     (base/content/infrastructure/traffic_light/trafficlightutil.lua leftHandTraffic). A branch on
--     the far side (crossing oncoming traffic) is not a slip lane: skip "far_side_branch".
--   * all one-way (case A): no lane layout tells the driving side, so the kerb side is the side the
--     branch leaves or joins (a right-hand off-ramp in right-hand traffic, and equally a left exit:
--     the lanes nearest the branch are the ones that can reach it without crossing).
--
-- The rule (S.roadConns), per travel direction; lanes counted kerb first (m = main in, t = through
-- out, b = branch out, p = through in, q = branch in, o = out; N, T, B, O lane counts):
--   * straight: 1:1 aligned from the far (median) side; extra outgoing lanes on the kerb side are
--     fed by the kerb lane, extra incoming kerb lanes fold into the kerb lane.
--   * diverge: f = max(1, N - T + 1) is the kerb-most lane that still has its own through lane
--     (aligned from the far side); k = min(B, N, f) kerb lanes feed the branch 1:1 (m_i -> b_i),
--     extra branch lanes fan from m_k. If N <= T the kerb lane m_1 feeds the branch AND continues
--     straight (shared), so through traffic keeps every lane; if N > T the kerb lanes m_1..m_(f-1)
--     are dedicated to the branch and m_f (when it feeds the branch too) is a shared "option" lane.
--     Lanes between the branch feeders and m_f (only when B < N - T) fold into t_1. With N <= T
--     only the kerb lane reaches the branch even when B >= 2: two branch feeders plus every lane
--     going straight would cross (m_1 -> t_1 over m_2 -> b_2).
--   * exit-only diverge (PHASE7.md step 3), when N <= T, N >= 3 and the look-ahead (S.divergeLook)
--     says so: E = min(B, N - 2) kerb lanes (S.exitLanes) feed only the branch (m_i -> b_i, extra
--     branch lanes fan from m_E), so through traffic keeps N - E >= 2 lanes, as at crossroads ("3+
--     lanes: the kerb lane turns only"); m_(E+1)..m_N go straight aligned from the far side and the
--     kerb-side through lanes they leave unfed are fed by m_(E+1) (no crossing).
--   * merge, when T + B > O and the through road keeps two or more lanes (O - B >= 2), and the
--     look-ahead (S.mergeLook, below) says so: the branch keeps its own kerb lanes q_i -> o_i, the
--     through lanes go into o_(B+1)..o_O aligned from the far side and the extra kerb-side ones fold
--     into o_(B+1): joining traffic never queues to merge. Otherwise the give-way merge below.
--   * other merges: through lanes 1:1 into o aligned from the far side (extra kerb-side through lanes fold
--     into o_1); branch lanes q_i -> o_min(i, c) with c = max(1, O - T + 1): with T + B <= O
--     nobody shares; otherwise the branch shares the kerb-side lanes with the through lanes (a
--     give-way merge) and never crosses them; B > c folds the extra branch lanes into o_c. Outgoing
--     lanes between the branch's and the through lanes' are fed by the nearer one.
--   * no U-turns, every incoming road lane gets a connection, every outgoing road lane is fed, no
--     two connections of one travel direction cross. Tram connections are kept as the engine made
--     them (Rules.mergeTram).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Walk = ug_require "square_smart_lanes::/smart_lanes/sl_walk.lua"

local S = {}

S.STRAIGHT_MAX_DEG = 45 -- through road / main road: at most this far off straight
S.MAX_TURN_DEG = 90     -- a branch belongs to a direction it turns less than this from (slip lanes
                        -- leave at 40-80 deg in the Channelized Junction; the other direction sees
                        -- the same branch at 100-140 deg)
S.MIN_SPLIT_DEG = 5     -- through and branch must differ this much (turn angle and its size)
-- A ramp leaves a highway tangentially, so at the gore node its direction is the highway's (in game
-- 2026-10-11: every parclo / diamond / roundabout-interchange gore was skipped "ambiguous"). Then the
-- segments' far ends decide (the ramp has curved away by its next node, the highway has not), at a
-- smaller split; then, for one-way roads, the lane count (the through road keeps the main road's).
S.MIN_FAR_SPLIT_DEG = 1
S.MAX_ROADS = 4
-- Merge look-ahead (S.mergeLook): walks of at most Walk.MAX_DIST / Walk.MAX_NODES each way.
S.LOOK_ROOM_M = 80  -- the through road's previous junction closer than this: no room to merge lanes
S.LOOK_DROP_M = 150 -- the out road loses a lane within this: keep the give-way merge
S.EXIT_MAX_DEG = 150 -- a road leaving the next junction at most this far off is an exit / turn
-- Exit-only kerb lanes before a diverge (S.exitLanes, S.divergeLook; the room check reuses LOOK_ROOM_M)
S.EXIT_KEEP_THROUGH = 2 -- through traffic keeps at least this many lanes beside the exit-only lanes

local atan2 = math.atan2 or math.atan

local function unit(x, y)
	local l = math.sqrt(x * x + y * y)
	if l < 1e-9 then return nil end
	return x / l, y / l
end

--- Unit direction pointing away from `node` along segment s (tangent at that end, else the chord).
function S.awayDir(s, node)
	local e = Ring.endAt(s, node)
	local t, sign
	if e == 0 then t, sign = s.t0, 1 else t, sign = s.t1, -1 end
	local x, y
	if t then x, y = unit(t.x * sign, t.y * sign) end
	if x == nil then x, y = unit((s.p1.x - s.p0.x) * sign, (s.p1.y - s.p0.y) * sign) end
	return x or 0, y or 0
end

--- Unit direction from `node` to the far end of segment s (the chord).
function S.farDir(s, node)
	local e = Ring.endAt(s, node)
	local x, y
	if e == 0 then x, y = unit(s.p1.x - s.p0.x, s.p1.y - s.p0.y) else x, y = unit(s.p0.x - s.p1.x, s.p0.y - s.p1.y) end
	return x or 0, y or 0
end

--- Signed turn (degrees, left positive) between segments a (arriving) and b (leaving) by their far ends.
local function farTurnDeg(world, node, a, b)
	local ax, ay = S.farDir(world.seg(a), node)
	local hx, hy = -ax, -ay
	local ox, oy = S.farDir(world.seg(b), node)
	return math.deg(atan2(hx * oy - hy * ox, hx * ox + hy * oy))
end
S.farTurnDeg = farTurnDeg

--- Signed turn (degrees, left positive) for traffic arriving on segment a and leaving on b.
local function turnDeg(world, node, a, b)
	local ax, ay = S.awayDir(world.seg(a), node)
	local hx, hy = -ax, -ay
	local ox, oy = S.awayDir(world.seg(b), node)
	return math.deg(atan2(hx * oy - hy * ox, hx * ox + hy * oy))
end
S.turnDeg = turnDeg

local function reversed(list)
	local out = {}
	for i = #list, 1, -1 do out[#out + 1] = list[i] end
	return out
end

--- Lane indices (ascending connection index) ordered kerb first. kerb: "right" or "left".
-- Incoming ascending = driver's right -> left; outgoing ascending = driver's left -> right.
function S.kerbFirst(asc, incoming, kerb)
	return Ring.outerFirst(asc, incoming, kerb == "right" and 1 or -1)
end

--- Driving side from a two-way segment's lanes at the node: "right", "left" or nil.
function S.sideOf(la)
	if #la.incoming == 0 or #la.outgoing == 0 then return nil end
	local inMax, inMin = la.incoming[#la.incoming], la.incoming[1]
	local outMax, outMin = la.outgoing[#la.outgoing], la.outgoing[1]
	if inMax < outMin then return "right" end
	if inMin > outMax then return "left" end
	return nil
end

local function skip(v, reason)
	v.kind, v.reason = "skip", reason
	return v
end

local function lanesOf(world, sid, node, incoming, kerb)
	local la = Ring.lanesAt(world.seg(sid), node)
	return S.kerbFirst(incoming and la.incoming or la.outgoing, incoming, kerb)
end

--- Builds a stream (one travel direction) from segment ids, with kerb-first lane lists.
-- shape "straight": inSeg, outSeg; "diverge": inSeg, throughSeg, branchSeg; "merge": throughSeg,
-- branchSeg (both incoming), outSeg.
local function makeStream(world, node, st)
	local k = st.kerb
	if st.shape == "straight" then
		st.m = lanesOf(world, st.inSeg, node, true, k)
		st.o = lanesOf(world, st.outSeg, node, false, k)
	elseif st.shape == "diverge" then
		st.m = lanesOf(world, st.inSeg, node, true, k)
		st.t = lanesOf(world, st.throughSeg, node, false, k)
		st.b = lanesOf(world, st.branchSeg, node, false, k)
	else
		st.p = lanesOf(world, st.throughSeg, node, true, k)
		st.q = lanesOf(world, st.branchSeg, node, true, k)
		st.o = lanesOf(world, st.outSeg, node, false, k)
	end
	return st
end

local function splitBy(c1, c2, key, minDeg)
	local t, b = c1, c2
	if math.abs(c2[key]) < math.abs(c1[key]) then t, b = c2, c1 end
	if math.abs(b[key]) - math.abs(t[key]) < minDeg or math.abs(b[key] - t[key]) < minDeg then return nil end
	return t, b
end

--- Through / branch of two candidates {seg, deg, far, lanes}: the smaller turn is the through road,
-- by the directions at the node, else by the far ends, else (mainLanes given) the one with the main
-- road's lane count. Returns through, branch, branch side relative to the through road
-- ("left"/"right") or nil, why; fifth: how it was decided ("node", "far", "lanes").
local function splitPair(c1, c2, mainLanes)
	if math.min(math.abs(c1.deg), math.abs(c2.deg)) > S.STRAIGHT_MAX_DEG then return nil, nil, nil, "no_through" end
	local t, b = splitBy(c1, c2, "deg", S.MIN_SPLIT_DEG)
	local how = "node"
	if t == nil and c1.far ~= nil and c2.far ~= nil then
		t, b = splitBy(c1, c2, "far", S.MIN_FAR_SPLIT_DEG)
		how = "far"
		if t == nil and mainLanes ~= nil and c1.lanes ~= c2.lanes and (c1.lanes == mainLanes or c2.lanes == mainLanes)
			and math.abs(c1.far - c2.far) >= S.MIN_FAR_SPLIT_DEG then
			if c1.lanes == mainLanes then t, b = c1, c2 else t, b = c2, c1 end
			how = "lanes"
		end
	end
	if t == nil then return nil, nil, nil, "ambiguous" end
	if math.abs(t.deg) > S.STRAIGHT_MAX_DEG then return nil, nil, nil, "no_through" end
	local key = how == "node" and "deg" or "far"
	return t, b, (b[key] > t[key]) and "left" or "right", nil, how
end

---------------------------------------------------------------------------
-- Merge look-ahead (PHASE7.md step 1): whether a ramp keeps its own lane at a tight merge

--- Whether a road leaves junction J on the kerb side of the straightest way on, for traffic arriving
-- on segment inSeg (an off-ramp, a slip lane or a turn into a side road: the out road's kerb lane
-- leaves there, so traffic joining from the kerb side wants that lane).
function S.exitAhead(world, J, inSeg, kerb)
	local roads = Walk.roadSegs(world, J)
	if not roads or not world.seg(inSeg) then return false end
	local cands = {}
	for _, r in ipairs(roads) do
		if r.sid ~= inSeg and #r.la.outgoing > 0 then
			local deg = turnDeg(world, J, inSeg, r.sid)
			if math.abs(deg) <= S.EXIT_MAX_DEG then
				cands[#cands + 1] = { deg = deg, far = farTurnDeg(world, J, inSeg, r.sid) }
			end
		end
	end
	if #cands < 2 then return false end
	local function kerbSide(d) return (kerb == "right" and d < 0) or (kerb == "left" and d > 0) end
	local st = cands[1]
	for i = 2, #cands do
		local c = cands[i]
		local dd = math.abs(c.deg) - math.abs(st.deg)
		if dd < -S.MIN_SPLIT_DEG or (math.abs(dd) < S.MIN_SPLIT_DEG and math.abs(c.far) < math.abs(st.far)) then st = c end
	end
	-- the road ends at J (no way on within STRAIGHT_MAX_DEG, e.g. a T): any turn to the kerb side
	if math.abs(st.deg) > S.STRAIGHT_MAX_DEG then
		for _, c in ipairs(cands) do
			if kerbSide(c.deg) then return true end
		end
		return false
	end
	for _, c in ipairs(cands) do
		if c ~= st then
			local d = c.deg - st.deg
			-- as straight as st (a symmetric fork): which one is "st" depends on the segment order,
			-- so the fork counts whichever side c is on (the kerb branch takes the kerb lane)
			local fork = math.abs(math.abs(c.deg) - math.abs(st.deg)) < S.MIN_SPLIT_DEG
				and math.abs(math.abs(c.far) - math.abs(st.far)) < S.MIN_FAR_SPLIT_DEG
			if math.abs(d) < S.MIN_SPLIT_DEG then
				d = c.far - st.far
				if math.abs(d) < S.MIN_FAR_SPLIT_DEG then d = 0 end
			end
			if kerbSide(d) or (fork and d ~= 0) then return true end
		end
	end
	return false
end

--- Look-ahead for a merge stream with T + B > O and O - B >= 2 (the counts allow the "ramp keeps its
-- own lane" merge). Walks the through road back (Walk "in") and the out road on (Walk "out"), each at
-- most Walk.MAX_DIST / Walk.MAX_NODES, and decides, first rule that applies:
--   1. the out road loses a lane within LOOK_DROP_M (assumed from the kerb side, as the game and the
--      lane-drop rule end lanes): give way ("drop_ahead");
--   2. the through road had at most O - B lanes somewhere on the walk (its extra kerb lanes were added
--      nearby and end here): own lane ("lane_added");
--   3. the through road's previous junction is closer than LOOK_ROOM_M (no room for its lanes to merge
--      among themselves): give way ("junction_close");
--   4. the through road carried all T lanes for the whole walk (a real T-lane road): give way
--      ("through_road"), unless the out road's next junction (within Walk.MAX_DIST) has a road leaving
--      on the kerb side (S.exitAhead: ramp traffic wants the kerb lane): own lane ("exit_ahead");
--   5. otherwise (some but not all of its extra lanes added on the walk): own lane ("lane_added").
-- Returns { merge = "own_lane" | "give_way", why, up = walk, down = walk }.
function S.mergeLook(world, n, st)
	local T, B, O = #st.p, #st.q, #st.o
	local up = Walk.follow(world, n, st.throughSeg, { dir = "in" })
	local down = Walk.follow(world, n, st.outSeg, { dir = "out" })
	local function res(m, why) return { merge = m, why = why, up = up, down = down } end
	local dropAt = Walk.firstBelow(down, O)
	if dropAt ~= nil and dropAt <= S.LOOK_DROP_M then return res("give_way", "drop_ahead") end
	local minUp = Walk.minLanes(up)
	if minUp <= O - B then return res("own_lane", "lane_added") end
	local jd = Walk.junctionDist(up)
	if jd ~= nil and jd < S.LOOK_ROOM_M then return res("give_way", "junction_close") end
	if minUp >= T then
		local jx = Walk.junctionDist(down)
		if jx ~= nil and jx <= Walk.MAX_DIST and S.exitAhead(world, down.node, Walk.lastSeg(down), st.kerb) then
			return res("own_lane", "exit_ahead")
		end
		return res("give_way", "through_road")
	end
	return res("own_lane", "lane_added")
end

---------------------------------------------------------------------------
-- Exit-only kerb lanes before a diverge (PHASE7.md step 3): the diverge counterpart of the merge rule

--- Number of kerb lanes that may become exit-only at a diverge of N main lanes into T through and B
-- branch lanes (pure counts): min(B, N - EXIT_KEEP_THROUGH) when N <= T (with N > T the kerb lanes
-- are dedicated to the branch by the counts already) and through traffic keeps EXIT_KEEP_THROUGH or
-- more lanes beside them (so N >= 3); else 0 (the kerb lane stays shared).
function S.exitLanes(N, T, B)
	if N == nil or T == nil or B == nil or B < 1 or N > T then return 0 end
	local E = math.min(B, N - S.EXIT_KEEP_THROUGH)
	if E < 1 then return 0 end
	return E
end

--- Look-ahead for a diverge stream whose counts allow exit-only kerb lanes (S.exitLanes > 0). Walks
-- the main road back (Walk "in", at most Walk.MAX_DIST / Walk.MAX_NODES) and decides, first rule that
-- applies:
--   1. the main road had at most N - E lanes somewhere on the walk (the exit lanes were added nearby:
--      an auxiliary / exit lane): exit-only ("lane_added");
--   2. the main road's previous junction (3+ road segments) is closer than LOOK_ROOM_M: shared
--      ("junction_close"; no room for through traffic that entered there in the kerb lane, e.g. from
--      an on-ramp or a side road, to move out of it);
--   3. otherwise exit-only, by the counts: "lane_added" when some (not all) of the exit lanes were
--      added on the walk, "through_road" for a road that carried all N lanes the whole walk.
-- Nothing downstream is walked: through traffic keeps N - E >= 2 lanes at the node by the counts.
-- Returns { diverge = "exit_only" | "shared", why, exits = E, up = walk }.
function S.divergeLook(world, n, st)
	local N = #st.m
	local E = S.exitLanes(N, #st.t, #st.b)
	local up = Walk.follow(world, n, st.inSeg, { dir = "in" })
	local function res(d, why) return { diverge = d, why = why, exits = E, up = up } end
	local minUp = Walk.minLanes(up)
	if minUp > 0 and minUp <= N - E then return res("exit_only", "lane_added") end
	local jd = Walk.junctionDist(up)
	if jd ~= nil and jd < S.LOOK_ROOM_M then return res("shared", "junction_close") end
	if minUp > 0 and minUp < N then return res("exit_only", "lane_added") end
	return res("exit_only", "through_road")
end

---------------------------------------------------------------------------
-- Remembered driving side (PHASE7.md step 3): one-way roads far from any two-way road

-- The driving side is one setting per map, so where only one-way roads are near (a highway
-- carriageway's lane drop, case "D") a two-way road read elsewhere tells it. What is remembered is
-- not the side but an ANCHOR: the last two-way road segment (and its node) a side was read from
-- reliably (every S.classify call reads the two-way roads at its node; sideNear the ones its walks
-- meet). Module state lives as long as the Lua state, and whether the GUI / game-script states are
-- rebuilt when another save is loaded in the same session is not verified: a bare side could leak
-- from a right-hand map into a left-hand one and wire every lane mirrored. So the side is re-read from
-- the current world on every use (S.rememberedSide(world)): the anchor node must exist, the anchor
-- segment must still be attached to it, and its lanes there must be two-way with a clear side;
-- otherwise the anchor is dropped and nothing is remembered (the caller then says "no_side"). In
-- another map the same ids name some other road, and its side is that map's side. Setting the anchor
-- costs no world reads (two locals); only a use reads one node and one segment. Case A (all one-way)
-- never uses it: there the kerb is the branch's side. Tests reset it (S.resetSide).
local anchorNode, anchorSeg = nil, nil

--- Remembers the anchor: two-way road segment `seg` at node `node`, whose lanes there told the side.
function S.rememberSide(node, seg)
	if node ~= nil and seg ~= nil then anchorNode, anchorSeg = node, seg end
end

--- The driving side re-read at the anchor in `world` ("right" | "left"), or nil (no anchor, or it no
-- longer names a two-way road segment at that node in this world: the anchor is dropped).
function S.rememberedSide(world)
	if anchorNode == nil or world == nil then return nil end
	local node = world.node(anchorNode)
	local attached = false
	for _, sid in ipairs(node and node.segs or {}) do
		if sid == anchorSeg then attached = true end
	end
	local s = attached and world.seg(anchorSeg) or nil
	local la = s and Ring.lanesAt(s, anchorNode)
	local side = la and #la.incoming > 0 and #la.outgoing > 0 and S.sideOf(la) or nil
	if side == nil then anchorNode, anchorSeg = nil, nil end
	return side
end

--- The remembered anchor (node, seg), or nil (tests).
function S.rememberedAnchor() return anchorNode, anchorSeg end

--- Forgets the remembered anchor (tests).
function S.resetSide() anchorNode, anchorSeg = nil, nil end

---------------------------------------------------------------------------
-- Plain lane drops and gains (PHASE7.md step 2): case "D"

--- Driving side near node n for a node of one-way roads only, or nil: the first two-way segment met by
-- a bounded walk (Walk.follow caps) along each road from n, or at the node the walk stopped at. The
-- driving side is one setting for the whole map, so any two-way road nearby tells it.
local function sideNear(world, n, roads)
	for _, r in ipairs(roads) do
		local w = Walk.follow(world, n, r.sid, { dir = #r.la.outgoing > 0 and "out" or "in" })
		for _, st in ipairs(w.steps) do
			local s = world.seg(st.seg)
			local la = s and Ring.lanesAt(s, st.from)
			local side = la and S.sideOf(la)
			if side then
				S.rememberSide(st.from, st.seg)
				return side
			end
		end
		if w.node ~= nil and w.node ~= n then
			for _, x in ipairs(Walk.roadSegs(world, w.node) or {}) do
				local side = S.sideOf(x.la)
				if side then
					S.rememberSide(w.node, x.sid)
					return side
				end
			end
		end
	end
	return nil
end

--- View of a node with exactly two road segments (`roads`, as in S.classify). Nothing to do ("none",
-- reason "roads_2", the common case, decided on four lane counts) unless a travel direction's lane
-- count changes. Then case "D", one "straight" stream per travel direction with lanes on both roads
-- (S.pairs("straight"): matched from the far side, extra incoming kerb lanes fold into the kerb-most
-- continuing lane, extra outgoing kerb lanes fed by the kerb lane; a direction whose count stays is
-- matched lane to lane), shape "lane_drop" | "lane_gain" | "lane_drop+gain".
--   * two two-way roads: driving side from their lane layout (both must agree, else skip "mixed_sides");
--   * two one-way roads, one in and one out: driving side from the nearest two-way road (sideNear),
--     else the remembered side (S.rememberedSide: re-read in this world at the anchor of an earlier
--     reading; sideFrom "remembered"); neither: "none" ("no_side"). A one-way loop through the node (a ring Ring.findRing refused,
--     e.g. mixed lane counts) stays "none" ("loop"): rings are the ring rules' business;
--   * a two-way road meeting a one-way road ("one_way_end"), or two one-way roads against each other
--     ("one_way_clash"): "none". There one direction of the two-way road has no road to go on, and
--     what the game does with it (turnarounds?) is unknown, so the node is left alone.
-- Bus lanes: skip "bus_lane". A segment with both ends at the node: "none" ("self_loop"). Tram
-- connections are kept by the caller (Rules.mergeTram); S.plan skips ("u_turn") a node whose current
-- connections include a road U-turn (a turnaround the rule does not model).
local function classifyDrop(world, n, roads, v)
	local a, b = roads[1], roads[2]
	if a.sid == b.sid then
		-- one segment with both ends at the node (a self-loop): no road on either side to match
		v.kind, v.reason = "none", "self_loop"
		return v
	end
	local abIn, abOut = #a.la.incoming, #b.la.outgoing -- travel a -> b
	local baIn, baOut = #b.la.incoming, #a.la.outgoing -- travel b -> a
	if abIn == abOut and baIn == baOut then
		v.kind, v.reason = "none", "roads_2"
		return v
	end
	if (abIn > 0) ~= (abOut > 0) or (baIn > 0) ~= (baOut > 0) then
		v.kind, v.reason = "none", (a.twoWay or b.twoWay) and "one_way_end" or "one_way_clash"
		return v
	end
	if a.la.busOnly or b.la.busOnly then return skip(v, "bus_lane") end
	v.case = "D"
	local side
	if a.twoWay and b.twoWay then
		local sA, sB = S.sideOf(a.la), S.sideOf(b.la)
		if sA == nil or sA ~= sB then return skip(v, "mixed_sides") end
		side, v.sideFrom = sA, "two_way"
	else
		if Ring.shortestCycle(world, n) ~= nil then
			v.kind, v.reason = "none", "loop"
			return v
		end
		side = sideNear(world, n, roads)
		v.sideFrom = "walk"
		if side == nil then
			-- the anchor re-read in this world (S.rememberedSide): nil when it is gone or no longer two-way
			side = S.rememberedSide(world)
			if side ~= nil then v.sideFrom = "remembered" end
		end
		if side == nil then
			v.sideFrom = nil
			v.kind, v.reason = "none", "no_side"
			return v
		end
	end
	v.side = side
	local drop, gain = false, false
	for _, d in ipairs({ { from = a, to = b }, { from = b, to = a } }) do
		if #d.from.la.incoming > 0 then
			local st = makeStream(world, n, { shape = "straight", kerb = side, inSeg = d.from.sid, outSeg = d.to.sid })
			if #st.m > #st.o then st.change, drop = "drop", true end
			if #st.m < #st.o then st.change, gain = "gain", true end
			v.streams[#v.streams + 1] = st
		end
	end
	if drop and gain then v.shape = "lane_drop+gain" elseif drop then v.shape = "lane_drop" else v.shape = "lane_gain" end
	v.kind = "slip"
	return v
end
S.classifyDrop = classifyDrop

--- The rules' view of node n:
-- { node, kind = "slip" | "none" | "skip", reason, case = "A" | "B" | "X" | "D", side (driving side when known:
--   "right" | "left"), sideFrom = "two_way" | "branch" | "walk" | "remembered", roads, streams = { stream... },
--   shape }
-- Case "D" (classifyDrop): a plain node of two roads where a travel direction's lane count changes;
-- its streams are all "straight" (st.change = "drop" | "gain" | nil), shape "lane_drop" | "lane_gain" |
-- "lane_drop+gain".
-- stream: { shape, kerb, inSeg/throughSeg/branchSeg/outSeg, m/t/b or p/q/o (kerb-first lanes),
--   deg (branch turn), throughDeg, look (merges whose counts allow the own-lane merge: S.mergeLook;
--   diverges whose counts allow exit-only kerb lanes: S.divergeLook), giveWay (true: the give-way merge
--   although the counts allow the own-lane one), exitOnly (true: the exit-only diverge) }.
-- Side effect: a two-way road at the node that tells the driving side reliably becomes the remembered
-- anchor (S.rememberSide; no world reads).
-- shape: "diverge", "merge" or "diverge+merge".
-- A game world (sl_write W.makeWorld: world.memo) keeps the view per node, so the tool's street walk,
-- badge and lane view classify a node once per world; callers only read the view. A view without a
-- driving side ("no_side") is not kept: a later call may find the side another node remembered.
local function classifyOf(world, n)
	local v = { node = n, streams = {} }
	local node = world.node(n)
	if not node then return skip(v, "no_node") end
	local roads = {}
	for _, sid in ipairs(node.segs or {}) do
		local s = world.seg(sid)
		local la = s and Ring.lanesAt(s, n)
		if la and (#la.incoming + #la.outgoing) > 0 then
			roads[#roads + 1] = { sid = sid, la = la, twoWay = #la.incoming > 0 and #la.outgoing > 0 }
		end
	end
	v.roads = #roads
	local oneWay = 0
	for _, r in ipairs(roads) do if not r.twoWay then oneWay = oneWay + 1 end end
	do
		-- remember the driving side: the two-way roads' lane layouts, when every one that tells agrees
		-- (the anchor: the first such segment at n; no world reads)
		local side, mixed, at = nil, false, nil
		for _, r in ipairs(roads) do
			local s = r.twoWay and S.sideOf(r.la) or nil
			if s ~= nil then
				if side ~= nil and s ~= side then mixed = true end
				side, at = s, at or r.sid
			end
		end
		if side ~= nil and not mixed then S.rememberSide(n, at) end
	end
	-- crossroads and T-junctions of two-way roads: sl_cross.lua (case "X")
	if #roads >= 3 and oneWay == 0 then return Cross.classify(world, n, roads, v) end
	-- plain nodes: a lane drop or gain (case "D"), else nothing to do
	if #roads == 2 then return classifyDrop(world, n, roads, v) end
	if #roads < 3 or oneWay == 0 then
		v.kind, v.reason = "none", #roads < 3 and "roads_" .. #roads or "no_one_way"
		return v
	end
	if #roads > S.MAX_ROADS then return skip(v, "roads_" .. #roads) end
	for _, r in ipairs(roads) do
		if r.la.busOnly then return skip(v, "bus_lane") end
	end
	local twoWays = #roads - oneWay

	if twoWays == 0 then
		-- case A: one-way main road with one branch
		if #roads ~= 3 then return skip(v, "one_way_" .. #roads) end
		local ins, outs = {}, {}
		for _, r in ipairs(roads) do
			if #r.la.incoming > 0 then ins[#ins + 1] = r.sid else outs[#outs + 1] = r.sid end
		end
		-- every road leaving (or every road arriving): no stream to plan (a T of three ramps drawn all out)
		if #ins == 0 or #outs == 0 then return skip(v, "one_way_dir") end
		v.case, v.sideFrom = "A", "branch"
		local function laneCount(sid)
			local la = Ring.lanesAt(world.seg(sid), n)
			return #la.incoming + #la.outgoing
		end
		if #ins == 1 then
			local c1 = { seg = outs[1], deg = turnDeg(world, n, ins[1], outs[1]), far = farTurnDeg(world, n, ins[1], outs[1]), lanes = laneCount(outs[1]) }
			local c2 = { seg = outs[2], deg = turnDeg(world, n, ins[1], outs[2]), far = farTurnDeg(world, n, ins[1], outs[2]), lanes = laneCount(outs[2]) }
			local t, b, side, why, how = splitPair(c1, c2, laneCount(ins[1]))
			if not t then return skip(v, why) end
			v.splitBy = how
			v.streams[1] = makeStream(world, n, { shape = "diverge", kerb = side, inSeg = ins[1],
				throughSeg = t.seg, branchSeg = b.seg, deg = b.deg, throughDeg = t.deg })
		else
			local c1 = { seg = ins[1], deg = turnDeg(world, n, ins[1], outs[1]), far = farTurnDeg(world, n, ins[1], outs[1]), lanes = laneCount(ins[1]) }
			local c2 = { seg = ins[2], deg = turnDeg(world, n, ins[2], outs[1]), far = farTurnDeg(world, n, ins[2], outs[1]), lanes = laneCount(ins[2]) }
			local t, b, side, why, how = splitPair(c1, c2, laneCount(outs[1]))
			if not t then return skip(v, why) end
			v.splitBy = how
			-- a branch joining from the right turns right into the road (it heads across the road's
			-- direction towards it), so the turn side is the side it joins from
			v.streams[1] = makeStream(world, n, { shape = "merge", kerb = side, throughSeg = t.seg,
				branchSeg = b.seg, outSeg = outs[1], deg = b.deg, throughDeg = t.deg })
		end
	elseif twoWays == 2 then
		-- case B: two-way main road, one or two one-way branches
		v.case, v.sideFrom = "B", "two_way"
		-- not a slip lane (a ramp end or one-way street meeting the road at a right angle, a branch
		-- on the far side, a bent main road): the crossing rule takes it as an ordinary junction
		local function toCross(reason)
			v.streams, v.slipReason = {}, reason
			return Cross.classify(world, n, roads, v)
		end
		local A, Bm, branches = nil, nil, {}
		for _, r in ipairs(roads) do
			if r.twoWay then
				if A == nil then A = r else Bm = r end
			else
				branches[#branches + 1] = r
			end
		end
		local sA, sB = S.sideOf(A.la), S.sideOf(Bm.la)
		if sA == nil or sA ~= sB then return skip(v, "mixed_sides") end
		v.side = sA
		local kerb = sA
		local dirs = {
			{ from = A.sid, to = Bm.sid },
			{ from = Bm.sid, to = A.sid },
		}
		for _, d in ipairs(dirs) do
			d.deg = turnDeg(world, n, d.from, d.to)
			if math.abs(d.deg) > S.STRAIGHT_MAX_DEG then return toCross("main_bend") end
		end
		-- each branch to the travel direction it turns least from, by the tangents at the node;
		-- returns nil or why not
		local function byTangents()
			for _, br in ipairs(branches) do
				local leaving = #br.la.outgoing > 0
				local best, bestDeg = nil, nil
				for _, d in ipairs(dirs) do
					local deg
					if leaving then deg = turnDeg(world, n, d.from, br.sid) else deg = turnDeg(world, n, br.sid, d.to) end
					if best == nil or math.abs(deg) < math.abs(bestDeg) then best, bestDeg = d, deg end
				end
				if math.abs(bestDeg) >= S.MAX_TURN_DEG then return "branch_turn" end
				if best.branch then return "two_branches_one_direction" end
				local t = { seg = best.to, deg = best.deg }
				local b = { seg = br.sid, deg = bestDeg }
				local key = "deg"
				if math.abs(b.deg) - math.abs(t.deg) < S.MIN_SPLIT_DEG or math.abs(b.deg - t.deg) < S.MIN_SPLIT_DEG then
					-- tangential: decide by the far ends (as splitPair)
					t.far = farTurnDeg(world, n, best.from, best.to)
					if leaving then b.far = farTurnDeg(world, n, best.from, br.sid) else b.far = farTurnDeg(world, n, br.sid, best.to) end
					if math.abs(b.far) - math.abs(t.far) < S.MIN_FAR_SPLIT_DEG or math.abs(b.far - t.far) < S.MIN_FAR_SPLIT_DEG then
						return "ambiguous"
					end
					key = "far"
					v.splitBy = "far"
				end
				-- leaving: the branch turns towards its side; joining: it turns towards the side it
				-- comes from as well (heading across the road towards it)
				local side = (b[key] > t[key]) and "left" or "right"
				if side ~= kerb then return "far_side_branch" end
				best.branch, best.leaving, best.branchDeg = br.sid, leaving, bestDeg
			end
			return nil
		end
		-- shallow ramps (sl_cross X.shallowRamps; in game 2026-10-11: ramps that peel off alongside the
		-- road had their tangent 80-100 deg off it at the node, so they went to the crossing rule,
		-- which let traffic turn across the oncoming carriageway into them): every branch a shallow
		-- ramp heading along the travel direction on whose kerb side it lies, one per direction.
		-- Returns true when that assigned them all.
		local function byShallowRamps()
			local sh = Cross.shallowRamps(world, n, roads, kerb)
			if sh == nil then return false end
			v.rampDeg = sh.measured
			for _, br in ipairs(branches) do
				local info = sh.ramps[br.sid]
				if info == nil or not info.forward then return false end
				local d = nil
				for _, x in ipairs(dirs) do
					if x.from == info.from and x.to == info.to then d = x end
				end
				if d == nil or d.branch ~= nil then return false end
				local leaving = #br.la.outgoing > 0
				d.branch, d.leaving = br.sid, leaving
				if leaving then d.branchDeg = turnDeg(world, n, d.from, br.sid) else d.branchDeg = turnDeg(world, n, br.sid, d.to) end
			end
			return true
		end
		local why = byTangents()
		if why == "ambiguous" then return skip(v, "ambiguous") end
		if why == nil then
			-- a ramp end that meets the road at about a right angle (a diamond or parclo terminal: its
			-- tangent at the node may lean less than MAX_TURN_DEG towards one direction, but its chord
			-- over the first 50 m is more than SHALLOW_MAX_DEG off the road) is no slip lane: the
			-- crossing rule keeps its turns both ways. Town one-way streets (sidewalks) are no ramps.
			local sh = nil
			for _, br in ipairs(branches) do
				if Cross.isRamp(world, br) then
					if sh == nil then sh = Cross.shallowRamps(world, n, roads, kerb) or false end
					local deg = sh and sh.deg[br.sid]
					if deg ~= nil and deg > Cross.SHALLOW_MAX_DEG then
						v.splitBy = nil
						return toCross("terminal")
					end
				end
			end
		else
			for _, d in ipairs(dirs) do d.branch, d.leaving, d.branchDeg = nil, nil, nil end
			v.splitBy = nil
			if not byShallowRamps() then
				for _, d in ipairs(dirs) do d.branch, d.leaving, d.branchDeg = nil, nil, nil end
				return toCross(why)
			end
			v.splitBy, v.shallowFrom = "shallow", why
		end
		for _, d in ipairs(dirs) do
			local st
			if d.branch == nil then
				st = { shape = "straight", kerb = kerb, inSeg = d.from, outSeg = d.to }
			elseif d.leaving then
				st = { shape = "diverge", kerb = kerb, inSeg = d.from, throughSeg = d.to, branchSeg = d.branch,
					deg = d.branchDeg, throughDeg = d.deg }
			else
				st = { shape = "merge", kerb = kerb, throughSeg = d.from, branchSeg = d.branch, outSeg = d.to,
					deg = d.branchDeg, throughDeg = d.deg }
			end
			v.streams[#v.streams + 1] = makeStream(world, n, st)
		end
	elseif twoWays >= 3 then
		-- three two-way roads and a one-way road (a crossroads with a ramp or one-way street, a
		-- two-way side road at a ramp node): the crossing rule, whose shallow-ramp rule keeps through
		-- traffic from turning across the opposing carriageway into a ramp
		v.case, v.sideFrom, v.slipReason = "X", "two_way", "three_two_way"
		return Cross.classify(world, n, roads, v)
	else
		-- one two-way road and one-way roads: a roundabout splitter's split node (an arm forking
		-- into its exit and entry legs, PHASE6.md: leave it) or a dual carriageway's end, where the
		-- two-way road runs on into a one-way road. Not a slip node, and not logged (every splitter
		-- roundabout has them). A two-way road meeting a one-way street at a right angle (every
		-- one-way road turns more than STRAIGHT_MAX_DEG from it) is a junction: the crossing rule.
		local two = nil
		for _, r in ipairs(roads) do if r.twoWay then two = r end end
		local square = true
		for _, r in ipairs(roads) do
			if not r.twoWay then
				local deg
				if #r.la.outgoing > 0 then deg = turnDeg(world, n, two.sid, r.sid) else deg = turnDeg(world, n, r.sid, two.sid) end
				if math.abs(deg) <= S.STRAIGHT_MAX_DEG then square = false end
			end
		end
		if square then
			v.slipReason = "one_way_square"
			return Cross.classify(world, n, roads, v)
		end
		v.kind, v.reason = "none", "mixed_one_way"
		return v
	end

	-- every stream needs lanes on each of its roads
	local hasD, hasM = false, false
	for _, st in ipairs(v.streams) do
		for _, key in ipairs({ "m", "t", "b", "p", "q", "o" }) do
			if st[key] ~= nil and #st[key] == 0 then return skip(v, "no_lanes") end
		end
		if st.shape == "diverge" then hasD = true end
		if st.shape == "merge" then hasM = true end
	end
	if hasD and hasM then v.shape = "diverge+merge" elseif hasD then v.shape = "diverge" else v.shape = "merge" end
	for _, st in ipairs(v.streams) do
		if st.shape == "merge" and #st.p + #st.q > #st.o and #st.o - #st.q >= 2 then
			st.look = S.mergeLook(world, n, st)
			st.giveWay = st.look.merge == "give_way"
		elseif st.shape == "diverge" and S.exitLanes(#st.m, #st.t, #st.b) > 0 then
			st.look = S.divergeLook(world, n, st)
			st.exitOnly = st.look.diverge == "exit_only"
		end
	end
	v.kind = "slip"
	return v
end

function S.classify(world, n)
	local memo = world.memo
	if memo == nil or type(n) ~= "number" then return classifyOf(world, n) end
	local m = memo.classify
	if m == nil then
		m = {}
		memo.classify = m
	end
	local v = m[n]
	if v == nil then
		v = classifyOf(world, n)
		if v.reason ~= "no_side" then m[n] = v end
	end
	return v
end

---------------------------------------------------------------------------
-- The rule

local function push(list, seen, s0, l0, s1, l1)
	local c = Rules.conn(s0, l0, s1, l1, true, false)
	local key = s0 .. ":" .. l0 .. ">" .. s1 .. ":" .. l1
	if not seen[key] then
		seen[key] = true
		list[#list + 1] = c
	end
end

--- Pairs (1-based kerb-first positions) of the lane rule for one stream. Returns a list of
-- { from = "m"|"p"|"q", i, to = "t"|"b"|"o", j }. Pure counts, so tests can check it per shape.
-- flag, merge: giveWay, true keeps the give-way merge where the counts allow the own-lane one (the
-- look-ahead's decision, S.mergeLook); diverge: exitOnly, true makes the S.exitLanes kerb lanes
-- exit-only where the counts allow it (S.divergeLook); nil / false: the count rule alone (a shared
-- kerb lane when N <= T).
function S.pairs(shape, a, b, c, flag)
	local out = {}
	local function add(f, i, t, j) out[#out + 1] = { from = f, i = i, to = t, j = j } end
	-- straight / through part: lanes 1..N into 1..T aligned from the far side; the extra kerb
	-- lanes fan (out) or fold (in) on the kerb lane. Returns nothing; adds pairs.
	local function aligned(f, N, t, T, lowest)
		lowest = lowest or 1
		local k = math.min(N - lowest + 1, T)
		for d = 0, k - 1 do add(f, N - d, t, T - d) end
		for j = 1, T - k do add(f, lowest, t, j) end         -- extra outgoing: fed by the kerb-most lane
		for i = lowest, N - k do add(f, i, t, 1) end          -- extra incoming: fold into the kerb lane
	end
	if shape == "straight" then
		aligned("m", a, "o", b)
	elseif shape == "diverge" then
		local N, T, B = a, b, c
		local E = flag and S.exitLanes(N, T, B) or 0
		if E > 0 then
			-- exit-only: m_1..m_E feed only the branch (extra branch lanes fan from m_E); the rest go
			-- straight aligned from the far side, m_(E+1) also feeding the kerb-side through lanes
			for i = 1, E do add("m", i, "b", i) end
			for j = E + 1, B do add("m", E, "b", j) end
			aligned("m", N, "t", T, E + 1)
			return out
		end
		local f = math.max(1, N - T + 1)
		local k = math.min(B, N, f)
		for i = 1, k do add("m", i, "b", i) end
		for j = k + 1, B do add("m", k, "b", j) end
		-- through: m_f..m_N aligned from the far side; with N < T the extra kerb through lanes
		-- fan from m_1 (f = 1); lanes between the branch feeders and m_f fold into t_1
		aligned("m", N, "t", T, f)
		for i = k + 1, f - 1 do add("m", i, "t", 1) end
	else -- merge: a = T (through in), b = B (branch in), c = O
		local T, B, O = a, b, c
		if T + B > O and O - B >= 2 and not flag then
			-- not enough lanes for both, and the through road keeps two or more: the branch keeps
			-- its own kerb lanes (never waits to merge) and the through lanes fold among themselves
			-- into the rest, the extra kerb-side through lanes into the kerb-most of them
			-- (in game 2026-10-11: a loop ramp sharing the kerb lane of a 3-lane road queued)
			local M = O - B
			for i = 1, B do add("q", i, "o", i) end
			local k = math.min(T, M)
			for d = 0, k - 1 do add("p", T - d, "o", O - d) end
			for i = 1, T - k do add("p", i, "o", B + 1) end
			return out
		end
		local k = math.min(T, O)
		for d = 0, k - 1 do add("p", T - d, "o", O - d) end
		for i = 1, T - k do add("p", i, "o", 1) end
		local cap = math.max(1, O - T + 1)
		for i = 1, B do add("q", i, "o", math.min(i, cap)) end
		-- outgoing lanes between the branch's (1..min(B, cap)) and the through lanes' (O-T+1..O)
		local qTop = math.min(B, cap)
		local pLow = O - k + 1
		for j = qTop + 1, pLow - 1 do
			if j - qTop < pLow - j then add("q", B, "o", j) else add("p", T - k + 1, "o", j) end
		end
	end
	return out
end

--- Road connections for a slip node view (kind "slip").
function S.roadConns(v)
	if v.case == "X" then return Cross.roadConns(v) end
	local list, seen = {}, {}
	for _, st in ipairs(v.streams) do
		local segOf, lanes
		if st.shape == "straight" then
			segOf = { m = st.inSeg, o = st.outSeg }
			lanes = { m = st.m, o = st.o }
			for _, pr in ipairs(S.pairs("straight", #st.m, #st.o)) do
				push(list, seen, segOf[pr.from], lanes[pr.from][pr.i], segOf[pr.to], lanes[pr.to][pr.j])
			end
		elseif st.shape == "diverge" then
			segOf = { m = st.inSeg, t = st.throughSeg, b = st.branchSeg }
			lanes = { m = st.m, t = st.t, b = st.b }
			for _, pr in ipairs(S.pairs("diverge", #st.m, #st.t, #st.b, st.exitOnly)) do
				push(list, seen, segOf[pr.from], lanes[pr.from][pr.i], segOf[pr.to], lanes[pr.to][pr.j])
			end
		else
			segOf = { p = st.throughSeg, q = st.branchSeg, o = st.outSeg }
			lanes = { p = st.p, q = st.q, o = st.o }
			for _, pr in ipairs(S.pairs("merge", #st.p, #st.q, #st.o, st.giveWay)) do
				push(list, seen, segOf[pr.from], lanes[pr.from][pr.i], segOf[pr.to], lanes[pr.to][pr.j])
			end
		end
	end
	return list
end

--- The game's own connections (a model) for a view, or nil where there is none (slip nodes, and
-- lane drops: no in-game dump of the game's connections there yet, so the tool's Reset restores the
-- snapshot from before its first Apply, as at slip nodes).
function S.defaultConns(v)
	if v.case == "X" then return Cross.defaultConns(v) end
	return nil
end

--- Whether `cur` is the game's default at view v (sl_cross X.isDefault: per movement, not per lane);
-- nil where there is no model (not case "X").
function S.isDefault(v, cur)
	if v ~= nil and v.case == "X" then return Cross.isDefault(v, cur) end
	return nil
end

--- Kerb turns of a crossroads / T-junction view (case "X", sl_cross X.kerbPairs), nil otherwise.
function S.kerbPairs(v)
	if v ~= nil and v.case == "X" then return (Cross.kerbPairs(v)) end
	return nil
end

--- Short lane summary of a view: "2 -> 2 + 2" (diverge: main -> through + branch), "2 + 1 -> 2"
-- (merge: through + branch -> out); both streams joined with "; ".
-- Case "D": "3 -> 2" per travel direction (in -> out lanes).
function S.summary(v)
	if v.case == "X" then return Cross.summary(v) end
	local parts = {}
	for _, st in ipairs(v.streams or {}) do
		if st.shape == "straight" and v.case == "D" then
			parts[#parts + 1] = string.format("%d -> %d", #st.m, #st.o)
		elseif st.shape == "diverge" then
			parts[#parts + 1] = string.format("%d -> %d + %d slip", #st.m, #st.t, #st.b)
		elseif st.shape == "merge" then
			parts[#parts + 1] = string.format("%d + %d slip -> %d", #st.p, #st.q, #st.o)
		end
	end
	return table.concat(parts, "; ")
end

--- Main road lanes of a view (the largest incoming main-road lane count of a diverge or merge;
-- case "D": the wider side of a direction whose lane count changes).
function S.mainLanes(v)
	if v.case == "X" then return Cross.mainLanes(v) end
	local n = 0
	for _, st in ipairs(v.streams or {}) do
		if st.change ~= nil then n = math.max(n, #st.m, #st.o) end
		if st.shape == "diverge" then n = math.max(n, #st.m) end
		if st.shape == "merge" then n = math.max(n, #st.o) end
	end
	return n
end

--- Plans one slip node: { node, view, status = "apply" | "same" | "skip" | "none", reason,
-- before, after, conns, fan, fanWait }. currentConns(n) -> the node's connections (plain tables).
-- opts (optional): { fan = true } (the node lies in an sl_fan zone): a case "X" node that is lit
-- (X.litOf true) gets the full fan (Cross.fanConns; r.fan = true; the caller writes it only with the
-- fan phase plan); unlit or unknown it keeps the rule (r.fanWait = "unlit" | "lit_unknown"). Other
-- cases: the rule.
function S.plan(world, n, currentConns, opts)
	local v = S.classify(world, n)
	local r = { node = n, view = v }
	if v.kind ~= "slip" then
		r.status, r.reason = v.kind, v.reason
		return r
	end
	local cur = currentConns(n) or {}
	if v.case == "D" then
		-- a lane drop is a plain stretch of road: a road U-turn there (a turnaround the game or the
		-- player made) is something the rule does not model, so the node is left alone, never wiped
		for _, c in ipairs(cur) do
			if c.withRoad and c.segment0 == c.segment1 then
				r.status, r.reason = "skip", "u_turn"
				return r
			end
		end
	end
	local road = nil
	if opts ~= nil and opts.fan and v.case == "X" then
		if v.lit == true then
			road, r.fan = Cross.fanConns(v), true
		else
			r.fanWait = v.lit == false and "unlit" or "lit_unknown"
		end
	end
	local conns = Rules.mergeTram(road or S.roadConns(v), cur)
	r.before, r.after, r.conns = Rules.roadCount(cur), Rules.roadCount(conns), conns
	if Rules.connsText(conns) == Rules.connsText(cur) then r.status = "same" else r.status = "apply" end
	return r
end

--- Log fields describing node n's roads and its current connections, for reading a junction someone
-- edited with the Crossing Tool. Returns { roads = fields, conns = { fields... } }:
-- roads: per road "seg@heading(in,out)" (heading in degrees, counterclockwise from +x, pointing away
-- from the node; in/out: road lanes arriving / leaving); conns: one per connection: from = seg:lane
-- (segment0, the arriving lane), to = seg:lane, turn = signed degrees (left positive), road / tram.
function S.describe(world, n, conns)
	local node = world.node(n)
	local roads = {}
	for _, sid in ipairs(node and node.segs or {}) do
		local s = world.seg(sid)
		if s then
			local x, y = S.awayDir(s, n)
			local la = Ring.lanesAt(s, n)
			roads[#roads + 1] = string.format("%d@%.0f(%d,%d)", sid, math.deg(atan2(y, x)), la and #la.incoming or 0,
				la and #la.outgoing or 0)
		end
	end
	local out = {}
	for _, c in ipairs(conns or {}) do
		local okT, deg = pcall(turnDeg, world, n, c.segment0, c.segment1)
		out[#out + 1] = { { "node", n }, { "from", c.segment0 .. ":" .. c.lane0 }, { "to", c.segment1 .. ":" .. c.lane1 },
			{ "turn", okT and string.format("%.0f", deg) or "?" }, { "road", c.withRoad }, { "tram", c.withTram } }
	end
	return { roads = { { "node", n }, { "roads", table.concat(roads, ";") }, { "conns", #out } }, conns = out }
end

--- Log fields of a planned slip node (APPLY / SKIP lines, kind=slip; case X: via=<why a node with
-- one-way roads went to the crossing rule>, bypass=<turns left to a slip lane>).
-- Case "D": kind=drop, side_from = two_way | walk | remembered.
function S.logFields(r)
	local v = r.view
	if v.case == "D" then
		return { { "kind", "drop" }, { "node", r.node }, { "shape", v.shape or "-" }, { "case", "D" },
			{ "side", v.side or "-" }, { "side_from", v.sideFrom or "-" }, { "lanes", S.summary(v) },
			{ "before", r.before }, { "after", r.after } }
	end
	local f = { { "kind", "slip" }, { "node", r.node }, { "shape", v.shape or "-" }, { "case", v.case or "-" } }
	-- a node with one-way roads handed over to the crossing rule (case X): why (the view's slipReason:
	-- main_bend, terminal, branch_turn, two_branches_one_direction, far_side_branch, three_two_way,
	-- one_way_square)
	if v.case == "X" and v.slipReason ~= nil then f[#f + 1] = { "via", v.slipReason } end
	for _, x in ipairs({
		{ "side", v.side or ("branch_" .. tostring(v.streams[1] and v.streams[1].kerb)) },
		{ "lanes", S.summary(v) }, { "split", v.splitBy or "node" }, { "before", r.before }, { "after", r.after } }) do
		f[#f + 1] = x
	end
	-- the look-aheads' decisions (only diverges whose counts allow exit-only kerb lanes, merges whose
	-- counts allow the own-lane merge): diverge=.. merge=.. why=<diverge's>,<merge's> (at most one of
	-- each per node: case A has one stream, case B one branch per travel direction)
	local diverge, merge, dWhy, mWhy = {}, {}, {}, {}
	for _, st in ipairs(v.streams or {}) do
		if st.look and st.look.diverge then
			diverge[#diverge + 1] = st.look.diverge
			dWhy[#dWhy + 1] = st.look.why
		elseif st.look and st.look.merge then
			merge[#merge + 1] = st.look.merge
			mWhy[#mWhy + 1] = st.look.why
		end
	end
	if #diverge > 0 then f[#f + 1] = { "diverge", table.concat(diverge, ",") } end
	if #merge > 0 then f[#f + 1] = { "merge", table.concat(merge, ",") } end
	for _, w in ipairs(mWhy) do dWhy[#dWhy + 1] = w end
	if #dWhy > 0 then f[#f + 1] = { "why", table.concat(dWhy, ",") } end
	-- case X: turns left to a slip lane (sl_cross X.bypasses), as a count
	if v.bypassed and #v.bypassed > 0 then f[#f + 1] = { "bypass", #v.bypassed } end
	-- case X: approaches with more lanes than all their exits, folded (sl_cross X.allocateView)
	if v.squeeze and #v.squeeze > 0 then f[#f + 1] = { "squeeze", table.concat(v.squeeze, ",") } end
	-- case X: the node's traffic lights (yes / no / unknown) and the approaches whose extra straight
	-- share was dropped because the node is unlit (X.allocateView)
	if v.case == "X" then f[#f + 1] = { "lit", Cross.litName(v.lit) } end
	-- an sl_fan zone (S.plan opts.fan): mode=fan (the full fan written with its fan plan), or
	-- fan=unlit | lit_unknown (the rule instead: no fan without a light)
	if r.fan then f[#f + 1] = { "mode", "fan" } elseif r.fanWait then f[#f + 1] = { "fan", r.fanWait } end
	-- an sl_exitfan zone (sl_cross X.classify): exit_fan=yes (the turns fanned over the exit lanes), else why
	-- not (unlit | lit_unknown | one_way | x_axes | t_axis | roads); nothing outside the zone
	if v.case == "X" and v.exitFan then f[#f + 1] = { "exit_fan", "yes" }
	elseif v.case == "X" and v.exitFanWhy then f[#f + 1] = { "exit_fan", v.exitFanWhy } end
	if v.unshared and #v.unshared > 0 then f[#f + 1] = { "unshared", table.concat(v.unshared, ",") } end
	-- shallow ramps (sl_cross X.shallowRamps): moves left out across the opposing carriageway (case
	-- X), the case B assignment's reason (split=shallow), every ramp's chord angle off the road
	if v.shallowBlocked and #v.shallowBlocked > 0 then f[#f + 1] = { "shallow", table.concat(v.shallowBlocked, ",") } end
	-- moves the shallow rule would leave out but that are an exit road's only feed or a ramp's only way on
	if v.shallowKept and #v.shallowKept > 0 then f[#f + 1] = { "shallow_kept", table.concat(v.shallowKept, ",") } end
	if v.shallowFrom then f[#f + 1] = { "tangent", v.shallowFrom } end
	if v.rampDeg and #v.rampDeg > 0 then f[#f + 1] = { "ramp_deg", table.concat(v.rampDeg, ",") } end
	return f
end

return S
