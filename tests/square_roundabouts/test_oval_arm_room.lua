-- Arm room on small 1-lane ovals (rev 7, 2026-10-12). A wide arm leaving the tight end of a
-- small oval met the ring's outer kerb behind its node: the Stress Test Showcase's
-- "Oval roundabout" (1.25:1, XS, 1 lane, country large T arms, no splitter) grew to 15 m and was
-- refused in game ("Construction Not Possible"); checks.engineModel flagged
-- "arms#1 / arms#3: a junction corner 1.4 m behind its node (> 1.0)". geom.plan now keeps a
-- plain arm's kerb corner within geom.ARM_BEHIND_PLAN of its node, so such a ring grows on (not
-- in the patterns whose radius the engine judged, geom.radiusSearched: round and 2:1 rings).
-- Sweep: every oval, 1 ring lane, radius sizes XS-M, splitter off, every arm road, arms layout,
-- centre, tram and direction (the builds the 2026-10-12 sweep flagged, and their neighbours).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local K = geom.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
-- A build at a radius the engine accepted for its pattern is the engine's call (test_junctions.lua),
-- and so is a pattern whose radius the probe searched (geom.radiusSearched: the 2:1 ovals; the
-- engine accepted Y arms there with corners 2.1 m behind; clockwise copies are not "judged")
local V = loadfile(here .. "verdicts.lua", "t", _ENV)()
local ENGINE = V.loadAll(here .. "../../plans/square_roundabouts/")
local judged = V.judge(geom, ENGINE.trials, ENGINE.sweep)

local function build(p)
	local over = {}
	for k, v in pairs(p) do over[K[k] or k] = v end
	return geom.build(geom.readParams(over))
end

local function label(p)
	return string.format("shape %d, size %d, arms %d, arm road %d, centre %d, tram %d, dir %d",
		p.shape, p.sqrb_radius_size, p.arms, p.armType, p.centre, p.tram, p.direction)
end

test("the arm-room rule leaves engine-searched patterns alone, applies to the never-probed ovals", function()
	-- 2:1, 1 lane, Y arms, town large at 8 m: the engine accepted the grown 12 m (corners 2.1 m behind)
	local y = build({ shape = 5, lanes = 1, radius = 1, arms = 2, armType = 3, splitter = 1 })
	ok(geom.radiusSearched(y.spec)); eq(y.radius, 12)
	for shape = 2, 4 do
		ok(not geom.radiusSearched(geom.readParams({ [K.shape] = shape, [K.lanes] = 1, [K.arms] = 2, [K.armType] = 3 })), "shape " .. shape)
	end
end)

test("Showcase oval (1.25:1, XS, 1 lane, country large T, no splitter) grows until the arms fit", function()
	local p = { sqrb_arm_type = 6, sqrb_arms = 3, sqrb_centre = 1, sqrb_island = 3, sqrb_lanes = 1, sqrb_radius_size = 1,
		sqrb_shape = 2, sqrb_signals = 1, sqrb_splitter = 1, sqrb_tram = 2 }
	local b = geom.build(geom.readParams(p))
	eq(#checks.engineModel(b.lists, b.halfWidth), 0, table.concat(checks.engineModel(b.lists, b.halfWidth), "; "))
	ok(b.radius > 15, "radius " .. b.radius .. " (rev 6: 15 m, corners 1.4 m behind)")
	eq(b.forced, nil)
end)

for shape = 2, #geom.SHAPE_RATIOS do
	test("1-lane oval " .. shape .. ", sizes XS-M, no splitter: no plain arm corner behind its node", function()
		local bad, n = {}, 0
		for size = 1, 3 do for arms = 1, #geom.ARM_LAYOUTS do for armType = 1, #geom.ARM_TEMPLATES do
		for centre = 1, 4 do for tram = 1, 2 do for direction = 1, 2 do
			local p = { shape = shape, lanes = 1, sqrb_radius_size = size, arms = arms, armType = armType,
				splitter = 1, centre = centre, tram = tram, direction = direction }
			local b = build(p)
			n = n + 1
			if not (judged(b) or geom.radiusSearched(b.spec)) then
				local pr = checks.engineModel(b.lists, b.halfWidth)
				if #pr > 0 then bad[#bad + 1] = label(p) .. " (R " .. b.radius .. "): " .. table.concat(pr, "; ") end
			end
			if b.forced then bad[#bad + 1] = label(p) .. ": forced fallback" end
		end end end end end end
		eq(n, 3 * #geom.ARM_LAYOUTS * #geom.ARM_TEMPLATES * 4 * 2 * 2)
		eq(#bad, 0, #bad .. " builds:\n" .. table.concat(bad, "\n", 1, math.min(#bad, 10)))
	end)
end
