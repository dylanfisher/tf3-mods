-- Stress Test town entry roundabout (Lights showcase; plans/square_stress_test/SHOWCASE.md "Town entries
-- must not be the bottleneck"): the pure geometry of square_stress_test_entry.con.lua. A round one-way ring of
-- a country street (3 lanes: highway_new_large, or 2 lanes: highway_new_medium; entry.RINGS; ring edges as
-- square_roundabouts' Roundabout output) with four straight arms of the large country road
-- along +x, +y, -x, -y, each ending REACH m from the centre. No api.*: unit-tested offline.
--
-- Why our own and not square_roundabouts' (in-game 2026-10-12, log 2026-10-12_2343_top-up-563524): its arms
-- run 30 m beyond the ring's outer edge (62 m from the centre), and at a Medium grid's side middle the next
-- grid nodes lie 75 m out, their junction areas (the 32 m town street: half 16 m) from about 59 m. Every one of
-- 96 entries came back "Collision (hits 12 other BASE_NODE)". These arms end at REACH (46 m), clear of them,
-- and the Stress Test joins each arm end to its far grid node afterwards.
--
-- Result shape as stress_grid_streets.lua: STREET edgeLists, every node free (freeNodes = all, snapNodes =
-- none), so once built the roundabout is plain streets; edge ends at the same spot become one node. Every
-- coordinate is exact and +0, never -0 (docs/findings.md "Negative zero"). Driving direction by the param
-- sqst_entry_dir: 1 anticlockwise (right-hand traffic, the default), 2 clockwise (left-hand traffic; the window
-- reads the map's driving side from a grid street's lanes).

local entry = {}

-- The ring: a country one-way street, so the town builds no houses on it or on its island (2026-10-13, user
-- screenshot of session 2026-10-13_0045_top-up-158690: with town_new_one_way_small a tower stood on the island and
-- houses lined the ring; the country arms stayed clear; country roads get no houses, docs/findings/roads.md).
-- highway_new_medium is the base game's 2-lane country one-way (square_roundabouts rings its 1-lane roundabouts
-- with highway_new_small); 18 m of lanes, no sidewalks.
-- The rings by sqst_entry_ring (1-based): 1 the 2-lane ring (highway_new_medium, 18 m of lanes, centreline 24 m:
-- square_roundabouts' 2-lane Roundabout at radius S), 2 the 3-lane ring (highway_new_large, 23 m of lanes, the
-- widest country one-way of the base game: no 4-lane one exists; centreline 22 m, island kerb at 10.5 m; outer
-- edge 33.5 m, as the 2-lane ring's 33 m, so it fits the same block; square_roundabouts' 3-lane ring with large
-- country arms placed in its engine probe at a 19 m centreline, plans/square_roundabouts/probe_results.csv).
-- User 2026-10-13: "3/4 lanes, whatever is biggest". The window tries the 3-lane ring first, then the 2-lane one.
entry.RINGS = {
	{ template = "::/infrastructure/street/highway/highway_new_medium.street_template", radius = 24, half = 9, lanes = 2 },
	{ template = "::/infrastructure/street/highway/highway_new_large.street_template", radius = 22, half = 11.5, lanes = 3 },
}
entry.RING_DEFAULT = 1
entry.RING_TEMPLATE = entry.RINGS[1].template
entry.RING_RADIUS = entry.RINGS[1].radius          -- the 2-lane ring's centreline
entry.RING_HALF_WIDTH = entry.RINGS[1].half
entry.ARM_TEMPLATE = "::/infrastructure/street/country/country_new_large.street_template"
entry.ARM_HALF_WIDTH = 15  -- country_new_large: 30 m of lanes
entry.REACH = 46           -- arm ends: this far from the centre (stress_logic ENTRY_REACH)
entry.FROM_YEAR = 1940     -- every template exists from 1940 (their yearFrom)
entry.KEYS = { dir = "sqst_entry_dir", inAxis = "sqst_entry_in_axis", inReach = "sqst_entry_in_reach", ring = "sqst_entry_ring",
	mid = "sqst_entry_mid" }
-- Ring mid nodes (the bench's Sheet 4 v4 3-lane ring, bench_rb3m; square_smart_lanes' sl_rsplit / sl_rmid write their
-- lane changes there): sqst_entry_mid 1 none (the default: the ring as before, byte for byte), 2..4 = 1..3 plain ring
-- nodes evenly on every quarter between two arms. With the 3-lane ring and its 30 m country large arms only 1 leaves
-- room: the arm's junction takes about 10 m of ring centreline at each end of a 34.6 m quarter (r asin(15 / 33.5)), so
-- 1 node leaves ~7 m of free ring on each piece, 2 nodes ~1 m (square_roundabouts asks for 5 m: geom.JUNCTION_PLAN).
entry.MID_MAX = 3
-- The inward arm (towards the town's central street) can end shorter: in game 2026-10-13 (log session
-- 2026-10-13_0018_top-up-598153) every 46 m inward arm still hit the next crossroads of the grid (75 m out) while
-- the ring arms cleared their T-junctions. sqst_entry_in_axis picks that arm (1 none, 2..5 = +x, +y, -x, -y),
-- sqst_entry_in_reach its end (index into IN_REACHES). The shortest leaves 2.5 m beyond the 3-lane ring's outer
-- edge (33.5 m), 3 m beyond the 2-lane one's (33 m).
entry.IN_REACHES = { 46, 42, 38, 36 }
entry.DIR_CCW = 1          -- anticlockwise: right-hand traffic
entry.DIR_CW = 2           -- clockwise: left-hand traffic

-- Ring nodes and the unit tangent (anticlockwise) at each, in order +x, +y, -x, -y.
local AXES = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }

