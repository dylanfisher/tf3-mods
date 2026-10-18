-- Organic Towns: town-structure / era motifs (pure). Phase M3 of the motifs plan (plans/square_organic_towns/
-- MOTIFS_BRIEF.md, 2026-10-13). Registered into the ot_motif registry by ot_motif (TW.registerAll(MO)), MO.IDS 10-13.
--
--   ring_road         (drawn; Vienna's Ringstrasse, the German Wallring) a curved street around the old core where its walls
--                     would have stood: a circle around the centre at the core's extent when the motif was picked (saved on
--                     the frame, `rr`), joined head on to the core's radial dead ends (short stubs straight out of them) or
--                     through a dead end lying on it; the districts outside it are the 19th-c. extension with the grid
--                     trend's straighter look (style.outer from the ring). Never splits a town street: where the town's
--                     streets cross or run along the circle (or water, steep ground, a country road, the map edge) the ring
--                     is cut, and only the arcs between two radial joints are laid (a full ring when nothing blocks it).
--   station_quarter   (derived: present whenever a rail passenger station stands near the town; the gameplay hook) a small
--                     straight grid (3 x 3 or 4 x 4 blocks) on the station's forecourt side, aligned with the station, a
--                     station square street along its front and a straight Bahnhofstrasse from the town to the grid. The
--                     driver re-reads the stations every STATION_REFRESH_S (stations appear over time) and the master plan
--                     is rebuilt when a town's stations change (style.stationKey).
--   workers_terraces  (drawn; to ~1935, fading by 1950) short parallel terrace rows (narrow streets 34-48 m apart: back-to-back single
--                     rows of dense houses) off a short spine from the town toward a LIGHT works (food, textiles, brewery
--                     ...; farms / forests / fisheries are no factories); the motif's pieces are free of the away-from-
--                     industry cost (ot_select `indFree`), heavy / medium works keep the away preference and exclude it.
--   culdesac_pods     (drawn; post-1950) suburban closes: a gently curving collector out of town with 3-6 short dead-end
--                     closes off alternate sides (plain dead ends: the base town templates have no turning head and a
--                     loop head would need a 70 m radius, ot_plan.MIN_RADIUS), no other plan streets behind the closes
--                     (meadow), the collector's and closes' streets locked (no game side streets on them).
--
-- Junctions where two lines must meet (the ring's joints, the quarter's grid crossings, the plan's T's onto the ring):
-- the game joins only dead ends, so the pieces sharing such a junction are flagged motifBranch + motifJoin (ot_select
-- withBranches: a chosen piece takes the others at its ends along when the junction is new or still a dead end).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local GR = ug_require "square_organic_towns::/organic_towns/ot_grid.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local L = ug_require "square_organic_towns::/organic_towns/ot_motif_land.lua"
local RM = ug_require "square_organic_towns::/organic_towns/ot_motif_road.lua"

local M = {}

local sqrt, cos, sin, abs, floor, max, min = math.sqrt, math.cos, math.sin, math.abs, math.floor, math.max, math.min
local TAU = 2 * math.pi

M.ON = true   -- (off in the other offline tests: their baselines were measured without M3; tests F.withTownMotifs)

-- ring road
M.RR = {
	R = { 0.45, 160, 650 },  -- the ring's radius when first planned: houses' extent + this x block, clamped (m)
	TRY = 120, TRY_STEP = 10, -- ... then the radius of R .. R + TRY with the most stubs and least blocked ring wins
	STEP = 10,               -- m between samples along the circle
	ON = 8,                  -- m: a node this near the circle lies on it
	SNAP = 5,                -- m: a dead end this near the circle: the ring passes through it
	AWK = 22,                -- m: a dead end nearer the circle (inside) has no room for a stub: the ring keeps off it
	CLEAR = 16,              -- m: the planner's clearance of new streets from others (ot_plan clearEdge)
	REACH = 1.3,             -- x block: a stub at most this long
	DEV = math.rad(45),      -- a stub's dead end points outward within this of the radial
	MIN_ARC = 120,           -- m: shorter arcs left out
	JOINT_GAP = 40,          -- m along the ring between joints at least
	GRADE = 0.9,             -- x maxSlope between circle samples at most
	GENTLE = 0.5,            -- medium where the ring's grade stays <= this x maxSlope, else small
	LOOK = 0.35,             -- the districts outside get at least this grid look (ot_grid)
	ROOM = 26,               -- m: the plan's own streets keep this far from the ring (but at a T)
	STYLE = { EU_ORGANIC = 1, EU_EXTENSION = 0.7, MED_HILL = 0.45 },
	MIN_RADIUS = 140,        -- m: the houses' extent at least (an old core)
	SCORE = 0.5,             -- eligibility at best (x style, era, flatness, shape)
	ERA = { 1940, 1975 },    -- eligibility x 1 up to the first year, falling to x 0.45 at the second (era range 1900+,
	                         -- 2026-10-13: an old-town motif of the early game; was 0.45 before 1850 -> 1 from 1900)
}
-- station quarter
M.SQ = {
	REACH = 800,             -- m beyond the houses' extent: a station this far out at most
	INSIDE = 1.5,            -- x block: ... and no deeper inside the houses' extent than this
	FRONT = 17,              -- m: the forecourt point in front of the station's origin (main building's front, -Y)
	GAP = 22,                -- m from the forecourt point to the station square street
	N = { 3, 4 },            -- blocks each way (seeded per station)
	LEN = { 0.9, 60, 100 },  -- block length along the station: x block length, clamped
	DEP = { 1.0, 45, 80 },   -- block depth away from it: x block depth, clamped
	TRACK = 20,              -- m: grid streets keep this far from tracks
	ROAD = 18,               -- m: ... from country roads
	GRADE = 0.8,             -- x maxSlope per block side at most
	SIDE_DOT = -0.2,         -- the forecourt faces the town when dot(front, toward the town) >= this
	FLIP_AWAY = true,        -- facing away: the quarter on the station's back (the town side), side=back (final test)
}
-- workers' terraces
M.WT = {
	YEAR = { 1935, 1950 },   -- x 1 up to the first year, falling to 0 at the second (era range 1900+, 2026-10-13: was
	                         -- 1900 / 1930, a 30-year window at the earliest start)
	D = { 120, 900 },        -- m beyond the houses' extent: the works this far out
	GAP = 110,               -- m: the last row this far from the works
	ROWS = { 3, 5 },         -- rows (seeded)
	SP = { 0.8, 40, 52 },    -- row spacing: x block depth, clamped (m): back-to-back lots between two rows
	HALF = { 1.0, 70, 100 }, -- each row's half length (both sides of the spine): x block length, clamped
	MIN_HALF = 40,
	GRADE = 0.75,
	CLEAR_WORKS = 90,        -- m: rows keep this far from every works
	HEAVY = 450,             -- m: no heavy / medium works this near the light one
	NOT_FACTORY = { "farm", "forest", "orchard", "fishing", "shrimp" },
	ROAD = 20,
	SCORE = 0.7,             -- eligibility at best (x era, style)
}
-- cul-de-sac pods
M.CP = {
	YEAR = { 1945, 1970 },   -- x 0 before the first year, 1 from the second
	STYLE = { NA_SUBURB = 1, EU_EXTENSION = 0.8, NA_GRID = 0.6, NORDIC = 0.5, EU_ORGANIC = 0.5, MED_HILL = 0.3,
		SUPERBLOCK = 0.2, MED_ENSANCHE = 0.2 },
	LEN = { 380, 560 },      -- m of collector beyond the houses (seeded)
	MIN_BEYOND = 220,
	STEP = 20,
	CURV = 1 / 700,          -- rad per m at most: a gently curving collector (seeded per direction)
	DIRS = 12,
	CLOSES = { 3, 6 },
	GAP = { 85, 120 },       -- m between closes (seeded)
	CLOSE_LEN = { 1.5, 60, 110 },
	CLOSE_MIN = 45,
	GREEN = 80,              -- m beyond the closes' ends kept free of plan streets (the green behind)
	GRADE = 0.7,
	CLOSE_GRADE = 0.75,
	ROAD = 22,
	OURS = 2,                -- locked edges along a direction: the collector is there (keep it)
	SCORE = 0.55,            -- eligibility at best (x style, era, flatness)
}

local function blk(style) return L.blk(style) end
local function unit(x, y)
	local l = sqrt(x * x + y * y)
	if l < 1e-9 then return 0, 0, 0 end
	return x / l, y / l, l
end
local function styleK(style) return L.styleK(style) end

--- Flags pieces (list) so the pieces sharing their junctions are chosen together (ot_select withBranches).
local function pair(pc)
	pc.motifBranch, pc.motifJoin = true, true
end

