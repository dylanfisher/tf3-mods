-- minimap_geom: world <-> minimap fraction <-> widget pixel helpers (pure, no api.*).

local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl"

local BOX = geom.boxFromBounds(-4096, -2048, 4096, 2048) -- 8192 x 4096 m, centred on 0
local function orient(fx, fy, sw) return { flipX = fx or false, flipY = fy or false, swapXY = sw or false } end

test("boxFromBounds orders corners and avoids zero extent", function()
	local b = geom.boxFromBounds(10, 20, -10, -20)
	eq(b.minX, -10); eq(b.maxX, 10); eq(b.minY, -20); eq(b.maxY, 20)
	local d = geom.boxFromBounds(5, 5, 5, 5)
	eq(d.maxX - d.minX, 1); eq(d.maxY - d.minY, 1)
end)

test("widgetSize keeps the aspect, long side fixed", function()
	local w, h = geom.widgetSize(BOX, 360, geom.DEFAULT_ORIENT)
	eq(w, 360); eq(h, 180)
	w, h = geom.widgetSize(BOX, 360, orient(false, false, true))
	eq(w, 180); eq(h, 360)
	w, h = geom.widgetSize(geom.boxFromBounds(0, 0, 1000, 1000), 300, nil)
	eq(w, 300); eq(h, 300)
end)

test("default orientation: x right, +y up (flipY)", function()
	local fx, fy = geom.worldToFrac(-4096, 2048, BOX, geom.DEFAULT_ORIENT)
	near(fx, 0); near(fy, 0) -- north-west corner at top-left
	fx, fy = geom.worldToFrac(4096, -2048, BOX, geom.DEFAULT_ORIENT)
	near(fx, 1); near(fy, 1)
	fx, fy = geom.worldToFrac(0, 0, BOX, nil) -- nil = default
	near(fx, 0.5); near(fy, 0.5)
end)

test("fracToWorld inverts worldToFrac for every orientation", function()
	local pts = { { -4000, 1500 }, { 1234, -567 }, { 0, 0 }, { 4096, 2048 } }
	for _, fx in ipairs({ false, true }) do
		for _, fy in ipairs({ false, true }) do
			for _, sw in ipairs({ false, true }) do
				local o = orient(fx, fy, sw)
				for _, p in ipairs(pts) do
					local u, v = geom.worldToFrac(p[1], p[2], BOX, o)
					local x, y = geom.fracToWorld(u, v, BOX, o)
					near(x, p[1], 1e-6, "x " .. tostring(fx) .. tostring(fy) .. tostring(sw))
					near(y, p[2], 1e-6, "y " .. tostring(fx) .. tostring(fy) .. tostring(sw))
				end
			end
		end
	end
end)

test("swapXY puts world y on the horizontal axis", function()
	local fx, fy = geom.worldToFrac(-4096, 2048, BOX, orient(false, false, true))
	near(fx, 1); near(fy, 0)
end)

test("childGravity centres a child on a fraction", function()
	-- parent 360, child 20: centre at 0.5 -> gravity 0.5
	near(geom.childGravity(0.5, 360, 20), 0.5)
	-- left edge of the child at 0 when its centre is at 10 px
	near(geom.childGravity(10 / 360, 360, 20), 0)
	near(geom.childGravity(350 / 360, 360, 20), 1)
	-- position check: g * (P - c) + c/2 == frac * P
	local g = geom.childGravity(0.3, 360, 40)
	near(g * (360 - 40) + 20, 0.3 * 360, 1e-9)
	-- clamped at the edges, and a child as large as the parent is centred
	eq(geom.childGravity(0, 360, 40), 0)
	eq(geom.childGravity(1, 360, 40), 1)
	eq(geom.childGravity(0.2, 100, 100), 0.5)
end)

