-- Continuous thoroughfares (§73, ot_core.continuity / wideRuns / wideAudit, ot_proposal.narrowJoin): medium / large
-- streets only as runs of RUN_MIN_M that reach an existing wide street, an exit, the centre or a station; short, cut
-- or orphaned runs get the narrower template; joins don't spread a wide dead end into a small street; the old era
-- starts at most RUN_OLD_MAX runs per town.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local TPL = "::/infrastructure/street/town/town_old_%s.street_template"
local SMALL, MEDIUM = TPL:format("small"), TPL:format("medium")
local COUNTRY = "::/infrastructure/street/country/country_old_small.street_template"

local function size(t) return core.townSize(t) or "?" end

--- A plain (early) style: main = medium, the rest small; centre at (0, 0).
local function plainStyle(old, extra)
	local s = { templatePaths = { main = MEDIUM, medium = SMALL, small = SMALL }, centre = { 0, 0 }, stations = {},
		newTemplates = not old, hierarchy = "plain" }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

--- A small existing street along y = 0 from x0 to x1 (nodes every 100 m; ids from `id`), template t. Returns node ids.
local function street(g, id, x0, x1, y, t)
	local ids, prev = {}, nil
	local step = x1 > x0 and 100 or -100
	local k = 0
	for x = x0, x1, step do
		local node = g.nodeById[id + k] or OG.addNode(g, id + k, x, y, 0)
		ids[#ids + 1] = node.id
		if prev then OG.addEdge(g, nil, prev, node.id, "small").template = t end
		prev = node.id
		k = k + 1
	end
	return ids
end

--- New wide edges along y from existing node `from` (at x0) eastward: n edges of 100 m, new nodes -10, -11 ...
local function wideChain(from, x0, y, n, t)
	local inc = { nodes = {}, edges = {} }
	local prev, px = from, x0
	for i = 1, n do
		local ent = -10 - i
		local x = x0 + 100 * i
		inc.nodes[#inc.nodes + 1] = { entity = ent, x = x, y = y, z = 0 }
		inc.edges[#inc.edges + 1] = { entity = -i, node0 = prev, node1 = ent, p0 = { px, y, 0 }, p1 = { x, y, 0 },
			class = "main", template = t or MEDIUM, through = true, key = "m#" .. i }
		prev, px = ent, x
	end
	return inc
end

test("a lone medium edge between small streets gets the small template", function()
	local g = OG.new()
	local ids = street(g, 1, -300, 0, 0, SMALL)
	local inc = wideChain(ids[#ids], 0, 0, 1)
	local h = core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].template, SMALL)
	eq(h.short, 1)
	eq(h.runs.cut, 1)
	eq(h.runs.kept, 0)
end)

test("a long run from the centre stays medium; the same run far out with no anchor is cut", function()
	local g = OG.new()
	local ids = street(g, 1, -300, 0, 0, SMALL)
	local inc = wideChain(ids[#ids], 0, 0, 3)
	local h = core.continuity(g, inc, plainStyle(false))
	for _, e in ipairs(inc.edges) do eq(e.template, MEDIUM) end
	eq(h.runs.kept, 1)
	near(h.runs.maxLen, 300, 1e-6)
	-- far from the centre (2 km), no exit, no station: cut
	g = OG.new()
	ids = street(g, 1, 1700, 2000, 0, SMALL)
	inc = wideChain(ids[#ids], 2000, 0, 4)
	h = core.continuity(g, inc, plainStyle(false))
	for _, e in ipairs(inc.edges) do eq(e.template, SMALL) end
	eq(h.short, 4)
	-- ... unless a station stands at its end
	inc = wideChain(ids[#ids], 2000, 0, 4)
	core.continuity(g, inc, plainStyle(false, { stations = { { 2400, 50 } } }))
	eq(inc.edges[1].template, MEDIUM)
	-- ... or it leaves from a country road (the town's exit)
	local g2 = OG.new()
	local ids2 = street(g2, 1, 1700, 2000, 0, SMALL)
	OG.addNode(g2, 50, 2000, -200, 0)
	OG.addEdge(g2, nil, ids2[#ids2], 50, "small").template = COUNTRY
	inc = wideChain(ids2[#ids2], 2000, 0, 3)
	core.continuity(g2, inc, plainStyle(false))
	eq(inc.edges[3].template, MEDIUM)
end)

test("an extension of an existing medium run stays medium; a short orphan stub doesn't grow by one edge", function()
	-- existing medium street of 300 m: one new edge on from its end is kept (continuity)
	local g = OG.new()
	local ids = street(g, 1, 1000, 1300, 0, MEDIUM)
	local inc = wideChain(ids[#ids], 1300, 0, 1)
	local h = core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].template, MEDIUM)
	eq(h.runs.kept, 1)
	-- an existing 100 m medium stub far out + one new edge: 200 m, too short
	g = OG.new()
	ids = street(g, 1, 1000, 1100, 0, MEDIUM)
	inc = wideChain(ids[#ids], 1100, 0, 1)
	core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].template, SMALL)
	-- ... + two new edges: 300 m with the stub: the stub becomes a run
	inc = wideChain(ids[#ids], 1100, 0, 2)
	core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[2].template, MEDIUM)
end)

test("old era: one run per town; a second separate run is cut, its extension and the high street's are kept", function()
	local g = OG.new()
	-- the high street: 400 m medium through the centre
	local hs = street(g, 1, -200, 200, 0, MEDIUM)
	-- a small street north, its end at the centre's edge
	local side = street(g, 100, -100, 0, 120, SMALL)
	local inc = wideChain(side[#side], 0, 120, 3)
	local h = core.continuity(g, inc, plainStyle(true))
	for _, e in ipairs(inc.edges) do eq(e.template, SMALL, "second run in 1909") end
	eq(h.runs.cut, 1)
	-- the same plan from 1940 (new templates): kept
	inc = wideChain(side[#side], 0, 120, 3)
	core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].template, MEDIUM)
	-- the high street goes on: kept in the old era
	inc = wideChain(hs[#hs], 200, 0, 1)
	core.continuity(g, inc, plainStyle(true))
	eq(inc.edges[1].template, MEDIUM)
	-- a town without a high street gets its first run
	local g2 = OG.new()
	local s2 = street(g2, 1, -300, 0, 0, SMALL)
	inc = wideChain(s2[#s2], 0, 0, 3)
	core.continuity(g2, inc, plainStyle(true))
	eq(inc.edges[1].template, MEDIUM)
	eq(core.RUN_OLD_MAX, 1)
end)

test("a run cut after planning (straight guard drop, forest lane) is judged again: no medium stub goes out", function()
	local g = OG.new()
	local ids = street(g, 1, -300, 0, 0, SMALL)
	local inc = wideChain(ids[#ids], 0, 0, 3)
	core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[3].template, MEDIUM)
	-- the far edge dropped (ot_driver.straightGuard): 200 m left
	PL.dropEdges(inc, { [3] = true })
	eq(#inc.edges, 2)
	local h = core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].template, SMALL)
	eq(inc.edges[2].template, SMALL)
	eq(h.runs.kept, 0)
	-- a forest lane in the middle of a 500 m run splits it into 100 + 300 m: the far 300 m part reaches nothing
	inc = wideChain(ids[#ids], 0, 0, 5)
	inc.edges[2].forestLane = COUNTRY
	core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].template, SMALL, "100 m at the centre")
	eq(inc.edges[4].template, SMALL, "300 m with no anchor")
	-- the hierarchy pass keeps no wide joint on a narrowed edge
	inc = wideChain(ids[#ids], 0, 0, 1)
	inc.edges[1].wideJoin = true
	core.continuity(g, inc, plainStyle(false))
	eq(inc.edges[1].wideJoin, nil)
end)

test("narrower template: the collector's when it isn't wide, else the local one", function()
	eq(core.narrowTemplate(plainStyle(false)), SMALL)
	local late = { templatePaths = { main = TPL:format("large"), medium = MEDIUM, small = SMALL } }
	eq(core.narrowTemplate(late), SMALL)
	local jp = { templatePaths = { main = MEDIUM, medium = SMALL, small = TPL:format("xsmall") } }
	eq(core.narrowTemplate(jp), SMALL, "a JP metro main street cut to small, not xsmall")
	eq(core.isWideEdge({ template = TPL:format("medium_trees") }), true)
	eq(core.isWideEdge({ template = "::/infrastructure/street/town/town_new_large_trees.street_template" }), true)
	eq(core.isWideEdge({ template = MEDIUM, forestLane = COUNTRY }), false)
	eq(core.isWideEdge({ class = "main" }), true)
	eq(core.isWideEdge({ class = "main", template = COUNTRY }), false)
end)

test("joins: a small street joining a medium dead end keeps its own template; same width and small dead ends copy", function()
	local function build(mine, dead, deadLanes)
		local inc = {
			nodes = { { entity = -3, x = 100, y = 0, z = 0 } },
			edges = { { entity = -1, node0 = 500, node1 = -3, p0 = { 0, 0, 0 }, p1 = { 100, 0, 0 }, t0 = { 100, 0, 0 },
				t1 = { 100, 0, 0 }, class = "small", template = mine, key = "a" } },
			joins = { { node = 500, edge = -1 } },
		}
		local info = { nodes = { [500] = { hasConfig = true, edges = { 900 }, lanes = deadLanes, src = 900, template = dead } },
			sources = {}, fallback = 902 }
		return assert(PR.build(inc, info))
	end
	local spec = build(SMALL, MEDIUM, 6)
	eq(spec.edges[1].override, SMALL)
	eq(spec.edges[1].template, SMALL)
	eq(spec.lanes[-1], 4)
	ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 6 end))
	spec = build(MEDIUM, MEDIUM, 6)
	eq(spec.edges[1].override, nil)
	spec = build(SMALL, SMALL, 4)
	eq(spec.edges[1].override, nil)
	spec = build(TPL:format("xsmall"), SMALL, 4)
	eq(spec.edges[1].override, nil, "JP / MED xsmall at a small dead end: copies as before")
	spec = build(SMALL, "::/infrastructure/street/town/town_old_medium_trees.street_template", 6)
	eq(spec.edges[1].override, SMALL)
	eq(PR.narrowJoin(MEDIUM, TPL:format("large")), true)
	eq(PR.narrowJoin(COUNTRY, MEDIUM), false)
	eq(PR.narrowJoin(nil, MEDIUM), false)
end)

test("audit: runs, short and lone ones, builders; text", function()
	local g = OG.new()
	street(g, 1, 0, 400, 0, MEDIUM)            -- a 400 m run
	street(g, 100, 0, 100, 500, MEDIUM)        -- a lone edge
	street(g, 200, 0, 300, 900, SMALL)
	local a = core.wideAudit(g, function(e) return e.id == 5 and "game" or "mod" end)
	eq(a.runs, 2); eq(a.edges, 5); eq(a.short, 1); eq(a.lone, 1)
	near(a.max, 400, 1e-6)
	eq(core.wideAuditText(a), "2/5/500:short1,lone1,max400;mod4,game1")
	eq(core.wideAuditText(core.wideAudit(OG.new())), "0")
	eq(core.wideAuditText(nil), "-")
	eq(core.hierText({ wide = 1, short = 2 }), "wide1/stub0/bare0/bent0/short2")
end)

test("capped walk: a huge graph is walked RUN_MAX_EDGES edges at most", function()
	local g = OG.new()
	street(g, 1, 0, 5000, 0, MEDIUM)
	local cap = core.RUN_MAX_EDGES
	core.RUN_MAX_EDGES = 10
	local okC, runs, walked = pcall(core.wideRuns, g, nil)
	core.RUN_MAX_EDGES = cap
	ok(okC, tostring(runs))
	ok(walked <= 11, "walked " .. tostring(walked))
	eq(#runs, 1)
	eq(#runs[1].edges, 10)
end)

test("no open tip or valve stub on a medium / large street (the game doesn't carry it on)", function()
	local GL = ug_require(F.DIR .. "ot_glock.lua")
	local inc = {
		{ key = "n", node0 = -1, node1 = -2, p0 = { 0, 200 }, p1 = { 0, 300 }, template = MEDIUM },
		{ key = "e", node0 = -1, node1 = -3, p0 = { 200, 0 }, p1 = { 300, 0 }, template = SMALL },
	}
	eq(GL.pickStub(inc, math.pi / 2, 0, 0, 300), nil, "the medium street north")
	eq(GL.pickStub(inc, 0, 0, 0, 300), "e")
	local edges = { { key = "b1", node0 = 5, node1 = -1, p0 = { 300, 0 }, p1 = { 420, 0 }, template = MEDIUM } }
	local picks, rej = GL.pickTips(edges, { b1 = "out" }, {}, 0, 0, 300, {}, 2)
	eq(#picks, 0); eq(rej.wide, 1)
	edges[1].template = SMALL
	eq(#GL.pickTips(edges, { b1 = "out" }, {}, 0, 0, 300, {}, 2), 1)
end)

---------------------------------------------------------------------------
-- Growth: no short / lone medium run is ever built, in any style and era (from a vanilla core, dead-end joins, as in
-- game; and from nothing).

local STYLES = { "EU_ORGANIC", "EU_EXTENSION", "NA_GRID", "NA_SUBURB", "MED_ENSANCHE", "NORDIC", "SUPERBLOCK", "JP_DENSE" }
local YEARS = { 1905, 1930, 1960, 1990 }

test("growth: every medium / large run the mod builds is >= RUN_MIN_M long; old era: at most one run per town", function()
	local STRIDE = FULL and 1 or 3
	local i, checked = 0, 0
	for _, id in ipairs(STYLES) do
		for _, year in ipairs(YEARS) do
			for _, vanilla in ipairs({ true, false }) do
				i = i + 1
				if (i - 1) % STRIDE == 0 or (id == "EU_ORGANIC" and year == 1905) then
					checked = checked + 1
					local style, stats = F.style({ forceStyle = id, townId = 7, year = year, capacity = 3000 }, F.flat)
					local g = vanilla and F.vanillaTown(OG.new(), { angle = 0.3 }) or OG.new()
					for k = 1, (FULL and 10 or 6) do
						local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats,
							join = vanilla and "deadEnd" or "any" })
						if #inc.edges == 0 then break end
						OG.apply(g, inc, k)
					end
					local a = core.wideAudit(g)
					eq(a.short, 0, string.format("%s %d vanilla=%s: short runs (%s)", id, year, tostring(vanilla),
						core.wideAuditText(a)))
					if not style.newTemplates then
						ok(a.runs <= core.RUN_OLD_MAX, string.format("%s %d: %d runs", id, year, a.runs))
					end
					if id == "EU_ORGANIC" and year == 1905 then
						print(string.format("EU_ORGANIC 1905 vanilla=%s wide=%s", tostring(vanilla), core.wideAuditText(a)))
					end
				end
			end
		end
	end
	ok(checked >= 10, "checked " .. checked)
end)
