-- Roundabout Interchange (square_roundabouts_interchange.lua, .con.lua, .script.lua): PHASE5.md
-- Phase 5d. Short edges and the availability year are checked with the other entries in
-- test_short_edges.lua.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local ix = ug_require(DIR .. "square_roundabouts_interchange.lua")
local S = geom.shapes
local K = ix.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end

local function params(over)
	local p = {}
	for k, v in pairs(over or {}) do
		if k == "year" then p.year = v else p[K[k]] = v end
	end
	return p
end

local function build(over) return ix.build(ix.readParams(params(over))) end

local FIELDS = { "layout", "highway", "level", "lanes", "radius", "cross", "slipLength", "armLength", "direction", "island" }
local function name(o)
	local parts = {}
	for _, k in ipairs(FIELDS) do if o[k] then parts[#parts + 1] = k .. "=" .. o[k] end end
	return table.concat(parts, " ")
end

--- fn(o) over the cartesian product of grid (field -> list of values).
local function each(grid, fn)
	local keys = {}
	for _, k in ipairs(FIELDS) do if grid[k] then keys[#keys + 1] = k end end
	local function rec(i, o)
		if i > #keys then
			local copy = {}
			for k, v in pairs(o) do copy[k] = v end
			return fn(copy)
		end
		for _, v in ipairs(grid[keys[i]]) do
			o[keys[i]] = v
			rec(i + 1, o)
		end
	end
	rec(1, {})
end

-- Engine limits from the base interchanges (PHASE5.md "Phase 5a notes", spike 4).
local MIN_SEP = 7          -- vertical separation where roads cross (base 6-8 m; ours 8 m)
local AVG_MAX = 0.10       -- slip road gradient, average over its plan length
local PEAK_MAX = 0.15      -- slip road gradient, steepest Hermite sample
-- Gore of a slip road at its carriageway (along the slip road, from the merge node until its band
-- is clear of the carriageway's by 0.5 m): the base diamond's are 25.8-37.5 m, the ramp then
-- 1.6-3.1 m up, computed with the same rule from its geometry (sc.lua:344-373). Ours: the level
-- gore edge (ix.rampEdges), at most GORE_MAX; checks.overlaps allows a ramp / highway junction
-- stretch of that length.
local GORE_MAX = 40

local function isRampHighway(A, B)
	return (A.role == "ramps" and B.role == "highway") or (A.role == "highway" and B.role == "ramps")
end
local function overlapLimit(A, B, default)
	if isRampHighway(A, B) then return math.max(default, GORE_MAX) end
	return default
end

--- The carriageway node a slip road joins (same tag), and the slip road end there.
local function mergeOf(b, e)
	local hwyTag = e.io == "in" and e.tag0 or e.tag1
	local rampEnd = e.io == "in" and e.p0 or e.p1
	local rampDir = S.norm(e.io == "in" and e.t0 or e.t1)
	for _, l in ipairs(b.lists) do
		if l.role == "highway" then
			for _, h in ipairs(l.edges) do
				if h.tag0 == hwyTag then return h.p0, S.norm(h.t0), rampEnd, rampDir, hwyTag end
				if h.tag1 == hwyTag then return h.p1, S.norm(h.t1), rampEnd, rampDir, hwyTag end
			end
		end
	end
end

--- Lists with every slip road's carriageway end moved onto its carriageway node (what the tag
-- merge does), for checks.tags.
local function snapped(b)
	local out = {}
	for _, l in ipairs(b.lists) do
		local edges = {}
		for i, e in ipairs(l.edges) do
			local c = { p0 = e.p0, t0 = e.t0, p1 = e.p1, t1 = e.t1, tag0 = e.tag0, tag1 = e.tag1 }
			if l.role == "ramps" and e.part == "gore" then
				local node = mergeOf(b, e)
				if e.io == "in" then c.p0 = node else c.p1 = node end
			end
			edges[i] = c
		end
		out[#out + 1] = { role = l.role, halfWidth = l.halfWidth, edges = edges }
	end
	return out
end

--- Plan length and average / peak gradient of an edge.
local function gradient(e)
	local n, plan, peak = 200, 0, 0
	local prev = e.p0
	for k = 1, n do
		local p = checks.hermite(e, k / n)
		local d = math.sqrt((p[1] - prev[1]) ^ 2 + (p[2] - prev[2]) ^ 2)
		plan = plan + d
		if d > 1e-9 then peak = math.max(peak, math.abs(p[3] - prev[3]) / d) end
		prev = p
	end
	return plan, math.abs(e.p1[3] - e.p0[3]) / plan, peak
end

--- Gore: along the slip road from its carriageway end until its band is clear of the carriageway
-- (the straight line through the carriageway node) by 0.5 m; and the slip road's height there.
local function gore(b, e)
	local node, hdir = mergeOf(b, e)
	local f = b.frame
	local n, along = 400, 0
	local prev
	for k = 0, n do
		local s = e.io == "in" and k / n or 1 - k / n
		local p = checks.hermite(e, s)
		if prev then along = along + math.sqrt((p[1] - prev[1]) ^ 2 + (p[2] - prev[2]) ^ 2) end
		prev = p
		local lateral = math.abs(S.cross(hdir, S.sub(p, node)))
		if lateral >= f.hwH + f.hwRamp + 0.5 then return along, math.abs(p[3] - node[3]) end
	end
	return math.huge, 0
end

local stats = {}
local function track(key, v, fn)
	stats[key] = (fn or math.max)(stats[key] or v, v)
end

--- Every check on one build (heavy: overlaps / island clearance only when full).
local function checkBuild(b, n, full)
	eq(b.forced, nil, n .. ": no forced plan")
	checks.report(checks.tags(snapped(b)), n)
	checks.report(checks.lengths(b.lists, geom.MIN_EDGE), n)
	checks.report(checks.engineModel(b.lists), n)
	for _, xe in ipairs(checks.junctions(b.lists)) do track("free", xe.free, math.min) end
	local H = ix.HEIGHT
	for _, l in ipairs(b.lists) do
		for _, e in ipairs(l.edges) do
			if l.role == "ramps" and e.part == "climb" then
				local plan, avg, peak = gradient(e)
				ok(math.abs(math.abs(e.p1[3] - e.p0[3]) - H) < 1e-9, n .. ": slip roads climb the full height")
				ok(avg <= AVG_MAX + 1e-9, n .. string.format(": slip road average %.1f %%", avg * 100))
				ok(peak <= PEAK_MAX + 1e-9, n .. string.format(": slip road peak %.1f %%", peak * 100))
				near(e.t0[3], 0, 1e-9); near(e.t1[3], 0, 1e-9, "flat at both ends (base addRamp / auto tangents)")
				track("avg", avg); track("peak", peak); track("rampMin", plan, math.min)
			elseif l.role == "ramps" then
				near(e.p0[3], b.zHighway, 1e-9, n); near(e.p1[3], b.zHighway, 1e-9, n .. ": gore level with the highway")
				near(e.t0[3], 0, 1e-9); near(e.t1[3], 0, 1e-9)
				-- merge as the base diamond: MERGE_OFFSET outside the carriageway node, same tag, parallel
				local node, hdir, rampEnd, rampDir = mergeOf(b, e)
				ok(node ~= nil, n .. ": slip road tag on a carriageway node")
				near(S.dist(node, rampEnd), ix.MERGE_OFFSET, 1e-9, n)
				near(S.dot(S.sub(rampEnd, node), hdir), 0, 1e-9, n .. ": beside the node")
				ok(S.dot(rampEnd, { 0, node[2] > 0 and 1 or -1, 0 }) > math.abs(node[2]), n .. ": on the outer side")
				near(S.dot(rampDir, hdir), 1, 1e-9, n .. ": parallel, same direction")
				near(rampEnd[3], node[3], 1e-9)
				local g, gz = gore(b, e)
				ok(g <= GORE_MAX, n .. string.format(": gore %.1f m", g))
				track("gore", g); track("goreMin", g, math.min); track("goreZ", gz)
			else
				-- every other road is level, at its level's height
				near(e.p0[3], e.p1[3], 1e-9, n); near(e.t0[3], 0, 1e-9, n); near(e.t1[3], 0, 1e-9, n)
				local z = l.role == "highway" and b.zHighway or b.zRing
				near(e.p0[3], z, 1e-9, n .. ": " .. l.role .. " height")
			end
			if l.edgeType then
				eq(l.edgeType, "BRIDGE"); eq(l.edgeTypeName, b.bridge)
				near(e.p0[3], H, 1e-9, n .. ": bridges at full height")
			end
		end
	end
	if full then
		local ls = {}
		checks.report(checks.overlaps(b.lists, 0.5, checks.levelSkip(MIN_SEP, 0.5, ls), overlapLimit), n)
		ok((ls.crossings or 0) >= 2, n .. ": the levels cross (bridges)")
		track("minSep", ls.minSep, math.min)
		checks.report(checks.islandClear(b.lists, b.island, geom.ISLAND_MARGIN - 0.25), n)
	end
end

test("readParams: defaults, foreign values, year -> bridge", function()
	local s = ix.readParams({})
	eq(s.layout, ix.LAYOUT_TWO_BRIDGE); eq(s.highway, ix.DEFAULT_HIGHWAY); eq(s.level, ix.LEVEL_RING_OVER)
	eq(s.lanes, 2); eq(s.radius, ix.RADII[ix.DEFAULT_RADIUS]); eq(s.cross, ix.DEFAULT_CROSS)
	eq(s.slipLength, ix.DEFAULT_SLIP_LENGTH); eq(s.armLength, ix.DEFAULT_ARM_LENGTH)
	eq(s.direction, geom.DIRECTION_CCW); eq(s.island, geom.ISLAND_NONE); eq(s.year, nil)
	eq(ix.readParams({ sqrb_ix_layout = 4, sqrb_ix_level = 0, sqrb_ix_radius = 1.5 }).layout, 1)
	eq(ix.readParams({ sqrb_ix_level = 3 }).level, 1)
	eq(ix.readParams({ sqrb_lanes = 3, sqrb_direction = 2, sqrb_island = 5 }).lanes, 3, "shares Ring lanes")
	eq(ix.bridgeType(nil), ix.BRIDGE_CONCRETE)
	eq(ix.bridgeType(1940), ix.BRIDGE_STEEL); eq(ix.bridgeType(1969), ix.BRIDGE_STEEL)
	eq(ix.bridgeType(1970), ix.BRIDGE_CONCRETE)
	eq(build({ year = 1955 }).bridge, ix.BRIDGE_STEEL)
end)

test(".con.lua: params, script, icon, availability; script exports only updateFn", function()
	local con = loadData("square_roundabouts_interchange.con.lua")
	eq(con.description.name, "Roundabout Interchange")
	eq(con.description.icon, "square_roundabouts_interchange.tga", "own icon (the game loads the @2x file)")
	eq(con.updateScript.fileName, "square_roundabouts_interchange.script@updateFn")
	eq(con.availability.yearFrom, 1940)
	eq(con.menuCategory.categories[1].category, "street_constructions")
	local byKey, order = {}, {}
	local shared = { [K.lanes] = true, [K.direction] = true, [K.island] = true }
	for _, p in ipairs(con.params) do
		ok(byKey[p.key] == nil, "duplicate key " .. p.key)
		byKey[p.key] = p
		order[#order + 1] = p.key
		ok(p.key:sub(1, 8) == "sqrb_ix_" or shared[p.key], "entry-specific keys are sqrb_ix_: " .. p.key)
		ok(#p.values >= 2, p.key)
		ok((p.defaultIndex or 1) >= 1 and (p.defaultIndex or 1) <= #p.values, p.key .. " default in range")
		eq(p.checkEnabledScript, nil, p.key .. " has no checkEnabledScript")
	end
	-- Phase 7c3: Radius is a row of presets on ix.RADIUS_PRESET_KEY (the slider key K.radius stays the
	-- full-range index for tests, goldens and the probe); no slider left
	local RP = ix.RADIUS_PRESET_KEY
	eq(order, { K.layout, K.highway, K.level, K.lanes, RP, K.cross, K.slipLength, K.armLength, K.direction, K.island }, "UI order")
	eq(#byKey[K.layout].values, 3); eq(#byKey[K.highway].values, #ix.HIGHWAYS); eq(#byKey[K.level].values, 2)
	eq(#byKey[K.lanes].values, #geom.RING_TEMPLATES)
	eq(byKey[RP].values, { "S", "M", "L", "XL" }); eq(byKey[RP].defaultIndex, ix.DEFAULT_RADIUS_PRESET)
	local radii = {}
	for i, ri in ipairs(ix.RADIUS_PRESETS) do radii[i] = ix.RADII[ri] end
	eq(radii, { 15, 20, 30, 45 })
	for i, ri in ipairs(ix.RADIUS_PRESETS) do
		eq(ix.readParams({ [RP] = i }), ix.readParams({ [K.radius] = ri }), "preset " .. i)
		eq(ix.readParams({ [RP] = i, [K.radius] = 10 }).radiusIndex, ri, "preset key first")
	end
	for _, p in ipairs(con.params) do
		ok(p.uiType ~= "Slider", p.key .. " is no slider")
		if p.displayMode == "Horizontal" then
			ok(#p.values <= 5, p.key)
			local chars = 0
			for _, v in ipairs(p.values) do chars = chars + #v end
			ok(chars <= 30, p.key .. ": short labels")
		end
	end
	eq(byKey[K.slipLength].uiType, "Button"); eq(byKey[K.armLength].uiType, "Button")
	eq(#byKey[K.cross].values, #geom.ARM_TEMPLATES); eq(#byKey[K.slipLength].values, #ix.SLIP_LENGTHS)
	eq(#byKey[K.armLength].values, #ix.ARM_LENGTHS); eq(#byKey[K.island].values, 5)
	-- shared keys keep the main entry's values and meaning
	local main = loadData("square_roundabouts.con.lua")
	for _, p in ipairs(main.params) do
		if shared[p.key] and p.key ~= K.direction then eq(#byKey[p.key].values, #p.values, p.key) end
	end
	local d = {}
	for _, p in ipairs(con.params) do d[p.key] = p.defaultIndex or 1 end
	-- 2026-10-09 (user: size menus default to the smallest): the Radius button row defaults to S (15 m);
	-- readParams' full-range fallback without any radius key (ix.DEFAULT_RADIUS, 20 m) is unchanged
	eq(d[ix.RADIUS_PRESET_KEY], 1, "Radius menu default = S, the smallest")
	local got, want = ix.readParams(d), ix.readParams({})
	eq(got.radius, 15); eq(got.radiusIndex, 1)
	got.radius, got.radiusIndex, want.radius, want.radiusIndex = nil, nil, nil, nil
	eq(got, want, "con defaults = readParams fallbacks (radius aside)")

	local script = loadData("square_roundabouts_interchange.script.lua")
	local keys = {}
	for k in pairs(script) do keys[#keys + 1] = k end
	eq(keys, { "updateFn" })
	for _, year in ipairs({ 1940, 1969, 1970, 2000, false }) do
		local r = script.updateFn({}, year and { year = year } or {})
		eq(r.subconstructions, nil, "Centre island None by default")
		eq(r.models, {}); eq(r.groundFaces, {}); eq(r.cost, 0)
		local bridges = 0
		for _, el in ipairs(r.edgeLists) do
			eq(el.type, "STREET"); eq(el.snapNodes, {})
			eq(#el.freeNodes, #el.edges, "every node free")
			for i, nd in ipairs(el.freeNodes) do eq(nd, i - 1) end
			ok(el.params.type:sub(1, 3) == "::/", el.params.type)
			if el.edgeType then
				bridges = bridges + 1
				eq(el.edgeType, "BRIDGE")
				eq(el.edgeTypeName, (year and year < 1970) and ix.BRIDGE_STEEL or ix.BRIDGE_CONCRETE)
			else
				eq(el.edgeTypeName, nil)
			end
		end
		eq(bridges, 1, "the ring's bridge list")
	end
	local r = script.updateFn({}, params({ island = 3, layout = 2 }))
	eq(#r.subconstructions, 1)
	eq(#r.subconstructions[1].groundFaces, 2, "an island per ring")
end)

test("lists: roles, templates, bridges per layout and level", function()
	for layout = 1, 3 do
		for level = 1, 2 do
			local b = build({ layout = layout, level = level })
			local roles = {}
			for _, l in ipairs(b.lists) do
				local key = l.role .. (l.edgeType and "+bridge" or "")
				roles[key] = (roles[key] or 0) + #l.edges
				if l.role == "highway" then eq(l.template, ix.HIGHWAYS[ix.DEFAULT_HIGHWAY].template) end
				if l.role == "ramps" then eq(l.template, ix.RAMP.template) end
				if l.role == "ring" then eq(l.template, geom.RING_TEMPLATES[2]) end
				if l.role == "arms" or l.role == "link" then eq(l.template, geom.ARM_TEMPLATES[ix.DEFAULT_CROSS]) end
			end
			local n = "layout " .. layout .. " level " .. level
			eq(roles.ramps, 8, n, "4 slip roads of 2 edges"); eq(roles.arms, 2, n)
			if level == ix.LEVEL_RING_OVER then
				eq(b.zRing, ix.HEIGHT); eq(b.zHighway, 0)
				eq(roles["highway+bridge"], nil, n); eq(roles.highway, 6, n)
				if layout == ix.LAYOUT_DUMBBELL then eq(roles["link+bridge"], 1, n) else ok((roles["ring+bridge"] or 0) >= 2, n) end
			else
				eq(b.zRing, 0); eq(b.zHighway, ix.HEIGHT)
				eq(roles["highway+bridge"], 2, n .. ": one bridge per carriageway")
				eq(roles["ring+bridge"], nil, n); eq(roles["link+bridge"], nil, n)
				eq(roles.highway, 8, n)
			end
		end
	end
end)

-- The full sweep: every layout x highway x level x traffic side x ring lanes x four cross roads
-- (town small / large, country small / large) at the default radius, slip and arm length.
test("every layout x highway x level x side x lanes x cross road: tags, levels, gradients, gores, engine model, overlaps, islands", function()
	local count = 0
	each({ layout = { 1, 2, 3 }, highway = { 1, 2, 3 }, level = { 1, 2 }, direction = { 1, 2 }, lanes = { 1, 2, 3 },
		cross = { 1, 3, 4, 6 }, island = { 3 } }, function(o)
		local b = build(o)
		count = count + 1
		-- overlaps on the widest and narrowest cross road; left-hand traffic only for the widest (it is
		-- the exact mirror, tested below)
		checkBuild(b, name(o), o.cross == 3 or (o.cross == 4 and o.direction == 1))
	end)
	print(string.format("    %d builds: smallest free length %.1f m; slip roads avg <= %.1f %%, peak <= %.1f %%, shortest %.0f m; gore %.1f-%.1f m (slip road up to %.1f m there); smallest separation at crossings %.1f m",
		count, stats.free, stats.avg * 100, stats.peak * 100, stats.rampMin, stats.goreMin, stats.gore, stats.goreZ, stats.minSep))
end)

test("radius, slip road length and arm length: every value passes (sample)", function()
	local count = 0
	each({ layout = { 1, 2, 3 }, highway = { 1, 3 }, level = { 1, 2 }, radius = { 1, 4, #ix.RADII }, slipLength = { 1, #ix.SLIP_LENGTHS },
		armLength = { 1, #ix.ARM_LENGTHS }, cross = { 6 }, lanes = { 3 } }, function(o)
		count = count + 1
		checkBuild(build(o), name(o), o.armLength == 1 and o.slipLength == 1)
	end)
	for slip = 1, #ix.SLIP_LENGTHS do
		for arm = 1, #ix.ARM_LENGTHS do
			checkBuild(build({ slipLength = slip, armLength = arm, layout = 3, lanes = 1 }), "slip " .. slip .. " arm " .. arm, false)
			count = count + 1
		end
	end
	print(string.format("    %d builds", count))
end)

test("radius: a minimum; the rings grow only as far as needed", function()
	each({ layout = { 1, 2, 3 }, highway = { 1, 2, 3 }, lanes = { 1, 2, 3 }, cross = { 1, 3, 6 }, radius = { 1, 2, 5, 10 } }, function(o)
		local spec = ix.readParams(params(o))
		local b = ix.build(spec)
		ok(b.radius >= spec.radius, name(o))
		eq(b.rc, b.radius + geom.RING_OFFSET[spec.lanes])
		-- every smaller candidate from the slider up does not fit
		local f = ix.frame(spec)
		for i = spec.radiusIndex, #ix.RADII do
			local r = ix.RADII[i]
			if r >= b.radius then break end
			local lay = ix.layout(spec, f, r + f.offset)
			ok(not (lay and ix.fits(lay)), name(o) .. ": " .. r .. " m fits")
		end
	end)
	-- dumbbell and peanut keep a small slider radius; the two-bridge ring must span the highway
	eq(build({ layout = 2, radius = 1 }).radius, ix.RADII[1])
	eq(build({ layout = 3, radius = 1 }).radius, ix.RADII[1])
	ok(build({ layout = 1, radius = 1 }).radius > ix.RADII[1])
	ok(build({ layout = 1, radius = 1, highway = 3 }).radius > build({ layout = 1, radius = 1, highway = 1 }).radius)
	-- the slider still matters above the minimum
	eq(build({ layout = 1, radius = #ix.RADII }).radius, ix.RADII[#ix.RADII])
end)

test("traffic side: left-hand traffic is the right-hand layout mirrored in x; rings and carriageways run the right way", function()
	local function mirrorOf(p) return { -p[1], p[2], p[3] } end
	each({ layout = { 1, 2, 3 }, highway = { 1, 3 }, level = { 1, 2 }, lanes = { 1, 3 }, island = { 3 } }, function(o)
		local r = build(o)
		o.direction = 2
		local l = build(o)
		local n = name(o)
		eq(l.mirrored, true); eq(#l.lists, #r.lists, n)
		for i, list in ipairs(r.lists) do
			eq(l.lists[i].template, list.template); eq(l.lists[i].edgeType, list.edgeType)
			for j, e in ipairs(list.edges) do
				local m = l.lists[i].edges[j]
				for _, k in ipairs({ "p0", "t0", "p1", "t1" }) do
					local w = mirrorOf(e[k])
					for c = 1, 3 do near(m[k][c], w[c], 1e-9, n) end
				end
				eq(m.tag0, e.tag0); eq(m.tag1, e.tag1)
			end
		end
		eq(#l.island.faces, #r.island.faces, n)
		for i, f in ipairs(r.island.faces) do near(S.area(l.island.faces[i].outline), S.area(f.outline), 1e-6) end
		for i, c in ipairs(r.island.colliders) do near(l.island.colliders[i].x, -c.x, 1e-9) end
		-- right-hand: carriageway south runs east; the ring turns anticlockwise (left-hand: mirrored)
		for side, b in ipairs({ r, l }) do
			local sign = side == 1 and 1 or -1
			for _, list in ipairs(b.lists) do
				for _, e in ipairs(list.edges) do
					if list.role == "highway" then
						ok(sign * e.t0[1] * (e.p0[2] < 0 and 1 or -1) > 0, n .. ": keeps to the traffic side")
					elseif list.role == "ring" and math.abs(S.cross(e.t0, e.t1)) > 1e-6 then
						-- lobe / ring arcs turn left (anticlockwise) in right-hand traffic; peanut waists turn the other way
						-- (the peanut's waist edges curve the other way: the pinch)
						if not e.waist then ok(sign * S.cross(e.t0, e.t1) > 0, n .. ": ring direction") end
					end
				end
			end
		end
	end)
end)

test("slip roads: off-ramps leave before the junction, on-ramps join after it; one per quadrant", function()
	for layout = 1, 3 do
		for direction = 1, 2 do
			local b = build({ layout = layout, direction = direction })
			local sign = direction == 1 and 1 or -1
			local seen = {}
			local ringEnds = {}
			for _, e in ipairs(b.ramps) do
				if e.part == "climb" then ringEnds[e.cw .. e.io] = e.io == "in" and e.p1 or e.p0 end
			end
			for _, e in ipairs(b.ramps) do
				if e.part ~= "gore" then goto continue end
				local node, hdir, rampEnd = mergeOf(b, e)
				local ringEnd = ringEnds[e.cw .. e.io]
				-- along the carriageway's direction the ring node lies after an off-ramp's merge, before an on-ramp's
				local ahead = S.dot(S.sub(ringEnd, rampEnd), hdir)
				ok((e.io == "in") == (ahead > 0), "layout " .. layout .. ": " .. e.io)
				ok(ringEnd[2] * rampEnd[2] > 0, "the slip road stays on its carriageway's side")
				seen[(rampEnd[1] > 0 and "e" or "w") .. (rampEnd[2] > 0 and "n" or "s")] = true
				-- south carriageway runs +x in right-hand traffic
				ok(sign * hdir[1] * (rampEnd[2] < 0 and 1 or -1) > 0)
				::continue::
			end
			eq(seen, { en = true, es = true, wn = true, ws = true })
		end
	end
end)

test("every param changes the build (radius: above the minimum; centre island: None adds nothing)", function()
	local function sig(b)
		local parts = {}
		for _, l in ipairs(b.lists) do
			parts[#parts + 1] = l.template .. tostring(l.edgeType) .. tostring(l.edgeTypeName)
			for _, e in ipairs(l.edges) do
				parts[#parts + 1] = string.format("%.3f,%.3f,%.3f,%.3f", e.p0[1], e.p0[2], e.p0[3], e.p1[1])
			end
		end
		if b.island then parts[#parts + 1] = #b.island.faces .. b.island.faces[1].fill .. #b.island.models end
		return table.concat(parts, ";")
	end
	local counts = { layout = 3, highway = 3, level = 2, lanes = 3, radius = #ix.RADII, cross = 6, slipLength = #ix.SLIP_LENGTHS,
		armLength = #ix.ARM_LENGTHS, direction = 2, island = 5 }
	for layout = 1, 3 do
		for field, n in pairs(counts) do
			local seen = {}
			local from = 1
			-- the radius is a minimum: on the two-bridge ring the values below its smallest span build that one
			if field == "radius" then
				local min = build({ layout = layout, radius = 1 }).radius
				while ix.RADII[from] < min do from = from + 1 end
				if layout == ix.LAYOUT_TWO_BRIDGE then ok(from > 1) end
			end
			for v = from, n do
				local o = { layout = layout, [field] = v }
				if field == "layout" then o = { layout = v } end
				local s = sig(build(o))
				ok(not seen[s], string.format("layout %d: %s = %d builds the same as %s", layout, field, v, tostring(seen[s])))
				seen[s] = v
			end
		end
	end
end)

test("islands: two-bridge halves beside the highway, one per dumbbell ring / peanut lobe; colliders inside; the roads do not depend on them", function()
	each({ layout = { 1, 2, 3 }, highway = { 1, 2, 3 }, lanes = { 1, 2, 3 }, island = { 1, 2, 3, 4, 5 } }, function(o)
		local b = build(o)
		local n = name(o)
		if o.island == 1 then eq(b.island, nil, n); return end
		eq(#b.island.faces, 2, n)
		local f = b.frame
		for _, fc in ipairs(b.island.faces) do
			ok(S.area(fc.outline) >= geom.ISLAND_MIN_AREA, n)
			for _, p in ipairs(fc.outline) do ok(math.abs(p[2]) >= f.corr + geom.ISLAND_MARGIN - 1e-6, n .. ": clear of the highway") end
		end
		for _, c in ipairs(b.island.colliders) do
			local inside = false
			for _, fc in ipairs(b.island.faces) do inside = inside or S.pointInPolygon(c.x, c.y, fc.outline) end
			ok(inside, n .. ": collider inside an island")
		end
		for _, m in ipairs(b.island.models) do
			local inside = false
			for _, fc in ipairs(b.island.faces) do inside = inside or S.fits(m.x, m.y, geom.MODEL_RADIUS[m.id] - 1e-6, fc.outline) end
			ok(inside, n .. ": model inside an island")
		end
		local none = build({ layout = o.layout, highway = o.highway, lanes = o.lanes })
		for i, l in ipairs(b.lists) do
			for j, e in ipairs(l.edges) do
				for c = 1, 3 do near(e.p0[c], none.lists[i].edges[j].p0[c], 1e-9, n) end
			end
		end
	end)
end)

-- Phase 5f: the engine rejected every 4-lane two-bridge ring (p5_all, alpha 52-58 deg); Phase 5g:
-- p5f_search accepted alpha 30-45 deg for every highway and level, 45 deg ships
test("two-bridge ring: 4 lanes keep alpha <= 45 deg (slip roads join >= 45 deg off the ring), 1-2 lanes <= 60 deg", function()
	for highway = 1, 3 do
		for _, level in ipairs({ 1, 2 }) do
			for radius = 1, #ix.RADII do
				for lanes = 1, 3 do
					local o = { highway = highway, level = level, radius = radius, lanes = lanes }
					local b = build(o)
					local limit = lanes == 3 and 45 or 60
					ok(b.alpha <= math.rad(limit) + 1e-9, name(o) .. string.format(": alpha %.1f", math.deg(b.alpha)))
					ok(not b.forced, name(o))
				end
			end
		end
	end
	-- the smallest 4-lane rings (15 m slider): small 30 m, medium 45 m, large 50 m (the radii
	-- p5f_search's ixAlphaMax=45 candidate placed)
	eq({ build({ highway = 1, lanes = 3, radius = 1 }).radius, build({ highway = 2, lanes = 3, radius = 1 }).radius,
		build({ highway = 3, lanes = 3, radius = 1 }).radius }, { 30, 45, 50 })
end)