test("rectFromPoints bounds and clamps", function()
	local r = geom.rectFromPoints({ 0.2, 0.7, 0.4, 0.1, -0.3, 0.5, 0.3, 1.4 })
	near(r.x0, 0); near(r.x1, 0.4); near(r.y0, 0.1); near(r.y1, 1)
	local e = geom.rectFromPoints({})
	eq(e.x0, 0); eq(e.x1, 0)
end)

test("rectAround: +-halfSide square in fractions", function()
	local r = geom.rectAround(0, 0, 409.6, BOX, geom.DEFAULT_ORIENT)
	near(r.x0, 0.45); near(r.x1, 0.55)
	near(r.y0, 0.4); near(r.y1, 0.6)
end)

test("eventToFrac with pixel widget coordinates", function()
	local fx, fy, norm = geom.eventToFrac(150, 300, 100, 200, 300, 400, 1920, 1080)
	near(fx, 0.25); near(fy, 0.5); eq(norm, false)
end)

test("eventToFrac with normalised widget coordinates", function()
	-- widget spans 0.5..0.75 x 0.25..0.5 of a 1920x1080 screen; event at its centre in pixels
	local fx, fy, norm = geom.eventToFrac(1200, 405, 0.5, 0.25, 0.75, 0.5, 1920, 1080)
	near(fx, 0.5); near(fy, 0.5); eq(norm, true)
end)

test("eventToFrac with a zero-size widget returns the centre", function()
	local fx, fy = geom.eventToFrac(10, 10, 5, 5, 5, 5, 1920, 1080)
	eq(fx, 0.5); eq(fy, 0.5)
end)

test("round", function()
	eq(geom.round(0.12345, 3), 0.123)
	eq(geom.round(0.9996, 3), 1)
end)

test("camPx: footprint and dot in whole pixels, minimum box size", function()
	local p = geom.camPx({ x0 = 0.25, y0 = 0.5, x1 = 0.75, y1 = 0.6 }, 0.5, 0.55, 400, 200, 4)
	eq(p.boxCX, 200); eq(p.boxCY, 110); eq(p.boxW, 200); eq(p.boxH, 20)
	eq(p.dotX, 200); eq(p.dotY, 110)
	local tiny = geom.camPx({ x0 = 0.5, y0 = 0.5, x1 = 0.501, y1 = 0.5 }, 1.7, -0.2, 400, 200, 4)
	eq(tiny.boxW, 4); eq(tiny.boxH, 4)
	eq(tiny.dotX, 400); eq(tiny.dotY, 0) -- dot clamped to the picture
end)

test("sameCamPx: equal only when every pixel field matches", function()
	local a = geom.camPx({ x0 = 0.1, y0 = 0.1, x1 = 0.2, y1 = 0.2 }, 0.15, 0.15, 400, 400, 4)
	local b = geom.camPx({ x0 = 0.1001, y0 = 0.1, x1 = 0.2001, y1 = 0.2 }, 0.1501, 0.15, 400, 400, 4)
	ok(geom.sameCamPx(a, b), "sub-pixel move is not a change")
	local c = geom.camPx({ x0 = 0.11, y0 = 0.1, x1 = 0.21, y1 = 0.2 }, 0.16, 0.15, 400, 400, 4)
	ok(not geom.sameCamPx(a, c), "4 px move is a change")
	ok(geom.sameCamPx(nil, nil)); ok(not geom.sameCamPx(a, nil)); ok(not geom.sameCamPx(nil, a))
end)

test("headingDegrees: clockwise from picture-up, whole degrees", function()
	eq(geom.headingDegrees(0, -1), 0)   -- up (y down)
	eq(geom.headingDegrees(1, 0), 90)   -- right
	eq(geom.headingDegrees(0, 5), 180)  -- down, length doesn't matter
	eq(geom.headingDegrees(-1, 0), 270) -- left
	eq(geom.headingDegrees(1, -1), 45)
	eq(geom.headingDegrees(-1, -1), 315)
	eq(geom.headingDegrees(-0.001, -1), 0) -- -0.06 deg rounds to 0, not 360
	eq(geom.headingDegrees(0, 0), nil)
	eq(geom.headingDegrees(nil, nil), nil)
end)

