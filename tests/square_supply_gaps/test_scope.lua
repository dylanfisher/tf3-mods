-- Phase 2d "Only towns in view": the pure in-view selection (sg_scope.tl). Camera footprint from
-- corner rays, polygon vs box overlap, town boxes from building boxes, hysteresis, names.

local scope = ug_require "square_supply_gaps::/supply_gaps/sg_scope.tl"

local function cam(poly, distance, cx, cy)
	return { cx = cx or 0, cy = cy or 0, distance = distance or 100, poly = poly, hits = 4, fallback = false }
end

-- groundPoint / footprint ------------------------------------------------------------------

test("groundPoint: a downward ray meets the plane; a ray above the horizon is capped", function()
	local x, y, hit = scope.groundPoint(0, 0, 100, 10, 0, 90, 0, 0, 0, 1000)
	near(x, 100)
	near(y, 0)
	eq(hit, true)
	x, y, hit = scope.groundPoint(0, 0, 100, 10, 0, 101, 0, 0, 0, 400)
	near(x, 400)
	near(y, 0)
	eq(hit, false)
	-- a far hit is capped at maxDist from the centre
	x, y, hit = scope.groundPoint(0, 0, 100, 1000, 0, 99, 0, 0, 0, 400)
	near(x, 400)
	eq(hit, true)
end)

test("footprint: four corner rays from an eye above the centre; depth order doesn't matter", function()
	local eye = { 0, 0, 100 }
	local function ray(dx, dy) return { { 0, 0, 100 }, { dx, dy, 0 } } end
	local poly, hits = scope.footprint({ ray(-50, 30), ray(50, 30), ray(50, -30), ray(-50, -30) }, eye, 0, 0, 0, 1000)
	eq(hits, 4)
	near(poly[1], -50); near(poly[2], 30); near(poly[3], 50); near(poly[6], -30)
	-- depth 0 and 1 swapped (reversed depth range): same ground point
	local poly2 = scope.footprint({ { { 50, 30, 0 }, { 0, 0, 100 } } }, eye, 0, 0, 0, 1000)
	near(poly2[1], 50); near(poly2[2], 30)
	-- missing far point -> the centre
	local poly3, hits3 = scope.footprint({ { { 0, 0, 100 }, nil } }, eye, 0, 7, 8, 1000)
	eq(poly3, { 7, 8 })
	eq(hits3, 0)
end)

test("footprint: tilted camera, far corners above the horizon are capped at maxDist", function()
	local eye = { 0, -200, 100 }
	local rays = {
		{ { 0, -200, 100 }, { -100, 1000, 120 } }, -- top left: above the horizon
		{ { 0, -200, 100 }, { 100, 1000, 120 } },
		{ { 0, -200, 100 }, { 60, -100, 0 } },     -- bottom: hits the ground
		{ { 0, -200, 100 }, { -60, -100, 0 } },
	}
	local poly, hits = scope.footprint(rays, eye, 0, 0, 0, 400)
	eq(hits, 2)
	for i = 1, 8, 2 do
		ok(math.sqrt(poly[i] ^ 2 + poly[i + 1] ^ 2) <= 400 + 1e-6, "corner within the cap")
	end
end)

-- intersects ------------------------------------------------------------------------------

test("intersects: inside, overlapping edge (centre outside), far, margin", function()
	local sq = scope.square(0, 0, 100)
	ok(scope.intersects(sq, { -10, -10, 10, 10 }, 0), "inside")
	ok(scope.intersects(sq, { 90, -10, 300, 10 }, 0), "box centre off screen, part on screen")
	ok(scope.intersects(sq, { -500, -500, 500, 500 }, 0), "view inside a big town")
	ok(not scope.intersects(sq, { 150, 150, 200, 200 }, 0), "far")
	ok(scope.intersects(sq, { 150, 150, 200, 200 }, 60), "within the margin")
	ok(not scope.intersects(nil, { 0, 0, 1, 1 }, 0))
	ok(not scope.intersects(sq, {}, 0), "no box")
end)

