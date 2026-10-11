-- DEV ONLY (never upload): Roundabouts Showcase, layout patterns, packed as tightly as possible.
-- Pure Lua (no api.*).
--
-- items = { { fp = footprint (sc_footprint), entry = "ring", entryIndex = 1, symbol = "R",
--             colour = "ring:Grass", side = 1 | 2, mirror = { fp, combo } | nil, combo } }
-- opts  = { pattern, gap, rotation, seed, cx, cy, maxRadius, cap }
-- layout.run(items, opts) -> placements, dropped
--   placement = { item, mirrored (bool), fp, x, y (world bbox centre), rot (deg, [0, 360)),
--                 ox, oy (world construction origin) }
--   dropped   = { { item, reason } }
--
-- Collision model: every footprint box is grown by gap / 2 on each side and turned by its rotation;
-- two grown boxes never overlap (exact separating-axis test, layout.overlaps). A spatial hash of the
-- placed boxes (Packer) answers "does this box fit?".
--   * Circle-ish patterns (kaleidoscope, mandala, spiral) give each item an ideal direction from the
--     centre and take the NEAREST free spot along that ray (coarse steps, then bisection to
--     PRECISION metres), so they keep their look but pack densely.
--   * The kaleidoscope places a whole orbit at once (n rotations + n mirror images, layout.orbit):
--     the item goes to the nearest point of its wedge where every copy fits, so the symmetry is exact.
--   * Rectangle patterns (grid, mosaic, size gradient, checkerboard) use skyline packing with each
--     item's own size.
--   * Scatter: seeded random spots in a disc sized for ~45 % fill, else the nearest free spot.
-- The rotation setting "pattern" also lets the packer try each item turned by 90 degrees (a box
-- turned by 180 has the same outline), whichever fits closer.
-- Rotations: multiples of 90 use exact cos / sin; every -0 becomes +0 (docs/findings.md
-- "Negative zero in construction geometry").

local rngMod = ug_require "square_roundabouts_showcase::/showcase/sc_rng.lua"
local shapeMod = ug_require "square_roundabouts_showcase::/showcase/sc_shape.lua"

local layout = {}

layout.PATTERNS = { "grid", "mosaic", "kaleido4", "kaleido8", "mandala", "spiral", "gradient", "checker", "scatter" }
-- the rotation of each pattern for the rotation setting "pattern"
layout.NATURAL_ROTATION = {
	grid = "fixed", mosaic = "fixed", gradient = "fixed", checker = "fixed",
	kaleido4 = "face", kaleido8 = "face", mandala = "face", spiral = "face", scatter = "random",
}
layout.GOLDEN_ANGLE = 137.50776405003785
layout.EPS = 1e-6
-- nearest-free search: final precision (m) and the wedge angles tried per kaleidoscope orbit
layout.PRECISION = 0.5
layout.WEDGE_ANGLES = 6
-- hash cell size (m)
layout.CELL = 64
-- scatter: disc sized for this fill (grown box area / disc area)
layout.SCATTER_FILL = 0.45
-- fill: at most this many items laid out (repeats included)
layout.MAX_ITEMS = 20000
-- road-shape collisions (sc_shape) up to this gap; larger gaps use the boxes alone
layout.SHAPE_MAX_GAP = 40
-- with shapes: wedge rays per kaleidoscope orbit, rotations tried per item (multiples of 90)
layout.SHAPE_WEDGE_ANGLES = 12
layout.SHAPE_ROTATIONS = 2

-- Geometry helpers -------------------------------------------------------------------------------

local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
layout.finite = finite

--- +0 for any zero (a -0 becomes +0); other values unchanged.
function layout.plusZero(v)
	if v == 0 then return 0 end
	return v
end

--- deg in [0, 360), rounded to 1e-6 degrees, never -0.
function layout.normRot(deg)
	local d = deg % 360
	d = math.floor(d * 1e6 + 0.5) / 1e6
	if d >= 360 then d = d - 360 end
	return layout.plusZero(d)
end

--- cos, sin of deg degrees, exact for multiples of 90, never -0.
function layout.cosSin(deg)
	local d = layout.normRot(deg)
	if d == 0 then return 1, 0 end
	if d == 90 then return 0, 1 end
	if d == 180 then return -1, 0 end
	if d == 270 then return 0, -1 end
	local a = math.rad(d)
	return layout.plusZero(math.cos(a)), layout.plusZero(math.sin(a))
end

--- Half extents of the axis-aligned box around a w x h box rotated by rot.
function layout.rotatedHalf(w, h, rot)
	local c, s = layout.cosSin(rot)
	c, s = math.abs(c), math.abs(s)
	return (c * w + s * h) / 2, (s * w + c * h) / 2
end

--- World origin of a construction whose bbox centre (fp.cx, fp.cy) is placed at (x, y), rotated.
function layout.origin(fp, x, y, rot)
	local c, s = layout.cosSin(rot)
	return layout.plusZero(x - (c * fp.cx - s * fp.cy)), layout.plusZero(y - (s * fp.cx + c * fp.cy))
end

--- A placement's construction origin for its current x, y, rot (cached on it).
function layout.originOf(p)
	if p._ox and p._kx == p.x and p._ky == p.y and p._kr == p.rot then return p._ox, p._oy end
	p._ox, p._oy = layout.origin(p.fp, p.x, p.y, p.rot)
	p._kx, p._ky, p._kr = p.x, p.y, p.rot
	return p._ox, p._oy
end

