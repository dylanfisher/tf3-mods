-- stress_entry_streets.lua: the Lights showcase's town entry roundabout (square_stress_test_entry.con.lua).
-- In game 2026-10-12 (log 2026-10-12_2343_top-up-563524) square_roundabouts' Roundabout ended its arms 62 m out,
-- inside the far grid nodes' junction areas: every entry "Collision (hits 12 other BASE_NODE)". These tests
-- pin the footprint that keeps it clear of them.

local entry = ug_require "square_stress_test::/stress/stress_entry_streets.lua"
local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"

local function negZero(v) return v == 0 and 1 / v < 0 end

local function key(p) return string.format("%.3f,%.3f", p[1], p[2]) end

test("the construction's script returns the geometry's result; its file is the one the window resolves", function()
	ug_require "square_stress_test::/infrastructure/street_construction/square_stress_test_entry.script.lua"
	local r = data().updateFn({}, { seed = 1 })
	eq(r, entry.result({}))
	eq(logic.ENTRY_FILE, "square_stress_test_entry.con")
	eq(logic.ENTRY_CASE.file, logic.ENTRY_FILE)
	local h = assert(io.open("mods/square_stress_test/content/" .. logic.JUNCTION_DIR .. logic.ENTRY_FILE .. ".lua"))
	h:close()
	eq(logic.showcaseArms(logic.ENTRY_CASE), { 0, 90, 180, 270 })
end)

