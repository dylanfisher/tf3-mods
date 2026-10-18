-- Town-structure / era motifs (ot_motif_town, phase M3 of plans/square_organic_towns/MOTIFS_BRIEF.md, 2026-10-13): the
-- ring road around the old core, the station quarter (derived: the gameplay hook), workers' terraces at light works and
-- cul-de-sac pods. Eligibility (era, style, size, surroundings), each motif's pattern metric after simulated increments
-- (join "deadEnd" as in game), the rules (no crossings, no water, grades, map edge, lead limit, configs for every new
-- node) and the saved ring radius.
-- Set OT_SVG=<dir> to dump an SVG per motif run (the plan grey, the motif's pieces orange, built streets black).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
local TW = ug_require(F.DIR .. "ot_motif_town.lua")
local L = ug_require(F.DIR .. "ot_motif_land.lua")
local RM = ug_require(F.DIR .. "ot_motif_road.lua")
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
local IND = ug_require(F.DIR .. "ot_industry.lua")

local EU = "::/names/europe/europe.names"
local NEW_SMALL = "::/infrastructure/street/town/town_new_small.street_template"

local function has(list, id) for _, m in ipairs(list or {}) do if m.id == id then return m end end end

local function resolve(sampler, o)
	o = o or {}
	local stats = T.stats(sampler, 0, 0, 600, 24)
	local inputs = I.build({ townId = o.id or 5, pos = { 0, 0 }, capacity = o.cap or 1500, year = o.year or 1900,
		nameList = EU, terrain = stats, forceStyle = o.style, autoStyle = o.style == nil, motif = o.motif,
		radius = o.radius or 160, bounds = o.bounds, frame = o.frame, shape = o.shape, industry = o.industry,
		railStations = o.stations, roads = o.roads })
	local st = ST.resolve(inputs)
	st.stationKey = TW.stationKey(o.stations)
	return st, stats, inputs
end

local function ctxOf(st, stats, inputs, o)
	o = o or {}
	return { style = st, terrain = stats, inputs = inputs, tier = o.tier or 2, year = o.year or 1900, shape = o.shape }
end

local SVGDIR = os.getenv("OT_SVG")
local function svg(name, g, mp, sampler, extra)
	if not SVGDIR then return end
	local f = io.open(SVGDIR .. "/" .. name .. ".svg", "w")
	if not f then return end
	local S, W = 1000, 2000
	local function X(x) return (x + W / 2) * S / W end
	local function Y(y) return (W / 2 - y) * S / W end
	f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="100%%" height="100%%" fill="white"/>', S, S))
	for i = 0, 49 do
		for j = 0, 49 do
			local x, y = -W / 2 + (i + 0.5) * W / 50, -W / 2 + (j + 0.5) * W / 50
			if T.isWater(sampler, x, y) then
				f:write(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#9cf"/>', X(x - W / 100),
					Y(y + W / 100), S / 50 + 0.5, S / 50 + 0.5))
			end
		end
	end
	for _, pc in ipairs(mp and mp.pieces or {}) do
		local d = {}
		for i, p in ipairs(pc.pts) do d[#d + 1] = (i == 1 and "M" or "L") .. string.format("%.1f %.1f", X(p[1]), Y(p[2])) end
		f:write(string.format('<path d="%s" stroke="%s" stroke-width="%s" fill="none"/>', table.concat(d, " "),
			pc.motif and "#f80" or "#ddd", pc.motif and 2 or 1))
	end
	for _, s in ipairs(extra or {}) do
		f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>', X(s[1]), Y(s[2]),
			X(s[3]), Y(s[4]), s.color or "#d33"))
	end
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#000" stroke-width="2"/>', X(a.x), Y(a.y),
			X(b.x), Y(b.y)))
	end
	f:write("</svg>")
	f:close()
end

--- A round organic core (F.roundCore: rings 90 / 180 / 270 m, 14 radial dead-end stubs ~50 m out of the outer ring).
local function roundTown(o)
	o = o or {}
	return F.roundCore(OG.new(), { rings = o.rings, counts = o.counts, stubStep = o.stubStep })
end

--- A forced motif on graph g, n increments (join "deadEnd"): measure, record, style, increments, stats.
local function run(g, sampler, motif, o)
	o = o or {}
	local st, stats = resolve(sampler, { motif = motif, style = o.style or "EU_ORGANIC", radius = o.radius, cap = o.cap,
		bounds = o.bounds, year = o.year, industry = o.industry, stations = o.stations, frame = o.frame, roads = o.roads })
	local incs = core.simulate(g, st, { terrain = sampler, stats = stats, join = "deadEnd" }, o.n or 12)
	local m = has(MO.list(st), motif)
	local mp = core.masterPlan(g, st, { terrain = sampler, stats = stats }, 8)
	local r = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = o.pts or {}, sampler = sampler, MT = MT, SH = SH,
		mp = mp })
	if o.svg then svg(o.svg, g, mp, sampler, o.extra) end
	return r, m, st, incs, stats, mp
end

--- Rules every motif run keeps: no crossing streets, min angle, nothing on water, no steep or large new street.
local function rules(name, g, st, incs, sampler, prefix)
	local e1, e2 = F.crossingPair(g)
	ok(e1 == nil, name .. ": crossing edges " .. tostring(e1 and e1.id) .. "/" .. tostring(e2 and e2.id))
	ok(F.minAngle(g) >= 15, name .. ": min angle " .. F.minAngle(g))
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			local pts = { { e.p0[1], e.p0[2] }, { e.p1[1], e.p1[2] } }
			ok(not T.wetAlong(sampler, pts, 0), name .. ": edge on water " .. tostring(e.key))
			ok(T.grade(sampler, e.p0[1], e.p0[2], e.p1[1], e.p1[2]) <= st.maxSlope + 0.01, name .. ": steep edge " .. tostring(e.key))
			if prefix and type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then
				ok(not tostring(e.template):find("large", 1, true), name .. ": wide motif street " .. e.key)
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

