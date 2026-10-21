-- §75 follow-up "one empty row at a time" (2026-10-19; user shot 5 of run 2026-10-19_1949_sqot: three long empty parallel
-- dead-end lanes ~45 m apart at an EU organic town's grass edge, no houses). ot_knot ROW / rowM / rowNeed / emptyOurs and
-- the selector's `row` knot reason (ot_select ROW): a steer organic town's piece leaving a new dead end waits while it runs
-- beside one of the mod's own streets without a house (or a piece chosen in the same increment); beside a housed street,
-- a game street, or closing a block it comes.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local KN = ug_require(F.DIR .. "ot_knot.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")

local BLOCK = { len = 100, depth = 45 }   -- EU organic's depth: lanes 45 m apart, PAR_K 0.9 -> 40.5 m (no parallel knot)

local function run(g, mp, lim, styleId)
	local style = F.style({ forceStyle = styleId or "EU_ORGANIC" })
	style.centre = { 0, 0 }
	style.block = BLOCK
	local st, rep = SEL.select(g, mp, style, { join = "any", joinR = 10, maxEdges = 12, limits = lim,
		terrain = F.flat, leadDepth = false })
	local out = {}
	for _, s in ipairs(st) do out[s.key] = true end
	return out, rep
end

--- Shot 5: a housed game street running north (x = 0) with nodes every 45 m; lane 1 east from its first node through
--- node 6 (150, 0) to a dead end at (250, 0) (beyond the selector's connector reach of lane 2's end: a connector closing
--- the block would let lane 2 pass, as it should). lane1 = { built, locked, own } (nil: no lane 1). far = true: a street
--- of ours north from node 6 through node 7 at (150, 45), so a lane 2 ending there closes a block.
local function shot5(lane1, far)
	local g = OG.new()
	for i = 0, 3 do OG.addNode(g, i + 1, 0, i * 45, 20) end
	for i = 1, 3 do
		local e = OG.addEdge(g, 10 + i, i, i + 1, "small")
		e.built = 4
	end
	if lane1 then
		OG.addNode(g, 6, 150, 0, 20)
		OG.addNode(g, 9, 250, 0, 20)
		for _, e in ipairs({ OG.addEdge(g, 21, 1, 6, "small"), OG.addEdge(g, 24, 6, 9, "small") }) do
			e.built, e.locked, e.own = lane1.built, lane1.locked, lane1.own
		end
		if far then
			OG.addNode(g, 7, 150, 45, 20)
			OG.addNode(g, 8, 150, 90, 20)
			local f1 = OG.addEdge(g, 22, 6, 7, "small")
			local f2 = OG.addEdge(g, 23, 7, 8, "small")
			f1.built, f1.locked, f2.built, f2.locked = 0, true, 0, true
		end
	end
	g.hasBuilt = true
	return g
end

-- lane 2: from the street's node at (0, 45) east 150 m (a new dead end at (150, 45), or node 7 there with `far`)
local function lane2Plan()
	return { junctions = { S = { 0, 45 }, T = { 150, 45 } },
		pieces = { { key = "lane2", a = "S", b = "T", pts = { { 0, 45 }, { 150, 45 } }, class = "small" } } }
end

test("row limits: ~1.2 block depths (at least the lattice's 44 m rows), the run, our empty streets", function()
	eq(KN.ROW, true)
	eq(SEL.ROW, true)
	near(KN.limits({ block = BLOCK }).rowM, 54, 1e-9, "EU organic 45 m blocks")
	near(KN.limits({ block = { len = 60, depth = 30 } }).rowM, 1.2 * 44, 1e-9, "MED hill: its rows are 44 m apart")
	eq(KN.limits({ block = { len = 300, depth = 150 } }).rowM, KN.ROW_MAX)
	-- the parallel knot stays under the lattice's own spacing; the row rule reaches past it
	ok(KN.limits({ block = BLOCK }).parM < 45 and KN.limits({ block = BLOCK }).rowM > 45)
	eq(KN.rowNeed(150), KN.ROW_RUN_M)
	near(KN.rowNeed(50), 30, 1e-9)
	eq(KN.rowNeed(10), KN.ROW_RUN_MIN)
	eq(KN.rowNeed(0 / 0), KN.ROW_RUN_MIN)
	ok(KN.emptyOurs({ built = 0, locked = true }))
	ok(KN.emptyOurs({ built = 0, own = true }))
	ok(KN.emptyOurs({ built = 0, increment = 3 }), "an offline increment's edge")
	ok(not KN.emptyOurs({ built = 0 }), "a game street")
	ok(not KN.emptyOurs({ built = 1, locked = true }), "one house: housed")
	ok(not KN.emptyOurs({ locked = true }), "no house data")
	ok(not KN.emptyOurs(nil))
end)

test("shot 5: a second empty lane beside our empty lane waits (row, never relaxed); beside a housed one it comes", function()
	local st, rep = run(shot5({ built = 0, locked = true }), lane2Plan(), { steer = true })
	ok(not st.lane2, "the next row waits for the houses: " .. KN.text(rep.knotWhy))
	eq(rep.knotWhy.row, 1)
	eq(rep.knotWhy.parallel or 0, 0, "45 m apart: not the parallel knot's (40.5 m)")
	-- (alone in the increment: still held, the rule never gives way)
	-- built this session (own, unlocked: the §69 steer lock's open tips) counts the same
	local st1 = run(shot5({ built = 0, own = true }), lane2Plan(), { steer = true })
	ok(not st1.lane2, "own")
	-- housed: the next row may come
	local st2, rep2 = run(shot5({ built = 2, locked = true }), lane2Plan(), { steer = true })
	ok(st2.lane2, "beside a housed lane: " .. KN.text(rep2.knotWhy))
	-- the game's own empty street: not ours, no hold
	local st3 = run(shot5({ built = 0 }), lane2Plan(), { steer = true })
	ok(st3.lane2, "a game street")
end)

test("shot 5: a lane closing a block passes; exemptions (grid growers, forced plans, no house data, other towns)", function()
	-- lane 2 ends at node 7 on our (empty) street along x = 150: a closed block, no comb
	local st, rep = run(shot5({ built = 0, locked = true }, true), lane2Plan(), { steer = true })
	ok(st.lane2, "a block-closing piece comes: " .. KN.text(rep.knotWhy))
	eq(rep.knotWhy.row or 0, 0)
	local empty = function() return shot5({ built = 0, locked = true }) end
	ok(run(empty(), lane2Plan(), { steer = true }, "NA_GRID").lane2, "grid growers lay their lattice")
	ok(run(empty(), lane2Plan(), { steer = true, rowHold = false }).lane2, "forced plans (the driver's rowHold = false)")
	ok(run(empty(), lane2Plan(), nil).lane2, "not a steer town")
	local g = empty()
	g.hasBuilt = nil
	for _, e in ipairs(g.edges) do e.built = nil end
	ok(run(g, lane2Plan(), { steer = true }).lane2, "no house data")
	local saved = SEL.ROW
	SEL.ROW = false
	ok(run(empty(), lane2Plan(), { steer = true }).lane2, "ROW off")
	SEL.ROW = saved
	-- a piece turning away (perpendicular) from the empty lane: no run beside it
	local mp = { junctions = { S = { 0, 45 }, T = { -150, 45 } },
		pieces = { { key = "west", a = "S", b = "T", pts = { { 0, 45 }, { -150, 45 } }, class = "small" } } }
	ok(run(empty(), mp, { steer = true }).west, "a lane on the other side, 150 m from lane 1's line")
end)

test("one increment: two empty lanes of a comb come one at a time; with the far street the block closes and all come", function()
	-- no lane of ours yet; lane A from (0, 0) and lane B from (0, 45), both east 150 m to new dead ends
	local function comb(far)
		local mp = { junctions = { A0 = { 0, 0 }, A1 = { 150, 0 }, B0 = { 0, 45 }, B1 = { 150, 45 } },
			pieces = {
				{ key = "laneA", a = "A0", b = "A1", pts = { { 0, 0 }, { 150, 0 } }, class = "small" },
				{ key = "laneB", a = "B0", b = "B1", pts = { { 0, 45 }, { 150, 45 } }, class = "small" } } }
		if far then
			mp.pieces[3] = { key = "far", a = "A1", b = "B1", pts = { { 150, 0 }, { 150, 45 } }, class = "small" }
		end
		return mp
	end
	local st, rep = run(shot5(nil), comb(false), { steer = true })
	ok((st.laneA and 1 or 0) + (st.laneB and 1 or 0) == 1, "one row: " .. KN.text(rep.knotWhy))
	eq(rep.knotWhy.row, 1)
	-- the far street tying both lanes' ends: the block closes within the increment, every piece comes
	local st2, rep2 = run(shot5(nil), comb(true), { steer = true })
	ok(st2.laneA and st2.laneB and st2.far, "a closed block: " .. KN.text(rep2.knotWhy))
end)

test("the snapshot carries the mod's own streets (own) for the row rule", function()
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 100, y = 0 } },
		edges = { { id = 5, node0 = 1, node1 = 2, class = "small", built = 0, own = true } } })
	eq(g.edgeById[5].own, true)
	ok(KN.emptyOurs(g.edgeById[5]))
