-- Stress Test "Remove roads" (Towns tab): every street edge that belongs to no construction, removed
-- in batches. Each batch is one SimpleProposal (streetProposal.edgesToRemove + the nodes it leaves
-- without any segment), sent with makeWorldBuildProposalCmd(p, nil, false, false) like the other
-- Stress Test proposals (stress_buslines.tl). Pattern: square_bulk_bulldozer bb_commit.tl:
--   whole tables assigned to the proposal lists (the userdata setter copies)  bb_commit.tl:148-153
--   orphan nodes from fresh getNodeSegments, construction nodes never removed  bb_commit.tl:130-146
-- Edges come from streetSystem.getNode2StreetEdgeMap() (BASE_EDGE_STREET can't be listed with
-- getEntitiesWithComponent: docs/findings.md "Stress Test probes"). Edges of a construction (stations,
-- depots, construction-built roads) go only with their construction: kept and counted.
-- A batch the engine refuses is split in half and retried; a single edge that fails is logged and
-- skipped. One proposal in flight at a time (serial queue lane).
-- A node that stays (its other edges are in a later batch, or it belongs to a construction) gets its
-- lane connections and crosswalks through the removed edges dropped in the same proposal
-- (nodeConfigsToRemove + nodeConfigsToAdd, as the Crossing Tool). Without that, a node whose
-- connections were written by a script (Junction test links, Smart Lanes) keeps pointing at the
-- removed edge, and the proposal throws: in game 2026-10-11 every batch failed with std::exception
-- after StreetShapeFactory.cpp:195 GetOrMakeLanes "lc.segment1 not found".

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones

local roads : SquareStressRoads = {}

local function str(v : any) : string
	return logic.listText(v)
end

local function errText(data : any) : string
	local ok, s = pcall(function() : string
		local d = data as WorldBuildProposalCommandData
		local es = d.resultProposalData.errorState
		return string.format("critical=%s messages=%s", tostring(es.critical), str(es.messages))
	end)
	return ok and s or "(no error state)"
end

