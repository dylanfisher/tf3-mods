-- Terrain / water motifs (ot_motif_land, phase M1 of plans/square_organic_towns/MOTIFS_BRIEF.md, 2026-10-13): the hill
-- climb, the valley fishbone, the harbour crescent and the fishing village. Eligibility on the synthetic fixtures (only
-- where the terrain fits), deterministic picks and saves, each motif's pattern metric after 12 simulated increments
-- (join "deadEnd" as in game: new streets end only at dead ends), and the rules (no crossings, no water, grades, local
-- widths, map edge, lead limit, configs for every new node).
-- Set OT_SVG=<dir> to dump an SVG per motif run (the plan grey, the motif's pieces orange, the built streets black).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
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

local EU = "::/names/europe/europe.names"
local KINDS = { "hill_climb", "valley_fishbone", "harbour_crescent", "fishing_village" }
local NEW_SMALL = "::/infrastructure/street/town/town_new_small.street_template"

local function has(list, id) for _, m in ipairs(list or {}) do if m.id == id then return m end end end

local function resolve(sampler, o)
	o = o or {}
	local stats = T.stats(sampler, 0, 0, 600, 24)
	local inputs = I.build({ townId = o.id or 5, pos = { 0, 0 }, capacity = o.cap or 1500, year = o.year or 1900,
		nameList = EU, terrain = stats, forceStyle = o.style, autoStyle = o.style == nil, motif = o.motif,
		radius = o.radius or 160, bounds = o.bounds, frame = o.frame, shape = o.shape })
	return ST.resolve(inputs), stats, inputs
end

local function ctxOf(st, stats, o)
	o = o or {}
	return { style = st, terrain = stats, tier = o.tier or 2, year = o.year or 1900 }
end

local SVGDIR = os.getenv("OT_SVG")
local function svg(name, g, mp, sampler)
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
			local h = T.height(sampler, x, y)
			local c = T.isWater(sampler, x, y) and "#9cf"
				or string.format("#%02x%02x%02x", 255 - math.min(120, math.floor(h)), 255 - math.min(80, math.floor(h / 2)), 220)
			f:write(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>', X(x - W / 100), Y(y + W / 100),
				S / 50 + 0.5, S / 50 + 0.5, c))
		end
	end
	for _, pc in ipairs(mp and mp.pieces or {}) do
		local d = {}
		for i, p in ipairs(pc.pts) do d[#d + 1] = (i == 1 and "M" or "L") .. string.format("%.1f %.1f", X(p[1]), Y(p[2])) end
		f:write(string.format('<path d="%s" stroke="%s" stroke-width="%s" fill="none"/>', table.concat(d, " "),
			pc.motif and "#f80" or "#ddd", pc.motif and 2 or 1))
	end
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#000" stroke-width="2"/>', X(a.x), Y(a.y),
			X(b.x), Y(b.y)))
	end
	f:write("</svg>")
	f:close()
end

--- A forced motif on a vanilla core at the origin, n increments (join "deadEnd" unless o.join): measure, record, graph,
--- style, increments, stats.
local function run(sampler, motif, o)
	o = o or {}
	local st, stats = resolve(sampler, { motif = motif, style = o.style or "EU_ORGANIC", radius = o.radius, cap = o.cap,
		bounds = o.bounds })
	local g = F.vanillaTown(nil, { n = o.core or 4, spacing = o.spacing or 80 })
	local incs = core.simulate(g, st, { terrain = sampler, stats = stats, join = o.join or "deadEnd" }, o.n or 12)
	local m = has(st.motifs, motif)
	local r = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = {}, sampler = sampler, MT = MT, SH = SH })
	if o.svg then svg(o.svg, g, core.masterPlan(g, st, { terrain = sampler, stats = stats }, 8), sampler) end
	return r, m, g, st, incs, stats
end

--- Rules every motif run keeps: no crossing streets, nothing on / beside water, no new street steeper than maxSlope, the
--- motif's streets local widths (no large template), every new node of every increment a config (crash rule).
local function rules(name, g, st, incs, sampler)
	local e1, e2 = F.crossingPair(g)
	ok(e1 == nil, name .. ": crossing edges")
	ok(F.minAngle(g) >= 15, name .. ": min angle " .. F.minAngle(g))
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			local pts = { { e.p0[1], e.p0[2] }, { e.p1[1], e.p1[2] } }
			ok(not T.wetAlong(sampler, pts, 0), name .. ": edge on water " .. tostring(e.key))
			ok(T.grade(sampler, e.p0[1], e.p0[2], e.p1[1], e.p1[2]) <= st.maxSlope + 0.01,
				name .. ": steep edge " .. tostring(e.key))
			if type(e.key) == "string" and e.key:match("^m[hvf][cfbv]") then
				ok(not tostring(e.template):find("large", 1, true), name .. ": wide motif street " .. e.key)
			end
		end
	end
