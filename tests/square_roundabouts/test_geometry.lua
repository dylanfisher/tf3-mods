-- square_roundabouts_geometry: ring, arms and island from params (pure, no api.*).
-- Phase 1/2 behaviour (no splitter, no through road); Phase 3 types: test_types.lua.

local geom = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"
local K = geom.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local PI = math.pi
local atan2 = math.atan2 or math.atan

local function spec(over)
	local p = {}
	for k, v in pairs(over or {}) do p[K[k]] = v end
	return geom.readParams(p)
end

local function build(over) return geom.build(spec(over)) end

-- cubic Hermite point at s in [0, 1]
local function hermite(p0, t0, p1, t1, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local out = {}
	for i = 1, 3 do out[i] = h00 * p0[i] + h10 * t0[i] + h01 * p1[i] + h11 * t1[i] end
	return out
end

local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function dist(p, q) return len({ p[1] - q[1], p[2] - q[2], p[3] - q[3] }) end
local function cross(p, q) return p[1] * q[2] - p[2] * q[1] end
local function dot(p, q) return p[1] * q[1] + p[2] * q[2] end

local function eachConfig(fn)
	for _, shape in ipairs({ geom.SHAPE_ROUND, 3, #geom.SHAPE_RATIOS }) do
		for lanes = 1, 3 do
			for arms = 1, #geom.ARM_LAYOUTS do
				for dir = 1, 2 do
					for _, radius in ipairs({ 1, 4, #geom.RADII }) do
						fn({ shape = shape, lanes = lanes, arms = arms, direction = dir, radius = radius })
					end
				end
			end
		end
	end
end

local function pointInPolygon(x, y, poly)
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
		if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- minimum distance from p to the ellipse (a, b), by dense sampling
-- Shortest distance from p to the ellipse: 720 samples, then a golden-section refinement around
-- every local minimum of them (at least as exact as 3600 plain samples, ~4x faster).
local function distToEllipse(p, a, b)
	local N = 720
	local function at(t) return dist(p, { a * math.cos(t), b * math.sin(t), 0 }) end
	local d = {}
	for k = 0, N - 1 do d[k] = at(2 * PI * k / N) end
	local best, step, g = math.huge, 2 * PI / N, (math.sqrt(5) - 1) / 2
	for k = 0, N - 1 do
		if d[k] <= d[(k - 1) % N] and d[k] <= d[(k + 1) % N] then
			local lo, hi = 2 * PI * k / N - step, 2 * PI * k / N + step
			local x1, x2 = hi - g * (hi - lo), lo + g * (hi - lo)
			local f1, f2 = at(x1), at(x2)
			for _ = 1, 40 do
				if f1 < f2 then hi, x2, f2 = x2, x1, f1; x1 = hi - g * (hi - lo); f1 = at(x1)
				else lo, x1, f1 = x1, x2, f2; x2 = lo + g * (hi - lo); f2 = at(x2) end
			end
			best = math.min(best, d[k], f1, f2)
		end
	end
	return best
end

test("hermiteScale: quarter circle equals the vanilla r * 4 * (sqrt(2) - 1)", function()
	near(geom.hermiteScale(PI / 2), 4 * (math.sqrt(2) - 1), 1e-12)
	-- 3x the Bezier control distance (4/3) tan(theta/4)
	near(geom.hermiteScale(PI / 3), 3 * (4 / 3) * math.tan(PI / 12), 1e-12)
end)

test("hermite arcs stay on the circle (radial error < 0.03 %)", function()
	local r = 30
	for _, theta in ipairs({ PI / 2, PI / 3, 72 * PI / 180, PI / 4, 0.2 }) do
		local s = geom.hermiteScale(theta) * r
		local p0, p1 = { r, 0, 0 }, { r * math.cos(theta), r * math.sin(theta), 0 }
		local t0 = { 0, s, 0 }
		local t1 = { -s * math.sin(theta), s * math.cos(theta), 0 }
		near(len(hermite(p0, t0, p1, t1, 0.5)), r, 1e-12, "midpoint exactly on the circle")
		for k = 1, 19 do
			local q = hermite(p0, t0, p1, t1, k / 20)
			ok(math.abs(len(q) - r) < 3e-4 * r, "theta " .. theta .. " s " .. k / 20 .. " radius " .. len(q))
		end
	end
end)

test("readParams: defaults and foreign values fall back", function()
	local s = geom.readParams({})
	eq(s.shape, geom.SHAPE_ROUND); eq(s.ovalRatio, 1); eq(s.lanes, 2); eq(s.radius, 20); eq(s.layout, 3)
	eq(s.armType, 1); eq(s.armLength, nil, "no arm length param"); eq(s.direction, geom.DIRECTION_CCW)
	eq(s.island, geom.ISLAND_NONE, "no centre island by default"); eq(s.mini, false)
	s = geom.readParams({ sqrb_shape = 9, sqrb_lanes = 0, sqrb_radius = 99, sqrb_arms = 2.5, sqrb_island = "x" })
	eq(s.shape, geom.SHAPE_ROUND); eq(s.lanes, 2); eq(s.radius, 20); eq(s.layout, 3); eq(s.island, geom.ISLAND_NONE)
	eq(spec({ shape = #geom.SHAPE_RATIOS }).ovalRatio, 2.0)
	eq(spec({ shape = 2 }).ovalRatio, 1.25)
	-- one radius slider: below 15 m it is a mini roundabout
	eq(spec({ radius = 1 }).radius, 8); eq(spec({ radius = 1 }).mini, true)
	eq(spec({ radius = 3 }).radius, 12); eq(spec({ radius = 3 }).mini, true)
	eq(spec({ radius = 4 }).radius, 15); eq(spec({ radius = 4 }).mini, false)
end)

test("ring centreline radius = radius + vanilla street offset", function()
	for lanes = 1, 3 do
		local b = build({ lanes = lanes, radius = 6 })
		eq(b.a, 25 + geom.RING_OFFSET[lanes]); eq(b.b, 25 + geom.RING_OFFSET[lanes])
		eq(b.ring.template, geom.RING_TEMPLATES[lanes])
	end
	local o = build({ shape = #geom.SHAPE_RATIOS, radius = 6, lanes = 2 })
	eq(o.a, 50 + 9); eq(o.b, 25 + 9)
end)

test("ring closes: each edge starts where the previous ends, with the same tag", function()
	eachConfig(function(over)
		local e = build(over).ring.edges
		for i = 1, #e do
			local nxt = e[i % #e + 1]
			eq(e[i].p1, nxt.p0, "position continuity")
			eq(e[i].tag1, nxt.tag0, "tag continuity")
			ok(e[i].tag0 ~= nil and e[i].tag1 ~= nil, "ring nodes are tagged")
			-- G1: tangent directions match at the shared node
			local a, b = e[i].t1, nxt.t0
			near(dot(a, b) / (len(a) * len(b)), 1, 1e-9, "tangent direction")
		end
	end)
end)

test("ring nodes lie on the circle / ellipse", function()
	eachConfig(function(over)
		local b = build(over)
		for _, n in ipairs(b.ring.nodes) do
			local x, y = n.pos[1], n.pos[2]
			near(x * x / (b.a * b.a) + y * y / (b.b * b.b), 1, 1e-12)
			eq(n.pos[3], 0)
		end
	end)
end)

test("ring edges span at most 90 degrees and the fewest edges", function()
	local expected = { 4, 6, 4, 5, 6, 4 } -- T: 90/90/180, Y: 3x120, 4: 4x90, 5: 5x72, 6: 6x60, none: 4
	for arms = 1, #geom.ARM_LAYOUTS do
		eq(#build({ arms = arms }).ring.edges, expected[arms], "layout " .. arms)
	end
	eachConfig(function(over)
		local nodes = build(over).ring.nodes
		for i = 1, #nodes do
			local t0 = nodes[i].t
			local t1 = (i == #nodes) and nodes[1].t + 2 * PI or nodes[i + 1].t
			ok(t1 > t0 and t1 - t0 <= PI / 2 + 1e-9, "span " .. (t1 - t0))
		end
	end)
end)

test("ellipse edges approximate the ellipse (affine image of the circle fit)", function()
	local b = build({ shape = #geom.SHAPE_RATIOS, radius = 1, arms = 5 })
	for _, e in ipairs(b.ring.edges) do
		for k = 1, 9 do
			local q = hermite(e.p0, e.t0, e.p1, e.t1, k / 10)
			local f = q[1] * q[1] / (b.a * b.a) + q[2] * q[2] / (b.b * b.b)
			ok(math.abs(math.sqrt(f) - 1) < 3e-4, "normalised radius " .. math.sqrt(f))
		end
	end
end)

test("direction: anticlockwise by default, clockwise reverses every edge", function()
	eachConfig(function(over)
		local e = build(over).ring.edges
		local sign = over.direction == geom.DIRECTION_CW and -1 or 1
		for i = 1, #e do
			ok(sign * cross(e[i].p0, e[i].t0) > 0, "start tangent turns the right way")
			ok(sign * cross(e[i].p1, e[i].t1) > 0, "end tangent turns the right way")
			ok(sign * cross(e[i].p0, e[i].p1) > 0, "edge runs the right way round")
		end
	end)
	local ccw = build({ direction = 1, arms = 4 }).ring.edges
	local cw = build({ direction = 2, arms = 4 }).ring.edges
	eq(#cw, #ccw)
	for i = 1, #ccw do
		local r = cw[#cw + 1 - i]
		eq(r.p0, ccw[i].p1); eq(r.p1, ccw[i].p0)
		eq(r.tag0, ccw[i].tag1); eq(r.tag1, ccw[i].tag0)
		near(r.t0[1], -ccw[i].t1[1], 1e-12); near(r.t1[2], -ccw[i].t0[2], 1e-12)
	end
end)

test("arm counts and angles follow the layout", function()
	local counts = { 3, 3, 4, 5, 6, 0 }
	for arms = 1, #geom.ARM_LAYOUTS do
		local b = build({ arms = arms, shape = 4 })
		eq(#b.arms.edges, counts[arms], "layout " .. arms)
		for i, e in ipairs(b.arms.edges) do
			local phi = geom.ARM_LAYOUTS[arms][i] * PI / 180
			near(math.cos(atan2(e.p0[2], e.p0[1]) - phi), 1, 1e-9, "start on the arm direction")
			-- Phase 3b: the arm leaves along the ring's normal (square to the ring; radial if round)
			local n = geom.armDir(b.a, b.b, phi)
			local d = { e.p1[1] - e.p0[1], e.p1[2] - e.p0[2], 0 }
			near(dot(d, n) / len(d), 1, 1e-9, "arm along the ring normal")
		end
		if arms == 3 then
			local r = build({ arms = arms })
			for i, e in ipairs(r.arms.edges) do
				local phi = geom.ARM_LAYOUTS[arms][i] * PI / 180
				near(math.cos(atan2(e.p1[2], e.p1[1]) - phi), 1, 1e-9, "round: radial")
			end
		end
	end
end)

test("arms start on a ring node with the same tag, run radially outwards", function()
	eachConfig(function(over)
		local b = build(over)
		local s = spec(over)
		local byTag = {}
		for _, n in ipairs(b.ring.nodes) do byTag[n.tag] = n end
		for _, e in ipairs(b.arms.edges) do
			local n = byTag[e.tag0]
			ok(n ~= nil, "arm tag is a ring node tag")
			eq(e.p0, n.pos, "arm starts exactly on the ring node")
			ok(n.arm ~= nil, "that ring node is an arm node")
			eq(e.tag1, nil, "arm end is a loose node")
			near(dist(e.p0, e.p1), b.halfWidth + geom.ARM_LENGTH, 1e-9, "reaches ARM_LENGTH past the ring edge")
			ok(dot(e.p0, { e.p1[1] - e.p0[1], e.p1[2] - e.p0[2] }) > 0, "points outwards")
			eq(e.t0, e.t1, "straight edge")
			near(len(e.t0), dist(e.p0, e.p1), 1e-9, "tangent length = edge length")
		end
		eq(b.arms.template, geom.ARM_TEMPLATES[s.armType])
	end)
end)

test("ring tags are unique per node", function()
	local seen = {}
	for _, n in ipairs(build({ arms = 5 }).ring.nodes) do
		ok(not seen[n.tag], "duplicate " .. n.tag)
		seen[n.tag] = true
	end
end)

test("templates are base-game templates (absolute :: paths)", function()
	for _, list in ipairs({ geom.RING_TEMPLATES, geom.ARM_TEMPLATES }) do
		for _, t in ipairs(list) do
			ok(t:find("::/infrastructure/street/", 1, true) == 1, t)
			ok(t:find("_new_", 1, true) ~= nil, t)
		end
	end
end)

test("island: none, grass, trees, fountain, paved", function()
	eq(build({ island = geom.ISLAND_NONE }).island, nil)
	local g = build({ island = geom.ISLAND_GRASS })
	eq(#g.island.faces, 1); eq(#g.island.colliders, 1)
	eq(g.island.faces[1].fill, geom.GTEX_GRASS); eq(g.island.faces[1].stroke, nil); eq(#g.island.models, 0)
	local p = build({ island = geom.ISLAND_PAVED })
	eq(p.island.faces[1].fill, geom.GTEX_PAVING_FILL); eq(p.island.faces[1].stroke, geom.GTEX_PAVING_STROKE)
	local t = build({ island = geom.ISLAND_TREES, radius = #geom.RADII })
	ok(#t.island.models > 4, "big island gets trees and bushes")
	eq(t.island.models[1].id, geom.MODEL_TREE)
	local f = build({ island = geom.ISLAND_FOUNTAIN })
	eq(f.island.models[1].id, geom.MODEL_FOUNTAIN)
end)

test("mini roundabouts (radius below 15 m): trees and fountain become a flat paved island", function()
	for _, kind in ipairs({ geom.ISLAND_TREES, geom.ISLAND_FOUNTAIN }) do
		for radius = 1, 3 do
			for _, shape in ipairs({ geom.SHAPE_ROUND, #geom.SHAPE_RATIOS }) do
				local b = build({ radius = radius, shape = shape, island = kind })
				eq(b.island.kind, geom.ISLAND_PAVED); eq(#b.island.models, 0)
			end
		end
		eq(build({ radius = 4, island = kind }).island.kind, kind, "15 m keeps the chosen island")
	end
	eq(build({ radius = 1, island = geom.ISLAND_GRASS }).island.kind, geom.ISLAND_GRASS)
end)

test("island outline keeps the margin to the ring road and is anticlockwise", function()
	-- quick runs (no TEST_FULL) check a sample of the configs (checks.sampled), --full every one
	checks.sampled(eachConfig, 5, checks.defaultCase(spec))(function(over)
		over.island = geom.ISLAND_TREES
		local b = build(over)
		local isl = b.island
		ok(isl ~= nil, "every config has room for an island")
		local d = b.halfWidth + geom.ISLAND_MARGIN
		local area = 0
		eq(#isl.faces, 1)
		local outline = isl.faces[1].outline
		for i, p in ipairs(outline) do
			local q = outline[i % #outline + 1]
			area = area + cross(p, q)
			near(distToEllipse(p, b.a, b.b), d, 0.02, "offset distance")
		end
		ok(area > 0, "counter-clockwise face")
	end)
end)

test("island collider and models stay inside the outline", function()
	eachConfig(function(over)
		over.island = spec(over).mini and geom.ISLAND_PAVED or geom.ISLAND_TREES
		local isl = build(over).island
		local c = isl.colliders[1]
		eq(c.type, "CYLINDER"); eq(c.x, 0); eq(c.y, 0); eq(c.hz, geom.COLLIDER_HEIGHT / 2)
		local outline = isl.faces[1].outline
		for k = 0, 179 do
			local t = 2 * PI * k / 180
			ok(pointInPolygon(c.hx * math.cos(t) * 0.999, c.hy * math.sin(t) * 0.999, outline), "collider inside outline")
		end
		for _, m in ipairs(isl.models) do
			ok(pointInPolygon(m.x, m.y, outline), "model inside outline")
		end
	end)
end)

test("toEdgeEntries / allNodes: two entries per edge, every node free", function()
	local edges = build({ arms = 3 }).ring.edges
	local entries = geom.toEdgeEntries(edges)
	eq(#entries, 2 * #edges)
	eq(entries[1][1], edges[1].p0); eq(entries[1][2], edges[1].t0); eq(entries[1][3], edges[1].tag0)
	eq(entries[2][1], edges[1].p1); eq(entries[2][3], edges[1].tag1)
	local free = geom.allNodes(entries)
	eq(#free, #entries); eq(free[1], 0); eq(free[#free], #entries - 1)
end)

test("transf: column-major rotation about z plus translation", function()
	local m = geom.transf(3, 4, 5, PI / 2)
	near(m[1], 0, 1e-12); near(m[2], 1, 1e-12); near(m[5], -1, 1e-12); near(m[6], 0, 1e-12)
	eq({ m[13], m[14], m[15], m[16] }, { 3, 4, 5, 1 })
end)
