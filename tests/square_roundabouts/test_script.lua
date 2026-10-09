-- square_roundabouts.script.lua (updateFn) and the .con.lua definition.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local K = geom.PARAM_KEYS

local function loadData(file)
	-- the file defines a global data(); each load replaces it
	ug_require(DIR .. file)
	return data()
end

local script = loadData("square_roundabouts.script.lua")

local function params(over)
	local p = {}
	for k, v in pairs(over or {}) do p[K[k]] = v end
	return p
end

local function update(over) return script.updateFn({}, params(over)) end

test("updateFn: ring + arm edgeLists, every node free, no snap nodes", function()
	for arms = 1, #geom.ARM_LAYOUTS do
		local r = update({ arms = arms })
		eq(#r.edgeLists, arms == #geom.ARM_LAYOUTS and 1 or 2, "layout " .. arms)
		for _, el in ipairs(r.edgeLists) do
			eq(el.type, "STREET")
			eq(el.snapNodes, {})
			eq(#el.edges % 2, 0, "two entries per edge")
			eq(#el.freeNodes, #el.edges, "every node free")
			for i, n in ipairs(el.freeNodes) do eq(n, i - 1) end
			eq(el.postConstructionModifiable, nil)
		end
		eq(r.cost, 0)
	end
end)

test("updateFn: ring uses the vanilla one-way set, arms the chosen template", function()
	for lanes = 1, 3 do
		eq(update({ lanes = lanes }).edgeLists[1].params.type, geom.RING_TEMPLATES[lanes])
	end
	for armType = 1, #geom.ARM_TEMPLATES do
		eq(update({ armType = armType }).edgeLists[2].params.type, geom.ARM_TEMPLATES[armType])
	end
end)

test("updateFn: arm start entries carry ring node tags", function()
	local r = update({ arms = 4 }) -- 5 arms
	local ringTags = {}
	for _, n in ipairs(r.edgeLists[1].edges) do
		ok(type(n[3]) == "string", "ring entry tagged")
		ringTags[n[3]] = (ringTags[n[3]] or 0) + 1
	end
	for _, c in pairs(ringTags) do eq(c, 2, "each ring node appears as one edge end and one edge start") end
	local armEdges = r.edgeLists[2].edges
	eq(#armEdges, 10)
	for i = 1, #armEdges, 2 do
		ok(ringTags[armEdges[i][3]] ~= nil, "arm start tag " .. tostring(armEdges[i][3]))
		eq(armEdges[i + 1][3], nil)
	end
end)

test("updateFn: island subconstruction only when chosen", function()
	local none = update({ island = geom.ISLAND_NONE })
	eq(none.subconstructions, nil)
	eq(none.models, {}); eq(none.groundFaces, {})

	local r = update({ island = geom.ISLAND_PAVED })
	eq(#r.subconstructions, 1)
	local sc = r.subconstructions[1]
	eq(r.models, nil)
	eq(sc.tag, 1)
	eq(#sc.groundFaces, 1)
	eq(sc.groundFaces[1].modes[1], { type = "FILL", key = geom.GTEX_PAVING_FILL })
	eq(sc.groundFaces[1].modes[2], { type = "STROKE_OUTER", key = geom.GTEX_PAVING_STROKE })
	ok(#sc.groundFaces[1].face >= 3)
	eq(sc.colliders[1].type, "CYLINDER")
	eq(#sc.colliders[1].transf, 16)
	eq(#sc.colliders[1].params.halfExtents, 3)
	eq(sc.terrainAlignmentLists, { { type = "EQUAL", faces = {} } })

	local t = update({ island = geom.ISLAND_TREES, radius = #geom.RADII })
	local models = t.subconstructions[1].models
	ok(#models > 0)
	for _, m in ipairs(models) do
		ok(type(m.id) == "string" and m.id:sub(1, 3) == "::/", m.id)
		eq(#m.transf, 16)
	end
end)

test("updateFn: tolerates empty params (defaults)", function()
	local r = script.updateFn({}, {})
	eq(#r.edgeLists, 2)
	eq(#r.edgeLists[2].edges, 8, "4 arms by default")
end)

test("updateFn: default result has no centre island", function()
	local r = script.updateFn({}, {})
	eq(r.subconstructions, nil)
	eq(r.models, {}); eq(r.groundFaces, {})
end)

test("script exports only updateFn (no checkEnabled functions)", function()
	local keys = {}
	for k in pairs(script) do keys[#keys + 1] = k end
	eq(keys, { "updateFn" })
end)

test(".con.lua: params, script references and availability", function()
	local con = loadData("square_roundabouts.con.lua")
	eq(con.description.name, "Better Roundabouts")
	eq(con.description.icon, "square_roundabouts.tga", "own icon (the game loads square_roundabouts@2x.tga)")
	eq(con.updateScript.fileName, "square_roundabouts.script@updateFn")
	eq(con.availability.yearFrom, 1940)
	eq(con.menuCategory.categories[1].category, "street_constructions")
	local byKey = {}
	for _, p in ipairs(con.params) do
		ok(byKey[p.key] == nil, "duplicate key " .. p.key)
		byKey[p.key] = p
		ok(p.key:sub(1, 5) == "sqrb_", "prefixed key " .. p.key)
		ok(#p.values >= 2, p.key)
		ok((p.defaultIndex or 1) >= 1 and (p.defaultIndex or 1) <= #p.values, p.key .. " default in range")
		-- the base params panel does not refresh "Disabled" live, and "Hidden" breaks it
		eq(p.checkEnabledScript, nil, p.key .. " has no checkEnabledScript")
	end
	for _, key in pairs(K) do ok(byKey[key] ~= nil, "param " .. key) end
	eq(#byKey[K.shape].values, #geom.SHAPE_RATIOS)
	eq(#byKey[K.radius].values, #geom.RADII)
	eq(#byKey[K.arms].values, #geom.ARM_LAYOUTS)
	eq(#byKey[K.armType].values, #geom.ARM_TEMPLATES)
	eq(byKey.sqrb_arm_length, nil, "no arm length param (fixed length)")
	eq(byKey[K.radius].name, "Radius")
	-- the defaults match readParams' fallbacks
	local d = {}
	for _, p in ipairs(con.params) do d[p.key] = p.defaultIndex or 1 end
	eq(geom.readParams(d), geom.readParams({}))
	eq(byKey[K.island].values[byKey[K.island].defaultIndex], "None", "centre island defaults to None")
end)

-- Phase 3

test("updateFn: every feature combination keeps every node free and no snap nodes", function()
	for arms = 1, #geom.ARM_LAYOUTS do
		for _, f in ipairs({ { splitter = 2 }, { centre = 2 }, { centre = 3 }, { tram = 2, splitter = 2, centre = 2, signals = 2, island = 3 } }) do
			f.arms = arms
			local r = update(f)
			for _, el in ipairs(r.edgeLists) do
				eq(el.snapNodes, {})
				eq(#el.freeNodes, #el.edges)
				ok(type(el.params.type) == "string" and el.params.type:sub(1, 3) == "::/", el.params.type)
			end
		end
	end
end)

test("updateFn: tramTrackType only where no tram template exists", function()
	local r = update({ tram = 2, lanes = 1, armType = 4 })
	eq(r.edgeLists[1].params.tramTrackType, "ELECTRIC", "1-lane ring")
	eq(r.edgeLists[2].params.tramTrackType, "ELECTRIC", "country arms")
	r = update({ tram = 2, lanes = 2, armType = 1 })
	eq(r.edgeLists[1].params.tramTrackType, nil)
	eq(r.edgeLists[1].params.type, geom.RING_TRAM[2].template)
	for _, el in ipairs(update({}).edgeLists) do eq(el.params.tramTrackType, nil) end
end)

test("updateFn: signals set both candidate fields on the ring edgeList, at entries with those tags", function()
	local off = update({})
	for _, el in ipairs(off.edgeLists) do
		eq(el.trafficLightYes, nil); eq(el.trafficLightNodePreference, nil)
	end
	local s = geom.readParams(params({ signals = 2, splitter = 2 }))
	local built = geom.build(s)
	local r = update({ signals = 2, splitter = 2 })
	local ring = r.edgeLists[1]
	local yesTags, prefTags = {}, {}
	for _, t in ipairs(built.ring.signalYes) do yesTags[t] = true end
	for _, t in ipairs(built.ring.signalPref) do prefTags[t] = true end
	ok(#ring.trafficLightYes > 0 and #ring.trafficLightNodePreference > 0)
	for _, i in ipairs(ring.trafficLightYes) do ok(yesTags[ring.edges[i + 1][3]], "yes index → entry tag") end
	for _, p in ipairs(ring.trafficLightNodePreference) do
		eq(#p, 2); eq(p[2], "YES")
		ok(prefTags[ring.edges[p[1] + 1][3]], "preference index → entry tag")
	end
	for i = 2, #r.edgeLists do
		eq(r.edgeLists[i].trafficLightYes, nil); eq(r.edgeLists[i].trafficLightNodePreference, nil)
	end
end)

test("updateFn: splitter triangles and island halves share one island subconstruction", function()
	local r = update({ splitter = 2, island = geom.ISLAND_GRASS })
	eq(#r.subconstructions, 1)
	eq(#r.subconstructions[1].groundFaces, 5, "centre + 4 triangles")
	r = update({ centre = 2, island = geom.ISLAND_PAVED, radius = #geom.RADII })
	local sc = r.subconstructions[1]
	eq(#sc.groundFaces, 2); eq(#sc.colliders, 2)
	for _, c in ipairs(sc.colliders) do eq(c.type, "BOX"); eq(#c.transf, 16) end
end)

test(".con.lua: Phase 3 params", function()
	local con = loadData("square_roundabouts.con.lua")
	local byKey = {}
	for _, p in ipairs(con.params) do byKey[p.key] = p end
	eq(#byKey[K.splitter].values, 2); eq(#byKey[K.centre].values, 4); eq(#byKey[K.tram].values, 2); eq(#byKey[K.signals].values, 2)
	ok(byKey[K.signals].tooltip:find("Experimental", 1, true) ~= nil, "signals marked experimental")
	ok(byKey[K.signals].values[2]:find("experimental", 1, true) ~= nil)
	-- Tram tracks lost the "experimental" label in Phase 4 (the engine probe: On is no worse than Off)
	ok(byKey[K.tram].tooltip:lower():find("experimental", 1, true) == nil, "tram tracks not experimental")
	eq(byKey[K.tram].values, { "Off", "On" })
end)

test("magic: con.lua, script and params", function()
	local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
	local con = loadData("square_roundabouts_magic.con.lua")
	eq(con.description.name, "Magic Roundabout")
	eq(con.description.icon, "square_roundabouts_magic.tga")
	eq(con.updateScript.fileName, "square_roundabouts_magic.script@updateFn")
	eq(con.menuCategory.categories[1].category, "street_constructions")
	local keys = {}
	for _, p in ipairs(con.params) do
		keys[p.key] = true
		eq(p.checkEnabledScript, nil)
		ok((p.defaultIndex or 1) >= 1 and (p.defaultIndex or 1) <= #p.values)
	end
	for _, key in pairs(magic.PARAM_KEYS) do ok(keys[key], key) end
	local n = 0
	for _ in pairs(keys) do n = n + 1 end
	eq(n, 5, "only size, arm road, mini roundabout lanes, direction, island")
	local size
	for _, p in ipairs(con.params) do if p.key == magic.PARAM_KEYS.size then size = p end end
	eq(size.uiType, "Slider"); eq(#size.values, #magic.SIZES); eq(size.defaultIndex, magic.DEFAULT_SIZE)
	eq(con.params[1].key, magic.PARAM_KEYS.size, "size first")
	local d = {}
	for _, p in ipairs(con.params) do d[p.key] = p.defaultIndex or 1 end
	eq(magic.readParams(d), magic.readParams({}))

	local ms = loadData("square_roundabouts_magic.script.lua")
	local r = ms.updateFn({}, {})
	eq(#r.edgeLists, 3)
	for _, el in ipairs(r.edgeLists) do
		eq(el.snapNodes, {}); eq(#el.freeNodes, #el.edges)
	end
	eq(r.subconstructions, nil, "island None by default")
	r = ms.updateFn({}, { sqrb_island = geom.ISLAND_TREES })
	eq(#r.subconstructions[1].groundFaces, 6, "centre + 5 satellites")
	eq(#r.subconstructions[1].colliders, 6)
end)
