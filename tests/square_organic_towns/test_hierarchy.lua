-- Street hierarchy by era (ot_style lateTemplates, ot_select.through, ot_core.hierarchy, ot_proposal wideJoin):
-- wide streets for the sprawling styles from 1950, only on through routes, never on dead-end stubs; lane
-- invariants hold with wide joints.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local C = ug_require(F.DIR .. "ot_check.lua")

local function size(t) return t and t:match("town_%a+_(%a+)%.street_template$") or "?" end

--- Grows a town n increments; returns the graph, the increments and template counts.
local function grow(id, year, n, vanilla)
	local style, stats = F.style({ forceStyle = id, townId = 5, year = year, capacity = 4000 }, F.flat)
	local g = vanilla and F.vanillaTown(OG.new(), { angle = 0 }) or OG.new()
	local incs, counts = {}, {}
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = vanilla and "deadEnd" or "any" })
		if #inc.edges == 0 then break end
		for _, e in ipairs(inc.edges) do counts[size(e.template)] = (counts[size(e.template)] or 0) + 1 end
		OG.apply(g, inc, k)
		incs[#incs + 1] = inc
	end
	return g, incs, counts, style
end

test("templates by style x era: sprawling styles get large arterials from 1950, old cores / MED / JP stay narrow", function()
	for _, id in ipairs({ "NA_GRID", "SUPERBLOCK" }) do
		local _, _, c = grow(id, 1960, 12)
		ok((c.large or 0) > 0, id .. " 1960 has large streets: " .. tostring(c.large))
		ok((c.small or 0) > 0, id .. " keeps small local streets")
		local _, _, c0 = grow(id, 1930, 12)
		eq(c0.large, nil, id .. " 1930: no large street")
	end
	for _, id in ipairs({ "EU_ORGANIC", "MED_HILL", "JP_DENSE" }) do
		local _, _, c = grow(id, 1990, 10)
		eq(c.large, nil, id .. " never large")
	end
	local _, _, cm = grow("MED_HILL", 1990, 10)
	eq(cm.medium, nil, "MED hill never medium")
	local s = F.style({ forceStyle = "NA_SUBURB", year = 1970 })
	eq(s.hierarchy, "late")
	eq(size(s.templatePaths.main), "large")
	eq(size(s.templatePaths.medium), "medium")
	eq(F.style({ forceStyle = "EU_EXTENSION", year = 1970 }).hierarchy, "plain")
end)

test("wide streets only on through routes: every wide edge is a through piece meeting another street", function()
	for _, id in ipairs({ "NA_GRID", "SUPERBLOCK", "NA_SUBURB" }) do
		for _, vanilla in ipairs({ false, true }) do
			local g, incs, _, style = grow(id, 1970, 12, vanilla)
			local small = style.templatePaths.small
			local wide, stubs = 0, 0
			for _, inc in ipairs(incs) do
				stubs = stubs + inc.hier.stub + inc.hier.bare
				for _, e in ipairs(inc.edges) do
					if e.template ~= small then
						wide = wide + 1
						ok(e.through, id .. " wide edge on a through piece: " .. tostring(e.key))
					end
				end
			end
			-- no wide dead-end spur longer than one block: from each wide dead end, a junction within 1.3 blocks
			local block = math.max(style.block.len, style.block.depth)
			for _, n in ipairs(OG.deadEnds(g)) do
				local e = g.edgeById[g.adj[n][1]]
				if e.template and C.halfWidth(nil, e.template) > C.halfWidth(nil, small) then
					local len, at, via = 0, n, e
					for _ = 1, 20 do
						len = len + OG.edgeLength(g, via)
						at = OG.other(via, at)
						if OG.degree(g, at) ~= 2 then break end
						local a = g.adj[at]
						via = g.edgeById[a[1] == via.id and a[2] or a[1]]
					end
					ok(len <= 1.3 * block + 1, string.format("%s wide spur %.0f m (block %.0f)", id, len, block))
				end
			end
			print(string.format("%s vanilla=%s wide=%d narrowed=%d", id, tostring(vanilla), wide, stubs))
		end
	end
end)

test("hierarchy: a bare wide spur and a non-through tip get the local template; a wide joint is marked", function()
	local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
	local LARGE = "::/infrastructure/street/town/town_new_large.street_template"
	local style = { templatePaths = { small = SMALL, medium = SMALL, main = LARGE } }
	local g = OG.new()
	OG.addNode(g, 1, 0, 0, 0)
	OG.addNode(g, 2, -100, 0, 0)
	OG.addEdge(g, 10, 2, 1, "small").template = SMALL
	local function e(ent, n0, n1, through, key)
		return { entity = ent, node0 = n0, node1 = n1, class = "main", template = LARGE, through = through, key = key }
	end
	-- a spur 1 -> -3 -> -4 with nothing crossing it: bare
	local inc = { edges = { e(-1, 1, -3, true, "a"), e(-2, -3, -4, true, "a") }, nodes = {} }
	core.hierarchy(g, inc, style)
	eq(inc.edges[1].template, SMALL)
	eq(inc.hier.bare, 2)
	-- the same with a cross street at -3: wide, the joint edge marked
	inc = { edges = { e(-1, 1, -3, true, "a"), e(-2, -3, -4, true, "a"),
		{ entity = -3, node0 = -3, node1 = -5, class = "small", template = SMALL, key = "b" } }, nodes = {} }
	core.hierarchy(g, inc, style)
	eq(inc.edges[1].template, LARGE)
	eq(inc.edges[1].wideJoin, true)
	eq(inc.hier.wide, 2)
	-- a tip (not through): local
	inc = { edges = { e(-1, 1, -3, false, "tip") }, nodes = {} }
	core.hierarchy(g, inc, style)
	eq(inc.edges[1].template, SMALL)
	eq(inc.hier.stub, 1)
end)

test("wide joint: the joint edge takes the large template with 8 lanes; every lane index valid", function()
	local SMALL = "::/infrastructure/street/town/town_old_small.street_template"
	local LARGE = "::/infrastructure/street/town/town_new_large.street_template"
	local inc = {
		nodes = { { entity = -3, x = 100, y = 0, z = 0 }, { entity = -4, x = 100, y = 100, z = 0 } },
		edges = {
			{ entity = -1, node0 = 500, node1 = -3, p0 = { 0, 0, 0 }, p1 = { 100, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 },
				class = "main", template = LARGE, key = "a", wideJoin = true },
			{ entity = -2, node0 = -3, node1 = -4, p0 = { 100, 0, 0 }, p1 = { 100, 100, 0 }, t0 = { 0, 100, 0 }, t1 = { 0, 100, 0 },
				class = "small", template = "::/infrastructure/street/town/town_new_small.street_template", key = "b" },
		},
		joins = { { node = 500, edge = -1 } },
	}
	local info = { nodes = { [500] = { hasConfig = true, edges = { 900 }, lanes = 4, src = 900, template = SMALL } },
		sources = {}, fallback = 902 }
	local spec = assert(PR.build(inc, info))
	eq(spec.edges[1].override, LARGE)
	eq(spec.edges[1].src, 900, "still copies the dead end's town street")
	eq(spec.lanes[-1], 8)
	ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
	-- without the mark: the dead end's own street
	inc.edges[1].wideJoin = nil
	spec = assert(PR.build(inc, info))
	eq(spec.edges[1].override, nil)
	eq(spec.lanes[-1], 4)
end)

---------------------------------------------------------------------------
-- Street mix (2026-10-12, user: "for higher density roads we build it's important they still mix in some smaller
-- roads"): few arterials, collectors between them, mostly local streets, measured as share of new length.

local SEL = ug_require(F.DIR .. "ot_select.lua")
local GRID = ug_require(F.DIR .. "ot_grow_grid.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")

--- Town mix over n increments (core.mix summed) from an empty town (joins anywhere) or a vanilla core (dead-end
--- joins, as in game). Returns the mix, the increments and the style.
local function townMix(id, n, vanilla, year)
	local style, stats = F.style({ forceStyle = id, townId = 5, year = year or 1970, capacity = 3000 }, F.flat)
	local g = vanilla and F.vanillaTown(OG.new(), { angle = 0.4 }) or OG.new()
	local tot, incs = nil, {}
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = vanilla and "deadEnd" or "any" })
		if #inc.edges == 0 then break end
		tot = core.addMix(tot, inc.mix)
		OG.apply(g, inc, k)
		incs[#incs + 1] = inc
	end
	return tot, incs, style, g
end

test("street mix: late styles keep arterials few and mostly local streets (10 increments)", function()
	for _, id in ipairs({ "NA_GRID", "NA_SUBURB", "SUPERBLOCK", "MED_ENSANCHE" }) do
		for _, vanilla in ipairs({ false, true }) do
			local m, incs = townMix(id, 10, vanilla)
			ok(#incs >= 6, id .. " grows: " .. #incs)
			local L, M, S = m.large / m.total, m.medium / m.total, m.small / m.total
			print(string.format("%-12s vanilla=%-5s mix=%s (%d increments, %.0f m)", id, tostring(vanilla), core.mixText(m),
				#incs, m.total))
			-- (0.23 since the shape envelope, 2026-10-12: a shaped grid grows along its arterial axis; 22.4 % measured)
			ok(L <= 0.23, id .. " large <= ~20 %: " .. core.mixText(m))
			ok(M >= 0.08, id .. " has collectors: " .. core.mixText(m))
			ok(S >= 0.5, id .. " small >= 50 %: " .. core.mixText(m))
		end
	end
	-- before 1950 the same styles build no large street at all
	local m = townMix("NA_GRID", 8, false, 1930)
	eq(m.large, 0)
end)

test("mix helpers: lengths by template size, text as L/M/S percent", function()
	local LARGE = "::/infrastructure/street/town/town_new_large.street_template"
	local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
	local XS = "::/infrastructure/street/town/town_old_xsmall.street_template"
	local inc = { edges = {
		{ p0 = { 0, 0 }, p1 = { 30, 40 }, template = LARGE },        -- 50 m
		{ p0 = { 0, 0 }, p1 = { 100, 0 }, template = SMALL },
		{ p0 = { 0, 0 }, p1 = { 0, 50 }, template = XS },
		{ p0 = { 0, 0 }, p1 = { 0, 50 }, class = "medium" },          -- no template: by class
	} }
	local m = core.mix(inc)
	eq(m.large, 50); eq(m.small, 150); eq(m.medium, 50); eq(m.total, 250)
	eq(core.mixText(m), "20/20/60")
	eq(core.mixText(nil), "-")
	eq(core.mixText(core.addMix(nil, m)), "20/20/60")
end)

test("superblock: arterial grid around each 350 x 250 cell, local streets inside, no interior through line", function()
	local p = F.style({ forceStyle = "SUPERBLOCK", year = 1970 })
	local mp = GRID.masterPlan(p, { extent = 1200 })
	eq(mp.su, 4); eq(mp.sv, 3)
	local len = { main = 0, medium = 0, small = 0 }
	for _, pc in ipairs(mp.pieces) do
		local a, b = pc.pts[1], pc.pts[#pc.pts]
		len[pc.class] = len[pc.class] + G.dist(a[1], a[2], b[1], b[2])
		local d, i, j = pc.key:match("^(%a)(%-?%d+):(%-?%d+)$")
		i, j = tonumber(i), tonumber(j)
		if d == "v" then
			-- a cell line (every 4th fine column) is arterial / collector; interior columns small, and only in
			-- the strips the pattern names (so no interior street runs straight across a cell)
			if i % 4 == 0 then ok(pc.class ~= "small", pc.key) else
				eq(pc.class, "small", pc.key)
				local s = j % 3
				ok((s == 1 and (i % 4 == 1 or i % 4 == 3)) or (s ~= 1 and i % 4 == 2), "cross pattern " .. pc.key)
			end
		elseif j % 3 ~= 0 then
			eq(pc.class, "small", pc.key)
		end
	end
	local total = len.main + len.medium + len.small
	print(string.format("superblock plan: main %.0f%% medium %.0f%% small %.0f%%", 100 * len.main / total,
		100 * len.medium / total, 100 * len.small / total))
	ok(len.small / total >= 0.55, "mostly local streets in the plan")
	ok(len.main / total <= 0.25)
	-- the cell lines keep their positions (saved superblock towns: the arterial lattice does not move)
	local cell = ST.profile("SUPERBLOCK").block
	near(mp.u[4] - mp.u[0], cell.len, cell.len * 0.1 * 1.7 + 1e-6)
end)

test("late styles: the cross axis is a collector, arterials every 6 (NA grid) / 8 (suburb) blocks", function()
	local mp = GRID.masterPlan(F.style({ forceStyle = "NA_GRID", year = 1970 }), { extent = 1500 })
	local cls = {}
	for _, pc in ipairs(mp.pieces) do cls[pc.key] = pc.class end
	eq(cls["h0:0"], "main"); eq(cls["v0:0"], "medium"); eq(cls["v6:0"], "main"); eq(cls["v2:0"], "medium")
	eq(cls["v1:0"], "small"); eq(cls["h0:4"], "medium"); eq(cls["h0:12"], "main")
	eq(GRID.lineClass(3, 6, false, 2), "small")
	eq(GRID.lineClass(8, 8, false, nil), "main")
	eq(GRID.lineClass(4, 8, false, nil), "medium", "no collectors given: half way")
	eq(GRID.lineClass(0, 8, true, nil, "medium"), "medium")
end)

test("wide streets lead at most WIDE_REACH (fine) blocks beyond the town's front (late styles)", function()
	for _, id in ipairs({ "NA_GRID", "NA_SUBURB", "SUPERBLOCK" }) do
		local style, stats = F.style({ forceStyle = id, townId = 5, year = 1970, capacity = 3000, shape = "compact" }, F.flat)
		local g = F.vanillaTown(OG.new(), { angle = 0.4 })
		local fine = math.max(style.block.len / ((style.sub and style.sub.u) or 1),
			style.block.depth / ((style.sub and style.sub.v) or 1))
		local worst = -math.huge
		for k = 1, 10 do
			local inc, rep = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd" })
			if #inc.edges == 0 then break end
			ok(rep.wideCap ~= nil, id .. " cap set")
			for _, e in ipairs(inc.edges) do
				if C.halfWidth(nil, e.template) > C.halfWidth(nil, style.templatePaths.small) then
					local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
					local cap = rep.wideCap + (e.class == "medium" and SEL.WIDE_REACH_MEDIUM * fine or 0)
					worst = math.max(worst, G.dist(style.centre[1], style.centre[2], mx, my) - cap)
				end
			end
			OG.apply(g, inc, k)
		end
		-- an edge of a piece reaches at most half a (long) piece beyond the piece's midpoint
		ok(worst <= 0.5 * math.max(style.block.len, style.block.depth) + 1, id .. " beyond the cap: " .. worst)
	end
end)

---------------------------------------------------------------------------
-- Joint kinks (Showcase v4 DIAGJOINT, 2026-10-12): an edge turning ~90 deg at an existing dead end was refused
-- (Construction Not Possible), the same edge continued straight built.

test("jointIssues: a sharp turn at a dead end left with two streets is a kink; a T or a straight one is not", function()
	local g = OG.new()
	OG.addNode(g, 1, 0, 0, 0)
	OG.addNode(g, 2, 100, 0, 0)
	OG.addEdge(g, 10, 1, 2, "small")   -- dead end at node 2, street heading east
	local function edge(key, x, y) return { entity = -1, node0 = 2, node1 = -9, p0 = { 100, 0 }, p1 = { x, y }, key = key } end
	eq(core.jointIssues(g, { edges = { edge("turn", 100, 80) } }), { "turn" })
	eq(core.jointIssues(g, { edges = { edge("straight", 180, 10) } }), {})
	eq(core.jointIssues(g, { edges = { edge("t1", 100, 80), edge("t2", 180, 0) } }), {}, "a T: three streets")
	eq(core.jointIssues(g, { edges = { edge("diag", 160, 60) } }), {}, "45 deg")
end)

test("joint rule on: no planned kink at a dead end; off (default) plans them as before", function()
	eq(SEL.JOINT_RULE, false)
	for _, id in ipairs({ "MED_ENSANCHE", "NA_GRID", "EU_ORGANIC" }) do
		local style, stats = F.style({ forceStyle = id, townId = 5, year = 1970, capacity = 3000 }, F.flat)
		local g = F.vanillaTown(OG.new(), { angle = 0 })
		for k = 1, 4 do
			local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", jointRule = true })
			if #inc.edges == 0 then break end
			eq(#core.jointIssues(g, inc), 0, id .. " increment " .. k)
			OG.apply(g, inc, k)
		end
	end
end)