test("intersects: rotated footprint (diamond): a box in its bounding square but outside is out", function()
	local diamond = { 0, 100, 100, 0, 0, -100, -100, 0 }
	ok(scope.intersects(diamond, { -5, -5, 5, 5 }, 0))
	ok(not scope.intersects(diamond, { 70, 70, 90, 90 }, 0), "corner of the AABB, outside the diamond")
	ok(scope.intersects(diamond, { 40, 40, 90, 90 }, 0), "touches the diamond's edge")
end)

-- townBoxes -------------------------------------------------------------------------------

test("townBoxes: union of each town's building boxes; missing / empty boxes skipped", function()
	local ids = { 1, 2, 3, 4 }
	local townOf = { 100, 100, 200, 200 }
	local boxes = { [1] = { 0, 0, 10, 10 }, [2] = { 50, -5, 60, 5 }, [3] = {} }
	local tb = scope.townBoxes(ids, townOf, boxes)
	eq(tb[100], { 0, -5, 60, 10 })
	eq(tb[200], nil)
end)

-- select (hysteresis) ---------------------------------------------------------------------

test("select: a town whose centre is off screen but whose buildings are visible is in view", function()
	local st = scope.newState()
	local towns = { [100] = { 80, -20, 400, 20 }, [200] = { 500, 500, 600, 600 } }
	local set, changed = scope.select(towns, cam(scope.square(0, 0, 100)), st, 1)
	eq(set, { [100] = true })
	eq(changed, true)
	local __, again = scope.select(towns, cam(scope.square(0, 0, 100)), st, 2)
	eq(again, false)
end)

test("select: a town just past the edge stays HOLD_TICKS ticks, then leaves; near the edge it stays", function()
	local st = scope.newState()
	local towns = { [100] = { 0, 0, 10, 10 } }
	scope.select(towns, cam(scope.square(0, 0, 50), 50), st, 1)
	-- pan far away: held for HOLD_TICKS - 1 more ticks
	local far = cam(scope.square(5000, 0, 50), 50, 5000, 0)
	for t = 2, scope.HOLD_TICKS do
		local set = scope.select(towns, far, st, t)
		ok(set[100], "held at tick " .. t)
	end
	local set, changed = scope.select(towns, far, st, scope.HOLD_TICKS + 1)
	eq(set, {})
	eq(changed, true)
	-- comes back: in again at once
	set = scope.select(towns, cam(scope.square(0, 0, 50), 50), st, 10)
	eq(set, { [100] = true })
	-- just outside (50 m away, exit margin EXIT_MIN = 100): stays in after the hold
	local edge = cam(scope.square(-100, 0, 50), 50, -100, 0) -- spans -150..-50; box at 0..10
	for t = 11, 20 do
		set = scope.select(towns, edge, st, t)
		ok(set[100], "kept by the exit margin at tick " .. t)
	end
	-- a town that was never in doesn't enter through the margin
	local st2 = scope.newState()
	eq(scope.select(towns, edge, st2, 1), {})
end)

test("select: demolished town (no box) leaves", function()
	local st = scope.newState()
	scope.select({ [100] = { 0, 0, 10, 10 } }, cam(scope.square(0, 0, 50)), st, 1)
	local set, changed = scope.select({}, cam(scope.square(0, 0, 50)), st, 2)
	eq(set, {})
	eq(changed, true)
end)

-- byDistance / namesText ------------------------------------------------------------------

test("byDistance: nearest box centre first, ties by id, unknown box last", function()
	local tb = { [1] = { 90, 0, 110, 0 }, [2] = { -10, 0, 10, 0 }, [3] = { -110, 0, -90, 0 } }
	eq(scope.byDistance({ [1] = true, [2] = true, [3] = true, [4] = true }, tb, 0, 0), { 2, 1, 3, 4 })
end)

test("namesText: up to NAMES_SHOWN names, then +N", function()
	eq(scope.namesText({ "Rockledge", "Columbus" }, 3), "Rockledge, Columbus")
	eq(scope.namesText({ "A", "B", "C", "D", "E" }, 3), "A, B, C +2")
	eq(scope.namesText({}, 3), "")
	eq(scope.namesText({ "A", "B" }, nil), "A, B")
end)
