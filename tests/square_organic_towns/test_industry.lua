-- Away from industries (2026-10-12; PLAN.md 6.3 "Away from industries"): the mod's street growth prefers land away
-- from the industries near a town (ot_industry: cost, envelope, sector lean, shape axis, dose points). A preference,
-- never a ban: a town boxed in by works still grows; heavy works push harder than light ones; no industries = the
-- plan is exactly as before.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local IND = ug_require(F.DIR .. "ot_industry.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local STEEL = "industries/steel_mill/steel_mill.con"
local FOOD = "industries/food_factory/food_factory.con"

local function info(list, year)
	return (IND.forTown(list, 0, 0, year or 1990))
end

--- n increments of 18 edges from a round core (houses after each), the style forced, industries `ind` (forTown
--- result or nil). Returns the new streets as segments (built by the mod) and the graph.
local function grow(styleId, ind, n, raw)
	local r = { forceStyle = styleId, townId = 11, year = 1990, nameList = "::/names/germany/germany.names", industry = ind }
	for k, v in pairs(raw or {}) do r[k] = v end
	local style, stats = F.style(r, F.flat)
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

--- Share of the segments' length within R of (x, y), and the total length.
local function shareNear(segs, x, y, R)
	local tot, inside = 0, 0
	for _, s in ipairs(segs) do
		local l = G.dist(s[1], s[2], s[3], s[4])
		tot = tot + l
		if G.dist((s[1] + s[3]) / 2, (s[2] + s[4]) / 2, x, y) < R then inside = inside + l end
	end
	return tot > 0 and inside / tot or 0, tot
end

--- Share of the segments' length on the side x > 0.
local function eastShare(segs)
	local tot, east = 0, 0
	for _, s in ipairs(segs) do
		local l = G.dist(s[1], s[2], s[3], s[4])
		tot = tot + l
		if (s[1] + s[3]) / 2 > 0 then east = east + l end
	end
	return tot > 0 and east / tot or 0
end

test("classify: heavy / medium / light by file name, unknown names medium and reported", function()
	eq(IND.classify(STEEL), "heavy")
	eq(IND.classify("industries/coal_mine/coal_mine.con"), "heavy")
	eq(IND.classify("industries/oil_refinery/oil_refinery.con"), "heavy")
	eq(IND.classify("industries/saw_mill/saw_mill.con"), "heavy")
	eq(IND.classify("industries/machine_factory/machine_factory.con"), "medium")
	eq(IND.classify(FOOD), "light")
	eq(IND.classify("industries/livestock_farm/livestock_farm.con"), "light")
	eq(IND.classify("industries/oil_platform/oil_platform.con"), "ignore")
	local k, matched = IND.classify("some_mod/industries/widget_plant.con")
	eq(k, "medium")
	eq(matched, false)
	local inf, unknown = IND.forTown({ { 300, 0, file = "some_mod/industries/widget_plant.con" },
		{ 200, 0, file = "industries/oil_platform/oil_platform.con" } }, 0, 0, 1990)
	eq(inf.n, 1, "the platform is ignored")
	ok(unknown["some_mod/industries/widget_plant.con"], "unknown name reported")
	eq(IND.text(inf), "1/300/0")
	eq(IND.text(nil), "0")
	eq(IND.forTown({ { 3000, 0, file = STEEL } }, 0, 0, 1990), nil, "beyond SEARCH_R: none")
	eq(IND.forTown({}, 0, 0, 1990), nil, "no industries: nil")
end)

test("era (era range 1900+): weak to 1910, full from 1945", function()
	near(IND.strength(1900), 0.4, 1e-9)
	near(IND.strength(1910), 0.4, 1e-9)
	near(IND.strength(1927.5), 0.7, 1e-9)
	near(IND.strength(1945), 1.0, 1e-9)
	local i1880, i1990 = info({ { 400, 0, file = STEEL } }, 1880), info({ { 400, 0, file = STEEL } }, 1990)
	ok(IND.pen(i1880, 300, 0) < IND.pen(i1990, 300, 0) * 0.5, "1880 penalty under half of 1990's")
	ok(IND.pen(i1990, 400, 0) > 0.9 and IND.pen(i1990, 1300, 0) < 0.01, "heavy: full at the works, ~0 beyond 1.9 r")
	near(i1990.away, math.pi, 1e-6, "away from an eastern works = west")
end)

test("no industries: the plan is identical to before", function()
	for _, id in ipairs({ "EU_ORGANIC", "NA_GRID" }) do
		local a = grow(id, nil, 4)
		local b = grow(id, IND.forTown({ { 5000, 0, file = STEEL } }, 0, 0, 1990), 4)
		eq(#a, #b, id .. " edge count")
		for i = 1, #a do eq(a[i].key, b[i].key, id .. " edge " .. i) end
	end
end)

-- a heavy works 550 m east of a ~260 m core (its 500 m buffer reaches the core's east side); 8 town seeds per style
-- (single seeds are chaotic: one reordered piece changes every later increment). Thresholds per style: the grids'
-- housed front leaves fewer pieces than the budget, so the cost can only reorder them (the hold does a little).
local X, SEEDS = 550, { 21, 22, 23, 24, 25, 26, 27, 28 }
local WANT = { EU_ORGANIC = 0.5, EU_EXTENSION = 0.6, JP_DENSE = 0.6, MED_HILL = 0.5, NORDIC = 0.85, NA_GRID = 0.95 }
for _, id in ipairs({ "EU_ORGANIC", "EU_EXTENSION", "JP_DENSE", "MED_HILL", "NORDIC", "NA_GRID" }) do
	test("an industry on one side: " .. id .. " builds mostly on the other side, heavy stronger than light", function()
		local r = { b = 0, h = 0, l = 0, e = 0, bt = 0, ht = 0, eb = 0, eh = 0 }
		local n = #SEEDS
		for _, town in ipairs(SEEDS) do
			local raw = { townId = town }
			local base = grow(id, nil, 8, raw)
			local heavy = grow(id, info({ { X, 0, file = STEEL } }), 8, raw)
			local light = grow(id, info({ { X, 0, file = FOOD } }), 8, raw)
			local early = grow(id, info({ { X, 0, file = STEEL } }, 1880), 8, raw)
			local b, bt = shareNear(base, X, 0, 500)
			local h, ht = shareNear(heavy, X, 0, 500)
			r.b, r.bt, r.h, r.ht = r.b + b / n, r.bt + bt, r.h + h / n, r.ht + ht
			r.l = r.l + shareNear(light, X, 0, 500) / n
			r.e = r.e + shareNear(early, X, 0, 500) / n
			r.eb, r.eh = r.eb + eastShare(base) / n, r.eh + eastShare(heavy) / n
		end
		print(string.format("      in buffer: none %.2f  heavy %.2f  light %.2f  heavy-1880 %.2f | east half: none %.2f heavy %.2f | length %.0f -> %.0f m",
			r.b, r.h, r.l, r.e, r.eb, r.eh, r.bt, r.ht))
		ok(r.h < r.b * WANT[id], id .. ": heavy works cut the share inside its buffer: " .. r.b .. " -> " .. r.h)
		ok(r.h <= r.l + 0.03, id .. ": heavy at least as strong as light: " .. r.h .. " vs " .. r.l)
		ok(r.e >= r.h - 0.03, id .. ": weaker before 1920: " .. r.e .. " vs " .. r.h)
		-- (NA grid: its frames go round the buffer, NE / SE, so its east half may even grow a little)
		if id ~= "NA_GRID" then ok(r.eh < r.eb, id .. ": less growth on the works' side") end
		ok(r.ht >= r.bt * 0.85, id .. ": the town grows about as much: " .. r.bt .. " -> " .. r.ht)
	end)
end

test("boxed in by works on four sides: the town still grows", function()
	local box = info({ { 430, 0, file = STEEL }, { -430, 0, file = STEEL }, { 0, 430, file = STEEL },
		{ 0, -430, file = STEEL } })
	-- (the soft buffer alone, the keep-clear zones off: the cost and the holds only reorder)
	local zone0 = IND.ZONE
	IND.ZONE = false
	for _, id in ipairs({ "EU_ORGANIC", "NA_GRID" }) do
		local base = grow(id, nil, 6)
		local boxed = grow(id, box, 6)
		local _, bt = shareNear(base, 0, 0, 1e9)
		local _, xt = shareNear(boxed, 0, 0, 1e9)
		print(string.format("      %-10s boxed: %d edges / %.0f m (no works: %d / %.0f m)", id, #boxed, xt, #base, bt))
		ok(#boxed >= 0.7 * #base and xt >= 0.6 * bt, id .. ": boxed-in town grows: " .. #boxed .. " vs " .. #base)
	end
	IND.ZONE = zone0
	-- (with the hard keep-clear zones, 2026-10-13: the works' discs stay empty, the town still grows between them)
	for _, id in ipairs({ "EU_ORGANIC", "NA_GRID" }) do
		local base = grow(id, nil, 6)
		local boxed = grow(id, box, 6)
		local inZone = 0
		for _, e in ipairs(boxed) do
			if IND.zoneHit(box, { { e[1], e[2] }, { e[3], e[4] } }, 0) then inZone = inZone + 1 end
		end
		print(string.format("      %-10s zones %s: %d edges (no works: %d), %d in a zone", id, IND.zoneText(box), #boxed, #base, inZone))
		eq(inZone, 0, id .. ": no street in a keep-clear zone")
		ok(#boxed >= 0.25 * #base, id .. ": boxed-in town still grows: " .. #boxed .. " vs " .. #base)
	end
end)

test("shape: a seeded axis turns its arms away from the works; a site axis stays", function()
	local ind = info({ { 450, 0, file = STEEL } })
	local turned, n = 0, 0
	for town = 1, 12 do
		local p = F.style({ forceStyle = "EU_ORGANIC", townId = town, year = 1990, shape = "linear", industry = ind,
			nameList = "::/names/germany/germany.names" }, F.flat)
		n = n + 1
		local worst = math.huge
		for _, a in ipairs(p.shape.arms) do worst = math.min(worst, G.angleDiff(a, 0)) end
		if p.shape.indTurned then turned = turned + 1 end
		ok(worst >= math.rad(40), "town " .. town .. ": no arm toward the works (" .. math.deg(worst) .. " deg)")
	end
	print(string.format("      linear towns turned away: %d of %d", turned, n))
	-- a river axis (site) is kept
	local river = F.style({ forceStyle = "EU_ORGANIC", townId = 3, year = 1990, industry = ind,
		nameList = "::/names/germany/germany.names" }, F.river(-120))
	ok(not river.shape.indTurned, "site axis untouched")
end)

test("dose points avoid the buffers when the build has streets outside them", function()
	local edges = {}
	for k = 0, 5 do edges[#edges + 1] = { p0 = { -300 + 120 * k, 50 }, p1 = { -300 + 120 * k + 100, 50 } } end
	local ind = info({ { 400, 50, file = STEEL } })
	local pts = D.fillPoints("metro", edges, nil, nil, nil, { industry = ind })
	ok(#pts > 0, "points")
	for _, p in ipairs(pts) do ok(not IND.inBuffer(ind, p[1], p[2]), "metro point outside the buffer") end
	-- every street inside a buffer: the points stay (boxed-in towns still get their dose)
	local all = D.fillPoints("metro", edges, nil, nil, nil, { industry = info({ { 0, 50, file = STEEL } }) })
	ok(#all > 0, "boxed: points kept")
	eq(#D.fillPoints("metro", edges, nil, nil, nil, {}), #D.fillPoints("metro", edges, nil, nil, nil, { industry = nil }))
end)

test("keep-clear zones (2026-10-13): max-level footprint + margin, shrunk short of the town centre, read out to r + reach", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local rMax, r1 = IND.footprint("industries/farm/farm.con")
	eq(rMax, 382); eq(r1, 108)
	eq(IND.footprint("industries/oil_platform/oil_platform.con"), 0)
	ok(IND.footprint("industries/steel_mill/steel_mill.con") < 150, "processing plants never grow")
	-- far from the centre: the whole footprint + margin; near it: down to the level-1 size + margin
	eq(IND.zoneRadius("industries/farm/farm.con", 2000, 0, 0, 0), 382 + IND.ZONE_MARGIN)
	eq(IND.zoneRadius("industries/farm/farm.con", 250, 0, 0, 0), 108 + IND.ZONE_MARGIN)
	eq(IND.zoneRadius("industries/farm/farm.con", 500, 0, 0, 0), 500 - IND.ZONE_CORE_M)
	-- Budleigh Salterton (run 2240): r = 1850 m, its farm 1700 m out was beyond the fixed 1500 m search
	local all = { { 1700, 0, file = "industries/farm/farm.con" } }
	eq(IND.forTown(all, 0, 0, 1990), nil, "fixed search radius: not seen")
	local info = IND.forTown(all, 0, 0, 1990, 1850 + IND.ZONE_REACH)
	ok(info and #info.zones == 1 and info.zones[1].r == 422, "seen with the town's reach")
	ok(IND.zoneHit(info, { { 1300, 0 }, { 1400, 0 } }) ~= nil, "a street 300 m from the farm")
	eq(IND.zoneHit(info, { { 1000, 0 }, { 1100, 300 } }), nil)
	eq(IND.zoneText(info), "1:422")
	-- the driver: streets near a zone locked; a dose point in one dropped (the fill stage) ; the zone lock count
	local job = { style = { industry = info }, inc = { edges = {
		{ key = "a", p0 = { 1200, 0 }, p1 = { 1240, 0 } }, { key = "b", p0 = { 600, 0 }, p1 = { 640, 0 } } } } }
	local keys, n = D.zoneLock(job, nil, 0)
	ok(keys.a and not keys.b and n == 1 and job.zoneLockN == 1, "the street beside the zone locked")
	-- every list of zones is respected by the planner (boxed-in test above) and by IND.inZone with the lot pad
	ok(IND.inZone(info, 1700 - 422 - 10, 0, IND.ZONE_LOT) ~= nil and IND.inZone(info, 1700 - 422 - 40, 0, IND.ZONE_LOT) == nil)
end)

test("enclosure (2026-10-14 late, dev ALLTOWN ind=): industries in the town, enclosed by houses / streets on 3+ sides", function()
	local all = { { 100, 0, file = "industry/farm/crop_farm.con" }, { 2000, 0, file = "industry/steel_mill/steel_mill.con" },
		{ -100, 50, file = "industry/brewery/brewery.con" } }
	-- houses north, east and south of the farm (within its keep-clear radius), nothing round the brewery
	local pts = { { 100, 200 }, { 300, 0 }, { 100, -250 } }
	local n, enc, text = IND.enclosure(all, 0, 0, 600, pts, {})
	eq(n, 2, "the steel mill is outside the town")
	eq(enc, 1)
	eq(text, "2/1:crop_farm")
	-- a street west of the brewery and houses on two more sides: enclosed too
	local n2, enc2 = IND.enclosure(all, 0, 0, 600, { { 100, 200 }, { 300, 0 }, { 100, -250 }, { -100, 150 }, { -100, -60 } },
		{ { -200, 40, -260, 60 } })
	eq(n2, 2)
	eq(enc2, 2)
	eq(select(3, IND.enclosure({}, 0, 0, 600, pts, {})), "0/0")
end)
