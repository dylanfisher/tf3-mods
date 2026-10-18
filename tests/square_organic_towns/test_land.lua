-- The landscape pull (ot_land, §62, 2026-10-15; PLAN.md 6.2 "Landscape pull"): one smooth angular field per town from
-- its tree grid and wide survey (forest and steep ground push, open land pulls hardest, the dry land beside water
-- pulls, never across it), blended into ot_select's preference next to the seeded sectors with a capped weight. Also
-- the §61 find: Driver:charIndustry reads the engine's { x, y } industry entries.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local LAND = ug_require(F.DIR .. "ot_land.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local DENSE = 200
local E_, N_, W_, S_ = 0, math.pi / 2, math.pi, -math.pi / 2

local function grid(fn) return FO.fromFunction(0, 0, fn, FO.R, FO.CELL) end
local function noTrees() return 0 end
local function eastWoods(x) return x > 200 and DENSE or 0 end
local function allWoods(x, y) return (x * x + y * y > 250 * 250) and DENSE or 0 end
--- a dry plane rising 8 % toward the east (F.plane dips under the sea 600 m west)
local RISE_E = T.sampler(function(x) return 300 + 0.08 * x end)
local function field(fn, sampler, style)
	local sm = sampler or F.flat
	local rd = LAND.read(fn and grid(fn) or nil, T.wide(sm, 0, 0, 2000), 200, T.stats(sm, 0, 0, 600, 24))
	return LAND.forStyle(rd, style or {}), rd
end

test("forest on one side: the lean peaks toward the open land, the forest pushes away, full strength", function()
	local f = field(eastWoods)
	ok(f.k > 0.3, "k " .. f.k)
	ok(LAND.at(f, W_) > 0.5, "west (open) " .. LAND.at(f, W_))
	ok(LAND.at(f, E_) < -0.8, "east (woods) " .. LAND.at(f, E_))
	eq(LAND.compass(f.peak), "W")
	eq(LAND.cuesText(f), "open:W,forest:E")
	ok(LAND.text(f):find("^open:W,forest:E/k0%.35/to180"), LAND.text(f))
end)

test("uniform surroundings: no lean (flat open land, forest all round)", function()
	local f = field(noTrees)
	eq(f.k, 0, "flat open")
	eq(LAND.cuesText(f), "-")
	local f2 = field(allWoods)
	ok(f2.k < 0.02, "forest all round " .. f2.k)
	-- no grid and no rays: no field at all
	eq(LAND.read(nil, nil, 0), nil)
	eq(LAND.forStyle(nil, {}), nil)
	eq(LAND.at(nil, 1), 0)
	eq(LAND.text(nil), "-")
end)

test("steep rising ground pushes away; the contour (sideways) is favoured", function()
	local f = field(nil, RISE_E)   -- rising 8 % toward the east
	ok(f.k > 0.1, "k " .. f.k)
	local e, w, n, s = LAND.at(f, E_), LAND.at(f, W_), LAND.at(f, N_), LAND.at(f, S_)
	ok(n > e + 0.5 and s > e + 0.5, string.format("contour over uphill: N %.2f S %.2f E %.2f", n, s, e))
	ok(n > w and s > w, string.format("contour over downhill: N %.2f S %.2f W %.2f", n, s, w))
	ok(w > e, "downhill counts less than uphill")
	ok(LAND.cuesText(f):find("steep:E", 1, true), LAND.cuesText(f))
end)

test("valley / canyon: growth along the floor axis both ways, not up the walls", function()
	local f = field(nil, F.valley(0))   -- floor along the x axis
	local e, w, n, s = LAND.at(f, E_), LAND.at(f, W_), LAND.at(f, N_), LAND.at(f, S_)
	ok(e > 0.5 and w > 0.5, string.format("along the floor E %.2f W %.2f", e, w))
	ok(n < 0 and s < 0 and e > n + 0.8 and w > s + 0.8, string.format("the walls N %.2f S %.2f", n, s))
end)

