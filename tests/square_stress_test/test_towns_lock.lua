-- Town growth locked into the grid (stress_towns lockTowns / densify, SHOWCASE.md "Town growth locked into the
-- grid") against a fake street world: every unlocked street of the town swapped for a locked copy in bounded
-- serial batches with complete node configs, a refused batch sent once more, unused corner stubs removed
-- (never a config removed from a node without one), the level weights and growth passes sent, and the leak
-- check after each pass (outside streets and houses counted, new streets locked).

local logic

local T = 0
local sent        -- every sendCommand: { cmd, cb }
local nodes       -- id -> { x, y, cfg (BASE_NODE_CONFIG or nil), con (in a construction) }
local edges       -- id -> { n0, n1, locked, objects, con }
local nextId
local towns_      -- town id -> { x, y, sizeFactors, buildings = { {x, y, level} } }
local weightsRead -- town id -> the last weights sent
local refuse      -- function(cmd, try) -> true: the proposal is refused

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function nodeEdges(n)
	local out = {}
	for e, ed in pairs(edges) do
		if ed.n0 == n or ed.n1 == n then out[#out + 1] = e end
	end
	table.sort(out)
	return out
end

local function newNode(x, y, noCfg)
	nextId = nextId + 1
	nodes[nextId] = { x = x, y = y, noCfg = noCfg }
	return nextId
end

local function newEdge(a, b, locked, extra)
	nextId = nextId + 1
	edges[nextId] = { n0 = a, n1 = b, locked = locked == true, objects = extra and extra.objects or {}, con = extra and extra.con }
	return nextId
end

--- The engine's answer to a street proposal: removed edges and nodes go, added edges get new ids.
local function apply(sp)
	for _, e in ipairs(sp.edgesToRemove or {}) do edges[e] = nil end
	for _, n in ipairs(sp.nodesToRemove or {}) do nodes[n] = nil end
	for _, seg in ipairs(sp.edgesToAdd or {}) do
		nextId = nextId + 1
		edges[nextId] = { n0 = seg.comp.node0, n1 = seg.comp.node1, locked = seg.comp.roadDevelopmentLocked == true, objects = {} }
	end
	for _, entry in ipairs(sp.nodeConfigsToAdd or {}) do
		if nodes[entry.entity] then nodes[entry.entity].noCfg = false end
	end
end

local function fakeApi()
	local CT = { TOWN = "TOWN", BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", BASE_NODE = "BASE_NODE",
		BASE_NODE_CONFIG = "BASE_NODE_CONFIG", TOWN_BUILDING = "TOWN_BUILDING", BOUNDING_VOLUME = "BOUNDING_VOLUME", CONSTRUCTION = "CONSTRUCTION" }
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = CT,
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = vec },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			SegmentAndEntity = { new = function() return {} end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			LaneConnection = { new = function() return { ctor = true } end },
			TrafficLightState = { new = function() return {} end },
			JournalEntry = { new = function() return { category = {} } end, Type = { OTHER = "OTHER" } },
		},
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb, t = T } end,
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player) return { kind = "build", p = p, ctx = ctx, ignore = ignore, player = player } end,
			makeTownUpdateSizeCmd = function(town, f, all) return { kind = "size", town = town, f = f, all = all } end,
			makeTownCustomDistributionWeightsCmd = function(town, w) return { kind = "weights", town = town, w = w } end,
		},
		engine = {
			entityExists = function(e) return towns_[e] ~= nil or edges[e] ~= nil or nodes[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "TOWN" then
					local t = towns_[e]
					return t and { sizeFactors = t.sizeFactors, levelToCapacityDistributionWeights = weightsRead[e],
						initialLandUseCapacities = t.initCaps } or nil
				elseif ct == "BASE_EDGE" then
					local ed = edges[e]
					if not ed then return nil end
					return { node0 = ed.n0, node1 = ed.n1, roadDevelopmentLocked = ed.locked, objects = ed.objects, tag = "edge" .. e }
				elseif ct == "BASE_EDGE_STREET" then
					return edges[e] and { street = e } or nil
				elseif ct == "BASE_NODE" then
					local n = nodes[e]
					return n and { position = vec(n.x, n.y, 0) } or nil
				elseif ct == "BASE_NODE_CONFIG" then
					local n = nodes[e]
					if not n or n.noCfg then return nil end
					local list = nodeEdges(e)
					local lcs = {}
					for i = 1, #list do
						for j = 1, #list do
							if i ~= j then lcs[#lcs + 1] = { segment0 = list[i], lane0 = 1, segment1 = list[j], lane1 = 2, withRoad = true, withTram = false } end
						end
					end
					if n.lit then
						-- a lit node: every edge a crosswalk; phases from n.lit (0-based indices)
						local tlc = { states = n.lit }
						tlc.clone = function(self) return { states = self.states, clone = self.clone } end
						return { laneConnections = lcs, crosswalks = list, trafficLightConfig = tlc }
					end
					return { laneConnections = lcs, crosswalks = { list[1] } }
				elseif ct == "TOWN_BUILDING" or ct == "BOUNDING_VOLUME" then
					for _, t in pairs(towns_) do
						local b = t.byId and t.byId[e]
						if b then
							if ct == "TOWN_BUILDING" then return { level = b.level, construction = b.con and (900000 + e) or nil } end
							if b.box then return { bbox = { min = { x = b.box[1], y = b.box[2] }, max = { x = b.box[3], y = b.box[4] } } } end
							return { bbox = { min = { x = b.x - 5, y = b.y - 5 }, max = { x = b.x + 5, y = b.y + 5 } } }
						end
					end
					return nil
				elseif ct == "CONSTRUCTION" and e > 900000 then
					for _, t in pairs(towns_) do
						local b = t.byId and t.byId[e - 900000]
						if b and b.con then
							return { transf = { getTransl = function() return { x = b.con[1], y = b.con[2], z = 0 } end } }
						end
					end
					return nil
				end
			end,
			util = {
				-- the engine's octree matches an edge by its position (the midpoint), not its extent
				-- (docs/findings/roads.md "Octree edge search matches the edge's position")
				octree = { findEntitiesInCircle = function(c, r, ct)
					assert(ct == "BASE_EDGE")
					local out = {}
					for e, ed in pairs(edges) do
						local p0, p1 = nodes[ed.n0], nodes[ed.n1]
						if p0 and p1 then
							local mx, my = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
							if (mx - c.x) ^ 2 + (my - c.y) ^ 2 <= r * r then out[#out + 1] = e end
						end
					end
					return out
				end },
				town = { getClosestTown = function(p)
					local best, bd = -1, math.huge
					for id, t in pairs(towns_) do
						local d = (t.x - p.x) ^ 2 + (t.y - p.y) ^ 2
						if d < bd then best, bd = id, d end
					end
					return best
				end },
				getPlayer = function() return 7 end,
				finance = { getPlayersBalance = function() return 1e9 end },
			},
			system = {
				streetSystem = {
					getNodeSegments = function(n) return nodeEdges(n) end,
					getNode2StreetEdgeMap = function()
						local m = {}
						for n in pairs(nodes) do m[n] = nodeEdges(n) end
						return m
					end,
				},
				streetConnectorSystem = {
					getConstructionEntityForEdge = function(e) return edges[e] and edges[e].con or -1 end,
					getConstructionEntityForNode = function(n) return nodes[n] and nodes[n].con or -1 end,
				},
				townBuildingSystem = { getTown2BuildingMap = function()
					local m = {}
					for id, t in pairs(towns_) do
						m[id] = {}
						for b in pairs(t.byId or {}) do m[id][#m[id] + 1] = b end
						table.sort(m[id])
					end
					return m
				end,
				-- residential capacity = population: t.pop when a test sets it (nil: no entry, unread)
				getTown2personCapacitiesMap = function()
					local m = {}
					for id, t in pairs(towns_) do
						if t.pop then m[id] = { t.pop, 0, 0 } end
					end
					return m
				end },
			},
		},
	}
end

local function addHouse(town, x, y, level, box, con)
	local t = towns_[town]
	t.byId = t.byId or {}
	nextId = nextId + 1
	t.byId[nextId] = { x = x, y = y, level = level, box = box, con = con }
end

local rt, towns
-- Town 1 at (0, 0), a 400 m locked grid (half 200, only its outline here): corners and side midpoints,
-- the four diagonal corner stubs (one used by a link: its outer end has the link's edge too, and one
-- corner without a config); inside two unlocked seed streets and one with a stop (edge objects); outside
-- an unlocked leak of two edges east and a junction's construction edge; town 2 far away with a street.
local W
local function world()
	W = {}
	local c = {}
	for _, p in ipairs({ { -200, -200 }, { 200, -200 }, { 200, 200 }, { -200, 200 } }) do c[#c + 1] = newNode(p[1], p[2]) end
	nodes[c[4]].noCfg = true
	local mids = {}
	for k = 1, 4 do
		local a, b = c[k], c[k % 4 + 1]
		mids[k] = newNode((nodes[a].x + nodes[b].x) / 2, (nodes[a].y + nodes[b].y) / 2)
		newEdge(a, mids[k], true)
		newEdge(mids[k], b, true)
	end
	local d = 60 * math.sqrt(0.5)
	W.stubs = {}
	for k, p in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local o = newNode(nodes[c[k]].x + p[1] * d, nodes[c[k]].y + p[2] * d)
		W.stubs[k] = { edge = newEdge(c[k], o, true), outer = o, corner = c[k] }
	end
	-- stub 2 (south east) is used by a link road (locked, ours)
	W.linkEdge = newEdge(W.stubs[2].outer, newNode(400, -400), true)
	local centre = newNode(0, 0)
	W.seed1 = newEdge(centre, newNode(0, 100))
	W.seed2 = newEdge(nodes[edges[W.seed1].n1] and edges[W.seed1].n1, mids[3])
	W.stop = newEdge(centre, newNode(-100, 0), false, { objects = { { 1, 2 } } })
	local east = mids[2]   -- the east side's midpoint (200, 0)
	local l1 = newNode(330, 0)
	W.leak1 = newEdge(east, l1)
	W.leak2 = newEdge(l1, newNode(460, 0))
	W.con = newEdge(newNode(-400, 0), newNode(-330, 0), false, { con = 99 })
	W.far = newEdge(newNode(6000, 0), newNode(6100, 0))
	W.area = { town = 1, label = "Tacoma", x = 0, y = 0, half = 200 }
end

before_each(function()
	T, sent, nodes, edges, nextId = 0, {}, {}, {}, 1000
	towns_ = { [1] = { x = 0, y = 0, sizeFactors = { 1, 1, 1 } }, [2] = { x = 6000, y = 0, sizeFactors = { 1, 1, 1 } } }
	weightsRead = {}
	refuse = nil
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl"
	world()
end)

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.msg end
	return table.concat(out, "\n")
end

local tries = {}
--- Ticks and answers every new command (build proposals applied unless refused); grow hooks run before
--- a size command's callback (the town building meanwhile).
local function run(rounds, onSize)
	for _ = 1, rounds do
		T = T + 600000
		rt.tick()
		for k = 1, #sent do
			local s = sent[k]
			if not s.answered then
				s.answered = true
				local ok_ = true
				if s.cmd.kind == "build" then
					local key = tostring(s.cmd.p)
					tries[key] = (tries[key] or 0) + 1
					if refuse and refuse(s.cmd) then ok_ = false else apply(s.cmd.p.streetProposal) end
				elseif s.cmd.kind == "size" then
					towns_[s.cmd.town].sizeFactors = s.cmd.f
					if onSize then onSize(s.cmd) end
				elseif s.cmd.kind == "weights" then
					weightsRead[s.cmd.town] = s.cmd.w
				end
				s.cb(s.cmd, ok_, {})
			end
		end
	end
end

local function builds()
	local out = {}
	for _, s in ipairs(sent) do if s.cmd.kind == "build" then out[#out + 1] = s.cmd.p.streetProposal end end
	return out
end

local function problems(sp)
	local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
	return nc.problems(sp, function() return 4 end)
end

test("lockTowns (after the links): every unlocked street of the town locked in one proposal, configs complete; unused stubs removed", function()
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	rt.tick()
	eq(#sent, 1, "one proposal in flight")
	local lock = sent[1].cmd.p.streetProposal
	local removed = {}
	for _, e in ipairs(lock.edgesToRemove) do removed[e] = true end
	eq(removed, { [W.seed1] = true, [W.seed2] = true, [W.leak1] = true, [W.leak2] = true },
		"seed streets and the leak; not the stop's edge, the junction's, the other town's or the locked grid")
	eq(#lock.edgesToAdd, 4)
	for _, seg in ipairs(lock.edgesToAdd) do eq(seg.comp.roadDevelopmentLocked, true) end
	eq(problems(lock), {})
	eq(sent[1].cmd.player, true)
	run(3)
	-- the stubs: the three no link uses, with their dead ends; corner 4 has no config (no remove on it)
	local bs = builds()
	eq(#bs, 2)
	local st = bs[2]
	eq(st.edgesToAdd, nil, "a removal only")
	local want = { W.stubs[1].edge, W.stubs[3].edge, W.stubs[4].edge }
	table.sort(st.edgesToRemove)
	eq(st.edgesToRemove, want)
	local dead = {}
	for _, n in ipairs(st.nodesToRemove) do dead[n] = true end
	eq(dead, { [W.stubs[1].outer] = true, [W.stubs[3].outer] = true, [W.stubs[4].outer] = true })
	eq(st.nodeConfigsToRemove, { W.stubs[1].corner, W.stubs[3].corner }, "corners with a config only")
	for _, entry in ipairs(st.nodeConfigsToAdd) do
		for _, lc in ipairs(entry.comp.laneConnections) do
			ok(lc.segment0 ~= W.stubs[1].edge and lc.segment1 ~= W.stubs[1].edge and lc.segment0 ~= W.stubs[3].edge, "no connection through a stub")
		end
		for _, cw in ipairs(entry.comp.crosswalks) do ok(cw ~= W.stubs[1].edge and cw ~= W.stubs[3].edge) end
	end
	eq(problems(st), {})
	ok(edges[W.stubs[2].edge] ~= nil, "the linked stub stays")
	local all = logText()
	ok(all:find("[SQST] showcase_lock town Tacoma lock pass=links edges=", 1, true), all)
	ok(all:find(" unlocked=4 inside=3 outside_streets=2 zone_streets=0 locked=4 refused=0 failed=0 batches=1 objects=1 left=0 stubs=3 removed=3", 1, true), all)
	ok(all:find("[SQST] showcase_lock summary pass=links towns=1 locked=4 failed=0 stubs_removed=3 stubs_kept=0 outside_streets=2", 1, true), all)
	ok(all:find("[SQST] action=showcase_lock count=1", 1, true), all)
	-- a second pass finds nothing left to lock or remove
	clear_logs()
	sent = {}
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(3)
	eq(#sent, 0)
	ok(logText():find(" unlocked=0 inside=1 outside_streets=0 zone_streets=0 locked=0 ", 1, true), logText())
end)

test("lockTowns (after the towns): no stub removal; bounded batches, one in flight, each built from fresh reads", function()
	-- more seed streets: 7 unlocked in all, batches of 3
	local a = newNode(50, 50)
	for k = 1, 3 do newEdge(a, newNode(50 + 30 * k, 50 + 10 * k)) end
	logic.LOCK_BATCH = 3
	towns.lockTowns("showcase_lock", { W.area }, { pass = "towns" })
	rt.tick()
	rt.tick()
	eq(#sent, 1)
	eq(#sent[1].cmd.p.streetProposal.edgesToRemove, 3)
	run(1)
	eq(#sent, 2, "the next batch only after the callback")
	ok(not sent[2].answered)
	run(5)
	local bs = builds()
	eq(#bs, 3, "7 edges: 3 + 3 + 1; no stub removal")
	eq(#bs[3].edgesToRemove, 1)
	for _, sp in ipairs(bs) do
		eq(problems(sp), {})
		for _, e in ipairs(sp.edgesToRemove) do ok(e ~= W.stubs[1].edge) end
	end
	local all = logText()
	ok(all:find(" locked=7 refused=0 failed=0 batches=3 objects=1 left=0 stubs=0 removed=0", 1, true), all)
	local unlocked = 0
	for _, ed in pairs(edges) do if not ed.locked and not ed.con and #ed.objects == 0 and nodes[ed.n0].x < 1000 then unlocked = unlocked + 1 end end
	eq(unlocked, 0, "every street of town 1 locked")
end)

test("lockTowns: at most LOCK_MAX_PASS edges per town and pass, the rest left for the next pass", function()
	logic.LOCK_MAX_PASS = 2
	towns.lockTowns("showcase_lock", { W.area }, { pass = "towns" })
	run(4)
	eq(#builds(), 1)
	eq(#builds()[1].edgesToRemove, 2)
	ok(logText():find(" unlocked=4 inside=3 outside_streets=2 zone_streets=0 locked=2 refused=0 failed=0 batches=1 objects=1 left=2 ", 1, true), logText())
end)

test("lockTowns: a refused batch is sent once more a few seconds later; refused twice it is left unlocked and the next batch goes on", function()
	logic.LOCK_BATCH = 2
	local n = 0
	refuse = function(cmd)
		n = n + 1
		return n <= 3   -- batch 1 twice, then batch 2 once
	end
	towns.lockTowns("showcase_lock", { W.area }, { pass = "towns" })
	run(30)
	local bs = builds()
	eq(#bs, 4, "batch 1 twice, batch 2 twice")
	eq(bs[1].edgesToRemove, bs[2].edgesToRemove)
	eq(bs[3].edgesToRemove, bs[4].edgesToRemove)
	ok(sent[2].t - sent[1].t >= logic.LOCK_RETRY_MS * 1000, "after the retry delay")
	local all = logText()
	ok(all:find("lock batch 1 (2 edges) refused; sent again in 3 s", 1, true), all)
	ok(all:find("lock batch 1 (2 edges) refused twice; left unlocked", 1, true), all)
	ok(all:find(" locked=2 refused=3 failed=2 batches=4 ", 1, true), all)
end)

test("lockTowns: an edge ending at a construction's node is never swapped (a junction's frozen streets)", function()
	local jn = newNode(100, -100)
	nodes[jn].con = 77
	local atJunction = newEdge(edges[W.seed1].n1, jn)
	towns.lockTowns("showcase_lock", { W.area }, { pass = "towns" })
	run(3)
	local bs = builds()
	eq(#bs, 1)
	for _, e in ipairs(bs[1].edgesToRemove) do ok(e ~= atJunction, "the edge at the construction node stays") end
	eq(#bs[1].edgesToRemove, 4)
	ok(edges[atJunction] ~= nil and not edges[atJunction].locked)
end)

test("lockTowns: a lit corner's phases are re-pointed when its stub goes (connections and crosswalks shift)", function()
	local c = W.stubs[1].corner
	-- 3 edges, stub last (highest id): 6 connections (0..5), crosswalks 6, 7, 8 (the stub's is 8)
	nodes[c].lit = {
		{ lockedLanes = { 0, 1, 2, 3, 4, 5, 6, 7, 8 }, duration = 20, minDuration = 1.5, canSkip = true },
		{ lockedLanes = { 7 }, duration = 6, minDuration = 1.5, canSkip = true },
		{ lockedLanes = { 8 }, duration = 3, minDuration = 1.5, canSkip = true },
	}
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(3)
	local st = builds()[2]
	local entry
	for _, e in ipairs(st.nodeConfigsToAdd) do if e.entity == c then entry = e end end
	ok(entry ~= nil, "the corner's config rewritten")
	eq(#entry.comp.laneConnections, 2)
	eq(#entry.comp.crosswalks, 2)
	local states = entry.comp.trafficLightConfig.states
	eq(#states, 3, "phases kept")
	eq(states[1].lockedLanes, { 0, 1, 2, 3 }, "all red: both connections and both crosswalks")
	eq(states[2].lockedLanes, { 3 }, "crosswalk 2 moved from 7 to 2 + 2 - 1")
	eq(states[3].lockedLanes, {}, "the stub's crosswalk is gone")
	eq(states[1].duration, 20)
	eq(problems(st), {})
end)

test("lockTowns: a town that is gone is logged and skipped; an empty list queues nothing", function()
	towns_[1] = nil
	towns.lockTowns("showcase_lock", { W.area }, { pass = "towns" })
	run(3)
	eq(#sent, 0)
	ok(logText():find("[SQST] showcase_lock town Tacoma: gone; not locked", 1, true), logText())
	towns.lockTowns("showcase_lock", {}, { pass = "towns" })
	eq(logic.pending(rt.queue), 0)
end)

test("densify: weights (3 land uses x 4 levels) then the passes; a leak check after each pass locks what the town grew; final levels", function()
	-- run the lock first so only growth is unlocked
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(5)
	sent = {}
	clear_logs()
	for k = 1, 30 do addHouse(1, -150 + k * 9, 0, 1 + k % 4) end
	addHouse(1, 0, 10, 4)
	local grown = 0
	towns.densify("showcase_grow", { W.area }, { factor = 10, passes = 2, weights = logic.DENSE_WEIGHTS })
	run(20, function(cmd)
		grown = grown + 1
		-- each pass: 25 houses, one of them outside, and a new street out of the grid (west)
		for k = 1, 25 do addHouse(1, -100 + k, 50, 4) end
		addHouse(1, 500, 0, 2)
		newEdge(newNode(-200, 50 * grown), newNode(-320, 50 * grown))
	end)
	local kinds = {}
	for k, s in ipairs(sent) do kinds[k] = s.cmd.kind end
	eq(kinds, { "weights", "size", "build", "size", "build" }, "weights, then per pass the growth and the lock of its new street")
	local w = sent[1].cmd.w
	eq(#w, 3)
	for k = 1, 3 do eq(w[k], { 0.0, 0.1, 0.5, 1.0 }) end
	eq(sent[2].cmd.f, { 10, 10, 10 })
	eq(sent[4].cmd.f, { 10, 10, 10 }, "the build-out pass re-sends")
	eq(sent[2].cmd.all, true)
	for _, sp in ipairs(builds()) do
		eq(#sp.edgesToAdd, 1)
		eq(sp.edgesToAdd[1].comp.roadDevelopmentLocked, true)
		eq(problems(sp), {})
	end
	local all = logText()
	ok(all:find("[SQST] showcase_grow queued towns=1 factor=x10 passes=2 weights={0,0.1,0.5,1}", 1, true), all)
	ok(all:find("[SQST] showcase_grow town Tacoma outside_streets=1 houses_outside=1 pass=1/2 buildings=57 houses_perimeter=0 zone_streets=0 inside_new=1 locked=1 failed=0", 1, true), all)
	ok(all:find("[SQST] showcase_grow town Tacoma outside_streets=1 houses_outside=2 pass=2/2 buildings=83 ", 1, true), all)
	ok(all:find("[SQST] showcase_grow town Tacoma outside_streets=0 houses_outside=2 final buildings=83 ", 1, true), all)
	ok(all:find("[SQST] showcase_grow town Tacoma levels 1:7 2:10 3:8 4:58 centre 1:5 2:5 3:6 4:57 buildings=83", 1, true), all)
	ok(all:find("[SQST] showcase_grow dense summary towns=1 factor=x10 passes=2 weights={0,0.1,0.5,1} sent=2 stoppedEarly=0 buildings 31->83 outside_streets=0 houses_outside=2 locked=2 levels 1:7 2:10 3:8 4:58", 1, true), all)
end)

test("densify: a pass adding too few buildings ends that town's build-out; no weights -> none sent", function()
	towns.densify("lights_showcase_grow", { W.area }, { factor = 10, passes = 3 })
	run(20)
	local kinds = {}
	for k, s in ipairs(sent) do kinds[k] = s.cmd.kind end
	eq(kinds, { "size", "build" }, "no weights; pass 1 gained nothing: done (its leak check locked the unlocked streets)")
	ok(logText():find("build-out done after pass 1", 1, true), logText())
	ok(logText():find(" stoppedEarly=1 ", 1, true), logText())
end)

test("the lock and density jobs are test jobs (Remove towns / roads and the other tests wait for them)", function()
	for _, j in ipairs({ "showcase_lock", "showcase_grow", "lights_showcase_lock", "lights_showcase_grow" }) do
		local hit = false
		for _, p in ipairs(rt.TEST_JOBS) do if j:sub(1, #p) == p then hit = true end end
		ok(hit, j)
	end
end)

test("lockTowns: every street in the town's junction zones is locked too, whatever town is closest (zone_streets)", function()
	-- a junction 3000 m east (its arm edge's closest town is town 2) and a street the town hung on it
	local arm = newEdge(newNode(2980, 0), newNode(3040, 0))
	local branch = newEdge(nodes[edges[arm].n1] and edges[arm].n1, newNode(3040, 150))
	local area = { town = 1, label = "Tacoma", x = 0, y = 0, half = 200, zones = { { 3000, 0, 60 } }, reach = 3000 }
	towns.lockTowns("showcase_lock", { area }, { pass = "links" })
	run(5)
	local removed = {}
	for _, sp in ipairs(builds()) do
		for _, e in ipairs(sp.edgesToRemove or {}) do removed[e] = true end
	end
	ok(removed[arm], "the junction's own arm is locked")
	ok(removed[branch], "the street on it too")
	ok(not removed[W.far], "a street of the other town outside the zone stays")
	ok(logText():find(" zone_streets=2 ", 1, true), logText())
	-- without zones the same streets are not the town's
	sent = {}
	clear_logs()
	local arm2 = newEdge(newNode(3980, 0), newNode(4040, 0))
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links" })
	run(5)
	for _, sp in ipairs(builds()) do
		for _, e in ipairs(sp.edgesToRemove or {}) do ok(e ~= arm2, "no zone: not locked") end
	end
end)

test("densify: houses along the outside of the perimeter street are counted apart (houses_perimeter)", function()
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(5)
	clear_logs()
	addHouse(1, 0, 0, 1)
	addHouse(1, 220, 0, 1)    -- 20 m outside the east street: the ring's outer parcels
	addHouse(1, -230, 50, 1)
	addHouse(1, 400, 0, 1)    -- beyond HOUSE_MARGIN: outside
	towns.densify("showcase_grow", { W.area }, { factor = 10, passes = 1 })
	run(20)
	ok(logText():find("houses_outside=1 final buildings=4 houses_perimeter=2 ", 1, true), logText())
end)

test("densify: a building's spot is its real box, else its construction's origin; an empty box at 0,0 is not a house outside (seed 530609)", function()
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(5)
	clear_logs()
	-- the area of a town far from the map's origin (as every Showcase town but one)
	local far = { town = W.area.town, label = W.area.label, x = 5000, y = 5000, half = W.area.half }
	addHouse(1, 5000, 5000, 1)                                          -- inside: box
	addHouse(1, 0, 0, 1, { 0, 0, 0, 0 }, { 5010, 4990 })                -- box not filled yet: the construction's origin, inside
	addHouse(1, 0, 0, 1, { 0, 0, 0, 0 }, nil)                           -- neither: unread, not counted
	addHouse(1, 0, 0, 1, { 5400, 5000, 5410, 5010 }, { 5020, 5000 })    -- box far from its construction: the origin, inside
	addHouse(1, 0, 0, 1, { 5300, 5000, 5310, 5010 }, { 5290, 5000 })    -- real box beyond the margin: outside
	towns.densify("showcase_grow", { far }, { factor = 10, passes = 1 })
	run(20)
	ok(logText():find("houses_outside=1 final buildings=5 houses_perimeter=0 ", 1, true), logText())
	ok(logText():find(" houses_unread=1 houses_pos=bbox:2,con:2,odd:1", 1, true), logText())
end)

test("housePos: box centre, construction origin, nothing", function()
	local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	local function hp(box, con) local p, f, o = logic.housePos(box, con) return { p, f, o } end
	eq(hp({ 10, 20, 30, 40 }, nil), { { 20, 30 }, "bbox", false })
	eq(hp({ 10, 20, 30, 40 }, { 25, 25 }), { { 20, 30 }, "bbox", false })
	eq(hp({ 0, 0, 0, 0 }, { 7, 8 }), { { 7, 8 }, "con", false })
	eq(hp({ 0, 0, 0, 0 }, { 0, 0 }), { nil, nil, false })
	eq(hp({ 1 / 0, 0, -1 / 0, 0 }, nil), { nil, nil, false })
	eq(hp({ 0 / 0, 0, 1, 1 }, { 3, 4 }), { { 3, 4 }, "con", false })
	eq(hp({ 1000, 0, 1010, 10 }, { 0.5, 0 }), { { 0.5, 0 }, "con", true })
	eq(hp(nil, nil), { nil, nil, false })
end)

test("lockTowns across towns: every town's streets in shared LOCK_BATCH proposals, one line per town with its own counts, every town's stubs in one removal, onDone(ms)", function()
	local area2 = { town = 2, label = "Seattle", x = 6000, y = 0, half = 200 }
	local doneMs
	towns.lockTowns("lights_showcase_lock", { W.area, area2 }, { pass = "links", stubs = true, onDone = function(ms) doneMs = ms end })
	run(5)
	local bs = builds()
	eq(#bs, 2, "one lock proposal for both towns, one stub removal")
	local removed = {}
	for _, e in ipairs(bs[1].edgesToRemove) do removed[e] = true end
	eq(removed, { [W.seed1] = true, [W.seed2] = true, [W.leak1] = true, [W.leak2] = true, [W.far] = true }, "both towns' streets together")
	eq(problems(bs[1]), {})
	eq(bs[2].edgesToAdd, nil)
	eq(#bs[2].edgesToRemove, 3, "town 1's three unused stubs")
	local all = logText()
	ok(all:find("[SQST] lights_showcase_lock town Tacoma lock pass=links edges=", 1, true), all)
	ok(all:find(" unlocked=4 inside=3 outside_streets=2 zone_streets=0 locked=4 refused=0 failed=0 batches=1 objects=1 left=0 stubs=3 removed=3", 1, true), all)
	ok(all:find("[SQST] lights_showcase_lock town Seattle lock pass=links edges=1 unlocked=1 inside=1 outside_streets=0 zone_streets=0 locked=1 refused=0 failed=0 batches=1 objects=0 left=0 stubs=0 removed=0", 1, true), all)
	ok(all:find("[SQST] lights_showcase_lock summary pass=links towns=2 locked=5 failed=0 stubs_removed=3 stubs_kept=0 outside_streets=2 edges=5 batches=1 ms=", 1, true), all)
	ok(doneMs ~= nil and doneMs >= 0, "onDone with the ms")
	ok(all:find("[SQST] action=lights_showcase_lock count=1", 1, true), all)
end)

test("lockTowns across towns: a refused shared stub removal is sent again one town at a time", function()
	-- town 2 gets an unused corner stub of its own too
	local c2 = newNode(6200, 200)
	newEdge(newNode(6000, 200), c2, true)
	newEdge(c2, newNode(6200, 0), true)
	local o2 = newNode(6200 + 42.43, 200 + 42.43)
	local stub2 = newEdge(c2, o2, true)
	local area2 = { town = 2, label = "Seattle", x = 6000, y = 0, half = 200 }
	refuse = function(cmd)
		local sp = cmd.p.streetProposal
		return sp.edgesToAdd == nil and #sp.edgesToRemove == 4   -- both towns' stubs together
	end
	towns.lockTowns("showcase_lock", { W.area, area2 }, { pass = "links", stubs = true })
	run(10)
	local bs = builds()
	eq(#bs, 4, "lock, the shared removal (refused), then each town's own")
	eq(#bs[3].edgesToRemove, 3)
	eq(bs[4].edgesToRemove, { stub2 })
	local all = logText()
	ok(all:find("town Tacoma, Seattle: removing 4 corner stubs was refused", 1, true), all)
	ok(all:find(" stubs=3 removed=3", 1, true) and all:find(" stubs=1 removed=1", 1, true), all)
end)

test("densify with one pass (Lights showcase): weights, one size command per town, no leak check in between, the final check", function()
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(5)
	sent = {}
	clear_logs()
	local doneMs
	towns_[W.area.town].pop = 987
	towns.densify("lights_showcase_grow", { W.area }, { factor = 10, passes = 1, weights = logic.DENSE_WEIGHTS, onDone = function(ms) doneMs = ms end })
	run(20, function()
		newEdge(newNode(-200, 50), newNode(-320, 50))   -- the town grew a street out of its grid
	end)
	local kinds = {}
	for k, s in ipairs(sent) do kinds[k] = s.cmd.kind end
	eq(kinds, { "weights", "size", "build" }, "the only lock is the final check's")
	local all = logText()
	ok(not all:find("pass=1/1 buildings=", 1, true), "no leak line for the pass")
	ok(all:find("[SQST] lights_showcase_grow town Tacoma outside_streets=1 houses_outside=0 final buildings=", 1, true), all)
	ok(all:find("[SQST] lights_showcase_grow dense summary towns=1 factor=x10 passes=1 ", 1, true), all)
	-- the population (residential capacity) at the final check and the summary's (the pass line has it too: detail log)
	ok(all:find("%[SQST%] lights_showcase_grow town Tacoma levels [^\n]* buildings=%d+ pop=987") ~= nil, all)
	ok(all:find(" pop min/mean/max=987/987/987 (1 of 1 towns read)", 1, true), all)
	ok(doneMs ~= nil)
end)

test("lockEdgeList: edges already locked count as locked (the entry ring's highway template is initiallyLocked), only the rest are swapped", function()
	local a, b, c, d = newNode(0, 0), newNode(20, 0), newNode(40, 0), newNode(60, 0)
	local l1, l2 = newEdge(a, b, true), newEdge(b, c, true)
	local u1 = newEdge(c, d)
	sent = {}
	local res
	towns.lockEdgeList("lights_showcase", "Tacoma entry", { l1, l2, u1 }, function(locked, failed, already) res = { locked, failed, already } end)
	run(10)
	eq(res, { 3, 0, 2 })
	local swapped = 0
	for _, s in ipairs(sent) do
		local sp = s.cmd.p and s.cmd.p.streetProposal
		if sp and sp.edgesToRemove then
			for _, e in ipairs(sp.edgesToRemove) do
				ok(e == u1, "only the unlocked edge swapped")
				swapped = swapped + 1
			end
		end
	end
	eq(swapped, 1)
end)

test("densify with a target: each town's size factors x (target / its capacity target: initial capacity x size factor), logged; unreadable: the fallback factor", function()
	towns.lockTowns("showcase_lock", { W.area }, { pass = "links", stubs = true })
	run(5)
	sent = {}
	clear_logs()
	towns_[W.area.town].pop = 180
	towns_[W.area.town].initCaps = { 250, 250, 250 }
	towns.densify("lights_showcase_grow", { W.area }, { factor = 1.0, target = 400, passes = 1, weights = logic.DENSE_WEIGHTS })
	run(20)
	local size
	for _, s in ipairs(sent) do if s.cmd.kind == "size" then size = s.cmd end end
	ok(size, "a size command")
	eq(size.f, { 1.6, 1.6, 1.6 }, "400 / 250, whatever its 180 people now")
	local all = logText()
	ok(all:find("queued towns=1 factor=x1 passes=1 weights={0,0.1,0.5,1} (level 1..4, every land use) target=400 (each town: target / its capacity target)", 1, true), all)
	-- no capacity readable: the fallback factor
	sent = {}
	clear_logs()
	towns_[W.area.town].initCaps = nil
	towns_[W.area.town].sizeFactors = { 1, 1, 1 }
	towns.densify("lights_showcase_grow", { W.area }, { factor = 1.25, target = 400, passes = 1, weights = logic.DENSE_WEIGHTS })
	run(20)
	size = nil
	for _, s in ipairs(sent) do if s.cmd.kind == "size" then size = s.cmd end end
	eq(size.f, { 1.25, 1.25, 1.25 })
end)
