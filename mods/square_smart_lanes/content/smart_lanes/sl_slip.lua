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
--     direction of the main road is a straight stream.
--   * anything else is not a slip node ("none": fewer than 3 road segments, no one-way segment, or
--     one two-way road with one-way roads such as a roundabout splitter's split node;
--     "skip" with a reason for candidates that do not fit: crossroads, 5+ roads, bus lanes,
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
--   * merge: through lanes 1:1 into o aligned from the far side (extra kerb-side through lanes fold
--     into o_1); branch lanes q_i -> o_min(i, c) with c = max(1, O - T + 1): with T + B <= O
--     nobody shares; otherwise the branch shares the kerb-side lanes with the through lanes (a
--     give-way merge) and never crosses them; B > c folds the extra branch lanes into o_c. Outgoing
--     lanes between the branch's and the through lanes' are fed by the nearer one.
--   * no U-turns, every incoming road lane gets a connection, every outgoing road lane is fed, no
--     two connections of one travel direction cross. Tram connections are kept as the engine made
--     them (Rules.mergeTram).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"

local S = {}

S.STRAIGHT_MAX_DEG = 45 -- through road / main road: at most this far off straight
S.MAX_TURN_DEG = 90     -- a branch belongs to a direction it turns less than this from (slip lanes
                        -- leave at 40-80 deg in the Channelized Junction; the other direction sees
                        -- the same branch at 100-140 deg)
S.MIN_SPLIT_DEG = 5     -- through and branch must differ this much (turn angle and its size)
S.MAX_ROADS = 4

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

--- Through / branch of two candidates {seg, deg}: the smaller turn is the through road.
-- Returns through, branch, branch side relative to the through road ("left"/"right") or nil, why.
local function splitPair(c1, c2)
	local t, b = c1, c2
	if math.abs(c2.deg) < math.abs(c1.deg) then t, b = c2, c1 end
	if math.abs(t.deg) > S.STRAIGHT_MAX_DEG then return nil, nil, nil, "no_through" end
	if math.abs(b.deg) - math.abs(t.deg) < S.MIN_SPLIT_DEG or math.abs(b.deg - t.deg) < S.MIN_SPLIT_DEG then
		return nil, nil, nil, "ambiguous"
	end
	return t, b, (b.deg > t.deg) and "left" or "right"
end

--- The rules' view of node n:
-- { node, kind = "slip" | "none" | "skip", reason, case = "A" | "B", side (driving side when known:
--   "right" | "left"), sideFrom = "two_way" | "branch", roads, streams = { stream... }, shape }
-- stream: { shape, kerb, inSeg/throughSeg/branchSeg/outSeg, m/t/b or p/q/o (kerb-first lanes),
--   deg (branch turn), throughDeg }.
-- shape: "diverge", "merge" or "diverge+merge".
function S.classify(world, n)
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
		v.case, v.sideFrom = "A", "branch"
		if #ins == 1 then
			local c1 = { seg = outs[1], deg = turnDeg(world, n, ins[1], outs[1]) }
			local c2 = { seg = outs[2], deg = turnDeg(world, n, ins[1], outs[2]) }
			local t, b, side, why = splitPair(c1, c2)
			if not t then return skip(v, why) end
			v.streams[1] = makeStream(world, n, { shape = "diverge", kerb = side, inSeg = ins[1],
				throughSeg = t.seg, branchSeg = b.seg, deg = b.deg, throughDeg = t.deg })
		else
			local c1 = { seg = ins[1], deg = turnDeg(world, n, ins[1], outs[1]) }
			local c2 = { seg = ins[2], deg = turnDeg(world, n, ins[2], outs[1]) }
			local t, b, side, why = splitPair(c1, c2)
			if not t then return skip(v, why) end
			-- a branch joining from the right turns right into the road (it heads across the road's
			-- direction towards it), so the turn side is the side it joins from
			v.streams[1] = makeStream(world, n, { shape = "merge", kerb = side, throughSeg = t.seg,
				branchSeg = b.seg, outSeg = outs[1], deg = b.deg, throughDeg = t.deg })
		end
	elseif twoWays == 2 then
		-- case B: two-way main road, one or two one-way branches
		v.case, v.sideFrom = "B", "two_way"
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
			if math.abs(d.deg) > S.STRAIGHT_MAX_DEG then return skip(v, "main_bend") end
		end
		for _, br in ipairs(branches) do
			local leaving = #br.la.outgoing > 0
			local best, bestDeg = nil, nil
			for _, d in ipairs(dirs) do
				local deg
				if leaving then deg = turnDeg(world, n, d.from, br.sid) else deg = turnDeg(world, n, br.sid, d.to) end
				if best == nil or math.abs(deg) < math.abs(bestDeg) then best, bestDeg = d, deg end
			end
			if math.abs(bestDeg) >= S.MAX_TURN_DEG then return skip(v, "branch_turn") end
			if best.branch then return skip(v, "two_branches_one_direction") end
			local t = { seg = best.to, deg = best.deg }
			local b = { seg = br.sid, deg = bestDeg }
			if math.abs(b.deg) - math.abs(t.deg) < S.MIN_SPLIT_DEG or math.abs(b.deg - t.deg) < S.MIN_SPLIT_DEG then
				return skip(v, "ambiguous")
			end
			-- leaving: the branch turns towards its side; joining: it turns towards the side it
			-- comes from as well (heading across the road towards it)
			local side = (b.deg > t.deg) and "left" or "right"
			if side ~= kerb then return skip(v, "far_side_branch") end
			best.branch, best.leaving, best.branchDeg = br.sid, leaving, bestDeg
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
	else
		-- one two-way road and one-way roads: a roundabout splitter's split node (an arm forking
		-- into its exit and entry legs, PHASE6.md: leave it) or a dual carriageway's end. Not a slip
		-- node, and not logged (every splitter roundabout has them).
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
	v.kind = "slip"
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
function S.pairs(shape, a, b, c)
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
			for _, pr in ipairs(S.pairs("diverge", #st.m, #st.t, #st.b)) do
				push(list, seen, segOf[pr.from], lanes[pr.from][pr.i], segOf[pr.to], lanes[pr.to][pr.j])
			end
		else
			segOf = { p = st.throughSeg, q = st.branchSeg, o = st.outSeg }
			lanes = { p = st.p, q = st.q, o = st.o }
			for _, pr in ipairs(S.pairs("merge", #st.p, #st.q, #st.o)) do
				push(list, seen, segOf[pr.from], lanes[pr.from][pr.i], segOf[pr.to], lanes[pr.to][pr.j])
			end
		end
	end
	return list
end

--- Short lane summary of a view: "2 -> 2 + 2" (diverge: main -> through + branch), "2 + 1 -> 2"
-- (merge: through + branch -> out); both streams joined with "; ".
function S.summary(v)
	local parts = {}
	for _, st in ipairs(v.streams or {}) do
		if st.shape == "diverge" then
			parts[#parts + 1] = string.format("%d -> %d + %d slip", #st.m, #st.t, #st.b)
		elseif st.shape == "merge" then
			parts[#parts + 1] = string.format("%d + %d slip -> %d", #st.p, #st.q, #st.o)
		end
	end
	return table.concat(parts, "; ")
end

--- Main road lanes of a view (the largest incoming main-road lane count of a diverge or merge).
function S.mainLanes(v)
	local n = 0
	for _, st in ipairs(v.streams or {}) do
		if st.shape == "diverge" then n = math.max(n, #st.m) end
		if st.shape == "merge" then n = math.max(n, #st.o) end
	end
	return n
end

--- Plans one slip node: { node, view, status = "apply" | "same" | "skip" | "none", reason,
-- before, after, conns }. currentConns(n) -> the node's connections (plain tables).
function S.plan(world, n, currentConns)
	local v = S.classify(world, n)
	local r = { node = n, view = v }
	if v.kind ~= "slip" then
		r.status, r.reason = v.kind, v.reason
		return r
	end
	local cur = currentConns(n) or {}
	local conns = Rules.mergeTram(S.roadConns(v), cur)
	r.before, r.after, r.conns = Rules.roadCount(cur), Rules.roadCount(conns), conns
	if Rules.connsText(conns) == Rules.connsText(cur) then r.status = "same" else r.status = "apply" end
	return r
end

--- Log fields of a planned slip node (APPLY / SKIP lines, kind=slip).
function S.logFields(r)
	local v = r.view
	return { { "kind", "slip" }, { "node", r.node }, { "shape", v.shape or "-" }, { "case", v.case or "-" },
		{ "side", v.side or ("branch_" .. tostring(v.streams[1] and v.streams[1].kerb)) },
		{ "lanes", S.summary(v) }, { "before", r.before }, { "after", r.after } }
end

return S
