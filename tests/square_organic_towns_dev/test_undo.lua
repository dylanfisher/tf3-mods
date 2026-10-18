-- otd_undo: which entities "Undo last increment" removes, config pruning, refusals.

local UN = ug_require "/organic_towns_dev/otd_undo.lua"

-- A record of 3 edges: 501 (joint 10 -> new 20), 502 (20 -> 21), 503 (21 -> 22). The town later attached its own
-- edge 600 to node 21.
local function reads(over)
	over = over or {}
	local edges = {
		[501] = { n0 = 10, n1 = 20, owned = false, objects = 0 },
		[502] = { n0 = 20, n1 = 21, owned = false, objects = 0 },
		[503] = { n0 = 21, n1 = 22, owned = false, objects = 0 },
	}
	for k, v in pairs(over.edges or {}) do edges[k] = v end
	local nodeEdges = { [10] = { 400, 501 }, [20] = { 501, 502 }, [21] = { 502, 503, 600 }, [22] = { 503 } }
	local cfg = over.cfg or { [10] = true, [21] = true }
	return {
		edge = function(id) if edges[id] == false then return nil end return edges[id] end,
		nodeEdges = function(n) return nodeEdges[n] end,
		hasConfig = function(n) return cfg[n] == true end,
		hasLights = function(n) return (over.lights or {})[n] == true end,
		inConstruction = function(n) return (over.construction or {})[n] == true end,
	}
end

test("plan: live edges, orphan nodes removed, configs pruned only where they exist", function()
	local p = UN.plan({ edges = { 501, 502, 503 } }, reads())
	eq(p.edges, { 501, 502, 503 })
	eq(p.nodesRemove, { 20, 22 })
	eq(p.cfgPrune, { 10, 21 }, "the joint and the node the town attached to; never a node without a config")
	eq(p.missing, 0)
	ok(p.gone[502])
	local p2 = UN.plan({ edges = { 501, 502, 503 } }, reads({ cfg = { [10] = true } }))
	eq(p2.cfgPrune, { 10 }, "node 21 has no config: left alone")
end)

test("plan: edges already gone are counted; nothing left -> refused", function()
	local p = UN.plan({ edges = { 501, 502, 503 } }, reads({ edges = { [503] = false } }))
	eq(p.missing, 1)
	eq(p.edges, { 501, 502 })
	eq(p.nodesRemove, { 20 })
	eq(p.cfgPrune, { 10, 21 })
	local none, why = UN.plan({ edges = { 501 } }, reads({ edges = { [501] = false } }))
	eq(none, nil)
	eq(why, "gone")
	eq(select(2, UN.plan(nil, reads())), "noRecord")
end)

test("plan refuses owned edges, edges with stops, construction nodes and lit junctions", function()
	eq(select(2, UN.plan({ edges = { 501 } }, reads({ edges = { [501] = { n0 = 10, n1 = 20, owned = true } } }))), "owned:501")
	eq(select(2, UN.plan({ edges = { 501 } }, reads({ edges = { [501] = { n0 = 10, n1 = 20, objects = 1 } } }))), "objects:501")
	eq(select(2, UN.plan({ edges = { 501 } }, reads({ construction = { [10] = true } }))), "construction:10")
	eq(select(2, UN.plan({ edges = { 501 } }, reads({ lights = { [10] = true } }))), "trafficLights:10")
end)

test("prune drops connections and crosswalks through removed edges; houses count built lots", function()
	local conns = {
		{ segment0 = 400, lane0 = 1, segment1 = 501, lane1 = 2 },
		{ segment0 = 501, lane0 = 1, segment1 = 400, lane1 = 2 },
		{ segment0 = 400, lane0 = 1, segment1 = 401, lane1 = 2 },
	}
	local keep, cws, dropped = UN.prune(conns, { 400, 501 }, { [501] = true })
	eq(#keep, 1)
	eq(keep[1].segment1, 401)
	eq(cws, { 400 })
	eq(dropped, 3)
	eq(UN.houses({ edges = { 501, 502 } }, { [501] = 4, [700] = 9 }), 4)
end)
