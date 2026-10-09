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

function result.build(built)
	local edgeLists = {}
	for _, l in ipairs(built.lists) do
		if #l.edges > 0 then edgeLists[#edgeLists + 1] = result.edgeList(l) end
	end
	local res = {
		edgeLists = edgeLists,
		cost = 0,
	}
	if built.island then
		res.subconstructions = { result.islandSubconstruction(built.island) }
	else
		-- exactly the base roundabout's result shape
		res.models = {}
		res.groundFaces = {}
	end
	return res
end

return result
