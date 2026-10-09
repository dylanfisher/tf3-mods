-- bb_commit against a fake api: two-step vs combined proposals, split retries with a skipped
-- reason, the hard-rule recheck right before sending, money refusal, preview sums, and the
-- command flags (ignoreErrors=false, playerInitiated=true, doDust=true). PLAN Phase 3.

local CT = {
	BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", CONSTRUCTION = "CONSTRUCTION",
	PLAYER_OWNED = "PLAYER_OWNED", PLAYER = "PLAYER", SUBCONSTRUCTION = "SUBCONSTRUCTION",
	ACCOUNT = "ACCOUNT",
}
local ME, OTHER, HQ = 1, 2, 900

local world
local function put(e, t, v)
	world.comps[e] = world.comps[e] or {}
	world.comps[e][t] = v
end

local function reset()
	world = {
		comps = {}, nodeCon = {}, nodeSegs = {}, edgeCon = {}, bad = {}, sent = {}, previews = 0,
		groupOf = {}, onSend = nil, throwOnSend = false,
	}
	put(ME, CT.PLAYER, { headquarters = HQ })
	put(ME, CT.ACCOUNT, { balance = 1000000 })
end

local function addEdge(e, n0, n1, opts)
	opts = opts or {}
	put(e, CT.BASE_EDGE, {
		type = "NORMAL", objects = opts.objects or {}, node0 = n0, node1 = n1,
		position0 = { x = 0, y = 0, z = 0 }, position1 = { x = 10, y = 0, z = 0 },
		tangent0 = { x = 10, y = 0, z = 0 }, tangent1 = { x = 10, y = 0, z = 0 },
	})
	if opts.street ~= false then put(e, CT.BASE_EDGE_STREET, {}) end
	put(e, CT.PLAYER_OWNED, { player = opts.owner or ME })
	for _, n in ipairs({ n0, n1 }) do
		world.nodeSegs[n] = world.nodeSegs[n] or {}
		table.insert(world.nodeSegs[n], e)
	end
end

local function addCon(e, opts)
	opts = opts or {}
	put(e, CT.CONSTRUCTION, {
		transf = { getTransl = function(_) return { x = 0, y = 0, z = 0 } end },
		stations = opts.stations or {}, depots = opts.depots or {}, industries = opts.industries or {},
		townBuildings = {}, frozenEdges = {}, frozenNodes = {},
	})
	if opts.owner ~= false then put(e, CT.PLAYER_OWNED, { player = opts.owner or ME }) end
end

