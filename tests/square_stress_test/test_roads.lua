-- stress_roads.tl against a fake api: batches of edge removals, orphan nodes, construction edges
-- kept, failed batches split in half, one proposal in flight at a time.

local T = 0
local sent        -- every sendCommand: { cmd, cb }
local edges       -- edge -> { n0, n1 } (existing street edges)
local conEdge     -- edge -> construction (>= 0) or nil
local conNode     -- node -> construction (>= 0) or nil
local refuse      -- function(edgeList) -> true when the engine refuses the proposal
local configs     -- node -> BaseNodeConfig ({ laneConnections, crosswalks }) or nil

local function node2edges()
	local m = {}
	for e, ns in pairs(edges) do
		for _, n in ipairs(ns) do
			m[n] = m[n] or {}
			table.insert(m[n], e)
		end
	end
	return m
end

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = { BASE_EDGE = "BASE_EDGE", BASE_NODE_CONFIG = "BASE_NODE_CONFIG", TOWN = "TOWN" },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			LaneConnection = { new = function() return { ctor = true } end },
		},
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player)
				return { kind = "proposal", p = p, ctx = ctx, ignore = ignore, player = player }
			end,
		},
		engine = {
			entityExists = function(e) return edges[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "BASE_NODE_CONFIG" then return configs[e] end
				eq(ct, "BASE_EDGE")
				local ns = edges[e]
				return ns and { node0 = ns[1], node1 = ns[2] } or nil
			end,
			system = {
				streetSystem = {
					getNode2StreetEdgeMap = node2edges,
					getNodeSegments = function(n) return node2edges()[n] or {} end,
				},
				streetConnectorSystem = {
					getConstructionEntityForEdge = function(e) return conEdge[e] or -1 end,
					getConstructionEntityForNode = function(n) return conNode[n] or -1 end,
				},
			},
		},
	}
end

local rt, roads, logic
before_each(function()
	T, sent, edges, conEdge, conNode, configs = 0, {}, {}, {}, {}, {}
	refuse = function() return false end
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	roads = ug_require "square_stress_test::/stress/gui/stress_roads.tl"
end)

local function frames(n) for _ = 1, n do rt.tick() end end

--- Answers every open proposal: the engine removes the edges unless refuse() says no.
local function answerAll(rounds)
	for _ = 1, rounds do
		frames(1)
		for _, s in ipairs(sent) do
			if not s.answered then
				s.answered = true
				local list = s.cmd.p.streetProposal.edgesToRemove
				local ok_ = not refuse(list)
				if ok_ then for _, e in ipairs(list) do edges[e] = nil end end
				s.cb(s.cmd, ok_)
			end
		end
	end
end

--- A straight road of n edges: nodes 1..n+1, edges 1001..1000+n.
local function road(n, firstNode, firstEdge)
	for i = 0, n - 1 do edges[firstEdge + i] = { firstNode + i, firstNode + i + 1 } end
end

test("count: street edges, construction edges counted apart", function()
	road(5, 1, 1001)
	conEdge[1003] = 77
	eq({ roads.count() }, { 4, 1 })
end)

