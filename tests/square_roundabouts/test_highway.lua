-- Highway Interchange (square_roundabouts_highway.lua, .con.lua, .script.lua): INTERCHANGES.md
-- Phases 7b (geometry), 7c (menu entry) and 7c2 (one menu entry per type). Short edges and the availability year are checked with
-- the other entries in test_short_edges.lua.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local ramps = ug_require(DIR .. "square_roundabouts_ramps.lua")
local hx = ug_require(DIR .. "square_roundabouts_highway.lua")
local ix = ug_require(DIR .. "square_roundabouts_interchange.lua")
local K = hx.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local S = checks.strictShapes(geom.shapes) -- S.dot is plan-only and fails on two 3D vectors: S.pdot / S.dot3

local function params(over)
	local p = {}
	for k, v in pairs(over or {}) do
		if k == "year" then p.year = v else p[K[k]] = v end
	end
	return p
end

local function build(over) return hx.build(hx.readParams(params(over))) end

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end

--- The ramp length a spec's plan starts from (shortest + the slider's extra), for the built Size.
-- Phase 7c3: hx.rampStart (the Scale also lengthens the shortest ramp).
local function rampStart(b)
	return hx.rampStart(b.spec, b.frame, b.size)
end

local FIELDS = { "type", "highway", "level", "cross", "size", "rampLength", "armLength", "direction" }
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
			local c = {}
			for k, v in pairs(o) do c[k] = v end
			return fn(c)
		end
		for _, v in ipairs(grid[keys[i]]) do
			o[keys[i]] = v
			rec(i + 1, o)
		end
	end
	rec(1, {})
end

-- Limits as test_interchange.lua (PHASE5.md "Phase 5a notes", spike 4).
local MIN_SEP = 7
local AVG_MAX = 0.10
local PEAK_MAX = 0.15
local GORE_MAX = 40
local H = ramps.HEIGHT

local function overlapLimit(A, B, default)
	if (A.role == "ramps" and B.role == "highway") or (A.role == "highway" and B.role == "ramps") then
		return math.max(default, GORE_MAX)
	end
	return default
end

--- The carriageway node a gore edge joins (same tag), and the ramp end there.
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

--- Lists with every gore's carriageway end moved onto its carriageway node (the tag merge).
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

