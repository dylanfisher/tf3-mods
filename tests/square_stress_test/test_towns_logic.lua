-- stress_logic.tl, Towns tab (Phase 2): serial queue lane, factor math, placement grids, distance
-- filtering, placement relaxation, build-out passes, town numbering, nearest pairs and the readout.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl"

local function clock(t) return function() return t[1] end end

---------------------------------------------------------------------------
-- serial lane

test("serial job: one step, then waits for resume; finishes only after the last resume", function()
	local q = logic.newQueue(4)
	local t = { 0 }
	local steps, job = {}, nil
	job = logic.push(q, { name = "s", total = 3, serial = true, step = function(i, j) steps[#steps + 1] = i; eq(j, job) end })
	eq(#logic.tick(q, clock(t)), 0)
	eq(steps, { 1 })
	eq(job.waiting, true)
	logic.tick(q, clock(t))
	eq(steps, { 1 }) -- still waiting
	logic.resume(job)
	logic.tick(q, clock(t))
	eq(steps, { 1, 2 })
	logic.resume(job)
	local done = logic.tick(q, clock(t))
	eq(steps, { 1, 2, 3 })
	eq(#done, 0) -- last step's callback still outstanding
	eq(#q.jobs, 1)
	logic.resume(job)
	done = logic.tick(q, clock(t))
	eq(#done, 1)
	eq(done[1].count, 3)
	eq(#q.jobs, 0)
end)

test("serial jobs share one lane; a normal job behind a waiting serial job still runs", function()
	local q = logic.newQueue(4)
	local t = { 0 }
	local log = {}
	local a = logic.push(q, { name = "a", total = 1, serial = true, step = function() log[#log + 1] = "a" end })
	logic.push(q, { name = "b", total = 1, serial = true, step = function() log[#log + 1] = "b" end })
	logic.push(q, { name = "n", total = 2, step = function(i) log[#log + 1] = "n" .. i end })
	logic.tick(q, clock(t))
	eq(log, { "a", "n1", "n2" }) -- b waits for a's callback
	logic.resume(a)
	logic.tick(q, clock(t))
	eq(log, { "a", "n1", "n2", "b" })
end)

test("serial: a step that resumes at once (nothing sent) lets the next step run in the same tick", function()
	local q = logic.newQueue(4)
	local n = 0
	logic.push(q, { name = "skip", total = 3, serial = true, step = function(_i, j) n = n + 1; logic.resume(j) end })
	local done = logic.tick(q, clock({ 0 }))
	eq(n, 3)
	eq(#done, 1)
end)

test("serial: a failing step doesn't wait; a missing callback times out as an error", function()
	local q = logic.newQueue(4)
	local t = { 0 }
	logic.push(q, { name = "err", total = 2, serial = true, step = function(i) if i == 1 then error("boom") end end,
		waitTimeoutUs = 5000000 })
	logic.tick(q, clock(t))
	local job = q.jobs[1]
	eq(job.done, 2)
	eq(job.errors, 1)
	eq(job.waiting, true) -- step 2 sent and waits
	t[1] = 4000000
	eq(#logic.tick(q, clock(t)), 0)
	t[1] = 6000000
	local done = logic.tick(q, clock(t))
	eq(#done, 1)
	eq(done[1].errors, 2)
	logic.resume(job) -- late callback after clear/finish: harmless
end)

test("progress uses the label: Growing x10 3/12", function()
	local q = logic.newQueue(1)
	logic.push(q, { name = "grow_x10", label = "Growing x10", total = 12, serial = true, step = function() end })
	logic.tick(q, clock({ 0 }))
	eq(logic.progress(q), "Growing x10 1/12")
	eq(logic.doneLine({ name = "grow_x10", count = 12, errors = 0, wallMs = 5, busyMs = 1 }):match("action=(%S+)"), "grow_x10")
end)

---------------------------------------------------------------------------
-- factors

test("grownFactors multiplies, caps at MAX_SIZE_FACTOR, nil resets to 1", function()
	eq(logic.grownFactors({ 1, 2, 3 }, 10), { 10, 20, 30 })
	eq(logic.grownFactors(nil, 5), { 5, 5, 5 })
	local f, capped = logic.grownFactors({ 100, 100, 5 }, 100)
	eq(f, { 1000, 1000, 500 })
	eq(capped, true)
	local r, c2 = logic.grownFactors({ 50, 50, 50 }, nil)
	eq(r, { 1, 1, 1 })
	eq(c2, false)
end)

test("listText formats numbers and lists", function()
	eq(logic.listText({ 1, 2.5, 3 }), "{1,2.5,3}")
	eq(logic.listText(nil), "nil")
	eq(logic.listText({ { 1, 2 }, 3 }), "{{1,2},3}")
end)

---------------------------------------------------------------------------
-- placement

test("spiralPoints: centre first, then the 4 neighbours at spacing, fixed order, exact count", function()
	local p = logic.spiralPoints(1000, 2000, 9, 100)
	eq(#p, 9)
	eq(p[1], { 1000, 2000 })
	for k = 2, 5 do
		local dx, dy = p[k][1] - 1000, p[k][2] - 2000
		eq(dx * dx + dy * dy, 10000)
	end
	for k = 6, 9 do
		local dx, dy = p[k][1] - 1000, p[k][2] - 2000
		eq(dx * dx + dy * dy, 20000)
	end
	eq(logic.spiralPoints(0, 0, 9, 100), logic.spiralPoints(0, 0, 9, 100))
	eq(#logic.spiralPoints(0, 0, 160, 10), 160)
	eq(#logic.spiralPoints(0, 0, 0, 10), 0)
end)

test("mapGrid: centred grid inside the margin", function()
	local g = logic.mapGrid(-5000, -5000, 5000, 5000, 3000, 1000)
	-- inner box -4000..4000 (8000 wide): 3 columns at -3000, 0, 3000
	eq(#g, 9)
	eq(g[1], { -3000, -3000 })
	eq(g[5], { 0, 0 })
	eq(g[9], { 3000, 3000 })
	eq(#logic.mapGrid(0, 0, 1000, 1000, 500, 600), 0) -- margin eats the map
end)

test("spreadSpacing: about 2n cells, never below the minimum", function()
	near(logic.spreadSpacing(0, 0, 20000, 20000, 8, 1000, 1500), math.sqrt(18000 * 18000 / 16), 1e-6)
	eq(logic.spreadSpacing(0, 0, 4000, 4000, 25, 1000, 1500), 1500)
end)

test("spreadPick: evenly from the list, all when n >= #points", function()
	local pts = {}
	for i = 1, 10 do pts[i] = { i, 0 } end
	local p = logic.spreadPick(pts, 2)
	eq(p, { { 3, 0 }, { 8, 0 } })
	eq(#logic.spreadPick(pts, 10), 10)
	eq(#logic.spreadPick(pts, 20), 10)
	eq(#logic.spreadPick(pts, 0), 0)
end)

test("placeTowns: skips spots near existing towns, near each other, and bad terrain", function()
	local cands = { { 0, 0 }, { 100, 0 }, { 2000, 0 }, { 4000, 0 }, { 6000, 0 }, { 8000, 0 } }
	local existing = { { 0, 500 } }
	local water = function(x, _y) if x == 4000 then return false, "water" end return true end
	local placed, skipped = logic.placeTowns(cands, existing, 2, 1500, water)
	eq(placed, { { 2000, 0 }, { 6000, 0 } })
	eq(skipped, { near = 2, water = 1 })
	-- accepted points keep their distance from each other
	local close = logic.placeTowns({ { 0, 0 }, { 1000, 0 }, { 1600, 0 } }, {}, 5, 1500, nil)
	eq(close, { { 0, 0 }, { 1600, 0 } })
end)

test("near-camera placement end to end: ring around the camera, n towns, all spaced", function()
	local cands = logic.spiralPoints(0, 0, 5 * 6 + 10, 1500)
	local placed = logic.placeTowns(cands, { { 0, 0 } }, 5, 1500, function() return true end)
	eq(#placed, 5)
	for i = 1, #placed do
		for j = i + 1, #placed do
			local dx, dy = placed[i][1] - placed[j][1], placed[i][2] - placed[j][2]
			ok(dx * dx + dy * dy >= 1500 * 1500 - 1e-6)
		end
		ok(placed[i][1] ~= 0 or placed[i][2] ~= 0, "camera spot is taken by an existing town")
	end
end)

---------------------------------------------------------------------------
-- placement relaxation

local function fixed(points) return function() return points end end
local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

test("stepDistance: fraction of the spacing, never below MIN_TOWN_DIST (800 m)", function()
	eq(logic.MIN_TOWN_DIST, 800)
	local s = logic.PLACE_STEPS
	eq(s[1].label, "strict")
	eq(logic.stepDistance(s[1], 2500), 2500)
	near(logic.stepDistance(s[3], 2500), 1750, 1e-9)
	eq(logic.stepDistance(s[4], 2500), 1250)
	eq(logic.stepDistance(s[4], 1200), 800) -- Small at 50% would be 600
	for _, st in ipairs(s) do ok(st.dist <= 1 and st.dist >= 0.5 and st.widen >= 1) end
end)

test("placeRelaxed: strict pass enough -> one step, relaxation=none", function()
	local placed, tried = logic.placeRelaxed(1, { { 0, 0 } }, 1500, fixed({ { 2000, 0 } }), nil, false)
	eq(placed, { { 2000, 0 } })
	eq(#tried, 1)
	eq(tried[1].label, "strict")
	ok(logic.placementText(tried):find("^relaxation=none | strict 1500m cands=1 placed=1 %(none%)$"), logic.placementText(tried))
end)

test("placeRelaxed: shrinks the distance step by step until it fits (100% -> wider -> 70%)", function()
	local seen = {}
	local placed, tried = logic.placeRelaxed(1, { { 0, 0 } }, 2000, function(step, minDist)
		seen[#seen + 1] = { step.label, minDist }
		return { { 1500, 0 } }
	end, nil, false)
	eq(placed, { { 1500, 0 } })
	eq(#tried, 3)
	eq(seen[1], { "strict", 2000 })
	eq(seen[2], { "wider", 2000 })
	eq(seen[3][1], "70%")
	near(seen[3][2], 1400, 1e-9)
	eq(tried[1].skipped, { near = 1 })
	eq(tried[3].placed, 1)
	local txt = logic.placementText(tried)
	ok(txt:find("^relaxation=70%% | strict 2000m cands=1 placed=0 %(near=1%) | wider"), txt)
end)

test("placeRelaxed: never closer than 800 m, even at the last step", function()
	local placed, tried = logic.placeRelaxed(1, { { 0, 0 } }, 1200, fixed({ { 700, 0 } }), nil, false)
	eq(placed, {})
	eq(#tried, #logic.PLACE_STEPS)
	eq(tried[#tried].minDist, 800)
	ok(logic.placementText(tried):find("^relaxation=50%%"))
end)

test("placeRelaxed: water and edge never relax", function()
	local water = function() return false, "water" end
	local placed, tried = logic.placeRelaxed(2, {}, 1500, fixed({ { 0, 0 }, { 5000, 0 } }), water, false)
	eq(placed, {})
	eq(#tried, 4)
	for _, t in ipairs(tried) do eq(t.skipped, { water = 2 }) end
end)

test("placeRelaxed: towns placed by an earlier step block the later steps; wider ring gets more candidates", function()
	local counts = {}
	local placed, tried = logic.placeRelaxed(2, {}, 2000, function(step)
		counts[#counts + 1] = step.widen
		if step.label == "strict" then return { { 0, 0 } } end
		return { { 500, 0 }, { 3000, 0 } }
	end, nil, false)
	eq(placed, { { 0, 0 }, { 3000, 0 } })
	eq(#tried, 2)
	eq(tried[2].skipped, { near = 1 })
	ok(counts[2] > counts[1])
end)

test("placeRelaxed spread: coarse grid full -> the fine grid fills the rest, picked evenly, all >= minDist", function()
	-- existing towns sit on every coarse grid point; the fine grid (step.fine) has free points between
	local existing = {}
	local coarse = logic.mapGrid(-4096, -4096, 4096, 4096, 3000, 1000)
	for i, p in ipairs(coarse) do existing[i] = p end
	local usedFine = false
	local placed, tried = logic.placeRelaxed(3, existing, 1200, function(step, minDist)
		if not step.fine then return coarse end
		usedFine = true
		return logic.mapGrid(-4096, -4096, 4096, 4096, minDist, 1000)
	end, function() return true end, true)
	ok(usedFine)
	eq(tried[1].placed, 0)
	eq(#placed, 3)
	for i, p in ipairs(placed) do
		for _, e in ipairs(existing) do ok(dist(p, e) >= 800 - 1e-6) end
		for j = i + 1, #placed do ok(dist(p, placed[j]) >= 800 - 1e-6) end
	end
end)

test("skippedText orders the reasons", function()
	eq(logic.skippedText({ edge = 4, near = 12 }), "near=12 edge=4")
	eq(logic.skippedText({}), "none")
	eq(logic.skippedText(nil), "none")
end)

---------------------------------------------------------------------------
-- grow build-out passes

test("passStep: town by town, passes within a town", function()
	local got = {}
	for i = 1, 6 do
		local k, p = logic.passStep(i, 3)
		got[i] = { k, p }
	end
	eq(got, { { 1, 1 }, { 1, 2 }, { 1, 3 }, { 2, 1 }, { 2, 2 }, { 2, 3 } })
	eq({ logic.passStep(4, 1) }, { 4, 1 })
	eq({ logic.passStep(2, nil) }, { 2, 1 })
end)

test("growPlan: pass 1 multiplies, later passes re-send, at cap is a build-out pass", function()
	local f, note = logic.growPlan({ 1, 2, 3 }, 10, 1)
	eq(f, { 10, 20, 30 })
	eq(note, "")
	f, note = logic.growPlan({ 10, 20, 30 }, 10, 2)
	eq(f, { 10, 20, 30 })
	eq(note, " (build-out pass)")
	f, note = logic.growPlan({ 1000, 1000, 1000 }, 10, 1)
	eq(f, { 1000, 1000, 1000 })
	eq(note, " (at cap, build-out pass)")
	f, note = logic.growPlan({ 100, 100, 5 }, 100, 1)
	eq(f, { 1000, 1000, 500 })
	eq(note, " (capped at 1000)")
	f, note = logic.growPlan({ 50, 50, 50 }, nil, 1)
	eq(f, { 1, 1, 1 })
	eq(note, "")
end)

test("passContinues: stop when a pass adds fewer than MIN_PASS_GAIN buildings", function()
	eq(logic.MIN_PASS_GAIN, 20)
	eq(logic.passContinues(889, 1193), true)
	eq(logic.passContinues(100, 120), true)
	eq(logic.passContinues(100, 119), false)
	eq(logic.passContinues(100, 90), false)
	eq(logic.GROW_PASSES, { 1, 3, 5, 10 })
end)

test("growLabel names the passes; one pass and reset leave them out", function()
	eq(logic.growLabel(false, 10, 3), "Grow all towns x10, 3 passes")
	eq(logic.growLabel(true, 2, 1), "Grow nearest town x2")
	eq(logic.growLabel(false, 5), "Grow all towns x5")
	eq(logic.growLabel(false, nil, 5), "Reset all towns to x1")
end)

---------------------------------------------------------------------------
-- names, pairs, readout

test("nextTownNumber: 1 + highest SQST Town N, ignores other names", function()
	eq(logic.nextTownNumber({}), 1)
	eq(logic.nextTownNumber({ "Tacoma", "SQST Town 3", "SQST Town 12", "SQST Town x", "My SQST Town 99" }), 13)
	eq(logic.nextTownNumber(nil), 1)
end)

test("nearestPairs: nearest other town per new town, deduplicated", function()
	local all = {
		{ id = 1, x = 0, y = 0 }, { id = 2, x = 1000, y = 0 }, { id = 3, x = 5000, y = 0 }, { id = 4, x = 5500, y = 0 },
	}
	local new = { all[2], all[3], all[4] }
	eq(logic.nearestPairs(new, all), { { 2, 1 }, { 3, 4 } }) -- 4's nearest is 3: same pair
	eq(logic.nearestPairs({ { id = 9, x = 0, y = 0 } }, { { id = 9, x = 0, y = 0 } }), {})
end)

test("townReadout sums person capacities and buildings", function()
	local caps = { [1] = { 100, 200, 300 }, [2] = { 1000, 1000, 1000 } }
	local bld = { [1] = { 11, 12 }, [2] = { 21, 22, 23 } }
	eq(logic.townReadout({ 1, 2, 3 }, caps, bld, 0), "Towns 3   Capacity 3.6k   Buildings 5")
	eq(logic.townReadout({ 1 }, caps, bld, 1), "Towns 1 (1 frozen)   Capacity 600   Buildings 2")
	eq(logic.townReadout({}, nil, nil, nil), "Towns 0   Capacity 0   Buildings 0")
end)

---------------------------------------------------------------------------
-- test grid

test("gridPositions: centred, spacing apart, row by row, names Grid <row letter><column>", function()
	local g = logic.gridPositions(100, 200, 2, 2, 3000)
	eq(#g, 4)
	eq({ g[1].x, g[1].y, g[1].name }, { -1400, -1300, "Grid A1" })
	eq({ g[2].x, g[2].y, g[2].name }, { 1600, -1300, "Grid A2" })
	eq({ g[3].x, g[3].y, g[3].name }, { -1400, 1700, "Grid B1" })
	eq({ g[4].x, g[4].y, g[4].name }, { 1600, 1700, "Grid B2" })
	local g3 = logic.gridPositions(0, 0, 3, 3, 1000)
	eq({ g3[5].x, g3[5].y, g3[5].name }, { 0, 0, "Grid B2" }) -- the middle town sits on the centre
	eq(g3[9].name, "Grid C3")
end)

test("gridPairs: none, neighbours, neighbours + diagonals", function()
	eq(logic.gridPairs(2, 2, 1), {})
	eq(logic.gridPairs(2, 2, 2), { { 1, 2 }, { 1, 3 }, { 2, 4 }, { 3, 4 } })
	eq(#logic.gridPairs(2, 2, 3), 6) -- every pair of the four
	eq(#logic.gridPairs(3, 3, 2), 12)
	eq(#logic.gridPairs(3, 3, 3), 20)
	eq(logic.gridPairs(4, 1, 3), { { 1, 2 }, { 2, 3 }, { 3, 4 } })
end)

test("gridLabel", function()
	eq(logic.gridLabel("3 x 3", 1500), "Create 3 x 3 grid, 1.5 km")
end)

test("isGridTownName and removeLabel", function()
	eq(logic.isGridTownName("Grid A1"), true)
	eq(logic.isGridTownName("Grid C12"), true)
	eq(logic.isGridTownName("Gridiron"), false)
	eq(logic.isGridTownName("SQST Town 1"), false)
	-- test town names (Remove towns > Grid towns): the grids', old Showcases' and the new Showcase names
	for _, n in ipairs({ "Grid A1", "Grid S35", "Parclo 3 N (Smart lanes)", "Ring IX 12 NW (Game default)",
			"T-junction 9 SE (Smart phases)", "Grid W", "Grid N", "Smart lanes 1 N", "Game default 2 E", "Smart phases 3 S", "Full fan 10 W", "Kerb locked 6 S", "Crossroads 2 E (Kerb locked)" }) do
		eq(logic.isTestTownName(n), true, n)
	end
	for _, n in ipairs({ "Gridiron", "Springfield", "Parclo 3 N", "Smart lanes 1 Q", "Full fan city", "Kerb locked road", "Kerb locked 2", "Smart lanes N",
			"Parclo N (Smart lanes)", "x 3 N (Other mode)", "Grid NE", "Grid", "" }) do
		eq(logic.isTestTownName(n), false, n)
	end
	eq(logic.isTestTownName(nil), false)
	eq(logic.removeLabel(2), "Remove grid towns")
end)

test("uniqueEdges, chunk, orphanNodes", function()
	eq(logic.uniqueEdges({ [1] = { 11, 12 }, [2] = { 12, 13 }, [3] = { 11 } }), { 11, 12, 13 })
	eq(logic.chunk({ 1, 2, 3, 4, 5 }, 2), { { 1, 2 }, { 3, 4 }, { 5 } })
	eq(logic.chunk({}, 2), {})
	-- node 2 joins both removed edges; node 3 still has another edge; node 4 is a construction node;
	-- node 9 has an unknown degree
	eq(logic.orphanNodes({ { 1, 2 }, { 2, 3 }, { 4, 9 } }, { [1] = 1, [2] = 2, [3] = 2, [4] = 1 }, { [4] = true }), { 1, 2 })
end)

---------------------------------------------------------------------------
-- Town growth locked into the grid (Showcase / Lights showcase)

test("outsideGrid / edgeOutside: the grid square grown by the margin; an edge leaving it at either end", function()
	local a = { town = 1, label = "A", x = 1000, y = -500, half = 200 }
	ok(not logic.outsideGrid(a, 1200, -300, 0))
	ok(logic.outsideGrid(a, 1201, -500, 0))
	ok(not logic.outsideGrid(a, 1219, -719, 20))
	ok(logic.outsideGrid(a, 1000, -721, 20))
	ok(not logic.edgeOutside(a, { 800, -500 }, { 1200, -500 }, logic.LOCK_MARGIN), "a grid street")
	ok(logic.edgeOutside(a, { 1200, -500 }, { 1350, -500 }, logic.LOCK_MARGIN), "a street out of the grid")
	ok(logic.edgeOutside(a, { 1350, -500 }, { 1200, -500 }, logic.LOCK_MARGIN))
end)

test("stubOuterEnd: exactly the four corner stubs of every wide grid, either direction; no other grid street", function()
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	for _, half in ipairs(grid.HALF) do
		local a = { town = 1, label = "A", x = 3000, y = 2000, half = half }
		local stubs = 0
		for _, e in ipairs(grid.edges(half)) do
			local p0 = { e[1][1] + a.x, e[1][2] + a.y }
			local p1 = { e[3][1] + a.x, e[3][2] + a.y }
			local k = logic.stubOuterEnd(a, p0, p1)
			if k ~= nil then
				stubs = stubs + 1
				eq(k, 1, "the grid's stubs run from the corner outwards")
				eq(logic.stubOuterEnd(a, p1, p0), 0, "reversed")
				ok(logic.edgeOutside(a, p0, p1, logic.LOCK_MARGIN), "a stub ends outside the grid (+ margin)")
			else
				ok(not logic.edgeOutside(a, p0, p1, logic.LOCK_MARGIN), "a grid street is inside")
			end
		end
		eq(stubs, 4, "half " .. half)
	end
	-- a street out of a side's middle, or diagonal from a point off the corner, is no stub
	local a = { town = 1, label = "A", x = 0, y = 0, half = 200 }
	eq(logic.stubOuterEnd(a, { 200, 0 }, { 260, 0 }), nil)
	eq(logic.stubOuterEnd(a, { 190, 200 }, { 240, 250 }), nil)
	eq(logic.stubOuterEnd(a, { -200, 200 }, { -242, 242 }), 1)
end)

test("denseWeights: one fresh row of four per land use, clamped to 0..1; all zero falls back to DENSE_WEIGHTS", function()
	local w = logic.denseWeights()
	eq(#w, 3)
	for k = 1, 3 do eq(w[k], { 0.0, 0.1, 0.5, 1.0 }) end
	ok(w[1] ~= w[2] and w[1] ~= logic.DENSE_WEIGHTS, "fresh tables")
	w[1][1] = 9
	eq(logic.DENSE_WEIGHTS[1], 0.0)
	eq(logic.denseWeights({ -1, 2, 0.5, 0.25 })[3], { 0.0, 1.0, 0.5, 0.25 })
	eq(logic.denseWeights({ 0, 0, 0, 0 })[1], logic.DENSE_WEIGHTS)
	-- the town editor's sliders run 0..100 % and never let all four be 0 (base town_eow.script.tl)
	local sum = 0
	for _, v in ipairs(logic.DENSE_WEIGHTS) do
		ok(v >= 0 and v <= 1)
		sum = sum + v
	end
	ok(sum > 0)
	ok(logic.DENSE_WEIGHTS[4] > logic.DENSE_WEIGHTS[3] and logic.DENSE_WEIGHTS[3] > logic.DENSE_WEIGHTS[2], "shifted to the high levels")
end)

test("levelCounts / levelText: per level 1..4, out of range clamped", function()
	local c = logic.levelCounts({ 1, 4, 4, 2, 3, 3, 3, 0, 7 })
	eq(c, { 2, 1, 3, 3 })
	eq(logic.levelText(c), "1:2 2:1 3:3 4:3")
	eq(logic.levelText(logic.levelCounts({})), "1:0 2:0 3:0 4:0")
end)

test("denseSteps: per town weights then its passes; every town's final check after all the growth", function()
	local st = logic.denseSteps(2, 3)
	local text = {}
	for k, s in ipairs(st) do text[k] = s.kind .. s.town .. ":" .. s.pass end
	eq(table.concat(text, " "), "weights1:0 grow1:1 grow1:2 grow1:3 weights2:0 grow2:1 grow2:2 grow2:3 final1:3 final2:3")
	eq(#logic.denseSteps(1, 0), 3, "at least one pass")
	eq(logic.denseSteps(0, 3), {})
end)

test("leakLine: the line TESTING.md looks for", function()
	eq(logic.leakLine("showcase_grow", "Grid S3", 0, 2, " final"), "[SQST] showcase_grow town Grid S3 outside_streets=0 houses_outside=2 final")
	eq(logic.leakLine("x", "y", nil, nil), "[SQST] x town y outside_streets=0 houses_outside=0")
end)

test("both Showcase specs: streets locked, level weights, Showcase x10 in 3 passes, Lights showcase x3 once (denser, same grid)", function()
	for _, sp in ipairs({ logic.SHOWCASE_SPEC, logic.LIGHTS_SPEC }) do
		eq(sp.lockStreets, true, sp.id)
		eq(sp.denseWeights, logic.DENSE_WEIGHTS, sp.id)
	end
	eq({ logic.SHOWCASE_SPEC.growFactor, logic.SHOWCASE_SPEC.growPasses }, { 10, 3 })
	for k = 1, #logic.LIGHTS_SHAPES do
		local sp = logic.lightsSpec(k)
		eq({ sp.growFactor, sp.growPasses, sp.growTarget }, { 1.0, 1, 400 }, sp.shapeLabel)
	end
	-- both Showcases: Medium towns (user 2026-10-12); the Lights showcase gets its people from density
	eq(logic.specSize(logic.SHOWCASE_SPEC), 2)
	eq(logic.specSize(logic.LIGHTS_SPEC), 2)
	-- sized for about 400 people per town (user 2026-10-13), each town from its capacity target; x1 the fallback
	eq(logic.LIGHTS_GROW_FACTOR, 1.0)
	eq(logic.LIGHTS_SPEC.growTarget, 400)
	ok(logic.LIGHTS_GROW_FACTOR < logic.DENSE_GROW_FACTOR)
	ok(logic.LIGHTS_GROW_FACTOR <= logic.MAX_SIZE_FACTOR)
	local inF, inP = false, false
	for _, f in ipairs(logic.GROW_FACTORS) do if f == logic.DENSE_GROW_FACTOR then inF = true end end
	for _, p in ipairs(logic.GROW_PASSES) do if p == logic.DENSE_GROW_PASSES then inP = true end end
	ok(inF and inP)
	ok(logic.LOCK_BATCH > 0 and logic.LOCK_BATCH <= logic.LOCK_MAX_PASS)
end)

test("town growth for a target population: growFactorFor (target / (fill x initial residential capacity), 0.25 steps, 1..MAX), growFactorForPop (target / pop, 0.05 steps); popText", function()
	eq(logic.GROW_FILL, 0.78)
	eq(logic.LIGHTS_TARGET_POP, 400)
	eq(logic.growFactorFor(400, 400), 1.25, "Medium at fill 0.78: 400 / 312 = 1.28")
	eq(logic.growFactorFor(400, 400, 1.0), 1.0, "at small factors the town fills its target: x1")
	eq(logic.growFactorFor(1000, 400), 3.25, "1000 / 312 = 3.21")
	eq(logic.growFactorFor(1000, 1600), 1.0, "Large: never below 1")
	eq(logic.growFactorFor(1000, 400, 0.5), 5.0)
	eq(logic.growFactorFor(1e9, 1), logic.MAX_SIZE_FACTOR)
	eq(logic.growFactorFor(nil, 400), 1.0)
	eq(logic.growFactorFor(1000, 0), 1.0)
	eq(logic.LIGHTS_GROW_FACTOR, 1.0)
	-- per town from its capacity target (2026-10-13 session 0356: pop = initial capacity x factor, median 0.998)
	eq(logic.growFactorForCap(400, 400), 1.0, "Medium: the level weights only")
	eq(logic.growFactorForCap(400, 250), 1.6)
	eq(logic.growFactorForCap(400, 1600), 1.0, "already bigger: weights only")
	eq(logic.growFactorForCap(400, 0), nil)
	eq(logic.growFactorForCap(400, nil), nil)
	eq(logic.growFactorForCap(400, 0 / 0), nil)
	eq(logic.growFactorForCap(1e9, 1), logic.MAX_SIZE_FACTOR)
	eq(logic.popText({ 900, nil, 1100, 1000 }, 4), " pop min/mean/max=900/1000/1100 (3 of 4 towns read)")
	eq(logic.popText({}, 3), " pop=unread")
	eq(logic.popText({}, 0), " pop=unread")
end)
