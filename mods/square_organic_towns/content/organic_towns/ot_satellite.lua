-- Organic Towns: satellite villages (pure; 2026-10-13).
--
-- User (real map run 2026-10-13_0018_top-up-598153): the vanilla cluster at Barnard Castle, a small separate group of
-- houses ~1.2 km out beside a farm, linked to the town by its country road, looked good. The game made it from the
-- small town streets the map generator lays at the edge of industries (baseConfig.locations.makeInitialStreets, "Add
-- small streets at the edge of industries", base/content/base/mod.script.tl:135, api type.d.tl:3554; default true,
-- the new-game page sets it true too: gui/menu/new_game_or_map_settings_page.tl:407); the town later grew houses onto
-- them. A deliberate small-town version of the polycentric metropolis:
--   * who (M.eligible): a growing town (a demand build) past MIN_BUILDINGS, a seeded CHANCE per town, not a
--     metropolis, not the block styles (superblock / ensanche), one satellite per town;
--   * where (M.pickSite): RING_D 0.8-1.5 km out (and SAT_GAP beyond the houses' extent), on dry, gentle land (no water
--     within 120 m, slope under MAX_SLOPE), away from heavy industry (a light works next to it is fine: farms are
--     where the vanilla cluster sits), nearer this town than any other, preferably beside a road leaving the town
--     (country road: ROAD_BONUS) and on a valley floor / shore (low ground: LOW_BONUS); the link from the town's
--     nearest joinable dead end must stay dry and under LINK_GRADE;
--   * what (M.streets): ONE link street from that dead end (a gentle bend, no side streets: the driver locks it and
--     keeps meadow discs along it out of the town's own plan, M.gapGreens) and a compact core at the site (a short
--     main street through it and a cross street: 3 edges, CORE_SMALL since 2026-10-14; two cross streets before),
--     CORE_EDGES at most; later growth (M.growStreets) extends the
--     core's own dead ends by one block at a time within CORE_R, up to MAX_EDGES, only while its houses keep up.
-- Plain base town streets like every increment; the houses belong to the town (the site is nearer this town).
-- M2 (2026-10-13): sites beside a crossroads of country roads (ot_roads junctions: the quadrants between their roads,
-- 90-170 m from the junction) score HAMLET_BONUS better, a farm / light works within LIGHT_R scores LIGHT_BONUS better
-- (only heavy / medium works keep the site away: IND.penHeavy); the crossroads hamlet motif (ot_motif_road) makes a
-- town seed its satellite there (o.hamlet: smaller towns, no seeded draw, a shorter gap and link). The junction itself is
-- never joined (country-road nodes: ot_roads header): the hamlet gets its own link street like every satellite.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local SK = ug_require "square_organic_towns::/organic_towns/ot_skeleton.lua"

local M = {}