--- Every new node of the motif's increments gets a config and valid lane indices (crash rule); never a join at a
--- noJoin node.
local function crashRule(name, g, st, stats, sampler, n)
	local specs = 0
	for k = 1, n do
		local inc = core.planIncrement(g, st, { terrain = sampler, stats = stats, join = "deadEnd" })
		if #inc.edges == 0 then break end
		local inf = { nodes = {}, sources = {}, fallback = 902 }
		for _, jn in ipairs(inc.joins) do
			local edges = {}
			for _, eid in ipairs(g.adj[jn.node] or {}) do edges[#edges + 1] = eid end
			inf.nodes[jn.node] = { hasConfig = true, edges = edges, lanes = 4, src = edges[1] or 902, template = NEW_SMALL }
		end
		local spec, err = PR.build(inc, inf)
		ok(spec ~= nil, name .. " " .. tostring(err))
		if spec then
			specs = specs + 1
			local cfg = {}
			for _, cc in ipairs(spec.cfgAdd) do cfg[cc.node] = true end
			for _, nd in ipairs(spec.nodes) do ok(cfg[nd.entity], name .. " node without a config") end
			ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
		end
		for _, jn in ipairs(inc.joins) do ok(not g.nodeById[jn.node].noJoin, name .. ": joined a noJoin node") end
		OG.apply(g, inc, k)
	end
	return specs
end

-- a station east of the town: forecourt (local -Y) facing the town (west), tracks north-south behind it
local function stationEast(x, o)
	o = o or {}
	local fx = o.fx or -1
	local tracks = {}
	local tx = x - fx * 25
	for k = -6, 5 do tracks[#tracks + 1] = { tx, k * 80, tx, (k + 1) * 80 } end
	return { x = x, y = o.y or 0, fx = fx, fy = 0, front = { x + fx * 17, o.y or 0 }, tracks = tracks,
		box = { x - 30, (o.y or 0) - 110, x + 30, (o.y or 0) + 110 }, file = "station/rail/modular_station/x.con" }
end

---------------------------------------------------------------------------

test("registry: the four M3 kinds with append-only save indices (10-13); the station quarter derived", function()
	local ids = { "crescent", "hill_road", "hill_climb", "valley_fishbone", "harbour_crescent", "fishing_village",
		"ribbon_village", "village_green", "crossroads_hamlet", "ring_road", "station_quarter", "workers_terraces",
		"culdesac_pods" }
	for i, id in ipairs(ids) do eq(MO.IDS[i], id) end
	for _, id in ipairs({ "ring_road", "workers_terraces", "culdesac_pods" }) do
		local k = MO.BY_ID[id]
		ok(k and not k.derived and k.eligible and k.plan and k.measure, id)
	end
	ok(MO.BY_ID.station_quarter.derived, "the station quarter is derived (stations come and go)")
	ok(MO.BY_ID.ring_road.style, "the ring sets the outer districts")
	ok(MO.BY_ID.workers_terraces.dose, "dense terrace rows")
	local v = MO.encode({ { id = "ring_road" }, { id = "culdesac_pods" } })
	eq(v, 10 + 64 * 13)
	local d = MO.decode(v)
	eq(d[1], "ring_road"); eq(d[2], "culdesac_pods")
	-- the derived station quarter is never saved
	eq(MO.encode({ { id = "station_quarter", derived = true } }), nil)
end)


test("eligibility: era, style, size and surroundings; none while the module is off (the other tests' baselines)", function()
	local light = IND.forTown({ { 380, 360, file = "industry/food_processing_plant/food_processing_plant.con" } }, 0, 0, 1905)
	local function score(id, sampler, o, ctxo)
		local st, stats, inputs = resolve(sampler, o)
		local s, why = MO.BY_ID[id].eligible(ctxOf(st, stats, inputs, ctxo))
		return s or 0, why
	end
	-- off (fixtures): every M3 kind 0
	eq(score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 250, year = 1900 }), 0)
	F.withTownMotifs(function()
		local lines = {}
		local function line(id, s, why) lines[#lines + 1] = string.format("%s=%.2f (%s)", id, s, tostring(why)) end
		-- ring road: an old core (EU organic / extension / MED hill), tier 2+, flat, more after ~1870
		local s, why = score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 250, year = 1900 })
		line("ring_road", s, why)
		ok(s > 0.3, "ring on a flat EU core " .. s)
		-- (era range 1900+: an early-game old-town motif, less in later starts)
		eq(score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 250, year = 1935 }, { year = 1935 }), s, "ring to 1940: full")
		ok(score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 250, year = 1970 }, { year = 1970 }) < s, "ring later: less")
		eq(score("ring_road", F.flat, { style = "NA_GRID", radius = 250 }), 0, "no ring in a grid town")
		eq(score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 250 }, { tier = 1 }), 0, "a village has no ring")
		eq(score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 100 }), 0, "a small core: no ring")
		eq(score("ring_road", F.plane(0.15, 0), { style = "EU_ORGANIC", radius = 250 }), 0, "steep: no ring")
		ok(score("ring_road", F.flat, { style = "EU_ORGANIC", radius = 250 }, { shape = "linear" }) < s, "a linear town: less")
		ok(score("ring_road", F.flat, { style = "EU_EXTENSION", radius = 250 }) > 0, "EU extension")
		-- station quarter: a rail station near the town (derived: no era / style limit but the metropolis)
		local sq, sqWhy = score("station_quarter", F.flat, { style = "EU_ORGANIC", stations = { stationEast(650) } })
		line("station_quarter", sq, sqWhy)
		eq(sq, 1)
		eq(score("station_quarter", F.flat, { style = "EU_ORGANIC" }), 0, "no station")
		eq(score("station_quarter", F.flat, { style = "EU_ORGANIC", stations = { stationEast(2000) } }), 0, "station too far")
		eq(score("station_quarter", F.flat, { style = "NA_GRID", stations = { stationEast(650) } }), 1, "any style")
		-- workers' terraces: a light works (a factory, not a farm) beyond the houses, before ~1920
		local wt, wtWhy = score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = light, year = 1905 })
		line("workers_terraces", wt, wtWhy)
		ok(wt > 0.4, "terraces at a food works " .. wt)
		ok(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = light, year = 1940 }, { year = 1940 }) < wt, "later: less")
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = light, year = 1930 }, { year = 1930 }), wt, "1930: full (era range 1900+)")
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = light, year = 1950 }, { year = 1950 }), 0, "1950: none")
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", year = 1905 }), 0, "no works")
		local farm = IND.forTown({ { 380, 360, file = "industry/farm/farm.con" } }, 0, 0, 1905)
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = farm, year = 1905 }), 0, "a farm is no factory")
		local steel = IND.forTown({ { 380, 360, file = "industry/steel_mill/steel_mill.con" } }, 0, 0, 1905)
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = steel, year = 1905 }), 0, "heavy works: never")
		local mixed = IND.forTown({ { 380, 360, file = "industry/food_processing_plant/food_processing_plant.con" },
			{ 600, 500, file = "industry/steel_mill/steel_mill.con" } }, 0, 0, 1905)
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = mixed, year = 1905 }), 0, "light works beside heavy")
		local inside = IND.forTown({ { 120, 80, file = "industry/food_processing_plant/food_processing_plant.con" } }, 0, 0, 1905)
		eq(score("workers_terraces", F.flat, { style = "EU_ORGANIC", industry = inside, year = 1905 }), 0, "works in the town")
		-- cul-de-sac pods: post-1950 suburbs
		local cp, cpWhy = score("culdesac_pods", F.flat, { style = "EU_EXTENSION", year = 1970 }, { year = 1970 })
		line("culdesac_pods", cp, cpWhy)
		ok(cp > 0.3, "pods 1970 " .. cp)
		eq(score("culdesac_pods", F.flat, { style = "EU_EXTENSION", year = 1930 }, { year = 1930 }), 0, "1930: none")
		eq(score("culdesac_pods", F.flat, { style = "JP_DENSE", year = 1970 }, { year = 1970 }), 0, "JP dense: none")
		ok(score("culdesac_pods", F.flat, { style = "NA_SUBURB", year = 1970 }, { year = 1970 }) > 0, "NA suburb")
		eq(score("culdesac_pods", F.plane(0.16, 0), { style = "EU_EXTENSION", year = 1970 }, { year = 1970 }), 0, "steep: none")
		print(table.concat(lines, "  "))
		-- metropolises: none of them
		for _, id in ipairs({ "ring_road", "station_quarter", "workers_terraces", "culdesac_pods" }) do
			local st, stats, inputs = resolve(F.flat, { style = "EU_EXTENSION", radius = 250, year = 1970, industry = light,
				stations = { stationEast(650) } })
			st.metro = { id = "grid" }
			eq(MO.BY_ID[id].eligible(ctxOf(st, stats, inputs, { year = 1905 })), 0, id .. " metropolis")
		end
	end)
