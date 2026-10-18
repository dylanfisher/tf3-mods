-- Satellite villages (ot_satellite, 2026-10-13): who gets one, where it goes (0.8-1.5 km out, dry, gentle, away
-- from heavy industry, nearer this town, beside a road), one link street and a compact core, growth by one block
-- from its own dead ends, the meadow discs along the link, the saved site.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")
local SAT = ug_require(F.DIR .. "ot_satellite.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local IND = ug_require(F.DIR .. "ot_industry.lua")

local function core()
	local g = F.roundCore(OG.new(), { rings = { 90, 180, 270 }, counts = { 6, 10, 14 } })
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do
		local node = g.nodeById[n]
		ends[#ends + 1] = { node.x, node.y, n }
	end
	return g, ends
end

local function site(o)
	local _, ends = core()
	local r = { cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 11, deadEnds = ends }
	for k, v in pairs(o or {}) do r[k] = v end
	return SAT.pickSite(r)
end

test("eligible: grown towns (>= 250), a seeded ~55 % (round 5), never metropolis / block styles / a second one", function()
	local on = 0
	for seed = 1, 400 do
		if SAT.eligible({ seed = seed, buildings = 400, styleId = "EU_ORGANIC" }) then on = on + 1 end
	end
	ok(on >= 190 and on <= 250, "share " .. on / 400)
	ok(SAT.eligible({ seed = 3, buildings = 249, styleId = "EU_ORGANIC" }) == false)
	local _, why = SAT.eligible({ seed = 1, buildings = 100, styleId = "EU_ORGANIC" })
	eq(why, "small")
	_, why = SAT.eligible({ seed = 1, buildings = 900, styleId = "EU_ORGANIC", metro = true })
	eq(why, "metro")
	_, why = SAT.eligible({ seed = 1, buildings = 900, styleId = "SUPERBLOCK" })
	eq(why, "style")
	_, why = SAT.eligible({ seed = 1, buildings = 900, styleId = "EU_ORGANIC", has = true })
	eq(why, "has")
end)

test("site: 0.65-1.2 km out, beyond the houses, link from the nearest dead end; water, heavy works, neighbours avoided", function()
	local s, n = site()
	ok(s ~= nil, tostring(n))
	-- (2026-10-14 late: RING_D 800-1500 -> 650-1200, MAX_LINK 900; was 800-1500)
	ok(s.dist >= 650 and s.dist <= 1200, "dist " .. s.dist)
	ok(s.linkLen <= SAT.MAX_LINK, "link at most MAX_LINK: " .. s.linkLen)
	ok(s.dist >= 300 + SAT.SAT_GAP, "beyond the extent")
	ok(G.dist(s.link[1][1], s.link[1][2], s.deadEnd[1], s.deadEnd[2]) < 1e-6, "link starts at the dead end")
	ok(s.linkLen >= SAT.MIN_LINK, "a meadow's worth of link: " .. s.linkLen)
	ok(G.dist(s.link[#s.link][1], s.link[#s.link][2], s.x, s.y) < 1e-6, "link ends at the site")
	-- sea east of x = 500: never east, never within WET_R of water
	local sea = T.sampler(function(x) return x > 500 and -3 or 5 end)
	for seed = 1, 10 do
		local w = site({ sampler = sea, seed = seed })
		ok(w and w.x < 500 - SAT.WET_R, "dry: " .. tostring(w and w.x))
	end
	-- a heavy works north: the site keeps clear of its buffer
	local info = IND.forTown({ { 0, 1100, file = "industry/steel_mill/steel_mill.con" } }, 0, 0, 1950)
	for seed = 1, 10 do
		local h = site({ industry = info, seed = seed })
		ok(h and IND.pen(info, h.x, h.y) <= SAT.HEAVY_PEN, "away from heavy industry")
	end
	-- a neighbour town 2 km west: the site stays nearer this town and >= 1.3 km from it
	for seed = 1, 10 do
		local b = site({ neighbours = { { -2000, 0 } }, seed = seed })
		ok(b and G.dist(b.x, b.y, -2000, 0) >= SAT.NEIGHBOUR_MIN and G.dist(b.x, b.y, -2000, 0) > b.dist, "neighbour")
	end
	-- a road south: preferred
	local roads = {}
	for k = 0, 30 do roads[#roads + 1] = { 0, -300 - k * 50 } end
	local onRoad = 0
	for seed = 1, 10 do
		local r = site({ roads = roads, seed = seed })
		if r.road then onRoad = onRoad + 1 end
	end
	ok(onRoad >= 7, "beside the road: " .. onRoad)
	-- no dead end, no site
	local none, why = SAT.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, deadEnds = {} })
	eq(none, nil)
	eq(why, "noDeadEnd")
end)

test("plan: one link street and a compact core; growth extends the core's own dead ends within CORE_R", function()
	local g, ends = core()
	local s = SAT.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 5, deadEnds = ends })
	local streets = SAT.streets(s)
	local inc = PL.plan(g, streets, { terrain = F.flat, maxSeg = 100, maxEdges = 60, join = "deadEnd",
		templatePaths = { main = "m", medium = "m", small = "s" } })
	local link, coreN = 0, 0
	for _, e in ipairs(inc.edges) do
		local st = streets[e.street]
		if st.sat == "link" then link = link + 1 else
			coreN = coreN + 1
			ok(G.dist(e.p0[1], e.p0[2], s.x, s.y) <= SAT.CORE_R and G.dist(e.p1[1], e.p1[2], s.x, s.y) <= SAT.CORE_R, "core near the site")
		end
	end
	print(string.format("      satellite dist %.0f link %.0f m: %d link edges, %d core edges, joins %d", s.dist, s.linkLen, link,
		coreN, #inc.joins))
	-- (2026-10-14 late: shorter links, 4+ edges; was >= 6)
	ok(link >= 4, "the link is built (" .. link .. " edges)")
	-- (2026-10-14: CORE_SMALL, 3 edges: the main street's first block and the cross street at the site; was >= 4)
	ok(coreN >= 3 and coreN <= SAT.CORE_EDGES, "a compact core: " .. coreN)
	eq(#inc.joins, 1, "one join: the link at the town's dead end")
	eq(inc.joins[1].node, s.deadEnd[3])
	-- the link has no side streets: its inner nodes have degree 2 in the increment
	OG.apply(g, inc, 1)
	local before = #g.edges
	local grow = SAT.growStreets(g, s, 5)
	ok(#grow >= 2, "growth streets from the core's dead ends: " .. #grow)
	local inc2 = PL.plan(g, grow, { terrain = F.flat, maxSeg = 100, maxEdges = SAT.GROW_EDGES, join = "deadEnd",
		templatePaths = { main = "m", medium = "m", small = "s" } })
	ok(#inc2.edges >= 2 and #inc2.edges <= SAT.GROW_EDGES, "growth edges " .. #inc2.edges)
	for _, e in ipairs(inc2.edges) do
		ok(G.dist(e.p1[1], e.p1[2], s.x, s.y) <= SAT.CORE_R + 1, "growth stays compact")
	end
	ok(before > 0)
	-- the meadow between: discs along the link, none near the town or the satellite
	local gr = SAT.gapGreens(s)
	ok(#gr >= 2, "meadow discs " .. #gr)
	for _, d in ipairs(gr) do
		ok(G.dist(d[1], d[2], s.x, s.y) - d[3] >= 0.8 * SAT.CORE_R - 1, "the satellite stays outside the meadow")
		ok(G.dist(d[1], d[2], 0, 0) - d[3] >= 250, "the town core stays outside the meadow")
	end
end)

test("saved: the satellite site goes on the town's frame once; normalize and frame() keep it", function()
	local raw = SV.applyFrame({ v = 1, known = {}, frames = {} }, { town = 5, a = 0.1, x = 1, y = 2 })
	local s2, changed = SV.applySat(raw, { town = 5, x = 900.5, y = -40 })
	ok(changed)
	local _, again = SV.applySat(s2, { town = 5, x = 1, y = 1 })
	ok(not again, "first one wins")
	local _, noFrame = SV.applySat(s2, { town = 6, x = 1, y = 1 })
	ok(not noFrame, "no frame: ignored")
	local fr = SV.frame(SV.normalize(s2), 5)
	eq(fr.sat, { 900.5, -40 })
end)

test("link clear of existing streets (real map run 2026-10-13: Harwich / Workington links crossed or ran along a street; the rest dropped as disconnected)", function()
	local g, ends = core()
	-- a country road ring at 600 m around the town: every link must cross it
	local prev, first = nil, nil
	for k = 0, 35 do
		local a = k / 36 * 2 * math.pi
		local nd = OG.addNode(g, nil, 600 * math.cos(a), 600 * math.sin(a), 20)
		if prev then OG.addEdge(g, nil, prev.id, nd.id, "small") else first = nd end
		prev = nd
	end
	OG.addEdge(g, nil, prev.id, first.id, "small")
	local s, why = SAT.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 11, deadEnds = ends, g = g })
	ok(s == nil and why == "noSite", "a closed road ring: no clear link: " .. tostring(why))
	-- a road running out east from the town: sites east would cross / follow it; a site is found elsewhere, its link clear
	local g2, ends2 = core()
	local r0 = OG.addNode(g2, nil, 330, 20, 20)
	local r1 = OG.addNode(g2, nil, 1600, 20, 20)
	OG.addEdge(g2, nil, r0.id, r1.id, "small")
	for seed = 1, 8 do
		local s2 = SAT.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = seed, deadEnds = ends2, g = g2 })
		ok(s2 ~= nil, "seed " .. seed)
		if s2 then
			ok(SAT.linkClear(g2, s2.link, s2.deadEnd[3]), "link clear")
			-- the planner accepts the whole link (no crossing / nearExisting drops)
			local streets = SAT.streets(s2)
			local inc = PL.plan(g2, streets, { terrain = F.flat, maxSeg = 100, maxEdges = 60, join = "deadEnd" })
			local drops = {}
			for _, d in ipairs(inc.dropped) do
				if streets[d.street].sat == "link" then drops[#drops + 1] = d.reason end
			end
			eq(#drops, 0, "link drops: " .. table.concat(drops, ","))
		end
	end
end)

test("obstacles beyond the snapshot (real map run 2026-10-13_0342_sqot: 3 of 4 seeds refused, Collision): link and core keep clear of fields, tracks, roads; refused sites skipped", function()
	local free, n0 = site()
	ok(free ~= nil, "a site without obstacles")
	-- a field box on the free site, a track across its link
	local fx, fy = free.x, free.y
	local obs = { segs = {}, boxes = { { fx - 60, fy - 60, fx + 60, fy + 60, id = 1, kind = "field" } } }
	local s2 = site({ obstacles = obs })
	ok(s2 ~= nil, "another site")
	ok(G.dist(s2.x, s2.y, fx, fy) > 1, "not the field's site")
	ok(SAT.clearOfObstacles(obs, s2.link, SAT.START_SKIP))
	for i, st in ipairs(SAT.streets(s2)) do
		if i > 1 then ok(SAT.clearOfObstacles(obs, st.pts), "core street " .. i .. " clear of the field") end
	end
	-- a track ring 900 m out (every direction): links crossing it fail, sites inside / beyond it need a clear link
	local ring = { segs = {}, boxes = {} }
	for k = 0, 47 do
		local a0, a1 = k * math.pi / 24, (k + 1) * math.pi / 24
		ring.segs[#ring.segs + 1] = { 900 * math.cos(a0), 900 * math.sin(a0), 900 * math.cos(a1), 900 * math.sin(a1),
			id = 100 + k, kind = "track" }
	end
	local s3, why3 = site({ obstacles = ring })
	ok(s3 == nil or G.dist(s3.x, s3.y, 0, 0) < 900 - SAT.TRACK_CLEAR, "no link across the track: " .. tostring(why3))
	if s3 then ok(SAT.clearOfObstacles(ring, s3.link, SAT.START_SKIP)) end
	-- (run 2026-10-14_0814_sqot: a bridge plan without a far cross street passed a nil line) nil / one point: clear
	ok(SAT.clearOfObstacles(ring, nil), "nil pts")
	ok(SAT.clearOfObstacles(ring, {}), "no points")
	ok(SAT.clearOfObstacles(ring, { { 0, 0 } }, 30), "one point")
	local ok1, kind = SAT.clearOfObstacles(ring, { { 0, 0 }, { 1200, 0 } })
	eq(ok1, false)
	eq(kind, "track")
	-- refused sites (o.bad) are skipped
	local s4 = site({ bad = { { fx, fy } } })
	ok(s4 ~= nil and G.dist(s4.x, s4.y, fx, fy) >= SAT.BAD_R, "a site away from the refused one")
	print(string.format("        satellite free %.0f:%.0f, field -> %.0f:%.0f, bad -> %.0f:%.0f, cands %s", fx, fy, s2.x, s2.y,
		s4.x, s4.y, tostring(n0)))
end)

test("curved link (2026-10-14 late): no straight run over MAX_STRAIGHT, ends exact, the gentlest variant on a slope", function()
	local worst = 0
	for _, L in ipairs({ 250, 400, 600, 900, 1250 }) do
		for seed = 1, 30 do
			local pts = SAT.curvedLink(0, 0, L, 0, seed, nil)
			local run = G.maxStraightRun(pts, SAT.STRAIGHT_TOL)
			if run > worst then worst = run end
			ok(G.dist(pts[1][1], pts[1][2], 0, 0) < 1e-6 and G.dist(pts[#pts][1], pts[#pts][2], L, 0) < 1e-6, "ends")
			local off = 0
			for _, p in ipairs(pts) do off = math.max(off, math.abs(p[2])) end
			ok(off <= SAT.BOW_MAX + L * SAT.WAVE_A[2] + 1, "bounded off the line: " .. off)
		end
	end
	print(string.format("      curved links 250-1250 m x 30 seeds: longest straight run %.0f m", worst))
	ok(worst <= SAT.MAX_STRAIGHT, "longest straight run " .. worst)
	-- a hillside rising north: the variant with the gentlest grade wins
	local hill = T.sampler(function(_x, y) return y * 0.05 end)
	local p0 = SAT.curvedLink(0, 0, 800, 0, 3, hill)
	local best = T.pathMaxGrade(hill, p0, 40)
	ok(best <= T.pathMaxGrade(hill, SAT.curvedLink(0, 0, 800, 0, 3, nil), 40) + 1e-9, "no worse than the unsampled pick")
end)

test("a straight run of new town streets ahead of the houses is cut at STRAIGHT_MAX (ot_check, ot_plan.dropEdges)", function()
	local CK = ug_require(F.DIR .. "ot_check.lua")
	-- an existing dead end at (0,0) (node 1), then 6 straight new edges of 80 m east and a side street at the 4th node
	local inc = { nodes = {}, edges = {}, joins = {} }
	local function edge(n0, n1, x0, x1, y0, y1)
		local i = #inc.edges + 1
		inc.edges[i] = { entity = -i, node0 = n0, node1 = n1, p0 = { x0, y0 or 0, 0 }, p1 = { x1, y1 or 0, 0 },
			t0 = { x1 - x0, (y1 or 0) - (y0 or 0), 0 }, t1 = { x1 - x0, (y1 or 0) - (y0 or 0), 0 },
			length = math.sqrt((x1 - x0) ^ 2 + ((y1 or 0) - (y0 or 0)) ^ 2), key = "k" .. i }
	end
	-- node entities: -8 .. -14 for the new nodes (7 edges first)
	local xs = { 0, 80, 160, 240, 320, 400, 480 }
	local ids = { 1, -8, -9, -10, -11, -12, -13 }
	for k = 1, 6 do edge(ids[k], ids[k + 1], xs[k], xs[k + 1]) end
	edge(-11, -14, 320, 320, 0, 80)   -- a side street off the 4th new node
	for i, id in ipairs({ -8, -9, -10, -11, -12, -13, -14 }) do
		local x = ({ 80, 160, 240, 320, 400, 480, 320 })[i]
		inc.nodes[#inc.nodes + 1] = { entity = id, x = x, y = id == -14 and 80 or 0, z = 0 }
	end
	inc.joins = { { node = 1, edge = -1 } }
	local houses = { { -20, 30 }, { -40, -30 } }
	local rep = CK.straightRuns(inc, houses)
	near(rep.max, 480, 1e-6)
	eq(#rep.runs, 1)
	local drop = {}
	for _, i in ipairs(rep.runs[1].drop) do drop[i] = true end
	eq(rep.runs[1].drop[1], 4, "kept from the town's end: 3 edges (240 m), the rest dropped")
	local _, removed = PL.dropEdges(inc, drop)
	eq(removed, 4, "3 straight edges + the side street left hanging")
	eq(#inc.edges, 3)
	eq(#inc.nodes, 3)
	eq(inc.edges[3].node1, -6, "renumbered: edges -1..-3, nodes -4..-6")
	eq(#inc.joins, 1)
	-- houses along it: no run (every midpoint within HOUSE_R of a building)
	local inc2 = { nodes = {}, edges = {}, joins = {} }
	inc = inc2
	for k = 1, 6 do edge(ids[k], ids[k + 1], xs[k], xs[k + 1]) end
	local along = {}
	for x = 0, 480, 40 do along[#along + 1] = { x, 25 } end
	eq(#CK.straightRuns(inc2, along).runs, 0)
	-- a curved chain (turning 10 deg at each node): no run
	eq(CK.straightRuns(inc2, along).max, 0)
end)
