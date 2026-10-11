-- Channelized Junction (square_roundabouts_channel.lua, .con.lua, .script.lua): PHASE5.md Phase 5b.
-- Short edges and the availability year are checked with the other entries in test_short_edges.lua.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local ch = ug_require(DIR .. "square_roundabouts_channel.lua")
local S = geom.shapes
local K = ch.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end

local function params(over)
	local p = {}
	for k, v in pairs(over or {}) do p[K[k]] = v end
	return p
end

local function build(over) return ch.build(ch.readParams(params(over))) end

local function name(o)
	return string.format("layout %d main %d side %d slips %d splitter %d len %d dir %d island %d scale %d",
		o.layout or 1, o.main or ch.DEFAULT_MAIN, o.side or ch.DEFAULT_SIDE, o.slips or 1, o.splitter or 1,
		o.armLength or 1, o.direction or 1, o.island or 1, o.scale or ch.DEFAULT_SCALE)
end

--- fn(over) for layout x main x side x slips x splitter (432 combos), plus the given fields.
local function each(extra, fn)
	for layout = 1, 2 do
		for main = 1, #geom.ARM_TEMPLATES do
			for side = 1, #geom.ARM_TEMPLATES do
				for slips = 1, 3 do
					for splitter = 1, 2 do
						local o = { layout = layout, main = main, side = side, slips = slips, splitter = splitter }
						for k, v in pairs(extra or {}) do o[k] = v end
						fn(o)
					end
				end
			end
		end
	end
end

-- A slip lane's gore (where it runs beside the arm it leaves or joins at SLIP_ANGLE) is one
-- junction: the bands overlap from the shared node until the slip lane is a band width out,
-- (hwA + hwB + margin) / sin(angle) along a straight slip lane (up to 36.5 m for large roads at
-- 40 degrees, over the 30 m default). checks.engineModel bounds that junction separately: every
-- edge keeps >= 2.5 m outside it. Every other pair keeps the default limit.
local function goreLimit(A, B, default)
	if A.role == "slips" or B.role == "slips" then
		return math.max(default, (A.hw + B.hw + 0.5) / math.sin(ch.SLIP_ANGLE) + 1)
	end
	return default
end

local function mirrorOf(p) return { -p[1], p[2], p[3] } end
local function near3(a, b, msg)
	for i = 1, 3 do near(a[i], b[i], 1e-9, msg) end
end
local function right(h) return { h[2], -h[1], 0 } end

test("readParams: defaults and foreign values", function()
	eq(ch.readParams({}), {
		layout = ch.LAYOUT_T, main = ch.DEFAULT_MAIN, side = ch.DEFAULT_SIDE, slips = ch.SLIPS_NEAR,
		splitter = ch.SPLITTER_OFF, armLength = ch.DEFAULT_ARM_LENGTH, scale = ch.DEFAULT_SCALE,
		direction = geom.DIRECTION_CCW, island = 1,
	})
	eq(ch.readParams({ sqrb_ch_scale = 6 }).scale, ch.DEFAULT_SCALE, "foreign Scale value")
	-- sqrb_island is the roundabouts' 5-value param: this entry has its own key
	eq(ch.readParams({ sqrb_island = 5, sqrb_ch_island = 4, sqrb_ch_layout = 3 }).island, 1)
	eq(ch.readParams({ sqrb_ch_layout = 3 }).layout, ch.LAYOUT_T)
	eq(ch.readParams({ sqrb_direction = 2 }).direction, geom.DIRECTION_CW, "shares the Direction key")
end)

