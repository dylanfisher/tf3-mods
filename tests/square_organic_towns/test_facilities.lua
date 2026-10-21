-- Away from player facilities (2026-10-18; ot_industry FAC_KINDS, PLAN.md 6.3 "Away from player facilities"): the
-- mod's street growth leans a little away from the harbors, airports, depots / maintenance stations and freight
-- stations the player builds near a town. Soft only: never a keep-clear zone, never the hold, weaker than any
-- industry; passenger rail stations and small passenger stops are no facility.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local IND = ug_require(F.DIR .. "ot_industry.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local STEEL = "industries/steel_mill/steel_mill.con"
local FOOD = "industries/food_factory/food_factory.con"
local HARBOR = { file = "stations/water/harbor_modular.con", cargo = true, passenger = false }
local AIRPORT = { file = "stations/air/airport.con", cargo = false, passenger = true }
local DEPOT = { file = "depots/road/road_depot/road_depot.con", depot = true }
local FREIGHT = { file = "stations/rail/modular_station/modular_station.con", cargo = true, passenger = false }

local function fac(proto, x, y)
	local r = { x, y }
	for k, v in pairs(proto) do r[k] = v end
	return r
end

local function grow(styleId, ind, n, raw)
	local r = { forceStyle = styleId, townId = 11, year = 1990, nameList = "::/names/germany/germany.names", industry = ind }
	for k, v in pairs(raw or {}) do r[k] = v end
	local style, stats = F.style(r, F.flat)
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local segs, held = {}, 0
	for k = 1, n do
		local inc, report = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
		if #inc.edges == 0 then break end
		held = held + ((report and report.indHeld) or 0)
		for _, e in ipairs(inc.edges) do segs[#segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2], key = e.key } end
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return segs, held
end

local function shareNear(segs, x, y, R)
	local tot, inside = 0, 0
	for _, s in ipairs(segs) do
		local l = G.dist(s[1], s[2], s[3], s[4])
		tot = tot + l
		if G.dist((s[1] + s[3]) / 2, (s[2] + s[4]) / 2, x, y) < R then inside = inside + l end
	end
	return tot > 0 and inside / tot or 0, tot
end

test("classifyFacility: harbors, airports, heliports, depots, maintenance stations, freight-only stations", function()
	eq(IND.classifyFacility(HARBOR), "port")
	-- (as the game lists them, 2026-10-18: cargo rail / truck stations cargo-only, a mixed terminal and industries' own
	-- stations report both)
	eq(IND.classifyFacility({ file = "::/stations/rail/modular_station/modular_station.con", cargo = true, passenger = false }), "freight")
	eq(IND.classifyFacility({ file = "::/stations/street/modular_street_station/modular_terminal.con", cargo = true, passenger = false }), "freight")
	eq(IND.classifyFacility({ file = "::/stations/street/modular_street_station/modular_terminal.con", cargo = true, passenger = true }), nil)
	eq(IND.classifyFacility({ file = "::/industries/steel_mill/steel_mill.con", cargo = true, passenger = false }), nil, "never an industry")
	eq(IND.classifyFacility({ file = "::/depots/water/water_maint_station.con", depot = true }), "depot")
	eq(IND.classifyFacility({ file = "stations/water/harbor_modular.con", passenger = true }), "port", "passenger harbors too")
	eq(IND.classifyFacility(AIRPORT), "airport")
	eq(IND.classifyFacility({ file = "stations/air/airfield.con" }), "airport")
	eq(IND.classifyFacility({ file = "stations/air/heliport.con" }), "heliport")
	eq(IND.classifyFacility({ file = "stations/air/helipad.con" }), "heliport")
	eq(IND.classifyFacility(DEPOT), "depot")
	eq(IND.classifyFacility({ file = "depots/road/tram_depot/tram_depot.con", depot = true }), "depot")
	eq(IND.classifyFacility({ file = "depots/rail/rail_maint_station.con", depot = true }), "depot")
	eq(IND.classifyFacility({ file = "depots/water/water_depot.con", depot = true }), "depot")
	eq(IND.classifyFacility({ file = "", depot = true }), "depot", "a depot whose construction is unreadable")
	eq(IND.classifyFacility(FREIGHT), "freight")
	eq(IND.classifyFacility({ file = "stations/street/modular_street_station/modular_terminal.con", cargo = true,
		passenger = false }), "freight", "truck station")
	-- no lean: passenger rail stations (the M3 station quarter pulls toward them), bus stops, mixed stations
	eq(IND.classifyFacility({ file = "stations/rail/modular_station/modular_station.con", passenger = true }), nil)
	eq(IND.classifyFacility({ file = "stations/rail/modular_station/modular_station.con", cargo = true, passenger = true }), nil)
	eq(IND.classifyFacility({ file = "stations/street/small_stops/small_new.con", passenger = true }), nil)
	eq(IND.classifyFacility({ file = "stations/street/underground_station/underground_station.con" }), nil)
	eq(IND.classifyFacility(nil), nil)
end)

test("forTown with facilities only: soft list, no zone, no hold penalty, industry fields empty", function()
	local inf = IND.forTown({}, 0, 0, 1990, nil, { fac(HARBOR, 300, 0), fac(DEPOT, -200, 0),
		fac({ file = "stations/rail/modular_station/modular_station.con", passenger = true }, 0, 200),
		fac(AIRPORT, 4000, 0) })
	ok(inf ~= nil, "info with facilities only")
	eq(inf.n, 0); eq(#inf.list, 0); eq(#inf.zones, 0)
	eq(inf.fac, 2, "harbor + depot (passenger station ignored, airport beyond reach)")
	eq(IND.zoneText(inf), "-")
	eq(IND.text(inf), "0")
	eq(IND.facText(inf), "2:1/0/0/1/0")
	eq(IND.facText(nil), "0")
	ok(IND.pen(inf, 300, 0) > 0.3, "harbor penalty at the harbor")
	eq(IND.penHold(inf, 300, 0), 0, "never a hold")
	eq(IND.inBuffer(inf, 300, 0), false, "no dose-fill avoidance")
	eq(IND.penHeavy(inf, 300, 0), 0)
	eq(IND.nearestLight(inf, 300, 0), nil)
	eq(IND.zoneHit(inf, { { 300, 0 }, { 300, 50 } }), nil)
	ok(inf.away ~= nil and math.cos(inf.away) < 0, "away from the eastern harbor leans west")
	eq(IND.forTown({}, 0, 0, 1990, nil, { fac(AIRPORT, 4000, 0) }), nil, "beyond reach: none")
	local save = IND.FAC_ON
	IND.FAC_ON = false
	eq(IND.forTown({}, 0, 0, 1990, nil, { fac(HARBOR, 300, 0) }), nil, "FAC_ON off: none")
	IND.FAC_ON = save
end)

test("facilities leave the industries' info unchanged; strengths: airport > port > freight > depot, all under industry", function()
	local all = { { 450, 0, file = STEEL }, { -500, 100, file = FOOD } }
	local a = IND.forTown(all, 0, 0, 1990)
	local b = IND.forTown(all, 0, 0, 1990, nil, {})
	local c = IND.forTown(all, 0, 0, 1990, nil, { fac(HARBOR, 0, 400) })
	for _, k in ipairs({ "n", "nearest", "heavy", "strength", "away", "awayMag" }) do eq(b[k], a[k], k) end
	eq(c.n, a.n); eq(#c.zones, #a.zones); eq(c.heavy, a.heavy)
	for _, p in ipairs({ { 300, 0 }, { 0, 0 }, { -400, 60 } }) do
		eq(IND.penHold(c, p[1], p[2]), IND.pen(a, p[1], p[2]), "hold penalty = industries only")
		eq(IND.pen(b, p[1], p[2]), IND.pen(a, p[1], p[2]))
	end
	ok(IND.pen(c, 0, 400) > IND.pen(a, 0, 400), "the harbor adds to the cost penalty")
	local function at(proto)
		local inf = IND.forTown({}, 0, 0, 1990, nil, { fac(proto, 0, 0) })
		return IND.pen(inf, 0, 0), IND.pen(inf, 250, 0)
	end
	local ap, ap250 = at(AIRPORT)
	local po, po250 = at(HARBOR)
	local fr = at(FREIGHT)
	local de, de250 = at(DEPOT)
	local light = IND.pen(IND.forTown({ { 0, 0, file = FOOD } }, 0, 0, 1990), 0, 0)
	print(string.format("      pen at the site: airport %.2f port %.2f freight %.2f depot %.2f light works %.2f | 250 m: airport %.2f port %.2f depot %.2f",
		ap, po, fr, de, light, ap250, po250, de250))
	ok(ap > po and po > fr and fr > de, "airport > port > freight > depot")
	ok(ap < light, "every facility weaker than a light works")
	ok(ap250 > po250 and po250 > de250, "the airport reaches farthest")
	-- era: weaker before 1920 like the industries
	local i1900 = IND.forTown({}, 0, 0, 1900, nil, { fac(HARBOR, 0, 0) })
	ok(IND.pen(i1900, 0, 0) < po * 0.5, "era weight applies")
end)

test("no facility near: the plan is identical to before", function()
	for _, id in ipairs({ "EU_ORGANIC", "NA_GRID" }) do
		local a = grow(id, nil, 4)
		local b = grow(id, IND.forTown({}, 0, 0, 1990, nil, { fac(AIRPORT, 5000, 0) }), 4)
		eq(#a, #b, id .. " edge count")
		for i = 1, #a do eq(a[i].key, b[i].key, id .. " edge " .. i) end
	end
end)

-- a facility 450 m east of a ~260 m core; town seeds averaged (single seeds are chaotic). The lean must show (less of
-- the new streets near it than without), stay weaker than a heavy works at the same place, never hold a piece back, and
-- the town grows about as much.
local X = 450
local SEEDS = FULL and { 21, 22, 23, 24, 25, 26 } or { 21, 23, 25 }
local STYLES = { "EU_ORGANIC", "MED_HILL", "NORDIC" }
for _, id in ipairs(STYLES) do
	test("a harbor / airport / depot on one side: " .. id .. " leans away, weaker than a heavy works, never holds", function()
		local r = { b = 0, p = 0, a = 0, d = 0, s = 0, bt = 0, pt = 0, held = 0 }
		local n = #SEEDS
		for _, town in ipairs(SEEDS) do
			local raw = { townId = town }
			local base = grow(id, nil, 8, raw)
			local port, hp = grow(id, IND.forTown({}, 0, 0, 1990, nil, { fac(HARBOR, X, 0) }), 8, raw)
			local air, ha = grow(id, IND.forTown({}, 0, 0, 1990, nil, { fac(AIRPORT, X, 0) }), 8, raw)
			local dep, hd = grow(id, IND.forTown({}, 0, 0, 1990, nil, { fac(DEPOT, X, 0) }), 8, raw)
			local steel = grow(id, IND.forTown({ { X, 0, file = STEEL } }, 0, 0, 1990), 8, raw)
			local b, bt = shareNear(base, X, 0, 400)
			local p, pt = shareNear(port, X, 0, 400)
			r.b, r.p, r.bt, r.pt = r.b + b / n, r.p + p / n, r.bt + bt, r.pt + pt
			r.a = r.a + shareNear(air, X, 0, 400) / n
			r.d = r.d + shareNear(dep, X, 0, 400) / n
			r.s = r.s + shareNear(steel, X, 0, 400) / n
			r.held = r.held + hp + ha + hd
		end
		print(string.format("      within 400 m: none %.3f  depot %.3f  harbor %.3f  airport %.3f  steel %.3f | length %.0f -> %.0f m, held %d",
			r.b, r.d, r.p, r.a, r.s, r.bt, r.pt, r.held))
		eq(r.held, 0, id .. ": facilities never hold a piece")
		ok(r.p < r.b, id .. ": the harbor lowers the share near it: " .. r.b .. " -> " .. r.p)
		ok(r.a <= r.b, id .. ": the airport too: " .. r.b .. " -> " .. r.a)
		ok(r.d <= r.b + 0.01, id .. ": a depot never pulls: " .. r.b .. " -> " .. r.d)
		ok(r.s <= r.p + 0.01, id .. ": a heavy works pushes at least as hard: " .. r.s .. " vs " .. r.p)
		ok(r.a <= r.d + 0.02, id .. ": an airport leans at least as much as a depot: " .. r.a .. " vs " .. r.d)
		ok(r.pt >= r.bt * 0.9, id .. ": the town grows about as much: " .. r.bt .. " -> " .. r.pt)
	end)
end