--- Do the oriented boxes of two placements, each grown by gap / 2, overlap (strictly)?
function layout.overlaps(a, b, gap)
	local g = (gap or 0) / 2
	local ca, sa = layout.cosSin(a.rot)
	local cb, sb = layout.cosSin(b.rot)
	local ahw, ahh = a.fp.w / 2 + g, a.fp.h / 2 + g
	local bhw, bhh = b.fp.w / 2 + g, b.fp.h / 2 + g
	local dx, dy = b.x - a.x, b.y - a.y
	-- quick reject on the circumscribed circles
	local rr = math.sqrt(ahw * ahw + ahh * ahh) + math.sqrt(bhw * bhw + bhh * bhh)
	if dx * dx + dy * dy >= rr * rr then return false end
	local axes = { { ca, sa }, { -sa, ca }, { cb, sb }, { -sb, cb } }
	for _, ax in ipairs(axes) do
		local d = math.abs(dx * ax[1] + dy * ax[2])
		local ra = math.abs(ca * ax[1] + sa * ax[2]) * ahw + math.abs(-sa * ax[1] + ca * ax[2]) * ahh
		local rb = math.abs(cb * ax[1] + sb * ax[2]) * bhw + math.abs(-sb * ax[1] + cb * ax[2]) * bhh
		if d >= ra + rb - layout.EPS then return false end
	end
	return true
end

--- Axis-aligned bounds of a placement's grown box.
local function bounds(p, gap)
	local hw, hh = layout.rotatedHalf(p.fp.w + gap, p.fp.h + gap, p.rot)
	return p.x - hw, p.x + hw, p.y - hh, p.y + hh
end

-- Packer: spatial hash of placed boxes ------------------------------------------------------------

local Packer = {}
Packer.__index = Packer
-- query stamps are stored on the placements, which several packers share (layout, validate, retries):
-- one counter for all packers, so a stamp left by another packer never matches
local STAMP = { n = 0 }

--- A packer; shapeD = the clearance field range for road-shape collisions (nil: boxes only).
function layout.newPacker(gap, cell, shapeD)
	return setmetatable({ gap = gap or 0, cell = cell or layout.CELL, cells = {}, list = {}, stamp = 0, tests = 0,
		shapeD = shapeD }, Packer)
end

--- Do two placements collide? Boxes (grown by gap / 2) first; when both have road shapes and the
-- packer uses them, overlapping boxes collide only if the road shapes do.
function Packer:clash(p, q)
	if not layout.overlaps(p, q, self.gap) then return false end
	if not (self.shapeD and p.fp.shape and q.fp.shape) then return true end
	local pox, poy = layout.originOf(p)
	local qox, qoy = layout.originOf(q)
	return shapeMod.collideRaw(p.fp.shape, p.rot, pox, poy, q.fp.shape, q.rot, qox, qoy, self.gap, self.shapeD, layout.cosSin)
end

function Packer:range(p)
	local x0, x1, y0, y1 = bounds(p, self.gap)
	local s = self.cell
	return math.floor(x0 / s), math.floor(x1 / s), math.floor(y0 / s), math.floor(y1 / s)
end

