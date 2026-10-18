-- §70 (2026-10-15; run 2026-10-15_2031_sqot): the lock maturity sooner (ot_lockpol.maturity: persons, size, age since
-- the first frame; the frame's `fy`; the driver's CHECK `lockMat=<v>:size:age:base`) and the knot look rules
-- (ot_knot + ot_select: crossings off a shared node on the curves, long near-parallel runs, small loops; relaxed only
-- when the increment would be empty).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local LP = ug_require(F.DIR .. "ot_lockpol.lua")
local KN = ug_require(F.DIR .. "ot_knot.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")

local TOWN = 7

-- the 2031 towns at year 40 (buildings, the persons measure logged as lockMat)
local RUN_2031 = { { "Dalemere", 534, 0.12 }, { "Shaw", 473, 0.10 }, { "Norfield", 462, 0.16 },
	{ "Little Dalemere", 431, 0.10 }, { "Holtbottom", 311, 0.00 }, { "Ashgrove", 288, 0.00 },
	{ "Two Waters", 795, 1.00 }, { "Merehythe", 714, 1.00 } }

test("maturity: the larger of persons, size and gated age; young and small towns stay steered", function()
	-- the base alone (no buildings, no age): as §69
	eq((LP.maturity(0.4, 0, nil, 1)), 0.4)
	eq((LP.maturity(nil, 0, nil, 1)), 0)
	-- size: 0 up to SIZE_B[1], 1 from SIZE_B[2]
	eq((LP.maturity(0, LP.SIZE_B[1], nil, 1)), 0)
	eq((LP.maturity(0, LP.SIZE_B[2], nil, 1)), 1)
	-- age: at most AGE_W, gated by the size
	local v, p = LP.maturity(0, 1000, 100, 1)
	eq(v, 1); near(p.age, LP.AGE_W, 1e-9)
	local _, p2 = LP.maturity(0, 0.5 * LP.AGE_GATE_B, 100, 1)
	near(p2.age, 0.5 * LP.AGE_W, 1e-9)
	eq(select(2, LP.maturity(0, 300, LP.AGE_Y[1], 1)).age, 0)
	-- an old hamlet stays young; a young town of 200 buildings too
	ok(LP.maturity(0, 60, 40, 1) < 0.15, "hamlet " .. LP.maturity(0, 60, 40, 1))
	ok(LP.maturity(0, 200, 10, 1) < 0.2, "young town " .. LP.maturity(0, 200, 10, 1))
	ok(LP.innerK(LP.maturity(0, 300, 20, 1)) < 0.3, "300 buildings at 20 years still mostly locked")
	-- the 2031 towns at 40 years: the mid-size ones open inside (innerK over half the outline), the grown stay grown
	for _, r in ipairs(RUN_2031) do
		local m = LP.maturity(r[3], r[2], 40, 1)
		ok(m >= r[3])
		if r[2] >= 280 then ok(LP.innerK(m) >= 0.45, string.format("%s %.2f -> %.2f", r[1], r[3], m)) end
		if r[2] >= 430 then ok(m >= 0.75, string.format("%s %.2f -> %.2f", r[1], r[3], m)) end
	end
	-- bad inputs
	eq((LP.maturity(0 / 0, 0 / 0, 0 / 0, 0 / 0)), 0)
	-- scale: grid styles and later eras need more / fewer buildings
	ok(LP.sizeScale({ grower = "grid" }, 1900) > LP.sizeScale({ grower = "organic" }, 1900))
	ok(LP.sizeScale({ grower = "organic" }, 2000) < LP.sizeScale({ grower = "organic" }, 1900))
	eq(LP.sizeScale({ grower = "organic" }, nil), 1)
	ok(LP.maturity(0, 450, nil, LP.sizeScale({ grower = "grid" }, 1900)) < LP.maturity(0, 450, nil, 1))
	eq(LP.matText(0.5, { size = 0.25, age = 0.5, base = 0.1 }), "0.50:size0.25:age0.50:base0.10")
	eq(LP.matText(nil), "-")
end)

