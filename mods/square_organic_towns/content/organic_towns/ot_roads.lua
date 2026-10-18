-- Organic Towns: the country roads around a town (pure). Phase M2 of the motifs plan (plans/square_organic_towns/
-- MOTIFS_BRIEF.md, 2026-10-13): the ribbon village follows a country road out of town, the village green sits at a road
-- fork, the crossroads hamlet at a junction of country roads 0.5-1.5 km out.
--
-- A country road = a street edge whose template is not a town street (`town_*`): the roads the game lays between towns
-- and to industries. The town's street snapshot (ot_driver.measure: every edge within the houses' extent + 300 m) holds
-- their first stretch; R.trace follows each one outward from where it leaves the town, edge by edge, fetching the edges
-- at the nodes beyond the snapshot (o.fetch: the driver's E.nodeStreetEdges + E.edge, capped by MAX_FETCH), always on
-- the edge that turns least (a road, not a side road), until REACH m from the centre, a dead end or a turn back. Nodes
-- where 3+ country-road edges meet are junctions (the hamlet's crossroads); every road edge seen (the followed ones and
-- the side roads at their nodes) goes into `segs`, so new streets can keep clear of them (the town graph doesn't hold the
-- part beyond the snapshot).
--
-- Joining: country-road nodes are never joined (ot_driver.snapshotGraph marks every node that isn't a plain town
-- street's dead end `noJoin`; MOTIFS_BRIEF M2 notes / PLAN.md 6.3 "Motifs M2"): motif streets run beside a road, never
-- from it.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"

local R = {}

R.REACH = 1700             -- m from the centre: roads followed this far
R.MAX_FETCH = 300          -- engine edge reads per trace at most
R.MAX_TURN = math.rad(70)  -- a road continues on the edge turning least, at most this much
R.BACK = 30                -- m: a step coming this much nearer the centre ends the road (it turns back)
R.MIN_LEN = 60             -- m: shorter roads left out
R.HEAD_R = 150             -- m beyond the houses' extent: a road's heading (from the centre) is taken there

--- true for a town street template (`town_*`).
function R.isTown(template)
	return type(template) == "string" and template:find("town_", 1, true) ~= nil
end

--- true for a country road edge (a street edge with a template that isn't a town street's).
function R.isRoad(ed)
	if ed == nil then return false end
	-- (the template's own `country` flag when the engine read it, ot_engine.roadEdges; else by name)
	if ed.country ~= nil then return ed.country == true or (type(ed.template) == "string" and not R.isTown(ed.template)) end
	return type(ed.template) == "string" and ed.template ~= "" and ed.template ~= "nil" and not R.isTown(ed.template)
end

local function xy(p) return p[1] or p.x, p[2] or p.y end

--- An edge's polyline from node `from` (its Hermite midpoint added when tangents are known).
local function edgePts(ed, from)
	local x0, y0 = xy(ed.p0)
	local x1, y1 = xy(ed.p1)
	local pts = { { x0, y0 } }
	if ed.t0 and ed.t1 then
		local tx0, ty0 = xy(ed.t0)
		local tx1, ty1 = xy(ed.t1)
		pts[#pts + 1] = { (x0 + x1) / 2 + (tx0 - tx1) / 8, (y0 + y1) / 2 + (ty0 - ty1) / 8 }
	end
	pts[#pts + 1] = { x1, y1 }
	if from == ed.n1 then
		local rev = {}
		for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
		pts = rev
	end
	return pts
end

--- Follows the country roads leaving the town at (cx, cy) (extent radius r). edges = { { id, n0, n1, p0 = {x, y},
--- p1, t0?, t1?, template } } (the snapshot); o = { fetch = fn(node) -> edges at it (or nil), snapR (m: the snapshot's
--- radius; nodes beyond snapR - 60 are fetched once), reach (m), maxFetch }. Returns { roads = { { pts, len, heading
--- (from the centre to where it is HEAD_R beyond r), out (m: its far end from the centre), edges = n } } (longest first),
--- junctions = { { x, y, d, deg, node, heads = { rad } } } (nearest first), segs = { { x0, y0, x1, y1, id } }, fetched }.
function R.trace(edges, cx, cy, r, o)
	o = o or {}
	local reach = o.reach or R.REACH
	local snapR = o.snapR or math.huge
	local maxFetch = o.maxFetch or R.MAX_FETCH
	local byNode, pos, known = {}, {}, {}
	local fetched, fetchedNode = 0, {}
	local function add(ed)
		if ed == nil or ed.id == nil or known[ed.id] then return end
		known[ed.id] = ed
		for k = 0, 1 do
			local n = k == 0 and ed.n0 or ed.n1
			local l = byNode[n]
			if l == nil then l = {}; byNode[n] = l end
			l[#l + 1] = ed
			if pos[n] == nil then
				local x, y = xy(k == 0 and ed.p0 or ed.p1)
				pos[n] = { x, y }
			end
		end
	end
	for _, ed in ipairs(edges or {}) do add(ed) end
	local function dist(n)
		local p = pos[n]
		return p and G.dist(cx, cy, p[1], p[2]) or math.huge
	end
	-- (a node near or beyond the snapshot's rim may miss edges: read them once)
	local function complete(n)
		if o.fetch == nil or fetchedNode[n] or fetched >= maxFetch then return end
		if dist(n) < snapR - 60 then return end
		fetchedNode[n] = true
		local ok, list = pcall(o.fetch, n)
		fetched = fetched + 1
		if ok and type(list) == "table" then for _, ed in ipairs(list) do add(ed) end end
	end
	local out = { roads = {}, junctions = {}, segs = {}, fetched = 0 }
	local segSeen, jSeen, used = {}, {}, {}
	local function addSegs(ed)
		if segSeen[ed.id] then return end
		segSeen[ed.id] = true
		local pts = edgePts(ed, ed.n0)
		for i = 2, #pts do
			out.segs[#out.segs + 1] = { pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], id = ed.id }
		end
	end
	local function roadsAt(n)
		local l = {}
		for _, ed in ipairs(byNode[n] or {}) do if R.isRoad(ed) then l[#l + 1] = ed end end
		return l
	end
	-- starts: road edges crossing the circle r, or meeting a town street (where the road enters the town), outer end
	-- farther from the centre
	local starts = {}
	local startList = {}
	for _, ed in ipairs(edges or {}) do startList[#startList + 1] = ed end
	table.sort(startList, function(a, b) return a.id < b.id end)
	for _, ed in ipairs(startList) do
		if R.isRoad(ed) then
			local d0, d1 = dist(ed.n0), dist(ed.n1)
			local inner = d0 <= d1 and ed.n0 or ed.n1
			local di, dd = math.min(d0, d1), math.max(d0, d1)
			local cross = di <= r and dd > r
			local entry = false
			if not cross and di <= r + 250 then
				for _, x in ipairs(byNode[inner] or {}) do
					if x ~= ed and R.isTown(x.template) then entry = true; break end
				end
			end
			if (cross or entry) and dd > di + 1 then starts[#starts + 1] = { ed = ed, from = inner } end
		end
	end
	for _, st in ipairs(starts) do
		if not used[st.ed.id] then
			local pts = {}
			local ed, from = st.ed, st.from
			local nEdges = 0
			local heading = nil
			while ed and not used[ed.id] do
				used[ed.id] = true
				addSegs(ed)
				nEdges = nEdges + 1
				local ep = edgePts(ed, from)
				for i = (#pts == 0 and 1 or 2), #ep do pts[#pts + 1] = ep[i] end
				local n = ed.n0 == from and ed.n1 or ed.n0
				if heading == nil then
					-- (the heading where it is HEAD_R beyond the houses: the road's own direction out of town)
					for _, p in ipairs(pts) do
						if G.dist(cx, cy, p[1], p[2]) > r + R.HEAD_R then heading = G.atan2(p[2] - cy, p[1] - cx); break end
					end
				end
				local dn = dist(n)
				if dn > reach then break end
				complete(n)
				local at = roadsAt(n)
				-- every road edge at this node: clearance data (side roads included)
				for _, x in ipairs(at) do addSegs(x) end
				if #at >= 3 and not jSeen[n] then
					jSeen[n] = true
					local heads = {}
					for _, x in ipairs(at) do
						local xp = edgePts(x, n)
						heads[#heads + 1] = G.heading(xp[1][1], xp[1][2], xp[2][1], xp[2][2])
					end
					table.sort(heads)
					out.junctions[#out.junctions + 1] = { x = pos[n][1], y = pos[n][2], d = dn, deg = #at, node = n,
						heads = heads }
				end
				-- continue on the road edge turning least (not back toward the town)
				local a = pts[#pts - 1] or pts[1]
				local b = pts[#pts]
				local hIn = G.heading(a[1], a[2], b[1], b[2])
				local best, bt = nil, math.huge
				for _, x in ipairs(at) do
					if x ~= ed and not used[x.id] then
						local xp = edgePts(x, n)
						local h = G.heading(xp[1][1], xp[1][2], xp[2][1], xp[2][2])
						local t = G.angleDiff(h, hIn)
						local far = x.n0 == n and x.n1 or x.n0
						if t <= R.MAX_TURN and dist(far) >= dn - R.BACK and (t < bt - 1e-9 or (math.abs(t - bt) <= 1e-9
							and best and x.id < best.id)) then
							best, bt = x, t
						end
					end
				end
				ed, from = best, n
			end
			local len = #pts >= 2 and G.polyLen(pts) or 0
			if len >= R.MIN_LEN then
				local e = pts[#pts]
				out.roads[#out.roads + 1] = { pts = pts, len = len, edges = nEdges,
					heading = heading or G.atan2(e[2] - cy, e[1] - cx), out = G.dist(cx, cy, e[1], e[2]) }
			end
		end
	end
	table.sort(out.roads, function(a, b)
		if math.abs(a.out - b.out) > 1e-6 then return a.out > b.out end
		return a.heading < b.heading
	end)
	table.sort(out.junctions, function(a, b)
		if math.abs(a.d - b.d) > 1e-6 then return a.d < b.d end
		return a.node < b.node
	end)
	out.fetched = fetched
	return out
end

--- The country roads of graph g (its edges with a template that isn't a town street's) as R.trace sees them: the
--- fallback when the driver gave none (offline tests; the snapshot's stretch only).
function R.fromGraph(g, cx, cy, r, o)
	local list = {}
	for _, e in ipairs(g and g.edges or {}) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b and type(e.template) == "string" then
			list[#list + 1] = { id = e.id, n0 = e.n0, n1 = e.n1, p0 = { a.x, a.y }, p1 = { b.x, b.y }, template = e.template }
		end
	end
	return R.trace(list, cx, cy, r, o)
end

---------------------------------------------------------------------------
-- Virtual roads (2026-10-13, final all-phases test, session 2026-10-13_0856_sqot-dev: every town logged `ROADS roads=0
-- segs=0 fetched=0` and the tour shots show no road leaving any town; that map was started with makeInitialStreets =
-- false ("Streets at industries: Off"), which seems to drop the generator's roads between towns too (the earlier maps,
-- default true, had dirt country roads): docs/findings/towns.md "`makeInitialStreets = false` also drops the roads between
-- towns"). The driver reads the road edges wide around the town first (ot_engine.roadEdges); only a town with none at all
-- gets these. Without a single country road near the town the road motifs (ribbon village, village green, tree-lined entries)
-- follow the roads the town would have: lines from the centre toward its nearest neighbour towns (the road to the next
-- village), else along the land's own direction (the contour / valley axis both ways), else two seeded opposite
-- headings. Each is traced over the terrain (the gentlest heading within V.TURN of the bearing, never onto or beside
-- water, at most V.REACH m). A virtual road is no street: nothing to keep clear of (no segs, no junctions); the ribbon
-- street runs on the line itself (ot_motif_road), the entry trees line the town's own streets along it (ot_entry).

R.V = {
	N = 3,                  -- virtual roads at most
	MIN_N = 2,              -- ... at least (filled with the land's / seeded directions)
	SEP = math.rad(50),     -- headings closer than this are one road
	STEP = 40,              -- m per trace step
	REACH = 1600,           -- m from the centre at most
	TURN = math.rad(12),    -- max turn per step
	DEV = math.rad(40),     -- max deviation from the bearing
	SETBACK = 30,           -- m: the trace keeps this far from water
	MIN_OUT = 420,          -- m: shorter traces (water, map edge) left out
	FAR = 6000,             -- m: neighbours this far count
}

local function wetAround(s, x, y, r)
	if T.isWater(s, x, y) then return true end
	for k = 0, 7 do
		local a = k * math.pi / 4
		if T.isWater(s, x + math.cos(a) * r, y + math.sin(a) * r) then return true end
	end
	return false
end

--- One virtual road from (cx, cy) toward heading `bearing` (rad) over sampler s (height / isWater, ot_terrain
--- interface; nil: a straight line). o = { reach, offEdge = fn(x, y) }. Returns pts or nil.
function R.traceVirtual(s, cx, cy, bearing, o)
	local v = R.V
	o = o or {}
	local reach = o.reach or v.REACH
	local pts = { { cx, cy } }
	local x, y, h = cx, cy, bearing
	local z = s and T.height(s, x, y) or 0
	for _ = 1, math.floor(reach / v.STEP) do
		local best, bs, bh, bz = nil, math.huge, nil, nil
		for k = -3, 3 do
			local hh = h + k * v.TURN / 3
			if G.angleDiff(hh, bearing) <= v.DEV then
				local nx, ny = x + math.cos(hh) * v.STEP, y + math.sin(hh) * v.STEP
				if not (s and wetAround(s, nx, ny, v.SETBACK)) and not (o.offEdge and o.offEdge(nx, ny))
					and G.dist(cx, cy, nx, ny) > G.dist(cx, cy, x, y) + 0.5 * v.STEP then
					local nz = s and T.height(s, nx, ny) or 0
					local sc = math.abs(nz - z) / v.STEP * 10 + G.angleDiff(hh, bearing) * 0.4
					if sc < bs - 1e-12 then best, bs, bh, bz = { nx, ny }, sc, hh, nz end
				end
			end
		end
		if best == nil then break end
		pts[#pts + 1] = best
		x, y, h, z = best[1], best[2], bh, bz
	end
	if G.dist(cx, cy, x, y) < v.MIN_OUT then return nil end
	return pts
end

--- Virtual roads for a town at (cx, cy) with no country road (see above). o = { sampler, neighbours = { { dir, dist } }
--- (nearest first), dirs = { rad } (the land's directions, ot_driver.lobeDirs), seed (number), offEdge }. Returns a
--- trace result like R.trace: { roads = { { pts, len, heading, out, edges = 0, virtual = true, why } }, junctions = {},
--- segs = {}, fetched = 0, virtual = true }.
function R.virtual(cx, cy, r, o)
	o = o or {}
	local v = R.V
	local heads = {}
	local function add(h, why)
		if #heads >= v.N then return end
		h = G.wrap(h)
		for _, x in ipairs(heads) do if G.angleDiff(x.h, h) < v.SEP then return end end
		heads[#heads + 1] = { h = h, why = why }
	end
	for _, nb in ipairs(o.neighbours or {}) do
		if (nb.dist or math.huge) <= v.FAR and nb.dir then add(nb.dir, "nbr") end
	end
	for _, d in ipairs(o.dirs or {}) do if #heads < v.MIN_N then add(d, "land") end end
	local seed = o.seed or 1
	local base = ((seed * 0.6180339887) % 1) * 2 * math.pi
	for k = 0, 3 do
		if #heads >= v.MIN_N then break end
		add(base + k * math.pi / 2 + (k >= 2 and math.pi / 4 or 0), "seed")
	end
	local out = { roads = {}, junctions = {}, segs = {}, fetched = 0, virtual = true }
	for _, hd in ipairs(heads) do
		local pts = R.traceVirtual(o.sampler, cx, cy, hd.h, { offEdge = o.offEdge })
		if pts == nil and o.sampler then
			-- (water or the map edge straight ahead: the bearing turned a little either way)
			for _, d in ipairs({ math.rad(35), -math.rad(35) }) do
				pts = R.traceVirtual(o.sampler, cx, cy, hd.h + d, { offEdge = o.offEdge })
				if pts then break end
			end
		end
		if pts then
			local e = pts[#pts]
			local heading = hd.h
			for _, p in ipairs(pts) do
				if G.dist(cx, cy, p[1], p[2]) > r + R.HEAD_R then heading = G.atan2(p[2] - cy, p[1] - cx); break end
			end
			out.roads[#out.roads + 1] = { pts = pts, len = G.polyLen(pts), edges = 0, heading = heading,
				out = G.dist(cx, cy, e[1], e[2]), virtual = true, why = hd.why }
		end
	end
	table.sort(out.roads, function(a, b)
		if math.abs(a.out - b.out) > 1e-6 then return a.out > b.out end
		return a.heading < b.heading
	end)
	return out
end

--- Road forks: pairs of roads leaving the town 35-120 deg apart: { { a, b (road indices), angle, bisector } }, widest
--- spread last (the narrowest fork first: a Y).
R.FORK = { math.rad(35), math.rad(120) }
function R.forks(roads)
	local out = {}
	local list = roads and roads.roads or {}
	for i = 1, #list do
		for j = i + 1, #list do
			local ha, hb = list[i].heading, list[j].heading
			local d = G.angleDiff(ha, hb)
			if d >= R.FORK[1] and d <= R.FORK[2] then
				local vx, vy = math.cos(ha) + math.cos(hb), math.sin(ha) + math.sin(hb)
				out[#out + 1] = { a = i, b = j, angle = d, bisector = G.atan2(vy, vx) }
			end
		end
	end
	table.sort(out, function(p, q)
		if math.abs(p.angle - q.angle) > 1e-9 then return p.angle < q.angle end
		if p.a ~= q.a then return p.a < q.a end
		return p.b < q.b
	end)
	return out
end

--- `roads=` text: "n:len/len/..;j=n" or "-".
function R.text(roads)
	if roads == nil or #(roads.roads or {}) == 0 then return "-" end
	local parts = {}
	for i, rd in ipairs(roads.roads) do
		if i > 4 then break end
		parts[#parts + 1] = string.format("%.0f@%d", rd.out, math.floor(math.deg(G.wrap(rd.heading)) % 360 + 0.5))
	end
	return string.format("%s%d:%s;j=%d;f=%d", roads.virtual and "virtual:" or "", #roads.roads, table.concat(parts, "/"),
		#(roads.junctions or {}), roads.fetched or 0)
end

return R