test("remove all: batches of ROAD_BATCH, one in flight, orphan nodes removed, construction edges stay", function()
	road(250, 1, 1001)
	conEdge[1250] = 77   -- last edge belongs to a station
	conNode[251] = 77
	roads.removeAll()
	frames(3)
	eq(#sent, 1) -- serial
	local first = sent[1].cmd
	eq(first.ctx, nil)
	eq(first.ignore, false)
	eq(#first.p.streetProposal.edgesToRemove, logic.ROAD_BATCH)
	-- nodes 1..100 are left without edges; node 101 still has edge 1101
	eq(#first.p.streetProposal.nodesToRemove, 100)
	answerAll(20)
	eq(#sent, 3)
	-- node 250 also touches the construction edge 1250: kept
	local last = sent[3].cmd.p.streetProposal
	eq(#last.edgesToRemove, 49)
	for _, n in ipairs(last.nodesToRemove) do ok(n ~= 250 and n ~= 251, "node " .. n) end
	eq(edges[1250] ~= nil, true)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("remove_roads summary edges=249 removed=249 nodes=", 1, true), all)
	ok(all:find("inConstructions=1 streets left=0", 1, true), all)
	eq(#rt.queue.jobs, 0)
end)

test("a refused batch is split in half and retried; a single bad edge is skipped and counted", function()
	road(8, 1, 1001)
	refuse = function(list)
		for _, e in ipairs(list) do if e == 1005 then return true end end
		return false
	end
	roads.removeAll()
	answerAll(40)
	-- 8 refused -> 4 ok + 4 refused -> 2 ok + 2 refused -> 1 ok (1006) + 1 failed (1005)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("removed=7 nodes=", 1, true), all)
	ok(all:find("failed=1 splits=3", 1, true), all)
	eq(edges[1005] ~= nil, true)
	eq(#rt.queue.jobs, 0)
end)

test("no streets: one step, summary with zero edges", function()
	roads.removeAll()
	answerAll(5)
	eq(#sent, 0)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("remove_roads summary edges=0 removed=0", 1, true), all)
end)

test("a node that stays loses the lane connections and crosswalks through the removed edges", function()
	-- 1 -[10]- 2 -[11]- 3; edge 11 belongs to a construction, so node 2 stays with its config
	edges[10] = { 1, 2 }
	edges[11] = { 2, 3 }
	conEdge[11] = 5
	conNode[3] = 5
	local function lc(a, b) return { segment0 = a, lane0 = 1, segment1 = b, lane1 = 2, withRoad = true, withTram = false } end
	configs[2] = { laneConnections = { lc(10, 11), lc(11, 10), lc(11, 11) }, crosswalks = { 10, 11 } }
	configs[1] = { laneConnections = {}, crosswalks = {} }
	roads.removeAll()
	answerAll(5)
	eq(#sent, 1)
	local sp = sent[1].cmd.p.streetProposal
	eq(sp.edgesToRemove, { 10 })
	eq(sp.nodesToRemove, { 1 })
	eq(sp.nodeConfigsToRemove, { 2 }, "remove + add, never a remove alone")
	eq(#sp.nodeConfigsToAdd, 1)
	local cfg = sp.nodeConfigsToAdd[1].comp
	eq(sp.nodeConfigsToAdd[1].entity, 2)
	eq(#cfg.laneConnections, 1)
	eq(cfg.laneConnections[1].segment0, 11)
	ok(cfg.laneConnections[1].ctor, "rebuilt with LaneConnection.new")
	eq(cfg.crosswalks, { 11 })
end)

test("nodes without connections through the removed edges get no config change", function()
	edges[10] = { 1, 2 }
	edges[11] = { 2, 3 }
	conEdge[11] = 5
	conNode[3] = 5
	configs[2] = { laneConnections = {}, crosswalks = {} }
	roads.removeAll()
	answerAll(5)
	eq(sent[1].cmd.p.streetProposal.nodeConfigsToAdd, nil)
end)

test("remove all refuses while a test build (Junction / Crossing test, Showcase) is queued", function()
	road(5, 1, 1001)
	rt.enqueue("showcase", 1, function(_i, job) end)
	local before = #rt.warnings
	roads.removeAll()
	eq(#rt.warnings, before + 1, "busy dialog")
	ok(rt.warnings[#rt.warnings].body:find("showcase is still queued or running", 1, true), rt.warnings[#rt.warnings].body)
	for _, j in ipairs(rt.queue.jobs) do ok(j.name ~= "remove_roads", "no removal queued") end
	rt.clearQueue()
end)

test("remove all: clears the Showcase's Smart Lanes zones first; without the event command (old api) it logs and goes on", function()
	local events = {}
	api.cmd.makeScriptingSendEventCmd = function(src, id, name, param) return { kind = "event", src = src, id = id, name = name, param = param } end
	local send = api.cmd.sendCommand
	api.cmd.sendCommand = function(cmd, cb)
		if cmd.kind == "event" then events[#events + 1] = cmd return end
		return send(cmd, cb)
	end
	edges = { [1] = { 10, 11 } }
	roads.removeAll()
	eq(#events, 1)
	eq({ events[1].id, events[1].name, events[1].param.op }, { "square_smart_lanes", "SmartLanes.zones", "clear" })
	ok(table.concat(rt.recent, "\n"):find("[SQST] showcase zones cleared by=remove_roads run=", 1, true))
	-- harmless without the call
	api.cmd.makeScriptingSendEventCmd = nil
	frames(10)
	edges = { [2] = { 12, 13 } }
	for _, s in ipairs(sent) do if not s.answered then s.answered = true s.cb(s.cmd, true) end end
	frames(10)
	roads.removeAll()
	ok(table.concat(rt.recent, "\n"):find("zones send failed", 1, true))
	ok(table.concat(rt.recent, "\n"):find("cleared by=remove_roads run=%S+ smart_lanes=no failed=yes") ~= nil, table.concat(rt.recent, "\n"))
end)
