-- §75 (2026-10-19; user shots): streets close beside another street at illogical angles.
--   A: a side street leaving a curving street at ~20-30 deg and running back beside it (a hairpin dead end);
--   B: a street running 200 m+ beside a diagonal main street ~45 m away (one row of houses between), then joining it;
--   C: two dead ends of a forest town ~60-80 m apart at right angles, the corner closing the block never made.
-- The side-street rule (ot_check.sideBad: 60-120 deg at a junction, a fork excepted; ot_plan sideAngle, ot_select SIDE),
-- the parallel knot over the whole street (ot_knot.chainBehind / streetLine / parallelRun, PAR_K 0.9, PAR_MAX 50, never
-- relaxed, connectors too, the near-miss joins), and the near-miss review: the corner shape, the woods only on the join's
-- own curve, the driver's retiredOk passed on.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local CK = ug_require(F.DIR .. "ot_check.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")
local KN = ug_require(F.DIR .. "ot_knot.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local NM = ug_require(F.DIR .. "ot_nearmiss.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local SMALL = "::/infrastructure/street/town/town_old_small.street_template"
local rad = math.rad

local function arms(list, newFrom)
	local out = {}
	for i, d in ipairs(list) do out[i] = { h = rad(d), new = i >= (newFrom or 1) } end
	return out
end

test("side rule: a side street leaves a junction at 60 deg or more; a Y fork and existing junctions excepted", function()
	local side = rad(CK.LIMITS.sideAngle)
	eq(CK.LIMITS.sideAngle, 60)
	-- a through street (0 / 180) and a side street at 25, 45, 75, 90 deg
	ok(CK.sideBad(arms({ 0, 180, 25 }, 3), side) ~= nil, "25 deg: case A")
	ok(CK.sideBad(arms({ 0, 180, 45 }, 3), side) ~= nil)
	eq(CK.sideBad(arms({ 0, 180, 75 }, 3), side), nil)
	eq(CK.sideBad(arms({ 0, 180, 90 }, 3), side), nil)
	-- a curving through street (170 deg) with the branch 25 deg off one arm: no fork (that arm goes on almost straight)
	ok(CK.sideBad(arms({ 0, 175, 25 }, 3), side) ~= nil)
	-- a Y: two arms 20 deg either side of the third street's continuation
	eq(CK.sideBad(arms({ 180, 20, -20 }, 2), side), nil, "a fork")
	ok(CK.isFork({ math.pi, rad(20), rad(-20) }, 2, 3))
	ok(not CK.isFork({ math.pi, rad(5), rad(30) }, 2, 3), "one arm straight on: a side street")
	ok(not CK.isFork({ math.pi, rad(70), rad(-70) }, 2, 3), "beyond FORK_MAX")
	-- a bend (two streets) is the minAngle rule's, not this one's
	eq(CK.sideBad(arms({ 0, 30 }, 2), side), nil)
	-- an existing junction's own angles stand: only pairs with a new street count
	eq(CK.sideBad(arms({ 0, 30, 180 }, 3), side), nil)
	ok(CK.sideBad(arms({ 0, 180, 200 }, 3), side) ~= nil, "the new street 20 deg off the existing 180")
	-- free streets (the climbing motifs) and off
	local a = arms({ 0, 180, 25 }, 3)
	a[3].free = true
	eq(CK.sideBad(a, side), nil)
	eq(CK.sideBad(arms({ 0, 180, 25 }, 3), 0), nil)
end)

-- case A for the planner: a street east from the dead end 2 through K (100, 0), curving on; a side street from K
-- leaving 26 deg off it and running back beside it ~25-35 m away
local function caseA()
	local g = OG.new()
	OG.addNode(g, 1, -200, 0, 0)
	OG.addNode(g, 2, 0, 0, 0)
	OG.addEdge(g, 11, 1, 2, "small")
	local through = { pts = { { 0, 0 }, { 100, 0 }, { 200, -10 }, { 300, -35 } }, class = "small", startNode = 2, key = "on" }
	local side = { pts = { { 100, 0 }, { 140, 15 }, { 200, 22 }, { 260, 15 } }, class = "small", key = "side" }
	return g, through, side
end

test("case A, planner and checker: the side street leaving 26 deg off is refused with sideAngle (steer), kept without", function()
	local g, through, side = caseA()
	local o = { join = "any", maxSeg = 100, minAngle = 25 }
	local plain = PL.plan(g, { through, side }, o)
	local geo = CK.increment(plain, g)
	eq(geo.counts.side, 1, "the checker reports it: " .. CK.summary(geo))
	eq(CK.badText(geo):find("side", 1, true), nil, "not in geoBad (the PLAN line's geoSide=)")
	local keys = {}
	for _, e in ipairs(plain.edges) do keys[e.key] = (keys[e.key] or 0) + 1 end
	ok(keys.side ~= nil, "without the rule the side street comes")
	o.sideAngle = CK.LIMITS.sideAngle
	local held = PL.plan(g, { through, side }, o)
	local why = {}
	for _, d in ipairs(held.dropped) do if held.edges and d.street == 2 then why[d.reason] = true end end
	ok(why.angle, "the side street's first edge: angle")
	local k2 = {}
	for _, e in ipairs(held.edges) do k2[e.key] = true end
	ok(k2.on and not k2.side, "the through street stays, the side street goes")
	eq(CK.increment(held, g).counts.side or 0, 0)
	-- the same side street at 75 deg passes
	local side2 = { pts = { { 100, 0 }, { 120, 75 }, { 130, 160 } }, class = "small", key = "side2" }
	local ok2 = PL.plan(g, { through, side2 }, o)
	local k3 = {}
	for _, e in ipairs(ok2.edges) do k3[e.key] = true end
	ok(k3.side2, "a side street at 75 deg comes")
	-- a free street (a climbing motif's) is exempt
	side.sideFree = true
	local free = PL.plan(g, { through, side }, o)
	local k4 = {}
	for _, e in ipairs(free.edges) do k4[e.key] = true end
	ok(k4.side, "sideFree")
	eq(CK.increment(free, g).counts.side or 0, 0, "free edges are no violation")
end)

local function run(g, mp, lim, styleId, block)
	local style = F.style({ forceStyle = styleId or "EU_ORGANIC" })
	style.centre = { 0, 0 }
	style.block = block or { len = 100, depth = 60 }
	local st, rep = SEL.select(g, mp, style, { join = "any", joinR = 60, maxEdges = 12, limits = lim,
		terrain = F.flat, leadDepth = false })
	local out = {}
	for _, s in ipairs(st) do out[s.key] = true end
	return out, rep
end

test("case A, selector: of the through street and the 26 deg side street at K only one comes (side); 75 deg comes", function()
	local g = caseA()
	local mp = { junctions = { N2 = { 0, 0 }, K = { 100, 0 }, E = { 200, -10 }, H = { 260, 15 }, V = { 130, 160 } },
		pieces = {
			{ key = "on1", a = "N2", b = "K", pts = { { 0, 0 }, { 100, 0 } }, class = "small" },
			{ key = "on2", a = "K", b = "E", pts = { { 100, 0 }, { 200, -10 } }, class = "small" },
			{ key = "side", a = "K", b = "H", pts = { { 100, 0 }, { 140, 15 }, { 200, 22 }, { 260, 15 } }, class = "small" } } }
	local st, rep = run(g, mp, { steer = true })
	ok(st.on1, "the street comes")
	ok(not (st.on2 and st.side), "not both: " .. tostring(st.on2) .. tostring(st.side) .. " " .. KN.text(rep.knotWhy))
	ok((rep.knotWhy.side or 0) >= 1, KN.text(rep.knotWhy))
	ok(not rep.knotRelax or not (st.on2 and st.side), "never relaxed")
	-- other towns (no steer), grid growers (SIDE_GRID), the rule off: as before
	local plain = run(g, mp, nil)
	ok(plain.on2 and plain.side, "other towns: both")
	local grid = run(g, mp, { steer = true }, "NA_GRID")
	ok(grid.on2 and grid.side, "grid growers: both")
	SEL.SIDE = false
	local off = run(g, mp, { steer = true })
	SEL.SIDE = true
	ok(off.on2 and off.side, "SIDE off: both")
	-- at 75 deg both come
	local mp2 = { junctions = mp.junctions, pieces = { mp.pieces[1], mp.pieces[2],
		{ key = "side", a = "K", b = "V", pts = { { 100, 0 }, { 120, 75 }, { 130, 160 } }, class = "small" } } }
	local st2, rep2 = run(g, mp2, { steer = true })
	ok(st2.on1 and st2.on2 and st2.side, "a proper side street: " .. KN.text(rep2.knotWhy))
end)

-- case B: a diagonal main street (u along it, v across), a side street off its node at u = 100 turning to run beside it
-- 45 m away for 200 m (built earlier); the next piece runs on beside it
local S2 = math.sqrt(0.5)
local function rot(u, v) return { (u - v) * S2, (u + v) * S2 } end
local function caseB(off)
	off = off or 45
	local g = OG.new()
	for i = 0, 4 do
		local p = rot(i * 100, 0)
		OG.addNode(g, i + 1, p[1], p[2], 0)
		if i > 0 then OG.addEdge(g, 100 + i, i, i + 1, "medium") end
	end
	local chain = { rot(100, off), rot(200, off), rot(300, off) }
	for k, p in ipairs(chain) do OG.addNode(g, 10 + k, p[1], p[2], 0) end
	OG.addEdge(g, 111, 2, 11, "small")
	OG.addEdge(g, 112, 11, 12, "small")
	OG.addEdge(g, 113, 12, 13, "small")
	return g
end
local EXT = { len = 110, depth = 80 }   -- EU extension's blocks (the Long Fork Beach style): parM 50, parRun 110

test("case B geometry: the run over the whole street; the old per-piece rule never saw it", function()
	local lim = KN.limits({ block = EXT })
	eq(lim.parM, 50); eq(lim.parRun, 110)
	local g = caseB()
	local main = {}
	for i = 101, 104 do main[#main + 1] = KN.edgePts(g, g.edgeById[i]) end
	local piece = { rot(300, 45), rot(400, 45) }
	-- before §75: 0.65 x depth capped at 35 m (45 m apart: nothing), END_SKIP at both ends of the 100 m piece
	local old = { parM = 35, parRun = 110, parCos = lim.parCos }
	eq(KN.parallelRun(piece, main, old), 0)
	ok(KN.parallelRun(piece, main, lim) < lim.parRun, "the piece alone: under the run")
	-- the whole street: back through 13 - 12 - 11 to the junction at node 2
	local at = function(id) return KN.graphAt(g, id) end
	local pa, ta, ea = KN.chainBehind(13, "p", at)
	eq(ea, "junction"); eq(#pa, 3)
	ok(ta.e113 and ta.e112 and ta.e111)
	local pb, _, eb = KN.chainBehind("new", "p", at)
	eq(eb, "end"); eq(#pb, 0)
	local C, s0, s1, k0, k1 = KN.streetLine(KN.dense(piece), pa, ea, pb, eb)
	eq(k0, KN.END_SKIP); eq(k1, 0)
	near(s1 - s0, 100, 1)
	local run = KN.parallelRun(C, main, lim, { s0 = s0, s1 = s1, skip0 = k0, skip1 = k1, self = true })
	ok(run >= 280, "beside the main street from u = 100 to 400: " .. run)
	-- a piece turning away (only its first metres beside the main street) is no knot
	local away = KN.dense({ rot(300, 45), rot(330, 90), rot(350, 160) })
	local C2, a0, a1, j0, j1 = KN.streetLine(away, pa, ea, pb, eb)
	ok(KN.parallelRun(C2, main, lim, { s0 = a0, s1 = a1, skip0 = j0, skip1 = j1 }) == 0, "turning away")
	-- 70 m off: no run
	local g70 = caseB(70)
	local pa7, _, ea7 = KN.chainBehind(13, "p", function(id) return KN.graphAt(g70, id) end)
	local C3, b0, b1, l0, l1 = KN.streetLine(KN.dense({ rot(300, 70), rot(400, 70) }), pa7, ea7, {}, "end")
	eq(KN.parallelRun(C3, main, lim, { s0 = b0, s1 = b1, skip0 = l0, skip1 = l1 }), 0)
	-- a street bent back beside itself at a sharp node counts (self)
	local hair = KN.dense({ { 0, 0 }, { 200, 0 }, { 170, 30 }, { -20, 30 } })
	ok(KN.parallelRun(hair, {}, lim, { skip0 = 0, skip1 = 0, self = true }) >= 110)
	eq(KN.parallelRun(hair, {}, lim, { skip0 = 0, skip1 = 0 }), 0)
	-- the walk's caps
	local w = KN.CHAIN_WALK
	KN.CHAIN_WALK = 1
	local pc, _, ec = KN.chainBehind(13, "p", at)
	KN.CHAIN_WALK = w
	eq(#pc, 1); eq(ec, "cap")
end)

test("case B, selector: the piece running on beside the main street waits (parallel, never relaxed); 70 m off it comes", function()
	local function mpB(off, extra)
		local pieces = { { key = "beside", a = "C", b = "D", pts = { rot(300, off), rot(400, off) }, class = "small" } }
		for _, p in ipairs(extra or {}) do pieces[#pieces + 1] = p end
		return { junctions = { C = rot(300, off), D = rot(400, off), M5 = rot(400, 0), X = rot(500, 0) }, pieces = pieces }
	end
	local on = { key = "main", a = "M5", b = "X", pts = { rot(400, 0), rot(500, 0) }, class = "medium" }
	local st, rep = run(caseB(), mpB(45, { on }), { steer = true }, "EU_EXTENSION", EXT)
	ok(st.main, "the main street goes on")
	ok(not st.beside, "the parallel street waits: " .. KN.text(rep.knotWhy))
	eq(rep.knotWhy.parallel, 1)
	-- alone: still held (no relax for parallel)
	local st2, rep2 = run(caseB(), mpB(45), { steer = true }, "EU_EXTENSION", EXT)
	ok(not st2.beside, "never relaxed: " .. KN.text(rep2.knotWhy))
	-- 70 m off (a block of two rows): it comes
	local st3 = run(caseB(70), mpB(70, { on }), { steer = true }, "EU_EXTENSION", EXT)
	ok(st3.beside and st3.main)
	-- other towns: as before
	local st4 = run(caseB(), mpB(45, { on }), nil, "EU_EXTENSION", EXT)
	ok(st4.beside)
	-- a connector piece too (§75: connectors were exempt)
	local mp5 = mpB(45, { on })
	mp5.pieces[1].connector = true
	local st5 = run(caseB(), mp5, { steer = true }, "EU_EXTENSION", EXT)
	ok(not st5.beside, "a connector beside the main street waits")
end)

test("case B within one increment: the pieces chosen before it count (the chain runs through this increment's pieces)", function()
	-- only the side stub 2 - 11 exists; three pieces run on beside the main street from its end
	local g = OG.new()
	for i = 0, 4 do
		local p = rot(i * 100, 0)
		OG.addNode(g, i + 1, p[1], p[2], 0)
		if i > 0 then OG.addEdge(g, 100 + i, i, i + 1, "medium") end
	end
	local A = rot(100, 45)
	OG.addNode(g, 11, A[1], A[2], 0)
	OG.addEdge(g, 111, 2, 11, "small")
	local mp = { junctions = { A = rot(100, 45), B = rot(200, 45), C = rot(300, 45), D = rot(400, 45) },
		pieces = {
			{ key = "q1", a = "A", b = "B", pts = { rot(100, 45), rot(200, 45) }, class = "small" },
			{ key = "q2", a = "B", b = "C", pts = { rot(200, 45), rot(300, 45) }, class = "small" },
			{ key = "q3", a = "C", b = "D", pts = { rot(300, 45), rot(400, 45) }, class = "small" } } }
	local st, rep = run(g, mp, { steer = true }, "EU_EXTENSION", EXT)
	ok(st.q1, "the first 100 m come (under the 110 m run)")
	ok(not st.q2 and not st.q3, "the next wait: " .. KN.text(rep.knotWhy))
	ok((rep.knotWhy.parallel or 0) >= 1)
end)

test("lattice: lanes a block depth apart (EU organic 45 m, MED hill 44 m) are no parallel knot", function()
	for _, b in ipairs({ { len = 60, depth = 45 }, { len = 44, depth = 30 } }) do
		local lim = KN.limits({ block = b })
		ok(lim.parM < 44, "under MIN_BLOCK: " .. lim.parM)
		local lane = KN.dense({ { 0, 44 }, { 300, 44 } })
		eq(KN.parallelRun(lane, { { { -50, 0 }, { 350, 0 } } }, lim, { skip0 = 0, skip1 = 0 }), 0)
	end
end)

-- near-miss joins: the parallel run over the street the join makes
local function street(g, id, pts, z)
	local ids, prev = {}, nil
	for k, p in ipairs(pts) do
		local n = g.nodeById[id + k - 1] or OG.addNode(g, id + k - 1, p[1], p[2], z or 20)
		ids[#ids + 1] = n.id
		if prev then OG.addEdge(g, nil, prev, n.id, "small").template = SMALL end
		prev = n.id
	end
	return ids
end
local function nmStyle(extra)
	local s = { templatePaths = { main = SMALL, medium = SMALL, small = SMALL }, block = { len = 110, depth = 80 },
		maxSlope = 0.1, waterSetback = 10, seed = 7 }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end
local function sure(fn)
	local a, b = NM.P_NEAR, NM.P_FAR
	NM.P_NEAR, NM.P_FAR = 1.01, 1.01
	local okR, err = pcall(fn)
	NM.P_NEAR, NM.P_FAR = a, b
	assert(okR, err)
end

test("near-miss: a join that makes a street run on beside another is a parallel knot (the street behind it counts)", function()
	local lim = KN.limits({ block = EXT })
	-- a main street along y = 0; a stub beside it 45 m north for 160 m; a join from its end 70 m on, still beside it
	local g = OG.new()
	street(g, 1, { { -100, 0 }, { 0, 0 }, { 100, 0 }, { 200, 0 }, { 300, 0 } })
	street(g, 20, { { -100, 0 }, { -60, 45 } })   -- (off node 1: the junction)
	street(g, 21, { { -60, 45 }, { 40, 45 }, { 100, 45 } })
	street(g, 30, { { 170, 45 }, { 260, 45 }, { 330, 60 } })
	local Pp = KN.dense({ { 100, 45 }, { 170, 45 } })
	ok(NM.parallelKnot(g, 23, 30, Pp, lim), "the joined street runs 230 m beside the main street")
	-- the piece alone (the old rule) saw nothing: 70 m, both ends skipped
	local others = {}
	for _, e in ipairs(g.edges) do
		if e.n0 <= 5 and e.n1 <= 5 then others[#others + 1] = KN.edgePts(g, e) end
	end
	eq(#others, 4)
	ok(KN.parallelRun(Pp, others, lim) < lim.parRun, "the join alone: under the run")
	eq(KN.parallelRun(Pp, others, { parM = 35, parRun = 110, parCos = lim.parCos }), 0, "the old 35 m: nothing")
	-- 80 m north: none
	local g2 = OG.new()
	street(g2, 1, { { -100, 0 }, { 0, 0 }, { 100, 0 }, { 200, 0 }, { 300, 0 } })
	street(g2, 20, { { -100, 0 }, { -60, 80 } })
	street(g2, 21, { { -60, 80 }, { 40, 80 }, { 100, 80 } })
	street(g2, 30, { { 170, 80 }, { 260, 80 }, { 330, 95 } })
	ok(not NM.parallelKnot(g2, 23, 30, KN.dense({ { 100, 80 }, { 170, 80 } }), lim))
end)

-- case C: a T at (-10, 100) (a 100 m stub west), the street on south to a dead end at (-10, 0); a street from the
-- south-west running east to a dead end at (-65, -45), 71 m away, at right angles; a forest town with the woods all
-- round its cleared land
local function caseC()
	local g = OG.new()
	street(g, 1, { { -10, 250 }, { -10, 100 }, { -10, 0 } })
	street(g, 10, { { -10, 100 }, { -110, 100 } })
	street(g, 20, { { -265, -45 }, { -165, -45 }, { -65, -45 } })
	return g
end
-- dense woods everywhere but the town's land (cells with centres at x -270..20, y -80..270): the join's corner is
-- cleared land, but a big wood lies within FOREST_R 40 m (+ half a cell) of the dead end at (-10, 0)
local function woods()
	return FO.fromFunction(0, 0, function(x, y) return (x > -270 and x < 20 and y > -80 and y < 270) and 0 or 400 end, 900, 50)
end

test("case C: two dead ends at right angles 71 m apart in a forest town are joined by a corner (cleared land)", function()
	sure(function()
		local wood = woods()
		ok(FO.bigWoodNear(wood, -10, 0, 40), "the old rule's woods: a big wood by the dead end")
		eq(NM.woodRun(wood, { { -65, -45 }, { -10, -45 }, { -10, 0 } }), 0, "the corner runs on cleared land")
		-- the corner shape: both streets straight on to (-10, -45)
		local c = NM.corner(-65, -45, 0, -10, 0, -math.pi / 2)
		ok(c and c.corner, "a corner")
		near(c.pts[2][1], -10, 1e-6); near(c.pts[2][2], -45, 1e-6)
		eq(NM.corner(-65, -45, 0, -10, 0, math.pi / 2), nil, "N heading away (its line behind): none")
		eq(NM.corner(-65, -45, 0, -10, 0, rad(170)), nil, "a hairpin: over CORNER_MAX_DEG")
		eq(NM.corner(-20, -45, 0, -10, 0, -math.pi / 2), nil, "a leg under CORNER_LEG_MIN")
		for _, mode in ipairs({ "hug", "deep" }) do
			local add, rep = NM.joins(caseC(), nmStyle({ forest = { mode = mode, grid = wood } }), nil,
				{ terrain = F.flat, seed = 3 })
			ok(add ~= nil, mode .. ": joined: " .. select(2, NM.text(rep)))
			eq(rep.joins[1], "pair:71c", mode .. ": a corner of the pair")
			eq(#add.edges, 2)
			-- (the corner a new node; ot_plan's two chords meet there at right angles)
			local e1, e2 = add.edges[1], add.edges[2]
			near(e1.p1[1], -10, 0.01); near(e1.p1[2], -45, 0.01)
			local geo = CK.increment(add, caseC())
			ok(CK.passes(geo), CK.summary(geo))
			ok(geo.maxCorner == 0 or geo.maxCorner >= 45)
			eq(e2.node1 == 3 or e1.node0 == 3, true)
		end
		-- the old forest rule (a big wood within FOREST_R of the dead end or the middle) kept it for good with this
		-- seed's draw: the pair's draw is fixed
		local keep = FO.isDeep({ mode = "deep", grid = wood }) and NM.DEEP_KEEP or NM.FOREST_KEEP
		ok(rng.draw(3, "nmWood", 3, 22) < keep, "seed 3's draw keeps it under the old rule")
		-- through the woods: the forest rule still applies (the cleared land shifted away from the corner)
		local thick = FO.fromFunction(0, 0, function() return 400 end, 900, 50)
		local kept = 0
		for seed = 1, 20 do
			local _, rep = NM.joins(caseC(), nmStyle({ forest = { mode = "deep", grid = thick } }), nil,
				{ terrain = F.flat, seed = seed })
			if (rep.why.forest or 0) > 0 then kept = kept + 1 end
		end
		ok(kept >= 8, "in the woods most are left (DEEP_KEEP): " .. kept)
		-- without the corner, a bend (arc) closes it here too: the woods were the reason
		NM.CORNER = false
		local add2, rep2 = NM.joins(caseC(), nmStyle({ forest = { mode = "deep", grid = wood } }), nil, { terrain = F.flat, seed = 3 })
		NM.CORNER = true
		ok(add2 ~= nil and rep2.joins[1] == "pair:71", select(2, NM.text(rep2)))
	end)
end)

test("the driver's retiredOk reaches the near-miss pass (ot_core.nearMissPass dropped it before §75)", function()
	local seen = nil
	local real = NM.joins
	NM.joins = function(_g, _st, _inc, o) seen = o return nil, { found = 0, joined = 0, kept = 0, why = {}, joins = {} } end
	local st, stats = F.style({ forceStyle = "EU_ORGANIC", townId = 3, year = 1905, capacity = 2000 }, F.flat)
	local fn = function() return true end
	local okR, err = pcall(core.planIncrement, caseC(), st, { terrain = F.flat, stats = stats,
		nearMiss = { retiredOk = fn, midOk = fn } })
	NM.joins = real
	assert(okR, err)
	ok(seen ~= nil and seen.retiredOk == fn and seen.midOk == fn)
end)

test("near-miss T: at 60 deg or more off every street (TEE_MIN_DEG = the side rule)", function()
	eq(NM.TEE_MIN_DEG, CK.LIMITS.sideAngle)
	ok(NM.endOk({ 0, math.pi }, rad(120)))
	ok(not NM.endOk({ 0, math.pi }, rad(130)), "50 deg off the west street")
	ok(NM.endOk({ 0, math.pi }, rad(65)))
end)

test("checker: a side street at the limit (a near-miss T clamped to 60 deg) is no geoSide; 59 deg is", function()
	-- (run 2026-10-19_1949_sqot: 6 plans with geoSide=1, each a near-miss join at minAngle=60.00)
	local function at(deg)
		local g = OG.new()
		OG.addNode(g, 1, -200, 0, 0)
		OG.addNode(g, 2, 0, 0, 0)
		OG.addEdge(g, 11, 1, 2, "small")
		local through = { pts = { { 0, 0 }, { 100, 0 }, { 200, 0 } }, class = "small", startNode = 2, key = "on" }
		local a = rad(deg)
		local side = { pts = { { 100, 0 }, { 100 + 80 * math.cos(a), 80 * math.sin(a) } }, class = "small", key = "side" }
		local inc = PL.plan(g, { through, side }, { join = "any", maxSeg = 100, minAngle = 25 })
		local k = {}
		for _, e in ipairs(inc.edges) do k[e.key] = true end
		ok(k.on and k.side, "both streets planned at " .. deg)
		return CK.increment(inc, g).counts.side or 0
	end
	ok(CK.SIDE_TOL > 0 and CK.SIDE_TOL <= 0.5)
	eq(at(60 - CK.SIDE_TOL / 4), 0, "at the limit")
	eq(at(60), 0)
	eq(at(59), 1, "a degree under it")
end)

test("knot text: cross / parallel / loop / side / row", function()
	eq(KN.text({ cross = 1, parallel = 2, loop = 3, side = 4 }), "1/2/3/4/0")
	eq(KN.text({ row = 5 }), "0/0/0/0/5")
	eq(KN.text(nil), "0/0/0/0/0")
	local _ = G
end)