test(".con.lua: params, script, icon, availability; script exports only updateFn", function()
	local con = loadData("square_roundabouts_channel.con.lua")
	eq(con.description.name, "Channelized Junction")
	eq(con.description.icon, "square_roundabouts_channel.tga", "own icon (the game loads the @2x file)")
	eq(con.updateScript.fileName, "square_roundabouts_channel.script@updateFn")
	eq(con.availability.yearFrom, 1940)
	eq(con.menuCategory.categories[1].category, "street_constructions")
	local byKey, order = {}, {}
	for _, p in ipairs(con.params) do
		ok(byKey[p.key] == nil, "duplicate key " .. p.key)
		byKey[p.key] = p
		order[#order + 1] = p.key
		ok(p.key:sub(1, 5) == "sqrb_", "prefixed key " .. p.key)
		ok(#p.values >= 2, p.key)
		ok((p.defaultIndex or 1) >= 1 and (p.defaultIndex or 1) <= #p.values, p.key .. " default in range")
		eq(p.checkEnabledScript, nil, p.key .. " has no checkEnabledScript")
	end
	eq(order, { K.layout, K.scale, K.main, K.side, K.slips, K.splitter, K.armLength, K.direction, K.island }, "UI order")
	-- revision 6: Scale, a row of size codes like the Magic Roundabout's, default XS (the only layout before)
	eq(byKey[K.scale].name, "Scale"); eq(byKey[K.scale].uiType, "Button"); eq(byKey[K.scale].displayMode, "Horizontal")
	eq(byKey[K.scale].values, { "XS", "S", "M", "L", "XL" }); eq(#ch.SCALES, 5)
	eq(byKey[K.scale].defaultIndex, 1); eq(ch.SCALES[ch.DEFAULT_SCALE], 1)
	for i, f in ipairs(ch.SCALES) do
		ok(byKey[K.scale].tooltip:find(i == 1 and "XS" or tostring(f), 1, true) ~= nil, "tooltip names factor " .. f)
	end
	eq(#byKey[K.main].values, #geom.ARM_TEMPLATES); eq(#byKey[K.side].values, #geom.ARM_TEMPLATES)
	eq(#byKey[K.armLength].values, #ch.ARM_LENGTHS); eq(#byKey[K.island].values, #ch.ISLAND_KINDS)
	-- Phase 7c3: Arm length is a row of buttons (was a slider), same key and indices; no slider left
	eq(byKey[K.armLength].uiType, "Button"); eq(byKey[K.armLength].displayMode, "Horizontal")
	eq(byKey[K.armLength].values, { "30 m", "40 m", "50 m", "60 m" })
	for _, p in ipairs(con.params) do ok(p.uiType ~= "Slider", p.key .. " is no slider") end
	eq(#byKey[K.slips].values, 3); eq(#byKey[K.layout].values, 2)
	local d = {}
	for _, p in ipairs(con.params) do d[p.key] = p.defaultIndex or 1 end
	eq(ch.readParams(d), ch.readParams({}), "con defaults = readParams fallbacks")

	local script = loadData("square_roundabouts_channel.script.lua")
	local keys = {}
	for k in pairs(script) do keys[#keys + 1] = k end
	eq(keys, { "updateFn" })
	local r = script.updateFn({}, {})
	eq(r.subconstructions, nil, "Islands None by default")
	eq(r.models, {}); eq(r.groundFaces, {}); eq(r.cost, 0)
	for _, el in ipairs(r.edgeLists) do
		eq(el.type, "STREET"); eq(el.snapNodes, {})
		eq(#el.freeNodes, #el.edges, "every node free")
		for i, n in ipairs(el.freeNodes) do eq(n, i - 1) end
		ok(el.params.type:sub(1, 3) == "::/", el.params.type)
	end
	r = script.updateFn({}, params({ island = 2, splitter = 2, layout = 2 }))
	eq(#r.subconstructions, 1)
	eq(#r.subconstructions[1].groundFaces, 6, "4 corner islands + 2 splitter triangles")
	for _, c in ipairs(r.subconstructions[1].colliders) do eq(c.type, "BOX"); eq(#c.transf, 16) end
end)

test("roads: templates, arms, slip lanes and legs per layout", function()
	local b = build()
	eq(b.lists[1].role, "main"); eq(b.lists[1].template, geom.ARM_TEMPLATES[ch.DEFAULT_MAIN])
	eq(b.lists[2].role, "side"); eq(b.lists[2].template, geom.ARM_TEMPLATES[ch.DEFAULT_SIDE])
	eq(b.lists[3].role, "slips"); eq(b.lists[3].template, ch.SLIP.template)
	eq(#b.slips, 2); eq(#b.legs, 0)
	eq(#build({ layout = 2 }).slips, 4)
	eq(#build({ slips = 3 }).slips, 0); eq(#build({ slips = 3 }).lists, 2)
	local x = build({ layout = 2, splitter = 2, slips = 2 })
	eq(#x.legs, 2); eq(#x.slips, 4)
	eq(x.lists[3].role, "legs")
	eq(x.lists[3].template, ch.splitParams(x.spec).leg.template)
	-- plain T: 3 arms from the centre node
	local plain = build({ slips = 3 })
	eq(#plain.lists[1].edges, 2); eq(#plain.lists[2].edges, 1)
	for _, l in ipairs(plain.lists) do
		for _, e in ipairs(l.edges) do eq(e.tag0, "sqrb_ch_centre"); eq(e.tag1, nil) end
	end
	-- the side road leaves north (both traffic sides)
	for direction = 1, 2 do
		for _, e in ipairs(build({ direction = direction }).lists[2].edges) do ok(e.p1[2] > e.p0[2] - 1e-9, "north") end
	end
end)

test("every combination: tags, edges >= 10 m, engine-fitted junction model, no overlaps, islands clear", function()
	local count, worstFree = 0, math.huge
	each({ island = 2 }, function(o)
		local b = build(o)
		local n = name(o)
		count = count + 1
		checks.report(checks.tags(b.lists), n)
		checks.report(checks.lengths(b.lists, geom.MIN_EDGE), n)
		checks.report(checks.engineModel(b.lists), n)
		checks.report(checks.overlaps(b.lists, 0.5, nil, goreLimit), n)
		checks.report(checks.islandClear(b.lists, b.island, geom.ISLAND_MARGIN - 0.25), n)
		for _, xe in ipairs(checks.junctions(b.lists)) do worstFree = math.min(worstFree, xe.free) end
	end)
	print(string.format("    %d builds, smallest free length %.1f m", count, worstFree))
end)

test("arm length: every arm runs that far beyond its outermost node; engine model holds", function()
	for len = 1, #ch.ARM_LENGTHS do
		for _, o in ipairs({ { main = 3, side = 6 }, { main = 4, side = 1, splitter = 2 }, { layout = 2, slips = 3 }, { layout = 2, slips = 3, splitter = 2, side = 3 } }) do
			o.armLength = len
			local b = build(o)
			checks.report(checks.engineModel(b.lists), name(o))
			for _, l in ipairs(b.lists) do
				if l.role == "main" or l.role == "side" then
					for _, e in ipairs(l.edges) do
						-- from a slip or split node exactly the arm length; from the centre or a leg node
						-- the crossing road's (or leg's) far kerb is added (checked below)
						local fromOuter = e.tag0 and (e.tag0:find("slip", 1, true) or e.tag0:find("split", 1, true))
						if e.tag1 == nil and fromOuter then near(S.dist(e.p0, e.p1), ch.ARM_LENGTHS[len], 1e-6, name(o)) end
					end
				end
			end
		end
	end
	-- no slip lanes, no splitter: beyond the crossing road's kerb
	local b = build({ slips = 3, main = 3, side = 1 })
	near(S.len(b.lists[1].edges[1].p1), geom.ARM_HALF_WIDTH[1] + ch.ARM_LENGTHS[1], 1e-9)
	near(S.len(b.lists[2].edges[1].p1), geom.ARM_HALF_WIDTH[3] + ch.ARM_LENGTHS[1], 1e-9)
	-- splitter, no slip lanes: main arms beyond the leg's far kerb
	b = build({ slips = 3, splitter = 2, side = 2 })
	local sp = ch.splitParams(b.spec)
	near(S.len(b.lists[1].edges[2].p1), 2 * sp.leg.halfWidth + sp.spread + ch.ARM_LENGTHS[1], 1e-9)
end)

test("traffic side: left-hand traffic is the right-hand layout mirrored in x, edges keep their direction", function()
	each({ island = 3 }, function(o)
		local r = build(o)
		o.direction = 2
		local l = build(o)
		eq(l.mirrored, true)
		eq(#l.lists, #r.lists, name(o))
		for i, list in ipairs(r.lists) do
			eq(l.lists[i].template, list.template)
			for j, e in ipairs(list.edges) do
				local m = l.lists[i].edges[j]
				near3(m.p0, mirrorOf(e.p0), name(o)); near3(m.p1, mirrorOf(e.p1))
				near3(m.t0, mirrorOf(e.t0)); near3(m.t1, mirrorOf(e.t1))
				eq(m.tag0, e.tag0); eq(m.tag1, e.tag1)
			end
		end
		if r.island then
			eq(#l.island.faces, #r.island.faces)
			for i, f in ipairs(r.island.faces) do
				near(S.area(l.island.faces[i].outline), S.area(f.outline), 1e-6, "same area, CCW")
			end
			for i, c in ipairs(r.island.colliders) do
				local lc = l.island.colliders[i]
				near(lc.x, -c.x, 1e-9); near(lc.y, c.y, 1e-9)
				near(math.cos(lc.rot), -math.cos(c.rot), 1e-9); near(math.sin(lc.rot), math.sin(c.rot), 1e-9)
			end
		end
	end)
end)

test("traffic side: near-side slip lanes turn the short way and use the near lanes; legs keep to the traffic side", function()
	for direction = 1, 2 do
		local sign = direction == geom.DIRECTION_CW and -1 or 1 -- 1: right-hand traffic
		for layout = 1, 2 do
			for splitter = 1, 2 do
				local b = build({ layout = layout, direction = direction, splitter = splitter })
				for _, e in ipairs(b.slips) do
					-- from the inbound arm (-u0) to the outbound arm (u1): a right turn (right-hand
					-- traffic), taken at both ends; past 45 deg (engine data, Phase 5f) the slip lane
					-- itself bends the other way between them
					local u0, u1 = S.norm(e.p0), S.norm(e.p1)
					ok(sign * S.cross(S.scale(u0, -1), u1) < 0, "near-side slip lane turns right (right-hand) / left (left-hand)")
					ok(sign * S.cross(S.scale(u0, -1), e.t0) < 0 and sign * S.cross(e.t1, u1) < 0, "turns at both ends")
					-- leaves the inbound lanes: on the traffic side of a driver heading in (-u)
					ok(sign * S.dot(e.t0, right(S.scale(u0, -1))) > 0, "leaves from the near (inbound) lanes")
					-- joins the outbound lanes: arrives from the traffic side of a driver heading out (u)
					ok(sign * S.dot(S.sub(checks.hermite(e, 0.9), e.p1), right(u1)) > 0, "joins the near (outbound) lanes")
				end
				for _, leg in ipairs(b.legs) do
					local u = S.norm(leg.split)
					local mid = checks.hermite(leg.entry, 0.5)
					ok(sign * S.dot(mid, right(S.scale(u, -1))) > 0, "entry leg on the inbound driver's traffic side")
					ok(S.dot(leg.entry.p0, u) > S.dot(leg.entry.p1, u), "entry leg runs towards the main road")
				end
			end
		end
	end
	-- "All turns off the main road": every slip lane starts on the main road and ends on a side road
	for _, b in ipairs({ build({ slips = 2 }), build({ slips = 2, layout = 2, direction = 2 }) }) do
		for _, e in ipairs(b.slips) do
			ok(math.abs(e.p0[2]) < 1e-9 and math.abs(e.p1[1]) < 1e-9, "main road -> side road")
		end
	end
end)

test("islands: one per slip lane and per splitter, base textures, colliders inside; the roads do not depend on Islands", function()
	each({}, function(o)
		local none = build(o)
		eq(none.island, nil)
		for island = 2, 3 do
			o.island = island
			local b = build(o)
			local n = name(o)
			-- the Islands param adds surfaces only: the same roads
			for i, l in ipairs(b.lists) do
				for j, e in ipairs(l.edges) do near3(e.p0, none.lists[i].edges[j].p0, n); near3(e.t0, none.lists[i].edges[j].t0, n) end
			end
			local want = #b.slips + #b.legs
			if want == 0 then
				eq(b.island, nil, n)
			else
				eq(#b.island.faces, want, n)
				eq(#b.island.colliders, #b.slips, n .. ": a box collider per corner island")
				for _, f in ipairs(b.island.faces) do
					ok(S.area(f.outline) >= ch.SPLIT_TRIANGLE_MIN - 1e-6, n .. string.format(": island %.1f m^2", S.area(f.outline)))
					eq(f.fill, island == 2 and geom.GTEX_GRASS or geom.GTEX_PAVING_FILL)
				end
				for _, c in ipairs(b.island.colliders) do
					local inside = false
					for _, f in ipairs(b.island.faces) do inside = inside or S.fits(c.x, c.y, math.min(c.hx, c.hy) - 1e-6, f.outline) end
					ok(inside, n .. ": collider centre inside its island")
				end
				eq(b.island.models, {})
			end
			o.island = nil
		end
	end)
end)

test("set-backs: the slip nodes do not depend on slip lanes, arm length or traffic side; layout only through the engine data", function()
	for main = 1, #geom.ARM_TEMPLATES do
		for side = 1, #geom.ARM_TEMPLATES do
			for splitter = 1, 2 do
				local ref = build({ main = main, side = side, splitter = splitter }).setback
				for _, o in ipairs({ { layout = 2 }, { slips = 2 }, { armLength = 4 }, { direction = 2 } }) do
					o.main, o.side, o.splitter = main, side, splitter
					local b = build(o)
					local tRule = { ch.slipRule(ch.readParams(params({ main = main, side = side, splitter = splitter }))) }
					local rule = { ch.slipRule(b.spec) }
					-- X and T share the set-backs when the engine data gives them the same slip lanes
					if rule[1] == tRule[1] and rule[2] == tRule[2] then eq(b.setback, ref, name(o)) end
					local same = build({ layout = o.layout, main = main, side = side, splitter = splitter }).setback
					eq(b.setback, same, name(o) .. ": as the same layout with the first slip lanes, arm length, traffic side")
				end
				-- splitter islands push the side slip node beyond the split node
				if splitter == 2 then
					local sp = ch.splitParams({ main = main, side = side })
					ok(ref.side > geom.ARM_HALF_WIDTH[main] + sp.split, "side slip node beyond the split node")
				end
			end
		end
	end
	-- wider roads, larger set-backs (at the same slip lanes: the engine data gives wide roads
	-- steeper ones, Phase 5g: e.g. 65 deg on a town large side road, which set back less than 40 deg)
	local function same(over)
		local p = params(over)
		p[geom.DEV_KEYS.chSlipAngle], p[geom.DEV_KEYS.chSlip] = 40, 1
		return ch.build(ch.readParams(p))
	end
	ok(same({ main = 3 }).setback.main > same({ main = 1 }).setback.main)
	ok(same({ side = 3 }).setback.side > same({ side = 1 }).setback.side)
end)

-- Scale (revision 6): XS is the computed minimum (the only layout before, golden-tested in
-- test_entries_unchanged_channel.lua); S-XL multiply both set-backs by ch.SCALES, rounded up.
local function copy(o, over)
	local c = {}
	for k, v in pairs(o) do c[k] = v end
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end

-- one test per scale, so the runner can shard them
for scale = 2, #ch.SCALES do
	test("Scale " .. ch.SCALE_NAMES[scale] .. ": every combination: set-backs = XS x factor rounded up, the same checks, islands, bend, arm length", function()
		local count, worstFree = 0, math.huge
		local step = ch.SETBACK_STEP
		local f = ch.SCALES[scale]
		each({ island = 2, scale = scale }, function(o)
			local b = build(o)
			local xs = build(copy(o, { scale = 1 }))
			local n = name(o)
			count = count + 1
			-- set-backs: XS x factor, rounded up to the step, always beyond XS
			for _, r in ipairs({ "main", "side" }) do
				local want = xs.setback[r] * f
				ok(b.setback[r] >= want - 1e-9 and b.setback[r] < want + step, n .. ": " .. r .. " set-back")
				ok(b.setback[r] > xs.setback[r], n .. ": " .. r .. " beyond XS")
			end
			-- same slip lane angle and template, same roads, slip lanes and legs
			eq(b.slipAngle, xs.slipAngle, n); eq(b.slipRoad, xs.slipRoad, n)
			eq(#b.lists, #xs.lists, n); eq(#b.slips, #xs.slips, n); eq(#b.legs, #xs.legs, n)
			-- one-way bend: the chord direction moves by the rounding only (CHORD_MARGIN is 2 deg)
			local chord = math.deg(math.atan(b.setback.side, b.setback.main))
			local chordXs = math.deg(math.atan(xs.setback.side, xs.setback.main))
			ok(math.abs(chord - chordXs) < 0.5, n .. string.format(": chord %.2f vs XS %.2f deg", chord, chordXs))
			local a = b.slipAngle
			local lo, hi = math.min(a, 90 - a), math.max(a, 90 - a)
			if chordXs >= lo + 2 - 1e-6 and chordXs <= hi - 2 + 1e-6 then
				ok(chord > lo + 1.5 and chord < hi - 1.5, n .. ": chord between the end headings")
			end
			-- splitter islands: the side slip node stays beyond the split node
			if o.splitter == 2 and o.slips ~= 3 then
				local sp = ch.splitParams(b.spec)
				ok(b.setback.side > geom.ARM_HALF_WIDTH[o.main] + sp.split + sp.leg.halfWidth, n .. ": beyond the split node")
			end
			checks.report(checks.tags(b.lists), n)
			checks.report(checks.lengths(b.lists, geom.MIN_EDGE), n)
			checks.report(checks.engineModel(b.lists), n)
			checks.report(checks.overlaps(b.lists, 0.5, nil, goreLimit), n)
			checks.report(checks.islandClear(b.lists, b.island, geom.ISLAND_MARGIN - 0.25), n)
			for _, xe in ipairs(checks.junctions(b.lists)) do worstFree = math.min(worstFree, xe.free) end
			-- islands: one per slip lane and per splitter, as at XS, none smaller than XS's smallest rule
			local want = #b.slips + #b.legs
			if want == 0 then eq(b.island, nil, n) else
				eq(#b.island.faces, want, n)
				eq(#b.island.colliders, #b.slips, n .. ": a box collider per corner island")
				for i, fc in ipairs(b.island.faces) do
					ok(S.area(fc.outline) >= ch.SPLIT_TRIANGLE_MIN - 1e-6, n .. string.format(": island %.1f m^2", S.area(fc.outline)))
					ok(S.area(fc.outline) >= S.area(xs.island.faces[i].outline) - 1e-6, n .. ": island not smaller than at XS")
				end
			end
			-- arm length: every arm still runs ARM_LENGTHS beyond its slip node
			for _, l in ipairs(b.lists) do
				if l.role == "main" or l.role == "side" then
					for _, e in ipairs(l.edges) do
						if e.tag1 == nil and e.tag0 and e.tag0:find("slip", 1, true) then
							near(S.dist(e.p0, e.p1), ch.ARM_LENGTHS[o.armLength or 1], 1e-6, n)
						end
					end
				end
			end
		end)
		print(string.format("    %d builds, smallest free length %.1f m", count, worstFree))
	end)
end

test("Scale: set-backs of the default junction at every scale", function()
	-- the set-backs of the default (town medium main, town small side) at each scale
	local row, prev = {}, { main = 0, side = 0 }
	for scale = 1, #ch.SCALES do
		local sb = build({ scale = scale }).setback
		ok(sb.main > prev.main and sb.side > prev.side, "larger at each scale"); prev = sb
		row[#row + 1] = string.format("%s %.1f / %.1f", ch.SCALE_NAMES[scale], sb.main, sb.side)
	end
	print("    default set-backs (main / side, m): " .. table.concat(row, ", "))
end)

for scale = 2, #ch.SCALES do
	test("Scale " .. ch.SCALE_NAMES[scale] .. ": left-hand traffic mirrors it; no new -0 in the result; the Islands param moves no road", function()
		local updateFn = loadData("square_roundabouts_channel.script.lua").updateFn
		each({ scale = scale }, function(o)
			for direction = 1, 2 do
				local p = params(copy(o, { direction = direction, island = 3 }))
				local _, n = checks.negativeZeros(updateFn({}, p))
				p[K.scale] = 1
				local _, nXs = checks.negativeZeros(updateFn({}, p))
				eq(n, nXs, name(copy(o, { direction = direction })) .. ": world -0 tangents as at XS")
			end
			local r, l = build(o), build(copy(o, { direction = 2 }))
			for i, list in ipairs(r.lists) do
				for j, e in ipairs(list.edges) do
					local m = l.lists[i].edges[j]
					near3(m.p0, mirrorOf(e.p0), name(o)); near3(m.t1, mirrorOf(e.t1), name(o))
				end
			end
			local g = build(copy(o, { island = 2 }))
			for i, list in ipairs(r.lists) do
				for j, e in ipairs(list.edges) do near3(e.p1, g.lists[i].edges[j].p1, name(o)) end
			end
		end)
	end)
end
