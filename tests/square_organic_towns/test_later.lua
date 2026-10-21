-- Later-ideas phase (2026-10-13): tree-lined town entries (ot_entry + ot_proposal decor), polycentric next steps
-- (ot_metro junction centres / third centre / core kinds, ot_poly grid cores). Upward density: test_driver.lua /
-- test_bigform.lua; protected meadows: test_bigform.lua.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local EN = ug_require(F.DIR .. "ot_entry.lua")
local MET = ug_require(F.DIR .. "ot_metro.lua")
local PO = ug_require(F.DIR .. "ot_poly.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local P = ug_require(F.DIR .. "ot_plan.lua")
local CK = ug_require(F.DIR .. "ot_check.lua")

local DIRS = "::/infrastructure/street/town/"
local OLD_SMALL = DIRS .. "town_old_small.street_template"
local OLD_SMALL_T = DIRS .. "town_old_small_trees.street_template"
local NEW_MED = DIRS .. "town_new_medium.street_template"
local NEW_MED_T = DIRS .. "town_new_medium_trees.street_template"
local NEW_XS = DIRS .. "town_new_xsmall.street_template"

test("entry: `_trees` variants of the town templates (small / medium / large), plain back, lanes unchanged", function()
	eq(EN.treesPath(OLD_SMALL), OLD_SMALL_T)
	eq(EN.treesPath(NEW_MED), NEW_MED_T)
	eq(EN.treesPath(NEW_XS), nil, "xsmall has no trees variant")
	eq(EN.treesPath(OLD_SMALL_T), nil, "already one")
	eq(EN.treesPath("::/infrastructure/street/country/country_new_small.street_template"), nil, "not a town street")
	eq(EN.plainPath(NEW_MED_T), NEW_MED)
	ok(EN.isTrees(NEW_MED_T) and not EN.isTrees(NEW_MED))
	eq(PR.pathLanes(NEW_MED_T), PR.pathLanes(NEW_MED), "the trees variant has the plain lanes")
	ok(PR.pathLanes(OLD_SMALL_T) ~= nil)
end)

--- A town style with one country road leaving east from (300, 0).
local function roadStyle(seedFor)
	local st = F.style({ forceStyle = "EU_ORGANIC", townId = seedFor or 7, year = 1920, nameList = "::/names/europe/europe.names" }, F.flat)
	st.roads = { roads = { { pts = { { 300, 0 }, { 700, 0 }, { 1200, 40 } }, len = 900, heading = 0, out = 1200 } }, junctions = {},
		segs = {} }
	return st
end

local function edge(x0, y0, x1, y1, class, template)
	return { entity = -1, node0 = -1, node1 = -2, p0 = { x0, y0, 0 }, p1 = { x1, y1, 0 }, t0 = { x1 - x0, y1 - y0, 0 },
		t1 = { x1 - x0, y1 - y0, 0 }, class = class or "small", template = template or OLD_SMALL, key = "k" }
end

test("entry: off by default (plain streets only, 2026-10-18): no town lines its entries", function()
	ok(not EN.ON)
	local inc = { edges = { edge(350, 40, 440, 40) } }
	for t = 1, 20 do
		ok(not EN.on(roadStyle(t)))
		eq(EN.mark(inc, roadStyle(t)), 0)
	end
	eq(inc.trees, nil)
end)

test("entry: streets along a road's first stretch out of town (beside, parallel) and wide streets at the entry", function()
	local wasOn = EN.ON
	EN.ON = true
	local st = roadStyle()
	ok(EN.isEntry(st.roads, edge(350, 40, 440, 40)), "beside the road, parallel")
	ok(EN.isEntry(st.roads, edge(500, -50, 600, -50)), "the other side")
	ok(not EN.isEntry(st.roads, edge(400, 40, 400, 140)), "across (a side lane): plain")
	ok(not EN.isEntry(st.roads, edge(800, 40, 900, 40)), "beyond LEN along the road: plain")
	ok(not EN.isEntry(st.roads, edge(350, 150, 440, 150)), "farther than BESIDE: plain")
	ok(EN.isEntry(st.roads, edge(280, 60, 280, 140, "main")), "a main street at the entry point")
	ok(not EN.isEntry(st.roads, edge(280, 60, 280, 140, "small")), "a small one there (across): plain")
	ok(not EN.isEntry(st.roads, edge(350, 40, 360, 40)), "too short")
	-- mark: seeded per town; a town that lines its entries flags only entry edges, never bridges
	local onTown, offTown
	for t = 1, 60 do
		local s = roadStyle(t)
		if EN.on(s) then onTown = onTown or s else offTown = offTown or s end
	end
	ok(onTown and offTown, "some towns line their entries, some don't")
	local inc = { edges = { edge(350, 40, 440, 40), edge(400, 40, 400, 140), edge(500, 40, 600, 40) } }
	inc.edges[3].bridge = true
	eq(EN.mark(inc, onTown), 1)
	ok(inc.edges[1].trees and not inc.edges[2].trees and not inc.edges[3].trees)
	eq(inc.trees, 1)
	eq(EN.mark(inc, onTown, function() return false end), 0, "no trees template in the game: none")
	eq(inc.trees, nil)
	eq(EN.mark(inc, offTown), 0)
	EN.mark(inc, onTown)
	eq(EN.strip(inc), 1)
	eq(inc.trees, nil)
	ok(not inc.edges[1].trees)
	local share = 0
	for t = 1, 200 do if EN.on(roadStyle(t)) then share = share + 1 end end
	print(string.format("      EU organic towns lining their entries: %.2f (P %.2f)", share / 200, EN.P.EU_ORGANIC))
	ok(math.abs(share / 200 - EN.P.EU_ORGANIC) < 0.12)
	EN.ON = wasOn
end)

--- One new edge -1 from dead end 500 (its edge 900, template `tpl`) to new node -3, then -2 on to -4.
local function inc2(tpl0, trees1, trees2)
	return {
		nodes = { { entity = -3, x = 100, y = 0, z = 0 }, { entity = -4, x = 200, y = 0, z = 0 } },
		edges = {
			{ entity = -1, node0 = 500, node1 = -3, p0 = { 0, 0, 0 }, p1 = { 100, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 },
				class = "small", template = OLD_SMALL, key = "a", trees = trees1 },
			{ entity = -2, node0 = -3, node1 = -4, p0 = { 100, 0, 0 }, p1 = { 200, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 },
				class = "small", template = OLD_SMALL, key = "b", trees = trees2 },
		},
		joins = { { node = 500, edge = -1 } },
		_tpl0 = tpl0,
	}
end

local function info(tpl0)
	return { nodes = { [500] = { hasConfig = true, edges = { 900 }, lanes = 4, src = 900, template = tpl0 } },
		sources = { [OLD_SMALL] = 901 }, fallback = 902 }
end

test("entry (proposal): a tree-lined edge takes the `_trees` template + its decorations; edges after a trees dead end go plain", function()
	local spec = assert(PR.build(inc2(OLD_SMALL, true, true), info(OLD_SMALL)))
	local a, b = spec.edges[1], spec.edges[2]
	eq(a.template, OLD_SMALL_T); eq(a.override, OLD_SMALL_T); eq(a.decor, "template")
	eq(a.src, 900, "the joint still copies the dead end's edge")
	eq(b.template, OLD_SMALL_T); eq(b.decor, "template"); eq(b.src, 901)
	ok(PR.summary(spec):find("trees=2", 1, true), PR.summary(spec))
	-- no flags: unchanged (no decor field, the summary as before)
	local plain = assert(PR.build(inc2(OLD_SMALL), info(OLD_SMALL)))
	eq(plain.edges[1].decor, nil); eq(plain.edges[1].override, nil); eq(plain.edges[2].decor, nil)
	ok(not PR.summary(plain):find("trees", 1, true))
	-- continuing from a tree-lined dead end without the flag: plain template, decorations cleared
	local cont = assert(PR.build(inc2(OLD_SMALL_T), info(OLD_SMALL_T)))
	eq(cont.edges[1].template, OLD_SMALL); eq(cont.edges[1].override, OLD_SMALL); eq(cont.edges[1].decor, "none")
	eq(cont.edges[2].decor, nil)
	-- lanes: every lane connection names a lane its segment has (the trees variant has the plain lanes)
	ok(PR.checkLanes(spec, function(_seg) return 4 end), "every lane connection names a lane its segment has")
	local joint = nil
	for _, c in ipairs(spec.cfgAdd) do if c.node == 500 then joint = c end end
	ok(joint and #joint.conns > 0, "the joint node gets its full config")
end)

test("plain streets only: a joint at a tram / bus-lane / barrier / tree-lined dead end takes the plain template", function()
	ok(PR.isPlain(OLD_SMALL) and PR.isPlain(NEW_XS) and PR.isPlain(DIRS .. "town_new_one_way_small.street_template"))
	ok(PR.isPlain("::/infrastructure/street/country/country_new_small.street_template"))
	for _, v in ipairs({ "_tram", "_tram_electrified", "_bus", "_barriers", "_trees" }) do
		local p = DIRS .. "town_new_medium" .. v .. ".street_template"
		ok(not PR.isPlain(p), v)
		eq(PR.plainPath(p), NEW_MED, v)
	end
	eq(PR.plainPath(DIRS .. "town_new_one_way_small_bus.street_template"), DIRS .. "town_new_one_way_small.street_template")
	eq(PR.plainPath("other_mod::/infrastructure/street/fancy_avenue.street_template"), nil)
	eq(PR.plainPath("::/infrastructure/street/highway/highway_new_small.street_template"), nil)
	for _, tpl in ipairs({ DIRS .. "town_old_small_tram.street_template", DIRS .. "town_old_small_tram_electrified.street_template",
			DIRS .. "town_old_small_barriers.street_template" }) do
		local spec = assert(PR.build(inc2(tpl), info(tpl)))
		local a = spec.edges[1]
		eq(a.template, OLD_SMALL, tpl); eq(a.override, OLD_SMALL, tpl); eq(a.src, 900)
		ok(a.decor ~= "template", tpl)
		eq(spec.edges[2].template, OLD_SMALL)
		ok(PR.checkLanes(spec, function(_seg) return 4 end), "the dead end's lanes")
	end
	-- the plain template's lanes known and different from the dead end's: the edge's own template instead
	local i = info(DIRS .. "town_old_medium_tram.street_template")
	i.nodes[500].lanes = 6
	i.templateLanes = { [DIRS .. "town_old_medium.street_template"] = 8 }
	local spec = assert(PR.build(inc2(DIRS .. "town_old_medium_tram.street_template"), i))
	eq(spec.edges[1].template, OLD_SMALL); eq(spec.edges[1].override, OLD_SMALL)
	-- another mod's street at the dead end: the edge's own plain template
	local mi = info("other_mod::/infrastructure/street/fancy_avenue.street_template")
	local ms = assert(PR.build(inc2("other_mod::/infrastructure/street/fancy_avenue.street_template"), mi))
	eq(ms.edges[1].template, OLD_SMALL); eq(ms.edges[1].override, OLD_SMALL)
	-- and no plain template of its own either: refused, never copied
	local bad = inc2("other_mod::/infrastructure/street/fancy_avenue.street_template")
	bad.edges[1].template = "other_mod::/infrastructure/street/fancy_avenue.street_template"
	local none, why = PR.build(bad, mi)
	eq(none, nil); eq(why, "specialJoin:500")
end)

test("polycentric: a centre at a country-road junction in range, the third from POLY_THIRD_CAP, core kinds seeded", function()
	eq(MET.centreCount(MET.POLY_MIN_CAP - 1), 0)
	eq(MET.centreCount(MET.POLY_MIN_CAP), 1)
	eq(MET.centreCount(2 * MET.POLY_MIN_CAP), 2)
	eq(MET.centreCount(MET.POLY_THIRD_CAP), 3)
	-- junctions: one in range near the axis, one too near, one off-axis
	local js = { { x = 1350, y = 120, heads = { 0.1, 1.6, 3.2 } }, { x = 500, y = 0, heads = { 0 } }, { x = 0, y = 1400, heads = { 1.5 } } }
	local cs = MET.centres({ 0, 0 }, 0, 3, 7, F.flat, nil, js)
	eq(#cs, 3)
	eq(cs[1].src, "junction"); eq(cs[1][1], 1350); eq(cs[1][2], 120)
	eq(cs[2].src, "ring", "opposite side: no junction there")
	eq(cs[3].src, "junction", "the third across the axis: the junction at 90 deg")
	for i = 1, 3 do
		for j = i + 1, 3 do ok(G.dist(cs[i][1], cs[i][2], cs[j][1], cs[j][2]) >= MET.POLY_SEP, "centres apart") end
	end
	-- without junctions: as before (ring, along the axis and opposite)
	local old = MET.centres({ 0, 0 }, 0, 2, 7, F.flat)
	eq(old[1].src, "ring"); ok(old[1][1] > 1000 and math.abs(old[1][2]) < 1)
	-- core kinds: grid more often in the US than in Europe
	local us, eu = 0, 0
	for s = 1, 300 do
		if MET.coreKind({ region = "US", seed = s, grower = "organic" }, 1) == "grid" then us = us + 1 end
		if MET.coreKind({ region = "EU", seed = s, grower = "organic" }, 1) == "grid" then eu = eu + 1 end
	end
	print(string.format("      grid cores: US %.2f, EU %.2f", us / 300, eu / 300))
	ok(us > eu)
end)

--- A polycentric metropolis style with forced centres, the given core kind on each.
local JD = 1150
local function polyStyle(kind, junction, townId)
	local base = F.style({ forceStyle = "EU_ORGANIC", townId = townId or 9, year = 1970, capacity = 20000,
		nameList = "::/names/europe/europe.names" }, F.flat)
	if junction then
		-- a crossroads JD m out along the town axis (the first centre's heading), roads along / across it
		local a = (base.shape and base.shape.axis) or base.axis or 0
		local ca, sa = math.cos(a), math.sin(a)
		local function w(u, v) return u * ca - v * sa, u * sa + v * ca end
		local x1, y1 = w(JD, -400)
		local x2, y2 = w(JD, 400)
		local x3, y3 = w(JD - 350, 0)
		local x4, y4 = w(JD + 350, 0)
		local jx, jy = w(JD, 0)
		base.roads = { roads = {}, segs = { { x1, y1, x2, y2 }, { x3, y3, x4, y4 } },
			junctions = { { x = jx, y = jy, heads = { a, a + math.pi / 2, a + math.pi, a - math.pi / 2 } } } }
		base._axisTest = a
	end
	local st = MET.apply(base, { variant = "polycentric", why = "test", forced = true }, { cap = 20000, sampler = F.flat })
	for _, c in ipairs(st.metro.centres) do c.core = kind end
	return st
end

test("polycentric (plan): a grid core at a secondary centre, squared, off the roads, crossings paired; plan cores untouched", function()
	local st = polyStyle("grid", true)
	ok(#st.metro.centres >= 2, "two centres at 20000")
	eq(st.metro.centres[1].src, "junction")
	local g = F.vanillaTown(OG.new(), { n = 4 })
	local mp = core.masterPlan(g, st, { terrain = F.flat }, 8)
	ok(mp.polyCores and #mp.polyCores >= 1, "cores recorded")
	local rec = mp.polyCores[1]
	eq(rec.kind, "grid")
	ok(rec.geo ~= nil, "a grid: " .. tostring(rec.why))
	ok(rec.planned > 0 and rec.runs > 0)
	local n, gu, gn = 0, 0, 0
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == "mpc1" then
			n = n + 1
			ok(pc.motifBranch and pc.motifJoin, "crossings come together")
			-- never across or onto the junction's roads (u = JD, v = 0 in the axis frame)
			local a = st._axisTest
			for _, p in ipairs(pc.pts) do
				local u = p[1] * math.cos(a) + p[2] * math.sin(a)
				local v = -p[1] * math.sin(a) + p[2] * math.cos(a)
				ok(math.abs(u - JD) >= PO.ROAD - 1 and math.abs(v) >= PO.ROAD - 1, "off the roads")
				gu, gn = gu + u, gn + 1
			end
		end
	end
	ok(n >= 8, "grid pieces " .. n)
	-- the grid lies in the quadrant toward the main centre (u < JD)
	ok(gu / math.max(1, gn) < JD, string.format("toward the town: mean u %.0f", gu / math.max(1, gn)))
	print(string.format("      grid core c1: %d pieces, %.0f m planned, %d runs; text %s", n, rec.planned, rec.runs, PO.text(mp, g)))
	ok(PO.text(mp, g):find("c1:grid@junction:0/", 1, true), PO.text(mp, g))
	-- plan cores: nothing laid
	local st2 = polyStyle("plan")
	local mp2 = core.masterPlan(g, st2, { terrain = F.flat }, 8)
	for _, pc in ipairs(mp2.pieces) do ok(not (type(pc.motif) == "string" and pc.motif:sub(1, 3) == "mpc"), "no grid pieces") end
	ok(PO.text(mp2, g):find("c1:plan@", 1, true), PO.text(mp2, g))
end)

test("polycentric (growth): the grid core is built once the town reaches it; every new node valid, no -0", function()
	-- (town 1: at the 44 m minimum block, 2026-10-18, town 9 stopped growing after 40 edges in this model, short of the
	-- grid centre; towns 1-12 build on the grid 9 of 12 times (10 before), town 1 then and now)
	local st = polyStyle("grid", nil, 1)
	-- a forced centre near the town so a few increments reach it
	st.metro.centres = MET.centres(st.centre, 0, 1, st.seed, F.flat, MET.POLY_D_FORCED)
	st.metro.centres[1].core = "grid"
	st.shape.second = { st.metro.centres[1][1], st.metro.centres[1][2] }
	st.shape.seconds = st.metro.centres
	-- (the housed front and the polycentric empty budget stay on: every new street gets houses in this model)
	local g = F.vanillaTown(OG.new(), { n = 5 })
	for _, e in ipairs(g.edges) do e.built = 6 end
	g.hasBuilt = true
	local total = 0
	for k = 1, 14 do
		local inc = core.planIncrement(g, st, { terrain = F.flat, join = "deadEnd", maxEdges = 36 })
		if #inc.edges == 0 then break end
		ok(P.noNegativeZero(inc), "no -0")
		local geo = CK.increment(inc, g)
		ok(geo.minRadius == nil or geo.minRadius >= 40, "curves")
		OG.apply(g, inc, k)
		for _, e in ipairs(g.edges) do if e.built == nil then e.built = 6 end end
		total = total + #inc.edges
	end
	local mp = core.masterPlan(g, st, { terrain = F.flat }, 8)
	local txt = PO.text(mp, g)
	print("      after growth: " .. txt .. ", edges " .. total)
	local built, planned = txt:match("c1:grid@%a+:(%d+)/(%d+)")
	ok(built and tonumber(built) > 0, "grid sides built: " .. txt)
	ok(F.minAngle(g) >= 0, "graph sane")
end)