test("sameCamPx: compares the arrow angle too", function()
	local a = geom.camPx({ x0 = 0.1, y0 = 0.1, x1 = 0.2, y1 = 0.2 }, 0.15, 0.15, 400, 400, 4)
	local b = geom.camPx({ x0 = 0.1, y0 = 0.1, x1 = 0.2, y1 = 0.2 }, 0.15, 0.15, 400, 400, 4)
	a.arrowDeg = geom.headingDegrees(0, -1)
	b.arrowDeg = geom.headingDegrees(0.001, -1)
	ok(geom.sameCamPx(a, b), "sub-degree turn is not a change")
	b.arrowDeg = geom.headingDegrees(1, 0)
	ok(not geom.sameCamPx(a, b), "turned camera is a change")
	b.arrowDeg = nil
	ok(not geom.sameCamPx(a, b), "arrow vs none")
end)

test("pictureSize: landscape and square keep the long-side sizes", function()
	local w, h = geom.pictureSize(BOX, 280, 240, 720, geom.DEFAULT_ORIENT) -- 2:1
	eq(w, 280); eq(h, 140)
	w, h = geom.pictureSize(BOX, 560, 360, 720, geom.DEFAULT_ORIENT)
	eq(w, 560); eq(h, 280)
	w, h = geom.pictureSize(geom.boxFromBounds(0, 0, 1000, 1000), 420, 300, 720, nil)
	eq(w, 420); eq(h, 420)
end)

test("pictureSize: portrait maps are widened to the minimum width, aspect kept", function()
	local tall = geom.boxFromBounds(0, 0, 4096, 8192) -- 1:2 portrait
	local w, h = geom.pictureSize(tall, 280, 240, 720, geom.DEFAULT_ORIENT)
	eq(w, 240); eq(h, 480) -- was 140 x 280: empty band right of the picture
	local w2, h2 = geom.pictureSize(tall, 420, 300, 720, geom.DEFAULT_ORIENT)
	eq(w2, 300); eq(h2, 600)
	local w3, h3 = geom.pictureSize(tall, 560, 360, 720, geom.DEFAULT_ORIENT)
	eq(w3, 360); eq(h3, 720)
	ok(w < w2 and w2 < w3, "S < M < L")
	-- the long-side cap wins over the minimum width: extreme strips stay on screen (narrow band)
	local strip = geom.boxFromBounds(0, 0, 1000, 4000)
	local ws, hs = geom.pictureSize(strip, 560, 240, 720, nil)
	eq(ws, 180); eq(hs, 720) -- was 240 x 960: bottom off screen
	local strip5 = geom.boxFromBounds(0, 0, 2048, 10240) -- 1:5, the reported case
	local s5w, s5h = geom.pictureSize(strip5, 280, 180, 480, geom.DEFAULT_ORIENT)
	local m5w, m5h = geom.pictureSize(strip5, 420, 300, 600, geom.DEFAULT_ORIENT)
	local l5w, l5h = geom.pictureSize(strip5, 560, 360, 720, geom.DEFAULT_ORIENT)
	eq(s5w, 96); eq(s5h, 480)
	eq(m5w, 120); eq(m5h, 600)
	eq(l5w, 144); eq(l5h, 720) -- was 360 x 1800
	-- landscape strips: the cap applies to the width the same way
	local wide = geom.boxFromBounds(0, 0, 10240, 2048)
	local ww, wh = geom.pictureSize(wide, 560, 360, 720, nil)
	eq(ww, 560); eq(wh, 112)
	ww, wh = geom.pictureSize(wide, 1000, 360, 720, nil)
	eq(ww, 720); eq(wh, 144)
	-- cap without a conflict: 1:2 at 1000 px long side -> 360 x 720
	local wc, hc = geom.pictureSize(tall, 1000, 200, 720, nil)
	eq(wc, 360); eq(hc, 720)
end)

