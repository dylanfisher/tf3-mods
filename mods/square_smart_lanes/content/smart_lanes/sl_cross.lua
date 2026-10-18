-- Smart Lanes: crossroads and T-junctions (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_cross.lua. sl_slip.lua hands these nodes over (view case "X"), so
-- the automatic pass, the tool, the badge and Reset treat them like slip-lane junctions:
--   * 3 or 4 two-way roads;
--   * two-way roads with one-way roads that are no slip lane: ramp ends meeting the cross road of a
--     diamond or parclo, the carriageways of a divided road crossing a road, one-way streets meeting
--     a two-way street at an angle, a branch on the far side.
-- A road that brings traffic in is an approach, a road that takes it away an exit; turns sharper
-- than MAX_TURN_DEG are no exits (a diamond's off-ramp onto its own on-ramp), unless nothing else is.
-- A ramp (a one-way road without a sidewalk: highway ramps; town one-way streets have sidewalks)
-- never leads into another ramp when a road is there (a parclo's off-ramp straight across onto the
-- on-ramp would leave the highway only to join it again; in game 2026-10-11).
-- Junctions of one-way roads only are left alone: no two-way road tells the driving side.
-- Exit-lane fan (sl_exitfan zones only, a measuring mode; PLAN.md "Exit-lane fan (sl_exitfan zones)"): at a lit
-- node the turns fan over the exit lanes their game phase group leaves them (X.phaseGroups, placeExitLit);
-- lane strings, straights and everything outside such a zone stay exactly as below.
-- Open exits (rev 7, PLAN.md "Open exit lanes near stops and close junctions"; X.openOf, openExit): an exit road
-- with a street stop within X.OPEN_M (80 m) of the node, or whose far end is a junction within X.OPEN_M where its
-- traffic has a choice of ways (X.waysOn; a slip lane's merge node is none), lets the
-- far-side turns into it land in every lane down to the kerb-side lane the movements beside them in the same
-- phase group leave free (a merge at the boundary, never a crossing), so a bus turning across can reach a curb
-- stop or the lane for the next junction without a lane change. Kerb-side turns and straights keep their lanes
-- (a freed kerb turn stays in the kerb lane); unlit / unknown / off the phase model: one group of every movement
-- into the exit. No such road: the connections exactly as below.
--
-- Shallow ramps (X.shallowRamps; in game 2026-10-11: one-way ramps leaving and joining a two-way
-- 3+3 road alongside it, where the crossing rule let the far lane turn across the oncoming
-- carriageway into the ramp on the other side and the joining ramp turn left across the road): a
-- ramp whose direction over its first X.SHALLOW_LOOK.dist m (the chord, not the tangent at the node:
-- in game a ramp that visibly peels off had its tangent 80-100 deg off the road there) is at most
-- X.SHALLOW_MAX_DEG off the line of the node's two-way through road belongs to the travel direction
-- on whose kerb side it lies. An outgoing one is an exit only for that direction's approach; an
-- incoming one only joins that direction's carriageway (into its kerb lanes) or a side road on its
-- own side of the through road. Nothing turns across the opposing carriageway into or out of it, so
-- a shallow ramp on the far side (a left exit in right-hand traffic) would be fed by no through-road
-- approach. Reachability comes first: a blocked move stays when it is the only feed of its exit road
-- (that far-side ramp out keeps the far turn of the approach it leaves), and a joining ramp whose
-- every move is blocked keeps them (logged shallow_kept=<approach>><exit>,...).
-- Ramp ends meeting a road at about a right angle (diamond and parclo terminals, 78-90 deg over the
-- first 50 m in square_roundabouts' Highway Interchange) keep the crossing rule and their left
-- turns; two-way side roads keep it too. sl_slip tries the slip-lane rule (case B) for these nodes
-- first; this is the fallback (a side road at the node, a far-side or backward ramp).
--
-- The engine's default lets most lanes turn everywhere, so turning traffic crosses the lanes of
-- straight traffic inside the junction. This rule gives each lane a contiguous range of exits,
-- ordered from the kerb-side turn to the far-side turn, so no two lanes of one approach cross:
--   * 1 lane: every exit.
--   * 2 lanes: shared lanes. Three exits: kerb lane = kerb turn + straight, far lane = straight +
--     far turn. Two exits: one lane each, and the lane next to a straight exit also goes straight
--     (a main road at a T keeps both lanes for through traffic).
--   * 3 or more lanes: every turn gets its own lane (the kerb lane turns only towards the kerb,
--     the far lane only towards the far side), straight gets the rest; without a straight exit the
--     far turn gets them. With a straight exit the far turn lane goes straight too (3 lanes, straight
--     and far turn: 1 straight, 2 straight, 3 straight + far), so straight traffic keeps every lane
--     but the kerb turn's (in game 2026-10-11: the player's hand edit at a Channelized X centre).
-- Never squeeze lanes inside the junction (X.allocateView; user report 2026-10-11 at
-- square_roundabouts' interchange: "4 lanes turning into 1"): an exit's block of lanes is at most
-- that exit road's lane count; the lanes left over go to the approach's other exits with room
-- (straight, then the far turn, then the kerb turn), and a shared lane (2 lanes, the far lane going
-- straight) only where the straight exit has a lane for it. Where several approaches feed one exit
-- road and their lanes outnumber its lanes, the widest turn block gives lanes back (towards one
-- lane each) to the other exits of its approach that have room, before two movements share an
-- exit lane. Lanes fold only when an approach has more lanes than all its exits together: then
-- where they add the fewest lanes per exit lane, logged squeeze=<approach>:<lanes folded>. Shared
-- exit lanes remain where the exit road is too narrow for every movement into it (a 2x2 crossroads,
-- 1-lane roads) and where the user rules' shared lanes meet turning traffic (a 3x3 crossroads:
-- the far lane's straight share and the far turn from the left); crossroads keep the game's lights.
-- Those extra straight shares (2 lanes: the lane next to the straight exit; 3+ lanes: the far turn
-- lane) stay only where the node has traffic lights (user decision 2026-10-11, "keep where lights
-- exist": the movements run in different phases). At an unlit node (preference NO) a share whose
-- straight exit road has more feeders than lanes is dropped, so the straight movement and the turn
-- from another approach never meet in one exit lane (X.allocateView, logged unshared=). Unknown
-- (preference AUTO and no light yet, or no light read: fixtures) keeps the share, as lit. A light
-- switched on or off later does not rewrite the lanes; the tool's badge then shows them as changed.
-- Within an exit, kerb-side turns enter its kerb lanes (kerb-aligned), far-side turns its far lanes
-- (far-aligned) and straight the lanes next to the far turns: straight traffic from a 3-lane road with a dedicated kerb
-- turn lane leaves the exit's kerb lane free for traffic turning in from the side road (a free
-- kerb-side turn). Where the movements outnumber the lanes, straight shares with the far turns
-- first, and every feeder is spread evenly when that would pile more on a lane than needed.
-- Exit lanes nobody feeds get the nearest feeder of an approach without crossing.
-- "Kerb" is the driving side (right in right-hand traffic), from the two-way roads' lane layout as
-- in sl_slip. Tram connections are kept as the engine made them, and every connection touching a
-- bus-only lane as the game or the player made it (Rules.mergeTram with v.bus, by the caller): the
-- approaches' lanes (ap.m, ex.o) are car lanes only (Ring.lanesAt), so the kerb lane is the kerb car lane.
--
-- Turns a slip lane already serves (X.bypasses; in game 2026-10-11: at square_roundabouts'
-- Channelized X the kerb lanes still turned right at the centre's lights, so right turners queued
-- there and ignored the slip lanes): an exit is bypassed for an approach when a one-way road leaves
-- the approach road upstream (at the junction the bounded walk back from the node stops at, the
-- first neighbour node included) and, followed forward, ends at the junction where the exit road's
-- bounded walk out from the node stops; it must leave and arrive within X.BYPASS_MAX_DEG of the
-- traffic's heading (no U-turn: a roundabout splitter's entry leg, a dual carriageway's other half)
-- and cut the corner (shorter than X.BYPASS_SHORTCUT of the way through the node: a one-way street
-- round a town block is none). Kerb-side and far-side slip lanes and both traffic sides alike; a
-- long loop (a jughandle) is no shortcut and keeps its turn. Bypassed exits are left out of the approach's
-- exits before the lanes are allocated (never the straight exit, never every exit of an approach,
-- never an exit road no other approach still feeds); the slip lane's diverge and merge nodes are
-- slip nodes of their own (sl_slip case B). ap.allExits keeps the full list: X.defaultConns (the
-- game's model for Reset) stays the game's full default.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Walk = ug_require "square_smart_lanes::/smart_lanes/sl_walk.lua"

local X = {}

X.STRAIGHT_MAX_DEG = 45 -- the straight exit: the smallest turn, at most this far off straight
X.MIN_EXIT_DEG = 5      -- two exits of one approach must differ this much
X.MAX_ROADS = 4
X.MAX_TURN_DEG = 135    -- sharper turns are U-turns, not exits (a skewed crossing turns up to ~120)
-- Slip-lane bypasses (X.bypasses): walk caps (m, segments) and the one-way roads examined per node
X.BYPASS_UP = { dist = 200, nodes = 6 }    -- back along the approach road
X.BYPASS_SLIP = { dist = 400, nodes = 10 } -- forward along the one-way road
X.BYPASS_EXIT = { dist = 200, nodes = 6 }  -- out along the exit road
X.BYPASS_MAX_ROADS = 8
-- the one-way road leaves U and reaches J at most this far off the traffic's heading there (Channelized
-- Junction slip lanes: 40-80 deg; a U-turn: 150-180), and is shorter than this share of the way
-- through n (slip lanes cut the corner: chord / (Lm + Ls) <= 0.75; a one-way street round a block: 1)
X.BYPASS_MAX_DEG = 100
X.BYPASS_SHORTCUT = 0.9
-- Shallow ramps (X.shallowRamps): the chord over the ramp's first `dist` m (plain nodes followed, at
-- most `nodes` segments) at most SHALLOW_MAX_DEG off the through road's line. square_roundabouts'
-- terminals: 78-90 deg (diamond S/M/L climb edge, parclo stubs and straight ends: 90); ramps alongside
-- the road: well under 60. A chord within SHALLOW_MIN_SIDE_DEG of the line tells no side: not shallow.
X.SHALLOW_MAX_DEG = 60
X.SHALLOW_LOOK = { dist = 50, nodes = 4 }
X.SHALLOW_MIN_SIDE_DEG = 2
-- Open exits (X.openOf): a street stop or the far end junction at most OPEN_M m along the exit road (sl_audit
-- A.WEAVE_M is this value); the walk out passes at most OPEN_NODES segments, at most OPEN_STOPS stops per segment
X.OPEN_M = 80
X.OPEN_NODES = 8
X.OPEN_STOPS = 16

local atan2 = math.atan2 or math.atan

local function unit(x, y)
	local l = math.sqrt(x * x + y * y)
	if l < 1e-9 then return nil end
	return x / l, y / l
end

--- Unit direction pointing away from `node` along segment s (tangent at that end, else the chord).
local function awayDir(s, node)
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
	local ax, ay = awayDir(world.seg(a), node)
	local hx, hy = -ax, -ay
	local ox, oy = awayDir(world.seg(b), node)
	return math.deg(atan2(hx * oy - hy * ox, hx * ox + hy * oy))
end

local function sideOf(la)
	if #la.incoming == 0 or #la.outgoing == 0 then return nil end
	if la.incoming[#la.incoming] < la.outgoing[1] then return "right" end
	if la.incoming[1] > la.outgoing[#la.outgoing] then return "left" end
	return nil
end

local function kerbFirst(asc, incoming, kerb)
	return Ring.outerFirst(asc, incoming, kerb == "right" and 1 or -1)
end

local function skip(v, reason)
	v.kind, v.reason = "skip", reason
	return v
end

--- Whether road r ({sid, la, twoWay}) is a ramp: a one-way road without a sidewalk (highway ramps;
-- town one-way streets have sidewalks). One test for both rules: Rules.isRampSeg.
function X.isRamp(world, r)
	if r.twoWay then return false end
	return Rules.isRampSeg(world, r.sid)
end

---------------------------------------------------------------------------
-- Shallow ramps

--- Point of segment s's Hermite curve at parameter u (0 = node0); the chord without tangents.
local function hermiteAt(s, u)
	local t0 = s.t0 or { x = s.p1.x - s.p0.x, y = s.p1.y - s.p0.y }
	local t1 = s.t1 or t0
	local u2, u3 = u * u, u * u * u
	local h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
	return h00 * s.p0.x + h10 * t0.x + h01 * s.p1.x + h11 * t1.x, h00 * s.p0.y + h10 * t0.y + h01 * s.p1.y + h11 * t1.y
end

--- Unit chord (pointing away from node n) from n to the point X.SHALLOW_LOOK.dist m along road sid
-- (Walk through plain nodes; `leaving`: traffic leaves n on it), or to where the walk stopped when
-- that comes first. nil when the road is missing or degenerate.
function X.rampChord(world, n, sid, leaving)
	local s0 = sid and world.seg(sid)
	local e = s0 and Ring.endAt(s0, n)
	if e == nil then return nil end
	local o = e == 0 and s0.p0 or s0.p1
	local w = Walk.follow(world, n, sid, { dir = leaving and "out" or "in", maxDist = X.SHALLOW_LOOK.dist, maxNodes = X.SHALLOW_LOOK.nodes })
	local st = w.steps[#w.steps]
	local s = st and world.seg(st.seg)
	if not s or not o then return nil end
	local u = math.min(1, math.max(0, (X.SHALLOW_LOOK.dist - st.at) / math.max(st.len, 1e-6)))
	if s.node0 ~= st.from then u = 1 - u end
	local px, py = hermiteAt(s, u)
	return unit(px - o.x, py - o.y)
end

--- Shallow ramps at node n (see the header) for kerb side `kerb` ("right" | "left"), or nil when the
-- node has no through road (two two-way roads at most STRAIGHT_MAX_DEG off straight both ways; the
-- straightest pair) or no ramp. Returns { a, b (the through road's segments), measured = { "seg:deg"
-- per ramp, the chord's angle off the line }, deg = { [seg] = that angle } (every measured ramp), ramps = { [seg] = { leaving, deg, from, to (the
-- approach and exit segments of the travel direction on whose kerb side it lies), side (+1 left /
-- -1 right of a -> b), forward (its traffic heads along that direction) } } (shallow ramps only),
-- sideOf(seg) (+1 / -1: the side of the line road seg leaves to, 0 on it) }.
function X.shallowRamps(world, n, roads, kerb)
	local hasRamp = false
	for _, r in ipairs(roads) do if X.isRamp(world, r) then hasRamp = true end end
	if not hasRamp then return nil end
	local A, B, best = nil, nil, nil
	for i, a in ipairs(roads) do
		for j = i + 1, #roads do
			local b = roads[j]
			if a.twoWay and b.twoWay then
				local d1, d2 = math.abs(turnDeg(world, n, a.sid, b.sid)), math.abs(turnDeg(world, n, b.sid, a.sid))
				if d1 <= X.STRAIGHT_MAX_DEG and d2 <= X.STRAIGHT_MAX_DEG and (best == nil or d1 + d2 < best) then
					A, B, best = a.sid, b.sid, d1 + d2
				end
			end
		end
	end
	if A == nil then return nil end
	local ax, ay = awayDir(world.seg(A), n)
	local bx, by = awayDir(world.seg(B), n)
	local hx, hy = unit(bx - ax, by - ay) -- heading of traffic from A to B
	if hx == nil then return nil end
	local minSide = math.sin(math.rad(X.SHALLOW_MIN_SIDE_DEG))
	local out = { a = A, b = B, measured = {}, deg = {}, ramps = {} }
	function out.sideOf(sid)
		local x, y = awayDir(world.seg(sid), n)
		local c = hx * y - hy * x
		if math.abs(c) < minSide then return 0 end
		return c > 0 and 1 or -1
	end
	for _, r in ipairs(roads) do
		if X.isRamp(world, r) then
			local leaving = #r.la.outgoing > 0
			local cx, cy = X.rampChord(world, n, r.sid, leaving)
			if cx ~= nil then
				local dt, cr = hx * cx + hy * cy, hx * cy - hy * cx
				local deg = math.deg(math.acos(math.min(1, math.abs(dt))))
				out.measured[#out.measured + 1] = string.format("%d:%.0f", r.sid, deg)
				out.deg[r.sid] = deg
				if deg <= X.SHALLOW_MAX_DEG and math.abs(cr) >= minSide then
					local side = cr > 0 and 1 or -1
					local kerbAB = (side > 0) == (kerb == "left")
					-- dot of the ramp traffic's heading with the a -> b heading
					local along = leaving and dt or -dt
					out.ramps[r.sid] = { leaving = leaving, deg = deg, side = side,
						from = kerbAB and A or B, to = kerbAB and B or A,
						forward = (kerbAB and along > 0) or (not kerbAB and along < 0) }
				end
			end
		end
	end
	return out
end

--- Whether the move a -> b (roads at the node) is left out by the shallow-ramp rule `sh`
-- (X.shallowRamps): it would cross the opposing carriageway into or out of a shallow ramp.
local function shallowBlocked(sh, a, b)
	if sh == nil then return false end
	local through = function(sid) return sid == sh.a or sid == sh.b end
	local rb, ra = sh.ramps[b.sid], sh.ramps[a.sid]
	if rb and rb.leaving and through(a.sid) then return a.sid ~= rb.from end
	if ra and not ra.leaving then
		if through(b.sid) then return b.sid ~= ra.to end
		if b.twoWay then return sh.sideOf(b.sid) ~= ra.side end
	end
	return false
end
X.shallowBlocked = shallowBlocked -- sl_audit.lua: moves across the opposing carriageway

---------------------------------------------------------------------------
-- The rule on counts

--- Exit range of every lane: N incoming lanes (1 = kerb), cats = exit categories ordered kerb-side
-- turn first ("kerb" | "straight" | "far"). Returns { [lane] = { lo, hi } } (exit indices), squeeze.
-- caps (optional, X.allocateView): per exit the most incoming lanes that may feed it (its outgoing
-- lanes, less what other approaches need); default no limit (the rule on counts alone). A block
-- never outgrows its cap: the lanes left over go to the exits with room, straight first, then the
-- far turns, then the kerb turns, and a lane shares into its neighbour exit only within that exit's
-- cap. Only when N exceeds the caps' total do lanes fold (squeeze: the lanes over it, else 0): the
-- excess goes where it adds the fewest lanes per exit lane (ties: the widest exit).
-- noShare (X.allocateView at an unlit node): no extra straight share (the 2-lane neighbour of the
-- straight lane, the 3+ lane far turn lane). Third result: the lane given that extra straight share,
-- else nil (a share of fewer lanes than exits, [1,2] [2,3], is no extra one).
function X.allocate(N, cats, caps, noShare)
	local k = #cats
	local res = {}
	if N <= 0 or k == 0 then return res, 0 end
	local function cap(e) return caps and caps[e] or math.huge end
	if N == 1 then
		res[1] = { 1, k }
		return res, 0
	end
	if N < k then
		-- fewer lanes than exits: overlapping ranges ([1,2], [2,3] for 2 lanes and 3 exits); a shared
		-- exit over its cap is dropped by the kerb-side lane first (the far lane keeps going straight)
		for i = 1, N do
			res[i] = { 1 + math.floor((i - 1) * k / N), math.ceil(i * k / N) }
		end
		for e = 1, k do
			local f = 0
			for i = 1, N do if res[i][1] <= e and e <= res[i][2] then f = f + 1 end end
			for i = 1, N do
				if f > cap(e) and res[i][2] == e and res[i][1] < e then res[i][2], f = e - 1, f - 1 end
			end
			for i = N, 1, -1 do
				if f > cap(e) and res[i][1] == e and res[i][2] > e then res[i][1], f = e + 1, f - 1 end
			end
		end
		return res, 0
	end
	local st = nil
	for i, c in ipairs(cats) do if c == "straight" then st = i end end
	-- every exit one lane; the rest by priority up to the caps: straight, far turns (the farthest
	-- first), kerb turns (the one nearest straight first)
	local size, order = {}, {}
	for i = 1, k do size[i] = 1 end
	if st then order[1] = st end
	for e = k, 1, -1 do if cats[e] == "far" then order[#order + 1] = e end end
	for e = k, 1, -1 do if cats[e] == "kerb" then order[#order + 1] = e end end
	local left = N - k
	for _, e in ipairs(order) do
		local add = math.min(left, math.max(0, cap(e) - size[e]))
		size[e], left = size[e] + add, left - add
	end
	local squeeze = left
	while left > 0 do
		-- unavoidable fold: fewest lanes per exit lane, then the widest exit, then the priority order
		local best, bestQ = nil, nil
		for _, e in ipairs(order) do
			local q = (size[e] + 1) / cap(e)
			if best == nil or q < bestQ - 1e-9 or (math.abs(q - bestQ) <= 1e-9 and cap(e) > cap(best)) then best, bestQ = e, q end
		end
		size[best], left = size[best] + 1, left - 1
	end
	local lane = 1
	for e = 1, k do
		for _ = 1, size[e] do
			res[lane] = { e, e }
			lane = lane + 1
		end
	end
	local extra = nil
	if st ~= nil and squeeze == 0 and not noShare then
		local first, last = lane, 0
		for i = 1, N do
			if res[i][1] == st then
				first = math.min(first, i)
				last = math.max(last, i)
			end
		end
		local room = size[st] < cap(st)
		if N == 2 then
			-- two lanes: the neighbours of the straight lane go straight too
			-- (with k == 2 only one of them exists)
			if room and first > 1 then res[first - 1][2], extra = st, first - 1 end
			if room and last < N then res[last + 1][1], extra = st, last + 1 end
		elseif room and last < N then
			-- the far turn lane goes straight too (in game 2026-10-11, the player's hand edit at a
			-- Channelized X: straight keeps every lane but the kerb turn's)
			res[last + 1][1], extra = st, last + 1
		end
	end
	return res, squeeze, extra
end

--- Pairs {f, o} (feeder position among the r feeders, exit lane) of r feeders into M exit lanes.
-- kerbSide: align from the kerb (kerb-side turns), else from the far side; extra feeders fold into
-- the last lane on the aligned side's opposite end.
function X.mapLanes(r, M, kerbSide)
	local out = {}
	if r == 0 or M == 0 then return out end
	local k = math.min(r, M)
	if kerbSide then
		for d = 1, k do out[#out + 1] = { d, d } end
		for d = k + 1, r do out[#out + 1] = { d, M } end
	else
		for d = 0, k - 1 do out[#out + 1] = { r - d, M - d } end
		for d = 1, r - k do out[#out + 1] = { d, 1 } end
	end
	return out
end

--- Pairs {f, t} of r feeders into w exit lanes as X.mapLanes, but more feeders than lanes spread
-- evenly (fewest feeders per lane; the extra ones on the aligned side, away from the other
-- movements into that exit road).
local function spreadLanes(r, w, kerbSide)
	if r <= w then return X.mapLanes(r, w, kerbSide) end
	local q, x = math.floor(r / w), r % w
	local out, f = {}, 1
	for t = 1, w do
		local extra = (kerbSide and t <= x) or (not kerbSide and t > w - x)
		for _ = 1, q + (extra and 1 or 0) do
			out[#out + 1] = { f, t }
			f = f + 1
		end
	end
	return out
end

--- Exit lanes of the movements into one exit road of M lanes: sets mv.map = { {f, lane} } per
-- movement mv = { r (its feeders), group = "kerb" | "straight" | "far", kd (turn, kerb side
-- negative) }. Kerb-side turns (and a shallow ramp joining as a merge) fill from the kerb lane,
-- far-side turns from the far lane, straight sits next to the far turns (far-aligned). More feeders
-- than lanes: straight shares with the far turns before it takes the kerb turns' lanes (the kerb
-- lane stays free for a free turn); when that piles more feeders on a lane than ceil(feeders /
-- lanes), every feeder is spread evenly over the lanes instead, in kerb-to-far order.
local GROUP_RANK = { kerb = 1, straight = 2, far = 3 }
local function byGroupTurn(p, q)
	if p.group ~= q.group then return GROUP_RANK[p.group] < GROUP_RANK[q.group] end
	if p.kd ~= q.kd then return p.kd < q.kd end
	return p.ap.seg < q.ap.seg
end

local function placeExit(mvs, M)
	local groups = { kerb = {}, straight = {}, far = {} }
	table.sort(mvs, byGroupTurn)
	local sum = { kerb = 0, straight = 0, far = 0 }
	for _, mv in ipairs(mvs) do
		local g = groups[mv.group]
		g[#g + 1] = mv
		sum[mv.group] = sum[mv.group] + mv.r
	end
	local pos = 1
	for _, mv in ipairs(groups.kerb) do
		mv.lo, mv.hi = pos, pos + mv.r - 1
		pos = mv.hi + 1
	end
	pos = M
	for i = #groups.far, 1, -1 do
		local mv = groups.far[i]
		mv.lo, mv.hi = pos - mv.r + 1, pos
		pos = mv.lo - 1
	end
	local S = sum.straight
	pos = math.max(M - sum.far - S + 1, sum.kerb + 1)
	if pos + S - 1 > M then pos = M - S + 1 end
	for _, mv in ipairs(groups.straight) do
		mv.lo, mv.hi = pos, pos + mv.r - 1
		pos = mv.hi + 1
	end
	local load, most, T = {}, 0, 0
	for _, mv in ipairs(mvs) do
		-- into 1..M (a block wider than the road keeps every lane: folded)
		local w = math.min(mv.r, M)
		if mv.lo < 1 then mv.lo, mv.hi = 1, w end
		if mv.hi > M then mv.lo, mv.hi = M - w + 1, M end
		mv.map = {}
		for _, p in ipairs(spreadLanes(mv.r, mv.hi - mv.lo + 1, mv.group == "kerb")) do
			local t = p[2] + mv.lo - 1
			mv.map[#mv.map + 1] = { p[1], t }
			load[t] = (load[t] or 0) + 1
			most = math.max(most, load[t])
		end
		T = T + mv.r
	end
	if most <= math.max(1, math.ceil(T / M)) then return end
	-- every feeder in kerb-to-far order onto the lanes, evenly (slot t of T onto lane ceil(t * M / T))
	local t = 0
	for _, mv in ipairs(mvs) do
		mv.map = {}
		for f = 1, mv.r do
			t = t + 1
			mv.map[#mv.map + 1] = { f, math.ceil(t * M / T) }
		end
	end
end

--- Lane blocks of r feeders over w exit lanes without crossing and without two feeders of one
-- movement in one lane: one feeder takes every lane; r <= w: contiguous blocks in order, the lanes
-- left over to the feeder at the aligned end (group "far": the far-most, else the kerb-most; the
-- game's own 3x3 turns, findings roads.md "The game's default crossroads connections vary per
-- approach"); r > w: folded as placeExit does (spreadLanes, kerb-aligned only for kerb turns).
-- Returns pairs {f, t}.
local function fanBlocks(r, w, group)
	if r > w then return spreadLanes(r, w, group == "kerb") end
	local kerbSide = group ~= "far"
	local out = {}
	local base, x = math.floor(w / r), w % r
	local t = 1
	for f = 1, r do
		local size = base
		if (kerbSide and f <= x) or (not kerbSide and f > r - x) then size = size + 1 end
		for _ = 1, size do
			out[#out + 1] = { f, t }
			t = t + 1
		end
	end
	return out
end

--- Exit lanes of the movements of ONE phase group into one exit road of M lanes (v.exitFan: the
-- movements green together under the game's phases; X.phaseGroups). Ordered kerb-side turn, straight,
-- far-side turn (byGroupTurn), movement i gets a contiguous range of exit lanes and neighbours share
-- exactly one lane at their boundary (a merge, as the game's own default has, but never a crossing: a
-- kerb-side movement never reaches a lane farther out than the far-side one beside it), so every turn
-- may pick between several exit lanes: 2 lanes = kerb turn 1-2, far turn 2; 3 = 1-2 / 2-3; 4 = 1-3 /
-- 3-4; one movement alone takes every lane. A movement of several feeders first gets as many lanes as
-- it has feeders (no fold where the road has room); the spare lanes go round robin from the kerb side,
-- so the kerb-side movement gets the larger share (it does not cross the opposing straight; its kerb
-- lane is the one a free kerb turn may use in other phases).
-- Fewer lanes than movements: overlapping ranges (a 1-lane exit: every movement into lane 1). Sets
-- mv.map = { {f, lane} } (fanBlocks within the range: a 1-feeder turn fans into its whole range; a
-- straight movement maps lane to lane from the far side as X.mapLanes).
local function placeExitLit(mvs, M)
	table.sort(mvs, byGroupTurn)
	local g = #mvs
	local lo, hi = {}, {}
	if g == 1 then
		lo[1], hi[1] = 1, M
	elseif M >= g then
		-- widths over M + g - 1 lane slots (one shared lane per neighbour pair): every movement one lane,
		-- then lanes up to its feeders (no fold where the road has room), then the spare ones, round
		-- robin from the kerb side
		local w, left = {}, M - 1
		for i = 1, g do w[i] = 1 end
		local grew = true
		while left > 0 and grew do
			grew = false
			for i = 1, g do
				if left > 0 and w[i] < mvs[i].r then w[i], left, grew = w[i] + 1, left - 1, true end
			end
		end
		while left > 0 do
			for i = 1, g do
				if left > 0 then w[i], left = w[i] + 1, left - 1 end
			end
		end
		local pos = 1
		for i = 1, g do
			lo[i], hi[i] = pos, pos + w[i] - 1
			pos = hi[i]
		end
	else
		for i = 1, g do
			lo[i] = 1 + math.floor((i - 1) * M / g)
			hi[i] = math.max(lo[i], math.ceil(i * M / g))
		end
	end
	for i, mv in ipairs(mvs) do
		mv.lo, mv.hi = lo[i], hi[i]
		mv.map = {}
		-- straight keeps today's lane-to-lane mapping from the far side (an exit lane it leaves is filled
		-- as everywhere, X.roadConns): the exit's kerb lane stays for a kerb turn freed in that phase
		local w = hi[i] - lo[i] + 1
		local list = mv.group == "straight" and X.mapLanes(mv.r, w, false) or fanBlocks(mv.r, w, mv.group)
		for _, p in ipairs(list) do
			mv.map[#mv.map + 1] = { p[1], p[2] + lo[i] - 1 }
		end
	end
end
X.placeExitLit = placeExitLit -- tests

--- The extra connections of an open exit road (v.open, X.openExits) of M lanes, once its movements are placed
-- and its unfed lanes filled (X.roadConns: `pairs` in placeExit's order, kerb-side turn, straight, far-side turn,
-- each { ap, feeders, map = { {f, lane} }, extra = the fill-in's { {f, lane} } or nil, group }). Each far-side turn
-- widens kerb-ward down to the highest lane any movement before it in the same group lands in, and out to the
-- lowest lane any later one lands in (a merge at the boundary lane, never a crossing); its kerb-most feeder takes
-- the new lanes below, its far-most feeder the ones above (no crossing within the approach). Kerb-side turns and
-- straights keep their connections. groupOf: phase group per approach seg (the game's axis phases at a lit node,
-- X.phaseGroupMap), nil: one group of every movement (unlit, unknown, off the model).
-- Returns { { pr = pair, f = feeder index, lane = exit lane position } } in order.
local function openExit(pairs_, M, groupOf)
	local function gid(pr)
		if groupOf == nil then return 0 end
		return groupOf[pr.ap.seg] or pr.ap.seg
	end
	local added = {} -- pair -> its new { {f, lane} } (later far turns see them: no crossing between two)
	local function span(pr)
		local lo, hi, fLo, fHi = nil, nil, nil, nil
		for _, list in ipairs({ pr.map or {}, pr.extra or {}, added[pr] or {} }) do
			for _, p in ipairs(list) do
				if lo == nil or p[2] < lo or (p[2] == lo and p[1] < fLo) then lo, fLo = p[2], p[1] end
				if hi == nil or p[2] > hi or (p[2] == hi and p[1] > fHi) then hi, fHi = p[2], p[1] end
			end
		end
		return lo, hi, fLo, fHi
	end
	local out = {}
	for i, pr in ipairs(pairs_) do
		local lo, hi, fLo, fHi = span(pr)
		if pr.group == "far" and lo ~= nil then
			local floor, ceil = 1, M
			for j, o in ipairs(pairs_) do
				if j ~= i and gid(o) == gid(pr) then
					local olo, ohi = span(o)
					if olo ~= nil then
						if j < i and ohi > floor then floor = ohi end
						if j > i and olo < ceil then ceil = olo end
					end
				end
			end
			local mine = {}
			for t = math.min(lo, floor), lo - 1 do mine[#mine + 1] = { fLo, t } end
			for t = hi + 1, math.max(hi, ceil) do mine[#mine + 1] = { fHi, t } end
			added[pr] = mine
			for _, p in ipairs(mine) do out[#out + 1] = { pr = pr, f = p[1], lane = p[2] } end
		end
	end
	return out
end
X.openExit = openExit -- tests

X.MAX_REDUCE = 100 -- X.allocateView: turn-block reductions tried per node (bounded work)

--- Feeders of every exit of approach ap (lanes whose range covers it).
local function feedCounts(ap)
	local f = {}
	for e = 1, #ap.exits do
		local n = 0
		for l = 1, #ap.m do
			local r = ap.lanes[l]
			if r and r[1] <= e and e <= r[2] then n = n + 1 end
		end
		f[e] = n
	end
	return f
end

--- Lane ranges (ap.lanes) of every approach of case X view v: never squeeze lanes inside the
-- junction (user report 2026-10-11, square_roundabouts interchange: "4 lanes turning into 1").
-- Each approach first on its own (X.allocate, every exit capped at its outgoing lanes). Then, while
-- an exit road gets more feeders than it has lanes, its widest turn block (kerb or far, more than one
-- lane) gives a lane back: that approach is allocated again with the turn one lane smaller and the
-- other exits capped at their feeders plus their road's spare lanes, so the lane goes where there
-- is room (straight, far, kerb). A reduction that would fold lanes is not made (two movements
-- sharing exit lanes then, as at a 2x2 crossroads under lights). Straight blocks and the user rules'
-- shared lanes stay. Sets ap.squeeze (lanes folded on the approach's own) and v.squeeze =
-- { "approach seg:folded lanes" }.
-- Unlit nodes (v.lit == false, user decision 2026-10-11 "keep where lights exist"): an approach's
-- extra straight share (X.allocate's third result) whose straight exit road gets more feeders than
-- it has lanes is dropped first (ap.noShare; v.unshared = { approach seg }), before any turn block
-- gives a lane back: without lights the straight movement and a turn from another approach would
-- meet in one exit lane at the same time. Lit and unknown nodes (v.lit true / nil) keep the share:
-- under lights the two movements run in different phases.
function X.allocateView(v)
	local aps = v.approaches or {}
	local caps, cats = {}, {}
	for i, ap in ipairs(aps) do
		caps[i], cats[i] = {}, {}
		for e, ex in ipairs(ap.exits) do caps[i][e], cats[i][e] = #ex.o, ex.cat end
		ap.noShare = nil
		ap.lanes, ap.squeeze, ap.extra = X.allocate(#ap.m, cats[i], caps[i])
		ap.usedCaps = caps[i]
	end
	v.unshared = {}
	local unlit = v.lit == false
	local tried = {}
	for _ = 1, X.MAX_REDUCE do
		local feeds, demand, width = {}, {}, {}
		for i, ap in ipairs(aps) do
			feeds[i] = feedCounts(ap)
			for e, ex in ipairs(ap.exits) do
				demand[ex.seg] = (demand[ex.seg] or 0) + feeds[i][e]
				width[ex.seg] = #ex.o
			end
		end
		-- unlit: an extra straight share into an exit road that is over its lanes goes first (once per
		-- approach: allocated again under the caps its lanes came from, without the share)
		local di = nil
		if unlit then
			for i, ap in ipairs(aps) do
				if di == nil and ap.extra ~= nil then
					for _, ex in ipairs(ap.exits) do
						if ex.cat == "straight" and demand[ex.seg] > width[ex.seg] then di = i end
					end
				end
			end
		end
		local bi, be, bf = nil, nil, 1
		if di == nil then
			-- an approach that folds on its own (ap.squeeze > 0) folds again under smaller caps: never a candidate
			for i, ap in ipairs(aps) do
				if ap.squeeze == 0 then
					for e, ex in ipairs(ap.exits) do
						local f = feeds[i][e]
						if ex.cat ~= "straight" and f > bf and demand[ex.seg] > width[ex.seg] and not tried[i .. ":" .. e] then
							bi, be, bf = i, e, f
						end
					end
				end
			end
		end
		if di ~= nil then
			local ap = aps[di]
			ap.noShare = true
			ap.lanes, ap.squeeze, ap.extra = X.allocate(#ap.m, cats[di], ap.usedCaps, true)
			v.unshared[#v.unshared + 1] = ap.seg
			tried = {}
		else
			if bi == nil then break end
			local ap = aps[bi]
			local nc, room = {}, 0
			for e, ex in ipairs(ap.exits) do
				if e == be then nc[e] = bf - 1
				else nc[e] = math.min(caps[bi][e], feeds[bi][e] + math.max(0, width[ex.seg] - demand[ex.seg])) end
				room = room + nc[e]
			end
			-- X.allocate folds exactly when the lanes outnumber the caps' total: skip that call
			local res, sq, extra = nil, 1, nil
			if room >= #ap.m then res, sq, extra = X.allocate(#ap.m, cats[bi], nc, ap.noShare) end
			if sq > 0 then
				tried[bi .. ":" .. be] = true
			else
				ap.lanes, ap.extra, ap.usedCaps, caps[bi][be] = res, extra, nc, nc[be]
				tried = {}
			end
		end
	end
	table.sort(v.unshared)
	v.squeeze = {}
	for _, ap in ipairs(aps) do
		if ap.squeeze > 0 then v.squeeze[#v.squeeze + 1] = ap.seg .. ":" .. ap.squeeze end
	end
end

---------------------------------------------------------------------------
-- Slip-lane bypasses

--- Heading (unit) of traffic leaving `node` along segment sid, or nil (missing / degenerate).
local function headingFrom(world, sid, node)
	local s = sid and world.seg(sid)
	if not s or Ring.endAt(s, node) == nil then return nil end
	local x, y = awayDir(s, node)
	if x == 0 and y == 0 then return nil end
	return x, y
end

--- Whether two headings differ by at most X.BYPASS_MAX_DEG (nil headings: no).
local function near(ax, ay, bx, by)
	if ax == nil or bx == nil then return false end
	return math.deg(math.abs(atan2(ax * by - ay * bx, ax * bx + ay * by))) <= X.BYPASS_MAX_DEG
end

--- One-way roads leaving approach road `aSeg` upstream of node n, at the junction U where the walk back
-- from n stops: list of { node = J (the junction the road ends at), hx, hy (heading arriving at J),
-- len, up (m from n back to U) }. Only roads that leave U forwards (the heading towards n within
-- X.BYPASS_MAX_DEG: no U-turn at U, e.g. a roundabout splitter's entry leg or a dual carriageway's
-- other half). budget.left: one-way roads still to follow at this node (decremented); memo: per
-- "U:seg" the road's result (two approaches sharing U follow it once).
local function bypassEnds(world, n, aSeg, budget, memo)
	local ends = {}
	local up = Walk.follow(world, n, aSeg, { dir = "in", maxDist = X.BYPASS_UP.dist, maxNodes = X.BYPASS_UP.nodes })
	-- plain nodes have no other road: only the junction the walk stops at (the first neighbour included)
	local U, last = up.node, Walk.lastSeg(up)
	if up.stop ~= "junction" or U == nil or U == n or last == nil then return ends end
	local roads = Walk.roadSegs(world, U)
	if not roads then return ends end
	local tx, ty = headingFrom(world, last, U) -- the approach's traffic at U, heading towards n
	for _, r in ipairs(roads) do
		if r.sid ~= last and #r.la.incoming == 0 and #r.la.outgoing > 0 then
			local key = U .. ":" .. r.sid
			local e = memo[key]
			if e == nil then
				e = false
				if near(tx, ty, headingFrom(world, r.sid, U)) then
					if budget.left <= 0 then return ends end
					budget.left = budget.left - 1
					local w = Walk.follow(world, U, r.sid, { dir = "out", maxDist = X.BYPASS_SLIP.dist, maxNodes = X.BYPASS_SLIP.nodes })
					if w.stop == "junction" and w.node ~= nil and w.node ~= n then
						local hx, hy = headingFrom(world, Walk.lastSeg(w), w.node)
						if hx ~= nil then e = { node = w.node, hx = -hx, hy = -hy, len = w.dist } end
					end
				end
				memo[key] = e
			end
			if e then ends[#ends + 1] = { node = e.node, hx = e.hx, hy = e.hy, len = e.len, up = up.dist } end
		end
	end
	return ends
end

--- Bypassed exits of node n: { [approach seg] = { [exit seg] = true } } over the approaches (each
-- { seg, exits = { { seg } } }), see the header. A one-way road from U bypasses an exit when it ends at
-- the junction J where the exit road's walk out stops, arrives there heading within X.BYPASS_MAX_DEG
-- of the exit road's traffic (no U-turn at J), and is a shortcut: shorter than X.BYPASS_SHORTCUT times
-- the way through n (U to n plus n to J). A one-way street around a town block (as long as the way
-- through n) is no bypass. Bounded: one walk per approach and per exit road (at most X.BYPASS_UP /
-- X.BYPASS_EXIT), at most X.BYPASS_MAX_ROADS one-way roads followed (X.BYPASS_SLIP), none twice.
function X.bypasses(world, n, approaches)
	local out = {}
	local budget, memo = { left = X.BYPASS_MAX_ROADS }, {}
	local exitEnd = {} -- exit seg -> { node = J, hx, hy (heading arriving at J), len } or false
	for _, ap in ipairs(approaches) do
		local ends = bypassEnds(world, n, ap.seg, budget, memo)
		if #ends > 0 then
			for _, ex in ipairs(ap.exits) do
				local x = exitEnd[ex.seg]
				if x == nil then
					x = false
					local w = Walk.follow(world, n, ex.seg, { dir = "out", maxDist = X.BYPASS_EXIT.dist, maxNodes = X.BYPASS_EXIT.nodes })
					if w.stop == "junction" and w.node ~= nil then
						local hx, hy = headingFrom(world, Walk.lastSeg(w), w.node)
						if hx ~= nil then x = { node = w.node, hx = -hx, hy = -hy, len = w.dist } end
					end
					exitEnd[ex.seg] = x
				end
				if x then
					for _, e in ipairs(ends) do
						if e.node == x.node and near(e.hx, e.hy, x.hx, x.hy)
							and e.len < X.BYPASS_SHORTCUT * (e.up + x.len) then
							out[ap.seg] = out[ap.seg] or {}
							out[ap.seg][ex.seg] = true
						end
					end
				end
			end
		end
	end
	return out
end

--- Leaves the bypassed exits out of the approaches' exit lists (ap.allExits keeps every exit): not
-- the straight exit, not every exit of an approach, not an exit road no other approach still feeds.
-- Returns the "approach>exit" pairs removed, sorted.
local function dropBypassed(approaches, by)
	local drop = {} -- [ap seg][exit seg] = true: bypassed, to remove
	for _, ap in ipairs(approaches) do
		local b = by[ap.seg]
		if b then
			local k, left = {}, 0
			for _, ex in ipairs(ap.exits) do
				if b[ex.seg] and ex.cat ~= "straight" then k[ex.seg] = true else left = left + 1 end
			end
			if left > 0 and next(k) ~= nil then drop[ap.seg] = k end
		end
	end
	-- every exit road keeps at least one approach feeding it at the node
	local fed = {}
	for _, ap in ipairs(approaches) do
		for _, ex in ipairs(ap.exits) do
			if not (drop[ap.seg] and drop[ap.seg][ex.seg]) then fed[ex.seg] = true end
		end
	end
	local removed = {}
	for _, ap in ipairs(approaches) do
		local k = drop[ap.seg]
		if k then
			local list = {}
			for _, ex in ipairs(ap.exits) do
				if k[ex.seg] and fed[ex.seg] then
					removed[#removed + 1] = ap.seg .. ">" .. ex.seg
				else
					list[#list + 1] = ex
				end
			end
			ap.exits = list
		end
	end
	table.sort(removed)
	return removed
end

---------------------------------------------------------------------------
-- Classification

--- Whether node n has traffic lights: world.lit(n) when the world has it (sl_write makeWorld:
-- sl_lights L.litOf, true = lit, false = unlit, nil = unknown), else nil (unknown: fixtures).
function X.litOf(world, n)
	if type(world.lit) ~= "function" then return nil end
	local ok, lit = pcall(world.lit, n)
	if ok and (lit == true or lit == false) then return lit end
	return nil
end

--- Whether node n lies in an sl_exitfan zone (sl_zones.lua; sl_write makeWorld world.exitFan): a
-- measuring mode for twins (PLAN.md "Exit-lane fan (sl_exitfan zones)"), true / false, or nil when the
-- world does not tell (fixtures). Everywhere else the rule's lanes stay exactly as they are.
function X.exitFanOf(world, n)
	if type(world.exitFan) ~= "function" then return nil end
	local ok, g = pcall(world.exitFan, n)
	if ok and (g == true or g == false) then return g end
	return nil
end

--- The game's phase groups at a lit crossroads / T-junction (measured in game 2026-10-12, findings
-- roads.md "Default traffic light phases": one phase greens both approaches of an axis, every movement
-- of them; a T's main road is one phase, its side road another). Two approaches form an axis when each
-- is the other's straight exit (ap.allExits cat "straight"). Sets v.phaseGroup = { [approach seg] =
-- group id (the smaller seg of the pair, or its own) } and returns true, or false and the reason the
-- node does not fit the model (then the rule's lanes as before): not every road two-way with traffic
-- in and out ("one_way"), a crossroads without two axes ("x_axes"), a T without its main road ("t_axis").
function X.phaseGroups(v, roads)
	local group, why = X.phaseGroupMap(v, roads)
	if group == nil then return false, why end
	v.phaseGroup = group
	return true
end

--- X.phaseGroups without touching the view: the group map, or nil and the reason.
function X.phaseGroupMap(v, roads)
	local aps = v.approaches or {}
	for _, r in ipairs(roads or {}) do
		if not r.twoWay then return nil, "one_way" end
	end
	if #aps ~= #(roads or {}) then return nil, "one_way" end
	local straightOf = {}
	for _, ap in ipairs(aps) do
		for _, ex in ipairs(ap.allExits or ap.exits or {}) do
			if ex.cat == "straight" then straightOf[ap.seg] = ex.seg end
		end
	end
	local group, axes = {}, 0
	for _, ap in ipairs(aps) do
		local o = straightOf[ap.seg]
		if o ~= nil and straightOf[o] == ap.seg then
			group[ap.seg] = math.min(ap.seg, o)
			if ap.seg < o then axes = axes + 1 end
		else
			group[ap.seg] = ap.seg
		end
	end
	if #aps == 4 and axes ~= 2 then return nil, "x_axes" end
	if #aps == 3 and axes ~= 1 then return nil, "t_axis" end
	if #aps ~= 3 and #aps ~= 4 then return nil, "roads" end
	return group
end

local function finite(x) return type(x) == "number" and x == x and x > -math.huge and x < math.huge end

--- Distance (m from the walk's start node) of a stop on walk step st (segment s): projected onto the step's
-- chord from the stop's position (stop.x / stop.y: EdgeObject transf, direction-free), else its param along
-- the segment (0 at node0: EdgeObject.param, the direction inferred from the tealdef), else the step's far end
-- (unknown: the farthest it can be on this segment).
local function stopDist(s, st, stop)
	local len = st.len or 0
	local along = nil
	local a, b = s.p0, s.p1
	if st.from ~= s.node0 then a, b = s.p1, s.p0 end
	if finite(stop.x) and finite(stop.y) and a and b and finite(a.x) and finite(a.y) and finite(b.x) and finite(b.y) then
		local dx, dy = b.x - a.x, b.y - a.y
		local c2 = dx * dx + dy * dy
		if c2 > 1e-6 then
			local t = ((stop.x - a.x) * dx + (stop.y - a.y) * dy) / c2
			if t < 0 then t = 0 elseif t > 1 then t = 1 end
			along = t * len
		end
	end
	if along == nil and finite(stop.param) and stop.param >= 0 and stop.param <= 1 then
		along = (st.from == s.node0) and stop.param * len or (1 - stop.param) * len
	end
	if along == nil then along = len end
	return (st.at or 0) + along
end
X.stopDist = stopDist -- tests

--- Whether exit road sid of node n is open (see the header): "stop" (a street stop at most X.OPEN_M m along
-- it: world.stops(seg) -> { {x, y, param} ... }, sl_write; a world without it has none), "near" (the walk
-- out through plain nodes ends at a junction at most X.OPEN_M m away where its traffic has 2+ ways on:
-- X.waysOn), or nil; plus the distance (m).
-- Bounded: one walk of at most X.OPEN_NODES segments, X.OPEN_STOPS stops per segment.
function X.openOf(world, n, sid)
	local w = Walk.follow(world, n, sid, { dir = "out", maxDist = X.OPEN_M, maxNodes = X.OPEN_NODES })
	if type(world.stops) == "function" then
		for _, st in ipairs(w.steps) do
			if st.at > X.OPEN_M then break end
			local s = world.seg(st.seg)
			local ok, list = pcall(world.stops, st.seg)
			if s and ok and type(list) == "table" then
				for i, stop in ipairs(list) do
					if i > X.OPEN_STOPS then break end
					if type(stop) == "table" then
						local d = stopDist(s, st, stop)
						if d <= X.OPEN_M then return "stop", d end
					end
				end
			end
		end
	end
	local jd = Walk.junctionDist(w)
	if jd ~= nil and jd <= X.OPEN_M and X.waysOn(world, w.node, Walk.lastSeg(w)) >= 2 then return "near", jd end
	return nil
end

--- Ways on for traffic arriving at junction J on segment a: J's road segments other than a with lanes leaving J,
-- at most X.MAX_TURN_DEG off straight (no U-turn). A slip lane's merge node (one way on) is no lane choice.
function X.waysOn(world, J, a)
	if J == nil or a == nil then return 0 end
	local roads = Walk.roadSegs(world, J)
	local k = 0
	for _, r in ipairs(roads or {}) do
		if r.sid ~= a and #r.la.outgoing > 0 and world.seg(a) ~= nil
			and math.abs(turnDeg(world, J, a, r.sid)) <= X.MAX_TURN_DEG then
			k = k + 1
		end
	end
	return k
end

--- The open exits of a classified case X view (X.classify; not in an sl_exitfan zone): exit roads a far-side
-- turn leads into (the only movements the open rule changes) that X.openOf finds open. Sets v.open = { [seg] =
-- "stop" | "near" }, v.openList = { "seg:why" } (roads order) and v.openGroup (phase group per approach at a
-- lit node on the game's axis model, else nil: one group of every movement into the exit), or leaves them nil.
function X.openExits(world, n, roads, v)
	local far = {}
	for _, ap in ipairs(v.approaches or {}) do
		for _, ex in ipairs(ap.exits or {}) do
			if ex.cat == "far" and ex.kerbAlign ~= true then far[ex.seg] = true end
		end
	end
	for _, r in ipairs(roads) do
		if far[r.sid] then
			local why = X.openOf(world, n, r.sid)
			if why ~= nil then
				v.open = v.open or {}
				v.openList = v.openList or {}
				v.open[r.sid] = why
				v.openList[#v.openList + 1] = tostring(r.sid) .. ":" .. why
			end
		end
	end
	if v.open ~= nil and v.lit == true then v.openGroup = X.phaseGroupMap(v, roads) end
end

--- The lit state for the log: "yes" | "no" | "unknown".
function X.litName(lit)
	if lit == true then return "yes" end
	if lit == false then return "no" end
	return "unknown"
end

--- View of node n whose road segments (`roads`: {sid, la, twoWay}) are all two-way:
-- { kind = "slip" | "skip", case = "X", side, shape = "crossroads" | "t_junction", roads,
--   approaches = { { seg, m = {kerb-first in lanes}, exits = { { seg, deg, cat, o } kerb first },
--   allExits = every exit (ap.exits: without the bypassed and the shallow-blocked ones), lanes =
--   X.allocate result } }, bypassed = { "approach seg>exit seg" ... } turns left to a slip lane
--   (X.bypasses), shallowBlocked = { "approach seg>exit seg" ... } moves across the opposing
--   carriageway into or out of a shallow ramp (X.shallowRamps), shallowKept = { "approach seg>exit
--   seg" ... } such moves kept as their exit road's only feed or the ramp's only way on, rampDeg = { "seg:deg" } the ramps'
--   chord angles off the through road (nil: no through road or no ramp), bypassMap = X.bypasses result (every
--   bypassed approach > exit, also the ones kept), lit = X.litOf (true / false / nil: unknown),
--   unshared = { approach seg } extra straight shares dropped at an unlit node (X.allocateView) }.
-- v: the table to fill (sl_slip's view).
function X.classify(world, n, roads, v)
	v = v or { node = n }
	v.case, v.sideFrom, v.streams = "X", "two_way", v.streams or {}
	v.roads = #roads
	if #roads > X.MAX_ROADS then return skip(v, "roads_" .. #roads) end
	local side = nil
	for _, r in ipairs(roads) do
		if r.twoWay then
			local s = sideOf(r.la)
			if s == nil or (side ~= nil and s ~= side) then return skip(v, "mixed_sides") end
			side = s
		end
	end
	if side == nil then return skip(v, "no_two_way") end
	v.side = side
	v.shape = #roads == 4 and "crossroads" or "t_junction"
	v.approaches = {}
	local isRamp = function(r) return X.isRamp(world, r) end
	-- shallow ramps: no move across the opposing carriageway into or out of them (see the header)
	local sh = X.shallowRamps(world, n, roads, side)
	v.rampDeg = sh and sh.measured or nil
	v.shallowBlocked, v.shallowKept = {}, {}
	for _, a in ipairs(roads) do
		if #a.la.incoming > 0 then
			local ap = { seg = a.sid, m = kerbFirst(a.la.incoming, true, side), exits = {} }
			local sharp, ramps, blocked = {}, {}, {}
			local fromRamp = isRamp(a)
			local ra = sh and sh.ramps[a.sid]
			for _, b in ipairs(roads) do
				if b.sid ~= a.sid and #b.la.outgoing > 0 then
					local ex = { seg = b.sid, deg = turnDeg(world, n, a.sid, b.sid), o = kerbFirst(b.la.outgoing, false, side) }
					-- a shallow ramp joins its own carriageway into the kerb lanes (as a merge)
					if ra and not ra.leaving and b.sid == ra.to then ex.kerbAlign = true end
					if shallowBlocked(sh, a, b) then blocked[#blocked + 1] = ex
					elseif math.abs(ex.deg) > X.MAX_TURN_DEG then sharp[#sharp + 1] = ex
					elseif fromRamp and isRamp(b) then ramps[#ramps + 1] = ex
					else ap.exits[#ap.exits + 1] = ex end
				end
			end
			if #ap.exits == 0 then ap.exits = ramps end
			if #ap.exits == 0 then ap.exits = sharp end
			if #ap.exits == 0 then
				-- a joining ramp with no other way on keeps its blocked moves (never without an exit)
				for _, ex in ipairs(blocked) do
					ap.exits[#ap.exits + 1] = ex
					v.shallowKept[#v.shallowKept + 1] = a.sid .. ">" .. ex.seg
				end
				blocked = {}
			end
			if #ap.exits == 0 then return skip(v, "no_exit") end
			-- the blocked moves stay in the game's model (ap.allExits, Reset) and in the categories
			for _, ex in ipairs(blocked) do
				ex.blocked = true
				ap.exits[#ap.exits + 1] = ex
				v.shallowBlocked[#v.shallowBlocked + 1] = a.sid .. ">" .. ex.seg
			end
			-- kerb-side turn first: right turns (negative) first in right-hand traffic
			table.sort(ap.exits, function(p, q)
				if side == "right" then return p.deg < q.deg end
				return p.deg > q.deg
			end)
			for i = 2, #ap.exits do
				if math.abs(ap.exits[i].deg - ap.exits[i - 1].deg) < X.MIN_EXIT_DEG then return skip(v, "ambiguous") end
			end
			local st, stAbs = nil, nil
			for i, e in ipairs(ap.exits) do
				if math.abs(e.deg) <= X.STRAIGHT_MAX_DEG and (stAbs == nil or math.abs(e.deg) < stAbs) then
					st, stAbs = i, math.abs(e.deg)
				end
			end
			local cats = {}
			for i, e in ipairs(ap.exits) do
				local kerbTurn = (side == "right" and e.deg < 0) or (side == "left" and e.deg > 0)
				if i == st then e.cat = "straight"
				elseif st ~= nil then e.cat = i < st and "kerb" or "far"
				else e.cat = kerbTurn and "kerb" or "far" end
				cats[i] = e.cat
			end
			ap.allExits = {}
			local kept = {}
			for i, e in ipairs(ap.exits) do
				ap.allExits[i] = e
				if not e.blocked then kept[#kept + 1] = e end
			end
			ap.exits = kept
			v.approaches[#v.approaches + 1] = ap
		end
	end
	-- an exit road only blocked moves lead into keeps them (as dropBypassed: every exit road keeps a
	-- feed), e.g. a far-side shallow ramp out keeps the far turn of the approach it leaves
	if #v.shallowBlocked > 0 then
		local fed, keep = {}, {}
		for _, ap in ipairs(v.approaches) do
			for _, e in ipairs(ap.exits) do fed[e.seg] = true end
		end
		for _, ap in ipairs(v.approaches) do
			local changed = false
			for _, e in ipairs(ap.allExits) do
				if e.blocked and not fed[e.seg] then
					e.blocked, changed = nil, true
					keep[ap.seg .. ">" .. e.seg] = true
					v.shallowKept[#v.shallowKept + 1] = ap.seg .. ">" .. e.seg
				end
			end
			if changed then
				local kept = {}
				for _, e in ipairs(ap.allExits) do
					if not e.blocked then kept[#kept + 1] = e end
				end
				ap.exits = kept
			end
		end
		local still = {}
		for _, k in ipairs(v.shallowBlocked) do
			if not keep[k] then still[#still + 1] = k end
		end
		v.shallowBlocked = still
	end
	-- turns a slip lane serves: left to the slip lane (the categories stay: only kerb / far exits go)
	-- v.bypassMap keeps every bypass found (sl_audit.lua: a turn still allowed although a slip lane serves it)
	v.bypassMap = X.bypasses(world, n, v.approaches)
	v.bypassed = dropBypassed(v.approaches, v.bypassMap)
	-- traffic lights decide the extra straight shares (X.allocateView): one read per handled node
	v.lit = X.litOf(world, n)
	-- an sl_exitfan zone (a measuring mode; the zone keeps the game's phases): at a lit node the turns
	-- fan over the exit lanes their phase group leaves them (X.phaseGroups, X.roadConns); unlit or
	-- unknown (exitFanWhy "unlit" / "lit_unknown") or off the model: the rule as everywhere
	v.exitFan, v.exitFanWhy = false, nil
	if X.exitFanOf(world, n) == true then
		if v.lit ~= true then
			v.exitFanWhy = v.lit == false and "unlit" or "lit_unknown"
		else
			local okG, why = X.phaseGroups(v, roads)
			v.exitFan, v.exitFanWhy = okG, why
		end
	end
	-- open exits (a stop or the next junction close by): far-side turns fan into them (X.roadConns openExit);
	-- an sl_exitfan zone's fan already covers them
	v.open, v.openList, v.openGroup = nil, nil, nil
	if not v.exitFan then X.openExits(world, n, roads, v) end
	-- the lanes, never squeezed inside the junction where the exit roads have room
	X.allocateView(v)
	v.kind = "slip"
	return v
end

---------------------------------------------------------------------------
-- Connections

--- Road connections of a case "X" view: per exit road, the movements into it get their exit lanes
-- (placeExit), each movement's feeders mapped onto its range in order (no crossing).
function X.roadConns(v)
	local list, seen = {}, {}
	local function push(s0, l0, s1, l1)
		local key = s0 .. ":" .. l0 .. ">" .. s1 .. ":" .. l1
		if not seen[key] then
			seen[key] = true
			list[#list + 1] = Rules.conn(s0, l0, s1, l1, true, false)
		end
	end
	-- per exit segment: { o = lanes, fed = {[pos] = true}, pairs = { {ap, feeders, map, cat} } }
	local exits, order = {}, {}
	local sgn = v.side == "left" and -1 or 1
	for _, ap in ipairs(v.approaches) do
		for e, ex in ipairs(ap.exits) do
			local feeders = {}
			for i = 1, #ap.m do
				local r = ap.lanes[i]
				if r and r[1] <= e and e <= r[2] then feeders[#feeders + 1] = i end
			end
			if #feeders > 0 then
				local x = exits[ex.seg]
				if x == nil then
					x = { o = ex.o, fed = {}, pairs = {}, mvs = {} }
					exits[ex.seg] = x
					order[#order + 1] = ex.seg
				end
				local group = (ex.cat == "kerb" or ex.kerbAlign == true) and "kerb" or ex.cat
				x.mvs[#x.mvs + 1] = { ap = ap, feeders = feeders, cat = ex.cat, group = group, r = #feeders, kd = sgn * ex.deg }
			end
		end
	end
	for _, sid in ipairs(order) do
		local x = exits[sid]
		if v.exitFan and v.phaseGroup then
			-- lit under the game's phases: each phase group's movements fan over the whole exit road
			local byG, gOrder = {}, {}
			for _, mv in ipairs(x.mvs) do
				local gid = v.phaseGroup[mv.ap.seg] or mv.ap.seg
				if byG[gid] == nil then
					byG[gid] = {}
					gOrder[#gOrder + 1] = gid
				end
				table.insert(byG[gid], mv)
			end
			table.sort(gOrder)
			local all = {}
			for _, gid in ipairs(gOrder) do
				placeExitLit(byG[gid], #x.o)
				for _, mv in ipairs(byG[gid]) do all[#all + 1] = mv end
			end
			x.mvs = all
		else
			placeExit(x.mvs, #x.o)
		end
		for _, mv in ipairs(x.mvs) do
			local map = mv.map
			x.pairs[#x.pairs + 1] = { ap = mv.ap, feeders = mv.feeders, map = map, cat = mv.cat, group = mv.group }
			for _, p in ipairs(map) do
				push(mv.ap.seg, mv.ap.m[mv.feeders[p[1]]], sid, x.o[p[2]])
				x.fed[p[2]] = true
			end
		end
	end
	-- exit lanes nobody feeds: the nearest feeder of one approach, keeping that approach uncrossed
	local prefer = { straight = 0, kerb = 1, far = 2 }
	for _, sid in ipairs(order) do
		local x = exits[sid]
		for j = 1, #x.o do
			if not x.fed[j] then
				local best, bestD, bestF = nil, nil, nil
				for _, pr in ipairs(x.pairs) do
					local below, above = nil, nil -- feeder position with the largest target < j / smallest > j
					local tBelow, tAbove = nil, nil
					for _, p in ipairs(pr.map) do
						local f, t = p[1], p[2]
						if t < j and (tBelow == nil or t > tBelow or (t == tBelow and f > below)) then below, tBelow = f, t end
						if t > j and (tAbove == nil or t < tAbove or (t == tAbove and f < above)) then above, tAbove = f, t end
					end
					local f, d = below, tBelow and (j - tBelow) or nil
					if tAbove and (d == nil or tAbove - j < d) then f, d = above, tAbove - j end
					if f ~= nil then
						local score = d * 10 + prefer[pr.cat]
						if bestD == nil or score < bestD then best, bestD, bestF = pr, score, f end
					end
				end
				if best then
					push(best.ap.seg, best.ap.m[best.feeders[bestF]], sid, x.o[j])
					x.fed[j] = true
					-- kept apart from best.map (the next lanes' choice above stays as it was): openExit reads it
					best.extra = best.extra or {}
					best.extra[#best.extra + 1] = { bestF, j }
				end
			end
		end
	end
	-- open exits (v.open, X.openExits): the far-side turns widen over the lanes the movements beside them leave
	if v.open ~= nil and not (v.exitFan and v.phaseGroup) then
		for _, sid in ipairs(order) do
			local x = exits[sid]
			if v.open[sid] ~= nil then
				for _, a in ipairs(openExit(x.pairs, #x.o, v.openGroup)) do
					push(a.pr.ap.seg, a.pr.ap.m[a.pr.feeders[a.f]], sid, x.o[a.lane])
				end
			end
		end
	end
	return list
end

--- Model of the game's own connections at a crossroads (the tool's Reset, the "Game default"
-- badge; no api call regenerates them, findings.md). From in-game dumps 2026-10-11: an untouched
-- 2x2 town crossroads (24 connections) and fresh 3x3 ones (36): the kerb lane turns towards the
-- kerb into every lane of that exit and goes straight; the far lane turns the other way into
-- every lane and goes straight; straight traffic is matched lane to lane from the far side. One
-- lane does all of it. Without a straight exit (the side road of a T) the kerb lane takes the
-- kerb turns, every other lane the far turns. Kept as a model: T-junctions and unequal lane counts
-- are extrapolated (TESTING.md K). Every exit (ap.allExits): the game's default has the turns a
-- slip lane serves too (X.bypasses only changes the rule).
function X.defaultConns(v)
	local list, seen = {}, {}
	local function push(s0, l0, s1, l1)
		local key = s0 .. ":" .. l0 .. ">" .. s1 .. ":" .. l1
		if not seen[key] then
			seen[key] = true
			list[#list + 1] = Rules.conn(s0, l0, s1, l1, true, false)
		end
	end
	for _, ap in ipairs(v.approaches) do
		local N = #ap.m
		local hasStraight = false
		local exits = ap.allExits or ap.exits
		for _, ex in ipairs(exits) do if ex.cat == "straight" then hasStraight = true end end
		for _, ex in ipairs(exits) do
			if ex.cat == "straight" then
				for _, p in ipairs(X.mapLanes(N, #ex.o, false)) do push(ap.seg, ap.m[p[1]], ex.seg, ex.o[p[2]]) end
			else
				local from = {}
				if ex.cat == "kerb" then
					from = { 1 }
				elseif hasStraight or N == 1 then
					from = { N }
				else
					for i = 2, N do from[#from + 1] = i end
				end
				for _, i in ipairs(from) do
					for _, o in ipairs(ex.o) do push(ap.seg, ap.m[i], ex.seg, o) end
				end
			end
		end
	end
	return list
end

--- The full fan of a case "X" view (sl_fan zones only, a measuring mode: PHASES_PLAN.md "Fan mode"; user
-- request 2026-10-12, a hand-made lit crossroads): every entry lane of every approach (ap.m, kerb lane
-- first) connected to every exit lane (ex.o) of every exit of that approach (ap.allExits: also the turns
-- a slip lane serves and the shallow moves, as the game's own model; turns sharper than MAX_TURN_DEG
-- and ramp to ramp stay out, as X.classify leaves them). Road lanes only: ap.m / ex.o are the road
-- lanes Ring.lanesAt lists (no sidewalk, no tram-only or bus lane; tram and bus-lane connections are kept
-- by the caller, Rules.mergeTram). Never a U-turn (an exit is always another road). Lanes of one approach
-- cross and merge inside the junction by design: only a phase plan with the whole approach in one
-- phase (sl_phaseplan opts.fan) makes it safe, so the caller writes it only at a lit node, with that
-- plan in the same proposal. Order: approach, exit, entry lane, exit lane (deterministic).
function X.fanConns(v)
	local list, seen = {}, {}
	for _, ap in ipairs(v.approaches or {}) do
		for _, ex in ipairs(ap.allExits or ap.exits or {}) do
			if ex.seg ~= ap.seg then
				for _, l0 in ipairs(ap.m or {}) do
					for _, l1 in ipairs(ex.o or {}) do
						local key = ap.seg .. ":" .. l0 .. ">" .. ex.seg .. ":" .. l1
						if not seen[key] then
							seen[key] = true
							list[#list + 1] = Rules.conn(ap.seg, l0, ex.seg, l1, true, false)
						end
					end
				end
			end
		end
	end
	return list
end

--- Movement signature of a connection list: { ["seg0>seg1"] = "count|exit lanes sorted" } (road
-- connections only). Movements in `exact` (the straight ones) also carry their lane pairs: only
-- the turns varied in game, straights were lane to lane as modelled (331872), and Smart Lanes'
-- own straight folds (a 3-lane road straight into 2 lanes) differ from the model only there.
local function movements(list, exact)
	local by = {}
	for _, c in ipairs(list or {}) do
		if c.withRoad ~= false then
			local k = tostring(c.segment0) .. ">" .. tostring(c.segment1)
			local m = by[k]
			if m == nil then m = { n = 0, lanes = {}, pairs = {} }; by[k] = m end
			m.n = m.n + 1
			m.lanes[c.lane1] = true
			m.pairs[#m.pairs + 1] = tostring(c.lane0) .. ">" .. tostring(c.lane1)
		end
	end
	local out = {}
	for k, m in pairs(by) do
		local lanes = {}
		for l in pairs(m.lanes) do lanes[#lanes + 1] = l end
		table.sort(lanes)
		local sig = m.n .. "|" .. table.concat(lanes, ",")
		if exact[k] then
			table.sort(m.pairs)
			sig = sig .. "|" .. table.concat(m.pairs, ",")
		end
		out[k] = sig
	end
	return out
end

--- Whether `cur` (a node's connections) is the game's own default at a crossroads (the "Game default"
-- badge, Reset's "already set"). The engine's lane-level choice varies per approach: in game
-- 2026-10-12 (seed 488838, Showcase g3b node 331872, skewed 3x3, 36 connections; and a right-angle
-- 3x3, node 66527 of 2026-10-11) one arm's turns, in and out, came from two lanes (kerb lane -> the
-- exit's two kerb lanes, the next lane -> its far lane) where X.defaultConns has one lane fanning
-- into every exit lane; the other arms matched. So a movement (approach > exit) is compared by its
-- connection count and the exit lanes it reaches, not by which approach lane carries it. Same
-- movements as the model, nothing else: true. Straight movements must match lane to lane.
function X.isDefault(v, cur)
	local straight = {}
	for _, ap in ipairs(v.approaches or {}) do
		for _, ex in ipairs(ap.allExits or ap.exits or {}) do
			if ex.cat == "straight" then straight[tostring(ap.seg) .. ">" .. tostring(ex.seg)] = true end
		end
	end
	-- car lanes only: the bus lanes' connections are no part of the model, whoever made them
	local want, have = movements(X.defaultConns(v), straight), movements(Rules.withoutBus(cur, v.bus), straight)
	for k, sig in pairs(want) do
		if have[k] ~= sig then return false end
	end
	for k in pairs(have) do
		if want[k] == nil then return false end
	end
	return true
end

--- The kerb turns of a case "X" view (sl_lights "Free kerb turn at traffic lights"): the set
-- { ["approach seg>exit seg"] = true } of every approach's exits of category "kerb" (the turn
-- towards the driving side: right in right-hand traffic, left in left-hand traffic; the categories
-- are per side, X.classify), and their count. ap.allExits: also turns a slip lane serves and shallow
-- moves the rule leaves out (they have no connection in the rule's list; the game's default model,
-- Reset, has them). Empty for a view without approaches. Each value is the exit's lane positions
-- kerb first, { [lane] = 1 for the kerb lane, 2, ... } (ex.o; "When safe" orders the streams
-- ending in the exit by it: sl_lights L.kerbConflict), or true when the exit has no lanes listed.
function X.kerbPairs(v)
	local out, n = {}, 0
	for _, ap in ipairs((v and v.approaches) or {}) do
		for _, ex in ipairs(ap.allExits or ap.exits or {}) do
			local k = tostring(ap.seg) .. ">" .. tostring(ex.seg)
			if ex.cat == "kerb" and not out[k] then
				local pos = true
				if type(ex.o) == "table" and #ex.o > 0 then
					pos = {}
					for i, lane in ipairs(ex.o) do
						if pos[lane] == nil then pos[lane] = i end
					end
				end
				out[k] = pos
				n = n + 1
			end
		end
	end
	-- the exit fan (v.exitFan): a freed kerb turn may only use the exit's kerb lane (sl_lights
	-- L.kerbPhases: its connections into other exit lanes stay red with its approach). Not a pair key.
	if v and v.exitFan then out.kerbLaneOnly = true end
	-- the bus-only lane ends (Ring.busLanes): their connections are no kerb turn (sl_lights L.kerbIndices)
	if v and v.bus then out.bus = v.bus end
	return out, n
end

--- Short lane summary: per approach its exit letters per lane, kerb lane first, e.g.
-- "41:k|s|sf;42:ks|sf" (k kerb-side turn, s straight, f far-side turn).
function X.summary(v)
	local parts = {}
	local letter = { kerb = "k", straight = "s", far = "f" }
	for _, ap in ipairs(v.approaches or {}) do
		local lanes = {}
		for i = 1, #ap.m do
			local r, s = ap.lanes[i], ""
			if r then for e = r[1], r[2] do s = s .. letter[ap.exits[e].cat] end end
			lanes[#lanes + 1] = s
		end
		parts[#parts + 1] = tostring(ap.seg) .. ":" .. table.concat(lanes, "|")
	end
	return table.concat(parts, ";")
end

--- The widest approach (incoming lanes).
function X.mainLanes(v)
	local n = 0
	for _, ap in ipairs(v.approaches or {}) do n = math.max(n, #ap.m) end
	return n
end

return X
