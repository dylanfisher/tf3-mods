-- Forest lanes (round R2, 2026-10-13; ot_lane): stretches of a planned street through forest with trees within lot
-- depth on both sides go out as locked country lanes (no houses); the street's other edges stay town streets.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local FO = ug_require(F.DIR .. "ot_forest.lua")
local LN = ug_require(F.DIR .. "ot_lane.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

-- a forest belt x in [200, 500] (all y)
local function belt(x, _y)
	if x >= 200 and x <= 500 then return 200 end
	return 0
end
local function fo(mode)
	local fg = FO.fromFunction(0, 0, belt, 1200, 50)
	return { grid = fg, mode = mode or "hug", share = fg.share }
end

--- An increment with one street east along y = 0 from x = 0 to 700 in 7 edges of 100 m (new nodes -1..-8; the first
--- node an existing dead end 5 when join).
local function streetInc(join, y)
	y = y or 0
	local inc = { edges = {}, nodes = {} }
	for k = 0, 6 do
		local n0 = (k == 0 and join) and 5 or -(k + 1)
		inc.edges[#inc.edges + 1] = { entity = -(100 + k), node0 = n0, node1 = -(k + 2), p0 = { k * 100, y, 0 },
			p1 = { (k + 1) * 100, y, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 }, class = "small", street = 1, key = "s1",
			template = "::/infrastructure/street/town/town_old_small.street_template" }
	end
	for k = 1, 8 do inc.nodes[#inc.nodes + 1] = { entity = -k, x = (k - 1) * 100, y = y, z = 0 } end
	return inc
end

local function style(mode, o)
	o = o or {}
	return { forest = fo(mode), seed = o.seed or 7, year = o.year or 1910, newTemplates = o.newT, metro = o.metro }
end

test("runs: the wooded middle of a street, never its first / last edge, both nodes new", function()
	local inc = streetInc(true)
	local runs = LN.runs(fo("hug"), inc)
	eq(#runs, 1)
	local r = runs[1]
	-- edges 3..5 (x 200-500) lie in the belt; edge 3 (200-300) reads the smoothed edge cell
	ok(#r.edges >= 2 and #r.edges <= 3, "the belt's edges: " .. #r.edges)
	for _, i in ipairs(r.edges) do
		local e = inc.edges[i]
		ok(e.p0[1] >= 200 and e.p1[1] <= 500, "inside the belt: " .. e.p0[1])
	end
	ok(r.len >= LN.MIN_M)
	-- a street wholly inside the forest, its ends included: only the middle edges
	local inc2 = streetInc(false, 0)
	for k, e in ipairs(inc2.edges) do e.p0[1], e.p1[1] = 220 + (k - 1) * 40, 220 + k * 40 end
	local r2 = LN.runs(fo("hug"), inc2)
	eq(#r2, 1)
	for _, i in ipairs(r2[1].edges) do ok(i > 1 and i < #inc2.edges, "never the first or last edge (a tip)") end
	-- a bridge edge breaks a run
	local inc3 = streetInc(false)
	inc3.edges[4].bridge = true
	for _, rr in ipairs(LN.runs(fo("hug"), inc3)) do
		for _, i in ipairs(rr.edges) do ok(i ~= 4, "no bridge edge") end
	end
end)

test("chance: hug more, clear fewer, none / metro never, later eras fewer", function()
	local ph = LN.chance(style("hug"))
	local pc = LN.chance(style("clear"))
	eq(LN.chance(style("none")), 0)
	eq(LN.chance(style("hug", { metro = true })), 0)
	ok(ph > pc and pc > 0, "hug " .. ph .. " > clear " .. pc)
	ok(LN.chance(style("hug", { year = 1990 })) < ph, "late era fewer")
	near(ph, LN.P * LN.MODE_F.hug, 1e-9)
end)

test("mark: seeded about 1 in 3 crossings for hug towns, the era's template, the per-town cap, strip", function()
	local n, total = 0, 200
	for seed = 1, total do
		local inc = streetInc(true)
		local marked = LN.mark(inc, style("clear", { seed = seed }), { seed = seed })
		if #marked > 0 then n = n + 1 end
	end
	local share = n / total
	print(string.format("      clear towns: %.2f of the crossings become lanes", share))
	ok(share > 0.08 and share < 0.3, "clear: sparingly " .. share)
	local nh = 0
	for seed = 1, total do
		if #LN.mark(streetInc(true), style("hug", { seed = seed }), { seed = seed }) > 0 then nh = nh + 1 end
	end
	print(string.format("      hug towns: %.2f", nh / total))
	ok(nh / total > 0.35 and nh / total < 0.65, "hug: about half " .. nh / total)
	-- a seed that marks: the template by era, the flags, the cap, strip
	local seed
	for sd = 1, total do
		if #LN.mark(streetInc(true), style("hug", { seed = sd }), { seed = sd }) > 0 then seed = sd; break end
	end
	ok(seed ~= nil)
	local inc = streetInc(true)
	local marked = LN.mark(inc, style("hug", { seed = seed, newT = true }), { seed = seed })
	eq(marked[1].template, LN.TEMPLATE.new)
	ok(inc.lanes > 0)
	for i, e in ipairs(inc.edges) do
		if e.forestLane then ok(i > 1 and i < #inc.edges) end
	end
	local _, sk = LN.mark(streetInc(true), style("hug", { seed = seed }), { seed = seed, used = LN.MAX_PER_TOWN })
	eq(sk[1].skip, "cap")
	local _, sk2 = LN.mark(streetInc(true), style("hug", { seed = seed }), { seed = seed, ok = function() return false end })
	eq(sk2[1].skip, "template")
	ok(LN.strip(inc) > 0)
	eq(inc.lanes, nil)
	for _, e in ipairs(inc.edges) do eq(e.forestLane, nil) end
end)

test("proposal: lane edges take the country template, locked, 4 lanes; the others stay town streets", function()
	local inc = streetInc(true)
	inc.edges[4].forestLane = LN.TEMPLATE.old
	inc.edges[1].forestLane = LN.TEMPLATE.old   -- a joined edge never becomes a lane
	local info = { nodes = { [5] = { hasConfig = true, edges = { 50 }, lanes = 4, src = 50,
		template = "::/infrastructure/street/town/town_old_small.street_template" } },
		sources = { ["::/infrastructure/street/town/town_old_small.street_template"] = 50 }, fallback = 50 }
	local spec = assert(PR.build(inc, info))
	local lane, town = 0, 0
	for _, e in ipairs(spec.edges) do
		if e.forestLane then
			lane = lane + 1
			eq(e.template, LN.TEMPLATE.old)
			eq(e.override, LN.TEMPLATE.old)
			eq(e.locked, true)
			eq(e.decor, "none")
		else
			town = town + 1
			ok(e.template:find("town_old_small", 1, true))
		end
	end
	eq(lane, 1)
	eq(town, 6)
	eq(PR.pathLanes(LN.TEMPLATE.new), 4)
	ok(PR.noNegativeZero(spec))
	-- every node config names lanes the segments have
	local okL = PR.checkLanes(spec, function() return 4 end)
	ok(okL)
	-- no dose beside a lane
	local pts = D.fillPoints("metro", spec.edges, nil, nil, nil, {})
	eq(#pts, 2 * (#spec.edges - 1))
end)

test("driver: FORESTLANE lines, PLAN lanes, built count, a refusal strips and 2 turn them off", function()
	local logs = {}
	local E = { nowUs = function() return 0 end, name = function() return "T" end, templateExists = function() return true end }
	local d = D.new(E, "[T]")
	d.log = function(_, what, fields)
		local t = { what }
		for _, f in ipairs(fields) do t[#t + 1] = f[1] .. "=" .. tostring(f[2]) end
		logs[#logs + 1] = table.concat(t, " ")
	end
	d.debug = d.log
	local seed
	for sd = 1, 200 do
		if #LN.mark(streetInc(true), style("hug", { seed = sd }), { seed = sd }) > 0 then seed = sd; break end
	end
	local inc = streetInc(true)
	local job = { town = 9, style = style("hug", { seed = seed }) }
	ok(d:laneMark(job, inc) > 0)
	local line = logs[#logs]
	ok(line:find("FORESTLANE town=9", 1, true) and line:find("len=", 1, true) and line:find("why=hug:p=", 1, true), line)
	job.inc, job.spec = inc, { edges = { { forestLane = true }, {} } }
	d:laneBuilt(job)
	eq(d:townState(9).lanes, 1)
	ok(logs[#logs]:find("outcome=built", 1, true))
	d.lanesOff = true
	eq(d:laneMark(job, streetInc(true)), 0, "off for the session")
end)

---------------------------------------------------------------------------
-- round after the names run (2026-10-13_2113_sqot-dev): Henley-in-Arden's lane was 6 edges of a back-row grid

--- A 3 x 3 block grid of back-row streets ("bk1:2:L<n>#<k>") wholly in the forest belt: 12 edges of 100 m, new nodes.
local function blockGrid(prefix)
	local inc = { edges = {}, nodes = {} }
	local id = function(i, j) return -(i * 10 + j + 1) end
	local n = 0
	local function add(i0, j0, i1, j1, line)
		n = n + 1
		inc.edges[#inc.edges + 1] = { entity = -(500 + n), node0 = id(i0, j0), node1 = id(i1, j1),
			p0 = { 220 + i0 * 100, j0 * 100, 0 }, p1 = { 220 + i1 * 100, j1 * 100, 0 }, class = "small", street = n,
			key = string.format("%s%s#%d", prefix, line, n) }
	end
	for j = 0, 2 do for i = 0, 1 do add(i, j, i + 1, j, ":L" .. j) end end
	for i = 0, 2 do for j = 0, 1 do add(i, j, i, j + 1, ":C" .. i) end end
	return inc
end

test("Henley: no lane on a block-interior line; a lane is one stretch of one line between town streets", function()
	local runs, st = LN.runs(fo("clear"), blockGrid("bk1:2"))
	eq(#runs, 0, "back-row grid: no lane")
	ok(st.line > 0, "counted as line=")
	-- the same grid on through lines ("sp"): runs stop at the junctions (no lane goes round a block), one line each
	local inc = blockGrid("sp1")
	for _, r in ipairs(LN.runs(fo("clear"), inc)) do
		local line = nil
		for _, i in ipairs(r.edges) do
			local l = LN.lineOf(inc.edges[i].key)
			ok(line == nil or l == line, "one line per lane")
			line = l
		end
		ok(r.len <= LN.MAX_M)
	end
	-- a wooded stretch longer than MAX_M stays a town street
	local long = { edges = {} }
	for k = 0, 8 do
		long.edges[#long.edges + 1] = { node0 = -(k + 1), node1 = -(k + 2), p0 = { 200 + k * 35, 0, 0 }, p1 = { 235 + k * 35, 0, 0 },
			key = "sp9:1#" .. (k + 1), street = 1 }
	end
	long.edges[#long.edges + 1] = { node0 = -1, node1 = -50, p0 = { 200, 0, 0 }, p1 = { 150, 0, 0 }, key = "sp9:0#1", street = 2 }
	long.edges[#long.edges + 1] = { node0 = -10, node1 = -51, p0 = { 515, 0, 0 }, p1 = { 560, 0, 0 }, key = "sp9:2#1", street = 3 }
	local lr, lst = LN.runs(fo("clear"), long)
	eq(#lr, 1, "8 x 35 m = 280 m in the belt fits")
	eq(lst.long, 0)
	LN.MAX_M, lr = 200, nil
	lr, lst = LN.runs(fo("clear"), long)
	LN.MAX_M = 400
	eq(#lr, 0); eq(lst.long, 1)
	ok(LN.lineOk("mrbK1#mrbK1:Xln2:2:7:4~mrb2:1") and LN.lineOk("rg3:2#1") and not LN.lineOk("q3:4") and LN.lineOk("h1:2"))
	eq(LN.lineOf("h1:2"), "h1"); eq(LN.lineOf("v-3:4"), "v-3"); eq(LN.lineOf("rg3:2#1"), "rg3:2")
	-- one edge between two junctions (a block side) is no lane
	local one = { edges = {
		{ node0 = -1, node1 = -2, p0 = { 300, 0, 0 }, p1 = { 400, 0, 0 }, key = "sp1:1#2" },
		{ node0 = -3, node1 = -1, p0 = { 300, -100, 0 }, p1 = { 300, 0, 0 }, key = "x1#1" },
		{ node0 = -1, node1 = -4, p0 = { 300, 0, 0 }, p1 = { 300, 100, 0 }, key = "x2#1" },
		{ node0 = -5, node1 = -2, p0 = { 400, -100, 0 }, p1 = { 400, 0, 0 }, key = "x3#1" },
		{ node0 = -2, node1 = -6, p0 = { 400, 0, 0 }, p1 = { 400, 100, 0 }, key = "x4#1" } } }
	local r1 = LN.runs(fo("clear"), one)
	for _, rr in ipairs(r1) do ok(#rr.edges >= LN.MIN_EDGES, "no single-edge lane") end
	ok(#LN.runs(fo("clear"), one, nil, 1) >= 1, "the dev test's force mode allows one")
end)

test("hug towns: a held wooded piece closing a gap may come as a lane (free), seeded, quota, line rule", function()
	local st = style("hug")
	local co = { c = 0.9, l = 0.8, r = 0.8, len = 260 }
	local n = 0
	for k = 1, 400 do
		if LN.free(st, { key = "rg" .. k .. ":1#1" }, co, 0, 4) then n = n + 1 end
	end
	local p = LN.chance(st)
	ok(math.abs(n / 400 - p) < 0.1, string.format("freed share %.2f ~ p %.2f", n / 400, p))
	ok(not LN.free(st, { key = "bk1:1:L1#1" }, co, 0, 4), "block line")
	ok(not LN.free(st, { key = "rg1:1#1" }, { c = 0.9, l = 0.8, r = 0.8, len = 150 }, 0, 4), "short")
	ok(not LN.free(st, { key = "rg1:1#1", motif = "x" }, co, 0, 4), "motif")
	local any = false
	for k = 1, 50 do if LN.free(st, { key = "rg" .. k .. ":1#1" }, co, 4, 4) then any = true end end
	ok(not any, "quota")
	-- a freed piece's edges are a lane run even without the per-edge read (the piece passed as a whole)
	local inc = streetInc(false)
	local freed = {}
	for k, e in ipairs(inc.edges) do e.key, e.p0[1], e.p1[1] = "rg1:1#1", (k - 1) * 50, k * 50 end
	freed["rg1:1#1"] = true
	local runs, rst = LN.runs({ grid = FO.fromFunction(0, 0, function() return 0 end, 1200, 50), mode = "hug" }, inc, freed)
	eq(#runs, 1, string.format("wooded %d joined %d line %d tip %d short %d long %d", rst.wooded, rst.joined, rst.line,
		rst.tip, rst.short, rst.long))
	eq(#runs[1].edges, 5, "the 7-edge street minus its two dead-end edges")
end)

test("planner: hug towns between forest fingers get a few lanes through the held strips (freed, marked)", function()
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	local core = ug_require(F.DIR .. "ot_core.lua")
	-- a forest band (r 290..470) round the core except clearings along the axes; open meadow beyond
	local function cross(x, y)
		local r2 = x * x + y * y
		if r2 < 290 * 290 or r2 > 470 * 470 then return 0 end
		if math.abs(x) < 80 or math.abs(y) < 80 then return 0 end
		return 200
	end
	local totalFreed, totalLanes, totalEdges, plans = 0, 0, 0, 0
	for _, id in ipairs({ "EU_ORGANIC", "NORDIC", "MED_HILL", "EU_EXTENSION" }) do
		for seedTown = 11, 14 do
			local r = { forceStyle = id, townId = seedTown, year = 1910, nameList = "::/names/germany/germany.names" }
			local st, stats = F.style(r, F.flat)
			local fg = FO.fromFunction(0, 0, cross, 1200, 50)
			st.forest = { grid = fg, mode = "hug", share = fg.share }
			local used = 0
			st.forest.laneFree = function(pc, co) return LN.free(st, pc, co, used, LN.MAX_PER_TOWN) end
			local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
			F.markBuilt(g, 120)
			for k = 1, 10 do
				local inc, report = core.planIncrement(g, st, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
				if #inc.edges == 0 then break end
				plans = plans + 1
				totalFreed = totalFreed + (report and report.laneFreed or 0)
				local marked = LN.mark(inc, st, { seed = st.seed, used = used, max = LN.MAX_PER_TOWN,
					freed = report and report.laneFree or nil })
				for _, m in ipairs(marked) do
					totalLanes = totalLanes + 1
					totalEdges = totalEdges + #m.edges
					-- a lane is never a tip and never on a block line
					for _, i in ipairs(m.edges) do ok(LN.lineOk(inc.edges[i].key), inc.edges[i].key) end
				end
				used = used + #marked
				OG.apply(g, inc, k)
				F.markBuilt(g, 120 + 70 * k)
			end
		end
	end
	print(string.format("      %d plans: %d pieces freed, %d lanes (%d edges)", plans, totalFreed, totalLanes, totalEdges))
	ok(totalLanes >= 1, "some lanes")
	ok(totalLanes <= plans, "sparingly")
end)
