-- bb_brush: radius list, ring geometry, sample-throttle policy (PLAN Phase 1; Phase 2 adds the
-- edge-touch tests here).

local brush = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_brush.tl"

test("radii: 12 steps, 5..200 m, default 20 m is one of them", function()
	eq(#brush.RADII, 12)
	eq(brush.RADII[1], 5)
	eq(brush.RADII[#brush.RADII], 200)
	for i = 2, #brush.RADII do ok(brush.RADII[i] > brush.RADII[i - 1], "ascending at " .. i) end
	eq(brush.radiusIndex(brush.DEFAULT_RADIUS), 4)
end)

test("radiusLabels match RADII", function()
	local labels = brush.radiusLabels()
	eq(#labels, #brush.RADII)
	eq(labels[1], "5 m")
	eq(labels[4], "20 m")
	eq(labels[12], "200 m")
end)

test("radiusFromParam accepts slider numbers only", function()
	eq(brush.radiusFromParam(20), 20)
	eq(brush.radiusFromParam(200), 200)
	eq(brush.radiusFromParam(7), nil)
	eq(brush.radiusFromParam(nil), nil)
	eq(brush.radiusIndex(33), nil)
end)

test("ringArcs: n arcs closing the circle, heights shared at joints", function()
	local calls = 0
	local function h(x, y) calls = calls + 1; return x * 0.1 + y * 0.01 end
	local arcs = brush.ringArcs(100, 50, 20, 48, h)
	eq(#arcs, 48)
	eq(calls, 48, "one height lookup per joint")
	local total = 0
	for i, a in ipairs(arcs) do
		near(a.startAngle, (i - 1) * 2 * math.pi / 48, 1e-12)
		near(a.length, 20 * a.angle, 1e-12)
		total = total + a.angle
		local nxt = arcs[i % 48 + 1]
		near(a.h1, nxt.h0, 1e-12, "joint " .. i)
	end
	near(total, 2 * math.pi, 1e-9)
	-- first joint is at angle 0: (120, 50)
	near(arcs[1].h0, 120 * 0.1 + 50 * 0.01, 1e-12)
	-- quarter turn: (100, 70)
	near(arcs[13].h0, 100 * 0.1 + 70 * 0.01, 1e-9)
end)

test("ringArcs: degenerate input gives no arcs", function()
	local h = function() return 0 end
	eq(#brush.ringArcs(0, 0, 0, 48, h), 0)
	eq(#brush.ringArcs(0, 0, 10, 0, h), 0)
end)

test("ringWidth clamps between 1.5 and 6 m", function()
	eq(brush.ringWidth(5), 1.5)
	near(brush.ringWidth(100), 4)
	eq(brush.ringWidth(200), 6)
end)

test("sampleDue: radius/4 move or 100 ms", function()
	ok(not brush.sampleDue(1, 1, 0.01, 20), "small move, short time")
	ok(brush.sampleDue(5, 0, 0.01, 20), "moved r/4")
	ok(brush.sampleDue(3, 4, 0.0, 20), "moved r/4 diagonally")
	ok(brush.sampleDue(0, 0, 0.1, 20), "100 ms passed")
	ok(not brush.sampleDue(40, 0, 0.05, 200), "40 m < 200/4")
end)

-- Phase 2: edge touch test (Hermite sampling) and point-in-circle.

-- Straight edge from (x0, y0) to (x1, y1): tangents = chord (the engine's convention for straights).
local function straight(x0, y0, x1, y1)
	return { p0x = x0, p0y = y0, p1x = x1, p1y = y1,
		t0x = x1 - x0, t0y = y1 - y0, t1x = x1 - x0, t1y = y1 - y0 }
end

-- Quarter circle of radius R around (0, 0) from (R, 0) to (0, R). Hermite tangent length
-- 4·tan(π/8)·R (= 3 × the usual Bezier handle 0.5523·R) keeps the curve within 0.03 % of the arc.
local function quarter(R)
	local k = 4 * math.tan(math.pi / 8) * R
	return { p0x = R, p0y = 0, p1x = 0, p1y = R, t0x = 0, t0y = k, t1x = -k, t1y = 0 }
end

test("hermite: end points and straight midpoint", function()
	local c = straight(0, 0, 100, 0)
	local x, y = brush.hermite(c, 0)
	near(x, 0); near(y, 0)
	x, y = brush.hermite(c, 1)
	near(x, 100); near(y, 0)
	x, y = brush.hermite(c, 0.5)
	near(x, 50); near(y, 0)
end)

test("hermite: quarter circle stays close to the arc", function()
	local c = quarter(100)
	for i = 0, 8 do
		local x, y = brush.hermite(c, i / 8)
		near(math.sqrt(x * x + y * y), 100, 0.05, "t = " .. i / 8)
	end
end)

test("pointSegmentDistance: interior, beyond the ends, degenerate", function()
	near(brush.pointSegmentDistance(50, 10, 0, 0, 100, 0), 10)
	near(brush.pointSegmentDistance(-30, 40, 0, 0, 100, 0), 50)
	near(brush.pointSegmentDistance(103, 4, 0, 0, 100, 0), 5)
	near(brush.pointSegmentDistance(3, 4, 0, 0, 0, 0), 5)
end)

test("curveTouchesCircle: straight edge through the middle of a long edge", function()
	-- 400 m edge, 5 m brush on its middle third, far from both ends and the octree's centre point.
	local c = straight(0, 0, 400, 0)
	ok(brush.curveTouchesCircle(c, 130, 0, 5), "on the edge")
	ok(brush.curveTouchesCircle(c, 130, 4.9, 5), "just inside")
	ok(not brush.curveTouchesCircle(c, 130, 5.1, 5), "just outside")
end)

test("curveTouchesCircle: tangent edge counts (distance == r)", function()
	local c = straight(0, 10, 100, 10)
	ok(brush.curveTouchesCircle(c, 50, 0, 10), "tangent at distance r")
	ok(not brush.curveTouchesCircle(c, 50, 0, 9.99), "a hair smaller misses")
end)

test("curveTouchesCircle: edge fully outside", function()
	local c = straight(0, 0, 100, 0)
	ok(not brush.curveTouchesCircle(c, 50, 60, 20), "parallel, too far")
	ok(not brush.curveTouchesCircle(c, 150, 0, 20), "beyond the end")
	ok(brush.curveTouchesCircle(c, 115, 0, 20), "end inside the circle")
	ok(not brush.curveTouchesCircle(nil, 0, 0, 20), "no curve")
end)

test("curveTouchesCircle: curved edge, inside and outside of the bend", function()
	local c = quarter(100)
	-- On the arc at 45°.
	local a = math.pi / 4
	ok(brush.curveTouchesCircle(c, 100 * math.cos(a), 100 * math.sin(a), 3), "on the arc")
	-- The chord midpoint (50, 50) is ~29 m inside the arc: a chord test would wrongly hit it.
	ok(not brush.curveTouchesCircle(c, 50, 50, 20), "inside the bend, off the curve")
	ok(brush.curveTouchesCircle(c, 50, 50, 31), "big enough to reach the arc")
	-- Outside the bend.
	ok(not brush.curveTouchesCircle(c, 90, 90, 25), "outside the bend")
	ok(brush.curveTouchesCircle(c, 90, 90, 30), "reaches from outside")
end)

test("curveTouchesCircle: bounding-box reject agrees with the full test", function()
	local c = quarter(100)
	for _, p in ipairs({ { -50, -50 }, { 300, 0 }, { 0, 300 }, { 150, 150 } }) do
		ok(not brush.curveTouchesCircle(c, p[1], p[2], 10), "far point " .. p[1] .. "," .. p[2])
	end
end)

test("pointInCircle: inside, on the rim, outside", function()
	ok(brush.pointInCircle(3, 4, 0, 0, 5), "on rim")
	ok(brush.pointInCircle(1, 1, 0, 0, 5), "inside")
	ok(not brush.pointInCircle(4, 4, 0, 0, 5), "outside")
end)

test("edgeQueryRadius adds the margin", function()
	ok(brush.EDGE_MARGIN >= 0)
	eq(brush.edgeQueryRadius(20), 20 + brush.EDGE_MARGIN)
	eq(brush.EDGE_SAMPLES, 9)
end)

test("throttle: a stroke dragged in small steps samples every r/4 or 100 ms", function()
	-- Simulate a drag at 1 m per 10 ms frame with r = 20: due every 5 m (50 ms) by distance.
	local r, last, samples = 20, { x = 0, t = 0 }, 1
	for f = 1, 100 do
		local x, t = f * 1.0, f * 0.01
		if brush.sampleDue(x - last.x, 0, t - last.t, r) then
			samples = samples + 1
			last = { x = x, t = t }
		end
	end
	eq(samples, 21, "1 + 100 m / 5 m")
	-- Standing still: only the 100 ms timer fires.
	last, samples = { t = 0 }, 0
	for f = 1, 100 do
		local t = f * 0.01
		if brush.sampleDue(0, 0, t - last.t, r) then samples = samples + 1; last = { t = t } end
	end
	ok(samples >= 9 and samples <= 10, "about every 100 ms: " .. samples)
end)