function Packer:add(p)
	local i0, i1, j0, j1 = self:range(p)
	for i = i0, i1 do
		local col = self.cells[i]
		if not col then col = {} self.cells[i] = col end
		for j = j0, j1 do
			local list = col[j]
			if not list then list = {} col[j] = list end
			list[#list + 1] = p
		end
	end
	self.list[#self.list + 1] = p
end

--- Does p fit (no overlap with any placed box)?
function Packer:fits(p)
	if not (finite(p.x) and finite(p.y)) then return false end
	-- the last placed box that blocked a candidate usually blocks the next one (same ray): try it first
	local w = self.witness
	if w and self:clash(p, w) then return false end
	STAMP.n = STAMP.n + 1
	local st = STAMP.n
	local i0, i1, j0, j1 = self:range(p)
	for i = i0, i1 do
		local col = self.cells[i]
		if col then
			for j = j0, j1 do
				for _, q in ipairs(col[j] or {}) do
					if q._st ~= st then
						q._st = st
						self.tests = self.tests + 1
						if q ~= w and self:clash(p, q) then
							self.witness = q
							return false
						end
					end
				end
			end
		end
	end
	return true
end

--- Do all of the copies fit, against the placed boxes and against each other?
function Packer:fitsAll(copies)
	for _, c in ipairs(copies) do if not self:fits(c) then return false end end
	for i = 1, #copies do
		for j = i + 1, #copies do
			if self:clash(copies[i], copies[j]) then return false end
		end
	end
	return true
end

--- The smallest t in [t0, tMax] (to PRECISION) whose make(t) fits, searching outward in steps:
-- returns t, candidate or nil. fits(candidate) decides.
function layout.searchRay(make, fits, t0, tMax, step)
	local t, bad = t0, nil
	while t <= tMax do
		local c = make(t)
		if fits(c) then
			if not bad then return t, c end
			local lo, hi, best = bad, t, c
			while hi - lo > layout.PRECISION do
				local mid = (lo + hi) / 2
				local cm = make(mid)
				if fits(cm) then hi, best = mid, cm else lo = mid end
			end
			return hi, best
		end
		bad = t
		t = t + step
	end
	return nil
end

-- Rotation choice ---------------------------------------------------------------------------------

--- The effective rotation mode of a pattern ("fixed" | "face" | "random90" | "random").
function layout.rotationMode(pattern, setting)
	if setting == nil or setting == "pattern" then return layout.NATURAL_ROTATION[pattern] or "fixed" end
	return setting
end

--- A rotation chosen before the position is known (face: 0, set later).
function layout.preRotation(mode, r)
	if mode == "random90" then return r:int(0, 3) * 90 end
	if mode == "random" then return math.floor(r:next() * 3600) / 10 end
	return 0
end

--- Facing the centre: the construction's local +y points away from (0, 0) along angle deg.
function layout.faceRot(deg) return deg - 90 end

local function atan2(y, x)
	if math.atan2 then return math.atan2(y, x) end
	return math.atan(y, x)
end

function layout.faceAngle(x, y)
	if x == 0 and y == 0 then return 0 end
	return layout.faceRot(math.deg(atan2(y, x)))
end

--- Rotations to try for an item placed along direction deg: the mode's rotation, plus the same
-- turned by 90 when the setting is "pattern" (a box turned by 180 has the same outline).
local function rotationsFor(item, mode, deg, turns)
	local base = mode == "face" and layout.faceRot(deg) or item.rot
	if not turns then return { base } end
	-- a box turned by 180 has the same outline, a road shape does not
	if turns == "shape" then
		local out = {}
		for k = 0, layout.SHAPE_ROTATIONS - 1 do out[#out + 1] = base + k * 90 end
		return out
	end
	return { base, base + 90 }
end

-- Item helpers ------------------------------------------------------------------------------------

local function sizeOf(item) return item.fp.w * item.fp.h end

local function sortBySize(list, desc)
	table.sort(list, function(a, b)
		local sa, sb = sizeOf(a), sizeOf(b)
		if sa ~= sb then if desc then return sa > sb end return sa < sb end
		return a.order < b.order
	end)
	return list
end

local function copyList(items)
	local out = {}
	for i, it in ipairs(items) do
		it.order = it.order or i
		it.outside = nil
		out[i] = it
	end
	return out
end

local function place(item, x, y, rot, mirrored)
	local fp = mirrored and item.mirror and item.mirror.fp or item.fp
	return { item = item, mirrored = mirrored and true or false, fp = fp, x = x, y = y, rot = rot or 0 }
end

local function stepOf(fp)
	-- road shapes interlock: finer steps find the pockets between arms
	if fp.shape then return math.max(4, math.min(40, math.min(fp.w, fp.h) / 6)) end
	return math.max(2, math.min(fp.w, fp.h) / 3)
end

--- The nearest free spot along the ray at deg degrees from (x0, y0), trying the item's rotations
-- and, with spread, the rays at deg +- spread / 2 and +- spread (the pattern still reads, the item
-- slips into a nearby hole). Returns the placement or nil.
local function nearestOnRay(packer, item, deg, mode, turns, tMax, x0, y0, t0, spread)
	local best, bestT = nil, math.huge
	local offsets = spread and { 0, -spread / 2, spread / 2 } or { 0 }
	for _, off in ipairs(offsets) do
		local d = deg + off
		local a = math.rad(d)
		local ux, uy = math.cos(a), math.sin(a)
		for _, rot in ipairs(rotationsFor(item, mode, d, turns)) do
			local t, c = layout.searchRay(function(tt)
				return place(item, (x0 or 0) + tt * ux, (y0 or 0) + tt * uy, rot)
			end, function(c) return packer:fits(c) end, t0 or 0, math.min(tMax, bestT), stepOf(item.fp))
			if t and t < bestT then best, bestT = c, t end
		end
	end
	return best
end

-- Rectangle patterns: skyline packing ---------------------------------------------------------------

--- Cell options of an item: { {w, h, rot} } (grown boxes' axis-aligned sizes). Face mode: a square
-- (turned by a multiple of 90 later).
local function cellOptions(item, gap, mode, turns)
	if mode == "face" then
		local m = math.max(item.fp.w, item.fp.h) + gap
		return { { m, m, 0 } }
	end
	local out = {}
	local rots = turns and { item.rot, item.rot + 90 } or { item.rot }
	for _, rot in ipairs(rots) do
		local hw, hh = layout.rotatedHalf(item.fp.w + gap, item.fp.h + gap, rot)
		out[#out + 1] = { 2 * hw, 2 * hh, rot }
	end
	return out
end

--- Skyline packing (bottom-left, lowest top first) into width W. Returns cells
-- { {item, x, y (cell centre, y down), w, h, rot} }, used width, used height.
function layout.skyline(list, W, options, tick)
	local sky = { { x = 0, w = W, y = 0 } }
	local out = {}
	local usedW, usedH = 0, 0
	for _, item in ipairs(list) do
		local best
		for _, o in ipairs(options(item)) do
			local cw, ch = o[1], o[2]
			for i = 1, #sky do
				local x = sky[i].x
				if x + cw <= W + 1e-9 or i == 1 then
					-- segments are sorted by x and start at sky[i].x: scan only those under the cell
					local y = 0
					local j = i
					while j <= #sky and sky[j].x < x + cw - 1e-9 do
						if sky[j].y > y then y = sky[j].y end
						j = j + 1
					end
					local top = y + ch
					if not best or top < best.top - 1e-9 or (math.abs(top - best.top) <= 1e-9 and (y < best.y - 1e-9 or (math.abs(y - best.y) <= 1e-9 and x < best.x))) then
						best = { x = x, y = y, top = top, w = cw, h = ch, rot = o[3] }
					end
				end
			end
		end
		out[#out + 1] = { item = item, x = best.x + best.w / 2, y = best.y + best.h / 2, w = best.w, h = best.h, rot = best.rot }
		usedW = math.max(usedW, best.x + best.w)
		usedH = math.max(usedH, best.top)
		-- new skyline: the parts of the old segments outside [x, x + w), plus the new segment
		local x0, x1 = best.x, best.x + best.w
		local nsky = {}
		for _, s in ipairs(sky) do
			if s.x < x0 then nsky[#nsky + 1] = { x = s.x, w = math.min(s.w, x0 - s.x), y = s.y } end
			if s.x + s.w > x1 then
				local nx = math.max(s.x, x1)
				nsky[#nsky + 1] = { x = nx, w = s.x + s.w - nx, y = s.y }
			end
		end
		nsky[#nsky + 1] = { x = x0, w = x1 - x0, y = best.top }
		table.sort(nsky, function(a, b) return a.x < b.x end)
		sky = {}
		for _, s in ipairs(nsky) do
			local last = sky[#sky]
			if last and math.abs(last.y - s.y) < 1e-9 then last.w = last.w + s.w
			elseif s.w > 1e-9 then sky[#sky + 1] = s end
		end
		if tick then tick() end
	end
	return out, usedW, usedH
end

local function packArea(list, gap)
	local area, widest = 0, 0
	for _, it in ipairs(list) do
		area = area + (it.fp.w + gap) * (it.fp.h + gap)
		widest = math.max(widest, math.max(it.fp.w, it.fp.h) + gap)
	end
	return area, widest
end

-- Repeats ("Fill: repeat to fill") ----------------------------------------------------------------

--- The item of a fill sequence: cycle 0 is the item itself, a later cycle a proxy with its own
-- rotation (drawn again for the random modes) that reads everything else from the item.
local function repeatOf(it, cycle, mode, r)
	if cycle == 0 then return it end
	local p = setmetatable({ cycle = cycle, base = it }, { __index = it })
	p.rot = layout.preRotation(mode, r)
	return p
end

--- Rectangle patterns with fill: the list cycled (pattern order kept) up to the count that covers
-- the 2R x 2R square around the max radius disc (the corners are cropped later), at most the cap.
local function expand(list, o, mode, r)
	if not o.fill or #list == 0 then return list end
	local area = packArea(list, o.gap)
	local R = o.maxRadius or 3000
	local want = math.ceil(4 * R * R / (area / #list) * (o.shapes and o.compact and 2.0 or 1.1))
	if o.cap then want = math.min(want, o.cap * 2) end
	want = math.min(want, layout.MAX_ITEMS)
	local out = {}
	for k = 1, math.max(want, #list) do
		local cycle = math.floor((k - 1) / #list)
		out[k] = repeatOf(list[(k - 1) % #list + 1], cycle, mode, r)
	end
	return out
end

--- Skyline-packs a list into a square-ish block (or a W wide one). Returns placements centred on
-- (0, 0), w, h.
local function skylineBlock(list, gap, mode, turns, W, tick)
	local area, widest = packArea(list, gap)
	W = math.max(widest, W or math.sqrt(area))
	local cells, w, h = layout.skyline(list, W, function(it) return cellOptions(it, gap, mode, turns) end, tick)
	local out = {}
	for _, c in ipairs(cells) do out[#out + 1] = place(c.item, c.x - w / 2, h / 2 - c.y, c.rot) end
	return out, w, h
end

local function fillWidth(o) return o.fill and 2 * (o.maxRadius or 3000) or nil end

function layout.grid(items, o, mode, r)
	local list = copyList(items)
	table.sort(list, function(a, b)
		if a.entryIndex ~= b.entryIndex then return (a.entryIndex or 0) < (b.entryIndex or 0) end
		local sa, sb = sizeOf(a), sizeOf(b)
		if sa ~= sb then return sa > sb end
		return a.order < b.order
	end)
	return (skylineBlock(expand(list, o, mode, r), o.gap, mode, o.turns, fillWidth(o), o.tick))
end

function layout.gradient(items, o, mode, r)
	local list = expand(sortBySize(copyList(items), false), o, mode, r)
	if o.fill then
		-- small to large within each repeat would make bands: sort the whole filled list by size
		table.sort(list, function(a, b)
			local sa, sb = sizeOf(a), sizeOf(b)
			if sa ~= sb then return sa < sb end
			return (a.cycle or 0) < (b.cycle or 0)
		end)
	end
	return (skylineBlock(list, o.gap, mode, o.turns, fillWidth(o), o.tick))
end

--- Two alternating groups: the traffic sides of a single entry, else odd / even entries.
function layout.checkerGroups(items)
	local entries, seen = {}, {}
	for _, it in ipairs(items) do
		if not seen[it.entry] then seen[it.entry] = true entries[#entries + 1] = it.entry end
	end
	local A, B = {}, {}
	if #entries <= 1 then
		for _, it in ipairs(items) do
			if it.side == 2 then B[#B + 1] = it else A[#A + 1] = it end
		end
	else
		local pos = {}
		for i, e in ipairs(entries) do pos[e] = i end
		for _, it in ipairs(items) do
			if pos[it.entry] % 2 == 1 then A[#A + 1] = it else B[#B + 1] = it end
		end
	end
	return A, B
end

function layout.checker(items, o, mode, r)
	local A, B = layout.checkerGroups(copyList(items))
	sortBySize(A, true)
	sortBySize(B, true)
	local list = {}
	local ia, ib = 1, 1
	while ia <= #A or ib <= #B do
		if ia <= #A then list[#list + 1] = A[ia] ia = ia + 1 end
		if ib <= #B then list[#list + 1] = B[ib] ib = ib + 1 end
	end
	return (skylineBlock(expand(list, o, mode, r), o.gap, mode, o.turns, fillWidth(o), o.tick))
end

function layout.mosaic(items, o, mode, r)
	local groups, order = {}, {}
	for _, it in ipairs(expand(copyList(items), o, mode, r)) do
		local k = tostring(it.colour or it.entry)
		if not groups[k] then groups[k] = {} order[#order + 1] = k end
		local g = groups[k]
		g[#g + 1] = it
	end
	table.sort(order)
	-- each colour group is one tightly packed patch; the patches are packed with a visible seam
	local blocks = {}
	for _, k in ipairs(order) do
		local ps, w, h = skylineBlock(sortBySize(groups[k], true), o.gap, mode, o.turns, nil, o.tick)
		blocks[#blocks + 1] = { ps = ps, fp = { w = w, h = h }, rot = 0, order = #blocks + 1 }
	end
	local seam = o.gap + 10
	sortBySize(blocks, true)
	local area, widest = 0, 0
	for _, b in ipairs(blocks) do
		area = area + (b.fp.w + seam) * (b.fp.h + seam)
		widest = math.max(widest, b.fp.w + seam)
	end
	local cells, W, H = layout.skyline(blocks, math.max(widest, math.sqrt(area)), function(b)
		return { { b.fp.w + seam, b.fp.h + seam, 0 } }
	end)
	local out = {}
	for _, c in ipairs(cells) do
		local bx, by = c.x - W / 2, H / 2 - c.y
		for _, p in ipairs(c.item.ps) do
			p.x, p.y = p.x + bx, p.y + by
			out[#out + 1] = p
		end
	end
	return out
end

-- Circle patterns: nearest free spot along each item's ray -------------------------------------------

--- Runs placeOne(item, i, cycle) over the list in order; with o.fill it cycles through the list
-- again (repeats) until the cap (constructions, `copies` per call) or until a whole cycle placed
-- nothing. placeOne returns how many constructions it placed.
-- An item that found no spot is retired: the free space only shrinks, so later cycles skip it
-- (this keeps a filled layout fast). i counts every slot, retired ones too, so the pattern's angles
-- stay as in the first cycle.
local function drive(list, o, mode, r, out, copies, placeOne)
	local n = #list
	if n == 0 then return end
	local retired, alive = {}, n
	local i, cycle, placed = 0, 0, 0
	while i < layout.MAX_ITEMS * 4 do
		i = i + 1
		local k = (i - 1) % n + 1
		if k == 1 and i > 1 then
			if not o.fill or placed == 0 or alive == 0 then break end
			cycle = cycle + 1
			placed = 0
		end
		if o.fill and o.cap and #out + copies > o.cap then break end
		if not retired[k] then
			local got = placeOne(repeatOf(list[k], cycle, mode, r), i, cycle)
			if got == 0 then
				retired[k] = true
				alive = alive - 1
			end
			placed = placed + got
			if o.tick then o.tick() end
		end
	end
end

--- Where a repeat's ray search starts: just inside the recent placements (holes deep inside were
-- filled by the earlier cycles), so a filled layout stays fast.
local function frontier(recent, it, cycle)
	if cycle == 0 or #recent == 0 then return 0 end
	local sum = 0
	for _, t in ipairs(recent) do sum = sum + t end
	return math.max(0, sum / #recent - 3 * it.fp.r)
end

local function remember(recent, t)
	recent[#recent + 1] = t
	if #recent > 16 then table.remove(recent, 1) end
end

--- The 2n copies of an orbit: the item at angle a (deg) and distance t with rotation theta, its
-- rotations by 360 / n, and their mirror images (the mirror combo: traffic side flipped;
-- square_roundabouts mirrors x -> -x) at angle -a with rotation 180 - theta.
function layout.orbit(item, n, a, theta, t)
	local out = {}
	local alpha = 360 / n
	for k = 0, n - 1 do
		local ak, am = math.rad(a + k * alpha), math.rad(-a + k * alpha)
		out[#out + 1] = place(item, t * math.cos(ak), t * math.sin(ak), theta + k * alpha, false)
		out[#out + 1] = place(item, t * math.cos(am), t * math.sin(am), 180 - theta + k * alpha, true)
	end
	return out
end

--- Kaleidoscope: dihedral symmetry D_n around (0, 0); each item's orbit goes to the nearest spot in
-- its wedge where every copy fits. Smallest in the centre. Repeats are whole orbits.
function layout.kaleido(items, o, mode, n, packer, r)
	local list = sortBySize(copyList(items), false)
	local out = {}
	if #list == 0 then return out end
	local centre = place(list[1], 0, 0, 0)
	packer:add(centre)
	out[1] = centre
	local rest = {}
	for i = 2, #list do rest[#rest + 1] = list[i] end
	if #rest == 0 and o.fill then rest = { list[1] } end
	local wedge = 180 / n
	local recent = {}
	drive(rest, o, mode, r, out, 2 * n, function(it, _, cycle)
		local reach = math.max(it.fp.r, it.mirror and it.mirror.fp and it.mirror.fp.r or 0)
		local tMax = (o.maxRadius or 1e9) - reach
		-- sorted by size, orbits grow outward: start near the recent ones in every cycle
		local t0 = frontier(recent, it, 1)
		local best, bestT = nil, math.huge
		local rays = o.shapes and layout.SHAPE_WEDGE_ANGLES or layout.WEDGE_ANGLES
		for j = 0, rays - 1 do
			local a = (j + 0.5) / rays * wedge
			for _, theta in ipairs(rotationsFor(it, mode, a, o.turns)) do
				local t, copies = layout.searchRay(function(tt) return layout.orbit(it, n, a, theta, tt) end,
					function(c) return packer:fitsAll(c) end, t0, math.min(tMax, bestT), stepOf(it.fp))
				if t and t < bestT then best, bestT = copies, t end
			end
		end
		if not best then
			it.outside = true
			return 0
		end
		remember(recent, bestT)
		for _, c in ipairs(best) do
			packer:add(c)
			out[#out + 1] = c
		end
		return #best
	end)
	return out
end

--- Mandala: concentric rings of 6, 12, 18 ... items by size; each item at the nearest free spot on
-- its ray (alternate rings offset by half a step).
function layout.mandala(items, o, mode, packer, r)
	local list = sortBySize(copyList(items), false)
	local out = {}
	if #list == 0 then return out end
	local centre = place(list[1], 0, 0, mode == "face" and 0 or list[1].rot)
	packer:add(centre)
	out[1] = centre
	local rest = {}
	for i = 2, #list do rest[#rest + 1] = list[i] end
	if #rest == 0 and o.fill then rest = { list[1] } end
	local ring, slot, count = 0, 0, 0
	local recent = {}
	drive(rest, o, mode, r, out, 1, function(it, i, cycle)
		if slot >= count then
			ring, slot = ring + 1, 0
			count = 6 * ring
			if not o.fill then count = math.min(count, #rest - i + 1) end
		end
		local deg = (slot + (ring % 2 == 0 and 0.5 or 0)) * 360 / count
		slot = slot + 1
		local p = nearestOnRay(packer, it, deg, mode, o.turns, (o.maxRadius or 1e9) - it.fp.r, 0, 0,
			frontier(recent, it, cycle), 180 / count)
		if not p then
			it.outside = true
			return 0
		end
		remember(recent, math.sqrt(p.x * p.x + p.y * p.y))
		packer:add(p)
		out[#out + 1] = p
		return 1
	end)
	return out
end

--- Spiral: golden-angle order by size, each item at the nearest free spot on its ray.
function layout.spiral(items, o, mode, packer, r)
	local list = sortBySize(copyList(items), false)
	local out = {}
	local recent = {}
	drive(list, o, mode, r, out, 1, function(it, i, cycle)
		local deg = (i - 1) * layout.GOLDEN_ANGLE
		local p = nearestOnRay(packer, it, deg, mode, o.turns, (o.maxRadius or 1e9) - it.fp.r, 0, 0,
			frontier(recent, it, cycle), 30)
		if not p then
			it.outside = true
			return 0
		end
		remember(recent, math.sqrt(p.x * p.x + p.y * p.y))
		packer:add(p)
		out[#out + 1] = p
		return 1
	end)
	return out
end

--- Scatter: seeded random spots in a disc sized for SCATTER_FILL (with fill: the max radius disc),
-- biggest first; an item that finds no random spot takes the nearest free spot on a random ray.
function layout.scatter(items, o, mode, r, packer)
	local list = sortBySize(copyList(items), true)
	local area = packArea(list, o.gap)
	local disc = o.fill and (o.maxRadius or 3000) or math.min(o.maxRadius or 1e9, math.sqrt(area / (math.pi * layout.SCATTER_FILL)))
	local out = {}
	drive(list, o, mode, r, out, 1, function(it, _, cycle)
		local span = disc - it.fp.r
		local p
		for _ = 1, (cycle == 0 and 60 or 20) do
			if span <= 0 then break end
			local d = span * math.sqrt(r:next())
			local a = r:next() * 2 * math.pi
			local x, y = d * math.cos(a), d * math.sin(a)
			local rot = mode == "face" and layout.faceAngle(x, y) or it.rot
			local c = place(it, x, y, rot)
			if packer:fits(c) then p = c break end
		end
		if not p and cycle == 0 then
			p = nearestOnRay(packer, it, r:next() * 360, mode, o.turns, (o.maxRadius or 1e9) - it.fp.r)
		end
		if not p then
			if cycle == 0 then it.outside = true end
			return 0
		end
		packer:add(p)
		out[#out + 1] = p
		return 1
	end)
	return out
end

-- Compaction (rectangle patterns with road shapes) -----------------------------------------------------

--- Slides every placement toward the axis line through the centre (axis "x": horizontally to x = 0,
-- keeping its row; "y": vertically), nearest first, to the closest spot where its road shape fits.
-- The box packing leaves the empty corners of star-shaped layouts; this lets arms interlock.
function layout.compact(ps, o, axis)
	local packer = layout.newPacker(o.gap, nil, o.shapeD)
	local order = {}
	for i, p in ipairs(ps) do order[i] = p end
	local function coord(p) return axis == "x" and p.x or p.y end
	table.sort(order, function(a, b)
		local ca, cb = math.abs(coord(a)), math.abs(coord(b))
		if ca ~= cb then return ca < cb end
		return math.abs(axis == "x" and a.y or a.x) < math.abs(axis == "x" and b.y or b.x)
	end)
	-- shift already applied per band of the other coordinate (and side): items further out in the
	-- same band slide at least about as far
	local band, shifts = 100, {}
	local function bandKey(p, sgn, d)
		return (sgn > 0 and "p" or "n") .. math.floor((axis == "x" and p.y or p.x) / band + d)
	end
	for _, p in ipairs(order) do
		local v = coord(p)
		local sgn = v >= 0 and 1 or -1
		local function at(t)
			local q = { item = p.item, mirrored = p.mirrored, fp = p.fp, rot = p.rot, x = p.x, y = p.y }
			if axis == "x" then q.x = sgn * t else q.y = sgn * t end
			return q
		end
		local fits = function(q) return packer:fits(q) end
		local step = stepOf(p.fp)
		-- the boxes were packed already: an item slides by at most about its own size
		local reach = 2 * (axis == "x" and p.fp.w or p.fp.h)
		local half = axis == "x" and p.fp.h or p.fp.w
		local prior = 0
		for d = -math.ceil(half / 2 / band), math.ceil(half / 2 / band) do
			prior = math.max(prior, shifts[bandKey(p, sgn, d)] or 0)
		end
		local t, c = layout.searchRay(at, fits, math.max(0, math.abs(v) - reach - prior), math.abs(v), step)
		if not t then t, c = layout.searchRay(at, fits, math.abs(v), math.abs(v) + 4 * (p.fp.w + p.fp.h), step) end
		if c then
			local moved = math.abs(v) - t
			p.x, p.y = c.x, c.y
			if moved > 0 then
				local k = bandKey(p, sgn, 0)
				shifts[k] = math.max(shifts[k] or 0, moved)
			end
		end
		packer:add(p)
		if o.tick then o.tick() end
	end
	return ps
end

local function compactBoth(ps, o)
	if not (o.shapes and o.compact) then return ps end
	-- items far beyond the max radius would be cropped anyway (sliding moves an item by about its size)
	if o.maxRadius then
		local keep = {}
		for _, p in ipairs(ps) do
			if math.sqrt(p.x * p.x + p.y * p.y) - 2 * (p.fp.w + p.fp.h) <= o.maxRadius then keep[#keep + 1] = p end
		end
		ps = keep
	end
	layout.compact(ps, o, "x")
	layout.compact(ps, o, "y")
	return ps
end

-- Driver ------------------------------------------------------------------------------------------

--- Drops placements overlapping an earlier one (exact oriented boxes, grown by gap / 2).
--- The clearance field range for a set of items (their mirrors too): any probe radius + gap + slack.
function layout.shapeRange(items, gap)
	local g = 0
	for _, it in ipairs(items) do
		g = math.max(g, it.fp.maxGrow or 0)
		if it.mirror and it.mirror.fp then g = math.max(g, it.mirror.fp.maxGrow or 0) end
	end
	return g + gap + shapeMod.SLACK + 1
end

function layout.validate(placements, gap, dropped, tick, shapeD)
	local packer = layout.newPacker(gap, nil, shapeD)
	local kept = {}
	for _, p in ipairs(placements) do
		if packer:fits(p) then
			packer:add(p)
			kept[#kept + 1] = p
		else
			dropped[#dropped + 1] = { item = p.item, reason = "overlap" }
		end
		if tick then tick() end
	end
	return kept
end

--- Footprint area / area of the layout's bounding box (0..1), and the bounding box size.
function layout.fill(placements)
	if #placements == 0 then return 0, 0, 0 end
	local area = 0
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(placements) do
		area = area + p.fp.w * p.fp.h
		local a, b, c, d = bounds(p, 0)
		x0, x1, y0, y1 = math.min(x0, a), math.max(x1, b), math.min(y0, c), math.max(y1, d)
	end
	local box = (x1 - x0) * (y1 - y0)
	return box > 0 and area / box or 0, x1 - x0, y1 - y0
end

--- Road area / area of the layout's bounding box (0..1): the buffered road shapes' area (their
-- clearance-field cells inside the shape; a box for a footprint without a shape).
function layout.roadFill(placements)
	if #placements == 0 then return 0 end
	local area = 0
	for _, p in ipairs(placements) do
		area = area + (p.fp.shape and shapeMod.area(p.fp.shape) or p.fp.w * p.fp.h)
	end
	local _, w, h = layout.fill(placements)
	return w * h > 0 and area / (w * h) or 0
end

--- Lays the items out. Returns placements (world coordinates), dropped.
-- opts.fill: repeat the items until the cap (total constructions) or the max radius is reached.
-- opts.tick: called now and then during long layouts (the runner yields its coroutine there).
function layout.run(items, opts)
	local pattern = opts.pattern or "grid"
	local gap = opts.gap or 10
	local mode = layout.rotationMode(pattern, opts.rotation)
	local shapes = opts.shapes ~= false and gap <= layout.SHAPE_MAX_GAP
	local turns = opts.rotation == nil or opts.rotation == "pattern"
	if turns and shapes then turns = "shape" end
	local o = { gap = gap, maxRadius = opts.maxRadius, turns = turns, shapes = shapes,
		fill = opts.fill and true or false, cap = opts.cap, tick = opts.tick }
	local r = rngMod.new(opts.seed or 1)
	local list = copyList(items)
	for _, it in ipairs(list) do it.rot = layout.preRotation(mode, r) end
	local shapeD = shapes and layout.shapeRange(items, gap) or nil
	local packer = layout.newPacker(gap, nil, shapeD)
	o.shapeD = shapeD
	-- (not in face mode: those cells are squares turned by multiples of 90 after packing)
	o.compact = (pattern == "grid" or pattern == "gradient" or pattern == "checker") and mode ~= "face"
	local placements
	-- the mosaic keeps its patch seams (no compaction)
	if pattern == "mosaic" then placements = layout.mosaic(list, o, mode, r)
	elseif pattern == "kaleido4" then placements = layout.kaleido(list, o, mode, 4, packer, r)
	elseif pattern == "kaleido8" then placements = layout.kaleido(list, o, mode, 8, packer, r)
	elseif pattern == "mandala" then placements = layout.mandala(list, o, mode, packer, r)
	elseif pattern == "spiral" then placements = layout.spiral(list, o, mode, packer, r)
	elseif pattern == "gradient" then placements = compactBoth(layout.gradient(list, o, mode, r), o)
	elseif pattern == "checker" then placements = compactBoth(layout.checker(list, o, mode, r), o)
	elseif pattern == "scatter" then placements = layout.scatter(list, o, mode, r, packer)
	else placements = compactBoth(layout.grid(list, o, mode, r), o)
	end
	local dropped = {}
	local kaleido = pattern == "kaleido4" or pattern == "kaleido8"
	local circle = kaleido or pattern == "mandala" or pattern == "spiral" or pattern == "scatter"
	for _, p in ipairs(placements) do
		-- rectangle patterns in face mode: turn by the multiple of 90 nearest to facing the centre
		-- (their cells are max(w, h) squares, so any multiple of 90 fits)
		if mode == "face" and not circle then
			p.rot = math.floor(layout.normRot(layout.faceAngle(p.x, p.y)) / 90 + 0.5) * 90
		end
		p.rot = layout.normRot(p.rot)
	end
	-- the max radius (the kaleidoscope's search already keeps whole orbits inside) and the cap
	-- (without fill the kaleidoscope places every combo's orbit: its cap is on combos; with fill the
	-- cap counts constructions everywhere). Repeats cropped by either are not reported.
	local maxRadius = opts.maxRadius or 1e9
	local capped = opts.cap and (o.fill or not kaleido)
	local inside = {}
	for _, p in ipairs(placements) do
		local d = math.sqrt(p.x * p.x + p.y * p.y) + p.fp.r
		local rep = p.item.cycle ~= nil
		if not (finite(p.x) and finite(p.y) and finite(p.rot)) then
			dropped[#dropped + 1] = { item = p.item, reason = "not finite" }
		elseif d > maxRadius + 1e-6 and not kaleido then
			if not rep then dropped[#dropped + 1] = { item = p.item, reason = "outside max radius" } end
		elseif capped and #inside >= opts.cap then
			if not rep then dropped[#dropped + 1] = { item = p.item, reason = "cap" } end
		else
			inside[#inside + 1] = p
		end
	end
	local kept = layout.validate(inside, gap, dropped, o.tick, shapeD)
	-- world coordinates
	local cx, cy = opts.cx or 0, opts.cy or 0
	for _, p in ipairs(kept) do
		p.x, p.y = layout.plusZero(p.x + cx), layout.plusZero(p.y + cy)
		p.ox, p.oy = layout.origin(p.fp, p.x, p.y, p.rot)
	end
	-- items the pattern did not place at all
	local seen = {}
	for _, p in ipairs(placements) do seen[p.item.base or p.item] = true end
	for _, it in ipairs(list) do
		if not seen[it] then
			dropped[#dropped + 1] = { item = it, reason = it.outside and "outside max radius" or "no free spot" }
		end
	end
	return kept, dropped
end

-- Retries (Build mode) ------------------------------------------------------------------------------

--- A packer holding every placement (world coordinates), for relocate().
function layout.packerOf(placements, gap)
	local shapeD
	if gap <= layout.SHAPE_MAX_GAP then
		local g = 0
		for _, p in ipairs(placements) do g = math.max(g, p.fp.maxGrow or 0) end
		shapeD = g + gap + shapeMod.SLACK + 1
	end
	local packer = layout.newPacker(gap, nil, shapeD)
	for _, p in ipairs(placements) do packer:add(p) end
	return packer
end

--- The nearest free spot around a refused placement p (which stays in the packer as a blocker:
-- its ground was refused): rays in 16 directions from p's position. Returns a new placement (added
-- to the packer) or nil. opts = { cx, cy, maxRadius }.
function layout.relocate(packer, p, opts)
	local best, bestD = nil, math.huge
	local cx, cy = opts.cx or 0, opts.cy or 0
	local maxR = opts.maxRadius or 1e9
	for k = 0, 15 do
		local a = math.rad(k * 22.5)
		local ux, uy = math.cos(a), math.sin(a)
		local t, c = layout.searchRay(function(tt)
			return { item = p.item, mirrored = p.mirrored, fp = p.fp, rot = p.rot, x = p.x + tt * ux, y = p.y + tt * uy }
		end, function(c)
			local d = math.sqrt((c.x - cx) ^ 2 + (c.y - cy) ^ 2) + c.fp.r
			return d <= maxR and packer:fits(c)
		end, stepOf(p.fp), math.min(bestD, maxR * 2), stepOf(p.fp))
		if t and t < bestD then best, bestD = c, t end
	end
	if not best then return nil end
	best.x, best.y = layout.plusZero(best.x), layout.plusZero(best.y)
	best.ox, best.oy = layout.origin(best.fp, best.x, best.y, best.rot)
	packer:add(best)
	return best
end

return layout
