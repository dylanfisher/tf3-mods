-- Organic Towns: geometry checker for planned street edges (pure). Evaluates each edge's Hermite curve
-- (p0, t0, p1, t1 as ot_plan emits them) against the town street template limits, and the angles at the nodes.
--
-- Limits (docs/findings.md "Town street templates", api/type.d.tl StreetType): every base `town_*` street has
-- minCurveRadius 44 m ("minimal radius of the final proposal"), minCurveRadiusBuild 60 m (player drag tool),
-- maxSlopeBuild 0.2. The planner aims at RADIUS = 70 m (60 m plus a margin) so script proposals pass whichever
-- of the two the engine applies to them.
--
--   M.edge(e)                 -> { length, chord, minRadius, slope, dev0, dev1 (deg: tangent vs chord), ratio }
--   M.increment(inc, g, lim)  -> report { edges = {per-edge info}, bad = {violations}, minRadius, minAngle, ... }
--   M.summary(report)         -> one log-friendly line
-- A violation is { kind = "radius"|"short"|"slope"|"angle"|"side"|"kink"|"tangent", edge = entity or nil, node = id,
-- value = number }.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

local sqrt, abs, deg, max, min = math.sqrt, math.abs, math.deg, math.max, math.min

M.LIMITS = {
	radius = 70,       -- m: planner target (template minCurveRadiusBuild 60 m + margin)
	hardRadius = 44,   -- m: template minCurveRadius ("final proposal")
	minLen = 10,       -- m: shortest edge the planner emits
	maxSlope = 0.2,    -- template maxSlopeBuild
	minAngle = 25,     -- deg: between two edges at a node (actual tangents): a bend at a node with two streets
	sideAngle = 60,    -- deg: at a junction (3+ streets) a new street meets every other street there at least this far
	                   -- off (a side street leaves at 60-120 deg; 2026-10-19 §75), except the two arms of a fork
	maxKink = 3,       -- deg: tangent break at a degree-2 node where one street continues (not a corner)
	cornerFrom = 45,   -- deg: a break this large at a degree-2 node is a deliberate corner, not a kink
	maxDev = 60,       -- deg: tangent vs chord at an edge end (beyond: the curve is an S or a loop)
}
M.SAMPLES = 24

