-- Phase 3 types of the main entry: splitter islands, through road / tram line, tram tracks,
-- experimental signals, plus whole-result checks (tags, edge lengths, overlaps, islands).

local geom = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"
local K = geom.PARAM_KEYS
local S = geom.shapes

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local PI = math.pi

local function spec(over)
	local p = {}
	for k, v in pairs(over or {}) do p[K[k]] = v end
	return geom.readParams(p)
end

local function build(over) return geom.build(spec(over)) end

local function copy(t, extra)
	local o = {}
	for k, v in pairs(t) do o[k] = v end
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

--- Calls fn(over) for the cartesian product of the value lists in grid.
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

local function range(n) local t = {}; for i = 1, n do t[i] = i end; return t end

local function label(over)
	local keys, parts = {}, {}
	for k in pairs(over) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(over[k]) end
	return table.concat(parts, " ")
end

-- every feature on and off, all layouts and directions, small / default / large radius
local FULL = {
	shape = { geom.SHAPE_ROUND, #geom.SHAPE_RATIOS },
	lanes = { 1, 2, 3 },
	arms = range(#geom.ARM_LAYOUTS),
	direction = { 1, 2 },
	radius = { 1, geom.DEFAULT_RADIUS, #geom.RADII },
	splitter = { 1, 2 },
	centre = { 1, 2, 3 },
	tram = { 1, 2 },
}

local function roleLists(b, role)
	local out = {}
	for _, l in ipairs(b.lists) do if l.role == role then out[#out + 1] = l end end
	return out
end

local function cross(p, q) return p[1] * q[2] - p[2] * q[1] end
local function dot(p, q) return p[1] * q[1] + p[2] * q[2] end
local function unit(v) local l = math.sqrt(v[1] ^ 2 + v[2] ^ 2); return { v[1] / l, v[2] / l, 0 } end

test("readParams: Phase 3 params default to off and reject foreign values", function()
	local s = geom.readParams({})
	eq(s.splitter, geom.SPLITTER_OFF); eq(s.centre, geom.CENTRE_NONE); eq(s.tram, geom.TRAM_OFF); eq(s.signals, geom.SIGNALS_OFF)
	eq(s.radiusIndex, geom.DEFAULT_RADIUS)
	s = geom.readParams({ sqrb_splitter = 3, sqrb_centre = 0, sqrb_tram = "x", sqrb_signals = 1.5 })
	eq(s.splitter, geom.SPLITTER_OFF); eq(s.centre, geom.CENTRE_NONE); eq(s.tram, geom.TRAM_OFF); eq(s.signals, geom.SIGNALS_OFF)
	s = spec({ splitter = 2, centre = 3, tram = 2, signals = 2 })
	eq(s.splitter, geom.SPLITTER_ON); eq(s.centre, geom.CENTRE_TRAM); eq(s.tram, geom.TRAM_ON); eq(s.signals, geom.SIGNALS_ENTRIES)
end)

test("without splitter or through road: ring + arms only; the ring grows only for junction room", function()
	each({ shape = range(#geom.SHAPE_RATIOS), lanes = { 1, 2, 3 }, arms = range(#geom.ARM_LAYOUTS),
		direction = { 1, 2 }, radius = range(#geom.RADII), armType = { 1, 3, 6 } }, function(over)
		local s = spec(over)
		local b = geom.build(s)
		-- Phase 2 behaviour wherever the chosen ring has room for its junctions (and the engine data
		-- does not ask for more: b.engine, Phase 4b)
		if geom.plan(s, s.radius, geom.armsFor(s)) and not b.engine then eq(b.radius, s.radius, label(over)) end
		ok(b.radius >= s.radius, label(over))
		eq(b.lists[1].role, "ring")
		eq(#b.lists, over.arms == #geom.ARM_LAYOUTS and 1 or 2, label(over))
		eq(#b.legs, 0); eq(b.through, nil)
		-- small town arms on 2-lane rings from 15 m (and the default) never grow
		if over.armType == 1 and over.lanes == 2 and s.radius >= 15 and not b.engine then eq(b.radius, s.radius, label(over)) end
	end)
	-- wide arms on a mini ring: it grows (they would eat the ring edges between them)
	ok(build({ radius = 1, lanes = 1, armType = 3 }).radius > 8)
end)

test("all features: tags merge consistently, every edge >= 10 m, ring circulation, fit without fallback", function()
	each(FULL, function(over)
		local s = spec(over)
		local b = geom.build(s)
		local name = label(over)
		checks.report(checks.tags(b.lists), name)
		checks.report(checks.lengths(b.lists, geom.MIN_EDGE), name)
		-- the effective radius is a real fit (geom.choosePlan never fell back to a forced plan), or
		-- an engine radius for exactly this layout (Phase 4b: the engine accepted it there)
		local arms = geom.armsFor(s)
		local engine = b.offline == false and (b.engine == "radius" or b.engine == "splitter")
		ok(not b.forced and (engine or geom.plan(b.spec, b.radius, arms) ~= nil), "fits at " .. b.radius .. ": " .. name)
		ok(b.radius >= s.radius, name)
		-- ring runs the chosen way round
		local sign = s.direction == geom.DIRECTION_CW and -1 or 1
		for _, e in ipairs(b.ring.edges) do
			ok(sign * cross(e.p0, e.t0) > 0 and sign * cross(e.p0, e.p1) > 0, "ring direction " .. name)
		end
		eq(b.lists[1], b.ring)
	end)
end)

test("ring growth: the smallest slider radius >= the chosen one that fits", function()
	each(FULL, function(over)
		local s = spec(over)
		local b = geom.build(s)
		local arms = geom.armsFor(s)
		-- growth starts at the slider, or at an engine floor the offline model checks (Phase 4b);
		-- an exact engine radius ("radius", "splitter") is not grown at all
		if not b.engine then
			for i = s.radiusIndex, #geom.RADII do
				local r = geom.RADII[i]
				if r >= b.radius then break end
				if not b.floor or r > b.floor then eq(geom.plan(s, r, arms), nil, "a smaller radius fitted: " .. label(over)) end
			end
		end
	end)
	-- the default 4-arm, 20 m, 2-lane ring takes splitters as it is; 6 arms need more room
	eq(build({ splitter = 2 }).radius, 20)
	ok(build({ splitter = 2, arms = 5 }).radius > 20, "6 arms with splitters grow")
	ok(build({ splitter = 2, radius = 1 }).radius >= 15, "an 8 m ring grows out of mini size")
	eq(build({ splitter = 2, radius = 1 }).mini, false)
end)

test("splitter legs: one-way entry and exit on the correct sides, joined at a split node on the arm axis", function()
	each({ shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 2, 3 }, arms = range(#geom.ARM_LAYOUTS), direction = { 1, 2 },
		radius = { 1, geom.DEFAULT_RADIUS, #geom.RADII }, centre = { 1, 2 }, tram = { 1, 2 } }, function(over)
		over.splitter = 2
		local s = spec(over)
		local b = geom.build(s)
		local name = label(over)
		local arms = geom.armsFor(s)
		local sigma = s.direction == geom.DIRECTION_CW and -1 or 1
		local nodeByTag = {}
		for _, n in ipairs(b.ring.nodes) do nodeByTag[n.tag] = n end
		local expected = 0
		for _, arm in ipairs(arms) do if not arm.axis then expected = expected + 1 end end
		eq(#b.legs, expected, "every arm off the through axis has legs: " .. name)
		for _, leg in ipairs(b.legs) do
			local arm = arms[leg.arm]
			local u = { math.cos(arm.phi), math.sin(arm.phi), 0 }
			local v = { -u[2], u[1], 0 }
			local p0 = S.ellipsePoint(b.a, b.b, S.paramForAngle(b.a, b.b, arm.phi))
			local E, X = nodeByTag[leg.entry.tag1], nodeByTag[leg.exit.tag0]
			ok(E and E.kind == "E" and E.arm == leg.arm, "entry leg ends on the arm's entry node")
			ok(X and X.kind == "X" and X.arm == leg.arm, "exit leg starts on the arm's exit node")
			eq(leg.entry.tag0, leg.exit.tag1, "legs share the split node")
			eq(leg.entry.p0, leg.split); eq(leg.exit.p1, leg.split)
			near(cross(u, S.sub(leg.split, p0)), 0, 1e-9, "split node on the arm axis")
			ok(dot(S.sub(leg.split, p0), u) > 0)
			-- right-hand traffic (anticlockwise ring): entry on the left of the outward axis
			ok(sigma * dot(E.pos, v) > sigma * dot(leg.split, v), "entry side " .. name)
			ok(sigma * dot(X.pos, v) < sigma * dot(leg.split, v), "exit side " .. name)
			-- merge with the circulation, never against it
			local function frame(n)
				local nrm = S.ellipseNormal(b.a, b.b, n.t)
				local tau = S.scale(S.norm(S.ellipseDeriv(b.a, b.b, n.t)), sigma)
				return nrm, tau
			end
			local nE, tE = frame(E)
			local nX, tX = frame(X)
			ok(dot(leg.entry.t1, tE) > 0 and dot(leg.entry.t1, nE) < 0, "entry joins with the traffic, heading in: " .. name)
			ok(dot(leg.exit.t0, tX) > 0 and dot(leg.exit.t0, nX) > 0, "exit leaves with the traffic, heading out: " .. name)
			ok(dot(leg.entry.t0, u) < 0 and dot(leg.exit.t1, u) > 0, "entry runs in, exit runs out")
			-- the two-way arm continues from the split node
			local armEdge
			for _, e in ipairs(b.arms.edges) do if e.arm == leg.arm then armEdge = e end end
			eq(armEdge.tag0, leg.entry.tag0, "arm starts at the split node")
			near(dot(S.sub(armEdge.p1, armEdge.p0), u), geom.ARM_LENGTH, 1e-9, "arm runs ARM_LENGTH beyond the split")
		end
		local legLists = roleLists(b, "legs")
		if #b.legs > 0 then
			eq(#legLists, 1)
			eq(legLists[1].template, (s.tram == geom.TRAM_ON and geom.LEG_TRAM or geom.LEG).template)
			eq(#legLists[1].edges, 2 * #b.legs)
		else
			eq(#legLists, 0)
		end
	end)
end)

test("fixed arm length: ARM_LENGTH beyond the ring's outer edge, or beyond the split node", function()
	local b = build({})
	for _, e in ipairs(b.arms.edges) do
		near(math.sqrt(e.p1[1] ^ 2 + e.p1[2] ^ 2), b.a + b.halfWidth + geom.ARM_LENGTH, 1e-9)
	end
	b = build({ splitter = 2 })
	for _, e in ipairs(b.arms.edges) do
		near(math.sqrt(e.p1[1] ^ 2 + e.p1[2] ^ 2), b.a + b.halfWidth + geom.SPLIT_LENGTH + geom.ARM_LENGTH, 1e-9)
	end
end)

test("splitter triangles: one per arm with an island chosen, none without", function()
	eq(build({ splitter = 2 }).island, nil, "island None: no triangles")
	local b = build({ splitter = 2, island = geom.ISLAND_GRASS })
	eq(#b.island.faces, 1 + #b.legs, "centre island + a triangle per arm")
	for i = 2, #b.island.faces do
		local f = b.island.faces[i]
		ok(S.area(f.outline) >= geom.ISLAND_MIN_AREA, "triangle area")
		eq(f.fill, geom.GTEX_GRASS)
	end
	eq(#b.island.colliders, 1, "triangles have no collider")
	-- trees: the triangles are plain grass; fountain/paved: paving
	local t = build({ splitter = 2, island = geom.ISLAND_FOUNTAIN })
	eq(t.island.faces[2].fill, geom.GTEX_PAVING_FILL)
	-- triangles exist at every size and direction for the default layout
	each({ radius = range(#geom.RADII), direction = { 1, 2 }, lanes = { 1, 2, 3 }, tram = { 1, 2 } }, function(over)
		over.splitter, over.island = 2, geom.ISLAND_PAVED
		local bb = build(over)
		local tris = #bb.island.faces - (bb.mini and 0 or 0)
		ok(tris >= #bb.legs, "triangles " .. label(over))
	end)
end)

test("through axis: first opposite pair, else an extra arm opposite the first, else east-west", function()
	local expect = {
		{ axis = { 0, 180 }, arms = 3 },   -- T
		{ axis = { 90, 270 }, arms = 4 },  -- Y + south
		{ axis = { 0, 180 }, arms = 4 },   -- 4
		{ axis = { 90, 270 }, arms = 6 },  -- 5 + south
		{ axis = { 0, 180 }, arms = 6 },   -- 6
		{ axis = { 0, 180 }, arms = 2 },   -- none: two new arms
	}
	for layout, x in ipairs(expect) do
		for _, centre in ipairs({ geom.CENTRE_ROAD, geom.CENTRE_TRAM }) do
			local s = spec({ arms = layout, centre = centre })
			local arms, axis = geom.armsFor(s)
			eq(#arms, x.arms, "layout " .. layout)
			eq({ arms[axis[1]].deg, arms[axis[2]].deg }, x.axis, "layout " .. layout)
			local b = geom.build(s)
			eq(#b.arms.edges, x.arms)
		end
		local arms, axis = geom.armsFor(spec({ arms = layout }))
		eq(axis, nil); eq(#arms, #geom.ARM_LAYOUTS[layout])
	end
end)

test("through road: one straight edge between the two opposite axis ring nodes", function()
	each({ shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 2, 3 }, arms = range(#geom.ARM_LAYOUTS), direction = { 1, 2 },
		radius = { 1, geom.DEFAULT_RADIUS, #geom.RADII }, centre = { 2, 3 }, splitter = { 1, 2 }, tram = { 1, 2 } }, function(over)
		local s = spec(over)
		local b = geom.build(s)
		local name = label(over)
		local e = b.through
		ok(e ~= nil, name)
		local byTag = {}
		for _, n in ipairs(b.ring.nodes) do byTag[n.tag] = n end
		local n0, n1 = byTag[e.tag0], byTag[e.tag1]
		ok(n0 and n1 and n0.kind == "P" and n1.kind == "P", "through ends on ring arm nodes: " .. name)
		eq(e.p0, n0.pos); eq(e.p1, n1.pos)
		near(dot(unit(n0.pos), unit(n1.pos)), -1, 1e-9, "opposite: " .. name)
		eq(e.t0, e.t1, "straight")
		local tl = roleLists(b, "through")
		if s.centre == geom.CENTRE_TRAM then
			-- town tram stubs at the ring nodes + a tram-only middle (or stubs only on a short axis)
			ok(#tl == 2 or #tl == 1, name)
			eq(tl[1].template, geom.ARM_TRAM[geom.TRAM_STUB_ARM].template)
			if #tl == 2 then eq(tl[2].template, geom.TRAM_THROUGH.template) end
		elseif s.tram == geom.TRAM_ON then
			eq(tl[1].template, geom.ARM_TRAM[s.armType].template)
		else
			eq(#tl, 1); eq(tl[1].template, geom.ARM_TEMPLATES[s.armType])
		end
		-- the axis arms start on those nodes
		local starts = {}
		for _, a in ipairs(b.arms.edges) do starts[a.tag0] = true end
		ok(starts[e.tag0] and starts[e.tag1], "axis arms continue the through road: " .. name)
	end)
end)

test("through road: island halves beside it, box colliders and models inside them", function()
	each({ shape = { 1, 3, #geom.SHAPE_RATIOS }, lanes = { 1, 2, 3 }, arms = range(#geom.ARM_LAYOUTS),
		radius = { 1, geom.DEFAULT_RADIUS, 9, #geom.RADII }, centre = { 2, 3 }, armType = { 1, 3 },
		island = { geom.ISLAND_TREES, geom.ISLAND_FOUNTAIN } }, function(over)
		local s = spec(over)
		local b = geom.build(s)
		local name = label(over)
		local isl = b.island
		if isl then
			local w = { -(b.through.p1[2] - b.through.p0[2]), b.through.p1[1] - b.through.p0[1], 0 }
			w = unit(w)
			local c = geom.throughHalfWidth(s) + geom.ISLAND_MARGIN
			ok(#isl.faces <= 2, name)
			for _, f in ipairs(isl.faces) do
				ok(S.area(f.outline) > 0, "anticlockwise")
				for _, p in ipairs(f.outline) do
					ok(math.abs(dot(p, w)) >= c - 1e-9, "half island clear of the through road: " .. name)
				end
			end
			for _, col in ipairs(isl.colliders) do
				eq(col.type, "BOX")
				local inside = false
				for _, f in ipairs(isl.faces) do
					local e = { math.cos(col.rot), math.sin(col.rot), 0 }
					local n = { -e[2], e[1], 0 }
					local all = true
					for _, sx in ipairs({ -1, 1 }) do
						for _, sy in ipairs({ -1, 1 }) do
							local x = col.x + e[1] * col.hx * sx + n[1] * col.hy * sy
							local y = col.y + e[2] * col.hx * sx + n[2] * col.hy * sy
							if not S.pointInPolygon(x, y, f.outline) then all = false end
						end
					end
					inside = inside or all
				end
				ok(inside, "box collider inside a half: " .. name)
			end
			for _, m in ipairs(isl.models) do
				local fits = false
				for _, f in ipairs(isl.faces) do
					fits = fits or S.fits(m.x, m.y, geom.MODEL_RADIUS[m.id] - 1e-6, f.outline)
				end
				ok(fits, "model clear of the island edge: " .. name)
			end
		end
	end)
	-- a large ring gets both halves, each with its own tree
	local b = build({ centre = 2, radius = #geom.RADII, island = geom.ISLAND_TREES })
	eq(#b.island.faces, 2); eq(#b.island.colliders, 2)
	local trees = 0
	for _, m in ipairs(b.island.models) do if m.id == geom.MODEL_TREE then trees = trees + 1 end end
	eq(trees, 2)
end)

test("tram: ring, arms, legs and through road templates", function()
	for lanes = 1, 3 do
		for armType = 1, #geom.ARM_TEMPLATES do
			-- tram tracks on: everything tram-capable
			local b = build({ lanes = lanes, armType = armType, tram = 2, splitter = 2, centre = 2, arms = 3 })
			eq(b.ring.template, geom.RING_TRAM[lanes].template)
			eq(b.ring.tramTrackType, geom.RING_TRAM[lanes].tramTrackType)
			for _, l in ipairs(roleLists(b, "arms")) do
				eq(l.template, geom.ARM_TRAM[armType].template); eq(l.tramTrackType, geom.ARM_TRAM[armType].tramTrackType)
			end
			-- the splitter rule's leg (medium/large arms, Phase 4b), tram variant
			eq(roleLists(b, "legs")[1].template, geom.splitParams(b.spec).leg.template)
			eq(geom.splitParams(b.spec).leg.template:find("tram_electrified", 1, true) ~= nil, true)
			-- tram line through, tracks off: the two axis arms only, the ring stays plain
			b = build({ lanes = lanes, armType = armType, centre = 3, arms = 3 })
			eq(b.ring.template, geom.RING_TEMPLATES[lanes]); eq(b.ring.tramTrackType, nil)
			local armLists = roleLists(b, "arms")
			eq(#armLists, 2)
			eq(armLists[1].template, geom.ARM_TEMPLATES[armType]); eq(#armLists[1].edges, 2)
			eq(armLists[2].template, geom.ARM_TRAM[armType].template); eq(#armLists[2].edges, 2)
			local tl = roleLists(b, "through")
			eq(tl[1].template, geom.ARM_TRAM[geom.TRAM_STUB_ARM].template)
			eq(tl[#tl].template, #tl == 2 and geom.TRAM_THROUGH.template or geom.ARM_TRAM[geom.TRAM_STUB_ARM].template)
			-- off: plain base templates, no tramTrackType anywhere
			b = build({ lanes = lanes, armType = armType })
			for _, l in ipairs(b.lists) do eq(l.tramTrackType, nil) end
			eq(b.ring.template, geom.RING_TEMPLATES[lanes])
		end
	end
	-- tramTrackType only where the base game has no tram variant: 1-lane ring, country roads
	for i, t in ipairs(geom.RING_TRAM) do
		eq(t.tramTrackType ~= nil, i == 1)
		ok(t.template:find("tram_electrified", 1, true) ~= nil or t.tramTrackType == "ELECTRIC", t.template)
	end
	for i, t in ipairs(geom.ARM_TRAM) do
		eq(t.tramTrackType ~= nil, i >= 4)
		ok(t.template:find("tram_electrified", 1, true) ~= nil or t.tramTrackType == "ELECTRIC", t.template)
	end
end)

test("templates are base-game templates (absolute :: paths)", function()
	local all = { geom.LEG.template, geom.LEG_TRAM.template, geom.TRAM_THROUGH.template }
	for _, t in ipairs(geom.RING_TRAM) do all[#all + 1] = t.template end
	for _, t in ipairs(geom.ARM_TRAM) do all[#all + 1] = t.template end
	for _, t in ipairs(all) do
		ok(t:find("::/infrastructure/street/", 1, true) == 1 and t:find("_new", 1, true) ~= nil, t)
	end
end)

test("signals: odd arms trafficLightYes, even arms trafficLightNodePreference, on the entry nodes", function()
	each({ arms = range(#geom.ARM_LAYOUTS), splitter = { 1, 2 }, centre = { 1, 2 } }, function(over)
		local off = build(over)
		eq(off.ring.signalYes, nil); eq(off.ring.signalPref, nil)
		over.signals = 2
		local s = spec(over)
		local b = geom.build(s)
		local arms = geom.armsFor(s)
		local byTag = {}
		for _, n in ipairs(b.ring.nodes) do byTag[n.tag] = n end
		local yes, pref = b.ring.signalYes or {}, b.ring.signalPref or {}
		eq(#yes + #pref, #arms, label(over))
		for _, list in ipairs({ { yes, 1 }, { pref, 0 } }) do
			for _, tag in ipairs(list[1]) do
				local n = byTag[tag]
				ok(n ~= nil, "a ring node")
				eq(n.arm % 2, list[2], "parity " .. label(over))
				eq(n.kind, arms[n.arm].splitter and "E" or "P", "the entry node")
			end
		end
	end)
end)

-- builds the engine judges (verdicts.lua V.judge) are checked by test_engine_verdicts.lua
local V = loadfile(here .. "verdicts.lua", "t", _ENV)()
local ENGINE = V.loadAll(here .. "../../plans/square_roundabouts/")
local judged = V.judge(geom, ENGINE.trials, ENGINE.sweep)
local function overlaps(b)
	if judged(b) then return {} end
	return checks.overlaps(b.lists, 0.5)
end

test("no road overlaps another outside the junctions they share", function()
	each({ shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 3 }, arms = range(#geom.ARM_LAYOUTS), direction = { 1, 2 },
		radius = { 1, #geom.RADII }, splitter = { 2 }, centre = { 1, 3 }, armType = { 3, 6 } }, function(over)
		local b = build(over)
		checks.report(overlaps(b), label(over))
	end)
	each({ shape = { 1 }, lanes = { 2 }, arms = range(#geom.ARM_LAYOUTS), radius = { 1, geom.DEFAULT_RADIUS },
		splitter = { 1, 2 }, centre = { 1, 2 }, armType = { 1 } }, function(over)
		local b = build(over)
		checks.report(overlaps(b), label(over))
	end)
	each({ arms = range(#geom.ARM_LAYOUTS), radius = { 1, geom.DEFAULT_RADIUS }, splitter = { 2 }, centre = { 1, 2 }, tram = { 2 }, armType = { 3 } }, function(over)
		local b = build(over)
		checks.report(overlaps(b), label(over))
	end)
end)

test("islands keep clear of every road", function()
	each({ shape = { 1, #geom.SHAPE_RATIOS }, lanes = { 1, 3 }, arms = range(#geom.ARM_LAYOUTS), direction = { 1, 2 },
		radius = { 1, geom.DEFAULT_RADIUS, #geom.RADII }, splitter = { 1, 2 }, centre = { 1, 2, 3 }, tram = { 1, 2 } }, function(over)
		over.island = geom.ISLAND_PAVED
		local b = build(over)
		checks.report(checks.islandClear(b.lists, b.island, geom.ISLAND_MARGIN - 0.25), label(over))
	end)
end)

-- Phase 5f: splitter arms on a long oval's flank split along the ring normal when no radial
-- layout fits (2:1, 4 lanes, Y / 5 arms, large arms: forced at 60 m or built at the 40 m floor
-- the offline model rejected before)
test("splitter on a 2:1 oval: split along the ring normal where no radial layout fits; round rings never", function()
	local n = 0
	for _, arms in ipairs({ 2, 4 }) do
		for _, armType in ipairs({ 3, 6 }) do
			for radius = 1, #geom.RADII do
				for centre = 1, 3 do
					local over = { shape = 5, lanes = 3, arms = arms, splitter = 2, armType = armType, radius = radius, centre = centre }
					local b = build(over)
					ok(not b.forced, "forced")
					eq(b.spec.splitNormal, true)
					ok(geom.plan(b.spec, b.radius, geom.armsFor(b.spec)) ~= nil, "the offline model accepts it")
					-- the split node lies on the ring normal at the arm
					local ea = b.radius * b.spec.ovalRatio + geom.RING_OFFSET[3]
					local eb = b.radius + geom.RING_OFFSET[3]
					local arms2 = geom.armsFor(b.spec)
					for _, leg in ipairs(b.legs) do
						local phi = arms2[leg.arm].phi
						local p0 = geom.ellipsePoint(ea, eb, geom.paramForAngle(ea, eb, phi))
						local d = S.norm(S.sub(leg.split, p0))
						local nrm = geom.armDir(ea, eb, phi)
						near(d[1] * nrm[1] + d[2] * nrm[2], 1, 1e-9, "split node on the ring normal")
					end
					n = n + 1
				end
			end
		end
	end
	ok(n == 2 * 2 * #geom.RADII * 3)
	-- never on round rings, nor where a radial layout fits
	for _, o in ipairs({ { shape = 1, lanes = 3, arms = 2, splitter = 2, armType = 3, radius = 13 },
		{ shape = 5, lanes = 2, arms = 3, splitter = 2, armType = 1, radius = 5 } }) do
		eq(build(o).spec.splitNormal, nil)
	end
end)