test("frame year: saved as fy (x 100), read back as year; frames from before have none", function()
	local fp = SV.frameParam(TOWN, { axis = 0, centre = { 0, 0 } }, nil, nil, nil, { lock = "steer", year = 1903.5 })
	eq(fp.fy, 190350)
	local s = SV.applyFrame(SV.normalize(nil), fp)
	near(SV.frame(s, TOWN).year, 1903.5, 1e-9)
	-- a save round trip keeps it
	near(SV.frame(SV.normalize(s), TOWN).year, 1903.5, 1e-9)
	-- old frames: no fy, no year; bad values dropped
	local s2 = SV.applyFrame(SV.normalize(nil), { town = 8, a = 0, x = 0, y = 0 })
	eq(SV.frame(s2, 8).year, nil)
	local s3 = SV.applyFrame(SV.normalize(nil), { town = 9, a = 0, x = 0, y = 0, fy = 0 / 0 })
	eq(SV.frame(s3, 9).year, nil)
	eq(SV.frameParam(TOWN, { axis = 0, centre = { 0, 0 } }, nil, nil, nil, { lock = "steer" }).fy, nil)
end)

local function fakeE(year)
	local E = { t = 0, logs = {}, events = {} }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.name(t) return "Town" .. t end
	function E.closestTown() return TOWN end
	function E.context() return {} end
	function E.sendEvent(_id, name, param) E.events[#E.events + 1] = { name = name, param = param } end
	function E.yearF() return year end
	function E.year() return math.floor(year or 1960) end
	return E
end

local function measured(buildings)
	local edges, built, lot = {}, {}, {}
	for k = 0, 15 do
		local a = k * 2 * math.pi / 16
		local id = k + 1
		edges[#edges + 1] = { id = id, p0 = { math.cos(a) * 100, math.sin(a) * 100 }, p1 = { math.cos(a) * 200, math.sin(a) * 200 } }
		built[id] = 3
		lot[#lot + 1] = { id = id }
	end
	return { ext = { cx = 0, cy = 0, r = 300 }, edges = edges, lotEdges = lot, builtBy = built, dem = { mat = 0.1 },
		buildings = buildings }
end

test("driver: the CHECK's lock maturity from persons, size and the age since the first frame (s.mat left to densify)", function()
	local saved = SV.applyFrame(SV.normalize(nil), { town = TOWN, a = 0, x = 0, y = 0, lm = 2, fy = 190000 })
	local d = D.new(fakeE(1940))
	d.opts = { debug = false }
	d.saved = saved
	local s = d:townState(TOWN)
	eq(d:townLockMode(TOWN, saved), "steer")
	s.mat = 0.42   -- (the densify draw's level maturity: steerNote no longer overwrites it)
	d:steerNote(TOWN, measured(430), saved)
	local want, parts = LP.maturity(0.1, 430, 40, LP.sizeScale({ grower = "organic" }, 1940))
	near(s.lockMat, want, 1e-9)
	near(s.lockMatParts.age, parts.age, 1e-9)
	ok(s.lockMat > 0.7, tostring(s.lockMat))
	eq(s.mat, 0.42)
	-- a frame without a year: no age part, the size still counts
	local d2 = D.new(fakeE(1940))
	d2.opts = { debug = false }
	local saved2 = SV.applyFrame(SV.normalize(nil), { town = TOWN, a = 0, x = 0, y = 0, lm = 2 })
	d2.saved = saved2
	d2:steerNote(TOWN, measured(430), saved2)
	eq(d2:townState(TOWN).lockMatParts.age, 0)
	ok(d2:townState(TOWN).lockMat < s.lockMat)
	-- steerPrep hands the lock maturity to the policy
	local job = { town = TOWN, inc = { edges = {} }, ext = { cx = 0, cy = 0, r = 300 }, style = { grower = "organic" }, force = true }
	d:jobLock(job)
	d:steerPrep(job)
	near(job.steerC.mat, s.lockMat, 1e-9)
end)

-- knots: geometry
test("knot geometry: crossings off a shared end, near-parallel runs, loop area, the way back", function()
	-- an X
	ok(KN.crosses({ { 0, 0 }, { 100, 100 } }, { { 0, 100 }, { 100, 0 } }))
	-- two streets from one node: no crossing at the shared end
	ok(not KN.crosses({ { 0, 0 }, { 100, 0 } }, { { 0, 0 }, { 0, 100 } }, { [1] = true }, { [1] = true }))
	-- a curve leaving a node and coming back across its neighbour street
	ok(KN.crosses({ { 0, 0 }, { 50, 60 }, { -30, 60 }, { -30, -40 } }, { { 0, 0 }, { -150, 0 } }, { [1] = true }, { [1] = true }))
	local lim = KN.limits({ block = { len = 60, depth = 45 } })
	near(lim.parM, 0.65 * 45, 1e-9)
	eq(lim.parRun, 60)
	-- 22 m beside a straight street for 260 m: a run; 60 m apart (a block): none; a continuation: none
	ok(KN.parallelRun({ { 0, 22 }, { 300, 22 } }, { { { -50, 0 }, { 350, 0 } } }, lim) >= 200)
	eq(KN.parallelRun({ { 0, 60 }, { 300, 60 } }, { { { -50, 0 }, { 350, 0 } } }, lim), 0)
	eq(KN.parallelRun({ { 0, 0 }, { 300, 0 } }, { { { -300, 0 }, { 0, 0 } } }, lim), 0)
	-- crossing at a right angle: not parallel
	eq(KN.parallelRun({ { 150, -150 }, { 150, 150 } }, { { { 0, 0 }, { 300, 0 } } }, lim), 0)
	near(KN.area({ { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } }), 100, 1e-9)
	-- the way back: a square of 4 nodes; from 1 to 2 the short way is the direct edge
	local pos = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }
	local adj = { { { 2, 100 }, { 4, 100 } }, { { 1, 100 }, { 3, 100 } }, { { 2, 100 }, { 4, 100 } }, { { 3, 100 }, { 1, 100 } } }
	local path, len = KN.way(1, 3, function(id) return adj[id] end, function(id) return pos[id][1], pos[id][2] end, 1000)
	eq(len, 200); eq(#path, 3)
	eq(KN.way(1, 3, function(id) return adj[id] end, function(id) return pos[id][1], pos[id][2] end, 150), nil, "beyond perim")
	-- loop cap: WALK_MAX settled nodes
	local cap = KN.WALK_MAX
	KN.WALK_MAX = 1
	eq(KN.way(1, 3, function(id) return adj[id] end, function(id) return pos[id][1], pos[id][2] end, 1000), nil)
	KN.WALK_MAX = cap
	-- the curve of an edge with tangents bulges off its chord
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 100, y = 0 } },
		edges = { { id = 9, node0 = 1, node1 = 2, t0 = { 80, 60, 0 }, t1 = { 80, -60, 0 } } } })
	local P = KN.edgePts(g, g.edgeById[9])
	local top = 0
	for _, p in ipairs(P) do top = math.max(top, p[2]) end
	ok(top > 10, "bulge " .. top)
end)

