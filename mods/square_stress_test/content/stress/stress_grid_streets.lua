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

grid.KEYS = { half = "sqst_grid_half", era = "sqst_grid_era", ring = "sqst_grid_ring" }
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
--- 300 m, new era, the ring of the grid's own street). Ring 2: the perimeter and the stubs are a second
--- edge list of the country street (the nodes they share with the inner streets are one node each).
function grid.result(params)
	params = params or {}
	local half = grid.HALF[index(params[grid.KEYS.half], #grid.HALF, 2)]
	local era = index(params[grid.KEYS.era], #grid.TEMPLATES, 1)
	local template = grid.TEMPLATES[era]
	local country = index(params[grid.KEYS.ring], 2, 1) == 2
	local inner, ring = {}, {}
	for _, e in ipairs(grid.edges(half)) do
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
