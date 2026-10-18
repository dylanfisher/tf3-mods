-- Forest-aware towns (phase F, 2026-10-13; PLAN.md 6.3 "Forest"): a coarse tree grid per town (ot_forest), a seeded
-- mode per town (hug: early, small, organic, character towns; clear: later, bigger, grid, metropolis) and, for hug
-- towns, dense forest as a soft barrier in the planner (cost, hold, edge premium) and dose points on the open side.
-- Synthetic forests only: the in-game tree read (ot_engine.forestReader) is checked in TESTING.md.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

-- forests (trees per hectare at a point)
local DENSE = 200
--- Forest everywhere beyond the core (r 260) except two clearings 2 x hw wide along the x and y axes (a cross: the
--- town's fingers should run out along them).
local function crossOf(hw)
	return function(x, y)
		if x * x + y * y < 260 * 260 then return 0 end
		if math.abs(x) < hw or math.abs(y) < hw then return 0 end
		return DENSE
	end
end
local crossForest = crossOf(80)
--- Forest all round beyond r 300 (a town boxed in by forest).
local function ringForest(x, y)
	if x * x + y * y < 300 * 300 then return 0 end
	return DENSE
end
--- Forest on the east half (x > 150) only: an edge running north-south.
local function eastForest(x, _y)
	if x > 150 then return DENSE end
	return 0
end

local function info(fn, mode)
	local fg = FO.fromFunction(0, 0, fn, 1200, 50)
	return { grid = fg, mode = mode or "hug", share = fg.share }
end

--- n increments of 18 edges from a round core (houses after each), the style forced, forest info `fo` (or nil).
--- Returns the new streets as segments, the graph and the style.
local function grow(styleId, fo, n, raw)
	local r = { forceStyle = styleId, townId = 11, year = 1960, nameList = "::/names/germany/germany.names" }
	for k, v in pairs(raw or {}) do r[k] = v end
	local style, stats = F.style(r, F.flat)
	style.forest = fo
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local segs = {}
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
		if #inc.edges == 0 then break end
		for _, e in ipairs(inc.edges) do segs[#segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2], key = e.key } end
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return segs, g, style
end

local function length(segs)
	local t = 0
	for _, s in ipairs(segs) do t = t + G.dist(s[1], s[2], s[3], s[4]) end
	return t
end

test("grid: density -> cover, smoothing, share, pen, edge, cut share", function()
	local fg = FO.newGrid(0, 0, 500, 50)
	eq(fg.n, 20)
	ok(FO.addTree(fg, 10, 10, 3), "inside")
	ok(not FO.addTree(fg, 900, 0, 1), "outside ignored")
	eq(fg.total, 3)
	FO.finish(fg)
	-- 3 trees in 0.25 ha = 12 / ha: below LIGHT_HA, no cover
	eq(FO.cover(fg, 10, 10), 0)
	local e = info(eastForest, "hug")
	near(FO.cover(e.grid, 600, 0), 1, 1e-9, "deep forest")
	eq(FO.cover(e.grid, -400, 0), 0, "open land")
	ok(FO.cover(e.grid, 160, 0) > 0.4 and FO.cover(e.grid, 160, 0) < 1, "edge cell smoothed")
	ok(e.share > 0.3 and e.share < 0.6, "share east of 150 m within 1 km: " .. e.share)
	near(FO.pen(e, { { 400, 0 }, { 600, 0 } }), 1, 1e-6)
	eq(FO.pen(e, { { -400, 0 }, { -200, 0 } }), 0)
	ok(FO.edge(e, 110, 0) > 0.5, "open point beside the forest: edge")
	eq(FO.edge(e, -300, 0), 0, "open point far from it")
	eq(FO.edge(e, 500, 0), 0, "inside the forest: no edge")
	near(FO.cutShare(e, { { -200, 0, 0, 0 }, { 400, 0, 600, 0 } }), 0.5, 1e-6)
	eq(FO.cutShare(nil, {}), nil)
	-- open side: a point in the forest swaps to the other side of the street when that is open
	local x, y = FO.openSide(e, 600, 0, -400, 0)
	eq(x, -400)
	x = FO.openSide(e, -400, 0, 600, 0)
	eq(x, -400, "an open point stays")
	x = FO.openSide(info(eastForest, "clear"), 600, 0, -400, 0)
	eq(x, 600, "clear towns: unchanged")
	eq(FO.text(e), string.format("%.2f:hug", e.share))
	eq(FO.text(nil), "-")
end)

test("mode: early / small / organic / character towns hug, late / big / grid / metropolis clear", function()
	local fg = FO.fromFunction(0, 0, eastForest, 1200, 50)
	local function hugShare(styleId, year, tier, character, metro)
		local n, hug = 0, 0
		for town = 1, 200 do
			local style = { id = styleId, year = year, tier = tier, seed = town * 7919,
				form = character and { character = true } or nil, metro = metro and { variant = "grid" } or nil }
			local fo = FO.forStyle(fg, style)
			n = n + 1
			if fo.mode == "hug" then hug = hug + 1 end
		end
		return hug / n
	end
	local early = hugShare("EU_ORGANIC", 1900, 2)
	local late = hugShare("EU_ORGANIC", 2010, 2)
	local big = hugShare("EU_ORGANIC", 1900, 4)
	local grid = hugShare("NA_GRID", 1900, 2)
	local nordic = hugShare("NORDIC", 1950, 2)
	local ch = hugShare("EU_ORGANIC", 1960, 3, true)
	local plain = hugShare("EU_ORGANIC", 1960, 3)
	print(string.format("      hug share: EU 1900 t2 %.2f, 2010 %.2f, 1900 t4 %.2f, NA grid %.2f, Nordic 1950 %.2f, 1960 t3 %.2f / character %.2f",
		early, late, big, grid, nordic, plain, ch))
	ok(early > 0.8, "early small organic towns mostly hug")
	ok(late < 0.5, "late ones mostly clear")
	ok(late < early - 0.35, "clearly fewer than early")
	ok(big < 0.4, "big towns mostly clear")
	ok(grid < 0.2, "grid towns clear")
	ok(ch > plain + 0.05, "character towns hug more")
	eq(hugShare("EU_ORGANIC", 1900, 1, false, true), 0, "a metropolis always clears")
	-- the era only lowers the chance: a town that hugs late also hugged early (never clear -> hug)
	for town = 1, 100 do
		local s1 = { id = "EU_ORGANIC", year = 1990, tier = 2, seed = town }
		local s0 = { id = "EU_ORGANIC", year = 1905, tier = 2, seed = town }
		if FO.forStyle(fg, s1).mode == "hug" then eq(FO.forStyle(fg, s0).mode, "hug", "town " .. town) end
	end
	-- too little forest: none
	local sparse = FO.fromFunction(0, 0, function(x, y) return (x > 900 and y > 900) and DENSE or 0 end, 1200, 50)
	eq(FO.forStyle(sparse, { id = "EU_ORGANIC", year = 1900, tier = 1, seed = 3 }).mode, "none")
	eq(FO.forStyle(nil, { id = "EU_ORGANIC" }), nil)
	-- the era curve (2026-10-15 §59): early boost to 1910 (back to 1 by 1930), full to 1950, about 0.5 by 1990
	near(FO.eraF(1900), FO.EARLY_F, 1e-9)
	near(FO.eraF(1920), 1 + (FO.EARLY_F - 1) * 0.5, 1e-9)
	near(FO.eraF(1930), 1, 1e-9)
	near(FO.eraF(1950), 1, 1e-9)
	near(FO.eraF(1970), 1 + (FO.ERA_LATE - 1) * 0.5, 1e-9)
	near(FO.eraF(2020), FO.ERA_LATE, 1e-9)
	ok(FO.EARLY_F > 1 and FO.EARLY_F <= 1.25, "early towns slightly higher")
	ok(FO.ERA_LATE >= 0.4 and FO.ERA_LATE <= 0.6, "about 0.5 by 1990")
	local prev = math.huge
	for y = 1850, 2100, 5 do
		ok(FO.eraF(y) <= prev + 1e-12, "never rises with the year: " .. y)
		prev = FO.eraF(y)
	end
	-- deep: full chance to 1960, then a gentler fall
	near(FO.deepEraF(1960), 1, 1e-9)
	ok(FO.deepEraF(1990) > 0.6, "deep forest still likely in 1990")
	near(FO.deepEraF(2050), FO.DEEP_ERA_LATE, 1e-9)
end)

-- the seed `a` replay (2026-10-15 §59): the 16 towns of the test map, their positions and the styles the game resolved
-- at a 1900 start (session 2026-10-14_2237_sqot-dev load 2; the same as 2026-10-14_1927_sqot load 1) and a 1950 start
-- (2026-10-14_2347_sqot-dev load 3, 2026-10-15_0234_sqot-dev load 2): id, x, y, style 1900, character 1900, mode 1900,
-- style 1950, character 1950, mode 1950 (as the game logged them with the earlier odds: ERA 1920 / 1980 / 0.25, deep
-- 1930 / 1990 / 0.35). The seeds come from the town id and position as in ot_style.resolve, so the draws are the game's.
local rng = ug_require(F.DIR .. "ot_rng.lua")
local SEED_A = {
	{ 60255, -2012, -2748, "JP_DENSE", false, "clear", "MED_HILL", false, "clear" },
	{ 60256, -1696, 44, "EU_ORGANIC", false, "hug", "EU_EXTENSION", false, "clear" },
	{ 60257, -5500, -5320, "EU_EXTENSION", false, "clear", "NORDIC", true, "hug" },
	{ 60258, -7256, 4896, "EU_ORGANIC", false, "hug", "EU_EXTENSION", false, "clear" },
	{ 60259, 2804, 144, "MED_HILL", false, "hug", "SUPERBLOCK", false, "clear" },
	{ 60260, 364, 2640, "MED_HILL", false, "clear", "NA_GRID", false, "clear" },
	{ 60261, -3968, 2568, "EU_ORGANIC", false, "hug", "EU_EXTENSION", false, "hug" },
	{ 60262, 1436, 6640, "EU_ORGANIC", true, "hug", "EU_EXTENSION", false, "clear" },
	{ 60263, 4340, 3204, "NORDIC", false, "hug", "NA_GRID", false, "clear" },
	{ 60264, -2412, 7324, "EU_ORGANIC", false, "clear", "EU_ORGANIC", false, "clear" },
	{ 60265, 4280, -6416, "NA_GRID", false, "clear", "MED_ENSANCHE", false, "clear" },
	{ 60266, 7124, -616, "EU_ORGANIC", false, "hug", "EU_ORGANIC", false, "clear" },
	{ 60267, 5516, -3240, "EU_ORGANIC", false, "hug", "EU_ORGANIC", false, "hug" },
	{ 60268, 5004, 6388, "EU_ORGANIC", false, "hug", "NA_SUBURB", false, "clear" },
	{ 60269, 1780, -3508, "EU_ORGANIC", false, "clear", "NA_SUBURB", false, "clear" },
	-- (the one town whose ring passes the deep share test: ring 0.48, tier 1 at both starts)
	{ 60270, 724, -6788, "EU_ORGANIC", true, "deep", "EU_ORGANIC", true, "clear", deepTier = 1 },
}

--- Modes of the seed `a` towns at a start year: { hug, clear, deep, modes = { [id] = mode } }.
local function seedA(year, era1950)
	local out = { hug = 0, clear = 0, deep = 0, modes = {} }
	for _, t in ipairs(SEED_A) do
		local id, ch = t[4], t[5]
		if era1950 then id, ch = t[7], t[8] end
		local style = { id = id, year = year, tier = t.deepTier or 2, seed = rng.seed(t[1], t[2], t[3]),
			form = ch and { character = true } or nil }
		local mode
		if t.deepTier and rng.unit(style.seed, "forestDeep") < FO.deepChance(style) then mode = "deep"
		else mode = (rng.unit(style.seed, "forestMode") < FO.chance(style)) and "hug" or "clear" end
		out[mode] = out[mode] + 1
		out.modes[t[1]] = mode
	end
	return out
end

test("seed a replay: early towns weave through more, a 1950 map keeps hugging and deep forest, clearing stays modern", function()
	-- the replay reproduces the game's draws with the earlier odds
	local keep = { FO.ERA, FO.ERA_LATE, FO.EARLY, FO.DEEP_ERA, FO.DEEP_ERA_LATE }
	-- (and the EU extension odds before the 2026-10-15 raise to 0.62)
	local keepExt = FO.STYLE_P.EU_EXTENSION
	FO.ERA, FO.ERA_LATE, FO.EARLY, FO.DEEP_ERA, FO.DEEP_ERA_LATE = { 1920, 1980 }, 0.25, nil, { 1930, 1990 }, 0.35
	FO.STYLE_P.EU_EXTENSION = 0.45
	local old1900, old1950 = seedA(1900), seedA(1950, true)
	FO.ERA, FO.ERA_LATE, FO.EARLY, FO.DEEP_ERA, FO.DEEP_ERA_LATE = keep[1], keep[2], keep[3], keep[4], keep[5]
	FO.STYLE_P.EU_EXTENSION = keepExt
	for _, t in ipairs(SEED_A) do
		eq(old1900.modes[t[1]], t[6], "1900 town " .. t[1])
		eq(old1950.modes[t[1]], t[9], "1950 town " .. t[1])
	end
	local n1900, n1950 = seedA(1900), seedA(1950, true)
	-- (a modern map: the 1950 styles at 2020)
	local n2020 = seedA(2020, true)
	print(string.format("      seed a: 1900 hug/clear/deep %d/%d/%d -> %d/%d/%d; 1950 %d/%d/%d -> %d/%d/%d; 2020 %d/%d/%d",
		old1900.hug, old1900.clear, old1900.deep, n1900.hug, n1900.clear, n1900.deep, old1950.hug, old1950.clear,
		old1950.deep, n1950.hug, n1950.clear, n1950.deep, n2020.hug, n2020.clear, n2020.deep))
	ok(n1900.hug >= 10 and n1900.hug <= 12, "1900: 10-12 hug of 16")
	ok(n1900.hug > old1900.hug, "early towns weave through more")
	ok(n1950.hug + n1950.deep > old1950.hug + old1950.deep, "1950: more forest towns than before")
	eq(n1950.deep, 1, "deep forest still possible at 1950")
	ok(n1950.hug >= 6, "1950: at least 6 hug (EU extension 0.62)")
	ok(n2020.clear > n2020.hug + n2020.deep, "modern maps: clearing more common")
	-- a town that hugged before still hugs (the curve only rose)
	for _, t in ipairs(SEED_A) do
		if old1900.modes[t[1]] == "hug" then ok(n1900.modes[t[1]] ~= "clear", "1900 town " .. t[1] .. " keeps the forest") end
		if old1950.modes[t[1]] == "hug" then ok(n1950.modes[t[1]] ~= "clear", "1950 town " .. t[1] .. " keeps the forest") end
	end
end)

test("no forest or a clearing town: the plan is identical to before", function()
	for _, id in ipairs({ "EU_ORGANIC", "NA_GRID" }) do
		local a = grow(id, nil, 4)
		local b = grow(id, info(crossForest, "clear"), 4)
		local c = grow(id, info(crossForest, "none"), 4)
		eq(#a, #b, id .. " edge count (clear)")
		eq(#a, #c, id .. " edge count (none)")
		for i = 1, #a do
			eq(a[i].key, b[i].key, id .. " edge " .. i)
			eq(a[i].key, c[i].key, id .. " edge " .. i)
		end
	end
end)

-- a forest with a cross of clearings beyond the core: hug towns keep out of the forest and run out along the
-- clearings (fingers); 6 town seeds per style. WANT: the hug town's forestCut at most this share of the clear town's;
-- GROW: its street length at least this share of the clear town's (once the open land is used up a hug town takes
-- wooded pieces only up to FO.CUT_FILL of an increment: it grows slower, the grids most). Nordic's cluster cells
-- (~230 m) can't thread 160 m clearings: it gets 440 m wide ones (on the 160 m cross: cut 0.63 vs 0.71).
local SEEDS = { 21, 22, 23, 24, 25, 26 }
local WANT = { EU_ORGANIC = 0.5, NORDIC = 0.65, MED_HILL = 0.5, JP_DENSE = 0.5, NA_GRID = 0.5 }
local GROW = { EU_ORGANIC = 0.65, NORDIC = 0.8, MED_HILL = 0.65, JP_DENSE = 0.6, NA_GRID = 0.5 }
local CROSS = { NORDIC = crossOf(220) }
for _, id in ipairs({ "EU_ORGANIC", "NORDIC", "MED_HILL", "JP_DENSE", "NA_GRID" }) do
	test("cross of clearings: a hugging " .. id .. " cuts little forest and grows along the clearings", function()
		local r = { hc = 0, cc = 0, hl = 0, cl = 0, hReach = 0, cReach = 0 }
		local fx = CROSS[id] or crossForest
		local hug, clear = info(fx, "hug"), info(fx, "clear")
		local n = #SEEDS
		for _, town in ipairs(SEEDS) do
			local raw = { townId = town }
			local h = grow(id, hug, 8, raw)
			local c = grow(id, clear, 8, raw)
			r.hc = r.hc + (FO.cutShare(hug, h) or 0) / n
			r.cc = r.cc + (FO.cutShare(hug, c) or 0) / n
			r.hl, r.cl = r.hl + length(h) / n, r.cl + length(c) / n
			-- reach: the farthest new street midpoint from the centre (fingers reach out)
			local function reach(segs)
				local best = 0
				for _, s in ipairs(segs) do best = math.max(best, G.dist(0, 0, (s[1] + s[3]) / 2, (s[2] + s[4]) / 2)) end
				return best
			end
			r.hReach, r.cReach = r.hReach + reach(h) / n, r.cReach + reach(c) / n
		end
		print(string.format("      forestCut: hug %.2f clear %.2f | length hug %.0f clear %.0f m | reach hug %.0f clear %.0f m",
			r.hc, r.cc, r.hl, r.cl, r.hReach, r.cReach))
		ok(r.hc <= r.cc * WANT[id] + 0.02, id .. ": hug cuts less forest: " .. r.hc .. " vs " .. r.cc)
		ok(r.hl >= r.cl * GROW[id], id .. ": the hug town still grows: " .. r.hl .. " vs " .. r.cl)
		-- fingers: the hug town reaches about as far out (along the clearings) though it builds less
		ok(r.hReach >= 0.9 * r.cReach, id .. ": reaches out along the clearings: " .. r.hReach .. " vs " .. r.cReach)
	end)
end

-- (slower: wooded pieces fill at most FO.CUT_FILL of an increment, so ~half the edges per increment; in game the demand
-- trigger builds again sooner)
test("boxed in by forest: a hugging town still grows (the held pieces come back)", function()
	for _, id in ipairs({ "EU_ORGANIC", "NA_GRID", "NORDIC" }) do
		local base = grow(id, nil, 6)
		local boxed = grow(id, info(ringForest, "hug"), 6)
		print(string.format("      %-10s boxed: %d edges / %.0f m (no forest: %d / %.0f m)", id, #boxed, length(boxed),
			#base, length(base)))
		-- (R4 2026-10-13: the open town grows ~10 % more with the organic empty-loop rule, so 0.45 -> 0.42)
		ok(#boxed >= 0.42 * #base and length(boxed) >= 0.42 * length(base), id .. ": boxed-in town grows")
		-- every increment adds streets (never an empty plan while the forest holds)
		ok(#boxed >= 6 * 6, id .. ": at least 6 edges per increment")
	end
end)

test("forest edge: a hugging town's streets run along the edge, not into the forest", function()
	local hug, clear = info(eastForest, "hug"), info(eastForest, "clear")
	local hEast, cEast, n = 0, 0, 0
	for _, town in ipairs(SEEDS) do
		local h = grow("EU_ORGANIC", hug, 8, { townId = town })
		local c = grow("EU_ORGANIC", clear, 8, { townId = town })
		hEast, cEast, n = hEast + (FO.cutShare(hug, h) or 0), cEast + (FO.cutShare(hug, c) or 0), n + 1
	end
	print(string.format("      east forest: cut hug %.2f clear %.2f", hEast / n, cEast / n))
	ok(hEast / n < cEast / n * 0.5, "hug keeps out of the forest half")
end)

test("dose points of a hugging town go to the open side of an edge street", function()
	-- a street along the forest edge (x = 140, north-south): its east side is forest
	local edges = {}
	for k = 0, 4 do edges[#edges + 1] = { p0 = { 140, -200 + 90 * k }, p1 = { 140, -200 + 90 * k + 80 } } end
	local hug = info(eastForest, "hug")
	local pts = D.fillPoints("metro", edges, nil, nil, nil, { forest = hug })
	ok(#pts > 0, "points")
	for _, p in ipairs(pts) do ok(FO.cover(hug.grid, p[1], p[2]) < FO.FOREST_COVER, "metro point on the open side") end
	local cl = D.fillPoints("metro", edges, nil, nil, nil, { forest = info(eastForest, "clear") })
	local east = 0
	for _, p in ipairs(cl) do if p[1] > 150 then east = east + 1 end end
	ok(east > 0, "clear towns keep both sides")
end)

test("driver: PLAN forestCut / STYLE forest texts", function()
	local hug = info(eastForest, "hug")
	local inc = { edges = { { p0 = { -200, 0 }, p1 = { 0, 0 } }, { p0 = { 400, 0 }, p1 = { 600, 0 } } } }
	eq(D.forestCutText(inc, { forest = hug }), "0.50")
	eq(D.forestCutText(inc, {}), "-")
	eq(D.forestText({ forest = hug }), string.format("%.2f:hug", hug.share))
end)

test("driver: the forest stage reads trees through the engine reader, slices, and lands on the stats", function()
	-- a fake reader: 3 slices, trees on the east half
	local steps = 0
	local E = {
		nowUs = function() return 0 end, name = function() return "T" end,
		forestReader = function(cx, cy, r, o)
			return { stats = { groups = 2, reads = 10, trees = 0, nonTree = 0, stride = 1, capped = false, listUs = 0 },
				step = function(self)
					steps = steps + 1
					if steps < 3 then return false end
					for x = 200, 1000, 10 do for y = -1000, 1000, 10 do o.add(x, y, 1); self.stats.trees = self.stats.trees + 1 end end
					return true
				end }
		end,
	}
	local d = D.new(E, "[T]")
	d.debug = function() end
	local s = d:townState(5)
	s.pos, s.stats = { 0, 0 }, {}
	eq(d:afterTerrain(5, 0), "forest")
	local job = { town = 5, stage = "forest", ext = { cx = 0, cy = 0 } }
	d:forest(job, 0)
	d:forest(job, 0)
	eq(job.stage, "forest", "still reading")
	d:forest(job, 0)
	eq(job.stage, "snapshot")
	ok(s.forest and s.forest.done, "grid on the town state")
	eq(s.stats.forest, s.forest, "and on the stats")
	ok(s.forest.share > 0.3, "east half forest: " .. s.forest.share)
	eq(d:afterTerrain(5, 0), "snapshot", "fresh grid: no new read")
	eq(d:afterTerrain(5, (FO.RENEW_S + 1) * 1e6), "forest", "renewed after RENEW_S")
	-- an engine without the reader (offline / older engine layer): no forest stage
	local d2 = D.new({ nowUs = function() return 0 end }, "[T]")
	d2:townState(5)
	eq(d2:afterTerrain(5, 0), "snapshot")
end)

test("engine: forestReader lists asset groups, samples tree instances with a stride, skips other models", function()
	local function vec(list)
		return { size = function() return #list end, at = function(_, i) return list[i] end }
	end
	-- group 101: 1000 thin trees on the east half; group 102: 4 fat rocks; group 103: dynamic (skipped)
	local thin = {}
	for k = 1, 1000 do thin[k] = { modelId = 1, pos = { x = 200 + (k % 40) * 10, y = -200 + math.floor(k / 40) * 10 } } end
	local fat = {}
	for k = 1, 4 do fat[k] = { modelId = 2, transf = { getTransl = function() return { x = -300, y = 0 } end } } end
	local comps = {
		[101] = { MIL = { fatInstances_native = vec({}), thinInstances_native = vec(thin) } },
		[102] = { MIL = { fatInstances_native = vec(fat), thinInstances_native = vec({}) } },
		[103] = { MIL = { dynamic = true, fatInstances_native = vec({}), thinInstances_native = vec(thin) } },
	}
	local radius
	set_global("api", {
		type = { ComponentType = { ASSET_GROUP = "AG", MODEL_INSTANCE_LIST = "MIL" },
			Vec2f = { new = function(x, y) return { x = x, y = y } end } },
		engine = {
			util = { octree = { findEntitiesInCircle = function(_, r, ct)
				radius = r
				eq(ct, "AG")
				return { 101, 102, 103 }
			end } },
			getComponent = function(e, ct) return comps[e] and comps[e][ct] end,
		},
		res = { modelRep = { get = function(id) return { metadata = { tree = id == 1 and { reputationFactor = 1 } or nil } } end } },
	})
	local E = ug_require(F.DIR .. "ot_engine.lua")
	local fg = FO.newGrid(0, 0, 1000, 50)
	local rd = E.forestReader(0, 0, 1400, { readMax = 300, add = function(x, y, w) FO.addTree(fg, x, y, w) end })
	eq(rd:step(1e9), false, "first step: the octree list")
	eq(radius, 1400)
	local n = 0
	while not rd:step(1e9) do n = n + 1; ok(n < 10, "finishes") end
	local st = rd.stats
	eq(st.groups, 3)
	eq(st.stride, 10, "1000 instances with 100 reads per group: stride 10")
	ok(st.capped, "sampled")
	near(st.trees, 1000, 10, "weighted trees ~ all of group 101")
	eq(st.nonTree, 4, "the rocks read, not counted")
	FO.finish(fg)
	ok(FO.cover(fg, 300, -100) > 0.5, "the trees' cells are wooded")
	eq(FO.cover(fg, -300, 0), 0, "rocks are no forest")
	-- a big group resumes over slices (audit 2026-10-13: one group read up to readMax instances in one slice): with no
	-- time per slice every READ_CHECK reads end the slice, and the next one goes on where it stopped
	local big = {}
	for k = 1, 3000 do big[k] = { modelId = 1, pos = { x = (k % 50) * 10, y = math.floor(k / 50) * 10 } } end
	comps[104] = { MIL = { fatInstances_native = vec({}), thinInstances_native = vec(big) } }
	local api0 = api
	api0.engine.util.octree.findEntitiesInCircle = function() return { 104 } end
	local rd3 = E.forestReader(0, 0, 1400, { readMax = 30000 })
	rd3:step(0)
	local slices = 0
	while not rd3:step(0) do slices = slices + 1; ok(slices < 100, "finishes") end
	ok(slices >= math.floor(3000 / E.READ_CHECK) - 1, "sliced within the group: " .. slices)
	eq(rd3.stats.trees, 3000, "every instance read once")
	-- no ASSET_GROUP type: an empty read with an error
	set_global("api", { type = { ComponentType = {} } })
	local rd2 = E.forestReader(0, 0, 100, { readMax = 10 })
	rd2:step(1)
	ok(rd2:step(1), "done")
	eq(rd2.stats.err, "noAssetGroupType")
	set_global("api", nil)
end)

test("grid: calibrated on the in-game read (final test: forest cells p50 24, p90 60 trees/ha at stride 2-3)", function()
	-- a wooded half (x > 0: ~40 trees/ha, as the read's p50-p90 cells) and a meadow with scattered trees (~4 / ha), read
	-- at stride 3 (each sampled tree counts 3)
	local function build()
		local fg = FO.newGrid(0, 0, 1500, 50)
		local seed = 12345
		local function rnd()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		for _ = 1, 30000 do
			local x, y = (rnd() * 2 - 1) * 1500, (rnd() * 2 - 1) * 1500
			-- (30000 candidates over 900 ha: 33.3 / ha; sampled trees 40 / 3 per ha in the wood, 4 / 3 in the meadow)
			local p = x > 0 and (40 / 3) / 33.3 or (4 / 3) / 33.3
			local keep = rnd() < p
			if keep then FO.addTree(fg, x, y, 3) end
		end
		fg.stride = 3
		return FO.finish(fg)
	end
	local fg = build()
	print(string.format("      wooded half: share %.2f, p50 %.0f, p90 %.0f, cover in the wood %.2f, in the meadow %.2f", fg.share,
		fg.p50 or 0, fg.p90 or 0, FO.cover(fg, 700, 300), FO.cover(fg, -700, 300)))
	ok(fg.share >= 0.35 and fg.share <= 0.6, "the wooded half reads as forest: share " .. fg.share)
	ok(FO.cover(fg, 700, 300) >= 0.5, "wooded cell " .. FO.cover(fg, 700, 300))
	ok(FO.cover(fg, -700, 300) < 0.2, "meadow")
	-- the old thresholds (25 / 90 trees/ha) read that map as almost no forest (the final test: shares 0.01-0.08)
	local l, d = FO.LIGHT_HA, FO.DENSE_HA
	FO.LIGHT_HA, FO.DENSE_HA = 25, 90
	local old = build()
	FO.LIGHT_HA, FO.DENSE_HA = l, d
	print(string.format("      old thresholds 25 / 90: share %.2f", old.share))
	ok(old.share < 0.15, "old calibration: share " .. old.share)
	-- a lone sampled tree (stride 3) is open land
	local one = FO.newGrid(0, 0, 500, 50)
	FO.addTree(one, 10, 10, 3)
	one.stride = 3
	FO.finish(one)
	eq(FO.cover(one, 10, 10), 0)
end)

-- Round R1 (2026-10-13, run 2026-10-13_1945_sqot-dev): forest by plot depth, the metre cap + clearing budget, the
-- stride bias, re-reads after builds.
test("R1 corridor: lots to 36 m per side, edge premium only one lot depth off the trees", function()
	local e = info(eastForest, "hug")
	-- a street one lot depth off the forest (x = 100, forest from 150): lots open, forest just beyond on the east side
	local far = FO.corridor(e, { { 100, -200 }, { 100, 0 } })
	ok(far.l < FO.EDGE_OPEN and far.r < FO.EDGE_OPEN, "lots open: " .. far.l .. " / " .. far.r)
	ok(FO.edgeOf(far) > 0.4, "edge street: " .. FO.edgeOf(far))
	-- a street right at the edge (x = 140): the east lots reach into the trees: no premium, dearer, not held
	local at = FO.corridor(e, { { 140, -200 }, { 140, 0 } })
	eq(FO.edgeOf(at), 0, "lots in the trees: no edge premium")
	ok(math.max(at.l, at.r) > 0.5, "one side wooded to lot depth")
	local pen = FO.corridorPen(at)
	ok(pen > 0.2 and pen < FO.HOLD_PEN, "one side wooded: dearer, not held: " .. pen)
	ok(at.lotHa > 0.3, "forest under the lots: " .. at.lotHa .. " ha")
	-- through the forest: both sides wooded, held
	local deep = FO.corridor(e, { { 500, -200 }, { 500, 0 } })
	ok(FO.corridorPen(deep) >= FO.HOLD_PEN, "deep forest held")
	near(deep.lotHa, 200 * 2 * FO.LOT_DEPTH / 10000, 0.05, "lot hectares: length x 2 sides x depth")
	-- the old centreline pen saw the x = 140 street as open
	ok(FO.pen(e, { { 140, -200 }, { 140, 0 } }) < 0.5, "centreline alone")
	-- dose at lot depth: a point 20 m east of x = 125 (145) is open but its lot (161) is wooded -> the west side
	local x = FO.openSide(e, 145, 0, 105, 0)
	eq(x, 105, "the dose goes to the side open to lot depth")
	-- degenerate input: zero-length / NaN segments count as open
	local z = FO.corridor(e, { { 0 / 0, 0 }, { 1, 1 } })
	eq(z.len, 0)
end)

test("R1 clearing budget: per town and decade, text", function()
	local ts = {}
	local b = FO.budgetFor(ts, 1913, 2)
	eq(b.total, FO.BUDGET_HA[2])
	b.used = 1
	eq(FO.budgetFor(ts, 1919, 2), b, "same decade")
	eq(FO.budgetText(b), string.format("%.1f/%.1f", FO.BUDGET_HA[2] - 1, FO.BUDGET_HA[2]))
	local b2 = FO.budgetFor(ts, 1920, 2)
	eq(b2.used, 0, "a new decade resets")
	eq(FO.budgetText(nil), "-")
end)

test("R1 metre cap: with the budget spent a boxed-in town's wooded metres per increment stay near CUT_MIN_M", function()
	local function run(budget)
		local fo = info(ringForest, "hug")
		fo.budget = budget
		local r = { forceStyle = "EU_ORGANIC", townId = 11, year = 1960, nameList = "::/names/germany/germany.names" }
		local style, stats = F.style(r, F.flat)
		style.forest = fo
		local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
		F.markBuilt(g, 120)
		local worst, total, n = 0, 0, 0
		for k = 1, 8 do
			local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
			if #inc.edges == 0 then break end
			local segs = {}
			for _, e in ipairs(inc.edges) do segs[#segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2] } end
			-- (the held pieces' wooded length: corridor pen at HOLD_PEN or more)
			local wood = 0
			for _, e in ipairs(inc.edges) do
				local co = FO.corridor(fo, { e.p0, e.p1 })
				if FO.corridorPen(co) >= FO.HOLD_PEN then wood = wood + co.woodM end
			end
			if k > 2 then worst = math.max(worst, wood) end
			total, n = total + #inc.edges, n + 1
			OG.apply(g, inc, k)
			F.markBuilt(g, 120 + 70 * k)
		end
		return worst, total, n
	end
	local wFree, eFree = run(nil)
	local wSpent, eSpent, nSpent = run({ total = 0, used = 0 })
	print(string.format("      boxed: most wooded m per increment (inc 3+) unlimited %.0f, budget spent %.0f; edges %d vs %d", wFree,
		wSpent, eFree, eSpent))
	ok(wSpent <= FO.CUT_MIN_M + 120, "wooded metres capped once the budget is spent: " .. wSpent)
	ok(wSpent < wFree, "less than with budget left")
	ok(eSpent <= eFree, "the spent budget slows the town")
	ok(nSpent >= 1, "it still plans")
end)

test("R1 stride bias: a stride-5 read keeps the 12 / 36 thresholds; only a lone sampled tree reads open", function()
	local fg = FO.newGrid(0, 0, 500, 50)
	-- 3 sampled trees at stride 5 in one cell: 60 trees/ha -> forest (the old rule made light 30 / dense 60: 1.0 too,
	-- but 2 samples (40 / ha) read 0.33 then, now 1)
	for _ = 1, 2 do FO.addTree(fg, 10, 10, 5) end
	FO.addTree(fg, 210, 10, 5)
	fg.stride = 5
	FO.finish(fg)
	local raw2 = fg.cover[math.floor((10 - fg.x0) / 50) * fg.n + math.floor((10 - fg.y0) / 50) + 1]
	ok(raw2 and raw2 >= 0.5, "two sampled trees at stride 5 (40 / ha): wooded (smoothed " .. tostring(raw2) .. ")")
	eq(FO.cover(fg, 210, 10), 0, "a lone sampled tree: open")
end)

test("R1 driver: the tree grid is read again after RENEW_BUILDS builds or RENEW_EDGES edges", function()
	local d = D.new({ nowUs = function() return 0 end, forestReader = function() end }, "[T]")
	local s = d:townState(7)
	s.forest, s.forestUs = { done = true }, 0
	eq(d:afterTerrain(7, 0), "snapshot")
	s.forestBuilds = FO.RENEW_BUILDS
	eq(d:afterTerrain(7, 0), "forest", "after builds")
	s.forestBuilds, s.forestEdges = 0, FO.RENEW_EDGES
	eq(d:afterTerrain(7, 0), "forest", "after edges")
end)

test("R1 driver: PLAN forestLot / forestBudget", function()
	local hug = info(eastForest, "hug")
	hug.budget = { total = 3, used = 0 }
	local inc = { edges = { { p0 = { 500, -100 }, p1 = { 500, 100 } } } }
	local lot = D.forestLot(inc, { forest = hug })
	ok(lot > 1 and lot < 1.6, "200 m through forest: ~1.44 ha under lots: " .. lot)
	-- (round after the names run: the text shows what is left once built; spent at the build, forestBudgetCommit)
	eq(D.forestBudgetSpend(inc, { forest = hug }), string.format("%.1f/%.1f:-", 3 - lot, 3))
	eq(hug.budget.used, 0, "not spent at the plan")
	D.forestBudgetCommit({ style = { forest = hug }, inc = inc })
	near(hug.budget.used, lot, 1e-9)
	D.forestBudgetCommit({ style = { forest = hug }, inc = inc })
	near(hug.budget.used, lot, 1e-9, "once")
	eq(D.forestBudgetSpend(inc, { forest = info(eastForest, "clear") }), "-")
	eq(D.forestLotText(inc, {}), "-")
end)

test("budget windows (round after the names run, Brentwood): a new decade or 1.5 x growth opens one; the tier follows", function()
	local ts = {}
	local b = FO.budgetFor(ts, 1900, 1, 116)
	eq(b.total, FO.BUDGET_HA[1]); eq(b.win, "first")
	b.used = b.total
	b = FO.budgetFor(ts, 1901, 1, 150)
	eq(b.used, b.total, "same window: still spent")
	b = FO.budgetFor(ts, 1901, 2, 180)
	eq(b.win, "growth"); eq(b.used, 0); eq(b.total, FO.BUDGET_HA[2])
	b.used = 1
	b = FO.budgetFor(ts, 1901, 3, 200)
	eq(b.total, FO.BUDGET_HA[3], "a bigger tier raises the total"); eq(b.used, 1)
	b = FO.budgetFor(ts, 1911, 3, 200)
	eq(b.win, "decade"); eq(b.used, 0)
	-- Brentwood's 116 -> 1917 buildings in one game decade: 7 windows instead of 1
	ts = {}
	local wins = 0
	for nb = 116, 1917, 10 do
		local bb = FO.budgetFor(ts, 1901, nb < 300 and 1 or (nb < 900 and 2 or 3), nb)
		if bb.used == 0 and bb.win ~= nil then bb.used = 0.001; wins = wins + 1 end
	end
	ok(wins >= 6 and wins <= 8, "windows " .. wins)
end)

test("forest-facing streets of a hug town are locked (the game hangs no streets of its own off them into the trees)", function()
	local hug = info(eastForest, "hug")
	-- a street along x = 120 (forest from x = 150: its east lots reach it) faces the forest; one at x = -200 does not
	ok(FO.facesForest(hug, { 120, -100 }, { 120, 100 }), "edge street")
	ok(not FO.facesForest(hug, { -200, -100 }, { -200, 100 }), "open street")
	-- a dead end pointing east into the forest
	local face, why = FO.facesForest(hug, { -40, 0 }, { 130, 0 }, false, true)
	ok(face and why == "tip", tostring(why))
	ok(not FO.facesForest(info(eastForest, "clear"), { 120, -100 }, { 120, 100 }), "only hug towns")
	-- the driver's lock keys
	local inc = { edges = {
		{ key = "a#1", node0 = 5, node1 = -1, p0 = { 120, -100 }, p1 = { 120, 0 } },
		{ key = "a#2", node0 = -1, node1 = -2, p0 = { 120, 0 }, p1 = { 120, 100 } },
		{ key = "b#1", node0 = 6, node1 = -3, p0 = { -300, 0 }, p1 = { -200, 0 } } } }
	local job = { inc = inc, style = { forest = hug } }
	local keys, n = D.lockKeys(job)
	ok(keys and keys["a#1"] and keys["a#2"] and not keys["b#1"], "the edge street locked")
	eq(job.forestLockN.side, 2)
end)