-- a town street: 1 (0, 0) - 2 (150, 0) - 3 (300, 0), and 2 - 4 (150, -100)
local function street()
	return OG.fromSnapshot({ nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 150, y = 0 }, { id = 3, x = 300, y = 0 },
		{ id = 4, x = 150, y = -100 } },
		edges = { { id = 11, node0 = 1, node1 = 2 }, { id = 12, node0 = 2, node1 = 3 }, { id = 13, node0 = 2, node1 = 4 } } })
end

local function run(mp, lim)
	local style = F.style({ forceStyle = "EU_ORGANIC" })
	style.centre = { 150, 0 }
	style.block = { len = 100, depth = 60 }
	local st, rep = SEL.select(street(), mp, style, { join = "any", joinR = 60, maxEdges = 12, limits = lim,
		terrain = F.flat, leadDepth = false })
	local out = {}
	for _, s in ipairs(st) do out[s.key] = true end
	return out, rep
end

test("knot rule: a piece crossing its own node's street, one running beside a street, a small loop wait; others come", function()
	local mp = { junctions = { N1 = { 0, 0 }, N2 = { 150, 0 }, N3 = { 300, 0 }, N4 = { 150, -100 }, P = { 280, 22 },
		X = { 120, -40 }, O = { 400, 0 } },
		pieces = {
			-- beside the street 22 m off for 260 m (its middle clear of occR: classifyPiece let it through)
			{ key = "beside", a = "N1", b = "P", pts = { { 0, 0 }, { 20, 22 }, { 280, 22 } }, class = "small" },
			-- leaves node 2, loops round and crosses the street 1-2 (an edge at its own end node: skipped by the chord test)
			{ key = "lasso", a = "N2", b = "X", pts = { { 150, 0 }, { 200, 60 }, { 120, 60 }, { 120, -40 } }, class = "small" },
			-- from 2 to 4 beside the street 2-4: a loop of 2000 m2 (half a block is 3000)
			{ key = "sliver", a = "N2", b = "N4", pts = { { 150, 0 }, { 110, -50 }, { 150, -100 } }, class = "small" },
			-- straight on from 3: fine
			{ key = "on", a = "N3", b = "O", pts = { { 300, 0 }, { 400, 0 } }, class = "small" } } }
	local plain = run(mp, nil)
	ok(plain.beside and plain.lasso and plain.sliver, "without the rule (other towns): all come")
	local st, rep = run(mp, { steer = true })
	ok(st.on, "the straight piece comes")
	ok(not st.beside and not st.lasso and not st.sliver, "the knots wait: " .. tostring(st.beside) .. tostring(st.lasso) .. tostring(st.sliver) .. " " .. KN.text(rep.knotWhy))
	ok(rep.knotHeld >= 3, "held " .. rep.knotHeld)
	ok((rep.knotWhy.cross or 0) >= 1 and (rep.knotWhy.parallel or 0) >= 1 and (rep.knotWhy.loop or 0) >= 1,
		KN.text(rep.knotWhy))
	ok(not rep.knotRelax)
	-- only a knot left: it gives way rather than an empty increment
	local mp2 = { junctions = mp.junctions, pieces = { mp.pieces[2] } }
	local st2, rep2 = run(mp2, { steer = true })
	ok(st2.lasso, "relaxed when nothing else fits")
	ok(rep2.knotRelax)
	-- off: the old behaviour (§71: the lasso is a curled dead end too, so the hook rule goes off with it)
	SEL.KNOT, SEL.HOOK = false, false
	local st3 = run(mp, { steer = true })
	SEL.KNOT, SEL.HOOK = true, true
	ok(st3.beside and st3.lasso, "M.KNOT off")
end)

