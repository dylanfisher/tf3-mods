-- Magic Roundabout geometry (square_roundabouts_magic.lua).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local S = geom.shapes

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local function build(over)
	local p = {}
	for k, v in pairs(over or {}) do p[magic.PARAM_KEYS[k]] = v end
	return magic.build(magic.readParams(p))
end

local function each(fn)
	for armType = 1, #geom.ARM_TEMPLATES do
		for size = 1, #magic.SIZES do
			for direction = 1, 2 do
				for lanes = 1, magic.LANE_CHOICES do
					fn({ armType = armType, size = size, direction = direction, island = geom.ISLAND_TREES, lanes = lanes })
				end
			end
		end
	end
end

test("readParams: defaults", function()
	local s = magic.readParams({})
	eq(s, { size = magic.DEFAULT_SIZE, armType = 1, direction = geom.DIRECTION_CCW, island = geom.ISLAND_NONE, lanes = 1 })
	eq(magic.readParams({ sqrb_magic_lanes = 2 }).lanes, 2)
	eq(magic.readParams({ sqrb_magic_lanes = 3 }).lanes, 1, "out of range: 1 lane")
	eq(magic.readParams({ sqrb_magic_size = 9, sqrb_arm_type = 0 }).size, magic.DEFAULT_SIZE)
	eq(magic.readParams({ sqrb_magic_size = 1 }).size, 1)
	-- the default is the smallest, XS (2026-10-09; was the original layout, M: 12 m satellites 52 m out)
	eq(magic.DEFAULT_SIZE, 1); eq(magic.SIZES[magic.DEFAULT_SIZE].radius, 8); eq(magic.SIZES[magic.DEFAULT_SIZE].distance, 40)
end)