test("a 2-lane one-way ring (4 quarters, anticlockwise) and four country large arms on the axes, ending at ENTRY_REACH", function()
	local r = entry.result({})
	eq(#r.edgeLists, 2)
	local ring, arms = r.edgeLists[1], r.edgeLists[2]
	eq(ring.params.type, entry.RING_TEMPLATE)
	eq(arms.params.type, entry.ARM_TEMPLATE)
	eq(arms.params.type, "::/infrastructure/street/country/country_new_large.street_template")
	-- a country one-way ring: no houses on it or its island (2026-10-13: the town street ring got a tower)
	eq(ring.params.type, "::/infrastructure/street/highway/highway_new_medium.street_template")
	eq(#ring.edges, 8)
	eq(#arms.edges, 8)
	for _, l in ipairs(r.edgeLists) do
		eq(l.type, "STREET")
		eq(#l.snapNodes, 0)
		eq(#l.freeNodes, #l.edges, "every node free")
		for i, f in ipairs(l.freeNodes) do eq(f, i - 1) end
	end
	-- ring: on the circle, anticlockwise (cross product of position and tangent > 0), tangents of the quarter value
	local t = entry.RING_RADIUS * 4 * (math.sqrt(2) - 1)
	local ringNodes = {}
	for i = 1, #ring.edges do
		local p, tan = ring.edges[i][1], ring.edges[i][2]
		near(math.sqrt(p[1] ^ 2 + p[2] ^ 2), entry.RING_RADIUS, 1e-9)
		ok(p[1] * tan[2] - p[2] * tan[1] > 0, "anticlockwise")
		near(math.sqrt(tan[1] ^ 2 + tan[2] ^ 2), t, 1e-9)
		ringNodes[key(p)] = true
	end
	-- every ring quarter ends where the next starts (one node each)
	for k = 1, 4 do eq(key(ring.edges[2 * k][1]), key(ring.edges[(2 * k) % 8 + 1][1])) end
	-- arms: start at a ring node, straight out along an axis, end at REACH
	local dirs = {}
	for k = 1, 4 do
		local a, b = arms.edges[2 * k - 1], arms.edges[2 * k]
		ok(ringNodes[key(a[1])], "arm starts at a ring node")
		near(math.sqrt(b[1][1] ^ 2 + b[1][2] ^ 2), logic.ENTRY_REACH, 1e-9)
		ok(b[1][1] == 0 or b[1][2] == 0, "on an axis")
		eq(a[2], b[2], "straight")
		dirs[#dirs + 1] = math.floor(math.deg((math.atan2 or math.atan)(b[1][2], b[1][1])) % 360 + 0.5)
	end
	table.sort(dirs)
	eq(dirs, { 0, 90, 180, 270 })
	eq(entry.REACH, logic.ENTRY_REACH)
end)

test("no -0 and nothing that is not finite anywhere in the output", function()
	local r = entry.result({})
	for _, l in ipairs(r.edgeLists) do
		for _, e in ipairs(l.edges) do
			for _, v in ipairs(e) do
				for k = 1, 3 do
					ok(not negZero(v[k]), "no -0")
					ok(v[k] == v[k] and math.abs(v[k]) < 1e6, "finite")
				end
			end
		end
	end
end)

test("the footprint: the ring clears the arms' start, every arm end stays outside the far grid nodes' junction areas with room for a join", function()
	-- the ring's outer edge comes before the arm end (an arm of at least 10 m beyond it)
	ok(entry.REACH - (entry.RING_RADIUS + entry.RING_HALF_WIDTH) >= 10)
	-- a Medium grid (the Lights showcase's): the far nodes lie one block out; the widest grid street's half width
	-- (town large, 32 m) is their junction area's reach; an arm end inside it collided in game
	local _, step = grid.lines(logic.gridHalfOfSize(logic.LIGHTS_SIZE))
	ok(logic.ENTRY_FAR_CLEAR >= 16, "half of the 32 m town street")
	ok(step - logic.ENTRY_FAR_CLEAR - logic.ENTRY_REACH >= logic.ENTRY_MIN_JOIN, "a join clear of the far junction: " .. step)
	-- square_roundabouts' 62 m arms would not pass the check that every entry now has to pass
	ok(not (step >= 62 + logic.ENTRY_FAR_CLEAR + logic.ENTRY_MIN_JOIN), "the old reach is refused by the block check")
end)

test("clockwise (sqst_entry_dir = 2, left-hand traffic): the same ring and arms, every quarter reversed, no -0", function()
	local ccw, cw = entry.result({}), entry.result({ [entry.KEYS.dir] = entry.DIR_CW })
	eq(entry.result({ [entry.KEYS.dir] = entry.DIR_CCW }), ccw)
	eq(cw.edgeLists[2], ccw.edgeLists[2], "arms unchanged")
	eq(cw.edgeLists[1].params, ccw.edgeLists[1].params)
	local ring, ringCcw = cw.edgeLists[1].edges, ccw.edgeLists[1].edges
	eq(#ring, 8)
	local t = entry.RING_RADIUS * 4 * (math.sqrt(2) - 1)
	local nodesCw, nodesCcw = {}, {}
	for i = 1, #ring do
		local p, tan = ring[i][1], ring[i][2]
		near(math.sqrt(p[1] ^ 2 + p[2] ^ 2), entry.RING_RADIUS, 1e-9)
		ok(p[1] * tan[2] - p[2] * tan[1] < 0, "clockwise")
		near(math.sqrt(tan[1] ^ 2 + tan[2] ^ 2), t, 1e-9)
		for k = 1, 3 do ok(not negZero(p[k]) and not negZero(tan[k]), "no -0") end
		nodesCw[key(p)] = true
		nodesCcw[key(ringCcw[i][1])] = true
	end
	eq(nodesCw, nodesCcw, "the same four ring nodes (the arms meet them)")
	-- each clockwise quarter is an anticlockwise one run backwards: its ends swapped, tangents negated
	for k = 1, 4 do
		local a, b = ring[2 * k - 1], ring[2 * k]
		local found = false
		for m = 1, 4 do
			local c, d = ringCcw[2 * m - 1], ringCcw[2 * m]
			if key(a[1]) == key(d[1]) and key(b[1]) == key(c[1]) then
				found = true
				near(a[2][1], -d[2][1], 1e-12)
				near(a[2][2], -d[2][2], 1e-12)
				near(b[2][1], -c[2][1], 1e-12)
				near(b[2][2], -c[2][2], 1e-12)
			end
		end
		ok(found, "quarter " .. k .. " reversed")
	end
	-- a closed one-way ring: each quarter ends where the one before it (in list order) starts
	for k = 1, 4 do eq(key(ring[2 * k][1]), key(ring[2 * ((k + 2) % 4) + 1][1])) end
	ok(entry.clockwise({ sqst_entry_dir = 2 }))
	ok(not entry.clockwise({ sqst_entry_dir = 1 }) and not entry.clockwise({}) and not entry.clockwise(nil))
end)

test("the construction: its year and its direction param (1-based, default anticlockwise)", function()
	ug_require "square_stress_test::/infrastructure/street_construction/square_stress_test_entry.con.lua"
	local d = data()
	eq(d.availability.yearFrom, 1940)
	eq(d.availability.yearFrom, logic.ENTRY_FROM_YEAR)
	eq(#d.params, 4)
	eq(d.params[1].key, "sqst_entry_dir")
	eq(d.params[1].values[d.params[1].defaultIndex], "Anticlockwise")
	eq(d.params[2].key, "sqst_entry_ring")
	eq(d.params[2].values, { "2 lanes", "3 lanes" })
	eq(d.params[2].values[d.params[2].defaultIndex], "2 lanes")
	eq(d.params[3].key, "sqst_entry_in_axis")
	eq(#d.params[3].values, 5)
	eq(d.params[3].values[d.params[3].defaultIndex], "None")
	eq(d.params[4].key, "sqst_entry_in_reach")
	eq(d.params[4].values, { "46 m", "42 m", "38 m", "36 m" })
end)

test("drivingSide: right / left from a two-way street's road lanes; nil for one-way, mixed or too few", function()
	eq(logic.drivingSide({ false, false, true, true }), "right")
	eq(logic.drivingSide({ false, true }), "right")
	eq(logic.drivingSide({ true, true, false, false }), "left")
	eq(logic.drivingSide({ true, true, true }), nil)
	eq(logic.drivingSide({ false, true, false, true }), nil)
	eq(logic.drivingSide({ true }), nil)
	eq(logic.drivingSide({}), nil)
	eq(logic.drivingSide(nil), nil)
end)

test("the inward arm: one axis ends at an IN_REACHES value, the other three at REACH; nothing else changes; no -0", function()
	eq(entry.IN_REACHES, logic.ENTRY_IN_REACHES)
	eq(entry.IN_REACHES[1], entry.REACH, "the first try is the full reach")
	for k = 2, #entry.IN_REACHES do ok(entry.IN_REACHES[k] < entry.IN_REACHES[k - 1], "descending") end
	-- the shortest still reaches 3 m beyond the ring's outer edge
	ok(entry.IN_REACHES[#entry.IN_REACHES] >= entry.RING_RADIUS + entry.RING_HALF_WIDTH + 3)
	-- no axis / out of range: every arm at REACH
	for _, p in ipairs({ {}, { sqst_entry_in_axis = 1 }, { sqst_entry_in_axis = 6 }, { sqst_entry_in_axis = 2.5 } }) do
		eq(entry.result(p), entry.result({}))
	end
	local base = entry.result({})
	for ax = 1, 4 do
		for ri, reach in ipairs(entry.IN_REACHES) do
			for _, dir in ipairs({ 1, 2 }) do
				local r = entry.result({ sqst_entry_in_axis = ax + 1, sqst_entry_in_reach = ri, sqst_entry_dir = dir })
				eq(r.edgeLists[1], entry.result({ sqst_entry_dir = dir }).edgeLists[1], "ring unchanged")
				local arms = r.edgeLists[2].edges
				for k = 1, 4 do
					local a, b = arms[2 * k - 1], arms[2 * k]
					local len = math.sqrt(b[1][1] ^ 2 + b[1][2] ^ 2)
					near(len, k == ax and reach or entry.REACH, 1e-9)
					eq(a[1], base.edgeLists[2].edges[2 * k - 1][1], "starts at the same ring node")
					near(math.sqrt(a[2][1] ^ 2 + a[2][2] ^ 2), len - entry.RING_RADIUS, 1e-9)
					-- straight and outwards along its own axis: end = start + tangent, both tangents the same, pointing away
					-- from the centre (2026-10-13 screenshot "arms bent outward": not the geometry, town streets on the ends)
					near(b[1][1], a[1][1] + a[2][1], 1e-9)
					near(b[1][2], a[1][2] + a[2][2], 1e-9)
					eq(a[2], b[2])
					ok(a[1][1] * a[2][1] + a[1][2] * a[2][2] > 0, "outwards")
					for _, v in ipairs({ a[1], a[2], b[1], b[2] }) do
						for c = 1, 3 do ok(not negZero(v[c]), "no -0") end
					end
				end
			end
		end
	end
	-- an unreadable reach index falls back to the first (full) reach
	eq(entry.result({ sqst_entry_in_axis = 2, sqst_entry_in_reach = 9 }), entry.result({ sqst_entry_in_axis = 2, sqst_entry_in_reach = 1 }))
end)

test("axisIndex: the inward axis of each side, nil off the axes", function()
	eq(logic.axisIndex({ 1, 0 }), 1)
	eq(logic.axisIndex({ 0, 1 }), 2)
	eq(logic.axisIndex({ -1, 0 }), 3)
	eq(logic.axisIndex({ 0, -1 }), 4)
	eq(logic.axisIndex({ -1, -0.0 }), 3)
	eq(logic.axisIndex({ 0.7, 0.7 }), nil)
	eq(logic.axisIndex(nil), nil)
end)

test("the 3-lane ring (sqst_entry_ring = 2): highway_new_large at 22 m, island and arms clear; every axis x reach x direction: on the circle, tangents, straight outward arms, no -0", function()
	eq(logic.ENTRY_RINGS, { 2, 1 }, "biggest first")
	eq(logic.ENTRY_RING_LANES, { entry.RINGS[1].lanes, entry.RINGS[2].lanes })
	eq(logic.ENTRY_RING_RADIUS, { entry.RINGS[1].radius, entry.RINGS[2].radius })
	local big = entry.RINGS[2]
	eq(big.template, "::/infrastructure/street/highway/highway_new_large.street_template")
	eq({ big.radius, big.half, big.lanes }, { 22, 11.5, 3 })
	ok(big.radius - big.half >= 8, "an island inside the ring")
	-- its outer edge no wider than the 2-lane ring's by more than 1 m: the same block and far-node clearances hold
	ok(big.radius + big.half <= entry.RINGS[1].radius + entry.RINGS[1].half + 1)
	-- the shortest inward arm still ends beyond its outer edge
	ok(entry.IN_REACHES[#entry.IN_REACHES] >= big.radius + big.half + 2.5)
	-- unknown ring index: the 2-lane ring
	eq(entry.result({ sqst_entry_ring = 7 }), entry.result({}))
	eq(entry.result({ sqst_entry_ring = 1.5 }), entry.result({}))
	local t = big.radius * 4 * (math.sqrt(2) - 1)
	for ax = 1, 4 do
		for ri, reach in ipairs(entry.IN_REACHES) do
			for _, dir in ipairs({ 1, 2 }) do
				local r = entry.result({ sqst_entry_ring = 2, sqst_entry_in_axis = ax + 1, sqst_entry_in_reach = ri, sqst_entry_dir = dir })
				local ring, arms = r.edgeLists[1], r.edgeLists[2]
				eq(ring.params.type, big.template)
				eq(arms.params.type, entry.ARM_TEMPLATE)
				local nodes = {}
				for i = 1, #ring.edges do
					local p, tan = ring.edges[i][1], ring.edges[i][2]
					near(math.sqrt(p[1] ^ 2 + p[2] ^ 2), big.radius, 1e-9)
					near(math.sqrt(tan[1] ^ 2 + tan[2] ^ 2), t, 1e-9)
					local cr = p[1] * tan[2] - p[2] * tan[1]
					ok(dir == 1 and cr > 0 or dir == 2 and cr < 0, "direction")
					for k = 1, 3 do ok(not negZero(p[k]) and not negZero(tan[k]), "no -0") end
					nodes[key(p)] = true
				end
				for k = 1, 4 do
					local a, b = arms.edges[2 * k - 1], arms.edges[2 * k]
					ok(nodes[key(a[1])], "arm at a ring node")
					near(math.sqrt(b[1][1] ^ 2 + b[1][2] ^ 2), k == ax and reach or entry.REACH, 1e-9)
					near(b[1][1], a[1][1] + a[2][1], 1e-9)
					near(b[1][2], a[1][2] + a[2][2], 1e-9)
					eq(a[2], b[2])
					ok(a[1][1] * a[2][1] + a[1][2] * a[2][2] > 0, "outwards")
					for _, v in ipairs({ a[1], a[2], b[1], b[2] }) do
						for c = 1, 3 do ok(not negZero(v[c]), "no -0") end
					end
				end
			end
		end
	end
end)
