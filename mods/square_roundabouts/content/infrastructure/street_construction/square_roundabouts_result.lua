-- Better Roundabouts: maps a pure geometry result (square_roundabouts_geometry.build,
-- square_roundabouts_magic.build, _channel.build, _interchange.build) to the construction result
-- table of an updateFn (docs/wiki/modding/constructions/basics.md "Update Script", "Edge Lists", "Subconstructions").
-- Pure: no api.*.
--
-- Every node of every edgeList is in freeNodes and snapNodes is empty, as in the base
-- updateFnRoundabout (base street_constructions.script.lua:632): once built, the edges become
-- ordinary streets that the player can edit, connect or bulldoze one by one.

local geom = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"

local result = {}

--- One STREET edgeList. Experimental signals (Phase 3, TESTING.md "Signals"): the same kind of
-- node gets lights through two candidate fields, so the in-game test shows which one the engine
-- reads: `trafficLightYes` (node indices, base tealdef construction_util_serialized.d.tl:150) and
-- `trafficLightNodePreference` ({{index, "YES"}}, docs/wiki/modding/constructions/basics.md:690).
function result.edgeList(l)
	local entries = geom.toEdgeEntries(l.edges)
	local params = { type = l.template }
	if l.tramTrackType then params.tramTrackType = l.tramTrackType end
	local el = {
		type = "STREET",
		params = params,
		edges = entries,
		snapNodes = {},
		freeNodes = geom.allNodes(entries),
	}
	-- bridges (Roundabout Interchange): a separate list per template, as base
	-- street_constructions.script.lua diamond_interchange (edgeType "BRIDGE" + edgeTypeName)
	if l.edgeType then el.edgeType = l.edgeType end
	if l.edgeTypeName then el.edgeTypeName = l.edgeTypeName end
	if l.signalYes then
		el.trafficLightYes = geom.nodesWithTags(entries, l.signalYes)
	end
	if l.signalPref then
		local pref = {}
		for _, i in ipairs(geom.nodesWithTags(entries, l.signalPref)) do pref[#pref + 1] = { i, "YES" } end
		el.trafficLightNodePreference = pref
	end
	return el
end

--- The island subconstruction: ground faces, colliders and models of all island pieces.
function result.islandSubconstruction(island)
	local groundFaces = {}
	for i, f in ipairs(island.faces) do
		local modes = { { type = "FILL", key = f.fill } }
		if f.stroke then
			modes[#modes + 1] = { type = "STROKE_OUTER", key = f.stroke }
		end
		groundFaces[i] = { face = f.outline, modes = modes, loop = true }
	end

	local models = {}
	for i, m in ipairs(island.models) do
		models[i] = { id = m.id, transf = geom.transf(m.x, m.y, 0, m.rot) }
	end

	-- keeps town buildings and other objects off the islands (basics.md "Collider")
	local colliders = {}
	for i, c in ipairs(island.colliders) do
		colliders[i] = {
			type = c.type,
			transf = geom.transf(c.x, c.y, c.hz, c.rot),
			params = { halfExtents = { c.hx, c.hy, c.hz } },
		}
	end

	return {
		tag = 1,
		models = models,
		groundFaces = groundFaces,
		colliders = colliders,
		-- no terrain change: the island follows the ground the ring is built on
		-- (same as base assetbuilderutil.script.lua with "Align Terrain" off)
		terrainAlignmentLists = { { type = "EQUAL", faces = {} } },
	}
end

-- Structure (every entry's last param, PLAN.md "Structure: Embankment / Bridge"). Raised with the
-- builder's Height (it reaches the construction only as the transf's z, never as a param), plain edges
-- stand on an embankment (Roundabout XS at +8 m: ~78,500 m3 of terrain); every edge list as a bridge
-- changes no terrain, also at grade (docs/findings/roads.md "A construction's edges as bridges").
-- Embankment (the default) is the result as before, byte for byte (test_structure_embankment.lua).
-- Bridge: every edge list without an edgeType becomes edgeType "BRIDGE" with result.structureBridgeType;
-- the interchanges' own bridges keep their type; no islands (their ground faces lie on the ground,
-- below the deck). Geometry is untouched, so the -0 normalization (hx.positiveZeros) still holds.
-- Appended values only: a saved index keeps its meaning.
result.STRUCTURE_KEY = "sqrb_structure"
result.STRUCTURE_EMBANKMENT = 1
result.STRUCTURE_BRIDGE = 2
-- Bridge type by year: base stone before 1970 (arches every 12 m; base concrete / steel put a pillar
-- only every 60-90 m, so a roundabout's 15-30 m pieces got none, in game 2026-10-22), the mod's own
-- short-span copy of base concrete (pillars every 12-24 m, hidden from the bridge menu) from 1970 and
-- when the year is missing.
result.BRIDGE_STONE = "::/infrastructure/bridge/stone.bridge"
result.BRIDGE_SHORT_CONCRETE = "square_roundabouts::/infrastructure/bridge/square_roundabouts_concrete_short.bridge"
result.SHORT_CONCRETE_FROM = 1970

--- The Structure bridge type for the year (params.year; nil: the short-span concrete).
function result.structureBridgeType(year)
	year = tonumber(year)
	if year and year < result.SHORT_CONCRETE_FROM then return result.BRIDGE_STONE end
	return result.BRIDGE_SHORT_CONCRETE
end

--- The Structure from the construction params: nil for Embankment (and any unknown value), else
-- { bridge = edgeTypeName }.
function result.readStructure(params)
	local v = tonumber(params and params[result.STRUCTURE_KEY])
	if v ~= result.STRUCTURE_BRIDGE then return nil end
	return { bridge = result.structureBridgeType(params.year) }
end

--- The Structure param of every menu entry (tr: the .con.lua's `_`; in a .con.lua it returns the key
-- and the game translates on display). default: result.STRUCTURE_EMBANKMENT (nil) or _BRIDGE (the
-- interchanges: their ramps climb to the upper level anyway, PLAN.md "Structure: Embankment / Bridge").
-- Only the menu default: a saved build without the key reads as Embankment (result.readStructure).
function result.structureParam(tr, default)
	local _ = tr or function(s) return s end
	return {
		key = result.STRUCTURE_KEY,
		name = _("Structure"),
		tooltip = _("Embankment: roads on the ground. Raised with the\nHeight control, they stand on earth fill.\nBridge: every road on a bridge, for a build raised\nwith the Height control: the ground stays as it is.\nNo islands on bridges."),
		uiType = "ComboBox",
		values = { _("Embankment"), _("Bridge") },
		defaultIndex = default or result.STRUCTURE_EMBANKMENT,
		location = "Toolbar",
	}
end

--- The construction result of a geometry; structure = result.readStructure(params) (nil: Embankment).
function result.build(built, structure)
	local edgeLists = {}
	for _, l in ipairs(built.lists) do
		if #l.edges > 0 then
			local el = result.edgeList(l)
			if structure and el.edgeType == nil then
				el.edgeType = "BRIDGE"
				el.edgeTypeName = structure.bridge
			end
			edgeLists[#edgeLists + 1] = el
		end
	end
	local res = {
		edgeLists = edgeLists,
		cost = 0,
	}
	if built.island and not structure then
		res.subconstructions = { result.islandSubconstruction(built.island) }
	else
		-- exactly the base roundabout's result shape
		res.models = {}
		res.groundFaces = {}
	end
	return res
end

return result
