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
--   * parallel: for at least PAR_RUN (PAR_RUN_K x block length, PAR_RUN_MIN..PAR_RUN_MAX) the street runs within PAR_M
--     (PAR_K x block depth, PAR_MIN..PAR_MAX) of another street, or of itself further along, at most PAR_DEG off its
--     direction. §75 (2026-10-19; user shots: a street 200 m+ beside a main street ~45 m away, a side street running
--     back beside its street): measured on the whole street through the piece (chainBehind: back through nodes with two
--     streets, CHAIN_WALK / CHAIN_BACK_M; streetLine), END_SKIP left out only at a junction end (its approach), the run
--     reaching PIECE_RUN_M into the piece; before, END_SKIP at both ends of each piece of at most 100 m (maxSeg) left
--     at most 40 m, under the 60 m run, so the rule never fired, and PAR_MAX 35 m missed a street ~45 m off;
--   * loop: the piece closes a loop (its ends already joined by the network) enclosing less than LOOP_K x a block's
--     area (len x depth): a lasso, a sliver between two curves.
--   * row (§75 follow-up, 2026-10-19, ROW below): a piece leaving a new dead end beside one of the mod's own streets
--     that has no house yet (or a piece chosen in the same increment), within rowM (~1.2 block depths) for rowNeed m:
--     one empty row at a time.
-- ot_select applies them to steer towns' pieces (cross / loop: not motif / ring / connector pieces, relaxed only when
-- the increment would be empty, as the §69 rake / wiggle rules; parallel: connectors too, never relaxed; row: organic
-- growers, not motif / ring / crescent / connector pieces, never relaxed) with a fourth, `side` (ot_check.sideBad);
-- ot_nearmiss applies parallel / loop to its joins. Every loop is capped (SCAN_MAX, WALK_MAX, CHAIN_WALK, the samples
-- per polyline).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local C = ug_require "square_organic_towns::/organic_towns/ot_check.lua"

local M = {}

local abs, sqrt, min, max = math.abs, math.sqrt, math.min, math.max

M.ON = true
M.TRIM_M = 6              -- m of a polyline's end at a shared node left out of the crossing test
M.PAR_K = 0.9             -- near-parallel: within this x the block depth (§75, was 0.65: just under the style's own
                          -- lattice, whose lanes and back rows lie a block depth apart, at least ot_style.MIN_BLOCK 44 m:
                          -- EU organic 45 m blocks -> 40.5 m, MED hill 30 -> 27 m) ...