local function proposalEntities(p)
	local out = {}
	if p.kind == "segments" then
		for _, e in ipairs(p.edges) do out[#out + 1] = e end
	else
		for _, e in ipairs(p.constructionsToRemove or {}) do out[#out + 1] = e end
		for _, e in ipairs(p.streetProposal.edgesToRemove or {}) do out[#out + 1] = e end
	end
	return out
end

local fakeApi = {
	type = {
		ComponentType = CT,
		enum = { BaseEdgeType = { NORMAL = "NORMAL", BRIDGE = "BRIDGE", TUNNEL = "TUNNEL" } },
		SimpleProposal = { new = function() return { streetProposal = {} } end },
		Context = { new = function() return {} end },
	},
	util = { formatMoney = function(c) return "$" .. tostring(c) end },
	gui = { construction = { getRefundableEntities = function() return { "refund-token" } end } },
	cmd = {
		makeWorldBuildProposalCmd = function(p, ctx, ignoreErrors, playerInitiated, doDust)
			return { proposal = p, ctx = ctx, ignoreErrors = ignoreErrors, playerInitiated = playerInitiated, doDust = doDust }
		end,
		sendCommand = function(cmd, cb)
			if world.throwOnSend then error("send exploded") end
			world.sent[#world.sent + 1] = cmd
			local ents = proposalEntities(cmd.proposal)
			for _, e in ipairs(ents) do
				if world.bad[e] then
					cb({ resultProposalData = { errorState = { messages = { world.bad[e] } } } }, false, {})
					return
				end
			end
			for _, e in ipairs(ents) do world.comps[e] = nil end
			if world.onSend then world.onSend(cmd) end
			cb({ resultProposalData = { errorState = { messages = {} } } }, true, {})
		end,
	},
	engine = {
		entityExists = function(e) return world.comps[e] ~= nil end,
		getComponent = function(e, t) return world.comps[e] and world.comps[e][t] or nil end,
		util = {
			getPlayer = function() return ME end,
			construction = { findSegmentsToDelete = function(_con, _keep) return {} end },
			proposal = {
				makeSegmentsRemoveProposal = function(edges)
					local c = {}
					for i, e in ipairs(edges) do c[i] = e end
					return { kind = "segments", edges = c }
				end,
				makeProposalData = function(p, _ctx)
					world.previews = world.previews + 1
					local n = #proposalEntities(p)
					local msgs = {}
					for _, e in ipairs(proposalEntities(p)) do if world.bad[e] then msgs[#msgs + 1] = world.bad[e] end end
					return { costs = 100 * n, errorState = { critical = false, messages = msgs } }
				end,
			},
		},
		system = {
			streetConnectorSystem = {
				getConstructionEntityForEdge = function(e) return world.edgeCon[e] or -1 end,
				getConstructionEntityForNode = function(n) return world.nodeCon[n] or -1 end,
				getConstructionEntityForSubconstruction = function(_e) return -1 end,
			},
			streetSystem = {
				getNodeSegments = function(n) return world.nodeSegs[n] or {} end,
			},
			stationGroupSystem = {
				getStationGroup = function(st) return world.groupOf[st] or -1 end,
			},
		},
	},
}

local commit = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_commit.tl"
local DEFAULTS = { combined = commit.COMBINED_PROPOSAL, withPlayer = commit.CONTEXT_WITH_PLAYER }
local CTX = { player = ME, hq = HQ }

before_each(function()
	reset()
	set_global("api", fakeApi)
	commit.COMBINED_PROPOSAL = false
	commit.CONTEXT_WITH_PLAYER = true
end)

local function run(edges, cons, pre)
	local results = {}
	local lines = {}
	commit.commit(edges, cons, CTX, {}, pre, function(r) results[#results + 1] = r end,
		function(s) lines[#lines + 1] = s end)
	eq(#results, 1, "onDone exactly once")
	return results[1], lines
end

test("defaults: base two-step, player context, 4 previews/s", function()
	eq(DEFAULTS.combined, false)
	eq(DEFAULTS.withPlayer, true)
	eq(commit.PREVIEW_INTERVAL, 0.25)
end)

test("two-step: constructions first, then edges via makeSegmentsRemoveProposal; command flags", function()
	addCon(50)
	addEdge(10, 1, 2)
	addEdge(11, 2, 3)
	local r, lines = run({ 10, 11 }, { 50 })
	eq(r.removed, 3)
	eq(r.skipped, 0)
	eq(r.commands, 2)
	eq(r.refused, nil)
	eq(#world.sent, 2)
	eq(world.sent[1].proposal.constructionsToRemove, { 50 })
	eq(world.sent[1].proposal.streetProposal.edgesToRemove, {})
	eq(world.sent[2].proposal.kind, "segments")
	eq(world.sent[2].proposal.edges, { 10, 11 })
	for _, c in ipairs(world.sent) do
		eq(c.ignoreErrors, false, "never ignoreErrors")
		eq(c.playerInitiated, true)
		eq(c.doDust, true)
		eq(c.ctx.player, ME)
		eq(c.ctx.refundableEntities, { "refund-token" })
	end
	ok(#lines >= 3, "logs commit, commands and summary")
	ok(lines[#lines]:find("commit done: removed 3 of 3", 1, true), lines[#lines])
end)

test("split: one bad edge is skipped with the game's reason, the rest goes", function()
	for i = 1, 6 do addEdge(10 + i, 100 + i, 200 + i) end
	world.bad[13] = "Vehicle in the way"
	local r = run({ 11, 12, 13, 14, 15, 16 }, {})
	eq(r.removed, 5)
	eq(r.skipped, 1)
	eq(r.reasons, { ["Vehicle in the way"] = 1 })
	ok(r.commands <= 7, "halving, not one by one: " .. r.commands)
	ok(world.comps[13] ~= nil, "bad edge still there")
	eq(world.comps[11], nil)
end)

test("hard rules are re-checked: industry, HQ, foreign, construction-owned never sent", function()
	addCon(50)
	addCon(51, { industries = { 1 } })
	addCon(HQ)
	addEdge(10, 1, 2)
	addEdge(11, 2, 3, { owner = OTHER })
	addEdge(12, 3, 4)
	world.edgeCon[12] = 51
	local r = run({ 10, 11, 12, 999 }, { 50, 51, HQ })
	eq(r.removed, 2)
	eq(r.skipped, 5)
	eq(r.reasons, { industry = 1, HQ = 1, ["other player"] = 1, ["part of a construction"] = 1, gone = 1 })
	for _, c in ipairs(world.sent) do
		for _, e in ipairs(proposalEntities(c.proposal)) do
			ok(e == 10 or e == 50, "sent only allowed entities, got " .. tostring(e))
		end
	end
end)

test("recheck right before sending: an edge that changed owner after step 1 is dropped", function()
	addCon(50)
	addEdge(10, 1, 2)
	addEdge(11, 2, 3)
	world.onSend = function(cmd)
		if cmd.proposal.kind ~= "segments" then put(11, CT.PLAYER_OWNED, { player = OTHER }) end
	end
	local r = run({ 10, 11 }, { 50 })
	eq(r.removed, 2)
	eq(r.reasons, { ["other player"] = 1 })
	eq(world.sent[2].proposal.edges, { 10 })
end)

test("nothing left after the recheck: refused, no command", function()
	addCon(51, { industries = { 1 } })
	local r = run({}, { 51 })
	eq(r.refused, "nothing left to remove")
	eq(#world.sent, 0)
end)

test("money: preflight cost above the balance refuses the whole commit", function()
	put(ME, CT.ACCOUNT, { balance = 150 })
	addEdge(10, 1, 2)
	addEdge(11, 2, 3)
	local r = run({ 10, 11 }, {})
	eq(r.refused, "not enough money")
	eq(r.cost, 200)
	eq(r.removed, 0)
	eq(#world.sent, 0)
end)

test("a given preview is reused (no second preflight)", function()
	addEdge(10, 1, 2)
	local r = run({ 10 }, {}, { ok = true, cost = 5, critical = false, errors = {}, seconds = 0 })
	eq(world.previews, 0)
	eq(r.cost, 5)
	eq(r.removed, 1)
end)

test("preview: two-step sums both proposals and collects messages", function()
	addCon(50)
	addEdge(10, 1, 2)
	addEdge(11, 2, 3)
	world.bad[11] = "Vehicle in the way"
	local pv = commit.preview({ 10, 11 }, { 50 })
	eq(pv.ok, true)
	eq(pv.cost, 300)
	eq(pv.errors, { "Vehicle in the way" })
	eq(world.previews, 2)
	eq(commit.preview({}, {}).cost, 0)
end)

test("combined: one SimpleProposal with edge objects and orphan nodes (shared / frozen kept)", function()
	commit.COMBINED_PROPOSAL = true
	-- 1 —10— 2 —11— 3, and 2 —12— 4 stays; node 3 is frozen (station).
	addEdge(10, 1, 2, { objects = { { 77, "SIGNAL" } } })
	addEdge(11, 2, 3)
	addEdge(12, 2, 4)
	world.nodeCon[3] = 60
	addCon(50)
	local r = run({ 10, 11 }, { 50 })
	eq(r.removed, 3)
	eq(#world.sent, 1)
	local p = world.sent[1].proposal
	eq(p.constructionsToRemove, { 50 })
	eq(p.streetProposal.edgesToRemove, { 10, 11 })
	eq(p.streetProposal.edgeObjectsToRemove, { 77 })
	eq(p.streetProposal.nodesToRemove, { 1 }, "2 keeps edge 12, 3 is frozen")
end)

test("combined split: the bad construction is skipped, edges still go", function()
	commit.COMBINED_PROPOSAL = true
	addCon(50)
	addEdge(10, 1, 2)
	world.bad[50] = "Locked"
	local r = run({ 10 }, { 50 })
	eq(r.removed, 1)
	eq(r.reasons, { Locked = 1 })
end)

test("a throwing sendCommand stops the commit once, with a reason", function()
	addEdge(10, 1, 2)
	world.throwOnSend = true
	local r = run({ 10 }, {})
	eq(r.removed, 0)
	eq(r.reasons, { ["script error"] = 1 })
end)

test("bare context when CONTEXT_WITH_PLAYER is off", function()
	commit.CONTEXT_WITH_PLAYER = false
	addEdge(10, 1, 2)
	run({ 10 }, {})
	eq(world.sent[1].ctx, {})
end)