test("five satellites, five links, five arms; base templates", function()
	local b = build()
	eq(#b.satellites, 5); eq(#b.links, 5); eq(#b.arms, 5)
	eq(b.lists[1].template, geom.RING_TEMPLATES[1])
	eq(b.lists[2].template, magic.LINK.template)
	eq(b.lists[3].template, geom.ARM_TEMPLATES[1])
	eq(build({ armType = 6 }).lists[3].template, geom.ARM_TEMPLATES[6])
	for i, sat in ipairs(b.satellites) do
		near(S.len(sat.centre), b.distance, 1e-9)
		local deg = magic.FIRST_DEG + 72 * (i - 1)
		near(math.cos(math.atan(sat.centre[2], sat.centre[1]) - deg * math.pi / 180), 1, 1e-9)
	end
end)

test("tags, edge lengths >= 10 m, no overlaps, islands clear of the roads", function()
	each(function(over)
		local b = build(over)
		local name = over.armType .. "/" .. over.size .. "/" .. over.direction .. "/" .. over.lanes .. " lanes"
		checks.report(checks.tags(b.lists), name)
		checks.report(checks.lengths(b.lists, geom.MIN_EDGE), name)
		checks.report(checks.overlaps(b.lists, 0.5), name)
		checks.report(checks.islandClear(b.lists, b.island, geom.ISLAND_MARGIN - 0.25), name)
	end)
end)

test("satellites circulate in the chosen direction; links join neighbouring satellites", function()
	for direction = 1, 2 do
		local b = build({ direction = direction })
		local sign = direction == geom.DIRECTION_CW and -1 or 1
		for _, sat in ipairs(b.satellites) do
			for _, e in ipairs(sat.edges) do
				local r0 = S.sub(e.p0, sat.centre)
				ok(sign * S.cross(r0, e.t0) > 0, "satellite direction")
				near(S.len(r0), b.rs, 1e-9)
			end
		end
		for i, l in ipairs(b.links) do
			eq(l.tag0, b.satellites[i].plus.tag)
			eq(l.tag1, b.satellites[i % 5 + 1].minus.tag)
			near(S.len(l.p0), b.distance, 1e-9); near(S.len(l.p1), b.distance, 1e-9)
			-- a link is an arc of the link circle
			for k = 1, 9 do
				local p = checks.hermite(l, k / 10)
				ok(math.abs(S.len(p) - b.distance) < 0.01, "on the link circle")
			end
		end
		for i, a in ipairs(b.arms) do
			eq(a.tag0, b.satellites[i].out.tag)
			eq(a.tag1, nil)
			ok(S.dot(a.p0, S.sub(a.p1, a.p0)) > 0, "arm points outwards")
			near(S.dist(a.p0, a.p1), b.halfWidth + geom.ARM_LENGTH, 1e-9, "fixed arm length past the satellite")
		end
	end
end)

test("islands: none by default; centre star + flat satellite islands; models inside", function()
	eq(build().island, nil)
	local b = build({ island = geom.ISLAND_TREES })
	local isl = b.island
	eq(#isl.faces, 6)
	eq(isl.faces[1].fill, geom.GTEX_GRASS)
	for i = 2, 6 do eq(isl.faces[i].fill, geom.GTEX_PAVING_FILL, "satellites are minis: paved") end
	ok(#isl.models > 5)
	for _, m in ipairs(isl.models) do
		ok(S.fits(m.x, m.y, 0, isl.faces[1].outline), "model in the centre island (mini satellites: none)")
	end
	local c = isl.colliders[1]
	for k = 0, 35 do
		local t = 2 * math.pi * k / 36
		ok(S.pointInPolygon(c.hx * math.cos(t), c.hy * math.sin(t), isl.faces[1].outline), "collider inside")
	end
	for i = 2, 6 do
		local sc = isl.colliders[i]
		local sat = b.satellites[i - 1]
		near(sc.x, sat.centre[1], 1e-9); near(sc.y, sat.centre[2], 1e-9)
	end
	eq(build({ island = geom.ISLAND_GRASS }).island.faces[2].fill, geom.GTEX_GRASS)
	-- Size 4 and 5: satellites of 20 / 35 m are no longer minis: trees on them too
	for size = 4, 5 do
		local big = build({ size = size, island = geom.ISLAND_TREES })
		eq(big.mini, false)
		for i = 2, 6 do eq(big.island.faces[i].fill, geom.GTEX_GRASS) end
		local onSat = 0
		for _, m in ipairs(big.island.models) do
			local inCentre = S.pointInPolygon(m.x, m.y, big.island.faces[1].outline)
			local inSat = false
			for i = 2, 6 do inSat = inSat or S.fits(m.x, m.y, geom.MODEL_RADIUS[m.id] - 1e-6, big.island.faces[i].outline) end
			ok(inCentre or inSat, "model on an island")
			if inSat then onSat = onSat + 1 end
		end
		ok(onSat >= 5, "every satellite has models")
	end
end)

test("size scales the whole layout", function()
	local prev
	for size = 1, #magic.SIZES do
		local b = build({ size = size })
		eq(b.size, size)
		eq(b.rs, magic.SIZES[size].radius + geom.RING_OFFSET[magic.SAT_LANES])
		eq(b.distance, magic.SIZES[size].distance)
		eq(b.mini, magic.SIZES[size].radius < geom.MINI_RADIUS_BELOW)
		if prev then ok(b.distance > prev.distance and b.rs > prev.rs, "grows with the size") end
		prev = b
	end
end)

test("2-lane minis: one-way small town road, wider ring; Large at least, at or above the engine floor", function()
	each(function(over)
		if over.lanes ~= 2 then return end
		local name = over.armType .. "/" .. over.size .. "/" .. over.direction
		local two = build(over)
		over.lanes = 1
		local one = build(over)
		eq(two.lists[1].template, geom.RING_TEMPLATES[2], name)
		eq(two.lists[2].template, magic.LINK.template, name .. ": links unchanged")
		eq(two.halfWidth, geom.RING_HALF_WIDTH[2], name)
		eq(two.rs, magic.SIZES[two.size].radius + geom.RING_OFFSET[2], name)
		-- not >= one.size: the engine took 2-lane Medium even with large arms, where 1 lane needs
		-- Large (search_magic_sizes), so the 2-lane rows are their own floors
		ok(two.size >= (magic.sizeFloor({ armType = over.armType, direction = over.direction, size = over.size, lanes = 2 }) or 1), name .. ": engine floor")
		eq(one.lists[1].template, geom.RING_TEMPLATES[1], name)
		ok(two.size >= 4, name .. ": 2 lanes need Large (offline fit)")
	end)
	-- the 1-lane default is untouched by the new param
	eq(build().lists[1].template, geom.RING_TEMPLATES[1])
	eq(build({ lanes = 1 }).rs, build().rs)
end)

test("sizeFloor: 2-lane rows by arm,dir,2; else the 1-lane row", function()
	local spec = { armType = 3, direction = 2, size = 1, lanes = 2 }
	geom.setTuning({ radius = {}, splitter = {}, magic = { ["3,2"] = { [1] = 4 } } })
	local okRun, err = pcall(function()
		eq(magic.sizeFloor(spec), 4, "falls back to the 1-lane row")
		geom.tuning.magic["3,2,2"] = { [1] = 5 }
		eq(magic.sizeFloor(spec), 5, "own 2-lane row")
		spec.lanes = 1
		eq(magic.sizeFloor(spec), 4, "1 lane ignores 2-lane rows")
	end)
	geom.setTuning(nil)
	if not okRun then error(err, 0) end
end)
