-- Phase 5c (PHASE5.md): hamburger / through-about on the main entry.
--   * "Through the centre" = "Road + traffic lights" (sqrb_centre 4): the Road geometry plus
--     experimental signals at the two ring nodes the through road crosses (ring and through lists);
--   * "Through road" (sqrb_through_road): the through road's template ("Same as arms" or an arm
--     road), with the ring growth, island halves, engine model and overlaps sized to it.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")
local K = geom.PARAM_KEYS
local S = geom.shapes

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local G = loadfile(here .. "golden.lua", "t", _ENV)()
local V = loadfile(here .. "verdicts.lua", "t", _ENV)()
local ENGINE = V.loadAll(here .. "../../plans/square_roundabouts/")
local judged = V.judge(geom, ENGINE.trials, ENGINE.sweep)

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end

local function params(over)
	local p = {}
	for k, v in pairs(over or {}) do p[K[k]] = v end
	return p
end
local function spec(over) return geom.readParams(params(over)) end
local function build(over) return geom.build(spec(over)) end

local function copy(t, extra)
	local o = {}
	for k, v in pairs(t) do o[k] = v end
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

local function each(grid, fn)
	local keys = {}
	for k in pairs(grid) do keys[#keys + 1] = k end
	table.sort(keys)
	local function rec(i, over)
		if i > #keys then return fn(copy(over)) end
		for _, v in ipairs(grid[keys[i]]) do
			over[keys[i]] = v
			rec(i + 1, over)
		end
	end
	rec(1, {})
end

-- Quick runs (no TEST_FULL) check every stride-th case of a sweep plus the first of each value the
-- stride misses and the default (checks.sampled); --full checks every case.
local isDefault = checks.defaultCase(function(o) return geom.readParams(params(o)) end)
local function sampledEach(stride, grid, fn)
	checks.sampled(function(f) each(grid, f) end, stride, isDefault)(fn)
end

local function range(n) local t = {}; for i = 1, n do t[i] = i end; return t end
local function from(a, b) local t = {}; for i = a, b do t[#t + 1] = i end; return t end

local function label(over)
	local keys, parts = {}, {}
	for k in pairs(over) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(over[k]) end
	return table.concat(parts, " ")
end

local function roleLists(b, role)
	local out = {}
	for _, l in ipairs(b.lists) do if l.role == role then out[#out + 1] = l end end
	return out
end

-- Overlaps: the through road and the ring may share a junction stretch of up to THROUGH_RING m
-- along each (default limit: 30 m). Same-as-arms through roads on 2:1 ovals already needed more
-- than 30 m (town large, 1-4 lanes: 29-36 m), and the engine accepted every one of them in the
-- Phase 3b sweep (probe_results.csv, e.g. m:5,3,1,1,1,2,3,1 at 45 m: 36.0 m); 40 m covers every
-- through road (Phase 5c notes). Other pairs keep the default.
local THROUGH_RING = 40
local function overlapLimit(A, B, default)
	if (A.role == "through" and B.role == "ring") or (A.role == "ring" and B.role == "through") then
		return math.max(default, THROUGH_RING)
	end
	return default
end

local function dot(p, q) return p[1] * q[1] + p[2] * q[2] end

local function text(v) return table.concat(V.text(v)) end

-- the lists without the signal fields (Road + traffic lights = Road geometry)
local function plainLists(b)
	local out = {}
	for i, l in ipairs(b.lists) do
		local c = copy(l)
		c.signalYes, c.signalPref, c.nodes = nil, nil, nil
		out[i] = c
	end
	return out
end

local THROUGH_ROADS = from(2, 1 + #geom.ARM_TEMPLATES)

test("readParams: Road + traffic lights and Through road; foreign values fall back", function()
	local s = geom.readParams({})
	eq(s.centre, geom.CENTRE_NONE); eq(s.throughRoad, geom.THROUGH_SAME); eq(s.throughType, s.armType)
	s = spec({ centre = 4, throughRoad = 4, armType = 2 })
	eq(s.centre, geom.CENTRE_ROAD_LIGHTS); eq(s.throughType, 3)
	s = spec({ centre = 2, throughRoad = 1, armType = 5 })
	eq(s.throughType, 5, "Same as arms follows the arm road")
	for _, bad in ipairs({ 0, 8, 1.5, "x" }) do
		s = geom.readParams({ [K.throughRoad] = bad, [K.armType] = 2, [K.centre] = 5 })
		eq(s.throughRoad, geom.THROUGH_SAME); eq(s.throughType, 2); eq(s.centre, geom.CENTRE_NONE)
	end
	-- the pattern key (tuning table) of Road + traffic lights is Road's; another through road than
	-- the arm road appends its arm road index (Phase 5f), Same as arms / the arm road itself does not
	eq(geom.basePatternKey(spec({ centre = 4, throughRoad = 3 })), geom.patternKey(spec({ centre = 2 })))
	eq(geom.patternKey(spec({ centre = 4, throughRoad = 3 })), geom.patternKey(spec({ centre = 2 })) .. ",2")
	eq(geom.patternKey(spec({ centre = 4, throughRoad = 3 })), geom.patternKey(spec({ centre = 2, throughRoad = 3 })))
	eq(geom.patternKey(spec({ centre = 2, throughRoad = 2 })), geom.patternKey(spec({ centre = 2 })), "the arm road = Same as arms")
	eq(geom.patternKey(spec({ centre = 3, throughRoad = 3 })), geom.basePatternKey(spec({ centre = 3 })), "tram line: no through road")
	eq(geom.centreRoad(spec({ centre = 2 })), true); eq(geom.centreRoad(spec({ centre = 4 })), true)
	eq(geom.centreRoad(spec({ centre = 3 })), false); eq(geom.centreRoad(spec({ centre = 1 })), false)
	eq(geom.throughOwnRoad(spec({ centre = 2, throughRoad = 2 })), false, "town small = the default arm road")
	eq(geom.throughOwnRoad(spec({ centre = 4, throughRoad = 3 })), true)
	eq(geom.throughOwnRoad(spec({ centre = 3, throughRoad = 3 })), false, "tram line: no effect")
end)

test("Same as arms, or the arm road chosen explicitly: exactly the build before Phase 5c", function()
	local groups, order = G.mainGroups(K)
	local main = loadData("square_roundabouts.script.lua").updateFn
	for _, name in ipairs(order) do
		for i, p in ipairs(groups[name]) do
			if i % (checks.FULL and 7 or 29) == 1 then
				local ref = text(main({}, p))
				local explicit = copy(p, { [K.throughRoad] = p[K.armType] + 1 })
				eq(text(main({}, explicit)), ref, name .. " #" .. i .. " explicit arm road")
				eq(text(main({}, copy(p, { [K.throughRoad] = geom.THROUGH_SAME }))), ref, name .. " #" .. i)
			end
		end
	end
end)

test("Through road has no effect with Nothing or Tram line (accepted precedent)", function()
	sampledEach(3, { arms = { 1, 3, 6 }, centre = { 1, 3 }, splitter = { 1, 2 }, tram = { 1, 2 }, radius = { 1, geom.DEFAULT_RADIUS },
		island = { 1, 3 } }, function(over)
		local ref = text(result.build(build(over)))
		for _, tt in ipairs(THROUGH_ROADS) do
			eq(text(result.build(build(copy(over, { throughRoad = tt })))), ref, label(over) .. " through " .. tt)
		end
	end)
end)

for lanes = 1, 3 do
test("Road + traffic lights: the Road geometry, signals on the two crossing nodes (ring + through lists), " .. lanes .. " lane(s)", function()
	sampledEach(7, { shape = { 1, #geom.SHAPE_RATIOS }, lanes = { lanes }, arms = range(#geom.ARM_LAYOUTS), direction = { 1, 2 },
		splitter = { 1, 2 }, tram = { 1, 2 }, throughRoad = { 1, 4 }, island = { 1, 3 } }, function(over)
		local name = label(over)
		local road = build(copy(over, { centre = 2 }))
		local b = build(copy(over, { centre = 4 }))
		eq(text(plainLists(b)), text(plainLists(road)), "same roads: " .. name)
		eq(text(b.island), text(road.island), "same island: " .. name)
		eq(b.radius, road.radius)
		eq(road.ring.signalYes, nil); eq(road.ring.signalPref, nil)
		local tl = roleLists(b, "through")
		eq(#tl, 1)
		local t0, t1 = b.through.tag0, b.through.tag1
		eq(tl[1].signalYes, { t0 }, name); eq(tl[1].signalPref, { t1 }, name)
		eq(b.ring.signalYes, { t0 }, name); eq(b.ring.signalPref, { t1 }, name)
		-- the nodes are the through axis ring nodes
		local byTag = {}
		for _, n in ipairs(b.ring.nodes) do byTag[n.tag] = n end
		ok(byTag[t0].kind == "P" and byTag[t0].arm == b.axis[1], name)
		ok(byTag[t1].kind == "P" and byTag[t1].arm == b.axis[2], name)
		-- no other list asks for lights
		for _, l in ipairs(b.lists) do
			if l ~= b.ring and l ~= tl[1] then eq(l.signalYes, nil); eq(l.signalPref, nil) end
		end
	end)
end)
end

test("Road + traffic lights in the result: both ring entries of each crossing node, the through road's end", function()
	local main = loadData("square_roundabouts.script.lua").updateFn
	for arms = 1, #geom.ARM_LAYOUTS do
		for _, signals in ipairs({ 1, 2 }) do
			for _, splitter in ipairs({ 1, 2 }) do
				local over = { arms = arms, centre = 4, signals = signals, splitter = splitter, throughRoad = 3 }
				local name = label(over)
				local b = build(over)
				local res = main({}, params(over))
				eq(#res.edgeLists, #b.lists)
				local ringEl, throughEl
				for i, l in ipairs(b.lists) do
					if l == b.ring then ringEl = res.edgeLists[i] end
					if l.role == "through" then throughEl = res.edgeLists[i] end
				end
				local t0, t1 = b.through.tag0, b.through.tag1
				local function tagsOf(el, idx)
					local out = {}
					for _, i in ipairs(idx) do
						local tag = el.edges[i + 1][3]
						out[tag] = (out[tag] or 0) + 1
					end
					return out
				end
				local prefIdx = {}
				for _, p in ipairs(ringEl.trafficLightNodePreference) do
					eq(p[2], "YES"); prefIdx[#prefIdx + 1] = p[1]
				end
				local yes, pref = tagsOf(ringEl, ringEl.trafficLightYes), tagsOf(ringEl, prefIdx)
				-- a ring node is the end of one ring edge and the start of the next: two entries
				if signals == 1 then
					eq(yes, { [t0] = 2 }, name); eq(pref, { [t1] = 2 }, name)
				else
					-- with Traffic lights = Entries too: the crossing nodes are listed once, in one field
					ok((yes[t0] or pref[t0]) == 2 and not (yes[t0] and pref[t0]), name)
					ok((yes[t1] or pref[t1]) == 2 and not (yes[t1] and pref[t1]), name)
					for tag, n in pairs(yes) do eq(n, 2, name); eq(pref[tag], nil, "a node in both fields: " .. name) end
					for _, n in pairs(pref) do eq(n, 2, name) end
				end
				eq(throughEl.trafficLightYes, { 0 }, name)
				eq(throughEl.trafficLightNodePreference, { { 1, "YES" } }, name)
				eq(throughEl.edges[1][3], t0); eq(throughEl.edges[2][3], t1)
				for _, el in ipairs(res.edgeLists) do
					if el ~= ringEl and el ~= throughEl then
						eq(el.trafficLightYes, nil); eq(el.trafficLightNodePreference, nil)
					end
				end
			end
		end
	end
	-- Road (no lights) and Traffic lights Off: no signal field anywhere
	for _, el in ipairs(main({}, params({ centre = 2, throughRoad = 3 })).edgeLists) do
		eq(el.trafficLightYes, nil); eq(el.trafficLightNodePreference, nil)
	end
end)

test("through road template: the chosen road (tram variant with Tram tracks On), arms keep theirs", function()
	for _, centre in ipairs({ 2, 4 }) do
		for armType = 1, #geom.ARM_TEMPLATES do
			for _, tt in ipairs(THROUGH_ROADS) do
				for _, tram in ipairs({ 1, 2 }) do
					local over = { centre = centre, armType = armType, throughRoad = tt, tram = tram }
					local b = build(over)
					local road = tt - 1
					local tl = roleLists(b, "through")
					eq(#tl, 1)
					local want = tram == 2 and geom.ARM_TRAM[road] or { template = geom.ARM_TEMPLATES[road] }
					eq(tl[1].template, want.template, label(over))
					eq(tl[1].tramTrackType, want.tramTrackType, label(over))
					eq(tl[1].halfWidth, geom.ARM_HALF_WIDTH[road])
					eq(geom.throughHalfWidth(b.spec), geom.ARM_HALF_WIDTH[road])
					for _, l in ipairs(roleLists(b, "arms")) do
						eq(l.template, (tram == 2 and geom.ARM_TRAM[armType] or { template = geom.ARM_TEMPLATES[armType] }).template)
					end
				end
			end
		end
	end
end)

-- The through-road sweep: every layout, lanes, round / 2:1, small / default / large radius,
-- splitter, tram tracks, every arm road x every other through road (Road + traffic lights has
-- the Road geometry, tested above, so the sweep builds it with lights).
local SWEEP = {
	shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 2, 3 }, arms = range(#geom.ARM_LAYOUTS),
	radius = { 1, geom.DEFAULT_RADIUS }, splitter = { 1, 2 }, armType = { 1, 3, 5 },
	throughRoad = THROUGH_ROADS, centre = { 4 },
}
-- part of the sweep (one shape and lane count, so the runner can shard it), sampled in quick runs
local function sweep(shape, lanes, stride, fn)
	local grid = copy(SWEEP, { shape = { shape }, lanes = { lanes } })
	sampledEach(stride, grid, function(over)
		if over.throughRoad - 1 ~= over.armType then fn(over) end
	end)
end
local function eachPart(fn)
	for _, shape in ipairs(SWEEP.shape) do
		for _, lanes in ipairs(SWEEP.lanes) do
			fn(shape, lanes, string.format("shape %d, %d lane(s)", shape, lanes))
		end
	end
end

eachPart(function(shape, lanes, part)
test("through roads: ring growth uses the through road's half width; fits without fallback, minimal growth (" .. part .. ")", function()
	local n, grown, floors = 0, 0, 0
	sweep(shape, lanes, 11, function(over)
		local s = spec(over)
		local b = geom.build(s)
		local name = label(over)
		n = n + 1
		local arms = geom.armsFor(s)
		-- an exact engine radius only from the through road's own pattern (p5_hamburger_radius,
		-- Phase 5f); elsewhere the arm-road pattern's radius is a floor (V.GAPS.through)
		if b.engine == "radius" or b.engine == "inferred" then
			ok(geom.tuning.radius[geom.patternKey(s)] ~= nil, "engine radius used as exact: " .. name)
		end
		-- the offline model judges it, except an exact engine radius, a layout a sweep accepted, or a
		-- pending splitter floor no radius fits offline (V.GAPS.splitter, as without a through road)
		local pending = b.engine == "floor" and b.offline == false
		if pending or b.engine == "radius" then ok(judged(b), "who judges: " .. name) end
		ok(not b.forced, "forced: " .. name)
		ok(geom.plan(b.spec, b.radius, arms) ~= nil or judged(b), "fits at " .. b.radius .. ": " .. name)
		ok(b.radius >= s.radius, name)
		if b.floor then floors = floors + 1 end
		-- minimal: no smaller slider radius from the chosen one (above an engine floor) fits
		if not b.engine then
			for i = s.radiusIndex, #geom.RADII do
				local r = geom.RADII[i]
				if r >= b.radius then break end
				if not b.floor or r > b.floor then eq(geom.plan(b.spec, r, arms), nil, "a smaller radius fitted: " .. name) end
			end
		end
		-- the through strip: every ring node off the axis keeps the through road's half width clear
		local w = S.norm({ -(b.through.p1[2] - b.through.p0[2]), b.through.p1[1] - b.through.p0[1], 0 })
		local hwT = geom.ARM_HALF_WIDTH[over.throughRoad - 1]
		-- (not where the engine judges: it accepted e.g. 12 m rings with 4 lanes and country small through)
		for _, nd in ipairs(judged(b) and {} or b.ring.nodes) do
			if nd.tag ~= b.through.tag0 and nd.tag ~= b.through.tag1 then
				ok(math.abs(dot(nd.pos, w)) >= hwT + b.halfWidth + geom.LEG_CLEARANCE - 1e-9, "node in the through strip: " .. name)
			end
		end
		if b.radius > build(copy(over, { throughRoad = geom.THROUGH_SAME })).radius then grown = grown + 1 end
	end)
	print(string.format("    %d builds; %d grow over the same layout with the arm road through; %d above an engine floor", n, grown, floors))
end)
end)

-- (split from the test above so the runner can shard them)
test("through roads: at the largest slider radius no through road forces a plan the arm road would not", function()
	-- the largest slider radius: a through road never forces a plan the arm road would not (Phase
	-- 5c: 2:1, 4 lanes, Y / 5 arms, large arms with splitters were forced from 45 m whatever the
	-- through road; Phase 5f splits those along the ring normal, geom.splitAxis: none forced now)
	local forced = 0
	sampledEach(5, { shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 3 }, arms = range(#geom.ARM_LAYOUTS), radius = { #geom.RADII },
		splitter = { 1, 2 }, armType = { 1, 3, 6 }, throughRoad = THROUGH_ROADS, centre = { 4 } }, function(over)
		local b = build(over)
		if b.forced then
			forced = forced + 1
			ok(build(copy(over, { throughRoad = geom.THROUGH_SAME })).forced, "forced only with this through road: " .. label(over))
		end
	end)
	print(string.format("    at %d m: %d builds forced as with the arm road through", geom.RADII[#geom.RADII], forced))
	-- a wider road through a small ring makes it grow
	ok(build({ centre = 4, radius = 1, throughRoad = 4, lanes = 1 }).radius > build({ centre = 4, radius = 1, lanes = 1 }).radius)
end)

eachPart(function(shape, lanes, part)
test("through roads: tags, edge lengths, engine model (" .. part .. ")", function()
	-- the engine model (slow with wide roads) at the smallest slider radius: the tightest rings
	sweep(shape, lanes, 11, function(over)
		local b = build(over)
		local name = label(over)
		checks.report(checks.tags(b.lists), name)
		checks.report(checks.lengths(b.lists, geom.MIN_EDGE), name)
		if over.radius == 1 and not judged(b) then checks.report(checks.engineModel(b.lists, b.halfWidth), name) end
	end)
end)
end)

-- (split from the test above so the runner can shard them; same grids and checks)
test("through roads: overlaps on the tightest rings", function()
	-- overlaps (slow) on a smaller grid: the smallest slider radius (the tightest rings)
	sampledEach(3, { shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 3 }, arms = { 1, 3 }, radius = { 1 },
		splitter = { 1, 2 }, armType = { 1, 3 }, throughRoad = THROUGH_ROADS, centre = { 4 } }, function(over)
		if over.throughRoad - 1 == over.armType then return end
		local b = build(over)
		if not judged(b) then checks.report(checks.overlaps(b.lists, 0.5, nil, overlapLimit), label(over)) end
	end)
end)

test("through roads: tram tracks and clockwise: tags, engine model", function()
	-- tram tracks and clockwise on a smaller grid (tram templates have the plain widths and
	-- clockwise mirrors the ring: the engine model only)
	sampledEach(5, { shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 3 }, arms = { 1, 3, 6 }, radius = { 1, geom.DEFAULT_RADIUS },
		splitter = { 1, 2 }, armType = { 1, 4 }, throughRoad = { 4, 7 }, centre = { 2 }, tram = { 2 }, direction = { 1, 2 } }, function(over)
		local b = build(over)
		local name = label(over)
		checks.report(checks.tags(b.lists), name)
		if not judged(b) then checks.report(checks.engineModel(b.lists, b.halfWidth), name) end
	end)
end)

for _, lanes in ipairs({ 1, 3 }) do
test("through roads: island halves sized to the through road, colliders and models inside, clear of roads, " .. lanes .. " lane(s)", function()
	sampledEach(7, { shape = { 1, #geom.SHAPE_RATIOS }, lanes = { lanes }, arms = { 1, 2, 3 },
		radius = { 1, geom.DEFAULT_RADIUS, #geom.RADII }, armType = { 1, 4 }, throughRoad = THROUGH_ROADS,
		centre = { 4 }, splitter = { 1, 2 }, island = { geom.ISLAND_TREES, geom.ISLAND_PAVED } }, function(over)
		local b = build(over)
		local name = label(over)
		local isl = b.island
		if isl then
			checks.report(checks.islandClear(b.lists, isl, geom.ISLAND_MARGIN - 0.25), name)
			local w = S.norm({ -(b.through.p1[2] - b.through.p0[2]), b.through.p1[1] - b.through.p0[1], 0 })
			local c = geom.ARM_HALF_WIDTH[over.throughRoad - 1] + geom.ISLAND_MARGIN
			local halves = 0
			for _, f in ipairs(isl.faces) do
				-- the centre halves touch the through road's strip edge; splitter triangles lie outside the ring
				local q = f.outline[1]
				local inner = (q[1] / b.a) ^ 2 + (q[2] / b.b) ^ 2 < 1
				if inner then
					halves = halves + 1
					ok(S.area(f.outline) > 0, "anticlockwise")
					local closest = math.huge
					for _, p in ipairs(f.outline) do closest = math.min(closest, math.abs(dot(p, w))) end
					ok(closest >= c - 1e-9, "half island clear of the through road: " .. name)
					ok(closest <= c + 0.5, "half island reaches the through road's kerb: " .. closest .. " " .. name)
				end
			end
			ok(halves <= 2, name)
			for _, col in ipairs(isl.colliders) do
				eq(col.type, "BOX")
				local inside = false
				for _, f in ipairs(isl.faces) do
					local e = { math.cos(col.rot), math.sin(col.rot), 0 }
					local nrm = { -e[2], e[1], 0 }
					local all = true
					for _, sx in ipairs({ -1, 1 }) do
						for _, sy in ipairs({ -1, 1 }) do
							local x = col.x + e[1] * col.hx * sx + nrm[1] * col.hy * sy
							local y = col.y + e[2] * col.hx * sx + nrm[2] * col.hy * sy
							if not S.pointInPolygon(x, y, f.outline) then all = false end
						end
					end
					inside = inside or all
				end
				ok(inside, "box collider inside a half: " .. name)
			end
			for _, m in ipairs(isl.models) do
				local fits = false
				for _, f in ipairs(isl.faces) do fits = fits or S.fits(m.x, m.y, geom.MODEL_RADIUS[m.id] - 1e-6, f.outline) end
				ok(fits, "model clear of the island edge: " .. name)
			end
		end
	end)
	-- a wider through road leaves smaller halves on the same ring
	local small = build({ centre = 4, radius = #geom.RADII, island = geom.ISLAND_GRASS, throughRoad = 2 })
	local large = build({ centre = 4, radius = #geom.RADII, island = geom.ISLAND_GRASS, throughRoad = 4 })
	eq(small.radius, large.radius)
	eq(#small.island.faces, 2); eq(#large.island.faces, 2)
	ok(S.area(large.island.faces[1].outline) < S.area(small.island.faces[1].outline), "halves shrink")
end)
end

test(".con.lua: Road + traffic lights appended, Through road after Through the centre", function()
	local con = loadData("square_roundabouts.con.lua")
	local byKey, pos = {}, {}
	for i, p in ipairs(con.params) do byKey[p.key] = p; pos[p.key] = i end
	local c = byKey[K.centre]
	eq(c.values, { "Nothing", "Road", "Tram line", "Road + traffic lights" })
	eq(c.uiType, "ComboBox")
	ok(c.tooltip:find("(experimental)", 1, true) ~= nil, "lights marked experimental")
	local t = byKey[K.throughRoad]
	eq(pos[K.throughRoad], pos[K.centre] + 1)
	eq(t.uiType, "ComboBox")
	eq(t.values[1], "Same as arms")
	eq(#t.values, 1 + #geom.ARM_TEMPLATES)
	for i, v in ipairs(byKey[K.armType].values) do eq(t.values[i + 1], v) end
	eq(t.defaultIndex, geom.THROUGH_SAME)
	eq(K.throughRoad, "sqrb_through_road")
end)