local function z0(v)
	if v == 0 then return 0 end -- -0 == 0: +0
	return v
end

local function vec(x, y) return { z0(x), z0(y), 0 } end

--- The ring of the params (sqst_entry_ring; missing or out of range: the 2-lane ring).
function entry.ring(params)
	local i = params ~= nil and tonumber(params[entry.KEYS.ring]) or nil
	if i == nil or i ~= math.floor(i) or entry.RINGS[i] == nil then i = entry.RING_DEFAULT end
	return entry.RINGS[i], i
end

--- Every edge: { p0, t0, p1, t1, template }: the four ring quarters (cubic Hermite tangents r * 4 * (sqrt 2 - 1),
--- the quarter-circle value square_roundabouts and the base roundabout use; an edge's direction is the one-way
--- ring's driving direction, clockwise when cw: each quarter reversed, its tangents negated), then the four
--- arms outwards (the one on axis inAxis, 1..4 in AXES order, ending at inReach instead of REACH). ring: an
--- entry.RINGS entry (nil: the 2-lane ring).
local function snap(v)
	if math.abs(v) < 1e-9 then return 0 end
	return v
end

--- The ring of one quarter (axis k to axis k + 1) in n + 1 pieces (n mid nodes), cubic Hermite tangents
--- r * 4 * tan(theta / 4) per piece (the arc's value; theta = 90 / (n + 1) degrees), in driving order.
local function quarterPieces(r, k, n, cw, template)
	local out = {}
	local a0 = (k - 1) * math.pi / 2
	local th = (math.pi / 2) / (n + 1)
	local s = r * 4 * math.tan(th / 4)
	for q = 0, n do
		local al, be = a0 + q * th, a0 + (q + 1) * th
		local p0 = vec(snap(r * math.cos(al)), snap(r * math.sin(al)))
		local p1 = vec(snap(r * math.cos(be)), snap(r * math.sin(be)))
		local t0 = vec(snap(-s * math.sin(al)), snap(s * math.cos(al)))
		local t1 = vec(snap(-s * math.sin(be)), snap(s * math.cos(be)))
		if cw then
			table.insert(out, 1, { p1, vec(-t1[1], -t1[2]), p0, vec(-t0[1], -t0[2]), template })
		else
			out[#out + 1] = { p0, t0, p1, t1, template }
		end
	end
	return out
end

function entry.edges(cw, inAxis, inReach, ring, mid)
	local rg = ring or entry.RINGS[entry.RING_DEFAULT]
	local r = rg.radius
	local t = r * 4 * (math.sqrt(2) - 1)
	local out = {}
	for k = 1, 4 do
		if mid ~= nil and mid > 0 then
			for _, e in ipairs(quarterPieces(r, k, mid, cw, rg.template)) do out[#out + 1] = e end
		else
			local a, b = AXES[k], AXES[k % 4 + 1]
			-- the anticlockwise tangent at axis (x, y) is (-y, x)
			if cw then
				out[#out + 1] = { vec(r * b[1], r * b[2]), vec(t * b[2], -t * b[1]), vec(r * a[1], r * a[2]), vec(t * a[2], -t * a[1]),
					rg.template }
			else
				out[#out + 1] = { vec(r * a[1], r * a[2]), vec(-t * a[2], t * a[1]), vec(r * b[1], r * b[2]), vec(-t * b[2], t * b[1]),
					rg.template }
			end
		end
	end
	for k, a in ipairs(AXES) do
		local reach = (k == inAxis and inReach ~= nil) and inReach or entry.REACH
		local len = reach - r
		local tan = vec(len * a[1], len * a[2])
		out[#out + 1] = { vec(r * a[1], r * a[2]), tan, vec(reach * a[1], reach * a[2]), { tan[1], tan[2], 0 }, entry.ARM_TEMPLATE }
	end
	return out
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

--- Whether the params ask for the clockwise ring (anything but sqst_entry_dir = 2 is anticlockwise).
function entry.clockwise(params)
	return params ~= nil and tonumber(params[entry.KEYS.dir]) == entry.DIR_CW
end

--- The inward arm's axis (1..4 in AXES order) and reach from the params; nil, nil: every arm at REACH.
function entry.inward(params)
	if params == nil then return nil, nil end
	local ax = tonumber(params[entry.KEYS.inAxis])
	local ri = tonumber(params[entry.KEYS.inReach])
	if ax == nil or ax < 2 or ax > 5 or ax ~= math.floor(ax) then return nil, nil end
	if ri == nil or ri < 1 or ri > #entry.IN_REACHES or ri ~= math.floor(ri) then ri = 1 end
	return ax - 1, entry.IN_REACHES[ri]
end

--- The ring mid nodes per quarter of the params (sqst_entry_mid; missing or out of range: 0).
function entry.midNodes(params)
	local i = params ~= nil and tonumber(params[entry.KEYS.mid]) or nil
	if i == nil or i ~= math.floor(i) or i < 1 or i > entry.MID_MAX + 1 then return 0 end
	return i - 1
end

--- The construction result for the params (sqst_entry_dir; missing: anticlockwise; the inward arm's).
function entry.result(params)
	local ring, arms = {}, {}
	local inAxis, inReach = entry.inward(params)
	local rg = entry.ring(params)
	for _, e in ipairs(entry.edges(entry.clockwise(params), inAxis, inReach, rg, entry.midNodes(params))) do
		if e[5] == rg.template then ring[#ring + 1] = e else arms[#arms + 1] = e end
	end
	return {
		edgeLists = { edgeList(rg.template, ring), edgeList(entry.ARM_TEMPLATE, arms) },
		models = {},
		groundFaces = {},
		cost = 0,
	}
end

return entry
