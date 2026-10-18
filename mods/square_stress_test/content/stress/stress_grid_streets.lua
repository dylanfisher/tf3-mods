-- Stress Test "Wide grid" town streets: the pure geometry of the street grid construction
-- (infrastructure/street_construction/square_stress_test_town_grid.con.lua), a square grid of the
-- large 4-lane town street centred on the construction's origin (an even number of blocks: a central
-- street both ways), its outer ring optionally the country street (Showcase grids). No api.*:
-- unit-tested offline.
--
-- Result shape as the base roundabout and square_roundabouts (square_roundabouts_result.lua): one
-- STREET edgeList, every node free (freeNodes = all, snapNodes = none), so once built the grid is
-- plain streets the town can line with houses and the player can edit. Edge ends at the same spot
-- become one node. Every coordinate is +0, never -0 (docs/findings.md "Negative zero").
-- A construction whose edges reach about 485 m along x from its origin is refused (docs/findings.md
-- "Highway street templates and interchange placement"; |y| <= 325 m tested), so the largest grid is
-- +-400 m (+ the corner stubs, ~442 m).

local grid = {}

grid.KEYS = { half = "sqst_grid_half", era = "sqst_grid_era", ring = "sqst_grid_ring", layout = "sqst_grid_layout",
	holes = "sqst_grid_holes" }