M.ON = true
-- (2026-10-13, real map round 5: the user wants them more common: 30 % of the towns >= 300 buildings -> 55 % >= 250;
-- the driver adds a map quota, D.SAT_MAP_MIN)
M.MIN_BUILDINGS = 250      -- a town this big (buildings) may seed one
M.CHANCE = 0.55            -- seeded share of the eligible towns
M.NO_STYLE = { SUPERBLOCK = true, MED_ENSANCHE = true }
-- (2026-10-14 late: shorter, the empty links were the most visible artefact: 800-1500 m, SAT_GAP 450, MIN_LINK 550)
M.RING_D = { 650, 800, 1000, 1200 }
M.DIRS = 24
M.SAT_GAP = 350            -- m beyond the houses' extent radius at least (meadow between)
M.MIN_LINK = 400           -- m: the link from the town's nearest dead end at least this long
M.MAX_LINK = 900           -- m: ... and at most this long (hamlets too; Henley-in-Arden's was 1233 m, 2026-10-14 late)
M.MAX_SLOPE = 0.08         -- mean slope in the core disc
M.CORE_R = 220             -- m: the satellite's own streets stay within this of its site
M.WET_R = 120
M.LINK_GRADE = 0.10
M.HEAVY_PEN = 0.15         -- industry penalty (ot_industry.pen, heavy works weigh most) above this: no site
M.ROAD_R = 150             -- a road (not a town street) within this: ROAD_BONUS
M.ROAD_BONUS = 0.35
M.LOW_BONUS = 0.2          -- the site lower than the town centre (valley floor, shore)
M.NEIGHBOUR_MIN = 1300     -- m from any other town centre
M.CORE_EDGES = 10          -- first increment: link + core at most this many edges more than the link needs
M.MAX_EDGES = 30           -- the satellite's own streets (core + growth, the link not counted)
M.GROW_EDGES = 8           -- per growth increment
M.HOUSED_PER_EDGE = 1.5    -- growth only when its buildings / own core edges reach this
M.EVERY = 3                -- every this many demand builds of the town one goes to the satellite (when housed); only
                           -- with the pacing off: ot_satpace.growDue paces it per pod since 2026-10-14
M.BLOCK = 80               -- m: core block length
-- crossroads hamlets and light industry (M2, 2026-10-13; ot_motif_road crossroads_hamlet, MOTIFS_BRIEF "Satellite
-- clusters at farms / light industry")
M.HAMLET_MIN_BUILDINGS = 120   -- a town with the hamlet motif may seed it from this size (no seeded CHANCE)
M.HAMLET_D = { 450, 1600 }     -- m: crossroads this far from the centre
M.HAMLET_R = { 90, 130, 170 }  -- m from the junction into each quadrant between its roads
M.HAMLET_GAP = 220             -- m beyond the houses' extent at least (SAT_GAP for the ring)
M.HAMLET_MIN_LINK = 250        -- m: the link at least this long (MIN_LINK for the ring)
M.HAMLET_BONUS = 0.3           -- any satellite: a site beside a crossroads scores this better
M.HAMLET_PICK = 1.0            -- the hamlet motif's own junction
M.QUAD_MIN = math.rad(50)      -- a quadrant between two roads at least this wide
M.LIGHT_R = 450                -- m: a light works / farm this near the site: LIGHT_BONUS ...
M.LIGHT_MIN = 100              -- ... but not on top of it
M.LIGHT_BONUS = 0.3
M.FOREST_W = 1.2               -- §63: score + this x how wooded the site's surroundings are (ot_skeleton.pointClear) ...
M.LINK_WOOD_W = 0.5            -- ... + this x the link's mean cover (o.forest: the parent's tree grid; o.deep: none)

--- Is town t a satellite candidate? o = { seed, buildings, styleId, metro (bool), has (already one), hamlet (the
--- crossroads hamlet motif's junction, M2) }. Returns true or false, why ("off" | "has" | "small" | "metro" | "style" |
--- "rare" | "seeded" | "hamlet").
function M.eligible(o)
	if not M.ON then return false, "off" end
	if o.has then return false, "has" end
	-- (the crossroads hamlet motif: smaller towns, no seeded draw; M2)
	if o.hamlet then
		if (o.buildings or 0) < M.HAMLET_MIN_BUILDINGS then return false, "small" end
		if o.metro then return false, "metro" end
		if M.NO_STYLE[o.styleId or ""] then return false, "style" end
		return true, "hamlet"
	end
	if (o.buildings or 0) < M.MIN_BUILDINGS then return false, "small" end
	if o.metro then return false, "metro" end
	if M.NO_STYLE[o.styleId or ""] then return false, "style" end
	if rng.decide(o.dv, o.seed or 1, "satellite") >= M.CHANCE then return false, "rare" end
	return true, "seeded"
end

local function meanSlope(s, x, y, r)
	local sum, n = 0, 0
	for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		sum = sum + T.slope(s, x + d[1] * r * 0.6, y + d[2] * r * 0.6, 8)
		n = n + 1
	end
	return sum / n
end

local function wetNear(s, x, y, r)
	if T.isWater(s, x, y) then return true end
	for k = 0, 7 do
		local a = k * math.pi / 4
		if T.isWater(s, x + math.cos(a) * r, y + math.sin(a) * r) then return true end
	end
	return false
end

--- The link polyline from (ax, ay) to (bx, by). Until 2026-10-14 a gentle seeded bend (BEND x length at the middle, 9
--- points), planned as straight chords: the same-seed comparison's long straight empty lanes (Ellesmere S, Winchcombe W,
--- Windermere SW, Henley-in-Arden S, 567-1233 m) were these links. Now (M.curvedLink) a meander: a seeded bow
--- (BOW x length, at most BOW_MAX m) plus a wiggle of one half-wave every WAVE_M (WAVE_A x WAVE_M), BENDS seeded variants,
--- the one with the gentlest grade along the terrain (sampler) or else the first; every MAX_STRAIGHT m the heading turns
--- by more than STRAIGHT_TOL deg (ot_geom.maxStraightRun). The driver plans it as a curved street (`curved`).
M.BEND = 0.06
M.BOW = { 0.04, 0.09 }
M.BOW_MAX = 110
M.WAVE_M = 150
M.WAVE_A = { 0.08, 0.11 }
M.BENDS = 4
M.MAX_STRAIGHT = 150
M.STRAIGHT_TOL = 4
M.LINK_COUNTRY = true      -- the seed's link as a locked country lane (2026-10-14 late; false: a locked town street)
M.CORE_FILL = true         -- the seed's core streets get a dose at the build (2026-10-14 late)
-- (2026-10-14, run 2026-10-14_0502_sqot: Ellesmere Port's "H" 800 m west and Henley-in-Arden's crossroads satellite
-- stayed empty skeletons. The satellite's streets are the parent's, so the game houses them by network distance and the
-- far skeleton waits behind every nearer free lot; the seed's dose came 1-2 s after the build, before the game had lots
-- on the new streets (FILL effect near=0->0 on all five dosed seeds), and five seeds got none (the dose's surge rule).
-- Now: a small core (CORE_SMALL: the main street's first block and one cross street at the site, 3 edges; the second
-- cross street comes with the growth once housed), the seed dose never held by the surge rule, a second dose at the
-- core once its lots exist (REDOSE_S after the build, up to REDOSES), and a satellite still empty after RETIRE_CHECKS
-- checks of its town from then is retired: no more streets, its meadow gap released (SATELLITE retire).)
M.CORE_SMALL = true
M.REDOSE_S = 45            -- real s after the seed build: the core's lots exist by then (the town adopted the streets)
M.REDOSES = 2              -- core doses after the seed's own
M.RETIRE_CHECKS = 10       -- checks of the town with no house at the satellite after the last dose: retired
function M.curvedLink(ax, ay, bx, by, seed, sampler, tag)
	local L = G.dist(ax, ay, bx, by)
	if L < 1 then return { { ax, ay }, { bx, by } } end
	local nx, ny = -(by - ay) / L, (bx - ax) / L
	local n = math.max(12, math.min(80, math.ceil(L / 25)))
	local h = math.max(2, math.floor(L / M.WAVE_M + 0.5))
	local best, bestCost = nil, math.huge
	tag = tag or "satBend"
	for v = 1, M.BENDS do
		local u1 = rng.unit(seed or 1, tag, v, 1)
		local u2 = rng.unit(seed or 1, tag, v, 2)
		local u3 = rng.unit(seed or 1, tag, v, 3)
		local bow = math.min(M.BOW_MAX, (M.BOW[1] + (M.BOW[2] - M.BOW[1]) * u1) * L) * (u2 < 0.5 and -1 or 1)
		local wave = (M.WAVE_A[1] + (M.WAVE_A[2] - M.WAVE_A[1]) * u3) * (L / h) * (v % 2 == 0 and -1 or 1)
		local pts = {}
		for i = 0, n do
			local t = i / n
			local w = bow * math.sin(math.pi * t) + wave * math.sin(h * math.pi * t)
			pts[#pts + 1] = { ax + (bx - ax) * t + nx * w, ay + (by - ay) * t + ny * w }
		end
		local cost = v * 1e-6
		if sampler then cost = cost + T.pathMaxGrade(sampler, pts, 40) end
		if cost < bestCost then best, bestCost = pts, cost end
	end
	return best
end

function M.linkPts(ax, ay, bx, by, seed, sampler)
	return M.curvedLink(ax, ay, bx, by, seed, sampler, "satBend")
end

M.LINK_TRIES = 3           -- dead ends tried per site (nearest first)
M.LINK_CLEAR = 18          -- m: the link keeps this far from existing streets (the planner's clearEdge is 16 m)
-- Obstacles outside the town's snapshot (2026-10-13, real map run 2026-10-13_0342_sqot: Middlewich's, Barrow's and
-- Hingham's seeds were refused, "Collision" with entities the snapshot didn't hold: 2-18 collisions, partners with
-- consecutive ids, most likely farm fields, tracks or country roads 1 km out). o.obstacles (ot_engine.obstacles): the link
-- and the core streets keep OBST_CLEAR m from every edge (TRACK_CLEAR from tracks) and BOX_CLEAR m from construction /
-- field boxes; the link's first START_SKIP m (its own dead end's street) are not tested.
M.OBST_CLEAR = 18
M.TRACK_CLEAR = 22
M.BOX_CLEAR = 15
M.START_SKIP = 30
M.BAD_R = 300              -- m: sites within this of a refused one are skipped (o.bad)

--- true when the link polyline crosses no existing street of graph g (nil: no check) and keeps LINK_CLEAR from every
--- street not at its dead end (startNode).
function M.linkClear(g, pts, startNode)
	if g == nil then return true end
	local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
	local skip = { [startNode] = true }
	for i = 2, #pts do
		if OG.crossing(g, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], skip) then return false end
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local L = G.dist(a[1], a[2], b[1], b[2])
		local n = math.max(1, math.ceil(L / 20))
		for k = 0, n do
			local px, py = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
			if OG.distToEdges(g, px, py, M.LINK_CLEAR, skip) then return false end
		end
	end
	return true
end

local OBST_CELL = 100

--- Grid index of the obstacles (cached on obs): each segment / box in every cell its box (+ the clearance) touches.
local function obstacleIndex(obs)
	if obs._idx then return obs._idx end
	local idx = {}
	local pad = math.max(M.OBST_CLEAR, M.TRACK_CLEAR, M.BOX_CLEAR)
	local function add(item, x0, y0, x1, y1)
		local c0, c1, r0, r1 = G.cellRange(x0, y0, x1, y1, pad, OBST_CELL)   -- (hang guard)
		for cx = c0 or 1, c1 or 0 do
			for cy = r0, r1 do
				local k = cx * 65536 + cy
				local l = idx[k]
				if l == nil then l = {}; idx[k] = l end
				l[#l + 1] = item
			end
		end
	end
	for _, sg in ipairs(obs.segs or {}) do add(sg, sg[1], sg[2], sg[3], sg[4]) end
	for _, bx in ipairs(obs.boxes or {}) do
		-- (a box bigger than 1.5 km, e.g. a map-wide construction: not an obstacle the site test can use)
		if bx[3] - bx[1] < 1500 and bx[4] - bx[2] < 1500 then add(bx, bx[1], bx[2], bx[3], bx[4]) end
	end
	obs._idx = idx
	return idx
end

--- true when the polyline pts keeps clear of the obstacles obs (ot_engine.obstacles; nil: no check). skipR: the
--- first skipR m from pts[1] are not tested (the link's own dead end). Second result: the kind hit.
function M.clearOfObstacles(obs, pts, skipR)
	if obs == nil or pts == nil or #pts < 2 then return true end
	local idx = obstacleIndex(obs)
	local x0, y0 = pts[1][1], pts[1][2]
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local L = G.dist(a[1], a[2], b[1], b[2])
		local n = math.max(1, math.ceil(L / 15))
		for k = 0, n do
			local px, py = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
			if skipR == nil or G.dist(px, py, x0, y0) > skipR then
				local l = idx[math.floor(px / OBST_CELL) * 65536 + math.floor(py / OBST_CELL)]
				for _, it in ipairs(l or {}) do
					if it.kind == "con" or it.kind == "field" then
						local c = M.BOX_CLEAR
						if px > it[1] - c and px < it[3] + c and py > it[2] - c and py < it[4] + c then return false, it.kind end
					else
						local c = it.kind == "track" and M.TRACK_CLEAR or M.OBST_CLEAR
						if G.pointSegDist(px, py, it[1], it[2], it[3], it[4]) < c then return false, it.kind end
					end
				end
			end
		end
	end
	return true
end

--- Best site, or nil, why. o = { cx, cy (town centre), r (houses' extent radius), sampler, seed, industry
--- (ot_industry.forTown info or nil), neighbours = { {x, y} } (other town centres), roads = { {x, y} } (midpoints of
--- non-town streets near the town), deadEnds = { {x, y, node} } (joinable dead ends of the town), bounds = the map's
--- bounding box (ot_map) or nil, g = the town's street graph (links clear of its streets) or nil, obstacles =
--- ot_engine.obstacles (link and core clear of edges / tracks / constructions / fields beyond the snapshot) or nil,
--- bad = { {x, y} } sites refused before (BAD_R), junctions = { {x, y, d, deg, heads} } (country-road crossroads,
--- ot_roads: sites beside them get HAMLET_BONUS), hamlet = one junction (the crossroads hamlet motif, ot_motif_road:
--- only sites beside the junctions, the motif's own first; a shorter gap / link) or nil }. Returns
--- { x, y, dist, heading, deadEnd, link (pts), score, road (bool), low (bool), at ("ring" | "crossroads" | "light"),
--- junction, light (m to the nearest light works or nil) }, candidates count.
function M.pickSite(o)
	local s = o.sampler
	if s == nil or o.deadEnds == nil or #o.deadEnds == 0 then return nil, "noDeadEnd" end
	local h0 = T.height(s, o.cx, o.cy)
	local best, n = nil, 0
	-- candidates: the ring (RING_D x DIRS; not for a hamlet) and the quadrants of the crossroads
	local cands = {}
	if o.hamlet == nil then
		local rot = rng.unit(o.seed or 1, "satRot") * 2 * math.pi / M.DIRS
		for k = 0, M.DIRS - 1 do
			local a = rot + k * 2 * math.pi / M.DIRS
			for _, d in ipairs(M.RING_D) do
				if d >= (o.r or 0) + M.SAT_GAP then
					cands[#cands + 1] = { x = o.cx + math.cos(a) * d, y = o.cy + math.sin(a) * d, d = d, a = a, k = k,
						gap = M.SAT_GAP, minLink = M.MIN_LINK }
				end
			end
		end
	end
	local js = {}
	if o.hamlet then js[1] = o.hamlet end
	for _, j in ipairs(o.junctions or {}) do
		if j ~= o.hamlet and not (o.hamlet and G.dist(j.x, j.y, o.hamlet.x, o.hamlet.y) < 1) then js[#js + 1] = j end
	end
	for ji, j in ipairs(js) do
		local jd = G.dist(o.cx, o.cy, j.x, j.y)
		if jd >= M.HAMLET_D[1] and jd <= M.HAMLET_D[2] and j.own ~= false then
			for _, q in ipairs(M.quadrants(j.heads)) do
				for _, qd in ipairs(M.HAMLET_R) do
					local x, y = j.x + math.cos(q) * qd, j.y + math.sin(q) * qd
					local d = G.dist(o.cx, o.cy, x, y)
					cands[#cands + 1] = { x = x, y = y, d = d, a = G.atan2(y - o.cy, x - o.cx), k = 1000 + ji * 10 + qd,
						gap = M.HAMLET_GAP, minLink = M.HAMLET_MIN_LINK, junction = j,
						bonus = (o.hamlet and ji == 1) and M.HAMLET_PICK or M.HAMLET_BONUS }
				end
			end
		end
	end
	for _, c in ipairs(cands) do
		if o.yield then o.yield() end   -- (2026-10-21: the driver's step note between the candidates, TICKCOST atStep)
		local x, y, d, a = c.x, c.y, c.d, c.a
		if d >= (o.r or 0) + c.gap then
			-- (map edge, ot_map 2026-10-13: the core and its growth radius inside the margin)
			local ok = not MAP.nearEdge(o.bounds, x, y, MAP.MARGIN + M.CORE_R) and not wetNear(s, x, y, M.WET_R)
			for _, b in ipairs(o.bad or {}) do
				if ok and G.dist(x, y, b[1], b[2]) < M.BAD_R then ok = false end
			end
			local sl = ok and meanSlope(s, x, y, M.CORE_R * 0.5) or 1
			ok = ok and sl <= M.MAX_SLOPE
			-- (heavy / medium works only: a farm or a light works beside the village is fine, even welcome; M2)
			local pen = ok and IND.penHeavy(o.industry, x, y) or 0
			ok = ok and pen <= M.HEAVY_PEN
			if ok then
				for _, nb in ipairs(o.neighbours or {}) do
					local dn = G.dist(x, y, nb[1], nb[2])
					if dn < M.NEIGHBOUR_MIN or dn < d * 1.15 then ok = false break end
				end
			end
			-- the link: from one of the LINK_TRIES nearest joinable dead ends (minLink .. d + 50 m away), dry, gentle,
			-- and clear of the existing streets (2026-10-13, real map run: Harwich's and Workington's links crossed or
			-- ran along a street, the planner dropped that piece and the rest was "disconnected")
			local de, deD, link = nil, math.huge, nil
			if ok then
				local near = {}
				for _, e in ipairs(o.deadEnds) do
					local dd = G.dist(x, y, e[1], e[2])
					if dd <= d + 50 and dd >= c.minLink and dd <= M.MAX_LINK then near[#near + 1] = { e = e, d = dd } end
				end
				table.sort(near, function(p, q)
					if p.d ~= q.d then return p.d < q.d end
					return p.e[3] < q.e[3]
				end)
				for i = 1, math.min(#near, M.LINK_TRIES) do
					local e = near[i].e
					local pts = M.linkPts(e[1], e[2], x, y, o.seed, s)
					if not T.wetAlong(s, pts, 20, 40) and T.pathMaxGrade(s, pts, 40) <= M.LINK_GRADE
						and M.linkClear(o.g, pts, e[3]) and M.clearOfObstacles(o.obstacles, pts, M.START_SKIP) then
						-- the core streets too (a field or track beside the site)
						local coreOk = true
						if o.obstacles then
							for j, st in ipairs(M.streets({ x = x, y = y, deadEnd = e, link = pts })) do
								if j > 1 and not M.clearOfObstacles(o.obstacles, st.pts) then coreOk = false break end
							end
						end
						if coreOk then
							de, deD, link = e, near[i].d, pts
							break
						end
					end
				end
				ok = de ~= nil
			end
			if ok then
				n = n + 1
				local road = c.junction ~= nil
				if not road then
					for _, rp in ipairs(o.roads or {}) do
						if G.dist(x, y, rp[1], rp[2]) <= M.ROAD_R then road = true break end
					end
				end
				local low = T.height(s, x, y) < h0 - 2
				local light = IND.nearestLight(o.industry, x, y)
				local nearLight = light ~= nil and light >= M.LIGHT_MIN and light <= M.LIGHT_R
				-- lower is better: flat, short link, near a road, low ground, away from industry, beside a farm / light
				-- works, at a crossroads, seeded jitter
				-- (§63: a site in or beside dense forest, and a wooded link, score worse: the core's streets fill with houses to
				-- lot depth and the woods go; deep forest towns' satellites may sit in the woods)
				local wood = 0
				if o.forest and o.forest.cover and not o.deep and M.FOREST_W > 0 then
					local reach = SK.POINT_R + SK.CLEAR_M
					wood = M.FOREST_W * (1 - math.min(1, SK.pointClear(o.forest, x, y) / reach))
						+ M.LINK_WOOD_W * FO.pen({ grid = o.forest }, link)
				end
				local score = sl / M.MAX_SLOPE + 0.3 * (deD / 1500) + pen * 2 - (road and M.ROAD_BONUS or 0)
					- (low and M.LOW_BONUS or 0) - (nearLight and M.LIGHT_BONUS or 0) - (c.bonus or 0) + wood
					+ 0.25 * rng.unit(o.seed or 1, "satSite", c.k, math.floor(d))
				if best == nil or score < best.score then
					best = { x = x, y = y, dist = d, heading = a, deadEnd = de, link = link, score = score, road = road,
						low = low, linkLen = deD, slope = sl, junction = c.junction, light = light,
						at = c.junction and "crossroads" or (nearLight and "light" or "ring") }
				end
			end
		end
	end
	if best == nil then return nil, o.hamlet and "noHamletSite" or "noSite" end
	return best, n
end

--- Headings into the quadrants of a junction whose roads leave at `heads` (rad): the bisector of every gap of at
--- least QUAD_MIN between neighbouring roads (none given: four diagonals).
function M.quadrants(heads)
	local hs = {}
	for _, h in ipairs(heads or {}) do hs[#hs + 1] = G.wrap(h) end
	table.sort(hs)
	if #hs == 0 then return { math.pi / 4, 3 * math.pi / 4, -3 * math.pi / 4, -math.pi / 4 } end
	local out = {}
	for i = 1, #hs do
		local a, b = hs[i], hs[i % #hs + 1]
		local gap = b - a
		if i == #hs then gap = gap + 2 * math.pi end
		if #hs == 1 then gap = 2 * math.pi end
		if gap >= M.QUAD_MIN then out[#out + 1] = G.wrap(a + gap / 2) end
	end
	return out
end

--- Street polylines of the first satellite increment (ot_plan streets): the link from the dead end (startNode) to the
--- site, then the core: a main street through the site along the link's direction and two cross streets.
function M.streets(site)
	local de = site.deadEnd
	local link = site.link
	-- (2026-10-14 late: the link is a curved country lane, ot_lead.mark: no lots, so no empty town street; the core
	-- streets are its end streets, dosed at the seed build)
	local out = { { pts = link, class = "small", startNode = de[3], sat = "link", key = "sat:link", curved = true,
		lead = "lane" } }
	local a = G.heading(link[#link - 1][1], link[#link - 1][2], site.x, site.y)
	local ux, uy = math.cos(a), math.sin(a)
	local px, py = -uy, ux
	local B = M.BLOCK
	local x, y = site.x, site.y
	-- main street on through the site (one block beyond), cross streets at the site and one block on
	out[#out + 1] = { pts = { { x, y }, { x + ux * B, y + uy * B } }, class = "small", sat = "core", key = "sat:main", lead = "end" }
	out[#out + 1] = { pts = { { x - px * B * 0.8, y - py * B * 0.8 }, { x, y }, { x + px * B * 0.8, y + py * B * 0.8 } },
		class = "small", sat = "core", key = "sat:cross1", lead = "end" }
	-- (CORE_SMALL, 2026-10-14: 3 edges; the far cross street waits for the growth, M.growStreets)
	if M.CORE_SMALL then return out end
	local x2, y2 = x + ux * B, y + uy * B
	out[#out + 1] = { pts = { { x2, y2 }, { x2 + px * B * 0.6, y2 + py * B * 0.6 } }, class = "small", sat = "core",
		key = "sat:cross2a", lead = "end" }
	out[#out + 1] = { pts = { { x2, y2 }, { x2 - px * B * 0.6, y2 - py * B * 0.6 } }, class = "small", sat = "core",
		key = "sat:cross2b", lead = "end" }
	return out
end

--- Growth streets: each dead end of the satellite (nodes within CORE_R of the site, degree 1, not the link's start)
--- extended by one block straight on, plus a short side street at its end; seeded order. g = the town graph (ot_graph),
--- site = { x, y }, seed. Returns streets (startNode set).
function M.growStreets(g, site, seed)
	local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do
		local node = g.nodeById[n]
		if node and not node.noJoin and G.dist(node.x, node.y, site.x, site.y) <= M.CORE_R then ends[#ends + 1] = node end
	end
	table.sort(ends, function(a, b)
		return rng.unit(seed or 1, "satGrow", a.id) < rng.unit(seed or 1, "satGrow", b.id)
	end)
	local out = {}
	for _, node in ipairs(ends) do
		local e = g.edgeById[g.adj[node.id][1]]
		local other = e and g.nodeById[e.n0 == node.id and e.n1 or e.n0]
		if other then
			local a = G.heading(other.x, other.y, node.x, node.y)
			local B = M.BLOCK * 0.9
			local ex, ey = node.x + math.cos(a) * B, node.y + math.sin(a) * B
			if G.dist(ex, ey, site.x, site.y) <= M.CORE_R then
				out[#out + 1] = { pts = { { node.x, node.y }, { ex, ey } }, class = "small", startNode = node.id, sat = "grow",
					key = "sat:grow:" .. node.id }
				local side = rng.unit(seed or 1, "satSide", node.id) < 0.5 and 1 or -1
				local sx, sy = ex + math.cos(a + side * math.pi / 2) * B * 0.7, ey + math.sin(a + side * math.pi / 2) * B * 0.7
				out[#out + 1] = { pts = { { ex, ey }, { sx, sy } }, class = "small", sat = "grow", key = "sat:side:" .. node.id }
			end
		end
	end
	return out
end

--- Meadow discs between the town and the satellite (style.greens entries {x, y, r}): along the link at 30-75 % of
--- its length, each kept 0.8 x CORE_R clear of the satellite and 60 m clear of the link's start (the town's edge), so the
--- town's own plan leaves the gap open.
function M.gapGreens(site)
	local out = {}
	local link = site.link
	if link == nil or #link < 2 then return out end
	local L = site.linkLen or G.dist(link[1][1], link[1][2], link[#link][1], link[#link][2])
	local r0 = math.max(60, math.min(110, 0.12 * L))
	for _, t in ipairs({ 0.3, 0.45, 0.6, 0.75 }) do
		local x, y = G.polyAt(link, t)
		local r = math.min(r0, G.dist(x, y, site.x, site.y) - 0.8 * M.CORE_R, G.dist(x, y, link[1][1], link[1][2]) - 60)
		if r >= 40 then out[#out + 1] = { x, y, r } end
	end
	return out
end

--- Core dose points around a satellite site (a restored satellite has no build points): FILL_OFFSET-ish beside the
--- site on two sides along the link's last direction when known, else east / north. Returns { {x, y}, {x, y} }.
function M.corePoints(site, off)
	off = off or 20
	local a = 0
	local link = site and site.link
	if link and #link >= 2 then a = G.heading(link[#link - 1][1], link[#link - 1][2], site.x, site.y) end
	local ux, uy = math.cos(a), math.sin(a)
	local px, py = -uy, ux
	local B = M.BLOCK * 0.5
	return { { site.x + ux * B + px * off, site.y + uy * B + py * off }, { site.x - px * off * 1.5, site.y - py * off * 1.5 } }
end

--- What a satellite's watch does at a check of its town (2026-10-14): st = the satellite state { us (seed build, real
--- us), doses (core doses after the seed's), lastDoseUs, emptyChecks, retired, restored }, near = buildings at the
--- site, nowUs. Returns "dose" (a core dose now), "retire", or nil; and updates emptyChecks.
function M.watch(st, near, nowUs)
	if st == nil or st.retired then return nil end
	if (near or 0) > 0 then
		st.emptyChecks = 0
		return nil
	end
	local since = st.lastDoseUs or st.us
	if (st.doses or 0) < M.REDOSES and since ~= nil and nowUs - since >= M.REDOSE_S * 1e6 then return "dose" end
	if (st.doses or 0) < M.REDOSES and since == nil then return "dose" end
	st.emptyChecks = (st.emptyChecks or 0) + 1
	if (st.doses or 0) >= M.REDOSES and st.emptyChecks >= M.RETIRE_CHECKS then return "retire" end
	return nil
end

--- Buildings within CORE_R of the site (pts = { {x, y} }).
function M.buildingsNear(site, pts)
	local n = 0
	for _, p in ipairs(pts or {}) do
		if G.dist(site.x, site.y, p[1], p[2]) <= M.CORE_R then n = n + 1 end
	end
	return n
end

return M