M.PAR_MIN = 20            -- ... at least (m; two small streets' bodies need 16) ...
M.PAR_MAX = 50            -- ... at most (m; §75, was 35: two 16 m streets and one row of the deepest 4-cell lots, 32 m,
                          -- are 48 m apart; closer, the two streets share one row of houses and the back street serves
                          -- none of its own: the user's 40-50 m parallel street, 2026-10-19; EU extension's 80 m blocks
                          -- and every larger style reach it)
M.PAR_DEG = 25            -- deg: at most this off the other street's direction
M.PAR_RUN_K = 1.0         -- for at least this x the block length ...
M.PAR_RUN_MIN = 60        -- ... at least (m) ...
M.PAR_RUN_MAX = 200       -- ... at most (m; §75: the superblock's 350 m blocks; the chain walk reaches this far)
M.END_SKIP = 30           -- m at a junction end of the street not counted for the parallel run (its approach); before
                          -- §75 at both ends of every piece, so a piece of at most 100 m (maxSeg) never reached 60 m
M.PIECE_RUN_M = 30        -- §75: m of the run at least on the piece itself (or half of it)
M.CHAIN_WALK = 8          -- §75: street edges walked behind each end of a piece at most ...
M.CHAIN_BACK_M = 300      -- ... and m
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
-- one empty row at a time (§75 follow-up, 2026-10-19; user shot 5 of run 2026-10-19_1949_sqot: three long empty parallel
-- dead-end lanes ~45 m apart at an organic town's grass edge, no houses: the lattice's lanes / back rows laid by demand
-- plans ahead of the houses; PAR_K 0.9 keeps the parallel rule just under the lattice's own spacing on purpose): a steer
-- town's piece that leaves a new dead end must not run beside one of the mod's own streets that has no house yet, within
-- rowM (ROW_K x the block depth, at least ROW_DEPTH_MIN = ot_style.MIN_BLOCK, the lattice's least row spacing; at most
-- ROW_MAX) for rowNeed m (ROW_RUN_M, or ROW_RUN_K of a shorter piece, at least ROW_RUN_MIN), at most PAR_DEG off its
-- direction: the next row waits for the houses on the first one. A piece closing a block (no new dead end) passes.
-- ot_select applies it (`row`, organic growers, not motif / ring / crescent / connector pieces; never relaxed).
M.ROW = true
M.ROW_K = 1.2
M.ROW_DEPTH_MIN = 44
M.ROW_MAX = 80
M.ROW_RUN_M = 40
M.ROW_RUN_K = 0.6
M.ROW_RUN_MIN = 20
M.ROW_HOUSED = 1          -- a street with this many buildings has houses

--- The limits for a style's block: { parM, parRun, parCos, loopA, perim }.
function M.limits(style)
	local b = style and style.block or {}
	local len, depth = tonumber(b.len) or 60, tonumber(b.depth) or 45
	return { parM = G.clamp(M.PAR_K * depth, M.PAR_MIN, M.PAR_MAX),
		parRun = G.clamp(M.PAR_RUN_K * len, M.PAR_RUN_MIN, M.PAR_RUN_MAX),
		parCos = math.cos(math.rad(M.PAR_DEG)), loopA = M.LOOP_K * len * depth, perim = M.LOOP_PERIM_K * (len + depth),
		hookR = G.clamp(M.HOOK_K * depth, M.HOOK_MIN, M.HOOK_MAX), hookTurn = math.rad(M.HOOK_DEG),
		hookTurnM = G.clamp(M.HOOK_TURN_K * len, M.HOOK_TURN_MIN, M.HOOK_TURN_MAX),
		rowM = min(M.ROW_MAX, M.ROW_K * max(M.ROW_DEPTH_MIN, depth)) }
end

--- One empty row at a time: the run (m) a piece of length L must have beside an empty street of ours to wait.
function M.rowNeed(L)
	L = tonumber(L) or 0
	if L ~= L then L = 0 end
	return max(M.ROW_RUN_MIN, min(M.ROW_RUN_M, M.ROW_RUN_K * L))
end

--- One empty row at a time: is graph edge e one of the mod's own streets (locked, built this session `own`, or an
--- offline increment's) without a house yet? Unknown house counts (no `built`) never count.
function M.emptyOurs(e)
	if e == nil or e.built == nil then return false end
	if not (e.locked == true or e.own == true or e.increment ~= nil) then return false end
	return (tonumber(e.built) or 0) < M.ROW_HOUSED
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

-- (§75) is (x, y) at arc position s within lim.parM of polyline D itself, beside a segment at least SELF_ARC_K x parM
-- of arc away (a street bent back beside itself at a sharp node), at most PAR_DEG off direction (ux, uy)?
M.SELF_ARC_K = 3
local function selfNear(D, cum, x, y, s, ux, uy, lim)
	local far = M.SELF_ARC_K * lim.parM
	for j = 2, #D do
		local a, b = D[j - 1], D[j]
		if abs((cum[j - 1] + cum[j]) / 2 - s) > far then
			local dx, dy = b[1] - a[1], b[2] - a[2]
			local l2 = dx * dx + dy * dy
			if l2 > 1e-9 then
				local t = ((x - a[1]) * dx + (y - a[2]) * dy) / l2
				if t >= 0 and t <= 1 and G.dist(x, y, a[1] + dx * t, a[2] + dy * t) < lim.parM then
					local l = sqrt(l2)
					if abs(ux * dx / l + uy * dy / l) >= lim.parCos then return true end
				end
			end
		end
	end
	return false
end

--- The longest run (m) along polyline P within lim.parM of one of the polylines in others at most PAR_DEG off its
--- direction. o = { skip0, skip1 (m at P's start / end not counted; default END_SKIP each), s0, s1 (only a run reaching
--- into P's arc range s0..s1 counts: the piece within the whole street, §75, with at least min(PIECE_RUN_M, half the
--- range) of it inside the range: a piece turning away from a street that already runs beside one is no knot), self (P
--- beside itself counts too, parts at least SELF_ARC_K x parM of arc apart) }; without o as before §75 (both ends
--- skipped, any run).
function M.parallelRun(P, others, lim, o)
	local D = M.dense(P)
	if D == nil or #D < 2 then return 0 end
	local L = G.polyLen(D)
	local cum = nil
	if o and o.self then
		cum = { 0 }
		for i = 2, #D do cum[i] = cum[i - 1] + G.dist(D[i - 1][1], D[i - 1][2], D[i][1], D[i][2]) end
	end
	local skip0 = o and o.skip0 or M.END_SKIP
	local skip1 = o and o.skip1 or M.END_SKIP
	local s0, s1 = o and o.s0 or 0, o and o.s1 or L
	local need = (o and o.s0) and min(M.PIECE_RUN_M, 0.5 * (s1 - s0)) or 0
	local run, best, s, inP = 0, 0, 0, 0
	for i = 2, #D do
		local a, b = D[i - 1], D[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		local mid = s + l / 2
		s = s + l
		local hit = false
		if l > 1e-9 and mid >= skip0 and mid <= L - skip1 then
			local ux, uy = (b[1] - a[1]) / l, (b[2] - a[2]) / l
			for j = 1, min(#others, M.SCAN_MAX) do
				local d, vx, vy = perpTo(mx, my, others[j])
				if d ~= nil and d < lim.parM and abs(ux * vx + uy * vy) >= lim.parCos then hit = true break end
			end
			if not hit and cum then hit = selfNear(D, cum, mx, my, mid, ux, uy, lim) end
		end
		if hit then
			run = run + l
			if mid >= s0 - 1e-6 and mid <= s1 + 1e-6 then inP = inP + l end
			if inP > 0 and inP >= need - 1e-6 and run > best then best = run end
		else
			run, inP = 0, 0
		end
	end
	return best
end

--- §75: the street behind node `id` away from the piece tagged `own`, walked through nodes with exactly one other
--- street (streetsAt(id) -> { { other id, pts from id outward, tag } }), at most CHAIN_WALK edges / CHAIN_BACK_M m, each
--- node once. Returns the polylines (each from its node outward, in walk order), the tags walked { [tag] = true } and
--- how it ends: "junction" (a node with 3+ streets), "end" (a dead end, or no street at all) or "cap".
function M.chainBehind(id, own, streetsAt)
	local polys, tags = {}, {}
	local cur, came, back = id, own, 0
	local seen = { [id] = true }
	for _ = 1, M.CHAIN_WALK + 1 do
		local list = {}
		for _, x in ipairs(streetsAt(cur) or {}) do
			if x[3] ~= came and x[3] ~= own and not tags[x[3]] then list[#list + 1] = x end
		end
		if #list == 0 then return polys, tags, "end" end
		if #list >= 2 then return polys, tags, "junction" end
		if #polys >= M.CHAIN_WALK or back >= M.CHAIN_BACK_M then return polys, tags, "cap" end
		local nx = list[1]
		polys[#polys + 1] = nx[2]
		tags[nx[3]] = true
		local l = G.polyLen(nx[2])
		back = back + ((l == l) and l or M.CHAIN_BACK_M)
		if seen[nx[1]] then return polys, tags, "cap" end
		seen[nx[1]] = true
		cur, came = nx[1], nx[3]
	end
	return polys, tags, "cap"
end

--- §75: the graph's streets at node id for chainBehind: { { other id, curve from id outward, "e<edge id>" } } (curves by
--- M.edgePts; curveOf(e) overrides, e.g. a cache).
function M.graphAt(g, id, curveOf)
	local out = {}
	for _, eid in ipairs(g.adj[id] or {}) do
		local e = g.edgeById[eid]
		local Q = e and ((curveOf and curveOf(e)) or M.edgePts(g, e))
		if Q then
			local R = Q
			if e.n0 ~= id then
				R = {}
				for i = #Q, 1, -1 do R[#R + 1] = Q[i] end
			end
			out[#out + 1] = { OG.other(e, id), R, "e" .. tostring(eid) }
		end
	end
	return out
end

--- §75: the whole street through piece P (from its node a to its node b) as one polyline: the chain behind a (polysA,
--- from a outward), P, the chain behind b; the piece's arc range on it (s0, s1) and the skips (END_SKIP at an end that
--- is a junction: its approach). Returns C, s0, s1, skip0, skip1.
function M.streetLine(P, polysA, endA, polysB, endB)
	local C = {}
	local function add(p)
		local q = C[#C]
		if q == nil or abs(q[1] - p[1]) > 1e-6 or abs(q[2] - p[2]) > 1e-6 then C[#C + 1] = { p[1], p[2] } end
	end
	for i = #(polysA or {}), 1, -1 do
		local Q = polysA[i]
		for j = #Q, 1, -1 do add(Q[j]) end
	end
	local s0 = #C >= 2 and G.polyLen(C) or 0
	for _, p in ipairs(P) do add(p) end
	local s1 = G.polyLen(C)
	for _, Q in ipairs(polysB or {}) do
		for _, p in ipairs(Q) do add(p) end
	end
	return C, s0, s1, endA == "junction" and M.END_SKIP or 0, endB == "junction" and M.END_SKIP or 0
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

---------------------------------------------------------------------------
-- The empty-row measure (2026-10-20, PLAN §75 "Follow-ups built"; SNAPSHOT `emptyRows=`, debug log): how much of the
-- town's own empty street runs as a row beside another (the shape the row rule holds), so a run shows whether the rule
-- cuts them in game. An edge counts when it is one of the mod's own streets without a house (emptyOurs: locked, or
-- built this session) and runs ROWS_RUN_M or more within the row distance (limits().rowM) of another such edge (not
-- one it shares a node with: its own street's next piece), at most PAR_DEG off its direction; a dead-end edge (an end
-- node with no other street) counts in deadM too. The offline metric of the row rule's table. Computed only when the
-- line is written; at most ROWS_EDGES_MAX edges measured (the rest: `capped`), SCAN_MAX neighbours each.
M.ROWS_RUN_M = 40
M.ROWS_EDGES_MAX = 400

--- { m = metres of row edges, deadM = of those at a dead end, n = edges, cand = empty edges of ours, capped = edges
--- not measured } for graph g and the style's limits lim (KN.limits); nil when g carries no house counts.
function M.emptyRows(g, lim)
	if g == nil or not g.hasBuilt or lim == nil or not tonumber(lim.rowM) then return nil end
	local out = { m = 0, deadM = 0, n = 0, cand = 0, capped = 0 }
	local isCand, cand = {}, {}
	for _, e in ipairs(g.edges or {}) do
		if M.emptyOurs(e) then
			isCand[e.id] = true
			cand[#cand + 1] = e
		end
	end
	out.cand = #cand
	if #cand < 2 then return out end
	local rl = { parM = lim.rowM, parCos = lim.parCos or math.cos(math.rad(M.PAR_DEG)) }
	local ptsOf = {}
	local function pts(e)
		local P = ptsOf[e.id]
		if P == nil then
			P = M.edgePts(g, e) or false
			ptsOf[e.id] = P
		end
		return P or nil
	end
	for i, e in ipairs(cand) do
		if i > M.ROWS_EDGES_MAX then
			out.capped = #cand - M.ROWS_EDGES_MAX
			break
		end
		local P = pts(e)
		local L = P and G.polyLen(P) or 0
		if L >= M.ROWS_RUN_M then
			local others = {}
			for _, id in ipairs(M.near(g, P, lim.rowM)) do
				local f = g.edgeById[id]
				if f and f ~= e and isCand[f.id] and f.n0 ~= e.n0 and f.n0 ~= e.n1 and f.n1 ~= e.n0 and f.n1 ~= e.n1 then
					local Q = pts(f)
					if Q then others[#others + 1] = Q end
				end
			end
			if #others > 0 and M.parallelRun(P, others, rl, { skip0 = 0, skip1 = 0 }) >= M.ROWS_RUN_M then
				out.n = out.n + 1
				out.m = out.m + L
				if OG.degree(g, e.n0) == 1 or OG.degree(g, e.n1) == 1 then out.deadM = out.deadM + L end
			end
		end
	end
	return out
end

--- SNAPSHOT `emptyRows=` text: "<m>/<dead-end m>/<edges>" (whole metres; "+<capped>" when edges were left out), "-"
--- without house counts.
function M.rowsText(r)
	if r == nil then return "-" end
	local t = string.format("%.0f/%.0f/%d", r.m or 0, r.deadM or 0, r.n or 0)
	if (r.capped or 0) > 0 then t = t .. "+" .. r.capped end
	return t
end

--- Tally text "<cross>/<parallel>/<loop>/<side>/<row>" (row: one empty row at a time, 2026-10-19).
function M.text(t)
	t = t or {}
	return string.format("%d/%d/%d/%d/%d", t.cross or 0, t.parallel or 0, t.loop or 0, t.side or 0, t.row or 0)
end

return M