--- Ramps by id ("sw_d", ...): their edges in driving order.
local function rampsOf(b)
	local by, order = {}, {}
	for _, e in ipairs(b.ramps) do
		if not by[e.ramp] then by[e.ramp] = {}; order[#order + 1] = e.ramp end
		local l = by[e.ramp]
		l[#l + 1] = e
	end
	return by, order
end

local function isClimb(e) return e.part == "climb" or e.part == "stub" or e.part == "loop" end

--- Signed turn of an edge (radians, + = left) from t0 to t1, and its circle radius (chord / angle).
local function turn(e)
	local a = math.atan(S.cross(e.t0, e.t1), S.pdot(e.t0, e.t1))
	local chord = math.sqrt((e.p1[1] - e.p0[1]) ^ 2 + (e.p1[2] - e.p0[2]) ^ 2)
	return a, chord / (2 * math.sin(math.abs(a) / 2))
end

local stats = {}
local function track(key, v, fn)
	if v == nil then return end
	stats[key] = (fn or math.max)(stats[key] or v, v)
end

--- Every check on one build (overlaps only when full).
local function checkBuild(b, n, full)
	eq(b.forced, nil, n .. ": no forced plan")
	checks.report(checks.tags(snapped(b)), n)
	checks.report(checks.lengths(b.lists, geom.MIN_EDGE), n)
	local problems, xs = checks.engineModel(b.lists)
	checks.report(problems, n)
	for _, xe in ipairs(xs) do track("free", xe.free, math.min) end
	local sign = b.mirrored and -1 or 1
	for _, l in ipairs(b.lists) do
		for _, e in ipairs(l.edges) do
			if l.role ~= "ramps" then
				near(e.p0[3], e.p1[3], 1e-9, n); near(e.t0[3], 0, 1e-9, n); near(e.t1[3], 0, 1e-9, n)
				near(e.p0[3], l.role == "highway" and b.zHighway or b.zCross, 1e-9, n .. ": " .. l.role .. " height")
			end
			if l.edgeType then
				eq(l.edgeType, "BRIDGE"); eq(l.edgeTypeName, b.bridge)
				near(e.p0[3], H, 1e-9, n .. ": bridges at full height")
				near(e.p1[3], H, 1e-9, n)
			end
		end
	end
	local by, order = rampsOf(b)
	for _, id in ipairs(order) do
		local edges = by[id]
		local rn = n .. " " .. id
		local climb, termTag, goreTag = {}, nil, nil
		for i, e in ipairs(edges) do
			if i > 1 then
				for c = 1, 3 do near(e.p0[c], edges[i - 1].p1[c], 1e-9, rn .. ": continuous") end
				near(S.dot3(S.norm(e.t0), S.norm(edges[i - 1].t1)), 1, 1e-9, rn .. ": tangent")
			end
			if isClimb(e) then climb[#climb + 1] = e end
			for _, t in pairs({ e.tag0 or false, e.tag1 or false }) do
				if t and t:find("^sqrb_hx_x") then termTag = t elseif t then goreTag = t end
			end
			if e.part == "gore" then
				near(e.p0[3], b.zHighway, 1e-9, rn); near(e.p1[3], b.zHighway, 1e-9, rn .. ": gore level with the highway")
				near(e.t0[3], 0, 1e-9); near(e.t1[3], 0, 1e-9)
				local node, hdir, rampEnd, rampDir = mergeOf(b, e)
				ok(node ~= nil, rn .. ": gore tag on a carriageway node")
				near(S.dist(node, rampEnd), ramps.MERGE_OFFSET, 1e-9, rn)
				near(S.dot(S.sub(rampEnd, node), hdir), 0, 1e-9, rn .. ": beside the node")
				ok(math.abs(rampEnd[2]) > math.abs(node[2]), rn .. ": on the outer side")
				near(S.dot(rampDir, hdir), 1, 1e-9, rn .. ": parallel, same direction")
				-- eastbound (south) runs +x in right-hand traffic
				ok(sign * hdir[1] * (node[2] < 0 and 1 or -1) > 0, rn .. ": carriageway direction")
			elseif e.part == "level" then
				near(e.p0[3], b.zHighway, 1e-9, rn); near(e.p1[3], b.zHighway, 1e-9, rn)
			end
		end
		ok(termTag ~= nil and goreTag ~= nil, rn .. ": one end on a terminal, one on a carriageway")
		-- the climb: the whole height, flat ends, within the gradient limits
		local first, last = climb[1], climb[#climb]
		near(math.abs(last.p1[3] - first.p0[3]), H, 1e-9, rn .. ": climbs the full height")
		near(first.t0[3], 0, 1e-9, rn); near(last.t1[3], 0, 1e-9, rn .. ": flat ends")
		local plan, avg, peak = ramps.gradient(climb)
		ok(avg <= AVG_MAX + 1e-9, rn .. string.format(": average %.1f %%", avg * 100))
		ok(peak <= PEAK_MAX + 1e-9, rn .. string.format(": peak %.1f %%", peak * 100))
		local kind = edges[1].kind
		track("avg_" .. kind, avg); track("peak_" .. kind, peak); track("min_" .. kind, plan, math.min)
		if kind == "l" then
			-- loop: circle arcs of radius R turning right (left in left-hand traffic), 180 deg in all
			local sweep = 0
			for _, e in ipairs(edges) do
				if e.part == "loop" then
					local a, r = turn(e)
					near(r, b.R, 1e-6, rn .. ": loop radius")
					ok(math.abs(a) <= geom.MAX_EDGE_ANGLE + 1e-9, rn .. ": <= 90 deg per edge")
					sweep = sweep + a
				end
			end
			near(sweep, -sign * math.pi, 1e-9, rn .. ": loop sweep and direction")
		end
	end
	if full then
		local ls, pairs = {}, {}
		local inner = checks.levelSkip(MIN_SEP, 0.5, ls)
		local function skip(A, B)
			local r = inner(A, B)
			if r then
				local roles = { A.role, B.role }
				table.sort(roles)
				pairs[#pairs + 1] = roles[1] .. "x" .. roles[2]
			end
			return r
		end
		checks.report(checks.overlaps(b.lists, 0.5, skip, overlapLimit), n)
		-- the only grade-separated pairs: the cross road's middle edge x carriageway edges (both
		-- carriageways; an edge ending at a loop's merge node `clear` beyond the cross road counts too)
		ok(#pairs >= 2, n .. ": the levels cross")
		for _, p in ipairs(pairs) do
			ok(p == "crossxhighway" or p == "armsxhighway", n .. ": only the cross road and the highway cross: " .. p)
		end
		track("minSep", ls.minSep, math.min)
	end
end

test("readParams: defaults, foreign values, shared keys, year -> bridge", function()
	local s = hx.readParams({})
	eq(s.type, hx.TYPE_A4); eq(s.highway, ramps.DEFAULT_HIGHWAY); eq(s.level, hx.LEVEL_ROAD_OVER)
	eq(s.cross, hx.DEFAULT_CROSS); eq(s.size, hx.DEFAULT_SIZE); eq(s.rampLength, hx.DEFAULT_RAMP_LENGTH)
	eq(s.armLength, hx.DEFAULT_ARM_LENGTH); eq(s.direction, geom.DIRECTION_CCW); eq(s.year, nil); eq(s.dev, nil)
	eq(hx.readParams({ sqrb_hx_type = 7, sqrb_hx_level = 0, sqrb_hx_scale = 1.5, sqrb_hx_ramp = "x", sqrb_hx_arm_length = 4 }), s)
	eq(hx.readParams({ sqrb_hx_type = 6 }).type, hx.TYPE_DIAMOND)
	-- 7c's keys (other values) are ignored
	eq(hx.readParams({ sqrb_hx_size = 4, sqrb_hx_ramp_length = 3, sqrb_ix_arm_length = 3 }), s)
	-- keys shared with the Roundabout Interchange keep its values and meaning
	eq(K.highway, ix.PARAM_KEYS.highway); eq(K.cross, ix.PARAM_KEYS.cross)
	eq(K.direction, ix.PARAM_KEYS.direction)
	eq(hx.DEFAULT_CROSS, ix.DEFAULT_CROSS)
	eq(hx.readParams({ sqrb_ix_highway = 3, sqrb_ix_cross = 6, sqrb_direction = 2 }).highway, 3)
	for k, v in pairs(K) do ok(v:sub(1, 5) == "sqrb_", k) end
	eq(#hx.TYPES, 6); eq(#hx.LOOP_RADII, 3); eq(#hx.TERMINAL_DISTANCES, 3); eq(#hx.RAMP_EXTRAS, 3); eq(#hx.ARM_LENGTHS, 3)
	-- Scale: Small = 7c's Compact, Medium = 7c's Large, Large beyond 7c's Very large (60 m / 50 m)
	eq(hx.LOOP_RADII[1], 25); eq(hx.LOOP_RADII[2], 45); ok(hx.LOOP_RADII[3] > 60)
	eq(hx.TERMINAL_DISTANCES[1], 0); ok(hx.TERMINAL_DISTANCES[3] > 50)
	-- specFor: the entry's captureParams.type wins over params; without it params' type
	eq(hx.specFor({ type = hx.TYPE_B2 }, { sqrb_hx_type = 6 }).type, hx.TYPE_B2)
	eq(hx.specFor({}, { sqrb_hx_type = 6 }).type, hx.TYPE_DIAMOND)
	eq(hx.specFor(nil, {}).type, hx.TYPE_A4)
	eq(hx.specFor({ type = 9 }, {}).type, hx.TYPE_A4)
	eq(build({ year = 1955 }).bridge, ramps.BRIDGE_STEEL)
	eq(build({ year = 1969, level = 2 }).bridge, ramps.BRIDGE_STEEL)
	eq(build({ year = 1970 }).bridge, ramps.BRIDGE_CONCRETE)
	eq(build({}).bridge, ramps.BRIDGE_CONCRETE)
end)

-- Phase 7c3: three entries (user: A and B are mirrors, so a Layout setting instead of an item each):
-- id, name, menu order, types behind the Layout buttons, button labels
local ENTRIES = {
	{ id = "parclo", name = "Parclo", order = 6002, types = { hx.TYPE_A4, hx.TYPE_B4 }, labels = { "A", "B" } },
	{ id = "parclo2", name = "Parclo, two quadrants", order = 6003, types = { hx.TYPE_A2, hx.TYPE_B2, hx.TYPE_AB2 },
		labels = { "A", "B", "AB" } },
	{ id = "diamond", name = "Diamond", order = 7001, types = { hx.TYPE_DIAMOND } },
}

test(".con.lua x 3: Parclo [A][B], Parclo two quadrants [A][B][AB], Diamond; button rows, script, icons, availability", function()
	local orders, covered = {}, {}
	for _, E in ipairs(ENTRIES) do
		local id = E.id
		local con = loadData("square_roundabouts_highway_" .. id .. ".con.lua")
		local n = id
		local t = E.types[1]
		eq(con.description.name, E.name, n)
		eq(con.description.icon, "square_roundabouts_highway_" .. id .. ".tga", "own icon (the game loads the @2x file)")
		eq(con.description.previewIcon, "square_roundabouts_highway_" .. id .. "_preview.tga")
		eq(con.updateScript.fileName, "square_roundabouts_highway.script@updateFn")
		eq(con.updateScript.params, { types = E.types }, n .. ": the types ride in captureParams")
		for _, x in ipairs(E.types) do ok(not covered[x], "type in one entry"); covered[x] = true end
		eq(con.availability.yearFrom, 1940)
		eq(con.menuCategory.categories[1].category, "street_constructions")
		local order = con.menuCategory.categories[1].order
		-- next to the base interchanges: parclos after the cloverleaf (6000) / diverging diamond (6001),
		-- the diamond after the base diamond (7000)
		eq(order, E.order, n)
		ok(not orders[order], n .. ": unique order"); orders[order] = true
		-- the Layout row: first, one button per type, the button index picks the type (hx.specFor)
		local layout = con.params[1].key == hx.LAYOUT_KEY and table.remove(con.params, 1) or nil
		if #E.types > 1 then
			ok(layout ~= nil, n .. ": Layout row first")
			eq(layout.name, "Layout"); eq(layout.values, E.labels); eq(layout.defaultIndex, 1)
			eq(layout.uiType, "Button"); eq(layout.displayMode, "Horizontal")
			for line in layout.tooltip:gmatch("[^\n]+") do ok(#line <= 62, "Layout tooltip line: " .. line) end
			for i, x in ipairs(E.types) do
				eq(hx.specFor(con.updateScript.params, { [hx.LAYOUT_KEY] = i }).type, x, n .. " layout " .. i)
				-- the probe's sqrb_hx_type without the Layout key; the Layout key wins
				eq(hx.specFor(con.updateScript.params, { [K.type] = x }).type, x, n .. " type " .. x)
				eq(hx.specFor(con.updateScript.params, { [hx.LAYOUT_KEY] = i, [K.type] = E.types[#E.types + 1 - i] }).type, x)
			end
			eq(hx.specFor(con.updateScript.params, { [K.type] = hx.TYPE_DIAMOND }).type, E.types[1], "foreign type")
		else
			eq(layout, nil, n .. ": no Layout row")
			eq(hx.specFor(con.updateScript.params, { [K.type] = hx.TYPE_A4 }).type, t)
		end
		eq(con.checkEnabledScript, nil)
		local byKey, keys = {}, {}
		local shared = { [K.highway] = true, [K.cross] = true, [K.direction] = true }
		for _, p in ipairs(con.params) do
			ok(byKey[p.key] == nil, "duplicate key " .. p.key)
			byKey[p.key] = p
			keys[#keys + 1] = p.key
			ok(p.key:sub(1, 8) == "sqrb_hx_" or shared[p.key], "entry-specific keys are sqrb_hx_: " .. p.key)
			ok(#p.values >= 2, p.key)
			ok((p.defaultIndex or 1) >= 1 and (p.defaultIndex or 1) <= #p.values, p.key .. " default in range")
			eq(p.checkEnabledScript, nil, p.key .. " has no checkEnabledScript")
			ok(type(p.tooltip) == "string" and #p.tooltip > 0, p.key .. " tooltip")
			for line in p.tooltip:gmatch("[^\n]+") do ok(#line <= 62, p.key .. " tooltip line: " .. line) end
			-- a row of buttons, as the base interchanges (Lanes [2][3], Scale [Small][Medium][Large]);
			-- only the six cross roads are a dropdown; no slider
			if p.key == K.cross then
				eq(p.uiType, "ComboBox")
			else
				eq(p.uiType, "Button", p.key); eq(p.displayMode, "Horizontal", p.key)
				ok(#p.values <= 3, p.key .. ": at most 3 buttons")
				local chars = 0
				for _, v in ipairs(p.values) do chars = chars + #v end
				ok(chars <= 24, p.key .. ": short labels")
			end
		end
		-- no Type param; every other param in the 7c order
		eq(keys, { K.highway, K.level, K.cross, K.size, K.rampLength, K.armLength, K.direction }, n .. ": UI order")
		for _, dk in pairs(geom.DEV_KEYS) do eq(byKey[dk], nil, "dev key " .. tostring(dk)) end
		for key in pairs(byKey) do ok(not key:find("dev") and not key:find("tmp"), key) end
		eq(#byKey[K.highway].values, #ramps.HIGHWAYS); eq(#byKey[K.level].values, 2)
		eq(#byKey[K.cross].values, #geom.ARM_TEMPLATES)
		eq(byKey[K.size].name, "Scale"); eq(byKey[K.size].values, { "S", "M", "L" })
		eq(#byKey[K.size].values, #hx.LOOP_RADII)
		ok(byKey[K.size].tooltip:find(t == hx.TYPE_DIAMOND and "the bridge and run" or "loop ramp radius", 1, true), n .. ": Scale tooltip per type")
		ok(byKey[K.size].tooltip:find("footprint", 1, true), n .. ": Scale tooltip names the footprint")
		eq(byKey[K.rampLength].values, { "Short", "Medium", "Long" }); eq(#hx.RAMP_EXTRAS, 3)
		eq(byKey[K.armLength].values, { "30 m", "45 m", "60 m" }); eq(#hx.ARM_LENGTHS, 3)
		eq(#byKey[K.direction].values, 2)
		-- shared keys keep the Roundabout Interchange's value counts and meaning
		local ixCon = loadData("square_roundabouts_interchange.con.lua")
		for _, p in ipairs(ixCon.params) do
			if shared[p.key] then eq(#byKey[p.key].values, #p.values, p.key) end
			if p.key == K.highway or p.key == K.cross then eq(byKey[p.key].values, p.values, p.key) end
		end
		local d = {}
		for _, p in ipairs(con.params) do d[p.key] = p.defaultIndex or 1 end
		local want = hx.readParams({})
		want.type = t
		eq(hx.specFor(con.updateScript.params, d), want, n .. ": con defaults = readParams fallbacks")
	end
	for x = 1, #hx.TYPES do ok(covered[x], "type " .. x .. " has an entry") end
	-- 7c2's six entries are gone
	for _, old in ipairs({ "parclo_a4", "parclo_b4", "parclo_a2", "parclo_b2", "parclo_ab2" }) do
		ok(not pcall(loadData, "square_roundabouts_highway_" .. old .. ".con.lua"), old .. " removed")
	end
	-- the old single entry is gone
	local okOld = pcall(loadData, "square_roundabouts_highway.con.lua")
	ok(not okOld, "no single Highway Interchange entry")

	local script = loadData("square_roundabouts_highway.script.lua")
	local keys = {}
	for k in pairs(script) do keys[#keys + 1] = k end
	eq(keys, { "updateFn" })
	for _, level in ipairs({ 1, 2 }) do
		for _, year in ipairs({ 1940, 1969, 1970, 2000, false }) do
			local p = params({ level = level })
			if year then p.year = year end
			local r = script.updateFn({}, p)
			eq(r.subconstructions, nil); eq(r.models, {}); eq(r.groundFaces, {}); eq(r.cost, 0)
			local bridges = 0
			for _, el in ipairs(r.edgeLists) do
				eq(el.type, "STREET"); eq(el.snapNodes, {})
				eq(#el.freeNodes, #el.edges, "every node free")
				for i, nd in ipairs(el.freeNodes) do eq(nd, i - 1) end
				ok(el.params.type:sub(1, 3) == "::/", el.params.type)
				if el.edgeType then
					bridges = bridges + 1
					eq(el.edgeType, "BRIDGE")
					eq(el.edgeTypeName, (year and year < 1970) and ramps.BRIDGE_STEEL or ramps.BRIDGE_CONCRETE)
				else
					eq(el.edgeTypeName, nil)
				end
			end
			eq(bridges, 1, "one bridge list (cross road, or both carriageways)")
		end
	end
	-- the script builds exactly hx.build for any params, the entry's type from captureParams
	local p = params({ type = hx.TYPE_A4, size = 3, rampLength = 3, direction = 2, year = 1950 })
	local res = script.updateFn({ type = hx.TYPE_DIAMOND }, p)
	local sp = hx.readParams(p)
	sp.type = hx.TYPE_DIAMOND
	local want = hx.build(sp)
	local n = 0
	for _, l in ipairs(want.lists) do n = n + #l.edges end
	local got = 0
	for _, el in ipairs(res.edgeLists) do got = got + #el.edges end
	eq(got, 2 * n, "two node entries per edge")
end)

test("lists: roles, templates, bridges, ramps and loops per type and level", function()
	local want = { A4 = { 6, 2 }, B4 = { 6, 2 }, A2 = { 4, 2 }, B2 = { 4, 2 }, AB2 = { 4, 2 }, Diamond = { 4, 0 } }
	for t = 1, #hx.TYPES do
		for level = 1, 2 do
			local b = build({ type = t, level = level })
			local n = b.type .. " level " .. level
			eq(b.type, hx.TYPES[t].name)
			local roles = {}
			for _, l in ipairs(b.lists) do
				local key = l.role .. (l.edgeType and "+bridge" or "")
				roles[key] = (roles[key] or 0) + #l.edges
				if l.role == "highway" then eq(l.template, ramps.HIGHWAYS[ramps.DEFAULT_HIGHWAY].template) end
				if l.role == "ramps" then eq(l.template, ramps.RAMP.template) end
				if l.role == "cross" or l.role == "arms" then eq(l.template, geom.ARM_TEMPLATES[hx.DEFAULT_CROSS]) end
			end
			local by, order = rampsOf(b)
			local loops = 0
			for _, id in ipairs(order) do if by[id][1].kind == "l" then loops = loops + 1 end end
			eq({ #order, loops }, want[b.type], n .. ": ramps, loops")
			eq(roles.arms, 2, n)
			if level == hx.LEVEL_ROAD_OVER then
				eq(b.zCross, H); eq(b.zHighway, 0); eq(b.xb, nil)
				eq(roles["highway+bridge"], nil, n); eq(roles["cross+bridge"], 1, n)
			else
				eq(b.zCross, 0); eq(b.zHighway, H); eq(b.yb, nil)
				eq(roles["highway+bridge"], 2, n .. ": one bridge per carriageway"); eq(roles["cross+bridge"], nil, n)
				eq(b.xb, b.frame.xCross, n .. ": bridge half = hx.frame's xCross")
			end
		end
	end
end)

-- The full sweep, one test per type (the runner shards them): every highway x level x traffic
-- side x Size x cross road {town small, town large, country small, country large} x the shortest and
-- longest ramp length. Overlaps on right-hand traffic (left-hand is the exact mirror, tested below)
-- with the widest town and the narrowest country road.
local function sweepTest(t)
	test("sweep " .. hx.TYPES[t].name .. ": every highway x level x side x Size x cross road x ramp length extremes", function()
		local count, total, worst = 0, 0, 0
		each({ type = { t }, highway = { 1, 2, 3 }, level = { 1, 2 }, direction = { 1, 2 }, size = { 1, 2, 3 },
			cross = { 1, 3, 4, 6 }, rampLength = { 1, #hx.RAMP_EXTRAS } }, function(o)
			local t0 = os.clock()
			local b = build(o)
			local dt = os.clock() - t0
			total, worst = total + dt, math.max(worst, dt)
			count = count + 1
			local n = name(o)
			-- Size and ramp length are minimums; shipped params never grow the Size
			eq(b.size, (t == hx.TYPE_DIAMOND and hx.TERMINAL_DISTANCES or hx.LOOP_RADII)[o.size], n .. ": Size kept")
			ok(b.xm >= rampStart(b) - 1e-9, n .. ": ramp length at least shortest + extra")
			checkBuild(b, n, o.direction == 1 and (o.cross == 3 or o.cross == 4))
		end)
		print(string.format("    %d builds: hx.build mean %.2f ms, max %.2f ms; smallest free length %.1f m; separation at crossings >= %.1f m",
			count, total / count * 1000, worst * 1000, stats.free, stats.minSep))
		for _, k in ipairs({ "d", "l" }) do
			if stats["avg_" .. k] then
				print(string.format("    %s: climb avg <= %.1f %%, peak <= %.1f %%, shortest climb %.0f m", k == "d" and "diagonals" or "loops",
					stats["avg_" .. k] * 100, stats["peak_" .. k] * 100, stats["min_" .. k]))
			end
		end
	end)
end
for t = 1, #hx.TYPES do sweepTest(t) end

test("arm length: every value passes; the cross road and highway run on by it", function()
	each({ type = { 1, 6 }, armLength = { 1, 2, 3 }, level = { 1, 2 } }, function(o)
		local b = build(o)
		checkBuild(b, name(o), false)
		local L = hx.ARM_LENGTHS[o.armLength]
		for _, l in ipairs(b.lists) do
			if l.role == "arms" then
				for _, e in ipairs(l.edges) do near(S.dist(e.p0, e.p1), L, 1e-9) end
			end
		end
	end)
end)

test("gores per carriageway in driving order (A: off then loop on; B: loop off then on)", function()
	local want = {
		A4 = { s = "off,loop on,on", n = "off,loop on,on" },
		B4 = { s = "off,loop off,on", n = "off,loop off,on" },
		A2 = { s = "off,loop on", n = "off,loop on" },
		B2 = { s = "loop off,on", n = "loop off,on" },
		AB2 = { s = "off,loop on", n = "loop off,on" },
		Diamond = { s = "off,on", n = "off,on" },
	}
	for t = 1, #hx.TYPES do
		for direction = 1, 2 do
			for level = 1, 2 do
				local b = build({ type = t, direction = direction, level = level })
				local gores = { s = {}, n = {} }
				for _, e in ipairs(b.ramps) do
					if e.part == "gore" then
						local node, hdir = mergeOf(b, e)
						local cw = node[2] < 0 and "s" or "n"
						local l = gores[cw]
						l[#l + 1] = { at = S.dot(node, hdir), what = (e.kind == "l" and "loop " or "") .. (e.io == "in" and "off" or "on") }
					end
				end
				for cw, l in pairs(gores) do
					table.sort(l, function(a, c) return a.at < c.at end)
					local seq = {}
					for i, g in ipairs(l) do seq[i] = g.what end
					eq(table.concat(seq, ","), want[b.type][cw], b.type .. " " .. cw .. " direction " .. direction)
				end
			end
		end
	end
end)

local function rot(p) return { -p[1], -p[2], p[3] } end
local function mir(p) return { -p[1], p[2], p[3] } end
local function quadEdges(b, q)
	local out = {}
	for _, e in ipairs(b.ramps) do if e.quad == q then out[#out + 1] = e end end
	return out
end
local function sameGeometry(got, want, n)
	eq(#got, #want, n .. ": edge count")
	for i, e in ipairs(want) do
		for _, k in ipairs({ "p0", "t0", "p1", "t1" }) do
			for c = 1, 3 do near(got[i][k][c], e[k][c], 1e-9, n .. " edge " .. i .. " " .. k) end
		end
		eq(got[i].part, e.part, n)
	end
end
--- want = SW mirrored in x with every edge reversed (in reverse order)
local function mirrorReverse(edges)
	local out = {}
	for i = #edges, 1, -1 do
		local e = edges[i]
		local t0, t1 = mir(e.t1), mir(e.t0)
		out[#out + 1] = { p0 = mir(e.p1), t0 = { -t0[1], -t0[2], -t0[3] }, p1 = mir(e.p0), t1 = { -t1[1], -t1[2], -t1[3] }, part = e.part }
	end
	return out
end
local function rotated(edges)
	local out = {}
	for i, e in ipairs(edges) do out[i] = { p0 = rot(e.p0), t0 = rot(e.t0), p1 = rot(e.p1), t1 = rot(e.t1), part = e.part } end
	return out
end

test("quadrant symmetry: NE = SW rotated, SE = SW mirror-reversed, NW = SE rotated (exact to 1e-9)", function()
	each({ highway = { 1, 3 }, level = { 1, 2 }, size = { 1, 3 }, cross = { 1, 6 } }, function(o)
		local n = name(o)
		o.type = hx.TYPE_DIAMOND
		local d = build(o)
		sameGeometry(quadEdges(d, "ne"), rotated(quadEdges(d, "sw")), n .. " diamond ne")
		sameGeometry(quadEdges(d, "se"), mirrorReverse(quadEdges(d, "sw")), n .. " diamond se")
		sameGeometry(quadEdges(d, "nw"), rotated(quadEdges(d, "se")), n .. " diamond nw")
		o.type = hx.TYPE_A4
		local a4 = build(o)
		sameGeometry(quadEdges(a4, "ne"), rotated(quadEdges(a4, "sw")), n .. " A4 ne")
		o.type = hx.TYPE_A2
		local a2 = build(o)
		o.type = hx.TYPE_B2
		local b2 = build(o)
		eq(a2.xm, b2.xm, n); eq(a2.R, b2.R, n)
		sameGeometry(quadEdges(b2, "se"), mirrorReverse(quadEdges(a2, "sw")), n .. " B = mirror-reverse(A)")
		sameGeometry(quadEdges(b2, "nw"), rotated(quadEdges(b2, "se")), n .. " B2 nw")
		o.type = hx.TYPE_AB2
		local ab2 = build(o)
		sameGeometry(quadEdges(ab2, "sw"), quadEdges(a2, "sw"), n .. " AB2 sw")
		sameGeometry(quadEdges(ab2, "nw"), quadEdges(b2, "nw"), n .. " AB2 nw")
	end)
end)

test("traffic side: left-hand traffic is the right-hand build mirrored in x", function()
	each({ type = { 1, 2, 3, 4, 5, 6 }, highway = { 1, 3 }, level = { 1, 2 } }, function(o)
		local r = build(o)
		o.direction = 2
		local l = build(o)
		local n = name(o)
		eq(l.mirrored, true); eq(r.mirrored, false); eq(#l.lists, #r.lists, n)
		for i, list in ipairs(r.lists) do
			eq(l.lists[i].template, list.template); eq(l.lists[i].edgeType, list.edgeType)
			eq(#l.lists[i].edges, #list.edges, n)
			for j, e in ipairs(list.edges) do
				local m = l.lists[i].edges[j]
				for _, k in ipairs({ "p0", "t0", "p1", "t1" }) do
					local w = mir(e[k])
					for c = 1, 3 do near(m[k][c], w[c], 1e-9, n) end
				end
				eq(m.tag0, e.tag0); eq(m.tag1, e.tag1)
			end
		end
	end)
end)

test("every param changes the build, for every type", function()
	local function sig(b)
		local parts = {}
		for _, l in ipairs(b.lists) do
			parts[#parts + 1] = l.template .. tostring(l.edgeType) .. tostring(l.edgeTypeName)
			for _, e in ipairs(l.edges) do
				parts[#parts + 1] = string.format("%.3f,%.3f,%.3f,%.3f,%.3f", e.p0[1], e.p0[2], e.p0[3], e.p1[1], e.p1[2])
			end
		end
		return table.concat(parts, ";")
	end
	local counts = { type = #hx.TYPES, highway = 3, level = 2, cross = 6, size = #hx.LOOP_RADII, rampLength = #hx.RAMP_EXTRAS,
		armLength = #hx.ARM_LENGTHS, direction = 2 }
	for t = 1, #hx.TYPES do
		-- the defaults, and the largest loops (the 7b absolute slider was dead there)
		for _, base in ipairs({ { type = t }, { type = t, size = #hx.LOOP_RADII, cross = 3, highway = 3 } }) do
			for field, n in pairs(counts) do
				local seen = {}
				for v = 1, n do
					local o = {}
					for k, x in pairs(base) do o[k] = x end
					o[field] = v
					local b = build(o)
					local s = sig(b)
					-- Phase 7e2: a ramp length capped by hx.MAX_REACH builds the cap (Scale Large, large highway)
					local capped = field == "rampLength" and seen[s] and hx.reach(b) >= hx.MAX_REACH[b.spec.level] - 1e-9
					ok(capped or not seen[s], string.format("type %d: %s = %d builds the same as %s", t, field, v, tostring(seen[s])))
					seen[s] = seen[s] or v
				end
			end
		end
	end
	-- Ramp length = shortest + extra exactly, for every type x Size (no growth with shipped params)
	each({ type = { 1, 2, 3, 4, 5, 6 }, size = { 1, 2, 3 }, rampLength = { 1, 2, 3 } }, function(o)
		local b = build(o)
		near(b.xm, rampStart(b), 1e-9, name(o))
		if o.type == hx.TYPE_DIAMOND then near(b.xm, hx.DIAMOND_RAMP_MINS[o.size] + hx.RAMP_EXTRAS[o.rampLength], 1e-9) end
	end)
end)

-- Phase 7c3 (user: "Scale often makes no visible difference"): the ramp footprint (bounding box of
-- every ramp edge) grows clearly with Scale, in both directions, for every type, highway, level,
-- cross road and ramp length: Medium >= 1.45 x Small, Large >= 2.2 x Small (hx.SCALES 1 / 1.6 / 2.5).
test("Scale: Small / Medium / Large footprints differ clearly", function()
	local function box(b)
		local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
		for _, e in ipairs(b.ramps) do
			for _, p in ipairs({ e.p0, e.p1 }) do
				x0, x1 = math.min(x0, p[1]), math.max(x1, p[1])
				y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
			end
		end
		return x1 - x0, y1 - y0
	end
	local cappedCount = 0
	each({ type = { 1, 2, 3, 4, 5, 6 }, highway = { 1, 2, 3 }, level = { 1, 2 }, cross = { 1, 6 }, rampLength = { 1, 3 } }, function(o)
		local w, h, capped = {}, {}, {}
		for s = 1, 3 do
			o.size = s
			local b = build(o)
			w[s], h[s] = box(b)
			capped[s] = hx.reach(b) >= hx.MAX_REACH[b.spec.level] - 1e-9
		end
		o.size = nil
		local n = name(o)
		-- x: 1.45 / 2.2 at Short; Long adds the same +60 m to every Scale. Phase 7e2: a Scale capped
		-- by hx.MAX_REACH only has to stay wider than the Scale below.
		local extra = 2 * hx.RAMP_EXTRAS[o.rampLength]
		ok(not capped[1] and not capped[2], n .. ": Small / Medium within the reach cap")
		ok(w[2] - extra >= 1.45 * (w[1] - extra) - 1e-6, n .. string.format(": width %.0f / %.0f", w[1], w[2]))
		if capped[3] then
			cappedCount = cappedCount + 1
			ok(w[3] > w[2] + 50, n .. string.format(": capped width %.0f / %.0f", w[2], w[3]))
		else
			ok(w[3] - extra >= 2.2 * (w[1] - extra) - 1e-6, n .. string.format(": width %.0f / %.0f", w[1], w[3]))
		end
		-- y: the diamond's Small is the highway band plus the ramps (no terminal distance)
		local hm = o.type == hx.TYPE_DIAMOND and 1.6 or 1.45
		local hl = o.type == hx.TYPE_DIAMOND and 2.8 or 2.2
		ok(h[2] >= hm * h[1] - 1e-6, n .. string.format(": depth %.0f / %.0f", h[1], h[2]))
		ok(h[3] >= hl * h[1] - 1e-6, n .. string.format(": depth %.0f / %.0f", h[1], h[3]))
	end)
	print(string.format("    %d of 288 type x highway x level x cross x ramp groups: Scale Large capped by hx.MAX_REACH", cappedCount))
end)

-- Phase 7e2 (probe p7_hx_scale): the engine refused every Scale Large parclo whose highway ends
-- reached |x| >= 486.25 m from the origin and placed every one up to 481.25 m ("Highway over road"
-- up to 462.5 m); edge lengths, gradients and the y reach did not separate them. Every build, every
-- param, stays within hx.MAX_REACH[level] along both axes (|x|, |y| of every edge point; the probe
-- cannot tell an axis limit from a radial one: the highway ends sit 6.5-13.5 m off the axis), and the
-- probe's placed layouts are kept: the ones at the cap are exactly the measured maxima.
test("reach: every build's edges within hx.MAX_REACH of the origin (engine limit, p7_hx_scale)", function()
	local count, capped, worst = 0, 0, { 0, 0 }
	each({ type = { 1, 2, 3, 4, 5, 6 }, highway = { 1, 2, 3 }, level = { 1, 2 }, cross = { 1, 2, 3, 4, 5, 6 },
		size = { 1, 2, 3 }, rampLength = { 1, 2, 3 }, armLength = { 1, 2, 3 }, direction = { 1 } }, function(o)
		local b = build(o)
		local n = name(o)
		count = count + 1
		ok(not b.forced, n .. ": not forced")
		local r = 0
		for _, l in ipairs(b.lists) do
			for _, e in ipairs(l.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do r = math.max(r, math.abs(p[1]), math.abs(p[2])) end
			end
		end
		local lim = hx.MAX_REACH[o.level]
		ok(r <= lim + 1e-6, n .. string.format(": reach %.2f m > %.2f m", r, lim))
		near(hx.reach(b), b.xm + hx.ARM_LENGTHS[o.armLength], 1e-9, n .. ": reach = highway end")
		near(r, hx.reach(b), 1e-9, n .. ": hx.reach is the furthest edge point")
		worst[o.level] = math.max(worst[o.level], r)
		if hx.reach(b) >= lim - 1e-9 then
			capped = capped + 1
			eq(o.size, 3, n .. ": only Scale Large reaches the cap")
		end
	end)
	print(string.format("    %d builds; %d at the cap; largest reach %.2f m (road over) / %.2f m (highway over)",
		count, capped, worst[1], worst[2]))
end)

test("plan: Size kept, ramp length a minimum; parclo layout numbers", function()
	each({ type = { 1, 6 }, highway = { 1, 2, 3 }, level = { 1, 2 }, cross = { 1, 3, 6 }, size = { 1, 3 } }, function(o)
		local spec = hx.readParams(params(o))
		local b = hx.build(spec)
		local f = b.frame
		local n = name(o)
		if spec.type == hx.TYPE_DIAMOND then
			eq(b.size, hx.TERMINAL_DISTANCES[o.size]); eq(b.R, nil); eq(b.yTi, nil)
			near(b.yTo, f.yClear + f.hwRamp + b.size, 1e-9, n)
		else
			local gap = hx.TERM_GAPS[o.size]
			eq(b.R, hx.LOOP_RADII[o.size], n); eq(b.Ro, b.R + gap, n)
			near(b.yTi, f.yg + 2 * b.R, 1e-9, n); near(b.yTo, b.yTi + gap, 1e-9, n)
			ok(b.dx - b.R - f.hwRamp >= f.hwX + f.clear - 1e-9, n .. ": loop clear of the cross road")
			ok(b.xm >= b.dx + b.Ro + b.R + f.run - 1e-9, n .. ": wrapped diagonal outside the loop")
		end
		-- the smaller ramp lengths from the slider up do not fit (or are below the layout minimum)
		for x = rampStart(b), b.xm - 1e-9, hx.RAMP_GROW_STEP do
			local lay = hx.layout(spec, f, b.size, x)
			ok(lay.xm == b.xm or not hx.fits(lay), n .. ": " .. x .. " m fits")
		end
	end)
	-- the cross road bridge: the tight diamond ends it at the terminals
	local tight = build({ type = hx.TYPE_DIAMOND, size = 1 })
	eq(tight.yb, tight.yTo)
	local wide = build({ type = hx.TYPE_DIAMOND, size = 2 })
	eq(wide.yb, wide.frame.yClear)
	-- a layout that never fits (dev terminal gap below two ramp widths): the plan flags it forced
	local spec = hx.readParams({})
	spec.dev = { hxTermGap = 5 }
	local forced = hx.build(spec)
	eq(forced.forced, true); eq(forced.R, hx.GROW_RADII[#hx.GROW_RADII])
end)

-- Phase 7e (probe p7_hx_all): "Highway over road" refused every large-highway parclo whose loop
-- carriageway node was 10.5 m from the highway bridge's end (25 / 35 m loops) and placed it at
-- 17.5 m (45 m loops); small / medium placed at 10 m. hx.BRIDGE_PIECE keeps that piece.
test("highway over road: loop carriageway nodes keep hx.BRIDGE_PIECE from the highway bridge end", function()
	eq(hx.BRIDGE_PIECE, { 10, 10, 17.5 })
	local function piece(b)
		local worst = math.huge
		for _, e in ipairs(b.ramps) do
			if e.kind == "l" and e.part == "gore" then
				for _, p in ipairs({ e.p0, e.p1 }) do
					if math.abs(math.abs(p[2]) - (b.frame.c + ramps.MERGE_OFFSET)) < 1e-9 then
						worst = math.min(worst, math.abs(p[1]) - b.xb)
					end
				end
			end
		end
		return worst
	end
	local function highwayText(b)
		local out = {}
		for _, l in ipairs(b.lists) do
			if l.role == "highway" then
				for _, e in ipairs(l.edges) do
					-- the carriageway near the bridge: the edges within 40 m of the cross road
					if math.max(math.abs(e.p0[1]), math.abs(e.p1[1])) < 40 then
						out[#out + 1] = string.format("%s %.3f,%.3f,%.3f %.3f,%.3f,%.3f", l.edgeType or "-",
							e.p0[1], e.p0[2], e.p0[3], e.p1[1], e.p1[2], e.p1[3])
					end
				end
			end
		end
		table.sort(out)
		return table.concat(out, "\n")
	end
	each({ type = { 1, 2, 3, 4, 5 }, highway = { 1, 2, 3 }, cross = { 1, 3, 4, 6 }, size = { 1, 2, 3 } }, function(o)
		o.level = hx.LEVEL_HIGHWAY_OVER
		local b = build(o)
		local n = name(o)
		ok(piece(b) >= hx.BRIDGE_PIECE[o.highway] - 1e-9, n .. ": piece " .. piece(b))
		if o.highway < 3 and o.size == 1 then near(piece(b), geom.MIN_EDGE, 0.5 + 1e-9, n .. ": small / medium unchanged") end
	end)
	-- large highway, 25 / 35 m loops: the carriageway pieces, loop carriageway nodes and bridge ends
	-- near the cross road are the 45 m loop's (which the engine placed)
	for _, cross in ipairs({ 2, 3, 4 }) do
		local ref = build({ type = 1, highway = 3, level = 2, cross = cross, size = 2 }) -- 45 m loops
		near(piece(ref), 17.5, 1e-9)
		for size = 1, 1 do
			local b = build({ type = 1, highway = 3, level = 2, cross = cross, size = size })
			eq(b.dx, ref.dx, "dx"); eq(b.R, hx.LOOP_RADII[size], "Size kept")
			eq(highwayText(b), highwayText(ref), "cross " .. cross .. " size " .. size)
		end
	end
end)

test("fits: rejects a too short diamond ramp; the plan then lengthens it", function()
	local spec = hx.readParams(params({ type = hx.TYPE_DIAMOND, size = 3, rampLength = 1 }))
	local f = hx.frame(spec)
	local lay = hx.layout(spec, f, 50, 40)
	local okFit, why = hx.fits(lay)
	eq(okFit, false); ok(why ~= nil)
	-- a layout that fits, then one with gores overlapping the cross road (highway over)
	ok(hx.fits(hx.layout(spec, f, 50, 160)))
end)

-- Phase 7e fix-up round 13: the construction tool's transform at rotation 0 is (cos, sin) = (1, -0);
-- a tangent (+x, -0) stayed (+x, -0) in the world and the engine refused the layout (the SE on-ramp).
test("no negative zero in any highway build; the tool's 0-degree transform keeps every tangent's y +0 or nonzero", function()
	local function isNeg0(v) return v == 0 and 1 / v < 0 end
	local n = 0
	for t = 1, #hx.TYPES do for h = 1, 3 do for lv = 1, 2 do for dir = 1, 2 do for sz = 1, #hx.LOOP_RADII do
		local p = { year = 2020, [K.type] = t, [K.highway] = h, [K.level] = lv, [K.direction] = dir, [K.size] = sz }
		local b = hx.build(hx.readParams(p))
		for _, l in ipairs(b.lists) do
			for _, e in ipairs(l.edges) do
				for _, v in ipairs({ e.p0, e.p1, e.t0, e.t1 }) do
					for i = 1, 3 do ok(not isNeg0(v[i]), "-0 in " .. l.role .. " t" .. t .. " h" .. h .. " v" .. lv .. " d" .. dir) end
				end
				for _, tg in ipairs({ e.t0, e.t1 }) do
					local wy = (-0.0) * tg[1] + 1 * tg[2]
					ok(not isNeg0(wy), "world tangent y -0")
					n = n + 1
				end
			end
		end
	end end end end end
	ok(n > 1000)
	-- hx.positiveZeros turns the old SE on-ramp's (+x, -0, -0) tangent into (+x, +0, +0), in place
	local e = { p0 = { 1, -0.0, 0 }, p1 = { 2, 0, -0.0 }, t0 = { 1, -0.0, -0.0 }, t1 = { -0.0, 1, 0 } }
	ok(isNeg0(e.t0[2]))
	hx.positiveZeros({ { edges = { e } } })
	for _, v in ipairs({ e.p0, e.p1, e.t0, e.t1 }) do for i = 1, 3 do ok(not isNeg0(v[i])) end end
	eq(e.t0, { 1, 0, 0 }); eq(e.t1[2], 1)
end)
