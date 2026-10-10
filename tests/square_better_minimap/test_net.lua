-- minimap_net (phase 6 network layer): transform, Hermite sampling, rasteriser, diff, encoder.
-- Pure module, no api.*.

local net = ug_require "square_better_minimap::/minimap/minimap_net.tl"
local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl"

local BOX = geom.boxFromBounds(-1000, -500, 1000, 500) -- 2000 x 1000 m
local ORIENT = geom.DEFAULT_ORIENT

local function cell(g, x, y) return g.cells[y * g.w + x + 1] end

local function countNonZero(g)
	local n = 0
	for i = 1, #g.cells do if g.cells[i] ~= 0 then n = n + 1 end end
	return n
end

local function allZero(g)
	for i = 1, #g.cells do if g.cells[i] ~= 0 then return false end end
	return true
end

-- transform ---------------------------------------------------------------

test("imageSize keeps the aspect on the long side", function()
	local w, h = net.imageSize(BOX, ORIENT, 512)
	eq(w, 512); eq(h, 256)
	local tall = geom.boxFromBounds(0, 0, 1000, 4000)
	w, h = net.imageSize(tall, ORIENT, 512)
	eq(w, 128); eq(h, 512)
	w, h = net.imageSize(BOX, { flipX = false, flipY = true, swapXY = true }, 512)
	eq(w, 256); eq(h, 512)
end)

test("toPx matches geom.worldToFrac times the image size (all orientations)", function()
	local orients = {
		ORIENT,
		{ flipX = false, flipY = false, swapXY = false },
		{ flipX = true, flipY = false, swapXY = false },
		{ flipX = true, flipY = true, swapXY = true },
		{ flipX = false, flipY = true, swapXY = true },
	}
	for _, o in ipairs(orients) do
		local w, h = net.imageSize(BOX, o, 400)
		local xf = net.makeXform(BOX, o, w, h)
		for _, p in ipairs({ { -1000, -500 }, { 1000, 500 }, { 0, 0 }, { 250, -125 }, { -730, 410 } }) do
			local fx, fy = geom.worldToFrac(p[1], p[2], BOX, o)
			local px, py = net.toPx(xf, p[1], p[2])
			near(px, fx * w, 1e-9)
			near(py, fy * h, 1e-9)
		end
	end
end)

test("default orientation: world +y is up in the image", function()
	local xf = net.makeXform(BOX, ORIENT, 400, 200)
	local x, y = net.toPx(xf, -1000, 500) -- north-west corner
	near(x, 0, 1e-9); near(y, 0, 1e-9)
	x, y = net.toPx(xf, 1000, -500)
	near(x, 400, 1e-9); near(y, 200, 1e-9)
	local dx, dy = net.vecToPx(xf, 100, 100) -- 100 m east + north = 20 px right, 20 px up
	near(dx, 20, 1e-9); near(dy, -20, 1e-9)
end)

test("vecToPx swaps with the axes", function()
	local o = { flipX = false, flipY = false, swapXY = true }
	local xf = net.makeXform(BOX, o, 200, 400)
	local dx, dy = net.vecToPx(xf, 100, 0) -- world x now runs down the image
	near(dx, 0, 1e-9); near(dy, 20, 1e-9)
end)

-- Hermite -----------------------------------------------------------------