-- Half the side of the grid (m), by the construction's "half" param (1-based index).
grid.HALF = { 200, 300, 400 }
-- Street template by the "era" param: the large town street, new (from 1940) or old.
grid.TEMPLATES = {
	"::/infrastructure/street/town/town_new_large.street_template",
	"::/infrastructure/street/town/town_old_large.street_template",
}
-- The outer ring (the four perimeter streets and the corner stubs) by the "ring" param: 1 the same
-- town street as the grid, 2 the country street of the same lanes (country_{new,old}_large: no houses on
-- either side of it, wiki modding/infrastructure/tracksstreets.md "country"; Showcase grids, SHOWCASE.md
-- "Country ring": the town then never lines the grid's outside).
grid.RING_TEMPLATES = {
	"::/infrastructure/street/country/country_new_large.street_template",
	"::/infrastructure/street/country/country_old_large.street_template",
}
-- Target block size (m, street centre to street centre); the real one divides the side evenly into an
-- even number of blocks, so a street runs through the centre both ways and every side has a node at
-- its middle (Lights showcase links join there, SHOWCASE.md "Square layout").
grid.BLOCK = 80
-- A dead-end stub this long leaves each corner diagonally outwards: the Junction test links only join
-- dead ends (stress_logic.rankTownNodes), and its junctions sit diagonally off the town's corners.
grid.STUB = 60

-- Layouts (the bench's City lights "Layout" option, BENCH.md "Funnel layouts"), by the "layout" param:
--   plain      every street (the default: every older build),
--   hourglass  a band of BAND_HALF blocks above and below the center line where only the 2 x NECK_HALF + 1 central
--              north-south streets (and the east-west streets between them) are built: the ring's sides, every other
--              north-south street and the east-west streets left and right of the neck are left out there, so all
--              traffic between the two halves goes through the neck,
--   holes      HOLE_COUNT holes of 2 x 2 blocks whose inner cross (the 4 streets meeting at the hole's center) is left
--              out; placed by the "holes" param (a pattern index, HOLE_PATTERNS of them), never at the grid's center
--              (the town's center stands there), at least HOLE_MIN_GAP lines apart (no two holes share a street).
-- Streets left out are never built (no bulldozing after the town grew): the town lines the remaining streets.
grid.LAYOUTS = { "plain", "hourglass", "holes" }
grid.NECK_HALF = 1        -- neck streets each side of the center street: 3 neck streets
grid.BAND_HALF = 1        -- blocks of the band above and below the center line: a band 2 blocks tall
grid.HOLE_COUNT = 4
grid.HOLE_PATTERNS = 12
grid.HOLE_MIN_GAP = 3     -- grid lines between two hole centers (either axis): one block of streets between holes
grid.GAP_MARGIN = 12.0    -- m: a street whose middle lies this far inside a gap is in it (the kept streets around: not)
grid.RING_REACH = 20.0    -- m: an hourglass gap reaches this far beyond the ring line (its ring sides are left out too)

local function z0(v)
	if v == 0 then return 0 end -- -0 == 0: +0
	return v
end

local function index(v, n, default)
	local i = tonumber(v)
	if i == nil or i < 1 or i > n or i ~= math.floor(i) then return default end
	return i
end

--- Street lines of a grid of half-size `half`: the coordinates of every line (both axes, an even
--- number of blocks: one line at 0) and the block size.
function grid.lines(half, block)
	local n = 2 * math.max(1, math.floor(half / (block or grid.BLOCK) + 0.5))
	local step = 2 * half / n
	local coords = {}
	for k = 0, n do coords[#coords + 1] = z0(-half + k * step) end
	return coords, step
end

--- Every grid edge: { p0, t0, p1, t1 } along x (rows) then along y (columns), straight, z 0.
function grid.edges(half, block)
	local coords, step = grid.lines(half, block)
	local out = {}
	for _, y in ipairs(coords) do
		for k = 1, #coords - 1 do
			out[#out + 1] = { { coords[k], y, 0 }, { step, 0, 0 }, { coords[k + 1], y, 0 }, { step, 0, 0 } }
		end
	end
	for _, x in ipairs(coords) do
		for k = 1, #coords - 1 do
			out[#out + 1] = { { x, coords[k], 0 }, { 0, step, 0 }, { x, coords[k + 1], 0 }, { 0, step, 0 } }
		end
	end
	local d = grid.STUB * math.sqrt(0.5)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			local cx, cy = z0(sx * half), z0(sy * half)
			local t = { z0(sx * d), z0(sy * d), 0 }
			out[#out + 1] = { { cx, cy, 0 }, t, { z0(cx + sx * d), z0(cy + sy * d), 0 }, t }
		end
	end
	return out
end

--- A Park-Miller step (exact in doubles: 16807 x 2^31 < 2^53).
local function nextRand(state)
	return (state * 16807) % 2147483647
end

--- The hole centers of pattern p on a grid of n blocks: { {i, j}, ... } (grid line indices 0..n), sorted. Candidates are
--- the lines 2..n-2 both ways (a hole's streets stay inner streets) except the center; shuffled by the pattern, then
--- taken greedily while at least HOLE_MIN_GAP lines from every hole taken. At most HOLE_COUNT; loops bounded by the
--- candidate count.
function grid.holeCenters(n, pattern)
	local c = math.floor(n / 2)
	local cand = {}
	for i = 2, n - 2 do
		for j = 2, n - 2 do
			if not (i == c and j == c) then cand[#cand + 1] = { i, j } end
		end
	end
	local state = ((math.floor(tonumber(pattern) or 1) - 1) % grid.HOLE_PATTERNS + 1) * 48271 % 2147483647
	for k = #cand, 2, -1 do
		state = nextRand(state)
		local r = state % k + 1
		cand[k], cand[r] = cand[r], cand[k]
	end
	local out = {}
	for _, p in ipairs(cand) do
		if #out >= grid.HOLE_COUNT then break end
		local free = true
		for _, q in ipairs(out) do
			if math.max(math.abs(p[1] - q[1]), math.abs(p[2] - q[2])) < grid.HOLE_MIN_GAP then free = false break end
		end
		if free then out[#out + 1] = p end
	end
	table.sort(out, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
	return out
end

--- The layout of a grid of half side `half`: which grid segments are left out (keys "h:i:j" = from line (i, j) to
--- (i + 1, j), "v:i:j" = to (i, j + 1)), its gaps (rectangles {x0, y0, x1, y1} relative to the center, before
--- GAP_MARGIN) and its counts. layout: grid.LAYOUTS name or index (anything else: plain); pattern: the holes pattern.
function grid.layout(half, layout, pattern, block)
	local _, step = grid.lines(half, block)
	local n = math.floor(2 * half / step + 0.5)
	local c = math.floor(n / 2)
	local name = grid.LAYOUTS[tonumber(layout) or 0] or layout
	if name ~= "hourglass" and name ~= "holes" then name = "plain" end
	local out = { name = name, n = n, step = step, half = half, removed = {}, gaps = {}, holes = {}, neck = 0, pattern = 0 }
	local function rect(i0, j0, i1, j1)
		return { -half + i0 * step, -half + j0 * step, -half + i1 * step, -half + j1 * step }
	end
	if name == "hourglass" then
		local N, B = grid.NECK_HALF, grid.BAND_HALF
		out.neck = 2 * N + 1
		for j = c - B + 1, c + B - 1 do
			for i = 0, n - 1 do
				if not (i >= c - N and i + 1 <= c + N) then out.removed["h:" .. i .. ":" .. j] = true end
			end
		end
		for i = 0, n do
			if math.abs(i - c) > N then
				for j = c - B, c + B - 1 do out.removed["v:" .. i .. ":" .. j] = true end
			end
		end
		local l = rect(0, c - B, c - N, c + B)
		l[1] = l[1] - grid.RING_REACH
		local r = rect(c + N, c - B, n, c + B)
		r[3] = r[3] + grid.RING_REACH
		out.gaps = { l, r }
	elseif name == "holes" then
		out.pattern = (math.floor(tonumber(pattern) or 1) - 1) % grid.HOLE_PATTERNS + 1
		out.holes = grid.holeCenters(n, out.pattern)
		for _, h in ipairs(out.holes) do
			local i, j = h[1], h[2]
			out.removed["h:" .. (i - 1) .. ":" .. j] = true
			out.removed["h:" .. i .. ":" .. j] = true
			out.removed["v:" .. i .. ":" .. (j - 1)] = true
			out.removed["v:" .. i .. ":" .. j] = true
			out.gaps[#out.gaps + 1] = rect(i - 1, j - 1, i + 1, j + 1)
		end
	end
	-- the inner crossings left: degree of every inner line point (1..n-1 both ways) from the kept segments
	local function kept(key) return not out.removed[key] end
	local x4, t3, gone = 0, 0, 0
	for i = 1, n - 1 do
		for j = 1, n - 1 do
			local d = 0
			if kept("h:" .. (i - 1) .. ":" .. j) then d = d + 1 end
			if kept("h:" .. i .. ":" .. j) then d = d + 1 end
			if kept("v:" .. i .. ":" .. (j - 1)) then d = d + 1 end
			if kept("v:" .. i .. ":" .. j) then d = d + 1 end
			if d == 4 then x4 = x4 + 1 elseif d == 3 then t3 = t3 + 1 elseif d == 0 then gone = gone + 1 end
		end
	end
	out.x4, out.t3, out.gone = x4, t3, gone
	out.crossings = x4 + t3
	return out
end

--- The segment key of a grid edge ({ p0, t0, p1, t1 } of grid.edges) in layout L, nil for a corner stub.
function grid.edgeKey(e, L)
	local a, b = e[1], e[3]
	local h = L.half
	if math.abs(a[1]) > h + 1e-6 or math.abs(a[2]) > h + 1e-6 or math.abs(b[1]) > h + 1e-6 or math.abs(b[2]) > h + 1e-6 then return nil end
	local i = math.floor((math.min(a[1], b[1]) + h) / L.step + 0.5)
	local j = math.floor((math.min(a[2], b[2]) + h) / L.step + 0.5)
	if math.abs(a[2] - b[2]) < 1e-6 then return "h:" .. i .. ":" .. j end
	return "v:" .. i .. ":" .. j
end

--- grid.edges without the segments layout L leaves out.
function grid.layoutEdges(half, L, block)
	local out = {}
	for _, e in ipairs(grid.edges(half, block)) do
		local key = grid.edgeKey(e, L)
		if key == nil or not L.removed[key] then out[#out + 1] = e end
	end
	return out
end

--- Whether a point (px, py relative to the grid's center; a street's middle) lies in one of layout L's gaps, GAP_MARGIN
--- inside it (the streets around a gap are not in it).
function grid.inGap(L, px, py)
	local m = grid.GAP_MARGIN
	for _, r in ipairs(L.gaps or {}) do
		if px > r[1] + m and px < r[3] - m and py > r[2] + m and py < r[4] - m then return true end
	end
	return false
end

--- Whether a grid edge (grid.edges' { p0, t0, p1, t1 }) belongs to the outer ring: both ends on the
--- same perimeter line, or a corner stub (an end outside the square).
function grid.onRing(e, half)
	local a, b = e[1], e[3]
	local function out(p) return math.abs(p[1]) > half + 1e-6 or math.abs(p[2]) > half + 1e-6 end
	if out(a) or out(b) then return true end
	for k = 1, 2 do
		if math.abs(math.abs(a[k]) - half) < 1e-6 and math.abs(b[k] - a[k]) < 1e-6 then return true end
	end
	return false
end

local function edgeList(template, list)
	local entries = {}
	for _, e in ipairs(list) do
		entries[#entries + 1] = { e[1], e[2] }
		entries[#entries + 1] = { e[3], e[4] }
	end
	local free = {}
	for i = 1, #entries do free[i] = i - 1 end
	return { type = "STREET", params = { type = template }, edges = entries, snapNodes = {}, freeNodes = free }
end

--- The construction result for the params (1-based indices; missing ones give the defaults:
--- 300 m, new era, the ring of the grid's own street, the plain layout). Ring 2: the perimeter and the stubs are a second
--- edge list of the country street (the nodes they share with the inner streets are one node each).
function grid.result(params)
	params = params or {}
	local half = grid.HALF[index(params[grid.KEYS.half], #grid.HALF, 2)]
	local era = index(params[grid.KEYS.era], #grid.TEMPLATES, 1)
	local template = grid.TEMPLATES[era]
	local country = index(params[grid.KEYS.ring], 2, 1) == 2
	local L = grid.layout(half, index(params[grid.KEYS.layout], #grid.LAYOUTS, 1),
		index(params[grid.KEYS.holes], grid.HOLE_PATTERNS, 1))
	local inner, ring = {}, {}
	for _, e in ipairs(grid.layoutEdges(half, L)) do
		if country and grid.onRing(e, half) then ring[#ring + 1] = e else inner[#inner + 1] = e end
	end
	local lists = { edgeList(template, inner) }
	if #ring > 0 then lists[2] = edgeList(grid.RING_TEMPLATES[era], ring) end
	return {
		edgeLists = lists,
		models = {},
		groundFaces = {},
		cost = 0,
	}
end

return grid