end

local function motifEdges(incs, prefix)
	local n = 0
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			if type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then n = n + 1 end
		end
	end
	return n
end

---------------------------------------------------------------------------

test("registry: the four M1 kinds are drawn kinds with append-only save indices", function()
	eq(MO.IDS[1], "crescent"); eq(MO.IDS[2], "hill_road")
	for i, id in ipairs(KINDS) do
		eq(MO.IDS[i + 2], id)
		local k = MO.BY_ID[id]
		ok(k and not k.derived and k.plan and k.measure and k.eligible, id)
	end
	eq(MO.BY_ID.hill_climb.group, MO.BY_ID.valley_fishbone.group)
	eq(MO.BY_ID.harbour_crescent.group, MO.BY_ID.fishing_village.group)
	ok(MO.BY_ID.harbour_crescent.dose ~= nil, "the harbour doses its row")
	-- frames: the new indices round-trip
	local v = MO.encode({ { id = "hill_climb" }, { id = "harbour_crescent" } })
	eq(v, 3 + 64 * 5)
	local d = MO.decode(v)
	eq(d[1], "hill_climb"); eq(d[2], "harbour_crescent")
end)

test("eligibility: each kind only where its terrain fits", function()
	local fx = { flat = F.flat, plane = F.plane(0.09, 0), terraces = F.terraces, valley = F.valley(0), coast = F.coast(),
		river = F.river(), bay = F.bay(), shore = F.shoreSlope(), ridge = F.valley(0, true) }
	local want = {
		flat = {}, coast = {}, river = {},
		plane = { hill_climb = true }, terraces = { hill_climb = true },
		valley = { hill_climb = true, valley_fishbone = true },
		ridge = {},   -- (a crest: the ridge street is M4)
		bay = { harbour_crescent = true },
		shore = { hill_climb = true, fishing_village = true },
	}
	local lines = {}
	for name, sampler in pairs(fx) do
		local st, stats = resolve(sampler, { style = "EU_ORGANIC" })
		local parts = {}
		for _, id in ipairs(KINDS) do
			local s, why = MO.BY_ID[id].eligible(ctxOf(st, stats))
			s = s or 0
			if s < MO.MIN_SCORE then s = 0 end   -- (the registry's floor, ot_motif MIN_SCORE: a trace is none)
			parts[#parts + 1] = string.format("%s=%.2f", id, s)
			if want[name][id] then ok(s > 0, name .. " " .. id .. " should be eligible") ; ok(type(why) == "string", why)
			else eq(s, 0, name .. " " .. id .. " should not be eligible") end
		end
		lines[#lines + 1] = name .. " " .. table.concat(parts, " ")
	end
	table.sort(lines)
	for _, l in ipairs(lines) do print(l) end
	-- strong where the land calls for it
	local st, stats = resolve(F.valley(0), { style = "EU_ORGANIC" })
	ok(MO.BY_ID.valley_fishbone.eligible(ctxOf(st, stats)) >= 0.9)
	st, stats = resolve(F.bay(), { style = "EU_ORGANIC" })
	ok(MO.BY_ID.harbour_crescent.eligible(ctxOf(st, stats)) >= 0.9)
	-- size / era / style: no fishing village for a big town, less late; grid styles weigh less
	st, stats = resolve(F.shoreSlope(), { style = "EU_ORGANIC" })
	local small = MO.BY_ID.fishing_village.eligible(ctxOf(st, stats, { tier = 1 }))
	eq(MO.BY_ID.fishing_village.eligible(ctxOf(st, stats, { tier = 4 })), 0)
	ok(MO.BY_ID.fishing_village.eligible(ctxOf(st, stats, { tier = 1, year = 1970 })) < small)
	local grid, gstats = resolve(F.plane(0.09, 0), { style = "NA_GRID" })
	local org, ostats = resolve(F.plane(0.09, 0), { style = "EU_ORGANIC" })
	ok(MO.BY_ID.hill_climb.eligible(ctxOf(grid, gstats)) < MO.BY_ID.hill_climb.eligible(ctxOf(org, ostats)))
	-- a shore town (its strip and row) gets neither harbour nor village
	local sh = { id = "shore" }
	local cst = { id = "EU_ORGANIC", shape = sh }
	st, stats = resolve(F.bay(), { style = "EU_ORGANIC" })
	cst.block = st.block
	eq(MO.BY_ID.harbour_crescent.eligible({ style = cst, terrain = stats, tier = 2, year = 1900 }), 0)
end)

test("picks: deterministic per town, eligible sites only, one per group, saved on the frame", function()
	local drawn = { valley = 0, flat = 0 }
	for id = 1, 120 do
		local a = resolve(F.valley(0), { id = id })
		local b = resolve(F.valley(0), { id = id })
		eq(MO.text(a.motifs), MO.text(b.motifs), "same town, same motifs")
		local land = 0
		for _, m in ipairs(a.motifs) do
			if MO.BY_ID[m.id].group == "land" then land = land + 1 end
			ok(m.id ~= "harbour_crescent" and m.id ~= "fishing_village", "no shore motif in a dry valley")
		end
		ok(land <= 1, "one land motif at most: " .. MO.text(a.motifs))
		if land > 0 then drawn.valley = drawn.valley + 1 end
		local f = resolve(F.flat, { id = id })
		drawn.flat = drawn.flat + #f.motifs
	end
	print(string.format("valley towns with a land motif: %d of 120; flat towns with a drawn motif: %d", drawn.valley, drawn.flat))
	eq(drawn.flat, 0, "flat land: no terrain motif")
	-- (final-test round: SLOT_P 0.9 x best / P_FULL; 40-100 of 120 with 0.6 x best before)
	ok(drawn.valley >= 70 and drawn.valley <= 118, "valley: " .. drawn.valley)
	-- the frame keeps it; a reload draws nothing new; an old frame has none
	local town, st
	for id = 1, 60 do
		local s = resolve(F.valley(0), { id = id })
		if #s.motifs > 0 then town, st = id, s; break end
	end
	local fp = SV.frameParam(town, st, nil, 900)
	ok(fp.mo ~= nil)
	local fr = SV.frame(SV.normalize(SV.applyFrame(SV.applyInit(nil, { known = {} }), fp)), town)
	local again = resolve(F.valley(0), { id = town, frame = fr })
	eq(MO.text(MO.list(again)):gsub(":saved", ":drawn"):gsub("%d%.%d%d", "x"), MO.text(MO.list(st)):gsub("%d%.%d%d", "x"))
	local old = SV.frame(SV.applyFrame(nil, { town = town, a = 0.1, x = 0, y = 0 }), town)
	eq(#resolve(F.valley(0), { id = town, frame = old }).motifs, 0, "old save: no drawn motif")
end)

test("hill climb: one gentle street up the slope, terrace loops on the shelves, green corridor", function()
	local r, m, g, st, incs = run(F.terraces, "hill_climb", { svg = "hill_climb" })
	local geo = m.geo
	print("terraces: " .. r.text, "anchors " .. tostring(geo.anchors))
	ok(geo.ix.len >= 500, "planned climb " .. geo.ix.len)
	ok(geo.grade <= st.maxSlope, "gentle: steepest " .. geo.grade)
	ok(geo.climb >= 25, "climbs " .. geo.climb)
	ok(#geo.terraces >= 1 and #geo.terraces <= 3, "terraces planned " .. #geo.terraces)
	ok(r.len >= 350, "climb built " .. r.len)
	ok(r.climb >= 20, "climb built up " .. r.climb)
	ok(r.terraces >= 1, "a terrace loop built")
	rules("hill_climb", g, st, incs, F.terraces)
	-- the corridor beyond the town: no plan street beside the climb except the motif's own
	local mp = core.masterPlan(g, st, { terrain = F.terraces, stats = T.stats(F.terraces, 0, 0, 600, 24) }, 8)
	local intruders = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == nil then
			local mx, my = G.polyAt(pc.pts, 0.5)
			if G.dist(0, 0, mx, my) > geo.r0 + 10 and L.nearest(geo.ix, mx, my, geo.corridor - 5) then intruders = intruders + 1 end
		end
	end
	eq(intruders, 0, "plan streets in the climb's corridor")
	-- a uniform 9 % plane: the climb crosses it at the target grade; no shelf, no terrace
	local r2, m2, g2, st2, incs2 = run(F.plane(0.09, 0), "hill_climb")
	print("plane: " .. r2.text)
	ok(r2.len >= 300 and #m2.geo.terraces == 0, r2.text)
	ok(m2.geo.grade <= 0.065, "grade at the target " .. m2.geo.grade)
	rules("hill_climb plane", g2, st2, incs2, F.plane(0.09, 0))
	-- a valley: up one side, along the contour where it gets steep (no hairpin)
	local r3 = run(F.valley(0), "hill_climb")
	print("valley: " .. r3.text)
	ok(r3.len >= 300, r3.text)
	-- deterministic: the same plan twice
	local a = L.climbGeo(st, F.terraces, 1500)
	local b = L.climbGeo(st, F.terraces, 1500)
	eq(#a.line, #b.line); near(a.ix.len, b.ix.len, 1e-9); eq(#a.terraces, #b.terraces)
	-- no hairpins: the heading never turns back more than DEV from the uphill bearing
	for k = 2, #a.line do
		local h = G.heading(a.line[k - 1][1], a.line[k - 1][2], a.line[k][1], a.line[k][2])
		ok(G.angleDiff(h, a.bearing) <= L.HC.DEV + math.rad(12), "hairpin at " .. k)
	end
	-- flat land: no climb (a forced one plans nothing and says why)
	local _, mf = run(F.flat, "hill_climb", { n = 2 })
	eq(mf.geo, nil)
	eq(mf.planWhy, "flat")
end)

test("valley fishbone: a spine along the floor, ribs up both slopes at intervals, stopping where it gets steep", function()
	local r, m, g, st, incs = run(F.valley(0), "valley_fishbone", { svg = "valley_fishbone" })
	local geo = m.geo
	print(r.text, "rib spacing planned " .. geo.sp)
	ok(r.len >= 600, "spine built " .. r.len)
	ok(r.ribs >= 12, "ribs " .. r.ribs)
	ok(r.left >= 5 and r.right >= 5, "both sides " .. r.left .. "+" .. r.right)
	ok(r.spacing >= 0.8 * geo.sp and r.spacing <= 1.6 * geo.sp, "spacing " .. r.spacing .. " vs " .. geo.sp)
	-- the spine stays on the floor (the valley axis y = 0), the ribs stop before the steep walls
	for _, p in ipairs(geo.line) do ok(math.abs(p[2]) < 30, "spine off the floor at " .. p[1] .. "," .. p[2]) end
	for _, rb in ipairs(geo.ribs) do
		ok(rb.len <= geo.ribMax + 1e-6, "rib too long")
		local steepNext = T.grade(F.valley(0), rb.x1, rb.y1, rb.x1 + (rb.x1 - rb.x0) / rb.len * 10,
			rb.y1 + (rb.y1 - rb.y0) / rb.len * 10) > L.VF.RIB_GRADE * st.maxSlope
		ok(steepNext or rb.len + 10 > geo.ribMax, "a rib stopped short of the steep ground")
	end
	rules("valley_fishbone", g, st, incs, F.valley(0))
end)

test("harbour crescent: the bay's curve covered by the waterfront street, short streets inland, dose on the row", function()
	local r, m, g, st, incs = run(F.bay(), "harbour_crescent", { svg = "harbour_crescent" })
	local geo = m.geo
	print(r.text)
	ok(geo.bay.ratio >= 0.3, "a bay " .. geo.bay.ratio)
	ok(geo.planCover >= 0.9, "planned cover " .. geo.planCover)
	ok(r.cover >= 0.7, "built cover " .. r.cover)
	ok(r.lanes >= 8, "lanes " .. r.lanes)
	eq(st.shoreFront, nil, "the crescent replaces the promenade")
	ok(st.waterPremium ~= nil, "streets near the water first")
	-- the crescent keeps its setback; the lanes go inland (away from the water)
	for _, p in ipairs(G.resample(geo.line, 20)) do ok(not T.wetAlong(F.bay(), { p, p }, st.waterSetback), "crescent near water") end
	for _, ln in ipairs(geo.lanes) do
		ok(T.clearance(F.bay(), ln.x1, ln.y1, 400, 5) > T.clearance(F.bay(), ln.x0, ln.y0, 400, 5), "lane toward the water")
	end
	rules("harbour_crescent", g, st, incs, F.bay())
	-- the driver's dose: points beside the build's crescent streets, on the land side
	local inc
	for _, x in ipairs(incs) do if motifEdges({ x }, "mhb#") > 0 then inc = x; break end end
	ok(inc, "an increment with crescent streets")
	local job = { style = st, spec = { edges = inc.edges } }
	local kind, why = D.fillKind(job, {}, { actual = 100, target = 100, initial = 100 }, nil, 50, 0)
	eq(kind, "dose"); eq(why, "motif")
	local pts = D.fillPoints("dose", inc.edges, st.shape, nil, F.bay(), st)
	ok(#pts >= 1 and #pts <= D.FILL_POINTS, "points " .. #pts)
	for _, p in ipairs(pts) do
		local d, _, side = L.nearest(geo.ix, p[1], p[2], 40)
		ok(d and side > 0 and not T.isWater(F.bay(), p[1], p[2]), "dose on the land side")
	end
	-- a town without a dose motif keeps its old fill decision
	eq(select(2, D.fillKind({ style = { shape = { id = "compact" } }, spec = { edges = inc.edges } }, {}, {}, nil, 50, 0)),
		"unshaped")
end)

test("fishing village: parallel streets straight down the slope to a waterfront street", function()
	local r, m, g, st, incs = run(F.shoreSlope(), "fishing_village", { core = 3, spacing = 70, cap = 400,
		svg = "fishing_village" })
	local geo = m.geo
	print(r.text)
	ok(#geo.streets >= 3, "streets planned " .. #geo.streets)
	ok(r.streets >= 3, "streets built down to the water " .. r.streets)
	ok(r.len >= 150, "waterfront built " .. r.len)
	-- parallel, straight, up the slope (away from the water), evenly spaced
	for i, s in ipairs(geo.streets) do
		local h = G.heading(s.x0, s.y0, s.x1, s.y1)
		ok(G.angleDiff(h, geo.heading) < 1e-6, "parallel")
		ok(T.height(F.shoreSlope(), s.x1, s.y1) > T.height(F.shoreSlope(), s.x0, s.y0) + 3, "uphill")
		if i > 1 then near(s.s - geo.streets[i - 1].s, geo.sp, 1e-6) end
	end
	eq(st.shoreFront, nil, "the village waterfront replaces the promenade")
	rules("fishing_village", g, st, incs, F.shoreSlope())
end)

test("rules: map edge margin, lead limit from the houses, configs for every new node", function()
	-- the map's east edge 650 m out: the climb (heading east-south-east) stops 400 m before it
	local bounds = { -4000, -4000, 650, 4000 }
	local r, m, g, st, incs = run(F.terraces, "hill_climb", { bounds = bounds })
	for _, p in ipairs(m.geo.line) do ok(MAP.edgeDist(bounds, p[1], p[2]) >= MAP.MARGIN - 45, "climb near the map edge") end
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			ok(MAP.edgeDist(bounds, e.p1[1], e.p1[2]) >= MAP.MARGIN - 1, "street near the map edge " .. tostring(e.key))
		end
	end
	-- house data: no new piece farther than the lead limit from a housed street (the climb leads by its housed stretch)
	for _, c in ipairs({ { F.terraces, "hill_climb" }, { F.valley(0), "valley_fishbone" }, { F.bay(), "harbour_crescent" } }) do
		local st2, stats2 = resolve(c[1], { motif = c[2], style = "EU_ORGANIC" })
		local g2 = F.vanillaTown(nil, { n = 4, spacing = 80 })
		local motif = 0
		for k = 1, 8 do
			F.markBuilt(g2, 40 + 30 * k)
			local idx = SEL.housedIndexM(g2, SEL.MAX_LEAD_M)
			local inc = core.planIncrement(g2, st2, { terrain = c[1], stats = stats2, join = "deadEnd" })
			if #inc.edges == 0 then break end
			for _, e in ipairs(inc.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do
					ok(SEL.housedDist(idx, p[1], p[2]) <= SEL.MAX_LEAD_M + 1, c[2] .. ": beyond the lead limit")
				end
				if type(e.key) == "string" and e.key:match("^m[hvf][cfbv]") then motif = motif + 1 end
			end
			OG.apply(g2, inc, k)
		end
		ok(motif > 0, c[2] .. ": the motif builds with house data too")
	end
	-- crash rule: every new node of a motif increment gets a config, every lane index valid
	local specs = 0
	for _, c in ipairs({ { F.terraces, "hill_climb" }, { F.valley(0), "valley_fishbone" }, { F.bay(), "harbour_crescent" },
		{ F.shoreSlope(), "fishing_village" } }) do
		local st3, stats3 = resolve(c[1], { motif = c[2], style = "EU_ORGANIC" })
		local g3 = F.vanillaTown(nil, { n = 3, spacing = 70 })
		for k = 1, 6 do
			local inc = core.planIncrement(g3, st3, { terrain = c[1], stats = stats3, join = "deadEnd" })
			if #inc.edges == 0 then break end
			local inf = { nodes = {}, sources = {}, fallback = 902 }
			for _, j in ipairs(inc.joins) do
				local edges = {}
				for _, eid in ipairs(g3.adj[j.node] or {}) do edges[#edges + 1] = eid end
				inf.nodes[j.node] = { hasConfig = true, edges = edges, lanes = 4, src = edges[1] or 902, template = NEW_SMALL }
			end
			local spec, err = PR.build(inc, inf)
			ok(spec ~= nil, c[2] .. " " .. tostring(err))
			if spec then
				specs = specs + 1
				local cfg = {}
				for _, cc in ipairs(spec.cfgAdd) do cfg[cc.node] = true end
				for _, nd in ipairs(spec.nodes) do ok(cfg[nd.entity], c[2] .. " node without a config") end
				ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
			end
			OG.apply(g3, inc, k)
		end
	end
	ok(specs >= 16, specs .. " specs")
end)

test("anchors: a line leaving the town links to a dead end (straight on, or a short arc without a kink)", function()
	local st = resolve(F.terraces, { motif = "hill_climb", style = "EU_ORGANIC" })
	local geo = L.climbGeo(st, F.terraces, 1500)
	local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
	local an = L.anchors(g, st, geo.ix, 0, { 1 }, F.terraces)
	eq(#an, 1)
	local a = an[1]
	ok(a.link, "a link street")
	-- the arc leaves the dead end along its street and keeps the template radius
	local nd = OG.nearestNode(g, a.x, a.y, 1)
	local e = g.edgeById[g.adj[nd.id][1]]
	local out = G.wrap(OG.headingFrom(g, e, nd.id) + math.pi)
	ok(G.angleDiff(G.atan2(a.pts[1][4], a.pts[1][3]), out) < 1e-6, "leaves straight on")
	ok(G.minDiscreteRadius(a.pts) >= L.ANCHOR.LINK_R - 1, "radius " .. G.minDiscreteRadius(a.pts))
	ok(L.linkClear(g, a.pts, nd.id))
	-- a dead end lying on the line: the line continues from it
	local g2 = OG.new()
	local x1, y1 = L.at(geo.ix, 260)
	local x0, y0 = L.at(geo.ix, 200)
	local n0 = OG.addNode(g2, nil, 0, 0, 20)
	local n1 = OG.addNode(g2, nil, x0, y0, 20)
	local n2 = OG.addNode(g2, nil, x1, y1, 20)
	OG.addEdge(g2, nil, n0.id, n1.id, "small"); OG.addEdge(g2, nil, n1.id, n2.id, "small")
	local an2 = L.anchors(g2, st, geo.ix, 0, { 1 }, F.terraces)
	eq(#an2, 1); eq(an2[1].link, false); near(an2[1].s, 260, 2)
end)

test("plan: motif pieces carry their limits; branches are chosen with the main line (dead ends only in game)", function()
	local st, stats = resolve(F.valley(0), { motif = "valley_fishbone", style = "EU_ORGANIC" })
	local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
	local mp = core.masterPlan(g, st, { terrain = F.valley(0), stats = stats }, 8)
	local main, branch, classes = 0, 0, {}
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == "valley_fishbone" then
			classes[pc.class] = true
			if pc.motifLead then main = main + 1 end
			if pc.motifBranch then branch = branch + 1 end
			ok(pc.costK and pc.costK < 1, "cheaper")
			ok(mp.junctions[pc.a] and mp.junctions[pc.b], "junctions")
		end
	end
	ok(main > 5 and branch >= 12, main .. " main, " .. branch .. " branches")
	ok(not classes.main, "no main-class motif piece")
	-- every increment's ribs leave junctions the spine passes in the same increment (or already passed)
	local incs = core.simulate(g, st, { terrain = F.valley(0), stats = stats, join = "deadEnd" }, 6)
	local ribs = motifEdges(incs, "mvfR")
	ok(ribs >= 8, "ribs built " .. ribs)
end)