end)

-- The empty-row measure (2026-10-20, SNAPSHOT `emptyRows=`): the town's own empty edges running >= 40 m beside another
-- within rowM; dead-end ones apart; capped.
local function comb(spacing, lanes, o)
	o = o or {}
	local g = OG.new()
	local id = 100
	for i = 0, lanes - 1 do OG.addNode(g, i + 1, 0, i * spacing, 20) end
	for i = 1, lanes - 1 do
		local e = OG.addEdge(g, 10 + i, i, i + 1, "small")
		e.built = 4
	end
	for i = 0, lanes - 1 do
		local y = i * spacing
		OG.addNode(g, 50 + i, 100, y, 20)
		OG.addNode(g, 70 + i, 200, y, 20)
		for _, e in ipairs({ OG.addEdge(g, 200 + 2 * i, i + 1, 50 + i, "small"),
			OG.addEdge(g, 201 + 2 * i, 50 + i, 70 + i, "small") }) do
			e.built = (o.housed and o.housed[i + 1]) and 3 or 0
			if o.game then e.locked = nil else e.locked = true end
		end
	end
	g.hasBuilt = o.noHouses ~= true
	return g
end

test("empty rows: a comb of our empty lanes 45 m apart counts, dead-end halves apart; houses, game streets, 70 m don't", function()
	local lim = KN.limits({ block = BLOCK })
	near(lim.rowM, 54, 1e-9)
	local r = KN.emptyRows(comb(45, 3), lim)
	eq(r.cand, 6)
	eq(r.n, 6)
	near(r.m, 600, 1e-6)
	near(r.deadM, 300, 1e-6, "the outer edge of each lane ends at a dead end")
	eq(KN.rowsText(r), "600/300/6")
	-- the middle lane housed: the outer two are 90 m apart, over rowM
	eq(KN.emptyRows(comb(45, 3, { housed = { false, true, false } }), lim).n, 0)
	-- two lanes, one housed: none
	eq(KN.emptyRows(comb(45, 2, { housed = { true, false } }), lim).n, 0)
	-- the game's own empty streets (not locked, not built this session): not ours
	eq(KN.emptyRows(comb(45, 3, { game = true }), lim).cand, 0)
	-- 70 m apart: beyond rowM
	eq(KN.emptyRows(comb(70, 3), lim).n, 0)
	-- built this session (own) counts as ours
	local g = comb(45, 2, { game = true })
	for _, e in ipairs(g.edges) do if e.id >= 200 then e.own = true end end
	eq(KN.emptyRows(g, lim).n, 4)
	-- no house counts: no measure
	eq(KN.emptyRows(comb(45, 3, { noHouses = true }), lim), nil)
	eq(KN.rowsText(nil), "-")
	-- the cap: the rest counted as capped
	local cap = KN.ROWS_EDGES_MAX
	KN.ROWS_EDGES_MAX = 2
	local rc = KN.emptyRows(comb(45, 3), lim)
	KN.ROWS_EDGES_MAX = cap
	eq(rc.capped, 4)
	eq(rc.n, 2)
	ok(KN.rowsText(rc):find("+4", 1, true))
end)

test("empty rows: a street's own next piece and an L of our street don't count (no shared node)", function()
	local lim = KN.limits({ block = BLOCK })
	local g = OG.new()
	OG.addNode(g, 1, 0, 0, 20)
	OG.addNode(g, 2, 100, 0, 20)
	OG.addNode(g, 3, 100, 100, 20)
	OG.addNode(g, 4, 60, 30, 20)
	for _, e in ipairs({ OG.addEdge(g, 1, 1, 2, "small"), OG.addEdge(g, 2, 2, 3, "small"), OG.addEdge(g, 3, 2, 4, "small") }) do
		e.built, e.locked = 0, true
	end
	g.hasBuilt = true
	eq(KN.emptyRows(g, lim).n, 0)
end)
