-- DEV ONLY (never upload): Roundabouts Showcase, road-shape collisions. Pure Lua (no api.*).
--
-- A footprint's shape is its actual road geometry, not its bounding box:
--   * probes: points every <= SPACING metres along every edge (and island outlines), each with its
--     own buffer radius g (half street width + kerb + earth slope, sc_footprint), in the
--     construction frame. Arrays px, py, pg, pz (height), pk (kind code, for the REFUSED analysis).
--   * segs: the polyline pieces between consecutive probes of an edge, buffered by max(g0, g1).
--   * polys: island outlines (ground faces): their inside is occupied too (the island
--     subconstruction has colliders).
-- The buffered shape = union of the buffered segments and the polygons.
--
-- Collision of two placed shapes A and B (gap metres apart at least): the shape with fewer probes is
-- tested against the other's CLEARANCE FIELD, a sparse grid (CELL m) in its own construction frame
-- holding, per cell centre, the distance to its buffered shape (negative = inside), stored where it
-- is below a range D. One table lookup per probe, early exit, so the costly part (the field) is
-- built once per combo, not per rotation or position. Conservative: a probe point p with radius g
-- collides when field(cell(p)) < g + gap + SLACK, SLACK = SPACING / 2 (the buffer between two
-- probes) + the cell's half diagonal (p is not exactly at its cell centre).
-- The bounding boxes (sc_layout.overlaps) stay the broad phase.

local shape = {}

shape.SPACING = 6
shape.CELL = 5
-- field segments join this many probe steps (their chord sag is added to the buffer)
shape.MERGE = 3
shape.SLACK = shape.SPACING / 2 + shape.CELL * math.sqrt(2) / 2
-- buffer radius of island outline probes (the polygon inside is occupied anyway)
shape.POLY_GROW = 1

-- kind codes of the probes (pk), for logs
shape.KINDS = { "town", "country", "highway", "bridge", "island", "other" }

--- Kind code of a street template (bridge lists win).
function shape.kindOf(template, bridge)
	if bridge then return 4 end
	local t = tostring(template or "")
	if t:find("highway", 1, true) then return 3 end
	if t:find("country", 1, true) then return 2 end
	if t:find("town", 1, true) then return 1 end
	return 6
end

function shape.new()
	return { px = {}, py = {}, pg = {}, pz = {}, pk = {}, segs = {}, polys = {}, n = 0, maxGrow = 0 }
end

local function addProbe(s, x, y, g, z, k)
	local n = s.n + 1
	s.n = n
	s.px[n], s.py[n], s.pg[n], s.pz[n], s.pk[n] = x, y, g, z or 0, k or 6
	if g > s.maxGrow then s.maxGrow = g end
	return n
end