test("water: the dry land beside it pulls (along the shore), the water itself never (no growth across)", function()
	local f = field(nil, F.coast(300))   -- sea beyond x = 300
	local e, n, s, w = LAND.at(f, E_), LAND.at(f, N_), LAND.at(f, S_), LAND.at(f, W_)
	ok(e < -0.5, "across the water " .. e)
	ok(n > w and s > w, string.format("along the shore N %.2f S %.2f over inland W %.2f", n, s, w))
	ok(LAND.cuesText(f):find("water:E", 1, true), LAND.cuesText(f))
	-- a river along y = -120 (the town on its north bank): the banks (east / west) over the far side
	local fr = field(nil, F.river(-120))
	ok(LAND.at(fr, S_) < LAND.at(fr, E_) and LAND.at(fr, S_) < LAND.at(fr, W_),
		string.format("river: S %.2f E %.2f W %.2f", LAND.at(fr, S_), LAND.at(fr, E_), LAND.at(fr, W_)))
	-- off the map counts as no land: rays marked off push like water
	local wide = T.wide(F.flat, 0, 0, 2000)
	D.markOffMap(wide, { -5000, -5000, 1200, 5000 })
	local fo = LAND.forStyle(LAND.read(nil, wide, 0), {})
	ok(LAND.at(fo, E_) < -0.5, "off-map east " .. LAND.at(fo, E_))
end)

test("prairie: forest north and a mountain east -> the open south-west pulls hardest", function()
	local function north(x, y) return y > 250 and DENSE or 0 end
	local mountain = T.sampler(function(x, y) return 20 + math.max(0, x - 200) * 0.12 end)
	local f = field(north, mountain)
	local best, bv = nil, -math.huge
	for k = 0, 15 do
		local a = k / 16 * 2 * math.pi
		if LAND.at(f, a) > bv then best, bv = a, LAND.at(f, a) end
	end
	local deg = math.deg(best) % 360
	ok(deg >= 180 and deg <= 290, "peak " .. deg)
	ok(f.k > 0.3, "k " .. f.k)
	local c = LAND.cuesText(f)
	ok(c:find("forest:N", 1, true) and c:find("steep:E", 1, true), c)
end)

test("style factors: clear / deep towns feel the woods less, character towns keep their intent", function()
	local rd = LAND.read(grid(function(x) return x > 200 and 25 or 0 end), T.wide(F.flat, 0, 0, 2000), 200)
	local hug = LAND.forStyle(rd, { forest = { mode = "hug" } })
	local clear = LAND.forStyle(rd, { forest = { mode = "clear" } })
	local deep = LAND.forStyle(rd, { forest = { mode = "deep" } })
	ok(hug.kRaw > clear.kRaw and clear.kRaw > deep.kRaw, string.format("hug %.2f clear %.2f deep %.2f", hug.kRaw, clear.kRaw, deep.kRaw))
	eq(clear.why, "clear")
	local ch = LAND.forStyle(rd, { charKind = "garden_city" })
	near(ch.k, ch.kRaw * LAND.CHAR_F, 1e-9)
	-- a hilltop ignores the steep cue, a waterfront the water cue
	local rdS = LAND.read(nil, T.wide(RISE_E, 0, 0, 2000), 0)
	eq(LAND.forStyle(rdS, { charKind = "hilltop" }).k, 0, "hilltop: no push off its hill")
	local rdW = LAND.read(nil, T.wide(F.coast(300), 0, 0, 2000), 0)
	local wf = LAND.forStyle(rdW, { charKind = "waterfront" })
	ok(not LAND.cuesText(wf):find("water", 1, true), LAND.cuesText(wf))
	local coast = LAND.forStyle(rdW, { waterDir = 0, irregular = { coast = 0.3 } })
	ok(coast.why:find("coast", 1, true), coast.why)
end)

