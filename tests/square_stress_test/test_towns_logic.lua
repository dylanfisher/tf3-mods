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