test("pictureSize: floorW beats maxLong up to absMaxLong", function()
	local strip3 = geom.boxFromBounds(0, 0, 4096, 12288) -- 1:3, the reported case (S was 121 x 360)
	local w, h = geom.pictureSize(strip3, 200, 180, 360, nil)
	eq(w, 121); eq(h, 360) -- without a floor: narrower than the window (aspect from the 67 x 200 widget)
	w, h = geom.pictureSize(strip3, 200, 180, 360, nil, 180, 720)
	eq(w, 180); eq(h, 537)
	local lw, lh = geom.pictureSize(strip3, 560, 360, 720, nil, 180, 720)
	eq(lw, 240); eq(lh, 720) -- L: already above the floor, unchanged
	ok(w < lw, "S < L")
	-- 1:5: the screen limit wins, a band is left
	local strip5 = geom.boxFromBounds(0, 0, 2048, 10240)
	local w5, h5 = geom.pictureSize(strip5, 200, 180, 360, nil, 180, 720)
	eq(w5, 144); eq(h5, 720)
	-- the in-game values (FLOOR_W 120): 1:3 at S keeps 121 x 360, 1:5 grows to the floor
	w, h = geom.pictureSize(strip3, 200, 180, 360, nil, 120, 720)
	eq(w, 121); eq(h, 360)
	w5, h5 = geom.pictureSize(strip5, 200, 180, 360, nil, 120, 720)
	eq(w5, 120); eq(h5, 600)
	-- 1:2 and landscape: no change
	local tall = geom.boxFromBounds(0, 0, 4096, 8192)
	local w2, h2 = geom.pictureSize(tall, 200, 180, 360, nil, 180, 720)
	eq(w2, 180); eq(h2, 360)
	local ww, wh = geom.pictureSize(geom.boxFromBounds(0, 0, 10240, 2048), 200, 180, 360, nil, 180, 720)
	eq(ww, 200); eq(wh, 40)
end)

test("groundPoint: ray hits the plane", function()
	-- eye 1000 m up at (0, -1000), looking at the centre (0, 0) on z = 0
	local x, y, hit = geom.groundPoint(0, -1000, 1000, 0, 1000, -1000, 0, 0, 0, 4000)
	ok(hit); near(x, 0); near(y, 0)
	-- plane at z = 100
	x, y, hit = geom.groundPoint(0, -1000, 1000, 0, 1000, -1000, 100, 0, 0, 4000)
	ok(hit); near(x, 0); near(y, -100)
	-- a far point beyond the plane works the same (only the direction matters)
	x, y = geom.groundPoint(0, -1000, 1000, 500, 9000, -9000, 0, 0, 0, 4000)
	near(x, 50); near(y, 0)
end)

test("groundPoint: shallow and horizon rays are capped at maxDist from the centre", function()
	-- nearly horizontal ray: hits 100 km away -> capped to 4 km along the same direction
	local x, y, hit = geom.groundPoint(0, -1000, 100, 0, 1000, 98, 0, 0, 0, 4000)
	ok(hit); near(x, 0); near(y, 4000)
	-- pointing upwards: no hit, ground direction +x
	x, y, hit = geom.groundPoint(0, 0, 500, 10, 0, 600, 0, 100, 0, 4000)
	ok(not hit); near(x, 4100); near(y, 0)
	-- straight up: centre
	x, y, hit = geom.groundPoint(5, 5, 500, 5, 5, 900, 0, 5, 5, 4000)
	ok(not hit); eq(x, 5); eq(y, 5)
	-- camera below the plane: the start point
	x, y, hit = geom.groundPoint(10, 20, -5, 10, 30, -50, 0, 0, 0, 4000)
	ok(hit); eq(x, 10); eq(y, 20)
end)

