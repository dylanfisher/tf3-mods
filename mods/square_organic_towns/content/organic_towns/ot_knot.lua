-- Organic Towns: knot look rules for a new plan piece (pure; §70, 2026-10-15; PLAN.md 6.2 "Steering lock policy
-- (§69)", "Knots (§70)").
--
-- Run `2026-10-15_2031_sqot` (seed `a`, Quick 40, the §69 steer lock): Merehythe's south grew tangled curved locked
-- streets: an X of two curves crossing away from any junction, a curve looping back across its neighbour, curves running
-- a few metres beside each other. The selector's own tests missed them (from the code): ot_select.classifyPiece blocks a
-- piece only when its MIDDLE point lies within occR (8-30 m) of a street, or when its chords cross a street's chord, with
-- every street at its end nodes left out; ot_plan's crossesExisting / nearExisting compare chords too. A 100 m curved
-- edge (radius >= 70 m) bulges up to ~20 m off its chord, so two curves cross while their chords don't, a curve leaving
-- a node may cross another street of that node further on, and a piece can run 20-35 m beside a street for 100 m with
-- its middle clear. Three rules, on the curves (graph edges as their Hermite curves from the snapshot tangents):
--   * cross: the piece crosses a street (an existing edge, or a piece chosen in this increment) other than at a node
--     they share (TRIM_M of each end at a shared node left out);
--   * parallel: for at least PAR_RUN (max(PAR_RUN_MIN, PAR_RUN_K x block length)) the piece runs within PAR_M
--     (PAR_K x block depth, PAR_MIN..PAR_MAX) of another street at most PAR_DEG off its direction (the street's own
--     ends don't count: a street continuing it is no neighbour; END_SKIP of each end of the piece left out);
--   * loop: the piece closes a loop (its ends already joined by the network) enclosing less than LOOP_K x a block's
--     area (len x depth): a lasso, a sliver between two curves.
-- ot_select applies them to steer towns' pieces (not motif / ring / connector pieces) and lets them give way only when
-- the increment would be empty (as the §69 rake / wiggle rules). Every loop is capped (SCAN_MAX, WALK_MAX, the
-- samples per polyline).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local C = ug_require "square_organic_towns::/organic_towns/ot_check.lua"

local M = {}

local abs, sqrt, min, max = math.abs, math.sqrt, math.min, math.max

M.ON = true
M.TRIM_M = 6              -- m of a polyline's end at a shared node left out of the crossing test
M.PAR_K = 0.65            -- near-parallel: within this x the block depth ...
M.PAR_MIN = 20            -- ... at least (m; two small streets' bodies need 16) ...
M.PAR_MAX = 35            -- ... at most (m; a lot depth: EU organic 45 m blocks -> 29 m)
M.PAR_DEG = 25            -- deg: at most this off the other street's direction
M.PAR_RUN_K = 1.0         -- for at least this x the block length ...
M.PAR_RUN_MIN = 60        -- ... at least (m)
M.END_SKIP = 30           -- m of each end of the piece not counted for the parallel run (its junction approach)
M.STEP = 10               -- m between samples
M.LOOP_K = 0.5            -- a loop enclosing less than this x a block's area (len x depth) is a knot
M.LOOP_PERIM_K = 3        -- the way back through the network at most this x (len + depth) (m)
M.WALK_MAX = 400          -- nodes settled at most in the loop search
M.SCAN_MAX = 400          -- other streets compared per piece at most
M.SAMPLES_MAX = 200       -- samples per polyline at most
-- hooks (§71, 2026-10-16; run 2026-10-16_0405_sqot: a few small curled "P" dead ends in Merehythe and Shaw, our locked
-- streets): a piece that leaves a new dead end must not make the dead-end street it ends (the piece plus the chain of
-- streets behind it back to its junction, through nodes with two streets) curl round:
--   * turn: the chain's last hookTurnM (HOOK_TURN_K x block length, HOOK_TURN_MIN..HOOK_TURN_MAX: a curl, not a long
--     sweeping street) turns more than HOOK_DEG in all (signed: an S that comes back to its heading is no hook);
--   * back: the far end comes back within hookR (HOOK_K x block depth, HOOK_MIN..HOOK_MAX) of its own chain (a point at
--     least HOOK_ARC_K x hookR back along it) or, heading toward it (HOOK_TOWARD_DEG), of the other streets at the chain's
--     junction, after at least HOOK_ARC_K x hookR of chain.
-- ot_select leaves such a piece out of a chosen increment (steer towns, as the knots; never connector / ring pieces,
-- nor the climbing motifs) and keeps it only when that would empty the increment.
M.HOOK = true
M.HOOK_DEG = 120
M.HOOK_TURN_K = 2.5
M.HOOK_TURN_MIN = 150
M.HOOK_TURN_MAX = 250
M.HOOK_K = 1.0
M.HOOK_MIN = 30
M.HOOK_MAX = 50
M.HOOK_ARC_K = 3
M.HOOK_TOWARD_DEG = 60    -- the end heads at most this off the way to the junction's street it comes back to
M.HOOK_WALK = 8           -- chain edges walked back at most
M.HOOK_BACK_M = 400       -- m of chain walked back at most
M.HOOK_FREE = { switchbacks = true, hill_climb = true }   -- motifs whose streets turn back by design

--- The limits for a style's block: { parM, parRun, parCos, loopA, perim }.
function M.limits(style)
	local b = style and style.block or {}
	local len, depth = tonumber(b.len) or 60, tonumber(b.depth) or 45
	return { parM = G.clamp(M.PAR_K * depth, M.PAR_MIN, M.PAR_MAX), parRun = max(M.PAR_RUN_MIN, M.PAR_RUN_K * len),
		parCos = math.cos(math.rad(M.PAR_DEG)), loopA = M.LOOP_K * len * depth, perim = M.LOOP_PERIM_K * (len + depth),
		hookR = G.clamp(M.HOOK_K * depth, M.HOOK_MIN, M.HOOK_MAX), hookTurn = math.rad(M.HOOK_DEG),
		hookTurnM = G.clamp(M.HOOK_TURN_K * len, M.HOOK_TURN_MIN, M.HOOK_TURN_MAX) }
end

--- A polyline resampled to at most STEP between points (at most SAMPLES_MAX points).
function M.dense(pts)
	if pts == nil or #pts < 2 then return pts end
	local L = G.polyLen(pts)
	local step = max(M.STEP, L / M.SAMPLES_MAX)
	return G.resample(pts, step)
end

--- A graph edge's curve as a polyline (its Hermite curve from the snapshot tangents; the chord without them).
function M.edgePts(g, e)
	local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
	if a == nil or b == nil then return nil end
	if e.t0 and e.t1 and tonumber(e.t0[1]) and tonumber(e.t1[1]) then
		return C.curvePts({ a.x, a.y }, { e.t0[1], e.t0[2] }, { b.x, b.y }, { e.t1[1], e.t1[2] }, M.STEP)
	end
	return { { a.x, a.y }, { b.x, b.y } }
end

local function bbox(P)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(P) do
		if p[1] < x0 then x0 = p[1] end
		if p[1] > x1 then x1 = p[1] end
		if p[2] < y0 then y0 = p[2] end
		if p[2] > y1 then y1 = p[2] end
	end
	return x0, y0, x1, y1
end
M.bbox = bbox

--- Do polylines P and Q cross other than at a shared end? sharedP / sharedQ = { [1] = true (its start is shared),
--- [2] = true (its end) }: TRIM_M of a shared end left out.
function M.crosses(P, Q, sharedP, sharedQ)
	sharedP, sharedQ = sharedP or {}, sharedQ or {}
	local p = C.polyTrim(P, sharedP[1] and M.TRIM_M or 0, sharedP[2] and M.TRIM_M or 0)
	local q = C.polyTrim(Q, sharedQ[1] and M.TRIM_M or 0, sharedQ[2] and M.TRIM_M or 0)
	if p == nil or q == nil then return false end
	-- (ends of segments included: two resampled curves often cross exactly at a sample of both, which
	-- ot_check.polyCross counts as touching; the shared ends are trimmed above)
	local x0, y0, x1, y1 = bbox(p)
	local u0, v0, u1, v1 = bbox(q)
	if u0 > x1 or u1 < x0 or v0 > y1 or v1 < y0 then return false end
	for i = 2, #p do
		local a, b = p[i - 1], p[i]
		for j = 2, #q do
			local c, d = q[j - 1], q[j]
			if G.segIntersect(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2], -1e-9) then return true end
		end
	end
	return false
end

-- the nearest interior projection of (x, y) onto polyline Q (perpendicular foot strictly inside Q, not beyond its
-- ends): distance and the segment's unit direction, or nil
local function perpTo(x, y, Q)
	local best, bx, by = nil, nil, nil
	local n = #Q
	for i = 2, n do
		local a, b = Q[i - 1], Q[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l2 = dx * dx + dy * dy
		if l2 > 1e-9 then
			local t = ((x - a[1]) * dx + (y - a[2]) * dy) / l2
			local inside = t >= 0 and t <= 1
			-- (beyond the polyline's own first / last point: not alongside it)
			if (i == 2 and t < 0) or (i == n and t > 1) then inside = false end
			if inside then
				local cx, cy = a[1] + dx * t, a[2] + dy * t
				local d = G.dist(x, y, cx, cy)
				if best == nil or d < best then
					local l = sqrt(l2)
					best, bx, by = d, dx / l, dy / l
				end
			end
		end
	end
	return best, bx, by
end

--- The longest run (m) along polyline P (END_SKIP of each end left out) within lim.parM of one of the polylines in
--- others at most PAR_DEG off its direction.
function M.parallelRun(P, others, lim)
	local D = M.dense(P)
	if D == nil or #D < 2 then return 0 end
	local L = G.polyLen(D)
	local run, best, s = 0, 0, 0
	for i = 2, #D do
		local a, b = D[i - 1], D[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		local mid = s + l / 2
		s = s + l
		local hit = false
		if l > 1e-9 and mid >= M.END_SKIP and mid <= L - M.END_SKIP then
			local ux, uy = (b[1] - a[1]) / l, (b[2] - a[2]) / l
			for j = 1, min(#others, M.SCAN_MAX) do
				local d, vx, vy = perpTo(mx, my, others[j])
				if d ~= nil and d < lim.parM and abs(ux * vx + uy * vy) >= lim.parCos then hit = true break end
			end
		end
		if hit then
			run = run + l
			if run > best then best = run end
		else
			run = 0
		end
	end
	return best
end

--- Polygon area (shoelace, absolute).
function M.area(poly)
	local s = 0
	local n = #poly
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		s = s + a[1] * b[2] - b[1] * a[2]
	end
	return abs(s) / 2
end

--- The shortest way (node positions, from `to` back to `from`) between two node ids through the network nbrs(id) ->
--- { { id, len, x, y } } (positions of the neighbours), within perim; nil when none (or the caps hit). Plain Dijkstra
--- over a list (WALK_MAX settled nodes at most).
function M.way(from, to, nbrs, posOf, perim)
	if from == nil or to == nil or from == to then return nil end
	local dist, prev, done = { [from] = 0 }, {}, {}
	local open = { from }
	local settled = 0
	while #open > 0 do
		local bi, bd = 1, dist[open[1]]
		for i = 2, #open do
			local d = dist[open[i]]
			if d < bd then bi, bd = i, d end
		end
		local u = table.remove(open, bi)
		if not done[u] then
			done[u] = true
			settled = settled + 1
			if settled > M.WALK_MAX then return nil end
			if u == to then
				local path, cur, guard = {}, to, 0
				while cur ~= nil and guard <= M.WALK_MAX do
					local x, y = posOf(cur)
					if x == nil then return nil end
					path[#path + 1] = { x, y }
					cur = prev[cur]
					guard = guard + 1
				end
				return path, bd
			end
			for _, nb in ipairs(nbrs(u) or {}) do
				local v, l = nb[1], nb[2]
				if not done[v] and l == l and l >= 0 then
					local nd = bd + l
					if nd <= perim and (dist[v] == nil or nd < dist[v]) then
						dist[v], prev[v] = nd, u
						open[#open + 1] = v
					end
				end
			end
		end
	end
	return nil
end

--- The area of the loop piece P (from node a to node b) closes with the way back (path from b to a, node positions).
function M.loopArea(P, path)
	local poly = {}
	for _, p in ipairs(P) do poly[#poly + 1] = { p[1], p[2] } end
	-- (path runs from b back to a: its first point is b = P's last, its last a = P's first)
	for i = 2, #path - 1 do poly[#poly + 1] = path[i] end
	return M.area(poly)
end

--- Graph edges near polyline P (ids, at most SCAN_MAX) within pad.
function M.near(g, P, pad)
	local x0, y0, x1, y1 = bbox(P)
	local ids = OG.edgesNear(g, x0, y0, x1, y1, pad)
	if #ids > M.SCAN_MAX then
		local out = {}
		for i = 1, M.SCAN_MAX do out[i] = ids[i] end
		return out
	end
	return ids
end

--- The signed winding of polyline P (radians): the sum of the turns between its steps, a step running from the last
--- kept point to the next point at least WIND_MIN_M from it (two pieces' joint points a few cm apart make no turn).
M.WIND_MIN_M = 2
function M.winding(P)
	local w, px, py = 0, nil, nil
	local n = min(#(P or {}), M.SAMPLES_MAX * M.HOOK_WALK + 2)
	if n < 2 then return 0 end
	local kx, ky = P[1][1], P[1][2]
	for i = 2, n do
		local dx, dy = P[i][1] - kx, P[i][2] - ky
		if dx * dx + dy * dy >= M.WIND_MIN_M * M.WIND_MIN_M then
			if px ~= nil then w = w + G.atan2(px * dy - py * dx, px * dx + py * dy) end
			px, py = dx, dy
			kx, ky = P[i][1], P[i][2]
		end
	end
	return w
end

-- the distance from (x, y) to polyline Q and the nearest point on it
local function polyNear(x, y, Q)
	local best, bx, by = math.huge, nil, nil
	for i = 2, #Q do
		local a, b = Q[i - 1], Q[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l2 = dx * dx + dy * dy
		local t = l2 > 1e-12 and G.clamp(((x - a[1]) * dx + (y - a[2]) * dy) / l2, 0, 1) or 0
		local cx, cy = a[1] + dx * t, a[2] + dy * t
		local d = G.dist(x, y, cx, cy)
		if d < best then best, bx, by = d, cx, cy end
	end
	return best, bx, by
end

--- Is the dead-end street C (a polyline from its junction out to the new dead end, the piece last) a hook? roots = the
--- other streets at its junction (polylines), lim = M.limits(style). Returns "turn" | "back" | nil.
function M.hook(C, roots, lim)
	if C == nil or #C < 2 then return nil end
	-- (the turn over the chain's last hookTurnM: from the first point within it to the end)
	local i0, s0 = #C, 0
	while i0 > 1 do
		local l = G.dist(C[i0 - 1][1], C[i0 - 1][2], C[i0][1], C[i0][2])
		if s0 + l > (lim.hookTurnM or math.huge) then break end
		s0 = s0 + l
		i0 = i0 - 1
	end
	local W = C
	if i0 > 1 then
		W = {}
		for i = i0 - 1, #C do W[#W + 1] = C[i] end
	end
	local w = M.winding(W)
	if w ~= w then return nil end
	if abs(w) > lim.hookTurn then return "turn" end
	local L = G.polyLen(C)
	local far = M.HOOK_ARC_K * lim.hookR
	if not (L >= far) or L == math.huge then return nil end
	local F = C[#C]
	local s = 0
	for i = 1, #C - 1 do
		if i > 1 then s = s + G.dist(C[i - 1][1], C[i - 1][2], C[i][1], C[i][2]) end
		if L - s < far then break end
		if G.dist(F[1], F[2], C[i][1], C[i][2]) < lim.hookR then return "back" end
		local d = G.pointSegDist(F[1], F[2], C[i][1], C[i][2], C[i + 1][1], C[i + 1][2])
		if d < lim.hookR and L - s - G.dist(C[i][1], C[i][2], C[i + 1][1], C[i + 1][2]) >= far then return "back" end
	end
	-- (the junction's other streets: only an end heading toward one (within HOOK_TOWARD_DEG) comes back to it; a lane
	-- beside a parallel back street is the knot rule's)
	local E0 = C[#C - 1]
	local ex, ey = F[1] - E0[1], F[2] - E0[2]
	local el = sqrt(ex * ex + ey * ey)
	local cosT = math.cos(math.rad(M.HOOK_TOWARD_DEG))
	if el > 1e-9 then
		for j = 1, min(#(roots or {}), M.SCAN_MAX) do
			local Q = roots[j]
			if Q and #Q >= 2 then
				local d, nx, ny = polyNear(F[1], F[2], Q)
				if d < lim.hookR and (d < 1e-6 or ((nx - F[1]) * ex + (ny - F[2]) * ey) / (d * el) >= cosT) then return "back" end
			end
		end
	end
	return nil
end

--- Tally text "<cross>/<parallel>/<loop>".
function M.text(t)
	t = t or {}
	return string.format("%d/%d/%d", t.cross or 0, t.parallel or 0, t.loop or 0)
end

return M
