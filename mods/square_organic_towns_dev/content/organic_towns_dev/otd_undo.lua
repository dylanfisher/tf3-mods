-- DEV ONLY (never upload). Organic Towns dev tools: which entities "Undo last increment" removes (pure; the
-- engine reads are injected so tests drive it with fakes).
--
-- Rules (docs/findings.md):
--   * Removing a town edge demolishes the houses along it (HANDOFF D4, 776k): the runner warns with the count.
--   * Edges that are player owned or carry objects (a stop) are never removed: the whole undo is refused.
--   * A node left without street edges goes into nodesToRemove ("Remove all roads", square_stress_test).
--   * A node that keeps other edges and has a BASE_NODE_CONFIG gets its config pruned in the same proposal
--     (remove + add without the connections and crosswalks through the removed edges): a remaining node whose
--     lane connections still name a removed edge throws "lc.segment1 not found". The joint of a D3 join goes
--     back to a plain dead end that way (0 connections). A node WITHOUT a config is never put into
--     nodeConfigsToRemove (Engine.cpp:693 assert, crash).
--   * Nodes inside a construction are refused; so are configs with traffic light phases (pruning would leave the
--     phases pointing past the list: VectorMap.h:11 assert).

local U = {}

--- record = { edges = { edge ids } } (ot_driver history); reads = {
---   edge = function(id) -> { n0, n1, owned = bool, objects = n } or nil (gone),
---   nodeEdges = function(n) -> { street edge ids at the node },
---   hasConfig = function(n) -> bool, hasLights = function(n) -> bool (optional),
---   inConstruction = function(n) -> bool }.
--- Returns plan = { edges, nodesRemove, cfgPrune, missing (edges already gone) } or nil, reason.
function U.plan(record, reads)
	if record == nil or record.edges == nil or #record.edges == 0 then return nil, "noRecord" end
	local live, gone, missing = {}, {}, 0
	local ends = {}
	for _, id in ipairs(record.edges) do
		local ed = reads.edge(id)
		if ed == nil then
			missing = missing + 1
		else
			if ed.owned then return nil, "owned:" .. id end
			if (ed.objects or 0) > 0 then return nil, "objects:" .. id end
			live[#live + 1] = id
			gone[id] = true
			ends[#ends + 1] = ed.n0
			ends[#ends + 1] = ed.n1
		end
	end
	if #live == 0 then return nil, "gone" end
	local seen, nodesRemove, cfgPrune = {}, {}, {}
	for _, n in ipairs(ends) do
		if n ~= nil and n >= 0 and not seen[n] then
			seen[n] = true
			if reads.inConstruction(n) then return nil, "construction:" .. n end
			local left = 0
			for _, e in ipairs(reads.nodeEdges(n) or {}) do
				if not gone[e] then left = left + 1 end
			end
			if left == 0 then
				nodesRemove[#nodesRemove + 1] = n
			elseif reads.hasConfig(n) then
				if reads.hasLights and reads.hasLights(n) then return nil, "trafficLights:" .. n end
				cfgPrune[#cfgPrune + 1] = n
			end
		end
	end
	table.sort(live)
	table.sort(nodesRemove)
	table.sort(cfgPrune)
	return { edges = live, nodesRemove = nodesRemove, cfgPrune = cfgPrune, missing = missing, gone = gone }
end

--- A config's lane connections and crosswalks without the ones through removed edges (gone = {[edge] = true}).
--- conns = { { segment0, lane0, segment1, lane1, ... } as plain tables with those keys }, crosswalks = { edge }.
--- Returns keptConns, keptCrosswalks, dropped count.
function U.prune(conns, crosswalks, gone)
	local keep, cws, dropped = {}, {}, 0
	for _, c in ipairs(conns or {}) do
		if gone[c.segment0] or gone[c.segment1] then dropped = dropped + 1 else keep[#keep + 1] = c end
	end
	for _, c in ipairs(crosswalks or {}) do
		if gone[c] then dropped = dropped + 1 else cws[#cws + 1] = c end
	end
	return keep, cws, dropped
end

--- Houses the undo would demolish: built lots on the removed edges (builtBy = { [edge] = count }).
function U.houses(plan, builtBy)
	local n = 0
	for _, e in ipairs(plan.edges) do n = n + ((builtBy or {})[e] or 0) end
	return n
end

return U