--- Adds a sampled polyline: points {{x, y, z, g}}; consecutive points become buffered segments.
function shape.addPolyline(s, pts, kind)
	local first = s.n + 1
	for _, p in ipairs(pts) do addProbe(s, p[1], p[2], p[4], p[3], kind) end
	local last = s.n
	-- field segments: chords over MERGE probe steps, buffered by the largest g of their probes plus the
	-- farthest probe's distance from the chord (so the chord's buffer covers every probe's)
	local a = first
	while a < last do
		local b = math.min(a + shape.MERGE, last)
		local x0, y0, x1, y1 = s.px[a], s.py[a], s.px[b], s.py[b]
		local dx, dy = x1 - x0, y1 - y0
		local L2 = dx * dx + dy * dy
		local g = 0
		for i = a, b do
			local t = 0
			if L2 > 0 then
				t = ((s.px[i] - x0) * dx + (s.py[i] - y0) * dy) / L2
				if t < 0 then t = 0 elseif t > 1 then t = 1 end
			end
			local ex, ey = s.px[i] - (x0 + t * dx), s.py[i] - (y0 + t * dy)
			local v = s.pg[i] + math.sqrt(ex * ex + ey * ey)
			if v > g then g = v end
		end
		s.segs[#s.segs + 1] = { x0, y0, x1, y1, g }
		a = b
	end
end

--- Adds an island outline (closed polygon of {x, y, z?} points): probes along it, the inside occupied.
function shape.addPolygon(s, outline)
	if type(outline) ~= "table" or #outline < 3 then return end
	local poly = {}
	for i, p in ipairs(outline) do poly[i] = { p[1], p[2] } end
	s.polys[#s.polys + 1] = poly
	local pts = {}
	for i = 1, #poly + 1 do
		local a = poly[(i - 1) % #poly + 1]
		local b = poly[i % #poly + 1]
		if i <= #poly then
			local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
			local m = math.max(1, math.ceil(len / shape.SPACING))
			for k = 0, m - 1 do
				local t = k / m
				pts[#pts + 1] = { a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2]), 0, shape.POLY_GROW }
			end
		end
	end
	pts[#pts + 1] = pts[1]
	shape.addPolyline(s, pts, 5)
end

local function inside(poly, x, y)
	local c = false
	local j = #poly
	for i = 1, #poly do
		local a, b = poly[i], poly[j]
		if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then c = not c end
		j = i
	end
	return c
end

local KEY = 1048576

--- The clearance field of a shape up to range D (cached; rebuilt only for a larger D).
-- field[i * KEY + j] = distance from the cell centre (i * CELL, j * CELL) to the buffered shape.
function shape.field(s, D, tick)
	if s.field and s.fieldD >= D then return s.field end
	local c = shape.CELL
	local f = {}
	for _, sg in ipairs(s.segs) do
		local x0, y0, x1, y1, g = sg[1], sg[2], sg[3], sg[4], sg[5]
		local r = g + D
		local dx, dy = x1 - x0, y1 - y0
		local L2 = dx * dx + dy * dy
		for i = math.floor((math.min(x0, x1) - r) / c), math.ceil((math.max(x0, x1) + r) / c) do
			local cx = i * c
			for j = math.floor((math.min(y0, y1) - r) / c), math.ceil((math.max(y0, y1) + r) / c) do
				local cy = j * c
				local t = 0
				if L2 > 0 then
					t = ((cx - x0) * dx + (cy - y0) * dy) / L2
					if t < 0 then t = 0 elseif t > 1 then t = 1 end
				end
				local ex, ey = cx - (x0 + t * dx), cy - (y0 + t * dy)
				local v = math.sqrt(ex * ex + ey * ey) - g
				if v < D then
					local k = i * KEY + j
					local old = f[k]
					if old == nil or v < old then f[k] = v end
				end
			end
		end
		if tick then tick() end
	end
	for _, poly in ipairs(s.polys) do
		local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(poly) do
			x0, x1, y0, y1 = math.min(x0, p[1]), math.max(x1, p[1]), math.min(y0, p[2]), math.max(y1, p[2])
		end
		for i = math.floor(x0 / c), math.ceil(x1 / c) do
			for j = math.floor(y0 / c), math.ceil(y1 / c) do
				if inside(poly, i * c, j * c) then f[i * KEY + j] = -1 end
			end
		end
	end
	s.field, s.fieldD = f, D
	return f
end

--- Area (m2) of the buffered shape: its field cells at or below 0 (cached; builds a small field
-- if none exists yet).
function shape.area(s)
	if s.areaM2 then return s.areaM2 end
	local f = s.field or shape.field(s, 1)
	local n = 0
	for _, v in pairs(f) do if v <= 0 then n = n + 1 end end
	s.areaM2 = n * shape.CELL * shape.CELL
	return s.areaM2
end

--- Probe chunks (CHUNK consecutive probes) with bounding circles, for culling (cached).
shape.CHUNK = 8
function shape.chunks(s)
	if s.chunkList then return s.chunkList end
	local out = {}
	for a = 1, s.n, shape.CHUNK do
		local b = math.min(a + shape.CHUNK - 1, s.n)
		local cx, cy = 0, 0
		for i = a, b do cx, cy = cx + s.px[i], cy + s.py[i] end
		cx, cy = cx / (b - a + 1), cy / (b - a + 1)
		local r = 0
		for i = a, b do r = math.max(r, math.sqrt((s.px[i] - cx) ^ 2 + (s.py[i] - cy) ^ 2)) end
		out[#out + 1] = { a, b, cx, cy, r }
	end
	s.chunkList = out
	return out
end

--- Bounds of a shape's field cells (construction frame): its probes' extent + max g + D.
local function fieldBounds(s, D)
	if s.fbD == D then return s.fb end
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, s.n do
		local g = s.pg[i] + D
		x0, x1 = math.min(x0, s.px[i] - g), math.max(x1, s.px[i] + g)
		y0, y1 = math.min(y0, s.py[i] - g), math.max(y1, s.py[i] + g)
	end
	for _, poly in ipairs(s.polys) do
		for _, q in ipairs(poly) do
			x0, x1 = math.min(x0, q[1] - D), math.max(x1, q[1] + D)
			y0, y1 = math.min(y0, q[2] - D), math.max(y1, q[2] + D)
		end
	end
	s.fb, s.fbD = { x0, x1, y0, y1 }, D
	return s.fb
end

--- Do two placed shapes collide? a, b = { fp = {shape}, rot, ox, oy } (construction origin and
-- rotation in one shared frame). The shape with fewer probes is tested against the other's field
-- (built to range D). Returns true / false.
function shape.collide(a, b, gap, D, cosSin)
	return shape.collideRaw(a.fp.shape, a.rot, a.ox, a.oy, b.fp.shape, b.rot, b.ox, b.oy, gap, D, cosSin)
end

--- collide() without tables: shapes, rotations and origins as arguments.
function shape.collideRaw(sa, ra, oxa, oya, sb, rb, oxb, oyb, gap, D, cosSin)
	local sx, sy, rX, rY, oxX, oyX, oxY, oyY = sa, sb, ra, rb, oxa, oya, oxb, oyb
	if sa.n > sb.n then sx, sy, rX, rY, oxX, oyX, oxY, oyY = sb, sa, rb, ra, oxb, oyb, oxa, oya end
	if shape.probesHit(sx, rX, oxX, oyX, sy, rY, oxY, oyY, gap, D, cosSin) then return true end
	-- the other shape may lie wholly inside an island polygon of the probed one (its outline probes
	-- never come near): only that polygon's field sees it
	if #sx.polys > 0 then return shape.probesHit(sy, rY, oxY, oyY, sx, rX, oxX, oyX, gap, D, cosSin) end
	return false
end

--- Do the probes of shape sx (rotation rX, origin oxX/oyX) hit the field of sy?
function shape.probesHit(sx, rX, oxX, oyX, sy, rY, oxY, oyY, gap, D, cosSin)
	local f = shape.field(sy, D)
	local cX, sX = cosSin(rX)
	local cY, sY = cosSin(rY)
	local c = shape.CELL
	local floor = math.floor
	local extra = gap + shape.SLACK
	local px, py, pg = sx.px, sx.py, sx.pg
	local dxo, dyo = oxX - oxY, oyX - oyY
	-- probe (x, y) in X -> world -> Y: q = R(-Y) (oX - oY + R(X) p)
	local ax, ay = cY * dxo + sY * dyo, -sY * dxo + cY * dyo
	local m11, m12 = cY * cX + sY * sX, -cY * sX + sY * cX
	local m21, m22 = -sY * cX + cY * sX, sY * sX + cY * cX
	local fb = fieldBounds(sy, D)
	local bx0, bx1, by0, by1 = fb[1], fb[2], fb[3], fb[4]
	for _, ch in ipairs(shape.chunks(sx)) do
		-- the chunk's circle in Y's frame; skip it when it misses Y's field area
		local x, y, r = ch[3], ch[4], ch[5]
		local qx, qy = ax + m11 * x + m12 * y, ay + m21 * x + m22 * y
		if qx + r >= bx0 and qx - r <= bx1 and qy + r >= by0 and qy - r <= by1 then
			for i = ch[1], ch[2] do
				x, y = px[i], py[i]
				qx, qy = ax + m11 * x + m12 * y, ay + m21 * x + m22 * y
				local v = f[floor(qx / c + 0.5) * KEY + floor(qy / c + 0.5)]
				if v and v < pg[i] + extra then return true end
			end
		end
	end
	return false
end

--- The model's clearance between two placed shapes (m, minus both buffers; negative = overlapping),
-- and the probe kind / height where it is smallest (REFUSED analysis). nil if not within D.
function shape.clearance(a, b, D, cosSin)
	local sa, sb = a.fp.shape, b.fp.shape
	local f = shape.field(sb, D)
	local cA, sA = cosSin(a.rot)
	local cB, sB = cosSin(b.rot)
	local c = shape.CELL
	local best, kind, z
	for i = 1, sa.n do
		local wx = a.ox + cA * sa.px[i] - sA * sa.py[i]
		local wy = a.oy + sA * sa.px[i] + cA * sa.py[i]
		local qx = cB * (wx - b.ox) + sB * (wy - b.oy)
		local qy = -sB * (wx - b.ox) + cB * (wy - b.oy)
		local v = f[math.floor(qx / c + 0.5) * KEY + math.floor(qy / c + 0.5)]
		if v then
			v = v - sa.pg[i]
			if not best or v < best then best, kind, z = v, sa.pk[i], sa.pz[i] end
		end
	end
	return best, kind and shape.KINDS[kind], z
end

return shape