test("knot rule: two pieces of one increment crossing each other: the second waits", function()
	local mp = { junctions = { N1 = { 0, 0 }, N3 = { 300, 0 }, A = { 250, 150 }, B = { 50, 150 } },
		pieces = {
			{ key = "a1", a = "N1", b = "A", pts = { { 0, 0 }, { 250, 150 } }, class = "small" },
			{ key = "b1", a = "N3", b = "B", pts = { { 300, 0 }, { 50, 150 } }, class = "small" } } }
	local st, rep = run(mp, { steer = true })
	ok((st.a1 and not st.b1) or (st.b1 and not st.a1), "one of the X: " .. tostring(st.a1) .. tostring(st.b1) .. KN.text(rep.knotWhy))
	eq(rep.knotWhy.cross, 1)
end)

test("clearing corridor: woods on both sides ahead face forest; a wide clearing or one side does not; no tip there", function()
	local FO = ug_require(F.DIR .. "ot_forest.lua")
	local SK = ug_require(F.DIR .. "ot_skeleton.lua")
	local GL = ug_require(F.DIR .. "ot_glock.lua")
	local narrow = FO.fromFunction(0, 0, function(_x, y) return math.abs(y) > 90 and 200 or 0 end, 1500, 50)
	local wide = FO.fromFunction(0, 0, function(_x, y) return math.abs(y) > 200 and 200 or 0 end, 1500, 50)
	local oneSide = FO.fromFunction(0, 0, function(_x, y) return y > 90 and 200 or 0 end, 1500, 50)
	ok(SK.corridorAt(narrow, 300, 0, 0, 1) ~= nil)
	eq(SK.corridorAt(wide, 300, 0, 0, 1), nil)
	eq(SK.corridorAt(oneSide, 300, 0, 0, 1), nil)
	eq(SK.corridorAt(nil, 300, 0, 0, 1), nil)
	-- a street at (150..200, 0) heading east into the clearing
	eq(LP.facing(200, 0, 1, 0, { fg = narrow }), "forest")
	eq(LP.facing(200, 0, 1, 0, { fg = wide }), nil)
	eq(LP.facing(200, 0, 1, 0, { fg = oneSide }), nil)
	LP.CORRIDOR = false
	eq(LP.facing(200, 0, 1, 0, { fg = narrow }), nil)
	LP.CORRIDOR = true
	-- tips: a branch's dead end in the clearing is rejected (corridor), in the open it is picked
	local edges = { { key = "b1", node0 = 5, node1 = -1, p0 = { 300, 0 }, p1 = { 420, 0 } } }
	local picks, rej = GL.pickTips(edges, { b1 = "out" }, { fg = narrow }, 0, 0, 300, {}, 2)
	eq(#picks, 0); eq(rej.corridor, 1)
	local picks2 = GL.pickTips(edges, { b1 = "out" }, { fg = wide }, 0, 0, 300, {}, 2)
	eq(#picks2, 1)
end)
