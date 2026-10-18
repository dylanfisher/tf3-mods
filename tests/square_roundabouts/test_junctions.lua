-- Junction room (Phase 3b): wide roads must not eat whole edges at a junction.
-- In game (2026-10-07) the Magic Roundabout and splitter islands failed with town/country large
-- arms ("Construction not possible") while small and medium worked. checks.junctionRoom is the
-- offline model of that: kerb corners between neighbouring roads at every node, the free length
-- each edge keeps between its two junctions, and how far a corner lies behind a road's node.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local S = geom.shapes
local K = geom.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local LARGE = { [3] = true, [6] = true } -- town large, country large

-- The Phase 3b model (free 4.5 m, corner behind 6 m), kept for the calibration replay below.
local function room3b(lists) return checks.junctionRoom(lists, geom.JUNCTION_FREE) end
-- Shipped builds: the engine-fitted model (checks.engineModel, Phase 4b). A build the engine
-- judges (verdicts.lua V.judge: an exact engine radius, a radius the engine accepted for the
-- pattern, or a pending engine floor) is checked by the engine replay instead
-- (test_engine_verdicts.lua): the model has a few false alarms there (2.49 m free, 2.1 m corners).
local V = loadfile(here .. "verdicts.lua", "t", _ENV)()
local ENGINE = V.loadAll(here .. "../../plans/square_roundabouts/")
local judged = V.judge(geom, ENGINE.trials, ENGINE.sweep)
local function room(b)
	if judged(b) then return {} end
	return checks.engineModel(b.lists, b.halfWidth)
end
local function overlaps(b)
	if judged(b) then return {} end
	return checks.overlaps(b.lists, 0.5)
end
local EMPTY = { radius = {}, magic = {}, splitter = {} }

