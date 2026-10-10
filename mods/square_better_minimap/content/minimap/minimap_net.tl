-- Minimap network layer (PLAN.md phase 6): the pure part. World -> image pixels, Hermite edge
-- sampling, a counting rasteriser with dirty bands, the resumable map flatten + cache sweep and the
-- RGBA encoder. No api.* here; unit-tested in tests/square_better_minimap/test_net.lua and
-- test_net_golden.lua. Types: minimap_types.d.tl. The time-sliced scheduler is minimap_netscan.tl,
-- the engine reads gui/minimap_hud.script.tl ("Network layer").
--
-- GRID: one number per image pixel holding three per-layer counts (how many items cover the
-- pixel): towns x 1, streets x UNIT_STREET, tracks x UNIT_TRACK (12 bits each, exact in a double).
-- Adding an item adds its unit to every pixel it covers, removing it subtracts the same pixels
-- again (the rasteriser is deterministic), so a removal never needs a full redraw. The colour of a
-- pixel is its topmost non-empty layer (track over street over town), found with two comparisons.
--
-- IMAGE DATA: ImageView{ data, size } takes bytes, 3 or 4 per pixel. Evidence from the game binary
-- (build 40420, plans/square_better_minimap/PLAN.md "Phase 6"): BuiltinImageView.cpp computes
-- pixelSize = (data byte length) / (size.x * size.y) and accepts only 3 or 4 ("ImageView Cannot use
-- image data with invalid pixel size (only 3 or 4 is supported)"); anything else is logged and a
-- default image is shown instead (no throw, no read past the buffer). The params' data vector is a
-- VectorWrapper<unsigned char> (its luabridge type sits next to params::ImageView), so one Lua
-- integer = one byte. We send 4 bytes per pixel (alpha for the transparent background) in the
-- channel order NET_ORDER (script constant; the calibration patch confirms it in game).

local net : SquareMinimapNet = {}

net.UNIT_TOWN = 1
net.UNIT_STREET = 4096
net.UNIT_TRACK = 4096 * 4096
net.LAYER_MAX = 4095 -- count limit per layer and pixel (more would carry into the next layer)

net.KIND_NONE = 0
net.KIND_TOWN = 1
net.KIND_STREET = 2
net.KIND_TRACK = 3

net.FLAT_PX = 0.5   -- a curve whose control points are this close to the chord is drawn straight
net.SEG_PX = 3      -- curve segment length (pixels, along the control polygon)
net.MAX_SEGS = 32
net.DASH_ON = 2     -- tunnels: DASH_ON pixels drawn ...
net.DASH_PERIOD = 4 -- ... out of every DASH_PERIOD
net.BAND_ROWS = 8   -- grid rows per dirty flag (encodeBand re-encodes only changed bands)
net.STRIP_BANDS = 8 -- bands per image strip (STRIPS below): 64 rows, 128 KiB at 512 px wide

local UNITS : {integer : number} = { [1] = net.UNIT_TOWN, [2] = net.UNIT_STREET, [3] = net.UNIT_TRACK }

function net.imageSize(box : SquareMinimapBox, orient : SquareMinimapOrient, longSide : integer) : integer, integer
	local w = box.maxX - box.minX
	local h = box.maxY - box.minY
	if orient ~= nil and orient.swapXY then w, h = h, w end
	if w >= h then
		return longSide, math.max(1, math.floor(longSide * h / w + 0.5))
	end
	return math.max(1, math.floor(longSide * w / h + 0.5)), longSide
end

function net.makeXform(box : SquareMinimapBox, orient : SquareMinimapOrient, w : integer, h : integer) : SquareMinimapNetXform
	-- Same mapping as geom.worldToFrac (u = (x - minX) / width, swap, flip), times the image size.
	local o : SquareMinimapOrient = orient or { flipX = false, flipY = true, swapXY = false }
	local uMin, uLen = box.minX, box.maxX - box.minX
	local vMin, vLen = box.minY, box.maxY - box.minY
	if o.swapXY then uMin, uLen, vMin, vLen = vMin, vLen, uMin, uLen end
	-- px = size * (s - min) / len, or size * (1 - (s - min) / len) when flipped: px = a + b * s
	local function axis(min : number, len : number, flip : boolean, px : integer) : number, number
		local b = px / len
		if flip then return px + b * min, -b end
		return -b * min, b
	end
	local ax, bx = axis(uMin, uLen, o.flipX, w)
	local ay, by = axis(vMin, vLen, o.flipY, h)
	return { swap = o.swapXY == true, ax = ax, bx = bx, ay = ay, by = by, w = w, h = h }
end

function net.toPx(xf : SquareMinimapNetXform, x : number, y : number) : number, number
	if xf.swap then x, y = y, x end
	return xf.ax + xf.bx * x, xf.ay + xf.by * y
end

function net.vecToPx(xf : SquareMinimapNetXform, dx : number, dy : number) : number, number
	if xf.swap then dx, dy = dy, dx end
	return xf.bx * dx, xf.by * dy
end

local function dist(ax : number, ay : number, bx : number, by : number) : number
	local dx, dy = bx - ax, by - ay
	return math.sqrt(dx * dx + dy * dy)
end

function net.curveSegments(p0x : number, p0y : number, t0x : number, t0y : number,
		p1x : number, p1y : number, t1x : number, t1y : number) : integer
	-- Bezier control points of the Hermite curve: b1 = p0 + t0 / 3, b2 = p1 - t1 / 3.
	local b1x, b1y = p0x + t0x / 3, p0y + t0y / 3
	local b2x, b2y = p1x - t1x / 3, p1y - t1y / 3
	local cx, cy = p1x - p0x, p1y - p0y
	local len = math.sqrt(cx * cx + cy * cy)
	local d1, d2 : number, number
	if len < 1e-9 then
		d1, d2 = dist(p0x, p0y, b1x, b1y), dist(p0x, p0y, b2x, b2y)
	else
		d1 = math.abs((b1x - p0x) * cy - (b1y - p0y) * cx) / len
		d2 = math.abs((b2x - p0x) * cy - (b2y - p0y) * cx) / len
	end
	if math.max(d1, d2) < net.FLAT_PX then return 1 end
	local poly = dist(p0x, p0y, b1x, b1y) + dist(b1x, b1y, b2x, b2y) + dist(b2x, b2y, p1x, p1y)
	local n = math.ceil(poly / net.SEG_PX)
	if n < 2 then return 2 end
	if n > net.MAX_SEGS then return net.MAX_SEGS end
	return n
end

function net.hermitePolyline(xf : SquareMinimapNetXform, p0x : number, p0y : number, t0x : number, t0y : number,
		p1x : number, p1y : number, t1x : number, t1y : number) : {integer}
	local ax, ay = net.toPx(xf, p0x, p0y)
	local bx, by = net.toPx(xf, p1x, p1y)
	local tax, tay = net.vecToPx(xf, t0x, t0y)
	local tbx, tby = net.vecToPx(xf, t1x, t1y)
	local n = net.curveSegments(ax, ay, tax, tay, bx, by, tbx, tby)
	local pts : {integer} = {}
	local lx, ly : integer, integer = nil, nil
	for i = 0, n do
		local t = i / n
		local t2 = t * t
		local t3 = t2 * t
		local h00 = 2 * t3 - 3 * t2 + 1
		local h10 = t3 - 2 * t2 + t
		local h01 = -2 * t3 + 3 * t2
		local h11 = t3 - t2
		local x = math.floor(h00 * ax + h10 * tax + h01 * bx + h11 * tbx)
		local y = math.floor(h00 * ay + h10 * tay + h01 * by + h11 * tby)
		if x ~= lx or y ~= ly then
			pts[#pts + 1] = x
			pts[#pts + 1] = y
			lx, ly = x, y
		end
	end
	return pts
end

function net.rectFromBounds(xf : SquareMinimapNetXform, minX : number, minY : number, maxX : number, maxY : number) : integer, integer, integer, integer
	local ax, ay = net.toPx(xf, minX, minY)
	local bx, by = net.toPx(xf, maxX, maxY)
	if bx < ax then ax, bx = bx, ax end
	if by < ay then ay, by = by, ay end
	return math.floor(ax), math.floor(ay), math.floor(bx), math.floor(by)
end

function net.newGrid(w : integer, h : integer) : SquareMinimapNetGrid
	local cells : {number} = {}
	for i = 1, w * h do cells[i] = 0 end
	local dirty : {boolean} = {}
	for b = 1, (h + net.BAND_ROWS - 1) // net.BAND_ROWS do dirty[b] = false end
	return { w = w, h = h, cells = cells, dirty = dirty }
end

--- Marks the bands of grid rows y0..y1 (clamped to the image) as changed since their last encode.
local function markRows(g : SquareMinimapNetGrid, y0 : integer, y1 : integer)
	if y0 < 0 then y0 = 0 end
	if y1 > g.h - 1 then y1 = g.h - 1 end
	if y1 < y0 then return end
	local dirty = g.dirty
	if dirty == nil then return end
	local band = net.BAND_ROWS
	for b = y0 // band + 1, y1 // band + 1 do dirty[b] = true end
end

--- Adds (delta 1) or removes (delta -1) one unit at a pixel; out-of-image pixels are skipped.
--- A layer count never goes below 0 or above LAYER_MAX (it would spill into another layer).
local floor = math.floor
local LAYER_MAX <const> = 4095 -- net.LAYER_MAX
local function plot(g : SquareMinimapNetGrid, x : integer, y : integer, unit : number, delta : integer) : integer
	if x < 0 or y < 0 or x >= g.w or y >= g.h then return 0 end
	local cells = g.cells
	local i = y * g.w + x + 1
	local c = cells[i]
	local n = floor(c / unit) % 4096
	if delta > 0 then
		if n >= LAYER_MAX then return 0 end
		cells[i] = c + unit
	else
		if n <= 0 then return 0 end
		cells[i] = c - unit
	end
	return 1
end

-- No closure per call (the earlier put() closure was ~330 bytes of garbage per drawn item).
function net.drawPolyline(g : SquareMinimapNetGrid, pts : {integer}, unit : number, delta : integer, dashed : boolean) : integer
	local n = #pts
	if n < 2 then return 0 end
	local dashOn, dashPeriod = net.DASH_ON, net.DASH_PERIOD
	local touched = 0
	local step = 1 -- the first point is drawn below (step 0 is always "on")
	touched = plot(g, pts[1], pts[2], unit, delta)
	local ymin, ymax = pts[2], pts[2]
	for i = 3, n - 1, 2 do
		-- Bresenham from the previous point; its first pixel was drawn by the previous segment.
		local x0, y0 = pts[i - 2], pts[i - 1]
		local x1, y1 = pts[i], pts[i + 1]
		if y1 < ymin then ymin = y1 end
		if y1 > ymax then ymax = y1 end
		local dx = math.abs(x1 - x0)
		local dy = -math.abs(y1 - y0)
		local sx = x0 < x1 and 1 or -1
		local sy = y0 < y1 and 1 or -1
		local err = dx + dy
		local x, y = x0, y0
		while x ~= x1 or y ~= y1 do
			local e2 = 2 * err
			if e2 >= dy then err = err + dy; x = x + sx end
			if e2 <= dx then err = err + dx; y = y + sy end
			if not dashed or step % dashPeriod < dashOn then
				touched = touched + plot(g, x, y, unit, delta)
			end
			step = step + 1
		end
	end
	if touched > 0 then markRows(g, ymin, ymax) end
	return touched
end

function net.fillRect(g : SquareMinimapNetGrid, x0 : integer, y0 : integer, x1 : integer, y1 : integer, unit : number, delta : integer) : integer
	local touched = 0
	for y = math.max(0, y0), math.min(g.h - 1, y1) do
		for x = math.max(0, x0), math.min(g.w - 1, x1) do
			touched = touched + plot(g, x, y, unit, delta)
		end
	end
	if touched > 0 then markRows(g, y0, y1) end
	return touched
end

function net.drawItem(g : SquareMinimapNetGrid, it : SquareMinimapNetItem, delta : integer) : integer
	if it == nil then return 0 end
	local unit = UNITS[it.kind]
	if unit == nil then return 0 end
	if it.pts ~= nil then
		return net.drawPolyline(g, it.pts, unit, delta, it.dashed)
	end
	if it.x0 ~= nil then
		return net.fillRect(g, it.x0, it.y0, it.x1, it.y1, unit, delta)
	end
	return 0
end

function net.layerOf(cell : number) : integer
	if cell >= net.UNIT_TRACK then return 3 end
	if cell >= net.UNIT_STREET then return 2 end
	if cell >= net.UNIT_TOWN then return 1 end
	return 0
end

--- Resumable walk over an engine map {key: {id, ...}} (node -> edges, town -> buildings): ids
--- already in the cache are marked seen (stamp); unknown ids are appended to added (once each,
--- kind in the parallel addKind). An id listed twice (an edge at both its nodes) counts once.
--- Replaces the earlier flatten-to-list + diff: no per-scan list or hint table of every id.
function net.newFlatten(map : {any : {integer}}, kind : integer, stamp : integer, added : {integer},
		addKind : {integer}, addedSet : {integer : boolean}) : SquareMinimapNetFlatten
	return { map = map, kind = kind, stamp = stamp, added = added, addKind = addKind, addedSet = addedSet, j = 1, done = false }
end

--- Up to maxItems ids (and map keys) per call; true when the map is done. Resumes with
--- next(map, key), valid because the map is never modified (it is the engine's returned copy).
function net.flattenStep(f : SquareMinimapNetFlatten, cache : {integer : SquareMinimapNetItem}, maxItems : integer) : boolean
	if f.done then return true end
	local map, stamp, kind = f.map, f.stamp, f.kind
	local added, addKind, addedSet = f.added, f.addKind, f.addedSet
	local n = 0
	while n < maxItems do
		local arr = f.arr
		if arr == nil then
			local k, v = next(map, f.key)
			if k == nil then
				f.done = true
				f.map = nil
				return true
			end
			f.key, f.arr, f.j = k, v, 1
			arr = v
			n = n + 1
		end
		local j, cnt = f.j, #arr
		while j <= cnt and n < maxItems do
			local id = arr[j]
			local it = cache[id]
			if it ~= nil then
				it.seen = stamp
			elseif not addedSet[id] then
				addedSet[id] = true
				added[#added + 1] = id
				addKind[#addKind + 1] = kind
			end
			j = j + 1
			n = n + 1
		end
		f.j = j
		if j > cnt then f.arr = nil end
	end
	return false
end

--- Resumable sweep of a cache for items not seen in this scan (removed). Valid while no keys are
--- added to the cache between steps (the scheduler adds only after its sweeps).
function net.newSweep(stamp : integer, removed : {integer}) : SquareMinimapNetSweep
	return { stamp = stamp, removed = removed, done = false }
end

function net.sweepStep(sw : SquareMinimapNetSweep, cache : {integer : SquareMinimapNetItem}, maxItems : integer) : boolean
	if sw.done then return true end
	local stamp, removed = sw.stamp, sw.removed
	local key = sw.key
	for _ = 1, maxItems do
		local k, it = next(cache, key)
		if k == nil then
			sw.done = true
			return true
		end
		if it.seen ~= stamp then removed[#removed + 1] = k end
		key = k
	end
	sw.key = key
	return false
end

local ORDERS : {string : {integer}} = {
	-- position of R, G, B, A in each 4-byte pixel
	RGBA = { 1, 2, 3, 4 },
	BGRA = { 3, 2, 1, 4 },
	ARGB = { 2, 3, 4, 1 },
	ABGR = { 4, 3, 2, 1 },
}

function net.orderColor(rgba : {integer}, order : string) : {integer}
	local pos = ORDERS[order] or ORDERS.RGBA
	local out : {integer} = { 0, 0, 0, 0 }
	for c = 1, 4 do out[pos[c]] = rgba[c] end
	return out
end

function net.makePalette(layers : {{integer}}, order : string) : {{integer}}
	-- layers[1..4] = RGBA of none, town, street, track -> palette[1..4] in the image's byte order
	local p : {{integer}} = {}
	for i = 1, 4 do p[i] = net.orderColor(layers[i], order) end
	return p
end

-- RGBA per layer (index 1..4 = none, town buildings, streets, tracks). The grid stores layer counts,
-- not colours, so switching palettes only re-encodes (encodeRows); nothing is re-read or re-drawn.
net.COLORS_NORMAL = {
	{ 0, 0, 0, 0 },
	{ 150, 140, 128, 170 }, -- town buildings: muted grey-brown, translucent
	{ 236, 236, 228, 235 }, -- streets: near white
	{ 36, 36, 44, 255 },    -- tracks: near black
}
-- High visibility: saturated and fully opaque, chosen to stand out on brown, green and blue terrain
-- (and from each other): orange buildings, yellow streets, magenta tracks (tunnels stay dashed).
net.COLORS_HIVIS = {
	{ 0, 0, 0, 0 },
	{ 255, 120, 0, 255 },   -- town buildings: orange
	{ 255, 236, 0, 255 },   -- streets: yellow
	{ 255, 0, 200, 255 },   -- tracks: magenta
}

function net.paletteFor(hiVis : boolean, order : string) : {{integer}}
	return net.makePalette(hiVis and net.COLORS_HIVIS or net.COLORS_NORMAL, order)
end

function net.recolorAction(phase : string, hasImage : boolean) : string
	-- What a palette switch does to the scheduler (minimap_hud.script.tl netStep):
	--   "none":    no picture yet and no pass running into one: the next encode uses the new palette anyway
	--   "encode":  idle with a picture: start an encode-only pass now (no list, no read)
	--   "restart": mid-encode or waiting for the hand-off: encode again (all rows) with the new palette
	--   "dirty":   mid-scan (list/flatten/sweep/remove/read): mark dirty, the pass encodes when it ends
	if phase == "encode" or phase == "handoff" then return "restart" end
	if phase == nil or phase == "idle" then
		if hasImage then return "encode" end
		return "none"
	end
	return "dirty"
end

function net.parkExpired(parkedSinceMs : number, nowMs : number, seconds : number) : boolean
	-- A layer switched off keeps its caches; true once they have been unused for `seconds`.
	if parkedSinceMs == nil or nowMs == nil then return false end
	return nowMs - parkedSinceMs >= seconds * 1000
end

function net.expectedLength(w : integer, h : integer) : integer
	return w * h * 4
end

-- Colour components in locals and the empty layer tested first (most pixels): no table read per
-- byte. Same bytes as the straightforward version (tests/square_better_minimap/test_net_golden.lua).
function net.encodeRows(g : SquareMinimapNetGrid, out : {integer}, row0 : integer, row1 : integer,
		palette : {{integer}}, flipRows : boolean)
	local w, h, cells = g.w, g.h, g.cells
	local p0, p1, p2, p3 = palette[1], palette[2], palette[3], palette[4]
	local a1, a2, a3, a4 = p0[1], p0[2], p0[3], p0[4]
	local b1, b2, b3, b4 = p1[1], p1[2], p1[3], p1[4]
	local c1, c2, c3, c4 = p2[1], p2[2], p2[3], p2[4]
	local d1, d2, d3, d4 = p3[1], p3[2], p3[3], p3[4]
	local street, track = net.UNIT_STREET, net.UNIT_TRACK
	for row = row0, math.min(row1, h) - 1 do
		local src = flipRows and (h - 1 - row) or row
		local base = src * w
		local o = row * w * 4
		for x = 1, w do
			local c = cells[base + x]
			if c < 1 then
				out[o + 1] = a1; out[o + 2] = a2; out[o + 3] = a3; out[o + 4] = a4
			elseif c < street then
				out[o + 1] = b1; out[o + 2] = b2; out[o + 3] = b3; out[o + 4] = b4
			elseif c < track then
				out[o + 1] = c1; out[o + 2] = c2; out[o + 3] = c3; out[o + 4] = c4
			else
				out[o + 1] = d1; out[o + 2] = d2; out[o + 3] = d3; out[o + 4] = d4
			end
			o = o + 4
		end
	end
end

function net.bandCount(g : SquareMinimapNetGrid) : integer
	return (g.h + net.BAND_ROWS - 1) // net.BAND_ROWS
end

--- Encodes grid band b (1-based, BAND_ROWS grid rows) into out when `all` or the band changed
--- since its last encode; clears its flag. Returns true if it encoded. The rows land where
--- encodeRows puts them (flipped or not), so a buffer kept from the previous image only needs its
--- changed bands rewritten to equal a full encode.
function net.encodeBand(g : SquareMinimapNetGrid, out : {integer}, b : integer, palette : {{integer}}, flipRows : boolean, all : boolean) : boolean
	local dirty = g.dirty
	if not all and dirty ~= nil and not dirty[b] then return false end
	local gy0 = (b - 1) * net.BAND_ROWS
	local gy1 = math.min(g.h, gy0 + net.BAND_ROWS)
	if flipRows then
		net.encodeRows(g, out, g.h - gy1, g.h - gy0, palette, true)
	else
		net.encodeRows(g, out, gy0, gy1, palette, false)
	end
	if dirty ~= nil then dirty[b] = false end
	return true
end

-- STRIPS: the picture is shown as horizontal strips of STRIP_BANDS bands (STRIP_BANDS * BAND_ROWS
-- grid rows; the last strip may be shorter), each its own ImageView with its own buffer, so an
-- update hands only the changed strips to the engine (one hand-off of w * rows * 4 bytes each,
-- instead of the whole image). Strip 1 is the top of the picture. Each strip's buffer is a small
-- image of its own: with flipRows its rows are bottom-up WITHIN the strip (the engine draws every
-- ImageView's first row at its bottom). So the full flipped image is the strips' buffers
-- concatenated last strip first, the unflipped one first strip first (test_net.lua).

function net.stripRows() : integer
	return net.STRIP_BANDS * net.BAND_ROWS
end

function net.stripCount(h : integer) : integer
	local rows = net.stripRows()
	return (h + rows - 1) // rows
end

--- Grid rows r0 .. r1 - 1 (0-based, top-down) of strip s (1-based) in an image h rows high.
function net.stripRange(h : integer, s : integer) : integer, integer
	local rows = net.stripRows()
	local r0 = (s - 1) * rows
	return r0, math.min(h, r0 + rows)
end

function net.stripOfBand(b : integer) : integer
	return (b - 1) // net.STRIP_BANDS + 1
end

--- True when a band of strip s changed since its last encode.
function net.stripDirty(g : SquareMinimapNetGrid, s : integer) : boolean
	local dirty = g.dirty
	if dirty == nil then return false end
	local b0 = (s - 1) * net.STRIP_BANDS + 1
	local b1 = math.min(#dirty, s * net.STRIP_BANDS)
	for b = b0, b1 do
		if dirty[b] then return true end
	end
	return false
end

--- Grid rows gy0 .. gy1 - 1 (inside strip rows s0 .. s1 - 1) into that strip's buffer (s1 - s0 rows
--- of w pixels, 4 bytes each); flipRows writes the strip's rows bottom-up. Same inner loop as
--- encodeRows, so the bytes per pixel are identical.
function net.encodeStripRows(g : SquareMinimapNetGrid, out : {integer}, s0 : integer, s1 : integer,
		gy0 : integer, gy1 : integer, palette : {{integer}}, flipRows : boolean)
	local w, cells = g.w, g.cells
	local p0, p1, p2, p3 = palette[1], palette[2], palette[3], palette[4]
	local a1, a2, a3, a4 = p0[1], p0[2], p0[3], p0[4]
	local b1, b2, b3, b4 = p1[1], p1[2], p1[3], p1[4]
	local c1, c2, c3, c4 = p2[1], p2[2], p2[3], p2[4]
	local d1, d2, d3, d4 = p3[1], p3[2], p3[3], p3[4]
	local street, track = net.UNIT_STREET, net.UNIT_TRACK
	if gy0 < s0 then gy0 = s0 end
	if gy1 > s1 then gy1 = s1 end
	for gy = gy0, gy1 - 1 do
		local row = flipRows and (s1 - 1 - gy) or (gy - s0)
		local base = gy * w
		local o = row * w * 4
		for x = 1, w do
			local c = cells[base + x]
			if c < 1 then
				out[o + 1] = a1; out[o + 2] = a2; out[o + 3] = a3; out[o + 4] = a4
			elseif c < street then
				out[o + 1] = b1; out[o + 2] = b2; out[o + 3] = b3; out[o + 4] = b4
			elseif c < track then
				out[o + 1] = c1; out[o + 2] = c2; out[o + 3] = c3; out[o + 4] = c4
			else
				out[o + 1] = d1; out[o + 2] = d2; out[o + 3] = d3; out[o + 4] = d4
			end
			o = o + 4
		end
	end
end

--- encodeBand for strips: grid band b into its strip's buffer `out` when `all` or the band changed
--- since its last encode; clears its flag. True if it encoded.
function net.encodeStripBand(g : SquareMinimapNetGrid, out : {integer}, b : integer, palette : {{integer}}, flipRows : boolean, all : boolean) : boolean
	local dirty = g.dirty
	if not all and dirty ~= nil and not dirty[b] then return false end
	local s0, s1 = net.stripRange(g.h, net.stripOfBand(b))
	local gy0 = (b - 1) * net.BAND_ROWS
	net.encodeStripRows(g, out, s0, s1, gy0, math.min(g.h, gy0 + net.BAND_ROWS), palette, flipRows)
	if dirty ~= nil then dirty[b] = false end
	return true
end

--- Placement of strip rows r0 .. r1 - 1 of an image H rows high in a picture h UI px high (the
--- image is stretched): top and height in whole UI px. Rounded edges, so the strips tile the
--- picture without gaps or overlaps; a seam sits at most 0.5 px from its exact position.
function net.stripPlacement(r0 : integer, r1 : integer, imageH : integer, h : integer) : integer, integer
	local top = math.floor(r0 * h / imageH + 0.5)
	local bottom = math.floor(r1 * h / imageH + 0.5)
	return top, bottom - top
end

--- localKey of one strip's node: changes with its image version, the picture size and the mode.
function net.stripKey(s : integer, version : integer, w : integer, h : integer, mode : string) : string
	return string.format("minimap_net_s%d_v%d_%dx%d_%s", s or 0, version or 0, w or 0, h or 0, mode or "none")
end

function net.paintCalibration(out : {integer}, w : integer, h : integer, order : string, flipRows : boolean, refSide? : integer) : integer
	-- Four squares in the top-left corner, left to right: red, green, blue, 50% white (all opaque
	-- but the last). Rows go through the same flip as encodeRows, so with the right constants the
	-- patch shows at the top-left in this order. Returns the square size (0 = image too small).
	-- refSide: the square size follows this side (the whole picture's) instead of min(w, h) (a strip).
	local s = math.max(4, math.floor((refSide or math.min(w, h)) / 24))
	local gap = math.max(1, s // 4)
	if 4 * (s + gap) + gap > w or s + 2 * gap > h then return 0 end
	local colors : {{integer}} = {
		{ 255, 0, 0, 255 }, { 0, 255, 0, 255 }, { 0, 0, 255, 255 }, { 255, 255, 255, 128 },
	}
	for k = 1, 4 do
		local col = net.orderColor(colors[k], order)
		local left = gap + (k - 1) * (s + gap)
		for y = gap, gap + s - 1 do
			local row = flipRows and (h - 1 - y) or y
			for x = left, left + s - 1 do
				local o = (row * w + x) * 4
				out[o + 1] = col[1]
				out[o + 2] = col[2]
				out[o + 3] = col[3]
				out[o + 4] = col[4]
			end
		end
	end
	return s
end

function net.scanInterval(listMs : number, minSeconds : number, maxSeconds : number, factor : number) : number
	-- Seconds until the next re-list: at least minSeconds, longer when listing is expensive (the list
	-- calls are single engine calls that can't be sliced), at most maxSeconds.
	local s = (listMs or 0) * factor / 1000
	if s < minSeconds then return minSeconds end
	if s > maxSeconds then return maxSeconds end
	return s
end

function net.nextScanSeconds(prev : number, base : number, changed : boolean, cap : number) : number
	-- Back-off: a scan that found nothing doubles the wait (up to cap, never below base, the
	-- list-time based interval); any change goes back to base.
	if changed or prev == nil then return base end
	local s = prev * 2
	if s > cap then s = cap end
	if s < base then s = base end
	return s
end

return net