--- true when the straight segment a-b crosses a street of graph g. Edges lying along it (both ends within ALONG m of the
--- segment's line: its own built piece, snapped a few metres off) don't count.
M.ALONG = 10
local function crossesGraph(g, ax, ay, bx, by)
	if g == nil or #g.edges == 0 then return false end
	for _, id in ipairs(OG.edgesNear(g, ax, ay, bx, by, 1)) do
		local e = g.edgeById[id]
		local a, b = e and g.nodeById[e.n0], e and g.nodeById[e.n1]
		if a and b and G.segIntersect(ax, ay, bx, by, a.x, a.y, b.x, b.y, 1e-4) then
			-- (perpendicular distance to the segment's line: the built piece runs on beyond the segment's end)
			local ux, uy, l = unit(bx - ax, by - ay)
			local da = l > 0 and abs((a.x - ax) * uy - (a.y - ay) * ux) or 0
			local db = l > 0 and abs((b.x - ax) * uy - (b.y - ay) * ux) or 0
			if not (da <= M.ALONG and db <= M.ALONG) then return true end
		end
	end
	return false
end

--- true when the straight segment a-b crosses one of the plan's pieces of motif id other than those of line `own`
--- (e.g. a close across the collector's link arc from the town).
M.crossesGraph = crossesGraph   -- (M4)
M.pair = pair

local function crossesMotif(mp, id, own, ax, ay, bx, by)
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == id and pc.motifLine ~= own then
			for i = 2, #pc.pts do
				local p, q = pc.pts[i - 1], pc.pts[i]
				if G.segIntersect(ax, ay, bx, by, p[1], p[2], q[1], q[2], 1e-4) then return true end
			end
		end
	end
	return false
end

local function segsOf(style)
	local roads = style.roads
	return roads and roads.segs or {}
end

---------------------------------------------------------------------------
-- ring road

-- Organic ring geometry (style.ringWobble, ot_style ORGANIC_RINGS, 2026-10-14 §56; the showcase run 2026-10-14_2150's EU
-- organic town: the ring road's long circle arcs read as "big equal circles"): the radius wobbles round the town, R x (1 +
-- sum of WOBBLE harmonics k = 2, 3, 5 with seeded phases), at most ~10 %; the curve stays far above the town streets'
-- radius limit (R >= 160 m). The saved `rr` is the profile's mean radius.
M.RR.WOBBLE = { { 2, 0.05 }, { 3, 0.035 }, { 5, 0.012 } }

--- The ring's radius at angle th: a function of th (the profile; a plain circle without style.ringWobble).
function M.ringRad(style, R)
	if not style.ringWobble then return function() return R end end
	local seed = style.seed or 1
	local hs = {}
	for i, h in ipairs(M.RR.WOBBLE) do
		hs[i] = { h[1], h[2] * (0.6 + 0.8 * rng.unit(seed, "rrAmp", i)), TAU * rng.unit(seed, "rrPhase", i) }
	end
	return function(th)
		local w = 0
		for _, h in ipairs(hs) do w = w + h[2] * sin(h[1] * th + h[3]) end
		return R * (1 + w)
	end
end

--- The ring's first radius (no saved one): the houses' extent + R[1] x block, clamped.
function M.ringR0(style)
	local rr = M.RR
	return G.round(G.clamp((style.radius or 0) + rr.R[1] * blk(style), rr.R[2], rr.R[3]), 1)
end

--- The radius of an earlier session's ring from the mod's locked streets lying on a circle around the centre, or nil.
function M.ringFromLocked(style, g)
	if g == nil then return nil end
	local cx, cy = style.centre[1], style.centre[2]
	local bins = {}
	for _, e in ipairs(g.edges) do
		if e.locked then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				local da, db = G.dist(cx, cy, a.x, a.y), G.dist(cx, cy, b.x, b.y)
				local l = G.dist(a.x, a.y, b.x, b.y)
				-- (along a circle: both ends at one distance, the chord square to the radial)
				if da > 100 and abs(da - db) < 4 and l > 20 then
					local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
					local sag = l * l / (8 * da)
					if abs(G.dist(cx, cy, mx, my) - (da - sag)) < 4 then
						local k = floor((da + db) / 20 + 0.5)
						bins[k] = bins[k] or { n = 0, s = 0 }
						bins[k].n, bins[k].s = bins[k].n + 1, bins[k].s + (da + db) / 2
					end
				end
			end
		end
	end
	local best = nil
	for _, b in pairs(bins) do
		if b.n >= 2 and (best == nil or b.n > best.n or (b.n == best.n and b.s / b.n < best.s / best.n)) then best = b end
	end
	return best and G.round(best.s / best.n, 1) or nil
end

--- The ring at radius R on graph g (pure): { R, n, ok (samples), joints = { { th, x, y, kind = "stub"|"snap"|"node",
--- node, dx, dy (stub: the dead end) } }, arcs = { { a (sample), b, joints, closed } }, blocked (m), awkward (dead ends
--- too near the circle), stubs }.
function M.ringScan(style, g, sampler, R)
	local rr = M.RR
	local cx, cy = style.centre[1], style.centre[2]
	local Rt = M.ringRad(style, R)
	local function angle(x, y) return G.atan2(y - cy, x - cx) end
	-- (the distance of (x, y) from the ring along its radial, + outside)
	local function off(x, y) return G.dist(cx, cy, x, y) - Rt(angle(x, y)) end
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	local n = max(36, math.ceil(TAU * R / rr.STEP))
	local dth = TAU / n
	local ok, z = {}, {}
	for k = 0, n - 1 do
		local th = k * dth
		local x, y = cx + cos(th) * Rt(th), cy + sin(th) * Rt(th)
		ok[k] = not (L.wetNear(sampler, x, y, setback) or L.offEdge(style, x, y))
		z[k] = T.height(sampler, x, y)
	end
	local stepLen = TAU * R / n
	for k = 0, n - 1 do
		local k2 = (k + 1) % n
		if abs(z[k2] - z[k]) / stepLen > rr.GRADE * maxSlope then ok[k], ok[k2] = false, false end
	end
	local function idx(th) return floor(G.wrap(th) % TAU / dth + 0.5) % n end
	local function blockAt(th, half)
		local w = math.ceil(half / dth)
		local k0 = idx(th)
		for d = -w, w do ok[(k0 + d) % n] = false end
	end
	local halfW = (rr.CLEAR + 4) / R
	-- country roads (beyond the snapshot too): nothing within CLEAR of the circle
	for _, sg in ipairs(segsOf(style)) do
		local l = G.dist(sg[1], sg[2], sg[3], sg[4])
		local m = max(1, math.ceil(l / 8))
		for i = 0, m do
			local x, y = sg[1] + (sg[3] - sg[1]) * i / m, sg[2] + (sg[4] - sg[2]) * i / m
			if abs(off(x, y)) < rr.CLEAR then blockAt(angle(x, y), halfW) end
		end
	end
	local joints, awkward = {}, 0
	local jointNode = {}
	if g then
		local function onC(nd) return abs(off(nd.x, nd.y)) < rr.ON end
		local function along(e)
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if not (a and b and onC(a) and onC(b)) then return false end
			local l = G.dist(a.x, a.y, b.x, b.y)
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			local dm = G.dist(cx, cy, mx, my)
			local Rm = Rt(angle(mx, my))
			return abs(dm - (Rm - l * l / (8 * Rm))) < rr.ON
		end
		local alongE = {}
		for _, e in ipairs(g.edges) do if along(e) then alongE[e.id] = true end end
		local reach = rr.REACH * blk(style)
		for _, nd in ipairs(g.nodes) do
			-- (the node's distance from the centre against the ring's radius in its direction)
			local Rn = Rt(angle(nd.x, nd.y))
			local d = G.dist(cx, cy, nd.x, nd.y) - Rn + R
			local deg = OG.degree(g, nd.id)
			local hasAlong = false
			for _, eid in ipairs(g.adj[nd.id] or {}) do if alongE[eid] then hasAlong = true end end
			if deg == 1 and not nd.noJoin and abs(d - R) < rr.SNAP then
				joints[#joints + 1] = { th = angle(nd.x, nd.y), x = nd.x, y = nd.y, kind = "snap", node = nd.id }
				jointNode[nd.id] = true
			elseif hasAlong and abs(d - R) < rr.ON then
				joints[#joints + 1] = { th = angle(nd.x, nd.y), x = nd.x, y = nd.y, kind = "node", node = nd.id }
				jointNode[nd.id] = true
			elseif deg == 1 and not nd.noJoin and d < R - rr.AWK and d >= R - reach then
				-- a radial dead end: a stub straight on out of it to the circle (head on)
				local e = g.edgeById[g.adj[nd.id][1]]
				local od = G.wrap(OG.headingFrom(g, e, nd.id) + math.pi)
				local ux, uy = cos(od), sin(od)
				local px, py = nd.x - cx, nd.y - cy
				local bq = px * ux + py * uy
				-- (where the ray meets the ring: on the circle of the ring's radius there, a few rounds for the profile)
				local Rq = Rn
				local disc = bq * bq - (px * px + py * py - Rq * Rq)
				local t = disc >= 0 and (-bq + sqrt(disc)) or nil
				for _ = 1, 3 do
					if t == nil then break end
					Rq = Rt(angle(nd.x + ux * t, nd.y + uy * t))
					disc = bq * bq - (px * px + py * py - Rq * Rq)
					t = disc >= 0 and (-bq + sqrt(disc)) or nil
				end
				if t then
					local qx, qy = nd.x + ux * t, nd.y + uy * t
					local th = angle(qx, qy)
					if t >= rr.AWK and t <= reach and G.angleDiff(od, th) <= rr.DEV then
						local pts = { { nd.x, nd.y }, { qx, qy } }
						if L.linkClear(g, pts, nd.id) and T.pathMaxGrade(sampler, pts) <= maxSlope
							and not T.wetAlong(sampler, pts, setback) then
							joints[#joints + 1] = { th = th, x = qx, y = qy, kind = "stub", node = nd.id, dx = nd.x, dy = nd.y,
								len = t }
						end
					end
				end
			elseif deg == 1 and abs(d - R) < rr.AWK then
				awkward = awkward + 1
			end
		end
		-- the town's streets crossing / running along the circle block it (but at a joint, and the ring's own streets)
		for _, nd in ipairs(g.nodes) do
			if not jointNode[nd.id] and abs(off(nd.x, nd.y)) < rr.ON then blockAt(angle(nd.x, nd.y), halfW) end
		end
		for _, e in ipairs(g.edges) do
			if not alongE[e.id] then
				local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
				if a and b then
					local l = G.dist(a.x, a.y, b.x, b.y)
					local m = max(1, math.ceil(l / 8))
					for i = 0, m do
						local x, y = a.x + (b.x - a.x) * i / m, a.y + (b.y - a.y) * i / m
						if abs(off(x, y)) < rr.CLEAR then
							local atJoint = (jointNode[e.n0] and G.dist(x, y, a.x, a.y) < rr.CLEAR + 6)
								or (jointNode[e.n1] and G.dist(x, y, b.x, b.y) < rr.CLEAR + 6)
							if not atJoint then blockAt(angle(x, y), halfW) end
						end
					end
				end
			end
		end
	end
	-- joints on bad samples out; stubs too near another joint out (nodes / snaps first)
	table.sort(joints, function(p, q)
		local rp, rq = p.kind == "stub" and 1 or 0, q.kind == "stub" and 1 or 0
		if rp ~= rq then return rp < rq end
		if p.th ~= q.th then return p.th < q.th end
		return (p.node or 0) < (q.node or 0)
	end)
	local kept = {}
	for _, j in ipairs(joints) do
		local good = ok[idx(j.th)]
		if j.kind == "stub" then
			for _, o in ipairs(kept) do
				if G.angleDiff(o.th, j.th) * R < rr.JOINT_GAP then good = false; break end
			end
		else
			good = true   -- (a built joint stays a joint)
		end
		if good then j.k = idx(j.th); kept[#kept + 1] = j end
	end
	-- (a stub meets the ring at its sample point: the ring's junctions sit on the samples)
	for _, j in ipairs(kept) do
		if j.kind == "stub" then
			j.th = j.k * dth
			j.x, j.y = cx + cos(j.th) * Rt(j.th), cy + sin(j.th) * Rt(j.th)
		end
	end
	table.sort(kept, function(p, q) return p.k < q.k end)
	local blocked, all = 0, true
	for k = 0, n - 1 do if not ok[k] then blocked = blocked + stepLen; all = false end end
	-- arcs: runs of good samples (circular); each from its first joint to its last
	local arcs = {}
	if all then
		if #kept >= 1 then arcs[1] = { a = kept[1].k, b = kept[1].k + n, joints = kept, closed = true } end
	else
		local start = nil
		for k = 0, n - 1 do if not ok[k] then start = k; break end end
		local k = start
		local run = nil
		for _ = 1, n do
			k = (k + 1) % n
			local kk = k
			if ok[kk] then
				if run == nil then run = { s = kk, e = kk } else run.e = kk end
			elseif run then
				arcs[#arcs + 1] = run
				run = nil
			end
		end
		if run then arcs[#arcs + 1] = run end
		local out = {}
		for _, r in ipairs(arcs) do
			local e = r.e
			if e < r.s then e = e + n end
			local js = {}
			for _, j in ipairs(kept) do
				local jk = j.k
				if jk < r.s then jk = jk + n end
				if jk >= r.s and jk <= e then js[#js + 1] = { j = j, k = jk } end
			end
			table.sort(js, function(p, q) return p.k < q.k end)
			if #js >= 2 and (js[#js].k - js[1].k) * stepLen >= rr.MIN_ARC then
				local list = {}
				for _, x in ipairs(js) do list[#list + 1] = x.j end
				out[#out + 1] = { a = js[1].k, b = js[#js].k, joints = list, closed = false }
			end
		end
		arcs = out
	end
	local stubs = 0
	for _, j in ipairs(kept) do if j.kind == "stub" then stubs = stubs + 1 end end
	return { R = R, n = n, dth = dth, ok = ok, joints = kept, arcs = arcs, blocked = blocked, awkward = awkward,
		stubs = stubs, closed = all and #arcs == 1 }
end

--- The ring's radius for this plan: the saved one, else the one an earlier plan this session chose, else the one an
--- earlier session's locked streets show, else the best of R0 .. R0 + TRY.
function M.ringRadius(style, m, g, sampler)
	if m.ringR then return m.ringR, m.ringSaved and "saved" or "session" end
	local Rl = M.ringFromLocked(style, g)
	if Rl then return Rl, "locked" end
	local R0 = m.ringR0 or M.ringR0(style)
	local best, bv = R0, math.huge
	for dR = 0, M.RR.TRY, M.RR.TRY_STEP do
		local sc = M.ringScan(style, g, sampler, R0 + dR)
		local planned = 0
		for _, a in ipairs(sc.arcs) do planned = planned + (a.b - a.a) end
		local v = (sc.n - planned) * TAU * sc.R / sc.n + 150 * sc.awkward - 40 * sc.stubs + 0.5 * dR
		if v < bv - 1e-6 then best, bv = R0 + dR, v end
	end
	return best, "picked"
end

--- The ring's plan geometry (pure): the scan + { lines = { { pts, joints = { { s, key, j } }, closed } }, R, src,
--- class } or nil, why.
function M.ringGeo(style, m, g, sampler)
	if sampler == nil then return nil, "noTerrain" end
	local R, src = M.ringRadius(style, m, g, sampler)
	local sc = M.ringScan(style, g, sampler, R)
	if #sc.arcs == 0 then return nil, (#sc.joints == 0 and "noJoint" or "blocked"), sc, R end
	local cx, cy = style.centre[1], style.centre[2]
	local Rt = M.ringRad(style, R)
	local lines = {}
	local zmax = 0
	for ai, a in ipairs(sc.arcs) do
		local pts = {}
		for k = a.a, a.b do
			local th = (k % sc.n) * sc.dth
			pts[#pts + 1] = { cx + cos(th) * Rt(th), cy + sin(th) * Rt(th) }
		end
		-- (the ends exactly on the joints' circle points)
		lines[#lines + 1] = { pts = pts, arc = a, i = ai }
		local gr = T.pathMaxGrade(sampler, pts)
		if gr > zmax then zmax = gr end
	end
	local cls = zmax <= M.RR.GENTLE * (style.maxSlope or 0.1) and "medium" or "small"
	return { R = R, src = src, scan = sc, lines = lines, class = cls, grade = zmax }
end

local function ringStyle(p, m, env)
	local fr = env.frame
	local R = fr and tonumber(fr.ringR) or nil
	if R then m.ringR, m.ringSaved = R, true end
	m.ringR0 = R or M.ringR0(p)
	-- the districts outside the ring: the 19th-c. extension, straighter as the grid trend rises (organic growers only)
	if p.grower == "organic" then
		local look = (p.gridBias and p.gridBias.look or 0) + GR.OUTER_EXTRA
		look = min(GR.LOOK_MAX, max(M.RR.LOOK, look))
		p.outer = { id = "EU_EXTENSION", from = m.ringR0, look = look }
		p._outerCache = nil
		m.outerFrom = m.ringR0
	end
end

local function ringPlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why, sc, R = M.ringGeo(style, m, env.g, env.terrain)
	if geo == nil then
		m.planWhy = why
		if sc then m.lastScan = { R = R, joints = #sc.joints, blocked = sc.blocked, awkward = sc.awkward } end
		-- (the radius chosen this session stays: the town's dead ends come later)
		if R and m.ringR == nil then m.ringR = R end
		mp.motifReanchor = true
		return
	end
	if m.ringR == nil then m.ringR = geo.R end
	local id = m.id
	local cx, cy = style.centre[1], style.centre[2]
	local jointKeys = {}
	local stops = {}
	local planned, made = 0, 0
	for _, ln in ipairs(geo.lines) do
		local ix = L.index(ln.pts)
		local js = {}
		for ji, j in ipairs(ln.arc.joints) do
			local key = "mrr:J" .. tostring(j.node or ji)
			jointKeys[key] = j
			local s
			if ji == 1 then s = 0 elseif ji == #ln.arc.joints and not ln.arc.closed then s = ix.len
			else s = select(2, L.nearest(ix, j.x, j.y, M.RR.ON + 10)) end
			if s then js[#js + 1] = { s = s, key = key, j = j } end
		end
		local first, last = js[1], js[#js]
		local mid = {}
		for i = 2, #js do
			if not (i == #js and not ln.arc.closed) then mid[#mid + 1] = { s = js[i].s, key = js[i].key } end
		end
		mp.junctions[first.key] = { ln.pts[1][1], ln.pts[1][2] }
		local endKey = ln.arc.closed and first.key or last.key
		mp.junctions[endKey] = mp.junctions[endKey] or { ln.pts[#ln.pts][1], ln.pts[#ln.pts][2] }
		local res = L.overlay(mp, ln.pts, { prefix = "mrr" .. ln.i, motif = id, class = geo.class, costK = L.COST_MAIN,
			lead = true, every = 90, stops = mid, part = "ring", band = L.band(style), startKey = first.key,
			endKey = endKey, teeK = L.COST_TEE })
		ln.ix, ln.res = ix, res
		for _, st in ipairs(res.stops) do
			if st.key:find(":X", 1, true) then stops[st.key] = true end
		end
		planned = planned + ix.len
		made = made + 1
	end
	-- stubs: the radial dead ends straight on to the ring (head on)
	local stubs, stubN = {}, 0
	for key, j in pairs(jointKeys) do
		if j.kind == "stub" and mp.junctions[key] then
			local dk = "mrr:D" .. tostring(j.node)
			mp.junctions[dk] = { j.dx, j.dy }
			L.overlay(mp, { { j.dx, j.dy }, { j.x, j.y } }, { prefix = "mrrS" .. tostring(j.node), motif = id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = dk, endKey = key, part = "stub", lead = true })
			stubs[#stubs + 1] = j
			stubN = stubN + 1
		end
	end
	table.sort(stubs, function(p, q) return p.node < q.node end)
	-- pieces meeting at a joint / a T come together (the game joins only dead ends)
	local tee = 0
	for _, pc in ipairs(mp.pieces) do
		local atJ = jointKeys[pc.a] or jointKeys[pc.b]
		local atX = stops[pc.a] or stops[pc.b]
		if pc.motif == id and (atJ or atX) then pair(pc)
		elseif pc.motif == nil and atX then
			tee = tee + 1
			pc.motif, pc.motifLead, pc.motifLine, pc.motifPart = id, true, "mrrT" .. tee, "tee"
			pair(pc)
		end
	end
	-- (the ring keeps its room: the town's plan streets meet it only head on)
	local ixs = {}
	for _, ln in ipairs(geo.lines) do ixs[#ixs + 1] = ln.ix end
	RM.clearAround(mp, ixs, M.RR.ROOM)
	geo.stubs, geo.planned, geo.tees, geo.made = stubs, planned, tee, made
	geo.circ = TAU * geo.R
	m.geo = geo
	m.planWhy = nil
	-- (a ring with arcs missing: plan again as the town grows, more radial dead ends may come)
	if not geo.scan.closed then mp.motifReanchor = true end
end

local function ringMeasure(env, m)
	local geo = m.geo
	if geo == nil then
		local ls = m.lastScan
		return { edges = 0, total = 0, houses = 0, text = string.format("none:%s,R=%s,joints=%s", tostring(m.planWhy or "-"),
			tostring(ls and ls.R or m.ringR or m.ringR0 or "-"), tostring(ls and ls.joints or "-")) }
	end
	local len, n, houses = 0, 0, 0
	for _, ln in ipairs(geo.lines) do
		local l, spans, k = L.builtAlong(env.g, ln.ix, 8)
		len, n = len + l, n + k
		houses = houses + L.housesAlong(env.pts, ln.ix, spans, 45)
	end
	local stubs = 0
	for _, j in ipairs(geo.stubs or {}) do
		if L.segBuilt(env.g, j.dx, j.dy, j.x, j.y, 8) then stubs = stubs + 1 end
	end
	-- radials: the ring's junctions with the town's streets (nodes on the circle with 3+ streets)
	local radials = 0
	local g = env.g
	local cx, cy = env.style.centre[1], env.style.centre[2]
	local Rt = M.ringRad(env.style, geo.R)
	for _, nd in ipairs(g and g.nodes or {}) do
		local Rn = Rt(G.atan2(nd.y - cy, nd.x - cx))
		if abs(G.dist(cx, cy, nd.x, nd.y) - Rn) < M.RR.ON and OG.degree(g, nd.id) >= 3 then radials = radials + 1 end
	end
	local cover = len / geo.circ
	return { edges = L.incEdges(env.inc, "mrr"), total = n, houses = houses, len = len, cover = cover, stubs = stubs,
		radials = radials, closed = geo.scan.closed and cover >= 0.9,
		text = string.format("R=%.0f(%s),arcs=%d,closedPlan=%s,planned=%.0f/%.0f,built=%.0f,cover=%.2f,radials=%d,joints=%d,"
			.. "stubs=%d/%d,tees=%d,blocked=%.0f,awkward=%d,class=%s,outer=%s", geo.R, geo.src, #geo.lines, tostring(geo.scan.closed),
			geo.planned, geo.circ, len, cover, radials, #geo.scan.joints, stubs, #(geo.stubs or {}), geo.tees or 0, geo.scan.blocked,
			geo.scan.awkward, geo.class, tostring(m.outerFrom and string.format("%.0f", m.outerFrom) or "-")) }
end

function M.ringEra(year)
	local e = M.RR.ERA
	return G.clamp(1 - 0.55 * ((tonumber(year) or 1900) - e[1]) / (e[2] - e[1]), 0.45, 1)
end

local function ringEligible(ctx)
	if not M.ON then return 0, "off" end
	local st = ctx.style
	local w = M.RR.STYLE[st.id] or 0
	if w <= 0 or st.metro then return 0, "style" end
	if (ctx.tier or 2) <= 1 then return 0, "small" end
	if (st.radius or 0) < M.RR.MIN_RADIUS then return 0, string.format("young:r=%.0f", st.radius or 0) end
	local t = ctx.terrain
	local ms = t and t.meanSlope or 0
	local flat = G.clamp((0.12 - ms) / 0.06, 0, 1)
	local era = M.ringEra(ctx.year)
	local shK = (ctx.shape == "linear" or ctx.shape == "shore") and 0.3 or 1
	local s = M.RR.SCORE * w * flat * era * shK
	if s <= 0 then return 0, string.format("rough:slope=%.3f", ms) end
	return s, string.format("core:r=%.0f,era=%.2f,slope=%.3f", st.radius or 0, era, ms)
end

---------------------------------------------------------------------------
-- station quarter

--- A town's station list key (ot_driver: the master plan is rebuilt when it changes).
function M.stationKey(list)
	if list == nil or #list == 0 then return "" end
	local parts = {}
	for _, s in ipairs(list) do parts[#parts + 1] = string.format("%.0f:%.0f", s.x or s[1] or 0, s.y or s[2] or 0) end
	table.sort(parts)
	return table.concat(parts, ";")
end

--- The station a quarter grows at: the nearest rail passenger station within the houses' extent + REACH (and no
--- deeper inside it than INSIDE blocks), d (m), or nil.
function M.stationFor(style)
	local list = style.railStations
	if list == nil or #list == 0 then return nil end
	local cx, cy = style.centre[1], style.centre[2]
	local r = style.radius or 0
	local best, bd = nil, math.huge
	for _, s in ipairs(list) do
		local x, y = s.x or s[1], s.y or s[2]
		if x and y then
			local d = G.dist(cx, cy, x, y)
			if d <= r + M.SQ.REACH and d >= r - M.SQ.INSIDE * blk(style) and not L.offEdge(style, x, y) and d < bd then
				best, bd = s, d
			end
		end
	end
	return best, best and bd or nil
end

--- The quarter's plan geometry (pure): { st, d, side, f = {x, y} (away from the station), u, O, n, len, dep, segs =
--- { { k1, j1, k2, j2, ok } }, junction(k, j) } or nil, why.
function M.stationGeo(style, g, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local S, d = M.stationFor(style)
	if S == nil then return nil, "noStation" end
	local sq = M.SQ
	local cx, cy = style.centre[1], style.centre[2]
	local sx, sy = S.x or S[1], S.y or S[2]
	local tx, ty = unit(cx - sx, cy - sy)
	local fx, fy, side
	if S.fx and S.fy and (S.fx ~= 0 or S.fy ~= 0) then
		fx, fy = unit(S.fx, S.fy)
		side = (fx * tx + fy * ty) >= sq.SIDE_DOT and "town" or "away"
	else
		fx, fy, side = tx, ty, "guess"
		if tx == 0 and ty == 0 then fx, fy = 1, 0 end
	end
	local front = S.front or { sx + fx * sq.FRONT, sy + fy * sq.FRONT }
	local ox, oy = (front[1] or front.x) + fx * sq.GAP, (front[2] or front.y) + fy * sq.GAP
	-- (2026-10-13 final test: South Molton's station 724 m out faced away from the town, the quarter lay beyond it with no
	-- link: nothing built. A forecourt facing away: the quarter goes on the station's back, the town side, beyond its
	-- bounding box (the tracks there: the grid keeps TRACK m from them), linked to the town as usual)
	local flipped = false
	if side == "away" and sq.FLIP_AWAY then
		fx, fy = -fx, -fy
		local reach = sq.FRONT
		local box = S.box
		if box then
			reach = 0
			for _, c in ipairs({ { box[1], box[2] }, { box[3], box[2] }, { box[1], box[4] }, { box[3], box[4] } }) do
				local a = (c[1] - sx) * fx + (c[2] - sy) * fy
				if a > reach then reach = a end
			end
		end
		ox, oy = sx + fx * (reach + sq.TRACK + sq.GAP), sy + fy * (reach + sq.TRACK + sq.GAP)
		front = { sx + fx * reach, sy + fy * reach }
		flipped = true
	end
	local ux, uy = -fy, fx
	local seed = style.seed or 1
	local n = sq.N[1] + floor(rng.unit(seed, "msqN", floor(sx), floor(sy)) * (sq.N[2] - sq.N[1] + 1))
	local len = L.clampSpec(sq.LEN, style.block and style.block.len or 80)
	local dep = L.clampSpec(sq.DEP, style.block and style.block.depth or 60)
	local function J(k, j)
		local a = (j - n / 2) * len
		return ox + fx * k * dep + ux * a, oy + fy * k * dep + uy * a
	end
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	extent = extent or 1500
	local tidx = RM.segIndex(S.tracks)
	local ridx = RM.segIndex(segsOf(style))
	local box = S.box
	local function okSeg(ax, ay, bx, by)
		local mx, my = (ax + bx) / 2, (ay + by) / 2
		for _, p in ipairs({ { ax, ay }, { mx, my }, { bx, by } }) do
			if L.offEdge(style, p[1], p[2]) or G.dist(cx, cy, p[1], p[2]) > extent then return false end
			if box and p[1] > box[1] - 8 and p[1] < box[3] + 8 and p[2] > box[2] - 8 and p[2] < box[4] + 8 then return false end
		end
		local pts = { { ax, ay }, { bx, by } }
		if T.wetAlong(sampler, pts, setback) then return false end
		if T.grade(sampler, ax, ay, bx, by) > sq.GRADE * maxSlope then return false end
		if RM.segNear(tidx, mx, my, sq.TRACK) or RM.segNear(tidx, ax, ay, 12) or RM.segNear(tidx, bx, by, 12) then return false end
		if RM.segNear(ridx, mx, my, sq.ROAD) or RM.segCross(ridx, ax, ay, bx, by) or RM.segCross(tidx, ax, ay, bx, by) then
			return false
		end
		if crossesGraph(g, ax, ay, bx, by) then return false end
		return true
	end
	local segs = {}
	for k = 0, n do
		for j = 0, n - 1 do
			local ax, ay = J(k, j)
			local bx, by = J(k, j + 1)
			segs[#segs + 1] = { k, j, k, j + 1, ok = okSeg(ax, ay, bx, by), dirU = true }
		end
	end
	for j = 0, n do
		for k = 0, n - 1 do
			local ax, ay = J(k, j)
			local bx, by = J(k + 1, j)
			segs[#segs + 1] = { k, j, k + 1, j, ok = okSeg(ax, ay, bx, by), dirU = false }
		end
	end
	local nOk = 0
	for _, s in ipairs(segs) do if s.ok then nOk = nOk + 1 end end
	if nOk < 4 then return nil, "noRoom", { side = flipped and "back" or side, d = d } end
	return { st = S, d = d, side = flipped and "back" or side, f = { fx, fy }, u = { ux, uy }, O = { ox, oy }, n = n,
		len = len, dep = dep, segs = segs, J = J, nOk = nOk, sx = sx, sy = sy, front = front, flipped = flipped }
end

local function sqKey(k, j) return "msq:" .. k .. ":" .. j end

--- Lays a straight grid into master plan mp (the station quarter, M3; the bridgehead quarter, M4): rows k = 0..nk (along
--- j), columns j = 0..nj (along k), each line as runs of good block sides (segOk(k1, j1, k2, j2)), every junction keyed
--- key(k, j) (the crossing lines share them). o = { nk, nj, J = fn(k, j) -> x, y, segOk, key, prefix, id (motif),
--- rowCls = fn(k) -> class (rows; columns small), drop = fn(x, y) (the plan's pieces dropped, by the first run's
--- overlay) }. Returns the planned length (m) and the number of runs.
function M.layGrid(mp, o)
	local nk, nj, J, segOk, key = o.nk, o.nj, o.J, o.segOk, o.key
	local runs = {}
	for k = 0, nk do
		local cls = o.rowCls and o.rowCls(k) or "small"
		local cur = { pts = {}, keys = {} }
		local r = 0
		for j = 0, nj do
			local x, y = J(k, j)
			if #cur.pts == 0 then cur.pts[1] = { x, y }; cur.keys[1] = key(k, j) end
			if j < nj and segOk(k, j, k, j + 1) then
				local bx, by = J(k, j + 1)
				cur.pts[#cur.pts + 1] = { bx, by }
				cur.keys[#cur.keys + 1] = key(k, j + 1)
			else
				r = r + 1
				if #cur.pts >= 2 then runs[#runs + 1] = { pts = cur.pts, keys = cur.keys, key = "U" .. k .. "_" .. r, cls = cls } end
				cur = { pts = {}, keys = {} }
			end
		end
	end
	for j = 0, nj do
		local cur = { pts = {}, keys = {} }
		local r = 0
		for k = 0, nk do
			local x, y = J(k, j)
			if #cur.pts == 0 then cur.pts[1] = { x, y }; cur.keys[1] = key(k, j) end
			if k < nk and segOk(k, j, k + 1, j) then
				local bx, by = J(k + 1, j)
				cur.pts[#cur.pts + 1] = { bx, by }
				cur.keys[#cur.keys + 1] = key(k + 1, j)
			else
				r = r + 1
				if #cur.pts >= 2 then runs[#runs + 1] = { pts = cur.pts, keys = cur.keys, key = "V" .. j .. "_" .. r, cls = "small" } end
				cur = { pts = {}, keys = {} }
			end
		end
	end
	local planned = 0
	local first = true
	for _, rn in ipairs(runs) do
		for i, p in ipairs(rn.pts) do
			if mp.junctions[rn.keys[i]] == nil then mp.junctions[rn.keys[i]] = { p[1], p[2] } end
		end
		local ix = L.index(rn.pts)
		local stops = {}
		for i = 2, #rn.pts - 1 do stops[#stops + 1] = { s = ix.cum[i], key = rn.keys[i] } end
		L.overlay(mp, rn.pts, { prefix = o.prefix .. rn.key, motif = o.id, class = rn.cls, curved = false, costK = L.COST_LANE,
			lead = true, startKey = rn.keys[1], endKey = rn.keys[#rn.keys], stops = stops, part = "grid",
			drop = first and o.drop or nil })
		first = false
		planned = planned + ix.len
	end
	return planned, #runs
end

local function stationPlan(mp, style, m, env)
	m.geo = nil
	mp.stationKey = style.stationKey
	if not M.ON then return end
	mp.stationGeo, mp.stationWhy, mp.stationInfo = nil, nil, nil
	local geo, why, info = M.stationGeo(style, env.g, env.terrain, env.extent)
	if geo == nil then
		m.planWhy, m.lastInfo = why, info
		mp.stationWhy, mp.stationInfo = why, info
		return
	end
	local id = m.id
	local n, J = geo.n, geo.J
	local fx, fy, ux, uy = geo.f[1], geo.f[2], geo.u[1], geo.u[2]
	local ox, oy = geo.O[1], geo.O[2]
	-- the quarter's rectangle (and the forecourt between it and the station): no plan streets inside
	local half = geo.n / 2 * geo.len + 15
	local depth = geo.n * geo.dep + 15
	local function inRect(x, y)
		local a = (x - ox) * fx + (y - oy) * fy
		local b = (x - ox) * ux + (y - oy) * uy
		return a >= -(M.SQ.GAP + M.SQ.FRONT + 10) and a <= depth and abs(b) <= half
	end
	local okAt = {}
	for _, s in ipairs(geo.segs) do okAt[s[1] .. ":" .. s[2] .. ":" .. s[3] .. ":" .. s[4]] = s.ok end
	local function segOk(k1, j1, k2, j2) return okAt[k1 .. ":" .. j1 .. ":" .. k2 .. ":" .. j2] end
	local planned, nRuns = M.layGrid(mp, { nk = n, nj = n, J = J, segOk = segOk, key = sqKey, prefix = "msq", id = id,
		rowCls = function(k) return k == 0 and "medium" or "small" end, drop = inRect })
	local runs = { n = nRuns }
	-- the Bahnhofstrasse: a straight street from the town to the grid's junction nearest the centre (not along the
	-- station square), anchored on the town's dead ends; none when the forecourt faces away (the tracks lie between)
	local cx, cy = style.centre[1], style.centre[2]
	local link, linkWhy = nil, geo.side == "away" and "away" or nil
	if linkWhy == nil then
		local bestK, bd = nil, math.huge
		for k = 1, n do
			for j = 0, n do
				local key = sqKey(k, j)
				local jn = mp.junctions[key]
				if jn then
					local d = G.dist(cx, cy, jn[1], jn[2])
					if d < bd then bestK, bd = key, d end
				end
			end
		end
		if bestK == nil then linkWhy = "noJunction"
		else
			local jn = mp.junctions[bestK]
			local line = { { cx, cy }, { jn[1], jn[2] } }
			-- (beyond the houses: no tracks / country road across it)
			local ok = true
			local tidx = RM.segIndex(geo.st.tracks)
			local ridx = RM.segIndex(segsOf(style))
			local r = style.radius or 0
			local ex, ey = unit(jn[1] - cx, jn[2] - cy)
			local x0, y0 = cx + ex * r, cy + ey * r
			if bd > r and (RM.segCross(tidx, x0, y0, jn[1], jn[2]) or RM.segCross(ridx, x0, y0, jn[1], jn[2])) then ok = false end
			if ok and T.wetAlong(env.terrain, { { x0, y0 }, { jn[1], jn[2] } }, style.waterSetback or 25) then ok = false end
			if ok then
				local lix = L.index(G.resample(line, 30))
				local anchors = L.anchors(env.g, style, lix, 0, { 1 }, env.terrain)
				local res = L.layMain(mp, G.resample(line, 30), { prefix = "msqB", approach = L.approach(style), teeK = L.COST_TEE,
					dense = L.dense(style), band = L.band(style), motif = id, class = "medium", costK = L.COST_MAIN, lead = true,
					every = 90, part = "link", mid = 0, curved = false, endKey = bestK }, anchors)
				link = { key = bestK, ix = lix, anchors = res.anchors, links = res.links, len = lix.len }
			else
				linkWhy = "blocked"
			end
		end
	end
	-- every quarter piece takes its neighbours along (the grid's crossings: the game joins only dead ends)
	local count = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == id then
			if pc.motifLine and pc.motifLine:sub(1, 4) == "msqB" then
				if pc.b == (link and link.key) or pc.a == (link and link.key) then pair(pc) end
			else
				pair(pc)
				count = count + 1
			end
		end
	end
	geo.planned, geo.pieces, geo.link, geo.linkWhy, geo.runs = planned, count, link, linkWhy, runs.n
	m.geo = geo
	mp.stationGeo = geo
	m.planWhy = nil
end

local function stationMeasure(env, m)
	-- (a derived kind's plan hook gets a fresh record per plan: the geometry lives on the master plan)
	local mp = env.mp
	local geo = m.geo or (mp and mp.stationGeo)
	if geo == nil then
		local why = m.planWhy or (mp and mp.stationWhy)
		local info = m.lastInfo or (mp and mp.stationInfo)
		if why == nil then return nil end
		return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(why) .. (info and
			(",side=" .. tostring(info.side) .. string.format(",d=%.0f", info.d or 0)) or "") }
	end
	local built, planned = 0, 0
	for _, s in ipairs(geo.segs) do
		if s.ok then
			planned = planned + 1
			local ax, ay = geo.J(s[1], s[2])
			local bx, by = geo.J(s[3], s[4])
			if L.segBuilt(env.g, ax, ay, bx, by, 8) then built = built + 1 end
		end
	end
	local linkLen = 0
	if geo.link then linkLen = L.builtAlong(env.g, geo.link.ix, 8) end
	local houses = 0
	local cxq, cyq = geo.J(geo.n / 2, geo.n / 2)
	local rq = geo.n * max(geo.len, geo.dep) * 0.75
	for _, p in ipairs(env.pts or {}) do if G.dist(cxq, cyq, p[1], p[2]) <= rq then houses = houses + 1 end end
	local cx, cy = env.style and env.style.centre[1] or 0, env.style and env.style.centre[2] or 0
	return { edges = L.incEdges(env.inc, "msq"), total = built, houses = houses, built = built, planned = planned,
		linkLen = linkLen,
		text = string.format("station=%.0f@%.0f,side=%s,grid=%dx%d,sides=%d/%d,link=%.0f/%.0f%s,anchors=%d/%d", geo.d,
			math.deg(G.wrap(G.heading(cx, cy, geo.sx, geo.sy))) % 360, geo.side, geo.n, geo.n, built, planned, linkLen,
			geo.link and geo.link.len or 0, geo.linkWhy and ("(" .. geo.linkWhy .. ")") or "", geo.link and geo.link.anchors or 0,
			geo.link and geo.link.links or 0) }
end

local function stationEligible(ctx)
	if not M.ON then return 0 end
	local st = ctx.style
	if st.metro then return 0 end
	local s, d = M.stationFor(st)
	if s == nil then return 0 end
	return 1, string.format("station:d=%.0f,n=%d", d, #st.railStations)
end

---------------------------------------------------------------------------
-- workers' terraces

local function isFactory(file)
	local s = string.lower(tostring(file or ""))
	for _, p in ipairs(M.WT.NOT_FACTORY) do if s:find(p, 1, true) then return false end end
	return true
end
M.isFactory = isFactory

--- The light works a town's terraces grow at: the nearest light factory D m beyond the houses' extent with no heavy /
--- medium works within HEAVY m of it, or nil.
function M.terraceWorks(style, info)
	if info == nil then return nil end
	local r = style.radius or 0
	for _, it in ipairs(info.list or {}) do
		if it.kind == "light" and isFactory(it.file) and it.d >= r + M.WT.D[1] and it.d <= r + M.WT.D[2]
			and not L.offEdge(style, it[1], it[2]) then
			local clean = true
			for _, o in ipairs(info.list) do
				if o.kind ~= "light" and G.dist(o[1], o[2], it[1], it[2]) < M.WT.HEAVY then clean = false; break end
			end
			if clean then return it end
		end
	end
	return nil
end

function M.terraceEra(year)
	local y = tonumber(year) or 1900
	local e = M.WT.YEAR
	if y <= e[1] then return 1 end
	return G.clamp((e[2] - y) / (e[2] - e[1]), 0, 1)
end

--- The terraces' plan geometry (pure): { works, line (spine), ix, rows = { { s, side, x0, y0, x1, y1, len, key } },
--- sp, half } or nil, why.
function M.terraceGeo(style, g, sampler, info)
	if sampler == nil then return nil, "noTerrain" end
	local W = M.terraceWorks(style, info)
	if W == nil then return nil, "noWorks" end
	local wt = M.WT
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local dx, dy, dW = unit(W[1] - cx, W[2] - cy)
	local sEnd = dW - wt.GAP
	local r = style.radius or 0
	local b = blk(style)
	local sMin = r + 0.5 * b
	local sp = L.clampSpec(wt.SP, style.block and style.block.depth or 60)
	local halfMax = L.clampSpec(wt.HALF, style.block and style.block.len or 80)
	local nWant = wt.ROWS[1] + floor(rng.unit(seed, "mwtRows") * (wt.ROWS[2] - wt.ROWS[1] + 1))
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	local ridx = RM.segIndex(segsOf(style))
	-- the spine: straight from the centre toward the works, ending GAP short of it
	local line = G.resample({ { cx, cy }, { cx + dx * sEnd, cy + dy * sEnd } }, 20)
	local ix = L.index(line)
	if T.wetAlong(sampler, { { cx + dx * r, cy + dy * r }, { cx + dx * sEnd, cy + dy * sEnd } }, setback) then return nil, "water" end
	local rows = {}
	for i = 1, nWant do
		local s = sEnd - (i - 1) * sp
		if s < sMin then break end
		local x, y = cx + dx * s, cy + dy * s
		for _, sd in ipairs({ 1, -1 }) do
			local nx, ny = -dy * sd, dx * sd
			local len, z = 0, T.height(sampler, x, y)
			for d = 10, halfMax, 10 do
				local px, py = x + nx * d, y + ny * d
				if L.wetNear(sampler, px, py, setback) or L.offEdge(style, px, py) then break end
				if RM.segNear(ridx, px, py, wt.ROAD) then break end
				local near = false
				for _, it in ipairs(info.list or {}) do
					if G.dist(px, py, it[1], it[2]) < wt.CLEAR_WORKS then near = true; break end
				end
				if near then break end
				local pz = T.height(sampler, px, py)
				if abs(pz - z) / 10 > wt.GRADE * maxSlope then break end
				if crossesGraph(g, x, y, px, py) then break end
				len, z = d, pz
			end
			if len >= wt.MIN_HALF then
				rows[#rows + 1] = { s = s, side = sd, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len, len = len, i = i }
			end
		end
	end
	if #rows < 2 then return nil, "noRoom" end
	return { works = W, file = W.file, d = dW, line = line, ix = ix, rows = rows, sp = sp, half = halfMax, sEnd = sEnd,
		nWant = nWant, dx = dx, dy = dy }
end

local function terracePlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.terraceGeo(style, env.g, env.terrain, style.industry)
	if geo == nil then m.planWhy = why; return end
	local id = m.id
	local cx, cy = style.centre[1], style.centre[2]
	local stops, byI = {}, {}
	for _, rw in ipairs(geo.rows) do
		if byI[rw.i] == nil then
			byI[rw.i] = { s = rw.s, key = "mwt:R" .. rw.i }
			stops[#stops + 1] = byI[rw.i]
		end
		rw.key = byI[rw.i].key
	end
	local sFirst = math.huge
	for _, rw in ipairs(geo.rows) do if rw.s < sFirst then sFirst = rw.s end end
	local dx, dy = geo.dx, geo.dy
	local function drop(x, y)
		local a = (x - cx) * dx + (y - cy) * dy
		local b = abs(-(x - cx) * dy + (y - cy) * dx)
		return a >= sFirst - geo.sp and a <= geo.sEnd + 30 and b <= geo.half + 20
	end
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mwt", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = id, class = "small", costK = L.COST_MAIN, lead = true,
		every = 90, stops = stops, part = "spine", mid = 0, curved = false, drop = drop }, anchors)
	local made = 0
	for i, rw in ipairs(geo.rows) do
		local j = mp.junctions[rw.key]
		if j and crossesMotif(mp, id, "mwt", j[1], j[2], rw.x1, rw.y1) then j = nil end
		if j then
			L.overlay(mp, { { j[1], j[2] }, { rw.x1, rw.y1 } }, { prefix = "mwtR" .. i, motif = id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = rw.key, deadEnd = true, part = "row", branch = "start",
				drop = function(x, y, tee) return tee or drop(x, y) end })
			made = made + 1
		end
	end
	-- (the motif's streets sit next to the works on purpose: no away-from-industry cost / hold for them; a row waits for
	-- the spine to go on past its junction, ot_select branchOk)
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == id then
			pc.indFree = true
			if pc.motifPart == "row" then pc.motifWait = true end
		end
	end
	geo.made, geo.anchors, geo.links = made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function terraceMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local built, rowsN = 0, {}
	local houses = 0
	for _, rw in ipairs(geo.rows) do
		local mx, my = (rw.x0 + rw.x1) / 2, (rw.y0 + rw.y1) / 2
		if L.segBuilt(env.g, rw.x0, rw.y0, mx, my, 8) then
			built = built + 1
			rowsN[rw.i] = true
		end
		local rix = L.index({ { rw.x0, rw.y0 }, { rw.x1, rw.y1 } })
		for _, p in ipairs(env.pts or {}) do if L.nearest(rix, p[1], p[2], 30) then houses = houses + 1 end end
	end
	local spine = L.builtAlong(env.g, geo.ix, 8)
	return { edges = L.incEdges(env.inc, "mwt"), total = built, houses = houses, rows = built,
		text = string.format("works=%s@%.0f,rows=%d/%d,spine=%.0f/%.0f,sp=%.0f,half=%.0f,anchors=%d/%d",
			tostring(geo.file):match("([%w_]+)%.con") or tostring(geo.file), geo.d, built, #geo.rows, spine, geo.ix.len, geo.sp,
			geo.half, geo.anchors or 0, geo.links or 0) }
end

local function terraceEligible(ctx)
	if not M.ON then return 0, "off" end
	local st = ctx.style
	if st.metro then return 0, "metro" end
	local era = M.terraceEra(ctx.year)
	if era <= 0 then return 0, "era" end
	local info = (ctx.inputs and ctx.inputs.industry) or st.industry
	local W = M.terraceWorks(st, info)
	if W == nil then return 0, "noLightWorks" end
	local s = M.WT.SCORE * era * styleK(st) * ((ctx.tier or 2) >= 4 and 0.5 or 1)
	if s <= 0 then return 0, "style" end
	return s, string.format("light:file=%s,d=%.0f", tostring(W.file):match("([%w_]+)%.con") or tostring(W.file), W.d)
end

--- DevelopAt points beside the build's terrace rows (both sides in turn), at most n.
local function terraceDose(m, edges, off, n)
	local out = {}
	if m.geo == nil then return out end
	local k = 0
	for _, e in ipairs(edges or {}) do
		if type(e.key) == "string" and e.key:sub(1, 4) == "mwtR" and e.p0 and e.p1 and #out < n then
			local ux, uy = unit(e.p1[1] - e.p0[1], e.p1[2] - e.p0[2])
			k = k + 1
			local sg = (k % 2 == 0) and 1 or -1
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			out[#out + 1] = { G.round(mx - uy * off * sg, 1), G.round(my + ux * off * sg, 1) }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- cul-de-sac pods

function M.podEra(year)
	local y = tonumber(year) or 1900
	local e = M.CP.YEAR
	return G.clamp((y - e[1]) / (e[2] - e[1]), 0, 1)
end

--- A collector's trace from the centre at heading th (curving c rad per m), to sMax: raw points, why it stopped, the
--- length beyond r. Stops only count beyond sGate (water / the map edge anywhere).
local function podTrace(style, sampler, th, c, sMax, sGate, ridx)
	local cp = M.CP
	local cx, cy = style.centre[1], style.centre[2]
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	local x, y = cx, cy
	local raw = { { x, y } }
	local z = T.height(sampler, x, y)
	local why = "len"
	local s = 0
	local guard = G.LOOP_CAP
	while s + cp.STEP <= sMax and guard > 0 do
		guard = guard - 1
		local h = th + c * s
		local nx, ny = x + cos(h) * cp.STEP, y + sin(h) * cp.STEP
		s = s + cp.STEP
		if L.wetNear(sampler, nx, ny, setback) then why = "water"; break end
		if L.offEdge(style, nx, ny) then why = "edge"; break end
		local nz = T.height(sampler, nx, ny)
		if s > sGate then
			if RM.segNear(ridx, nx, ny, cp.ROAD) or RM.segCross(ridx, x, y, nx, ny) then why = "road"; break end
			if abs(nz - z) / cp.STEP > cp.GRADE * maxSlope then why = "steep"; break end
		end
		raw[#raw + 1] = { nx, ny }
		x, y, z = nx, ny, nz
	end
	return raw, why, s
end

--- The pods' plan geometry (pure): { line, ix, th, closes = { { s, side, x0, y0, x1, y1, len } }, r0 (closes and the
--- green zone from here: half a block beyond the houses), closeMax, stop, beyond, pick } or nil, why. pick (optional): the direction chosen earlier this session (m.podPick).
function M.podGeo(style, g, sampler, extent, pick)
	if sampler == nil then return nil, "noTerrain" end
	local cp = M.CP
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local b = blk(style)
	local r = max(style.radius or 0, b)
	local depth = style.block and style.block.depth or 60
	local want = cp.LEN[1] + rng.unit(seed, "mcpLen") * (cp.LEN[2] - cp.LEN[1])
	-- (not cut at the plan's extent: the line must stay put as the plan grows)
	local sMax = r + want
	local sGate = r + 0.5 * b
	local ridx = RM.segIndex(segsOf(style))
	local rot = rng.unit(seed, "mcpRot") * TAU / cp.DIRS
	local best = nil
	for k = 0, cp.DIRS - 1 do
		if pick == nil or pick == k then
			local th = rot + k * TAU / cp.DIRS
			local c = (rng.unit(seed, "mcpCurv", k) * 2 - 1) * cp.CURV
			local raw, why, s = podTrace(style, sampler, th, c, sMax, sGate, ridx)
			local beyond = max(0, s - r)
			if beyond >= cp.MIN_BEYOND or pick ~= nil then
				-- (the mod's locked streets along it: an earlier session's collector stays where it is)
				local ours = 0
				if g then
					local ix0 = L.index(raw)
					for _, e in ipairs(g.edges) do
						if e.locked then
							local a, bb = g.nodeById[e.n0], g.nodeById[e.n1]
							if a and bb and G.dist(cx, cy, a.x, a.y) > r and L.nearest(ix0, (a.x + bb.x) / 2, (a.y + bb.y) / 2, 8) then
								ours = ours + 1
							end
						end
					end
				end
				local mi = raw[max(1, floor(#raw * 0.75))]
				local pen = IND.pen(style.industry, mi[1], mi[2])
				local slope = T.pathMaxGrade(sampler, raw) / max(style.maxSlope or 0.1, 1e-6)
				local sc = beyond - 300 * pen - 150 * slope + 40 * rng.unit(seed, "mcpPick", k) + (ours >= cp.OURS and 10000 or 0)
				if best == nil or sc > best.score then
					best = { raw = raw, why = why, th = th, c = c, k = k, beyond = beyond, score = sc, ours = ours }
				end
			end
		end
	end
	if best == nil or best.beyond < cp.MIN_BEYOND then return nil, "noRoom" end
	-- (the trace is a circular arc already: no smoothing, whose result would move as the line grows longer)
	local line = best.raw
	local ix = L.index(line)
	local r0 = r + 0.5 * b
	local closeMax = L.clampSpec(cp.CLOSE_LEN, depth)
	local gap = cp.GAP[1] + rng.unit(seed, "mcpGap") * (cp.GAP[2] - cp.GAP[1])
	local nWant = cp.CLOSES[1] + floor(rng.unit(seed, "mcpN") * (cp.CLOSES[2] - cp.CLOSES[1] + 1))
	local phase = rng.unit(seed, "mcpPhase") * gap
	local side0 = rng.unit(seed, "mcpSide") < 0.5 and 1 or -1
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	local closes = {}
	-- (close positions on a fixed comb along the line: a later session with a larger town adds the next ones outward)
	local k0 = math.ceil((r0 + 20 - phase) / gap)
	local kk = k0
	local guard = G.LOOP_CAP
	while #closes < nWant and guard > 0 do
		guard = guard - 1
		local s = phase + kk * gap
		if s > ix.len - 40 then break end
		local x, y, ux, uy = L.at(ix, s)
		local sd = (kk % 2 == 0) and side0 or -side0
		local nx, ny = -uy * sd, ux * sd
		local len, z = 0, T.height(sampler, x, y)
		for d = 10, closeMax, 10 do
			local px, py = x + nx * d, y + ny * d
			if L.wetNear(sampler, px, py, setback) or L.offEdge(style, px, py) then break end
			if RM.segNear(ridx, px, py, cp.ROAD) then break end
			local pz = T.height(sampler, px, py)
			if abs(pz - z) / 10 > cp.CLOSE_GRADE * maxSlope then break end
			if crossesGraph(g, x, y, px, py) then break end
			len, z = d, pz
		end
		if len >= cp.CLOSE_MIN then
			closes[#closes + 1] = { s = s, side = sd, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len, len = len }
		end
		kk = kk + 1
	end
	return { line = line, ix = ix, th = best.th, k = best.k, closes = closes, r0 = r0, closeMax = closeMax, stop = best.why,
		beyond = best.beyond, ours = best.ours, gap = gap, want = nWant, grade = T.pathMaxGrade(sampler, line) }
end

local function podPlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.podGeo(style, env.g, env.terrain, env.extent, m.podPick)
	if geo == nil then m.planWhy = why; return end
	m.podPick = geo.k
	local id = m.id
	local cx, cy = style.centre[1], style.centre[2]
	local stops = {}
	for i, c in ipairs(geo.closes) do
		c.key = "mcp:C" .. i
		stops[#stops + 1] = { s = c.s, key = c.key }
	end
	local zone = geo.closeMax + M.CP.GREEN
	local function drop(x, y)
		if G.dist(cx, cy, x, y) < geo.r0 then return false end
		return L.nearest(geo.ix, x, y, zone) ~= nil
	end
	local cls = geo.grade <= 0.5 * (style.maxSlope or 0.1) and "medium" or "small"
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mcp", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = id, class = cls, costK = L.COST_MAIN, lead = true, every = 90,
		stops = stops, part = "collector", mid = 0, drop = drop }, anchors)
	local made = 0
	for i, c in ipairs(geo.closes) do
		local j = mp.junctions[c.key]
		if j and crossesMotif(mp, id, "mcp", j[1], j[2], c.x1, c.y1) then j = nil end
		if j then
			-- (a close stays a cul-de-sac: no plan street meets or crosses it)
			L.overlay(mp, { { j[1], j[2] }, { c.x1, c.y1 } }, { prefix = "mcpC" .. i, motif = id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = c.key, deadEnd = true, part = "close", branch = "start",
				drop = function(x, y, tee) return tee or drop(x, y) end })
			made = made + 1
		end
	end
	-- (a close waits for the collector to go on past its junction, ot_select branchOk)
	for _, pc in ipairs(mp.pieces) do if pc.motif == id and pc.motifPart == "close" then pc.motifWait = true end end
	-- the green behind the closes: reserves there (ot_select inGreen, also against the selector's connectors), once
	if not m.greensAdded then
		m.greensAdded = true
		local rg = M.CP.GREEN / 2 + 10
		style.greens = style.greens or {}
		for _, c in ipairs(geo.closes) do
			local ux, uy = unit(c.x1 - c.x0, c.y1 - c.y0)
			style.greens[#style.greens + 1] = { G.round(c.x1 + ux * (rg + 10), 1), G.round(c.y1 + uy * (rg + 10), 1), rg }
		end
	end
	geo.made, geo.anchors, geo.links, geo.class = made, res.anchors, res.links, cls
	m.geo = geo
	m.planWhy = nil
end

local function podMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	-- (beyond the houses: the line starts at the centre, its inner part lies in the town)
	local rS = env.style and env.style.radius or 0
	local beyond = 0
	for _, sp in ipairs(spans) do beyond = beyond + max(0, sp[2] - max(sp[1], rS)) end
	local closes = 0
	for _, c in ipairs(geo.closes) do
		local mx, my = (c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2
		if L.segBuilt(env.g, c.x0, c.y0, mx, my, 8) then closes = closes + 1 end
	end
	-- the green behind the closes: other streets (the game's) in the zone beyond the closes' ends
	local inGreen = 0
	local g = env.g
	local cx, cy = env.style.centre[1], env.style.centre[2]
	for _, e in ipairs(g and g.edges or {}) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b and not e.locked then
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			local d = L.nearest(geo.ix, mx, my, geo.closeMax + M.CP.GREEN)
			if d and d > geo.closeMax + 10 and G.dist(cx, cy, mx, my) > geo.r0 then inGreen = inGreen + 1 end
		end
	end
	local houses = L.housesAlong(env.pts, geo.ix, spans, geo.closeMax + 20)
	return { edges = L.incEdges(env.inc, "mcp"), total = n, houses = houses, len = beyond, closes = closes, inGreen = inGreen,
		text = string.format("collector=%.0f/%.0f,closes=%d/%d,heads=plain,dir=%.0f,class=%s,inGreen=%d,stop=%s,anchors=%d/%d",
			beyond, max(0, geo.ix.len - rS), closes, #geo.closes, math.deg(G.wrap(geo.th)) % 360, geo.class or "-", inGreen,
			tostring(geo.stop),
			geo.anchors or 0, geo.links or 0) }
end

local function podEligible(ctx)
	if not M.ON then return 0, "off" end
	local st = ctx.style
	if st.metro then return 0, "metro" end
	local w = M.CP.STYLE[st.id] or 0
	if w <= 0 then return 0, "style" end
	local era = M.podEra(ctx.year)
	if era <= 0 then return 0, "era" end
	local t = ctx.terrain
	local ms = t and t.meanSlope or 0
	local flat = G.clamp((0.15 - ms) / 0.07, 0, 1)
	local s = M.CP.SCORE * w * era * flat
	if s <= 0 then return 0, string.format("rough:slope=%.3f", ms) end
	return s, string.format("suburb:era=%.2f,slope=%.3f", era, ms)
end

---------------------------------------------------------------------------

--- Registers the M3 kinds (append order = their save indices after the M2 kinds: 10-13).
function M.registerAll(MO)
	MO.register({ id = "ring_road", group = "ring", lock = true, eligible = ringEligible, style = ringStyle, plan = ringPlan,
		measure = ringMeasure })
	-- (derived: present whenever a station stands near the town, also on old / framed towns; not saved, no diversity)
	-- (extra, M4: the player's station takes no motif slot from the drawn kinds)
	MO.register({ id = "station_quarter", derived = true, extra = true, lock = true, eligible = stationEligible, plan = stationPlan,
		measure = stationMeasure })
	MO.register({ id = "workers_terraces", group = "works", eligible = terraceEligible, plan = terracePlan,
		measure = terraceMeasure, dose = terraceDose })
	MO.register({ id = "culdesac_pods", group = "pods", lock = true, eligible = podEligible, plan = podPlan,
		measure = podMeasure })
end

return M
