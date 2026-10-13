-- stress_buslines.tl: the pure helpers (Hermite point, edge pair selection, depot retry spots, town pick,
-- labels), the depot builder's retry loop and lookup against a fake api, and Auto bus lines end to end:
-- one command in flight at a time, per-town failure handling, the 3-failed-towns stop, money, removal.

local T = 0
local W            -- the fake world (see fakeApi)

local function edgeGeo(id, x0, y0, x1, y1, dist)
	local p0, p1 = { x0, y0, 0 }, { x1, y1, 0 }
	local t = { x1 - x0, y1 - y0, 0 }
	return { id = id, node0 = id * 10, node1 = id * 10 + 1, p0 = p0, p1 = p1, t0 = t, t1 = t,
		mid = { (x0 + x1) / 2, (y0 + y1) / 2, 0 }, dmid = t, length = math.sqrt(t[1] ^ 2 + t[2] ^ 2), dist = dist or 0 }
end

-- A world of towns, each with a straight row of street edges along +x through its centre (100 m each,
-- ten per town), plus whatever a test adds. Commands go through W.answer(cmd) -> success, data, res;
-- callbacks are held in W.pending and answered by pump() one at a time (W.maxInFlight records the most
-- commands ever waiting at once).
local function fakeApi()
	W = { towns = {}, edges = {}, nodes = {}, groups = {}, depots = {}, sent = {}, pending = {}, maxInFlight = 0,
		nextId = 5000, exists = {}, removed = {}, balance = 1e9, price = 1000, keepNoCosts = false, best = 800, built = {},
		kind = {}, onLine = {}, moving = {}, lineNames = {} }
	function W.addTown(id, x, y)
		W.towns[#W.towns + 1] = { existing = id, pos = { x = x, y = y } }
		for k = 0, 9 do
			local e = id * 100 + k
			local x0 = x - 500 + k * 100
			W.edges[e] = { node0 = e * 10, node1 = e * 10 + 1, objects = {}, x0 = x0, y = y, town = id }
			W.nodes[e * 10] = { x = x0, y = y }
			W.nodes[e * 10 + 1] = { x = x0 + 100, y = y }
		end
		W.depots[800 + id] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { x, y + 50 } }   -- a depot in every town
	end
	W.depots[800] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 0, 50 } }
	function W.answer(cmd)
		if cmd.kind == "build" then
			local sp = cmd.proposal.streetProposal or {}
			if sp.edgeObjectsToAdd and #sp.edgeObjectsToAdd > 0 then
				if W.stopFails and W.stopFails(sp.edgesToRemove[1]) then return false, {}, {} end
				W.edges[sp.edgesToRemove[1]].objects = { 1 }
				W.nextId = W.nextId + 1
				W.groups[#W.groups + 1] = W.nextId
				return true, {}, {}
			end
			return true, {}, {}
		elseif cmd.kind == "line" then
			W.nextId = W.nextId + 1
			W.exists[W.nextId] = true
			W.kind[W.nextId] = "line"
			W.lineNames[W.nextId] = cmd.name
			return true, {}, { { W.nextId, 1 } }
		elseif cmd.kind == "buy" then
			if W.buyFails then return false, {}, {} end
			W.nextId = W.nextId + 1
			W.exists[W.nextId] = true
			W.kind[W.nextId] = W.buyKind or "vehicle"
			return true, { resultVehicleEntity = W.nextId }, {}
		elseif cmd.kind == "setLine" then
			W.onLine[cmd.v] = cmd.line
			return true, {}, {}
		elseif cmd.kind == "sell" then
			if W.sellFails then return false, {}, {} end
			for _, v in ipairs(cmd.vs) do W.removed[v] = true W.onLine[v] = nil end
			return true, {}, {}
		elseif cmd.kind == "destroyLine" then
			W.removed[cmd.line] = true
			return true, {}, {}
		end
		return true, {}, {}
	end
	local CT = setmetatable({}, { __index = function(_, k) return k end })
	local function getComponent(e, ct)
		local ed = W.edges[e]
		if ed and ct == "BASE_EDGE" then
			return { node0 = ed.node0, node1 = ed.node1, objects = ed.objects, roadTemplate = ed.template,
				tangent0 = { x = 100, y = 0, z = 0 }, tangent1 = { x = 100, y = 0, z = 0 } }
		end
		if ed and ct == "BASE_EDGE_STREET" then return {} end
		local n = W.nodes[e]
		if n and ct == "BASE_NODE" then return { position = { x = n.x, y = n.y, z = 0 } } end
		local d = W.depots[e]
		if d and ct == "VEHICLE_DEPOT" then return d end
		if d and d.pos and ct == "BOUNDING_VOLUME" then
			return { bbox = { min = { x = d.pos[1], y = d.pos[2], z = 0 }, max = { x = d.pos[1], y = d.pos[2], z = 0 } } }
		end
		if ct == "TRANSPORT_VEHICLE" and W.kind[e] == "vehicle" and not W.removed[e] then return { transportVehicleConfig = {} } end
		if ct == "LINE" and W.kind[e] == "line" and not W.removed[e] then return { stops = {} } end
		if ct == "GAME_TIME" then return { gameTime = 100 } end
		if W.extraComp then return W.extraComp(e, ct) end
		return nil
	end
	return {
		type = {
			Clock = { new = function() return { getTime = function() T = T + 1000 return T end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Vec4f = { new = function(x, y, z, w) return { x, y, z, w } end },
			Mat4f = { new = function(c1, c2, c3, c4) return { c1, c2, c3, c4 } end },
			ComponentType = CT,
			enum = { EdgeObjectType = { STOP_LEFT = 0, STOP_RIGHT = 1 }, Carrier = { ROAD = 0, RAIL = 1 },
				TransportMode = { CAR = 2, BUS = 3, TRUCK = 4, TRAIN = 7 } },
			SimpleProposal = { new = function() return { streetProposal = {} } end,
				ConstructionEntity = { new = function() return {} end } },
			SimpleStreetProposal = { EdgeObject = { new = function() return {} end } },
			SegmentAndEntity = { new = function() return { comp = {} } end },
			NodeAndEntity = { new = function() return { comp = {} } end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			Line = { new = function() return {} end, Stop = { new = function() return {} end } },
			TransportVehiclePart = { new = function() return { part = {} } end },
			LoadConfig = { new = function() return {} end },
			TransportVehicleConfig = { new = function(c) return c and { vehicles = c.vehicles, copied = true } or {} end },
		},
		gui = { camera = { getCameraData = function() return { x = 0, y = 0 } end } },
		res = {
			getBaseConfig = function() return { noCosts = W.keepNoCosts } end,
			modelRep = {
				forEachModelWithMetadata = function(_k, fn) if not W.noBus then fn("bus.mdl") end end,
				find = function() return 1 end,
				get = function() return { metadata = { transportVehicle = { carrier = 0, transportModes = { 3 }, filterTags = { "default" },
					compartments = { {} } }, availability = { yearFrom = 1950, yearTo = 0 } } } end,
			},
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p) return { kind = "build", proposal = p } end,
			makeLineCreateCmd = function(name, _c, _p, line) return { kind = "line", name = name, line = line } end,
			makeLineDestroyCmd = function(line) return { kind = "destroyLine", line = line } end,
			makeVehicleBuyCmd = function(_p, depot, cfg) return { kind = "buy", depot = depot, cfg = cfg } end,
			makeVehicleSetLineCmd = function(v, line, stop) return { kind = "setLine", v = v, line = line, stop = stop } end,
			makeVehicleSellCmd = function(vs) return { kind = "sell", vs = vs } end,
			sendCommand = function(cmd, cb)
				W.sent[#W.sent + 1] = cmd
				W.pending[#W.pending + 1] = { cmd = cmd, cb = cb }
				if #W.pending > W.maxInFlight then W.maxInFlight = #W.pending end
			end,
		},
		engine = {
			getComponent = getComponent,
			entityExists = function(e) return not W.removed[e] end,
			getEntitiesWithComponent = function(ct)
				if ct == "STATION_GROUP" then return W.groups end
				if ct == "VEHICLE_DEPOT" then
					local out = {}
					for d in pairs(W.depots) do out[#out + 1] = d end
					table.sort(out)
					return out
				end
				return {}
			end,
			terrain = { getHeightAt = function() return 0 end, makeMapFromGame = function() return { towns = W.towns } end },
			util = {
				getPlayer = function() return 7 end,
				getWorld = function() return 1 end,
				getYear = function() return 2000 end,
				getEntityName = function(e) return W.lineNames[e] or ("Town" .. e) end,
				finance = { getPlayersBalance = function() return W.balance end },
				town = { getClosestTown = function(p)
					local best, bd
					for _, t in ipairs(W.towns) do
						local d = (t.pos.x - p.x) ^ 2 + (t.pos.y - p.y) ^ 2
						if not bd or d < bd then best, bd = t.existing, d end
					end
					return best or -1
				end },
				octree = { findEntitiesInCircle = function(c, r, ct)
					local out = {}
					if ct == "BASE_EDGE" then
						for e, ed in pairs(W.edges) do
							local mx = ed.x0 + 50
							if (mx - c.x) ^ 2 + (ed.y - c.y) ^ 2 <= r * r then out[#out + 1] = e end
						end
						table.sort(out)
					elseif ct == "TOWN_BUILDING" then
						out = { 1 }
					end
					return out
				end },
				vehicle = {
					getPartPrice = function() return W.price end,
					findBestDepotForLine = function() return W.best end,
				},
			},
			system = {
				streetConnectorSystem = {
					getConstructionEntityForEdge = function() return -1 end,
					getConstructionEntityForDepot = function() return -1 end,
				},
				lineSystem = { getLinesForPlayer = function() return {} end },
				transportVehicleSystem = { getLineVehicles = function(line)
					local out = {}
					for v, l in pairs(W.onLine) do if l == line and not W.removed[v] then out[#out + 1] = v end end
					table.sort(out)
					return out
				end },
				simPersonSystem = { getSimPersonsMovingForTransportNetwork = function(e) return W.moving[e] or {} end },
			},
		},
	}
end

local rt, bl, logic
before_each(function()
	T = 0
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	bl = ug_require "square_stress_test::/stress/gui/stress_buslines.tl"
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
end)

--- Ticks the queue and answers the oldest pending command each round until the queue is empty.
local function pump(maxRounds)
	for _ = 1, maxRounds or 200000 do
		rt.tick()
		local p = table.remove(W.pending, 1)
		if p then
			local success, data, res = W.answer(p.cmd)
			p.cb(data, success, res)
		elseif #rt.queue.jobs == 0 then
			return
		end
	end
	error("queue never emptied: " .. logic.progress(rt.queue))
end

local function logText()
	local parts = {}
	for _, e in ipairs(log_entries()) do parts[#parts + 1] = e.msg end
	return table.concat(parts, "\n")
end

local function kinds()
	local out = {}
	for _, c in ipairs(W.sent) do
		local k = c.kind
		if k == "build" then
			local p = c.proposal
			k = p.constructionsToAdd and "depot" or (p.streetProposal.edgeObjectsToAdd and "stop" or "street")
		end
		out[#out + 1] = k
	end
	return table.concat(out, ",")
end

-- Pure helpers ---------------------------------------------------------------------------------------

test("hermiteAt: ends, middle and derivative of a straight edge; z0 turns -0 into +0", function()
	local p0, t0, p1, t1 = { 0, 0, 0 }, { 100, 0, 0 }, { 100, 0, 0 }, { 100, 0, 0 }
	local p, d = bl.hermiteAt(p0, t0, p1, t1, 0)
	eq(p, { 0, 0, 0 })
	eq(d, { 100, 0, 0 })
	p, d = bl.hermiteAt(p0, t0, p1, t1, 0.25)
	near(p[1], 25)
	near(d[1], 100)
	p = bl.hermiteAt(p0, t0, p1, t1, 1)
	near(p[1], 100)
	eq(1 / bl.z0(-0.0), math.huge)
	eq(bl.z0(3), 3)
end)

test("pickEdgePair: nearest first, partner within the range, avoid points and tries respected", function()
	local cands = {
		edgeGeo(1, 0, 0, 40, 0, 1),        -- mid 20,0
		edgeGeo(2, 100, 0, 140, 0, 2),     -- mid 120
		edgeGeo(3, 400, 0, 440, 0, 3),     -- mid 420: 400 m from edge 1
		edgeGeo(4, 900, 0, 940, 0, 4),     -- mid 920
	}
	local a, b = bl.pickEdgePair(cands, 300, 800, {}, 0, 30)
	eq({ a.id, b.id }, { 1, 3 })
	-- a stop near edge 1 already: edge 2 pairs with 3 (300 m)
	a, b = bl.pickEdgePair(cands, 300, 800, { { 20, 0 } }, 100, 30)
	eq({ a.id, b.id }, { 2, 3 })
	-- only the first edge may start a pair, and nothing in range for it
	a, b = bl.pickEdgePair(cands, 500, 800, {}, 0, 1)
	eq(a, nil)
	a, b = bl.pickEdgePair(cands, 500, 800, {}, 0, 3)
	eq({ a.id, b.id }, { 2, 4 })
	eq(bl.pickEdgePair({}, 300, 800, {}, 0, 30), nil)
end)

test("depotTries: per edge, gaps nearest first, params 0.5/0.25/0.75, right then left; no -0; short pieces left out", function()
	local g = edgeGeo(50, 0, 0, 100, 0)
	local tries = bl.depotTries({ g }, { 30, 45, 60 }, { 0.5, 0.25, 0.75 })
	eq(#tries, 18)
	eq(bl.tryText(tries[1]), "e50 t=0.50 R30")
	eq(bl.tryText(tries[2]), "e50 t=0.50 L30")
	eq(bl.tryText(tries[3]), "e50 t=0.25 R30")
	eq(bl.tryText(tries[7]), "e50 t=0.50 R45")
	eq(bl.tryText(tries[18]), "e50 t=0.75 L60")
	-- edge along +x: right is -y, left +y; the entrance sits gap metres off the street point
	eq(tries[1].n, { 0, -1 })
	eq(tries[2].n, { 0, 1 })
	eq(1 / tries[1].n[1], math.huge, "right normal x is +0")
	eq(1 / tries[2].n[1], math.huge, "left normal x is +0")
	near(tries[1].entrance[1], 50)
	near(tries[1].entrance[2], -30)
	near(tries[3].entrance[1], 25)
	-- a 40 m edge: 0.25 / 0.75 leave a 10 m piece (< 12 m), only 0.5 stays
	local short = bl.depotTries({ edgeGeo(51, 0, 0, 40, 0) }, { 30 }, { 0.5, 0.25, 0.75 })
	eq(#short, 2)
	eq(bl.tryText(short[1]), "e51 t=0.50 R30")
	-- two edges: all spots of the first edge come first
	local two = bl.depotTries({ g, edgeGeo(52, 0, 0, 0, 100) }, { 30 }, { 0.5 })
	eq(#two, 4)
	eq(two[3].edge.id, 52)
	eq(two[3].n, { 1, 0 })   -- edge along +y: right is +x
end)

test("busTownPick and busLinesLabel", function()
	local towns = { { id = 3, x = 1000, y = 0 }, { id = 1, x = 10, y = 0 }, { id = 2, x = -300, y = 0 } }
	local function ids(l) local o = {} for i, t in ipairs(l) do o[i] = t.id end return o end
	eq(ids(logic.busTownPick(towns, 0, 0, 1)), { 1 })
	eq(ids(logic.busTownPick(towns, 0, 0, 2)), { 1, 2, 3 })
	local many = {}
	for i = 1, 40 do many[i] = { id = i, x = i * 10, y = 0 } end
	eq(#logic.busTownPick(many, 0, 0, 3), 25)
	eq(#logic.busTownPick({}, 0, 0, 3), 0)
	eq(logic.busLinesLabel(1, 1), "Add 1 bus line to the nearest town")
	eq(logic.busLinesLabel(2, 2), "Add 2 bus lines each to 5 towns")
	eq(logic.busLinesLabel(3, 4), "Add 4 bus lines each to all towns (max 25)")
	eq(logic.BUS_LINES_PER_TOWN, { 1, 2, 4 })
	eq(logic.BUSES_PER_LINE, { 2, 5, 10 })
end)

-- Depot lookup and building --------------------------------------------------------------------------

test("nearestRoadDepot: road by transportModes or carrier, position from the construction or bounding volume, nodes preferred", function()
	W.depots = {
		[801] = { transportModes = { [3] = true } },                        -- bus mode, no carrier field
		[802] = { carrier = 1, transportModes = { [7] = true } },           -- rail
		[803] = { carrier = 0, inNodes = {}, outNodes = {} },               -- road, no nodes, nearer
		[804] = { carrier = 0, inNodes = { {} }, outNodes = {} },           -- road with nodes, far
	}
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 801 and 901 or -1 end
	W.extraComp = function(e, ct)
		if e == 901 and ct == "CONSTRUCTION" then return { transf = { [13] = 30, [14] = 40, [15] = 0 } } end
		if ct == "BOUNDING_VOLUME" then
			local x = ({ [802] = 10, [803] = 20, [804] = 900 })[e]
			if x then return { bbox = { min = { x = x - 5, y = -5, z = 0 }, max = { x = x + 5, y = 5, z = 10 } } } end
		end
	end
	local d, dist, info = bl.nearestRoadDepot(0, 0, 1500)
	eq(d, 804)
	near(dist, 900)
	ok(info:find("depots=4 road=3 withPos=4", 1, true) ~= nil, info)
	ok(info:find("801:road/modes/50m/nodes=false", 1, true) ~= nil, info)
	ok(info:find("802:notRoad/carrier=1/10m", 1, true) ~= nil, info)
	-- out of range for the one with nodes: the nearest road depot without nodes
	d = bl.nearestRoadDepot(0, 0, 500)
	eq(d, 803)
	eq(bl.depotPos(801), { 30, 40, 0 })
	local p, src = bl.depotPos(803)
	eq({ p[1], src }, { 20, "bbox" })
end)

test("buildDepot skips spots whose pre-check reports a collision, sends the first clean one, maps the new depot to its construction and connects it", function()
	local g = edgeGeo(50, 0, 0, 100, 0)
	W.edges[50] = { node0 = 500, node1 = 501, objects = {}, x0 = 0, y = 0 }
	W.nodes[500], W.nodes[501] = { x = 0, y = 0 }, { x = 100, y = 0 }
	W.depots = {}
	local checks = 0
	api.engine.util.proposal = { makeProposalData = function(p)
		checks = checks + 1
		if p.constructionsToAdd and checks <= 5 then return { errorState = { critical = false, messages = { "Collision" } } } end
		return { errorState = { critical = false, messages = {} } }
	end }
	local node2edges = { [10] = { 60 } }
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return node2edges end }
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 811 and 700 or -1 end
	W.extraComp = function(e, ct)
		if e == 700 and ct == "CONSTRUCTION" then
			return { frozenNodes = { 11 }, frozenEdges = { 60 }, transf = { [13] = 50, [14] = 65, [15] = 0 } }
		end
		if e == 60 and ct == "BASE_EDGE" then return { node0 = 10, node1 = 11 } end
		if e == 10 and ct == "BASE_NODE" then return { position = { x = 50, y = 30, z = 0 } } end
		if e == 11 and ct == "BASE_NODE" then return { position = { x = 50, y = 44.7, z = 0 } } end
	end
	W.answer = function(cmd)
		if cmd.proposal.constructionsToAdd then
			W.depots[810] = { carrier = 0 }                         -- a second, unrelated new depot
			W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			return true, {}, { { 10438, 1 } }
		end
		node2edges[10] = { 60, 61 }
		return true, {}, {}
	end
	local result
	bl.buildDepot("dep", { g }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	ok(result ~= nil, "onDone called")
	ok(result[1], result[2])
	eq(result[3], 811)
	eq(kinds(), "depot,street")
	-- spots 1-5 collided (right/left at 0.5, right/left at 0.25, right at 0.75); spot 6 = left at 0.75
	ok(result[2]:find("spots=24 tried=6 pre={Collision=5,ok=1} sent=1 [e50 t=0.75 L30", 1, true) ~= nil, result[2])
	ok(result[2]:find("new=[810(con=nil noPos nodes=false) 811(con=700", 1, true) ~= nil, result[2])
	ok(result[2]:find("depot=811 construction=700", 1, true) ~= nil, result[2])
	ok(result[2]:find("connected=true", 1, true) ~= nil, result[2])
	eq(bl.depots, { 811 })
	-- the connection splits the edge at the spot's param (0.75)
	local sp = W.sent[2].proposal.streetProposal
	eq(sp.nodesToAdd[1].comp.position, { x = 75, y = 0, z = 0 })
	eq(sp.edgesToAdd[3].comp.node1, 10)
	eq(W.maxInFlight, 1)
end)

test("buildDepot: refused builds move on to the next spot and give up after DEPOT_MAX_SENDS; nothing clean = no spot left", function()
	local g = edgeGeo(50, 0, 0, 100, 0)
	W.edges[50] = { node0 = 500, node1 = 501, objects = {}, x0 = 0, y = 0 }
	W.nodes[500], W.nodes[501] = { x = 0, y = 0 }, { x = 100, y = 0 }
	W.answer = function() return false, { resultProposalData = { errorState = { critical = true, messages = {} }, costs = 0 } }, {} end
	local result
	bl.buildDepot("dep", { g }, 0, 0, function(ok_, details) result = { ok_, details } end)
	pump()
	eq(result[1], false)
	eq(#W.sent, bl.DEPOT_MAX_SENDS)
	ok(result[2]:find("pre={unavailable=6} sent=6", 1, true) ~= nil, result[2])
	ok(result[2]:find("gave up after 6 build commands", 1, true) ~= nil, result[2])
	ok(result[2]:find("success=false critical=true", 1, true) ~= nil, result[2])
	-- every spot collides in the pre-check: nothing is sent
	W.sent = {}
	api.engine.util.proposal = { makeProposalData = function() return { errorState = { critical = true, messages = { "Collision" } } } end }
	bl.buildDepot("dep2", { g }, 0, 0, function(ok_, details) result = { ok_, details } end)
	pump()
	eq(result[1], false)
	eq(#W.sent, 0)
	ok(result[2]:find("tried=24 pre={Collision=24} sent=0", 1, true) ~= nil, result[2])
	ok(result[2]:find("no spot left", 1, true) ~= nil, result[2])
end)

-- Auto bus lines -------------------------------------------------------------------------------------

test("auto bus lines: per town 2 stops, a line, the best depot and N buses, strictly one command in flight", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 2, 1, 1   -- 5 nearest (2 exist), 1 line, 2 buses
	bl.addBusLines()
	pump()
	eq(W.maxInFlight, 1)
	eq(kinds(), "stop,stop,line,buy,setLine,buy,setLine,stop,stop,line,buy,setLine,buy,setLine")
	eq(#bl.lines, 2)
	eq(#bl.vehicles, 4)
	-- stops 300-800 m apart within each town; the buses are bought at findBestDepotForLine's depot
	local s1, s2 = W.sent[1].proposal.streetProposal.edgesToRemove[1], W.sent[2].proposal.streetProposal.edgesToRemove[1]
	local d = math.abs(W.edges[s1].x0 - W.edges[s2].x0)
	ok(d >= 300 and d <= 800, "stop distance " .. d)
	eq(W.edges[s1].town, 1)
	eq(W.sent[4].depot, 800)
	eq({ W.sent[5].line, W.sent[5].stop }, { bl.lines[1], 0 })
	eq(#W.sent[3].line.stops, 2)
	local text = logText()
	ok(text:find("[SQST] bus_lines: 2 towns x 1 lines x 2 buses (2 lines)", 1, true) ~= nil, text)
	ok(text:find("[SQST] bus_lines town Town1 (1): 1 lines ok", 1, true) ~= nil, text)
	ok(text:find("bus_lines 1/2 Town1 ok", 1, true) ~= nil, text)
	ok(text:find("buses from depot=800 (findBestDepotForLine=800) buses=2/2", 1, true) ~= nil, text)
	ok(text:find("depot=801 (existing, 50m)", 1, true) ~= nil, text)
	ok(text:find("bus_lines summary towns=2 ok=2 failed=0 lines=2 (complete 2) buses=4", 1, true) ~= nil, text)
	ok(text:find("[SQST] action=bus_lines count=2", 1, true) ~= nil, text)
end)

test("auto bus lines: two lines per town use different streets (no stop near an earlier one)", function()
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 2, 1
	bl.addBusLines()
	pump()
	eq(#bl.lines, 2)
	local stops = {}
	for _, c in ipairs(W.sent) do
		if c.kind == "build" and c.proposal.streetProposal.edgeObjectsToAdd then stops[#stops + 1] = c.proposal.streetProposal.edgesToRemove[1] end
	end
	eq(#stops, 4)
	local seen = {}
	for _, e in ipairs(stops) do ok(not seen[e], "edge used twice: " .. e) seen[e] = true end
end)

test("auto bus lines: no depot near the town builds one FIRST (ring 300-700 m), then stops and line; the next line reuses it", function()
	W.addTown(1, 0, 0)
	W.depots = {}
	-- findBestDepotForLine finds the depot once it is built
	api.engine.util.vehicle.findBestDepotForLine = function() return W.depots[811] and 811 or -1 end
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return { [10] = { 60, 61 } } end }
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 811 and 700 or -1 end
	W.extraComp = function(e, ct)
		if e == 700 and ct == "CONSTRUCTION" then return { frozenNodes = { 11 }, frozenEdges = { 60 }, transf = { [13] = 450, [14] = -65, [15] = 0 } } end
		if e == 60 and ct == "BASE_EDGE" then return { node0 = 10, node1 = 11 } end
		if e == 10 and ct == "BASE_NODE" then return { position = { x = 450, y = -30, z = 0 } } end
	end
	local base = W.answer
	W.answer = function(cmd)
		if cmd.kind == "build" and cmd.proposal.constructionsToAdd then
			W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			return true, {}, {}
		end
		return base(cmd)
	end
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 2, 1
	bl.addBusLines()
	pump()
	-- the depot exists already when the connection is checked (2 street edges at its node): no stub needed
	eq(kinds(), "depot,stop,stop,line,buy,setLine,buy,setLine,stop,stop,line,buy,setLine,buy,setLine")
	eq(W.sent[5].depot, 811)
	eq(W.sent[12].depot, 811)
	-- the depot's spot is on an edge of the first ring (middle 300-700 m from the centre), nearest first
	local ce = W.sent[1].proposal.constructionsToAdd[1]
	local x = ce.transf[4][1]
	ok(math.abs(x) >= 300 and math.abs(x) <= 700, "depot in the 300-700 m ring: x=" .. x)
	local text = logText()
	ok(text:find("depot=811 (built in ring 300-700m)", 1, true) ~= nil, text)
	ok(text:find("depot rings: 300-700m inRing=4 edges=4 spots=", 1, true) ~= nil, text)
end)

test("auto bus lines: a town stops at its first failure, the batch goes on, and stops after 3 failed towns in a row", function()
	for i = 1, 5 do W.addTown(i, (i - 1) * 5000, 0) end
	W.stopFails = function(edge) return math.floor(edge / 100) <= 4 end   -- towns 1-4: stops refused
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 2, 2, 1
	bl.addBusLines()
	pump()
	local text = logText()
	-- each failed town sends stop variant A and B once, then moves on; towns 4 and 5 are never tried
	eq(kinds(), "stop,stop,stop,stop,stop,stop")
	ok(text:find("town Town1 (1) failed after 0 lines: line 1: edges", 1, true) ~= nil, text)
	ok(text:find("(3/3 failed towns in a row)", 1, true) ~= nil, text)
	ok(text:find("bus_lines stopped after 3 failed towns in a row", 1, true) ~= nil, text)
	ok(text:find("summary towns=5 ok=0 failed=3 lines=0 (complete 0) buses=0", 1, true) ~= nil, text)
	ok(text:find("stopped: 3 failed towns in a row", 1, true) ~= nil, text)
	eq(#bl.lines, 0)
end)

test("auto bus lines: a failed buy after the first bus fails the town but keeps the line (it has a bus); a later good town resets the count", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	local buys = 0
	local base = W.answer
	W.answer = function(cmd)
		if cmd.kind == "buy" then
			buys = buys + 1
			if buys == 2 then return false, {}, {} end
		end
		return base(cmd)
	end
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 2, 1, 1
	bl.addBusLines()
	pump()
	local text = logText()
	ok(text:find("town Town1 (1) failed after 0 lines:", 1, true) ~= nil, text)
	ok(text:find("buses=1/2 | buy 2/2 failed at depot 800", 1, true) ~= nil, text)
	ok(text:find("town Town2 (2): 1 lines ok", 1, true) ~= nil, text)
	ok(text:find("summary towns=2 ok=1 failed=1 lines=2 (complete 1) buses=3", 1, true) ~= nil, text)
	eq(#bl.lines, 2)
end)

test("auto bus lines: without Keep balance a low balance stops the batch before a line; an unaffordable bus fails the town", function()
	W.addTown(1, 0, 0)
	W.balance = 500000
	bl.addBusLines()
	pump()
	eq(#W.sent, 0)
	ok(logText():find("bus_lines stopped: balance 500k below 1M; tick Keep balance or add money", 1, true) ~= nil, logText())
	clear_logs()
	W.balance, W.price = 2e6, 5e6
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	ok(logText():find("buses=0/2 | balance 2M can't pay the next bus (5M)", 1, true) ~= nil, logText())
	-- Keep balance on: no money checks
	clear_logs()
	rt.keepBalance = true
	W.balance = 0
	bl.addBusLines()
	pump()
	ok(logText():find("1 lines ok", 1, true) ~= nil, logText())
end)

test("auto bus lines: no bus on sale copies one of your buses; none at all stops the batch", function()
	W.addTown(1, 0, 0)
	W.noBus = true
	bl.addBusLines()
	pump()
	eq(#W.sent, 0)
	ok(logText():find("stopped: no bus model on sale and no bus to copy", 1, true) ~= nil, logText())
	clear_logs()
	api.engine.system.lineSystem.getLinesForPlayer = function() return { 70 } end
	api.engine.system.transportVehicleSystem = { getLineVehicles = function() return { 71 } end }
	W.extraComp = function(e, ct)
		if e == 71 and ct == "TRANSPORT_VEHICLE" then
			return { transportVehicleConfig = { vehicles = { { part = { modelId = 1, compartment2loadConfig = { 0 } } } } } }
		end
	end
	bl.addBusLines()
	pump()
	ok(logText():find("1 lines ok", 1, true) ~= nil, logText())
	local buy
	for _, c in ipairs(W.sent) do if c.kind == "buy" then buy = c break end end
	ok(buy.cfg.copied, "config copied from the existing bus")
	eq(buy.cfg.vehicles[1].autoLoadConfig, { true })
end)

test("remove added bus lines: sells the buses first, then deletes the lines, one at a time; nothing added = one line", function()
	bl.removeAdded()
	pump()
	ok(logText():find("remove_bus_lines: no bus lines added in this session", 1, true) ~= nil, logText())
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(#bl.lines, 1)
	eq(#bl.vehicles, 2)
	local line = bl.lines[1]
	W.sent, W.maxInFlight = {}, 0
	clear_logs()
	W.removed[bl.vehicles[2]] = true   -- sold by hand meanwhile
	eq(bl.removeLabel(), "Remove added bus lines (1)")
	bl.removeAdded()
	pump()
	eq(kinds(), "sell,destroyLine")
	eq(W.sent[2].line, line)
	eq(W.maxInFlight, 1)
	eq(#bl.lines, 0)
	eq(#bl.vehicles, 0)
	ok(logText():find("remove_bus_lines summary vehicles=2 sold=1 lines=1 deleted=1 kept=0 gone=1 failed=0 wait: 0 still listed after", 1, true) ~= nil, logText())
end)

test("label and uiSignature follow the selections", function()
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 3, 3
	eq(bl.label(), "Add 4 bus lines to the nearest town")
	eq(bl.selectedBuses(), 10)
	eq(bl.uiSignature(), "1/3/3/0/0")
end)

test("Clear queue during a batch: the line in progress sends nothing more", function()
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 3   -- 10 buses
	bl.addBusLines()
	-- run until the first buy was answered (its SetLine is in flight), then clear the queue
	for _ = 1, 100000 do
		rt.tick()
		local p = table.remove(W.pending, 1)
		if p then
			local success, data, res = W.answer(p.cmd)
			p.cb(data, success, res)
			if p.cmd.kind == "buy" then break end
		end
	end
	rt.clearQueue()
	pump()
	local buys = 0
	for _, c in ipairs(W.sent) do if c.kind == "buy" then buys = buys + 1 end end
	eq(buys, 1)
	eq(#bl.vehicles, 1)
end)

-- Sixth run fixes (2026-10-10): depot first, line destroyed on a later failure, ring search, line names,
-- debounce, id guards --------------------------------------------------------------------------------

local function collideAll()
	api.engine.util.proposal = { makeProposalData = function() return { errorState = { critical = false, messages = { "Collision" } } } end }
end

test("depot first: no depot anywhere and every spot collides = the town is skipped with no stop, line or depot command", function()
	W.addTown(1, 0, 0)
	W.depots = {}
	W.best = -1
	collideAll()
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "")
	eq(#bl.lines, 0)
	local text = logText()
	ok(text:find("depot failed, nothing built (no road depot anywhere; rings: ", 1, true) ~= nil, text)
	-- rings in order, compact: 300-700 (4 edges of the town row), 700-1200 and 1200-2000 (none), then 0-300 (6)
	local r1 = text:find("300-700m inRing=4 edges=4 spots=96 tried=96 pre={Collision=96} sent=0 no spot left", 1, true)
	local r2 = text:find("700-1200m edges=0; 1200-2000m edges=0; 0-300m inRing=6 edges=6", 1, true)
	ok(r1 ~= nil and r2 ~= nil and r1 < r2, text)
	ok(text:find("summary towns=1 ok=0 failed=1 lines=0 (complete 0) buses=0 wastedStops=0", 1, true) ~= nil, text)
end)

test("depot first: the last-resort far depot is used only if findBestDepotForLine confirms one; else, no depot near stop 1 either, the line is destroyed with no bus bought", function()
	W.addTown(1, 0, 0)
	W.depots = { [900] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 9000, 0 } } }
	W.best = -1
	collideAll()
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line,destroyLine")
	eq(#bl.lines, 0)
	local text = logText()
	ok(text:find("depot=900 (nearest anywhere, 9000m;", 1, true) ~= nil, text)
	ok(text:find("no depot reaches the line (findBestDepotForLine=-1; depot 900: nearest anywhere, 9000m;", 1, true) ~= nil, text)
	ok(text:find("and none could be built near stop 1 (0-400m of stop 1 inRing=", 1, true) ~= nil, text)
	ok(text:find("destroyed=true, 2 stops wasted", 1, true) ~= nil, text)
	ok(text:find("wastedStops=2", 1, true) ~= nil, text)
	-- findBestDepotForLine finds one: the line is kept and the buses come from it
	clear_logs()
	W.sent = {}
	W.best = 900
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line,buy,setLine,buy,setLine")
	eq(#bl.lines, 1)
end)

test("a line whose first bus can't be bought is destroyed again and its stops logged as wasted", function()
	W.addTown(1, 0, 0)
	W.buyFails = true
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line,buy,destroyLine")
	eq(W.sent[5].line, W.nextId)   -- the line just created (the refused buy made no entity)
	eq(#bl.lines, 0)
	local text = logText()
	ok(text:find("buses=0/2 | buy 1/2 failed at depot 800 | line ", 1, true) ~= nil, text)
	ok(text:find("destroyed=true, 2 stops wasted", 1, true) ~= nil, text)
	ok(text:find("summary towns=1 ok=0 failed=1 lines=0 (complete 0) buses=0 wastedStops=2", 1, true) ~= nil, text)
	-- the second stop refused: one stop wasted, no line
	clear_logs()
	W.buyFails, W.sent = false, {}
	local stops = 0
	W.stopFails = function() stops = stops + 1 return stops > 1 end
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,stop")   -- stop1, stop2 variant A, variant B
	ok(logText():find("| 1 stop wasted", 1, true) ~= nil, logText())
	ok(logText():find("wastedStops=1", 1, true) ~= nil, logText())
end)

test("ringPick: only the ring, sampled evenly, fewest buildings first, then distance, at most max", function()
	local cands = {}
	for i = 1, 20 do cands[i] = edgeGeo(i, 0, 0, 40, 0, i * 50) end   -- dist 50 .. 1000
	local build = { [7] = 3, [8] = 0, [9] = 5, [10] = 0, [11] = 1, [12] = 2, [13] = 0 }
	local out, inRing = bl.ringPick(cands, 300, 700, 60, 4, function(g) return build[g.id] or 9 end)
	eq(inRing, 8)   -- 300 <= dist < 700: ids 6-13
	local ids = {}
	for i, g in ipairs(out) do ids[i] = g.id end
	eq(ids, { 8, 10, 13, 11 })
	-- sampling: 8 in the ring, sample 3 -> the 1st, 3rd and 6th by distance (ids 6, 8, 11), then ranked
	out = bl.ringPick(cands, 300, 700, 3, 15, function(g) return build[g.id] or 9 end)
	ids = {}
	for i, g in ipairs(out) do ids[i] = g.id end
	eq(ids, { 8, 11, 6 })
	eq(#bl.ringPick(cands, 2000, 3000, 60, 15, function() return 0 end), 0)
	eq(bl.DEPOT_RINGS[1], { 300.0, 700.0 })
	eq(bl.DEPOT_RINGS[4], { 0.0, 300.0 })
	eq(bl.DEPOT_GAPS, { 30.0, 45.0, 60.0, 80.0 })
	eq(bl.depotShort("edges=4 spots=72 tried=72 pre={Collision=72} sent=0 [] | no spot left"),
		"edges=4 spots=72 tried=72 pre={Collision=72} sent=0 no spot left")
end)

test("line names: SQST Bus 1, 2, 3 in order (not by 3), continuing after the highest existing SQST Bus N", function()
	eq(bl.nextLineNumber({}, 0), 1)
	eq(bl.nextLineNumber({ "SQST Bus 7", "Bus 99", "SQST Bus 3", "SQST Bus x" }, 0), 8)
	eq(bl.nextLineNumber({ "SQST Bus 2" }, 5), 6)
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 3, 1   -- 4 lines
	bl.addBusLines()
	pump()
	local names = {}
	for _, c in ipairs(W.sent) do if c.kind == "line" then names[#names + 1] = c.name end end
	eq(names, { "SQST Bus 1", "SQST Bus 2", "SQST Bus 3", "SQST Bus 4" })
	-- a fresh session (reload) with "SQST Bus 4" on the map continues at 5
	reset_modules()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	bl = ug_require "square_stress_test::/stress/gui/stress_buslines.tl"
	eq(#bl.lines, 0)   -- tracked ids are memory only: gone after a reload
	api.engine.system.lineSystem.getLinesForPlayer = function() return { 70 } end
	W.lineNames[70] = "SQST Bus 4"
	W.sent = {}
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	W.addTown(2, 5000, 0)
	api.gui.camera.getCameraData = function() return { x = 5000, y = 0 } end
	bl.addBusLines()
	pump()
	for _, c in ipairs(W.sent) do if c.kind == "line" then eq(c.name, "SQST Bus 5") end end
end)

test("debounce: clicks while a bus-lines batch or removal is queued or running are refused and logged", function()
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	bl.addBusLines()
	bl.addBusLines()
	bl.removeAdded()   -- nothing added yet: logs that, never queues
	rt.tick()
	bl.addBusLines()   -- running now
	local text = logText()
	local _, plans = text:gsub("bus_lines: 1 towns x 1 lines", "")
	eq(plans, 1)
	local _, refused = text:gsub("Busy: bus_lines: bus_lines is still queued or running", "")
	eq(refused, 3)
	pump()
	eq(#bl.lines, 1)
	clear_logs()
	bl.removeAdded()
	bl.addBusLines()
	bl.removeAdded()
	ok(logText():find("Busy: bus_lines: remove_bus_lines is still queued or running", 1, true) ~= nil, logText())
	ok(logText():find("Busy: remove_bus_lines: remove_bus_lines is still queued or running", 1, true) ~= nil, logText())
	pump()
	eq(#bl.lines, 0)
	-- idle again: a new batch is accepted
	clear_logs()
	bl.addBusLines()
	ok(logText():find("bus_lines: 1 towns x 1 lines", 1, true) ~= nil, logText())
	pump()
end)

test("guards: no SetLine on a bought id that isn't a vehicle; every bus and stop id is logged", function()
	W.addTown(1, 0, 0)
	W.buyKind = "stop"   -- the returned id is not a transport vehicle
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line,buy,destroyLine")
	local text = logText()
	ok(text:find("is not a vehicle of yours now; setLine skipped", 1, true) ~= nil, text)
	ok(text:find("bus_lines bought bus=" .. W.nextId .. " depot=800 for line=", 1, true) ~= nil, text)
	ok(text:find("bus_lines:stop1 stop built: SQST Stop 1 edge=", 1, true) ~= nil, text)
	ok(text:find("stationGroup=", 1, true) ~= nil, text)
	-- another player's depot is never used
	W.buyKind = nil
	W.sent = {}
	clear_logs()
	W.depots = { [801] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 0, 50 } } }
	W.extraComp = function(e, ct) if e == 801 and ct == "PLAYER_OWNED" then return { player = 99 } end end
	eq(bl.nearestRoadDepot(0, 0, 2000), nil)
end)

test("remove: a tracked id that is no longer a vehicle is never sold; a line still listing vehicles after the wait is kept", function()
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	local v1, v2 = bl.vehicles[1], bl.vehicles[2]
	local line = bl.lines[1]
	W.kind[v1] = "stop"   -- the id now names something else (still exists)
	W.onLine[v1] = nil
	W.sellFails = true    -- v2 can't be sold: stays on the line
	bl.REMOVE_WAIT_MS = 50
	W.sent = {}
	clear_logs()
	bl.removeAdded()
	pump()
	eq(kinds(), "sell")
	eq(W.sent[1].vs, { v2 })
	local text = logText()
	ok(text:find("line " .. line .. " still lists 1 vehicles; not deleted", 1, true) ~= nil, text)
	ok(text:find("sold=0 lines=1 deleted=0 kept=1 gone=1 failed=1", 1, true) ~= nil, text)
	eq(bl.lines, { line })
	eq(bl.vehicles, { v2 })   -- not sold: still tracked
	-- the line was destroyed elsewhere meanwhile (no LINE component): never sent a destroy
	W.sellFails = false
	W.removed[line] = true
	W.sent = {}
	bl.removeAdded()
	pump()
	eq(kinds(), "sell")
	eq(#bl.lines, 0)
end)

test("remove waits for the sold buses to be gone before deleting the line", function()
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	-- the sell answers success, but the buses only disappear a few polls later
	local polls = 0
	local base = W.answer
	local pendingGone = {}
	W.answer = function(cmd)
		if cmd.kind == "sell" then
			for _, v in ipairs(cmd.vs) do pendingGone[#pendingGone + 1] = v end
			return true, {}, {}
		end
		if cmd.kind == "destroyLine" then
			for _, v in ipairs(pendingGone) do ok(W.removed[v], "bus " .. v .. " gone before the line is destroyed") end
		end
		return base(cmd)
	end
	local lv = api.engine.system.transportVehicleSystem.getLineVehicles
	api.engine.system.transportVehicleSystem.getLineVehicles = function(l)
		polls = polls + 1
		if polls == 4 then for _, v in ipairs(pendingGone) do W.removed[v] = true end end
		return lv(l)
	end
	W.sent = {}
	clear_logs()
	bl.removeAdded()
	pump()
	eq(kinds(), "sell,sell,destroyLine")
	ok(polls >= 4, "polled " .. polls)
	ok(logText():find("deleted=1 kept=0 gone=0 failed=0 wait: 0 still listed", 1, true) ~= nil, logText())
end)

test("stop edges: never next to our earlier stops (across batches) or our depot entrance; edges with traffic come last", function()
	W.addTown(1, 0, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	-- edge 105 (mid 50) and 106 (mid 150) carry moving persons: the first line avoids them
	W.moving[105] = { 1 }
	W.moving[106] = { 2, 3 }
	bl.addBusLines()
	pump()
	local first = {}
	for _, c in ipairs(W.sent) do
		if c.kind == "build" and c.proposal.streetProposal.edgeObjectsToAdd then first[#first + 1] = c.proposal.streetProposal.edgesToRemove[1] end
	end
	for _, e in ipairs(first) do ok(e ~= 105 and e ~= 106, "busy edge used: " .. e) end
	eq(#bl.avoidPoints, 2)
	-- a second batch: no stop within 100 m of the first batch's stops
	W.sent = {}
	bl.addBusLines()
	pump()
	for _, c in ipairs(W.sent) do
		if c.kind == "build" and c.proposal.streetProposal.edgeObjectsToAdd then
			local e = c.proposal.streetProposal.edgesToRemove[1]
			for _, f in ipairs(first) do ok(math.abs(W.edges[e].x0 - W.edges[f].x0) >= 100, "stop next to an earlier one: " .. e) end
		end
	end
end)

---------------------------------------------------------------------------
-- Route lines (Junction / Crossing test Traffic = Bus lines)

test("route lines: a stop in each town, one line between them, the buses; one command in flight", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	bl.ui.buses = 1
	local n = bl.addRouteLines("bus_lines_junction_test", "Junction test", {
		{ a = { id = 1, x = 0, y = 0 }, b = { id = 2, x = 5000, y = 0 }, label = "Cell A1 Grid A1 -> Grid B2" },
	})
	eq(n, 1)
	pump()
	eq(W.maxInFlight, 1)
	eq(kinds(), "stop,stop,line,buy,setLine,buy,setLine")
	local s1, s2 = W.sent[1].proposal.streetProposal.edgesToRemove[1], W.sent[2].proposal.streetProposal.edgesToRemove[1]
	eq(W.edges[s1].town, 1)
	eq(W.edges[s2].town, 2)
	eq(#bl.lines, 1)
	eq(#bl.vehicles, 2)
	local text = logText()
	ok(text:find("[SQST] bus_lines_junction_test: 1 bus lines between Junction test towns x 2 buses", 1, true) ~= nil, text)
	ok(text:find("bus_lines_junction_test town Cell A1 Grid A1 -> Grid B2 (1): 1 lines ok", 1, true) ~= nil, text)
	ok(text:find("bus_lines_junction_test summary towns=1 ok=1 failed=0 lines=1", 1, true) ~= nil, text)
	-- Remove added bus lines takes them too
	bl.removeAdded()
	pump()
	eq(#bl.lines, 0)
end)

test("route lines: a batch stopped by a low balance says so in a dialog; moneyWarning only without Keep balance", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	W.balance = -92.1e6
	local n = bl.addRouteLines("bus_lines_showcase", "Showcase", {
		{ a = { id = 1, x = 0, y = 0 }, b = { id = 2, x = 5000, y = 0 }, label = "Showcase Grid S1 -> Grid S2" },
	})
	eq(n, 1)
	pump()
	eq(#W.sent, 0)
	eq(#rt.warnings, 1)
	eq(rt.warnings[1].title, "Showcase bus lines")
	local body = rt.warnings[1].body
	ok(body:find("Bus lines not added: the balance -92.1M is below 1M.", 1, true), body)
	ok(body:find("Tick Keep balance (Game tab) or add money, then build the Showcase again", 1, true), body)
	ok(bl.moneyWarning():find("Keep balance (Game tab) is off", 1, true))
	rt.keepBalance = true
	eq(bl.moneyWarning(), nil)
	rt.keepBalance = false
	-- Auto bus lines: the same dialog, its own re-run
	rt.warnings = {}
	bl.addBusLines()
	pump()
	eq(#rt.warnings, 1)
	ok(rt.warnings[1].body:find("then press the button again.", 1, true), rt.warnings[1].body)
end)

test("route lines: two routes from one town use different stop edges; bad routes are left out", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	W.addTown(3, 0, 5000)
	bl.ui.buses = 1
	local t1, t2, t3 = { id = 1, x = 0, y = 0 }, { id = 2, x = 5000, y = 0 }, { id = 3, x = 0, y = 5000 }
	eq(bl.addRouteLines("bus_lines_crossing_test", "Crossing test", { { a = t1, b = t1 }, { a = t1 }, {} }), 0, "nothing valid")
	eq(#rt.queue.jobs, 0)
	eq(bl.addRouteLines("bus_lines_crossing_test", "Crossing test", { { a = t1, b = t2 }, { a = t1, b = t3 } }), 2)
	pump()
	eq(#bl.lines, 2)
	local seen = {}
	for _, c in ipairs(W.sent) do
		if c.kind == "build" and c.proposal.streetProposal.edgeObjectsToAdd then
			local e = c.proposal.streetProposal.edgesToRemove[1]
			ok(not seen[e], "edge used twice: " .. e)
			seen[e] = true
		end
	end
end)

test("route lines: refused while a bus-lines job is queued or running (no stacking)", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	eq(bl.addRouteLines("bus_lines_junction_test", "Junction test", { { a = { id = 1, x = 0, y = 0 }, b = { id = 2, x = 5000, y = 0 } } }), 0)
	ok(logText():find("Busy: bus_lines_junction_test: bus_lines is still queued or running; wait for it to finish.", 1, true) ~= nil, logText())
	pump()
	eq(#bl.lines, 1)
end)

test("route lines: streets removed while the job is queued or running (Remove all roads): fails cleanly, no error", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	W.addTown(3, 0, 5000)
	bl.ui.buses = 1
	local t1, t2, t3 = { id = 1, x = 0, y = 0 }, { id = 2, x = 5000, y = 0 }, { id = 3, x = 0, y = 5000 }
	eq(bl.addRouteLines("bus_lines_junction_test", "Junction test", { { a = t1, b = t2 }, { a = t1, b = t3 } }), 2)
	-- town 2's streets go before the first line starts
	for e, ed in pairs(W.edges) do
		if ed.town == 2 then W.edges[e] = nil W.removed[e] = true end
	end
	-- the second route's stop 2 edge goes after its stop 1 was placed
	W.stopFails = function(e)
		if W.edges[e] and W.edges[e].town == 1 and #bl.lines == 0 then
			for e2, ed in pairs(W.edges) do
				if ed.town == 3 then W.edges[e2] = nil W.removed[e2] = true end
			end
		end
		return false
	end
	pump()
	local text = logText()
	ok(text:find("no free street edge in one of the towns", 1, true) ~= nil, text)
	ok(text:find("bus_lines_junction_test summary towns=2 ok=0 failed=2 lines=0", 1, true) ~= nil, text)
	ok(text:find("error:", 1, true) == nil, text)
	eq(#bl.lines, 0)
end)

---------------------------------------------------------------------------
-- Showcase in-game failures (2026-10-12, seed 204313): depots of another road network, an unconnected
-- depot at the map edge, buses stuck in a depot

--- buildDepot's world for one edge (50: 0,0 -> 100,0): every built depot gets the next id (811, 812,
--- ...) and construction (701, 702, ...) with its free entrance node; connect(n) answers the n-th
--- connection; removals are recorded.
local function depotWorld(connect)
	W.edges[50] = { node0 = 500, node1 = 501, objects = {}, x0 = 0, y = 0 }
	W.nodes[500], W.nodes[501] = { x = 0, y = 0 }, { x = 100, y = 0 }
	W.depots = {}
	api.engine.util.proposal = { makeProposalData = function() return { errorState = { critical = false, messages = {} } } end }
	local node2edges = {}
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return node2edges end }
	local built, connects, removed = 0, 0, {}
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d > 810 and d - 110 or -1 end
	W.extraComp = function(e, ct)
		if e > 700 and e < 710 and ct == "CONSTRUCTION" and not removed[e] then
			return { frozenNodes = {}, frozenEdges = { e * 10 }, transf = { [13] = 50, [14] = 65, [15] = 0 } }
		end
		if e > 7000 and e < 7100 and ct == "BASE_EDGE" then return { node0 = e + 1, node1 = e + 2 } end
		if e > 7000 and e < 7100 and ct == "BASE_NODE" then return { position = { x = 50, y = 30, z = 0 } } end
	end
	W.answer = function(cmd)
		local p = cmd.proposal
		if p.constructionsToRemove then
			for _, c in ipairs(p.constructionsToRemove) do
				removed[c] = true
				W.depots[c + 110] = nil
			end
			return true, {}, {}
		end
		if p.constructionsToAdd then
			built = built + 1
			W.depots[810 + built] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			node2edges[(700 + built) * 10 + 1] = { 1 }
			return true, {}, {}
		end
		connects = connects + 1
		local ok_ = connect(connects)
		if ok_ then node2edges[(700 + built) * 10 + 1] = { 1, 2 } end
		return ok_, ok_ and {} or { resultProposalData = { errorState = { critical = true, messages = { "Construction Not Possible" } } } }, {}
	end
	return removed
end

test("buildDepot: a depot whose connection is refused is removed again and the next spot tried", function()
	local removed = depotWorld(function(n) return n >= 2 end)
	local result
	bl.buildDepot("dep", { edgeGeo(50, 0, 0, 100, 0) }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	ok(result[1], result[2])
	eq(result[3], 812)
	eq(kinds(), "depot,street,street,depot,street")   -- build, refused connect, removal, build, connect
	ok(removed[701], "the unconnected depot's construction removed")
	eq(bl.depots, { 812 })
	ok(result[2]:find("not connected (", 1, true) and result[2]:find("Construction Not Possible", 1, true), result[2])
	ok(result[2]:find("depot 811 removed=true", 1, true), result[2])
	-- every connection refused: nothing is left standing
	W.sent = {}
	bl.depots = {}
	removed = depotWorld(function() return false end)
	bl.buildDepot("dep2", { edgeGeo(50, 0, 0, 100, 0) }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	eq(result[1], false)
	eq(#bl.depots, 0)
	local n = 0
	for _ in pairs(removed) do n = n + 1 end
	eq(n, bl.DEPOT_MAX_SENDS, "each of the depots built is removed again")
end)

test("buildDepot: spots within MAP_MARGIN of the map edge are left out", function()
	depotWorld(function() return true end)
	-- the map's lower edge 450 m below the street: spots south of it (building origin at y = -65 ...) are out
	api.engine.terrain.getBoundingBox = function() return { min = { x = -8000, y = -450 }, max = { x = 8000, y = 8000 } } end
	ok(not bl.insideMap({ 0, -60 }, bl.MAP_MARGIN))
	ok(bl.insideMap({ 0, -40 }, bl.MAP_MARGIN))
	local result
	bl.buildDepot("dep", { edgeGeo(50, 0, 0, 100, 0) }, 0, 0, function(ok_, details) result = { ok_, details } end)
	pump()
	ok(result[1], result[2])
	ok(result[2]:find("spots=12 tried=1 pre={ok=1} sent=1 outside=12 [e50 t=0.50 L30", 1, true), result[2])
	-- no box readable: nothing left out
	api.engine.terrain.getBoundingBox = nil
	ok(bl.insideMap({ 0, -1e9 }, bl.MAP_MARGIN))
end)

test("buses: a bus whose SetLine fails is sold again (never left in the depot)", function()
	W.addTown(1, 0, 0)
	local base = W.answer
	W.answer = function(cmd)
		if cmd.kind == "setLine" then return false, {}, {} end
		return base(cmd)
	end
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line,buy,setLine,sell,destroyLine")
	eq(#bl.vehicles, 0)
	ok(logText():find("setLine failed vehicle=", 1, true) and logText():find("; sold again=true", 1, true), logText())
end)

test("buses only from a depot that reaches the line: none -> a new depot near stop 1, asked again; still none -> no bus bought", function()
	W.addTown(1, 0, 0)
	W.depots = { [801] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 0, 50 } } }
	-- the town's depot does not reach the line; one built near stop 1 does
	local base = W.answer
	local builtD = false
	W.answer = function(cmd)
		if cmd.kind == "build" and cmd.proposal.constructionsToAdd then
			builtD = true
			W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			return true, {}, {}
		end
		return base(cmd)
	end
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return { [10] = { 60, 61 } } end }
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 811 and 700 or -1 end
	W.extraComp = function(e, ct)
		if e == 700 and ct == "CONSTRUCTION" then return { frozenNodes = { 11 }, frozenEdges = { 60 }, transf = { [13] = 0, [14] = -65, [15] = 0 } } end
		if e == 60 and ct == "BASE_EDGE" then return { node0 = 10, node1 = 11 } end
		if e == 10 and ct == "BASE_NODE" then return { position = { x = 0, y = -30, z = 0 } } end
	end
	api.engine.util.vehicle.findBestDepotForLine = function() return builtD and 811 or -1 end
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line,depot,buy,setLine,buy,setLine")
	for _, c in ipairs(W.sent) do if c.kind == "buy" then eq(c.depot, 811) end end
	local text = logText()
	ok(text:find("depot=801 (existing, 50m)", 1, true), text)
	ok(text:find("buses from depot=811 (findBestDepotForLine=811 after depot 811 built 0-400m of stop 1)", 1, true), text)
	-- no depot ever reaches the line: given up before any bus is bought
	clear_logs()
	W.sent = {}
	builtD = false
	api.engine.util.vehicle.findBestDepotForLine = function() return -1 end
	bl.addBusLines()
	pump()
	ok(not kinds():find("buy", 1, true), kinds())
	ok(logText():find("| no depot reaches the line (findBestDepotForLine=-1; depot 811", 1, true)
		and logText():find("destroyed=true, 2 stops wasted", 1, true), logText())
end)

test("buses only from a depot that reaches the line: a line that vanished meanwhile gets no depot built and no bus", function()
	W.addTown(1, 0, 0)
	W.depots = { [801] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 0, 50 } } }
	-- findBestDepotForLine finds nothing because the line is gone (removed elsewhere right after its creation)
	api.engine.util.vehicle.findBestDepotForLine = function(_c, _m, line)
		W.removed[line] = true
		return -1
	end
	bl.ui.towns, bl.ui.lines, bl.ui.buses = 1, 1, 1
	bl.addBusLines()
	pump()
	eq(kinds(), "stop,stop,line")
	local text = logText()
	ok(text:find("| line ", 1, true) and text:find(" is gone (findBestDepotForLine=-1) | line ", 1, true)
		and text:find("kept (no longer a line), 2 stops wasted", 1, true), text)
end)

test("route lines with a network: our depot of another network is not reused; a new one on the town's own streets", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	W.depots = { [900] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 0, 1177 } } }   -- ours, another network
	bl.depots = { 900 }
	bl.depotNet[900] = "line 2"
	local base = W.answer
	W.answer = function(cmd)
		if cmd.kind == "build" and cmd.proposal.constructionsToAdd then
			W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			return true, {}, {}
		end
		return base(cmd)
	end
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return { [10] = { 60, 61 } } end }
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 811 and 700 or -1 end
	W.extraComp = function(e, ct)
		if e == 700 and ct == "CONSTRUCTION" then return { frozenNodes = { 11 }, frozenEdges = { 60 }, transf = { [13] = 450, [14] = -65, [15] = 0 } } end
		if e == 60 and ct == "BASE_EDGE" then return { node0 = 10, node1 = 11 } end
		if e == 10 and ct == "BASE_NODE" then return { position = { x = 450, y = -30, z = 0 } } end
	end
	api.engine.util.vehicle.findBestDepotForLine = function() return W.depots[811] and 811 or -1 end
	bl.ui.buses = 1
	eq(bl.addRouteLines("bus_lines_showcase", "Showcase", {
		{ a = { id = 1, x = 0, y = 0 }, b = { id = 2, x = 5000, y = 0 }, label = "Showcase Grid S5 -> Grid S6", net = "group 1" },
	}), 1)
	pump()
	eq(kinds(), "depot,stop,stop,line,buy,setLine,buy,setLine")
	-- the new depot is on town 1's own streets and belongs to group 1 now
	local ce = W.sent[1].proposal.constructionsToAdd[1]
	ok(math.abs(ce.transf[4][1]) < 1000, "near town 1")
	eq(bl.depotNet[811], "group 1")
	local text = logText()
	ok(text:find("depot=811 (built in ring 300-700m)", 1, true), text)
	-- a second route of the same network reuses it; the existing player depots near the town are not taken
	clear_logs()
	W.sent = {}
	bl.addRouteLines("bus_lines_showcase", "Showcase", {
		{ a = { id = 1, x = 0, y = 0 }, b = { id = 2, x = 5000, y = 0 }, label = "Showcase Grid S5 -> Grid S7", net = "group 1" },
	})
	pump()
	eq(kinds(), "stop,stop,line,buy,setLine,buy,setLine")
	ok(logText():find("depot=811 (ours, ", 1, true) and logText():find("m, group 1)", 1, true), logText())
end)

-- Showcase v2 in-game failures (2026-10-12, seed 488838): every depot stub into the grid refused
-- "Construction Not Possible", the one depot that connected sat by a junction's ramp with a dead-end gate,
-- and the batch stopped after its first 3 of 40 routes

test("busEdgeReject: highway, one-way, not a town street, outside the town grid, inside a junction zone", function()
	local town = { id = 1, x = 0, y = 0, half = 300 }
	local p0, p1 = { -50, 100 }, { 50, 100 }
	local large = "::/infrastructure/street/town/town_new_large.street_template"
	eq(logic.busEdgeReject(large, p0, p1, town, nil, true), nil)
	eq(logic.busEdgeReject("::/infrastructure/street/highway/highway_new_medium.street_template", p0, p1, town, nil, true), "highway")
	eq(logic.busEdgeReject("::/infrastructure/street/town/town_new_one_way_small.street_template", p0, p1, nil, nil, false), "oneway")
	eq(logic.busEdgeReject("::/infrastructure/street/country/country_new_large.street_template", p0, p1, town, nil, true), "not_town")
	eq(logic.busEdgeReject("::/infrastructure/street/country/country_new_large.street_template", p0, p1, nil, nil, false), nil,
		"Auto bus lines: country roads are fine")
	-- the grid's outer street (x = 300) is in, a link road leaving it is not
	eq(logic.busEdgeReject(large, { 300, -50 }, { 300, 50 }, town, nil, true), nil)
	eq(logic.busEdgeReject(large, { 300, 0 }, { 400, 0 }, town, nil, true), "outside_town")
	eq(logic.busEdgeReject(large, { 300, 0 }, { 400, 0 }, { id = 1, x = 0, y = 0 }, nil, true), nil, "no grid: no square")
	-- a zone of reach 150 m at 600,100 keeps edges within 250 m of its centre
	local zones = { { 600, 100, 150 } }
	eq(logic.busEdgeReject(large, { 300, 50 }, { 300, 150 }, town, zones, true), nil, "300 m away")
	eq(logic.busEdgeReject(large, { 300, 50 }, { 300, 150 }, town, { { 500, 100, 150 } }, true), "zone")
	eq(logic.busEdgeReject("", p0, p1, town, nil, true), nil, "unreadable template: only the geometry")
	eq(logic.gridHalfOfSize(1), 200)
	eq(logic.gridHalfOfSize(2), 300)
	eq(logic.gridHalfOfSize(nil), 200)
end)

test("depot connection: the stub is the small town street and the gate node gets its two-way lane connections", function()
	local g = edgeGeo(50, 0, 0, 100, 0)
	W.edges[50] = { node0 = 500, node1 = 501, objects = {}, x0 = 0, y = 0 }
	W.nodes[500], W.nodes[501] = { x = 0, y = 0 }, { x = 100, y = 0 }
	W.depots = {}
	local checked = {}
	api.engine.util.proposal = { makeProposalData = function(p)
		checked[#checked + 1] = p
		return { errorState = { critical = false, messages = {} } }
	end }
	api.type.LaneConnection = { new = function() return {} end }
	api.res.streetTemplateRep = {
		find = function(path) return path end,
		get = function(path) return { laneConfigs = { "lanes of " .. path }, streetStyle = "style of " .. path } end,
	}
	local node2edges = { [11] = { 60 } }
	local gateConns = {}
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return node2edges end }
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 811 and 700 or -1 end
	W.extraComp = function(e, ct)
		if e == 700 and ct == "CONSTRUCTION" then
			return { frozenNodes = { 10 }, frozenEdges = { 60 }, transf = { [13] = 50, [14] = 65, [15] = 0 } }
		end
		if e == 60 and ct == "BASE_EDGE" then return { node0 = 11, node1 = 10 } end
		if e == 10 and ct == "BASE_NODE" then return { position = { x = 50, y = 44.7, z = 0 } } end
		if e == 11 and ct == "BASE_NODE" then return { position = { x = 50, y = 30, z = 0 } } end
		if e == 11 and ct == "BASE_NODE_CONFIG" then return { laneConnections = gateConns, crosswalks = { 60 } } end
	end
	W.answer = function(cmd)
		if cmd.proposal.constructionsToAdd then
			W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			return true, {}, {}
		end
		node2edges[11] = { 60, 61 }
		gateConns = { 1, 2 }
		return true, {}, {}
	end
	local result
	bl.buildDepot("dep", { g }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	ok(result[1], result[2])
	local sp = W.sent[2].proposal.streetProposal
	local stub = sp.edgesToAdd[3]
	eq(stub.entity, -3)
	eq(stub.comp.node1, 11)
	eq(stub.comp.roadTemplate, "::/infrastructure/street/town/town_new_small.street_template")
	eq(stub.comp.laneConfigs, { "lanes of ::/infrastructure/street/town/town_new_small.street_template" })
	-- the gate: its old config removed and a full one added (entrance edge 60 <-> stub -3, lane 1 -> 2)
	eq(sp.nodeConfigsToRemove, { 11 })
	local entry
	for _, e in ipairs(sp.nodeConfigsToAdd) do if e.entity == 11 then entry = e end end
	ok(entry ~= nil, "gate config")
	eq(entry.comp.crosswalks, { 60 })
	eq(entry.comp.laneConnections, {
		{ segment0 = 60, lane0 = 1, segment1 = -3, lane1 = 2, withRoad = true, withTram = false },
		{ segment0 = -3, lane0 = 1, segment1 = 60, lane1 = 2, withRoad = true, withTram = false },
	})
	-- the new split node -4 gets a config too (a new node without one can crash the simulation):
	-- the two-way pattern over its 3 segments, a.1 -> b.2 for each ordered pair
	local split
	for _, e in ipairs(sp.nodeConfigsToAdd) do if e.entity == -4 then split = e end end
	ok(split ~= nil, "config for the split node -4")
	eq(#split.comp.laneConnections, 6)
	for _, lc in ipairs(split.comp.laneConnections) do
		ok(lc.segment0 ~= lc.segment1 and lc.lane0 == 1 and lc.lane1 == 2, "a.1 -> b.2")
	end
	-- the pre-check's stand-in -5 (a new 1-edge node) gets an empty config
	local stand
	for _, pp in ipairs(checked) do
		for _, e in ipairs(pp.streetProposal.nodeConfigsToAdd or {}) do if e.entity == -5 then stand = e end end
	end
	ok(stand ~= nil and #stand.comp.laneConnections == 0, "empty config for the stand-in -5")
	-- the split edge's end nodes 500 / 501 have no config in this world: each gets one, add only
	local ends = {}
	for _, e in ipairs(sp.nodeConfigsToAdd) do if e.entity == 500 or e.entity == 501 then ends[#ends + 1] = e.entity end end
	table.sort(ends)
	eq(ends, { 500, 501 })
	local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
	eq(nc.problems(sp, function() return 4 end), {})
	ok(result[2]:find("laneConns 0->2 (entrance edge 60, stub ::/infrastructure/street/town/town_new_small.street_template) connected=true", 1, true), result[2])
	-- the pre-check's stand-in stub is the same small street, and the old era takes town_old_small
	api.engine.util.getYear = function() return 1900 end
	W.sent = {}
	bl.depots = {}
	node2edges[11] = { 60 }
	gateConns = {}
	W.depots = {}
	bl.buildDepot("dep2", { g }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	eq(W.sent[2].proposal.streetProposal.edgesToAdd[3].comp.roadTemplate, "::/infrastructure/street/town/town_old_small.street_template")
end)

test("depot connection: never a stub onto a highway or a one-way street", function()
	local g = edgeGeo(50, 0, 0, 100, 0)
	g.template = "::/infrastructure/street/town/town_new_one_way_small.street_template"
	local h = edgeGeo(51, 0, 50, 100, 50)
	h.template = "::/infrastructure/street/highway/highway_new_medium.street_template"
	local result
	bl.buildDepot("dep", { g, h }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	eq(result[1], false)
	ok(result[2]:find("no depot spot", 1, true), result[2])
	eq(#W.sent, 0)
end)

test("depot connection: a gate left with no lane connections (dead end) counts as not connected; the depot is removed", function()
	local g = edgeGeo(50, 0, 0, 100, 0)
	W.edges[50] = { node0 = 500, node1 = 501, objects = {}, x0 = 0, y = 0 }
	W.nodes[500], W.nodes[501] = { x = 0, y = 0 }, { x = 100, y = 0 }
	W.depots = {}
	api.engine.util.proposal = { makeProposalData = function() return { errorState = { critical = false, messages = {} } } end }
	local node2edges = { [11] = { 60 } }
	api.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return node2edges end }
	api.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) return d == 811 and 700 or -1 end
	local removed = false
	W.extraComp = function(e, ct)
		if e == 700 and ct == "CONSTRUCTION" and not removed then
			return { frozenNodes = { 10 }, frozenEdges = { 60 }, transf = { [13] = 50, [14] = 65, [15] = 0 } }
		end
		if e == 60 and ct == "BASE_EDGE" then return { node0 = 11, node1 = 10 } end
		if e == 10 and ct == "BASE_NODE" then return { position = { x = 50, y = 44.7, z = 0 } } end
		if e == 11 and ct == "BASE_NODE" then return { position = { x = 50, y = 30, z = 0 } } end
		if e == 11 and ct == "BASE_NODE_CONFIG" then return { laneConnections = {}, crosswalks = {} } end
	end
	W.answer = function(cmd)
		local p = cmd.proposal
		if p.constructionsToRemove then removed = true W.depots[811] = nil node2edges[11] = { 60 } return true, {}, {} end
		if p.constructionsToAdd then
			removed = false
			W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
			return true, {}, {}
		end
		node2edges[11] = { 60, 61 }   -- joined, but the config stays empty
		return true, {}, {}
	end
	local result
	bl.buildDepot("dep", { g }, 0, 0, function(ok_, details, depot) result = { ok_, details, depot } end)
	pump()
	eq(result[1], false, result[2])
	eq(#bl.depots, 0)
	ok(result[2]:find("laneConns 0->0", 1, true) and result[2]:find("connected=false", 1, true), result[2])
	ok(result[2]:find("depot 811 removed=true", 1, true), result[2])
	-- gateText reads a depot's gate for the log
	W.depots[811] = { carrier = 0, inNodes = { {} }, outNodes = {} }
	removed = false
	eq(bl.gateText(811), "gate node=11 streetEdges=1 laneConns=0")
	eq(bl.gateText(999), "gate ?(no construction)")
end)

test("route lines: stops and depots only on the route's own town grid, never in a junction zone or on a highway", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	-- town 1's row runs x -500..500: with a 300 m grid only the edges within x -315..315 are its streets
	for k = 0, 9 do W.edges[100 + k].template = "::/infrastructure/street/town/town_new_large.street_template" end
	W.edges[105].template = "::/infrastructure/street/highway/highway_new_medium.street_template"   -- x 0..100
	bl.ui.buses = 1
	-- no depot of the network yet: the depot search keeps to the same streets
	eq(bl.addRouteLines("bus_lines_showcase", "Showcase", {
		{ a = { id = 1, x = 0, y = 0, half = 300 }, b = { id = 2, x = 5000, y = 0 }, label = "Showcase Grid S1 -> Grid S2",
			net = "group 1", zones = { { -250, 0, 50 } } },
	}), 1)
	pump()
	local depotText = logText()
	ok(depotText:find("rings: 300-700m edges=0 rejected={highway=1,outside_town=4,zone=2}", 1, true), depotText)
	for _, c in ipairs(W.sent) do
		if c.kind == "build" and c.proposal.constructionsToAdd then
			local x = c.proposal.constructionsToAdd[1].transf[4][1]
			ok(x == -50 or x == 150 or x == 250, "depot beside edges 104/106/107 (middles -50, 150, 250): x=" .. x)
		end
	end
	-- with a depot of the network: the stops
	W.sent = {}
	clear_logs()
	W.depots[900] = { carrier = 0, inNodes = { {} }, outNodes = {}, pos = { 250, -100 } }
	bl.depots = { 900 }
	bl.depotNet[900] = "group 1"
	eq(bl.addRouteLines("bus_lines_showcase", "Showcase", {
		{ a = { id = 1, x = 0, y = 0, half = 300 }, b = { id = 2, x = 5000, y = 0 }, label = "Showcase Grid S1 -> Grid S2",
			net = "group 1", zones = { { -250, 0, 50 } } },
	}), 1)
	pump()
	-- the first stop (and the depot search) stays on town 1's grid: not 105 (highway), not 102/103 (zone at x -250
	-- r 50+100: edges x -300..-100), not 100/101/108/109 (outside the grid)
	local stops = {}
	for _, c in ipairs(W.sent) do
		if c.kind == "build" and c.proposal.streetProposal and c.proposal.streetProposal.edgeObjectsToAdd then
			stops[#stops + 1] = c.proposal.streetProposal.edgesToRemove[1]
		end
	end
	ok(#stops >= 1, logText())
	ok(stops[1] == 104 or stops[1] == 106 or stops[1] == 107, "stop 1 on " .. tostring(stops[1]))
	ok(logText():find("depot=900 (ours, ", 1, true), logText())
end)

test("route lines: the batch goes on past failed routes and stops only after MAX_ROUTE_FAILS", function()
	W.addTown(1, 0, 0)
	W.addTown(2, 5000, 0)
	W.stopFails = function() return true end   -- every stop refused: every route fails
	bl.ui.buses = 1
	local routes = {}
	for k = 1, bl.MAX_ROUTE_FAILS + 3 do
		routes[k] = { a = { id = 1, x = 0, y = 0 }, b = { id = 2, x = 5000, y = 0 }, label = "Showcase route " .. k, net = "group 1" }
	end
	eq(bl.addRouteLines("bus_lines_showcase", "Showcase", routes), #routes)
	pump()
	local text = logText()
	ok(text:find("(3/10 failed routes, going on)", 1, true), text)
	ok(text:find("bus_lines_showcase stopped after 10 failed routes", 1, true), text)
	ok(text:find("summary towns=13 ok=0 failed=10", 1, true), text)
	ok(not text:find("failed towns in a row", 1, true), text)
end)