--- Every street edge, and how many of them belong to a construction (left out of the first list).
local function gatherEdges() : {integer}, integer
	local ok, m = pcall(api.engine.system.streetSystem.getNode2StreetEdgeMap)
	if not ok or m == nil then return {}, 0 end
	local free : {integer} = {}
	local kept = 0
	for _, e in ipairs(logic.uniqueEdges(m as {integer : {integer}})) do
		local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForEdge, e)
		if okC and con ~= nil and con < 0 then
			free[#free + 1] = e
		else
			kept = kept + 1
		end
	end
	return free, kept
end

--- node's configuration without the lane connections and crosswalks through `gone` edges, nil when
--- none goes through them (or the node has no configuration).
local function prunedConfig(node : integer, gone : {integer : boolean}) : Proposal.BaseNodeLaneConnectionAndEntity
	local entry, changed = rt.nodeConfigEntry(node, nil, gone)
	if entry == nil or changed == 0 then return nil end
	return entry
end

--- The removal proposal of a batch from fresh engine reads: edges that still exist and the nodes
--- they leave without segments. nil when nothing of the batch is left.
local function batchProposal(batch : {integer}) : SimpleProposal, {integer}, integer
	local live : {integer} = {}
	local ends : {{integer}} = {}
	for _, e in ipairs(batch) do
		local be = api.engine.entityExists(e) and api.engine.getComponent(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge or nil
		if be ~= nil then
			live[#live + 1] = e
			ends[#ends + 1] = { be.node0, be.node1 }
		end
	end
	if #live == 0 then return nil, live, 0 end
	local degree : {integer : integer} = {}
	local frozen : {integer : boolean} = {}
	for _, pair in ipairs(ends) do
		for k = 1, 2 do
			local n = pair[k]
			if n ~= nil and n >= 0 and frozen[n] == nil then
				local okS, segs = pcall(api.engine.system.streetSystem.getNodeSegments, n)
				if okS and segs ~= nil then degree[n] = #segs end
				-- Unreadable owner counts as a construction node: never removed.
				local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForNode, n)
				frozen[n] = not okC or con == nil or con >= 0
			end
		end
	end
	local nodes = logic.orphanNodes(ends, degree, frozen)
	local gone : {integer : boolean} = {}
	for _, e in ipairs(live) do gone[e] = true end
	local orphan : {integer : boolean} = {}
	for _, n in ipairs(nodes) do orphan[n] = true end
	local cfgRemove : {integer} = {}
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local seen : {integer : boolean} = {}
	for _, pair in ipairs(ends) do
		for k = 1, 2 do
			local n = pair[k]
			if n ~= nil and n >= 0 and not orphan[n] and not seen[n] then
				seen[n] = true
				local okE, entry = pcall(prunedConfig, n, gone)
				if okE and entry ~= nil then
					cfgRemove[#cfgRemove + 1] = n
					cfgAdd[#cfgAdd + 1] = entry
				end
			end
		end
	end
	local p = api.type.SimpleProposal.new()
	p.streetProposal.edgesToRemove = live
	p.streetProposal.nodesToRemove = nodes
	if #cfgAdd > 0 then
		p.streetProposal.nodeConfigsToRemove = cfgRemove
		p.streetProposal.nodeConfigsToAdd = cfgAdd
	end
	return p, live, #nodes
end

function roads.count() : integer, integer
	local free, kept = gatherEdges()
	return #free, kept
end

function roads.removeAll()
	local name = "remove_roads"
	local busy = rt.busyJob(rt.TEST_JOBS)
	if busy ~= nil then
		rt.warn("Remove all roads", string.format("Remove all roads: %s is still queued or running; wait for it to finish.", busy))
		return
	end
	-- the Showcase's junctions go with the roads: its twin zones go from Smart Lanes too (harmless without it)
	slzones.sendClear(name)
	local batches : {{integer}} = {}
	local found, kept, removed, nodesRemoved, failed, splits = 0, 0, 0, 0, 0, 0
	rt.enqueue(name, 1, function(i : integer, job : SquareStressJob)
		local function last()
			if i >= job.total then
				local left = gatherEdges()
				rt.log(string.format("[SQST] %s summary edges=%d removed=%d nodes=%d failed=%d splits=%d inConstructions=%d streets left=%d",
					name, found, removed, nodesRemoved, failed, splits, kept, #left))
			end
		end
		if i == 1 then
			local free : {integer}
			free, kept = gatherEdges()
			found = #free
			batches = logic.chunk(free, logic.ROAD_BATCH)
			job.total = math.max(1, #batches)
			rt.log(string.format("[SQST] %s: %d street edges in %d batches (%d in constructions kept)", name, found,
				#batches, kept))
		end
		local b = batches[i]
		if b == nil then
			logic.resume(job)
			last()
			return
		end
		local p, live, nNodes = batchProposal(b)
		if p == nil then
			logic.resume(job)
			last()
			return
		end
		local t0 = rt.nowUs()
		local function done(success : boolean, data : any)
			local ms = (rt.nowUs() - t0) / 1000
			if success then
				removed = removed + #live
				nodesRemoved = nodesRemoved + nNodes
			elseif #live > 1 then
				-- Split and retry both halves at the end of the job.
				local h = math.floor(#live / 2)
				local a, c : {integer}, {integer} = {}, {}
				for k, e in ipairs(live) do
					if k <= h then a[#a + 1] = e else c[#c + 1] = e end
				end
				batches[#batches + 1] = a
				batches[#batches + 1] = c
				job.total = job.total + 2
				splits = splits + 1
			else
				failed = failed + 1
			end
			local why = type(data) == "string" and (" " .. data as string) or (success and "" or (" " .. errText(data)))
			rt.detail(string.format("[SQST] %s batch %d/%d edges=%d nodes=%d success=%s ms=%.0f%s", name, i, job.total,
				#live, nNodes, tostring(success), ms, why))
			logic.resume(job)
			last()
		end
		-- A proposal the engine throws on (an assert while building it) counts as refused: split and
		-- retried like one it answers with failure (2026-10-11: std::exception ended every batch).
		local okS, err : boolean, any = pcall(function()
			rt.send(name, api.cmd.makeWorldBuildProposalCmd(p, nil, false, false), done)
		end)
		if not okS then done(false, "threw: " .. tostring(err)) end
	end, { serial = true, label = "Removing roads" })
end

return roads