test("ot_select: no field = the old preference exactly; the cap keeps the seeded variety", function()
	local style = F.style({ forceStyle = "EU_ORGANIC", townId = 11 }, F.flat)
	style._irr = nil
	local c0 = SEL.irregularity(style)
	eq(c0.ampSeed, c0.amp)
	eq(c0.ampLand, 0)
	for k = 0, 11 do
		local a = k / 12 * 2 * math.pi
		near(SEL.preference(c0, a), SEL.seededPreference(c0, a), 1e-12)
		near(SEL.reach(c0, a, false), 1 + c0.amp * SEL.seededPreference(c0, a), 1e-12)
	end
	-- with a full-strength field: amplitudes capped together, the seeded part keeps most of its weight
	local favs = {}
	local f = field(eastWoods)
	for town = 1, 40 do
		local st = F.style({ forceStyle = "EU_ORGANIC", townId = town }, F.flat)
		st.land, st._irr = f, nil
		local c = SEL.irregularity(st)
		ok(c.ampSeed + c.ampLand <= LAND.TOTAL_MAX + 1e-9, "cap")
		ok(c.ampSeed >= 0.7 * c.amp, "seeded kept " .. c.ampSeed .. " of " .. c.amp)
		local lo, hi, best, bv = math.huge, -math.huge, 0, -math.huge
		for k = 0, 35 do
			local a = k / 36 * 2 * math.pi
			local r = SEL.reach(c, a, false)
			lo, hi = math.min(lo, r), math.max(hi, r)
			if r > bv then best, bv = a, r end
		end
		ok(hi / lo <= (1 + LAND.TOTAL_MAX) / (1 - LAND.TOTAL_MAX) + 1e-9, "reach ratio " .. hi / lo)
		ok(SEL.reach(c, W_, false) > SEL.reach(c, E_, false), "town " .. town .. ": the open west reaches farther")
		favs[#favs + 1] = math.floor(math.deg(best) % 360 / 30)
		-- shaped towns: the lean damped by LAND.SHAPE_F (the seeded part by SH.SECTOR_DAMP)
		local c2 = { harm = c.harm, wsum = c.wsum, amp = c.amp, coast = 0, ampSeed = 0, ampLand = c.ampLand, land = c.land }
		near(SEL.reach(c2, W_, true) - 1, LAND.SHAPE_F * (SEL.reach(c2, W_, false) - 1), 1e-9, "shaped damped")
	end
	local distinct = {}
	for _, b in ipairs(favs) do distinct[b] = true end
	local nd = 0
	for _ in pairs(distinct) do nd = nd + 1 end
	ok(nd >= 3, "the favoured heading still varies by town (" .. nd .. " of 12 bins)")
end)

--- n increments of 18 edges from a round core (houses after each): the new street length west / east of the centre.
local function growWestEast(land, n)
	local style, stats = F.style({ forceStyle = "EU_ORGANIC", townId = 11, year = 1960 }, F.flat)
	style.land, style._irr = land, nil
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local west, east = 0, 0
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
		if #inc.edges == 0 then break end
		for _, e in ipairs(inc.edges) do
			local mx = (e.p0[1] + e.p1[1]) / 2
			local L = G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
			if mx < -100 then west = west + L elseif mx > 100 then east = east + L end
		end
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return west, east
end

test("growth: with woods to the east, the town fills the open west first", function()
	local w0, e0 = growWestEast(nil, 8)
	local w1, e1 = growWestEast(field(eastWoods), 8)
	print(string.format("      west / east street m: no pull %.0f / %.0f (%.2f), pull %.0f / %.0f (%.2f)", w0, e0,
		w0 / math.max(1, w0 + e0), w1, e1, w1 / math.max(1, w1 + e1)))
	ok(w1 / math.max(1, w1 + e1) > w0 / math.max(1, w0 + e0) + 0.05, "a bigger west share")
	ok(e1 > 0, "the east still grows (a lean, not a wall)")
end)

test("lobe headings: re-ordered toward the favoured land, unchanged when the lean is weak", function()
	local f = field(eastWoods)
	local dirs = { E_, N_, W_ }
	local o = LAND.orderDirs(dirs, f)
	eq(o[1], W_)
	eq(o[3], E_)
	eq(#dirs, 3)
	eq(dirs[1], E_, "the base list untouched")
	local weak = { k = 0.01, lean = f.lean, n = f.n }
	eq(LAND.orderDirs(dirs, weak), dirs)
	eq(LAND.orderDirs(nil, f), nil)
end)

test("hang guards: the grid read is capped; sector helpers", function()
	local fg = FO.newGrid(0, 0, 6000, 20)   -- 600 x 600 cells
	FO.finish(fg)
	local t0 = os.clock()
	local s = LAND.forestSectors(fg, 300, 1450, 16)
	ok(s ~= nil and #s == 16)
	ok(os.clock() - t0 < 2, "capped")
	eq(LAND.sectorOf(0, 16), 1)
	eq(LAND.sectorOf(2 * math.pi - 0.01, 16), 1)
	eq(LAND.sectorOf(math.pi, 16), 9)
	eq(LAND.r0For(0), 300)
	eq(LAND.r0For(600), 700)
	eq(LAND.r0For(5000), LAND.R0_MAX)
end)

---------------------------------------------------------------------------
-- the driver

local function fakeE(o)
	local E = { logs = {}, t = 0 }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.name(t) return "T" .. t end
	for k, v in pairs(o or {}) do E[k] = v end
	return E
end
local function linesWith(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do if l:find(what, 1, true) then out[#out + 1] = l end end
	return out
end

test("driver: landRefresh puts the field on the style, logs LAND once per change, redoes the cached preference", function()
	local E = fakeE()
	local d = D.new(E, "[T]")
	local s = d:townState(5)
	s.pos, s.extR = { 0, 0 }, 200
	s.wide = T.wide(F.flat, 0, 0, 2000)
	s.forest = grid(eastWoods)
	local style = F.style({ forceStyle = "EU_ORGANIC", townId = 5 }, F.flat)
	style.lobeDirs = { E_, W_ }
	style.forest = FO.forStyle(s.forest, style)
	SEL.irregularity(style)
	ok(style._irr ~= nil)
	local job = { town = 5, ext = { cx = 0, cy = 0, r = 200 } }
	d:landRefresh(job, style)
	ok(style.land ~= nil and style.land.k > 0.1, "field on the style")
	eq(style._irr, nil, "the cached preference is redone")
	eq(style.lobeDirs[1], W_, "lobes toward the open land first")
	local l = linesWith(E, "LAND")
	eq(#l, 1)
	ok(l[1]:find("cues=open:W,forest:E", 1, true) and l[1]:find(" to=180", 1, true), l[1])
	SEL.irregularity(style)
	d:landRefresh(job, style)
	ok(style._irr ~= nil, "unchanged field: the cache stays")
	eq(#linesWith(E, "LAND"), 1, "logged once")
	-- the forest re-read: a new grid, the field recomputed
	s.forest = grid(function(x) return x < -200 and DENSE or 0 end)
	d:landRefresh(job, style)
	eq(LAND.compass(style.land.peak), "E")
	eq(#linesWith(E, "LAND"), 2)
	-- off: no field
	D.LAND = false
	d:landRefresh(job, style)
	eq(style.land, nil)
	D.LAND = true
end)

test("driver: an older save (town state without any land reading) plans as before until it has one", function()
	local E = fakeE()
	local d = D.new(E, "[T]")
	d:townState(6).pos = { 0, 0 }   -- no wide survey, no forest
	local style = F.style({ forceStyle = "EU_ORGANIC", townId = 6 }, F.flat)
	d:landRefresh({ town = 6, ext = { cx = 0, cy = 0, r = 100 } }, style)
	eq(style.land, nil)
	eq(#linesWith(E, "LAND"), 0)
	local c = SEL.irregularity(style)
	eq(c.ampLand, 0)
end)

test("driver: charIndustry reads the engine's { x, y } industry entries (§61 find: no company town was ever picked)", function()
	local E = fakeE({ industries = function()
		return { { 900, 0, file = "industry/steel_mill/steel_mill.con", e = 1 }, { 300, 0, file = "industry/farm/farm.con", e = 2 },
			{ x = 1200, y = 0, file = "industry/coal_mine/coal_mine.con" } }
	end })
	local d = D.new(E, "[T]")
	local best = d:charIndustry(0, 0, 0)
	ok(best ~= nil, "found")
	eq(best.x, 900)
	eq(best.y, 0)
	near(best.d, 900, 1e-9)
	ok(best.kind == "heavy" or best.kind == "medium", tostring(best.kind))
	local d2 = D.new(fakeE({ industries = function() return { { 5000, 0, file = "industry/steel_mill/steel_mill.con" } } end }), "[T]")
	eq(d2:charIndustry(0, 0, 0), nil, "beyond COMPANY_R")
end)
