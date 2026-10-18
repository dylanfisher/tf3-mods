-- Road / village motifs (ot_motif_road + ot_roads, phase M2 of plans/square_organic_towns/MOTIFS_BRIEF.md, 2026-10-13):
-- the ribbon village, the village green and the crossroads hamlet. The country roads traced beyond the snapshot,
-- eligibility from the roads (none without them), each motif's pattern metric after simulated increments (join
-- "deadEnd" as in game), the satellites' crossroads / light industry preference, and the rules (no crossings, nothing
-- across a country road, water, grades, map edge, lead limit, configs for every new node).
-- Set OT_SVG=<dir> to dump an SVG per motif run (the plan grey, the motif's pieces orange, built streets black, roads red).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
local RM = ug_require(F.DIR .. "ot_motif_road.lua")
local RDS = ug_require(F.DIR .. "ot_roads.lua")
local L = ug_require(F.DIR .. "ot_motif_land.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")
local MAP = ug_require(F.DIR .. "ot_map.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SAT = ug_require(F.DIR .. "ot_satellite.lua")
local IND = ug_require(F.DIR .. "ot_industry.lua")

local EU = "::/names/europe/europe.names"
local KINDS = { "ribbon_village", "village_green", "crossroads_hamlet" }
local TOWN = "::/infrastructure/street/town/town_new_small.street_template"
local COUNTRY = "::/infrastructure/street/country/country_new_small.street_template"
local NEW_SMALL = TOWN
local SNAP = 500   -- m: the snapshot's reach in these fixtures (the driver: houses' extent + 300 m)

local function has(list, id) for _, m in ipairs(list or {}) do if m.id == id then return m end end end

--- A polyline from (x, y) at heading h0 (deg), n steps of `step` m, the heading wobbling by `wob` deg over `per` m.
local function roadPts(x, y, h0, n, step, wob, per)
	local pts = { { x, y } }
	for k = 1, n do
		local h = math.rad(h0 + (wob or 0) * math.sin(k * step / (per or 400)))
		x, y = x + math.cos(h) * step, y + math.sin(h) * step
		pts[#pts + 1] = { x, y }
	end
	return pts
end

--- A town (vanilla 4 x 4 core, 80 m) with country roads: list of polylines; each starts at a town node (nearest its
--- first point) or at the last point of an earlier road (`from` = index: a junction). Returns g (snapshot: the roads'
--- edges reaching within SNAP m of the centre, their nodes noJoin), full (every edge, as ot_engine.streets gives them),
--- roads (ot_roads.trace over the snapshot with a fetch from the full set), junction points.
local function roadTown(lines, o)
	o = o or {}
	local g = F.vanillaTown(nil, { n = o.core or 4, spacing = o.spacing or 80 })
	for _, e in ipairs(g.edges) do e.template = TOWN end
	local full, byNode, nodePos = {}, {}, {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		nodePos[e.n0], nodePos[e.n1] = { a.x, a.y }, { b.x, b.y }
		full[#full + 1] = { id = e.id, n0 = e.n0, n1 = e.n1, p0 = { a.x, a.y }, p1 = { b.x, b.y }, template = TOWN }
	end
	local nextId = 100000
	local ends = {}
	for li, ln in ipairs(lines) do
		local prev
		if ln.from then prev = ends[ln.from]
		else
			local nd = OG.nearestNode(g, ln.pts[1][1], ln.pts[1][2], 1e9)
			prev = nd.id
			nodePos[prev] = { nd.x, nd.y }
		end
		local first = prev
		for k = 2, #ln.pts do
			local id
			if ln.to and k == #ln.pts then id = ln.to else
				nextId = nextId + 1
				id = nextId
				nodePos[id] = { ln.pts[k][1], ln.pts[k][2] }
			end
			nextId = nextId + 1
			full[#full + 1] = { id = nextId, n0 = prev, n1 = id, p0 = nodePos[prev], p1 = nodePos[id], template = COUNTRY }
			prev = id
		end
		ends[li] = prev
		ln.first, ln.last = first, prev
		if ln.mid then ends[li] = ln.mid end
	end
	for _, ed in ipairs(full) do
		byNode[ed.n0] = byNode[ed.n0] or {}; byNode[ed.n0][#byNode[ed.n0] + 1] = ed
		byNode[ed.n1] = byNode[ed.n1] or {}; byNode[ed.n1][#byNode[ed.n1] + 1] = ed
	end
	-- the snapshot: the country edges reaching within SNAP of the centre go into g (their nodes not joinable)
	local snap = {}
	for _, ed in ipairs(full) do
		local d0, d1 = G.dist(0, 0, ed.p0[1], ed.p0[2]), G.dist(0, 0, ed.p1[1], ed.p1[2])
		if math.min(d0, d1) <= SNAP then
			snap[#snap + 1] = ed
			if ed.template == COUNTRY then
				for _, n in ipairs({ ed.n0, ed.n1 }) do
					if g.nodeById[n] == nil then
						local p = nodePos[n]
						OG.addNode(g, n, p[1], p[2], 20)
						g.nodeById[n].noJoin = true
					end
				end
				local e = OG.addEdge(g, ed.id, ed.n0, ed.n1, "small")
				e.template = COUNTRY
			end
		end
	end
	local roads = RDS.trace(snap, 0, 0, o.r or 160, { snapR = SNAP, fetch = function(n) return byNode[n] or {} end })
	return g, full, roads
end

-- the standard roads: A east-north-east out of town (to 1.7 km), B east-south-east (a fork with A, 60 deg), and a cross
-- road through A at ~1 km (a crossroads)
local function roadA() return { pts = roadPts(120, 120, 20, 20, 80, 6, 500) } end
local function roadB() return { pts = roadPts(120, -120, -40, 18, 80, 5, 450) } end
local function crossAt(li, k)
	return function(lines)
		local p = lines[li].pts[k]
		local h = G.heading(lines[li].pts[k - 1][1], lines[li].pts[k - 1][2], p[1], p[2]) + math.pi / 2
		return { pts = { p, { p[1] + math.cos(h) * 240, p[2] + math.sin(h) * 240 },
			{ p[1] + math.cos(h) * 480, p[2] + math.sin(h) * 480 } } },
			{ pts = { p, { p[1] - math.cos(h) * 240, p[2] - math.sin(h) * 240 },
			{ p[1] - math.cos(h) * 480, p[2] - math.sin(h) * 480 } } }
	end
end

--- Road A split at node k (so a cross road can start there): two lines, the second from the first's end.
local function splitA(k)
	local a = roadA().pts
	local p1, p2 = {}, {}
	for i = 1, k do p1[#p1 + 1] = a[i] end
	for i = k, #a do p2[#p2 + 1] = a[i] end
	return { pts = p1 }, { pts = p2, from = 1 }
end

local function crossroadsTown(o)
	local a1, a2 = splitA(12)
	local lines = { a1, a2 }
	local c1, c2 = crossAt(1, 12)({ a1 })
	c1.from, c2.from = 1, 1
	lines[3], lines[4] = c1, c2
	if o and o.fork then lines[5] = roadB() end
	return roadTown(lines, o)
end

local function resolve(sampler, o)
	o = o or {}
	local stats = T.stats(sampler, 0, 0, 600, 24)
	local inputs = I.build({ townId = o.id or 5, pos = { 0, 0 }, capacity = o.cap or 1500, year = o.year or 1900,
		nameList = EU, terrain = stats, forceStyle = o.style, autoStyle = o.style == nil, motif = o.motif,
		radius = o.radius or 160, bounds = o.bounds, frame = o.frame, roads = o.roads })
	return ST.resolve(inputs), stats, inputs
end

local function ctxOf(st, stats, inputs, o)
	o = o or {}
	return { style = st, terrain = stats, inputs = inputs, tier = o.tier or 2, year = o.year or 1900 }
end

local SVGDIR = os.getenv("OT_SVG")
local function svg(name, g, mp, sampler, full)
	if not SVGDIR then return end
	local f = io.open(SVGDIR .. "/" .. name .. ".svg", "w")
	if not f then return end
	local S, W = 1000, 2400
	local function X(x) return (x + W / 2 - 400) * S / W end
	local function Y(y) return (W / 2 - y) * S / W end
	f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="100%%" height="100%%" fill="white"/>', S, S))
	for i = 0, 49 do
		for j = 0, 49 do
			local x, y = -W / 2 + 400 + (i + 0.5) * W / 50, -W / 2 + (j + 0.5) * W / 50
			if T.isWater(sampler, x, y) then
				f:write(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#9cf"/>', X(x - W / 100), Y(y + W / 100),
					S / 50 + 0.5, S / 50 + 0.5))
			end
		end
	end
	for _, ed in ipairs(full or {}) do
		if ed.template == COUNTRY then
			f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#d33" stroke-width="2"/>', X(ed.p0[1]),
				Y(ed.p0[2]), X(ed.p1[1]), Y(ed.p1[2])))
		end
	end
	for _, pc in ipairs(mp and mp.pieces or {}) do
		local d = {}
		for i, p in ipairs(pc.pts) do d[#d + 1] = (i == 1 and "M" or "L") .. string.format("%.1f %.1f", X(p[1]), Y(p[2])) end
		f:write(string.format('<path d="%s" stroke="%s" stroke-width="%s" fill="none"/>', table.concat(d, " "),
			pc.motif and "#f80" or "#ddd", pc.motif and 2 or 1))
	end
	for _, e in ipairs(g.edges) do
		if e.template ~= COUNTRY then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#000" stroke-width="2"/>', X(a.x), Y(a.y),
				X(b.x), Y(b.y)))
		end
	end
	f:write("</svg>")
	f:close()
end

--- A forced motif on a road town, n increments (join "deadEnd"): measure, record, graph, style, increments, roads, full.
local function run(sampler, motif, lines, o)
	o = o or {}
	local g, full, roads = roadTown(lines, o)
	local st, stats = resolve(sampler, { motif = motif, style = o.style or "EU_ORGANIC", radius = o.radius, cap = o.cap,
		bounds = o.bounds, roads = roads, year = o.year })
	local incs = core.simulate(g, st, { terrain = sampler, stats = stats, join = "deadEnd" }, o.n or 12)
	local m = has(st.motifs, motif)
	local r = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = o.pts or {}, sampler = sampler, MT = MT, SH = SH })
	if o.svg then svg(o.svg, g, core.masterPlan(g, st, { terrain = sampler, stats = stats }, 8), sampler, full) end
	return r, m, g, st, incs, stats, roads, full
end

--- Rules every motif run keeps: no crossing streets, nothing on water, no steep new street, no large template, every new
--- street clear of the country roads (never across one: the roads beyond the snapshot too).
local function rules(name, g, st, incs, sampler, roads)
	local e1, e2 = F.crossingPair(g)
	ok(e1 == nil, name .. ": crossing edges " .. tostring(e1 and e1.id) .. "/" .. tostring(e2 and e2.id))
	ok(F.minAngle(g) >= 15, name .. ": min angle " .. F.minAngle(g))
	local idx = RM.segIndex(roads and roads.segs)
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			local pts = { { e.p0[1], e.p0[2] }, { e.p1[1], e.p1[2] } }
			ok(not T.wetAlong(sampler, pts, 0), name .. ": edge on water " .. tostring(e.key))
			ok(T.grade(sampler, e.p0[1], e.p0[2], e.p1[1], e.p1[2]) <= st.maxSlope + 0.01, name .. ": steep edge " .. tostring(e.key))
			if type(e.key) == "string" and e.key:match("^mrb") or tostring(e.key):match("^mvg") then
				ok(not tostring(e.template):find("large", 1, true), name .. ": wide motif street " .. e.key)
				local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
				ok(not RM.segNear(idx, mx, my, 12), name .. ": motif street on a country road " .. e.key)
			end
			for _, sg in ipairs(roads and roads.segs or {}) do
				if G.segIntersect(e.p0[1], e.p0[2], e.p1[1], e.p1[2], sg[1], sg[2], sg[3], sg[4], 1e-3) then
					ok(false, name .. ": street across a country road " .. tostring(e.key))
				end
			end
		end
	end
end

local function motifEdges(incs, prefix)
	local n, list = 0, {}
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			if type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then n = n + 1; list[#list + 1] = e end
		end
	end
	return n, list
end

---------------------------------------------------------------------------

test("registry: the three M2 kinds are drawn kinds with append-only save indices (7-9)", function()
	for i, id in ipairs({ "crescent", "hill_road", "hill_climb", "valley_fishbone", "harbour_crescent", "fishing_village" }) do
		eq(MO.IDS[i], id)
	end
	for i, id in ipairs(KINDS) do
		eq(MO.IDS[i + 6], id)
		local k = MO.BY_ID[id]
		ok(k and not k.derived and k.eligible and k.measure, id)
	end
	ok(MO.BY_ID.ribbon_village.plan and MO.BY_ID.village_green.plan, "plan hooks")
	ok(MO.BY_ID.crossroads_hamlet.style, "the hamlet picks its junction")
	eq(MO.BY_ID.ribbon_village.group, MO.BY_ID.village_green.group)
	ok(MO.BY_ID.ribbon_village.lock and MO.BY_ID.village_green.lock, "locked streets")
	ok(MO.BY_ID.ribbon_village.dose, "the ribbon doses its road-side row")
	local v = MO.encode({ { id = "ribbon_village" }, { id = "crossroads_hamlet" } })
	eq(v, 7 + 64 * 9)
	local d = MO.decode(v)
	eq(d[1], "ribbon_village"); eq(d[2], "crossroads_hamlet")
end)

test("roads: traced beyond the snapshot (fetch), junctions, side roads, forks; the town graph fallback", function()
	local g, full, roads = crossroadsTown({ fork = true })
	print(RDS.text(roads))
	ok(#roads.roads >= 2, "roads " .. #roads.roads)
	-- road A followed through the crossroads to its end (1.7 km), beyond the 500 m snapshot
	local a = roads.roads[1]
	ok(a.out >= 1600, "followed to " .. a.out)
	near(math.deg(G.wrap(a.heading)), 30, 10)
	-- the crossroads at A's 12th node, 4 roads
	eq(#roads.junctions, 1)
	local j = roads.junctions[1]
	near(j.x, roadA().pts[12][1], 1); near(j.y, roadA().pts[12][2], 1)
	eq(j.deg, 4)
	eq(#j.heads, 4)
	ok(j.d > 900 and j.d < 1100, "junction at " .. j.d)
	-- the side roads' segments are known (clearance), though never followed
	local idx = RM.segIndex(roads.segs)
	local cx, cy = full[#full].p1[1], full[#full].p1[2]
	ok(#roads.segs >= 40, "segs " .. #roads.segs)
	ok(RM.segNear(idx, j.x + 1, j.y + 1, 5), "the junction's segments")
	-- forks: A and B leave 60 deg apart
	local fk = RDS.forks(roads)
	ok(#fk >= 1, "a fork")
	ok(fk[1].angle > math.rad(45) and fk[1].angle < math.rad(80), "fork angle " .. math.deg(fk[1].angle))
	-- without a fetch the trace ends at the snapshot's edges; the graph fallback sees the same stretch
	local snap = {}
	for _, ed in ipairs(full) do
		if math.min(G.dist(0, 0, ed.p0[1], ed.p0[2]), G.dist(0, 0, ed.p1[1], ed.p1[2])) <= SNAP then snap[#snap + 1] = ed end
	end
	local cut = RDS.trace(snap, 0, 0, 160, {})
	ok(cut.roads[1].out < 700 and cut.roads[1].out > 400, "snapshot only: " .. cut.roads[1].out)
	local fg = RDS.fromGraph(g, 0, 0, 160)
	ok(#fg.roads >= 1, "graph fallback " .. RDS.text(fg))
	-- deterministic
	local _, _, again = crossroadsTown({ fork = true })
	eq(RDS.text(again), RDS.text(roads))
	-- a town without country roads: none
	local plain = RDS.trace({ { id = 1, n0 = 1, n1 = 2, p0 = { 0, 0 }, p1 = { 80, 0 }, template = TOWN } }, 0, 0, 160, {})
	eq(#plain.roads, 0); eq(#plain.junctions, 0)
	_ = cx; _ = cy
end)

test("eligibility: from the roads (none without them), size, era, style; the fork and the crossroads", function()
	local _, _, roads = crossroadsTown()
	local _, _, forkRoads = crossroadsTown({ fork = true })
	local lines = {}
	local function score(id, sampler, o, ctxo)
		local st, stats, inputs = resolve(sampler, o)
		local s, why = MO.BY_ID[id].eligible(ctxOf(st, stats, inputs, ctxo))
		return s or 0, why
	end
	for _, id in ipairs(KINDS) do
		-- no roads known: never
		eq(score(id, F.flat, { style = "EU_ORGANIC" }), 0, id .. " without roads")
		local s, why = score(id, F.flat, { style = "EU_ORGANIC", roads = roads })
		lines[#lines + 1] = string.format("%s=%.2f (%s)", id, s, tostring(why))
		ok(s > 0 and type(why) == "string", id .. " with roads")
		-- a metropolis-sized town: none
		eq(score(id, F.flat, { style = "EU_ORGANIC", roads = roads }, { tier = 4 }), 0, id .. " tier 4")
	end
	print(table.concat(lines, "  "))
	-- era: ribbon and green less in the motor age; the hamlet any era
	local early = score("ribbon_village", F.flat, { style = "EU_ORGANIC", roads = roads })
	local late = score("ribbon_village", F.flat, { style = "EU_ORGANIC", roads = roads, year = 1970 }, { year = 1970 })
	ok(late < early, "ribbon later: " .. late .. " vs " .. early)
	eq(score("crossroads_hamlet", F.flat, { style = "EU_ORGANIC", roads = roads }, { year = 1970 }),
		score("crossroads_hamlet", F.flat, { style = "EU_ORGANIC", roads = roads }), "hamlet any era")
	-- the grid styles weigh less
	ok(score("ribbon_village", F.flat, { style = "NA_GRID", roads = roads }) < early, "grid ribbon")
	-- a fork calls for the green more
	local gFork = score("village_green", F.flat, { style = "EU_ORGANIC", roads = forkRoads })
	local gOne = score("village_green", F.flat, { style = "EU_ORGANIC", roads = roads })
	ok(gFork > gOne, "fork " .. gFork .. " vs " .. gOne)
	-- the green: no green on a steep site
	eq(score("village_green", F.plane(0.12, 0), { style = "EU_ORGANIC", roads = forkRoads }), 0, "steep: no green")
	-- the hamlet: the crossroads must lie 0.45-1.6 km out and beyond the houses
	eq(score("crossroads_hamlet", F.flat, { style = "EU_ORGANIC", roads = roads, radius = 900 }), 0, "a junction in town")
	local far = { roads = roads.roads, segs = roads.segs, junctions = { { x = 2500, y = 0, d = 2500, deg = 4, heads = {} } } }
	eq(score("crossroads_hamlet", F.flat, { style = "EU_ORGANIC", roads = far }), 0, "too far")
	local other = { roads = roads.roads, segs = roads.segs, junctions = { { x = 900, y = 0, d = 900, deg = 3, own = false } } }
	eq(score("crossroads_hamlet", F.flat, { style = "EU_ORGANIC", roads = other }), 0, "nearer another town")
	-- picks: deterministic, one of ribbon / green at most (group road), saved
	local seen = { ribbon_village = 0, village_green = 0, crossroads_hamlet = 0 }
	for id = 1, 120 do
		local a = resolve(F.flat, { id = id, roads = forkRoads })
		local b = resolve(F.flat, { id = id, roads = forkRoads })
		eq(MO.text(a.motifs), MO.text(b.motifs), "same town, same motifs")
		local road = 0
		for _, m in ipairs(a.motifs) do
			if seen[m.id] then seen[m.id] = seen[m.id] + 1 end
			if MO.BY_ID[m.id].group == "road" then road = road + 1 end
		end
		ok(road <= 1, "one road motif at most: " .. MO.text(a.motifs))
	end
	print(string.format("picks of 120 fork + crossroads towns: ribbon %d, green %d, hamlet %d", seen.ribbon_village,
		seen.village_green, seen.crossroads_hamlet))
	ok(seen.ribbon_village > 5 and seen.village_green > 5 and seen.crossroads_hamlet > 5, "each kind drawn")
	-- a town without roads (the old tests' fixtures) draws none of them
	for id = 1, 40 do
		for _, m in ipairs(resolve(F.flat, { id = id }).motifs) do ok(seen[m.id] == nil, "no road motif without roads") end
	end
end)

test("ribbon village: a street beside the road out of town at the setback, lanes off its far side, road-side dose", function()
	local r, m, g, st, incs, stats, roads, full = run(F.flat, "ribbon_village", { roadA() }, { n = 14, svg = "ribbon_village" })
	local geo = m.geo
	ok(geo ~= nil, tostring(m.planWhy))
	print(r.text, "planned " .. string.format("%.0f m, %d lanes, side %d, off %.0f", geo.ix.len, #geo.lanes, geo.sd, geo.off))
	ok(geo.beyond >= 400, "planned beyond the town " .. geo.beyond)
	ok(#geo.lanes >= 2 and #geo.lanes <= 4, "lanes planned " .. #geo.lanes)
	ok(r.len >= 300, "ribbon built " .. r.len)
	ok(r.lanes >= 1, "a lane built: " .. r.lanes)
	-- the setback: every built ribbon street (beyond the town) off the road by about `off`, never across it
	local rix = L.index(roads.roads[1].pts)
	local n, list = motifEdges(incs, "mrb#")
	ok(n >= 4, "ribbon edges " .. n)
	for _, e in ipairs(list) do
		local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
		if G.dist(0, 0, mx, my) > 260 then
			local d = L.nearest(rix, mx, my, 200)
			ok(d and d >= geo.off - 14 and d <= geo.off + 14, "setback " .. tostring(d) .. " vs " .. geo.off)
		end
	end
	-- the lanes go away from the road
	for _, ln in ipairs(geo.lanes) do
		local d0 = L.nearest(rix, ln.x0, ln.y0, 400) or 0
		local d1 = L.nearest(rix, ln.x1, ln.y1, 400) or 0
		ok(d1 > d0 + 30, "lane away from the road")
	end
	-- no plan street between the ribbon and the road beyond the town
	local mp = core.masterPlan(g, st, { terrain = F.flat, stats = stats }, 8)
	local between = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == nil then
			local mx, my = G.polyAt(pc.pts, 0.5)
			local d, _, side = L.nearest(geo.ix, mx, my, geo.off)
			if d and G.dist(0, 0, mx, my) > geo.r0 and side * geo.sd < 0 then between = between + 1 end
		end
	end
	eq(between, 0, "plan streets between the ribbon and the road")
	rules("ribbon", g, st, incs, F.flat, roads)
	-- the dose: points on the road side of the new ribbon streets, between the street and the road
	local inc
	for _, x in ipairs(incs) do if motifEdges({ x }, "mrb#") > 0 then inc = x; break end end
	local pts = MO.dose(st, inc.edges, D.FILL_OFFSET, D.FILL_POINTS)
	ok(#pts >= 1, "dose points")
	for _, p in ipairs(pts) do
		local d, _, side = L.nearest(geo.ix, p[1], p[2], 40)
		ok(d and side * geo.sd < 0, "dose on the road side")
		ok((L.nearest(rix, p[1], p[2], 100) or 999) >= 8, "not on the road")
	end
	eq(select(2, D.fillKind({ style = st, spec = { edges = inc.edges } }, {}, { actual = 100, target = 100, initial = 100 }, nil, 50, 0)),
		"motif")
	-- locked: the build's ribbon streets (no game side streets on them)
	local keys, nk, mode = D.lockKeys({ style = st, inc = inc })
	ok(keys and nk >= 1, "locked " .. tostring(nk) .. " " .. tostring(mode))
	for k in pairs(keys or {}) do ok(tostring(k):match("^mrb") ~= nil or st.shape ~= nil, "lock key " .. tostring(k)) end
	-- deterministic
	local a = RM.ribbonGeo(st, g, F.flat, 1500)
	local b = RM.ribbonGeo(st, g, F.flat, 1500)
	near(a.ix.len, b.ix.len, 1e-9); eq(a.sd, b.sd); eq(#a.lanes, #b.lanes)
	-- water beside the road on one side: the ribbon takes the dry side; a lake ahead ends it
	local lake = T.sampler(function(x, y) return (y > 0.36 * x + 140 and x > 300) and -3 or 20 end)
	local _, ml = run(lake, "ribbon_village", { roadA() }, { n = 2 })
	ok(ml.geo == nil or ml.geo.sd == -1, "the dry side (" .. tostring(ml.geo and ml.geo.sd) .. ")")
	-- no road: nothing planned, says why
	local _, mn = run(F.flat, "ribbon_village", {}, { n = 2 })
	eq(mn.geo, nil); eq(mn.planWhy, "noRoad")
end)

test("village green: a lens (one road) or a triangle at a fork, closed around the green, nothing built inside", function()
	for _, case in ipairs({ { name = "lens", lines = { roadA() }, shape = "lens" },
		{ name = "triangle", lines = { roadA(), roadB() }, shape = "triangle" } }) do
		local r, m, g, st, incs, stats, roads = run(F.flat, "village_green", case.lines, { n = 16, svg = "village_green_" .. case.name })
		local geo = m.geo
		ok(geo ~= nil, case.name .. " " .. tostring(m.planWhy))
		print(case.name .. ": " .. r.text)
		eq(geo.shape, case.shape)
		ok(geo.d >= RM.VG.D[1] and geo.d <= RM.VG.D[2] + RM.VG.PUSH_N * RM.VG.PUSH, "distance " .. geo.d)
		ok(r.cover >= 0.9, case.name .. ": the green's ring closed: " .. r.cover)
		-- nothing built inside the green (only its ring)
		local inside = 0
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			if RM.pointInPoly(geo.poly, mx, my) then
				local onRing = (L.nearest(L.index(geo.boundary), mx, my, 10)) ~= nil
				if not onRing then inside = inside + 1 end
			end
		end
		eq(inside, 0, case.name .. ": streets inside the green")
		-- the plan: nothing inside the green
		local mp = core.masterPlan(g, st, { terrain = F.flat, stats = stats }, 8)
		for _, pc in ipairs(mp.pieces) do
			if pc.motif == nil then
				local mx, my = G.polyAt(pc.pts, 0.5)
				ok(not RM.pointInPoly(geo.poly, mx, my), case.name .. ": plan street inside the green")
			end
		end
		-- the triangle sits in the fork, between the two roads
		if case.shape == "triangle" then
			ok(G.angleDiff(geo.theta, geo.fork.bisector) <= RM.VG.FORK_TOL + 1e-6, "along the fork's bisector")
		end
		-- a later plan (new session, the motif record gone) finds the built green again by its locked streets (the
		-- driver locks them, ot_driver.lockKeys): same place
		local bix = L.index(geo.boundary)
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if L.nearest(bix, (a.x + b.x) / 2, (a.y + b.y) / 2, 8) then e.locked = true end
		end
		local st2 = resolve(F.flat, { motif = "village_green", style = "EU_ORGANIC", roads = roads, radius = 330 })
		local again = RM.greenGeo(st2, g, F.flat, 1500)
		ok(again and again.ours, case.name .. ": the built green is found again")
		near(again.P[1], geo.P[1], 1e-6); near(again.P[2], geo.P[2], 1e-6)
		rules("green " .. case.name, g, st, incs, F.flat, roads)
		-- houses: those deeper inside than a lot count as on the green
		local pts = { { geo.P[1] + math.cos(geo.theta) * 120, geo.P[2] + math.sin(geo.theta) * 120 } }
		local rr = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = pts })
		eq(rr.onGreen, 1)
	end
	-- steep or wet everywhere: no green, says why
	local _, mw = run(T.sampler(function(x, y) return G.dist(0, 0, x, y) > 230 and -3 or 20 end), "village_green", { roadA() }, { n = 1 })
	eq(mw.geo, nil)
	ok(tostring(mw.planWhy):match("noRoom") ~= nil, tostring(mw.planWhy))
end)

test("crossroads hamlet: the satellite seeded beside the crossroads (a quadrant between the roads), its own link", function()
	local g, full, roads = crossroadsTown()
	local st, stats, inputs = resolve(F.flat, { motif = "crossroads_hamlet", style = "EU_ORGANIC", roads = roads })
	ok(st.hamlet ~= nil, "the motif picks the junction")
	local j = roads.junctions[1]
	near(st.hamlet.x, j.x, 1e-6)
	-- eligibility: from HAMLET_MIN_BUILDINGS, no seeded draw
	local okH, why = SAT.eligible({ seed = 1, buildings = SAT.HAMLET_MIN_BUILDINGS, styleId = "EU_ORGANIC", hamlet = st.hamlet })
	ok(okH, why); eq(why, "hamlet")
	eq(select(2, SAT.eligible({ seed = 1, buildings = 100, styleId = "EU_ORGANIC", hamlet = st.hamlet })), "small")
	eq(select(2, SAT.eligible({ seed = 1, buildings = 900, styleId = "SUPERBLOCK", hamlet = st.hamlet })), "style")
	-- the site: beside the junction, in a quadrant, the link clear of the country roads (obstacles)
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do
		local nd = g.nodeById[n]
		if not nd.noJoin then ends[#ends + 1] = { nd.x, nd.y, n } end
	end
	local obst = { segs = {}, boxes = {} }
	for _, sg in ipairs(roads.segs) do obst.segs[#obst.segs + 1] = { sg[1], sg[2], sg[3], sg[4], kind = "street" } end
	local quads = SAT.quadrants(j.heads)
	eq(#quads, 4)
	for seed = 1, 8 do
		local site, n = SAT.pickSite({ cx = 0, cy = 0, r = 200, sampler = F.flat, seed = seed, deadEnds = ends, g = g,
			obstacles = obst, junctions = roads.junctions, hamlet = st.hamlet })
		ok(site ~= nil, "seed " .. seed .. ": " .. tostring(n))
		if site then
			eq(site.at, "crossroads")
			local dj = G.dist(site.x, site.y, j.x, j.y)
			ok(dj >= 85 and dj <= 175, "beside the junction " .. dj)
			ok(SAT.clearOfObstacles(obst, site.link, SAT.START_SKIP), "link clear of the roads")
			for _, s2 in ipairs(SAT.streets(site)) do
				if s2.sat ~= "link" then ok(SAT.clearOfObstacles(obst, s2.pts), "core clear of the roads") end
			end
		end
	end
	-- no hamlet motif: a crossroads site still scores better than the ring (HAMLET_BONUS)
	local at = 0
	for seed = 1, 10 do
		local site = SAT.pickSite({ cx = 0, cy = 0, r = 200, sampler = F.flat, seed = seed, deadEnds = ends, g = g,
			obstacles = obst, junctions = roads.junctions })
		if site and site.at == "crossroads" then at = at + 1 end
	end
	print("satellites at the crossroads (no motif): " .. at .. " of 10")
	ok(at >= 5, "crossroads preferred " .. at)
	-- the measure: waiting until the satellite stands, then its numbers
	local m = has(st.motifs, "crossroads_hamlet")
	local w = MO.measure(m, { g = g, style = st, pts = {} })
	eq(w.text, "none:waiting")
	local sat = { x = j.x + 100, y = j.y - 60, edges = 8, at = "crossroads" }
	local b = MO.measure(m, { g = g, style = st, pts = { { j.x + 110, j.y - 60 }, { 0, 0 } }, sat = sat })
	eq(b.houses, 1)
	ok(b.text:match("^site=") ~= nil, b.text)
end)

test("satellites at farms / light industry (never heavy): a farm nearby scores better, heavy / medium keep the site away", function()
	local _, ends = (function()
		local g = F.roundCore(OG.new(), { rings = { 90, 180, 270 }, counts = { 6, 10, 14 } })
		local e = {}
		for _, n in ipairs(OG.deadEnds(g)) do local nd = g.nodeById[n]; e[#e + 1] = { nd.x, nd.y, n } end
		return g, e
	end)()
	local light, heavyNear = 0, 0
	for seed = 1, 12 do
		-- a farm 1.1 km south: the site goes beside it (not on top)
		local info = IND.forTown({ { 0, -1150, file = "industry/farm/farm.con" } }, 0, 0, 1950)
		local s = SAT.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = seed, deadEnds = ends, industry = info })
		ok(s ~= nil)
		if s and s.at == "light" then
			light = light + 1
			local d = G.dist(s.x, s.y, 0, -1150)
			ok(d >= SAT.LIGHT_MIN and d <= SAT.LIGHT_R, "beside the farm " .. d)
		end
		-- a steel mill: still away
		local hv = IND.forTown({ { 0, -1150, file = "industry/steel_mill/steel_mill.con" } }, 0, 0, 1950)
		local h = SAT.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = seed, deadEnds = ends, industry = hv })
		ok(h and IND.pen(hv, h.x, h.y) <= SAT.HEAVY_PEN, "away from heavy industry")
		if h and G.dist(h.x, h.y, 0, -1150) < 500 then heavyNear = heavyNear + 1 end
	end
	print(string.format("sites beside a farm: %d of 12; within 500 m of a steel mill: %d of 12", light, heavyNear))
	ok(light >= 8, "beside the farm " .. light)
	eq(heavyNear, 0)
	-- penHeavy ignores the light works, keeps the heavy ones
	local mix = IND.forTown({ { 0, 0, file = "industry/farm/farm.con" }, { 1400, 0, file = "industry/steel_mill/steel_mill.con" } }, 0, 0, 1950)
	near(IND.penHeavy(mix, 0, 0), 0, 1e-3)
	ok(IND.penHeavy(mix, 1400, 0) > 0.5)
	near(IND.nearestLight(mix, 30, 40), 50, 1e-6)
end)

test("rules: map edge margin, lead limit from the houses, configs for every new node", function()
	-- the map's east edge 900 m out: the ribbon (heading east-north-east) stops 400 m before it
	local bounds = { -4000, -4000, 900, 4000 }
	local _, m, g, st, incs, _, roads = run(F.flat, "ribbon_village", { roadA() }, { bounds = bounds })
	ok(m.geo ~= nil, tostring(m.planWhy))
	for _, p in ipairs(m.geo.line) do ok(MAP.edgeDist(bounds, p[1], p[2]) >= MAP.MARGIN - 45, "ribbon near the map edge") end
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			ok(MAP.edgeDist(bounds, e.p1[1], e.p1[2]) >= MAP.MARGIN - 1, "street near the map edge " .. tostring(e.key))
		end
	end
	rules("ribbon edge", g, st, incs, F.flat, roads)
	-- house data: no new piece farther than the lead limit from a housed street; the motif still builds
	for _, c in ipairs({ { "ribbon_village", { roadA() } }, { "village_green", { roadA(), roadB() } } }) do
		local g2, _, roads2 = roadTown(c[2])
		local st2, stats2 = resolve(F.flat, { motif = c[1], style = "EU_ORGANIC", roads = roads2 })
		local motif = 0
		for k = 1, 8 do
			F.markBuilt(g2, 40 + 30 * k)
			local idx = SEL.housedIndexM(g2, SEL.MAX_LEAD_M)
			local inc = core.planIncrement(g2, st2, { terrain = F.flat, stats = stats2, join = "deadEnd" })
			if #inc.edges == 0 then break end
			for _, e in ipairs(inc.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do
					ok(SEL.housedDist(idx, p[1], p[2]) <= SEL.MAX_LEAD_M + 1, c[1] .. ": beyond the lead limit")
				end
				if type(e.key) == "string" and (e.key:match("^mrb") or e.key:match("^mvg")) then motif = motif + 1 end
			end
			OG.apply(g2, inc, k)
		end
		ok(motif > 0, c[1] .. ": the motif builds with house data too")
	end
	-- crash rule: every new node of a motif increment gets a config, every lane index valid
	local specs = 0
	for _, c in ipairs({ { "ribbon_village", { roadA() } }, { "village_green", { roadA() } }, { "village_green", { roadA(), roadB() } } }) do
		local g3, _, roads3 = roadTown(c[2], { core = 3, spacing = 70 })
		local st3, stats3 = resolve(F.flat, { motif = c[1], style = "EU_ORGANIC", roads = roads3 })
		for k = 1, 8 do
			local inc = core.planIncrement(g3, st3, { terrain = F.flat, stats = stats3, join = "deadEnd" })
			if #inc.edges == 0 then break end
			local inf = { nodes = {}, sources = {}, fallback = 902 }
			for _, jn in ipairs(inc.joins) do
				local edges = {}
				for _, eid in ipairs(g3.adj[jn.node] or {}) do edges[#edges + 1] = eid end
				inf.nodes[jn.node] = { hasConfig = true, edges = edges, lanes = 4, src = edges[1] or 902, template = NEW_SMALL }
			end
			local spec, err = PR.build(inc, inf)
			ok(spec ~= nil, c[1] .. " " .. tostring(err))
			if spec then
				specs = specs + 1
				local cfg = {}
				for _, cc in ipairs(spec.cfgAdd) do cfg[cc.node] = true end
				for _, nd in ipairs(spec.nodes) do ok(cfg[nd.entity], c[1] .. " node without a config") end
				ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
			end
			-- (never joined to a country-road node)
			for _, jn in ipairs(inc.joins) do ok(not g3.nodeById[jn.node].noJoin, c[1] .. ": joined a country-road node") end
			OG.apply(g3, inc, k)
		end
	end
	ok(specs >= 12, specs .. " specs")
end)

test("driver: the country roads traced once per town and session (fetch beyond the snapshot), junction owners, ROADS line", function()
	local _, full = crossroadsTown()
	local byNode, byId = {}, {}
	for _, ed in ipairs(full) do
		byId[ed.id] = ed
		byNode[ed.n0] = byNode[ed.n0] or {}; byNode[ed.n0][#byNode[ed.n0] + 1] = ed.id
		byNode[ed.n1] = byNode[ed.n1] or {}; byNode[ed.n1][#byNode[ed.n1] + 1] = ed.id
	end
	local snap = {}
	for _, ed in ipairs(full) do
		if math.min(G.dist(0, 0, ed.p0[1], ed.p0[2]), G.dist(0, 0, ed.p1[1], ed.p1[2])) <= SNAP then snap[#snap + 1] = ed end
	end
	local lines, reads, now = {}, 0, 0
	local E = {
		nowUs = function() now = now + 10; return now end,
		log = function(l) lines[#lines + 1] = l end,
		edge = function(id) reads = reads + 1; return byId[id] end,
		nodeStreetEdges = function(n) return byNode[n] or {} end,
		closestTown = function(x, y) return x > 900 and 2 or 1 end,
	}
	local d = D.new(E)
	d.opts = { debug = true }
	local job = { edges = snap, ext = { cx = 0, cy = 0, r = 160 } }
	local roads = d:countryRoads(job, 1, { 0, 0 })
	ok(roads and #roads.roads >= 1, "roads")
	ok(roads.roads[1].out >= 1600, "followed beyond the snapshot: " .. roads.roads[1].out)
	ok(reads > 0 and reads <= D.ROAD_MAX_FETCH * 4, "edge reads " .. reads)
	eq(#roads.junctions, 1)
	eq(roads.junctions[1].own, false, "the crossroads is nearer town 2")
	local again = d:countryRoads(job, 1, { 0, 0 })
	ok(again == roads, "cached for the session")
	local roadsLine = false
	for _, l in ipairs(lines) do if l:find("ROADS", 1, true) then roadsLine = true end end
	ok(roadsLine, "ROADS line")
	-- a hamlet only where the crossroads is this town's
	eq(RM.hamletJunction({ radius = 160, block = { len = 80, depth = 60 } }, roads), nil)
end)

test("virtual roads (no country road near the town, TF3's new maps): toward the neighbours, off the water; ribbon, entry", function()
	local EN = ug_require(F.DIR .. "ot_entry.lua")
	-- toward the two nearest neighbours, a third heading skipped when within SEP of one
	local vr = RDS.virtual(0, 0, 160, { sampler = F.flat, seed = 7,
		neighbours = { { dir = 0, dist = 3000 }, { dir = math.rad(150), dist = 3500 }, { dir = math.rad(20), dist = 3900 } } })
	ok(vr.virtual and #vr.roads == 2, "two roads " .. #vr.roads)
	for _, rd in ipairs(vr.roads) do
		ok(rd.virtual and rd.out >= 1500, "out " .. rd.out)
		ok(G.angleDiff(rd.heading, 0) < math.rad(10) or G.angleDiff(rd.heading, math.rad(150)) < math.rad(10), "toward a neighbour")
	end
	eq(#vr.segs, 0, "no segments to keep clear of")
	eq(#vr.junctions, 0, "no junctions (no hamlet)")
	ok(RDS.text(vr):find("^virtual:2:"), RDS.text(vr))
	-- no neighbour: the land's directions, else seeded; at least MIN_N
	local v2 = RDS.virtual(0, 0, 160, { sampler = F.flat, seed = 3 })
	ok(#v2.roads >= RDS.V.MIN_N, "seeded " .. #v2.roads)
	-- water: a road toward the sea is turned or left out, never on water
	local coast = F.coast(300)
	local v3 = RDS.virtual(0, 0, 160, { sampler = coast, seed = 3, neighbours = { { dir = 0, dist = 2000 }, { dir = math.pi, dist = 2500 } } })
	for _, rd in ipairs(v3.roads) do
		for _, p in ipairs(rd.pts) do ok(not T.isWater(coast, p[1], p[2]), "virtual road on water") end
	end
	ok(#v3.roads >= 1, "inland road kept")
	-- the driver: no road edge in the snapshot -> virtual roads, the ROADS line says so
	local lines, now = {}, 0
	local E = { nowUs = function() now = now + 10; return now end, log = function(l) lines[#lines + 1] = l end,
		edge = function() return nil end, nodeStreetEdges = function() return {} end, sampler = function() return F.flat end,
		towns = function() return { 1, 2 } end, boxCentre = function(id) if id == 2 then return 2500, 0 end return 0, 0 end }
	local d = D.new(E)
	d.opts = { debug = true }
	local g0 = F.vanillaTown(nil, { n = 3, spacing = 70 })
	local edges = {}
	for _, e in ipairs(g0.edges) do
		local a, b = g0.nodeById[e.n0], g0.nodeById[e.n1]
		edges[#edges + 1] = { id = e.id, n0 = e.n0, n1 = e.n1, p0 = { a.x, a.y }, p1 = { b.x, b.y }, template = TOWN }
	end
	local roads = d:countryRoads({ edges = edges, ext = { cx = 0, cy = 0, r = 120 } }, 1, { 0, 0 })
	ok(roads and roads.virtual and #roads.roads >= 2, "driver: virtual roads")
	ok(G.angleDiff(roads.roads[1].heading, 0) < math.rad(10) or G.angleDiff(roads.roads[2].heading, 0) < math.rad(10),
		"one toward the neighbour")
	local line = nil
	for _, l in ipairs(lines) do if l:find("ROADS", 1, true) then line = l end end
	ok(line and line:find("virtual=", 1, true) and line:find("nbr", 1, true) and line:find("nonTown=0", 1, true), tostring(line))
	-- the ribbon village on a virtual road: the street on the line itself, lanes both sides, built out of town
	local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
	local st, stats, inputs = resolve(F.flat, { motif = "ribbon_village", style = "EU_ORGANIC", roads = vr })
	local s, why = MO.BY_ID.ribbon_village.eligible(ctxOf(st, stats, inputs))
	ok(s > 0 and tostring(why):find("virtual", 1, true), "eligible on virtual roads: " .. tostring(why))
	local s2, why2 = MO.BY_ID.village_green.eligible(ctxOf(st, stats, inputs))
	ok(s2 > 0, "village green on virtual roads: " .. tostring(why2))
	local s3, why3 = MO.BY_ID.crossroads_hamlet.eligible(ctxOf(st, stats, inputs))
	eq(s3, 0, "no hamlet without a real crossroads: " .. tostring(why3))
	local incs = core.simulate(g, st, { terrain = F.flat, stats = stats, join = "deadEnd" }, 14)
	local m = has(st.motifs, "ribbon_village")
	ok(m and m.geo and m.geo.virtual and m.geo.off == 0, "ribbon on the line: " .. tostring(m and m.planWhy))
	local r = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = {}, sampler = F.flat, MT = MT, SH = SH })
	print("      virtual ribbon: " .. tostring(r and r.text))
	local n = motifEdges(incs, "mrb")
	ok(n >= 4, "built " .. n)
	rules("virtual ribbon", g, st, incs, F.flat, vr)
	-- tree-lined entries: the town's streets along a virtual road's first stretch out of town (from its edge, not the centre)
	local rd = vr.roads[1]
	local hx, hy = math.cos(rd.heading), math.sin(rd.heading)
	local near = { p0 = { hx * 170, hy * 170 }, p1 = { hx * 230, hy * 230 }, class = "small" }
	local inner = { p0 = { hx * 10, hy * 10 }, p1 = { hx * 60, hy * 60 }, class = "medium" }
	ok(EN.isEntry(vr, near, { 0, 0 }, 160), "entry along the virtual road at the town edge")
	ok(not EN.isEntry(vr, inner, { 0, 0 }, 160), "not in the core")
end)

test("driver: country roads the snapshot misses are found by the wide road read (template country flag); no virtual roads then", function()
	local _, full = crossroadsTown()
	-- the snapshot: the town's own streets only (as in the final test: no road edge in it)
	local snap = {}
	for _, ed in ipairs(full) do if RDS.isTown(ed.template) then snap[#snap + 1] = ed end end
	local wideList = {}
	for _, ed in ipairs(full) do
		local c = {}
		for k, v in pairs(ed) do c[k] = v end
		c.country = not RDS.isTown(ed.template)
		c.street = true
		wideList[#wideList + 1] = c
	end
	local byNode, byId = {}, {}
	for _, ed in ipairs(full) do
		byId[ed.id] = ed
		byNode[ed.n0] = byNode[ed.n0] or {}; byNode[ed.n0][#byNode[ed.n0] + 1] = ed.id
		byNode[ed.n1] = byNode[ed.n1] or {}; byNode[ed.n1][#byNode[ed.n1] + 1] = ed.id
	end
	local lines, now = {}, 0
	local E = {
		nowUs = function() now = now + 10; return now end,
		log = function(l) lines[#lines + 1] = l end,
		edge = function(id) return byId[id] end,
		nodeStreetEdges = function(n) return byNode[n] or {} end,
		closestTown = function() return 1 end,
		roadEdges = function() return { list = wideList, stats = { edges = #wideList, streets = #wideList, noStreetComp = 0,
			tracks = 0, country = #wideList - #snap, town = #snap, other = 0, templates = { country_new_small = #wideList - #snap } } } end,
	}
	local d = D.new(E)
	d.opts = { debug = true }
	local job = { edges = snap, ext = { cx = 0, cy = 0, r = 160 } }
	local roads = d:countryRoads(job, 1, { 0, 0 })
	ok(roads and not roads.virtual and #roads.roads >= 1, "real roads found: " .. RDS.text(roads))
	ok(job.roadEdges and #job.roadEdges > #snap, "merged edges for the exits")
	local SHp = ug_require(F.DIR .. "ot_shape.lua")
	ok(#SHp.exits(job.roadEdges, 0, 0, 160) >= 1, "exits from the merged edges")
	local line
	for _, l in ipairs(lines) do if l:find("ROADS", 1, true) then line = l end end
	ok(line and line:find("wide=", 1, true) and line:find("country_new_small", 1, true) and line:find("virtual=-", 1, true), tostring(line))
	-- cached: the merged edges come back with the cached roads
	local job2 = { edges = snap, ext = { cx = 0, cy = 0, r = 160 } }
	ok(d:countryRoads(job2, 1, { 0, 0 }) == roads and job2.roadEdges ~= nil, "cached with its edges")
	-- the country flag decides over the name
	ok(RDS.isRoad({ template = "::/x/town_odd.street_template", country = true }), "country flag")
	ok(not RDS.isRoad({ template = "nil" }), "an unread template is no road")
end)