test("a straight edge is one segment", function()
	eq(net.curveSegments(0, 0, 30, 0, 30, 0, 30, 0), 1)
	local xf = net.makeXform(BOX, ORIENT, 400, 200)
	local pts = net.hermitePolyline(xf, -500, 0, 500, 0, 0, 0, 500, 0)
	eq(#pts, 4)
	eq(pts[1], 100); eq(pts[2], 100); eq(pts[3], 200); eq(pts[4], 100)
end)

test("a curve gets more segments the longer it is, capped", function()
	-- quarter circle-ish in pixels
	local n1 = net.curveSegments(0, 0, 20, 0, 20, 20, 0, 20)
	local n2 = net.curveSegments(0, 0, 200, 0, 200, 200, 0, 200)
	ok(n1 >= 2, "curved: at least two segments, got " .. n1)
	ok(n2 > n1, "longer curve, more segments")
	eq(net.curveSegments(0, 0, 4000, 0, 4000, 4000, 0, 4000), net.MAX_SEGS)
end)

test("the polyline follows the Hermite curve and ends on the end points", function()
	local xf = net.makeXform(geom.boxFromBounds(0, 0, 1000, 1000), { flipX = false, flipY = false, swapXY = false }, 1000, 1000)
	-- quarter arc from (100,500) heading +x to (500,900) heading +y
	local pts = net.hermitePolyline(xf, 100, 500, 400, 0, 500, 900, 0, 400)
	eq(pts[1], 100); eq(pts[2], 500)
	eq(pts[#pts - 1], 500); eq(pts[#pts], 900)
	ok(#pts >= 6, "sampled into several points")
	-- midpoint of the Hermite at t = 0.5: 0.5 * (p0 + p1) + 0.125 * (t0 - t1)
	local mx, my = 0.5 * (100 + 500) + 0.125 * (400 - 0), 0.5 * (500 + 900) + 0.125 * (0 - 400)
	local best = math.huge
	for i = 1, #pts - 1, 2 do
		local d = math.sqrt((pts[i] - mx) ^ 2 + (pts[i + 1] - my) ^ 2)
		if d < best then best = d end
	end
	ok(best < 10, "a sample near the curve midpoint, off by " .. best)
	-- no consecutive duplicates
	for i = 3, #pts - 1, 2 do
		ok(pts[i] ~= pts[i - 2] or pts[i + 1] ~= pts[i - 1], "duplicate point at " .. i)
	end
end)

test("a zero-length edge gives one point", function()
	local xf = net.makeXform(BOX, ORIENT, 400, 200)
	local pts = net.hermitePolyline(xf, 0, 0, 0, 0, 0, 0, 0, 0)
	eq(#pts, 2)
end)

-- rasteriser --------------------------------------------------------------

test("drawPolyline draws a connected line and removes it exactly", function()
	local g = net.newGrid(20, 10)
	local n = net.drawPolyline(g, { 1, 1, 10, 6, 15, 2 }, net.UNIT_STREET, 1, false)
	ok(n > 0)
	eq(countNonZero(g), n)
	eq(cell(g, 1, 1), net.UNIT_STREET)
	eq(cell(g, 10, 6), net.UNIT_STREET) -- the joint is drawn once
	eq(cell(g, 15, 2), net.UNIT_STREET)
	-- Bresenham covers max(|dx|, |dy|) + 1 pixels per segment; the joint (10,6) is shared: 10 + (6 - 1)
	eq(n, 10 + 5)
	net.drawPolyline(g, { 1, 1, 10, 6, 15, 2 }, net.UNIT_STREET, -1, false)
	ok(allZero(g), "removed again")
end)

test("overlapping items count per layer; removing one keeps the other", function()
	local g = net.newGrid(10, 10)
	net.drawPolyline(g, { 0, 5, 9, 5 }, net.UNIT_STREET, 1, false)
	net.drawPolyline(g, { 5, 0, 5, 9 }, net.UNIT_TRACK, 1, false)
	net.fillRect(g, 4, 4, 6, 6, net.UNIT_TOWN, 1)
	eq(cell(g, 5, 5), net.UNIT_STREET + net.UNIT_TRACK + net.UNIT_TOWN)
	eq(net.layerOf(cell(g, 5, 5)), 3)
	eq(net.layerOf(cell(g, 2, 5)), 2)
	eq(net.layerOf(cell(g, 4, 4)), 1)
	eq(net.layerOf(cell(g, 0, 0)), 0)
	net.drawPolyline(g, { 5, 0, 5, 9 }, net.UNIT_TRACK, -1, false)
	eq(cell(g, 5, 5), net.UNIT_STREET + net.UNIT_TOWN)
	eq(net.layerOf(cell(g, 5, 5)), 2)
	eq(cell(g, 5, 0), 0)
end)

test("two equal streets on one pixel: one removal keeps it drawn", function()
	local g = net.newGrid(5, 5)
	net.drawPolyline(g, { 0, 0, 4, 0 }, net.UNIT_STREET, 1, false)
	net.drawPolyline(g, { 0, 0, 4, 0 }, net.UNIT_STREET, 1, false)
	eq(cell(g, 2, 0), 2 * net.UNIT_STREET)
	net.drawPolyline(g, { 0, 0, 4, 0 }, net.UNIT_STREET, -1, false)
	eq(net.layerOf(cell(g, 2, 0)), 2)
end)

test("removing more than was added never goes below zero or into another layer", function()
	local g = net.newGrid(5, 5)
	net.fillRect(g, 0, 0, 1, 1, net.UNIT_TOWN, 1)
	net.drawPolyline(g, { 0, 0, 4, 0 }, net.UNIT_STREET, -1, false)
	eq(cell(g, 0, 0), net.UNIT_TOWN)
	net.fillRect(g, 0, 0, 1, 1, net.UNIT_TOWN, -1)
	net.fillRect(g, 0, 0, 1, 1, net.UNIT_TOWN, -1)
	ok(allZero(g))
end)

test("pixels outside the image are skipped", function()
	local g = net.newGrid(8, 8)
	local n = net.drawPolyline(g, { -5, 4, 12, 4 }, net.UNIT_STREET, 1, false)
	eq(n, 8)
	eq(net.fillRect(g, -3, -3, 0, 0, net.UNIT_TOWN, 1), 1)
	eq(net.fillRect(g, 9, 9, 12, 12, net.UNIT_TOWN, 1), 0)
end)

test("dashed (tunnel) lines draw half the pixels and remove cleanly", function()
	local g = net.newGrid(40, 3)
	local n = net.drawPolyline(g, { 0, 1, 39, 1 }, net.UNIT_TRACK, 1, true)
	eq(n, 20)
	eq(cell(g, 0, 1), net.UNIT_TRACK); eq(cell(g, 1, 1), net.UNIT_TRACK)
	eq(cell(g, 2, 1), 0); eq(cell(g, 3, 1), 0)
	net.drawPolyline(g, { 0, 1, 39, 1 }, net.UNIT_TRACK, -1, true)
	ok(allZero(g))
end)

test("drawItem dispatches by kind; KIND_NONE draws nothing", function()
	local g = net.newGrid(10, 10)
	eq(net.drawItem(g, { kind = net.KIND_NONE }, 1), 0)
	eq(net.drawItem(g, { kind = net.KIND_TOWN, x0 = 1, y0 = 1, x1 = 2, y1 = 2 }, 1), 4)
	eq(net.drawItem(g, { kind = net.KIND_STREET, pts = { 0, 0, 9, 0 } }, 1), 10)
	eq(net.drawItem(g, { kind = net.KIND_TRACK, pts = { 0, 9 } }, 1), 1)
	eq(net.drawItem(g, nil, 1), 0)
end)

test("rectFromBounds orders the corners under a flipped axis", function()
	local xf = net.makeXform(BOX, ORIENT, 400, 200)
	local x0, y0, x1, y1 = net.rectFromBounds(xf, 0, 0, 20, 20) -- 4 x 4 px, y flipped
	eq(x0, 200); eq(x1, 204); eq(y0, 96); eq(y1, 100)
end)

test("a random add/remove sequence returns to an empty grid", function()
	local g = net.newGrid(64, 48)
	local xf = net.makeXform(BOX, ORIENT, 64, 48)
	local items = {}
	local seed = 12345
	local function rnd(a, b)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return a + seed % (b - a + 1)
	end
	for i = 1, 200 do
		local kind = rnd(1, 3)
		local it = { kind = kind }
		if kind == 1 then
			it.x0, it.y0, it.x1, it.y1 = net.rectFromBounds(xf, rnd(-1100, 900), rnd(-600, 400), rnd(-900, 1100), rnd(-400, 600))
		else
			it.pts = net.hermitePolyline(xf, rnd(-1100, 1100), rnd(-600, 600), rnd(-800, 800), rnd(-800, 800),
				rnd(-1100, 1100), rnd(-600, 600), rnd(-800, 800), rnd(-800, 800))
			it.dashed = rnd(0, 3) == 0
		end
		items[i] = it
		net.drawItem(g, it, 1)
	end
	ok(not allZero(g))
	for i = 200, 1, -2 do net.drawItem(g, items[i], -1) end
	for i = 1, 199, 2 do net.drawItem(g, items[i], -1) end
	ok(allZero(g), "every pixel back to 0")
end)

-- flatten + sweep (the scan's diff) ---------------------------------------

--- Flattens map (node -> ids) into the cache's stamps, then sweeps; small chunks.
local function runDiff(map, cache, stamp, chunk)
	local added, kinds, removed = {}, {}, {}
	local f = net.newFlatten(map, net.KIND_STREET, stamp, added, kinds, {})
	local steps = 0
	while not net.flattenStep(f, cache, chunk or 2) do
		steps = steps + 1
		assert(steps < 1000, "flatten does not finish")
	end
	local sw = net.newSweep(stamp, removed)
	while not net.sweepStep(sw, cache, chunk or 2) do
		steps = steps + 1
		assert(steps < 2000, "sweep does not finish")
	end
	table.sort(added); table.sort(removed)
	return { added = added, removed = removed, kinds = kinds }, steps
end

test("flatten + sweep find added and removed ids, in small resumable steps", function()
	local cache = { [1] = { seen = 1 }, [2] = { seen = 1 }, [3] = { seen = 1 } }
	local d, steps = runDiff({ [100] = { 2, 3 }, [101] = { 4, 5 } }, cache, 2, 2)
	eq(d.added, { 4, 5 })
	eq(d.kinds, { net.KIND_STREET, net.KIND_STREET })
	eq(d.removed, { 1 })
	eq(cache[2].seen, 2); eq(cache[3].seen, 2)
	ok(steps >= 3, "it took several steps")
end)

test("flatten lists an id once (street maps name each edge at both nodes)", function()
	local d = runDiff({ [1] = { 7, 8 }, [2] = { 7 }, [3] = {}, [4] = { 8, 7 } }, {}, 1, 1)
	eq(d.added, { 7, 8 })
	eq(d.removed, {})
end)

test("flatten keeps the map's first-seen order and the kind per id", function()
	-- one key: the order is the array order (next() order across keys is the map's own)
	local added, kinds, set = {}, {}, {}
	local f = net.newFlatten({ [5] = { 30, 10, 20, 10 } }, net.KIND_TRACK, 1, added, kinds, set)
	while not net.flattenStep(f, {}, 3) do end
	eq(added, { 30, 10, 20 })
	eq(kinds, { net.KIND_TRACK, net.KIND_TRACK, net.KIND_TRACK })
	-- a second map into the same lists (streets, then tracks) appends; a shared id stays once
	f = net.newFlatten({ [6] = { 20, 40 } }, net.KIND_STREET, 1, added, kinds, set)
	while not net.flattenStep(f, {}, 3) do end
	eq(added, { 30, 10, 20, 40 })
	eq(kinds[4], net.KIND_STREET)
end)

test("an empty map removes everything; an unchanged one nothing", function()
	local cache = { [10] = { seen = 4 }, [11] = { seen = 4 } }
	local d = runDiff({}, cache, 5)
	eq(d.removed, { 10, 11 })
	cache = { [10] = { seen = 4 }, [11] = { seen = 4 } }
	d = runDiff({ [1] = { 11 }, [2] = { 10 } }, cache, 5)
	eq(d.added, {}); eq(d.removed, {})
end)

-- encoder -----------------------------------------------------------------

local PALETTE_RGBA = {
	{ 0, 0, 0, 0 },         -- none
	{ 170, 160, 150, 160 }, -- town
	{ 240, 240, 235, 230 }, -- street
	{ 40, 40, 48, 255 },    -- track
}

test("orderColor permutes the channels", function()
	eq(net.orderColor({ 1, 2, 3, 4 }, "RGBA"), { 1, 2, 3, 4 })
	eq(net.orderColor({ 1, 2, 3, 4 }, "BGRA"), { 3, 2, 1, 4 })
	eq(net.orderColor({ 1, 2, 3, 4 }, "ARGB"), { 4, 1, 2, 3 })
	eq(net.orderColor({ 1, 2, 3, 4 }, "ABGR"), { 4, 3, 2, 1 })
	eq(net.orderColor({ 1, 2, 3, 4 }, "nonsense"), { 1, 2, 3, 4 })
end)

test("encodeRows writes 4 bytes per pixel, the top layer's colour, exact length", function()
	local g = net.newGrid(3, 2)
	g.cells[1] = net.UNIT_TOWN
	g.cells[2] = net.UNIT_STREET + net.UNIT_TOWN
	g.cells[3] = net.UNIT_TRACK + net.UNIT_STREET
	local out = {}
	local pal = net.makePalette(PALETTE_RGBA, "RGBA")
	net.encodeRows(g, out, 0, 1, pal, false)
	net.encodeRows(g, out, 1, 5, pal, false) -- row1 past the end is clamped
	eq(#out, net.expectedLength(3, 2))
	eq({ out[1], out[2], out[3], out[4] }, PALETTE_RGBA[2])
	eq({ out[5], out[6], out[7], out[8] }, PALETTE_RGBA[3])
	eq({ out[9], out[10], out[11], out[12] }, PALETTE_RGBA[4])
	for i = 13, 24 do eq(out[i], 0) end
	for i = 1, #out do
		ok(out[i] >= 0 and out[i] <= 255 and math.floor(out[i]) == out[i], "byte at " .. i)
	end
end)

test("encodeRows with flipped rows and BGRA order", function()
	local g = net.newGrid(2, 2)
	g.cells[1] = net.UNIT_TRACK -- grid row 0
	local out = {}
	net.encodeRows(g, out, 0, 2, net.makePalette(PALETTE_RGBA, "BGRA"), true)
	eq(#out, 16)
	-- grid row 0 lands in image row 1
	eq({ out[1], out[2], out[3], out[4] }, { 0, 0, 0, 0 })
	eq({ out[9], out[10], out[11], out[12] }, { 48, 40, 40, 255 })
end)

test("paintCalibration: red, green, blue, half white at the top-left, inside the buffer", function()
	local w, h = 96, 48
	local out = {}
	local g = net.newGrid(w, h)
	net.encodeRows(g, out, 0, h, net.makePalette(PALETTE_RGBA, "RGBA"), false)
	local s = net.paintCalibration(out, w, h, "RGBA", false)
	eq(s, 4)
	eq(#out, net.expectedLength(w, h))
	local function px(x, y) local o = (y * w + x) * 4 return { out[o + 1], out[o + 2], out[o + 3], out[o + 4] } end
	local gap = 1
	eq(px(gap, gap), { 255, 0, 0, 255 })
	eq(px(gap + (s + gap), gap), { 0, 255, 0, 255 })
	eq(px(gap + 2 * (s + gap), gap), { 0, 0, 255, 255 })
	eq(px(gap + 3 * (s + gap), gap), { 255, 255, 255, 128 })
	eq(px(0, 0), { 0, 0, 0, 0 })
	-- flipped: the patch sits in the last rows of the buffer
	local out2 = {}
	net.encodeRows(g, out2, 0, h, net.makePalette(PALETTE_RGBA, "RGBA"), true)
	net.paintCalibration(out2, w, h, "RGBA", true)
	eq(#out2, net.expectedLength(w, h))
	local o = ((h - 1 - gap) * w + gap) * 4
	eq({ out2[o + 1], out2[o + 2], out2[o + 3], out2[o + 4] }, { 255, 0, 0, 255 })
	eq(net.paintCalibration({}, 10, 3, "RGBA", false), 0)
end)

test("scanInterval: at least the minimum, longer for slow lists, capped", function()
	eq(net.scanInterval(0, 5, 60, 500), 5)
	eq(net.scanInterval(20, 5, 60, 500), 10)
	eq(net.scanInterval(1000, 5, 60, 500), 60)
	eq(net.scanInterval(nil, 5, 60, 500), 5)
end)

-- palettes, hi-vis switch, parked caches (revision 5 round 3) ------------------

test("both palettes: transparent background, four bytes per layer, hi-vis fully opaque", function()
	for _, cols in ipairs({ net.COLORS_NORMAL, net.COLORS_HIVIS }) do
		eq(#cols, 4)
		eq(cols[1], { 0, 0, 0, 0 })
		for l = 1, 4 do
			eq(#cols[l], 4)
			for c = 1, 4 do ok(cols[l][c] >= 0 and cols[l][c] <= 255 and math.floor(cols[l][c]) == cols[l][c], "byte") end
		end
	end
	for l = 2, 4 do
		eq(net.COLORS_HIVIS[l][4], 255)
		ok(net.COLORS_HIVIS[l][1] ~= net.COLORS_NORMAL[l][1] or net.COLORS_HIVIS[l][2] ~= net.COLORS_NORMAL[l][2]
			or net.COLORS_HIVIS[l][3] ~= net.COLORS_NORMAL[l][3], "hi-vis differs from normal for layer " .. l)
	end
	-- the three hi-vis layers are distinct colours
	ok(net.COLORS_HIVIS[2][2] ~= net.COLORS_HIVIS[3][2] and net.COLORS_HIVIS[3][3] ~= net.COLORS_HIVIS[4][3], "distinct")
	eq(net.paletteFor(false, "RGBA"), net.makePalette(net.COLORS_NORMAL, "RGBA"))
	eq(net.paletteFor(true, "RGBA"), net.makePalette(net.COLORS_HIVIS, "RGBA"))
	eq(net.paletteFor(true, "BGRA")[3], net.orderColor(net.COLORS_HIVIS[3], "BGRA"))
end)

test("palette switch re-encodes into the reused buffer: every byte rewritten, grid untouched", function()
	local w, h = 40, 24
	local g = net.newGrid(w, h)
	local xf = net.makeXform(geom.boxFromBounds(0, 0, 400, 240), ORIENT, w, h)
	net.drawItem(g, { kind = net.KIND_TOWN, x0 = 2, y0 = 2, x1 = 9, y1 = 7 }, 1)
	net.drawItem(g, { kind = net.KIND_STREET, pts = net.hermitePolyline(xf, 10, 10, 300, 0, 310, 10, 300, 0) }, 1)
	net.drawItem(g, { kind = net.KIND_TRACK, dashed = true, pts = net.hermitePolyline(xf, 20, 230, 0, -200, 20, 30, 0, -200) }, 1)
	local before = {}
	for i = 1, #g.cells do before[i] = g.cells[i] end
	local function encodeAll(out, hiVis)
		local rows = math.max(1, 64 // w) -- sliced like the scheduler (NET_ENCODE_PX // w rows per step)
		local r = 0
		while r < h do net.encodeRows(g, out, r, r + rows, net.paletteFor(hiVis, "RGBA"), true); r = r + rows end
	end
	local buf = {}
	encodeAll(buf, false)
	eq(#buf, net.expectedLength(w, h))
	encodeAll(buf, true) -- the same table, other palette
	eq(#buf, net.expectedLength(w, h))
	local fresh = {}
	encodeAll(fresh, true)
	eq(buf, fresh)
	for i = 1, #g.cells do eq(g.cells[i], before[i]) end
	-- every pixel shows its layer's hi-vis colour (rows flipped)
	local counts = { 0, 0, 0, 0 }
	for row = 0, h - 1 do
		for x = 0, w - 1 do
			local layer = net.layerOf(g.cells[(h - 1 - row) * w + x + 1]) + 1
			local o = (row * w + x) * 4
			eq({ buf[o + 1], buf[o + 2], buf[o + 3], buf[o + 4] }, net.COLORS_HIVIS[layer])
			counts[layer] = counts[layer] + 1
		end
	end
	ok(counts[2] > 0 and counts[3] > 0 and counts[4] > 0, "all three layers drawn")
	-- and back: identical to the first normal encode
	encodeAll(buf, false)
	local normal = {}
	encodeAll(normal, false)
	eq(buf, normal)
end)

test("encodeBand: only changed bands are rewritten, and the kept buffer equals a fresh full encode", function()
	local w, h = 64, 45 -- 6 bands, the last one short
	local box = geom.boxFromBounds(0, 0, 640, 450)
	local xf = net.makeXform(box, ORIENT, w, h)
	local g = net.newGrid(w, h)
	eq(net.bandCount(g), 6)
	local seed = 4242
	local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
	local items = {}
	for i = 1, 60 do
		local it
		if i % 3 == 0 then
			local x, y = rnd(w), rnd(h)
			it = { kind = net.KIND_TOWN, x0 = x, y0 = y, x1 = x + rnd(5), y1 = y + rnd(5) }
		else
			local x0, y0 = rnd(640), rnd(450)
			it = { kind = (i % 2 == 0) and net.KIND_TRACK or net.KIND_STREET, dashed = i % 5 == 0,
				pts = net.hermitePolyline(xf, x0, y0, rnd(200) - 100, rnd(200) - 100, x0 + rnd(160) - 80, y0 + rnd(160) - 80, rnd(200) - 100, rnd(200) - 100) }
		end
		items[i] = it
	end
	for _, flip in ipairs({ false, true }) do
		local pal = net.paletteFor(false, "RGBA")
		local g2 = net.newGrid(w, h)
		for i = 1, 30 do net.drawItem(g2, items[i], 1) end
		local buf = {}
		for b = 1, net.bandCount(g2) do ok(net.encodeBand(g2, buf, b, pal, flip, true), "full encode writes every band") end
		for b = 1, net.bandCount(g2) do eq(g2.dirty[b], false) end
		-- nothing changed: no band is encoded
		for b = 1, net.bandCount(g2) do eq(net.encodeBand(g2, buf, b, pal, flip, false), false) end
		-- a few changes, then only their bands
		for step = 1, 6 do
			for i = 1, 5 do
				local k = rnd(60) + 1
				net.drawItem(g2, items[k], (rnd(2) == 0) and 1 or -1)
			end
			local n = 0
			for b = 1, net.bandCount(g2) do if net.encodeBand(g2, buf, b, pal, flip, false) then n = n + 1 end end
			local fresh = {}
			for b = 1, net.bandCount(g2) do net.encodeBand(g2, fresh, b, pal, flip, true) end
			eq(#buf, net.expectedLength(w, h))
			eq(buf, fresh, "partial encode == full encode (step " .. step .. ", flip " .. tostring(flip) .. ")")
		end
	end
end)

test("a change marks only the bands of its rows", function()
	local g = net.newGrid(32, 32) -- 4 bands of 8 rows
	net.drawItem(g, { kind = net.KIND_TOWN, x0 = 2, y0 = 9, x1 = 5, y1 = 15 }, 1)
	eq(g.dirty, { false, true, false, false })
	net.drawItem(g, { kind = net.KIND_STREET, pts = { 0, 7, 20, 25 } }, 1)
	eq(g.dirty, { true, true, true, true })
	for b = 1, 4 do g.dirty[b] = false end
	-- nothing changes (removing what isn't there): no band marked
	net.drawItem(g, { kind = net.KIND_TRACK, pts = { 0, 0, 5, 0 } }, -1)
	eq(g.dirty, { false, false, false, false })
	-- off-image parts are clamped
	net.drawItem(g, { kind = net.KIND_TOWN, x0 = -5, y0 = 28, x1 = 3, y1 = 60 }, 1)
	eq(g.dirty, { false, false, false, true })
end)

test("nextScanSeconds: back-off doubles to the cap without changes, any change resets", function()
	eq(net.nextScanSeconds(5, 5, true, 30), 5)
	eq(net.nextScanSeconds(5, 5, false, 30), 10)
	eq(net.nextScanSeconds(10, 5, false, 30), 20)
	eq(net.nextScanSeconds(20, 5, false, 30), 30)
	eq(net.nextScanSeconds(30, 5, false, 30), 30)
	eq(net.nextScanSeconds(30, 5, true, 30), 5)
	eq(net.nextScanSeconds(nil, 7, false, 30), 7)
	-- a slow list (base above the cap) never goes below its base
	eq(net.nextScanSeconds(40, 40, false, 30), 40)
end)

-- strips -------------------------------------------------------------------

test("strip geometry: 64-row strips aligned with the bands, the last one short", function()
	eq(net.stripRows(), 64)
	eq(net.stripRows() % net.BAND_ROWS, 0)
	eq(net.stripCount(512), 8)
	eq(net.stripCount(256), 4)
	eq(net.stripCount(150), 3)
	eq(net.stripCount(1), 1)
	eq({ net.stripRange(150, 1) }, { 0, 64 })
	eq({ net.stripRange(150, 3) }, { 128, 150 })
	eq(net.stripOfBand(1), 1)
	eq(net.stripOfBand(8), 1)
	eq(net.stripOfBand(9), 2)
	eq(net.stripOfBand(19), 3)
	local g = net.newGrid(16, 150)
	net.drawItem(g, { kind = net.KIND_TOWN, x0 = 0, y0 = 70, x1 = 2, y1 = 71 }, 1)
	eq({ net.stripDirty(g, 1), net.stripDirty(g, 2), net.stripDirty(g, 3) }, { false, true, false })
	net.drawItem(g, { kind = net.KIND_TOWN, x0 = 0, y0 = 149, x1 = 0, y1 = 149 }, 1)
	eq(net.stripDirty(g, 3), true)
end)

local function stripWorld(w, h, seed)
	local g = net.newGrid(w, h)
	local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
	for i = 1, 80 do
		if i % 3 == 0 then
			local x, y = rnd(w), rnd(h)
			net.drawItem(g, { kind = net.KIND_TOWN, x0 = x, y0 = y, x1 = x + rnd(6), y1 = y + rnd(6) }, 1)
		else
			net.drawItem(g, { kind = (i % 2 == 0) and net.KIND_TRACK or net.KIND_STREET, dashed = i % 5 == 0,
				pts = { rnd(w), rnd(h), rnd(w), rnd(h), rnd(w), rnd(h) } }, 1)
		end
	end
	return g, rnd
end

--- Strips concatenated as one image: bottom-up (flip) = last strip first, else first strip first.
local function joinStrips(bufs, n, flip)
	local full = {}
	local s0, s1, ds = 1, n, 1
	if flip then s0, s1, ds = n, 1, -1 end
	for s = s0, s1, ds do
		for i = 1, #bufs[s] do full[#full + 1] = bufs[s][i] end
	end
	return full
end

test("strips joined equal the full image byte for byte (both row orders, a short last strip)", function()
	for _, size in ipairs({ { 37, 150 }, { 64, 128 }, { 20, 9 } }) do
		local w, h = size[1], size[2]
		local g = stripWorld(w, h, 777)
		for _, hiVis in ipairs({ false, true }) do
			local pal = net.paletteFor(hiVis, "RGBA")
			for _, flip in ipairs({ false, true }) do
				local full = {}
				net.encodeRows(g, full, 0, h, pal, flip)
				local bufs = {}
				for b = 1, net.bandCount(g) do
					local s = net.stripOfBand(b)
					bufs[s] = bufs[s] or {}
					ok(net.encodeStripBand(g, bufs[s], b, pal, flip, true))
				end
				eq(#bufs, net.stripCount(h))
				for s = 1, #bufs do
					local r0, r1 = net.stripRange(h, s)
					eq(#bufs[s], net.expectedLength(w, r1 - r0), "strip " .. s .. " length")
				end
				eq(joinStrips(bufs, #bufs, flip), full, string.format("%dx%d flip=%s", w, h, tostring(flip)))
			end
		end
	end
end)

test("a flipped strip holds its own rows bottom-up: its first row is its lowest grid row", function()
	local g = net.newGrid(2, 70) -- strip 1: rows 0..63, strip 2: rows 64..69
	g.cells[63 * 2 + 1] = net.UNIT_TRACK -- grid row 63 (bottom of strip 1)
	g.cells[64 * 2 + 1] = net.UNIT_STREET -- grid row 64 (top of strip 2)
	local pal = net.makePalette(PALETTE_RGBA, "RGBA")
	local s1, s2 = {}, {}
	for b = 1, 8 do net.encodeStripBand(g, s1, b, pal, true, true) end
	for b = 9, 9 do net.encodeStripBand(g, s2, b, pal, true, true) end
	eq({ s1[1], s1[2], s1[3], s1[4] }, PALETTE_RGBA[4], "strip 1's first (drawn bottom) row is grid row 63")
	eq(#s2, 2 * 6 * 4)
	local o = 5 * 2 * 4 -- strip 2's last data row = its top = grid row 64
	eq({ s2[o + 1], s2[o + 2], s2[o + 3], s2[o + 4] }, PALETTE_RGBA[3])
end)

test("encodeStripBand: only changed bands rewritten; the kept strip buffers equal a fresh encode", function()
	local w, h = 40, 150
	for _, flip in ipairs({ false, true }) do
		local g, rnd = stripWorld(w, h, 31337)
		local pal = net.paletteFor(false, "RGBA")
		local bufs = {}
		for b = 1, net.bandCount(g) do
			local s = net.stripOfBand(b)
			bufs[s] = bufs[s] or {}
			net.encodeStripBand(g, bufs[s], b, pal, flip, true)
		end
		for b = 1, net.bandCount(g) do eq(net.encodeStripBand(g, bufs[net.stripOfBand(b)], b, pal, flip, false), false) end
		for step = 1, 5 do
			local x, y = rnd(w), rnd(h)
			local it = { kind = net.KIND_STREET, pts = { x, y, x + 3, y + 2 } }
			net.drawItem(g, it, 1)
			local n = 0
			for b = 1, net.bandCount(g) do
				if net.encodeStripBand(g, bufs[net.stripOfBand(b)], b, pal, flip, false) then n = n + 1 end
			end
			ok(n >= 1 and n <= 2, "one short line: 1-2 bands, got " .. n)
			local full = {}
			net.encodeRows(g, full, 0, h, pal, flip)
			eq(joinStrips(bufs, #bufs, flip), full, "step " .. step)
		end
	end
end)

test("stripPlacement: strips tile the picture without gaps or overlaps, seams within 0.5 px", function()
	for _, c in ipairs({ { 512, 360 }, { 512, 560 }, { 512, 720 }, { 512, 200 }, { 300, 333 }, { 150, 701 }, { 9, 250 }, { 512, 512 } }) do
		local H, h = c[1], c[2]
		local nextTop = 0
		for s = 1, net.stripCount(H) do
			local r0, r1 = net.stripRange(H, s)
			local top, height = net.stripPlacement(r0, r1, H, h)
			eq(top, nextTop, string.format("H=%d h=%d strip %d starts where the previous ended", H, h, s))
			ok(height > 0, "positive height")
			ok(math.abs(top - r0 * h / H) <= 0.5, "seam within 0.5 px")
			nextTop = top + height
		end
		eq(nextTop, h, string.format("H=%d h=%d: the strips cover the whole picture", H, h))
	end
	-- the exact case: 512 rows into 512 px is 64 px per strip
	eq({ net.stripPlacement(64, 128, 512, 512) }, { 64, 64 })
end)

test("stripKey: changes with the strip, its version, the size and the hand-off mode only", function()
	local k = net.stripKey(2, 3, 560, 560, "params")
	eq(k, net.stripKey(2, 3, 560, 560, "params"))
	ok(k ~= net.stripKey(1, 3, 560, 560, "params"))
	ok(k ~= net.stripKey(2, 4, 560, 560, "params"))
	ok(k ~= net.stripKey(2, 3, 200, 560, "params"))
	ok(k ~= net.stripKey(2, 3, 560, 200, "params"))
	ok(k ~= net.stripKey(2, 3, 560, 560, "table"))
	eq(net.stripKey(nil, nil, 1, 2, nil), "minimap_net_s0_v0_1x2_none")
end)

test("paintCalibration into a strip: squares sized from the whole picture (refSide)", function()
	local w, h = 512, 64
	local out = {}
	local g = net.newGrid(w, h)
	net.encodeRows(g, out, 0, h, net.makePalette(PALETTE_RGBA, "RGBA"), true)
	eq(net.paintCalibration(out, w, h, "RGBA", true, 512), 21)
	eq(net.paintCalibration(out, w, h, "RGBA", true), 4)
	eq(#out, net.expectedLength(w, h))
end)

test("recolorAction: encode when idle with a picture, restart mid-encode, dirty mid-scan", function()
	eq(net.recolorAction("idle", true), "encode")
	eq(net.recolorAction("idle", false), "none")
	eq(net.recolorAction(nil, true), "encode")
	eq(net.recolorAction("encode", true), "restart")
	eq(net.recolorAction("encode", false), "restart")
	eq(net.recolorAction("handoff", true), "restart")
	for _, ph in ipairs({ "list_s", "flat_s", "list_t", "flat_t", "sweep_e", "list_b", "flat_b", "sweep_b", "remove_e", "remove_b", "read_e", "read_b" }) do
		eq(net.recolorAction(ph, true), "dirty")
		eq(net.recolorAction(ph, false), "dirty")
	end
end)

test("parkExpired: kept for the given seconds, then released; not parked = never", function()
	eq(net.parkExpired(nil, 1e6, 60), false)
	eq(net.parkExpired(1000, 1000, 60), false)
	eq(net.parkExpired(1000, 60999, 60), false)
	eq(net.parkExpired(1000, 61000, 60), true)
	eq(net.parkExpired(1000, 1e9, 60), true)
	eq(net.parkExpired(1000, nil, 60), false)
end)