-- The Magic Roundabout as built before Phase 3b (12 m satellites 52 m out, even ring nodes, arms
-- 20 m), to replay the in-game results.
local function oldMagic(armType)
	local rs, hwS, D = 17, 4.5, 52
	local dTheta = 2 * math.asin(rs / (2 * D))
	local step = 2 * math.pi / 5
	local sats, satEdges, arms, links = {}, {}, {}, {}
	for i = 1, 5 do
		local theta = math.pi / 2 + (i - 1) * step
		local c = S.scale(S.dir(theta), D)
		local plus, minus = S.scale(S.dir(theta + dTheta), D), S.scale(S.dir(theta - dTheta), D)
		local function localT(p) return S.wrap(S.atan2(p[2] - c[2], p[1] - c[1])) end
		local anchorPos = { S.add(c, S.scale(S.dir(theta), rs)), plus, minus }
		local ts, at = geom.ringParams({ S.wrap(theta), localT(plus), localT(minus) })
		local nodes, by = {}, {}
		for k, t in ipairs(ts) do
			nodes[k] = { pos = at[k] and anchorPos[at[k]] or S.add(c, S.scale(S.dir(t), rs)), tag = i .. "_" .. k, t = t }
			if at[k] then by[at[k]] = nodes[k] end
		end
		for _, e in ipairs(geom.ringEdges(rs, rs, nodes, 1)) do satEdges[#satEdges + 1] = e end
		arms[#arms + 1] = S.straightEdge(by[1].pos, S.add(by[1].pos, S.scale(S.dir(theta), hwS + 20)), by[1].tag, nil)
		sats[i] = { theta = theta, plus = by[2], minus = by[3] }
	end
	local span = step - 2 * dTheta
	local hs = geom.hermiteScale(span) * D
	for i = 1, 5 do
		local s0, s1 = sats[i], sats[i % 5 + 1]
		local a0 = s0.theta + dTheta
		links[i] = { p0 = s0.plus.pos, t0 = S.scale(S.left(S.dir(a0)), hs), p1 = s1.minus.pos,
			t1 = S.scale(S.left(S.dir(a0 + span)), hs), tag0 = s0.plus.tag, tag1 = s1.minus.tag }
	end
	return {
		{ role = "satellites", halfWidth = hwS, edges = satEdges },
		{ role = "links", halfWidth = 8, edges = links },
		{ role = "arms", halfWidth = geom.ARM_HALF_WIDTH[armType], edges = arms },
	}
end

test("calibration: the junction model reproduces the in-game results of the old layouts", function()
	for armType = 1, #geom.ARM_TEMPLATES do
		local p = room3b(oldMagic(armType))
		eq(#p > 0, LARGE[armType] == true, "old Magic, arm road " .. armType .. ": " .. table.concat(p, "; "))
	end
	-- old splitter: 40 degree fork for every road, arm 10 m past the split (old default length)
	-- (and without the Phase 3b split-node rule, which would widen the fork)
	-- (and without the Phase 4b engine tuning: the old splitter for every arm road)
	local saved = { geom.LEG_FORK_PER_M, geom.LEG_SPREAD_PER_M, geom.ARM_LENGTH, geom.BEHIND_PLAN }
	geom.LEG_FORK_PER_M, geom.LEG_SPREAD_PER_M, geom.ARM_LENGTH, geom.BEHIND_PLAN = 0, 0, 10, math.huge
	geom.setTuning(EMPTY)
	local results = {}
	local okRun, err = pcall(function()
		for armType = 1, #geom.ARM_TEMPLATES do
			local b = geom.build(geom.readParams({ [K.armType] = armType, [K.splitter] = 2 }))
			eq(b.radius, 20); eq(b.spec.forkBump, nil)
			results[armType] = room3b(b.lists)
		end
	end)
	geom.setTuning(nil)
	geom.LEG_FORK_PER_M, geom.LEG_SPREAD_PER_M, geom.ARM_LENGTH, geom.BEHIND_PLAN = saved[1], saved[2], saved[3], saved[4]
	if not okRun then error(err, 0) end
	for armType = 1, #geom.ARM_TEMPLATES do
		eq(#results[armType] > 0, LARGE[armType] == true, "old splitter, arm road " .. armType .. ": " .. table.concat(results[armType], "; "))
	end
end)

test("magic: every size and arm road keeps junction room, no overlaps; tags and lengths", function()
	for size = 1, #magic.SIZES do
		for armType = 1, #geom.ARM_TEMPLATES do
			for direction = 1, 2 do
				local b = magic.build(magic.readParams({ sqrb_magic_size = size, [K.armType] = armType, [K.direction] = direction, [K.island] = geom.ISLAND_TREES }))
				local name = ("size %d -> %d, arm %d, dir %d"):format(size, b.size, armType, direction)
				checks.report(room(b), name)
				checks.report(checks.overlaps(b.lists, 0.5), name)
				checks.report(checks.tags(b.lists), name)
				checks.report(checks.lengths(b.lists, geom.MIN_EDGE), name)
				checks.report(checks.islandClear(b.lists, b.island, geom.ISLAND_MARGIN - 0.25), name)
			end
		end
	end
end)

test("magic: the size grows only as far as the arm road needs", function()
	for size = 1, #magic.SIZES do
		for armType = 1, #geom.ARM_TEMPLATES do
			local spec = magic.readParams({ sqrb_magic_size = size, [K.armType] = armType })
			local b = magic.build(spec)
			ok(b.size >= size, "never smaller")
			ok(magic.layout(spec, b.size) ~= nil, "a real fit, not the forced fallback")
			-- from the engine's size floor (search_magic_sizes: town and country large from Large)
			for s = magic.sizeFloor(spec) or size, b.size - 1 do eq(magic.layout(spec, s), nil, "a smaller size fitted") end
		end
	end
	-- the original layout (Size 3) still takes small and medium arms; the engine needs Size 4 for
	-- town and country large (probe search_magic_sizes); Size 5 takes every road; small arms fit
	-- even the compact layout
	local need = { [3] = 4, [6] = 4 }
	for armType = 1, #geom.ARM_TEMPLATES do
		eq(magic.build(magic.readParams({ sqrb_magic_size = 3, [K.armType] = armType })).size, need[armType] or 3, "arm " .. armType)
		eq(magic.build(magic.readParams({ sqrb_magic_size = 4, [K.armType] = armType })).size, 4)
		eq(magic.build(magic.readParams({ sqrb_magic_size = 5, [K.armType] = armType })).size, 5)
	end
	eq(magic.build(magic.readParams({ sqrb_magic_size = 1 })).size, 1)
	eq(magic.build(magic.readParams({ sqrb_magic_size = 1, [K.armType] = 4 })).size, 1)
end)

local function each(grid, fn)
	local keys = {}
	for k in pairs(grid) do keys[#keys + 1] = k end
	table.sort(keys)
	local function rec(i, over)
		if i > #keys then
			local o = {}
			for k, v in pairs(over) do o[k] = v end
			return fn(o)
		end
		for _, v in ipairs(grid[keys[i]]) do
			over[keys[i]] = v
			rec(i + 1, over)
		end
	end
	rec(1, {})
end

local function range(n) local t = {}; for i = 1, n do t[i] = i end; return t end

local function label(over)
	local keys, parts = {}, {}
	for k in pairs(over) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(over[k]) end
	return table.concat(parts, " ")
end

local function specOf(over)
	local p = {}
	for k, v in pairs(over) do p[K[k]] = v end
	return geom.readParams(p)
end
local function buildMain(over) return geom.build(specOf(over)) end

-- Quick runs (no TEST_FULL) check every stride-th case of a sweep plus the first of each value the
-- stride misses and the default (checks.sampled); --full checks every case.
local isDefault = checks.defaultCase(specOf)
local function sampledEach(stride, grid, fn)
	checks.sampled(function(f) each(grid, f) end, stride, isDefault)(fn)
end

-- (split by lane count, so the runner can shard them)
for lanes = 1, 3 do
test("splitter islands: every arm road keeps junction room, " .. lanes .. " lane(s)", function()
	sampledEach(7, { armType = { 1, 2, 3, 4, 5, 6 }, arms = { 1, 2, 3, 4, 5 }, lanes = { lanes }, radius = { 1, geom.DEFAULT_RADIUS },
		direction = { 1, 2 }, shape = { 1, #geom.SHAPE_RATIOS } }, function(over)
		over.splitter = 2
		local b = buildMain(over)
		checks.report(room(b), label(over))
	end)
end)
end
for _, lanes in ipairs({ 1, 3 }) do
for _, armType in ipairs({ 3, 6 }) do
test("splitter islands: large arms do not overlap, edges >= 10 m, " .. lanes .. " lane(s), arm road " .. armType, function()
	sampledEach(7, { armType = { armType }, arms = { 1, 2, 3, 4, 5 }, lanes = { lanes }, radius = { 1, geom.DEFAULT_RADIUS },
		direction = { 1, 2 }, shape = { 1, #geom.SHAPE_RATIOS }, tram = { 1, 2 } }, function(over)
		over.splitter = 2
		local b = buildMain(over)
		checks.report(overlaps(b), label(over))
		checks.report(checks.lengths(b.lists, geom.MIN_EDGE), label(over))
	end)
end)
end
end

test("splitter islands: large arms fork wider; small and medium keep the tested 40 degrees", function()
	for armType = 1, #geom.ARM_TEMPLATES do
		local fork, spread = geom.legShape(geom.readParams({ [K.armType] = armType }))
		if LARGE[armType] then
			ok(fork > geom.LEG_FORK and spread > geom.LEG_SPREAD, "arm " .. armType)
		else
			eq(fork, geom.LEG_FORK); eq(spread, geom.LEG_SPREAD)
		end
	end
	-- the default 4-arm ring keeps 20 m for small and medium arms; large arms make it grow
	for armType = 1, #geom.ARM_TEMPLATES do
		local b = buildMain({ armType = armType, splitter = 2 })
		if LARGE[armType] then ok(b.radius > 20, "arm " .. armType) else eq(b.radius, 20, "arm " .. armType) end
	end
end)

test("plain arms, through road, tram line: every arm road keeps junction room", function()
	sampledEach(5, { armType = { 1, 2, 3, 4, 5, 6 }, arms = { 1, 2, 3, 4, 5, 6 }, lanes = { 1, 2, 3 }, radius = { 1, 3, geom.DEFAULT_RADIUS },
		shape = { 1, #geom.SHAPE_RATIOS }, centre = { 1, 2, 3 } }, function(over)
		local b = buildMain(over)
		checks.report(room(b), label(over))
	end)
end)

test("plain arms: no road overlaps another outside their junctions, for every arm road", function()
	sampledEach(5, { armType = { 1, 2, 3, 4, 5, 6 }, arms = { 1, 2, 3, 4, 5 }, lanes = { 1, 2, 3 }, radius = { 1, 3 },
		shape = { 1, #geom.SHAPE_RATIOS } }, function(over)
		local b = buildMain(over)
		checks.report(checks.overlaps(b.lists, 0.5), label(over))
	end)
end)

-- (one test per lane count, so the runner can shard them)
for lanes = 1, 3 do
test("every combination fits without the forced fallback (growth may go past the slider's 60 m), " .. lanes .. " lane(s)", function()
	local fails, pending = {}, 0
	sampledEach(7, { armType = range(#geom.ARM_TEMPLATES), arms = range(#geom.ARM_LAYOUTS), lanes = { lanes },
		shape = { 1, 3, #geom.SHAPE_RATIOS }, tram = { 1, 2 }, centre = { 1, 2, 3 }, splitter = { 1, 2 }, radius = { 1 } }, function(over)
		local s = specOf(over)
		local b = geom.build(s)
		-- an engine radius the offline model rejects is the layout the engine accepted (no fallback);
		-- an engine floor the offline model rejects everywhere waits for the engine (counted)
		local fits = b.offline == false and (b.engine == "radius" or b.engine == "splitter")
			or geom.plan(b.spec, b.radius, geom.armsFor(s)) ~= nil
		if b.engine == "floor" and b.offline == false then
			pending = pending + 1
		elseif (b.forced or not fits) and #fails < 8 then
			fails[#fails + 1] = label(over)
		end
	end)
	eq(#fails, 0, table.concat(fails, "\n"))
	print(string.format("    %d of the swept combos build an engine floor the offline model rejects (pending search_radius_split)", pending))
end)
end

test("growth past the slider's 60 m: only the widest arms with splitter islands", function()
	-- the growth beyond the slider is only for the widest arms with splitter islands
	ok(buildMain({ armType = 3, splitter = 2, arms = 4, lanes = 1, centre = 2 }).radius >= 40)
	eq(buildMain({ armType = 1, splitter = 2, arms = 5 }).radius <= 60, true)
end)
