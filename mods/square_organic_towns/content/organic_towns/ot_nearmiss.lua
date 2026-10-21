-- Organic Towns: close the gap, near-miss dead ends joined to the street ahead (pure; §74, 2026-10-17; PLAN.md 6.2
-- "Close the gap (§74)").
--
-- The user (2026-10-17): "Is it feasible to have our roads connect to each other slightly more logically when they are
-- so close? I like the loose and organic, but sometimes it feels a little too random". Three cases in the shots: two dead
-- ends curling past each other 20-40 m apart; a stub ending 10-30 m beside a junction / another street; a stub ending a
-- few metres short of the side of a street, pointing at it.
--
-- Why they happen (from the code; the logs hold no per-edge geometry): the planner joins only existing DEAD ENDS
-- (ot_plan join "deadEnd": a street may never end at a node in the middle of a street, the D3 joint verified in game
-- is a dead end's), and the selector's pieces come from the master plan's lattice, which knows nothing of the streets
-- already there: a piece whose middle lies within occR (8-30 m) of a street or crosses one is blocked
-- (ot_select.classifyPiece), a planned edge within clearEdge (16 m centre line, i.e. ~8 m of open ground between two
-- small streets' kerbs) of a street it doesn't meet is dropped (`nearExisting`), a new node within 6 m of a street is
-- refused (`blockedNode`). A dead end only joins another when a lattice junction happens to lie within snapR (8 m) of
-- it (or a connector to a lattice junction, ot_select). So every lattice front that meets an existing street stops one
-- piece short of it, and two fronts from different lattices pass each other. The game's own growth adds cul-de-sacs.
--
-- The pass (M.joins, after each increment's plan, ot_core.planIncrement opts.nearMiss): for each joinable dead end D
-- with another street within JOIN_MAX ahead (AHEAD_DEG of its heading), the nearest target nodes N ahead within NODE_MAX
-- (another dead end: a bend joining both, case 1; a node in the middle of a street (degree 2: a T, case 3) or a small
-- junction (degree 3: a crossroads, case 2), where the driver allows it, `midOk`; never a country road's node) are
-- tried, cheapest checks first (2026-10-18 "less cautious": KINK_DEG 45, ARC_MIN 74, NODE_MAX 100, GEN_SHAPES, the
-- chance, retired dead ends through o.retiredOk; PLAN.md §74):
--   * shapes (M.shapes, best first): the straight line, one circular arc (>= ARC_MIN), an arc of ARC_R and a straight
--     either way, Hermite curves; leaving D at most KINK_DEG off its street, meeting a dead end N at most KINK_DEG off
--     N's street or a street node TEE_MIN_DEG (60, the side-street rule, §75) or more off every street there (the base
--     town templates build curves down to 60 m; ot_plan keeps its edges at MIN_RADIUS 70); for a pair also the corner
--     (M.corner, §75: both streets straight on to where they meet, a 45-100 deg block corner at a new node);
--   * on the shape: buildings (centres within BUILD_CLEAR: the engine's pre-check refuses the rest, the driver then
--     excludes the join's key for the session), the town's gap lines (ot_gap), industry zones, green reserves, country
--     roads beyond the snapshot;
--   * ot_plan with that one street (its angles, the side rule at sideAngle 60, footprints, chord clearance, slope,
--     water; `joinExtra` lets it end at the street node);
--   * on the planned curve: slope (node heights and the ground, style.maxSlope <= the templates' 0.2), water, streets
--     crossed or passed within CLEAR, §70 knots (a long near-parallel run over the whole street the join makes, §75
--     M.parallelKnot; a loop under LOOP_K x a block), another junction within JUNCTION_GAP of a street node.
-- A dead end with a passing join keeps it with a seeded chance falling with the gap (P_NEAR up to SURE_M, P_FAR at
-- JOIN_MAX: the pair's draw is fixed, so a pair left by chance stays left), less through big woods (FOREST_KEEP; a
-- deep forest town DEEP_KEEP; §75: WOOD_RUN_M of the join's own curve in big-wood cells, not a wood near it); the
-- nearest go first, at most MAX_PER_INC per increment, none touching a node the
-- increment already uses. otherTown / no-config dead ends stay out (their noJoin), a retired one unless o.retiredOk
-- allows it; a snapshot dead end the game sees more streets at is the snapshot's cut (`cut`). Report: found (dead ends
-- with a street within JOIN_MAX ahead; a pair join counts both), joined, kept, why, joins ("<kind>:<gap>" + "c" a
-- corner, "r" closing a retired dead end). Every loop is capped (MAX_DEAD,
-- MAX_TARGETS, MAX_TESTS, MAX_PLANS, MAX_SHAPES, the scans and the arc walks), and o.clock / o.budgetUs bound the time.
-- o.trace(D, N, reason, gap, heading) is a test hook. Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local C = ug_require "square_organic_towns::/organic_towns/ot_check.lua"
local P = ug_require "square_organic_towns::/organic_towns/ot_plan.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local KN = ug_require "square_organic_towns::/organic_towns/ot_knot.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local SEL = ug_require "square_organic_towns::/organic_towns/ot_select.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local LN = ug_require "square_organic_towns::/organic_towns/ot_lane.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

local abs, min, max, rad = math.abs, math.min, math.max, math.rad

M.ON = true
M.JOIN_MAX = 80          -- m: a street at most this far ahead of a dead end makes it a near miss (about 1.5 blocks:
                         -- farther, a join is a new street, the grower's job; the curve's radius limits it anyway)
M.NODE_MAX = 100         -- m: target nodes this far (the street ahead within JOIN_MAX; 2026-10-18, was JOIN_MAX: the
                         -- next node of a long street ahead often lies just beyond 80 m, `noNode`)
M.AHEAD_DEG = 60         -- deg: ... within this of the dead end's heading (its street's tangent or its last chord)
M.SURE_M = 25            -- m: up to this gap a passing join is near certain (2026-10-18 loosened: 15) ...
M.P_NEAR = 0.97          -- ... with this chance ...
M.P_FAR = 0.4            -- ... falling linearly to this at JOIN_MAX (2026-10-18 loosened: 0.15; in game `chance` kept
                         -- 86 against 20 joined)
M.MAX_PER_INC = 2        -- joins per increment at most
M.MAX_DEAD = 150         -- dead ends looked at per call at most
M.MAX_TARGETS = 6        -- target nodes tried per dead end at most (nearest first)
M.MAX_TESTS = 48         -- target nodes tried per call at most
M.MAX_PLANS = 40         -- single-street plans (ot_plan) per call at most (the shapes of the targets; ~0.2-0.3 ms each)
M.KINK_DEG = 45          -- deg: the join leaves a dead end at most this far off its street, at both ends of a pair
                         -- (2026-10-18 loosened: 35; still under ot_select JOINT_TURN 60, the planner's own joints)
M.TEE_MIN_DEG = 60       -- deg: at a street node the join meets every street there at least this far off (§75, was
                         -- 50: a side street leaves at 60-120 deg, ot_check LIMITS.sideAngle, which ot_plan holds here too)
M.MAX_TURN_DEG = 120     -- deg: the curve turns at most this much end to end
M.DETOUR = 1.45          -- the curve at most this x the straight distance
M.CLEAR = 16             -- m: kept from streets the join doesn't meet (two small streets' bodies, ot_plan clearEdge) ...
M.END_SKIP = 12          -- ... its first / last this many m left out (the joints)
M.BUILD_CLEAR = 12       -- m: no building centre this near the curve
M.JUNCTION_GAP = 20      -- m: a street node joined at least this far from another junction (degree >= 3)
M.JUNCTION_JOIN = true   -- degree-3 nodes of small streets may become crossroads
M.FOREST_KEEP = 0.5      -- a join through a big wood (hug towns) is left with this chance ...
M.DEEP_KEEP = 0.75       -- ... in a deep forest town with this
M.WOOD_RUN_M = 16        -- m of the join's curve in big-wood cells (ot_forest.bigWoodAt) make it a join through the woods
                         -- (§75, 2026-10-19: was a big wood within FOREST_R 40 m of its middle or the dead end, true for
                         -- almost every join in a forest town, also those closing a block on cleared town land)
M.LOOP_K = 0.25          -- a join closing a loop under this x a block's area (len x depth) is a knot (ot_knot's LOOP_K
                         -- 0.5 is for new pieces out in the field; closing a block between two streets is the point here)
M.STEP = 8               -- m between the curve's samples
M.AHEAD_STEP = 5         -- m between samples along other streets (the ahead scan)
M.SCAN_EDGES = 200       -- edges scanned per dead end at most
M.BUILD_CELL = 50        -- m: the buildings' hash cell

M.SMALL = { small = true, xsmall = true }
-- the planner's refusals of a join as kept reasons (ot_plan dropped reasons)
M.PLAN_WHY = { steep = "slope", water = "water", crossesExisting = "cross", nearExisting = "near", curve = "curve",
	angle = "angle", footprint = "footprint", blockedNode = "near", short = "curve" }
-- reasons of the shape rather than the place: a later shape's other refusal names the candidate instead
M.SHAPE_WHY = { curve = true, angle = true, footprint = true, plan = true }

--- The chance a passing join of gap d (m) is built.
function M.chance(d)
	if d == nil or d ~= d then return 0 end
	if d <= M.SURE_M then return M.P_NEAR end
	if d >= M.JOIN_MAX then return M.P_FAR end
	return M.P_NEAR - (M.P_NEAR - M.P_FAR) * (d - M.SURE_M) / (M.JOIN_MAX - M.SURE_M)
end

--- The dead end's outward headings (radians): its street's tangent continued, and its last edge's chord continued; nil
--- when id is no dead end.
function M.outHeadings(g, id)
	local adj = g.adj[id]
	if adj == nil or #adj ~= 1 then return nil end
	local e = g.edgeById[adj[1]]
	if e == nil then return nil end
	local n, f = g.nodeById[id], g.nodeById[OG.other(e, id)]
	if n == nil or f == nil then return nil end
	local h = G.wrap(OG.headingFrom(g, e, id) + math.pi)
	local hc = G.heading(f.x, f.y, n.x, n.y)
	return h, hc, e, f
end

local function aheadOk(hs, b, lim)
	for _, h in ipairs(hs) do
		if h and G.angleDiff(h, b) <= lim then return true end
	end
	return false
end

--- Distance (m) from dead end `id` to the nearest point of another street (not one at the dead end or at its street's
--- other node) within R and AHEAD_DEG ahead, or nil. Samples every AHEAD_STEP m along the chords.
function M.aheadDist(g, id, R)
	R = R or M.JOIN_MAX
	local h, hc, e, f = M.outHeadings(g, id)
	if h == nil then return nil end
	local n = g.nodeById[id]
	local lim = rad(M.AHEAD_DEG)
	local hs = { h, hc }
	local best = nil
	local ids = OG.edgesNear(g, n.x, n.y, n.x, n.y, R)
	for i = 1, min(#ids, M.SCAN_EDGES) do
		local o = g.edgeById[ids[i]]
		local a, b = o and g.nodeById[o.n0], o and g.nodeById[o.n1]
		if o and o.n0 ~= id and o.n1 ~= id and o.n0 ~= f.id and o.n1 ~= f.id
			and G.pointSegDist(n.x, n.y, a.x, a.y, b.x, b.y) <= R and (best == nil or G.pointSegDist(n.x, n.y, a.x, a.y, b.x, b.y) < best) then
			local L = G.dist(a.x, a.y, b.x, b.y)
			local k = max(1, math.min(400, math.ceil(L / M.AHEAD_STEP)))
			for s = 0, k do
				local x, y = a.x + (b.x - a.x) * s / k, a.y + (b.y - a.y) * s / k
				local d = G.dist(n.x, n.y, x, y)
				if d <= R and (best == nil or d < best) and d > 1e-6 and aheadOk(hs, G.heading(n.x, n.y, x, y), lim) then
					best = d
				end
			end
		end
	end
	return best
end

--- Share of g's dead ends with another street within R ahead (the near-miss share; tests and the audit), and the count.
function M.nearShare(g, R)
	local des = OG.deadEnds(g)
	if #des == 0 then return 0, 0, 0 end
	local n = 0
	for i = 1, min(#des, 5000) do
		if M.aheadDist(g, des[i], R) then n = n + 1 end
	end
	return n / #des, n, #des
end

-- free angle at a street node: the middle of the gap between its streets' headings that holds heading `toward`, and
-- the gap's width (radians); nil without one
local function freeGap(hs, toward)
	local list = {}
	for _, h in ipairs(hs) do list[#list + 1] = (h % (2 * math.pi)) end
	table.sort(list)
	local n = #list
	if n == 0 then return nil end
	local t = toward % (2 * math.pi)
	for i = 1, n do
		local a = list[i]
		local b = list[i % n + 1]
		local w = b - a
		if w <= 0 then w = w + 2 * math.pi end
		local d = t - a
		if d < 0 then d = d + 2 * math.pi end
		if d <= w then return G.wrap(a + w / 2), w end
	end
	return nil
end

local function unitOf(h) return { math.cos(h), math.sin(h) } end

--- The end rule at N for a new street leaving N at heading `leave`: a dead end (one street, pair) within KINK_DEG of
--- its street continued; a street node (tee / cross) TEE_MIN_DEG or more off every street there. Returns ok, the
--- deviation (radians: off the straight continuation, or off the middle of the free angle).
function M.endOk(armsN, leave, slack)
	slack = slack or 1e-9
	if #armsN == 1 then
		local d = G.angleDiff(leave, armsN[1] + math.pi)
		return d <= rad(M.KINK_DEG) + slack, d
	end
	local worst = math.huge
	for _, a in ipairs(armsN) do worst = min(worst, G.angleDiff(a, leave)) end
	return worst >= rad(M.TEE_MIN_DEG) - slack, math.max(0, math.pi / 2 - worst)
end

M.ARC_R = { 100, 150, 240 }  -- m: the arc-and-straight shapes' radii
M.MAX_SHAPES = 4            -- shapes per target planned at most (ot_plan) ...
M.GEN_SHAPES = 8            -- ... out of this many tried on the place checks (a shape over a house, the water or a
                            -- gap line costs no plan: the next one may pass beside it; 2026-10-18, was 4)
M.ARC_MIN = 74              -- m: a single circular arc's radius at least (ot_plan.MIN_RADIUS 70 for its cut edges;
                            -- 2026-10-18 loosened: 78)
-- §75 (2026-10-19; user: two dead ends ~60-80 m apart at right angles in a forest town, "the obvious corner join closing
-- the block was never made"): a pair's corner, both streets straight on to where they meet, turning there between
-- CORNER_MIN_DEG (ot_check cornerFrom: a smaller turn is a kink, and the arcs reach it) and CORNER_MAX_DEG (a block
-- corner, not a hairpin), each leg at least CORNER_LEG_MIN (two junction footprints); a new node at the corner. The arcs
-- can't: a quarter turn at ARC_MIN needs dead ends 105 m apart.
M.CORNER = true
M.CORNER_MIN_DEG = 45
M.CORNER_MAX_DEG = 100
M.CORNER_LEG_MIN = 20

-- an arc of radius R from (x, y) at heading a turning toward (xN, yN) until the straight line to it is tangent, then the
-- line: a smooth polyline carrying unit tangents ({x, y, ux, uy}), or nil (the target inside the circle / behind)
local function arcLine(x, y, a, R, xN, yN)
	local s = G.wrap(G.heading(x, y, xN, yN) - a) >= 0 and 1 or -1
	local cx, cy = x + R * math.cos(a + s * math.pi / 2), y + R * math.sin(a + s * math.pi / 2)
	if G.dist(cx, cy, xN, yN) <= R + 1 then return nil end
	local pts = { { x, y, math.cos(a), math.sin(a) } }
	local step = math.min(rad(4), 5 / R)
	local ang = a - s * math.pi / 2     -- the point's angle seen from the centre
	local h = a
	local turned = 0
	for _ = 1, 400 do
		local px, py = cx + R * math.cos(ang), cy + R * math.sin(ang)
		local toN = G.heading(px, py, xN, yN)
		if s * G.wrap(toN - h) <= 0 then break end
		turned = turned + step
		if turned > rad(M.MAX_TURN_DEG) then return nil end
		ang = ang + s * step
		h = h + s * step
		local qx, qy = cx + R * math.cos(ang), cy + R * math.sin(ang)
		pts[#pts + 1] = { qx, qy, math.cos(h), math.sin(h) }
	end
	local last = pts[#pts]
	local L = G.dist(last[1], last[2], xN, yN)
	if L < 1 then return nil end
	local ux, uy = (xN - last[1]) / L, (yN - last[2]) / L
	last[3], last[4] = ux, uy
	local n = math.max(1, math.ceil(L / 10))
	for k = 1, n do
		pts[#pts + 1] = { last[1] + (xN - last[1]) * k / n, last[2] + (yN - last[2]) * k / n, ux, uy }
	end
	return pts, G.atan2(uy, ux)
end

-- the circular arc from (x, y) leaving at heading a through (xN, yN): a smooth polyline carrying unit tangents and the
-- heading arriving there, or nil when its radius is under rMin (straight on: the line)
local function arcThrough(x, y, a, xN, yN, rMin)
	local L = G.dist(x, y, xN, yN)
	local d = G.wrap(G.heading(x, y, xN, yN) - a)
	if abs(d) >= math.pi / 2 then return nil end
	local sn = math.sin(abs(d))
	local r = sn > 1e-9 and L / (2 * sn) or math.huge
	if r < rMin then return nil end
	local turn = 2 * d
	local arc = r < math.huge and r * abs(turn) or L
	local n = math.max(2, math.ceil(arc / 6))
	local pts = {}
	if r == math.huge then
		for k = 0, n do pts[#pts + 1] = { x + (xN - x) * k / n, y + (yN - y) * k / n, math.cos(a), math.sin(a) } end
		return pts, a
	end
	local s = d >= 0 and 1 or -1
	local cx, cy = x + r * math.cos(a + s * math.pi / 2), y + r * math.sin(a + s * math.pi / 2)
	local ang0 = a - s * math.pi / 2
	for k = 0, n do
		local t = turn * k / n
		local h = a + t
		pts[#pts + 1] = { cx + r * math.cos(ang0 + t), cy + r * math.sin(ang0 + t), math.cos(h), math.sin(h) }
	end
	pts[#pts][1], pts[#pts][2] = xN, yN
	return pts, a + turn
end

--- Candidate shapes of a join from dead end D (outward heading hD) to node N (its streets leaving N at armsN): a list
--- of { pts (a smooth polyline carrying unit tangents), kind = "pair"|"tee"|"cross", kinkD, score } best first, or
--- nil, why ("angle": no shape meets the end rules, "curve": none bends gently enough). Shapes: the straight line (D's
--- kink allowing), an arc of ARC_R then straight, a Hermite curve (end directions tried at D within KINK_DEG, at N
--- the straight continuation / the free angle); ot_plan decides on each.
function M.shapes(xD, yD, hD, xN, yN, armsN)
	local L = G.dist(xD, yD, xN, yN)
	if L < 1e-6 then return nil, "short" end
	local kind = #armsN == 1 and "pair" or (#armsN == 2 and "tee" or "cross")
	local bear = G.heading(xD, yD, xN, yN)
	local kink = rad(M.KINK_DEG)
	local s = G.wrap(bear - hD) >= 0 and 1 or -1
	local out = {}
	local why = "angle"
	local rMin = P.MIN_RADIUS
	local function add(pts, leave, kinkD, score)
		local okE, dev = M.endOk(armsN, leave)
		if not okE then return end
		out[#out + 1] = { pts = pts, kind = kind, kinkD = kinkD, score = score + 0.5 * dev }
	end
	-- the straight line
	if G.angleDiff(bear, hD) <= kink then
		local n = math.max(1, math.ceil(L / 10))
		local pts = {}
		for k = 0, n do
			pts[#pts + 1] = { xD + (xN - xD) * k / n, yD + (yN - yD) * k / n, math.cos(bear), math.sin(bear) }
		end
		add(pts, G.wrap(bear + math.pi), G.angleDiff(bear, hD), G.angleDiff(bear, hD))
	end
	-- the new street's heading leaving N: a dead end's street continued (within the kink), a street node's free angle
	-- (TEE_MIN_DEG off its streets; the straightest ways in first: D's heading continued, the line back, clamped into it)
	local bC = {}
	if kind == "pair" then
		local hOutN = G.wrap(armsN[1] + math.pi)
		for _, f in ipairs({ 0, 0.5, -0.5, 1, -1 }) do bC[#bC + 1] = hOutN + f * kink end
	else
		local back = G.heading(xN, yN, xD, yD)
		local mid, w = freeGap(armsN, back)
		local tee = rad(M.TEE_MIN_DEG)
		if mid ~= nil and w >= 2 * tee then
			local half = w / 2 - tee
			local function clampIn(h)
				local d = G.wrap(h - mid)
				if d > half then d = half elseif d < -half then d = -half end
				return mid + d
			end
			bC = { clampIn(hD + math.pi), clampIn(back), mid, clampIn(mid + rad(20)), clampIn(mid - rad(20)) }
		end
	end
	-- one circular arc: leaving D at its kinks, or arriving at N at its headings
	for _, f in ipairs({ 0, 0.5, 1 }) do
		local a = hD + s * f * kink
		local pts, hEnd = arcThrough(xD, yD, a, xN, yN, M.ARC_MIN)
		if pts then add(pts, G.wrap(hEnd + math.pi), f * kink, f * kink) else why = "curve" end
	end
	for _, b in ipairs(bC) do
		local rp, hEnd = arcThrough(xN, yN, b, xD, yD, M.ARC_MIN)
		if rp then
			local kD = G.angleDiff(G.wrap(hEnd + math.pi), hD)
			if kD <= kink + 1e-9 then
				local pts = {}
				for k = #rp, 1, -1 do pts[#pts + 1] = { rp[k][1], rp[k][2], -rp[k][3], -rp[k][4] } end
				add(pts, b, kD, kD)
			end
		else
			why = "curve"
		end
	end
	-- (the families come best first: the straight line and single arcs, then arc-and-straight, then Hermite curves; the
	-- later ones only while fewer than GEN_SHAPES are found, as only that many are tried)
	-- an arc out of D then straight on to N (D's kink tried), and straight out of D then an arc into N (N's headings)
	if #out >= M.GEN_SHAPES then bC = {} end
	for _, f in ipairs(#out < M.GEN_SHAPES and { 0, 0.5, 1 } or {}) do
		local a = hD + s * f * kink
		for _, R in ipairs(M.ARC_R) do
			local pts, hEnd = arcLine(xD, yD, a, R, xN, yN)
			if pts then add(pts, G.wrap(hEnd + math.pi), f * kink, f * kink + 30 / R) else why = "curve" end
		end
	end
	for _, b in ipairs(bC) do
		for _, R in ipairs(M.ARC_R) do
			local rp, hEnd = arcLine(xN, yN, b, R, xD, yD)
			if rp then
				-- (reversed: from D to N, tangents turned round; hEnd is the line's heading arriving at D)
				local kD = G.angleDiff(G.wrap(hEnd + math.pi), hD)
				if kD <= kink + 1e-9 then
					local pts = {}
					for k = #rp, 1, -1 do pts[#pts + 1] = { rp[k][1], rp[k][2], -rp[k][3], -rp[k][4] } end
					add(pts, b, kD, kD + 30 / R + 0.05)
				end
			else
				why = "curve"
			end
		end
	end
	-- Hermite curves
	if #out >= M.GEN_SHAPES then bC = {} end
	for _, f in ipairs({ 0, 0.5, 1 }) do
		local a = hD + s * f * kink
		local dA = unitOf(a)
		for _, b in ipairs(bC) do
			local dB = unitOf(b + math.pi)
			if G.angleDiff(a, b + math.pi) <= rad(M.MAX_TURN_DEG) then
				local r, len = C.minRadius({ xD, yD }, { dA[1] * L, dA[2] * L }, { xN, yN }, { dB[1] * L, dB[2] * L }, 12)
				if r >= 0.9 * rMin and len <= M.DETOUR * L then
					add(G.hermitePts(xD, yD, xN, yN, dA, dB, 24), b, f * kink, f * kink + 0.3 + rMin / r)
				else
					why = "curve"
				end
			end
		end
	end
	-- (§75) a pair's corner: both streets on to where they meet
	if kind == "pair" and M.CORNER then
		local c = M.corner(xD, yD, hD, xN, yN, G.wrap(armsN[1] + math.pi))
		if c then out[#out + 1] = c end
	end
	if #out == 0 then return nil, why end
	table.sort(out, function(p, q) return p.score < q.score end)
	return out
end

--- §75: the corner join of two dead ends, D at (xD, yD) heading hD out of it, N heading hN out of it: both straight on
--- to where their lines meet. A shape { pts = { D, corner, N }, kind = "pair", corner = true, kinkD = 0, score } or nil
--- (the lines meet behind one of them, a leg under CORNER_LEG_MIN, the turn outside CORNER_MIN_DEG..CORNER_MAX_DEG, or
--- the legs over DETOUR x the gap).
function M.corner(xD, yD, hD, xN, yN, hN)
	local ux, uy, vx, vy = math.cos(hD), math.sin(hD), math.cos(hN), math.sin(hN)
	local den = ux * vy - uy * vx
	if abs(den) < 1e-6 then return nil end
	local dx, dy = xN - xD, yN - yD
	local t1 = (dx * vy - dy * vx) / den
	local t2 = (dx * uy - dy * ux) / den
	if not (t1 >= M.CORNER_LEG_MIN and t2 >= M.CORNER_LEG_MIN) then return nil end
	local turn = G.angleDiff(hD, hN + math.pi)
	if turn < rad(M.CORNER_MIN_DEG) or turn > rad(M.CORNER_MAX_DEG) then return nil end
	local L = G.dist(xD, yD, xN, yN)
	if t1 + t2 > M.DETOUR * L then return nil end
	local cx, cy = xD + ux * t1, yD + uy * t1
	return { pts = { { xD, yD }, { cx, cy }, { xN, yN } }, kind = "pair", corner = true, kinkD = 0,
		score = 0.3 + 0.5 * abs(turn - math.pi / 2) }
end

-- buildings hash: cell -> { {x, y} }
local function buildingIndex(pts)
	if pts == nil or #pts == 0 then return nil end
	local idx = {}
	for i = 1, min(#pts, 50000) do
		local p = pts[i]
		local x, y = p[1] or p.x, p[2] or p.y
		if G.finite(x) and G.finite(y) then
			local k = math.floor(x / M.BUILD_CELL) * 100003 + math.floor(y / M.BUILD_CELL)
			local l = idx[k]
			if l == nil then l = {}; idx[k] = l end
			l[#l + 1] = { x, y }
		end
	end
	return idx
end

local function buildingNear(idx, x, y, r)
	if idx == nil then return false end
	local cx, cy = math.floor(x / M.BUILD_CELL), math.floor(y / M.BUILD_CELL)
	for i = cx - 1, cx + 1 do
		for j = cy - 1, cy + 1 do
			for _, b in ipairs(idx[i * 100003 + j] or {}) do
				if G.dist(x, y, b[1], b[2]) < r then return true end
			end
		end
	end
	return false
end

-- arc positions of a polyline's points
local function arcs(Pp)
	local out, s = { 0 }, 0
	for i = 2, #Pp do
		s = s + G.dist(Pp[i - 1][1], Pp[i - 1][2], Pp[i][1], Pp[i][2])
		out[i] = s
	end
	return out, s
end

--- The checks of one planned join (D -> N, its curve Pp from D to N, length len) beyond the planner's: nil when it
--- passes, else why. Exposed for the tests. ctx = { g, style, terrain, maxGrade, waterSetback, bidx, lim }.
function M.check(ctx, D, N, Pp, len)
	local g, style = ctx.g, ctx.style or {}
	local a, b = g.nodeById[D], g.nodeById[N]
	Pp = G.resample(Pp, M.STEP)
	-- slope: between the two existing nodes (their heights are fixed), and over the ground
	local maxGrade = math.min(ctx.maxGrade or style.maxSlope or 0.1, 0.2)
	if abs((b.z or 0) - (a.z or 0)) / max(len or G.polyLen(Pp), 1) > maxGrade then return "slope" end
	local terrain = ctx.terrain
	-- (the ground on the planned curve only: a shape's pre-check leaves it out, it costs most)
	if terrain and not ctx.placeOnly then
		if T.pathMaxGrade(terrain, Pp) > maxGrade then return "slope" end
		if T.wetAlong(terrain, Pp, ctx.waterSetback or style.waterSetback or 0) then return "water" end
	end
	if style.gaps and GP.held(style.gaps, Pp, "small") then return "gap" end
	if style.industry and IND.zoneHit(style.industry, Pp) then return "zone" end
	if SEL.inGreen(style, Pp) then return "green" end
	if style.roads and SEL.ROAD_BLOCK and SEL.nearRoads(style.roads, Pp) then return "road" end
	for _, p in ipairs(Pp) do
		if buildingNear(ctx.bidx, p[1], p[2], M.BUILD_CLEAR) then return "building" end
	end
	if ctx.placeOnly then return nil end
	local at, total = arcs(Pp)
	-- streets crossed or passed: every edge near the curve; those at D / N only for crossings beyond the joint
	local ids = KN.near(g, Pp, M.CLEAR + 5)
	for k = 1, min(#ids, M.SCAN_EDGES) do
		local e = g.edgeById[ids[k]]
		local Q = e and KN.edgePts(g, e)
		if Q then
			local atD, atN = (e.n0 == D or e.n1 == D), (e.n0 == N or e.n1 == N)
			if atD or atN then
				-- (a shared node flagged on both: P starts at D and ends at N)
				local sq = { [1] = e.n0 == D or e.n0 == N, [2] = e.n1 == D or e.n1 == N }
				if KN.crosses(Pp, Q, { [1] = atD, [2] = atN }, sq) then return "cross" end
			else
				if KN.crosses(Pp, Q) then return "cross" end
				for i, p in ipairs(Pp) do
					if at[i] >= M.END_SKIP and at[i] <= total - M.END_SKIP and C.pointPolyDist(p[1], p[2], Q) < M.CLEAR then
						return "near"
					end
				end
			end
		end
	end
	-- §70 knots: a long near-parallel run, a small loop. §75: the run over the whole street the join makes (the streets
	-- behind D, and behind N for a pair, through two-street nodes; a tee / cross end is a junction: its approach left
	-- out), beside the streets near it or itself
	local lim = ctx.lim
	if M.parallelKnot(g, D, N, Pp, lim) then return "parallel" end
	local function nbrs(u)
		local out = {}
		for _, id in ipairs(g.adj[u] or {}) do
			local e = g.edgeById[id]
			local v = OG.other(e, u)
			out[#out + 1] = { v, OG.edgeLength(g, e) }
		end
		return out
	end
	local function posOf(id)
		local nd = g.nodeById[id]
		if nd == nil then return nil end
		return nd.x, nd.y
	end
	local path = KN.way(D, N, nbrs, posOf, lim.perim)
	if path and KN.loopArea(Pp, path) < ctx.loopA then return "loop" end
	-- room at a street node: no other junction right beside it
	if OG.degree(g, N) >= 2 then
		for _, nd in ipairs(OG.nodesNear(g, b.x, b.y, b.x, b.y, M.JUNCTION_GAP)) do
			if nd.id ~= N and nd.id ~= D and OG.degree(g, nd.id) >= 3 and G.dist(nd.x, nd.y, b.x, b.y) < M.JUNCTION_GAP then
				return "spacing"
			end
		end
	end
	return nil
end

--- §75: does the join D -> N (its curve Pp) make a street that runs beside another (or itself) for at least lim.parRun
--- within lim.parM (ot_knot.parallelRun over the street through it, ot_knot.chainBehind)? Exposed for the tests.
function M.parallelKnot(g, D, N, Pp, lim)
	local function at(id) return KN.graphAt(g, id) end
	local pa, ta, ea = KN.chainBehind(D, "join", at)
	local pb, tb, eb = KN.chainBehind(N, "join", at)
	local C, s0, s1, k0, k1 = KN.streetLine(Pp, pa, ea, pb, eb)
	local others = {}
	for _, id in ipairs(KN.near(g, C, lim.parM)) do
		local tag = "e" .. tostring(id)
		local e = g.edgeById[id]
		local Q = e and not ta[tag] and not tb[tag] and KN.edgePts(g, e)
		if Q then others[#others + 1] = Q end
	end
	return KN.parallelRun(C, others, lim, { s0 = s0, s1 = s1, skip0 = k0, skip1 = k1, self = true }) >= lim.parRun
end

local function bump(t, k) t[k] = (t[k] or 0) + 1 end

--- §75: m of polyline Pp in big-wood cells (ot_forest.bigWoodAt), sampled every STEP (at most 200 samples).
function M.woodRun(wood, Pp)
	if wood == nil or Pp == nil or #Pp < 2 then return 0 end
	local R = G.resample(Pp, max(M.STEP, G.polyLen(Pp) / 200))
	local n = 0
	for i = 2, #R do
		local a, b = R[i - 1], R[i]
		if FO.bigWoodAt(wood, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2) then n = n + G.dist(a[1], a[2], b[1], b[2]) end
	end
	return n
end

--- The planner street of a join: a shape's smooth polyline carrying its tangents (ot_plan.streetPoints cuts it by arc
--- length and turn and refuses an edge whose Hermite curve is under MIN_RADIUS; not dirA / dirB, which the planner
--- blends toward the chord under LINE_RADIUS).
function M.street(D, N, shape)
	-- (§75: a corner is two straight legs, ot_plan's chords, the corner a new node)
	return { pts = shape.pts, curved = not shape.corner, smooth = not shape.corner, startNode = D, endNode = N,
		class = "small", key = "nm:" .. D .. ":" .. N, origin = "nearMiss", nearMiss = shape.kind }
end

-- the planned edges of one street as one curve from its first edge's node0 on, and its length; the leaving headings at
-- its two ends (at the start node, and at the end node back into the curve)
local function plannedCurve(inc)
	local Pp, len = {}, 0
	for _, e in ipairs(inc.edges) do
		local Q = C.curvePts(e.p0, e.t0, e.p1, e.t1, M.STEP)
		for k, q in ipairs(Q) do
			if k > 1 or #Pp == 0 then Pp[#Pp + 1] = q end
		end
		len = len + (e.length or 0)
	end
	local e1, e2 = inc.edges[1], inc.edges[#inc.edges]
	return Pp, len, G.atan2(e1.t0[2], e1.t0[1]), G.atan2(-e2.t1[2], -e2.t1[1])
end

local function planOpts(o, style, extra, maxEdges)
	return { terrain = o.terrain, maxSeg = o.maxSeg or 100, snapR = 8, minLen = 10, minAngle = 25,
		sideAngle = C.LIMITS.sideAngle,
		maxGrade = o.maxGrade or style.maxSlope, waterSetback = o.waterSetback or style.waterSetback,
		maxEdges = maxEdges, join = o.join or "deadEnd", templatePaths = style.templatePaths, joinExtra = extra,
		requireConnected = true }
end

-- curve points of a planned edge
local function edgeCurve(e)
	return C.curvePts(e.p0, e.t0, e.p1, e.t1)
end

--- Near-miss joins for graph g beside the increment `inc` (the grower's, may be nil / empty). o = { terrain, maxSeg,
--- maxGrade, waterSetback, join, midOk = function(node id) -> true when a street node may be joined (nil: any),
--- buildings = { {x, y} }, seed, exclude = { [key] = true }, cap }. Returns add (an ot_plan increment of the joins, or
--- nil) and report = { found, joined, kept, why = { [reason] = n }, tests, joins = { "kind:gap" } }.
function M.joins(g, style, inc, o)
	o = o or {}
	local rep = { found = 0, joined = 0, kept = 0, why = {}, tests = 0, plans = 0, joins = {} }
	if not M.ON or g == nil or #g.edges == 0 then return nil, rep end
	local used = {}
	for _, e in ipairs((inc and inc.edges) or {}) do
		if e.node0 > 0 then used[e.node0] = true end
		if e.node1 > 0 then used[e.node1] = true end
	end
	local exclude = o.exclude or {}
	local join = o.join or "deadEnd"
	local ctx = { g = g, style = style, terrain = o.terrain, maxGrade = o.maxGrade, waterSetback = o.waterSetback,
		bidx = buildingIndex(o.buildings), lim = KN.limits(style) }
	do
		local b = style.block or {}
		ctx.loopA = M.LOOP_K * (tonumber(b.len) or 60) * (tonumber(b.depth) or 45)
	end
	local seed = o.seed or style.seed or 1
	local fo = style.forest
	local wood = fo and FO.active(fo) and fo.grid or nil
	local keepWood = fo and FO.isDeep(fo) and M.DEEP_KEEP or M.FOREST_KEEP
	local midCache, retCache = {}, {}
	-- a retired dead end (the driver's snapshot: the mod's own empty street, never extended this session; nmRetired
	-- only when that is its one noJoin reason) may still be closed by a join when o.retiredOk says so (2026-10-18)
	local function retiredOk(nd)
		if not (nd.noJoin and nd.nmRetired) or o.retiredOk == nil then return false end
		if retCache[nd.id] == nil then
			local okR, v = pcall(o.retiredOk, nd.id)
			retCache[nd.id] = okR and v == true
		end
		return retCache[nd.id]
	end
	local function deadOk(nd)
		return P.joinable(g, nd, join) or (OG.degree(g, nd.id) == 1 and retiredOk(nd))
	end
	-- ot_plan's joinExtra for a join D -> N: N whatever its degree, a retired end by name ("retired")
	local function extraOf(D, N)
		local e = {}
		for _, id in ipairs({ D, N }) do
			local nd = g.nodeById[id]
			if nd and nd.noJoin and nd.nmRetired and retCache[id] then e[id] = "retired"
			elseif id == N then e[id] = true end
		end
		return e
	end
	local function targetOk(nd)
		local deg = OG.degree(g, nd.id)
		-- (never a node of a country road: the mod leaves their nodes and edges alone)
		for _, id in ipairs(g.adj[nd.id]) do
			local e = g.edgeById[id]
			if e and LN.isCountry(e.template) then return false end
		end
		if deg == 1 then return deadOk(nd) end
		if nd.noJoin then return false end
		if deg == 3 then
			if not M.JUNCTION_JOIN then return false end
			for _, id in ipairs(g.adj[nd.id]) do
				local e = g.edgeById[id]
				if not M.SMALL[e.class or "small"] then return false end
			end
		elseif deg ~= 2 then
			return false
		end
		if o.midOk == nil then return true end
		if midCache[nd.id] == nil then
			local okM, v = pcall(o.midOk, nd.id)
			midCache[nd.id] = okM and v == true
		end
		return midCache[nd.id]
	end
	local passing = {}
	-- status per near-miss dead end (`order`): a kept reason, "passing", or "joined" (also a pair's partner)
	local status, order = {}, {}
	-- the near-miss dead ends, the smallest gap first (a time budget, o.clock / o.budgetUs, stops the rest: `budget`)
	local des = OG.deadEnds(g)
	local near = {}
	for i = 1, min(#des, M.MAX_DEAD) do
		local gap = M.aheadDist(g, des[i], M.JOIN_MAX)
		if gap then near[#near + 1] = { D = des[i], gap = gap } end
	end
	table.sort(near, function(p, q) return p.gap < q.gap or (p.gap == q.gap and p.D < q.D) end)
	local t0 = o.clock and o.clock() or nil
	for i = 1, #near do
		local D = near[i].D
		local nD = g.nodeById[D]
		do
			order[#order + 1] = D
			local h, hc, eD, f = M.outHeadings(g, D)
			local why = nil
			if t0 and o.budgetUs and o.clock() - t0 > o.budgetUs then why = "budget"
			elseif used[D] then why = "inc"
			elseif nD.nmCut then why = "cut"
			elseif not deadOk(nD) then why = "noJoin"
			elseif eD and LN.isCountry(eD.template) then why = "lane"
			else
				-- target nodes ahead, nearest first
				local lim = rad(M.AHEAD_DEG)
				local cands = {}
				for _, nd in ipairs(OG.nodesNear(g, nD.x, nD.y, nD.x, nD.y, M.NODE_MAX)) do
					local d = G.dist(nD.x, nD.y, nd.x, nd.y)
					if nd.id ~= D and nd.id ~= f.id and d <= M.NODE_MAX and d > 8 and not used[nd.id]
						and aheadOk({ h, hc }, G.heading(nD.x, nD.y, nd.x, nd.y), lim) then
						cands[#cands + 1] = { nd = nd, d = d }
					end
				end
				table.sort(cands, function(p, q) return p.d < q.d or (p.d == q.d and p.nd.id < q.nd.id) end)
				local found = nil
				local tried = 0
				for _, c in ipairs(cands) do
					if tried >= M.MAX_TARGETS then break end
					local N = c.nd.id
					local key = "nm:" .. D .. ":" .. N
					local r
					if exclude[key] then r = "refused"
					elseif not targetOk(c.nd) then r = "target"
					elseif rep.tests >= M.MAX_TESTS then r = "budget"
					else
						tried = tried + 1
						rep.tests = rep.tests + 1
						local arms = {}
						for _, id in ipairs(g.adj[N]) do arms[#arms + 1] = OG.headingFrom(g, g.edgeById[id], N) end
						local shapes, sw = M.shapes(nD.x, nD.y, h, c.nd.x, c.nd.y, arms)
						if shapes == nil then r = sw
						elseif abs((c.nd.z or 0) - (nD.z or 0)) / c.d > math.min(o.maxGrade or style.maxSlope or 0.1, 0.2) then
							r = "slope"
						else
							local planned = 0
							for k = 1, min(#shapes, M.GEN_SHAPES) do
								if rep.plans >= M.MAX_PLANS then r = r or "budget" break end
								if planned >= M.MAX_SHAPES then break end
								-- (the place checks on the shape first: no plan for a shape over a house, the water, a gap line)
								ctx.placeOnly = true
								local rk = M.check(ctx, D, N, shapes[k].pts, nil)
								ctx.placeOnly = nil
								local one = { edges = {}, dropped = {} }
								if rk == nil then
									rep.plans = rep.plans + 1
									planned = planned + 1
									one = P.plan(g, { M.street(D, N, shapes[k]) }, planOpts(o, style, extraOf(D, N), 4))
								end
								local st = M.street(D, N, shapes[k])
								if rk then
									-- (refused before the plan)
								elseif #one.edges == 0 or #one.dropped > 0 then
									rk = M.PLAN_WHY[one.dropped[1] and one.dropped[1].reason or "empty"] or "plan"
								else
									local Pp, len, hA, hB = plannedCurve(one)
									-- (the planner's cut edges carry the shape's end directions to within a degree or two)
									if G.angleDiff(hA, h) > rad(M.KINK_DEG) + rad(2) or not M.endOk(arms, hB, rad(2)) then
										rk = "angle"
									else
										rk = M.check(ctx, D, N, Pp, len)
										if rk == nil then
											found = { D = D, N = N, st = st, gap = c.d, kind = shapes[k].kind, pts = Pp,
												corner = shapes[k].corner }
											break
										end
									end
								end
								-- (the first refusal names the candidate; a geometry refusal of the planner gives way to a later check's)
								if r == nil or (M.SHAPE_WHY[r] and not M.SHAPE_WHY[rk]) then r = rk end
							end
						end
					end
					if o.trace then o.trace(D, N, r or "ok", c.d, h) end
					if found then break end
					why = why or r
				end
				if found then
					why = nil
					-- the woods: some joins left on purpose (a lane or a track into the trees stays a dead end)
					if wood and M.woodRun(wood, found.pts) >= M.WOOD_RUN_M
						and rng.draw(seed, "nmWood", min(D, found.N), max(D, found.N)) < keepWood then
						why = "forest"
					elseif rng.draw(seed, "nearMiss", min(D, found.N), max(D, found.N)) >= M.chance(found.gap) then
						why = "chance"
					else
						passing[#passing + 1] = found
					end
				elseif why == nil then
					why = #cands == 0 and "noNode" or "target"
				end
			end
			status[D] = why or "passing"
		end
	end
	-- nearest first, each node once, the cap
	table.sort(passing, function(p, q) return p.gap < q.gap or (p.gap == q.gap and p.D < q.D) end)
	local chosen, taken = {}, {}
	local cap = o.cap or M.MAX_PER_INC
	for _, c in ipairs(passing) do
		if taken[c.D] or taken[c.N] then
			-- (its partner dead end already chosen (a pair seen from both ends), or a node taken: the next increment)
			if not (taken[c.N] and taken[c.D]) then status[c.D] = "taken" end
		elseif #chosen >= cap then
			status[c.D] = "cap"
		else
			chosen[#chosen + 1] = c
			taken[c.D], taken[c.N] = true, true
		end
	end
	local function finish(add)
		if add then
			for _, c in ipairs(chosen) do
				status[c.D] = "joined"
				if status[c.N] ~= nil then status[c.N] = "joined" end
				-- (§75: "c" a corner, "r" closing a retired dead end)
				local retired = retCache[c.D] or retCache[c.N]
				rep.joins[#rep.joins + 1] = string.format("%s:%.0f%s%s", c.kind, c.gap, c.corner and "c" or "",
					retired and "r" or "")
			end
		end
		rep.found = #order
		for _, D in ipairs(order) do
			local st = status[D]
			if st == "joined" then rep.joined = rep.joined + 1
			else
				rep.kept = rep.kept + 1
				bump(rep.why, st == "passing" and "taken" or (st:match("^[^:]+")))
			end
		end
		return add, rep
	end
	if #chosen == 0 then return finish(nil) end
	-- plan them together; a join in conflict with the increment's own new streets (or with another join) is left out
	local add = nil
	for _ = 1, #chosen + 1 do
		local streets, extra = {}, {}
		for _, c in ipairs(chosen) do
			streets[#streets + 1] = c.st
			for k, v in pairs(extraOf(c.D, c.N)) do extra[k] = v end
		end
		add = P.plan(g, streets, planOpts(o, style, extra, 4 * #chosen))
		local drop = {}
		for _, d in ipairs(add.dropped or {}) do drop[d.street] = d.reason end
		for _, e in ipairs(add.edges) do
			local Pj = edgeCurve(e)
			for _, x in ipairs((inc and inc.edges) or {}) do
				local kind = C.pairConflict(Pj, e.node0, e.node1, C.halfWidth("small"), edgeCurve(x), x.node0, x.node1,
					C.halfWidth(x.class, x.template))
				if kind then drop[e.street] = "conflict"; break end
			end
		end
		local kept = {}
		for i, c in ipairs(chosen) do
			if drop[i] then
				status[c.D] = drop[i] == "conflict" and "conflict" or "plan"
			else
				kept[#kept + 1] = c
			end
		end
		if #kept == #chosen then break end
		chosen = kept
		add = nil
		if #chosen == 0 then break end
	end
	if add == nil or #add.edges == 0 then return finish(nil) end
	for _, e in ipairs(add.edges) do
		e.nearMiss = true
		local c = chosen[e.street]
		if c then
			e.nearMissKind = c.kind
			-- (§75 follow-up: a pair's corner, for the provenance record, ot_prov)
			if c.corner then e.nearMissCorner = true end
		end
	end
	return finish(add)
end

--- inc with the joins `add` appended (both ot_plan increments; entities renumbered: edges -1..-E, then the new nodes).
--- In place on inc; returns it.
function M.merge(inc, add)
	if add == nil or #add.edges == 0 then return inc end
	local E1 = #inc.edges
	local Et = E1 + #add.edges
	local nodes = {}
	local mapA, mapB = {}, {}
	local nxt = -(Et + 1)
	for _, n in ipairs(inc.nodes) do
		mapA[n.entity] = nxt
		n.entity = nxt
		nodes[#nodes + 1] = n
		nxt = nxt - 1
	end
	for _, n in ipairs(add.nodes) do
		mapB[n.entity] = nxt
		n.entity = nxt
		nodes[#nodes + 1] = n
		nxt = nxt - 1
	end
	local function m(map, id)
		if id > 0 then return id end
		return map[id]
	end
	local edges, joins, total = {}, {}, 0
	for i, e in ipairs(inc.edges) do
		e.node0, e.node1 = m(mapA, e.node0), m(mapA, e.node1)
		e.entity = -i
		edges[#edges + 1] = e
	end
	for j, e in ipairs(add.edges) do
		e.node0, e.node1 = m(mapB, e.node0), m(mapB, e.node1)
		e.entity = -(E1 + j)
		e.street = nil
		edges[#edges + 1] = e
	end
	for _, e in ipairs(edges) do
		if e.node0 > 0 then joins[#joins + 1] = { node = e.node0, edge = e.entity } end
		if e.node1 > 0 then joins[#joins + 1] = { node = e.node1, edge = e.entity } end
		total = total + (e.length or 0)
	end
	inc.edges, inc.nodes, inc.joins = edges, nodes, joins
	inc.stats = { edges = #edges, nodes = #nodes, length = total }
	inc.nearMiss = (inc.nearMiss or 0) + #add.edges
	return inc
end

--- PLAN `nearMiss=` text: "<found>/<joined>/<kept>" and the kept reasons "r:n,...", or "-" without a report.
function M.text(rep)
	if rep == nil then return "-", "-" end
	local keys = {}
	for k in pairs(rep.why or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. rep.why[k] end
	return string.format("%d/%d/%d", rep.found or 0, rep.joined or 0, rep.kept or 0),
		#parts > 0 and table.concat(parts, ",") or "-"
end

return M