-- §75 (2026-10-19; user shots: a side street leaving a curving street at ~20-30 deg and running back beside it): a
-- junction's side street leaves at least LIMITS.sideAngle off every street there. A fork is the one exception: two arms
-- under it that split a third street's straight continuation between them, each at least FORK_DEV (and at most
-- FORK_MAX) off it (a Y; a street going on straight with a branch at 25 deg beside it is no fork).
M.FORK_DEV = 12
M.FORK_MAX = 50
-- deg: the checker's report (PLAN geoSide=) counts a side street only this far under LIMITS.sideAngle. The planner and the
-- near-miss T hold the rule exactly (a T's heading is clamped to TEE_MIN_DEG 60), and the built edges' tangents
-- read back 59.99x: run 2026-10-19_1949_sqot's 6 geoSide=1 plans were near-miss joins at minAngle=60.00 (§75 follow-up)
M.SIDE_TOL = 0.1

--- Is the pair (i, j) of the headings hs (radians, the streets leaving one node) a fork? Only at a node of three.
function M.isFork(hs, i, j)
	if #hs ~= 3 then return false end
	local k = 6 - i - j
	local opp = hs[k] + math.pi
	local di, dj = G.angleDiff(hs[i], opp), G.angleDiff(hs[j], opp)
	local lo, hi = math.rad(M.FORK_DEV), math.rad(M.FORK_MAX)
	if di < lo or dj < lo or di > hi or dj > hi then return false end
	-- (the continuation lies between them)
	return abs(di + dj - G.angleDiff(hs[i], hs[j])) < 1e-3
end

--- The side-street rule at one node: arms = { { h = heading leaving the node (radians), new = bool, free = bool } }.
--- At a node with three or more streets, the smallest angle (radians) of a pair with a new arm (and no `free` one:
--- streets exempt by design) under `side` (radians) that is no fork, and the pair's indices; nil when none.
function M.sideBad(arms, side)
	if side == nil or side <= 0 or #arms < 3 then return nil end
	local hs = {}
	for i, a in ipairs(arms) do hs[i] = a.h end
	local worst, wi, wj = nil, nil, nil
	for i = 1, #arms do
		for j = i + 1, #arms do
			local a, b = arms[i], arms[j]
			if (a.new or b.new) and not a.free and not b.free then
				local d = G.angleDiff(a.h, b.h)
				if d < side - 1e-9 and not M.isFork(hs, i, j) and (worst == nil or d < worst) then worst, wi, wj = d, i, j end
			end
		end
	end
	return worst, wi, wj
end

local function lim(l, k)
	if l and l[k] ~= nil then return l[k] end
	return M.LIMITS[k]
end

--- Hermite first and second derivatives (2D) at s in 0..1.
function M.derivs(p0, t0, p1, t1, s)
	local s2 = s * s
	local a1, b1, c1, d1 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
	local a2, b2, c2, d2 = 12 * s - 6, 6 * s - 4, -12 * s + 6, 6 * s - 2
	local dx = a1 * p0[1] + b1 * t0[1] + c1 * p1[1] + d1 * t1[1]
	local dy = a1 * p0[2] + b1 * t0[2] + c1 * p1[2] + d1 * t1[2]
	local ddx = a2 * p0[1] + b2 * t0[1] + c2 * p1[1] + d2 * t1[1]
	local ddy = a2 * p0[2] + b2 * t0[2] + c2 * p1[2] + d2 * t1[2]
	return dx, dy, ddx, ddy
end

--- Point (2D) of the Hermite curve at s.
function M.point(p0, t0, p1, t1, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	return h00 * p0[1] + h10 * t0[1] + h01 * p1[1] + h11 * t1[1], h00 * p0[2] + h10 * t0[2] + h01 * p1[2] + h11 * t1[2]
end

--- Smallest radius of curvature (2D) along the edge's Hermite curve, and its arc length (sampled).
function M.minRadius(p0, t0, p1, t1, n)
	n = n or M.SAMPLES
	local best = math.huge
	local length = 0
	local px, py = p0[1], p0[2]
	for i = 0, n do
		local s = i / n
		local dx, dy, ddx, ddy = M.derivs(p0, t0, p1, t1, s)
		local v2 = dx * dx + dy * dy
		local cross = abs(dx * ddy - dy * ddx)
		if v2 < 1e-9 then
			best = 0   -- a cusp: the curve stops and turns
		elseif cross > 1e-12 then
			local r = v2 * sqrt(v2) / cross
			if r < best then best = r end
		end
		if i > 0 then
			local x, y = M.point(p0, t0, p1, t1, s)
			length = length + G.dist(px, py, x, y)
			px, py = x, y
		end
	end
	return best, length
end

local function angleOf(x, y) return G.atan2(y, x) end

-- plan line of a piece key: the part before "#" (organic lines are split into pieces "<line>#<n>"; a piece
-- that is a whole line is its own). Grid pieces ("h<i>:<j>", "v<i>:<j>") return nil: a lattice node whose
-- jitter is too large for one tangent keeps a corner by design (ot_grow_grid nodeDir), reported as a corner.
local function lineOf(key)
	if key == nil then return nil end
	if key:match("^[hv]%-?%d+:%-?%d+$") then return nil end
	local line = key:match("^(.-)#%d+$")
	if line then return line end
	return key
end
M.lineOf = lineOf

--- Per-edge geometry numbers.
function M.edge(e)
	local p0, p1, t0, t1 = e.p0, e.p1, e.t0, e.t1
	local cx, cy = p1[1] - p0[1], p1[2] - p0[2]
	local chord = sqrt(cx * cx + cy * cy)
	local r, length = M.minRadius(p0, t0, p1, t1)
	local ch = angleOf(cx, cy)
	local dev0 = deg(G.angleDiff(angleOf(t0[1], t0[2]), ch))
	local dev1 = deg(G.angleDiff(angleOf(t1[1], t1[2]), ch))
	local tl0, tl1 = G.len(t0[1], t0[2]), G.len(t1[1], t1[2])
	local slope = 0
	if chord > 0 then slope = abs((p1[3] or 0) - (p0[3] or 0)) / chord end
	return { length = length, chord = chord, minRadius = r, slope = slope, dev0 = dev0, dev1 = dev1,
		ratio = chord > 0 and max(tl0, tl1) / chord or 0, ratioMin = chord > 0 and min(tl0, tl1) / chord or 0 }
end

-- heading of an edge leaving node `id` (its tangent there, pointing away from the node)
local function leaving(e, id)
	if e.node0 == id then return angleOf(e.t0[1], e.t0[2]) end
	return angleOf(-e.t1[1], -e.t1[2])
end

--- Checks an increment. `g` (ot_graph, optional) adds the existing edges at join nodes (their tangents when
--- known, else chords). Returns a report; report.bad lists violations, worst first per kind.
function M.increment(inc, g, limits)
	local rep = { edges = {}, bad = {}, minRadius = math.huge, minAngle = 180, maxKink = 0, maxCorner = 0, shortest = math.huge,
		maxSlope = 0, counts = {} }
	local function bad(kind, v)
		v.kind = kind
		rep.bad[#rep.bad + 1] = v
		rep.counts[kind] = (rep.counts[kind] or 0) + 1
	end
	local R, hardR, minLen = lim(limits, "radius"), lim(limits, "hardRadius"), lim(limits, "minLen")
	local maxSlope, maxDev = lim(limits, "maxSlope"), lim(limits, "maxDev")
	local at = {}   -- node id -> { {heading, edge entity, street key} }
	local function add(id, h, ent, key, free)
		at[id] = at[id] or {}
		local l = at[id]
		l[#l + 1] = { h = h, edge = ent, key = key, free = free }
	end
	for _, e in ipairs(inc.edges) do
		local info = M.edge(e)
		info.entity = e.entity
		rep.edges[#rep.edges + 1] = info
		if info.minRadius < rep.minRadius then rep.minRadius = info.minRadius end
		if info.chord < rep.shortest then rep.shortest = info.chord end
		if info.slope > rep.maxSlope then rep.maxSlope = info.slope end
		if info.minRadius < R then
			bad("radius", { edge = e.entity, value = info.minRadius, hard = info.minRadius < hardR, length = info.chord })
		end
		if info.chord < minLen - 1e-6 then bad("short", { edge = e.entity, value = info.chord }) end
		if info.slope > maxSlope + 1e-9 then bad("slope", { edge = e.entity, value = info.slope }) end
		if info.dev0 > maxDev or info.dev1 > maxDev then
			bad("tangent", { edge = e.entity, value = max(info.dev0, info.dev1) })
		end
		add(e.node0, leaving(e, e.node0), e.entity, e.key, e.sideFree)
		add(e.node1, leaving(e, e.node1), e.entity, e.key, e.sideFree)
	end
	-- existing edges at the nodes the increment touches
	if g then
		for id, l in pairs(at) do
			if id > 0 then
				for _, eid in ipairs(g.adj[id] or {}) do
					local ge = g.edgeById[eid]
					local a, b = g.nodeById[ge.n0], g.nodeById[ge.n1]
					local t0 = ge.t0 or { b.x - a.x, b.y - a.y }
					local t1 = ge.t1 or { b.x - a.x, b.y - a.y }
					l[#l + 1] = { h = leaving({ node0 = ge.n0, t0 = t0, t1 = t1 }, id), edge = "g" .. eid, existing = true }
				end
			end
		end
	end
	local minAngle, maxKink, corner = lim(limits, "minAngle"), lim(limits, "maxKink"), lim(limits, "cornerFrom")
	local side = math.rad(lim(limits, "sideAngle") - M.SIDE_TOL)
	for id, l in pairs(at) do
		-- (§75: a side street at a junction; the new edges' arms only, an existing junction's own angles stand)
		local arms = {}
		for i, x in ipairs(l) do arms[i] = { h = x.h, new = not x.existing, free = x.free } end
		local sb, si, sj = M.sideBad(arms, side)
		if sb then bad("side", { node = id, value = deg(sb), edges = { l[si].edge, l[sj].edge } }) end
		for i = 1, #l do
			for j = i + 1, #l do
				local a = deg(G.angleDiff(l[i].h, l[j].h))
				if a < rep.minAngle then rep.minAngle = a end
				if a < minAngle - 1e-6 then bad("angle", { node = id, value = a, edges = { l[i].edge, l[j].edge } }) end
			end
		end
		if #l == 2 then
			-- a break where one plan line continues is a kink; between two different lines (or at a join with an
			-- existing street) it is a corner (rep.maxCorner), which towns have too
			local k = 180 - deg(G.angleDiff(l[1].h, l[2].h))
			local la, lb = lineOf(l[1].key), lineOf(l[2].key)
			if la and la == lb then
				if k > rep.maxKink then rep.maxKink = k end
				if k > maxKink and k < corner then bad("kink", { node = id, value = k, edges = { l[1].edge, l[2].edge } }) end
			elseif k > rep.maxCorner and k < corner then
				rep.maxCorner = k
			end
		end
	end
	table.sort(rep.bad, function(p, q)
		if p.kind ~= q.kind then return p.kind < q.kind end
		if p.kind == "radius" or p.kind == "short" or p.kind == "angle" or p.kind == "side" then return p.value < q.value end
		return p.value > q.value
	end)
	if rep.minRadius == math.huge then rep.minRadius = -1 end
	if rep.shortest == math.huge then rep.shortest = 0 end
	return rep
end

---------------------------------------------------------------------------
-- Self-clearance: the new edges of ONE increment must not overlap or cross each other except at shared nodes
-- (showcase v2 log: "REFUSED ... msgs=Collision partners=ent-20": the pre-check collided a plan's new edge with
-- one of its own new nodes). ot_plan applies M.pairConflict while it accepts edges; M.selfClearance re-checks a
-- finished increment (tests, the driver's PLAN line). Street bodies: a small town street is 16 m wide, a medium
-- one 24 m (main streets are planned medium), so centre lines of two streets that don't meet keep half widths
-- apart (16 / 20 / 24 m). Near a node an edge ends at, a cap of END_CAP m is left out of the body test (the
-- junction itself), but the end node must keep END_CLEAR m from the other street's centre line.

M.END_CAP = 12          -- m of an edge end left out of the body-to-body test
M.END_CLEAR = 12        -- m: an edge's end node to another (unconnected) new edge's centre line
M.SHARED_CAP = 30       -- m: two edges from one node may run closer than the bodies near that node ...
M.SHARED_FACTOR = 0.6   -- ... beyond it they keep this share of the body clearance (a curve bending back)
M.SAMPLE_STEP = 10      -- m between curve samples

--- Half width (m) of a planned street class (main is planned with the medium template), or of its template
--- when given (base town templates: xsmall 14 m, small 16, medium 24, large 32 wide incl. sidewalks).
M.TEMPLATE_HALF = { xsmall = 7, small = 8, medium = 12, large = 16 }
function M.halfWidth(class, template)
	if type(template) == "string" then
		local size = template:match("town_%a+_(%a+)%.street_template$")
		if size and M.TEMPLATE_HALF[size] then return M.TEMPLATE_HALF[size] end
	end
	if class == "main" or class == "medium" then return 12 end
	return 8
end

-- Junction footprint (NEXT_PHASE_BRIEF 9: 98 x "Construction Not Possible" with no collision; every failing
-- junction star of the showcase v3 log included the short `conn:` joint edge, 17-38 m, mostly at 45-55 deg to
-- the next street). Where two streets meet at angle theta (between their directions away from the node), their
-- bodies overlap for about max(half widths) / tan(theta / 2) along each: 8 m at a right angle for small streets,
-- 19 m at 46 deg, 36 m at 25 deg. An edge needs room for the footprints at both ends plus FOOTPRINT_MARGIN, or
-- the engine cannot fit its junction geometry (inferred from the log: unverified rule, PLAN.md 6.2 "Refusals").
M.FOOTPRINT_MARGIN = 4          -- m of plain street left between the two junction footprints of an edge
M.FOOTPRINT_STRAIGHT = math.rad(150)   -- streets meeting this straight need no footprint (a gentle bend)

--- Footprint (m) along a street of half width w leaving a node at heading h, from one other street there at
--- heading o with half width wo.
function M.footprint(h, w, o, wo)
	local theta = G.angleDiff(h, o)
	if theta >= M.FOOTPRINT_STRAIGHT then return 0 end
	return math.max(w, wo) / math.tan(math.max(theta, math.rad(5)) / 2)
end

--- Samples of an edge's Hermite curve (2D) every ~SAMPLE_STEP m: { {x, y}, ... } from p0 to p1. Straight edges
--- (tangents along the chord) give their two end points.
function M.curvePts(p0, t0, p1, t1, step)
	step = step or M.SAMPLE_STEP
	local cx, cy = p1[1] - p0[1], p1[2] - p0[2]
	local L = sqrt(cx * cx + cy * cy)
	local function straight(t)
		local tl = sqrt(t[1] * t[1] + t[2] * t[2])
		return tl < 1e-9 or L < 1e-9 or abs(t[1] * cy - t[2] * cx) / (tl * L) < 1e-4 and (t[1] * cx + t[2] * cy) > 0
	end
	if straight(t0) and straight(t1) then return { { p0[1], p0[2] }, { p1[1], p1[2] } } end
	local n = max(2, math.ceil(L / step))
	local out = {}
	for i = 0, n do
		local x, y = M.point(p0, t0, p1, t1, i / n)
		out[#out + 1] = { x, y }
	end
	out[1] = { p0[1], p0[2] }
	out[#out] = { p1[1], p1[2] }
	return out
end

--- The part of polyline pts between arc length a from its start and b from its end (nil when nothing is left).
function M.polyTrim(pts, a, b)
	local total = G.polyLen(pts)
	if a + b >= total - 1e-6 then return nil end
	local function at(s)
		local acc = 0
		for i = 2, #pts do
			local p, q = pts[i - 1], pts[i]
			local l = G.dist(p[1], p[2], q[1], q[2])
			if acc + l >= s or i == #pts then
				local t = l > 0 and G.clamp((s - acc) / l, 0, 1) or 0
				return p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, i
			end
			acc = acc + l
		end
		return pts[#pts][1], pts[#pts][2], #pts
	end
	local x0, y0, i0 = at(a)
	local x1, y1, i1 = at(total - b)
	local out = { { x0, y0 } }
	for i = i0, i1 - 1 do out[#out + 1] = { pts[i][1], pts[i][2] } end
	out[#out + 1] = { x1, y1 }
	return out
end

--- Distance from a point to a polyline.
function M.pointPolyDist(x, y, pts)
	local best = math.huge
	for i = 2, #pts do
		local d = (G.pointSegDist(x, y, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]))
		if d < best then best = d end
	end
	if #pts == 1 then best = G.dist(x, y, pts[1][1], pts[1][2]) end
	return best
end

local function bboxOf(pts)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(pts) do
		if p[1] < x0 then x0 = p[1] end
		if p[1] > x1 then x1 = p[1] end
		if p[2] < y0 then y0 = p[2] end
		if p[2] > y1 then y1 = p[2] end
	end
	return x0, y0, x1, y1
end

--- Smallest distance between two polylines (0 when they cross).
function M.polyDist(P, Q)
	local best = math.huge
	for i = 2, #P do
		local a, b = P[i - 1], P[i]
		for j = 2, #Q do
			local c, d = Q[j - 1], Q[j]
			if G.segIntersect(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2], 1e-9) then return 0 end
			local v = min(G.pointSegDist(a[1], a[2], c[1], c[2], d[1], d[2]), G.pointSegDist(b[1], b[2], c[1], c[2], d[1], d[2]),
				G.pointSegDist(c[1], c[2], a[1], a[2], b[1], b[2]), (G.pointSegDist(d[1], d[2], a[1], a[2], b[1], b[2])))
			if v < best then best = v end
		end
	end
	return best
end

--- true when the polylines' interiors cross (touching ends within 1e-4 don't count).
function M.polyCross(P, Q)
	for i = 2, #P do
		local a, b = P[i - 1], P[i]
		for j = 2, #Q do
			local c, d = Q[j - 1], Q[j]
			if G.segIntersect(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2], 1e-4) then return true end
		end
	end
	return false
end

local function reversed(pts)
	local out = {}
	for i = #pts, 1, -1 do out[#out + 1] = pts[i] end
	return out
end

--- Conflict between two new edges given as sampled polylines P (nodes pa -> pb) and Q (qa -> qb) with their
--- half widths: nil when they may coexist, else "crossesNew" | "nearNew" and the measured distance. Node ids
--- only tell shared ends apart (equal ids = the same node).
function M.pairConflict(P, pa, pb, wP, Q, qa, qb, wQ)
	local ce = wP + wQ
	local x0, y0, x1, y1 = bboxOf(P)
	local u0, v0, u1, v1 = bboxOf(Q)
	if u0 > x1 + ce or u1 < x0 - ce or v0 > y1 + ce or v1 < y0 - ce then return nil end
	local shared = 0
	if pa == qa or pa == qb then shared = shared + 1 end
	if pb == qa or pb == qb then shared = shared + 1 end
	if shared >= 2 then return nil end   -- the same node pair: ot_plan's "exists"
	if shared == 1 then
		-- orient both to start at the shared node
		local s = (pa == qa or pa == qb) and pa or pb
		if pa ~= s then P = reversed(P) end
		if qa ~= s then Q = reversed(Q) end
		local p5, q5 = M.polyTrim(P, 5, 0), M.polyTrim(Q, 5, 0)
		if p5 and q5 and M.polyCross(p5, q5) then return "crossesNew", 0 end
		local pf, qf = M.polyTrim(P, M.SHARED_CAP, 0), M.polyTrim(Q, M.SHARED_CAP, 0)
		if pf and qf then
			local d = M.polyDist(pf, qf)
			if d < M.SHARED_FACTOR * ce then return "nearNew", d end
		end
		return nil
	end
	if M.polyCross(P, Q) then return "crossesNew", 0 end
	local e = min(M.pointPolyDist(P[1][1], P[1][2], Q), M.pointPolyDist(P[#P][1], P[#P][2], Q),
		M.pointPolyDist(Q[1][1], Q[1][2], P), M.pointPolyDist(Q[#Q][1], Q[#Q][2], P))
	if e < M.END_CLEAR then return "nearNew", e end
	local pt, qt = M.polyTrim(P, M.END_CAP, M.END_CAP), M.polyTrim(Q, M.END_CAP, M.END_CAP)
	if pt and qt then
		local d = M.polyDist(pt, qt)
		if d < ce then return "nearNew", d end
	end
	return nil
end

--- Every pair of new edges of an increment (ot_plan shapes: p0, t0, p1, t1, node0, node1, class) that conflicts:
--- { {i, j, kind, d} } (indices into inc.edges), empty when the increment is clean.
function M.selfClearance(inc)
	local pts, out = {}, {}
	for i, e in ipairs(inc.edges) do pts[i] = M.curvePts(e.p0, e.t0, e.p1, e.t1) end
	for i = 1, #inc.edges do
		local a = inc.edges[i]
		for j = i + 1, #inc.edges do
			local b = inc.edges[j]
			local kind, d = M.pairConflict(pts[i], a.node0, a.node1, M.halfWidth(a.class, a.template), pts[j], b.node0, b.node1,
				M.halfWidth(b.class, b.template))
			if kind then out[#out + 1] = { i = i, j = j, kind = kind, d = d } end
		end
	end
	return out
end

--- True when the report has no violation of the given kinds (default: radius, short, slope, angle, tangent, kink;
--- not "side": the planner holds it for steer towns' plans only, §75).
function M.passes(rep, kinds)
	kinds = kinds or { "radius", "short", "slope", "angle", "tangent", "kink" }
	for _, k in ipairs(kinds) do
		if (rep.counts[k] or 0) > 0 then return false end
	end
	return true
end

--- Violation counts as "radius:2/kink:1" ("none" without; "side" not: steer towns' plans only, the PLAN line's
--- `geoSide=`).
function M.badText(rep)
	local parts = {}
	for _, k in ipairs({ "radius", "short", "slope", "angle", "kink", "tangent" }) do
		if rep.counts[k] then parts[#parts + 1] = k .. ":" .. rep.counts[k] end
	end
	return #parts > 0 and table.concat(parts, "/") or "none"
end

--- One line: counts per kind and the extremes.
function M.summary(rep)
	return string.format("bad=%s minR=%.1f minAngle=%.1f maxKink=%.1f maxCorner=%.1f shortest=%.1f maxSlope=%.3f",
		M.badText(rep), rep.minRadius, rep.minAngle, rep.maxKink, rep.maxCorner,
		rep.shortest, rep.maxSlope)
end

-- Long straight empty streets (2026-10-14 late, the same-seed comparison: the long straight empty lanes at Ellesmere S,
-- Winchcombe W, Windermere SW, Henley-in-Arden S were the satellite links, see ot_satellite). The guard over any
-- increment: a chain of new town-street edges (no country lane, no bridge), each one straight (its tangents within
-- STRAIGHT_EDGE_DEG of its chord), joined end to end at a node where they turn less than STRAIGHT_DEG, whose midpoints
-- are all more than HOUSE_R from any building, is a straight run; ot_driver drops the far part of a run longer than
-- STRAIGHT_MAX (PLAN `straight=`).
M.STRAIGHT_MAX = 250
M.STRAIGHT_DEG = 6
M.STRAIGHT_EDGE_DEG = 3
M.HOUSE_R = 60

local function angDiff(a, b)
	local d = math.abs(a - b) % (2 * math.pi)
	if d > math.pi then d = 2 * math.pi - d end
	return d
end

--- Straight runs ahead of the houses in an increment (see above). pts = the town's buildings { {x, y} }; o =
--- { max = STRAIGHT_MAX, centre = {x, y} (the side a run is kept from; default: the end nearer a building) }.
--- Returns { max = the longest run (m), runs = { { len, edges = { index, ... } (from the kept end), drop = { index, ...
--- } (the edges beyond o.max from the kept end) } } }.
function M.straightRuns(inc, pts, o)
	o = o or {}
	local maxLen = o.max or M.STRAIGHT_MAX
	local cell = M.HOUSE_R
	local idx = {}
	for _, p in ipairs(pts or {}) do
		local k = math.floor(p[1] / cell) * 65536 + math.floor(p[2] / cell)
		local l = idx[k]
		if l == nil then l = {}; idx[k] = l end
		l[#l + 1] = p
	end
	local function nearHouse(x, y)
		local i0, j0 = math.floor(x / cell), math.floor(y / cell)
		local best = math.huge
		for i = i0 - 1, i0 + 1 do
			for j = j0 - 1, j0 + 1 do
				for _, p in ipairs(idx[i * 65536 + j] or {}) do
					local d = (p[1] - x) ^ 2 + (p[2] - y) ^ 2
					if d < best then best = d end
				end
			end
		end
		return math.sqrt(best)
	end
	local tol = math.rad(M.STRAIGHT_EDGE_DEG)
	local cand, byNode = {}, {}
	for i, e in ipairs(inc and inc.edges or {}) do
		if not e.forestLane and not e.bridge and ((e.node0 or 0) < 0 or (e.node1 or 0) < 0) then
			local cx, cy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
			local L = math.sqrt(cx * cx + cy * cy)
			if L > 1 then
				local hc = math.atan(cy, cx)
				local h0 = math.atan(e.t0[2], e.t0[1])
				local h1 = math.atan(e.t1[2], e.t1[1])
				local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
				if angDiff(h0, hc) <= tol and angDiff(h1, hc) <= tol and nearHouse(mx, my) > M.HOUSE_R then
					cand[i] = { i = i, h = hc, len = e.length or L, a = e.node0, b = e.node1 }
					byNode[e.node0] = byNode[e.node0] or {}
					byNode[e.node1] = byNode[e.node1] or {}
					table.insert(byNode[e.node0], i)
					table.insert(byNode[e.node1], i)
				end
			end
		end
	end
	-- (the heading of edge c leaving node n)
	local function out(c, n)
		if c.a == n then return c.h end
		return c.h + math.pi
	end
	-- (the edge going straight on from c through node n, also across a junction: leaving n along it is the opposite of
	-- leaving n along c, within STRAIGHT_DEG; the straightest one)
	local function partner(c, n)
		local l = byNode[n]
		if l == nil or n > 0 then return nil end
		local best, bd = nil, math.rad(M.STRAIGHT_DEG)
		for _, j in ipairs(l) do
			local d = cand[j]
			if d and j ~= c.i then
				local a = angDiff(out(d, n), out(c, n) + math.pi)
				if a <= bd then best, bd = d, a end
			end
		end
		return best
	end
	local seen, rep = {}, { max = 0, runs = {} }
	for i, c in pairs(cand) do
		if not seen[i] then
			-- walk to one end, then collect to the other
			local cur, from = c, nil
			local endNode = c.a
			for _ = 1, 1000 do
				local nxt = partner(cur, endNode)
				if nxt == nil or nxt == from or seen[nxt.i] then break end
				from = cur
				endNode = nxt.a == endNode and nxt.b or nxt.a
				cur = nxt
			end
			-- cur is an end edge, endNode its outer node; collect from there
			local chain, len = {}, 0
			local node = endNode
			local e = cur
			local prev = nil
			for _ = 1, 1000 do
				if e == nil or seen[e.i] then break end
				seen[e.i] = true
				chain[#chain + 1] = e.i
				len = len + e.len
				local far = e.a == node and e.b or e.a
				prev, node = e, far
				e = partner(prev, node)
			end
			if len > rep.max then rep.max = len end
			if len > maxLen then
				-- the kept end: an existing node (joined to the town) or the end nearer a building
				local first, last = inc.edges[chain[1]], inc.edges[chain[#chain]]
				local function endPos(edge, n) return edge.node0 == n and edge.p0 or edge.p1 end
				local fn = (first.node0 == endNode) and first.node0 or first.node1
				local p1 = endPos(first, fn)
				local p2 = endPos(last, node)
				local keepFirst
				if fn > 0 and node <= 0 then keepFirst = true
				elseif node > 0 and fn <= 0 then keepFirst = false
				else keepFirst = nearHouse(p1[1], p1[2]) <= nearHouse(p2[1], p2[2]) end
				if not keepFirst then
					local r = {}
					for k = #chain, 1, -1 do r[#r + 1] = chain[k] end
					chain = r
				end
				local acc, drop = 0, {}
				for _, k in ipairs(chain) do
					acc = acc + cand[k].len
					if acc > maxLen + 1e-6 then drop[#drop + 1] = k end
				end
				rep.runs[#rep.runs + 1] = { len = len, edges = chain, drop = drop }
			end
		end
	end
	return rep
end

return M