test("groundPoint footprint moves with the camera centre", function()
	-- same view shifted by +3000 m in x: every corner shifts by the same amount
	local function corners(ox)
		local pts = {}
		for _, c in ipairs({ { -500, 700 }, { 500, 700 }, { 300, -300 }, { -300, -300 } }) do
			local x, y = geom.groundPoint(ox, -1500, 1500, ox + c[1], -1500 + 1000, 1500 - 1000 + c[2] * 0, 0, ox, 0, 6000)
			pts[#pts + 1] = { x, y }
		end
		return pts
	end
	local a, b = corners(0), corners(3000)
	for i = 1, 4 do near(b[i][1] - a[i][1], 3000, 1e-6); near(b[i][2] - a[i][2], 0, 1e-6) end
end)

test("normalizeScreenPos: fractions pass, pixels are divided", function()
	local x, y = geom.normalizeScreenPos(0.9, 0.1, 2560, 1440)
	near(x, 0.9); near(y, 0.1)
	x, y = geom.normalizeScreenPos(2304, 144, 2560, 1440)
	near(x, 0.9); near(y, 0.1)
end)

test("windowAnchor: top-right corner clamped on screen, invalid -> nil", function()
	local x, y = geom.windowAnchor(0.7, 0.2, 0.9, 0.6, 0.06)
	near(x, 0.9); near(y, 0.2)
	-- dragged past the left edge: right edge kept >= width
	x, y = geom.windowAnchor(-0.1, 0.0, 0.1, 0.4, 0.06)
	near(x, 0.2); near(y, 0.06)
	-- past the bottom
	x, y = geom.windowAnchor(0.5, 0.9, 0.7, 1.2, 0.06)
	near(x, 0.7); near(y, 0.7)
	eq(geom.windowAnchor(0, 0, 0, 0, 0.06), nil) -- hidden/unmounted node
	eq(geom.windowAnchor(0 / 0, 0, 1, 1, 0.06), nil)
	eq(geom.windowAnchor(5, 5, 9, 9, 0.06), nil)
end)

test("readPrefs keeps valid fields only", function()
	local p = geom.readPrefs({ posX = 0.8, posY = 0.3, pinned = true, sizeIdx = 2, showIndustries = false, open = true }, 3, 0.06)
	near(p.posX, 0.8); near(p.posY, 0.3)
	eq(p.pinned, true); eq(p.sizeIdx, 2); eq(p.showIndustries, false); eq(p.open, true)
	-- top kept below the ridge
	p = geom.readPrefs({ posX = 0.5, posY = 0.0 }, 3, 0.06)
	near(p.posY, 0.06)
	-- position needs both coordinates inside 0..1 (x > 0: it is the right edge)
	eq(geom.readPrefs({ posX = 0.5 }, 3, 0.06).posX, nil)
	eq(geom.readPrefs({ posX = 1.5, posY = 0.2 }, 3, 0.06).posX, nil)
	eq(geom.readPrefs({ posX = 0, posY = 0.2 }, 3, 0.06).posX, nil)
	eq(geom.readPrefs({ posX = 0 / 0, posY = 0.2 }, 3, 0.06).posX, nil)
	eq(geom.readPrefs({ posX = "0.5", posY = 0.2 }, 3, 0.06).posX, nil)
	-- size index must be a whole step that exists
	eq(geom.readPrefs({ sizeIdx = 4 }, 3, 0.06).sizeIdx, nil)
	eq(geom.readPrefs({ sizeIdx = 0 }, 3, 0.06).sizeIdx, nil)
	eq(geom.readPrefs({ sizeIdx = 1.5 }, 3, 0.06).sizeIdx, nil)
	-- non-booleans dropped; non-tables give an empty table
	eq(geom.readPrefs({ pinned = 1, open = "yes" }, 3, 0.06).pinned, nil)
	-- network layer toggle (phase 6): a boolean or nothing (older settings have no key)
	eq(geom.readPrefs({ showNet = true }, 3, 0.06).showNet, true)
	eq(geom.readPrefs({ showNet = 1 }, 3, 0.06).showNet, nil)
	eq(geom.readPrefs({}, 3, 0.06).showNet, nil)
	-- hi-vis palette toggle (revision 5): a boolean or nothing
	eq(geom.readPrefs({ hiVis = true }, 3, 0.06).hiVis, true)
	eq(geom.readPrefs({ hiVis = false, showNet = true }, 3, 0.06).hiVis, false)
	eq(geom.readPrefs({ hiVis = "on" }, 3, 0.06).hiVis, nil)
	eq(geom.readPrefs({}, 3, 0.06).hiVis, nil)
	local e = geom.readPrefs(nil, 3, 0.06)
	eq(e.posX, nil); eq(e.pinned, nil); eq(e.sizeIdx, nil)
	eq(geom.readPrefs("junk", 3, 0.06).open, nil)
end)

test("clipBox inside, clipped left/top, clipped right/bottom", function()
	local l, t, w, h = geom.clipBox(100, 200, 40, 20, 240, 480)
	assert(l == 80 and t == 190 and w == 40 and h == 20, "inside")
	l, t, w, h = geom.clipBox(10, 5, 40, 20, 240, 480)
	assert(l == 0 and t == 0 and w == 30 and h == 15, "left/top")
	l, t, w, h = geom.clipBox(230, 475, 40, 20, 240, 480)
	assert(l == 210 and t == 465 and w == 30 and h == 15, "right/bottom")
end)

-- Phase 7: industry filter helpers.

test("readPrefs keeps the filter string only", function()
	eq(geom.readPrefs({ filterTypes = "a.con|b.con" }, 2, 0.06).filterTypes, "a.con|b.con")
	eq(geom.readPrefs({ filterTypes = "" }, 2, 0.06).filterTypes, "")
	eq(geom.readPrefs({ filterTypes = 5 }, 2, 0.06).filterTypes, nil)
	eq(geom.readPrefs({}, 2, 0.06).filterTypes, nil)
end)

test("markerLayout carries the type key", function()
	local box = geom.boxFromBounds(0, 0, 100, 100)
	local l = geom.markerLayout({ { entity = 1, x = 50, y = 50, icon = "i", name = "n", typeKey = "farm.con" } },
		box, geom.DEFAULT_ORIENT, 100, 100, 10)
	eq(#l, 1); eq(l[1].typeKey, "farm.con")
end)

local function mk(entity, left, top, typeKey)
	return { key = "k" .. entity, entity = entity, left = left, top = top, icon = "i", typeKey = typeKey }
end

test("hitMarker finds the marker under the point, with tolerance", function()
	local ms = { mk(1, 10, 10, "a"), mk(2, 50, 50, "b") }
	eq(geom.hitMarker(ms, 15, 15, 10, 2).entity, 1)
	eq(geom.hitMarker(ms, 10, 10, 10, 0).entity, 1)  -- edge counts
	eq(geom.hitMarker(ms, 21, 15, 10, 2).entity, 1)  -- inside the tolerance
	eq(geom.hitMarker(ms, 23, 15, 10, 2), nil)        -- outside
	eq(geom.hitMarker(ms, 55, 55, 10, 2).entity, 2)
	eq(geom.hitMarker(ms, 35, 35, 10, 2), nil)
	eq(geom.hitMarker(nil, 1, 1, 10, 2), nil)
	eq(geom.hitMarker({}, 1, 1, 10, 2), nil)
end)

test("hitMarker picks the nearest centre of overlapping markers, ties to the one on top", function()
	local ms = { mk(1, 10, 10, "a"), mk(2, 16, 10, "b") }
	eq(geom.hitMarker(ms, 14, 15, 10, 0).entity, 1)  -- centre 15 vs 21
	eq(geom.hitMarker(ms, 19, 15, 10, 0).entity, 2)
	eq(geom.hitMarker(ms, 18, 15, 10, 0).entity, 2)  -- equal distance (3): the later (drawn on top) wins
end)

test("hitMarker skips markers that aren't visible", function()
	local ms = { mk(1, 10, 10, "a"), mk(2, 12, 10, "b") }
	local onlyA = function(m) return m.typeKey == "a" end
	eq(geom.hitMarker(ms, 20, 15, 10, 0, onlyA).entity, 1)
	eq(geom.hitMarker(ms, 21, 15, 10, 0, function() return false end), nil)
end)

test("controlRows: greedy rows by estimated width, hidden controls left out", function()
	local function ids(rows)
		local out = {}
		for _, r in ipairs(rows) do out[#out + 1] = table.concat(r, " ") end
		return table.concat(out, " / ")
	end
	local W = { ind = 47, filter = 68, net = 47, viz = 47 }
	local all = { "ind", "filter", "net", "viz" }
	eq(ids(geom.controlRows(235, all, W, 6, 8)), "ind filter net viz")
	eq(ids(geom.controlRows(234, all, W, 6, 8)), "ind filter net / viz")
	eq(ids(geom.controlRows(129, all, W, 6, 8)), "ind filter / net viz")
	eq(ids(geom.controlRows(120, all, W, 6, 8)), "ind / filter / net viz")
	eq(ids(geom.controlRows(120, { "ind", "net" }, W, 6, 8)), "ind net")
	eq(ids(geom.controlRows(161, { "ind", "net", "viz" }, W, 6, 8)), "ind net viz")
	eq(ids(geom.controlRows(160, { "ind", "net", "viz" }, W, 6, 8)), "ind net / viz")
	eq(ids(geom.controlRows(40, { "ind", "net" }, W, 6, 8)), "ind / net")
	eq(ids(geom.controlRows(200, {}, W, 6, 8)), "")
end)

test("textUnits / controlWidth: UTF-8 chars, CJK twice; fits the measured English widths", function()
	eq(geom.textUnits(""), 0)
	eq(geom.textUnits("Ind"), 3)
	eq(geom.textUnits("Фильтр"), 6) -- Cyrillic: 2-byte, one unit each
	eq(geom.textUnits("Ärger"), 5)
	eq(geom.textUnits("産業"), 4) -- kana/ideographs: wide
	eq(geom.textUnits("필터"), 4) -- Hangul: wide
	eq(geom.textUnits("€5"), 2) -- 3-byte below U+3000: narrow
	eq(geom.controlWidth("Ind"), 47)
	eq(geom.controlWidth("Filter"), 68)
	eq(geom.controlWidth(nil), 26)
	-- Translated labels push controls onto a second row sooner.
	local function ids(rows)
		local out = {}
		for _, r in ipairs(rows) do out[#out + 1] = table.concat(r, " ") end
		return table.concat(out, " / ")
	end
	local ru = { ind = geom.controlWidth("Пром"), filter = geom.controlWidth("Фильтр"),
		net = geom.controlWidth("Сеть"), viz = geom.controlWidth("Ярко") }
	eq(ids(geom.controlRows(235, { "ind", "filter", "net", "viz" }, ru, 6, 8)), "ind filter net / viz")
	eq(ids(geom.controlRows(256, { "ind", "filter", "net", "viz" }, ru, 6, 8)), "ind filter net viz")
end)

test("fitText: cuts at a UTF-8 boundary with '...', CJK counted twice", function()
	eq(select(1, geom.fitText("Sawmill", 10)), "Sawmill")
	eq(select(2, geom.fitText("Sawmill", 10)), false)
	local s, cut = geom.fitText("Лесозаготовительное предприятие", 22)
	eq(cut, true)
	eq(s, "Лесозаготовительное...") -- trailing space dropped
	eq(geom.textUnits(s) <= 22, true)
	eq(select(1, geom.fitText("Завод по производству инструментов", 20)), "Завод по производ...")
	eq(select(1, geom.fitText("食品加工工場", 9)), "食品加...") -- 3 wide chars = 6 units + 3
	eq(select(1, geom.fitText("Ab", 2)), "Ab")
end)