end)

test("picks: deterministic, one per group, the era decides between ring / terraces and pods; the quarter takes no slot", function()
	F.withTownMotifs(function()
		local light = IND.forTown({ { 380, 360, file = "industry/textile_factory/textile_factory.con" } }, 0, 0, 1905)
		local function count(year, o)
			local seen = { ring_road = 0, workers_terraces = 0, culdesac_pods = 0, station_quarter = 0 }
			for id = 1, 120 do
				local a = resolve(F.flat, { id = id, radius = 250, cap = 3000, year = year, industry = light, stations = o and o.stations })
				local b = resolve(F.flat, { id = id, radius = 250, cap = 3000, year = year, industry = light, stations = o and o.stations })
				eq(MO.text(a.motifs), MO.text(b.motifs), "same town, same motifs")
				-- (the extra station quarter and the free crescents (final-test round) take no slot)
				local slotted = 0
				for _, m in ipairs(MO.list(a)) do
					local k = MO.BY_ID[m.id]
					if not (k.extra or k.free) then slotted = slotted + 1 end
				end
				ok(slotted <= MO.MAX, "slots " .. MO.text(MO.list(a)))
				seen.texts = seen.texts or {}
				seen.texts[id] = MO.text(a.motifs)
				local groups = {}
				for _, m in ipairs(MO.list(a)) do
					if seen[m.id] then seen[m.id] = seen[m.id] + 1 end
					local gr = MO.BY_ID[m.id].group
					if gr then ok(not groups[gr], "one per group"); groups[gr] = true end
				end
				-- (drawn motifs fill the slots the derived ones leave)
				ok(#a.motifs <= MO.MAX - MO.slotsTaken(a), "derived first " .. MO.text(MO.list(a)))
			end
			return seen
		end
		local early, late = count(1905), count(1975)
		print(string.format("120 towns 1905: ring %d, terraces %d, pods %d | 1975: ring %d, terraces %d, pods %d", early.ring_road,
			early.workers_terraces, early.culdesac_pods, late.ring_road, late.workers_terraces, late.culdesac_pods))
		ok(early.ring_road > 5 and early.workers_terraces > 5, "1905: rings and terraces")
		eq(early.culdesac_pods, 0, "no pods before 1945")
		eq(late.workers_terraces, 0, "no terraces after 1930")
		ok(late.culdesac_pods > 5 and late.ring_road > 0, "1975: pods (and a few rings: fewer old organic cores then)")
		local st = count(1975, { stations = { stationEast(650) } })
		eq(st.station_quarter, 120, "a station: every town has the quarter (derived)")
		print(string.format("with a station: ring %d, pods %d", st.ring_road, st.culdesac_pods))
		-- (M4 fix: the player's station is an `extra` quarter: the drawn motifs are exactly those without it)
		eq(st.ring_road, late.ring_road, "the station takes no ring slot")
		eq(st.culdesac_pods, late.culdesac_pods, "the station takes no pods slot")
		for id = 1, 120 do eq(st.texts[id], late.texts[id], "town " .. id .. ": same drawn motifs with a station") end
		eq(MO.slotsTaken(resolve(F.flat, { id = 1, radius = 250, stations = { stationEast(650) } })), 0, "no slot taken")
		-- saved: the frame keeps the drawn ones, never the derived quarter; old frames none
		local a = resolve(F.flat, { id = 3, radius = 250, cap = 3000, year = 1975, stations = { stationEast(650) } })
		local fp = SV.frameParam(3, a, nil, nil)
		local dec = MO.decode(fp.mo) or {}
		for _, id in ipairs(dec) do ok(id ~= "station_quarter", "derived never saved") end
	end)
end)

test("ring road: a closed ring around the old core joined head on to its radial dead ends; outer districts gridded", function()
	F.withTownMotifs(function()
		local g = roundTown()
		local r, m, st, incs, stats, mp = run(g, F.flat, "ring_road", { radius = 250, n = 16, svg = "ring_road" })
		print(r.text)
		local geo = m.geo
		ok(geo ~= nil, tostring(m.planWhy))
		ok(geo.scan.closed, "a full ring planned (nothing blocks it)")
		ok(geo.R > 330, "beyond the core's dead ends: R " .. geo.R)
		ok(r.cover >= 0.9, "the ring closed: cover " .. r.cover)
		ok(r.radials >= 8, "joined to the core's radials: " .. r.radials)
		-- every ring street on the circle, never a large one; the stubs radial
		local n, list = motifEdges(incs, "mrr")
		ok(n >= 20, "ring edges " .. n)
		for _, e in ipairs(list) do
			ok(not tostring(e.template):find("large", 1, true), "large ring street")
			if e.key:sub(1, 4) == "mrr1" then
				for _, p in ipairs({ e.p0, e.p1 }) do near(G.dist(0, 0, p[1], p[2]), geo.R, 9, "on the circle") end
			elseif e.key:sub(1, 4) == "mrrS" then
				local h = G.heading(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
				local rad = G.heading(0, 0, (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2)
				ok(G.lineAngleDiff(h, rad) <= math.rad(50), "stub head on")
			end
		end
		-- the town's plan streets meet the ring only head on (none running alongside within ROOM)
		local ix = geo.lines[1].ix
		for _, pc in ipairs(mp.pieces) do
			if pc.motif == nil then
				local a, b = pc.pts[1], pc.pts[#pc.pts]
				for _, p in ipairs(G.resample(pc.pts, 10)) do
					local endNear = G.dist(p[1], p[2], a[1], a[2]) < TW.RR.ROOM + 6 or G.dist(p[1], p[2], b[1], b[2]) < TW.RR.ROOM + 6
					if not endNear then ok(L.nearest(ix, p[1], p[2], TW.RR.ROOM - 2) == nil, "plan street along the ring " .. pc.key) end
				end
			end
		end
		-- the districts outside: the 19th-c. extension with a grid look from the ring on
		eq(st.outer.id, "EU_EXTENSION")
		near(st.outer.from, m.ringR0, 1e-9)
		ok(st.outer.look >= TW.RR.LOOK, "outer look " .. st.outer.look)
		ok(ST.zone(st, geo.R + 50).gridness > ST.zone(st, 50).gridness, "straighter outside")
		rules("ring", g, st, incs, F.flat, "mrr")
		-- saved: the radius on the frame (rr); a later session keeps the ring where it is, also with a bigger town
		-- (as a drawn motif: a forced one is never saved)
		m.forced = nil
		local fp = SV.frameParam(5, st, mp, nil)
		near(fp.rr, geo.R, 0.05)
		local raw = select(1, SV.applyFrame(nil, fp))
		local fr = SV.frame(raw, 5)
		near(fr.ringR, geo.R, 0.05)
		eq(fr.motifs[1], "ring_road")
		local st2 = resolve(F.flat, { style = "EU_ORGANIC", radius = 420, frame = fr })
		local m2 = has(st2.motifs, "ring_road")
		ok(m2 and m2.saved, "saved motif")
		near(m2.ringR, geo.R, 0.05)
		local geo2 = TW.ringGeo(st2, m2, g, F.flat)
		near(geo2.R, geo.R, 0.05); eq(geo2.src, "saved")
		-- ... and without the frame field (an earlier session's ring found by its locked streets)
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if math.abs(G.dist(0, 0, a.x, a.y) - geo.R) < 2 and math.abs(G.dist(0, 0, b.x, b.y) - geo.R) < 2 then e.locked = true end
		end
		near(TW.ringFromLocked(st2, g), geo.R, 2)
		-- deterministic
		local a1 = TW.ringScan(st, roundTown(), F.flat, 360)
		local a2 = TW.ringScan(st, roundTown(), F.flat, 360)
		eq(#a1.joints, #a2.joints); eq(#a1.arcs, #a2.arcs)
	end)
end)

test("ring road: blocked by a street across the circle and a lake: arcs between radial dead ends, coverage logged", function()
	F.withTownMotifs(function()
		local g = roundTown()
		local a = OG.nearestNode(g, 330, 0, 60)
		local prev = a.id
		local across = {}
		for k = 1, 5 do
			local n = OG.addNode(g, nil, a.x + k * 70, a.y + k * 5, 20)
			local e = OG.addEdge(g, nil, prev, n.id, "small")
			across[e.id] = true
			prev = n.id
		end
		local lake = T.sampler(function(x, y) return (y > 330 and math.abs(x) < 200) and -3 or 20 end)
		local r, m, st, incs = run(g, lake, "ring_road", { radius = 250, n = 16, svg = "ring_blocked" })
		print(r.text)
		local geo = m.geo
		ok(geo ~= nil, tostring(m.planWhy))
		ok(not geo.scan.closed, "not a full ring")
		ok(geo.scan.blocked > 200, "blocked " .. geo.scan.blocked)
		ok(r.cover > 0.3 and r.cover < 0.9, "arcs built: cover " .. r.cover)
		ok(r.text:find("cover=", 1, true) and r.text:find("blocked=", 1, true), "coverage in the MOTIF line")
		-- every arc starts and ends at a joint (a radial dead end's stub, or a dead end on the circle)
		for _, ln in ipairs(geo.lines) do
			ok(#ln.arc.joints >= 2, "an arc between two joints")
		end
		-- never across the street, never onto the lake's shore
		for _, inc in ipairs(incs) do
			for _, e in ipairs(inc.edges) do
				if tostring(e.key):sub(1, 3) == "mrr" then
					ok(not T.wetAlong(lake, { e.p0, e.p1 }, st.waterSetback - 1), "ring on the shore")
				end
			end
		end
		rules("ring blocked", g, st, incs, lake, "mrr")
		-- nothing joins mid-edge: the street across keeps its two nodes' degrees (2 inside, 1 at the far end)
		for id in pairs(across) do ok(g.edgeById[id] ~= nil, "the street across stays") end
		-- no joints at all (no dead end near the circle, a closed grid): nothing planned, says why
		local grid = F.vanillaTown(nil, { n = 6, spacing = 80, stub = 0 })
		local _, mg = run(grid, F.flat, "ring_road", { radius = 250, n = 1 })
		ok(mg.geo == nil or #mg.geo.lines >= 1, "no ring or a ring with joints")
	end)
end)

test("station quarter: a small straight grid on the forecourt side, aligned with the station, linked to the town", function()
	F.withTownMotifs(function()
		local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
		local S = stationEast(650)
		local r, m, st, incs, stats, mp = run(g, F.flat, "station_quarter", { radius = 160, n = 16, stations = { S },
			svg = "station_quarter", extra = S.tracks })
		print(r.text)
		local geo = mp.stationGeo
		ok(geo ~= nil, tostring(mp.stationWhy))
		eq(geo.side, "town")
		ok(geo.n >= 3 and geo.n <= 4, "3x3 .. 4x4")
		ok(r.built >= 0.6 * r.planned, "grid sides built " .. r.built .. "/" .. r.planned)
		ok(geo.link ~= nil, "a Bahnhofstrasse")
		-- the grid: on the forecourt side (west of the station front), aligned with it, clear of the tracks
		local n, list = motifEdges(incs, "msq")
		ok(n >= 15, "quarter edges " .. n)
		local tidx = RM.segIndex(S.tracks)
		for _, e in ipairs(list) do
			if e.key:sub(1, 4) ~= "msqB" then
				for _, p in ipairs({ e.p0, e.p1 }) do ok(p[1] < S.front[1] - 10, "forecourt side " .. p[1]) end
				local h = G.heading(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
				local d0 = math.min(G.lineAngleDiff(h, 0), G.lineAngleDiff(h, math.pi / 2))
				ok(d0 < math.rad(2), "aligned " .. math.deg(d0))
				ok(not RM.segNear(tidx, (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2, TW.SQ.TRACK - 1), "beside the tracks")
			end
		end
		rules("station", g, st, incs, F.flat, "msq")
		-- the quarter's streets locked (derived kind with lock)
		local inc
		for _, x in ipairs(incs) do if motifEdges({ x }, "msq") > 0 then inc = x; break end end
		local keys, nk = D.lockKeys({ style = st, inc = inc })
		ok(keys and nk >= 1, "locked")
		-- the stations change: the master plan is rebuilt (the quarter follows the stations)
		local mp1 = core.masterPlan(g, st, { terrain = F.flat, stats = stats }, 8)
		eq(core.masterPlan(g, st, { terrain = F.flat, stats = stats }, 8), mp1, "cached")
		st.railStations, st.stationKey = {}, ""
		local mp2 = core.masterPlan(g, st, { terrain = F.flat, stats = stats }, 8)
		ok(mp2 ~= mp1, "rebuilt")
		eq(mp2.stationGeo, nil)
		for _, pc in ipairs(mp2.pieces) do ok(not tostring(pc.key):match("^msq"), "no quarter without a station") end
		eq(has(MO.derived(st), "station_quarter"), nil, "not eligible without a station")
		-- a forecourt facing away from the town (the tracks between; final-test round 2026-10-13, South Molton: nothing
		-- built): the quarter on the station's back, the town side, clear of the tracks and the station, linked to the town
		local _, _, _, incsA, _, mpA = run(F.vanillaTown(nil, { n = 4, spacing = 80 }), F.flat, "station_quarter",
			{ radius = 160, n = 12, stations = { stationEast(650, { fx = 1 }) } })
		ok(mpA.stationGeo and mpA.stationGeo.side == "back" and mpA.stationGeo.flipped, "away: on the back")
		ok(mpA.stationGeo.linkWhy ~= "away", "away: linked " .. tostring(mpA.stationGeo.linkWhy))
		local nA = 0
		for _, pc in ipairs(mpA.pieces) do
			if pc.motif == "station_quarter" then
				for _, p in ipairs(pc.pts) do ok(p[1] < 650 - 30 - TW.SQ.TRACK + 1, "away: on the town side " .. p[1]) end
				nA = nA + 1
			end
		end
		ok(nA >= 4, "away: quarter pieces " .. nA)
		ok(motifEdges(incsA, "msq") >= 3, "away: built " .. motifEdges(incsA, "msq"))
		-- (FLIP_AWAY off: the grid beyond the station as before, no link across the tracks)
		TW.SQ.FLIP_AWAY = false
		local _, _, _, _, _, mpB = run(F.vanillaTown(nil, { n = 4, spacing = 80 }), F.flat, "station_quarter",
			{ radius = 160, n = 1, stations = { stationEast(650, { fx = 1 }) } })
		TW.SQ.FLIP_AWAY = true
		ok(mpB.stationGeo and mpB.stationGeo.side == "away" and mpB.stationGeo.link == nil, "away (no flip): no link")
		for _, pc in ipairs(mpB.pieces) do
			if pc.motif == "station_quarter" then
				for _, p in ipairs(pc.pts) do ok(p[1] > 650, "away (no flip): beyond the station") end
			end
		end
		-- no direction known: toward the town
		local Sg = stationEast(650)
		Sg.fx, Sg.fy, Sg.front = nil, nil, nil
		local _, _, _, _, _, mpG = run(F.vanillaTown(nil, { n = 4, spacing = 80 }), F.flat, "station_quarter",
			{ radius = 160, n = 1, stations = { Sg } })
		eq(mpG.stationGeo and mpG.stationGeo.side, "guess")
	end)
end)

test("workers' terraces: parallel short rows beside a light works, free of the away-from-industry cost", function()
	F.withTownMotifs(function()
		local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
		local W = { 380, 360 }
		local info = IND.forTown({ { W[1], W[2], file = "industry/food_processing_plant/food_processing_plant.con" } }, 0, 0, 1905)
		local r, m, st, incs = run(g, F.flat, "workers_terraces", { radius = 160, n = 16, industry = info, year = 1905,
			svg = "workers_terraces", extra = { { W[1] - 20, W[2] - 20, W[1] + 20, W[2] + 20 } } })
		print(r.text)
		local geo = m.geo
		ok(geo ~= nil, tostring(m.planWhy))
		ok(#geo.rows >= 4, "rows planned " .. #geo.rows)
		ok(r.rows >= 3, "rows built " .. r.rows)
		-- the rows: parallel, square to the spine, evenly spaced, never nearer the works than CLEAR_WORKS
		local spine = G.heading(0, 0, W[1], W[2])
		local ss = {}
		for _, rw in ipairs(geo.rows) do
			local h = G.heading(rw.x0, rw.y0, rw.x1, rw.y1)
			near(G.lineAngleDiff(h, spine), math.pi / 2, math.rad(1), "square to the spine")
			ok(G.dist(rw.x1, rw.y1, W[1], W[2]) >= TW.WT.CLEAR_WORKS - 10, "clear of the works")
			ss[rw.s] = true
		end
		local sl = {}
		for s in pairs(ss) do sl[#sl + 1] = s end
		table.sort(sl)
		for i = 2, #sl do near(sl[i] - sl[i - 1], geo.sp, 0.5, "spacing") end
		ok(geo.sp >= TW.WT.SP[2] and geo.sp <= TW.WT.SP[3], "spacing " .. geo.sp)
		-- built inside the works' buffer (light 320 m): the motif's streets are free of the away cost / hold
		local inBuf = 0
		local n, list = motifEdges(incs, "mwt")
		for _, e in ipairs(list) do
			if G.dist(W[1], W[2], (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2) < 320 then inBuf = inBuf + 1 end
		end
		ok(inBuf >= 4, "terrace streets beside the works: " .. inBuf .. " of " .. n)
		local mp = core.masterPlan(g, st, { terrain = F.flat }, 8)
		for _, pc in ipairs(mp.pieces) do if pc.motif == "workers_terraces" then ok(pc.indFree, "indFree " .. pc.key) end end
		rules("terraces", g, st, incs, F.flat, "mwt")
		-- dense rows: the dose beside the build's rows
		local inc
		for _, x in ipairs(incs) do if motifEdges({ x }, "mwtR") > 0 then inc = x; break end end
		local pts = MO.dose(st, inc.edges, D.FILL_OFFSET, D.FILL_POINTS)
		ok(#pts >= 1, "dose points")
		-- heavy works beside the light one: none
		local mixed = IND.forTown({ { W[1], W[2], file = "industry/food_processing_plant/food_processing_plant.con" },
			{ W[1] + 250, W[2] + 200, file = "industry/chemical_plant/chemical_plant.con" } }, 0, 0, 1905)
		local _, mh = run(F.vanillaTown(nil, { n = 4, spacing = 80 }), F.flat, "workers_terraces", { radius = 160, n = 1,
			industry = mixed, year = 1905 })
		eq(mh.geo, nil); eq(mh.planWhy, "noWorks")
	end)
end)

test("cul-de-sac pods: a curving collector, short dead-end closes off both sides, green behind, locked", function()
	F.withTownMotifs(function()
		local results = {}
		for _, sty in ipairs({ "EU_EXTENSION", "EU_ORGANIC", "NORDIC", "NA_SUBURB" }) do
			local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
			local r, m, st, incs, stats, mp = run(g, F.flat, "culdesac_pods", { radius = 160, n = 24, year = 1970, style = sty,
				svg = "culdesac_pods_" .. sty })
			print(sty, r.text)
			local geo = m.geo
			ok(geo ~= nil, sty .. " " .. tostring(m.planWhy))
			ok(r.len >= 250, sty .. ": collector built " .. r.len)
			results[#results + 1] = r.closes
			-- built closes are dead ends (plain heads): the far end of every close's built edges
			local byClose = {}
			for _, inc in ipairs(incs) do
				for _, e in ipairs(inc.edges) do
					local ci = tostring(e.key):match("^mcpC(%d+)#")
					if ci then
						byClose[ci] = byClose[ci] or {}
						for _, p in ipairs({ e.p0, e.p1 }) do byClose[ci][#byClose[ci] + 1] = p end
					end
				end
			end
			for ci, pts in pairs(byClose) do
				local far, fd = nil, -1
				for _, p in ipairs(pts) do
					local d = L.nearest(geo.ix, p[1], p[2], 400) or 0
					if d > fd then far, fd = p, d end
				end
				local tip = OG.nearestNode(g, far[1], far[2], 1)
				ok(tip and OG.degree(g, tip.id) == 1, sty .. ": close " .. ci .. " ends in a dead end")
			end
			-- the green behind: no plan street of the town there, reserves added
			for _, pc in ipairs(mp.pieces) do
				if pc.motif == nil then
					local mx, my = G.polyAt(pc.pts, 0.5)
					local d = L.nearest(geo.ix, mx, my, geo.closeMax + TW.CP.GREEN)
					ok(not (d and G.dist(0, 0, mx, my) > geo.r0), sty .. ": plan street in the pods' zone " .. pc.key)
				end
			end
			ok(#st.greens >= #geo.closes, "green reserves behind the closes")
			rules("pods " .. sty, g, st, incs, F.flat, "mcp")
			-- locked
			local inc
			for _, x in ipairs(incs) do if motifEdges({ x }, "mcp") > 0 then inc = x; break end end
			local keys, nk = D.lockKeys({ style = st, inc = inc })
			ok(keys and nk >= 1, sty .. ": locked")
			-- the line stays put as the plan's extent grows (no smoothing over its length)
			local a = TW.podGeo(st, OG.new(), F.flat, 900, geo.k)
			local b = TW.podGeo(st, OG.new(), F.flat, 3000, geo.k)
			for i = 1, math.min(#a.line, #b.line) do
				near(a.line[i][1], b.line[i][1], 1e-6); near(a.line[i][2], b.line[i][2], 1e-6)
			end
		end
		local closes = 0
		for _, c in ipairs(results) do closes = closes + c end
		ok(closes >= 5, "closes built over the four styles: " .. closes)
	end)
end)

test("give-up: a close waiting for its collector's refused next piece is dropped after WAIT_GIVEUP plans (M4 fix)", function()
	F.withTownMotifs(function()
		local found = nil
		for k0 = 2, 10 do
			local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
			local st, stats = resolve(F.flat, { motif = "culdesac_pods", style = "EU_EXTENSION", radius = 160, year = 1970 })
			local opts = { terrain = F.flat, stats = stats, join = "deadEnd" }
			for k = 1, k0 do
				local inc = core.planIncrement(g, st, opts)
				if #inc.edges == 0 then break end
				OG.apply(g, inc, k)
			end
			eq(st._motifGaveUp, nil, "no give-up while the collector goes on")
			-- the game refuses every collector piece not built yet (s.exclude): the closes at its tip wait for nothing
			local mp = core.masterPlan(g, st, opts, 8)
			local ex = {}
			for _, pc in ipairs(mp.pieces) do
				if pc.motif == "culdesac_pods" and pc.motifLead then ex[pc.key] = true end
			end
			opts.exclude = ex
			local gave, at, built = nil, nil, {}
			for k = 1, SEL.WAIT_GIVEUP + 4 do
				local inc, rep = core.planIncrement(g, st, opts)
				if rep and rep.waitGaveUp then gave, at = rep.waitGaveUp, k end
				for _, e in ipairs(inc.edges) do built[tostring(e.key)] = true end
				if #inc.edges > 0 then OG.apply(g, inc, 100 + k) end
			end
			if gave then
				found = { gave = gave, at = at, st = st, g = g, k0 = k0, built = built }
				break
			end
		end
		ok(found ~= nil, "a close waited on a refused collector piece and was given up")
		if found then
			local w = found.gave[1]
			print(string.format("gave up %s (line %s) after %d plans, %d increments built first", w.key, tostring(w.line), w.plans,
				found.k0))
			eq(w.plans, SEL.WAIT_GIVEUP)
			ok(w.key:match("^mcpC%d+#"), "a close " .. w.key)
			ok(found.st._motifGaveUp[w.key], "dropped for the session")
			-- (dropped: never built, so the collector's tip stays a dead end)
			ok(not found.built[w.key], "the dropped close was built")
		end
	end)
end)

test("rules: map edge margin, lead limit from the houses, configs for every new node", function()
	F.withTownMotifs(function()
		-- the map's east edge 700 m out: the ring keeps MARGIN from it (arcs end there)
		local bounds = { -4000, -4000, 700, 4000 }
		local g = roundTown()
		local _, m, st, incs = run(g, F.flat, "ring_road", { radius = 250, n = 12, bounds = bounds })
		ok(m.geo ~= nil, tostring(m.planWhy))
		ok(not m.geo.scan.closed, "the edge cuts the ring")
		for _, inc in ipairs(incs) do
			for _, e in ipairs(inc.edges) do
				ok(MAP.edgeDist(bounds, e.p1[1], e.p1[2]) >= MAP.MARGIN - 1, "street near the map edge " .. tostring(e.key))
			end
		end
		-- house data: no new piece beyond the lead limit; the motifs still build
		local light = IND.forTown({ { 380, 360, file = "industry/food_processing_plant/food_processing_plant.con" } }, 0, 0, 1905)
		local cases = {
			{ "ring_road", roundTown, { radius = 250 }, "mrr" },
			{ "station_quarter", function() return F.vanillaTown(nil, { n = 4, spacing = 80 }) end,
				{ radius = 160, stations = { stationEast(520) } }, "msq" },
			{ "workers_terraces", function() return F.vanillaTown(nil, { n = 4, spacing = 80 }) end,
				{ radius = 160, industry = light, year = 1905 }, "mwt" },
			{ "culdesac_pods", function() return F.vanillaTown(nil, { n = 4, spacing = 80 }) end,
				{ radius = 160, year = 1970, style = "EU_EXTENSION" }, "mcp" },
		}
		local specs = 0
		for _, c in ipairs(cases) do
			local g2 = c[2]()
			local o = { motif = c[1], style = c[3].style or "EU_ORGANIC" }
			for k, v in pairs(c[3]) do o[k] = v end
			local st2, stats2 = resolve(F.flat, o)
			local motif = 0
			for k = 1, 10 do
				F.markBuilt(g2, 60 + 40 * k)
				local idx = SEL.housedIndexM(g2, SEL.MAX_LEAD_M)
				local inc = core.planIncrement(g2, st2, { terrain = F.flat, stats = stats2, join = "deadEnd" })
				if #inc.edges == 0 then break end
				for _, e in ipairs(inc.edges) do
					for _, p in ipairs({ e.p0, e.p1 }) do
						ok(SEL.housedDist(idx, p[1], p[2]) <= SEL.MAX_LEAD_M + 1, c[1] .. ": beyond the lead limit")
					end
					if tostring(e.key):sub(1, #c[4]) == c[4] then motif = motif + 1 end
				end
				OG.apply(g2, inc, k)
			end
			print(c[1] .. " with house data: " .. motif .. " motif edges")
			ok(motif > 0, c[1] .. ": the motif builds with house data too")
			-- crash rule
			local g3 = c[2]()
			local st3, stats3 = resolve(F.flat, o)
			specs = specs + crashRule(c[1], g3, st3, stats3, F.flat, 10)
		end
		ok(specs >= 30, specs .. " specs")
	end)
end)

test("driver: rail stations read once per refresh, per town within reach with their tracks; the plan follows", function()
	F.withTownMotifs(function()
		local lines, now, reads, obst = {}, 0, 0, 0
		local list = { stationEast(650), stationEast(5000) }
		list[1].tracks = nil
		local E = {
			nowUs = function() return now end,
			log = function(l) lines[#lines + 1] = l end,
			name = function() return "Town" end,
			railStations = function() reads = reads + 1; return list end,
			obstacles = function(x, y, r)
				obst = obst + 1
				return { segs = { { x + 25, y - 300, x + 25, y + 300, kind = "track" }, { x - 400, y, x - 300, y, kind = "street" } },
					boxes = {} }
			end,
		}
		local d = D.new(E)
		d.opts = { debug = true }
		local ext = { cx = 0, cy = 0, r = 160 }
		local rs = d:stationsFor(1, now, ext)
		eq(#rs, 1, "the far station is not this town's")
		eq(#rs[1].tracks, 1, "its tracks (streets left out)")
		eq(reads, 1); eq(obst, 1)
		now = 60e6
		d:stationsFor(1, now, ext)
		eq(reads, 1, "cached within the refresh")
		now = (D.STATION_REFRESH_S + 61) * 1e6
		d:stationsFor(1, now, ext)
		eq(reads, 2, "re-read after the refresh")
		eq(obst, 1, "tracks kept for a known station")
		local listing, town = false, false
		for _, l in ipairs(lines) do
			if l:find("STATIONS stations=", 1, true) then listing = true end
			if l:find("STATIONS town=1", 1, true) then town = true end
		end
		ok(listing and town, "STATIONS lines")
		-- the planner's style gets them; a change logs the quarter's pick
		local st = resolve(F.flat, { style = "EU_ORGANIC" })
		eq(st.stationKey, "")
		local job = { town = 1, ext = ext, baseStyle = st }
		lines = {}
		d:stationRefresh(job, st, now)
		eq(st.stationKey, TW.stationKey(rs))
		ok(has(MO.list(st), "station_quarter"), "the quarter now")
		local pick = false
		for _, l in ipairs(lines) do if l:find("kind=station_quarter", 1, true) and l:find("event=pick", 1, true) then pick = true end end
		ok(pick, "MOTIF pick line")
	end)
end)

test("engine: rail passenger stations from the station map, the construction's file, transform and box (fake api)", function()
	local ENG = ug_require(F.DIR .. "ot_engine.lua")
	local comps = {
		[100] = { CONSTRUCTION = { fileName = "station/rail/modular_station/modular_station.con", transf = {
			getTransl = function() return { x = 500, y = 20 } end,
			transformDirection = function(_, v) return { x = -v.y * 0 + 1 * 0 - 1 * 1 * -v.y * 0 - 1, y = 0 } end } },
			BOUNDING_VOLUME = { bbox = { min = { x = 470, y = -90 }, max = { x = 530, y = 130 } } } },
		[200] = { CONSTRUCTION = { fileName = "station/street/modular_street_station/modular_terminal.con", transf = {} } },
		[300] = { CONSTRUCTION = { fileName = "station/rail/modular_station/x.con", transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 40, 60, 0, 1 } } },
	}
	local stCon = { [1] = 100, [2] = 200, [3] = 300, [4] = 100, [5] = -1 }
	set_global("api", {
		type = { ComponentType = { CONSTRUCTION = "CONSTRUCTION", BOUNDING_VOLUME = "BOUNDING_VOLUME", STATION = "STATION" },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } },
		engine = {
			getComponent = function(e, ct) return comps[e] and comps[e][ct] end,
			getEntitiesWithComponent = function() return {} end,
			system = {
				stationSystem = { getTown2StationsMap = function() return { [10] = { 1, 2 }, [11] = { 3, 4, 5 } } end },
				streetConnectorSystem = { getConstructionEntityForStation = function(st) return stCon[st] end },
				stationGroupSystem = {},
			},
			util = { station = { isStationOfType = function(st, cargo) return st ~= 3 or cargo end } },
		},
	})
	local list = ENG.railStations()
	ok(list ~= nil, "listed")
	table.sort(list, function(a, b) return a.id < b.id end)
	eq(#list, 1, "one rail passenger station per construction (the street stop, the cargo one and duplicates out)")
	eq(list[1].id, 100)
	near(list[1].x, 500, 1e-9); near(list[1].y, 20, 1e-9)
	ok(list[1].fx ~= nil, "forecourt direction")
	near(list[1].front[1], 500 + list[1].fx * 17, 1e-9)
	eq(list[1].box[1], 470)
	-- the transform read as 16 numbers: the origin and local -Y
	comps[300].CONSTRUCTION.fileName = "station/rail/modular_station/x.con"
	set_global("api", api)
	local fake = api
	fake.engine.util.station.isStationOfType = function() return true end
	local l2 = ENG.railStations()
	table.sort(l2, function(a, b) return a.id < b.id end)
	eq(#l2, 2)
	near(l2[2].x, 40, 1e-9); near(l2[2].y, 60, 1e-9)
	near(l2[2].fx, 0, 1e-9); near(l2[2].fy, -1, 1e-9)
	set_global("api", nil)
end)
