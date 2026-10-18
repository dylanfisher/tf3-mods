-- ot_metro: metropolis as an automatic city style (NEXT_PHASE_BRIEF 14) and ot_metrics.greenGaps.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MET = ug_require(F.DIR .. "ot_metro.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local SITE = ug_require(F.DIR .. "ot_site.lua")
local core = ug_require(F.DIR .. "ot_core.lua")

local OPEN = { open = 0.9, rough = 0.05, coast = 0, river = 0, valley = 0, kind = "plain" }

test("decide: only big towns on open flat land, a seeded share; never MED hill; forced variants", function()
	eq(select(2, MET.decide({ styleId = "EU_EXTENSION", cap = 3000, features = OPEN, region = "EU", year = 2000, seed = 1 })), "small")
	eq(select(2, MET.decide({ styleId = "MED_HILL", cap = 9000, features = OPEN, region = "MED", year = 2000, seed = 1 })), "style")
	eq(select(2, MET.decide({ styleId = "EU_EXTENSION", cap = 9000, region = "EU", year = 2000, seed = 1,
		features = { open = 0.2, rough = 0.6, kind = "hills" } })), "site")
	local n, byV = 0, {}
	for seed = 1, 300 do
		local d = MET.decide({ styleId = "NA_GRID", cap = 6000, features = OPEN, region = "US", year = 2000, seed = seed * 7919 })
		if d then n = n + 1; byV[d.variant] = (byV[d.variant] or 0) + 1 end
	end
	print(string.format("      US flat towns >= 4000: %d of 300 metropolis (grid %d, polycentric %d, radial %d, other %d)", n,
		byV.grid or 0, byV.polycentric or 0, byV.radial or 0, n - (byV.grid or 0) - (byV.polycentric or 0) - (byV.radial or 0)))
	ok(n > 40 and n < 160, "rare enough, not never: " .. n)
	ok((byV.grid or 0) > (byV.oldcore or 0), "US: grids over old cores")
	-- no polycentric before the car age
	for seed = 1, 200 do
		local d = MET.decide({ styleId = "NA_GRID", cap = 6000, features = OPEN, region = "US", year = 1900, seed = seed })
		ok(d == nil or d.variant ~= "polycentric")
	end
	-- a coast town with some open land: corridor
	local coast = { open = 0.4, rough = 0.1, coast = 0.8, kind = "coast" }
	local any = false
	for seed = 1, 100 do
		local d = MET.decide({ styleId = "EU_EXTENSION", cap = 6000, features = coast, region = "EU", year = 2000, seed = seed })
		if d then eq(d.variant, "corridor"); any = true end
	end
	ok(any)
	local f = MET.decide({ forced = "radial", cap = 10 })
	eq(f.variant, "radial"); eq(f.forced, true)
end)

local function base(id, region, pos)
	return F.style({ forceStyle = id, townId = 9, pos = pos or { 0, 0 }, year = 2000, capacity = 6000,
		nameList = region == "EU" and "::/names/europe/europe.names" or nil }, F.flat)
end

test("apply: each variant changes road mix, shape and plan; the base style stays untouched", function()
	local b = base("EU_EXTENSION", "EU")
	local mainBefore = b.templates.main
	for _, v in ipairs(MET.VARIANTS) do
		local s = MET.apply(b, { variant = v, why = "test" }, { cap = 12000, sampler = F.flat })
		eq(s.metro.variant, v)
		eq(s.templates.main, "large", v .. ": large arterials")
		ok(s.templatePaths.main:find("_large", 1, true))
		eq(s.hierarchy, "late")
		if v == "grid" or v == "radial" or v == "oldcore" then eq(s.shape.id, "compact", v) end
		if v == "corridor" then eq(s.shape.id, "linear"); eq(s.shape.reach, 1) end
		if v == "radial" then ok(s.radial.spokes >= 8) end
		if v == "oldcore" then ok(s.outer ~= nil) end
		if v == "polycentric" then
			eq(s.shape.id, "twin")
			eq(#s.metro.centres, 1, "one secondary centre at 12000")
			local c = s.metro.centres[1]
			local d = math.sqrt(c[1] ^ 2 + c[2] ^ 2)
			ok(d >= MET.POLY_D[1] - 1 and d <= MET.POLY_D[2] + 1, "centre " .. d .. " m out")
			-- the twin field reaches toward the centre: cheaper there than at the same distance on the far side
			ok(SH.distance(s.shape, c[1], c[2]) < SH.distance(s.shape, -c[1], -c[2]))
		end
	end
	eq(b.templates.main, mainBefore, "the cached base style is not changed")
	eq(b.metro, nil)
	-- polycentric centres: none below POLY_MIN_CAP (unless forced), two from 2x
	eq(MET.centreCount(5000), 0)
	eq(MET.centreCount(5000, true), 1)
	eq(MET.centreCount(2 * MET.POLY_MIN_CAP), 2)
	local s2 = MET.apply(b, { variant = "polycentric" }, { cap = 2 * MET.POLY_MIN_CAP, sampler = F.flat })
	eq(#s2.metro.centres, 2)
	eq(#s2.shape.seconds, 2)
	ok(s2.metro.centres[1][1] * s2.metro.centres[2][1] + s2.metro.centres[1][2] * s2.metro.centres[2][2] < 0, "opposite sides")
	local s3 = MET.apply(b, { variant = "polycentric" }, { cap = 5000, forcedCentres = true, sampler = F.flat })
	eq(#s3.metro.centres, 1)
end)

test("lock and fill per variant: radial locks arterials, corridor the streets off the band, polycentric between", function()
	local b = base("EU_EXTENSION", "EU")
	local inc = { edges = {
		{ key = "art", class = "main", p0 = { 100, 0 }, p1 = { 200, 0 } },
		{ key = "loc", class = "small", p0 = { 0, 100 }, p1 = { 0, 180 } },
		{ key = "far", class = "small", p0 = { 0, 700 }, p1 = { 0, 780 } } } }
	local grid = MET.apply(b, { variant = "grid" }, { cap = 6000 })
	-- (Showcase v8 round: every new street of a metropolis is locked, so the town can't branch its own organic streets
	-- off the variant's skeleton; the variant rules below apply with LOCK_ALL off)
	local all, nAll = MET.lockKeys(grid, inc)
	eq(nAll, 3, "LOCK_ALL: every street")
	ok(all.art and all.loc and all.far)
	local savedAll = MET.LOCK_ALL
	MET.LOCK_ALL = false
	eq(MET.lockKeys(grid, inc), nil, "grid: no lock")
	local radial = MET.apply(b, { variant = "radial" }, { cap = 6000 })
	local k, n = MET.lockKeys(radial, inc)
	eq(n, 1); ok(k.art)
	local cor = MET.apply(b, { variant = "corridor" }, { cap = 6000 })
	cor.shape.axis = 0
	k, n = MET.lockKeys(cor, inc)
	ok(k and k.far and not k.art, "corridor: off-band streets locked")
	local fe = MET.fillEdges(cor, inc.edges)
	for _, e in ipairs(fe) do ok(e.key ~= "far", "corridor fill inside the band") end
	local poly = MET.apply(b, { variant = "polycentric" }, { cap = 6000, forcedCentres = true, sampler = F.flat })
	-- a street 600 m out across the line to the secondary centre: between the discs
	local c0 = poly.metro.centres[1]
	local l0 = math.sqrt(c0[1] ^ 2 + c0[2] ^ 2)
	local bx, by = -c0[2] / l0 * 600, c0[1] / l0 * 600
	local pinc = { edges = { inc.edges[1], inc.edges[2], { key = "between", class = "small", p0 = { bx, by }, p1 = { bx + 1, by + 60 } },
		{ key = "sub", class = "small", p0 = { c0[1], c0[2] }, p1 = { c0[1] + 50, c0[2] } } } }
	k = MET.lockKeys(poly, pinc)
	ok(k and k.between and not k.art and not k.loc and not k.sub, "polycentric: streets between the centres locked")
	MET.LOCK_ALL = savedAll
	eq(#MET.fillEdges(poly, pinc.edges), 3, "polycentric fill only in the centres' discs")
	-- radial / oldcore fill nearest the centre first
	local rf = MET.fillEdges(radial, { inc.edges[3], inc.edges[1] })
	eq(rf[1].key, "art")
	-- density per centre
	local pts = {}
	for i = 1, 50 do pts[#pts + 1] = { i, 0 } end
	local c = poly.metro.centres[1]
	for i = 1, 10 do pts[#pts + 1] = { c[1] + i, c[2] } end
	pts[#pts + 1] = { 900, 900 }
	local dn = MET.density(poly, pts, 1500)
	eq(dn.counts, { 50, 10 }); eq(dn.rest, 1)
	ok(dn.centres[1] > dn.centres[2] and dn.centres[2] > dn.between)
	local dt, bt = MET.densityText(dn)
	ok(dt:find("core:", 1, true) and dt:find("c1:", 1, true), dt)
end)

test("metropolis variants grow differently (planned 6 increments from an empty town)", function()
	local b = base("EU_EXTENSION", "EU")
	local shapes = {}
	for _, v in ipairs({ "grid", "radial", "corridor", "oldcore" }) do
		local s = MET.apply(b, { variant = v }, { cap = 6000, sampler = F.flat })
		local g = OG.new()
		local L = { large = 0, total = 0 }
		for k = 1, 6 do
			local inc = core.planIncrement(g, s, { terrain = F.flat, join = "any" })
			if #inc.edges == 0 then break end
			L.large, L.total = L.large + inc.mix.large, L.total + inc.mix.total
			ok(inc.hier.maxDefl.large <= core.STRAIGHT_LIMITS.large.joint + 1e-6, v .. " straight large streets")
			OG.apply(g, inc, k)
		end
		local m = MT.graph(g, 0, 0)
		shapes[v] = m
		print(string.format("      %-9s edges=%d elong=%.2f large=%.0f%%", v, #g.edges, m.elong, L.total > 0 and 100 * L.large / L.total or 0))
		ok(#g.edges > 30, v .. " grows")
	end
	ok(shapes.corridor.elong > shapes.grid.elong, "the corridor is long")
end)

--- A square ring road (side m) around (0, 0) with a cross street, as a graph.
local function ring(side)
	local g = OG.new()
	local h = side / 2
	local a = OG.addNode(g, nil, -h, -h, 0)
	local b = OG.addNode(g, nil, h, -h, 0)
	local c = OG.addNode(g, nil, h, h, 0)
	local d = OG.addNode(g, nil, -h, h, 0)
	OG.addEdge(g, nil, a.id, b.id, "small")
	OG.addEdge(g, nil, b.id, c.id, "small")
	OG.addEdge(g, nil, c.id, d.id, "small")
	OG.addEdge(g, nil, d.id, a.id, "small")
	return g
end

test("green gaps: an empty enclosed block counts, a built one does not, open land outside never", function()
	local g = ring(400)
	local gg = MT.greenGaps(g, {})
	eq(gg.gaps, 1)
	ok(gg.gapHa > 12 and gg.gapHa < 17, "about 16 ha: " .. gg.gapHa)
	ok(gg.share > 0.9)
	-- houses all over the block: no gap
	local pts = {}
	for x = -190, 190, 30 do for y = -190, 190, 30 do pts[#pts + 1] = { x, y } end end
	eq(MT.greenGaps(g, pts).gaps, 0)
	-- houses only along the ring: the middle stays a gap (a meadow inside the block)
	pts = {}
	for t = -190, 190, 20 do
		for _, p in ipairs({ { t, -180 }, { t, 180 }, { -180, t }, { 180, t } }) do pts[#pts + 1] = p end
	end
	gg = MT.greenGaps(g, pts)
	eq(gg.gaps, 1)
	ok(gg.gapHa > 5 and gg.gapHa < 14, tostring(gg.gapHa))
	ok(MT.greenText(gg):find("^1/"))
	eq(MT.greenGaps(OG.new(), {}), nil)
	eq(MT.greenText(nil), "-")
	-- a dead-end street in open land encloses nothing
	local g2 = OG.new()
	local p, q = OG.addNode(g2, nil, 0, 0, 0), OG.addNode(g2, nil, 300, 0, 0)
	OG.addEdge(g2, nil, p.id, q.id, "small")
	eq(MT.greenGaps(g2, {}).enclosedHa, 0)
end)

test("green reserves: organic styles and metropolis parks; no plan piece inside, the town grows around them", function()
	local SEL = ug_require(F.DIR .. "ot_select.lua")
	local ST = ug_require(F.DIR .. "ot_style.lua")
	-- (a compact town: an armed shape keeps its arms free of reserves; round 5 drew town 9 linear)
	local s = F.style({ forceStyle = "EU_ORGANIC", townId = 9, pos = { 0, 0 }, year = 2000, capacity = 6000,
		nameList = "::/names/europe/europe.names", shape = "compact" }, F.flat)
	eq(#s.greens, ST.GREEN_STYLES.EU_ORGANIC)
	for _, gr in ipairs(s.greens) do ok(gr[3] >= ST.GREEN_MIN and gr[3] <= ST.GREEN_MAX) end
	eq(#base("NA_GRID", "US").greens, 0, "strict grids fill every block")
	local m = MET.apply(base("NA_GRID", "US"), { variant = "grid" }, { cap = 6000 })
	eq(#m.greens, MET.PARKS, "a metropolis gets parks")
	F.withGreen(function()
		local g = OG.new()
		local stats = nil
		for k = 1, 20 do
			local inc = core.planIncrement(g, s, { terrain = F.flat, join = "any" })
			if #inc.edges == 0 then break end
			OG.apply(g, inc, k)
		end
		ok(#g.edges > 100, "grows: " .. #g.edges)
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			for _, gr in ipairs(s.greens) do
				ok(math.sqrt((mx - gr[1]) ^ 2 + (my - gr[2]) ^ 2) >= gr[3] - 1, "no street midpoint inside a reserve")
			end
		end
		local gg = MT.greenGaps(g, F.houses and {} or {})
		print(string.format("      EU organic, 20 increments, %d reserves: green %s", #s.greens, MT.greenText(gg)))
		ok(SEL.inGreen(s, { { s.greens[1][1], s.greens[1][2] }, { s.greens[1][1] + 1, s.greens[1][2] } }))
	end)
	ok(not SEL.inGreen(s, { { s.greens[1][1], s.greens[1][2] }, { s.greens[1][1] + 1, s.greens[1][2] } }), "off outside withGreen")
end)

test("metropolis on a flat valley / river floor in hilly country: a corridor (not why=site), 2026-10-13", function()
	local MT2 = ug_require(F.DIR .. "ot_metro.lua")
	local SITE2 = ug_require(F.DIR .. "ot_site.lua")
	-- Bexley (session 2026-10-13_0018_top-up-598153): slope 0.02, 2 km spread 82 m, a river; 4164 persons
	local f = SITE2.features({ meanSlope = 0.02, waterFraction = 0.05, water = { kind = "river", body = "river", distance = 375 } },
		{ sd = 82, water = 0.27 })
	eq(f.kind, "river")
	local on, site = 0, 0
	for seed = 1, 200 do
		local d, why = MT2.decide({ styleId = "EU_ORGANIC", cap = 4200, features = f, region = "EU", year = 1930, seed = seed })
		if d then
			on = on + 1
			eq(d.variant, "corridor")
			ok(d.why:find("floor=", 1, true), d.why)
		elseif why == "site" then site = site + 1 end
	end
	eq(site, 0)
	ok(on >= 25 and on <= 75, "a seeded share: " .. on .. " / 200")
	-- a steep town in the same hills stays why=site
	local st = SITE2.features({ meanSlope = 0.12, waterFraction = 0, water = { kind = "river", body = "river", distance = 300 } },
		{ sd = 82, water = 0.05 })
	local _, why = MT2.decide({ styleId = "EU_ORGANIC", cap = 4200, features = st, region = "EU", year = 1930, seed = 3 })
	eq(why, "site")
end)
